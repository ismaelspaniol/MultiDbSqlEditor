unit Presentation.DdlPreviewDialog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Clipbrd, LCLType, fpjson, jsonparser, SynEdit, SynHighlighterSQL,
  Domain.DatabaseTypes, Domain.ConnectionProfile;

function IsDdlPreviewEnabled: Boolean;
procedure SetDdlPreviewEnabled(const AEnabled: Boolean);
function ConfirmAndPreviewDDL(
  const AProfile: TConnectionProfile;
  const AOperationTitle: string;
  const ADdlScript: string;
  out AEditedDdl: string;
  const AAllowEdit: Boolean = False
): Boolean;

implementation

type
  TDdlPreviewDialog = class(TForm)
  private
    FProfile: TConnectionProfile;
    FOperationTitle: string;
    FSynEdit: TSynEdit;
    FSynHl: TSynSQLSyn;
    FChkAlwaysShow: TCheckBox;
    FLblFeedback: TLabel;
    procedure BuildUI(const AAllowEdit: Boolean; const ADdlScript: string);
    procedure BtnCopyClick(Sender: TObject);
    procedure BtnAppendClick(Sender: TObject);
    procedure ChkAlwaysShowClick(Sender: TObject);
    procedure FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

var
  GSettingsLoaded: Boolean = False;
  GDdlPreviewEnabled: Boolean = True;
  GLastChangelogFile: string = '';

function SettingsFilePath: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'ddl_preview_settings.json';
end;

procedure EnsureSettingsLoaded;
var
  SL: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
  Path: string;
begin
  if GSettingsLoaded then
    Exit;
  GSettingsLoaded := True;
  GDdlPreviewEnabled := True;
  GLastChangelogFile := '';

  Path := SettingsFilePath;
  if not FileExists(Path) then
    Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(Path);
      Data := GetJSON(SL.Text);
      try
        if Data is TJSONObject then
        begin
          Obj := TJSONObject(Data);
          GDdlPreviewEnabled := Obj.Get('confirmBeforeDdl', True);
          GLastChangelogFile := Obj.Get('lastChangelogFile', '');
        end;
      finally
        Data.Free;
      end;
    except
      { Ignore corrupt settings file and keep defaults }
    end;
  finally
    SL.Free;
  end;
end;

procedure SaveSettings;
var
  Obj: TJSONObject;
  SL: TStringList;
begin
  EnsureSettingsLoaded;
  Obj := TJSONObject.Create;
  SL := TStringList.Create;
  try
    Obj.Add('confirmBeforeDdl', GDdlPreviewEnabled);
    Obj.Add('lastChangelogFile', GLastChangelogFile);
    SL.Text := Obj.FormatJSON;
    try
      SL.SaveToFile(SettingsFilePath);
    except
    end;
  finally
    SL.Free;
    Obj.Free;
  end;
end;

function IsDdlPreviewEnabled: Boolean;
begin
  EnsureSettingsLoaded;
  Result := GDdlPreviewEnabled;
end;

procedure SetDdlPreviewEnabled(const AEnabled: Boolean);
begin
  EnsureSettingsLoaded;
  GDdlPreviewEnabled := AEnabled;
  SaveSettings;
end;

function BuildCopyableSql(const ASql: string): string;
var
  Trimmed, UpperTail, LastWord: string;
  LastChar: Char;
  I: Integer;
begin
  Trimmed := Trim(ASql);
  if Trimmed = '' then
    Exit('');

  LastChar := Trimmed[Length(Trimmed)];
  if LastChar in [';', '^', '$'] then
    Exit(Trimmed);

  UpperTail := UpperCase(Copy(Trimmed, Max(1, Length(Trimmed) - 16), 17));
  I := Length(UpperTail);
  while (I >= 1) and (UpperTail[I] in ['A'..'Z', '0'..'9', '_']) do
    Dec(I);
  LastWord := Copy(UpperTail, I + 1, MaxInt);
  if LastWord = 'END' then
    Exit(Trimmed);

  Result := Trimmed + ';';
end;

{ TDdlPreviewDialog }

procedure TDdlPreviewDialog.BuildUI(const AAllowEdit: Boolean; const ADdlScript: string);
var
  PnlTop, PnlTopBorder, PnlOpts, PnlBtns: TPanel;
  LblOpTitle, LblHint: TLabel;
  BtnCopy, BtnAppend, BtnCancel, BtnExecute: TButton;
  HeaderText: string;
