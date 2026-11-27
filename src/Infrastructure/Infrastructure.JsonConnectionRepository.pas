unit Infrastructure.JsonConnectionRepository;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpjson,
  jsonparser,
  base64,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.Interfaces,
  Domain.AppLogger;

type
  { Persistência local de perfis de conexão em arquivo JSON }
  TJsonConnectionRepository = class(TInterfacedObject, IConnectionRepository)
  private
    FFilePath: string;
    FFoldersFilePath: string;
    function LoadJsonArray: TJSONArray;
    procedure SaveJsonArray(const AArray: TJSONArray);
    function LoadFoldersJsonObject: TJSONObject;
    procedure SaveFoldersJsonObject(const AObj: TJSONObject);
    function ProfileToJson(const AProfile: TConnectionProfile): TJSONObject;
    function JsonToProfile(const AObj: TJSONObject): TConnectionProfile;
    function EncodeSecret(const APlain: string): string;
    function DecodeSecret(const AEncoded: string): string;
  public
    constructor Create(const AFilePath: string = '');
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

implementation

constructor TJsonConnectionRepository.Create(const AFilePath: string);
begin
  inherited Create;
  if Trim(AFilePath) <> '' then
    FFilePath := AFilePath
  else
    FFilePath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'connections.json';
  FFoldersFilePath := IncludeTrailingPathDelimiter(ExtractFilePath(FFilePath)) + 'connection_folders.json';
end;

function TJsonConnectionRepository.EncodeSecret(const APlain: string): string;
begin
  if APlain = '' then
    Result := ''
  else
    Result := EncodeStringBase64(APlain);
end;

function TJsonConnectionRepository.DecodeSecret(const AEncoded: string): string;
begin
  if AEncoded = '' then
    Result := ''
  else
    try
      Result := DecodeStringBase64(AEncoded);
    except
      on E: Exception do
      begin
        LogException('JsonConnectionRepository.DecodeSecret', E);
        Result := AEncoded;
      end;
    end;
end;

function TJsonConnectionRepository.LoadJsonArray: TJSONArray;
var
  SL: TStringList;
  Data: TJSONData;
begin
  if not FileExists(FFilePath) then
  begin
    Result := TJSONArray.Create;
    Exit;
  end;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FFilePath, TEncoding.UTF8);
    if Trim(SL.Text) = '' then
    begin
      Result := TJSONArray.Create;
      Exit;
    end;
    Data := GetJSON(SL.Text);
    if Data is TJSONArray then
      Result := TJSONArray(Data)
    else
    begin
      Data.Free;
      Result := TJSONArray.Create;
    end;
  finally
    SL.Free;
  end;
end;

procedure TJsonConnectionRepository.SaveJsonArray(const AArray: TJSONArray);
var
  SL: TStringList;
  Dir: string;
