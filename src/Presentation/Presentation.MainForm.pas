unit Presentation.MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Generics.Collections, Forms, Controls, Graphics, Dialogs,
  ComCtrls, ExtCtrls, StdCtrls, Menus, LCLType, LMessages, SynEdit,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Domain.QueryHistory,
  Infrastructure.JsonQueryHistoryRepository,
  Presentation.QueryHistoryForm,
  Presentation.ReplicationForm,
  Application.TestConnectionUseCase,
  Application.ManageConnectionsUseCase,
  Application.ExecuteQueryUseCase,
  Application.BrowseSchemaUseCase,
  Application.ManageDatabaseObjectsUseCase,
  Application.DatabaseMonitoringUseCase,
  Application.ManageTableStructureUseCase,
  Infrastructure.ProviderFactory,
  Infrastructure.JsonConnectionRepository,
  Infrastructure.JsonWorkspaceRepository,
  Infrastructure.FirebirdSqlDbProvider,
  Infrastructure.MormotPostgresProvider,
  Infrastructure.MariaDbSqlDbProvider,
  Presentation.ConnectionForm,
  Presentation.SqlEditorFrame,
  Presentation.ObjectEditorFrame,
  Presentation.GeneratorForm,
  Presentation.DatabaseMonitorFrame,
  Presentation.TableEditorFrame,
  Domain.MaintenanceTypes,
  Presentation.DatabaseComparerFrame,
  Presentation.DatabaseMaintenanceForm,
  Presentation.ScriptExecutorFrame,
  Presentation.SqlBeautifierHelper,
  Presentation.DatabaseToolsForm,
  Presentation.DataImportForm;

type
  TExplorerNodeKind = (enkGroup, enkFolder, enkConnection, enkDatabase, enkCategory, enkObject);

  TExplorerNodeData = class
  public
    Kind: TExplorerNodeKind;
    DatabaseType: TDatabaseType;
    FolderName: string;
    Profile: TConnectionProfile;
    Category: TSchemaObjectKind;
    ObjectName: string;
    Loaded: Boolean;
    TotalCount: Integer;
  end;

  TExplorerNodeDataList = specialize TObjectList<TExplorerNodeData>;

  TProfileSessionSummary = record
    ActiveCount: Integer;
    BusyCount: Integer;
    InTransactionCount: Integer;
  end;

  { TMainForm }
  TMainForm = class(TForm)
    pnlLeft: TPanel;
    pnlConnActions: TPanel;
    btnNewConn: TButton;
    btnEditConn: TButton;
    btnDeleteConn: TButton;
    pnlConnOrder: TPanel;
    btnMoveConnUp: TButton;
    btnMoveConnDown: TButton;
    btnSortConns: TButton;
    pnlMain: TPanel;
    pnlEditorBar: TPanel;
    btnToggleSidebar: TButton;
    btnNewTab: TButton;
    btnMonitorDb: TButton;
    btnCompareDb: TButton;
    btnScriptExec: TButton;
    Splitter1: TSplitter;
    lblConnections: TLabel;
    pnlTreeFilter: TPanel;
    edtTreeFilter: TEdit;
    btnClearFilter: TButton;
    tvConnections: TTreeView;
    pgEditors: TPageControl;
    StatusBar1: TStatusBar;
    pmConnections: TPopupMenu;
    miOpenSqlTab: TMenuItem;
    miScriptExec: TMenuItem;
    miMonitorDb: TMenuItem;
    miCompareDb: TMenuItem;
    miMaintenanceDb: TMenuItem;
    miSepObj: TMenuItem;
    miEditObject: TMenuItem;
    miViewObjectDDL: TMenuItem;
    miViewObjectData: TMenuItem;
    miNewObject: TMenuItem;
    miRefreshCategory: TMenuItem;
    miDropObject: TMenuItem;
    miSep1: TMenuItem;
    miDisconnectConn: TMenuItem;
    miEditConn: TMenuItem;
    miDuplicateConn: TMenuItem;
    miDeleteConn: TMenuItem;
    miSep2: TMenuItem;
    miMoveConnUp: TMenuItem;
    miMoveConnDown: TMenuItem;
    miSortAsc: TMenuItem;
    miSortDesc: TMenuItem;
    MainMenu1: TMainMenu;
    miFileMenu: TMenuItem;
    miMenuNewTab: TMenuItem;
    miMenuNewScript: TMenuItem;
    miMenuCloseTab: TMenuItem;
    miMenuFileSep: TMenuItem;
    miMenuExit: TMenuItem;
    miConnMenu: TMenuItem;
    miMenuNewConn: TMenuItem;
    miMenuEditConn: TMenuItem;
    miMenuDeleteConn: TMenuItem;
    miToolsMenu: TMenuItem;
    miMenuScriptExec: TMenuItem;
    miMenuCompareDb: TMenuItem;
    miMenuMonitorDb: TMenuItem;
    miMenuToolsSep: TMenuItem;
    miMenuBackupDb: TMenuItem;
    miMenuRestoreDb: TMenuItem;
    miMenuRepairDb: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure btnNewConnClick(Sender: TObject);
    procedure btnEditConnClick(Sender: TObject);
    procedure btnDeleteConnClick(Sender: TObject);
    procedure btnMoveConnUpClick(Sender: TObject);
    procedure btnMoveConnDownClick(Sender: TObject);
    procedure btnSortConnsClick(Sender: TObject);
    procedure btnToggleSidebarClick(Sender: TObject);
    procedure btnNewTabClick(Sender: TObject);
    procedure btnCloseTabClick(Sender: TObject);
    procedure pgEditorsCloseTabClicked(Sender: TObject);
    procedure pgEditorsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure btnMonitorDbClick(Sender: TObject);
    procedure btnCompareDbClick(Sender: TObject);
    procedure btnScriptExecClick(Sender: TObject);
    procedure edtTreeFilterChange(Sender: TObject);
    procedure btnClearFilterClick(Sender: TObject);
    procedure tvConnectionsChange(Sender: TObject; Node: TTreeNode);
    procedure tvConnectionsDblClick(Sender: TObject);
    procedure tvConnectionsExpanding(Sender: TObject; Node: TTreeNode;
      var AllowExpansion: Boolean);
    procedure tvConnectionsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure tvConnectionsDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure tvConnectionsDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure tvConnectionsKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure pmConnectionsPopup(Sender: TObject);
    procedure miOpenSqlTabClick(Sender: TObject);
    procedure miScriptExecClick(Sender: TObject);
    procedure miMonitorDbClick(Sender: TObject);
    procedure miCompareDbClick(Sender: TObject);
    procedure miMaintenanceDbClick(Sender: TObject);
    procedure miEditObjectClick(Sender: TObject);
    procedure miViewObjectDDLClick(Sender: TObject);
    procedure miViewObjectDataClick(Sender: TObject);
    procedure miNewObjectClick(Sender: TObject);
    procedure miRefreshCategoryClick(Sender: TObject);
    procedure miDropObjectClick(Sender: TObject);
    procedure miDisconnectConnClick(Sender: TObject);
    procedure miDuplicateConnClick(Sender: TObject);
    procedure miSortAscClick(Sender: TObject);
    procedure miSortDescClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure miToolBackupClick(Sender: TObject);
    procedure miToolRestoreClick(Sender: TObject);
    procedure miToolRepairClick(Sender: TObject);
    procedure miToolQueryHistoryClick(Sender: TObject);
    procedure miToolReplicationClick(Sender: TObject);
    procedure miToolAboutClick(Sender: TObject);
    procedure miSelectSchemaClick(Sender: TObject);
    procedure FormShortCut(var Msg: TLMKey; var Handled: Boolean);
    procedure tvConnectionsCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
      State: TCustomDrawState; var DefaultDraw: Boolean);
  private
    FFactory: IDatabaseProviderFactory;
    FRepository: IConnectionRepository;
    FWorkspaceRepo: TJsonWorkspaceRepository;
    FManageConnections: TManageConnectionsUseCase;
    FTestConnection: TTestConnectionUseCase;
    FExecuteQuery: TExecuteQueryUseCase;
    FBrowseSchema: TBrowseSchemaUseCase;
    FManageObjects: TManageDatabaseObjectsUseCase;
    FMonitorUseCase: TDatabaseMonitoringUseCase;
    FManageTableStructure: TManageTableStructureUseCase;
    FConnections: TConnectionProfileList;
    FDatabaseProfiles: TConnectionProfileList;
    FQueryHistory: IQueryHistoryService;
    FNodeDataList: TExplorerNodeDataList;
    FTabCounter: Integer;
    FNextSortAsc: Boolean;
    FLastLeftPanelWidth: Integer;
    miSelectSchema: TMenuItem;
    miToolQueryHistory: TMenuItem;
    miToolReplication: TMenuItem;
    miToolMetadataSearch: TMenuItem;
    miToolIndexManager: TMenuItem;
    miToolImportData: TMenuItem;
    miToolDocs: TMenuItem;
    miConnMetadataSearch: TMenuItem;
    miConnIndexManager: TMenuItem;
    miConnImportData: TMenuItem;
    miToolAbout: TMenuItem;
    pnlBrandHeader: TPanel;
    btnNewFolder: TButton;
    miNewFolder: TMenuItem;
    miNewConnInFolder: TMenuItem;
    miRenameFolder: TMenuItem;
    miDeleteFolder: TMenuItem;
    miMoveToFolder: TMenuItem;
    miMenuNewFolder: TMenuItem;
    procedure miToolMetadataSearchClick(Sender: TObject);
    procedure miToolIndexManagerClick(Sender: TObject);
    procedure miToolImportDataClick(Sender: TObject);
    procedure miToolDocsClick(Sender: TObject);
    procedure miNewFolderClick(Sender: TObject);
    procedure miNewConnInFolderClick(Sender: TObject);
    procedure miRenameFolderClick(Sender: TObject);
    procedure miDeleteFolderClick(Sender: TObject);
    procedure miMoveToFolderClick(Sender: TObject);
    procedure ApplyVisualTheme;
    procedure HandleOpenSqlFromHistory(const AProfileId, ASqlText: string);
    procedure InitializeDependencies;
    procedure RefreshConnectionsTree(
      const ASelectProfileId: string = '';
      const ASelectFolderName: string = ''
    );
    procedure UpdateFolderCaptions;
    function SelectedFolderNode: TTreeNode;
    procedure ApplyTreeFilter;
    procedure RefreshOpenTabsConnections;
    procedure RestoreWorkspace;
    procedure SaveWorkspace;
    procedure UpdateConnectionButtonsState;
    procedure PersistCurrentTreeOrder;
    procedure MoveSelectedConnection(const ADelta: Integer);
    procedure SortConnections(const AAscending: Boolean);
    procedure SetSidebarVisible(const AVisible: Boolean);
    function FindCategoryNode(const AProfileId: string; const AKind: TSchemaObjectKind): TTreeNode;
    procedure ReloadCategoryNode(const ACategoryNode: TTreeNode);
    procedure ReloadCategoryForProfile(const AProfileId: string; const AKind: TSchemaObjectKind);
    procedure HandleObjectChanged(const AProfileId: string; const AKind: TSchemaObjectKind);
    procedure HandleOpenViewData(const AProfileId, AViewName: string);
    procedure HandleOpenSqlFromTool(const AProfileId, ATitle, ASqlText: string);
    procedure HandleOpenTableSqlScript(const AProfile: TConnectionProfile; const ATitle, ASqlText: string);
    function OpenNewEditorTab(const AInitialProfileId: string = ''; const ACaption: string = ''; const AOverrideProfile: TConnectionProfile = nil): TSqlEditorFrame;
    function FindEditorTabIndex(const ATab: TTabSheet): Integer;
    procedure CloseEditorTab(const ATab: TTabSheet);
    procedure HandleDeferredCloseTab(Data: PtrInt);
    function FindSqlEditorFrame(const ATab: TTabSheet): TSqlEditorFrame;
    function FindComparerFrame(const ATab: TTabSheet): TDatabaseComparerFrame;
    function FindScriptExecutorFrame(const ATab: TTabSheet): TScriptExecutorFrame;
    function FindMonitorFrame(const ATab: TTabSheet): TDatabaseMonitorFrame;
    function FindTableEditorFrame(const ATab: TTabSheet): TTableEditorFrame;
    function GetProfileSessionSummary(const AProfileId: string): TProfileSessionSummary;
    function DisconnectProfileSessions(const AProfileId: string): Integer;
    function CountExecutingTabs: Integer;
    function CountBusyComparerTabs: Integer;
    function CountBusyScriptTabs: Integer;
    function CountDirtyTableTriggerTabs: Integer;
    procedure HandleEditorExecutionStateChanged(
      Sender: TObject;
      const ARunning: Boolean;
      const AStatusText: string
    );
    procedure OpenObjectEditorTab(
      const AProfile: TConnectionProfile;
      const AKind: TSchemaObjectKind;
      const AObjectName: string;
      const AIsNew: Boolean
    );
    procedure OpenTableEditorTab(const AProfile: TConnectionProfile; const ATableName: string);
    procedure HandleTableStructureChanged(const AProfileId: string);
    procedure HandleTableTriggersChanged(const AProfileId: string);
    procedure HandleOpenTableDependency(
      const AProfile: TConnectionProfile;
      const AKind: TSchemaObjectKind;
      const AObjectName: string
    );
    procedure OpenMonitorTab(const AInitialProfileId: string = '');
    procedure OpenComparerTab(const AInitialSourceId: string = '');
    procedure OpenScriptExecutorTab(const AInitialProfileId: string = ''; const AInitialScript: string = '');
    procedure OpenMaintenanceDialog(const AInitialTab: TMaintenanceTabKind; const AInitialProfileId: string = '');
    function CreateNodeData(
      const AKind: TExplorerNodeKind;
      const AProfile: TConnectionProfile = nil;
      const ACategory: TSchemaObjectKind = sokTables;
      const AObjectName: string = '';
      const ADbType: TDatabaseType = dtFirebird;
      const AFolderName: string = ''
    ): TExplorerNodeData;
    function SelectedNodeData: TExplorerNodeData;
    function SelectedConnectionNode: TTreeNode;
    function FindAdjacentVisibleSibling(const ANode: TTreeNode; const ADelta: Integer): TTreeNode;
    function SelectedProfile: TConnectionProfile;
  public
  end;

var
  MainForm: TMainForm;

implementation

