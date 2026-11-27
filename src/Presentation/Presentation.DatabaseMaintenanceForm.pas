unit Presentation.DatabaseMaintenanceForm;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Clipbrd,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  StdCtrls,
  ExtCtrls,
  ComCtrls,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.Interfaces,
  Domain.MaintenanceTypes,
  Application.DatabaseMaintenanceUseCase;

type
  { Diálogo completo para Backup, Restore e Correção de Base de Dados }
  TDatabaseMaintenanceForm = class(TForm)
    pnlConnSelect: TFlowPanel;
    lblConnection: TLabel;
    cbConnection: TComboBox;
    lblFbBackend: TLabel;
    cbFbBackend: TComboBox;
    lblToolPath: TLabel;
    edtToolPath: TEdit;
    btnBrowseTool: TButton;
    pgMaintenance: TPageControl;
    tsBackup: TTabSheet;
    pnlBkpFile: TFlowPanel;
    lblBkpFile: TLabel;
    edtBkpFile: TEdit;
    btnBrowseBkpFile: TButton;
    chkBkpVerbose: TCheckBox;
    pnlFbBackupOpts: TFlowPanel;
    chkFbBkpIgnoreChecksums: TCheckBox;
    chkFbBkpIgnoreLimbo: TCheckBox;
    chkFbBkpMetadataOnly: TCheckBox;
    chkFbBkpNoGc: TCheckBox;
    chkFbBkpNonTransportable: TCheckBox;
    pnlPgBackupOpts: TFlowPanel;
    lblPgFormat: TLabel;
    cbPgBkpFormat: TComboBox;
    chkPgBkpSchemaOnly: TCheckBox;
    chkPgBkpDataOnly: TCheckBox;
    chkPgBkpNoOwner: TCheckBox;
    chkPgBkpClean: TCheckBox;
    chkPgBkpIfExists: TCheckBox;
    pnlBkpRun: TFlowPanel;
    btnStartBackup: TButton;
    tsRestore: TTabSheet;
    pnlResFiles: TFlowPanel;
    lblResInput: TLabel;
    edtResInput: TEdit;
    btnBrowseResInput: TButton;
    lblResTarget: TLabel;
    edtResTarget: TEdit;
    chkResVerbose: TCheckBox;
    pnlFbRestoreOpts: TFlowPanel;
    rbFbResCreate: TRadioButton;
    rbFbResReplace: TRadioButton;
    chkFbResDeactivateIdx: TCheckBox;
    chkFbResNoValidity: TCheckBox;
    chkFbResNoShadow: TCheckBox;
    chkFbResOneAtATime: TCheckBox;
    lblFbPageSize: TLabel;
    cbFbPageSize: TComboBox;
    pnlPgRestoreOpts: TFlowPanel;
    chkPgResCreateDb: TCheckBox;
    chkPgResClean: TCheckBox;
    chkPgResIfExists: TCheckBox;
    chkPgResNoOwner: TCheckBox;
    pnlResRun: TFlowPanel;
    btnStartRestore: TButton;
    tsRepair: TTabSheet;
    pnlFbRepair: TPanel;
    lblFbRecoveryGuide: TLabel;
    pnlFbRepairOpts: TFlowPanel;
    lblFbRepairAction: TLabel;
    cbFbRepairAction: TComboBox;
    chkFbRepairIgnoreCs: TCheckBox;
    lblLimboTx: TLabel;
    edtLimboTxId: TEdit;
    pnlFbRepairActions: TFlowPanel;
    btnStartRepair: TButton;
    btnEmergencyBackupPreset: TButton;
    pnlPgRepair: TPanel;
    pnlPgRepairOpts: TFlowPanel;
    lblPgRepairAction: TLabel;
    cbPgRepairAction: TComboBox;
    btnStartPgRepair: TButton;
    splOutput: TSplitter;
    pnlOutput: TPanel;
    pnlPreview: TPanel;
    lblPreviewTitle: TLabel;
    edtCmdPreview: TEdit;
    pnlLogBar: TFlowPanel;
    lblOpStatus: TLabel;
    btnCancelOp: TButton;
    btnClearLog: TButton;
    btnCopyLog: TButton;
    btnSaveLog: TButton;
    memOutput: TMemo;
    pnlFooter: TPanel;
    btnClose: TButton;
    dlgOpenFile: TOpenDialog;
    dlgSaveFile: TSaveDialog;
    dlgSaveLog: TSaveDialog;
    tmrElapsed: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure cbConnectionChange(Sender: TObject);
    procedure cbFbBackendChange(Sender: TObject);
    procedure pgMaintenanceChange(Sender: TObject);
    procedure InputsChanged(Sender: TObject);
    procedure cbFbRepairActionChange(Sender: TObject);
    procedure cbPgRepairActionChange(Sender: TObject);
    procedure btnBrowseToolClick(Sender: TObject);
    procedure btnBrowseBkpFileClick(Sender: TObject);
    procedure btnBrowseResInputClick(Sender: TObject);
    procedure btnStartBackupClick(Sender: TObject);
    procedure btnStartRestoreClick(Sender: TObject);
    procedure btnStartRepairClick(Sender: TObject);
    procedure btnEmergencyBackupPresetClick(Sender: TObject);
    procedure btnCancelOpClick(Sender: TObject);
    procedure btnClearLogClick(Sender: TObject);
    procedure btnCopyLogClick(Sender: TObject);
    procedure btnSaveLogClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure tmrElapsedTimer(Sender: TObject);
    procedure PanelsResize(Sender: TObject);
  private
    FProfiles: TConnectionProfileList;
    FFbServiceFactory: IFirebirdMaintenanceServiceFactory;
    FWorker: TMaintenanceWorkerThread;
    FIsRunning: Boolean;
    FStartTick: QWord;
    FCurrentOpLabel: string;
    FUpdatingUI: Boolean;
    procedure PopulateConnections(const AConnections: TConnectionProfileList; const AInitialProfileId: string);
    procedure PopulateRepairActions;
    function SelectedProfile: TConnectionProfile;
    function CurrentBackend: TFirebirdExecBackend;
    function CurrentBackupRequest: TBackupRequest;
    function CurrentRestoreRequest: TRestoreRequest;
    function CurrentRepairRequest: TRepairRequest;
    procedure UpdateModeAndToolVisibility;
    procedure UpdateDefaultPathsForProfile;
    procedure UpdateCommandPreview;
    procedure SetRunningState(const ARunning: Boolean; const ALabelText: string);
    procedure AppendOutputLine(const ALine: string);
    procedure HandleWorkerLog(const ALine: string);
    procedure HandleWorkerComplete(const AWorker: TObject; const ASuccess: Boolean; const AMessage: string);
  public
    class procedure Execute(
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string = '';
      const AInitialTab: TMaintenanceTabKind = mtkBackup;
      const AFbServiceFactory: IFirebirdMaintenanceServiceFactory = nil
    );
  end;

