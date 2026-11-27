unit Presentation.ConnectionComboSearch;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  Controls,
  StdCtrls,
  LCLType,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile;

type
  TConnComboProfileSelectedEvent = procedure(Sender: TObject; const AProfile: TConnectionProfile) of object;
  TConnComboBusyCheck = function: Boolean of object;

  { Controlador reutilizável para tornar qualquer TComboBox de conexões pesquisável ao digitar }
  TConnectionComboSearchController = class(TComponent)
  private
    FCombo: TComboBox;
    FPopupParent: TWinControl;
    FLbSuggest: TListBox;
    FIsUpdating: Boolean;
    FActiveProfileId: string;
    FOnProfileSelected: TConnComboProfileSelectedEvent;
    FOnRestoreSelection: TNotifyEvent;
    FOnBeforeShowSuggest: TNotifyEvent;
    FOnIsBusy: TConnComboBusyCheck;
    procedure EnsureSuggestBox;
    function CheckBusy: Boolean;
    procedure UpdateSuggestList(const AFilter: string);
    procedure ApplyProfile(const AProfile: TConnectionProfile);
    procedure HandleComboChange(Sender: TObject);
    procedure HandleComboDropDown(Sender: TObject);
    procedure HandleComboKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleComboExit(Sender: TObject);
    procedure HandleSuggestMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HandleSuggestKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleSuggestExit(Sender: TObject);
  public
    constructor CreateForCombo(
      AOwner: TComponent;
      const ACombo: TComboBox;
      const APopupParent: TWinControl
    );
    procedure BeginUpdate;
    procedure EndUpdate;
    procedure HideSuggest(const ARestoreText: Boolean = False);
    procedure RestoreActiveSelection;
    function SelectProfileById(const AProfileId: string): Boolean;
    property IsUpdating: Boolean read FIsUpdating;
    property ActiveProfileId: string read FActiveProfileId write FActiveProfileId;
    property OnProfileSelected: TConnComboProfileSelectedEvent read FOnProfileSelected write FOnProfileSelected;
    property OnRestoreSelection: TNotifyEvent read FOnRestoreSelection write FOnRestoreSelection;
    property OnBeforeShowSuggest: TNotifyEvent read FOnBeforeShowSuggest write FOnBeforeShowSuggest;
    property OnIsBusy: TConnComboBusyCheck read FOnIsBusy write FOnIsBusy;
  end;

implementation

{ TConnectionComboSearchController }

constructor TConnectionComboSearchController.CreateForCombo(
  AOwner: TComponent;
  const ACombo: TComboBox;
  const APopupParent: TWinControl
);
begin
  inherited Create(AOwner);
  FCombo := ACombo;
  FPopupParent := APopupParent;
  FIsUpdating := False;
  FActiveProfileId := '';

  if FCombo <> nil then
  begin
    FCombo.Style := csDropDown;
    FCombo.AutoComplete := False;
    FCombo.AutoSelect := True;
    FCombo.DropDownCount := 16;
    FCombo.TextHint := 'Pesquisar conexão...';
    FCombo.OnChange := @HandleComboChange;
    FCombo.OnDropDown := @HandleComboDropDown;
    FCombo.OnKeyDown := @HandleComboKeyDown;
    FCombo.OnExit := @HandleComboExit;
  end;
end;

procedure TConnectionComboSearchController.BeginUpdate;
begin
  FIsUpdating := True;
end;

procedure TConnectionComboSearchController.EndUpdate;
begin
  FIsUpdating := False;
end;

function TConnectionComboSearchController.CheckBusy: Boolean;
begin
  Result := Assigned(FOnIsBusy) and FOnIsBusy();
end;

procedure TConnectionComboSearchController.EnsureSuggestBox;
begin
  if (FLbSuggest <> nil) or (FPopupParent = nil) or (FCombo = nil) then
    Exit;

  FLbSuggest := TListBox.Create(Self);
  FLbSuggest.Parent := FPopupParent;
  FLbSuggest.Visible := False;
  FLbSuggest.TabStop := False;
  FLbSuggest.Font.Assign(FCombo.Font);
  FLbSuggest.OnMouseDown := @HandleSuggestMouseDown;
  FLbSuggest.OnKeyDown := @HandleSuggestKeyDown;
  FLbSuggest.OnExit := @HandleSuggestExit;
end;

procedure TConnectionComboSearchController.RestoreActiveSelection;
var
  I: Integer;
