unit Presentation.DatabaseComparerFrame;

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
  ExtCtrls,
  StdCtrls,
  ComCtrls,
  Grids,
  LCLType,
  SynEdit,
  SynHighlighterSQL,
  fpjson,
  jsonparser,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.Interfaces,
  Domain.DatabaseCompareTypes,
  Application.DatabaseComparerUseCase;

type
  TOpenSqlInNewTabEvent = procedure(const AProfileId, ATitle, ASqlText: string) of object;

  { Frame visual do Database Comparer (comparação entre 2 bases + script de sincronização) }
  TDatabaseComparerFrame = class(TFrame)
    pnlConnBar: TFlowPanel;
    lblSource: TLabel;
    cbSourceConn: TComboBox;
    btnSwapConns: TButton;
    lblTarget: TLabel;
    cbTargetConn: TComboBox;
    btnCompare: TButton;
    btnCancelOp: TButton;
    lblStatus: TLabel;
    pnlOptionsBar: TFlowPanel;
    chkTables: TCheckBox;
    chkConstraints: TCheckBox;
    chkIndexes: TCheckBox;
    chkGenerators: TCheckBox;
    chkViews: TCheckBox;
    chkProcedures: TCheckBox;
    chkTriggers: TCheckBox;
    chkIncludeDrops: TCheckBox;
    btnSelectAll: TButton;
    btnSelectNone: TButton;
    grdDiffs: TStringGrid;
    splMain: TSplitter;
    pgDetails: TPageControl;
    tsScript: TTabSheet;
    pnlScriptBar: TFlowPanel;
    btnCopyScript: TButton;
    btnSaveScript: TButton;
    btnOpenInEditor: TButton;
    btnExecuteScript: TButton;
    SynEditScript: TSynEdit;
    tsCompareDDL: TTabSheet;
    pnlSrcDDL: TPanel;
    lblSrcDDL: TLabel;
    SynEditSourceDDL: TSynEdit;
    splCompareDDL: TSplitter;
    pnlTgtDDL: TPanel;
    lblTgtDDL: TLabel;
    SynEditTargetDDL: TSynEdit;
    tsLog: TTabSheet;
    memLog: TMemo;
    SynSQLSyn1: TSynSQLSyn;
    dlgSaveSql: TSaveDialog;
    procedure btnSwapConnsClick(Sender: TObject);
    procedure cbSourceConnChange(Sender: TObject);
    procedure cbTargetConnChange(Sender: TObject);
    procedure btnCompareClick(Sender: TObject);
    procedure btnCancelOpClick(Sender: TObject);
    procedure btnSelectAllClick(Sender: TObject);
    procedure btnSelectNoneClick(Sender: TObject);
    procedure grdDiffsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure grdDiffsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure grdDiffsSelectCell(Sender: TObject; aCol, aRow: Integer;
      var CanSelect: Boolean);
    procedure grdDiffsPrepareCanvas(sender: TObject; aCol, aRow: Integer;
      aState: TGridDrawState);
    procedure btnCopyScriptClick(Sender: TObject);
    procedure btnSaveScriptClick(Sender: TObject);
    procedure btnOpenInEditorClick(Sender: TObject);
    procedure btnExecuteScriptClick(Sender: TObject);
    procedure pnlToolbarResize(Sender: TObject);
  private
    FFactory: IDatabaseProviderFactory;
    FProfiles: TConnectionProfileList;
    FSourceProfileId: string;
    FTargetProfileId: string;
    FResult: TCompareResult;
    FCompareWorker: TCompareDatabasesWorker;
    FApplyWorker: TApplyCompareScriptWorker;
    FUpdatingToolbarSize: Boolean;
    FOnOpenSqlInNewTab: TOpenSqlInNewTabEvent;
    procedure LogMessage(const AMsg: string);
    procedure ConfigureGrid;
    procedure UpdateToolbarLayouts;
    procedure UpdateDialectForProfile(const AProfile: TConnectionProfile);
    function SelectedSourceProfile: TConnectionProfile;
    function SelectedTargetProfile: TConnectionProfile;
    function ReadOptionsFromUI: TCompareOptions;
    function SettingsFilePath: string;
    procedure LoadSettings(const APreserveSourceId: Boolean);
    procedure SaveSettings;
    procedure SetRunningState(const ARunning: Boolean; const AStatusText: string);
    procedure PopulateDiffGrid;
    procedure RebuildCombinedScript;
    procedure ShowRowDDL(const ARowIdx: Integer);
    procedure ToggleRowSelection(const ARowIdx: Integer);
    procedure HandleCompareProgress(const AStatusText: string);
    procedure HandleCompareComplete(
      const AWorker: TCompareDatabasesWorker;
      const AResult: TCompareResult;
      const AErrorMessage: string
    );
    procedure HandleApplyProgress(const ALogLine: string);
    procedure HandleApplyComplete(
      const AWorker: TApplyCompareScriptWorker;
      const ASuccess: Boolean;
      const AExecutedCount: Integer;
      const AErrorMessage: string
    );
  public
    destructor Destroy; override;
    procedure Initialize(
      const AFactory: IDatabaseProviderFactory;
      const AConnections: TConnectionProfileList;
      const AInitialSourceId: string = ''
    );
    procedure RefreshConnections(const AConnections: TConnectionProfileList);
    function UsesProfile(const AProfileId: string): Boolean;
    function IsBusy: Boolean;
    procedure DetachAndCancel;
    procedure DisconnectAndCancel;
    property OnOpenSqlInNewTab: TOpenSqlInNewTabEvent
      read FOnOpenSqlInNewTab write FOnOpenSqlInNewTab;
  end;

