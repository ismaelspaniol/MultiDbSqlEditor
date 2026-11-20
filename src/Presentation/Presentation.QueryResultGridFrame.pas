unit Presentation.QueryResultGridFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Clipbrd, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, Menus, LCLType,
  Domain.QueryResult;

type
  TResultGridExportedEvent = procedure(Sender: TObject; const AFileName: string) of object;

  { Frame reutilizável de exibição, ordenação, cópia e exportação CSV de TQueryResult }
  TQueryResultGridFrame = class(TFrame)
    grdResults: TDrawGrid;
    pnlGridFooter: TPanel;
    lblGridSummary: TLabel;
    dlgSaveCsv: TSaveDialog;
    pmGrid: TPopupMenu;
    miCopyCell: TMenuItem;
    miCopySelection: TMenuItem;
    miCopyRow: TMenuItem;
    miCopyRowWithHeader: TMenuItem;
    miGridSep1: TMenuItem;
    miCopyColName: TMenuItem;
    miGridSep2: TMenuItem;
    miExportCsv: TMenuItem;
    procedure grdResultsDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure grdResultsHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
    procedure grdResultsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure grdResultsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure grdResultsTopLeftChanged(Sender: TObject);
    procedure pmGridPopup(Sender: TObject);
    procedure miCopyCellClick(Sender: TObject);
    procedure miCopySelectionClick(Sender: TObject);
    procedure miCopyRowClick(Sender: TObject);
    procedure miCopyRowWithHeaderClick(Sender: TObject);
    procedure miCopyColNameClick(Sender: TObject);
    procedure miExportCsvClick(Sender: TObject);
  private
    FResult: TQueryResult; // Referência não-proprietária
    FSortCol: Integer;
    FSortAsc: Boolean;
    FLastClickedGridCol: Integer;
    FSortingEnabled: Boolean;
    FExportEnabled: Boolean;
    FEmptyMessage: string;
    FOnNeedMoreRows: TNotifyEvent;
    FOnExportedCsv: TResultGridExportedEvent;
    procedure SetEmptyMessage(const AValue: string);
    function GetGridCellText(const ACol, ARow: Integer): string;
    procedure CopySelectedCell;
    procedure CopySelectedRange;
    procedure CopyCurrentRow(const AIncludeHeader: Boolean);
    procedure CopyCurrentColumnName;
    function EscapeCsvField(const AValue: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetResult(
      const AResult: TQueryResult;
      const AResetSort: Boolean = True;
      const AAutoFit: Boolean = True
    );
    procedure RefreshRowCount;
    procedure UpdateSummaryText;
    procedure SetCustomSummary(const AText: string);
    procedure AutoFitColumns;
    function CanExportCsv: Boolean;
    function ExportToCsv: Boolean;
    function IsNearBottom(const AThreshold: Integer = 10): Boolean;
    property SortingEnabled: Boolean read FSortingEnabled write FSortingEnabled;
    property ExportEnabled: Boolean read FExportEnabled write FExportEnabled;
    property EmptyMessage: string read FEmptyMessage write SetEmptyMessage;
    property OnNeedMoreRows: TNotifyEvent read FOnNeedMoreRows write FOnNeedMoreRows;
    property OnExportedCsv: TResultGridExportedEvent read FOnExportedCsv write FOnExportedCsv;
  end;

implementation

{$R *.lfm}

constructor TQueryResultGridFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FResult := nil;
  FSortCol := -1;
  FSortAsc := True;
  FLastClickedGridCol := -1;
  FSortingEnabled := True;
  FExportEnabled := True;
  FEmptyMessage := 'Nenhuma consulta executada.';
end;

procedure TQueryResultGridFrame.SetEmptyMessage(const AValue: string);
begin
  FEmptyMessage := AValue;
  if (FResult = nil) and (lblGridSummary <> nil) then
    lblGridSummary.Caption := FEmptyMessage;
end;

procedure TQueryResultGridFrame.SetResult(
  const AResult: TQueryResult;
  const AResetSort: Boolean;
  const AAutoFit: Boolean
);
begin
  FResult := AResult;
  if AResetSort then
  begin
    FSortCol := -1;
    FSortAsc := True;
    FLastClickedGridCol := -1;
  end;

  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
  begin
    grdResults.ColCount := 1;
    grdResults.RowCount := 1;
    grdResults.Invalidate;
    UpdateSummaryText;
    Exit;
  end;

  grdResults.ColCount := FResult.ColumnCount;
  grdResults.RowCount := FResult.RowCount + 1;
  grdResults.FixedRows := 1;
  if AAutoFit then
    AutoFitColumns;
  grdResults.Invalidate;
  UpdateSummaryText;
end;

procedure TQueryResultGridFrame.RefreshRowCount;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    grdResults.RowCount := 1
  else
    grdResults.RowCount := Max(1, FResult.RowCount + 1);
  UpdateSummaryText;
end;

procedure TQueryResultGridFrame.UpdateSummaryText;
var
  MemInfo: string;
begin
  if (FResult = nil) or (not FResult.HasResultSet) then
  begin
    if (FResult <> nil) and (Trim(FResult.MessageText) <> '') then
      lblGridSummary.Caption := FResult.MessageText
    else
      lblGridSummary.Caption := FEmptyMessage;
    Exit;
  end;

  if FResult.MemoryLimitBytes > 0 then
    MemInfo := Format('%s / %s', [
      FormatByteSize(FResult.EstimatedMemoryBytes),
      FormatByteSize(FResult.MemoryLimitBytes)
    ])
  else
    MemInfo := Format('%s (sem limite)', [FormatByteSize(FResult.EstimatedMemoryBytes)]);

  if FResult.SystemMemoryLow then
    lblGridSummary.Caption := Format(
      '[PROTEÇÃO RAM DO SO] %d registro(s) mantidos | RAM: %s | Tempo: %d ms',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs]
    )
  else if FResult.MemoryLimitReached then
    lblGridSummary.Caption := Format(
      '[LIMITE RAM ATINGIDO] %d registro(s) mantidos | RAM: %s | Tempo: %d ms',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs]
    )
  else if FResult.HasMoreRows then
    lblGridSummary.Caption := Format(
      'Registros carregados: %d (role para carregar mais ou clique em Fetch All) | RAM: %s | Tempo: %d ms',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs]
    )
  else
    lblGridSummary.Caption := Format(
      'Total de registros: %d | RAM: %s | Tempo: %d ms',
      [FResult.RowCount, MemInfo, FResult.ExecutionTimeMs]
    );