begin
  if Assigned(FOnRestoreSelection) then
  begin
    FOnRestoreSelection(Self);
    Exit;
  end;

  if FCombo = nil then
    Exit;

  FIsUpdating := True;
  try
    FCombo.ItemIndex := -1;
    for I := 0 to FCombo.Items.Count - 1 do
    begin
      if (FCombo.Items.Objects[I] <> nil) and
         SameText(TConnectionProfile(FCombo.Items.Objects[I]).Id, FActiveProfileId) then
      begin
        FCombo.ItemIndex := I;
        FCombo.Text := FCombo.Items[I];
        Break;
      end;
    end;
    if FCombo.ItemIndex < 0 then
      FCombo.Text := '';
  finally
    FIsUpdating := False;
  end;
end;

function TConnectionComboSearchController.SelectProfileById(const AProfileId: string): Boolean;
begin
  FActiveProfileId := AProfileId;
  RestoreActiveSelection;
  Result := (FCombo <> nil) and (FCombo.ItemIndex >= 0);
end;

procedure TConnectionComboSearchController.HideSuggest(const ARestoreText: Boolean);
begin
  if FLbSuggest <> nil then
    FLbSuggest.Visible := False;
  if ARestoreText then
    RestoreActiveSelection;
end;

procedure TConnectionComboSearchController.UpdateSuggestList(const AFilter: string);
var
  Q, Haystack, CurText: string;
  I, ItemH, MaxH, CurSel: Integer;
  P: TConnectionProfile;
  ScreenPt, ClientPt: TPoint;
begin
  if (FCombo = nil) or (FPopupParent = nil) then
    Exit;

  EnsureSuggestBox;
  if Assigned(FOnBeforeShowSuggest) then
    FOnBeforeShowSuggest(Self);

  if FCombo.DroppedDown then
  begin
    CurText := FCombo.Text;
    CurSel := FCombo.SelStart;
    FIsUpdating := True;
    try
      FCombo.DroppedDown := False;
      if FCombo.Text <> CurText then
        FCombo.Text := CurText;
      FCombo.SelStart := CurSel;
      FCombo.SelLength := 0;
    finally
      FIsUpdating := False;
    end;
  end;

  Q := LowerCase(Trim(AFilter));
  if Q = '' then
  begin
    if FLbSuggest <> nil then
      FLbSuggest.Visible := False;
    Exit;
  end;

  FLbSuggest.Items.BeginUpdate;
  try
    FLbSuggest.Items.Clear;
    for I := 0 to FCombo.Items.Count - 1 do
    begin
      P := TConnectionProfile(FCombo.Items.Objects[I]);
      if P = nil then
        Continue;
      Haystack := LowerCase(
        P.Name + ' ' + P.Folder + ' ' + P.Database + ' ' + P.Host + ' ' + DatabaseTypeToStr(P.DatabaseType)
      );
      if Pos(Q, Haystack) > 0 then
        FLbSuggest.Items.AddObject(FCombo.Items[I], P);
    end;
  finally
    FLbSuggest.Items.EndUpdate;
  end;

  if FLbSuggest.Items.Count = 0 then
  begin
    FLbSuggest.Visible := False;
    Exit;
  end;

  ScreenPt := FCombo.ClientToScreen(Point(0, FCombo.Height));
  ClientPt := FPopupParent.ScreenToClient(ScreenPt);
  FLbSuggest.Left := ClientPt.X;
  FLbSuggest.Top := ClientPt.Y + 1;
  FLbSuggest.Width := Max(FCombo.Width, 340);
  if FLbSuggest.Left + FLbSuggest.Width > FPopupParent.ClientWidth - 4 then
    FLbSuggest.Width := Max(FCombo.Width, FPopupParent.ClientWidth - FLbSuggest.Left - 4);
  ItemH := 18;
  MaxH := Min(12, FLbSuggest.Items.Count) * ItemH + 6;
  FLbSuggest.Height := MaxH;
  FLbSuggest.ItemIndex := 0;
  FLbSuggest.Visible := True;
  FLbSuggest.BringToFront;
end;

procedure TConnectionComboSearchController.ApplyProfile(const AProfile: TConnectionProfile);
var
  I: Integer;
begin
  if CheckBusy or (FCombo = nil) or (AProfile = nil) then
    Exit;

  FActiveProfileId := AProfile.Id;
  FIsUpdating := True;
  try
    for I := 0 to FCombo.Items.Count - 1 do
    begin
      if (FCombo.Items.Objects[I] <> nil) and
         SameText(TConnectionProfile(FCombo.Items.Objects[I]).Id, AProfile.Id) then
      begin
        FCombo.ItemIndex := I;
        FCombo.Text := FCombo.Items[I];
        Break;
      end;
    end;
  finally
    FIsUpdating := False;
  end;

  if FLbSuggest <> nil then
    FLbSuggest.Visible := False;

  if Assigned(FOnProfileSelected) then
    FOnProfileSelected(Self, AProfile);
