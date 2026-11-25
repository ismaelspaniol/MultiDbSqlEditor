unit Presentation.TriggerDebugValuesForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, LCLType,
  Domain.QueryResult,
  Domain.TableStructureTypes,
  Domain.PsqlDebugger;

type
  TTriggerFieldEditItem = record
    FieldName: string;
    DataType: string;
    OrigIsNull: Boolean;
    OrigValue: string;
    OldIsNull: Boolean;
    OldValue: string;
    NewIsNull: Boolean;
    NewValue: string;
  end;

  { Diálogo para editar valores OLD e NEW antes de iniciar o debug de uma Trigger }
  TTriggerDebugValuesForm = class(TForm)
  private
    pnlTop: TPanel;
    lblTriggerInfo: TLabel;
    lblEvent: TLabel;
    cbEvent: TComboBox;
    btnCopyOldToNew: TButton;
    btnClearNew: TButton;
    btnClearOld: TButton;
    grdValues: TStringGrid;
    pnlBottom: TPanel;
    lblHint: TLabel;
    btnStartDebug: TButton;
    btnCancel: TButton;
    FItems: array of TTriggerFieldEditItem;
    FLastEvent: string;
    procedure BuildUI(const ATableName: string; const ATrigger: TTableTriggerInfo);
    procedure LoadFields(
      const AColumns: TTableColumnInfoArray;
      const AResult: TQueryResult;
      const ADataRowIndex: Integer
    );
    procedure ApplyEventDefaults(const AEvent: string);
    procedure RefreshGrid;
    procedure cbEventChange(Sender: TObject);
    procedure btnCopyOldToNewClick(Sender: TObject);
    procedure btnClearNewClick(Sender: TObject);
    procedure btnClearOldClick(Sender: TObject);
    procedure grdValuesSelectEditor(Sender: TObject; aCol, aRow: Integer; var Editor: TWinControl);
    procedure grdValuesSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
    procedure grdValuesMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure grdValuesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure grdValuesPrepareCanvas(Sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    class function Execute(
      const ATableName: string;
      const ATrigger: TTableTriggerInfo;
      const AColumns: TTableColumnInfoArray;
      const AResult: TQueryResult;
      const ADataRowIndex: Integer;
      out AChosenEvent: string;
      out AOldFields, ANewFields: TDebugParamDeclArray
    ): Boolean;
  end;

implementation

procedure TTriggerDebugValuesForm.BuildUI(
  const ATableName: string;
  const ATrigger: TTableTriggerInfo
);
begin
  Caption := Format('Debugar Trigger: %s (%s)', [ATrigger.TriggerName, ATableName]);
  Width := 920;
  Height := 600;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 70;
  pnlTop.BevelOuter := bvNone;

  lblTriggerInfo := TLabel.Create(Self);
  lblTriggerInfo.Parent := pnlTop;
  lblTriggerInfo.Left := 10;
  lblTriggerInfo.Top := 8;
  lblTriggerInfo.Font.Style := [fsBold];
  lblTriggerInfo.Caption := Format('Trigger: %s  |  %s %s  |  Tabela: %s',
    [ATrigger.TriggerName, ATrigger.Timing, ATrigger.Events, ATableName]);

  lblEvent := TLabel.Create(Self);
  lblEvent.Parent := pnlTop;
  lblEvent.Left := 10;
  lblEvent.Top := 38;
  lblEvent.Caption := 'Simular Evento:';

  cbEvent := TComboBox.Create(Self);
  cbEvent.Parent := pnlTop;
  cbEvent.Left := 104;
  cbEvent.Top := 34;
  cbEvent.Width := 115;
  cbEvent.Style := csDropDownList;
  if ATrigger.HasInsert then
    cbEvent.Items.Add('INSERT');
  if ATrigger.HasUpdate then
    cbEvent.Items.Add('UPDATE');
  if ATrigger.HasDelete then
    cbEvent.Items.Add('DELETE');
  if cbEvent.Items.Count = 0 then
  begin
    cbEvent.Items.Add('INSERT');
    cbEvent.Items.Add('UPDATE');
    cbEvent.Items.Add('DELETE');
  end;
  if cbEvent.Items.IndexOf('UPDATE') >= 0 then
    cbEvent.ItemIndex := cbEvent.Items.IndexOf('UPDATE')
  else
    cbEvent.ItemIndex := 0;
  cbEvent.OnChange := @cbEventChange;

  btnCopyOldToNew := TButton.Create(Self);
  btnCopyOldToNew.Parent := pnlTop;
  btnCopyOldToNew.Left := 232;
  btnCopyOldToNew.Top := 33;
  btnCopyOldToNew.Width := 135;
  btnCopyOldToNew.Height := 26;
  btnCopyOldToNew.Caption := 'Copiar OLD → NEW';
  btnCopyOldToNew.OnClick := @btnCopyOldToNewClick;

  btnClearNew := TButton.Create(Self);
  btnClearNew.Parent := pnlTop;
  btnClearNew.Left := 374;
  btnClearNew.Top := 33;
  btnClearNew.Width := 135;
  btnClearNew.Height := 26;
  btnClearNew.Caption := 'Limpar NEW (NULL)';
  btnClearNew.OnClick := @btnClearNewClick;

  btnClearOld := TButton.Create(Self);
  btnClearOld.Parent := pnlTop;
  btnClearOld.Left := 516;
  btnClearOld.Top := 33;
  btnClearOld.Width := 135;
  btnClearOld.Height := 26;
  btnClearOld.Caption := 'Limpar OLD (NULL)';
  btnClearOld.OnClick := @btnClearOldClick;

  grdValues := TStringGrid.Create(Self);
  grdValues.Parent := Self;
  grdValues.Align := alClient;
  grdValues.BorderSpacing.Left := 8;
  grdValues.BorderSpacing.Right := 8;
  grdValues.ColCount := 6;
  grdValues.FixedCols := 0;
  grdValues.FixedRows := 1;
  grdValues.DefaultRowHeight := 22;
  grdValues.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine,
    goEditing, goColSizing, goThumbTracking];
  grdValues.Cells[0, 0] := 'Campo';
  grdValues.Cells[1, 0] := 'Tipo';
  grdValues.Cells[2, 0] := 'OLD (Valor)';
  grdValues.Cells[3, 0] := 'OLD NULL';
  grdValues.Cells[4, 0] := 'NEW (Valor)';
  grdValues.Cells[5, 0] := 'NEW NULL';
  grdValues.ColWidths[0] := 170;
  grdValues.ColWidths[1] := 110;
  grdValues.ColWidths[2] := 215;
  grdValues.ColWidths[3] := 70;
  grdValues.ColWidths[4] := 215;
  grdValues.ColWidths[5] := 70;
  grdValues.OnSelectEditor := @grdValuesSelectEditor;
  grdValues.OnSetEditText := @grdValuesSetEditText;
  grdValues.OnMouseDown := @grdValuesMouseDown;
  grdValues.OnKeyDown := @grdValuesKeyDown;
  grdValues.OnPrepareCanvas := @grdValuesPrepareCanvas;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 48;
  pnlBottom.BevelOuter := bvNone;

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := pnlBottom;
  btnCancel.Align := alRight;
  btnCancel.Width := 95;
  btnCancel.BorderSpacing.Top := 10;
  btnCancel.BorderSpacing.Bottom := 10;
  btnCancel.BorderSpacing.Right := 8;
  btnCancel.Cancel := True;
  btnCancel.ModalResult := mrCancel;
  btnCancel.Caption := 'Cancelar';

  btnStartDebug := TButton.Create(Self);
  btnStartDebug.Parent := pnlBottom;
  btnStartDebug.Align := alRight;
  btnStartDebug.Width := 140;
  btnStartDebug.BorderSpacing.Top := 10;
  btnStartDebug.BorderSpacing.Bottom := 10;
  btnStartDebug.BorderSpacing.Right := 8;
  btnStartDebug.Default := True;
  btnStartDebug.ModalResult := mrOk;
  btnStartDebug.Caption := 'Iniciar Debug (F9)';

  lblHint := TLabel.Create(Self);
  lblHint.Parent := pnlBottom;
  lblHint.Align := alClient;
  lblHint.Layout := tlCenter;
  lblHint.BorderSpacing.Left := 10;
  lblHint.BorderSpacing.Right := 8;
  lblHint.Caption := 'Edite OLD/NEW diretamente na grade. Clique em OLD NULL / NEW NULL (ou Espaço) para alternar NULL.';
