unit Domain.MonitoringTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TMonitoredConnection = record
    ConnectionId: Int64;
    UserName: string;
    RoleName: string;
    State: string;
    StartedAt: string;
    RemoteAddress: string;
    ClientProcess: string;
    RemotePid: string;
    ServerPid: string;
    IsCurrent: Boolean;
  end;

  TMonitoredTransaction = record
    TransactionId: Int64;
    ConnectionId: Int64;
    UserName: string;
    State: string;
    StartedAt: string;
    IsolationMode: string;
    ReadOnlyStr: string;
    RemoteAddress: string;
    ClientProcess: string;
    StatementId: Int64;
    SqlText: string;
    IsCurrentConnection: Boolean;
  end;

  TMonitoredStatement = record
    StatementId: Int64;
    ConnectionId: Int64;
    TransactionId: Int64;
    UserName: string;
    State: string;
    StartedAt: string;
    RemoteAddress: string;
    ClientProcess: string;
    SqlText: string;
    IsCurrentConnection: Boolean;
  end;

  TMonitoringSnapshot = class
  public
    CapturedAt: TDateTime;
    Connections: array of TMonitoredConnection;
    Transactions: array of TMonitoredTransaction;
    Statements: array of TMonitoredStatement;
    constructor Create;
    procedure Clear;
  end;

implementation

constructor TMonitoringSnapshot.Create;
begin
  inherited Create;
  Clear;
end;

procedure TMonitoringSnapshot.Clear;
begin
  CapturedAt := 0;
  SetLength(Connections, 0);
  SetLength(Transactions, 0);
  SetLength(Statements, 0);
end;

end.
