unit Application.DatabaseMonitoringUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Domain.DatabaseTypes,
  Domain.QueryResult,
  Domain.MonitoringTypes,
  Domain.Interfaces;

type
  { Caso de uso para Database Monitoring em tempo real (estilo IBExpert) }
  TDatabaseMonitoringUseCase = class
  private
    function FormatMonitorTimestamp(const AValue: string): string;
    function DecodeFbState(const AState: Integer; const AIsStatement: Boolean = False): string;
    function DecodeFbIsolation(const AIsolation: Integer): string;
    procedure RefreshSessionSnapshot(const ASession: IDatabaseSession);
    procedure LoadFirebirdSnapshot(const ASession: IDatabaseSession; const ASnapshot: TMonitoringSnapshot);
    procedure LoadPostgresSnapshot(const ASession: IDatabaseSession; const ASnapshot: TMonitoringSnapshot);
  public
    function CaptureSnapshot(
      const ASession: IDatabaseSession;
      const ADbType: TDatabaseType
    ): TMonitoringSnapshot;
    function TerminateConnection(
      const ASession: IDatabaseSession;
      const ADbType: TDatabaseType;
      const AConnectionId: Int64;
      out AMessage: string
    ): Boolean;
    function CancelStatement(
      const ASession: IDatabaseSession;
      const ADbType: TDatabaseType;
      const AStatementId, AConnectionId: Int64;
      out AMessage: string
    ): Boolean;
    function CancelTransaction(
      const ASession: IDatabaseSession;
      const ADbType: TDatabaseType;
      const ATransactionId, AConnectionId: Int64;
      const ATerminateConnection: Boolean;
      out AMessage: string
    ): Boolean;
  end;

implementation

function TDatabaseMonitoringUseCase.FormatMonitorTimestamp(const AValue: string): string;
var
  S: string;
  DT: TDateTime;
  ISOFS: TFormatSettings;
begin
  S := Trim(AValue);
  if S = '' then
    Exit('');

  if TryStrToDateTime(S, DT) then
    Exit(FormatDateTime('dd/mm/yyyy hh:nn:ss', DT));

  ISOFS := DefaultFormatSettings;
  ISOFS.DateSeparator := '-';
  ISOFS.ShortDateFormat := 'yyyy-mm-dd';
  ISOFS.LongDateFormat := 'yyyy-mm-dd';
  ISOFS.TimeSeparator := ':';
  if TryStrToDateTime(Copy(S, 1, 19), DT, ISOFS) then
    Exit(FormatDateTime('dd/mm/yyyy hh:nn:ss', DT));

  Result := S;
end;

function TDatabaseMonitoringUseCase.DecodeFbState(const AState: Integer; const AIsStatement: Boolean): string;
begin
  case AState of
    0: Result := 'Ociosa';
    1: Result := 'Ativa';
    2:
      if AIsStatement then
        Result := 'Aguardando Fetch'
      else
        Result := '2';
  else
    Result := IntToStr(AState);
  end;
end;

function TDatabaseMonitoringUseCase.DecodeFbIsolation(const AIsolation: Integer): string;
begin
  case AIsolation of
    0: Result := 'Consistency';
    1: Result := 'Concurrency';
    2: Result := 'Read Committed (RecVer)';
    3: Result := 'Read Committed (NoRecVer)';
    4: Result := 'Read Committed (Read Consistency)';
  else
    Result := IntToStr(AIsolation);
  end;
end;

procedure TDatabaseMonitoringUseCase.RefreshSessionSnapshot(const ASession: IDatabaseSession);
begin
  if ASession = nil then
    Exit;
  if not ASession.IsConnected then
    ASession.Connect;
  { No Firebird, MON$ mantém snapshot por transação: Commit antes de ler garante dados atuais }
  if ASession.InTransaction then
    ASession.Commit;
  ASession.StartTransaction;
end;

procedure TDatabaseMonitoringUseCase.LoadFirebirdSnapshot(
  const ASession: IDatabaseSession;
  const ASnapshot: TMonitoringSnapshot
);
var
  Res: TQueryResult;
  I, Cnt: Integer;
  Row: TQueryRow;
