unit Presentation.ReplicationForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Grids, Clipbrd,
  SynEdit, SynHighlighterSQL,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces;

type
  { TReplicationForm }
  TReplicationForm = class(TForm)
  private
    FFactory: IDatabaseProviderFactory;
    FConnections: TConnectionProfileList;

    pnlTop: TPanel;
    lblConn: TLabel;
    cbConnection: TComboBox;
    btnCheckStatus: TButton;

    pgMode: TPageControl;
    tsPostgres: TTabSheet;
    tsFirebird: TTabSheet;
    tsTutorial: TTabSheet;

    { PostgreSQL controls }
    memPgStatus: TMemo;
    grpPgPub: TGroupBox;
    lblPubName: TLabel;
    edtPubName: TEdit;
    chkPubAllTables: TCheckBox;
    lblPubTables: TLabel;
    edtPubTables: TEdit;
    btnCreatePub: TButton;
    btnDropPub: TButton;

    grpPgSub: TGroupBox;
    lblSubName: TLabel;
    edtSubName: TEdit;
    lblSubHost: TLabel;
    edtSubHost: TEdit;
    lblSubPort: TLabel;
    edtSubPort: TEdit;
    lblSubDb: TLabel;
    edtSubDb: TEdit;
    lblSubUser: TLabel;
    edtSubUser: TEdit;
    lblSubPass: TLabel;
    edtSubPass: TEdit;
    lblSubPub: TLabel;
    edtSubPub: TEdit;
    btnCreateSub: TButton;
    btnRefreshSub: TButton;
    btnDropSub: TButton;

    { Firebird 5 controls }
    memFbStatus: TMemo;
    grpFbDdl: TGroupBox;
    btnFbEnablePub: TButton;
    btnFbDisablePub: TButton;
    btnFbIncludeAll: TButton;
    lblFbTable: TLabel;
    edtFbTable: TEdit;
    btnFbIncludeTable: TButton;
    btnFbExcludeTable: TButton;

    grpFbConf: TGroupBox;
    lblFbPrimaryDb: TLabel;
    edtFbPrimaryDb: TEdit;
    lblFbJournalDir: TLabel;
    edtFbJournalDir: TEdit;
    lblFbArchiveDir: TLabel;
    edtFbArchiveDir: TEdit;
    lblFbSyncReplica: TLabel;
    edtFbSyncReplica: TEdit;
    lblFbReplicaSource: TLabel;
    edtFbReplicaSource: TEdit;
    lblFbReplicaDb: TLabel;
    edtFbReplicaDb: TEdit;
    btnFbGenConf: TButton;
    btnFbCopyConf: TButton;
    memFbConf: TMemo;

    { Tutorial controls }
    pnlTutorialTop: TPanel;
    btnRefreshTutorial: TButton;
    btnCopyTutorial: TButton;
    memTutorial: TMemo;

    procedure BuildUI;
    function SelectedProfile: TConnectionProfile;
    function ExecuteSqlOnSelected(const ASQL: string; out AOutput: string): Boolean;
    procedure cbConnectionChange(Sender: TObject);
    procedure btnCheckStatusClick(Sender: TObject);
    procedure chkPubAllTablesChange(Sender: TObject);
    procedure btnCreatePubClick(Sender: TObject);
    procedure btnDropPubClick(Sender: TObject);
    procedure btnCreateSubClick(Sender: TObject);
    procedure btnRefreshSubClick(Sender: TObject);
    procedure btnDropSubClick(Sender: TObject);
    procedure btnFbEnablePubClick(Sender: TObject);
    procedure btnFbDisablePubClick(Sender: TObject);
    procedure btnFbIncludeAllClick(Sender: TObject);
    procedure btnFbIncludeTableClick(Sender: TObject);
    procedure btnFbExcludeTableClick(Sender: TObject);
    procedure btnFbGenConfClick(Sender: TObject);
    procedure btnFbCopyConfClick(Sender: TObject);
    procedure RefreshTutorialText;
    procedure btnRefreshTutorialClick(Sender: TObject);
    procedure btnCopyTutorialClick(Sender: TObject);
  public
    class procedure Execute(
      const AFactory: IDatabaseProviderFactory;
      const AConnections: TConnectionProfileList;
      const AInitialProfileId: string = ''
    );
  end;

implementation

class procedure TReplicationForm.Execute(
  const AFactory: IDatabaseProviderFactory;
  const AConnections: TConnectionProfileList;
  const AInitialProfileId: string
);
var
  Frm: TReplicationForm;
  I, SelIdx, Idx: Integer;
  P: TConnectionProfile;
begin
  Frm := TReplicationForm.CreateNew(nil);
  try
    Frm.FFactory := AFactory;
    Frm.FConnections := AConnections;
    Frm.BuildUI;

    SelIdx := -1;
    if AConnections <> nil then
    begin
      for I := 0 to AConnections.Count - 1 do
      begin
        P := AConnections[I];
        if P.DatabaseType in [dtPostgreSQL, dtFirebird] then
        begin
          Idx := Frm.cbConnection.Items.AddObject(
            Format('%s [%s]', [P.Name, DatabaseTypeToStr(P.DatabaseType)]),
            P
          );
          if (AInitialProfileId <> '') and SameText(P.Id, AInitialProfileId) then
            SelIdx := Idx;
        end;
      end;
    end;
    if (SelIdx < 0) and (Frm.cbConnection.Items.Count > 0) then
      SelIdx := 0;
    Frm.cbConnection.ItemIndex := SelIdx;
    Frm.cbConnectionChange(nil);
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

