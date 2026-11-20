unit Presentation.DatabaseMonitorFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Grids,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.MonitoringTypes,
  Domain.Interfaces,
  Application.DatabaseMonitoringUseCase;

type
  { Frame de monitoramento em tempo real de conexões, transações e consultas (estilo IBExpert) }
  TDatabaseMonitorFrame = class(TFrame)
    pnlToolbar: TFlowPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    btnRefresh: TButton;
    chkAutoRefresh: TCheckBox;
    cbInterval: TComboBox;
    lblFilter: TLabel;
    edtFilter: TEdit;
    lblStatus: TLabel;
    pgMonitor: TPageControl;
    tsConnections: TTabSheet;
    pnlConnBar: TPanel;
    btnKillConnection: TButton;
    grdConnections: TStringGrid;
    tsTransactions: TTabSheet;
    pnlTxBar: TPanel;
    btnCancelTxQuery: TButton;
    btnKillTx: TButton;
    grdTransactions: TStringGrid;
    splTx: TSplitter;
    memTxSql: TMemo;
    tsStatements: TTabSheet;
    pnlStmtBar: TPanel;
    btnCancelStmt: TButton;
    grdStatements: TStringGrid;
    splStmt: TSplitter;
    memStmtSql: TMemo;
    tmrRefresh: TTimer;
    procedure pnlToolbarResize(Sender: TObject);
    procedure cbConnectionChange(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure chkAutoRefreshChange(Sender: TObject);
    procedure cbIntervalChange(Sender: TObject);
    procedure edtFilterChange(Sender: TObject);
    procedure btnKillConnectionClick(Sender: TObject);
    procedure grdConnectionsPrepareCanvas(sender: TObject; aCol, aRow: Integer;
      aState: TGridDrawState);
    procedure grdConnectionsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure btnCancelTxQueryClick(Sender: TObject);
    procedure btnKillTxClick(Sender: TObject);
    procedure grdTransactionsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure btnCancelStmtClick(Sender: TObject);
    procedure grdStatementsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure tmrRefreshTimer(Sender: TObject);
  private
    FFactory: IDatabaseProviderFactory;
    FMonitorUseCase: TDatabaseMonitoringUseCase;
    FProfiles: TConnectionProfileList;
    FActiveProfileId: string;
    FSession: IDatabaseSession;
    FSnapshot: TMonitoringSnapshot;
    FVisibleConnIndices: array of Integer;
    FVisibleTxIndices: array of Integer;
    FVisibleStmtIndices: array of Integer;
    FIsRefreshing: Boolean;
    FUpdatingToolbarSize: Boolean;
    FLastToolbarWidth: Integer;
    function SelectedProfile: TConnectionProfile;
    function SelectedConnectionId(out AIsCurrent: Boolean): Int64;
    function SelectedTransaction(out ATx: TMonitoredTransaction): Boolean;
    function SelectedStatement(out AStmt: TMonitoredStatement): Boolean;
    function SingleLinePreview(const ASQL: string; const AMaxLen: Integer = 120): string;
    function MatchesFilter(const AValues: array of string): Boolean;
    procedure UpdateToolbarLayout;
    procedure ApplyTimerSettings;
    procedure DisconnectSession;
    procedure SetupGridHeaders;
    procedure AutoFitGrid(const AGrid: TStringGrid);
    procedure PopulateGridsFromSnapshot;
    procedure UpdateSelectedDetails;
    procedure RefreshSnapshot(const AFromTimer: Boolean);
  public
    destructor Destroy; override;
    procedure Initialize(
      const AFactory: IDatabaseProviderFactory;
      const AMonitorUseCase: TDatabaseMonitoringUseCase;
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string = ''
    );
    procedure RefreshConnections(const AConnections: TConnectionProfileList);
    function ActiveProfileId: string;
    function IsConnected: Boolean;
    procedure Disconnect;
  end;

implementation

{$R *.lfm}

destructor TDatabaseMonitorFrame.Destroy;
begin
  if tmrRefresh <> nil then
    tmrRefresh.Enabled := False;
  DisconnectSession;
  FreeAndNil(FSnapshot);
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TDatabaseMonitorFrame.UpdateToolbarLayout;
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
end;

procedure TDatabaseMonitorFrame.ApplyTimerSettings;
var
  Sec: Integer;
  S: string;
begin
  S := StringReplace(Trim(cbInterval.Text), 's', '', [rfReplaceAll, rfIgnoreCase]);
  Sec := StrToIntDef(S, 3);
  if Sec < 1 then
    Sec := 3;
  tmrRefresh.Interval := Sec * 1000;
  tmrRefresh.Enabled := chkAutoRefresh.Checked and (SelectedProfile <> nil);
end;

procedure TDatabaseMonitorFrame.DisconnectSession;
begin
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
end;

procedure TDatabaseMonitorFrame.SetupGridHeaders;
begin
  grdConnections.ColCount := 9;
  grdConnections.FixedCols := 0;
  grdConnections.FixedRows := 1;
  grdConnections.Cells[0, 0] := 'ID';
  grdConnections.Cells[1, 0] := 'Usuário';
  grdConnections.Cells[2, 0] := 'Estado';
  grdConnections.Cells[3, 0] := 'Data / Hora Início';
  grdConnections.Cells[4, 0] := 'IP Remoto';
  grdConnections.Cells[5, 0] := 'Aplicação / Processo';
  grdConnections.Cells[6, 0] := 'PID Remoto';
  grdConnections.Cells[7, 0] := 'PID Servidor';
  grdConnections.Cells[8, 0] := 'Sessão Atual';

  grdTransactions.ColCount := 10;
  grdTransactions.FixedCols := 0;
  grdTransactions.FixedRows := 1;
  grdTransactions.Cells[0, 0] := 'ID Transação';
  grdTransactions.Cells[1, 0] := 'ID Conexão';
  grdTransactions.Cells[2, 0] := 'Usuário';
  grdTransactions.Cells[3, 0] := 'Estado';
  grdTransactions.Cells[4, 0] := 'Data / Hora Início';
  grdTransactions.Cells[5, 0] := 'Isolamento';
  grdTransactions.Cells[6, 0] := 'Modo';
  grdTransactions.Cells[7, 0] := 'IP Remoto';
  grdTransactions.Cells[8, 0] := 'Aplicação';
  grdTransactions.Cells[9, 0] := 'SQL (resumo)';

  grdStatements.ColCount := 9;
  grdStatements.FixedCols := 0;
  grdStatements.FixedRows := 1;
  grdStatements.Cells[0, 0] := 'ID Statement';
  grdStatements.Cells[1, 0] := 'ID Conexão';
  grdStatements.Cells[2, 0] := 'ID Transação';
  grdStatements.Cells[3, 0] := 'Usuário';
  grdStatements.Cells[4, 0] := 'Estado';
  grdStatements.Cells[5, 0] := 'Data / Hora Início';
  grdStatements.Cells[6, 0] := 'IP Remoto';
  grdStatements.Cells[7, 0] := 'Aplicação';
  grdStatements.Cells[8, 0] := 'SQL';
end;

procedure TDatabaseMonitorFrame.Initialize(
  const AFactory: IDatabaseProviderFactory;
  const AMonitorUseCase: TDatabaseMonitoringUseCase;
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string
);
begin
  FFactory := AFactory;
  FMonitorUseCase := AMonitorUseCase;
  FActiveProfileId := AInitialProfileId;
  FIsRefreshing := False;
  FUpdatingToolbarSize := False;
  FLastToolbarWidth := -1;
  FSnapshot := TMonitoringSnapshot.Create;

  {$IFDEF UNIX}
  memTxSql.Font.Name := 'Monospace';
  memStmtSql.Font.Name := 'Monospace';
  {$ENDIF}

  SetupGridHeaders;
  RefreshConnections(AConnections);
  UpdateToolbarLayout;
  ApplyTimerSettings;

  if SelectedProfile <> nil then
    RefreshSnapshot(False);
end;

procedure TDatabaseMonitorFrame.RefreshConnections(const AConnections: TConnectionProfileList);
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
      FActiveProfileId := SelectedProfile.Id;
  finally
    cbConnection.Items.EndUpdate;
  end;
end;

function TDatabaseMonitorFrame.ActiveProfileId: string;
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    Result := Profile.Id
  else
    Result := FActiveProfileId;
end;

function TDatabaseMonitorFrame.IsConnected: Boolean;
begin
  Result := (FSession <> nil) and FSession.IsConnected;
end;

procedure TDatabaseMonitorFrame.Disconnect;
begin
  if tmrRefresh <> nil then
    tmrRefresh.Enabled := False;
  if chkAutoRefresh <> nil then
    chkAutoRefresh.Checked := False;
  DisconnectSession;
  lblStatus.Caption := 'Desconectado';
  lblStatus.Font.Color := clGrayText;
  UpdateToolbarLayout;
end;

function TDatabaseMonitorFrame.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection.ItemIndex >= 0) and (cbConnection.ItemIndex < cbConnection.Items.Count) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

