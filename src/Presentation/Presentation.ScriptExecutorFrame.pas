unit Presentation.ScriptExecutorFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Clipbrd, Forms, Controls, Graphics, Dialogs,
  ExtCtrls, StdCtrls, ComCtrls, Grids, CheckLst, LCLType,
  SynEdit, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Domain.ScriptExecutionTypes,
  Application.AsyncQueryRunner,
  Application.ScriptExecutorUseCase,
  Presentation.SqlCompletionController,
  Presentation.SqlObjectLinkController;

const
  MAX_EDITOR_DIRECT_LOAD_BYTES = 2 * 1024 * 1024; // 2 MB

type
  { Frame visual estilo IBExpert Script Executive para executar vários scripts SQL }
  TScriptExecutorFrame = class(TFrame)
    pnlToolbar: TFlowPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    btnExecuteScript: TButton;
    btnExecuteFromCursor: TButton;
    btnExecuteSelection: TButton;
    btnPauseResume: TButton;
    btnCancel: TButton;
    btnCommit: TButton;
    btnRollback: TButton;
    lblCommitMode: TLabel;
    cbCommitMode: TComboBox;
    edtCommitEveryN: TEdit;
    lblErrorPolicy: TLabel;
    cbErrorPolicy: TComboBox;
    btnOpenFile: TButton;
    btnSaveFile: TButton;
    btnClearScript: TButton;
    lblTxStatus: TLabel;
    pnlTopArea: TPanel;
    pnlQueue: TPanel;
    lblQueueTitle: TLabel;
    pnlQueueBar: TFlowPanel;
    btnQueueAdd: TButton;
    btnQueueRemove: TButton;
    btnQueueUp: TButton;
    btnQueueDown: TButton;
    btnQueueClear: TButton;
    clbFiles: TCheckListBox;
    pnlQueueFooter: TPanel;
    chkRunQueueDirect: TCheckBox;
    btnLoadQueueToEditor: TButton;
    splQueue: TSplitter;
    SynEdit1: TSynEdit;
    Splitter1: TSplitter;
    pnlBottom: TPanel;
    pnlProgress: TPanel;
    pbProgress: TProgressBar;
    lblProgress: TLabel;
    pgOutput: TPageControl;
    tsStatements: TTabSheet;
    grdStatements: TStringGrid;
    tsLog: TTabSheet;
    pnlLogBar: TFlowPanel;
    btnCopyLog: TButton;
    btnSaveLog: TButton;
    btnClearLog: TButton;
    chkLogToFile: TCheckBox;
    edtLogFile: TEdit;
    btnBrowseLogFile: TButton;
    memLog: TMemo;
    SynSQLSyn1: TSynSQLSyn;
    dlgOpenSql: TOpenDialog;
    dlgAddSqlFiles: TOpenDialog;
    dlgSaveSql: TSaveDialog;
    dlgSaveLog: TSaveDialog;
    tmrElapsed: TTimer;
    procedure cbConnectionChange(Sender: TObject);
    procedure cbCommitModeChange(Sender: TObject);
    procedure chkLogToFileChange(Sender: TObject);
    procedure btnBrowseLogFileClick(Sender: TObject);
    procedure btnExecuteScriptClick(Sender: TObject);
    procedure btnExecuteFromCursorClick(Sender: TObject);
    procedure btnExecuteSelectionClick(Sender: TObject);
    procedure btnPauseResumeClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnCommitClick(Sender: TObject);
    procedure btnRollbackClick(Sender: TObject);
    procedure btnOpenFileClick(Sender: TObject);
    procedure btnSaveFileClick(Sender: TObject);
    procedure btnClearScriptClick(Sender: TObject);
    procedure btnQueueAddClick(Sender: TObject);
    procedure btnQueueRemoveClick(Sender: TObject);
    procedure btnQueueUpClick(Sender: TObject);
    procedure btnQueueDownClick(Sender: TObject);
    procedure btnQueueClearClick(Sender: TObject);
    procedure clbFilesClickCheck(Sender: TObject);
    procedure clbFilesDblClick(Sender: TObject);
    procedure btnLoadQueueToEditorClick(Sender: TObject);
    procedure btnCopyLogClick(Sender: TObject);
    procedure btnSaveLogClick(Sender: TObject);
    procedure btnClearLogClick(Sender: TObject);
    procedure SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure grdStatementsDblClick(Sender: TObject);
    procedure grdStatementsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure grdStatementsPrepareCanvas(sender: TObject; aCol, aRow: Integer;
      aState: TGridDrawState);
    procedure PanelsResize(Sender: TObject);
    procedure Splitter1Moved(Sender: TObject);
    procedure tmrElapsedTimer(Sender: TObject);
  private
    FFactory: IDatabaseProviderFactory;
    FProfiles: TConnectionProfileList;
    FActiveProfileId: string;
    FSession: IDatabaseSession;
    FQueueFilePaths: TStringList;
    FLoadedFilePath: string;
    FWorker: TScriptExecutorWorker;
    FCancelWorker: TCancelQueryWorker;
    FIsBusy: Boolean;
    FCancelRequested: Boolean;
    FExecStartTick: QWord;
    FExecutedCount: Integer;
    FTotalStatements: Integer;
    FBaseTabCaption: string;
    FOutcomes: TScriptStatementOutcomeArray;
    FEditorSplitRatio: Double;
    FIsAdjustingSplit: Boolean;
    FUpdatingLayout: Boolean;
    FCompletionCtrl: TSqlCompletionController;
    FLinkCtrl: TSqlObjectLinkController;
    FOnOpenObject: TOpenDbObjectLinkEvent;
    function SelectedProfile: TConnectionProfile;
    function ExecuteCompletionMetadataQuery(const ASQL: string): TQueryResult;
    procedure HandleOpenObjectLink(const AProfile: TConnectionProfile;
      const AKind: TSchemaObjectKind; const AObjectName: string);
    procedure ClearMetadataCache;
    function SelectedCommitMode: TScriptCommitMode;
    function SelectedErrorPolicy: TScriptErrorPolicy;
    procedure CollectCheckedQueuePaths(const ATarget: TStrings);
    procedure UpdateQueueTitleAndButtons;
    procedure SwapQueueItems(const AIdxA, AIdxB: Integer);
    procedure OpenFileIntoEditor(const AFilePath: string);
    procedure ConfigureGrid;
    procedure ApplyHighlighterForProfile(const AProfile: TConnectionProfile);
    procedure LogMessage(const AMsg: string);
    procedure UpdateLayouts;
    procedure AdjustSplitHeight;
    procedure UpdateTransactionUI;
    function BaseTabCaption: string;
    function FormatElapsedSeconds: string;
    function FormatThroughputText: string;
    procedure SetRunningState(const ARunning: Boolean; const ATotalStatements: Integer);
    procedure StartScriptExecution(const AMode: Integer); // 0=auto(queue or all), 1=cursor, 2=selection
    procedure JumpToLocation(const ASourceFile: string; const ALineNum: Integer);
    procedure HandleScriptProgress(
      const ANewOutcomes: TScriptStatementOutcomeArray;
      const AExecutedCount, ATotalCount: Integer
    );
    procedure HandleErrorPrompt(
      const AOutcome: TScriptStatementOutcome;
      out AAction: TScriptErrorAction
    );
    procedure HandleScriptCompleted(
      const AWorker: TObject;
      const ASummary: TScriptExecutionSummary
    );
    procedure HandleCancelCompleted(
      const AWorker: TCancelQueryWorker;
      const ASuccess: Boolean;
      const AMessage: string
    );
  protected
    procedure Resize; override;
  public
    destructor Destroy; override;
    procedure Initialize(
      const AFactory: IDatabaseProviderFactory;
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string = ''
    );
    property OnOpenObject: TOpenDbObjectLinkEvent
      read FOnOpenObject write FOnOpenObject;
    procedure RefreshConnections(const AConnections: TConnectionProfileList);
    procedure SetScriptText(const AScriptText: string);
    function ActiveProfileId: string;
    function IsBusy: Boolean;
    function IsConnected: Boolean;
    function HasActiveTransaction: Boolean;
    procedure RequestCancel;
    procedure DetachAndCancel;
    procedure DisconnectSession;
  end;

