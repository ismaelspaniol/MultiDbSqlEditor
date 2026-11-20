unit Application.ManageDatabaseObjectsUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces;

type
  TProcedureParamMode = (ppmIn, ppmOut, ppmInOut);
  TProcedureParamValueKind = (ppvkString, ppvkInteger, ppvkFloat, ppvkBoolean, ppvkDateTime);

  TProcedureParamInfo = record
    Name: string;
    Mode: TProcedureParamMode;
    DataTypeDisplay: string;
    ValueKind: TProcedureParamValueKind;
    DefaultValue: string;
    HasDefault: Boolean;
    DefaultIsNull: Boolean;
    Position: Integer;
  end;
  TProcedureParamInfoArray = array of TProcedureParamInfo;

  TProcedureParamValue = record
    ParamName: string;
    IsNull: Boolean;
    RawValue: string;
  end;
  TProcedureParamValueArray = array of TProcedureParamValue;

  TProcedureMetadata = record
    DatabaseType: TDatabaseType;
    ProcedureName: string;
    IsFunction: Boolean;
    IsSelectable: Boolean;
    HasOutput: Boolean;
    AllParams: TProcedureParamInfoArray;
    InputParams: TProcedureParamInfoArray;
    OutputParamCount: Integer;
  end;

  { Caso de uso para visualizar, editar, compilar e excluir Views, Procedures, Triggers e Generators }
  TManageDatabaseObjectsUseCase = class
  private
    FFactory: IDatabaseProviderFactory;
    function ExecuteSingleQuery(const AProfile: TConnectionProfile; const ASQL: string): TQueryResult;
    function LoadFirebirdViewDDL(const AProfile: TConnectionProfile; const AObjectName: string): string;
    function LoadFirebirdProcedureDDL(const AProfile: TConnectionProfile; const AObjectName: string): string;
    function LoadFirebirdTriggerDDL(const AProfile: TConnectionProfile; const AObjectName: string): string;
    function LoadPostgresViewDDL(const AProfile: TConnectionProfile; const AObjectName: string): string;
    function LoadPostgresProcedureDDL(const AProfile: TConnectionProfile; const AObjectName: string): string;
    function LoadPostgresTriggerDDL(const AProfile: TConnectionProfile; const AObjectName: string): string;
    function LoadFirebirdProcedureMetadata(
      const AProfile: TConnectionProfile;
      const AProcedureName: string
    ): TProcedureMetadata;
    function LoadPostgresProcedureMetadata(
      const AProfile: TConnectionProfile;
      const AProcedureName: string
    ): TProcedureMetadata;
  public
    constructor Create(const AFactory: IDatabaseProviderFactory);
    function ExecuteMetadataQuery(const AProfile: TConnectionProfile; const ASQL: string): TQueryResult;
    function LoadObjectDDL(
      const AProfile: TConnectionProfile;
      const AKind: TSchemaObjectKind;
      const AObjectName: string
    ): string;
    function CompileDDL(
      const AProfile: TConnectionProfile;
      const ADDL: string;
      out AMessage: string
    ): Boolean;
    function DropObject(
      const AProfile: TConnectionProfile;
      const AKind: TSchemaObjectKind;
      const AObjectName: string;
      out AMessage: string
    ): Boolean;
    function BuildNewObjectTemplate(
      const ADbType: TDatabaseType;
      const AKind: TSchemaObjectKind;
      const AObjectName: string = ''
    ): string;
    function LoadProcedureMetadata(
      const AProfile: TConnectionProfile;
      const AProcedureName: string
    ): TProcedureMetadata;
    function BuildExecuteProcedureSQL(
      const AMeta: TProcedureMetadata;
      const AValues: TProcedureParamValueArray
    ): string;
    function ExecuteProcedure(
      const AProfile: TConnectionProfile;
      const AMeta: TProcedureMetadata;
      const AValues: TProcedureParamValueArray;
      const AAutoCommit: Boolean;
      out AExecutedSQL: string
    ): TQueryResult;

    function GetGeneratorValue(const AProfile: TConnectionProfile; const AGeneratorName: string): Int64;
    function SetGeneratorValue(
      const AProfile: TConnectionProfile;
      const AGeneratorName: string;
      const ANewValue: Int64;
      out AMessage: string
    ): Boolean;
    function IncrementGenerator(
      const AProfile: TConnectionProfile;
      const AGeneratorName: string;
      const AStep: Int64;
      out ANewValue: Int64;
      out AMessage: string
    ): Boolean;
    function CreateGenerator(
      const AProfile: TConnectionProfile;
      const AGeneratorName: string;
      const AInitialValue: Int64;
      out AMessage: string
    ): Boolean;
    function DropGenerator(
      const AProfile: TConnectionProfile;
      const AGeneratorName: string;
      out AMessage: string
    ): Boolean;
  end;

function QuoteDbIdent(const ADbType: TDatabaseType; const AName: string): string;
function DecodeFirebirdFieldType(
  const AFieldSource: string;
  const AFieldType, ASubType, AFieldLen, APrecision, AScale, ACharLen: Integer
): string;
function DecodeFirebirdTriggerType(const ATrigType: Integer): string;

implementation

uses
  Application.ManageTableStructureUseCase;

