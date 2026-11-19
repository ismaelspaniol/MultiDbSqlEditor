program MultiDbSqlEditor;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // LCL widgetset
  Forms,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Application.TestConnectionUseCase,
  Application.ManageConnectionsUseCase,
  Application.ExecuteQueryUseCase,
  Infrastructure.ProviderFactory,
  Presentation.MainForm;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Forms.Application.Scaled := True;
  Forms.Application.Initialize;
  Forms.Application.CreateForm(TMainForm, MainForm);
  Forms.Application.Run;
end.
