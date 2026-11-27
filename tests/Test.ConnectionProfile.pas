unit Test.ConnectionProfile;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile;

type
  TTestConnectionProfile = class(TTestCase)
  published
    procedure TestParseAndBuildFirebirdConnectionString;
    procedure TestEnvironmentAndEffectiveDatabase;
  end;

implementation

procedure TTestConnectionProfile.TestParseAndBuildFirebirdConnectionString;
var
  Host, Db: string;
  Port: Word;
begin
  AssertTrue(TConnectionProfile.TryParseFirebirdString('127.0.0.1/3055:D:\dados\app.fdb', Host, Port, Db));
  AssertEquals('127.0.0.1', Host);
  AssertEquals(3055, Port);
  AssertEquals('D:\dados\app.fdb', Db);
  AssertEquals('127.0.0.1/3055:D:\dados\app.fdb', TConnectionProfile.BuildConnectionString(dtFirebird, Host, Port, Db));
end;

procedure TTestConnectionProfile.TestEnvironmentAndEffectiveDatabase;
var
  P: TConnectionProfile;
begin
  P := TConnectionProfile.Create;
  try
    P.DatabaseType := dtPostgreSQL;
    P.Database := '';
    P.EnvironmentKind := 'Producao';
    AssertEquals('postgres', P.EffectiveDatabase);
    AssertTrue(P.IsProduction);
  finally
    P.Free;
  end;
end;

initialization
  RegisterTest(TTestConnectionProfile);

end.