function EscapeSqlString(const AValue: string): string;
begin
  Result := StringReplace(Trim(AValue), '''', '''''', [rfReplaceAll]);
end;

function NeedsFirebirdQuotes(const AName: string): Boolean;
var
  I: Integer;
begin
  if AName = '' then
    Exit(True);
  if not (AName[1] in ['A'..'Z', '_']) then
    Exit(True);
  for I := 2 to Length(AName) do
  begin
    if not (AName[I] in ['A'..'Z', '0'..'9', '_', '$']) then
      Exit(True);
  end;
  Result := False;
end;

function QuoteDbIdent(const ADbType: TDatabaseType; const AName: string): string;
var
  Cleaned: string;
begin
  Cleaned := Trim(AName);
  if ADbType = dtPostgreSQL then
    Result := '"' + StringReplace(Cleaned, '"', '""', [rfReplaceAll]) + '"'
  else if NeedsFirebirdQuotes(Cleaned) then
    Result := '"' + StringReplace(Cleaned, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := Cleaned;
end;

function DecodeFirebirdFieldType(
  const AFieldSource: string;
  const AFieldType, ASubType, AFieldLen, APrecision, AScale, ACharLen: Integer
): string;
var
  Src: string;
  EffLen, EffPrec: Integer;
begin
  Src := Trim(AFieldSource);
  if (Src <> '') and (Pos('RDB$', UpperCase(Src)) <> 1) then
    Exit(QuoteDbIdent(dtFirebird, Src));

  case AFieldType of
    7:
      begin
        if (AScale < 0) and (ASubType in [1, 2]) then
        begin
          EffPrec := APrecision;
          if EffPrec <= 0 then
            EffPrec := 4;
          if ASubType = 2 then
            Result := Format('DECIMAL(%d,%d)', [EffPrec, -AScale])
          else
            Result := Format('NUMERIC(%d,%d)', [EffPrec, -AScale]);
        end
        else
          Result := 'SMALLINT';
      end;
    8:
      begin
        if (AScale < 0) and (ASubType in [1, 2]) then
        begin
          EffPrec := APrecision;
          if EffPrec <= 0 then
            EffPrec := 9;
          if ASubType = 2 then
            Result := Format('DECIMAL(%d,%d)', [EffPrec, -AScale])
          else
            Result := Format('NUMERIC(%d,%d)', [EffPrec, -AScale]);
        end
        else
          Result := 'INTEGER';
      end;
    10:
      Result := 'FLOAT';
    11, 27:
      Result := 'DOUBLE PRECISION';
    12:
      Result := 'DATE';
    13:
      Result := 'TIME';
    14:
      begin
        EffLen := ACharLen;
        if EffLen <= 0 then
          EffLen := AFieldLen;
        if EffLen <= 0 then
          EffLen := 1;
        Result := Format('CHAR(%d)', [EffLen]);
      end;
    16:
      begin
        if (AScale < 0) and (ASubType in [1, 2]) then
        begin
          EffPrec := APrecision;
          if EffPrec <= 0 then
            EffPrec := 18;
          if ASubType = 2 then
            Result := Format('DECIMAL(%d,%d)', [EffPrec, -AScale])
          else
            Result := Format('NUMERIC(%d,%d)', [EffPrec, -AScale]);
        end
        else
          Result := 'BIGINT';
      end;
    23:
      Result := 'BOOLEAN';
    24:
      Result := 'DECFLOAT(16)';
    25:
      Result := 'DECFLOAT(34)';
    26:
      Result := 'INT128';
    28:
      Result := 'TIME WITH TIME ZONE';
    29:
      Result := 'TIMESTAMP WITH TIME ZONE';
    35:
      Result := 'TIMESTAMP';
    37:
      begin
        EffLen := ACharLen;
        if EffLen <= 0 then
          EffLen := AFieldLen;
        if EffLen <= 0 then
          EffLen := 1;
        Result := Format('VARCHAR(%d)', [EffLen]);
      end;
    40:
      begin
        EffLen := ACharLen;
        if EffLen <= 0 then
          EffLen := AFieldLen;
        Result := Format('CSTRING(%d)', [EffLen]);
      end;
    261:
      begin
        if ASubType = 1 then
          Result := 'BLOB SUB_TYPE TEXT'
        else if ASubType = 0 then
          Result := 'BLOB SUB_TYPE BINARY'
        else
          Result := Format('BLOB SUB_TYPE %d', [ASubType]);
      end;
  else
    Result := 'VARCHAR(100)';
  end;
end;

function DecodeFirebirdTriggerType(const ATrigType: Integer): string;
var
  Phase, Events: string;
  Mask, Slot, I: Integer;
begin
  case ATrigType of
    8192: Exit('ON CONNECT');
    8193: Exit('ON DISCONNECT');
    8194: Exit('ON TRANSACTION START');
    8195: Exit('ON TRANSACTION COMMIT');
    8196: Exit('ON TRANSACTION ROLLBACK');
  end;

  if (ATrigType and 1) = 1 then
    Phase := 'BEFORE'
  else
    Phase := 'AFTER';

  Mask := (ATrigType + 1) shr 1;
  Events := '';
  for I := 0 to 2 do
  begin
    Slot := (Mask shr (I * 2)) and 3;
    case Slot of
      1:
        begin
          if Events <> '' then
            Events := Events + ' OR ';
          Events := Events + 'INSERT';
        end;
      2:
        begin
          if Events <> '' then
            Events := Events + ' OR ';
          Events := Events + 'UPDATE';
        end;
      3:
        begin
          if Events <> '' then
            Events := Events + ' OR ';
          Events := Events + 'DELETE';
        end;
    end;
  end;

  if Events = '' then
    Events := 'INSERT';
  Result := Phase + ' ' + Events;
end;

function StartsWithAsKeyword(const ASource: string): Boolean;
var
  Upper: string;
begin
  Upper := UpperCase(TrimLeft(ASource));
  if Copy(Upper, 1, 2) <> 'AS' then
    Exit(False);
  if Length(Upper) = 2 then
    Exit(True);
  Result := Upper[3] in [#0..' '];
end;

{ TManageDatabaseObjectsUseCase }

constructor TManageDatabaseObjectsUseCase.Create(const AFactory: IDatabaseProviderFactory);
begin
  inherited Create;
  FFactory := AFactory;
end;

function TManageDatabaseObjectsUseCase.ExecuteSingleQuery(
  const AProfile: TConnectionProfile;
  const ASQL: string
): TQueryResult;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
begin
  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  Session.Connect;
  try
    Result := Session.ExecuteSQL(ASQL, False, 0);
    if not Result.Success then
    begin
      try
        raise Exception.Create(Result.MessageText);
      except
        Result.Free;
        raise;
      end;
    end;
  finally
    Session.Disconnect;
  end;
end;

function TManageDatabaseObjectsUseCase.LoadFirebirdViewDDL(
  const AProfile: TConnectionProfile;
  const AObjectName: string
): string;
var
  SafeName, ViewSource, ColsStr: string;
  ResSrc, ResCols: TQueryResult;
  I: Integer;
begin
  SafeName := EscapeSqlString(AObjectName);
  ResSrc := ExecuteSingleQuery(
    AProfile,
    Format('SELECT RDB$VIEW_SOURCE FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = ''%s''', [SafeName])
  );
  try
    if ResSrc.RowCount = 0 then
      raise Exception.CreateFmt('View "%s" não encontrada.', [AObjectName]);
    ViewSource := Trim(ResSrc.GetRow(0)[0].AsText);
  finally
    ResSrc.Free;
  end;

  ColsStr := '';
  ResCols := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT TRIM(RDB$FIELD_NAME) FROM RDB$RELATION_FIELDS ' +
      'WHERE RDB$RELATION_NAME = ''%s'' ORDER BY RDB$FIELD_POSITION',
      [SafeName]
    )
  );
  try
    for I := 0 to ResCols.RowCount - 1 do
    begin
      if ColsStr <> '' then
        ColsStr := ColsStr + ',' + LineEnding + '  ';
      ColsStr := ColsStr + QuoteDbIdent(dtFirebird, ResCols.GetRow(I)[0].AsText);
    end;
  finally
    ResCols.Free;
  end;

  Result := 'CREATE OR ALTER VIEW ' + QuoteDbIdent(dtFirebird, AObjectName);
  if ColsStr <> '' then
    Result := Result + ' (' + LineEnding + '  ' + ColsStr + LineEnding + ')';
  Result := Result + LineEnding + 'AS' + LineEnding + ViewSource;
  if (Result <> '') and (Result[Length(Result)] <> ';') then
    Result := Result + ';';
end;

function TManageDatabaseObjectsUseCase.LoadFirebirdProcedureDDL(
  const AProfile: TConnectionProfile;
  const AObjectName: string
): string;
var
  SafeName, ProcSource, InParams, OutParams, ParamLine, TypeStr: string;
  ResSrc, ResParams: TQueryResult;
  I, ParamType: Integer;
  Row: TQueryRow;
