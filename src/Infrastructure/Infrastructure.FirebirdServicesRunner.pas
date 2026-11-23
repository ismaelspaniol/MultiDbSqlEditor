unit Infrastructure.FirebirdServicesRunner;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  ibase60dyn,
  Domain.ConnectionProfile,
  Domain.MaintenanceTypes,
  Infrastructure.FirebirdSqlDbProvider;

type
  TFbServiceLogProc = procedure(const ALine: string) of object;
  TFbServiceCancelFunc = function: Boolean of object;

  { Executor nativo via Firebird Services API (isc_service_attach/start/query/detach) }
  TFirebirdServicesRunner = class
  private
    function FormatStatusError(const AStatus: PISC_STATUS): string;
    function BuildServiceName(const AProfile: TConnectionProfile): string;
    function BuildAttachSPB(const AProfile: TConnectionProfile): string;
    function ShortParam(const ACode: Byte; const AVal: string): string;
    function SpbString(const ACode: Byte; const AVal: string): string;
    function SpbInt32(const ACode: Byte; const AVal: LongInt): string;
    function AttachService(
      const AProfile: TConnectionProfile;
      out ASvcHandle: isc_svc_handle;
      out AErrMsg: string
    ): Boolean;
    procedure DetachService(var ASvcHandle: isc_svc_handle);
    function QueryServiceRunning(const ASvcHandle: isc_svc_handle): Boolean;
    function StreamServiceLines(
      const ASvcHandle: isc_svc_handle;
      const AOnLog: TFbServiceLogProc;
      const ACancelCheck: TFbServiceCancelFunc;
      out AErrMsg: string
    ): Boolean;
    function WaitServiceFinish(
      const ASvcHandle: isc_svc_handle;
      const AOnLog: TFbServiceLogProc;
      const ACancelCheck: TFbServiceCancelFunc;
      out AErrMsg: string
    ): Boolean;
    function QueryLimboTransactions(
      const ASvcHandle: isc_svc_handle;
      const ADbName: string;
      const AOnLog: TFbServiceLogProc;
      out AErrMsg: string
    ): specialize TArray<LongInt>;
  public
    function RunBackup(
      const AReq: TBackupRequest;
      const AOnLog: TFbServiceLogProc;
      const ACancelCheck: TFbServiceCancelFunc;
      out AMessage: string
    ): Boolean;
    function RunRestore(
      const AReq: TRestoreRequest;
      const AOnLog: TFbServiceLogProc;
      const ACancelCheck: TFbServiceCancelFunc;
      out AMessage: string
    ): Boolean;
    function RunRepair(
      const AReq: TRepairRequest;
      const AOnLog: TFbServiceLogProc;
      const ACancelCheck: TFbServiceCancelFunc;
      out AMessage: string
    ): Boolean;
  end;

implementation

{ TFirebirdServicesRunner }

function TFirebirdServicesRunner.FormatStatusError(const AStatus: PISC_STATUS): string;
var
  Buf: array[0..1023] of AnsiChar;
  Ptr: PISC_STATUS;
  Line: string;
begin
  Result := '';
  Ptr := AStatus;
  while isc_interprete(@Buf[0], @Ptr) > 0 do
  begin
    Line := Trim(StrPas(PAnsiChar(@Buf[0])));
    if Line <> '' then
    begin
      if Result <> '' then
        Result := Result + LineEnding;
      Result := Result + Line;
    end;
  end;
  if Result = '' then
    Result := 'Erro desconhecido no Firebird Services API.';
end;

function TFirebirdServicesRunner.BuildServiceName(const AProfile: TConnectionProfile): string;
var
  H: string;
begin
  H := Trim(AProfile.Host);
  if H = '' then
    Result := 'service_mgr'
  else if (AProfile.Port > 0) and (AProfile.Port <> 3050) then
    Result := Format('%s/%d:service_mgr', [H, AProfile.Port])
  else
    Result := H + ':service_mgr';
end;

