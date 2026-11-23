unit Domain.QueryHistory;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Generics.Collections, Domain.DatabaseTypes;

type
  TQueryHistoryEntry = class
  public
    ExecutedAt: TDateTime;
    ProfileId: string;
    ProfileName: string;
    DatabaseType: TDatabaseType;
    SqlText: string;
    DurationMs: Int64;
    Success: Boolean;
    RowsInfo: string;
    ErrorMessage: string;
    function Clone: TQueryHistoryEntry;
  end;

  TQueryHistoryList = specialize TObjectList<TQueryHistoryEntry>;

  IQueryHistoryService = interface
    ['{D7E3A120-4B8F-4A9E-9C12-77B201A9F001}']
    function GetMaxEntries: Integer;
    procedure SetMaxEntries(const AValue: Integer);
    procedure RecordExecution(
      const AProfileId, AProfileName: string;
      const ADbType: TDatabaseType;
      const ASqlText: string;
      const ADurationMs: Int64;
      const ASuccess: Boolean;
      const ARowsInfo, AErrorMessage: string
    );
    function GetAll: TQueryHistoryList;
    procedure ClearAll;
    property MaxEntries: Integer read GetMaxEntries write SetMaxEntries;
  end;

implementation

function TQueryHistoryEntry.Clone: TQueryHistoryEntry;
begin
  Result := TQueryHistoryEntry.Create;
  Result.ExecutedAt := ExecutedAt;
  Result.ProfileId := ProfileId;
  Result.ProfileName := ProfileName;
  Result.DatabaseType := DatabaseType;
  Result.SqlText := SqlText;
  Result.DurationMs := DurationMs;
  Result.Success := Success;
  Result.RowsInfo := RowsInfo;
  Result.ErrorMessage := ErrorMessage;
end;

end.