uses
  Presentation.TabHelpers;

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'Multi-DB SQL Editor (Firebird, PostgreSQL & MariaDB)';
  try
    Forms.Application.Icon.LoadFromResourceName(HInstance, 'MAINICON');
    Icon.Assign(Forms.Application.Icon);
  except
  end;
  FTabCounter := 0;
  FNextSortAsc := True;
  FLastLeftPanelWidth := pnlLeft.Width;
  FNodeDataList := TExplorerNodeDataList.Create(True);
  FDatabaseProfiles := TConnectionProfileList.Create(True);
  InitializeDependencies;
  RefreshConnectionsTree;
  RestoreWorkspace;
  UpdateConnectionButtonsState;
  miMenuScriptExec.ShortCut := Menus.ShortCut(VK_F12, [ssCtrl]);
  miSelectSchema := TMenuItem.Create(pmConnections);
  miSelectSchema.Caption := 'Selecionar Schema...';
  miSelectSchema.OnClick := @miSelectSchemaClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miEditConn), miSelectSchema);

  if miMenuScriptExec.Parent <> nil then
  begin
    miToolQueryHistory := TMenuItem.Create(Self);
    miToolQueryHistory.Caption := 'Histórico de Execução...';
    miToolQueryHistory.OnClick := @miToolQueryHistoryClick;
    miMenuScriptExec.Parent.Add(miToolQueryHistory);

    miToolReplication := TMenuItem.Create(Self);
    miToolReplication.Caption := 'Configurar Replicação (PostgreSQL / Firebird 5)...';
    miToolReplication.OnClick := @miToolReplicationClick;
    miMenuScriptExec.Parent.Add(miToolReplication);

    miToolMetadataSearch := TMenuItem.Create(Self);
    miToolMetadataSearch.Caption := 'Buscar nos Metadados / Código-Fonte...';
    miToolMetadataSearch.ShortCut := Menus.ShortCut(VK_F, [ssCtrl, ssShift]);
    miToolMetadataSearch.OnClick := @miToolMetadataSearchClick;
    miMenuScriptExec.Parent.Add(miToolMetadataSearch);

    miToolIndexManager := TMenuItem.Create(Self);
    miToolIndexManager.Caption := 'Gerenciador de Índices e Estatísticas...';
    miToolIndexManager.OnClick := @miToolIndexManagerClick;
    miMenuScriptExec.Parent.Add(miToolIndexManager);

    miToolImportData := TMenuItem.Create(Self);
    miToolImportData.Caption := 'Importar Dados (Excel / CSV / TXT -> Tabela)...';
    miToolImportData.OnClick := @miToolImportDataClick;
    miMenuScriptExec.Parent.Add(miToolImportData);

    miToolDocs := TMenuItem.Create(Self);
    miToolDocs.Caption := 'Documentação e Funcionalidades (F1)...';
    miToolDocs.ShortCut := Menus.ShortCut(VK_F1, []);
    miToolDocs.OnClick := @miToolDocsClick;
    miMenuScriptExec.Parent.Add(miToolDocs);

    miToolAbout := TMenuItem.Create(Self);
    miToolAbout.Caption := 'Sobre o Multi-DB SQL Editor...';
    miToolAbout.OnClick := @miToolAboutClick;
    miMenuScriptExec.Parent.Add(miToolAbout);
  end;

  miConnMetadataSearch := TMenuItem.Create(pmConnections);
  miConnMetadataSearch.Caption := 'Buscar nos Metadados (Ctrl+Shift+F)...';
  miConnMetadataSearch.OnClick := @miToolMetadataSearchClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miCompareDb) + 1, miConnMetadataSearch);

  miConnIndexManager := TMenuItem.Create(pmConnections);
  miConnIndexManager.Caption := 'Gerenciador de Índices e Estatísticas...';
  miConnIndexManager.OnClick := @miToolIndexManagerClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miConnMetadataSearch) + 1, miConnIndexManager);

  miConnImportData := TMenuItem.Create(pmConnections);
  miConnImportData.Caption := 'Importar Dados (Excel / CSV / TXT)...';
  miConnImportData.OnClick := @miToolImportDataClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miConnIndexManager) + 1, miConnImportData);

  if pnlConnOrder <> nil then
  begin
    pnlConnOrder.ChildSizing.ControlsPerLine := 4;
    btnNewFolder := TButton.Create(Self);
    btnNewFolder.Parent := pnlConnOrder;
    btnNewFolder.Caption := '+ Pasta';
    btnNewFolder.Hint := 'Criar nova pasta para organizar conexões';
    btnNewFolder.ParentShowHint := False;
    btnNewFolder.ShowHint := True;
    btnNewFolder.AutoSize := True;
    btnNewFolder.Constraints.MinHeight := 26;
    btnNewFolder.OnClick := @miNewFolderClick;
  end;

  if miMenuNewConn.Parent <> nil then
  begin
    miMenuNewFolder := TMenuItem.Create(Self);
    miMenuNewFolder.Caption := 'Nova Pasta...';
    miMenuNewFolder.OnClick := @miNewFolderClick;
    miMenuNewConn.Parent.Insert(miMenuNewConn.Parent.IndexOf(miMenuNewConn) + 1, miMenuNewFolder);
  end;

  miNewFolder := TMenuItem.Create(pmConnections);
  miNewFolder.Caption := 'Nova Pasta...';
  miNewFolder.OnClick := @miNewFolderClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miEditConn), miNewFolder);

  miNewConnInFolder := TMenuItem.Create(pmConnections);
  miNewConnInFolder.Caption := 'Nova Conexão nesta Pasta...';
  miNewConnInFolder.OnClick := @miNewConnInFolderClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miNewFolder) + 1, miNewConnInFolder);

  miRenameFolder := TMenuItem.Create(pmConnections);
  miRenameFolder.Caption := 'Renomear Pasta...';
  miRenameFolder.OnClick := @miRenameFolderClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miNewConnInFolder) + 1, miRenameFolder);

  miDeleteFolder := TMenuItem.Create(pmConnections);
  miDeleteFolder.Caption := 'Excluir Pasta';
  miDeleteFolder.OnClick := @miDeleteFolderClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miRenameFolder) + 1, miDeleteFolder);

  miMoveToFolder := TMenuItem.Create(pmConnections);
  miMoveToFolder.Caption := 'Mover para Pasta...';
  miMoveToFolder.OnClick := @miMoveToFolderClick;
  pmConnections.Items.Insert(pmConnections.Items.IndexOf(miEditConn) + 1, miMoveToFolder);

  OnShortCut := @FormShortCut;
  ApplyVisualTheme;
  StatusBar1.SimpleText := 'Pronto (F9 executa | Alt+F formata SQL | Ctrl+F12 Script Executive | Ctrl+Espaço autocompleta)';
end;

procedure TMainForm.FormShortCut(var Msg: TLMKey; var Handled: Boolean);
begin
  if (Msg.CharCode = Ord('F')) and (KeyDataToShiftState(Msg.KeyData) = [ssAlt]) then
  begin
    if (ActiveControl is TSynEdit) and (not TSynEdit(ActiveControl).ReadOnly) then
    begin
      FormatSynEditSql(TSynEdit(ActiveControl));
      Handled := True;
    end;
  end
  else if (Msg.CharCode = Ord('F')) and (KeyDataToShiftState(Msg.KeyData) = [ssCtrl, ssShift]) then
  begin
    miToolMetadataSearchClick(nil);
    Handled := True;
  end
  else if (Msg.CharCode = VK_F1) and (KeyDataToShiftState(Msg.KeyData) = []) then
  begin
    miToolDocsClick(nil);
    Handled := True;
  end;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  RunningCount, BusyCompCount, BusyScriptCount, TotalBusy, DirtyTriggerCount, I: Integer;
  Frame: TSqlEditorFrame;
  CompFrame: TDatabaseComparerFrame;
  ScriptFrame: TScriptExecutorFrame;
  Deadline: QWord;
begin
  RunningCount := CountExecutingTabs;
  BusyCompCount := CountBusyComparerTabs;
  BusyScriptCount := CountBusyScriptTabs;
  TotalBusy := RunningCount + BusyCompCount + BusyScriptCount;
  DirtyTriggerCount := CountDirtyTableTriggerTabs;

  if TotalBusy > 0 then
  begin
    if MessageDlg(
         'Operações em Segundo Plano',
         Format('Há %d operação(ões) em execução em segundo plano (consultas / scripts / comparação). Deseja cancelar e encerrar a aplicação?', [TotalBusy]),
         mtConfirmation,
         [mbYes, mbNo],
         0
       ) <> mrYes then
    begin
      CanClose := False;
      Exit;
    end;
  end;

  if DirtyTriggerCount > 0 then
  begin
    if MessageDlg(
         'Triggers com Alterações Não Compiladas',
         Format('Há %d aba(s) de tabela com alterações não compiladas em triggers. Deseja descartar as alterações e encerrar a aplicação?', [DirtyTriggerCount]),
         mtConfirmation,
         [mbYes, mbNo],
         0
       ) <> mrYes then
    begin
      CanClose := False;
      Exit;
    end;
  end;

  if TotalBusy <= 0 then
    Exit;

  for I := 0 to pgEditors.PageCount - 1 do
  begin
    Frame := FindSqlEditorFrame(pgEditors.Pages[I]);
    if (Frame <> nil) and Frame.IsExecuting then
      Frame.RequestCancel;
    CompFrame := FindComparerFrame(pgEditors.Pages[I]);
    if (CompFrame <> nil) and CompFrame.IsBusy then
      CompFrame.DetachAndCancel;
    ScriptFrame := FindScriptExecutorFrame(pgEditors.Pages[I]);
    if (ScriptFrame <> nil) and ScriptFrame.IsBusy then
      ScriptFrame.DetachAndCancel;
  end;

  Deadline := GetTickCount64 + 2500;
  while ((CountExecutingTabs > 0) or (CountBusyComparerTabs > 0) or (CountBusyScriptTabs > 0)) and
        (GetTickCount64 < Deadline) do
  begin
    Forms.Application.ProcessMessages;
    Sleep(25);
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Forms.Application.RemoveAsyncCalls(Self);
  SaveWorkspace;
  FreeAndNil(FNodeDataList);
  FreeAndNil(FDatabaseProfiles);
  FreeAndNil(FWorkspaceRepo);
  FreeAndNil(FConnections);
  FreeAndNil(FManageTableStructure);
  FreeAndNil(FMonitorUseCase);
  FreeAndNil(FManageObjects);
  FreeAndNil(FBrowseSchema);
  FreeAndNil(FExecuteQuery);
  FreeAndNil(FTestConnection);
  FreeAndNil(FManageConnections);
end;

procedure TMainForm.InitializeDependencies;
var
  ConcreteFactory: TDatabaseProviderFactory;
begin
  ConcreteFactory := TDatabaseProviderFactory.Create;
  ConcreteFactory.RegisterProvider(TFirebirdSqlDbProvider.Create);
  ConcreteFactory.RegisterProvider(TMormotPostgresProvider.Create);
  ConcreteFactory.RegisterProvider(TMariaDbSqlDbProvider.Create);
  FFactory := ConcreteFactory;
  FQueryHistory := TJsonQueryHistoryService.Create;

  FRepository := TJsonConnectionRepository.Create;
  FWorkspaceRepo := TJsonWorkspaceRepository.Create;
  FManageConnections := TManageConnectionsUseCase.Create(FRepository);
  FTestConnection := TTestConnectionUseCase.Create(FFactory);
  FExecuteQuery := TExecuteQueryUseCase.Create;
  FBrowseSchema := TBrowseSchemaUseCase.Create(FFactory);
  FManageObjects := TManageDatabaseObjectsUseCase.Create(FFactory);
  FMonitorUseCase := TDatabaseMonitoringUseCase.Create;
  FManageTableStructure := TManageTableStructureUseCase.Create(FFactory);
end;

function TMainForm.CreateNodeData(
  const AKind: TExplorerNodeKind;
  const AProfile: TConnectionProfile;
  const ACategory: TSchemaObjectKind;
  const AObjectName: string;
  const ADbType: TDatabaseType;
  const AFolderName: string
): TExplorerNodeData;
begin
  Result := TExplorerNodeData.Create;
  Result.Kind := AKind;
  Result.DatabaseType := ADbType;
  Result.FolderName := Trim(AFolderName);
  Result.Profile := AProfile;
  if (AProfile <> nil) and (AKind in [enkConnection, enkDatabase, enkCategory, enkObject]) then
    Result.DatabaseType := AProfile.DatabaseType;
  Result.Category := ACategory;
  Result.ObjectName := AObjectName;
  Result.Loaded := False;
  Result.TotalCount := 0;
  FNodeDataList.Add(Result);
end;

procedure TMainForm.UpdateFolderCaptions;
var
  Node: TTreeNode;
  Data: TExplorerNodeData;
begin
  Node := tvConnections.Items.GetFirstNode;
  while Node <> nil do
  begin
    if Node.Data <> nil then
    begin
      Data := TExplorerNodeData(Node.Data);
      if Data.Kind = enkFolder then
        Node.Text := Format('[Pasta] %s (%d)', [Data.FolderName, Node.Count]);
    end;
    Node := Node.GetNextSibling;
  end;
end;

procedure TMainForm.RefreshConnectionsTree(
  const ASelectProfileId: string;
  const ASelectFolderName: string
);
var
  ParentNode, FolderNode, ConnNode, SelectNode, Cur: TTreeNode;
  Profile: TConnectionProfile;
  FolderList: TStringList;
  I: Integer;
  FolderName, ConnCaption: string;

  function FindOrAddFolderNode(const AName: string): TTreeNode;
  var
    SearchNode: TTreeNode;
    D: TExplorerNodeData;
  begin
    SearchNode := tvConnections.Items.GetFirstNode;
    while SearchNode <> nil do
    begin
      if SearchNode.Data <> nil then
      begin
        D := TExplorerNodeData(SearchNode.Data);
        if (D.Kind = enkFolder) and SameText(D.FolderName, AName) then
          Exit(SearchNode);
      end;
      SearchNode := SearchNode.GetNextSibling;
    end;
    Result := tvConnections.Items.AddObject(
      nil,
      Format('[Pasta] %s (0)', [AName]),
      CreateNodeData(enkFolder, nil, sokTables, '', dtFirebird, AName)
    );
  end;

begin
  SelectNode := nil;
  FolderList := TStringList.Create;
  tvConnections.Items.BeginUpdate;
  try
    tvConnections.Items.Clear;
    FNodeDataList.Clear;
    if FDatabaseProfiles <> nil then
      FDatabaseProfiles.Clear;
    FreeAndNil(FConnections);
    FConnections := FManageConnections.ListAll;

    FManageConnections.GetFolders(FolderList);
    for I := 0 to FolderList.Count - 1 do
    begin
      FolderNode := FindOrAddFolderNode(FolderList[I]);
      if (ASelectProfileId = '') and (Trim(ASelectFolderName) <> '') and
         SameText(FolderList[I], Trim(ASelectFolderName)) then
        SelectNode := FolderNode;
    end;

    for Profile in FConnections do
    begin
      FolderName := Trim(Profile.Folder);
      if FolderName <> '' then
      begin
        FolderNode := FindOrAddFolderNode(FolderName);
        ParentNode := FolderNode;
      end
      else
        ParentNode := nil;

      if (Profile.DatabaseType = dtPostgreSQL) and (Trim(Profile.Database) = '') then
        ConnCaption := Format('%s [PG: servidor]', [Profile.Name])
      else if Profile.DatabaseType = dtPostgreSQL then
        ConnCaption := Format('%s [PG: %s]', [Profile.Name, Profile.EffectiveSchema])
      else if Profile.DatabaseType = dtMariaDB then
        ConnCaption := Format('%s [MariaDB]', [Profile.Name])
      else
        ConnCaption := Format('%s [FB]', [Profile.Name]);

      ConnNode := tvConnections.Items.AddChildObject(
        ParentNode,
        ConnCaption,
        CreateNodeData(enkConnection, Profile)
      );

      ConnNode.HasChildren := True;
      if (ASelectProfileId <> '') and SameText(Profile.Id, ASelectProfileId) then
        SelectNode := ConnNode;
    end;

    UpdateFolderCaptions;
    Cur := tvConnections.Items.GetFirstNode;
    while Cur <> nil do
    begin
      if (Cur.Data <> nil) and (TExplorerNodeData(Cur.Data).Kind = enkFolder) and (Cur.Count > 0) then
        Cur.Expand(False);
      Cur := Cur.GetNextSibling;
    end;
  finally
    tvConnections.Items.EndUpdate;
    FolderList.Free;
  end;

  ApplyTreeFilter;
  if (SelectNode <> nil) and SelectNode.Visible then
  begin
    tvConnections.Selected := SelectNode;
    SelectNode.MakeVisible;
  end;
  UpdateConnectionButtonsState;
  RefreshOpenTabsConnections;
end;

