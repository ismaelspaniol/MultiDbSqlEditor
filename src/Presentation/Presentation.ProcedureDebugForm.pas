unit Presentation.ProcedureDebugForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Grids, LCLType, SynEdit, SynEditMarks, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Domain.PsqlDebugger,
  Application.ManageDatabaseObjectsUseCase;

type
  { Formulário de Debug passo-a-passo estilo IBExpert para Procedures Firebird }
  TProcedureDebugForm = class(TForm)
    pnlToolbar: TPanel;
    btnRun: TButton;
    btnStepOver: TButton;
    btnStepInto: TButton;
    btnRunToCursor: TButton;
    btnToggleBp: TButton;
    btnRestart: TButton;
    chkRollback: TCheckBox;
    lblStatus: TLabel;
    pnlMain: TPanel;
    SynEdit1: TSynEdit;
    SplitterV: TSplitter;
    pnlInspector: TPanel;
    pnlVars: TPanel;
    lblVars: TLabel;
    gridVars: TStringGrid;
    SplitterVars: TSplitter;
    pnlFields: TPanel;
    lblFields: TLabel;
    gridFields: TStringGrid;
    SplitterH: TSplitter;
    pgBottom: TPageControl;
    tsResults: TTabSheet;
    tsLog: TTabSheet;
    gridResults: TStringGrid;
    memLog: TMemo;
    SynSQLSyn1: TSynSQLSyn;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnRunClick(Sender: TObject);
    procedure btnStepOverClick(Sender: TObject);
    procedure btnStepIntoClick(Sender: TObject);
    procedure btnRunToCursorClick(Sender: TObject);
    procedure btnToggleBpClick(Sender: TObject);
    procedure btnRestartClick(Sender: TObject);
    procedure SynEdit1GutterClick(Sender: TObject; X, Y, Line: Integer; Mark: TSynEditMark);
    procedure SynEdit1SpecialLineColors(Sender: TObject; Line: Integer;
      var Special: Boolean; var FG, BG: TColor);
    procedure gridVarsPrepareCanvas(Sender: TObject; aCol, aRow: Integer;
      aState: TGridDrawState);
  private
    FProfile: TConnectionProfile;
    FMeta: TProcedureMetadata;
    FInputValues: TProcedureParamValueArray;
    FDDL: string;
    FUseCase: TManageDatabaseObjectsUseCase;
    FFactory: IDatabaseProviderFactory;
    FSession: IDatabaseSession;
    FDebugger: TPsqlDebugger;
    FIsRunning: Boolean;
    FIsTriggerMode: Boolean;
    FTriggerName: string;
    FTriggerEvent: string;
    FOldFields: TDebugParamDeclArray;
    FNewFields: TDebugParamDeclArray;
    edtVarsFilter: TEdit;
    edtResultsFilter: TEdit;
    FFilteredVarIndices: array of Integer;

    procedure edtVarsFilterChange(Sender: TObject);
    procedure edtResultsFilterChange(Sender: TObject);

    function HandleDebugExecSql(const ASQL: string; out AError: string): TQueryResult;
    procedure HandleDebugLog(const AMsg: string);
    procedure HandleDebugYield(Sender: TObject);
    function BuildDebugParams: TDebugParamDeclArray;
    procedure EnsureSessionConnected;
    procedure EndSessionTransaction;
    procedure RefreshUI;
    procedure RefreshVarsGrid;
    procedure RefreshFieldsGrid;
    procedure RefreshResultsGrid;
    procedure HighlightCurrentLine;
    procedure SetupGrids;
  public
    class procedure Execute(
      const AProfile: TConnectionProfile;
      const AUseCase: TManageDatabaseObjectsUseCase;
      const AMeta: TProcedureMetadata;
      const AInputValues: TProcedureParamValueArray;
      const ADDL: string
    );
    class procedure ExecuteTrigger(
      const AProfile: TConnectionProfile;
      const AFactory: IDatabaseProviderFactory;
      const ATriggerName, ATableName, AEvent: string;
      const AOldFields, ANewFields: TDebugParamDeclArray;
      const ADDL: string
    );
  end;

implementation

{$R *.lfm}

