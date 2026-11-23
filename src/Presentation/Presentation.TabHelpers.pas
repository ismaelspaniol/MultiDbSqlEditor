unit Presentation.TabHelpers;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ComCtrls;

const
  TAB_CLOSE_SUFFIX = {$IFDEF WINDOWS}'   ×'{$ELSE}''{$ENDIF};

function StripEditorTabCloseSuffix(const ACaption: string): string;
function FormatEditorTabCaption(const ATitle: string): string;
procedure SetTabSheetTitle(const ATab: TTabSheet; const ATitle: string);

implementation

function StripEditorTabCloseSuffix(const ACaption: string): string;
begin
  Result := ACaption;
  if (TAB_CLOSE_SUFFIX <> '') and
     (Length(Result) >= Length(TAB_CLOSE_SUFFIX)) and
     (Copy(Result, Length(Result) - Length(TAB_CLOSE_SUFFIX) + 1, Length(TAB_CLOSE_SUFFIX)) = TAB_CLOSE_SUFFIX) then
    Result := Copy(Result, 1, Length(Result) - Length(TAB_CLOSE_SUFFIX));
end;

function FormatEditorTabCaption(const ATitle: string): string;
begin
  Result := StripEditorTabCloseSuffix(ATitle) + TAB_CLOSE_SUFFIX;
end;

procedure SetTabSheetTitle(const ATab: TTabSheet; const ATitle: string);
begin
  if ATab <> nil then
    ATab.Caption := FormatEditorTabCaption(ATitle);
end;

end.
