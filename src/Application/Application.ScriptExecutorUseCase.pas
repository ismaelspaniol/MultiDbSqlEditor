unit Application.ScriptExecutorUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  Math,
  Domain.DatabaseTypes,
  Domain.Interfaces,
  Domain.QueryResult,
  Domain.ScriptExecutionTypes,
  Application.AsyncQueryRunner;

const
  SCRIPT_SELECT_MEMORY_LIMIT_BYTES = Int64(16) * 1024 * 1024;
  MAX_SCRIPT_INPUT_DEPTH = 8;

type
  TScriptProgressEvent = procedure(
    const ANewOutcomes: TScriptStatementOutcomeArray;
    const AExecutedCount, ATotalCount: Integer
  ) of object;

  TScriptErrorPromptEvent = procedure(
    const AOutcome: TScriptStatementOutcome;
    out AAction: TScriptErrorAction
  ) of object;

  TScriptCompletedEvent = procedure(
    const AWorker: TObject;
    const ASummary: TScriptExecutionSummary
  ) of object;

  { Worker em segundo plano para executar scripts SQL (estilo IBExpert Script Executive) }
  TScriptExecutorWorker = class(TThread)
  private
    FSession: IDatabaseSession;
    FDbType: TDatabaseType;
    FStatements: TParsedScriptStatementArray;
    FOptions: TScriptExecutionOptions;
    FLock: TCriticalSection;
    FCancelRequested: Boolean;
    FPaused: Boolean;
    FDetached: Boolean;
    FCurrentIndex: Integer;
    FCurrentFile: string;
    FCurrentSqlPreview: string;
    FPendingOutcomes: TScriptStatementOutcomeArray;
    FSummary: TScriptExecutionSummary;
    FPromptOutcome: TScriptStatementOutcome;
    FPromptAction: TScriptErrorAction;
    FOnProgress: TScriptProgressEvent;
    FOnErrorPrompt: TScriptErrorPromptEvent;
    FOnComplete: TScriptCompletedEvent;
    function IsCancelRequested: Boolean;
    function IsDetached: Boolean;
    procedure PushOutcome(const AOutcome: TScriptStatementOutcome);
    procedure DeliverProgressOnMainThread;
    procedure AskErrorOnMainThread;
    procedure CleanupDetachedResources;
    procedure FinishOnMainThread;
    procedure ExecuteSavepointSql(const ASql: string);
  protected
    procedure Execute; override;
  public
    constructor Create(
      const ASession: IDatabaseSession;
      const ADbType: TDatabaseType;
      const AStatements: TParsedScriptStatementArray;
      const AOptions: TScriptExecutionOptions;
      const AOnProgress: TScriptProgressEvent;
      const AOnComplete: TScriptCompletedEvent;
      const AOnErrorPrompt: TScriptErrorPromptEvent = nil
    );
    destructor Destroy; override;
    procedure MarkCancelRequested;
    procedure SetPaused(const APaused: Boolean);
    function IsPaused: Boolean;
    procedure GetCurrentStatus(out AIndex, ATotal: Integer; out AFile, ASqlPreview: string);
    procedure DetachAndCancel;
  end;

function ParseSqlScriptWithLines(
  const AScript: string;
  const ADbType: TDatabaseType;
  const ASourceFile: string = '';
  const ABaseDir: string = '';
  const AExpandInputDirectives: Boolean = True;
  const ADepth: Integer = 0
): TParsedScriptStatementArray;

function ParseSqlFilesBatch(
  const AFilePaths: TStrings;
  const ADbType: TDatabaseType;
  const AExpandInputDirectives: Boolean = True
): TParsedScriptStatementArray;

implementation

