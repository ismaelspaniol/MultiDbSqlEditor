unit Presentation.SqlEditorFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Grids, Menus, LCLType, LCLIntf, LCLProc,
  SynEdit, SynHighlighterSQL, SynCompletion,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Application.ExecuteQueryUseCase;

type
  { TSqlEditorFrame }
  TSqlEditorFrame = class(TFrame)
    pnlToolbar: TPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    btnExecute: TButton;
    btnCommit: TButton;
    btnRollback: TButton;
    chkAutoCommit: TCheckBox;
    lblBatchSize: TLabel;
    cbBatchSize: TComboBox;
    btnFetchAll: TButton;
    btnOpenSql: TButton;
    btnSaveSql: TButton;
    btnExportCsv: TButton;
    lblTxStatus: TLabel;
    SynEdit1: TSynEdit;
    SynSQLSyn1: TSynSQLSyn;
    Splitter1: TSplitter;
    pgBottom: TPageControl;
    tsData: TTabSheet;
    tsMessages: TTabSheet;
    grdResults: TDrawGrid;
    pnlGridFooter: TPanel;
    lblGridSummary: TLabel;
    memMessages: TMemo;
    dlgOpenSql: TOpenDialog;
    dlgSaveSql: TSaveDialog;
    dlgSaveCsv: TSaveDialog;
    procedure btnExecuteClick(Sender: TObject);
    procedure btnCommitClick(Sender: TObject);
    procedure btnRollbackClick(Sender: TObject);
    procedure btnFetchAllClick(Sender: TObject);
    procedure btnOpenSqlClick(Sender: TObject);
    procedure btnSaveSqlClick(Sender: TObject);
    procedure btnExportCsvClick(Sender: TObject);
    procedure cbConnectionChange(Sender: TObject);
    procedure grdResultsDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure grdResultsTopLeftChanged(Sender: TObject);
    procedure grdResultsHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
    procedure SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FFactory: IDatabaseProviderFactory;
    FExecuteUseCase: TExecuteQueryUseCase;
    FSession: IDatabaseSession;
    FActiveProfileId: string;
    FProfiles: TConnectionProfileList;
    FLastResult: TQueryResult;
    FIsFetchingMore: Boolean;
    FSortCol: Integer;
    FSortAsc: Boolean;
    FCompletion: TSynCompletion;
    FCachedTables: TStringList;
    procedure LogMessage(const AMsg: string);
    procedure UpdateTransactionUI;
    procedure UpdateGridFromResult;
    procedure UpdateDataTabCaption;
    procedure TryFetchMoreRows;
    procedure ApplyHighlighterForProfile(const AProfile: TConnectionProfile);
    procedure CompletionExecute(Sender: TObject);
    procedure CompletionKeyNextChar(Sender: TObject);
    procedure CompletionKeyPrevChar(Sender: TObject);
    function EnsureSessionConnected: Boolean;
    procedure EnsureTablesCached;
    function ExtractPrefixBeforeCaret: string;
    function ExtractWordBeforeDot: string;
    procedure LoadColumnsForTable(const ATableName: string; const ATarget: TStrings);
    function SelectedProfile: TConnectionProfile;
    function CurrentBatchSize: Integer;
    function EscapeCsvField(const AValue: string): string;
  public
    destructor Destroy; override;
    procedure Initialize(
      const AFactory: IDatabaseProviderFactory;
      const AExecuteUseCase: TExecuteQueryUseCase;
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string = ''
    );
    procedure RefreshConnections(const AConnections: TConnectionProfileList);
    procedure ExecuteCurrentSQL;
    function ActiveProfileId: string;
    function SqlText: string;
    procedure SetSqlText(const ASql: string);
    function BatchSizeText: string;
    procedure SetBatchSizeText(const AValue: string);
    function AutoCommit: Boolean;
    procedure SetAutoCommit(const AValue: Boolean);
  end;

implementation

{$R *.lfm}

destructor TSqlEditorFrame.Destroy;
begin
  if FSession <> nil then
  begin
    try
      if FSession.InTransaction then
        FSession.Rollback;
      FSession.Disconnect;
    except
    end;
    FSession := nil;
  end;
  FreeAndNil(FLastResult);
  FreeAndNil(FCachedTables);
  FreeAndNil(FProfiles);
  inherited Destroy;
