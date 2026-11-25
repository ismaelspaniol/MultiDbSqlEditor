unit Domain.PsqlDebugger;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Variants, StrUtils, Math, DateUtils,
  Domain.DatabaseTypes,
  Domain.QueryResult;

type
  TDebugVarScope = (dvsInput, dvsOutput, dvsLocal, dvsSystem, dvsNew, dvsOld);

  TDebugVariable = class
  public
    Name: string;
    Scope: TDebugVarScope;
    DataType: string;
    InitExpr: string;
    IsNull: Boolean;
    Value: string;
    LastChangedStep: Integer;
  end;

  TDebugFieldEntry = record
    FieldName: string;
    IsNull: Boolean;
    Value: string;
  end;
  TDebugFieldArray = array of TDebugFieldEntry;

  TDebugParamDecl = record
    Name: string;
    DataType: string;
    IsInput: Boolean;
    IsOutput: Boolean;
    IsNull: Boolean;
    Value: string;
  end;
  TDebugParamDeclArray = array of TDebugParamDecl;

  TDebugSqlExecEvent = function(
    const ASQL: string;
    out AError: string
  ): TQueryResult of object;

  TDebugLogEvent = procedure(const AMsg: string) of object;

  TPsqlTokenKind = (
    ptkIdent,
    ptkNumber,
    ptkString,
    ptkSymbol,
    ptkEOF
  );

  TPsqlToken = record
    Kind: TPsqlTokenKind;
    Text: string;
    UpperText: string;
    Line: Integer;
    Col: Integer;
  end;
  TPsqlTokenArray = array of TPsqlToken;

  TPsqlStmtKind = (
    pskBlock,
    pskAssign,
    pskIf,
    pskWhile,
    pskForSelect,
    pskForExecStmt,
    pskSelectInto,
    pskSuspend,
    pskExit,
    pskBreak,
    pskPostEvent,
    pskException,
    pskSql,
    pskEmpty
  );

  TPsqlStmt = class
  public
    Kind: TPsqlStmtKind;
    Line: Integer;
    EndLine: Integer;
    TargetVar: string;
    ExprText: string;
    SqlText: string;
    IntoVars: array of string;
    Body: TPsqlStmt;
    ElseBody: TPsqlStmt;
    Children: array of TPsqlStmt;
    destructor Destroy; override;
  end;

  TDebugExecFrameKind = (
    dfkBlock,
    dfkWhile,
    dfkForSelect,
    dfkForExecStmt
  );

  TDebugExecFrame = class
  public
    Kind: TDebugExecFrameKind;
    Stmt: TPsqlStmt;
    ChildIndex: Integer;
    CursorResult: TQueryResult;
    CursorRowIndex: Integer;
    ConditionChecked: Boolean;
    destructor Destroy; override;
  end;

  TDebugState = (
    dsIdle,
    dsPaused,
    dsFinished,
    dsError
  );

  { Interpretador / Debugger passo-a-passo de Procedures Firebird (PSQL) }
  TPsqlDebugger = class
  private
    FTokens: TPsqlTokenArray;
    FTokIdx: Integer;
    FRootStmt: TPsqlStmt;
    FVars: TList;
    FStack: TList;
    FBreakpoints: TStringList;
    FCursorFields: TDebugFieldArray;
    FSuspendedRows: array of array of string;
    FOutputColNames: array of string;
    FState: TDebugState;
    FCurrentLine: Integer;
    FStepCount: Integer;
    FLastError: string;
    FStopRequested: Boolean;
    FOnExecSql: TDebugSqlExecEvent;
    FOnLog: TDebugLogEvent;
    FOnYield: TNotifyEvent;

    procedure ClearVars;
    procedure ClearStack;
    procedure ClearSuspendedRows;
    procedure Log(const AMsg: string);

    function FindVar(const AName: string): TDebugVariable;
    function EnsureVar(const AName: string; const AScope: TDebugVarScope; const ADataType: string): TDebugVariable;
    procedure SetVarValue(const AName: string; const AIsNull: Boolean; const AValue: string);
    function GetVarValue(const AName: string; out AIsNull: Boolean; out AValue: string): Boolean;

    procedure Tokenize(const ASource: string);
    function PeekTok(const AOffset: Integer = 0): TPsqlToken;
    function NextTok: TPsqlToken;
    function MatchUpper(const AUpper: string): Boolean;
    function MatchSymbol(const ASym: string): Boolean;
    procedure SkipSemicolons;

    procedure ParseHeaderAndDecls(const AParams: TDebugParamDeclArray);
    procedure ParseDeclareVariable;
    function ParseStatement: TPsqlStmt;
    function ParseBlock: TPsqlStmt;
    function ParseIf: TPsqlStmt;
    function ParseWhile: TPsqlStmt;
    function ParseFor: TPsqlStmt;
    function ParseSelectIntoOrSql(const AStartLine: Integer): TPsqlStmt;
    function ParseExecProcOrDml(const AStartLine: Integer): TPsqlStmt;
    function CollectTokensUntil(const AStopUpper1, AStopUpper2: string; const AStopSym: string;
      const AIncludeParenDepthZeroOnly: Boolean; out AEndLine: Integer): string;

    function SubstituteSqlVars(const ASQL: string): string;
    function FormatSqlLiteral(const AIsNull: Boolean; const AValue, ADataType: string): string;

    function EvalExpression(const AExpr: string; out AIsNull: Boolean; out AValue: string): Boolean;
    function EvalCondition(const AExpr: string): Boolean;
    function EvalViaDatabase(const AExpr: string; out AIsNull: Boolean; out AValue: string): Boolean;

    procedure PushFrame(const AKind: TDebugExecFrameKind; const AStmt: TPsqlStmt);
    procedure PopFrame;
    function CurrentFrame: TDebugExecFrame;
    function AdvanceToNextExecutable(out AExecutedAction: Boolean): Boolean;
    function ExecuteAtomicStmt(const AStmt: TPsqlStmt): Boolean;
    procedure UpdateCurrentLineFromTopFrame;
    procedure CaptureCursorFields(const ARes: TQueryResult; const ARowIdx: Integer; const AStmt: TPsqlStmt);
    procedure RecordSuspendedRow;
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadProcedure(
      const ADDL: string;
      const AParams: TDebugParamDeclArray
    );
    procedure LoadTrigger(
      const ADDL: string;
      const AEvent: string;
      const AOldFields, ANewFields: TDebugParamDeclArray
    );
    procedure Start;
    procedure StepInto;
    procedure StepOver;
    procedure Run;
    procedure RunToLine(const ATargetLine: Integer);
    procedure RequestStop;
    procedure Stop;

    procedure ToggleBreakpoint(const ALine: Integer);
    function HasBreakpoint(const ALine: Integer): Boolean;
    procedure ClearBreakpoints;

    function VarCount: Integer;
    function GetVar(const AIndex: Integer): TDebugVariable;
    function CursorFieldCount: Integer;
    function GetCursorField(const AIndex: Integer): TDebugFieldEntry;

    function OutputColCount: Integer;
    function GetOutputColName(const AIndex: Integer): string;
    function SuspendedRowCount: Integer;
    function GetSuspendedCell(const ARow, ACol: Integer): string;

    property State: TDebugState read FState;
    property CurrentLine: Integer read FCurrentLine;
    property StepCount: Integer read FStepCount;
    property LastError: string read FLastError;
    property OnExecSql: TDebugSqlExecEvent read FOnExecSql write FOnExecSql;
    property OnLog: TDebugLogEvent read FOnLog write FOnLog;
    property OnYield: TNotifyEvent read FOnYield write FOnYield;
  end;

implementation

function IsIdentStartChar(const C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '_', '$']);
end;

