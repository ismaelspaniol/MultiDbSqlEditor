unit Domain.QueryResult;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

const
  DEFAULT_RESULT_MEMORY_LIMIT_BYTES = Int64(128) * 1024 * 1024;
  MAX_GRID_CELL_CHARS = 65536;
  OS_MEMORY_CHECK_INTERVAL_MS = 150;
  OS_MEMORY_CHECK_DELTA_BYTES = Int64(4) * 1024 * 1024;
  OS_MEMORY_MIN_RESERVE_BYTES = Int64(512) * 1024 * 1024;
  OS_MEMORY_MAX_RESERVE_BYTES = Int64(1024) * 1024 * 1024;
  OS_MEMORY_SMALL_HOST_THRESHOLD_BYTES = Int64(2) * 1024 * 1024 * 1024;
  OS_MEMORY_SMALL_HOST_MIN_RESERVE_BYTES = Int64(128) * 1024 * 1024;

type
  TQueryResult = class;

  TSystemMemoryInfo = record
    Available: Boolean;
    TotalBytes: Int64;
    AvailableBytes: Int64;
    ReserveBytes: Int64;
  end;

  TQueryColumn = record
    Name: string;
    DataTypeName: string;
    IsNullable: Boolean;
  end;

  TQueryCell = record
    IsNull: Boolean;
    AsText: string;
  end;

  TQueryRow = array of TQueryCell;

  TTablePerformanceStat = record
    RelationId: Integer;
    TableName: string;
    NonIndexedReads: Int64;
    IndexedReads: Int64;
    Inserts: Int64;
    Updates: Int64;
    Deletes: Int64;
  end;
  TTablePerformanceStatArray = array of TTablePerformanceStat;

  { Estatísticas de performance de uma execução SQL (estilo IBExpert Performance Analysis) }
  TQueryPerformanceStats = class
  public
    HasData: Boolean;
    PlanText: string;
    PrepareTimeMs: Int64;
    ExecuteTimeMs: Int64;
    TotalTimeMs: Int64;
    DiskReads: Int64;
    DiskWrites: Int64;
    MemoryFetches: Int64;
    MemoryMarks: Int64;
    CurrentMemoryBytes: Int64;
    MaxMemoryBytes: Int64;
    TableStats: TTablePerformanceStatArray;
    constructor Create;
    procedure Clear;
    procedure AssignFrom(const ASource: TQueryPerformanceStats);
    procedure AddTableStat(const AStat: TTablePerformanceStat);
    function TotalNonIndexedReads: Int64;
    function TotalIndexedReads: Int64;
  end;

  { Cursor para carregamento sob demanda (paginação estilo IBExpert/DBeaver) }
  IResultSetCursor = interface
    ['{8F6A52F0-8A2C-4E1C-A31B-6C9E01B5A010}']
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure RefreshPerformance(const ATarget: TQueryResult);
    procedure CloseCursor;
  end;

  { Resultado padronizado de execução SQL (SELECT, DML ou DDL) }
  TQueryResult = class
  private
    FSuccess: Boolean;
    FHasResultSet: Boolean;
    FColumns: array of TQueryColumn;
    FRows: array of TQueryRow;
    FRowCount: Integer;
    FRowCapacity: Integer;
    FEstimatedMemoryBytes: Int64;
    FBaselineMemoryBytes: Int64;
    FMemoryLimitBytes: Int64;
    FMemoryLimitReached: Boolean;
    FSystemMemoryLow: Boolean;
    FHasCheckedOsMem: Boolean;
    FLastOsMemCheckTick: QWord;
    FLastOsMemCheckBytes: Int64;
    FLimitMessage: string;
    FRowsAffected: Int64;
    FExecutionTimeMs: Int64;
    FMessageText: string;
    FErrorCode: Integer;
    FCursor: IResultSetCursor;
    FPerformance: TQueryPerformanceStats;
    FAllowDiskSpill: Boolean;
    FSpilledToDisk: Boolean;
    FSpillFilePath: string;
    FSpillStream: TFileStream;
    FSpillOffsets: array of Int64;
    FSpillCapacity: Integer;
    FCachedSpillRowIdx: Integer;
    FCachedSpillRow: TQueryRow;
    procedure EnsureRowCapacity(const AMinCapacity: Integer);
    procedure EnsureSpillCapacity(const AMinCapacity: Integer);
    procedure WriteSpillRow(const ARow: TQueryRow);
    function ReadSpillRow(const AIndex: Integer): TQueryRow;
    function ActivateDiskSpill: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetColumns(const AColumns: array of TQueryColumn);
    procedure AddRow(const ARow: TQueryRow);
    procedure UpdateCell(const ARowIndex, AColIndex: Integer; const AIsNull: Boolean; const AText: string);
    function InsertEmptyRow: Integer;
    procedure DeleteRow(const ARowIndex: Integer);
    function ColumnCount: Integer;
    function RowCount: Integer;
    function GetColumn(const AIndex: Integer): TQueryColumn;
    function GetRow(const AIndex: Integer): TQueryRow;
    function HasMoreRows: Boolean;
    function FetchMore(const ABatchSize: Integer = 100): Integer;
    function FetchAll: Integer;
    function AppendRowsFrom(const ASource: TQueryResult): Integer;
    procedure SortByColumn(const AColIndex: Integer; const AAscending: Boolean);
    procedure CloseCursor;
    function TotalTrackedMemoryBytes: Int64;
    function IsMemoryLimitReached: Boolean;
    procedure MarkMemoryLimitReached(const AReason: string = '');
    procedure MarkSystemMemoryLow(const AInfo: TSystemMemoryInfo);

    property Success: Boolean read FSuccess write FSuccess;
    property HasResultSet: Boolean read FHasResultSet write FHasResultSet;
    property RowsAffected: Int64 read FRowsAffected write FRowsAffected;
    property ExecutionTimeMs: Int64 read FExecutionTimeMs write FExecutionTimeMs;
    property MessageText: string read FMessageText write FMessageText;
    property ErrorCode: Integer read FErrorCode write FErrorCode;
    property Cursor: IResultSetCursor read FCursor write FCursor;
    property Performance: TQueryPerformanceStats read FPerformance;
    property EstimatedMemoryBytes: Int64 read FEstimatedMemoryBytes;
    property BaselineMemoryBytes: Int64 read FBaselineMemoryBytes write FBaselineMemoryBytes;
    property MemoryLimitBytes: Int64 read FMemoryLimitBytes write FMemoryLimitBytes;
    property MemoryLimitReached: Boolean read FMemoryLimitReached;
    property SystemMemoryLow: Boolean read FSystemMemoryLow;
    property LimitMessage: string read FLimitMessage;
    property AllowDiskSpill: Boolean read FAllowDiskSpill write FAllowDiskSpill;
    property SpilledToDisk: Boolean read FSpilledToDisk;
    property SpillFilePath: string read FSpillFilePath;
  end;

