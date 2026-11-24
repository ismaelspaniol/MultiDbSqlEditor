unit Application.ManageTableStructureUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Domain.TableStructureTypes,
  Application.ManageDatabaseObjectsUseCase;

type
  { Caso de uso para visualizar e editar campos, índices e dependências de uma tabela }
  TManageTableStructureUseCase = class
  private
    FFactory: IDatabaseProviderFactory;
    function ExecuteQuery(const ASession: IDatabaseSession; const ASQL: string): TQueryResult;
    function ExecuteDDLStatements(
      const AProfile: TConnectionProfile;
      const AStatements: TStrings;
      out AMessage: string
    ): Boolean;
    procedure LoadFirebirdStructure(
      const ASession: IDatabaseSession;
      const ATableName: string;
      const AStructure: TTableStructure
    );
    procedure LoadPostgresStructure(
      const ASession: IDatabaseSession;
      const ATableName: string;
      const AStructure: TTableStructure
    );
    procedure LoadMariaDbStructure(
      const ASession: IDatabaseSession;
      const ATableName: string;
      const AStructure: TTableStructure
    );
    procedure LoadFirebirdFieldDependencies(
      const ASession: IDatabaseSession;
      const ATableName, AFieldName: string;
      var ATarget: TTableDependencyInfoArray
    );
    procedure LoadPostgresFieldDependencies(
      const ASession: IDatabaseSession;
      const ATableName, AFieldName: string;
      var ATarget: TTableDependencyInfoArray
    );
  public
    constructor Create(const AFactory: IDatabaseProviderFactory);
    function LoadTableStructure(
      const AProfile: TConnectionProfile;
      const ATableName: string
    ): TTableStructure;
    function LoadTableDDL(
      const AProfile: TConnectionProfile;
      const ATableName: string;
      const AIncludeIndexes: Boolean = True
    ): string;
    function LoadFieldDependencies(
      const AProfile: TConnectionProfile;
      const ATableName, AFieldName: string
    ): TTableDependencyInfoArray;
    function AddColumn(
      const AProfile: TConnectionProfile;
      const ATableName, AColumnName, ADataType, ADefaultValue: string;
      const ANotNull: Boolean;
      out AMessage: string
    ): Boolean;
    function EditColumn(
      const AProfile: TConnectionProfile;
      const ATableName: string;
      const AOldCol: TTableColumnInfo;
      const ANewName, ANewDataType, ANewDefaultValue: string;
      const ANewNotNull: Boolean;
      out AMessage: string
    ): Boolean;
    function DropColumn(
      const AProfile: TConnectionProfile;
      const ATableName, AColumnName: string;
      out AMessage: string
    ): Boolean;
    function CreateIndex(
      const AProfile: TConnectionProfile;
      const ATableName, AIndexName: string;
      const AColumns: TStrings;
      const AUnique, ADescending: Boolean;
      out AMessage: string
    ): Boolean;
    function DropIndex(
      const AProfile: TConnectionProfile;
      const AIndexName: string;
      out AMessage: string
    ): Boolean;
    function SetIndexActive(
      const AProfile: TConnectionProfile;
      const AIndexName: string;
      const AActive: Boolean;
      out AMessage: string
    ): Boolean;
    function SaveTableTrigger(
      const AProfile: TConnectionProfile;
      const ATableName, AOriginalTriggerName, ATriggerName, ATiming: string;
      const AHasInsert, AHasUpdate, AHasDelete, AIsActive: Boolean;
      const APosition: Integer;
      const ACodeText: string;
      const AIsNew: Boolean;
      out AMessage: string
    ): Boolean;
    function SetTriggerActive(
      const AProfile: TConnectionProfile;
      const ATableName, ATriggerName: string;
      const AActive: Boolean;
      out AMessage: string
    ): Boolean;
    function DropTableTrigger(
      const AProfile: TConnectionProfile;
      const ATableName, ATriggerName: string;
      out AMessage: string
    ): Boolean;
    function DropTable(
      const AProfile: TConnectionProfile;
      const ATableName: string;
      out AMessage: string
    ): Boolean;
    function LoadTableData(
      const AProfile: TConnectionProfile;
      const ATableName, AWhereClause: string;
      const ALimitRows: Integer;
      out AExecutedSQL: string
    ): TQueryResult;
    function ExecuteMetadataQuery(
      const AProfile: TConnectionProfile;
      const ASQL: string
    ): TQueryResult;
    property Factory: IDatabaseProviderFactory read FFactory;
  end;

procedure AddUniqueDependencyToArray(
  var AArr: TTableDependencyInfoArray;
  const ADirection: TTableDependencyDirection;
  const AObjName, AObjType: string;
  const ADetail: string = ''
);
function QuoteIdentList(const ADbType: TDatabaseType; const ACommaList: string): string;
function GenerateTableDDL(
  const ADbType: TDatabaseType;
  const AStructure: TTableStructure;
  const AIncludeIndexes: Boolean = True;
  const AIncludeTriggers: Boolean = False
): string;
procedure DecodeFirebirdTriggerDetails(
  const ATrigType: Integer;
  out ATiming, AEvents: string;
  out AHasInsert, AHasUpdate, AHasDelete: Boolean
);
function BuildTriggerEventsClause(
  const AHasInsert, AHasUpdate, AHasDelete: Boolean
): string;
function BuildFirebirdTriggerHeader(
  const ATableName, ATriggerName, ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete, AIsActive: Boolean;
  const APosition: Integer
): string;
function BuildFirebirdTriggerDDL(
  const ATableName, ATriggerName, ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete, AIsActive: Boolean;
  const APosition: Integer;
  const ABody: string
): string;
function BuildNewTableTriggerTemplate(
  const ADbType: TDatabaseType;
  const ATableName, ATriggerName, ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete: Boolean
): string;
function DecodeFirebirdDependencyType(const ADepType: Integer): string;
function TryResolveDependencyObjectKind(
  const ADbType: TDatabaseType;
  const AObjectType: string;
  out AKind: TSchemaObjectKind
): Boolean;
function StripLeadingDefaultKeyword(const ADefaultSource: string): string;
function BuildAddColumnDDL(
  const ADbType: TDatabaseType;
  const ATableName, AColumnName, ADataType, ADefaultValue: string;
  const ANotNull: Boolean
): string;
procedure BuildEditColumnDDL(
  const ADbType: TDatabaseType;
  const ATableName: string;
  const AOldCol: TTableColumnInfo;
  const ANewName, ANewDataType, ANewDefaultValue: string;
  const ANewNotNull: Boolean;
  const AIsFirebird25: Boolean;
  const ATargetStatements: TStrings
);
function BuildDropColumnDDL(
  const ADbType: TDatabaseType;
  const ATableName, AColumnName: string
): string;
function BuildCreateIndexDDL(
  const ADbType: TDatabaseType;
  const ATableName, AIndexName: string;
  const AColumns: TStrings;
  const AUnique, ADescending: Boolean
): string;
function BuildDropIndexDDL(const ADbType: TDatabaseType; const AIndexName: string): string;
function BuildSetIndexActiveDDL(
  const ADbType: TDatabaseType;
  const AIndexName: string;
  const AActive: Boolean
): string;

implementation

