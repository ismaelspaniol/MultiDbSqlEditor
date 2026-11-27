unit Infrastructure.JsonQueryHistoryRepository;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson, jsonparser,
  Domain.DatabaseTypes,
  Domain.QueryHistory,
  Domain.AppLogger;

type
  TJsonQueryHistoryService = class(TInterfacedObject, IQueryHistoryService)
  private
    FFilePath: string;
    FLock: TCriticalSection;
    FMaxEntries: Integer;
    FEntries: TQueryHistoryList;
    procedure LoadFromFile;
    procedure SaveToFile;
    procedure TrimToMaxEntries;
  public
    constructor Create(const AFilePath: string = '');
    destructor Destroy; override;
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
  end;

implementation

const
  DEFAULT_MAX_HISTORY_ENTRIES = 500;

constructor TJsonQueryHistoryService.Create(const AFilePath: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMaxEntries := DEFAULT_MAX_HISTORY_ENTRIES;
  FEntries := TQueryHistoryList.Create(True);
  if Trim(AFilePath) <> '' then
    FFilePath := AFilePath
  else
    FFilePath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'query_history.json';
  LoadFromFile;
end;

destructor TJsonQueryHistoryService.Destroy;
begin
  FreeAndNil(FEntries);
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure TJsonQueryHistoryService.TrimToMaxEntries;
begin
  if FMaxEntries < 10 then
    FMaxEntries := 10;
  while FEntries.Count > FMaxEntries do
    FEntries.Delete(FEntries.Count - 1);
end;

procedure TJsonQueryHistoryService.LoadFromFile;
var
  SL: TStringList;
  Data: TJSONData;
  Root: TJSONObject;
  Arr: TJSONArray;
  ItemObj: TJSONObject;
  Entry: TQueryHistoryEntry;
  I: Integer;
  DtStr: string;
  DtVal: TDateTime;
begin
  FLock.Acquire;
  try
    FEntries.Clear;
    if not FileExists(FFilePath) then
      Exit;

    SL := TStringList.Create;
    try
      SL.LoadFromFile(FFilePath, TEncoding.UTF8);
      if Trim(SL.Text) = '' then
        Exit;
      Data := GetJSON(SL.Text);
      try
        if not (Data is TJSONObject) then
          Exit;
        Root := TJSONObject(Data);
        FMaxEntries := Root.Get('maxEntries', DEFAULT_MAX_HISTORY_ENTRIES);
        if FMaxEntries < 10 then
          FMaxEntries := 10;

        if Root.Find('entries', Arr) then
        begin
          for I := 0 to Arr.Count - 1 do
          begin
            if not (Arr.Items[I] is TJSONObject) then
              Continue;
            ItemObj := TJSONObject(Arr.Items[I]);
            Entry := TQueryHistoryEntry.Create;
            DtStr := ItemObj.Get('executedAt', '');
            if TryStrToDateTime(DtStr, DtVal) then
              Entry.ExecutedAt := DtVal
            else
              Entry.ExecutedAt := Now;
            Entry.ProfileId := ItemObj.Get('profileId', '');
            Entry.ProfileName := ItemObj.Get('profileName', '');
            try
              Entry.DatabaseType := StrToDatabaseType(ItemObj.Get('databaseType', 'Firebird'));
            except
              Entry.DatabaseType := dtFirebird;
            end;
            Entry.SqlText := ItemObj.Get('sqlText', '');
            Entry.DurationMs := ItemObj.Get('durationMs', Int64(0));
            Entry.Success := ItemObj.Get('success', True);
            Entry.RowsInfo := ItemObj.Get('rowsInfo', '');
            Entry.ErrorMessage := ItemObj.Get('errorMessage', '');
            FEntries.Add(Entry);
          end;
        end;
        TrimToMaxEntries;
      finally
        Data.Free;
      end;
    except
      on E: Exception do
        LogException('JsonQueryHistoryRepository.Load', E);
    end;
    SL.Free;
  finally
    FLock.Release;
  end;
end;

procedure TJsonQueryHistoryService.SaveToFile;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Entry: TQueryHistoryEntry;
  SL: TStringList;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('maxEntries', FMaxEntries);
    Arr := TJSONArray.Create;
    for Entry in FEntries do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('executedAt', DateTimeToStr(Entry.ExecutedAt));
      Obj.Add('profileId', Entry.ProfileId);
      Obj.Add('profileName', Entry.ProfileName);
      Obj.Add('databaseType', DatabaseTypeToStr(Entry.DatabaseType));
      Obj.Add('sqlText', Entry.SqlText);
      Obj.Add('durationMs', Entry.DurationMs);
      Obj.Add('success', Entry.Success);
      Obj.Add('rowsInfo', Entry.RowsInfo);
      Obj.Add('errorMessage', Entry.ErrorMessage);
      Arr.Add(Obj);
    end;
    Root.Add('entries', Arr);

    SL := TStringList.Create;
    try
      SL.Text := Root.FormatJSON();
      SL.SaveToFile(FFilePath, TEncoding.UTF8);
    finally
      SL.Free;
    end;
  finally
    Root.Free;
  end;
end;

function TJsonQueryHistoryService.GetMaxEntries: Integer;
begin
  FLock.Acquire;
  try
    Result := FMaxEntries;
  finally
    FLock.Release;
  end;
end;

procedure TJsonQueryHistoryService.SetMaxEntries(const AValue: Integer);
begin
  FLock.Acquire;
  try
    if AValue < 10 then
      FMaxEntries := 10
    else if AValue > 50000 then
      FMaxEntries := 50000
    else
      FMaxEntries := AValue;
    TrimToMaxEntries;
    SaveToFile;
  finally
    FLock.Release;
  end;
end;

procedure TJsonQueryHistoryService.RecordExecution(
  const AProfileId, AProfileName: string;
  const ADbType: TDatabaseType;
  const ASqlText: string;
  const ADurationMs: Int64;
  const ASuccess: Boolean;
  const ARowsInfo, AErrorMessage: string
);
var
  Entry: TQueryHistoryEntry;
begin
  if Trim(ASqlText) = '' then
    Exit;

  FLock.Acquire;
  try
    Entry := TQueryHistoryEntry.Create;
    Entry.ExecutedAt := Now;
    Entry.ProfileId := AProfileId;
    Entry.ProfileName := AProfileName;
    Entry.DatabaseType := ADbType;
    Entry.SqlText := ASqlText;
    Entry.DurationMs := ADurationMs;
    Entry.Success := ASuccess;
    Entry.RowsInfo := ARowsInfo;
    Entry.ErrorMessage := AErrorMessage;

    { Mais recente no topo (índice 0) }
    FEntries.Insert(0, Entry);
    TrimToMaxEntries;
    SaveToFile;
  finally
    FLock.Release;
  end;
end;

function TJsonQueryHistoryService.GetAll: TQueryHistoryList;
var
  Entry: TQueryHistoryEntry;
begin
  Result := TQueryHistoryList.Create(True);
  FLock.Acquire;
  try
    for Entry in FEntries do
      Result.Add(Entry.Clone);
  finally
    FLock.Release;
  end;
end;

procedure TJsonQueryHistoryService.ClearAll;
begin
  FLock.Acquire;
  try
    FEntries.Clear;
    SaveToFile;
  finally
    FLock.Release;
  end;
end;

end.