begin
  SafeName := EscapeSqlString(AObjectName);
  ResSrc := ExecuteSingleQuery(
    AProfile,
    Format('SELECT RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE RDB$PROCEDURE_NAME = ''%s''', [SafeName])
  );
  try
    if ResSrc.RowCount = 0 then
      raise Exception.CreateFmt('Procedure "%s" não encontrada.', [AObjectName]);
    ProcSource := ResSrc.GetRow(0)[0].AsText;
  finally
    ResSrc.Free;
  end;

  InParams := '';
  OutParams := '';
  ResParams := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT ' +
      '  pp.RDB$PARAMETER_TYPE, ' +
      '  TRIM(pp.RDB$PARAMETER_NAME), ' +
      '  TRIM(pp.RDB$FIELD_SOURCE), ' +
      '  COALESCE(f.RDB$FIELD_TYPE, 0), ' +
      '  COALESCE(f.RDB$FIELD_SUB_TYPE, 0), ' +
      '  COALESCE(f.RDB$FIELD_LENGTH, 0), ' +
      '  COALESCE(f.RDB$FIELD_PRECISION, 0), ' +
      '  COALESCE(f.RDB$FIELD_SCALE, 0), ' +
      '  COALESCE(f.RDB$CHARACTER_LENGTH, 0) ' +
      'FROM RDB$PROCEDURE_PARAMETERS pp ' +
      'LEFT JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = pp.RDB$FIELD_SOURCE ' +
      'WHERE pp.RDB$PROCEDURE_NAME = ''%s'' ' +
      'ORDER BY pp.RDB$PARAMETER_TYPE, pp.RDB$PARAMETER_NUMBER',
      [SafeName]
    )
  );
  try
    for I := 0 to ResParams.RowCount - 1 do
    begin
      Row := ResParams.GetRow(I);
      ParamType := StrToIntDef(Trim(Row[0].AsText), 0);
      TypeStr := DecodeFirebirdFieldType(
        Row[2].AsText,
        StrToIntDef(Trim(Row[3].AsText), 0),
        StrToIntDef(Trim(Row[4].AsText), 0),
        StrToIntDef(Trim(Row[5].AsText), 0),
        StrToIntDef(Trim(Row[6].AsText), 0),
        StrToIntDef(Trim(Row[7].AsText), 0),
        StrToIntDef(Trim(Row[8].AsText), 0)
      );
      ParamLine := '  ' + QuoteDbIdent(dtFirebird, Row[1].AsText) + ' ' + TypeStr;
      if ParamType = 0 then
      begin
        if InParams <> '' then
          InParams := InParams + ',' + LineEnding;
        InParams := InParams + ParamLine;
      end
      else
      begin
        if OutParams <> '' then
          OutParams := OutParams + ',' + LineEnding;
        OutParams := OutParams + ParamLine;
      end;
    end;
  finally
    ResParams.Free;
  end;

  Result := 'CREATE OR ALTER PROCEDURE ' + QuoteDbIdent(dtFirebird, AObjectName);
  if InParams <> '' then
    Result := Result + ' (' + LineEnding + InParams + LineEnding + ')';
  if OutParams <> '' then
    Result := Result + LineEnding + 'RETURNS (' + LineEnding + OutParams + LineEnding + ')';
  if not StartsWithAsKeyword(ProcSource) then
    Result := Result + LineEnding + 'AS';
  Result := Result + LineEnding + TrimRight(ProcSource);
end;

function TManageDatabaseObjectsUseCase.LoadFirebirdTriggerDDL(
  const AProfile: TConnectionProfile;
  const AObjectName: string
): string;
var
  SafeName, RelName, TrigSource, ActiveStr, EventsStr: string;
  TrigSeq, TrigType, IsInactive: Integer;
  Res: TQueryResult;
  Row: TQueryRow;
begin
  SafeName := EscapeSqlString(AObjectName);
  Res := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT ' +
      '  TRIM(COALESCE(RDB$RELATION_NAME, '''')), ' +
      '  COALESCE(RDB$TRIGGER_SEQUENCE, 0), ' +
      '  COALESCE(RDB$TRIGGER_TYPE, 0), ' +
      '  COALESCE(RDB$TRIGGER_INACTIVE, 0), ' +
      '  RDB$TRIGGER_SOURCE ' +
      'FROM RDB$TRIGGERS ' +
      'WHERE RDB$TRIGGER_NAME = ''%s''',
      [SafeName]
    )
  );
  try
    if Res.RowCount = 0 then
      raise Exception.CreateFmt('Trigger "%s" não encontrada.', [AObjectName]);
    Row := Res.GetRow(0);
    RelName := Trim(Row[0].AsText);
    TrigSeq := StrToIntDef(Trim(Row[1].AsText), 0);
    TrigType := StrToIntDef(Trim(Row[2].AsText), 1);
    IsInactive := StrToIntDef(Trim(Row[3].AsText), 0);
    TrigSource := Row[4].AsText;
  finally
    Res.Free;
  end;

  if IsInactive <> 0 then
    ActiveStr := 'INACTIVE'
  else
    ActiveStr := 'ACTIVE';

  EventsStr := DecodeFirebirdTriggerType(TrigType);

  Result := 'CREATE OR ALTER TRIGGER ' + QuoteDbIdent(dtFirebird, AObjectName);
  if RelName <> '' then
    Result := Result + ' FOR ' + QuoteDbIdent(dtFirebird, RelName);
  Result := Result + LineEnding + ActiveStr + ' ' + EventsStr + ' POSITION ' + IntToStr(TrigSeq);
  if not StartsWithAsKeyword(TrigSource) then
    Result := Result + LineEnding + 'AS';
  Result := Result + LineEnding + TrimRight(TrigSource);
end;

function TManageDatabaseObjectsUseCase.LoadPostgresViewDDL(
  const AProfile: TConnectionProfile;
  const AObjectName: string
): string;
var
  SafeName, ViewDef: string;
  Res: TQueryResult;
begin
  SafeName := EscapeSqlString(AObjectName);
  Res := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT pg_get_viewdef(c.oid, true) ' +
      'FROM pg_class c ' +
      'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'WHERE n.nspname = ''public'' AND c.relname = ''%s'' AND c.relkind = ''v''',
      [SafeName]
    )
  );
  try
    if Res.RowCount = 0 then
      raise Exception.CreateFmt('View "%s" não encontrada.', [AObjectName]);
    ViewDef := Trim(Res.GetRow(0)[0].AsText);
  finally
    Res.Free;
  end;

  Result := 'CREATE OR REPLACE VIEW ' + QuoteDbIdent(dtPostgreSQL, AObjectName) +
    ' AS' + LineEnding + ViewDef;
  if (Result <> '') and (Result[Length(Result)] <> ';') then
    Result := Result + ';';
end;

function TManageDatabaseObjectsUseCase.LoadPostgresProcedureDDL(
  const AProfile: TConnectionProfile;
  const AObjectName: string
): string;
var
  SafeName: string;
  Res: TQueryResult;
  I: Integer;
begin
  SafeName := EscapeSqlString(AObjectName);
  Res := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT pg_get_functiondef(p.oid) ' +
      'FROM pg_proc p ' +
      'JOIN pg_namespace n ON n.oid = p.pronamespace ' +
      'WHERE n.nspname = ''public'' AND p.proname = ''%s''',
      [SafeName]
    )
  );
  try
    if Res.RowCount = 0 then
      raise Exception.CreateFmt('Procedure/Function "%s" não encontrada.', [AObjectName]);
    Result := '';
    for I := 0 to Res.RowCount - 1 do
    begin
      if Result <> '' then
        Result := Result + LineEnding + LineEnding;
      Result := Result + TrimRight(Res.GetRow(I)[0].AsText);
      if (Result <> '') and (Result[Length(Result)] <> ';') then
        Result := Result + ';';
    end;
  finally
    Res.Free;
  end;
end;

function TManageDatabaseObjectsUseCase.LoadPostgresTriggerDDL(
  const AProfile: TConnectionProfile;
  const AObjectName: string
): string;
var
  SafeName, RelName, TrigDef: string;
  Res: TQueryResult;
begin
  SafeName := EscapeSqlString(AObjectName);
  Res := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT c.relname, pg_get_triggerdef(t.oid, true) ' +
      'FROM pg_trigger t ' +
      'JOIN pg_class c ON c.oid = t.tgrelid ' +
      'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'WHERE n.nspname = ''public'' AND NOT t.tgisinternal AND t.tgname = ''%s'' ' +
      'LIMIT 1',
      [SafeName]
    )
  );
  try
    if Res.RowCount = 0 then
      raise Exception.CreateFmt('Trigger "%s" não encontrada.', [AObjectName]);
    RelName := Trim(Res.GetRow(0)[0].AsText);
    TrigDef := TrimRight(Res.GetRow(0)[1].AsText);
  finally
    Res.Free;
  end;

  if (TrigDef <> '') and (TrigDef[Length(TrigDef)] <> ';') then
    TrigDef := TrigDef + ';';

  Result :=
    '-- Para recriar a trigger no PostgreSQL, execute também o DROP antes:' + LineEnding +
    Format('-- DROP TRIGGER IF EXISTS %s ON %s;', [QuoteDbIdent(dtPostgreSQL, AObjectName), QuoteDbIdent(dtPostgreSQL, RelName)]) + LineEnding +
    TrigDef;
