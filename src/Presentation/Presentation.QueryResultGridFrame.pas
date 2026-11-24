unit Presentation.QueryResultGridFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Clipbrd, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Grids, Menus, LCLType, fpjson, jsonparser,
  Domain.QueryResult;

type
  TResultGridExportedEvent = procedure(Sender: TObject; const AFileName: string) of object;
  TResultGridUpdateCellEvent = function(
    const ARowIndex, AColIndex: Integer;
    const AOldRow: TQueryRow;
    const ANewIsNull: Boolean;
    const ANewValue: string;
    out AError: string
  ): Boolean of object;
  TResultGridInsertRowEvent = function(
    const ANewRow: TQueryRow;
    out AError: string
  ): Boolean of object;
  TResultGridDeleteRowEvent = function(
    const AOldRow: TQueryRow;
    out AError: string
  ): Boolean of object;

  { Frame reutilizável de exibição, ordenação, edição, cópia e exportação CSV de TQueryResult }
  TQueryResultGridFrame = class(TFrame)
    pnlEditBar: TPanel;
    btnInsertRow: TButton;
    btnSaveNewRow: TButton;
    btnDeleteRow: TButton;
    btnSetNull: TButton;
    lblEditTable: TLabel;
    grdResults: TDrawGrid;
    pnlGridFooter: TPanel;
    lblGridSummary: TLabel;
    dlgSaveCsv: TSaveDialog;
    pmGrid: TPopupMenu;
    miCopyCell: TMenuItem;
    miCopySelection: TMenuItem;
    miCopyRow: TMenuItem;
    miCopyRowWithHeader: TMenuItem;
    miGridSep1: TMenuItem;
    miCopyColName: TMenuItem;
    miGridSep2: TMenuItem;
    miExportCsv: TMenuItem;
    miGridSep3: TMenuItem;
    miInsertRow: TMenuItem;
    miDeleteRow: TMenuItem;
    miSetNull: TMenuItem;
    procedure grdResultsDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure grdResultsGetEditText(Sender: TObject; aCol, aRow: Integer;
      var aValue: string);
    procedure grdResultsSetEditText(Sender: TObject; aCol, aRow: Integer;
      const aValue: string);
    procedure grdResultsEditingDone(Sender: TObject);
    procedure grdResultsHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
    procedure grdResultsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure grdResultsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure grdResultsTopLeftChanged(Sender: TObject);
    procedure pmGridPopup(Sender: TObject);
    procedure miCopyCellClick(Sender: TObject);
    procedure miCopySelectionClick(Sender: TObject);
    procedure miCopyRowClick(Sender: TObject);
    procedure miCopyRowWithHeaderClick(Sender: TObject);
    procedure miCopyColNameClick(Sender: TObject);
    procedure miExportCsvClick(Sender: TObject);
    procedure btnInsertRowClick(Sender: TObject);
    procedure btnSaveNewRowClick(Sender: TObject);
    procedure btnDeleteRowClick(Sender: TObject);
    procedure btnSetNullClick(Sender: TObject);
  private
    FResult: TQueryResult; // Referência não-proprietária
    FSortCol: Integer;
    FSortAsc: Boolean;
    FLastClickedGridCol: Integer;
    FSortingEnabled: Boolean;
    FExportEnabled: Boolean;
    FEditable: Boolean;
    FEditableTableName: string;
    FNewRowIndex: Integer;
    FHasPendingEdit: Boolean;
    FPendingEditRow: Integer;
    FPendingEditCol: Integer;
    FPendingEditValue: string;
    FEmptyMessage: string;
    pnlTopTools: TPanel;
    lblQuickFilter: TLabel;
    edtQuickFilter: TEdit;
    btnClearFilter: TButton;
    btnToggleInspector: TButton;
    btnToggleRecordView: TButton;
    splSide: TSplitter;
    pnlSide: TPanel;
    pgSide: TPageControl;
    tsInspector: TTabSheet;
    pnlInspectorTop: TPanel;
    lblInspectorMeta: TLabel;
    btnFormatJson: TButton;
    btnCopyInspector: TButton;
    btnCloseSide: TButton;
    memInspector: TMemo;
    tsRecordView: TTabSheet;
    grdRecordView: TStringGrid;
    miFilterByCell: TMenuItem;
    miQuickSearch: TMenuItem;
    miClearFilter: TMenuItem;
    miInspectCell: TMenuItem;
    miRecordView: TMenuItem;
    miSubMenuRecord: TMenuItem;
    miRecCsv: TMenuItem;
    miRecInsert: TMenuItem;
    miRecUpdate: TMenuItem;
    miRecUpsert: TMenuItem;
    miRecJson: TMenuItem;
    miRecMarkdown: TMenuItem;
    miSubMenuAll: TMenuItem;
    miCopyAllCsv: TMenuItem;
    miAllInsert: TMenuItem;
    miAllUpdate: TMenuItem;
    miAllUpsert: TMenuItem;
    miAllJson: TMenuItem;
    miAllMarkdown: TMenuItem;
    FFilteredRowIndices: array of Integer;
    FFilterActive: Boolean;
    FUpdatingFilterUI: Boolean;
    FOnNeedMoreRows: TNotifyEvent;
    FOnExportedCsv: TResultGridExportedEvent;
    FOnUpdateCell: TResultGridUpdateCellEvent;
    FOnInsertRow: TResultGridInsertRowEvent;
    FOnDeleteRow: TResultGridDeleteRowEvent;
    procedure EnsureExtendedControls;
    procedure grdResultsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure edtQuickFilterChange(Sender: TObject);
    procedure edtQuickFilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnClearFilterClick(Sender: TObject);
    procedure btnToggleInspectorClick(Sender: TObject);
    procedure btnToggleRecordViewClick(Sender: TObject);
    procedure btnFormatJsonClick(Sender: TObject);
    procedure btnCopyInspectorClick(Sender: TObject);
    procedure btnCloseSideClick(Sender: TObject);
    procedure miFilterByCellClick(Sender: TObject);
    procedure miQuickSearchClick(Sender: TObject);
    procedure miClearFilterClick(Sender: TObject);
    procedure miInspectCellClick(Sender: TObject);
    procedure miRecordViewClick(Sender: TObject);
    procedure miRecCsvClick(Sender: TObject);
    procedure miRecInsertClick(Sender: TObject);
    procedure miRecUpdateClick(Sender: TObject);
    procedure miRecUpsertClick(Sender: TObject);
    procedure miRecJsonClick(Sender: TObject);
    procedure miRecMarkdownClick(Sender: TObject);
    procedure miCopyAllCsvClick(Sender: TObject);
    procedure miAllInsertClick(Sender: TObject);
    procedure miAllUpdateClick(Sender: TObject);
    procedure miAllUpsertClick(Sender: TObject);
    procedure miAllJsonClick(Sender: TObject);
    procedure miAllMarkdownClick(Sender: TObject);
    function DataRowIndexForGridRow(const AGridRow: Integer): Integer;
    function VisibleDataRowCount: Integer;
    procedure ApplyQuickFilter;
    procedure OpenSidePanel(const AShowRecordView: Boolean);
    procedure UpdateSidePanelContent;
    function TryFormatJsonText(const AText: string; out AFormatted: string): Boolean;
    function BuildSelectionAggregationSuffix: string;
    function FormatCellSqlValue(const AColIndex: Integer; const ARow: TQueryRow): string;
    function BuildCsvForRows(const ARowIndices: array of Integer): string;
    function BuildInsertSqlForRows(const ARowIndices: array of Integer): string;
    function BuildUpdateSqlForRows(const ARowIndices: array of Integer): string;
    function BuildUpsertSqlForRows(const ARowIndices: array of Integer): string;
    function BuildJsonForRows(const ARowIndices: array of Integer): string;
    function BuildMarkdownForRows(const ARowIndices: array of Integer): string;
    function BuildHtmlForRows(const ARowIndices: array of Integer): string;
    function CollectSingleRecordIndex: TIntegerDynArray;
    function CollectAllQueryRowIndices: TIntegerDynArray;
    function CollectTargetDataRowIndices(const AAllVisible: Boolean): TIntegerDynArray;
    procedure SetEmptyMessage(const AValue: string);
    procedure UpdateEditButtonsState;
    procedure CommitPendingCellEdit;
    function GetGridCellText(const ACol, ARow: Integer): string;
    procedure CopySelectedCell;
    procedure CopySelectedRange;
    procedure CopyCurrentRow(const AIncludeHeader: Boolean);
    procedure CopyCurrentColumnName;
    function EscapeCsvField(const AValue: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetResult(
      const AResult: TQueryResult;
      const AResetSort: Boolean = True;
      const AAutoFit: Boolean = True
    );
    procedure SetEditable(const AEditable: Boolean; const ATableName: string = '');
    procedure RefreshRowCount;
    procedure UpdateSummaryText;
    procedure SetCustomSummary(const AText: string);
    procedure AutoFitColumns;
    function CanExportCsv: Boolean;
    function ExportToCsv: Boolean;
    function IsNearBottom(const AThreshold: Integer = 10): Boolean;
    property SortingEnabled: Boolean read FSortingEnabled write FSortingEnabled;
    property ExportEnabled: Boolean read FExportEnabled write FExportEnabled;
    property EmptyMessage: string read FEmptyMessage write SetEmptyMessage;
    property OnNeedMoreRows: TNotifyEvent read FOnNeedMoreRows write FOnNeedMoreRows;
    property OnExportedCsv: TResultGridExportedEvent read FOnExportedCsv write FOnExportedCsv;
    property OnUpdateCell: TResultGridUpdateCellEvent read FOnUpdateCell write FOnUpdateCell;
    property OnInsertRow: TResultGridInsertRowEvent read FOnInsertRow write FOnInsertRow;
    property OnDeleteRow: TResultGridDeleteRowEvent read FOnDeleteRow write FOnDeleteRow;
  end;

implementation

{$R *.lfm}

constructor TQueryResultGridFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FResult := nil;
  FSortCol := -1;
  FSortAsc := True;
  FLastClickedGridCol := -1;
  FSortingEnabled := True;
  FExportEnabled := True;
  FEditable := False;
  FNewRowIndex := -1;
  FHasPendingEdit := False;
  FFilterActive := False;
  FUpdatingFilterUI := False;
  FEmptyMessage := 'Nenhuma consulta executada.';
  EnsureExtendedControls;
end;

procedure TQueryResultGridFrame.EnsureExtendedControls;
var
  SepItem: TMenuItem;
begin
  if pnlTopTools <> nil then
    Exit;

  pnlTopTools := TPanel.Create(Self);
  pnlTopTools.Parent := Self;
  pnlTopTools.Align := alTop;
  pnlTopTools.Height := 30;
  pnlTopTools.BevelOuter := bvNone;
  pnlTopTools.Visible := False;

  lblQuickFilter := TLabel.Create(Self);
  lblQuickFilter.Parent := pnlTopTools;
  lblQuickFilter.Left := 6;
  lblQuickFilter.Top := 7;
  lblQuickFilter.Caption := 'Filtro rápido:';

  edtQuickFilter := TEdit.Create(Self);
  edtQuickFilter.Parent := pnlTopTools;
  edtQuickFilter.Left := 84;
  edtQuickFilter.Top := 3;
  edtQuickFilter.Width := 230;
  edtQuickFilter.TextHint := 'Pesquisar nas linhas carregadas (Esc limpa)...';
  edtQuickFilter.OnChange := @edtQuickFilterChange;
  edtQuickFilter.OnKeyDown := @edtQuickFilterKeyDown;

  btnClearFilter := TButton.Create(Self);
  btnClearFilter.Parent := pnlTopTools;
  btnClearFilter.Left := 320;
  btnClearFilter.Top := 3;
  btnClearFilter.Width := 68;
  btnClearFilter.Height := 24;
  btnClearFilter.Caption := 'Limpar';
  btnClearFilter.OnClick := @btnClearFilterClick;

  btnToggleInspector := TButton.Create(Self);
  btnToggleInspector.Parent := pnlTopTools;
  btnToggleInspector.Left := 396;
  btnToggleInspector.Top := 3;
  btnToggleInspector.Width := 110;
  btnToggleInspector.Height := 24;
  btnToggleInspector.Caption := 'Valor / JSON';
  btnToggleInspector.OnClick := @btnToggleInspectorClick;

  btnToggleRecordView := TButton.Create(Self);
  btnToggleRecordView.Parent := pnlTopTools;
  btnToggleRecordView.Left := 512;
  btnToggleRecordView.Top := 3;
  btnToggleRecordView.Width := 115;
  btnToggleRecordView.Height := 24;
  btnToggleRecordView.Caption := 'Visão Registro';
  btnToggleRecordView.OnClick := @btnToggleRecordViewClick;

  pnlSide := TPanel.Create(Self);
  pnlSide.Parent := Self;
  pnlSide.Align := alRight;
  pnlSide.Width := 320;
  pnlSide.BevelOuter := bvNone;
  pnlSide.Visible := False;

  splSide := TSplitter.Create(Self);
  splSide.Parent := Self;
  splSide.Align := alRight;
  splSide.Width := 5;
  splSide.Visible := False;

  pgSide := TPageControl.Create(Self);
  pgSide.Parent := pnlSide;
  pgSide.Align := alClient;

  tsInspector := TTabSheet.Create(pgSide);
  tsInspector.PageControl := pgSide;
  tsInspector.Caption := 'Valor / JSON';

  pnlInspectorTop := TPanel.Create(Self);
  pnlInspectorTop.Parent := tsInspector;
  pnlInspectorTop.Align := alTop;
  pnlInspectorTop.Height := 54;
  pnlInspectorTop.BevelOuter := bvNone;

  lblInspectorMeta := TLabel.Create(Self);
  lblInspectorMeta.Parent := pnlInspectorTop;
  lblInspectorMeta.Left := 6;
  lblInspectorMeta.Top := 4;
  lblInspectorMeta.Caption := 'Célula:';

  btnFormatJson := TButton.Create(Self);
  btnFormatJson.Parent := pnlInspectorTop;
  btnFormatJson.Left := 6;
  btnFormatJson.Top := 24;
  btnFormatJson.Width := 95;
  btnFormatJson.Height := 24;
  btnFormatJson.Caption := 'Formatar JSON';
  btnFormatJson.OnClick := @btnFormatJsonClick;

  btnCopyInspector := TButton.Create(Self);
  btnCopyInspector.Parent := pnlInspectorTop;
  btnCopyInspector.Left := 106;
  btnCopyInspector.Top := 24;
  btnCopyInspector.Width := 75;
  btnCopyInspector.Height := 24;
  btnCopyInspector.Caption := 'Copiar';
  btnCopyInspector.OnClick := @btnCopyInspectorClick;

  btnCloseSide := TButton.Create(Self);
  btnCloseSide.Parent := pnlInspectorTop;
  btnCloseSide.Left := 186;
  btnCloseSide.Top := 24;
  btnCloseSide.Width := 70;
  btnCloseSide.Height := 24;
  btnCloseSide.Caption := 'Fechar';
  btnCloseSide.OnClick := @btnCloseSideClick;

  memInspector := TMemo.Create(Self);
  memInspector.Parent := tsInspector;
  memInspector.Align := alClient;
  memInspector.ReadOnly := True;
  memInspector.ScrollBars := ssBoth;
  memInspector.WordWrap := True;

  tsRecordView := TTabSheet.Create(pgSide);
  tsRecordView.PageControl := pgSide;
  tsRecordView.Caption := 'Visão Registro';

  grdRecordView := TStringGrid.Create(Self);
  grdRecordView.Parent := tsRecordView;
  grdRecordView.Align := alClient;
  grdRecordView.ColCount := 3;
  grdRecordView.FixedCols := 0;
  grdRecordView.FixedRows := 1;
  grdRecordView.RowCount := 1;
  grdRecordView.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goThumbTracking];
  grdRecordView.Cells[0, 0] := 'Campo';
  grdRecordView.Cells[1, 0] := 'Tipo';
  grdRecordView.Cells[2, 0] := 'Valor';
  grdRecordView.ColWidths[0] := 110;
  grdRecordView.ColWidths[1] := 75;
  grdRecordView.ColWidths[2] := 120;

  if grdResults <> nil then
    grdResults.OnSelection := @grdResultsSelection;

  if dlgSaveCsv <> nil then
  begin
    dlgSaveCsv.Filter :=
      'CSV - Consulta Inteira (*.csv)|*.csv|' +
      'SQL INSERT - Consulta Inteira (*.sql)|*.sql|' +
      'SQL UPDATE - Consulta Inteira (*.sql)|*.sql|' +
      'SQL INSERT OR UPDATE - Consulta Inteira (*.sql)|*.sql|' +
      'JSON - Consulta Inteira (*.json)|*.json|' +
      'Tabela Markdown - Consulta Inteira (*.md)|*.md|' +
      'HTML - Consulta Inteira (*.html)|*.html|' +
      'Todos os arquivos (*.*)|*.*';
  end;

  if pmGrid <> nil then
  begin
    miCopyRow.Caption := 'Copiar Registro Atual (TSV sem Cabeçalhos)';
    miCopyRowWithHeader.Caption := 'Copiar Registro Atual (TSV com Cabeçalhos)';
    miExportCsv.Caption := 'Exportar Consulta Inteira em Arquivo (CSV / SQL / JSON / MD / HTML)...';

    miSubMenuRecord := TMenuItem.Create(pmGrid);
    miSubMenuRecord.Caption := 'Gerar / Copiar do Registro Atual';
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep1), miSubMenuRecord);

    miRecCsv := TMenuItem.Create(pmGrid);
    miRecCsv.Caption := 'Copiar Registro Atual (CSV com Cabeçalhos)';
    miRecCsv.OnClick := @miRecCsvClick;
    miSubMenuRecord.Add(miRecCsv);

    miRecInsert := TMenuItem.Create(pmGrid);
    miRecInsert.Caption := 'Gerar INSERT do Registro Atual';
    miRecInsert.OnClick := @miRecInsertClick;
    miSubMenuRecord.Add(miRecInsert);

    miRecUpdate := TMenuItem.Create(pmGrid);
    miRecUpdate.Caption := 'Gerar UPDATE do Registro Atual';
    miRecUpdate.OnClick := @miRecUpdateClick;
    miSubMenuRecord.Add(miRecUpdate);

    miRecUpsert := TMenuItem.Create(pmGrid);
    miRecUpsert.Caption := 'Gerar INSERT OR UPDATE do Registro Atual';
    miRecUpsert.OnClick := @miRecUpsertClick;
    miSubMenuRecord.Add(miRecUpsert);

    miRecJson := TMenuItem.Create(pmGrid);
    miRecJson.Caption := 'Gerar JSON do Registro Atual';
    miRecJson.OnClick := @miRecJsonClick;
    miSubMenuRecord.Add(miRecJson);

    miRecMarkdown := TMenuItem.Create(pmGrid);
    miRecMarkdown.Caption := 'Gerar Markdown do Registro Atual';
    miRecMarkdown.OnClick := @miRecMarkdownClick;
    miSubMenuRecord.Add(miRecMarkdown);

    miSubMenuAll := TMenuItem.Create(pmGrid);
    miSubMenuAll.Caption := 'Gerar / Copiar da Consulta Inteira';
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep1), miSubMenuAll);

    miCopyAllCsv := TMenuItem.Create(pmGrid);
    miCopyAllCsv.Caption := 'Copiar Consulta Inteira (CSV com Cabeçalhos)';
    miCopyAllCsv.OnClick := @miCopyAllCsvClick;
    miSubMenuAll.Add(miCopyAllCsv);

    miAllInsert := TMenuItem.Create(pmGrid);
    miAllInsert.Caption := 'Gerar INSERTs da Consulta Inteira';
    miAllInsert.OnClick := @miAllInsertClick;
    miSubMenuAll.Add(miAllInsert);

    miAllUpdate := TMenuItem.Create(pmGrid);
    miAllUpdate.Caption := 'Gerar UPDATEs da Consulta Inteira';
    miAllUpdate.OnClick := @miAllUpdateClick;
    miSubMenuAll.Add(miAllUpdate);

    miAllUpsert := TMenuItem.Create(pmGrid);
    miAllUpsert.Caption := 'Gerar INSERT OR UPDATEs da Consulta Inteira';
    miAllUpsert.OnClick := @miAllUpsertClick;
    miSubMenuAll.Add(miAllUpsert);

    miAllJson := TMenuItem.Create(pmGrid);
    miAllJson.Caption := 'Gerar JSON da Consulta Inteira';
    miAllJson.OnClick := @miAllJsonClick;
    miSubMenuAll.Add(miAllJson);

    miAllMarkdown := TMenuItem.Create(pmGrid);
    miAllMarkdown.Caption := 'Gerar Markdown da Consulta Inteira';
    miAllMarkdown.OnClick := @miAllMarkdownClick;
    miSubMenuAll.Add(miAllMarkdown);

    SepItem := TMenuItem.Create(pmGrid);
    SepItem.Caption := '-';
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep2), SepItem);

    miInspectCell := TMenuItem.Create(pmGrid);
    miInspectCell.Caption := 'Inspecionar Valor / JSON...';
    miInspectCell.OnClick := @miInspectCellClick;
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep2), miInspectCell);

    miRecordView := TMenuItem.Create(pmGrid);
    miRecordView.Caption := 'Visão Vertical do Registro...';
    miRecordView.OnClick := @miRecordViewClick;
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep2), miRecordView);

    miFilterByCell := TMenuItem.Create(pmGrid);
    miFilterByCell.Caption := 'Filtrar por Valor desta Célula';
    miFilterByCell.OnClick := @miFilterByCellClick;
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep2), miFilterByCell);

    miQuickSearch := TMenuItem.Create(pmGrid);
    miQuickSearch.Caption := 'Busca Rápida no Grid (Ctrl+F)...';
    miQuickSearch.OnClick := @miQuickSearchClick;
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep2), miQuickSearch);

    miClearFilter := TMenuItem.Create(pmGrid);
    miClearFilter.Caption := 'Limpar Filtro Local';
    miClearFilter.OnClick := @miClearFilterClick;
    pmGrid.Items.Insert(pmGrid.Items.IndexOf(miGridSep2), miClearFilter);
  end;
