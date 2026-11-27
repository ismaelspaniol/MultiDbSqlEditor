unit Application.CheckUpdateUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  DateUtils,
  fpjson,
  jsonparser,
  Domain.Interfaces,
  Domain.AppVersion,
  Domain.AppLogger;

type
  TUpdateSettings = record
    AutoCheckOnStartup: Boolean;
    IgnoredVersion: string;
    LastCheckUtc: string;
  end;

  TUpdateCheckCompleteEvent = procedure(
    const AWorker: TObject;
    const AResult: TUpdateCheckResult;
    const AManualCheck: Boolean
  ) of object;

  { Caso de uso para verificar atualizações e persistir preferências }
  TCheckUpdateUseCase = class
  private
    FService: IUpdateCheckService;
    FSettingsPath: string;
    function ResolveSettingsPath: string;
  public
    constructor Create(const AService: IUpdateCheckService);
    function LoadSettings: TUpdateSettings;
    procedure SaveSettings(const ASettings: TUpdateSettings);
    function ShouldRunAutoCheck: Boolean;
    procedure MarkCheckedNow(const AIgnoredVersion: string = '');
    function CheckNow: TUpdateCheckResult;
  end;

  { Worker em segundo plano para checagem de atualização sem travar a UI }
  TUpdateCheckWorkerThread = class(TThread)
  private
    FLock: TCriticalSection;
    FService: IUpdateCheckService;
    FManualCheck: Boolean;
    FDetached: Boolean;
    FResult: TUpdateCheckResult;
    FOnComplete: TUpdateCheckCompleteEvent;
    procedure DeliverOnMainThread;
  protected
    procedure Execute; override;
  public
    constructor Create(
      const AService: IUpdateCheckService;
      const AManualCheck: Boolean;
      const AOnComplete: TUpdateCheckCompleteEvent
    );
    destructor Destroy; override;
    procedure Detach;
  end;

implementation

{ TCheckUpdateUseCase }

constructor TCheckUpdateUseCase.Create(const AService: IUpdateCheckService);
begin
  inherited Create;
  FService := AService;
  FSettingsPath := '';
end;

function TCheckUpdateUseCase.ResolveSettingsPath: string;
var
  ExePath, ConfigDir: string;
begin
  if FSettingsPath <> '' then
    Exit(FSettingsPath);

  ExePath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'update_settings.json';
  if FileExists(ExePath) then
  begin
    FSettingsPath := ExePath;
    Exit(FSettingsPath);
  end;

  ConfigDir := GetAppConfigDir(False);
  if ForceDirectories(ExtractFileDir(ExePath)) then
    FSettingsPath := ExePath
  else
  begin
    ForceDirectories(ConfigDir);
    FSettingsPath := IncludeTrailingPathDelimiter(ConfigDir) + 'update_settings.json';
  end;
  Result := FSettingsPath;
end;

function TCheckUpdateUseCase.LoadSettings: TUpdateSettings;
var
  SL: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
  Path: string;
begin
  Result.AutoCheckOnStartup := True;
  Result.IgnoredVersion := '';
  Result.LastCheckUtc := '';

  Path := ResolveSettingsPath;
  if not FileExists(Path) then
    Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(Path, TEncoding.UTF8);
      Data := GetJSON(SL.Text);
      try
        if Data is TJSONObject then
        begin
          Obj := TJSONObject(Data);
          Result.AutoCheckOnStartup := Obj.Get('autoCheckOnStartup', True);
          Result.IgnoredVersion := Obj.Get('ignoredVersion', '');
          Result.LastCheckUtc := Obj.Get('lastCheckUtc', '');
        end;
      finally
        Data.Free;
      end;
    except
      on E: Exception do
        LogException('CheckUpdateUseCase.LoadSettings', E);
    end;
  finally
    SL.Free;
  end;
end;

procedure TCheckUpdateUseCase.SaveSettings(const ASettings: TUpdateSettings);
var
  Obj: TJSONObject;
  SL: TStringList;
  Path, FallbackPath: string;