end;

procedure TSqlEditorFrame.Initialize(
  const AFactory: IDatabaseProviderFactory;
  const AExecuteUseCase: TExecuteQueryUseCase;
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string
);
begin
  FFactory := AFactory;
  FExecuteUseCase := AExecuteUseCase;
  FActiveProfileId := AInitialProfileId;
  FSortCol := -1;
  FSortAsc := True;

  SynSQLSyn1.Enabled := True;
  SynEdit1.Highlighter := SynSQLSyn1;
  SynEdit1.Keystrokes.ResetDefaults;

  FCachedTables := TStringList.Create;
  FCachedTables.Sorted := True;
  FCachedTables.Duplicates := dupIgnore;

  FCompletion := TSynCompletion.Create(Self);
  FCompletion.Editor := SynEdit1;
  FCompletion.ShortCut := Menus.ShortCut(VK_SPACE, [ssCtrl]);
  FCompletion.OnExecute := @CompletionExecute;
  FCompletion.OnKeyNextChar := @CompletionKeyNextChar;
  FCompletion.OnKeyPrevChar := @CompletionKeyPrevChar;

  grdResults.ColCount := 1;
  grdResults.RowCount := 1;
  lblGridSummary.Caption := 'Nenhuma consulta executada.';

  RefreshConnections(AConnections);
  UpdateTransactionUI;
end;

procedure TSqlEditorFrame.RefreshConnections(const AConnections: TConnectionProfileList);
var
  Item, Cloned: TConnectionProfile;
  Idx, SelectedIdx: Integer;
  TargetId: string;
begin
  TargetId := FActiveProfileId;
  if (TargetId = '') and (SelectedProfile <> nil) then
    TargetId := SelectedProfile.Id;

  FreeAndNil(FProfiles);
  FProfiles := TConnectionProfileList.Create(True);

  cbConnection.Items.BeginUpdate;
  try
    cbConnection.Items.Clear;
    SelectedIdx := -1;
    if AConnections <> nil then
    begin
      for Item in AConnections do
      begin
        Cloned := Item.Clone;
        FProfiles.Add(Cloned);
        Idx := cbConnection.Items.AddObject(
          Format('%s [%s]', [Cloned.Name, DatabaseTypeToStr(Cloned.DatabaseType)]),
          Cloned
        );
        if (TargetId <> '') and SameText(Cloned.Id, TargetId) then
          SelectedIdx := Idx;
      end;
    end;

    if (SelectedIdx = -1) and (cbConnection.Items.Count > 0) then
      SelectedIdx := 0;

    cbConnection.ItemIndex := SelectedIdx;
    if SelectedProfile <> nil then
    begin
      FActiveProfileId := SelectedProfile.Id;
      ApplyHighlighterForProfile(SelectedProfile);
    end;
  finally
    cbConnection.Items.EndUpdate;
  end;
end;

function TSqlEditorFrame.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection.ItemIndex >= 0) and (cbConnection.ItemIndex < cbConnection.Items.Count) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

procedure TSqlEditorFrame.ApplyHighlighterForProfile(const AProfile: TConnectionProfile);
begin
  if AProfile = nil then
    Exit;
  if AProfile.DatabaseType = dtPostgreSQL then
    SynSQLSyn1.SQLDialect := sqlPostgres
  else
    SynSQLSyn1.SQLDialect := sqlFirebird40;
end;

procedure TSqlEditorFrame.cbConnectionChange(Sender: TObject);
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if (Profile <> nil) and SameText(Profile.Id, FActiveProfileId) then
    Exit;

  if FSession <> nil then
  begin
    try
      if FSession.InTransaction then
        FSession.Rollback;
      FSession.Disconnect;
    except
    end;
    FSession := nil;
  end;

  if FCachedTables <> nil then
    FCachedTables.Clear;

  if Profile <> nil then
  begin
    FActiveProfileId := Profile.Id;
    ApplyHighlighterForProfile(Profile);
    LogMessage('Conexão alterada para: ' + Profile.Name);
  end
  else
    FActiveProfileId := '';

  UpdateTransactionUI;
