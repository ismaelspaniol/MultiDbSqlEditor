unit Presentation.MainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, Forms, Controls, Graphics, Dialogs,
  ComCtrls, ExtCtrls, StdCtrls,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.Interfaces,
  Application.TestConnectionUseCase,
  Application.ManageConnectionsUseCase,
  Application.ExecuteQueryUseCase,
  Application.BrowseSchemaUseCase,
  Infrastructure.ProviderFactory,
  Infrastructure.JsonConnectionRepository,
  Infrastructure.JsonWorkspaceRepository,
  Infrastructure.FirebirdSqlDbProvider,
  Infrastructure.MormotPostgresProvider,
  Presentation.ConnectionForm,
  Presentation.SqlEditorFrame;

type
  TExplorerNodeKind = (enkGroup, enkConnection, enkCategory, enkObject);

  TExplorerNodeData = class
  public
    Kind: TExplorerNodeKind;
    Profile: TConnectionProfile;
    Category: TSchemaObjectKind;
    ObjectName: string;
    Loaded: Boolean;
    TotalCount: Integer;
  end;

  TExplorerNodeDataList = specialize TObjectList<TExplorerNodeData>;

  { TMainForm }
  TMainForm = class(TForm)
    pnlLeft: TPanel;
    pnlConnActions: TPanel;
    btnNewConn: TButton;
    btnEditConn: TButton;
    btnDeleteConn: TButton;
    pnlMain: TPanel;
    pnlEditorBar: TPanel;
    btnNewTab: TButton;
    btnCloseTab: TButton;
    Splitter1: TSplitter;
    lblConnections: TLabel;
    pnlTreeFilter: TPanel;
    edtTreeFilter: TEdit;
    btnClearFilter: TButton;
    tvConnections: TTreeView;
    pgEditors: TPageControl;
    StatusBar1: TStatusBar;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnNewConnClick(Sender: TObject);
    procedure btnEditConnClick(Sender: TObject);
    procedure btnDeleteConnClick(Sender: TObject);
    procedure btnNewTabClick(Sender: TObject);
    procedure btnCloseTabClick(Sender: TObject);
    procedure edtTreeFilterChange(Sender: TObject);
    procedure btnClearFilterClick(Sender: TObject);
    procedure tvConnectionsDblClick(Sender: TObject);
    procedure tvConnectionsExpanding(Sender: TObject; Node: TTreeNode;
      var AllowExpansion: Boolean);
  private
    FFactory: IDatabaseProviderFactory;
    FRepository: IConnectionRepository;
    FWorkspaceRepo: TJsonWorkspaceRepository;
    FManageConnections: TManageConnectionsUseCase;
    FTestConnection: TTestConnectionUseCase;
    FExecuteQuery: TExecuteQueryUseCase;
    FBrowseSchema: TBrowseSchemaUseCase;
    FConnections: TConnectionProfileList;
    FNodeDataList: TExplorerNodeDataList;
    FTabCounter: Integer;
    procedure InitializeDependencies;
    procedure RefreshConnectionsTree;
    procedure ApplyTreeFilter;
    procedure RefreshOpenTabsConnections;
    procedure RestoreWorkspace;
    procedure SaveWorkspace;
    function OpenNewEditorTab(const AInitialProfileId: string = ''; const ACaption: string = ''): TSqlEditorFrame;
    function CreateNodeData(
      const AKind: TExplorerNodeKind;
      const AProfile: TConnectionProfile = nil;
      const ACategory: TSchemaObjectKind = sokTables;
      const AObjectName: string = ''
    ): TExplorerNodeData;
    function SelectedNodeData: TExplorerNodeData;
    function SelectedProfile: TConnectionProfile;
  public
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'Multi-DB SQL Editor (Firebird & PostgreSQL)';
  FTabCounter := 0;
  FNodeDataList := TExplorerNodeDataList.Create(True);
  InitializeDependencies;
  RefreshConnectionsTree;
  RestoreWorkspace;
  StatusBar1.SimpleText := 'Pronto (F9 executa a consulta | Ctrl+Espaço autocompleta)';
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  SaveWorkspace;
  FreeAndNil(FNodeDataList);
  FreeAndNil(FWorkspaceRepo);
  FreeAndNil(FConnections);
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
  FFactory := ConcreteFactory;

  FRepository := TJsonConnectionRepository.Create;
  FWorkspaceRepo := TJsonWorkspaceRepository.Create;
  FManageConnections := TManageConnectionsUseCase.Create(FRepository);
  FTestConnection := TTestConnectionUseCase.Create(FFactory);
  FExecuteQuery := TExecuteQueryUseCase.Create;
  FBrowseSchema := TBrowseSchemaUseCase.Create(FFactory);