implementation

uses
  Presentation.TabHelpers;

{$R *.lfm}

destructor TScriptExecutorFrame.Destroy;
begin
  DetachAndCancel;
  if FSession <> nil then
  begin
    try
      if FSession.InTransaction then
        FSession.Rollback;
      FSession.Disconnect;
    except
    end;
    FSession := nil;
  end;
  FreeAndNil(FQueueFilePaths);
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TScriptExecutorFrame.Initialize(
  const AFactory: IDatabaseProviderFactory;
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string
);
begin
  FFactory := AFactory;
  FActiveProfileId := AInitialProfileId;
  FQueueFilePaths := TStringList.Create;
  FLoadedFilePath := '';
  FIsBusy := False;
  FCancelRequested := False;
  FWorker := nil;
  FCancelWorker := nil;
  FExecStartTick := 0;
  FExecutedCount := 0;
  FTotalStatements := 0;
  FBaseTabCaption := '';
  SetLength(FOutcomes, 0);
  FEditorSplitRatio := 0.45;
  FIsAdjustingSplit := False;
  FUpdatingLayout := False;

  {$IFDEF UNIX}
  SynEdit1.Font.Name := 'Monospace';
  memLog.Font.Name := 'Monospace';
  {$ENDIF}

  SynSQLSyn1.Enabled := True;
  SynEdit1.Highlighter := SynSQLSyn1;
  SynEdit1.Keystrokes.ResetDefaults;

  if FLinkCtrl = nil then
    FLinkCtrl := TSqlObjectLinkController.Create(
      Self,
      SynEdit1,
      SynSQLSyn1,
      @SelectedProfile,
      @ExecuteCompletionMetadataQuery,
      @HandleOpenObjectLink
    );
  FLinkCtrl.ClearCache;

  if FCompletionCtrl = nil then
  begin
    FCompletionCtrl := TSqlCompletionController.Create(
      Self,
      SynEdit1,
      @SelectedProfile,
      @ExecuteCompletionMetadataQuery
    );
    FCompletionCtrl.IncludeProceduralKeywords := True;
  end;

  ConfigureGrid;
  RefreshConnections(AConnections);
  UpdateTransactionUI;
  UpdateQueueTitleAndButtons;
  UpdateLayouts;
end;

procedure TScriptExecutorFrame.ConfigureGrid;
begin
  grdStatements.ColCount := 8;
  grdStatements.RowCount := 1;
  grdStatements.FixedCols := 0;
  grdStatements.FixedRows := 1;
  grdStatements.Cells[0, 0] := '#';
  grdStatements.Cells[1, 0] := 'Arquivo';
  grdStatements.Cells[2, 0] := 'Linha';
  grdStatements.Cells[3, 0] := 'Status';
  grdStatements.Cells[4, 0] := 'Tempo';
  grdStatements.Cells[5, 0] := 'Afetadas';
  grdStatements.Cells[6, 0] := 'Comando';
  grdStatements.Cells[7, 0] := 'Mensagem / Erro';

  grdStatements.ColWidths[0] := 42;
  grdStatements.ColWidths[1] := 130;
  grdStatements.ColWidths[2] := 50;
  grdStatements.ColWidths[3] := 75;
  grdStatements.ColWidths[4] := 70;
  grdStatements.ColWidths[5] := 70;
  grdStatements.ColWidths[6] := 280;
  grdStatements.ColWidths[7] := 320;
end;

procedure TScriptExecutorFrame.RefreshConnections(const AConnections: TConnectionProfileList);
var
  Item, Cloned: TConnectionProfile;
  Idx, SelectedIdx: Integer;
  TargetId: string;
begin
  TargetId := FActiveProfileId;
  if (TargetId = '') and (SelectedProfile <> nil) then
    TargetId := SelectedProfile.Id;

  FreeAndNil(FProfiles);
  FProfiles := TConnectionProfileList.Create(True);

  cbConnection.Items.BeginUpdate;
  try
    cbConnection.Items.Clear;
    SelectedIdx := -1;
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
        if (TargetId <> '') and SameText(Cloned.Id, TargetId) then
          SelectedIdx := Idx;
      end;
    end;

    if (SelectedIdx = -1) and (cbConnection.Items.Count > 0) then
      SelectedIdx := 0;

    cbConnection.ItemIndex := SelectedIdx;
    if SelectedProfile <> nil then
    begin
      FActiveProfileId := SelectedProfile.Id;
      ApplyHighlighterForProfile(SelectedProfile);
    end;
  finally
    cbConnection.Items.EndUpdate;
  end;
end;

procedure TScriptExecutorFrame.SetScriptText(const AScriptText: string);
begin
  SynEdit1.Lines.Text := AScriptText;
end;

function TScriptExecutorFrame.ActiveProfileId: string;
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    Result := Profile.Id
  else
    Result := FActiveProfileId;
end;

function TScriptExecutorFrame.IsBusy: Boolean;
begin
  Result := FIsBusy;
end;

function TScriptExecutorFrame.IsConnected: Boolean;
begin
  Result := FIsBusy or ((FSession <> nil) and FSession.IsConnected);
end;

function TScriptExecutorFrame.HasActiveTransaction: Boolean;
begin
  Result := (not FIsBusy) and (FSession <> nil) and FSession.IsConnected and FSession.InTransaction;
end;

function TScriptExecutorFrame.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection.ItemIndex >= 0) and (cbConnection.ItemIndex < cbConnection.Items.Count) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

function TScriptExecutorFrame.SelectedCommitMode: TScriptCommitMode;
begin
  case cbCommitMode.ItemIndex of
    1: Result := scmCommitPerStatement;
    2: Result := scmCommitEveryN;
    3: Result := scmCommitPerFile;
    4: Result := scmManual;
  else
    Result := scmSingleTransaction;
  end;
end;

function TScriptExecutorFrame.SelectedErrorPolicy: TScriptErrorPolicy;
begin
  case cbErrorPolicy.ItemIndex of
    1: Result := sepAskUser;
    2: Result := sepIgnoreErrors;
  else
    Result := sepStopOnError;
  end;
end;

procedure TScriptExecutorFrame.CollectCheckedQueuePaths(const ATarget: TStrings);
var
  I: Integer;
