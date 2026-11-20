unit Presentation.ObjectEditorFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Clipbrd, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, LCLType, SynEdit, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Application.ManageDatabaseObjectsUseCase,
  Presentation.QueryResultGridFrame,
  Presentation.SqlCompletionController,
  Presentation.ProcedureParamsForm;

type
  TObjectChangedEvent = procedure(const AProfileId: string; const AKind: TSchemaObjectKind) of object;
  TOpenViewDataEvent = procedure(const AProfileId, AViewName: string) of object;

  { Frame de visualização e edição DDL de Views, Procedures e Triggers }
  TObjectEditorFrame = class(TFrame)
    pnlToolbar: TFlowPanel;
    lblObjectTitle: TLabel;
    btnCompile: TButton;
    btnExecute: TButton;
    btnReload: TButton;
    btnCopyDDL: TButton;
    btnViewData: TButton;
    btnDropObject: TButton;
    SynEdit1: TSynEdit;
    Splitter1: TSplitter;
    pgBottom: TPageControl;
    tsLog: TTabSheet;
    tsResult: TTabSheet;
    memLog: TMemo;
    SynSQLSyn1: TSynSQLSyn;
    procedure btnCompileClick(Sender: TObject);
    procedure btnExecuteClick(Sender: TObject);
    procedure btnReloadClick(Sender: TObject);
    procedure btnCopyDDLClick(Sender: TObject);
    procedure btnViewDataClick(Sender: TObject);
    procedure btnDropObjectClick(Sender: TObject);
    procedure SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pnlToolbarResize(Sender: TObject);
  private
    FProfile: TConnectionProfile;
    FObjectKind: TSchemaObjectKind;
    FObjectName: string;
    FIsNewObject: Boolean;
    FUseCase: TManageDatabaseObjectsUseCase;
    FUpdatingToolbarSize: Boolean;
    FLastToolbarWidth: Integer;
    FCompletionCtrl: TSqlCompletionController;
    FResultGrid: TQueryResultGridFrame;
    FLastResult: TQueryResult;
    FLastParamValues: TProcedureParamValueArray;
    FLastParamProcName: string;
    FOnObjectChanged: TObjectChangedEvent;
    FOnOpenViewData: TOpenViewDataEvent;
    procedure LogMessage(const AMsg: string);
    procedure UpdateToolbarLayout;
    procedure UpdateTitleAndButtons;
    function GetCompletionProfile: TConnectionProfile;
    function ExecuteCompletionMetadataQuery(const ASQL: string): TQueryResult;
    procedure HandleGridExportedCsv(Sender: TObject; const AFileName: string);
    function TryExtractObjectNameFromDDL(const ADDL: string): string;
  public
    destructor Destroy; override;
    procedure Initialize(
      const AProfile: TConnectionProfile;
      const AKind: TSchemaObjectKind;
      const AObjectName: string;
      const AUseCase: TManageDatabaseObjectsUseCase;
      const AInitialDDL: string;
      const AIsNewObject: Boolean = False
    );
    procedure ClearMetadataCache;
    function ProfileId: string;
    property ObjectKind: TSchemaObjectKind read FObjectKind;
    property ObjectName: string read FObjectName;
    property OnObjectChanged: TObjectChangedEvent read FOnObjectChanged write FOnObjectChanged;
    property OnOpenViewData: TOpenViewDataEvent read FOnOpenViewData write FOnOpenViewData;
  end;

implementation

{$R *.lfm}

destructor TObjectEditorFrame.Destroy;
begin
  if FResultGrid <> nil then
    FResultGrid.SetResult(nil, False, False);
  FreeAndNil(FLastResult);
  FreeAndNil(FProfile);
  inherited Destroy;
end;

procedure TObjectEditorFrame.ClearMetadataCache;
begin
  if FCompletionCtrl <> nil then
    FCompletionCtrl.ClearMetadataCache;
end;