function TFirebirdServicesRunner.ShortParam(const ACode: Byte; const AVal: string): string;
var
  S: string;
begin
  S := Copy(AVal, 1, 255);
  Result := Chr(ACode) + Chr(Length(S)) + S;
end;

function TFirebirdServicesRunner.SpbString(const ACode: Byte; const AVal: string): string;
var
  Len: Word;
begin
  Len := Length(AVal);
  Result := Chr(ACode) + Chr(Len and $FF) + Chr((Len shr 8) and $FF) + AVal;
end;

function TFirebirdServicesRunner.SpbInt32(const ACode: Byte; const AVal: LongInt): string;
begin
  Result := Chr(ACode) +
    Chr(AVal and $FF) +
    Chr((AVal shr 8) and $FF) +
    Chr((AVal shr 16) and $FF) +
    Chr((AVal shr 24) and $FF);
end;

function TFirebirdServicesRunner.BuildAttachSPB(const AProfile: TConnectionProfile): string;
begin
  Result := Chr(isc_spb_version) + Chr(isc_spb_current_version) +
    ShortParam(isc_spb_user_name, AProfile.Username) +
    ShortParam(isc_spb_password, AProfile.Password);
end;

function TFirebirdServicesRunner.AttachService(
  const AProfile: TConnectionProfile;
  out ASvcHandle: isc_svc_handle;
  out AErrMsg: string
): Boolean;
var
  SvcName, SPB: string;
  Status: array[0..19] of ISC_STATUS;
begin
  Result := False;
  ASvcHandle := isc_svc_handle(FB_API_NULLHANDLE);
  AErrMsg := '';

  AcquireFirebirdClientLib(AProfile);
  SvcName := BuildServiceName(AProfile);
  SPB := BuildAttachSPB(AProfile);
  FillChar(Status[0], SizeOf(Status), 0);

  if isc_service_attach(
       @Status[0],
       Word(Length(SvcName)),
       PAnsiChar(SvcName),
       @ASvcHandle,
       Word(Length(SPB)),
       PAnsiChar(SPB)
     ) <> 0 then
  begin
    AErrMsg := FormatStatusError(@Status[0]);
    ReleaseFirebirdClientLib;
    Exit;
  end;

  Result := True;
end;

procedure TFirebirdServicesRunner.DetachService(var ASvcHandle: isc_svc_handle);
var
  Status: array[0..19] of ISC_STATUS;
begin
  if ASvcHandle <> isc_svc_handle(FB_API_NULLHANDLE) then
  begin
    try
      FillChar(Status[0], SizeOf(Status), 0);
      isc_service_detach(@Status[0], @ASvcHandle);
    except
    end;
    ASvcHandle := isc_svc_handle(FB_API_NULLHANDLE);
    ReleaseFirebirdClientLib;
  end;
end;

function TFirebirdServicesRunner.QueryServiceRunning(const ASvcHandle: isc_svc_handle): Boolean;
var
  Status: array[0..19] of ISC_STATUS;
  Req: Byte;
  ResBuf: array[0..63] of Byte;
  FlagVal: LongInt;
begin
  Result := False;
  Req := isc_info_svc_running;
  FillChar(Status[0], SizeOf(Status), 0);
  FillChar(ResBuf[0], SizeOf(ResBuf), 0);
  if isc_service_query(@Status[0], @ASvcHandle, nil, 0, nil, 1, PAnsiChar(@Req), SizeOf(ResBuf), PAnsiChar(@ResBuf[0])) = 0 then
  begin
    if ResBuf[0] = isc_info_svc_running then
    begin
      FlagVal := isc_vax_integer(PAnsiChar(@ResBuf[1]), 4);
      Result := FlagVal = 1;
    end;
  end;
end;

function TFirebirdServicesRunner.StreamServiceLines(
  const ASvcHandle: isc_svc_handle;
  const AOnLog: TFbServiceLogProc;
  const ACancelCheck: TFbServiceCancelFunc;
  out AErrMsg: string
): Boolean;
const
  BUF_SIZE = 2048;
