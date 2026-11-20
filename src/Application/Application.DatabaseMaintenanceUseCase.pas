unit Application.DatabaseMaintenanceUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  Process,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.MaintenanceTypes,
  Infrastructure.FirebirdServicesRunner;

type
  TMaintenanceLogEvent = procedure(const ALine: string) of object;
  TMaintenanceCompleteEvent = procedure(
    const AWorker: TObject;
    const ASuccess: Boolean;
    const AMessage: string
  ) of object;

  { Thread em segundo plano para Backup, Restore e Reparo com streaming de log }
  TMaintenanceWorkerThread = class(TThread)
  private
    FOpMode: Integer; // 0 = backup, 1 = restore, 2 = repair, 3 = custom CLI
    FProfile: TConnectionProfile;
    FBackupReq: TBackupRequest;
    FRestoreReq: TRestoreRequest;
    FRepairReq: TRepairRequest;
    FCustomExe: string;
    FCustomParams: TStringList;
    FCustomEnv: TStringList;
    FLock: TCriticalSection;
    FDetached: Boolean;
    FCancelRequested: Boolean;
    FRunningProc: TProcess;
    FPendingLog: TStringList;
    FSuccess: Boolean;
    FMessage: string;
    FOnLog: TMaintenanceLogEvent;
    FOnComplete: TMaintenanceCompleteEvent;
    procedure AppendLogLine(const ALine: string);
    function CheckCancelled: Boolean;
    procedure DeliverLogOnMainThread;
    procedure FinishOnMainThread;
    function RunCliProcess(
      const AExe: string;
      const AParams, AEnv: TStrings;
      const ADisplayCmd: string;
      out AErrMsg: string
    ): Boolean;
  protected
    procedure Execute; override;
  public
    constructor CreateBackup(
      const AReq: TBackupRequest;
      const AOnLog: TMaintenanceLogEvent;
      const AOnComplete: TMaintenanceCompleteEvent
    );
    constructor CreateRestore(
      const AReq: TRestoreRequest;
      const AOnLog: TMaintenanceLogEvent;
      const AOnComplete: TMaintenanceCompleteEvent
    );
    constructor CreateRepair(
      const AReq: TRepairRequest;
      const AOnLog: TMaintenanceLogEvent;
      const AOnComplete: TMaintenanceCompleteEvent
    );
    constructor CreateCustomCli(
      const AExe: string;
      const AParams, AEnv: TStrings;
      const AOnLog: TMaintenanceLogEvent;
      const AOnComplete: TMaintenanceCompleteEvent
    );
    destructor Destroy; override;
    procedure RequestCancel;
    procedure Detach;
  end;

function FindMaintenanceToolPath(
  const AToolName: string;
  const AProfile: TConnectionProfile = nil
): string;

function FormatFirebirdTargetString(
  const AProfile: TConnectionProfile;
  const AOverrideDatabase: string = ''
): string;

procedure BuildBackupCliCommand(
  const AReq: TBackupRequest;
  out AExe: string;
  const AParams, AEnv: TStrings;
  out ADisplayCmd: string
);

procedure BuildRestoreCliCommand(
  const AReq: TRestoreRequest;
  out AExe: string;
  const AParams, AEnv: TStrings;
  out ADisplayCmd: string
);

procedure BuildRepairCliCommand(
  const AReq: TRepairRequest;
  out AExe: string;
  const AParams, AEnv: TStrings;
  out ADisplayCmd: string
);

function BuildServicesPreviewText(
  const AKind: TMaintenanceTabKind;
  const AProfile: TConnectionProfile;
  const ADetail: string
): string;

implementation