end;

function TMainForm.CreateNodeData(
  const AKind: TExplorerNodeKind;
  const AProfile: TConnectionProfile;
  const ACategory: TSchemaObjectKind;
  const AObjectName: string
): TExplorerNodeData;
begin
  Result := TExplorerNodeData.Create;
  Result.Kind := AKind;
  Result.Profile := AProfile;
  Result.Category := ACategory;
  Result.ObjectName := AObjectName;
  Result.Loaded := False;
  Result.TotalCount := 0;
  FNodeDataList.Add(Result);
end;

procedure TMainForm.RefreshConnectionsTree;
var
  RootFirebird, RootPostgres, ConnNode: TTreeNode;
  Profile: TConnectionProfile;
begin
  tvConnections.Items.BeginUpdate;
  try
    tvConnections.Items.Clear;
    FNodeDataList.Clear;
    FreeAndNil(FConnections);
    FConnections := FManageConnections.ListAll;

    RootFirebird := tvConnections.Items.AddObject(nil, 'Firebird', CreateNodeData(enkGroup));
    RootPostgres := tvConnections.Items.AddObject(nil, 'PostgreSQL', CreateNodeData(enkGroup));

    for Profile in FConnections do
    begin
      if Profile.DatabaseType = dtFirebird then
        ConnNode := tvConnections.Items.AddChildObject(
          RootFirebird, Profile.Name, CreateNodeData(enkConnection, Profile)
        )
      else
        ConnNode := tvConnections.Items.AddChildObject(
          RootPostgres, Profile.Name, CreateNodeData(enkConnection, Profile)
        );
      ConnNode.HasChildren := True;
    end;

    RootFirebird.Expand(False);
    RootPostgres.Expand(False);
  finally
    tvConnections.Items.EndUpdate;
  end;

  ApplyTreeFilter;
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
      if (Data.Kind = enkCategory) and Data.Loaded then
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
      enkConnection:
        SelfMatches := Pos(FilterText, LowerCase(Data.Profile.Name)) > 0;
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
        TSqlEditorFrame(Tab.Controls[J]).RefreshConnections(FConnections);
    end;
  end;
end;

function TMainForm.OpenNewEditorTab(const AInitialProfileId: string; const ACaption: string): TSqlEditorFrame;
var
  Tab: TTabSheet;
begin
  Inc(FTabCounter);
  Tab := TTabSheet.Create(pgEditors);
  Tab.PageControl := pgEditors;
  if Trim(ACaption) <> '' then
    Tab.Caption := ACaption
  else
    Tab.Caption := Format('SQL %d', [FTabCounter]);

  Result := TSqlEditorFrame.Create(Tab);
  Result.Name := Format('SqlEditorFrame_%d', [FTabCounter]);
  Result.Parent := Tab;
  Result.Align := alClient;
  Result.Initialize(FFactory, FExecuteQuery, FConnections, AInitialProfileId);

  pgEditors.ActivePage := Tab;
end;

procedure TMainForm.RestoreWorkspace;
var
  State: TWorkspaceState;
  I: Integer;
  Frame: TSqlEditorFrame;
