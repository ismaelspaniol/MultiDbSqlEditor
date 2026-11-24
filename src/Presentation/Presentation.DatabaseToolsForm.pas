unit Presentation.DatabaseToolsForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Clipbrd, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, LCLType, SynEdit, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Application.ManageDatabaseObjectsUseCase,
  Presentation.SqlObjectLinkController;

type
  TMetadataSearchHit = record
    Kind: TSchemaObjectKind;
    CategoryLabel: string;
    ObjectName: string;
    Detail: string;
    Snippet: string;
  end;

  { Busca Global de Metadados e Código-Fonte (Ctrl+Shift+F) }
  TMetadataSearchForm = class(TForm)
  private
    FFactory: IDatabaseProviderFactory;
    FProfiles: TConnectionProfileList;
    FOnOpenObject: TOpenDbObjectLinkEvent;
    FHits: array of TMetadataSearchHit;

    pnlTop: TPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    lblQuery: TLabel;
    edtQuery: TEdit;
    btnSearch: TButton;
    grdResults: TStringGrid;
    splMain: TSplitter;
    pnlBottom: TPanel;
    synPreview: TSynEdit;
    synHl: TSynSQLSyn;
    pnlActions: TPanel;
    lblStatus: TLabel;
    btnOpenObject: TButton;
    btnClose: TButton;

    procedure BuildUI(const AInitialProfileId: string);
    function SelectedProfile: TConnectionProfile;
    procedure RunSearch;
    procedure btnSearchClick(Sender: TObject);
    procedure edtQueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure grdResultsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure grdResultsDblClick(Sender: TObject);
    procedure btnOpenObjectClick(Sender: TObject);
  public
    class procedure Execute(
      const AFactory: IDatabaseProviderFactory;
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string;
      const AOnOpenObject: TOpenDbObjectLinkEvent
    );
    destructor Destroy; override;
  end;

  { Gerenciador de Índices e Estatísticas (Firebird / PostgreSQL / MariaDB) }
  TIndexManagerForm = class(TForm)
  private
    FFactory: IDatabaseProviderFactory;
    FProfiles: TConnectionProfileList;
    FOnOpenObject: TOpenDbObjectLinkEvent;

    pnlTop: TPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    btnRefresh: TButton;
    btnRecomputeOne: TButton;
    btnRecomputeAll: TButton;
    btnToggleOrReindex: TButton;
    btnOpenTable: TButton;
    grdIndexes: TStringGrid;
    pnlBottom: TPanel;
    lblStatus: TLabel;
    btnClose: TButton;

    procedure BuildUI(const AInitialProfileId: string);
    function SelectedProfile: TConnectionProfile;
    procedure LoadIndexes;
    procedure ExecuteAdminSql(const ASQL, ASuccessMsg: string);
    procedure cbConnectionChange(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnRecomputeOneClick(Sender: TObject);
    procedure btnRecomputeAllClick(Sender: TObject);
    procedure btnToggleOrReindexClick(Sender: TObject);
    procedure btnOpenTableClick(Sender: TObject);
    procedure grdIndexesPrepareCanvas(sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
  public
    class procedure Execute(
      const AFactory: IDatabaseProviderFactory;
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string;
      const AOnOpenObject: TOpenDbObjectLinkEvent
    );
    destructor Destroy; override;
  end;

  { Manual e Documentação Integrada das Funcionalidades }
  TDocumentationForm = class(TForm)
  private
    FSections: array of record
      Title: string;
      Body: string;
    end;
    FVisibleIndices: array of Integer;
    pnlTop: TPanel;
    lblSearch: TLabel;
    edtSearch: TEdit;
    btnCopy: TButton;
    btnClose: TButton;
    lbTopics: TListBox;
    splMain: TSplitter;
    memDoc: TMemo;

    procedure InitSections;
    procedure BuildUI;
    procedure PopulateTopics;
    procedure edtSearchChange(Sender: TObject);
    procedure lbTopicsClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
  public
    class procedure Execute;
  end;

implementation

{ TMetadataSearchForm }

class procedure TMetadataSearchForm.Execute(
  const AFactory: IDatabaseProviderFactory;
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string;
  const AOnOpenObject: TOpenDbObjectLinkEvent
);
var
  Frm: TMetadataSearchForm;
  P: TConnectionProfile;
begin
  if AFactory = nil then
    Exit;
  Frm := TMetadataSearchForm.CreateNew(nil);
  try
    Frm.FFactory := AFactory;
    Frm.FOnOpenObject := AOnOpenObject;
    Frm.FProfiles := TConnectionProfileList.Create(True);
    if AConnections <> nil then
      for P in AConnections do
        Frm.FProfiles.Add(P.Clone);
    Frm.BuildUI(AInitialProfileId);
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

destructor TMetadataSearchForm.Destroy;
begin
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TMetadataSearchForm.BuildUI(const AInitialProfileId: string);
var
  I, SelIdx: Integer;
begin
  Caption := 'Busca Global nos Metadados e Código-Fonte';
  Position := poScreenCenter;
  Width := 980;
  Height := 640;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 46;
  pnlTop.BevelOuter := bvNone;

  lblConn := TLabel.Create(Self);
  lblConn.Parent := pnlTop;
  lblConn.Left := 10;
  lblConn.Top := 15;
  lblConn.Caption := 'Conexão:';

  cbConnection := TComboBox.Create(Self);
  cbConnection.Parent := pnlTop;
  cbConnection.Left := 70;
  cbConnection.Top := 11;
  cbConnection.Width := 260;
  cbConnection.Style := csDropDownList;
  SelIdx := -1;
  for I := 0 to FProfiles.Count - 1 do
  begin
    cbConnection.Items.AddObject(
      Format('%s [%s]', [FProfiles[I].Name, DatabaseTypeToStr(FProfiles[I].DatabaseType)]),
      FProfiles[I]
    );
    if (AInitialProfileId <> '') and SameText(FProfiles[I].Id, AInitialProfileId) then
      SelIdx := I;
  end;
  if (SelIdx < 0) and (cbConnection.Items.Count > 0) then
    SelIdx := 0;
  cbConnection.ItemIndex := SelIdx;

  lblQuery := TLabel.Create(Self);
  lblQuery.Parent := pnlTop;
  lblQuery.Left := 345;
  lblQuery.Top := 15;
  lblQuery.Caption := 'Termo:';

  edtQuery := TEdit.Create(Self);
  edtQuery.Parent := pnlTop;
  edtQuery.Left := 392;
  edtQuery.Top := 11;
  edtQuery.Width := 440;
  edtQuery.Anchors := [akTop, akLeft, akRight];
  edtQuery.TextHint := 'Ex: VL_DESCONTO, SP_CALCULA, CPF...';
  edtQuery.OnKeyDown := @edtQueryKeyDown;

  btnSearch := TButton.Create(Self);
  btnSearch.Parent := pnlTop;
  btnSearch.Left := 842;
  btnSearch.Top := 10;
  btnSearch.Width := 120;
  btnSearch.Height := 26;
  btnSearch.Anchors := [akTop, akRight];
  btnSearch.Caption := 'Buscar';
  btnSearch.Default := True;
  btnSearch.OnClick := @btnSearchClick;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 230;
  pnlBottom.BevelOuter := bvNone;

  splMain := TSplitter.Create(Self);
  splMain.Parent := Self;
  splMain.Align := alBottom;
  splMain.Height := 5;

  grdResults := TStringGrid.Create(Self);
  grdResults.Parent := Self;
  grdResults.Align := alClient;
  grdResults.BorderSpacing.Left := 8;
  grdResults.BorderSpacing.Right := 8;
  grdResults.ColCount := 4;
  grdResults.FixedCols := 0;
  grdResults.FixedRows := 1;
  grdResults.RowCount := 1;
  grdResults.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect, goColSizing, goThumbTracking];
  grdResults.Cells[0, 0] := 'Categoria';
  grdResults.Cells[1, 0] := 'Objeto';
  grdResults.Cells[2, 0] := 'Detalhe';
  grdResults.Cells[3, 0] := 'Trecho encontrado';
  grdResults.ColWidths[0] := 120;
  grdResults.ColWidths[1] := 230;
  grdResults.ColWidths[2] := 180;
  grdResults.ColWidths[3] := 410;
  grdResults.OnSelection := @grdResultsSelection;
  grdResults.OnDblClick := @grdResultsDblClick;

  pnlActions := TPanel.Create(Self);
  pnlActions.Parent := pnlBottom;
  pnlActions.Align := alBottom;
  pnlActions.Height := 40;
  pnlActions.BevelOuter := bvNone;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := pnlActions;
  lblStatus.Left := 10;
  lblStatus.Top := 12;
  lblStatus.Caption := 'Digite um termo e clique em Buscar.';

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlActions;
  btnClose.Caption := 'Fechar';
  btnClose.ModalResult := mrCancel;
  btnClose.Cancel := True;
  btnClose.Width := 90;
  btnClose.Height := 26;
  btnClose.Left := pnlActions.Width - 100;
  btnClose.Top := 7;
  btnClose.Anchors := [akTop, akRight];

  btnOpenObject := TButton.Create(Self);
  btnOpenObject.Parent := pnlActions;
  btnOpenObject.Caption := 'Abrir Objeto';
  btnOpenObject.Width := 120;
  btnOpenObject.Height := 26;
  btnOpenObject.Left := btnClose.Left - 128;
  btnOpenObject.Top := 7;
  btnOpenObject.Anchors := [akTop, akRight];
  btnOpenObject.OnClick := @btnOpenObjectClick;

  synHl := TSynSQLSyn.Create(Self);
  synPreview := TSynEdit.Create(Self);
  synPreview.Parent := pnlBottom;
  synPreview.Align := alClient;
  synPreview.BorderSpacing.Left := 8;
  synPreview.BorderSpacing.Right := 8;
  synPreview.BorderSpacing.Top := 4;
  synPreview.ReadOnly := True;
  synPreview.Highlighter := synHl;
end;

function TMetadataSearchForm.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection <> nil) and (cbConnection.ItemIndex >= 0) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

