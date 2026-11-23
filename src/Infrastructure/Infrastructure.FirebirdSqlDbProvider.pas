unit Infrastructure.FirebirdSqlDbProvider;

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
  dynlibs,
  LazUTF8,
  LConvEncoding,
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
  TFirebirdSqlDbSession = class;

  TFirebirdTableCountEntry = record
    RelationId: Integer;
    Count: Int64;
  end;
  TFirebirdTableCountArray = array of TFirebirdTableCountEntry;

  TFirebirdDbCounters = record
    Valid: Boolean;
    Reads: Int64;
    Writes: Int64;
    Fetches: Int64;
    Marks: Int64;
    CurrentMemory: Int64;
    MaxMemory: Int64;
    SeqReads: TFirebirdTableCountArray;
    IdxReads: TFirebirdTableCountArray;
    Inserts: TFirebirdTableCountArray;
    Updates: TFirebirdTableCountArray;
    Deletes: TFirebirdTableCountArray;
  end;

  { Cursor sob demanda para Firebird (busca de 100 em 100 registros) }
  TFirebirdResultCursor = class(TInterfacedObject, IResultSetCursor)
  private
    FQuery: TSQLQuery;
    FColCount: Integer;
    FClosed: Boolean;
    FSession: TFirebirdSqlDbSession;
    FBeforeCounters: TFirebirdDbCounters;
    FPlanText: string;
    FPrepMs: Int64;
    FExecStartTick: QWord;
    FConnCharset: string;
  public
    constructor Create(
      const AQuery: TSQLQuery;
      const AColCount: Integer;
      const ASession: TFirebirdSqlDbSession;
      const ABeforeCounters: TFirebirdDbCounters;
      const APlanText: string;
      const APrepMs: Int64;
      const AExecStartTick: QWord;
      const AConnCharset: string
    );
    destructor Destroy; override;
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure RefreshPerformance(const ATarget: TQueryResult);
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
    FRelationNames: TStringList;
    FActiveCharset: string;
    FHasUncommittedDML: Boolean;
    FStateLock: TCriticalSection;
    FCancelDbHandle: isc_db_handle;
    FAttachmentId: Int64;
    function IsSelectLikeSQL(const ASQL: string): Boolean;
    function IsBlockSizeLimitError(const AEx: Exception): Boolean;
    function DetectSingleByteFallbackCharset: string;
    procedure ReconnectWithCharset(const ANewCharset: string);
    procedure CaptureAttachmentId;
    function CreateAndPrepareQuery(
      const ASQL: string;
      const AIsSelect: Boolean;
      out APrepMs: Int64
    ): TSQLQuery;
    function ResolveClientDllPath: string;
    procedure EnsureClientLibraryLoaded;
    procedure ReleaseClientLibraryIfLoaded;
    procedure CloseActiveCursor;
    procedure EnsureRelationNamesLoaded;
    function CaptureDatabaseCounters(out ACounters: TFirebirdDbCounters): Boolean;
    function ExtractQueryPlan(const AQuery: TSQLQuery): string;
    procedure PopulatePerformanceStats(
      const ABefore, AAfter: TFirebirdDbCounters;
      const APlan: string;
      const APrepMs, AExecMs: Int64;
      const ATarget: TQueryResult
    );
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
      const AFetchBatchSize: Integer = DEFAULT_FETCH_BATCH;
      const AMemoryLimitBytes: Int64 = DEFAULT_RESULT_MEMORY_LIMIT_BYTES
    ): TQueryResult;
    function CancelRunningQuery(out AMessage: string): Boolean;
  end;

  { Provedor Firebird via SQLdb }
  TFirebirdSqlDbProvider = class(TInterfacedObject, IDatabaseProvider)
  public
    function DatabaseType: TDatabaseType;
    function TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
    function CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
  end;

function IsMultiByteFirebirdCharset(const ACharset: string): Boolean;
function IsFirebirdBlockSizeErrorText(const AMessage: string): Boolean;
function EncodeFirebirdSqlForCharset(const ASQL, ACharset: string): string;
function DecodeFirebirdTextToUTF8(const AText, ACharset: string): string;
function ResolveFirebirdClientDllPath(const AProfile: TConnectionProfile): string;
procedure AcquireFirebirdClientLib(const AProfile: TConnectionProfile);
procedure ReleaseFirebirdClientLib;

implementation

const
  FB_CANCEL_RAISE = 3;

type
  PFbDbHandle = ^isc_db_handle;
  TFbCancelOperation = function(
    status_vector: PISC_STATUS;
    db_handle: PFbDbHandle;
    option: ISC_USHORT
  ): ISC_STATUS; {$IFDEF WINDOWS} stdcall; {$ELSE} cdecl; {$ENDIF}

  TExposedSQLQuery = class(TSQLQuery);
  TExposedIBCursor = class(TIBCursor);

var
  GFbLibLock: TCriticalSection = nil;
  GFbFetchLock: TCriticalSection = nil;
  GFbActiveLibUsers: Integer = 0;

{$IFDEF WINDOWS}
function SetDllDirectoryW(lpPathName: PWideChar): BOOL; stdcall; external 'kernel32.dll' name 'SetDllDirectoryW';
{$ENDIF}

function ReadVaxInt64(const P: PByte; const ALen: Integer): Int64;
var
  I: Integer;
  U: QWord;
begin
  U := 0;
  for I := 0 to Min(ALen, 8) - 1 do
    U := U or (QWord(P[I]) shl (I * 8));
  Result := Int64(U);
end;

function IsMultiByteFirebirdCharset(const ACharset: string): Boolean;
var
  Up: string;
begin
  Up := UpperCase(Trim(ACharset));
  Result := (Up = 'UTF8') or (Up = 'UTF-8') or (Up = 'UNICODE_FSS') or
            (Up = 'UTF16') or (Up = 'UTF32');
end;

function IsFirebirdBlockSizeErrorText(const AMessage: string): Boolean;
begin
  Result := Pos('block size exceeds implementation restriction', LowerCase(AMessage)) > 0;
end;

function EncodeFirebirdSqlForCharset(const ASQL, ACharset: string): string;
var
  Up: string;
  RawBytes: RawByteString;