end;

function TManageDatabaseObjectsUseCase.LoadObjectDDL(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind;
  const AObjectName: string
): string;
var
  Val: Int64;
  TableUseCase: TManageTableStructureUseCase;
begin
  if AProfile = nil then
    raise Exception.Create('Conexão inválida.');

  if AKind = sokTables then
  begin
    TableUseCase := TManageTableStructureUseCase.Create(FFactory);
    try
      Result := TableUseCase.LoadTableDDL(AProfile, AObjectName, True);
    finally
      TableUseCase.Free;
    end;
    Exit;
  end;

  if AProfile.DatabaseType = dtPostgreSQL then
  begin
    case AKind of
      sokViews:
        Result := LoadPostgresViewDDL(AProfile, AObjectName);
      sokProcedures:
        Result := LoadPostgresProcedureDDL(AProfile, AObjectName);
      sokTriggers:
        Result := LoadPostgresTriggerDDL(AProfile, AObjectName);
      sokGenerators:
        begin
          Val := GetGeneratorValue(AProfile, AObjectName);
          Result := Format(
            'CREATE SEQUENCE IF NOT EXISTS %s;' + LineEnding +
            'SELECT setval(''%s'', %d, true);',
            [QuoteDbIdent(dtPostgreSQL, AObjectName), EscapeSqlString(AObjectName), Val]
          );
        end;
    else
      raise Exception.Create('Tipo de objeto não suportado para edição de DDL.');
    end;
  end
  else
  begin
    case AKind of
      sokViews:
        Result := LoadFirebirdViewDDL(AProfile, AObjectName);
      sokProcedures:
        Result := LoadFirebirdProcedureDDL(AProfile, AObjectName);
      sokTriggers:
        Result := LoadFirebirdTriggerDDL(AProfile, AObjectName);
      sokGenerators:
        begin
          Val := GetGeneratorValue(AProfile, AObjectName);
          Result := Format(
            'CREATE GENERATOR %s;' + LineEnding +
            'SET GENERATOR %s TO %d;',
            [QuoteDbIdent(dtFirebird, AObjectName), QuoteDbIdent(dtFirebird, AObjectName), Val]
          );
        end;
    else
      raise Exception.Create('Tipo de objeto não suportado para edição de DDL.');
    end;
  end;
end;

function TManageDatabaseObjectsUseCase.CompileDDL(
  const AProfile: TConnectionProfile;
  const ADDL: string;
  out AMessage: string
): Boolean;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
begin
  Result := False;
  AMessage := '';
  if AProfile = nil then
  begin
    AMessage := 'Conexão não informada.';
    Exit;
  end;
  if Trim(ADDL) = '' then
  begin
    AMessage := 'Nenhum código DDL informado.';
    Exit;
  end;

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    Session.Connect;
    Res := Session.ExecuteSQL(ADDL, False, 0);
    try
      if not Res.Success then
      begin
        if Session.InTransaction then
          Session.Rollback;
        AMessage := Res.MessageText;
        Exit;
      end;
      if Session.InTransaction then
        Session.Commit;
      Result := True;
      AMessage := Format('Objeto compilado/executado com sucesso (%d ms).', [Res.ExecutionTimeMs]);
    finally
      Res.Free;
    end;
  except
    on E: Exception do
    begin
      try
        if Session.InTransaction then
          Session.Rollback;
      except
      end;
      Result := False;
      AMessage := E.Message;
    end;
  end;
  try
    Session.Disconnect;
  except
  end;
end;

function TManageDatabaseObjectsUseCase.DropObject(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind;
  const AObjectName: string;
  out AMessage: string
): Boolean;
var
  Ident, SQL: string;
begin
  Ident := QuoteDbIdent(AProfile.DatabaseType, AObjectName);
  if AProfile.DatabaseType = dtPostgreSQL then
  begin
    case AKind of
      sokViews: SQL := 'DROP VIEW ' + Ident;
      sokProcedures: SQL := 'DROP FUNCTION ' + Ident;
      sokGenerators: SQL := 'DROP SEQUENCE ' + Ident;
    else
      raise Exception.Create('Para excluir Trigger no PostgreSQL use: DROP TRIGGER nome ON tabela;');
    end;
  end
  else
  begin
    case AKind of
      sokViews: SQL := 'DROP VIEW ' + Ident;
      sokProcedures: SQL := 'DROP PROCEDURE ' + Ident;
      sokTriggers: SQL := 'DROP TRIGGER ' + Ident;
      sokGenerators: SQL := 'DROP GENERATOR ' + Ident;
    else
      raise Exception.Create('Tipo de objeto inválido para exclusão.');
    end;
  end;
  Result := CompileDDL(AProfile, SQL, AMessage);
  if Result then
    AMessage := Format('Objeto "%s" excluído com sucesso.', [AObjectName]);
end;

function TManageDatabaseObjectsUseCase.BuildNewObjectTemplate(
  const ADbType: TDatabaseType;
  const AKind: TSchemaObjectKind;
  const AObjectName: string
): string;
var
  ObjName: string;
begin
  ObjName := Trim(AObjectName);
  if ObjName = '' then
  begin
    case AKind of
      sokViews: ObjName := 'VW_NOVA_VIEW';
      sokProcedures: ObjName := 'SP_NOVA_PROCEDURE';
      sokTriggers: ObjName := 'TRG_NOVA_TRIGGER';
      sokGenerators: ObjName := 'GEN_NOVO_GENERATOR';
    else
      ObjName := 'NOVO_OBJETO';
    end;
  end;

  if ADbType = dtPostgreSQL then
  begin
    case AKind of
      sokViews:
        Result :=
          'CREATE OR REPLACE VIEW ' + QuoteDbIdent(dtPostgreSQL, LowerCase(ObjName)) + ' AS' + LineEnding +
          'SELECT 1 AS codigo;';
      sokProcedures:
        Result :=
          'CREATE OR REPLACE FUNCTION ' + QuoteDbIdent(dtPostgreSQL, LowerCase(ObjName)) + '(p_id integer)' + LineEnding +
          'RETURNS integer' + LineEnding +
          'LANGUAGE plpgsql' + LineEnding +
          'AS $$' + LineEnding +
          'BEGIN' + LineEnding +
          '  RETURN p_id;' + LineEnding +
          'END;' + LineEnding +
          '$$;';
      sokTriggers:
        Result :=
          'CREATE TRIGGER ' + QuoteDbIdent(dtPostgreSQL, LowerCase(ObjName)) + LineEnding +
          'BEFORE INSERT OR UPDATE ON sua_tabela' + LineEnding +
          'FOR EACH ROW' + LineEnding +
          'EXECUTE FUNCTION sua_funcao_trigger();';
      sokGenerators:
        Result :=
          'CREATE SEQUENCE ' + QuoteDbIdent(dtPostgreSQL, LowerCase(ObjName)) + ' START 1;';
    else
      Result := '';
    end;
  end
  else
  begin
    case AKind of
      sokViews:
        Result :=
          'CREATE OR ALTER VIEW ' + QuoteDbIdent(dtFirebird, UpperCase(ObjName)) + ' (' + LineEnding +
          '  COLUNA1' + LineEnding +
          ') AS' + LineEnding +
          'SELECT 1 FROM RDB$DATABASE;';
      sokProcedures:
        Result :=
          'CREATE OR ALTER PROCEDURE ' + QuoteDbIdent(dtFirebird, UpperCase(ObjName)) + ' (' + LineEnding +
          '  P_ENTRADA INTEGER' + LineEnding +
          ')' + LineEnding +
          'RETURNS (' + LineEnding +
          '  R_SAIDA INTEGER' + LineEnding +
          ')' + LineEnding +
          'AS' + LineEnding +
          'BEGIN' + LineEnding +
          '  R_SAIDA = P_ENTRADA;' + LineEnding +
          '  SUSPEND;' + LineEnding +
          'END';
      sokTriggers:
        Result :=
          'CREATE OR ALTER TRIGGER ' + QuoteDbIdent(dtFirebird, UpperCase(ObjName)) + ' FOR SUA_TABELA' + LineEnding +
          'ACTIVE BEFORE INSERT POSITION 0' + LineEnding +
          'AS' + LineEnding +
          'BEGIN' + LineEnding +
          '  /* Lógica da trigger */' + LineEnding +
          'END';
      sokGenerators:
        Result :=
          'CREATE GENERATOR ' + QuoteDbIdent(dtFirebird, UpperCase(ObjName)) + ';';
    else
      Result := '';
    end;
  end;