end;

procedure TTriggerDebugValuesForm.LoadFields(
  const AColumns: TTableColumnInfoArray;
  const AResult: TQueryResult;
  const ADataRowIndex: Integer
);
var
  I, J, ColIdx: Integer;
  Row: TQueryRow;
  ColName: string;
  Exists: Boolean;
begin
  SetLength(FItems, 0);
  Row := nil;
  if (AResult <> nil) and (ADataRowIndex >= 0) and (ADataRowIndex < AResult.RowCount) then
    Row := AResult.GetRow(ADataRowIndex);

  for I := 0 to High(AColumns) do
  begin
    SetLength(FItems, Length(FItems) + 1);
    FItems[High(FItems)].FieldName := AColumns[I].ColumnName;
    FItems[High(FItems)].DataType := AColumns[I].DataType;
    FItems[High(FItems)].OrigIsNull := True;
    FItems[High(FItems)].OrigValue := '';

    if AResult <> nil then
    begin
      for ColIdx := 0 to AResult.ColumnCount - 1 do
      begin
        if SameText(AResult.GetColumn(ColIdx).Name, AColumns[I].ColumnName) then
        begin
          if ColIdx < Length(Row) then
          begin
            FItems[High(FItems)].OrigIsNull := Row[ColIdx].IsNull;
            FItems[High(FItems)].OrigValue := Row[ColIdx].AsText;
          end;
          Break;
        end;
      end;
    end;
  end;

  if AResult <> nil then
  begin
    for ColIdx := 0 to AResult.ColumnCount - 1 do
    begin
      ColName := AResult.GetColumn(ColIdx).Name;
      Exists := False;
      for J := 0 to High(FItems) do
      begin
        if SameText(FItems[J].FieldName, ColName) then
        begin
          Exists := True;
          Break;
        end;
      end;
      if not Exists then
      begin
        SetLength(FItems, Length(FItems) + 1);
        FItems[High(FItems)].FieldName := ColName;
        FItems[High(FItems)].DataType := AResult.GetColumn(ColIdx).DataTypeName;
        if ColIdx < Length(Row) then
        begin
          FItems[High(FItems)].OrigIsNull := Row[ColIdx].IsNull;
          FItems[High(FItems)].OrigValue := Row[ColIdx].AsText;
        end
        else
        begin
          FItems[High(FItems)].OrigIsNull := True;
          FItems[High(FItems)].OrigValue := '';
        end;
      end;
    end;
  end;