begin
  Up := UpperCase(Trim(ACharset));
  if Up = 'WIN1252' then
    RawBytes := UTF8ToCP1252(ASQL, False)
  else if Up = 'ISO8859_1' then
    RawBytes := UTF8ToISO_8859_1(ASQL, False)
  else if Up = 'WIN1250' then
    RawBytes := UTF8ToCP1250(ASQL, False)
  else if Up = 'WIN1251' then
    RawBytes := UTF8ToCP1251(ASQL, False)
  else if Up = 'DOS850' then
    RawBytes := UTF8ToCP850(ASQL, False)
  else
  begin
    Result := ASQL;
    Exit;
  end;
  Result := RawBytes;
end;

function DecodeFirebirdTextToUTF8(const AText, ACharset: string): string;
var
  Up: string;
begin
  if (AText = '') or (FindInvalidUTF8Codepoint(PChar(AText), Length(AText)) < 0) then
    Exit(AText);

  Up := UpperCase(Trim(ACharset));
  if Up = 'ISO8859_1' then
    Result := ISO_8859_1ToUTF8(AText)
  else if Up = 'WIN1250' then
    Result := CP1250ToUTF8(AText)
  else if Up = 'WIN1251' then
    Result := CP1251ToUTF8(AText)
  else if Up = 'DOS850' then
    Result := CP850ToUTF8(AText)
  else
    Result := CP1252ToUTF8(AText);
end;

{ TFirebirdResultCursor }

constructor TFirebirdResultCursor.Create(
  const AQuery: TSQLQuery;
  const AColCount: Integer;
  const ASession: TFirebirdSqlDbSession;
  const ABeforeCounters: TFirebirdDbCounters;
  const APlanText: string;
  const APrepMs: Int64;
  const AExecStartTick: QWord;
  const AConnCharset: string
);
begin
  inherited Create;
  FQuery := AQuery;
  FColCount := AColCount;
  FClosed := False;
  FSession := ASession;
  FBeforeCounters := ABeforeCounters;
  FPlanText := APlanText;
  FPrepMs := APrepMs;
  FExecStartTick := AExecStartTick;
  FConnCharset := Trim(AConnCharset);
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
  Fld: TField;
begin
  Result := 0;
  if not HasMore then
    Exit;

  GFbFetchLock.Acquire;
  try
    if not HasMore then
      Exit;

    Count := 0;
    while (not FQuery.EOF) and (Count < ABatchSize) do
    begin
      if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
      begin
        ATarget.MarkMemoryLimitReached;
        RefreshPerformance(ATarget);
        CloseCursor;
        Break;
      end;

      SetLength(Row, FColCount);
      for I := 0 to FColCount - 1 do
      begin
        Fld := FQuery.Fields[I];
        Row[I].IsNull := Fld.IsNull;
        if Row[I].IsNull then
          Row[I].AsText := ''
        else if Fld.DataType in [ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary, ftOraBlob] then
          Row[I].AsText := '(BLOB)'
        else if Fld.DataType in [ftBytes, ftVarBytes] then
          Row[I].AsText := Format('(BINARY %d B)', [Fld.DataSize])
        else if Fld.DataType in [ftString, ftFixedChar, ftMemo, ftWideString, ftFixedWideChar, ftWideMemo] then
          Row[I].AsText := TruncateGridCellText(DecodeFirebirdTextToUTF8(Fld.AsString, FConnCharset))
        else
          Row[I].AsText := Fld.AsString;
      end;
      ATarget.AddRow(Row);
      Inc(Count);
      FQuery.Next;

      if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
      begin
        ATarget.MarkMemoryLimitReached;
        RefreshPerformance(ATarget);
        CloseCursor;
        Break;
      end;
    end;

    Result := Count;
    if (not FClosed) and (FQuery <> nil) and FQuery.EOF then
    begin
      RefreshPerformance(ATarget);
      CloseCursor;
    end;
  finally
    GFbFetchLock.Release;
  end;
end;

procedure TFirebirdResultCursor.RefreshPerformance(const ATarget: TQueryResult);
var
  AfterCounters: TFirebirdDbCounters;
  ExecMs: Int64;
begin
  if (ATarget = nil) or (FSession = nil) or (not FSession.IsConnected) then
    Exit;

  if FSession.CaptureDatabaseCounters(AfterCounters) then
  begin
    ExecMs := Int64(GetTickCount64 - FExecStartTick);
    FSession.PopulatePerformanceStats(
      FBeforeCounters,
      AfterCounters,
      FPlanText,
      FPrepMs,
      ExecMs,
      ATarget
    );
  end;
end;

procedure TFirebirdResultCursor.CloseCursor;
begin
  if FClosed then
    Exit;
  FClosed := True;
  FSession := nil;
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
  FStateLock := TCriticalSection.Create;
  FCancelDbHandle := isc_db_handle(0);
  FAttachmentId := 0;
  FProfile := AProfile.Clone;
  FConn := TIBConnection.Create(nil);
  FTrans := TSQLTransaction.Create(nil);
  FRelationNames := TStringList.Create;
  FRelationNames.NameValueSeparator := '=';

  FConn.HostName := FProfile.Host;
  if FProfile.Port > 0 then
    FConn.Port := FProfile.Port;
  FConn.DatabaseName := FProfile.Database;
  FConn.UserName := FProfile.Username;
  FConn.Password := FProfile.Password;
  if Trim(FProfile.Charset) <> '' then
    FConn.CharSet := FProfile.Charset;
  FActiveCharset := Trim(FProfile.Charset);
  FHasUncommittedDML := False;
  if Trim(FProfile.Role) <> '' then
    FConn.Role := FProfile.Role;
  FConn.LoginPrompt := False;

  FTrans.Database := FConn;
  FConn.Transaction := FTrans;
end;

destructor TFirebirdSqlDbSession.Destroy;
begin
  Disconnect;
  FRelationNames.Free;
  FTrans.Free;
  FConn.Free;
  FProfile.Free;
  FStateLock.Free;
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

