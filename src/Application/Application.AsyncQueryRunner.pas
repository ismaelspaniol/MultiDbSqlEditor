unit Application.AsyncQueryRunner;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  Domain.Interfaces,
  Domain.QueryResult,
  Application.ExecuteQueryUseCase;

type
  TAsyncQueryMode = (aqmExecuteSQL, aqmFetchAll);

  TAsyncSqlWorker = class;
  TCancelQueryWorker = class;

  TAsyncSqlCompletedEvent = procedure(const AWorker: TAsyncSqlWorker) of object;
  TAsyncCancelDoneEvent = procedure(
    const AWorker: TCancelQueryWorker;
    const ASuccess: Boolean;
    const AMessage: string
  ) of object;

  { Thread secundária para enviar sinal de cancelamento ao servidor sem travar a GUI }
  TCancelQueryWorker = class(TThread)
  private
    FSession: IDatabaseSession;
    FLock: TCriticalSection;
    FDetached: Boolean;
    FOnDone: TAsyncCancelDoneEvent;
    FSuccess: Boolean;
    FMessage: string;
    procedure FinishOnMainThread;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASession: IDatabaseSession; const AOnDone: TAsyncCancelDoneEvent);
    destructor Destroy; override;
    procedure Detach;
  end;

  { Worker assíncrono para execução de SQL ou FetchAll em segundo plano }
  TAsyncSqlWorker = class(TThread)
  private
    FMode: TAsyncQueryMode;
    FSession: IDatabaseSession;
    FSQL: string;
    FAutoCommit: Boolean;
    FBatchSize: Integer;
    FMemoryLimitBytes: Int64;
    FCursor: IResultSetCursor;
    FResult: TQueryResult;
    FErrorMessage: string;
    FElapsedMs: Int64;
    FLock: TCriticalSection;
    FCancelRequested: Boolean;
    FDetached: Boolean;
    FOnComplete: TAsyncSqlCompletedEvent;
    function IsCancelRequested: Boolean;
    function IsDetached: Boolean;
    procedure CleanupDetachedResources;
    procedure FinishOnMainThread;
  protected
    procedure Execute; override;
  public
    constructor CreateExecuteSQL(
      const ASession: IDatabaseSession;
      const ASQL: string;
      const AAutoCommit: Boolean;
      const ABatchSize: Integer;
      const AOnComplete: TAsyncSqlCompletedEvent;
      const AMemoryLimitBytes: Int64 = DEFAULT_RESULT_MEMORY_LIMIT_BYTES
    );
    constructor CreateFetchAll(
      const ASession: IDatabaseSession;
      const ACursor: IResultSetCursor;
      const AStagingResult: TQueryResult;
      const AOnComplete: TAsyncSqlCompletedEvent
    );
    destructor Destroy; override;

    function TakeResult: TQueryResult;
    function TakeCursor: IResultSetCursor;
    procedure MarkCancelRequested;
    procedure DetachAndCancel;

    property Mode: TAsyncQueryMode read FMode;
    property ErrorMessage: string read FErrorMessage;
    property ElapsedMs: Int64 read FElapsedMs;
    property WasCancelled: Boolean read IsCancelRequested;
  end;

implementation

{ TCancelQueryWorker }