implementation

{$R *.lfm}

destructor TDatabaseComparerFrame.Destroy;
begin
  SaveSettings;
  DetachAndCancel;
  FreeAndNil(FResult);
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TDatabaseComparerFrame.LogMessage(const AMsg: string);
begin
  memLog.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss', Now), AMsg]));
end;

procedure TDatabaseComparerFrame.ConfigureGrid;
begin
  grdDiffs.ColCount := 5;
  grdDiffs.FixedCols := 0;
  grdDiffs.FixedRows := 1;
  grdDiffs.Cells[0, 0] := 'Aplicar';
  grdDiffs.Cells[1, 0] := 'Categoria';
  grdDiffs.Cells[2, 0] := 'Objeto';
  grdDiffs.Cells[3, 0] := 'Status';
  grdDiffs.Cells[4, 0] := 'Detalhes';
  grdDiffs.ColWidths[0] := 65;
  grdDiffs.ColWidths[1] := 130;
  grdDiffs.ColWidths[2] := 250;
  grdDiffs.ColWidths[3] := 145;
  grdDiffs.ColWidths[4] := 350;
end;

procedure TDatabaseComparerFrame.UpdateToolbarLayouts;
begin
  if FUpdatingToolbarSize then
    Exit;
  FUpdatingToolbarSize := True;
  try
    if pnlConnBar <> nil then
    begin
      pnlConnBar.ReAlign;
      pnlConnBar.InvalidatePreferredSize;
      pnlConnBar.AdjustSize;
    end;
    if pnlOptionsBar <> nil then
    begin
      pnlOptionsBar.ReAlign;
      pnlOptionsBar.InvalidatePreferredSize;
      pnlOptionsBar.AdjustSize;
    end;
    if pnlScriptBar <> nil then
    begin
      pnlScriptBar.ReAlign;
      pnlScriptBar.InvalidatePreferredSize;
      pnlScriptBar.AdjustSize;
    end;
  finally
    FUpdatingToolbarSize := False;
  end;
end;

procedure TDatabaseComparerFrame.pnlToolbarResize(Sender: TObject);
begin
  UpdateToolbarLayouts;
end;

procedure TDatabaseComparerFrame.UpdateDialectForProfile(const AProfile: TConnectionProfile);
begin
  if (AProfile <> nil) and (AProfile.DatabaseType = dtPostgreSQL) then
    SynSQLSyn1.SQLDialect := sqlPostgres
  else
    SynSQLSyn1.SQLDialect := sqlFirebird40;
end;

function TDatabaseComparerFrame.SelectedSourceProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbSourceConn.ItemIndex >= 0) and (cbSourceConn.ItemIndex < cbSourceConn.Items.Count) then
    Result := TConnectionProfile(cbSourceConn.Items.Objects[cbSourceConn.ItemIndex]);