end;

procedure TSqlEditorFrame.LogMessage(const AMsg: string);
begin
  memMessages.Lines.Add(Format('[%s] %s', [FormatDateTime('hh:nn:ss', Now), AMsg]));
end;

procedure TSqlEditorFrame.UpdateTransactionUI;
begin
  if (FSession = nil) or (not FSession.IsConnected) then
  begin
    btnCommit.Enabled := False;
    btnRollback.Enabled := False;
    lblTxStatus.Caption := 'Desconectado';
    lblTxStatus.Font.Color := clGrayText;
  end
  else if FSession.InTransaction then
  begin
    btnCommit.Enabled := True;
    btnRollback.Enabled := True;
    lblTxStatus.Caption := 'Em Transação';
    lblTxStatus.Font.Color := clMaroon;
  end
  else
  begin
    btnCommit.Enabled := False;
    btnRollback.Enabled := False;
    lblTxStatus.Caption := 'Conectado';
    lblTxStatus.Font.Color := clGreen;
  end;
end;

procedure TSqlEditorFrame.UpdateDataTabCaption;
begin
  if (FLastResult = nil) or (not FLastResult.HasResultSet) then
  begin
    tsData.Caption := 'Dados (Grid)';
    if FLastResult = nil then
      lblGridSummary.Caption := 'Nenhuma consulta executada.'
    else
      lblGridSummary.Caption := FLastResult.MessageText;
  end
  else if FLastResult.HasMoreRows then
  begin
    tsData.Caption := Format('Dados (%d+)', [FLastResult.RowCount]);
    lblGridSummary.Caption := Format(
      'Registros carregados: %d (role para carregar mais ou clique em Fetch All) | Tempo: %d ms',
      [FLastResult.RowCount, FLastResult.ExecutionTimeMs]
    );
  end
  else
  begin
    tsData.Caption := Format('Dados (%d)', [FLastResult.RowCount]);
    lblGridSummary.Caption := Format(
      'Total de registros: %d | Tempo: %d ms',
      [FLastResult.RowCount, FLastResult.ExecutionTimeMs]
    );
  end;
  btnFetchAll.Enabled := (FLastResult <> nil) and FLastResult.HasMoreRows;
end;

procedure TSqlEditorFrame.UpdateGridFromResult;
var
  I: Integer;
begin
  if (FLastResult = nil) or (not FLastResult.HasResultSet) or (FLastResult.ColumnCount = 0) then
  begin
    grdResults.ColCount := 1;
    grdResults.RowCount := 1;
    grdResults.Invalidate;
    UpdateDataTabCaption;
    Exit;
  end;

  grdResults.ColCount := FLastResult.ColumnCount;
  grdResults.RowCount := FLastResult.RowCount + 1;
  grdResults.FixedRows := 1;
  for I := 0 to FLastResult.ColumnCount - 1 do
    grdResults.ColWidths[I] := 150;
  grdResults.Invalidate;
  UpdateDataTabCaption;
end;

function TSqlEditorFrame.CurrentBatchSize: Integer;
var
  S: string;
begin
  S := LowerCase(Trim(cbBatchSize.Text));
  if (S = '') or (S = 'todos') or (S = 'all') or (S = '0') then
    Result := 0
  else
  begin
    Result := StrToIntDef(S, 100);
    if Result < 0 then
      Result := 100;
  end;
end;

procedure TSqlEditorFrame.TryFetchMoreRows;
var
  Fetched, Batch: Integer;
begin
  if FIsFetchingMore or (FLastResult = nil) or (not FLastResult.HasMoreRows) then
    Exit;

  if grdResults.TopRow + grdResults.VisibleRowCount < grdResults.RowCount - 10 then
    Exit;

  Batch := CurrentBatchSize;
  if Batch <= 0 then
    Batch := 100;

  FIsFetchingMore := True;
  try
    Fetched := FLastResult.FetchMore(Batch);
    if Fetched > 0 then
    begin
      grdResults.RowCount := FLastResult.RowCount + 1;
      UpdateDataTabCaption;
      if not FLastResult.HasMoreRows then
        LogMessage(Format('Todos os %d registros foram carregados.', [FLastResult.RowCount]));
    end
    else
      UpdateDataTabCaption;
  finally
    FIsFetchingMore := False;
  end;
