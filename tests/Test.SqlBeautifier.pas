unit Test.SqlBeautifier;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.SqlBeautifier;

type
  TTestSqlBeautifier = class(TTestCase)
  published
    procedure TestFormatSelectQuery;
  end;

implementation

procedure TTestSqlBeautifier.TestFormatSelectQuery;
var
  Formatted: string;
begin
  Formatted := TSqlBeautifier.FormatSql('select id, nome from clientes where ativo = 1 order by nome');
  AssertTrue(Pos('SELECT', Formatted) > 0);
  AssertTrue(Pos('FROM', Formatted) > 0);
  AssertTrue(Pos('WHERE', Formatted) > 0);
  AssertTrue(Pos('ORDER BY', Formatted) > 0);
end;

initialization
  RegisterTest(TTestSqlBeautifier);

end.
