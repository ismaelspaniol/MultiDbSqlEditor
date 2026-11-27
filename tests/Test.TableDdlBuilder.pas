unit Test.TableDdlBuilder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.DatabaseTypes,
  Domain.TableStructureTypes,
  Domain.TableDdlBuilder;

type
  TTestTableDdlBuilder = class(TTestCase)
  published
    procedure TestQuoteDbIdent;
    procedure TestBuildAddAndDropColumnDDL;
    procedure TestBuildEditColumnDDLFirebird;
    procedure TestBuildCreateIndexDDL;
    procedure TestBuildFirebirdTriggerDDL;
  end;

implementation

procedure TTestTableDdlBuilder.TestQuoteDbIdent;
begin
  AssertEquals('CLIENTES', QuoteDbIdent(dtFirebird, 'CLIENTES'));
  AssertEquals('"Clientes"', QuoteDbIdent(dtFirebird, 'Clientes'));
  AssertEquals('"clientes"', QuoteDbIdent(dtPostgreSQL, 'clientes'));
  AssertEquals('`clientes`', QuoteDbIdent(dtMariaDB, 'clientes'));
end;

procedure TTestTableDdlBuilder.TestBuildAddAndDropColumnDDL;
begin
  AssertEquals(
    'ALTER TABLE CLIENTES ADD ATIVO SMALLINT DEFAULT 1 NOT NULL',
    BuildAddColumnDDL(dtFirebird, 'CLIENTES', 'ATIVO', 'SMALLINT', 'DEFAULT 1', True)
  );
  AssertEquals(
    'ALTER TABLE "clientes" DROP "ativo"',
    BuildDropColumnDDL(dtPostgreSQL, 'clientes', 'ativo')
  );
end;

procedure TTestTableDdlBuilder.TestBuildEditColumnDDLFirebird;
var
  OldCol: TTableColumnInfo;
  Stmts: TStringList;
begin
  OldCol := Default(TTableColumnInfo);
  OldCol.ColumnName := 'NOME';
  OldCol.DataType := 'VARCHAR(50)';
  OldCol.DefaultValue := '';
  OldCol.NotNull := False;

  Stmts := TStringList.Create;
  try
    BuildEditColumnDDL(dtFirebird, 'CLIENTES', OldCol, 'NOME_RAZAO', 'VARCHAR(100)', '''N/A''', True, False, Stmts);
    AssertEquals(4, Stmts.Count);
    AssertEquals('ALTER TABLE CLIENTES ALTER COLUMN NOME TO NOME_RAZAO', Stmts[0]);
    AssertEquals('ALTER TABLE CLIENTES ALTER COLUMN NOME_RAZAO TYPE VARCHAR(100)', Stmts[1]);
    AssertEquals('ALTER TABLE CLIENTES ALTER COLUMN NOME_RAZAO SET DEFAULT ''N/A''', Stmts[2]);
    AssertEquals('ALTER TABLE CLIENTES ALTER COLUMN NOME_RAZAO SET NOT NULL', Stmts[3]);
  finally
    Stmts.Free;
  end;
end;

procedure TTestTableDdlBuilder.TestBuildCreateIndexDDL;
var
  Cols: TStringList;
begin
  Cols := TStringList.Create;
  try
    Cols.Add('NOME');
    Cols.Add('CODIGO');
    AssertEquals(
      'CREATE UNIQUE DESCENDING INDEX IDX_CLIENTES_NOME ON CLIENTES (NOME, CODIGO)',
      BuildCreateIndexDDL(dtFirebird, 'CLIENTES', 'IDX_CLIENTES_NOME', Cols, True, True)
    );
  finally
    Cols.Free;
  end;
end;

procedure TTestTableDdlBuilder.TestBuildFirebirdTriggerDDL;
var
  DDL: string;
begin
  DDL := BuildFirebirdTriggerDDL('CLIENTES', 'TRG_CLI_BI', 'BEFORE', True, False, False, True, 0, 'BEGIN NEW.ID = 1; END');
  AssertTrue(Pos('CREATE OR ALTER TRIGGER TRG_CLI_BI FOR CLIENTES', DDL) > 0);
  AssertTrue(Pos('ACTIVE BEFORE INSERT POSITION 0', DDL) > 0);
  AssertTrue(Pos('AS' + LineEnding + 'BEGIN NEW.ID = 1; END', DDL) > 0);
end;

initialization
  RegisterTest(TTestTableDdlBuilder);

end.