implementation

{$R *.lfm}

class procedure TDatabaseMaintenanceForm.Execute(
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string;
  const AInitialTab: TMaintenanceTabKind;
  const AFbServiceFactory: IFirebirdMaintenanceServiceFactory
);
var
  Frm: TDatabaseMaintenanceForm;
begin
  Frm := TDatabaseMaintenanceForm.Create(nil);
  try
    Frm.FFbServiceFactory := AFbServiceFactory;
    Frm.PopulateConnections(AConnections, AInitialProfileId);
    case AInitialTab of
      mtkBackup: Frm.pgMaintenance.ActivePage := Frm.tsBackup;
      mtkRestore: Frm.pgMaintenance.ActivePage := Frm.tsRestore;
      mtkRepair: Frm.pgMaintenance.ActivePage := Frm.tsRepair;
    end;
    Frm.UpdateModeAndToolVisibility;
    Frm.UpdateDefaultPathsForProfile;
    Frm.UpdateCommandPreview;
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

procedure TDatabaseMaintenanceForm.FormCreate(Sender: TObject);
begin
  FProfiles := TConnectionProfileList.Create(True);
  FWorker := nil;
  FIsRunning := False;
  FStartTick := 0;
  FCurrentOpLabel := '';
  FUpdatingUI := False;
  {$IFDEF UNIX}
  memOutput.Font.Name := 'Monospace';
  edtCmdPreview.Font.Name := 'Monospace';
  {$ENDIF}
  PopulateRepairActions;
end;