var
  Status: array[0..19] of ISC_STATUS;
  ReqBuf: array[0..0] of Byte;
  ResBuf: array[0..BUF_SIZE - 1] of Byte;
  LineLen: Integer;
  LineText: string;
begin
  Result := True;
  AErrMsg := '';
  ReqBuf[0] := isc_info_svc_line;

  while True do
  begin
    if Assigned(ACancelCheck) and ACancelCheck() then
    begin
      AErrMsg := 'Operação cancelada pelo usuário (acompanhamento interrompido).';
      Exit(False);
    end;

    FillChar(Status[0], SizeOf(Status), 0);
    FillChar(ResBuf[0], SizeOf(ResBuf), 0);
    if isc_service_query(
         @Status[0], @ASvcHandle, nil, 0, nil,
         1, PAnsiChar(@ReqBuf[0]),
         SizeOf(ResBuf), PAnsiChar(@ResBuf[0])
       ) <> 0 then
    begin
      AErrMsg := FormatStatusError(@Status[0]);
      Exit(False);
    end;

    if ResBuf[0] = isc_info_svc_line then
    begin
      LineLen := isc_vax_integer(PAnsiChar(@ResBuf[1]), 2);
      if LineLen <= 0 then
        Break;
      SetString(LineText, PAnsiChar(@ResBuf[3]), LineLen);
      if Assigned(AOnLog) then
        AOnLog(LineText);
    end
    else
      Break;
  end;
end;

function TFirebirdServicesRunner.WaitServiceFinish(
  const ASvcHandle: isc_svc_handle;
  const AOnLog: TFbServiceLogProc;
  const ACancelCheck: TFbServiceCancelFunc;
  out AErrMsg: string
): Boolean;
begin
  Result := True;
  AErrMsg := '';
  while QueryServiceRunning(ASvcHandle) do
  begin
    if Assigned(ACancelCheck) and ACancelCheck() then
    begin
      AErrMsg := 'Acompanhamento cancelado pelo usuário (o serviço pode continuar concluindo no servidor).';
      Exit(False);
    end;
    Sleep(100);
  end;
  if Assigned(AOnLog) then
    AOnLog('Serviço concluído no servidor Firebird.');
end;

function TFirebirdServicesRunner.QueryLimboTransactions(
  const ASvcHandle: isc_svc_handle;
  const ADbName: string;
  const AOnLog: TFbServiceLogProc;
  out AErrMsg: string
): specialize TArray<LongInt>;
const
  BUF_SIZE = 4096;
var
  Status: array[0..19] of ISC_STATUS;
  StartSPB: string;
  Req: Byte;
  ResBuf: array[0..BUF_SIZE - 1] of Byte;
  Idx, Len: Integer;
  Item: Byte;
  TxId: LongInt;
