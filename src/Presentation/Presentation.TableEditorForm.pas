unit Presentation.TableEditorForm;

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
  StdCtrls,
  ExtCtrls,
  ComCtrls,
  Grids,
  Menus,
  SynEdit,
  SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.TableStructureTypes,
  Application.ManageDatabaseObjectsUseCase,
  Application.ManageTableStructureUseCase;

type
  TOnOpenTableDependency = procedure(
    const AProfile: TConnectionProfile;
    const AKind: TSchemaObjectKind;
    const AObjectName: string;
    out AShouldCloseTableForm: Boolean
  ) of object;

  TOnOpenTableSqlScript = procedure(
    const AProfile: TConnectionProfile;
    const ATitle, ASqlText: string
  ) of object;

  { TTableEditorForm }
  TTableEditorForm = class(TForm)
    pnlHeader: TPanel;
    lblTableTitle: TLabel;
    btnRefresh: TButton;
    btnViewData: TButton;
    pgTable: TPageControl;
    tsFields: TTabSheet;
    pnlFieldsBar: TFlowPanel;
    btnAddField: TButton;
    btnEditField: TButton;
    btnDropField: TButton;
    btnFieldDeps: TButton;
    grdFields: TStringGrid;
    tsIndexes: TTabSheet;
    pnlIndexesBar: TFlowPanel;
    btnAddIndex: TButton;
    btnToggleIndexActive: TButton;
    btnDropIndex: TButton;
    grdIndexes: TStringGrid;
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
    SynEditDDL: TSynEdit;
    pnlBottom: TPanel;
    lblStatus: TLabel;
    btnClose: TButton;
    pmFields: TPopupMenu;
    miFieldDeps: TMenuItem;
    miFieldSep1: TMenuItem;
    miFieldEdit: TMenuItem;
    miFieldDrop: TMenuItem;
    SynSQLSynDDL: TSynSQLSyn;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnViewDataClick(Sender: TObject);
    procedure btnAddFieldClick(Sender: TObject);
    procedure btnEditFieldClick(Sender: TObject);
    procedure btnDropFieldClick(Sender: TObject);
    procedure btnFieldDepsClick(Sender: TObject);
    procedure pmFieldsPopup(Sender: TObject);
    procedure grdFieldsDblClick(Sender: TObject);
    procedure grdFieldsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure btnAddIndexClick(Sender: TObject);
    procedure btnToggleIndexActiveClick(Sender: TObject);
    procedure btnDropIndexClick(Sender: TObject);
    procedure grdIndexesSelection(Sender: TObject; aCol, aRow: Integer);
    procedure cbDepFieldChange(Sender: TObject);
    procedure grdDepUsedByDblClick(Sender: TObject);
    procedure grdDepUsesDblClick(Sender: TObject);
    procedure btnCopyTableDDLClick(Sender: TObject);
    procedure btnOpenDDLInSqlClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
  private
    FProfile: TConnectionProfile;
    FTableName: string;
    FUseCase: TManageTableStructureUseCase;
    FStructure: TTableStructure;
    FUsedByDeps: TTableDependencyInfoArray;
    FUsesDeps: TTableDependencyInfoArray;
    FOnOpenDependency: TOnOpenTableDependency;
    FOnOpenSqlScript: TOnOpenTableSqlScript;
    FWasModified: Boolean;
    FWantsViewData: Boolean;
    FOpenedMainTab: Boolean;
    procedure ConfigureGrids;
    procedure LoadAndDisplayStructure;
    procedure PopulateFieldsGrid;
    procedure PopulateIndexesGrid;
    procedure PopulateDependenciesFieldFilter;
    procedure RefreshDependenciesDisplay;
    procedure PopulateDependenciesGrids(const ADeps: TTableDependencyInfoArray);
    procedure OpenDependencyFromGrid(const AGrid: TStringGrid; const ADeps: TTableDependencyInfoArray);
    function SelectedColumnIndex: Integer;
    function SelectedIndexPos: Integer;
    procedure UpdateButtonsState;
    function ShowColumnDialog(const AIsEdit: Boolean; const AExisting: TTableColumnInfo): Boolean;
    function ShowCreateIndexDialog: Boolean;
  public
    class function Execute(
      const AProfile: TConnectionProfile;
      const ATableName: string;
      const AUseCase: TManageTableStructureUseCase;
      out AWasModified: Boolean;
      out AWantsViewData: Boolean;
      out AOpenedMainTab: Boolean;
      const AOnOpenDependency: TOnOpenTableDependency = nil;
      const AOnOpenSqlScript: TOnOpenTableSqlScript = nil
    ): Boolean;
  end;

