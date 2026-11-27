unit Domain.Interfaces;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  Generics.Collections,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult;

const
  DDL_CANCELLED_MESSAGE = '__DDL_CANCELLED__';

type
  TConnectionProfileList = specialize TObjectList<TConnectionProfile>;

  { Callback estilo IBExpert para revisar/copiar DDL antes de executar alterações no banco }
  TDdlConfirmCallback = function(
    const AProfile: TConnectionProfile;
    const AOperationTitle: string;
    const ADdlScript: string;
    out AEditedDdl: string;
    const AAllowEdit: Boolean
  ): Boolean of object;

  { Callback chamado após execução bem-sucedida de DDL (ex.: registrar no histórico) }
  TDdlExecutedCallback = procedure(
    const AProfile: TConnectionProfile;
    const AOperationTitle: string;
    const ADdlScript: string;
    const ADurationMs: Int64
  ) of object;

  { Sessão isolada de conexão e transação (ex.: uma por aba do editor SQL) }
  IDatabaseSession = interface
    ['{8F6A52F0-8A2C-4E1C-A31B-6C9E01B5A001}']
    function IsConnected: Boolean;
    function InTransaction: Boolean;
    procedure Connect;
    procedure Disconnect;
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function ExecuteSQL(
      const ASQL: string;
      const AAutoCommit: Boolean = False;
      const AFetchBatchSize: Integer = 100;
      const AMemoryLimitBytes: Int64 = DEFAULT_RESULT_MEMORY_LIMIT_BYTES
    ): TQueryResult;
    function CancelRunningQuery(out AMessage: string): Boolean;
  end;

  { Provedor específico de um banco de dados (Firebird, PostgreSQL, etc.) }
  IDatabaseProvider = interface
    ['{8F6A52F0-8A2C-4E1C-A31B-6C9E01B5A002}']
    function DatabaseType: TDatabaseType;
    function TestConnection(const AProfile: TConnectionProfile; out AErrorMessage: string): Boolean;
    function CreateSession(const AProfile: TConnectionProfile): IDatabaseSession;
  end;

  { Fábrica que resolve o provedor correto a partir do TDatabaseType }
  IDatabaseProviderFactory = interface
    ['{8F6A52F0-8A2C-4E1C-A31B-6C9E01B5A003}']
    function GetProvider(const AType: TDatabaseType): IDatabaseProvider;
  end;

  { Repositório para persistência local dos perfis de conexão }
  IConnectionRepository = interface
    ['{8F6A52F0-8A2C-4E1C-A31B-6C9E01B5A004}']
    function GetAll: TConnectionProfileList;
    function FindById(const AId: string): TConnectionProfile;
    procedure Save(const AProfile: TConnectionProfile);
    procedure Delete(const AId: string);
    procedure Reorder(const AOrderedIds: TStrings);
    procedure GetFolders(const ATarget: TStrings);
    procedure AddFolder(const AFolderName: string);
    procedure RenameFolder(const AOldName, ANewName: string);
    procedure DeleteFolder(const AFolderName: string);
  end;

  function IsDdlCancelledMessage(const AMessage: string): Boolean;

implementation

function IsDdlCancelledMessage(const AMessage: string): Boolean;
begin
  Result := (AMessage = DDL_CANCELLED_MESSAGE);
end;

end.
