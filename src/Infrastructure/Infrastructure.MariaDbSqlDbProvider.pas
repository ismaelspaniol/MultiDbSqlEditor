unit Infrastructure.MariaDbSqlDbProvider;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  Classes,
  SysUtils,
  SyncObjs,
  Math,
  DB,
  sqldb,
  mysql80conn,
  mysql80dyn,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces;

const
  MARIADB_DEFAULT_FETCH_BATCH = 100;

type
  TMariaDbSqlDbSession = class;

  { Cursor sob demanda para MariaDB / MySQL }
  TMariaDbResultCursor = class(TInterfacedObject, IResultSetCursor)
  private
    FQuery: TSQLQuery;
    FColCount: Integer;
    FClosed: Boolean;
    FSession: TMariaDbSqlDbSession;
    FPrepMs: Int64;
    FExecStartTick: QWord;
  public
    constructor Create(
      const AQuery: TSQLQuery;
      const AColCount: Integer;
      const ASession: TMariaDbSqlDbSession;
      const APrepMs: Int64;
      const AExecStartTick: QWord
    );
    destructor Destroy; override;
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure RefreshPerformance(const ATarget: TQueryResult);
    procedure CloseCursor;
  end;

  { Sessão MariaDB usando TMySQL80Connection (compatível com libmariadb.dll e libmysql.dll) }
  TMariaDbSqlDbSession = class(TInterfacedObject, IDatabaseSession)
  private
    FProfile: TConnectionProfile;
    FConn: TMySQL80Connection;
    FTrans: TSQLTransaction;
    FActiveCursor: IResultSetCursor;
    FHasUncommittedDML: Boolean;
    FStateLock: TCriticalSection;
    FConnectionId: Int64;
    function IsResultSetSQL(const ASQL: string): Boolean;
    function ResolveClientLibraryPath: string;
    procedure ConfigureConnection;
    procedure CaptureConnectionId;
    procedure CloseActiveCursor;
    function FieldTypeToStr(const AField: TField): string;
    function FieldToQueryCell(const AField: TField): TQueryCell;
    procedure PopulateColumns(const AQuery: TSQLQuery; const ATarget: TQueryResult);
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
      const AFetchBatchSize: Integer = 100;
      const AMemoryLimitBytes: Int64 = DEFAULT_RESULT_MEMORY_LIMIT_BYTES
    ): TQueryResult;
    function CancelRunningQuery(out AMessage: string): Boolean;
  end;

  TMariaDbSqlDbProvider = class(TInterfacedObject, IDatabaseProvider)
  public
    function DatabaseType: TDatabaseType;
    function TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
    function CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
  end;

implementation

var
  GMariaDbLibLock: TCriticalSection = nil;
  GMariaDbLibLoadedPath: string = '';

function GetMariaDbLibLock: TCriticalSection;
begin
  if GMariaDbLibLock = nil then
    GMariaDbLibLock := TCriticalSection.Create;
  Result := GMariaDbLibLock;
end;

{ TMariaDbResultCursor }

constructor TMariaDbResultCursor.Create(
  const AQuery: TSQLQuery;
  const AColCount: Integer;
  const ASession: TMariaDbSqlDbSession;
  const APrepMs: Int64;
  const AExecStartTick: QWord
);
begin
  inherited Create;
  FQuery := AQuery;
  FColCount := AColCount;
  FSession := ASession;
  FPrepMs := APrepMs;
  FExecStartTick := AExecStartTick;
  FClosed := False;
end;

destructor TMariaDbResultCursor.Destroy;
begin
  CloseCursor;
  inherited Destroy;
end;

function TMariaDbResultCursor.HasMore: Boolean;
begin
  Result := (not FClosed) and (FQuery <> nil) and FQuery.Active and (not FQuery.EOF);
end;

function TMariaDbResultCursor.FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
var
  BatchLimit, Fetched, ColIdx: Integer;
  Row: TQueryRow;
