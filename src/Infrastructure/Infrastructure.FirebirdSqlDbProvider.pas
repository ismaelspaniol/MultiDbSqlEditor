unit Infrastructure.FirebirdSqlDbProvider;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  Classes,
  SysUtils,
  dynlibs,
  DB,
  sqldb,
  IBConnection,
  ibase60dyn,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces;

const
  DEFAULT_FETCH_BATCH = 100;

type
  { Cursor sob demanda para Firebird (busca de 100 em 100 registros) }
  TFirebirdResultCursor = class(TInterfacedObject, IResultSetCursor)
  private
    FQuery: TSQLQuery;
    FColCount: Integer;
    FClosed: Boolean;
  public
    constructor Create(const AQuery: TSQLQuery; const AColCount: Integer);
    destructor Destroy; override;
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure CloseCursor;
  end;

  { Sessão Firebird usando TIBConnection / TSQLTransaction / TSQLQuery nativos }
  TFirebirdSqlDbSession = class(TInterfacedObject, IDatabaseSession)
  private
    FProfile: TConnectionProfile;
    FConn: TIBConnection;
    FTrans: TSQLTransaction;
    FCustomLibLoaded: Boolean;
    FActiveCursor: IResultSetCursor;
    function IsSelectLikeSQL(const ASQL: string): Boolean;
    function ResolveClientDllPath: string;
    procedure EnsureClientLibraryLoaded;
    procedure ReleaseClientLibraryIfLoaded;
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
      const AFetchBatchSize: Integer = DEFAULT_FETCH_BATCH
    ): TQueryResult;
  end;

  { Provedor Firebird via SQLdb }
  TFirebirdSqlDbProvider = class(TInterfacedObject, IDatabaseProvider)
  public
    function DatabaseType: TDatabaseType;
    function TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
    function CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
  end;

implementation

{$IFDEF WINDOWS}
function SetDllDirectoryW(lpPathName: PWideChar): BOOL; stdcall; external 'kernel32.dll' name 'SetDllDirectoryW';
{$ENDIF}

{ TFirebirdResultCursor }

constructor TFirebirdResultCursor.Create(const AQuery: TSQLQuery; const AColCount: Integer);
begin
  inherited Create;
  FQuery := AQuery;
  FColCount := AColCount;
  FClosed := False;
end;

destructor TFirebirdResultCursor.Destroy;
begin
  CloseCursor;
  inherited Destroy;
end;

function TFirebirdResultCursor.HasMore: Boolean;
begin
  Result := (not FClosed) and (FQuery <> nil) and FQuery.Active and (not FQuery.EOF);
end;

function TFirebirdResultCursor.FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
var
  I, Count: Integer;
  Row: TQueryRow;
begin
  Result := 0;
  if not HasMore then
    Exit;

  Count := 0;
  while (not FQuery.EOF) and (Count < ABatchSize) do
  begin
    SetLength(Row, FColCount);
    for I := 0 to FColCount - 1 do
    begin
      Row[I].IsNull := FQuery.Fields[I].IsNull;
      if Row[I].IsNull then
        Row[I].AsText := ''
      else
        Row[I].AsText := FQuery.Fields[I].AsString;
    end;
    ATarget.AddRow(Row);
    Inc(Count);
    FQuery.Next;
  end;

  Result := Count;
  if FQuery.EOF then
    CloseCursor;
end;

procedure TFirebirdResultCursor.CloseCursor;
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

{ TFirebirdSqlDbSession }

constructor TFirebirdSqlDbSession.Create(const AProfile: TConnectionProfile);
begin
  inherited Create;
  FProfile := AProfile.Clone;
  FConn := TIBConnection.Create(nil);
  FTrans := TSQLTransaction.Create(nil);

  FConn.HostName := FProfile.Host;
  if FProfile.Port > 0 then
    FConn.Port := FProfile.Port;
  FConn.DatabaseName := FProfile.Database;
  FConn.UserName := FProfile.Username;
  FConn.Password := FProfile.Password;
  if Trim(FProfile.Charset) <> '' then
    FConn.CharSet := FProfile.Charset;
  if Trim(FProfile.Role) <> '' then
    FConn.Role := FProfile.Role;
  FConn.LoginPrompt := False;

  FTrans.Database := FConn;
  FConn.Transaction := FTrans;
