unit Test.ExplainPlanParser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.ExplainPlanParser;

type
  TTestExplainPlanParser = class(TTestCase)
  published
    procedure TestParseFirebirdPlan;
    procedure TestParsePostgresJson;
  end;

implementation

procedure TTestExplainPlanParser.TestParseFirebirdPlan;
var
  Root: TExplainPlanNode;
  Summary: TExplainPlanSummary;
begin
  Root := TExplainPlanParser.ParseFirebirdPlan('PLAN (CLIENTES NATURAL)', Summary);
  try
    AssertNotNull(Root);
    AssertTrue(Summary.FullScanCount >= 1);
  finally
    Root.Free;
  end;
end;

procedure TTestExplainPlanParser.TestParsePostgresJson;
const
  PgJson = '[{"Plan": {"Node Type": "Seq Scan", "Relation Name": "clientes", "Startup Cost": 0.0, "Total Cost": 15.5, "Plan Rows": 100}}]';
var
  Root: TExplainPlanNode;
  Summary: TExplainPlanSummary;
begin
  Root := TExplainPlanParser.ParsePostgresJson(PgJson, Summary);
  try
    AssertNotNull(Root);
    AssertEquals(1, Summary.FullScanCount);
    AssertTrue(Summary.RootCost > 15.0);
  finally
    Root.Free;
  end;
end;

initialization
  RegisterTest(TTestExplainPlanParser);

end.