procedure TDatabaseMaintenanceForm.FormDestroy(Sender: TObject);
begin
  if tmrElapsed <> nil then
    tmrElapsed.Enabled := False;
  if FWorker <> nil then
  begin
    FWorker.Detach;
    FWorker := nil;
  end;
  FreeAndNil(FProfiles);
end;

procedure TDatabaseMaintenanceForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FIsRunning then
  begin
    if MessageDlg(
         'Operação em Andamento',
         'Há uma operação de manutenção em andamento. Deseja cancelar e fechar esta janela?',
         mtConfirmation,
         [mbYes, mbNo],
         0
       ) <> mrYes then
    begin
      CanClose := False;
      Exit;
    end;
    if FWorker <> nil then
    begin
      FWorker.Detach;
      FWorker := nil;
    end;
    FIsRunning := False;
  end;
end;

procedure TDatabaseMaintenanceForm.PopulateRepairActions;
var
  FbAct: TFirebirdRepairAction;
  PgAct: TPostgresRepairAction;
begin
  cbFbRepairAction.Items.BeginUpdate;
  try
    cbFbRepairAction.Items.Clear;
    for FbAct := Low(TFirebirdRepairAction) to High(TFirebirdRepairAction) do
      cbFbRepairAction.Items.Add(FirebirdRepairActionTitle(FbAct));
    cbFbRepairAction.ItemIndex := 0;
  finally
    cbFbRepairAction.Items.EndUpdate;
  end;

  cbPgRepairAction.Items.BeginUpdate;
  try
    cbPgRepairAction.Items.Clear;
    for PgAct := Low(TPostgresRepairAction) to High(TPostgresRepairAction) do
      cbPgRepairAction.Items.Add(PostgresRepairActionTitle(PgAct));
    cbPgRepairAction.ItemIndex := 1; // VACUUM ANALYZE
  finally
    cbPgRepairAction.Items.EndUpdate;
  end;
end;

procedure TDatabaseMaintenanceForm.PopulateConnections(
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string
);
var
  Item, Cloned: TConnectionProfile;
  Idx, SelIdx: Integer;
begin
  FProfiles.Clear;
  cbConnection.Items.BeginUpdate;
  try
    cbConnection.Items.Clear;
    SelIdx := -1;
    if AConnections <> nil then
    begin
      for Item in AConnections do
      begin
        Cloned := Item.Clone;
        FProfiles.Add(Cloned);
        Idx := cbConnection.Items.AddObject(
          Format('%s [%s]', [Cloned.Name, DatabaseTypeToStr(Cloned.DatabaseType)]),
          Cloned
        );
        if (AInitialProfileId <> '') and SameText(Cloned.Id, AInitialProfileId) then
          SelIdx := Idx;
      end;
    end;
    if (SelIdx < 0) and (cbConnection.Items.Count > 0) then
      SelIdx := 0;
    cbConnection.ItemIndex := SelIdx;
  finally
    cbConnection.Items.EndUpdate;
  end;
end;

function TDatabaseMaintenanceForm.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection.ItemIndex >= 0) and (cbConnection.ItemIndex < cbConnection.Items.Count) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

function TDatabaseMaintenanceForm.CurrentBackend: TFirebirdExecBackend;
begin
  if cbFbBackend.ItemIndex = 1 then
    Result := febCliTools
  else
    Result := febServicesApi;
end;

procedure TDatabaseMaintenanceForm.UpdateModeAndToolVisibility;
var
  P: TConnectionProfile;
  IsFb, IsServices, NeedsToolInput, ShowLimbo: Boolean;
  FbAct: TFirebirdRepairAction;
  ToolName, FoundPath: string;
