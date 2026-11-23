unit Application.BrowseSchemaUseCase;

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
  { Caso de uso para listar tabelas, views, procedures, triggers e generators/sequences }
  TBrowseSchemaUseCase = class
  private
    FFactory: IDatabaseProviderFactory;
    function BuildMetadataSQL(const ADbType: TDatabaseType; const AKind: TSchemaObjectKind): string;
  public
    constructor Create(const AFactory: IDatabaseProviderFactory);
    function ListObjects(const AProfile: TConnectionProfile; const AKind: TSchemaObjectKind): TStringList;
  end;

implementation

constructor TBrowseSchemaUseCase.Create(const AFactory: IDatabaseProviderFactory);
begin
  inherited Create;
  FFactory := AFactory;
end;

function TBrowseSchemaUseCase.BuildMetadataSQL(
  const ADbType: TDatabaseType;
  const AKind: TSchemaObjectKind
): string;
begin
  if ADbType = dtPostgreSQL then
  begin
    case AKind of
      sokTables:
        Result :=
          'SELECT c.relname, pg_total_relation_size(c.oid) ' +
          'FROM pg_class c ' +
          'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
          'WHERE n.nspname = current_schema() AND c.relkind IN (''r'', ''p'') ' +
          'ORDER BY 1';
      sokViews:
        Result := 'SELECT table_name FROM information_schema.views WHERE table_schema = current_schema() ORDER BY 1';
      sokProcedures:
        Result := 'SELECT routine_name FROM information_schema.routines WHERE routine_schema = current_schema() ORDER BY 1';
      sokTriggers:
        Result := 'SELECT DISTINCT trigger_name FROM information_schema.triggers WHERE trigger_schema = current_schema() ORDER BY 1';
      sokGenerators:
        Result := 'SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = current_schema() ORDER BY 1';
    end;
  end
  else if ADbType = dtMariaDB then
  begin
    case AKind of
      sokTables:
        Result :=
          'SELECT table_name, COALESCE(data_length, 0) + COALESCE(index_length, 0) ' +
          'FROM information_schema.tables ' +
          'WHERE table_schema = DATABASE() AND table_type = ''BASE TABLE'' ' +
          'ORDER BY 1';
      sokViews:
        Result := 'SELECT table_name FROM information_schema.views WHERE table_schema = DATABASE() ORDER BY 1';
      sokProcedures:
        Result := 'SELECT routine_name FROM information_schema.routines WHERE routine_schema = DATABASE() ORDER BY 1';
      sokTriggers:
        Result := 'SELECT trigger_name FROM information_schema.triggers WHERE trigger_schema = DATABASE() ORDER BY 1';
      sokGenerators:
        Result := 'SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = ''SEQUENCE'' ORDER BY 1';
    end;
  end
  else
  begin
    case AKind of
      sokTables:
        Result := 'SELECT TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NULL ORDER BY 1';
      sokViews:
        Result := 'SELECT TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NOT NULL ORDER BY 1';
      sokProcedures:
        Result := 'SELECT TRIM(RDB$PROCEDURE_NAME) FROM RDB$PROCEDURES WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1';
      sokTriggers:
        Result := 'SELECT TRIM(RDB$TRIGGER_NAME) FROM RDB$TRIGGERS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1';
      sokGenerators:
        Result := 'SELECT TRIM(RDB$GENERATOR_NAME) FROM RDB$GENERATORS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1';
    end;
  end;
end;

function TBrowseSchemaUseCase.ListObjects(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind
): TStringList;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  SQL, ObjName: string;
  Res: TQueryResult;
  I: Integer;
  SizeBytes: Int64;
  SizePtr: Pointer;
begin
  Result := TStringList.Create;
  if AProfile = nil then
    Exit;

  SQL := BuildMetadataSQL(AProfile.DatabaseType, AKind);
  if SQL = '' then
    Exit;

  Provider := FFactory.GetProvider(AProfile.DatabaseType);
  Session := Provider.CreateSession(AProfile);
  try
    Session.Connect;
    Res := Session.ExecuteSQL(SQL, False, 0);
    try
      if not Res.Success then
        raise Exception.Create(Res.MessageText);

      if Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          ObjName := Trim(Res.GetRow(I)[0].AsText);
          if ObjName <> '' then
          begin
            SizePtr := nil;
            if (Res.ColumnCount >= 2) and (not Res.GetRow(I)[1].IsNull) and
               TryStrToInt64(Trim(Res.GetRow(I)[1].AsText), SizeBytes) and (SizeBytes >= 0) then
              SizePtr := Pointer(PtrInt(SizeBytes + 1));
            Result.AddObject(ObjName, TObject(SizePtr));
          end;
        end;
      end;
    finally
      Res.Free;
    end;
  finally
    Session.Disconnect;
  end;
end;

end.