function ScopeToLabel(const AScope: TDebugVarScope): string;
begin
  case AScope of
    dvsInput: Result := 'IN';
    dvsOutput: Result := 'OUT';
    dvsLocal: Result := 'LOCAL';
    dvsSystem: Result := 'SYS';
    dvsNew: Result := 'NEW';
    dvsOld: Result := 'OLD';
  else
    Result := '';
  end;
end;

{ TProcedureDebugForm }

class procedure TProcedureDebugForm.Execute(
  const AProfile: TConnectionProfile;
  const AUseCase: TManageDatabaseObjectsUseCase;
  const AMeta: TProcedureMetadata;
  const AInputValues: TProcedureParamValueArray;
  const ADDL: string
);
var
  Frm: TProcedureDebugForm;
begin
  Frm := TProcedureDebugForm.Create(Forms.Application);
  try
    Frm.FProfile := AProfile;
    Frm.FUseCase := AUseCase;
    Frm.FIsTriggerMode := False;
    Frm.FMeta := AMeta;
    Frm.FInputValues := AInputValues;
    Frm.FDDL := ADDL;
    Frm.Caption := Format('Debug Procedure: %s (%s)', [AMeta.ProcedureName, AProfile.Name]);
    Frm.SynEdit1.Lines.Text := ADDL;
    Frm.FDebugger.LoadProcedure(ADDL, Frm.BuildDebugParams);
    Frm.FDebugger.Start;
    Frm.RefreshUI;
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

class procedure TProcedureDebugForm.ExecuteTrigger(
  const AProfile: TConnectionProfile;
  const AFactory: IDatabaseProviderFactory;
  const ATriggerName, ATableName, AEvent: string;
  const AOldFields, ANewFields: TDebugParamDeclArray;
  const ADDL: string
);
var
  Frm: TProcedureDebugForm;
begin
  Frm := TProcedureDebugForm.Create(Forms.Application);
  try
    Frm.FProfile := AProfile;
    Frm.FFactory := AFactory;
    Frm.FIsTriggerMode := True;
    Frm.FTriggerName := ATriggerName;
    Frm.FTriggerEvent := AEvent;
    Frm.FOldFields := AOldFields;
    Frm.FNewFields := ANewFields;
    Frm.FDDL := ADDL;
    Frm.Caption := Format('Debug Trigger: %s [%s em %s] (%s)',
      [ATriggerName, AEvent, ATableName, AProfile.Name]);
    Frm.edtResultsFilter.Visible := True;
    Frm.SynEdit1.Lines.Text := ADDL;
    Frm.FDebugger.LoadTrigger(ADDL, AEvent, AOldFields, ANewFields);
    Frm.FDebugger.Start;
    Frm.RefreshUI;
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

procedure TProcedureDebugForm.FormCreate(Sender: TObject);
begin
  FDebugger := TPsqlDebugger.Create;
  FDebugger.OnExecSql := @HandleDebugExecSql;
  FDebugger.OnLog := @HandleDebugLog;
  FDebugger.OnYield := @HandleDebugYield;

  edtVarsFilter := TEdit.Create(Self);
  edtVarsFilter.Parent := pnlVars;
  edtVarsFilter.Align := alTop;
  edtVarsFilter.Top := lblVars.Top + lblVars.Height + 2;
  edtVarsFilter.BorderSpacing.Left := 4;
  edtVarsFilter.BorderSpacing.Right := 4;
  edtVarsFilter.BorderSpacing.Bottom := 4;
  edtVarsFilter.TextHint := 'Buscar variável / parâmetro...';
  edtVarsFilter.OnChange := @edtVarsFilterChange;

  edtResultsFilter := TEdit.Create(Self);
  edtResultsFilter.Parent := tsResults;
  edtResultsFilter.Align := alTop;
  edtResultsFilter.BorderSpacing.Around := 4;
  edtResultsFilter.TextHint := 'Buscar campo OLD vs NEW...';
  edtResultsFilter.Visible := False;
  edtResultsFilter.OnChange := @edtResultsFilterChange;

  SynEdit1.Keystrokes.ResetDefaults;
  SetupGrids;
end;

function TProcedureDebugForm.BuildDebugParams: TDebugParamDeclArray;
var
  I, K, Idx, InputIdx: Integer;
  P: TProcedureParamInfo;
  FoundVal: Boolean;