end;

function TManageDatabaseObjectsUseCase.GetGeneratorValue(
  const AProfile: TConnectionProfile;
  const AGeneratorName: string
): Int64;
var
  SQL: string;
  Res: TQueryResult;
begin
  if AProfile.DatabaseType = dtPostgreSQL then
    SQL := 'SELECT last_value FROM ' + QuoteDbIdent(dtPostgreSQL, AGeneratorName)
  else
    SQL := Format('SELECT GEN_ID(%s, 0) FROM RDB$DATABASE', [QuoteDbIdent(dtFirebird, AGeneratorName)]);

  Res := ExecuteSingleQuery(AProfile, SQL);
  try
    if Res.RowCount = 0 then
      raise Exception.CreateFmt('Generator "%s" não encontrado.', [AGeneratorName]);
    Result := StrToInt64Def(Trim(Res.GetRow(0)[0].AsText), 0);
  finally
    Res.Free;
  end;
end;

function TManageDatabaseObjectsUseCase.SetGeneratorValue(
  const AProfile: TConnectionProfile;
  const AGeneratorName: string;
  const ANewValue: Int64;
  out AMessage: string
): Boolean;
var
  SQL: string;
begin
  if AProfile.DatabaseType = dtPostgreSQL then
    SQL := Format('SELECT setval(''%s'', %d, true)', [EscapeSqlString(AGeneratorName), ANewValue])
  else
    SQL := Format('SET GENERATOR %s TO %d', [QuoteDbIdent(dtFirebird, AGeneratorName), ANewValue]);

  Result := CompileDDL(AProfile, SQL, AMessage);
  if Result then
    AMessage := Format('Valor de "%s" definido para %d.', [AGeneratorName, ANewValue]);
end;

function TManageDatabaseObjectsUseCase.IncrementGenerator(
  const AProfile: TConnectionProfile;
  const AGeneratorName: string;
  const AStep: Int64;
  out ANewValue: Int64;
  out AMessage: string
): Boolean;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  SQL: string;
  Res: TQueryResult;
begin
  Result := False;
  ANewValue := 0;
  AMessage := '';

  if AProfile.DatabaseType = dtPostgreSQL then
  begin
    if AStep = 1 then
      SQL := Format('SELECT nextval(''%s'')', [EscapeSqlString(AGeneratorName)])
    else
      SQL := Format(
        'SELECT setval(''%s'', (SELECT last_value + %d FROM %s), true)',
        [EscapeSqlString(AGeneratorName), AStep, QuoteDbIdent(dtPostgreSQL, AGeneratorName)]
      );
  end
  else
    SQL := Format('SELECT GEN_ID(%s, %d) FROM RDB$DATABASE', [QuoteDbIdent(dtFirebird, AGeneratorName), AStep]);

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    Session.Connect;
    Res := Session.ExecuteSQL(SQL, False, 0);
    try
      if not Res.Success then
      begin
        if Session.InTransaction then
          Session.Rollback;
        AMessage := Res.MessageText;
        Exit;
      end;
      if Res.RowCount > 0 then
        ANewValue := StrToInt64Def(Trim(Res.GetRow(0)[0].AsText), 0);
      if Session.InTransaction then
        Session.Commit;
      Result := True;
      AMessage := Format('Incrementado (+%d). Novo valor: %d.', [AStep, ANewValue]);
    finally
      Res.Free;
    end;
  except
    on E: Exception do
    begin
      try
        if Session.InTransaction then
          Session.Rollback;
      except
      end;
      Result := False;
      AMessage := E.Message;
    end;
  end;
  try
    Session.Disconnect;
  except
  end;
end;

function TManageDatabaseObjectsUseCase.CreateGenerator(
  const AProfile: TConnectionProfile;
  const AGeneratorName: string;
  const AInitialValue: Int64;
  out AMessage: string
): Boolean;
var
  SQL, Msg2: string;
begin
  if Trim(AGeneratorName) = '' then
  begin
    Result := False;
    AMessage := 'Nome do generator é obrigatório.';
    Exit;
  end;

  if AProfile.DatabaseType = dtPostgreSQL then
    SQL := Format('CREATE SEQUENCE %s START %d', [QuoteDbIdent(dtPostgreSQL, AGeneratorName), AInitialValue])
  else
    SQL := Format('CREATE GENERATOR %s', [QuoteDbIdent(dtFirebird, AGeneratorName)]);

  Result := CompileDDL(AProfile, SQL, AMessage);
  if Result and (AProfile.DatabaseType = dtFirebird) and (AInitialValue <> 0) then
  begin
    Result := SetGeneratorValue(AProfile, AGeneratorName, AInitialValue, Msg2);
    if Result then
      AMessage := Format('Generator "%s" criado com valor inicial %d.', [AGeneratorName, AInitialValue])
    else
      AMessage := Msg2;
  end
  else if Result then
    AMessage := Format('Generator "%s" criado com sucesso.', [AGeneratorName]);
end;

function TManageDatabaseObjectsUseCase.DropGenerator(
  const AProfile: TConnectionProfile;
  const AGeneratorName: string;
  out AMessage: string
): Boolean;
begin
  Result := DropObject(AProfile, sokGenerators, AGeneratorName, AMessage);
end;

function MapFirebirdParamValueKind(const AFieldType, AScale: Integer): TProcedureParamValueKind;
begin
  case AFieldType of
    7, 8, 16, 26:
      if AScale < 0 then
        Result := ppvkFloat
      else
        Result := ppvkInteger;
    10, 11, 27, 24, 25:
      Result := ppvkFloat;
    23:
      Result := ppvkBoolean;
    12, 13, 35, 28, 29:
      Result := ppvkDateTime;
  else
    Result := ppvkString;
  end;
end;

function MapPostgresParamValueKind(const ADataType, AUdtName: string): TProcedureParamValueKind;
var
  DT, Udt: string;
begin
  DT := LowerCase(Trim(ADataType));
  Udt := LowerCase(Trim(AUdtName));
  if (DT = 'smallint') or (DT = 'integer') or (DT = 'bigint') or
     (Udt = 'int2') or (Udt = 'int4') or (Udt = 'int8') or (Udt = 'oid') then
    Result := ppvkInteger
  else if (DT = 'numeric') or (DT = 'decimal') or (DT = 'real') or
          (DT = 'double precision') or (DT = 'money') or
          (Udt = 'numeric') or (Udt = 'float4') or (Udt = 'float8') then
    Result := ppvkFloat
  else if (DT = 'boolean') or (Udt = 'bool') then
    Result := ppvkBoolean
  else if (DT = 'date') or (Pos('time', DT) = 1) or (Pos('timestamp', Udt) = 1) then
    Result := ppvkDateTime
  else
    Result := ppvkString;
