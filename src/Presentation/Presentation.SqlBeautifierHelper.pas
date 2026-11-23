unit Presentation.SqlBeautifierHelper;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SynEdit, Domain.SqlBeautifier;

function FormatSynEditSql(const ASynEdit: TSynEdit): Boolean;

implementation

function FormatSynEditSql(const ASynEdit: TSynEdit): Boolean;
var
  SourceText, FormattedText: string;
  OldCaret: TPoint;
  MaxLine, MaxCol: Integer;
begin
  Result := False;
  if (ASynEdit = nil) or ASynEdit.ReadOnly then
    Exit;

  if ASynEdit.SelAvail then
  begin
    SourceText := ASynEdit.SelText;
    if Trim(SourceText) = '' then
      Exit;

    FormattedText := TSqlBeautifier.FormatSql(SourceText);
    if FormattedText = SourceText then
      Exit;

    ASynEdit.BeginUndoBlock;
    try
      ASynEdit.SelText := FormattedText;
    finally
      ASynEdit.EndUndoBlock;
    end;
    Result := True;
    Exit;
  end;

  SourceText := ASynEdit.Text;
  if Trim(SourceText) = '' then
    Exit;

  FormattedText := TSqlBeautifier.FormatSql(SourceText);
  if FormattedText = SourceText then
    Exit;

  OldCaret := ASynEdit.CaretXY;
  ASynEdit.BeginUpdate(False);
  try
    ASynEdit.BeginUndoBlock;
    try
      ASynEdit.SelectAll;
      ASynEdit.SelText := FormattedText;
    finally
      ASynEdit.EndUndoBlock;
    end;

    MaxLine := ASynEdit.Lines.Count;
    if MaxLine < 1 then
      MaxLine := 1;
    if OldCaret.y > MaxLine then
      OldCaret.y := MaxLine
    else if OldCaret.y < 1 then
      OldCaret.y := 1;

    if (OldCaret.y - 1) < ASynEdit.Lines.Count then
      MaxCol := Length(ASynEdit.Lines[OldCaret.y - 1]) + 1
    else
      MaxCol := 1;
    if OldCaret.x > MaxCol then
      OldCaret.x := MaxCol
    else if OldCaret.x < 1 then
      OldCaret.x := 1;

    ASynEdit.CaretXY := OldCaret;
    ASynEdit.BlockBegin := OldCaret;
    ASynEdit.BlockEnd := OldCaret;
  finally
    ASynEdit.EndUpdate;
  end;
  Result := True;
end;

end.
