unit Domain.AppLogger;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs;

type
  TAppLogLevel = (
    allDebug,
    allInfo,
    allWarn,
    allError
  );

  { Logger diagnóstico cross-platform (Windows/Linux), thread-safe, com rotação e ring-buffer }
  TAppLogger = class
  private
    FLock: TCriticalSection;
    FCustomLogFilePath: string;
    FResolvedLogFilePath: string;
    FMaxFileSizeBytes: Int64;
    FRingBuffer: TStringList;
    FMaxRingLines: Integer;
    function ResolveLogFilePath: string;
    function TryWriteLineToFile(const AFilePath, ALine: string): Boolean;
    procedure RotateIfNeeded(const AFilePath: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Log(const ALevel: TAppLogLevel; const AContext, AMessage: string);
    procedure LogException(const AContext: string; const E: Exception);
    function GetRecentLines(const ATarget: TStrings): Integer;
    function GetRecentText: string;
    function GetLogFilePath: string;
    function GetLogDirectory: string;
    procedure SetLogFilePathForTest(const AFilePath: string);
    procedure ClearForTest;
  end;

function AppLogger: TAppLogger;
function LogLevelToStr(const ALevel: TAppLogLevel): string;
procedure LogDebug(const AContext, AMessage: string);
procedure LogInfo(const AContext, AMessage: string);
procedure LogWarn(const AContext, AMessage: string);
procedure LogError(const AContext, AMessage: string);
procedure LogException(const AContext: string; const E: Exception);

implementation

var
  GAppLogger: TAppLogger = nil;

function AppLogger: TAppLogger;
begin
  if GAppLogger = nil then
    GAppLogger := TAppLogger.Create;
  Result := GAppLogger;
end;

function LogLevelToStr(const ALevel: TAppLogLevel): string;
begin
  case ALevel of
    allDebug: Result := 'DEBUG';
    allInfo: Result := 'INFO';
    allWarn: Result := 'WARN';
    allError: Result := 'ERROR';
  else
    Result := 'INFO';
  end;
end;

procedure LogDebug(const AContext, AMessage: string);
begin
  AppLogger.Log(allDebug, AContext, AMessage);
end;

procedure LogInfo(const AContext, AMessage: string);
begin
  AppLogger.Log(allInfo, AContext, AMessage);
end;

procedure LogWarn(const AContext, AMessage: string);
begin
  AppLogger.Log(allWarn, AContext, AMessage);
end;

procedure LogError(const AContext, AMessage: string);
begin
  AppLogger.Log(allError, AContext, AMessage);
end;

procedure LogException(const AContext: string; const E: Exception);
begin
  AppLogger.LogException(AContext, E);
end;

{ TAppLogger }

constructor TAppLogger.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRingBuffer := TStringList.Create;
  FMaxFileSizeBytes := 2 * 1024 * 1024; // 2 MB
  FMaxRingLines := 500;
  FCustomLogFilePath := '';
  FResolvedLogFilePath := '';
end;

destructor TAppLogger.Destroy;
begin
  FreeAndNil(FRingBuffer);
  FreeAndNil(FLock);
  inherited Destroy;
end;

function TAppLogger.ResolveLogFilePath: string;
var
  ExeLogsDir, ConfigDir: string;
begin
  if FCustomLogFilePath <> '' then
    Exit(FCustomLogFilePath);

  if FResolvedLogFilePath <> '' then
    Exit(FResolvedLogFilePath);

  ExeLogsDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'logs';
  if ForceDirectories(ExeLogsDir) then
  begin
    FResolvedLogFilePath := IncludeTrailingPathDelimiter(ExeLogsDir) + 'multidb.log';
    Exit(FResolvedLogFilePath);
  end;

  ConfigDir := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'logs';
  ForceDirectories(ConfigDir);
  FResolvedLogFilePath := IncludeTrailingPathDelimiter(ConfigDir) + 'multidb.log';
  Result := FResolvedLogFilePath;
end;

procedure TAppLogger.RotateIfNeeded(const AFilePath: string);
var
  SR: TSearchRec;
  BackupPath: string;
begin
  if not FileExists(AFilePath) then
    Exit;
  if FindFirst(AFilePath, faAnyFile, SR) = 0 then
  begin
    try
      if SR.Size >= FMaxFileSizeBytes then
      begin
        BackupPath := AFilePath + '.1';
        if FileExists(BackupPath) then
          DeleteFile(BackupPath);
        RenameFile(AFilePath, BackupPath);
      end;
    finally
      FindClose(SR);
    end;
  end;
end;

function TAppLogger.TryWriteLineToFile(const AFilePath, ALine: string): Boolean;
var
  Dir: string;
  FS: TFileStream;
  Bytes: RawByteString;
  Mode: Word;
begin
  Result := False;
  if AFilePath = '' then
    Exit;

  Dir := ExtractFileDir(AFilePath);
  if (Dir <> '') and (not DirectoryExists(Dir)) then
    if not ForceDirectories(Dir) then
      Exit;

  RotateIfNeeded(AFilePath);

  if FileExists(AFilePath) then
    Mode := fmOpenReadWrite or fmShareDenyNone
  else
    Mode := fmCreate or fmShareDenyNone;

  try
    FS := TFileStream.Create(AFilePath, Mode);
    try
      FS.Seek(0, soEnd);
      Bytes := UTF8Encode(ALine + LineEnding);
      if Length(Bytes) > 0 then
        FS.WriteBuffer(Bytes[1], Length(Bytes));
      Result := True;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TAppLogger.Log(const ALevel: TAppLogLevel; const AContext, AMessage: string);
var
  Timestamp, CleanMsg, FormattedLine, TargetPath, FallbackPath: string;
begin
  Timestamp := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now);
  CleanMsg := StringReplace(Trim(AMessage), #13#10, ' ', [rfReplaceAll]);
  CleanMsg := StringReplace(CleanMsg, #10, ' ', [rfReplaceAll]);
  FormattedLine := Format('%s [%s] [%s] %s', [
    Timestamp,
    LogLevelToStr(ALevel),
    Trim(AContext),
    CleanMsg
  ]);

  FLock.Acquire;
  try
    FRingBuffer.Add(FormattedLine);
    while FRingBuffer.Count > FMaxRingLines do
      FRingBuffer.Delete(0);

    TargetPath := ResolveLogFilePath;
    if not TryWriteLineToFile(TargetPath, FormattedLine) then
    begin
      if FCustomLogFilePath = '' then
      begin
        FallbackPath := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'logs' + PathDelim + 'multidb.log';
        if not SameText(TargetPath, FallbackPath) then
        begin
          if TryWriteLineToFile(FallbackPath, FormattedLine) then
            FResolvedLogFilePath := FallbackPath;
        end;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TAppLogger.LogException(const AContext: string; const E: Exception);
begin
  if E <> nil then
    Log(allError, AContext, E.ClassName + ': ' + E.Message)
  else
    Log(allError, AContext, 'Exceção desconhecida (nil)');
end;

function TAppLogger.GetRecentLines(const ATarget: TStrings): Integer;
var
  I: Integer;
begin
  Result := 0;
  if ATarget = nil then
    Exit;
  FLock.Acquire;
  try
    ATarget.BeginUpdate;
    try
      ATarget.Clear;
      for I := 0 to FRingBuffer.Count - 1 do
        ATarget.Add(FRingBuffer[I]);
      Result := FRingBuffer.Count;
    finally
      ATarget.EndUpdate;
    end;
  finally
    FLock.Release;
  end;
end;

function TAppLogger.GetRecentText: string;
begin
  FLock.Acquire;
  try
    Result := FRingBuffer.Text;
  finally
    FLock.Release;
  end;
end;

function TAppLogger.GetLogFilePath: string;
begin
  FLock.Acquire;
  try
    Result := ResolveLogFilePath;
  finally
    FLock.Release;
  end;
end;

function TAppLogger.GetLogDirectory: string;
begin
  Result := ExtractFileDir(GetLogFilePath);
end;

procedure TAppLogger.SetLogFilePathForTest(const AFilePath: string);
begin
  FLock.Acquire;
  try
    FCustomLogFilePath := AFilePath;
    FResolvedLogFilePath := '';
  finally
    FLock.Release;
  end;
end;

procedure TAppLogger.ClearForTest;
begin
  FLock.Acquire;
  try
    FRingBuffer.Clear;
  finally
    FLock.Release;
  end;
end;

finalization
  FreeAndNil(GAppLogger);

end.
