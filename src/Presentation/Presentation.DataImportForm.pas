unit Presentation.DataImportForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Clipbrd, Forms, Controls, Graphics, Dialogs,
  ExtCtrls, StdCtrls, ComCtrls, Grids, LCLType,
  zipper, DOM, XMLRead
  {$IFDEF WINDOWS}, ComObj, Variants{$ENDIF},
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Domain.TableStructureTypes,
  Application.BrowseSchemaUseCase,
  Application.ManageDatabaseObjectsUseCase,
  Application.ManageTableStructureUseCase,
  Presentation.DdlPreviewDialog;

type
  TImportColumnMap = record
    Include: Boolean;
    IsKey: Boolean;
    TargetColName: string;
    TargetDataType: string;
    IsComputed: Boolean;
    SourceColIndex: Integer; // >= 0: file column index; -1: ignore; -2: fixed value
    FixedValue: string;
  end;

  { Ferramenta de Importação de Dados estilo IBExpert (Excel / CSV / TXT -> Tabela Existente ou Nova Tabela) }
  TDataImportForm = class(TForm)
  private
    FFactory: IDatabaseProviderFactory;
    FProfiles: TConnectionProfileList;
    FInitialTableName: string;
    FStructure: TTableStructure;
    FMappings: array of TImportColumnMap;
    FCsvHeaders: array of string;
    FCsvRows: array of TStringArray;
    FImportedAny: Boolean;
    FIsLoadingTable: Boolean;

    pnlTop: TPanel;
    pnlRow1: TPanel;
    lblFile: TLabel;
    edtFilePath: TEdit;
    btnBrowseFile: TButton;
    lblDelim: TLabel;
    cbDelimiter: TComboBox;
    lblQuote: TLabel;
    cbQuoteChar: TComboBox;
    chkHasHeader: TCheckBox;
    btnReloadFile: TButton;

    pnlRow2: TPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    lblTable: TLabel;
    cbTable: TComboBox;
    edtNewTableName: TEdit;
    chkCreateNewTable: TCheckBox;
    lblMode: TLabel;
    cbImportMode: TComboBox;
    chkDeleteBefore: TCheckBox;

    pnlRow3: TPanel;
    lblBatch: TLabel;
    cbCommitBatch: TComboBox;
    chkStopOnError: TCheckBox;
    btnAutoMapName: TButton;
    btnAutoMapOrder: TButton;
    btnDropTable: TButton;

    pgMain: TPageControl;
    tsMapping: TTabSheet;
    grdMapping: TStringGrid;
    tsPreview: TTabSheet;
    grdPreview: TStringGrid;
    tsLog: TTabSheet;
    memLog: TMemo;

    pnlBottom: TPanel;
    ProgressBar1: TProgressBar;
    lblStatus: TLabel;
    btnPreviewSql: TButton;
    btnImport: TButton;
    btnClose: TButton;
    dlgOpenFile: TOpenDialog;

    procedure BuildUI(const AInitialProfile: TConnectionProfile);
    function SelectedProfile: TConnectionProfile;
    function SelectedDelimiter: Char;
    function SelectedQuoteChar: Char;
    function SelectedBatchSize: Integer;
    procedure LoadTablesForSelectedConnection;
    procedure LoadTargetTableColumns;
    procedure LoadDataFile;
    procedure ParseCsvFile(const AFilePath: string);
    function ParseXlsxFile(const AFilePath: string): Boolean;
    function ParseXlsViaOle(const AFilePath: string): Boolean;
    procedure FinalizeLoadedRows(const AAllRows: array of TStringArray; const AMaxCols: Integer);
    procedure PopulatePreviewGrid;
    function SanitizeSqlIdentifier(const AText: string; const AFallbackIndex: Integer): string;
    function InferColumnSqlType(const AColIdx: Integer; const ADbType: TDatabaseType): string;
    procedure BuildMappingsForNewTable;
    procedure AutoMapByName;
    procedure AutoMapByOrder;
    procedure RefreshMappingGrid;
    procedure UpdateStatusSummary;
    procedure UpdateTableModeUI;
    function FormatSqlLiteral(const ATargetType, ARawValue: string): string;
    function BuildCreateTableDDL(
      const ADbType: TDatabaseType;
      const ATableName: string;
      out AError: string
    ): string;
    function BuildRowImportSQL(
      const ADbType: TDatabaseType;
      const ATableName: string;
      const ARowIdx: Integer;
      out AError: string
    ): string;
    procedure ChooseSourceForMappingRow(const AMapIdx: Integer);

    procedure btnBrowseFileClick(Sender: TObject);
    procedure btnReloadFileClick(Sender: TObject);
    procedure cbDelimiterChange(Sender: TObject);
    procedure cbConnectionChange(Sender: TObject);
    procedure cbTableChange(Sender: TObject);
    procedure chkCreateNewTableClick(Sender: TObject);
    procedure btnAutoMapNameClick(Sender: TObject);
    procedure btnAutoMapOrderClick(Sender: TObject);
    procedure btnDropTableClick(Sender: TObject);
    procedure grdMappingMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure grdMappingDblClick(Sender: TObject);
    procedure grdMappingKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnPreviewSqlClick(Sender: TObject);
    procedure btnImportClick(Sender: TObject);
  public
    class function Execute(
      const AFactory: IDatabaseProviderFactory;
      const AConnections: TConnectionProfileList;
      const AInitialProfile: TConnectionProfile;
      const AInitialTableName: string = ''
    ): Boolean;
    destructor Destroy; override;
  end;

implementation

procedure DeleteDirectoryRecursive(const ADir: string);
var
  CleanDir: string;
  SR: SysUtils.TSearchRec;
