program MultiDbSqlEditorTests;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  SysUtils,
  consoletestrunner,
  Test.AppVersion,
  Test.TableDdlBuilder,
  Test.SqlScriptUtils,
  Test.SqlAliasResolver,
  Test.SqlBeautifier,
  Test.ExplainPlanParser,
  Test.ConnectionProfile,
  Test.AppLogger;

type
  TMultiDbTestRunner = class(TTestRunner)
  protected
    procedure AppendLongOpts; override;
  end;

procedure TMultiDbTestRunner.AppendLongOpts;
begin
  inherited AppendLongOpts;
end;

var
  Application: TMultiDbTestRunner;
begin
  Application := TMultiDbTestRunner.Create(nil);
  Application.Initialize;
  Application.Title := 'MultiDbSqlEditor Unit Tests';
  Application.Run;
  Application.Free;
end.