procedure TMainForm.ApplyTreeFilter;
var
  FilterText: string;

  function FilterNode(const ANode: TTreeNode; const AParentMatched: Boolean): Boolean;
  var
    Data: TExplorerNodeData;
    Child: TTreeNode;
    SelfMatches, AnyChildVisible: Boolean;
    VisibleChildrenCount: Integer;
  begin
    if (ANode = nil) or (ANode.Data = nil) then
    begin
      Result := True;
      Exit;
    end;

    Data := TExplorerNodeData(ANode.Data);
    if FilterText = '' then
    begin
      ANode.Visible := True;
      if Data.Kind = enkFolder then
        ANode.Text := Format('[Pasta] %s (%d)', [Data.FolderName, ANode.Count])
      else if (Data.Kind = enkCategory) and Data.Loaded then
        ANode.Text := Format('%s (%d)', [SchemaObjectKindToStr(Data.Category), Data.TotalCount]);
      Child := ANode.GetFirstChild;
      while Child <> nil do
      begin
        FilterNode(Child, False);
        Child := Child.GetNextSibling;
      end;
      Result := True;
      Exit;
    end;

    SelfMatches := False;
    case Data.Kind of
      enkGroup:
        SelfMatches := False;
      enkFolder:
        SelfMatches := Pos(FilterText, LowerCase(Data.FolderName)) > 0;
      enkConnection:
        SelfMatches := AParentMatched or (Pos(FilterText, LowerCase(Data.Profile.Name)) > 0);
      enkDatabase:
        SelfMatches := AParentMatched or (Pos(FilterText, LowerCase(Data.Profile.Database)) > 0);
      enkCategory:
        SelfMatches := AParentMatched or (Pos(FilterText, LowerCase(SchemaObjectKindToStr(Data.Category))) > 0);
      enkObject:
        SelfMatches := AParentMatched or (Pos(FilterText, LowerCase(Data.ObjectName)) > 0);
    end;

    AnyChildVisible := False;
    VisibleChildrenCount := 0;
    Child := ANode.GetFirstChild;
    while Child <> nil do
    begin
      if FilterNode(Child, SelfMatches) then
      begin
        AnyChildVisible := True;
        Inc(VisibleChildrenCount);
      end;
      Child := Child.GetNextSibling;
    end;

    if Data.Kind = enkCategory then
    begin
      if Data.Loaded then
      begin
        if SelfMatches and (not AnyChildVisible) and (VisibleChildrenCount = 0) then
          ANode.Text := Format('%s (%d)', [SchemaObjectKindToStr(Data.Category), Data.TotalCount])
        else
          ANode.Text := Format('%s (%d/%d)', [SchemaObjectKindToStr(Data.Category), VisibleChildrenCount, Data.TotalCount]);
      end;
      Result := SelfMatches or AnyChildVisible;
    end
    else if Data.Kind = enkGroup then
      Result := AnyChildVisible
    else
      Result := SelfMatches or AnyChildVisible;

    ANode.Visible := Result;
    if Result and AnyChildVisible then
      ANode.Expand(False);
  end;

var
  Root: TTreeNode;
begin
  FilterText := LowerCase(Trim(edtTreeFilter.Text));
  tvConnections.Items.BeginUpdate;
  try
    Root := tvConnections.Items.GetFirstNode;
    while Root <> nil do
    begin
      FilterNode(Root, False);
      Root := Root.GetNextSibling;
    end;
  finally
    tvConnections.Items.EndUpdate;
  end;
end;

procedure TMainForm.edtTreeFilterChange(Sender: TObject);
begin
  ApplyTreeFilter;
  UpdateConnectionButtonsState;
end;

procedure TMainForm.btnClearFilterClick(Sender: TObject);
begin
  edtTreeFilter.Text := '';
  edtTreeFilter.SetFocus;
end;

procedure TMainForm.RefreshOpenTabsConnections;
var
  I, J: Integer;
  Tab: TTabSheet;
begin
  for I := 0 to pgEditors.PageCount - 1 do
  begin
    Tab := pgEditors.Pages[I];
    for J := 0 to Tab.ControlCount - 1 do
    begin
      if Tab.Controls[J] is TSqlEditorFrame then
        TSqlEditorFrame(Tab.Controls[J]).RefreshConnections(FConnections)
      else if Tab.Controls[J] is TDatabaseMonitorFrame then
        TDatabaseMonitorFrame(Tab.Controls[J]).RefreshConnections(FConnections)
      else if Tab.Controls[J] is TDatabaseComparerFrame then
        TDatabaseComparerFrame(Tab.Controls[J]).RefreshConnections(FConnections)
      else if Tab.Controls[J] is TScriptExecutorFrame then
        TScriptExecutorFrame(Tab.Controls[J]).RefreshConnections(FConnections);
    end;
  end;
end;

function TMainForm.FindCategoryNode(const AProfileId: string; const AKind: TSchemaObjectKind): TTreeNode;

  function SearchInNode(const ANode: TTreeNode): TTreeNode;
  var
    Child: TTreeNode;
    Data: TExplorerNodeData;
  begin
    Result := nil;
    if (ANode = nil) or (ANode.Data = nil) then
      Exit;

    Data := TExplorerNodeData(ANode.Data);
    if (Data.Kind = enkCategory) and (Data.Category = AKind) and
       (Data.Profile <> nil) and SameText(Data.Profile.Id, AProfileId) then
      Exit(ANode);

    if Data.Kind in [enkGroup, enkFolder, enkConnection, enkDatabase] then
    begin
      Child := ANode.GetFirstChild;
      while Child <> nil do
      begin
        Result := SearchInNode(Child);
        if Result <> nil then
          Exit;
        Child := Child.GetNextSibling;
      end;
    end;
  end;

var
  GroupNode: TTreeNode;
begin
  Result := nil;
  GroupNode := tvConnections.Items.GetFirstNode;
  while GroupNode <> nil do
  begin
    Result := SearchInNode(GroupNode);
    if Result <> nil then
      Exit;
    GroupNode := GroupNode.GetNextSibling;
  end;
end;

function FormatExplorerObjectCaption(const AName: string; const ASizeTag: TObject): string;
var
  SizeBytes: Int64;
begin
  if PtrInt(ASizeTag) <= 0 then
    Exit(AName);
  SizeBytes := Int64(PtrInt(ASizeTag)) - 1;
  if SizeBytes < 1024 then
    Result := Format('%s (%d B)', [AName, SizeBytes])
  else if SizeBytes < 1024 * 1024 then
    Result := Format('%s (%.1f KB)', [AName, SizeBytes / 1024.0])
  else if SizeBytes < Int64(1024) * 1024 * 1024 then
    Result := Format('%s (%.1f MB)', [AName, SizeBytes / (1024.0 * 1024.0)])
  else
    Result := Format('%s (%.2f GB)', [AName, SizeBytes / (1024.0 * 1024.0 * 1024.0)]);
end;

procedure TMainForm.ReloadCategoryNode(const ACategoryNode: TTreeNode);
var
  Data: TExplorerNodeData;
  Objects: TStringList;
  I: Integer;
begin
  if (ACategoryNode = nil) or (ACategoryNode.Data = nil) then
    Exit;

  Data := TExplorerNodeData(ACategoryNode.Data);
  if (Data.Kind <> enkCategory) or (Data.Profile = nil) then
    Exit;

  Screen.Cursor := crHourGlass;
  tvConnections.Items.BeginUpdate;
  try
    try
      Objects := FBrowseSchema.ListObjects(Data.Profile, Data.Category);
      try
        ACategoryNode.DeleteChildren;
        for I := 0 to Objects.Count - 1 do
        begin
          tvConnections.Items.AddChildObject(
            ACategoryNode,
            FormatExplorerObjectCaption(Objects[I], Objects.Objects[I]),
            CreateNodeData(enkObject, Data.Profile, Data.Category, Objects[I])
          );
        end;
        ACategoryNode.Text := Format('%s (%d)', [SchemaObjectKindToStr(Data.Category), Objects.Count]);
        Data.TotalCount := Objects.Count;
        Data.Loaded := True;
        ACategoryNode.HasChildren := Objects.Count > 0;
        ACategoryNode.Expand(False);
      finally
        Objects.Free;
      end;
    except
      on E: Exception do
        MessageDlg('Erro ao recarregar metadados', E.Message, mtError, [mbOK], 0);
    end;
  finally
    tvConnections.Items.EndUpdate;
    Screen.Cursor := crDefault;
  end;

  if Trim(edtTreeFilter.Text) <> '' then
    ApplyTreeFilter;
  UpdateConnectionButtonsState;
end;

procedure TMainForm.ReloadCategoryForProfile(const AProfileId: string; const AKind: TSchemaObjectKind);
var
  CatNode: TTreeNode;
begin
  CatNode := FindCategoryNode(AProfileId, AKind);
  if (CatNode <> nil) and (CatNode.Data <> nil) and TExplorerNodeData(CatNode.Data).Loaded then
    ReloadCategoryNode(CatNode);
end;

procedure TMainForm.HandleObjectChanged(const AProfileId: string; const AKind: TSchemaObjectKind);
var
  I: Integer;
  TableFrame: TTableEditorFrame;
begin
  ReloadCategoryForProfile(AProfileId, AKind);
  if (AKind = sokTriggers) and (pgEditors <> nil) then
  begin
    for I := 0 to pgEditors.PageCount - 1 do
    begin
      TableFrame := FindTableEditorFrame(pgEditors.Pages[I]);
      if (TableFrame <> nil) and SameText(TableFrame.ProfileId, AProfileId) and
         (not TableFrame.HasUnsavedTriggerChanges) then
        TableFrame.RefreshAll;
    end;
  end;
  HandleTableStructureChanged(AProfileId);
end;

procedure TMainForm.HandleOpenViewData(const AProfileId, AViewName: string);
var
  Profile: TConnectionProfile;
  Frame: TSqlEditorFrame;
  Item: TConnectionProfile;
begin
  Profile := nil;
  if FConnections <> nil then
  begin
    for Item in FConnections do
    begin
      if SameText(Item.Id, AProfileId) then
      begin
        Profile := Item;
        Break;
      end;
    end;
  end;
  if Profile = nil then
    Exit;

  Frame := OpenNewEditorTab(Profile.Id, AViewName);
  Frame.SetSqlText('SELECT * FROM ' + QuoteDbIdent(Profile.DatabaseType, AViewName));
  Frame.ExecuteCurrentSQL;
end;

procedure TMainForm.HandleOpenSqlFromTool(const AProfileId, ATitle, ASqlText: string);
var
  Frame: TSqlEditorFrame;
begin
  Frame := OpenNewEditorTab(AProfileId, ATitle);
  Frame.SetSqlText(ASqlText);
end;

procedure TMainForm.HandleOpenTableSqlScript(const AProfile: TConnectionProfile; const ATitle, ASqlText: string);
var
  ProfileId: string;
begin
  if AProfile <> nil then
    ProfileId := AProfile.Id
  else
    ProfileId := '';
  HandleOpenSqlFromTool(ProfileId, ATitle, ASqlText);
end;

function TMainForm.OpenNewEditorTab(
  const AInitialProfileId: string;
  const ACaption: string;
  const AOverrideProfile: TConnectionProfile
): TSqlEditorFrame;
var
  Tab: TTabSheet;
begin
  Inc(FTabCounter);
  Tab := TTabSheet.Create(pgEditors);
  Tab.PageControl := pgEditors;
  if Trim(ACaption) <> '' then
    SetTabSheetTitle(Tab, ACaption)
  else
    SetTabSheetTitle(Tab, Format('SQL %d', [FTabCounter]));

  Result := TSqlEditorFrame.Create(Tab);
  Result.Name := Format('SqlEditorFrame_%d', [FTabCounter]);
  Result.Parent := Tab;
  Result.Align := alClient;
  Result.OnExecutionStateChanged := @HandleEditorExecutionStateChanged;
  Result.OnOpenObject := @HandleOpenTableDependency;
  Result.QueryHistory := FQueryHistory;
  Result.Initialize(FFactory, FExecuteQuery, FConnections, AInitialProfileId);
  if AOverrideProfile <> nil then
    Result.SelectOrAddProfile(AOverrideProfile);

  pgEditors.ActivePage := Tab;
end;

function TMainForm.FindSqlEditorFrame(const ATab: TTabSheet): TSqlEditorFrame;
var
  J: Integer;
begin
  Result := nil;
  if ATab = nil then
    Exit;
  for J := 0 to ATab.ControlCount - 1 do
  begin
    if ATab.Controls[J] is TSqlEditorFrame then
      Exit(TSqlEditorFrame(ATab.Controls[J]));
  end;
end;

function TMainForm.FindComparerFrame(const ATab: TTabSheet): TDatabaseComparerFrame;
var
  J: Integer;
begin
  Result := nil;
  if ATab = nil then
    Exit;
  for J := 0 to ATab.ControlCount - 1 do
  begin
    if ATab.Controls[J] is TDatabaseComparerFrame then
      Exit(TDatabaseComparerFrame(ATab.Controls[J]));
  end;
end;

function TMainForm.FindScriptExecutorFrame(const ATab: TTabSheet): TScriptExecutorFrame;
var
  J: Integer;
begin
  Result := nil;
  if ATab = nil then
    Exit;
  for J := 0 to ATab.ControlCount - 1 do
  begin
    if ATab.Controls[J] is TScriptExecutorFrame then
      Exit(TScriptExecutorFrame(ATab.Controls[J]));
  end;
end;

function TMainForm.FindMonitorFrame(const ATab: TTabSheet): TDatabaseMonitorFrame;
var
  J: Integer;
begin
  Result := nil;
  if ATab = nil then
    Exit;
  for J := 0 to ATab.ControlCount - 1 do
  begin
    if ATab.Controls[J] is TDatabaseMonitorFrame then
      Exit(TDatabaseMonitorFrame(ATab.Controls[J]));
  end;
end;

function TMainForm.FindTableEditorFrame(const ATab: TTabSheet): TTableEditorFrame;
var
  J: Integer;
begin
  Result := nil;
  if ATab = nil then
    Exit;
  for J := 0 to ATab.ControlCount - 1 do
  begin
    if ATab.Controls[J] is TTableEditorFrame then
      Exit(TTableEditorFrame(ATab.Controls[J]));
  end;
end;

function TMainForm.GetProfileSessionSummary(const AProfileId: string): TProfileSessionSummary;
var
  I: Integer;
  Tab: TTabSheet;
  SqlFrame: TSqlEditorFrame;
  ScriptFrame: TScriptExecutorFrame;
  MonFrame: TDatabaseMonitorFrame;
  CompFrame: TDatabaseComparerFrame;
begin
  Result := Default(TProfileSessionSummary);
  if (pgEditors = nil) or (Trim(AProfileId) = '') then
    Exit;

  for I := 0 to pgEditors.PageCount - 1 do
  begin
    Tab := pgEditors.Pages[I];

    SqlFrame := FindSqlEditorFrame(Tab);
    if (SqlFrame <> nil) and SameText(SqlFrame.ActiveProfileId, AProfileId) and SqlFrame.IsConnected then
    begin
      Inc(Result.ActiveCount);
      if SqlFrame.IsExecuting then
        Inc(Result.BusyCount)
      else if SqlFrame.HasActiveTransaction then
        Inc(Result.InTransactionCount);
    end;

    ScriptFrame := FindScriptExecutorFrame(Tab);
    if (ScriptFrame <> nil) and SameText(ScriptFrame.ActiveProfileId, AProfileId) and ScriptFrame.IsConnected then
    begin
      Inc(Result.ActiveCount);
      if ScriptFrame.IsBusy then
        Inc(Result.BusyCount)
      else if ScriptFrame.HasActiveTransaction then
        Inc(Result.InTransactionCount);
    end;

    MonFrame := FindMonitorFrame(Tab);
    if (MonFrame <> nil) and SameText(MonFrame.ActiveProfileId, AProfileId) and MonFrame.IsConnected then
      Inc(Result.ActiveCount);

    CompFrame := FindComparerFrame(Tab);
    if (CompFrame <> nil) and CompFrame.IsBusy and CompFrame.UsesProfile(AProfileId) then
    begin
      Inc(Result.ActiveCount);
      Inc(Result.BusyCount);
    end;
  end;
end;

function TMainForm.DisconnectProfileSessions(const AProfileId: string): Integer;
var
  I: Integer;
  Tab: TTabSheet;
  SqlFrame: TSqlEditorFrame;
  ScriptFrame: TScriptExecutorFrame;
  MonFrame: TDatabaseMonitorFrame;
  CompFrame: TDatabaseComparerFrame;