end;

function TDatabaseComparerFrame.SelectedTargetProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbTargetConn.ItemIndex >= 0) and (cbTargetConn.ItemIndex < cbTargetConn.Items.Count) then
    Result := TConnectionProfile(cbTargetConn.Items.Objects[cbTargetConn.ItemIndex]);
end;

procedure TDatabaseComparerFrame.Initialize(
  const AFactory: IDatabaseProviderFactory;
  const AConnections: TConnectionProfileList;
  const AInitialSourceId: string
);
begin
  FFactory := AFactory;
  FSourceProfileId := AInitialSourceId;
  FTargetProfileId := '';
  FResult := nil;
  FCompareWorker := nil;
  FApplyWorker := nil;
  FUpdatingToolbarSize := False;

  {$IFDEF UNIX}
  grdDiffs.Font.Name := 'Monospace';
  SynEditScript.Font.Name := 'Monospace';
  SynEditSourceDDL.Font.Name := 'Monospace';
  SynEditTargetDDL.Font.Name := 'Monospace';
  memLog.Font.Name := 'Monospace';
  {$ENDIF}

  SynSQLSyn1.Enabled := True;
  SynEditScript.Highlighter := SynSQLSyn1;
  SynEditSourceDDL.Highlighter := SynSQLSyn1;
  SynEditTargetDDL.Highlighter := SynSQLSyn1;

  ConfigureGrid;
  LoadSettings(Trim(AInitialSourceId) <> '');
  RefreshConnections(AConnections);
  SetRunningState(False, 'Selecione Origem e Destino e clique em Comparar Bases.');
  LogMessage('Database Comparer pronto. Selecione uma base Origem (modelo) e uma base Destino (a atualizar).');
end;

procedure TDatabaseComparerFrame.RefreshConnections(const AConnections: TConnectionProfileList);
var
  Item, Cloned: TConnectionProfile;
  Idx, SrcIdx, TgtIdx: Integer;
  SrcId, TgtId: string;
begin
  if SelectedSourceProfile <> nil then
    SrcId := SelectedSourceProfile.Id
  else
    SrcId := FSourceProfileId;

  if SelectedTargetProfile <> nil then
    TgtId := SelectedTargetProfile.Id
  else
    TgtId := FTargetProfileId;

  FreeAndNil(FProfiles);
  FProfiles := TConnectionProfileList.Create(True);

  cbSourceConn.Items.BeginUpdate;
  cbTargetConn.Items.BeginUpdate;
  try
    cbSourceConn.Items.Clear;
    cbTargetConn.Items.Clear;
    SrcIdx := -1;
    TgtIdx := -1;

    if AConnections <> nil then
    begin
      for Item in AConnections do
      begin
        Cloned := Item.Clone;
        FProfiles.Add(Cloned);
        Idx := cbSourceConn.Items.AddObject(
          Format('%s [%s]', [Cloned.Name, DatabaseTypeToStr(Cloned.DatabaseType)]),
          Cloned
        );
        cbTargetConn.Items.AddObject(
          Format('%s [%s]', [Cloned.Name, DatabaseTypeToStr(Cloned.DatabaseType)]),
          Cloned
        );
        if (SrcId <> '') and SameText(Cloned.Id, SrcId) then
          SrcIdx := Idx;
        if (TgtId <> '') and SameText(Cloned.Id, TgtId) then
          TgtIdx := Idx;
      end;
    end;

    if (SrcIdx < 0) and (cbSourceConn.Items.Count > 0) then
      SrcIdx := 0;
    cbSourceConn.ItemIndex := SrcIdx;

    if (TgtIdx < 0) and (cbTargetConn.Items.Count > 1) then
    begin
      if SrcIdx = 0 then
        TgtIdx := 1
      else
        TgtIdx := 0;
    end;
    cbTargetConn.ItemIndex := TgtIdx;

    if SelectedSourceProfile <> nil then
      FSourceProfileId := SelectedSourceProfile.Id
    else
      FSourceProfileId := '';
    if SelectedTargetProfile <> nil then
      FTargetProfileId := SelectedTargetProfile.Id
    else
      FTargetProfileId := '';
    UpdateDialectForProfile(SelectedSourceProfile);
  finally
    cbTargetConn.Items.EndUpdate;
    cbSourceConn.Items.EndUpdate;
  end;
