unit Test.SqlAliasResolver;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.SqlAliasResolver;

type
  TTestSqlAliasResolver = class(TTestCase)
  published
    procedure TestExtractAndResolveAliases;
  end;

implementation

procedure TTestSqlAliasResolver.TestExtractAndResolveAliases;
const
  SQL = 'SELECT c.nome, p.total FROM clientes c JOIN pedidos AS p ON p.cliente_id = c.id WHERE c.';
var
  Aliases: TSqlTableAliasArray;
begin
  Aliases := ExtractSqlTableAliases(SQL);
  AssertTrue(Length(Aliases) >= 2);
  AssertEquals('clientes', ResolveSqlTableAlias(SQL, Length(SQL), 'c'));
  AssertEquals('pedidos', ResolveSqlTableAlias(SQL, Length(SQL), 'p'));
end;

initialization
  RegisterTest(TTestSqlAliasResolver);

end.