end;

destructor TFirebirdSqlDbSession.Destroy;
begin
  Disconnect;
  FTrans.Free;
  FConn.Free;
  FProfile.Free;
  inherited Destroy;
end;

procedure TFirebirdSqlDbSession.CloseActiveCursor;
begin
  if FActiveCursor <> nil then
  begin
    FActiveCursor.CloseCursor;
    FActiveCursor := nil;
  end;
end;

function TFirebirdSqlDbSession.IsConnected: Boolean;
begin
  Result := FConn.Connected;
end;

function TFirebirdSqlDbSession.InTransaction: Boolean;
begin
  Result := FTrans.Active;
end;

function TFirebirdSqlDbSession.ResolveClientDllPath: string;
var
  ExeDir, VerFolder, Candidate: string;
  AutoVersions: array[0..3] of string = ('5.0', '4.0', '3.0', '2.5');
  I: Integer;
begin
  Result := '';
  if (Trim(FProfile.ClientLibraryPath) <> '') and FileExists(FProfile.ClientLibraryPath) then
  begin
    Result := FProfile.ClientLibraryPath;
    Exit;
  end;

  ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  if FProfile.FirebirdVersion <> fvAuto then
  begin
    VerFolder := FirebirdVersionFolder(FProfile.FirebirdVersion);
    Candidate := ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + VerFolder + PathDelim + 'fbclient.dll';
    if FileExists(Candidate) then
      Result := Candidate
    else
      raise Exception.CreateFmt(
        'DLL do Firebird %s não encontrada em: %s',
        [VerFolder, Candidate]
      );
    Exit;
  end;

  for I := Low(AutoVersions) to High(AutoVersions) do
  begin
    Candidate := ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + AutoVersions[I] + PathDelim + 'fbclient.dll';
    if FileExists(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
  end;

  Candidate := ExeDir + 'fbclient.dll';
  if FileExists(Candidate) then
    Result := Candidate;
end;

procedure TFirebirdSqlDbSession.EnsureClientLibraryLoaded;
var
  DllPath, DllDir: string;
  {$IFDEF WINDOWS}
  WideDir: UnicodeString;
  {$ENDIF}
begin
  if FCustomLibLoaded then
    Exit;

  DllPath := ResolveClientDllPath;
  if DllPath = '' then
    Exit;

  if (IBaseLibraryHandle <> NilHandle) and (not SameText(string(IBaseLoadedLibrary), DllPath)) then
    ReleaseIBase60;

  DllDir := ExtractFileDir(DllPath);
  {$IFDEF WINDOWS}
  WideDir := UnicodeString(DllDir);
  SetDllDirectoryW(PWideChar(WideDir));
  try
  {$ENDIF}
    InitialiseIBase60(AnsiString(DllPath));
    FCustomLibLoaded := True;
  {$IFDEF WINDOWS}
  finally
    SetDllDirectoryW(nil);
  end;
  {$ENDIF}
end;

procedure TFirebirdSqlDbSession.ReleaseClientLibraryIfLoaded;
begin
  if FCustomLibLoaded then
  begin
    FCustomLibLoaded := False;
    ReleaseIBase60;
  end;
end;

procedure TFirebirdSqlDbSession.Connect;
begin
  if not FConn.Connected then
  begin
    EnsureClientLibraryLoaded;
    FConn.Connected := True;
  end;
end;

procedure TFirebirdSqlDbSession.Disconnect;
begin
  CloseActiveCursor;
  if FTrans.Active then
    FTrans.Rollback;
  if FConn.Connected then
    FConn.Connected := False;
  ReleaseClientLibraryIfLoaded;
end;

procedure TFirebirdSqlDbSession.StartTransaction;
begin
  if not IsConnected then
    Connect;
  if not FTrans.Active then
    FTrans.StartTransaction;
end;

procedure TFirebirdSqlDbSession.Commit;
begin
  CloseActiveCursor;
  if FTrans.Active then
    FTrans.Commit;
end;

procedure TFirebirdSqlDbSession.Rollback;
begin
  CloseActiveCursor;
  if FTrans.Active then
    FTrans.Rollback;
end;

function TFirebirdSqlDbSession.IsSelectLikeSQL(const ASQL: string): Boolean;
var
  Trimmed: string;
begin
  Trimmed := UpperCase(TrimLeft(ASQL));
  Result :=
    (Pos('SELECT', Trimmed) = 1) or
    (Pos('WITH', Trimmed) = 1);
end;

function TFirebirdSqlDbSession.ExecuteSQL(
  const ASQL: string;
  const AAutoCommit: Boolean;
  const AFetchBatchSize: Integer
): TQueryResult;
var
  StartTick: QWord;
  Query: TSQLQuery;
  Cols: array of TQueryColumn;
  I, ColCount, EffectiveBatch: Integer;
  Cursor: IResultSetCursor;
begin
  Result := TQueryResult.Create;
  StartTick := GetTickCount64;
  CloseActiveCursor;
  Query := TSQLQuery.Create(nil);
  try
    if not IsConnected then
      Connect;
    if not InTransaction then
      StartTransaction;

    Query.DataBase := FConn;
    Query.Transaction := FTrans;
    if AFetchBatchSize <= 0 then
      Query.PacketRecords := 1000
    else
      Query.PacketRecords := AFetchBatchSize;
    Query.SQL.Text := ASQL;

    if IsSelectLikeSQL(ASQL) then
    begin
      Query.Open;
      ColCount := Query.Fields.Count;
      SetLength(Cols, ColCount);
      for I := 0 to ColCount - 1 do
      begin
        Cols[I].Name := Query.Fields[I].FieldName;
        Cols[I].DataTypeName := Fieldtypenames[Query.Fields[I].DataType];
        Cols[I].IsNullable := not Query.Fields[I].Required;
      end;
      Result.SetColumns(Cols);
      Result.HasResultSet := True;

      Cursor := TFirebirdResultCursor.Create(Query, ColCount);
      Query := nil; // Posse transferida para o Cursor

      if AFetchBatchSize <= 0 then
      begin
        while Cursor.HasMore do
          Cursor.FetchNext(1000, Result);
      end
      else
      begin
        EffectiveBatch := AFetchBatchSize;
        Cursor.FetchNext(EffectiveBatch, Result);
      end;

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
      try
        Query.ExecSQL;
        Result.HasResultSet := False;
        Result.RowsAffected := Query.RowsAffected;
        Result.MessageText := Format('Comando executado com sucesso. %d linha(s) afetada(s).', [Result.RowsAffected]);
      finally
        Query.Free;
      end;
    end;

    if AAutoCommit and InTransaction and (not Result.HasMoreRows) then
      Commit;

    Result.Success := True;
  except
    on E: Exception do
    begin
      if Query <> nil then
        Query.Free;
      Result.Success := False;
      Result.MessageText := E.Message;
    end;
  end;
  Result.ExecutionTimeMs := Int64(GetTickCount64 - StartTick);
end;

{ TFirebirdSqlDbProvider }

function TFirebirdSqlDbProvider.DatabaseType: TDatabaseType;
begin
  Result := dtFirebird;
end;

function TFirebirdSqlDbProvider.TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
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

function TFirebirdSqlDbProvider.CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
begin
  Result := TFirebirdSqlDbSession.Create(AProfile);
end;

end.
