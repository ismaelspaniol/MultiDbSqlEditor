unit Presentation.TableEditorFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Types,
  Math,
  Clipbrd,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  StdCtrls,
  ExtCtrls,
  ComCtrls,
  Grids,
  Menus,
  Spin,
  LCLType,
  SynEdit,
  SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.TableStructureTypes,
  Application.ManageDatabaseObjectsUseCase,
  Application.ManageTableStructureUseCase,
  Presentation.QueryResultGridFrame,
  Presentation.SqlCompletionController;

type
  TOnTableOpenDependency = procedure(
    const AProfile: TConnectionProfile;
    const AKind: TSchemaObjectKind;
    const AObjectName: string
  ) of object;

  TOnTableOpenSqlScript = procedure(
    const AProfile: TConnectionProfile;
    const ATitle, ASqlText: string
  ) of object;

  TOnTableProfileChanged = procedure(const AProfileId: string) of object;

  { Frame estilo IBExpert para visualizar e editar tabela (campos, constraints, índices, triggers, dados, dependências e DDL) }
  TTableEditorFrame = class(TFrame)
    pnlHeader: TPanel;
    lblTableTitle: TLabel;
    btnRefresh: TButton;
    btnViewData: TButton;
    btnOpenInSql: TButton;
    pgTable: TPageControl;
    tsFields: TTabSheet;
    pnlFieldsBar: TFlowPanel;
    btnAddField: TButton;
    btnEditField: TButton;
    btnDropField: TButton;
    btnFieldDeps: TButton;
    grdFields: TStringGrid;
    tsConstraints: TTabSheet;
    pgConstraints: TPageControl;
    tsConstraintPK: TTabSheet;
    grdPK: TStringGrid;
    tsConstraintFK: TTabSheet;
    lblFKHint: TLabel;
    grdFK: TStringGrid;
    tsConstraintUnique: TTabSheet;
    grdUnique: TStringGrid;
    tsConstraintChecks: TTabSheet;
    grdChecks: TStringGrid;
    tsIndexes: TTabSheet;
    pnlIndexesBar: TFlowPanel;
    btnAddIndex: TButton;
    btnToggleIndexActive: TButton;
    btnDropIndex: TButton;
    grdIndexes: TStringGrid;
    tsTriggers: TTabSheet;
    pnlTriggersLeft: TPanel;
    pnlTriggersListBar: TFlowPanel;
    btnNewTrigger: TButton;
    btnToggleTriggerActive: TButton;
    btnDropTrigger: TButton;
    tvTriggers: TTreeView;
    splTriggers: TSplitter;
    pnlTriggerRight: TPanel;
    pnlTriggerToolbar: TFlowPanel;
    btnCompileTrigger: TButton;
    btnReloadTrigger: TButton;
    btnCopyTriggerDDL: TButton;
    btnOpenTriggerFunction: TButton;
    btnOpenTriggerInTab: TButton;
    lblTriggerState: TLabel;
    pnlTriggerMeta: TPanel;
    pnlTriggerMetaRow1: TFlowPanel;
    lblTrigName: TLabel;
    edtTriggerName: TEdit;
    chkTriggerActive: TCheckBox;
    lblTrigPos: TLabel;
    spnTriggerPos: TSpinEdit;
    pnlTriggerMetaRow2: TFlowPanel;
    lblTrigTiming: TLabel;
    cbTriggerTiming: TComboBox;
    chkTrigInsert: TCheckBox;
    chkTrigUpdate: TCheckBox;
    chkTrigDelete: TCheckBox;
    lblTriggerHeaderPreview: TLabel;
    SynEditTrigger: TSynEdit;
    splTriggerLog: TSplitter;
    memTriggerLog: TMemo;
    tsData: TTabSheet;
    pnlDataBar: TFlowPanel;
    btnRefreshData: TButton;
    lblDataLimit: TLabel;
    cbDataLimit: TComboBox;
    lblDataWhere: TLabel;
    edtDataWhere: TEdit;
    btnOpenDataInSql: TButton;
    tsDependencies: TTabSheet;
    pnlDepFilter: TFlowPanel;
    lblDepScope: TLabel;
    cbDepField: TComboBox;
    pnlDepUsedBy: TPanel;
    lblDepUsedBy: TLabel;
    grdDepUsedBy: TStringGrid;
    splDeps: TSplitter;
    pnlDepUses: TPanel;
    lblDepUses: TLabel;
    grdDepUses: TStringGrid;
    tsDDL: TTabSheet;
    pnlDDLBar: TFlowPanel;
    btnCopyTableDDL: TButton;
    btnOpenDDLInSql: TButton;
    chkIncludeTriggersDDL: TCheckBox;
    SynEditDDL: TSynEdit;
    pnlBottom: TPanel;
    lblStatus: TLabel;
    pmFields: TPopupMenu;
    miFieldDeps: TMenuItem;
    miFieldSep1: TMenuItem;
    miFieldEdit: TMenuItem;
    miFieldDrop: TMenuItem;
    pmTriggers: TPopupMenu;
    miTrigNewInCategory: TMenuItem;
    miTrigToggleActive: TMenuItem;
    miTrigOpenTab: TMenuItem;
    miTrigSep1: TMenuItem;
    miTrigDrop: TMenuItem;
    SynSQLSynDDL: TSynSQLSyn;
    SynSQLSynTrigger: TSynSQLSyn;
    procedure btnRefreshClick(Sender: TObject);
    procedure btnViewDataClick(Sender: TObject);
    procedure btnOpenInSqlClick(Sender: TObject);
    procedure pgTableChange(Sender: TObject);
    procedure btnAddFieldClick(Sender: TObject);
    procedure btnEditFieldClick(Sender: TObject);
    procedure btnDropFieldClick(Sender: TObject);
    procedure btnFieldDepsClick(Sender: TObject);
    procedure pmFieldsPopup(Sender: TObject);
    procedure grdFieldsDblClick(Sender: TObject);
    procedure grdFieldsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure grdFKDblClick(Sender: TObject);
    procedure btnAddIndexClick(Sender: TObject);
    procedure btnToggleIndexActiveClick(Sender: TObject);
    procedure btnDropIndexClick(Sender: TObject);
    procedure grdIndexesSelection(Sender: TObject; aCol, aRow: Integer);
    procedure btnNewTriggerClick(Sender: TObject);
    procedure btnToggleTriggerActiveClick(Sender: TObject);
    procedure btnDropTriggerClick(Sender: TObject);
    procedure btnCompileTriggerClick(Sender: TObject);
    procedure btnReloadTriggerClick(Sender: TObject);
    procedure btnCopyTriggerDDLClick(Sender: TObject);
    procedure btnOpenTriggerFunctionClick(Sender: TObject);
    procedure btnOpenTriggerInTabClick(Sender: TObject);
    procedure pnlTriggerToolbarResize(Sender: TObject);
    procedure tvTriggersChanging(Sender: TObject; Node: TTreeNode; var AllowChange: Boolean);
    procedure tvTriggersChange(Sender: TObject; Node: TTreeNode);
    procedure tvTriggersCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure tvTriggersDblClick(Sender: TObject);
    procedure tvTriggersMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pmTriggersPopup(Sender: TObject);
    procedure TriggerMetaChanged(Sender: TObject);
    procedure SynEditTriggerChange(Sender: TObject);
    procedure SynEditTriggerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnRefreshDataClick(Sender: TObject);
    procedure cbDataLimitChange(Sender: TObject);
    procedure edtDataWhereKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnOpenDataInSqlClick(Sender: TObject);
    procedure cbDepFieldChange(Sender: TObject);
    procedure grdDepUsedByDblClick(Sender: TObject);
    procedure grdDepUsesDblClick(Sender: TObject);
    procedure btnCopyTableDDLClick(Sender: TObject);
    procedure btnOpenDDLInSqlClick(Sender: TObject);
    procedure chkIncludeTriggersDDLClick(Sender: TObject);
  private
    FProfile: TConnectionProfile;
    FTableName: string;
    FUseCase: TManageTableStructureUseCase;
    FStructure: TTableStructure;
    FUsedByDeps: TTableDependencyInfoArray;
    FUsesDeps: TTableDependencyInfoArray;
    FDataGrid: TQueryResultGridFrame;
    FLastDataResult: TQueryResult;
    FDataLoaded: Boolean;
    FTriggerCompletion: TSqlCompletionController;
    FCurrentTriggerName: string;
    FTriggerIsNew: Boolean;
    FTriggerDirty: Boolean;
    FLoadingTrigger: Boolean;
    FUpdatingTriggerToolbarSize: Boolean;
    FLastTriggerToolbarWidth: Integer;
    FOnOpenDependency: TOnTableOpenDependency;
    FOnOpenSqlScript: TOnTableOpenSqlScript;
    FOnStructureChanged: TOnTableProfileChanged;
    FOnTriggersChanged: TOnTableProfileChanged;
    procedure ConfigureGrids;
    procedure LoadAndDisplayStructure(const ASelectTriggerName: string = '');
    procedure PopulateFieldsGrid;
    procedure PopulateConstraintsGrids;
    procedure PopulateIndexesGrid;
    procedure PopulateTriggersTree(const APreferredTriggerName: string = '');
    procedure PopulateDependenciesFieldFilter;
    procedure RefreshDependenciesDisplay;
    procedure PopulateDependenciesGrids(const ADeps: TTableDependencyInfoArray);
    procedure RefreshDDLPreview;
    procedure OpenDependencyFromGrid(const AGrid: TStringGrid; const ADeps: TTableDependencyInfoArray);
    function SelectedColumnIndex: Integer;
    function SelectedIndexPos: Integer;
    function SelectedTriggerIndex: Integer;
    function SelectedTreeCategoryCode: Integer;
    procedure CategoryCodeToDefaults(
      const ACatCode: Integer;
      out ATiming: string;
      out AHasInsert, AHasUpdate, AHasDelete: Boolean
    );
    function ClassifyTriggerCategoryCode(const ATrig: TTableTriggerInfo): Integer;
    function BuildSuggestedTriggerName(
      const ATiming: string;
      const AHasInsert, AHasUpdate, AHasDelete: Boolean
    ): string;
    function TriggerExistsInStructure(const AName: string): Boolean;
    function FindTriggerIndexByName(const AName: string): Integer;
    procedure LoadSelectedTriggerIntoEditor;
    procedure ClearTriggerEditorPlaceholder;
    procedure StartNewTrigger(
      const ATiming: string;
      const AHasInsert, AHasUpdate, AHasDelete: Boolean
    );
    procedure UpdateTriggerHeaderPreview;
    procedure UpdateTriggerEditorControlsState;
    procedure UpdateTriggerToolbarLayout;
    procedure LogTriggerMessage(const AMsg: string);
    function ConfirmDiscardTriggerChanges: Boolean;
    procedure UpdateButtonsState;
    function ShowColumnDialog(const AIsEdit: Boolean; const AExisting: TTableColumnInfo): Boolean;
    function ShowCreateIndexDialog: Boolean;
    function GetCompletionProfile: TConnectionProfile;
    function ExecuteCompletionMetadataQuery(const ASQL: string): TQueryResult;
    function SelectedDataLimit: Integer;
    function BuildDataSelectSQL: string;
    procedure LoadTableDataGrid;
    procedure HandleDataGridExportedCsv(Sender: TObject; const AFileName: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Initialize(
      const AProfile: TConnectionProfile;
      const ATableName: string;
      const AUseCase: TManageTableStructureUseCase
    );
    procedure RefreshAll;
    procedure ClearMetadataCache;
    function HasUnsavedTriggerChanges: Boolean;
    function ProfileId: string;
    property TableName: string read FTableName;
    property OnOpenDependency: TOnTableOpenDependency read FOnOpenDependency write FOnOpenDependency;
    property OnOpenSqlScript: TOnTableOpenSqlScript read FOnOpenSqlScript write FOnOpenSqlScript;
    property OnStructureChanged: TOnTableProfileChanged read FOnStructureChanged write FOnStructureChanged;
    property OnTriggersChanged: TOnTableProfileChanged read FOnTriggersChanged write FOnTriggersChanged;
  end;

implementation

{$R *.lfm}

const
  TRIG_NODE_DATA_BASE = 1000;

type
  TColumnDialogHelper = class
  public
    Dlg: TForm;
    Profile: TConnectionProfile;
    TableName: string;
    UseCase: TManageTableStructureUseCase;
    IsEdit: Boolean;
    OldCol: TTableColumnInfo;
    EdtName: TEdit;
    CbType: TComboBox;
    EdtDefault: TEdit;
    ChkNotNull: TCheckBox;
    MemPreview: TMemo;
    BtnExecute: TButton;
    procedure InputChanged(Sender: TObject);
    procedure ExecuteClicked(Sender: TObject);
  end;

  TIndexDialogHelper = class
  public
    Dlg: TForm;
    Profile: TConnectionProfile;
    TableName: string;
    UseCase: TManageTableStructureUseCase;
    AllColsOrder: TStringList;
    EdtIndexName: TEdit;
    LstAvailable: TListBox;
    LstSelected: TListBox;
    BtnAddCol: TButton;
    BtnRemoveCol: TButton;
    BtnMoveUp: TButton;
    BtnMoveDown: TButton;
    ChkUnique: TCheckBox;
    ChkDescending: TCheckBox;
    MemPreview: TMemo;
    BtnCreate: TButton;
    UserEditedName: Boolean;
    procedure UpdateSuggestedIndexName;
    procedure UpdateControlsAndPreview;
    procedure IndexNameKeyPress(Sender: TObject; var Key: Char);
    procedure InputChanged(Sender: TObject);
    procedure AddColClicked(Sender: TObject);
    procedure RemoveColClicked(Sender: TObject);
    procedure MoveUpClicked(Sender: TObject);
    procedure MoveDownClicked(Sender: TObject);
    procedure CreateClicked(Sender: TObject);
  end;

function StartsWithAnyTriggerDDL(const AText: string): Boolean;
var
  Up: string;
begin
  Up := UpperCase(TrimLeft(AText));
  Result :=
    ((Pos('CREATE', Up) = 1) and ((Length(Up) = 6) or (Up[7] <= ' '))) or
    ((Pos('RECREATE', Up) = 1) and ((Length(Up) = 8) or (Up[9] <= ' '))) or
    ((Pos('ALTER', Up) = 1) and ((Length(Up) = 5) or (Up[6] <= ' ')));
end;

procedure TColumnDialogHelper.InputChanged(Sender: TObject);
var
  Stmts: TStringList;
  IsFB25: Boolean;
begin
  Stmts := TStringList.Create;
  try
    if IsEdit then
    begin
      IsFB25 := (Profile.DatabaseType = dtFirebird) and (Profile.FirebirdVersion = fv25);
      BuildEditColumnDDL(
        Profile.DatabaseType,
        TableName,
        OldCol,
        EdtName.Text,
        CbType.Text,
        EdtDefault.Text,
        ChkNotNull.Checked,
        IsFB25,
        Stmts
      );
      if Stmts.Count = 0 then
        MemPreview.Lines.Text := '-- Nenhuma alteração detectada.'
      else
        MemPreview.Lines.Assign(Stmts);
    end
    else
    begin
      if (Trim(EdtName.Text) = '') or (Trim(CbType.Text) = '') then
        MemPreview.Lines.Text := '-- Preencha o nome e o tipo do campo.'
      else
        MemPreview.Lines.Text := BuildAddColumnDDL(
          Profile.DatabaseType,
          TableName,
          EdtName.Text,
          CbType.Text,
          EdtDefault.Text,
          ChkNotNull.Checked
        ) + ';';
    end;
  finally
    Stmts.Free;
  end;
end;

procedure TColumnDialogHelper.ExecuteClicked(Sender: TObject);
var
  Ok: Boolean;
  Msg: string;
begin
  if Trim(EdtName.Text) = '' then
  begin
    MessageDlg('Atenção', 'Informe o nome do campo.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if Trim(CbType.Text) = '' then
  begin
    MessageDlg('Atenção', 'Informe o tipo do campo.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if IsEdit then
    Ok := UseCase.EditColumn(
      Profile,
      TableName,
      OldCol,
      EdtName.Text,
      CbType.Text,
      EdtDefault.Text,
      ChkNotNull.Checked,
      Msg
    )
  else
    Ok := UseCase.AddColumn(
      Profile,
      TableName,
      EdtName.Text,
      CbType.Text,
      EdtDefault.Text,
      ChkNotNull.Checked,
      Msg
    );

  if Ok then
    Dlg.ModalResult := mrOk
  else
    MessageDlg('Erro ao alterar estrutura', Msg, mtError, [mbOK], 0);
end;

procedure TIndexDialogHelper.UpdateSuggestedIndexName;
var
  BaseName: string;
begin
  if UserEditedName then
    Exit;

  BaseName := 'IDX_' + Trim(TableName);
  if LstSelected.Items.Count > 0 then
    BaseName := BaseName + '_' + Trim(LstSelected.Items[0]);

  if Profile.DatabaseType = dtPostgreSQL then
    BaseName := LowerCase(BaseName)
  else
  begin
    BaseName := UpperCase(BaseName);
    if (Profile.FirebirdVersion in [fvAuto, fv25, fv30]) and (Length(BaseName) > 31) then
      BaseName := Copy(BaseName, 1, 31);
  end;
  EdtIndexName.Text := BaseName;
end;

procedure TIndexDialogHelper.UpdateControlsAndPreview;
var
  DDL: string;
begin
  BtnAddCol.Enabled := LstAvailable.ItemIndex >= 0;
  BtnRemoveCol.Enabled := LstSelected.ItemIndex >= 0;
  BtnMoveUp.Enabled := LstSelected.ItemIndex > 0;
  BtnMoveDown.Enabled := (LstSelected.ItemIndex >= 0) and (LstSelected.ItemIndex < LstSelected.Items.Count - 1);

  DDL := BuildCreateIndexDDL(
    Profile.DatabaseType,
    TableName,
    EdtIndexName.Text,
    LstSelected.Items,
    ChkUnique.Checked,
    ChkDescending.Checked
  );
  if DDL = '' then
    MemPreview.Lines.Text := '-- Informe o nome do índice e adicione ao menos uma coluna.'
  else
    MemPreview.Lines.Text := DDL + ';';
end;

procedure TIndexDialogHelper.IndexNameKeyPress(Sender: TObject; var Key: Char);
begin
  if Key >= ' ' then
    UserEditedName := True;
end;

procedure TIndexDialogHelper.InputChanged(Sender: TObject);
begin
  UpdateControlsAndPreview;
end;

procedure TIndexDialogHelper.AddColClicked(Sender: TObject);
var
  Idx, NextIdx: Integer;
  ColName: string;
begin
  Idx := LstAvailable.ItemIndex;
  if Idx < 0 then
    Exit;

  ColName := LstAvailable.Items[Idx];
  LstSelected.Items.Add(ColName);
  LstSelected.ItemIndex := LstSelected.Items.Count - 1;
  LstAvailable.Items.Delete(Idx);

  if LstAvailable.Items.Count > 0 then
  begin
    NextIdx := Idx;
    if NextIdx >= LstAvailable.Items.Count then
      NextIdx := LstAvailable.Items.Count - 1;
    LstAvailable.ItemIndex := NextIdx;
  end;

  UpdateSuggestedIndexName;
  UpdateControlsAndPreview;
end;

procedure TIndexDialogHelper.RemoveColClicked(Sender: TObject);
var
  Idx, NextIdx: Integer;
  ColName: string;
begin
  Idx := LstSelected.ItemIndex;
  if Idx < 0 then
    Exit;

  ColName := LstSelected.Items[Idx];
  LstSelected.Items.Delete(Idx);
  LstAvailable.Items.Add(ColName);
  LstAvailable.ItemIndex := LstAvailable.Items.Count - 1;

  if LstSelected.Items.Count > 0 then
  begin
    NextIdx := Idx;
    if NextIdx >= LstSelected.Items.Count then
      NextIdx := LstSelected.Items.Count - 1;
    LstSelected.ItemIndex := NextIdx;
  end;

  UpdateSuggestedIndexName;
  UpdateControlsAndPreview;
end;

procedure TIndexDialogHelper.MoveUpClicked(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := LstSelected.ItemIndex;
  if Idx <= 0 then
    Exit;
  LstSelected.Items.Exchange(Idx, Idx - 1);
  LstSelected.ItemIndex := Idx - 1;
  UpdateSuggestedIndexName;
  UpdateControlsAndPreview;
end;

procedure TIndexDialogHelper.MoveDownClicked(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := LstSelected.ItemIndex;
  if (Idx < 0) or (Idx >= LstSelected.Items.Count - 1) then
    Exit;
  LstSelected.Items.Exchange(Idx, Idx + 1);
  LstSelected.ItemIndex := Idx + 1;
  UpdateSuggestedIndexName;
  UpdateControlsAndPreview;
end;

procedure TIndexDialogHelper.CreateClicked(Sender: TObject);
var
  Msg: string;
begin
  if Trim(EdtIndexName.Text) = '' then
  begin
    MessageDlg('Atenção', 'Informe o nome do índice.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if LstSelected.Items.Count = 0 then
  begin
    MessageDlg('Atenção', 'Selecione ao menos uma coluna para o índice.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if UseCase.CreateIndex(
       Profile,
       TableName,
       EdtIndexName.Text,
       LstSelected.Items,
       ChkUnique.Checked,
       ChkDescending.Checked,
       Msg
     ) then
    Dlg.ModalResult := mrOk
  else
    MessageDlg('Erro ao criar índice', Msg, mtError, [mbOK], 0);
end;

{ TTableEditorFrame }

constructor TTableEditorFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FProfile := nil;
  FTableName := '';
  FUseCase := nil;
  FStructure := nil;
  FUsedByDeps := nil;
  FUsesDeps := nil;
  FDataGrid := nil;
  FLastDataResult := nil;
  FDataLoaded := False;
  FTriggerCompletion := nil;
  FCurrentTriggerName := '';
  FTriggerIsNew := False;
  FTriggerDirty := False;
  FLoadingTrigger := False;
  FUpdatingTriggerToolbarSize := False;
  FLastTriggerToolbarWidth := -1;

  {$IFDEF UNIX}
  grdFields.Font.Name := 'Monospace';
  grdPK.Font.Name := 'Monospace';
  grdFK.Font.Name := 'Monospace';
  grdUnique.Font.Name := 'Monospace';
  grdChecks.Font.Name := 'Monospace';
  grdIndexes.Font.Name := 'Monospace';
  grdDepUsedBy.Font.Name := 'Monospace';
  grdDepUses.Font.Name := 'Monospace';
  SynEditDDL.Font.Name := 'Monospace';
  SynEditTrigger.Font.Name := 'Monospace';
  lblTriggerHeaderPreview.Font.Name := 'Monospace';
  memTriggerLog.Font.Name := 'Monospace';
  {$ENDIF}
  ConfigureGrids;
end;

destructor TTableEditorFrame.Destroy;
begin
  if FDataGrid <> nil then
    FDataGrid.SetResult(nil, False, False);
  FreeAndNil(FLastDataResult);
  FUsedByDeps := nil;
  FUsesDeps := nil;
  FreeAndNil(FStructure);
  FreeAndNil(FProfile);
  inherited Destroy;
end;

procedure TTableEditorFrame.Initialize(
  const AProfile: TConnectionProfile;
  const ATableName: string;
  const AUseCase: TManageTableStructureUseCase
);
begin
  if FDataGrid <> nil then
    FDataGrid.SetResult(nil, False, False);
  FreeAndNil(FLastDataResult);
  FDataLoaded := False;

  FreeAndNil(FProfile);
  if AProfile <> nil then
    FProfile := AProfile.Clone;
  FTableName := Trim(ATableName);
  FUseCase := AUseCase;

  if (FProfile <> nil) and (FProfile.DatabaseType = dtPostgreSQL) then
  begin
    SynSQLSynDDL.SQLDialect := sqlPostgres;
    SynSQLSynTrigger.SQLDialect := sqlPostgres;
  end
  else
  begin
    SynSQLSynDDL.SQLDialect := sqlFirebird40;
    SynSQLSynTrigger.SQLDialect := sqlFirebird40;
  end;

  SynSQLSynDDL.Enabled := True;
  SynEditDDL.Highlighter := SynSQLSynDDL;
  SynSQLSynTrigger.Enabled := True;
  SynEditTrigger.Highlighter := SynSQLSynTrigger;
  SynEditTrigger.Keystrokes.ResetDefaults;

  if FDataGrid = nil then
  begin
    FDataGrid := TQueryResultGridFrame.Create(Self);
    FDataGrid.Name := 'TableDataGridFrame';
    FDataGrid.Parent := tsData;
    FDataGrid.Align := alClient;
    FDataGrid.EmptyMessage := 'Clique em "Atualizar Dados" ou abra a aba Dados para carregar os registros.';
    FDataGrid.OnExportedCsv := @HandleDataGridExportedCsv;
  end;
  FDataGrid.SetResult(nil, True, False);

  if FTriggerCompletion = nil then
    FTriggerCompletion := TSqlCompletionController.Create(
      Self,
      SynEditTrigger,
      @GetCompletionProfile,
      @ExecuteCompletionMetadataQuery
    );
  FTriggerCompletion.IncludeProceduralKeywords := True;
  FTriggerCompletion.DefaultTriggerTable := FTableName;
  FTriggerCompletion.ClearMetadataCache;

  if FProfile <> nil then
    lblTableTitle.Caption := Format('Tabela: %s  |  Conexão: %s (%s)', [
      FTableName,
      FProfile.Name,
      DatabaseTypeToStr(FProfile.DatabaseType)
    ])
  else
    lblTableTitle.Caption := 'Tabela: ' + FTableName;

  pgTable.ActivePage := tsFields;
  LoadAndDisplayStructure;
end;

procedure TTableEditorFrame.RefreshAll;
begin
  LoadAndDisplayStructure(FCurrentTriggerName);
  if (pgTable.ActivePage = tsData) and FDataLoaded then
    LoadTableDataGrid;
end;

procedure TTableEditorFrame.ClearMetadataCache;
begin
  if FTriggerCompletion <> nil then
    FTriggerCompletion.ClearMetadataCache;
end;

function TTableEditorFrame.HasUnsavedTriggerChanges: Boolean;
begin
  Result := FTriggerDirty;
end;

function TTableEditorFrame.ProfileId: string;
begin
  if FProfile <> nil then
    Result := FProfile.Id
  else
    Result := '';
end;

function TTableEditorFrame.GetCompletionProfile: TConnectionProfile;
begin
  Result := FProfile;
end;

function TTableEditorFrame.ExecuteCompletionMetadataQuery(const ASQL: string): TQueryResult;
begin
  if (FUseCase <> nil) and (FProfile <> nil) then
    Result := FUseCase.ExecuteMetadataQuery(FProfile, ASQL)
  else
    Result := nil;
end;

procedure TTableEditorFrame.HandleDataGridExportedCsv(Sender: TObject; const AFileName: string);
begin
  lblStatus.Caption := 'Dados exportados para CSV: ' + AFileName;
end;

procedure TTableEditorFrame.ConfigureGrids;
begin
  grdFields.ColCount := 8;
  grdFields.Cells[0, 0] := '#';
  grdFields.Cells[1, 0] := 'Campo';
  grdFields.Cells[2, 0] := 'Tipo';
  grdFields.Cells[3, 0] := 'Domínio';
  grdFields.Cells[4, 0] := 'Not Null';
  grdFields.Cells[5, 0] := 'PK';
  grdFields.Cells[6, 0] := 'Valor Padrão';
  grdFields.Cells[7, 0] := 'Detalhes / Calculado';
  grdFields.ColWidths[0] := 42;
  grdFields.ColWidths[1] := 175;
  grdFields.ColWidths[2] := 150;
  grdFields.ColWidths[3] := 120;
  grdFields.ColWidths[4] := 70;
  grdFields.ColWidths[5] := 48;
  grdFields.ColWidths[6] := 125;
  grdFields.ColWidths[7] := 180;

  grdPK.ColCount := 2;
  grdPK.Cells[0, 0] := 'Constraint';
  grdPK.Cells[1, 0] := 'Colunas';
  grdPK.ColWidths[0] := 260;
  grdPK.ColWidths[1] := 540;

  grdFK.ColCount := 6;
  grdFK.Cells[0, 0] := 'Constraint';
  grdFK.Cells[1, 0] := 'Colunas';
  grdFK.Cells[2, 0] := 'Tabela Referenciada';
  grdFK.Cells[3, 0] := 'Colunas Ref.';
  grdFK.Cells[4, 0] := 'ON UPDATE';
  grdFK.Cells[5, 0] := 'ON DELETE';
  grdFK.ColWidths[0] := 190;
  grdFK.ColWidths[1] := 150;
  grdFK.ColWidths[2] := 180;
  grdFK.ColWidths[3] := 150;
  grdFK.ColWidths[4] := 105;
  grdFK.ColWidths[5] := 105;

  grdUnique.ColCount := 2;
  grdUnique.Cells[0, 0] := 'Constraint';
  grdUnique.Cells[1, 0] := 'Colunas';
  grdUnique.ColWidths[0] := 260;
  grdUnique.ColWidths[1] := 540;

  grdChecks.ColCount := 2;
  grdChecks.Cells[0, 0] := 'Constraint';
  grdChecks.Cells[1, 0] := 'Condição (CHECK)';
  grdChecks.ColWidths[0] := 240;
  grdChecks.ColWidths[1] := 600;

  grdIndexes.ColCount := 6;
  grdIndexes.Cells[0, 0] := 'Índice';
  grdIndexes.Cells[1, 0] := 'Colunas / Expressão';
  grdIndexes.Cells[2, 0] := 'Único';
  grdIndexes.Cells[3, 0] := 'Ordem';
  grdIndexes.Cells[4, 0] := 'Ativo';
  grdIndexes.Cells[5, 0] := 'Constraint / Tipo';
  grdIndexes.ColWidths[0] := 210;
  grdIndexes.ColWidths[1] := 280;
  grdIndexes.ColWidths[2] := 65;
  grdIndexes.ColWidths[3] := 80;
  grdIndexes.ColWidths[4] := 65;
  grdIndexes.ColWidths[5] := 200;

  grdDepUsedBy.ColCount := 2;
  grdDepUsedBy.Cells[0, 0] := 'Objeto';
  grdDepUsedBy.Cells[1, 0] := 'Tipo';
  grdDepUsedBy.ColWidths[0] := 480;
  grdDepUsedBy.ColWidths[1] := 340;

  grdDepUses.ColCount := 2;
  grdDepUses.Cells[0, 0] := 'Objeto';
  grdDepUses.Cells[1, 0] := 'Tipo';
  grdDepUses.ColWidths[0] := 480;
  grdDepUses.ColWidths[1] := 340;
end;

procedure TTableEditorFrame.LoadAndDisplayStructure(const ASelectTriggerName: string);
var
  NewStruct: TTableStructure;
begin
  if (FUseCase = nil) or (FProfile = nil) then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    try
      NewStruct := FUseCase.LoadTableStructure(FProfile, FTableName);
      FreeAndNil(FStructure);
      FStructure := NewStruct;
      PopulateFieldsGrid;
      PopulateConstraintsGrids;
      PopulateIndexesGrid;
      PopulateTriggersTree(ASelectTriggerName);
      PopulateDependenciesFieldFilter;
      RefreshDependenciesDisplay;
      RefreshDDLPreview;
      lblStatus.Caption := Format('%d campo(s) | %d índice(s) | %d trigger(s) | %d dependência(s)', [
        Length(FStructure.Columns),
        Length(FStructure.Indexes),
        Length(FStructure.Triggers),
        Length(FStructure.Dependencies)
      ]);
    except
      on E: Exception do
      begin
        lblStatus.Caption := 'Erro ao carregar estrutura: ' + E.Message;
        MessageDlg('Erro ao carregar estrutura da tabela', E.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    Screen.Cursor := crDefault;
    UpdateButtonsState;
  end;
end;

procedure TTableEditorFrame.PopulateFieldsGrid;
var
  I, R: Integer;
  Col: TTableColumnInfo;
  Details: string;
begin
  if (FStructure = nil) or (Length(FStructure.Columns) = 0) then
  begin
    grdFields.RowCount := 1;
    Exit;
  end;

  grdFields.RowCount := Length(FStructure.Columns) + 1;
  for I := 0 to High(FStructure.Columns) do
  begin
    Col := FStructure.Columns[I];
    R := I + 1;
    grdFields.Cells[0, R] := IntToStr(Col.Position);
    grdFields.Cells[1, R] := Col.ColumnName;
    grdFields.Cells[2, R] := Col.DataType;
    grdFields.Cells[3, R] := Col.DomainName;
    if Col.NotNull then
      grdFields.Cells[4, R] := 'Sim'
    else
      grdFields.Cells[4, R] := 'Não';
    if Col.IsPrimaryKey then
      grdFields.Cells[5, R] := 'PK'
    else
      grdFields.Cells[5, R] := '';
    grdFields.Cells[6, R] := Col.DefaultValue;
    Details := '';
    if Col.IsComputed then
      Details := 'COMPUTED: ' + Col.ComputedSource;
    if Col.Description <> '' then
    begin
      if Details <> '' then
        Details := Details + ' | ';
      Details := Details + Col.Description;
    end;
    grdFields.Cells[7, R] := Details;
  end;
  if grdFields.RowCount > 1 then
    grdFields.Row := 1;
end;

procedure TTableEditorFrame.PopulateConstraintsGrids;
var
  I, R, PkCount: Integer;
  FK: TTableForeignKeyInfo;
  UK: TTableUniqueConstraintInfo;
  CHK: TTableCheckConstraintInfo;
begin
  if FStructure = nil then
  begin
    grdPK.RowCount := 1;
    grdFK.RowCount := 1;
    grdUnique.RowCount := 1;
    grdChecks.RowCount := 1;
    tsConstraintPK.Caption := 'Primary Key (0)';
    tsConstraintFK.Caption := 'Foreign Keys (0)';
    tsConstraintUnique.Caption := 'Unique (0)';
    tsConstraintChecks.Caption := 'Checks (0)';
    Exit;
  end;

  { Primary Key }
  if Trim(FStructure.PrimaryKeyColumns) <> '' then
  begin
    PkCount := 1;
    grdPK.RowCount := 2;
    if Trim(FStructure.PrimaryKeyName) <> '' then
      grdPK.Cells[0, 1] := FStructure.PrimaryKeyName
    else
      grdPK.Cells[0, 1] := '(PRIMARY KEY)';
    grdPK.Cells[1, 1] := FStructure.PrimaryKeyColumns;
  end
  else
  begin
    PkCount := 0;
    grdPK.RowCount := 1;
  end;
  tsConstraintPK.Caption := Format('Primary Key (%d)', [PkCount]);

  { Foreign Keys }
  if Length(FStructure.ForeignKeys) = 0 then
    grdFK.RowCount := 1
  else
  begin
    grdFK.RowCount := Length(FStructure.ForeignKeys) + 1;
    for I := 0 to High(FStructure.ForeignKeys) do
    begin
      FK := FStructure.ForeignKeys[I];
      R := I + 1;
      grdFK.Cells[0, R] := FK.ConstraintName;
      grdFK.Cells[1, R] := FK.Columns;
      grdFK.Cells[2, R] := FK.RefTable;
      grdFK.Cells[3, R] := FK.RefColumns;
      grdFK.Cells[4, R] := FK.UpdateRule;
      grdFK.Cells[5, R] := FK.DeleteRule;
    end;
    grdFK.Row := 1;
  end;
  tsConstraintFK.Caption := Format('Foreign Keys (%d)', [Length(FStructure.ForeignKeys)]);

  { Unique Constraints }
  if Length(FStructure.UniqueConstraints) = 0 then
    grdUnique.RowCount := 1
  else
  begin
    grdUnique.RowCount := Length(FStructure.UniqueConstraints) + 1;
    for I := 0 to High(FStructure.UniqueConstraints) do
    begin
      UK := FStructure.UniqueConstraints[I];
      R := I + 1;
      grdUnique.Cells[0, R] := UK.ConstraintName;
      grdUnique.Cells[1, R] := UK.Columns;
    end;
    grdUnique.Row := 1;
  end;
  tsConstraintUnique.Caption := Format('Unique (%d)', [Length(FStructure.UniqueConstraints)]);

  { Check Constraints }
  if Length(FStructure.CheckConstraints) = 0 then
    grdChecks.RowCount := 1
  else
  begin
    grdChecks.RowCount := Length(FStructure.CheckConstraints) + 1;
    for I := 0 to High(FStructure.CheckConstraints) do
    begin
      CHK := FStructure.CheckConstraints[I];
      R := I + 1;
      grdChecks.Cells[0, R] := CHK.ConstraintName;
      grdChecks.Cells[1, R] := CHK.CheckSource;
    end;
    grdChecks.Row := 1;
  end;
  tsConstraintChecks.Caption := Format('Checks (%d)', [Length(FStructure.CheckConstraints)]);
end;

procedure TTableEditorFrame.PopulateIndexesGrid;
var
  I, R: Integer;
  IdxInfo: TTableIndexInfo;
  OriginText: string;
begin
  if (FStructure = nil) or (Length(FStructure.Indexes) = 0) then
  begin
    grdIndexes.RowCount := 1;
    Exit;
  end;

  grdIndexes.RowCount := Length(FStructure.Indexes) + 1;
  for I := 0 to High(FStructure.Indexes) do
  begin
    IdxInfo := FStructure.Indexes[I];
    R := I + 1;
    grdIndexes.Cells[0, R] := IdxInfo.IndexName;
    if IdxInfo.ExpressionSource <> '' then
      grdIndexes.Cells[1, R] := IdxInfo.ExpressionSource
    else
      grdIndexes.Cells[1, R] := IdxInfo.Columns;
    if IdxInfo.IsUnique then
      grdIndexes.Cells[2, R] := 'Sim'
    else
      grdIndexes.Cells[2, R] := 'Não';
    if IdxInfo.IsDescending then
      grdIndexes.Cells[3, R] := 'DESC'
    else
      grdIndexes.Cells[3, R] := 'ASC';
    if IdxInfo.IsActive then
      grdIndexes.Cells[4, R] := 'Sim'
    else
      grdIndexes.Cells[4, R] := 'Inativo';

    if IdxInfo.IsPrimaryKey then
      OriginText := 'PRIMARY KEY (' + IdxInfo.ConstraintName + ')'
    else if IdxInfo.IsForeignKey then
      OriginText := 'FOREIGN KEY (' + IdxInfo.ConstraintName + ')'
    else if IdxInfo.ConstraintName <> '' then
      OriginText := 'UNIQUE (' + IdxInfo.ConstraintName + ')'
    else
      OriginText := 'Índice manual';
    grdIndexes.Cells[5, R] := OriginText;
  end;
  if grdIndexes.RowCount > 1 then
    grdIndexes.Row := 1;
end;

function TTableEditorFrame.ClassifyTriggerCategoryCode(const ATrig: TTableTriggerInfo): Integer;
var
  EvCount: Integer;
  IsBefore, IsAfter: Boolean;
begin
  EvCount := 0;
  if ATrig.HasInsert then Inc(EvCount);
  if ATrig.HasUpdate then Inc(EvCount);
  if ATrig.HasDelete then Inc(EvCount);

  IsBefore := SameText(Trim(ATrig.Timing), 'BEFORE');
  IsAfter := SameText(Trim(ATrig.Timing), 'AFTER');

  if (EvCount <> 1) or ((not IsBefore) and (not IsAfter)) or
     (Pos('TRUNCATE', UpperCase(ATrig.Events)) > 0) then
    Exit(7);

  if ATrig.HasInsert then
  begin
    if IsBefore then Result := 1 else Result := 2;
  end
  else if ATrig.HasUpdate then
  begin
    if IsBefore then Result := 3 else Result := 4;
  end
  else
  begin
    if IsBefore then Result := 5 else Result := 6;
  end;
end;

procedure TTableEditorFrame.CategoryCodeToDefaults(
  const ACatCode: Integer;
  out ATiming: string;
  out AHasInsert, AHasUpdate, AHasDelete: Boolean
);
begin
  ATiming := 'BEFORE';
  AHasInsert := False;
  AHasUpdate := False;
  AHasDelete := False;
  case ACatCode of
    1: begin ATiming := 'BEFORE'; AHasInsert := True; end;
    2: begin ATiming := 'AFTER';  AHasInsert := True; end;
    3: begin ATiming := 'BEFORE'; AHasUpdate := True; end;
    4: begin ATiming := 'AFTER';  AHasUpdate := True; end;
    5: begin ATiming := 'BEFORE'; AHasDelete := True; end;
    6: begin ATiming := 'AFTER';  AHasDelete := True; end;
  else
    ATiming := 'BEFORE';
    AHasInsert := True;
  end;
end;

procedure TTableEditorFrame.PopulateTriggersTree(const APreferredTriggerName: string);
var
  CatNodes: array[1..7] of TTreeNode;
  CatCounts: array[1..7] of Integer;
  I, CatCode: Integer;
  Trig: TTableTriggerInfo;
  NodeText, TargetName: string;
  FirstTrigNode, SelectedNode, TrigNode: TTreeNode;
begin
  FLoadingTrigger := True;
  tvTriggers.Items.BeginUpdate;
  try
    tvTriggers.Items.Clear;
    for I := 1 to 7 do
    begin
      CatNodes[I] := nil;
      CatCounts[I] := 0;
    end;

    CatNodes[1] := tvTriggers.Items.AddObject(nil, 'Before Insert', Pointer(PtrUInt(1)));
    CatNodes[2] := tvTriggers.Items.AddObject(nil, 'After Insert', Pointer(PtrUInt(2)));
    CatNodes[3] := tvTriggers.Items.AddObject(nil, 'Before Update', Pointer(PtrUInt(3)));
    CatNodes[4] := tvTriggers.Items.AddObject(nil, 'After Update', Pointer(PtrUInt(4)));
    CatNodes[5] := tvTriggers.Items.AddObject(nil, 'Before Delete', Pointer(PtrUInt(5)));
    CatNodes[6] := tvTriggers.Items.AddObject(nil, 'After Delete', Pointer(PtrUInt(6)));

    FirstTrigNode := nil;
    SelectedNode := nil;
    TargetName := Trim(APreferredTriggerName);

    if FStructure <> nil then
    begin
      for I := 0 to High(FStructure.Triggers) do
      begin
        Trig := FStructure.Triggers[I];
        CatCode := ClassifyTriggerCategoryCode(Trig);
        if (CatCode = 7) and (CatNodes[7] = nil) then
          CatNodes[7] := tvTriggers.Items.AddObject(nil, 'Multi-evento / Outros', Pointer(PtrUInt(7)));

        Inc(CatCounts[CatCode]);

        if CatCode = 7 then
          NodeText := Format('%s [%s %s]', [Trig.TriggerName, Trig.Timing, Trig.Events])
        else if (FProfile <> nil) and (FProfile.DatabaseType = dtFirebird) then
          NodeText := Format('%s [Pos %d]', [Trig.TriggerName, Trig.Position])
        else
          NodeText := Trig.TriggerName;

        if not Trig.IsActive then
          NodeText := NodeText + ' (INATIVA)';

        if CatNodes[CatCode] <> nil then
        begin
          TrigNode := tvTriggers.Items.AddChildObject(
            CatNodes[CatCode],
            NodeText,
            Pointer(PtrUInt(TRIG_NODE_DATA_BASE + I))
          );
          if FirstTrigNode = nil then
            FirstTrigNode := TrigNode;
          if (TargetName <> '') and SameText(Trig.TriggerName, TargetName) then
            SelectedNode := TrigNode;
        end;
      end;
    end;

    for I := 1 to 7 do
    begin
      if (CatNodes[I] <> nil) and (CatCounts[I] > 0) then
      begin
        CatNodes[I].Text := Format('%s (%d)', [CatNodes[I].Text, CatCounts[I]]);
        CatNodes[I].Expand(False);
      end
      else if CatNodes[I] <> nil then
        CatNodes[I].Expand(False);
    end;

    if SelectedNode <> nil then
      tvTriggers.Selected := SelectedNode
    else if FirstTrigNode <> nil then
      tvTriggers.Selected := FirstTrigNode
    else
      tvTriggers.Selected := CatNodes[1];

    if tvTriggers.Selected <> nil then
      tvTriggers.Selected.MakeVisible;
  finally
    tvTriggers.Items.EndUpdate;
    FLoadingTrigger := False;
  end;

  if FStructure <> nil then
    tsTriggers.Caption := Format('Triggers (%d)', [Length(FStructure.Triggers)])
  else
    tsTriggers.Caption := 'Triggers (0)';

  if SelectedTriggerIndex >= 0 then
    LoadSelectedTriggerIntoEditor
  else
    ClearTriggerEditorPlaceholder;
end;

function TTableEditorFrame.SelectedTriggerIndex: Integer;
var
  DataVal: PtrUInt;
begin
  Result := -1;
  if (FStructure = nil) or (tvTriggers.Selected = nil) then
    Exit;
  DataVal := PtrUInt(tvTriggers.Selected.Data);
  if (DataVal >= TRIG_NODE_DATA_BASE) and
     (DataVal - TRIG_NODE_DATA_BASE <= PtrUInt(High(FStructure.Triggers))) then
    Result := Integer(DataVal - TRIG_NODE_DATA_BASE);
end;

function TTableEditorFrame.SelectedTreeCategoryCode: Integer;
var
  Node: TTreeNode;
  DataVal: PtrUInt;
begin
  Result := 1;
  Node := tvTriggers.Selected;
  if Node = nil then
    Exit;
  DataVal := PtrUInt(Node.Data);
  if (DataVal >= 1) and (DataVal <= 7) then
  begin
    Result := Integer(DataVal);
    Exit;
  end;
  if (DataVal >= TRIG_NODE_DATA_BASE) and (Node.Parent <> nil) then
  begin
    DataVal := PtrUInt(Node.Parent.Data);
    if (DataVal >= 1) and (DataVal <= 7) then
      Result := Integer(DataVal);
  end;
end;

function TTableEditorFrame.TriggerExistsInStructure(const AName: string): Boolean;
begin
  Result := FindTriggerIndexByName(AName) >= 0;
end;

function TTableEditorFrame.FindTriggerIndexByName(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if (FStructure = nil) or (Trim(AName) = '') then
    Exit;
  for I := 0 to High(FStructure.Triggers) do
    if SameText(FStructure.Triggers[I].TriggerName, Trim(AName)) then
      Exit(I);
end;

function TTableEditorFrame.BuildSuggestedTriggerName(
  const ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete: Boolean
): string;
var
  Prefix, EvCode, Base, Candidate: string;
  Seq, MaxLen: Integer;
  IsPG, TrimTo31: Boolean;
begin
  IsPG := (FProfile <> nil) and (FProfile.DatabaseType = dtPostgreSQL);
  TrimTo31 := (FProfile <> nil) and (FProfile.DatabaseType = dtFirebird) and
    (FProfile.FirebirdVersion in [fvAuto, fv25, fv30]);

  if SameText(Trim(ATiming), 'AFTER') then
    Prefix := 'A'
  else
    Prefix := 'B';

  EvCode := '';
  if AHasInsert then EvCode := EvCode + 'I';
  if AHasUpdate then EvCode := EvCode + 'U';
  if AHasDelete then EvCode := EvCode + 'D';
  if EvCode = '' then
    EvCode := 'I';

  Base := Trim(FTableName) + '_' + Prefix + EvCode;
  if IsPG then
    Base := 'trg_' + LowerCase(Base)
  else
    Base := 'TRG_' + UpperCase(Base);

  Seq := 0;
  repeat
    Candidate := Base + IntToStr(Seq);
    if TrimTo31 and (Length(Candidate) > 31) then
    begin
      MaxLen := 31 - Length('_' + Prefix + EvCode + IntToStr(Seq));
      if MaxLen < 4 then
        MaxLen := 4;
      Candidate := Copy('TRG_' + UpperCase(Trim(FTableName)), 1, MaxLen) + '_' + Prefix + EvCode + IntToStr(Seq);
      if Length(Candidate) > 31 then
        Candidate := Copy(Candidate, 1, 31);
    end;
    Inc(Seq);
  until not TriggerExistsInStructure(Candidate);

  Result := Candidate;
end;

procedure TTableEditorFrame.LoadSelectedTriggerIntoEditor;
var
  Idx: Integer;
  Trig: TTableTriggerInfo;
begin
  Idx := SelectedTriggerIndex;
  if Idx < 0 then
  begin
    ClearTriggerEditorPlaceholder;
    Exit;
  end;

  Trig := FStructure.Triggers[Idx];
  FLoadingTrigger := True;
  try
    FCurrentTriggerName := Trig.TriggerName;
    FTriggerIsNew := False;
    FTriggerDirty := False;

    edtTriggerName.Text := Trig.TriggerName;
    edtTriggerName.ReadOnly := True;
    chkTriggerActive.Checked := Trig.IsActive;
    spnTriggerPos.Value := Max(0, Trig.Position);

    if SameText(Trig.Timing, 'AFTER') then
      cbTriggerTiming.ItemIndex := 1
    else
      cbTriggerTiming.ItemIndex := 0;

    chkTrigInsert.Checked := Trig.HasInsert;
    chkTrigUpdate.Checked := Trig.HasUpdate;
    chkTrigDelete.Checked := Trig.HasDelete;

    SynEditTrigger.Lines.Text := Trig.SourceBody;
    SynEditTrigger.ReadOnly := False;
  finally
    FLoadingTrigger := False;
  end;

  UpdateTriggerHeaderPreview;
  UpdateTriggerEditorControlsState;
end;

procedure TTableEditorFrame.ClearTriggerEditorPlaceholder;
begin
  FLoadingTrigger := True;
  try
    FCurrentTriggerName := '';
    FTriggerIsNew := False;
    FTriggerDirty := False;
    edtTriggerName.Text := '';
    edtTriggerName.ReadOnly := True;
    chkTriggerActive.Checked := True;
    spnTriggerPos.Value := 0;
    cbTriggerTiming.ItemIndex := 0;
    chkTrigInsert.Checked := True;
    chkTrigUpdate.Checked := False;
    chkTrigDelete.Checked := False;
    SynEditTrigger.Lines.Clear;
    SynEditTrigger.ReadOnly := True;
  finally
    FLoadingTrigger := False;
  end;

  UpdateTriggerHeaderPreview;
  UpdateTriggerEditorControlsState;
end;

procedure TTableEditorFrame.StartNewTrigger(
  const ATiming: string;
  const AHasInsert, AHasUpdate, AHasDelete: Boolean
);
var
  SuggestedName: string;
  IsPG: Boolean;
begin
  if not ConfirmDiscardTriggerChanges then
    Exit;

  IsPG := (FProfile <> nil) and (FProfile.DatabaseType = dtPostgreSQL);
  SuggestedName := BuildSuggestedTriggerName(ATiming, AHasInsert, AHasUpdate, AHasDelete);

  FLoadingTrigger := True;
  try
    FCurrentTriggerName := '';
    FTriggerIsNew := True;
    FTriggerDirty := False;

    edtTriggerName.Text := SuggestedName;
    edtTriggerName.ReadOnly := IsPG;
    chkTriggerActive.Checked := True;
    spnTriggerPos.Value := 0;
    if SameText(ATiming, 'AFTER') then
      cbTriggerTiming.ItemIndex := 1
    else
      cbTriggerTiming.ItemIndex := 0;
    chkTrigInsert.Checked := AHasInsert;
    chkTrigUpdate.Checked := AHasUpdate;
    chkTrigDelete.Checked := AHasDelete;

    if FProfile <> nil then
      SynEditTrigger.Lines.Text := BuildNewTableTriggerTemplate(
        FProfile.DatabaseType,
        FTableName,
        SuggestedName,
        cbTriggerTiming.Text,
        AHasInsert,
        AHasUpdate,
        AHasDelete
      )
    else
      SynEditTrigger.Lines.Clear;
    SynEditTrigger.ReadOnly := False;
  finally
    FLoadingTrigger := False;
  end;

  UpdateTriggerHeaderPreview;
  UpdateTriggerEditorControlsState;
  if SynEditTrigger.CanFocus then
    SynEditTrigger.SetFocus;
  LogTriggerMessage(Format('Modelo de nova trigger "%s" pronto. Pressione F9 para compilar.', [SuggestedName]));
end;

procedure TTableEditorFrame.UpdateTriggerHeaderPreview;
var
  IsPG: Boolean;
  TimingStr, EventsStr, HeaderText: string;
  TrigIdx: Integer;
  FuncName: string;
begin
  IsPG := (FProfile <> nil) and (FProfile.DatabaseType = dtPostgreSQL);

  if (not FTriggerIsNew) and (FCurrentTriggerName = '') then
  begin
    lblTriggerHeaderPreview.Caption := '-- Selecione uma trigger à esquerda ou clique em "+ Nova" para criar uma trigger.';
    Exit;
  end;

  if IsPG then
  begin
    TrigIdx := FindTriggerIndexByName(FCurrentTriggerName);
    FuncName := '';
    if TrigIdx >= 0 then
      FuncName := FStructure.Triggers[TrigIdx].FunctionName;
    TimingStr := cbTriggerTiming.Text;
    EventsStr := BuildTriggerEventsClause(chkTrigInsert.Checked, chkTrigUpdate.Checked, chkTrigDelete.Checked);
    if TrigIdx >= 0 then
    begin
      TimingStr := FStructure.Triggers[TrigIdx].Timing;
      EventsStr := FStructure.Triggers[TrigIdx].Events;
    end;
    if FuncName <> '' then
      lblTriggerHeaderPreview.Caption := Format('PostgreSQL: %s %s ON %s  |  Função: %s  (F9 recompila / Ctrl+Espaço autocompleta)', [
        TimingStr, EventsStr, FTableName, FuncName
      ])
    else
      lblTriggerHeaderPreview.Caption := Format('PostgreSQL: Edite o comando CREATE TRIGGER completo abaixo (%s)', [FTableName]);
  end
  else
  begin
    if StartsWithAnyTriggerDDL(SynEditTrigger.Lines.Text) then
      lblTriggerHeaderPreview.Caption := 'Modo DDL completo detectado no editor (CREATE/ALTER TRIGGER será executado diretamente).'
    else
    begin
      HeaderText := BuildFirebirdTriggerHeader(
        FTableName,
        edtTriggerName.Text,
        cbTriggerTiming.Text,
        chkTrigInsert.Checked,
        chkTrigUpdate.Checked,
        chkTrigDelete.Checked,
        chkTriggerActive.Checked,
        spnTriggerPos.Value
      );
      lblTriggerHeaderPreview.Caption := HeaderText;
    end;
  end;
end;

procedure TTableEditorFrame.UpdateTriggerToolbarLayout;
begin
  if FUpdatingTriggerToolbarSize or (pnlTriggerToolbar = nil) then
    Exit;

  FUpdatingTriggerToolbarSize := True;
  try
    FLastTriggerToolbarWidth := pnlTriggerToolbar.Width;
    pnlTriggerToolbar.ReAlign;
    pnlTriggerToolbar.InvalidatePreferredSize;
    pnlTriggerToolbar.AdjustSize;
  finally
    FUpdatingTriggerToolbarSize := False;
  end;
end;

procedure TTableEditorFrame.UpdateTriggerEditorControlsState;
var
  HasLoaded, IsPG: Boolean;
  TrigIdx: Integer;
  IsActiveFlag: Boolean;
begin
  HasLoaded := FTriggerIsNew or (FCurrentTriggerName <> '');
  IsPG := (FProfile <> nil) and (FProfile.DatabaseType = dtPostgreSQL);
  TrigIdx := SelectedTriggerIndex;

  pnlTriggerMetaRow2.Visible := not IsPG;
  lblTrigPos.Visible := not IsPG;
  spnTriggerPos.Visible := not IsPG;
  chkTriggerActive.Enabled := (not IsPG) and HasLoaded;
  edtTriggerName.Enabled := HasLoaded and (not IsPG);

  btnCompileTrigger.Enabled := HasLoaded;
  btnReloadTrigger.Enabled := (not FTriggerIsNew) and (FCurrentTriggerName <> '');
  btnCopyTriggerDDL.Enabled := HasLoaded and (Trim(SynEditTrigger.Lines.Text) <> '');
  btnOpenTriggerInTab.Enabled := (not FTriggerIsNew) and (FCurrentTriggerName <> '');

  if TrigIdx >= 0 then
  begin
    IsActiveFlag := FStructure.Triggers[TrigIdx].IsActive;
    btnToggleTriggerActive.Enabled := True;
    if IsActiveFlag then
      btnToggleTriggerActive.Caption := 'Inativar'
    else
      btnToggleTriggerActive.Caption := 'Ativar';
    btnDropTrigger.Enabled := True;
    btnOpenTriggerFunction.Visible := IsPG and (FStructure.Triggers[TrigIdx].FunctionName <> '');
  end
  else
  begin
    btnToggleTriggerActive.Enabled := False;
    btnToggleTriggerActive.Caption := 'Ativar / Inativar';
    btnDropTrigger.Enabled := False;
    btnOpenTriggerFunction.Visible := False;
  end;

  if FTriggerIsNew then
  begin
    if FTriggerDirty then
      lblTriggerState.Caption := Format('Nova: %s *', [edtTriggerName.Text])
    else
      lblTriggerState.Caption := Format('Nova: %s', [edtTriggerName.Text]);
  end
  else if FCurrentTriggerName <> '' then
  begin
    if FTriggerDirty then
      lblTriggerState.Caption := Format('Editando: %s *', [FCurrentTriggerName])
    else
      lblTriggerState.Caption := Format('Editando: %s', [FCurrentTriggerName]);
  end
  else
    lblTriggerState.Caption := 'Nenhuma trigger selecionada';

  UpdateTriggerToolbarLayout;
end;

procedure TTableEditorFrame.LogTriggerMessage(const AMsg: string);
begin
  memTriggerLog.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss', Now), AMsg]));
end;

function TTableEditorFrame.ConfirmDiscardTriggerChanges: Boolean;
begin
  if not FTriggerDirty then
    Exit(True);

  Result := MessageDlg(
    'Alterações não compiladas',
    'Existem alterações não compiladas na trigger atual. Deseja descartá-las?',
    mtConfirmation,
    [mbYes, mbNo],
    0
  ) = mrYes;
end;

procedure TTableEditorFrame.PopulateDependenciesFieldFilter;
var
  PrevText: string;
  I, NewIdx: Integer;
begin
  if cbDepField = nil then
    Exit;

  PrevText := '';
  if cbDepField.ItemIndex > 0 then
    PrevText := cbDepField.Text;

  cbDepField.Items.BeginUpdate;
  try
    cbDepField.Items.Clear;
    cbDepField.Items.Add('(Toda a tabela)');
    if FStructure <> nil then
    begin
      for I := 0 to High(FStructure.Columns) do
        cbDepField.Items.Add(FStructure.Columns[I].ColumnName);
    end;
    NewIdx := 0;
    if PrevText <> '' then
    begin
      for I := 1 to cbDepField.Items.Count - 1 do
      begin
        if SameText(cbDepField.Items[I], PrevText) then
        begin
          NewIdx := I;
          Break;
        end;
      end;
    end;
    cbDepField.ItemIndex := NewIdx;
  finally
    cbDepField.Items.EndUpdate;
  end;
end;

procedure TTableEditorFrame.RefreshDependenciesDisplay;
var
  FieldName: string;
  FieldDeps: TTableDependencyInfoArray;
begin
  if cbDepField.ItemIndex <= 0 then
  begin
    lblDepUsedBy.Caption := 'Objetos que dependem desta tabela (Usada por — duplo clique para abrir):';
    lblDepUses.Caption := 'Esta tabela depende de (Referencia — duplo clique para abrir):';
    if FStructure <> nil then
      PopulateDependenciesGrids(FStructure.Dependencies)
    else
      PopulateDependenciesGrids(nil);
    Exit;
  end;

  FieldName := Trim(cbDepField.Text);
  lblDepUsedBy.Caption := Format('Objetos que utilizam o campo "%s" (duplo clique para abrir):', [FieldName]);
  lblDepUses.Caption := Format('Objetos referenciados pelo campo "%s" (duplo clique para abrir):', [FieldName]);

  Screen.Cursor := crHourGlass;
  try
    FieldDeps := FUseCase.LoadFieldDependencies(FProfile, FTableName, FieldName);
    PopulateDependenciesGrids(FieldDeps);
    lblStatus.Caption := Format('Campo "%s": %d dependência(s) encontrada(s).', [FieldName, Length(FieldDeps)]);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TTableEditorFrame.PopulateDependenciesGrids(const ADeps: TTableDependencyInfoArray);
var
  I, R: Integer;
  Dep: TTableDependencyInfo;
begin
  FUsedByDeps := nil;
  FUsesDeps := nil;
  for I := 0 to High(ADeps) do
  begin
    Dep := ADeps[I];
    if Dep.Direction = tddDependentOnTable then
    begin
      SetLength(FUsedByDeps, Length(FUsedByDeps) + 1);
      FUsedByDeps[High(FUsedByDeps)] := Dep;
    end
    else
    begin
      SetLength(FUsesDeps, Length(FUsesDeps) + 1);
      FUsesDeps[High(FUsesDeps)] := Dep;
    end;
  end;

  if Length(FUsedByDeps) = 0 then
    grdDepUsedBy.RowCount := 1
  else
  begin
    grdDepUsedBy.RowCount := Length(FUsedByDeps) + 1;
    for I := 0 to High(FUsedByDeps) do
    begin
      R := I + 1;
      grdDepUsedBy.Cells[0, R] := FUsedByDeps[I].ObjectName;
      grdDepUsedBy.Cells[1, R] := FUsedByDeps[I].ObjectType;
    end;
  end;

  if Length(FUsesDeps) = 0 then
    grdDepUses.RowCount := 1
  else
  begin
    grdDepUses.RowCount := Length(FUsesDeps) + 1;
    for I := 0 to High(FUsesDeps) do
    begin
      R := I + 1;
      grdDepUses.Cells[0, R] := FUsesDeps[I].ObjectName;
      grdDepUses.Cells[1, R] := FUsesDeps[I].ObjectType;
    end;
  end;
end;

procedure TTableEditorFrame.RefreshDDLPreview;
begin
  if (FProfile = nil) or (FStructure = nil) then
  begin
    SynEditDDL.Lines.Clear;
    Exit;
  end;
  SynEditDDL.Lines.Text := GenerateTableDDL(
    FProfile.DatabaseType,
    FStructure,
    True,
    chkIncludeTriggersDDL.Checked
  );
end;

procedure TTableEditorFrame.OpenDependencyFromGrid(
  const AGrid: TStringGrid;
  const ADeps: TTableDependencyInfoArray
);
var
  MousePos: TPoint;
  ACol, ARow: Integer;
  Dep: TTableDependencyInfo;
  Kind: TSchemaObjectKind;
begin
  if (AGrid = nil) or (FProfile = nil) or (not Assigned(FOnOpenDependency)) then
    Exit;

  MousePos := AGrid.ScreenToClient(Mouse.CursorPos);
  AGrid.MouseToCell(MousePos.X, MousePos.Y, ACol, ARow);
  if (ARow < 1) or (ARow - 1 > High(ADeps)) then
    Exit;

  Dep := ADeps[ARow - 1];
  if not TryResolveDependencyObjectKind(FProfile.DatabaseType, Dep.ObjectType, Kind) then
  begin
    lblStatus.Caption := Format('Objeto "%s" (%s) não possui editor direto.', [Dep.ObjectName, Dep.ObjectType]);
    Exit;
  end;

  if (Kind = sokTables) and SameText(Dep.ObjectName, FTableName) then
  begin
    lblStatus.Caption := Format('A tabela "%s" já está aberta nesta aba.', [FTableName]);
    Exit;
  end;

  FOnOpenDependency(FProfile, Kind, Dep.ObjectName);
end;

function TTableEditorFrame.SelectedColumnIndex: Integer;
begin
  Result := grdFields.Row - 1;
  if (FStructure = nil) or (Result < 0) or (Result >= Length(FStructure.Columns)) then
    Result := -1;
end;

function TTableEditorFrame.SelectedIndexPos: Integer;
begin
  Result := grdIndexes.Row - 1;
  if (FStructure = nil) or (Result < 0) or (Result >= Length(FStructure.Indexes)) then
    Result := -1;
end;

procedure TTableEditorFrame.UpdateButtonsState;
var
  ColIdx, IdxPos: Integer;
  IdxInfo: TTableIndexInfo;
  CanAlterIdx: Boolean;
begin
  ColIdx := SelectedColumnIndex;
  btnEditField.Enabled := (ColIdx >= 0) and (not FStructure.Columns[ColIdx].IsComputed);
  btnDropField.Enabled := ColIdx >= 0;
  btnFieldDeps.Enabled := ColIdx >= 0;

  IdxPos := SelectedIndexPos;
  btnToggleIndexActive.Visible := (FProfile <> nil) and (FProfile.DatabaseType = dtFirebird);
  if IdxPos >= 0 then
  begin
    IdxInfo := FStructure.Indexes[IdxPos];
    CanAlterIdx := (not IdxInfo.IsPrimaryKey) and (not IdxInfo.IsForeignKey);
    btnDropIndex.Enabled := CanAlterIdx;
    btnToggleIndexActive.Enabled := (FProfile <> nil) and (FProfile.DatabaseType = dtFirebird) and CanAlterIdx;
    if IdxInfo.IsActive then
      btnToggleIndexActive.Caption := 'Inativar Índice'
    else
      btnToggleIndexActive.Caption := 'Ativar Índice';
  end
  else
  begin
    btnDropIndex.Enabled := False;
    btnToggleIndexActive.Enabled := False;
    btnToggleIndexActive.Caption := 'Ativar / Inativar';
  end;
end;

function TTableEditorFrame.ShowColumnDialog(const AIsEdit: Boolean; const AExisting: TTableColumnInfo): Boolean;
const
  FirebirdTypes: array[0..15] of string = (
    'INTEGER', 'BIGINT', 'SMALLINT', 'VARCHAR(50)', 'VARCHAR(100)', 'VARCHAR(255)',
    'CHAR(1)', 'NUMERIC(15,2)', 'DECIMAL(15,2)', 'DOUBLE PRECISION',
    'DATE', 'TIME', 'TIMESTAMP', 'BOOLEAN', 'BLOB SUB_TYPE TEXT', 'BLOB SUB_TYPE BINARY'
  );
  PostgresTypes: array[0..16] of string = (
    'integer', 'bigint', 'smallint', 'varchar(50)', 'varchar(100)', 'varchar(255)',
    'text', 'numeric(15,2)', 'double precision', 'boolean',
    'date', 'time', 'timestamp', 'timestamptz', 'uuid', 'jsonb', 'bytea'
  );
var
  Helper: TColumnDialogHelper;
  PnlInputs, PnlBtns: TPanel;
  FormDlg: TForm;
  OwnerForm: TCustomForm;
  LblName, LblType, LblDefault, LblPreview: TLabel;
  BtnCancel: TButton;
  I: Integer;
begin
  Result := False;
  OwnerForm := Forms.GetParentForm(Self);
  FormDlg := TForm.Create(OwnerForm);
  Helper := TColumnDialogHelper.Create;
  try
    FormDlg.BorderStyle := bsSizeable;
    FormDlg.BorderIcons := [biSystemMenu];
    if OwnerForm <> nil then
      FormDlg.Position := poOwnerFormCenter
    else
      FormDlg.Position := poScreenCenter;
    FormDlg.Width := 540;
    FormDlg.Height := 430;
    FormDlg.Constraints.MinWidth := 420;
    FormDlg.Constraints.MinHeight := 360;
    if AIsEdit then
      FormDlg.Caption := Format('Editar Campo: %s.%s', [FTableName, AExisting.ColumnName])
    else
      FormDlg.Caption := Format('Adicionar Campo em %s', [FTableName]);

    Helper.Dlg := FormDlg;
    Helper.Profile := FProfile;
    Helper.TableName := FTableName;
    Helper.UseCase := FUseCase;
    Helper.IsEdit := AIsEdit;
    Helper.OldCol := AExisting;

    PnlInputs := TPanel.Create(FormDlg);
    PnlInputs.Parent := FormDlg;
    PnlInputs.Align := alTop;
    PnlInputs.AutoSize := True;
    PnlInputs.BevelOuter := bvNone;
    PnlInputs.BorderSpacing.Around := 12;

    LblName := TLabel.Create(FormDlg);
    LblName.Parent := PnlInputs;
    LblName.Align := alTop;
    LblName.Caption := 'Nome do Campo:';

    Helper.EdtName := TEdit.Create(FormDlg);
    Helper.EdtName.Parent := PnlInputs;
    Helper.EdtName.Align := alTop;
    Helper.EdtName.BorderSpacing.Top := 3;
    Helper.EdtName.BorderSpacing.Bottom := 8;

    LblType := TLabel.Create(FormDlg);
    LblType.Parent := PnlInputs;
    LblType.Align := alTop;
    LblType.Caption := 'Tipo de Dados:';

    Helper.CbType := TComboBox.Create(FormDlg);
    Helper.CbType.Parent := PnlInputs;
    Helper.CbType.Align := alTop;
    Helper.CbType.Style := csDropDown;
    Helper.CbType.BorderSpacing.Top := 3;
    Helper.CbType.BorderSpacing.Bottom := 8;
    if FProfile.DatabaseType = dtPostgreSQL then
    begin
      for I := Low(PostgresTypes) to High(PostgresTypes) do
        Helper.CbType.Items.Add(PostgresTypes[I]);
    end
    else
    begin
      for I := Low(FirebirdTypes) to High(FirebirdTypes) do
        Helper.CbType.Items.Add(FirebirdTypes[I]);
    end;

    LblDefault := TLabel.Create(FormDlg);
    LblDefault.Parent := PnlInputs;
    LblDefault.Align := alTop;
    LblDefault.Caption := 'Valor Padrão (ex.: 0, '''', CURRENT_TIMESTAMP):';

    Helper.EdtDefault := TEdit.Create(FormDlg);
    Helper.EdtDefault.Parent := PnlInputs;
    Helper.EdtDefault.Align := alTop;
    Helper.EdtDefault.BorderSpacing.Top := 3;
    Helper.EdtDefault.BorderSpacing.Bottom := 8;

    Helper.ChkNotNull := TCheckBox.Create(FormDlg);
    Helper.ChkNotNull.Parent := PnlInputs;
    Helper.ChkNotNull.Align := alTop;
    Helper.ChkNotNull.Caption := 'NOT NULL (Obrigatório)';
    Helper.ChkNotNull.BorderSpacing.Bottom := 8;

    LblPreview := TLabel.Create(FormDlg);
    LblPreview.Parent := PnlInputs;
    LblPreview.Align := alTop;
    LblPreview.Caption := 'Prévia do DDL:';
    LblPreview.Font.Style := [fsBold];

    Helper.MemPreview := TMemo.Create(FormDlg);
    Helper.MemPreview.Parent := FormDlg;
    Helper.MemPreview.Align := alClient;
    Helper.MemPreview.BorderSpacing.Left := 12;
    Helper.MemPreview.BorderSpacing.Right := 12;
    Helper.MemPreview.ReadOnly := True;
    Helper.MemPreview.ScrollBars := ssBoth;
    {$IFDEF UNIX}
    Helper.MemPreview.Font.Name := 'Monospace';
    {$ELSE}
    Helper.MemPreview.Font.Name := 'Consolas';
    {$ENDIF}

    PnlBtns := TPanel.Create(FormDlg);
    PnlBtns.Parent := FormDlg;
    PnlBtns.Align := alBottom;
    PnlBtns.AutoSize := True;
    PnlBtns.BevelOuter := bvNone;
    PnlBtns.BorderSpacing.Around := 12;

    BtnCancel := TButton.Create(FormDlg);
    BtnCancel.Parent := PnlBtns;
    BtnCancel.Align := alRight;
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Caption := 'Cancelar';
    BtnCancel.Constraints.MinWidth := 95;
    BtnCancel.Constraints.MinHeight := 30;
    BtnCancel.BorderSpacing.Left := 8;

    Helper.BtnExecute := TButton.Create(FormDlg);
    Helper.BtnExecute.Parent := PnlBtns;
    Helper.BtnExecute.Align := alRight;
    Helper.BtnExecute.Default := True;
    Helper.BtnExecute.Caption := 'Executar';
    Helper.BtnExecute.Constraints.MinWidth := 110;
    Helper.BtnExecute.Constraints.MinHeight := 30;
    Helper.BtnExecute.OnClick := @Helper.ExecuteClicked;

    if AIsEdit then
    begin
      Helper.EdtName.Text := AExisting.ColumnName;
      Helper.CbType.Text := AExisting.DataType;
      Helper.EdtDefault.Text := AExisting.DefaultValue;
      Helper.ChkNotNull.Checked := AExisting.NotNull;
    end
    else
    begin
      if FProfile.DatabaseType = dtPostgreSQL then
        Helper.CbType.Text := 'varchar(100)'
      else
        Helper.CbType.Text := 'VARCHAR(100)';
      Helper.ChkNotNull.Checked := False;
    end;

    Helper.EdtName.OnChange := @Helper.InputChanged;
    Helper.CbType.OnChange := @Helper.InputChanged;
    Helper.EdtDefault.OnChange := @Helper.InputChanged;
    Helper.ChkNotNull.OnClick := @Helper.InputChanged;
    Helper.InputChanged(nil);

    Result := FormDlg.ShowModal = mrOk;
  finally
    Helper.Free;
    FormDlg.Free;
  end;
end;

function TTableEditorFrame.ShowCreateIndexDialog: Boolean;
var
  FormDlg: TForm;
  OwnerForm: TCustomForm;
  Helper: TIndexDialogHelper;
  PnlTop, PnlLists, PnlLeft, PnlMidBtns, PnlRight, PnlOpts, PnlBtns: TPanel;
  LblIdxName, LblAvail, LblSel, LblPreview: TLabel;
  BtnCancel: TButton;
  I: Integer;
begin
  Result := False;
  if FStructure = nil then
    Exit;

  OwnerForm := Forms.GetParentForm(Self);
  FormDlg := TForm.Create(OwnerForm);
  Helper := TIndexDialogHelper.Create;
  Helper.AllColsOrder := TStringList.Create;
  try
    FormDlg.BorderStyle := bsSizeable;
    FormDlg.BorderIcons := [biSystemMenu];
    if OwnerForm <> nil then
      FormDlg.Position := poOwnerFormCenter
    else
      FormDlg.Position := poScreenCenter;
    FormDlg.Width := 620;
    FormDlg.Height := 510;
    FormDlg.Constraints.MinWidth := 500;
    FormDlg.Constraints.MinHeight := 420;
    FormDlg.Caption := Format('Novo Índice em %s', [FTableName]);

    Helper.Dlg := FormDlg;
    Helper.Profile := FProfile;
    Helper.TableName := FTableName;
    Helper.UseCase := FUseCase;
    Helper.UserEditedName := False;

    PnlTop := TPanel.Create(FormDlg);
    PnlTop.Parent := FormDlg;
    PnlTop.Align := alTop;
    PnlTop.AutoSize := True;
    PnlTop.BevelOuter := bvNone;
    PnlTop.BorderSpacing.Around := 12;

    LblIdxName := TLabel.Create(FormDlg);
    LblIdxName.Parent := PnlTop;
    LblIdxName.Align := alTop;
    LblIdxName.Caption := 'Nome do Índice:';

    Helper.EdtIndexName := TEdit.Create(FormDlg);
    Helper.EdtIndexName.Parent := PnlTop;
    Helper.EdtIndexName.Align := alTop;
    Helper.EdtIndexName.BorderSpacing.Top := 3;

    PnlLists := TPanel.Create(FormDlg);
    PnlLists.Parent := FormDlg;
    PnlLists.Align := alTop;
    PnlLists.Height := 185;
    PnlLists.BevelOuter := bvNone;
    PnlLists.BorderSpacing.Left := 12;
    PnlLists.BorderSpacing.Right := 12;

    PnlLeft := TPanel.Create(FormDlg);
    PnlLeft.Parent := PnlLists;
    PnlLeft.Align := alLeft;
    PnlLeft.Width := 210;
    PnlLeft.BevelOuter := bvNone;

    LblAvail := TLabel.Create(FormDlg);
    LblAvail.Parent := PnlLeft;
    LblAvail.Align := alTop;
    LblAvail.Caption := 'Colunas Disponíveis:';

    Helper.LstAvailable := TListBox.Create(FormDlg);
    Helper.LstAvailable.Parent := PnlLeft;
    Helper.LstAvailable.Align := alClient;
    Helper.LstAvailable.BorderSpacing.Top := 3;

    PnlMidBtns := TPanel.Create(FormDlg);
    PnlMidBtns.Parent := PnlLists;
    PnlMidBtns.Align := alLeft;
    PnlMidBtns.Width := 130;
    PnlMidBtns.BevelOuter := bvNone;
    PnlMidBtns.BorderSpacing.Left := 8;
    PnlMidBtns.BorderSpacing.Right := 8;

    Helper.BtnAddCol := TButton.Create(FormDlg);
    Helper.BtnAddCol.Parent := PnlMidBtns;
    Helper.BtnAddCol.Align := alTop;
    Helper.BtnAddCol.Top := 24;
    Helper.BtnAddCol.BorderSpacing.Top := 22;
    Helper.BtnAddCol.Caption := 'Adicionar >>';
    Helper.BtnAddCol.Constraints.MinHeight := 28;
    Helper.BtnAddCol.OnClick := @Helper.AddColClicked;

    Helper.BtnRemoveCol := TButton.Create(FormDlg);
    Helper.BtnRemoveCol.Parent := PnlMidBtns;
    Helper.BtnRemoveCol.Align := alTop;
    Helper.BtnRemoveCol.BorderSpacing.Top := 6;
    Helper.BtnRemoveCol.Caption := '<< Remover';
    Helper.BtnRemoveCol.Constraints.MinHeight := 28;
    Helper.BtnRemoveCol.OnClick := @Helper.RemoveColClicked;

    Helper.BtnMoveUp := TButton.Create(FormDlg);
    Helper.BtnMoveUp.Parent := PnlMidBtns;
    Helper.BtnMoveUp.Align := alTop;
    Helper.BtnMoveUp.BorderSpacing.Top := 12;
    Helper.BtnMoveUp.Caption := 'Subir';
    Helper.BtnMoveUp.Constraints.MinHeight := 28;
    Helper.BtnMoveUp.OnClick := @Helper.MoveUpClicked;

    Helper.BtnMoveDown := TButton.Create(FormDlg);
    Helper.BtnMoveDown.Parent := PnlMidBtns;
    Helper.BtnMoveDown.Align := alTop;
    Helper.BtnMoveDown.BorderSpacing.Top := 6;
    Helper.BtnMoveDown.Caption := 'Descer';
    Helper.BtnMoveDown.Constraints.MinHeight := 28;
    Helper.BtnMoveDown.OnClick := @Helper.MoveDownClicked;

    PnlRight := TPanel.Create(FormDlg);
    PnlRight.Parent := PnlLists;
    PnlRight.Align := alClient;
    PnlRight.BevelOuter := bvNone;

    LblSel := TLabel.Create(FormDlg);
    LblSel.Parent := PnlRight;
    LblSel.Align := alTop;
    LblSel.Caption := 'Colunas do Índice (em ordem):';

    Helper.LstSelected := TListBox.Create(FormDlg);
    Helper.LstSelected.Parent := PnlRight;
    Helper.LstSelected.Align := alClient;
    Helper.LstSelected.BorderSpacing.Top := 3;

    PnlOpts := TPanel.Create(FormDlg);
    PnlOpts.Parent := FormDlg;
    PnlOpts.Align := alTop;
    PnlOpts.AutoSize := True;
    PnlOpts.BevelOuter := bvNone;
    PnlOpts.BorderSpacing.Left := 12;
    PnlOpts.BorderSpacing.Top := 10;
    PnlOpts.BorderSpacing.Right := 12;

    Helper.ChkUnique := TCheckBox.Create(FormDlg);
    Helper.ChkUnique.Parent := PnlOpts;
    Helper.ChkUnique.Align := alLeft;
    Helper.ChkUnique.Caption := 'Índice Único (UNIQUE)';
    Helper.ChkUnique.BorderSpacing.Right := 16;

    Helper.ChkDescending := TCheckBox.Create(FormDlg);
    Helper.ChkDescending.Parent := PnlOpts;
    Helper.ChkDescending.Align := alLeft;
    Helper.ChkDescending.Caption := 'Descendente (DESC)';

    LblPreview := TLabel.Create(FormDlg);
    LblPreview.Parent := FormDlg;
    LblPreview.Align := alTop;
    LblPreview.Caption := 'Prévia do DDL:';
    LblPreview.Font.Style := [fsBold];
    LblPreview.BorderSpacing.Left := 12;
    LblPreview.BorderSpacing.Top := 8;
    LblPreview.BorderSpacing.Bottom := 4;

    Helper.MemPreview := TMemo.Create(FormDlg);
    Helper.MemPreview.Parent := FormDlg;
    Helper.MemPreview.Align := alClient;
    Helper.MemPreview.BorderSpacing.Left := 12;
    Helper.MemPreview.BorderSpacing.Right := 12;
    Helper.MemPreview.ReadOnly := True;
    Helper.MemPreview.ScrollBars := ssBoth;
    {$IFDEF UNIX}
    Helper.MemPreview.Font.Name := 'Monospace';
    {$ELSE}
    Helper.MemPreview.Font.Name := 'Consolas';
    {$ENDIF}

    PnlBtns := TPanel.Create(FormDlg);
    PnlBtns.Parent := FormDlg;
    PnlBtns.Align := alBottom;
    PnlBtns.AutoSize := True;
    PnlBtns.BevelOuter := bvNone;
    PnlBtns.BorderSpacing.Around := 12;

    BtnCancel := TButton.Create(FormDlg);
    BtnCancel.Parent := PnlBtns;
    BtnCancel.Align := alRight;
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Caption := 'Cancelar';
    BtnCancel.Constraints.MinWidth := 95;
    BtnCancel.Constraints.MinHeight := 30;
    BtnCancel.BorderSpacing.Left := 8;

    Helper.BtnCreate := TButton.Create(FormDlg);
    Helper.BtnCreate.Parent := PnlBtns;
    Helper.BtnCreate.Align := alRight;
    Helper.BtnCreate.Default := True;
    Helper.BtnCreate.Caption := 'Criar Índice';
    Helper.BtnCreate.Constraints.MinWidth := 115;
    Helper.BtnCreate.Constraints.MinHeight := 30;
    Helper.BtnCreate.OnClick := @Helper.CreateClicked;

    for I := 0 to High(FStructure.Columns) do
    begin
      if not FStructure.Columns[I].IsComputed then
      begin
        Helper.AllColsOrder.Add(FStructure.Columns[I].ColumnName);
        Helper.LstAvailable.Items.Add(FStructure.Columns[I].ColumnName);
      end;
    end;
    if Helper.LstAvailable.Items.Count > 0 then
      Helper.LstAvailable.ItemIndex := 0;

    Helper.EdtIndexName.OnKeyPress := @Helper.IndexNameKeyPress;
    Helper.EdtIndexName.OnChange := @Helper.InputChanged;
    Helper.LstAvailable.OnClick := @Helper.InputChanged;
    Helper.LstAvailable.OnDblClick := @Helper.AddColClicked;
    Helper.LstSelected.OnClick := @Helper.InputChanged;
    Helper.LstSelected.OnDblClick := @Helper.RemoveColClicked;
    Helper.ChkUnique.OnClick := @Helper.InputChanged;
    Helper.ChkDescending.OnClick := @Helper.InputChanged;

    Helper.UpdateSuggestedIndexName;
    Helper.UpdateControlsAndPreview;

    Result := FormDlg.ShowModal = mrOk;
  finally
    Helper.AllColsOrder.Free;
    Helper.Free;
    FormDlg.Free;
  end;
end;

function TTableEditorFrame.SelectedDataLimit: Integer;
begin
  case cbDataLimit.ItemIndex of
    0: Result := 100;
    1: Result := 500;
    2: Result := 1000;
    3: Result := 5000;
  else
    Result := 0;
  end;
end;

function TTableEditorFrame.BuildDataSelectSQL: string;
var
  CleanWhere, LowerWhere: string;
  LimitVal: Integer;
begin
  Result := '';
  if FProfile = nil then
    Exit;

  CleanWhere := Trim(edtDataWhere.Text);
  LowerWhere := LowerCase(CleanWhere);
  if (Pos('where', LowerWhere) = 1) and ((Length(LowerWhere) = 5) or (LowerWhere[6] <= ' ')) then
    CleanWhere := Trim(Copy(CleanWhere, 6, MaxInt));
  while (CleanWhere <> '') and (CleanWhere[Length(CleanWhere)] = ';') do
    CleanWhere := TrimRight(Copy(CleanWhere, 1, Length(CleanWhere) - 1));

  LimitVal := SelectedDataLimit;
  if FProfile.DatabaseType = dtPostgreSQL then
  begin
    Result := 'SELECT * FROM ' + QuoteDbIdent(dtPostgreSQL, FTableName);
    if CleanWhere <> '' then
      Result := Result + ' WHERE ' + CleanWhere;
    if LimitVal > 0 then
      Result := Result + ' LIMIT ' + IntToStr(LimitVal);
  end
  else
  begin
    if LimitVal > 0 then
      Result := Format('SELECT FIRST %d * FROM %s', [LimitVal, QuoteDbIdent(dtFirebird, FTableName)])
    else
      Result := 'SELECT * FROM ' + QuoteDbIdent(dtFirebird, FTableName);
    if CleanWhere <> '' then
      Result := Result + ' WHERE ' + CleanWhere;
  end;
end;

procedure TTableEditorFrame.LoadTableDataGrid;
var
  ExecutedSQL: string;
  Res: TQueryResult;
begin
  if (FUseCase = nil) or (FProfile = nil) then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    if FDataGrid <> nil then
      FDataGrid.SetResult(nil, False, False);
    FreeAndNil(FLastDataResult);

    try
      Res := FUseCase.LoadTableData(
        FProfile,
        FTableName,
        edtDataWhere.Text,
        SelectedDataLimit,
        ExecutedSQL
      );
      FLastDataResult := Res;
      FDataLoaded := True;

      if FLastDataResult = nil then
      begin
        if FDataGrid <> nil then
          FDataGrid.SetResult(nil, True, False);
        lblStatus.Caption := 'Nenhum resultado retornado.';
      end
      else if not FLastDataResult.Success then
      begin
        if FDataGrid <> nil then
        begin
          FDataGrid.SetResult(nil, True, False);
          FDataGrid.SetCustomSummary('Erro: ' + FLastDataResult.MessageText);
        end;
        lblStatus.Caption := 'Erro ao carregar dados: ' + FLastDataResult.MessageText;
        MessageDlg('Erro ao carregar dados da tabela', FLastDataResult.MessageText, mtError, [mbOK], 0);
      end
      else
      begin
        if FDataGrid <> nil then
          FDataGrid.SetResult(FLastDataResult, True, True);
        if FLastDataResult.SystemMemoryLow then
        begin
          lblStatus.Caption := Format('Proteção RAM do SO em "%s": %d registro(s) mantidos.', [
            FTableName, FLastDataResult.RowCount
          ]);
          MessageDlg('Proteção de Memória RAM do Sistema', FLastDataResult.LimitMessage, mtWarning, [mbOK], 0);
        end
        else
          lblStatus.Caption := Format('Dados de "%s": %d registro(s) (%d ms).', [
            FTableName, FLastDataResult.RowCount, FLastDataResult.ExecutionTimeMs
          ]);
      end;
    except
      on E: Exception do
      begin
        FDataLoaded := True;
        if FDataGrid <> nil then
        begin
          FDataGrid.SetResult(nil, True, False);
          FDataGrid.SetCustomSummary('Erro: ' + E.Message);
        end;
        lblStatus.Caption := 'Erro ao carregar dados: ' + E.Message;
        MessageDlg('Erro ao carregar dados da tabela', E.Message, mtError, [mbOK], 0);
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TTableEditorFrame.btnRefreshClick(Sender: TObject);
begin
  if not ConfirmDiscardTriggerChanges then
    Exit;

  LoadAndDisplayStructure(FCurrentTriggerName);
  if (pgTable.ActivePage = tsData) and FDataLoaded then
    LoadTableDataGrid;
end;

procedure TTableEditorFrame.btnViewDataClick(Sender: TObject);
begin
  pgTable.ActivePage := tsData;
  LoadTableDataGrid;
end;

procedure TTableEditorFrame.btnOpenInSqlClick(Sender: TObject);
begin
  if (FProfile <> nil) and Assigned(FOnOpenSqlScript) then
    FOnOpenSqlScript(FProfile, FTableName, 'SELECT * FROM ' + QuoteDbIdent(FProfile.DatabaseType, FTableName));
end;

procedure TTableEditorFrame.pgTableChange(Sender: TObject);
begin
  if (pgTable.ActivePage = tsData) and (not FDataLoaded) then
    LoadTableDataGrid;
end;

procedure TTableEditorFrame.btnAddFieldClick(Sender: TObject);
var
  DummyCol: TTableColumnInfo;
begin
  FillChar(DummyCol, SizeOf(DummyCol), 0);
  if ShowColumnDialog(False, DummyCol) then
  begin
    ClearMetadataCache;
    LoadAndDisplayStructure(FCurrentTriggerName);
    if Assigned(FOnStructureChanged) and (FProfile <> nil) then
      FOnStructureChanged(FProfile.Id);
  end;
end;

procedure TTableEditorFrame.btnEditFieldClick(Sender: TObject);
var
  ColIdx: Integer;
begin
  ColIdx := SelectedColumnIndex;
  if ColIdx < 0 then
    Exit;

  if FStructure.Columns[ColIdx].IsComputed then
  begin
    MessageDlg('Aviso', 'Campos calculados (COMPUTED BY) não podem ser editados diretamente nesta tela.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if ShowColumnDialog(True, FStructure.Columns[ColIdx]) then
  begin
    ClearMetadataCache;
    LoadAndDisplayStructure(FCurrentTriggerName);
    if Assigned(FOnStructureChanged) and (FProfile <> nil) then
      FOnStructureChanged(FProfile.Id);
  end;
end;

procedure TTableEditorFrame.btnDropFieldClick(Sender: TObject);
var
  ColIdx: Integer;
  ColName, Msg: string;
begin
  ColIdx := SelectedColumnIndex;
  if ColIdx < 0 then
    Exit;

  ColName := FStructure.Columns[ColIdx].ColumnName;
  if MessageDlg(
       'Confirmar Exclusão',
       Format('Deseja excluir permanentemente o campo "%s" da tabela "%s"?', [ColName, FTableName]),
       mtConfirmation,
       [mbYes, mbNo],
       0
     ) <> mrYes then
    Exit;

  if FUseCase.DropColumn(FProfile, FTableName, ColName, Msg) then
  begin
    ClearMetadataCache;
    LoadAndDisplayStructure(FCurrentTriggerName);
    lblStatus.Caption := Msg;
    if Assigned(FOnStructureChanged) and (FProfile <> nil) then
      FOnStructureChanged(FProfile.Id);
  end
  else
    MessageDlg('Erro ao excluir campo', Msg, mtError, [mbOK], 0);
end;

procedure TTableEditorFrame.btnFieldDepsClick(Sender: TObject);
var
  ColIdx, I: Integer;
  ColName: string;
begin
  ColIdx := SelectedColumnIndex;
  if ColIdx < 0 then
    Exit;

  ColName := FStructure.Columns[ColIdx].ColumnName;
  for I := 1 to cbDepField.Items.Count - 1 do
  begin
    if SameText(cbDepField.Items[I], ColName) then
    begin
      cbDepField.ItemIndex := I;
      Break;
    end;
  end;
  pgTable.ActivePage := tsDependencies;
  RefreshDependenciesDisplay;
end;

procedure TTableEditorFrame.pmFieldsPopup(Sender: TObject);
var
  ColIdx: Integer;
begin
  ColIdx := SelectedColumnIndex;
  miFieldDeps.Enabled := ColIdx >= 0;
  miFieldEdit.Enabled := (ColIdx >= 0) and (not FStructure.Columns[ColIdx].IsComputed);
  miFieldDrop.Enabled := ColIdx >= 0;
end;

procedure TTableEditorFrame.grdFieldsDblClick(Sender: TObject);
begin
  btnEditFieldClick(Sender);
end;

procedure TTableEditorFrame.grdFieldsSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateButtonsState;
end;

procedure TTableEditorFrame.grdFKDblClick(Sender: TObject);
var
  MousePos: TPoint;
  ACol, ARow: Integer;
  RefTable: string;
begin
  if (FStructure = nil) or (FProfile = nil) or (not Assigned(FOnOpenDependency)) then
    Exit;

  MousePos := grdFK.ScreenToClient(Mouse.CursorPos);
  grdFK.MouseToCell(MousePos.X, MousePos.Y, ACol, ARow);
  if (ARow < 1) or (ARow - 1 > High(FStructure.ForeignKeys)) then
    Exit;

  RefTable := Trim(FStructure.ForeignKeys[ARow - 1].RefTable);
  if RefTable = '' then
    Exit;
  if SameText(RefTable, FTableName) then
  begin
    lblStatus.Caption := Format('A tabela "%s" (autorreferência) já está aberta nesta aba.', [FTableName]);
    Exit;
  end;

  FOnOpenDependency(FProfile, sokTables, RefTable);
end;

procedure TTableEditorFrame.btnAddIndexClick(Sender: TObject);
begin
  if ShowCreateIndexDialog then
  begin
    LoadAndDisplayStructure(FCurrentTriggerName);
    if Assigned(FOnStructureChanged) and (FProfile <> nil) then
      FOnStructureChanged(FProfile.Id);
  end;
end;

procedure TTableEditorFrame.btnToggleIndexActiveClick(Sender: TObject);
var
  IdxPos: Integer;
  IdxInfo: TTableIndexInfo;
  TargetActive: Boolean;
  Msg: string;
begin
  IdxPos := SelectedIndexPos;
  if (IdxPos < 0) or (FProfile = nil) or (FProfile.DatabaseType <> dtFirebird) then
    Exit;

  IdxInfo := FStructure.Indexes[IdxPos];
  if IdxInfo.IsPrimaryKey or IdxInfo.IsForeignKey then
    Exit;

  TargetActive := not IdxInfo.IsActive;
  if FUseCase.SetIndexActive(FProfile, IdxInfo.IndexName, TargetActive, Msg) then
  begin
    LoadAndDisplayStructure(FCurrentTriggerName);
    lblStatus.Caption := Msg;
    if Assigned(FOnStructureChanged) and (FProfile <> nil) then
      FOnStructureChanged(FProfile.Id);
  end
  else
    MessageDlg('Erro ao alterar status do índice', Msg, mtError, [mbOK], 0);
end;

procedure TTableEditorFrame.btnDropIndexClick(Sender: TObject);
var
  IdxPos: Integer;
  IdxInfo: TTableIndexInfo;
  Msg: string;
begin
  IdxPos := SelectedIndexPos;
  if IdxPos < 0 then
    Exit;

  IdxInfo := FStructure.Indexes[IdxPos];
  if IdxInfo.IsPrimaryKey or IdxInfo.IsForeignKey then
  begin
    MessageDlg('Aviso', 'Índices de Primary Key ou Foreign Key são gerenciados pela constraint correspondente.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if MessageDlg(
       'Confirmar Exclusão',
       Format('Deseja excluir permanentemente o índice "%s"?', [IdxInfo.IndexName]),
       mtConfirmation,
       [mbYes, mbNo],
       0
     ) <> mrYes then
    Exit;

  if FUseCase.DropIndex(FProfile, IdxInfo.IndexName, Msg) then
  begin
    LoadAndDisplayStructure(FCurrentTriggerName);
    lblStatus.Caption := Msg;
    if Assigned(FOnStructureChanged) and (FProfile <> nil) then
      FOnStructureChanged(FProfile.Id);
  end
  else
    MessageDlg('Erro ao excluir índice', Msg, mtError, [mbOK], 0);
end;

procedure TTableEditorFrame.grdIndexesSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateButtonsState;
end;

procedure TTableEditorFrame.btnNewTriggerClick(Sender: TObject);
var
  Timing: string;
  HasIns, HasUpd, HasDel: Boolean;
begin
  CategoryCodeToDefaults(SelectedTreeCategoryCode, Timing, HasIns, HasUpd, HasDel);
  StartNewTrigger(Timing, HasIns, HasUpd, HasDel);
end;

procedure TTableEditorFrame.btnToggleTriggerActiveClick(Sender: TObject);
var
  TrigIdx: Integer;
  Trig: TTableTriggerInfo;
  TargetActive: Boolean;
  Msg: string;
begin
  TrigIdx := SelectedTriggerIndex;
  if (TrigIdx < 0) or (FUseCase = nil) or (FProfile = nil) then
    Exit;

  if FTriggerDirty and (not ConfirmDiscardTriggerChanges) then
    Exit;

  Trig := FStructure.Triggers[TrigIdx];
  TargetActive := not Trig.IsActive;
  Screen.Cursor := crHourGlass;
  try
    if FUseCase.SetTriggerActive(FProfile, FTableName, Trig.TriggerName, TargetActive, Msg) then
    begin
      FTriggerDirty := False;
      LogTriggerMessage('SUCESSO: ' + Msg);
      LoadAndDisplayStructure(Trig.TriggerName);
      lblStatus.Caption := Msg;
      if Assigned(FOnTriggersChanged) then
        FOnTriggersChanged(FProfile.Id);
    end
    else
      LogTriggerMessage('ERRO: ' + Msg);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TTableEditorFrame.btnDropTriggerClick(Sender: TObject);
var
  TrigIdx: Integer;
  TrigName, Msg: string;
begin
  TrigIdx := SelectedTriggerIndex;
  if (TrigIdx < 0) or (FUseCase = nil) or (FProfile = nil) then
    Exit;

  TrigName := FStructure.Triggers[TrigIdx].TriggerName;
  if MessageDlg(
       'Confirmar Exclusão',
       Format('Deseja realmente excluir a trigger "%s" da tabela "%s"?', [TrigName, FTableName]),
       mtConfirmation,
       [mbYes, mbNo],
       0
     ) <> mrYes then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    if FUseCase.DropTableTrigger(FProfile, FTableName, TrigName, Msg) then
    begin
      FTriggerDirty := False;
      FCurrentTriggerName := '';
      FTriggerIsNew := False;
      LogTriggerMessage('SUCESSO: ' + Msg);
      LoadAndDisplayStructure('');
      lblStatus.Caption := Msg;
      if Assigned(FOnTriggersChanged) then
        FOnTriggersChanged(FProfile.Id);
    end
    else
      LogTriggerMessage('ERRO AO EXCLUIR: ' + Msg);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TTableEditorFrame.btnCompileTriggerClick(Sender: TObject);
var
  TargetName, OriginalName, Msg: string;
begin
  if (FUseCase = nil) or (FProfile = nil) then
    Exit;
  if (not FTriggerIsNew) and (FCurrentTriggerName = '') then
    Exit;

  OriginalName := FCurrentTriggerName;
  TargetName := Trim(edtTriggerName.Text);
  if (TargetName = '') and (not FTriggerIsNew) then
    TargetName := FCurrentTriggerName;

  Screen.Cursor := crHourGlass;
  try
    if FUseCase.SaveTableTrigger(
         FProfile,
         FTableName,
         OriginalName,
         TargetName,
         cbTriggerTiming.Text,
         chkTrigInsert.Checked,
         chkTrigUpdate.Checked,
         chkTrigDelete.Checked,
         chkTriggerActive.Checked,
         spnTriggerPos.Value,
         SynEditTrigger.Lines.Text,
         FTriggerIsNew,
         Msg
       ) then
    begin
      FTriggerDirty := False;
      FTriggerIsNew := False;
      LogTriggerMessage('SUCESSO: ' + Msg);
      if (FProfile.DatabaseType = dtPostgreSQL) and (OriginalName <> '') then
        LoadAndDisplayStructure(OriginalName)
      else
        LoadAndDisplayStructure(TargetName);
      lblStatus.Caption := Msg;
      if Assigned(FOnTriggersChanged) then
        FOnTriggersChanged(FProfile.Id);
    end
    else
      LogTriggerMessage('ERRO AO COMPILAR: ' + Msg);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TTableEditorFrame.btnReloadTriggerClick(Sender: TObject);
var
  KeepName: string;
begin
  if FCurrentTriggerName = '' then
    Exit;
  if not ConfirmDiscardTriggerChanges then
    Exit;

  KeepName := FCurrentTriggerName;
  FTriggerDirty := False;
  LoadAndDisplayStructure(KeepName);
  LogTriggerMessage(Format('Trigger "%s" recarregada do banco de dados.', [KeepName]));
end;

procedure TTableEditorFrame.btnCopyTriggerDDLClick(Sender: TObject);
var
  DDL: string;
begin
  if (FProfile <> nil) and (FProfile.DatabaseType = dtFirebird) and
     (not StartsWithAnyTriggerDDL(SynEditTrigger.Lines.Text)) then
    DDL := BuildFirebirdTriggerDDL(
      FTableName,
      edtTriggerName.Text,
      cbTriggerTiming.Text,
      chkTrigInsert.Checked,
      chkTrigUpdate.Checked,
      chkTrigDelete.Checked,
      chkTriggerActive.Checked,
      spnTriggerPos.Value,
      SynEditTrigger.Lines.Text
    )
  else
    DDL := SynEditTrigger.Lines.Text;

  Clipboard.AsText := DDL;
  LogTriggerMessage('DDL da trigger copiado para a área de transferência.');
end;

procedure TTableEditorFrame.btnOpenTriggerFunctionClick(Sender: TObject);
var
  TrigIdx: Integer;
  FuncName: string;
begin
  TrigIdx := SelectedTriggerIndex;
  if (TrigIdx < 0) or (FProfile = nil) or (not Assigned(FOnOpenDependency)) then
    Exit;

  FuncName := Trim(FStructure.Triggers[TrigIdx].FunctionName);
  if FuncName <> '' then
    FOnOpenDependency(FProfile, sokProcedures, FuncName);
end;

procedure TTableEditorFrame.btnOpenTriggerInTabClick(Sender: TObject);
begin
  if (FProfile <> nil) and (FCurrentTriggerName <> '') and Assigned(FOnOpenDependency) then
    FOnOpenDependency(FProfile, sokTriggers, FCurrentTriggerName);
end;

procedure TTableEditorFrame.pnlTriggerToolbarResize(Sender: TObject);
begin
  if (not FUpdatingTriggerToolbarSize) and (pnlTriggerToolbar.Width <> FLastTriggerToolbarWidth) then
    UpdateTriggerToolbarLayout;
end;

procedure TTableEditorFrame.tvTriggersChanging(Sender: TObject; Node: TTreeNode; var AllowChange: Boolean);
begin
  if FLoadingTrigger then
    Exit;
  if FTriggerDirty and (not ConfirmDiscardTriggerChanges) then
    AllowChange := False;
end;

procedure TTableEditorFrame.tvTriggersChange(Sender: TObject; Node: TTreeNode);
begin
  if FLoadingTrigger then
    Exit;

  if SelectedTriggerIndex >= 0 then
    LoadSelectedTriggerIntoEditor
  else
    ClearTriggerEditorPlaceholder;
end;

procedure TTableEditorFrame.tvTriggersCustomDrawItem(
  Sender: TCustomTreeView;
  Node: TTreeNode;
  State: TCustomDrawState;
  var DefaultDraw: Boolean
);
var
  DataVal: PtrUInt;
  Idx: Integer;
begin
  DefaultDraw := True;
  if (Node = nil) or (Sender = nil) then
    Exit;

  DataVal := PtrUInt(Node.Data);
  if (DataVal >= 1) and (DataVal <= 7) then
  begin
    if Node.HasChildren then
      Sender.Canvas.Font.Style := [fsBold]
    else
      Sender.Canvas.Font.Style := [];
  end
  else if (DataVal >= TRIG_NODE_DATA_BASE) and (FStructure <> nil) and
          (DataVal - TRIG_NODE_DATA_BASE <= PtrUInt(High(FStructure.Triggers))) then
  begin
    Idx := Integer(DataVal - TRIG_NODE_DATA_BASE);
    if not FStructure.Triggers[Idx].IsActive then
    begin
      Sender.Canvas.Font.Style := [fsItalic];
      if not (cdsSelected in State) then
        Sender.Canvas.Font.Color := clGrayText;
    end
    else
      Sender.Canvas.Font.Style := [];
  end;
end;

procedure TTableEditorFrame.tvTriggersDblClick(Sender: TObject);
var
  Node: TTreeNode;
  DataVal: PtrUInt;
  Timing: string;
  HasIns, HasUpd, HasDel: Boolean;
begin
  Node := tvTriggers.Selected;
  if Node = nil then
    Exit;

  DataVal := PtrUInt(Node.Data);
  if (DataVal >= 1) and (DataVal <= 7) then
  begin
    CategoryCodeToDefaults(Integer(DataVal), Timing, HasIns, HasUpd, HasDel);
    StartNewTrigger(Timing, HasIns, HasUpd, HasDel);
  end;
end;

procedure TTableEditorFrame.tvTriggersMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  HitNode: TTreeNode;
begin
  if Button = mbRight then
  begin
    HitNode := tvTriggers.GetNodeAt(X, Y);
    if HitNode <> nil then
      tvTriggers.Selected := HitNode;
  end;
end;

procedure TTableEditorFrame.pmTriggersPopup(Sender: TObject);
var
  HasTrig: Boolean;
  TrigIdx: Integer;
begin
  TrigIdx := SelectedTriggerIndex;
  HasTrig := TrigIdx >= 0;
  miTrigNewInCategory.Enabled := True;
  miTrigToggleActive.Enabled := HasTrig;
  if HasTrig and FStructure.Triggers[TrigIdx].IsActive then
    miTrigToggleActive.Caption := 'Inativar Trigger'
  else
    miTrigToggleActive.Caption := 'Ativar Trigger';
  miTrigOpenTab.Enabled := HasTrig;
  miTrigDrop.Enabled := HasTrig;
end;

procedure TTableEditorFrame.TriggerMetaChanged(Sender: TObject);
begin
  if FLoadingTrigger then
    Exit;
  if (not FTriggerIsNew) and (FCurrentTriggerName = '') then
    Exit;

  FTriggerDirty := True;
  UpdateTriggerHeaderPreview;
  UpdateTriggerEditorControlsState;
end;

procedure TTableEditorFrame.SynEditTriggerChange(Sender: TObject);
begin
  if FLoadingTrigger then
    Exit;
  if (not FTriggerIsNew) and (FCurrentTriggerName = '') then
    Exit;

  FTriggerDirty := True;
  UpdateTriggerHeaderPreview;
  UpdateTriggerEditorControlsState;
end;

procedure TTableEditorFrame.SynEditTriggerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F9) and (Shift = []) then
  begin
    if btnCompileTrigger.Enabled then
    begin
      Key := 0;
      btnCompileTriggerClick(Sender);
    end;
  end
  else if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    if btnCompileTrigger.Enabled then
    begin
      Key := 0;
      btnCompileTriggerClick(Sender);
    end;
  end;
end;

procedure TTableEditorFrame.btnRefreshDataClick(Sender: TObject);
begin
  LoadTableDataGrid;
end;

procedure TTableEditorFrame.cbDataLimitChange(Sender: TObject);
begin
  if (pgTable.ActivePage = tsData) or FDataLoaded then
    LoadTableDataGrid;
end;

procedure TTableEditorFrame.edtDataWhereKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    LoadTableDataGrid;
  end;
end;

procedure TTableEditorFrame.btnOpenDataInSqlClick(Sender: TObject);
begin
  if (FProfile <> nil) and Assigned(FOnOpenSqlScript) then
    FOnOpenSqlScript(FProfile, FTableName, BuildDataSelectSQL);
end;

procedure TTableEditorFrame.cbDepFieldChange(Sender: TObject);
begin
  RefreshDependenciesDisplay;
end;

procedure TTableEditorFrame.grdDepUsedByDblClick(Sender: TObject);
begin
  OpenDependencyFromGrid(grdDepUsedBy, FUsedByDeps);
end;

procedure TTableEditorFrame.grdDepUsesDblClick(Sender: TObject);
begin
  OpenDependencyFromGrid(grdDepUses, FUsesDeps);
end;

procedure TTableEditorFrame.btnCopyTableDDLClick(Sender: TObject);
begin
  Clipboard.AsText := SynEditDDL.Lines.Text;
  lblStatus.Caption := 'DDL da tabela copiado para a área de transferência.';
end;

procedure TTableEditorFrame.btnOpenDDLInSqlClick(Sender: TObject);
begin
  if (FProfile <> nil) and Assigned(FOnOpenSqlScript) then
    FOnOpenSqlScript(FProfile, 'DDL: ' + FTableName, SynEditDDL.Lines.Text);
end;

procedure TTableEditorFrame.chkIncludeTriggersDDLClick(Sender: TObject);
begin
  RefreshDDLPreview;
end;

end.
