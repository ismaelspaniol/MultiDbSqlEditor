unit Domain.AppVersion;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  fpjson,
  jsonparser;

const
  APP_NAME = 'Multi-DB SQL Editor';
  APP_VERSION = '1.4.0';
  GITHUB_REPO_OWNER = 'ismaelspaniol';
  GITHUB_REPO_NAME = 'MultiDbSqlEditor';
  GITHUB_RELEASES_API_URL = 'https://api.github.com/repos/ismaelspaniol/MultiDbSqlEditor/releases/latest';
  GITHUB_RELEASES_PAGE_URL = 'https://github.com/ismaelspaniol/MultiDbSqlEditor/releases';

type
  TUpdateReleaseAsset = record
    Name: string;
    DownloadUrl: string;
    SizeBytes: Int64;
  end;

  TUpdateCheckResult = record
    Success: Boolean;
    UpdateAvailable: Boolean;
    CurrentVersion: string;
    LatestVersion: string;
    ReleaseName: string;
    ReleaseNotes: string;
    ReleasePageUrl: string;
    PublishedAt: string;
    RecommendedAsset: TUpdateReleaseAsset;
    ErrorMessage: string;
  end;

function CurrentPlatformName: string;
function CurrentPlatformAssetToken: string;
function NormalizeVersionTag(const ATag: string): string;
function CompareSemVer(const AV1, AV2: string): Integer;
function ParseGitHubReleaseJson(
  const AJsonText, ACurrentVersion, APlatformToken: string
): TUpdateCheckResult;

implementation

function CurrentPlatformName: string;
begin
  {$IFDEF WINDOWS}
    {$IFDEF CPU64}
    Result := 'Windows x64';
    {$ELSE}
    Result := 'Windows x86';
    {$ENDIF}
  {$ELSE}
    {$IFDEF LINUX}
      {$IFDEF CPUAARCH64}
      Result := 'Linux ARM64';
      {$ELSE}
        {$IFDEF CPU64}
        Result := 'Linux x86_64';
        {$ELSE}
        Result := 'Linux x86';
        {$ENDIF}
      {$ENDIF}
    {$ELSE}
      Result := 'Desktop';
    {$ENDIF}
  {$ENDIF}
end;

function CurrentPlatformAssetToken: string;
begin
  {$IFDEF WINDOWS}
    {$IFDEF CPU64}
    Result := 'win64';
    {$ELSE}
    Result := 'win32';
    {$ENDIF}
  {$ELSE}
    {$IFDEF CPUAARCH64}
    Result := 'linux-aarch64';
    {$ELSE}
      {$IFDEF CPU64}
      Result := 'linux-x86_64';
      {$ELSE}
      Result := 'linux';
      {$ENDIF}
    {$ENDIF}
  {$ENDIF}
end;

function NormalizeVersionTag(const ATag: string): string;
begin
  Result := Trim(ATag);
  if (Result <> '') and ((Result[1] = 'v') or (Result[1] = 'V')) then
    Result := Trim(Copy(Result, 2, MaxInt));
end;

procedure SplitSemVer(
  const AVersion: string;
  out AMajor, AMinor, APatch: Integer;
  out APreRelease: string
);
var
  S, Core: string;
  DashPos, P1, P2: Integer;
begin
  AMajor := 0;
  AMinor := 0;
  APatch := 0;
  APreRelease := '';

  S := NormalizeVersionTag(AVersion);
  DashPos := Pos('-', S);
  if DashPos > 0 then
  begin
    Core := Copy(S, 1, DashPos - 1);
    APreRelease := Trim(Copy(S, DashPos + 1, MaxInt));
  end
  else
    Core := S;

  P1 := Pos('.', Core);
  if P1 > 0 then
  begin
    AMajor := StrToIntDef(Copy(Core, 1, P1 - 1), 0);
    Delete(Core, 1, P1);
    P2 := Pos('.', Core);
    if P2 > 0 then
    begin
      AMinor := StrToIntDef(Copy(Core, 1, P2 - 1), 0);
      APatch := StrToIntDef(Copy(Core, P2 + 1, MaxInt), 0);
    end
    else
      AMinor := StrToIntDef(Core, 0);
  end
  else
    AMajor := StrToIntDef(Core, 0);
end;

function CompareSemVer(const AV1, AV2: string): Integer;
var
  Maj1, Min1, Pat1, Maj2, Min2, Pat2: Integer;
  Pre1, Pre2: string;