procedure TReplicationForm.BuildUI;
begin
  Caption := 'Configurador de Replicação (PostgreSQL & Firebird 5)';
  Position := poScreenCenter;
  Width := 920;
  Height := 680;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 540;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 44;
  pnlTop.BevelOuter := bvNone;

  lblConn := TLabel.Create(Self);
  lblConn.Parent := pnlTop;
  lblConn.Left := 12;
  lblConn.Top := 14;
  lblConn.Caption := 'Conexão Alvo:';

  cbConnection := TComboBox.Create(Self);
  cbConnection.Parent := pnlTop;
  cbConnection.Left := 102;
  cbConnection.Top := 10;
  cbConnection.Width := 340;
  cbConnection.Style := csDropDownList;
  cbConnection.OnChange := @cbConnectionChange;

  btnCheckStatus := TButton.Create(Self);
  btnCheckStatus.Parent := pnlTop;
  btnCheckStatus.Left := 454;
  btnCheckStatus.Top := 9;
  btnCheckStatus.Width := 190;
  btnCheckStatus.Height := 25;
  btnCheckStatus.Caption := 'Verificar Status de Replicação';
  btnCheckStatus.OnClick := @btnCheckStatusClick;

  pgMode := TPageControl.Create(Self);
  pgMode.Parent := Self;
  pgMode.Align := alClient;
  pgMode.BorderSpacing.Around := 8;

  tsPostgres := TTabSheet.Create(pgMode);
  tsPostgres.PageControl := pgMode;
  tsPostgres.Caption := 'PostgreSQL (Replicação Lógica)';

  memPgStatus := TMemo.Create(Self);
  memPgStatus.Parent := tsPostgres;
  memPgStatus.Align := alTop;
  memPgStatus.Height := 125;
  memPgStatus.ReadOnly := True;
  memPgStatus.ScrollBars := ssVertical;

  grpPgPub := TGroupBox.Create(Self);
  grpPgPub.Parent := tsPostgres;
  grpPgPub.Align := alTop;
  grpPgPub.Height := 118;
  grpPgPub.Caption := 'Publicador (Origem - CREATE PUBLICATION)';

  lblPubName := TLabel.Create(Self);
  lblPubName.Parent := grpPgPub;
  lblPubName.Left := 12;
  lblPubName.Top := 14;
  lblPubName.Caption := 'Nome da Publicação:';

  edtPubName := TEdit.Create(Self);
  edtPubName.Parent := grpPgPub;
  edtPubName.Left := 140;
  edtPubName.Top := 10;
  edtPubName.Width := 190;
  edtPubName.Text := 'pub_principal';

  chkPubAllTables := TCheckBox.Create(Self);
  chkPubAllTables.Parent := grpPgPub;
  chkPubAllTables.Left := 348;
  chkPubAllTables.Top := 12;
  chkPubAllTables.Width := 230;
  chkPubAllTables.Caption := 'Todas as tabelas (FOR ALL TABLES)';
  chkPubAllTables.Checked := True;
  chkPubAllTables.OnChange := @chkPubAllTablesChange;

  lblPubTables := TLabel.Create(Self);
  lblPubTables.Parent := grpPgPub;
  lblPubTables.Left := 12;
  lblPubTables.Top := 44;
  lblPubTables.Caption := 'Tabelas (sep. vírgula):';

  edtPubTables := TEdit.Create(Self);
  edtPubTables.Parent := grpPgPub;
  edtPubTables.Left := 140;
  edtPubTables.Top := 40;
  edtPubTables.Width := 430;
  edtPubTables.Enabled := False;
  edtPubTables.TextHint := 'Ex.: clientes, pedidos';

  btnCreatePub := TButton.Create(Self);
  btnCreatePub.Parent := grpPgPub;
  btnCreatePub.Left := 590;
  btnCreatePub.Top := 9;
  btnCreatePub.Width := 135;
  btnCreatePub.Height := 26;
  btnCreatePub.Caption := 'Criar Publicação';
  btnCreatePub.OnClick := @btnCreatePubClick;

  btnDropPub := TButton.Create(Self);
  btnDropPub.Parent := grpPgPub;
  btnDropPub.Left := 734;
  btnDropPub.Top := 9;
  btnDropPub.Width := 135;
  btnDropPub.Height := 26;
  btnDropPub.Caption := 'Remover Publicação';
  btnDropPub.OnClick := @btnDropPubClick;

  grpPgSub := TGroupBox.Create(Self);
  grpPgSub.Parent := tsPostgres;
  grpPgSub.Align := alClient;
  grpPgSub.Caption := 'Assinante (Destino - CREATE SUBSCRIPTION)';

  lblSubName := TLabel.Create(Self);
  lblSubName.Parent := grpPgSub;
  lblSubName.Left := 12;
  lblSubName.Top := 18;
  lblSubName.Caption := 'Nome Assinatura:';

  edtSubName := TEdit.Create(Self);
  edtSubName.Parent := grpPgSub;
  edtSubName.Left := 140;
  edtSubName.Top := 14;
  edtSubName.Width := 190;
  edtSubName.Text := 'sub_principal';

  lblSubPub := TLabel.Create(Self);
  lblSubPub.Parent := grpPgSub;
  lblSubPub.Left := 348;
  lblSubPub.Top := 18;
  lblSubPub.Caption := 'Publicação Remota:';

  edtSubPub := TEdit.Create(Self);
  edtSubPub.Parent := grpPgSub;
  edtSubPub.Left := 470;
  edtSubPub.Top := 14;
  edtSubPub.Width := 180;
  edtSubPub.Text := 'pub_principal';

  lblSubHost := TLabel.Create(Self);
  lblSubHost.Parent := grpPgSub;
  lblSubHost.Left := 12;
  lblSubHost.Top := 50;
  lblSubHost.Caption := 'Host Origem:';

  edtSubHost := TEdit.Create(Self);
  edtSubHost.Parent := grpPgSub;
  edtSubHost.Left := 140;
  edtSubHost.Top := 46;
  edtSubHost.Width := 190;
  edtSubHost.Text := 'localhost';

  lblSubPort := TLabel.Create(Self);
  lblSubPort.Parent := grpPgSub;
  lblSubPort.Left := 348;
  lblSubPort.Top := 50;
  lblSubPort.Caption := 'Porta:';

  edtSubPort := TEdit.Create(Self);
  edtSubPort.Parent := grpPgSub;
  edtSubPort.Left := 470;
  edtSubPort.Top := 46;
  edtSubPort.Width := 80;
  edtSubPort.Text := '5432';

  lblSubDb := TLabel.Create(Self);
  lblSubDb.Parent := grpPgSub;
  lblSubDb.Left := 12;
  lblSubDb.Top := 82;
  lblSubDb.Caption := 'Banco Origem:';

  edtSubDb := TEdit.Create(Self);
  edtSubDb.Parent := grpPgSub;
  edtSubDb.Left := 140;
  edtSubDb.Top := 78;
  edtSubDb.Width := 190;

  lblSubUser := TLabel.Create(Self);
  lblSubUser.Parent := grpPgSub;
  lblSubUser.Left := 348;
  lblSubUser.Top := 82;
  lblSubUser.Caption := 'Usuário Origem:';

  edtSubUser := TEdit.Create(Self);
  edtSubUser.Parent := grpPgSub;
  edtSubUser.Left := 470;
  edtSubUser.Top := 78;
  edtSubUser.Width := 180;
  edtSubUser.Text := 'postgres';

  lblSubPass := TLabel.Create(Self);
  lblSubPass.Parent := grpPgSub;
  lblSubPass.Left := 12;
  lblSubPass.Top := 114;
  lblSubPass.Caption := 'Senha Origem:';

  edtSubPass := TEdit.Create(Self);
  edtSubPass.Parent := grpPgSub;
  edtSubPass.Left := 140;
  edtSubPass.Top := 110;
  edtSubPass.Width := 190;
  edtSubPass.PasswordChar := '*';

  btnCreateSub := TButton.Create(Self);
  btnCreateSub.Parent := grpPgSub;
  btnCreateSub.Left := 140;
  btnCreateSub.Top := 148;
  btnCreateSub.Width := 145;
  btnCreateSub.Height := 28;
  btnCreateSub.Caption := 'Criar Assinatura';
  btnCreateSub.OnClick := @btnCreateSubClick;

  btnRefreshSub := TButton.Create(Self);
  btnRefreshSub.Parent := grpPgSub;
  btnRefreshSub.Left := 295;
  btnRefreshSub.Top := 148;
  btnRefreshSub.Width := 165;
  btnRefreshSub.Height := 28;
  btnRefreshSub.Caption := 'Atualizar (REFRESH)';
  btnRefreshSub.OnClick := @btnRefreshSubClick;

  btnDropSub := TButton.Create(Self);
  btnDropSub.Parent := grpPgSub;
  btnDropSub.Left := 470;
  btnDropSub.Top := 148;
  btnDropSub.Width := 155;
  btnDropSub.Height := 28;
  btnDropSub.Caption := 'Remover Assinatura';
  btnDropSub.OnClick := @btnDropSubClick;

  { Firebird 5 }
  tsFirebird := TTabSheet.Create(pgMode);
  tsFirebird.PageControl := pgMode;
  tsFirebird.Caption := 'Firebird 5 (Publicação & replication.conf)';

  memFbStatus := TMemo.Create(Self);
  memFbStatus.Parent := tsFirebird;
  memFbStatus.Align := alTop;
  memFbStatus.Height := 120;
  memFbStatus.ReadOnly := True;
  memFbStatus.ScrollBars := ssVertical;

  grpFbDdl := TGroupBox.Create(Self);
  grpFbDdl.Parent := tsFirebird;
  grpFbDdl.Align := alTop;
  grpFbDdl.Height := 104;
  grpFbDdl.Caption := 'Controle DDL de Publicação no Banco Primário';

  btnFbEnablePub := TButton.Create(Self);
  btnFbEnablePub.Parent := grpFbDdl;
  btnFbEnablePub.Left := 12;
  btnFbEnablePub.Top := 12;
  btnFbEnablePub.Width := 180;
  btnFbEnablePub.Height := 26;
  btnFbEnablePub.Caption := 'Habilitar Publicação';
  btnFbEnablePub.OnClick := @btnFbEnablePubClick;

  btnFbDisablePub := TButton.Create(Self);
  btnFbDisablePub.Parent := grpFbDdl;
  btnFbDisablePub.Left := 200;
  btnFbDisablePub.Top := 12;
  btnFbDisablePub.Width := 180;
  btnFbDisablePub.Height := 26;
  btnFbDisablePub.Caption := 'Desabilitar Publicação';
  btnFbDisablePub.OnClick := @btnFbDisablePubClick;

  btnFbIncludeAll := TButton.Create(Self);
  btnFbIncludeAll.Parent := grpFbDdl;
  btnFbIncludeAll.Left := 388;
  btnFbIncludeAll.Top := 12;
  btnFbIncludeAll.Width := 215;
  btnFbIncludeAll.Height := 26;
  btnFbIncludeAll.Caption := 'Incluir Todas as Tabelas';
  btnFbIncludeAll.OnClick := @btnFbIncludeAllClick;

  lblFbTable := TLabel.Create(Self);
  lblFbTable.Parent := grpFbDdl;
  lblFbTable.Left := 12;
  lblFbTable.Top := 50;
  lblFbTable.Caption := 'Tabela específica:';

  edtFbTable := TEdit.Create(Self);
  edtFbTable.Parent := grpFbDdl;
  edtFbTable.Left := 130;
  edtFbTable.Top := 46;
  edtFbTable.Width := 230;
  edtFbTable.TextHint := 'Ex.: CLIENTES';

  btnFbIncludeTable := TButton.Create(Self);
  btnFbIncludeTable.Parent := grpFbDdl;
  btnFbIncludeTable.Left := 370;
  btnFbIncludeTable.Top := 45;
  btnFbIncludeTable.Width := 130;
  btnFbIncludeTable.Height := 26;
  btnFbIncludeTable.Caption := 'Incluir Tabela';
  btnFbIncludeTable.OnClick := @btnFbIncludeTableClick;

  btnFbExcludeTable := TButton.Create(Self);
  btnFbExcludeTable.Parent := grpFbDdl;
  btnFbExcludeTable.Left := 508;
  btnFbExcludeTable.Top := 45;
  btnFbExcludeTable.Width := 130;
  btnFbExcludeTable.Height := 26;
  btnFbExcludeTable.Caption := 'Excluir Tabela';
  btnFbExcludeTable.OnClick := @btnFbExcludeTableClick;

  grpFbConf := TGroupBox.Create(Self);
  grpFbConf.Parent := tsFirebird;
  grpFbConf.Align := alClient;
  grpFbConf.Caption := 'Gerador de replication.conf (Firebird 5)';

  lblFbPrimaryDb := TLabel.Create(Self);
  lblFbPrimaryDb.Parent := grpFbConf;
  lblFbPrimaryDb.Left := 12;
  lblFbPrimaryDb.Top := 16;
  lblFbPrimaryDb.Caption := 'Banco Primário:';

  edtFbPrimaryDb := TEdit.Create(Self);
  edtFbPrimaryDb.Parent := grpFbConf;
  edtFbPrimaryDb.Left := 130;
  edtFbPrimaryDb.Top := 12;
  edtFbPrimaryDb.Width := 290;

  lblFbJournalDir := TLabel.Create(Self);
  lblFbJournalDir.Parent := grpFbConf;
  lblFbJournalDir.Left := 436;
  lblFbJournalDir.Top := 16;
  lblFbJournalDir.Caption := 'journal_directory:';

  edtFbJournalDir := TEdit.Create(Self);
  edtFbJournalDir.Parent := grpFbConf;
  edtFbJournalDir.Left := 555;
  edtFbJournalDir.Top := 12;
  edtFbJournalDir.Width := 290;
  edtFbJournalDir.Text := 'C:\FirebirdRepl\journal';

  lblFbArchiveDir := TLabel.Create(Self);
  lblFbArchiveDir.Parent := grpFbConf;
  lblFbArchiveDir.Left := 12;
  lblFbArchiveDir.Top := 46;
  lblFbArchiveDir.Caption := 'archive_directory:';

  edtFbArchiveDir := TEdit.Create(Self);
  edtFbArchiveDir.Parent := grpFbConf;
  edtFbArchiveDir.Left := 130;
  edtFbArchiveDir.Top := 42;
  edtFbArchiveDir.Width := 290;
  edtFbArchiveDir.Text := 'C:\FirebirdRepl\archive';

  lblFbSyncReplica := TLabel.Create(Self);
  lblFbSyncReplica.Parent := grpFbConf;
  lblFbSyncReplica.Left := 436;
  lblFbSyncReplica.Top := 46;
  lblFbSyncReplica.Caption := 'sync_replica (opc.):';

  edtFbSyncReplica := TEdit.Create(Self);
  edtFbSyncReplica.Parent := grpFbConf;
  edtFbSyncReplica.Left := 555;
  edtFbSyncReplica.Top := 42;
  edtFbSyncReplica.Width := 290;
  edtFbSyncReplica.TextHint := 'Ex.: replica_host:C:\Dados\banco_repl.fdb';

  lblFbReplicaSource := TLabel.Create(Self);
  lblFbReplicaSource.Parent := grpFbConf;
  lblFbReplicaSource.Left := 12;
  lblFbReplicaSource.Top := 76;
  lblFbReplicaSource.Caption := 'source_directory:';

  edtFbReplicaSource := TEdit.Create(Self);
  edtFbReplicaSource.Parent := grpFbConf;
  edtFbReplicaSource.Left := 130;
  edtFbReplicaSource.Top := 72;
  edtFbReplicaSource.Width := 290;
  edtFbReplicaSource.Text := 'C:\FirebirdRepl\incoming';

  lblFbReplicaDb := TLabel.Create(Self);
  lblFbReplicaDb.Parent := grpFbConf;
  lblFbReplicaDb.Left := 436;
  lblFbReplicaDb.Top := 76;
  lblFbReplicaDb.Caption := 'Banco Réplica:';

  edtFbReplicaDb := TEdit.Create(Self);
  edtFbReplicaDb.Parent := grpFbConf;
  edtFbReplicaDb.Left := 555;
  edtFbReplicaDb.Top := 72;
  edtFbReplicaDb.Width := 290;
  edtFbReplicaDb.Text := 'C:\Dados\banco_replica.fdb';

  btnFbGenConf := TButton.Create(Self);
  btnFbGenConf.Parent := grpFbConf;
  btnFbGenConf.Left := 130;
  btnFbGenConf.Top := 102;
  btnFbGenConf.Width := 180;
  btnFbGenConf.Height := 26;
  btnFbGenConf.Caption := 'Gerar replication.conf';
  btnFbGenConf.OnClick := @btnFbGenConfClick;

  btnFbCopyConf := TButton.Create(Self);
  btnFbCopyConf.Parent := grpFbConf;
  btnFbCopyConf.Left := 318;
  btnFbCopyConf.Top := 102;
  btnFbCopyConf.Width := 150;
  btnFbCopyConf.Height := 26;
  btnFbCopyConf.Caption := 'Copiar Bloco';
  btnFbCopyConf.OnClick := @btnFbCopyConfClick;

  memFbConf := TMemo.Create(Self);
  memFbConf.Parent := grpFbConf;
  memFbConf.Left := 12;
  memFbConf.Top := 136;
  memFbConf.Width := grpFbConf.ClientWidth - 24;
  memFbConf.Height := grpFbConf.ClientHeight - 146;
  memFbConf.Anchors := [akTop, akLeft, akRight, akBottom];
  memFbConf.ScrollBars := ssBoth;

  { Tutorial Passo a Passo }
  tsTutorial := TTabSheet.Create(pgMode);
  tsTutorial.PageControl := pgMode;
  tsTutorial.Caption := 'Tutorial Passo a Passo';

  pnlTutorialTop := TPanel.Create(Self);
  pnlTutorialTop.Parent := tsTutorial;
  pnlTutorialTop.Align := alTop;
  pnlTutorialTop.Height := 38;
  pnlTutorialTop.BevelOuter := bvNone;

  btnRefreshTutorial := TButton.Create(Self);
  btnRefreshTutorial.Parent := pnlTutorialTop;
  btnRefreshTutorial.Left := 10;
  btnRefreshTutorial.Top := 6;
  btnRefreshTutorial.Width := 220;
  btnRefreshTutorial.Height := 26;
  btnRefreshTutorial.Caption := 'Atualizar Tutorial com Meus Caminhos';
  btnRefreshTutorial.OnClick := @btnRefreshTutorialClick;

  btnCopyTutorial := TButton.Create(Self);
  btnCopyTutorial.Parent := pnlTutorialTop;
  btnCopyTutorial.Left := 238;
  btnCopyTutorial.Top := 6;
  btnCopyTutorial.Width := 130;
  btnCopyTutorial.Height := 26;
  btnCopyTutorial.Caption := 'Copiar Tutorial';
  btnCopyTutorial.OnClick := @btnCopyTutorialClick;

  memTutorial := TMemo.Create(Self);
  memTutorial.Parent := tsTutorial;
  memTutorial.Align := alClient;
  memTutorial.ReadOnly := True;
  memTutorial.ScrollBars := ssBoth;
  RefreshTutorialText;