procedure TMetadataSearchForm.edtQueryKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    RunSearch;
  end;
end;

procedure TMetadataSearchForm.btnSearchClick(Sender: TObject);
begin
  RunSearch;
end;

procedure TMetadataSearchForm.RunSearch;
var
  Profile: TConnectionProfile;
  Term, TermEsc, TermFbEsc, SQL, SourceText, TermLower: string;
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  I, LineNum, HitCount, Cap: Integer;
  SL: TStringList;
  CatText, ObjText, LineTxt, Det: string;

  procedure AddHit(const AKind: TSchemaObjectKind; const ACat, AObj, ADet, ASnip: string);
  begin
    if HitCount >= Cap then
    begin
      Cap := Cap * 2;
      SetLength(FHits, Cap);
    end;
    FHits[HitCount].Kind := AKind;
    FHits[HitCount].CategoryLabel := ACat;
    FHits[HitCount].ObjectName := AObj;
    FHits[HitCount].Detail := ADet;
    FHits[HitCount].Snippet := ASnip;
    Inc(HitCount);
  end;

  function ExtractMatchingLine(const ACode: string; out ALineNum: Integer): string;
  var
    K: Integer;
  begin
    Result := '';
    ALineNum := 0;
    SL.Text := ACode;
    for K := 0 to SL.Count - 1 do
    begin
      if Pos(TermLower, LowerCase(SL[K])) > 0 then
      begin
        ALineNum := K + 1;
        Result := Trim(SL[K]);
        Exit;
      end;
    end;
  end;

