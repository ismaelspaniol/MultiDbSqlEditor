unit Presentation.GeneratorForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Clipbrd, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Application.ManageDatabaseObjectsUseCase;

type
  { Diálogo responsivo para visualizar, alterar, incrementar e excluir Generators/Sequences }
  TGeneratorForm = class(TForm)
    pnlContent: TPanel;
    lblHeader: TLabel;
    lblCurrentValue: TLabel;
    edtCurrentValue: TEdit;
    btnRefreshValue: TButton;
    lblNewValue: TLabel;
    edtNewValue: TEdit;
    btnApplyValue: TButton;
    lblStep: TLabel;
    edtStep: TEdit;
    btnIncrement: TButton;
    lblDdlPreview: TLabel;
    memDdl: TMemo;
    pnlButtons: TPanel;
    btnDropGenerator: TButton;
    btnCopyDdl: TButton;
    btnClose: TButton;
    procedure btnRefreshValueClick(Sender: TObject);
    procedure btnApplyValueClick(Sender: TObject);
    procedure btnIncrementClick(Sender: TObject);
    procedure btnCopyDdlClick(Sender: TObject);
    procedure btnDropGeneratorClick(Sender: TObject);
  private
    FProfile: TConnectionProfile;
    FGeneratorName: string;
    FUseCase: TManageDatabaseObjectsUseCase;
    FModified: Boolean;
    FDropped: Boolean;
    procedure UpdatePreviewFromValue(const AValue: Int64);
    procedure RefreshValue;
  public
    class function Execute(
      const AProfile: TConnectionProfile;
      const AGeneratorName: string;
      const AUseCase: TManageDatabaseObjectsUseCase;
      out ADropped: Boolean
    ): Boolean;
  end;

implementation

{$R *.lfm}

class function TGeneratorForm.Execute(
  const AProfile: TConnectionProfile;
  const AGeneratorName: string;
  const AUseCase: TManageDatabaseObjectsUseCase;
  out ADropped: Boolean
): Boolean;
var
  Frm: TGeneratorForm;
begin
  ADropped := False;
  Frm := TGeneratorForm.Create(nil);
  try
    Frm.FProfile := AProfile;
    Frm.FGeneratorName := AGeneratorName;
    Frm.FUseCase := AUseCase;
    Frm.FModified := False;
    Frm.FDropped := False;

    {$IFDEF UNIX}
    Frm.memDdl.Font.Name := 'Monospace';
    {$ENDIF}

    if AProfile.DatabaseType = dtPostgreSQL then
    begin
      Frm.Caption := 'Sequence: ' + AGeneratorName;
      Frm.lblHeader.Caption := Format('[%s] Sequence: %s', [AProfile.Name, AGeneratorName]);
      Frm.btnIncrement.Caption := '+ Incrementar (nextval)';
      Frm.btnDropGenerator.Caption := 'Excluir Sequence';
    end
    else
    begin
      Frm.Caption := 'Generator: ' + AGeneratorName;
      Frm.lblHeader.Caption := Format('[%s] Generator: %s', [AProfile.Name, AGeneratorName]);
      Frm.btnIncrement.Caption := '+ Incrementar (GEN_ID)';
      Frm.btnDropGenerator.Caption := 'Excluir Generator';
    end;

    Frm.RefreshValue;
    Frm.ShowModal;
    ADropped := Frm.FDropped;
    Result := Frm.FModified or Frm.FDropped;
  finally
    Frm.Free;
  end;
end;

procedure TGeneratorForm.UpdatePreviewFromValue(const AValue: Int64);
var
  Ident, EscName: string;
begin
  Ident := QuoteDbIdent(FProfile.DatabaseType, FGeneratorName);
  if FProfile.DatabaseType = dtPostgreSQL then
  begin
    EscName := StringReplace(FGeneratorName, '''', '''''', [rfReplaceAll]);
    memDdl.Lines.Text := Format(
      'CREATE SEQUENCE IF NOT EXISTS %s;' + LineEnding +
      'SELECT setval(''%s'', %d, true);',
      [Ident, EscName, AValue]
    );
  end
  else
    memDdl.Lines.Text := Format(
      'CREATE GENERATOR %s;' + LineEnding +
      'SET GENERATOR %s TO %d;',
      [Ident, Ident, AValue]
    );
end;

procedure TGeneratorForm.RefreshValue;
var
  CurVal: Int64;
begin
  Screen.Cursor := crHourGlass;
  try
    try
      CurVal := FUseCase.GetGeneratorValue(FProfile, FGeneratorName);
      edtCurrentValue.Text := IntToStr(CurVal);
      if Trim(edtNewValue.Text) = '' then
        edtNewValue.Text := IntToStr(CurVal);
      UpdatePreviewFromValue(CurVal);
    except
      on E: Exception do
        MessageDlg('Erro ao ler valor', E.Message, mtError, [mbOK], 0);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TGeneratorForm.btnRefreshValueClick(Sender: TObject);
begin
  RefreshValue;
end;

procedure TGeneratorForm.btnApplyValueClick(Sender: TObject);
var
  NewVal: Int64;
  Msg: string;
begin
  if not TryStrToInt64(Trim(edtNewValue.Text), NewVal) then
  begin
    MessageDlg('Validação', 'Informe um número inteiro válido para o novo valor.', mtWarning, [mbOK], 0);
    edtNewValue.SetFocus;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    if FUseCase.SetGeneratorValue(FProfile, FGeneratorName, NewVal, Msg) then
    begin
      FModified := True;
      edtCurrentValue.Text := IntToStr(NewVal);
      UpdatePreviewFromValue(NewVal);
      MessageDlg('Sucesso', Msg, mtInformation, [mbOK], 0);
    end
    else
      MessageDlg('Erro', Msg, mtError, [mbOK], 0);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TGeneratorForm.btnIncrementClick(Sender: TObject);
var
  StepVal, NewVal: Int64;
  Msg: string;
begin
  if not TryStrToInt64(Trim(edtStep.Text), StepVal) then
  begin
    MessageDlg('Validação', 'Informe um passo inteiro válido.', mtWarning, [mbOK], 0);
    edtStep.SetFocus;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    if FUseCase.IncrementGenerator(FProfile, FGeneratorName, StepVal, NewVal, Msg) then
    begin
      FModified := True;
      edtCurrentValue.Text := IntToStr(NewVal);
      edtNewValue.Text := IntToStr(NewVal);
      UpdatePreviewFromValue(NewVal);
    end
    else
      MessageDlg('Erro', Msg, mtError, [mbOK], 0);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TGeneratorForm.btnCopyDdlClick(Sender: TObject);
begin
  Clipboard.AsText := memDdl.Lines.Text;
end;

procedure TGeneratorForm.btnDropGeneratorClick(Sender: TObject);
var
  Msg: string;
begin
  if MessageDlg('Confirmar Exclusão',
    Format('Deseja realmente excluir "%s" do banco "%s"?', [FGeneratorName, FProfile.Name]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Screen.Cursor := crHourGlass;
  try
    if FUseCase.DropGenerator(FProfile, FGeneratorName, Msg) then
    begin
      FDropped := True;
      MessageDlg('Sucesso', Msg, mtInformation, [mbOK], 0);
      Close;
    end
    else
      MessageDlg('Erro', Msg, mtError, [mbOK], 0);
  finally
    Screen.Cursor := crDefault;
  end;
end;

end.
