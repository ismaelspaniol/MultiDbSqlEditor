unit Infrastructure.MormotPostgresProvider;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.db.core,
  mormot.db.sql,
  mormot.db.sql.postgres,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces;

const
  DEFAULT_PG_FETCH_BATCH = 100;

type
  { Cursor sob demanda para PostgreSQL via mORMot2 (busca de 100 em 100 registros) }
  TMormotPostgresResultCursor = class(TInterfacedObject, IResultSetCursor)
  private
    FStmt: ISqlDBStatement;
    FColCount: Integer;
    FHasMore: Boolean;
  public
    constructor Create(const AStmt: ISqlDBStatement; const AColCount: Integer);
    destructor Destroy; override;
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure CloseCursor;
  end;

  { Sessão PostgreSQL usando mORMot2 (mormot.db.sql.postgres) }
  TMormotPostgresSession = class(TInterfacedObject, IDatabaseSession)
  private
    FProfile: TConnectionProfile;
    FProps: TSqlDBPostgresConnectionProperties;
    FConn: TSqlDBConnection;
    FActiveCursor: IResultSetCursor;
    function IsSelectLikeSQL(const ASQL: string): Boolean;
    function FieldTypeToStr(const AType: TSqlDBFieldType): string;
    procedure CloseActiveCursor;
  public
    constructor Create(const AProfile: TConnectionProfile);
    destructor Destroy; override;
    function IsConnected: Boolean;
    function InTransaction: Boolean;
    procedure Connect;
    procedure Disconnect;
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function ExecuteSQL(
      const ASQL: string;
      const AAutoCommit: Boolean = False;
      const AFetchBatchSize: Integer = DEFAULT_PG_FETCH_BATCH
    ): TQueryResult;
  end;

  { Provedor PostgreSQL via mORMot2 }
  TMormotPostgresProvider = class(TInterfacedObject, IDatabaseProvider)
  public
    function DatabaseType: TDatabaseType;
    function TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
    function CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
  end;

implementation

{ TMormotPostgresResultCursor }

constructor TMormotPostgresResultCursor.Create(const AStmt: ISqlDBStatement; const AColCount: Integer);
begin
  inherited Create;
  FStmt := AStmt;
  FColCount := AColCount;
  FHasMore := FStmt <> nil;
end;

destructor TMormotPostgresResultCursor.Destroy;
begin
  CloseCursor;
  inherited Destroy;
end;

function TMormotPostgresResultCursor.HasMore: Boolean;
begin
  Result := FHasMore and (FStmt <> nil);
end;

function TMormotPostgresResultCursor.FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
var
  I, Count: Integer;
  Row: TQueryRow;
begin
  Result := 0;
  if not HasMore then
    Exit;

  Count := 0;
  while (Count < ABatchSize) and FStmt.Step do
  begin
    SetLength(Row, FColCount);
    for I := 0 to FColCount - 1 do
    begin
      Row[I].IsNull := FStmt.ColumnNull(I);
      if Row[I].IsNull then
        Row[I].AsText := ''
      else
        Row[I].AsText := string(FStmt.ColumnUtf8(I));
    end;
    ATarget.AddRow(Row);
    Inc(Count);
  end;

  Result := Count;
  if Count < ABatchSize then
    CloseCursor;
end;

procedure TMormotPostgresResultCursor.CloseCursor;
begin
  FHasMore := False;
  if FStmt <> nil then
  begin
    try
      FStmt.ReleaseRows;
    except
    end;
    FStmt := nil;
  end;
end;

{ TMormotPostgresSession }

constructor TMormotPostgresSession.Create(const AProfile: TConnectionProfile);
var
  ServerAddr: RawUtf8;
begin
  inherited Create;
  FProfile := AProfile.Clone;
  if FProfile.Port > 0 then
    ServerAddr := RawUtf8(Format('%s:%d', [FProfile.Host, FProfile.Port]))
  else
    ServerAddr := RawUtf8(FProfile.Host);

  FProps := TSqlDBPostgresConnectionProperties.Create(
    ServerAddr,
    RawUtf8(FProfile.Database),
    RawUtf8(FProfile.Username),
    RawUtf8(FProfile.Password)
  );
end;

destructor TMormotPostgresSession.Destroy;
begin
  Disconnect;
  FProps.Free;
  FProfile.Free;
  inherited Destroy;
end;

procedure TMormotPostgresSession.CloseActiveCursor;
begin
  if FActiveCursor <> nil then
  begin
    FActiveCursor.CloseCursor;
    FActiveCursor := nil;
  end;
end;

function TMormotPostgresSession.IsConnected: Boolean;
begin
  Result := (FConn <> nil) and FConn.IsConnected;
end;

function TMormotPostgresSession.InTransaction: Boolean;
begin
  Result := IsConnected and (FConn.TransactionCount > 0);
end;

procedure TMormotPostgresSession.Connect;
begin
  if IsConnected then
    Exit;
  if FConn = nil then
    FConn := FProps.NewConnection;
  FConn.Connect;
end;

