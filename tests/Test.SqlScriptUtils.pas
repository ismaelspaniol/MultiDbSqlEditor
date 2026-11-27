unit Test.SqlScriptUtils;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.DatabaseTypes,
  Domain.SqlScriptUtils;

type
  TTestSqlScriptUtils = class(TTestCase)
  published
    procedure TestSplitBasicStatements;
    procedure TestSplitFirebirdSetTerm;
    procedure TestSplitPostgresDollarQuote;
    procedure TestNormalizeCodeText;
  end;

implementation

procedure TTestSqlScriptUtils.TestSplitBasicStatements;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    SplitSqlScriptStatements(
      'SELECT ''a;b'' FROM RDB$DATABASE; -- comentario' + LineEnding +
      '/* bloco ; */' + LineEnding +
      'INSERT INTO T (X) VALUES (1);',
      dtFirebird,
      List
    );
    AssertEquals(2, List.Count);
    AssertEquals('SELECT ''a;b'' FROM RDB$DATABASE', List[0]);
    AssertEquals('INSERT INTO T (X) VALUES (1)', List[1]);
  finally
    List.Free;
  end;
end;

procedure TTestSqlScriptUtils.TestSplitFirebirdSetTerm;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    SplitSqlScriptStatements(
      'SET TERM ^ ;' + LineEnding +
      'CREATE PROCEDURE P_TEST AS BEGIN SELECT 1 FROM RDB$DATABASE; END^' + LineEnding +
      'SET TERM ; ^' + LineEnding +
      'SELECT 2 FROM RDB$DATABASE;',
      dtFirebird,
      List
    );
    AssertEquals(2, List.Count);
    AssertTrue(Pos('CREATE PROCEDURE P_TEST', List[0]) = 1);
    AssertEquals('SELECT 2 FROM RDB$DATABASE', List[1]);
  finally
    List.Free;
  end;
end;

procedure TTestSqlScriptUtils.TestSplitPostgresDollarQuote;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    SplitSqlScriptStatements(
      'CREATE FUNCTION f() RETURNS int AS $$ BEGIN RETURN 1; END; $$ LANGUAGE plpgsql;' + LineEnding +
      'SELECT 1;',
      dtPostgreSQL,
      List
    );
    AssertEquals(2, List.Count);
    AssertTrue(Pos('CREATE FUNCTION f()', List[0]) = 1);
    AssertEquals('SELECT 1', List[1]);
  finally
    List.Free;
  end;
end;

procedure TTestSqlScriptUtils.TestNormalizeCodeText;
begin
  AssertEquals('SELECT 1 FROM T', NormalizeCodeText('  SELECT   1' + LineEnding + '  FROM   T ; ', True));
end;

initialization
  RegisterTest(TTestSqlScriptUtils);

end.
