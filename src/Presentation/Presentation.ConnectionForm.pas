unit Presentation.ConnectionForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Clipbrd,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Application.TestConnectionUseCase,
  Application.ManageConnectionsUseCase;

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
    lblSchema: TLabel;
    cbSchema: TComboBox;
    btnLoadSchemas: TButton;
    btnTest: TButton;
    btnSave: TButton;
    btnCancel: TButton;
    dlgOpenDb: TOpenDialog;
    procedure cbDbTypeChange(Sender: TObject);
    procedure edtHostChange(Sender: TObject);
    procedure edtDatabaseChange(Sender: TObject);
    procedure btnBrowseDbClick(Sender: TObject);
    procedure btnLoadSchemasClick(Sender: TObject);
    procedure btnTestClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FProfile: TConnectionProfile;
    FTestUseCase: TTestConnectionUseCase;
    FManageUseCase: TManageConnectionsUseCase;
    FIsAutoFilling: Boolean;
    lblEnvironment: TLabel;
    cbEnvironment: TComboBox;
    lblFolder: TLabel;
    cbFolder: TComboBox;
    lblConnStr: TLabel;
    edtConnStr: TEdit;
    btnCopyConnStr: TButton;
    procedure EnsureEnvironmentControls;
    procedure RefreshFolderItems;
    procedure UpdateConnectionStringPreview;
    procedure btnCopyConnStrClick(Sender: TObject);
    procedure edtPortChange(Sender: TObject);
    procedure TryAutoParseConnectionString(const AText: string);
    procedure UpdateFieldsForDatabaseType;
    procedure LoadFromProfile(const AProfile: TConnectionProfile);
    procedure SaveToProfile(const AProfile: TConnectionProfile);
  public
    class function Execute(
      const AProfile: TConnectionProfile;
      const ATestUseCase: TTestConnectionUseCase;
      const AManageUseCase: TManageConnectionsUseCase = nil
    ): Boolean;
  end;

implementation

{$R *.lfm}

class function TConnectionForm.Execute(
  const AProfile: TConnectionProfile;
  const ATestUseCase: TTestConnectionUseCase;
  const AManageUseCase: TManageConnectionsUseCase
): Boolean;
var
  Frm: TConnectionForm;
begin
  Frm := TConnectionForm.Create(nil);
  try
    Frm.FProfile := AProfile;
    Frm.FTestUseCase := ATestUseCase;
    Frm.FManageUseCase := AManageUseCase;
    Frm.LoadFromProfile(AProfile);
    Result := Frm.ShowModal = mrOk;
    if Result then
      Frm.SaveToProfile(AProfile);
  finally
    Frm.Free;
  end;
end;

