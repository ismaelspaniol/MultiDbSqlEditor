unit Infrastructure.GitHubUpdateService;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Process,
  mormot.core.base,
  mormot.net.client,
  Domain.Interfaces,
  Domain.AppVersion,
  Domain.AppLogger;

type
  { Consulta a última release no GitHub via mORMot2 HttpGet com fallback para curl (Windows/Linux) }
  TGitHubUpdateService = class(TInterfacedObject, IUpdateCheckService)
  private
    function TryFetchViaCurl(out AJsonText, AErrorMessage: string): Boolean;
  public
    function FetchLatestReleaseJson(out AJsonText, AErrorMessage: string): Boolean;
  end;

implementation

function TGitHubUpdateService.TryFetchViaCurl(out AJsonText, AErrorMessage: string): Boolean;
var
  Proc: TProcess;
  OutStream: TMemoryStream;
  Buf: array[0..4095] of Byte;
  BytesRead: LongInt;
  CurlExe: string;
begin
  Result := False;
  AJsonText := '';
  AErrorMessage := '';

  {$IFDEF WINDOWS}
  CurlExe := 'curl.exe';
  {$ELSE}
  CurlExe := 'curl';
  {$ENDIF}

  Proc := TProcess.Create(nil);
  OutStream := TMemoryStream.Create;
  try
    Proc.Executable := CurlExe;
    Proc.Parameters.Add('-fsSL');
    Proc.Parameters.Add('--max-time');
    Proc.Parameters.Add('8');
    Proc.Parameters.Add('-H');
    Proc.Parameters.Add('User-Agent: MultiDbSqlEditor/' + APP_VERSION);
    Proc.Parameters.Add('-H');
    Proc.Parameters.Add('Accept: application/vnd.github+json');
    Proc.Parameters.Add(GITHUB_RELEASES_API_URL);
    Proc.Options := [poUsePipes, poNoConsole];
    try
      Proc.Execute;
      while Proc.Running do
      begin
        while Proc.Output.NumBytesAvailable > 0 do
        begin
          BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
          if BytesRead > 0 then
            OutStream.WriteBuffer(Buf[0], BytesRead);
        end;
        Sleep(15);
      end;
      while Proc.Output.NumBytesAvailable > 0 do
      begin
        BytesRead := Proc.Output.Read(Buf[0], SizeOf(Buf));
        if BytesRead > 0 then
          OutStream.WriteBuffer(Buf[0], BytesRead);
      end;

      if (Proc.ExitStatus = 0) and (OutStream.Size > 0) then
      begin
        SetString(AJsonText, PAnsiChar(OutStream.Memory), OutStream.Size);
        Result := True;
      end
      else
        AErrorMessage := Format('curl retornou código %d.', [Proc.ExitStatus]);
    except
      on E: Exception do
      begin
        LogException('GitHubUpdateService.TryFetchViaCurl', E);
        AErrorMessage := E.Message;
      end;
    end;
  finally
    OutStream.Free;
    Proc.Free;
  end;
end;

function TGitHubUpdateService.FetchLatestReleaseJson(out AJsonText, AErrorMessage: string): Boolean;
var
  InHdr, OutHdr: RawUtf8;
  StatusCode: Integer;
  Resp: RawByteString;
  CurlErr: string;
begin
  Result := False;
  AJsonText := '';
  AErrorMessage := '';

  StatusCode := 0;
  InHdr := RawUtf8('User-Agent: MultiDbSqlEditor/' + APP_VERSION + #13#10 +
                   'Accept: application/vnd.github+json');
  try
    Resp := HttpGet(
      RawUtf8(GITHUB_RELEASES_API_URL),
      InHdr,
      @OutHdr,
      True,
      @StatusCode,
      8000,
      False,
      False
    );
    if (StatusCode = 200) and (Resp <> '') then
    begin
      AJsonText := string(Resp);
      Exit(True);
    end;
    AErrorMessage := Format('HTTP %d ao consultar GitHub Releases.', [StatusCode]);
  except
    on E: Exception do
    begin
      LogException('GitHubUpdateService.HttpGet', E);
      AErrorMessage := E.Message;
    end;
  end;

  if TryFetchViaCurl(AJsonText, CurlErr) then
    Exit(True);

  if CurlErr <> '' then
    AErrorMessage := AErrorMessage + ' (Fallback curl: ' + CurlErr + ')';
  LogWarn('GitHubUpdateService', AErrorMessage);
end;

end.