begin
  SplitSemVer(AV1, Maj1, Min1, Pat1, Pre1);
  SplitSemVer(AV2, Maj2, Min2, Pat2, Pre2);

  if Maj1 <> Maj2 then
  begin
    if Maj1 < Maj2 then Exit(-1) else Exit(1);
  end;
  if Min1 <> Min2 then
  begin
    if Min1 < Min2 then Exit(-1) else Exit(1);
  end;
  if Pat1 <> Pat2 then
  begin
    if Pat1 < Pat2 then Exit(-1) else Exit(1);
  end;

  if (Pre1 = '') and (Pre2 = '') then
    Exit(0);
  if Pre1 = '' then
    Exit(1); // versão final > pre-release
  if Pre2 = '' then
    Exit(-1);
  Result := CompareText(Pre1, Pre2);
  if Result < 0 then Result := -1
  else if Result > 0 then Result := 1;
end;

function ScoreAssetForPlatform(const AAssetName, APlatformToken: string): Integer;
var
  LowerName, LowerToken: string;
begin
  LowerName := LowerCase(Trim(AAssetName));
  LowerToken := LowerCase(Trim(APlatformToken));
  Result := 0;

  if LowerName = '' then
    Exit(0);

  if (LowerToken <> '') and (Pos(LowerToken, LowerName) > 0) then
    Inc(Result, 100);

  if Pos('linux', LowerToken) > 0 then
  begin
    if Pos('linux', LowerName) > 0 then
      Inc(Result, 40);
    if Pos('.tar.gz', LowerName) > 0 then
      Inc(Result, 20)
    else if Pos('.appimage', LowerName) > 0 then
      Inc(Result, 18)
    else if Pos('.zip', LowerName) > 0 then
      Inc(Result, 10);
  end
  else if Pos('win', LowerToken) > 0 then
  begin
    if Pos('.zip', LowerName) > 0 then
      Inc(Result, 20);
  end;
end;

function ParseGitHubReleaseJson(
  const AJsonText, ACurrentVersion, APlatformToken: string
): TUpdateCheckResult;
var
  Data: TJSONData;
  Obj, AssetObj: TJSONObject;
  AssetsArr: TJSONArray;
  I, BestScore, Score: Integer;
  TagName, AssetName: string;
begin
  Result := Default(TUpdateCheckResult);
  Result.CurrentVersion := NormalizeVersionTag(ACurrentVersion);
  Result.ReleasePageUrl := GITHUB_RELEASES_PAGE_URL;

  if Trim(AJsonText) = '' then
  begin
    Result.ErrorMessage := 'Resposta vazia da API de releases.';
    Exit;
  end;

  try
    Data := GetJSON(AJsonText);
  except
    on E: Exception do
    begin
      Result.ErrorMessage := 'JSON inválido: ' + E.Message;
      Exit;
    end;
  end;

  try
    if not (Data is TJSONObject) then
    begin
      Result.ErrorMessage := 'Formato inesperado na resposta da API do GitHub.';
      Exit;
    end;

    Obj := TJSONObject(Data);
    TagName := Obj.Get('tag_name', '');
    if TagName = '' then
    begin
      Result.ErrorMessage := Obj.Get('message', 'Tag de release não encontrada.');
      Exit;
    end;

    Result.LatestVersion := NormalizeVersionTag(TagName);
    Result.ReleaseName := Obj.Get('name', TagName);
    Result.ReleaseNotes := Obj.Get('body', '');
    Result.PublishedAt := Obj.Get('published_at', '');
    if Obj.Get('html_url', '') <> '' then
      Result.ReleasePageUrl := Obj.Get('html_url', '');

    BestScore := 0;
    if Obj.Find('assets', AssetsArr) and (AssetsArr <> nil) then
    begin
      for I := 0 to AssetsArr.Count - 1 do
      begin
        if not (AssetsArr.Items[I] is TJSONObject) then
          Continue;
        AssetObj := TJSONObject(AssetsArr.Items[I]);
        AssetName := AssetObj.Get('name', '');
        Score := ScoreAssetForPlatform(AssetName, APlatformToken);
        if Score > BestScore then
        begin
          BestScore := Score;
          Result.RecommendedAsset.Name := AssetName;
          Result.RecommendedAsset.DownloadUrl := AssetObj.Get('browser_download_url', '');
          Result.RecommendedAsset.SizeBytes := AssetObj.Get('size', Int64(0));
        end;
      end;
    end;

    Result.Success := True;
    Result.UpdateAvailable := CompareSemVer(Result.CurrentVersion, Result.LatestVersion) < 0;
  finally
    Data.Free;
  end;
end;

end.