procedure TConnectionForm.EnsureEnvironmentControls;
begin
  if cbEnvironment = nil then
  begin
    lblEnvironment := TLabel.Create(Self);
    lblEnvironment.Parent := pnlContent;
    lblEnvironment.Left := 0;
    lblEnvironment.Top := 306;
    lblEnvironment.Caption := 'Ambiente / Cor de Alerta:';

    cbEnvironment := TComboBox.Create(Self);
    cbEnvironment.Parent := pnlContent;
    cbEnvironment.Left := 0;
    cbEnvironment.Top := 324;
    cbEnvironment.Width := pnlContent.ClientWidth;
    cbEnvironment.Anchors := [akTop, akLeft, akRight];
    cbEnvironment.Style := csDropDownList;
    cbEnvironment.Items.Add('Padrão (Sem cor)');
    cbEnvironment.Items.Add('Desenvolvimento (Verde)');
    cbEnvironment.Items.Add('Homologação (Amarelo)');
    cbEnvironment.Items.Add('Produção (Vermelho + Alerta de Segurança)');
    cbEnvironment.ItemIndex := 0;
  end;

  if cbFolder = nil then
  begin
    lblFolder := TLabel.Create(Self);
    lblFolder.Parent := pnlContent;
    lblFolder.Left := 0;
    lblFolder.Top := 356;
    lblFolder.Caption := 'Pasta / Grupo (opcional — escolha existente ou digite um novo nome):';

    cbFolder := TComboBox.Create(Self);
    cbFolder.Parent := pnlContent;
    cbFolder.Left := 0;
    cbFolder.Top := 374;
    cbFolder.Width := pnlContent.ClientWidth;
    cbFolder.Anchors := [akTop, akLeft, akRight];
    cbFolder.Style := csDropDown;
    cbFolder.Text := '';

    if Constraints.MinHeight < 495 then
      Constraints.MinHeight := 495;
    if Height < 520 then
      Height := 520;
  end;

  if edtConnStr = nil then
  begin
    lblConnStr := TLabel.Create(Self);
    lblConnStr.Parent := pnlContent;
    lblConnStr.Left := 0;
    lblConnStr.Top := 406;
    lblConnStr.Caption := 'String de conexão (somente leitura — selecione ou clique em Copiar):';

    btnCopyConnStr := TButton.Create(Self);
    btnCopyConnStr.Parent := pnlContent;
    btnCopyConnStr.Top := 424;
    btnCopyConnStr.Width := 80;
    btnCopyConnStr.Height := 23;
    btnCopyConnStr.Left := pnlContent.ClientWidth - 80;
    btnCopyConnStr.Anchors := [akTop, akRight];
    btnCopyConnStr.Caption := 'Copiar';
    btnCopyConnStr.OnClick := @btnCopyConnStrClick;

    edtConnStr := TEdit.Create(Self);
    edtConnStr.Parent := pnlContent;
    edtConnStr.Left := 0;
    edtConnStr.Top := 424;
    edtConnStr.Width := pnlContent.ClientWidth - 86;
    edtConnStr.Anchors := [akTop, akLeft, akRight];
    edtConnStr.ReadOnly := True;
    edtConnStr.TabStop := True;
    edtConnStr.Color := clBtnFace;

    if Constraints.MinHeight < 545 then
      Constraints.MinHeight := 545;
    if Height < 570 then
      Height := 570;

    edtPort.OnChange := @edtPortChange;
  end;
end;

procedure TConnectionForm.RefreshFolderItems;
var
  Folders: TStringList;
  CurText: string;
begin
  if (cbFolder = nil) or (FManageUseCase = nil) then
    Exit;

  CurText := cbFolder.Text;
  Folders := TStringList.Create;
  try
    FManageUseCase.GetFolders(Folders);
    cbFolder.Items.Assign(Folders);
    cbFolder.Text := CurText;
  finally
    Folders.Free;
  end;
end;

procedure TConnectionForm.LoadFromProfile(const AProfile: TConnectionProfile);
begin
  EnsureEnvironmentControls;
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
      dtMariaDB: cbDbType.ItemIndex := 2;
    end;
    edtHost.Text := AProfile.Host;
    edtPort.Text := IntToStr(AProfile.Port);
    edtDatabase.Text := AProfile.Database;
    edtUsername.Text := AProfile.Username;
    edtPassword.Text := AProfile.Password;
    cbCharset.Text := AProfile.Charset;
    edtRole.Text := AProfile.Role;
    cbSchema.Text := AProfile.EffectiveSchema;
    case AProfile.FirebirdVersion of
      fvAuto: cbFirebirdVersion.ItemIndex := 0;
      fv50: cbFirebirdVersion.ItemIndex := 1;
      fv40: cbFirebirdVersion.ItemIndex := 2;
      fv30: cbFirebirdVersion.ItemIndex := 3;
      fv25: cbFirebirdVersion.ItemIndex := 4;
    else
      cbFirebirdVersion.ItemIndex := 0;
    end;
    if cbEnvironment <> nil then
    begin
      if SameText(AProfile.EnvironmentKind, 'Desenvolvimento') then
        cbEnvironment.ItemIndex := 1
      else if SameText(AProfile.EnvironmentKind, 'Homologacao') then
        cbEnvironment.ItemIndex := 2
      else if SameText(AProfile.EnvironmentKind, 'Producao') then
        cbEnvironment.ItemIndex := 3
      else
        cbEnvironment.ItemIndex := 0;
    end;
    RefreshFolderItems;
    if cbFolder <> nil then
      cbFolder.Text := Trim(AProfile.Folder);
    UpdateFieldsForDatabaseType;
    UpdateConnectionStringPreview;
  finally
    FIsAutoFilling := False;
  end;