begin
  Caption := 'Revisar Comando DDL — ' + FOperationTitle;
  Position := poScreenCenter;
  Width := 800;
  Height := 500;
  Constraints.MinWidth := 560;
  Constraints.MinHeight := 340;
  BorderStyle := bsSizeable;
  KeyPreview := True;
  OnKeyDown := @FormKeyDownHandler;

  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 52;
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := $00F4F6F9;

  PnlTopBorder := TPanel.Create(PnlTop);
  PnlTopBorder.Parent := PnlTop;
  PnlTopBorder.Align := alBottom;
  PnlTopBorder.Height := 1;
  PnlTopBorder.BevelOuter := bvNone;
  PnlTopBorder.Color := $00D2D9E2;

  HeaderText := FOperationTitle;
  if FProfile <> nil then
    HeaderText := HeaderText + Format('   [%s — %s]', [FProfile.Name, DatabaseTypeToStr(FProfile.DatabaseType)]);

  LblOpTitle := TLabel.Create(PnlTop);
  LblOpTitle.Parent := PnlTop;
  LblOpTitle.Left := 12;
  LblOpTitle.Top := 8;
  LblOpTitle.Font.Style := [fsBold];
  LblOpTitle.Font.Size := 10;
  LblOpTitle.Caption := HeaderText;

  LblHint := TLabel.Create(PnlTop);
  LblHint.Parent := PnlTop;
  LblHint.Left := 12;
  LblHint.Top := 29;
  LblHint.Font.Size := 8;
  LblHint.Font.Color := $00555555;
  LblHint.Caption := 'Revise ou copie o comando DDL abaixo para manter seu histórico de alterações antes de executar no banco.';

  PnlBtns := TPanel.Create(Self);
  PnlBtns.Parent := Self;
  PnlBtns.Align := alBottom;
  PnlBtns.Height := 44;
  PnlBtns.BevelOuter := bvNone;
  PnlBtns.BorderSpacing.Left := 8;
  PnlBtns.BorderSpacing.Right := 8;
  PnlBtns.BorderSpacing.Bottom := 8;

  BtnCopy := TButton.Create(PnlBtns);
  BtnCopy.Parent := PnlBtns;
  BtnCopy.Align := alLeft;
  BtnCopy.Width := 175;
  BtnCopy.BorderSpacing.Top := 6;
  BtnCopy.BorderSpacing.Bottom := 6;
  BtnCopy.Caption := 'Copiar SQL (Ctrl+Shift+C)';
  BtnCopy.OnClick := @BtnCopyClick;

  BtnAppend := TButton.Create(PnlBtns);
  BtnAppend.Parent := PnlBtns;
  BtnAppend.Align := alLeft;
  BtnAppend.Width := 130;
  BtnAppend.BorderSpacing.Left := 8;
  BtnAppend.BorderSpacing.Top := 6;
  BtnAppend.BorderSpacing.Bottom := 6;
  BtnAppend.Caption := 'Anexar em .sql...';
  BtnAppend.OnClick := @BtnAppendClick;

  BtnExecute := TButton.Create(PnlBtns);
  BtnExecute.Parent := PnlBtns;
  BtnExecute.Align := alRight;
  BtnExecute.Width := 170;
  BtnExecute.BorderSpacing.Left := 8;
  BtnExecute.BorderSpacing.Top := 6;
  BtnExecute.BorderSpacing.Bottom := 6;
  BtnExecute.Caption := 'Executar / Commit (F9)';
  BtnExecute.ModalResult := mrOk;

  BtnCancel := TButton.Create(PnlBtns);
  BtnCancel.Parent := PnlBtns;
  BtnCancel.Align := alRight;
  BtnCancel.Width := 115;
  BtnCancel.BorderSpacing.Top := 6;
  BtnCancel.BorderSpacing.Bottom := 6;
  BtnCancel.Caption := 'Cancelar (Esc)';
  BtnCancel.Cancel := True;
  BtnCancel.ModalResult := mrCancel;

  PnlOpts := TPanel.Create(Self);
  PnlOpts.Parent := Self;
  PnlOpts.Align := alBottom;
  PnlOpts.Height := 26;
  PnlOpts.BevelOuter := bvNone;
  PnlOpts.BorderSpacing.Left := 8;
  PnlOpts.BorderSpacing.Right := 8;

  FChkAlwaysShow := TCheckBox.Create(PnlOpts);
  FChkAlwaysShow.Parent := PnlOpts;
  FChkAlwaysShow.Align := alLeft;
  FChkAlwaysShow.Caption := 'Sempre exibir esta janela antes de executar alterações DDL';
  FChkAlwaysShow.Checked := IsDdlPreviewEnabled;
  FChkAlwaysShow.OnClick := @ChkAlwaysShowClick;

  FLblFeedback := TLabel.Create(PnlOpts);
  FLblFeedback.Parent := PnlOpts;
  FLblFeedback.Align := alRight;
  FLblFeedback.Layout := tlCenter;
  FLblFeedback.Font.Style := [fsBold];
  FLblFeedback.Font.Color := $001B7F3A;
  FLblFeedback.Caption := '';

  FSynHl := TSynSQLSyn.Create(Self);
  if (FProfile <> nil) and (FProfile.DatabaseType = dtPostgreSQL) then
    FSynHl.SQLDialect := sqlPostgres
  else
    FSynHl.SQLDialect := sqlFirebird40;
  FSynHl.Enabled := True;

  FSynEdit := TSynEdit.Create(Self);
  FSynEdit.Parent := Self;
  FSynEdit.Align := alClient;
  FSynEdit.BorderSpacing.Around := 8;
  {$IFDEF UNIX}
  FSynEdit.Font.Name := 'Monospace';
  {$ELSE}
  FSynEdit.Font.Name := 'Consolas';
  {$ENDIF}
  FSynEdit.Font.Height := -13;
  FSynEdit.ScrollBars := ssBoth;
  FSynEdit.Gutter.Visible := True;
  FSynEdit.RightEdge := 120;
  FSynEdit.TabWidth := 2;
  FSynEdit.Highlighter := FSynHl;
  FSynEdit.Keystrokes.ResetDefaults;
  FSynEdit.ReadOnly := not AAllowEdit;
  FSynEdit.Lines.Text := Trim(ADdlScript);
