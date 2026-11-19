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
  Domain.Interfaces;

type
  { Persistência local de perfis de conexão em arquivo JSON }
  TJsonConnectionRepository = class(TInterfacedObject, IConnectionRepository)
  private
    FFilePath: string;
    function LoadJsonArray: TJSONArray;
    procedure SaveJsonArray(const AArray: TJSONArray);
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
  end;

implementation

constructor TJsonConnectionRepository.Create(const AFilePath: string);
begin
  inherited Create;
  if Trim(AFilePath) <> '' then
    FFilePath := AFilePath
  else
    FFilePath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'connections.json';
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
      Result := AEncoded;
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
  Result.Add('clientLibraryPath', AProfile.ClientLibraryPath);
  Result.Add('firebirdVersion', FirebirdVersionToStr(AProfile.FirebirdVersion));
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
  Result.ClientLibraryPath := AObj.Get('clientLibraryPath', '');
  Result.FirebirdVersion := StrToFirebirdVersion(AObj.Get('firebirdVersion', 'Auto'));
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

end.
