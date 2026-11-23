unit Domain.ExplainPlanParser;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Generics.Collections, fpjson, jsonparser,
  Domain.DatabaseTypes;

type
  TExplainPlanNode = class;
  TExplainPlanNodeList = specialize TObjectList<TExplainPlanNode>;

  TExplainPlanNode = class
  public
    NodeType: string;
    RelationName: string;
    IndexName: string;
    StartupCost: Double;
    TotalCost: Double;
    PlanRows: Int64;
    ActualTimeMs: Double;
    ActualRows: Int64;
    IsFullScan: Boolean;
    HasMemoryBottleneck: Boolean;
    ExtraInfo: string;
    Children: TExplainPlanNodeList;
    constructor Create;
    destructor Destroy; override;
    function DisplayText(const ARootCost: Double): string;
  end;

  TExplainPlanSummary = record
    RootCost: Double;
    TotalTimeMs: Double;
    FullScanCount: Integer;
    IndexScanCount: Integer;
    MemoryBottleneckCount: Integer;
    RawPlanText: string;
  end;

  TExplainPlanParser = class
  public
    class function ParsePostgresJson(const AJsonText: string; out ASummary: TExplainPlanSummary): TExplainPlanNode;
    class function ParseMariaDbJson(const AJsonText: string; out ASummary: TExplainPlanSummary): TExplainPlanNode;
    class function ParseFirebirdPlan(const APlanText: string; out ASummary: TExplainPlanSummary): TExplainPlanNode;
  end;

implementation

constructor TExplainPlanNode.Create;
begin
  inherited Create;
  Children := TExplainPlanNodeList.Create(True);
end;

destructor TExplainPlanNode.Destroy;
begin
  FreeAndNil(Children);
  inherited Destroy;
end;

function TExplainPlanNode.DisplayText(const ARootCost: Double): string;
var
  Badges, TargetStr, CostStr: string;
  Pct: Double;
begin
  Badges := '';
  if IsFullScan then
    Badges := Badges + '[! FULL SCAN] ';
  if HasMemoryBottleneck then
    Badges := Badges + '[MEM/SORT] ';

  TargetStr := '';
  if RelationName <> '' then
  begin
    TargetStr := ' em ' + RelationName;
    if IndexName <> '' then
      TargetStr := TargetStr + ' (Índice: ' + IndexName + ')';
  end
  else if IndexName <> '' then
    TargetStr := ' (Índice: ' + IndexName + ')';

  CostStr := '';
  if TotalCost > 0 then
  begin
    if ARootCost > 0 then
      Pct := (TotalCost / ARootCost) * 100.0
    else
      Pct := 0;
    CostStr := Format(' | Custo: %.2f (%.0f%%)', [TotalCost, Pct]);
  end;
  if ActualTimeMs > 0 then
    CostStr := CostStr + Format(' | Tempo: %.2f ms', [ActualTimeMs]);
  if ActualRows > 0 then
    CostStr := CostStr + Format(' | Linhas: %d', [ActualRows])
  else if PlanRows > 0 then
    CostStr := CostStr + Format(' | Est. Linhas: %d', [PlanRows]);
  if ExtraInfo <> '' then
    CostStr := CostStr + ' | ' + ExtraInfo;

  Result := Badges + NodeType + TargetStr + CostStr;
end;

procedure CollectStats(const ANode: TExplainPlanNode; var ASummary: TExplainPlanSummary);
var
  Child: TExplainPlanNode;
begin
  if ANode = nil then
    Exit;
  if ANode.IsFullScan then
    Inc(ASummary.FullScanCount);
  if ANode.IndexName <> '' then
    Inc(ASummary.IndexScanCount);
  if ANode.HasMemoryBottleneck then
    Inc(ASummary.MemoryBottleneckCount);
  for Child in ANode.Children do
    CollectStats(Child, ASummary);
end;