begin
  Result := 0;
  if FClosed or (FQuery = nil) or (not FQuery.Active) or (ATarget = nil) then
    Exit;

  if ABatchSize <= 0 then
    BatchLimit := MaxInt
  else
    BatchLimit := ABatchSize;

  Fetched := 0;
  while (not FQuery.EOF) and (Fetched < BatchLimit) do
  begin
    SetLength(Row, FColCount);
    for ColIdx := 0 to FColCount - 1 do
      Row[ColIdx] := FSession.FieldToQueryCell(FQuery.Fields[ColIdx]);
    ATarget.AddRow(Row);
    Inc(Fetched);
    FQuery.Next;

    if ATarget.IsMemoryLimitReached then
    begin
      CloseCursor;
      Break;
    end;
  end;

  if (not FClosed) and FQuery.EOF then
    CloseCursor;

  Result := Fetched;
  RefreshPerformance(ATarget);
end;

procedure TMariaDbResultCursor.RefreshPerformance(const ATarget: TQueryResult);
begin
  if (ATarget = nil) or (ATarget.Performance = nil) then
    Exit;
  ATarget.Performance.HasData := True;
  ATarget.Performance.PrepareTimeMs := FPrepMs;
  if FExecStartTick > 0 then
    ATarget.Performance.TotalTimeMs := Int64(GetTickCount64 - FExecStartTick);
  ATarget.Performance.ExecuteTimeMs := Max(0, ATarget.Performance.TotalTimeMs - FPrepMs);
end;

procedure TMariaDbResultCursor.CloseCursor;
begin
  if FClosed then
    Exit;
  FClosed := True;
  if FQuery <> nil then
  begin
    try
      if FQuery.Active then
        FQuery.Close;
    except
    end;
    FreeAndNil(FQuery);
  end;
end;

{ TMariaDbSqlDbSession }

constructor TMariaDbSqlDbSession.Create(const AProfile: TConnectionProfile);
begin
  inherited Create;
  FProfile := AProfile.Clone;
  FConn := TMySQL80Connection.Create(nil);
  FTrans := TSQLTransaction.Create(nil);
  FConn.Transaction := FTrans;
  FTrans.DataBase := FConn;
  FActiveCursor := nil;
  FHasUncommittedDML := False;
  FStateLock := TCriticalSection.Create;
  FConnectionId := 0;
end;

destructor TMariaDbSqlDbSession.Destroy;
begin
  Disconnect;
  FreeAndNil(FTrans);
  FreeAndNil(FConn);
  FreeAndNil(FProfile);
  FreeAndNil(FStateLock);
  inherited Destroy;
end;

function TMariaDbSqlDbSession.IsResultSetSQL(const ASQL: string): Boolean;
var
  S, FirstWord: string;
  I, Len: Integer;