begin
  { 1. Conexões (MON$ATTACHMENTS) }
  Res := ASession.ExecuteSQL(
    'SELECT ' +
    '  a.MON$ATTACHMENT_ID, ' +
    '  COALESCE(TRIM(a.MON$USER), ''''), ' +
    '  COALESCE(TRIM(a.MON$ROLE), ''''), ' +
    '  a.MON$STATE, ' +
    '  a.MON$TIMESTAMP, ' +
    '  COALESCE(TRIM(a.MON$REMOTE_ADDRESS), ''''), ' +
    '  COALESCE(TRIM(a.MON$REMOTE_PROCESS), ''''), ' +
    '  COALESCE(CAST(a.MON$REMOTE_PID AS VARCHAR(20)), ''''), ' +
    '  COALESCE(CAST(a.MON$SERVER_PID AS VARCHAR(20)), ''''), ' +
    '  CASE WHEN a.MON$ATTACHMENT_ID = CURRENT_CONNECTION THEN 1 ELSE 0 END ' +
    'FROM MON$ATTACHMENTS a ' +
    'WHERE a.MON$USER IS NOT NULL ' +
    'ORDER BY a.MON$TIMESTAMP DESC, a.MON$ATTACHMENT_ID DESC',
    False, 0
  );
  try
    if not Res.Success then
      raise Exception.Create(Res.MessageText);
    Cnt := Res.RowCount;
    SetLength(ASnapshot.Connections, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Row := Res.GetRow(I);
      ASnapshot.Connections[I].ConnectionId := StrToInt64Def(Trim(Row[0].AsText), 0);
      ASnapshot.Connections[I].UserName := Trim(Row[1].AsText);
      ASnapshot.Connections[I].RoleName := Trim(Row[2].AsText);
      ASnapshot.Connections[I].State := DecodeFbState(StrToIntDef(Trim(Row[3].AsText), 0));
      ASnapshot.Connections[I].StartedAt := FormatMonitorTimestamp(Row[4].AsText);
      ASnapshot.Connections[I].RemoteAddress := Trim(Row[5].AsText);
      ASnapshot.Connections[I].ClientProcess := Trim(Row[6].AsText);
      ASnapshot.Connections[I].RemotePid := Trim(Row[7].AsText);
      ASnapshot.Connections[I].ServerPid := Trim(Row[8].AsText);
      ASnapshot.Connections[I].IsCurrent := StrToIntDef(Trim(Row[9].AsText), 0) = 1;
    end;
  finally
    Res.Free;
  end;

  { 2. Transações (MON$TRANSACTIONS) }
  Res := ASession.ExecuteSQL(
    'SELECT ' +
    '  t.MON$TRANSACTION_ID, ' +
    '  t.MON$ATTACHMENT_ID, ' +
    '  COALESCE(TRIM(a.MON$USER), ''''), ' +
    '  t.MON$STATE, ' +
    '  t.MON$TIMESTAMP, ' +
    '  t.MON$ISOLATION_MODE, ' +
    '  t.MON$READ_ONLY, ' +
    '  COALESCE(TRIM(a.MON$REMOTE_ADDRESS), ''''), ' +
    '  COALESCE(TRIM(a.MON$REMOTE_PROCESS), ''''), ' +
    '  COALESCE((SELECT FIRST 1 s.MON$STATEMENT_ID FROM MON$STATEMENTS s ' +
    '            WHERE s.MON$TRANSACTION_ID = t.MON$TRANSACTION_ID ' +
    '            ORDER BY s.MON$STATE DESC, s.MON$TIMESTAMP DESC), 0), ' +
    '  (SELECT FIRST 1 s.MON$SQL_TEXT FROM MON$STATEMENTS s ' +
    '   WHERE s.MON$TRANSACTION_ID = t.MON$TRANSACTION_ID ' +
    '   ORDER BY s.MON$STATE DESC, s.MON$TIMESTAMP DESC), ' +
    '  CASE WHEN t.MON$ATTACHMENT_ID = CURRENT_CONNECTION THEN 1 ELSE 0 END ' +
    'FROM MON$TRANSACTIONS t ' +
    'LEFT JOIN MON$ATTACHMENTS a ON a.MON$ATTACHMENT_ID = t.MON$ATTACHMENT_ID ' +
    'ORDER BY t.MON$TIMESTAMP DESC, t.MON$TRANSACTION_ID DESC',
    False, 0
  );
  try
    if not Res.Success then
      raise Exception.Create(Res.MessageText);
    Cnt := Res.RowCount;
    SetLength(ASnapshot.Transactions, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Row := Res.GetRow(I);
      ASnapshot.Transactions[I].TransactionId := StrToInt64Def(Trim(Row[0].AsText), 0);
      ASnapshot.Transactions[I].ConnectionId := StrToInt64Def(Trim(Row[1].AsText), 0);
      ASnapshot.Transactions[I].UserName := Trim(Row[2].AsText);
      ASnapshot.Transactions[I].State := DecodeFbState(StrToIntDef(Trim(Row[3].AsText), 0));
      ASnapshot.Transactions[I].StartedAt := FormatMonitorTimestamp(Row[4].AsText);
      ASnapshot.Transactions[I].IsolationMode := DecodeFbIsolation(StrToIntDef(Trim(Row[5].AsText), 0));
      if StrToIntDef(Trim(Row[6].AsText), 0) = 1 then
        ASnapshot.Transactions[I].ReadOnlyStr := 'Somente Leitura'
      else
        ASnapshot.Transactions[I].ReadOnlyStr := 'Leitura/Escrita';
      ASnapshot.Transactions[I].RemoteAddress := Trim(Row[7].AsText);
      ASnapshot.Transactions[I].ClientProcess := Trim(Row[8].AsText);
      ASnapshot.Transactions[I].StatementId := StrToInt64Def(Trim(Row[9].AsText), 0);
      ASnapshot.Transactions[I].SqlText := Trim(Row[10].AsText);
      ASnapshot.Transactions[I].IsCurrentConnection := StrToIntDef(Trim(Row[11].AsText), 0) = 1;
    end;
  finally
    Res.Free;
  end;

  { 3. Consultas / Statements (MON$STATEMENTS) }
  Res := ASession.ExecuteSQL(
    'SELECT ' +
    '  s.MON$STATEMENT_ID, ' +
    '  s.MON$ATTACHMENT_ID, ' +
    '  COALESCE(s.MON$TRANSACTION_ID, 0), ' +
    '  COALESCE(TRIM(a.MON$USER), ''''), ' +
    '  s.MON$STATE, ' +
    '  s.MON$TIMESTAMP, ' +
    '  COALESCE(TRIM(a.MON$REMOTE_ADDRESS), ''''), ' +
    '  COALESCE(TRIM(a.MON$REMOTE_PROCESS), ''''), ' +
    '  s.MON$SQL_TEXT, ' +
    '  CASE WHEN s.MON$ATTACHMENT_ID = CURRENT_CONNECTION THEN 1 ELSE 0 END ' +
    'FROM MON$STATEMENTS s ' +
    'LEFT JOIN MON$ATTACHMENTS a ON a.MON$ATTACHMENT_ID = s.MON$ATTACHMENT_ID ' +
    'WHERE s.MON$ATTACHMENT_ID <> CURRENT_CONNECTION OR s.MON$STATE > 0 ' +
    'ORDER BY s.MON$STATE DESC, s.MON$TIMESTAMP DESC, s.MON$STATEMENT_ID DESC',
    False, 0
  );
  try
    if not Res.Success then
      raise Exception.Create(Res.MessageText);
    Cnt := Res.RowCount;
    SetLength(ASnapshot.Statements, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Row := Res.GetRow(I);
      ASnapshot.Statements[I].StatementId := StrToInt64Def(Trim(Row[0].AsText), 0);
      ASnapshot.Statements[I].ConnectionId := StrToInt64Def(Trim(Row[1].AsText), 0);
      ASnapshot.Statements[I].TransactionId := StrToInt64Def(Trim(Row[2].AsText), 0);
      ASnapshot.Statements[I].UserName := Trim(Row[3].AsText);
      ASnapshot.Statements[I].State := DecodeFbState(StrToIntDef(Trim(Row[4].AsText), 0), True);
      ASnapshot.Statements[I].StartedAt := FormatMonitorTimestamp(Row[5].AsText);
      ASnapshot.Statements[I].RemoteAddress := Trim(Row[6].AsText);
      ASnapshot.Statements[I].ClientProcess := Trim(Row[7].AsText);
      ASnapshot.Statements[I].SqlText := Trim(Row[8].AsText);
      ASnapshot.Statements[I].IsCurrentConnection := StrToIntDef(Trim(Row[9].AsText), 0) = 1;
    end;
  finally
    Res.Free;
  end;
end;

procedure TDatabaseMonitoringUseCase.LoadPostgresSnapshot(
  const ASession: IDatabaseSession;
  const ASnapshot: TMonitoringSnapshot
);
var
  Res: TQueryResult;
  I, Cnt: Integer;
  Row: TQueryRow;
begin
  { 1. Conexões (pg_stat_activity) }
  Res := ASession.ExecuteSQL(
    'SELECT ' +
    '  pid, ' +
    '  COALESCE(usename, ''''), ' +
    '  '''', ' +
    '  COALESCE(state, ''''), ' +
    '  COALESCE(to_char(backend_start, ''DD/MM/YYYY HH24:MI:SS''), ''''), ' +
    '  COALESCE(client_addr::text, ''local''), ' +
    '  COALESCE(application_name, ''''), ' +
    '  COALESCE(client_port::text, ''''), ' +
    '  pid::text, ' +
    '  CASE WHEN pid = pg_backend_pid() THEN 1 ELSE 0 END ' +
    'FROM pg_stat_activity ' +
    'WHERE datname = current_database() ' +
    'ORDER BY backend_start DESC',
    False, 0
  );
  try
    if not Res.Success then
      raise Exception.Create(Res.MessageText);
    Cnt := Res.RowCount;
    SetLength(ASnapshot.Connections, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Row := Res.GetRow(I);
      ASnapshot.Connections[I].ConnectionId := StrToInt64Def(Trim(Row[0].AsText), 0);
      ASnapshot.Connections[I].UserName := Trim(Row[1].AsText);
      ASnapshot.Connections[I].RoleName := Trim(Row[2].AsText);
      ASnapshot.Connections[I].State := Trim(Row[3].AsText);
      ASnapshot.Connections[I].StartedAt := Trim(Row[4].AsText);
      ASnapshot.Connections[I].RemoteAddress := Trim(Row[5].AsText);
      ASnapshot.Connections[I].ClientProcess := Trim(Row[6].AsText);
      ASnapshot.Connections[I].RemotePid := Trim(Row[7].AsText);
      ASnapshot.Connections[I].ServerPid := Trim(Row[8].AsText);
      ASnapshot.Connections[I].IsCurrent := StrToIntDef(Trim(Row[9].AsText), 0) = 1;
    end;
  finally
    Res.Free;
  end;

  { 2. Transações em andamento }
  Res := ASession.ExecuteSQL(
    'SELECT ' +
    '  COALESCE(backend_xid::text::bigint, pid), ' +
    '  pid, ' +
    '  COALESCE(usename, ''''), ' +
    '  COALESCE(state, ''''), ' +
    '  COALESCE(to_char(xact_start, ''DD/MM/YYYY HH24:MI:SS''), ''''), ' +
    '  COALESCE(wait_event_type || '': '' || wait_event, ''Normal''), ' +
    '  CASE WHEN state = ''active'' THEN ''Ativa'' ELSE ''Aberta'' END, ' +
    '  COALESCE(client_addr::text, ''local''), ' +
    '  COALESCE(application_name, ''''), ' +
    '  pid, ' +
    '  COALESCE(query, ''''), ' +
    '  CASE WHEN pid = pg_backend_pid() THEN 1 ELSE 0 END ' +
    'FROM pg_stat_activity ' +
    'WHERE datname = current_database() AND xact_start IS NOT NULL ' +
    'ORDER BY xact_start ASC',
    False, 0
  );
  try
    if not Res.Success then
      raise Exception.Create(Res.MessageText);
    Cnt := Res.RowCount;
    SetLength(ASnapshot.Transactions, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Row := Res.GetRow(I);
      ASnapshot.Transactions[I].TransactionId := StrToInt64Def(Trim(Row[0].AsText), 0);
      ASnapshot.Transactions[I].ConnectionId := StrToInt64Def(Trim(Row[1].AsText), 0);
      ASnapshot.Transactions[I].UserName := Trim(Row[2].AsText);
      ASnapshot.Transactions[I].State := Trim(Row[3].AsText);
      ASnapshot.Transactions[I].StartedAt := Trim(Row[4].AsText);
      ASnapshot.Transactions[I].IsolationMode := Trim(Row[5].AsText);
      ASnapshot.Transactions[I].ReadOnlyStr := Trim(Row[6].AsText);
      ASnapshot.Transactions[I].RemoteAddress := Trim(Row[7].AsText);
      ASnapshot.Transactions[I].ClientProcess := Trim(Row[8].AsText);
      ASnapshot.Transactions[I].StatementId := StrToInt64Def(Trim(Row[9].AsText), 0);
      ASnapshot.Transactions[I].SqlText := Trim(Row[10].AsText);
      ASnapshot.Transactions[I].IsCurrentConnection := StrToIntDef(Trim(Row[11].AsText), 0) = 1;
    end;
  finally
    Res.Free;
  end;

  { 3. Consultas Ativas }
  Res := ASession.ExecuteSQL(
    'SELECT ' +
    '  pid, ' +
    '  pid, ' +
    '  COALESCE(usename, ''''), ' +
    '  COALESCE(state, ''''), ' +
    '  COALESCE(to_char(COALESCE(query_start, xact_start, backend_start), ''DD/MM/YYYY HH24:MI:SS''), ''''), ' +
    '  COALESCE(client_addr::text, ''local''), ' +
    '  COALESCE(application_name, ''''), ' +
    '  COALESCE(query, ''''), ' +
    '  CASE WHEN pid = pg_backend_pid() THEN 1 ELSE 0 END ' +
    'FROM pg_stat_activity ' +
    'WHERE datname = current_database() AND state IS NOT NULL AND state <> ''idle'' ' +
    'ORDER BY query_start ASC NULLS LAST',
    False, 0
  );
  try
    if not Res.Success then
      raise Exception.Create(Res.MessageText);
    Cnt := Res.RowCount;
    SetLength(ASnapshot.Statements, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      Row := Res.GetRow(I);
      ASnapshot.Statements[I].StatementId := StrToInt64Def(Trim(Row[0].AsText), 0);
      ASnapshot.Statements[I].ConnectionId := StrToInt64Def(Trim(Row[1].AsText), 0);
      ASnapshot.Statements[I].TransactionId := 0;
      ASnapshot.Statements[I].UserName := Trim(Row[2].AsText);
      ASnapshot.Statements[I].State := Trim(Row[3].AsText);
      ASnapshot.Statements[I].StartedAt := Trim(Row[4].AsText);
      ASnapshot.Statements[I].RemoteAddress := Trim(Row[5].AsText);
      ASnapshot.Statements[I].ClientProcess := Trim(Row[6].AsText);
      ASnapshot.Statements[I].SqlText := Trim(Row[7].AsText);
      ASnapshot.Statements[I].IsCurrentConnection := StrToIntDef(Trim(Row[8].AsText), 0) = 1;
    end;
  finally
    Res.Free;
  end;
end;

function TDatabaseMonitoringUseCase.CaptureSnapshot(
  const ASession: IDatabaseSession;
  const ADbType: TDatabaseType
): TMonitoringSnapshot;
begin
  Result := TMonitoringSnapshot.Create;
  try
    RefreshSessionSnapshot(ASession);
    if ADbType = dtPostgreSQL then
      LoadPostgresSnapshot(ASession, Result)
    else
      LoadFirebirdSnapshot(ASession, Result);
    Result.CapturedAt := Now;
    if ASession.InTransaction then
      ASession.Commit;
  except
    on E: Exception do
    begin
      try
        if (ASession <> nil) and ASession.InTransaction then
          ASession.Rollback;
      except
      end;
      Result.Free;
      raise;
    end;
  end;
end;

function TDatabaseMonitoringUseCase.TerminateConnection(
  const ASession: IDatabaseSession;
  const ADbType: TDatabaseType;
  const AConnectionId: Int64;
  out AMessage: string
): Boolean;
var
  SQL: string;
  Res: TQueryResult;
begin
  Result := False;
  AMessage := '';
  if ASession = nil then
  begin
    AMessage := 'Sessão de monitoramento inválida.';
    Exit;
  end;

  RefreshSessionSnapshot(ASession);
  if ADbType = dtPostgreSQL then
    SQL := Format('SELECT pg_terminate_backend(%d)', [AConnectionId])
  else
    SQL := Format(
      'DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID = %d AND MON$ATTACHMENT_ID <> CURRENT_CONNECTION',
      [AConnectionId]
    );

  Res := ASession.ExecuteSQL(SQL, False, 0);
  try
    if not Res.Success then
    begin
      if ASession.InTransaction then
        ASession.Rollback;
      AMessage := Res.MessageText;
      Exit;
    end;
    if ASession.InTransaction then
      ASession.Commit;
    Result := True;
    AMessage := Format('Conexão #%d encerrada.', [AConnectionId]);
  finally
    Res.Free;
  end;
end;

function TDatabaseMonitoringUseCase.CancelStatement(
  const ASession: IDatabaseSession;
  const ADbType: TDatabaseType;
  const AStatementId, AConnectionId: Int64;
  out AMessage: string
): Boolean;
var
  SQL: string;
  Res: TQueryResult;
begin
  Result := False;
  AMessage := '';
  if ASession = nil then
  begin
    AMessage := 'Sessão de monitoramento inválida.';
    Exit;
  end;

  RefreshSessionSnapshot(ASession);
  if ADbType = dtPostgreSQL then
    SQL := Format('SELECT pg_cancel_backend(%d)', [AConnectionId])
  else
    SQL := Format('DELETE FROM MON$STATEMENTS WHERE MON$STATEMENT_ID = %d', [AStatementId]);

  Res := ASession.ExecuteSQL(SQL, False, 0);
  try
    if not Res.Success then
    begin
      if ASession.InTransaction then
        ASession.Rollback;
      AMessage := Res.MessageText;
      Exit;
    end;
    if ASession.InTransaction then
      ASession.Commit;
    Result := True;
    if ADbType = dtPostgreSQL then
      AMessage := Format('Cancelamento de consulta enviado ao PID #%d.', [AConnectionId])
    else
      AMessage := Format('Consulta #%d cancelada.', [AStatementId]);
  finally
    Res.Free;
  end;
end;

function TDatabaseMonitoringUseCase.CancelTransaction(
  const ASession: IDatabaseSession;
  const ADbType: TDatabaseType;
  const ATransactionId, AConnectionId: Int64;
  const ATerminateConnection: Boolean;
  out AMessage: string
): Boolean;
var
  SQL: string;
  Res: TQueryResult;
begin
  Result := False;
  AMessage := '';
  if ASession = nil then
  begin
    AMessage := 'Sessão de monitoramento inválida.';
    Exit;
  end;

  RefreshSessionSnapshot(ASession);
  if ADbType = dtPostgreSQL then
  begin
    if ATerminateConnection then
      SQL := Format('SELECT pg_terminate_backend(%d)', [AConnectionId])
    else
      SQL := Format('SELECT pg_cancel_backend(%d)', [AConnectionId]);

    Res := ASession.ExecuteSQL(SQL, False, 0);
    try
      if not Res.Success then
      begin
        if ASession.InTransaction then
          ASession.Rollback;
        AMessage := Res.MessageText;
        Exit;
      end;
      if ASession.InTransaction then
        ASession.Commit;
      Result := True;
      AMessage := Format('Ação executada para a transação #%d (PID #%d).', [ATransactionId, AConnectionId]);
    finally
      Res.Free;
    end;
  end
  else
  begin
    Res := ASession.ExecuteSQL(
      Format('DELETE FROM MON$STATEMENTS WHERE MON$TRANSACTION_ID = %d', [ATransactionId]),
      False, 0
    );
    try
      if not Res.Success then
      begin
        if ASession.InTransaction then
          ASession.Rollback;
        AMessage := Res.MessageText;
        Exit;
      end;
    finally
      Res.Free;
    end;

    if ATerminateConnection then
    begin
      Res := ASession.ExecuteSQL(
        Format(
          'DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID = %d AND MON$ATTACHMENT_ID <> CURRENT_CONNECTION',
          [AConnectionId]
        ),
        False, 0
      );
      try
        if not Res.Success then
        begin
          if ASession.InTransaction then
            ASession.Rollback;
          AMessage := Res.MessageText;
          Exit;
        end;
      finally
        Res.Free;
      end;
    end;

    if ASession.InTransaction then
      ASession.Commit;
    Result := True;
    if ATerminateConnection then
      AMessage := Format('Transação #%d encerrada (conexão #%d desconectada com rollback).', [ATransactionId, AConnectionId])
    else
      AMessage := Format('Consultas da transação #%d canceladas.', [ATransactionId]);
  end;
end;

end.