end;

procedure TQueryResultGridFrame.SetEditable(const AEditable: Boolean; const ATableName: string);
begin
  FEditable := AEditable and (FResult <> nil) and FResult.HasResultSet and (FResult.ColumnCount > 0);
  FEditableTableName := ATableName;
  FNewRowIndex := -1;
  FHasPendingEdit := False;

  if FEditable then
  begin
    grdResults.Options := grdResults.Options + [goEditing];
    if pnlEditBar <> nil then
      pnlEditBar.Visible := True;
    if lblEditTable <> nil then
      lblEditTable.Caption := Format('Edição: %s (use Commit/Rollback acima)', [FEditableTableName]);
  end
  else
  begin
    grdResults.Options := grdResults.Options - [goEditing];
    if pnlEditBar <> nil then
      pnlEditBar.Visible := False;
  end;
  UpdateEditButtonsState;
end;

procedure TQueryResultGridFrame.UpdateEditButtonsState;
var
  HasValidRow: Boolean;
begin
  HasValidRow := FEditable and (FResult <> nil) and (FResult.RowCount > 0) and
    (DataRowIndexForGridRow(grdResults.Row) >= 0);
  if btnInsertRow <> nil then
    btnInsertRow.Enabled := FEditable and (FNewRowIndex < 0);
  if btnSaveNewRow <> nil then
    btnSaveNewRow.Enabled := FEditable and (FNewRowIndex >= 0);
  if btnDeleteRow <> nil then
    btnDeleteRow.Enabled := HasValidRow;
  if btnSetNull <> nil then
    btnSetNull.Enabled := HasValidRow and (grdResults.Col >= 0) and (grdResults.Col < FResult.ColumnCount);
