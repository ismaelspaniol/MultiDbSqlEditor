unit Domain.ScriptExecutionTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TScriptCommitMode = (
    scmSingleTransaction,
    scmCommitPerStatement,
    scmCommitEveryN,
    scmCommitPerFile,
    scmManual
  );

  TScriptErrorPolicy = (
    sepStopOnError,
    sepAskUser,
    sepIgnoreErrors
  );

  TScriptErrorAction = (
    seaAbort,
    seaIgnoreOne,
    seaIgnoreAll
  );

  TScriptStatementKind = (sskSql, sskCommit, sskRollback);

  TParsedScriptStatement = record
    Index: Integer;
    SourceFile: string;
    StartLine: Integer;
    EndLine: Integer;
    Kind: TScriptStatementKind;
    SqlText: string;
  end;
  TParsedScriptStatementArray = array of TParsedScriptStatement;

  TScriptExecutionOptions = record
    CommitMode: TScriptCommitMode;
    CommitEveryN: Integer;
    ErrorPolicy: TScriptErrorPolicy;
    EchoSqlInLog: Boolean;
    LogToFilePath: string;
  end;

  TScriptStatementStatus = (sssOk, sssError, sssCancelled);

  TScriptStatementOutcome = record
    Index: Integer;
    SourceFile: string;
    StartLine: Integer;
    EndLine: Integer;
    Kind: TScriptStatementKind;
    Status: TScriptStatementStatus;
    ElapsedMs: Int64;
    RowsAffected: Int64;
    SqlPreview: string;
    MessageText: string;
  end;
  TScriptStatementOutcomeArray = array of TScriptStatementOutcome;

  TScriptExecutionSummary = record
    TotalStatements: Integer;
    ExecutedCount: Integer;
    SuccessCount: Integer;
    ErrorCount: Integer;
    WasCancelled: Boolean;
    CommittedAtEnd: Boolean;
    RolledBackOnError: Boolean;
    TotalElapsedMs: Int64;
    FirstErrorLine: Integer;
    FirstErrorFile: string;
    FinalMessage: string;
  end;

function DefaultScriptExecutionOptions: TScriptExecutionOptions;
function DefaultScriptExecutionSummary: TScriptExecutionSummary;
function ScriptCommitModeToStr(const AMode: TScriptCommitMode): string;
function ScriptErrorPolicyToStr(const APolicy: TScriptErrorPolicy): string;
function ScriptStatementStatusToStr(const AStatus: TScriptStatementStatus): string;
function BuildSqlPreview(const ASQL: string; const AMaxLen: Integer = 110): string;

implementation

function DefaultScriptExecutionOptions: TScriptExecutionOptions;
begin
  Result := Default(TScriptExecutionOptions);
  Result.CommitMode := scmSingleTransaction;
  Result.CommitEveryN := 1000;
  Result.ErrorPolicy := sepStopOnError;
  Result.EchoSqlInLog := True;
  Result.LogToFilePath := '';
end;

function DefaultScriptExecutionSummary: TScriptExecutionSummary;
begin
  Result := Default(TScriptExecutionSummary);
  Result.FirstErrorLine := 0;
  Result.FirstErrorFile := '';
end;

function ScriptCommitModeToStr(const AMode: TScriptCommitMode): string;
begin
  case AMode of
    scmSingleTransaction: Result := 'Commit ao final (transação única)';
    scmCommitPerStatement: Result := 'Commit por comando';
    scmCommitEveryN: Result := 'Commit a cada N comandos';
    scmCommitPerFile: Result := 'Commit por arquivo .sql';
    scmManual: Result := 'Manual (respeitar apenas COMMIT/ROLLBACK do script)';
  else
    Result := '';
  end;
end;

function ScriptErrorPolicyToStr(const APolicy: TScriptErrorPolicy): string;
begin
  case APolicy of
    sepStopOnError: Result := 'Parar no erro';
    sepAskUser: Result := 'Perguntar ao usuário';
    sepIgnoreErrors: Result := 'Ignorar erros e continuar';
  else
    Result := '';
  end;
end;

function ScriptStatementStatusToStr(const AStatus: TScriptStatementStatus): string;
begin
  case AStatus of
    sssOk: Result := 'OK';
    sssError: Result := 'ERRO';
    sssCancelled: Result := 'CANCELADO';
  else
    Result := '';
  end;
end;

function BuildSqlPreview(const ASQL: string; const AMaxLen: Integer): string;
var
  I: Integer;
  InSpace: Boolean;
  C: Char;
begin
  Result := '';
  InSpace := True;
  for I := 1 to Length(ASQL) do
  begin
    C := ASQL[I];
    if C in [' ', #9, #10, #13] then
    begin
      if not InSpace then
      begin
        Result := Result + ' ';
        InSpace := True;
      end;
    end
    else
    begin
      Result := Result + C;
      InSpace := False;
    end;
    if (AMaxLen > 0) and (Length(Result) >= AMaxLen) then
    begin
      Result := TrimRight(Result) + '...';
      Exit;
    end;
  end;
  Result := Trim(Result);
end;

end.
