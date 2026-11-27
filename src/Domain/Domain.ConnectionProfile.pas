unit Domain.ConnectionProfile;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Domain.DatabaseTypes;

type
  { Perfil de conexão cadastrado pelo usuário (independente de driver/UI) }
  TConnectionProfile = class
  private
    FId: string;
    FName: string;
    FDatabaseType: TDatabaseType;
    FHost: string;
    FPort: Word;
    FDatabase: string;
    FUsername: string;
    FPassword: string;
    FCharset: string;
    FRole: string;
    FSchema: string;
    FClientLibraryPath: string;
    FFirebirdVersion: TFirebirdVersion;
    FEnvironmentKind: string;
    FFolder: string;
  public
    constructor Create;
    function Clone: TConnectionProfile;
    procedure Validate;
    function EffectiveDatabase: string;
    function EffectiveSchema: string;
    function IsProduction: Boolean;
    function EnvironmentBannerColor: Integer;
    function EnvironmentTextColor: Integer;
    { Faz o parse de strings como "127.0.0.1/3055:D:\caminho\banco.fdb" ou "host:banco.fdb" }
    class function TryParseFirebirdString(
      const AInput: string;
      out AHost: string;
      out APort: Word;
      out ADatabase: string
    ): Boolean;
    class function BuildConnectionString(
      ADbType: TDatabaseType;
      const AHost: string;
      APort: Word;
      const ADatabase: string
    ): string;
    function ConnectionString: string;

    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property DatabaseType: TDatabaseType read FDatabaseType write FDatabaseType;
    property Host: string read FHost write FHost;
    property Port: Word read FPort write FPort;
    { No Firebird: caminho do arquivo .fdb (ou alias). No PostgreSQL: nome do database. }
    property Database: string read FDatabase write FDatabase;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property Charset: string read FCharset write FCharset;
    property Role: string read FRole write FRole;
    { No PostgreSQL: schema padrão da sessão (padrão: 'public') }
    property Schema: string read FSchema write FSchema;
    { Caminho opcional para fbclient.dll ou libpq.dll }
    property ClientLibraryPath: string read FClientLibraryPath write FClientLibraryPath;
    property FirebirdVersion: TFirebirdVersion read FFirebirdVersion write FFirebirdVersion;
    property EnvironmentKind: string read FEnvironmentKind write FEnvironmentKind;
    property Folder: string read FFolder write FFolder;
  end;

implementation

constructor TConnectionProfile.Create;
begin
  inherited Create;
  FDatabaseType := dtFirebird;
  FHost := 'localhost';
  FPort := DefaultPortForDatabase(FDatabaseType);
  FCharset := 'UTF8';
  FSchema := 'public';
  FFirebirdVersion := fvAuto;
  FEnvironmentKind := 'Padrao';
  FFolder := '';
end;

function TConnectionProfile.IsProduction: Boolean;
begin
  Result := SameText(Trim(FEnvironmentKind), 'Producao');
end;

function TConnectionProfile.EnvironmentBannerColor: Integer;
begin
  if SameText(Trim(FEnvironmentKind), 'Desenvolvimento') then
    Result := $00DCF5DC
  else if SameText(Trim(FEnvironmentKind), 'Homologacao') then
    Result := $00CCF2FF
  else if SameText(Trim(FEnvironmentKind), 'Producao') then
    Result := $00D6D6FF
  else
    Result := 0;
end;

function TConnectionProfile.EnvironmentTextColor: Integer;
begin
  if SameText(Trim(FEnvironmentKind), 'Desenvolvimento') then
    Result := $001E7E1E
  else if SameText(Trim(FEnvironmentKind), 'Homologacao') then
    Result := $000066B3
  else if SameText(Trim(FEnvironmentKind), 'Producao') then
    Result := $001F1FC8
  else
    Result := 0;
end;

function TConnectionProfile.EffectiveDatabase: string;
begin
  Result := Trim(FDatabase);
  if (Result = '') and (FDatabaseType = dtPostgreSQL) then
    Result := 'postgres';
end;