function ResolveFirebirdClientDllPath(const AProfile: TConnectionProfile): string;
{$IFDEF WINDOWS}
const
  {$IFDEF CPU64}
  WinArchDir = 'win64';
  {$ELSE}
  WinArchDir = 'win32';
  {$ENDIF}
{$ENDIF}
var
  ExeDir, VerFolder, CandidateDir: string;
  AutoVersions: array[0..3] of string = ('5.0', '4.0', '3.0', '2.5');
  Candidates: array of string;
  {$IFDEF UNIX}
  SystemDirs: array[0..5] of string = (
    '/usr/lib/x86_64-linux-gnu',
    '/usr/lib',
    '/usr/lib64',
    '/usr/local/lib',
    '/opt/firebird/lib',
    '/lib/x86_64-linux-gnu'
  );
  {$ENDIF}
  I, J: Integer;

  function FindInDir(const ADir: string; const ANames: array of string): string;
  var
    K: Integer;
    TestPath: string;
  begin
    Result := '';
    for K := Low(ANames) to High(ANames) do
    begin
      TestPath := IncludeTrailingPathDelimiter(ADir) + ANames[K];
      if FileExists(TestPath) then
        Exit(TestPath);
    end;
  end;

begin
  Result := '';
  if AProfile = nil then
    Exit;

  if (Trim(AProfile.ClientLibraryPath) <> '') and FileExists(AProfile.ClientLibraryPath) then
  begin
    Result := AProfile.ClientLibraryPath;
    Exit;
  end;

  {$IFDEF WINDOWS}
  SetLength(Candidates, 1);
  Candidates[0] := 'fbclient.dll';
  {$ELSE}
  case AProfile.FirebirdVersion of
    fv50:
    begin
      SetLength(Candidates, 3);
      Candidates[0] := 'libfbclient.so.5';
      Candidates[1] := 'libfbclient.so';
      Candidates[2] := 'libfbclient.so.2';
    end;
    fv40:
    begin
      SetLength(Candidates, 3);
      Candidates[0] := 'libfbclient.so.4';
      Candidates[1] := 'libfbclient.so';
      Candidates[2] := 'libfbclient.so.2';
    end;
    fv30:
    begin
      SetLength(Candidates, 3);
      Candidates[0] := 'libfbclient.so.3';
      Candidates[1] := 'libfbclient.so.2';
      Candidates[2] := 'libfbclient.so';
    end;
    fv25:
    begin
      SetLength(Candidates, 3);
      Candidates[0] := 'libfbclient.so.2.5';
      Candidates[1] := 'libfbclient.so.2';
      Candidates[2] := 'libfbclient.so';
    end;
  else
    SetLength(Candidates, 6);
    Candidates[0] := 'libfbclient.so.2';
    Candidates[1] := 'libfbclient.so';
    Candidates[2] := 'libfbclient.so.3';
    Candidates[3] := 'libfbclient.so.4';
    Candidates[4] := 'libfbclient.so.5';
    Candidates[5] := 'libgds.so';
  end;
  {$ENDIF}

  ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  if AProfile.FirebirdVersion <> fvAuto then
  begin
    VerFolder := FirebirdVersionFolder(AProfile.FirebirdVersion);
    {$IFDEF WINDOWS}
    CandidateDir := ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + VerFolder + PathDelim + WinArchDir;
    Result := FindInDir(CandidateDir, Candidates);
    if Result <> '' then
      Exit;

    Result := FindInDir(ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + VerFolder, Candidates);
    if Result <> '' then
      Exit;
    {$ELSE}
    CandidateDir := ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + VerFolder;
    Result := FindInDir(CandidateDir, Candidates);
    if Result <> '' then
      Exit;
    {$ENDIF}

    Result := FindInDir(ExeDir, Candidates);
    if Result <> '' then
      Exit;

    {$IFDEF UNIX}
    for I := Low(SystemDirs) to High(SystemDirs) do
    begin
      Result := FindInDir(SystemDirs[I], Candidates);
      if Result <> '' then
        Exit;
    end;
    {$ENDIF}

    raise Exception.CreateFmt(
      'Biblioteca cliente do Firebird %s não encontrada.' + LineEnding +
      {$IFDEF UNIX}
      'No Linux, instale o pacote libfbclient2:' + LineEnding +
      '  sudo apt install libfbclient2' + LineEnding +
      'Ou copie o arquivo (.so) para: %s%s',
      {$ELSE}
      'No Windows, coloque fbclient.dll em: %s%s',
      {$ENDIF}
      [VerFolder, CandidateDir, PathDelim]
    );
  end;

  for I := Low(AutoVersions) to High(AutoVersions) do
  begin
    {$IFDEF WINDOWS}
    CandidateDir := ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + AutoVersions[I] + PathDelim + WinArchDir;
    Result := FindInDir(CandidateDir, Candidates);
    if Result <> '' then
      Exit;
    {$ENDIF}
    CandidateDir := ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + AutoVersions[I];
    Result := FindInDir(CandidateDir, Candidates);
    if Result <> '' then
      Exit;
  end;

  Result := FindInDir(ExeDir, Candidates);
  if Result <> '' then
    Exit;

  {$IFDEF UNIX}
  for J := Low(SystemDirs) to High(SystemDirs) do
  begin
    Result := FindInDir(SystemDirs[J], Candidates);
    if Result <> '' then
      Exit;
  end;
  {$ENDIF}
end;

procedure AcquireFirebirdClientLib(const AProfile: TConnectionProfile);
var
  DllPath, DllDir: string;
  {$IFDEF WINDOWS}
  WideDir: UnicodeString;
  {$ENDIF}
