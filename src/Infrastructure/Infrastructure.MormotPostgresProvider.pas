unit Infrastructure.MormotPostgresProvider;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  SyncObjs,
  Math,
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
  TMormotPostgresSession = class;

  { Cursor em streaming no servidor PostgreSQL (DECLARE NO SCROLL CURSOR + FETCH FORWARD) }
  TMormotPostgresServerCursor = class(TInterfacedObject, IResultSetCursor)
  private
    FSession: TMormotPostgresSession;
    FConn: TSqlDBConnection;
    FCursorName: string;
    FColCount: Integer;
    FHasMore: Boolean;
    FClosed: Boolean;
    FOwnsTransaction: Boolean;
    FExecStartTick: QWord;
    FColsLoaded: Boolean;
  public
    constructor Create(
      const ASession: TMormotPostgresSession;
      const AConn: TSqlDBConnection;
      const ACursorName: string;
      const AOwnsTransaction: Boolean;
      const AExecStartTick: QWord
    );
    destructor Destroy; override;
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure RefreshPerformance(const ATarget: TQueryResult);
    procedure CloseCursor;
  end;

  { Cursor sob demanda para PostgreSQL via mORMot2 (fallback para SHOW/EXPLAIN/RETURNING) }
  TMormotPostgresResultCursor = class(TInterfacedObject, IResultSetCursor)
  private
    FStmt: ISqlDBStatement;
    FColCount: Integer;
    FHasMore: Boolean;
    FExecStartTick: QWord;
  public
    constructor Create(const AStmt: ISqlDBStatement; const AColCount: Integer; const AExecStartTick: QWord);
    destructor Destroy; override;
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure RefreshPerformance(const ATarget: TQueryResult);
    procedure CloseCursor;
  end;

  { Sessão PostgreSQL usando mORMot2 (mormot.db.sql.postgres) }
  TMormotPostgresSession = class(TInterfacedObject, IDatabaseSession)
  private
    FProfile: TConnectionProfile;
    FProps: TSqlDBPostgresConnectionProperties;
    FConn: TSqlDBConnection;
    FActiveCursor: IResultSetCursor;
    FStateLock: TCriticalSection;
    FBackendPid: Int64;
    FCursorCounter: Int64;
    function IsSelectLikeSQL(const ASQL: string): Boolean;
    function FieldTypeToStr(const AType: TSqlDBFieldType): string;
    function ExtractExplainPlan(const ASQL: string): string;
    procedure CaptureBackendPid;
    procedure CloseActiveCursor;
    procedure ExecuteNonQueryDirect(const ASQL: string);
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
      const AFetchBatchSize: Integer = DEFAULT_PG_FETCH_BATCH;
      const AMemoryLimitBytes: Int64 = DEFAULT_RESULT_MEMORY_LIMIT_BYTES
    ): TQueryResult;
    function CancelRunningQuery(out AMessage: string): Boolean;
  end;

  { Provedor PostgreSQL via mORMot2 }
  TMormotPostgresProvider = class(TInterfacedObject, IDatabaseProvider)
  public
    function DatabaseType: TDatabaseType;
    function TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
    function CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
  end;

function PostgresFieldTypeToStr(const AType: TSqlDBFieldType): string;
function CanUsePostgresServerCursor(const ASQL: string): Boolean;

implementation

uses
  mormot.db.raw.postgres;

type
  TExposedPgStatement = class(TSqlDBPostgresStatement);

function PostgresFieldTypeToStr(const AType: TSqlDBFieldType): string;
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

function CanUsePostgresServerCursor(const ASQL: string): Boolean;
var
  Cleaned, FirstKw, Tok, DollarTag: string;
  I, J, Len: Integer;
  InSingle, InDouble, InLineCom, InBlockCom: Boolean;

  function IsIdentChar(const C: Char): Boolean;
  begin
    Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  end;

  procedure CheckToken(const ATok: string);
  var
    Up: string;
  begin
    if ATok = '' then
      Exit;
    Up := UpperCase(ATok);
    if FirstKw = '' then
      FirstKw := Up
    else if (Up = 'INSERT') or (Up = 'UPDATE') or (Up = 'DELETE') then
      Tok := 'DML_FOUND';
  end;