end;

procedure TQueryResultGridFrame.SetCustomSummary(const AText: string);
begin
  if lblGridSummary <> nil then
    lblGridSummary.Caption := AText;
end;

procedure TQueryResultGridFrame.AutoFitColumns;
var
  C, R, MaxRows, W, ColW: Integer;
  CanMeasure: Boolean;
  HeaderText, CellText: string;
  Row: TQueryRow;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  CanMeasure := grdResults.HandleAllocated;
  if not CanMeasure then
  begin
    for C := 0 to FResult.ColumnCount - 1 do
      grdResults.ColWidths[C] := 150;
    Exit;
  end;

  MaxRows := Min(50, FResult.RowCount);
  grdResults.Canvas.Font.Assign(grdResults.Font);

  for C := 0 to FResult.ColumnCount - 1 do
  begin
    grdResults.Canvas.Font.Style := [fsBold];
    HeaderText := FResult.GetColumn(C).Name + ' ▲';
    ColW := grdResults.Canvas.TextWidth(HeaderText) + 20;

    grdResults.Canvas.Font.Style := [];
    for R := 0 to MaxRows - 1 do
    begin
      Row := FResult.GetRow(R);
      if C < Length(Row) then
      begin
        if Row[C].IsNull then
          CellText := '(NULL)'
        else
          CellText := Row[C].AsText;
        W := grdResults.Canvas.TextWidth(CellText) + 16;
        if W > ColW then
          ColW := W;
      end;
    end;

    if ColW < 70 then
      ColW := 70
    else if ColW > 320 then
      ColW := 320;
    grdResults.ColWidths[C] := ColW;
  end;