end;

procedure TQueryResultGridFrame.SetEmptyMessage(const AValue: string);
begin
  FEmptyMessage := AValue;
  if (FResult = nil) and (lblGridSummary <> nil) then
    lblGridSummary.Caption := FEmptyMessage;
end;

procedure TQueryResultGridFrame.SetResult(
  const AResult: TQueryResult;
  const AResetSort: Boolean;
  const AAutoFit: Boolean
);
begin
  FResult := AResult;
  FNewRowIndex := -1;
  FHasPendingEdit := False;
  FFilterActive := False;
  SetLength(FFilteredRowIndices, 0);
  if edtQuickFilter <> nil then
  begin
    FUpdatingFilterUI := True;
    try
      edtQuickFilter.Text := '';
    finally
      FUpdatingFilterUI := False;
    end;
  end;
  if AResetSort then
  begin
    FSortCol := -1;
    FSortAsc := True;
    FLastClickedGridCol := -1;
  end;

  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
  begin
    grdResults.ColCount := 1;
    grdResults.RowCount := 1;
    grdResults.Invalidate;
    UpdateSummaryText;
    UpdateSidePanelContent;
    Exit;
  end;

  grdResults.ColCount := FResult.ColumnCount;
  grdResults.RowCount := FResult.RowCount + 1;
  grdResults.FixedRows := 1;
  if AAutoFit then
    AutoFitColumns;
  grdResults.Invalidate;
  UpdateSummaryText;
  UpdateSidePanelContent;
end;

procedure TQueryResultGridFrame.RefreshRowCount;
begin
  if FFilterActive then
  begin
    ApplyQuickFilter;
    Exit;
  end;
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    grdResults.RowCount := 1
  else
    grdResults.RowCount := Max(1, FResult.RowCount + 1);
  UpdateSummaryText;
  UpdateSidePanelContent;
end;

procedure TQueryResultGridFrame.UpdateSummaryText;
var
  MemInfo, FilterSuffix, AggSuffix: string;
begin
  if (FResult = nil) or (not FResult.HasResultSet) then
  begin
    if (FResult <> nil) and (Trim(FResult.MessageText) <> '') then
      lblGridSummary.Caption := FResult.MessageText
    else
      lblGridSummary.Caption := FEmptyMessage;
    Exit;
  end;

  if FResult.MemoryLimitBytes > 0 then
    MemInfo := Format('%s / %s', [
      FormatByteSize(FResult.EstimatedMemoryBytes),
      FormatByteSize(FResult.MemoryLimitBytes)
    ])
  else
    MemInfo := Format('%s (sem limite)', [FormatByteSize(FResult.EstimatedMemoryBytes)]);

  if FFilterActive then
    FilterSuffix := Format(' | Filtro: %d/%d', [Length(FFilteredRowIndices), FResult.RowCount])
  else
    FilterSuffix := '';
  AggSuffix := BuildSelectionAggregationSuffix;

  if FResult.SpilledToDisk then
    lblGridSummary.Caption := Format(
      '[ARMAZENADO EM DISCO] %d registro(s) | Tempo: %d ms%s%s',
      [FResult.RowCount, FResult.ExecutionTimeMs, FilterSuffix, AggSuffix]
    )
  else if FResult.SystemMemoryLow then
    lblGridSummary.Caption := Format(
      '[PROTEÇÃO RAM DO SO] %d registro(s) mantidos | RAM: %s | Tempo: %d ms%s%s',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs, FilterSuffix, AggSuffix]
    )
  else if FResult.MemoryLimitReached then
    lblGridSummary.Caption := Format(
      '[LIMITE RAM ATINGIDO] %d registro(s) mantidos | RAM: %s | Tempo: %d ms%s%s',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs, FilterSuffix, AggSuffix]
    )
  else if FResult.HasMoreRows then
    lblGridSummary.Caption := Format(
      'Registros carregados: %d (role para carregar mais ou clique em Fetch All) | RAM: %s | Tempo: %d ms%s%s',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs, FilterSuffix, AggSuffix]
    )
  else
    lblGridSummary.Caption := Format(
      'Total de registros: %d | RAM: %s | Tempo: %d ms%s%s',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs, FilterSuffix, AggSuffix]
    );
end;

procedure TQueryResultGridFrame.SetCustomSummary(const AText: string);
begin
  if lblGridSummary <> nil then
    lblGridSummary.Caption := AText;
end;

procedure TQueryResultGridFrame.AutoFitColumns;
var
  C, R, MaxRows, W, ColW: Integer;
  CanMeasure: Boolean;
  HeaderText, CellText: string;
  Row: TQueryRow;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  CanMeasure := grdResults.HandleAllocated;
  if not CanMeasure then
  begin
    for C := 0 to FResult.ColumnCount - 1 do
      grdResults.ColWidths[C] := 150;
    Exit;
  end;

  MaxRows := Min(50, FResult.RowCount);
  grdResults.Canvas.Font.Assign(grdResults.Font);

  for C := 0 to FResult.ColumnCount - 1 do
  begin
    grdResults.Canvas.Font.Style := [fsBold];
    HeaderText := FResult.GetColumn(C).Name + ' ▲';
    ColW := grdResults.Canvas.TextWidth(HeaderText) + 20;

    grdResults.Canvas.Font.Style := [];
    for R := 0 to MaxRows - 1 do
    begin
      Row := FResult.GetRow(R);
      if C < Length(Row) then
      begin
        if Row[C].IsNull then
          CellText := '(NULL)'
        else
          CellText := Row[C].AsText;
        W := grdResults.Canvas.TextWidth(CellText) + 16;
        if W > ColW then
          ColW := W;
      end;
    end;

    if ColW < 70 then
      ColW := 70
    else if ColW > 320 then
      ColW := 320;
    grdResults.ColWidths[C] := ColW;
  end;