begin
  SetLength(Result, 0);
  AErrMsg := '';

  StartSPB := Chr(isc_action_svc_repair) +
    SpbString(isc_spb_dbname, ADbName) +
    SpbInt32(isc_spb_options, isc_spb_rpr_list_limbo_trans);

  FillChar(Status[0], SizeOf(Status), 0);
  if isc_service_start(@Status[0], @ASvcHandle, nil, Word(Length(StartSPB)), PAnsiChar(StartSPB)) <> 0 then
  begin
    AErrMsg := FormatStatusError(@Status[0]);
    Exit;
  end;

  Req := isc_info_svc_limbo_trans;
  FillChar(Status[0], SizeOf(Status), 0);
  FillChar(ResBuf[0], SizeOf(ResBuf), 0);
  if isc_service_query(@Status[0], @ASvcHandle, nil, 0, nil, 1, PAnsiChar(@Req), SizeOf(ResBuf), PAnsiChar(@ResBuf[0])) <> 0 then
  begin
    AErrMsg := FormatStatusError(@Status[0]);
    Exit;
  end;

  Idx := 0;
  if ResBuf[Idx] = isc_info_svc_limbo_trans then
  begin
    Len := isc_vax_integer(PAnsiChar(@ResBuf[Idx + 1]), 2);
    Inc(Idx, 3);
    while (Idx < SizeOf(ResBuf)) and (Idx < 3 + Len) do
    begin
      Item := ResBuf[Idx];
      Inc(Idx);
      if (Item = isc_info_end) or (Item = isc_info_flag_end) then
        Break;
      case Item of
        isc_spb_single_tra_id,
        isc_spb_multi_tra_id,
        isc_spb_tra_id:
          begin
            if Idx + 4 <= SizeOf(ResBuf) then
            begin
              TxId := isc_vax_integer(PAnsiChar(@ResBuf[Idx]), 4);
              Inc(Idx, 4);
              SetLength(Result, Length(Result) + 1);
              Result[High(Result)] := TxId;
              if Assigned(AOnLog) then
                AOnLog(Format('Transação em limbo encontrada: ID #%d', [TxId]));
            end;
          end;
        isc_spb_tra_state,
        isc_spb_tra_advise:
          Inc(Idx, 1);
        isc_spb_tra_host_site,
        isc_spb_tra_remote_site,
        isc_spb_tra_db_path:
          begin
            if Idx + 2 <= SizeOf(ResBuf) then
            begin
              TxId := isc_vax_integer(PAnsiChar(@ResBuf[Idx]), 2);
              Inc(Idx, 2 + TxId);
            end;
          end;
      end;
    end;
  end;
end;

function TFirebirdServicesRunner.RunBackup(
  const AReq: TBackupRequest;
  const AOnLog: TFbServiceLogProc;
  const ACancelCheck: TFbServiceCancelFunc;
  out AMessage: string
): Boolean;
var
  SvcHandle: isc_svc_handle;
  Status: array[0..19] of ISC_STATUS;
  SPB, ErrMsg: string;
  Opts: LongInt;
begin
  Result := False;
  AMessage := '';
  if (AReq.Profile = nil) or (Trim(AReq.OutputFile) = '') then
  begin
    AMessage := 'Conexão ou caminho do arquivo de backup (.fbk) não informado.';
    Exit;
  end;

  if not AttachService(AReq.Profile, SvcHandle, ErrMsg) then
  begin
    AMessage := 'Falha ao conectar no Firebird Service Manager: ' + ErrMsg;
    Exit;
  end;

  try
    Opts := 0;
    if AReq.FbIgnoreChecksums then
      Opts := Opts or isc_spb_bkp_ignore_checksums;
    if AReq.FbIgnoreLimbo then
      Opts := Opts or isc_spb_bkp_ignore_limbo;
    if AReq.FbMetadataOnly then
      Opts := Opts or isc_spb_bkp_metadata_only;
    if AReq.FbNoGarbageCollect then
      Opts := Opts or isc_spb_bkp_no_garbage_collect;
    if AReq.FbNonTransportable then
      Opts := Opts or isc_spb_bkp_non_transportable;

    SPB := Chr(isc_action_svc_backup) +
      SpbString(isc_spb_dbname, AReq.Profile.Database) +
      SpbString(isc_spb_bkp_file, Trim(AReq.OutputFile));
    if Trim(AReq.Profile.Role) <> '' then
      SPB := SPB + SpbString(isc_spb_sql_role_name, Copy(Trim(AReq.Profile.Role), 1, 31));
    if AReq.Verbose then
      SPB := SPB + Chr(isc_spb_verbose);
    SPB := SPB + SpbInt32(isc_spb_options, Opts);

    if Assigned(AOnLog) then
      AOnLog(Format('Iniciando backup via Services API (%s -> %s)...', [
        AReq.Profile.Database, Trim(AReq.OutputFile)
      ]));

    FillChar(Status[0], SizeOf(Status), 0);
    if isc_service_start(@Status[0], @SvcHandle, nil, Word(Length(SPB)), PAnsiChar(SPB)) <> 0 then
    begin
      AMessage := 'Erro ao iniciar backup: ' + FormatStatusError(@Status[0]);
      Exit;
    end;

    if AReq.Verbose then
      Result := StreamServiceLines(SvcHandle, AOnLog, ACancelCheck, ErrMsg)
    else
      Result := WaitServiceFinish(SvcHandle, AOnLog, ACancelCheck, ErrMsg);

    if Result then
      AMessage := 'Backup Firebird concluído com sucesso.'
    else
      AMessage := ErrMsg;
  finally
    DetachService(SvcHandle);
  end;