end;

function TQueryResultGridFrame.IsNearBottom(const AThreshold: Integer): Boolean;
begin
  Result := (grdResults.TopRow + grdResults.VisibleRowCount >= grdResults.RowCount - AThreshold);
end;

procedure TQueryResultGridFrame.grdResultsTopLeftChanged(Sender: TObject);
begin
  if Assigned(FOnNeedMoreRows) and IsNearBottom(10) then
    FOnNeedMoreRows(Self);
end;

procedure TQueryResultGridFrame.grdResultsHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
begin
  if (not FSortingEnabled) or (not IsColumn) or (FResult = nil) or (not FResult.HasResultSet) then
    Exit;
  if (Index < 0) or (Index >= FResult.ColumnCount) then
    Exit;

  if FSortCol = Index then
    FSortAsc := not FSortAsc
  else
  begin
    FSortCol := Index;
    FSortAsc := True;
  end;

  FResult.SortByColumn(FSortCol, FSortAsc);
  grdResults.Invalidate;
end;

procedure TQueryResultGridFrame.grdResultsDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
var
  CellText: string;
  Row: TQueryRow;
  TextRect: TRect;
  IsCellSelected: Boolean;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  TextRect := aRect;
  InflateRect(TextRect, -4, -2);

  if aRow = 0 then
  begin
    if aCol < FResult.ColumnCount then
    begin
      grdResults.Canvas.Font.Style := [fsBold];
      grdResults.Canvas.Font.Color := clWindowText;
      CellText := FResult.GetColumn(aCol).Name;
      if aCol = FSortCol then
      begin
        if FSortAsc then
          CellText := CellText + ' ▲'
        else
          CellText := CellText + ' ▼';
      end;
      grdResults.Canvas.TextRect(TextRect, TextRect.Left, TextRect.Top, CellText);
    end;
    Exit;
  end;

  if (aRow - 1 < FResult.RowCount) and (aCol < FResult.ColumnCount) then
  begin
    IsCellSelected := (gdSelected in aState) and
      ((not (gdFocused in aState)) or
       (goDrawFocusSelected in grdResults.Options) or
       ((goRowSelect in grdResults.Options) and not (goRelaxedRowSelect in grdResults.Options)));

    Row := FResult.GetRow(aRow - 1);
    if (aCol >= Length(Row)) or Row[aCol].IsNull then
    begin
      grdResults.Canvas.Font.Style := [fsItalic];
      if not IsCellSelected then
        grdResults.Canvas.Font.Color := clGrayText;
      CellText := '(NULL)';
    end
    else
    begin
      grdResults.Canvas.Font.Style := [];
      if not IsCellSelected then
        grdResults.Canvas.Font.Color := clWindowText;
      CellText := Row[aCol].AsText;
    end;
    grdResults.Canvas.TextRect(TextRect, TextRect.Left, TextRect.Top, CellText);
  end;
end;

function TQueryResultGridFrame.GetGridCellText(const ACol, ARow: Integer): string;
var
  RowData: TQueryRow;
begin
  Result := '';
  if (FResult = nil) or (not FResult.HasResultSet) then
    Exit;
  if (ARow < 1) or (ARow - 1 >= FResult.RowCount) then
    Exit;
  if (ACol < 0) or (ACol >= FResult.ColumnCount) then
    Exit;

  RowData := FResult.GetRow(ARow - 1);
  if (ACol < Length(RowData)) and (not RowData[ACol].IsNull) then
    Result := RowData[ACol].AsText;
end;

procedure TQueryResultGridFrame.CopySelectedCell;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or
     (FResult.RowCount = 0) or (FResult.ColumnCount = 0) then
    Exit;
  if (grdResults.Row < 1) or (grdResults.Col < 0) then
    Exit;
  Clipboard.AsText := GetGridCellText(grdResults.Col, grdResults.Row);
end;