end;

function TReplicationForm.SelectedProfile: TConnectionProfile;
begin
  Result := nil;
  if (cbConnection.ItemIndex >= 0) and (cbConnection.ItemIndex < cbConnection.Items.Count) then
    Result := TConnectionProfile(cbConnection.Items.Objects[cbConnection.ItemIndex]);
end;

function TReplicationForm.ExecuteSqlOnSelected(const ASQL: string; out AOutput: string): Boolean;
var
  P: TConnectionProfile;
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  I, C: Integer;
  Line: string;
begin
  Result := False;
  AOutput := '';
  P := SelectedProfile;
  if (P = nil) or (FFactory = nil) then
  begin
    AOutput := 'Selecione uma conexão válida.';
    Exit;
  end;

  Provider := FFactory.GetProvider(P.DatabaseType);
  Session := Provider.CreateSession(P);
  try
    Session.Connect;
    Res := Session.ExecuteSQL(ASQL, True, 0);
    try
      Result := Res.Success;
      if not Res.Success then
      begin
        AOutput := Res.MessageText;
        Exit;
      end;
      if Res.HasResultSet then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          Line := '';
          for C := 0 to Res.ColumnCount - 1 do
          begin
            if C > 0 then
              Line := Line + ' | ';
            Line := Line + Res.GetColumn(C).Name + '=' + Res.GetRow(I)[C].AsText;
          end;
          if AOutput <> '' then
            AOutput := AOutput + LineEnding;
          AOutput := AOutput + Line;
        end;
        if AOutput = '' then
          AOutput := '(0 registros)';
      end
      else
        AOutput := Res.MessageText;
    finally
      Res.Free;
    end;
  except
    on E: Exception do
    begin
      Result := False;
      AOutput := E.Message;
    end;
  end;
