unit Domain.SqlAliasResolver;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math;

type
  TSqlTableAlias = record
    AliasName: string;
    TableName: string;
    SchemaName: string;
  end;

  TSqlTableAliasArray = array of TSqlTableAlias;

function ExtractStatementAtOffset(const ASQL: string; const AByteOffset: Integer): string;
function ExtractSqlTableAliases(const ASQL: string): TSqlTableAliasArray;
function ResolveSqlTableAlias(
  const ASQL: string;
  const ACaretByteOffset: Integer;
  const AQualifier: string
): string;

implementation

type
  TSqlTokenKind = (
    stkWord,
    stkQuotedIdent,
    stkString,
    stkDot,
    stkComma,
    stkOpenParen,
    stkCloseParen,
    stkSemicolon,
    stkOther
  );

  TSqlToken = record
    Kind: TSqlTokenKind;
    Text: string;
    Upper: string;
    StartPos: Integer;
    EndPos: Integer;
  end;

  TSqlTokenArray = array of TSqlToken;

  TScopedTableAlias = record
    AliasName: string;
    TableName: string;
    SchemaName: string;
    Depth: Integer;
  end;

  TScopedTableAliasArray = array of TScopedTableAlias;

function IsIdentStartChar(const C: Char): Boolean; inline;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '_', '$']) or (Ord(C) >= 128);
end;

function IsIdentContChar(const C: Char): Boolean; inline;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) or (Ord(C) >= 128);
end;