begin
  Result := nil;
  SetLength(Result, 0);
  InputIdx := 0;
  for I := 0 to High(FMeta.AllParams) do
  begin
    P := FMeta.AllParams[I];
    Idx := Length(Result);
    SetLength(Result, Idx + 1);
    Result[Idx].Name := P.Name;
    Result[Idx].DataType := P.DataTypeDisplay;
    Result[Idx].IsInput := (P.Mode in [ppmIn, ppmInOut]);
    Result[Idx].IsOutput := (P.Mode in [ppmOut, ppmInOut]);
    Result[Idx].IsNull := True;
    Result[Idx].Value := '';

    if Result[Idx].IsInput then
    begin
      FoundVal := False;
      for K := 0 to High(FInputValues) do
      begin
        if SameText(FInputValues[K].ParamName, P.Name) then
        begin
          Result[Idx].IsNull := FInputValues[K].IsNull;
          Result[Idx].Value := FInputValues[K].RawValue;
          FoundVal := True;
          Break;
        end;
      end;
      if (not FoundVal) and (InputIdx < Length(FInputValues)) then
      begin
        Result[Idx].IsNull := FInputValues[InputIdx].IsNull;
        Result[Idx].Value := FInputValues[InputIdx].RawValue;
      end;
      Inc(InputIdx);
    end;
  end;
end;

procedure TProcedureDebugForm.FormDestroy(Sender: TObject);
begin
  EndSessionTransaction;
  FSession := nil;
  FreeAndNil(FDebugger);
end;

procedure TProcedureDebugForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if FDebugger <> nil then
    FDebugger.RequestStop;
  EndSessionTransaction;
end;

procedure TProcedureDebugForm.SetupGrids;
begin
  gridVars.ColCount := 4;
  gridVars.RowCount := 1;
  gridVars.Cells[0, 0] := 'Nome';
  gridVars.Cells[1, 0] := 'Escopo';
  gridVars.Cells[2, 0] := 'Tipo';
  gridVars.Cells[3, 0] := 'Valor';
  gridVars.ColWidths[0] := 125;
  gridVars.ColWidths[1] := 55;
  gridVars.ColWidths[2] := 85;
  gridVars.ColWidths[3] := 125;

  gridFields.ColCount := 2;
  gridFields.RowCount := 1;
  gridFields.Cells[0, 0] := 'Campo';
  gridFields.Cells[1, 0] := 'Valor';
  gridFields.ColWidths[0] := 165;
  gridFields.ColWidths[1] := 225;
end;

procedure TProcedureDebugForm.EnsureSessionConnected;
begin
  if FSession = nil then
  begin
    if FUseCase <> nil then
      FSession := FUseCase.CreateSession(FProfile)
    else if FFactory <> nil then
      FSession := FFactory.GetProvider(FProfile.DatabaseType).CreateSession(FProfile);
    if FSession <> nil then
      FSession.Connect;
  end
  else if not FSession.IsConnected then
    FSession.Connect;
end;

procedure TProcedureDebugForm.EndSessionTransaction;
begin
  if FSession = nil then
    Exit;
  try
    if FSession.InTransaction then
    begin
      if chkRollback.Checked then
        FSession.Rollback
      else
        FSession.Commit;
    end;
  except
  end;
  try
    if FSession.IsConnected then
      FSession.Disconnect;
  except
  end;
end;

function TProcedureDebugForm.HandleDebugExecSql(
  const ASQL: string;
  out AError: string
): TQueryResult;
begin
  Result := nil;
  AError := '';
  try
    EnsureSessionConnected;
    Result := FSession.ExecuteSQL(ASQL, False, 0);
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := nil;
    end;
  end;
end;

procedure TProcedureDebugForm.HandleDebugLog(const AMsg: string);
begin
  memLog.Lines.Add(AMsg);
end;

procedure TProcedureDebugForm.HandleDebugYield(Sender: TObject);
begin
  Forms.Application.ProcessMessages;
end;

procedure TProcedureDebugForm.edtVarsFilterChange(Sender: TObject);
begin
  RefreshVarsGrid;
end;

procedure TProcedureDebugForm.edtResultsFilterChange(Sender: TObject);
begin
  RefreshResultsGrid;
end;

procedure TProcedureDebugForm.RefreshVarsGrid;
var
  I, RowIdx: Integer;
  V: TDebugVariable;
  Q, ValStr, Haystack: string;