end;

procedure TSqlEditorFrame.btnFetchAllClick(Sender: TObject);
var
  StartTick: QWord;
  Fetched: Integer;
begin
  if (FLastResult = nil) or (not FLastResult.HasMoreRows) then
    Exit;

  Screen.Cursor := crHourGlass;
  FIsFetchingMore := True;
  StartTick := GetTickCount64;
  try
    Fetched := FLastResult.FetchAll;
    grdResults.RowCount := FLastResult.RowCount + 1;
    UpdateDataTabCaption;
    LogMessage(Format('Fetch All: +%d registro(s), total %d (%d ms).',
      [Fetched, FLastResult.RowCount, Int64(GetTickCount64 - StartTick)]));
  finally
    FIsFetchingMore := False;
    Screen.Cursor := crDefault;
  end;
end;

procedure TSqlEditorFrame.grdResultsTopLeftChanged(Sender: TObject);
begin
  TryFetchMoreRows;
end;

procedure TSqlEditorFrame.grdResultsHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
begin
  if (not IsColumn) or (FLastResult = nil) or (not FLastResult.HasResultSet) then
    Exit;
  if (Index < 0) or (Index >= FLastResult.ColumnCount) then
    Exit;

  if FSortCol = Index then
    FSortAsc := not FSortAsc
  else
  begin
    FSortCol := Index;
    FSortAsc := True;
  end;

  FLastResult.SortByColumn(FSortCol, FSortAsc);
  grdResults.Invalidate;
end;

procedure TSqlEditorFrame.ExecuteCurrentSQL;
var
  Profile: TConnectionProfile;
  SQLToRun: string;
  Provider: IDatabaseProvider;
  NewResult: TQueryResult;