function EscapeSqlStr(const AValue: string): string;
begin
  Result := StringReplace(Trim(AValue), '''', '''''', [rfReplaceAll]);
end;

function StartsWithSqlKeyword(const AText, AKw: string): Boolean;
var
  Up: string;
begin
  Up := UpperCase(TrimLeft(AText));
  if Copy(Up, 1, Length(AKw)) <> UpperCase(AKw) then
    Exit(False);
  if Length(Up) = Length(AKw) then
    Exit(True);
  Result := Up[Length(AKw) + 1] in [#0..' '];
end;

procedure DecodeFirebirdTriggerDetails(
  const ATrigType: Integer;
  out ATiming, AEvents: string;
  out AHasInsert, AHasUpdate, AHasDelete: Boolean
);
var
  Mask, Slot, I: Integer;
begin
  AHasInsert := False;
  AHasUpdate := False;
  AHasDelete := False;
  AEvents := '';

  case ATrigType of
    8192: begin ATiming := 'DATABASE'; AEvents := 'ON CONNECT'; Exit; end;
    8193: begin ATiming := 'DATABASE'; AEvents := 'ON DISCONNECT'; Exit; end;
    8194: begin ATiming := 'DATABASE'; AEvents := 'ON TRANSACTION START'; Exit; end;
    8195: begin ATiming := 'DATABASE'; AEvents := 'ON TRANSACTION COMMIT'; Exit; end;
    8196: begin ATiming := 'DATABASE'; AEvents := 'ON TRANSACTION ROLLBACK'; Exit; end;
  end;

  if (ATrigType and 1) = 1 then
    ATiming := 'BEFORE'
  else
    ATiming := 'AFTER';

  Mask := (ATrigType + 1) shr 1;
  for I := 0 to 2 do
  begin
    Slot := (Mask shr (I * 2)) and 3;
    case Slot of
      1:
        if not AHasInsert then
        begin
          AHasInsert := True;
          if AEvents <> '' then AEvents := AEvents + ' OR ';
          AEvents := AEvents + 'INSERT';
        end;
      2:
        if not AHasUpdate then
        begin
          AHasUpdate := True;
          if AEvents <> '' then AEvents := AEvents + ' OR ';
          AEvents := AEvents + 'UPDATE';
        end;
      3:
        if not AHasDelete then
        begin
          AHasDelete := True;
          if AEvents <> '' then AEvents := AEvents + ' OR ';
          AEvents := AEvents + 'DELETE';
        end;
    end;
  end;

  if AEvents = '' then
  begin
    AHasInsert := True;
    AEvents := 'INSERT';
  end;
end;

function BuildTriggerEventsClause(
  const AHasInsert, AHasUpdate, AHasDelete: Boolean
): string;
begin
  Result := '';
  if AHasInsert then
    Result := 'INSERT';
  if AHasUpdate then
  begin
    if Result <> '' then
      Result := Result + ' OR ';
    Result := Result + 'UPDATE';
  end;
  if AHasDelete then
  begin
    if Result <> '' then
      Result := Result + ' OR ';
    Result := Result + 'DELETE';
  end;
end;

function BuildFirebirdTriggerHeader(
  const ATableName, ATriggerName, ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete, AIsActive: Boolean;
  const APosition: Integer
): string;
var
  TimingStr, EventsStr, ActiveStr: string;
  PosVal: Integer;
begin
  TimingStr := UpperCase(Trim(ATiming));
  if (TimingStr <> 'BEFORE') and (TimingStr <> 'AFTER') then
    TimingStr := 'BEFORE';

  EventsStr := BuildTriggerEventsClause(AHasInsert, AHasUpdate, AHasDelete);
  if EventsStr = '' then
    EventsStr := 'INSERT';

  if AIsActive then
    ActiveStr := 'ACTIVE'
  else
    ActiveStr := 'INACTIVE';

  PosVal := APosition;
  if PosVal < 0 then
    PosVal := 0;

  Result := Format(
    'CREATE OR ALTER TRIGGER %s FOR %s' + LineEnding + '%s %s %s POSITION %d',
    [
      QuoteDbIdent(dtFirebird, ATriggerName),
      QuoteDbIdent(dtFirebird, ATableName),
      ActiveStr,
      TimingStr,
      EventsStr,
      PosVal
    ]
  );
end;

function BuildFirebirdTriggerDDL(
  const ATableName, ATriggerName, ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete, AIsActive: Boolean;
  const APosition: Integer;
  const ABody: string
): string;
var
  CleanBody: string;
begin
  Result := BuildFirebirdTriggerHeader(
    ATableName,
    ATriggerName,
    ATiming,
    AHasInsert,
    AHasUpdate,
    AHasDelete,
    AIsActive,
    APosition
  );
  CleanBody := TrimRight(ABody);
  if not StartsWithSqlKeyword(CleanBody, 'AS') then
    Result := Result + LineEnding + 'AS';
  if CleanBody <> '' then
    Result := Result + LineEnding + CleanBody;
end;

function BuildNewTableTriggerTemplate(
  const ADbType: TDatabaseType;
  const ATableName, ATriggerName, ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete: Boolean
): string;
var
  TimingStr, EventsStr: string;
begin
  if ADbType = dtPostgreSQL then
  begin
    TimingStr := UpperCase(Trim(ATiming));
    if (TimingStr <> 'BEFORE') and (TimingStr <> 'AFTER') and (TimingStr <> 'INSTEAD OF') then
      TimingStr := 'BEFORE';
    EventsStr := BuildTriggerEventsClause(AHasInsert, AHasUpdate, AHasDelete);
    if EventsStr = '' then
      EventsStr := 'INSERT';
    Result :=
      'CREATE TRIGGER ' + QuoteDbIdent(dtPostgreSQL, ATriggerName) + LineEnding +
      TimingStr + ' ' + EventsStr + ' ON ' + QuoteDbIdent(dtPostgreSQL, ATableName) + LineEnding +
      'FOR EACH ROW' + LineEnding +
      'EXECUTE FUNCTION sua_funcao_trigger();';
  end
  else
  begin
    Result :=
      'AS' + LineEnding +
      'BEGIN' + LineEnding +
      '  /* Código PSQL da trigger */' + LineEnding +
      'END';
  end;
end;

function DecodeFirebirdDependencyType(const ADepType: Integer): string;
begin
  case ADepType of
    0: Result := 'TABLE';
    1: Result := 'VIEW';
    2: Result := 'TRIGGER';
    3: Result := 'COMPUTED FIELD';
    4: Result := 'VALIDATION';
    5: Result := 'PROCEDURE';
    6: Result := 'EXPRESSION INDEX';
    7: Result := 'EXCEPTION';
    8: Result := 'USER';
    9: Result := 'DOMAIN / FIELD';
    10: Result := 'INDEX';
    14: Result := 'GENERATOR';
    15: Result := 'FUNCTION';
    16: Result := 'BLOB FILTER';
    18: Result := 'PACKAGE';
    19: Result := 'PACKAGE BODY';
  else
    Result := Format('OBJECT(%d)', [ADepType]);
  end;
end;

function TryResolveDependencyObjectKind(
  const ADbType: TDatabaseType;
  const AObjectType: string;
  out AKind: TSchemaObjectKind
): Boolean;
var
  Up: string;
begin
  Result := True;
  Up := UpperCase(Trim(AObjectType));
  if (Up = 'TABLE') or
     (Up = 'FOREIGN KEY (TABELA FILHA)') or
     (Up = 'FOREIGN KEY (TABELA PAI)') then
    AKind := sokTables
  else if (Up = 'VIEW') or (Up = 'MATERIALIZED VIEW') then
    AKind := sokViews
  else if (Up = 'PROCEDURE') or ((ADbType = dtPostgreSQL) and (Up = 'FUNCTION')) then
    AKind := sokProcedures
  else if Up = 'TRIGGER' then
    AKind := sokTriggers
  else if (Up = 'GENERATOR') or (Up = 'SEQUENCE') then
    AKind := sokGenerators
  else
    Result := False;
end;

function StripLeadingDefaultKeyword(const ADefaultSource: string): string;
var
  S: string;
begin
  S := Trim(ADefaultSource);
  if SameText(S, 'DEFAULT') then
    Exit('');
  if (Length(S) > 7) and SameText(Copy(S, 1, 7), 'DEFAULT') and
     (S[8] in [' ', #9, #10, #13]) then
    S := Trim(Copy(S, 8, MaxInt));
  if (Length(S) >= 1) and (S[1] = '=') then
    S := Trim(Copy(S, 2, MaxInt));
  Result := S;
end;

function BuildAddColumnDDL(
  const ADbType: TDatabaseType;
  const ATableName, AColumnName, ADataType, ADefaultValue: string;
  const ANotNull: Boolean
): string;
var
  TblIdent, ColIdent, CleanType, CleanDef: string;
begin
  TblIdent := QuoteDbIdent(ADbType, ATableName);
  ColIdent := QuoteDbIdent(ADbType, AColumnName);
  CleanType := Trim(ADataType);
  CleanDef := StripLeadingDefaultKeyword(ADefaultValue);

  Result := Format('ALTER TABLE %s ADD %s %s', [TblIdent, ColIdent, CleanType]);
  if CleanDef <> '' then
    Result := Result + ' DEFAULT ' + CleanDef;
  if ANotNull then
    Result := Result + ' NOT NULL';
end;

procedure BuildEditColumnDDL(
  const ADbType: TDatabaseType;
  const ATableName: string;
  const AOldCol: TTableColumnInfo;
  const ANewName, ANewDataType, ANewDefaultValue: string;
  const ANewNotNull: Boolean;
  const AIsFirebird25: Boolean;
  const ATargetStatements: TStrings
);
var
  TblIdent, OldColName, NewColName, CurColName, CurIdent, NewIdent: string;
  OldType, NewType, OldDef, NewDef, SafeTbl, SafeCol: string;
begin
  if ATargetStatements = nil then
    Exit;
  ATargetStatements.Clear;

  TblIdent := QuoteDbIdent(ADbType, ATableName);
  OldColName := Trim(AOldCol.ColumnName);
  NewColName := Trim(ANewName);
  if NewColName = '' then
    NewColName := OldColName;

  CurColName := OldColName;
  CurIdent := QuoteDbIdent(ADbType, CurColName);

  { 1. Renomear coluna }
  if not SameText(OldColName, NewColName) then
  begin
    NewIdent := QuoteDbIdent(ADbType, NewColName);
    if ADbType = dtPostgreSQL then
      ATargetStatements.Add(Format('ALTER TABLE %s RENAME COLUMN %s TO %s', [TblIdent, CurIdent, NewIdent]))
    else
      ATargetStatements.Add(Format('ALTER TABLE %s ALTER COLUMN %s TO %s', [TblIdent, CurIdent, NewIdent]));
    CurColName := NewColName;
    CurIdent := NewIdent;
  end;

  { 2. Alterar tipo de dados }
  OldType := Trim(AOldCol.DataType);
  NewType := Trim(ANewDataType);
  if (NewType <> '') and (not SameText(OldType, NewType)) then
    ATargetStatements.Add(Format('ALTER TABLE %s ALTER COLUMN %s TYPE %s', [TblIdent, CurIdent, NewType]));

  { 3. Alterar valor padrão }
  OldDef := StripLeadingDefaultKeyword(AOldCol.DefaultValue);
  NewDef := StripLeadingDefaultKeyword(ANewDefaultValue);
  if OldDef <> NewDef then
  begin
    if NewDef = '' then
      ATargetStatements.Add(Format('ALTER TABLE %s ALTER COLUMN %s DROP DEFAULT', [TblIdent, CurIdent]))
    else
      ATargetStatements.Add(Format('ALTER TABLE %s ALTER COLUMN %s SET DEFAULT %s', [TblIdent, CurIdent, NewDef]));
  end;

  { 4. Alterar restrição NOT NULL }
  if AOldCol.NotNull <> ANewNotNull then
  begin
    if (ADbType = dtPostgreSQL) or (not AIsFirebird25) then
    begin
      if ANewNotNull then
        ATargetStatements.Add(Format('ALTER TABLE %s ALTER COLUMN %s SET NOT NULL', [TblIdent, CurIdent]))
      else
        ATargetStatements.Add(Format('ALTER TABLE %s ALTER COLUMN %s DROP NOT NULL', [TblIdent, CurIdent]));
    end
    else
    begin
      SafeTbl := EscapeSqlStr(ATableName);
      SafeCol := EscapeSqlStr(CurColName);
      if ANewNotNull then
        ATargetStatements.Add(Format(
          'UPDATE RDB$RELATION_FIELDS SET RDB$NULL_FLAG = 1 ' +
          'WHERE UPPER(TRIM(RDB$RELATION_NAME)) = UPPER(''%s'') AND UPPER(TRIM(RDB$FIELD_NAME)) = UPPER(''%s'')',
          [SafeTbl, SafeCol]
        ))
      else
        ATargetStatements.Add(Format(
          'UPDATE RDB$RELATION_FIELDS SET RDB$NULL_FLAG = NULL ' +
          'WHERE UPPER(TRIM(RDB$RELATION_NAME)) = UPPER(''%s'') AND UPPER(TRIM(RDB$FIELD_NAME)) = UPPER(''%s'')',
          [SafeTbl, SafeCol]
        ));
    end;
  end;
end;

function BuildDropColumnDDL(
  const ADbType: TDatabaseType;
  const ATableName, AColumnName: string
): string;
begin
  Result := Format('ALTER TABLE %s DROP %s', [
    QuoteDbIdent(ADbType, ATableName),
    QuoteDbIdent(ADbType, AColumnName)
  ]);
end;

function BuildCreateIndexDDL(
  const ADbType: TDatabaseType;
  const ATableName, AIndexName: string;
  const AColumns: TStrings;
  const AUnique, ADescending: Boolean
): string;
var
  I: Integer;
  ColsStr, ColIdent, UniquePart, DescPart: string;
begin
  Result := '';
  if (AColumns = nil) or (AColumns.Count = 0) or
     (Trim(ATableName) = '') or (Trim(AIndexName) = '') then
    Exit;

  ColsStr := '';
  for I := 0 to AColumns.Count - 1 do
  begin
    if Trim(AColumns[I]) = '' then
      Continue;
    if ColsStr <> '' then
      ColsStr := ColsStr + ', ';
    ColIdent := QuoteDbIdent(ADbType, Trim(AColumns[I]));
    if (ADbType = dtPostgreSQL) and ADescending then
      ColIdent := ColIdent + ' DESC';
    ColsStr := ColsStr + ColIdent;
  end;

  if ColsStr = '' then
    Exit;

  UniquePart := '';
  if AUnique then
    UniquePart := 'UNIQUE ';

  DescPart := '';
  if (ADbType = dtFirebird) and ADescending then
    DescPart := 'DESCENDING ';

  Result := Format('CREATE %s%sINDEX %s ON %s (%s)', [
    UniquePart,
    DescPart,
    QuoteDbIdent(ADbType, AIndexName),
    QuoteDbIdent(ADbType, ATableName),
    ColsStr
  ]);
end;

function BuildDropIndexDDL(const ADbType: TDatabaseType; const AIndexName: string): string;
begin
  Result := Format('DROP INDEX %s', [QuoteDbIdent(ADbType, AIndexName)]);
end;

function BuildSetIndexActiveDDL(
  const ADbType: TDatabaseType;
  const AIndexName: string;
  const AActive: Boolean
): string;
begin
  if ADbType <> dtFirebird then
    Exit('');
  if AActive then
    Result := Format('ALTER INDEX %s ACTIVE', [QuoteDbIdent(dtFirebird, AIndexName)])
  else
    Result := Format('ALTER INDEX %s INACTIVE', [QuoteDbIdent(dtFirebird, AIndexName)]);
end;

{ TManageTableStructureUseCase }

constructor TManageTableStructureUseCase.Create(const AFactory: IDatabaseProviderFactory);
begin
  inherited Create;
  FFactory := AFactory;
end;

function TManageTableStructureUseCase.ExecuteQuery(const ASession: IDatabaseSession; const ASQL: string): TQueryResult;
begin
  Result := ASession.ExecuteSQL(ASQL, False, 0);
  if (Result <> nil) and (not Result.Success) then
  begin
    try
      raise Exception.Create(Result.MessageText);
    except
      Result.Free;
      raise;
    end;
  end;
end;

function TManageTableStructureUseCase.ExecuteDDLStatements(
  const AProfile: TConnectionProfile;
  const AStatements: TStrings;
  out AMessage: string
): Boolean;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  I: Integer;
  Stmt: string;
begin
  Result := False;
  AMessage := '';
  if (AProfile = nil) or (FFactory = nil) then
  begin
    AMessage := 'Conexão inválida.';
    Exit;
  end;
  if (AStatements = nil) or (AStatements.Count = 0) then
  begin
    AMessage := 'Nenhuma alteração pendente.';
    Result := True;
    Exit;
  end;

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    Session.Connect;
    Session.StartTransaction;
    try
      for I := 0 to AStatements.Count - 1 do
      begin
        Stmt := Trim(AStatements[I]);
        if Stmt = '' then
          Continue;
        Res := Session.ExecuteSQL(Stmt, False, 0);
        try
          if not Res.Success then
            raise Exception.Create(Res.MessageText);
        finally
          Res.Free;
        end;
      end;
      Session.Commit;
      Result := True;
      AMessage := 'Operação executada com sucesso.';
    except
      on E: Exception do
      begin
        if Session.InTransaction then
        begin
          try
            Session.Rollback;
          except
          end;
        end;
        AMessage := E.Message;
      end;
    end;
  finally
    Session.Disconnect;
  end;
end;

function QuoteIdentList(const ADbType: TDatabaseType; const ACommaList: string): string;
var
  Parts: TStringList;
  I: Integer;
  Item: string;
begin
  Result := '';
  if Trim(ACommaList) = '' then
    Exit;
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ',';
    Parts.DelimitedText := ACommaList;
    for I := 0 to Parts.Count - 1 do
    begin
      Item := Trim(Parts[I]);
      if Item = '' then
        Continue;
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + QuoteDbIdent(ADbType, Item);
    end;
  finally
    Parts.Free;
  end;
end;

function GenerateTableDDL(
  const ADbType: TDatabaseType;
  const AStructure: TTableStructure;
  const AIncludeIndexes: Boolean;
  const AIncludeTriggers: Boolean
): string;
var
  Entries, ColsList, IdxLines, TrigLines: TStringList;
  I, J, K: Integer;
  Col: TTableColumnInfo;
  IdxInfo: TTableIndexInfo;
  TrigInfo: TTableTriggerInfo;
  FK: TTableForeignKeyInfo;
  UK: TTableUniqueConstraintInfo;
  CHK: TTableCheckConstraintInfo;
  Line, ColType, DefVal, Expr, RuleUpd, RuleDel, IdxDDL, TrigDDL, CreateBody: string;
  IsAutoConstraintName: Boolean;

  function NormalizeExpr(const ASource, AKw: string): string;
  begin
    Result := Trim(ASource);
    if Result = '' then
      Exit;
    if (Length(Result) >= Length(AKw)) and
       SameText(Copy(Result, 1, Length(AKw)), AKw) and
       ((Length(Result) = Length(AKw)) or (Result[Length(AKw) + 1] in [' ', '(', #9, #10, #13])) then
      Exit;
    if Result[1] <> '(' then
      Result := '(' + Result + ')';
    Result := AKw + ' ' + Result;
  end;

begin
  Result := '';
  if (AStructure = nil) or (Trim(AStructure.TableName) = '') then
    Exit;

  Entries := TStringList.Create;
  IdxLines := TStringList.Create;
  TrigLines := TStringList.Create;
  try
    { 1. Colunas }
    for I := 0 to High(AStructure.Columns) do
    begin
      Col := AStructure.Columns[I];
      Line := '  ' + QuoteDbIdent(ADbType, Col.ColumnName) + ' ';
      if Col.IsComputed then
      begin
        Expr := Trim(Col.ComputedSource);
        if (Expr <> '') and (Expr[1] <> '(') then
          Expr := '(' + Expr + ')';
        if ADbType = dtPostgreSQL then
          Line := Line + Trim(Col.DataType) + ' GENERATED ALWAYS AS ' + Expr + ' STORED'
        else
          Line := Line + 'COMPUTED BY ' + Expr;
      end
      else
      begin
        if (Trim(Col.DomainName) <> '') and (ADbType = dtFirebird) then
          ColType := QuoteDbIdent(ADbType, Col.DomainName)
        else
          ColType := Trim(Col.DataType);
        Line := Line + ColType;
        DefVal := StripLeadingDefaultKeyword(Col.DefaultValue);
        if DefVal <> '' then
          Line := Line + ' DEFAULT ' + DefVal;
        if Col.NotNull then
          Line := Line + ' NOT NULL';
      end;
      Entries.Add(Line);
    end;

    { 2. Primary Key }
    if Trim(AStructure.PrimaryKeyColumns) <> '' then
    begin
      IsAutoConstraintName := (Trim(AStructure.PrimaryKeyName) = '') or
        ((ADbType = dtFirebird) and (Pos('INTEG_', UpperCase(Trim(AStructure.PrimaryKeyName))) = 1));
      Line := '  ';
      if not IsAutoConstraintName then
        Line := Line + 'CONSTRAINT ' + QuoteDbIdent(ADbType, AStructure.PrimaryKeyName) + ' ';
      Line := Line + 'PRIMARY KEY (' + QuoteIdentList(ADbType, AStructure.PrimaryKeyColumns) + ')';
      Entries.Add(Line);
    end;

    { 3. Unique Constraints }
    for I := 0 to High(AStructure.UniqueConstraints) do
    begin
      UK := AStructure.UniqueConstraints[I];
      if Trim(UK.Columns) = '' then
        Continue;
      IsAutoConstraintName := (Trim(UK.ConstraintName) = '') or
        ((ADbType = dtFirebird) and (Pos('INTEG_', UpperCase(Trim(UK.ConstraintName))) = 1));
      Line := '  ';
      if not IsAutoConstraintName then
        Line := Line + 'CONSTRAINT ' + QuoteDbIdent(ADbType, UK.ConstraintName) + ' ';
      Line := Line + 'UNIQUE (' + QuoteIdentList(ADbType, UK.Columns) + ')';
      Entries.Add(Line);
    end;

    { 4. Foreign Keys }
    for I := 0 to High(AStructure.ForeignKeys) do
    begin
      FK := AStructure.ForeignKeys[I];
      if (Trim(FK.Columns) = '') or (Trim(FK.RefTable) = '') then
        Continue;
      Line := '  ';
      IsAutoConstraintName := (Trim(FK.ConstraintName) = '') or
        ((ADbType = dtFirebird) and (Pos('INTEG_', UpperCase(Trim(FK.ConstraintName))) = 1));
      if not IsAutoConstraintName then
        Line := Line + 'CONSTRAINT ' + QuoteDbIdent(ADbType, FK.ConstraintName) + ' ';
      Line := Line + Format('FOREIGN KEY (%s) REFERENCES %s', [
        QuoteIdentList(ADbType, FK.Columns),
        QuoteDbIdent(ADbType, FK.RefTable)
      ]);
      if Trim(FK.RefColumns) <> '' then
        Line := Line + ' (' + QuoteIdentList(ADbType, FK.RefColumns) + ')';
      RuleUpd := UpperCase(Trim(FK.UpdateRule));
      RuleDel := UpperCase(Trim(FK.DeleteRule));
      if (RuleUpd <> '') and (RuleUpd <> 'RESTRICT') and (RuleUpd <> 'NO ACTION') then
        Line := Line + ' ON UPDATE ' + RuleUpd;
      if (RuleDel <> '') and (RuleDel <> 'RESTRICT') and (RuleDel <> 'NO ACTION') then
        Line := Line + ' ON DELETE ' + RuleDel;
      Entries.Add(Line);
    end;

    { 5. Check Constraints }
    for I := 0 to High(AStructure.CheckConstraints) do
    begin
      CHK := AStructure.CheckConstraints[I];
      if Trim(CHK.CheckSource) = '' then
        Continue;
      Line := '  ';
      IsAutoConstraintName := (Trim(CHK.ConstraintName) = '') or
        ((ADbType = dtFirebird) and (Pos('INTEG_', UpperCase(Trim(CHK.ConstraintName))) = 1));
      if not IsAutoConstraintName then
        Line := Line + 'CONSTRAINT ' + QuoteDbIdent(ADbType, CHK.ConstraintName) + ' ';
      Line := Line + NormalizeExpr(CHK.CheckSource, 'CHECK');
      Entries.Add(Line);
    end;

    CreateBody := 'CREATE TABLE ' + QuoteDbIdent(ADbType, AStructure.TableName) + ' (' + LineEnding;
    for I := 0 to Entries.Count - 1 do
    begin
      CreateBody := CreateBody + Entries[I];
      if I < Entries.Count - 1 then
        CreateBody := CreateBody + ',';
      CreateBody := CreateBody + LineEnding;
    end;
    CreateBody := CreateBody + ');';
    Result := CreateBody;

    { 6. Índices manuais }
    if AIncludeIndexes then
    begin
      for I := 0 to High(AStructure.Indexes) do
      begin
        IdxInfo := AStructure.Indexes[I];
        if IdxInfo.IsPrimaryKey or IdxInfo.IsForeignKey or (Trim(IdxInfo.ConstraintName) <> '') then
          Continue;

        IdxDDL := '';
        if (ADbType = dtPostgreSQL) and (Pos('CREATE ', UpperCase(TrimLeft(IdxInfo.ExpressionSource))) = 1) then
        begin
          IdxDDL := TrimRight(IdxInfo.ExpressionSource);
          if (IdxDDL <> '') and (IdxDDL[Length(IdxDDL)] <> ';') then
            IdxDDL := IdxDDL + ';';
        end
        else if (Trim(IdxInfo.ExpressionSource) <> '') then
        begin
          IdxDDL := 'CREATE ';
          if IdxInfo.IsUnique then
            IdxDDL := IdxDDL + 'UNIQUE ';
          if (ADbType = dtFirebird) and IdxInfo.IsDescending then
            IdxDDL := IdxDDL + 'DESCENDING ';
          IdxDDL := IdxDDL + Format('INDEX %s ON %s COMPUTED BY %s;', [
            QuoteDbIdent(ADbType, IdxInfo.IndexName),
            QuoteDbIdent(ADbType, AStructure.TableName),
            Trim(IdxInfo.ExpressionSource)
          ]);
        end
        else if Trim(IdxInfo.Columns) <> '' then
        begin
          ColsList := TStringList.Create;
          try
            ColsList.StrictDelimiter := True;
            ColsList.Delimiter := ',';
            ColsList.DelimitedText := IdxInfo.Columns;
            for K := 0 to ColsList.Count - 1 do
              ColsList[K] := Trim(ColsList[K]);
            for J := ColsList.Count - 1 downto 0 do
              if ColsList[J] = '' then
                ColsList.Delete(J);
            IdxDDL := BuildCreateIndexDDL(
              ADbType,
              AStructure.TableName,
              IdxInfo.IndexName,
              ColsList,
              IdxInfo.IsUnique,
              IdxInfo.IsDescending
            );
            if IdxDDL <> '' then
              IdxDDL := IdxDDL + ';';
          finally
            ColsList.Free;
          end;
        end;

        if IdxDDL <> '' then
        begin
          IdxLines.Add(IdxDDL);
          if (ADbType = dtFirebird) and (not IdxInfo.IsActive) then
            IdxLines.Add('ALTER INDEX ' + QuoteDbIdent(dtFirebird, IdxInfo.IndexName) + ' INACTIVE;');
        end;
      end;

      if IdxLines.Count > 0 then
        Result := Result + LineEnding + LineEnding + TrimRight(IdxLines.Text);
    end;

    { 7. Triggers }
    if AIncludeTriggers and (Length(AStructure.Triggers) > 0) then
    begin
      if ADbType = dtFirebird then
      begin
        TrigLines.Add('/* Triggers */');
        TrigLines.Add('SET TERM ^ ;');
        TrigLines.Add('');
        for I := 0 to High(AStructure.Triggers) do
        begin
          TrigInfo := AStructure.Triggers[I];
          TrigDDL := TrimRight(TrigInfo.FullDDL);
          if TrigDDL = '' then
            Continue;
          TrigLines.Add(TrigDDL + '^');
          TrigLines.Add('');
        end;
        TrigLines.Add('SET TERM ; ^');
      end
      else
      begin
        TrigLines.Add('-- Triggers');
        for I := 0 to High(AStructure.Triggers) do
        begin
          TrigInfo := AStructure.Triggers[I];
          TrigDDL := TrimRight(TrigInfo.FullDDL);
          if TrigDDL = '' then
            Continue;
          if TrigDDL[Length(TrigDDL)] <> ';' then
            TrigDDL := TrigDDL + ';';
          TrigLines.Add(TrigDDL);
          if I < High(AStructure.Triggers) then
            TrigLines.Add('');
        end;
      end;

      if TrigLines.Count > 1 then
        Result := Result + LineEnding + LineEnding + TrimRight(TrigLines.Text);
    end;
  finally
    TrigLines.Free;
    IdxLines.Free;
    Entries.Free;
  end;
end;

procedure AddUniqueDependencyToArray(
  var AArr: TTableDependencyInfoArray;
  const ADirection: TTableDependencyDirection;
  const AObjName, AObjType: string;
  const ADetail: string = ''
);
var
  I, Len: Integer;
  CleanName, CleanType: string;
begin
  CleanName := Trim(AObjName);
  CleanType := Trim(AObjType);
  if CleanName = '' then
    Exit;

  for I := 0 to High(AArr) do
  begin
    if (AArr[I].Direction = ADirection) and
       SameText(AArr[I].ObjectName, CleanName) and
       SameText(AArr[I].ObjectType, CleanType) then
      Exit;
  end;

  Len := Length(AArr);
  SetLength(AArr, Len + 1);
  AArr[Len].Direction := ADirection;
  AArr[Len].ObjectName := CleanName;
  AArr[Len].ObjectType := CleanType;
  AArr[Len].FieldOrDetail := Trim(ADetail);
end;

procedure AddUniqueDependency(
  const AStructure: TTableStructure;
  const ADirection: TTableDependencyDirection;
  const AObjName, AObjType, ADetail: string
);
begin
  if AStructure = nil then
    Exit;
  AddUniqueDependencyToArray(AStructure.Dependencies, ADirection, AObjName, AObjType, ADetail);
end;

procedure TManageTableStructureUseCase.LoadFirebirdStructure(
  const ASession: IDatabaseSession;
  const ATableName: string;
  const AStructure: TTableStructure
);
var
  SafeTbl, ColDef, FldDef, IdxName, SegCol, TriggerInfo, TrigBody: string;
  Res, ResSeg, ResPK: TQueryResult;
  PKCols: TStringList;
  IdxColsMap: TStringList;
  I, J, IdxPos, TrigType, TrigSeq, InactiveFlag: Integer;
  Row: TQueryRow;
  Col: TTableColumnInfo;
  IdxInfo: TTableIndexInfo;
  TrigItem: TTableTriggerInfo;
  ColListPtr: TStringList;
begin
  SafeTbl := EscapeSqlStr(ATableName);

  { 1. Colunas de PK }
  PKCols := TStringList.Create;
  PKCols.CaseSensitive := False;
  try
    ResPK := ExecuteQuery(ASession, Format(
      'SELECT TRIM(rc.RDB$CONSTRAINT_NAME), TRIM(s.RDB$FIELD_NAME) ' +
      'FROM RDB$RELATION_CONSTRAINTS rc ' +
      'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND rc.RDB$CONSTRAINT_TYPE = ''PRIMARY KEY'' ' +
      'ORDER BY s.RDB$FIELD_POSITION',
      [SafeTbl]
    ));
    try
      if (ResPK <> nil) and ResPK.HasResultSet then
      begin
        for I := 0 to ResPK.RowCount - 1 do
        begin
          if AStructure.PrimaryKeyName = '' then
            AStructure.PrimaryKeyName := Trim(ResPK.GetRow(I)[0].AsText);
          SegCol := Trim(ResPK.GetRow(I)[1].AsText);
          if SegCol <> '' then
          begin
            PKCols.Add(SegCol);
            if AStructure.PrimaryKeyColumns <> '' then
              AStructure.PrimaryKeyColumns := AStructure.PrimaryKeyColumns + ', ';
            AStructure.PrimaryKeyColumns := AStructure.PrimaryKeyColumns + SegCol;
          end;
        end;
      end;
    finally
      ResPK.Free;
    end;

    { 2. Campos }
    Res := ExecuteQuery(ASession, Format(
      'SELECT ' +
      '  rf.RDB$FIELD_POSITION, ' +
      '  TRIM(rf.RDB$FIELD_NAME), ' +
      '  TRIM(rf.RDB$FIELD_SOURCE), ' +
      '  f.RDB$FIELD_TYPE, ' +
      '  f.RDB$FIELD_SUB_TYPE, ' +
      '  f.RDB$FIELD_LENGTH, ' +
      '  f.RDB$FIELD_PRECISION, ' +
      '  f.RDB$FIELD_SCALE, ' +
      '  f.RDB$CHARACTER_LENGTH, ' +
      '  COALESCE(rf.RDB$NULL_FLAG, f.RDB$NULL_FLAG, 0), ' +
      '  rf.RDB$DEFAULT_SOURCE, ' +
      '  f.RDB$DEFAULT_SOURCE, ' +
      '  f.RDB$COMPUTED_SOURCE, ' +
      '  rf.RDB$DESCRIPTION ' +
      'FROM RDB$RELATION_FIELDS rf ' +
      'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE ' +
      'WHERE UPPER(TRIM(rf.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      'ORDER BY rf.RDB$FIELD_POSITION',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        SetLength(AStructure.Columns, Res.RowCount);
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          Col.Position := StrToIntDef(Trim(Row[0].AsText), I);
          Col.ColumnName := Trim(Row[1].AsText);
          if Pos('RDB$', UpperCase(Trim(Row[2].AsText))) = 1 then
            Col.DomainName := ''
          else
            Col.DomainName := Trim(Row[2].AsText);
          Col.DataType := DecodeFirebirdFieldType(
            '',
            StrToIntDef(Trim(Row[3].AsText), 0),
            StrToIntDef(Trim(Row[4].AsText), 0),
            StrToIntDef(Trim(Row[5].AsText), 0),
            StrToIntDef(Trim(Row[6].AsText), 0),
            StrToIntDef(Trim(Row[7].AsText), 0),
            StrToIntDef(Trim(Row[8].AsText), 0)
          );
          Col.NotNull := StrToIntDef(Trim(Row[9].AsText), 0) = 1;
          ColDef := '';
          if not Row[10].IsNull then
            ColDef := StripLeadingDefaultKeyword(Row[10].AsText);
          if (ColDef = '') and (not Row[11].IsNull) then
            ColDef := StripLeadingDefaultKeyword(Row[11].AsText);
          Col.DefaultValue := ColDef;
          Col.ComputedSource := '';
          if not Row[12].IsNull then
            Col.ComputedSource := Trim(Row[12].AsText);
          Col.IsComputed := Col.ComputedSource <> '';
          Col.Description := '';
          if not Row[13].IsNull then
            Col.Description := Trim(Row[13].AsText);
          Col.IsPrimaryKey := PKCols.IndexOf(Col.ColumnName) >= 0;
          if Col.IsPrimaryKey then
            Col.NotNull := True;
          AStructure.Columns[I] := Col;
        end;
      end;
    finally
      Res.Free;
    end;
  finally
    PKCols.Free;
  end;

  { 3. Índices }
  IdxColsMap := TStringList.Create;
  IdxColsMap.OwnsObjects := True;
  IdxColsMap.CaseSensitive := False;
  IdxColsMap.Sorted := True;
  try
    ResSeg := ExecuteQuery(ASession, Format(
      'SELECT TRIM(s.RDB$INDEX_NAME), TRIM(s.RDB$FIELD_NAME), s.RDB$FIELD_POSITION ' +
      'FROM RDB$INDEX_SEGMENTS s ' +
      'JOIN RDB$INDICES i ON i.RDB$INDEX_NAME = s.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(i.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND COALESCE(i.RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY s.RDB$INDEX_NAME, s.RDB$FIELD_POSITION',
      [SafeTbl]
    ));
    try
      if (ResSeg <> nil) and ResSeg.HasResultSet then
      begin
        for I := 0 to ResSeg.RowCount - 1 do
        begin
          Row := ResSeg.GetRow(I);
          IdxName := Trim(Row[0].AsText);
          SegCol := Trim(Row[1].AsText);
          if not IdxColsMap.Find(IdxName, IdxPos) then
          begin
            ColListPtr := TStringList.Create;
            IdxColsMap.AddObject(IdxName, ColListPtr);
          end
          else
            ColListPtr := TStringList(IdxColsMap.Objects[IdxPos]);
          if SegCol <> '' then
            ColListPtr.Add(SegCol);
        end;
      end;
    finally
      ResSeg.Free;
    end;

    Res := ExecuteQuery(ASession, Format(
      'SELECT ' +
      '  TRIM(i.RDB$INDEX_NAME), ' +
      '  COALESCE(i.RDB$UNIQUE_FLAG, 0), ' +
      '  COALESCE(i.RDB$INDEX_TYPE, 0), ' +
      '  COALESCE(i.RDB$INDEX_INACTIVE, 0), ' +
      '  TRIM(COALESCE(rc.RDB$CONSTRAINT_TYPE, '''')), ' +
      '  TRIM(COALESCE(rc.RDB$CONSTRAINT_NAME, '''')), ' +
      '  i.RDB$EXPRESSION_SOURCE ' +
      'FROM RDB$INDICES i ' +
      'LEFT JOIN RDB$RELATION_CONSTRAINTS rc ON rc.RDB$INDEX_NAME = i.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(i.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND COALESCE(i.RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY i.RDB$INDEX_NAME',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        SetLength(AStructure.Indexes, Res.RowCount);
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          IdxInfo.IndexName := Trim(Row[0].AsText);
          IdxInfo.IsUnique := StrToIntDef(Trim(Row[1].AsText), 0) = 1;
          IdxInfo.IsDescending := StrToIntDef(Trim(Row[2].AsText), 0) = 1;
          IdxInfo.IsActive := StrToIntDef(Trim(Row[3].AsText), 0) = 0;
          FldDef := Trim(Row[4].AsText);
          IdxInfo.ConstraintName := Trim(Row[5].AsText);
          IdxInfo.IsPrimaryKey := SameText(FldDef, 'PRIMARY KEY');
          IdxInfo.IsForeignKey := SameText(FldDef, 'FOREIGN KEY');
          IdxInfo.ExpressionSource := '';
          if not Row[6].IsNull then
            IdxInfo.ExpressionSource := Trim(Row[6].AsText);
          IdxInfo.Columns := '';
          if IdxColsMap.Find(IdxInfo.IndexName, IdxPos) then
          begin
            ColListPtr := TStringList(IdxColsMap.Objects[IdxPos]);
            for J := 0 to ColListPtr.Count - 1 do
            begin
              if IdxInfo.Columns <> '' then
                IdxInfo.Columns := IdxInfo.Columns + ', ';
              IdxInfo.Columns := IdxInfo.Columns + ColListPtr[J];
            end;
          end;
          AStructure.Indexes[I] := IdxInfo;
        end;
      end;
    finally
      Res.Free;
    end;
  finally
    IdxColsMap.Free;
  end;

  { 4. Dependências (Usada por esta tabela / Objetos que dependem desta tabela) }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(d.RDB$DEPENDENT_NAME), d.RDB$DEPENDENT_TYPE, TRIM(COALESCE(d.RDB$FIELD_NAME, '''')) ' +
      'FROM RDB$DEPENDENCIES d ' +
      'WHERE UPPER(TRIM(d.RDB$DEPENDED_ON_NAME)) = UPPER(''%s'') ' +
      '  AND UPPER(TRIM(d.RDB$DEPENDENT_NAME)) <> UPPER(''%s'') ' +
      'ORDER BY 2, 1, 3',
      [SafeTbl, SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(
            AStructure,
            tddDependentOnTable,
            Trim(Row[0].AsText),
            DecodeFirebirdDependencyType(StrToIntDef(Trim(Row[1].AsText), -1)),
            Trim(Row[2].AsText)
          );
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { Tabelas filhas por Foreign Key }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(child_rc.RDB$RELATION_NAME), TRIM(child_rc.RDB$CONSTRAINT_NAME) ' +
      'FROM RDB$REF_CONSTRAINTS ref ' +
      'JOIN RDB$RELATION_CONSTRAINTS parent_rc ON parent_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONST_NAME_UQ ' +
      'JOIN RDB$RELATION_CONSTRAINTS child_rc ON child_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONSTRAINT_NAME ' +
      'WHERE UPPER(TRIM(parent_rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      'ORDER BY 1, 2',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(
            AStructure,
            tddDependentOnTable,
            Trim(Row[0].AsText),
            'FOREIGN KEY (Tabela Filha)',
            'FK: ' + Trim(Row[1].AsText)
          );
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { Triggers associadas à tabela }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT ' +
      '  TRIM(t.RDB$TRIGGER_NAME), ' +
      '  COALESCE(t.RDB$TRIGGER_TYPE, 1), ' +
      '  COALESCE(t.RDB$TRIGGER_SEQUENCE, 0), ' +
      '  COALESCE(t.RDB$TRIGGER_INACTIVE, 0), ' +
      '  t.RDB$TRIGGER_SOURCE ' +
      'FROM RDB$TRIGGERS t ' +
      'WHERE UPPER(TRIM(t.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND COALESCE(t.RDB$SYSTEM_FLAG, 0) = 0 ' +
      '  AND NOT EXISTS (SELECT 1 FROM RDB$CHECK_CONSTRAINTS cc WHERE cc.RDB$TRIGGER_NAME = t.RDB$TRIGGER_NAME) ' +
      'ORDER BY t.RDB$TRIGGER_SEQUENCE, t.RDB$TRIGGER_NAME',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        SetLength(AStructure.Triggers, Res.RowCount);
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          TrigType := StrToIntDef(Trim(Row[1].AsText), 1);
          TrigSeq := StrToIntDef(Trim(Row[2].AsText), 0);
          InactiveFlag := StrToIntDef(Trim(Row[3].AsText), 0);
          if Row[4].IsNull then
            TrigBody := ''
          else
            TrigBody := TrimRight(Row[4].AsText);

          TrigItem := Default(TTableTriggerInfo);
          TrigItem.TriggerName := Trim(Row[0].AsText);
          DecodeFirebirdTriggerDetails(
            TrigType,
            TrigItem.Timing,
            TrigItem.Events,
            TrigItem.HasInsert,
            TrigItem.HasUpdate,
            TrigItem.HasDelete
          );
          TrigItem.Position := TrigSeq;
          TrigItem.IsActive := InactiveFlag = 0;
          TrigItem.SourceBody := TrigBody;
          TrigItem.FunctionName := '';
          TrigItem.FullDDL := BuildFirebirdTriggerDDL(
            ATableName,
            TrigItem.TriggerName,
            TrigItem.Timing,
            TrigItem.HasInsert,
            TrigItem.HasUpdate,
            TrigItem.HasDelete,
            TrigItem.IsActive,
            TrigItem.Position,
            TrigItem.SourceBody
          );
          AStructure.Triggers[I] := TrigItem;

          TriggerInfo := Trim(TrigItem.Timing + ' ' + TrigItem.Events);
          if not TrigItem.IsActive then
            TriggerInfo := TriggerInfo + ' (INATIVA)';
          AddUniqueDependency(
            AStructure,
            tddDependentOnTable,
            TrigItem.TriggerName,
            'TRIGGER',
            TriggerInfo
          );
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { 5. Objetos de que esta tabela depende }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(d.RDB$DEPENDED_ON_NAME), d.RDB$DEPENDED_ON_TYPE, TRIM(COALESCE(d.RDB$FIELD_NAME, '''')) ' +
      'FROM RDB$DEPENDENCIES d ' +
      'WHERE UPPER(TRIM(d.RDB$DEPENDENT_NAME)) = UPPER(''%s'') ' +
      '  AND UPPER(TRIM(d.RDB$DEPENDED_ON_NAME)) <> UPPER(''%s'') ' +
      'ORDER BY 2, 1, 3',
      [SafeTbl, SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(
            AStructure,
            tddTableDependsOn,
            Trim(Row[0].AsText),
            DecodeFirebirdDependencyType(StrToIntDef(Trim(Row[1].AsText), -1)),
            Trim(Row[2].AsText)
          );
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { Tabelas pai referenciadas pelas FKs desta tabela }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(parent_rc.RDB$RELATION_NAME), TRIM(child_rc.RDB$CONSTRAINT_NAME) ' +
      'FROM RDB$REF_CONSTRAINTS ref ' +
      'JOIN RDB$RELATION_CONSTRAINTS child_rc ON child_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONSTRAINT_NAME ' +
      'JOIN RDB$RELATION_CONSTRAINTS parent_rc ON parent_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONST_NAME_UQ ' +
      'WHERE UPPER(TRIM(child_rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      'ORDER BY 1, 2',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(
            AStructure,
            tddTableDependsOn,
            Trim(Row[0].AsText),
            'FOREIGN KEY (Tabela Pai)',
            'FK: ' + Trim(Row[1].AsText)
          );
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { Domínios customizados usados pelos campos }
  for I := 0 to High(AStructure.Columns) do
  begin
    if AStructure.Columns[I].DomainName <> '' then
      AddUniqueDependency(
        AStructure,
        tddTableDependsOn,
        AStructure.Columns[I].DomainName,
        'DOMAIN',
        'Campo: ' + AStructure.Columns[I].ColumnName
      );
  end;

  { 6. Unique Constraints }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT TRIM(rc.RDB$CONSTRAINT_NAME), TRIM(s.RDB$FIELD_NAME) ' +
      'FROM RDB$RELATION_CONSTRAINTS rc ' +
      'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND rc.RDB$CONSTRAINT_TYPE = ''UNIQUE'' ' +
      'ORDER BY rc.RDB$CONSTRAINT_NAME, s.RDB$FIELD_POSITION',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          ColDef := Trim(Row[0].AsText);
          SegCol := Trim(Row[1].AsText);
          IdxPos := -1;
          for J := 0 to High(AStructure.UniqueConstraints) do
            if SameText(AStructure.UniqueConstraints[J].ConstraintName, ColDef) then
            begin
              IdxPos := J;
              Break;
            end;
          if IdxPos < 0 then
          begin
            IdxPos := Length(AStructure.UniqueConstraints);
            SetLength(AStructure.UniqueConstraints, IdxPos + 1);
            AStructure.UniqueConstraints[IdxPos].ConstraintName := ColDef;
            AStructure.UniqueConstraints[IdxPos].Columns := SegCol;
          end
          else if SegCol <> '' then
            AStructure.UniqueConstraints[IdxPos].Columns := AStructure.UniqueConstraints[IdxPos].Columns + ', ' + SegCol;
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { 7. Foreign Keys }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT ' +
      '  TRIM(child_rc.RDB$CONSTRAINT_NAME), ' +
      '  TRIM(cs.RDB$FIELD_NAME), ' +
      '  TRIM(parent_rc.RDB$RELATION_NAME), ' +
      '  TRIM(ps.RDB$FIELD_NAME), ' +
      '  TRIM(COALESCE(ref.RDB$UPDATE_RULE, '''')), ' +
      '  TRIM(COALESCE(ref.RDB$DELETE_RULE, '''')) ' +
      'FROM RDB$RELATION_CONSTRAINTS child_rc ' +
      'JOIN RDB$REF_CONSTRAINTS ref ON ref.RDB$CONSTRAINT_NAME = child_rc.RDB$CONSTRAINT_NAME ' +
      'JOIN RDB$RELATION_CONSTRAINTS parent_rc ON parent_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONST_NAME_UQ ' +
      'JOIN RDB$INDEX_SEGMENTS cs ON cs.RDB$INDEX_NAME = child_rc.RDB$INDEX_NAME ' +
      'JOIN RDB$INDEX_SEGMENTS ps ON ps.RDB$INDEX_NAME = parent_rc.RDB$INDEX_NAME AND ps.RDB$FIELD_POSITION = cs.RDB$FIELD_POSITION ' +
      'WHERE UPPER(TRIM(child_rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND child_rc.RDB$CONSTRAINT_TYPE = ''FOREIGN KEY'' ' +
      'ORDER BY child_rc.RDB$CONSTRAINT_NAME, cs.RDB$FIELD_POSITION',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          ColDef := Trim(Row[0].AsText);
          SegCol := Trim(Row[1].AsText);
          FldDef := Trim(Row[3].AsText);
          IdxPos := -1;
          for J := 0 to High(AStructure.ForeignKeys) do
            if SameText(AStructure.ForeignKeys[J].ConstraintName, ColDef) then
            begin
              IdxPos := J;
              Break;
            end;
          if IdxPos < 0 then
          begin
            IdxPos := Length(AStructure.ForeignKeys);
            SetLength(AStructure.ForeignKeys, IdxPos + 1);
            AStructure.ForeignKeys[IdxPos].ConstraintName := ColDef;
            AStructure.ForeignKeys[IdxPos].Columns := SegCol;
            AStructure.ForeignKeys[IdxPos].RefTable := Trim(Row[2].AsText);
            AStructure.ForeignKeys[IdxPos].RefColumns := FldDef;
            AStructure.ForeignKeys[IdxPos].UpdateRule := Trim(Row[4].AsText);
            AStructure.ForeignKeys[IdxPos].DeleteRule := Trim(Row[5].AsText);
          end
          else
          begin
            if SegCol <> '' then
              AStructure.ForeignKeys[IdxPos].Columns := AStructure.ForeignKeys[IdxPos].Columns + ', ' + SegCol;
            if FldDef <> '' then
              AStructure.ForeignKeys[IdxPos].RefColumns := AStructure.ForeignKeys[IdxPos].RefColumns + ', ' + FldDef;
          end;
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { 8. Check Constraints }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(rc.RDB$CONSTRAINT_NAME), t.RDB$TRIGGER_SOURCE ' +
      'FROM RDB$RELATION_CONSTRAINTS rc ' +
      'JOIN RDB$CHECK_CONSTRAINTS cc ON cc.RDB$CONSTRAINT_NAME = rc.RDB$CONSTRAINT_NAME ' +
      'JOIN RDB$TRIGGERS t ON t.RDB$TRIGGER_NAME = cc.RDB$TRIGGER_NAME ' +
      'WHERE UPPER(TRIM(rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND rc.RDB$CONSTRAINT_TYPE = ''CHECK'' ' +
      'ORDER BY 1',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          ColDef := Trim(Row[0].AsText);
          IdxPos := -1;
          for J := 0 to High(AStructure.CheckConstraints) do
            if SameText(AStructure.CheckConstraints[J].ConstraintName, ColDef) then
            begin
              IdxPos := J;
              Break;
            end;
          if (IdxPos < 0) and (Trim(Row[1].AsText) <> '') then
          begin
            IdxPos := Length(AStructure.CheckConstraints);
            SetLength(AStructure.CheckConstraints, IdxPos + 1);
            AStructure.CheckConstraints[IdxPos].ConstraintName := ColDef;
            AStructure.CheckConstraints[IdxPos].CheckSource := Trim(Row[1].AsText);
          end;
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;
end;

procedure TManageTableStructureUseCase.LoadPostgresStructure(
  const ASession: IDatabaseSession;
  const ATableName: string;
  const AStructure: TTableStructure
);
var
  SafeTbl, IndexDefStr, PgEvents: string;
  Res: TQueryResult;
  I, PgTrigType: Integer;
  Row: TQueryRow;
  Col: TTableColumnInfo;
  IdxInfo: TTableIndexInfo;
  TrigItem: TTableTriggerInfo;
begin
  SafeTbl := EscapeSqlStr(ATableName);

  { 1. Colunas }
  Res := ExecuteQuery(ASession, Format(
    'SELECT ' +
    '  a.attnum, ' +
    '  a.attname, ' +
    '  format_type(a.atttypid, a.atttypmod), ' +
    '  CASE WHEN t.typtype = ''d'' THEN t.typname ELSE '''' END, ' +
    '  COALESCE(pg_get_expr(ad.adbin, ad.adrelid), ''''), ' +
    '  a.attnotnull, ' +
    '  EXISTS ( ' +
    '    SELECT 1 FROM pg_constraint con ' +
    '    WHERE con.conrelid = c.oid AND con.contype = ''p'' AND a.attnum = ANY(con.conkey) ' +
    '  ) AS is_pk, ' +
    '  COALESCE(col_description(c.oid, a.attnum), '''') ' +
    'FROM pg_attribute a ' +
    'JOIN pg_class c ON c.oid = a.attrelid ' +
    'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'JOIN pg_type t ON t.oid = a.atttypid ' +
    'LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum ' +
    'WHERE n.nspname = current_schema() AND lower(c.relname) = lower(''%s'') ' +
    '  AND a.attnum > 0 AND NOT a.attisdropped ' +
    'ORDER BY a.attnum',
    [SafeTbl]
  ));
  try
    if (Res <> nil) and Res.HasResultSet then
    begin
      SetLength(AStructure.Columns, Res.RowCount);
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        Col.Position := StrToIntDef(Trim(Row[0].AsText), I + 1);
        Col.ColumnName := Trim(Row[1].AsText);
        Col.DataType := Trim(Row[2].AsText);
        Col.DomainName := Trim(Row[3].AsText);
        Col.DefaultValue := Trim(Row[4].AsText);
        Col.NotNull := SameText(Trim(Row[5].AsText), 't') or SameText(Trim(Row[5].AsText), 'true') or (Trim(Row[5].AsText) = '1');
        Col.IsPrimaryKey := SameText(Trim(Row[6].AsText), 't') or SameText(Trim(Row[6].AsText), 'true') or (Trim(Row[6].AsText) = '1');
        Col.ComputedSource := '';
        Col.IsComputed := False;
        Col.Description := Trim(Row[7].AsText);
        AStructure.Columns[I] := Col;
      end;
    end;
  finally
    Res.Free;
  end;

  { 2. Índices }
  Res := ExecuteQuery(ASession, Format(
    'SELECT ' +
    '  idx_cls.relname, ' +
    '  COALESCE(string_agg(att.attname, '', '' ORDER BY ord.pos), ''''), ' +
    '  COALESCE(pg_get_indexdef(idx.indexrelid), ''''), ' +
    '  idx.indisunique, ' +
    '  idx.indisprimary, ' +
    '  idx.indisvalid, ' +
    '  COALESCE((SELECT con.conname FROM pg_constraint con WHERE con.conindid = idx.indexrelid LIMIT 1), '''') ' +
    'FROM pg_index idx ' +
    'JOIN pg_class tbl ON tbl.oid = idx.indrelid ' +
    'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
    'JOIN pg_class idx_cls ON idx_cls.oid = idx.indexrelid ' +
    'LEFT JOIN LATERAL unnest(idx.indkey) WITH ORDINALITY AS ord(attnum, pos) ON true ' +
    'LEFT JOIN pg_attribute att ON att.attrelid = tbl.oid AND att.attnum = ord.attnum AND ord.attnum > 0 ' +
    'WHERE n.nspname = current_schema() AND lower(tbl.relname) = lower(''%s'') ' +
    'GROUP BY idx_cls.relname, idx.indexrelid, idx.indisunique, idx.indisprimary, idx.indisvalid ' +
    'ORDER BY idx_cls.relname',
    [SafeTbl]
  ));
  try
    if (Res <> nil) and Res.HasResultSet then
    begin
      SetLength(AStructure.Indexes, Res.RowCount);
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        IdxInfo.IndexName := Trim(Row[0].AsText);
        IdxInfo.Columns := Trim(Row[1].AsText);
        IndexDefStr := Trim(Row[2].AsText);
        IdxInfo.ExpressionSource := '';
        if IdxInfo.Columns = '' then
          IdxInfo.ExpressionSource := IndexDefStr;
        IdxInfo.IsUnique := SameText(Trim(Row[3].AsText), 't') or SameText(Trim(Row[3].AsText), 'true') or (Trim(Row[3].AsText) = '1');
        IdxInfo.IsPrimaryKey := SameText(Trim(Row[4].AsText), 't') or SameText(Trim(Row[4].AsText), 'true') or (Trim(Row[4].AsText) = '1');
        IdxInfo.IsActive := SameText(Trim(Row[5].AsText), 't') or SameText(Trim(Row[5].AsText), 'true') or (Trim(Row[5].AsText) = '1');
        IdxInfo.ConstraintName := Trim(Row[6].AsText);
        IdxInfo.IsForeignKey := False;
        IdxInfo.IsDescending := Pos(' DESC', UpperCase(IndexDefStr)) > 0;
        AStructure.Indexes[I] := IdxInfo;
      end;
    end;
  finally
    Res.Free;
  end;

  { 3. Dependências: Views que usam a tabela }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT vc.relname, CASE WHEN vc.relkind = ''m'' THEN ''MATERIALIZED VIEW'' ELSE ''VIEW'' END ' +
      'FROM pg_depend d ' +
      'JOIN pg_rewrite rw ON rw.oid = d.objid ' +
      'JOIN pg_class vc ON vc.oid = rw.ev_class ' +
      'JOIN pg_class tbl ON tbl.oid = d.refobjid ' +
      'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
      'WHERE n.nspname = current_schema() AND lower(tbl.relname) = lower(''%s'') AND vc.oid <> tbl.oid ' +
      'ORDER BY 1',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(AStructure, tddDependentOnTable, Row[0].AsText, Row[1].AsText, '');
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { Tabelas filhas por Foreign Key }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT child_tbl.relname, con.conname ' +
      'FROM pg_constraint con ' +
      'JOIN pg_class child_tbl ON child_tbl.oid = con.conrelid ' +
      'JOIN pg_class parent_tbl ON parent_tbl.oid = con.confrelid ' +
      'JOIN pg_namespace n ON n.oid = parent_tbl.relnamespace ' +
      'WHERE con.contype = ''f'' AND n.nspname = current_schema() AND lower(parent_tbl.relname) = lower(''%s'') ' +
      'ORDER BY 1, 2',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(AStructure, tddDependentOnTable, Row[0].AsText, 'FOREIGN KEY (Tabela Filha)', 'FK: ' + Trim(Row[1].AsText));
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { Triggers nesta tabela }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT ' +
      '  tg.tgname, ' +
      '  tg.tgenabled::text, ' +
      '  tg.tgtype, ' +
      '  COALESCE(p.proname, ''''), ' +
      '  COALESCE(pg_get_triggerdef(tg.oid, true), '''') ' +
      'FROM pg_trigger tg ' +
      'JOIN pg_class tbl ON tbl.oid = tg.tgrelid ' +
      'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
      'LEFT JOIN pg_proc p ON p.oid = tg.tgfoid ' +
      'WHERE NOT tg.tgisinternal AND n.nspname = current_schema() AND lower(tbl.relname) = lower(''%s'') ' +
      'ORDER BY tg.tgname',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        SetLength(AStructure.Triggers, Res.RowCount);
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          PgTrigType := StrToIntDef(Trim(Row[2].AsText), 0);
          TrigItem := Default(TTableTriggerInfo);
          TrigItem.TriggerName := Trim(Row[0].AsText);
          TrigItem.IsActive := not SameText(Trim(Row[1].AsText), 'D');
          if (PgTrigType and 64) <> 0 then
            TrigItem.Timing := 'INSTEAD OF'
          else if (PgTrigType and 2) <> 0 then
            TrigItem.Timing := 'BEFORE'
          else
            TrigItem.Timing := 'AFTER';
          TrigItem.HasInsert := (PgTrigType and 4) <> 0;
          TrigItem.HasDelete := (PgTrigType and 8) <> 0;
          TrigItem.HasUpdate := (PgTrigType and 16) <> 0;
          PgEvents := BuildTriggerEventsClause(
            TrigItem.HasInsert,
            TrigItem.HasUpdate,
            TrigItem.HasDelete
          );
          if (PgTrigType and 32) <> 0 then
          begin
            if PgEvents <> '' then
              PgEvents := PgEvents + ' OR ';
            PgEvents := PgEvents + 'TRUNCATE';
          end;
          if PgEvents = '' then
            PgEvents := 'INSERT';
          TrigItem.Events := PgEvents;
          TrigItem.Position := 0;
          TrigItem.FunctionName := Trim(Row[3].AsText);
          TrigItem.SourceBody := TrimRight(Row[4].AsText);
          if (TrigItem.SourceBody <> '') and (TrigItem.SourceBody[Length(TrigItem.SourceBody)] <> ';') then
            TrigItem.SourceBody := TrigItem.SourceBody + ';';
          TrigItem.FullDDL := TrigItem.SourceBody;
          AStructure.Triggers[I] := TrigItem;

          AddUniqueDependency(
            AStructure,
            tddDependentOnTable,
            TrigItem.TriggerName,
            'TRIGGER',
            'Função: ' + TrigItem.FunctionName
          );
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { 4. Esta tabela depende de: Tabelas pai por FK }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT parent_tbl.relname, con.conname ' +
      'FROM pg_constraint con ' +
      'JOIN pg_class child_tbl ON child_tbl.oid = con.conrelid ' +
      'JOIN pg_class parent_tbl ON parent_tbl.oid = con.confrelid ' +
      'JOIN pg_namespace n ON n.oid = child_tbl.relnamespace ' +
      'WHERE con.contype = ''f'' AND n.nspname = current_schema() AND lower(child_tbl.relname) = lower(''%s'') ' +
      'ORDER BY 1, 2',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(AStructure, tddTableDependsOn, Row[0].AsText, 'FOREIGN KEY (Tabela Pai)', 'FK: ' + Trim(Row[1].AsText));
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { Sequences / Domínios usados pela tabela }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT seq.relname, ''SEQUENCE'' ' +
      'FROM pg_depend d ' +
      'JOIN pg_class seq ON seq.oid = d.objid AND seq.relkind = ''S'' ' +
      'JOIN pg_class tbl ON tbl.oid = d.refobjid ' +
      'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
      'WHERE n.nspname = current_schema() AND lower(tbl.relname) = lower(''%s'') ' +
      'ORDER BY 1',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependency(AStructure, tddTableDependsOn, Row[0].AsText, Row[1].AsText, 'Owned / Default');
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  for I := 0 to High(AStructure.Columns) do
  begin
    if AStructure.Columns[I].DomainName <> '' then
      AddUniqueDependency(AStructure, tddTableDependsOn, AStructure.Columns[I].DomainName, 'DOMAIN', 'Campo: ' + AStructure.Columns[I].ColumnName);
  end;

  { 5. Constraints (PK, UNIQUE, CHECK, FOREIGN KEY) }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT ' +
      '  con.conname, ' +
      '  con.contype::text, ' +
      '  COALESCE((SELECT string_agg(a.attname, '', '' ORDER BY ord.pos) ' +
      '            FROM unnest(con.conkey) WITH ORDINALITY AS ord(attnum, pos) ' +
      '            JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ord.attnum), ''''), ' +
      '  COALESCE(ref_tbl.relname, ''''), ' +
      '  COALESCE((SELECT string_agg(pa.attname, '', '' ORDER BY pord.pos) ' +
      '            FROM unnest(con.confkey) WITH ORDINALITY AS pord(attnum, pos) ' +
      '            JOIN pg_attribute pa ON pa.attrelid = con.confrelid AND pa.attnum = pord.attnum), ''''), ' +
      '  CASE con.confupdtype WHEN ''c'' THEN ''CASCADE'' WHEN ''n'' THEN ''SET NULL'' WHEN ''d'' THEN ''SET DEFAULT'' WHEN ''r'' THEN ''RESTRICT'' ELSE ''NO ACTION'' END, ' +
      '  CASE con.confdeltype WHEN ''c'' THEN ''CASCADE'' WHEN ''n'' THEN ''SET NULL'' WHEN ''d'' THEN ''SET DEFAULT'' WHEN ''r'' THEN ''RESTRICT'' ELSE ''NO ACTION'' END, ' +
      '  pg_get_constraintdef(con.oid, true) ' +
      'FROM pg_constraint con ' +
      'JOIN pg_class c ON c.oid = con.conrelid ' +
      'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'LEFT JOIN pg_class ref_tbl ON ref_tbl.oid = con.confrelid ' +
      'WHERE n.nspname = current_schema() AND lower(c.relname) = lower(''%s'') ' +
      'ORDER BY con.contype, con.conname',
      [SafeTbl]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          IndexDefStr := Trim(Row[1].AsText);
          if IndexDefStr = 'p' then
          begin
            AStructure.PrimaryKeyName := Trim(Row[0].AsText);
            AStructure.PrimaryKeyColumns := Trim(Row[2].AsText);
          end
          else if IndexDefStr = 'u' then
          begin
            SetLength(AStructure.UniqueConstraints, Length(AStructure.UniqueConstraints) + 1);
            AStructure.UniqueConstraints[High(AStructure.UniqueConstraints)].ConstraintName := Trim(Row[0].AsText);
            AStructure.UniqueConstraints[High(AStructure.UniqueConstraints)].Columns := Trim(Row[2].AsText);
          end
          else if IndexDefStr = 'f' then
          begin
            SetLength(AStructure.ForeignKeys, Length(AStructure.ForeignKeys) + 1);
            AStructure.ForeignKeys[High(AStructure.ForeignKeys)].ConstraintName := Trim(Row[0].AsText);
            AStructure.ForeignKeys[High(AStructure.ForeignKeys)].Columns := Trim(Row[2].AsText);
            AStructure.ForeignKeys[High(AStructure.ForeignKeys)].RefTable := Trim(Row[3].AsText);
            AStructure.ForeignKeys[High(AStructure.ForeignKeys)].RefColumns := Trim(Row[4].AsText);
            AStructure.ForeignKeys[High(AStructure.ForeignKeys)].UpdateRule := Trim(Row[5].AsText);
            AStructure.ForeignKeys[High(AStructure.ForeignKeys)].DeleteRule := Trim(Row[6].AsText);
          end
          else if IndexDefStr = 'c' then
          begin
            SetLength(AStructure.CheckConstraints, Length(AStructure.CheckConstraints) + 1);
            AStructure.CheckConstraints[High(AStructure.CheckConstraints)].ConstraintName := Trim(Row[0].AsText);
            AStructure.CheckConstraints[High(AStructure.CheckConstraints)].CheckSource := Trim(Row[7].AsText);
          end;
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;
end;

procedure TManageTableStructureUseCase.LoadFirebirdFieldDependencies(
  const ASession: IDatabaseSession;
  const ATableName, AFieldName: string;
  var ATarget: TTableDependencyInfoArray
);
var
  SafeTbl, SafeCol, KindStr, ConType: string;
  Res: TQueryResult;
  I: Integer;
  Row: TQueryRow;
begin
  SafeTbl := EscapeSqlStr(ATableName);
  SafeCol := EscapeSqlStr(AFieldName);

  { 1. Objetos em RDB$DEPENDENCIES que referenciam especificamente este campo }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(d.RDB$DEPENDENT_NAME), d.RDB$DEPENDENT_TYPE ' +
      'FROM RDB$DEPENDENCIES d ' +
      'WHERE UPPER(TRIM(d.RDB$DEPENDED_ON_NAME)) = UPPER(''%s'') ' +
      '  AND UPPER(TRIM(COALESCE(d.RDB$FIELD_NAME, ''''))) = UPPER(''%s'') ' +
      'ORDER BY 2, 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependencyToArray(
            ATarget,
            tddDependentOnTable,
            Row[0].AsText,
            DecodeFirebirdDependencyType(StrToIntDef(Trim(Row[1].AsText), -1))
          );
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { 2. Índices / Constraints que utilizam este campo }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(i.RDB$INDEX_NAME), TRIM(COALESCE(rc.RDB$CONSTRAINT_TYPE, '''')) ' +
      'FROM RDB$INDEX_SEGMENTS s ' +
      'JOIN RDB$INDICES i ON i.RDB$INDEX_NAME = s.RDB$INDEX_NAME ' +
      'LEFT JOIN RDB$RELATION_CONSTRAINTS rc ON rc.RDB$INDEX_NAME = i.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(i.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND UPPER(TRIM(s.RDB$FIELD_NAME)) = UPPER(''%s'') ' +
      '  AND COALESCE(i.RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          ConType := UpperCase(Trim(Row[1].AsText));
          if (ConType = 'PRIMARY KEY') or (ConType = 'FOREIGN KEY') or (ConType = 'UNIQUE') then
            KindStr := ConType
          else
            KindStr := 'INDEX';
          AddUniqueDependencyToArray(ATarget, tddDependentOnTable, Row[0].AsText, KindStr);
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;

  { 3. Tabelas filhas por Foreign Key referenciando este campo }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(child_rc.RDB$RELATION_NAME) ' +
      'FROM RDB$REF_CONSTRAINTS ref ' +
      'JOIN RDB$RELATION_CONSTRAINTS parent_rc ON parent_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONST_NAME_UQ ' +
      'JOIN RDB$RELATION_CONSTRAINTS child_rc ON child_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONSTRAINT_NAME ' +
      'JOIN RDB$INDEX_SEGMENTS ps ON ps.RDB$INDEX_NAME = parent_rc.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(parent_rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND UPPER(TRIM(ps.RDB$FIELD_NAME)) = UPPER(''%s'') ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
        for I := 0 to Res.RowCount - 1 do
          AddUniqueDependencyToArray(ATarget, tddDependentOnTable, Res.GetRow(I)[0].AsText, 'FOREIGN KEY (Tabela Filha)');
    finally
      Res.Free;
    end;
  except
  end;

  { 4. Tabelas pai referenciadas por Foreign Key neste campo }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT TRIM(parent_rc.RDB$RELATION_NAME) ' +
      'FROM RDB$REF_CONSTRAINTS ref ' +
      'JOIN RDB$RELATION_CONSTRAINTS child_rc ON child_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONSTRAINT_NAME ' +
      'JOIN RDB$RELATION_CONSTRAINTS parent_rc ON parent_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONST_NAME_UQ ' +
      'JOIN RDB$INDEX_SEGMENTS cs ON cs.RDB$INDEX_NAME = child_rc.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(child_rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND UPPER(TRIM(cs.RDB$FIELD_NAME)) = UPPER(''%s'') ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
        for I := 0 to Res.RowCount - 1 do
          AddUniqueDependencyToArray(ATarget, tddTableDependsOn, Res.GetRow(I)[0].AsText, 'FOREIGN KEY (Tabela Pai)');
    finally
      Res.Free;
    end;
  except
  end;

  { 5. Domain customizado usado por este campo }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT TRIM(rf.RDB$FIELD_SOURCE) ' +
      'FROM RDB$RELATION_FIELDS rf ' +
      'WHERE UPPER(TRIM(rf.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND UPPER(TRIM(rf.RDB$FIELD_NAME)) = UPPER(''%s'')',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet and (Res.RowCount > 0) then
      begin
        KindStr := Trim(Res.GetRow(0)[0].AsText);
        if (KindStr <> '') and (Pos('RDB$', UpperCase(KindStr)) <> 1) then
          AddUniqueDependencyToArray(ATarget, tddTableDependsOn, KindStr, 'DOMAIN');
      end;
    finally
      Res.Free;
    end;
  except
  end;
end;

procedure TManageTableStructureUseCase.LoadPostgresFieldDependencies(
  const ASession: IDatabaseSession;
  const ATableName, AFieldName: string;
  var ATarget: TTableDependencyInfoArray
);
var
  SafeTbl, SafeCol, KindStr: string;
  Res: TQueryResult;
  I: Integer;
  Row: TQueryRow;
begin
  SafeTbl := EscapeSqlStr(ATableName);
  SafeCol := EscapeSqlStr(AFieldName);

  { 1. Views e Materialized Views usando exatamente esta coluna }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT vc.relname, CASE WHEN vc.relkind = ''m'' THEN ''MATERIALIZED VIEW'' ELSE ''VIEW'' END ' +
      'FROM pg_depend d ' +
      'JOIN pg_rewrite rw ON rw.oid = d.objid ' +
      'JOIN pg_class vc ON vc.oid = rw.ev_class ' +
      'JOIN pg_class tbl ON tbl.oid = d.refobjid ' +
      'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
      'JOIN pg_attribute att ON att.attrelid = tbl.oid AND att.attnum = d.refobjsubid ' +
      'WHERE n.nspname = current_schema() AND lower(tbl.relname) = lower(''%s'') ' +
      '  AND lower(att.attname) = lower(''%s'') AND vc.oid <> tbl.oid ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependencyToArray(ATarget, tddDependentOnTable, Row[0].AsText, Row[1].AsText);
        end;
    finally
      Res.Free;
    end;
  except
  end;

  { 2. Índices contendo esta coluna }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT idx_cls.relname, CASE WHEN idx.indisprimary THEN ''PRIMARY KEY'' WHEN idx.indisunique THEN ''UNIQUE'' ELSE ''INDEX'' END ' +
      'FROM pg_index idx ' +
      'JOIN pg_class tbl ON tbl.oid = idx.indrelid ' +
      'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
      'JOIN pg_class idx_cls ON idx_cls.oid = idx.indexrelid ' +
      'JOIN pg_attribute att ON att.attrelid = tbl.oid AND att.attnum = ANY(idx.indkey) ' +
      'WHERE n.nspname = current_schema() AND lower(tbl.relname) = lower(''%s'') ' +
      '  AND lower(att.attname) = lower(''%s'') ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
        for I := 0 to Res.RowCount - 1 do
        begin
          Row := Res.GetRow(I);
          AddUniqueDependencyToArray(ATarget, tddDependentOnTable, Row[0].AsText, Row[1].AsText);
        end;
    finally
      Res.Free;
    end;
  except
  end;

  { 3. Tabelas filhas por FK referenciando esta coluna }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT child_tbl.relname ' +
      'FROM pg_constraint con ' +
      'JOIN pg_class parent_tbl ON parent_tbl.oid = con.confrelid ' +
      'JOIN pg_class child_tbl ON child_tbl.oid = con.conrelid ' +
      'JOIN pg_namespace n ON n.oid = parent_tbl.relnamespace ' +
      'JOIN pg_attribute att ON att.attrelid = parent_tbl.oid AND att.attnum = ANY(con.confkey) ' +
      'WHERE con.contype = ''f'' AND n.nspname = current_schema() ' +
      '  AND lower(parent_tbl.relname) = lower(''%s'') AND lower(att.attname) = lower(''%s'') ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
        for I := 0 to Res.RowCount - 1 do
          AddUniqueDependencyToArray(ATarget, tddDependentOnTable, Res.GetRow(I)[0].AsText, 'FOREIGN KEY (Tabela Filha)');
    finally
      Res.Free;
    end;
  except
  end;

  { 4. Tabelas pai por FK neste campo }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT parent_tbl.relname ' +
      'FROM pg_constraint con ' +
      'JOIN pg_class child_tbl ON child_tbl.oid = con.conrelid ' +
      'JOIN pg_class parent_tbl ON parent_tbl.oid = con.confrelid ' +
      'JOIN pg_namespace n ON n.oid = child_tbl.relnamespace ' +
      'JOIN pg_attribute att ON att.attrelid = child_tbl.oid AND att.attnum = ANY(con.conkey) ' +
      'WHERE con.contype = ''f'' AND n.nspname = current_schema() ' +
      '  AND lower(child_tbl.relname) = lower(''%s'') AND lower(att.attname) = lower(''%s'') ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
        for I := 0 to Res.RowCount - 1 do
          AddUniqueDependencyToArray(ATarget, tddTableDependsOn, Res.GetRow(I)[0].AsText, 'FOREIGN KEY (Tabela Pai)');
    finally
      Res.Free;
    end;
  except
  end;

  { 5. Triggers por coluna (UPDATE OF coluna) e Domain }
  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT DISTINCT tg.tgname ' +
      'FROM pg_trigger tg ' +
      'JOIN pg_class tbl ON tbl.oid = tg.tgrelid ' +
      'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
      'JOIN pg_attribute att ON att.attrelid = tbl.oid AND att.attnum = ANY(tg.tgattr) ' +
      'WHERE NOT tg.tgisinternal AND n.nspname = current_schema() ' +
      '  AND lower(tbl.relname) = lower(''%s'') AND lower(att.attname) = lower(''%s'') ' +
      'ORDER BY 1',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet then
        for I := 0 to Res.RowCount - 1 do
          AddUniqueDependencyToArray(ATarget, tddDependentOnTable, Res.GetRow(I)[0].AsText, 'TRIGGER');
    finally
      Res.Free;
    end;
  except
  end;

  try
    Res := ExecuteQuery(ASession, Format(
      'SELECT t.typname ' +
      'FROM pg_attribute a ' +
      'JOIN pg_class c ON c.oid = a.attrelid ' +
      'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'JOIN pg_type t ON t.oid = a.atttypid ' +
      'WHERE n.nspname = current_schema() AND lower(c.relname) = lower(''%s'') ' +
      '  AND lower(a.attname) = lower(''%s'') AND t.typtype = ''d''',
      [SafeTbl, SafeCol]
    ));
    try
      if (Res <> nil) and Res.HasResultSet and (Res.RowCount > 0) then
      begin
        KindStr := Trim(Res.GetRow(0)[0].AsText);
        if KindStr <> '' then
          AddUniqueDependencyToArray(ATarget, tddTableDependsOn, KindStr, 'DOMAIN');
      end;
    finally
      Res.Free;
    end;
  except
  end;
end;

function TManageTableStructureUseCase.LoadTableDDL(
  const AProfile: TConnectionProfile;
  const ATableName: string;
  const AIncludeIndexes: Boolean
): string;
var
  Struct: TTableStructure;
begin
  Result := '';
  if (AProfile = nil) or (Trim(ATableName) = '') then
    Exit;

  Struct := LoadTableStructure(AProfile, ATableName);
  try
    Result := GenerateTableDDL(AProfile.DatabaseType, Struct, AIncludeIndexes);
  finally
    Struct.Free;
  end;
end;

function TManageTableStructureUseCase.LoadFieldDependencies(
  const AProfile: TConnectionProfile;
  const ATableName, AFieldName: string
): TTableDependencyInfoArray;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
begin
  Result := nil;
  if (AProfile = nil) or (FFactory = nil) or (Trim(ATableName) = '') or (Trim(AFieldName) = '') then
    Exit;

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    Session.Connect;
    if AProfile.DatabaseType = dtPostgreSQL then
      LoadPostgresFieldDependencies(Session, Trim(ATableName), Trim(AFieldName), Result)
    else
      LoadFirebirdFieldDependencies(Session, Trim(ATableName), Trim(AFieldName), Result);
  finally
    Session.Disconnect;
  end;
end;

procedure TManageTableStructureUseCase.LoadMariaDbStructure(
  const ASession: IDatabaseSession;
  const ATableName: string;
  const AStructure: TTableStructure
);
var
  SafeTbl, CType: string;
  Res: TQueryResult;
  I, K: Integer;
  Row: TQueryRow;
  Col: TTableColumnInfo;
  IdxInfo: TTableIndexInfo;
  FkInfo: TTableForeignKeyInfo;
  UqInfo: TTableUniqueConstraintInfo;
  TrigInfo: TTableTriggerInfo;
begin
  SafeTbl := StringReplace(ATableName, '''', '''''', [rfReplaceAll]);

  { 1. Colunas }
  Res := ExecuteQuery(ASession, Format(
    'SELECT ordinal_position, column_name, column_type, '''', COALESCE(column_default, ''''), ' +
    '  CASE WHEN is_nullable = ''NO'' THEN 1 ELSE 0 END, ' +
    '  CASE WHEN column_key = ''PRI'' THEN 1 ELSE 0 END, ' +
    '  COALESCE(generation_expression, ''''), ' +
    '  COALESCE(column_comment, '''') ' +
    'FROM information_schema.columns ' +
    'WHERE table_schema = DATABASE() AND LOWER(table_name) = LOWER(''%s'') ' +
    'ORDER BY ordinal_position',
    [SafeTbl]
  ));
  try
    if (Res <> nil) and Res.HasResultSet then
    begin
      SetLength(AStructure.Columns, Res.RowCount);
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        Col.Position := StrToIntDef(Trim(Row[0].AsText), I + 1);
        Col.ColumnName := Trim(Row[1].AsText);
        Col.DataType := Trim(Row[2].AsText);
        Col.DomainName := '';
        Col.DefaultValue := Trim(Row[4].AsText);
        Col.NotNull := Trim(Row[5].AsText) = '1';
        Col.IsPrimaryKey := Trim(Row[6].AsText) = '1';
        Col.ComputedSource := Trim(Row[7].AsText);
        Col.IsComputed := Col.ComputedSource <> '';
        Col.Description := Trim(Row[8].AsText);
        AStructure.Columns[I] := Col;
      end;
    end;
  finally
    Res.Free;
  end;

  { 2. Índices }
  Res := ExecuteQuery(ASession, Format(
    'SELECT index_name, ' +
    '  COALESCE(GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR '', ''), ''''), ' +
    '  MAX(CASE WHEN non_unique = 0 THEN 1 ELSE 0 END), ' +
    '  MAX(CASE WHEN index_name = ''PRIMARY'' THEN 1 ELSE 0 END) ' +
    'FROM information_schema.statistics ' +
    'WHERE table_schema = DATABASE() AND LOWER(table_name) = LOWER(''%s'') ' +
    'GROUP BY index_name ' +
    'ORDER BY index_name',
    [SafeTbl]
  ));
  try
    if (Res <> nil) and Res.HasResultSet then
    begin
      SetLength(AStructure.Indexes, Res.RowCount);
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        IdxInfo.IndexName := Trim(Row[0].AsText);
        IdxInfo.Columns := Trim(Row[1].AsText);
        IdxInfo.ExpressionSource := '';
        IdxInfo.IsUnique := Trim(Row[2].AsText) = '1';
        IdxInfo.IsPrimaryKey := Trim(Row[3].AsText) = '1';
        IdxInfo.IsActive := True;
        IdxInfo.ConstraintName := IdxInfo.IndexName;
        IdxInfo.IsForeignKey := False;
        IdxInfo.IsDescending := False;
        AStructure.Indexes[I] := IdxInfo;
      end;
    end;
  finally
    Res.Free;
  end;

  { 3. Constraints (PK / FK / Unique) }
  Res := ExecuteQuery(ASession, Format(
    'SELECT tc.constraint_name, tc.constraint_type, ' +
    '  COALESCE(GROUP_CONCAT(kcu.column_name ORDER BY kcu.ordinal_position SEPARATOR '', ''), ''''), ' +
    '  COALESCE(MAX(kcu.referenced_table_name), ''''), ' +
    '  COALESCE(GROUP_CONCAT(kcu.referenced_column_name ORDER BY kcu.ordinal_position SEPARATOR '', ''), '''') ' +
    'FROM information_schema.table_constraints tc ' +
    'LEFT JOIN information_schema.key_column_usage kcu ' +
    '  ON kcu.constraint_schema = tc.constraint_schema ' +
    ' AND kcu.table_name = tc.table_name ' +
    ' AND kcu.constraint_name = tc.constraint_name ' +
    'WHERE tc.table_schema = DATABASE() AND LOWER(tc.table_name) = LOWER(''%s'') ' +
    'GROUP BY tc.constraint_name, tc.constraint_type ' +
    'ORDER BY tc.constraint_type, tc.constraint_name',
    [SafeTbl]
  ));
  try
    if (Res <> nil) and Res.HasResultSet then
    begin
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        CType := UpperCase(Trim(Row[1].AsText));
        if CType = 'PRIMARY KEY' then
        begin
          AStructure.PrimaryKeyName := Trim(Row[0].AsText);
          AStructure.PrimaryKeyColumns := Trim(Row[2].AsText);
        end
        else if CType = 'FOREIGN KEY' then
        begin
          FkInfo := Default(TTableForeignKeyInfo);
          FkInfo.ConstraintName := Trim(Row[0].AsText);
          FkInfo.Columns := Trim(Row[2].AsText);
          FkInfo.RefTable := Trim(Row[3].AsText);
          FkInfo.RefColumns := Trim(Row[4].AsText);
          K := Length(AStructure.ForeignKeys);
          SetLength(AStructure.ForeignKeys, K + 1);
          AStructure.ForeignKeys[K] := FkInfo;
        end
        else if CType = 'UNIQUE' then
        begin
          UqInfo := Default(TTableUniqueConstraintInfo);
          UqInfo.ConstraintName := Trim(Row[0].AsText);
          UqInfo.Columns := Trim(Row[2].AsText);
          K := Length(AStructure.UniqueConstraints);
          SetLength(AStructure.UniqueConstraints, K + 1);
          AStructure.UniqueConstraints[K] := UqInfo;
        end;
      end;
    end;
  finally
    Res.Free;
  end;

  { 4. Triggers }
  Res := ExecuteQuery(ASession, Format(
    'SELECT trigger_name, CONCAT(action_timing, '' '', event_manipulation), action_statement ' +
    'FROM information_schema.triggers ' +
    'WHERE trigger_schema = DATABASE() AND LOWER(event_object_table) = LOWER(''%s'') ' +
    'ORDER BY trigger_name',
    [SafeTbl]
  ));
  try
    if (Res <> nil) and Res.HasResultSet then
    begin
      SetLength(AStructure.Triggers, Res.RowCount);
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        TrigInfo := Default(TTableTriggerInfo);
        TrigInfo.TriggerName := Trim(Row[0].AsText);
        TrigInfo.Timing := Trim(Row[1].AsText);
        TrigInfo.Events := '';
        TrigInfo.IsActive := True;
        TrigInfo.SourceBody := Trim(Row[2].AsText);
        TrigInfo.FullDDL := TrigInfo.SourceBody;
        AStructure.Triggers[I] := TrigInfo;
      end;
    end;
  finally
    Res.Free;
  end;
end;

function TManageTableStructureUseCase.LoadTableStructure(
  const AProfile: TConnectionProfile;
  const ATableName: string
): TTableStructure;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
begin
  Result := TTableStructure.Create;
  Result.TableName := Trim(ATableName);
  if (AProfile = nil) or (FFactory = nil) or (Result.TableName = '') then
    Exit;

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    Session.Connect;
    if AProfile.DatabaseType = dtPostgreSQL then
      LoadPostgresStructure(Session, Result.TableName, Result)
    else if AProfile.DatabaseType = dtMariaDB then
      LoadMariaDbStructure(Session, Result.TableName, Result)
    else
      LoadFirebirdStructure(Session, Result.TableName, Result);
  finally
    Session.Disconnect;
  end;
end;

function TManageTableStructureUseCase.AddColumn(
  const AProfile: TConnectionProfile;
  const ATableName, AColumnName, ADataType, ADefaultValue: string;
  const ANotNull: Boolean;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
begin
  if (Trim(AColumnName) = '') or (Trim(ADataType) = '') then
  begin
    AMessage := 'Informe o nome e o tipo do campo.';
    Exit(False);
  end;

  Stmts := TStringList.Create;
  try
    Stmts.Add(BuildAddColumnDDL(AProfile.DatabaseType, ATableName, AColumnName, ADataType, ADefaultValue, ANotNull));
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
      AMessage := Format('Campo "%s" adicionado com sucesso.', [Trim(AColumnName)]);
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.EditColumn(
  const AProfile: TConnectionProfile;
  const ATableName: string;
  const AOldCol: TTableColumnInfo;
  const ANewName, ANewDataType, ANewDefaultValue: string;
  const ANewNotNull: Boolean;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
  IsFB25: Boolean;
begin
  Stmts := TStringList.Create;
  try
    IsFB25 := (AProfile.DatabaseType = dtFirebird) and (AProfile.FirebirdVersion = fv25);
    BuildEditColumnDDL(
      AProfile.DatabaseType,
      ATableName,
      AOldCol,
      ANewName,
      ANewDataType,
      ANewDefaultValue,
      ANewNotNull,
      IsFB25,
      Stmts
    );
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);

    { Caso Firebird esteja em Auto e seja 2.5, ALTER COLUMN SET/DROP NOT NULL falha por sintaxe: faz fallback }
    if (not Result) and (AProfile.DatabaseType = dtFirebird) and
       (AProfile.FirebirdVersion = fvAuto) and (AOldCol.NotNull <> ANewNotNull) and
       ((Pos('token unknown', LowerCase(AMessage)) > 0) or (Pos('-104', AMessage) > 0)) then
    begin
      Stmts.Clear;
      BuildEditColumnDDL(
        AProfile.DatabaseType,
        ATableName,
        AOldCol,
        ANewName,
        ANewDataType,
        ANewDefaultValue,
        ANewNotNull,
        True,
        Stmts
      );
      Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    end;

    if Result then
      AMessage := Format('Campo "%s" atualizado com sucesso.', [Trim(ANewName)]);
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.DropColumn(
  const AProfile: TConnectionProfile;
  const ATableName, AColumnName: string;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
begin
  Stmts := TStringList.Create;
  try
    Stmts.Add(BuildDropColumnDDL(AProfile.DatabaseType, ATableName, AColumnName));
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
      AMessage := Format('Campo "%s" excluído com sucesso.', [Trim(AColumnName)]);
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.CreateIndex(
  const AProfile: TConnectionProfile;
  const ATableName, AIndexName: string;
  const AColumns: TStrings;
  const AUnique, ADescending: Boolean;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
  DDL: string;
begin
  DDL := BuildCreateIndexDDL(AProfile.DatabaseType, ATableName, AIndexName, AColumns, AUnique, ADescending);
  if DDL = '' then
  begin
    AMessage := 'Informe o nome do índice e selecione ao menos uma coluna.';
    Exit(False);
  end;

  Stmts := TStringList.Create;
  try
    Stmts.Add(DDL);
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
      AMessage := Format('Índice "%s" criado com sucesso.', [Trim(AIndexName)]);
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.DropIndex(
  const AProfile: TConnectionProfile;
  const AIndexName: string;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
begin
  Stmts := TStringList.Create;
  try
    Stmts.Add(BuildDropIndexDDL(AProfile.DatabaseType, AIndexName));
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
      AMessage := Format('Índice "%s" excluído com sucesso.', [Trim(AIndexName)]);
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.SetIndexActive(
  const AProfile: TConnectionProfile;
  const AIndexName: string;
  const AActive: Boolean;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
  DDL: string;
begin
  DDL := BuildSetIndexActiveDDL(AProfile.DatabaseType, AIndexName, AActive);
  if DDL = '' then
  begin
    AMessage := 'Ativar/inativar índice é suportado apenas no Firebird.';
    Exit(False);
  end;

  Stmts := TStringList.Create;
  try
    Stmts.Add(DDL);
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
    begin
      if AActive then
        AMessage := Format('Índice "%s" ativado com sucesso.', [Trim(AIndexName)])
      else
        AMessage := Format('Índice "%s" inativado com sucesso.', [Trim(AIndexName)]);
    end;
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.DropTable(
  const AProfile: TConnectionProfile;
  const ATableName: string;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
begin
  Result := False;
  AMessage := '';
  if (AProfile = nil) or (Trim(ATableName) = '') then
  begin
    AMessage := 'Tabela ou conexão inválida.';
    Exit;
  end;

  Stmts := TStringList.Create;
  try
    Stmts.Add('DROP TABLE ' + QuoteDbIdent(AProfile.DatabaseType, Trim(ATableName)));
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
      AMessage := Format('Tabela "%s" excluída com sucesso.', [Trim(ATableName)]);
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.SaveTableTrigger(
  const AProfile: TConnectionProfile;
  const ATableName, AOriginalTriggerName, ATriggerName, ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete, AIsActive: Boolean;
  const APosition: Integer;
  const ACodeText: string;
  const AIsNew: Boolean;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
  DDL, DropName, UpDDL: string;
begin
  Result := False;
  AMessage := '';
  if AProfile = nil then
  begin
    AMessage := 'Conexão inválida.';
    Exit;
  end;
  if Trim(ACodeText) = '' then
  begin
    AMessage := 'Informe o código DDL/PSQL da trigger.';
    Exit;
  end;

  Stmts := TStringList.Create;
  try
    if AProfile.DatabaseType = dtPostgreSQL then
    begin
      DDL := Trim(ACodeText);
      UpDDL := UpperCase(DDL);
      DropName := Trim(AOriginalTriggerName);
      if (not AIsNew) and (DropName <> '') and
         (Pos('DROP TRIGGER', UpDDL) = 0) and
         (Pos('CREATE OR REPLACE TRIGGER', UpDDL) = 0) then
        Stmts.Add(Format(
          'DROP TRIGGER IF EXISTS %s ON %s',
          [QuoteDbIdent(dtPostgreSQL, DropName), QuoteDbIdent(dtPostgreSQL, ATableName)]
        ));
      Stmts.Add(DDL);
      Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
      if Result then
        AMessage := Format('Trigger "%s" compilada com sucesso.', [Trim(ATriggerName)]);
    end
    else
    begin
      if StartsWithSqlKeyword(ACodeText, 'CREATE') or
         StartsWithSqlKeyword(ACodeText, 'RECREATE') or
         StartsWithSqlKeyword(ACodeText, 'ALTER') then
        Stmts.Add(Trim(ACodeText))
      else
      begin
        if Trim(ATriggerName) = '' then
        begin
          AMessage := 'Informe o nome da trigger.';
          Exit;
        end;
        if not (AHasInsert or AHasUpdate or AHasDelete) then
        begin
          AMessage := 'Selecione pelo menos um evento (INSERT, UPDATE ou DELETE).';
          Exit;
        end;
        Stmts.Add(BuildFirebirdTriggerDDL(
          ATableName,
          ATriggerName,
          ATiming,
          AHasInsert,
          AHasUpdate,
          AHasDelete,
          AIsActive,
          APosition,
          ACodeText
        ));
      end;
      Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
      if Result then
      begin
        if Trim(ATriggerName) <> '' then
          AMessage := Format('Trigger "%s" compilada com sucesso.', [Trim(ATriggerName)])
        else
          AMessage := 'Trigger compilada com sucesso.';
      end;
    end;
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.SetTriggerActive(
  const AProfile: TConnectionProfile;
  const ATableName, ATriggerName: string;
  const AActive: Boolean;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
  SQL: string;
begin
  Result := False;
  AMessage := '';
  if (AProfile = nil) or (Trim(ATriggerName) = '') then
  begin
    AMessage := 'Trigger inválida.';
    Exit;
  end;

  if AProfile.DatabaseType = dtPostgreSQL then
  begin
    if AActive then
      SQL := Format('ALTER TABLE %s ENABLE TRIGGER %s', [QuoteDbIdent(dtPostgreSQL, ATableName), QuoteDbIdent(dtPostgreSQL, ATriggerName)])
    else
      SQL := Format('ALTER TABLE %s DISABLE TRIGGER %s', [QuoteDbIdent(dtPostgreSQL, ATableName), QuoteDbIdent(dtPostgreSQL, ATriggerName)]);
  end
  else
  begin
    if AActive then
      SQL := Format('ALTER TRIGGER %s ACTIVE', [QuoteDbIdent(dtFirebird, ATriggerName)])
    else
      SQL := Format('ALTER TRIGGER %s INACTIVE', [QuoteDbIdent(dtFirebird, ATriggerName)]);
  end;

  Stmts := TStringList.Create;
  try
    Stmts.Add(SQL);
    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
    begin
      if AActive then
        AMessage := Format('Trigger "%s" ativada com sucesso.', [Trim(ATriggerName)])
      else
        AMessage := Format('Trigger "%s" inativada com sucesso.', [Trim(ATriggerName)]);
    end;
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.DropTableTrigger(
  const AProfile: TConnectionProfile;
  const ATableName, ATriggerName: string;
  out AMessage: string
): Boolean;
var
  Stmts: TStringList;
begin
  Result := False;
  AMessage := '';
  if (AProfile = nil) or (Trim(ATriggerName) = '') then
  begin
    AMessage := 'Trigger inválida.';
    Exit;
  end;

  Stmts := TStringList.Create;
  try
    if AProfile.DatabaseType = dtPostgreSQL then
      Stmts.Add(Format(
        'DROP TRIGGER %s ON %s',
        [QuoteDbIdent(dtPostgreSQL, ATriggerName), QuoteDbIdent(dtPostgreSQL, ATableName)]
      ))
    else
      Stmts.Add(Format('DROP TRIGGER %s', [QuoteDbIdent(dtFirebird, ATriggerName)]));

    Result := ExecuteDDLStatements(AProfile, Stmts, AMessage);
    if Result then
      AMessage := Format('Trigger "%s" excluída com sucesso.', [Trim(ATriggerName)]);
  finally
    Stmts.Free;
  end;
end;

function TManageTableStructureUseCase.LoadTableData(
  const AProfile: TConnectionProfile;
  const ATableName, AWhereClause: string;
  const ALimitRows: Integer;
  out AExecutedSQL: string
): TQueryResult;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  CleanWhere, SQL: string;
begin
  Result := nil;
  AExecutedSQL := '';
  if (AProfile = nil) or (FFactory = nil) or (Trim(ATableName) = '') then
    Exit;

  CleanWhere := Trim(AWhereClause);
  if StartsWithSqlKeyword(CleanWhere, 'WHERE') then
    CleanWhere := Trim(Copy(CleanWhere, 6, MaxInt));
  while (CleanWhere <> '') and (CleanWhere[Length(CleanWhere)] = ';') do
    CleanWhere := TrimRight(Copy(CleanWhere, 1, Length(CleanWhere) - 1));

  if AProfile.DatabaseType in [dtPostgreSQL, dtMariaDB] then
  begin
    SQL := 'SELECT * FROM ' + QuoteDbIdent(AProfile.DatabaseType, ATableName);
    if CleanWhere <> '' then
      SQL := SQL + ' WHERE ' + CleanWhere;
    if ALimitRows > 0 then
      SQL := SQL + ' LIMIT ' + IntToStr(ALimitRows);
  end
  else
  begin
    if ALimitRows > 0 then
      SQL := Format('SELECT FIRST %d * FROM %s', [ALimitRows, QuoteDbIdent(dtFirebird, ATableName)])
    else
      SQL := 'SELECT * FROM ' + QuoteDbIdent(dtFirebird, ATableName);
    if CleanWhere <> '' then
      SQL := SQL + ' WHERE ' + CleanWhere;
  end;
  AExecutedSQL := SQL;

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    Session.Connect;
    Result := Session.ExecuteSQL(SQL, False, 0);
  finally
    try
      if Session.InTransaction then
        Session.Rollback;
    except
    end;
    try
      Session.Disconnect;
    except
    end;
    Session := nil;
  end;
end;

function TManageTableStructureUseCase.ExecuteMetadataQuery(
  const AProfile: TConnectionProfile;
  const ASQL: string
): TQueryResult;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
begin
  Result := nil;
  if (AProfile = nil) or (FFactory = nil) then
    Exit;

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    try
      Session.Connect;
      Result := Session.ExecuteSQL(ASQL, False, 0);
    except
      FreeAndNil(Result);
    end;
  finally
    try
      if Session.InTransaction then
        Session.Rollback;
    except
    end;
    try
      Session.Disconnect;
    except
    end;
    Session := nil;
  end;
end;

end.
