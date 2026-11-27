unit Presentation.SqlObjectLinkController;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, SynEdit, SynEditTypes, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Presentation.SqlCompletionController;

type
  TOpenDbObjectLinkEvent = procedure(
    const AProfile: TConnectionProfile;
    const AKind: TSchemaObjectKind;
    const AObjectName: string
  ) of object;

  { Controlador reutilizável de destaque e Ctrl+Clique em Tabelas, Views e Procedures no TSynEdit }
  TSqlObjectLinkController = class(TComponent)
  private
    FSynEdit: TSynEdit;
    FSynSQLSyn: TSynSQLSyn;
    FGetProfile: TGetCompletionProfileEvent;
    FExecMeta: TExecuteMetadataQueryEvent;
    FOnOpenObject: TOpenDbObjectLinkEvent;
    FLinkObjects: TStringList;
    FLoaded: Boolean;
    function FindObjectKind(const AName: string; out AKind: TSchemaObjectKind; out ACanonicalName: string): Boolean;
    procedure HandleMouseLink(Sender: TObject; X, Y: Integer; var AllowMouseLink: Boolean);
    procedure HandleClickLink(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    constructor Create(
      AOwner: TComponent;
      const ASynEdit: TSynEdit;
      const ASynSQLSyn: TSynSQLSyn;
      const AGetProfile: TGetCompletionProfileEvent;
      const AExecMeta: TExecuteMetadataQueryEvent;
      const AOnOpenObject: TOpenDbObjectLinkEvent
    ); reintroduce;
    destructor Destroy; override;
    procedure EnsureLoaded;
    procedure ClearCache;
    property OnOpenObject: TOpenDbObjectLinkEvent read FOnOpenObject write FOnOpenObject;
  end;

implementation

constructor TSqlObjectLinkController.Create(
  AOwner: TComponent;
  const ASynEdit: TSynEdit;
  const ASynSQLSyn: TSynSQLSyn;
  const AGetProfile: TGetCompletionProfileEvent;
  const AExecMeta: TExecuteMetadataQueryEvent;
  const AOnOpenObject: TOpenDbObjectLinkEvent
);
begin
  inherited Create(AOwner);
  FSynEdit := ASynEdit;
  FSynSQLSyn := ASynSQLSyn;
  FGetProfile := AGetProfile;
  FExecMeta := AExecMeta;
  FOnOpenObject := AOnOpenObject;
  FLoaded := False;

  FLinkObjects := TStringList.Create;
  FLinkObjects.Sorted := True;
  FLinkObjects.Duplicates := dupIgnore;
  FLinkObjects.CaseSensitive := False;

  if FSynSQLSyn <> nil then
  begin
    FSynSQLSyn.TableNameAttri.Foreground := RGBToColor(0, 102, 204);
    FSynSQLSyn.TableNameAttri.Style := [fsUnderline];
  end;

  if FSynEdit <> nil then
  begin
    FSynEdit.Options := FSynEdit.Options + [eoShowCtrlMouseLinks];
    FSynEdit.OnMouseLink := @HandleMouseLink;
    FSynEdit.OnClickLink := @HandleClickLink;
  end;
end;

destructor TSqlObjectLinkController.Destroy;
begin
  FreeAndNil(FLinkObjects);
  inherited Destroy;
end;

procedure TSqlObjectLinkController.ClearCache;
begin
  FLoaded := False;
  if FLinkObjects <> nil then
    FLinkObjects.Clear;
  if FSynSQLSyn <> nil then
    FSynSQLSyn.TableNames.Clear;
end;

procedure TSqlObjectLinkController.EnsureLoaded;
var
  Profile: TConnectionProfile;
  SQL, ObjName: string;
  Res: TQueryResult;
  I, KindInt: Integer;
  Kind: TSchemaObjectKind;
begin
  if FLoaded or (FLinkObjects = nil) or (not Assigned(FGetProfile)) or (not Assigned(FExecMeta)) then
    Exit;

  Profile := FGetProfile();
  if Profile = nil then
    Exit;

  FLoaded := True;
  FLinkObjects.Clear;
  if FSynSQLSyn <> nil then
    FSynSQLSyn.TableNames.BeginUpdate;
  try
    if FSynSQLSyn <> nil then
      FSynSQLSyn.TableNames.Clear;

    if Profile.DatabaseType = dtPostgreSQL then
      SQL :=
        'SELECT c.relname AS obj_name, 0 AS obj_kind ' +
        'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
        'WHERE n.nspname = current_schema() AND c.relkind IN (''r'', ''p'') ' +
        'UNION ALL ' +
        'SELECT c.relname AS obj_name, 1 AS obj_kind ' +
        'FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ' +
        'WHERE n.nspname = current_schema() AND c.relkind = ''v'' ' +
        'UNION ALL ' +
        'SELECT p.proname AS obj_name, 2 AS obj_kind ' +
        'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
        'WHERE n.nspname = current_schema()'
    else if Profile.DatabaseType = dtMariaDB then
      SQL :=
        'SELECT table_name AS obj_name, CASE WHEN table_type = ''VIEW'' THEN 1 ELSE 0 END AS obj_kind ' +
        'FROM information_schema.tables WHERE table_schema = DATABASE() ' +
        'UNION ALL ' +
        'SELECT routine_name AS obj_name, 2 AS obj_kind ' +
        'FROM information_schema.routines WHERE routine_schema = DATABASE()'
    else
      SQL :=
        'SELECT TRIM(RDB$RELATION_NAME) AS OBJ_NAME, 0 AS OBJ_KIND ' +
        'FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NULL ' +
        'UNION ALL ' +
        'SELECT TRIM(RDB$RELATION_NAME) AS OBJ_NAME, 1 AS OBJ_KIND ' +
        'FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NOT NULL ' +
        'UNION ALL ' +
        'SELECT TRIM(RDB$PROCEDURE_NAME) AS OBJ_NAME, 2 AS OBJ_KIND ' +
        'FROM RDB$PROCEDURES WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0';

    Res := FExecMeta(SQL);
    if Res = nil then
      Exit;
    try
      if Res.Success then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          ObjName := Trim(Res.GetRow(I)[0].AsText);
          if ObjName = '' then
            Continue;
          KindInt := StrToIntDef(Trim(Res.GetRow(I)[1].AsText), 0);
          case KindInt of
            1: Kind := sokViews;
            2: Kind := sokProcedures;
          else
            Kind := sokTables;
          end;
          FLinkObjects.AddObject(ObjName, TObject(PtrInt(Ord(Kind))));
          if FSynSQLSyn <> nil then
            FSynSQLSyn.TableNames.Add(ObjName);
        end;
      end;
    finally
      Res.Free;
    end;
  finally
    if FSynSQLSyn <> nil then
      FSynSQLSyn.TableNames.EndUpdate;
  end;
  if FSynEdit <> nil then
    FSynEdit.Invalidate;
end;

function TSqlObjectLinkController.FindObjectKind(
  const AName: string;
  out AKind: TSchemaObjectKind;
  out ACanonicalName: string
): Boolean;
var
  Idx: Integer;
  Clean: string;
begin
  Result := False;
  ACanonicalName := '';
  if (FLinkObjects = nil) or (Trim(AName) = '') then
    Exit;
  Clean := Trim(AName);
  if (Length(Clean) >= 2) and (Clean[1] = '"') and (Clean[Length(Clean)] = '"') then
    Clean := Copy(Clean, 2, Length(Clean) - 2);
  Idx := FLinkObjects.IndexOf(Clean);
  if Idx >= 0 then
  begin
    AKind := TSchemaObjectKind(PtrInt(FLinkObjects.Objects[Idx]));
    ACanonicalName := FLinkObjects[Idx];
    Result := True;
  end;
end;

procedure TSqlObjectLinkController.HandleMouseLink(Sender: TObject; X, Y: Integer;
  var AllowMouseLink: Boolean);
var
  Word, CanonicalName: string;
  Kind: TSchemaObjectKind;
begin
  AllowMouseLink := False;
  if FSynEdit = nil then
    Exit;
  if not FLoaded then
    EnsureLoaded;
  Word := FSynEdit.GetWordAtRowCol(Point(X, Y));
  if Word <> '' then
    AllowMouseLink := FindObjectKind(Word, Kind, CanonicalName);
end;

procedure TSqlObjectLinkController.HandleClickLink(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Pt: TPoint;
  Word, CanonicalName: string;
  Kind: TSchemaObjectKind;
  Profile: TConnectionProfile;
begin
  if (Button <> mbLeft) or (FSynEdit = nil) then
    Exit;
  Pt := FSynEdit.PixelsToRowColumn(Point(X, Y));
  Word := FSynEdit.GetWordAtRowCol(Pt);
  if (Word <> '') and FindObjectKind(Word, Kind, CanonicalName) and Assigned(FGetProfile) then
  begin
    Profile := FGetProfile();
    if (Profile <> nil) and Assigned(FOnOpenObject) then
      FOnOpenObject(Profile, Kind, CanonicalName);
  end;
end;

end.