function TConnectionProfile.EffectiveSchema: string;
begin
  Result := Trim(FSchema);
  if Result = '' then
    Result := 'public';
end;

function TConnectionProfile.Clone: TConnectionProfile;
begin
  Result := TConnectionProfile.Create;
  Result.Id := FId;
  Result.Name := FName;
  Result.DatabaseType := FDatabaseType;
  Result.Host := FHost;
  Result.Port := FPort;
  Result.Database := FDatabase;
  Result.Username := FUsername;
  Result.Password := FPassword;
  Result.Charset := FCharset;
  Result.Role := FRole;
  Result.Schema := FSchema;
  Result.ClientLibraryPath := FClientLibraryPath;
  Result.FirebirdVersion := FFirebirdVersion;
  Result.EnvironmentKind := FEnvironmentKind;
  Result.Folder := FFolder;
end;

procedure TConnectionProfile.Validate;
begin
  if Trim(FName) = '' then
    raise Exception.Create('O nome da conexão é obrigatório.');
  if (FDatabaseType <> dtPostgreSQL) and (Trim(FDatabase) = '') then
    raise Exception.Create('O caminho ou nome do banco de dados é obrigatório.');
  if Trim(FUsername) = '' then
    raise Exception.Create('O usuário é obrigatório.');
  if FPort = 0 then
    FPort := DefaultPortForDatabase(FDatabaseType);
end;

class function TConnectionProfile.TryParseFirebirdString(
  const AInput: string;
  out AHost: string;
  out APort: Word;
  out ADatabase: string
): Boolean;
var
  S, HostPart, DbPart, PortStr: string;
  ColonPos, SlashPos, PortNum: Integer;
begin
  Result := False;
  AHost := '';
  APort := 0;
  ADatabase := '';

  S := Trim(AInput);
  if S = '' then
    Exit;

  ColonPos := Pos(':', S);
  if ColonPos <= 1 then
    Exit;

  { Ignora caminhos locais do Windows como "D:\pasta\banco.fdb" }
  if (ColonPos = 2) and (S[1] in ['A'..'Z', 'a'..'z']) and
     (Length(S) >= 3) and (S[3] in ['\', '/']) then
    Exit;

  HostPart := Trim(Copy(S, 1, ColonPos - 1));
  DbPart := Trim(Copy(S, ColonPos + 1, MaxInt));
  if (HostPart = '') or (DbPart = '') then
    Exit;

  SlashPos := Pos('/', HostPart);
  if SlashPos > 0 then
  begin
    AHost := Trim(Copy(HostPart, 1, SlashPos - 1));
    PortStr := Trim(Copy(HostPart, SlashPos + 1, MaxInt));
    if TryStrToInt(PortStr, PortNum) and (PortNum > 0) and (PortNum <= 65535) then
      APort := Word(PortNum)
    else
      Exit;
  end
  else
  begin
    AHost := HostPart;
    APort := DefaultPortForDatabase(dtFirebird);
  end;

  if AHost = '' then
    Exit;

  ADatabase := DbPart;
  Result := True;
end;

class function TConnectionProfile.BuildConnectionString(
  ADbType: TDatabaseType;
  const AHost: string;
  APort: Word;
  const ADatabase: string
): string;
var
  H, D: string;
  P: Word;
begin
  H := Trim(AHost);
  D := Trim(ADatabase);
  P := APort;
  if P = 0 then
    P := DefaultPortForDatabase(ADbType);

  if ADbType = dtFirebird then
  begin
    if H = '' then
      Result := D
    else if D = '' then
      Result := Format('%s/%d:', [H, P])
    else
      Result := Format('%s/%d:%s', [H, P, D]);
  end
  else
  begin
    if H = '' then
      Result := D
    else if D = '' then
      Result := Format('%s:%d', [H, P])
    else
      Result := Format('%s:%d/%s', [H, P, D]);
  end;
end;

function TConnectionProfile.ConnectionString: string;
begin
  Result := BuildConnectionString(FDatabaseType, FHost, FPort, FDatabase);
end;

end.