function TObjectEditorFrame.GetCompletionProfile: TConnectionProfile;
begin
  Result := FProfile;
end;

function TObjectEditorFrame.ExecuteCompletionMetadataQuery(const ASQL: string): TQueryResult;
begin
  if (FUseCase <> nil) and (FProfile <> nil) then
    Result := FUseCase.ExecuteMetadataQuery(FProfile, ASQL)
  else
    Result := nil;
end;

procedure TObjectEditorFrame.HandleGridExportedCsv(Sender: TObject; const AFileName: string);
begin
  LogMessage('Resultado exportado para CSV: ' + AFileName);
end;

function TObjectEditorFrame.TryExtractObjectNameFromDDL(const ADDL: string): string;
var
  I, Len, StartI: Integer;
  Tok, UpperTok, ExpectedKw, ExpectedAltKw, PartName: string;
  IsWord, WasQuoted, MatchFound, ExpectName: Boolean;

  function NextToken(out AIsWord, AWasQuoted: Boolean): string;
  var
    C: Char;
    Buf: string;
  begin
    AIsWord := False;
    AWasQuoted := False;
    Result := '';
    while I <= Len do
    begin
      C := ADDL[I];
      if C in [' ', #9, #10, #13] then
      begin
        Inc(I);
        Continue;
      end;
      if (C = '-') and (I < Len) and (ADDL[I + 1] = '-') then
      begin
        Inc(I, 2);
        while (I <= Len) and not (ADDL[I] in [#10, #13]) do
          Inc(I);
        Continue;
      end;
      if (C = '/') and (I < Len) and (ADDL[I + 1] = '*') then
      begin
        Inc(I, 2);
        while (I < Len) and not ((ADDL[I] = '*') and (ADDL[I + 1] = '/')) do
          Inc(I);
        if I <= Len - 1 then
          Inc(I, 2)
        else
          I := Len + 1;
        Continue;
      end;
      if C = '''' then
      begin
        Inc(I);
        while I <= Len do
        begin
          if ADDL[I] = '''' then
          begin
            if (I < Len) and (ADDL[I + 1] = '''') then
              Inc(I, 2)
            else
            begin
              Inc(I);
              Break;
            end;
          end
          else
            Inc(I);
        end;
        Result := '''''';
        Exit;
      end;
      if C = '"' then
      begin
        Buf := '';
        Inc(I);
        while I <= Len do
        begin
          if ADDL[I] = '"' then
          begin
            if (I < Len) and (ADDL[I + 1] = '"') then
            begin
              Buf := Buf + '"';
              Inc(I, 2);
            end
            else
            begin
              Inc(I);
              Break;
            end;
          end
          else
          begin
            Buf := Buf + ADDL[I];
            Inc(I);
          end;
        end;
        AIsWord := True;
        AWasQuoted := True;
        Result := Trim(Buf);
        Exit;
      end;
      if (C in ['A'..'Z', 'a'..'z', '_', '$']) or (Ord(C) >= 128) then
      begin
        StartI := I;
        Inc(I);
        while (I <= Len) and ((ADDL[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) or (Ord(ADDL[I]) >= 128)) do
          Inc(I);
        AIsWord := True;
        Result := Copy(ADDL, StartI, I - StartI);
        Exit;
      end;
      Result := C;
      Inc(I);
      Exit;
    end;
  end;

  function NormalizeExtractedIdent(const AName: string; const AQuoted: Boolean): string;
  begin
    Result := Trim(AName);
    if (Result = '') or AQuoted or (FProfile = nil) then
      Exit;
    if FProfile.DatabaseType = dtPostgreSQL then
      Result := LowerCase(Result)
    else
      Result := UpperCase(Result);
  end;

begin
  Result := '';
  ExpectedKw := '';
  ExpectedAltKw := '';
  case FObjectKind of
    sokViews: ExpectedKw := 'VIEW';
    sokProcedures:
      begin
        ExpectedKw := 'PROCEDURE';
        ExpectedAltKw := 'FUNCTION';
      end;
    sokTriggers: ExpectedKw := 'TRIGGER';
  else
    Exit;
  end;

  Len := Length(ADDL);
  I := 1;
  MatchFound := False;
  ExpectName := False;
  while I <= Len do
  begin
    Tok := NextToken(IsWord, WasQuoted);
    if Tok = '' then
      Break;
    UpperTok := UpperCase(Tok);

    if ExpectName then
    begin
      if IsWord then
      begin
        PartName := NormalizeExtractedIdent(Tok, WasQuoted);
        Tok := NextToken(IsWord, WasQuoted);
        if Tok = '.' then
        begin
          Tok := NextToken(IsWord, WasQuoted);
          if IsWord and (Tok <> '') then
            PartName := NormalizeExtractedIdent(Tok, WasQuoted);
        end;
        Result := PartName;
      end;
      Exit;
    end;

    if not MatchFound then
    begin
      if IsWord and ((UpperTok = 'CREATE') or (UpperTok = 'RECREATE') or (UpperTok = 'ALTER')) then
        MatchFound := True;
    end
    else if IsWord then
    begin
      if (UpperTok = ExpectedKw) or ((ExpectedAltKw <> '') and (UpperTok = ExpectedAltKw)) then
        ExpectName := True
      else if (UpperTok = 'OR') or (UpperTok = 'ALTER') or (UpperTok = 'REPLACE') or
              (UpperTok = 'TEMP') or (UpperTok = 'TEMPORARY') or (UpperTok = 'CONSTRAINT') or
              (UpperTok = 'MATERIALIZED') then
        Continue
      else
        MatchFound := False;
    end;
  end;
end;

procedure TObjectEditorFrame.LogMessage(const AMsg: string);
begin
  memLog.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss', Now), AMsg]));
end;

procedure TObjectEditorFrame.UpdateToolbarLayout;
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

procedure TObjectEditorFrame.UpdateTitleAndButtons;
var
  KindLabel: string;
begin
  case FObjectKind of
    sokTables: KindLabel := 'Tabela (DDL)';
    sokViews: KindLabel := 'View';
    sokProcedures: KindLabel := 'Procedure';
    sokTriggers: KindLabel := 'Trigger';
    sokGenerators: KindLabel := 'Generator';
  else
    KindLabel := 'Objeto';
  end;

  if FIsNewObject then
    lblObjectTitle.Caption := Format('[%s] Novo(a) %s', [FProfile.Name, KindLabel])
  else
    lblObjectTitle.Caption := Format('[%s] %s: %s', [FProfile.Name, KindLabel, FObjectName]);

  btnCompile.Visible := not (FObjectKind in [sokTables, sokGenerators]);
  btnExecute.Visible := (FObjectKind = sokProcedures);
  btnExecute.Enabled := (FObjectKind = sokProcedures) and (not FIsNewObject);
  btnReload.Enabled := not FIsNewObject;
  btnCopyDDL.Enabled := True;
  btnDropObject.Visible := not (FObjectKind in [sokTables, sokGenerators]);
  btnDropObject.Enabled := (not FIsNewObject) and
    (not ((FProfile.DatabaseType = dtPostgreSQL) and (FObjectKind = sokTriggers)));
  btnViewData.Visible := (not FIsNewObject) and (FObjectKind in [sokTables, sokViews]);
  SynEdit1.ReadOnly := (FObjectKind in [sokTables, sokGenerators]);
  if tsResult <> nil then
    tsResult.TabVisible := (FObjectKind = sokProcedures);
  UpdateToolbarLayout;
end;

procedure TObjectEditorFrame.Initialize(
  const AProfile: TConnectionProfile;
  const AKind: TSchemaObjectKind;
  const AObjectName: string;
  const AUseCase: TManageDatabaseObjectsUseCase;
  const AInitialDDL: string;
  const AIsNewObject: Boolean
);
begin
  if FResultGrid <> nil then
    FResultGrid.SetResult(nil, False, False);
  FreeAndNil(FLastResult);
  SetLength(FLastParamValues, 0);
  FLastParamProcName := '';

  FreeAndNil(FProfile);
  FProfile := AProfile.Clone;
  FObjectKind := AKind;
  FObjectName := AObjectName;
  FUseCase := AUseCase;
  FIsNewObject := AIsNewObject;
  FUpdatingToolbarSize := False;
  FLastToolbarWidth := -1;

  {$IFDEF UNIX}
  SynEdit1.Font.Name := 'Monospace';
  memLog.Font.Name := 'Monospace';
  {$ENDIF}

  if FProfile.DatabaseType = dtPostgreSQL then
    SynSQLSyn1.SQLDialect := sqlPostgres
  else
    SynSQLSyn1.SQLDialect := sqlFirebird40;

  SynSQLSyn1.Enabled := True;
  SynEdit1.Highlighter := SynSQLSyn1;
  SynEdit1.Keystrokes.ResetDefaults;
  SynEdit1.Lines.Text := AInitialDDL;

  if FResultGrid = nil then
  begin
    FResultGrid := TQueryResultGridFrame.Create(Self);
    FResultGrid.Name := 'ProcResultGridFrame';
    FResultGrid.Parent := tsResult;
    FResultGrid.Align := alClient;
    FResultGrid.EmptyMessage := 'Nenhuma execução realizada.';
    FResultGrid.OnExportedCsv := @HandleGridExportedCsv;
  end;
  FResultGrid.SetResult(nil, True, False);
  tsResult.Caption := 'Resultado';
  pgBottom.ActivePage := tsLog;

  if FObjectKind in [sokViews, sokProcedures, sokTriggers] then
  begin
    if FCompletionCtrl = nil then
      FCompletionCtrl := TSqlCompletionController.Create(
        Self,
        SynEdit1,
        @GetCompletionProfile,
        @ExecuteCompletionMetadataQuery
      );
    FCompletionCtrl.IncludeProceduralKeywords := (FObjectKind in [sokProcedures, sokTriggers]);
    FCompletionCtrl.ClearMetadataCache;
  end
  else
    FreeAndNil(FCompletionCtrl);

  UpdateTitleAndButtons;
  if FObjectKind = sokTables then
    LogMessage('DDL da tabela carregado (somente visualização). Use "Copiar DDL" ou "Ver Dados (SELECT)".')
  else if FObjectKind = sokGenerators then
    LogMessage('DDL do generator/sequence carregado (somente visualização). Para alterar o valor ou excluir, dê duplo clique no objeto na árvore.')
  else if FObjectKind = sokProcedures then
    LogMessage('DDL carregado. Pressione F9 para compilar, F8 para executar e Ctrl+Espaço para autocompletar.')
  else
    LogMessage('DDL carregado. Pressione F9 para compilar/salvar e Ctrl+Espaço para autocompletar.');
end;

function TObjectEditorFrame.ProfileId: string;
begin
  if FProfile <> nil then
    Result := FProfile.Id
  else
    Result := '';
end;

procedure TObjectEditorFrame.pnlToolbarResize(Sender: TObject);
begin
  if (not FUpdatingToolbarSize) and (pnlToolbar.Width <> FLastToolbarWidth) then
    UpdateToolbarLayout;
end;

procedure TObjectEditorFrame.btnCompileClick(Sender: TObject);
var
  Msg, ExtractedName, Prefix: string;
begin
  if (FUseCase = nil) or (FProfile = nil) or (FObjectKind in [sokTables, sokGenerators]) then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    if FUseCase.CompileDDL(FProfile, SynEdit1.Lines.Text, Msg) then
    begin
      LogMessage('SUCESSO: ' + Msg);
      ClearMetadataCache;
      if FIsNewObject then
      begin
        ExtractedName := TryExtractObjectNameFromDDL(SynEdit1.Lines.Text);
        if ExtractedName <> '' then
        begin
          FObjectName := ExtractedName;
          FIsNewObject := False;
          UpdateTitleAndButtons;
          if Parent is TTabSheet then
          begin
            case FObjectKind of
              sokViews: Prefix := 'View';
              sokProcedures: Prefix := 'Proc';
              sokTriggers: Prefix := 'Trg';
            else
              Prefix := 'DDL';
            end;
            TTabSheet(Parent).Caption := Prefix + ': ' + FObjectName;
          end;
        end;
      end;
      if Assigned(FOnObjectChanged) then
        FOnObjectChanged(FProfile.Id, FObjectKind);
    end
    else
    begin
      LogMessage('ERRO AO COMPILAR: ' + Msg);
      pgBottom.ActivePage := tsLog;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TObjectEditorFrame.btnExecuteClick(Sender: TObject);
var
  Meta: TProcedureMetadata;
  PrevValues, ParamValues: TProcedureParamValueArray;
  AutoCommit: Boolean;
  ExecutedSQL: string;
  Res: TQueryResult;
  TargetH: Integer;
begin
  if (FUseCase = nil) or (FProfile = nil) or (FObjectKind <> sokProcedures) or FIsNewObject then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    try
      Meta := FUseCase.LoadProcedureMetadata(FProfile, FObjectName);
    except
      on E: Exception do
      begin
        LogMessage('ERRO AO CARREGAR METADADOS DA PROCEDURE: ' + E.Message);
        pgBottom.ActivePage := tsLog;
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  SetLength(PrevValues, 0);
  if Length(Meta.InputParams) > 0 then
  begin
    if SameText(FLastParamProcName, FObjectName) then
      PrevValues := FLastParamValues;
    if not TProcedureParamsForm.Execute(Meta, FUseCase, PrevValues, ParamValues, AutoCommit) then
      Exit;
    FLastParamValues := ParamValues;
    FLastParamProcName := FObjectName;
  end
  else
  begin
    SetLength(ParamValues, 0);
    AutoCommit := True;
  end;

  Screen.Cursor := crHourGlass;
  try
    try
      Res := FUseCase.ExecuteProcedure(FProfile, Meta, ParamValues, AutoCommit, ExecutedSQL);
    except
      on E: Exception do
      begin
        LogMessage('ERRO AO EXECUTAR: ' + E.Message);
        pgBottom.ActivePage := tsLog;
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  LogMessage('Executando: ' + ExecutedSQL);

  if FResultGrid <> nil then
    FResultGrid.SetResult(nil, False, False);
  FreeAndNil(FLastResult);
  FLastResult := Res;

  if FLastResult = nil then
  begin
    if FResultGrid <> nil then
      FResultGrid.SetResult(nil, True, False);
    tsResult.Caption := 'Resultado';
    LogMessage('ERRO AO EXECUTAR: Resultado vazio.');
    pgBottom.ActivePage := tsLog;
    Exit;
  end;

  if not FLastResult.Success then
  begin
    if FResultGrid <> nil then
      FResultGrid.SetResult(nil, True, False);
    tsResult.Caption := 'Resultado';
    LogMessage('ERRO AO EXECUTAR: ' + FLastResult.MessageText);
    pgBottom.ActivePage := tsLog;
  end
  else if FLastResult.HasResultSet and (FLastResult.ColumnCount > 0) then
  begin
    if FResultGrid <> nil then
      FResultGrid.SetResult(FLastResult, True, True);
    if FLastResult.SystemMemoryLow then
      tsResult.Caption := Format('Resultado (%d | RAM SO baixa)', [FLastResult.RowCount])
    else if FLastResult.MemoryLimitReached then
      tsResult.Caption := Format('Resultado (%d | Limite RAM)', [FLastResult.RowCount])
    else
      tsResult.Caption := Format('Resultado (%d)', [FLastResult.RowCount]);
    LogMessage(Format('SUCESSO: %s (%d ms)', [FLastResult.MessageText, FLastResult.ExecutionTimeMs]));
    if FLastResult.MemoryLimitReached then
      LogMessage('AVISO: ' + FLastResult.LimitMessage);
    if pgBottom.Height < 220 then
    begin
      TargetH := Min(280, Max(180, ClientHeight div 2));
      if TargetH > pgBottom.Height then
        pgBottom.Height := TargetH;
    end;
    pgBottom.ActivePage := tsResult;
    if FLastResult.SystemMemoryLow then
      MessageDlg('Proteção de Memória RAM do Sistema', FLastResult.LimitMessage, mtWarning, [mbOK], 0);
  end
  else
  begin
    if FResultGrid <> nil then
    begin
      FResultGrid.SetResult(nil, True, False);
      FResultGrid.SetCustomSummary('Procedure executada com sucesso (sem parâmetros de saída).');
    end;
    tsResult.Caption := 'Resultado';
    LogMessage(Format('SUCESSO: Procedure "%s" executada (%d ms).', [FObjectName, FLastResult.ExecutionTimeMs]));
    pgBottom.ActivePage := tsLog;
  end;
end;

procedure TObjectEditorFrame.btnReloadClick(Sender: TObject);
var
  DDL: string;
begin
  if (FUseCase = nil) or (FProfile = nil) or FIsNewObject then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    try
      DDL := FUseCase.LoadObjectDDL(FProfile, FObjectKind, FObjectName);
      SynEdit1.Lines.Text := DDL;
      LogMessage('Definição recarregada do banco de dados.');
    except
      on E: Exception do
      begin
        LogMessage('ERRO AO RECARREGAR: ' + E.Message);
        pgBottom.ActivePage := tsLog;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TObjectEditorFrame.btnCopyDDLClick(Sender: TObject);
begin
  Clipboard.AsText := SynEdit1.Lines.Text;
  LogMessage('DDL copiado para a área de transferência.');
end;

procedure TObjectEditorFrame.btnViewDataClick(Sender: TObject);
begin
  if (FProfile <> nil) and (FObjectKind in [sokTables, sokViews]) and Assigned(FOnOpenViewData) then
    FOnOpenViewData(FProfile.Id, FObjectName);
end;

procedure TObjectEditorFrame.btnDropObjectClick(Sender: TObject);
var
  Msg: string;
begin
  if (FUseCase = nil) or (FProfile = nil) or FIsNewObject then
    Exit;

  if MessageDlg('Confirmar Exclusão',
    Format('Deseja realmente excluir "%s" do banco "%s"?', [FObjectName, FProfile.Name]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    if FUseCase.DropObject(FProfile, FObjectKind, FObjectName, Msg) then
    begin
      LogMessage('SUCESSO: ' + Msg);
      btnCompile.Enabled := False;
      btnExecute.Enabled := False;
      btnReload.Enabled := False;
      btnViewData.Visible := False;
      btnDropObject.Enabled := False;
      UpdateToolbarLayout;
      if Assigned(FOnObjectChanged) then
        FOnObjectChanged(FProfile.Id, FObjectKind);
    end
    else
    begin
      LogMessage('ERRO AO EXCLUIR: ' + Msg);
      pgBottom.ActivePage := tsLog;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TObjectEditorFrame.SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F9) and (Shift = []) then
  begin
    Key := 0;
    btnCompileClick(Sender);
  end
  else if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    btnCompileClick(Sender);
  end
  else if (Key = VK_F8) and (Shift = []) and
          (FObjectKind = sokProcedures) and btnExecute.Visible and btnExecute.Enabled then
  begin
    Key := 0;
    btnExecuteClick(Sender);
  end;
end;

end.