begin
  Q := '';
  if edtVarsFilter <> nil then
    Q := LowerCase(Trim(edtVarsFilter.Text));

  SetLength(FFilteredVarIndices, 0);
  for I := 0 to FDebugger.VarCount - 1 do
  begin
    V := FDebugger.GetVar(I);
    if V.IsNull then
      ValStr := '<NULL>'
    else
      ValStr := V.Value;

    if Q <> '' then
    begin
      Haystack := LowerCase(V.Name + ' ' + ScopeToLabel(V.Scope) + ' ' + V.DataType + ' ' + ValStr);
      if Pos(Q, Haystack) = 0 then
        Continue;
    end;

    SetLength(FFilteredVarIndices, Length(FFilteredVarIndices) + 1);
    FFilteredVarIndices[High(FFilteredVarIndices)] := I;
  end;

  gridVars.RowCount := 1 + Length(FFilteredVarIndices);
  for I := 0 to High(FFilteredVarIndices) do
  begin
    V := FDebugger.GetVar(FFilteredVarIndices[I]);
    RowIdx := I + 1;
    gridVars.Cells[0, RowIdx] := V.Name;
    gridVars.Cells[1, RowIdx] := ScopeToLabel(V.Scope);
    gridVars.Cells[2, RowIdx] := V.DataType;
    if V.IsNull then
      gridVars.Cells[3, RowIdx] := '<NULL>'
    else
      gridVars.Cells[3, RowIdx] := V.Value;
  end;
  gridVars.Invalidate;
end;

procedure TProcedureDebugForm.RefreshFieldsGrid;
var
  I, RowIdx: Integer;
  F: TDebugFieldEntry;
begin
  gridFields.RowCount := 1 + FDebugger.CursorFieldCount;
  for I := 0 to FDebugger.CursorFieldCount - 1 do
  begin
    F := FDebugger.GetCursorField(I);
    RowIdx := I + 1;
    gridFields.Cells[0, RowIdx] := F.FieldName;
    if F.IsNull then
      gridFields.Cells[1, RowIdx] := '<NULL>'
    else
      gridFields.Cells[1, RowIdx] := F.Value;
  end;
end;

procedure TProcedureDebugForm.RefreshResultsGrid;
var
  C, R, Cols, Rows, I, J, MatchCount: Integer;
  FieldName, OldValStr, NewValStr, ModStr, Q, Haystack: string;
  OldNull, NewNull, IsMod: Boolean;
  V: TDebugVariable;
begin
  if FIsTriggerMode then
  begin
    tsResults.Caption := 'Campos OLD vs NEW';
    gridResults.ColCount := 4;
    gridResults.Cells[0, 0] := 'Campo';
    gridResults.Cells[1, 0] := 'OLD';
    gridResults.Cells[2, 0] := 'NEW';
    gridResults.Cells[3, 0] := 'Modificado';
    gridResults.ColWidths[0] := 180;
    gridResults.ColWidths[1] := 260;
    gridResults.ColWidths[2] := 260;
    gridResults.ColWidths[3] := 90;

    Q := '';
    if edtResultsFilter <> nil then
      Q := LowerCase(Trim(edtResultsFilter.Text));

    gridResults.RowCount := 1;
    MatchCount := 0;
    for I := 0 to High(FNewFields) do
    begin
      FieldName := FNewFields[I].Name;
      OldNull := True;
      OldValStr := '<NULL>';
      NewNull := True;
      NewValStr := '<NULL>';

      for J := 0 to FDebugger.VarCount - 1 do
      begin
        V := FDebugger.GetVar(J);
        if SameText(V.Name, 'OLD.' + FieldName) then
        begin
          OldNull := V.IsNull;
          if not V.IsNull then OldValStr := V.Value;
        end
        else if SameText(V.Name, 'NEW.' + FieldName) then
        begin
          NewNull := V.IsNull;
          if not V.IsNull then NewValStr := V.Value;
        end;
      end;

      IsMod := (OldNull <> NewNull) or ((not OldNull) and (OldValStr <> NewValStr));
      if IsMod then
        ModStr := 'Sim'
      else
        ModStr := '';

      if Q <> '' then
      begin
        Haystack := LowerCase(FieldName + ' ' + OldValStr + ' ' + NewValStr + ' ' + ModStr);
        if Pos(Q, Haystack) = 0 then
          Continue;
      end;

      Inc(MatchCount);
      gridResults.RowCount := 1 + MatchCount;
      gridResults.Cells[0, MatchCount] := FieldName;
      gridResults.Cells[1, MatchCount] := OldValStr;
      gridResults.Cells[2, MatchCount] := NewValStr;
      gridResults.Cells[3, MatchCount] := ModStr;
    end;
    Exit;
  end;

  Cols := FDebugger.OutputColCount;
  Rows := FDebugger.SuspendedRowCount;
  if Cols <= 0 then
  begin
    gridResults.ColCount := 1;
    gridResults.RowCount := 1;
    gridResults.Cells[0, 0] := '(Sem parâmetros RETURNS)';
    Exit;
  end;

  gridResults.ColCount := Cols;
  gridResults.RowCount := 1 + Rows;
  for C := 0 to Cols - 1 do
  begin
    gridResults.Cells[C, 0] := FDebugger.GetOutputColName(C);
    if gridResults.ColWidths[C] < 110 then
      gridResults.ColWidths[C] := 110;
  end;

  for R := 0 to Rows - 1 do
    for C := 0 to Cols - 1 do
      gridResults.Cells[C, R + 1] := FDebugger.GetSuspendedCell(R, C);

  tsResults.Caption := Format('Resultados (SUSPEND: %d)', [Rows]);
