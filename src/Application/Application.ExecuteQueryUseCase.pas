unit Application.ExecuteQueryUseCase;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Domain.Interfaces,
  Domain.QueryResult;

type
  TExecuteQueryUseCase = class
  public
    function Execute(
      const ASession: IDatabaseSession;
      const ASQL: string;
      const AAutoCommit: Boolean = False;
      const AFetchBatchSize: Integer = 100
    ): TQueryResult;
  end;

implementation

function TExecuteQueryUseCase.Execute(
  const ASession: IDatabaseSession;
  const ASQL: string;
  const AAutoCommit: Boolean;
  const AFetchBatchSize: Integer
): TQueryResult;
begin
  if ASession = nil then
    raise Exception.Create('Nenhuma sessão ativa vinculada à aba do editor.');

  if Trim(ASQL) = '' then
  begin
    Result := TQueryResult.Create;
    Result.Success := False;
    Result.MessageText := 'Nenhuma instrução SQL informada para execução.';
    Exit;
  end;

  if not ASession.IsConnected then
    ASession.Connect;

  Result := ASession.ExecuteSQL(ASQL, AAutoCommit, AFetchBatchSize);
end;

end.