begin
  ATarget.Clear;
  if FQueueFilePaths = nil then
    Exit;
  for I := 0 to Min(clbFiles.Items.Count, FQueueFilePaths.Count) - 1 do
  begin
    if clbFiles.Checked[I] then
      ATarget.Add(FQueueFilePaths[I]);
  end;
end;

procedure TScriptExecutorFrame.UpdateQueueTitleAndButtons;
var
  CheckedCount, I, TotalCount: Integer;
begin
  TotalCount := clbFiles.Items.Count;
  CheckedCount := 0;
  for I := 0 to TotalCount - 1 do
    if clbFiles.Checked[I] then
      Inc(CheckedCount);

  if TotalCount = 0 then
    lblQueueTitle.Caption := 'Fila de Scripts (.sql)'
  else
    lblQueueTitle.Caption := Format('Fila (%d/%d marcados)', [CheckedCount, TotalCount]);

  btnQueueRemove.Enabled := (not FIsBusy) and (clbFiles.ItemIndex >= 0);
  btnQueueUp.Enabled := (not FIsBusy) and (clbFiles.ItemIndex > 0);
  btnQueueDown.Enabled := (not FIsBusy) and (clbFiles.ItemIndex >= 0) and (clbFiles.ItemIndex < TotalCount - 1);
  btnQueueClear.Enabled := (not FIsBusy) and (TotalCount > 0);
  btnLoadQueueToEditor.Enabled := (not FIsBusy) and (CheckedCount > 0);
end;

procedure TScriptExecutorFrame.SwapQueueItems(const AIdxA, AIdxB: Integer);
var
  TmpLabel, TmpPath: string;
  TmpChecked: Boolean;
begin
  if (AIdxA < 0) or (AIdxB < 0) or (AIdxA >= clbFiles.Items.Count) or
     (AIdxB >= clbFiles.Items.Count) or (AIdxA = AIdxB) then
    Exit;

  TmpLabel := clbFiles.Items[AIdxA];
  TmpChecked := clbFiles.Checked[AIdxA];
  TmpPath := FQueueFilePaths[AIdxA];

  clbFiles.Items[AIdxA] := clbFiles.Items[AIdxB];
  clbFiles.Checked[AIdxA] := clbFiles.Checked[AIdxB];
  FQueueFilePaths[AIdxA] := FQueueFilePaths[AIdxB];

  clbFiles.Items[AIdxB] := TmpLabel;
  clbFiles.Checked[AIdxB] := TmpChecked;
  FQueueFilePaths[AIdxB] := TmpPath;
end;

procedure TScriptExecutorFrame.OpenFileIntoEditor(const AFilePath: string);
var
  SR: TSearchRec;
  FileSizeBytes: Int64;
begin
  if not FileExists(AFilePath) then
  begin
    MessageDlg('Arquivo não encontrado', Format('O arquivo "%s" não existe mais.', [AFilePath]), mtWarning, [mbOK], 0);
    Exit;
  end;

  FileSizeBytes := 0;
  if FindFirst(AFilePath, faAnyFile, SR) = 0 then
  begin
    FileSizeBytes := SR.Size;
    FindClose(SR);
  end;

  if FileSizeBytes > MAX_EDITOR_DIRECT_LOAD_BYTES then
  begin
    if MessageDlg(
         'Arquivo Grande',
         Format('O arquivo "%s" tem %.1f MB. Carregar no editor pode consumir bastante memória; recomenda-se executar pela fila direto do disco. Deseja abrir mesmo assim?',
           [ExtractFileName(AFilePath), FileSizeBytes / (1024 * 1024)]),
         mtConfirmation,
         [mbYes, mbNo],
         0
       ) <> mrYes then
      Exit;
  end;

  SynEdit1.Lines.LoadFromFile(AFilePath);
  FLoadedFilePath := AFilePath;
  LogMessage('Arquivo carregado no editor: ' + AFilePath);
end;

procedure TScriptExecutorFrame.ApplyHighlighterForProfile(const AProfile: TConnectionProfile);
begin
  if AProfile = nil then
    Exit;
  if AProfile.DatabaseType = dtPostgreSQL then
    SynSQLSyn1.SQLDialect := sqlPostgres
  else
    SynSQLSyn1.SQLDialect := sqlFirebird40;
end;

procedure TScriptExecutorFrame.LogMessage(const AMsg: string);
begin
  memLog.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss', Now), AMsg]));
end;

procedure TScriptExecutorFrame.Resize;
begin
  inherited Resize;
  AdjustSplitHeight;
end;

procedure TScriptExecutorFrame.PanelsResize(Sender: TObject);
begin
  UpdateLayouts;
end;

procedure TScriptExecutorFrame.Splitter1Moved(Sender: TObject);
var
  Avail: Integer;
begin
  if FIsAdjustingSplit then
    Exit;
  Avail := ClientHeight - pnlToolbar.Height - Splitter1.Height;
  if Avail > 250 then
  begin
    FEditorSplitRatio := pnlTopArea.Height / Avail;
    if FEditorSplitRatio < 0.15 then
      FEditorSplitRatio := 0.15
    else if FEditorSplitRatio > 0.85 then
      FEditorSplitRatio := 0.85;
  end;
end;

procedure TScriptExecutorFrame.UpdateLayouts;
begin
  if FUpdatingLayout then
    Exit;
  FUpdatingLayout := True;
  try
    if pnlToolbar <> nil then
    begin
      pnlToolbar.ReAlign;
      pnlToolbar.InvalidatePreferredSize;
      pnlToolbar.AdjustSize;
    end;
    if pnlQueueBar <> nil then
    begin
      pnlQueueBar.ReAlign;
      pnlQueueBar.InvalidatePreferredSize;
      pnlQueueBar.AdjustSize;
    end;
    if pnlLogBar <> nil then
    begin
      pnlLogBar.ReAlign;
      pnlLogBar.InvalidatePreferredSize;
      pnlLogBar.AdjustSize;
    end;
  finally
    FUpdatingLayout := False;
  end;
  AdjustSplitHeight;
end;

procedure TScriptExecutorFrame.AdjustSplitHeight;
var
  Avail, NewHeight: Integer;
begin
  if FIsAdjustingSplit or (pnlTopArea = nil) or (pnlToolbar = nil) or (Splitter1 = nil) then
    Exit;

  if FEditorSplitRatio <= 0 then
    FEditorSplitRatio := 0.45;

  Avail := ClientHeight - pnlToolbar.Height - Splitter1.Height;
  if Avail > 250 then
  begin
    NewHeight := Round(Avail * FEditorSplitRatio);
    if NewHeight < 120 then
      NewHeight := 120
    else if NewHeight > Avail - 140 then
      NewHeight := Avail - 140;

    if pnlTopArea.Height <> NewHeight then
    begin
      FIsAdjustingSplit := True;
      try
        pnlTopArea.Height := NewHeight;
      finally
        FIsAdjustingSplit := False;
      end;
    end;
  end;
end;