end;

procedure NormalizeParamDefaultValue(
  const ARawDefault: string;
  const ARawIsNull: Boolean;
  out AHasDefault: Boolean;
  out ADefaultIsNull: Boolean;
  out ADefaultValue: string
);
var
  S, Up, Unquoted: string;
  P, Len: Integer;
  QuoteClosed: Boolean;
begin
  AHasDefault := False;
  ADefaultIsNull := False;
  ADefaultValue := '';
  if ARawIsNull then
    Exit;

  S := Trim(ARawDefault);
  if S = '' then
    Exit;

  Up := UpperCase(S);
  if (Pos('DEFAULT', Up) = 1) and ((Length(Up) = 7) or (Up[8] <= ' ')) then
    S := Trim(Copy(S, 8, Length(S)))
  else if S[1] = '=' then
    S := Trim(Copy(S, 2, Length(S)));

  if S = '' then
    Exit;

  Up := UpperCase(S);
  if (Up = 'NULL') or (Pos('NULL::', Up) = 1) then
  begin
    AHasDefault := True;
    ADefaultIsNull := True;
    ADefaultValue := '';
    Exit;
  end;

  { Remove aspas simples e eventual cast "::tipo" de literais padrão no Postgres/Firebird }
  if S[1] = '''' then
  begin
    Len := Length(S);
    P := 2;
    Unquoted := '';
    QuoteClosed := False;
    while P <= Len do
    begin
      if S[P] = '''' then
      begin
        if (P < Len) and (S[P + 1] = '''') then
        begin
          Unquoted := Unquoted + '''';
          Inc(P, 2);
        end
        else
        begin
          QuoteClosed := True;
          Inc(P);
          Break;
        end;
      end
      else
      begin
        Unquoted := Unquoted + S[P];
        Inc(P);
      end;
    end;
    if QuoteClosed then
    begin
      S := Trim(Copy(S, P, Len - P + 1));
      if (S = '') or (Pos('::', S) = 1) then
      begin
        AHasDefault := True;
        ADefaultIsNull := False;
        ADefaultValue := Unquoted;
        Exit;
      end;
    end;
  end;

  AHasDefault := True;
  ADefaultIsNull := False;
  ADefaultValue := Trim(ARawDefault);
  Up := UpperCase(ADefaultValue);
  if (Pos('DEFAULT', Up) = 1) and ((Length(Up) = 7) or (Up[8] <= ' ')) then
    ADefaultValue := Trim(Copy(ADefaultValue, 8, Length(ADefaultValue)))
  else if (ADefaultValue <> '') and (ADefaultValue[1] = '=') then
    ADefaultValue := Trim(Copy(ADefaultValue, 2, Length(ADefaultValue)));
end;

function HasSuspendKeywordOutsideCommentsAndStrings(const ASource: string): Boolean;
var
  I, Len, StartI: Integer;
  C: Char;
  Tok: string;
begin
  Result := False;
  Len := Length(ASource);
  I := 1;
  while I <= Len do
  begin
    C := ASource[I];
    if C in [' ', #9, #10, #13] then
    begin
      Inc(I);
      Continue;
    end;
    if (C = '-') and (I < Len) and (ASource[I + 1] = '-') then
    begin
      Inc(I, 2);
      while (I <= Len) and not (ASource[I] in [#10, #13]) do
        Inc(I);
      Continue;
    end;
    if (C = '/') and (I < Len) and (ASource[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I < Len) and not ((ASource[I] = '*') and (ASource[I + 1] = '/')) do
        Inc(I);
      if I <= Len - 1 then
        Inc(I, 2)
      else
        I := Len + 1;
      Continue;
    end;
    if C = '''' then
    begin
      Inc(I);
      while I <= Len do
      begin
        if ASource[I] = '''' then
        begin
          if (I < Len) and (ASource[I + 1] = '''') then
            Inc(I, 2)
          else
          begin
            Inc(I);
            Break;
          end;
        end
        else
          Inc(I);
      end;
      Continue;
    end;
    if C = '"' then
    begin
      Inc(I);
      while I <= Len do
      begin
        if ASource[I] = '"' then
        begin
          if (I < Len) and (ASource[I + 1] = '"') then
            Inc(I, 2)
          else
          begin
            Inc(I);
            Break;
          end;
        end
        else
          Inc(I);
      end;
      Continue;
    end;
    if C in ['A'..'Z', 'a'..'z', '_'] then
    begin
      StartI := I;
      Inc(I);
      while (I <= Len) and (ASource[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) do
        Inc(I);
      Tok := UpperCase(Copy(ASource, StartI, I - StartI));
      if Tok = 'SUSPEND' then
        Exit(True);
      Continue;
    end;
    Inc(I);
  end;
end;

function IsValidIntegerToken(const S: string): Boolean;
var
  I, StartIdx: Integer;
begin
  if S = '' then
    Exit(False);
  StartIdx := 1;
  if S[1] in ['+', '-'] then
    StartIdx := 2;
  if StartIdx > Length(S) then
    Exit(False);
  for I := StartIdx to Length(S) do
  begin
    if not (S[I] in ['0'..'9']) then
      Exit(False);
  end;
  Result := True;
end;

function FormatProcedureParamLiteral(
  const AParam: TProcedureParamInfo;
  const AValue: TProcedureParamValue
): string;
var
  S, Norm, LowS: string;
  DblVal: Double;
  InvFmt: TFormatSettings;
begin
  if AValue.IsNull then
    Exit('NULL');

  case AParam.ValueKind of
    ppvkInteger:
      begin
        S := Trim(AValue.RawValue);
        if not IsValidIntegerToken(S) then
          raise Exception.CreateFmt(
            'Valor inteiro inválido para o parâmetro "%s": "%s".',
            [AParam.Name, AValue.RawValue]
          );
        Result := S;
      end;
    ppvkFloat:
      begin
        S := Trim(AValue.RawValue);
        if S = '' then
          raise Exception.CreateFmt(
            'Informe um número válido (ou marque NULL) para o parâmetro "%s".',
            [AParam.Name]
          );
        if Pos(',', S) > 0 then
        begin
          if Pos('.', S) > 0 then
            Norm := StringReplace(S, '.', '', [rfReplaceAll])
          else
            Norm := S;
          Norm := StringReplace(Norm, ',', '.', [rfReplaceAll]);
        end
        else
          Norm := S;
        InvFmt := DefaultFormatSettings;
        InvFmt.DecimalSeparator := '.';
        if not TryStrToFloat(Norm, DblVal, InvFmt) then
          raise Exception.CreateFmt(
            'Valor numérico inválido para o parâmetro "%s": "%s".',
            [AParam.Name, AValue.RawValue]
          );
        Result := Norm;
      end;
    ppvkBoolean:
      begin
        LowS := LowerCase(Trim(AValue.RawValue));
        if (LowS = 'true') or (LowS = '1') or (LowS = 't') or
           (LowS = 'sim') or (LowS = 's') or (LowS = 'yes') or (LowS = 'y') then
          Result := 'TRUE'
        else if (LowS = 'false') or (LowS = '0') or (LowS = 'f') or
                (LowS = 'nao') or (LowS = 'não') or (LowS = 'n') or (LowS = 'no') then
          Result := 'FALSE'
        else
          raise Exception.CreateFmt(
            'Valor booleano inválido para o parâmetro "%s" (use TRUE/FALSE ou 1/0): "%s".',
            [AParam.Name, AValue.RawValue]
          );
      end;
    ppvkDateTime:
      begin
        S := Trim(AValue.RawValue);
        if S = '' then
          raise Exception.CreateFmt(
            'Informe uma data/hora válida (ou marque NULL) para o parâmetro "%s".',
            [AParam.Name]
          );
        Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
      end;
  else
    Result := '''' + StringReplace(AValue.RawValue, '''', '''''', [rfReplaceAll]) + '''';
  end;
end;

function TManageDatabaseObjectsUseCase.ExecuteMetadataQuery(
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

function TManageDatabaseObjectsUseCase.LoadFirebirdProcedureMetadata(
  const AProfile: TConnectionProfile;
  const AProcedureName: string
): TProcedureMetadata;
var
  SafeName, ProcSource, DefaultRaw: string;
  ProcType, ProcOutputs, I, ParamType, FldType, FldScale: Integer;
  ResProc, ResParams: TQueryResult;
  Row: TQueryRow;
  PInfo: TProcedureParamInfo;
  DefaultNull: Boolean;
begin
  Result := Default(TProcedureMetadata);
  Result.DatabaseType := dtFirebird;
  Result.ProcedureName := Trim(AProcedureName);
  Result.IsFunction := False;

  SafeName := EscapeSqlString(AProcedureName);
  ResProc := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT COALESCE(RDB$PROCEDURE_TYPE, 0), COALESCE(RDB$PROCEDURE_OUTPUTS, 0), RDB$PROCEDURE_SOURCE ' +
      'FROM RDB$PROCEDURES WHERE RDB$PROCEDURE_NAME = ''%s''',
      [SafeName]
    )
  );
  try
    if ResProc.RowCount = 0 then
      raise Exception.CreateFmt('Procedure "%s" não encontrada.', [AProcedureName]);
    Row := ResProc.GetRow(0);
    ProcType := StrToIntDef(Trim(Row[0].AsText), 0);
    ProcOutputs := StrToIntDef(Trim(Row[1].AsText), 0);
    if Row[2].IsNull then
      ProcSource := ''
    else
      ProcSource := Row[2].AsText;
  finally
    ResProc.Free;
  end;

  ResParams := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT ' +
      '  pp.RDB$PARAMETER_TYPE, ' +
      '  TRIM(pp.RDB$PARAMETER_NAME), ' +
      '  TRIM(pp.RDB$FIELD_SOURCE), ' +
      '  COALESCE(f.RDB$FIELD_TYPE, 0), ' +
      '  COALESCE(f.RDB$FIELD_SUB_TYPE, 0), ' +
      '  COALESCE(f.RDB$FIELD_LENGTH, 0), ' +
      '  COALESCE(f.RDB$FIELD_PRECISION, 0), ' +
      '  COALESCE(f.RDB$FIELD_SCALE, 0), ' +
      '  COALESCE(f.RDB$CHARACTER_LENGTH, 0), ' +
      '  pp.RDB$DEFAULT_SOURCE, ' +
      '  f.RDB$DEFAULT_SOURCE, ' +
      '  COALESCE(pp.RDB$PARAMETER_NUMBER, 0) ' +
      'FROM RDB$PROCEDURE_PARAMETERS pp ' +
      'LEFT JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = pp.RDB$FIELD_SOURCE ' +
      'WHERE pp.RDB$PROCEDURE_NAME = ''%s'' ' +
      'ORDER BY pp.RDB$PARAMETER_TYPE, pp.RDB$PARAMETER_NUMBER',
      [SafeName]
    )
  );
  try
    for I := 0 to ResParams.RowCount - 1 do
    begin
      Row := ResParams.GetRow(I);
      PInfo := Default(TProcedureParamInfo);
      ParamType := StrToIntDef(Trim(Row[0].AsText), 0);
      PInfo.Name := Trim(Row[1].AsText);
      FldType := StrToIntDef(Trim(Row[3].AsText), 0);
      FldScale := StrToIntDef(Trim(Row[7].AsText), 0);
      PInfo.DataTypeDisplay := DecodeFirebirdFieldType(
        Row[2].AsText,
        FldType,
        StrToIntDef(Trim(Row[4].AsText), 0),
        StrToIntDef(Trim(Row[5].AsText), 0),
        StrToIntDef(Trim(Row[6].AsText), 0),
        FldScale,
        StrToIntDef(Trim(Row[8].AsText), 0)
      );
      PInfo.ValueKind := MapFirebirdParamValueKind(FldType, FldScale);
      PInfo.Position := StrToIntDef(Trim(Row[11].AsText), I);

      DefaultRaw := '';
      DefaultNull := True;
      if (not Row[9].IsNull) and (Trim(Row[9].AsText) <> '') then
      begin
        DefaultRaw := Row[9].AsText;
        DefaultNull := False;
      end
      else if (not Row[10].IsNull) and (Trim(Row[10].AsText) <> '') then
      begin
        DefaultRaw := Row[10].AsText;
        DefaultNull := False;
      end;
      NormalizeParamDefaultValue(DefaultRaw, DefaultNull, PInfo.HasDefault, PInfo.DefaultIsNull, PInfo.DefaultValue);

      if ParamType = 0 then
      begin
        PInfo.Mode := ppmIn;
        SetLength(Result.InputParams, Length(Result.InputParams) + 1);
        Result.InputParams[High(Result.InputParams)] := PInfo;
      end
      else
      begin
        PInfo.Mode := ppmOut;
        Inc(Result.OutputParamCount);
      end;

      SetLength(Result.AllParams, Length(Result.AllParams) + 1);
      Result.AllParams[High(Result.AllParams)] := PInfo;
    end;
  finally
    ResParams.Free;
  end;

  if (Result.OutputParamCount = 0) and (ProcOutputs > 0) then
    Result.OutputParamCount := ProcOutputs;

  if Result.OutputParamCount > 0 then
  begin
    if ProcType = 1 then
      Result.IsSelectable := True
    else if ProcType = 2 then
      Result.IsSelectable := False
    else
      Result.IsSelectable := HasSuspendKeywordOutsideCommentsAndStrings(ProcSource);
    Result.HasOutput := True;
  end
  else
  begin
    Result.IsSelectable := False;
    Result.HasOutput := False;
  end;
end;

function TManageDatabaseObjectsUseCase.LoadPostgresProcedureMetadata(
  const AProfile: TConnectionProfile;
  const AProcedureName: string
): TProcedureMetadata;
var
  SafeName, SafeSpecificName, RoutineType, ReturnDataType, ModeStr, DataTypeStr, UdtNameStr: string;
  ResProc, ResParams: TQueryResult;
  Row: TQueryRow;
  I, OrdPos: Integer;
  PInfo: TProcedureParamInfo;
begin
  Result := Default(TProcedureMetadata);
  Result.DatabaseType := dtPostgreSQL;
  Result.ProcedureName := Trim(AProcedureName);

  SafeName := EscapeSqlString(AProcedureName);
  ResProc := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT specific_name, UPPER(COALESCE(routine_type, ''FUNCTION'')), ' +
      'LOWER(COALESCE(data_type, '''')), LOWER(COALESCE(type_udt_name, '''')) ' +
      'FROM information_schema.routines ' +
      'WHERE routine_schema = ''public'' AND routine_name = ''%s'' ' +
      'ORDER BY specific_name LIMIT 1',
      [SafeName]
    )
  );
  try
    if ResProc.RowCount = 0 then
      raise Exception.CreateFmt('Procedure/Function "%s" não encontrada.', [AProcedureName]);
    Row := ResProc.GetRow(0);
    SafeSpecificName := EscapeSqlString(Row[0].AsText);
    RoutineType := UpperCase(Trim(Row[1].AsText));
    ReturnDataType := LowerCase(Trim(Row[2].AsText));
    if (ReturnDataType = '') and (not Row[3].IsNull) then
      ReturnDataType := LowerCase(Trim(Row[3].AsText));
  finally
    ResProc.Free;
  end;

  Result.IsFunction := (RoutineType <> 'PROCEDURE');
  Result.IsSelectable := Result.IsFunction;

  ResParams := ExecuteSingleQuery(
    AProfile,
    Format(
      'SELECT ' +
      '  COALESCE(ordinal_position, 0), ' +
      '  UPPER(COALESCE(parameter_mode, ''IN'')), ' +
      '  COALESCE(parameter_name, ''''), ' +
      '  COALESCE(data_type, ''''), ' +
      '  COALESCE(udt_name, ''''), ' +
      '  parameter_default ' +
      'FROM information_schema.parameters ' +
      'WHERE specific_schema = ''public'' AND specific_name = ''%s'' ' +
      'ORDER BY ordinal_position',
      [SafeSpecificName]
    )
  );
  try
    for I := 0 to ResParams.RowCount - 1 do
    begin
      Row := ResParams.GetRow(I);
      OrdPos := StrToIntDef(Trim(Row[0].AsText), 0);
      ModeStr := UpperCase(Trim(Row[1].AsText));
      if (ModeStr = 'RETURN') or (OrdPos <= 0) then
        Continue;

      PInfo := Default(TProcedureParamInfo);
      PInfo.Position := OrdPos;
      PInfo.Name := Trim(Row[2].AsText);
      if PInfo.Name = '' then
        PInfo.Name := Format('$%d', [OrdPos]);

      if ModeStr = 'OUT' then
        PInfo.Mode := ppmOut
      else if ModeStr = 'INOUT' then
        PInfo.Mode := ppmInOut
      else
        PInfo.Mode := ppmIn;

      DataTypeStr := Trim(Row[3].AsText);
      UdtNameStr := Trim(Row[4].AsText);
      if (UpperCase(DataTypeStr) = 'USER-DEFINED') or (DataTypeStr = '') then
        PInfo.DataTypeDisplay := UdtNameStr
      else
        PInfo.DataTypeDisplay := DataTypeStr;
      if PInfo.DataTypeDisplay = '' then
        PInfo.DataTypeDisplay := 'text';

      PInfo.ValueKind := MapPostgresParamValueKind(DataTypeStr, UdtNameStr);
      NormalizeParamDefaultValue(
        Row[5].AsText,
        Row[5].IsNull,
        PInfo.HasDefault,
        PInfo.DefaultIsNull,
        PInfo.DefaultValue
      );

      if PInfo.Mode in [ppmIn, ppmInOut] then
      begin
        SetLength(Result.InputParams, Length(Result.InputParams) + 1);
        Result.InputParams[High(Result.InputParams)] := PInfo;
      end;
      if PInfo.Mode in [ppmOut, ppmInOut] then
        Inc(Result.OutputParamCount);

      SetLength(Result.AllParams, Length(Result.AllParams) + 1);
      Result.AllParams[High(Result.AllParams)] := PInfo;
    end;
  finally
    ResParams.Free;
  end;

  if Result.IsFunction then
    Result.HasOutput := (Result.OutputParamCount > 0) or ((ReturnDataType <> '') and (ReturnDataType <> 'void'))
  else
    Result.HasOutput := (Result.OutputParamCount > 0);
end;

function TManageDatabaseObjectsUseCase.LoadProcedureMetadata(
  const AProfile: TConnectionProfile;
  const AProcedureName: string
): TProcedureMetadata;
begin
  if AProfile = nil then
    raise Exception.Create('Conexão inválida.');
  if Trim(AProcedureName) = '' then
    raise Exception.Create('Nome da procedure não informado.');

  if AProfile.DatabaseType = dtPostgreSQL then
    Result := LoadPostgresProcedureMetadata(AProfile, AProcedureName)
  else
    Result := LoadFirebirdProcedureMetadata(AProfile, AProcedureName);
end;

function TManageDatabaseObjectsUseCase.BuildExecuteProcedureSQL(
  const AMeta: TProcedureMetadata;
  const AValues: TProcedureParamValueArray
): string;
var
  QuotedName, ArgsStr: string;
  I, InputIdx: Integer;

  function FindInputValue(const AParamName: string; const AInputPos: Integer): TProcedureParamValue;
  var
    K: Integer;
  begin
    for K := 0 to High(AValues) do
    begin
      if SameText(AValues[K].ParamName, AParamName) then
        Exit(AValues[K]);
    end;
    if (AInputPos >= 0) and (AInputPos < Length(AValues)) then
      Exit(AValues[AInputPos]);
    Result.ParamName := AParamName;
    Result.IsNull := True;
    Result.RawValue := '';
  end;

begin
  QuotedName := QuoteDbIdent(AMeta.DatabaseType, AMeta.ProcedureName);
  ArgsStr := '';

  if (AMeta.DatabaseType = dtPostgreSQL) and (not AMeta.IsFunction) then
  begin
    { PostgreSQL CALL exige argumentos na ordem posicional completa (OUT recebe NULL) }
    InputIdx := 0;
    for I := 0 to High(AMeta.AllParams) do
    begin
      if I > 0 then
        ArgsStr := ArgsStr + ', ';
      if AMeta.AllParams[I].Mode = ppmOut then
        ArgsStr := ArgsStr + 'NULL'
      else
      begin
        ArgsStr := ArgsStr + FormatProcedureParamLiteral(
          AMeta.AllParams[I],
          FindInputValue(AMeta.AllParams[I].Name, InputIdx)
        );
        Inc(InputIdx);
      end;
    end;
    Result := Format('CALL %s(%s)', [QuotedName, ArgsStr]);
    Exit;
  end;

  for I := 0 to High(AMeta.InputParams) do
  begin
    if I > 0 then
      ArgsStr := ArgsStr + ', ';
    ArgsStr := ArgsStr + FormatProcedureParamLiteral(
      AMeta.InputParams[I],
      FindInputValue(AMeta.InputParams[I].Name, I)
    );
  end;

  if AMeta.DatabaseType = dtPostgreSQL then
    Result := Format('SELECT * FROM %s(%s)', [QuotedName, ArgsStr])
  else if AMeta.IsSelectable then
  begin
    if Length(AMeta.InputParams) > 0 then
      Result := Format('SELECT * FROM %s(%s)', [QuotedName, ArgsStr])
    else
      Result := Format('SELECT * FROM %s', [QuotedName]);
  end
  else
  begin
    if Length(AMeta.InputParams) > 0 then
      Result := Format('EXECUTE PROCEDURE %s(%s)', [QuotedName, ArgsStr])
    else
      Result := Format('EXECUTE PROCEDURE %s', [QuotedName]);
  end;
end;

function TManageDatabaseObjectsUseCase.ExecuteProcedure(
  const AProfile: TConnectionProfile;
  const AMeta: TProcedureMetadata;
  const AValues: TProcedureParamValueArray;
  const AAutoCommit: Boolean;
  out AExecutedSQL: string
): TQueryResult;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
begin
  if AProfile = nil then
    raise Exception.Create('Conexão inválida.');

  AExecutedSQL := BuildExecuteProcedureSQL(AMeta, AValues);
  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  Session.Connect;
  try
    Result := Session.ExecuteSQL(AExecutedSQL, AAutoCommit, 0);
    if (Result <> nil) and Result.Success and (not AMeta.HasOutput) then
      Result.HasResultSet := False;
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