end;

procedure TConnectionForm.SaveToProfile(const AProfile: TConnectionProfile);
begin
  AProfile.Name := Trim(edtName.Text);
  if cbDbType.ItemIndex = 1 then
    AProfile.DatabaseType := dtPostgreSQL
  else if cbDbType.ItemIndex = 2 then
    AProfile.DatabaseType := dtMariaDB
  else
    AProfile.DatabaseType := dtFirebird;
  AProfile.Host := Trim(edtHost.Text);
  AProfile.Port := StrToIntDef(Trim(edtPort.Text), Integer(DefaultPortForDatabase(AProfile.DatabaseType)));
  AProfile.Database := Trim(edtDatabase.Text);
  AProfile.Username := Trim(edtUsername.Text);
  AProfile.Password := edtPassword.Text;
  AProfile.Charset := Trim(cbCharset.Text);
  AProfile.Role := Trim(edtRole.Text);
  if Trim(cbSchema.Text) <> '' then
    AProfile.Schema := Trim(cbSchema.Text)
  else
    AProfile.Schema := 'public';
  case cbFirebirdVersion.ItemIndex of
    1: AProfile.FirebirdVersion := fv50;
    2: AProfile.FirebirdVersion := fv40;
    3: AProfile.FirebirdVersion := fv30;
    4: AProfile.FirebirdVersion := fv25;
  else
    AProfile.FirebirdVersion := fvAuto;
  end;
  if cbEnvironment <> nil then
  begin
    case cbEnvironment.ItemIndex of
      1: AProfile.EnvironmentKind := 'Desenvolvimento';
      2: AProfile.EnvironmentKind := 'Homologacao';
      3: AProfile.EnvironmentKind := 'Producao';
    else
      AProfile.EnvironmentKind := 'Padrao';
    end;
  end;
  if cbFolder <> nil then
    AProfile.Folder := Trim(cbFolder.Text);
end;

procedure TConnectionForm.UpdateFieldsForDatabaseType;
var
  IsFirebird, IsPostgres: Boolean;
begin
  IsFirebird := cbDbType.ItemIndex = 0;
  IsPostgres := cbDbType.ItemIndex = 1;
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
    lblFirebirdVersion.Visible := True;
    cbFirebirdVersion.Visible := True;
    lblSchema.Visible := False;
    cbSchema.Visible := False;
    btnLoadSchemas.Visible := False;
    if Trim(edtUsername.Text) = '' then
      edtUsername.Text := 'SYSDBA';
  end
  else
  begin
    if IsPostgres then
      lblDatabase.Caption := 'Nome do Banco (Database - opcional para listar todos):'
    else
      lblDatabase.Caption := 'Nome do Banco (Database):';
    btnBrowseDb.Visible := False;
    edtDatabase.AnchorSideRight.Control := pnlContent;
    edtDatabase.AnchorSideRight.Side := asrBottom;
    edtDatabase.BorderSpacing.Right := 0;
    lblCharset.Enabled := not IsPostgres;
    cbCharset.Enabled := not IsPostgres;
    lblRole.Enabled := False;
    edtRole.Enabled := False;
    lblFirebirdVersion.Enabled := False;
    cbFirebirdVersion.Enabled := False;
    lblFirebirdVersion.Visible := False;
    cbFirebirdVersion.Visible := False;
    lblSchema.Visible := IsPostgres;
    cbSchema.Visible := IsPostgres;
    btnLoadSchemas.Visible := IsPostgres;
    if IsPostgres then
    begin
      if Trim(cbSchema.Text) = '' then
        cbSchema.Text := 'public';
      if Trim(edtUsername.Text) = '' then
        edtUsername.Text := 'postgres';
    end
    else
    begin
      if Trim(edtUsername.Text) = '' then
        edtUsername.Text := 'root';
    end;
  end;
end;