begin
  GFbLibLock.Acquire;
  try
    DllPath := ResolveFirebirdClientDllPath(AProfile);
    if DllPath <> '' then
    begin
      if (IBaseLibraryHandle <> NilHandle) and (not SameText(string(IBaseLoadedLibrary), DllPath)) then
      begin
        if GFbActiveLibUsers = 0 then
          ReleaseIBase60
        else
        begin
          InitialiseIBase60;
          Inc(GFbActiveLibUsers);
          Exit;
        end;
      end;

      DllDir := ExtractFileDir(DllPath);
      {$IFDEF WINDOWS}
      WideDir := UnicodeString(DllDir);
      SetDllDirectoryW(PWideChar(WideDir));
      try
      {$ENDIF}
        try
          InitialiseIBase60(AnsiString(DllPath));
          Inc(GFbActiveLibUsers);
        except
          on E: Exception do
            raise Exception.CreateFmt(
              'Falha ao carregar a biblioteca cliente do Firebird em "%s": %s',
              [DllPath, E.Message]
            );
        end;
      {$IFDEF WINDOWS}
      finally
        SetDllDirectoryW(nil);
      end;
      {$ENDIF}
    end
    else
    begin
      try
        InitialiseIBase60;
        Inc(GFbActiveLibUsers);
      except
        on E: Exception do
        begin
          {$IFDEF UNIX}
          raise Exception.Create(
            'Biblioteca cliente do Firebird não encontrada no Linux.' + LineEnding +
            'Para instalar a biblioteca oficial, execute no terminal:' + LineEnding +
            '  sudo apt install libfbclient2' + LineEnding + LineEnding +
            'Detalhe do erro original: ' + E.Message
          );
          {$ELSE}
          raise Exception.Create(
            'Biblioteca cliente do Firebird (fbclient.dll) não encontrada.' + LineEnding +
            'Coloque fbclient.dll na mesma pasta do executável.' + LineEnding + LineEnding +
            'Detalhe do erro original: ' + E.Message
          );
          {$ENDIF}
        end;
      end;
    end;
  finally
    GFbLibLock.Release;
  end;
end;

procedure ReleaseFirebirdClientLib;
begin
  GFbLibLock.Acquire;
  try
    if GFbActiveLibUsers > 0 then
      Dec(GFbActiveLibUsers);
    ReleaseIBase60;
  finally
    GFbLibLock.Release;
  end;
end;

function TFirebirdSqlDbSession.ResolveClientDllPath: string;
begin
  Result := ResolveFirebirdClientDllPath(FProfile);
end;

procedure TFirebirdSqlDbSession.EnsureClientLibraryLoaded;
begin
  if FCustomLibLoaded then
    Exit;
  AcquireFirebirdClientLib(FProfile);
  FCustomLibLoaded := True;
end;

procedure TFirebirdSqlDbSession.ReleaseClientLibraryIfLoaded;
begin
  if FCustomLibLoaded then
  begin
    FCustomLibLoaded := False;
    ReleaseFirebirdClientLib;
  end;
end;

procedure TFirebirdSqlDbSession.Connect;
begin
  if not FConn.Connected then
  begin
    EnsureClientLibraryLoaded;
    FConn.Connected := True;
    FStateLock.Acquire;
    try
      FCancelDbHandle := isc_db_handle(PtrUInt(FConn.Handle));
      FAttachmentId := 0;
    finally
      FStateLock.Release;
    end;
  end;
end;

procedure TFirebirdSqlDbSession.Disconnect;
begin
  FStateLock.Acquire;
  try
    FCancelDbHandle := isc_db_handle(0);
    FAttachmentId := 0;
  finally
    FStateLock.Release;
  end;
  CloseActiveCursor;
  if FTrans.Active then
    FTrans.Rollback;
  FHasUncommittedDML := False;
  if FConn.Connected then
    FConn.Connected := False;
  if FRelationNames <> nil then
    FRelationNames.Clear;
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
  FHasUncommittedDML := False;
end;

procedure TFirebirdSqlDbSession.Rollback;
begin
  CloseActiveCursor;
  if FTrans.Active then
    FTrans.Rollback;
  FHasUncommittedDML := False;
end;

function TFirebirdSqlDbSession.IsSelectLikeSQL(const ASQL: string): Boolean;
begin
  Result := IsSelectLikeSQLText(ASQL, False);
end;

function TFirebirdSqlDbSession.IsBlockSizeLimitError(const AEx: Exception): Boolean;
const
  ISC_BLKTOOBIG = 335544381;
var
  IBEx: EIBDatabaseError;
  I: Integer;
begin
  if AEx = nil then
    Exit(False);
  if IsFirebirdBlockSizeErrorText(AEx.Message) then
    Exit(True);
  if AEx is EIBDatabaseError then
  begin
    IBEx := EIBDatabaseError(AEx);
    if IBEx.ErrorCode = ISC_BLKTOOBIG then
      Exit(True);
    for I := Low(IBEx.StatusVector) to High(IBEx.StatusVector) do
      if IBEx.StatusVector[I] = ISC_BLKTOOBIG then
        Exit(True);
  end;
  Result := False;
end;

function TFirebirdSqlDbSession.DetectSingleByteFallbackCharset: string;
const
  KnownSingleByteCharsets: array[0..17] of string = (
    'WIN1252', 'ISO8859_1', 'NONE', 'ASCII',
    'WIN1250', 'WIN1251', 'WIN1253', 'WIN1254', 'WIN1255', 'WIN1256', 'WIN1257', 'WIN1258',
    'ISO8859_2', 'ISO8859_15', 'DOS850', 'DOS852', 'DOS437', 'OCTETS'
  );
var
  Q: TSQLQuery;
  DbCharset: string;
  I: Integer;