begin
  P := SelectedProfile;
  IsFb := (P = nil) or (P.DatabaseType = dtFirebird);

  lblFbBackend.Visible := IsFb;
  cbFbBackend.Visible := IsFb;

  pnlFbBackupOpts.Visible := IsFb;
  pnlPgBackupOpts.Visible := not IsFb;

  pnlFbRestoreOpts.Visible := IsFb;
  pnlPgRestoreOpts.Visible := not IsFb;

  pnlFbRepair.Visible := IsFb;
  pnlPgRepair.Visible := not IsFb;

  IsServices := IsFb and (CurrentBackend = febServicesApi);
  NeedsToolInput := (not IsFb) or (not IsServices);

  lblToolPath.Visible := NeedsToolInput;
  edtToolPath.Visible := NeedsToolInput;
  btnBrowseTool.Visible := NeedsToolInput;

  if NeedsToolInput and (not FUpdatingUI) then
  begin
    if IsFb then
    begin
      if pgMaintenance.ActivePage = tsRepair then
        ToolName := 'gfix'
      else
        ToolName := 'gbak';
    end
    else
    begin
      if pgMaintenance.ActivePage = tsBackup then
        ToolName := 'pg_dump'
      else if pgMaintenance.ActivePage = tsRestore then
        ToolName := 'pg_restore'
      else
        ToolName := 'psql';
    end;
    FoundPath := FindMaintenanceToolPath(ToolName, P);
    edtToolPath.TextHint := ToolName + ' (auto)';
    if (Trim(edtToolPath.Text) = '') and (FoundPath <> '') then
    begin
      FUpdatingUI := True;
      try
        edtToolPath.Text := FoundPath;
      finally
        FUpdatingUI := False;
      end;
    end;
  end;

  if IsFb and (cbFbRepairAction.ItemIndex >= 0) then
  begin
    FbAct := TFirebirdRepairAction(cbFbRepairAction.ItemIndex);
    ShowLimbo := FbAct in [fraCommitLimboAll, fraRollbackLimboAll];
    lblLimboTx.Visible := ShowLimbo;
    edtLimboTxId.Visible := ShowLimbo;
    chkFbRepairIgnoreCs.Visible := FbAct in [fraValidateCheckOnly, fraValidateFull, fraMendCorrupt];
  end;
end;

procedure TDatabaseMaintenanceForm.UpdateDefaultPathsForProfile;
var
  P: TConnectionProfile;
  BaseName, Stamp, Ext: string;
begin
  P := SelectedProfile;
  if P = nil then
    Exit;

  FUpdatingUI := True;
  try
    Stamp := FormatDateTime('yyyymmdd_hhnn', Now);
    if P.DatabaseType = dtFirebird then
    begin
      BaseName := ChangeFileExt(ExtractFileName(P.Database), '');
      if BaseName = '' then
        BaseName := P.Name;
      edtBkpFile.Text := BaseName + '_' + Stamp + '.fbk';
      edtResTarget.Text := P.Database;
    end
    else
    begin
      BaseName := Trim(P.Database);
      if BaseName = '' then
        BaseName := P.Name;
      Ext := '.dump';
      if cbPgBkpFormat.ItemIndex = 1 then
        Ext := '.sql'
      else if cbPgBkpFormat.ItemIndex = 3 then
        Ext := '.tar';
      edtBkpFile.Text := IncludeTrailingPathDelimiter(GetTempDir) + BaseName + '_' + Stamp + Ext;
      edtResTarget.Text := BaseName;
    end;
  finally
    FUpdatingUI := False;
  end;
end;

function TDatabaseMaintenanceForm.CurrentBackupRequest: TBackupRequest;
begin
  Result := DefaultBackupRequest;
  Result.Profile := SelectedProfile;
  Result.Backend := CurrentBackend;
  Result.ToolExecutablePath := Trim(edtToolPath.Text);
  Result.OutputFile := Trim(edtBkpFile.Text);
  Result.Verbose := chkBkpVerbose.Checked;
  Result.FbIgnoreChecksums := chkFbBkpIgnoreChecksums.Checked;
  Result.FbIgnoreLimbo := chkFbBkpIgnoreLimbo.Checked;
  Result.FbMetadataOnly := chkFbBkpMetadataOnly.Checked;
  Result.FbNoGarbageCollect := chkFbBkpNoGc.Checked;
  Result.FbNonTransportable := chkFbBkpNonTransportable.Checked;

  case cbPgBkpFormat.ItemIndex of
    1: Result.PgFormat := pdfPlainSql;
    2: Result.PgFormat := pdfDirectory;
    3: Result.PgFormat := pdfTar;
  else
    Result.PgFormat := pdfCustom;
  end;
  Result.PgSchemaOnly := chkPgBkpSchemaOnly.Checked;
  Result.PgDataOnly := chkPgBkpDataOnly.Checked;
  Result.PgNoOwner := chkPgBkpNoOwner.Checked;
  Result.PgClean := chkPgBkpClean.Checked;
  Result.PgIfExists := chkPgBkpIfExists.Checked;
