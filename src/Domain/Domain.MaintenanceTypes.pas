unit Domain.MaintenanceTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile;

type
  TMaintenanceTabKind = (mtkBackup, mtkRestore, mtkRepair);

  TFirebirdExecBackend = (febServicesApi, febCliTools);

  TFirebirdRepairAction = (
    fraValidateCheckOnly,
    fraValidateFull,
    fraMendCorrupt,
    fraSweep,
    fraListLimbo,
    fraCommitLimboAll,
    fraRollbackLimboAll,
    fraKillShadows,
    fraShutdownForce,
    fraBringOnline
  );

  TPostgresRepairAction = (
    praVacuum,
    praVacuumAnalyze,
    praVacuumFull,
    praReindexDatabase,
    praAnalyze,
    praCheckCorruptedIndexes
  );

  TPostgresDumpFormat = (pdfCustom, pdfPlainSql, pdfDirectory, pdfTar);

  TBackupRequest = record
    Profile: TConnectionProfile;
    Backend: TFirebirdExecBackend;
    ToolExecutablePath: string;
    OutputFile: string;
    Verbose: Boolean;
    { Firebird (gbak / Services API) }
    FbIgnoreChecksums: Boolean;
    FbIgnoreLimbo: Boolean;
    FbMetadataOnly: Boolean;
    FbNoGarbageCollect: Boolean;
    FbNonTransportable: Boolean;
    { PostgreSQL (pg_dump) }
    PgFormat: TPostgresDumpFormat;
    PgSchemaOnly: Boolean;
    PgDataOnly: Boolean;
    PgNoOwner: Boolean;
    PgClean: Boolean;
    PgIfExists: Boolean;
  end;

  TRestoreRequest = record
    Profile: TConnectionProfile;
    Backend: TFirebirdExecBackend;
    ToolExecutablePath: string;
    InputFile: string;
    TargetDatabaseOrName: string;
    Verbose: Boolean;
    { Firebird (gbak / Services API) }
    FbReplaceExisting: Boolean;
    FbCreateNew: Boolean;
    FbDeactivateIndexes: Boolean;
    FbNoValidity: Boolean;
    FbNoShadow: Boolean;
    FbOneAtATime: Boolean;
    FbPageSize: Integer;
    FbFixFssDataCharset: string;
    FbFixFssMetaCharset: string;
    { PostgreSQL (pg_restore / psql) }
    PgCreateDb: Boolean;
    PgClean: Boolean;
    PgIfExists: Boolean;
    PgNoOwner: Boolean;
  end;

  TRepairRequest = record
    Profile: TConnectionProfile;
    Backend: TFirebirdExecBackend;
    ToolExecutablePath: string;
    Verbose: Boolean;
    FbAction: TFirebirdRepairAction;
    FbIgnoreChecksums: Boolean;
    FbLimboTxId: string;
    PgAction: TPostgresRepairAction;
  end;

function DefaultBackupRequest: TBackupRequest;
function DefaultRestoreRequest: TRestoreRequest;
function DefaultRepairRequest: TRepairRequest;
function FirebirdRepairActionTitle(const AAction: TFirebirdRepairAction): string;
function PostgresRepairActionTitle(const AAction: TPostgresRepairAction): string;

implementation

function DefaultBackupRequest: TBackupRequest;
begin
  Result := Default(TBackupRequest);
  Result.Backend := febServicesApi;
  Result.Verbose := True;
  Result.PgFormat := pdfCustom;
  Result.PgNoOwner := True;
end;

function DefaultRestoreRequest: TRestoreRequest;
begin
  Result := Default(TRestoreRequest);
  Result.Backend := febServicesApi;
  Result.Verbose := True;
  Result.FbCreateNew := True;
  Result.FbReplaceExisting := False;
  Result.PgNoOwner := True;
end;

function DefaultRepairRequest: TRepairRequest;
begin
  Result := Default(TRepairRequest);
  Result.Backend := febServicesApi;
  Result.Verbose := True;
  Result.FbAction := fraValidateCheckOnly;
  Result.FbLimboTxId := 'all';
  Result.PgAction := praVacuumAnalyze;
end;

function FirebirdRepairActionTitle(const AAction: TFirebirdRepairAction): string;
begin
  case AAction of
    fraValidateCheckOnly: Result := '1. Validar Somente Leitura (check_db / gfix -v -n)';
    fraValidateFull: Result := '2. Validar Completo com Preparo de Correção (gfix -v -full)';
    fraMendCorrupt: Result := '3. Reparar Base Corrompida (mend / gfix -mend -full -ignore)';
    fraSweep: Result := 'Limpar Lixo / Garbage Collect (sweep / gfix -sweep)';
    fraListLimbo: Result := 'Listar Transações em Limbo (gfix -list)';
    fraCommitLimboAll: Result := 'Confirmar Transações em Limbo (gfix -commit)';
    fraRollbackLimboAll: Result := 'Desfazer Transações em Limbo (gfix -rollback)';
    fraKillShadows: Result := 'Remover Arquivos Shadow Indisponíveis (gfix -kill)';
    fraShutdownForce: Result := 'Desligar Banco Imediatamente (gfix -shut -force 0)';
    fraBringOnline: Result := 'Colocar Banco Online Novamente (gfix -online)';
  else
    Result := 'Manutenção Firebird';
  end;
end;

function PostgresRepairActionTitle(const AAction: TPostgresRepairAction): string;
begin
  case AAction of
    praVacuum: Result := 'VACUUM (VERBOSO) - Recuperar Espaço Morto';
    praVacuumAnalyze: Result := 'VACUUM ANALYZE - Limpeza e Estatísticas';
    praVacuumFull: Result := 'VACUUM FULL - Compactação Profunda (bloqueia tabelas)';
    praReindexDatabase: Result := 'REINDEX DATABASE - Reconstruir Índices Corrompidos';
    praAnalyze: Result := 'ANALYZE - Atualizar Estatísticas do Otimizador';
    praCheckCorruptedIndexes: Result := 'Verificar Tabelas/Índices Inválidos e Integridade';
  else
    Result := 'Manutenção PostgreSQL';
  end;
end;

end.