procedure TConnectionForm.cbDbTypeChange(Sender: TObject);
begin
  if cbDbType.ItemIndex = 1 then
  begin
    if (Trim(edtPort.Text) = '') or (Trim(edtPort.Text) = '3050') or (Trim(edtPort.Text) = '3306') then
      edtPort.Text := '5432';
    if SameText(Trim(edtUsername.Text), 'SYSDBA') or SameText(Trim(edtUsername.Text), 'root') then
      edtUsername.Text := 'postgres';
  end
  else if cbDbType.ItemIndex = 2 then
  begin
    if (Trim(edtPort.Text) = '') or (Trim(edtPort.Text) = '3050') or (Trim(edtPort.Text) = '5432') then
      edtPort.Text := '3306';
    if SameText(Trim(edtUsername.Text), 'SYSDBA') or SameText(Trim(edtUsername.Text), 'postgres') then
      edtUsername.Text := 'root';
  end
  else
  begin
    if (Trim(edtPort.Text) = '') or (Trim(edtPort.Text) = '5432') or (Trim(edtPort.Text) = '3306') then
      edtPort.Text := '3050';
    if SameText(Trim(edtUsername.Text), 'postgres') or SameText(Trim(edtUsername.Text), 'root') then
      edtUsername.Text := 'SYSDBA';
  end;
  UpdateFieldsForDatabaseType;
  UpdateConnectionStringPreview;
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
    UpdateConnectionStringPreview;
  end;
end;

procedure TConnectionForm.UpdateConnectionStringPreview;
var
  DbType: TDatabaseType;
  PortNum: Word;
begin
  if edtConnStr = nil then
    Exit;

  if cbDbType.ItemIndex = 1 then
    DbType := dtPostgreSQL
  else if cbDbType.ItemIndex = 2 then
    DbType := dtMariaDB
  else
    DbType := dtFirebird;

  PortNum := StrToIntDef(Trim(edtPort.Text), DefaultPortForDatabase(DbType));
  edtConnStr.Text := TConnectionProfile.BuildConnectionString(
    DbType,
    edtHost.Text,
    PortNum,
    edtDatabase.Text
  );
  if btnCopyConnStr <> nil then
    btnCopyConnStr.Caption := 'Copiar';
end;

procedure TConnectionForm.btnCopyConnStrClick(Sender: TObject);
begin
  if edtConnStr = nil then
    Exit;
  Clipboard.AsText := edtConnStr.Text;
  if btnCopyConnStr <> nil then
    btnCopyConnStr.Caption := 'Copiado!';
end;

procedure TConnectionForm.edtPortChange(Sender: TObject);
begin
  UpdateConnectionStringPreview;
end;

procedure TConnectionForm.edtHostChange(Sender: TObject);
begin
  TryAutoParseConnectionString(edtHost.Text);
  UpdateConnectionStringPreview;
end;

procedure TConnectionForm.edtDatabaseChange(Sender: TObject);
begin
  TryAutoParseConnectionString(edtDatabase.Text);
  UpdateConnectionStringPreview;
end;

procedure TConnectionForm.btnBrowseDbClick(Sender: TObject);
begin
  if dlgOpenDb.Execute then
    edtDatabase.Text := dlgOpenDb.FileName;
end;

procedure TConnectionForm.btnLoadSchemasClick(Sender: TObject);
var
  TempProfile: TConnectionProfile;
  Schemas: TStringList;
  CurText, ErrMsg: string;
begin
  if FTestUseCase = nil then
    Exit;

  CurText := Trim(cbSchema.Text);
  TempProfile := TConnectionProfile.Create;
  Schemas := TStringList.Create;
  try
    SaveToProfile(TempProfile);
    Screen.Cursor := crHourGlass;
    try
      if not FTestUseCase.ListPostgresSchemas(TempProfile, Schemas, ErrMsg) then
      begin
        MessageDlg('Schemas PostgreSQL', 'Erro ao listar schemas: ' + ErrMsg, mtError, [mbOK], 0);
        Exit;
      end;
    finally
      Screen.Cursor := crDefault;
    end;

    cbSchema.Items.Assign(Schemas);
    if (CurText <> '') and (cbSchema.Items.IndexOf(CurText) >= 0) then
      cbSchema.Text := CurText
    else if cbSchema.Items.Count > 0 then
      cbSchema.ItemIndex := 0;
    cbSchema.DroppedDown := cbSchema.Items.Count > 0;
  finally
    Schemas.Free;
    TempProfile.Free;
  end;
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