begin
  Profile := SelectedProfile;
  Term := Trim(edtQuery.Text);
  if (Profile = nil) or (Term = '') then
    Exit;

  if Profile.DatabaseType = dtPostgreSQL then
    synHl.SQLDialect := sqlPostgres
  else
    synHl.SQLDialect := sqlFirebird40;

  TermLower := LowerCase(Term);
  TermEsc := StringReplace(TermLower, '''', '''''', [rfReplaceAll]);
  TermEsc := StringReplace(TermEsc, '%', '\%', [rfReplaceAll]);
  TermFbEsc := StringReplace(Term, '''', '''''', [rfReplaceAll]);

  HitCount := 0;
  Cap := 64;
  SetLength(FHits, Cap);
  SL := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    Provider := FFactory.GetProvider(Profile.DatabaseType);
    Session := Provider.CreateSession(Profile);
    try
      Session.Connect;
      if Profile.DatabaseType = dtFirebird then
      begin
        SQL :=
          'SELECT CAST(''Tabela'' AS VARCHAR(20)) AS CAT, TRIM(RDB$RELATION_NAME) AS OBJ, CAST(''Nome da Tabela'' AS VARCHAR(128)) AS DET, CAST(TRIM(RDB$RELATION_NAME) AS BLOB SUB_TYPE TEXT) AS SRC ' +
          'FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NULL AND RDB$RELATION_NAME CONTAINING ''' + TermFbEsc + ''' ' +
          'UNION ALL ' +
          'SELECT CAST(''Coluna'' AS VARCHAR(20)), TRIM(rf.RDB$RELATION_NAME), CAST(TRIM(rf.RDB$FIELD_NAME) AS VARCHAR(128)), CAST(TRIM(rf.RDB$FIELD_NAME) AS BLOB SUB_TYPE TEXT) ' +
          'FROM RDB$RELATION_FIELDS rf JOIN RDB$RELATIONS r ON r.RDB$RELATION_NAME = rf.RDB$RELATION_NAME ' +
          'WHERE COALESCE(r.RDB$SYSTEM_FLAG, 0) = 0 AND rf.RDB$FIELD_NAME CONTAINING ''' + TermFbEsc + ''' ' +
          'UNION ALL ' +
          'SELECT CAST(''View'' AS VARCHAR(20)), TRIM(RDB$RELATION_NAME), CAST(''Código da View'' AS VARCHAR(128)), RDB$VIEW_SOURCE ' +
          'FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NOT NULL AND (RDB$RELATION_NAME CONTAINING ''' + TermFbEsc + ''' OR RDB$VIEW_SOURCE CONTAINING ''' + TermFbEsc + ''') ' +
          'UNION ALL ' +
          'SELECT CAST(''Procedure'' AS VARCHAR(20)), TRIM(RDB$PROCEDURE_NAME), CAST(''Código PSQL'' AS VARCHAR(128)), RDB$PROCEDURE_SOURCE ' +
          'FROM RDB$PROCEDURES WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND (RDB$PROCEDURE_NAME CONTAINING ''' + TermFbEsc + ''' OR RDB$PROCEDURE_SOURCE CONTAINING ''' + TermFbEsc + ''') ' +
          'UNION ALL ' +
          'SELECT CAST(''Trigger'' AS VARCHAR(20)), TRIM(RDB$TRIGGER_NAME), CAST(''Tabela: '' || TRIM(COALESCE(RDB$RELATION_NAME, '''')) AS VARCHAR(128)), RDB$TRIGGER_SOURCE ' +
          'FROM RDB$TRIGGERS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND (RDB$TRIGGER_NAME CONTAINING ''' + TermFbEsc + ''' OR RDB$TRIGGER_SOURCE CONTAINING ''' + TermFbEsc + ''')';
      end
      else if Profile.DatabaseType = dtPostgreSQL then
      begin
        SQL :=
          'SELECT ''Tabela'' AS cat, table_name AS obj, ''Nome da Tabela'' AS det, table_name AS src ' +
          'FROM information_schema.tables WHERE table_schema = current_schema() AND table_type = ''BASE TABLE'' AND LOWER(table_name) LIKE ''%' + TermEsc + '%'' ' +
          'UNION ALL ' +
          'SELECT ''Coluna'', table_name, column_name, column_name || '' ('' || data_type || '')'' ' +
          'FROM information_schema.columns WHERE table_schema = current_schema() AND LOWER(column_name) LIKE ''%' + TermEsc + '%'' ' +
          'UNION ALL ' +
          'SELECT ''View'', table_name, ''Código da View'', COALESCE(view_definition, '''') ' +
          'FROM information_schema.views WHERE table_schema = current_schema() AND (LOWER(table_name) LIKE ''%' + TermEsc + '%'' OR LOWER(COALESCE(view_definition, '''')) LIKE ''%' + TermEsc + '%'') ' +
          'UNION ALL ' +
          'SELECT ''Procedure'', p.proname, ''Código da Função/Proc'', COALESCE(pg_get_functiondef(p.oid), p.prosrc, '''') ' +
          'FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace ' +
          'WHERE n.nspname = current_schema() AND (LOWER(p.proname) LIKE ''%' + TermEsc + '%'' OR LOWER(COALESCE(p.prosrc, '''')) LIKE ''%' + TermEsc + '%'') ' +
          'UNION ALL ' +
          'SELECT ''Trigger'', t.tgname, ''Tabela: '' || c.relname, pg_get_triggerdef(t.oid) ' +
          'FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace ' +
          'WHERE NOT t.tgisinternal AND n.nspname = current_schema() AND (LOWER(t.tgname) LIKE ''%' + TermEsc + '%'' OR LOWER(pg_get_triggerdef(t.oid)) LIKE ''%' + TermEsc + '%'')';
      end
      else
      begin
        SQL :=
          'SELECT ''Tabela'' AS cat, table_name AS obj, ''Nome da Tabela'' AS det, table_name AS src ' +
          'FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = ''BASE TABLE'' AND LOWER(table_name) LIKE ''%' + TermEsc + '%'' ' +
          'UNION ALL ' +
          'SELECT ''Coluna'', table_name, column_name, column_name ' +
          'FROM information_schema.columns WHERE table_schema = DATABASE() AND LOWER(column_name) LIKE ''%' + TermEsc + '%'' ' +
          'UNION ALL ' +
          'SELECT ''View'', table_name, ''Código da View'', COALESCE(view_definition, '''') ' +
          'FROM information_schema.views WHERE table_schema = DATABASE() AND (LOWER(table_name) LIKE ''%' + TermEsc + '%'' OR LOWER(COALESCE(view_definition, '''')) LIKE ''%' + TermEsc + '%'') ' +
          'UNION ALL ' +
          'SELECT ''Procedure'', routine_name, ''Código da Routine'', COALESCE(routine_definition, '''') ' +
          'FROM information_schema.routines WHERE routine_schema = DATABASE() AND (LOWER(routine_name) LIKE ''%' + TermEsc + '%'' OR LOWER(COALESCE(routine_definition, '''')) LIKE ''%' + TermEsc + '%'')';
      end;

      Res := Session.ExecuteSQL(SQL, False, 0);
      try
        if not Res.Success then
        begin
          MessageDlg('Busca nos Metadados', Res.MessageText, mtError, [mbOK], 0);
          Exit;
        end;
        for I := 0 to Res.RowCount - 1 do
        begin
          CatText := Trim(Res.GetRow(I)[0].AsText);
          ObjText := Trim(Res.GetRow(I)[1].AsText);
          Det := Trim(Res.GetRow(I)[2].AsText);
          SourceText := Res.GetRow(I)[3].AsText;
          if SameText(CatText, 'Tabela') then
            AddHit(sokTables, 'Tabela', ObjText, Det, SourceText)
          else if SameText(CatText, 'Coluna') then
            AddHit(sokTables, 'Tabela (Coluna)', ObjText, 'Coluna: ' + Det, SourceText)
          else
          begin
            LineTxt := ExtractMatchingLine(SourceText, LineNum);
            if LineNum > 0 then
              Det := Format('%s (Linha %d)', [Det, LineNum]);
            if LineTxt = '' then
              LineTxt := SourceText;
            if SameText(CatText, 'View') then
              AddHit(sokViews, 'View', ObjText, Det, SourceText)
            else if SameText(CatText, 'Procedure') then
              AddHit(sokProcedures, 'Procedure', ObjText, Det, SourceText)
            else
              AddHit(sokTriggers, 'Trigger', ObjText, Det, SourceText);
            FHits[HitCount - 1].Detail := Det + ' | ' + LineTxt;
          end;
        end;
      finally
        Res.Free;
      end;
    finally
      Session.Disconnect;
    end;

    SetLength(FHits, HitCount);
    grdResults.RowCount := HitCount + 1;
    for I := 0 to HitCount - 1 do
    begin
      grdResults.Cells[0, I + 1] := FHits[I].CategoryLabel;
      grdResults.Cells[1, I + 1] := FHits[I].ObjectName;
      grdResults.Cells[2, I + 1] := FHits[I].Detail;
      grdResults.Cells[3, I + 1] := Copy(StringReplace(FHits[I].Snippet, LineEnding, ' ', [rfReplaceAll]), 1, 140);
    end;
    lblStatus.Caption := Format('%d ocorrência(s) encontrada(s) para "%s".', [HitCount, Term]);
    if HitCount > 0 then
    begin
      grdResults.Row := 1;
      grdResultsSelection(nil, 0, 1);
    end
    else
      synPreview.Clear;
  finally
    Screen.Cursor := crDefault;
    SL.Free;
  end;
end;

procedure TMetadataSearchForm.grdResultsSelection(Sender: TObject; aCol, aRow: Integer);
var
  Idx: Integer;
begin
  Idx := aRow - 1;
  if (Idx >= 0) and (Idx <= High(FHits)) then
    synPreview.Lines.Text := FHits[Idx].Snippet
  else
    synPreview.Clear;
end;

procedure TMetadataSearchForm.grdResultsDblClick(Sender: TObject);
begin
  btnOpenObjectClick(nil);
end;

procedure TMetadataSearchForm.btnOpenObjectClick(Sender: TObject);
var
  Idx: Integer;
  Prof: TConnectionProfile;
begin
  Idx := grdResults.Row - 1;
  Prof := SelectedProfile;
  if (Prof = nil) or (Idx < 0) or (Idx > High(FHits)) then
    Exit;
  if Assigned(FOnOpenObject) then
    FOnOpenObject(Prof, FHits[Idx].Kind, FHits[Idx].ObjectName);
end;

{ TIndexManagerForm }

class procedure TIndexManagerForm.Execute(
  const AFactory: IDatabaseProviderFactory;
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string;
  const AOnOpenObject: TOpenDbObjectLinkEvent
);
var
  Frm: TIndexManagerForm;
  P: TConnectionProfile;
begin
  if AFactory = nil then
    Exit;
  Frm := TIndexManagerForm.CreateNew(nil);
  try
    Frm.FFactory := AFactory;
    Frm.FOnOpenObject := AOnOpenObject;
    Frm.FProfiles := TConnectionProfileList.Create(True);
    if AConnections <> nil then
      for P in AConnections do
        Frm.FProfiles.Add(P.Clone);
    Frm.BuildUI(AInitialProfileId);
    Frm.LoadIndexes;
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

destructor TIndexManagerForm.Destroy;
begin
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TIndexManagerForm.BuildUI(const AInitialProfileId: string);
var
  I, SelIdx: Integer;
begin
  Caption := 'Gerenciador de Índices e Estatísticas';
  Position := poScreenCenter;
  Width := 980;
  Height := 600;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 46;
  pnlTop.BevelOuter := bvNone;

  lblConn := TLabel.Create(Self);
  lblConn.Parent := pnlTop;
  lblConn.Left := 10;
  lblConn.Top := 15;
  lblConn.Caption := 'Conexão:';

  cbConnection := TComboBox.Create(Self);
  cbConnection.Parent := pnlTop;
  cbConnection.Left := 70;
  cbConnection.Top := 11;
  cbConnection.Width := 250;
  cbConnection.Style := csDropDownList;
  SelIdx := -1;
  for I := 0 to FProfiles.Count - 1 do
  begin
    cbConnection.Items.AddObject(
      Format('%s [%s]', [FProfiles[I].Name, DatabaseTypeToStr(FProfiles[I].DatabaseType)]),
      FProfiles[I]
    );
    if (AInitialProfileId <> '') and SameText(FProfiles[I].Id, AInitialProfileId) then
      SelIdx := I;
  end;
  if (SelIdx < 0) and (cbConnection.Items.Count > 0) then
    SelIdx := 0;
  cbConnection.ItemIndex := SelIdx;
  cbConnection.OnChange := @cbConnectionChange;

  btnRefresh := TButton.Create(Self);
  btnRefresh.Parent := pnlTop;
  btnRefresh.Left := 330;
  btnRefresh.Top := 10;
  btnRefresh.Width := 95;
  btnRefresh.Height := 26;
  btnRefresh.Caption := 'Atualizar';
  btnRefresh.OnClick := @btnRefreshClick;

  btnRecomputeOne := TButton.Create(Self);
  btnRecomputeOne.Parent := pnlTop;
  btnRecomputeOne.Left := 432;
  btnRecomputeOne.Top := 10;
  btnRecomputeOne.Width := 155;
  btnRecomputeOne.Height := 26;
  btnRecomputeOne.Caption := 'Recalcular Selecionado';
  btnRecomputeOne.OnClick := @btnRecomputeOneClick;

  btnRecomputeAll := TButton.Create(Self);
  btnRecomputeAll.Parent := pnlTop;
  btnRecomputeAll.Left := 594;
  btnRecomputeAll.Top := 10;
  btnRecomputeAll.Width := 155;
  btnRecomputeAll.Height := 26;
  btnRecomputeAll.Caption := 'Recalcular Todos (Lote)';
  btnRecomputeAll.OnClick := @btnRecomputeAllClick;

  btnToggleOrReindex := TButton.Create(Self);
  btnToggleOrReindex.Parent := pnlTop;
  btnToggleOrReindex.Left := 756;
  btnToggleOrReindex.Top := 10;
  btnToggleOrReindex.Width := 115;
  btnToggleOrReindex.Height := 26;
  btnToggleOrReindex.Caption := 'Ativar / Reindexar';
  btnToggleOrReindex.OnClick := @btnToggleOrReindexClick;

  btnOpenTable := TButton.Create(Self);
  btnOpenTable.Parent := pnlTop;
  btnOpenTable.Left := 878;
  btnOpenTable.Top := 10;
  btnOpenTable.Width := 90;
  btnOpenTable.Height := 26;
  btnOpenTable.Caption := 'Abrir Tabela';
  btnOpenTable.OnClick := @btnOpenTableClick;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 38;
  pnlBottom.BevelOuter := bvNone;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := pnlBottom;
  lblStatus.Left := 10;
  lblStatus.Top := 11;
  lblStatus.Caption := 'Pronto.';

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlBottom;
  btnClose.Caption := 'Fechar';
  btnClose.ModalResult := mrCancel;
  btnClose.Cancel := True;
  btnClose.Width := 90;
  btnClose.Height := 26;
  btnClose.Left := pnlBottom.Width - 100;
  btnClose.Top := 6;
  btnClose.Anchors := [akTop, akRight];

  grdIndexes := TStringGrid.Create(Self);
  grdIndexes.Parent := Self;
  grdIndexes.Align := alClient;
  grdIndexes.BorderSpacing.Left := 8;
  grdIndexes.BorderSpacing.Right := 8;
  grdIndexes.ColCount := 6;
  grdIndexes.FixedCols := 0;
  grdIndexes.FixedRows := 1;
  grdIndexes.RowCount := 1;
  grdIndexes.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect, goColSizing, goThumbTracking];
  grdIndexes.Cells[0, 0] := 'Índice';
  grdIndexes.Cells[1, 0] := 'Tabela';
  grdIndexes.Cells[2, 0] := 'Colunas';
  grdIndexes.Cells[3, 0] := 'Unique';
  grdIndexes.Cells[4, 0] := 'Status';
  grdIndexes.Cells[5, 0] := 'Seletividade / Uso';
  grdIndexes.ColWidths[0] := 210;
  grdIndexes.ColWidths[1] := 180;
  grdIndexes.ColWidths[2] := 220;
  grdIndexes.ColWidths[3] := 65;
  grdIndexes.ColWidths[4] := 95;
  grdIndexes.ColWidths[5] := 175;
  grdIndexes.OnPrepareCanvas := @grdIndexesPrepareCanvas;
end;

function TIndexManagerForm.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection <> nil) and (cbConnection.ItemIndex >= 0) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

procedure TIndexManagerForm.cbConnectionChange(Sender: TObject);
begin
  LoadIndexes;
end;

procedure TIndexManagerForm.btnRefreshClick(Sender: TObject);
begin
  LoadIndexes;
end;

procedure TIndexManagerForm.LoadIndexes;
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  SQL: string;
  I: Integer;
begin
  Profile := SelectedProfile;
  grdIndexes.RowCount := 1;
  if Profile = nil then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    Provider := FFactory.GetProvider(Profile.DatabaseType);
    Session := Provider.CreateSession(Profile);
    try
      Session.Connect;
      if Profile.DatabaseType = dtFirebird then
      begin
        SQL :=
          'SELECT TRIM(i.RDB$INDEX_NAME), TRIM(i.RDB$RELATION_NAME), ' +
          'COALESCE(LIST(TRIM(s.RDB$FIELD_NAME), '', ''), ''''), ' +
          'CASE WHEN COALESCE(i.RDB$UNIQUE_FLAG, 0) = 1 THEN ''Sim'' ELSE ''Não'' END, ' +
          'CASE WHEN COALESCE(i.RDB$INDEX_INACTIVE, 0) = 1 THEN ''Inativo'' ELSE ''Ativo'' END, ' +
          'CAST(COALESCE(i.RDB$STATISTICS, 0) AS VARCHAR(30)) ' +
          'FROM RDB$INDICES i ' +
          'LEFT JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = i.RDB$INDEX_NAME ' +
          'WHERE COALESCE(i.RDB$SYSTEM_FLAG, 0) = 0 ' +
          'GROUP BY i.RDB$INDEX_NAME, i.RDB$RELATION_NAME, i.RDB$UNIQUE_FLAG, i.RDB$INDEX_INACTIVE, i.RDB$STATISTICS ' +
          'ORDER BY 2, 1';
      end
      else if Profile.DatabaseType = dtPostgreSQL then
      begin
        SQL :=
          'SELECT s.indexrelname, s.relname, ' +
          'COALESCE(pg_get_indexdef(s.indexrelid), ''''), ' +
          'CASE WHEN x.indisunique THEN ''Sim'' ELSE ''Não'' END, ' +
          'CASE WHEN s.idx_scan = 0 THEN ''Sem uso'' ELSE ''Ativo'' END, ' +
          '''Scans: '' || s.idx_scan || '' ('' || pg_size_pretty(pg_relation_size(s.indexrelid)) || '')'' ' +
          'FROM pg_stat_user_indexes s ' +
          'JOIN pg_index x ON x.indexrelid = s.indexrelid ' +
          'WHERE s.schemaname = current_schema() ' +
          'ORDER BY s.idx_scan ASC, pg_relation_size(s.indexrelid) DESC';
      end
      else
      begin
        SQL :=
          'SELECT index_name, table_name, GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR '', ''), ' +
          'CASE WHEN MAX(non_unique) = 0 THEN ''Sim'' ELSE ''Não'' END, ' +
          '''Ativo'', ' +
          '''Cardinality: '' || COALESCE(MAX(cardinality), 0) ' +
          'FROM information_schema.statistics ' +
          'WHERE table_schema = DATABASE() ' +
          'GROUP BY index_name, table_name ' +
          'ORDER BY 2, 1';
      end;

      Res := Session.ExecuteSQL(SQL, False, 0);
      try
        if not Res.Success then
        begin
          MessageDlg('Gerenciador de Índices', Res.MessageText, mtError, [mbOK], 0);
          Exit;
        end;
        grdIndexes.RowCount := Res.RowCount + 1;
        for I := 0 to Res.RowCount - 1 do
        begin
          grdIndexes.Cells[0, I + 1] := Res.GetRow(I)[0].AsText;
          grdIndexes.Cells[1, I + 1] := Res.GetRow(I)[1].AsText;
          grdIndexes.Cells[2, I + 1] := Res.GetRow(I)[2].AsText;
          grdIndexes.Cells[3, I + 1] := Res.GetRow(I)[3].AsText;
          grdIndexes.Cells[4, I + 1] := Res.GetRow(I)[4].AsText;
          grdIndexes.Cells[5, I + 1] := Res.GetRow(I)[5].AsText;
        end;
        lblStatus.Caption := Format('%d índice(s) carregado(s).', [Res.RowCount]);
      finally
        Res.Free;
      end;
    finally
      Session.Disconnect;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TIndexManagerForm.ExecuteAdminSql(const ASQL, ASuccessMsg: string);
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
begin
  Profile := SelectedProfile;
  if Profile = nil then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    Provider := FFactory.GetProvider(Profile.DatabaseType);
    Session := Provider.CreateSession(Profile);
    try
      Session.Connect;
      Res := Session.ExecuteSQL(ASQL, True, 0);
      try
        if not Res.Success then
        begin
          MessageDlg('Erro', Res.MessageText, mtError, [mbOK], 0);
          Exit;
        end;
      finally
        Res.Free;
      end;
    finally
      Session.Disconnect;
    end;
    lblStatus.Caption := ASuccessMsg;
    LoadIndexes;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TIndexManagerForm.btnRecomputeOneClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  IdxName, TblName, SQL: string;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (grdIndexes.Row < 1) then
    Exit;
  IdxName := grdIndexes.Cells[0, grdIndexes.Row];
  TblName := grdIndexes.Cells[1, grdIndexes.Row];
  if Profile.DatabaseType = dtFirebird then
    SQL := 'SET STATISTICS INDEX ' + QuoteDbIdent(dtFirebird, IdxName)
  else if Profile.DatabaseType = dtPostgreSQL then
    SQL := 'ANALYZE ' + QuoteDbIdent(dtPostgreSQL, TblName)
  else
    SQL := 'ANALYZE TABLE ' + QuoteDbIdent(dtMariaDB, TblName);
  ExecuteAdminSql(SQL, 'Estatística recalculada para ' + IdxName + '.');
end;

procedure TIndexManagerForm.btnRecomputeAllClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  R: Integer;
  SQL: string;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (grdIndexes.RowCount <= 1) then
    Exit;
  if MessageDlg('Confirmar', Format('Recalcular estatísticas de %d índice(s)?', [grdIndexes.RowCount - 1]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    Provider := FFactory.GetProvider(Profile.DatabaseType);
    Session := Provider.CreateSession(Profile);
    try
      Session.Connect;
      for R := 1 to grdIndexes.RowCount - 1 do
      begin
        if Profile.DatabaseType = dtFirebird then
          SQL := 'SET STATISTICS INDEX ' + QuoteDbIdent(dtFirebird, grdIndexes.Cells[0, R])
        else if Profile.DatabaseType = dtPostgreSQL then
          SQL := 'ANALYZE ' + QuoteDbIdent(dtPostgreSQL, grdIndexes.Cells[1, R])
        else
          SQL := 'ANALYZE TABLE ' + QuoteDbIdent(dtMariaDB, grdIndexes.Cells[1, R]);
        Res := Session.ExecuteSQL(SQL, True, 0);
        try
          if not Res.Success then
          begin
            MessageDlg('Erro em lote', Res.MessageText, mtError, [mbOK], 0);
            Break;
          end;
        finally
          Res.Free;
        end;
      end;
    finally
      Session.Disconnect;
    end;
    lblStatus.Caption := 'Estatísticas recalculadas em lote.';
    LoadIndexes;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TIndexManagerForm.btnToggleOrReindexClick(Sender: TObject);
var
  Profile: TConnectionProfile;
  IdxName, TblName, StatusStr, SQL: string;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (grdIndexes.Row < 1) then
    Exit;
  IdxName := grdIndexes.Cells[0, grdIndexes.Row];
  TblName := grdIndexes.Cells[1, grdIndexes.Row];
  StatusStr := grdIndexes.Cells[4, grdIndexes.Row];
  if Profile.DatabaseType = dtFirebird then
  begin
    if SameText(StatusStr, 'Inativo') then
      SQL := Format('ALTER INDEX %s ACTIVE', [QuoteDbIdent(dtFirebird, IdxName)])
    else
      SQL := Format('ALTER INDEX %s INACTIVE', [QuoteDbIdent(dtFirebird, IdxName)]);
    ExecuteAdminSql(SQL, 'Estado do índice alterado: ' + IdxName);
  end
  else if Profile.DatabaseType = dtPostgreSQL then
  begin
    SQL := 'REINDEX INDEX ' + QuoteDbIdent(dtPostgreSQL, IdxName);
    ExecuteAdminSql(SQL, 'Índice reindexado: ' + IdxName);
  end
  else
  begin
    SQL := 'OPTIMIZE TABLE ' + QuoteDbIdent(dtMariaDB, TblName);
    ExecuteAdminSql(SQL, 'Tabela otimizada: ' + TblName);
  end;
end;

procedure TIndexManagerForm.btnOpenTableClick(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if (Profile = nil) or (grdIndexes.Row < 1) then
    Exit;
  if Assigned(FOnOpenObject) then
    FOnOpenObject(Profile, sokTables, grdIndexes.Cells[1, grdIndexes.Row]);
end;

procedure TIndexManagerForm.grdIndexesPrepareCanvas(sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
begin
  if (aRow >= 1) and not (gdSelected in aState) then
  begin
    if SameText(grdIndexes.Cells[4, aRow], 'Inativo') or SameText(grdIndexes.Cells[4, aRow], 'Sem uso') then
    begin
      grdIndexes.Canvas.Font.Color := clMaroon;
      if aCol = 4 then
        grdIndexes.Canvas.Font.Style := [fsBold];
    end;
  end;
end;

{ TDocumentationForm }

class procedure TDocumentationForm.Execute;
var
  Frm: TDocumentationForm;
begin
  Frm := TDocumentationForm.CreateNew(nil);
  try
    Frm.InitSections;
    Frm.BuildUI;
    Frm.PopulateTopics;
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

procedure TDocumentationForm.InitSections;
var
  AllText: string;
  I: Integer;

  procedure AddSec(const ATitle, ABody: string);
  var
    N: Integer;
  begin
    N := Length(FSections);
    SetLength(FSections, N + 1);
    FSections[N].Title := ATitle;
    FSections[N].Body := ABody;
  end;

begin
  SetLength(FSections, 0);

  AddSec(
    'Visão Geral e Bancos Suportados',
    'MULTI-DB SQL EDITOR' + LineEnding +
    '===================' + LineEnding + LineEnding +
    'IDE e editor SQL multi-banco inspirado no IBExpert, desenvolvido em Free Pascal / Lazarus + mORMot2.' + LineEnding + LineEnding +
    'BANCOS SUPORTADOS:' + LineEnding +
    '• Firebird (2.5 / 3.0 / 4.0 / 5.0): via SQLdb (fbclient.dll detectada por versão/arquitetura), Debugger PSQL passo a passo, SET TERM, contadores I/O (Indexed vs Natural), Backup/Restore/Repair (Services API) e Replicação FB 5.' + LineEnding +
    '• PostgreSQL: via mORMot2 (libpq.dll) com cursor em streaming no servidor, conexão sem informar banco (nível de servidor), seletor de Schema, EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) e Replicação Lógica.' + LineEnding +
    '• MariaDB / MySQL: via SQLdb (libmariadb.dll), navegação de objetos, editor visual de tabelas, EXPLAIN FORMAT=JSON, comparador e importação/exportação.'
  );

  AddSec(
    '1. Conexões, Multi-Banco PG e Proteção de Produção',
    '1. GERENCIADOR DE CONEXÕES E SEGURANÇA POR AMBIENTE' + LineEnding +
    '====================================================' + LineEnding + LineEnding +
    '• Perfis salvos em connections.json com teste de conectividade, duplicação, ordenação e reordenação (drag-and-drop ou Alt+Seta).' + LineEnding +
    '• Parser automático de connection strings Firebird (ex.: 127.0.0.1/3055:D:\dados\banco.fdb).' + LineEnding +
    '• PostgreSQL sem nome de banco (nível de servidor): ao deixar o campo Database em branco no PostgreSQL, o editor conecta ao banco padrão "postgres" e permite expandir a árvore para visualizar e trabalhar em todos os bancos registrados no servidor.' + LineEnding +
    '• Seletor de Schema (PostgreSQL): botão "Listar" no cadastro ou clique direito -> "Selecionar Schema" na árvore.' + LineEnding +
    '• Cor de Alerta por Ambiente: escolha Padrão, Desenvolvimento (Verde), Homologação (Amarelo) ou Produção (Vermelho) ao cadastrar/editar uma conexão.' + LineEnding +
    '• Proteção de Produção: conexões marcadas como Produção exibem faixa vermelha no editor e exigem confirmação explícita antes de executar DROP, TRUNCATE, DELETE ou UPDATE sem cláusula WHERE.'
  );

  AddSec(
    '2. Explorador de Objetos (Árvore Lateral)',
    '2. EXPLORADOR DE OBJETOS' + LineEnding +
    '========================' + LineEnding + LineEnding +
    '• Agrupamento por SGBD (Firebird, PostgreSQL, MariaDB) com nós expansíveis para Bancos (PostgreSQL nível servidor), Tabelas (exibindo tamanho estimado), Views, Procedures/Functions, Triggers e Generators/Sequences.' + LineEnding +
    '• Filtro rápido no topo da árvore para localizar conexões, bancos ou objetos instantaneamente.' + LineEnding +
    '• Menu de contexto completo: Nova Aba SQL, Script Executive, Monitor, Comparar Bases, Manutenção, Buscar nos Metadados, Gerenciador de Índices, Importar Dados, Editar/Ver DDL, Ver Dados, Criar/Excluir objeto, Desconectar sessões.' + LineEnding +
    '• Exclusão de tabela com dupla confirmação (1/2 e 2/2) para evitar DROP TABLE acidental.'
  );

  AddSec(
    '3. Editor SQL, Parâmetros (:param), Fixar Aba e Disk Spill',
    '3. EDITOR SQL AVANÇADO' + LineEnding +
    '======================' + LineEnding + LineEnding +
    '• Execução assíncrona em segundo plano (F9) com cronômetro e botão Cancelar.' + LineEnding +
    '• Paginação sob demanda (Batch Fetch / Fetch All) com Commit, Rollback e Auto Commit.' + LineEnding +
    '• Proteção de RAM + "Disco se faltar RAM": monitora o limite de RAM da consulta e a RAM livre do SO. Com "Disco se faltar RAM" marcado, grava os dados excedentes em arquivo temporário (.tmp) no disco e mantém a navegação fluida. Todos os arquivos .tmp relacionados são limpos automaticamente ao fechar a aplicação.' + LineEnding +
    '• Parâmetros Dinâmicos (:param): ao executar SELECT/WITH/INSERT/UPDATE/DELETE com :parametro, abre uma grade para informar valores (com memória na sessão e suporte a NULL), ignorando :: e :=.' + LineEnding +
    '• Múltiplos Resultados e Abas Fixadas: executar vários SELECTs separados por ";" abre automaticamente abas adicionais (Resultado 2, Resultado 3...). O botão "Fixar" congela o resultado atual em uma aba separada para comparação.' + LineEnding +
    '• Autocompletar SQL (Ctrl+Espaço) sensível a aliases (FROM clientes c WHERE c.).' + LineEnding +
    '• Navegação Ctrl+Click sobre o nome de Tabelas, Views, Procedures, Triggers e Sequences.' + LineEnding +
    '• Formatador SQL (Alt+F), Biblioteca de Snippets/Favoritos (botão Snippets) e Histórico de Execução.'
  );

  AddSec(
    '4. Grid de Resultados, Inspetor JSON e Geradores SQL/CSV',
    '4. GRID DE RESULTADOS E MANIPULAÇÃO DE DADOS' + LineEnding +
    '============================================' + LineEnding + LineEnding +
    '• Edição inline para consultas de tabela única (+ Inserir, editar célula, Definir NULL, - Excluir, Commit/Rollback).' + LineEnding +
    '• Filtro Rápido Local (Ctrl+F no grid) e clique direito -> "Filtrar por Valor desta Célula".' + LineEnding +
    '• Inspetor Lateral Valor / JSON e Visão Vertical do Registro (Campo | Tipo | Valor), acessível pelo menu de contexto ou pela barra de filtro.' + LineEnding +
    '• Agregações Instantâneas na Seleção: ao selecionar múltiplas células numéricas, exibe no rodapé Contagem | Soma | Média | Mín | Máx.' + LineEnding +
    '• Menus separados e explícitos para Registro Atual vs Consulta Inteira:' + LineEnding +
    '  - Gerar / Copiar do Registro Atual: CSV, INSERT, UPDATE, UPDATE OR INSERT, JSON, Markdown e TSV.' + LineEnding +
    '  - Gerar / Copiar da Consulta Inteira (busca todas as linhas pendentes): CSV, INSERTs, UPDATEs, UPDATE OR INSERTs, JSON, Markdown e Exportar em Arquivo (.csv, .sql, .json, .md, .html).'
  );

  AddSec(
    '5. Plano de Execução Visual (Explain Plan) e Performance',
    '5. PLANO DE EXECUÇÃO VISUAL E PERFORMANCE' + LineEnding +
    '=========================================' + LineEnding + LineEnding +
    '• Exibe tempo de Prepare, Execute/Fetch, Total, memória usada e tabela de estatísticas (Leituras Indexadas vs Não-Indexadas/Natural).' + LineEnding +
    '• Firebird: análise do plano textual nativo e contadores de I/O por tabela.' + LineEnding +
    '• PostgreSQL e MariaDB: botão "Plano Visual (EXPLAIN ANALYZE)" monta a árvore visual destacando Full Scans e gargalos de memória/ordenação.'
  );

  AddSec(
    '6. Editor Visual de Tabelas e Autocompletar no WHERE',
    '6. EDITOR VISUAL DE TABELAS (ESTILO ISEXPERT/IBEXPERT)' + LineEnding +
    '======================================================' + LineEnding + LineEnding +
    '• Campos: adicionar, editar, excluir colunas e consultar dependências por campo.' + LineEnding +
    '• Constraints e Índices: visualizar PK, FK, Unique, Check e criar/ativar/inativar/excluir índices.' + LineEnding +
    '• Triggers: árvore agrupada por evento, editor com autocompletar PSQL/PLpgSQL e compilação com F9.' + LineEnding +
    '• Aba Dados: consulta direta com limite, campo WHERE com autocompletar automático de colunas ao digitar (ou Ctrl+Espaço; setas/Enter/Tab aceitam; Enter com lista fechada aplica o filtro), edição inline, Exportar CSV e Importar Dados...' + LineEnding +
    '• Exclusão Segura: botão "Excluir Tabela..." no cabeçalho com 2 confirmações obrigatórias (1/2 e 2/2).'
  );

  AddSec(
    '7. Debugger PSQL (Procedures Firebird)',
    '7. DEBUGGER PSQL PARA PROCEDURES FIREBIRD' + LineEnding +
    '=========================================' + LineEnding + LineEnding +
    '• Executa interpretação passo a passo no cliente sem depender de agente no servidor:' + LineEnding +
    '  - Step Into (F7), Step Over (F8), Continuar (F9), Até o Cursor (F4), Breakpoints (F5 ou clique na margem).' + LineEnding +
    '  - Diálogo de parâmetros de entrada, inspetor de Variáveis/Parâmetros, Campos do Cursor atual, resultados de SUSPEND e Log SQL.' + LineEnding +
    '  - Opção de Rollback automático ao encerrar ou reiniciar para não persistir alterações de teste.'
  );

  AddSec(
    '8. Database Comparer (Diff DDL Colorido)',
    '8. DATABASE COMPARER (COMPARADOR DE SCHEMAS)' + LineEnding +
    '============================================' + LineEnding + LineEnding +
    '• Compara Generators/Sequences, Tabelas, Colunas (tipo, NOT NULL, DEFAULT, COMPUTED BY, comentários), PKs, Índices, FKs, UNIQUE, CHECK, Views, Procedures e Triggers entre Origem (Modelo) e Destino.' + LineEnding +
    '• Ordenação topológica por dependência para Views e Procedures.' + LineEnding +
    '• Visualizador DDL Origem vs Destino pintado linha a linha: Verde = apenas na Origem, Vermelho = apenas no Destino, Amarelo = linhas modificadas.' + LineEnding +
    '• Aplica os itens selecionados em transação única (com Rollback automático em caso de erro).'
  );

  AddSec(
    '9. Importar Dados (Excel .xlsx/.xls, CSV e Criar Tabela)',
    '9. IMPORTAR DADOS (IMPORT DATA)' + LineEnding +
    '===============================' + LineEnding + LineEnding +
    '• Acessível pela aba Dados das tabelas ("Importar Dados..."), menu Ferramentas ou clique direito na árvore.' + LineEnding +
    '• Formatos: Excel .xlsx (leitura nativa sem precisar do Excel), .xls (via Excel OLE ou texto) e .csv / .txt / .tsv.' + LineEnding +
    '• Destino: importe em uma tabela existente ou marque "Criar Nova Tabela" para gerar automaticamente o CREATE TABLE com inferência de tipos SQL.' + LineEnding +
    '• Mapeamento de Colunas: dê duplo clique em qualquer linha para editar nome da coluna destino, tipo SQL, Chave Primária (PK), coluna de origem no arquivo ou valor fixo/NULL.' + LineEnding +
    '• Modos: INSERT, UPDATE OR INSERT / UPSERT e UPDATE, além de Limpar tabela antes, Pré-visualização, Script SQL no Log e Commit em lote ou transação única.'
  );

  AddSec(
    '10. Busca Global nos Metadados (Ctrl+Shift+F) e Índices',
    '10. BUSCA GLOBAL NOS METADADOS E GERENCIADOR DE ÍNDICES' + LineEnding +
    '=======================================================' + LineEnding + LineEnding +
    '• Busca Global nos Metadados e Código-Fonte (Ctrl+Shift+F): pesquisa um termo simultaneamente em Tabelas, Colunas e dentro do código-fonte de Views, Procedures e Triggers (Firebird, PostgreSQL e MariaDB), exibindo o trecho e abrindo o objeto ao clicar.' + LineEnding +
    '• Gerenciador de Índices e Estatísticas: exibe seletividade (RDB$STATISTICS), uso (idx_scan) e cardinalidade, permitindo recalcular estatísticas individualmente ou em lote (SET STATISTICS INDEX / ANALYZE), ativar/inativar índices ou executar REINDEX/OPTIMIZE.'
  );

  AddSec(
    '11. Script Executive, Monitor, Manutenção e Replicação',
    '11. FERRAMENTAS ADMINISTRATIVAS' + LineEnding +
    '===============================' + LineEnding + LineEnding +
    '• Script Executive (Ctrl+F12): execução em lote com suporte a SET TERM (Firebird) e modo "Executar fila direto do disco" para scripts enormes.' + LineEnding +
    '• Monitor de Atividade: conexões, transações e consultas ativas com filtro e ações para cancelar query ou encerrar sessão/PID.' + LineEnding +
    '• Manutenção: Backup, Restore e Validação/Reparo.' + LineEnding +
    '• Assistente de Replicação: Replicação Lógica no PostgreSQL (Publication/Subscription) e Firebird 5.'
  );

  AddSec(
    '12. Atalhos de Teclado',
    '12. ATALHOS DE TECLADO' + LineEnding +
    '======================' + LineEnding + LineEnding +
    'F1            -> Abrir esta Documentação' + LineEnding +
    'F9            -> Executar SQL / Compilar DDL / Continuar Debug' + LineEnding +
    'Ctrl+Espaço   -> Autocompletar SQL / Sugerir colunas no WHERE' + LineEnding +
    'Ctrl+Click    -> Abrir objeto sob o cursor no Editor SQL' + LineEnding +
    'Alt+F         -> Formatar / indentar código SQL' + LineEnding +
    'Ctrl+F        -> Filtro rápido local no Grid de Resultados' + LineEnding +
    'Ctrl+Shift+F  -> Busca Global nos Metadados e Código-Fonte' + LineEnding +
    'Ctrl+F12      -> Abrir Script Executive' + LineEnding +
    'F7 / F8 / F4  -> Debugger PSQL: Step Into / Step Over / Até Cursor' + LineEnding +
    'F5            -> Debugger PSQL: Alternar Breakpoint' + LineEnding +
    'Alt+↑ / Alt+↓ -> Reordenar conexão selecionada na árvore'
  );

  AllText := '';
  for I := 0 to High(FSections) do
  begin
    if AllText <> '' then
      AllText := AllText + LineEnding + LineEnding + StringOfChar('-', 72) + LineEnding + LineEnding;
    AllText := AllText + FSections[I].Body;
  end;
  AddSec('Documentação Completa (Todos os Tópicos)', AllText);
end;

procedure TDocumentationForm.BuildUI;
begin
  Caption := 'Documentação e Manual de Funcionalidades - Multi-DB SQL Editor';
  Position := poScreenCenter;
  Width := 1020;
  Height := 680;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 480;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 44;
  pnlTop.BevelOuter := bvNone;

  lblSearch := TLabel.Create(Self);
  lblSearch.Parent := pnlTop;
  lblSearch.Left := 10;
  lblSearch.Top := 14;
  lblSearch.Caption := 'Filtrar tópico:';

  edtSearch := TEdit.Create(Self);
  edtSearch.Parent := pnlTop;
  edtSearch.Left := 92;
  edtSearch.Top := 10;
  edtSearch.Width := 360;
  edtSearch.TextHint := 'Digite uma palavra-chave (ex.: Excel, Debug, CSV, Postgres)...';
  edtSearch.OnChange := @edtSearchChange;

  btnCopy := TButton.Create(Self);
  btnCopy.Parent := pnlTop;
  btnCopy.Left := 464;
  btnCopy.Top := 9;
  btnCopy.Width := 135;
  btnCopy.Height := 26;
  btnCopy.Caption := 'Copiar Tópico';
  btnCopy.OnClick := @btnCopyClick;

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlTop;
  btnClose.Caption := 'Fechar';
  btnClose.ModalResult := mrClose;
  btnClose.Cancel := True;
  btnClose.Width := 90;
  btnClose.Height := 26;
  btnClose.Left := Width - 100;
  btnClose.Top := 9;
  btnClose.Anchors := [akTop, akRight];

  lbTopics := TListBox.Create(Self);
  lbTopics.Parent := Self;
  lbTopics.Align := alLeft;
  lbTopics.Width := 320;
  lbTopics.BorderSpacing.Left := 8;
  lbTopics.BorderSpacing.Bottom := 8;
  lbTopics.OnClick := @lbTopicsClick;

  splMain := TSplitter.Create(Self);
  splMain.Parent := Self;
  splMain.Align := alLeft;
  splMain.Width := 5;

  memDoc := TMemo.Create(Self);
  memDoc.Parent := Self;
  memDoc.Align := alClient;
  memDoc.BorderSpacing.Right := 8;
  memDoc.BorderSpacing.Bottom := 8;
  memDoc.ReadOnly := True;
  memDoc.ScrollBars := ssVertical;
  memDoc.WordWrap := True;
  memDoc.Font.Name := 'Segoe UI';
  memDoc.Font.Size := 10;
end;

procedure TDocumentationForm.PopulateTopics;
var
  FilterLower: string;
  I, Cnt: Integer;
begin
  FilterLower := LowerCase(Trim(edtSearch.Text));
  lbTopics.Items.BeginUpdate;
  try
    lbTopics.Items.Clear;
    SetLength(FVisibleIndices, Length(FSections));
    Cnt := 0;
    for I := 0 to High(FSections) do
    begin
      if (FilterLower = '') or
         (Pos(FilterLower, LowerCase(FSections[I].Title)) > 0) or
         (Pos(FilterLower, LowerCase(FSections[I].Body)) > 0) then
      begin
        FVisibleIndices[Cnt] := I;
        Inc(Cnt);
        lbTopics.Items.Add(FSections[I].Title);
      end;
    end;
    SetLength(FVisibleIndices, Cnt);
    if lbTopics.Items.Count > 0 then
    begin
      lbTopics.ItemIndex := 0;
      lbTopicsClick(nil);
    end
    else
      memDoc.Lines.Text := 'Nenhum tópico encontrado para "' + Trim(edtSearch.Text) + '".';
  finally
    lbTopics.Items.EndUpdate;
  end;
end;

procedure TDocumentationForm.edtSearchChange(Sender: TObject);
begin
  PopulateTopics;
end;

procedure TDocumentationForm.lbTopicsClick(Sender: TObject);
var
  Idx: Integer;
begin
  if (lbTopics.ItemIndex >= 0) and (lbTopics.ItemIndex <= High(FVisibleIndices)) then
  begin
    Idx := FVisibleIndices[lbTopics.ItemIndex];
    memDoc.Lines.Text := FSections[Idx].Body;
    memDoc.SelStart := 0;
    memDoc.SelLength := 0;
  end;
end;

procedure TDocumentationForm.btnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := memDoc.Lines.Text;
end;

end.