function TDatabaseMonitorFrame.SingleLinePreview(const ASQL: string; const AMaxLen: Integer): string;
begin
  Result := Trim(StringReplace(StringReplace(ASQL, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  if Length(Result) > AMaxLen then
    Result := Copy(Result, 1, AMaxLen - 3) + '...';
end;

function TDatabaseMonitorFrame.MatchesFilter(const AValues: array of string): Boolean;
var
  FilterText: string;
  I: Integer;
begin
  FilterText := LowerCase(Trim(edtFilter.Text));
  if FilterText = '' then
    Exit(True);

  for I := Low(AValues) to High(AValues) do
  begin
    if Pos(FilterText, LowerCase(AValues[I])) > 0 then
      Exit(True);
  end;
  Result := False;
end;

procedure TDatabaseMonitorFrame.AutoFitGrid(const AGrid: TStringGrid);
var
  C, R, MaxRows, ColW, W: Integer;
begin
  if (AGrid = nil) or (not AGrid.HandleAllocated) then
    Exit;

  MaxRows := AGrid.RowCount - 1;
  if MaxRows > 60 then
    MaxRows := 60;

  AGrid.Canvas.Font.Assign(AGrid.Font);
  for C := 0 to AGrid.ColCount - 1 do
  begin
    AGrid.Canvas.Font.Style := [fsBold];
    ColW := AGrid.Canvas.TextWidth(AGrid.Cells[C, 0]) + 20;
    AGrid.Canvas.Font.Style := [];
    for R := 1 to MaxRows do
    begin
      W := AGrid.Canvas.TextWidth(AGrid.Cells[C, R]) + 18;
      if W > ColW then
        ColW := W;
    end;
    if ColW < 70 then
      ColW := 70
    else if ColW > 360 then
      ColW := 360;
    AGrid.ColWidths[C] := ColW;
  end;
end;

procedure TDatabaseMonitorFrame.PopulateGridsFromSnapshot;
var
  I, RowIdx, RestoreRow: Integer;
  PrevConnId, PrevTxId, PrevStmtId: Int64;
  PrevIsCur: Boolean;
  PrevTx: TMonitoredTransaction;
  PrevStmt: TMonitoredStatement;
  ConnItem: TMonitoredConnection;
  TxItem: TMonitoredTransaction;
  StmtItem: TMonitoredStatement;
  CurStr: string;
begin
  PrevConnId := SelectedConnectionId(PrevIsCur);
  if not SelectedTransaction(PrevTx) then
    PrevTxId := -1
  else
    PrevTxId := PrevTx.TransactionId;
  if not SelectedStatement(PrevStmt) then
    PrevStmtId := -1
  else
    PrevStmtId := PrevStmt.StatementId;

  { 1. Conexões }
  SetLength(FVisibleConnIndices, 0);
  if FSnapshot <> nil then
  begin
    for I := 0 to High(FSnapshot.Connections) do
    begin
      ConnItem := FSnapshot.Connections[I];
      if MatchesFilter([
        IntToStr(ConnItem.ConnectionId), ConnItem.UserName, ConnItem.State,
        ConnItem.StartedAt, ConnItem.RemoteAddress, ConnItem.ClientProcess
      ]) then
      begin
        RowIdx := Length(FVisibleConnIndices);
        SetLength(FVisibleConnIndices, RowIdx + 1);
        FVisibleConnIndices[RowIdx] := I;
      end;
    end;
  end;

  grdConnections.BeginUpdate;
  try
    grdConnections.RowCount := Length(FVisibleConnIndices) + 1;
    RestoreRow := 1;
    for I := 0 to High(FVisibleConnIndices) do
    begin
      ConnItem := FSnapshot.Connections[FVisibleConnIndices[I]];
      RowIdx := I + 1;
      if ConnItem.IsCurrent then
        CurStr := 'Sim (Monitor)'
      else
        CurStr := '';
      grdConnections.Cells[0, RowIdx] := IntToStr(ConnItem.ConnectionId);
      grdConnections.Cells[1, RowIdx] := ConnItem.UserName;
      grdConnections.Cells[2, RowIdx] := ConnItem.State;
      grdConnections.Cells[3, RowIdx] := ConnItem.StartedAt;
      grdConnections.Cells[4, RowIdx] := ConnItem.RemoteAddress;
      grdConnections.Cells[5, RowIdx] := ConnItem.ClientProcess;
      grdConnections.Cells[6, RowIdx] := ConnItem.RemotePid;
      grdConnections.Cells[7, RowIdx] := ConnItem.ServerPid;
      grdConnections.Cells[8, RowIdx] := CurStr;
      if (PrevConnId > 0) and (ConnItem.ConnectionId = PrevConnId) then
        RestoreRow := RowIdx;
    end;
    if grdConnections.RowCount > 1 then
      grdConnections.Row := RestoreRow;
  finally
    grdConnections.EndUpdate;
  end;
  if grdConnections.Tag = 0 then
  begin
    AutoFitGrid(grdConnections);
    if grdConnections.RowCount > 1 then
      grdConnections.Tag := 1;
  end;

  { 2. Transações }
  SetLength(FVisibleTxIndices, 0);
  if FSnapshot <> nil then
  begin
    for I := 0 to High(FSnapshot.Transactions) do
    begin
      TxItem := FSnapshot.Transactions[I];
      if MatchesFilter([
        IntToStr(TxItem.TransactionId), IntToStr(TxItem.ConnectionId), TxItem.UserName,
        TxItem.State, TxItem.StartedAt, TxItem.IsolationMode, TxItem.RemoteAddress,
        TxItem.ClientProcess, TxItem.SqlText
      ]) then
      begin
        RowIdx := Length(FVisibleTxIndices);
        SetLength(FVisibleTxIndices, RowIdx + 1);
        FVisibleTxIndices[RowIdx] := I;
      end;
    end;
  end;

  grdTransactions.BeginUpdate;
  try
    grdTransactions.RowCount := Length(FVisibleTxIndices) + 1;
    RestoreRow := 1;
    for I := 0 to High(FVisibleTxIndices) do
    begin
      TxItem := FSnapshot.Transactions[FVisibleTxIndices[I]];
      RowIdx := I + 1;
      grdTransactions.Cells[0, RowIdx] := IntToStr(TxItem.TransactionId);
      grdTransactions.Cells[1, RowIdx] := IntToStr(TxItem.ConnectionId);
      grdTransactions.Cells[2, RowIdx] := TxItem.UserName;
      grdTransactions.Cells[3, RowIdx] := TxItem.State;
      grdTransactions.Cells[4, RowIdx] := TxItem.StartedAt;
      grdTransactions.Cells[5, RowIdx] := TxItem.IsolationMode;
      grdTransactions.Cells[6, RowIdx] := TxItem.ReadOnlyStr;
      grdTransactions.Cells[7, RowIdx] := TxItem.RemoteAddress;
      grdTransactions.Cells[8, RowIdx] := TxItem.ClientProcess;
      grdTransactions.Cells[9, RowIdx] := SingleLinePreview(TxItem.SqlText);
      if (PrevTxId > 0) and (TxItem.TransactionId = PrevTxId) then
        RestoreRow := RowIdx;
    end;
    if grdTransactions.RowCount > 1 then
      grdTransactions.Row := RestoreRow;
  finally
    grdTransactions.EndUpdate;
  end;
  if grdTransactions.Tag = 0 then
  begin
    AutoFitGrid(grdTransactions);
    if grdTransactions.RowCount > 1 then
      grdTransactions.Tag := 1;
  end;

  { 3. Consultas Ativas / Statements }
  SetLength(FVisibleStmtIndices, 0);
  if FSnapshot <> nil then
  begin
    for I := 0 to High(FSnapshot.Statements) do
    begin
      StmtItem := FSnapshot.Statements[I];
      if MatchesFilter([
        IntToStr(StmtItem.StatementId), IntToStr(StmtItem.ConnectionId),
        IntToStr(StmtItem.TransactionId), StmtItem.UserName, StmtItem.State,
        StmtItem.StartedAt, StmtItem.RemoteAddress, StmtItem.ClientProcess, StmtItem.SqlText
      ]) then
      begin
        RowIdx := Length(FVisibleStmtIndices);
        SetLength(FVisibleStmtIndices, RowIdx + 1);
        FVisibleStmtIndices[RowIdx] := I;
      end;
    end;
  end;

  grdStatements.BeginUpdate;
  try
    grdStatements.RowCount := Length(FVisibleStmtIndices) + 1;
    RestoreRow := 1;
    for I := 0 to High(FVisibleStmtIndices) do
    begin
      StmtItem := FSnapshot.Statements[FVisibleStmtIndices[I]];
      RowIdx := I + 1;
      grdStatements.Cells[0, RowIdx] := IntToStr(StmtItem.StatementId);
      grdStatements.Cells[1, RowIdx] := IntToStr(StmtItem.ConnectionId);
      grdStatements.Cells[2, RowIdx] := IntToStr(StmtItem.TransactionId);
      grdStatements.Cells[3, RowIdx] := StmtItem.UserName;
      grdStatements.Cells[4, RowIdx] := StmtItem.State;
      grdStatements.Cells[5, RowIdx] := StmtItem.StartedAt;
      grdStatements.Cells[6, RowIdx] := StmtItem.RemoteAddress;
      grdStatements.Cells[7, RowIdx] := StmtItem.ClientProcess;
      grdStatements.Cells[8, RowIdx] := SingleLinePreview(StmtItem.SqlText, 160);
      if (PrevStmtId > 0) and (StmtItem.StatementId = PrevStmtId) then
        RestoreRow := RowIdx;
    end;
    if grdStatements.RowCount > 1 then
      grdStatements.Row := RestoreRow;
  finally
    grdStatements.EndUpdate;
  end;
  if grdStatements.Tag = 0 then
  begin
    AutoFitGrid(grdStatements);
    if grdStatements.RowCount > 1 then
      grdStatements.Tag := 1;
  end;

  tsConnections.Caption := Format('Conexões (%d)', [Length(FVisibleConnIndices)]);
  tsTransactions.Caption := Format('Transações (%d)', [Length(FVisibleTxIndices)]);
  tsStatements.Caption := Format('Consultas Ativas (%d)', [Length(FVisibleStmtIndices)]);

  UpdateSelectedDetails;
end;

function TDatabaseMonitorFrame.SelectedConnectionId(out AIsCurrent: Boolean): Int64;
var
  Idx: Integer;
begin
  Result := -1;
  AIsCurrent := False;
  Idx := grdConnections.Row - 1;
  if (FSnapshot <> nil) and (Idx >= 0) and (Idx <= High(FVisibleConnIndices)) then
  begin
    Result := FSnapshot.Connections[FVisibleConnIndices[Idx]].ConnectionId;
    AIsCurrent := FSnapshot.Connections[FVisibleConnIndices[Idx]].IsCurrent;
  end;
end;

function TDatabaseMonitorFrame.SelectedTransaction(out ATx: TMonitoredTransaction): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  FillChar(ATx, SizeOf(ATx), 0);
  Idx := grdTransactions.Row - 1;
  if (FSnapshot <> nil) and (Idx >= 0) and (Idx <= High(FVisibleTxIndices)) then
  begin
    ATx := FSnapshot.Transactions[FVisibleTxIndices[Idx]];
    Result := True;
  end;
end;

function TDatabaseMonitorFrame.SelectedStatement(out AStmt: TMonitoredStatement): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  FillChar(AStmt, SizeOf(AStmt), 0);
  Idx := grdStatements.Row - 1;
  if (FSnapshot <> nil) and (Idx >= 0) and (Idx <= High(FVisibleStmtIndices)) then
  begin
    AStmt := FSnapshot.Statements[FVisibleStmtIndices[Idx]];
    Result := True;
  end;
end;

procedure TDatabaseMonitorFrame.UpdateSelectedDetails;
var
  ConnId: Int64;
  IsCur: Boolean;
  Tx: TMonitoredTransaction;
  Stmt: TMonitoredStatement;
begin
  ConnId := SelectedConnectionId(IsCur);
  btnKillConnection.Enabled := (ConnId > 0) and (not IsCur);

  if SelectedTransaction(Tx) then
  begin
    memTxSql.Lines.Text := Tx.SqlText;
    btnKillTx.Enabled := not Tx.IsCurrentConnection;
    btnCancelTxQuery.Enabled := (not Tx.IsCurrentConnection) and (Tx.StatementId > 0);
  end
  else
  begin
    memTxSql.Clear;
    btnKillTx.Enabled := False;
    btnCancelTxQuery.Enabled := False;
  end;

  if SelectedStatement(Stmt) then
  begin
    memStmtSql.Lines.Text := Stmt.SqlText;
    btnCancelStmt.Enabled := (not Stmt.IsCurrentConnection) and (Stmt.StatementId > 0);
  end
  else
  begin
    memStmtSql.Clear;
    btnCancelStmt.Enabled := False;
  end;
end;

procedure TDatabaseMonitorFrame.RefreshSnapshot(const AFromTimer: Boolean);
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
  NewSnap: TMonitoringSnapshot;
begin
  if FIsRefreshing or (FMonitorUseCase = nil) or (FFactory = nil) then
    Exit;

  Profile := SelectedProfile;
  if Profile = nil then
  begin
    lblStatus.Caption := 'Selecione uma conexão.';
    lblStatus.Font.Color := clGrayText;
    Exit;
  end;

  FIsRefreshing := True;
  try
    try
      if FSession = nil then
      begin
        Provider := FFactory.GetProvider(Profile.DatabaseType);
        FSession := Provider.CreateSession(Profile);
      end;
      NewSnap := FMonitorUseCase.CaptureSnapshot(FSession, Profile.DatabaseType);
      FreeAndNil(FSnapshot);
      FSnapshot := NewSnap;
      PopulateGridsFromSnapshot;
      lblStatus.Caption := Format('Atualizado: %s', [FormatDateTime('hh:nn:ss', FSnapshot.CapturedAt)]);
      lblStatus.Font.Color := clGreen;
      UpdateToolbarLayout;
    except
      on E: Exception do
      begin
        lblStatus.Caption := 'Erro: ' + SingleLinePreview(E.Message, 70);
        lblStatus.Font.Color := clMaroon;
        UpdateToolbarLayout;
        if AFromTimer then
        begin
          chkAutoRefresh.Checked := False;
          tmrRefresh.Enabled := False;
        end
        else
          MessageDlg('Erro no Database Monitoring', E.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    FIsRefreshing := False;
  end;
end;

procedure TDatabaseMonitorFrame.pnlToolbarResize(Sender: TObject);
begin
  if (not FUpdatingToolbarSize) and (pnlToolbar.Width <> FLastToolbarWidth) then
    UpdateToolbarLayout;
end;

procedure TDatabaseMonitorFrame.cbConnectionChange(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if (Profile <> nil) and SameText(Profile.Id, FActiveProfileId) then
    Exit;

  DisconnectSession;
  if FSnapshot <> nil then
    FSnapshot.Clear;
  grdConnections.Tag := 0;
  grdTransactions.Tag := 0;
  grdStatements.Tag := 0;
  PopulateGridsFromSnapshot;

  if Profile <> nil then
    FActiveProfileId := Profile.Id
  else
    FActiveProfileId := '';

  ApplyTimerSettings;
  if Profile <> nil then
    RefreshSnapshot(False);
end;

procedure TDatabaseMonitorFrame.btnRefreshClick(Sender: TObject);
begin
  RefreshSnapshot(False);
end;

procedure TDatabaseMonitorFrame.chkAutoRefreshChange(Sender: TObject);
begin
  ApplyTimerSettings;
end;

procedure TDatabaseMonitorFrame.cbIntervalChange(Sender: TObject);
begin
  ApplyTimerSettings;
end;

procedure TDatabaseMonitorFrame.edtFilterChange(Sender: TObject);
begin
  PopulateGridsFromSnapshot;
end;

procedure TDatabaseMonitorFrame.tmrRefreshTimer(Sender: TObject);
begin
  RefreshSnapshot(True);
end;

procedure TDatabaseMonitorFrame.grdConnectionsPrepareCanvas(sender: TObject; aCol, aRow: Integer;
  aState: TGridDrawState);
var
  Idx: Integer;
begin
  if (aRow >= 1) and (not (gdSelected in aState)) and (FSnapshot <> nil) then
  begin
    Idx := aRow - 1;
    if (Idx >= 0) and (Idx <= High(FVisibleConnIndices)) then
    begin
      if FSnapshot.Connections[FVisibleConnIndices[Idx]].IsCurrent then
      begin
        grdConnections.Canvas.Font.Color := clGrayText;
        grdConnections.Canvas.Font.Style := [fsItalic];
      end
      else if SameText(FSnapshot.Connections[FVisibleConnIndices[Idx]].State, 'Ativa') or
              SameText(FSnapshot.Connections[FVisibleConnIndices[Idx]].State, 'active') then
      begin
        if aCol = 2 then
        begin
          grdConnections.Canvas.Font.Color := clGreen;
          grdConnections.Canvas.Font.Style := [fsBold];
        end;
      end;
    end;
  end;
end;

procedure TDatabaseMonitorFrame.grdConnectionsSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateSelectedDetails;
end;

procedure TDatabaseMonitorFrame.grdTransactionsSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateSelectedDetails;
end;

procedure TDatabaseMonitorFrame.grdStatementsSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateSelectedDetails;
end;

procedure TDatabaseMonitorFrame.btnKillConnectionClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  ConnId: Int64;
  IsCur, WasTimerEnabled: Boolean;
  Msg: string;
begin
  Profile := SelectedProfile;
  ConnId := SelectedConnectionId(IsCur);
  if (Profile = nil) or (ConnId <= 0) then
    Exit;

  if IsCur then
  begin
    MessageDlg('Aviso', 'Não é possível encerrar a própria conexão do monitor.', mtInformation, [mbOK], 0);
    Exit;
  end;

  WasTimerEnabled := tmrRefresh.Enabled;
  tmrRefresh.Enabled := False;
  try
    if MessageDlg('Encerrar Conexão',
      Format('Deseja realmente encerrar a conexão #%d? Todas as transações abertas nela sofrerão rollback.', [ConnId]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    if FMonitorUseCase.TerminateConnection(FSession, Profile.DatabaseType, ConnId, Msg) then
    begin
      lblStatus.Caption := Msg;
      lblStatus.Font.Color := clGreen;
      RefreshSnapshot(False);
    end
    else
      MessageDlg('Erro ao encerrar conexão', Msg, mtError, [mbOK], 0);
  finally
    tmrRefresh.Enabled := WasTimerEnabled and chkAutoRefresh.Checked;
  end;
end;

procedure TDatabaseMonitorFrame.btnCancelTxQueryClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  Tx: TMonitoredTransaction;
  WasTimerEnabled: Boolean;
  Msg: string;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (not SelectedTransaction(Tx)) then
    Exit;

  if Tx.IsCurrentConnection then
  begin
    MessageDlg('Aviso', 'Não é possível cancelar a própria sessão do monitor.', mtInformation, [mbOK], 0);
    Exit;
  end;

  WasTimerEnabled := tmrRefresh.Enabled;
  tmrRefresh.Enabled := False;
  try
    if MessageDlg('Cancelar Consulta da Transação',
      Format('Deseja cancelar a consulta em andamento na transação #%d (conexão #%d)?', [Tx.TransactionId, Tx.ConnectionId]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    if FMonitorUseCase.CancelTransaction(FSession, Profile.DatabaseType, Tx.TransactionId, Tx.ConnectionId, False, Msg) then
    begin
      lblStatus.Caption := Msg;
      lblStatus.Font.Color := clGreen;
      RefreshSnapshot(False);
    end
    else
      MessageDlg('Erro ao cancelar consulta', Msg, mtError, [mbOK], 0);
  finally
    tmrRefresh.Enabled := WasTimerEnabled and chkAutoRefresh.Checked;
  end;
end;

procedure TDatabaseMonitorFrame.btnKillTxClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  Tx: TMonitoredTransaction;
  WasTimerEnabled: Boolean;
  PromptText, Msg: string;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (not SelectedTransaction(Tx)) then
    Exit;

  if Tx.IsCurrentConnection then
  begin
    MessageDlg('Aviso', 'Não é possível encerrar a própria sessão do monitor.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if Profile.DatabaseType = dtPostgreSQL then
    PromptText := Format('Deseja encerrar o processo/PID #%d da transação #%d (forçando rollback)?', [Tx.ConnectionId, Tx.TransactionId])
  else
    PromptText := Format('No Firebird, encerrar a transação #%d desconecta a conexão #%d (forçando rollback imediato). Deseja continuar?', [Tx.TransactionId, Tx.ConnectionId]);

  WasTimerEnabled := tmrRefresh.Enabled;
  tmrRefresh.Enabled := False;
  try
    if MessageDlg('Encerrar Transação', PromptText, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    if FMonitorUseCase.CancelTransaction(FSession, Profile.DatabaseType, Tx.TransactionId, Tx.ConnectionId, True, Msg) then
    begin
      lblStatus.Caption := Msg;
      lblStatus.Font.Color := clGreen;
      RefreshSnapshot(False);
    end
    else
      MessageDlg('Erro ao encerrar transação', Msg, mtError, [mbOK], 0);
  finally
    tmrRefresh.Enabled := WasTimerEnabled and chkAutoRefresh.Checked;
  end;
end;

procedure TDatabaseMonitorFrame.btnCancelStmtClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  Stmt: TMonitoredStatement;
  WasTimerEnabled: Boolean;
  Msg: string;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (not SelectedStatement(Stmt)) then
    Exit;

  if Stmt.IsCurrentConnection then
  begin
    MessageDlg('Aviso', 'Não é possível cancelar a própria sessão do monitor.', mtInformation, [mbOK], 0);
    Exit;
  end;

  WasTimerEnabled := tmrRefresh.Enabled;
  tmrRefresh.Enabled := False;
  try
    if MessageDlg('Cancelar Consulta',
      Format('Deseja cancelar a consulta #%d (conexão #%d)?', [Stmt.StatementId, Stmt.ConnectionId]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    if FMonitorUseCase.CancelStatement(FSession, Profile.DatabaseType, Stmt.StatementId, Stmt.ConnectionId, Msg) then
    begin
      lblStatus.Caption := Msg;
      lblStatus.Font.Color := clGreen;
      RefreshSnapshot(False);
    end
    else
      MessageDlg('Erro ao cancelar consulta', Msg, mtError, [mbOK], 0);
  finally
    tmrRefresh.Enabled := WasTimerEnabled and chkAutoRefresh.Checked;
  end;
end;

end.