begin
  Dir := ExtractFileDir(FFilePath);
  if (Dir <> '') and (not DirectoryExists(Dir)) then
    ForceDirectories(Dir);

  SL := TStringList.Create;
  try
    SL.Text := AArray.FormatJSON;
    SL.SaveToFile(FFilePath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

function TJsonConnectionRepository.ProfileToJson(const AProfile: TConnectionProfile): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', AProfile.Id);
  Result.Add('name', AProfile.Name);
  Result.Add('databaseType', DatabaseTypeToStr(AProfile.DatabaseType));
  Result.Add('host', AProfile.Host);
  Result.Add('port', AProfile.Port);
  Result.Add('database', AProfile.Database);
  Result.Add('username', AProfile.Username);
  Result.Add('password', EncodeSecret(AProfile.Password));
  Result.Add('charset', AProfile.Charset);
  Result.Add('role', AProfile.Role);
  Result.Add('schema', AProfile.Schema);
  Result.Add('clientLibraryPath', AProfile.ClientLibraryPath);
  Result.Add('firebirdVersion', FirebirdVersionToStr(AProfile.FirebirdVersion));
  Result.Add('environmentKind', AProfile.EnvironmentKind);
  Result.Add('folder', Trim(AProfile.Folder));
end;

function TJsonConnectionRepository.JsonToProfile(const AObj: TJSONObject): TConnectionProfile;
begin
  Result := TConnectionProfile.Create;
  Result.Id := AObj.Get('id', '');
  Result.Name := AObj.Get('name', '');
  Result.DatabaseType := StrToDatabaseType(AObj.Get('databaseType', 'Firebird'));
  Result.Host := AObj.Get('host', 'localhost');
  Result.Port := Word(AObj.Get('port', Integer(DefaultPortForDatabase(Result.DatabaseType))));
  Result.Database := AObj.Get('database', '');
  Result.Username := AObj.Get('username', '');
  Result.Password := DecodeSecret(AObj.Get('password', ''));
  Result.Charset := AObj.Get('charset', 'UTF8');
  Result.Role := AObj.Get('role', '');
  Result.Schema := AObj.Get('schema', 'public');
  Result.ClientLibraryPath := AObj.Get('clientLibraryPath', '');
  Result.FirebirdVersion := StrToFirebirdVersion(AObj.Get('firebirdVersion', 'Auto'));
  Result.EnvironmentKind := AObj.Get('environmentKind', 'Padrao');
  Result.Folder := Trim(AObj.Get('folder', ''));
end;

function TJsonConnectionRepository.GetAll: TConnectionProfileList;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Result := TConnectionProfileList.Create(True);
  Arr := LoadJsonArray;
  try
    for I := 0 to Arr.Count - 1 do
    begin
      if Arr.Items[I] is TJSONObject then
        Result.Add(JsonToProfile(TJSONObject(Arr.Items[I])));
    end;
  finally
    Arr.Free;
  end;
end;

function TJsonConnectionRepository.FindById(const AId: string): TConnectionProfile;
var
  List: TConnectionProfileList;
  Item: TConnectionProfile;
begin
  Result := nil;
  List := GetAll;
  try
    for Item in List do
    begin
      if SameText(Item.Id, AId) then
      begin
        Result := Item.Clone;
        Break;
      end;
    end;
  finally
    List.Free;
  end;
end;

procedure TJsonConnectionRepository.Save(const AProfile: TConnectionProfile);
var
  Arr: TJSONArray;
  I: Integer;
  Obj: TJSONObject;
  Found: Boolean;
begin
  Arr := LoadJsonArray;
  try
    Found := False;
    for I := 0 to Arr.Count - 1 do
    begin
      if (Arr.Items[I] is TJSONObject) and
         SameText(TJSONObject(Arr.Items[I]).Get('id', ''), AProfile.Id) then
      begin
        Arr.Items[I] := ProfileToJson(AProfile);
        Found := True;
        Break;
      end;
    end;

    if not Found then
    begin
      Obj := ProfileToJson(AProfile);
      Arr.Add(Obj);
    end;

    SaveJsonArray(Arr);
    if Trim(AProfile.Folder) <> '' then
      AddFolder(Trim(AProfile.Folder));
  finally
    Arr.Free;
  end;
end;

procedure TJsonConnectionRepository.Delete(const AId: string);
var
  Arr: TJSONArray;
  I: Integer;
begin
  Arr := LoadJsonArray;
  try
    for I := Arr.Count - 1 downto 0 do
    begin
      if (Arr.Items[I] is TJSONObject) and
         SameText(TJSONObject(Arr.Items[I]).Get('id', ''), AId) then
      begin
        Arr.Delete(I);
      end;
    end;
    SaveJsonArray(Arr);
  finally
    Arr.Free;
  end;
end;

procedure TJsonConnectionRepository.Reorder(const AOrderedIds: TStrings);
var
  Arr, NewArr: TJSONArray;
  Used: array of Boolean;
  I, J: Integer;
  TargetId: string;
begin
  if (AOrderedIds = nil) or (AOrderedIds.Count = 0) then
    Exit;

  Arr := LoadJsonArray;
  try
    if Arr.Count <= 1 then
      Exit;

    SetLength(Used, Arr.Count);
    for J := 0 to Arr.Count - 1 do
      Used[J] := False;

    NewArr := TJSONArray.Create;
    try
      for I := 0 to AOrderedIds.Count - 1 do
      begin
        TargetId := Trim(AOrderedIds[I]);
        if TargetId = '' then
          Continue;

        for J := 0 to Arr.Count - 1 do
        begin
          if (not Used[J]) and (Arr.Items[J] is TJSONObject) and
             SameText(TJSONObject(Arr.Items[J]).Get('id', ''), TargetId) then
          begin
            Used[J] := True;
            NewArr.Add(Arr.Items[J].Clone);
            Break;
          end;
        end;
      end;

      for J := 0 to Arr.Count - 1 do
      begin
        if not Used[J] then
          NewArr.Add(Arr.Items[J].Clone);
      end;

      SaveJsonArray(NewArr);
    finally
      NewArr.Free;
    end;
  finally
    Arr.Free;
  end;
end;

function TJsonConnectionRepository.LoadFoldersJsonObject: TJSONObject;
var
  SL: TStringList;
  Data: TJSONData;
begin
  if not FileExists(FFoldersFilePath) then
  begin
    Result := TJSONObject.Create;
    Exit;
  end;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FFoldersFilePath, TEncoding.UTF8);
    if Trim(SL.Text) = '' then
    begin
      Result := TJSONObject.Create;
      Exit;
    end;
    try
      Data := GetJSON(SL.Text);
      if Data is TJSONObject then
        Result := TJSONObject(Data)
      else
      begin
        Data.Free;
        Result := TJSONObject.Create;
      end;
    except
      Result := TJSONObject.Create;
    end;
  finally
    SL.Free;
  end;
