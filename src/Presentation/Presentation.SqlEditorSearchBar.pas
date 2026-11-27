unit Presentation.SqlEditorSearchBar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, StrUtils, Forms, Controls, Graphics,
  StdCtrls, ExtCtrls, Buttons, LCLType, SynEdit, SynEditTypes, SynEditSearch;

type
  TSqlEditorSearchBar = class(TPanel)
  private
    FEditor: TSynEdit;
    FBtnToggleReplace: TSpeedButton;
    FEdtFind: TEdit;
    FLblCount: TLabel;
    FBtnPrev: TSpeedButton;
    FBtnNext: TSpeedButton;
    FBtnCase: TSpeedButton;
    FBtnWholeWord: TSpeedButton;
    FBtnClose: TSpeedButton;
    FEdtReplace: TEdit;
    FBtnReplaceOne: TSpeedButton;
    FBtnReplaceAll: TSpeedButton;
    FReplaceMode: Boolean;
    FUpdatingText: Boolean;
    FSearchAnchor: TPoint;
    FHasSavedHideSelection: Boolean;
    FSavedHideSelection: Boolean;
    procedure BuildControls;
    procedure EditorChangeBounds(Sender: TObject);
    procedure EdtFindChange(Sender: TObject);
    procedure SearchEditKeyPress(Sender: TObject; var Key: Char);
    procedure BtnToggleReplaceClick(Sender: TObject);
    procedure BtnPrevClick(Sender: TObject);
    procedure BtnNextClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure OptionButtonClick(Sender: TObject);
    procedure BtnReplaceOneClick(Sender: TObject);
    procedure BtnReplaceAllClick(Sender: TObject);
    procedure EnsureEditorHighlightStyle;
    procedure RestoreEditorState;
    function BuildSearchOptions(const ABackwards: Boolean): TSynSearchOptions;
    procedure ApplyHighlightAndCount;
    function DoFind(const ABackwards, AIncremental: Boolean): Boolean;
    procedure DoReplaceCurrent;
    procedure DoReplaceAll;
    function GetSearchText: string;
  protected
    procedure Paint; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor CreateForEditor(const AEditor: TSynEdit);
    destructor Destroy; override;
    procedure UpdatePositionAndLayout;
    procedure OpenForEditor(const AShowReplace: Boolean = False);
    procedure CloseBar(const ARefocusEditor: Boolean = True);
    procedure FindNext;
    procedure FindPrev;
    procedure ReplaceCurrent;
    procedure FocusFindEdit;
    property SearchText: string read GetSearchText;
    property FindEdit: TEdit read FEdtFind;
    property ReplaceEdit: TEdit read FEdtReplace;
  end;

procedure InstallGlobalSqlEditorSearchHook;
procedure UninstallGlobalSqlEditorSearchHook;
procedure OpenSearchForSqlEditor(const AEditor: TSynEdit; const AShowReplace: Boolean = False);

implementation

const
  MAX_MATCH_COUNT = 2000;

