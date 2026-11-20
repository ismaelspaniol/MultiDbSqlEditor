unit Presentation.ProcedureParamsForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Application.ManageDatabaseObjectsUseCase;

type
  TParamRowControls = record
    ParamInfo: TProcedureParamInfo;
    Panel: TPanel;
    LabelCtrl: TLabel;
    EditCtrl: TEdit;
    NullCheck: TCheckBox;
  end;

  { Diálogo dinâmico para preenchimento de parâmetros de entrada de Stored Procedures }
  TProcedureParamsForm = class(TForm)
    pnlHeader: TPanel;
    lblTitle: TLabel;
    lblSubtitle: TLabel;
    sbParams: TScrollBox;
    pnlFooter: TPanel;
    chkAutoCommit: TCheckBox;
    btnExecute: TButton;
    btnCancel: TButton;
    procedure btnExecuteClick(Sender: TObject);
  private
    FMeta: TProcedureMetadata;
    FUseCase: TManageDatabaseObjectsUseCase;
    FRows: array of TParamRowControls;
    FValues: TProcedureParamValueArray;
    procedure HandleNullCheckChange(Sender: TObject);
    procedure BuildParameterRows(const APreviousValues: TProcedureParamValueArray);
  public
    class function Execute(
      const AMeta: TProcedureMetadata;
      const AUseCase: TManageDatabaseObjectsUseCase;
      const APreviousValues: TProcedureParamValueArray;
      out AValues: TProcedureParamValueArray;
      out AAutoCommit: Boolean
    ): Boolean;
  end;

implementation

{$R *.lfm}

procedure TProcedureParamsForm.HandleNullCheckChange(Sender: TObject);
var
  Chk: TCheckBox;
  Idx: Integer;
begin
  if not (Sender is TCheckBox) then
    Exit;
  Chk := TCheckBox(Sender);
  Idx := Chk.Tag;
  if (Idx < 0) or (Idx >= Length(FRows)) then
    Exit;

  FRows[Idx].EditCtrl.Enabled := not Chk.Checked;
  if (not Chk.Checked) and FRows[Idx].EditCtrl.CanFocus then
    FRows[Idx].EditCtrl.SetFocus;
end;

procedure TProcedureParamsForm.BuildParameterRows(const APreviousValues: TProcedureParamValueArray);
var
  I, K, DesiredHeight: Integer;
  PInfo: TProcedureParamInfo;
  RowPanel: TPanel;
  Lbl: TLabel;
  Edt: TEdit;
  Chk: TCheckBox;
  ModeSuffix: string;
  FoundPrev, InitNull: Boolean;
  InitText: string;
  FirstEdit: TEdit;