procedure TQueryResultGridFrame.CopySelectedRange;
var
  Sel: TGridRect;
  R, C, MinR, MaxR, MinC, MaxC: Integer;
  SL: TStringList;
  LineText: string;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or
     (FResult.RowCount = 0) or (FResult.ColumnCount = 0) then
    Exit;

  Sel := grdResults.Selection;
  MinR := Max(1, Min(Sel.Top, Sel.Bottom));
  MaxR := Min(FResult.RowCount, Max(Sel.Top, Sel.Bottom));
  MinC := Max(0, Min(Sel.Left, Sel.Right));
  MaxC := Min(FResult.ColumnCount - 1, Max(Sel.Left, Sel.Right));
  if (MinR > MaxR) or (MinC > MaxC) then
    Exit;

  SL := TStringList.Create;
  try
    for R := MinR to MaxR do
    begin
      LineText := '';
      for C := MinC to MaxC do
      begin
        if C > MinC then
          LineText := LineText + #9;
        LineText := LineText + GetGridCellText(C, R);
      end;
      SL.Add(LineText);
    end;
    Clipboard.AsText := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TQueryResultGridFrame.CopyCurrentRow(const AIncludeHeader: Boolean);
var
  C, DataRow: Integer;
  HeaderLine, DataLine: string;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or
     (FResult.RowCount = 0) or (FResult.ColumnCount = 0) then
    Exit;

  DataRow := grdResults.Row;
  if (DataRow < 1) or (DataRow - 1 >= FResult.RowCount) then
    Exit;

  HeaderLine := '';
  DataLine := '';
  for C := 0 to FResult.ColumnCount - 1 do
  begin
    if C > 0 then
    begin
      HeaderLine := HeaderLine + #9;
      DataLine := DataLine + #9;
    end;
    if AIncludeHeader then
      HeaderLine := HeaderLine + FResult.GetColumn(C).Name;
    DataLine := DataLine + GetGridCellText(C, DataRow);
  end;

  if AIncludeHeader then
    Clipboard.AsText := HeaderLine + LineEnding + DataLine
  else
    Clipboard.AsText := DataLine;
end;

procedure TQueryResultGridFrame.CopyCurrentColumnName;
var
  TargetCol: Integer;
begin
  if (FResult = nil) or (not FResult.HasResultSet) or (FResult.ColumnCount = 0) then
    Exit;

  TargetCol := FLastClickedGridCol;
  if (TargetCol < 0) or (TargetCol >= FResult.ColumnCount) then
    TargetCol := grdResults.Col;
  if (TargetCol >= 0) and (TargetCol < FResult.ColumnCount) then
    Clipboard.AsText := FResult.GetColumn(TargetCol).Name;
end;

procedure TQueryResultGridFrame.grdResultsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Sel: TGridRect;
begin
  if (ssCtrl in Shift) and ((Key = VK_C) or (Key = Ord('C'))) then
  begin
    Key := 0;
    Sel := grdResults.Selection;
    if (Sel.Left <> Sel.Right) or (Sel.Top <> Sel.Bottom) then
      CopySelectedRange
    else
      CopySelectedCell;
  end;
end;

procedure TQueryResultGridFrame.grdResultsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  ACol, ARow: Integer;
  Sel: TGridRect;
  InSelection: Boolean;
begin
  if Button <> mbRight then
    Exit;

  grdResults.MouseToCell(X, Y, ACol, ARow);
  FLastClickedGridCol := ACol;
  if (ACol >= 0) and (ARow >= 1) and (FResult <> nil) and
     (ACol < FResult.ColumnCount) and (ARow - 1 < FResult.RowCount) then
  begin
    Sel := grdResults.Selection;
    InSelection := (ACol >= Min(Sel.Left, Sel.Right)) and (ACol <= Max(Sel.Left, Sel.Right)) and
                   (ARow >= Min(Sel.Top, Sel.Bottom)) and (ARow <= Max(Sel.Top, Sel.Bottom));
    if not InSelection then
    begin
      grdResults.Col := ACol;
      grdResults.Row := ARow;
    end;
  end;
end;

procedure TQueryResultGridFrame.pmGridPopup(Sender: TObject);
var
  HasGrid, HasRows, HasValidRow: Boolean;