begin
  Result := 0;
  if (pgEditors = nil) or (Trim(AProfileId) = '') then
    Exit;

  for I := 0 to pgEditors.PageCount - 1 do
  begin
    Tab := pgEditors.Pages[I];

    SqlFrame := FindSqlEditorFrame(Tab);
    if (SqlFrame <> nil) and SameText(SqlFrame.ActiveProfileId, AProfileId) and SqlFrame.IsConnected then
    begin
      SqlFrame.DisconnectSession;
      Inc(Result);
    end;

    ScriptFrame := FindScriptExecutorFrame(Tab);
    if (ScriptFrame <> nil) and SameText(ScriptFrame.ActiveProfileId, AProfileId) and ScriptFrame.IsConnected then
    begin
      ScriptFrame.DisconnectSession;
      Inc(Result);
    end;

    MonFrame := FindMonitorFrame(Tab);
    if (MonFrame <> nil) and SameText(MonFrame.ActiveProfileId, AProfileId) and MonFrame.IsConnected then
    begin
      MonFrame.Disconnect;
      Inc(Result);
    end;

    CompFrame := FindComparerFrame(Tab);
    if (CompFrame <> nil) and CompFrame.IsBusy and CompFrame.UsesProfile(AProfileId) then
    begin
      CompFrame.DisconnectAndCancel;
      Inc(Result);
    end;
  end;
end;

function TMainForm.CountExecutingTabs: Integer;
var
  I: Integer;
  Frame: TSqlEditorFrame;
begin
  Result := 0;
  if pgEditors = nil then
    Exit;
  for I := 0 to pgEditors.PageCount - 1 do
  begin
    Frame := FindSqlEditorFrame(pgEditors.Pages[I]);
    if (Frame <> nil) and Frame.IsExecuting then
      Inc(Result);
  end;
end;

function TMainForm.CountBusyComparerTabs: Integer;
var
  I: Integer;
  CompFrame: TDatabaseComparerFrame;
begin
  Result := 0;
  if pgEditors = nil then
    Exit;
  for I := 0 to pgEditors.PageCount - 1 do
  begin
    CompFrame := FindComparerFrame(pgEditors.Pages[I]);
    if (CompFrame <> nil) and CompFrame.IsBusy then
      Inc(Result);
  end;
end;

function TMainForm.CountBusyScriptTabs: Integer;
var
  I: Integer;
  ScriptFrame: TScriptExecutorFrame;
begin
  Result := 0;
  if pgEditors = nil then
    Exit;
  for I := 0 to pgEditors.PageCount - 1 do
  begin
    ScriptFrame := FindScriptExecutorFrame(pgEditors.Pages[I]);
    if (ScriptFrame <> nil) and ScriptFrame.IsBusy then
      Inc(Result);
  end;
end;

function TMainForm.CountDirtyTableTriggerTabs: Integer;
var
  I: Integer;
  TableFrame: TTableEditorFrame;
begin
  Result := 0;
  if pgEditors = nil then
    Exit;
  for I := 0 to pgEditors.PageCount - 1 do
  begin
    TableFrame := FindTableEditorFrame(pgEditors.Pages[I]);
    if (TableFrame <> nil) and TableFrame.HasUnsavedTriggerChanges then
      Inc(Result);
  end;
end;

procedure TMainForm.HandleEditorExecutionStateChanged(
  Sender: TObject;
  const ARunning: Boolean;
  const AStatusText: string
);
var
  Frame: TSqlEditorFrame;
  TabCap: string;
begin
  if not (Sender is TSqlEditorFrame) then
    Exit;
  Frame := TSqlEditorFrame(Sender);
  TabCap := Trim(Frame.BaseTabCaption);
  if TabCap = '' then
    TabCap := 'SQL';
  if ARunning then
    StatusBar1.SimpleText := Format('[%s] %s', [TabCap, AStatusText])
  else
    StatusBar1.SimpleText := Format('[%s] %s', [TabCap, AStatusText]);
end;

procedure TMainForm.HandleTableStructureChanged(const AProfileId: string);
var
  I, J: Integer;
  Tab: TTabSheet;
begin
  if (pgEditors = nil) or (Trim(AProfileId) = '') then
    Exit;

  ReloadCategoryForProfile(AProfileId, sokTables);
  for I := 0 to pgEditors.PageCount - 1 do
  begin
    Tab := pgEditors.Pages[I];
    for J := 0 to Tab.ControlCount - 1 do
    begin
      if (Tab.Controls[J] is TSqlEditorFrame) and
         SameText(TSqlEditorFrame(Tab.Controls[J]).ActiveProfileId, AProfileId) then
        TSqlEditorFrame(Tab.Controls[J]).ClearMetadataCache
      else if (Tab.Controls[J] is TObjectEditorFrame) and
              SameText(TObjectEditorFrame(Tab.Controls[J]).ProfileId, AProfileId) then
        TObjectEditorFrame(Tab.Controls[J]).ClearMetadataCache
      else if (Tab.Controls[J] is TTableEditorFrame) and
              SameText(TTableEditorFrame(Tab.Controls[J]).ProfileId, AProfileId) then
        TTableEditorFrame(Tab.Controls[J]).ClearMetadataCache;
    end;
  end;
end;

procedure TMainForm.HandleTableTriggersChanged(const AProfileId: string);
begin
  ReloadCategoryForProfile(AProfileId, sokTriggers);
  HandleTableStructureChanged(AProfileId);
end;

procedure TMainForm.OpenTableEditorTab(const AProfile: TConnectionProfile; const ATableName: string);
var
  I: Integer;
  Tab: TTabSheet;
  TableFrame: TTableEditorFrame;
  CleanTableName: string;
begin
  CleanTableName := Trim(ATableName);
  if (AProfile = nil) or (CleanTableName = '') then
    Exit;

  for I := 0 to pgEditors.PageCount - 1 do
  begin
    Tab := pgEditors.Pages[I];
    TableFrame := FindTableEditorFrame(Tab);
    if (TableFrame <> nil) and
       SameText(TableFrame.ProfileId, AProfile.Id) and
       SameText(TableFrame.TableName, CleanTableName) then
    begin
      pgEditors.ActivePage := Tab;
      Exit;
    end;
  end;

  Inc(FTabCounter);
  Tab := TTabSheet.Create(pgEditors);
  Tab.PageControl := pgEditors;
  SetTabSheetTitle(Tab, 'Tabela: ' + CleanTableName);

  TableFrame := TTableEditorFrame.Create(Tab);
  TableFrame.Name := Format('TableEditorFrame_%d', [FTabCounter]);
  TableFrame.Parent := Tab;
  TableFrame.Align := alClient;
  TableFrame.OnOpenDependency := @HandleOpenTableDependency;
  TableFrame.OnOpenSqlScript := @HandleOpenTableSqlScript;
  TableFrame.OnStructureChanged := @HandleTableStructureChanged;
  TableFrame.OnTriggersChanged := @HandleTableTriggersChanged;
  TableFrame.Initialize(AProfile, CleanTableName, FManageTableStructure);

  pgEditors.ActivePage := Tab;
end;

procedure TMainForm.HandleOpenTableDependency(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind;
  const AObjectName: string
);
var
  WasDropped: Boolean;
begin
  if (AProfile = nil) or (Trim(AObjectName) = '') then
    Exit;

  case AKind of
    sokTables:
      OpenTableEditorTab(AProfile, AObjectName);
    sokViews, sokProcedures, sokTriggers:
      OpenObjectEditorTab(AProfile, AKind, AObjectName, False);
    sokGenerators:
      begin
        if TGeneratorForm.Execute(AProfile, AObjectName, FManageObjects, WasDropped) and WasDropped then
          ReloadCategoryForProfile(AProfile.Id, sokGenerators);
      end;
  end;
end;

procedure TMainForm.OpenObjectEditorTab(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind;
  const AObjectName: string;
  const AIsNew: Boolean
);
var
  I, J: Integer;
  Tab: TTabSheet;
  ObjFrame: TObjectEditorFrame;
  DDL, Prefix: string;