begin
  S := TrimLeft(ASQL);
  while (Length(S) >= 2) and (((S[1] = '-') and (S[2] = '-')) or ((S[1] = '/') and (S[2] = '*'))) do
  begin
    if (S[1] = '-') and (S[2] = '-') then
    begin
      I := Pos(#10, S);
      if I = 0 then
        Exit(False);
      S := TrimLeft(Copy(S, I + 1, MaxInt));
    end
    else
    begin
      I := Pos('*/', S);
      if I = 0 then
        Exit(False);
      S := TrimLeft(Copy(S, I + 2, MaxInt));
    end;
  end;

  Len := Length(S);
  I := 1;
  while (I <= Len) and (S[I] in ['A'..'Z', 'a'..'z', '_']) do
    Inc(I);
  FirstWord := UpperCase(Copy(S, 1, I - 1));
  Result := (FirstWord = 'SELECT') or (FirstWord = 'SHOW') or
            (FirstWord = 'DESCRIBE') or (FirstWord = 'DESC') or
            (FirstWord = 'EXPLAIN') or (FirstWord = 'WITH');
end;

function TMariaDbSqlDbSession.ResolveClientLibraryPath: string;
var
  AppDir, ArchDir: string;
  Candidates: TStringList;
  I: Integer;
begin
  Result := '';
  if (FProfile <> nil) and (Trim(FProfile.ClientLibraryPath) <> '') and
     FileExists(Trim(FProfile.ClientLibraryPath)) then
    Exit(Trim(FProfile.ClientLibraryPath));

  AppDir := ExtractFilePath(ParamStr(0));
  {$IFDEF CPU64}
  ArchDir := 'win64';
  {$ELSE}
  ArchDir := 'win32';
  {$ENDIF}

  Candidates := TStringList.Create;
  try
    Candidates.Add(IncludeTrailingPathDelimiter(AppDir) + 'clients\mariadb\' + ArchDir + '\libmariadb.dll');
    Candidates.Add(IncludeTrailingPathDelimiter(AppDir) + 'clients\mariadb\' + ArchDir + '\libmysql.dll');
    Candidates.Add(IncludeTrailingPathDelimiter(AppDir) + 'clients\mariadb\libmariadb.dll');
    Candidates.Add(IncludeTrailingPathDelimiter(AppDir) + 'clients\mariadb\libmysql.dll');
    Candidates.Add(IncludeTrailingPathDelimiter(AppDir) + 'libmariadb.dll');
    Candidates.Add(IncludeTrailingPathDelimiter(AppDir) + 'libmysql.dll');

    for I := 0 to Candidates.Count - 1 do
      if FileExists(Candidates[I]) then
        Exit(Candidates[I]);
  finally
    Candidates.Free;
  end;
end;

procedure TMariaDbSqlDbSession.ConfigureConnection;
var
  LibPath, EffectiveCharset: string;
begin
  if (FConn = nil) or (FProfile = nil) then
    Exit;

  LibPath := ResolveClientLibraryPath;
  GetMariaDbLibLock.Acquire;
  try
    if (LibPath <> '') and (GMariaDbLibLoadedPath <> LibPath) then
    begin
      if GMariaDbLibLoadedPath <> '' then
        ReleaseMysql;
      InitialiseMysql(LibPath);
      GMariaDbLibLoadedPath := LibPath;
    end
    else if GMariaDbLibLoadedPath = '' then
    begin
      try
        InitialiseMysql('libmariadb.dll');
        GMariaDbLibLoadedPath := 'libmariadb.dll';
      except
        InitialiseMysql('libmysql.dll');
        GMariaDbLibLoadedPath := 'libmysql.dll';
      end;
    end;
  finally
    GetMariaDbLibLock.Release;
  end;

  FConn.SkipLibraryVersionCheck := True;
  FConn.HostName := Trim(FProfile.Host);
  if FConn.HostName = '' then
    FConn.HostName := 'localhost';
  if FProfile.Port > 0 then
    FConn.Port := FProfile.Port
  else
    FConn.Port := 3306;
  FConn.DatabaseName := Trim(FProfile.Database);
  FConn.UserName := Trim(FProfile.Username);
  FConn.Password := FProfile.Password;

  EffectiveCharset := Trim(FProfile.Charset);
  if (EffectiveCharset = '') or SameText(EffectiveCharset, 'UTF8') then
    EffectiveCharset := 'utf8mb4';
  FConn.CharSet := EffectiveCharset;
end;

procedure TMariaDbSqlDbSession.CaptureConnectionId;
var
  Q: TSQLQuery;
begin
  FStateLock.Acquire;
  try
    if FConnectionId > 0 then
      Exit;
  finally
    FStateLock.Release;
  end;

  if not IsConnected then
    Exit;

  Q := TSQLQuery.Create(nil);
  try
    Q.DataBase := FConn;
    Q.Transaction := FTrans;
    Q.SQL.Text := 'SELECT CONNECTION_ID()';
    Q.Open;
    if not Q.EOF then
    begin
      FStateLock.Acquire;
      try
        FConnectionId := Q.Fields[0].AsLargeInt;
      finally
        FStateLock.Release;
      end;
    end;
    Q.Close;
  except
  end;
  Q.Free;
end;

procedure TMariaDbSqlDbSession.CloseActiveCursor;
begin
  if FActiveCursor <> nil then
  begin
    try
      FActiveCursor.CloseCursor;
    except
    end;
    FActiveCursor := nil;
  end;
end;

function TMariaDbSqlDbSession.IsConnected: Boolean;
begin
  Result := (FConn <> nil) and FConn.Connected;
end;

function TMariaDbSqlDbSession.InTransaction: Boolean;
begin
  Result := IsConnected and FHasUncommittedDML and (FTrans <> nil) and FTrans.Active;
end;

procedure TMariaDbSqlDbSession.Connect;
begin
  if IsConnected then
    Exit;
  ConfigureConnection;
  FConn.Open;
  if not FTrans.Active then
    FTrans.StartTransaction;
  CaptureConnectionId;
end;

procedure TMariaDbSqlDbSession.Disconnect;
begin
  FStateLock.Acquire;
  try
    FConnectionId := 0;
  finally
    FStateLock.Release;
  end;
  CloseActiveCursor;
  FHasUncommittedDML := False;
  if FConn <> nil then
  begin
    try
      if (FTrans <> nil) and FTrans.Active then
        FTrans.Rollback;
    except
    end;
    try
      if FConn.Connected then
        FConn.Close;
    except
    end;
  end;
end;

procedure TMariaDbSqlDbSession.StartTransaction;
begin
  if not IsConnected then
    Connect;
  if not FTrans.Active then
    FTrans.StartTransaction;
end;

procedure TMariaDbSqlDbSession.Commit;
begin
  CloseActiveCursor;
  if (FTrans <> nil) and FTrans.Active then
    FTrans.Commit;
  FHasUncommittedDML := False;
  if IsConnected and (not FTrans.Active) then
    FTrans.StartTransaction;
end;

procedure TMariaDbSqlDbSession.Rollback;
begin
  CloseActiveCursor;
  if (FTrans <> nil) and FTrans.Active then
    FTrans.Rollback;
  FHasUncommittedDML := False;
  if IsConnected and (not FTrans.Active) then
    FTrans.StartTransaction;
end;

function TMariaDbSqlDbSession.FieldTypeToStr(const AField: TField): string;
begin
  case AField.DataType of
    ftString, ftFixedChar, ftWideString, ftFixedWideChar: Result := 'VARCHAR';
    ftSmallint, ftWord: Result := 'SMALLINT';
    ftInteger: Result := 'INT';
    ftLargeint: Result := 'BIGINT';
    ftFloat, ftCurrency: Result := 'DOUBLE';
    ftBCD, ftFMTBcd: Result := 'DECIMAL';
    ftBoolean: Result := 'BOOLEAN';
    ftDate: Result := 'DATE';
    ftTime: Result := 'TIME';
    ftDateTime, ftTimeStamp: Result := 'DATETIME';
    ftMemo, ftWideMemo: Result := 'TEXT';
    ftBlob, ftBytes, ftVarBytes: Result := 'BLOB';
  else
    Result := 'TEXT';
  end;
end;

function TMariaDbSqlDbSession.FieldToQueryCell(const AField: TField): TQueryCell;
begin
  if AField.IsNull then
  begin
    Result.IsNull := True;
    Result.AsText := '';
  end
  else
  begin
    Result.IsNull := False;
    if AField.DataType in [ftBlob, ftBytes, ftVarBytes] then
      Result.AsText := Format('[BLOB %d bytes]', [Length(AField.AsString)])
    else
      Result.AsText := AField.AsString;
  end;
end;

procedure TMariaDbSqlDbSession.PopulateColumns(const AQuery: TSQLQuery; const ATarget: TQueryResult);
var
  I: Integer;
  Cols: array of TQueryColumn;
begin
  SetLength(Cols, AQuery.FieldCount);
  for I := 0 to AQuery.FieldCount - 1 do
  begin
    Cols[I].Name := AQuery.Fields[I].FieldName;
    Cols[I].DataTypeName := FieldTypeToStr(AQuery.Fields[I]);
  end;
  ATarget.SetColumns(Cols);
end;

function TMariaDbSqlDbSession.ExecuteSQL(
  const ASQL: string;
  const AAutoCommit: Boolean;
  const AFetchBatchSize: Integer;
  const AMemoryLimitBytes: Int64
): TQueryResult;
var
  Q: TSQLQuery;
  StartTick, PrepEndTick: QWord;
  PrepMs: Int64;
  CursorObj: TMariaDbResultCursor;
  CursorIntf: IResultSetCursor;
  BatchCount: Integer;
begin
  Result := TQueryResult.Create;
  Result.MemoryLimitBytes := AMemoryLimitBytes;
  StartTick := GetTickCount64;

  try
    if not IsConnected then
      Connect;
    if not FTrans.Active then
      FTrans.StartTransaction;

    CloseActiveCursor;

    Q := TSQLQuery.Create(nil);
    Q.DataBase := FConn;
    Q.Transaction := FTrans;
    Q.SQL.Text := ASQL;

    if IsResultSetSQL(ASQL) then
    begin
      Q.Prepare;
      PrepEndTick := GetTickCount64;
      PrepMs := Int64(PrepEndTick - StartTick);
      Q.Open;

      PopulateColumns(Q, Result);
      Result.HasResultSet := True;
      Result.Success := True;

      CursorObj := TMariaDbResultCursor.Create(Q, Q.FieldCount, Self, PrepMs, StartTick);
      CursorIntf := CursorObj;
      FActiveCursor := CursorIntf;

      if AFetchBatchSize <= 0 then
        BatchCount := MaxInt
      else
        BatchCount := AFetchBatchSize;

      CursorObj.FetchNext(BatchCount, Result);
      if CursorObj.HasMore then
        Result.Cursor := CursorIntf
      else
        FActiveCursor := nil;

      Result.ExecutionTimeMs := Int64(GetTickCount64 - StartTick);
      Result.MessageText := Format('%d linha(s) carregada(s).', [Result.RowCount]);
    end
    else
    begin
      Q.Prepare;
      PrepEndTick := GetTickCount64;
      PrepMs := Int64(PrepEndTick - StartTick);
      Q.ExecSQL;
      Result.RowsAffected := Q.RowsAffected;
      Q.Free;

      if AAutoCommit then
      begin
        FTrans.Commit;
        FHasUncommittedDML := False;
        if not FTrans.Active then
          FTrans.StartTransaction;
      end
      else
        FHasUncommittedDML := True;

      Result.HasResultSet := False;
      Result.Success := True;
      Result.ExecutionTimeMs := Int64(GetTickCount64 - StartTick);
      Result.Performance.HasData := True;
      Result.Performance.PrepareTimeMs := PrepMs;
      Result.Performance.TotalTimeMs := Result.ExecutionTimeMs;
      Result.Performance.ExecuteTimeMs := Max(0, Result.ExecutionTimeMs - PrepMs);
      Result.MessageText := Format('Comando executado com sucesso (%d registro(s) afetado(s)).', [Result.RowsAffected]);
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.MessageText := E.Message;
      Result.ExecutionTimeMs := Int64(GetTickCount64 - StartTick);
    end;
  end;
end;

function TMariaDbSqlDbSession.CancelRunningQuery(out AMessage: string): Boolean;
var
  ConnId: Int64;
  CancelSession: TMariaDbSqlDbSession;
  Res: TQueryResult;
begin
  Result := False;
  AMessage := '';

  FStateLock.Acquire;
  try
    ConnId := FConnectionId;
  finally
    FStateLock.Release;
  end;

  if ConnId <= 0 then
  begin
    AMessage := 'ID de conexão MariaDB indisponível para cancelamento.';
    Exit;
  end;

  CancelSession := TMariaDbSqlDbSession.Create(FProfile);
  try
    CancelSession.Connect;
    Res := CancelSession.ExecuteSQL(Format('KILL QUERY %d', [ConnId]), True, 0);
    try
      Result := Res.Success;
      if Result then
        AMessage := 'Query MariaDB cancelada com sucesso.'
      else
        AMessage := Res.MessageText;
    finally
      Res.Free;
    end;
  except
    on E: Exception do
    begin
      Result := False;
      AMessage := E.Message;
    end;
  end;
  CancelSession.Free;
end;

{ TMariaDbSqlDbProvider }

function TMariaDbSqlDbProvider.DatabaseType: TDatabaseType;
begin
  Result := dtMariaDB;
end;

function TMariaDbSqlDbProvider.TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
var
  Session: IDatabaseSession;
begin
  Result := False;
  AErrorMessage := '';
  try
    Session := CreateSession(AProfile);
    Session.Connect;
    Session.Disconnect;
    Result := True;
  except
    on E: Exception do
    begin
      Result := False;
      AErrorMessage := E.Message;
    end;
  end;
end;

function TMariaDbSqlDbProvider.CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
begin
  Result := TMariaDbSqlDbSession.Create(AProfile);
end;

finalization
  if GMariaDbLibLock <> nil then
    FreeAndNil(GMariaDbLibLock);

end.