begin
  Obj := TJSONObject.Create;
  SL := TStringList.Create;
  try
    Obj.Add('autoCheckOnStartup', ASettings.AutoCheckOnStartup);
    Obj.Add('ignoredVersion', ASettings.IgnoredVersion);
    Obj.Add('lastCheckUtc', ASettings.LastCheckUtc);
    SL.Text := Obj.FormatJSON;
    Path := ResolveSettingsPath;
    try
      SL.SaveToFile(Path, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        FallbackPath := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'update_settings.json';
        if not SameText(Path, FallbackPath) then
        begin
          try
            ForceDirectories(ExtractFileDir(FallbackPath));
            SL.SaveToFile(FallbackPath, TEncoding.UTF8);
            FSettingsPath := FallbackPath;
          except
            on E2: Exception do
              LogException('CheckUpdateUseCase.SaveSettings.Fallback', E2);
          end;
        end
        else
          LogException('CheckUpdateUseCase.SaveSettings', E);
      end;
    end;
  finally
    SL.Free;
    Obj.Free;
  end;
end;

function TCheckUpdateUseCase.ShouldRunAutoCheck: Boolean;
var
  Settings: TUpdateSettings;
  LastDt: TDateTime;
begin
  Settings := LoadSettings;
  if not Settings.AutoCheckOnStartup then
    Exit(False);
  if Trim(Settings.LastCheckUtc) = '' then
    Exit(True);
  try
    LastDt := ISO8601ToDate(Settings.LastCheckUtc, True);
    Result := HoursBetween(Now, LastDt) >= 24;
  except
    Result := True;
  end;
end;

procedure TCheckUpdateUseCase.MarkCheckedNow(const AIgnoredVersion: string);
var
  Settings: TUpdateSettings;
begin
  Settings := LoadSettings;
  Settings.LastCheckUtc := DateToISO8601(Now, True);
  if AIgnoredVersion <> '' then
    Settings.IgnoredVersion := AIgnoredVersion;
  SaveSettings(Settings);
end;

function TCheckUpdateUseCase.CheckNow: TUpdateCheckResult;
var
  JsonText, ErrMsg: string;
begin
  Result := Default(TUpdateCheckResult);
  Result.CurrentVersion := APP_VERSION;
  Result.ReleasePageUrl := GITHUB_RELEASES_PAGE_URL;

  if FService = nil then
  begin
    Result.ErrorMessage := 'Serviço de verificação de atualizações não configurado.';
    Exit;
  end;

  if not FService.FetchLatestReleaseJson(JsonText, ErrMsg) then
  begin
    Result.ErrorMessage := ErrMsg;
    Exit;
  end;

  Result := ParseGitHubReleaseJson(JsonText, APP_VERSION, CurrentPlatformAssetToken);
end;

{ TUpdateCheckWorkerThread }

constructor TUpdateCheckWorkerThread.Create(
  const AService: IUpdateCheckService;
  const AManualCheck: Boolean;
  const AOnComplete: TUpdateCheckCompleteEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FService := AService;
  FManualCheck := AManualCheck;
  FDetached := False;
  FOnComplete := AOnComplete;
end;

destructor TUpdateCheckWorkerThread.Destroy;
begin
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure TUpdateCheckWorkerThread.Detach;
begin
  FLock.Acquire;
  try
    FDetached := True;
    FOnComplete := nil;
  finally
    FLock.Release;
  end;
end;

procedure TUpdateCheckWorkerThread.Execute;
var
  UC: TCheckUpdateUseCase;
begin
  UC := TCheckUpdateUseCase.Create(FService);
  try
    FResult := UC.CheckNow;
  finally
    UC.Free;
  end;
  Queue(nil, @DeliverOnMainThread);
end;

procedure TUpdateCheckWorkerThread.DeliverOnMainThread;
var
  WasDetached, ManualCopy: Boolean;
  ResCopy: TUpdateCheckResult;
  Cb: TUpdateCheckCompleteEvent;
begin
  WaitFor;
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Cb := FOnComplete;
    FOnComplete := nil;
    ManualCopy := FManualCheck;
    ResCopy := FResult;
  finally
    FLock.Release;
  end;

  try
    if (not WasDetached) and Assigned(Cb) then
      Cb(Self, ResCopy, ManualCopy);
  finally
    Free;
  end;
end;

end.