procedure ExtractLeadingWords(const AText: string; out W0, W1, W2: string; out AWordCount: Integer);
var
  I, Len, StartIdx: Integer;

  procedure SkipIgnorable;
  begin
    while I <= Len do
    begin
      if AText[I] in [' ', #9, #10, #13] then
      begin
        Inc(I);
        Continue;
      end;
      if (I < Len) and (AText[I] = '-') and (AText[I + 1] = '-') then
      begin
        Inc(I, 2);
        while (I <= Len) and (AText[I] <> #10) do
          Inc(I);
        Continue;
      end;
      if (I < Len) and (AText[I] = '/') and (AText[I + 1] = '*') then
      begin
        Inc(I, 2);
        while (I < Len) and not ((AText[I] = '*') and (AText[I + 1] = '/')) do
          Inc(I);
        if I < Len then
          Inc(I, 2)
        else
          I := Len + 1;
        Continue;
      end;
      Break;
    end;
  end;

  function NextToken: string;
  begin
    SkipIgnorable;
    if I > Len then
      Exit('');
    StartIdx := I;
    while (I <= Len) and not (AText[I] in [' ', #9, #10, #13]) do
      Inc(I);
    Result := Copy(AText, StartIdx, I - StartIdx);
  end;

var
  Dummy: string;
begin
  W0 := '';
  W1 := '';
  W2 := '';
  AWordCount := 0;
  Len := Length(AText);
  I := 1;

  W0 := NextToken;
  if W0 = '' then
    Exit;
  Inc(AWordCount);

  W1 := NextToken;
  if W1 = '' then
    Exit;
  Inc(AWordCount);

  W2 := NextToken;
  if W2 = '' then
    Exit;
  Inc(AWordCount);

  Dummy := NextToken;
  if Dummy <> '' then
    Inc(AWordCount);
end;

function ExtractInputFileArgument(const AText: string): string;
var
  I, Len, StartIdx: Integer;
  QuoteCh: Char;
begin
  Result := '';
  Len := Length(AText);
  I := 1;

  while I <= Len do
  begin
    if AText[I] in [' ', #9, #10, #13] then
      Inc(I)
    else if (I < Len) and (AText[I] = '-') and (AText[I + 1] = '-') then
    begin
      Inc(I, 2);
      while (I <= Len) and (AText[I] <> #10) do
        Inc(I);
    end
    else if (I < Len) and (AText[I] = '/') and (AText[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I < Len) and not ((AText[I] = '*') and (AText[I + 1] = '/')) do
        Inc(I);
      if I < Len then
        Inc(I, 2)
      else
        I := Len + 1;
    end
    else
      Break;
  end;

  { Pula palavra-chave INPUT }
  while (I <= Len) and not (AText[I] in [' ', #9, #10, #13]) do
    Inc(I);
  while (I <= Len) and (AText[I] in [' ', #9, #10, #13]) do
    Inc(I);
  if I > Len then
    Exit;

  if AText[I] in ['''', '"'] then
  begin
    QuoteCh := AText[I];
    Inc(I);
    StartIdx := I;
    while (I <= Len) and (AText[I] <> QuoteCh) do
      Inc(I);
    Result := Copy(AText, StartIdx, I - StartIdx);
  end
  else
  begin
    StartIdx := I;
    while (I <= Len) and not (AText[I] in [' ', #9, ';', #10, #13]) do
      Inc(I);
    Result := Trim(Copy(AText, StartIdx, I - StartIdx));
  end;
end;

function ResolveIncludedPath(const ARawArg, ABaseDir: string): string;
var
  Cleaned: string;
  IsAbs: Boolean;
begin
  Cleaned := Trim(ARawArg);
  {$IFNDEF WINDOWS}
  Cleaned := StringReplace(Cleaned, '\', DirectorySeparator, [rfReplaceAll]);
  {$ELSE}
  Cleaned := StringReplace(Cleaned, '/', DirectorySeparator, [rfReplaceAll]);
  {$ENDIF}
  if Cleaned = '' then
    Exit('');

  {$IFDEF WINDOWS}
  IsAbs := ((Length(Cleaned) >= 2) and (Cleaned[2] = ':')) or
           ((Length(Cleaned) >= 2) and (Cleaned[1] = '\') and (Cleaned[2] = '\'));
  {$ELSE}
  IsAbs := Cleaned[1] = '/';
  {$ENDIF}

  if (not IsAbs) and (Trim(ABaseDir) <> '') then
    Result := ExpandFileName(IncludeTrailingPathDelimiter(ABaseDir) + Cleaned)
  else
    Result := ExpandFileName(Cleaned);
end;

function IsFirebirdClientDirective(const W0, W1: string; const ADbType: TDatabaseType): Boolean;
var
  Up1: string;
begin
  Result := False;
  if (ADbType <> dtFirebird) or (not SameText(W0, 'SET')) then
    Exit;
  Up1 := UpperCase(W1);
  Result :=
    (Up1 = 'AUTODDL') or
    (Up1 = 'ECHO') or
    (Up1 = 'HEADING') or
    (Up1 = 'HEADINGS') or
    (Up1 = 'STAT') or
    (Up1 = 'STATS') or
    (Up1 = 'STATISTICS') or
    (Up1 = 'PLAN') or
    (Up1 = 'PLANONLY') or
    (Up1 = 'BAIL') or
    (Up1 = 'COUNT') or
    (Up1 = 'LIST') or
    (Up1 = 'NAMES') or
    (Up1 = 'SQL') or
    (Up1 = 'WIDTH') or
    (Up1 = 'WARNINGS') or
    (Up1 = 'TIME') or
    (Up1 = 'MAXROWS');
end;

function ParseSqlScriptWithLines(
  const AScript: string;
  const ADbType: TDatabaseType;
  const ASourceFile: string;
  const ABaseDir: string;
  const AExpandInputDirectives: Boolean;
  const ADepth: Integer
): TParsedScriptStatementArray;
var
  I, Len, CurLine, StartPos, StartLine, StmtEndLine, J, K, MatchedLen: Integer;
  Term, DollarTag, CurRaw: string;
  InSingleQuote, InDoubleQuote, InLineComment, InBlockComment, HasToken: Boolean;
  Count: Integer;

  procedure StepChar;
  begin
    if I > Len then
      Exit;
    if (AScript[I] = #13) and (I < Len) and (AScript[I + 1] = #10) then
    begin
      Inc(CurLine);
      Inc(I, 2);
    end
    else if (AScript[I] = #10) or (AScript[I] = #13) then
    begin
      Inc(CurLine);
      Inc(I);
    end
    else
      Inc(I);
  end;

  function StartsWithAt(const APos: Integer; const APat: string): Boolean;
  begin
    if (APat = '') or (APos < 1) or (APos + Length(APat) - 1 > Len) then
      Exit(False);
    Result := Copy(AScript, APos, Length(APat)) = APat;
  end;

  procedure AppendParsedArray(const ASrc: TParsedScriptStatementArray);
  var
    M, OldCount: Integer;
  begin
    if Length(ASrc) = 0 then
      Exit;
    OldCount := Count;
    Inc(Count, Length(ASrc));
    SetLength(Result, Count);
    for M := 0 to High(ASrc) do
    begin
      Result[OldCount + M] := ASrc[M];
      Result[OldCount + M].Index := OldCount + M + 1;
    end;
  end;

  procedure PushStatement(const ARawText: string; const AStartLine, AEndLine: Integer);
  var
    Trimmed, W0, W1, W2, IncArg, ResolvedPath: string;
    WordCount: Integer;
    Kind: TScriptStatementKind;
    SL: TStringList;
    ChildStmts: TParsedScriptStatementArray;
  begin
    Trimmed := Trim(ARawText);
    if Trimmed = '' then
      Exit;

    ExtractLeadingWords(Trimmed, W0, W1, W2, WordCount);
    if W0 = '' then
      Exit;

    if (ADbType = dtFirebird) and SameText(W0, 'SET') and SameText(W1, 'TERM') then
    begin
      if W2 <> '' then
        Term := W2;
      Exit;
    end;

    if IsFirebirdClientDirective(W0, W1, ADbType) then
      Exit;

    if AExpandInputDirectives and SameText(W0, 'INPUT') and (WordCount >= 2) then
    begin
      IncArg := ExtractInputFileArgument(Trimmed);
      ResolvedPath := ResolveIncludedPath(IncArg, ABaseDir);
      if ADepth >= MAX_SCRIPT_INPUT_DEPTH then
        raise Exception.CreateFmt('Limite de aninhamento de diretivas INPUT (%d) excedido ao incluir "%s".',
          [MAX_SCRIPT_INPUT_DEPTH, ResolvedPath]);
      if (ResolvedPath = '') or (not FileExists(ResolvedPath)) then
        raise Exception.CreateFmt('Arquivo incluído via INPUT não encontrado: "%s" (%s linha %d).',
          [ResolvedPath, ASourceFile, AStartLine]);

      SL := TStringList.Create;
      try
        SL.LoadFromFile(ResolvedPath);
        ChildStmts := ParseSqlScriptWithLines(
          SL.Text,
          ADbType,
          ExtractFileName(ResolvedPath),
          ExtractFilePath(ResolvedPath),
          True,
          ADepth + 1
        );
      finally
        SL.Free;
      end;
      AppendParsedArray(ChildStmts);
      Exit;
    end;

    if SameText(W0, 'COMMIT') and
       ((WordCount = 1) or ((WordCount = 2) and (SameText(W1, 'WORK') or SameText(W1, 'TRANSACTION')))) then
      Kind := sskCommit
    else if SameText(W0, 'ROLLBACK') and
            ((WordCount = 1) or ((WordCount = 2) and (SameText(W1, 'WORK') or SameText(W1, 'TRANSACTION')))) then
      Kind := sskRollback
    else
      Kind := sskSql;

    Inc(Count);
    SetLength(Result, Count);
    Result[Count - 1].Index := Count;
    Result[Count - 1].SourceFile := ASourceFile;
    Result[Count - 1].StartLine := AStartLine;
    Result[Count - 1].EndLine := AEndLine;
    Result[Count - 1].Kind := Kind;
    Result[Count - 1].SqlText := Trimmed;
  end;

  procedure FlushStmt(const AEndIdx, AOldTermLen, AEndLine: Integer);
  var
    RawText: string;
  begin
    if HasToken and (AEndIdx >= StartPos) then
      RawText := Copy(AScript, StartPos, AEndIdx - StartPos + 1)
    else
      RawText := '';
    HasToken := False;
    StartPos := AEndIdx + 1 + AOldTermLen;
    if Trim(RawText) <> '' then
      PushStatement(RawText, StartLine, AEndLine);
  end;

begin
  SetLength(Result, 0);
  Count := 0;
  Len := Length(AScript);
  if Len = 0 then
    Exit;

  Term := ';';
  I := 1;
  CurLine := 1;
  StartPos := 1;
  StartLine := 1;
  StmtEndLine := 1;
  InSingleQuote := False;
  InDoubleQuote := False;
  InLineComment := False;
  InBlockComment := False;
  DollarTag := '';
  HasToken := False;

  while I <= Len do
  begin
    if InLineComment then
    begin
      if (AScript[I] = #10) or (AScript[I] = #13) then
        InLineComment := False;
      StepChar;
      Continue;
    end;

    if InBlockComment then
    begin
      if (I < Len) and (AScript[I] = '*') and (AScript[I + 1] = '/') then
      begin
        InBlockComment := False;
        Inc(I, 2);
      end
      else
        StepChar;
      Continue;
    end;

    if DollarTag <> '' then
    begin
      if StartsWithAt(I, DollarTag) then
      begin
        MatchedLen := Length(DollarTag);
        for K := 1 to MatchedLen do
          StepChar;
        DollarTag := '';
        StmtEndLine := CurLine;
      end
      else
      begin
        StepChar;
        StmtEndLine := CurLine;
      end;
      Continue;
    end;

    if InSingleQuote then
    begin
      if AScript[I] = '''' then
      begin
        if (I < Len) and (AScript[I + 1] = '''') then
          Inc(I, 2)
        else
        begin
          InSingleQuote := False;
          Inc(I);
        end;
      end
      else
        StepChar;
      StmtEndLine := CurLine;
      Continue;
    end;

    if InDoubleQuote then
    begin
      if AScript[I] = '"' then
      begin
        if (I < Len) and (AScript[I + 1] = '"') then
          Inc(I, 2)
        else
        begin
          InDoubleQuote := False;
          Inc(I);
        end;
      end
      else
        StepChar;
      StmtEndLine := CurLine;
      Continue;
    end;

    { Comentários }
    if (I < Len) and (AScript[I] = '-') and (AScript[I + 1] = '-') then
    begin
      InLineComment := True;
      Inc(I, 2);
      Continue;
    end;
    if (I < Len) and (AScript[I] = '/') and (AScript[I + 1] = '*') then
    begin
      InBlockComment := True;
      Inc(I, 2);
      Continue;
    end;

    { Strings e identificadores }
    if AScript[I] = '''' then
    begin
      if not HasToken then
      begin
        HasToken := True;
        StartPos := I;
        StartLine := CurLine;
      end;
      InSingleQuote := True;
      StmtEndLine := CurLine;
      Inc(I);
      Continue;
    end;
    if AScript[I] = '"' then
    begin
      if not HasToken then
      begin
        HasToken := True;
        StartPos := I;
        StartLine := CurLine;
      end;
      InDoubleQuote := True;
      StmtEndLine := CurLine;
      Inc(I);
      Continue;
    end;

    { Dollar-quoting PostgreSQL }
    if (ADbType = dtPostgreSQL) and (AScript[I] = '$') then
    begin
      J := I + 1;
      while (J <= Len) and (AScript[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(J);
      if (J <= Len) and (AScript[J] = '$') then
      begin
        if not HasToken then
        begin
          HasToken := True;
          StartPos := I;
          StartLine := CurLine;
        end;
        DollarTag := Copy(AScript, I, J - I + 1);
        StmtEndLine := CurLine;
        I := J + 1;
        Continue;
      end;
    end;

    { Terminador atual (; ou definido via SET TERM) }
    if StartsWithAt(I, Term) then
    begin
      MatchedLen := Length(Term);
      if HasToken then
        FlushStmt(I - 1, MatchedLen, CurLine)
      else
        StartPos := I + MatchedLen;
      for K := 1 to MatchedLen do
        StepChar;
      Continue;
    end;

    if not (AScript[I] in [' ', #9, #10, #13]) then
    begin
      if not HasToken then
      begin
        HasToken := True;
        StartPos := I;
        StartLine := CurLine;
      end;
      StmtEndLine := CurLine;
    end;
    StepChar;
  end;

  if HasToken and (StartPos <= Len) then
  begin
    CurRaw := Copy(AScript, StartPos, Len - StartPos + 1);
    if Trim(CurRaw) <> '' then
      PushStatement(CurRaw, StartLine, StmtEndLine);
  end;
end;

function ParseSqlFilesBatch(
  const AFilePaths: TStrings;
  const ADbType: TDatabaseType;
  const AExpandInputDirectives: Boolean
): TParsedScriptStatementArray;
var
  I, J, OldCount: Integer;
  Path: string;
  SL: TStringList;
  FileStmts: TParsedScriptStatementArray;
begin
  SetLength(Result, 0);
  if AFilePaths = nil then
    Exit;

  SL := TStringList.Create;
  try
    for I := 0 to AFilePaths.Count - 1 do
    begin
      Path := Trim(AFilePaths[I]);
      if Path = '' then
        Continue;
      if not FileExists(Path) then
        raise Exception.CreateFmt('Arquivo de script não encontrado: "%s"', [Path]);

      SL.LoadFromFile(Path);
      FileStmts := ParseSqlScriptWithLines(
        SL.Text,
        ADbType,
        ExtractFileName(Path),
        ExtractFilePath(Path),
        AExpandInputDirectives,
        0
      );
      if Length(FileStmts) > 0 then
      begin
        OldCount := Length(Result);
        SetLength(Result, OldCount + Length(FileStmts));
        for J := 0 to High(FileStmts) do
        begin
          Result[OldCount + J] := FileStmts[J];
          Result[OldCount + J].Index := OldCount + J + 1;
        end;
      end;
    end;
  finally
    SL.Free;
  end;
end;

{ TScriptExecutorWorker }

constructor TScriptExecutorWorker.Create(
  const ASession: IDatabaseSession;
  const ADbType: TDatabaseType;
  const AStatements: TParsedScriptStatementArray;
  const AOptions: TScriptExecutionOptions;
  const AOnProgress: TScriptProgressEvent;
  const AOnComplete: TScriptCompletedEvent;
  const AOnErrorPrompt: TScriptErrorPromptEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FSession := ASession;
  FDbType := ADbType;
  FStatements := Copy(AStatements, 0, Length(AStatements));
  FOptions := AOptions;
  FCancelRequested := False;
  FPaused := False;
  FDetached := False;
  FCurrentIndex := 0;
  FCurrentFile := '';
  FCurrentSqlPreview := '';
  SetLength(FPendingOutcomes, 0);
  FSummary := DefaultScriptExecutionSummary;
  FSummary.TotalStatements := Length(FStatements);
  FOnProgress := AOnProgress;
  FOnErrorPrompt := AOnErrorPrompt;
  FOnComplete := AOnComplete;
end;

destructor TScriptExecutorWorker.Destroy;
begin
  FSession := nil;
  FLock.Free;
  inherited Destroy;
end;

function TScriptExecutorWorker.IsCancelRequested: Boolean;
begin
  FLock.Acquire;
  try
    Result := FCancelRequested;
  finally
    FLock.Release;
  end;
end;

function TScriptExecutorWorker.IsDetached: Boolean;
begin
  FLock.Acquire;
  try
    Result := FDetached;
  finally
    FLock.Release;
  end;
end;

procedure TScriptExecutorWorker.MarkCancelRequested;
begin
  FLock.Acquire;
  try
    FCancelRequested := True;
    FPaused := False;
  finally
    FLock.Release;
  end;
end;

procedure TScriptExecutorWorker.SetPaused(const APaused: Boolean);
begin
  FLock.Acquire;
  try
    FPaused := APaused;
  finally
    FLock.Release;
  end;
end;

function TScriptExecutorWorker.IsPaused: Boolean;
begin
  FLock.Acquire;
  try
    Result := FPaused;
  finally
    FLock.Release;
  end;
end;

procedure TScriptExecutorWorker.GetCurrentStatus(
  out AIndex, ATotal: Integer;
  out AFile, ASqlPreview: string
);
begin
  FLock.Acquire;
  try
    AIndex := FCurrentIndex;
    ATotal := FSummary.TotalStatements;
    AFile := FCurrentFile;
    ASqlPreview := FCurrentSqlPreview;
  finally
    FLock.Release;
  end;
end;

procedure TScriptExecutorWorker.DetachAndCancel;
var
  SessionRef: IDatabaseSession;
  CancelWorker: TCancelQueryWorker;
begin
  FLock.Acquire;
  try
    FDetached := True;
    FCancelRequested := True;
    FPaused := False;
    FOnProgress := nil;
    FOnErrorPrompt := nil;
    FOnComplete := nil;
    SessionRef := FSession;
  finally
    FLock.Release;
  end;

  if SessionRef <> nil then
  begin
    CancelWorker := TCancelQueryWorker.Create(SessionRef, nil);
    CancelWorker.Detach;
    CancelWorker.Start;
  end;
end;

procedure TScriptExecutorWorker.PushOutcome(const AOutcome: TScriptStatementOutcome);
var
  ShouldQueue: Boolean;
  Idx: Integer;
begin
  FLock.Acquire;
  try
    if FDetached then
      Exit;
    ShouldQueue := (Length(FPendingOutcomes) = 0) and Assigned(FOnProgress);
    Idx := Length(FPendingOutcomes);
    SetLength(FPendingOutcomes, Idx + 1);
    FPendingOutcomes[Idx] := AOutcome;
  finally
    FLock.Release;
  end;

  if ShouldQueue then
    Queue(nil, @DeliverProgressOnMainThread);
end;

procedure TScriptExecutorWorker.DeliverProgressOnMainThread;
var
  Batch: TScriptStatementOutcomeArray;
  ExecCount, TotalCount: Integer;
  Cb: TScriptProgressEvent;
  WasDetached: Boolean;
begin
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Cb := FOnProgress;
    Batch := FPendingOutcomes;
    SetLength(FPendingOutcomes, 0);
    ExecCount := FSummary.ExecutedCount;
    TotalCount := FSummary.TotalStatements;
  finally
    FLock.Release;
  end;

  if (not WasDetached) and (Length(Batch) > 0) and Assigned(Cb) then
    Cb(Batch, ExecCount, TotalCount);
end;

procedure TScriptExecutorWorker.AskErrorOnMainThread;
var
  Cb: TScriptErrorPromptEvent;
  WasDetached, WasCancelled: Boolean;
  OutcomeCopy: TScriptStatementOutcome;
  ActionCopy: TScriptErrorAction;
begin
  FLock.Acquire;
  try
    WasDetached := FDetached;
    WasCancelled := FCancelRequested;
    Cb := FOnErrorPrompt;
    OutcomeCopy := FPromptOutcome;
  finally
    FLock.Release;
  end;

  ActionCopy := seaAbort;
  if (not WasDetached) and (not WasCancelled) and Assigned(Cb) then
    Cb(OutcomeCopy, ActionCopy);

  FLock.Acquire;
  try
    FPromptAction := ActionCopy;
  finally
    FLock.Release;
  end;
end;

procedure TScriptExecutorWorker.CleanupDetachedResources;
begin
  if FSession <> nil then
  begin
    try
      if FSession.InTransaction then
        FSession.Rollback;
      FSession.Disconnect;
    except
    end;
    FSession := nil;
  end;
end;

procedure TScriptExecutorWorker.ExecuteSavepointSql(const ASql: string);
var
  Res: TQueryResult;
begin
  Res := FSession.ExecuteSQL(ASql, False, 0);
  Res.Free;
end;

procedure TScriptExecutorWorker.Execute;
const
  UTF8_BOM: string = #$EF#$BB#$BF;
var
  StartTick, StmtTick: QWord;
  I, UncommittedOk, EveryN: Integer;
  Stmt: TParsedScriptStatement;
  Outcome: TScriptStatementOutcome;
  Res: TQueryResult;
  EffectivePolicy: TScriptErrorPolicy;
  ActionChosen: TScriptErrorAction;
  UsedSavepoint, Ok, AbortedOnError, IsEndOfFile: Boolean;
  MsgText, LogLine: string;
  RowsAff: Int64;
  LogStream: TFileStream;

  procedure WriteLogFileLine(const ALine: string);
  var
    Raw: string;
  begin
    if LogStream = nil then
      Exit;
    try
      Raw := ALine + LineEnding;
      LogStream.WriteBuffer(Raw[1], Length(Raw));
    except
    end;
  end;

begin
  StartTick := GetTickCount64;
  LogStream := nil;
  EffectivePolicy := FOptions.ErrorPolicy;
  EveryN := Max(1, FOptions.CommitEveryN);
  UncommittedOk := 0;
  AbortedOnError := False;

  try
    if Trim(FOptions.LogToFilePath) <> '' then
    begin
      if FOptions.AppendLogFile and FileExists(Trim(FOptions.LogToFilePath)) then
      begin
        LogStream := TFileStream.Create(Trim(FOptions.LogToFilePath), fmOpenReadWrite or fmShareDenyWrite);
        LogStream.Seek(0, soEnd);
        WriteLogFileLine('');
      end
      else
      begin
        LogStream := TFileStream.Create(Trim(FOptions.LogToFilePath), fmCreate);
        LogStream.WriteBuffer(UTF8_BOM[1], Length(UTF8_BOM));
      end;
      if Trim(FOptions.TargetDatabaseName) <> '' then
        WriteLogFileLine(Format('=== Script Executive Log (%s) | Banco: %s ===',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), FOptions.TargetDatabaseName]))
      else
        WriteLogFileLine(Format('=== Script Executive Log (%s) ===',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
      WriteLogFileLine(Format('Modo de transação: %s | Comandos: %d',
        [ScriptCommitModeToStr(FOptions.CommitMode), Length(FStatements)]));
      WriteLogFileLine('');
    end;

    if FSession = nil then
      raise Exception.Create('Nenhuma sessão disponível para executar o script.');

    if not FSession.IsConnected then
      FSession.Connect;

    if (FOptions.CommitMode = scmSingleTransaction) and (not FSession.InTransaction) then
      FSession.StartTransaction;

    for I := 0 to High(FStatements) do
    begin
      while IsPaused and (not IsCancelRequested) and (not IsDetached) do
        Sleep(30);

      if IsCancelRequested or IsDetached then
      begin
        FLock.Acquire;
        try
          FSummary.WasCancelled := True;
        finally
          FLock.Release;
        end;
        Break;
      end;

      Stmt := FStatements[I];

      FLock.Acquire;
      try
        FCurrentIndex := Stmt.Index;
        FCurrentFile := Stmt.SourceFile;
        FCurrentSqlPreview := BuildSqlPreview(Stmt.SqlText);
      finally
        FLock.Release;
      end;

      StmtTick := GetTickCount64;
      Outcome := Default(TScriptStatementOutcome);
      Outcome.Index := Stmt.Index;
      Outcome.SourceFile := Stmt.SourceFile;
      Outcome.StartLine := Stmt.StartLine;
      Outcome.EndLine := Stmt.EndLine;
      Outcome.Kind := Stmt.Kind;
      Outcome.SqlPreview := FCurrentSqlPreview;

      case Stmt.Kind of
        sskCommit:
          begin
            try
              if FSession.InTransaction then
              begin
                FSession.Commit;
                UncommittedOk := 0;
                Outcome.MessageText := 'Transação confirmada (COMMIT).';
              end
              else
                Outcome.MessageText := 'COMMIT ignorado (nenhuma transação ativa).';
              Outcome.Status := sssOk;
            except
              on E: Exception do
              begin
                Outcome.Status := sssError;
                Outcome.MessageText := E.Message;
              end;
            end;
          end;
        sskRollback:
          begin
            try
              if FSession.InTransaction then
              begin
                FSession.Rollback;
                UncommittedOk := 0;
                Outcome.MessageText := 'Transação desfeita (ROLLBACK).';
              end
              else
                Outcome.MessageText := 'ROLLBACK ignorado (nenhuma transação ativa).';
              Outcome.Status := sssOk;
            except
              on E: Exception do
              begin
                Outcome.Status := sssError;
                Outcome.MessageText := E.Message;
              end;
            end;
          end;
      else
        begin
          UsedSavepoint := False;
          Ok := False;
          RowsAff := 0;
          MsgText := '';
          try
            if (FOptions.CommitMode <> scmCommitPerStatement) and
               (EffectivePolicy <> sepStopOnError) and
               (FDbType = dtPostgreSQL) and
               FSession.InTransaction then
            begin
              try
                ExecuteSavepointSql('SAVEPOINT _mdbsql_sc_sp');
                UsedSavepoint := True;
              except
                UsedSavepoint := False;
              end;
            end;

            Res := FSession.ExecuteSQL(Stmt.SqlText, False, 100, SCRIPT_SELECT_MEMORY_LIMIT_BYTES);
            try
              Ok := Res.Success;
              RowsAff := Res.RowsAffected;
              MsgText := Res.MessageText;
            finally
              Res.Free;
            end;

            if UsedSavepoint then
            begin
              try
                if Ok then
                  ExecuteSavepointSql('RELEASE SAVEPOINT _mdbsql_sc_sp')
                else
                begin
                  ExecuteSavepointSql('ROLLBACK TO SAVEPOINT _mdbsql_sc_sp');
                  ExecuteSavepointSql('RELEASE SAVEPOINT _mdbsql_sc_sp');
                end;
              except
              end;
            end;

            if Ok then
            begin
              Inc(UncommittedOk);
              if (FOptions.CommitMode = scmCommitPerStatement) and FSession.InTransaction then
              begin
                FSession.Commit;
                UncommittedOk := 0;
                MsgText := MsgText + ' [Commit]';
              end
              else if (FOptions.CommitMode = scmCommitEveryN) and
                      (UncommittedOk >= EveryN) and
                      FSession.InTransaction then
              begin
                FSession.Commit;
                MsgText := MsgText + Format(' [Commit lote %d]', [UncommittedOk]);
                UncommittedOk := 0;
              end;
            end;

            Outcome.RowsAffected := RowsAff;
            Outcome.MessageText := MsgText;
            if Ok then
              Outcome.Status := sssOk
            else if IsCancelRequested or IsDetached then
              Outcome.Status := sssCancelled
            else
              Outcome.Status := sssError;
          except
            on E: Exception do
            begin
              if UsedSavepoint then
              begin
                try
                  ExecuteSavepointSql('ROLLBACK TO SAVEPOINT _mdbsql_sc_sp');
                  ExecuteSavepointSql('RELEASE SAVEPOINT _mdbsql_sc_sp');
                except
                end;
              end;
              Outcome.MessageText := E.Message;
              if IsCancelRequested or IsDetached then
                Outcome.Status := sssCancelled
              else
                Outcome.Status := sssError;
            end;
          end;
        end;
      end;

      { Commit ao término de cada arquivo no modo Commit por Arquivo quando o comando terminou OK }
      IsEndOfFile := (I = High(FStatements)) or
        (not SameText(FStatements[I + 1].SourceFile, Stmt.SourceFile));
      if (FOptions.CommitMode = scmCommitPerFile) and IsEndOfFile and
         (Outcome.Status = sssOk) and FSession.InTransaction then
      begin
        try
          FSession.Commit;
          UncommittedOk := 0;
          Outcome.MessageText := Outcome.MessageText + ' [Commit arquivo]';
        except
          on E: Exception do
          begin
            Outcome.Status := sssError;
            Outcome.MessageText := 'Erro no COMMIT do arquivo: ' + E.Message;
          end;
        end;
      end;

      Outcome.ElapsedMs := Int64(GetTickCount64 - StmtTick);

      FLock.Acquire;
      try
        Inc(FSummary.ExecutedCount);
        case Outcome.Status of
          sssOk:
            Inc(FSummary.SuccessCount);
          sssError:
            begin
              Inc(FSummary.ErrorCount);
              if FSummary.FirstErrorLine = 0 then
              begin
                FSummary.FirstErrorLine := Outcome.StartLine;
                FSummary.FirstErrorFile := Outcome.SourceFile;
              end;
            end;
          sssCancelled:
            FSummary.WasCancelled := True;
        end;
      finally
        FLock.Release;
      end;

      if Outcome.SourceFile <> '' then
        LogLine := Format('[%s] #%d %s:%d (%d ms): %s | %s', [
          ScriptStatementStatusToStr(Outcome.Status),
          Outcome.Index, Outcome.SourceFile, Outcome.StartLine,
          Outcome.ElapsedMs, Outcome.SqlPreview, Outcome.MessageText
        ])
      else
        LogLine := Format('[%s] #%d Linha %d (%d ms): %s | %s', [
          ScriptStatementStatusToStr(Outcome.Status),
          Outcome.Index, Outcome.StartLine,
          Outcome.ElapsedMs, Outcome.SqlPreview, Outcome.MessageText
        ]);
      WriteLogFileLine(LogLine);

      PushOutcome(Outcome);

      if Outcome.Status = sssCancelled then
        Break;

      if Outcome.Status = sssError then
      begin
        if EffectivePolicy = sepStopOnError then
        begin
          AbortedOnError := True;
          Break;
        end
        else if EffectivePolicy = sepAskUser then
        begin
          if IsDetached or IsCancelRequested or (not Assigned(FOnErrorPrompt)) then
          begin
            AbortedOnError := True;
            Break;
          end;
          Synchronize(@DeliverProgressOnMainThread);
          FLock.Acquire;
          try
            FPromptOutcome := Outcome;
            FPromptAction := seaAbort;
          finally
            FLock.Release;
          end;
          Synchronize(@AskErrorOnMainThread);
          FLock.Acquire;
          try
            ActionChosen := FPromptAction;
          finally
            FLock.Release;
          end;
          if ActionChosen = seaAbort then
          begin
            AbortedOnError := True;
            Break;
          end
          else if ActionChosen = seaIgnoreAll then
            EffectivePolicy := sepIgnoreErrors;
        end;
      end;

      { Se o último comando do arquivo deu erro mas o usuário ignorou, confirma o que já havia dado OK (ou faz rollback se nada deu OK) }
      if (FOptions.CommitMode = scmCommitPerFile) and IsEndOfFile and
         (Outcome.Status = sssError) and FSession.InTransaction then
      begin
        if UncommittedOk > 0 then
        begin
          try
            FSession.Commit;
            UncommittedOk := 0;
            WriteLogFileLine('[COMMIT ARQUIVO] Comandos bem-sucedidos confirmados após ignorar erro no último comando do arquivo.');
          except
          end;
        end
        else
        begin
          try
            FSession.Rollback;
          except
          end;
        end;
      end;
    end;

    if not IsDetached then
    begin
      case FOptions.CommitMode of
        scmSingleTransaction:
          begin
            if FSession.InTransaction then
            begin
              if (FSummary.ErrorCount = 0) and (not FSummary.WasCancelled) then
              begin
                try
                  FSession.Commit;
                  FSummary.CommittedAtEnd := True;
                except
                  on E: Exception do
                  begin
                    Inc(FSummary.ErrorCount);
                    FSummary.FinalMessage := 'Erro no COMMIT final: ' + E.Message;
                  end;
                end;
              end
              else
              begin
                try
                  FSession.Rollback;
                  FSummary.RolledBackOnError := True;
                except
                end;
              end;
            end;
          end;
        scmCommitEveryN:
          begin
            if FSession.InTransaction then
            begin
              if (not FSummary.WasCancelled) and (not AbortedOnError) and (UncommittedOk > 0) then
              begin
                try
                  FSession.Commit;
                  FSummary.CommittedAtEnd := True;
                except
                  on E: Exception do
                  begin
                    Inc(FSummary.ErrorCount);
                    FSummary.FinalMessage := 'Erro no COMMIT final do lote: ' + E.Message;
                  end;
                end;
              end
              else if FSummary.WasCancelled or AbortedOnError then
              begin
                try
                  FSession.Rollback;
                  FSummary.RolledBackOnError := True;
                except
                end;
              end;
            end;
          end;
        scmCommitPerStatement, scmCommitPerFile:
          begin
            if FSession.InTransaction and (FSummary.WasCancelled or AbortedOnError) then
            begin
              try
                FSession.Rollback;
                FSummary.RolledBackOnError := True;
              except
              end;
            end;
          end;
      end;
    end;
  except
    on E: Exception do
    begin
      Inc(FSummary.ErrorCount);
      FSummary.FinalMessage := E.Message;
      WriteLogFileLine('[ERRO FATAL] ' + E.Message);
    end;
  end;

  FLock.Acquire;
  try
    FSummary.TotalElapsedMs := Int64(GetTickCount64 - StartTick);
    if Trim(FSummary.FinalMessage) = '' then
    begin
      if FSummary.WasCancelled then
        FSummary.FinalMessage := Format(
          'Script cancelado após %d/%d comando(s) (%d sucesso(s), %d erro(s)) em %d ms.',
          [FSummary.ExecutedCount, FSummary.TotalStatements, FSummary.SuccessCount,
           FSummary.ErrorCount, FSummary.TotalElapsedMs]
        )
      else if FSummary.ErrorCount > 0 then
        FSummary.FinalMessage := Format(
          'Script finalizado com %d erro(s): %d/%d comando(s) executados em %d ms.',
          [FSummary.ErrorCount, FSummary.ExecutedCount, FSummary.TotalStatements, FSummary.TotalElapsedMs]
        )
      else
        FSummary.FinalMessage := Format(
          'Script concluído com sucesso: %d/%d comando(s) em %d ms.',
          [FSummary.SuccessCount, FSummary.TotalStatements, FSummary.TotalElapsedMs]
        );
    end;
    WriteLogFileLine('');
    WriteLogFileLine('RESUMO: ' + FSummary.FinalMessage);
  finally
    FLock.Release;
    if LogStream <> nil then
      LogStream.Free;
  end;

  if IsDetached then
    CleanupDetachedResources;

  Queue(nil, @FinishOnMainThread);
end;

procedure TScriptExecutorWorker.FinishOnMainThread;
var
  WasDetached: Boolean;
  Cb: TScriptCompletedEvent;
  SummaryCopy: TScriptExecutionSummary;
begin
  DeliverProgressOnMainThread;
  WaitFor;
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Cb := FOnComplete;
    FOnComplete := nil;
    FOnProgress := nil;
    FOnErrorPrompt := nil;
    SummaryCopy := FSummary;
  finally
    FLock.Release;
  end;

  try
    if WasDetached then
      CleanupDetachedResources
    else if Assigned(Cb) then
      Cb(Self, SummaryCopy);
  finally
    Free;
  end;
end;

end.