end;

function TDatabaseMaintenanceForm.CurrentRestoreRequest: TRestoreRequest;
begin
  Result := DefaultRestoreRequest;
  Result.Profile := SelectedProfile;
  Result.Backend := CurrentBackend;
  Result.ToolExecutablePath := Trim(edtToolPath.Text);
  Result.InputFile := Trim(edtResInput.Text);
  Result.TargetDatabaseOrName := Trim(edtResTarget.Text);
  Result.Verbose := chkResVerbose.Checked;
  Result.FbCreateNew := rbFbResCreate.Checked;
  Result.FbReplaceExisting := rbFbResReplace.Checked;
  Result.FbDeactivateIndexes := chkFbResDeactivateIdx.Checked;
  Result.FbNoValidity := chkFbResNoValidity.Checked;
  Result.FbNoShadow := chkFbResNoShadow.Checked;
  Result.FbOneAtATime := chkFbResOneAtATime.Checked;
  if cbFbPageSize.ItemIndex > 0 then
    Result.FbPageSize := StrToIntDef(cbFbPageSize.Text, 0)
  else
    Result.FbPageSize := 0;
  Result.PgCreateDb := chkPgResCreateDb.Checked;
  Result.PgClean := chkPgResClean.Checked;
  Result.PgIfExists := chkPgResIfExists.Checked;
  Result.PgNoOwner := chkPgResNoOwner.Checked;
end;

function TDatabaseMaintenanceForm.CurrentRepairRequest: TRepairRequest;
begin
  Result := DefaultRepairRequest;
  Result.Profile := SelectedProfile;
  Result.Backend := CurrentBackend;
  Result.ToolExecutablePath := Trim(edtToolPath.Text);
  Result.Verbose := True;
  if cbFbRepairAction.ItemIndex >= 0 then
    Result.FbAction := TFirebirdRepairAction(cbFbRepairAction.ItemIndex);
  Result.FbIgnoreChecksums := chkFbRepairIgnoreCs.Checked;
  Result.FbLimboTxId := Trim(edtLimboTxId.Text);
  if cbPgRepairAction.ItemIndex >= 0 then
    Result.PgAction := TPostgresRepairAction(cbPgRepairAction.ItemIndex);
end;

procedure TDatabaseMaintenanceForm.UpdateCommandPreview;
var
  P: TConnectionProfile;
  ExePath, DisplayCmd: string;
  Params, Env: TStringList;
begin
  P := SelectedProfile;
  if P = nil then
  begin
    edtCmdPreview.Text := 'Nenhuma conexão selecionada.';
    Exit;
  end;

  Params := TStringList.Create;
  Env := TStringList.Create;
  try
    if (P.DatabaseType = dtFirebird) and (CurrentBackend = febServicesApi) then
    begin
      if pgMaintenance.ActivePage = tsBackup then
        edtCmdPreview.Text := BuildServicesPreviewText(mtkBackup, P, 'Destino: ' + Trim(edtBkpFile.Text))
      else if pgMaintenance.ActivePage = tsRestore then
        edtCmdPreview.Text := BuildServicesPreviewText(mtkRestore, P, 'Origem: ' + Trim(edtResInput.Text) + ' -> ' + Trim(edtResTarget.Text))
      else
        edtCmdPreview.Text := BuildServicesPreviewText(mtkRepair, P, cbFbRepairAction.Text);
      Exit;
    end;

    if pgMaintenance.ActivePage = tsBackup then
      BuildBackupCliCommand(CurrentBackupRequest, ExePath, Params, Env, DisplayCmd)
    else if pgMaintenance.ActivePage = tsRestore then
      BuildRestoreCliCommand(CurrentRestoreRequest, ExePath, Params, Env, DisplayCmd)
    else
      BuildRepairCliCommand(CurrentRepairRequest, ExePath, Params, Env, DisplayCmd);

    edtCmdPreview.Text := DisplayCmd;
  finally
    Env.Free;
    Params.Free;
  end;
end;

