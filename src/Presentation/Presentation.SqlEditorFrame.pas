unit Presentation.SqlEditorFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Grids, Menus, LCLType, LCLIntf, LCLProc,
  SynEdit, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Domain.QueryHistory,
  Domain.ExplainPlanParser,
  Application.ExecuteQueryUseCase,
  Application.AsyncQueryRunner,
  Application.ManageDatabaseObjectsUseCase,
  Application.GridDmlHelper,
  Presentation.QueryResultGridFrame,
  Presentation.SqlCompletionController,
  Presentation.SqlObjectLinkController;

type
  TExecutionStateChangedEvent = procedure(
    Sender: TObject;
    const ARunning: Boolean;
    const AStatusText: string
  ) of object;

  { TSqlEditorFrame }
  TSqlEditorFrame = class(TFrame)
    pnlToolbar: TFlowPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    btnExecute: TButton;
    btnCancel: TButton;
    btnCommit: TButton;
    btnRollback: TButton;
    chkAutoCommit: TCheckBox;
    lblBatchSize: TLabel;
    cbBatchSize: TComboBox;
    lblMemLimit: TLabel;
    cbMemLimit: TComboBox;
    btnFetchAll: TButton;
    btnOpenSql: TButton;
    btnSaveSql: TButton;
    btnExportCsv: TButton;
    lblTxStatus: TLabel;
    SynEdit1: TSynEdit;
    SynSQLSyn1: TSynSQLSyn;
    Splitter1: TPanel;
    pgBottom: TPageControl;
    tsData: TTabSheet;
    tsPerformance: TTabSheet;
    pnlPerfSummary: TPanel;
    lblPerfTiming: TLabel;
    lblPerfIO: TLabel;
    lblPerfMemory: TLabel;
    pnlPerfPlan: TPanel;
    lblPerfPlanTitle: TLabel;
    memPerfPlan: TMemo;
    SplitterPerf: TSplitter;
    grdPerfTables: TStringGrid;
    tsMessages: TTabSheet;
    memMessages: TMemo;
    dlgOpenSql: TOpenDialog;
    dlgSaveSql: TSaveDialog;
    tmrExecElapsed: TTimer;
    procedure btnExecuteClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnCommitClick(Sender: TObject);
    procedure btnRollbackClick(Sender: TObject);
    procedure btnFetchAllClick(Sender: TObject);
    procedure btnOpenSqlClick(Sender: TObject);
    procedure btnSaveSqlClick(Sender: TObject);
    procedure btnExportCsvClick(Sender: TObject);
    procedure cbConnectionChange(Sender: TObject);
    procedure cbMemLimitEditingDone(Sender: TObject);
    procedure cbMemLimitKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure tmrExecElapsedTimer(Sender: TObject);
    procedure SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pnlToolbarResize(Sender: TObject);
    procedure Splitter1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure Splitter1MouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
    procedure Splitter1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure Splitter1Paint(Sender: TObject);
    procedure grdPerfTablesPrepareCanvas(sender: TObject; aCol, aRow: Integer;
      aState: TGridDrawState);
  private
    FFactory: IDatabaseProviderFactory;
    FExecuteUseCase: TExecuteQueryUseCase;
    FSession: IDatabaseSession;
    FActiveProfileId: string;
    FProfiles: TConnectionProfileList;
    FLastResult: TQueryResult;
    FIsFetchingMore: Boolean;
    FResultGrid: TQueryResultGridFrame;
    FCompletionCtrl: TSqlCompletionController;
    FEditorSplitRatio: Double;
    FIsAdjustingSplit: Boolean;
    FSplitterDragging: Boolean;
    FSplitDragStartY: Integer;
    FSplitDragStartHeight: Integer;
    FUpdatingToolbarSize: Boolean;
    FLastToolbarWidth: Integer;
    FIsExecuting: Boolean;
    FCancelRequested: Boolean;
    FExecStartTick: QWord;
    FActiveMode: TAsyncQueryMode;
    FActiveWorker: TAsyncSqlWorker;
    FCancelWorker: TCancelQueryWorker;
    FBaseTabCaption: string;
    FLowOsRamTicks: Integer;
    FAutoCancelledByLowOsRam: Boolean;
    FAutoCancelLowRamMessage: string;
    FDmlHelper: TGridDmlHelper;
    FLinkCtrl: TSqlObjectLinkController;
    FQueryHistory: IQueryHistoryService;
    FLastExecutedSQL: string;
    tvExplainVisual: TTreeView;
    btnRunExplain: TButton;
    chkSpillToDisk: TCheckBox;
    FOnExecutionStateChanged: TExecutionStateChangedEvent;
    FOnOpenObject: TOpenDbObjectLinkEvent;
    procedure LogMessage(const AMsg: string);
    procedure UpdateTransactionUI;
    procedure UpdateGridFromResult;
    procedure UpdatePerformanceUI;
    function FormatElapsedSeconds: string;
    procedure BeginBackgroundExecution(const AMode: TAsyncQueryMode);
    procedure EndBackgroundExecution;
    procedure HandleAsyncQueryCompleted(const AWorker: TAsyncSqlWorker);
    procedure HandleAsyncFetchAllCompleted(const AWorker: TAsyncSqlWorker);
    procedure HandleCancelCompleted(
      const AWorker: TCancelQueryWorker;
      const ASuccess: Boolean;
      const AMessage: string
    );
    procedure HandleGridNeedMoreRows(Sender: TObject);
    procedure HandleGridExportedCsv(Sender: TObject; const AFileName: string);
    function TryExtractSingleTableFromSelect(const ASQL: string): string;
    function HandleGridUpdateCell(const ARowIndex, AColIndex: Integer; const AOldRow: TQueryRow;
      const ANewIsNull: Boolean; const ANewValue: string; out AError: string): Boolean;
    function HandleGridInsertRow(const ANewRow: TQueryRow; out AError: string): Boolean;
    function HandleGridDeleteRow(const AOldRow: TQueryRow; out AError: string): Boolean;
    procedure HandleOpenObjectLink(const AProfile: TConnectionProfile;
      const AKind: TSchemaObjectKind; const AObjectName: string);
    procedure UpdateToolbarLayout;
    procedure AdjustEditorSplitHeight;
    procedure UpdateDataTabCaption;
    procedure PopulateExplainTree(const ARoot: TExplainPlanNode; const ASummary: TExplainPlanSummary);
    procedure btnRunExplainClick(Sender: TObject);
    procedure tvExplainVisualCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure TryFetchMoreRows;
    procedure ApplyHighlighterForProfile(const AProfile: TConnectionProfile);
    function EnsureSessionConnected: Boolean;
    function ExecuteMetadataQuery(const ASQL: string): TQueryResult;
    function SelectedProfile: TConnectionProfile;
    function CurrentBatchSize: Integer;
    function CurrentMemoryLimitBytes: Int64;
  protected
    procedure Resize; override;
  public
    destructor Destroy; override;
    procedure Initialize(
      const AFactory: IDatabaseProviderFactory;
      const AExecuteUseCase: TExecuteQueryUseCase;
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string = ''
    );
    procedure RefreshConnections(const AConnections: TConnectionProfileList);
    procedure ClearMetadataCache;
    procedure ExecuteCurrentSQL;
    function IsExecuting: Boolean;
    function IsConnected: Boolean;
    function HasActiveTransaction: Boolean;
    procedure RequestCancel;
    procedure DetachAndCancel;
    procedure DisconnectSession;
    function BaseTabCaption: string;
    function ActiveProfileId: string;
    function SqlText: string;
    procedure SetSqlText(const ASql: string);
    function BatchSizeText: string;
    procedure SetBatchSizeText(const AValue: string);
    function MemoryLimitText: string;
    procedure SetMemoryLimitText(const AValue: string);
    function AutoCommit: Boolean;
    procedure SetAutoCommit(const AValue: Boolean);
    property OnExecutionStateChanged: TExecutionStateChangedEvent
      read FOnExecutionStateChanged write FOnExecutionStateChanged;
    property OnOpenObject: TOpenDbObjectLinkEvent
      read FOnOpenObject write FOnOpenObject;
    property QueryHistory: IQueryHistoryService
      read FQueryHistory write FQueryHistory;
  end;

implementation

uses
  Presentation.TabHelpers;

{$R *.lfm}