begin
  Result := 'NONE';
  if (not IsConnected) or (not InTransaction) then
    Exit;

  Q := TSQLQuery.Create(nil);
  try
    Q.DataBase := FConn;
    Q.Transaction := FTrans;
    Q.ParamCheck := False;
    Q.SQL.Text := 'SELECT TRIM(COALESCE(RDB$CHARACTER_SET_NAME, '''')) FROM RDB$DATABASE';
    try
      Q.Open;
      if not Q.EOF then
      begin
        DbCharset := UpperCase(Trim(Q.Fields[0].AsString));
        for I := Low(KnownSingleByteCharsets) to High(KnownSingleByteCharsets) do
        begin
          if DbCharset = KnownSingleByteCharsets[I] then
          begin
            Result := DbCharset;
            Break;
          end;
        end;
      end;
      Q.Close;
    except
      Result := 'NONE';
    end;
  finally
    Q.Free;
  end;
end;

procedure TFirebirdSqlDbSession.ReconnectWithCharset(const ANewCharset: string);
begin
  FStateLock.Acquire;
  try
    FCancelDbHandle := isc_db_handle(0);
    FAttachmentId := 0;
  finally
    FStateLock.Release;
  end;
  CloseActiveCursor;
  if FTrans.Active then
    FTrans.Rollback;
  FHasUncommittedDML := False;
  if FConn.Connected then
    FConn.Connected := False;

  FActiveCharset := Trim(ANewCharset);
  FConn.CharSet := FActiveCharset;
  FConn.Connected := True;
  FStateLock.Acquire;
  try
    FCancelDbHandle := isc_db_handle(PtrUInt(FConn.Handle));
    FAttachmentId := 0;
  finally
    FStateLock.Release;
  end;
  FTrans.StartTransaction;
  CaptureAttachmentId;

  if FRelationNames <> nil then
    FRelationNames.Clear;
  EnsureRelationNamesLoaded;
end;

procedure TFirebirdSqlDbSession.CaptureAttachmentId;
var
  Q: TSQLQuery;
  AttId: Int64;
begin
  FStateLock.Acquire;
  try
    if FAttachmentId > 0 then
      Exit;
  finally
    FStateLock.Release;
  end;

  if (not IsConnected) or (not InTransaction) then
    Exit;

  Q := TSQLQuery.Create(nil);
  try
    Q.DataBase := FConn;
    Q.Transaction := FTrans;
    Q.ParamCheck := False;
    Q.SQL.Text := 'SELECT CURRENT_CONNECTION FROM RDB$DATABASE';
    try
      Q.Open;
      if not Q.EOF then
      begin
        AttId := StrToInt64Def(Trim(Q.Fields[0].AsString), 0);
        if AttId > 0 then
        begin
          FStateLock.Acquire;
          try
            FAttachmentId := AttId;
          finally
            FStateLock.Release;
          end;
        end;
      end;
      Q.Close;
    except
    end;
  finally
    Q.Free;
  end;
end;

function TFirebirdSqlDbSession.CreateAndPrepareQuery(
  const ASQL: string;
  const AIsSelect: Boolean;
  out APrepMs: Int64
): TSQLQuery;
var
  Q: TSQLQuery;
  PrepStart: QWord;
begin
  Q := TSQLQuery.Create(nil);
  try
    Q.DataBase := FConn;
    Q.Transaction := FTrans;
    Q.ParamCheck := False;
    Q.ParseSQL := False;
    if AIsSelect then
    begin
      { Modo somente-leitura e unidirecional evita acumular todos os registros na RAM do TBufDataset }
      Q.ReadOnly := True;
      Q.UniDirectional := True;
    end;
    Q.SQL.Text := EncodeFirebirdSqlForCharset(ASQL, FActiveCharset);

    PrepStart := GetTickCount64;
    Q.Prepare;
    APrepMs := Int64(GetTickCount64 - PrepStart);
    Result := Q;
  except
    Q.Free;
    raise;
  end;
end;

procedure TFirebirdSqlDbSession.EnsureRelationNamesLoaded;
var
  Q: TSQLQuery;
  RelId, RelName: string;
begin
  if (FRelationNames = nil) or (FRelationNames.Count > 0) or (not IsConnected) or (not InTransaction) then
    Exit;

  Q := TSQLQuery.Create(nil);
  try
    Q.DataBase := FConn;
    Q.Transaction := FTrans;
    Q.ParamCheck := False;
    Q.SQL.Text := 'SELECT RDB$RELATION_ID, TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS WHERE RDB$RELATION_ID IS NOT NULL';
    try
      Q.Open;
      while not Q.EOF do
      begin
        RelId := Trim(Q.Fields[0].AsString);
        RelName := Trim(Q.Fields[1].AsString);
        if (RelId <> '') and (RelName <> '') then
          FRelationNames.Values[RelId] := RelName;
        Q.Next;
      end;
      Q.Close;
    except
      { Não impede execução de consultas caso RDB$RELATIONS não esteja acessível }
    end;
  finally
    Q.Free;
  end;
end;

function TFirebirdSqlDbSession.CaptureDatabaseCounters(out ACounters: TFirebirdDbCounters): Boolean;
const
  INFO_BUF_SIZE = 32000;
var
  Status: TStatusVector;
  DbHandle: isc_db_handle;
  ResBuf: array[0..INFO_BUF_SIZE - 1] of Byte;

  function QueryScalarCounters: Boolean;
  var
    ReqBuf: array[0..6] of AnsiChar;
    Idx, Len: Integer;
    Item: Byte;
    Val: Int64;
  begin
    Result := False;
    ReqBuf[0] := AnsiChar(isc_info_reads);
    ReqBuf[1] := AnsiChar(isc_info_writes);
    ReqBuf[2] := AnsiChar(isc_info_fetches);
    ReqBuf[3] := AnsiChar(isc_info_marks);
    ReqBuf[4] := AnsiChar(isc_info_current_memory);
    ReqBuf[5] := AnsiChar(isc_info_max_memory);
    ReqBuf[6] := AnsiChar(isc_info_end);
    FillChar(ResBuf[0], SizeOf(ResBuf), 0);
    if isc_database_info(@Status[0], @DbHandle, Length(ReqBuf), @ReqBuf[0], SizeOf(ResBuf), PAnsiChar(@ResBuf[0])) <> 0 then
      Exit;

    Idx := 0;
    while Idx < SizeOf(ResBuf) do
    begin
      Item := ResBuf[Idx];
      if Item in [isc_info_end, isc_info_error, isc_info_truncated] then
        Break;
      if Idx + 3 > SizeOf(ResBuf) then
        Break;
      Len := isc_vax_integer(PAnsiChar(@ResBuf[Idx + 1]), 2);
      Inc(Idx, 3);
      if (Len < 0) or (Idx + Len > SizeOf(ResBuf)) then
        Break;
      Val := ReadVaxInt64(@ResBuf[Idx], Len);
      case Item of
        isc_info_reads: ACounters.Reads := Val;
        isc_info_writes: ACounters.Writes := Val;
        isc_info_fetches: ACounters.Fetches := Val;
        isc_info_marks: ACounters.Marks := Val;
        isc_info_current_memory: ACounters.CurrentMemory := Val;
        isc_info_max_memory: ACounters.MaxMemory := Val;
      end;
      Inc(Idx, Len);
    end;
    Result := True;
  end;

  function QueryTableCounter(const AInfoCode: Byte): TFirebirdTableCountArray;
  var
    ReqBuf: array[0..1] of AnsiChar;
    Idx, BlockLen, BlockEnd, Count: Integer;
    Item: Byte;
  begin
    SetLength(Result, 0);
    ReqBuf[0] := AnsiChar(AInfoCode);
    ReqBuf[1] := AnsiChar(isc_info_end);
    FillChar(ResBuf[0], SizeOf(ResBuf), 0);
    if isc_database_info(@Status[0], @DbHandle, Length(ReqBuf), @ReqBuf[0], SizeOf(ResBuf), PAnsiChar(@ResBuf[0])) <> 0 then
      Exit;

    Idx := 0;
    Count := 0;
    while Idx < SizeOf(ResBuf) do
    begin
      Item := ResBuf[Idx];
      if Item in [isc_info_end, isc_info_error, isc_info_truncated] then
        Break;
      if Idx + 3 > SizeOf(ResBuf) then
        Break;
      BlockLen := isc_vax_integer(PAnsiChar(@ResBuf[Idx + 1]), 2);
      Inc(Idx, 3);
      if (BlockLen < 0) or (Idx + BlockLen > SizeOf(ResBuf)) then
        Break;
      BlockEnd := Idx + BlockLen;
      if Item = AInfoCode then
      begin
        while Idx + 6 <= BlockEnd do
        begin
          Inc(Count);
          SetLength(Result, Count);
          Result[Count - 1].RelationId := Integer(Word(isc_vax_integer(PAnsiChar(@ResBuf[Idx]), 2)));
          Result[Count - 1].Count := ReadVaxInt64(@ResBuf[Idx + 2], 4);
          Inc(Idx, 6);
        end;
      end;
      Idx := BlockEnd;
    end;
  end;

begin
  FillChar(ACounters, SizeOf(ACounters), 0);
  Result := False;
  if (not IsConnected) or (FConn.Handle = nil) then
    Exit;

  DbHandle := isc_db_handle(PtrUInt(FConn.Handle));
  if DbHandle = isc_db_handle(0) then
    Exit;

  try
    if not QueryScalarCounters then
      Exit;
    ACounters.SeqReads := QueryTableCounter(isc_info_read_seq_count);
    ACounters.IdxReads := QueryTableCounter(isc_info_read_idx_count);
    ACounters.Inserts := QueryTableCounter(isc_info_insert_count);
    ACounters.Updates := QueryTableCounter(isc_info_update_count);
    ACounters.Deletes := QueryTableCounter(isc_info_delete_count);
    ACounters.Valid := True;
    Result := True;
  except
    Result := False;
  end;
end;

function TFirebirdSqlDbSession.ExtractQueryPlan(const AQuery: TSQLQuery): string;
const
  PLAN_BUF_SIZE = 16384;
var
  Cur: TSQLCursor;
  RawStmt: Pointer;
  StmtHandle: isc_stmt_handle;
  Status: TStatusVector;
  ReqBuf: array[0..1] of AnsiChar;
  ResBuf: array[0..PLAN_BUF_SIZE - 1] of Byte;
  PlanLen: Integer;
begin
  Result := '';
  if AQuery = nil then
    Exit;
  try
    Cur := TExposedSQLQuery(AQuery).Cursor;
    if not (Cur is TIBCursor) then
      Exit;
    RawStmt := TExposedIBCursor(Cur).StatementHandle;
    if RawStmt = nil then
      Exit;

    StmtHandle := isc_stmt_handle(PtrUInt(RawStmt));
    ReqBuf[0] := AnsiChar(isc_info_sql_get_plan);
    ReqBuf[1] := AnsiChar(isc_info_end);
    FillChar(ResBuf[0], SizeOf(ResBuf), 0);

    if isc_dsql_sql_info(@Status[0], @StmtHandle, Length(ReqBuf), @ReqBuf[0], SizeOf(ResBuf), PAnsiChar(@ResBuf[0])) <> 0 then
      Exit;

    if ResBuf[0] = isc_info_sql_get_plan then
    begin
      PlanLen := isc_vax_integer(PAnsiChar(@ResBuf[1]), 2);
      if (PlanLen > 0) and (3 + PlanLen <= SizeOf(ResBuf)) then
      begin
        SetString(Result, PAnsiChar(@ResBuf[3]), PlanLen);
        Result := Trim(Result);
      end;
    end;
  except
    Result := '';
  end;
end;

procedure TFirebirdSqlDbSession.PopulatePerformanceStats(
  const ABefore, AAfter: TFirebirdDbCounters;
  const APlan: string;
  const APrepMs, AExecMs: Int64;
  const ATarget: TQueryResult
);
var
  Merged: array of TTablePerformanceStat;

  function FindOrAddTable(const ARelId: Integer): Integer;
  var
    I: Integer;
    RelName: string;
  begin
    for I := 0 to High(Merged) do
    begin
      if Merged[I].RelationId = ARelId then
        Exit(I);
    end;
    Result := Length(Merged);
    SetLength(Merged, Result + 1);
    Merged[Result].RelationId := ARelId;
    RelName := '';
    if FRelationNames <> nil then
      RelName := FRelationNames.Values[IntToStr(ARelId)];
    if RelName = '' then
      RelName := 'RELATION#' + IntToStr(ARelId);
    Merged[Result].TableName := RelName;
    Merged[Result].NonIndexedReads := 0;
    Merged[Result].IndexedReads := 0;
    Merged[Result].Inserts := 0;
    Merged[Result].Updates := 0;
    Merged[Result].Deletes := 0;
  end;

  function FindCount(const AArr: TFirebirdTableCountArray; const ARelId: Integer): Int64;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to High(AArr) do
    begin
      if AArr[I].RelationId = ARelId then
        Exit(AArr[I].Count);
    end;
  end;

  procedure ApplyDelta(const ABeforeArr, AAfterArr: TFirebirdTableCountArray; const AKind: Integer);
  var
    I, Idx: Integer;
    RelId: Integer;
    Delta: Int64;
  begin
    for I := 0 to High(AAfterArr) do
    begin
      RelId := AAfterArr[I].RelationId;
      Delta := AAfterArr[I].Count - FindCount(ABeforeArr, RelId);
      if Delta > 0 then
      begin
        Idx := FindOrAddTable(RelId);
        case AKind of
          0: Inc(Merged[Idx].NonIndexedReads, Delta);
          1: Inc(Merged[Idx].IndexedReads, Delta);
          2: Inc(Merged[Idx].Inserts, Delta);
          3: Inc(Merged[Idx].Updates, Delta);
          4: Inc(Merged[Idx].Deletes, Delta);
        end;
      end;
    end;
  end;

var
  I, J: Integer;
  Tmp: TTablePerformanceStat;
  SwapNeeded: Boolean;
begin
  if ATarget = nil then
    Exit;

  ATarget.Performance.Clear;
  ATarget.Performance.HasData := True;
  ATarget.Performance.PlanText := APlan;
  ATarget.Performance.PrepareTimeMs := APrepMs;
  ATarget.Performance.ExecuteTimeMs := AExecMs;
  ATarget.Performance.TotalTimeMs := APrepMs + AExecMs;

  if ABefore.Valid and AAfter.Valid then
  begin
    ATarget.Performance.DiskReads := Max(0, AAfter.Reads - ABefore.Reads);
    ATarget.Performance.DiskWrites := Max(0, AAfter.Writes - ABefore.Writes);
    ATarget.Performance.MemoryFetches := Max(0, AAfter.Fetches - ABefore.Fetches);
    ATarget.Performance.MemoryMarks := Max(0, AAfter.Marks - ABefore.Marks);
    ATarget.Performance.CurrentMemoryBytes := AAfter.CurrentMemory;
    ATarget.Performance.MaxMemoryBytes := AAfter.MaxMemory;

    SetLength(Merged, 0);
    ApplyDelta(ABefore.SeqReads, AAfter.SeqReads, 0);
    ApplyDelta(ABefore.IdxReads, AAfter.IdxReads, 1);
    ApplyDelta(ABefore.Inserts, AAfter.Inserts, 2);
    ApplyDelta(ABefore.Updates, AAfter.Updates, 3);
    ApplyDelta(ABefore.Deletes, AAfter.Deletes, 4);

    for I := 0 to High(Merged) - 1 do
      for J := I + 1 to High(Merged) do
      begin
        SwapNeeded := False;
        if Merged[J].NonIndexedReads > Merged[I].NonIndexedReads then
          SwapNeeded := True
        else if (Merged[J].NonIndexedReads = Merged[I].NonIndexedReads) and
                (Merged[J].IndexedReads > Merged[I].IndexedReads) then
          SwapNeeded := True
        else if (Merged[J].NonIndexedReads = Merged[I].NonIndexedReads) and
                (Merged[J].IndexedReads = Merged[I].IndexedReads) and
                (AnsiCompareText(Merged[J].TableName, Merged[I].TableName) < 0) then
          SwapNeeded := True;

        if SwapNeeded then
        begin
          Tmp := Merged[I];
          Merged[I] := Merged[J];
          Merged[J] := Tmp;
        end;
      end;

    for I := 0 to High(Merged) do
      ATarget.Performance.AddTableStat(Merged[I]);
  end;
end;

function TFirebirdSqlDbSession.ExecuteSQL(
  const ASQL: string;
  const AAutoCommit: Boolean;
  const AFetchBatchSize: Integer;
  const AMemoryLimitBytes: Int64
): TQueryResult;
var
  StartTick, ExecStart: QWord;
  PrepMs, ExecMs: Int64;
  Query: TSQLQuery;
  Cols: array of TQueryColumn;
  I, ColCount, EffectiveBatch: Integer;
  Cursor: IResultSetCursor;
  BeforeCounters, AfterCounters: TFirebirdDbCounters;
  PlanText, FallbackCharset: string;
  FallbackApplied, IsSelect: Boolean;
begin
  Result := TQueryResult.Create;
  Result.MemoryLimitBytes := AMemoryLimitBytes;
  StartTick := GetTickCount64;
  CloseActiveCursor;
  Query := nil;
  FallbackApplied := False;
  IsSelect := IsSelectLikeSQL(ASQL);
  try
    if not IsConnected then
      Connect;
    if not InTransaction then
      StartTransaction;

    CaptureAttachmentId;
    EnsureRelationNamesLoaded;
    CaptureDatabaseCounters(BeforeCounters);

    try
      Query := CreateAndPrepareQuery(ASQL, IsSelect, PrepMs);
    except
      on E: Exception do
      begin
        if IsSelect and IsBlockSizeLimitError(E) and
           IsMultiByteFirebirdCharset(FActiveCharset) and (not FHasUncommittedDML) then
        begin
          FallbackCharset := DetectSingleByteFallbackCharset;
          ReconnectWithCharset(FallbackCharset);
          CaptureDatabaseCounters(BeforeCounters);
          Query := CreateAndPrepareQuery(ASQL, IsSelect, PrepMs);
          FallbackApplied := True;
        end
        else
          raise;
      end;
    end;

    if (not IsSelect) and
       (TExposedSQLQuery(Query).Cursor <> nil) and
       TExposedSQLQuery(Query).Cursor.FSelectable then
    begin
      IsSelect := True;
      FHasUncommittedDML := True;
      Query.ReadOnly := True;
    end;

    PlanText := ExtractQueryPlan(Query);

    if IsSelect then
    begin
      ExecStart := GetTickCount64;
      if Pos('2.5', string(IBaseLoadedLibrary)) > 0 then
      begin
        GFbFetchLock.Acquire;
        try
          Query.Open;
        finally
          GFbFetchLock.Release;
        end;
      end
      else
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

      Cursor := TFirebirdResultCursor.Create(
        Query,
        ColCount,
        Self,
        BeforeCounters,
        PlanText,
        PrepMs,
        ExecStart,
        FActiveCharset
      );
      Query := nil; // Posse transferida para o Cursor

      if AFetchBatchSize <= 0 then
      begin
        while Cursor.HasMore and (not Result.IsMemoryLimitReached) do
          Cursor.FetchNext(1000, Result);
      end
      else
      begin
        EffectiveBatch := AFetchBatchSize;
        Cursor.FetchNext(EffectiveBatch, Result);
      end;
      if Result.IsMemoryLimitReached then
        Result.MarkMemoryLimitReached;
      ExecMs := Int64(GetTickCount64 - ExecStart);

      if Result.MemoryLimitReached then
      begin
        if CaptureDatabaseCounters(AfterCounters) then
          PopulatePerformanceStats(BeforeCounters, AfterCounters, PlanText, PrepMs, ExecMs, Result);
        Cursor.CloseCursor;
        Result.Cursor := nil;
        Result.MessageText := Result.LimitMessage;
      end
      else if Cursor.HasMore then
      begin
        FActiveCursor := Cursor;
        Result.Cursor := Cursor;
        Result.MessageText := Format('%d registro(s) carregado(s) (role para buscar mais).', [Result.RowCount]);
        if CaptureDatabaseCounters(AfterCounters) then
          PopulatePerformanceStats(BeforeCounters, AfterCounters, PlanText, PrepMs, ExecMs, Result);
      end
      else
      begin
        if CaptureDatabaseCounters(AfterCounters) then
          PopulatePerformanceStats(BeforeCounters, AfterCounters, PlanText, PrepMs, ExecMs, Result);
        Cursor.CloseCursor;
        Result.MessageText := Format('%d registro(s) retornado(s).', [Result.RowCount]);
      end;
      if FallbackApplied then
        Result.MessageText := Result.MessageText +
          Format(' [Charset da sessão ajustado automaticamente para %s devido ao limite de 64 KB do Firebird com UTF8]',
            [FActiveCharset]);
      Result.RowsAffected := Result.RowCount;
    end
    else
    begin
      try
        ExecStart := GetTickCount64;
        Query.ExecSQL;
        FHasUncommittedDML := True;
        ExecMs := Int64(GetTickCount64 - ExecStart);
        Result.HasResultSet := False;
        Result.RowsAffected := Query.RowsAffected;
        Result.MessageText := Format('Comando executado com sucesso. %d linha(s) afetada(s).', [Result.RowsAffected]);
        if CaptureDatabaseCounters(AfterCounters) then
          PopulatePerformanceStats(BeforeCounters, AfterCounters, PlanText, PrepMs, ExecMs, Result);
      finally
        FreeAndNil(Query);
      end;
    end;

    if AAutoCommit and InTransaction and (not Result.HasMoreRows) then
      Commit;

    Result.Success := True;
  except
    on E: Exception do
    begin
      FreeAndNil(Query);
      Result.Success := False;
      Result.MessageText := E.Message;
      if IsBlockSizeLimitError(E) then
      begin
        if IsMultiByteFirebirdCharset(FActiveCharset) and FHasUncommittedDML then
          Result.MessageText := Result.MessageText + LineEnding + LineEnding +
            'Dica: Há alterações pendentes na transação atual, impedindo a troca automática do charset UTF8. ' +
            'Execute Commit ou Rollback, ou altere o Charset da conexão para WIN1252, ISO8859_1 ou NONE.'
        else
          Result.MessageText := Result.MessageText + LineEnding + LineEnding +
            'Dica: A tabela excede o limite de 64 KB por linha do Firebird no buffer DSQL (especialmente com charset UTF8, que multiplica colunas texto por 4 bytes). ' +
            'Selecione apenas as colunas desejadas em vez de SELECT *, ou configure o Charset da conexão para WIN1252, ISO8859_1 ou NONE.';
      end;
    end;
  end;
  Result.ExecutionTimeMs := Int64(GetTickCount64 - StartTick);
  if Result.Performance.HasData then
    Result.Performance.TotalTimeMs := Result.ExecutionTimeMs;
end;

function TFirebirdSqlDbSession.CancelRunningQuery(out AMessage: string): Boolean;
var
  CancelFn: TFbCancelOperation;
  DbHandle: isc_db_handle;
  AttId: Int64;
  Status: TStatusVector;
  CancelSession: IDatabaseSession;
  Res: TQueryResult;
begin
  Result := False;
  AMessage := '';

  CancelFn := nil;
  GFbLibLock.Acquire;
  try
    if IBaseLibraryHandle <> NilHandle then
      Pointer(CancelFn) := GetProcedureAddress(IBaseLibraryHandle, 'fb_cancel_operation');
  finally
    GFbLibLock.Release;
  end;

  AttId := 0;
  FStateLock.Acquire;
  try
    DbHandle := FCancelDbHandle;
    AttId := FAttachmentId;
    if (DbHandle <> isc_db_handle(0)) and Assigned(CancelFn) then
    begin
      FillChar(Status[0], SizeOf(Status), 0);
      if CancelFn(@Status[0], @DbHandle, FB_CANCEL_RAISE) = 0 then
      begin
        AMessage := 'Sinal de cancelamento enviado ao Firebird (fb_cancel_operation).';
        Result := True;
        Exit;
      end;
    end;
  finally
    FStateLock.Release;
  end;

  if AttId > 0 then
  begin
    CancelSession := TFirebirdSqlDbSession.Create(FProfile);
    try
      try
        CancelSession.Connect;
        CancelSession.StartTransaction;
        Res := CancelSession.ExecuteSQL(
          Format('DELETE FROM MON$STATEMENTS WHERE MON$ATTACHMENT_ID = %d AND MON$STATE > 0', [AttId]),
          False,
          0
        );
        try
          if Res.Success then
          begin
            if CancelSession.InTransaction then
              CancelSession.Commit;
            AMessage := Format('Cancelamento enviado ao Firebird via MON$STATEMENTS (conexão #%d).', [AttId]);
            Result := True;
          end
          else
          begin
            if CancelSession.InTransaction then
              CancelSession.Rollback;
            AMessage := 'Falha ao cancelar via MON$STATEMENTS: ' + Res.MessageText;
          end;
        finally
          Res.Free;
        end;
      finally
        try
          CancelSession.Disconnect;
        except
        end;
        CancelSession := nil;
      end;
    except
      on E: Exception do
        AMessage := 'Falha ao solicitar cancelamento no Firebird: ' + E.Message;
    end;
    Exit;
  end;

  AMessage := 'Conexão ainda inicializando; o cancelamento será aplicado assim que possível.';
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

initialization
  GFbLibLock := TCriticalSection.Create;
  GFbFetchLock := TCriticalSection.Create;

finalization
  FreeAndNil(GFbFetchLock);
  FreeAndNil(GFbLibLock);

end.