function TokenizeSQL(const ASQL: string): TSqlTokenArray;
var
  I, Len, Count, StartI: Integer;
  C: Char;
  Buf: string;

  procedure PushToken(const AKind: TSqlTokenKind; const AText: string; const AStartPos, AEndPos: Integer);
  begin
    if Count >= Length(Result) then
    begin
      if Length(Result) = 0 then
        SetLength(Result, 64)
      else
        SetLength(Result, Length(Result) * 2);
    end;
    Result[Count].Kind := AKind;
    Result[Count].Text := AText;
    if AKind = stkWord then
      Result[Count].Upper := UpperCase(AText)
    else
      Result[Count].Upper := '';
    Result[Count].StartPos := AStartPos;
    Result[Count].EndPos := AEndPos;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  Len := Length(ASQL);
  I := 1;

  while I <= Len do
  begin
    C := ASQL[I];

    if C in [' ', #9, #10, #13] then
    begin
      Inc(I);
      Continue;
    end;

    { Comentário de linha -- }
    if (C = '-') and (I < Len) and (ASQL[I + 1] = '-') then
    begin
      Inc(I, 2);
      while (I <= Len) and not (ASQL[I] in [#10, #13]) do
        Inc(I);
      Continue;
    end;

    { Comentário de bloco /* ... */ }
    if (C = '/') and (I < Len) and (ASQL[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I < Len) and not ((ASQL[I] = '*') and (ASQL[I + 1] = '/')) do
        Inc(I);
      if I <= Len - 1 then
        Inc(I, 2)
      else
        I := Len + 1;
      Continue;
    end;

    { Literal string '...' }
    if C = '''' then
    begin
      StartI := I;
      Inc(I);
      while I <= Len do
      begin
        if ASQL[I] = '''' then
        begin
          if (I < Len) and (ASQL[I + 1] = '''') then
            Inc(I, 2)
          else
          begin
            Inc(I);
            Break;
          end;
        end
        else
          Inc(I);
      end;
      PushToken(stkString, '', StartI, I - 1);
      Continue;
    end;

    { Identificador com aspas duplas "..." }
    if C = '"' then
    begin
      StartI := I;
      Buf := '';
      Inc(I);
      while I <= Len do
      begin
        if ASQL[I] = '"' then
        begin
          if (I < Len) and (ASQL[I + 1] = '"') then
          begin
            Buf := Buf + '"';
            Inc(I, 2);
          end
          else
          begin
            Inc(I);
            Break;
          end;
        end
        else
        begin
          Buf := Buf + ASQL[I];
          Inc(I);
        end;
      end;
      PushToken(stkQuotedIdent, Buf, StartI, I - 1);
      Continue;
    end;

    if IsIdentStartChar(C) then
    begin
      StartI := I;
      Inc(I);
      while (I <= Len) and IsIdentContChar(ASQL[I]) do
        Inc(I);
      PushToken(stkWord, Copy(ASQL, StartI, I - StartI), StartI, I - 1);
      Continue;
    end;

    if C in ['0'..'9'] then
    begin
      StartI := I;
      Inc(I);
      while (I <= Len) and (ASQL[I] in ['0'..'9', '.']) do
        Inc(I);
      PushToken(stkOther, Copy(ASQL, StartI, I - StartI), StartI, I - 1);
      Continue;
    end;

    case C of
      '.': PushToken(stkDot, '.', I, I);
      ',': PushToken(stkComma, ',', I, I);
      '(': PushToken(stkOpenParen, '(', I, I);
      ')': PushToken(stkCloseParen, ')', I, I);
      ';': PushToken(stkSemicolon, ';', I, I);
    else
      PushToken(stkOther, C, I, I);
    end;
    Inc(I);
  end;

  SetLength(Result, Count);
end;

function IsSqlStopKeyword(const AUpperWord: string): Boolean;
const
  StopWords: array[0..53] of string = (
    'SELECT', 'FROM', 'WHERE', 'ON', 'USING', 'SET', 'VALUES',
    'ORDER', 'GROUP', 'HAVING', 'INNER', 'LEFT', 'RIGHT', 'FULL',
    'CROSS', 'NATURAL', 'OUTER', 'JOIN', 'UNION', 'INTERSECT', 'EXCEPT',
    'PLAN', 'ROWS', 'LIMIT', 'OFFSET', 'FETCH', 'FOR', 'INTO',
    'RETURNING', 'WHEN', 'THEN', 'ELSE', 'END', 'AND', 'OR',
    'NOT', 'IS', 'IN', 'BETWEEN', 'LIKE', 'SIMILAR', 'STARTING',
    'CONTAINING', 'UPDATE', 'DELETE', 'INSERT', 'MERGE', 'WITH',
    'WINDOW', 'QUALIFY', 'AS', 'DISTINCT', 'ALL', 'BY'
  );
  ExtraWords: array[0..9] of string = (
    'ASC', 'DESC', 'NULLS', 'FIRST', 'LAST', 'TO', 'SKIP', 'WAIT', 'LOCK', 'CASE'
  );
var
  I: Integer;
begin
  for I := Low(StopWords) to High(StopWords) do
    if AUpperWord = StopWords[I] then
      Exit(True);
  for I := Low(ExtraWords) to High(ExtraWords) do
    if AUpperWord = ExtraWords[I] then
      Exit(True);
  Result := False;
end;

function IsFromScalarFunction(const AUpperWord: string): Boolean;
begin
  Result := (AUpperWord = 'EXTRACT') or (AUpperWord = 'SUBSTRING') or
            (AUpperWord = 'TRIM') or (AUpperWord = 'OVERLAY') or
            (AUpperWord = 'POSITION');
end;

procedure ExtractStatementRangeAtOffset(
  const ASQL: string;
  const AByteOffset: Integer;
  out AStartOffset: Integer;
  out AEndOffset: Integer
);
var
  Tokens: TSqlTokenArray;
  EffOffset, CurStart, I: Integer;
begin
  AStartOffset := 1;
  AEndOffset := Length(ASQL);
  if ASQL = '' then
    Exit;

  EffOffset := AByteOffset;
  if EffOffset < 1 then
    EffOffset := 1;

  Tokens := TokenizeSQL(ASQL);
  CurStart := 1;
  for I := 0 to High(Tokens) do
  begin
    if Tokens[I].Kind = stkSemicolon then
    begin
      if EffOffset <= Tokens[I].StartPos then
      begin
        AStartOffset := CurStart;
        AEndOffset := Tokens[I].StartPos - 1;
        Exit;
      end;
      CurStart := Tokens[I].EndPos + 1;
    end;
  end;
  AStartOffset := CurStart;
  AEndOffset := Length(ASQL);
end;

function ExtractStatementAtOffset(const ASQL: string; const AByteOffset: Integer): string;
var
  StartOff, EndOff: Integer;
begin
  ExtractStatementRangeAtOffset(ASQL, AByteOffset, StartOff, EndOff);
  if EndOff < StartOff then
    Result := ''
  else
    Result := Copy(ASQL, StartOff, EndOff - StartOff + 1);
end;

function ExtractScopedAliases(const ASQL: string): TScopedTableAliasArray;
var
  Tokens: TSqlTokenArray;
  FromActive: array of Boolean;
  SawQueryVerb: array of Boolean;
  IgnoreFrom: array of Boolean;
  Depth, Idx, AliasCount: Integer;
  PrevWordUpper: string;

  procedure EnsureDepthCapacity(const ANeededDepth: Integer);
  var
    OldLen, K: Integer;
  begin
    if ANeededDepth < Length(FromActive) then
      Exit;
    OldLen := Length(FromActive);
    SetLength(FromActive, ANeededDepth + 8);
    SetLength(SawQueryVerb, ANeededDepth + 8);
    SetLength(IgnoreFrom, ANeededDepth + 8);
    for K := OldLen to High(FromActive) do
    begin
      FromActive[K] := False;
      SawQueryVerb[K] := False;
      IgnoreFrom[K] := False;
    end;
  end;

  procedure AddAliasEntry(const AAliasName, ATableName, ASchemaName: string; const ADepth: Integer);
  begin
    if (Trim(AAliasName) = '') or (Trim(ATableName) = '') then
      Exit;
    if AliasCount >= Length(Result) then
    begin
      if Length(Result) = 0 then
        SetLength(Result, 8)
      else
        SetLength(Result, Length(Result) * 2);
    end;
    Result[AliasCount].AliasName := AAliasName;
    Result[AliasCount].TableName := ATableName;
    Result[AliasCount].SchemaName := ASchemaName;
    Result[AliasCount].Depth := ADepth;
    Inc(AliasCount);
  end;

  procedure SkipBalancedParens(var APos: Integer);
  var
    ParDepth: Integer;
  begin
    if (APos > High(Tokens)) or (Tokens[APos].Kind <> stkOpenParen) then
      Exit;
    ParDepth := 0;
    while APos <= High(Tokens) do
    begin
      if Tokens[APos].Kind = stkOpenParen then
        Inc(ParDepth)
      else if Tokens[APos].Kind = stkCloseParen then
      begin
        Dec(ParDepth);
        if ParDepth <= 0 then
        begin
          Inc(APos);
          Exit;
        end;
      end;
      Inc(APos);
    end;
  end;

  procedure ParseTableReference(var APos: Integer; const ARequireExplicitAS: Boolean);
  var
    Part1, SchemaName, TableName, AliasName: string;
  begin
    if APos > High(Tokens) then
      Exit;

    { Subconsulta (SELECT ...) ou LATERAL (SELECT ...) deve ser percorrida pelo loop principal }
    if Tokens[APos].Kind = stkOpenParen then
      Exit;
    if (Tokens[APos].Kind = stkWord) and (Tokens[APos].Upper = 'LATERAL') and
       (APos + 1 <= High(Tokens)) and (Tokens[APos + 1].Kind = stkOpenParen) then
      Exit;

    if not ((Tokens[APos].Kind = stkQuotedIdent) or
            ((Tokens[APos].Kind = stkWord) and (not IsSqlStopKeyword(Tokens[APos].Upper)))) then
      Exit;

    Part1 := Tokens[APos].Text;
    Inc(APos);

    if (APos + 1 <= High(Tokens)) and (Tokens[APos].Kind = stkDot) and
       (Tokens[APos + 1].Kind in [stkWord, stkQuotedIdent]) then
    begin
      SchemaName := Part1;
      TableName := Tokens[APos + 1].Text;
      Inc(APos, 2);
    end
    else
    begin
      SchemaName := '';
      TableName := Part1;
    end;

    { Stored procedure selecionável ou table-valued function: FROM sp(arg1, arg2) [AS] alias }
    if (not ARequireExplicitAS) and (APos <= High(Tokens)) and (Tokens[APos].Kind = stkOpenParen) then
      SkipBalancedParens(APos);

    AliasName := '';
    if APos <= High(Tokens) then
    begin
      if (Tokens[APos].Kind = stkWord) and (Tokens[APos].Upper = 'AS') then
      begin
        Inc(APos);
        if (APos <= High(Tokens)) and
           ((Tokens[APos].Kind = stkQuotedIdent) or
            ((Tokens[APos].Kind = stkWord) and (not IsSqlStopKeyword(Tokens[APos].Upper)))) then
        begin
          AliasName := Tokens[APos].Text;
          Inc(APos);
        end;
      end
      else if not ARequireExplicitAS then
      begin
        if (Tokens[APos].Kind = stkQuotedIdent) or
           ((Tokens[APos].Kind = stkWord) and (not IsSqlStopKeyword(Tokens[APos].Upper))) then
        begin
          AliasName := Tokens[APos].Text;
          Inc(APos);
        end;
      end;
    end;

    if AliasName <> '' then
      AddAliasEntry(AliasName, TableName, SchemaName, Depth);
  end;

var
  W: string;
  K: Integer;
begin
  Result := nil;
  AliasCount := 0;
  Tokens := TokenizeSQL(ASQL);
  if Length(Tokens) = 0 then
    Exit;

  Depth := 0;
  EnsureDepthCapacity(0);
  SawQueryVerb[0] := True;
  PrevWordUpper := '';

  Idx := 0;
  while Idx <= High(Tokens) do
  begin
    case Tokens[Idx].Kind of
      stkOpenParen:
        begin
          Inc(Depth);
          EnsureDepthCapacity(Depth);
          FromActive[Depth] := False;
          SawQueryVerb[Depth] := False;
          IgnoreFrom[Depth] := IsFromScalarFunction(PrevWordUpper);
          PrevWordUpper := '';
          Inc(Idx);
          Continue;
        end;

      stkCloseParen:
        begin
          if Depth > 0 then
          begin
            FromActive[Depth] := False;
            SawQueryVerb[Depth] := False;
            IgnoreFrom[Depth] := False;
            Dec(Depth);
          end;
          PrevWordUpper := '';
          Inc(Idx);
          Continue;
        end;

      stkSemicolon:
        begin
          for K := 0 to High(FromActive) do
          begin
            FromActive[K] := False;
            SawQueryVerb[K] := (K = 0);
            IgnoreFrom[K] := False;
          end;
          Depth := 0;
          PrevWordUpper := '';
          Inc(Idx);
          Continue;
        end;

      stkComma:
        begin
          PrevWordUpper := '';
          Inc(Idx);
          if FromActive[Depth] then
          begin
            ParseTableReference(Idx, False);
            Continue;
          end;
          Continue;
        end;

      stkWord:
        begin
          W := Tokens[Idx].Upper;

          if (W = 'SELECT') or (W = 'WITH') then
          begin
            SawQueryVerb[Depth] := True;
            FromActive[Depth] := False;
            PrevWordUpper := W;
            Inc(Idx);
            Continue;
          end;

          if W = 'DELETE' then
          begin
            SawQueryVerb[Depth] := True;
            FromActive[Depth] := False;
            PrevWordUpper := W;
            Inc(Idx);
            Continue;
          end;

          if (W = 'FROM') and (not IgnoreFrom[Depth]) and ((Depth = 0) or SawQueryVerb[Depth]) then
          begin
            FromActive[Depth] := True;
            PrevWordUpper := W;
            Inc(Idx);
            ParseTableReference(Idx, False);
            Continue;
          end;

          if W = 'JOIN' then
          begin
            PrevWordUpper := W;
            Inc(Idx);
            ParseTableReference(Idx, False);
            Continue;
          end;

          if (W = 'USING') and (Idx + 1 <= High(Tokens)) and (Tokens[Idx + 1].Kind <> stkOpenParen) then
          begin
            FromActive[Depth] := True;
            PrevWordUpper := W;
            Inc(Idx);
            ParseTableReference(Idx, False);
            Continue;
          end;

          if (W = 'UPDATE') and not ((PrevWordUpper = 'ON') or (PrevWordUpper = 'FOR') or
             (PrevWordUpper = 'OR') or (PrevWordUpper = 'BEFORE') or (PrevWordUpper = 'AFTER')) then
          begin
            FromActive[Depth] := False;
            PrevWordUpper := W;
            Inc(Idx);
            ParseTableReference(Idx, False);
            Continue;
          end;

          if W = 'MERGE' then
          begin
            FromActive[Depth] := False;
            PrevWordUpper := W;
            Inc(Idx);
            if (Idx <= High(Tokens)) and (Tokens[Idx].Kind = stkWord) and (Tokens[Idx].Upper = 'INTO') then
              Inc(Idx);
            ParseTableReference(Idx, False);
            Continue;
          end;

          if W = 'INSERT' then
          begin
            FromActive[Depth] := False;
            PrevWordUpper := W;
            Inc(Idx);
            if (Idx <= High(Tokens)) and (Tokens[Idx].Kind = stkWord) and (Tokens[Idx].Upper = 'INTO') then
              Inc(Idx);
            ParseTableReference(Idx, True);
            Continue;
          end;

          if (W = 'WHERE') or (W = 'GROUP') or (W = 'HAVING') or (W = 'ORDER') or
             (W = 'UNION') or (W = 'INTERSECT') or (W = 'EXCEPT') or (W = 'LIMIT') or
             (W = 'OFFSET') or (W = 'FETCH') or (W = 'ROWS') or (W = 'PLAN') or
             (W = 'SET') or (W = 'VALUES') or (W = 'INTO') or (W = 'RETURNING') or
             (W = 'WINDOW') or (W = 'QUALIFY') or (W = 'FOR') then
          begin
            FromActive[Depth] := False;
          end;

          PrevWordUpper := W;
          Inc(Idx);
          Continue;
        end;
    else
      PrevWordUpper := '';
      Inc(Idx);
    end;
  end;

  SetLength(Result, AliasCount);
end;

function ExtractSqlTableAliases(const ASQL: string): TSqlTableAliasArray;
var
  Scoped: TScopedTableAliasArray;
  I: Integer;
begin
  Scoped := ExtractScopedAliases(ASQL);
  SetLength(Result, Length(Scoped));
  for I := 0 to High(Scoped) do
  begin
    Result[I].AliasName := Scoped[I].AliasName;
    Result[I].TableName := Scoped[I].TableName;
    Result[I].SchemaName := Scoped[I].SchemaName;
  end;
end;

function CleanQualifierName(const AQualifier: string): string;
var
  S, Seg: string;
  LastDot, Len: Integer;
  InQuotes: Boolean;
  I: Integer;
begin
  S := Trim(AQualifier);
  if S = '' then
    Exit('');

  { Se houver schema.nome, considerar apenas o último segmento fora de aspas }
  LastDot := 0;
  InQuotes := False;
  Len := Length(S);
  I := 1;
  while I <= Len do
  begin
    if S[I] = '"' then
    begin
      if InQuotes and (I < Len) and (S[I + 1] = '"') then
        Inc(I)
      else
        InQuotes := not InQuotes;
    end
    else if (not InQuotes) and (S[I] = '.') then
      LastDot := I;
    Inc(I);
  end;

  if LastDot > 0 then
    Seg := Trim(Copy(S, LastDot + 1, MaxInt))
  else
    Seg := S;

  if (Length(Seg) >= 2) and (Seg[1] = '"') and (Seg[Length(Seg)] = '"') then
    Seg := StringReplace(Copy(Seg, 2, Length(Seg) - 2), '""', '"', [rfReplaceAll]);

  Result := Trim(Seg);
end;

function FindAliasMatch(
  const AAliases: TScopedTableAliasArray;
  const AQualifier: string;
  const AOnlyDepthZero: Boolean;
  out ATableName: string
): Boolean;
var
  I: Integer;
begin
  for I := High(AAliases) downto 0 do
  begin
    if AOnlyDepthZero and (AAliases[I].Depth <> 0) then
      Continue;
    if SameText(AAliases[I].AliasName, AQualifier) then
    begin
      ATableName := AAliases[I].TableName;
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  TParenSpan = record
    OpenPos: Integer;
    ClosePos: Integer;
  end;

function ResolveSqlTableAlias(
  const ASQL: string;
  const ACaretByteOffset: Integer;
  const AQualifier: string
): string;
var
  CleanQual, StmtSQL, InnerSQL, ResolvedTable: string;
  StmtStart, StmtEnd, LocalOffset, I, J: Integer;
  Tokens: TSqlTokenArray;
  OpenStack: array of Integer;
  StackTop: Integer;
  EnclosingSpans: array of TParenSpan;
  SpanCount: Integer;
  TmpSpan: TParenSpan;
  Aliases: TScopedTableAliasArray;
begin
  CleanQual := CleanQualifierName(AQualifier);
  if CleanQual = '' then
    Exit('');
  Result := CleanQual;

  ExtractStatementRangeAtOffset(ASQL, ACaretByteOffset, StmtStart, StmtEnd);
  if StmtEnd < StmtStart then
    StmtSQL := ''
  else
    StmtSQL := Copy(ASQL, StmtStart, StmtEnd - StmtStart + 1);

  if StmtSQL <> '' then
  begin
    LocalOffset := ACaretByteOffset - StmtStart + 1;
    if LocalOffset < 1 then
      LocalOffset := 1;
    if LocalOffset > Length(StmtSQL) + 1 then
      LocalOffset := Length(StmtSQL) + 1;

    Tokens := TokenizeSQL(StmtSQL);
    OpenStack := nil;
    StackTop := 0;
    EnclosingSpans := nil;
    SpanCount := 0;

    for I := 0 to High(Tokens) do
    begin
      if Tokens[I].Kind = stkOpenParen then
      begin
        if Tokens[I].StartPos < LocalOffset then
        begin
          if StackTop >= Length(OpenStack) then
            SetLength(OpenStack, Max(8, StackTop * 2));
          OpenStack[StackTop] := Tokens[I].StartPos;
          Inc(StackTop);
        end;
      end
      else if Tokens[I].Kind = stkCloseParen then
      begin
        if StackTop > 0 then
        begin
          Dec(StackTop);
          if Tokens[I].EndPos >= LocalOffset then
          begin
            if SpanCount >= Length(EnclosingSpans) then
              SetLength(EnclosingSpans, Max(8, SpanCount * 2));
            EnclosingSpans[SpanCount].OpenPos := OpenStack[StackTop];
            EnclosingSpans[SpanCount].ClosePos := Tokens[I].StartPos;
            Inc(SpanCount);
          end;
        end;
      end;
    end;

    while StackTop > 0 do
    begin
      Dec(StackTop);
      if SpanCount >= Length(EnclosingSpans) then
        SetLength(EnclosingSpans, Max(8, SpanCount * 2));
      EnclosingSpans[SpanCount].OpenPos := OpenStack[StackTop];
      EnclosingSpans[SpanCount].ClosePos := Length(StmtSQL) + 1;
      Inc(SpanCount);
    end;

    { Ordenar do parêntese mais interno (maior OpenPos) para o mais externo }
    for I := 0 to SpanCount - 2 do
      for J := I + 1 to SpanCount - 1 do
      begin
        if EnclosingSpans[J].OpenPos > EnclosingSpans[I].OpenPos then
        begin
          TmpSpan := EnclosingSpans[I];
          EnclosingSpans[I] := EnclosingSpans[J];
          EnclosingSpans[J] := TmpSpan;
        end;
      end;

    for I := 0 to SpanCount - 1 do
    begin
      InnerSQL := Copy(
        StmtSQL,
        EnclosingSpans[I].OpenPos + 1,
        EnclosingSpans[I].ClosePos - EnclosingSpans[I].OpenPos - 1
      );
      Aliases := ExtractScopedAliases(InnerSQL);
      if FindAliasMatch(Aliases, CleanQual, True, ResolvedTable) then
        Exit(ResolvedTable);
    end;

    { Escopo da instrução atual (primeiro Depth=0, depois qualquer profundidade) }
    Aliases := ExtractScopedAliases(StmtSQL);
    if FindAliasMatch(Aliases, CleanQual, True, ResolvedTable) then
      Exit(ResolvedTable);
    if FindAliasMatch(Aliases, CleanQual, False, ResolvedTable) then
      Exit(ResolvedTable);
  end;

  { Fallback: texto completo do editor }
  Aliases := ExtractScopedAliases(ASQL);
  if FindAliasMatch(Aliases, CleanQual, False, ResolvedTable) then
    Exit(ResolvedTable);
end;

end.