destructor TSqlEditorFrame.Destroy;
begin
  if tmrExecElapsed <> nil then
    tmrExecElapsed.Enabled := False;
  if FCancelWorker <> nil then
  begin
    FCancelWorker.Detach;
    FCancelWorker := nil;
  end;
  if FActiveWorker <> nil then
  begin
    FActiveWorker.DetachAndCancel;
    FActiveWorker := nil;
    FSession := nil;
  end
  else if FSession <> nil then
  begin
    try
      if FSession.InTransaction then
        FSession.Rollback;
      FSession.Disconnect;
    except
    end;
    FSession := nil;
  end;
  if FResultGrid <> nil then
    FResultGrid.SetResult(nil, False, False);
  FreeAndNil(FDmlHelper);
  FreeAndNil(FLastResult);
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TSqlEditorFrame.Initialize(
  const AFactory: IDatabaseProviderFactory;
  const AExecuteUseCase: TExecuteQueryUseCase;
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string
);
begin
  FFactory := AFactory;
  FExecuteUseCase := AExecuteUseCase;
  FActiveProfileId := AInitialProfileId;
  FEditorSplitRatio := 0.45;
  FIsAdjustingSplit := False;
  FUpdatingToolbarSize := False;
  FLastToolbarWidth := -1;
  FIsExecuting := False;
  FCancelRequested := False;
  FExecStartTick := 0;
  FActiveMode := aqmExecuteSQL;
  FActiveWorker := nil;
  FCancelWorker := nil;
  FBaseTabCaption := '';
  FLowOsRamTicks := 0;
  FAutoCancelledByLowOsRam := False;
  FAutoCancelLowRamMessage := '';
  if FDmlHelper = nil then
    FDmlHelper := TGridDmlHelper.Create;

  {$IFDEF UNIX}
  SynEdit1.Font.Name := 'Monospace';
  memMessages.Font.Name := 'Monospace';
  memPerfPlan.Font.Name := 'Monospace';
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
      @ExecuteMetadataQuery,
      @HandleOpenObjectLink
    );
  FLinkCtrl.ClearCache;

  if FResultGrid = nil then
  begin
    FResultGrid := TQueryResultGridFrame.Create(Self);
    FResultGrid.Name := 'ResultGridFrame';
    FResultGrid.Parent := tsData;
    FResultGrid.Align := alClient;
    FResultGrid.EmptyMessage := 'Nenhuma consulta executada.';
    FResultGrid.OnNeedMoreRows := @HandleGridNeedMoreRows;
    FResultGrid.OnExportedCsv := @HandleGridExportedCsv;
    FResultGrid.OnUpdateCell := @HandleGridUpdateCell;
    FResultGrid.OnInsertRow := @HandleGridInsertRow;
    FResultGrid.OnDeleteRow := @HandleGridDeleteRow;
  end;
  FResultGrid.SetResult(nil, True, False);

  if FCompletionCtrl = nil then
    FCompletionCtrl := TSqlCompletionController.Create(
      Self,
      SynEdit1,
      @SelectedProfile,
      @ExecuteMetadataQuery
    );

  if chkSpillToDisk = nil then
  begin
    chkSpillToDisk := TCheckBox.Create(Self);
    chkSpillToDisk.Parent := pnlToolbar;
    chkSpillToDisk.Caption := 'Disco se faltar RAM';
    chkSpillToDisk.Hint := 'Quando atingir o limite de RAM ou memória do SO, armazena os resultados em arquivo temporário no disco.';
    chkSpillToDisk.ShowHint := True;
    chkSpillToDisk.Checked := False;
    chkSpillToDisk.AutoSize := True;
    chkSpillToDisk.BorderSpacing.Right := 8;
  end;

  if tvExplainVisual = nil then
  begin
    btnRunExplain := TButton.Create(Self);
    btnRunExplain.Parent := pnlPerfSummary;
    btnRunExplain.Align := alRight;
    btnRunExplain.Width := 210;
    btnRunExplain.Caption := 'Plano Visual (EXPLAIN ANALYZE)';
    btnRunExplain.OnClick := @btnRunExplainClick;

    tvExplainVisual := TTreeView.Create(Self);
    tvExplainVisual.Parent := pnlPerfPlan;
    tvExplainVisual.Align := alLeft;
    tvExplainVisual.Width := 520;
    tvExplainVisual.ReadOnly := True;
    tvExplainVisual.OnCustomDrawItem := @tvExplainVisualCustomDrawItem;
  end;

  RefreshConnections(AConnections);
  UpdateTransactionUI;
  UpdatePerformanceUI;
  UpdateToolbarLayout;
end;

procedure TSqlEditorFrame.RefreshConnections(const AConnections: TConnectionProfileList);
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

procedure TSqlEditorFrame.ClearMetadataCache;
begin
  if FCompletionCtrl <> nil then
    FCompletionCtrl.ClearMetadataCache;
  if FLinkCtrl <> nil then
    FLinkCtrl.ClearCache;
end;

function TSqlEditorFrame.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection.ItemIndex >= 0) and (cbConnection.ItemIndex < cbConnection.Items.Count) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

procedure TSqlEditorFrame.ApplyHighlighterForProfile(const AProfile: TConnectionProfile);
begin
  if AProfile = nil then
    Exit;
  if AProfile.DatabaseType = dtPostgreSQL then
    SynSQLSyn1.SQLDialect := sqlPostgres
  else
    SynSQLSyn1.SQLDialect := sqlFirebird40;
end;