end;

function TDatabaseComparerFrame.UsesProfile(const AProfileId: string): Boolean;
var
  SrcProf, TgtProf: TConnectionProfile;
  SrcId, TgtId: string;
begin
  SrcProf := SelectedSourceProfile;
  if SrcProf <> nil then
    SrcId := SrcProf.Id
  else
    SrcId := FSourceProfileId;

  TgtProf := SelectedTargetProfile;
  if TgtProf <> nil then
    TgtId := TgtProf.Id
  else
    TgtId := FTargetProfileId;

  Result := SameText(SrcId, AProfileId) or SameText(TgtId, AProfileId);
end;

function TDatabaseComparerFrame.IsBusy: Boolean;
begin
  Result := (FCompareWorker <> nil) or (FApplyWorker <> nil);
end;

procedure TDatabaseComparerFrame.DetachAndCancel;
begin
  if FCompareWorker <> nil then
  begin
    FCompareWorker.Detach;
    FCompareWorker := nil;
  end;
  if FApplyWorker <> nil then
  begin
    FApplyWorker.Detach;
    FApplyWorker := nil;
  end;
end;

procedure TDatabaseComparerFrame.DisconnectAndCancel;
begin
  if not IsBusy then
    Exit;
  DetachAndCancel;
  SetRunningState(False, 'Operação cancelada e conexão desconectada.');
  LogMessage('Operação cancelada e conexão desconectada pelo usuário.');
end;

function TDatabaseComparerFrame.SettingsFilePath: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'comparer_settings.json';
end;

procedure TDatabaseComparerFrame.LoadSettings(const APreserveSourceId: Boolean);
var
  Path: string;
  SL: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
begin
  Path := SettingsFilePath;
  if not FileExists(Path) then
    Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(Path, TEncoding.UTF8);
      if Trim(SL.Text) = '' then
        Exit;
      Data := GetJSON(SL.Text);
      try
        if not (Data is TJSONObject) then
          Exit;
        Obj := TJSONObject(Data);
        if not APreserveSourceId then
          FSourceProfileId := Obj.Get('sourceProfileId', FSourceProfileId);
        FTargetProfileId := Obj.Get('targetProfileId', FTargetProfileId);
        chkTables.Checked := Obj.Get('compareTables', chkTables.Checked);
        chkConstraints.Checked := Obj.Get('compareConstraints', chkConstraints.Checked);
        chkIndexes.Checked := Obj.Get('compareIndexes', chkIndexes.Checked);
        chkGenerators.Checked := Obj.Get('compareGenerators', chkGenerators.Checked);
        chkViews.Checked := Obj.Get('compareViews', chkViews.Checked);
        chkProcedures.Checked := Obj.Get('compareProcedures', chkProcedures.Checked);
        chkTriggers.Checked := Obj.Get('compareTriggers', chkTriggers.Checked);
        chkIncludeDrops.Checked := Obj.Get('includeDrops', chkIncludeDrops.Checked);
        if Obj.Get('diffGridHeight', 0) >= 60 then
          grdDiffs.Height := Obj.Get('diffGridHeight', grdDiffs.Height);
      finally
        Data.Free;
      end;
    except
    end;
  finally
    SL.Free;
  end;
end;

procedure TDatabaseComparerFrame.SaveSettings;
var
  Obj: TJSONObject;
  SL: TStringList;
  SrcId, TgtId: string;