end;

procedure TProcedureDebugForm.HighlightCurrentLine;
begin
  if FDebugger.CurrentLine > 0 then
  begin
    SynEdit1.CaretY := FDebugger.CurrentLine;
    SynEdit1.EnsureCursorPosVisible;
  end;
  SynEdit1.Invalidate;
end;

procedure TProcedureDebugForm.RefreshUI;
var
  CanStep: Boolean;
begin
  RefreshVarsGrid;
  RefreshFieldsGrid;
  RefreshResultsGrid;
  HighlightCurrentLine;

  CanStep := FDebugger.State in [dsIdle, dsPaused];
  btnRun.Enabled := CanStep;
  btnStepOver.Enabled := CanStep;
  btnStepInto.Enabled := CanStep;
  btnRunToCursor.Enabled := CanStep;

  case FDebugger.State of
    dsIdle:
      begin
        lblStatus.Font.Color := clDefault;
        lblStatus.Caption := 'Pronto para iniciar';
      end;
    dsPaused:
      begin
        lblStatus.Font.Color := clNavy;
        lblStatus.Caption := Format('Pausado na linha %d (Passo %d)', [FDebugger.CurrentLine, FDebugger.StepCount]);
      end;
    dsFinished:
      begin
        lblStatus.Font.Color := clGreen;
        lblStatus.Caption := Format('Finalizado (%d passos, %d linhas)', [FDebugger.StepCount, FDebugger.SuspendedRowCount]);
      end;
    dsError:
      begin
        lblStatus.Font.Color := clRed;
        lblStatus.Caption := 'Erro na execução';
        memLog.Lines.Add('[ERRO] ' + FDebugger.LastError);
        pgBottom.ActivePage := tsLog;
      end;
  end;
end;

procedure TProcedureDebugForm.btnRunClick(Sender: TObject);
begin
  if FIsRunning then
    Exit;
  FIsRunning := True;
  btnRun.Enabled := False;
  btnStepOver.Enabled := False;
  btnStepInto.Enabled := False;
  btnRunToCursor.Enabled := False;
  lblStatus.Caption := 'Executando...';
  Screen.Cursor := crHourGlass;
  try
    FDebugger.Run;
  finally
    FIsRunning := False;
    Screen.Cursor := crDefault;
  end;
  RefreshUI;
end;

procedure TProcedureDebugForm.btnStepOverClick(Sender: TObject);
begin
  if FIsRunning then
    Exit;
  FDebugger.StepOver;
  RefreshUI;
end;

procedure TProcedureDebugForm.btnStepIntoClick(Sender: TObject);
begin
  if FIsRunning then
    Exit;
  FDebugger.StepInto;
  RefreshUI;
end;