end;

procedure TJsonConnectionRepository.SaveFoldersJsonObject(const AObj: TJSONObject);
var
  SL: TStringList;
  Dir: string;
begin
  Dir := ExtractFileDir(FFoldersFilePath);
  if (Dir <> '') and (not DirectoryExists(Dir)) then
    ForceDirectories(Dir);

  SL := TStringList.Create;
  try
    SL.Text := AObj.FormatJSON;
    SL.SaveToFile(FFoldersFilePath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

procedure TJsonConnectionRepository.GetFolders(const ATarget: TStrings);
var
  RootObj: TJSONObject;
  Arr: TJSONArray;
  FolderName: string;
  I, J, K: Integer;
  ExistsInTarget: Boolean;
  Profiles: TConnectionProfileList;
  Profile: TConnectionProfile;
begin
  if ATarget = nil then
    Exit;
  ATarget.Clear;

  RootObj := LoadFoldersJsonObject;
  try
    for K := 0 to RootObj.Count - 1 do
    begin
      if RootObj.Items[K] is TJSONArray then
      begin
        Arr := TJSONArray(RootObj.Items[K]);
        for I := 0 to Arr.Count - 1 do
        begin
          FolderName := Trim(Arr.Strings[I]);
          if FolderName = '' then
            Continue;
          ExistsInTarget := False;
          for J := 0 to ATarget.Count - 1 do
            if SameText(ATarget[J], FolderName) then
            begin
              ExistsInTarget := True;
              Break;
            end;
          if not ExistsInTarget then
            ATarget.Add(FolderName);
        end;
      end;
    end;
  finally
    RootObj.Free;
  end;

  { Também garante que pastas referenciadas em connections.json apareçam }
  Profiles := GetAll;
  try
    for Profile in Profiles do
    begin
      if Trim(Profile.Folder) <> '' then
      begin
        FolderName := Trim(Profile.Folder);
        ExistsInTarget := False;
        for J := 0 to ATarget.Count - 1 do
          if SameText(ATarget[J], FolderName) then
          begin
            ExistsInTarget := True;
            Break;
          end;
        if not ExistsInTarget then
          ATarget.Add(FolderName);
      end;
    end;
  finally
    Profiles.Free;
  end;
end;

procedure TJsonConnectionRepository.AddFolder(const AFolderName: string);
const
  KEY_GLOBAL = 'folders';
var
  CleanName: string;
  RootObj: TJSONObject;
  Arr: TJSONArray;
  I, K: Integer;
begin
  CleanName := Trim(AFolderName);
  if CleanName = '' then
    Exit;

  RootObj := LoadFoldersJsonObject;
  try
    for K := 0 to RootObj.Count - 1 do
      if RootObj.Items[K] is TJSONArray then
      begin
        Arr := TJSONArray(RootObj.Items[K]);
        for I := 0 to Arr.Count - 1 do
          if SameText(Trim(Arr.Strings[I]), CleanName) then
            Exit;
      end;

    if not RootObj.Find(KEY_GLOBAL, Arr) then
    begin
      Arr := TJSONArray.Create;
      RootObj.Add(KEY_GLOBAL, Arr);
    end;

    Arr.Add(CleanName);
    SaveFoldersJsonObject(RootObj);
  finally
    RootObj.Free;
  end;
end;

procedure TJsonConnectionRepository.RenameFolder(const AOldName, ANewName: string);
const
  KEY_GLOBAL = 'folders';
var
  CleanOld, CleanNew: string;
  RootObj, ConnObj: TJSONObject;
  FoldersArr, ConnsArr: TJSONArray;
  I, K, DuplicateIdx: Integer;
  ChangedFolders, ChangedConns: Boolean;
begin
  CleanOld := Trim(AOldName);
  CleanNew := Trim(ANewName);
  if (CleanOld = '') or (CleanNew = '') then
    Exit;

  RootObj := LoadFoldersJsonObject;
  try
    ChangedFolders := False;
    DuplicateIdx := -1;

    for K := 0 to RootObj.Count - 1 do
      if RootObj.Items[K] is TJSONArray then
      begin
        FoldersArr := TJSONArray(RootObj.Items[K]);
        for I := 0 to FoldersArr.Count - 1 do
          if SameText(Trim(FoldersArr.Strings[I]), CleanNew) and (not SameText(CleanOld, CleanNew)) then
            DuplicateIdx := I;
      end;

    for K := 0 to RootObj.Count - 1 do
      if RootObj.Items[K] is TJSONArray then
      begin
        FoldersArr := TJSONArray(RootObj.Items[K]);
        for I := FoldersArr.Count - 1 downto 0 do
        begin
          if SameText(Trim(FoldersArr.Strings[I]), CleanOld) then
          begin
            if DuplicateIdx >= 0 then
              FoldersArr.Delete(I)
            else
              FoldersArr.Strings[I] := CleanNew;
            ChangedFolders := True;
          end;
        end;
      end;

    if (not ChangedFolders) and (DuplicateIdx < 0) then
    begin
      if not RootObj.Find(KEY_GLOBAL, FoldersArr) then
      begin
        FoldersArr := TJSONArray.Create;
        RootObj.Add(KEY_GLOBAL, FoldersArr);
      end;
      FoldersArr.Add(CleanNew);
      ChangedFolders := True;
    end;

    if ChangedFolders then
      SaveFoldersJsonObject(RootObj);
  finally
    RootObj.Free;
  end;

  ChangedConns := False;
  ConnsArr := LoadJsonArray;
  try
    for I := 0 to ConnsArr.Count - 1 do
    begin
      if ConnsArr.Items[I] is TJSONObject then
      begin
        ConnObj := TJSONObject(ConnsArr.Items[I]);
        if SameText(Trim(ConnObj.Get('folder', '')), CleanOld) then
        begin
          ConnObj.Strings['folder'] := CleanNew;
          ChangedConns := True;
        end;
      end;
    end;
    if ChangedConns then
      SaveJsonArray(ConnsArr);
  finally
    ConnsArr.Free;
  end;
end;

procedure TJsonConnectionRepository.DeleteFolder(const AFolderName: string);
var
  CleanName: string;
  RootObj, ConnObj: TJSONObject;
  FoldersArr, ConnsArr: TJSONArray;
  I, K: Integer;
  ChangedFolders, ChangedConns: Boolean;
begin
  CleanName := Trim(AFolderName);
  if CleanName = '' then
    Exit;

  RootObj := LoadFoldersJsonObject;
  try
    ChangedFolders := False;
    for K := 0 to RootObj.Count - 1 do
    begin
      if RootObj.Items[K] is TJSONArray then
      begin
        FoldersArr := TJSONArray(RootObj.Items[K]);
        for I := FoldersArr.Count - 1 downto 0 do
        begin
          if SameText(Trim(FoldersArr.Strings[I]), CleanName) then
          begin
            FoldersArr.Delete(I);
            ChangedFolders := True;
          end;
        end;
      end;
    end;
    if ChangedFolders then
      SaveFoldersJsonObject(RootObj);
  finally
    RootObj.Free;
  end;

  ChangedConns := False;
  ConnsArr := LoadJsonArray;
  try
    for I := 0 to ConnsArr.Count - 1 do
    begin
      if ConnsArr.Items[I] is TJSONObject then
      begin
        ConnObj := TJSONObject(ConnsArr.Items[I]);
        if SameText(Trim(ConnObj.Get('folder', '')), CleanName) then
        begin
          ConnObj.Strings['folder'] := '';
          ChangedConns := True;
        end;
      end;
    end;
    if ChangedConns then
      SaveJsonArray(ConnsArr);
  finally
    ConnsArr.Free;
  end;
end;

end.