begin
  if SelectedSourceProfile <> nil then
    SrcId := SelectedSourceProfile.Id
  else
    SrcId := FSourceProfileId;
  if SelectedTargetProfile <> nil then
    TgtId := SelectedTargetProfile.Id
  else
    TgtId := FTargetProfileId;

  Obj := TJSONObject.Create;
  SL := TStringList.Create;
  try
    Obj.Add('sourceProfileId', SrcId);
    Obj.Add('targetProfileId', TgtId);
    Obj.Add('compareTables', chkTables.Checked);
    Obj.Add('compareConstraints', chkConstraints.Checked);
    Obj.Add('compareIndexes', chkIndexes.Checked);
    Obj.Add('compareGenerators', chkGenerators.Checked);
    Obj.Add('compareViews', chkViews.Checked);
    Obj.Add('compareProcedures', chkProcedures.Checked);
    Obj.Add('compareTriggers', chkTriggers.Checked);
    Obj.Add('includeDrops', chkIncludeDrops.Checked);
    Obj.Add('diffGridHeight', grdDiffs.Height);
    SL.Text := Obj.FormatJSON([], 2);
    try
      SL.SaveToFile(SettingsFilePath, TEncoding.UTF8);
    except
    end;
  finally
    SL.Free;
    Obj.Free;
  end;
end;

function TDatabaseComparerFrame.ReadOptionsFromUI: TCompareOptions;
begin
  Result.CompareTablesAndColumns := chkTables.Checked;
  Result.CompareConstraints := chkConstraints.Checked;
  Result.CompareIndexes := chkIndexes.Checked;
  Result.CompareGenerators := chkGenerators.Checked;
  Result.CompareViews := chkViews.Checked;
  Result.CompareProcedures := chkProcedures.Checked;
  Result.CompareTriggers := chkTriggers.Checked;
  Result.IncludeDropsForExtraObjects := chkIncludeDrops.Checked;
  Result.IgnoreWhitespaceInCode := True;
end;

procedure TDatabaseComparerFrame.SetRunningState(const ARunning: Boolean; const AStatusText: string);
var
  HasScript: Boolean;
  HasDiffs: Boolean;
begin
  cbSourceConn.Enabled := not ARunning;
  cbTargetConn.Enabled := not ARunning;
  btnSwapConns.Enabled := not ARunning;
  btnCompare.Enabled := not ARunning;
  btnCancelOp.Enabled := ARunning;
  pnlOptionsBar.Enabled := not ARunning;

  HasDiffs := (FResult <> nil) and (Length(FResult.Items) > 0);
  HasScript := Trim(SynEditScript.Lines.Text) <> '';

  btnSelectAll.Enabled := (not ARunning) and HasDiffs;
  btnSelectNone.Enabled := (not ARunning) and HasDiffs;
  btnCopyScript.Enabled := (not ARunning) and HasScript;
  btnSaveScript.Enabled := (not ARunning) and HasScript;
  btnOpenInEditor.Enabled := (not ARunning) and HasScript;
  btnExecuteScript.Enabled := (not ARunning) and HasScript and (SelectedTargetProfile <> nil);

  if AStatusText <> '' then
  begin
    lblStatus.Caption := AStatusText;
    if ARunning then
      lblStatus.Font.Color := clNavy
    else
      lblStatus.Font.Color := clWindowText;
  end;
  UpdateToolbarLayouts;
end;

procedure TDatabaseComparerFrame.PopulateDiffGrid;
var
  I, R: Integer;
  Item: TCompareDiffItem;
begin
  ConfigureGrid;
  if (FResult = nil) or (Length(FResult.Items) = 0) then
  begin
    grdDiffs.RowCount := 1;
    SynEditSourceDDL.Clear;
    SynEditTargetDDL.Clear;
    Exit;
  end;

  grdDiffs.RowCount := Length(FResult.Items) + 1;
  for I := 0 to High(FResult.Items) do
  begin
    Item := FResult.Items[I];
    R := I + 1;
    if Item.Selected then
      grdDiffs.Cells[0, R] := '[X]'
    else
      grdDiffs.Cells[0, R] := '[ ]';
    grdDiffs.Cells[1, R] := CompareObjectCategoryToStr(Item.Category);
    grdDiffs.Cells[2, R] := Item.ObjectName;
    grdDiffs.Cells[3, R] := CompareDiffStatusToStr(Item.Status);
    grdDiffs.Cells[4, R] := Item.Summary;
  end;

  grdDiffs.Row := 1;
  ShowRowDDL(0);
end;