end;

procedure TDdlPreviewDialog.BtnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := BuildCopyableSql(FSynEdit.Lines.Text);
  FLblFeedback.Caption := '✓ SQL copiado para a área de transferência!';
end;

procedure TDdlPreviewDialog.BtnAppendClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
  ProfileLabel, DbLabel, BlockText: string;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Anexar DDL em arquivo de histórico (.sql)';
    Dlg.Filter := 'Scripts SQL (*.sql)|*.sql|Todos os arquivos (*.*)|*.*';
    Dlg.DefaultExt := 'sql';
    Dlg.Options := [ofEnableSizing];
    if GLastChangelogFile <> '' then
    begin
      Dlg.InitialDir := ExtractFileDir(GLastChangelogFile);
      Dlg.FileName := ExtractFileName(GLastChangelogFile);
    end;
    if not Dlg.Execute then
      Exit;

    GLastChangelogFile := Dlg.FileName;
    SaveSettings;

    if FProfile <> nil then
    begin
      ProfileLabel := FProfile.Name;
      DbLabel := DatabaseTypeToStr(FProfile.DatabaseType);
    end
    else
    begin
      ProfileLabel := 'Conexão';
      DbLabel := 'SQL';
    end;

    BlockText := Format('-- [%s] %s (%s) | %s', [
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
      ProfileLabel,
      DbLabel,
      FOperationTitle
    ]) + LineEnding + BuildCopyableSql(FSynEdit.Lines.Text) + LineEnding + LineEnding;

    SL := TStringList.Create;
    try
      if FileExists(Dlg.FileName) then
        SL.LoadFromFile(Dlg.FileName);
      SL.Text := SL.Text + BlockText;
      SL.SaveToFile(Dlg.FileName);
    finally
      SL.Free;
    end;

    FLblFeedback.Caption := '✓ Anexado em: ' + ExtractFileName(Dlg.FileName);
  finally
    Dlg.Free;
  end;
end;

procedure TDdlPreviewDialog.ChkAlwaysShowClick(Sender: TObject);
begin
  SetDdlPreviewEnabled(FChkAlwaysShow.Checked);
end;

procedure TDdlPreviewDialog.FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ((Key = VK_F9) and (Shift = [])) or ((Key = VK_RETURN) and (ssCtrl in Shift)) then
  begin
    Key := 0;
    ModalResult := mrOk;
  end
  else if ((Key = VK_C) or (Key = Ord('C'))) and (Shift = [ssCtrl, ssShift]) then
  begin
    Key := 0;
    BtnCopyClick(nil);
  end;
end;

function ConfirmAndPreviewDDL(
  const AProfile: TConnectionProfile;
  const AOperationTitle: string;
  const ADdlScript: string;
  out AEditedDdl: string;
  const AAllowEdit: Boolean
): Boolean;
var
  Dlg: TDdlPreviewDialog;
  OldCursor: TCursor;
begin
  AEditedDdl := ADdlScript;
  if not IsDdlPreviewEnabled then
    Exit(True);

  OldCursor := Screen.Cursor;
  Screen.Cursor := crDefault;
  try
    Dlg := TDdlPreviewDialog.CreateNew(Forms.Application);
    try
      Dlg.FProfile := AProfile;
      Dlg.FOperationTitle := AOperationTitle;
      Dlg.BuildUI(AAllowEdit, ADdlScript);
      Result := Dlg.ShowModal = mrOk;
      if Result and AAllowEdit and (Trim(Dlg.FSynEdit.Lines.Text) <> Trim(ADdlScript)) then
        AEditedDdl := Trim(Dlg.FSynEdit.Lines.Text);
    finally
      Dlg.Free;
    end;
  finally
    Screen.Cursor := OldCursor;
  end;
end;

end.