procedure TDatabaseMaintenanceForm.SetRunningState(const ARunning: Boolean; const ALabelText: string);
begin
  FIsRunning := ARunning;
  cbConnection.Enabled := not ARunning;
  cbFbBackend.Enabled := not ARunning;
  edtToolPath.Enabled := not ARunning;
  btnBrowseTool.Enabled := not ARunning;
  btnStartBackup.Enabled := not ARunning;
  btnStartRestore.Enabled := not ARunning;
  btnStartRepair.Enabled := not ARunning;
  btnEmergencyBackupPreset.Enabled := not ARunning;
  btnStartPgRepair.Enabled := not ARunning;
  btnCancelOp.Enabled := ARunning;

  if ARunning then
  begin
    FStartTick := GetTickCount64;
    FCurrentOpLabel := ALabelText;
    lblOpStatus.Font.Color := clNavy;
    lblOpStatus.Caption := ALabelText + ' (0,0s)';
    tmrElapsed.Enabled := True;
  end
  else
  begin
    tmrElapsed.Enabled := False;
    lblOpStatus.Font.Color := clWindowText;
    lblOpStatus.Caption := ALabelText;
  end;
end;

procedure TDatabaseMaintenanceForm.AppendOutputLine(const ALine: string);
begin
  memOutput.Lines.Add(ALine);
  memOutput.SelStart := Length(memOutput.Text);
end;

procedure TDatabaseMaintenanceForm.HandleWorkerLog(const ALine: string);
begin
  AppendOutputLine(ALine);
end;

procedure TDatabaseMaintenanceForm.HandleWorkerComplete(
  const AWorker: TObject;
  const ASuccess: Boolean;
  const AMessage: string
);
var
  ElapsedStr, FinalStatus: string;
begin
  if FWorker = AWorker then
    FWorker := nil;

  ElapsedStr := FormatFloat('0.0', (GetTickCount64 - FStartTick) / 1000.0) + 's';
  if ASuccess then
    FinalStatus := Format('Concluído (%s): %s', [ElapsedStr, AMessage])
  else
    FinalStatus := Format('Falhou (%s): %s', [ElapsedStr, AMessage]);

  AppendOutputLine('------------------------------------------------------------');
  AppendOutputLine(FinalStatus);
  SetRunningState(False, FinalStatus);
end;

procedure TDatabaseMaintenanceForm.cbConnectionChange(Sender: TObject);
begin
  edtToolPath.Text := '';
  UpdateModeAndToolVisibility;
  UpdateDefaultPathsForProfile;
  UpdateCommandPreview;
end;

procedure TDatabaseMaintenanceForm.cbFbBackendChange(Sender: TObject);
begin
  edtToolPath.Text := '';
  UpdateModeAndToolVisibility;
  UpdateCommandPreview;
end;

procedure TDatabaseMaintenanceForm.pgMaintenanceChange(Sender: TObject);
begin
  edtToolPath.Text := '';
  UpdateModeAndToolVisibility;
  UpdateCommandPreview;
end;

procedure TDatabaseMaintenanceForm.InputsChanged(Sender: TObject);
begin
  if not FUpdatingUI then
    UpdateCommandPreview;
end;

procedure TDatabaseMaintenanceForm.cbFbRepairActionChange(Sender: TObject);
begin
  UpdateModeAndToolVisibility;
  UpdateCommandPreview;
end;

procedure TDatabaseMaintenanceForm.cbPgRepairActionChange(Sender: TObject);
begin
  UpdateCommandPreview;
end;

procedure TDatabaseMaintenanceForm.btnBrowseToolClick(Sender: TObject);
begin
  dlgOpenFile.Title := 'Selecionar Executável da Ferramenta';
  dlgOpenFile.Filter := 'Todos os arquivos (*.*)|*.*';
  if dlgOpenFile.Execute then
  begin
    edtToolPath.Text := dlgOpenFile.FileName;
    UpdateCommandPreview;
  end;
end;

procedure TDatabaseMaintenanceForm.btnBrowseBkpFileClick(Sender: TObject);
var
  P: TConnectionProfile;
begin
  P := SelectedProfile;
  if (P <> nil) and (P.DatabaseType = dtFirebird) then
    dlgSaveFile.Filter := 'Backup Firebird (*.fbk;*.gbk)|*.fbk;*.gbk|Todos os arquivos (*.*)|*.*'
  else
    dlgSaveFile.Filter := 'Backup PostgreSQL (*.dump;*.sql;*.tar)|*.dump;*.sql;*.tar|Todos os arquivos (*.*)|*.*';
  dlgSaveFile.FileName := edtBkpFile.Text;
  if dlgSaveFile.Execute then
  begin
    edtBkpFile.Text := dlgSaveFile.FileName;
    UpdateCommandPreview;
  end;
