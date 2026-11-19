unit Application.TestConnectionUseCase;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Domain.ConnectionProfile,
  Domain.Interfaces;

type
  TTestConnectionUseCase = class
  private
    FFactory: IDatabaseProviderFactory;
  public
    constructor Create(const AFactory: IDatabaseProviderFactory);
    function Execute(const AProfile: TConnectionProfile; out AMessage: string): Boolean;
  end;

implementation

constructor TTestConnectionUseCase.Create(const AFactory: IDatabaseProviderFactory);
begin
  inherited Create;
  FFactory := AFactory;
end;

function TTestConnectionUseCase.Execute(const AProfile: TConnectionProfile; out AMessage: string): Boolean;
var
  Provider: IDatabaseProvider;
begin
  Result := False;
  AMessage := '';
  if AProfile = nil then
  begin
    AMessage := 'Perfil de conexão inválido.';
    Exit;
  end;

  try
    AProfile.Validate;
    Provider := FFactory.GetProvider(AProfile.DatabaseType);
    Result := Provider.TestConnection(AProfile, AMessage);
    if Result and (AMessage = '') then
      AMessage := 'Conexão estabelecida com sucesso.';
  except
    on E: Exception do
    begin
      Result := False;
      AMessage := E.Message;
    end;
  end;
end;

end.