procedure TDatabaseComparerFrame.RebuildCombinedScript;
begin
  if FResult = nil then
    SynEditScript.Clear
  else
    SynEditScript.Lines.Text := FResult.BuildCombinedScript(True);

  btnCopyScript.Enabled := (not IsBusy) and (Trim(SynEditScript.Lines.Text) <> '');
  btnSaveScript.Enabled := btnCopyScript.Enabled;
  btnOpenInEditor.Enabled := btnCopyScript.Enabled;
  btnExecuteScript.Enabled := btnCopyScript.Enabled and (SelectedTargetProfile <> nil);
end;

procedure TDatabaseComparerFrame.ShowRowDDL(const ARowIdx: Integer);
begin
  if (FResult = nil) or (ARowIdx < 0) or (ARowIdx > High(FResult.Items)) then
  begin
    SynEditSourceDDL.Clear;
    SynEditTargetDDL.Clear;
    Exit;
  end;
  SynEditSourceDDL.Lines.Text := FResult.Items[ARowIdx].SourceDDL;
  SynEditTargetDDL.Lines.Text := FResult.Items[ARowIdx].TargetDDL;
end;

procedure TDatabaseComparerFrame.ToggleRowSelection(const ARowIdx: Integer);
begin
  if IsBusy or (FResult = nil) or (ARowIdx < 0) or (ARowIdx > High(FResult.Items)) then
    Exit;
  FResult.Items[ARowIdx].Selected := not FResult.Items[ARowIdx].Selected;
  if FResult.Items[ARowIdx].Selected then
    grdDiffs.Cells[0, ARowIdx + 1] := '[X]'
  else
    grdDiffs.Cells[0, ARowIdx + 1] := '[ ]';
  RebuildCombinedScript;
end;

procedure TDatabaseComparerFrame.btnSwapConnsClick(Sender: TObject);
var
  OldSrcIdx, OldTgtIdx: Integer;
begin
  if IsBusy then
    Exit;
  OldSrcIdx := cbSourceConn.ItemIndex;
  OldTgtIdx := cbTargetConn.ItemIndex;
  cbSourceConn.ItemIndex := OldTgtIdx;
  cbTargetConn.ItemIndex := OldSrcIdx;
  cbSourceConnChange(nil);
  cbTargetConnChange(nil);
end;

procedure TDatabaseComparerFrame.cbSourceConnChange(Sender: TObject);
begin
  if SelectedSourceProfile <> nil then
  begin
    FSourceProfileId := SelectedSourceProfile.Id;
    UpdateDialectForProfile(SelectedSourceProfile);
  end
  else
    FSourceProfileId := '';
end;

procedure TDatabaseComparerFrame.cbTargetConnChange(Sender: TObject);
begin
  if SelectedTargetProfile <> nil then
    FTargetProfileId := SelectedTargetProfile.Id
  else
    FTargetProfileId := '';
end;

procedure TDatabaseComparerFrame.btnCompareClick(Sender: TObject);
var
  SrcProf, TgtProf: TConnectionProfile;