end;

procedure TReplicationForm.cbConnectionChange(Sender: TObject);
var
  P: TConnectionProfile;
begin
  P := SelectedProfile;
  if P = nil then
    Exit;
  if P.DatabaseType = dtPostgreSQL then
  begin
    pgMode.ActivePage := tsPostgres;
    if Trim(edtSubDb.Text) = '' then
      edtSubDb.Text := P.Database;
  end
  else
  begin
    pgMode.ActivePage := tsFirebird;
    edtFbPrimaryDb.Text := P.Database;
    btnFbGenConfClick(nil);
  end;
end;

procedure TReplicationForm.btnCheckStatusClick(Sender: TObject);
var
  P: TConnectionProfile;
  Out1, Out2, Out3: string;
begin
  P := SelectedProfile;
  if P = nil then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    if P.DatabaseType = dtPostgreSQL then
    begin
      pgMode.ActivePage := tsPostgres;
      memPgStatus.Clear;
      ExecuteSqlOnSelected(
        'SELECT name, setting FROM pg_settings WHERE name IN (''wal_level'', ''max_replication_slots'', ''max_wal_senders'') ORDER BY name',
        Out1
      );
      ExecuteSqlOnSelected('SELECT pubname, puballtables FROM pg_publication ORDER BY pubname', Out2);
      ExecuteSqlOnSelected('SELECT subname, subenabled, subpublications FROM pg_subscription ORDER BY subname', Out3);
      memPgStatus.Lines.Add('=== Parâmetros PostgreSQL ===');
      memPgStatus.Lines.Add(Out1);
      memPgStatus.Lines.Add('=== Publicações (pg_publication) ===');
      memPgStatus.Lines.Add(Out2);
      memPgStatus.Lines.Add('=== Assinaturas (pg_subscription) ===');
      memPgStatus.Lines.Add(Out3);
    end
    else
    begin
      pgMode.ActivePage := tsFirebird;
      memFbStatus.Clear;
      ExecuteSqlOnSelected(
        'SELECT TRIM(RDB$PUBLICATION_NAME) AS PUBLICACAO, RDB$ACTIVE_FLAG AS ATIVA, RDB$AUTO_ENABLE_FLAG AS AUTO_INCLUIR FROM RDB$PUBLICATIONS',
        Out1
      );
      ExecuteSqlOnSelected(
        'SELECT TRIM(RDB$TABLE_NAME) AS TABELA FROM RDB$PUBLICATION_TABLES ORDER BY 1',
        Out2
      );
      memFbStatus.Lines.Add('=== RDB$PUBLICATIONS (Firebird 4/5) ===');
      memFbStatus.Lines.Add(Out1);
      memFbStatus.Lines.Add('=== Tabelas Publicadas (RDB$PUBLICATION_TABLES) ===');
      memFbStatus.Lines.Add(Out2);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TReplicationForm.chkPubAllTablesChange(Sender: TObject);