end;

function TFirebirdServicesRunner.RunRestore(
  const AReq: TRestoreRequest;
  const AOnLog: TFbServiceLogProc;
  const ACancelCheck: TFbServiceCancelFunc;
  out AMessage: string
): Boolean;
var
  SvcHandle: isc_svc_handle;
  Status: array[0..19] of ISC_STATUS;
  SPB, ErrMsg, TargetDb: string;
  Opts: LongInt;
begin
  Result := False;
  AMessage := '';
  TargetDb := Trim(AReq.TargetDatabaseOrName);
  if (TargetDb = '') and (AReq.Profile <> nil) then
    TargetDb := AReq.Profile.Database;

  if (AReq.Profile = nil) or (Trim(AReq.InputFile) = '') or (TargetDb = '') then
  begin
    AMessage := 'Informe o arquivo de backup (.fbk) e o banco de destino para o restore.';
    Exit;
  end;

  if not AttachService(AReq.Profile, SvcHandle, ErrMsg) then
  begin
    AMessage := 'Falha ao conectar no Firebird Service Manager: ' + ErrMsg;
    Exit;
  end;

  try
    Opts := 0;
    if AReq.FbReplaceExisting then
      Opts := Opts or isc_spb_res_replace
    else
      Opts := Opts or isc_spb_res_create;
    if AReq.FbDeactivateIndexes then
      Opts := Opts or isc_spb_res_deactivate_idx;
    if AReq.FbNoValidity then
      Opts := Opts or isc_spb_res_no_validity;
    if AReq.FbNoShadow then
      Opts := Opts or isc_spb_res_no_shadow;
    if AReq.FbOneAtATime then
      Opts := Opts or isc_spb_res_one_at_a_time;

    SPB := Chr(isc_action_svc_restore) +
      SpbString(isc_spb_bkp_file, Trim(AReq.InputFile)) +
      SpbString(isc_spb_dbname, TargetDb);
    if Trim(AReq.Profile.Role) <> '' then
      SPB := SPB + SpbString(isc_spb_sql_role_name, Copy(Trim(AReq.Profile.Role), 1, 31));
    if AReq.FbPageSize > 0 then
      SPB := SPB + SpbInt32(isc_spb_res_page_size, AReq.FbPageSize);
    if Trim(AReq.FbFixFssDataCharset) <> '' then
      SPB := SPB + SpbString(isc_spb_res_fix_fss_data, Trim(AReq.FbFixFssDataCharset));
    if Trim(AReq.FbFixFssMetaCharset) <> '' then
      SPB := SPB + SpbString(isc_spb_res_fix_fss_metadata, Trim(AReq.FbFixFssMetaCharset));
    if AReq.Verbose then
      SPB := SPB + Chr(isc_spb_verbose);
    SPB := SPB + SpbInt32(isc_spb_options, Opts);

    if Assigned(AOnLog) then
      AOnLog(Format('Iniciando restore via Services API (%s -> %s)...', [
        Trim(AReq.InputFile), TargetDb
      ]));

    FillChar(Status[0], SizeOf(Status), 0);
    if isc_service_start(@Status[0], @SvcHandle, nil, Word(Length(SPB)), PAnsiChar(SPB)) <> 0 then
    begin
      AMessage := 'Erro ao iniciar restore: ' + FormatStatusError(@Status[0]);
      Exit;
    end;

    if AReq.Verbose then
      Result := StreamServiceLines(SvcHandle, AOnLog, ACancelCheck, ErrMsg)
    else
      Result := WaitServiceFinish(SvcHandle, AOnLog, ACancelCheck, ErrMsg);

    if Result then
      AMessage := 'Restore Firebird concluído com sucesso.'
    else
      AMessage := ErrMsg;
  finally
    DetachService(SvcHandle);
  end;