procedure TMormotPostgresSession.Disconnect;
begin
  CloseActiveCursor;
  if FConn <> nil then
  begin
    try
      if FConn.IsConnected then
        FConn.Disconnect;
    finally
      FreeAndNil(FConn);
    end;
  end;
end;

procedure TMormotPostgresSession.StartTransaction;
begin
  if not IsConnected then
    Connect;
  if not InTransaction then
    FConn.StartTransaction;
end;

procedure TMormotPostgresSession.Commit;
begin
  CloseActiveCursor;
  if InTransaction then
    FConn.Commit;
end;

procedure TMormotPostgresSession.Rollback;
begin
  CloseActiveCursor;
  if InTransaction then
    FConn.Rollback;
end;

function TMormotPostgresSession.IsSelectLikeSQL(const ASQL: string): Boolean;
var
  Trimmed: string;
begin
  Trimmed := UpperCase(TrimLeft(ASQL));
  Result :=
    (Pos('SELECT', Trimmed) = 1) or
    (Pos('WITH', Trimmed) = 1) or
    (Pos('SHOW', Trimmed) = 1) or
    (Pos('EXPLAIN', Trimmed) = 1);
end;

function TMormotPostgresSession.FieldTypeToStr(const AType: TSqlDBFieldType): string;
begin
  case AType of
    ftUnknown: Result := 'UNKNOWN';
    ftNull: Result := 'NULL';
    ftInt64: Result := 'BIGINT';
    ftDouble: Result := 'DOUBLE';
    ftCurrency: Result := 'NUMERIC';
    ftDate: Result := 'TIMESTAMP';
    ftUtf8: Result := 'TEXT';
    ftBlob: Result := 'BYTEA';
  else
    Result := 'TEXT';
  end;
end;

function TMormotPostgresSession.ExecuteSQL(
  const ASQL: string;
  const AAutoCommit: Boolean;
  const AFetchBatchSize: Integer
): TQueryResult;
var
  StartTick: QWord;
  ExpectResults: Boolean;
  Stmt: ISqlDBStatement;
  Cols: array of TQueryColumn;
  I, ColCount: Integer;
  Cursor: IResultSetCursor;
begin
  Result := TQueryResult.Create;
  StartTick := GetTickCount64;
  CloseActiveCursor;
  try
    if not IsConnected then
      Connect;

    if (not AAutoCommit) and (not InTransaction) then
      StartTransaction;

    ExpectResults := IsSelectLikeSQL(ASQL);
    Stmt := FConn.NewStatementPrepared(RawUtf8(ASQL), ExpectResults, True);
    Stmt.ExecutePrepared;

    if ExpectResults then
    begin
      ColCount := Stmt.ColumnCount;
      SetLength(Cols, ColCount);
      for I := 0 to ColCount - 1 do
      begin
        Cols[I].Name := string(Stmt.ColumnName(I));
        Cols[I].DataTypeName := FieldTypeToStr(Stmt.ColumnType(I));
        Cols[I].IsNullable := True;
      end;
      Result.SetColumns(Cols);
      Result.HasResultSet := True;

      Cursor := TMormotPostgresResultCursor.Create(Stmt, ColCount);
      if AFetchBatchSize <= 0 then
      begin
        while Cursor.HasMore do
          Cursor.FetchNext(1000, Result);
      end
      else
        Cursor.FetchNext(AFetchBatchSize, Result);

      if Cursor.HasMore then
      begin
        FActiveCursor := Cursor;
        Result.Cursor := Cursor;
        Result.MessageText := Format('%d registro(s) carregado(s) (role para buscar mais).', [Result.RowCount]);
      end
      else
      begin
        Cursor.CloseCursor;
        Result.MessageText := Format('%d registro(s) retornado(s).', [Result.RowCount]);
      end;
      Result.RowsAffected := Result.RowCount;
    end
    else
    begin
      Result.HasResultSet := False;
      Result.RowsAffected := Stmt.UpdateCount;
      Result.MessageText := Format('Comando executado com sucesso. %d linha(s) afetada(s).', [Result.RowsAffected]);
    end;

    if AAutoCommit and InTransaction and (not Result.HasMoreRows) then
      Commit;

    Result.Success := True;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.MessageText := E.Message;
    end;
  end;
  Result.ExecutionTimeMs := Int64(GetTickCount64 - StartTick);
end;

{ TMormotPostgresProvider }

function TMormotPostgresProvider.DatabaseType: TDatabaseType;
begin
  Result := dtPostgreSQL;
end;

function TMormotPostgresProvider.TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
var
  Session: IDatabaseSession;
begin
  Result := False;
  AErrorMessage := '';
  try
    Session := CreateSession(AProfile);
    Session.Connect;
    Result := Session.IsConnected;
    Session.Disconnect;
  except
    on E: Exception do
    begin
      Result := False;
      AErrorMessage := E.Message;
    end;
  end;
end;

function TMormotPostgresProvider.CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
begin
  Result := TMormotPostgresSession.Create(AProfile);
end;

end.