begin
  if AProfile = nil then
    Exit;

  if not AIsNew then
  begin
    for I := 0 to pgEditors.PageCount - 1 do
    begin
      Tab := pgEditors.Pages[I];
      for J := 0 to Tab.ControlCount - 1 do
      begin
        if Tab.Controls[J] is TObjectEditorFrame then
        begin
          ObjFrame := TObjectEditorFrame(Tab.Controls[J]);
          if SameText(ObjFrame.ProfileId, AProfile.Id) and
             (ObjFrame.ObjectKind = AKind) and
             SameText(ObjFrame.ObjectName, AObjectName) then
          begin
            pgEditors.ActivePage := Tab;
            Exit;
          end;
        end;
      end;
    end;
  end;

  Screen.Cursor := crHourGlass;
  try
    try
      if AIsNew then
        DDL := FManageObjects.BuildNewObjectTemplate(AProfile.DatabaseType, AKind, AObjectName)
      else
        DDL := FManageObjects.LoadObjectDDL(AProfile, AKind, AObjectName);
    except
      on E: Exception do
      begin
        MessageDlg('Erro ao carregar DDL', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  Inc(FTabCounter);
  Tab := TTabSheet.Create(pgEditors);
  Tab.PageControl := pgEditors;
  case AKind of
    sokTables: Prefix := 'DDL Tabela';
    sokViews: Prefix := 'View';
    sokProcedures: Prefix := 'Proc';
    sokTriggers: Prefix := 'Trg';
    sokGenerators: Prefix := 'DDL Gen';
  else
    Prefix := 'DDL';
  end;
  if AIsNew then
    SetTabSheetTitle(Tab, 'Novo(a) ' + Prefix)
  else
    SetTabSheetTitle(Tab, Prefix + ': ' + AObjectName);

  ObjFrame := TObjectEditorFrame.Create(Tab);
  ObjFrame.Name := Format('ObjectEditorFrame_%d', [FTabCounter]);
  ObjFrame.Parent := Tab;
  ObjFrame.Align := alClient;
  ObjFrame.OnObjectChanged := @HandleObjectChanged;
  ObjFrame.OnOpenViewData := @HandleOpenViewData;
  ObjFrame.Initialize(AProfile, AKind, AObjectName, FManageObjects, DDL, AIsNew);

  pgEditors.ActivePage := Tab;
end;

procedure TMainForm.OpenMonitorTab(const AInitialProfileId: string);
var
  Tab: TTabSheet;
  MonFrame: TDatabaseMonitorFrame;
  TargetId: string;
  Profile: TConnectionProfile;
begin
  TargetId := AInitialProfileId;
  if TargetId = '' then
  begin
    Profile := SelectedProfile;
    if Profile <> nil then
      TargetId := Profile.Id;
  end;

  Inc(FTabCounter);
  Tab := TTabSheet.Create(pgEditors);
  Tab.PageControl := pgEditors;
  SetTabSheetTitle(Tab, 'Monitor BD');

  MonFrame := TDatabaseMonitorFrame.Create(Tab);
  MonFrame.Name := Format('DatabaseMonitorFrame_%d', [FTabCounter]);
  MonFrame.Parent := Tab;
  MonFrame.Align := alClient;
  MonFrame.Initialize(FFactory, FMonitorUseCase, FConnections, TargetId);

  pgEditors.ActivePage := Tab;
end;

procedure TMainForm.OpenComparerTab(const AInitialSourceId: string);
var
  Tab: TTabSheet;
  CompFrame: TDatabaseComparerFrame;
  TargetId: string;
  Profile: TConnectionProfile;
begin
  TargetId := AInitialSourceId;
  if TargetId = '' then
  begin
    Profile := SelectedProfile;
    if Profile <> nil then
      TargetId := Profile.Id;
  end;

  Inc(FTabCounter);
  Tab := TTabSheet.Create(pgEditors);
  Tab.PageControl := pgEditors;
  SetTabSheetTitle(Tab, 'Comparar Bases');

  CompFrame := TDatabaseComparerFrame.Create(Tab);
  CompFrame.Name := Format('DatabaseComparerFrame_%d', [FTabCounter]);
  CompFrame.Parent := Tab;
  CompFrame.Align := alClient;
  CompFrame.OnOpenSqlInNewTab := @HandleOpenSqlFromTool;
  CompFrame.Initialize(FFactory, FConnections, TargetId);

  pgEditors.ActivePage := Tab;
end;

procedure TMainForm.OpenScriptExecutorTab(
  const AInitialProfileId: string;
  const AInitialScript: string
);
var
  Tab: TTabSheet;
  ScriptFrame: TScriptExecutorFrame;
  TargetId: string;
  Profile: TConnectionProfile;
begin
  TargetId := AInitialProfileId;
  if TargetId = '' then
  begin
    Profile := SelectedProfile;
    if Profile <> nil then
      TargetId := Profile.Id;
  end;

  Inc(FTabCounter);
  Tab := TTabSheet.Create(pgEditors);
  Tab.PageControl := pgEditors;
  SetTabSheetTitle(Tab, Format('Script %d', [FTabCounter]));

  ScriptFrame := TScriptExecutorFrame.Create(Tab);
  ScriptFrame.Name := Format('ScriptExecutorFrame_%d', [FTabCounter]);
  ScriptFrame.Parent := Tab;
  ScriptFrame.Align := alClient;
  ScriptFrame.OnOpenObject := @HandleOpenTableDependency;
  ScriptFrame.Initialize(FFactory, FConnections, TargetId);
  if Trim(AInitialScript) <> '' then
    ScriptFrame.SetScriptText(AInitialScript);

  pgEditors.ActivePage := Tab;
end;

procedure TMainForm.OpenMaintenanceDialog(
  const AInitialTab: TMaintenanceTabKind;
  const AInitialProfileId: string
);
var
  TargetId: string;
  Profile: TConnectionProfile;
begin
  TargetId := AInitialProfileId;
  if TargetId = '' then
  begin
    Profile := SelectedProfile;
    if Profile <> nil then
      TargetId := Profile.Id;
  end;
  TDatabaseMaintenanceForm.Execute(FConnections, TargetId, AInitialTab);
end;

procedure TMainForm.RestoreWorkspace;
var
  State: TWorkspaceState;
  I, MaxW, MaxH: Integer;
  Frame: TSqlEditorFrame;
begin
  State := FWorkspaceRepo.Load;
  try
    if State.WindowMaximized then
      WindowState := wsMaximized
    else if (State.WindowWidth >= Constraints.MinWidth) and (State.WindowHeight >= Constraints.MinHeight) then
    begin
      MaxW := State.WindowWidth;
      MaxH := State.WindowHeight;
      if (Screen <> nil) and (Screen.WorkAreaWidth > 0) then
        MaxW := Min(MaxW, Max(Constraints.MinWidth, Screen.WorkAreaWidth));
      if (Screen <> nil) and (Screen.WorkAreaHeight > 0) then
        MaxH := Min(MaxH, Max(Constraints.MinHeight, Screen.WorkAreaHeight));
      Width := MaxW;
      Height := MaxH;
    end;

    if State.LeftPanelWidth >= 250 then
    begin
      FLastLeftPanelWidth := State.LeftPanelWidth;
      if (ClientWidth > 670) and (FLastLeftPanelWidth > ClientWidth - 420) then
        FLastLeftPanelWidth := ClientWidth - 420;
      pnlLeft.Width := FLastLeftPanelWidth;
    end;
    SetSidebarVisible(State.LeftPanelVisible);

    if Length(State.Tabs) = 0 then
    begin
      OpenNewEditorTab;
      Exit;
    end;

    for I := 0 to High(State.Tabs) do
    begin
      Frame := OpenNewEditorTab(State.Tabs[I].ProfileId, State.Tabs[I].Title);
      Frame.SetSqlText(State.Tabs[I].SqlText);
      Frame.SetBatchSizeText(State.Tabs[I].BatchSize);
      Frame.SetMemoryLimitText(State.Tabs[I].MemoryLimit);
      Frame.SetAutoCommit(State.Tabs[I].AutoCommit);
    end;

    if (State.ActiveTabIndex >= 0) and (State.ActiveTabIndex < pgEditors.PageCount) then
      pgEditors.ActivePageIndex := State.ActiveTabIndex;
  finally
    State.Free;
  end;
end;

procedure TMainForm.SaveWorkspace;
var
  State: TWorkspaceState;
  I, J: Integer;
  Tab: TTabSheet;
  Frame: TSqlEditorFrame;
  Item: TWorkspaceTabState;
  TabTitle: string;
begin
  if FWorkspaceRepo = nil then
    Exit;

  State := TWorkspaceState.Create;
  try
    State.ActiveTabIndex := pgEditors.ActivePageIndex;
    State.WindowMaximized := (WindowState = wsMaximized);
    if State.WindowMaximized then
    begin
      if RestoredWidth > 0 then
        State.WindowWidth := RestoredWidth
      else
        State.WindowWidth := Width;
      if RestoredHeight > 0 then
        State.WindowHeight := RestoredHeight
      else
        State.WindowHeight := Height;
    end
    else
    begin
      State.WindowWidth := Width;
      State.WindowHeight := Height;
    end;
    State.LeftPanelVisible := pnlLeft.Visible;
    if pnlLeft.Visible then
      State.LeftPanelWidth := pnlLeft.Width
    else
      State.LeftPanelWidth := FLastLeftPanelWidth;

    for I := 0 to pgEditors.PageCount - 1 do
    begin
      Tab := pgEditors.Pages[I];
      for J := 0 to Tab.ControlCount - 1 do
      begin
        if Tab.Controls[J] is TSqlEditorFrame then
        begin
          Frame := TSqlEditorFrame(Tab.Controls[J]);
          TabTitle := Trim(Frame.BaseTabCaption);
          if TabTitle = '' then
            TabTitle := StripEditorTabCloseSuffix(Tab.Caption);
          Item.Title := TabTitle;
          Item.ProfileId := Frame.ActiveProfileId;
          Item.SqlText := Frame.SqlText;
          Item.BatchSize := Frame.BatchSizeText;
          Item.MemoryLimit := Frame.MemoryLimitText;
          Item.AutoCommit := Frame.AutoCommit;
          State.AddTab(Item);
          Break;
        end;
      end;
    end;
    FWorkspaceRepo.Save(State);
  finally
    State.Free;
  end;
end;

function TMainForm.SelectedNodeData: TExplorerNodeData;
begin
  Result := nil;
  if (tvConnections.Selected <> nil) and (tvConnections.Selected.Data <> nil) then
    Result := TExplorerNodeData(tvConnections.Selected.Data);
end;

function TMainForm.SelectedConnectionNode: TTreeNode;
var
  Node: TTreeNode;
  Data: TExplorerNodeData;
begin
  Result := nil;
  Node := tvConnections.Selected;
  while Node <> nil do
  begin
    if Node.Data <> nil then
    begin
      Data := TExplorerNodeData(Node.Data);
      if Data.Kind = enkConnection then
        Exit(Node);
    end;
    Node := Node.Parent;
  end;
end;

function TMainForm.FindAdjacentVisibleSibling(const ANode: TTreeNode; const ADelta: Integer): TTreeNode;
var
  Cur: TTreeNode;
begin
  Result := nil;
  if ANode = nil then
    Exit;

  if ADelta < 0 then
    Cur := ANode.GetPrevSibling
  else
    Cur := ANode.GetNextSibling;

  while Cur <> nil do
  begin
    if Cur.Visible then
      Exit(Cur);
    if ADelta < 0 then
      Cur := Cur.GetPrevSibling
    else
      Cur := Cur.GetNextSibling;
  end;
end;

function TMainForm.SelectedFolderNode: TTreeNode;
var
  Node: TTreeNode;
  Data: TExplorerNodeData;
begin
  Result := nil;
  Node := tvConnections.Selected;
  while Node <> nil do
  begin
    if Node.Data <> nil then
    begin
      Data := TExplorerNodeData(Node.Data);
      if Data.Kind = enkFolder then
        Exit(Node);
    end;
    Node := Node.Parent;
  end;
end;

procedure TMainForm.UpdateConnectionButtonsState;
var
  ConnNode, FolderNode: TTreeNode;
  HasConn, HasFolder: Boolean;
begin
  ConnNode := SelectedConnectionNode;
  FolderNode := SelectedFolderNode;
  HasConn := ConnNode <> nil;
  HasFolder := (not HasConn) and (FolderNode <> nil);
  btnEditConn.Enabled := HasConn or HasFolder;
  btnDeleteConn.Enabled := HasConn or HasFolder;
  if HasFolder then
  begin
    btnEditConn.Hint := 'Renomear pasta selecionada';
    btnDeleteConn.Hint := 'Excluir pasta selecionada';
  end
  else
  begin
    btnEditConn.Hint := 'Editar conexão selecionada';
    btnDeleteConn.Hint := 'Excluir conexão selecionada';
  end;
  btnMoveConnUp.Enabled := HasConn and (FindAdjacentVisibleSibling(ConnNode, -1) <> nil);
  btnMoveConnDown.Enabled := HasConn and (FindAdjacentVisibleSibling(ConnNode, 1) <> nil);
  btnSortConns.Enabled := (FConnections <> nil) and (FConnections.Count > 1);
  if FNextSortAsc then
    btnSortConns.Caption := 'A-Z'
  else
    btnSortConns.Caption := 'Z-A';
end;

procedure TMainForm.PersistCurrentTreeOrder;
var
  OrderedProfiles: TConnectionProfileList;
  OrderedIds: TStringList;
  Root: TTreeNode;
  Profile: TConnectionProfile;

  procedure CollectFromNode(const ANode: TTreeNode);
  var
    Child: TTreeNode;
    Data: TExplorerNodeData;
  begin
    if (ANode = nil) or (ANode.Data = nil) then
      Exit;

    Data := TExplorerNodeData(ANode.Data);
    if (Data.Kind = enkConnection) and (Data.Profile <> nil) then
    begin
      if OrderedProfiles.IndexOf(Data.Profile) < 0 then
      begin
        OrderedProfiles.Add(Data.Profile);
        OrderedIds.Add(Data.Profile.Id);
      end;
    end
    else if Data.Kind in [enkGroup, enkFolder] then
    begin
      Child := ANode.GetFirstChild;
      while Child <> nil do
      begin
        CollectFromNode(Child);
        Child := Child.GetNextSibling;
      end;
    end;
  end;

begin
  if FConnections = nil then
    Exit;

  OrderedProfiles := TConnectionProfileList.Create(False);
  OrderedIds := TStringList.Create;
  try
    Root := tvConnections.Items.GetFirstNode;
    while Root <> nil do
    begin
      CollectFromNode(Root);
      Root := Root.GetNextSibling;
    end;

    for Profile in FConnections do
    begin
      if OrderedProfiles.IndexOf(Profile) < 0 then
      begin
        OrderedProfiles.Add(Profile);
        OrderedIds.Add(Profile.Id);
      end;
    end;

    FConnections.OwnsObjects := False;
    try
      FConnections.Clear;
      for Profile in OrderedProfiles do
        FConnections.Add(Profile);
    finally
      FConnections.OwnsObjects := True;
    end;

    FManageConnections.Reorder(OrderedIds);
    RefreshOpenTabsConnections;
  finally
    OrderedIds.Free;
    OrderedProfiles.Free;
  end;
end;

procedure TMainForm.MoveSelectedConnection(const ADelta: Integer);
var
  ConnNode, TargetNode: TTreeNode;
begin
  ConnNode := SelectedConnectionNode;
  if ConnNode = nil then
    Exit;

  TargetNode := FindAdjacentVisibleSibling(ConnNode, ADelta);
  if TargetNode = nil then
    Exit;

  tvConnections.Items.BeginUpdate;
  try
    if ADelta < 0 then
      ConnNode.MoveTo(TargetNode, naInsert)
    else
      ConnNode.MoveTo(TargetNode, naInsertBehind);
    tvConnections.Selected := ConnNode;
    ConnNode.MakeVisible;
  finally
    tvConnections.Items.EndUpdate;
  end;

  PersistCurrentTreeOrder;
  UpdateConnectionButtonsState;
  StatusBar1.SimpleText := 'Ordem das conexões atualizada.';
end;

procedure TMainForm.SortConnections(const AAscending: Boolean);
var
  PrevSelected: TTreeNode;

  procedure SortNodesArray(var ANodes: array of TTreeNode; const ACount: Integer);
  var
    I, J, Cmp: Integer;
    TempNode: TTreeNode;
  begin
    for I := 0 to ACount - 2 do
      for J := I + 1 to ACount - 1 do
      begin
        Cmp := AnsiCompareText(ANodes[I].Text, ANodes[J].Text);
        if not AAscending then
          Cmp := -Cmp;
        if Cmp > 0 then
        begin
          TempNode := ANodes[I];
          ANodes[I] := ANodes[J];
          ANodes[J] := TempNode;
        end;
      end;
  end;

  procedure SortRootAndFolders;
  var
    Folders, RootConns, FolderConns: array of TTreeNode;
    Node, Child: TTreeNode;
    FCount, RCount, CCount, I: Integer;
  begin
    SetLength(Folders, 0);
    SetLength(RootConns, 0);
    FCount := 0;
    RCount := 0;

    Node := tvConnections.Items.GetFirstNode;
    while Node <> nil do
    begin
      if Node.Data <> nil then
      begin
        if TExplorerNodeData(Node.Data).Kind = enkFolder then
        begin
          Inc(FCount);
          SetLength(Folders, FCount);
          Folders[FCount - 1] := Node;
        end
        else if TExplorerNodeData(Node.Data).Kind = enkConnection then
        begin
          Inc(RCount);
          SetLength(RootConns, RCount);
          RootConns[RCount - 1] := Node;
        end;
      end;
      Node := Node.GetNextSibling;
    end;

    SortNodesArray(Folders, FCount);
    SortNodesArray(RootConns, RCount);

    for I := 0 to FCount - 1 do
    begin
      Folders[I].MoveTo(nil, naAdd);

      SetLength(FolderConns, 0);
      CCount := 0;
      Child := Folders[I].GetFirstChild;
      while Child <> nil do
      begin
        if (Child.Data <> nil) and (TExplorerNodeData(Child.Data).Kind = enkConnection) then
        begin
          Inc(CCount);
          SetLength(FolderConns, CCount);
          FolderConns[CCount - 1] := Child;
        end;
        Child := Child.GetNextSibling;
      end;
      SortNodesArray(FolderConns, CCount);
      for Child in FolderConns do
        Child.MoveTo(Folders[I], naAddChild);
    end;

    for I := 0 to RCount - 1 do
      RootConns[I].MoveTo(nil, naAdd);
  end;

begin
  PrevSelected := SelectedConnectionNode;
  tvConnections.Items.BeginUpdate;
  try
    SortRootAndFolders;

    if PrevSelected <> nil then
    begin
      tvConnections.Selected := PrevSelected;
      PrevSelected.MakeVisible;
    end;
  finally
    tvConnections.Items.EndUpdate;
  end;

  PersistCurrentTreeOrder;
  UpdateConnectionButtonsState;
  if AAscending then
    StatusBar1.SimpleText := 'Conexões ordenadas de A-Z.'
  else
    StatusBar1.SimpleText := 'Conexões ordenadas de Z-A.';
end;

procedure TMainForm.SetSidebarVisible(const AVisible: Boolean);
var
  TargetW: Integer;
begin
  if AVisible then
  begin
    TargetW := FLastLeftPanelWidth;
    if TargetW < 250 then
      TargetW := 280;
    if (ClientWidth > 670) and (TargetW > ClientWidth - 420) then
      TargetW := ClientWidth - 420;
    pnlLeft.Width := TargetW;
    pnlLeft.Visible := True;
    Splitter1.Visible := True;
    Splitter1.Left := pnlLeft.Width;
    btnToggleSidebar.Caption := '« Painel';
  end
  else
  begin
    if pnlLeft.Visible and (pnlLeft.Width >= 250) then
      FLastLeftPanelWidth := pnlLeft.Width;
    Splitter1.Visible := False;
    pnlLeft.Visible := False;
    btnToggleSidebar.Caption := '» Conexões';
  end;
end;

procedure TMainForm.FormResize(Sender: TObject);
var
  MaxLeft: Integer;
begin
  if pnlLeft.Visible and (ClientWidth > 670) then
  begin
    MaxLeft := ClientWidth - 420;
    if pnlLeft.Width > MaxLeft then
      pnlLeft.Width := MaxLeft;
  end;
end;

function TMainForm.SelectedProfile: TConnectionProfile;
var
  Data: TExplorerNodeData;
begin
  Result := nil;
  Data := SelectedNodeData;
  if Data <> nil then
    Result := Data.Profile;
end;

procedure TMainForm.tvConnectionsExpanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: Boolean);
var
  Data: TExplorerNodeData;
  Cat: TSchemaObjectKind;
  CatNode, DbNode: TTreeNode;
  Objects, Databases: TStringList;
  DbProfile: TConnectionProfile;
  I: Integer;
begin
  if (Node = nil) or (Node.Data = nil) then
    Exit;

  Data := TExplorerNodeData(Node.Data);
  if Data.Loaded then
    Exit;

  if (Data.Kind = enkConnection) and (Data.Profile <> nil) and
     (Data.Profile.DatabaseType = dtPostgreSQL) and (Trim(Data.Profile.Database) = '') then
  begin
    Screen.Cursor := crHourGlass;
    tvConnections.Items.BeginUpdate;
    try
      try
        Databases := FBrowseSchema.ListPostgresDatabases(Data.Profile);
        try
          Node.DeleteChildren;
          for I := 0 to Databases.Count - 1 do
          begin
            DbProfile := Data.Profile.Clone;
            DbProfile.Database := Databases[I];
            DbProfile.Name := Format('%s (%s)', [Data.Profile.Name, Databases[I]]);
            DbProfile.Id := Format('%s::%s', [Data.Profile.Id, Databases[I]]);
            FDatabaseProfiles.Add(DbProfile);
            DbNode := tvConnections.Items.AddChildObject(
              Node,
              Format('%s [%s]', [Databases[I], DbProfile.EffectiveSchema]),
              CreateNodeData(enkDatabase, DbProfile)
            );
            DbNode.HasChildren := True;
          end;
          Node.Text := Format('%s [PG: servidor] (%d)', [Data.Profile.Name, Databases.Count]);
          Data.TotalCount := Databases.Count;
          Data.Loaded := True;
        finally
          Databases.Free;
        end;
      except
        on E: Exception do
        begin
          AllowExpansion := False;
          MessageDlg('Erro ao listar bancos de dados', E.Message, mtError, [mbOK], 0);
        end;
      end;
    finally
      tvConnections.Items.EndUpdate;
      Screen.Cursor := crDefault;
    end;
    if Trim(edtTreeFilter.Text) <> '' then
    begin
      ApplyTreeFilter;
      UpdateConnectionButtonsState;
    end;
  end
  else if Data.Kind in [enkConnection, enkDatabase] then
  begin
    tvConnections.Items.BeginUpdate;
    try
      Node.DeleteChildren;
      for Cat := Low(TSchemaObjectKind) to High(TSchemaObjectKind) do
      begin
        CatNode := tvConnections.Items.AddChildObject(
          Node,
          SchemaObjectKindToStr(Cat),
          CreateNodeData(enkCategory, Data.Profile, Cat)
        );
        CatNode.HasChildren := True;
      end;
      Data.Loaded := True;
    finally
      tvConnections.Items.EndUpdate;
    end;
  end
  else if Data.Kind = enkCategory then
  begin
    Screen.Cursor := crHourGlass;
    tvConnections.Items.BeginUpdate;
    try
      try
        Objects := FBrowseSchema.ListObjects(Data.Profile, Data.Category);
        try
          Node.DeleteChildren;
          for I := 0 to Objects.Count - 1 do
          begin
            tvConnections.Items.AddChildObject(
              Node,
              FormatExplorerObjectCaption(Objects[I], Objects.Objects[I]),
              CreateNodeData(enkObject, Data.Profile, Data.Category, Objects[I])
            );
          end;
          Node.Text := Format('%s (%d)', [SchemaObjectKindToStr(Data.Category), Objects.Count]);
          Data.TotalCount := Objects.Count;
          Data.Loaded := True;
        finally
          Objects.Free;
        end;
      except
        on E: Exception do
        begin
          AllowExpansion := False;
          MessageDlg('Erro ao carregar metadados', E.Message, mtError, [mbOK], 0);
        end;
      end;
    finally
      tvConnections.Items.EndUpdate;
      Screen.Cursor := crDefault;
    end;
    if Trim(edtTreeFilter.Text) <> '' then
    begin
      ApplyTreeFilter;
      UpdateConnectionButtonsState;
    end;
  end;