begin
  if IsBusy or (FFactory = nil) then
    Exit;

  SrcProf := SelectedSourceProfile;
  TgtProf := SelectedTargetProfile;
  if (SrcProf = nil) or (TgtProf = nil) then
  begin
    MessageDlg('Aviso', 'Selecione as conexões de Origem e Destino.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if SameText(SrcProf.Id, TgtProf.Id) then
  begin
    MessageDlg('Aviso', 'Selecione duas conexões diferentes para comparar.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if SrcProf.DatabaseType <> TgtProf.DatabaseType then
  begin
    MessageDlg('Aviso', 'A comparação suporta apenas bases do mesmo SGBD (ambas Firebird ou ambas PostgreSQL).', mtWarning, [mbOK], 0);
    Exit;
  end;

  UpdateDialectForProfile(TgtProf);
  SaveSettings;
  FreeAndNil(FResult);
  PopulateDiffGrid;
  SynEditScript.Clear;

  SetRunningState(True, Format('Iniciando comparação "%s" -> "%s"...', [SrcProf.Name, TgtProf.Name]));
  LogMessage(Format('Comparando "%s" (Origem) com "%s" (Destino)...', [SrcProf.Name, TgtProf.Name]));

  FCompareWorker := TCompareDatabasesWorker.Create(
    FFactory,
    SrcProf,
    TgtProf,
    ReadOptionsFromUI,
    @HandleCompareProgress,
    @HandleCompareComplete
  );
  FCompareWorker.Start;
end;

procedure TDatabaseComparerFrame.btnCancelOpClick(Sender: TObject);
begin
  if FCompareWorker <> nil then
  begin
    FCompareWorker.RequestCancel;
    btnCancelOp.Enabled := False;
    lblStatus.Caption := 'Cancelando comparação...';
    LogMessage('Cancelamento da comparação solicitado.');
  end
  else if FApplyWorker <> nil then
  begin
    FApplyWorker.RequestCancel;
    btnCancelOp.Enabled := False;
    lblStatus.Caption := 'Cancelando aplicação do script...';
    LogMessage('Cancelamento da execução solicitado.');
  end;
end;

procedure TDatabaseComparerFrame.HandleCompareProgress(const AStatusText: string);
begin
  lblStatus.Caption := AStatusText;
  LogMessage(AStatusText);
end;

procedure TDatabaseComparerFrame.HandleCompareComplete(
  const AWorker: TCompareDatabasesWorker;
  const AResult: TCompareResult;
  const AErrorMessage: string
);
var
  StatusSummary: string;
begin
  if FCompareWorker = AWorker then
    FCompareWorker := nil;

  FreeAndNil(FResult);
  FResult := AResult;

  if AErrorMessage <> '' then
  begin
    PopulateDiffGrid;
    SynEditScript.Clear;
    StatusSummary := 'Erro na comparação: ' + AErrorMessage;
    LogMessage('ERRO: ' + AErrorMessage);
    pgDetails.ActivePage := tsLog;
  end
  else if FResult <> nil then
  begin
    PopulateDiffGrid;
    RebuildCombinedScript;
    if Length(FResult.Items) = 0 then
      StatusSummary := Format('Bases idênticas (%d ms). Nenhuma diferença encontrada.', [FResult.ElapsedMs])
    else
      StatusSummary := Format('%d diferença(s) encontrada(s) (%d selecionada(s)) em %d ms.', [
        Length(FResult.Items), FResult.SelectedCount, FResult.ElapsedMs
      ]);
    LogMessage(StatusSummary);
    pgDetails.ActivePage := tsScript;
  end
  else
    StatusSummary := 'Comparação finalizada.';

  SetRunningState(False, StatusSummary);
end;

procedure TDatabaseComparerFrame.btnSelectAllClick(Sender: TObject);
var
  I: Integer;
begin
  if IsBusy or (FResult = nil) then
    Exit;
  for I := 0 to High(FResult.Items) do
  begin
    FResult.Items[I].Selected := True;
    grdDiffs.Cells[0, I + 1] := '[X]';
  end;
  RebuildCombinedScript;
end;

procedure TDatabaseComparerFrame.btnSelectNoneClick(Sender: TObject);
var
  I: Integer;
begin
  if IsBusy or (FResult = nil) then
    Exit;
  for I := 0 to High(FResult.Items) do
  begin
    FResult.Items[I].Selected := False;
    grdDiffs.Cells[0, I + 1] := '[ ]';
  end;
  RebuildCombinedScript;
end;

procedure TDatabaseComparerFrame.grdDiffsMouseDown(
  Sender: TObject;
  Button: TMouseButton;
  Shift: TShiftState;
  X, Y: Integer
);
var
  ACol, ARow: Integer;
begin
  if Button <> mbLeft then
    Exit;
  grdDiffs.MouseToCell(X, Y, ACol, ARow);
  if (ARow >= 1) and (ACol = 0) then
    ToggleRowSelection(ARow - 1);
end;

procedure TDatabaseComparerFrame.grdDiffsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_SPACE then
  begin
    Key := 0;
    if grdDiffs.Row >= 1 then
      ToggleRowSelection(grdDiffs.Row - 1);
  end;
end;

procedure TDatabaseComparerFrame.grdDiffsSelectCell(
  Sender: TObject;
  aCol, aRow: Integer;
  var CanSelect: Boolean
);
begin
  if aRow >= 1 then
    ShowRowDDL(aRow - 1);
end;

procedure TDatabaseComparerFrame.grdDiffsPrepareCanvas(
  sender: TObject;
  aCol, aRow: Integer;
  aState: TGridDrawState
);
var
  StatusVal: TCompareDiffStatus;
begin
  if (aRow >= 1) and (FResult <> nil) and (aRow - 1 <= High(FResult.Items)) and
     not (gdSelected in aState) then
  begin
    StatusVal := FResult.Items[aRow - 1].Status;
    if aCol = 3 then
    begin
      grdDiffs.Canvas.Font.Style := [fsBold];
      case StatusVal of
        cdsMissingInTarget: grdDiffs.Canvas.Font.Color := clGreen;
        cdsDifferent: grdDiffs.Canvas.Font.Color := clNavy;
        cdsExtraInTarget: grdDiffs.Canvas.Font.Color := clMaroon;
      end;
    end;
  end;
end;

procedure TDatabaseComparerFrame.btnCopyScriptClick(Sender: TObject);
begin
  Clipboard.AsText := SynEditScript.Lines.Text;
  lblStatus.Caption := 'Script copiado para a área de transferência.';
end;

procedure TDatabaseComparerFrame.btnSaveScriptClick(Sender: TObject);
begin
  if dlgSaveSql.Execute then
  begin
    SynEditScript.Lines.SaveToFile(dlgSaveSql.FileName, TEncoding.UTF8);
    LogMessage('Script salvo em: ' + dlgSaveSql.FileName);
  end;
end;

procedure TDatabaseComparerFrame.btnOpenInEditorClick(Sender: TObject);
var
  TgtProf: TConnectionProfile;
  ProfId, TabCap: string;
begin
  TgtProf := SelectedTargetProfile;
  if TgtProf <> nil then
  begin
    ProfId := TgtProf.Id;
    TabCap := 'Sync -> ' + TgtProf.Name;
  end
  else
  begin
    ProfId := '';
    TabCap := 'Sync Script';
  end;

  if Assigned(FOnOpenSqlInNewTab) then
    FOnOpenSqlInNewTab(ProfId, TabCap, SynEditScript.Lines.Text);
end;

procedure TDatabaseComparerFrame.btnExecuteScriptClick(Sender: TObject);
var
  TgtProf: TConnectionProfile;
begin
  if IsBusy or (FFactory = nil) then
    Exit;
  TgtProf := SelectedTargetProfile;
  if TgtProf = nil then
  begin
    MessageDlg('Aviso', 'Selecione a conexão de Destino.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if Trim(SynEditScript.Lines.Text) = '' then
    Exit;

  if MessageDlg(
       'Confirmar Aplicação de Script',
       Format('Deseja executar o script de atualização na base DESTINO "%s"? Recomendamos fazer backup antes de alterações estruturais.', [TgtProf.Name]),
       mtConfirmation,
       [mbYes, mbNo],
       0
     ) <> mrYes then
    Exit;

  pgDetails.ActivePage := tsLog;
  SetRunningState(True, Format('Aplicando script na base "%s"...', [TgtProf.Name]));
  LogMessage(Format('Iniciando aplicação do script na base "%s"...', [TgtProf.Name]));

  FApplyWorker := TApplyCompareScriptWorker.Create(
    FFactory,
    TgtProf,
    SynEditScript.Lines.Text,
    @HandleApplyProgress,
    @HandleApplyComplete
  );
  FApplyWorker.Start;
end;

procedure TDatabaseComparerFrame.HandleApplyProgress(const ALogLine: string);
begin
  LogMessage(ALogLine);
end;

procedure TDatabaseComparerFrame.HandleApplyComplete(
  const AWorker: TApplyCompareScriptWorker;
  const ASuccess: Boolean;
  const AExecutedCount: Integer;
  const AErrorMessage: string
);
var
  Msg: string;
begin
  if FApplyWorker = AWorker then
    FApplyWorker := nil;

  if ASuccess then
    Msg := Format('Script aplicado com sucesso (%d comando(s)).', [AExecutedCount])
  else
    Msg := 'Falha ao aplicar script (ROLLBACK executado): ' + AErrorMessage;

  SetRunningState(False, Msg);
  if ASuccess then
    MessageDlg('Sucesso', Msg, mtInformation, [mbOK], 0)
  else
    MessageDlg('Erro ao Aplicar Script', AErrorMessage, mtError, [mbOK], 0);
end;

end.