implementation

{$R *.lfm}

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

{ TTableEditorForm }

class function TTableEditorForm.Execute(
  const AProfile: TConnectionProfile;
  const ATableName: string;
  const AUseCase: TManageTableStructureUseCase;
  out AWasModified: Boolean;
  out AWantsViewData: Boolean;
  out AOpenedMainTab: Boolean;
  const AOnOpenDependency: TOnOpenTableDependency;
  const AOnOpenSqlScript: TOnOpenTableSqlScript
): Boolean;
var
  Frm: TTableEditorForm;
begin
  Result := False;
  AWasModified := False;
  AWantsViewData := False;
  AOpenedMainTab := False;
  if (AProfile = nil) or (AUseCase = nil) or (Trim(ATableName) = '') then
    Exit;

  Frm := TTableEditorForm.Create(nil);
  try
    Frm.FProfile := AProfile;
    Frm.FTableName := Trim(ATableName);
    Frm.FUseCase := AUseCase;
    Frm.FOnOpenDependency := AOnOpenDependency;
    Frm.FOnOpenSqlScript := AOnOpenSqlScript;
    if AProfile.DatabaseType = dtPostgreSQL then
      Frm.SynSQLSynDDL.SQLDialect := sqlPostgres
    else
      Frm.SynSQLSynDDL.SQLDialect := sqlFirebird40;
    Frm.SynSQLSynDDL.Enabled := True;
    Frm.SynEditDDL.Highlighter := Frm.SynSQLSynDDL;
    Frm.Caption := Format('Tabela: %s (%s)', [Frm.FTableName, AProfile.Name]);
    Frm.lblTableTitle.Caption := Format('Tabela: %s  |  Conexão: %s (%s)', [
      Frm.FTableName,
      AProfile.Name,
      DatabaseTypeToStr(AProfile.DatabaseType)
    ]);
    Frm.LoadAndDisplayStructure;
    Frm.ShowModal;
    AWasModified := Frm.FWasModified;
    AWantsViewData := Frm.FWantsViewData;
    AOpenedMainTab := Frm.FOpenedMainTab;
    Result := True;
  finally
    Frm.Free;
  end;
end;

procedure TTableEditorForm.FormCreate(Sender: TObject);
begin
  FWasModified := False;
  FWantsViewData := False;
  FOpenedMainTab := False;
  FStructure := nil;
  FUsedByDeps := nil;
  FUsesDeps := nil;
  {$IFDEF UNIX}
  grdFields.Font.Name := 'Monospace';
  grdIndexes.Font.Name := 'Monospace';
  grdDepUsedBy.Font.Name := 'Monospace';
  grdDepUses.Font.Name := 'Monospace';
  SynEditDDL.Font.Name := 'Monospace';
  {$ENDIF}
  ConfigureGrids;
end;

procedure TTableEditorForm.FormDestroy(Sender: TObject);
begin
  FUsedByDeps := nil;
  FUsesDeps := nil;
  FreeAndNil(FStructure);
end;

procedure TTableEditorForm.ConfigureGrids;
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
  grdFields.ColWidths[1] := 170;
  grdFields.ColWidths[2] := 145;
  grdFields.ColWidths[3] := 120;
  grdFields.ColWidths[4] := 70;
  grdFields.ColWidths[5] := 48;
  grdFields.ColWidths[6] := 120;
  grdFields.ColWidths[7] := 140;

  grdIndexes.ColCount := 6;
  grdIndexes.Cells[0, 0] := 'Índice';
  grdIndexes.Cells[1, 0] := 'Colunas / Expressão';
  grdIndexes.Cells[2, 0] := 'Único';
  grdIndexes.Cells[3, 0] := 'Ordem';
  grdIndexes.Cells[4, 0] := 'Ativo';
  grdIndexes.Cells[5, 0] := 'Constraint / Tipo';
  grdIndexes.ColWidths[0] := 200;
  grdIndexes.ColWidths[1] := 260;
  grdIndexes.ColWidths[2] := 65;
  grdIndexes.ColWidths[3] := 80;
  grdIndexes.ColWidths[4] := 65;
  grdIndexes.ColWidths[5] := 175;

  grdDepUsedBy.ColCount := 2;
  grdDepUsedBy.Cells[0, 0] := 'Objeto';
  grdDepUsedBy.Cells[1, 0] := 'Tipo';
  grdDepUsedBy.ColWidths[0] := 480;
  grdDepUsedBy.ColWidths[1] := 320;

  grdDepUses.ColCount := 2;
  grdDepUses.Cells[0, 0] := 'Objeto';
  grdDepUses.Cells[1, 0] := 'Tipo';
  grdDepUses.ColWidths[0] := 480;
  grdDepUses.ColWidths[1] := 320;