end;

procedure TMainForm.btnNewConnClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  Data: TExplorerNodeData;
begin
  Profile := TConnectionProfile.Create;
  try
    Data := SelectedNodeData;
    if (Data <> nil) and (Data.Kind = enkFolder) then
      Profile.Folder := Data.FolderName
    else if (Data <> nil) and (Data.Profile <> nil) then
      Profile.Folder := Data.Profile.Folder;

    if TConnectionForm.Execute(Profile, FTestConnection, FManageConnections) then
    begin
      FManageConnections.Save(Profile);
      RefreshConnectionsTree(Profile.Id);
      StatusBar1.SimpleText := 'Conexão salva: ' + Profile.Name;
    end;
  finally
    Profile.Free;
  end;
end;

procedure TMainForm.btnEditConnClick(Sender: TObject);
var
  Current, Editable: TConnectionProfile;
  FolderNode: TTreeNode;
begin
  Current := SelectedProfile;
  if Current = nil then
  begin
    FolderNode := SelectedFolderNode;
    if FolderNode <> nil then
    begin
      miRenameFolderClick(nil);
      Exit;
    end;
    MessageDlg('Aviso', 'Selecione uma conexão ou pasta para editar.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Editable := Current.Clone;
  try
    if TConnectionForm.Execute(Editable, FTestConnection, FManageConnections) then
    begin
      FManageConnections.Save(Editable);
      RefreshConnectionsTree(Editable.Id);
      StatusBar1.SimpleText := 'Conexão atualizada: ' + Editable.Name;
    end;
  finally
    Editable.Free;
  end;
end;

procedure TMainForm.btnDeleteConnClick(Sender: TObject);
var
  Current: TConnectionProfile;
  FolderNode: TTreeNode;
begin
  Current := SelectedProfile;
  if Current = nil then
  begin
    FolderNode := SelectedFolderNode;
    if FolderNode <> nil then
    begin
      miDeleteFolderClick(nil);
      Exit;
    end;
    MessageDlg('Aviso', 'Selecione uma conexão ou pasta para excluir.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if MessageDlg('Confirmar Exclusão',
    Format('Deseja excluir a conexão "%s"?', [Current.Name]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FManageConnections.Delete(Current.Id);
    RefreshConnectionsTree;
    StatusBar1.SimpleText := 'Conexão excluída.';
  end;
end;

procedure TMainForm.btnMoveConnUpClick(Sender: TObject);
begin
  MoveSelectedConnection(-1);
end;

procedure TMainForm.btnMoveConnDownClick(Sender: TObject);
begin
  MoveSelectedConnection(1);
end;

procedure TMainForm.btnSortConnsClick(Sender: TObject);
begin
  SortConnections(FNextSortAsc);
  FNextSortAsc := not FNextSortAsc;
  UpdateConnectionButtonsState;
end;

procedure TMainForm.btnToggleSidebarClick(Sender: TObject);
begin
  SetSidebarVisible(not pnlLeft.Visible);
end;

procedure TMainForm.btnNewTabClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    OpenNewEditorTab(Profile.Id, Profile.Name, Profile)
  else
    OpenNewEditorTab;
end;

function TMainForm.FindEditorTabIndex(const ATab: TTabSheet): Integer;
var
  I: Integer;
begin
  Result := -1;
  if ATab = nil then
    Exit;
  for I := 0 to pgEditors.PageCount - 1 do
    if pgEditors.Pages[I] = ATab then
      Exit(I);
end;

procedure TMainForm.CloseEditorTab(const ATab: TTabSheet);
  function ConfirmBusyTabClose(const ATitle, AMessage: string): Boolean;
  begin
    pgEditors.ActivePage := ATab;
    Result := (MessageDlg(ATitle, AMessage, mtConfirmation, [mbYes, mbNo], 0) = mrYes) and
              not (csDestroying in ComponentState) and
              (FindEditorTabIndex(ATab) >= 0);
  end;

var
  Frame: TSqlEditorFrame;
  CompFrame: TDatabaseComparerFrame;
  ScriptFrame: TScriptExecutorFrame;
  TableFrame: TTableEditorFrame;
begin
  if (csDestroying in ComponentState) or (ATab = nil) or (FindEditorTabIndex(ATab) < 0) then
    Exit;

  if pgEditors.PageCount <= 1 then
  begin
    MessageDlg('Aviso', 'Mantenha pelo menos uma aba de editor aberta.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Frame := FindSqlEditorFrame(ATab);
  if (Frame <> nil) and Frame.IsExecuting then
  begin
    if not ConfirmBusyTabClose(
         'Consulta em Execução',
         'Esta aba possui uma consulta em execução em segundo plano. Deseja cancelar a consulta e fechar a aba?'
       ) then
      Exit;
    Frame := FindSqlEditorFrame(ATab);
    if Frame <> nil then
      Frame.DetachAndCancel;
  end;

  CompFrame := FindComparerFrame(ATab);
  if (CompFrame <> nil) and CompFrame.IsBusy then
  begin
    if not ConfirmBusyTabClose(
         'Comparação / Script em Execução',
         'Esta aba está executando uma comparação ou aplicação de script em segundo plano. Deseja cancelar e fechar a aba?'
       ) then
      Exit;
    CompFrame := FindComparerFrame(ATab);
    if CompFrame <> nil then
      CompFrame.DetachAndCancel;
  end;

  ScriptFrame := FindScriptExecutorFrame(ATab);
  if (ScriptFrame <> nil) and ScriptFrame.IsBusy then
  begin
    if not ConfirmBusyTabClose(
         'Script em Execução',
         'Esta aba possui um script em execução em segundo plano. Deseja cancelar e fechar a aba?'
       ) then
      Exit;
    ScriptFrame := FindScriptExecutorFrame(ATab);
    if ScriptFrame <> nil then
      ScriptFrame.DetachAndCancel;
  end;

  TableFrame := FindTableEditorFrame(ATab);
  if (TableFrame <> nil) and TableFrame.HasUnsavedTriggerChanges then
  begin
    if not ConfirmBusyTabClose(
         'Trigger com Alterações Não Compiladas',
         'Esta tabela possui alterações não compiladas em uma trigger. Deseja descartar as alterações e fechar a aba?'
       ) then
      Exit;
  end;

  if (csDestroying in ComponentState) or (pgEditors.PageCount <= 1) or (FindEditorTabIndex(ATab) < 0) then
    Exit;

  ATab.Free;
  TrimProcessMemoryUsage;
end;

procedure TMainForm.HandleDeferredCloseTab(Data: PtrInt);
var
  I: Integer;
  TargetTab: TTabSheet;
begin
  if csDestroying in ComponentState then
    Exit;

  TargetTab := nil;
  for I := 0 to pgEditors.PageCount - 1 do
    if PtrInt(pgEditors.Pages[I]) = Data then
    begin
      TargetTab := pgEditors.Pages[I];
      Break;
    end;

  if TargetTab <> nil then
    CloseEditorTab(TargetTab);
end;

procedure TMainForm.btnCloseTabClick(Sender: TObject);
begin
  CloseEditorTab(pgEditors.ActivePage);
end;

procedure TMainForm.pgEditorsCloseTabClicked(Sender: TObject);
begin
  if (Sender is TTabSheet) and (FindEditorTabIndex(TTabSheet(Sender)) >= 0) then
    // Defer freeing the tab past GTK2's button clicked signal emission.
    Forms.Application.QueueAsyncCall(@HandleDeferredCloseTab, PtrInt(Sender));
end;

procedure TMainForm.pgEditorsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
{$IFDEF WINDOWS}
var
  TabIdx: Integer;
  R: TRect;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if not (Button in [mbLeft, mbMiddle]) then
    Exit;
  TabIdx := pgEditors.IndexOfTabAt(X, Y);
  if (TabIdx < 0) or (TabIdx >= pgEditors.PageCount) then
    Exit;
  if Button = mbMiddle then
  begin
    Forms.Application.QueueAsyncCall(@HandleDeferredCloseTab, PtrInt(pgEditors.Pages[TabIdx]));
    Exit;
  end;
  R := pgEditors.TabRect(TabIdx);
  if (X >= R.Right - 22) and (X <= R.Right) and (Y >= R.Top) and (Y <= R.Bottom) then
    Forms.Application.QueueAsyncCall(@HandleDeferredCloseTab, PtrInt(pgEditors.Pages[TabIdx]));
  {$ENDIF}
end;

procedure TMainForm.btnMonitorDbClick(Sender: TObject);
begin
  OpenMonitorTab;
end;

procedure TMainForm.btnCompareDbClick(Sender: TObject);
begin
  OpenComparerTab;
end;

procedure TMainForm.btnScriptExecClick(Sender: TObject);
begin
  OpenScriptExecutorTab;
end;

procedure TMainForm.tvConnectionsChange(Sender: TObject; Node: TTreeNode);
begin
  UpdateConnectionButtonsState;
end;

procedure TMainForm.tvConnectionsDblClick(Sender: TObject);
var
  Data: TExplorerNodeData;
  WasDropped: Boolean;
begin
  Data := SelectedNodeData;
  if Data = nil then
    Exit;

  if Data.Kind = enkConnection then
  begin
    if (Data.Profile <> nil) and (Data.Profile.DatabaseType = dtPostgreSQL) and
       (Trim(Data.Profile.Database) = '') then
      Exit;
    OpenNewEditorTab(Data.Profile.Id, Data.Profile.Name);
  end
  else if Data.Kind = enkDatabase then
    OpenNewEditorTab(Data.Profile.Id, Data.Profile.Name, Data.Profile)
  else if Data.Kind = enkObject then
  begin
    case Data.Category of
      sokTables:
        OpenTableEditorTab(Data.Profile, Data.ObjectName);
      sokViews, sokProcedures, sokTriggers:
        OpenObjectEditorTab(Data.Profile, Data.Category, Data.ObjectName, False);
      sokGenerators:
        begin
          if TGeneratorForm.Execute(Data.Profile, Data.ObjectName, FManageObjects, WasDropped) then
          begin
            if WasDropped then
              ReloadCategoryForProfile(Data.Profile.Id, sokGenerators);
          end;
        end;
    end;
  end;
end;

procedure TMainForm.tvConnectionsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  HitNode: TTreeNode;
begin
  HitNode := tvConnections.GetNodeAt(X, Y);
  if Button = mbRight then
  begin
    if HitNode <> nil then
      tvConnections.Selected := HitNode;
    Exit;
  end;

  if (Button = mbLeft) and (not (ssDouble in Shift)) and (HitNode <> nil) and (HitNode.Data <> nil) then
  begin
    if (TExplorerNodeData(HitNode.Data).Kind = enkConnection) and
       (not (htOnButton in tvConnections.GetHitTestInfoAt(X, Y))) then
    begin
      tvConnections.Selected := HitNode;
      tvConnections.BeginDrag(False, 6);
    end;
  end;
end;

procedure TMainForm.tvConnectionsDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
var
  SrcNode, DstNode: TTreeNode;
  SrcData, DstData: TExplorerNodeData;
begin
  Accept := False;
  if Source <> tvConnections then
    Exit;

  SrcNode := tvConnections.Selected;
  DstNode := tvConnections.GetNodeAt(X, Y);
  if (SrcNode = nil) or (SrcNode = DstNode) or (SrcNode.Data = nil) then
    Exit;

  SrcData := TExplorerNodeData(SrcNode.Data);
  if (SrcData.Kind <> enkConnection) or (SrcData.Profile = nil) then
    Exit;

  if DstNode = nil then
  begin
    { Área vazia da árvore: permite tirar a conexão da pasta para a raiz }
    Accept := SrcNode.Parent <> nil;
    Exit;
  end;

  if DstNode.Data = nil then
    Exit;

  DstData := TExplorerNodeData(DstNode.Data);
  Accept := (DstData.Kind in [enkConnection, enkFolder]);
end;

procedure TMainForm.tvConnectionsDragDrop(Sender, Source: TObject; X, Y: Integer);
var
  SrcNode, DstNode: TTreeNode;
  SrcData, DstData: TExplorerNodeData;
  NodeRect: TRect;
  TargetFolder, OldFolder: string;
begin
  if Source <> tvConnections then
    Exit;

  SrcNode := tvConnections.Selected;
  DstNode := tvConnections.GetNodeAt(X, Y);
  if (SrcNode = nil) or (SrcNode = DstNode) or (SrcNode.Data = nil) then
    Exit;

  SrcData := TExplorerNodeData(SrcNode.Data);
  if (SrcData.Kind <> enkConnection) or (SrcData.Profile = nil) then
    Exit;

  OldFolder := Trim(SrcData.Profile.Folder);
  TargetFolder := OldFolder;

  tvConnections.Items.BeginUpdate;
  try
    if DstNode = nil then
    begin
      TargetFolder := '';
      SrcNode.MoveTo(nil, naAdd);
    end
    else
    begin
      if DstNode.Data = nil then
        Exit;
      DstData := TExplorerNodeData(DstNode.Data);

      if DstData.Kind = enkFolder then
      begin
        TargetFolder := DstData.FolderName;
        SrcNode.MoveTo(DstNode, naAddChild);
        DstNode.Expand(False);
      end
      else if (DstData.Kind = enkConnection) and (DstData.Profile <> nil) then
      begin
        TargetFolder := Trim(DstData.Profile.Folder);
        NodeRect := DstNode.DisplayRect(False);
        if Y < (NodeRect.Top + NodeRect.Bottom) div 2 then
          SrcNode.MoveTo(DstNode, naInsert)
        else
          SrcNode.MoveTo(DstNode, naInsertBehind);
      end
      else
        Exit;
    end;

    UpdateFolderCaptions;
    tvConnections.Selected := SrcNode;
    SrcNode.MakeVisible;
  finally
    tvConnections.Items.EndUpdate;
  end;

  if not SameText(OldFolder, TargetFolder) then
  begin
    SrcData.Profile.Folder := TargetFolder;
    FManageConnections.Save(SrcData.Profile);
  end;

  PersistCurrentTreeOrder;
  UpdateConnectionButtonsState;
  if not SameText(OldFolder, TargetFolder) then
  begin
    if TargetFolder = '' then
      StatusBar1.SimpleText := Format('Conexão "%s" movida para a raiz.', [SrcData.Profile.Name])
    else
      StatusBar1.SimpleText := Format('Conexão "%s" movida para a pasta "%s".', [SrcData.Profile.Name, TargetFolder]);
  end
  else
    StatusBar1.SimpleText := 'Ordem das conexões atualizada.';
end;

procedure TMainForm.tvConnectionsKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (ssAlt in Shift) and (Key = VK_UP) then
  begin
    Key := 0;
    MoveSelectedConnection(-1);
  end
  else if (ssAlt in Shift) and (Key = VK_DOWN) then
  begin
    Key := 0;
    MoveSelectedConnection(1);
  end;
end;

procedure TMainForm.pmConnectionsPopup(Sender: TObject);
var
  ConnNode, FolderNode: TTreeNode;
  Data: TExplorerNodeData;
  Profile: TConnectionProfile;
  Summary: TProfileSessionSummary;
  HasConn, HasFolder, HasMultiple, IsCat, IsObj: Boolean;
begin
  ConnNode := SelectedConnectionNode;
  FolderNode := SelectedFolderNode;
  HasConn := ConnNode <> nil;
  HasFolder := FolderNode <> nil;
  HasMultiple := (FConnections <> nil) and (FConnections.Count > 1);
  Data := SelectedNodeData;
  IsCat := (Data <> nil) and (Data.Kind = enkCategory);
  IsObj := (Data <> nil) and (Data.Kind = enkObject);

  Profile := SelectedProfile;
  if (Profile = nil) and HasConn and (ConnNode.Data <> nil) then
    Profile := TExplorerNodeData(ConnNode.Data).Profile;

  Summary := Default(TProfileSessionSummary);
  if Profile <> nil then
    Summary := GetProfileSessionSummary(Profile.Id);

  miOpenSqlTab.Enabled := HasConn;
  miScriptExec.Enabled := HasConn;
  miMonitorDb.Enabled := HasConn;
  miCompareDb.Enabled := HasConn;
  miMaintenanceDb.Enabled := HasConn;
  if miConnMetadataSearch <> nil then
    miConnMetadataSearch.Enabled := HasConn;
  if miConnIndexManager <> nil then
    miConnIndexManager.Enabled := HasConn;
  if miConnImportData <> nil then
    miConnImportData.Enabled := HasConn;

  miEditObject.Visible := IsObj and (Data.Category in [sokTables, sokViews, sokProcedures, sokTriggers, sokGenerators]);
  if IsObj and (Data.Category = sokTables) then
    miEditObject.Caption := 'Abrir Tabela (Estrutura / Triggers / Dados)'
  else if IsObj and (Data.Category = sokGenerators) then
    miEditObject.Caption := 'Editar Valor / Propriedades...'
  else
    miEditObject.Caption := 'Editar / Ver DDL';

  miViewObjectDDL.Visible := IsObj and (Data.Category in [sokTables, sokViews, sokProcedures, sokTriggers, sokGenerators]);
  miViewObjectData.Visible := IsObj and (Data.Category in [sokTables, sokViews]);
  miNewObject.Visible := (IsCat or IsObj) and (Data.Category in [sokViews, sokProcedures, sokTriggers, sokGenerators]);
  miRefreshCategory.Visible := IsCat or IsObj;
  miDropObject.Visible := IsObj and (Data.Category in [sokTables, sokViews, sokProcedures, sokTriggers, sokGenerators]) and
    not ((Data.Profile <> nil) and (Data.Profile.DatabaseType = dtPostgreSQL) and (Data.Category = sokTriggers));
  miSepObj.Visible := miEditObject.Visible or miViewObjectDDL.Visible or miViewObjectData.Visible or
    miNewObject.Visible or miRefreshCategory.Visible or miDropObject.Visible;

  miDisconnectConn.Enabled := HasConn and (Summary.ActiveCount > 0);
  if Summary.ActiveCount > 1 then
    miDisconnectConn.Caption := Format('Desconectar (%d sessões ativas)', [Summary.ActiveCount])
  else if Summary.ActiveCount = 1 then
    miDisconnectConn.Caption := 'Desconectar (1 sessão ativa)'
  else
    miDisconnectConn.Caption := 'Desconectar';

  miEditConn.Enabled := HasConn;
  if miNewFolder <> nil then
    miNewFolder.Visible := True;
  if miNewConnInFolder <> nil then
    miNewConnInFolder.Visible := (not HasConn) and HasFolder;
  if miRenameFolder <> nil then
    miRenameFolder.Visible := (not HasConn) and HasFolder;
  if miDeleteFolder <> nil then
    miDeleteFolder.Visible := (not HasConn) and HasFolder;
  if miMoveToFolder <> nil then
    miMoveToFolder.Visible := HasConn;
  if miSelectSchema <> nil then
  begin
    miSelectSchema.Visible := (Profile <> nil) and (Profile.DatabaseType = dtPostgreSQL) and
      not ((Data <> nil) and (Data.Kind = enkConnection) and (Trim(Profile.Database) = ''));
    if miSelectSchema.Visible then
      miSelectSchema.Caption := Format('Selecionar Schema (%s)...', [Profile.EffectiveSchema]);
  end;
  miDuplicateConn.Enabled := HasConn;
  miDeleteConn.Enabled := HasConn;
  miMoveConnUp.Enabled := HasConn and (FindAdjacentVisibleSibling(ConnNode, -1) <> nil);
  miMoveConnDown.Enabled := HasConn and (FindAdjacentVisibleSibling(ConnNode, 1) <> nil);
  miSortAsc.Enabled := HasMultiple;
  miSortDesc.Enabled := HasMultiple;
end;

procedure TMainForm.miOpenSqlTabClick(Sender: TObject);
var
  ConnNode: TTreeNode;
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile = nil then
  begin
    ConnNode := SelectedConnectionNode;
    if (ConnNode <> nil) and (ConnNode.Data <> nil) then
      Profile := TExplorerNodeData(ConnNode.Data).Profile;
  end;
  if Profile <> nil then
    OpenNewEditorTab(Profile.Id, Profile.Name, Profile);
end;

procedure TMainForm.miScriptExecClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    OpenScriptExecutorTab(Profile.Id)
  else
    OpenScriptExecutorTab;
end;

procedure TMainForm.miMonitorDbClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    OpenMonitorTab(Profile.Id)
  else
    OpenMonitorTab;
end;

procedure TMainForm.miCompareDbClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    OpenComparerTab(Profile.Id)
  else
    OpenComparerTab;
end;

procedure TMainForm.miMaintenanceDbClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    OpenMaintenanceDialog(mtkBackup, Profile.Id)
  else
    OpenMaintenanceDialog(mtkBackup);
end;

procedure TMainForm.miEditObjectClick(Sender: TObject);
var
  Data: TExplorerNodeData;
  WasDropped: Boolean;
begin
  Data := SelectedNodeData;
  if (Data = nil) or (Data.Kind <> enkObject) or (Data.Profile = nil) then
    Exit;

  if Data.Category = sokTables then
    OpenTableEditorTab(Data.Profile, Data.ObjectName)
  else if Data.Category = sokGenerators then
  begin
    if TGeneratorForm.Execute(Data.Profile, Data.ObjectName, FManageObjects, WasDropped) and WasDropped then
      ReloadCategoryForProfile(Data.Profile.Id, sokGenerators);
  end
  else if Data.Category in [sokViews, sokProcedures, sokTriggers] then
    OpenObjectEditorTab(Data.Profile, Data.Category, Data.ObjectName, False);
end;

procedure TMainForm.miViewObjectDDLClick(Sender: TObject);
var
  Data: TExplorerNodeData;
begin
  Data := SelectedNodeData;
  if (Data = nil) or (Data.Kind <> enkObject) or (Data.Profile = nil) then
    Exit;

  OpenObjectEditorTab(Data.Profile, Data.Category, Data.ObjectName, False);
end;

procedure TMainForm.miViewObjectDataClick(Sender: TObject);
var
  Data: TExplorerNodeData;
  Frame: TSqlEditorFrame;
begin
  Data := SelectedNodeData;
  if (Data = nil) or (Data.Kind <> enkObject) or (Data.Profile = nil) then
    Exit;

  if Data.Category in [sokTables, sokViews] then
  begin
    Frame := OpenNewEditorTab(Data.Profile.Id, Data.ObjectName);
    Frame.SetSqlText('SELECT * FROM ' + QuoteDbIdent(Data.Profile.DatabaseType, Data.ObjectName));
    Frame.ExecuteCurrentSQL;
  end;
end;

procedure TMainForm.miNewObjectClick(Sender: TObject);
var
  Data: TExplorerNodeData;
  NewName, Msg: string;
  WasDropped: Boolean;
begin
  Data := SelectedNodeData;
  if (Data = nil) or (Data.Profile = nil) or not (Data.Kind in [enkCategory, enkObject]) then
    Exit;

  if Data.Category = sokGenerators then
  begin
    NewName := 'GEN_NOVO_GENERATOR';
    if Data.Profile.DatabaseType = dtPostgreSQL then
      NewName := 'seq_nova_sequence';
    if not InputQuery('Novo Generator / Sequence', 'Nome:', NewName) then
      Exit;
    NewName := Trim(NewName);
    if NewName = '' then
      Exit;

    if FManageObjects.CreateGenerator(Data.Profile, NewName, 0, Msg) then
    begin
      ReloadCategoryForProfile(Data.Profile.Id, sokGenerators);
      StatusBar1.SimpleText := Msg;
      if TGeneratorForm.Execute(Data.Profile, NewName, FManageObjects, WasDropped) and WasDropped then
        ReloadCategoryForProfile(Data.Profile.Id, sokGenerators);
    end
    else
      MessageDlg('Erro ao criar Generator', Msg, mtError, [mbOK], 0);
  end
  else if Data.Category in [sokViews, sokProcedures, sokTriggers] then
    OpenObjectEditorTab(Data.Profile, Data.Category, '', True);
end;

procedure TMainForm.miRefreshCategoryClick(Sender: TObject);
var
  Node: TTreeNode;
  Data: TExplorerNodeData;
begin
  Node := tvConnections.Selected;
  if (Node = nil) or (Node.Data = nil) then
    Exit;
  Data := TExplorerNodeData(Node.Data);
  if Data.Kind = enkObject then
    Node := Node.Parent;
  ReloadCategoryNode(Node);
end;

procedure TMainForm.miDropObjectClick(Sender: TObject);
var
  Data: TExplorerNodeData;
  Msg: string;
begin
  Data := SelectedNodeData;
  if (Data = nil) or (Data.Kind <> enkObject) or (Data.Profile = nil) then
    Exit;

  if Data.Category = sokTables then
  begin
    if MessageDlg('Confirmar Exclusão da Tabela (1/2)',
      Format('Deseja excluir permanentemente a tabela "%s" e TODOS os seus dados de "%s"?',
        [Data.ObjectName, Data.Profile.Name]),
      mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    if MessageDlg('Confirmação Final — Exclusão Irreversível (2/2)',
      Format('ATENÇÃO: Esta operação NÃO pode ser desfeita (DROP TABLE %s).' + LineEnding + LineEnding +
        'Confirma em definitivo a EXCLUSÃO da tabela "%s"?', [Data.ObjectName, Data.ObjectName]),
      mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end
  else
  begin
    if MessageDlg('Confirmar Exclusão',
      Format('Deseja realmente excluir "%s" de "%s"?', [Data.ObjectName, Data.Profile.Name]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  if FManageObjects.DropObject(Data.Profile, Data.Category, Data.ObjectName, Msg) then
  begin
    ReloadCategoryForProfile(Data.Profile.Id, Data.Category);
    StatusBar1.SimpleText := Msg;
  end
  else
    MessageDlg('Erro ao excluir objeto', Msg, mtError, [mbOK], 0);
end;

procedure TMainForm.miDuplicateConnClick(Sender: TObject);
var
  Current, Duplicated: TConnectionProfile;
begin
  Current := SelectedProfile;
  if Current = nil then
  begin
    MessageDlg('Aviso', 'Selecione uma conexão para duplicar.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Duplicated := Current.Clone;
  try
    Duplicated.Id := '';
    Duplicated.Name := Current.Name + ' (Cópia)';
    if TConnectionForm.Execute(Duplicated, FTestConnection, FManageConnections) then
    begin
      FManageConnections.Save(Duplicated);
      RefreshConnectionsTree(Duplicated.Id);
      StatusBar1.SimpleText := 'Conexão duplicada: ' + Duplicated.Name;
    end;
  finally
    Duplicated.Free;
  end;
end;

procedure TMainForm.miSelectSchemaClick(Sender: TObject);
var
  Profile, UpdatedProfile: TConnectionProfile;
  Schemas: TStringList;
  ErrMsg, ChosenSchema: string;
  Dlg: TForm;
  Lbl: TLabel;
  Lb: TListBox;
  BtnOk, BtnCancel: TButton;
  PnlBtn: TPanel;
  Idx: Integer;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (Profile.DatabaseType <> dtPostgreSQL) then
    Exit;

  Schemas := TStringList.Create;
  try
    Screen.Cursor := crHourGlass;
    try
      if not FTestConnection.ListPostgresSchemas(Profile, Schemas, ErrMsg) then
      begin
        MessageDlg('Selecionar Schema', 'Erro ao listar schemas: ' + ErrMsg, mtError, [mbOK], 0);
        Exit;
      end;
    finally
      Screen.Cursor := crDefault;
    end;

    if Schemas.Count = 0 then
    begin
      MessageDlg('Selecionar Schema', 'Nenhum schema encontrado no banco.', mtInformation, [mbOK], 0);
      Exit;
    end;

    Dlg := TForm.CreateNew(nil);
    try
      Dlg.Caption := 'Selecionar Schema - ' + Profile.Name;
      Dlg.Position := poScreenCenter;
      Dlg.BorderStyle := bsDialog;
      Dlg.Width := 340;
      Dlg.Height := 360;

      Lbl := TLabel.Create(Dlg);
      Lbl.Parent := Dlg;
      Lbl.Align := alTop;
      Lbl.BorderSpacing.Around := 10;
      Lbl.Caption := 'Escolha o schema padrão para esta conexão:';

      PnlBtn := TPanel.Create(Dlg);
      PnlBtn.Parent := Dlg;
      PnlBtn.Align := alBottom;
      PnlBtn.Height := 42;
      PnlBtn.BevelOuter := bvNone;

      BtnCancel := TButton.Create(Dlg);
      BtnCancel.Parent := PnlBtn;
      BtnCancel.Caption := 'Cancelar';
      BtnCancel.ModalResult := mrCancel;
      BtnCancel.Cancel := True;
      BtnCancel.Width := 85;
      BtnCancel.Height := 26;
      BtnCancel.Left := PnlBtn.Width - 95;
      BtnCancel.Top := 8;
      BtnCancel.Anchors := [akTop, akRight];

      BtnOk := TButton.Create(Dlg);
      BtnOk.Parent := PnlBtn;
      BtnOk.Caption := 'Selecionar';
      BtnOk.ModalResult := mrOk;
      BtnOk.Default := True;
      BtnOk.Width := 85;
      BtnOk.Height := 26;
      BtnOk.Left := BtnCancel.Left - 93;
      BtnOk.Top := 8;
      BtnOk.Anchors := [akTop, akRight];

      Lb := TListBox.Create(Dlg);
      Lb.Parent := Dlg;
      Lb.Align := alClient;
      Lb.BorderSpacing.Left := 10;
      Lb.BorderSpacing.Right := 10;
      Lb.Items.Assign(Schemas);
      Idx := Lb.Items.IndexOf(Profile.EffectiveSchema);
      if Idx < 0 then
        Idx := 0;
      if (Idx >= 0) and (Idx < Lb.Items.Count) then
        Lb.ItemIndex := Idx;

      if (Dlg.ShowModal = mrOk) and (Lb.ItemIndex >= 0) then
      begin
        ChosenSchema := Lb.Items[Lb.ItemIndex];
        if (SelectedNodeData <> nil) and (SelectedNodeData.Kind in [enkDatabase, enkCategory, enkObject]) and
           (Pos('::', Profile.Id) > 0) then
        begin
          Profile.Schema := ChosenSchema;
          // Atualiza nó enkDatabase correspondente e recarrega categorias se já expandido
          while (tvConnections.Selected <> nil) and (tvConnections.Selected.Data <> nil) and
                (TExplorerNodeData(tvConnections.Selected.Data).Kind <> enkDatabase) do
            tvConnections.Selected := tvConnections.Selected.Parent;
          if (tvConnections.Selected <> nil) and (tvConnections.Selected.Data <> nil) and
             (TExplorerNodeData(tvConnections.Selected.Data).Kind = enkDatabase) then
          begin
            tvConnections.Selected.Text := Format('%s [%s]', [Profile.Database, ChosenSchema]);
            TExplorerNodeData(tvConnections.Selected.Data).Loaded := False;
            if tvConnections.Selected.Expanded then
            begin
              tvConnections.Selected.Collapse(False);
              tvConnections.Selected.Expand(False);
            end;
          end;
          StatusBar1.SimpleText := Format('Schema ativo de "%s" alterado para "%s".', [Profile.Name, ChosenSchema]);
        end
        else
        begin
          UpdatedProfile := Profile.Clone;
          try
            UpdatedProfile.Schema := ChosenSchema;
            FManageConnections.Save(UpdatedProfile);
          finally
            UpdatedProfile.Free;
          end;
          RefreshConnectionsTree(Profile.Id);
          StatusBar1.SimpleText := Format('Schema ativo de "%s" alterado para "%s".', [Profile.Name, ChosenSchema]);
        end;
      end;
    finally
      Dlg.Free;
    end;
  finally
    Schemas.Free;
  end;
end;

procedure TMainForm.miDisconnectConnClick(Sender: TObject);
var
  ConnNode: TTreeNode;
  Profile: TConnectionProfile;
  Summary: TProfileSessionSummary;
  Details: string;
  DisconnectedCount: Integer;
begin
  ConnNode := SelectedConnectionNode;
  if (ConnNode = nil) or (ConnNode.Data = nil) then
    Exit;

  Profile := TExplorerNodeData(ConnNode.Data).Profile;
  if Profile = nil then
    Exit;

  Summary := GetProfileSessionSummary(Profile.Id);
  if Summary.ActiveCount <= 0 then
  begin
    StatusBar1.SimpleText := Format('A conexão "%s" já está desconectada.', [Profile.Name]);
    Exit;
  end;

  if (Summary.BusyCount > 0) or (Summary.InTransactionCount > 0) then
  begin
    Details := Format('A conexão "%s" possui:', [Profile.Name]) + LineEnding;
    if Summary.BusyCount > 0 then
      Details := Details + Format('- %d operação(ões) em execução em segundo plano (serão canceladas)', [Summary.BusyCount]) + LineEnding;
    if Summary.InTransactionCount > 0 then
      Details := Details + Format('- %d transação(ões) aberta(s) sem commit (serão desfeitas com ROLLBACK)', [Summary.InTransactionCount]) + LineEnding;
    Details := Details + LineEnding + 'Deseja desconectar mesmo assim?';

    if MessageDlg('Confirmar Desconexão', Details, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;

  DisconnectedCount := DisconnectProfileSessions(Profile.Id);
  if DisconnectedCount = 1 then
    StatusBar1.SimpleText := Format('Conexão "%s" desconectada (1 sessão encerrada).', [Profile.Name])
  else
    StatusBar1.SimpleText := Format('Conexão "%s" desconectada (%d sessões encerradas).', [Profile.Name, DisconnectedCount]);
end;

procedure TMainForm.miSortAscClick(Sender: TObject);
begin
  SortConnections(True);
  FNextSortAsc := False;
  UpdateConnectionButtonsState;
end;

procedure TMainForm.miSortDescClick(Sender: TObject);
begin
  SortConnections(False);
  FNextSortAsc := True;
  UpdateConnectionButtonsState;
end;

procedure TMainForm.miExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.miToolBackupClick(Sender: TObject);
begin
  OpenMaintenanceDialog(mtkBackup);
end;

procedure TMainForm.miToolRestoreClick(Sender: TObject);
begin
  OpenMaintenanceDialog(mtkRestore);
end;

procedure TMainForm.miToolRepairClick(Sender: TObject);
begin
  OpenMaintenanceDialog(mtkRepair);
end;

procedure TMainForm.HandleOpenSqlFromHistory(const AProfileId, ASqlText: string);
var
  Frame: TSqlEditorFrame;
begin
  Frame := OpenNewEditorTab(AProfileId, '');
  if Frame <> nil then
    Frame.SetSqlText(ASqlText);
end;

procedure TMainForm.miToolQueryHistoryClick(Sender: TObject);
begin
  TQueryHistoryForm.Execute(FQueryHistory, @HandleOpenSqlFromHistory);
end;

procedure TMainForm.miToolReplicationClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  InitialId: string;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    InitialId := Profile.Id
  else
    InitialId := '';
  TReplicationForm.Execute(FFactory, FConnections, InitialId);
end;

procedure TMainForm.miToolAboutClick(Sender: TObject);
var
  Dlg: TForm;
  Img: TImage;
  Pic: TPicture;
  RS: TResourceStream;
  LblInfo: TLabel;
  BtnClose, BtnDocs: TButton;
begin
  Dlg := TForm.CreateNew(nil);
  try
    Dlg.Caption := 'Sobre - Multi-DB SQL Editor';
    Dlg.Position := poScreenCenter;
    Dlg.BorderStyle := bsDialog;
    Dlg.Color := $00221811;
    Dlg.Width := 560;
    Dlg.Height := 395;

    Img := TImage.Create(Dlg);
    Img.Parent := Dlg;
    Img.Align := alTop;
    Img.Height := 290;
    Img.Proportional := True;
    Img.Center := True;
    Img.Stretch := True;
    try
      RS := TResourceStream.Create(HInstance, 'LOGO_BANNER', PChar(10));
      try
        Pic := TPicture.Create;
        try
          Pic.LoadFromStream(RS);
          Img.Picture.Assign(Pic);
        finally
          Pic.Free;
        end;
      finally
        RS.Free;
      end;
    except
    end;

    LblInfo := TLabel.Create(Dlg);
    LblInfo.Parent := Dlg;
    LblInfo.Left := 16;
    LblInfo.Top := 302;
    LblInfo.Font.Color := clWhite;
    LblInfo.Caption := 'Multi-DB SQL Editor — PostgreSQL • Firebird • MariaDB';

    BtnClose := TButton.Create(Dlg);
    BtnClose.Parent := Dlg;
    BtnClose.Caption := 'Fechar';
    BtnClose.ModalResult := mrClose;
    BtnClose.Default := True;
    BtnClose.Cancel := True;
    BtnClose.Width := 90;
    BtnClose.Height := 28;
    BtnClose.Left := Dlg.ClientWidth - 106;
    BtnClose.Top := 348;

    BtnDocs := TButton.Create(Dlg);
    BtnDocs.Parent := Dlg;
    BtnDocs.Caption := 'Ver Documentação Completa (F1)...';
    BtnDocs.Width := 230;
    BtnDocs.Height := 28;
    BtnDocs.Left := 16;
    BtnDocs.Top := 348;
    BtnDocs.OnClick := @miToolDocsClick;

    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.ApplyVisualTheme;
var
  ImgLogo: TImage;
  LblTitle, LblSub: TLabel;
  Ico: TIcon;
begin
  Color := $00F0F3F7;
  pnlLeft.Color := $00F7F9FC;
  pnlMain.Color := $00F0F3F7;
  pnlEditorBar.Color := $00F4F6F9;
  pnlConnActions.Color := $00F4F6F9;
  pnlConnOrder.Color := $00F4F6F9;
  pnlTreeFilter.Color := $00F7F9FC;
  tvConnections.BackgroundColor := $00FAFBFD;
  tvConnections.OnCustomDrawItem := @tvConnectionsCustomDrawItem;

  if pnlBrandHeader = nil then
  begin
    pnlBrandHeader := TPanel.Create(Self);
    pnlBrandHeader.Parent := Self;
    pnlBrandHeader.Align := alTop;
    pnlBrandHeader.Top := 0;
    pnlBrandHeader.Height := 40;
    pnlBrandHeader.BevelOuter := bvNone;
    pnlBrandHeader.Color := $002C1E14;

    ImgLogo := TImage.Create(pnlBrandHeader);
    ImgLogo.Parent := pnlBrandHeader;
    ImgLogo.Left := 10;
    ImgLogo.Top := 4;
    ImgLogo.Width := 32;
    ImgLogo.Height := 32;
    ImgLogo.Proportional := True;
    ImgLogo.Center := True;
    ImgLogo.Stretch := True;
    try
      Ico := TIcon.Create;
      try
        Ico.LoadFromResourceName(HInstance, 'MAINICON');
        ImgLogo.Picture.Assign(Ico);
      finally
        Ico.Free;
      end;
    except
    end;

    LblTitle := TLabel.Create(pnlBrandHeader);
    LblTitle.Parent := pnlBrandHeader;
    LblTitle.Left := 50;
    LblTitle.Top := 5;
    LblTitle.Font.Color := clWhite;
    LblTitle.Font.Style := [fsBold];
    LblTitle.Font.Size := 10;
    LblTitle.Caption := 'MULTI-DB SQL EDITOR';

    LblSub := TLabel.Create(pnlBrandHeader);
    LblSub.Parent := pnlBrandHeader;
    LblSub.Left := 50;
    LblSub.Top := 22;
    LblSub.Font.Color := $00E8C298;
    LblSub.Font.Size := 8;
    LblSub.Caption := 'PostgreSQL  •  Firebird  •  MariaDB';
  end;
end;

procedure TMainForm.tvConnectionsCustomDrawItem(
  Sender: TCustomTreeView;
  Node: TTreeNode;
  State: TCustomDrawState;
  var DefaultDraw: Boolean
);
var
  Data: TExplorerNodeData;
begin
  DefaultDraw := True;
  if (Node = nil) or (Node.Data = nil) or (cdsSelected in State) then
    Exit;
  Data := TExplorerNodeData(Node.Data);
  if Data.Kind = enkGroup then
  begin
    Sender.Canvas.Font.Style := [fsBold];
    if SameText(Node.Text, 'Firebird') then
      Sender.Canvas.Font.Color := $001F57D6
    else if SameText(Node.Text, 'PostgreSQL') then
      Sender.Canvas.Font.Color := $00B86A22
    else if SameText(Node.Text, 'MariaDB') then
      Sender.Canvas.Font.Color := $00807015;
  end
  else if Data.Kind = enkFolder then
  begin
    Sender.Canvas.Font.Style := [fsBold];
    Sender.Canvas.Font.Color := $00266B9E;
  end
  else if Data.Kind in [enkConnection, enkDatabase] then
  begin
    Sender.Canvas.Font.Style := [fsBold];
    if (Data.Profile <> nil) and (Data.Profile.EnvironmentTextColor <> 0) then
      Sender.Canvas.Font.Color := TColor(Data.Profile.EnvironmentTextColor);
  end;
end;

procedure TMainForm.miToolMetadataSearchClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  InitialId: string;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    InitialId := Profile.Id
  else
    InitialId := '';
  TMetadataSearchForm.Execute(FFactory, FConnections, InitialId, @HandleOpenTableDependency);
end;

procedure TMainForm.miToolIndexManagerClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  InitialId: string;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    InitialId := Profile.Id
  else
    InitialId := '';
  TIndexManagerForm.Execute(FFactory, FConnections, InitialId, @HandleOpenTableDependency);
end;

procedure TMainForm.miToolImportDataClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  TableName: string;
  NodeData: TExplorerNodeData;
begin
  Profile := SelectedProfile;
  TableName := '';
  NodeData := SelectedNodeData;
  if (NodeData <> nil) and (NodeData.Kind = enkObject) and (NodeData.Category = sokTables) then
    TableName := NodeData.ObjectName;
  TDataImportForm.Execute(FFactory, FConnections, Profile, TableName);
end;

procedure TMainForm.miToolDocsClick(Sender: TObject);
begin
  TDocumentationForm.Execute;
end;

procedure TMainForm.miNewFolderClick(Sender: TObject);
var
  FolderName: string;
begin
  FolderName := '';
  if not InputQuery('Nova Pasta de Conexões', 'Nome da pasta:', FolderName) then
    Exit;

  FolderName := Trim(FolderName);
  if FolderName = '' then
    Exit;

  try
    FManageConnections.AddFolder(FolderName);
    RefreshConnectionsTree('', FolderName);
    StatusBar1.SimpleText := Format('Pasta "%s" criada.', [FolderName]);
  except
    on E: Exception do
      MessageDlg('Erro ao criar pasta', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.miNewConnInFolderClick(Sender: TObject);
begin
  btnNewConnClick(Sender);
end;

procedure TMainForm.miRenameFolderClick(Sender: TObject);
var
  FolderNode: TTreeNode;
  Data: TExplorerNodeData;
  OldName, NewName: string;
begin
  FolderNode := SelectedFolderNode;
  if (FolderNode = nil) or (FolderNode.Data = nil) then
    Exit;

  Data := TExplorerNodeData(FolderNode.Data);
  OldName := Data.FolderName;
  NewName := OldName;
  if not InputQuery('Renomear Pasta', 'Novo nome da pasta:', NewName) then
    Exit;

  NewName := Trim(NewName);
  if (NewName = '') or SameText(OldName, NewName) then
    Exit;

  try
    FManageConnections.RenameFolder(OldName, NewName);
    RefreshConnectionsTree('', NewName);
    StatusBar1.SimpleText := Format('Pasta "%s" renomeada para "%s".', [OldName, NewName]);
  except
    on E: Exception do
      MessageDlg('Erro ao renomear pasta', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.miDeleteFolderClick(Sender: TObject);
var
  FolderNode: TTreeNode;
  Data: TExplorerNodeData;
  ConnCount: Integer;
  Msg: string;
begin
  FolderNode := SelectedFolderNode;
  if (FolderNode = nil) or (FolderNode.Data = nil) then
    Exit;

  Data := TExplorerNodeData(FolderNode.Data);
  ConnCount := FolderNode.Count;
  if ConnCount > 0 then
    Msg := Format('Deseja excluir a pasta "%s"? As %d conexão(ões) dentro dela serão mantidas e movidas para a raiz.',
      [Data.FolderName, ConnCount])
  else
    Msg := Format('Deseja excluir a pasta vazia "%s"?', [Data.FolderName]);

  if MessageDlg('Excluir Pasta', Msg, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  FManageConnections.DeleteFolder(Data.FolderName);
  RefreshConnectionsTree;
  StatusBar1.SimpleText := Format('Pasta "%s" excluída.', [Data.FolderName]);
end;

procedure TMainForm.miMoveToFolderClick(Sender: TObject);
var
  Profile, MovedProfile: TConnectionProfile;
  Folders: TStringList;
  Dlg: TForm;
  Lbl: TLabel;
  CbFolder: TComboBox;
  BtnOk, BtnCancel: TButton;
  ChosenFolder: string;
begin
  Profile := SelectedProfile;
  if Profile = nil then
    Exit;

  Folders := TStringList.Create;
  try
    FManageConnections.GetFolders(Folders);

    Dlg := TForm.CreateNew(nil);
    try
      Dlg.Caption := 'Mover Conexão para Pasta - ' + Profile.Name;
      Dlg.Position := poScreenCenter;
      Dlg.BorderStyle := bsDialog;
      Dlg.ClientWidth := 380;
      Dlg.ClientHeight := 130;

      Lbl := TLabel.Create(Dlg);
      Lbl.Parent := Dlg;
      Lbl.Left := 14;
      Lbl.Top := 14;
      Lbl.Caption := 'Escolha uma pasta, digite um novo nome ou deixe em branco para Raiz:';

      CbFolder := TComboBox.Create(Dlg);
      CbFolder.Parent := Dlg;
      CbFolder.Left := 14;
      CbFolder.Top := 34;
      CbFolder.Width := 352;
      CbFolder.Style := csDropDown;
      CbFolder.Items.Assign(Folders);
      CbFolder.Text := Trim(Profile.Folder);

      BtnCancel := TButton.Create(Dlg);
      BtnCancel.Parent := Dlg;
      BtnCancel.Caption := 'Cancelar';
      BtnCancel.ModalResult := mrCancel;
      BtnCancel.Cancel := True;
      BtnCancel.Width := 88;
      BtnCancel.Height := 28;
      BtnCancel.Left := 278;
      BtnCancel.Top := 82;

      BtnOk := TButton.Create(Dlg);
      BtnOk.Parent := Dlg;
      BtnOk.Caption := 'Mover';
      BtnOk.ModalResult := mrOk;
      BtnOk.Default := True;
      BtnOk.Width := 88;
      BtnOk.Height := 28;
      BtnOk.Left := 182;
      BtnOk.Top := 82;

      if Dlg.ShowModal = mrOk then
      begin
        ChosenFolder := Trim(CbFolder.Text);
        MovedProfile := Profile.Clone;
        try
          MovedProfile.Folder := ChosenFolder;
          FManageConnections.Save(MovedProfile);
        finally
          MovedProfile.Free;
        end;
        RefreshConnectionsTree(Profile.Id);
        if ChosenFolder = '' then
          StatusBar1.SimpleText := Format('Conexão "%s" movida para a raiz.', [Profile.Name])
        else
          StatusBar1.SimpleText := Format('Conexão "%s" movida para a pasta "%s".', [Profile.Name, ChosenFolder]);
      end;
    finally
      Dlg.Free;
    end;
  finally
    Folders.Free;
  end;
end;

end.