procedure TProcedureDebugForm.btnRunToCursorClick(Sender: TObject);
begin
  if FIsRunning then
    Exit;
  FIsRunning := True;
  btnRun.Enabled := False;
  btnStepOver.Enabled := False;
  btnStepInto.Enabled := False;
  btnRunToCursor.Enabled := False;
  lblStatus.Caption := 'Executando até cursor...';
  Screen.Cursor := crHourGlass;
  try
    FDebugger.RunToLine(SynEdit1.CaretY);
  finally
    FIsRunning := False;
    Screen.Cursor := crDefault;
  end;
  RefreshUI;
end;

procedure TProcedureDebugForm.btnToggleBpClick(Sender: TObject);
begin
  FDebugger.ToggleBreakpoint(SynEdit1.CaretY);
  SynEdit1.Invalidate;
end;

procedure TProcedureDebugForm.btnRestartClick(Sender: TObject);
begin
  if FIsRunning then
  begin
    FDebugger.RequestStop;
    Exit;
  end;
  EndSessionTransaction;
  memLog.Clear;
  if FIsTriggerMode then
    FDebugger.LoadTrigger(FDDL, FTriggerEvent, FOldFields, FNewFields)
  else
    FDebugger.LoadProcedure(FDDL, BuildDebugParams);
  FDebugger.Start;
  RefreshUI;
end;

procedure TProcedureDebugForm.SynEdit1GutterClick(
  Sender: TObject;
  X, Y, Line: Integer;
  Mark: TSynEditMark
);
begin
  if Line > 0 then
  begin
    FDebugger.ToggleBreakpoint(Line);
    SynEdit1.Invalidate;
  end;
end;

procedure TProcedureDebugForm.SynEdit1SpecialLineColors(
  Sender: TObject;
  Line: Integer;
  var Special: Boolean;
  var FG, BG: TColor
);
var
  IsCurrent, IsBp: Boolean;
begin
  IsCurrent := (FDebugger <> nil) and (FDebugger.State = dsPaused) and (Line = FDebugger.CurrentLine);
  IsBp := (FDebugger <> nil) and FDebugger.HasBreakpoint(Line);

  if IsCurrent and IsBp then
  begin
    Special := True;
    FG := clBlack;
    BG := RGBToColor(255, 210, 140);
  end
  else if IsCurrent then
  begin
    Special := True;
    FG := clBlack;
    BG := RGBToColor(255, 243, 176);
  end
  else if IsBp then
  begin
    Special := True;
    FG := clBlack;
    BG := RGBToColor(255, 214, 214);
  end;
end;

procedure TProcedureDebugForm.gridVarsPrepareCanvas(
  Sender: TObject;
  aCol, aRow: Integer;
  aState: TGridDrawState
);
var
  V: TDebugVariable;
begin
  if (aRow <= 0) or (FDebugger = nil) or ((aRow - 1) >= Length(FFilteredVarIndices)) then
    Exit;
  if gdSelected in aState then
    Exit;

  V := FDebugger.GetVar(FFilteredVarIndices[aRow - 1]);
  if (V.LastChangedStep >= 0) and (V.LastChangedStep = FDebugger.StepCount) then
  begin
    gridVars.Canvas.Brush.Color := RGBToColor(224, 242, 254);
    gridVars.Canvas.Font.Color := clNavy;
    gridVars.Canvas.Font.Style := [fsBold];
  end
  else if V.IsNull then
  begin
    if aCol = 3 then
      gridVars.Canvas.Font.Color := clGray;
  end;
end;

procedure TProcedureDebugForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F9) and (Shift = []) then
  begin
    Key := 0;
    btnRunClick(nil);
  end
  else if (Key = VK_F8) and (Shift = []) then
  begin
    Key := 0;
    btnStepOverClick(nil);
  end
  else if (Key = VK_F7) and (Shift = []) then
  begin
    Key := 0;
    btnStepIntoClick(nil);
  end
  else if (Key = VK_F5) and (Shift = []) then
  begin
    Key := 0;
    btnToggleBpClick(nil);
  end
  else if (Key = VK_F4) and (Shift = []) then
  begin
    Key := 0;
    btnRunToCursorClick(nil);
  end
  else if (Key = VK_F2) and (ssCtrl in Shift) then
  begin
    Key := 0;
    btnRestartClick(nil);
  end;
end;

end.