end;

procedure TTableEditorForm.LoadAndDisplayStructure;
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
      PopulateIndexesGrid;
      PopulateDependenciesFieldFilter;
      RefreshDependenciesDisplay;
      SynEditDDL.Lines.Text := GenerateTableDDL(FProfile.DatabaseType, FStructure, True);
      lblStatus.Caption := Format('%d campo(s) | %d índice(s) | %d dependência(s)', [
        Length(FStructure.Columns),
        Length(FStructure.Indexes),
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

procedure TTableEditorForm.PopulateFieldsGrid;
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

procedure TTableEditorForm.PopulateIndexesGrid;
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

procedure TTableEditorForm.PopulateDependenciesFieldFilter;
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

procedure TTableEditorForm.RefreshDependenciesDisplay;
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

procedure TTableEditorForm.PopulateDependenciesGrids(const ADeps: TTableDependencyInfoArray);
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

procedure TTableEditorForm.OpenDependencyFromGrid(
  const AGrid: TStringGrid;
  const ADeps: TTableDependencyInfoArray
);
var
  MousePos: TPoint;
  ACol, ARow: Integer;
  Dep: TTableDependencyInfo;
  Kind: TSchemaObjectKind;
  ShouldClose: Boolean;
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
    lblStatus.Caption := Format('A tabela "%s" já está aberta nesta janela.', [FTableName]);
    Exit;
  end;

  ShouldClose := False;
  FOnOpenDependency(FProfile, Kind, Dep.ObjectName, ShouldClose);
  if ShouldClose then
  begin
    FOpenedMainTab := True;
    Close;
  end;
end;

function TTableEditorForm.SelectedColumnIndex: Integer;
begin
  Result := grdFields.Row - 1;
  if (FStructure = nil) or (Result < 0) or (Result >= Length(FStructure.Columns)) then
    Result := -1;
end;

function TTableEditorForm.SelectedIndexPos: Integer;
begin
  Result := grdIndexes.Row - 1;
  if (FStructure = nil) or (Result < 0) or (Result >= Length(FStructure.Indexes)) then
    Result := -1;
end;

procedure TTableEditorForm.UpdateButtonsState;
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

function TTableEditorForm.ShowColumnDialog(const AIsEdit: Boolean; const AExisting: TTableColumnInfo): Boolean;
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
  Dlg, PnlInputs, PnlBtns: TPanel;
  FormDlg: TForm;
  LblName, LblType, LblDefault, LblPreview: TLabel;
  BtnCancel: TButton;
  I: Integer;
begin
  Result := False;
  FormDlg := TForm.Create(Self);
  Helper := TColumnDialogHelper.Create;
  try
    FormDlg.BorderStyle := bsSizeable;
    FormDlg.BorderIcons := [biSystemMenu];
    FormDlg.Position := poOwnerFormCenter;
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

    { Preencher valores iniciais }
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

function TTableEditorForm.ShowCreateIndexDialog: Boolean;
var
  FormDlg: TForm;
  Helper: TIndexDialogHelper;
  PnlTop, PnlLists, PnlLeft, PnlMidBtns, PnlRight, PnlOpts, PnlBtns: TPanel;
  LblIdxName, LblAvail, LblSel, LblPreview: TLabel;
  BtnCancel: TButton;
  I: Integer;
begin
  Result := False;
  if FStructure = nil then
    Exit;

  FormDlg := TForm.Create(Self);
  Helper := TIndexDialogHelper.Create;
  Helper.AllColsOrder := TStringList.Create;
  try
    FormDlg.BorderStyle := bsSizeable;
    FormDlg.BorderIcons := [biSystemMenu];
    FormDlg.Position := poOwnerFormCenter;
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

procedure TTableEditorForm.btnRefreshClick(Sender: TObject);
begin
  LoadAndDisplayStructure;
end;

procedure TTableEditorForm.btnViewDataClick(Sender: TObject);
begin
  FWantsViewData := True;
  Close;
end;

procedure TTableEditorForm.btnAddFieldClick(Sender: TObject);
var
  DummyCol: TTableColumnInfo;
begin
  FillChar(DummyCol, SizeOf(DummyCol), 0);
  if ShowColumnDialog(False, DummyCol) then
  begin
    FWasModified := True;
    LoadAndDisplayStructure;
  end;
end;

procedure TTableEditorForm.btnEditFieldClick(Sender: TObject);
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
    FWasModified := True;
    LoadAndDisplayStructure;
  end;
end;

procedure TTableEditorForm.btnDropFieldClick(Sender: TObject);
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
    FWasModified := True;
    LoadAndDisplayStructure;
    lblStatus.Caption := Msg;
  end
  else
    MessageDlg('Erro ao excluir campo', Msg, mtError, [mbOK], 0);
end;

procedure TTableEditorForm.btnFieldDepsClick(Sender: TObject);
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

procedure TTableEditorForm.pmFieldsPopup(Sender: TObject);
var
  ColIdx: Integer;
begin
  ColIdx := SelectedColumnIndex;
  miFieldDeps.Enabled := ColIdx >= 0;
  miFieldEdit.Enabled := (ColIdx >= 0) and (not FStructure.Columns[ColIdx].IsComputed);
  miFieldDrop.Enabled := ColIdx >= 0;
end;

procedure TTableEditorForm.cbDepFieldChange(Sender: TObject);
begin
  RefreshDependenciesDisplay;
end;

procedure TTableEditorForm.grdFieldsDblClick(Sender: TObject);
begin
  btnEditFieldClick(Sender);
end;

procedure TTableEditorForm.grdFieldsSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateButtonsState;
end;

procedure TTableEditorForm.btnAddIndexClick(Sender: TObject);
begin
  if ShowCreateIndexDialog then
  begin
    FWasModified := True;
    LoadAndDisplayStructure;
  end;
end;

procedure TTableEditorForm.btnToggleIndexActiveClick(Sender: TObject);
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
    FWasModified := True;
    LoadAndDisplayStructure;
    lblStatus.Caption := Msg;
  end
  else
    MessageDlg('Erro ao alterar status do índice', Msg, mtError, [mbOK], 0);
end;

procedure TTableEditorForm.btnDropIndexClick(Sender: TObject);
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
    FWasModified := True;
    LoadAndDisplayStructure;
    lblStatus.Caption := Msg;
  end
  else
    MessageDlg('Erro ao excluir índice', Msg, mtError, [mbOK], 0);
end;

procedure TTableEditorForm.grdIndexesSelection(Sender: TObject; aCol, aRow: Integer);
begin
  UpdateButtonsState;
end;

procedure TTableEditorForm.grdDepUsedByDblClick(Sender: TObject);
begin
  OpenDependencyFromGrid(grdDepUsedBy, FUsedByDeps);
end;

procedure TTableEditorForm.grdDepUsesDblClick(Sender: TObject);
begin
  OpenDependencyFromGrid(grdDepUses, FUsesDeps);
end;

procedure TTableEditorForm.btnCopyTableDDLClick(Sender: TObject);
begin
  Clipboard.AsText := SynEditDDL.Lines.Text;
  lblStatus.Caption := 'DDL da tabela copiado para a área de transferência.';
end;

procedure TTableEditorForm.btnOpenDDLInSqlClick(Sender: TObject);
begin
  if (FProfile <> nil) and Assigned(FOnOpenSqlScript) then
  begin
    FOnOpenSqlScript(FProfile, 'DDL: ' + FTableName, SynEditDDL.Lines.Text);
    FOpenedMainTab := True;
    Close;
  end;
end;

procedure TTableEditorForm.btnCloseClick(Sender: TObject);
begin
  Close;
end;

end.