end;

function TQueryResultGridFrame.IsNearBottom(const AThreshold: Integer): Boolean;
begin
  Result := (grdResults.TopRow + grdResults.VisibleRowCount >= grdResults.RowCount - AThreshold);
end;

procedure TQueryResultGridFrame.grdResultsTopLeftChanged(Sender: TObject);
begin
  if Assigned(FOnNeedMoreRows) and IsNearBottom(10) then
    FOnNeedMoreRows(Self);
end;

procedure TQueryResultGridFrame.grdResultsHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
begin
  if (not FSortingEnabled) or (not IsColumn) or (FResult = nil) or (not FResult.HasResultSet) then
    Exit;
  if (Index < 0) or (Index >= FResult.ColumnCount) then
    Exit;

  if FSortCol = Index then
    FSortAsc := not FSortAsc
  else
  begin
    FSortCol := Index;
    FSortAsc := True;
  end;

  FResult.SortByColumn(FSortCol, FSortAsc);
  if FFilterActive then
    ApplyQuickFilter
  else
  begin
    grdResults.Invalidate;
    UpdateSidePanelContent;
  end;
end;

procedure TQueryResultGridFrame.grdResultsDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
var
  CellText: string;
  Row: TQueryRow;
  TextRect: TRect;
  IsCellSelected: Boolean;
  DataIdx: Integer;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  TextRect := aRect;
  InflateRect(TextRect, -4, -2);

  if aRow = 0 then
  begin
    if aCol < FResult.ColumnCount then
    begin
      grdResults.Canvas.Font.Style := [fsBold];
      grdResults.Canvas.Font.Color := clWindowText;
      CellText := FResult.GetColumn(aCol).Name;
      if aCol = FSortCol then
      begin
        if FSortAsc then
          CellText := CellText + ' ▲'
        else
          CellText := CellText + ' ▼';
      end;
      grdResults.Canvas.TextRect(TextRect, TextRect.Left, TextRect.Top, CellText);
    end;
    Exit;
  end;

  DataIdx := DataRowIndexForGridRow(aRow);
  if (DataIdx >= 0) and (DataIdx < FResult.RowCount) and (aCol < FResult.ColumnCount) then
  begin
    IsCellSelected := (gdSelected in aState) and
      ((not (gdFocused in aState)) or
       (goDrawFocusSelected in grdResults.Options) or
       ((goRowSelect in grdResults.Options) and not (goRelaxedRowSelect in grdResults.Options)));

    Row := FResult.GetRow(DataIdx);
    if (not IsCellSelected) and (DataIdx = FNewRowIndex) then
    begin
      grdResults.Canvas.Brush.Color := RGBToColor(240, 253, 244);
      grdResults.Canvas.FillRect(aRect);
    end;
    if (aCol >= Length(Row)) or Row[aCol].IsNull then
    begin
      grdResults.Canvas.Font.Style := [fsItalic];
      if not IsCellSelected then
        grdResults.Canvas.Font.Color := clGrayText;
      CellText := '(NULL)';
    end
    else
    begin
      grdResults.Canvas.Font.Style := [];
      if not IsCellSelected then
        grdResults.Canvas.Font.Color := clWindowText;
      CellText := Row[aCol].AsText;
    end;
    grdResults.Canvas.TextRect(TextRect, TextRect.Left, TextRect.Top, CellText);
  end;
end;

function TQueryResultGridFrame.GetGridCellText(const ACol, ARow: Integer): string;
var
  RowData: TQueryRow;
  DataIdx: Integer;
begin
  Result := '';
  if (FResult = nil) or (not FResult.HasResultSet) then
    Exit;
  DataIdx := DataRowIndexForGridRow(ARow);
  if (DataIdx < 0) or (DataIdx >= FResult.RowCount) then
    Exit;
  if (ACol < 0) or (ACol >= FResult.ColumnCount) then
    Exit;

  RowData := FResult.GetRow(DataIdx);
  if (ACol < Length(RowData)) and (not RowData[ACol].IsNull) then
    Result := RowData[ACol].AsText;
end;

procedure TQueryResultGridFrame.CopySelectedCell;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or
     (FResult.RowCount = 0) or (FResult.ColumnCount = 0) then
    Exit;
  if (grdResults.Row < 1) or (grdResults.Col < 0) then
    Exit;
  Clipboard.AsText := GetGridCellText(grdResults.Col, grdResults.Row);
end;

procedure TQueryResultGridFrame.CopySelectedRange;
var
  Sel: TGridRect;
  R, C, MinR, MaxR, MinC, MaxC: Integer;
  SL: TStringList;
  LineText: string;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or
     (FResult.RowCount = 0) or (FResult.ColumnCount = 0) then
    Exit;

  Sel := grdResults.Selection;
  MinR := Max(1, Min(Sel.Top, Sel.Bottom));
  MaxR := Min(VisibleDataRowCount, Max(Sel.Top, Sel.Bottom));
  MinC := Max(0, Min(Sel.Left, Sel.Right));
  MaxC := Min(FResult.ColumnCount - 1, Max(Sel.Left, Sel.Right));
  if (MinR > MaxR) or (MinC > MaxC) then
    Exit;

  SL := TStringList.Create;
  try
    for R := MinR to MaxR do
    begin
      LineText := '';
      for C := MinC to MaxC do
      begin
        if C > MinC then
          LineText := LineText + #9;
        LineText := LineText + GetGridCellText(C, R);
      end;
      SL.Add(LineText);
    end;
    Clipboard.AsText := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TQueryResultGridFrame.CopyCurrentRow(const AIncludeHeader: Boolean);
var
  C, DataRow: Integer;
  HeaderLine, DataLine: string;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or
     (FResult.RowCount = 0) or (FResult.ColumnCount = 0) then
    Exit;

  DataRow := grdResults.Row;
  if DataRowIndexForGridRow(DataRow) < 0 then
    Exit;

  HeaderLine := '';
  DataLine := '';
  for C := 0 to FResult.ColumnCount - 1 do
  begin
    if C > 0 then
    begin
      HeaderLine := HeaderLine + #9;
      DataLine := DataLine + #9;
    end;
    if AIncludeHeader then
      HeaderLine := HeaderLine + FResult.GetColumn(C).Name;
    DataLine := DataLine + GetGridCellText(C, DataRow);
  end;

  if AIncludeHeader then
    Clipboard.AsText := HeaderLine + LineEnding + DataLine
  else
    Clipboard.AsText := DataLine;
end;

procedure TQueryResultGridFrame.CopyCurrentColumnName;
var
  TargetCol: Integer;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  TargetCol := FLastClickedGridCol;
  if (TargetCol < 0) or (TargetCol >= FResult.ColumnCount) then
    TargetCol := grdResults.Col;
  if (TargetCol >= 0) and (TargetCol < FResult.ColumnCount) then
    Clipboard.AsText := FResult.GetColumn(TargetCol).Name;
end;

procedure TQueryResultGridFrame.grdResultsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Sel: TGridRect;
begin
  if (ssCtrl in Shift) and ((Key = VK_C) or (Key = Ord('C'))) then
  begin
    Key := 0;
    Sel := grdResults.Selection;
    if (Sel.Left <> Sel.Right) or (Sel.Top <> Sel.Bottom) then
      CopySelectedRange
    else
      CopySelectedCell;
  end
  else if (ssCtrl in Shift) and ((Key = VK_F) or (Key = Ord('F'))) then
  begin
    Key := 0;
    miQuickSearchClick(nil);
  end;
end;

procedure TQueryResultGridFrame.grdResultsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  ACol, ARow: Integer;
  Sel: TGridRect;
  InSelection: Boolean;
begin
  if Button <> mbRight then
    Exit;

  grdResults.MouseToCell(X, Y, ACol, ARow);
  FLastClickedGridCol := ACol;
  if (ACol >= 0) and (ARow >= 1) and (FResult <> nil) and
     (ACol < FResult.ColumnCount) and (DataRowIndexForGridRow(ARow) >= 0) then
  begin
    Sel := grdResults.Selection;
    InSelection := (ACol >= Min(Sel.Left, Sel.Right)) and (ACol <= Max(Sel.Left, Sel.Right)) and
                   (ARow >= Min(Sel.Top, Sel.Bottom)) and (ARow <= Max(Sel.Top, Sel.Bottom));
    if not InSelection then
    begin
      grdResults.Col := ACol;
      grdResults.Row := ARow;
    end;
  end;
end;

procedure TQueryResultGridFrame.pmGridPopup(Sender: TObject);
var
  HasGrid, HasRows, HasValidRow, HasValidCell: Boolean;
begin
  HasGrid := (FResult <> nil) and FResult.HasResultSet and (FResult.ColumnCount > 0);
  HasRows := HasGrid and (VisibleDataRowCount > 0);
  HasValidRow := HasRows and (DataRowIndexForGridRow(grdResults.Row) >= 0);
  HasValidCell := HasValidRow and (grdResults.Col >= 0) and (grdResults.Col < FResult.ColumnCount);

  miCopyCell.Enabled := HasValidCell;
  miCopySelection.Enabled := HasRows;
  miCopyRow.Enabled := HasValidRow;
  miCopyRowWithHeader.Enabled := HasValidRow;
  if miSubMenuRecord <> nil then
    miSubMenuRecord.Enabled := HasValidRow;
  if miSubMenuAll <> nil then
    miSubMenuAll.Enabled := HasRows;
  miCopyColName.Enabled := HasGrid and (((FLastClickedGridCol >= 0) and (FLastClickedGridCol < FResult.ColumnCount)) or
    ((grdResults.Col >= 0) and (grdResults.Col < FResult.ColumnCount)));
  if miInspectCell <> nil then
    miInspectCell.Enabled := HasValidCell;
  if miRecordView <> nil then
    miRecordView.Enabled := HasValidRow;
  if miFilterByCell <> nil then
    miFilterByCell.Enabled := HasValidCell;
  if miQuickSearch <> nil then
    miQuickSearch.Enabled := HasGrid;
  if miClearFilter <> nil then
    miClearFilter.Enabled := FFilterActive;
  miGridSep2.Visible := FExportEnabled;
  miExportCsv.Visible := FExportEnabled;
  miExportCsv.Enabled := FExportEnabled and CanExportCsv;

  miGridSep3.Visible := FEditable;
  miInsertRow.Visible := FEditable;
  miInsertRow.Enabled := FEditable and (FNewRowIndex < 0) and (not FFilterActive);
  miDeleteRow.Visible := FEditable;
  miDeleteRow.Enabled := FEditable and HasValidRow;
  miSetNull.Visible := FEditable;
  miSetNull.Enabled := FEditable and HasValidCell;
