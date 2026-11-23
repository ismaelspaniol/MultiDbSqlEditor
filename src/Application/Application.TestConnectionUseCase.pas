unit Application.TestConnectionUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces;

type
  TTestConnectionUseCase = class
  private
    FFactory: IDatabaseProviderFactory;
  public
    constructor Create(const AFactory: IDatabaseProviderFactory);
    function Execute(const AProfile: TConnectionProfile; out AMessage: string): Boolean;
    function ListPostgresSchemas(
      const AProfile: TConnectionProfile;
      const ASchemas: TStrings;
      out AError: string
    ): Boolean;
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

function TTestConnectionUseCase.ListPostgresSchemas(
  const AProfile: TConnectionProfile;
  const ASchemas: TStrings;
  out AError: string
): Boolean;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  I: Integer;
  S: string;
begin
  Result := False;
  AError := '';
  if (AProfile = nil) or (ASchemas = nil) or (FFactory = nil) then
  begin
    AError := 'Perfil de conexão inválido.';
    Exit;
  end;
  if AProfile.DatabaseType <> dtPostgreSQL then
  begin
    AError := 'Schemas estão disponíveis apenas para PostgreSQL.';
    Exit;
  end;

  ASchemas.Clear;
  try
    AProfile.Validate;
    Provider := FFactory.GetProvider(dtPostgreSQL);
    Session := Provider.CreateSession(AProfile);
    try
      Session.Connect;
      Res := Session.ExecuteSQL(
        'SELECT schema_name FROM information_schema.schemata ' +
        'WHERE schema_name NOT LIKE ''pg_%'' AND schema_name <> ''information_schema'' ' +
        'ORDER BY CASE WHEN schema_name = ''public'' THEN 0 ELSE 1 END, schema_name',
        False,
        0
      );
      try
        if (Res = nil) or (not Res.Success) then
        begin
          if Res <> nil then
            AError := Res.MessageText
          else
            AError := 'Falha ao consultar schemas.';
          Exit;
        end;
        for I := 0 to Res.RowCount - 1 do
        begin
          S := Trim(Res.GetRow(I)[0].AsText);
          if S <> '' then
            ASchemas.Add(S);
        end;
        Result := True;
      finally
        Res.Free;
      end;
    finally
      if Session.IsConnected then
        Session.Disconnect;
    end;
  except
    on E: Exception do
    begin
      Result := False;
      AError := E.Message;
    end;
  end;
end;

end.