begin
  Profile := SelectedProfile;
  if Profile = nil then
  begin
    MessageDlg('Aviso', 'Selecione ou cadastre uma conexão antes de executar.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if SynEdit1.SelAvail then
    SQLToRun := SynEdit1.SelText
  else
    SQLToRun := SynEdit1.Lines.Text;

  if Trim(SQLToRun) = '' then
  begin
    LogMessage('Nenhuma instrução SQL para executar.');
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    try
      if FSession = nil then
      begin
        Provider := FFactory.GetProvider(Profile.DatabaseType);
        FSession := Provider.CreateSession(Profile);
      end;

      FreeAndNil(FLastResult);
      FSortCol := -1;
      FSortAsc := True;
      NewResult := FExecuteUseCase.Execute(FSession, SQLToRun, chkAutoCommit.Checked, CurrentBatchSize);
      FLastResult := NewResult;

      UpdateGridFromResult;
      btnExportCsv.Enabled := (FLastResult <> nil) and FLastResult.HasResultSet and (FLastResult.RowCount > 0);

      if FLastResult.Success then
      begin
        LogMessage(Format('%s (%d ms)', [FLastResult.MessageText, FLastResult.ExecutionTimeMs]));
        if FLastResult.HasResultSet then
          pgBottom.ActivePage := tsData
        else
          pgBottom.ActivePage := tsMessages;
      end
      else
      begin
        LogMessage('ERRO: ' + FLastResult.MessageText);
        pgBottom.ActivePage := tsMessages;
      end;
    except
      on E: Exception do
      begin
        LogMessage('ERRO: ' + E.Message);
        pgBottom.ActivePage := tsMessages;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
    UpdateTransactionUI;
  end;
end;

procedure TSqlEditorFrame.btnExecuteClick(Sender: TObject);
begin
  ExecuteCurrentSQL;
end;

procedure TSqlEditorFrame.btnCommitClick(Sender: TObject);
begin
  if FSession = nil then
    Exit;
  try
    FSession.Commit;
    LogMessage('Transação confirmada (COMMIT).');
  except
    on E: Exception do
      LogMessage('ERRO ao executar COMMIT: ' + E.Message);
  end;
  UpdateTransactionUI;
end;

procedure TSqlEditorFrame.btnRollbackClick(Sender: TObject);
begin
  if FSession = nil then
    Exit;
  try
    FSession.Rollback;
    LogMessage('Transação desfeita (ROLLBACK).');
  except
    on E: Exception do
      LogMessage('ERRO ao executar ROLLBACK: ' + E.Message);
  end;
  UpdateTransactionUI;
end;

procedure TSqlEditorFrame.btnOpenSqlClick(Sender: TObject);
begin
  if dlgOpenSql.Execute then
  begin
    SynEdit1.Lines.LoadFromFile(dlgOpenSql.FileName);
    LogMessage('Arquivo carregado: ' + dlgOpenSql.FileName);
  end;
end;

procedure TSqlEditorFrame.btnSaveSqlClick(Sender: TObject);
begin
  if dlgSaveSql.Execute then
  begin
    SynEdit1.Lines.SaveToFile(dlgSaveSql.FileName);
    LogMessage('Arquivo salvo: ' + dlgSaveSql.FileName);
  end;
end;

function TSqlEditorFrame.EscapeCsvField(const AValue: string): string;
begin
  if (Pos(';', AValue) > 0) or (Pos('"', AValue) > 0) or
     (Pos(#10, AValue) > 0) or (Pos(#13, AValue) > 0) then
    Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AValue;
end;

procedure TSqlEditorFrame.btnExportCsvClick(Sender: TObject);
var
  SL: TStringList;
  R, C: Integer;
  Line: string;
  Row: TQueryRow;
begin
  if (FLastResult = nil) or (not FLastResult.HasResultSet) or (FLastResult.RowCount = 0) then
    Exit;

  if not dlgSaveCsv.Execute then
    Exit;

  SL := TStringList.Create;
  try
    Line := '';
    for C := 0 to FLastResult.ColumnCount - 1 do
    begin
      if C > 0 then
        Line := Line + ';';
      Line := Line + EscapeCsvField(FLastResult.GetColumn(C).Name);
    end;
    SL.Add(Line);

    for R := 0 to FLastResult.RowCount - 1 do
    begin
      Row := FLastResult.GetRow(R);
      Line := '';
      for C := 0 to FLastResult.ColumnCount - 1 do
      begin
        if C > 0 then
          Line := Line + ';';
        if not Row[C].IsNull then
          Line := Line + EscapeCsvField(Row[C].AsText);
      end;
      SL.Add(Line);
    end;

    SL.SaveToFile(dlgSaveCsv.FileName, TEncoding.UTF8);
    LogMessage('Resultado exportado para CSV: ' + dlgSaveCsv.FileName);
  finally
    SL.Free;
  end;
end;

procedure TSqlEditorFrame.grdResultsDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
var
  CellText: string;
  Row: TQueryRow;
  TextRect: TRect;
begin
  if (FLastResult = nil) or (not FLastResult.HasResultSet) or (FLastResult.ColumnCount = 0) then
    Exit;

  TextRect := aRect;
  InflateRect(TextRect, -4, -2);

  if aRow = 0 then
  begin
    if aCol < FLastResult.ColumnCount then
    begin
      grdResults.Canvas.Font.Style := [fsBold];
      grdResults.Canvas.Font.Color := clWindowText;
      CellText := FLastResult.GetColumn(aCol).Name;
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

  if (aRow - 1 < FLastResult.RowCount) and (aCol < FLastResult.ColumnCount) then
  begin
    Row := FLastResult.GetRow(aRow - 1);
    if Row[aCol].IsNull then
    begin
      grdResults.Canvas.Font.Style := [fsItalic];
      if gdSelected in aState then
        grdResults.Canvas.Font.Color := clHighlightText
      else
        grdResults.Canvas.Font.Color := clGrayText;
      CellText := '(NULL)';
    end
    else
    begin
      grdResults.Canvas.Font.Style := [];
      if gdSelected in aState then
        grdResults.Canvas.Font.Color := clHighlightText
      else
        grdResults.Canvas.Font.Color := clWindowText;
      CellText := Row[aCol].AsText;
    end;
    grdResults.Canvas.TextRect(TextRect, TextRect.Left, TextRect.Top, CellText);
  end;
end;

procedure TSqlEditorFrame.SynEdit1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F9) and (Shift = []) then
  begin
    Key := 0;
    ExecuteCurrentSQL;
  end
  else if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    ExecuteCurrentSQL;
  end;
end;

function TSqlEditorFrame.ActiveProfileId: string;
var
  Profile: TConnectionProfile;
begin
  Profile := SelectedProfile;
  if Profile <> nil then
    Result := Profile.Id
  else
    Result := FActiveProfileId;
end;

function TSqlEditorFrame.SqlText: string;
begin
  Result := SynEdit1.Lines.Text;
end;

procedure TSqlEditorFrame.SetSqlText(const ASql: string);
begin
  SynEdit1.Lines.Text := ASql;
end;

function TSqlEditorFrame.BatchSizeText: string;
begin
  Result := cbBatchSize.Text;
end;

procedure TSqlEditorFrame.SetBatchSizeText(const AValue: string);
begin
  if Trim(AValue) <> '' then
    cbBatchSize.Text := AValue;
end;

function TSqlEditorFrame.AutoCommit: Boolean;
begin
  Result := chkAutoCommit.Checked;
end;

procedure TSqlEditorFrame.SetAutoCommit(const AValue: Boolean);
begin
  chkAutoCommit.Checked := AValue;
end;

function TSqlEditorFrame.EnsureSessionConnected: Boolean;
var
  Profile: TConnectionProfile;
  Provider: IDatabaseProvider;
begin
  Result := False;
  if (FSession <> nil) and FSession.IsConnected then
  begin
    Result := True;
    Exit;
  end;

  Profile := SelectedProfile;
  if (Profile = nil) or (FFactory = nil) then
    Exit;

  try
    if FSession = nil then
    begin
      Provider := FFactory.GetProvider(Profile.DatabaseType);
      FSession := Provider.CreateSession(Profile);
    end;
    if not FSession.IsConnected then
      FSession.Connect;
    Result := FSession.IsConnected;
    UpdateTransactionUI;
  except
    on E: Exception do
    begin
      LogMessage('Aviso ao conectar para autocompletar: ' + E.Message);
      Result := False;
    end;
  end;
end;

procedure TSqlEditorFrame.EnsureTablesCached;
var
  Profile: TConnectionProfile;
  SQL: string;
  Res: TQueryResult;
  I: Integer;
  TblName: string;
begin
  if (FCachedTables = nil) or (FCachedTables.Count > 0) then
    Exit;
  if not EnsureSessionConnected then
    Exit;

  Profile := SelectedProfile;
  if Profile = nil then
    Exit;

  if Profile.DatabaseType = dtPostgreSQL then
    SQL := 'SELECT table_name FROM information_schema.tables WHERE table_schema = ''public'' ORDER BY 1'
  else
    SQL := 'SELECT TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1';

  try
    Res := FSession.ExecuteSQL(SQL, False, 0);
    try
      if Res.Success and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          TblName := Trim(Res.GetRow(I)[0].AsText);
          if TblName <> '' then
            FCachedTables.Add(TblName);
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;
end;

function TSqlEditorFrame.ExtractPrefixBeforeCaret: string;
var
  Line: string;
  EndPos, StartPos: Integer;
begin
  Result := '';
  Line := SynEdit1.LineText;
  EndPos := SynEdit1.CaretX - 1;
  if EndPos > Length(Line) then
    EndPos := Length(Line);
  if EndPos < 1 then
    Exit;

  StartPos := EndPos;
  while (StartPos >= 1) and (Line[StartPos] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) do
    Dec(StartPos);
  Inc(StartPos);
  if StartPos <= EndPos then
    Result := Copy(Line, StartPos, EndPos - StartPos + 1);
end;

function TSqlEditorFrame.ExtractWordBeforeDot: string;
var
  Line, PrefixBefore: string;
  P, StartPos: Integer;
begin
  Result := '';
  Line := SynEdit1.LineText;
  PrefixBefore := ExtractPrefixBeforeCaret;
  P := SynEdit1.CaretX - 1 - Length(PrefixBefore);
  if (P >= 1) and (P <= Length(Line)) and (Line[P] = '.') then
  begin
    Dec(P);
    StartPos := P;
    while (StartPos >= 1) and (Line[StartPos] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) do
      Dec(StartPos);
    Inc(StartPos);
    if StartPos <= P then
      Result := Copy(Line, StartPos, P - StartPos + 1);
  end;
end;

procedure TSqlEditorFrame.LoadColumnsForTable(const ATableName: string; const ATarget: TStrings);
var
  Profile: TConnectionProfile;
  SQL, ColName, SafeTable: string;
  Res: TQueryResult;
  I: Integer;
begin
  if (Trim(ATableName) = '') or (not EnsureSessionConnected) then
    Exit;

  Profile := SelectedProfile;
  if Profile = nil then
    Exit;

  SafeTable := StringReplace(Trim(ATableName), '''', '''''', [rfReplaceAll]);
  if Profile.DatabaseType = dtPostgreSQL then
    SQL := Format(
      'SELECT column_name FROM information_schema.columns WHERE table_schema = ''public'' AND lower(table_name) = lower(''%s'') ORDER BY ordinal_position',
      [SafeTable]
    )
  else
    SQL := Format(
      'SELECT TRIM(RDB$FIELD_NAME) FROM RDB$RELATION_FIELDS WHERE UPPER(TRIM(RDB$RELATION_NAME)) = UPPER(''%s'') ORDER BY RDB$FIELD_POSITION',
      [SafeTable]
    );

  try
    Res := FSession.ExecuteSQL(SQL, False, 0);
    try
      if Res.Success and Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          ColName := Trim(Res.GetRow(I)[0].AsText);
          if ColName <> '' then
            ATarget.Add(ColName);
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;
end;

procedure TSqlEditorFrame.CompletionExecute(Sender: TObject);
const
  SqlKeywords: array[0..30] of string = (
    'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IN', 'IS NULL', 'IS NOT NULL',
    'ORDER BY', 'GROUP BY', 'HAVING', 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'ON',
    'AS', 'DISTINCT', 'FIRST 100', 'LIMIT 100', 'INSERT INTO', 'VALUES',
    'UPDATE', 'SET', 'DELETE FROM', 'COUNT(*)', 'SUM(', 'AVG(', 'MIN(', 'MAX(',
    'COALESCE('
  );
var
  Prefix, TableBeforeDot: string;
  I: Integer;
  Candidates: TStringList;
begin
  FCompletion.ItemList.Clear;
  Prefix := ExtractPrefixBeforeCaret;
  FCompletion.CurrentString := Prefix;
  Prefix := LowerCase(Prefix);

  Candidates := TStringList.Create;
  try
    TableBeforeDot := ExtractWordBeforeDot;
    if TableBeforeDot <> '' then
      LoadColumnsForTable(TableBeforeDot, Candidates)
    else
    begin
      EnsureTablesCached;
      for I := 0 to FCachedTables.Count - 1 do
        Candidates.Add(FCachedTables[I]);
      for I := Low(SqlKeywords) to High(SqlKeywords) do
        Candidates.Add(SqlKeywords[I]);
    end;

    for I := 0 to Candidates.Count - 1 do
    begin
      if (Prefix = '') or (Pos(Prefix, LowerCase(Candidates[I])) = 1) then
        FCompletion.ItemList.Add(Candidates[I]);
    end;
  finally
    Candidates.Free;
  end;
end;

procedure TSqlEditorFrame.CompletionKeyNextChar(Sender: TObject);
begin
  if SynEdit1.CaretX <= Length(SynEdit1.LineText) then
    SynEdit1.CaretX := SynEdit1.CaretX + 1;
  CompletionExecute(FCompletion);
end;

procedure TSqlEditorFrame.CompletionKeyPrevChar(Sender: TObject);
begin
  if SynEdit1.CaretX > 1 then
    SynEdit1.CaretX := SynEdit1.CaretX - 1;
  CompletionExecute(FCompletion);
end;

end.