type
  TSqlEditorSearchManager = class
  public
    procedure HandleAppKeyDownBefore(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

var
  GSearchManager: TSqlEditorSearchManager = nil;
  GLastSearchText: string = '';

function SamePoint(const A, B: TPoint): Boolean; inline;
begin
  Result := (A.X = B.X) and (A.Y = B.Y);
end;

function FindBarForEditor(const AEditor: TSynEdit): TSqlEditorSearchBar;
var
  I: Integer;
begin
  Result := nil;
  if AEditor = nil then
    Exit;
  for I := 0 to AEditor.ComponentCount - 1 do
  begin
    if AEditor.Components[I] is TSqlEditorSearchBar then
      Exit(TSqlEditorSearchBar(AEditor.Components[I]));
  end;
end;

function EnsureBarForEditor(const AEditor: TSynEdit): TSqlEditorSearchBar;
begin
  Result := FindBarForEditor(AEditor);
  if Result = nil then
    Result := TSqlEditorSearchBar.CreateForEditor(AEditor);
end;

function FindOwnerBar(const AControl: TObject): TSqlEditorSearchBar;
var
  C: TControl;
begin
  Result := nil;
  if not (AControl is TControl) then
    Exit;
  C := TControl(AControl);
  while C <> nil do
  begin
    if C is TSqlEditorSearchBar then
      Exit(TSqlEditorSearchBar(C));
    C := C.Parent;
  end;
end;

procedure OpenSearchForSqlEditor(const AEditor: TSynEdit; const AShowReplace: Boolean);
var
  Bar: TSqlEditorSearchBar;
begin
  if (AEditor = nil) or (AEditor.Parent = nil) then
    Exit;
  Bar := EnsureBarForEditor(AEditor);
  Bar.OpenForEditor(AShowReplace);
end;

procedure InstallGlobalSqlEditorSearchHook;
begin
  if GSearchManager <> nil then
    Exit;
  GSearchManager := TSqlEditorSearchManager.Create;
  Forms.Application.AddOnKeyDownBeforeHandler(@GSearchManager.HandleAppKeyDownBefore, True);
end;

procedure UninstallGlobalSqlEditorSearchHook;
begin
  if GSearchManager = nil then
    Exit;
  if Forms.Application <> nil then
    Forms.Application.RemoveOnKeyDownBeforeHandler(@GSearchManager.HandleAppKeyDownBefore);
  FreeAndNil(GSearchManager);
end;

{ TSqlEditorSearchManager }

procedure TSqlEditorSearchManager.HandleAppKeyDownBefore(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  IsOnlyCtrl, NoCtrlAlt: Boolean;
  Ed: TSynEdit;
  Bar: TSqlEditorSearchBar;
begin
  IsOnlyCtrl := (ssCtrl in Shift) and (not (ssAlt in Shift)) and (not (ssShift in Shift));
  NoCtrlAlt := (not (ssCtrl in Shift)) and (not (ssAlt in Shift));

  if Sender is TSynEdit then
  begin
    Ed := TSynEdit(Sender);
    if Ed.Keystrokes.Count = 0 then
      Ed.Keystrokes.ResetDefaults;

    if ((Key = VK_C) or (Key = Ord('C'))) and IsOnlyCtrl then
    begin
      Key := 0;
      Ed.CopyToClipboard;
    end
    else if ((Key = VK_V) or (Key = Ord('V'))) and IsOnlyCtrl then
    begin
      Key := 0;
      if not Ed.ReadOnly then
        Ed.PasteFromClipboard;
    end
    else if ((Key = VK_X) or (Key = Ord('X'))) and IsOnlyCtrl then
    begin
      Key := 0;
      if not Ed.ReadOnly then
        Ed.CutToClipboard;
    end
    else if ((Key = VK_A) or (Key = Ord('A'))) and IsOnlyCtrl then
    begin
      Key := 0;
      Ed.SelectAll;
    end
    else if ((Key = VK_F) or (Key = Ord('F'))) and IsOnlyCtrl then
    begin
      Key := 0;
      OpenSearchForSqlEditor(Ed, False);
    end
    else if ((Key = VK_H) or (Key = Ord('H'))) and IsOnlyCtrl then
    begin
      Key := 0;
      OpenSearchForSqlEditor(Ed, not Ed.ReadOnly);
    end
    else if (Key = VK_F3) and NoCtrlAlt then
    begin
      Bar := FindBarForEditor(Ed);
      if (Bar <> nil) and (Bar.SearchText <> '') then
      begin
        Key := 0;
        if ssShift in Shift then
          Bar.FindPrev
        else
          Bar.FindNext;
      end
      else if GLastSearchText <> '' then
      begin
        Key := 0;
        Bar := EnsureBarForEditor(Ed);
        Bar.OpenForEditor(False);
      end;
    end
    else if (Key = VK_ESCAPE) and NoCtrlAlt and (not (ssShift in Shift)) then
    begin
      Bar := FindBarForEditor(Ed);
      if (Bar <> nil) and Bar.Visible then
      begin
        Key := 0;
        Bar.CloseBar(True);
      end;
    end;
    Exit;
  end;

  Bar := FindOwnerBar(Sender);
  if Bar = nil then
    Exit;

  if (Key = VK_ESCAPE) and NoCtrlAlt then
  begin
    Key := 0;
    Bar.CloseBar(True);
  end
  else if (Key = VK_RETURN) and NoCtrlAlt then
  begin
    if Sender = Bar.FindEdit then
    begin
      Key := 0;
      if ssShift in Shift then
        Bar.FindPrev
      else
        Bar.FindNext;
    end
    else if Sender = Bar.ReplaceEdit then
    begin
      Key := 0;
      Bar.ReplaceCurrent;
    end;
  end
  else if (Key = VK_F3) and NoCtrlAlt then
  begin
    Key := 0;
    if ssShift in Shift then
      Bar.FindPrev
    else
      Bar.FindNext;
  end
  else if ((Key = VK_F) or (Key = Ord('F'))) and IsOnlyCtrl then
  begin
    Key := 0;
    Bar.FocusFindEdit;
  end
  else if ((Key = VK_H) or (Key = Ord('H'))) and IsOnlyCtrl then
  begin
    Key := 0;
    Bar.OpenForEditor(True);
  end
  else if IsOnlyCtrl and (Sender is TCustomEdit) then
  begin
    if (Key = VK_C) or (Key = Ord('C')) then
    begin
      Key := 0;
      TCustomEdit(Sender).CopyToClipboard;
    end
    else if (Key = VK_V) or (Key = Ord('V')) then
    begin
      Key := 0;
      TCustomEdit(Sender).PasteFromClipboard;
    end
    else if (Key = VK_X) or (Key = Ord('X')) then
    begin
      Key := 0;
      TCustomEdit(Sender).CutToClipboard;
    end
    else if (Key = VK_A) or (Key = Ord('A')) then
    begin
      Key := 0;
      TCustomEdit(Sender).SelectAll;
    end;
  end;
end;

{ TSqlEditorSearchBar }

constructor TSqlEditorSearchBar.CreateForEditor(const AEditor: TSynEdit);
begin
  inherited Create(AEditor);
  FEditor := AEditor;
  if FEditor <> nil then
    FEditor.FreeNotification(Self);
  Align := alNone;
  BevelOuter := bvNone;
  Color := $00F7F9FC;
  DoubleBuffered := True;
  Visible := False;
  ShowHint := True;
  if (FEditor <> nil) and (FEditor.Parent <> nil) then
    Parent := FEditor.Parent;
  BuildControls;
  if FEditor <> nil then
    FEditor.AddHandlerOnChangeBounds(@EditorChangeBounds);
end;

destructor TSqlEditorSearchBar.Destroy;
begin
  if FEditor <> nil then
  begin
    FEditor.RemoveHandlerOnChangeBounds(@EditorChangeBounds);
    FEditor.SetHighlightSearch('', []);
    RestoreEditorState;
  end;
  inherited Destroy;
end;

procedure TSqlEditorSearchBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FEditor) then
    FEditor := nil;
end;

procedure TSqlEditorSearchBar.Paint;
begin
  inherited Paint;
  Canvas.Pen.Color := $00C4CDD8;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(0, 0, Width, Height);
end;

procedure TSqlEditorSearchBar.BuildControls;
begin
  FBtnToggleReplace := TSpeedButton.Create(Self);
  FBtnToggleReplace.Parent := Self;
  FBtnToggleReplace.Top := 5;
  FBtnToggleReplace.Width := 20;
  FBtnToggleReplace.Height := 24;
  FBtnToggleReplace.Flat := True;
  FBtnToggleReplace.Caption := '▸';
  FBtnToggleReplace.Hint := 'Substituir (Ctrl+H)';
  FBtnToggleReplace.ShowHint := True;
  FBtnToggleReplace.OnClick := @BtnToggleReplaceClick;

  FEdtFind := TEdit.Create(Self);
  FEdtFind.Parent := Self;
  FEdtFind.Top := 5;
  FEdtFind.Height := 24;
  FEdtFind.TextHint := 'Localizar no SQL...';
  FEdtFind.OnChange := @EdtFindChange;
  FEdtFind.OnKeyPress := @SearchEditKeyPress;

  FLblCount := TLabel.Create(Self);
  FLblCount.Parent := Self;
  FLblCount.Top := 5;
  FLblCount.Width := 56;
  FLblCount.Height := 24;
  FLblCount.AutoSize := False;
  FLblCount.Alignment := taCenter;
  FLblCount.Layout := tlCenter;
  FLblCount.Font.Size := 8;
  FLblCount.Font.Color := $00555555;
  FLblCount.Caption := '';

  FBtnPrev := TSpeedButton.Create(Self);
  FBtnPrev.Parent := Self;
  FBtnPrev.Top := 5;
  FBtnPrev.Width := 24;
  FBtnPrev.Height := 24;
  FBtnPrev.Flat := True;
  FBtnPrev.Caption := '▲';
  FBtnPrev.Hint := 'Anterior (Shift+F3 / Shift+Enter)';
  FBtnPrev.ShowHint := True;
  FBtnPrev.OnClick := @BtnPrevClick;

  FBtnNext := TSpeedButton.Create(Self);
  FBtnNext.Parent := Self;
  FBtnNext.Top := 5;
  FBtnNext.Width := 24;
  FBtnNext.Height := 24;
  FBtnNext.Flat := True;
  FBtnNext.Caption := '▼';
  FBtnNext.Hint := 'Próximo (F3 / Enter)';
  FBtnNext.ShowHint := True;
  FBtnNext.OnClick := @BtnNextClick;

  FBtnCase := TSpeedButton.Create(Self);
  FBtnCase.Parent := Self;
  FBtnCase.Top := 5;
  FBtnCase.Width := 26;
  FBtnCase.Height := 24;
  FBtnCase.Flat := True;
  FBtnCase.GroupIndex := 1;
  FBtnCase.AllowAllUp := True;
  FBtnCase.Caption := 'Aa';
  FBtnCase.Hint := 'Diferenciar maiúsculas/minúsculas';
  FBtnCase.ShowHint := True;
  FBtnCase.OnClick := @OptionButtonClick;

  FBtnWholeWord := TSpeedButton.Create(Self);
  FBtnWholeWord.Parent := Self;
  FBtnWholeWord.Top := 5;
  FBtnWholeWord.Width := 28;
  FBtnWholeWord.Height := 24;
  FBtnWholeWord.Flat := True;
  FBtnWholeWord.GroupIndex := 2;
  FBtnWholeWord.AllowAllUp := True;
  FBtnWholeWord.Caption := 'Pal';
  FBtnWholeWord.Hint := 'Palavra inteira';
  FBtnWholeWord.ShowHint := True;
  FBtnWholeWord.OnClick := @OptionButtonClick;

  FBtnClose := TSpeedButton.Create(Self);
  FBtnClose.Parent := Self;
  FBtnClose.Top := 5;
  FBtnClose.Width := 22;
  FBtnClose.Height := 24;
  FBtnClose.Flat := True;
  FBtnClose.Caption := '×';
  FBtnClose.Hint := 'Fechar (Esc)';
  FBtnClose.ShowHint := True;
  FBtnClose.OnClick := @BtnCloseClick;

  FEdtReplace := TEdit.Create(Self);
  FEdtReplace.Parent := Self;
  FEdtReplace.Top := 34;
  FEdtReplace.Height := 24;
  FEdtReplace.TextHint := 'Substituir por...';
  FEdtReplace.OnKeyPress := @SearchEditKeyPress;

  FBtnReplaceOne := TSpeedButton.Create(Self);
  FBtnReplaceOne.Parent := Self;
  FBtnReplaceOne.Top := 34;
  FBtnReplaceOne.Width := 54;
  FBtnReplaceOne.Height := 24;
  FBtnReplaceOne.Flat := True;
  FBtnReplaceOne.Caption := 'Subst.';
  FBtnReplaceOne.Hint := 'Substituir ocorrência atual (Enter)';
  FBtnReplaceOne.ShowHint := True;
  FBtnReplaceOne.OnClick := @BtnReplaceOneClick;

  FBtnReplaceAll := TSpeedButton.Create(Self);
  FBtnReplaceAll.Parent := Self;
  FBtnReplaceAll.Top := 34;
  FBtnReplaceAll.Width := 54;
  FBtnReplaceAll.Height := 24;
  FBtnReplaceAll.Flat := True;
  FBtnReplaceAll.Caption := 'Tudo';
  FBtnReplaceAll.Hint := 'Substituir todas as ocorrências';
  FBtnReplaceAll.ShowHint := True;
  FBtnReplaceAll.OnClick := @BtnReplaceAllClick;
end;

procedure TSqlEditorSearchBar.EditorChangeBounds(Sender: TObject);
begin
  if Visible then
    UpdatePositionAndLayout;
end;

procedure TSqlEditorSearchBar.UpdatePositionAndLayout;
var
  MaxBarW, AvailW, BarW, RightX, LeftX: Integer;
  CanReplace, ShowRep: Boolean;
begin
  if (FEditor = nil) or (FEditor.Parent = nil) then
    Exit;

  MaxBarW := 440;
  AvailW := FEditor.Width - 24;
  BarW := Min(MaxBarW, Max(250, AvailW));
  if FEditor.Width < 260 then
    BarW := Max(180, FEditor.Width - 8);

  CanReplace := not FEditor.ReadOnly;
  ShowRep := FReplaceMode and CanReplace;

  Width := BarW;
  Height := IfThen(ShowRep, 64, 34);
  Left := Max(FEditor.Left + 4, FEditor.Left + FEditor.Width - BarW - 20);
  Top := FEditor.Top + 4;

  RightX := Width - 5;

  FBtnClose.Left := RightX - FBtnClose.Width;
  RightX := FBtnClose.Left - 2;

  FBtnWholeWord.Left := RightX - FBtnWholeWord.Width;
  RightX := FBtnWholeWord.Left - 2;

  FBtnCase.Left := RightX - FBtnCase.Width;
  RightX := FBtnCase.Left - 2;

  FBtnNext.Left := RightX - FBtnNext.Width;
  RightX := FBtnNext.Left - 2;

  FBtnPrev.Left := RightX - FBtnPrev.Width;
  RightX := FBtnPrev.Left - 2;

  FLblCount.Left := RightX - FLblCount.Width;
  RightX := FLblCount.Left - 4;

  FBtnToggleReplace.Visible := CanReplace;
  if CanReplace then
  begin
    FBtnToggleReplace.Left := 4;
    FBtnToggleReplace.Caption := IfThen(ShowRep, '▾', '▸');
    LeftX := FBtnToggleReplace.Left + FBtnToggleReplace.Width + 4;
  end
  else
    LeftX := 6;

  FEdtFind.Left := LeftX;
  FEdtFind.Width := Max(60, RightX - LeftX);

  FEdtReplace.Visible := ShowRep;
  FBtnReplaceOne.Visible := ShowRep;
  FBtnReplaceAll.Visible := ShowRep;
  if ShowRep then
  begin
    FBtnReplaceAll.Left := Width - 5 - FBtnReplaceAll.Width;
    FBtnReplaceOne.Left := FBtnReplaceAll.Left - 4 - FBtnReplaceOne.Width;
    FEdtReplace.Left := LeftX;
    FEdtReplace.Width := Max(60, FBtnReplaceOne.Left - 4 - LeftX);
  end;

  BringToFront;
end;

procedure TSqlEditorSearchBar.EnsureEditorHighlightStyle;
begin
  if FEditor = nil then
    Exit;
  if not FHasSavedHideSelection then
  begin
    FSavedHideSelection := FEditor.HideSelection;
    FHasSavedHideSelection := True;
  end;
  FEditor.HideSelection := False;

  if (FEditor.HighlightAllColor.Background = clNone) and
     (FEditor.HighlightAllColor.Foreground = clNone) and
     (FEditor.HighlightAllColor.FrameColor = clNone) then
  begin
    FEditor.HighlightAllColor.Background := RGBToColor(255, 243, 168);
    FEditor.HighlightAllColor.FrameColor := RGBToColor(230, 175, 46);
  end;
end;

procedure TSqlEditorSearchBar.RestoreEditorState;
begin
  if (FEditor <> nil) and FHasSavedHideSelection then
  begin
    FEditor.HideSelection := FSavedHideSelection;
    FHasSavedHideSelection := False;
  end;
end;

function TSqlEditorSearchBar.BuildSearchOptions(const ABackwards: Boolean): TSynSearchOptions;
begin
  Result := [];
  if FBtnCase.Down then
    Include(Result, ssoMatchCase);
  if FBtnWholeWord.Down then
    Include(Result, ssoWholeWord);
  if ABackwards then
    Include(Result, ssoBackwards);
end;

procedure TSqlEditorSearchBar.ApplyHighlightAndCount;
var
  Term: string;
  Opts: TSynSearchOptions;
  Search: TSynEditSearch;
  CurStart, EndPt, FS, FE: TPoint;
  Total, CurrentIdx: Integer;
begin
  if FEditor = nil then
    Exit;

  Term := FEdtFind.Text;
  if Term = '' then
  begin
    FEditor.SetHighlightSearch('', []);
    FLblCount.Caption := '';
    FLblCount.Font.Color := $00555555;
    FEdtFind.Color := clWindow;
    Exit;
  end;

  Opts := BuildSearchOptions(False);
  FEditor.SetHighlightSearch(Term, Opts);

  if FEditor.Lines.Count = 0 then
  begin
    FLblCount.Caption := '0/0';
    FLblCount.Font.Color := $002828CC;
    FEdtFind.Color := $00EBEBFF;
    Exit;
  end;

  Total := 0;
  CurrentIdx := 0;
  Search := TSynEditSearch.Create;
  try
    Search.Sensitive := ssoMatchCase in Opts;
    Search.Whole := ssoWholeWord in Opts;
    Search.Pattern := Term;
    Search.Backwards := False;

    CurStart := Point(1, 1);
    EndPt := Point(Length(FEditor.Lines[FEditor.Lines.Count - 1]) + 1, FEditor.Lines.Count);
    while Search.FindNextOne(FEditor.Lines, CurStart, EndPt, FS, FE, True) do
    begin
      Inc(Total);
      if FEditor.SelAvail and SamePoint(FS, FEditor.BlockBegin) and SamePoint(FE, FEditor.BlockEnd) then
        CurrentIdx := Total;
      if Total >= MAX_MATCH_COUNT then
        Break;
      if SamePoint(FS, FE) then
        Break;
      CurStart := FE;
    end;
  finally
    Search.Free;
  end;

  if Total = 0 then
  begin
    FLblCount.Caption := '0/0';
    FLblCount.Font.Color := $002828CC;
    FEdtFind.Color := $00EBEBFF;
  end
  else if Total >= MAX_MATCH_COUNT then
  begin
    FLblCount.Caption := IfThen(CurrentIdx > 0, IntToStr(CurrentIdx) + '/2000+', '2000+');
    FLblCount.Font.Color := $00555555;
    FEdtFind.Color := clWindow;
  end
  else
  begin
    FLblCount.Caption := IfThen(CurrentIdx > 0, Format('%d/%d', [CurrentIdx, Total]), Format('0/%d', [Total]));
    FLblCount.Font.Color := $00555555;
    FEdtFind.Color := clWindow;
  end;
end;

function TSqlEditorSearchBar.DoFind(const ABackwards, AIncremental: Boolean): Boolean;
var
  Term: string;
  Opts: TSynSearchOptions;
  StartPt, WrapPt: TPoint;
begin
  Result := False;
  if (FEditor = nil) or (FEditor.Lines.Count = 0) then
  begin
    ApplyHighlightAndCount;
    Exit;
  end;

  Term := FEdtFind.Text;
  if Term = '' then
  begin
    ApplyHighlightAndCount;
    Exit;
  end;

  GLastSearchText := Term;

  if AIncremental then
  begin
    StartPt := FSearchAnchor;
    if StartPt.Y < 1 then
      StartPt.Y := 1
    else if StartPt.Y > FEditor.Lines.Count then
      StartPt.Y := FEditor.Lines.Count;
    if StartPt.X < 1 then
      StartPt.X := 1;
  end
  else if ABackwards then
  begin
    if FEditor.SelAvail then
      StartPt := FEditor.BlockBegin
    else
      StartPt := FEditor.LogicalCaretXY;
  end
  else
  begin
    if FEditor.SelAvail then
      StartPt := FEditor.BlockEnd
    else
      StartPt := FEditor.LogicalCaretXY;
  end;

  Opts := BuildSearchOptions(ABackwards);
  Result := FEditor.SearchReplaceEx(Term, '', Opts, StartPt) > 0;
  if not Result then
  begin
    if ABackwards then
      WrapPt := Point(Length(FEditor.Lines[FEditor.Lines.Count - 1]) + 1, FEditor.Lines.Count)
    else
      WrapPt := Point(1, 1);
    Result := FEditor.SearchReplaceEx(Term, '', Opts, WrapPt) > 0;
  end;

  ApplyHighlightAndCount;
end;

procedure TSqlEditorSearchBar.DoReplaceCurrent;
var
  Term: string;
  Opts: TSynSearchOptions;
  Search: TSynEditSearch;
  FS, FE: TPoint;
  MatchesSel: Boolean;
begin
  if (FEditor = nil) or FEditor.ReadOnly or (FEdtFind.Text = '') or (FEditor.Lines.Count = 0) then
    Exit;

  Term := FEdtFind.Text;
  Opts := BuildSearchOptions(False);
  MatchesSel := False;
  if FEditor.SelAvail then
  begin
    Search := TSynEditSearch.Create;
    try
      Search.Sensitive := ssoMatchCase in Opts;
      Search.Whole := ssoWholeWord in Opts;
      Search.Pattern := Term;
      Search.Backwards := False;
      if Search.FindNextOne(FEditor.Lines, FEditor.BlockBegin, FEditor.BlockEnd, FS, FE, True) then
        MatchesSel := SamePoint(FS, FEditor.BlockBegin) and SamePoint(FE, FEditor.BlockEnd);
    finally
      Search.Free;
    end;
  end;

  if MatchesSel then
    FEditor.SearchReplaceEx(Term, FEdtReplace.Text, Opts + [ssoReplace], FEditor.BlockBegin);

  DoFind(False, False);
end;

procedure TSqlEditorSearchBar.DoReplaceAll;
var
  Term: string;
  Opts: TSynSearchOptions;
  Replaced: Integer;
begin
  if (FEditor = nil) or FEditor.ReadOnly or (FEdtFind.Text = '') or (FEditor.Lines.Count = 0) then
    Exit;

  Term := FEdtFind.Text;
  Opts := BuildSearchOptions(False) + [ssoEntireScope, ssoReplaceAll];
  Replaced := FEditor.SearchReplaceEx(Term, FEdtReplace.Text, Opts, Point(1, 1));
  ApplyHighlightAndCount;
  if Replaced > 0 then
  begin
    FLblCount.Caption := Format('%d subst.', [Replaced]);
    FLblCount.Font.Color := $001B7F3A;
  end;
end;

procedure TSqlEditorSearchBar.OpenForEditor(const AShowReplace: Boolean);
var
  Sel: string;
begin
  if (FEditor = nil) or (FEditor.Parent = nil) then
    Exit;

  if Parent <> FEditor.Parent then
    Parent := FEditor.Parent;

  if FEditor.SelAvail then
    FSearchAnchor := FEditor.BlockBegin
  else
    FSearchAnchor := FEditor.LogicalCaretXY;

  FUpdatingText := True;
  try
    if FEditor.SelAvail then
    begin
      Sel := FEditor.SelText;
      if (Sel <> '') and (Length(Sel) <= 200) and (Pos(#10, Sel) = 0) and (Pos(#13, Sel) = 0) then
        FEdtFind.Text := Sel;
    end
    else if (FEdtFind.Text = '') and (GLastSearchText <> '') then
      FEdtFind.Text := GLastSearchText;
  finally
    FUpdatingText := False;
  end;

  FReplaceMode := AShowReplace and (not FEditor.ReadOnly);
  EnsureEditorHighlightStyle;
  UpdatePositionAndLayout;
  Visible := True;
  BringToFront;
  ApplyHighlightAndCount;

  if FReplaceMode and (FEdtFind.Text <> '') and FEdtReplace.CanFocus then
  begin
    FEdtReplace.SetFocus;
    FEdtReplace.SelectAll;
  end
  else if FEdtFind.CanFocus then
  begin
    FEdtFind.SetFocus;
    FEdtFind.SelectAll;
  end;
end;

procedure TSqlEditorSearchBar.CloseBar(const ARefocusEditor: Boolean);
begin
  Visible := False;
  if FEditor <> nil then
  begin
    FEditor.SetHighlightSearch('', []);
    RestoreEditorState;
    if ARefocusEditor and FEditor.CanFocus then
      FEditor.SetFocus;
  end;
end;

procedure TSqlEditorSearchBar.FindNext;
begin
  DoFind(False, False);
end;

procedure TSqlEditorSearchBar.FindPrev;
begin
  DoFind(True, False);
end;

procedure TSqlEditorSearchBar.ReplaceCurrent;
begin
  DoReplaceCurrent;
end;

procedure TSqlEditorSearchBar.FocusFindEdit;
begin
  if FEdtFind.CanFocus then
  begin
    FEdtFind.SetFocus;
    FEdtFind.SelectAll;
  end;
end;

function TSqlEditorSearchBar.GetSearchText: string;
begin
  Result := FEdtFind.Text;
end;

procedure TSqlEditorSearchBar.EdtFindChange(Sender: TObject);
begin
  if FUpdatingText then
    Exit;
  DoFind(False, True);
end;

procedure TSqlEditorSearchBar.SearchEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key in [#1, #3, #6, #13, #22, #24, #27] then
    Key := #0;
end;

procedure TSqlEditorSearchBar.BtnToggleReplaceClick(Sender: TObject);
begin
  if (FEditor <> nil) and FEditor.ReadOnly then
    Exit;
  FReplaceMode := not FReplaceMode;
  UpdatePositionAndLayout;
end;

procedure TSqlEditorSearchBar.BtnPrevClick(Sender: TObject);
begin
  FindPrev;
end;

procedure TSqlEditorSearchBar.BtnNextClick(Sender: TObject);
begin
  FindNext;
end;

procedure TSqlEditorSearchBar.BtnCloseClick(Sender: TObject);
begin
  CloseBar(True);
end;

procedure TSqlEditorSearchBar.OptionButtonClick(Sender: TObject);
begin
  DoFind(False, True);
end;

procedure TSqlEditorSearchBar.BtnReplaceOneClick(Sender: TObject);
begin
  DoReplaceCurrent;
end;

procedure TSqlEditorSearchBar.BtnReplaceAllClick(Sender: TObject);
begin
  DoReplaceAll;
end;

initialization

finalization
  UninstallGlobalSqlEditorSearchHook;

end.