end;

procedure TTriggerDebugValuesForm.ApplyEventDefaults(const AEvent: string);
var
  I: Integer;
  EvtUp: string;
begin
  EvtUp := UpperCase(Trim(AEvent));
  FLastEvent := EvtUp;
  for I := 0 to High(FItems) do
  begin
    if EvtUp = 'INSERT' then
    begin
      FItems[I].OldIsNull := True;
      FItems[I].OldValue := '';
      FItems[I].NewIsNull := FItems[I].OrigIsNull;
      FItems[I].NewValue := FItems[I].OrigValue;
    end
    else if EvtUp = 'DELETE' then
    begin
      FItems[I].OldIsNull := FItems[I].OrigIsNull;
      FItems[I].OldValue := FItems[I].OrigValue;
      FItems[I].NewIsNull := True;
      FItems[I].NewValue := '';
    end
    else
    begin
      FItems[I].OldIsNull := FItems[I].OrigIsNull;
      FItems[I].OldValue := FItems[I].OrigValue;
      FItems[I].NewIsNull := FItems[I].OrigIsNull;
      FItems[I].NewValue := FItems[I].OrigValue;
    end;
  end;
  RefreshGrid;
end;

procedure TTriggerDebugValuesForm.RefreshGrid;
var
  I, R: Integer;