function ComputeSystemMemoryReserveBytes(const ATotalBytes: Int64): Int64;
function GetSystemMemoryInfo(out AInfo: TSystemMemoryInfo): Boolean;
function FormatApproxBytes(const ABytes: Int64): string;
function FormatByteSize(const ABytes: Int64): string;
function TruncateGridCellText(const AText: string; const AMaxChars: Integer = MAX_GRID_CELL_CHARS): string;
function EstimateQueryRowBytes(const ARow: TQueryRow): Int64;
function StripLeadingSqlComments(const ASQL: string): string;
function IsSelectLikeSQLText(const ASQL: string; const AIncludeExplainShow: Boolean = False): Boolean;
procedure TrimProcessMemoryUsage;

threadvar
  GThreadAllowDiskSpill: Boolean;

implementation

{$IFDEF WINDOWS}
uses
  Windows;

type
  TMemoryStatusEx = record
    dwLength: DWORD;
    dwMemoryLoad: DWORD;
    ullTotalPhys: QWord;
    ullAvailPhys: QWord;
    ullTotalPageFile: QWord;
    ullAvailPageFile: QWord;
    ullTotalVirtual: QWord;
    ullAvailVirtual: QWord;
    ullAvailExtendedVirtual: QWord;
  end;

function GlobalMemoryStatusEx(var lpBuffer: TMemoryStatusEx): BOOL; stdcall; external 'kernel32' name 'GlobalMemoryStatusEx';
{$ENDIF}

procedure TrimProcessMemoryUsage;
begin
  {$IFDEF WINDOWS}
  try
    SetProcessWorkingSetSize(GetCurrentProcess, PtrUInt(-1), PtrUInt(-1));
  except
  end;
  {$ENDIF}
end;

{ TQueryPerformanceStats }

constructor TQueryPerformanceStats.Create;
begin
  inherited Create;
  Clear;
end;

procedure TQueryPerformanceStats.Clear;
begin
  HasData := False;
  PlanText := '';
  PrepareTimeMs := 0;
  ExecuteTimeMs := 0;
  TotalTimeMs := 0;
  DiskReads := 0;
  DiskWrites := 0;
  MemoryFetches := 0;
  MemoryMarks := 0;
  CurrentMemoryBytes := 0;
  MaxMemoryBytes := 0;
  SetLength(TableStats, 0);
end;