function ParsePgNode(const AObj: TJSONObject): TExplainPlanNode;
var
  PlansArr: TJSONArray;
  I: Integer;
  TempWritten, LocalWritten: Int64;
begin
  Result := TExplainPlanNode.Create;
  Result.NodeType := AObj.Get('Node Type', 'Node');
  Result.RelationName := AObj.Get('Relation Name', '');
  Result.IndexName := AObj.Get('Index Name', '');
  Result.StartupCost := AObj.Get('Startup Cost', 0.0);
  Result.TotalCost := AObj.Get('Total Cost', 0.0);
  Result.PlanRows := AObj.Get('Plan Rows', Int64(0));
  Result.ActualTimeMs := AObj.Get('Actual Total Time', 0.0);
  Result.ActualRows := AObj.Get('Actual Rows', Int64(0));

  Result.IsFullScan := SameText(Result.NodeType, 'Seq Scan');
  TempWritten := AObj.Get('Temp Written Blocks', Int64(0));
  LocalWritten := AObj.Get('Local Written Blocks', Int64(0));
  Result.HasMemoryBottleneck :=
    (TempWritten > 0) or (LocalWritten > 0) or
    (Pos('Sort', Result.NodeType) > 0) or
    (Pos('Hash', Result.NodeType) > 0) or
    (Pos('Materialize', Result.NodeType) > 0);

  if TempWritten > 0 then
    Result.ExtraInfo := Format('Temp Blocks: %d', [TempWritten]);

  if AObj.Find('Plans', PlansArr) then
  begin
    for I := 0 to PlansArr.Count - 1 do
      if PlansArr.Items[I] is TJSONObject then
        Result.Children.Add(ParsePgNode(TJSONObject(PlansArr.Items[I])));
  end;
end;

class function TExplainPlanParser.ParsePostgresJson(const AJsonText: string; out ASummary: TExplainPlanSummary): TExplainPlanNode;
var
  Data: TJSONData;
  Arr: TJSONArray;
  RootObj, PlanObj: TJSONObject;
begin
  Result := nil;
  ASummary := Default(TExplainPlanSummary);
  ASummary.RawPlanText := AJsonText;
  if Trim(AJsonText) = '' then
    Exit;

  Data := GetJSON(AJsonText);
  try
    if (Data is TJSONArray) and (TJSONArray(Data).Count > 0) then
    begin
      Arr := TJSONArray(Data);
      if Arr.Items[0] is TJSONObject then
      begin
        RootObj := TJSONObject(Arr.Items[0]);
        ASummary.TotalTimeMs := RootObj.Get('Execution Time', 0.0);
        if RootObj.Find('Plan', PlanObj) then
        begin
          Result := ParsePgNode(PlanObj);
          ASummary.RootCost := Result.TotalCost;
          CollectStats(Result, ASummary);
        end;
      end;
    end;
  finally
    Data.Free;
  end;
end;

procedure ParseMariaNodeFromObject(const AObj: TJSONObject; const AParent: TExplainPlanNode);
var
  TableObj, NestedArr, QBlockObj: TJSONObject;
  Arr: TJSONArray;
  Node: TExplainPlanNode;
  I: Integer;
  AccessType: string;