procedure TScriptExecutorFrame.UpdateTransactionUI;
begin
  if FIsBusy then
  begin
    btnCommit.Enabled := False;
    btnRollback.Enabled := False;
    Exit;
  end;

  if (FSession = nil) or (not FSession.IsConnected) then
  begin
    btnCommit.Enabled := False;
    btnRollback.Enabled := False;
    lblTxStatus.Caption := 'Desconectado';
    lblTxStatus.Font.Color := clGrayText;
  end
  else if FSession.InTransaction then
  begin
    btnCommit.Enabled := True;
    btnRollback.Enabled := True;
    lblTxStatus.Caption := 'Em Transação';
    lblTxStatus.Font.Color := clMaroon;
  end
  else
  begin
    btnCommit.Enabled := False;
    btnRollback.Enabled := False;
    lblTxStatus.Caption := 'Conectado';
    lblTxStatus.Font.Color := clGreen;
  end;
  UpdateLayouts;
end;

function TScriptExecutorFrame.BaseTabCaption: string;
const
  RunningSuffix = ' (Executando...)';
var
  Cap: string;
begin
  if Trim(FBaseTabCaption) <> '' then
    Result := FBaseTabCaption
  else if Parent is TTabSheet then
  begin
    Cap := StripEditorTabCloseSuffix(TTabSheet(Parent).Caption);
    if Copy(Cap, Length(Cap) - Length(RunningSuffix) + 1, Length(RunningSuffix)) = RunningSuffix then
      Result := Copy(Cap, 1, Length(Cap) - Length(RunningSuffix))
    else
      Result := Cap;
  end
  else
    Result := '';
end;

function TScriptExecutorFrame.FormatElapsedSeconds: string;
var
  ElapsedMs: Int64;
begin
  ElapsedMs := Int64(GetTickCount64 - FExecStartTick);
  Result := FormatFloat('0.0', ElapsedMs / 1000.0) + 's';
end;

function TScriptExecutorFrame.FormatThroughputText: string;
var
  Sec: Double;
begin
  Sec := Max(0.1, (GetTickCount64 - FExecStartTick) / 1000.0);
  Result := FormatFloat('0.0', FExecutedCount / Sec) + ' cmd/s';
end;

procedure TScriptExecutorFrame.SetRunningState(const ARunning: Boolean; const ATotalStatements: Integer);
begin
  FIsBusy := ARunning;
  cbConnection.Enabled := not ARunning;
  btnExecuteScript.Enabled := not ARunning;
  btnExecuteFromCursor.Enabled := not ARunning;
  btnExecuteSelection.Enabled := not ARunning;
  btnPauseResume.Enabled := ARunning;
  btnPauseResume.Caption := 'Pausar';
  btnCancel.Enabled := ARunning and (not FCancelRequested);
  cbCommitMode.Enabled := not ARunning;
  edtCommitEveryN.Enabled := not ARunning;
  cbErrorPolicy.Enabled := not ARunning;
  btnOpenFile.Enabled := not ARunning;
  btnSaveFile.Enabled := not ARunning;
  btnClearScript.Enabled := not ARunning;
  btnQueueAdd.Enabled := not ARunning;
  clbFiles.Enabled := not ARunning;
  chkRunQueueDirect.Enabled := not ARunning;
  chkLogToFile.Enabled := not ARunning;
  edtLogFile.Enabled := (not ARunning) and chkLogToFile.Checked;
  btnBrowseLogFile.Enabled := (not ARunning) and chkLogToFile.Checked;

  if ARunning then
  begin
    FBaseTabCaption := BaseTabCaption;
    FCancelRequested := False;
    FExecStartTick := GetTickCount64;
    FExecutedCount := 0;
    FTotalStatements := ATotalStatements;
    pbProgress.Min := 0;
    pbProgress.Max := Max(1, ATotalStatements);
    pbProgress.Position := 0;
    if Parent is TTabSheet then
    begin
      if FBaseTabCaption <> '' then
        SetTabSheetTitle(TTabSheet(Parent), FBaseTabCaption + ' (Executando...)')
      else
        SetTabSheetTitle(TTabSheet(Parent), 'Executando...');
    end;
    lblTxStatus.Font.Color := clNavy;
    lblTxStatus.Caption := 'Executando... 0.0s';
    lblProgress.Caption := Format('Executando: 0/%d comando(s) | 0.0s', [ATotalStatements]);
    tmrElapsed.Enabled := True;
  end
  else
  begin
    if tmrElapsed <> nil then
      tmrElapsed.Enabled := False;
    FWorker := nil;
    FCancelRequested := False;
    if (Parent is TTabSheet) and (FBaseTabCaption <> '') then
      SetTabSheetTitle(TTabSheet(Parent), FBaseTabCaption);
    FBaseTabCaption := '';
    UpdateTransactionUI;
  end;
  UpdateQueueTitleAndButtons;
  UpdateLayouts;
end;

