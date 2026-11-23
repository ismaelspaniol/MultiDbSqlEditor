unit Presentation.QueryHistoryForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, Spin, Clipbrd,
  SynEdit, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.QueryHistory;

type
  TOnOpenSqlFromHistory = procedure(const AProfileId, ASqlText: string) of object;

  { TQueryHistoryForm }
  TQueryHistoryForm = class(TForm)
  private
    FHistoryService: IQueryHistoryService;
    FEntries: TQueryHistoryList;
    FFilteredIndices: array of Integer;
    FOnOpenSql: TOnOpenSqlFromHistory;

    pnlTop: TPanel;
    lblSearch: TLabel;
    edtSearch: TEdit;
    lblStatusFilter: TLabel;
    cbStatusFilter: TComboBox;
    lblMax: TLabel;
    spMaxEntries: TSpinEdit;
    btnApplyMax: TButton;
    btnClearHistory: TButton;

    grdHistory: TStringGrid;
    splMain: TSplitter;
    pnlBottom: TPanel;
    lblDetails: TLabel;
    synPreview: TSynEdit;
    synHighlighter: TSynSQLSyn;
    pnlActions: TPanel;
    btnOpenInTab: TButton;
    btnCopySql: TButton;
    btnClose: TButton;

    procedure BuildUI;
    procedure LoadEntries;
    procedure PopulateGrid;
    procedure UpdatePreview;
    procedure edtSearchChange(Sender: TObject);
    procedure cbStatusFilterChange(Sender: TObject);
    procedure btnApplyMaxClick(Sender: TObject);
    procedure btnClearHistoryClick(Sender: TObject);
    procedure grdHistorySelection(Sender: TObject; aCol, aRow: Integer);
    procedure grdHistoryDblClick(Sender: TObject);
    procedure grdHistoryPrepareCanvas(sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
    procedure btnOpenInTabClick(Sender: TObject);
    procedure btnCopySqlClick(Sender: TObject);
  public
    class procedure Execute(
      const AHistoryService: IQueryHistoryService;
      const AOnOpenSql: TOnOpenSqlFromHistory
    );
    destructor Destroy; override;
  end;

implementation

class procedure TQueryHistoryForm.Execute(
  const AHistoryService: IQueryHistoryService;
  const AOnOpenSql: TOnOpenSqlFromHistory
);
var
  Frm: TQueryHistoryForm;
begin
  if AHistoryService = nil then
    Exit;
  Frm := TQueryHistoryForm.CreateNew(nil);
  try
    Frm.FHistoryService := AHistoryService;
    Frm.FOnOpenSql := AOnOpenSql;
    Frm.BuildUI;
    Frm.LoadEntries;
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

destructor TQueryHistoryForm.Destroy;
begin
  FreeAndNil(FEntries);
  inherited Destroy;
end;

procedure TQueryHistoryForm.BuildUI;
begin
  Caption := 'Histórico de Execução de Queries';
  Position := poScreenCenter;
  Width := 980;
  Height := 640;
  Constraints.MinWidth := 720;
  Constraints.MinHeight := 460;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 44;
  pnlTop.BevelOuter := bvNone;

  lblSearch := TLabel.Create(Self);
  lblSearch.Parent := pnlTop;
  lblSearch.Left := 10;
  lblSearch.Top := 14;
  lblSearch.Caption := 'Buscar:';

  edtSearch := TEdit.Create(Self);
  edtSearch.Parent := pnlTop;
  edtSearch.Left := 58;
  edtSearch.Top := 10;
  edtSearch.Width := 230;
  edtSearch.TextHint := 'SQL, conexão ou erro...';
  edtSearch.OnChange := @edtSearchChange;

  lblStatusFilter := TLabel.Create(Self);
  lblStatusFilter.Parent := pnlTop;
  lblStatusFilter.Left := 300;
  lblStatusFilter.Top := 14;
  lblStatusFilter.Caption := 'Status:';

  cbStatusFilter := TComboBox.Create(Self);
  cbStatusFilter.Parent := pnlTop;
  cbStatusFilter.Left := 346;
  cbStatusFilter.Top := 10;
  cbStatusFilter.Width := 115;
  cbStatusFilter.Style := csDropDownList;
  cbStatusFilter.Items.Add('Todos');
  cbStatusFilter.Items.Add('Sucesso');
  cbStatusFilter.Items.Add('Erro');
  cbStatusFilter.ItemIndex := 0;
  cbStatusFilter.OnChange := @cbStatusFilterChange;

  lblMax := TLabel.Create(Self);
  lblMax.Parent := pnlTop;
  lblMax.Left := 476;
  lblMax.Top := 14;
  lblMax.Caption := 'Armazenar máx.:';

  spMaxEntries := TSpinEdit.Create(Self);
  spMaxEntries.Parent := pnlTop;
  spMaxEntries.Left := 574;
  spMaxEntries.Top := 10;
  spMaxEntries.Width := 80;
  spMaxEntries.MinValue := 10;
  spMaxEntries.MaxValue := 50000;
  spMaxEntries.Increment := 50;
  spMaxEntries.Value := FHistoryService.GetMaxEntries;

  btnApplyMax := TButton.Create(Self);
  btnApplyMax.Parent := pnlTop;
  btnApplyMax.Left := 660;
  btnApplyMax.Top := 9;
  btnApplyMax.Width := 70;
  btnApplyMax.Height := 25;
  btnApplyMax.Caption := 'Aplicar';
  btnApplyMax.OnClick := @btnApplyMaxClick;

  btnClearHistory := TButton.Create(Self);
  btnClearHistory.Parent := pnlTop;
  btnClearHistory.Left := Width - 130;
  btnClearHistory.Top := 9;
  btnClearHistory.Width := 118;
  btnClearHistory.Height := 25;
  btnClearHistory.Anchors := [akTop, akRight];
  btnClearHistory.Caption := 'Limpar Histórico';
  btnClearHistory.OnClick := @btnClearHistoryClick;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 230;
  pnlBottom.BevelOuter := bvNone;

  splMain := TSplitter.Create(Self);
  splMain.Parent := Self;
  splMain.Align := alBottom;
  splMain.Height := 5;

  grdHistory := TStringGrid.Create(Self);
  grdHistory.Parent := Self;
  grdHistory.Align := alClient;
  grdHistory.BorderSpacing.Left := 8;
  grdHistory.BorderSpacing.Right := 8;
  grdHistory.ColCount := 7;
  grdHistory.FixedCols := 0;
  grdHistory.FixedRows := 1;
  grdHistory.RowCount := 1;
  grdHistory.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect, goColSizing, goThumbTracking];
  grdHistory.Cells[0, 0] := 'Data/Hora';
  grdHistory.Cells[1, 0] := 'Conexão';
  grdHistory.Cells[2, 0] := 'Banco';
  grdHistory.Cells[3, 0] := 'Status';
  grdHistory.Cells[4, 0] := 'Tempo';
  grdHistory.Cells[5, 0] := 'Resumo';
  grdHistory.Cells[6, 0] := 'SQL';
  grdHistory.ColWidths[0] := 130;
  grdHistory.ColWidths[1] := 145;
  grdHistory.ColWidths[2] := 85;
  grdHistory.ColWidths[3] := 70;
  grdHistory.ColWidths[4] := 70;
  grdHistory.ColWidths[5] := 160;
  grdHistory.ColWidths[6] := 290;
  grdHistory.OnSelection := @grdHistorySelection;
  grdHistory.OnDblClick := @grdHistoryDblClick;
  grdHistory.OnPrepareCanvas := @grdHistoryPrepareCanvas;

  lblDetails := TLabel.Create(Self);
  lblDetails.Parent := pnlBottom;
  lblDetails.Align := alTop;
  lblDetails.BorderSpacing.Left := 8;
  lblDetails.BorderSpacing.Top := 4;
  lblDetails.BorderSpacing.Bottom := 4;
  lblDetails.Caption := 'SQL selecionado:';

  pnlActions := TPanel.Create(Self);
  pnlActions.Parent := pnlBottom;
  pnlActions.Align := alBottom;
  pnlActions.Height := 40;
  pnlActions.BevelOuter := bvNone;

  btnOpenInTab := TButton.Create(Self);
  btnOpenInTab.Parent := pnlActions;
  btnOpenInTab.Left := 8;
  btnOpenInTab.Top := 7;
  btnOpenInTab.Width := 165;
  btnOpenInTab.Height := 26;
  btnOpenInTab.Caption := 'Abrir em Nova Aba SQL';
  btnOpenInTab.OnClick := @btnOpenInTabClick;

  btnCopySql := TButton.Create(Self);
  btnCopySql.Parent := pnlActions;
  btnCopySql.Left := 181;
  btnCopySql.Top := 7;
  btnCopySql.Width := 110;
  btnCopySql.Height := 26;
  btnCopySql.Caption := 'Copiar SQL';
  btnCopySql.OnClick := @btnCopySqlClick;

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlActions;
  btnClose.Left := pnlActions.Width - 102;
  btnClose.Top := 7;
  btnClose.Width := 92;
  btnClose.Height := 26;
  btnClose.Anchors := [akTop, akRight];
  btnClose.Caption := 'Fechar';
  btnClose.ModalResult := mrClose;
  btnClose.Cancel := True;

  synHighlighter := TSynSQLSyn.Create(Self);
  synHighlighter.SQLDialect := sqlFirebird40;
  synHighlighter.Enabled := True;

  synPreview := TSynEdit.Create(Self);
  synPreview.Parent := pnlBottom;
  synPreview.Align := alClient;
  synPreview.BorderSpacing.Left := 8;
  synPreview.BorderSpacing.Right := 8;
  synPreview.ReadOnly := True;
  synPreview.Highlighter := synHighlighter;
  synPreview.Gutter.Visible := True;
