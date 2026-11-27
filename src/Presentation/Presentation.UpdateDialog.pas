unit Presentation.UpdateDialog;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  StdCtrls,
  ExtCtrls,
  Clipbrd,
  LCLIntf,
  Domain.AppVersion,
  Domain.AppLogger;

type
  { Diálogo modal para exibir nova versão disponível e abrir download/release }
  TUpdateDialog = class
  public
    class function Execute(
      const AResult: TUpdateCheckResult;
      out AIgnoreThisVersion: Boolean
    ): Boolean;
  end;

  { Diálogo modal para exibir log diagnóstico cross-platform }
  TDiagnosticLogDialog = class
  public
    class procedure Execute;
  end;

implementation

type
  TUpdateDialogForm = class(TForm)
  private
    FDownloadUrl: string;
    FReleasePageUrl: string;
    FIgnoreClicked: Boolean;
    procedure BtnDownloadClick(Sender: TObject);
    procedure BtnGitHubClick(Sender: TObject);
    procedure BtnIgnoreClick(Sender: TObject);
  end;

procedure TUpdateDialogForm.BtnDownloadClick(Sender: TObject);
begin
  if FDownloadUrl <> '' then
    OpenURL(FDownloadUrl)
  else if FReleasePageUrl <> '' then
    OpenURL(FReleasePageUrl);
end;

procedure TUpdateDialogForm.BtnGitHubClick(Sender: TObject);
begin
  if FReleasePageUrl <> '' then
    OpenURL(FReleasePageUrl);
end;

procedure TUpdateDialogForm.BtnIgnoreClick(Sender: TObject);
begin
  FIgnoreClicked := True;
  ModalResult := mrIgnore;
end;

class function TUpdateDialog.Execute(
  const AResult: TUpdateCheckResult;
  out AIgnoreThisVersion: Boolean
): Boolean;
var
  Frm: TUpdateDialogForm;
  PnlTop, PnlBottom: TPanel;
  LblTitle, LblMeta: TLabel;
  MemNotes: TMemo;
  BtnDownload, BtnGitHub, BtnIgnore, BtnClose: TButton;
  AssetSizeMb: Double;
begin
  AIgnoreThisVersion := False;
  Result := False;

  Frm := TUpdateDialogForm.CreateNew(nil);
  try
    Frm.Caption := 'Atualização Disponível - ' + APP_NAME;
    Frm.Position := poScreenCenter;
    Frm.BorderStyle := bsDialog;
    Frm.Width := 620;
    Frm.Height := 450;
    Frm.FDownloadUrl := AResult.RecommendedAsset.DownloadUrl;
    Frm.FReleasePageUrl := AResult.ReleasePageUrl;
    Frm.FIgnoreClicked := False;

    PnlTop := TPanel.Create(Frm);
    PnlTop.Parent := Frm;
    PnlTop.Align := alTop;
    PnlTop.Height := 72;
    PnlTop.BevelOuter := bvNone;
    PnlTop.Color := $00F4F6F9;

    LblTitle := TLabel.Create(PnlTop);
    LblTitle.Parent := PnlTop;
    LblTitle.Left := 16;
    LblTitle.Top := 12;
    LblTitle.Font.Style := [fsBold];
    LblTitle.Font.Size := 11;
    LblTitle.Caption := Format('Nova versão disponível: v%s (atual: v%s)', [
      AResult.LatestVersion,
      AResult.CurrentVersion
    ]);

    LblMeta := TLabel.Create(PnlTop);
    LblMeta.Parent := PnlTop;
    LblMeta.Left := 16;
    LblMeta.Top := 40;
    LblMeta.Caption := Format('Plataforma: %s  |  Release: %s', [
      CurrentPlatformName,
      AResult.ReleaseName
    ]);

    PnlBottom := TPanel.Create(Frm);
    PnlBottom.Parent := Frm;
    PnlBottom.Align := alBottom;
    PnlBottom.Height := 48;
    PnlBottom.BevelOuter := bvNone;

    MemNotes := TMemo.Create(Frm);
    MemNotes.Parent := Frm;
    MemNotes.Align := alClient;
    MemNotes.BorderSpacing.Around := 12;
    MemNotes.ReadOnly := True;
    MemNotes.ScrollBars := ssVertical;
    MemNotes.WordWrap := True;
    if Trim(AResult.ReleaseNotes) <> '' then
      MemNotes.Lines.Text := AResult.ReleaseNotes
    else
      MemNotes.Lines.Text := 'Consulte os detalhes completos na página da release no GitHub.';

    BtnDownload := TButton.Create(PnlBottom);
    BtnDownload.Parent := PnlBottom;
    BtnDownload.Left := 12;
    BtnDownload.Top := 10;
    BtnDownload.Height := 28;
    BtnDownload.Width := 220;
    if (AResult.RecommendedAsset.Name <> '') and (AResult.RecommendedAsset.DownloadUrl <> '') then
    begin
      AssetSizeMb := AResult.RecommendedAsset.SizeBytes / (1024.0 * 1024.0);
      BtnDownload.Caption := Format('Baixar (%s - %.1f MB)', [CurrentPlatformAssetToken, AssetSizeMb]);
    end
    else
      BtnDownload.Caption := 'Baixar no GitHub...';
    BtnDownload.OnClick := @Frm.BtnDownloadClick;

    BtnGitHub := TButton.Create(PnlBottom);
    BtnGitHub.Parent := PnlBottom;
    BtnGitHub.Left := 240;
    BtnGitHub.Top := 10;
    BtnGitHub.Height := 28;
    BtnGitHub.Width := 130;
    BtnGitHub.Caption := 'Abrir no GitHub';
    BtnGitHub.OnClick := @Frm.BtnGitHubClick;

    BtnIgnore := TButton.Create(PnlBottom);
    BtnIgnore.Parent := PnlBottom;
    BtnIgnore.Left := 378;
    BtnIgnore.Top := 10;
    BtnIgnore.Height := 28;
    BtnIgnore.Width := 130;
    BtnIgnore.Caption := 'Ignorar esta versão';
    BtnIgnore.OnClick := @Frm.BtnIgnoreClick;

    BtnClose := TButton.Create(PnlBottom);
    BtnClose.Parent := PnlBottom;
    BtnClose.Left := 516;
    BtnClose.Top := 10;
    BtnClose.Height := 28;
    BtnClose.Width := 90;
    BtnClose.Caption := 'Fechar';
    BtnClose.ModalResult := mrClose;
    BtnClose.Default := True;
    BtnClose.Cancel := True;

    Frm.ShowModal;
    AIgnoreThisVersion := Frm.FIgnoreClicked;
    Result := True;
  finally
    Frm.Free;
  end;
