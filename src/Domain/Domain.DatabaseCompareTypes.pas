unit Domain.DatabaseCompareTypes;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Domain.DatabaseTypes;

type
  TCompareObjectCategory = (
    cocGenerator,
    cocTable,
    cocColumn,
    cocPrimaryKey,
    cocForeignKey,
    cocIndex,
    cocView,
    cocProcedure,
    cocTrigger
  );

  TCompareDiffStatus = (
    cdsMissingInTarget,
    cdsDifferent,
    cdsExtraInTarget
  );

  TCompareOptions = record
    CompareTablesAndColumns: Boolean;
    CompareConstraints: Boolean;
    CompareIndexes: Boolean;
    CompareGenerators: Boolean;
    CompareViews: Boolean;
    CompareProcedures: Boolean;
    CompareTriggers: Boolean;
    IncludeDropsForExtraObjects: Boolean;
    IgnoreWhitespaceInCode: Boolean;
  end;

  TCompareDiffItem = record
    Selected: Boolean;
    Category: TCompareObjectCategory;
    ObjectName: string;
    ParentName: string;
    Status: TCompareDiffStatus;
    Summary: string;
    SourceDDL: string;
    TargetDDL: string;
    UpdateSQL: string;
    NeedsSetTerm: Boolean;
  end;
  TCompareDiffItemArray = array of TCompareDiffItem;

  { Resultado completo da comparação entre duas bases de dados }
  TCompareResult = class
  public
    DatabaseType: TDatabaseType;
    SourceProfileName: string;
    TargetProfileName: string;
    ElapsedMs: Int64;
    Items: TCompareDiffItemArray;
    Warnings: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AddItem(const AItem: TCompareDiffItem);
    function SelectedCount: Integer;
    function BuildCombinedScript(const ASelectedOnly: Boolean = True): string;
  end;

function DefaultCompareOptions: TCompareOptions;
function CompareObjectCategoryToStr(const ACat: TCompareObjectCategory): string;
function CompareDiffStatusToStr(const AStatus: TCompareDiffStatus): string;

implementation

function DefaultCompareOptions: TCompareOptions;
begin
  Result.CompareTablesAndColumns := True;
  Result.CompareConstraints := True;
  Result.CompareIndexes := True;
  Result.CompareGenerators := True;
  Result.CompareViews := True;
  Result.CompareProcedures := True;
  Result.CompareTriggers := True;
  Result.IncludeDropsForExtraObjects := False;
  Result.IgnoreWhitespaceInCode := True;
end;

function CompareObjectCategoryToStr(const ACat: TCompareObjectCategory): string;
begin
  case ACat of
    cocGenerator: Result := 'Generator / Seq';
    cocTable: Result := 'Tabela';
    cocColumn: Result := 'Campo';
    cocPrimaryKey: Result := 'Primary Key';
    cocForeignKey: Result := 'Foreign Key';
    cocIndex: Result := 'Índice';
    cocView: Result := 'View';
    cocProcedure: Result := 'Procedure';
    cocTrigger: Result := 'Trigger';
  else
    Result := 'Objeto';
  end;
end;

function CompareDiffStatusToStr(const AStatus: TCompareDiffStatus): string;
begin
  case AStatus of
    cdsMissingInTarget: Result := 'Falta no Destino';
    cdsDifferent: Result := 'Diferente';
    cdsExtraInTarget: Result := 'Extra no Destino';
  else
    Result := '---';
  end;
end;

{ TCompareResult }

constructor TCompareResult.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
  Clear;
end;

destructor TCompareResult.Destroy;
begin
  Warnings.Free;
  inherited Destroy;
end;

procedure TCompareResult.Clear;
begin
  DatabaseType := dtFirebird;
  SourceProfileName := '';
  TargetProfileName := '';
  ElapsedMs := 0;
  SetLength(Items, 0);
  if Warnings <> nil then
    Warnings.Clear;
end;

procedure TCompareResult.AddItem(const AItem: TCompareDiffItem);
var
  Idx: Integer;
begin
  Idx := Length(Items);
  SetLength(Items, Idx + 1);
  Items[Idx] := AItem;
end;

function TCompareResult.SelectedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Items) do
    if Items[I].Selected then
      Inc(Result);
end;

function TCompareResult.BuildCombinedScript(const ASelectedOnly: Boolean): string;
var
  SL: TStringList;
  I: Integer;
  Item: TCompareDiffItem;
  SqlBlock: string;
begin
  SL := TStringList.Create;
  try
    SL.Add(Format('-- Script de atualização gerado pelo Database Comparer (%s)',
      [DatabaseTypeToStr(DatabaseType)]));
    SL.Add(Format('-- Origem (Modelo): %s', [SourceProfileName]));
    SL.Add(Format('-- Destino (Alvo) : %s', [TargetProfileName]));
    SL.Add(Format('-- Gerado em      : %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
    SL.Add('');

    for I := 0 to High(Items) do
    begin
      Item := Items[I];
      if ASelectedOnly and (not Item.Selected) then
        Continue;
      SqlBlock := Trim(Item.UpdateSQL);
      if SqlBlock = '' then
        Continue;

      SL.Add(Format('-- [%s] %s (%s)', [
        CompareObjectCategoryToStr(Item.Category),
        Item.ObjectName,
        CompareDiffStatusToStr(Item.Status)
      ]));

      if (DatabaseType = dtFirebird) and Item.NeedsSetTerm then
      begin
        if (SqlBlock <> '') and (SqlBlock[Length(SqlBlock)] = ';') then
          SqlBlock := TrimRight(Copy(SqlBlock, 1, Length(SqlBlock) - 1));
        SL.Add('SET TERM ^ ;');
        SL.Add(SqlBlock + '^');
        SL.Add('SET TERM ; ^');
      end
      else
      begin
        if (SqlBlock <> '') and (SqlBlock[Length(SqlBlock)] <> ';') then
          SqlBlock := SqlBlock + ';';
        SL.Add(SqlBlock);
      end;
      SL.Add('');
    end;

    Result := TrimRight(SL.Text) + LineEnding;
  finally
    SL.Free;
  end;
end;

end.
