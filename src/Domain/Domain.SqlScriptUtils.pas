unit Domain.SqlScriptUtils;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Domain.DatabaseTypes;

function EscapeSqlLit(const AValue: string): string;
function NormalizeCodeText(const AStr: string; const AIgnoreWhitespace: Boolean): string;
function StartsWithAsKw(const ASource: string): Boolean;
function ExtractCommaIdentList(const ACommaText: string): TStringList;
procedure SplitSqlScriptStatements(
  const AScript: string;
  const ADbType: TDatabaseType;
  const ATarget: TStrings
);

implementation

function EscapeSqlLit(const AValue: string): string;
begin
  Result := StringReplace(Trim(AValue), '''', '''''', [rfReplaceAll]);
end;

function NormalizeCodeText(const AStr: string; const AIgnoreWhitespace: Boolean): string;
var
  S: string;
  I: Integer;
  InSpace: Boolean;
begin
  S := StringReplace(AStr, #13#10, #10, [rfReplaceAll]);
  S := StringReplace(S, #13, #10, [rfReplaceAll]);
  S := Trim(S);
  while (S <> '') and (S[Length(S)] = ';') do
    S := TrimRight(Copy(S, 1, Length(S) - 1));
  if not AIgnoreWhitespace then
    Exit(S);

  Result := '';
  InSpace := False;
  for I := 1 to Length(S) do
  begin
    if S[I] in [' ', #9, #10, #13] then
    begin
      if not InSpace then
      begin
        Result := Result + ' ';
        InSpace := True;
      end;
    end
    else
    begin
      Result := Result + S[I];
      InSpace := False;
    end;
  end;
  Result := Trim(Result);
end;

function StartsWithAsKw(const ASource: string): Boolean;
var
  Upper: string;
begin
  Upper := UpperCase(TrimLeft(ASource));
  if Copy(Upper, 1, 2) <> 'AS' then
    Exit(False);
  if Length(Upper) = 2 then
    Exit(True);
  Result := Upper[3] in [#0..' '];
end;

function ExtractCommaIdentList(const ACommaText: string): TStringList;
var
  I: Integer;
begin
  Result := TStringList.Create;
  Result.StrictDelimiter := True;
  Result.Delimiter := ',';
  Result.DelimitedText := ACommaText;
  for I := Result.Count - 1 downto 0 do
  begin
    Result[I] := Trim(Result[I]);
    if Result[I] = '' then
      Result.Delete(I);
  end;
end;

procedure SplitSqlScriptStatements(
  const AScript: string;
  const ADbType: TDatabaseType;
  const ATarget: TStrings
);
var
  I, Len, StartPos, J, MatchedTermLen: Integer;
  Term, CurStmt, DollarTag: string;
  InSingleQuote, InDoubleQuote, InLineComment, InBlockComment, HasToken: Boolean;

  function StartsWithAt(const APos: Integer; const APat: string): Boolean;
  begin
    if (APat = '') or (APos < 1) or (APos + Length(APat) - 1 > Len) then
      Exit(False);
    Result := Copy(AScript, APos, Length(APat)) = APat;
  end;

  function StripLeadingCommentsAndWS(const S: string): string;
  var
    P, L: Integer;
  begin
    P := 1;
    L := Length(S);
    while P <= L do
    begin
      while (P <= L) and (S[P] in [' ', #9, #10, #13]) do
        Inc(P);
      if (P < L) and (S[P] = '-') and (S[P + 1] = '-') then
      begin
        Inc(P, 2);
        while (P <= L) and (S[P] <> #10) do
          Inc(P);
        Continue;
      end;
      if (P < L) and (S[P] = '/') and (S[P + 1] = '*') then
      begin
        Inc(P, 2);
        while (P < L) and not ((S[P] = '*') and (S[P + 1] = '/')) do
          Inc(P);
        if P < L then
          Inc(P, 2)
        else
          P := L + 1;
        Continue;
      end;
      Break;
    end;
    Result := Trim(Copy(S, P, MaxInt));
  end;

  function TryHandleFirebirdSetTerm(const AStmt: string): Boolean;
  var
    CleanStmt, Tok0, Tok1, Tok2: string;
    P, L: Integer;

    function NextWord: string;
    var
      StartIdx: Integer;
    begin
      while (P <= L) and (CleanStmt[P] in [' ', #9, #10, #13]) do
        Inc(P);
      StartIdx := P;
      while (P <= L) and not (CleanStmt[P] in [' ', #9, #10, #13]) do
        Inc(P);
      Result := Copy(CleanStmt, StartIdx, P - StartIdx);
    end;

  begin
    Result := False;
    if ADbType <> dtFirebird then
      Exit;
    CleanStmt := StripLeadingCommentsAndWS(AStmt);
    L := Length(CleanStmt);
    if L < 8 then
      Exit;
    P := 1;
    Tok0 := NextWord;
    if not SameText(Tok0, 'SET') then
      Exit;
    Tok1 := NextWord;
    if not SameText(Tok1, 'TERM') then
      Exit;
    Tok2 := NextWord;
    if Tok2 <> '' then
      Term := Tok2;
    Result := True;
  end;

  procedure FlushStmt(const AEndIdx, AOldTermLen: Integer);
  var
    RawStmt: string;
  begin
    if AEndIdx >= StartPos then
      RawStmt := StripLeadingCommentsAndWS(Copy(AScript, StartPos, AEndIdx - StartPos + 1))
    else
      RawStmt := '';
    StartPos := AEndIdx + 1 + AOldTermLen;
    HasToken := False;
    if RawStmt = '' then
      Exit;

    if TryHandleFirebirdSetTerm(RawStmt) then
      Exit;

    ATarget.Add(RawStmt);
  end;

begin
  if ATarget = nil then
    Exit;
  ATarget.Clear;

  Len := Length(AScript);
  if Len = 0 then
    Exit;

  Term := ';';
  StartPos := 1;
  I := 1;
  InSingleQuote := False;
  InDoubleQuote := False;
  InLineComment := False;
  InBlockComment := False;
  DollarTag := '';
  HasToken := False;

  while I <= Len do
  begin
    if InLineComment then
    begin
      if AScript[I] = #10 then
        InLineComment := False;
      Inc(I);
      Continue;
    end;

    if InBlockComment then
    begin
      if (I < Len) and (AScript[I] = '*') and (AScript[I + 1] = '/') then
      begin
        InBlockComment := False;
        Inc(I, 2);
      end
      else
        Inc(I);
      Continue;
    end;

    if DollarTag <> '' then
    begin
      if StartsWithAt(I, DollarTag) then
      begin
        Inc(I, Length(DollarTag));
        DollarTag := '';
      end
      else
        Inc(I);
      Continue;
    end;

    if InSingleQuote then
    begin
      if AScript[I] = '''' then
      begin
        if (I < Len) and (AScript[I + 1] = '''') then
          Inc(I, 2)
        else
        begin
          InSingleQuote := False;
          Inc(I);
        end;
      end
      else
        Inc(I);
      Continue;
    end;

    if InDoubleQuote then
    begin
      if AScript[I] = '"' then
      begin
        if (I < Len) and (AScript[I + 1] = '"') then
          Inc(I, 2)
        else
        begin
          InDoubleQuote := False;
          Inc(I);
        end;
      end
      else
        Inc(I);
      Continue;
    end;

    { Comentários }
    if (I < Len) and (AScript[I] = '-') and (AScript[I + 1] = '-') then
    begin
      InLineComment := True;
      Inc(I, 2);
      Continue;
    end;
    if (I < Len) and (AScript[I] = '/') and (AScript[I + 1] = '*') then
    begin
      InBlockComment := True;
      Inc(I, 2);
      Continue;
    end;

    { Strings e identificadores }
    if AScript[I] = '''' then
    begin
      HasToken := True;
      InSingleQuote := True;
      Inc(I);
      Continue;
    end;
    if AScript[I] = '"' then
    begin
      HasToken := True;
      InDoubleQuote := True;
      Inc(I);
      Continue;
    end;

    { Dollar-quoting do PostgreSQL: $$...$$ ou $tag$...$tag$ }
    if (ADbType = dtPostgreSQL) and (AScript[I] = '$') then
    begin
      J := I + 1;
      while (J <= Len) and (AScript[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(J);
      if (J <= Len) and (AScript[J] = '$') then
      begin
        DollarTag := Copy(AScript, I, J - I + 1);
        HasToken := True;
        I := J + 1;
        Continue;
      end;
    end;

    { Checa diretiva "SET TERM <new> ;" ou terminador atual }
    if StartsWithAt(I, Term) then
    begin
      MatchedTermLen := Length(Term);
      if HasToken then
        FlushStmt(I - 1, MatchedTermLen)
      else
        StartPos := I + MatchedTermLen;
      Inc(I, MatchedTermLen);
      Continue;
    end;

    if not (AScript[I] in [' ', #9, #10, #13]) then
      HasToken := True;
    Inc(I);
  end;

  if StartPos <= Len then
  begin
    CurStmt := Trim(Copy(AScript, StartPos, Len - StartPos + 1));
    if (CurStmt <> '') and HasToken then
    begin
      if not TryHandleFirebirdSetTerm(CurStmt) then
        ATarget.Add(CurStmt);
    end;
  end;
end;

end.