begin
  grdValues.RowCount := 1 + Length(FItems);
  for I := 0 to High(FItems) do
  begin
    R := I + 1;
    grdValues.Cells[0, R] := FItems[I].FieldName;
    grdValues.Cells[1, R] := FItems[I].DataType;
    if FItems[I].OldIsNull then
    begin
      grdValues.Cells[2, R] := '<NULL>';
      grdValues.Cells[3, R] := '[X]';
    end
    else
    begin
      grdValues.Cells[2, R] := FItems[I].OldValue;
      grdValues.Cells[3, R] := '[ ]';
    end;

    if FItems[I].NewIsNull then
    begin
      grdValues.Cells[4, R] := '<NULL>';
      grdValues.Cells[5, R] := '[X]';
    end
    else
    begin
      grdValues.Cells[4, R] := FItems[I].NewValue;
      grdValues.Cells[5, R] := '[ ]';
    end;
  end;
  grdValues.Invalidate;
end;

procedure TTriggerDebugValuesForm.cbEventChange(Sender: TObject);
begin
  ApplyEventDefaults(cbEvent.Text);
end;

procedure TTriggerDebugValuesForm.btnCopyOldToNewClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
  begin
    FItems[I].NewIsNull := FItems[I].OldIsNull;
    FItems[I].NewValue := FItems[I].OldValue;
  end;
  RefreshGrid;
end;

procedure TTriggerDebugValuesForm.btnClearNewClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
  begin
    FItems[I].NewIsNull := True;
    FItems[I].NewValue := '';
  end;
  RefreshGrid;
end;

procedure TTriggerDebugValuesForm.btnClearOldClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
  begin
    FItems[I].OldIsNull := True;
    FItems[I].OldValue := '';
  end;
  RefreshGrid;
end;

procedure TTriggerDebugValuesForm.grdValuesSelectEditor(
  Sender: TObject;
  aCol, aRow: Integer;
  var Editor: TWinControl
);
begin
  if (aCol <> 2) and (aCol <> 4) then
    Editor := nil;
end;

procedure TTriggerDebugValuesForm.grdValuesSetEditText(
  Sender: TObject;
  ACol, ARow: Integer;
  const Value: string
);
var
  Idx: Integer;
begin
  Idx := ARow - 1;
  if (Idx < 0) or (Idx > High(FItems)) then
    Exit;

  if ACol = 2 then
  begin
    if Value <> '<NULL>' then
    begin
      FItems[Idx].OldIsNull := False;
      FItems[Idx].OldValue := Value;
      grdValues.Cells[3, ARow] := '[ ]';
    end;
  end
  else if ACol = 4 then
  begin
    if Value <> '<NULL>' then
    begin
      FItems[Idx].NewIsNull := False;
      FItems[Idx].NewValue := Value;
      grdValues.Cells[5, ARow] := '[ ]';
    end;
  end;
  grdValues.Invalidate;
end;

procedure TTriggerDebugValuesForm.grdValuesMouseDown(
  Sender: TObject;
  Button: TMouseButton;
  Shift: TShiftState;
  X, Y: Integer
);
var
  ACol, ARow, Idx: Integer;
begin
  if Button <> mbLeft then
    Exit;
  grdValues.MouseToCell(X, Y, ACol, ARow);
  Idx := ARow - 1;
  if (Idx < 0) or (Idx > High(FItems)) then
    Exit;

  if ACol = 3 then
  begin
    FItems[Idx].OldIsNull := not FItems[Idx].OldIsNull;
    RefreshGrid;
  end
  else if ACol = 5 then
  begin
    FItems[Idx].NewIsNull := not FItems[Idx].NewIsNull;
    RefreshGrid;
  end;