begin
  edtPubTables.Enabled := not chkPubAllTables.Checked;
end;

procedure TReplicationForm.btnCreatePubClick(Sender: TObject);
var
  SQL, OutMsg: string;
begin
  if Trim(edtPubName.Text) = '' then
    Exit;
  if chkPubAllTables.Checked then
    SQL := Format('CREATE PUBLICATION "%s" FOR ALL TABLES', [Trim(edtPubName.Text)])
  else
    SQL := Format('CREATE PUBLICATION "%s" FOR TABLE %s', [Trim(edtPubName.Text), Trim(edtPubTables.Text)]);

  if ExecuteSqlOnSelected(SQL, OutMsg) then
  begin
    MessageDlg('Replicação PostgreSQL', 'Publicação criada com sucesso.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnDropPubClick(Sender: TObject);
var
  OutMsg: string;
begin
  if Trim(edtPubName.Text) = '' then
    Exit;
  if ExecuteSqlOnSelected(Format('DROP PUBLICATION IF EXISTS "%s"', [Trim(edtPubName.Text)]), OutMsg) then
  begin
    MessageDlg('Replicação PostgreSQL', 'Publicação removida.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnCreateSubClick(Sender: TObject);
var
  SQL, ConnStr, OutMsg: string;
begin
  ConnStr := Format('host=%s port=%s dbname=%s user=%s password=%s', [
    Trim(edtSubHost.Text), Trim(edtSubPort.Text), Trim(edtSubDb.Text),
    Trim(edtSubUser.Text), edtSubPass.Text
  ]);
  SQL := Format('CREATE SUBSCRIPTION "%s" CONNECTION ''%s'' PUBLICATION "%s"', [
    Trim(edtSubName.Text),
    StringReplace(ConnStr, '''', '''''', [rfReplaceAll]),
    Trim(edtSubPub.Text)
  ]);
  if ExecuteSqlOnSelected(SQL, OutMsg) then
  begin
    MessageDlg('Replicação PostgreSQL', 'Assinatura criada com sucesso.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnRefreshSubClick(Sender: TObject);
var
  OutMsg: string;
begin
  if ExecuteSqlOnSelected(Format('ALTER SUBSCRIPTION "%s" REFRESH PUBLICATION', [Trim(edtSubName.Text)]), OutMsg) then
    MessageDlg('Replicação PostgreSQL', 'Publicação sincronizada na assinatura.', mtInformation, [mbOK], 0)
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnDropSubClick(Sender: TObject);
var
  OutMsg: string;
begin
  if ExecuteSqlOnSelected(Format('DROP SUBSCRIPTION IF EXISTS "%s"', [Trim(edtSubName.Text)]), OutMsg) then
  begin
    MessageDlg('Replicação PostgreSQL', 'Assinatura removida.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnFbEnablePubClick(Sender: TObject);
var
  OutMsg: string;
begin
  if ExecuteSqlOnSelected('ALTER DATABASE ENABLE PUBLICATION', OutMsg) then
  begin
    MessageDlg('Replicação Firebird 5', 'Publicação habilitada no banco.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnFbDisablePubClick(Sender: TObject);
var
  OutMsg: string;
begin
  if ExecuteSqlOnSelected('ALTER DATABASE DISABLE PUBLICATION', OutMsg) then
  begin
    MessageDlg('Replicação Firebird 5', 'Publicação desabilitada no banco.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnFbIncludeAllClick(Sender: TObject);
var
  OutMsg: string;
begin
  if ExecuteSqlOnSelected('ALTER DATABASE INCLUDE ALL TO PUBLICATION', OutMsg) then
  begin
    MessageDlg('Replicação Firebird 5', 'Todas as tabelas incluídas na publicação.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnFbIncludeTableClick(Sender: TObject);
var
  OutMsg: string;
begin
  if Trim(edtFbTable.Text) = '' then
    Exit;
  if ExecuteSqlOnSelected('ALTER DATABASE INCLUDE TABLE ' + Trim(edtFbTable.Text) + ' TO PUBLICATION', OutMsg) then
  begin
    MessageDlg('Replicação Firebird 5', 'Tabela incluída na publicação.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnFbExcludeTableClick(Sender: TObject);
var
  OutMsg: string;
begin
  if Trim(edtFbTable.Text) = '' then
    Exit;
  if ExecuteSqlOnSelected('ALTER DATABASE EXCLUDE TABLE ' + Trim(edtFbTable.Text) + ' FROM PUBLICATION', OutMsg) then
  begin
    MessageDlg('Replicação Firebird 5', 'Tabela removida da publicação.', mtInformation, [mbOK], 0);
    btnCheckStatusClick(nil);
  end
  else
    MessageDlg('Erro', OutMsg, mtError, [mbOK], 0);
end;

procedure TReplicationForm.btnFbGenConfClick(Sender: TObject);
begin
  memFbConf.Lines.Clear;
  memFbConf.Lines.Add('# === Configuração no Servidor PRIMÁRIO (replication.conf) ===');
  memFbConf.Lines.Add('database = ' + Trim(edtFbPrimaryDb.Text));
  memFbConf.Lines.Add('{');
  memFbConf.Lines.Add('  journal_directory = ' + Trim(edtFbJournalDir.Text));
  memFbConf.Lines.Add('  journal_archive_directory = ' + Trim(edtFbArchiveDir.Text));
  memFbConf.Lines.Add('  journal_archive_timeout = 10');
  if Trim(edtFbSyncReplica.Text) <> '' then
    memFbConf.Lines.Add('  sync_replica = ' + Trim(edtFbSyncReplica.Text));
  memFbConf.Lines.Add('  verbose_logging = true');
  memFbConf.Lines.Add('}');
  memFbConf.Lines.Add('');
  memFbConf.Lines.Add('# === Configuração no Servidor RÉPLICA (replication.conf) ===');
  memFbConf.Lines.Add('database = ' + Trim(edtFbReplicaDb.Text));
  memFbConf.Lines.Add('{');
  memFbConf.Lines.Add('  journal_source_directory = ' + Trim(edtFbReplicaSource.Text));
  memFbConf.Lines.Add('  verbose_logging = true');
  memFbConf.Lines.Add('}');
  RefreshTutorialText;
end;

procedure TReplicationForm.btnFbCopyConfClick(Sender: TObject);
begin
  Clipboard.AsText := memFbConf.Lines.Text;
end;

procedure TReplicationForm.RefreshTutorialText;
var
  PrimDb, ReplDb, JDir, ADir, SDir, SyncR: string;
begin
  if memTutorial = nil then
    Exit;
  PrimDb := Trim(edtFbPrimaryDb.Text);
  if PrimDb = '' then
    PrimDb := 'C:\Dados\banco_primario.fdb';
  ReplDb := Trim(edtFbReplicaDb.Text);
  if ReplDb = '' then
    ReplDb := 'C:\Dados\banco_replica.fdb';
  JDir := Trim(edtFbJournalDir.Text);
  ADir := Trim(edtFbArchiveDir.Text);
  SDir := Trim(edtFbReplicaSource.Text);
  SyncR := Trim(edtFbSyncReplica.Text);

  memTutorial.Lines.BeginUpdate;
  try
    memTutorial.Lines.Clear;
    memTutorial.Lines.Add('======================================================================');
    memTutorial.Lines.Add('  TUTORIAL COMPLETO DE REPLICAÇÃO — FIREBIRD 5');
    memTutorial.Lines.Add('======================================================================');
    memTutorial.Lines.Add('');
    memTutorial.Lines.Add('PASSO 1 — Preparar o banco PRIMÁRIO (aqui no MultiDbSqlEditor)');
    memTutorial.Lines.Add('  1. Selecione a conexão do banco primário no topo e vá na aba Firebird 5.');
    memTutorial.Lines.Add('  2. Clique em "Habilitar Publicação" (ALTER DATABASE ENABLE PUBLICATION).');
    memTutorial.Lines.Add('  3. Clique em "Incluir Todas as Tabelas" (ALTER DATABASE INCLUDE ALL TO PUBLICATION).');
    memTutorial.Lines.Add('  4. Crie as pastas no servidor primário com permissão de escrita ao Firebird:');
    memTutorial.Lines.Add('     - journal_directory (onde o journal ativo é gravado): ' + JDir);
    memTutorial.Lines.Add('     - journal_archive_directory (segmentos fechados p/ envio): ' + ADir);
    memTutorial.Lines.Add('  5. Cole o bloco do PRIMÁRIO no arquivo replication.conf do servidor primário');
    memTutorial.Lines.Add('     (ex.: C:\Program Files\Firebird\Firebird_5_0\replication.conf).');
    if SyncR <> '' then
      memTutorial.Lines.Add('     Modo Síncrono configurado: sync_replica = ' + SyncR)
    else
      memTutorial.Lines.Add('     Modo Assíncrono: copie periodicamente os arquivos de "' + ADir + '" para "' + SDir + '" na réplica.');
    memTutorial.Lines.Add('');
    memTutorial.Lines.Add('PASSO 2 — Copiar o banco inicial para a RÉPLICA (obrigatório no Firebird 5)');
    memTutorial.Lines.Add('  Com o banco parado OU online usando nbackup (sem derrubar usuários):');
    memTutorial.Lines.Add('    nbackup -U SYSDBA -P masterkey -L "' + PrimDb + '"');
    memTutorial.Lines.Add('    copy "' + PrimDb + '" "' + ReplDb + '"');
    memTutorial.Lines.Add('    nbackup -U SYSDBA -P masterkey -N "' + PrimDb + '"');
    memTutorial.Lines.Add('');
    memTutorial.Lines.Add('PASSO 3 — Marcar o banco copiado como RÉPLICA e configurar a Réplica');
    memTutorial.Lines.Add('  1. No servidor RÉPLICA, execute:');
    memTutorial.Lines.Add('     gfix -user SYSDBA -password masterkey -replica read_only "' + ReplDb + '"');
    memTutorial.Lines.Add('  2. Crie a pasta de entrada na réplica: ' + SDir);
    memTutorial.Lines.Add('  3. Cole o bloco da RÉPLICA no arquivo replication.conf do servidor réplica.');
    memTutorial.Lines.Add('  4. Faça uma transação no primário e acompanhe o arquivo replication.log na pasta do Firebird 5.');
    memTutorial.Lines.Add('');
    memTutorial.Lines.Add('======================================================================');
    memTutorial.Lines.Add('  TUTORIAL COMPLETO DE REPLICAÇÃO LÓGICA — POSTGRESQL');
    memTutorial.Lines.Add('======================================================================');
    memTutorial.Lines.Add('  1. No postgresql.conf da ORIGEM, garanta:');
    memTutorial.Lines.Add('     wal_level = logical');
    memTutorial.Lines.Add('     max_replication_slots = 4 (ou maior)');
    memTutorial.Lines.Add('     max_wal_senders = 4 (ou maior)');
    memTutorial.Lines.Add('     (Reinicie o PostgreSQL se alterar o postgresql.conf e libere o IP no pg_hba.conf).');
    memTutorial.Lines.Add('  2. Conectado na ORIGEM: clique em "Criar Publicação" (CREATE PUBLICATION).');
    memTutorial.Lines.Add('  3. Garanta que a estrutura das tabelas (DDL) já exista no banco DESTINO.');
    memTutorial.Lines.Add('  4. Conectado no DESTINO: preencha os dados da origem e clique em "Criar Assinatura".');
    memTutorial.Lines.Add('     O PostgreSQL copiará os dados iniciais automaticamente pela rede (copy_data = true).');
  finally
    memTutorial.Lines.EndUpdate;
  end;
end;

procedure TReplicationForm.btnRefreshTutorialClick(Sender: TObject);
begin
  RefreshTutorialText;
end;

procedure TReplicationForm.btnCopyTutorialClick(Sender: TObject);
begin
  Clipboard.AsText := memTutorial.Lines.Text;
end;

end.