constructor TCancelQueryWorker.Create(
  const ASession: IDatabaseSession;
  const AOnDone: TAsyncCancelDoneEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FSession := ASession;
  FOnDone := AOnDone;
  FDetached := False;
  FSuccess := False;
  FMessage := '';
end;

destructor TCancelQueryWorker.Destroy;
begin
  FSession := nil;
  FLock.Free;
  inherited Destroy;
end;

procedure TCancelQueryWorker.Detach;
begin
  FLock.Acquire;
  try
    FDetached := True;
    FOnDone := nil;
  finally
    FLock.Release;
  end;
end;

procedure TCancelQueryWorker.Execute;
begin
  try
    if FSession <> nil then
      FSuccess := FSession.CancelRunningQuery(FMessage)
    else
      FMessage := 'Nenhuma sessão disponível para cancelamento.';
  except
    on E: Exception do
    begin
      FSuccess := False;
      FMessage := E.Message;
    end;
  end;
  FSession := nil;
  Queue(nil, @FinishOnMainThread);
end;

procedure TCancelQueryWorker.FinishOnMainThread;
var
  WasDetached: Boolean;
  Callback: TAsyncCancelDoneEvent;
  SuccessCopy: Boolean;
  MsgCopy: string;
begin
  WaitFor;
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Callback := FOnDone;
    FOnDone := nil;
    SuccessCopy := FSuccess;
    MsgCopy := FMessage;
  finally
    FLock.Release;
  end;

  try
    if (not WasDetached) and Assigned(Callback) then
      Callback(Self, SuccessCopy, MsgCopy);
  finally
    Free;
  end;
end;

{ TAsyncSqlWorker }

constructor TAsyncSqlWorker.CreateExecuteSQL(
  const ASession: IDatabaseSession;
  const ASQL: string;
  const AAutoCommit: Boolean;
  const ABatchSize: Integer;
  const AOnComplete: TAsyncSqlCompletedEvent;
  const AMemoryLimitBytes: Int64
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FMode := aqmExecuteSQL;
  FSession := ASession;
  FSQL := ASQL;
  FAutoCommit := AAutoCommit;
  FBatchSize := ABatchSize;
  FMemoryLimitBytes := AMemoryLimitBytes;
  FCursor := nil;
  FResult := nil;
  FErrorMessage := '';
  FElapsedMs := 0;
  FCancelRequested := False;
  FDetached := False;
  FOnComplete := AOnComplete;
end;

constructor TAsyncSqlWorker.CreateFetchAll(
  const ASession: IDatabaseSession;
  const ACursor: IResultSetCursor;
  const AStagingResult: TQueryResult;
  const AOnComplete: TAsyncSqlCompletedEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FMode := aqmFetchAll;
  FSession := ASession;
  FSQL := '';
  FAutoCommit := False;
  FBatchSize := 1000;
  FCursor := ACursor;
  FResult := AStagingResult;
  FErrorMessage := '';
  FElapsedMs := 0;
  FCancelRequested := False;
  FDetached := False;
  FOnComplete := AOnComplete;
end;

destructor TAsyncSqlWorker.Destroy;
begin
  FreeAndNil(FResult);
  FCursor := nil;
  FSession := nil;
  FLock.Free;
  inherited Destroy;
end;

function TAsyncSqlWorker.IsCancelRequested: Boolean;
begin
  FLock.Acquire;
  try
    Result := FCancelRequested;
  finally
    FLock.Release;
  end;
end;

function TAsyncSqlWorker.IsDetached: Boolean;
begin
  FLock.Acquire;
  try
    Result := FDetached;
  finally
    FLock.Release;
  end;
end;

procedure TAsyncSqlWorker.CleanupDetachedResources;
begin
  FreeAndNil(FResult);
  FCursor := nil;
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

function TAsyncSqlWorker.TakeResult: TQueryResult;
begin
  Result := FResult;
  FResult := nil;
end;

function TAsyncSqlWorker.TakeCursor: IResultSetCursor;
begin
  Result := FCursor;
  FCursor := nil;
end;

procedure TAsyncSqlWorker.MarkCancelRequested;
begin
  FLock.Acquire;
  try
    FCancelRequested := True;
  finally
    FLock.Release;
  end;
end;

procedure TAsyncSqlWorker.DetachAndCancel;
var
  SessionRef: IDatabaseSession;
  CancelWorker: TCancelQueryWorker;
begin
  FLock.Acquire;
  try
    FDetached := True;
    FCancelRequested := True;
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

procedure TAsyncSqlWorker.Execute;
var
  StartTick: QWord;
  UseCase: TExecuteQueryUseCase;
  StepCount: Integer;
begin
  StartTick := GetTickCount64;
  try
    if FMode = aqmExecuteSQL then
    begin
      UseCase := TExecuteQueryUseCase.Create;
      try
        FResult := UseCase.Execute(FSession, FSQL, FAutoCommit, FBatchSize, FMemoryLimitBytes);
      finally
        UseCase.Free;
      end;
    end
    else
    begin
      if FResult = nil then
        FResult := TQueryResult.Create;
      while (not IsCancelRequested) and (not IsDetached) and
            (not FResult.IsMemoryLimitReached) and
            (FCursor <> nil) and FCursor.HasMore do
      begin
        StepCount := FCursor.FetchNext(1000, FResult);
        if StepCount <= 0 then
          Break;
      end;
      if FResult.IsMemoryLimitReached then
      begin
        FResult.MarkMemoryLimitReached;
        if (FCursor <> nil) and (not IsDetached) then
          FCursor.RefreshPerformance(FResult);
        if FCursor <> nil then
        begin
          FCursor.CloseCursor;
          FCursor := nil;
        end;
      end
      else if (FCursor <> nil) and FCursor.HasMore and (not IsDetached) then
        FCursor.RefreshPerformance(FResult);
      FResult.ExecutionTimeMs := Int64(GetTickCount64 - StartTick);
      FResult.Success := True;
    end;
  except
    on E: Exception do
    begin
      FErrorMessage := E.Message;
      if FMode = aqmFetchAll then
      begin
        if FResult = nil then
          FResult := TQueryResult.Create;
        FResult.Success := False;
        FResult.MessageText := E.Message;
      end;
    end;
  end;
  FElapsedMs := Int64(GetTickCount64 - StartTick);

  if IsDetached then
    CleanupDetachedResources;

  Queue(nil, @FinishOnMainThread);
end;

procedure TAsyncSqlWorker.FinishOnMainThread;
var
  WasDetached: Boolean;
  Callback: TAsyncSqlCompletedEvent;
begin
  WaitFor;
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Callback := FOnComplete;
    FOnComplete := nil;
  finally
    FLock.Release;
  end;

  try
    if WasDetached then
      CleanupDetachedResources
    else if Assigned(Callback) then
      Callback(Self);
  finally
    Free;
  end;
end;

end.