end;

procedure TTriggerDebugValuesForm.grdValuesKeyDown(
  Sender: TObject;
  var Key: Word;
  Shift: TShiftState
);
var
  Idx: Integer;
begin
  if (Key = VK_SPACE) and ((grdValues.Col = 3) or (grdValues.Col = 5)) then
  begin
    Key := 0;
    Idx := grdValues.Row - 1;
    if (Idx < 0) or (Idx > High(FItems)) then
      Exit;
    if grdValues.Col = 3 then
      FItems[Idx].OldIsNull := not FItems[Idx].OldIsNull
    else
      FItems[Idx].NewIsNull := not FItems[Idx].NewIsNull;
    RefreshGrid;
  end;
end;

procedure TTriggerDebugValuesForm.grdValuesPrepareCanvas(
  Sender: TObject;
  aCol, aRow: Integer;
  aState: TGridDrawState
);
var
  Idx: Integer;
  IsDiff: Boolean;
begin
  Idx := aRow - 1;
  if (Idx < 0) or (Idx > High(FItems)) or (gdSelected in aState) then
    Exit;

  IsDiff := (FItems[Idx].OldIsNull <> FItems[Idx].NewIsNull) or
            ((not FItems[Idx].OldIsNull) and (FItems[Idx].OldValue <> FItems[Idx].NewValue));
  if IsDiff then
    grdValues.Canvas.Brush.Color := RGBToColor(224, 242, 254);

  if ((aCol = 2) and FItems[Idx].OldIsNull) or ((aCol = 4) and FItems[Idx].NewIsNull) then
    grdValues.Canvas.Font.Color := clGray;
end;

procedure TTriggerDebugValuesForm.FormKeyDown(
  Sender: TObject;
  var Key: Word;
  Shift: TShiftState
);
begin
  if (Key = VK_F9) and (Shift = []) then
  begin
    Key := 0;
    ModalResult := mrOk;
  end;
end;

class function TTriggerDebugValuesForm.Execute(
  const ATableName: string;
  const ATrigger: TTableTriggerInfo;
  const AColumns: TTableColumnInfoArray;
  const AResult: TQueryResult;
  const ADataRowIndex: Integer;
  out AChosenEvent: string;
  out AOldFields, ANewFields: TDebugParamDeclArray
): Boolean;
var
  Frm: TTriggerDebugValuesForm;
  I: Integer;
begin
  Result := False;
  AChosenEvent := '';
  SetLength(AOldFields, 0);
  SetLength(ANewFields, 0);

  Frm := TTriggerDebugValuesForm.CreateNew(Forms.Application);
  try
    Frm.BuildUI(ATableName, ATrigger);
    Frm.LoadFields(AColumns, AResult, ADataRowIndex);
    Frm.ApplyEventDefaults(Frm.cbEvent.Text);

    if Frm.ShowModal = mrOk then
    begin
      AChosenEvent := Frm.cbEvent.Text;
      SetLength(AOldFields, Length(Frm.FItems));
      SetLength(ANewFields, Length(Frm.FItems));
      for I := 0 to High(Frm.FItems) do
      begin
        AOldFields[I].Name := Frm.FItems[I].FieldName;
        AOldFields[I].DataType := Frm.FItems[I].DataType;
        AOldFields[I].IsInput := True;
        AOldFields[I].IsOutput := False;
        AOldFields[I].IsNull := Frm.FItems[I].OldIsNull;
        AOldFields[I].Value := Frm.FItems[I].OldValue;

        ANewFields[I].Name := Frm.FItems[I].FieldName;
        ANewFields[I].DataType := Frm.FItems[I].DataType;
        ANewFields[I].IsInput := True;
        ANewFields[I].IsOutput := False;
        ANewFields[I].IsNull := Frm.FItems[I].NewIsNull;
        ANewFields[I].Value := Frm.FItems[I].NewValue;
      end;
      Result := True;
    end;
  finally
    Frm.Free;
  end;
end;

end.