end;

function TFirebirdServicesRunner.RunRepair(
  const AReq: TRepairRequest;
  const AOnLog: TFbServiceLogProc;
  const ACancelCheck: TFbServiceCancelFunc;
  out AMessage: string
): Boolean;
var
  SvcHandle: isc_svc_handle;
  Status: array[0..19] of ISC_STATUS;
  SPB, ErrMsg, TxText: string;
  Opts: LongInt;
  LimboIds: specialize TArray<LongInt>;
  TxVal, I: LongInt;
begin
  Result := False;
  AMessage := '';
  if AReq.Profile = nil then
  begin
    AMessage := 'Conexão não informada.';
    Exit;
  end;

  if not AttachService(AReq.Profile, SvcHandle, ErrMsg) then
  begin
    AMessage := 'Falha ao conectar no Firebird Service Manager: ' + ErrMsg;
    Exit;
  end;

  try
    if Assigned(AOnLog) then
      AOnLog('Executando: ' + FirebirdRepairActionTitle(AReq.FbAction));

    { Nota: Firebird NÃO aceita isc_spb_verbose em isc_action_svc_repair nem isc_action_svc_properties }
    case AReq.FbAction of
      fraListLimbo:
        begin
          LimboIds := QueryLimboTransactions(SvcHandle, AReq.Profile.Database, AOnLog, ErrMsg);
          if ErrMsg <> '' then
          begin
            AMessage := 'Erro ao listar transações limbo: ' + ErrMsg;
            Exit;
          end;
          if Length(LimboIds) = 0 then
            if Assigned(AOnLog) then
              AOnLog('Nenhuma transação em limbo encontrada.');
          Result := True;
          AMessage := Format('Verificação concluída: %d transação(ões) em limbo.', [Length(LimboIds)]);
          Exit;
        end;
      fraCommitLimboAll, fraRollbackLimboAll:
        begin
          TxText := Trim(AReq.FbLimboTxId);
          if (TxText = '') or SameText(TxText, 'all') then
          begin
            LimboIds := QueryLimboTransactions(SvcHandle, AReq.Profile.Database, AOnLog, ErrMsg);
            if ErrMsg <> '' then
            begin
              AMessage := 'Erro ao localizar transações limbo: ' + ErrMsg;
              Exit;
            end;
            if Length(LimboIds) = 0 then
            begin
              if Assigned(AOnLog) then
                AOnLog('Nenhuma transação em limbo para processar.');
              Result := True;
              AMessage := 'Nenhuma transação em limbo pendente.';
              Exit;
            end;
          end
          else if TryStrToInt(TxText, TxVal) then
          begin
            SetLength(LimboIds, 1);
            LimboIds[0] := TxVal;
          end
          else
          begin
            AMessage := 'ID da transação limbo inválido: ' + TxText;
            Exit;
          end;

          for I := 0 to High(LimboIds) do
          begin
            SPB := Chr(isc_action_svc_repair) + SpbString(isc_spb_dbname, AReq.Profile.Database);
            if AReq.FbAction = fraCommitLimboAll then
              SPB := SPB + SpbInt32(isc_spb_rpr_commit_trans, LimboIds[I])
            else
              SPB := SPB + SpbInt32(isc_spb_rpr_rollback_trans, LimboIds[I]);

            FillChar(Status[0], SizeOf(Status), 0);
            if isc_service_start(@Status[0], @SvcHandle, nil, Word(Length(SPB)), PAnsiChar(SPB)) <> 0 then
            begin
              AMessage := FormatStatusError(@Status[0]);
              Exit;
            end;
            if not WaitServiceFinish(SvcHandle, AOnLog, ACancelCheck, ErrMsg) then
            begin
              AMessage := ErrMsg;
              Exit;
            end;
            if Assigned(AOnLog) then
              AOnLog(Format('Transação limbo #%d processada.', [LimboIds[I]]));
          end;
          Result := True;
          AMessage := Format('%d transação(ões) limbo resolvida(s).', [Length(LimboIds)]);
          Exit;
        end;
      fraShutdownForce:
        begin
          SPB := Chr(isc_action_svc_properties) +
            SpbString(isc_spb_dbname, AReq.Profile.Database) +
            SpbInt32(isc_spb_prp_shutdown_db, 0);
        end;
      fraBringOnline:
        begin
          SPB := Chr(isc_action_svc_properties) +
            SpbString(isc_spb_dbname, AReq.Profile.Database) +
            SpbInt32(isc_spb_options, isc_spb_prp_db_online);
        end;
    else
      begin
        Opts := 0;
        case AReq.FbAction of
          fraValidateCheckOnly: Opts := isc_spb_rpr_validate_db or isc_spb_rpr_check_db;
          fraValidateFull: Opts := isc_spb_rpr_validate_db or isc_spb_rpr_full;
          fraMendCorrupt: Opts := isc_spb_rpr_mend_db or isc_spb_rpr_full or isc_spb_rpr_ignore_checksum;
          fraSweep: Opts := isc_spb_rpr_sweep_db;
          fraKillShadows: Opts := isc_spb_rpr_kill_shadows;
        end;
        if AReq.FbIgnoreChecksums then
          Opts := Opts or isc_spb_rpr_ignore_checksum;

        SPB := Chr(isc_action_svc_repair) +
          SpbString(isc_spb_dbname, AReq.Profile.Database) +
          SpbInt32(isc_spb_options, Opts);
      end;
    end;

    FillChar(Status[0], SizeOf(Status), 0);
    if isc_service_start(@Status[0], @SvcHandle, nil, Word(Length(SPB)), PAnsiChar(SPB)) <> 0 then
    begin
      ErrMsg := FormatStatusError(@Status[0]);
      if (AReq.FbAction in [fraValidateCheckOnly, fraValidateFull]) and
         (Pos('secondary server attachments cannot validate', LowerCase(ErrMsg)) > 0) then
      begin
        if Assigned(AOnLog) then
          AOnLog('Banco possui outras conexões ativas; tentando validação online (isc_action_svc_validate)...');
        SPB := Chr(30 { isc_action_svc_validate }) +
          SpbString(isc_spb_dbname, AReq.Profile.Database) +
          SpbInt32(5 { isc_spb_val_lock_timeout }, 10);
        FillChar(Status[0], SizeOf(Status), 0);
        if isc_service_start(@Status[0], @SvcHandle, nil, Word(Length(SPB)), PAnsiChar(SPB)) <> 0 then
        begin
          AMessage := 'Erro ao executar manutenção Firebird: ' + ErrMsg +
            LineEnding + 'Dica: A validação gfix (-v) exige acesso exclusivo ao banco (feche outras conexões ou faça Shutdown antes). ' +
            'Tentativa de validação online também falhou: ' + FormatStatusError(@Status[0]);
          Exit;
        end;
        Result := WaitServiceFinish(SvcHandle, AOnLog, ACancelCheck, ErrMsg);
        if Result then
          AMessage := FirebirdRepairActionTitle(AReq.FbAction) + ' (validação online) — concluído sem erros.'
        else
          AMessage := ErrMsg;
        Exit;
      end;

      AMessage := 'Erro ao executar manutenção Firebird: ' + ErrMsg;
      Exit;
    end;

    Result := WaitServiceFinish(SvcHandle, AOnLog, ACancelCheck, ErrMsg);
    if Result then
      AMessage := FirebirdRepairActionTitle(AReq.FbAction) + ' — concluído sem erros.'
    else
      AMessage := ErrMsg;
  finally
    DetachService(SvcHandle);
  end;
end;

end.