end;

procedure TConnectionComboSearchController.HandleComboChange(Sender: TObject);
var
  Idx: Integer;
  Profile: TConnectionProfile;
begin
  if FIsUpdating or CheckBusy or (FCombo = nil) then
    Exit;

  Idx := FCombo.ItemIndex;
  if (Idx >= 0) and (Idx < FCombo.Items.Count) and
     SameText(FCombo.Text, FCombo.Items[Idx]) then
  begin
    Profile := TConnectionProfile(FCombo.Items.Objects[Idx]);
    if Profile <> nil then
      ApplyProfile(Profile);
    Exit;
  end;

  UpdateSuggestList(FCombo.Text);
end;

procedure TConnectionComboSearchController.HandleComboDropDown(Sender: TObject);
begin
  if FLbSuggest <> nil then
    FLbSuggest.Visible := False;
  if Assigned(FOnBeforeShowSuggest) then
    FOnBeforeShowSuggest(Self);
end;

procedure TConnectionComboSearchController.HandleComboKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  P: TConnectionProfile;
  NewIdx: Integer;
begin
  if (FLbSuggest <> nil) and FLbSuggest.Visible and (FLbSuggest.Items.Count > 0) then
  begin
    if Key = VK_DOWN then
    begin
      Key := 0;
      NewIdx := FLbSuggest.ItemIndex + 1;
      if NewIdx >= FLbSuggest.Items.Count then
        NewIdx := 0;
      FLbSuggest.ItemIndex := NewIdx;
      Exit;
    end
    else if Key = VK_UP then
    begin
      Key := 0;
      NewIdx := FLbSuggest.ItemIndex - 1;
      if NewIdx < 0 then
        NewIdx := FLbSuggest.Items.Count - 1;
      FLbSuggest.ItemIndex := NewIdx;
      Exit;
    end
    else if Key = VK_RETURN then
    begin
      Key := 0;
      if FLbSuggest.ItemIndex < 0 then
        FLbSuggest.ItemIndex := 0;
      P := TConnectionProfile(FLbSuggest.Items.Objects[FLbSuggest.ItemIndex]);
      if P <> nil then
        ApplyProfile(P);
      Exit;
    end
    else if Key = VK_ESCAPE then
    begin
      Key := 0;
      HideSuggest(True);
      Exit;
    end;
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    RestoreActiveSelection;
  end;
end;

procedure TConnectionComboSearchController.HandleComboExit(Sender: TObject);
begin
  if (FLbSuggest <> nil) and FLbSuggest.Visible and FLbSuggest.Focused then
    Exit;
  HideSuggest(True);
end;

procedure TConnectionComboSearchController.HandleSuggestMouseDown(
  Sender: TObject;
  Button: TMouseButton;
  Shift: TShiftState;
  X, Y: Integer
);
var
  Idx: Integer;
  P: TConnectionProfile;
begin
  if (FLbSuggest = nil) or (Button <> mbLeft) then
    Exit;
  Idx := FLbSuggest.ItemAtPos(Point(X, Y), True);
  if (Idx >= 0) and (Idx < FLbSuggest.Items.Count) then
  begin
    FLbSuggest.ItemIndex := Idx;
    P := TConnectionProfile(FLbSuggest.Items.Objects[Idx]);
    if P <> nil then
      ApplyProfile(P);
  end;
end;

procedure TConnectionComboSearchController.HandleSuggestKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  P: TConnectionProfile;
begin
  if FLbSuggest = nil then
    Exit;
  if Key = VK_RETURN then
  begin
    Key := 0;
    if (FLbSuggest.ItemIndex >= 0) and (FLbSuggest.ItemIndex < FLbSuggest.Items.Count) then
    begin
      P := TConnectionProfile(FLbSuggest.Items.Objects[FLbSuggest.ItemIndex]);
      if P <> nil then
        ApplyProfile(P);
    end;
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    HideSuggest(True);
    if (FCombo <> nil) and FCombo.CanFocus then
      FCombo.SetFocus;
  end;
end;

procedure TConnectionComboSearchController.HandleSuggestExit(Sender: TObject);
begin
  if (FCombo <> nil) and FCombo.Focused then
    Exit;
  HideSuggest(True);
end;

end.