begin
  State := FWorkspaceRepo.Load;
  try
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
begin
  if FWorkspaceRepo = nil then
    Exit;

  State := TWorkspaceState.Create;
  try
    State.ActiveTabIndex := pgEditors.ActivePageIndex;
    for I := 0 to pgEditors.PageCount - 1 do
    begin
      Tab := pgEditors.Pages[I];
      for J := 0 to Tab.ControlCount - 1 do
      begin
        if Tab.Controls[J] is TSqlEditorFrame then
        begin
          Frame := TSqlEditorFrame(Tab.Controls[J]);
          Item.Title := Tab.Caption;
          Item.ProfileId := Frame.ActiveProfileId;
          Item.SqlText := Frame.SqlText;
          Item.BatchSize := Frame.BatchSizeText;
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
  CatNode: TTreeNode;
  Objects: TStringList;
  I: Integer;
begin
  if (Node = nil) or (Node.Data = nil) then
    Exit;

  Data := TExplorerNodeData(Node.Data);
  if Data.Loaded then
    Exit;

  if Data.Kind = enkConnection then
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
              Objects[I],
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
      ApplyTreeFilter;
  end;
end;

procedure TMainForm.btnNewConnClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := TConnectionProfile.Create;
  try
    if TConnectionForm.Execute(Profile, FTestConnection) then
    begin
      FManageConnections.Save(Profile);
      RefreshConnectionsTree;
      StatusBar1.SimpleText := 'Conexão salva: ' + Profile.Name;
    end;
  finally
    Profile.Free;
  end;
end;

procedure TMainForm.btnEditConnClick(Sender: TObject);
var
  Current, Editable: TConnectionProfile;
begin
  Current := SelectedProfile;
  if Current = nil then
  begin
    MessageDlg('Aviso', 'Selecione uma conexão para editar.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Editable := Current.Clone;
  try
    if TConnectionForm.Execute(Editable, FTestConnection) then
    begin
      FManageConnections.Save(Editable);
      RefreshConnectionsTree;
      StatusBar1.SimpleText := 'Conexão atualizada: ' + Editable.Name;
    end;
  finally
    Editable.Free;
  end;
end;

procedure TMainForm.btnDeleteConnClick(Sender: TObject);
var
  Current: TConnectionProfile;
begin
  Current := SelectedProfile;
  if Current = nil then
  begin
    MessageDlg('Aviso', 'Selecione uma conexão para excluir.', mtInformation, [mbOK], 0);
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

procedure TMainForm.btnNewTabClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    OpenNewEditorTab(Profile.Id, Profile.Name)
  else
    OpenNewEditorTab;
end;

procedure TMainForm.btnCloseTabClick(Sender: TObject);
var
  Tab: TTabSheet;
begin
  if pgEditors.PageCount <= 1 then
  begin
    MessageDlg('Aviso', 'Mantenha pelo menos uma aba de editor aberta.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Tab := pgEditors.ActivePage;
  if Tab <> nil then
    Tab.Free;
end;

procedure TMainForm.tvConnectionsDblClick(Sender: TObject);
var
  Data: TExplorerNodeData;
  Frame: TSqlEditorFrame;
begin
  Data := SelectedNodeData;
  if Data = nil then
    Exit;

  if Data.Kind = enkConnection then
    OpenNewEditorTab(Data.Profile.Id, Data.Profile.Name)
  else if Data.Kind = enkObject then
  begin
    if Data.Category in [sokTables, sokViews] then
    begin
      Frame := OpenNewEditorTab(Data.Profile.Id, Data.ObjectName);
      Frame.SetSqlText('SELECT * FROM ' + Data.ObjectName);
      Frame.ExecuteCurrentSQL;
    end
    else
    begin
      Frame := OpenNewEditorTab(Data.Profile.Id, Data.ObjectName);
      Frame.SetSqlText('-- ' + SchemaObjectKindToStr(Data.Category) + ': ' + Data.ObjectName);
    end;
  end;
end;

end.