begin
  if AObj.Find('query_block', QBlockObj) then
  begin
    Node := TExplainPlanNode.Create;
    Node.NodeType := 'Query Block';
    Node.TotalCost := QBlockObj.Get('cost', 0.0);
    AParent.Children.Add(Node);
    ParseMariaNodeFromObject(QBlockObj, Node);
    Exit;
  end;

  if AObj.Find('table', TableObj) then
  begin
    Node := TExplainPlanNode.Create;
    AccessType := TableObj.Get('access_type', 'SCAN');
    Node.NodeType := 'Table Access (' + AccessType + ')';
    Node.RelationName := TableObj.Get('table_name', '');
    Node.IndexName := TableObj.Get('key', '');
    Node.PlanRows := TableObj.Get('rows', Int64(0));
    Node.TotalCost := TableObj.Get('cost', 0.0);
    Node.IsFullScan := SameText(AccessType, 'ALL');
    Node.HasMemoryBottleneck := TableObj.Get('using_temporary_table', False) or TableObj.Get('using_filesort', False);
    if TableObj.Get('using_filesort', False) then
      Node.ExtraInfo := 'Using filesort';
    if TableObj.Get('using_temporary_table', False) then
    begin
      if Node.ExtraInfo <> '' then
        Node.ExtraInfo := Node.ExtraInfo + ', ';
      Node.ExtraInfo := Node.ExtraInfo + 'Using temporary';
    end;
    AParent.Children.Add(Node);
  end;

  if AObj.Find('nested_loop', Arr) then
  begin
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
        ParseMariaNodeFromObject(TJSONObject(Arr.Items[I]), AParent);
  end;

  if AObj.Find('filesort', NestedArr) then
  begin
    Node := TExplainPlanNode.Create;
    Node.NodeType := 'Filesort';
    Node.HasMemoryBottleneck := True;
    AParent.Children.Add(Node);
    ParseMariaNodeFromObject(NestedArr, Node);
  end;

  if AObj.Find('temporary_table', NestedArr) then
  begin
    Node := TExplainPlanNode.Create;
    Node.NodeType := 'Temporary Table';
    Node.HasMemoryBottleneck := True;
    AParent.Children.Add(Node);
    ParseMariaNodeFromObject(NestedArr, Node);
  end;
end;

class function TExplainPlanParser.ParseMariaDbJson(const AJsonText: string; out ASummary: TExplainPlanSummary): TExplainPlanNode;
var
  Data: TJSONData;
begin
  Result := nil;
  ASummary := Default(TExplainPlanSummary);
  ASummary.RawPlanText := AJsonText;
  if Trim(AJsonText) = '' then
    Exit;

  Data := GetJSON(AJsonText);
  try
    if Data is TJSONObject then
    begin
      Result := TExplainPlanNode.Create;
      Result.NodeType := 'Plano MariaDB';
      ParseMariaNodeFromObject(TJSONObject(Data), Result);
      if Result.Children.Count > 0 then
        Result.TotalCost := Result.Children[0].TotalCost;
      ASummary.RootCost := Result.TotalCost;
      CollectStats(Result, ASummary);
    end;
  finally
    Data.Free;
  end;
end;

class function TExplainPlanParser.ParseFirebirdPlan(const APlanText: string; out ASummary: TExplainPlanSummary): TExplainPlanNode;
var
  SL: TStringList;
  I: Integer;
  Line, UpperLine: string;
  Node: TExplainPlanNode;
  P1, P2: Integer;
begin
  Result := nil;
  ASummary := Default(TExplainPlanSummary);
  ASummary.RawPlanText := APlanText;
  if Trim(APlanText) = '' then
    Exit;

  Result := TExplainPlanNode.Create;
  Result.NodeType := 'Plano de Execução Firebird';

  SL := TStringList.Create;
  try
    SL.Text := APlanText;
    for I := 0 to SL.Count - 1 do
    begin
      Line := Trim(SL[I]);
      if Line = '' then
        Continue;
      UpperLine := UpperCase(Line);
      Node := TExplainPlanNode.Create;
      Node.NodeType := Line;
      Node.IsFullScan := Pos('NATURAL', UpperLine) > 0;
      Node.HasMemoryBottleneck := (Pos('SORT', UpperLine) > 0) or (Pos('HASH', UpperLine) > 0);
      P1 := Pos('INDEX (', UpperLine);
      if P1 > 0 then
      begin
        P2 := Pos(')', Copy(Line, P1 + 7, MaxInt));
        if P2 > 0 then
          Node.IndexName := Trim(Copy(Line, P1 + 7, P2 - 1));
      end;
      Result.Children.Add(Node);
    end;
  finally
    SL.Free;
  end;
  CollectStats(Result, ASummary);
end;

end.
