unit Test.AppLogger;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.AppLogger;

type
  TTestAppLogger = class(TTestCase)
  private
    FTempLogPath: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLogWritesToFileAndRingBuffer;
  end;

implementation

procedure TTestAppLogger.SetUp;
begin
  FTempLogPath := GetTempDir(False) + 'multidb_test_' + IntToStr(GetTickCount64) + '.log';
  AppLogger.ClearForTest;
  AppLogger.SetLogFilePathForTest(FTempLogPath);
end;

procedure TTestAppLogger.TearDown;
begin
  AppLogger.SetLogFilePathForTest('');
  AppLogger.ClearForTest;
  if FileExists(FTempLogPath) then
    DeleteFile(FTempLogPath);
end;

procedure TTestAppLogger.TestLogWritesToFileAndRingBuffer;
var
  SL: TStringList;
begin
  LogInfo('TestContext', 'Mensagem de teste');
  AssertTrue(FileExists(FTempLogPath));
  SL := TStringList.Create;
  try
    AppLogger.GetRecentLines(SL);
    AssertEquals(1, SL.Count);
    AssertTrue(Pos('[INFO] [TestContext] Mensagem de teste', SL[0]) > 0);
  finally
    SL.Free;
  end;
end;

initialization
  RegisterTest(TTestAppLogger);

end.