function IsIdentChar(const C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']);
end;

function TryParseFloatInv(const S: string; out V: Double): Boolean;
var
  FS: TFormatSettings;
  Clean: string;
begin
  Clean := Trim(S);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := TryStrToFloat(Clean, V, FS);
  if (not Result) and (Pos('.', Clean) = 0) and (Pos(',', Clean) > 0) then
  begin
    FS.DecimalSeparator := ',';
    Result := TryStrToFloat(Clean, V, FS);
  end;
end;

function FloatToStrInv(const V: Double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FloatToStr(V, FS);
end;

{ TPsqlStmt }

destructor TPsqlStmt.Destroy;
var
  I: Integer;
begin
  FreeAndNil(Body);
  FreeAndNil(ElseBody);
  for I := 0 to High(Children) do
    Children[I].Free;
  SetLength(Children, 0);
  inherited Destroy;
end;

{ TDebugExecFrame }

destructor TDebugExecFrame.Destroy;
begin
  FreeAndNil(CursorResult);
  inherited Destroy;
end;

{ TPsqlDebugger }

constructor TPsqlDebugger.Create;
begin
  inherited Create;
  FVars := TList.Create;
  FStack := TList.Create;
  FBreakpoints := TStringList.Create;
  FBreakpoints.Sorted := True;
  FBreakpoints.Duplicates := dupIgnore;
  FState := dsIdle;
  FCurrentLine := 0;
  FStepCount := 0;
end;

destructor TPsqlDebugger.Destroy;
begin
  ClearStack;
  ClearVars;
  FreeAndNil(FRootStmt);
  FreeAndNil(FStack);
  FreeAndNil(FVars);
  FreeAndNil(FBreakpoints);
  inherited Destroy;
end;

procedure TPsqlDebugger.ClearVars;
var
  I: Integer;
begin
  for I := 0 to FVars.Count - 1 do
    TObject(FVars[I]).Free;
  FVars.Clear;
  SetLength(FCursorFields, 0);
end;

procedure TPsqlDebugger.ClearStack;
var
  I: Integer;
begin
  for I := 0 to FStack.Count - 1 do
    TObject(FStack[I]).Free;
  FStack.Clear;
end;

procedure TPsqlDebugger.ClearSuspendedRows;
begin
  SetLength(FSuspendedRows, 0);
end;

procedure TPsqlDebugger.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

function TPsqlDebugger.FindVar(const AName: string): TDebugVariable;
var
  I: Integer;
  Clean: string;
begin
  Clean := Trim(AName);
  if (Clean <> '') and (Clean[1] = ':') then
    Delete(Clean, 1, 1);
  for I := 0 to FVars.Count - 1 do
  begin
    if SameText(TDebugVariable(FVars[I]).Name, Clean) then
      Exit(TDebugVariable(FVars[I]));
  end;
  Result := nil;
end;

function TPsqlDebugger.EnsureVar(
  const AName: string;
  const AScope: TDebugVarScope;
  const ADataType: string
): TDebugVariable;
var
  Clean: string;
begin
  Clean := Trim(AName);
  if (Clean <> '') and (Clean[1] = ':') then
    Delete(Clean, 1, 1);
  Result := FindVar(Clean);
  if Result = nil then
  begin
    Result := TDebugVariable.Create;
    Result.Name := Clean;
    Result.Scope := AScope;
    Result.DataType := ADataType;
    Result.IsNull := True;
    Result.Value := '';
    Result.LastChangedStep := -1;
    FVars.Add(Result);
  end
  else if Trim(ADataType) <> '' then
    Result.DataType := ADataType;
end;

procedure TPsqlDebugger.SetVarValue(const AName: string; const AIsNull: Boolean; const AValue: string);
var
  V: TDebugVariable;
begin
  V := FindVar(AName);
  if V = nil then
    V := EnsureVar(AName, dvsLocal, '');
  if (V.IsNull <> AIsNull) or (V.Value <> AValue) then
    V.LastChangedStep := FStepCount;
  V.IsNull := AIsNull;
  V.Value := AValue;
end;

function TPsqlDebugger.GetVarValue(const AName: string; out AIsNull: Boolean; out AValue: string): Boolean;
var
  V: TDebugVariable;
  Clean: string;
begin
  Clean := Trim(AName);
  if (Clean <> '') and (Clean[1] = ':') then
    Delete(Clean, 1, 1);

  if SameText(Clean, 'CURRENT_DATE') then
  begin
    AIsNull := False;
    AValue := FormatDateTime('yyyy-mm-dd', Date);
    Exit(True);
  end;
  if SameText(Clean, 'CURRENT_TIME') then
  begin
    AIsNull := False;
    AValue := FormatDateTime('hh:nn:ss', Time);
    Exit(True);
  end;
  if SameText(Clean, 'CURRENT_TIMESTAMP') or SameText(Clean, 'NOW') then
  begin
    AIsNull := False;
    AValue := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    Exit(True);
  end;

  V := FindVar(Clean);
  if V = nil then
  begin
    AIsNull := True;
    AValue := '';
    Exit(False);
  end;
  AIsNull := V.IsNull;
  AValue := V.Value;
  Result := True;
end;

procedure TPsqlDebugger.Tokenize(const ASource: string);
var
  I, Len, Line, Col, StartIdx, StartCol, StartLine: Integer;
  Count, Cap: Integer;
  S: string;

  procedure AddTok(const AKind: TPsqlTokenKind; const AText: string; const ALine, ACol: Integer);
  begin
    if Count >= Cap then
    begin
      if Cap = 0 then Cap := 128 else Cap := Cap * 2;
      SetLength(FTokens, Cap);
    end;
    FTokens[Count].Kind := AKind;
    FTokens[Count].Text := AText;
    FTokens[Count].UpperText := UpperCase(AText);
    FTokens[Count].Line := ALine;
    FTokens[Count].Col := ACol;
    Inc(Count);
  end;

begin
  SetLength(FTokens, 0);
  Count := 0;
  Cap := 0;
  I := 1;
  Len := Length(ASource);
  Line := 1;
  Col := 1;

  while I <= Len do
  begin
    if ASource[I] = #13 then
    begin
      if (I < Len) and (ASource[I + 1] = #10) then
        Inc(I);
      Inc(Line);
      Col := 1;
      Inc(I);
      Continue;
    end;
    if ASource[I] = #10 then
    begin
      Inc(Line);
      Col := 1;
      Inc(I);
      Continue;
    end;
    if ASource[I] in [' ', #9] then
    begin
      Inc(Col);
      Inc(I);
      Continue;
    end;

    { Single-line comment -- }
    if (ASource[I] = '-') and (I < Len) and (ASource[I + 1] = '-') then
    begin
      while (I <= Len) and not (ASource[I] in [#10, #13]) do
        Inc(I);
      Continue;
    end;

    { Multi-line comment /* ... */ }
    if (ASource[I] = '/') and (I < Len) and (ASource[I + 1] = '*') then
    begin
      Inc(I, 2);
      Inc(Col, 2);
      while I <= Len do
      begin
        if (ASource[I] = '*') and (I < Len) and (ASource[I + 1] = '/') then
        begin
          Inc(I, 2);
          Inc(Col, 2);
          Break;
        end;
        if ASource[I] = #13 then
        begin
          if (I < Len) and (ASource[I + 1] = #10) then Inc(I);
          Inc(Line);
          Col := 1;
        end
        else if ASource[I] = #10 then
        begin
          Inc(Line);
          Col := 1;
        end
        else
          Inc(Col);
        Inc(I);
      end;
      Continue;
    end;

    { String literal '...' }
    if ASource[I] = '''' then
    begin
      StartLine := Line;
      StartCol := Col;
      S := '';
      Inc(I);
      Inc(Col);
      while I <= Len do
      begin
        if ASource[I] = '''' then
        begin
          if (I < Len) and (ASource[I + 1] = '''') then
          begin
            S := S + '''';
            Inc(I, 2);
            Inc(Col, 2);
            Continue;
          end
          else
          begin
            Inc(I);
            Inc(Col);
            Break;
          end;
        end;
        if ASource[I] = #13 then
        begin
          if (I < Len) and (ASource[I + 1] = #10) then Inc(I);
          S := S + #10;
          Inc(Line);
          Col := 1;
        end
        else if ASource[I] = #10 then
        begin
          S := S + #10;
          Inc(Line);
          Col := 1;
        end
        else
        begin
          S := S + ASource[I];
          Inc(Col);
        end;
        Inc(I);
      end;
      AddTok(ptkString, S, StartLine, StartCol);
      Continue;
    end;

    { Double-quoted identifier "..." }
    if ASource[I] = '"' then
    begin
      StartCol := Col;
      StartIdx := I;
      Inc(I);
      Inc(Col);
      while (I <= Len) and (ASource[I] <> '"') do
      begin
        Inc(I);
        Inc(Col);
      end;
      if I <= Len then
      begin
        Inc(I);
        Inc(Col);
      end;
      AddTok(ptkIdent, Copy(ASource, StartIdx, I - StartIdx), Line, StartCol);
      Continue;
    end;

    { Number literal }
    if ASource[I] in ['0'..'9'] then
    begin
      StartCol := Col;
      StartIdx := I;
      while (I <= Len) and (ASource[I] in ['0'..'9']) do
      begin
        Inc(I);
        Inc(Col);
      end;
      if (I < Len) and (ASource[I] = '.') and (ASource[I + 1] in ['0'..'9']) then
      begin
        Inc(I);
        Inc(Col);
        while (I <= Len) and (ASource[I] in ['0'..'9']) do
        begin
          Inc(I);
          Inc(Col);
        end;
      end;
      AddTok(ptkNumber, Copy(ASource, StartIdx, I - StartIdx), Line, StartCol);
      Continue;
    end;

    { Identifier }
    if IsIdentStartChar(ASource[I]) then
    begin
      StartCol := Col;
      StartIdx := I;
      while (I <= Len) and IsIdentChar(ASource[I]) do
      begin
        Inc(I);
        Inc(Col);
      end;
      AddTok(ptkIdent, Copy(ASource, StartIdx, I - StartIdx), Line, StartCol);
      Continue;
    end;

    { Two-char symbols }
    StartCol := Col;
    if (I < Len) and (
       ((ASource[I] = '<') and (ASource[I + 1] in ['>', '='])) or
       ((ASource[I] = '>') and (ASource[I + 1] = '=')) or
       ((ASource[I] = '!') and (ASource[I + 1] = '=')) or
       ((ASource[I] = '|') and (ASource[I + 1] = '|')) or
       ((ASource[I] = ':') and (ASource[I + 1] = '='))
    ) then
    begin
      AddTok(ptkSymbol, ASource[I] + ASource[I + 1], Line, StartCol);
      Inc(I, 2);
      Inc(Col, 2);
      Continue;
    end;

    { Single-char symbol }
    AddTok(ptkSymbol, ASource[I], Line, StartCol);
    Inc(I);
    Inc(Col);
  end;

  { Ensure final EOF token }
  AddTok(ptkEOF, '', Line, Col);
  SetLength(FTokens, Count);
end;

function TPsqlDebugger.PeekTok(const AOffset: Integer): TPsqlToken;
var
  Idx: Integer;
begin
  Idx := FTokIdx + AOffset;
  if (Idx < 0) or (Idx >= Length(FTokens)) then
    Exit(FTokens[High(FTokens)]);
  Result := FTokens[Idx];
end;

function TPsqlDebugger.NextTok: TPsqlToken;
begin
  Result := PeekTok(0);
  if FTokIdx < High(FTokens) then
    Inc(FTokIdx);
end;

function TPsqlDebugger.MatchUpper(const AUpper: string): Boolean;
begin
  Result := (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = AUpper);
  if Result then
    NextTok;
end;

function TPsqlDebugger.MatchSymbol(const ASym: string): Boolean;
begin
  Result := (PeekTok.Kind = ptkSymbol) and (PeekTok.Text = ASym);
  if Result then
    NextTok;
end;

procedure TPsqlDebugger.SkipSemicolons;
begin
  while MatchSymbol(';') do ;
end;

function TPsqlDebugger.CollectTokensUntil(
  const AStopUpper1, AStopUpper2: string;
  const AStopSym: string;
  const AIncludeParenDepthZeroOnly: Boolean;
  out AEndLine: Integer
): string;
var
  Depth: Integer;
  T: TPsqlToken;
  Piece: string;
begin
  Result := '';
  Depth := 0;
  AEndLine := PeekTok.Line;

  while PeekTok.Kind <> ptkEOF do
  begin
    T := PeekTok;
    if (not AIncludeParenDepthZeroOnly) or (Depth = 0) then
    begin
      if (AStopSym <> '') and (T.Kind = ptkSymbol) and (T.Text = AStopSym) then
        Break;
      if (AStopUpper1 <> '') and (T.Kind = ptkIdent) and (T.UpperText = AStopUpper1) then
        Break;
      if (AStopUpper2 <> '') and (T.Kind = ptkIdent) and (T.UpperText = AStopUpper2) then
        Break;
    end;

    NextTok;
    AEndLine := T.Line;
    if T.Kind = ptkSymbol then
    begin
      if T.Text = '(' then Inc(Depth)
      else if (T.Text = ')') and (Depth > 0) then Dec(Depth);
    end;

    if T.Kind = ptkString then
      Piece := '''' + StringReplace(T.Text, '''', '''''', [rfReplaceAll]) + ''''
    else
      Piece := T.Text;

    if Result = '' then
      Result := Piece
    else if (T.Kind = ptkSymbol) and ((T.Text = ',') or (T.Text = ';') or (T.Text = '.') or (T.Text = ')')) then
      Result := Result + Piece
    else if (Copy(Result, Length(Result), 1) = '(') or
            (Copy(Result, Length(Result), 1) = '.') or
            (Copy(Result, Length(Result), 1) = ':') then
      Result := Result + Piece
    else
      Result := Result + ' ' + Piece;
  end;
  Result := Trim(Result);
end;

procedure TPsqlDebugger.ParseDeclareVariable;
var
  VarName, TypeStr, InitExpr: string;
  ParenDepth, EndLine: Integer;
  V: TDebugVariable;
  IsNull: Boolean;
  Val: string;
begin
  { DECLARE [VARIABLE] <name> <type> [DEFAULT <expr> | = <expr>]; }
  MatchUpper('VARIABLE');
  if PeekTok.Kind <> ptkIdent then
  begin
    CollectTokensUntil('', '', ';', False, EndLine);
    MatchSymbol(';');
    Exit;
  end;

  VarName := NextTok.Text;
  TypeStr := '';
  ParenDepth := 0;
  while PeekTok.Kind <> ptkEOF do
  begin
    if (ParenDepth = 0) and (
       MatchSymbol(';') or
       (PeekTok.Kind = ptkIdent) and ((PeekTok.UpperText = 'DEFAULT') or (PeekTok.UpperText = 'NOT')) or
       ((PeekTok.Kind = ptkSymbol) and (PeekTok.Text = '='))
    ) then
      Break;

    if PeekTok.Text = '(' then Inc(ParenDepth)
    else if (PeekTok.Text = ')') and (ParenDepth > 0) then Dec(ParenDepth);

    if TypeStr = '' then
      TypeStr := NextTok.Text
    else
      TypeStr := TypeStr + ' ' + NextTok.Text;
  end;

  V := EnsureVar(VarName, dvsLocal, Trim(TypeStr));
  InitExpr := '';
  if MatchUpper('DEFAULT') or MatchSymbol('=') then
    InitExpr := CollectTokensUntil('', '', ';', True, EndLine)
  else if PeekTok.UpperText = 'NOT' then
  begin
    { NOT NULL [= expr | DEFAULT expr] }
    NextTok;
    MatchUpper('NULL');
    if MatchUpper('DEFAULT') or MatchSymbol('=') then
      InitExpr := CollectTokensUntil('', '', ';', True, EndLine);
  end;
  MatchSymbol(';');

  if InitExpr <> '' then
    V.InitExpr := InitExpr;
end;

procedure TPsqlDebugger.ParseHeaderAndDecls(const AParams: TDebugParamDeclArray);
var
  I: Integer;
  V: TDebugVariable;
  EndLine: Integer;
begin
  { Initialize system variables }
  V := EnsureVar('ROW_COUNT', dvsSystem, 'INTEGER');
  V.IsNull := False;
  V.Value := '0';
  V := EnsureVar('SQLCODE', dvsSystem, 'INTEGER');
  V.IsNull := False;
  V.Value := '0';

  { Initialize IN/OUT parameters }
  SetLength(FOutputColNames, 0);
  for I := 0 to High(AParams) do
  begin
    if AParams[I].IsInput then
    begin
      V := EnsureVar(AParams[I].Name, dvsInput, AParams[I].DataType);
      V.IsNull := AParams[I].IsNull;
      V.Value := AParams[I].Value;
    end;
    if AParams[I].IsOutput then
    begin
      EnsureVar(AParams[I].Name, dvsOutput, AParams[I].DataType);
      SetLength(FOutputColNames, Length(FOutputColNames) + 1);
      FOutputColNames[High(FOutputColNames)] := AParams[I].Name;
    end;
  end;

  { Advance token stream past header up to AS ... BEGIN }
  while (PeekTok.Kind <> ptkEOF) and (PeekTok.UpperText <> 'AS') do
    NextTok;
  MatchUpper('AS');

  { Parse DECLARE VARIABLE / DECLARE CURSOR before main BEGIN }
  while (PeekTok.Kind <> ptkEOF) and (PeekTok.UpperText <> 'BEGIN') do
  begin
    if MatchUpper('DECLARE') then
    begin
      if PeekTok.UpperText = 'CURSOR' then
      begin
        CollectTokensUntil('', '', ';', False, EndLine);
        MatchSymbol(';');
      end
      else
        ParseDeclareVariable;
    end
    else
      NextTok;
  end;
end;

function TPsqlDebugger.ParseBlock: TPsqlStmt;
var
  Child: TPsqlStmt;
  DummyEndLine: Integer;
begin
  Result := TPsqlStmt.Create;
  Result.Kind := pskBlock;
  Result.Line := PeekTok.Line;
  MatchUpper('BEGIN');

  while (PeekTok.Kind <> ptkEOF) and (PeekTok.UpperText <> 'END') do
  begin
    SkipSemicolons;
    if (PeekTok.Kind = ptkEOF) or (PeekTok.UpperText = 'END') then
      Break;

    { Skip WHEN ... DO error handlers for now after consuming them cleanly }
    if MatchUpper('WHEN') then
    begin
      CollectTokensUntil('DO', '', '', False, DummyEndLine);
      MatchUpper('DO');
      Child := ParseStatement;
      Child.Free;
      Continue;
    end;

    Child := ParseStatement;
    if Child <> nil then
    begin
      SetLength(Result.Children, Length(Result.Children) + 1);
      Result.Children[High(Result.Children)] := Child;
    end;
  end;

  Result.EndLine := PeekTok.Line;
  MatchUpper('END');
  SkipSemicolons;
end;

function TPsqlDebugger.ParseIf: TPsqlStmt;
var
  ParenDepth, EndLine: Integer;
  Cond: string;
begin
  Result := TPsqlStmt.Create;
  Result.Kind := pskIf;
  Result.Line := PeekTok.Line;
  MatchUpper('IF');

  Cond := '';
  ParenDepth := 0;
  while PeekTok.Kind <> ptkEOF do
  begin
    if (ParenDepth = 0) and (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = 'THEN') then
      Break;
    if PeekTok.Text = '(' then Inc(ParenDepth)
    else if (PeekTok.Text = ')') and (ParenDepth > 0) then Dec(ParenDepth);

    if PeekTok.Kind = ptkString then
      Cond := Cond + ' ''' + StringReplace(PeekTok.Text, '''', '''''', [rfReplaceAll]) + ''''
    else if Cond = '' then
      Cond := PeekTok.Text
    else if (PeekTok.Kind = ptkSymbol) and ((PeekTok.Text = ',') or (PeekTok.Text = '.') or (PeekTok.Text = ')')) then
      Cond := Cond + PeekTok.Text
    else if (Copy(Cond, Length(Cond), 1) = '(') or
            (Copy(Cond, Length(Cond), 1) = '.') or
            (Copy(Cond, Length(Cond), 1) = ':') then
      Cond := Cond + PeekTok.Text
    else
      Cond := Cond + ' ' + PeekTok.Text;
    NextTok;
  end;

  Result.ExprText := Trim(Cond);
  EndLine := PeekTok.Line;
  MatchUpper('THEN');
  Result.Body := ParseStatement;
  if MatchUpper('ELSE') then
    Result.ElseBody := ParseStatement;
  Result.EndLine := EndLine;
end;

function TPsqlDebugger.ParseWhile: TPsqlStmt;
var
  ParenDepth: Integer;
  Cond: string;
begin
  Result := TPsqlStmt.Create;
  Result.Kind := pskWhile;
  Result.Line := PeekTok.Line;
  MatchUpper('WHILE');

  Cond := '';
  ParenDepth := 0;
  while PeekTok.Kind <> ptkEOF do
  begin
    if (ParenDepth = 0) and (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = 'DO') then
      Break;
    if PeekTok.Text = '(' then Inc(ParenDepth)
    else if (PeekTok.Text = ')') and (ParenDepth > 0) then Dec(ParenDepth);

    if PeekTok.Kind = ptkString then
      Cond := Cond + ' ''' + StringReplace(PeekTok.Text, '''', '''''', [rfReplaceAll]) + ''''
    else if Cond = '' then
      Cond := PeekTok.Text
    else if (PeekTok.Kind = ptkSymbol) and ((PeekTok.Text = ',') or (PeekTok.Text = '.') or (PeekTok.Text = ')')) then
      Cond := Cond + PeekTok.Text
    else if (Copy(Cond, Length(Cond), 1) = '(') or
            (Copy(Cond, Length(Cond), 1) = '.') or
            (Copy(Cond, Length(Cond), 1) = ':') then
      Cond := Cond + PeekTok.Text
    else
      Cond := Cond + ' ' + PeekTok.Text;
    NextTok;
  end;

  Result.ExprText := Trim(Cond);
  MatchUpper('DO');
  Result.Body := ParseStatement;
  if Result.Body <> nil then
    Result.EndLine := Result.Body.EndLine
  else
    Result.EndLine := Result.Line;
end;

function TPsqlDebugger.ParseFor: TPsqlStmt;
var
  EndLine: Integer;
  FullHeader, VarName: string;
  IntoPos: Integer;
  IsExecStmt: Boolean;
begin
  Result := TPsqlStmt.Create;
  Result.Line := PeekTok.Line;
  MatchUpper('FOR');

  IsExecStmt := (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = 'EXECUTE');
  if IsExecStmt then
  begin
    Result.Kind := pskForExecStmt;
    NextTok; { EXECUTE }
    MatchUpper('STATEMENT');
    Result.ExprText := CollectTokensUntil('INTO', 'DO', '', True, EndLine);
    if MatchUpper('INTO') then
    begin
      while (PeekTok.Kind <> ptkEOF) and (PeekTok.UpperText <> 'DO') do
      begin
        if MatchSymbol(':') or (PeekTok.Kind = ptkIdent) then
        begin
          if PeekTok.Kind = ptkIdent then
          begin
            VarName := NextTok.Text;
            SetLength(Result.IntoVars, Length(Result.IntoVars) + 1);
            Result.IntoVars[High(Result.IntoVars)] := VarName;
          end;
        end
        else
          NextTok;
        MatchSymbol(',');
      end;
    end;
    MatchUpper('DO');
    Result.Body := ParseStatement;
    Exit;
  end;

  Result.Kind := pskForSelect;
  FullHeader := '';
  while (PeekTok.Kind <> ptkEOF) do
  begin
    if (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = 'DO') then
      Break;
    if (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = 'INTO') then
    begin
      NextTok; { INTO }
      while (PeekTok.Kind <> ptkEOF) and (PeekTok.UpperText <> 'DO') and
            (PeekTok.UpperText <> 'AS') do
      begin
        if PeekTok.Kind = ptkSymbol then
        begin
          NextTok;
          Continue;
        end;
        VarName := NextTok.Text;
        if (SameText(VarName, 'NEW') or SameText(VarName, 'OLD')) and
           (PeekTok.Kind = ptkSymbol) and (PeekTok.Text = '.') and
           (PeekTok(1).Kind = ptkIdent) then
        begin
          NextTok; { '.' }
          VarName := VarName + '.' + NextTok.Text;
        end;
        SetLength(Result.IntoVars, Length(Result.IntoVars) + 1);
        Result.IntoVars[High(Result.IntoVars)] := VarName;
      end;
      if MatchUpper('AS') then
      begin
        MatchUpper('CURSOR');
        if PeekTok.Kind = ptkIdent then NextTok;
      end;
      Break;
    end;

    if PeekTok.Kind = ptkString then
      FullHeader := FullHeader + ' ''' + StringReplace(PeekTok.Text, '''', '''''', [rfReplaceAll]) + ''''
    else if FullHeader = '' then
      FullHeader := PeekTok.Text
    else if (PeekTok.Kind = ptkSymbol) and ((PeekTok.Text = ',') or (PeekTok.Text = '.') or (PeekTok.Text = ')')) then
      FullHeader := FullHeader + PeekTok.Text
    else if (Copy(FullHeader, Length(FullHeader), 1) = '(') or
            (Copy(FullHeader, Length(FullHeader), 1) = '.') or
            (Copy(FullHeader, Length(FullHeader), 1) = ':') then
      FullHeader := FullHeader + PeekTok.Text
    else
      FullHeader := FullHeader + ' ' + PeekTok.Text;
    NextTok;
  end;

  IntoPos := Length(FullHeader);
  if IntoPos > 0 then ;
  Result.SqlText := Trim(FullHeader);
  MatchUpper('DO');
  Result.Body := ParseStatement;
  if Result.Body <> nil then
    Result.EndLine := Result.Body.EndLine
  else
    Result.EndLine := Result.Line;
end;

function TPsqlDebugger.ParseSelectIntoOrSql(const AStartLine: Integer): TPsqlStmt;
var
  SqlPart, VarName: string;
  HasInto: Boolean;
  ParenDepth: Integer;
begin
  Result := TPsqlStmt.Create;
  Result.Line := AStartLine;
  SqlPart := '';
  HasInto := False;
  ParenDepth := 0;

  while (PeekTok.Kind <> ptkEOF) and not ((ParenDepth = 0) and (PeekTok.Text = ';')) do
  begin
    if (ParenDepth = 0) and (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = 'INTO') then
    begin
      HasInto := True;
      NextTok; { INTO }
      while (PeekTok.Kind <> ptkEOF) and (PeekTok.Text <> ';') do
      begin
        if PeekTok.Kind = ptkSymbol then
        begin
          NextTok;
          Continue;
        end;
        VarName := NextTok.Text;
        if (SameText(VarName, 'NEW') or SameText(VarName, 'OLD')) and
           (PeekTok.Kind = ptkSymbol) and (PeekTok.Text = '.') and
           (PeekTok(1).Kind = ptkIdent) then
        begin
          NextTok; { '.' }
          VarName := VarName + '.' + NextTok.Text;
        end;
        SetLength(Result.IntoVars, Length(Result.IntoVars) + 1);
        Result.IntoVars[High(Result.IntoVars)] := VarName;
      end;
      Break;
    end;

    if PeekTok.Text = '(' then Inc(ParenDepth)
    else if (PeekTok.Text = ')') and (ParenDepth > 0) then Dec(ParenDepth);

    if PeekTok.Kind = ptkString then
      SqlPart := SqlPart + ' ''' + StringReplace(PeekTok.Text, '''', '''''', [rfReplaceAll]) + ''''
    else if SqlPart = '' then
      SqlPart := PeekTok.Text
    else if (PeekTok.Kind = ptkSymbol) and ((PeekTok.Text = ',') or (PeekTok.Text = '.') or (PeekTok.Text = ')')) then
      SqlPart := SqlPart + PeekTok.Text
    else if (Copy(SqlPart, Length(SqlPart), 1) = '(') or
            (Copy(SqlPart, Length(SqlPart), 1) = '.') or
            (Copy(SqlPart, Length(SqlPart), 1) = ':') then
      SqlPart := SqlPart + PeekTok.Text
    else
      SqlPart := SqlPart + ' ' + PeekTok.Text;
    NextTok;
  end;

  Result.EndLine := PeekTok.Line;
  MatchSymbol(';');
  if HasInto then
    Result.Kind := pskSelectInto
  else
    Result.Kind := pskSql;
  Result.SqlText := Trim(SqlPart);
end;

function TPsqlDebugger.ParseExecProcOrDml(const AStartLine: Integer): TPsqlStmt;
var
  SqlPart, VarName: string;
  HasInto, SeenReturning: Boolean;
  ParenDepth: Integer;
begin
  Result := TPsqlStmt.Create;
  Result.Line := AStartLine;
  SqlPart := '';
  HasInto := False;
  SeenReturning := False;
  ParenDepth := 0;

  while (PeekTok.Kind <> ptkEOF) and not ((ParenDepth = 0) and (PeekTok.Text = ';')) do
  begin
    if (ParenDepth = 0) and (PeekTok.Kind = ptkIdent) and (PeekTok.UpperText = 'RETURNING') then
      SeenReturning := True;

    if (ParenDepth = 0) and (PeekTok.Kind = ptkIdent) and
       ((PeekTok.UpperText = 'RETURNING_VALUES') or (SeenReturning and (PeekTok.UpperText = 'INTO'))) then
    begin
      HasInto := True;
      NextTok; { RETURNING_VALUES or INTO }
      while (PeekTok.Kind <> ptkEOF) and (PeekTok.Text <> ';') do
      begin
        if PeekTok.Kind = ptkSymbol then
        begin
          NextTok;
          Continue;
        end;
        VarName := NextTok.Text;
        if (SameText(VarName, 'NEW') or SameText(VarName, 'OLD')) and
           (PeekTok.Kind = ptkSymbol) and (PeekTok.Text = '.') and
           (PeekTok(1).Kind = ptkIdent) then
        begin
          NextTok; { '.' }
          VarName := VarName + '.' + NextTok.Text;
        end;
        SetLength(Result.IntoVars, Length(Result.IntoVars) + 1);
        Result.IntoVars[High(Result.IntoVars)] := VarName;
      end;
      Break;
    end;

    if PeekTok.Text = '(' then Inc(ParenDepth)
    else if (PeekTok.Text = ')') and (ParenDepth > 0) then Dec(ParenDepth);

    if PeekTok.Kind = ptkString then
      SqlPart := SqlPart + ' ''' + StringReplace(PeekTok.Text, '''', '''''', [rfReplaceAll]) + ''''
    else if SqlPart = '' then
      SqlPart := PeekTok.Text
    else if (PeekTok.Kind = ptkSymbol) and ((PeekTok.Text = ',') or (PeekTok.Text = '.') or (PeekTok.Text = ')')) then
      SqlPart := SqlPart + PeekTok.Text
    else if (Copy(SqlPart, Length(SqlPart), 1) = '(') or
            (Copy(SqlPart, Length(SqlPart), 1) = '.') or
            (Copy(SqlPart, Length(SqlPart), 1) = ':') then
      SqlPart := SqlPart + PeekTok.Text
    else
      SqlPart := SqlPart + ' ' + PeekTok.Text;
    NextTok;
  end;

  Result.EndLine := PeekTok.Line;
  MatchSymbol(';');
  if HasInto then
    Result.Kind := pskSelectInto
  else
    Result.Kind := pskSql;
  Result.SqlText := Trim(SqlPart);
end;

function TPsqlDebugger.ParseStatement: TPsqlStmt;
var
  T: TPsqlToken;
  EndLine: Integer;
  TargetName: string;
begin
  SkipSemicolons;
  T := PeekTok;
  if (T.Kind = ptkEOF) or (T.UpperText = 'END') then
    Exit(nil);

  if T.Kind = ptkIdent then
  begin
    if T.UpperText = 'BEGIN' then
      Exit(ParseBlock);
    if T.UpperText = 'IF' then
      Exit(ParseIf);
    if T.UpperText = 'WHILE' then
      Exit(ParseWhile);
    if T.UpperText = 'FOR' then
      Exit(ParseFor);
    if T.UpperText = 'SUSPEND' then
    begin
      Result := TPsqlStmt.Create;
      Result.Kind := pskSuspend;
      Result.Line := T.Line;
      Result.EndLine := T.Line;
      NextTok;
      MatchSymbol(';');
      Exit;
    end;
    if T.UpperText = 'EXIT' then
    begin
      Result := TPsqlStmt.Create;
      Result.Kind := pskExit;
      Result.Line := T.Line;
      Result.EndLine := T.Line;
      NextTok;
      MatchSymbol(';');
      Exit;
    end;
    if (T.UpperText = 'BREAK') or (T.UpperText = 'LEAVE') then
    begin
      Result := TPsqlStmt.Create;
      Result.Kind := pskBreak;
      Result.Line := T.Line;
      CollectTokensUntil('', '', ';', False, EndLine);
      Result.EndLine := EndLine;
      MatchSymbol(';');
      Exit;
    end;
    if T.UpperText = 'POST_EVENT' then
    begin
      Result := TPsqlStmt.Create;
      Result.Kind := pskPostEvent;
      Result.Line := T.Line;
      NextTok;
      Result.ExprText := CollectTokensUntil('', '', ';', True, EndLine);
      Result.EndLine := EndLine;
      MatchSymbol(';');
      Exit;
    end;
    if T.UpperText = 'EXCEPTION' then
    begin
      Result := TPsqlStmt.Create;
      Result.Kind := pskException;
      Result.Line := T.Line;
      NextTok;
      Result.ExprText := CollectTokensUntil('', '', ';', True, EndLine);
      Result.EndLine := EndLine;
      MatchSymbol(';');
      Exit;
    end;
    if T.UpperText = 'SELECT' then
      Exit(ParseSelectIntoOrSql(T.Line));
    if ((T.UpperText = 'EXECUTE') and (PeekTok(1).Kind = ptkIdent) and (PeekTok(1).UpperText = 'PROCEDURE')) or
       (T.UpperText = 'INSERT') or (T.UpperText = 'UPDATE') or (T.UpperText = 'DELETE') then
      Exit(ParseExecProcOrDml(T.Line));

    { Qualified assignment: NEW.<field> = <expr>; or OLD.<field> = <expr>; }
    if ((T.UpperText = 'NEW') or (T.UpperText = 'OLD')) and
       (PeekTok(1).Kind = ptkSymbol) and (PeekTok(1).Text = '.') and
       (PeekTok(2).Kind = ptkIdent) and
       (PeekTok(3).Kind = ptkSymbol) and ((PeekTok(3).Text = '=') or (PeekTok(3).Text = ':=')) then
    begin
      Result := TPsqlStmt.Create;
      Result.Kind := pskAssign;
      Result.Line := T.Line;
      TargetName := NextTok.Text;
      NextTok; { '.' }
      TargetName := TargetName + '.' + NextTok.Text;
      NextTok; { '=' }
      Result.TargetVar := TargetName;
      Result.ExprText := CollectTokensUntil('', '', ';', True, EndLine);
      Result.EndLine := EndLine;
      MatchSymbol(';');
      Exit;
    end;

    { Variable assignment: <ident> = <expr>; }
    if (PeekTok(1).Kind = ptkSymbol) and ((PeekTok(1).Text = '=') or (PeekTok(1).Text = ':=')) then
    begin
      Result := TPsqlStmt.Create;
      Result.Kind := pskAssign;
      Result.Line := T.Line;
      TargetName := NextTok.Text;
      NextTok; { = }
      Result.TargetVar := TargetName;
      Result.ExprText := CollectTokensUntil('', '', ';', True, EndLine);
      Result.EndLine := EndLine;
      MatchSymbol(';');
      Exit;
    end;
  end;

  { Generic SQL statement (INSERT, UPDATE, DELETE, MERGE, EXECUTE PROCEDURE, etc.) }
  Result := TPsqlStmt.Create;
  Result.Kind := pskSql;
  Result.Line := T.Line;
  Result.SqlText := CollectTokensUntil('', '', ';', False, EndLine);
  Result.EndLine := EndLine;
  MatchSymbol(';');
end;

function TPsqlDebugger.FormatSqlLiteral(const AIsNull: Boolean; const AValue, ADataType: string): string;
var
  UpperType, Trimmed, IsoDate: string;
  IntVal: Int64;
  FltVal: Double;
begin
  if AIsNull then
    Exit('NULL');
  Trimmed := Trim(AValue);
  UpperType := UpperCase(ADataType);
  if (Pos('INT', UpperType) > 0) or (Pos('NUMERIC', UpperType) > 0) or
     (Pos('DECIMAL', UpperType) > 0) or (Pos('FLOAT', UpperType) > 0) or
     (Pos('DOUBLE', UpperType) > 0) then
  begin
    if TryStrToInt64(Trimmed, IntVal) then
      Exit(Trimmed);
    if TryParseFloatInv(Trimmed, FltVal) then
      Exit(FloatToStrInv(FltVal));
  end;
  if TryStrToInt64(Trimmed, IntVal) and (UpperType = '') then
    Exit(Trimmed);

  if ((Pos('DATE', UpperType) > 0) or (Pos('TIMESTAMP', UpperType) > 0) or (UpperType = '')) and
     (Length(Trimmed) >= 10) and (Trimmed[3] = '/') and (Trimmed[6] = '/') and
     (Trimmed[1] in ['0'..'9']) and (Trimmed[2] in ['0'..'9']) and
     (Trimmed[4] in ['0'..'9']) and (Trimmed[5] in ['0'..'9']) and
     (Trimmed[7] in ['0'..'9']) and (Trimmed[8] in ['0'..'9']) and
     (Trimmed[9] in ['0'..'9']) and (Trimmed[10] in ['0'..'9']) then
  begin
    IsoDate := Copy(Trimmed, 7, 4) + '-' + Copy(Trimmed, 4, 2) + '-' + Copy(Trimmed, 1, 2) +
               Copy(Trimmed, 11, Length(Trimmed) - 10);
    Exit('''' + StringReplace(IsoDate, '''', '''''', [rfReplaceAll]) + '''');
  end;

  Result := '''' + StringReplace(AValue, '''', '''''', [rfReplaceAll]) + '''';
end;

function TPsqlDebugger.SubstituteSqlVars(const ASQL: string): string;
var
  I, Len, StartIdx: Integer;
  InSingleQuote: Boolean;
  VarName, FieldName, VarVal: string;
  IsNull: Boolean;
  V: TDebugVariable;
  PrevChar: Char;
begin
  Result := '';
  I := 1;
  Len := Length(ASQL);
  InSingleQuote := False;

  while I <= Len do
  begin
    if ASQL[I] = '''' then
    begin
      InSingleQuote := not InSingleQuote;
      Result := Result + ASQL[I];
      Inc(I);
      Continue;
    end;

    if (not InSingleQuote) and (ASQL[I] = ':') and (I < Len) and IsIdentStartChar(ASQL[I + 1]) then
    begin
      Inc(I);
      StartIdx := I;
      while (I <= Len) and IsIdentChar(ASQL[I]) do
        Inc(I);
      VarName := Copy(ASQL, StartIdx, I - StartIdx);
      if (SameText(VarName, 'NEW') or SameText(VarName, 'OLD')) and
         (I < Len) and (ASQL[I] = '.') and IsIdentStartChar(ASQL[I + 1]) then
      begin
        Inc(I);
        StartIdx := I;
        while (I <= Len) and IsIdentChar(ASQL[I]) do
          Inc(I);
        VarName := VarName + '.' + Copy(ASQL, StartIdx, I - StartIdx);
      end;
      V := FindVar(VarName);
      if V <> nil then
        Result := Result + FormatSqlLiteral(V.IsNull, V.Value, V.DataType)
      else if GetVarValue(VarName, IsNull, VarVal) then
        Result := Result + FormatSqlLiteral(IsNull, VarVal, '')
      else
        Result := Result + ':' + VarName;
      Continue;
    end;

    if (not InSingleQuote) and IsIdentStartChar(ASQL[I]) then
    begin
      if I > 1 then PrevChar := ASQL[I - 1] else PrevChar := ' ';
      if (not IsIdentChar(PrevChar)) and (PrevChar <> '.') then
      begin
        StartIdx := I;
        while (I <= Len) and IsIdentChar(ASQL[I]) do
          Inc(I);
        VarName := Copy(ASQL, StartIdx, I - StartIdx);
        if (SameText(VarName, 'NEW') or SameText(VarName, 'OLD')) and
           (I < Len) and (ASQL[I] = '.') and IsIdentStartChar(ASQL[I + 1]) then
        begin
          Inc(I);
          StartIdx := I;
          while (I <= Len) and IsIdentChar(ASQL[I]) do
            Inc(I);
          FieldName := Copy(ASQL, StartIdx, I - StartIdx);
          V := FindVar(VarName + '.' + FieldName);
          if V <> nil then
          begin
            Result := Result + FormatSqlLiteral(V.IsNull, V.Value, V.DataType);
            Continue;
          end;
          Result := Result + VarName + '.' + FieldName;
          Continue;
        end;
        Result := Result + VarName;
        Continue;
      end;
    end;

    Result := Result + ASQL[I];
    Inc(I);
  end;
end;

function TPsqlDebugger.EvalViaDatabase(const AExpr: string; out AIsNull: Boolean; out AValue: string): Boolean;
var
  SQL, Err: string;
  Res: TQueryResult;
begin
  Result := False;
  AIsNull := True;
  AValue := '';
  if not Assigned(FOnExecSql) then
    Exit;

  SQL := 'SELECT ' + SubstituteSqlVars(AExpr) + ' FROM RDB$DATABASE';
  Res := FOnExecSql(SQL, Err);
  if Res = nil then
    Exit;
  try
    if Res.Success and (Res.RowCount > 0) and (Length(Res.GetRow(0)) > 0) then
    begin
      AIsNull := Res.GetRow(0)[0].IsNull;
      AValue := Res.GetRow(0)[0].AsText;
      Result := True;
    end;
  finally
    Res.Free;
  end;
end;

function TPsqlDebugger.EvalExpression(const AExpr: string; out AIsNull: Boolean; out AValue: string): Boolean;
var
  Expr: string;
  PosIdx, Len: Integer;

  procedure SkipSpaces;
  begin
    while (PosIdx <= Len) and (Expr[PosIdx] in [' ', #9, #10, #13]) do
      Inc(PosIdx);
  end;

  function ParseOr(out ONull: Boolean; out OVal: string): Boolean; forward;

  function PeekWord(const AWord: string): Boolean;
  var
    Saved, WLen: Integer;
  begin
    SkipSpaces;
    WLen := Length(AWord);
    Saved := PosIdx;
    Result := (Saved + WLen - 1 <= Len) and
              SameText(Copy(Expr, Saved, WLen), AWord) and
              ((Saved + WLen > Len) or not IsIdentChar(Expr[Saved + WLen]));
  end;

  function ConsumeWord(const AWord: string): Boolean;
  begin
    Result := PeekWord(AWord);
    if Result then
      Inc(PosIdx, Length(AWord));
  end;

  function ParsePrimary(out ONull: Boolean; out OVal: string): Boolean;
  var
    StartIdx: Integer;
    Ident, FnUpper: string;
    ArgNulls: array of Boolean;
    ArgVals: array of string;
    DVal: Double;
    IVal: Int64;
  begin
    SkipSpaces;
    ONull := True;
    OVal := '';
    if PosIdx > Len then
      Exit(False);

    if Expr[PosIdx] = '(' then
    begin
      Inc(PosIdx);
      Result := ParseOr(ONull, OVal);
      SkipSpaces;
      if (PosIdx <= Len) and (Expr[PosIdx] = ')') then
        Inc(PosIdx);
      Exit;
    end;

    if Expr[PosIdx] = '''' then
    begin
      Inc(PosIdx);
      OVal := '';
      while PosIdx <= Len do
      begin
        if Expr[PosIdx] = '''' then
        begin
          if (PosIdx < Len) and (Expr[PosIdx + 1] = '''') then
          begin
            OVal := OVal + '''';
            Inc(PosIdx, 2);
            Continue;
          end;
          Inc(PosIdx);
          Break;
        end;
        OVal := OVal + Expr[PosIdx];
        Inc(PosIdx);
      end;
      ONull := False;
      Exit(True);
    end;

    if Expr[PosIdx] in ['0'..'9'] then
    begin
      StartIdx := PosIdx;
      while (PosIdx <= Len) and (Expr[PosIdx] in ['0'..'9', '.']) do
        Inc(PosIdx);
      OVal := Copy(Expr, StartIdx, PosIdx - StartIdx);
      ONull := False;
      Exit(True);
    end;

    if Expr[PosIdx] = ':' then
      Inc(PosIdx);

    if (PosIdx <= Len) and IsIdentStartChar(Expr[PosIdx]) then
    begin
      StartIdx := PosIdx;
      while (PosIdx <= Len) and IsIdentChar(Expr[PosIdx]) do
        Inc(PosIdx);
      Ident := Copy(Expr, StartIdx, PosIdx - StartIdx);
      FnUpper := UpperCase(Ident);

      if FnUpper = 'NULL' then
      begin
        ONull := True;
        OVal := '';
        Exit(True);
      end;
      if FnUpper = 'TRUE' then
      begin
        ONull := False;
        OVal := '1';
        Exit(True);
      end;
      if FnUpper = 'FALSE' then
      begin
        ONull := False;
        OVal := '0';
        Exit(True);
      end;

      SkipSpaces;
      if (PosIdx <= Len) and (Expr[PosIdx] = '(') then
      begin
        Inc(PosIdx);
        SetLength(ArgNulls, 0);
        SetLength(ArgVals, 0);
        SkipSpaces;
        if (PosIdx <= Len) and (Expr[PosIdx] <> ')') then
        begin
          while True do
          begin
            SetLength(ArgNulls, Length(ArgNulls) + 1);
            SetLength(ArgVals, Length(ArgVals) + 1);
            if not ParseOr(ArgNulls[High(ArgNulls)], ArgVals[High(ArgVals)]) then
              Exit(False);
            SkipSpaces;
            if (PosIdx <= Len) and (Expr[PosIdx] = ',') then
              Inc(PosIdx)
            else
              Break;
          end;
        end;
        SkipSpaces;
        if (PosIdx <= Len) and (Expr[PosIdx] = ')') then
          Inc(PosIdx)
        else
          Exit(False);

        if FnUpper = 'COALESCE' then
        begin
          ONull := True;
          OVal := '';
          for StartIdx := 0 to High(ArgNulls) do
          begin
            if not ArgNulls[StartIdx] then
            begin
              ONull := False;
              OVal := ArgVals[StartIdx];
              Break;
            end;
          end;
          Exit(True);
        end;
        if (FnUpper = 'IIF') and (Length(ArgVals) >= 3) then
        begin
          if (not ArgNulls[0]) and ((ArgVals[0] = '1') or SameText(ArgVals[0], 'true')) then
          begin
            ONull := ArgNulls[1];
            OVal := ArgVals[1];
          end
          else
          begin
            ONull := ArgNulls[2];
            OVal := ArgVals[2];
          end;
          Exit(True);
        end;
        if (FnUpper = 'UPPER') and (Length(ArgVals) >= 1) then
        begin
          ONull := ArgNulls[0];
          OVal := AnsiUpperCase(ArgVals[0]);
          Exit(True);
        end;
        if (FnUpper = 'LOWER') and (Length(ArgVals) >= 1) then
        begin
          ONull := ArgNulls[0];
          OVal := AnsiLowerCase(ArgVals[0]);
          Exit(True);
        end;
        if (FnUpper = 'TRIM') and (Length(ArgVals) >= 1) then
        begin
          ONull := ArgNulls[0];
          OVal := Trim(ArgVals[0]);
          Exit(True);
        end;
        if ((FnUpper = 'CHAR_LENGTH') or (FnUpper = 'STRLEN')) and (Length(ArgVals) >= 1) then
        begin
          ONull := ArgNulls[0];
          if not ONull then
            OVal := IntToStr(Length(ArgVals[0]));
          Exit(True);
        end;
        if (FnUpper = 'ABS') and (Length(ArgVals) >= 1) then
        begin
          ONull := ArgNulls[0];
          if (not ONull) and TryStrToInt64(Trim(ArgVals[0]), IVal) then
            OVal := IntToStr(Abs(IVal))
          else if (not ONull) and TryParseFloatInv(ArgVals[0], DVal) then
            OVal := FloatToStrInv(Abs(DVal));
          Exit(True);
        end;

        { Fallback to database evaluation for complex Firebird functions }
        Exit(False);
      end;

      if (FnUpper = 'NEW') or (FnUpper = 'OLD') then
      begin
        SkipSpaces;
        if (PosIdx <= Len) and (Expr[PosIdx] = '.') then
        begin
          Inc(PosIdx);
          SkipSpaces;
          if (PosIdx <= Len) and IsIdentStartChar(Expr[PosIdx]) then
          begin
            StartIdx := PosIdx;
            while (PosIdx <= Len) and IsIdentChar(Expr[PosIdx]) do
              Inc(PosIdx);
            Ident := Ident + '.' + Copy(Expr, StartIdx, PosIdx - StartIdx);
          end;
        end;
      end;

      if GetVarValue(Ident, ONull, OVal) then
        Exit(True);
      Exit(False);
    end;
    Result := False;
  end;

  function ParseUnary(out ONull: Boolean; out OVal: string): Boolean;
  var
    D: Double;
    I: Int64;
  begin
    SkipSpaces;
    if (PosIdx <= Len) and (Expr[PosIdx] = '-') then
    begin
      Inc(PosIdx);
      Result := ParseUnary(ONull, OVal);
      if Result and (not ONull) then
      begin
        if TryStrToInt64(Trim(OVal), I) then OVal := IntToStr(-I)
        else if TryParseFloatInv(OVal, D) then OVal := FloatToStrInv(-D);
      end;
      Exit;
    end;
    if (PosIdx <= Len) and (Expr[PosIdx] = '+') then
    begin
      Inc(PosIdx);
      Exit(ParseUnary(ONull, OVal));
    end;
    Result := ParsePrimary(ONull, OVal);
  end;

  function ParseMul(out ONull: Boolean; out OVal: string): Boolean;
  var
    RNull: Boolean;
    RVal: string;
    Op: Char;
    LInt, RInt: Int64;
    LD, RD: Double;
  begin
    Result := ParseUnary(ONull, OVal);
    if not Result then Exit;
    while True do
    begin
      SkipSpaces;
      if (PosIdx <= Len) and (Expr[PosIdx] in ['*', '/']) then
      begin
        Op := Expr[PosIdx];
        Inc(PosIdx);
        if not ParseUnary(RNull, RVal) then Exit(False);
        if ONull or RNull then
        begin
          ONull := True;
          OVal := '';
        end
        else if (Op = '*') and TryStrToInt64(Trim(OVal), LInt) and TryStrToInt64(Trim(RVal), RInt) then
          OVal := IntToStr(LInt * RInt)
        else if TryParseFloatInv(OVal, LD) and TryParseFloatInv(RVal, RD) then
        begin
          if Op = '*' then OVal := FloatToStrInv(LD * RD)
          else if RD <> 0 then OVal := FloatToStrInv(LD / RD)
          else Exit(False);
        end
        else Exit(False);
      end
      else
        Break;
    end;
  end;

  function ParseAdd(out ONull: Boolean; out OVal: string): Boolean;
  var
    RNull: Boolean;
    RVal: string;
    IsConcat: Boolean;
    Op: Char;
    LInt, RInt: Int64;
    LD, RD: Double;
  begin
    Result := ParseMul(ONull, OVal);
    if not Result then Exit;
    while True do
    begin
      SkipSpaces;
      IsConcat := (PosIdx < Len) and (Expr[PosIdx] = '|') and (Expr[PosIdx + 1] = '|');
      if IsConcat then
      begin
        Inc(PosIdx, 2);
        if not ParseMul(RNull, RVal) then Exit(False);
        if ONull or RNull then
        begin
          ONull := True;
          OVal := '';
        end
        else
        begin
          ONull := False;
          OVal := OVal + RVal;
        end;
        Continue;
      end;

      if (PosIdx <= Len) and (Expr[PosIdx] in ['+', '-']) then
      begin
        Op := Expr[PosIdx];
        Inc(PosIdx);
        if not ParseMul(RNull, RVal) then Exit(False);
        if ONull or RNull then
        begin
          ONull := True;
          OVal := '';
        end
        else if TryStrToInt64(Trim(OVal), LInt) and TryStrToInt64(Trim(RVal), RInt) then
        begin
          if Op = '+' then OVal := IntToStr(LInt + RInt)
          else OVal := IntToStr(LInt - RInt);
        end
        else if TryParseFloatInv(OVal, LD) and TryParseFloatInv(RVal, RD) then
        begin
          if Op = '+' then OVal := FloatToStrInv(LD + RD)
          else OVal := FloatToStrInv(LD - RD);
        end
        else Exit(False);
      end
      else
        Break;
    end;
  end;

  function CompareVals(const ANullL: Boolean; const AValL: string; const ANullR: Boolean; const AValR: string): Integer;
  var
    LD, RD: Double;
  begin
    if ANullL or ANullR then
      Exit(0);
    if TryParseFloatInv(AValL, LD) and TryParseFloatInv(AValR, RD) then
    begin
      if LD < RD then Exit(-1);
      if LD > RD then Exit(1);
      Exit(0);
    end;
    Result := AnsiCompareStr(AValL, AValR);
  end;

  function ParseCmp(out ONull: Boolean; out OVal: string): Boolean;
  var
    RNull, NotFlag, ResBool: Boolean;
    RVal, Op: string;
    Cmp: Integer;
  begin
    Result := ParseAdd(ONull, OVal);
    if not Result then Exit;

    SkipSpaces;
    if ConsumeWord('IS') then
    begin
      NotFlag := ConsumeWord('NOT');
      if ConsumeWord('NULL') then
      begin
        ResBool := ONull;
        if NotFlag then ResBool := not ResBool;
        ONull := False;
        if ResBool then OVal := '1' else OVal := '0';
        Exit(True);
      end
      else if ConsumeWord('DISTINCT') then
      begin
        ConsumeWord('FROM');
        if not ParseAdd(RNull, RVal) then Exit(False);
        if ONull and RNull then
          ResBool := False
        else if ONull <> RNull then
          ResBool := True
        else
          ResBool := (CompareVals(ONull, OVal, RNull, RVal) <> 0);
        if NotFlag then ResBool := not ResBool;
        ONull := False;
        if ResBool then OVal := '1' else OVal := '0';
        Exit(True);
      end;
      Exit(False);
    end;

    if ConsumeWord('CONTAINING') then
    begin
      if not ParseAdd(RNull, RVal) then Exit(False);
      if ONull or RNull then begin ONull := False; OVal := '0'; Exit(True); end;
      ONull := False;
      if Pos(AnsiUpperCase(RVal), AnsiUpperCase(OVal)) > 0 then OVal := '1' else OVal := '0';
      Exit(True);
    end;

    if ConsumeWord('STARTING') then
    begin
      ConsumeWord('WITH');
      if not ParseAdd(RNull, RVal) then Exit(False);
      if ONull or RNull then begin ONull := False; OVal := '0'; Exit(True); end;
      ONull := False;
      if AnsiStartsText(RVal, OVal) then OVal := '1' else OVal := '0';
      Exit(True);
    end;

    Op := '';
    if (PosIdx < Len) and ((Copy(Expr, PosIdx, 2) = '<>') or (Copy(Expr, PosIdx, 2) = '!=') or
       (Copy(Expr, PosIdx, 2) = '<=') or (Copy(Expr, PosIdx, 2) = '>=')) then
    begin
      Op := Copy(Expr, PosIdx, 2);
      Inc(PosIdx, 2);
    end
    else if (PosIdx <= Len) and (Expr[PosIdx] in ['=', '<', '>']) then
    begin
      Op := Expr[PosIdx];
      Inc(PosIdx);
    end;

    if Op <> '' then
    begin
      if not ParseAdd(RNull, RVal) then Exit(False);
      if ONull or RNull then
      begin
        ONull := False;
        OVal := '0';
        Exit(True);
      end;
      Cmp := CompareVals(ONull, OVal, RNull, RVal);
      if Op = '=' then ResBool := (Cmp = 0)
      else if (Op = '<>') or (Op = '!=') then ResBool := (Cmp <> 0)
      else if Op = '<' then ResBool := (Cmp < 0)
      else if Op = '<=' then ResBool := (Cmp <= 0)
      else if Op = '>' then ResBool := (Cmp > 0)
      else ResBool := (Cmp >= 0);
      ONull := False;
      if ResBool then OVal := '1' else OVal := '0';
    end;
  end;

  function ParseNot(out ONull: Boolean; out OVal: string): Boolean;
  begin
    if ConsumeWord('NOT') then
    begin
      Result := ParseNot(ONull, OVal);
      if Result and (not ONull) then
      begin
        if (OVal = '1') or SameText(OVal, 'true') then OVal := '0'
        else OVal := '1';
      end;
      Exit;
    end;
    Result := ParseCmp(ONull, OVal);
  end;

  function ParseAnd(out ONull: Boolean; out OVal: string): Boolean;
  var
    RNull: Boolean;
    RVal: string;
    LTrue, RTrue: Boolean;
  begin
    Result := ParseNot(ONull, OVal);
    if not Result then Exit;
    while ConsumeWord('AND') do
    begin
      if not ParseNot(RNull, RVal) then Exit(False);
      LTrue := (not ONull) and ((OVal = '1') or SameText(OVal, 'true'));
      RTrue := (not RNull) and ((RVal = '1') or SameText(RVal, 'true'));
      ONull := False;
      if LTrue and RTrue then OVal := '1' else OVal := '0';
    end;
  end;

  function ParseOr(out ONull: Boolean; out OVal: string): Boolean;
  var
    RNull: Boolean;
    RVal: string;
    LTrue, RTrue: Boolean;
  begin
    Result := ParseAnd(ONull, OVal);
    if not Result then Exit;
    while ConsumeWord('OR') do
    begin
      if not ParseAnd(RNull, RVal) then Exit(False);
      LTrue := (not ONull) and ((OVal = '1') or SameText(OVal, 'true'));
      RTrue := (not RNull) and ((RVal = '1') or SameText(RVal, 'true'));
      ONull := False;
      if LTrue or RTrue then OVal := '1' else OVal := '0';
    end;
  end;

begin
  Expr := Trim(AExpr);
  if Expr = '' then
  begin
    AIsNull := True;
    AValue := '';
    Exit(True);
  end;

  PosIdx := 1;
  Len := Length(Expr);
  if ParseOr(AIsNull, AValue) then
  begin
    SkipSpaces;
    if PosIdx > Len then
      Exit(True);
  end;

  { Fallback to Firebird database evaluation }
  Result := EvalViaDatabase(Expr, AIsNull, AValue);
end;

function TPsqlDebugger.EvalCondition(const AExpr: string): Boolean;
var
  IsNull: Boolean;
  Val: string;
begin
  Result := False;
  if EvalExpression(AExpr, IsNull, Val) then
    Result := (not IsNull) and ((Val = '1') or SameText(Val, 'true'))
  else if EvalViaDatabase('CASE WHEN (' + AExpr + ') THEN 1 ELSE 0 END', IsNull, Val) then
    Result := (not IsNull) and ((Val = '1') or SameText(Val, 'true'));
end;

procedure TPsqlDebugger.PushFrame(const AKind: TDebugExecFrameKind; const AStmt: TPsqlStmt);
var
  F: TDebugExecFrame;
begin
  F := TDebugExecFrame.Create;
  F.Kind := AKind;
  F.Stmt := AStmt;
  F.ChildIndex := 0;
  F.CursorResult := nil;
  F.CursorRowIndex := -1;
  F.ConditionChecked := False;
  FStack.Add(F);
end;

procedure TPsqlDebugger.PopFrame;
var
  Idx: Integer;
begin
  if FStack.Count > 0 then
  begin
    Idx := FStack.Count - 1;
    TObject(FStack[Idx]).Free;
    FStack.Delete(Idx);
  end;
end;

function TPsqlDebugger.CurrentFrame: TDebugExecFrame;
begin
  if FStack.Count > 0 then
    Result := TDebugExecFrame(FStack[FStack.Count - 1])
  else
    Result := nil;
end;

procedure TPsqlDebugger.CaptureCursorFields(
  const ARes: TQueryResult;
  const ARowIdx: Integer;
  const AStmt: TPsqlStmt
);
var
  I: Integer;
  Row: TQueryRow;
begin
  SetLength(FCursorFields, 0);
  if (ARes = nil) or (ARowIdx < 0) or (ARowIdx >= ARes.RowCount) then
    Exit;

  Row := ARes.GetRow(ARowIdx);
  SetLength(FCursorFields, ARes.ColumnCount);
  for I := 0 to ARes.ColumnCount - 1 do
  begin
    FCursorFields[I].FieldName := ARes.GetColumn(I).Name;
    if I < Length(Row) then
    begin
      FCursorFields[I].IsNull := Row[I].IsNull;
      FCursorFields[I].Value := Row[I].AsText;
    end
    else
    begin
      FCursorFields[I].IsNull := True;
      FCursorFields[I].Value := '';
    end;
  end;

  for I := 0 to High(AStmt.IntoVars) do
  begin
    if I < Length(Row) then
      SetVarValue(AStmt.IntoVars[I], Row[I].IsNull, Row[I].AsText)
    else
      SetVarValue(AStmt.IntoVars[I], True, '');
  end;
end;

procedure TPsqlDebugger.RecordSuspendedRow;
var
  I, RIdx: Integer;
  V: TDebugVariable;
begin
  if Length(FOutputColNames) = 0 then
    Exit;
  RIdx := Length(FSuspendedRows);
  SetLength(FSuspendedRows, RIdx + 1);
  SetLength(FSuspendedRows[RIdx], Length(FOutputColNames));
  for I := 0 to High(FOutputColNames) do
  begin
    V := FindVar(FOutputColNames[I]);
    if V = nil then
      FSuspendedRows[RIdx][I] := '<NULL>'
    else if V.IsNull then
      FSuspendedRows[RIdx][I] := '<NULL>'
    else
      FSuspendedRows[RIdx][I] := V.Value;
  end;
end;

function TPsqlDebugger.ExecuteAtomicStmt(const AStmt: TPsqlStmt): Boolean;
var
  IsNull: Boolean;
  Val, ExecSQL, Err: string;
  Res: TQueryResult;
begin
  Result := True;
  if AStmt = nil then
    Exit;

  Inc(FStepCount);
  case AStmt.Kind of
    pskAssign:
      begin
        if EvalExpression(AStmt.ExprText, IsNull, Val) then
          SetVarValue(AStmt.TargetVar, IsNull, Val)
        else
        begin
          FLastError := Format('Não foi possível avaliar expressão na linha %d: %s', [AStmt.Line, AStmt.ExprText]);
          FState := dsError;
          Exit(False);
        end;
      end;

    pskSelectInto:
      begin
        ExecSQL := SubstituteSqlVars(AStmt.SqlText);
        Log('[SQL] ' + ExecSQL);
        if not Assigned(FOnExecSql) then
        begin
          FLastError := 'Callback de execução SQL não configurado.';
          FState := dsError;
          Exit(False);
        end;
        Res := FOnExecSql(ExecSQL, Err);
        if Res = nil then
        begin
          FLastError := Err;
          FState := dsError;
          Exit(False);
        end;
        try
          if not Res.Success then
          begin
            FLastError := Res.MessageText;
            FState := dsError;
            Exit(False);
          end;
          if Res.RowCount > 0 then
          begin
            CaptureCursorFields(Res, 0, AStmt);
            SetVarValue('ROW_COUNT', False, IntToStr(Res.RowCount));
          end
          else
          begin
            SetLength(FCursorFields, 0);
            SetVarValue('ROW_COUNT', False, '0');
          end;
        finally
          Res.Free;
        end;
      end;

    pskSql:
      begin
        ExecSQL := SubstituteSqlVars(AStmt.SqlText);
        Log('[SQL] ' + ExecSQL);
        if Assigned(FOnExecSql) then
        begin
          Res := FOnExecSql(ExecSQL, Err);
          if Res = nil then
          begin
            FLastError := Err;
            FState := dsError;
            Exit(False);
          end;
          try
            if not Res.Success then
            begin
              FLastError := Res.MessageText;
              FState := dsError;
              Exit(False);
            end;
            SetVarValue('ROW_COUNT', False, IntToStr(Res.RowsAffected));
          finally
            Res.Free;
          end;
        end;
      end;

    pskSuspend:
      begin
        RecordSuspendedRow;
        Log(Format('[SUSPEND] Linha emitida (#%d)', [Length(FSuspendedRows)]));
      end;

    pskPostEvent:
      begin
        if EvalExpression(AStmt.ExprText, IsNull, Val) then
          Log('[POST_EVENT] ' + Val)
        else
          Log('[POST_EVENT] ' + AStmt.ExprText);
      end;

    pskException:
      begin
        FLastError := 'Exceção disparada na linha ' + IntToStr(AStmt.Line) + ': ' + AStmt.ExprText;
        FState := dsError;
        Exit(False);
      end;

    pskExit:
      begin
        ClearStack;
        FState := dsFinished;
        FCurrentLine := AStmt.Line;
        Exit(True);
      end;

    pskBreak:
      begin
        while (FStack.Count > 0) and not (CurrentFrame.Kind in [dfkWhile, dfkForSelect, dfkForExecStmt]) do
          PopFrame;
        if FStack.Count > 0 then
          PopFrame;
      end;
  end;
end;

procedure TPsqlDebugger.UpdateCurrentLineFromTopFrame;
var
  F: TDebugExecFrame;
  NextChild: TPsqlStmt;
begin
  F := CurrentFrame;
  if F = nil then
  begin
    FState := dsFinished;
    Exit;
  end;

  case F.Kind of
    dfkBlock:
      begin
        if F.ChildIndex < Length(F.Stmt.Children) then
        begin
          NextChild := F.Stmt.Children[F.ChildIndex];
          FCurrentLine := NextChild.Line;
        end
        else
          FCurrentLine := F.Stmt.EndLine;
      end;
    dfkWhile, dfkForSelect, dfkForExecStmt:
      begin
        if not F.ConditionChecked then
          FCurrentLine := F.Stmt.Line
        else if F.Stmt.Body <> nil then
          FCurrentLine := F.Stmt.Body.Line
        else
          FCurrentLine := F.Stmt.Line;
      end;
  end;
end;

function TPsqlDebugger.AdvanceToNextExecutable(out AExecutedAction: Boolean): Boolean;
var
  F: TDebugExecFrame;
  Child: TPsqlStmt;
  ExecSQL, Err, StmtExpr: string;
  IsNull: Boolean;
begin
  AExecutedAction := False;
  Result := True;

  while FStack.Count > 0 do
  begin
    F := CurrentFrame;

    if F.Kind = dfkBlock then
    begin
      if F.ChildIndex >= Length(F.Stmt.Children) then
      begin
        PopFrame;
        Continue;
      end;

      Child := F.Stmt.Children[F.ChildIndex];
      Inc(F.ChildIndex);

      if Child.Kind = pskBlock then
      begin
        PushFrame(dfkBlock, Child);
        UpdateCurrentLineFromTopFrame;
        AExecutedAction := True;
        Exit(True);
      end
      else if Child.Kind = pskIf then
      begin
        Inc(FStepCount);
        if EvalCondition(Child.ExprText) then
        begin
          if Child.Body <> nil then
          begin
            if Child.Body.Kind = pskBlock then
              PushFrame(dfkBlock, Child.Body)
            else
            begin
              { Wrap single statement execution }
              if not ExecuteAtomicStmt(Child.Body) then
                Exit(False);
            end;
          end;
        end
        else if Child.ElseBody <> nil then
        begin
          if Child.ElseBody.Kind = pskBlock then
            PushFrame(dfkBlock, Child.ElseBody)
          else
          begin
            if not ExecuteAtomicStmt(Child.ElseBody) then
              Exit(False);
          end;
        end;
        UpdateCurrentLineFromTopFrame;
        AExecutedAction := True;
        Exit(True);
      end
      else if Child.Kind = pskWhile then
      begin
        PushFrame(dfkWhile, Child);
        UpdateCurrentLineFromTopFrame;
        AExecutedAction := True;
        Exit(True);
      end
      else if Child.Kind = pskForSelect then
      begin
        PushFrame(dfkForSelect, Child);
        UpdateCurrentLineFromTopFrame;
        AExecutedAction := True;
        Exit(True);
      end
      else if Child.Kind = pskForExecStmt then
      begin
        PushFrame(dfkForExecStmt, Child);
        UpdateCurrentLineFromTopFrame;
        AExecutedAction := True;
        Exit(True);
      end
      else
      begin
        if not ExecuteAtomicStmt(Child) then
          Exit(False);
        if FState = dsFinished then
          Exit(True);
        UpdateCurrentLineFromTopFrame;
        AExecutedAction := True;
        Exit(True);
      end;
    end
    else if F.Kind = dfkWhile then
    begin
      Inc(FStepCount);
      if EvalCondition(F.Stmt.ExprText) then
      begin
        if F.Stmt.Body <> nil then
        begin
          if F.Stmt.Body.Kind = pskBlock then
            PushFrame(dfkBlock, F.Stmt.Body)
          else if not ExecuteAtomicStmt(F.Stmt.Body) then
            Exit(False);
        end;
      end
      else
        PopFrame;
      UpdateCurrentLineFromTopFrame;
      AExecutedAction := True;
      Exit(True);
    end
    else if (F.Kind = dfkForSelect) or (F.Kind = dfkForExecStmt) then
    begin
      if not F.ConditionChecked then
      begin
        F.ConditionChecked := True;
        if F.Kind = dfkForSelect then
          ExecSQL := SubstituteSqlVars(F.Stmt.SqlText)
        else
        begin
          if not EvalExpression(F.Stmt.ExprText, IsNull, StmtExpr) or IsNull then
          begin
            FLastError := 'EXECUTE STATEMENT retornou SQL inválido/nulo.';
            FState := dsError;
            Exit(False);
          end;
          ExecSQL := SubstituteSqlVars(StmtExpr);
        end;
        Log('[FOR SQL] ' + ExecSQL);
        if not Assigned(FOnExecSql) then
        begin
          FLastError := 'Callback de execução SQL não configurado.';
          FState := dsError;
          Exit(False);
        end;
        F.CursorResult := FOnExecSql(ExecSQL, Err);
        if F.CursorResult = nil then
        begin
          FLastError := Err;
          FState := dsError;
          Exit(False);
        end;
        if not F.CursorResult.Success then
        begin
          FLastError := F.CursorResult.MessageText;
          FState := dsError;
          Exit(False);
        end;
        F.CursorRowIndex := -1;
      end;

      Inc(F.CursorRowIndex);
      if (F.CursorResult <> nil) and (F.CursorRowIndex >= F.CursorResult.RowCount) and F.CursorResult.HasMoreRows then
        F.CursorResult.FetchMore(200);
      Inc(FStepCount);
      if (F.CursorResult <> nil) and (F.CursorRowIndex < F.CursorResult.RowCount) then
      begin
        CaptureCursorFields(F.CursorResult, F.CursorRowIndex, F.Stmt);
        SetVarValue('ROW_COUNT', False, IntToStr(F.CursorRowIndex + 1));
        if F.Stmt.Body <> nil then
        begin
          if F.Stmt.Body.Kind = pskBlock then
            PushFrame(dfkBlock, F.Stmt.Body)
          else if not ExecuteAtomicStmt(F.Stmt.Body) then
            Exit(False);
        end;
      end
      else
      begin
        SetLength(FCursorFields, 0);
        PopFrame;
      end;
      UpdateCurrentLineFromTopFrame;
      AExecutedAction := True;
      Exit(True);
    end;
  end;

  FState := dsFinished;
end;

procedure TPsqlDebugger.LoadProcedure(
  const ADDL: string;
  const AParams: TDebugParamDeclArray
);
begin
  ClearStack;
  ClearVars;
  ClearSuspendedRows;
  FreeAndNil(FRootStmt);
  FStepCount := 0;
  FLastError := '';

  Tokenize(ADDL);
  FTokIdx := 0;
  ParseHeaderAndDecls(AParams);
  FRootStmt := ParseStatement;
  if FRootStmt <> nil then
  begin
    FState := dsIdle;
    FCurrentLine := FRootStmt.Line;
  end
  else
  begin
    FState := dsError;
    FLastError := 'Não foi possível localizar o bloco BEGIN..END da procedure.';
  end;
end;

procedure TPsqlDebugger.LoadTrigger(
  const ADDL: string;
  const AEvent: string;
  const AOldFields, ANewFields: TDebugParamDeclArray
);
var
  I, EndLine: Integer;
  V: TDebugVariable;
  EvtUp: string;
begin
  ClearStack;
  ClearVars;
  ClearSuspendedRows;
  FreeAndNil(FRootStmt);
  FStepCount := 0;
  FLastError := '';

  Tokenize(ADDL);
  FTokIdx := 0;

  V := EnsureVar('ROW_COUNT', dvsSystem, 'INTEGER');
  V.IsNull := False;
  V.Value := '0';
  V := EnsureVar('SQLCODE', dvsSystem, 'INTEGER');
  V.IsNull := False;
  V.Value := '0';

  EvtUp := UpperCase(Trim(AEvent));
  V := EnsureVar('INSERTING', dvsSystem, 'BOOLEAN');
  V.IsNull := False;
  if EvtUp = 'INSERT' then V.Value := '1' else V.Value := '0';

  V := EnsureVar('UPDATING', dvsSystem, 'BOOLEAN');
  V.IsNull := False;
  if EvtUp = 'UPDATE' then V.Value := '1' else V.Value := '0';

  V := EnsureVar('DELETING', dvsSystem, 'BOOLEAN');
  V.IsNull := False;
  if EvtUp = 'DELETE' then V.Value := '1' else V.Value := '0';

  SetLength(FOutputColNames, 0);
  for I := 0 to High(AOldFields) do
  begin
    V := EnsureVar('OLD.' + AOldFields[I].Name, dvsOld, AOldFields[I].DataType);
    V.IsNull := AOldFields[I].IsNull;
    V.Value := AOldFields[I].Value;
  end;
  for I := 0 to High(ANewFields) do
  begin
    V := EnsureVar('NEW.' + ANewFields[I].Name, dvsNew, ANewFields[I].DataType);
    V.IsNull := ANewFields[I].IsNull;
    V.Value := ANewFields[I].Value;
  end;

  while (PeekTok.Kind <> ptkEOF) and (PeekTok.UpperText <> 'AS') do
    NextTok;
  MatchUpper('AS');

  while (PeekTok.Kind <> ptkEOF) and (PeekTok.UpperText <> 'BEGIN') do
  begin
    if MatchUpper('DECLARE') then
    begin
      if PeekTok.UpperText = 'CURSOR' then
      begin
        CollectTokensUntil('', '', ';', False, EndLine);
        MatchSymbol(';');
      end
      else
        ParseDeclareVariable;
    end
    else
      NextTok;
  end;

  FRootStmt := ParseStatement;
  if FRootStmt <> nil then
  begin
    FState := dsIdle;
    FCurrentLine := FRootStmt.Line;
  end
  else
  begin
    FState := dsError;
    FLastError := 'Não foi possível localizar o bloco BEGIN..END da trigger.';
  end;
end;

procedure TPsqlDebugger.Start;
var
  I: Integer;
  V: TDebugVariable;
  IsNull: Boolean;
  Val: string;
begin
  if FRootStmt = nil then
    Exit;
  ClearStack;
  ClearSuspendedRows;
  FStepCount := 0;
  FLastError := '';

  for I := 0 to FVars.Count - 1 do
  begin
    V := TDebugVariable(FVars[I]);
    if (V.Scope = dvsLocal) and (V.InitExpr <> '') then
    begin
      if EvalExpression(V.InitExpr, IsNull, Val) then
      begin
        V.IsNull := IsNull;
        V.Value := Val;
      end;
    end;
  end;

  if FRootStmt.Kind = pskBlock then
    PushFrame(dfkBlock, FRootStmt)
  else
  begin
    { Wrap single statement }
    PushFrame(dfkBlock, FRootStmt);
  end;
  FState := dsPaused;
  UpdateCurrentLineFromTopFrame;
end;

procedure TPsqlDebugger.StepInto;
var
  Executed: Boolean;
begin
  if FState = dsIdle then
  begin
    Start;
    Exit;
  end;
  if FState <> dsPaused then
    Exit;

  if not AdvanceToNextExecutable(Executed) then
    Exit;

  if FStack.Count = 0 then
    FState := dsFinished;
end;

procedure TPsqlDebugger.StepOver;
begin
  StepInto;
end;

procedure TPsqlDebugger.RequestStop;
begin
  FStopRequested := True;
end;

procedure TPsqlDebugger.Run;
var
  Executed: Boolean;
  IterCount: Integer;
begin
  if FState = dsIdle then
    Start;
  if FState <> dsPaused then
    Exit;

  FStopRequested := False;
  IterCount := 0;
  while (FState = dsPaused) and (not FStopRequested) do
  begin
    if not AdvanceToNextExecutable(Executed) then
      Exit;
    if FState <> dsPaused then
      Break;
    if HasBreakpoint(FCurrentLine) then
      Break;
    Inc(IterCount);
    if (IterCount mod 16 = 0) and Assigned(FOnYield) then
      FOnYield(Self);
  end;
end;

procedure TPsqlDebugger.RunToLine(const ATargetLine: Integer);
var
  Executed: Boolean;
  IterCount: Integer;
begin
  if FState = dsIdle then
    Start;
  if FState <> dsPaused then
    Exit;

  FStopRequested := False;
  IterCount := 0;
  while (FState = dsPaused) and (not FStopRequested) do
  begin
    if not AdvanceToNextExecutable(Executed) then
      Exit;
    if FState <> dsPaused then
      Break;
    if (FCurrentLine = ATargetLine) or HasBreakpoint(FCurrentLine) then
      Break;
    Inc(IterCount);
    if (IterCount mod 16 = 0) and Assigned(FOnYield) then
      FOnYield(Self);
  end;
end;

procedure TPsqlDebugger.Stop;
begin
  ClearStack;
  FState := dsIdle;
  if FRootStmt <> nil then
    FCurrentLine := FRootStmt.Line
  else
    FCurrentLine := 0;
end;

procedure TPsqlDebugger.ToggleBreakpoint(const ALine: Integer);
var
  Key: string;
  Idx: Integer;
begin
  if ALine <= 0 then
    Exit;
  Key := IntToStr(ALine);
  Idx := FBreakpoints.IndexOf(Key);
  if Idx >= 0 then
    FBreakpoints.Delete(Idx)
  else
    FBreakpoints.Add(Key);
end;

function TPsqlDebugger.HasBreakpoint(const ALine: Integer): Boolean;
begin
  Result := FBreakpoints.IndexOf(IntToStr(ALine)) >= 0;
end;

procedure TPsqlDebugger.ClearBreakpoints;
begin
  FBreakpoints.Clear;
end;

function TPsqlDebugger.VarCount: Integer;
begin
  Result := FVars.Count;
end;

function TPsqlDebugger.GetVar(const AIndex: Integer): TDebugVariable;
begin
  Result := TDebugVariable(FVars[AIndex]);
end;

function TPsqlDebugger.CursorFieldCount: Integer;
begin
  Result := Length(FCursorFields);
end;

function TPsqlDebugger.GetCursorField(const AIndex: Integer): TDebugFieldEntry;
begin
  Result := FCursorFields[AIndex];
end;

function TPsqlDebugger.OutputColCount: Integer;
begin
  Result := Length(FOutputColNames);
end;

function TPsqlDebugger.GetOutputColName(const AIndex: Integer): string;
begin
  Result := FOutputColNames[AIndex];
end;

function TPsqlDebugger.SuspendedRowCount: Integer;
begin
  Result := Length(FSuspendedRows);
end;

function TPsqlDebugger.GetSuspendedCell(const ARow, ACol: Integer): string;
begin
  Result := FSuspendedRows[ARow][ACol];
end;

end.