end;

procedure TDatabaseMaintenanceForm.btnBrowseResInputClick(Sender: TObject);
var
  P: TConnectionProfile;
begin
  P := SelectedProfile;
  if (P <> nil) and (P.DatabaseType = dtFirebird) then
    dlgOpenFile.Filter := 'Backup Firebird (*.fbk;*.gbk)|*.fbk;*.gbk|Todos os arquivos (*.*)|*.*'
  else
    dlgOpenFile.Filter := 'Backup PostgreSQL (*.dump;*.sql;*.tar)|*.dump;*.sql;*.tar|Todos os arquivos (*.*)|*.*';
  dlgOpenFile.FileName := edtResInput.Text;
  if dlgOpenFile.Execute then
  begin
    edtResInput.Text := dlgOpenFile.FileName;
    UpdateCommandPreview;
  end;
end;

procedure TDatabaseMaintenanceForm.btnStartBackupClick(Sender: TObject);
var
  Req: TBackupRequest;
begin
  if FIsRunning then
    Exit;
  Req := CurrentBackupRequest;
  if Req.Profile = nil then
  begin
    MessageDlg('Aviso', 'Selecione uma conexão válida.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if Trim(Req.OutputFile) = '' then
  begin
    MessageDlg('Aviso', 'Informe o arquivo de destino para o backup.', mtWarning, [mbOK], 0);
    edtBkpFile.SetFocus;
    Exit;
  end;

  AppendOutputLine('');
  AppendOutputLine(Format('=== [%s] Iniciando Backup de "%s" ===', [FormatDateTime('hh:nn:ss', Now), Req.Profile.Name]));
  SetRunningState(True, 'Executando Backup');
  FWorker := TMaintenanceWorkerThread.CreateBackup(Req, @HandleWorkerLog, @HandleWorkerComplete, FFbServiceFactory);
  FWorker.Start;
end;

procedure TDatabaseMaintenanceForm.btnStartRestoreClick(Sender: TObject);
var
  Req: TRestoreRequest;
  PromptMsg: string;
begin
  if FIsRunning then
    Exit;
  Req := CurrentRestoreRequest;
  if Req.Profile = nil then
  begin
    MessageDlg('Aviso', 'Selecione uma conexão válida.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if Trim(Req.InputFile) = '' then
  begin
    MessageDlg('Aviso', 'Informe o arquivo de backup para restaurar.', mtWarning, [mbOK], 0);
    edtResInput.SetFocus;
    Exit;
  end;

  if (Req.Profile.DatabaseType = dtFirebird) and Req.FbReplaceExisting then
  begin
    PromptMsg := Format(
      'ATENÇÃO: A opção "Sobrescrever (-rep)" apagará e recriará a base "%s". Deseja continuar?',
      [Req.TargetDatabaseOrName]
    );
    if MessageDlg('Confirmar Restore Destrutivo', PromptMsg, mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end
  else if (Req.Profile.DatabaseType = dtPostgreSQL) and Req.PgClean then
  begin
    PromptMsg := Format(
      'A opção "Clean (-c)" removerá objetos existentes em "%s" antes de restaurar. Deseja continuar?',
      [Req.TargetDatabaseOrName]
    );
    if MessageDlg('Confirmar Restore', PromptMsg, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  AppendOutputLine('');
  AppendOutputLine(Format('=== [%s] Iniciando Restore para "%s" ===', [FormatDateTime('hh:nn:ss', Now), Req.TargetDatabaseOrName]));
  SetRunningState(True, 'Executando Restore');
  FWorker := TMaintenanceWorkerThread.CreateRestore(Req, @HandleWorkerLog, @HandleWorkerComplete, FFbServiceFactory);
  FWorker.Start;
end;

procedure TDatabaseMaintenanceForm.btnStartRepairClick(Sender: TObject);
var
  Req: TRepairRequest;
  ConfirmMsg: string;
begin
  if FIsRunning then
    Exit;
  Req := CurrentRepairRequest;
  if Req.Profile = nil then
  begin
    MessageDlg('Aviso', 'Selecione uma conexão válida.', mtInformation, [mbOK], 0);
    Exit;
  end;

  ConfirmMsg := '';
  if Req.Profile.DatabaseType = dtFirebird then
  begin
    case Req.FbAction of
      fraMendCorrupt:
        ConfirmMsg := 'ATENÇÃO: O comando MEND (-mend) pode descartar registros em páginas danificadas para permitir backup/restore. Certifique-se de ter uma cópia física do arquivo .fdb antes. Continuar?';
      fraShutdownForce:
        ConfirmMsg := 'Deseja desligar o banco imediatamente (derrubando conexões ativas)?';
      fraCommitLimboAll, fraRollbackLimboAll:
        ConfirmMsg := 'Deseja confirmar/desfazer a(s) transação(ões) em limbo informada(s)?';
      fraKillShadows:
        ConfirmMsg := 'Deseja remover referências a arquivos Shadow indisponíveis?';
    end;
  end
  else
  begin
    if Req.PgAction in [praVacuumFull, praReindexDatabase] then
      ConfirmMsg := 'Esta manutenção adquire bloqueio exclusivo temporário nas tabelas ou reconstrói os índices da base. Deseja continuar?';
  end;

  if (ConfirmMsg <> '') and
     (MessageDlg('Confirmar Ação de Reparo', ConfirmMsg, mtWarning, [mbYes, mbNo], 0) <> mrYes) then
    Exit;

  AppendOutputLine('');
  AppendOutputLine(Format('=== [%s] Manutenção/Correção em "%s" ===', [FormatDateTime('hh:nn:ss', Now), Req.Profile.Name]));
  SetRunningState(True, 'Executando Correção');
  FWorker := TMaintenanceWorkerThread.CreateRepair(Req, @HandleWorkerLog, @HandleWorkerComplete, FFbServiceFactory);
  FWorker.Start;
end;

procedure TDatabaseMaintenanceForm.btnEmergencyBackupPresetClick(Sender: TObject);
begin
  if FIsRunning then
    Exit;
  chkBkpVerbose.Checked := True;
  chkFbBkpIgnoreChecksums.Checked := True;
  chkFbBkpIgnoreLimbo.Checked := True;
  chkFbBkpNoGc.Checked := True;
  chkFbBkpMetadataOnly.Checked := False;
  pgMaintenance.ActivePage := tsBackup;
  UpdateModeAndToolVisibility;
  UpdateCommandPreview;
  AppendOutputLine('Preset aplicado: Backup de Emergência Firebird (-b -g -ig -l -v). Clique em "Executar Backup".');
end;

procedure TDatabaseMaintenanceForm.btnCancelOpClick(Sender: TObject);
begin
  if FWorker <> nil then
  begin
    FWorker.RequestCancel;
    btnCancelOp.Enabled := False;
    lblOpStatus.Caption := 'Solicitando cancelamento...';
    AppendOutputLine('Solicitando cancelamento...');
  end;
end;

procedure TDatabaseMaintenanceForm.btnClearLogClick(Sender: TObject);
begin
  memOutput.Clear;
end;

procedure TDatabaseMaintenanceForm.btnCopyLogClick(Sender: TObject);
begin
  Clipboard.AsText := memOutput.Lines.Text;
end;

procedure TDatabaseMaintenanceForm.btnSaveLogClick(Sender: TObject);
begin
  if dlgSaveLog.Execute then
    memOutput.Lines.SaveToFile(dlgSaveLog.FileName, TEncoding.UTF8);
end;

procedure TDatabaseMaintenanceForm.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TDatabaseMaintenanceForm.tmrElapsedTimer(Sender: TObject);
begin
  if not FIsRunning then
  begin
    tmrElapsed.Enabled := False;
    Exit;
  end;
  lblOpStatus.Caption := Format('%s (%s)', [
    FCurrentOpLabel,
    FormatFloat('0.0', (GetTickCount64 - FStartTick) / 1000.0) + 's'
  ]);
end;

procedure TDatabaseMaintenanceForm.PanelsResize(Sender: TObject);
var
  Panel: TFlowPanel;
begin
  if Sender is TFlowPanel then
  begin
    Panel := TFlowPanel(Sender);
    Panel.ReAlign;
    Panel.InvalidatePreferredSize;
    Panel.AdjustSize;
  end;
end;

end.
