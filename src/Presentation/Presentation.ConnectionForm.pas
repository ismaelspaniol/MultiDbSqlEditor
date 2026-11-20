unit Presentation.ConnectionForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Application.TestConnectionUseCase;

type
  { TConnectionForm }
  TConnectionForm = class(TForm)
    pnlContent: TPanel;
    pnlButtons: TPanel;
    pnlRowCreds: TPanel;
    pnlUser: TPanel;
    pnlPass: TPanel;
    pnlRowOpts: TPanel;
    pnlCharset: TPanel;
    pnlRole: TPanel;
    lblName: TLabel;
    edtName: TEdit;
    lblDbType: TLabel;
    cbDbType: TComboBox;
    lblHost: TLabel;
    edtHost: TEdit;
    lblPort: TLabel;
    edtPort: TEdit;
    lblDatabase: TLabel;
    edtDatabase: TEdit;
    btnBrowseDb: TButton;
    lblUsername: TLabel;
    edtUsername: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblCharset: TLabel;
    cbCharset: TComboBox;
    lblRole: TLabel;
    edtRole: TEdit;
    lblFirebirdVersion: TLabel;
    cbFirebirdVersion: TComboBox;
    btnTest: TButton;
    btnSave: TButton;
    btnCancel: TButton;
    dlgOpenDb: TOpenDialog;
    procedure cbDbTypeChange(Sender: TObject);
    procedure edtHostChange(Sender: TObject);
    procedure edtDatabaseChange(Sender: TObject);
    procedure btnBrowseDbClick(Sender: TObject);
    procedure btnTestClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FProfile: TConnectionProfile;
    FTestUseCase: TTestConnectionUseCase;
    FIsAutoFilling: Boolean;
    procedure TryAutoParseConnectionString(const AText: string);
    procedure UpdateFieldsForDatabaseType;
    procedure LoadFromProfile(const AProfile: TConnectionProfile);
    procedure SaveToProfile(const AProfile: TConnectionProfile);
  public
    class function Execute(
      const AProfile: TConnectionProfile;
      const ATestUseCase: TTestConnectionUseCase
    ): Boolean;
  end;

implementation

{$R *.lfm}

class function TConnectionForm.Execute(
  const AProfile: TConnectionProfile;
  const ATestUseCase: TTestConnectionUseCase
): Boolean;
var
  Frm: TConnectionForm;
begin
  Frm := TConnectionForm.Create(nil);
  try
    Frm.FProfile := AProfile;
    Frm.FTestUseCase := ATestUseCase;
    Frm.LoadFromProfile(AProfile);
    Result := Frm.ShowModal = mrOk;
    if Result then
      Frm.SaveToProfile(AProfile);
  finally
    Frm.Free;
  end;
end;

procedure TConnectionForm.LoadFromProfile(const AProfile: TConnectionProfile);
begin
  if Trim(AProfile.Id) = '' then
    Caption := 'Nova Conexão de Banco de Dados'
  else
    Caption := 'Editar Conexão: ' + AProfile.Name;

  FIsAutoFilling := True;
  try
    edtName.Text := AProfile.Name;
    case AProfile.DatabaseType of
      dtFirebird: cbDbType.ItemIndex := 0;
      dtPostgreSQL: cbDbType.ItemIndex := 1;
    end;
    edtHost.Text := AProfile.Host;
    edtPort.Text := IntToStr(AProfile.Port);
    edtDatabase.Text := AProfile.Database;
    edtUsername.Text := AProfile.Username;
    edtPassword.Text := AProfile.Password;
    cbCharset.Text := AProfile.Charset;
    edtRole.Text := AProfile.Role;
    case AProfile.FirebirdVersion of
      fvAuto: cbFirebirdVersion.ItemIndex := 0;
      fv50: cbFirebirdVersion.ItemIndex := 1;
      fv40: cbFirebirdVersion.ItemIndex := 2;
      fv30: cbFirebirdVersion.ItemIndex := 3;
      fv25: cbFirebirdVersion.ItemIndex := 4;
    else
      cbFirebirdVersion.ItemIndex := 0;
    end;
    UpdateFieldsForDatabaseType;
  finally
    FIsAutoFilling := False;
  end;
end;

procedure TConnectionForm.SaveToProfile(const AProfile: TConnectionProfile);
begin
  AProfile.Name := Trim(edtName.Text);
  if cbDbType.ItemIndex = 1 then
    AProfile.DatabaseType := dtPostgreSQL
  else
    AProfile.DatabaseType := dtFirebird;
  AProfile.Host := Trim(edtHost.Text);
  AProfile.Port := StrToIntDef(Trim(edtPort.Text), Integer(DefaultPortForDatabase(AProfile.DatabaseType)));
  AProfile.Database := Trim(edtDatabase.Text);
  AProfile.Username := Trim(edtUsername.Text);
  AProfile.Password := edtPassword.Text;
  AProfile.Charset := Trim(cbCharset.Text);
  AProfile.Role := Trim(edtRole.Text);
  case cbFirebirdVersion.ItemIndex of
    1: AProfile.FirebirdVersion := fv50;
    2: AProfile.FirebirdVersion := fv40;
    3: AProfile.FirebirdVersion := fv30;
    4: AProfile.FirebirdVersion := fv25;
  else
    AProfile.FirebirdVersion := fvAuto;
  end;