begin
  SetLength(FRows, Length(FMeta.InputParams));
  FirstEdit := nil;

  for I := 0 to High(FMeta.InputParams) do
  begin
    PInfo := FMeta.InputParams[I];

    RowPanel := TPanel.Create(Self);
    RowPanel.Parent := sbParams;
    RowPanel.Top := I * 38;
    RowPanel.Align := alTop;
    RowPanel.Height := 30;
    RowPanel.BevelOuter := bvNone;
    RowPanel.BorderSpacing.Top := 2;
    RowPanel.BorderSpacing.Bottom := 4;
    RowPanel.TabOrder := I;

    if PInfo.Mode = ppmInOut then
      ModeSuffix := ' [INOUT]'
    else
      ModeSuffix := '';

    Lbl := TLabel.Create(Self);
    Lbl.Parent := RowPanel;
    Lbl.Align := alLeft;
    Lbl.Width := 230;
    Lbl.Layout := tlCenter;
    Lbl.ShowAccelChar := False;
    Lbl.Caption := Format('%s (%s)%s:', [PInfo.Name, PInfo.DataTypeDisplay, ModeSuffix]);
    Lbl.Hint := Lbl.Caption;
    Lbl.ShowHint := True;

    Chk := TCheckBox.Create(Self);
    Chk.Parent := RowPanel;
    Chk.Align := alRight;
    Chk.Width := 62;
    Chk.Caption := 'NULL';
    Chk.Tag := I;
    Chk.TabOrder := 1;
    Chk.OnChange := @HandleNullCheckChange;

    Edt := TEdit.Create(Self);
    Edt.Parent := RowPanel;
    Edt.Align := alClient;
    Edt.BorderSpacing.Left := 6;
    Edt.BorderSpacing.Right := 8;
    Edt.Tag := I;
    Edt.TabOrder := 0;

    InitNull := False;
    InitText := '';
    FoundPrev := False;
    for K := 0 to High(APreviousValues) do
    begin
      if SameText(APreviousValues[K].ParamName, PInfo.Name) then
      begin
        InitNull := APreviousValues[K].IsNull;
        InitText := APreviousValues[K].RawValue;
        FoundPrev := True;
        Break;
      end;
    end;

    if (not FoundPrev) and PInfo.HasDefault then
    begin
      InitNull := PInfo.DefaultIsNull;
      InitText := PInfo.DefaultValue;
    end;

    Edt.Text := InitText;
    Chk.Checked := InitNull;
    Edt.Enabled := not InitNull;

    if (FirstEdit = nil) and Edt.Enabled then
      FirstEdit := Edt;

    FRows[I].ParamInfo := PInfo;
    FRows[I].Panel := RowPanel;
    FRows[I].LabelCtrl := Lbl;
    FRows[I].EditCtrl := Edt;
    FRows[I].NullCheck := Chk;
  end;

  DesiredHeight := 160 + Length(FMeta.InputParams) * 36;
  if DesiredHeight < 280 then
    DesiredHeight := 280
  else if DesiredHeight > 560 then
    DesiredHeight := 560;
  Height := DesiredHeight;

  if FirstEdit <> nil then
    ActiveControl := FirstEdit
  else
    ActiveControl := btnExecute;
end;

procedure TProcedureParamsForm.btnExecuteClick(Sender: TObject);
var
  I: Integer;
begin
  SetLength(FValues, Length(FRows));
  for I := 0 to High(FRows) do
  begin
    FValues[I].ParamName := FRows[I].ParamInfo.Name;
    FValues[I].IsNull := FRows[I].NullCheck.Checked;
    FValues[I].RawValue := FRows[I].EditCtrl.Text;
  end;

  try
    if FUseCase <> nil then
      FUseCase.BuildExecuteProcedureSQL(FMeta, FValues);
    ModalResult := mrOk;
  except
    on E: Exception do
    begin
      MessageDlg('Parâmetro inválido', E.Message, mtWarning, [mbOK], 0);
    end;
  end;
end;

class function TProcedureParamsForm.Execute(
  const AMeta: TProcedureMetadata;
  const AUseCase: TManageDatabaseObjectsUseCase;
  const APreviousValues: TProcedureParamValueArray;
  out AValues: TProcedureParamValueArray;
  out AAutoCommit: Boolean
): Boolean;
var
  Frm: TProcedureParamsForm;
begin
  Result := False;
  AValues := nil;
  AAutoCommit := True;

  Frm := TProcedureParamsForm.Create(Forms.Application);
  try
    Frm.FMeta := AMeta;
    Frm.FUseCase := AUseCase;
    Frm.Caption := Format('Executar %s', [AMeta.ProcedureName]);
    Frm.lblTitle.Caption := Format('Executar Procedure: %s', [AMeta.ProcedureName]);
    Frm.BuildParameterRows(APreviousValues);

    if Frm.ShowModal = mrOk then
    begin
      AValues := Frm.FValues;
      AAutoCommit := Frm.chkAutoCommit.Checked;
      Result := True;
    end;
  finally
    Frm.Free;
  end;
end;

end.