end;

procedure TQueryResultGridFrame.grdResultsGetEditText(Sender: TObject; aCol, aRow: Integer;
  var aValue: string);
begin
  aValue := GetGridCellText(aCol, aRow);
end;

procedure TQueryResultGridFrame.grdResultsSetEditText(Sender: TObject; aCol, aRow: Integer;
  const aValue: string);
var
  DataIdx: Integer;
begin
  DataIdx := DataRowIndexForGridRow(aRow);
  if (not FEditable) or (FResult = nil) or (DataIdx < 0) or (DataIdx >= FResult.RowCount) then
    Exit;
  FPendingEditRow := DataIdx;
  FPendingEditCol := aCol;
  FPendingEditValue := aValue;
  FHasPendingEdit := True;
end;

procedure TQueryResultGridFrame.CommitPendingCellEdit;
var
  OldRow: TQueryRow;
  OldIsNull: Boolean;
  OldText, Err: string;
begin
  if (not FHasPendingEdit) or (not FEditable) or (FResult = nil) then
  begin
    FHasPendingEdit := False;
    Exit;
  end;
  FHasPendingEdit := False;

  if (FPendingEditRow < 0) or (FPendingEditRow >= FResult.RowCount) or
     (FPendingEditCol < 0) or (FPendingEditCol >= FResult.ColumnCount) then
    Exit;

  OldRow := FResult.GetRow(FPendingEditRow);
  OldIsNull := (FPendingEditCol >= Length(OldRow)) or OldRow[FPendingEditCol].IsNull;
  if OldIsNull then
    OldText := ''
  else
    OldText := OldRow[FPendingEditCol].AsText;

  { If cell was NULL and user left it empty without typing, keep NULL }
  if OldIsNull and (FPendingEditValue = '') then
    Exit;
  if (not OldIsNull) and (FPendingEditValue = OldText) then
    Exit;

  if FPendingEditRow = FNewRowIndex then
  begin
    FResult.UpdateCell(FPendingEditRow, FPendingEditCol, False, FPendingEditValue);
    grdResults.Invalidate;
    Exit;
  end;

  if Assigned(FOnUpdateCell) then
  begin
    if FOnUpdateCell(FPendingEditRow, FPendingEditCol, OldRow, False, FPendingEditValue, Err) then
    begin
      FResult.UpdateCell(FPendingEditRow, FPendingEditCol, False, FPendingEditValue);
      grdResults.Invalidate;
    end
    else
      MessageDlg('Erro ao Atualizar Célula', Err, mtError, [mbOK], 0);
  end;
end;

procedure TQueryResultGridFrame.grdResultsEditingDone(Sender: TObject);
begin
  CommitPendingCellEdit;
end;

procedure TQueryResultGridFrame.btnInsertRowClick(Sender: TObject);
begin
  if (not FEditable) or (FResult = nil) or (FNewRowIndex >= 0) then
    Exit;
  CommitPendingCellEdit;
  FNewRowIndex := FResult.InsertEmptyRow;
  RefreshRowCount;
  grdResults.Row := FNewRowIndex + 1;
  grdResults.Col := 0;
  grdResults.Invalidate;
  UpdateEditButtonsState;
  grdResults.SetFocus;
end;

procedure TQueryResultGridFrame.btnSaveNewRowClick(Sender: TObject);
var
  Err: string;
begin
  if (not FEditable) or (FResult = nil) or (FNewRowIndex < 0) then
    Exit;
  if grdResults.EditorMode then
    grdResults.EditorMode := False;
  CommitPendingCellEdit;

  if Assigned(FOnInsertRow) then
  begin
    if FOnInsertRow(FResult.GetRow(FNewRowIndex), Err) then
    begin
      FNewRowIndex := -1;
      grdResults.Invalidate;
      UpdateEditButtonsState;
      UpdateSummaryText;
    end
    else
      MessageDlg('Erro ao Inserir Linha', Err, mtError, [mbOK], 0);
  end;
end;

procedure TQueryResultGridFrame.btnDeleteRowClick(Sender: TObject);
var
  RowIdx: Integer;
  Err: string;