end;

procedure TConnectionForm.UpdateFieldsForDatabaseType;
var
  IsFirebird: Boolean;
begin
  IsFirebird := cbDbType.ItemIndex <> 1;
  if IsFirebird then
  begin
    lblDatabase.Caption := 'Arquivo (.fdb) ou Alias:';
    btnBrowseDb.Visible := True;
    edtDatabase.AnchorSideRight.Control := btnBrowseDb;
    edtDatabase.AnchorSideRight.Side := asrLeft;
    edtDatabase.BorderSpacing.Right := 6;
    lblCharset.Enabled := True;
    cbCharset.Enabled := True;
    lblRole.Enabled := True;
    edtRole.Enabled := True;
    lblFirebirdVersion.Enabled := True;
    cbFirebirdVersion.Enabled := True;
    if Trim(edtUsername.Text) = '' then
      edtUsername.Text := 'SYSDBA';
  end
  else
  begin
    lblDatabase.Caption := 'Nome do Banco (Database):';
    btnBrowseDb.Visible := False;
    edtDatabase.AnchorSideRight.Control := pnlContent;
    edtDatabase.AnchorSideRight.Side := asrBottom;
    edtDatabase.BorderSpacing.Right := 0;
    lblCharset.Enabled := False;
    cbCharset.Enabled := False;
    lblRole.Enabled := False;
    edtRole.Enabled := False;
    lblFirebirdVersion.Enabled := False;
    cbFirebirdVersion.Enabled := False;
    if Trim(edtUsername.Text) = '' then
      edtUsername.Text := 'postgres';
  end;
end;

procedure TConnectionForm.cbDbTypeChange(Sender: TObject);
begin
  if cbDbType.ItemIndex = 1 then
  begin
    if (Trim(edtPort.Text) = '') or (Trim(edtPort.Text) = '3050') then
      edtPort.Text := '5432';
    if SameText(Trim(edtUsername.Text), 'SYSDBA') then
      edtUsername.Text := 'postgres';
  end
  else
  begin
    if (Trim(edtPort.Text) = '') or (Trim(edtPort.Text) = '5432') then
      edtPort.Text := '3050';
    if SameText(Trim(edtUsername.Text), 'postgres') then
      edtUsername.Text := 'SYSDBA';
  end;
  UpdateFieldsForDatabaseType;
end;

procedure TConnectionForm.TryAutoParseConnectionString(const AText: string);
var
  ParsedHost, ParsedDb, SuggestedName: string;
  ParsedPort: Word;
begin
  if FIsAutoFilling or (cbDbType.ItemIndex = 1) then
    Exit;

  if TConnectionProfile.TryParseFirebirdString(AText, ParsedHost, ParsedPort, ParsedDb) then
  begin
    FIsAutoFilling := True;
    try
      edtHost.Text := ParsedHost;
      edtPort.Text := IntToStr(ParsedPort);
      edtDatabase.Text := ParsedDb;
      if Trim(edtName.Text) = '' then
      begin
        SuggestedName := ChangeFileExt(ExtractFileName(ParsedDb), '');
        if SuggestedName <> '' then
          edtName.Text := SuggestedName;
      end;
    finally
      FIsAutoFilling := False;
    end;
  end;
end;

procedure TConnectionForm.edtHostChange(Sender: TObject);
begin
  TryAutoParseConnectionString(edtHost.Text);
end;

procedure TConnectionForm.edtDatabaseChange(Sender: TObject);
begin
  TryAutoParseConnectionString(edtDatabase.Text);
end;

procedure TConnectionForm.btnBrowseDbClick(Sender: TObject);
begin
  if dlgOpenDb.Execute then
    edtDatabase.Text := dlgOpenDb.FileName;
end;

procedure TConnectionForm.btnTestClick(Sender: TObject);
var
  TempProfile: TConnectionProfile;
  Msg: string;
begin
  if FTestUseCase = nil then
    Exit;

  TempProfile := TConnectionProfile.Create;
  try
    SaveToProfile(TempProfile);
    Screen.Cursor := crHourGlass;
    try
      if FTestUseCase.Execute(TempProfile, Msg) then
        MessageDlg('Sucesso', Msg, mtInformation, [mbOK], 0)
      else
        MessageDlg('Falha na Conexão', Msg, mtError, [mbOK], 0);
    finally
      Screen.Cursor := crDefault;
    end;
  finally
    TempProfile.Free;
  end;
end;

procedure TConnectionForm.btnSaveClick(Sender: TObject);
var
  TempProfile: TConnectionProfile;
begin
  TempProfile := TConnectionProfile.Create;
  try
    SaveToProfile(TempProfile);
    try
      TempProfile.Validate;
      ModalResult := mrOk;
    except
      on E: Exception do
        MessageDlg('Validação', E.Message, mtWarning, [mbOK], 0);
    end;
  finally
    TempProfile.Free;
  end;
end;

end.