procedure TSqlEditorFrame.cbConnectionChange(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  if FIsExecuting then
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

  ClearMetadataCache;

  if Profile <> nil then
  begin
    FActiveProfileId := Profile.Id;
    ApplyHighlighterForProfile(Profile);
    LogMessage('Conexão alterada para: ' + Profile.Name);
  end
  else
    FActiveProfileId := '';

  UpdateTransactionUI;
end;

procedure TSqlEditorFrame.LogMessage(const AMsg: string);
begin
  memMessages.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss', Now), AMsg]));
end;

procedure TSqlEditorFrame.UpdateTransactionUI;
begin
  if FIsExecuting then
  begin
    btnExecute.Enabled := False;
    btnCancel.Enabled := not FCancelRequested;
    btnCommit.Enabled := False;
    btnRollback.Enabled := False;
    cbConnection.Enabled := False;
    chkAutoCommit.Enabled := False;
    cbBatchSize.Enabled := False;
    cbMemLimit.Enabled := False;
    btnFetchAll.Enabled := False;
    btnExportCsv.Enabled := False;
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
  UpdateToolbarLayout;
end;

procedure TSqlEditorFrame.Resize;
begin
  inherited Resize;
  AdjustEditorSplitHeight;
end;

procedure TSqlEditorFrame.pnlToolbarResize(Sender: TObject);
begin
  if (not FUpdatingToolbarSize) and (pnlToolbar.Width <> FLastToolbarWidth) then
    UpdateToolbarLayout;
end;

procedure TSqlEditorFrame.Splitter1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  FSplitterDragging := True;
  FSplitDragStartY := Splitter1.ClientToScreen(Point(X, Y)).Y;
  FSplitDragStartHeight := SynEdit1.Height;
end;

procedure TSqlEditorFrame.Splitter1MouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  CurY, Avail, NewHeight: Integer;
begin
  if not FSplitterDragging then
    Exit;

  CurY := Splitter1.ClientToScreen(Point(X, Y)).Y;
  Avail := ClientHeight - pnlToolbar.Height - Splitter1.Height;
  if Avail <= 100 then
    Exit;

  NewHeight := FSplitDragStartHeight + (CurY - FSplitDragStartY);
  if NewHeight < 40 then
    NewHeight := 40
  else if NewHeight > Avail - 40 then
    NewHeight := Avail - 40;

  if SynEdit1.Height <> NewHeight then
  begin
    FIsAdjustingSplit := True;
    try
      SynEdit1.Height := NewHeight;
    finally
      FIsAdjustingSplit := False;
    end;
  end;
  FEditorSplitRatio := NewHeight / Avail;
  if FEditorSplitRatio < 0.08 then
    FEditorSplitRatio := 0.08
  else if FEditorSplitRatio > 0.92 then
    FEditorSplitRatio := 0.92;
end;

procedure TSqlEditorFrame.Splitter1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    FSplitterDragging := False;
end;

procedure TSqlEditorFrame.Splitter1Paint(Sender: TObject);
var
  C: TCanvas;
  MidX, MidY: Integer;
begin
  C := Splitter1.Canvas;
  C.Brush.Color := RGBToColor(226, 232, 240);
  C.FillRect(0, 0, Splitter1.Width, Splitter1.Height);
  C.Pen.Color := RGBToColor(148, 163, 184);
  C.Line(0, 0, Splitter1.Width, 0);
  C.Line(0, Splitter1.Height - 1, Splitter1.Width, Splitter1.Height - 1);

  MidX := Splitter1.Width div 2;
  MidY := Splitter1.Height div 2;
  C.Pen.Color := RGBToColor(100, 116, 139);
  C.Line(MidX - 24, MidY - 1, MidX + 24, MidY - 1);
  C.Line(MidX - 24, MidY + 1, MidX + 24, MidY + 1);
end;

procedure TSqlEditorFrame.UpdateToolbarLayout;
begin
  if FUpdatingToolbarSize or (pnlToolbar = nil) then
    Exit;

  FUpdatingToolbarSize := True;
  try
    FLastToolbarWidth := pnlToolbar.Width;
    pnlToolbar.ReAlign;
    pnlToolbar.InvalidatePreferredSize;
    pnlToolbar.AdjustSize;
  finally
    FUpdatingToolbarSize := False;
  end;
  AdjustEditorSplitHeight;
end;

procedure TSqlEditorFrame.AdjustEditorSplitHeight;
var
  Avail, NewHeight: Integer;
begin
  if FIsAdjustingSplit or (SynEdit1 = nil) or (pnlToolbar = nil) or (Splitter1 = nil) then
    Exit;

  if FEditorSplitRatio <= 0 then
    FEditorSplitRatio := 0.45;

  Avail := ClientHeight - pnlToolbar.Height - Splitter1.Height;
  if Avail > 100 then
  begin
    NewHeight := Round(Avail * FEditorSplitRatio);
    if NewHeight < 40 then
      NewHeight := 40
    else if NewHeight > Avail - 40 then
      NewHeight := Avail - 40;

    if SynEdit1.Height <> NewHeight then
    begin
      FIsAdjustingSplit := True;
      try
        SynEdit1.Height := NewHeight;
      finally
        FIsAdjustingSplit := False;
      end;
    end;
  end;
end;

procedure TSqlEditorFrame.UpdateDataTabCaption;
begin
  if (FLastResult = nil) or (not FLastResult.HasResultSet) then
    tsData.Caption := 'Dados (Grid)'
  else if FLastResult.SystemMemoryLow then
    tsData.Caption := Format('Dados (%d | RAM SO baixa)', [FLastResult.RowCount])
  else if FLastResult.MemoryLimitReached then
    tsData.Caption := Format('Dados (%d | Limite RAM)', [FLastResult.RowCount])
  else if FLastResult.HasMoreRows then
    tsData.Caption := Format('Dados (%d+)', [FLastResult.RowCount])
  else
    tsData.Caption := Format('Dados (%d)', [FLastResult.RowCount]);

  if (not FIsExecuting) and (FResultGrid <> nil) then
    FResultGrid.UpdateSummaryText;

  btnFetchAll.Enabled := (not FIsExecuting) and (FLastResult <> nil) and
    FLastResult.HasMoreRows and (not FLastResult.MemoryLimitReached);
end;

procedure TSqlEditorFrame.UpdateGridFromResult;
begin
  if FResultGrid <> nil then
    FResultGrid.SetResult(FLastResult, False, True);
  UpdateDataTabCaption;
end;

procedure TSqlEditorFrame.UpdatePerformanceUI;
var
  Perf: TQueryPerformanceStats;
  I, C, ColW, W: Integer;
  CanMeasure: Boolean;
  TotNonIdx, TotIdx: Int64;
  SysMem: TSystemMemoryInfo;
  OsRamSuffix: string;
  PlanRoot: TExplainPlanNode;
  PlanSum: TExplainPlanSummary;
begin
  if GetSystemMemoryInfo(SysMem) and SysMem.Available then
    OsRamSuffix := Format(
      ' | RAM SO Livre: %s / %s (reserva %s)',
      [
        FormatApproxBytes(SysMem.AvailableBytes),
        FormatApproxBytes(SysMem.TotalBytes),
        FormatApproxBytes(SysMem.ReserveBytes)
      ]
    )
  else
    OsRamSuffix := '';

  grdPerfTables.ColCount := 6;
  grdPerfTables.FixedCols := 0;
  grdPerfTables.FixedRows := 1;
  grdPerfTables.Cells[0, 0] := 'Tabela';
  grdPerfTables.Cells[1, 0] := 'Não-Indexadas (Natural)';
  grdPerfTables.Cells[2, 0] := 'Indexadas';
  grdPerfTables.Cells[3, 0] := 'Inserts';
  grdPerfTables.Cells[4, 0] := 'Updates';
  grdPerfTables.Cells[5, 0] := 'Deletes';

  if (FLastResult = nil) or (not FLastResult.Performance.HasData) then
  begin
    tsPerformance.Caption := 'Performance Analysis';
    lblPerfTiming.Caption := 'Nenhuma análise disponível. Execute uma consulta (F9).';
    lblPerfIO.Caption := 'I/O: ---';
    lblPerfMemory.Caption := 'Memória / Leituras: ---' + OsRamSuffix;
    memPerfPlan.Clear;
    if tvExplainVisual <> nil then
      tvExplainVisual.Items.Clear;
    grdPerfTables.RowCount := 1;
    grdPerfTables.ColWidths[0] := 200;
    grdPerfTables.ColWidths[1] := 160;
    grdPerfTables.ColWidths[2] := 110;
    grdPerfTables.ColWidths[3] := 90;
    grdPerfTables.ColWidths[4] := 90;
    grdPerfTables.ColWidths[5] := 90;
    Exit;
  end;

  Perf := FLastResult.Performance;
  TotNonIdx := Perf.TotalNonIndexedReads;
  TotIdx := Perf.TotalIndexedReads;

  if TotNonIdx > 0 then
    tsPerformance.Caption := Format('Performance (%d ms | !Natural)', [Perf.TotalTimeMs])
  else
    tsPerformance.Caption := Format('Performance (%d ms)', [Perf.TotalTimeMs]);

  lblPerfTiming.Caption := Format(
    'Prepare: %d ms | Execute/Fetch: %d ms | Total: %d ms | Linhas: %d',
    [Perf.PrepareTimeMs, Perf.ExecuteTimeMs, Perf.TotalTimeMs, FLastResult.RowCount]
  );
  lblPerfIO.Caption := Format(
    'I/O -> Disk Reads: %s | Disk Writes: %s | Memory Fetches: %s | Memory Marks: %s',
    [
      FormatFloat('#,##0', Perf.DiskReads),
      FormatFloat('#,##0', Perf.DiskWrites),
      FormatFloat('#,##0', Perf.MemoryFetches),
      FormatFloat('#,##0', Perf.MemoryMarks)
    ]
  );
  lblPerfMemory.Caption := Format(
    'Memória -> Atual: %s | Pico (Max): %s | Leituras -> Indexadas: %s | Não-Indexadas (Natural): %s',
    [
      FormatByteSize(Perf.CurrentMemoryBytes),
      FormatByteSize(Perf.MaxMemoryBytes),
      FormatFloat('#,##0', TotIdx),
      FormatFloat('#,##0', TotNonIdx)
    ]
  ) + OsRamSuffix;

  if Trim(Perf.PlanText) <> '' then
    memPerfPlan.Lines.Text := Perf.PlanText
  else
    memPerfPlan.Lines.Text := '(Nenhum plano retornado pelo servidor para esta instrução.)';

  if (tvExplainVisual <> nil) and (Trim(Perf.PlanText) <> '') then
  begin
    PlanRoot := TExplainPlanParser.ParseFirebirdPlan(Perf.PlanText, PlanSum);
    try
      PopulateExplainTree(PlanRoot, PlanSum);
    finally
      PlanRoot.Free;
    end;
  end;

  grdPerfTables.RowCount := Length(Perf.TableStats) + 1;
  for I := 0 to High(Perf.TableStats) do
  begin
    grdPerfTables.Cells[0, I + 1] := Perf.TableStats[I].TableName;
    grdPerfTables.Cells[1, I + 1] := IntToStr(Perf.TableStats[I].NonIndexedReads);
    grdPerfTables.Cells[2, I + 1] := IntToStr(Perf.TableStats[I].IndexedReads);
    grdPerfTables.Cells[3, I + 1] := IntToStr(Perf.TableStats[I].Inserts);
    grdPerfTables.Cells[4, I + 1] := IntToStr(Perf.TableStats[I].Updates);
    grdPerfTables.Cells[5, I + 1] := IntToStr(Perf.TableStats[I].Deletes);
  end;

  CanMeasure := grdPerfTables.HandleAllocated;
  if CanMeasure then
  begin
    grdPerfTables.Canvas.Font.Assign(grdPerfTables.Font);
    for C := 0 to grdPerfTables.ColCount - 1 do
    begin
      grdPerfTables.Canvas.Font.Style := [fsBold];
      ColW := grdPerfTables.Canvas.TextWidth(grdPerfTables.Cells[C, 0]) + 20;
      grdPerfTables.Canvas.Font.Style := [];
      for I := 1 to grdPerfTables.RowCount - 1 do
      begin
        W := grdPerfTables.Canvas.TextWidth(grdPerfTables.Cells[C, I]) + 18;
        if W > ColW then
          ColW := W;
      end;
      if ColW < 85 then
        ColW := 85
      else if ColW > 320 then
        ColW := 320;
      grdPerfTables.ColWidths[C] := ColW;
    end;
  end;
  grdPerfTables.Invalidate;
end;

procedure TSqlEditorFrame.grdPerfTablesPrepareCanvas(sender: TObject; aCol, aRow: Integer;
  aState: TGridDrawState);
var
  Val: string;
begin
  if (aRow >= 1) and (aCol = 1) and not (gdSelected in aState) then
  begin
    Val := Trim(grdPerfTables.Cells[aCol, aRow]);
    if (Val <> '') and (Val <> '0') then
    begin
      grdPerfTables.Canvas.Font.Color := clMaroon;
      grdPerfTables.Canvas.Font.Style := [fsBold];
    end;
  end;
end;

function TSqlEditorFrame.CurrentBatchSize: Integer;
var
  S: string;
begin
  S := LowerCase(Trim(cbBatchSize.Text));
  if (S = '') or (S = 'todos') or (S = 'all') or (S = '0') then
    Result := 0
  else
  begin
    Result := StrToIntDef(S, 100);
    if Result < 0 then
      Result := 100;
  end;
end;

function ParseMemoryLimitText(
  const AText: string;
  out ABytes: Int64;
  out ANormalizedText: string
): Boolean;
const
  MAX_RAM_BYTES: Int64 = Int64(1024) * 1024 * 1024 * 1024;
  MIN_RAM_BYTES: Int64 = 1024;
var
  S, NumPart, UnitPart, UnitLabel, ValueStr: string;
  I, Len: Integer;
  HasDigit, HasSep: Boolean;
  NumVal, RawBytes: Double;
  Multiplier: Int64;
  InvFmt: TFormatSettings;
begin
  Result := False;
  ABytes := DEFAULT_RESULT_MEMORY_LIMIT_BYTES;
  ANormalizedText := '128 MB';

  S := LowerCase(Trim(AText));
  if S = '' then
    Exit;

  if (S = 'sem limite') or (S = 'ilimitado') or (S = 'unlimited') or
     (S = 'none') or (S = 'todos') or (S = 'all') then
  begin
    ABytes := 0;
    ANormalizedText := 'Sem limite';
    Exit(True);
  end;

  Len := Length(S);
  I := 1;
  HasDigit := False;
  HasSep := False;
  while I <= Len do
  begin
    if S[I] in ['0'..'9'] then
    begin
      HasDigit := True;
      Inc(I);
    end
    else if (S[I] in ['.', ',']) and (not HasSep) then
    begin
      HasSep := True;
      Inc(I);
    end
    else
      Break;
  end;

  if not HasDigit then
    Exit(False);

  NumPart := StringReplace(Copy(S, 1, I - 1), ',', '.', [rfReplaceAll]);
  UnitPart := Trim(Copy(S, I, MaxInt));

  InvFmt := DefaultFormatSettings;
  InvFmt.DecimalSeparator := '.';
  if not TryStrToFloat(NumPart, NumVal, InvFmt) then
    Exit(False);
  if NumVal < 0 then
    Exit(False);

  if (UnitPart = '') or (UnitPart = 'm') or (UnitPart = 'mb') or
     (UnitPart = 'mib') or (UnitPart = 'mega') or (UnitPart = 'megas') then
  begin
    Multiplier := Int64(1024) * 1024;
    UnitLabel := 'MB';
  end
  else if (UnitPart = 'g') or (UnitPart = 'gb') or (UnitPart = 'gib') or
          (UnitPart = 'giga') or (UnitPart = 'gigas') then
  begin
    Multiplier := Int64(1024) * 1024 * 1024;
    UnitLabel := 'GB';
  end
  else if (UnitPart = 'k') or (UnitPart = 'kb') or (UnitPart = 'kib') then
  begin
    Multiplier := 1024;
    UnitLabel := 'KB';
  end
  else if (UnitPart = 'b') or (UnitPart = 'byte') or (UnitPart = 'bytes') then
  begin
    Multiplier := 1;
    UnitLabel := 'B';
  end
  else
    Exit(False);

  if NumVal = 0 then
  begin
    ABytes := 0;
    ANormalizedText := 'Sem limite';
    Exit(True);
  end;

  RawBytes := NumVal * Multiplier;
  if RawBytes >= MAX_RAM_BYTES then
    ABytes := MAX_RAM_BYTES
  else if RawBytes < MIN_RAM_BYTES then
    ABytes := MIN_RAM_BYTES
  else
    ABytes := Round(RawBytes);

  if Abs(NumVal - Round(NumVal)) < 0.0001 then
    ValueStr := IntToStr(Round(NumVal))
  else
    ValueStr := FormatFloat('0.##', NumVal, InvFmt);

  ANormalizedText := ValueStr + ' ' + UnitLabel;
  Result := True;
end;

function TSqlEditorFrame.CurrentMemoryLimitBytes: Int64;
var
  NormText: string;
begin
  if not ParseMemoryLimitText(cbMemLimit.Text, Result, NormText) then
    Result := DEFAULT_RESULT_MEMORY_LIMIT_BYTES;
end;

procedure TSqlEditorFrame.cbMemLimitEditingDone(Sender: TObject);
var
  Bytes, SafeHeadroom: Int64;
  NormText: string;
  SysMem: TSystemMemoryInfo;
begin
  if ParseMemoryLimitText(cbMemLimit.Text, Bytes, NormText) then
  begin
    if cbMemLimit.Text <> NormText then
      cbMemLimit.Text := NormText;

    if GetSystemMemoryInfo(SysMem) and SysMem.Available then
    begin
      if SysMem.AvailableBytes > SysMem.ReserveBytes then
        SafeHeadroom := SysMem.AvailableBytes - SysMem.ReserveBytes
      else
        SafeHeadroom := 0;

      if (Bytes > 0) and (Bytes > SafeHeadroom) then
        LogMessage(Format(
          'AVISO: O limite configurado (%s) excede a folga segura atual do SO (%s livres de %s; reserva %s). A proteção automática de RAM do sistema permanecerá ativa.',
          [
            NormText,
            FormatApproxBytes(SysMem.AvailableBytes),
            FormatApproxBytes(SysMem.TotalBytes),
            FormatApproxBytes(SysMem.ReserveBytes)
          ]
        ))
      else if Bytes = 0 then
        LogMessage(Format(
          'Limite por consulta desativado (Sem limite). A proteção automática de RAM do sistema permanecerá ativa (livre: %s / %s; reserva %s).',
          [
            FormatApproxBytes(SysMem.AvailableBytes),
            FormatApproxBytes(SysMem.TotalBytes),
            FormatApproxBytes(SysMem.ReserveBytes)
          ]
        ));
    end;
  end
  else
  begin
    if Trim(cbMemLimit.Text) <> '' then
      LogMessage('Limite de RAM inválido; restaurado para 128 MB (use ex.: 256, 512 MB, 2 GB ou 0).');
    cbMemLimit.Text := '128 MB';
  end;
end;

procedure TSqlEditorFrame.cbMemLimitKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    cbMemLimitEditingDone(Sender);
    if SynEdit1.CanFocus then
      SynEdit1.SetFocus;
  end;
end;

procedure TSqlEditorFrame.TryFetchMoreRows;
var
  Fetched, Batch: Integer;
  WasSysLow: Boolean;
begin
  if FIsExecuting or FIsFetchingMore or (FLastResult = nil) or (not FLastResult.HasMoreRows) then
    Exit;

  if (FResultGrid = nil) or (not FResultGrid.IsNearBottom(10)) then
    Exit;

  WasSysLow := FLastResult.SystemMemoryLow;
  FLastResult.MemoryLimitBytes := CurrentMemoryLimitBytes;
  Batch := CurrentBatchSize;
  if Batch <= 0 then
    Batch := 100;

  FIsFetchingMore := True;
  try
    Fetched := FLastResult.FetchMore(Batch);
    if Fetched > 0 then
    begin
      FResultGrid.RefreshRowCount;
      UpdateDataTabCaption;
      UpdatePerformanceUI;
      if FLastResult.MemoryLimitReached then
        LogMessage('AVISO: ' + FLastResult.LimitMessage)
      else if not FLastResult.HasMoreRows then
        LogMessage(Format('Todos os %d registros foram carregados.', [FLastResult.RowCount]));
    end
    else
    begin
      UpdateDataTabCaption;
      UpdatePerformanceUI;
      if FLastResult.MemoryLimitReached then
        LogMessage('AVISO: ' + FLastResult.LimitMessage);
    end;

    if FLastResult.SystemMemoryLow and (not WasSysLow) then
      MessageDlg('Proteção de Memória RAM do Sistema', FLastResult.LimitMessage, mtWarning, [mbOK], 0);
  finally
    FIsFetchingMore := False;
  end;
end;

procedure TSqlEditorFrame.HandleGridNeedMoreRows(Sender: TObject);
begin
  TryFetchMoreRows;
end;

procedure TSqlEditorFrame.HandleGridExportedCsv(Sender: TObject; const AFileName: string);
begin
  LogMessage('Resultado exportado para CSV: ' + AFileName);
end;

procedure TSqlEditorFrame.btnFetchAllClick(Sender: TObject);
var
  ResultCursor: IResultSetCursor;
  Staging: TQueryResult;
  MemLimit: Int64;
  SysMem: TSystemMemoryInfo;
  WarnMsg: string;
begin
  if FIsExecuting or FIsFetchingMore or (FLastResult = nil) or (not FLastResult.HasMoreRows) or
     (FSession = nil) then
    Exit;

  if GetSystemMemoryInfo(SysMem) and SysMem.Available and
     (SysMem.AvailableBytes <= SysMem.ReserveBytes) then
  begin
    WarnMsg := Format(
      'Fetch All bloqueado porque a memória RAM disponível do sistema está baixa (%s livres de %s; reserva mínima de segurança: %s). Feche outras abas ou aplicativos antes de continuar para evitar travamento do sistema operacional.',
      [
        FormatApproxBytes(SysMem.AvailableBytes),
        FormatApproxBytes(SysMem.TotalBytes),
        FormatApproxBytes(SysMem.ReserveBytes)
      ]
    );
    LogMessage('AVISO: ' + WarnMsg);
    MessageDlg('Proteção de Memória RAM do Sistema', WarnMsg, mtWarning, [mbOK], 0);
    Exit;
  end;

  MemLimit := CurrentMemoryLimitBytes;
  FLastResult.MemoryLimitBytes := MemLimit;
  if FLastResult.IsMemoryLimitReached then
  begin
    FLastResult.MarkMemoryLimitReached;
    FLastResult.CloseCursor;
    UpdateDataTabCaption;
    LogMessage('AVISO: ' + FLastResult.LimitMessage);
    if FLastResult.SystemMemoryLow then
      MessageDlg('Proteção de Memória RAM do Sistema', FLastResult.LimitMessage, mtWarning, [mbOK], 0);
    Exit;
  end;

  ResultCursor := FLastResult.Cursor;
  if ResultCursor = nil then
    Exit;
  FLastResult.Cursor := nil;

  Staging := TQueryResult.Create;
  Staging.MemoryLimitBytes := MemLimit;
  Staging.BaselineMemoryBytes := FLastResult.EstimatedMemoryBytes;
  Staging.Performance.AssignFrom(FLastResult.Performance);

  FIsFetchingMore := True;
  BeginBackgroundExecution(aqmFetchAll);
  FActiveWorker := TAsyncSqlWorker.CreateFetchAll(
    FSession,
    ResultCursor,
    Staging,
    @HandleAsyncFetchAllCompleted
  );
  FActiveWorker.Start;
end;

function TSqlEditorFrame.FormatElapsedSeconds: string;
var
  ElapsedMs: Int64;
begin
  ElapsedMs := Int64(GetTickCount64 - FExecStartTick);
  Result := FormatFloat('0.0', ElapsedMs / 1000.0) + 's';
end;

function TSqlEditorFrame.BaseTabCaption: string;
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

function TSqlEditorFrame.IsExecuting: Boolean;
begin
  Result := FIsExecuting;
end;

function TSqlEditorFrame.IsConnected: Boolean;
begin
  Result := FIsExecuting or ((FSession <> nil) and FSession.IsConnected);
end;

function TSqlEditorFrame.HasActiveTransaction: Boolean;
begin
  Result := (not FIsExecuting) and (FSession <> nil) and FSession.IsConnected and FSession.InTransaction;
end;

procedure TSqlEditorFrame.BeginBackgroundExecution(const AMode: TAsyncQueryMode);
var
  ElapsedStr, StatusText: string;
begin
  FBaseTabCaption := BaseTabCaption;
  FIsExecuting := True;
  FCancelRequested := False;
  FLowOsRamTicks := 0;
  FAutoCancelledByLowOsRam := False;
  FAutoCancelLowRamMessage := '';
  FActiveMode := AMode;
  FExecStartTick := GetTickCount64;

  if Parent is TTabSheet then
  begin
    if FBaseTabCaption <> '' then
      SetTabSheetTitle(TTabSheet(Parent), FBaseTabCaption + ' (Executando...)')
    else
      SetTabSheetTitle(TTabSheet(Parent), 'Executando...');
  end;

  btnExecute.Enabled := False;
  btnCancel.Enabled := True;
  btnCommit.Enabled := False;
  btnRollback.Enabled := False;
  cbConnection.Enabled := False;
  chkAutoCommit.Enabled := False;
  cbBatchSize.Enabled := False;
  cbMemLimit.Enabled := False;
  btnFetchAll.Enabled := False;
  btnExportCsv.Enabled := False;
  if FResultGrid <> nil then
  begin
    FResultGrid.SortingEnabled := False;
    FResultGrid.ExportEnabled := False;
  end;

  ElapsedStr := FormatElapsedSeconds;
  lblTxStatus.Font.Color := clNavy;
  if AMode = aqmFetchAll then
  begin
    lblTxStatus.Caption := 'Fetch All... ' + ElapsedStr;
    if FLastResult <> nil then
    begin
      tsData.Caption := Format('Dados (%d+ carregando...)', [FLastResult.RowCount]);
      if FResultGrid <> nil then
        FResultGrid.SetCustomSummary(Format('Fetch All... (%d registro(s) até agora | %s)',
          [FLastResult.RowCount, ElapsedStr]));
    end
    else
    begin
      tsData.Caption := 'Dados (Fetch All...)';
      if FResultGrid <> nil then
        FResultGrid.SetCustomSummary('Carregando registros em segundo plano... ' + ElapsedStr);
    end;
    StatusText := 'Carregando registros em segundo plano...';
  end
  else
  begin
    lblTxStatus.Caption := 'Executando... ' + ElapsedStr;
    tsData.Caption := 'Dados (Executando...)';
    if FResultGrid <> nil then
      FResultGrid.SetCustomSummary('Executando consulta em segundo plano... ' + ElapsedStr);
    StatusText := 'Executando consulta em segundo plano...';
  end;

  UpdateToolbarLayout;
  tmrExecElapsed.Enabled := True;

  if Assigned(FOnExecutionStateChanged) then
    FOnExecutionStateChanged(Self, True, StatusText);
end;

procedure TSqlEditorFrame.EndBackgroundExecution;
begin
  if tmrExecElapsed <> nil then
    tmrExecElapsed.Enabled := False;
  FIsExecuting := False;
  FActiveWorker := nil;

  if (Parent is TTabSheet) and (FBaseTabCaption <> '') then
    SetTabSheetTitle(TTabSheet(Parent), FBaseTabCaption);
  FBaseTabCaption := '';

  btnExecute.Enabled := True;
  btnCancel.Enabled := False;
  cbConnection.Enabled := True;
  chkAutoCommit.Enabled := True;
  cbBatchSize.Enabled := True;
  cbMemLimit.Enabled := True;
  if FResultGrid <> nil then
  begin
    FResultGrid.SortingEnabled := True;
    FResultGrid.ExportEnabled := True;
  end;
end;

procedure TSqlEditorFrame.HandleAsyncQueryCompleted(const AWorker: TAsyncSqlWorker);
var
  NewResult: TQueryResult;
  ErrMsg, StatusMsg, AutoLowRamMsg: string;
  WasCancel, AutoLowRam: Boolean;
  Prof: TConnectionProfile;
begin
  if AWorker <> FActiveWorker then
    Exit;

  WasCancel := FCancelRequested or AWorker.WasCancelled;
  AutoLowRam := FAutoCancelledByLowOsRam;
  AutoLowRamMsg := FAutoCancelLowRamMessage;
  FLowOsRamTicks := 0;
  FAutoCancelledByLowOsRam := False;
  FAutoCancelLowRamMessage := '';
  ErrMsg := AWorker.ErrorMessage;
  NewResult := AWorker.TakeResult;
  EndBackgroundExecution;
  FCancelRequested := False;

  if NewResult <> nil then
  begin
    if FResultGrid <> nil then
      FResultGrid.SetResult(nil, False, False);
    FreeAndNil(FLastResult);
    FLastResult := NewResult;
  end;

  if FResultGrid <> nil then
  begin
    FResultGrid.SetResult(FLastResult, True, True);
    if (FLastResult <> nil) and FLastResult.Success and FLastResult.HasResultSet and
       (FDmlHelper <> nil) and (FDmlHelper.TableName <> '') then
      FResultGrid.SetEditable(True, FDmlHelper.TableName)
    else
      FResultGrid.SetEditable(False);
  end;
  if FLinkCtrl <> nil then
    FLinkCtrl.EnsureLoaded;
  UpdateDataTabCaption;
  UpdatePerformanceUI;
  btnExportCsv.Enabled := (FLastResult <> nil) and FLastResult.HasResultSet and (FLastResult.RowCount > 0);

  if ErrMsg <> '' then
  begin
    if WasCancel then
      StatusMsg := 'Execução cancelada: ' + ErrMsg
    else
      StatusMsg := 'ERRO: ' + ErrMsg;
    LogMessage(StatusMsg);
    pgBottom.ActivePage := tsMessages;
  end
  else if FLastResult <> nil then
  begin
    if FLastResult.Success then
    begin
      StatusMsg := Format('%s (%d ms)', [FLastResult.MessageText, FLastResult.ExecutionTimeMs]);
      LogMessage(StatusMsg);
      if FLastResult.MemoryLimitReached then
        LogMessage('AVISO: ' + FLastResult.LimitMessage);
      if FLastResult.HasResultSet then
        pgBottom.ActivePage := tsData
      else
        pgBottom.ActivePage := tsMessages;
    end
    else
    begin
      if WasCancel then
        StatusMsg := 'Consulta cancelada: ' + FLastResult.MessageText
      else
        StatusMsg := 'ERRO: ' + FLastResult.MessageText;
      LogMessage(StatusMsg);
      pgBottom.ActivePage := tsMessages;
    end;
  end
  else
  begin
    StatusMsg := 'Execução finalizada sem resultado.';
    LogMessage(StatusMsg);
    pgBottom.ActivePage := tsMessages;
  end;

  if (FQueryHistory <> nil) and (Trim(FLastExecutedSQL) <> '') then
  begin
    Prof := SelectedProfile;
    if Prof <> nil then
    begin
      if (ErrMsg = '') and (FLastResult <> nil) and FLastResult.Success then
        FQueryHistory.RecordExecution(
          Prof.Id, Prof.Name, Prof.DatabaseType, FLastExecutedSQL,
          FLastResult.ExecutionTimeMs, True, FLastResult.MessageText, ''
        )
      else
      begin
        if ErrMsg <> '' then
          StatusMsg := ErrMsg
        else if FLastResult <> nil then
          StatusMsg := FLastResult.MessageText;
        if FLastResult <> nil then
          FQueryHistory.RecordExecution(
            Prof.Id, Prof.Name, Prof.DatabaseType, FLastExecutedSQL,
            FLastResult.ExecutionTimeMs, False, '', StatusMsg
          )
        else
          FQueryHistory.RecordExecution(
            Prof.Id, Prof.Name, Prof.DatabaseType, FLastExecutedSQL,
            0, False, '', StatusMsg
          );
      end;
    end;
  end;

  UpdateTransactionUI;
  if Assigned(FOnExecutionStateChanged) then
    FOnExecutionStateChanged(Self, False, StatusMsg);

  if (FLastResult <> nil) and FLastResult.SystemMemoryLow then
    MessageDlg('Proteção de Memória RAM do Sistema', FLastResult.LimitMessage, mtWarning, [mbOK], 0)
  else if AutoLowRam then
    MessageDlg('Proteção de Memória RAM do Sistema', AutoLowRamMsg, mtWarning, [mbOK], 0);
end;

procedure TSqlEditorFrame.HandleAsyncFetchAllCompleted(const AWorker: TAsyncSqlWorker);
var
  Staging: TQueryResult;
  RemCursor: IResultSetCursor;
  Fetched: Integer;
  ErrMsg, StatusMsg, AutoLowRamMsg: string;
  WasCancel, AutoLowRam: Boolean;
begin
  if AWorker <> FActiveWorker then
    Exit;

  WasCancel := FCancelRequested or AWorker.WasCancelled;
  AutoLowRam := FAutoCancelledByLowOsRam;
  AutoLowRamMsg := FAutoCancelLowRamMessage;
  FLowOsRamTicks := 0;
  FAutoCancelledByLowOsRam := False;
  FAutoCancelLowRamMessage := '';
  ErrMsg := AWorker.ErrorMessage;
  Staging := AWorker.TakeResult;
  RemCursor := AWorker.TakeCursor;
  FIsFetchingMore := False;
  EndBackgroundExecution;
  FCancelRequested := False;

  try
    if FLastResult <> nil then
    begin
      Fetched := 0;
      if Staging <> nil then
      begin
        Fetched := FLastResult.AppendRowsFrom(Staging);
        if Staging.Performance.HasData then
          FLastResult.Performance.AssignFrom(Staging.Performance);
      end;
      if (RemCursor <> nil) and RemCursor.HasMore then
        FLastResult.Cursor := RemCursor
      else if RemCursor <> nil then
        RemCursor.CloseCursor;
      FLastResult.ExecutionTimeMs := FLastResult.ExecutionTimeMs + AWorker.ElapsedMs;

      if FResultGrid <> nil then
        FResultGrid.RefreshRowCount;
      UpdateDataTabCaption;
      UpdatePerformanceUI;
      btnExportCsv.Enabled := FLastResult.HasResultSet and (FLastResult.RowCount > 0);

      if ErrMsg <> '' then
        StatusMsg := Format('Fetch All interrompido (+%d registro(s)): %s', [Fetched, ErrMsg])
      else if FLastResult.MemoryLimitReached then
        StatusMsg := 'AVISO: ' + FLastResult.LimitMessage
      else if WasCancel and FLastResult.HasMoreRows then
        StatusMsg := Format('Fetch All cancelado: +%d registro(s), total %d (%d ms).',
          [Fetched, FLastResult.RowCount, AWorker.ElapsedMs])
      else
        StatusMsg := Format('Fetch All: +%d registro(s), total %d (%d ms).',
          [Fetched, FLastResult.RowCount, AWorker.ElapsedMs]);
      LogMessage(StatusMsg);
    end
    else
    begin
      if RemCursor <> nil then
        RemCursor.CloseCursor;
      StatusMsg := 'Fetch All finalizado.';
    end;
  finally
    Staging.Free;
  end;

  UpdateTransactionUI;
  if Assigned(FOnExecutionStateChanged) then
    FOnExecutionStateChanged(Self, False, StatusMsg);

  if (FLastResult <> nil) and FLastResult.SystemMemoryLow then
    MessageDlg('Proteção de Memória RAM do Sistema', FLastResult.LimitMessage, mtWarning, [mbOK], 0)
  else if AutoLowRam then
    MessageDlg('Proteção de Memória RAM do Sistema', AutoLowRamMsg, mtWarning, [mbOK], 0);
end;

procedure TSqlEditorFrame.HandleCancelCompleted(
  const AWorker: TCancelQueryWorker;
  const ASuccess: Boolean;
  const AMessage: string
);
begin
  if FCancelWorker = AWorker then
    FCancelWorker := nil;

  if Trim(AMessage) <> '' then
    LogMessage(AMessage);

  if (not ASuccess) and FIsExecuting then
  begin
    FCancelRequested := False;
    btnCancel.Enabled := True;
  end;
end;

procedure TSqlEditorFrame.RequestCancel;
begin
  if (not FIsExecuting) or FCancelRequested then
    Exit;

  FCancelRequested := True;
  btnCancel.Enabled := False;
  if FActiveWorker <> nil then
    FActiveWorker.MarkCancelRequested;

  lblTxStatus.Caption := 'Cancelando... ' + FormatElapsedSeconds;
  if FResultGrid <> nil then
    FResultGrid.SetCustomSummary('Solicitando cancelamento... ' + FormatElapsedSeconds);
  LogMessage('Solicitando cancelamento da consulta...');

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

procedure TSqlEditorFrame.DetachAndCancel;
begin
  if tmrExecElapsed <> nil then
    tmrExecElapsed.Enabled := False;
  if FCancelWorker <> nil then
  begin
    FCancelWorker.Detach;
    FCancelWorker := nil;
  end;
  if FActiveWorker <> nil then
  begin
    FActiveWorker.DetachAndCancel;
    FActiveWorker := nil;
    FSession := nil;
  end;
  FIsExecuting := False;
  FIsFetchingMore := False;
  FCancelRequested := False;
end;

procedure TSqlEditorFrame.DisconnectSession;
var
  WasConnected: Boolean;
begin
  if FIsExecuting then
  begin
    DetachAndCancel;
    EndBackgroundExecution;
    if FLastResult <> nil then
      FLastResult.CloseCursor;
    btnExportCsv.Enabled := (FLastResult <> nil) and FLastResult.HasResultSet and (FLastResult.RowCount > 0);
    UpdateDataTabCaption;
    UpdateTransactionUI;
    LogMessage('Execução cancelada e conexão desconectada.');
    if Assigned(FOnExecutionStateChanged) then
      FOnExecutionStateChanged(Self, False, 'Execução cancelada e conexão desconectada.');
    Exit;
  end;

  if FLastResult <> nil then
    FLastResult.CloseCursor;

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

  UpdateDataTabCaption;
  UpdateTransactionUI;
  if WasConnected then
    LogMessage('Conexão desconectada.');
end;

procedure TSqlEditorFrame.btnCancelClick(Sender: TObject);
begin
  RequestCancel;
end;

procedure TSqlEditorFrame.tmrExecElapsedTimer(Sender: TObject);
var
  ElapsedStr, Prefix: string;
  SysMem: TSystemMemoryInfo;
begin
  if not FIsExecuting then
  begin
    tmrExecElapsed.Enabled := False;
    Exit;
  end;

  if not FCancelRequested then
  begin
    if GetSystemMemoryInfo(SysMem) and SysMem.Available and
       (SysMem.AvailableBytes <= SysMem.ReserveBytes) then
    begin
      Inc(FLowOsRamTicks);
      if (FLowOsRamTicks >= 2) or (SysMem.AvailableBytes <= (SysMem.ReserveBytes div 2)) then
      begin
        FAutoCancelledByLowOsRam := True;
        FAutoCancelLowRamMessage := Format(
          'Consulta cancelada automaticamente pela proteção de memória RAM do sistema para evitar travamento do SO (RAM livre: %s de %s; reserva mínima: %s).',
          [
            FormatApproxBytes(SysMem.AvailableBytes),
            FormatApproxBytes(SysMem.TotalBytes),
            FormatApproxBytes(SysMem.ReserveBytes)
          ]
        );
        LogMessage('AVISO: ' + FAutoCancelLowRamMessage);
        RequestCancel;
        Exit;
      end;
    end
    else
      FLowOsRamTicks := 0;
  end;

  ElapsedStr := FormatElapsedSeconds;
  if FCancelRequested then
    Prefix := 'Cancelando'
  else if FActiveMode = aqmFetchAll then
    Prefix := 'Fetch All'
  else
    Prefix := 'Executando';

  lblTxStatus.Caption := Format('%s... %s', [Prefix, ElapsedStr]);
  if FActiveMode = aqmFetchAll then
  begin
    if (FLastResult <> nil) and (FResultGrid <> nil) then
      FResultGrid.SetCustomSummary(Format('%s... (%d registro(s) até agora | %s)',
        [Prefix, FLastResult.RowCount, ElapsedStr]));
  end
  else if FResultGrid <> nil then
    FResultGrid.SetCustomSummary(Format('%s consulta em segundo plano... %s', [Prefix, ElapsedStr]));
end;

procedure TSqlEditorFrame.ExecuteCurrentSQL;
var
  Profile: TConnectionProfile;
  SQLToRun, LowRamPrompt: string;
  Provider: IDatabaseProvider;
  SysMem: TSystemMemoryInfo;
begin
  if FIsExecuting then
  begin
    LogMessage('Uma consulta já está em execução nesta aba.');
    Exit;
  end;

  Profile := SelectedProfile;
  if Profile = nil then
  begin
    MessageDlg('Aviso', 'Selecione ou cadastre uma conexão antes de executar.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if SynEdit1.SelAvail then
    SQLToRun := SynEdit1.SelText
  else
    SQLToRun := SynEdit1.Lines.Text;

  if Trim(SQLToRun) = '' then
  begin
    LogMessage('Nenhuma instrução SQL para executar.');
    Exit;
  end;
  FLastExecutedSQL := SQLToRun;

  if FSession = nil then
  begin
    Provider := FFactory.GetProvider(Profile.DatabaseType);
    FSession := Provider.CreateSession(Profile);
  end;

  if FResultGrid <> nil then
  begin
    FResultGrid.SetEditable(False);
    FResultGrid.SetResult(nil, True, False);
  end;
  if FDmlHelper <> nil then
    FDmlHelper.Reset(TryExtractSingleTableFromSelect(SQLText));
  if FLastResult <> nil then
  begin
    FreeAndNil(FLastResult);
    TrimProcessMemoryUsage;
  end;
  UpdateGridFromResult;
  UpdatePerformanceUI;

  if GetSystemMemoryInfo(SysMem) and SysMem.Available and
     (SysMem.AvailableBytes <= SysMem.ReserveBytes) then
  begin
    LowRamPrompt := Format(
      'A memória RAM disponível do sistema está crítica (%s livres de %s; reserva mínima: %s).' + LineEnding +
      'Se continuar, o carregamento será interrompido automaticamente caso a RAM permaneça crítica, para evitar travar o sistema operacional.' + LineEnding + LineEnding +
      'Deseja executar a consulta mesmo assim?',
      [
        FormatApproxBytes(SysMem.AvailableBytes),
        FormatApproxBytes(SysMem.TotalBytes),
        FormatApproxBytes(SysMem.ReserveBytes)
      ]
    );
    if MessageDlg('Memória RAM do Sistema Baixa', LowRamPrompt, mtWarning, [mbYes, mbNo], 0) <> mrYes then
    begin
      LogMessage('Execução cancelada pelo usuário devido à pouca memória RAM disponível no sistema.');
      Exit;
    end;
  end;

  BeginBackgroundExecution(aqmExecuteSQL);
  FActiveWorker := TAsyncSqlWorker.CreateExecuteSQL(
    FSession,
    SQLToRun,
    chkAutoCommit.Checked,
    CurrentBatchSize,
    @HandleAsyncQueryCompleted,
    CurrentMemoryLimitBytes,
    (chkSpillToDisk <> nil) and chkSpillToDisk.Checked
  );
  FActiveWorker.Start;
end;

procedure TSqlEditorFrame.btnExecuteClick(Sender: TObject);
begin
  ExecuteCurrentSQL;
end;

procedure TSqlEditorFrame.btnCommitClick(Sender: TObject);
begin
  if FIsExecuting or (FSession = nil) then
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

procedure TSqlEditorFrame.btnRollbackClick(Sender: TObject);
begin
  if FIsExecuting or (FSession = nil) then
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

procedure TSqlEditorFrame.btnOpenSqlClick(Sender: TObject);
begin
  if dlgOpenSql.Execute then
  begin
    SynEdit1.Lines.LoadFromFile(dlgOpenSql.FileName);
    LogMessage('Arquivo carregado: ' + dlgOpenSql.FileName);
  end;
end;

procedure TSqlEditorFrame.btnSaveSqlClick(Sender: TObject);
begin
  if dlgSaveSql.Execute then
  begin
    SynEdit1.Lines.SaveToFile(dlgSaveSql.FileName);
    LogMessage('Arquivo salvo: ' + dlgSaveSql.FileName);
  end;
end;

procedure TSqlEditorFrame.btnExportCsvClick(Sender: TObject);
begin
  if (not FIsExecuting) and (FResultGrid <> nil) then
    FResultGrid.ExportToCsv;
end;

procedure TSqlEditorFrame.SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F9) and (Shift = []) then
  begin
    Key := 0;
    if not FIsExecuting then
      ExecuteCurrentSQL;
  end
  else if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    if not FIsExecuting then
      ExecuteCurrentSQL;
  end;
end;

function TSqlEditorFrame.ActiveProfileId: string;
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    Result := Profile.Id
  else
    Result := FActiveProfileId;
end;

function TSqlEditorFrame.SqlText: string;
begin
  Result := SynEdit1.Lines.Text;
end;

procedure TSqlEditorFrame.SetSqlText(const ASql: string);
begin
  SynEdit1.Lines.Text := ASql;
end;

function TSqlEditorFrame.BatchSizeText: string;
begin
  Result := cbBatchSize.Text;
end;

procedure TSqlEditorFrame.SetBatchSizeText(const AValue: string);
begin
  if Trim(AValue) <> '' then
    cbBatchSize.Text := AValue;
end;

function TSqlEditorFrame.MemoryLimitText: string;
begin
  Result := Trim(cbMemLimit.Text);
end;

procedure TSqlEditorFrame.SetMemoryLimitText(const AValue: string);
var
  Bytes: Int64;
  NormText: string;
begin
  if ParseMemoryLimitText(AValue, Bytes, NormText) then
    cbMemLimit.Text := NormText;
end;

function TSqlEditorFrame.AutoCommit: Boolean;
begin
  Result := chkAutoCommit.Checked;
end;

procedure TSqlEditorFrame.SetAutoCommit(const AValue: Boolean);
begin
  chkAutoCommit.Checked := AValue;
end;

function TSqlEditorFrame.EnsureSessionConnected: Boolean;
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
begin
  Result := False;
  if FIsExecuting then
    Exit;
  if (FSession <> nil) and FSession.IsConnected then
  begin
    Result := True;
    Exit;
  end;

  Profile := SelectedProfile;
  if (Profile = nil) or (FFactory = nil) then
    Exit;

  try
    if FSession = nil then
    begin
      Provider := FFactory.GetProvider(Profile.DatabaseType);
      FSession := Provider.CreateSession(Profile);
    end;
    if not FSession.IsConnected then
      FSession.Connect;
    Result := FSession.IsConnected;
    UpdateTransactionUI;
  except
    on E: Exception do
    begin
      LogMessage('Aviso ao conectar para autocompletar: ' + E.Message);
      Result := False;
    end;
  end;
end;

function TSqlEditorFrame.ExecuteMetadataQuery(const ASQL: string): TQueryResult;
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
  TempSession: IDatabaseSession;
begin
  Result := nil;
  Profile := SelectedProfile;
  if (Profile = nil) or (FFactory = nil) then
    Exit;

  { Evita disputar a FSession quando há consulta em segundo plano ou cursor paginado aberto }
  if FIsExecuting or ((FLastResult <> nil) and FLastResult.HasMoreRows) then
  begin
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
    Exit;
  end;

  if not EnsureSessionConnected then
    Exit;
  Result := FSession.ExecuteSQL(ASQL, False, 0);
end;

function TSqlEditorFrame.TryExtractSingleTableFromSelect(const ASQL: string): string;
var
  CleanSQL, UpperSQL, AfterFrom, Tok: string;
  P, ParenDepth, I, Len: Integer;
  InSingle: Boolean;
begin
  Result := '';
  CleanSQL := Trim(StripLeadingSqlComments(ASQL));
  if CleanSQL = '' then
    Exit;
  UpperSQL := UpperCase(CleanSQL);
  if Pos('SELECT', UpperSQL) <> 1 then
    Exit;
  if (Pos(' JOIN ', UpperSQL) > 0) or (Pos(' UNION ', UpperSQL) > 0) then
    Exit;

  { Find top-level FROM }
  ParenDepth := 0;
  InSingle := False;
  Len := Length(CleanSQL);
  P := 0;
  I := 1;
  while I <= Len do
  begin
    if CleanSQL[I] = '''' then
      InSingle := not InSingle
    else if not InSingle then
    begin
      if CleanSQL[I] = '(' then
        Inc(ParenDepth)
      else if (CleanSQL[I] = ')') and (ParenDepth > 0) then
        Dec(ParenDepth)
      else if (ParenDepth = 0) and (I + 4 <= Len) and
              (UpperCase(Copy(CleanSQL, I, 4)) = 'FROM') and
              ((I = 1) or (CleanSQL[I - 1] in [' ', #9, #10, #13])) and
              ((I + 4 > Len) or (CleanSQL[I + 4] in [' ', #9, #10, #13])) then
      begin
        P := I + 4;
        Break;
      end;
    end;
    Inc(I);
  end;
  if P <= 0 then
    Exit;

  AfterFrom := Trim(Copy(CleanSQL, P, MaxInt));
  if (AfterFrom = '') or (AfterFrom[1] = '(') then
    Exit;

  { Extract first identifier (supports "Quoted" or schema.table) }
  Tok := '';
  I := 1;
  Len := Length(AfterFrom);
  while I <= Len do
  begin
    if AfterFrom[I] in [' ', #9, #10, #13, ',', ';', '('] then
      Break;
    Tok := Tok + AfterFrom[I];
    Inc(I);
  end;
  if (Length(Tok) >= 2) and (Tok[1] = '"') and (Tok[Length(Tok)] = '"') then
    Tok := Copy(Tok, 2, Length(Tok) - 2);
  { Reject RDB$ / MON$ / pg_ system tables }
  if (Pos('RDB$', UpperCase(Tok)) = 1) or (Pos('MON$', UpperCase(Tok)) = 1) or
     (Pos('PG_', UpperCase(Tok)) = 1) then
    Exit;

  { Reject comma-joins like FROM A, B or FROM A aliasA, B aliasB }
  while (I <= Len) and (AfterFrom[I] in [' ', #9, #10, #13]) do
    Inc(I);
  if (I <= Len) and (AfterFrom[I] = ',') then
    Exit;
  if (I <= Len) and not (AfterFrom[I] in [';', '(', ')']) then
  begin
    { Skip optional alias }
    while (I <= Len) and not (AfterFrom[I] in [' ', #9, #10, #13, ',', ';']) do
      Inc(I);
    while (I <= Len) and (AfterFrom[I] in [' ', #9, #10, #13]) do
      Inc(I);
    if (I <= Len) and (AfterFrom[I] = ',') then
      Exit;
  end;

  Result := Tok;
end;

function TSqlEditorFrame.HandleGridUpdateCell(
  const ARowIndex, AColIndex: Integer;
  const AOldRow: TQueryRow;
  const ANewIsNull: Boolean;
  const ANewValue: string;
  out AError: string
): Boolean;
var
  Profile: TConnectionProfile;
  ExecutedSQL: string;
begin
  Result := False;
  AError := '';
  if FIsExecuting then
  begin
    AError := 'Aguarde a conclusão da execução em andamento.';
    Exit;
  end;
  Profile := SelectedProfile;
  if (Profile = nil) or (FLastResult = nil) or (FDmlHelper = nil) then
  begin
    AError := 'Tabela editável não identificada.';
    Exit;
  end;
  if not EnsureSessionConnected then
  begin
    AError := 'Não foi possível conectar à sessão.';
    Exit;
  end;

  Result := FDmlHelper.ExecuteUpdateCell(
    Profile, FSession, FLastResult, AColIndex, AOldRow,
    ANewIsNull, ANewValue, chkAutoCommit.Checked, ExecutedSQL, AError
  );
  if Result then
    LogMessage('[Grid UPDATE] ' + ExecutedSQL);
  UpdateTransactionUI;
end;

function TSqlEditorFrame.HandleGridInsertRow(
  const ANewRow: TQueryRow;
  out AError: string
): Boolean;
var
  Profile: TConnectionProfile;
  ExecutedSQL: string;
begin
  Result := False;
  AError := '';
  if FIsExecuting then
  begin
    AError := 'Aguarde a conclusão da execução em andamento.';
    Exit;
  end;
  Profile := SelectedProfile;
  if (Profile = nil) or (FLastResult = nil) or (FDmlHelper = nil) then
  begin
    AError := 'Tabela editável não identificada.';
    Exit;
  end;
  if not EnsureSessionConnected then
  begin
    AError := 'Não foi possível conectar à sessão.';
    Exit;
  end;

  Result := FDmlHelper.ExecuteInsertRow(
    Profile, FSession, FLastResult, ANewRow, chkAutoCommit.Checked, ExecutedSQL, AError
  );
  if Result then
    LogMessage('[Grid INSERT] ' + ExecutedSQL);
  UpdateTransactionUI;
end;

function TSqlEditorFrame.HandleGridDeleteRow(
  const AOldRow: TQueryRow;
  out AError: string
): Boolean;
var
  Profile: TConnectionProfile;
  ExecutedSQL: string;
begin
  Result := False;
  AError := '';
  if FIsExecuting then
  begin
    AError := 'Aguarde a conclusão da execução em andamento.';
    Exit;
  end;
  Profile := SelectedProfile;
  if (Profile = nil) or (FLastResult = nil) or (FDmlHelper = nil) then
  begin
    AError := 'Tabela editável não identificada.';
    Exit;
  end;
  if not EnsureSessionConnected then
  begin
    AError := 'Não foi possível conectar à sessão.';
    Exit;
  end;

  Result := FDmlHelper.ExecuteDeleteRow(
    Profile, FSession, FLastResult, AOldRow, chkAutoCommit.Checked, ExecutedSQL, AError
  );
  if Result then
    LogMessage('[Grid DELETE] ' + ExecutedSQL);
  UpdateTransactionUI;
end;

procedure TSqlEditorFrame.HandleOpenObjectLink(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind;
  const AObjectName: string
);
begin
  if Assigned(FOnOpenObject) then
    FOnOpenObject(AProfile, AKind, AObjectName);
end;

procedure TSqlEditorFrame.PopulateExplainTree(
  const ARoot: TExplainPlanNode;
  const ASummary: TExplainPlanSummary
);
  procedure AddNode(const AParentTree: TTreeNode; const APlanNode: TExplainPlanNode);
  var
    TN: TTreeNode;
    Child: TExplainPlanNode;
    TagFlags: PtrInt;
  begin
    if APlanNode = nil then
      Exit;
    TagFlags := 0;
    if APlanNode.IsFullScan then
      TagFlags := TagFlags or 1;
    if APlanNode.HasMemoryBottleneck then
      TagFlags := TagFlags or 2;
    TN := tvExplainVisual.Items.AddChildObject(
      AParentTree,
      APlanNode.DisplayText(ASummary.RootCost),
      Pointer(TagFlags)
    );
    for Child in APlanNode.Children do
      AddNode(TN, Child);
  end;
begin
  if tvExplainVisual = nil then
    Exit;
  tvExplainVisual.Items.BeginUpdate;
  try
    tvExplainVisual.Items.Clear;
    if ARoot <> nil then
    begin
      AddNode(nil, ARoot);
      tvExplainVisual.FullExpand;
    end;
  finally
    tvExplainVisual.Items.EndUpdate;
  end;
end;

procedure TSqlEditorFrame.tvExplainVisualCustomDrawItem(
  Sender: TCustomTreeView;
  Node: TTreeNode;
  State: TCustomDrawState;
  var DefaultDraw: Boolean
);
var
  Flags: PtrInt;
begin
  DefaultDraw := True;
  if (Node = nil) or (cdsSelected in State) then
    Exit;
  Flags := PtrInt(Node.Data);
  if (Flags and 1) <> 0 then
  begin
    Sender.Canvas.Font.Color := clMaroon;
    Sender.Canvas.Font.Style := [fsBold];
  end
  else if (Flags and 2) <> 0 then
  begin
    Sender.Canvas.Font.Color := clNavy;
    Sender.Canvas.Font.Style := [fsBold];
  end;
end;

procedure TSqlEditorFrame.btnRunExplainClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  SQLToExplain, ExplainSQL, JsonText: string;
  Res: TQueryResult;
  I: Integer;
  RootNode: TExplainPlanNode;
  Sum: TExplainPlanSummary;
begin
  if FIsExecuting then
    Exit;
  Profile := SelectedProfile;
  if Profile = nil then
  begin
    MessageDlg('Plano Visual', 'Selecione uma conexão antes de analisar.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if SynEdit1.SelAvail then
    SQLToExplain := Trim(SynEdit1.SelText)
  else
    SQLToExplain := Trim(SynEdit1.Lines.Text);
  if SQLToExplain = '' then
  begin
    MessageDlg('Plano Visual', 'Digite uma consulta SQL para analisar.', mtInformation, [mbOK], 0);
    Exit;
  end;
  while (SQLToExplain <> '') and (SQLToExplain[Length(SQLToExplain)] = ';') do
    SQLToExplain := TrimRight(Copy(SQLToExplain, 1, Length(SQLToExplain) - 1));

  if Profile.DatabaseType = dtFirebird then
  begin
    ExecuteCurrentSQL;
    pgBottom.ActivePage := tsPerformance;
    Exit;
  end;

  if not EnsureSessionConnected then
    Exit;

  if Profile.DatabaseType = dtPostgreSQL then
    ExplainSQL := 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + SQLToExplain
  else
    ExplainSQL := 'EXPLAIN FORMAT=JSON ' + SQLToExplain;

  Screen.Cursor := crHourGlass;
  try
    Res := FSession.ExecuteSQL(ExplainSQL, False, 0);
    try
      if (Res = nil) or (not Res.Success) then
      begin
        if Res <> nil then
          MessageDlg('Erro no EXPLAIN', Res.MessageText, mtError, [mbOK], 0);
        Exit;
      end;

      JsonText := '';
      for I := 0 to Res.RowCount - 1 do
      begin
        if JsonText <> '' then
          JsonText := JsonText + LineEnding;
        JsonText := JsonText + Res.GetRow(I)[0].AsText;
      end;

      memPerfPlan.Lines.Text := JsonText;
      if Profile.DatabaseType = dtPostgreSQL then
        RootNode := TExplainPlanParser.ParsePostgresJson(JsonText, Sum)
      else
        RootNode := TExplainPlanParser.ParseMariaDbJson(JsonText, Sum);
      try
        PopulateExplainTree(RootNode, Sum);
        lblPerfTiming.Caption := Format(
          'EXPLAIN | Tempo Total: %.2f ms | Custo Raiz: %.2f | Full Scans: %d | Índices: %d | Gargalos Mem/Sort: %d',
          [Sum.TotalTimeMs, Sum.RootCost, Sum.FullScanCount, Sum.IndexScanCount, Sum.MemoryBottleneckCount]
        );
        if Sum.FullScanCount > 0 then
          tsPerformance.Caption := Format('Performance (!%d Full Scan)', [Sum.FullScanCount])
        else
          tsPerformance.Caption := 'Performance (OK)';
      finally
        RootNode.Free;
      end;
      pgBottom.ActivePage := tsPerformance;
    finally
      Res.Free;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

end.