begin
  RowIdx := DataRowIndexForGridRow(grdResults.Row);
  if (not FEditable) or (FResult = nil) or (RowIdx < 0) or (RowIdx >= FResult.RowCount) then
    Exit;

  if RowIdx = FNewRowIndex then
  begin
    FHasPendingEdit := False;
    FResult.DeleteRow(RowIdx);
    FNewRowIndex := -1;
    RefreshRowCount;
    grdResults.Invalidate;
    UpdateEditButtonsState;
    Exit;
  end;

  if MessageDlg('Confirmar Exclusão', 'Deseja excluir a linha selecionada (poderá confirmar com Commit ou desfazer com Rollback)?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if Assigned(FOnDeleteRow) then
  begin
    if FOnDeleteRow(FResult.GetRow(RowIdx), Err) then
    begin
      FResult.DeleteRow(RowIdx);
      if FNewRowIndex > RowIdx then
        Dec(FNewRowIndex);
      RefreshRowCount;
      grdResults.Invalidate;
      UpdateEditButtonsState;
    end
    else
      MessageDlg('Erro ao Excluir Linha', Err, mtError, [mbOK], 0);
  end;
end;

procedure TQueryResultGridFrame.btnSetNullClick(Sender: TObject);
var
  RowIdx, ColIdx: Integer;
  OldRow: TQueryRow;
  Err: string;
begin
  RowIdx := DataRowIndexForGridRow(grdResults.Row);
  if (not FEditable) or (FResult = nil) or (RowIdx < 0) then
    Exit;
  ColIdx := grdResults.Col;
  if (RowIdx < 0) or (RowIdx >= FResult.RowCount) or (ColIdx < 0) or (ColIdx >= FResult.ColumnCount) then
    Exit;

  if grdResults.EditorMode then
    grdResults.EditorMode := False;
  FHasPendingEdit := False;

  if RowIdx = FNewRowIndex then
  begin
    FResult.UpdateCell(RowIdx, ColIdx, True, '');
    grdResults.Invalidate;
    Exit;
  end;

  OldRow := FResult.GetRow(RowIdx);
  if Assigned(FOnUpdateCell) then
  begin
    if FOnUpdateCell(RowIdx, ColIdx, OldRow, True, '', Err) then
    begin
      FResult.UpdateCell(RowIdx, ColIdx, True, '');
      grdResults.Invalidate;
    end
    else
      MessageDlg('Erro ao Definir NULL', Err, mtError, [mbOK], 0);
  end;
end;

procedure TQueryResultGridFrame.miCopyCellClick(Sender: TObject);
begin
  CopySelectedCell;
end;

procedure TQueryResultGridFrame.miCopySelectionClick(Sender: TObject);
begin
  CopySelectedRange;
end;

procedure TQueryResultGridFrame.miCopyRowClick(Sender: TObject);
begin
  CopyCurrentRow(False);
end;

procedure TQueryResultGridFrame.miCopyRowWithHeaderClick(Sender: TObject);
begin
  CopyCurrentRow(True);
end;

procedure TQueryResultGridFrame.miCopyColNameClick(Sender: TObject);
begin
  CopyCurrentColumnName;
end;

procedure TQueryResultGridFrame.miExportCsvClick(Sender: TObject);
begin
  ExportToCsv;
end;

function TQueryResultGridFrame.EscapeCsvField(const AValue: string): string;
begin
  if (Pos(';', AValue) > 0) or (Pos('"', AValue) > 0) or
     (Pos(#10, AValue) > 0) or (Pos(#13, AValue) > 0) then
    Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AValue;
end;

function TQueryResultGridFrame.CanExportCsv: Boolean;
begin
  Result := FExportEnabled and (FResult <> nil) and FResult.HasResultSet and (FResult.RowCount > 0);
end;

function TQueryResultGridFrame.ExportToCsv: Boolean;
const
  BUF_FLUSH_BYTES = 65536;
  UTF8_BOM: string = #$EF#$BB#$BF;
var
  FS: TFileStream;
  I, R, C: Integer;
  Buf, Line, Ext, OutText: string;
  Row: TQueryRow;
  AllIndices: TIntegerDynArray;

  procedure FlushBuf(var ABuf: string);
  begin
    if ABuf <> '' then
    begin
      FS.WriteBuffer(ABuf[1], Length(ABuf));
      ABuf := '';
    end;
  end;

begin
  Result := False;
  if not CanExportCsv then
    Exit;

  if not dlgSaveCsv.Execute then
    Exit;

  if FResult.HasMoreRows then
  begin
    Screen.Cursor := crHourGlass;
    try
      FResult.FetchAll;
      RefreshRowCount;
    finally
      Screen.Cursor := crDefault;
    end;
  end;

  Ext := LowerCase(ExtractFileExt(dlgSaveCsv.FileName));
  if (Ext = '.sql') or (Ext = '.json') or (Ext = '.md') or (Ext = '.html') or (Ext = '.htm') then
  begin
    AllIndices := CollectTargetDataRowIndices(True);
    if Ext = '.sql' then
    begin
      if dlgSaveCsv.FilterIndex = 3 then
        OutText := BuildUpdateSqlForRows(AllIndices)
      else if dlgSaveCsv.FilterIndex = 4 then
        OutText := BuildUpsertSqlForRows(AllIndices)
      else
        OutText := BuildInsertSqlForRows(AllIndices);
    end
    else if Ext = '.json' then
      OutText := BuildJsonForRows(AllIndices)
    else if Ext = '.md' then
      OutText := BuildMarkdownForRows(AllIndices)
    else
      OutText := BuildHtmlForRows(AllIndices);

    FS := TFileStream.Create(dlgSaveCsv.FileName, fmCreate);
    try
      if OutText <> '' then
        FS.WriteBuffer(OutText[1], Length(OutText));
    finally
      FS.Free;
    end;
    Result := True;
    if Assigned(FOnExportedCsv) then
      FOnExportedCsv(Self, dlgSaveCsv.FileName);
    Exit;
  end;

  FS := TFileStream.Create(dlgSaveCsv.FileName, fmCreate);
  try
    Buf := UTF8_BOM;
    Line := '';
    for C := 0 to FResult.ColumnCount - 1 do
    begin
      if C > 0 then
        Line := Line + ';';
      Line := Line + EscapeCsvField(FResult.GetColumn(C).Name);
    end;
    Buf := Buf + Line + LineEnding;

    for I := 0 to VisibleDataRowCount - 1 do
    begin
      if FFilterActive then
        R := FFilteredRowIndices[I]
      else
        R := I;
      Row := FResult.GetRow(R);
      Line := '';
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        if C > 0 then
          Line := Line + ';';
        if (C < Length(Row)) and (not Row[C].IsNull) then
          Line := Line + EscapeCsvField(Row[C].AsText);
      end;
      Buf := Buf + Line + LineEnding;
      if Length(Buf) >= BUF_FLUSH_BYTES then
        FlushBuf(Buf);
    end;
    FlushBuf(Buf);
    Result := True;
    if Assigned(FOnExportedCsv) then
      FOnExportedCsv(Self, dlgSaveCsv.FileName);
  finally
    FS.Free;
  end;
end;

function TQueryResultGridFrame.DataRowIndexForGridRow(const AGridRow: Integer): Integer;
var
  RawIdx: Integer;
begin
  RawIdx := AGridRow - 1;
  if (RawIdx < 0) or (FResult = nil) then
    Exit(-1);
  if FFilterActive then
  begin
    if RawIdx <= High(FFilteredRowIndices) then
      Result := FFilteredRowIndices[RawIdx]
    else
      Result := -1;
  end
  else
  begin
    if RawIdx < FResult.RowCount then
      Result := RawIdx
    else
      Result := -1;
  end;
end;

function TQueryResultGridFrame.VisibleDataRowCount: Integer;
begin
  if FResult = nil then
    Result := 0
  else if FFilterActive then
    Result := Length(FFilteredRowIndices)
  else
    Result := FResult.RowCount;
end;

procedure TQueryResultGridFrame.ApplyQuickFilter;
var
  FilterLower: string;
  R, C, MatchCount, Cap: Integer;
  Row: TQueryRow;
  Matched: Boolean;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
  begin
    FFilterActive := False;
    SetLength(FFilteredRowIndices, 0);
    grdResults.RowCount := 1;
    UpdateSummaryText;
    UpdateSidePanelContent;
    Exit;
  end;

  if edtQuickFilter <> nil then
    FilterLower := LowerCase(Trim(edtQuickFilter.Text))
  else
    FilterLower := '';

  if FilterLower = '' then
  begin
    FFilterActive := False;
    SetLength(FFilteredRowIndices, 0);
    grdResults.RowCount := Max(1, FResult.RowCount + 1);
    grdResults.FixedRows := 1;
    grdResults.Invalidate;
    UpdateSummaryText;
    UpdateSidePanelContent;
    UpdateEditButtonsState;
    Exit;
  end;

  FFilterActive := True;
  MatchCount := 0;
  Cap := 64;
  SetLength(FFilteredRowIndices, Cap);
  for R := 0 to FResult.RowCount - 1 do
  begin
    Row := FResult.GetRow(R);
    Matched := False;
    for C := 0 to FResult.ColumnCount - 1 do
    begin
      if (C < Length(Row)) and (not Row[C].IsNull) then
      begin
        if Pos(FilterLower, LowerCase(Row[C].AsText)) > 0 then
        begin
          Matched := True;
          Break;
        end;
      end
      else if Pos(FilterLower, '(null)') > 0 then
      begin
        Matched := True;
        Break;
      end;
    end;
    if Matched then
    begin
      if MatchCount >= Cap then
      begin
        Cap := Cap * 2;
        SetLength(FFilteredRowIndices, Cap);
      end;
      FFilteredRowIndices[MatchCount] := R;
      Inc(MatchCount);
    end;
  end;
  SetLength(FFilteredRowIndices, MatchCount);
  grdResults.RowCount := Max(1, MatchCount + 1);
  grdResults.FixedRows := 1;
  grdResults.Invalidate;
  UpdateSummaryText;
  UpdateSidePanelContent;
  UpdateEditButtonsState;
end;

procedure TQueryResultGridFrame.edtQuickFilterChange(Sender: TObject);
begin
  if not FUpdatingFilterUI then
    ApplyQuickFilter;
end;

procedure TQueryResultGridFrame.edtQuickFilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    btnClearFilterClick(nil);
    if grdResults.CanFocus then
      grdResults.SetFocus;
  end;
end;

procedure TQueryResultGridFrame.btnClearFilterClick(Sender: TObject);
begin
  if edtQuickFilter <> nil then
    edtQuickFilter.Text := '';
  ApplyQuickFilter;
end;

procedure TQueryResultGridFrame.OpenSidePanel(const AShowRecordView: Boolean);
begin
  if (pnlSide = nil) or (splSide = nil) or (pgSide = nil) then
    Exit;
  if not pnlSide.Visible then
  begin
    pnlSide.Visible := True;
    splSide.Visible := True;
    splSide.Left := pnlSide.Left - 1;
  end;
  if AShowRecordView then
    pgSide.ActivePage := tsRecordView
  else
    pgSide.ActivePage := tsInspector;
  UpdateSidePanelContent;
end;

procedure TQueryResultGridFrame.btnToggleInspectorClick(Sender: TObject);
begin
  if (pnlSide <> nil) and pnlSide.Visible and (pgSide.ActivePage = tsInspector) then
    btnCloseSideClick(nil)
  else
    OpenSidePanel(False);
end;

procedure TQueryResultGridFrame.btnToggleRecordViewClick(Sender: TObject);
begin
  if (pnlSide <> nil) and pnlSide.Visible and (pgSide.ActivePage = tsRecordView) then
    btnCloseSideClick(nil)
  else
    OpenSidePanel(True);
end;

procedure TQueryResultGridFrame.btnCloseSideClick(Sender: TObject);
begin
  if splSide <> nil then
    splSide.Visible := False;
  if pnlSide <> nil then
    pnlSide.Visible := False;
end;

function TQueryResultGridFrame.TryFormatJsonText(const AText: string; out AFormatted: string): Boolean;
var
  Trimmed: string;
  Data: TJSONData;
begin
  Result := False;
  AFormatted := AText;
  Trimmed := Trim(AText);
  if (Trimmed = '') or (not (Trimmed[1] in ['{', '['])) then
    Exit;
  try
    Data := GetJSON(Trimmed);
    if Data <> nil then
    begin
      try
        AFormatted := Data.FormatJSON([], 2);
        Result := True;
      finally
        Data.Free;
      end;
    end;
  except
    Result := False;
  end;
end;

procedure TQueryResultGridFrame.btnFormatJsonClick(Sender: TObject);
var
  Pretty: string;
begin
  if memInspector = nil then
    Exit;
  if TryFormatJsonText(memInspector.Lines.Text, Pretty) then
    memInspector.Lines.Text := Pretty;
end;

procedure TQueryResultGridFrame.btnCopyInspectorClick(Sender: TObject);
begin
  if memInspector <> nil then
    Clipboard.AsText := memInspector.Lines.Text;
end;

procedure TQueryResultGridFrame.UpdateSidePanelContent;
var
  DataIdx, C, ColIdx: Integer;
  Row: TQueryRow;
  ColInfo: TQueryColumn;
  RawText, PrettyText: string;
begin
  if (pnlSide = nil) or (not pnlSide.Visible) then
    Exit;

  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
  begin
    if lblInspectorMeta <> nil then
      lblInspectorMeta.Caption := 'Célula: (sem dados)';
    if memInspector <> nil then
      memInspector.Clear;
    if grdRecordView <> nil then
      grdRecordView.RowCount := 1;
    Exit;
  end;

  DataIdx := DataRowIndexForGridRow(grdResults.Row);
  ColIdx := grdResults.Col;
  if (DataIdx < 0) or (DataIdx >= FResult.RowCount) then
  begin
    if memInspector <> nil then
      memInspector.Clear;
    if grdRecordView <> nil then
      grdRecordView.RowCount := 1;
    Exit;
  end;

  Row := FResult.GetRow(DataIdx);

  if (ColIdx >= 0) and (ColIdx < FResult.ColumnCount) and (memInspector <> nil) then
  begin
    ColInfo := FResult.GetColumn(ColIdx);
    if (ColIdx >= Length(Row)) or Row[ColIdx].IsNull then
    begin
      if lblInspectorMeta <> nil then
        lblInspectorMeta.Caption := Format('%s (%s) — NULL', [ColInfo.Name, ColInfo.DataTypeName]);
      memInspector.Lines.Text := '(NULL)';
    end
    else
    begin
      RawText := Row[ColIdx].AsText;
      if lblInspectorMeta <> nil then
        lblInspectorMeta.Caption := Format('%s (%s) — %d chars', [ColInfo.Name, ColInfo.DataTypeName, Length(RawText)]);
      if TryFormatJsonText(RawText, PrettyText) then
        memInspector.Lines.Text := PrettyText
      else
        memInspector.Lines.Text := RawText;
    end;
  end;

  if grdRecordView <> nil then
  begin
    grdRecordView.RowCount := FResult.ColumnCount + 1;
    for C := 0 to FResult.ColumnCount - 1 do
    begin
      ColInfo := FResult.GetColumn(C);
      grdRecordView.Cells[0, C + 1] := ColInfo.Name;
      grdRecordView.Cells[1, C + 1] := ColInfo.DataTypeName;
      if (C >= Length(Row)) or Row[C].IsNull then
        grdRecordView.Cells[2, C + 1] := '(NULL)'
      else
        grdRecordView.Cells[2, C + 1] := Row[C].AsText;
    end;
  end;
end;

procedure TQueryResultGridFrame.grdResultsSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateEditButtonsState;
  UpdateSidePanelContent;
  UpdateSummaryText;
end;

function TQueryResultGridFrame.BuildSelectionAggregationSuffix: string;
const
  MAX_AGG_CELLS = 20000;
var
  Sel: TGridRect;
  MinR, MaxR, MinC, MaxC, R, C, DataIdx, CellCount, NumCount: Integer;
  SumVal, MinVal, MaxVal, CurVal: Double;
  CellStr, NormStr: string;
  Row: TQueryRow;
  InvFmt: TFormatSettings;

  function TryParseGridNumber(const AStr: string; out AVal: Double): Boolean;
  var
    S: string;
    DotPos, CommaPos: Integer;
  begin
    S := Trim(AStr);
    if S = '' then
      Exit(False);
    DotPos := Pos('.', S);
    CommaPos := Pos(',', S);
    if (CommaPos > 0) and (DotPos = 0) then
      NormStr := StringReplace(S, ',', '.', [rfReplaceAll])
    else if (CommaPos > 0) and (DotPos > 0) then
    begin
      if CommaPos > DotPos then
        NormStr := StringReplace(StringReplace(S, '.', '', [rfReplaceAll]), ',', '.', [rfReplaceAll])
      else
        NormStr := StringReplace(S, ',', '', [rfReplaceAll]);
    end
    else
      NormStr := S;
    Result := TryStrToFloat(NormStr, AVal, InvFmt);
  end;

begin
  Result := '';
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  Sel := grdResults.Selection;
  if (Sel.Left = Sel.Right) and (Sel.Top = Sel.Bottom) then
    Exit;

  MinR := Max(1, Min(Sel.Top, Sel.Bottom));
  MaxR := Min(VisibleDataRowCount, Max(Sel.Top, Sel.Bottom));
  MinC := Max(0, Min(Sel.Left, Sel.Right));
  MaxC := Min(FResult.ColumnCount - 1, Max(Sel.Left, Sel.Right));
  if (MinR > MaxR) or (MinC > MaxC) then
    Exit;

  if Int64(MaxR - MinR + 1) * Int64(MaxC - MinC + 1) > MAX_AGG_CELLS then
    Exit(Format(' | Sel: %d células', [(MaxR - MinR + 1) * (MaxC - MinC + 1)]));

  InvFmt := DefaultFormatSettings;
  InvFmt.DecimalSeparator := '.';
  CellCount := 0;
  NumCount := 0;
  SumVal := 0;
  MinVal := 0;
  MaxVal := 0;

  for R := MinR to MaxR do
  begin
    DataIdx := DataRowIndexForGridRow(R);
    if (DataIdx < 0) or (DataIdx >= FResult.RowCount) then
      Continue;
    Row := FResult.GetRow(DataIdx);
    for C := MinC to MaxC do
    begin
      Inc(CellCount);
      if (C < Length(Row)) and (not Row[C].IsNull) then
      begin
        CellStr := Row[C].AsText;
        if TryParseGridNumber(CellStr, CurVal) then
        begin
          if NumCount = 0 then
          begin
            MinVal := CurVal;
            MaxVal := CurVal;
          end
          else
          begin
            if CurVal < MinVal then
              MinVal := CurVal;
            if CurVal > MaxVal then
              MaxVal := CurVal;
          end;
          SumVal := SumVal + CurVal;
          Inc(NumCount);
        end;
      end;
    end;
  end;

  if NumCount > 0 then
    Result := Format(' | Sel: %d | Soma: %g | Média: %g | Mín: %g | Máx: %g',
      [CellCount, SumVal, SumVal / NumCount, MinVal, MaxVal])
  else if CellCount > 1 then
    Result := Format(' | Sel: %d células', [CellCount]);
end;

function TQueryResultGridFrame.CollectTargetDataRowIndices(const AAllVisible: Boolean): TIntegerDynArray;
var
  Sel: TGridRect;
  MinR, MaxR, R, DataIdx, Count: Integer;
begin
  SetLength(Result, 0);
  if (FResult = nil) or (not FResult.HasResultSet) or (VisibleDataRowCount = 0) then
    Exit;

  if AAllVisible then
  begin
    SetLength(Result, VisibleDataRowCount);
    for R := 0 to VisibleDataRowCount - 1 do
    begin
      if FFilterActive then
        Result[R] := FFilteredRowIndices[R]
      else
        Result[R] := R;
    end;
    Exit;
  end;

  Sel := grdResults.Selection;
  if Sel.Top = Sel.Bottom then
    Exit(CollectTargetDataRowIndices(True));

  MinR := Max(1, Min(Sel.Top, Sel.Bottom));
  MaxR := Min(VisibleDataRowCount, Max(Sel.Top, Sel.Bottom));
  if MinR > MaxR then
    Exit(CollectTargetDataRowIndices(True));

  SetLength(Result, MaxR - MinR + 1);
  Count := 0;
  for R := MinR to MaxR do
  begin
    DataIdx := DataRowIndexForGridRow(R);
    if DataIdx >= 0 then
    begin
      Result[Count] := DataIdx;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function TQueryResultGridFrame.FormatCellSqlValue(const AColIndex: Integer; const ARow: TQueryRow): string;
var
  ValTxt, UpperType: string;
  InvFmt: TFormatSettings;
  DummyNum: Double;
begin
  if (FResult = nil) or (AColIndex < 0) or (AColIndex >= FResult.ColumnCount) or
     (AColIndex >= Length(ARow)) or ARow[AColIndex].IsNull then
    Exit('NULL');

  InvFmt := DefaultFormatSettings;
  InvFmt.DecimalSeparator := '.';
  ValTxt := ARow[AColIndex].AsText;
  UpperType := UpperCase(FResult.GetColumn(AColIndex).DataTypeName);
  if ((Pos('INT', UpperType) > 0) or (Pos('NUM', UpperType) > 0) or
      (Pos('DEC', UpperType) > 0) or (Pos('FLOAT', UpperType) > 0) or
      (Pos('DOUBLE', UpperType) > 0)) and
     TryStrToFloat(StringReplace(Trim(ValTxt), ',', '.', []), DummyNum, InvFmt) then
    Result := StringReplace(Trim(ValTxt), ',', '.', [])
  else
    Result := '''' + StringReplace(ValTxt, '''', '''''', [rfReplaceAll]) + '''';
end;

function TQueryResultGridFrame.BuildCsvForRows(const ARowIndices: array of Integer): string;
var
  SB: TStringList;
  I, C: Integer;
  Line: string;
  Row: TQueryRow;
begin
  Result := '';
  if (FResult = nil) or (FResult.ColumnCount = 0) or (Length(ARowIndices) = 0) then
    Exit;

  SB := TStringList.Create;
  try
    Line := '';
    for C := 0 to FResult.ColumnCount - 1 do
    begin
      if C > 0 then
        Line := Line + ';';
      Line := Line + EscapeCsvField(FResult.GetColumn(C).Name);
    end;
    SB.Add(Line);

    for I := 0 to High(ARowIndices) do
    begin
      Row := FResult.GetRow(ARowIndices[I]);
      Line := '';
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        if C > 0 then
          Line := Line + ';';
        if (C < Length(Row)) and (not Row[C].IsNull) then
          Line := Line + EscapeCsvField(Row[C].AsText);
      end;
      SB.Add(Line);
    end;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function TQueryResultGridFrame.BuildInsertSqlForRows(const ARowIndices: array of Integer): string;
var
  SB: TStringList;
  TblName, ColsStr, ValsStr: string;
  I, C: Integer;
  Row: TQueryRow;
begin
  Result := '';
  if (FResult = nil) or (FResult.ColumnCount = 0) or (Length(ARowIndices) = 0) then
    Exit;

  TblName := Trim(FEditableTableName);
  if TblName = '' then
    TblName := 'TABELA_DESTINO';

  ColsStr := '';
  for C := 0 to FResult.ColumnCount - 1 do
  begin
    if C > 0 then
      ColsStr := ColsStr + ', ';
    ColsStr := ColsStr + FResult.GetColumn(C).Name;
  end;

  SB := TStringList.Create;
  try
    for I := 0 to High(ARowIndices) do
    begin
      Row := FResult.GetRow(ARowIndices[I]);
      ValsStr := '';
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        if C > 0 then
          ValsStr := ValsStr + ', ';
        ValsStr := ValsStr + FormatCellSqlValue(C, Row);
      end;
      SB.Add(Format('INSERT INTO %s (%s) VALUES (%s);', [TblName, ColsStr, ValsStr]));
    end;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function TQueryResultGridFrame.BuildUpdateSqlForRows(const ARowIndices: array of Integer): string;
var
  SB: TStringList;
  TblName, KeyCol, SetStr, WhereStr: string;
  I, C, StartCol: Integer;
  Row: TQueryRow;
begin
  Result := '';
  if (FResult = nil) or (FResult.ColumnCount = 0) or (Length(ARowIndices) = 0) then
    Exit;

  TblName := Trim(FEditableTableName);
  if TblName = '' then
    TblName := 'TABELA_DESTINO';
  KeyCol := FResult.GetColumn(0).Name;
  if FResult.ColumnCount > 1 then
    StartCol := 1
  else
    StartCol := 0;

  SB := TStringList.Create;
  try
    for I := 0 to High(ARowIndices) do
    begin
      Row := FResult.GetRow(ARowIndices[I]);
      SetStr := '';
      for C := StartCol to FResult.ColumnCount - 1 do
      begin
        if SetStr <> '' then
          SetStr := SetStr + ', ';
        SetStr := SetStr + FResult.GetColumn(C).Name + ' = ' + FormatCellSqlValue(C, Row);
      end;
      if (0 >= Length(Row)) or Row[0].IsNull then
        WhereStr := KeyCol + ' IS NULL'
      else
        WhereStr := KeyCol + ' = ' + FormatCellSqlValue(0, Row);
      SB.Add(Format('UPDATE %s SET %s WHERE %s;', [TblName, SetStr, WhereStr]));
    end;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function TQueryResultGridFrame.BuildUpsertSqlForRows(const ARowIndices: array of Integer): string;
var
  SB: TStringList;
  TblName, KeyCol, ColsStr, ValsStr: string;
  I, C: Integer;
  Row: TQueryRow;
begin
  Result := '';
  if (FResult = nil) or (FResult.ColumnCount = 0) or (Length(ARowIndices) = 0) then
    Exit;

  TblName := Trim(FEditableTableName);
  if TblName = '' then
    TblName := 'TABELA_DESTINO';
  KeyCol := FResult.GetColumn(0).Name;

  ColsStr := '';
  for C := 0 to FResult.ColumnCount - 1 do
  begin
    if C > 0 then
      ColsStr := ColsStr + ', ';
    ColsStr := ColsStr + FResult.GetColumn(C).Name;
  end;

  SB := TStringList.Create;
  try
    for I := 0 to High(ARowIndices) do
    begin
      Row := FResult.GetRow(ARowIndices[I]);
      ValsStr := '';
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        if C > 0 then
          ValsStr := ValsStr + ', ';
        ValsStr := ValsStr + FormatCellSqlValue(C, Row);
      end;
      SB.Add(Format('UPDATE OR INSERT INTO %s (%s) VALUES (%s) MATCHING (%s);',
        [TblName, ColsStr, ValsStr, KeyCol]));
    end;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function TQueryResultGridFrame.BuildJsonForRows(const ARowIndices: array of Integer): string;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, C: Integer;
  Row: TQueryRow;
  ColName: string;
begin
  Result := '[]';
  if (FResult = nil) or (FResult.ColumnCount = 0) or (Length(ARowIndices) = 0) then
    Exit;

  Arr := TJSONArray.Create;
  try
    for I := 0 to High(ARowIndices) do
    begin
      Row := FResult.GetRow(ARowIndices[I]);
      Obj := TJSONObject.Create;
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        ColName := FResult.GetColumn(C).Name;
        if (C >= Length(Row)) or Row[C].IsNull then
          Obj.Add(ColName, TJSONNull.Create)
        else
          Obj.Add(ColName, Row[C].AsText);
      end;
      Arr.Add(Obj);
    end;
    Result := Arr.FormatJSON([], 2);
  finally
    Arr.Free;
  end;
end;

function TQueryResultGridFrame.BuildMarkdownForRows(const ARowIndices: array of Integer): string;
var
  SB: TStringList;
  I, C: Integer;
  Line, SepLine, CellTxt: string;
  Row: TQueryRow;
begin
  Result := '';
  if (FResult = nil) or (FResult.ColumnCount = 0) or (Length(ARowIndices) = 0) then
    Exit;

  SB := TStringList.Create;
  try
    Line := '|';
    SepLine := '|';
    for C := 0 to FResult.ColumnCount - 1 do
    begin
      Line := Line + ' ' + StringReplace(FResult.GetColumn(C).Name, '|', '\|', [rfReplaceAll]) + ' |';
      SepLine := SepLine + ' --- |';
    end;
    SB.Add(Line);
    SB.Add(SepLine);

    for I := 0 to High(ARowIndices) do
    begin
      Row := FResult.GetRow(ARowIndices[I]);
      Line := '|';
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        if (C >= Length(Row)) or Row[C].IsNull then
          CellTxt := 'NULL'
        else
        begin
          CellTxt := StringReplace(Row[C].AsText, '|', '\|', [rfReplaceAll]);
          CellTxt := StringReplace(CellTxt, #13#10, ' ', [rfReplaceAll]);
          CellTxt := StringReplace(CellTxt, #10, ' ', [rfReplaceAll]);
        end;
        Line := Line + ' ' + CellTxt + ' |';
      end;
      SB.Add(Line);
    end;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function TQueryResultGridFrame.BuildHtmlForRows(const ARowIndices: array of Integer): string;
var
  SB: TStringList;
  I, C: Integer;
  Line, CellTxt: string;
  Row: TQueryRow;

  function HtmlEsc(const S: string): string;
  begin
    Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
    Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
    Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  end;

begin
  Result := '';
  if (FResult = nil) or (FResult.ColumnCount = 0) then
    Exit;

  SB := TStringList.Create;
  try
    SB.Add('<!DOCTYPE html><html><head><meta charset="utf-8"><style>table{border-collapse:collapse;font-family:sans-serif;font-size:12px}th,td{border:1px solid #ccc;padding:4px 8px}th{background:#f0f4f8}</style></head><body><table>');
    Line := '<tr>';
    for C := 0 to FResult.ColumnCount - 1 do
      Line := Line + '<th>' + HtmlEsc(FResult.GetColumn(C).Name) + '</th>';
    Line := Line + '</tr>';
    SB.Add(Line);

    for I := 0 to High(ARowIndices) do
    begin
      Row := FResult.GetRow(ARowIndices[I]);
      Line := '<tr>';
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        if (C >= Length(Row)) or Row[C].IsNull then
          CellTxt := '<i>NULL</i>'
        else
          CellTxt := HtmlEsc(Row[C].AsText);
        Line := Line + '<td>' + CellTxt + '</td>';
      end;
      Line := Line + '</tr>';
      SB.Add(Line);
    end;
    SB.Add('</table></body></html>');
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

procedure TQueryResultGridFrame.miFilterByCellClick(Sender: TObject);
var
  DataIdx: Integer;
  Row: TQueryRow;
begin
  if (FResult = nil) or (edtQuickFilter = nil) then
    Exit;
  DataIdx := DataRowIndexForGridRow(grdResults.Row);
  if (DataIdx < 0) or (grdResults.Col < 0) or (grdResults.Col >= FResult.ColumnCount) then
    Exit;

  if pnlTopTools <> nil then
    pnlTopTools.Visible := True;
  Row := FResult.GetRow(DataIdx);
  if (grdResults.Col >= Length(Row)) or Row[grdResults.Col].IsNull then
    edtQuickFilter.Text := '(NULL)'
  else
    edtQuickFilter.Text := Row[grdResults.Col].AsText;
end;

procedure TQueryResultGridFrame.miQuickSearchClick(Sender: TObject);
begin
  if pnlTopTools <> nil then
    pnlTopTools.Visible := True;
  if (edtQuickFilter <> nil) and edtQuickFilter.CanFocus then
  begin
    edtQuickFilter.SetFocus;
    edtQuickFilter.SelectAll;
  end;
end;

procedure TQueryResultGridFrame.miClearFilterClick(Sender: TObject);
begin
  btnClearFilterClick(nil);
end;

procedure TQueryResultGridFrame.miInspectCellClick(Sender: TObject);
begin
  OpenSidePanel(False);
end;

procedure TQueryResultGridFrame.miRecordViewClick(Sender: TObject);
begin
  OpenSidePanel(True);
end;

function TQueryResultGridFrame.CollectSingleRecordIndex: TIntegerDynArray;
var
  DataIdx: Integer;
begin
  SetLength(Result, 0);
  DataIdx := DataRowIndexForGridRow(grdResults.Row);
  if DataIdx >= 0 then
  begin
    SetLength(Result, 1);
    Result[0] := DataIdx;
  end;
end;

function TQueryResultGridFrame.CollectAllQueryRowIndices: TIntegerDynArray;
begin
  SetLength(Result, 0);
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  if FResult.HasMoreRows then
  begin
    Screen.Cursor := crHourGlass;
    try
      FResult.FetchAll;
      RefreshRowCount;
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  Result := CollectTargetDataRowIndices(True);
end;

procedure TQueryResultGridFrame.miRecCsvClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectSingleRecordIndex;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildCsvForRows(Indices);
end;

procedure TQueryResultGridFrame.miRecInsertClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectSingleRecordIndex;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildInsertSqlForRows(Indices);
end;

procedure TQueryResultGridFrame.miRecUpdateClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectSingleRecordIndex;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildUpdateSqlForRows(Indices);
end;

procedure TQueryResultGridFrame.miRecUpsertClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectSingleRecordIndex;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildUpsertSqlForRows(Indices);
end;

procedure TQueryResultGridFrame.miRecJsonClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectSingleRecordIndex;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildJsonForRows(Indices);
end;

procedure TQueryResultGridFrame.miRecMarkdownClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectSingleRecordIndex;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildMarkdownForRows(Indices);
end;

procedure TQueryResultGridFrame.miCopyAllCsvClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectAllQueryRowIndices;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildCsvForRows(Indices);
end;

procedure TQueryResultGridFrame.miAllInsertClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectAllQueryRowIndices;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildInsertSqlForRows(Indices);
end;

procedure TQueryResultGridFrame.miAllUpdateClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectAllQueryRowIndices;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildUpdateSqlForRows(Indices);
end;

procedure TQueryResultGridFrame.miAllUpsertClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectAllQueryRowIndices;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildUpsertSqlForRows(Indices);
end;

procedure TQueryResultGridFrame.miAllJsonClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectAllQueryRowIndices;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildJsonForRows(Indices);
end;

procedure TQueryResultGridFrame.miAllMarkdownClick(Sender: TObject);
var
  Indices: TIntegerDynArray;
begin
  Indices := CollectAllQueryRowIndices;
  if Length(Indices) > 0 then
    Clipboard.AsText := BuildMarkdownForRows(Indices);
end;

end.