begin
  CleanDir := IncludeTrailingPathDelimiter(ADir);
  if not DirectoryExists(CleanDir) then
    Exit;
  if SysUtils.FindFirst(CleanDir + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          if (SR.Attr and faDirectory) <> 0 then
            DeleteDirectoryRecursive(CleanDir + SR.Name)
          else
            SysUtils.DeleteFile(CleanDir + SR.Name);
        end;
      until SysUtils.FindNext(SR) <> 0;
    finally
      SysUtils.FindClose(SR);
    end;
  end;
  RemoveDir(ExcludeTrailingPathDelimiter(CleanDir));
end;

function DecodeExcelColumnIndex(const ACellRef: string): Integer;
var
  I, ColNum: Integer;
begin
  ColNum := 0;
  for I := 1 to Length(ACellRef) do
  begin
    if ACellRef[I] in ['A'..'Z'] then
      ColNum := ColNum * 26 + (Ord(ACellRef[I]) - Ord('A') + 1)
    else if ACellRef[I] in ['a'..'z'] then
      ColNum := ColNum * 26 + (Ord(ACellRef[I]) - Ord('a') + 1)
    else
      Break;
  end;
  if ColNum > 0 then
    Result := ColNum - 1
  else
    Result := -1;
end;

function CollectXmlTextRecursive(const ANode: TDOMNode): string;
var
  Child: TDOMNode;
begin
  Result := '';
  if ANode = nil then
    Exit;
  if ANode.NodeType in [TEXT_NODE, CDATA_SECTION_NODE] then
  begin
    Result := string(ANode.NodeValue);
    Exit;
  end;
  if ANode.NodeName = 'rPh' then
    Exit;
  Child := ANode.FirstChild;
  while Child <> nil do
  begin
    Result := Result + CollectXmlTextRecursive(Child);
    Child := Child.NextSibling;
  end;
end;

{ TDataImportForm }

class function TDataImportForm.Execute(
  const AFactory: IDatabaseProviderFactory;
  const AConnections: TConnectionProfileList;
  const AInitialProfile: TConnectionProfile;
  const AInitialTableName: string
): Boolean;
var
  Frm: TDataImportForm;
  P: TConnectionProfile;
  FoundInitial: Boolean;
begin
  Result := False;
  if AFactory = nil then
    Exit;

  Frm := TDataImportForm.CreateNew(nil);
  try
    Frm.FFactory := AFactory;
    Frm.FInitialTableName := Trim(AInitialTableName);
    Frm.FStructure := TTableStructure.Create;
    Frm.FProfiles := TConnectionProfileList.Create(True);
    FoundInitial := False;
    if AConnections <> nil then
    begin
      for P in AConnections do
      begin
        Frm.FProfiles.Add(P.Clone);
        if (AInitialProfile <> nil) and SameText(P.Id, AInitialProfile.Id) then
          FoundInitial := True;
      end;
    end;
    if (AInitialProfile <> nil) and (not FoundInitial) then
      Frm.FProfiles.Insert(0, AInitialProfile.Clone);

    Frm.BuildUI(AInitialProfile);
    Frm.LoadTablesForSelectedConnection;
    Frm.ShowModal;
    Result := Frm.FImportedAny;
  finally
    Frm.Free;
  end;
end;

destructor TDataImportForm.Destroy;
begin
  FreeAndNil(FStructure);
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TDataImportForm.BuildUI(const AInitialProfile: TConnectionProfile);
var
  I, SelIdx: Integer;
begin
  Caption := 'Importar Dados (Import Data - Excel / CSV / TXT)';
  Position := poScreenCenter;
  Width := 1080;
  Height := 720;
  Constraints.MinWidth := 860;
  Constraints.MinHeight := 560;

  dlgOpenFile := TOpenDialog.Create(Self);
  dlgOpenFile.Filter :=
    'Excel e CSV (*.xlsx;*.xls;*.csv;*.txt;*.tsv)|*.xlsx;*.xls;*.csv;*.txt;*.tsv|' +
    'Excel (*.xlsx;*.xls)|*.xlsx;*.xls|' +
    'CSV / Texto (*.csv;*.txt;*.tsv)|*.csv;*.txt;*.tsv|' +
    'Todos os arquivos (*.*)|*.*';

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.AutoSize := True;
  pnlTop.BevelOuter := bvNone;
  pnlTop.BorderSpacing.Around := 6;

  pnlRow3 := TPanel.Create(Self);
  pnlRow3.Parent := pnlTop;
  pnlRow3.Align := alTop;
  pnlRow3.Height := 34;
  pnlRow3.BevelOuter := bvNone;

  pnlRow2 := TPanel.Create(Self);
  pnlRow2.Parent := pnlTop;
  pnlRow2.Align := alTop;
  pnlRow2.Height := 34;
  pnlRow2.BevelOuter := bvNone;

  pnlRow1 := TPanel.Create(Self);
  pnlRow1.Parent := pnlTop;
  pnlRow1.Align := alTop;
  pnlRow1.Height := 34;
  pnlRow1.BevelOuter := bvNone;

  { Row 1: File & CSV options }
  lblFile := TLabel.Create(Self);
  lblFile.Parent := pnlRow1;
  lblFile.Left := 4;
  lblFile.Top := 9;
  lblFile.Caption := 'Arquivo:';

  edtFilePath := TEdit.Create(Self);
  edtFilePath.Parent := pnlRow1;
  edtFilePath.Left := 56;
  edtFilePath.Top := 5;
  edtFilePath.Width := 320;
  edtFilePath.TextHint := 'Selecione Excel (.xlsx/.xls) ou CSV/TXT...';

  btnBrowseFile := TButton.Create(Self);
  btnBrowseFile.Parent := pnlRow1;
  btnBrowseFile.Left := 382;
  btnBrowseFile.Top := 4;
  btnBrowseFile.Width := 36;
  btnBrowseFile.Height := 25;
  btnBrowseFile.Caption := '...';
  btnBrowseFile.OnClick := @btnBrowseFileClick;

  lblDelim := TLabel.Create(Self);
  lblDelim.Parent := pnlRow1;
  lblDelim.Left := 428;
  lblDelim.Top := 9;
  lblDelim.Caption := 'Separador:';

  cbDelimiter := TComboBox.Create(Self);
  cbDelimiter.Parent := pnlRow1;
  cbDelimiter.Left := 492;
  cbDelimiter.Top := 5;
  cbDelimiter.Width := 130;
  cbDelimiter.Style := csDropDownList;
  cbDelimiter.Items.Add('; (Ponto e vírgula)');
  cbDelimiter.Items.Add(', (Vírgula)');
  cbDelimiter.Items.Add('Tab (\t)');
  cbDelimiter.Items.Add('| (Pipe)');
  cbDelimiter.ItemIndex := 0;
  cbDelimiter.OnChange := @cbDelimiterChange;

  lblQuote := TLabel.Create(Self);
  lblQuote.Parent := pnlRow1;
  lblQuote.Left := 630;
  lblQuote.Top := 9;
  lblQuote.Caption := 'Aspas:';

  cbQuoteChar := TComboBox.Create(Self);
  cbQuoteChar.Parent := pnlRow1;
  cbQuoteChar.Left := 672;
  cbQuoteChar.Top := 5;
  cbQuoteChar.Width := 115;
  cbQuoteChar.Style := csDropDownList;
  cbQuoteChar.Items.Add('" (Duplas)');
  cbQuoteChar.Items.Add(''' (Simples)');
  cbQuoteChar.Items.Add('Nenhum');
  cbQuoteChar.ItemIndex := 0;
  cbQuoteChar.OnChange := @cbDelimiterChange;

  chkHasHeader := TCheckBox.Create(Self);
  chkHasHeader.Parent := pnlRow1;
  chkHasHeader.Left := 796;
  chkHasHeader.Top := 7;
  chkHasHeader.Caption := '1ª linha é cabeçalho';
  chkHasHeader.Checked := True;
  chkHasHeader.OnClick := @cbDelimiterChange;

  btnReloadFile := TButton.Create(Self);
  btnReloadFile.Parent := pnlRow1;
  btnReloadFile.Left := 944;
  btnReloadFile.Top := 4;
  btnReloadFile.Width := 90;
  btnReloadFile.Height := 25;
  btnReloadFile.Caption := 'Ler Arquivo';
  btnReloadFile.OnClick := @btnReloadFileClick;

  { Row 2: Connection, Table / New Table, Mode }
  lblConn := TLabel.Create(Self);
  lblConn.Parent := pnlRow2;
  lblConn.Left := 4;
  lblConn.Top := 9;
  lblConn.Caption := 'Conexão:';

  cbConnection := TComboBox.Create(Self);
  cbConnection.Parent := pnlRow2;
  cbConnection.Left := 62;
  cbConnection.Top := 5;
  cbConnection.Width := 210;
  cbConnection.Style := csDropDownList;
  SelIdx := -1;
  for I := 0 to FProfiles.Count - 1 do
  begin
    cbConnection.Items.AddObject(
      Format('%s [%s]', [FProfiles[I].Name, DatabaseTypeToStr(FProfiles[I].DatabaseType)]),
      FProfiles[I]
    );
    if (AInitialProfile <> nil) and SameText(FProfiles[I].Id, AInitialProfile.Id) then
      SelIdx := I;
  end;
  if (SelIdx < 0) and (cbConnection.Items.Count > 0) then
    SelIdx := 0;
  cbConnection.ItemIndex := SelIdx;
  cbConnection.OnChange := @cbConnectionChange;

  chkCreateNewTable := TCheckBox.Create(Self);
  chkCreateNewTable.Parent := pnlRow2;
  chkCreateNewTable.Left := 282;
  chkCreateNewTable.Top := 7;
  chkCreateNewTable.Caption := 'Criar Nova Tabela';
  chkCreateNewTable.Checked := False;
  chkCreateNewTable.OnClick := @chkCreateNewTableClick;

  lblTable := TLabel.Create(Self);
  lblTable.Parent := pnlRow2;
  lblTable.Left := 408;
  lblTable.Top := 9;
  lblTable.Caption := 'Tabela:';

  cbTable := TComboBox.Create(Self);
  cbTable.Parent := pnlRow2;
  cbTable.Left := 454;
  cbTable.Top := 5;
  cbTable.Width := 200;
  cbTable.Style := csDropDownList;
  cbTable.OnChange := @cbTableChange;

  edtNewTableName := TEdit.Create(Self);
  edtNewTableName.Parent := pnlRow2;
  edtNewTableName.Left := 454;
  edtNewTableName.Top := 5;
  edtNewTableName.Width := 200;
  edtNewTableName.Visible := False;
  edtNewTableName.TextHint := 'NOME_DA_NOVA_TABELA';

  lblMode := TLabel.Create(Self);
  lblMode.Parent := pnlRow2;
  lblMode.Left := 664;
  lblMode.Top := 9;
  lblMode.Caption := 'Modo:';

  cbImportMode := TComboBox.Create(Self);
  cbImportMode.Parent := pnlRow2;
  cbImportMode.Left := 702;
  cbImportMode.Top := 5;
  cbImportMode.Width := 210;
  cbImportMode.Style := csDropDownList;
  cbImportMode.Items.Add('INSERT (Inserir registros)');
  cbImportMode.Items.Add('UPDATE OR INSERT / UPSERT (Chave)');
  cbImportMode.Items.Add('UPDATE (Atualizar pela Chave)');
  cbImportMode.ItemIndex := 0;

  chkDeleteBefore := TCheckBox.Create(Self);
  chkDeleteBefore.Parent := pnlRow2;
  chkDeleteBefore.Left := 920;
  chkDeleteBefore.Top := 7;
  chkDeleteBefore.Caption := 'Limpar tabela antes';
  chkDeleteBefore.Checked := False;

  { Row 3: Commit batch, error handling, auto-map }
  lblBatch := TLabel.Create(Self);
  lblBatch.Parent := pnlRow3;
  lblBatch.Left := 4;
  lblBatch.Top := 9;
  lblBatch.Caption := 'Transação:';

  cbCommitBatch := TComboBox.Create(Self);
  cbCommitBatch.Parent := pnlRow3;
  cbCommitBatch.Left := 68;
  cbCommitBatch.Top := 5;
  cbCommitBatch.Width := 230;
  cbCommitBatch.Style := csDropDownList;
  cbCommitBatch.Items.Add('Transação Única (Rollback se falhar)');
  cbCommitBatch.Items.Add('Commit a cada 100 linhas');
  cbCommitBatch.Items.Add('Commit a cada 500 linhas');
  cbCommitBatch.Items.Add('Commit a cada 1000 linhas');
  cbCommitBatch.ItemIndex := 0;

  chkStopOnError := TCheckBox.Create(Self);
  chkStopOnError.Parent := pnlRow3;
  chkStopOnError.Left := 308;
  chkStopOnError.Top := 7;
  chkStopOnError.Caption := 'Parar no primeiro erro';
  chkStopOnError.Checked := True;

  btnAutoMapName := TButton.Create(Self);
  btnAutoMapName.Parent := pnlRow3;
  btnAutoMapName.Left := 470;
  btnAutoMapName.Top := 4;
  btnAutoMapName.Width := 130;
  btnAutoMapName.Height := 25;
  btnAutoMapName.Caption := 'Mapear por Nome';
  btnAutoMapName.OnClick := @btnAutoMapNameClick;

  btnAutoMapOrder := TButton.Create(Self);
  btnAutoMapOrder.Parent := pnlRow3;
  btnAutoMapOrder.Left := 608;
  btnAutoMapOrder.Top := 4;
  btnAutoMapOrder.Width := 130;
  btnAutoMapOrder.Height := 25;
  btnAutoMapOrder.Caption := 'Mapear por Ordem';
  btnAutoMapOrder.OnClick := @btnAutoMapOrderClick;

  btnDropTable := TButton.Create(Self);
  btnDropTable.Parent := pnlRow3;
  btnDropTable.Left := 748;
  btnDropTable.Top := 4;
  btnDropTable.Width := 135;
  btnDropTable.Height := 25;
  btnDropTable.Caption := 'Excluir Tabela...';
  btnDropTable.OnClick := @btnDropTableClick;

  { Bottom Panel }
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 64;
  pnlBottom.BevelOuter := bvNone;

  ProgressBar1 := TProgressBar.Create(Self);
  ProgressBar1.Parent := pnlBottom;
  ProgressBar1.Left := 8;
  ProgressBar1.Top := 6;
  ProgressBar1.Width := Width - 16;
  ProgressBar1.Height := 14;
  ProgressBar1.Anchors := [akTop, akLeft, akRight];

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := pnlBottom;
  lblStatus.Left := 8;
  lblStatus.Top := 32;
  lblStatus.Caption := 'Selecione um arquivo Excel (.xlsx/.xls) ou CSV/TXT e a tabela de destino.';

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlBottom;
  btnClose.Caption := 'Fechar';
  btnClose.ModalResult := mrCancel;
  btnClose.Cancel := True;
  btnClose.Width := 95;
  btnClose.Height := 28;
  btnClose.Left := pnlBottom.Width - 103;
  btnClose.Top := 28;
  btnClose.Anchors := [akTop, akRight];

  btnImport := TButton.Create(Self);
  btnImport.Parent := pnlBottom;
  btnImport.Caption := 'Importar Dados Agora';
  btnImport.Width := 165;
  btnImport.Height := 28;
  btnImport.Left := btnClose.Left - 173;
  btnImport.Top := 28;
  btnImport.Anchors := [akTop, akRight];
  btnImport.OnClick := @btnImportClick;

  btnPreviewSql := TButton.Create(Self);
  btnPreviewSql.Parent := pnlBottom;
  btnPreviewSql.Caption := 'Gerar Script SQL (Log)';
  btnPreviewSql.Width := 160;
  btnPreviewSql.Height := 28;
  btnPreviewSql.Left := btnImport.Left - 168;
  btnPreviewSql.Top := 28;
  btnPreviewSql.Anchors := [akTop, akRight];
  btnPreviewSql.OnClick := @btnPreviewSqlClick;

  { Main PageControl }
  pgMain := TPageControl.Create(Self);
  pgMain.Parent := Self;
  pgMain.Align := alClient;
  pgMain.BorderSpacing.Left := 6;
  pgMain.BorderSpacing.Right := 6;

  tsMapping := TTabSheet.Create(pgMain);
  tsMapping.PageControl := pgMain;
  tsMapping.Caption := 'Mapeamento de Colunas (Duplo clique para editar nome/tipo/origem)';

  grdMapping := TStringGrid.Create(Self);
  grdMapping.Parent := tsMapping;
  grdMapping.Align := alClient;
  grdMapping.ColCount := 6;
  grdMapping.FixedCols := 0;
  grdMapping.FixedRows := 1;
  grdMapping.RowCount := 1;
  grdMapping.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect, goColSizing, goThumbTracking];
  grdMapping.Cells[0, 0] := 'Importar';
  grdMapping.Cells[1, 0] := 'Coluna Destino';
  grdMapping.Cells[2, 0] := 'Tipo no Banco';
  grdMapping.Cells[3, 0] := 'Chave (PK)';
  grdMapping.Cells[4, 0] := 'Origem no Arquivo / Valor';
  grdMapping.Cells[5, 0] := 'Amostra (1ª Linha)';
  grdMapping.ColWidths[0] := 65;
  grdMapping.ColWidths[1] := 190;
  grdMapping.ColWidths[2] := 155;
  grdMapping.ColWidths[3] := 75;
  grdMapping.ColWidths[4] := 260;
  grdMapping.ColWidths[5] := 250;
  grdMapping.OnMouseDown := @grdMappingMouseDown;
  grdMapping.OnDblClick := @grdMappingDblClick;
  grdMapping.OnKeyDown := @grdMappingKeyDown;

  tsPreview := TTabSheet.Create(pgMain);
  tsPreview.PageControl := pgMain;
  tsPreview.Caption := 'Pré-visualização do Arquivo';

  grdPreview := TStringGrid.Create(Self);
  grdPreview.Parent := tsPreview;
  grdPreview.Align := alClient;
  grdPreview.FixedCols := 0;
  grdPreview.FixedRows := 1;
  grdPreview.RowCount := 1;
  grdPreview.ColCount := 1;
  grdPreview.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goThumbTracking];

  tsLog := TTabSheet.Create(pgMain);
  tsLog.PageControl := pgMain;
  tsLog.Caption := 'Script SQL / Log';

  memLog := TMemo.Create(Self);
  memLog.Parent := tsLog;
  memLog.Align := alClient;
  memLog.ScrollBars := ssBoth;
  memLog.WordWrap := False;
  memLog.Font.Name := 'Consolas';
end;

function TDataImportForm.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection <> nil) and (cbConnection.ItemIndex >= 0) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

function TDataImportForm.SelectedDelimiter: Char;
begin
  case cbDelimiter.ItemIndex of
    1: Result := ',';
    2: Result := #9;
    3: Result := '|';
  else
    Result := ';';
  end;
end;

function TDataImportForm.SelectedQuoteChar: Char;
begin
  case cbQuoteChar.ItemIndex of
    1: Result := '''';
    2: Result := #0;
  else
    Result := '"';
  end;
end;

function TDataImportForm.SelectedBatchSize: Integer;
begin
  case cbCommitBatch.ItemIndex of
    1: Result := 100;
    2: Result := 500;
    3: Result := 1000;
  else
    Result := 0;
  end;
end;

procedure TDataImportForm.UpdateTableModeUI;
var
  IsNewMode: Boolean;
begin
  IsNewMode := chkCreateNewTable.Checked;
  cbTable.Visible := not IsNewMode;
  edtNewTableName.Visible := IsNewMode;
  if IsNewMode then
  begin
    cbImportMode.ItemIndex := 0;
    cbImportMode.Enabled := False;
    chkDeleteBefore.Checked := False;
    chkDeleteBefore.Enabled := False;
  end
  else
  begin
    cbImportMode.Enabled := True;
    chkDeleteBefore.Enabled := True;
  end;
  if btnDropTable <> nil then
    btnDropTable.Enabled := not IsNewMode;
end;

procedure TDataImportForm.LoadTablesForSelectedConnection;
var
  Profile: TConnectionProfile;
  Browser: TBrowseSchemaUseCase;
  Tables: TStringList;
  I, SelIdx: Integer;
begin
  cbTable.Items.Clear;
  Profile := SelectedProfile;
  if Profile = nil then
    Exit;

  FIsLoadingTable := True;
  Screen.Cursor := crHourGlass;
  try
    Browser := TBrowseSchemaUseCase.Create(FFactory);
    try
      Tables := Browser.ListObjects(Profile, sokTables);
      try
        cbTable.Items.Assign(Tables);
      finally
        Tables.Free;
      end;
    finally
      Browser.Free;
    end;

    SelIdx := -1;
    if FInitialTableName <> '' then
    begin
      for I := 0 to cbTable.Items.Count - 1 do
      begin
        if SameText(cbTable.Items[I], FInitialTableName) then
        begin
          SelIdx := I;
          Break;
        end;
      end;
    end;
    if (SelIdx < 0) and (cbTable.Items.Count > 0) then
      SelIdx := 0;
    cbTable.ItemIndex := SelIdx;
  finally
    FIsLoadingTable := False;
    Screen.Cursor := crDefault;
  end;

  if chkCreateNewTable.Checked then
    BuildMappingsForNewTable
  else
    LoadTargetTableColumns;
end;

procedure TDataImportForm.LoadTargetTableColumns;
var
  Profile: TConnectionProfile;
  TblName: string;
  UseCase: TManageTableStructureUseCase;
  LoadedStruct: TTableStructure;
  I: Integer;
begin
  FStructure.Clear;
  SetLength(FMappings, 0);
  Profile := SelectedProfile;
  TblName := Trim(cbTable.Text);
  if (Profile = nil) or (TblName = '') then
  begin
    RefreshMappingGrid;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    UseCase := TManageTableStructureUseCase.Create(FFactory);
    try
      LoadedStruct := UseCase.LoadTableStructure(Profile, TblName);
      try
        FreeAndNil(FStructure);
        FStructure := LoadedStruct;
        LoadedStruct := nil;
      finally
        LoadedStruct.Free;
      end;
    finally
      UseCase.Free;
    end;

    SetLength(FMappings, Length(FStructure.Columns));
    for I := 0 to High(FStructure.Columns) do
    begin
      FMappings[I].TargetColName := FStructure.Columns[I].ColumnName;
      FMappings[I].TargetDataType := FStructure.Columns[I].DataType;
      FMappings[I].IsComputed := FStructure.Columns[I].IsComputed;
      FMappings[I].Include := not FStructure.Columns[I].IsComputed;
      FMappings[I].IsKey := FStructure.Columns[I].IsPrimaryKey;
      FMappings[I].SourceColIndex := -1;
      FMappings[I].FixedValue := '';
    end;

    if Length(FCsvHeaders) > 0 then
      AutoMapByName
    else
      RefreshMappingGrid;
  finally
    Screen.Cursor := crDefault;
  end;
end;

function TDataImportForm.SanitizeSqlIdentifier(const AText: string; const AFallbackIndex: Integer): string;
var
  I: Integer;
  S, OutStr: string;
  Ch: Char;
begin
  S := Trim(AText);
  OutStr := '';
  for I := 1 to Length(S) do
  begin
    Ch := UpCase(S[I]);
    if Ch in ['A'..'Z', '0'..'9', '_'] then
      OutStr := OutStr + Ch
    else if Ch in [' ', '-', '.', '/', '\', ';', ','] then
    begin
      if (OutStr <> '') and (OutStr[Length(OutStr)] <> '_') then
        OutStr := OutStr + '_';
    end;
  end;
  while (OutStr <> '') and (OutStr[Length(OutStr)] = '_') do
    Delete(OutStr, Length(OutStr), 1);
  if (OutStr = '') or (OutStr[1] in ['0'..'9']) then
    OutStr := 'COL_' + IntToStr(AFallbackIndex) + '_' + OutStr;
  if Length(OutStr) > 31 then
    OutStr := Copy(OutStr, 1, 31);
  Result := OutStr;
end;

function TDataImportForm.InferColumnSqlType(const AColIdx: Integer; const ADbType: TDatabaseType): string;
var
  R, ScanLimit, MaxLen, NonEmptyCount: Integer;
  Val, NormNum: string;
  AllInt, AllNum, HasDot: Boolean;
  IntVal: Int64;
  DblVal: Double;
  InvFmt: TFormatSettings;
begin
  ScanLimit := Min(200, Length(FCsvRows));
  MaxLen := 0;
  NonEmptyCount := 0;
  AllInt := True;
  AllNum := True;
  InvFmt := DefaultFormatSettings;
  InvFmt.DecimalSeparator := '.';

  for R := 0 to ScanLimit - 1 do
  begin
    if AColIdx < Length(FCsvRows[R]) then
      Val := Trim(FCsvRows[R][AColIdx])
    else
      Val := '';
    if (Val = '') or SameText(Val, 'NULL') or SameText(Val, '(NULL)') then
      Continue;

    Inc(NonEmptyCount);
    if Length(Val) > MaxLen then
      MaxLen := Length(Val);

    if not TryStrToInt64(Val, IntVal) then
      AllInt := False;

    if (Pos(',', Val) > 0) and (Pos('.', Val) = 0) then
      NormNum := StringReplace(Val, ',', '.', [rfReplaceAll])
    else if (Pos(',', Val) > 0) and (Pos('.', Val) > 0) then
      NormNum := StringReplace(StringReplace(Val, '.', '', [rfReplaceAll]), ',', '.', [rfReplaceAll])
    else
      NormNum := Val;

    HasDot := Pos('.', NormNum) > 0;
    if not TryStrToFloat(NormNum, DblVal, InvFmt) then
      AllNum := False
    else if not HasDot then
    begin
      if (Length(Val) > 1) and (Val[1] = '0') then
      begin
        { Preserve leading zeros like CEP / CPF / codes as VARCHAR }
        AllInt := False;
        AllNum := False;
      end;
    end;
  end;

  if (NonEmptyCount > 0) and AllInt then
  begin
    if MaxLen > 9 then
      Result := 'BIGINT'
    else
      Result := 'INTEGER';
  end
  else if (NonEmptyCount > 0) and AllNum then
    Result := 'NUMERIC(18,4)'
  else if MaxLen > 4000 then
  begin
    if ADbType = dtFirebird then
      Result := 'BLOB SUB_TYPE TEXT'
    else
      Result := 'TEXT';
  end
  else if MaxLen <= 60 then
    Result := 'VARCHAR(60)'
  else if MaxLen <= 120 then
    Result := 'VARCHAR(120)'
  else if MaxLen <= 255 then
    Result := 'VARCHAR(255)'
  else if MaxLen <= 500 then
    Result := 'VARCHAR(500)'
  else if MaxLen <= 1000 then
    Result := 'VARCHAR(1000)'
  else
    Result := 'VARCHAR(4000)';
end;

procedure TDataImportForm.BuildMappingsForNewTable;
var
  I: Integer;
  Prof: TConnectionProfile;
  DbType: TDatabaseType;
begin
  Prof := SelectedProfile;
  if Prof <> nil then
    DbType := Prof.DatabaseType
  else
    DbType := dtFirebird;

  if Length(FCsvHeaders) = 0 then
  begin
    SetLength(FMappings, 0);
    RefreshMappingGrid;
    Exit;
  end;

  SetLength(FMappings, Length(FCsvHeaders));
  for I := 0 to High(FCsvHeaders) do
  begin
    FMappings[I].TargetColName := SanitizeSqlIdentifier(FCsvHeaders[I], I + 1);
    FMappings[I].TargetDataType := InferColumnSqlType(I, DbType);
    FMappings[I].IsComputed := False;
    FMappings[I].Include := True;
    FMappings[I].IsKey := (I = 0) and SameText(FMappings[I].TargetColName, 'ID');
    FMappings[I].SourceColIndex := I;
    FMappings[I].FixedValue := '';
  end;
  RefreshMappingGrid;
end;

procedure TDataImportForm.FinalizeLoadedRows(const AAllRows: array of TStringArray; const AMaxCols: Integer);
var
  I, RowCnt: Integer;
begin
  RowCnt := Length(AAllRows);
  if (RowCnt = 0) or (AMaxCols = 0) then
  begin
    SetLength(FCsvHeaders, 0);
    SetLength(FCsvRows, 0);
    PopulatePreviewGrid;
    RefreshMappingGrid;
    Exit;
  end;

  SetLength(FCsvHeaders, AMaxCols);
  if chkHasHeader.Checked then
  begin
    for I := 0 to AMaxCols - 1 do
    begin
      if I < Length(AAllRows[0]) then
        FCsvHeaders[I] := Trim(AAllRows[0][I])
      else
        FCsvHeaders[I] := '';
      if FCsvHeaders[I] = '' then
        FCsvHeaders[I] := Format('Coluna_%d', [I + 1]);
    end;
    SetLength(FCsvRows, RowCnt - 1);
    for I := 1 to RowCnt - 1 do
      FCsvRows[I - 1] := AAllRows[I];
  end
  else
  begin
    for I := 0 to AMaxCols - 1 do
      FCsvHeaders[I] := Format('Coluna_%d', [I + 1]);
    SetLength(FCsvRows, RowCnt);
    for I := 0 to RowCnt - 1 do
      FCsvRows[I] := AAllRows[I];
  end;

  if Trim(edtNewTableName.Text) = '' then
    edtNewTableName.Text := SanitizeSqlIdentifier(ChangeFileExt(ExtractFileName(edtFilePath.Text), ''), 1);

  PopulatePreviewGrid;
  if chkCreateNewTable.Checked then
    BuildMappingsForNewTable
  else
    AutoMapByName;
end;

procedure TDataImportForm.LoadDataFile;
var
  FilePath, Ext: string;
  FS: TFileStream;
  Sig: array[0..3] of Byte;
  IsOleBinary: Boolean;
begin
  FilePath := Trim(edtFilePath.Text);
  if (FilePath = '') or (not FileExists(FilePath)) then
  begin
    SetLength(FCsvHeaders, 0);
    SetLength(FCsvRows, 0);
    PopulatePreviewGrid;
    RefreshMappingGrid;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    Ext := LowerCase(ExtractFileExt(FilePath));
    if Ext = '.xlsx' then
    begin
      if not ParseXlsxFile(FilePath) then
        MessageDlg('Importar Excel (.xlsx)', 'Não foi possível ler a planilha .xlsx selecionada.', mtError, [mbOK], 0);
    end
    else if Ext = '.xls' then
    begin
      IsOleBinary := False;
      FillChar(Sig, SizeOf(Sig), 0);
      FS := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyNone);
      try
        if FS.Size >= 4 then
        begin
          FS.ReadBuffer(Sig[0], 4);
          IsOleBinary := (Sig[0] = $D0) and (Sig[1] = $CF) and (Sig[2] = $11) and (Sig[3] = $E0);
        end;
      finally
        FS.Free;
      end;

      if IsOleBinary then
      begin
        if not ParseXlsViaOle(FilePath) then
          MessageDlg('Importar Excel (.xls)', 'Para ler arquivos binários .xls, é necessário ter o Microsoft Excel instalado (ou salve como .xlsx / .csv).', mtWarning, [mbOK], 0);
      end
      else
        ParseCsvFile(FilePath);
    end
    else
      ParseCsvFile(FilePath);
  finally
    Screen.Cursor := crDefault;
  end;
end;

function TDataImportForm.ParseXlsxFile(const AFilePath: string): Boolean;
var
  TempDir, SharedPath, SheetPath, CellType, CellRef, CellVal: string;
  Unzipper: TUnZipper;
  FilesToExtract, SharedStrings: TStringList;
  I, ColIdx, RowCap, RowCnt, MaxCols, MaxRowCols: Integer;
  Doc: TXMLDocument;
  Node, SiNode, RowNode, CellNode, SubNode, IsNode: TDOMNode;
  Elem: TDOMElement;
  CurRow: TStringArray;
  AllRows: array of TStringArray;
begin
  Result := False;
  TempDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('multidb_xlsx_%d_%d', [GetTickCount64, PtrUInt(Self)]);
  ForceDirectories(TempDir);
  SharedStrings := TStringList.Create;
  FilesToExtract := TStringList.Create;
  Unzipper := TUnZipper.Create;
  try
    Unzipper.FileName := AFilePath;
    Unzipper.OutputPath := TempDir;
    Unzipper.Examine;
    SharedPath := '';
    SheetPath := '';
    for I := 0 to Unzipper.Entries.Count - 1 do
    begin
      if SameText(Unzipper.Entries[I].ArchiveFileName, 'xl/sharedStrings.xml') then
      begin
        SharedPath := Unzipper.Entries[I].ArchiveFileName;
        FilesToExtract.Add(SharedPath);
      end
      else if SameText(Unzipper.Entries[I].ArchiveFileName, 'xl/worksheets/sheet1.xml') then
      begin
        SheetPath := Unzipper.Entries[I].ArchiveFileName;
        FilesToExtract.Add(SheetPath);
      end;
    end;

    if SheetPath = '' then
    begin
      for I := 0 to Unzipper.Entries.Count - 1 do
      begin
        if Pos('xl/worksheets/sheet', LowerCase(Unzipper.Entries[I].ArchiveFileName)) = 1 then
        begin
          SheetPath := Unzipper.Entries[I].ArchiveFileName;
          FilesToExtract.Add(SheetPath);
          Break;
        end;
      end;
    end;

    if SheetPath = '' then
      Exit(False);

    Unzipper.UnZipFiles(FilesToExtract);

    SharedPath := IncludeTrailingPathDelimiter(TempDir) + StringReplace(SharedPath, '/', PathDelim, [rfReplaceAll]);
    if (SharedPath <> '') and FileExists(SharedPath) then
    begin
      ReadXMLFile(Doc, SharedPath);
      try
        if (Doc <> nil) and (Doc.DocumentElement <> nil) then
        begin
          SiNode := Doc.DocumentElement.FirstChild;
          while SiNode <> nil do
          begin
            if SiNode.NodeName = 'si' then
              SharedStrings.Add(CollectXmlTextRecursive(SiNode));
            SiNode := SiNode.NextSibling;
          end;
        end;
      finally
        Doc.Free;
      end;
    end;

    SheetPath := IncludeTrailingPathDelimiter(TempDir) + StringReplace(SheetPath, '/', PathDelim, [rfReplaceAll]);
    if not FileExists(SheetPath) then
      Exit(False);

    RowCnt := 0;
    RowCap := 128;
    SetLength(AllRows, RowCap);
    MaxCols := 0;

    ReadXMLFile(Doc, SheetPath);
    try
      if (Doc = nil) or (Doc.DocumentElement = nil) then
        Exit(False);
      Node := Doc.DocumentElement.FirstChild;
      while Node <> nil do
      begin
        if Node.NodeName = 'sheetData' then
        begin
          RowNode := Node.FirstChild;
          while RowNode <> nil do
          begin
            if RowNode.NodeName = 'row' then
            begin
              SetLength(CurRow, 0);
              MaxRowCols := 0;
              CellNode := RowNode.FirstChild;
              while CellNode <> nil do
              begin
                if (CellNode.NodeName = 'c') and (CellNode is TDOMElement) then
                begin
                  Elem := TDOMElement(CellNode);
                  CellRef := string(Elem.GetAttribute('r'));
                  CellType := string(Elem.GetAttribute('t'));
                  ColIdx := DecodeExcelColumnIndex(CellRef);
                  if ColIdx < 0 then
                    ColIdx := MaxRowCols;
                  if ColIdx >= Length(CurRow) then
                    SetLength(CurRow, ColIdx + 1);
                  if ColIdx + 1 > MaxRowCols then
                    MaxRowCols := ColIdx + 1;

                  CellVal := '';
                  SubNode := CellNode.FirstChild;
                  while SubNode <> nil do
                  begin
                    if SubNode.NodeName = 'v' then
                    begin
                      CellVal := CollectXmlTextRecursive(SubNode);
                      Break;
                    end
                    else if SubNode.NodeName = 'is' then
                    begin
                      IsNode := SubNode;
                      CellVal := CollectXmlTextRecursive(IsNode);
                      Break;
                    end;
                    SubNode := SubNode.NextSibling;
                  end;

                  if (CellType = 's') and TryStrToInt(Trim(CellVal), I) and
                     (I >= 0) and (I < SharedStrings.Count) then
                    CellVal := SharedStrings[I];

                  CurRow[ColIdx] := CellVal;
                end;
                CellNode := CellNode.NextSibling;
              end;

              if MaxRowCols > 0 then
              begin
                SetLength(CurRow, MaxRowCols);
                if MaxRowCols > MaxCols then
                  MaxCols := MaxRowCols;
                if RowCnt >= RowCap then
                begin
                  RowCap := RowCap * 2;
                  SetLength(AllRows, RowCap);
                end;
                AllRows[RowCnt] := CurRow;
                Inc(RowCnt);
              end;
            end;
            RowNode := RowNode.NextSibling;
          end;
        end;
        Node := Node.NextSibling;
      end;
    finally
      Doc.Free;
    end;

    SetLength(AllRows, RowCnt);
    FinalizeLoadedRows(AllRows, MaxCols);
    Result := True;
  finally
    Unzipper.Free;
    FilesToExtract.Free;
    SharedStrings.Free;
    DeleteDirectoryRecursive(TempDir);
  end;
end;

function TDataImportForm.ParseXlsViaOle(const AFilePath: string): Boolean;
{$IFDEF WINDOWS}
var
  Excel, WB, Sheet, UsedRng, Arr: OleVariant;
  R, C, LowR, HighR, LowC, HighC, RowCnt, ColCnt: Integer;
  AllRows: array of TStringArray;
begin
  Result := False;
  try
    Excel := CreateOleObject('Excel.Application');
  except
    Exit(False);
  end;
  try
    Excel.Visible := False;
    Excel.DisplayAlerts := False;
    WB := Excel.Workbooks.Open(AFilePath, 0, True);
    try
      Sheet := WB.ActiveSheet;
      UsedRng := Sheet.UsedRange;
      Arr := UsedRng.Value;
      if VarIsArray(Arr) then
      begin
        LowR := VarArrayLowBound(Arr, 1);
        HighR := VarArrayHighBound(Arr, 1);
        LowC := VarArrayLowBound(Arr, 2);
        HighC := VarArrayHighBound(Arr, 2);
        RowCnt := HighR - LowR + 1;
        ColCnt := HighC - LowC + 1;
        SetLength(AllRows, RowCnt);
        for R := LowR to HighR do
        begin
          SetLength(AllRows[R - LowR], ColCnt);
          for C := LowC to HighC do
            AllRows[R - LowR][C - LowC] := VarToStr(Arr[R, C]);
        end;
      end
      else
      begin
        RowCnt := 1;
        ColCnt := 1;
        SetLength(AllRows, 1);
        SetLength(AllRows[0], 1);
        AllRows[0][0] := VarToStr(Arr);
      end;
      FinalizeLoadedRows(AllRows, ColCnt);
      Result := True;
    finally
      WB.Close(False);
    end;
  finally
    Excel.Quit;
    Excel := Unassigned;
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

procedure TDataImportForm.ParseCsvFile(const AFilePath: string);
var
  Content, FieldBuf: string;
  FS: TFileStream;
  I, Len, MaxCols, RowCap, RowCnt, ColCnt, ColCap: Integer;
  Delim, QuoteCh: Char;
  InQuotes: Boolean;
  CurRow: TStringArray;
  AllRows: array of TStringArray;

  procedure PushField;
  begin
    if ColCnt >= ColCap then
    begin
      ColCap := ColCap * 2;
      SetLength(CurRow, ColCap);
    end;
    CurRow[ColCnt] := FieldBuf;
    Inc(ColCnt);
    FieldBuf := '';
  end;

  procedure PushRow;
  begin
    if (ColCnt = 1) and (CurRow[0] = '') then
    begin
      ColCnt := 0;
      Exit;
    end;
    SetLength(CurRow, ColCnt);
    if ColCnt > MaxCols then
      MaxCols := ColCnt;
    if RowCnt >= RowCap then
    begin
      RowCap := RowCap * 2;
      SetLength(AllRows, RowCap);
    end;
    AllRows[RowCnt] := CurRow;
    Inc(RowCnt);
    ColCap := Max(8, MaxCols);
    SetLength(CurRow, ColCap);
    ColCnt := 0;
  end;

begin
  Content := '';
  FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Content, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Content[1], FS.Size);
  finally
    FS.Free;
  end;

  if Copy(Content, 1, 3) = #$EF#$BB#$BF then
    Delete(Content, 1, 3);

  Delim := SelectedDelimiter;
  QuoteCh := SelectedQuoteChar;

  RowCnt := 0;
  RowCap := 128;
  SetLength(AllRows, RowCap);
  MaxCols := 0;
  ColCnt := 0;
  ColCap := 16;
  SetLength(CurRow, ColCap);
  FieldBuf := '';
  InQuotes := False;

  Len := Length(Content);
  I := 1;
  while I <= Len do
  begin
    if InQuotes then
    begin
      if (QuoteCh <> #0) and (Content[I] = QuoteCh) then
      begin
        if (I < Len) and (Content[I + 1] = QuoteCh) then
        begin
          FieldBuf := FieldBuf + QuoteCh;
          Inc(I, 2);
          Continue;
        end
        else
        begin
          InQuotes := False;
          Inc(I);
          Continue;
        end;
      end;
      FieldBuf := FieldBuf + Content[I];
      Inc(I);
      Continue;
    end;

    if (QuoteCh <> #0) and (Content[I] = QuoteCh) and (FieldBuf = '') then
    begin
      InQuotes := True;
      Inc(I);
      Continue;
    end;

    if Content[I] = Delim then
    begin
      PushField;
      Inc(I);
      Continue;
    end;

    if Content[I] = #13 then
    begin
      PushField;
      PushRow;
      if (I < Len) and (Content[I + 1] = #10) then
        Inc(I, 2)
      else
        Inc(I);
      Continue;
    end;

    if Content[I] = #10 then
    begin
      PushField;
      PushRow;
      Inc(I);
      Continue;
    end;

    FieldBuf := FieldBuf + Content[I];
    Inc(I);
  end;

  if (FieldBuf <> '') or (ColCnt > 0) then
  begin
    PushField;
    PushRow;
  end;

  SetLength(AllRows, RowCnt);
  FinalizeLoadedRows(AllRows, MaxCols);
end;

procedure TDataImportForm.PopulatePreviewGrid;
var
  C, R, PreviewCount: Integer;
begin
  if Length(FCsvHeaders) = 0 then
  begin
    grdPreview.ColCount := 1;
    grdPreview.RowCount := 1;
    grdPreview.Cells[0, 0] := '(Nenhum arquivo carregado)';
    Exit;
  end;

  grdPreview.ColCount := Length(FCsvHeaders);
  PreviewCount := Min(100, Length(FCsvRows));
  grdPreview.RowCount := PreviewCount + 1;
  grdPreview.FixedRows := 1;
  for C := 0 to High(FCsvHeaders) do
  begin
    grdPreview.Cells[C, 0] := Format('#%d: %s', [C + 1, FCsvHeaders[C]]);
    grdPreview.ColWidths[C] := 140;
  end;
  for R := 0 to PreviewCount - 1 do
  begin
    for C := 0 to High(FCsvHeaders) do
    begin
      if C < Length(FCsvRows[R]) then
        grdPreview.Cells[C, R + 1] := FCsvRows[R][C]
      else
        grdPreview.Cells[C, R + 1] := '';
    end;
  end;
end;

procedure TDataImportForm.AutoMapByName;
var
  I, J: Integer;
  TargetNorm, HeaderNorm: string;
  AnyMapped: Boolean;
begin
  if chkCreateNewTable.Checked then
  begin
    BuildMappingsForNewTable;
    Exit;
  end;

  AnyMapped := False;
  for I := 0 to High(FMappings) do
  begin
    FMappings[I].SourceColIndex := -1;
    if FMappings[I].IsComputed then
    begin
      FMappings[I].Include := False;
      Continue;
    end;
    TargetNorm := LowerCase(Trim(FMappings[I].TargetColName));
    for J := 0 to High(FCsvHeaders) do
    begin
      HeaderNorm := LowerCase(Trim(FCsvHeaders[J]));
      if TargetNorm = HeaderNorm then
      begin
        FMappings[I].SourceColIndex := J;
        FMappings[I].Include := True;
        AnyMapped := True;
        Break;
      end;
    end;
    if FMappings[I].SourceColIndex < 0 then
      FMappings[I].Include := False;
  end;

  if (not AnyMapped) and (Length(FCsvHeaders) > 0) and (Length(FMappings) > 0) then
    AutoMapByOrder
  else
    RefreshMappingGrid;
end;

procedure TDataImportForm.AutoMapByOrder;
var
  I, SrcIdx: Integer;
begin
  if chkCreateNewTable.Checked then
  begin
    BuildMappingsForNewTable;
    Exit;
  end;

  SrcIdx := 0;
  for I := 0 to High(FMappings) do
  begin
    if FMappings[I].IsComputed then
    begin
      FMappings[I].Include := False;
      FMappings[I].SourceColIndex := -1;
      Continue;
    end;
    if SrcIdx <= High(FCsvHeaders) then
    begin
      FMappings[I].SourceColIndex := SrcIdx;
      FMappings[I].Include := True;
      Inc(SrcIdx);
    end
    else
    begin
      FMappings[I].SourceColIndex := -1;
      FMappings[I].Include := False;
    end;
  end;
  RefreshMappingGrid;
end;

procedure TDataImportForm.RefreshMappingGrid;
var
  I, SrcIdx: Integer;
begin
  grdMapping.RowCount := Length(FMappings) + 1;
  for I := 0 to High(FMappings) do
  begin
    if FMappings[I].Include then
      grdMapping.Cells[0, I + 1] := '[X]'
    else
      grdMapping.Cells[0, I + 1] := '[ ]';

    grdMapping.Cells[1, I + 1] := FMappings[I].TargetColName;
    grdMapping.Cells[2, I + 1] := FMappings[I].TargetDataType;

    if FMappings[I].IsKey then
      grdMapping.Cells[3, I + 1] := '[X]'
    else
      grdMapping.Cells[3, I + 1] := '[ ]';

    SrcIdx := FMappings[I].SourceColIndex;
    if (SrcIdx >= 0) and (SrcIdx <= High(FCsvHeaders)) then
    begin
      grdMapping.Cells[4, I + 1] := Format('#%d: %s', [SrcIdx + 1, FCsvHeaders[SrcIdx]]);
      if (Length(FCsvRows) > 0) and (SrcIdx < Length(FCsvRows[0])) then
        grdMapping.Cells[5, I + 1] := FCsvRows[0][SrcIdx]
      else
        grdMapping.Cells[5, I + 1] := '';
    end
    else if SrcIdx = -2 then
    begin
      grdMapping.Cells[4, I + 1] := '= ' + FMappings[I].FixedValue;
      grdMapping.Cells[5, I + 1] := FMappings[I].FixedValue;
    end
    else
    begin
      grdMapping.Cells[4, I + 1] := '(Ignorar)';
      grdMapping.Cells[5, I + 1] := '';
    end;
  end;
  UpdateStatusSummary;
end;

procedure TDataImportForm.UpdateStatusSummary;
var
  I, MappedCount: Integer;
begin
  MappedCount := 0;
  for I := 0 to High(FMappings) do
    if FMappings[I].Include and (FMappings[I].SourceColIndex <> -1) then
      Inc(MappedCount);
  lblStatus.Caption := Format('Linhas no arquivo: %d | Colunas mapeadas: %d de %d',
    [Length(FCsvRows), MappedCount, Length(FMappings)]);
end;

procedure TDataImportForm.ChooseSourceForMappingRow(const AMapIdx: Integer);
var
  Dlg: TForm;
  PnlTopEdit, PnlBtn: TPanel;
  LblColName, LblColType, LblInfo: TLabel;
  EdtColName, EdtFixed: TEdit;
  CbColType: TComboBox;
  ChkIsKey: TCheckBox;
  Lb: TListBox;
  BtnOk, BtnCancel: TButton;
  I, SelIdx: Integer;
  IsNewTbl: Boolean;
begin
  if (AMapIdx < 0) or (AMapIdx > High(FMappings)) then
    Exit;

  IsNewTbl := chkCreateNewTable.Checked;
  Dlg := TForm.CreateNew(nil);
  try
    Dlg.Caption := 'Mapear Coluna: ' + FMappings[AMapIdx].TargetColName;
    Dlg.Position := poScreenCenter;
    Dlg.BorderStyle := bsDialog;
    Dlg.Width := 460;
    Dlg.Height := 450;

    PnlTopEdit := TPanel.Create(Dlg);
    PnlTopEdit.Parent := Dlg;
    PnlTopEdit.Align := alTop;
    PnlTopEdit.Height := 118;
    PnlTopEdit.BevelOuter := bvNone;

    LblColName := TLabel.Create(Dlg);
    LblColName.Parent := PnlTopEdit;
    LblColName.Left := 8;
    LblColName.Top := 10;
    LblColName.Caption := 'Nome da Coluna Destino:';

    EdtColName := TEdit.Create(Dlg);
    EdtColName.Parent := PnlTopEdit;
    EdtColName.Left := 8;
    EdtColName.Top := 28;
    EdtColName.Width := 210;
    EdtColName.Text := FMappings[AMapIdx].TargetColName;
    EdtColName.Enabled := IsNewTbl;

    LblColType := TLabel.Create(Dlg);
    LblColType.Parent := PnlTopEdit;
    LblColType.Left := 228;
    LblColType.Top := 10;
    LblColType.Caption := 'Tipo de Dados SQL:';

    CbColType := TComboBox.Create(Dlg);
    CbColType.Parent := PnlTopEdit;
    CbColType.Left := 228;
    CbColType.Top := 28;
    CbColType.Width := 220;
    CbColType.Items.Add('INTEGER');
    CbColType.Items.Add('BIGINT');
    CbColType.Items.Add('NUMERIC(15,2)');
    CbColType.Items.Add('NUMERIC(18,4)');
    CbColType.Items.Add('VARCHAR(60)');
    CbColType.Items.Add('VARCHAR(120)');
    CbColType.Items.Add('VARCHAR(255)');
    CbColType.Items.Add('VARCHAR(500)');
    CbColType.Items.Add('VARCHAR(1000)');
    CbColType.Items.Add('DATE');
    CbColType.Items.Add('TIMESTAMP');
    CbColType.Items.Add('BOOLEAN');
    CbColType.Items.Add('BLOB SUB_TYPE TEXT');
    CbColType.Items.Add('TEXT');
    CbColType.Text := FMappings[AMapIdx].TargetDataType;
    CbColType.Enabled := IsNewTbl;

    ChkIsKey := TCheckBox.Create(Dlg);
    ChkIsKey.Parent := PnlTopEdit;
    ChkIsKey.Left := 8;
    ChkIsKey.Top := 60;
    ChkIsKey.Caption := 'Coluna é Chave Primária (PK / Matching)';
    ChkIsKey.Checked := FMappings[AMapIdx].IsKey;

    LblInfo := TLabel.Create(Dlg);
    LblInfo.Parent := PnlTopEdit;
    LblInfo.Left := 8;
    LblInfo.Top := 92;
    LblInfo.Caption := 'Origem no arquivo (Excel/CSV) ou Valor Fixo / NULL:';

    PnlBtn := TPanel.Create(Dlg);
    PnlBtn.Parent := Dlg;
    PnlBtn.Align := alBottom;
    PnlBtn.Height := 76;
    PnlBtn.BevelOuter := bvNone;

    EdtFixed := TEdit.Create(Dlg);
    EdtFixed.Parent := PnlBtn;
    EdtFixed.Left := 8;
    EdtFixed.Top := 6;
    EdtFixed.Width := PnlBtn.Width - 16;
    EdtFixed.Anchors := [akTop, akLeft, akRight];
    EdtFixed.TextHint := 'Valor fixo (se selecionar "Usar Valor Fixo" acima), ex.: NULL, S, 0';
    EdtFixed.Text := FMappings[AMapIdx].FixedValue;

    BtnCancel := TButton.Create(Dlg);
    BtnCancel.Parent := PnlBtn;
    BtnCancel.Caption := 'Cancelar';
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Cancel := True;
    BtnCancel.Width := 88;
    BtnCancel.Height := 26;
    BtnCancel.Left := PnlBtn.Width - 96;
    BtnCancel.Top := 40;
    BtnCancel.Anchors := [akTop, akRight];

    BtnOk := TButton.Create(Dlg);
    BtnOk.Parent := PnlBtn;
    BtnOk.Caption := 'Aplicar';
    BtnOk.ModalResult := mrOk;
    BtnOk.Default := True;
    BtnOk.Width := 88;
    BtnOk.Height := 26;
    BtnOk.Left := BtnCancel.Left - 96;
    BtnOk.Top := 40;
    BtnOk.Anchors := [akTop, akRight];

    Lb := TListBox.Create(Dlg);
    Lb.Parent := Dlg;
    Lb.Align := alClient;
    Lb.BorderSpacing.Left := 8;
    Lb.BorderSpacing.Right := 8;
    Lb.Items.AddObject('(Ignorar esta coluna)', TObject(PtrInt(-1)));
    Lb.Items.AddObject('(Usar Valor Fixo / NULL informado abaixo)', TObject(PtrInt(-2)));
    for I := 0 to High(FCsvHeaders) do
      Lb.Items.AddObject(Format('#%d: %s', [I + 1, FCsvHeaders[I]]), TObject(PtrInt(I)));

    SelIdx := 0;
    if FMappings[AMapIdx].SourceColIndex = -2 then
      SelIdx := 1
    else if (FMappings[AMapIdx].SourceColIndex >= 0) and (FMappings[AMapIdx].SourceColIndex <= High(FCsvHeaders)) then
      SelIdx := FMappings[AMapIdx].SourceColIndex + 2;
    Lb.ItemIndex := SelIdx;

    if (Dlg.ShowModal = mrOk) and (Lb.ItemIndex >= 0) then
    begin
      if IsNewTbl then
      begin
        if Trim(EdtColName.Text) <> '' then
          FMappings[AMapIdx].TargetColName := Trim(EdtColName.Text);
        if Trim(CbColType.Text) <> '' then
          FMappings[AMapIdx].TargetDataType := Trim(CbColType.Text);
      end;
      FMappings[AMapIdx].IsKey := ChkIsKey.Checked;
      FMappings[AMapIdx].SourceColIndex := Integer(PtrInt(Lb.Items.Objects[Lb.ItemIndex]));
      if FMappings[AMapIdx].SourceColIndex = -2 then
      begin
        FMappings[AMapIdx].FixedValue := Trim(EdtFixed.Text);
        if FMappings[AMapIdx].FixedValue = '' then
          FMappings[AMapIdx].FixedValue := 'NULL';
        FMappings[AMapIdx].Include := True;
      end
      else
        FMappings[AMapIdx].Include := FMappings[AMapIdx].SourceColIndex >= 0;
      RefreshMappingGrid;
    end;
  finally
    Dlg.Free;
  end;
end;

function TDataImportForm.FormatSqlLiteral(const ATargetType, ARawValue: string): string;
var
  TrimVal, UpperType, NormNum: string;
  InvFmt: TFormatSettings;
  DummyNum: Double;
  IsNumericType, IsDateOrTimeType, IsBoolType: Boolean;
begin
  TrimVal := Trim(ARawValue);
  if SameText(TrimVal, 'NULL') or SameText(TrimVal, '(NULL)') then
    Exit('NULL');

  UpperType := UpperCase(ATargetType);
  IsNumericType := (Pos('INT', UpperType) > 0) or (Pos('NUM', UpperType) > 0) or
                   (Pos('DEC', UpperType) > 0) or (Pos('FLOAT', UpperType) > 0) or
                   (Pos('DOUBLE', UpperType) > 0) or (Pos('REAL', UpperType) > 0);
  IsDateOrTimeType := (Pos('DATE', UpperType) > 0) or (Pos('TIME', UpperType) > 0);
  IsBoolType := (Pos('BOOL', UpperType) > 0);

  if TrimVal = '' then
  begin
    if IsNumericType or IsDateOrTimeType or IsBoolType then
      Exit('NULL')
    else
      Exit('''''');
  end;

  if IsBoolType then
  begin
    if SameText(TrimVal, '1') or SameText(TrimVal, 'true') or SameText(TrimVal, 't') or SameText(TrimVal, 'sim') or SameText(TrimVal, 's') then
      Exit('TRUE')
    else
      Exit('FALSE');
  end;

  if IsNumericType then
  begin
    InvFmt := DefaultFormatSettings;
    InvFmt.DecimalSeparator := '.';
    if (Pos(',', TrimVal) > 0) and (Pos('.', TrimVal) = 0) then
      NormNum := StringReplace(TrimVal, ',', '.', [rfReplaceAll])
    else if (Pos(',', TrimVal) > 0) and (Pos('.', TrimVal) > 0) then
      NormNum := StringReplace(StringReplace(TrimVal, '.', '', [rfReplaceAll]), ',', '.', [rfReplaceAll])
    else
      NormNum := TrimVal;
    if TryStrToFloat(NormNum, DummyNum, InvFmt) then
      Exit(NormNum);
  end;

  Result := '''' + StringReplace(ARawValue, '''', '''''', [rfReplaceAll]) + '''';
end;

function TDataImportForm.BuildCreateTableDDL(
  const ADbType: TDatabaseType;
  const ATableName: string;
  out AError: string
): string;
var
  I: Integer;
  ColsDef, KeysStr, ColDef: string;
begin
  Result := '';
  AError := '';
  if Trim(ATableName) = '' then
  begin
    AError := 'Informe o nome da nova tabela.';
    Exit;
  end;

  ColsDef := '';
  KeysStr := '';
  for I := 0 to High(FMappings) do
  begin
    if (not FMappings[I].Include) or (FMappings[I].SourceColIndex = -1) then
      Continue;
    if Trim(FMappings[I].TargetColName) = '' then
    begin
      AError := Format('A coluna #%d está sem nome destino.', [I + 1]);
      Exit;
    end;
    ColDef := '  ' + QuoteDbIdent(ADbType, FMappings[I].TargetColName) + ' ' + Trim(FMappings[I].TargetDataType);
    if FMappings[I].IsKey then
    begin
      ColDef := ColDef + ' NOT NULL';
      if KeysStr <> '' then
        KeysStr := KeysStr + ', ';
      KeysStr := KeysStr + QuoteDbIdent(ADbType, FMappings[I].TargetColName);
    end;
    if ColsDef <> '' then
      ColsDef := ColsDef + ',' + LineEnding;
    ColsDef := ColsDef + ColDef;
  end;

  if ColsDef = '' then
  begin
    AError := 'Nenhuma coluna marcada/mapeada para criar a tabela.';
    Exit;
  end;

  if KeysStr <> '' then
    ColsDef := ColsDef + ',' + LineEnding + '  PRIMARY KEY (' + KeysStr + ')';

  Result := Format('CREATE TABLE %s (%s%s%s)', [
    QuoteDbIdent(ADbType, Trim(ATableName)),
    LineEnding,
    ColsDef,
    LineEnding
  ]);
end;

function TDataImportForm.BuildRowImportSQL(
  const ADbType: TDatabaseType;
  const ATableName: string;
  const ARowIdx: Integer;
  out AError: string
): string;
var
  I, SrcIdx: Integer;
  QuotedTable, ColIdent, ValSql, ColsStr, ValsStr, KeysStr, AssignStr, WhereStr, RawStr: string;
  Mode: Integer;
begin
  Result := '';
  AError := '';
  Mode := cbImportMode.ItemIndex;
  QuotedTable := QuoteDbIdent(ADbType, ATableName);

  ColsStr := '';
  ValsStr := '';
  KeysStr := '';
  AssignStr := '';
  WhereStr := '';

  for I := 0 to High(FMappings) do
  begin
    if (not FMappings[I].Include) or (FMappings[I].SourceColIndex = -1) then
      Continue;

    SrcIdx := FMappings[I].SourceColIndex;
    if SrcIdx = -2 then
    begin
      if SameText(Trim(FMappings[I].FixedValue), 'CURRENT_TIMESTAMP') or
         SameText(Trim(FMappings[I].FixedValue), 'CURRENT_DATE') or
         SameText(Trim(FMappings[I].FixedValue), 'NOW()') then
        ValSql := Trim(FMappings[I].FixedValue)
      else
        ValSql := FormatSqlLiteral(FMappings[I].TargetDataType, FMappings[I].FixedValue);
    end
    else
    begin
      if (ARowIdx >= 0) and (ARowIdx < Length(FCsvRows)) and (SrcIdx < Length(FCsvRows[ARowIdx])) then
        RawStr := FCsvRows[ARowIdx][SrcIdx]
      else
        RawStr := '';
      ValSql := FormatSqlLiteral(FMappings[I].TargetDataType, RawStr);
    end;

    ColIdent := QuoteDbIdent(ADbType, FMappings[I].TargetColName);
    if ColsStr <> '' then
    begin
      ColsStr := ColsStr + ', ';
      ValsStr := ValsStr + ', ';
    end;
    ColsStr := ColsStr + ColIdent;
    ValsStr := ValsStr + ValSql;

    if FMappings[I].IsKey then
    begin
      if KeysStr <> '' then
      begin
        KeysStr := KeysStr + ', ';
        WhereStr := WhereStr + ' AND ';
      end;
      KeysStr := KeysStr + ColIdent;
      if ValSql = 'NULL' then
        WhereStr := WhereStr + ColIdent + ' IS NULL'
      else
        WhereStr := WhereStr + ColIdent + ' = ' + ValSql;
    end
    else
    begin
      if AssignStr <> '' then
        AssignStr := AssignStr + ', ';
      if ADbType = dtPostgreSQL then
        AssignStr := AssignStr + ColIdent + ' = EXCLUDED.' + ColIdent
      else if (Mode = 1) and (ADbType = dtMariaDB) then
        AssignStr := AssignStr + ColIdent + ' = VALUES(' + ColIdent + ')'
      else
        AssignStr := AssignStr + ColIdent + ' = ' + ValSql;
    end;
  end;

  if ColsStr = '' then
  begin
    AError := 'Nenhuma coluna marcada/mapeada para importação.';
    Exit;
  end;

  if Mode = 0 then
    Result := Format('INSERT INTO %s (%s) VALUES (%s)', [QuotedTable, ColsStr, ValsStr])
  else if Mode = 1 then
  begin
    if KeysStr = '' then
    begin
      AError := 'Marque ao menos uma coluna como Chave (PK) para usar UPDATE OR INSERT / UPSERT.';
      Exit;
    end;
    if ADbType = dtFirebird then
      Result := Format('UPDATE OR INSERT INTO %s (%s) VALUES (%s) MATCHING (%s)', [QuotedTable, ColsStr, ValsStr, KeysStr])
    else if ADbType = dtPostgreSQL then
    begin
      if AssignStr = '' then
        Result := Format('INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO NOTHING', [QuotedTable, ColsStr, ValsStr, KeysStr])
      else
        Result := Format('INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO UPDATE SET %s', [QuotedTable, ColsStr, ValsStr, KeysStr, AssignStr]);
    end
    else
    begin
      if AssignStr = '' then
        Result := Format('INSERT IGNORE INTO %s (%s) VALUES (%s)', [QuotedTable, ColsStr, ValsStr])
      else
        Result := Format('INSERT INTO %s (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s', [QuotedTable, ColsStr, ValsStr, AssignStr]);
    end;
  end
  else
  begin
    if WhereStr = '' then
    begin
      AError := 'Marque ao menos uma coluna como Chave (PK) para usar UPDATE.';
      Exit;
    end;
    if AssignStr = '' then
    begin
      AError := 'Nenhuma coluna não-chave mapeada para atualizar no UPDATE.';
      Exit;
    end;
    if ADbType = dtPostgreSQL then
    begin
      AssignStr := '';
      for I := 0 to High(FMappings) do
      begin
        if (not FMappings[I].Include) or (FMappings[I].SourceColIndex = -1) or FMappings[I].IsKey then
          Continue;
        SrcIdx := FMappings[I].SourceColIndex;
        if SrcIdx = -2 then
          ValSql := FormatSqlLiteral(FMappings[I].TargetDataType, FMappings[I].FixedValue)
        else if (ARowIdx >= 0) and (ARowIdx < Length(FCsvRows)) and (SrcIdx < Length(FCsvRows[ARowIdx])) then
          ValSql := FormatSqlLiteral(FMappings[I].TargetDataType, FCsvRows[ARowIdx][SrcIdx])
        else
          ValSql := FormatSqlLiteral(FMappings[I].TargetDataType, '');
        if AssignStr <> '' then
          AssignStr := AssignStr + ', ';
        AssignStr := AssignStr + QuoteDbIdent(ADbType, FMappings[I].TargetColName) + ' = ' + ValSql;
      end;
    end;
    Result := Format('UPDATE %s SET %s WHERE %s', [QuotedTable, AssignStr, WhereStr]);
  end;
end;

procedure TDataImportForm.btnBrowseFileClick(Sender: TObject);
begin
  if dlgOpenFile.Execute then
  begin
    edtFilePath.Text := dlgOpenFile.FileName;
    if Trim(edtNewTableName.Text) = '' then
      edtNewTableName.Text := SanitizeSqlIdentifier(ChangeFileExt(ExtractFileName(dlgOpenFile.FileName), ''), 1);
    LoadDataFile;
  end;
end;

procedure TDataImportForm.btnReloadFileClick(Sender: TObject);
begin
  LoadDataFile;
end;

procedure TDataImportForm.cbDelimiterChange(Sender: TObject);
begin
  if Trim(edtFilePath.Text) <> '' then
    LoadDataFile;
end;

procedure TDataImportForm.cbConnectionChange(Sender: TObject);
begin
  LoadTablesForSelectedConnection;
end;

procedure TDataImportForm.cbTableChange(Sender: TObject);
begin
  if (not FIsLoadingTable) and (not chkCreateNewTable.Checked) then
    LoadTargetTableColumns;
end;

procedure TDataImportForm.chkCreateNewTableClick(Sender: TObject);
begin
  UpdateTableModeUI;
  if chkCreateNewTable.Checked then
  begin
    if (Trim(edtNewTableName.Text) = '') and (Trim(edtFilePath.Text) <> '') then
      edtNewTableName.Text := SanitizeSqlIdentifier(ChangeFileExt(ExtractFileName(edtFilePath.Text), ''), 1);
    BuildMappingsForNewTable;
  end
  else
    LoadTargetTableColumns;
end;

procedure TDataImportForm.btnAutoMapNameClick(Sender: TObject);
begin
  AutoMapByName;
end;

procedure TDataImportForm.btnAutoMapOrderClick(Sender: TObject);
begin
  AutoMapByOrder;
end;

procedure TDataImportForm.btnDropTableClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  TblName, Msg: string;
  UseCase: TManageTableStructureUseCase;
begin
  Profile := SelectedProfile;
  TblName := Trim(cbTable.Text);
  if chkCreateNewTable.Checked or (Profile = nil) or (TblName = '') then
    Exit;

  if MessageDlg(
       'Confirmar Exclusão da Tabela (1/2)',
       Format('Deseja excluir permanentemente a tabela "%s" e TODOS os seus dados do banco "%s"?',
         [TblName, Profile.Name]),
       mtWarning, [mbYes, mbNo], 0
     ) <> mrYes then
    Exit;

  if MessageDlg(
       'Confirmação Final — Exclusão Irreversível (2/2)',
       Format('ATENÇÃO: Esta operação NÃO pode ser desfeita (DROP TABLE %s).' + LineEnding + LineEnding +
         'Confirma em definitivo a EXCLUSÃO da tabela "%s"?', [TblName, TblName]),
       mtWarning, [mbYes, mbNo], 0
     ) <> mrYes then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    UseCase := TManageTableStructureUseCase.Create(FFactory);
    try
      if UseCase.DropTable(Profile, TblName, Msg) then
      begin
        FImportedAny := True;
        memLog.Lines.Add(Msg);
        MessageDlg('Tabela Excluída', Msg, mtInformation, [mbOK], 0);
        FInitialTableName := '';
        LoadTablesForSelectedConnection;
      end
      else
        MessageDlg('Erro ao Excluir Tabela', Msg, mtError, [mbOK], 0);
    finally
      UseCase.Free;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TDataImportForm.grdMappingMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ACol, ARow, Idx: Integer;
begin
  if Button <> mbLeft then
    Exit;
  grdMapping.MouseToCell(X, Y, ACol, ARow);
  Idx := ARow - 1;
  if (Idx < 0) or (Idx > High(FMappings)) then
    Exit;

  if ACol = 0 then
  begin
    FMappings[Idx].Include := not FMappings[Idx].Include;
    RefreshMappingGrid;
  end
  else if ACol = 3 then
  begin
    FMappings[Idx].IsKey := not FMappings[Idx].IsKey;
    RefreshMappingGrid;
  end;
end;

procedure TDataImportForm.grdMappingDblClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := grdMapping.Row - 1;
  if (Idx >= 0) and (Idx <= High(FMappings)) then
    ChooseSourceForMappingRow(Idx);
end;

procedure TDataImportForm.grdMappingKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Idx: Integer;
begin
  Idx := grdMapping.Row - 1;
  if (Idx < 0) or (Idx > High(FMappings)) then
    Exit;

  if Key = VK_SPACE then
  begin
    Key := 0;
    FMappings[Idx].Include := not FMappings[Idx].Include;
    RefreshMappingGrid;
  end
  else if Key = VK_RETURN then
  begin
    Key := 0;
    ChooseSourceForMappingRow(Idx);
  end;
end;

procedure TDataImportForm.btnPreviewSqlClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  TblName, CreateDDL, SqlLine, Err: string;
  I, MaxPreview: Integer;
begin
  Profile := SelectedProfile;
  if chkCreateNewTable.Checked then
    TblName := Trim(edtNewTableName.Text)
  else
    TblName := Trim(cbTable.Text);

  if (Profile = nil) or (TblName = '') or (Length(FCsvRows) = 0) then
  begin
    MessageDlg('Importar Dados', 'Carregue um arquivo com dados e selecione a conexão/tabela.', mtInformation, [mbOK], 0);
    Exit;
  end;

  memLog.Lines.BeginUpdate;
  try
    memLog.Lines.Clear;
    if chkCreateNewTable.Checked then
    begin
      CreateDDL := BuildCreateTableDDL(Profile.DatabaseType, TblName, Err);
      if Err <> '' then
      begin
        MessageDlg('Nova Tabela Inválida', Err, mtWarning, [mbOK], 0);
        Exit;
      end;
      memLog.Lines.Add(CreateDDL + ';');
      memLog.Lines.Add('');
    end
    else if chkDeleteBefore.Checked then
      memLog.Lines.Add('DELETE FROM ' + QuoteDbIdent(Profile.DatabaseType, TblName) + ';');

    MaxPreview := Min(500, Length(FCsvRows));
    for I := 0 to MaxPreview - 1 do
    begin
      SqlLine := BuildRowImportSQL(Profile.DatabaseType, TblName, I, Err);
      if Err <> '' then
      begin
        MessageDlg('Mapeamento Inválido', Err, mtWarning, [mbOK], 0);
        Exit;
      end;
      memLog.Lines.Add(SqlLine + ';');
    end;
    if Length(FCsvRows) > MaxPreview then
      memLog.Lines.Add(Format('-- ... (%d linhas adicionais omitidas no preview; todas serão importadas ao clicar em Importar Dados Agora)',
        [Length(FCsvRows) - MaxPreview]));
  finally
    memLog.Lines.EndUpdate;
  end;
  pgMain.ActivePage := tsLog;
end;

procedure TDataImportForm.btnImportClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  TblName, CreateDDL, SQL, Err, TestSql: string;
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  I, BatchSize, BatchCount, OkCount, ErrCount: Integer;
  StopOnError, Aborted: Boolean;
begin
  Profile := SelectedProfile;
  if chkCreateNewTable.Checked then
    TblName := Trim(edtNewTableName.Text)
  else
    TblName := Trim(cbTable.Text);

  if (Profile = nil) or (TblName = '') or (Length(FCsvRows) = 0) then
  begin
    MessageDlg('Importar Dados', 'Selecione um arquivo com registros, uma conexão e a tabela destino.', mtInformation, [mbOK], 0);
    Exit;
  end;

  CreateDDL := '';
  if chkCreateNewTable.Checked then
  begin
    CreateDDL := BuildCreateTableDDL(Profile.DatabaseType, TblName, Err);
    if (CreateDDL = '') or (Err <> '') then
    begin
      MessageDlg('Nova Tabela Inválida', Err, mtWarning, [mbOK], 0);
      Exit;
    end;
    if not ConfirmAndPreviewDDL(Profile, 'Criar Nova Tabela: ' + TblName, CreateDDL, CreateDDL, True) then
      Exit;
  end;

  TestSql := BuildRowImportSQL(Profile.DatabaseType, TblName, 0, Err);
  if (TestSql = '') or (Err <> '') then
  begin
    MessageDlg('Mapeamento Inválido', Err, mtWarning, [mbOK], 0);
    Exit;
  end;

  if (not chkCreateNewTable.Checked) and chkDeleteBefore.Checked then
  begin
    if MessageDlg(
         'Confirmar Limpeza da Tabela',
         Format('A opção "Limpar tabela antes" executará DELETE FROM %s antes de importar %d registro(s). Deseja continuar?',
           [TblName, Length(FCsvRows)]),
         mtWarning, [mbYes, mbNo], 0
       ) <> mrYes then
      Exit;
  end;

  BatchSize := SelectedBatchSize;
  StopOnError := chkStopOnError.Checked;
  OkCount := 0;
  ErrCount := 0;
  BatchCount := 0;
  Aborted := False;

  memLog.Lines.Clear;
  memLog.Lines.Add(Format('[%s] Iniciando importação de %d linha(s) para "%s"...',
    [FormatDateTime('hh:nn:ss', Now), Length(FCsvRows), TblName]));
  pgMain.ActivePage := tsLog;

  ProgressBar1.Min := 0;
  ProgressBar1.Max := Length(FCsvRows);
  ProgressBar1.Position := 0;

  btnImport.Enabled := False;
  btnPreviewSql.Enabled := False;
  Screen.Cursor := crHourGlass;
  try
    Provider := FFactory.GetProvider(Profile.DatabaseType);
    Session := Provider.CreateSession(Profile);
    try
      Session.Connect;
      if chkCreateNewTable.Checked then
      begin
        Res := Session.ExecuteSQL(CreateDDL, False, 0);
        try
          if not Res.Success then
            raise Exception.Create('Falha ao criar tabela "' + TblName + '": ' + Res.MessageText);
        finally
          Res.Free;
        end;
        if Session.InTransaction then
          Session.Commit;
        memLog.Lines.Add(Format('Tabela "%s" criada com sucesso.', [TblName]));
      end
      else if chkDeleteBefore.Checked then
      begin
        Res := Session.ExecuteSQL('DELETE FROM ' + QuoteDbIdent(Profile.DatabaseType, TblName), False, 0);
        try
          if not Res.Success then
            raise Exception.Create('Falha ao limpar tabela: ' + Res.MessageText);
          memLog.Lines.Add(Format('Tabela "%s" limpa (%d registro(s) removidos).', [TblName, Res.RowsAffected]));
        finally
          Res.Free;
        end;
      end;

      for I := 0 to High(FCsvRows) do
      begin
        SQL := BuildRowImportSQL(Profile.DatabaseType, TblName, I, Err);
        if Err <> '' then
        begin
          Inc(ErrCount);
          memLog.Lines.Add(Format('Linha %d: %s', [I + 1, Err]));
          if StopOnError then
          begin
            Aborted := True;
            Break;
          end;
          Continue;
        end;

        Res := Session.ExecuteSQL(SQL, False, 0);
        try
          if Res.Success then
          begin
            Inc(OkCount);
            Inc(BatchCount);
            if (BatchSize > 0) and (BatchCount >= BatchSize) then
            begin
              Session.Commit;
              BatchCount := 0;
            end;
          end
          else
          begin
            Inc(ErrCount);
            memLog.Lines.Add(Format('ERRO Linha %d: %s | SQL: %s', [I + 1, Res.MessageText, SQL]));
            if StopOnError then
            begin
              Aborted := True;
              Break;
            end;
          end;
        finally
          Res.Free;
        end;

        if ((I + 1) mod 25 = 0) or (I = High(FCsvRows)) then
        begin
          ProgressBar1.Position := I + 1;
          lblStatus.Caption := Format('Importando... %d / %d (Sucesso: %d | Erros: %d)',
            [I + 1, Length(FCsvRows), OkCount, ErrCount]);
          Forms.Application.ProcessMessages;
        end;
      end;

      if Aborted and (BatchSize = 0) then
      begin
        if Session.InTransaction then
          Session.Rollback;
        memLog.Lines.Add('Importação abortada. ROLLBACK executado na transação única (nenhum registro foi gravado).');
      end
      else
      begin
        if Session.InTransaction then
          Session.Commit;
        if OkCount > 0 then
          FImportedAny := True;
        memLog.Lines.Add(Format('[%s] Importação finalizada. Importados: %d | Erros: %d.',
          [FormatDateTime('hh:nn:ss', Now), OkCount, ErrCount]));
      end;
    finally
      if Session.IsConnected then
        Session.Disconnect;
    end;
  except
    on E: Exception do
    begin
      memLog.Lines.Add('ERRO CRÍTICO: ' + E.Message);
      MessageDlg('Erro na Importação', E.Message, mtError, [mbOK], 0);
    end;
  end;

  Screen.Cursor := crDefault;
  btnImport.Enabled := True;
  btnPreviewSql.Enabled := True;
  lblStatus.Caption := Format('Concluído: %d importado(s), %d erro(s).', [OkCount, ErrCount]);
end;

end.