procedure TScriptExecutorFrame.cbConnectionChange(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  if FIsBusy then
    Exit;
  Profile := SelectedProfile;
  if (Profile <> nil) and SameText(Profile.Id, FActiveProfileId) then
    Exit;

  if FSession <> nil then
  begin
    try
      if FSession.InTransaction then
        FSession.Rollback;
      FSession.Disconnect;
    except
    end;
    FSession := nil;
  end;

  if Profile <> nil then
  begin
    FActiveProfileId := Profile.Id;
    ApplyHighlighterForProfile(Profile);
    ClearMetadataCache;
    LogMessage('Conexão alterada para: ' + Profile.Name);
  end
  else
    FActiveProfileId := '';

  UpdateTransactionUI;
end;

procedure TScriptExecutorFrame.cbCommitModeChange(Sender: TObject);
begin
  edtCommitEveryN.Visible := (cbCommitMode.ItemIndex = 2);
  UpdateLayouts;
end;

procedure TScriptExecutorFrame.chkLogToFileChange(Sender: TObject);
begin
  edtLogFile.Enabled := (not FIsBusy) and chkLogToFile.Checked;
  btnBrowseLogFile.Enabled := (not FIsBusy) and chkLogToFile.Checked;
  if chkLogToFile.Checked and (Trim(edtLogFile.Text) = '') then
    edtLogFile.Text := ExtractFilePath(ParamStr(0)) +
      'script_exec_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.log';
end;

procedure TScriptExecutorFrame.btnBrowseLogFileClick(Sender: TObject);
begin
  if Trim(edtLogFile.Text) <> '' then
    dlgSaveLog.FileName := Trim(edtLogFile.Text);
  if dlgSaveLog.Execute then
    edtLogFile.Text := dlgSaveLog.FileName;
end;

procedure TScriptExecutorFrame.StartScriptExecution(const AMode: Integer);
var
  Profile: TConnectionProfile;
  ScriptText, SourceLabel, BaseDir: string;
  LineOffset, I, StartY: Integer;
  CheckedFiles, TempLines: TStringList;
  Stmts: TParsedScriptStatementArray;
  Opts: TScriptExecutionOptions;
  Provider: IDatabaseProvider;
begin
  if FIsBusy then
  begin
    LogMessage('Já existe uma execução de script em andamento nesta aba.');
    Exit;
  end;

  Profile := SelectedProfile;
  if (Profile = nil) or (FFactory = nil) then
  begin
    MessageDlg('Aviso', 'Selecione uma conexão antes de executar.', mtInformation, [mbOK], 0);
    Exit;
  end;

  CheckedFiles := TStringList.Create;
  try
    CollectCheckedQueuePaths(CheckedFiles);

    try
      if (AMode = 0) and chkRunQueueDirect.Checked and (CheckedFiles.Count > 0) then
      begin
        Stmts := ParseSqlFilesBatch(CheckedFiles, Profile.DatabaseType, True);
      end
      else if AMode = 1 then
      begin
        StartY := Max(1, SynEdit1.CaretY);
        if StartY > SynEdit1.Lines.Count then
          Exit;
        TempLines := TStringList.Create;
        try
          for I := StartY - 1 to SynEdit1.Lines.Count - 1 do
            TempLines.Add(SynEdit1.Lines[I]);
          ScriptText := TempLines.Text;
        finally
          TempLines.Free;
        end;
        LineOffset := StartY - 1;
        if FLoadedFilePath <> '' then
        begin
          SourceLabel := ExtractFileName(FLoadedFilePath);
          BaseDir := ExtractFilePath(FLoadedFilePath);
        end
        else
        begin
          SourceLabel := 'Editor';
          BaseDir := '';
        end;
        Stmts := ParseSqlScriptWithLines(ScriptText, Profile.DatabaseType, SourceLabel, BaseDir, True, 0);
        for I := 0 to High(Stmts) do
        begin
          if SameText(Stmts[I].SourceFile, SourceLabel) then
          begin
            Inc(Stmts[I].StartLine, LineOffset);
            Inc(Stmts[I].EndLine, LineOffset);
          end;
        end;
      end
      else if (AMode = 2) and SynEdit1.SelAvail then
      begin
        ScriptText := SynEdit1.SelText;
        LineOffset := Max(0, Min(SynEdit1.BlockBegin.Y, SynEdit1.BlockEnd.Y) - 1);
        if FLoadedFilePath <> '' then
        begin
          SourceLabel := ExtractFileName(FLoadedFilePath);
          BaseDir := ExtractFilePath(FLoadedFilePath);
        end
        else
        begin
          SourceLabel := 'Editor';
          BaseDir := '';
        end;
        Stmts := ParseSqlScriptWithLines(ScriptText, Profile.DatabaseType, SourceLabel, BaseDir, True, 0);
        for I := 0 to High(Stmts) do
        begin
          if SameText(Stmts[I].SourceFile, SourceLabel) then
          begin
            Inc(Stmts[I].StartLine, LineOffset);
            Inc(Stmts[I].EndLine, LineOffset);
          end;
        end;
      end
      else
      begin
        if (AMode = 0) and chkRunQueueDirect.Checked and (CheckedFiles.Count = 0) and
           (Trim(SynEdit1.Lines.Text) = '') then
        begin
          MessageDlg('Aviso', 'Adicione e marque pelo menos um arquivo .sql na fila ou digite SQL no editor.',
            mtInformation, [mbOK], 0);
          Exit;
        end;
        ScriptText := SynEdit1.Lines.Text;
        if Trim(ScriptText) = '' then
        begin
          if CheckedFiles.Count > 0 then
            Stmts := ParseSqlFilesBatch(CheckedFiles, Profile.DatabaseType, True)
          else
          begin
            LogMessage('Nenhum comando SQL para executar.');
            Exit;
          end;
        end
        else
        begin
          if FLoadedFilePath <> '' then
          begin
            SourceLabel := ExtractFileName(FLoadedFilePath);
            BaseDir := ExtractFilePath(FLoadedFilePath);
          end
          else
          begin
            SourceLabel := 'Editor';
            BaseDir := '';
          end;
          Stmts := ParseSqlScriptWithLines(ScriptText, Profile.DatabaseType, SourceLabel, BaseDir, True, 0);
        end;
      end;
    except
      on E: Exception do
      begin
        LogMessage('ERRO ao analisar script: ' + E.Message);
        MessageDlg('Erro no Script', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    CheckedFiles.Free;
  end;

  if Length(Stmts) = 0 then
  begin
    LogMessage('Nenhum comando SQL executável encontrado (apenas comentários ou diretivas).');
    Exit;
  end;

  if FSession = nil then
  begin
    Provider := FFactory.GetProvider(Profile.DatabaseType);
    FSession := Provider.CreateSession(Profile);
  end;

  SetLength(FOutcomes, 0);
  ConfigureGrid;
  pgOutput.ActivePage := tsStatements;

  Opts := DefaultScriptExecutionOptions;
  Opts.CommitMode := SelectedCommitMode;
  Opts.CommitEveryN := Max(1, StrToIntDef(Trim(edtCommitEveryN.Text), 1000));
  Opts.ErrorPolicy := SelectedErrorPolicy;
  if chkLogToFile.Checked then
    Opts.LogToFilePath := Trim(edtLogFile.Text)
  else
    Opts.LogToFilePath := '';

  LogMessage(Format('Iniciando Script Executive em "%s": %d comando(s) | %s | Erro: %s',
    [Profile.Name, Length(Stmts), ScriptCommitModeToStr(Opts.CommitMode),
     ScriptErrorPolicyToStr(Opts.ErrorPolicy)]));

  SetRunningState(True, Length(Stmts));
  FWorker := TScriptExecutorWorker.Create(
    FSession,
    Profile.DatabaseType,
    Stmts,
    Opts,
    @HandleScriptProgress,
    @HandleScriptCompleted,
    @HandleErrorPrompt
  );
  FWorker.Start;
end;

procedure TScriptExecutorFrame.HandleScriptProgress(
  const ANewOutcomes: TScriptStatementOutcomeArray;
  const AExecutedCount, ATotalCount: Integer
);
var
  I, OldLen, RowIdx: Integer;
  O: TScriptStatementOutcome;
  StatusStr, LocStr: string;
begin
  if Length(ANewOutcomes) = 0 then
    Exit;

  OldLen := Length(FOutcomes);
  SetLength(FOutcomes, OldLen + Length(ANewOutcomes));
  grdStatements.RowCount := Length(FOutcomes) + 1;

  for I := 0 to High(ANewOutcomes) do
  begin
    O := ANewOutcomes[I];
    FOutcomes[OldLen + I] := O;
    RowIdx := OldLen + I + 1;

    if O.Kind = sskCommit then
      StatusStr := 'COMMIT'
    else if O.Kind = sskRollback then
      StatusStr := 'ROLLBACK'
    else
      StatusStr := ScriptStatementStatusToStr(O.Status);

    grdStatements.Cells[0, RowIdx] := IntToStr(O.Index);
    grdStatements.Cells[1, RowIdx] := O.SourceFile;
    grdStatements.Cells[2, RowIdx] := IntToStr(O.StartLine);
    grdStatements.Cells[3, RowIdx] := StatusStr;
    grdStatements.Cells[4, RowIdx] := Format('%d ms', [O.ElapsedMs]);
    grdStatements.Cells[5, RowIdx] := IntToStr(O.RowsAffected);
    grdStatements.Cells[6, RowIdx] := O.SqlPreview;
    grdStatements.Cells[7, RowIdx] := O.MessageText;

    if O.SourceFile <> '' then
      LocStr := Format('%s:%d', [O.SourceFile, O.StartLine])
    else
      LocStr := Format('Linha %d', [O.StartLine]);

    if O.Status = sssError then
      LogMessage(Format('[ERRO] #%d (%s): %s -> %s', [O.Index, LocStr, O.SqlPreview, O.MessageText]))
    else if O.ElapsedMs >= 50 then
      LogMessage(Format('[%s] #%d (%s | %d ms): %s', [StatusStr, O.Index, LocStr, O.ElapsedMs, O.SqlPreview]));
  end;

  FExecutedCount := AExecutedCount;
  FTotalStatements := ATotalCount;
  pbProgress.Max := Max(1, ATotalCount);
  pbProgress.Position := Min(ATotalCount, AExecutedCount);
  lblProgress.Caption := Format('Executando: %d/%d (%d%% | %s | %s)',
    [AExecutedCount, ATotalCount, Round(100 * AExecutedCount / Max(1, ATotalCount)),
     FormatThroughputText, FormatElapsedSeconds]);

  if grdStatements.RowCount > 1 then
    grdStatements.Row := grdStatements.RowCount - 1;
end;

procedure TScriptExecutorFrame.HandleErrorPrompt(
  const AOutcome: TScriptStatementOutcome;
  out AAction: TScriptErrorAction
);
var
  LocInfo, PromptText: string;
  DlgRes: TModalResult;
begin
  if AOutcome.SourceFile <> '' then
    LocInfo := Format('%s (linha %d)', [AOutcome.SourceFile, AOutcome.StartLine])
  else
    LocInfo := Format('Linha %d', [AOutcome.StartLine]);

  PromptText := Format(
    'Erro ao executar comando #%d em %s:%s%s%s%sErro: %s%sO que deseja fazer?',
    [AOutcome.Index, LocInfo, LineEnding, LineEnding,
     AOutcome.SqlPreview, LineEnding + LineEnding,
     AOutcome.MessageText, LineEnding + LineEnding]
  );

  DlgRes := QuestionDlg(
    'Script Executive — Erro no Comando',
    PromptText,
    mtError,
    [mrAbort, 'Abortar Script', mrIgnore, 'Ignorar e Continuar', mrAll, 'Ignorar Todos'],
    0
  );

  case DlgRes of
    mrIgnore: AAction := seaIgnoreOne;
    mrAll: AAction := seaIgnoreAll;
  else
    AAction := seaAbort;
  end;
end;

procedure TScriptExecutorFrame.JumpToLocation(const ASourceFile: string; const ALineNum: Integer);
var
  I: Integer;
  CurLoadedName: string;
begin
  if ALineNum <= 0 then
    Exit;

  CurLoadedName := ExtractFileName(FLoadedFilePath);
  if (ASourceFile <> '') and (not SameText(ASourceFile, 'Editor')) and
     (not SameText(ASourceFile, CurLoadedName)) and (FQueueFilePaths <> nil) then
  begin
    for I := 0 to FQueueFilePaths.Count - 1 do
    begin
      if SameText(ExtractFileName(FQueueFilePaths[I]), ASourceFile) then
      begin
        OpenFileIntoEditor(FQueueFilePaths[I]);
        Break;
      end;
    end;
  end;

  SynEdit1.CaretXY := Point(1, Min(ALineNum, Max(1, SynEdit1.Lines.Count)));
  SynEdit1.TopLine := Max(1, ALineNum - 3);
  if SynEdit1.CanFocus then
    SynEdit1.SetFocus;
end;

procedure TScriptExecutorFrame.HandleScriptCompleted(
  const AWorker: TObject;
  const ASummary: TScriptExecutionSummary
);
var
  ErrLoc: string;
begin
  if (FWorker <> nil) and (AWorker <> FWorker) then
    Exit;

  SetRunningState(False, ASummary.TotalStatements);
  pbProgress.Max := Max(1, ASummary.TotalStatements);
  pbProgress.Position := Min(ASummary.TotalStatements, ASummary.ExecutedCount);

  if ASummary.FirstErrorLine > 0 then
  begin
    if ASummary.FirstErrorFile <> '' then
      ErrLoc := Format('%s linha %d', [ASummary.FirstErrorFile, ASummary.FirstErrorLine])
    else
      ErrLoc := Format('linha %d', [ASummary.FirstErrorLine]);
    lblProgress.Caption := Format('%s (1º erro em %s - duplo clique na grade)',
      [ASummary.FinalMessage, ErrLoc]);
  end
  else
    lblProgress.Caption := ASummary.FinalMessage;

  LogMessage(ASummary.FinalMessage);
  if ASummary.CommittedAtEnd then
    LogMessage('COMMIT final executado com sucesso.')
  else if ASummary.RolledBackOnError then
    LogMessage('ROLLBACK automático executado após erro/cancelamento.');

  if (ASummary.ErrorCount > 0) and (ASummary.FirstErrorLine > 0) then
    JumpToLocation(ASummary.FirstErrorFile, ASummary.FirstErrorLine);
end;

procedure TScriptExecutorFrame.HandleCancelCompleted(
  const AWorker: TCancelQueryWorker;
  const ASuccess: Boolean;
  const AMessage: string
);
begin
  if FCancelWorker = AWorker then
    FCancelWorker := nil;
  if Trim(AMessage) <> '' then
    LogMessage(AMessage);
  if (not ASuccess) and FIsBusy then
  begin
    FCancelRequested := False;
    btnCancel.Enabled := True;
  end;
end;

procedure TScriptExecutorFrame.RequestCancel;
begin
  if (not FIsBusy) or FCancelRequested then
    Exit;

  FCancelRequested := True;
  btnCancel.Enabled := False;
  btnPauseResume.Enabled := False;
  if FWorker <> nil then
    FWorker.MarkCancelRequested;

  lblTxStatus.Caption := 'Cancelando... ' + FormatElapsedSeconds;
  lblProgress.Caption := Format('Cancelando script em segundo plano (%d/%d)... %s',
    [FExecutedCount, FTotalStatements, FormatElapsedSeconds]);
  LogMessage('Solicitando cancelamento do script...');

  if FCancelWorker <> nil then
  begin
    FCancelWorker.Detach;
    FCancelWorker := nil;
  end;
  if FSession <> nil then
  begin
    FCancelWorker := TCancelQueryWorker.Create(FSession, @HandleCancelCompleted);
    FCancelWorker.Start;
  end;
end;

procedure TScriptExecutorFrame.DetachAndCancel;
begin
  if tmrElapsed <> nil then
    tmrElapsed.Enabled := False;
  if FCancelWorker <> nil then
  begin
    FCancelWorker.Detach;
    FCancelWorker := nil;
  end;
  if FWorker <> nil then
  begin
    FWorker.DetachAndCancel;
    FWorker := nil;
    FSession := nil;
  end;
  FIsBusy := False;
  FCancelRequested := False;
end;

procedure TScriptExecutorFrame.DisconnectSession;
var
  WasConnected: Boolean;
begin
  if FIsBusy then
  begin
    DetachAndCancel;
    SetRunningState(False, FTotalStatements);
    lblProgress.Caption := 'Execução cancelada e conexão desconectada.';
    LogMessage('Execução cancelada e conexão desconectada.');
    Exit;
  end;

  WasConnected := False;
  if FSession <> nil then
  begin
    WasConnected := FSession.IsConnected;
    try
      if FSession.InTransaction then
        FSession.Rollback;
      FSession.Disconnect;
    except
    end;
    FSession := nil;
  end;

  UpdateTransactionUI;
  if WasConnected then
    LogMessage('Conexão desconectada.');
end;

procedure TScriptExecutorFrame.btnExecuteScriptClick(Sender: TObject);
begin
  StartScriptExecution(0);
end;

procedure TScriptExecutorFrame.btnExecuteFromCursorClick(Sender: TObject);
begin
  StartScriptExecution(1);
end;

procedure TScriptExecutorFrame.btnExecuteSelectionClick(Sender: TObject);
begin
  StartScriptExecution(2);
end;

procedure TScriptExecutorFrame.btnPauseResumeClick(Sender: TObject);
var
  WillPause: Boolean;
begin
  if (not FIsBusy) or (FWorker = nil) then
    Exit;
  WillPause := not FWorker.IsPaused;
  FWorker.SetPaused(WillPause);
  if WillPause then
  begin
    btnPauseResume.Caption := 'Continuar';
    lblTxStatus.Caption := 'Pausado | ' + FormatElapsedSeconds;
    LogMessage('Execução pausada pelo usuário.');
  end
  else
  begin
    btnPauseResume.Caption := 'Pausar';
    lblTxStatus.Caption := 'Executando... ' + FormatElapsedSeconds;
    LogMessage('Execução retomada.');
  end;
end;

procedure TScriptExecutorFrame.btnCancelClick(Sender: TObject);
begin
  RequestCancel;
end;

procedure TScriptExecutorFrame.btnCommitClick(Sender: TObject);
begin
  if FIsBusy or (FSession = nil) then
    Exit;
  try
    FSession.Commit;
    LogMessage('Transação confirmada (COMMIT).');
  except
    on E: Exception do
      LogMessage('ERRO ao executar COMMIT: ' + E.Message);
  end;
  UpdateTransactionUI;
end;

procedure TScriptExecutorFrame.btnRollbackClick(Sender: TObject);
begin
  if FIsBusy or (FSession = nil) then
    Exit;
  try
    FSession.Rollback;
    LogMessage('Transação desfeita (ROLLBACK).');
  except
    on E: Exception do
      LogMessage('ERRO ao executar ROLLBACK: ' + E.Message);
  end;
  UpdateTransactionUI;
end;

procedure TScriptExecutorFrame.btnOpenFileClick(Sender: TObject);
begin
  if FIsBusy then
    Exit;
  if dlgOpenSql.Execute then
    OpenFileIntoEditor(dlgOpenSql.FileName);
end;

procedure TScriptExecutorFrame.btnSaveFileClick(Sender: TObject);
begin
  if FLoadedFilePath <> '' then
    dlgSaveSql.FileName := FLoadedFilePath;
  if dlgSaveSql.Execute then
  begin
    SynEdit1.Lines.SaveToFile(dlgSaveSql.FileName);
    FLoadedFilePath := dlgSaveSql.FileName;
    LogMessage('Script salvo: ' + dlgSaveSql.FileName);
  end;
end;

procedure TScriptExecutorFrame.btnClearScriptClick(Sender: TObject);
begin
  if FIsBusy then
    Exit;
  if (Trim(SynEdit1.Lines.Text) <> '') and
     (MessageDlg('Limpar Script', 'Deseja limpar o conteúdo do editor?',
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  SynEdit1.ClearAll;
  FLoadedFilePath := '';
  SetLength(FOutcomes, 0);
  ConfigureGrid;
  pbProgress.Position := 0;
  lblProgress.Caption := 'Editor limpo.';
end;

procedure TScriptExecutorFrame.btnQueueAddClick(Sender: TObject);
var
  I, NewIdx, AddedCount: Integer;
  SortedFiles: TStringList;
  FPath: string;
begin
  if FIsBusy or (not dlgAddSqlFiles.Execute) then
    Exit;

  SortedFiles := TStringList.Create;
  try
    SortedFiles.Assign(dlgAddSqlFiles.Files);
    if SortedFiles.Count > 1 then
      SortedFiles.Sort;

    AddedCount := 0;
    for I := 0 to SortedFiles.Count - 1 do
    begin
      FPath := SortedFiles[I];
      if FQueueFilePaths.IndexOf(FPath) >= 0 then
        Continue;
      FQueueFilePaths.Add(FPath);
      NewIdx := clbFiles.Items.Add(ExtractFileName(FPath));
      clbFiles.Checked[NewIdx] := True;
      clbFiles.ItemIndex := NewIdx;
      Inc(AddedCount);
    end;

    if (AddedCount > 0) and (Trim(SynEdit1.Lines.Text) = '') then
      chkRunQueueDirect.Checked := True;

    if AddedCount > 0 then
      LogMessage(Format('%d arquivo(s) adicionado(s) à fila de scripts.', [AddedCount]));
  finally
    SortedFiles.Free;
  end;
  UpdateQueueTitleAndButtons;
end;

procedure TScriptExecutorFrame.btnQueueRemoveClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FIsBusy then
    Exit;
  Idx := clbFiles.ItemIndex;
  if (Idx < 0) or (Idx >= clbFiles.Items.Count) then
    Exit;
  clbFiles.Items.Delete(Idx);
  if Idx < FQueueFilePaths.Count then
    FQueueFilePaths.Delete(Idx);
  if clbFiles.Items.Count > 0 then
    clbFiles.ItemIndex := Min(Idx, clbFiles.Items.Count - 1);
  UpdateQueueTitleAndButtons;
end;

procedure TScriptExecutorFrame.btnQueueUpClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FIsBusy then
    Exit;
  Idx := clbFiles.ItemIndex;
  if Idx > 0 then
  begin
    SwapQueueItems(Idx, Idx - 1);
    clbFiles.ItemIndex := Idx - 1;
    UpdateQueueTitleAndButtons;
  end;
end;

procedure TScriptExecutorFrame.btnQueueDownClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FIsBusy then
    Exit;
  Idx := clbFiles.ItemIndex;
  if (Idx >= 0) and (Idx < clbFiles.Items.Count - 1) then
  begin
    SwapQueueItems(Idx, Idx + 1);
    clbFiles.ItemIndex := Idx + 1;
    UpdateQueueTitleAndButtons;
  end;
end;

procedure TScriptExecutorFrame.btnQueueClearClick(Sender: TObject);
begin
  if FIsBusy then
    Exit;
  clbFiles.Items.Clear;
  FQueueFilePaths.Clear;
  chkRunQueueDirect.Checked := False;
  UpdateQueueTitleAndButtons;
end;

procedure TScriptExecutorFrame.clbFilesClickCheck(Sender: TObject);
begin
  UpdateQueueTitleAndButtons;
end;

procedure TScriptExecutorFrame.clbFilesDblClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FIsBusy then
    Exit;
  Idx := clbFiles.ItemIndex;
  if (Idx >= 0) and (Idx < FQueueFilePaths.Count) then
    OpenFileIntoEditor(FQueueFilePaths[Idx]);
  UpdateQueueTitleAndButtons;
end;

procedure TScriptExecutorFrame.btnLoadQueueToEditorClick(Sender: TObject);
var
  CheckedPaths, TempSL: TStringList;
  I: Integer;
  SR: TSearchRec;
  TotalBytes: Int64;
begin
  if FIsBusy then
    Exit;
  CheckedPaths := TStringList.Create;
  TempSL := TStringList.Create;
  try
    CollectCheckedQueuePaths(CheckedPaths);
    if CheckedPaths.Count = 0 then
      Exit;

    TotalBytes := 0;
    for I := 0 to CheckedPaths.Count - 1 do
    begin
      if FindFirst(CheckedPaths[I], faAnyFile, SR) = 0 then
      begin
        Inc(TotalBytes, SR.Size);
        FindClose(SR);
      end;
    end;
    if TotalBytes > MAX_EDITOR_DIRECT_LOAD_BYTES then
    begin
      if MessageDlg(
           'Arquivos Grandes',
           Format('O conjunto selecionado soma %.1f MB. Para arquivos grandes, recomenda-se marcar "Executar fila direto do disco". Deseja carregar mesmo assim?',
             [TotalBytes / (1024 * 1024)]),
           mtConfirmation,
           [mbYes, mbNo],
           0
         ) <> mrYes then
        Exit;
    end;

    SynEdit1.BeginUpdate(False);
    try
      for I := 0 to CheckedPaths.Count - 1 do
      begin
        TempSL.LoadFromFile(CheckedPaths[I]);
        if Trim(SynEdit1.Lines.Text) <> '' then
          SynEdit1.Lines.Add('');
        SynEdit1.Lines.Add('-- ========================================================');
        SynEdit1.Lines.Add('-- Arquivo: ' + ExtractFileName(CheckedPaths[I]));
        SynEdit1.Lines.Add('-- ========================================================');
        SynEdit1.Lines.AddStrings(TempSL);
      end;
    finally
      SynEdit1.EndUpdate;
    end;
    chkRunQueueDirect.Checked := False;
    LogMessage(Format('%d arquivo(s) mesclado(s) no editor.', [CheckedPaths.Count]));
  finally
    TempSL.Free;
    CheckedPaths.Free;
  end;
end;

procedure TScriptExecutorFrame.btnCopyLogClick(Sender: TObject);
begin
  Clipboard.AsText := memLog.Lines.Text;
end;

procedure TScriptExecutorFrame.btnSaveLogClick(Sender: TObject);
begin
  if dlgSaveLog.Execute then
  begin
    memLog.Lines.SaveToFile(dlgSaveLog.FileName);
    LogMessage('Log salvo: ' + dlgSaveLog.FileName);
  end;
end;

procedure TScriptExecutorFrame.btnClearLogClick(Sender: TObject);
begin
  memLog.Clear;
end;

procedure TScriptExecutorFrame.SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F9) and (Shift = []) then
  begin
    Key := 0;
    if not FIsBusy then
      StartScriptExecution(0);
  end
  else if (Key = VK_F9) and (Shift = [ssShift]) then
  begin
    Key := 0;
    if not FIsBusy then
      StartScriptExecution(1);
  end
  else if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    if not FIsBusy then
    begin
      if SynEdit1.SelAvail then
        StartScriptExecution(2)
      else
        StartScriptExecution(0);
    end;
  end;
end;

procedure TScriptExecutorFrame.grdStatementsDblClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := grdStatements.Row - 1;
  if (Idx >= 0) and (Idx <= High(FOutcomes)) then
    JumpToLocation(FOutcomes[Idx].SourceFile, FOutcomes[Idx].StartLine);
end;

procedure TScriptExecutorFrame.grdStatementsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Idx: Integer;
begin
  if (ssCtrl in Shift) and ((Key = VK_C) or (Key = Ord('C'))) then
  begin
    Key := 0;
    Idx := grdStatements.Row - 1;
    if (Idx >= 0) and (Idx <= High(FOutcomes)) then
      Clipboard.AsText := FOutcomes[Idx].SqlPreview + LineEnding + FOutcomes[Idx].MessageText;
  end;
end;

procedure TScriptExecutorFrame.grdStatementsPrepareCanvas(sender: TObject; aCol, aRow: Integer;
  aState: TGridDrawState);
var
  Idx: Integer;
begin
  if (aRow < 1) or (gdSelected in aState) then
    Exit;
  Idx := aRow - 1;
  if (Idx < 0) or (Idx > High(FOutcomes)) then
    Exit;

  if aCol = 3 then
  begin
    case FOutcomes[Idx].Status of
      sssOk:
        begin
          if FOutcomes[Idx].Kind <> sskSql then
            grdStatements.Canvas.Font.Color := clNavy
          else
            grdStatements.Canvas.Font.Color := clGreen;
        end;
      sssError:
        grdStatements.Canvas.Font.Color := clMaroon;
      sssCancelled:
        grdStatements.Canvas.Font.Color := clOlive;
    end;
    grdStatements.Canvas.Font.Style := [fsBold];
  end;
end;

procedure TScriptExecutorFrame.tmrElapsedTimer(Sender: TObject);
var
  ElapsedStr, CurFile, CurSql: string;
  CurIdx, CurTot: Integer;
begin
  if not FIsBusy then
  begin
    tmrElapsed.Enabled := False;
    Exit;
  end;
  ElapsedStr := FormatElapsedSeconds;
  if FCancelRequested then
  begin
    lblTxStatus.Caption := 'Cancelando... ' + ElapsedStr;
    Exit;
  end;
  if (FWorker <> nil) and FWorker.IsPaused then
  begin
    lblTxStatus.Caption := 'Pausado | ' + ElapsedStr;
    Exit;
  end;

  lblTxStatus.Caption := 'Executando... ' + ElapsedStr;
  if FWorker <> nil then
  begin
    FWorker.GetCurrentStatus(CurIdx, CurTot, CurFile, CurSql);
    if CurFile <> '' then
      lblProgress.Caption := Format('Executando #%d/%d [%s] (%s | %s): %s',
        [CurIdx, CurTot, CurFile, FormatThroughputText, ElapsedStr, CurSql])
    else
      lblProgress.Caption := Format('Executando #%d/%d (%s | %s): %s',
        [CurIdx, CurTot, FormatThroughputText, ElapsedStr, CurSql]);
  end;
end;

procedure TScriptExecutorFrame.ClearMetadataCache;
begin
  if FCompletionCtrl <> nil then
    FCompletionCtrl.ClearMetadataCache;
  if FLinkCtrl <> nil then
    FLinkCtrl.ClearCache;
end;

function TScriptExecutorFrame.ExecuteCompletionMetadataQuery(const ASQL: string): TQueryResult;
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
  TempSession: IDatabaseSession;
begin
  Result := nil;
  Profile := SelectedProfile;
  if (Profile = nil) or (FFactory = nil) then
    Exit;

  Provider := FFactory.GetProvider(Profile.DatabaseType);
  TempSession := Provider.CreateSession(Profile);
  try
    TempSession.Connect;
    Result := TempSession.ExecuteSQL(ASQL, False, 0);
  finally
    try
      if TempSession.InTransaction then
        TempSession.Rollback;
      TempSession.Disconnect;
    except
    end;
    TempSession := nil;
  end;
end;

procedure TScriptExecutorFrame.HandleOpenObjectLink(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind;
  const AObjectName: string
);
begin
  if Assigned(FOnOpenObject) then
    FOnOpenObject(AProfile, AKind, AObjectName);
end;

end.