function QuoteShellArgForDisplay(const S: string): string;
begin
  if (S = '') or (Pos(' ', S) > 0) or (Pos(#9, S) > 0) then
    Result := '"' + S + '"'
  else
    Result := S;
end;

function FormatMaskedCommandLine(
  const AExe: string;
  const AParams, AEnv: TStrings;
  const AMaskSecretNextArg: array of string
): string;
var
  I, J: Integer;
  Val, KeyName: string;
  MaskNext: Boolean;
begin
  Result := '';
  if AEnv <> nil then
  begin
    for I := 0 to AEnv.Count - 1 do
    begin
      KeyName := AEnv.Names[I];
      if SameText(KeyName, 'PGPASSWORD') then
        Result := Result + 'PGPASSWORD=****** '
      else
        Result := Result + AEnv[I] + ' ';
    end;
  end;

  Result := Result + QuoteShellArgForDisplay(AExe);
  MaskNext := False;
  for I := 0 to AParams.Count - 1 do
  begin
    if MaskNext then
    begin
      Val := '******';
      MaskNext := False;
    end
    else
    begin
      Val := AParams[I];
      for J := Low(AMaskSecretNextArg) to High(AMaskSecretNextArg) do
      begin
        if SameText(Val, AMaskSecretNextArg[J]) then
        begin
          MaskNext := True;
          Break;
        end;
      end;
    end;
    Result := Result + ' ' + QuoteShellArgForDisplay(Val);
  end;
end;

function FindMaintenanceToolPath(
  const AToolName: string;
  const AProfile: TConnectionProfile
): string;
var
  CleanName, ExeDir, VerFolder, PathEnv, DirItem, Candidate: string;
  Dirs, PathParts: TStringList;
  I: Integer;
  {$IFDEF WINDOWS}
  const ToolExt = '.exe';
  {$ELSE}
  const ToolExt = '';
  {$ENDIF}
begin
  Result := '';
  CleanName := Trim(AToolName);
  if CleanName = '' then
    Exit;

  {$IFDEF WINDOWS}
  if ExtractFileExt(CleanName) = '' then
    CleanName := CleanName + ToolExt;
  {$ENDIF}

  Dirs := TStringList.Create;
  try
    ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    if ExeDir <> '' then
      Dirs.Add(ExeDir);

    if (AProfile <> nil) and (AProfile.DatabaseType = dtFirebird) then
    begin
      if AProfile.FirebirdVersion <> fvAuto then
      begin
        VerFolder := FirebirdVersionFolder(AProfile.FirebirdVersion);
        if VerFolder <> '' then
        begin
          {$IFDEF WINDOWS}
          {$IFDEF CPU64}
          Dirs.Add(ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + VerFolder + PathDelim + 'win64');
          {$ELSE}
          Dirs.Add(ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + VerFolder + PathDelim + 'win32');
          {$ENDIF}
          {$ENDIF}
          Dirs.Add(ExeDir + 'clients' + PathDelim + 'firebird' + PathDelim + VerFolder);
        end;
      end;
      if Trim(AProfile.ClientLibraryPath) <> '' then
        Dirs.Add(ExtractFileDir(AProfile.ClientLibraryPath));
    end
    else if (AProfile <> nil) and (AProfile.DatabaseType = dtPostgreSQL) then
    begin
      {$IFDEF WINDOWS}
      {$IFDEF CPU64}
      Dirs.Add(ExeDir + 'clients' + PathDelim + 'postgres' + PathDelim + 'win64');
      {$ELSE}
      Dirs.Add(ExeDir + 'clients' + PathDelim + 'postgres' + PathDelim + 'win32');
      {$ENDIF}
      {$ENDIF}
      Dirs.Add(ExeDir + 'clients' + PathDelim + 'postgres');
      if Trim(AProfile.ClientLibraryPath) <> '' then
        Dirs.Add(ExtractFileDir(AProfile.ClientLibraryPath));
    end;

    PathEnv := GetEnvironmentVariable('PATH');
    if PathEnv <> '' then
    begin
      PathParts := TStringList.Create;
      try
        PathParts.StrictDelimiter := True;
        {$IFDEF WINDOWS}
        PathParts.Delimiter := ';';
        {$ELSE}
        PathParts.Delimiter := ':';
        {$ENDIF}
        PathParts.DelimitedText := PathEnv;
        for I := 0 to PathParts.Count - 1 do
          Dirs.Add(PathParts[I]);
      finally
        PathParts.Free;
      end;
    end;

    {$IFDEF UNIX}
    Dirs.Add('/usr/bin');
    Dirs.Add('/usr/local/bin');
    Dirs.Add('/opt/firebird/bin');
    {$ENDIF}

    for I := 0 to Dirs.Count - 1 do
    begin
      DirItem := Trim(Dirs[I]);
      if DirItem = '' then
        Continue;
      Candidate := IncludeTrailingPathDelimiter(DirItem) + CleanName;
      if FileExists(Candidate) then
        Exit(Candidate);
    end;
  finally
    Dirs.Free;
  end;
end;

function FormatFirebirdTargetString(
  const AProfile: TConnectionProfile;
  const AOverrideDatabase: string
): string;
var
  DbPath, H: string;
begin
  if AProfile = nil then
    Exit(Trim(AOverrideDatabase));

  DbPath := Trim(AOverrideDatabase);
  if DbPath = '' then
    DbPath := Trim(AProfile.Database);

  H := Trim(AProfile.Host);
  if H = '' then
    Result := DbPath
  else if (AProfile.Port > 0) and (AProfile.Port <> 3050) then
    Result := Format('%s/%d:%s', [H, AProfile.Port, DbPath])
  else
    Result := H + ':' + DbPath;
end;

procedure BuildBackupCliCommand(
  const AReq: TBackupRequest;
  out AExe: string;
  const AParams, AEnv: TStrings;
  out ADisplayCmd: string
);
var
  DefaultTool, FormatFlag: string;
  PortNum: Word;
begin
  AParams.Clear;
  AEnv.Clear;
  AExe := '';
  ADisplayCmd := '';
  if AReq.Profile = nil then
    Exit;

  if AReq.Profile.DatabaseType = dtFirebird then
  begin
    DefaultTool := 'gbak';
    if Trim(AReq.ToolExecutablePath) <> '' then
      AExe := Trim(AReq.ToolExecutablePath)
    else
    begin
      AExe := FindMaintenanceToolPath(DefaultTool, AReq.Profile);
      if AExe = '' then
        AExe := DefaultTool;
    end;

    AParams.Add('-b');
    if AReq.Verbose then
      AParams.Add('-v');
    if AReq.FbIgnoreChecksums then
      AParams.Add('-ig');
    if AReq.FbIgnoreLimbo then
      AParams.Add('-l');
    if AReq.FbMetadataOnly then
      AParams.Add('-m');
    if AReq.FbNoGarbageCollect then
      AParams.Add('-g');
    if AReq.FbNonTransportable then
      AParams.Add('-nt');
    if Trim(AReq.Profile.Username) <> '' then
    begin
      AParams.Add('-user');
      AParams.Add(Trim(AReq.Profile.Username));
    end;
    if AReq.Profile.Password <> '' then
    begin
      AParams.Add('-pas');
      AParams.Add(AReq.Profile.Password);
    end;
    if Trim(AReq.Profile.Role) <> '' then
    begin
      AParams.Add('-role');
      AParams.Add(Trim(AReq.Profile.Role));
    end;
    AParams.Add(FormatFirebirdTargetString(AReq.Profile));
    AParams.Add(Trim(AReq.OutputFile));

    ADisplayCmd := FormatMaskedCommandLine(AExe, AParams, AEnv, ['-pas']);
  end
  else
  begin
    DefaultTool := 'pg_dump';
    if Trim(AReq.ToolExecutablePath) <> '' then
      AExe := Trim(AReq.ToolExecutablePath)
    else
    begin
      AExe := FindMaintenanceToolPath(DefaultTool, AReq.Profile);
      if AExe = '' then
        AExe := DefaultTool;
    end;

    if AReq.Profile.Password <> '' then
      AEnv.Add('PGPASSWORD=' + AReq.Profile.Password);

    if Trim(AReq.Profile.Host) <> '' then
    begin
      AParams.Add('-h');
      AParams.Add(Trim(AReq.Profile.Host));
    end;
    PortNum := AReq.Profile.Port;
    if PortNum = 0 then
      PortNum := 5432;
    AParams.Add('-p');
    AParams.Add(IntToStr(PortNum));
    if Trim(AReq.Profile.Username) <> '' then
    begin
      AParams.Add('-U');
      AParams.Add(Trim(AReq.Profile.Username));
    end;

    case AReq.PgFormat of
      pdfPlainSql: FormatFlag := 'p';
      pdfDirectory: FormatFlag := 'd';
      pdfTar: FormatFlag := 't';
    else
      FormatFlag := 'c';
    end;
    AParams.Add('-F');
    AParams.Add(FormatFlag);
    AParams.Add('-f');
    AParams.Add(Trim(AReq.OutputFile));
    if AReq.Verbose then
      AParams.Add('-v');
    if AReq.PgSchemaOnly then
      AParams.Add('-s');
    if AReq.PgDataOnly then
      AParams.Add('-a');
    if AReq.PgNoOwner then
      AParams.Add('-O');
    if AReq.PgClean then
      AParams.Add('-c');
    if AReq.PgIfExists and AReq.PgClean then
      AParams.Add('--if-exists');
    AParams.Add(Trim(AReq.Profile.Database));

    ADisplayCmd := FormatMaskedCommandLine(AExe, AParams, AEnv, []);
  end;
end;

procedure BuildRestoreCliCommand(
  const AReq: TRestoreRequest;
  out AExe: string;
  const AParams, AEnv: TStrings;
  out ADisplayCmd: string
);
var
  DefaultTool, TargetDb: string;
  IsPlainSql: Boolean;
  PortNum: Word;
begin
  AParams.Clear;
  AEnv.Clear;
  AExe := '';
  ADisplayCmd := '';
  if AReq.Profile = nil then
    Exit;

  TargetDb := Trim(AReq.TargetDatabaseOrName);
  if TargetDb = '' then
    TargetDb := Trim(AReq.Profile.Database);

  if AReq.Profile.DatabaseType = dtFirebird then
  begin
    DefaultTool := 'gbak';
    if Trim(AReq.ToolExecutablePath) <> '' then
      AExe := Trim(AReq.ToolExecutablePath)
    else
    begin
      AExe := FindMaintenanceToolPath(DefaultTool, AReq.Profile);
      if AExe = '' then
        AExe := DefaultTool;
    end;

    if AReq.FbReplaceExisting then
      AParams.Add('-rep')
    else
      AParams.Add('-c');

    if AReq.Verbose then
      AParams.Add('-v');
    if AReq.FbDeactivateIndexes then
      AParams.Add('-i');
    if AReq.FbNoValidity then
      AParams.Add('-n');
    if AReq.FbNoShadow then
      AParams.Add('-k');
    if AReq.FbOneAtATime then
      AParams.Add('-o');
    if AReq.FbPageSize > 0 then
    begin
      AParams.Add('-p');
      AParams.Add(IntToStr(AReq.FbPageSize));
    end;
    if Trim(AReq.FbFixFssDataCharset) <> '' then
    begin
      AParams.Add('-fix_fss_data');
      AParams.Add(Trim(AReq.FbFixFssDataCharset));
    end;
    if Trim(AReq.FbFixFssMetaCharset) <> '' then
    begin
      AParams.Add('-fix_fss_metadata');
      AParams.Add(Trim(AReq.FbFixFssMetaCharset));
    end;
    if Trim(AReq.Profile.Username) <> '' then
    begin
      AParams.Add('-user');
      AParams.Add(Trim(AReq.Profile.Username));
    end;
    if AReq.Profile.Password <> '' then
    begin
      AParams.Add('-pas');
      AParams.Add(AReq.Profile.Password);
    end;
    if Trim(AReq.Profile.Role) <> '' then
    begin
      AParams.Add('-role');
      AParams.Add(Trim(AReq.Profile.Role));
    end;
    AParams.Add(Trim(AReq.InputFile));
    AParams.Add(FormatFirebirdTargetString(AReq.Profile, TargetDb));

    ADisplayCmd := FormatMaskedCommandLine(AExe, AParams, AEnv, ['-pas']);
  end
  else
  begin
    IsPlainSql := SameText(ExtractFileExt(Trim(AReq.InputFile)), '.sql');
    if IsPlainSql then
      DefaultTool := 'psql'
    else
      DefaultTool := 'pg_restore';

    if (Trim(AReq.ToolExecutablePath) <> '') and (not IsPlainSql) then
      AExe := Trim(AReq.ToolExecutablePath)
    else
    begin
      AExe := FindMaintenanceToolPath(DefaultTool, AReq.Profile);
      if AExe = '' then
        AExe := DefaultTool;
    end;

    if AReq.Profile.Password <> '' then
      AEnv.Add('PGPASSWORD=' + AReq.Profile.Password);

    if Trim(AReq.Profile.Host) <> '' then
    begin
      AParams.Add('-h');
      AParams.Add(Trim(AReq.Profile.Host));
    end;
    PortNum := AReq.Profile.Port;
    if PortNum = 0 then
      PortNum := 5432;
    AParams.Add('-p');
    AParams.Add(IntToStr(PortNum));
    if Trim(AReq.Profile.Username) <> '' then
    begin
      AParams.Add('-U');
      AParams.Add(Trim(AReq.Profile.Username));
    end;

    if IsPlainSql then
    begin
      AParams.Add('-d');
      AParams.Add(TargetDb);
      AParams.Add('-v');
      AParams.Add('ON_ERROR_STOP=1');
      AParams.Add('-f');
      AParams.Add(Trim(AReq.InputFile));
    end
    else
    begin
      if AReq.PgCreateDb then
      begin
        AParams.Add('-d');
        AParams.Add('postgres');
        AParams.Add('-C');
      end
      else
      begin
        AParams.Add('-d');
        AParams.Add(TargetDb);
      end;
      if AReq.PgClean then
        AParams.Add('-c');
      if AReq.PgIfExists and AReq.PgClean then
        AParams.Add('--if-exists');
      if AReq.PgNoOwner then
        AParams.Add('-O');
      if AReq.Verbose then
        AParams.Add('-v');
      AParams.Add(Trim(AReq.InputFile));
    end;

    ADisplayCmd := FormatMaskedCommandLine(AExe, AParams, AEnv, []);
  end;
end;

procedure BuildRepairCliCommand(
  const AReq: TRepairRequest;
  out AExe: string;
  const AParams, AEnv: TStrings;
  out ADisplayCmd: string
);
var
  DefaultTool, TxStr, SqlCmd, QuotedDb: string;
  PortNum: Word;
begin
  AParams.Clear;
  AEnv.Clear;
  AExe := '';
  ADisplayCmd := '';
  if AReq.Profile = nil then
    Exit;

  if AReq.Profile.DatabaseType = dtFirebird then
  begin
    DefaultTool := 'gfix';
    if Trim(AReq.ToolExecutablePath) <> '' then
      AExe := Trim(AReq.ToolExecutablePath)
    else
    begin
      AExe := FindMaintenanceToolPath(DefaultTool, AReq.Profile);
      if AExe = '' then
        AExe := DefaultTool;
    end;

    case AReq.FbAction of
      fraValidateCheckOnly:
        begin
          AParams.Add('-v');
          AParams.Add('-n');
        end;
      fraValidateFull:
        begin
          AParams.Add('-v');
          AParams.Add('-full');
        end;
      fraMendCorrupt:
        begin
          AParams.Add('-mend');
          AParams.Add('-full');
          AParams.Add('-ignore');
        end;
      fraSweep:
        AParams.Add('-sweep');
      fraListLimbo:
        AParams.Add('-list');
      fraCommitLimboAll:
        begin
          TxStr := Trim(AReq.FbLimboTxId);
          if TxStr = '' then
            TxStr := 'all';
          AParams.Add('-commit');
          AParams.Add(TxStr);
        end;
      fraRollbackLimboAll:
        begin
          TxStr := Trim(AReq.FbLimboTxId);
          if TxStr = '' then
            TxStr := 'all';
          AParams.Add('-rollback');
          AParams.Add(TxStr);
        end;
      fraKillShadows:
        AParams.Add('-kill');
      fraShutdownForce:
        begin
          AParams.Add('-shut');
          AParams.Add('-force');
          AParams.Add('0');
        end;
      fraBringOnline:
        AParams.Add('-online');
    end;

    if AReq.FbIgnoreChecksums and (AReq.FbAction <> fraMendCorrupt) then
      AParams.Add('-ignore');

    if Trim(AReq.Profile.Username) <> '' then
    begin
      AParams.Add('-user');
      AParams.Add(Trim(AReq.Profile.Username));
    end;
    if AReq.Profile.Password <> '' then
    begin
      AParams.Add('-pas');
      AParams.Add(AReq.Profile.Password);
    end;
    AParams.Add(FormatFirebirdTargetString(AReq.Profile));

    ADisplayCmd := FormatMaskedCommandLine(AExe, AParams, AEnv, ['-pas']);
  end
  else
  begin
    DefaultTool := 'psql';
    if Trim(AReq.ToolExecutablePath) <> '' then
      AExe := Trim(AReq.ToolExecutablePath)
    else
    begin
      AExe := FindMaintenanceToolPath(DefaultTool, AReq.Profile);
      if AExe = '' then
        AExe := DefaultTool;
    end;

    if AReq.Profile.Password <> '' then
      AEnv.Add('PGPASSWORD=' + AReq.Profile.Password);

    if Trim(AReq.Profile.Host) <> '' then
    begin
      AParams.Add('-h');
      AParams.Add(Trim(AReq.Profile.Host));
    end;
    PortNum := AReq.Profile.Port;
    if PortNum = 0 then
      PortNum := 5432;
    AParams.Add('-p');
    AParams.Add(IntToStr(PortNum));
    if Trim(AReq.Profile.Username) <> '' then
    begin
      AParams.Add('-U');
      AParams.Add(Trim(AReq.Profile.Username));
    end;
    AParams.Add('-d');
    AParams.Add(Trim(AReq.Profile.Database));
    AParams.Add('-v');
    AParams.Add('ON_ERROR_STOP=1');

    QuotedDb := '"' + StringReplace(Trim(AReq.Profile.Database), '"', '""', [rfReplaceAll]) + '"';
    case AReq.PgAction of
      praVacuum:
        SqlCmd := 'VACUUM (VERBOSE);';
      praVacuumAnalyze:
        SqlCmd := 'VACUUM (VERBOSE, ANALYZE);';
      praVacuumFull:
        SqlCmd := 'VACUUM (FULL, VERBOSE, ANALYZE);';
      praReindexDatabase:
        SqlCmd := 'REINDEX DATABASE ' + QuotedDb + ';';
      praAnalyze:
        SqlCmd := 'ANALYZE VERBOSE;';
      praCheckCorruptedIndexes:
        SqlCmd :=
          'SELECT n.nspname AS schema, tbl.relname AS tabela, c.relname AS indice, ' +
          'i.indisvalid AS valido, i.indisready AS pronto ' +
          'FROM pg_index i ' +
          'JOIN pg_class c ON c.oid = i.indexrelid ' +
          'JOIN pg_class tbl ON tbl.oid = i.indrelid ' +
          'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
          'WHERE n.nspname NOT IN (''pg_catalog'', ''information_schema'') ' +
          '  AND (NOT i.indisvalid OR NOT i.indisready) ' +
          'ORDER BY 1, 2, 3;';
    end;
    AParams.Add('-c');
    AParams.Add(SqlCmd);

    ADisplayCmd := FormatMaskedCommandLine(AExe, AParams, AEnv, []);
  end;
end;

function BuildServicesPreviewText(
  const AKind: TMaintenanceTabKind;
  const AProfile: TConnectionProfile;
  const ADetail: string
): string;
var
  SvcTarget, ActionStr: string;
begin
  if AProfile = nil then
    Exit('Selecione uma conexão Firebird.');

  if Trim(AProfile.Host) = '' then
    SvcTarget := 'service_mgr'
  else if (AProfile.Port > 0) and (AProfile.Port <> 3050) then
    SvcTarget := Format('%s/%d:service_mgr', [Trim(AProfile.Host), AProfile.Port])
  else
    SvcTarget := Trim(AProfile.Host) + ':service_mgr';

  case AKind of
    mtkBackup: ActionStr := 'isc_action_svc_backup';
    mtkRestore: ActionStr := 'isc_action_svc_restore';
    mtkRepair: ActionStr := 'isc_action_svc_repair/properties';
  end;

  Result := Format('Firebird Services API [%s] -> %s | DB: %s | %s', [
    SvcTarget, ActionStr, AProfile.Database, ADetail
  ]);
end;

{ TMaintenanceWorkerThread }

constructor TMaintenanceWorkerThread.CreateBackup(
  const AReq: TBackupRequest;
  const AOnLog: TMaintenanceLogEvent;
  const AOnComplete: TMaintenanceCompleteEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FPendingLog := TStringList.Create;
  FCustomParams := TStringList.Create;
  FCustomEnv := TStringList.Create;
  FOpMode := 0;
  FBackupReq := AReq;
  FProfile := AReq.Profile.Clone;
  FBackupReq.Profile := FProfile;
  FOnLog := AOnLog;
  FOnComplete := AOnComplete;
  FDetached := False;
  FCancelRequested := False;
  FRunningProc := nil;
  FSuccess := False;
  FMessage := '';
end;

constructor TMaintenanceWorkerThread.CreateRestore(
  const AReq: TRestoreRequest;
  const AOnLog: TMaintenanceLogEvent;
  const AOnComplete: TMaintenanceCompleteEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FPendingLog := TStringList.Create;
  FCustomParams := TStringList.Create;
  FCustomEnv := TStringList.Create;
  FOpMode := 1;
  FRestoreReq := AReq;
  FProfile := AReq.Profile.Clone;
  FRestoreReq.Profile := FProfile;
  FOnLog := AOnLog;
  FOnComplete := AOnComplete;
  FDetached := False;
  FCancelRequested := False;
  FRunningProc := nil;
  FSuccess := False;
  FMessage := '';
end;

constructor TMaintenanceWorkerThread.CreateRepair(
  const AReq: TRepairRequest;
  const AOnLog: TMaintenanceLogEvent;
  const AOnComplete: TMaintenanceCompleteEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FPendingLog := TStringList.Create;
  FCustomParams := TStringList.Create;
  FCustomEnv := TStringList.Create;
  FOpMode := 2;
  FRepairReq := AReq;
  FProfile := AReq.Profile.Clone;
  FRepairReq.Profile := FProfile;
  FOnLog := AOnLog;
  FOnComplete := AOnComplete;
  FDetached := False;
  FCancelRequested := False;
  FRunningProc := nil;
  FSuccess := False;
  FMessage := '';
end;

constructor TMaintenanceWorkerThread.CreateCustomCli(
  const AExe: string;
  const AParams, AEnv: TStrings;
  const AOnLog: TMaintenanceLogEvent;
  const AOnComplete: TMaintenanceCompleteEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FPendingLog := TStringList.Create;
  FCustomParams := TStringList.Create;
  FCustomEnv := TStringList.Create;
  FOpMode := 3;
  FProfile := nil;
  FCustomExe := AExe;
  if AParams <> nil then
    FCustomParams.Assign(AParams);
  if AEnv <> nil then
    FCustomEnv.Assign(AEnv);
  FOnLog := AOnLog;
  FOnComplete := AOnComplete;
  FDetached := False;
  FCancelRequested := False;
  FRunningProc := nil;
  FSuccess := False;
  FMessage := '';
end;

destructor TMaintenanceWorkerThread.Destroy;
begin
  FCustomEnv.Free;
  FCustomParams.Free;
  FPendingLog.Free;
  FProfile.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TMaintenanceWorkerThread.RequestCancel;
var
  ProcRef: TProcess;
begin
  FLock.Acquire;
  try
    FCancelRequested := True;
    ProcRef := FRunningProc;
  finally
    FLock.Release;
  end;

  if ProcRef <> nil then
  begin
    try
      if ProcRef.Running then
        ProcRef.Terminate(1);
    except
    end;
  end;
end;

procedure TMaintenanceWorkerThread.Detach;
begin
  FLock.Acquire;
  try
    FDetached := True;
    FCancelRequested := True;
    FOnLog := nil;
    FOnComplete := nil;
  finally
    FLock.Release;
  end;
  RequestCancel;
end;

function TMaintenanceWorkerThread.CheckCancelled: Boolean;
begin
  FLock.Acquire;
  try
    Result := FCancelRequested or FDetached;
  finally
    FLock.Release;
  end;
end;

procedure TMaintenanceWorkerThread.AppendLogLine(const ALine: string);
var
  DetachedCopy: Boolean;
begin
  FLock.Acquire;
  try
    DetachedCopy := FDetached;
    if not DetachedCopy then
      FPendingLog.Add(ALine);
  finally
    FLock.Release;
  end;
  if not DetachedCopy then
    Queue(nil, @DeliverLogOnMainThread);
end;

procedure TMaintenanceWorkerThread.DeliverLogOnMainThread;
var
  DetachedCopy: Boolean;
  Cb: TMaintenanceLogEvent;
  LinesCopy: TStringList;
  I: Integer;
begin
  LinesCopy := TStringList.Create;
  try
    FLock.Acquire;
    try
      DetachedCopy := FDetached;
      Cb := FOnLog;
      LinesCopy.Assign(FPendingLog);
      FPendingLog.Clear;
    finally
      FLock.Release;
    end;

    if (not DetachedCopy) and Assigned(Cb) then
    begin
      for I := 0 to LinesCopy.Count - 1 do
        Cb(LinesCopy[I]);
    end;
  finally
    LinesCopy.Free;
  end;
end;

function TMaintenanceWorkerThread.RunCliProcess(
  const AExe: string;
  const AParams, AEnv: TStrings;
  const ADisplayCmd: string;
  out AErrMsg: string
): Boolean;
var
  Proc: TProcess;
  Buf: array[0..4095] of Byte;
  BytesAvail, BytesRead: Integer;
  Remainder, Chunk, LineText: string;
  P, I, ExitCodeVal: Integer;
begin
  Result := False;
  AErrMsg := '';
  if Trim(AExe) = '' then
  begin
    AErrMsg := 'Executável da ferramenta não encontrado.';
    Exit;
  end;

  AppendLogLine('Comando: ' + ADisplayCmd);

  Proc := TProcess.Create(nil);
  try
    try
      Proc.Executable := AExe;
      if AParams <> nil then
        Proc.Parameters.Assign(AParams);
      if (AEnv <> nil) and (AEnv.Count > 0) then
      begin
        for I := 0 to GetEnvironmentVariableCount - 1 do
          Proc.Environment.Add(GetEnvironmentString(I));
        for I := 0 to AEnv.Count - 1 do
          Proc.Environment.Add(AEnv[I]);
      end;
      Proc.Options := [poUsePipes, poStderrToOutPut];
      Proc.ShowWindow := swoHIDE;

      FLock.Acquire;
      try
        FRunningProc := Proc;
      finally
        FLock.Release;
      end;

      try
        Proc.Execute;
        Remainder := '';
        while Proc.Running or ((Proc.Output <> nil) and (Proc.Output.NumBytesAvailable > 0)) do
        begin
          if CheckCancelled and Proc.Running then
          begin
            try
              Proc.Terminate(1);
            except
            end;
            AErrMsg := 'Operação cancelada pelo usuário.';
            Break;
          end;

          BytesAvail := 0;
          if Proc.Output <> nil then
            BytesAvail := Proc.Output.NumBytesAvailable;

          if BytesAvail > 0 then
          begin
            if BytesAvail > SizeOf(Buf) then
              BytesAvail := SizeOf(Buf);
            BytesRead := Proc.Output.Read(Buf[0], BytesAvail);
            if BytesRead > 0 then
            begin
              SetString(Chunk, PAnsiChar(@Buf[0]), BytesRead);
              Chunk := StringReplace(Chunk, #13#10, #10, [rfReplaceAll]);
              Chunk := StringReplace(Chunk, #13, #10, [rfReplaceAll]);
              Remainder := Remainder + Chunk;
              P := Pos(#10, Remainder);
              while P > 0 do
              begin
                LineText := Copy(Remainder, 1, P - 1);
                Delete(Remainder, 1, P);
                AppendLogLine(LineText);
                P := Pos(#10, Remainder);
              end;
            end;
          end
          else
            Sleep(25);
        end;

        if Remainder <> '' then
          AppendLogLine(Remainder);

        if AErrMsg <> '' then
          Exit(False);

        ExitCodeVal := Proc.ExitStatus;
        if ExitCodeVal = 0 then
        begin
          Result := True;
          AErrMsg := 'Processo concluído com sucesso (código 0).';
        end
        else
        begin
          Result := False;
          AErrMsg := Format('Processo finalizado com erro (código de saída %d).', [ExitCodeVal]);
        end;
      finally
        FLock.Acquire;
        try
          FRunningProc := nil;
        finally
          FLock.Release;
        end;
      end;
    except
      on E: Exception do
      begin
        Result := False;
        AErrMsg := Format('Falha ao iniciar "%s": %s', [AExe, E.Message]);
      end;
    end;
  finally
    Proc.Free;
  end;
end;

procedure TMaintenanceWorkerThread.Execute;
var
  Runner: TFirebirdServicesRunner;
  ExePath, DisplayCmd: string;
  Params, Env: TStringList;
begin
  Params := TStringList.Create;
  Env := TStringList.Create;
  try
    try
      case FOpMode of
        0:
          begin
            if (FBackupReq.Profile.DatabaseType = dtFirebird) and (FBackupReq.Backend = febServicesApi) then
            begin
              Runner := TFirebirdServicesRunner.Create;
              try
                FSuccess := Runner.RunBackup(FBackupReq, @AppendLogLine, @CheckCancelled, FMessage);
              finally
                Runner.Free;
              end;
            end
            else
            begin
              BuildBackupCliCommand(FBackupReq, ExePath, Params, Env, DisplayCmd);
              FSuccess := RunCliProcess(ExePath, Params, Env, DisplayCmd, FMessage);
            end;
          end;
        1:
          begin
            if (FRestoreReq.Profile.DatabaseType = dtFirebird) and (FRestoreReq.Backend = febServicesApi) then
            begin
              Runner := TFirebirdServicesRunner.Create;
              try
                FSuccess := Runner.RunRestore(FRestoreReq, @AppendLogLine, @CheckCancelled, FMessage);
              finally
                Runner.Free;
              end;
            end
            else
            begin
              BuildRestoreCliCommand(FRestoreReq, ExePath, Params, Env, DisplayCmd);
              FSuccess := RunCliProcess(ExePath, Params, Env, DisplayCmd, FMessage);
            end;
          end;
        2:
          begin
            if (FRepairReq.Profile.DatabaseType = dtFirebird) and (FRepairReq.Backend = febServicesApi) then
            begin
              Runner := TFirebirdServicesRunner.Create;
              try
                FSuccess := Runner.RunRepair(FRepairReq, @AppendLogLine, @CheckCancelled, FMessage);
              finally
                Runner.Free;
              end;
            end
            else
            begin
              BuildRepairCliCommand(FRepairReq, ExePath, Params, Env, DisplayCmd);
              FSuccess := RunCliProcess(ExePath, Params, Env, DisplayCmd, FMessage);
            end;
          end;
        3:
          begin
            DisplayCmd := FormatMaskedCommandLine(FCustomExe, FCustomParams, FCustomEnv, []);
            FSuccess := RunCliProcess(FCustomExe, FCustomParams, FCustomEnv, DisplayCmd, FMessage);
          end;
      end;
    except
      on E: Exception do
      begin
        FSuccess := False;
        FMessage := E.Message;
      end;
    end;
  finally
    Env.Free;
    Params.Free;
  end;
  Queue(nil, @FinishOnMainThread);
end;

procedure TMaintenanceWorkerThread.FinishOnMainThread;
var
  WasDetached, SuccessCopy: Boolean;
  MsgCopy: string;
  Cb: TMaintenanceCompleteEvent;
begin
  DeliverLogOnMainThread;
  WaitFor;
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Cb := FOnComplete;
    FOnComplete := nil;
    FOnLog := nil;
    SuccessCopy := FSuccess;
    MsgCopy := FMessage;
  finally
    FLock.Release;
  end;

  try
    if (not WasDetached) and Assigned(Cb) then
      Cb(Self, SuccessCopy, MsgCopy);
  finally
    Free;
  end;
end;

end.