end;

type
  TDiagnosticLogForm = class(TForm)
  private
    FMem: TMemo;
    procedure BtnCopyClick(Sender: TObject);
    procedure BtnOpenDirClick(Sender: TObject);
    procedure BtnRefreshClick(Sender: TObject);
  end;

procedure TDiagnosticLogForm.BtnCopyClick(Sender: TObject);
begin
  if FMem <> nil then
    Clipboard.AsText := FMem.Lines.Text;
end;

procedure TDiagnosticLogForm.BtnOpenDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := AppLogger.GetLogDirectory;
  if Dir <> '' then
    OpenDocument(Dir);
end;

procedure TDiagnosticLogForm.BtnRefreshClick(Sender: TObject);
begin
  if FMem <> nil then
  begin
    AppLogger.GetRecentLines(FMem.Lines);
    if FMem.Lines.Count = 0 then
      FMem.Lines.Add('(Nenhum evento registrado nesta sessão.)');
  end;
end;

class procedure TDiagnosticLogDialog.Execute;
var
  Dlg: TDiagnosticLogForm;
  PnlTop, PnlBottom: TPanel;
  LblPath: TLabel;
  BtnRefresh, BtnCopy, BtnOpenDir, BtnClose: TButton;
begin
  Dlg := TDiagnosticLogForm.CreateNew(nil);
  try
    Dlg.Caption := 'Log Diagnóstico - ' + APP_NAME;
    Dlg.Position := poScreenCenter;
    Dlg.Width := 760;
    Dlg.Height := 480;

    PnlTop := TPanel.Create(Dlg);
    PnlTop.Parent := Dlg;
    PnlTop.Align := alTop;
    PnlTop.Height := 34;
    PnlTop.BevelOuter := bvNone;

    LblPath := TLabel.Create(PnlTop);
    LblPath.Parent := PnlTop;
    LblPath.Left := 12;
    LblPath.Top := 9;
    LblPath.Caption := 'Arquivo: ' + AppLogger.GetLogFilePath;

    PnlBottom := TPanel.Create(Dlg);
    PnlBottom.Parent := Dlg;
    PnlBottom.Align := alBottom;
    PnlBottom.Height := 44;
    PnlBottom.BevelOuter := bvNone;

    Dlg.FMem := TMemo.Create(Dlg);
    Dlg.FMem.Parent := Dlg;
    Dlg.FMem.Align := alClient;
    Dlg.FMem.BorderSpacing.Around := 8;
    Dlg.FMem.ReadOnly := True;
    Dlg.FMem.ScrollBars := ssBoth;
    Dlg.FMem.WordWrap := False;
    Dlg.FMem.Font.Name := 'Consolas';
    Dlg.FMem.Font.Size := 9;
    Dlg.BtnRefreshClick(nil);

    BtnCopy := TButton.Create(PnlBottom);
    BtnCopy.Parent := PnlBottom;
    BtnCopy.Left := 12;
    BtnCopy.Top := 8;
    BtnCopy.Width := 110;
    BtnCopy.Height := 28;
    BtnCopy.Caption := 'Copiar Tudo';
    BtnCopy.OnClick := @Dlg.BtnCopyClick;

    BtnOpenDir := TButton.Create(PnlBottom);
    BtnOpenDir.Parent := PnlBottom;
    BtnOpenDir.Left := 130;
    BtnOpenDir.Top := 8;
    BtnOpenDir.Width := 140;
    BtnOpenDir.Height := 28;
    BtnOpenDir.Caption := 'Abrir Pasta do Log';
    BtnOpenDir.OnClick := @Dlg.BtnOpenDirClick;

    BtnRefresh := TButton.Create(PnlBottom);
    BtnRefresh.Parent := PnlBottom;
    BtnRefresh.Left := 278;
    BtnRefresh.Top := 8;
    BtnRefresh.Width := 100;
    BtnRefresh.Height := 28;
    BtnRefresh.Caption := 'Atualizar';
    BtnRefresh.OnClick := @Dlg.BtnRefreshClick;

    BtnClose := TButton.Create(PnlBottom);
    BtnClose.Parent := PnlBottom;
    BtnClose.Left := Dlg.ClientWidth - 102;
    BtnClose.Top := 8;
    BtnClose.Width := 90;
    BtnClose.Height := 28;
    BtnClose.Caption := 'Fechar';
    BtnClose.ModalResult := mrClose;
    BtnClose.Default := True;
    BtnClose.Cancel := True;

    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
