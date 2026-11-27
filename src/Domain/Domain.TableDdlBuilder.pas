unit Domain.TableDdlBuilder;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Domain.DatabaseTypes,
  Domain.TableStructureTypes;

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

      if TrigLines.Count > 0 then
        Result := Result + LineEnding + LineEnding + TrimRight(TrigLines.Text);
    end;
  finally
    TrigLines.Free;
    IdxLines.Free;
    Entries.Free;
  end;
end;

end.