end;

procedure TQueryHistoryForm.LoadEntries;
begin
  FreeAndNil(FEntries);
  FEntries := FHistoryService.GetAll;
  PopulateGrid;
end;

procedure TQueryHistoryForm.PopulateGrid;
var
  I, RowIdx: Integer;
  FilterStr, Preview: string;
  Entry: TQueryHistoryEntry;
  MatchStatus, MatchText: Boolean;
begin
  SetLength(FFilteredIndices, 0);
  if FEntries = nil then
  begin
    grdHistory.RowCount := 1;
    UpdatePreview;
    Exit;
  end;

  FilterStr := LowerCase(Trim(edtSearch.Text));
  for I := 0 to FEntries.Count - 1 do
  begin
    Entry := FEntries[I];
    case cbStatusFilter.ItemIndex of
      1: MatchStatus := Entry.Success;
      2: MatchStatus := not Entry.Success;
    else
      MatchStatus := True;
    end;
    if not MatchStatus then
      Continue;

    if FilterStr = '' then
      MatchText := True
    else
      MatchText := (Pos(FilterStr, LowerCase(Entry.SqlText)) > 0) or
                   (Pos(FilterStr, LowerCase(Entry.ProfileName)) > 0) or
                   (Pos(FilterStr, LowerCase(Entry.ErrorMessage)) > 0);
    if not MatchText then
      Continue;

    RowIdx := Length(FFilteredIndices);
    SetLength(FFilteredIndices, RowIdx + 1);
    FFilteredIndices[RowIdx] := I;
  end;

  grdHistory.BeginUpdate;
  try
    grdHistory.RowCount := Length(FFilteredIndices) + 1;
    for I := 0 to High(FFilteredIndices) do
    begin
      Entry := FEntries[FFilteredIndices[I]];
      RowIdx := I + 1;
      Preview := Trim(StringReplace(StringReplace(Entry.SqlText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
      if Length(Preview) > 140 then
        Preview := Copy(Preview, 1, 137) + '...';

      grdHistory.Cells[0, RowIdx] := FormatDateTime('dd/mm/yyyy hh:nn:ss', Entry.ExecutedAt);
      grdHistory.Cells[1, RowIdx] := Entry.ProfileName;
      grdHistory.Cells[2, RowIdx] := DatabaseTypeToStr(Entry.DatabaseType);
      if Entry.Success then
        grdHistory.Cells[3, RowIdx] := 'OK'
      else
        grdHistory.Cells[3, RowIdx] := 'Erro';
      grdHistory.Cells[4, RowIdx] := IntToStr(Entry.DurationMs) + ' ms';
      if Entry.Success then
        grdHistory.Cells[5, RowIdx] := Entry.RowsInfo
      else
        grdHistory.Cells[5, RowIdx] := Entry.ErrorMessage;
      grdHistory.Cells[6, RowIdx] := Preview;
    end;
    if grdHistory.RowCount > 1 then
      grdHistory.Row := 1;
  finally
    grdHistory.EndUpdate;
  end;
  UpdatePreview;
end;

procedure TQueryHistoryForm.UpdatePreview;
var
  Idx: Integer;
  Entry: TQueryHistoryEntry;
begin
  Idx := grdHistory.Row - 1;
  if (FEntries <> nil) and (Idx >= 0) and (Idx <= High(FFilteredIndices)) then
  begin
    Entry := FEntries[FFilteredIndices[Idx]];
    synPreview.Lines.Text := Entry.SqlText;
    if Entry.Success then
      lblDetails.Caption := Format('SQL (%s | %d ms | %s):', [Entry.ProfileName, Entry.DurationMs, Entry.RowsInfo])
    else
      lblDetails.Caption := Format('SQL (%s | Erro: %s):', [Entry.ProfileName, Entry.ErrorMessage]);
    btnOpenInTab.Enabled := True;
    btnCopySql.Enabled := True;
  end
  else
  begin
    synPreview.Clear;
    lblDetails.Caption := 'Nenhum item selecionado.';
    btnOpenInTab.Enabled := False;
    btnCopySql.Enabled := False;
  end;
end;

procedure TQueryHistoryForm.edtSearchChange(Sender: TObject);
begin
  PopulateGrid;
end;

procedure TQueryHistoryForm.cbStatusFilterChange(Sender: TObject);
begin
  PopulateGrid;
end;

procedure TQueryHistoryForm.btnApplyMaxClick(Sender: TObject);
begin
  FHistoryService.SetMaxEntries(spMaxEntries.Value);
  LoadEntries;
  MessageDlg('Histórico', Format('Limite atualizado para %d registros.', [spMaxEntries.Value]), mtInformation, [mbOK], 0);
end;

procedure TQueryHistoryForm.btnClearHistoryClick(Sender: TObject);
begin
  if MessageDlg('Limpar Histórico', 'Deseja apagar todo o histórico de execução?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FHistoryService.ClearAll;
    LoadEntries;
  end;
end;

procedure TQueryHistoryForm.grdHistorySelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdatePreview;
end;

procedure TQueryHistoryForm.grdHistoryDblClick(Sender: TObject);
begin
  btnOpenInTabClick(Sender);
end;

procedure TQueryHistoryForm.grdHistoryPrepareCanvas(sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
begin
  if (aRow >= 1) and (aCol = 3) and not (gdSelected in aState) then
  begin
    if grdHistory.Cells[3, aRow] = 'Erro' then
    begin
      grdHistory.Canvas.Font.Color := clMaroon;
      grdHistory.Canvas.Font.Style := [fsBold];
    end
    else
    begin
      grdHistory.Canvas.Font.Color := clGreen;
      grdHistory.Canvas.Font.Style := [fsBold];
    end;
  end;
end;

procedure TQueryHistoryForm.btnOpenInTabClick(Sender: TObject);
var
  Idx: Integer;
  Entry: TQueryHistoryEntry;
begin
  Idx := grdHistory.Row - 1;
  if (FEntries <> nil) and (Idx >= 0) and (Idx <= High(FFilteredIndices)) then
  begin
    Entry := FEntries[FFilteredIndices[Idx]];
    if Assigned(FOnOpenSql) then
      FOnOpenSql(Entry.ProfileId, Entry.SqlText);
    ModalResult := mrOk;
  end;
end;

procedure TQueryHistoryForm.btnCopySqlClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := grdHistory.Row - 1;
  if (FEntries <> nil) and (Idx >= 0) and (Idx <= High(FFilteredIndices)) then
    Clipboard.AsText := FEntries[FFilteredIndices[Idx]].SqlText;
end;

end.