procedure TQueryPerformanceStats.AssignFrom(const ASource: TQueryPerformanceStats);
begin
  if ASource = nil then
  begin
    Clear;
    Exit;
  end;
  HasData := ASource.HasData;
  PlanText := ASource.PlanText;
  PrepareTimeMs := ASource.PrepareTimeMs;
  ExecuteTimeMs := ASource.ExecuteTimeMs;
  TotalTimeMs := ASource.TotalTimeMs;
  DiskReads := ASource.DiskReads;
  DiskWrites := ASource.DiskWrites;
  MemoryFetches := ASource.MemoryFetches;
  MemoryMarks := ASource.MemoryMarks;
  CurrentMemoryBytes := ASource.CurrentMemoryBytes;
  MaxMemoryBytes := ASource.MaxMemoryBytes;
  TableStats := Copy(ASource.TableStats, 0, Length(ASource.TableStats));
end;

procedure TQueryPerformanceStats.AddTableStat(const AStat: TTablePerformanceStat);
var
  Idx: Integer;
begin
  Idx := Length(TableStats);
  SetLength(TableStats, Idx + 1);
  TableStats[Idx] := AStat;
end;

function TQueryPerformanceStats.TotalNonIndexedReads: Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(TableStats) do
    Inc(Result, TableStats[I].NonIndexedReads);
end;

function TQueryPerformanceStats.TotalIndexedReads: Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(TableStats) do
    Inc(Result, TableStats[I].IndexedReads);
end;

{ Helpers de memória e texto }

function ComputeSystemMemoryReserveBytes(const ATotalBytes: Int64): Int64;
begin
  if ATotalBytes <= 0 then
    Exit(OS_MEMORY_MIN_RESERVE_BYTES);

  if ATotalBytes <= OS_MEMORY_SMALL_HOST_THRESHOLD_BYTES then
  begin
    Result := ATotalBytes div 5;
    if Result < OS_MEMORY_SMALL_HOST_MIN_RESERVE_BYTES then
      Result := OS_MEMORY_SMALL_HOST_MIN_RESERVE_BYTES;
    Exit;
  end;

  Result := ATotalBytes div 10;
  if Result < OS_MEMORY_MIN_RESERVE_BYTES then
    Result := OS_MEMORY_MIN_RESERVE_BYTES
  else if Result > OS_MEMORY_MAX_RESERVE_BYTES then
    Result := OS_MEMORY_MAX_RESERVE_BYTES;
end;