begin
  HasGrid := (FResult <> nil) and FResult.HasResultSet and (FResult.ColumnCount > 0);
  HasRows := HasGrid and (FResult.RowCount > 0);
  HasValidRow := HasRows and (grdResults.Row >= 1) and (grdResults.Row - 1 < FResult.RowCount);

  miCopyCell.Enabled := HasValidRow and (grdResults.Col >= 0) and (grdResults.Col < FResult.ColumnCount);
  miCopySelection.Enabled := HasRows;
  miCopyRow.Enabled := HasValidRow;
  miCopyRowWithHeader.Enabled := HasValidRow;
  miCopyColName.Enabled := HasGrid and (((FLastClickedGridCol >= 0) and (FLastClickedGridCol < FResult.ColumnCount)) or
    ((grdResults.Col >= 0) and (grdResults.Col < FResult.ColumnCount)));
  miGridSep2.Visible := FExportEnabled;
  miExportCsv.Visible := FExportEnabled;
  miExportCsv.Enabled := FExportEnabled and CanExportCsv;
end;

procedure TQueryResultGridFrame.miCopyCellClick(Sender: TObject);
begin
  CopySelectedCell;
end;

procedure TQueryResultGridFrame.miCopySelectionClick(Sender: TObject);
begin
  CopySelectedRange;
end;

procedure TQueryResultGridFrame.miCopyRowClick(Sender: TObject);
begin
  CopyCurrentRow(False);
end;

procedure TQueryResultGridFrame.miCopyRowWithHeaderClick(Sender: TObject);
begin
  CopyCurrentRow(True);
end;

procedure TQueryResultGridFrame.miCopyColNameClick(Sender: TObject);
begin
  CopyCurrentColumnName;
end;

procedure TQueryResultGridFrame.miExportCsvClick(Sender: TObject);
begin
  ExportToCsv;
end;

function TQueryResultGridFrame.EscapeCsvField(const AValue: string): string;
begin
  if (Pos(';', AValue) > 0) or (Pos('"', AValue) > 0) or
     (Pos(#10, AValue) > 0) or (Pos(#13, AValue) > 0) then
    Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AValue;
end;

function TQueryResultGridFrame.CanExportCsv: Boolean;
begin
  Result := FExportEnabled and (FResult <> nil) and FResult.HasResultSet and (FResult.RowCount > 0);
end;

function TQueryResultGridFrame.ExportToCsv: Boolean;
const
  BUF_FLUSH_BYTES = 65536;
  UTF8_BOM: string = #$EF#$BB#$BF;
var
  FS: TFileStream;
  R, C: Integer;
  Buf, Line: string;
  Row: TQueryRow;

  procedure FlushBuf(var ABuf: string);
  begin
    if ABuf <> '' then
    begin
      FS.WriteBuffer(ABuf[1], Length(ABuf));
      ABuf := '';
    end;
  end;

begin
  Result := False;
  if not CanExportCsv then
    Exit;

  if not dlgSaveCsv.Execute then
    Exit;

  FS := TFileStream.Create(dlgSaveCsv.FileName, fmCreate);
  try
    Buf := UTF8_BOM;
    Line := '';
    for C := 0 to FResult.ColumnCount - 1 do
    begin
      if C > 0 then
        Line := Line + ';';
      Line := Line + EscapeCsvField(FResult.GetColumn(C).Name);
    end;
    Buf := Buf + Line + LineEnding;

    for R := 0 to FResult.RowCount - 1 do
    begin
      Row := FResult.GetRow(R);
      Line := '';
      for C := 0 to FResult.ColumnCount - 1 do
      begin
        if C > 0 then
          Line := Line + ';';
        if (C < Length(Row)) and (not Row[C].IsNull) then
          Line := Line + EscapeCsvField(Row[C].AsText);
      end;
      Buf := Buf + Line + LineEnding;
      if Length(Buf) >= BUF_FLUSH_BYTES then
        FlushBuf(Buf);
    end;
    FlushBuf(Buf);
    Result := True;
    if Assigned(FOnExportedCsv) then
      FOnExportedCsv(Self, dlgSaveCsv.FileName);
  finally
    FS.Free;
  end;
end;

end.
