unit Test.AppVersion;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.AppVersion;

type
  TTestAppVersion = class(TTestCase)
  published
    procedure TestNormalizeVersionTag;
    procedure TestCompareSemVer;
    procedure TestParseGitHubReleaseJsonWindows;
    procedure TestParseGitHubReleaseJsonLinux;
    procedure TestParseGitHubReleaseJsonInvalid;
  end;

implementation

procedure TTestAppVersion.TestNormalizeVersionTag;
begin
  AssertEquals('1.4.0', NormalizeVersionTag('v1.4.0'));
  AssertEquals('1.4.0', NormalizeVersionTag('V1.4.0'));
  AssertEquals('1.4.0', NormalizeVersionTag(' 1.4.0 '));
end;

procedure TTestAppVersion.TestCompareSemVer;
begin
  AssertEquals(0, CompareSemVer('v1.4.0', '1.4.0'));
  AssertEquals(-1, CompareSemVer('1.3.0', '1.4.0'));
  AssertEquals(1, CompareSemVer('1.5.0', '1.4.9'));
  AssertEquals(-1, CompareSemVer('1.4.0-beta', '1.4.0'));
  AssertEquals(1, CompareSemVer('1.4.0', '1.4.0-rc1'));
  AssertEquals(-1, CompareSemVer('1.9.9', '2.0.0'));
end;

procedure TTestAppVersion.TestParseGitHubReleaseJsonWindows;
const
  SampleJson =
    '{' +
    '  "tag_name": "v1.5.0",' +
    '  "name": "v1.5.0 - Novidades",' +
    '  "body": "Notas da release",' +
    '  "html_url": "https://github.com/ismaelspaniol/MultiDbSqlEditor/releases/tag/v1.5.0",' +
    '  "published_at": "2026-12-01T10:00:00Z",' +
    '  "assets": [' +
    '    {"name": "MultiDbSqlEditor-v1.5.0-linux-x86_64.tar.gz", "browser_download_url": "https://example.com/linux.tar.gz", "size": 12000000},' +
    '    {"name": "MultiDbSqlEditor-v1.5.0-win64.zip", "browser_download_url": "https://example.com/win64.zip", "size": 24000000}' +
    '  ]' +
    '}';
var
  Res: TUpdateCheckResult;
begin
  Res := ParseGitHubReleaseJson(SampleJson, '1.4.0', 'win64');
  AssertTrue(Res.Success);
  AssertTrue(Res.UpdateAvailable);
  AssertEquals('1.5.0', Res.LatestVersion);
  AssertEquals('MultiDbSqlEditor-v1.5.0-win64.zip', Res.RecommendedAsset.Name);
  AssertEquals('https://example.com/win64.zip', Res.RecommendedAsset.DownloadUrl);
  AssertEquals(Int64(24000000), Res.RecommendedAsset.SizeBytes);
end;

procedure TTestAppVersion.TestParseGitHubReleaseJsonLinux;
const
  SampleJson =
    '{' +
    '  "tag_name": "v1.5.0",' +
    '  "name": "v1.5.0",' +
    '  "body": "Linux test",' +
    '  "assets": [' +
    '    {"name": "MultiDbSqlEditor-v1.5.0-win64.zip", "browser_download_url": "https://example.com/win64.zip", "size": 24000000},' +
    '    {"name": "MultiDbSqlEditor-v1.5.0-linux-x86_64.tar.gz", "browser_download_url": "https://example.com/linux.tar.gz", "size": 12000000}' +
    '  ]' +
    '}';
var
  Res: TUpdateCheckResult;
begin
  Res := ParseGitHubReleaseJson(SampleJson, '1.5.0', 'linux-x86_64');
  AssertTrue(Res.Success);
  AssertFalse(Res.UpdateAvailable);
  AssertEquals('MultiDbSqlEditor-v1.5.0-linux-x86_64.tar.gz', Res.RecommendedAsset.Name);
end;

procedure TTestAppVersion.TestParseGitHubReleaseJsonInvalid;
var
  Res: TUpdateCheckResult;
begin
  Res := ParseGitHubReleaseJson('{invalid', '1.4.0', 'win64');
  AssertFalse(Res.Success);
  AssertTrue(Res.ErrorMessage <> '');
end;

initialization
  RegisterTest(TTestAppVersion);

end.