function GetSystemMemoryInfo(out AInfo: TSystemMemoryInfo): Boolean;
{$IFDEF LINUX}
var
  Fd: THandle;
  Buf: array[0..4095] of AnsiChar;
  BytesRead, Idx, LineStart, LineEnd, KStart, ColonPos: LongInt;
  TotalKB, AvailKB, FreeKB, BuffersKB, CachedKB, ParsedVal: Int64;
  HasTotal, HasAvail, HasFree: Boolean;
  TotalBytes, AvailBytes: Int64;

  function MatchesKey(const AStart, AEnd: LongInt; const AKey: ShortString): Boolean;
  var
    KeyLen, K: Integer;
  begin
    KeyLen := Ord(AKey[0]);
    if (AEnd - AStart + 1) <> KeyLen then
      Exit(False);
    for K := 1 to KeyLen do
      if Buf[AStart + K - 1] <> AKey[K] then
        Exit(False);
    Result := True;
  end;

  function ParseIntAfter(const AFrom, ALineEnd: LongInt; out AVal: Int64): Boolean;
  var
    P: LongInt;
    HasDigit: Boolean;
  begin
    P := AFrom;
    while (P <= ALineEnd) and ((Buf[P] = ' ') or (Buf[P] = #9)) do
      Inc(P);
    AVal := 0;
    HasDigit := False;
    while (P <= ALineEnd) and (Buf[P] in ['0'..'9']) do
    begin
      HasDigit := True;
      if AVal <= (High(Int64) - 9) div 10 then
        AVal := AVal * 10 + (Ord(Buf[P]) - Ord('0'));
      Inc(P);
    end;
    Result := HasDigit;
  end;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  Result := False;

  { Leitura sem alocacoes no heap para continuar seguro mesmo sob pressao critica de RAM }
  Fd := FileOpen('/proc/meminfo', fmOpenRead or fmShareDenyNone);
  if Fd = feInvalidHandle then
    Exit(False);
  try
    BytesRead := FileRead(Fd, Buf[0], SizeOf(Buf));
  finally
    FileClose(Fd);
  end;

  if BytesRead <= 0 then
    Exit(False);

  TotalKB := 0;
  AvailKB := 0;
  FreeKB := 0;
  BuffersKB := 0;
  CachedKB := 0;
  HasTotal := False;
  HasAvail := False;
  HasFree := False;

  Idx := 0;
  while Idx < BytesRead do
  begin
    LineStart := Idx;
    while (Idx < BytesRead) and (Buf[Idx] <> #10) do
      Inc(Idx);
    LineEnd := Idx - 1;
    if (LineEnd >= LineStart) and (Buf[LineEnd] = #13) then
      Dec(LineEnd);
    if Idx < BytesRead then
      Inc(Idx);

    KStart := LineStart;
    while (KStart <= LineEnd) and ((Buf[KStart] = ' ') or (Buf[KStart] = #9)) do
      Inc(KStart);

    ColonPos := KStart;
    while (ColonPos <= LineEnd) and (Buf[ColonPos] <> ':') do
      Inc(ColonPos);

    if (ColonPos > KStart) and (ColonPos <= LineEnd) and
       ParseIntAfter(ColonPos + 1, LineEnd, ParsedVal) then
    begin
      if MatchesKey(KStart, ColonPos - 1, 'MemTotal') then
      begin
        TotalKB := ParsedVal;
        HasTotal := True;
      end
      else if MatchesKey(KStart, ColonPos - 1, 'MemAvailable') then
      begin
        AvailKB := ParsedVal;
        HasAvail := True;
      end
      else if MatchesKey(KStart, ColonPos - 1, 'MemFree') then
      begin
        FreeKB := ParsedVal;
        HasFree := True;
      end
      else if MatchesKey(KStart, ColonPos - 1, 'Buffers') then
        BuffersKB := ParsedVal
      else if MatchesKey(KStart, ColonPos - 1, 'Cached') then
        CachedKB := ParsedVal;
    end;

    if HasTotal and HasAvail then
      Break;
  end;

  if (not HasTotal) or (TotalKB <= 0) then
    Exit(False);

  TotalBytes := TotalKB * 1024;
  if HasAvail then
    AvailBytes := AvailKB * 1024
  else if HasFree then
    AvailBytes := (FreeKB + BuffersKB + CachedKB) * 1024
  else
    Exit(False);

  if AvailBytes < 0 then
    AvailBytes := 0
  else if AvailBytes > TotalBytes then
    AvailBytes := TotalBytes;

  AInfo.TotalBytes := TotalBytes;
  AInfo.AvailableBytes := AvailBytes;
  AInfo.ReserveBytes := ComputeSystemMemoryReserveBytes(TotalBytes);
  AInfo.Available := True;
  Result := True;
end;
{$ELSE}
{$IFDEF WINDOWS}
var
  MemStat: TMemoryStatusEx;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  Result := False;
  FillChar(MemStat, SizeOf(MemStat), 0);
  MemStat.dwLength := SizeOf(MemStat);
  if GlobalMemoryStatusEx(MemStat) and (MemStat.ullTotalPhys > 0) then
  begin
    AInfo.TotalBytes := Int64(MemStat.ullTotalPhys);
    AInfo.AvailableBytes := Int64(MemStat.ullAvailPhys);
    if AInfo.AvailableBytes < 0 then
      AInfo.AvailableBytes := 0
    else if AInfo.AvailableBytes > AInfo.TotalBytes then
      AInfo.AvailableBytes := AInfo.TotalBytes;
    AInfo.ReserveBytes := ComputeSystemMemoryReserveBytes(AInfo.TotalBytes);
    AInfo.Available := True;
    Result := True;
  end;
end;
{$ELSE}
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  Result := False;
end;
{$ENDIF}
{$ENDIF}

function FormatApproxBytes(const ABytes: Int64): string;
const
  ONE_KB = Int64(1024);
  ONE_MB = ONE_KB * 1024;
  ONE_GB = ONE_MB * 1024;
begin
  if ABytes < ONE_KB then
    Result := Format('%d B', [ABytes])
  else if ABytes < ONE_MB then
    Result := FormatFloat('#,##0.## KB', ABytes / ONE_KB)
  else if ABytes < ONE_GB then
    Result := FormatFloat('#,##0.## MB', ABytes / ONE_MB)
  else
    Result := FormatFloat('#,##0.## GB', ABytes / ONE_GB);
end;

function FormatByteSize(const ABytes: Int64): string;
begin
  Result := FormatApproxBytes(ABytes);
end;

function TruncateGridCellText(const AText: string; const AMaxChars: Integer): string;
var
  CutLen: Integer;
begin
  if (AMaxChars <= 0) or (Length(AText) <= AMaxChars) then
    Exit(AText);

  CutLen := AMaxChars;
  while (CutLen > 0) and (CutLen < Length(AText)) and ((Ord(AText[CutLen + 1]) and $C0) = $80) do
    Dec(CutLen);
  if CutLen <= 0 then
    CutLen := AMaxChars;

  Result := Copy(AText, 1, CutLen) +
    Format('... [truncado: %s total]', [FormatApproxBytes(Length(AText))]);
end;

function EstimateQueryRowBytes(const ARow: TQueryRow): Int64;
var
  I: Integer;
begin
  Result := 32 + Int64(Length(ARow)) * SizeOf(TQueryCell);
  for I := 0 to High(ARow) do
  begin
    if (not ARow[I].IsNull) and (Length(ARow[I].AsText) > 0) then
      Inc(Result, 24 + Int64(Length(ARow[I].AsText)));
  end;
end;

{ TQueryResult }

constructor TQueryResult.Create;
begin
  inherited Create;
  FSuccess := False;
  FHasResultSet := False;
  FRowCount := 0;
  FRowCapacity := 0;
  FEstimatedMemoryBytes := 0;
  FBaselineMemoryBytes := 0;
  FMemoryLimitBytes := DEFAULT_RESULT_MEMORY_LIMIT_BYTES;
  FMemoryLimitReached := False;
  FSystemMemoryLow := False;
  FHasCheckedOsMem := False;
  FLastOsMemCheckTick := 0;
  FLastOsMemCheckBytes := 0;
  FLimitMessage := '';
  FRowsAffected := 0;
  FExecutionTimeMs := 0;
  FErrorCode := 0;
  FCursor := nil;
  FPerformance := TQueryPerformanceStats.Create;
  FAllowDiskSpill := GThreadAllowDiskSpill;
  FSpilledToDisk := False;
  FSpillFilePath := '';
  FSpillStream := nil;
  FSpillCapacity := 0;
  FCachedSpillRowIdx := -1;
end;

destructor TQueryResult.Destroy;
begin
  CloseCursor;
  FreeAndNil(FSpillStream);
  if (FSpillFilePath <> '') and FileExists(FSpillFilePath) then
    SysUtils.DeleteFile(FSpillFilePath);
  FPerformance.Free;
  inherited Destroy;
end;

procedure TQueryResult.EnsureRowCapacity(const AMinCapacity: Integer);
var
  NewCap: Integer;
begin
  if AMinCapacity <= FRowCapacity then
    Exit;
  NewCap := FRowCapacity;
  if NewCap < 128 then
    NewCap := 128;
  while NewCap < AMinCapacity do
  begin
    if NewCap > (MaxInt div 2) then
    begin
      NewCap := AMinCapacity;
      Break;
    end;
    NewCap := NewCap * 2;
  end;
  SetLength(FRows, NewCap);
  FRowCapacity := NewCap;
end;

procedure TQueryResult.SetColumns(const AColumns: array of TQueryColumn);
var
  I: Integer;
begin
  SetLength(FColumns, Length(AColumns));
  for I := 0 to High(AColumns) do
    FColumns[I] := AColumns[I];
end;

procedure TQueryResult.EnsureSpillCapacity(const AMinCapacity: Integer);
var
  NewCap: Integer;
begin
  if AMinCapacity <= FSpillCapacity then
    Exit;
  NewCap := FSpillCapacity;
  if NewCap < 256 then
    NewCap := 256;
  while NewCap < AMinCapacity do
  begin
    if NewCap > (MaxInt div 2) then
    begin
      NewCap := AMinCapacity;
      Break;
    end;
    NewCap := NewCap * 2;
  end;
  SetLength(FSpillOffsets, NewCap);
  FSpillCapacity := NewCap;
end;

procedure TQueryResult.WriteSpillRow(const ARow: TQueryRow);
var
  ColCnt, I, Len: Int32;
  IsNullByte: Byte;
  S: string;
begin
  if FSpillStream = nil then
    Exit;
  FSpillStream.Position := FSpillStream.Size;
  ColCnt := Length(ARow);
  FSpillStream.WriteBuffer(ColCnt, SizeOf(ColCnt));
  for I := 0 to ColCnt - 1 do
  begin
    if ARow[I].IsNull then
    begin
      IsNullByte := 1;
      FSpillStream.WriteBuffer(IsNullByte, 1);
    end
    else
    begin
      IsNullByte := 0;
      FSpillStream.WriteBuffer(IsNullByte, 1);
      S := ARow[I].AsText;
      Len := Length(S);
      FSpillStream.WriteBuffer(Len, SizeOf(Len));
      if Len > 0 then
        FSpillStream.WriteBuffer(S[1], Len);
    end;
  end;
end;

function TQueryResult.ReadSpillRow(const AIndex: Integer): TQueryRow;
var
  ColCnt, I, Len: Int32;
  IsNullByte: Byte;
  S: string;
begin
  if (AIndex = FCachedSpillRowIdx) and (Length(FCachedSpillRow) > 0) then
    Exit(FCachedSpillRow);

  Result := nil;
  if (FSpillStream = nil) or (AIndex < 0) or (AIndex >= FRowCount) then
    Exit;

  FSpillStream.Position := FSpillOffsets[AIndex];
  FSpillStream.ReadBuffer(ColCnt, SizeOf(ColCnt));
  SetLength(Result, ColCnt);
  for I := 0 to ColCnt - 1 do
  begin
    FSpillStream.ReadBuffer(IsNullByte, 1);
    if IsNullByte <> 0 then
    begin
      Result[I].IsNull := True;
      Result[I].AsText := '';
    end
    else
    begin
      Result[I].IsNull := False;
      FSpillStream.ReadBuffer(Len, SizeOf(Len));
      if Len > 0 then
      begin
        SetLength(S, Len);
        FSpillStream.ReadBuffer(S[1], Len);
        Result[I].AsText := S;
      end
      else
        Result[I].AsText := '';
    end;
  end;
  FCachedSpillRowIdx := AIndex;
  FCachedSpillRow := Result;
end;

function TQueryResult.ActivateDiskSpill: Boolean;
var
  I: Integer;
begin
  if FSpilledToDisk then
    Exit(True);
  Result := False;
  try
    FSpillFilePath := IncludeTrailingPathDelimiter(GetTempDir(False)) +
      Format('multidb_spill_%d_%d.tmp', [GetTickCount64, PtrUInt(Self)]);
    FSpillStream := TFileStream.Create(FSpillFilePath, fmCreate or fmShareDenyNone);
    EnsureSpillCapacity(FRowCount);
    for I := 0 to FRowCount - 1 do
    begin
      FSpillOffsets[I] := FSpillStream.Size;
      WriteSpillRow(FRows[I]);
    end;
    SetLength(FRows, 0);
    FRowCapacity := 0;
    FEstimatedMemoryBytes := 0;
    FCachedSpillRowIdx := -1;
    SetLength(FCachedSpillRow, 0);
    FSpilledToDisk := True;
    TrimProcessMemoryUsage;
    Result := True;
  except
    FreeAndNil(FSpillStream);
    Result := False;
  end;
end;

procedure TQueryResult.AddRow(const ARow: TQueryRow);
begin
  if FSpilledToDisk then
  begin
    EnsureSpillCapacity(FRowCount + 1);
    FSpillOffsets[FRowCount] := FSpillStream.Size;
    WriteSpillRow(ARow);
    Inc(FRowCount);
    Exit;
  end;

  EnsureRowCapacity(FRowCount + 1);
  FRows[FRowCount] := ARow;
  Inc(FRowCount);
  Inc(FEstimatedMemoryBytes, EstimateQueryRowBytes(ARow));
end;

procedure TQueryResult.UpdateCell(
  const ARowIndex, AColIndex: Integer;
  const AIsNull: Boolean;
  const AText: string
);
begin
  if (ARowIndex < 0) or (ARowIndex >= FRowCount) or
     (AColIndex < 0) or (AColIndex >= Length(FColumns)) then
    Exit;
  if Length(FRows[ARowIndex]) <= AColIndex then
    SetLength(FRows[ARowIndex], Length(FColumns));
  FRows[ARowIndex][AColIndex].IsNull := AIsNull;
  if AIsNull then
    FRows[ARowIndex][AColIndex].AsText := ''
  else
    FRows[ARowIndex][AColIndex].AsText := AText;
end;

function TQueryResult.InsertEmptyRow: Integer;
var
  NewRow: TQueryRow;
  I: Integer;
begin
  SetLength(NewRow, Length(FColumns));
  for I := 0 to High(NewRow) do
  begin
    NewRow[I].IsNull := True;
    NewRow[I].AsText := '';
  end;
  AddRow(NewRow);
  Result := FRowCount - 1;
end;

procedure TQueryResult.DeleteRow(const ARowIndex: Integer);
var
  I: Integer;
begin
  if (ARowIndex < 0) or (ARowIndex >= FRowCount) then
    Exit;
  for I := ARowIndex to FRowCount - 2 do
    FRows[I] := FRows[I + 1];
  SetLength(FRows[FRowCount - 1], 0);
  Dec(FRowCount);
end;

function TQueryResult.ColumnCount: Integer;
begin
  Result := Length(FColumns);
end;

function TQueryResult.RowCount: Integer;
begin
  Result := FRowCount;
end;

function TQueryResult.GetColumn(const AIndex: Integer): TQueryColumn;
begin
  Result := FColumns[AIndex];
end;

function TQueryResult.GetRow(const AIndex: Integer): TQueryRow;
begin
  if FSpilledToDisk then
    Result := ReadSpillRow(AIndex)
  else
    Result := FRows[AIndex];
end;

function TQueryResult.TotalTrackedMemoryBytes: Int64;
begin
  Result := FBaselineMemoryBytes + FEstimatedMemoryBytes;
end;

function TQueryResult.IsMemoryLimitReached: Boolean;
var
  NowTick: QWord;
  SysMem: TSystemMemoryInfo;
begin
  if FMemoryLimitReached then
    Exit(True);

  if FSpilledToDisk then
    Exit(False);

  if (FMemoryLimitBytes > 0) and (TotalTrackedMemoryBytes >= FMemoryLimitBytes) then
  begin
    if FAllowDiskSpill and ActivateDiskSpill then
      Exit(False);
    Exit(True);
  end;

  NowTick := GetTickCount64;
  if (not FHasCheckedOsMem) or
     (FEstimatedMemoryBytes - FLastOsMemCheckBytes >= OS_MEMORY_CHECK_DELTA_BYTES) or
     (NowTick - FLastOsMemCheckTick >= OS_MEMORY_CHECK_INTERVAL_MS) then
  begin
    FHasCheckedOsMem := True;
    FLastOsMemCheckTick := NowTick;
    FLastOsMemCheckBytes := FEstimatedMemoryBytes;
    if GetSystemMemoryInfo(SysMem) and SysMem.Available and
       (SysMem.AvailableBytes <= SysMem.ReserveBytes) then
    begin
      if FAllowDiskSpill and ActivateDiskSpill then
        Exit(False);
      MarkSystemMemoryLow(SysMem);
      Exit(True);
    end;
  end;

  Result := False;
end;

procedure TQueryResult.MarkMemoryLimitReached(const AReason: string);
begin
  FMemoryLimitReached := True;
  if Trim(AReason) <> '' then
    FLimitMessage := Trim(AReason)
  else if Trim(FLimitMessage) = '' then
    FLimitMessage := Format(
      'Limite de memória RAM atingido (%s usados / limite %s; %d linha(s) carregadas). Use WHERE/paginação ou ajuste o limite na barra.',
      [FormatApproxBytes(TotalTrackedMemoryBytes), FormatApproxBytes(FMemoryLimitBytes), FRowCount]
    );
end;

procedure TQueryResult.MarkSystemMemoryLow(const AInfo: TSystemMemoryInfo);
begin
  FSystemMemoryLow := True;
  MarkMemoryLimitReached(Format(
    'Proteção de memória RAM do sistema ativada para evitar travamento do SO (RAM livre: %s de %s; reserva mínima: %s; consulta: %s). O carregamento foi interrompido com segurança e os registros já carregados foram mantidos.',
    [
      FormatApproxBytes(AInfo.AvailableBytes),
      FormatApproxBytes(AInfo.TotalBytes),
      FormatApproxBytes(AInfo.ReserveBytes),
      FormatApproxBytes(TotalTrackedMemoryBytes)
    ]
  ));
end;

function TQueryResult.HasMoreRows: Boolean;
begin
  Result := (FCursor <> nil) and FCursor.HasMore;
end;

function TQueryResult.FetchMore(const ABatchSize: Integer): Integer;
begin
  if not HasMoreRows then
  begin
    Result := 0;
    Exit;
  end;
  if IsMemoryLimitReached then
  begin
    MarkMemoryLimitReached;
    if FCursor <> nil then
      FCursor.RefreshPerformance(Self);
    CloseCursor;
    Result := 0;
    Exit;
  end;
  Result := FCursor.FetchNext(ABatchSize, Self);
  if IsMemoryLimitReached then
  begin
    MarkMemoryLimitReached;
    if FCursor <> nil then
      FCursor.RefreshPerformance(Self);
    CloseCursor;
  end;
  FRowsAffected := FRowCount;
  if FCursor <> nil then
    FCursor.RefreshPerformance(Self);
end;

function TQueryResult.FetchAll: Integer;
var
  StepCount: Integer;
begin
  Result := 0;
  while HasMoreRows and (not IsMemoryLimitReached) do
  begin
    StepCount := FCursor.FetchNext(1000, Self);
    if StepCount <= 0 then
      Break;
    Inc(Result, StepCount);
  end;
  if IsMemoryLimitReached then
  begin
    MarkMemoryLimitReached;
    if FCursor <> nil then
      FCursor.RefreshPerformance(Self);
    CloseCursor;
  end;
  FRowsAffected := FRowCount;
  if FCursor <> nil then
    FCursor.RefreshPerformance(Self);
end;

function TQueryResult.AppendRowsFrom(const ASource: TQueryResult): Integer;
var
  OldCount, SrcCount, I: Integer;
begin
  Result := 0;
  if ASource = nil then
    Exit;
  SrcCount := ASource.RowCount;
  if SrcCount > 0 then
  begin
    OldCount := FRowCount;
    EnsureRowCapacity(OldCount + SrcCount);
    for I := 0 to SrcCount - 1 do
      FRows[OldCount + I] := ASource.FRows[I];
    Inc(FRowCount, SrcCount);
    Inc(FEstimatedMemoryBytes, ASource.FEstimatedMemoryBytes);
    FRowsAffected := FRowCount;
    Result := SrcCount;
  end;
  if ASource.SystemMemoryLow then
    FSystemMemoryLow := True;
  if ASource.MemoryLimitReached then
    MarkMemoryLimitReached(ASource.LimitMessage)
  else if IsMemoryLimitReached then
    MarkMemoryLimitReached;
end;

procedure TQueryResult.SortByColumn(const AColIndex: Integer; const AAscending: Boolean);
var
  InvFormat: TFormatSettings;

  function CompareCells(const A, B: TQueryCell): Integer;
  var
    NumA, NumB: Double;
    IsNumA, IsNumB: Boolean;
  begin
    if A.IsNull and B.IsNull then
    begin
      Result := 0;
      Exit;
    end;
    if A.IsNull then
    begin
      Result := 1; // NULLs por último
      Exit;
    end;
    if B.IsNull then
    begin
      Result := -1;
      Exit;
    end;

    IsNumA := TryStrToFloat(A.AsText, NumA, InvFormat) or TryStrToFloat(A.AsText, NumA);
    IsNumB := TryStrToFloat(B.AsText, NumB, InvFormat) or TryStrToFloat(B.AsText, NumB);
    if IsNumA and IsNumB then
    begin
      if NumA < NumB then
        Result := -1
      else if NumA > NumB then
        Result := 1
      else
        Result := 0;
    end
    else
      Result := AnsiCompareText(A.AsText, B.AsText);

    if not AAscending then
      Result := -Result;
  end;

  procedure QuickSortRows(L, R: Integer);
  var
    I, J: Integer;
    Pivot, Temp: TQueryRow;
  begin
    I := L;
    J := R;
    Pivot := FRows[(L + R) div 2];
    repeat
      while CompareCells(FRows[I][AColIndex], Pivot[AColIndex]) < 0 do
        Inc(I);
      while CompareCells(FRows[J][AColIndex], Pivot[AColIndex]) > 0 do
        Dec(J);
      if I <= J then
      begin
        if I <> J then
        begin
          Temp := FRows[I];
          FRows[I] := FRows[J];
          FRows[J] := Temp;
        end;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then
      QuickSortRows(L, J);
    if I < R then
      QuickSortRows(I, R);
  end;

begin
  if (AColIndex < 0) or (AColIndex >= ColumnCount) or (RowCount <= 1) then
    Exit;
  InvFormat := DefaultFormatSettings;
  InvFormat.DecimalSeparator := '.';
  QuickSortRows(0, RowCount - 1);
end;

procedure TQueryResult.CloseCursor;
begin
  if FCursor <> nil then
  begin
    try
      FCursor.CloseCursor;
    except
    end;
    FCursor := nil;
  end;
end;

function StripLeadingSqlComments(const ASQL: string): string;
var
  I, Len: Integer;
begin
  Len := Length(ASQL);
  I := 1;
  while I <= Len do
  begin
    while (I <= Len) and (ASQL[I] <= ' ') do
      Inc(I);
    if (I + 1 <= Len) and (ASQL[I] = '-') and (ASQL[I + 1] = '-') then
    begin
      Inc(I, 2);
      while (I <= Len) and (ASQL[I] <> #10) do
        Inc(I);
    end
    else if (I + 1 <= Len) and (ASQL[I] = '/') and (ASQL[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I + 1 <= Len) and not ((ASQL[I] = '*') and (ASQL[I + 1] = '/')) do
        Inc(I);
      if I + 1 <= Len then
        Inc(I, 2)
      else
        I := Len + 1;
    end
    else
      Break;
  end;
  if I <= Len then
    Result := Copy(ASQL, I, Len - I + 1)
  else
    Result := '';
end;

function IsSelectLikeSQLText(const ASQL: string; const AIncludeExplainShow: Boolean): Boolean;
var
  Cleaned, Upper: string;

  function StartsWithKeyword(const AKeyword: string): Boolean;
  var
    KLen: Integer;
  begin
    KLen := Length(AKeyword);
    if Copy(Upper, 1, KLen) <> AKeyword then
      Exit(False);
    if Length(Upper) = KLen then
      Exit(True);
    Result := Upper[KLen + 1] in [#0..' ', '(', '*', ';'];
  end;

begin
  Cleaned := StripLeadingSqlComments(ASQL);
  Upper := UpperCase(Cleaned);
  Result := StartsWithKeyword('SELECT') or StartsWithKeyword('WITH');
  if (not Result) and AIncludeExplainShow then
    Result := StartsWithKeyword('SHOW') or StartsWithKeyword('EXPLAIN');
end;

end.