begin
  Result := False;
  Cleaned := Trim(StripLeadingSqlComments(ASQL));
  while (Cleaned <> '') and (Cleaned[Length(Cleaned)] in [';', ' ', #9, #10, #13]) do
    Cleaned := TrimRight(Copy(Cleaned, 1, Length(Cleaned) - 1));
  if Cleaned = '' then
    Exit;

  FirstKw := '';
  Tok := '';
  Len := Length(Cleaned);
  I := 1;
  InSingle := False;
  InDouble := False;
  InLineCom := False;
  InBlockCom := False;
  DollarTag := '';

  while I <= Len do
  begin
    if InLineCom then
    begin
      if Cleaned[I] = #10 then
        InLineCom := False;
      Inc(I);
      Continue;
    end;
    if InBlockCom then
    begin
      if (I < Len) and (Cleaned[I] = '*') and (Cleaned[I + 1] = '/') then
      begin
        InBlockCom := False;
        Inc(I, 2);
      end
      else
        Inc(I);
      Continue;
    end;
    if DollarTag <> '' then
    begin
      if Copy(Cleaned, I, Length(DollarTag)) = DollarTag then
      begin
        Inc(I, Length(DollarTag));
        DollarTag := '';
      end
      else
        Inc(I);
      Continue;
    end;
    if InSingle then
    begin
      if Cleaned[I] = '''' then
      begin
        if (I < Len) and (Cleaned[I + 1] = '''') then
          Inc(I, 2)
        else
        begin
          InSingle := False;
          Inc(I);
        end;
      end
      else
        Inc(I);
      Continue;
    end;
    if InDouble then
    begin
      if Cleaned[I] = '"' then
      begin
        if (I < Len) and (Cleaned[I + 1] = '"') then
          Inc(I, 2)
        else
        begin
          InDouble := False;
          Inc(I);
        end;
      end
      else
        Inc(I);
      Continue;
    end;

    if (I < Len) and (Cleaned[I] = '-') and (Cleaned[I + 1] = '-') then
    begin
      InLineCom := True;
      Inc(I, 2);
      Continue;
    end;
    if (I < Len) and (Cleaned[I] = '/') and (Cleaned[I + 1] = '*') then
    begin
      InBlockCom := True;
      Inc(I, 2);
      Continue;
    end;
    if Cleaned[I] = '''' then
    begin
      InSingle := True;
      Inc(I);
      Continue;
    end;
    if Cleaned[I] = '"' then
    begin
      InDouble := True;
      Inc(I);
      Continue;
    end;
    if Cleaned[I] = '$' then
    begin
      J := I + 1;
      while (J <= Len) and (Cleaned[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(J);
      if (J <= Len) and (Cleaned[J] = '$') then
      begin
        DollarTag := Copy(Cleaned, I, J - I + 1);
        I := J + 1;
        Continue;
      end;
    end;

    if Cleaned[I] = ';' then
      Exit(False); // Múltiplas instruções não suportam cursor único

    if IsIdentChar(Cleaned[I]) then
    begin
      J := I;
      while (J <= Len) and IsIdentChar(Cleaned[J]) do
        Inc(J);
      CheckToken(Copy(Cleaned, I, J - I));
      if FirstKw = '' then
        FirstKw := UpperCase(Copy(Cleaned, I, J - I));
      I := J;
      Continue;
    end;

    Inc(I);
  end;

  if (FirstKw = 'SELECT') or (FirstKw = 'TABLE') or (FirstKw = 'VALUES') then
    Result := True
  else if FirstKw = 'WITH' then
    Result := (Tok <> 'DML_FOUND');
end;

{ TMormotPostgresServerCursor }

constructor TMormotPostgresServerCursor.Create(
  const ASession: TMormotPostgresSession;
  const AConn: TSqlDBConnection;
  const ACursorName: string;
  const AOwnsTransaction: Boolean;
  const AExecStartTick: QWord
);
begin
  inherited Create;
  FSession := ASession;
  FConn := AConn;
  FCursorName := ACursorName;
  FOwnsTransaction := AOwnsTransaction;
  FExecStartTick := AExecStartTick;
  FColCount := 0;
  FColsLoaded := False;
  FClosed := False;
  FHasMore := (FConn <> nil) and (FCursorName <> '');
end;

destructor TMormotPostgresServerCursor.Destroy;
begin
  CloseCursor;
  inherited Destroy;
end;

function TMormotPostgresServerCursor.HasMore: Boolean;
begin
  Result := FHasMore and (not FClosed) and (FConn <> nil);
end;

function TMormotPostgresServerCursor.FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
var
  Remaining, Chunk, ChunkFetched, I: Integer;
  RawStmt: TSqlDBStatement;
  Stmt: ISqlDBStatement;
  Cols: array of TQueryColumn;
  Row: TQueryRow;
begin
  Result := 0;
  if not HasMore then
    Exit;

  if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
  begin
    ATarget.MarkMemoryLimitReached;
    RefreshPerformance(ATarget);
    CloseCursor;
    Exit;
  end;

  if ABatchSize <= 0 then
    Remaining := 500
  else
    Remaining := ABatchSize;

  while Remaining > 0 do
  begin
    if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
    begin
      ATarget.MarkMemoryLimitReached;
      RefreshPerformance(ATarget);
      CloseCursor;
      Break;
    end;

    Chunk := Min(Remaining, 500);
    ChunkFetched := 0;
    RawStmt := FConn.NewStatement;
    Stmt := RawStmt;
    RawStmt.Prepare(RawUtf8(Format('FETCH FORWARD %d FROM "%s"', [Chunk, FCursorName])), True);
    Stmt.ExecutePrepared;
    try
      if not FColsLoaded then
      begin
        FColCount := Stmt.ColumnCount;
        if (ATarget <> nil) and (ATarget.ColumnCount = 0) and (FColCount > 0) then
        begin
          SetLength(Cols, FColCount);
          for I := 0 to FColCount - 1 do
          begin
            Cols[I].Name := string(Stmt.ColumnName(I));
            Cols[I].DataTypeName := PostgresFieldTypeToStr(Stmt.ColumnType(I));
            Cols[I].IsNullable := True;
          end;
          ATarget.SetColumns(Cols);
        end;
        FColsLoaded := True;
      end;

      while Stmt.Step do
      begin
        if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
          Break;
        SetLength(Row, FColCount);
        for I := 0 to FColCount - 1 do
        begin
          Row[I].IsNull := Stmt.ColumnNull(I);
          if Row[I].IsNull then
            Row[I].AsText := ''
          else if Stmt.ColumnType(I) = ftBlob then
            Row[I].AsText := '(BYTEA)'
          else
            Row[I].AsText := TruncateGridCellText(string(Stmt.ColumnUtf8(I)));
        end;
        if ATarget <> nil then
          ATarget.AddRow(Row);
        Inc(ChunkFetched);
        Inc(Result);
        if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
          Break;
      end;
    finally
      Stmt.ReleaseRows;
      Stmt := nil;
    end;

    Dec(Remaining, ChunkFetched);
    if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
    begin
      ATarget.MarkMemoryLimitReached;
      RefreshPerformance(ATarget);
      CloseCursor;
      Break;
    end;
    if ChunkFetched < Chunk then
    begin
      RefreshPerformance(ATarget);
      CloseCursor;
      Break;
    end;
  end;
end;

procedure TMormotPostgresServerCursor.RefreshPerformance(const ATarget: TQueryResult);
begin
  if (ATarget <> nil) and ATarget.Performance.HasData then
  begin
    ATarget.Performance.ExecuteTimeMs := Int64(GetTickCount64 - FExecStartTick);
    ATarget.Performance.TotalTimeMs := ATarget.Performance.ExecuteTimeMs;
  end;
end;

procedure TMormotPostgresServerCursor.CloseCursor;
var
  RawStmt: TSqlDBStatement;
  Stmt: ISqlDBStatement;
begin
  if FClosed then
    Exit;
  FClosed := True;
  FHasMore := False;

  if FConn <> nil then
  begin
    try
      if FConn.IsConnected and (FCursorName <> '') then
      begin
        RawStmt := FConn.NewStatement;
        Stmt := RawStmt;
        RawStmt.Prepare(RawUtf8(Format('CLOSE "%s"', [FCursorName])), False);
        Stmt.ExecutePrepared;
        Stmt := nil;
      end;
    except
    end;

    if FOwnsTransaction and FConn.IsConnected and (FConn.TransactionCount > 0) then
    begin
      try
        FConn.Commit;
      except
        try
          if FConn.TransactionCount > 0 then
            FConn.Rollback;
        except
        end;
      end;
    end;
  end;

  FSession := nil;
  FConn := nil;
end;

{ TMormotPostgresResultCursor }

constructor TMormotPostgresResultCursor.Create(
  const AStmt: ISqlDBStatement;
  const AColCount: Integer;
  const AExecStartTick: QWord
);
begin
  inherited Create;
  FStmt := AStmt;
  FColCount := AColCount;
  FExecStartTick := AExecStartTick;
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
      Row[I].IsNull := FStmt.ColumnNull(I);
      if Row[I].IsNull then
        Row[I].AsText := ''
      else if FStmt.ColumnType(I) = ftBlob then
        Row[I].AsText := '(BYTEA)'
      else
        Row[I].AsText := TruncateGridCellText(string(FStmt.ColumnUtf8(I)));
    end;
    ATarget.AddRow(Row);
    Inc(Count);
    if (ATarget <> nil) and ATarget.IsMemoryLimitReached then
    begin
      ATarget.MarkMemoryLimitReached;
      RefreshPerformance(ATarget);
      CloseCursor;
      Break;
    end;
  end;

  Result := Count;
  if HasMore and (Count < ABatchSize) then
  begin
    RefreshPerformance(ATarget);
    CloseCursor;
  end;
end;

procedure TMormotPostgresResultCursor.RefreshPerformance(const ATarget: TQueryResult);
begin
  if (ATarget <> nil) and ATarget.Performance.HasData then
  begin
    ATarget.Performance.ExecuteTimeMs := Int64(GetTickCount64 - FExecStartTick);
    ATarget.Performance.TotalTimeMs := ATarget.Performance.ExecuteTimeMs;
  end;
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
  FStateLock := TCriticalSection.Create;
  FBackendPid := 0;
  FCursorCounter := 0;
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
  FStateLock.Free;
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
  CaptureBackendPid;
end;

procedure TMormotPostgresSession.Disconnect;
begin
  FStateLock.Acquire;
  try
    FBackendPid := 0;
  finally
    FStateLock.Release;
  end;
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

procedure TMormotPostgresSession.CaptureBackendPid;
var
  RawStmt: TSqlDBStatement;
  PidStmt: ISqlDBStatement;
  Pid: Int64;
begin
  FStateLock.Acquire;
  try
    if FBackendPid > 0 then
      Exit;
  finally
    FStateLock.Release;
  end;

  if not IsConnected then
    Exit;

  try
    RawStmt := FConn.NewStatement;
    PidStmt := RawStmt;
    RawStmt.Prepare('SELECT pg_backend_pid()', True);
    PidStmt.ExecutePrepared;
    try
      if PidStmt.Step and (PidStmt.ColumnCount > 0) then
      begin
        Pid := StrToInt64Def(Trim(string(PidStmt.ColumnUtf8(0))), 0);
        if Pid > 0 then
        begin
          FStateLock.Acquire;
          try
            FBackendPid := Pid;
          finally
            FStateLock.Release;
          end;
        end;
      end;
    finally
      PidStmt.ReleaseRows;
    end;
  except
  end;
end;

procedure TMormotPostgresSession.ExecuteNonQueryDirect(const ASQL: string);
var
  RawStmt: TSqlDBStatement;
  Stmt: ISqlDBStatement;
begin
  RawStmt := FConn.NewStatement;
  Stmt := RawStmt;
  RawStmt.Prepare(RawUtf8(ASQL), False);
  Stmt.ExecutePrepared;
  Stmt := nil;
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
begin
  Result := IsSelectLikeSQLText(ASQL, True) or CanUsePostgresServerCursor(ASQL);
end;

function TMormotPostgresSession.FieldTypeToStr(const AType: TSqlDBFieldType): string;
begin
  Result := PostgresFieldTypeToStr(AType);
end;

function TMormotPostgresSession.ExtractExplainPlan(const ASQL: string): string;
var
  CleanSQL, Line: string;
  ExplainRaw: TSqlDBStatement;
  ExplainStmt: ISqlDBStatement;
begin
  Result := '';
  if not IsSelectLikeSQLText(ASQL, False) then
    Exit;

  CleanSQL := Trim(ASQL);
  while (CleanSQL <> '') and (CleanSQL[Length(CleanSQL)] = ';') do
    CleanSQL := TrimRight(Copy(CleanSQL, 1, Length(CleanSQL) - 1));
  if CleanSQL = '' then
    Exit;

  try
    ExplainRaw := FConn.NewStatement;
    ExplainStmt := ExplainRaw;
    ExplainRaw.Prepare(RawUtf8('EXPLAIN (COSTS true) ' + CleanSQL), True);
    ExplainStmt.ExecutePrepared;
    try
      while ExplainStmt.Step do
      begin
        if ExplainStmt.ColumnCount > 0 then
        begin
          Line := string(ExplainStmt.ColumnUtf8(0));
          if Result <> '' then
            Result := Result + LineEnding;
          Result := Result + Line;
        end;
      end;
    finally
      ExplainStmt.ReleaseRows;
    end;
  except
    Result := '';
  end;
end;

function TMormotPostgresSession.ExecuteSQL(
  const ASQL: string;
  const AAutoCommit: Boolean;
  const AFetchBatchSize: Integer;
  const AMemoryLimitBytes: Int64
): TQueryResult;
var
  StartTick, ExecStart: QWord;
  ExecMs: Int64;
  ExpectResults, WasSelectLike, OwnsTx, UsedSavepoint: Boolean;
  RawStmt: TSqlDBStatement;
  Stmt: ISqlDBStatement;
  Cols: array of TQueryColumn;
  I, ColCount: Integer;
  Cursor: IResultSetCursor;
  CleanSQL, CursorName: string;
begin
  Result := TQueryResult.Create;
  Result.MemoryLimitBytes := AMemoryLimitBytes;
  StartTick := GetTickCount64;
  CloseActiveCursor;
  try
    if not IsConnected then
      Connect;
    CaptureBackendPid;

    if (not AAutoCommit) and (not InTransaction) then
      StartTransaction;

    ExpectResults := IsSelectLikeSQL(ASQL);
    WasSelectLike := ExpectResults;
    ExecStart := GetTickCount64;

    CleanSQL := Trim(ASQL);
    while (CleanSQL <> '') and (CleanSQL[Length(CleanSQL)] in [';', ' ', #9, #10, #13]) do
      CleanSQL := TrimRight(Copy(CleanSQL, 1, Length(CleanSQL) - 1));

    if ExpectResults and CanUsePostgresServerCursor(CleanSQL) then
    begin
      OwnsTx := False;
      UsedSavepoint := False;
      if not InTransaction then
      begin
        StartTransaction;
        OwnsTx := True;
      end
      else
      begin
        ExecuteNonQueryDirect('SAVEPOINT _mdbsql_cur_sp');
        UsedSavepoint := True;
      end;

      Inc(FCursorCounter);
      CursorName := '_mdbsql_cur_' + IntToStr(FCursorCounter);
      try
        ExecuteNonQueryDirect(Format('DECLARE "%s" NO SCROLL CURSOR FOR %s', [CursorName, CleanSQL]));
        if UsedSavepoint then
        begin
          ExecuteNonQueryDirect('RELEASE SAVEPOINT _mdbsql_cur_sp');
          UsedSavepoint := False;
        end;
      except
        if OwnsTx and InTransaction then
        begin
          try
            FConn.Rollback;
          except
          end;
        end
        else if UsedSavepoint and InTransaction then
        begin
          try
            ExecuteNonQueryDirect('ROLLBACK TO SAVEPOINT _mdbsql_cur_sp');
            ExecuteNonQueryDirect('RELEASE SAVEPOINT _mdbsql_cur_sp');
          except
          end;
        end;
        raise;
      end;

      Result.HasResultSet := True;
      Cursor := TMormotPostgresServerCursor.Create(Self, FConn, CursorName, OwnsTx, ExecStart);
      if AFetchBatchSize <= 0 then
      begin
        while Cursor.HasMore and (not Result.IsMemoryLimitReached) do
          Cursor.FetchNext(500, Result);
      end
      else
        Cursor.FetchNext(AFetchBatchSize, Result);

      if Result.IsMemoryLimitReached then
        Result.MarkMemoryLimitReached;
      ExecMs := Int64(GetTickCount64 - ExecStart);

      if Result.MemoryLimitReached then
      begin
        Cursor.CloseCursor;
        Result.Cursor := nil;
        Result.MessageText := Result.LimitMessage;
      end
      else if Cursor.HasMore then
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

      Result.Performance.HasData := True;
      Result.Performance.ExecuteTimeMs := ExecMs;
      Result.Performance.PlanText := ExtractExplainPlan(CleanSQL);
    end
    else
    begin
      RawStmt := FConn.NewStatement;
      Stmt := RawStmt;
      RawStmt.Prepare(RawUtf8(ASQL), ExpectResults);
      Stmt.ExecutePrepared;

      if (not ExpectResults) and (RawStmt is TSqlDBPostgresStatement) and
         (TExposedPgStatement(RawStmt).fRes <> nil) and
         (TExposedPgStatement(RawStmt).fResStatus = PGRES_TUPLES_OK) then
      begin
        TExposedPgStatement(RawStmt).fTotalRowsRetrieved :=
          PQ.ntuples(TExposedPgStatement(RawStmt).fRes);
        TExposedPgStatement(RawStmt).fCurrentRow := -1;
        TExposedPgStatement(RawStmt).BindColumns;
        ExpectResults := Stmt.ColumnCount > 0;
      end;

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

        Cursor := TMormotPostgresResultCursor.Create(Stmt, ColCount, ExecStart);
        Stmt := nil;
        if AFetchBatchSize <= 0 then
        begin
          while Cursor.HasMore and (not Result.IsMemoryLimitReached) do
            Cursor.FetchNext(1000, Result);
        end
        else
          Cursor.FetchNext(AFetchBatchSize, Result);

        if Result.IsMemoryLimitReached then
          Result.MarkMemoryLimitReached;
        ExecMs := Int64(GetTickCount64 - ExecStart);

        if Result.MemoryLimitReached then
        begin
          Cursor.CloseCursor;
          Result.Cursor := nil;
          Result.MessageText := Result.LimitMessage;
        end
        else if Cursor.HasMore then
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

        Result.Performance.HasData := True;
        Result.Performance.ExecuteTimeMs := ExecMs;
        if WasSelectLike then
          Result.Performance.PlanText := ExtractExplainPlan(ASQL);
      end
      else
      begin
        ExecMs := Int64(GetTickCount64 - ExecStart);
        Result.HasResultSet := False;
        Result.RowsAffected := Stmt.UpdateCount;
        Result.MessageText := Format('Comando executado com sucesso. %d linha(s) afetada(s).', [Result.RowsAffected]);
        Result.Performance.HasData := True;
        Result.Performance.ExecuteTimeMs := ExecMs;
      end;
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
  if Result.Performance.HasData then
    Result.Performance.TotalTimeMs := Result.ExecutionTimeMs;
end;

function TMormotPostgresSession.CancelRunningQuery(out AMessage: string): Boolean;
var
  Pid: Int64;
  CancelSession: IDatabaseSession;
  Res: TQueryResult;
begin
  Result := False;
  AMessage := '';

  FStateLock.Acquire;
  try
    Pid := FBackendPid;
  finally
    FStateLock.Release;
  end;

  if Pid <= 0 then
  begin
    AMessage := 'Nenhuma consulta ativa identificada para cancelamento.';
    Exit;
  end;

  CancelSession := TMormotPostgresSession.Create(FProfile);
  try
    try
      CancelSession.Connect;
      Res := CancelSession.ExecuteSQL(Format('SELECT pg_cancel_backend(%d)', [Pid]), True, 0);
      try
        if Res.Success then
        begin
          AMessage := Format('Cancelamento enviado ao PostgreSQL (PID %d).', [Pid]);
          Result := True;
        end
        else
          AMessage := 'Falha ao cancelar no PostgreSQL: ' + Res.MessageText;
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
      AMessage := 'Falha ao enviar cancelamento ao PostgreSQL: ' + E.Message;
  end;
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
