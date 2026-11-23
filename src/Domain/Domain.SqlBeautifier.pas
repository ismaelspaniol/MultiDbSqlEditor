unit Domain.SqlBeautifier;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TSqlBeautifier = class
  public
    class function FormatSql(const ASql: string; const AIndentSize: Integer = 2): string;
  end;

implementation

type
  TSqlTokenKind = (
    stkWord,
    stkString,
    stkQuotedIdent,
    stkLineComment,
    stkBlockComment,
    stkLParen,
    stkRParen,
    stkComma,
    stkSemicolon,
    stkDot,
    stkOperator,
    stkColon
  );

  TSqlToken = record
    Kind: TSqlTokenKind;
    Text: string;
    Upper: string;
    HadNewlineBefore: Boolean;
  end;

  TSqlTokenArray = array of TSqlToken;

  TClauseKind = (
    clNone,
    clWith,
    clSelect,
    clFrom,
    clJoin,
    clWhere,
    clGroupBy,
    clHaving,
    clOrderBy,
    clUpdateSet,
    clInsert,
    clValues,
    clOther
  );

  PBlockState = ^TBlockState;
  TBlockState = record
    BlockIndent: Integer;
    Clause: TClauseKind;
    InBetween: Boolean;
    IsSubqueryParen: Boolean;
    CaseDepth: Integer;
  end;

const
  SQL_KEYWORDS: array[0..218] of string = (
    'SELECT', 'DISTINCT', 'FIRST', 'SKIP', 'TOP', 'ALL',
    'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IN', 'EXISTS', 'BETWEEN',
    'LIKE', 'ILIKE', 'SIMILAR', 'TO', 'CONTAINING', 'STARTING', 'WITH',
    'IS', 'NULL', 'TRUE', 'FALSE', 'UNKNOWN',
    'INNER', 'LEFT', 'RIGHT', 'FULL', 'OUTER', 'CROSS', 'NATURAL', 'JOIN', 'ON', 'USING',
    'GROUP', 'BY', 'HAVING', 'ORDER', 'ASC', 'DESC', 'NULLS', 'LAST',
    'ROWS', 'FETCH', 'NEXT', 'ONLY', 'OFFSET', 'LIMIT', 'FOR',
    'UNION', 'INTERSECT', 'EXCEPT', 'MINUS',
    'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'MERGE', 'MATCHED', 'RETURNING',
    'AS', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'CAST',
    'CREATE', 'ALTER', 'DROP', 'RECREATE', 'REPLACE', 'TABLE', 'VIEW', 'INDEX',
    'UNIQUE', 'TRIGGER', 'PROCEDURE', 'FUNCTION', 'GENERATOR', 'SEQUENCE', 'DOMAIN',
    'EXCEPTION', 'ROLE', 'USER', 'GRANT', 'REVOKE', 'COMMIT', 'ROLLBACK',
    'SAVEPOINT', 'WORK', 'TRANSACTION',
    'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'CHECK', 'CONSTRAINT', 'DEFAULT',
    'COMPUTED', 'GENERATED', 'ALWAYS', 'IDENTITY',
    'ACTIVE', 'INACTIVE', 'BEFORE', 'AFTER', 'POSITION', 'EXECUTE', 'STATEMENT',
    'BLOCK', 'BEGIN', 'DECLARE', 'VARIABLE', 'RETURNS', 'SUSPEND', 'DO', 'WHILE',
    'IF', 'ELSIF', 'LEAVE', 'BREAK', 'EXIT', 'ANY', 'SOME', 'SQLCODE', 'GDSCODE',
    'OVER', 'PARTITION', 'RANGE', 'UNBOUNDED', 'PRECEDING', 'FOLLOWING', 'CURRENT', 'ROW',
    'RECURSIVE', 'PLAN', 'ESCAPE', 'COLLATE', 'CHARACTER',
    'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE', 'NULLIF', 'IIF', 'DECODE',
    'UPPER', 'LOWER', 'TRIM', 'LTRIM', 'RTRIM', 'SUBSTRING', 'CHAR_LENGTH',
    'CHARACTER_LENGTH', 'OCTET_LENGTH', 'LPAD', 'RPAD', 'REVERSE', 'ABS', 'ROUND',
    'TRUNC', 'FLOOR', 'CEIL', 'CEILING', 'MOD', 'POWER', 'SQRT', 'EXP', 'LN', 'LOG',
    'EXTRACT', 'DATEADD', 'DATEDIFF', 'CURRENT_DATE', 'CURRENT_TIME',
    'CURRENT_TIMESTAMP', 'LOCALTIME', 'LOCALTIMESTAMP', 'GEN_ID', 'LIST',
    'ROW_NUMBER', 'RANK', 'DENSE_RANK', 'LAG', 'LEAD', 'FIRST_VALUE', 'LAST_VALUE',
    'STRING_AGG',
    'INTEGER', 'INT', 'SMALLINT', 'BIGINT', 'INT128', 'NUMERIC', 'DECIMAL',
    'FLOAT', 'DOUBLE', 'PRECISION', 'REAL', 'VARCHAR', 'CHAR', 'VARYING',
    'NCHAR', 'NVARCHAR', 'BLOB', 'SUB_TYPE', 'CLOB', 'DATE', 'TIME', 'TIMESTAMP',
    'BOOLEAN', 'DECFLOAT'
  );

  SPACE_BEFORE_LPAREN_KEYWORDS: array[0..25] of string = (
    'IN', 'EXISTS', 'NOT', 'AND', 'OR', 'ON', 'WHERE', 'HAVING', 'VALUES',
    'AS', 'USING', 'OVER', 'SET', 'SELECT', 'FROM', 'JOIN', 'CASE', 'WHEN',
    'THEN', 'ELSE', 'RETURN', 'UNION', 'INTERSECT', 'EXCEPT', 'CHECK', 'WITH'
  );

function IsInArray(const AUpper: string; const AArr: array of string): Boolean;
var
  I: Integer;
begin
  for I := Low(AArr) to High(AArr) do
    if AUpper = AArr[I] then
      Exit(True);
  Result := False;
end;

function IsSqlKeyword(const AUpper: string): Boolean;
begin
  Result := IsInArray(AUpper, SQL_KEYWORDS);
end;

function NeedsSpaceBeforeLParen(const AUpper: string): Boolean;
begin
  Result := IsInArray(AUpper, SPACE_BEFORE_LPAREN_KEYWORDS);
end;

function IsWordStartChar(const C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#']);
end;

function IsWordChar(const C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#']);
end;

function Tokenize(const ASql: string): TSqlTokenArray;
var
  Len, I, StartIdx, Count: Integer;
  HadNL: Boolean;
  Tag, CloseTag: string;

  procedure AddToken(const AKind: TSqlTokenKind; const AText: string);
  begin
    if Count = Length(Result) then
      SetLength(Result, Length(Result) * 2 + 32);
    Result[Count].Kind := AKind;
    Result[Count].Text := AText;
    if AKind = stkWord then
      Result[Count].Upper := UpperCase(AText)
    else
      Result[Count].Upper := '';
    Result[Count].HadNewlineBefore := HadNL;
    Inc(Count);
    HadNL := False;
  end;

begin
  Result := nil;
  Count := 0;
  Len := Length(ASql);
  I := 1;
  HadNL := False;

  while I <= Len do
  begin
    { Whitespace }
    if ASql[I] in [' ', #9, #13, #10] then
    begin
      if ASql[I] in [#13, #10] then
        HadNL := True;
      Inc(I);
      Continue;
    end;

    { Line comment -- }
    if (ASql[I] = '-') and (I < Len) and (ASql[I + 1] = '-') then
    begin
      StartIdx := I;
      Inc(I, 2);
      while (I <= Len) and not (ASql[I] in [#13, #10]) do
        Inc(I);
      AddToken(stkLineComment, Copy(ASql, StartIdx, I - StartIdx));
      Continue;
    end;

    { Block comment /* ... */ }
    if (ASql[I] = '/') and (I < Len) and (ASql[I + 1] = '*') then
    begin
      StartIdx := I;
      Inc(I, 2);
      while (I < Len) and not ((ASql[I] = '*') and (ASql[I + 1] = '/')) do
        Inc(I);
      if I < Len then
        Inc(I, 2)
      else
        I := Len + 1;
      AddToken(stkBlockComment, Copy(ASql, StartIdx, I - StartIdx));
      Continue;
    end;

    { Single-quoted string '...' }
    if ASql[I] = '''' then
    begin
      StartIdx := I;
      Inc(I);
      while I <= Len do
      begin
        if ASql[I] = '''' then
        begin
          if (I < Len) and (ASql[I + 1] = '''') then
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
      AddToken(stkString, Copy(ASql, StartIdx, I - StartIdx));
      Continue;
    end;

    { PostgreSQL dollar-quoted string $tag$...$tag$ }
    if ASql[I] = '$' then
    begin
      StartIdx := I;
      Inc(I);
      while (I <= Len) and (ASql[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(I);
      if (I <= Len) and (ASql[I] = '$') then
      begin
        Inc(I);
        Tag := Copy(ASql, StartIdx, I - StartIdx);
        CloseTag := Tag;
        while I <= Len do
        begin
          if (ASql[I] = '$') and (Copy(ASql, I, Length(CloseTag)) = CloseTag) then
          begin
            Inc(I, Length(CloseTag));
            Break;
          end;
          Inc(I);
        end;
        AddToken(stkString, Copy(ASql, StartIdx, I - StartIdx));
        Continue;
      end
      else
      begin
        I := StartIdx;
      end;
    end;

    { Double-quoted identifier "..." }
    if ASql[I] = '"' then
    begin
      StartIdx := I;
      Inc(I);
      while I <= Len do
      begin
        if ASql[I] = '"' then
        begin
          if (I < Len) and (ASql[I + 1] = '"') then
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
      AddToken(stkQuotedIdent, Copy(ASql, StartIdx, I - StartIdx));
      Continue;
    end;

    { Punctuation }
    case ASql[I] of
      '(':
        begin
          AddToken(stkLParen, '(');
          Inc(I);
          Continue;
        end;
      ')':
        begin
          AddToken(stkRParen, ')');
          Inc(I);
          Continue;
        end;
      ',':
        begin
          AddToken(stkComma, ',');
          Inc(I);
          Continue;
        end;
      ';':
        begin
          AddToken(stkSemicolon, ';');
          Inc(I);
          Continue;
        end;
      '.':
        begin
          if (I < Len) and (ASql[I + 1] = '.') then
          begin
            AddToken(stkOperator, '..');
            Inc(I, 2);
          end
          else
          begin
            AddToken(stkDot, '.');
            Inc(I);
          end;
          Continue;
        end;
      ':':
        begin
          if (I < Len) and (ASql[I + 1] = ':') then
          begin
            AddToken(stkOperator, '::');
            Inc(I, 2);
          end
          else if (I < Len) and (ASql[I + 1] = '=') then
          begin
            AddToken(stkOperator, ':=');
            Inc(I, 2);
          end
          else
          begin
            AddToken(stkColon, ':');
            Inc(I);
          end;
          Continue;
        end;
    end;

    { Multi-char operators }
    if (I < Len) and (
         ((ASql[I] = '<') and (ASql[I + 1] in ['>', '='])) or
         ((ASql[I] = '>') and (ASql[I + 1] = '=')) or
         ((ASql[I] = '!') and (ASql[I + 1] = '=')) or
         ((ASql[I] = '|') and (ASql[I + 1] = '|')) or
         ((ASql[I] = '=') and (ASql[I + 1] = '>'))
       ) then
    begin
      AddToken(stkOperator, Copy(ASql, I, 2));
      Inc(I, 2);
      Continue;
    end;

    { Single-char operators }
    if ASql[I] in ['=', '<', '>', '+', '-', '*', '/', '[', ']', '@', '~', '&', '|', '^', '%'] then
    begin
      AddToken(stkOperator, ASql[I]);
      Inc(I);
      Continue;
    end;

    { Word / Identifier / Keyword / Number }
    if IsWordStartChar(ASql[I]) then
    begin
      StartIdx := I;
      Inc(I);
      while (I <= Len) and IsWordChar(ASql[I]) do
        Inc(I);
      AddToken(stkWord, Copy(ASql, StartIdx, I - StartIdx));
      Continue;
    end;

    { Fallback unknown char }
    AddToken(stkOperator, ASql[I]);
    Inc(I);
  end;

  SetLength(Result, Count);
end;

class function TSqlBeautifier.FormatSql(const ASql: string; const AIndentSize: Integer): string;
var
  Tokens: TSqlTokenArray;
  SB: TStringBuilder;
  Stack: array of TBlockState;
  StackLen, I, TokenCount: Integer;
  AtLineStart, NeedSpace, PrevWasDot, PrevWasColon: Boolean;
  PrevTokKind: TSqlTokenKind;
  PrevTokUpper, PrevTokText: string;

  function CurrentState: PBlockState; inline;
  begin
    Result := @Stack[StackLen - 1];
  end;

  procedure PushState(const ABlockIndent: Integer; const AClause: TClauseKind; const AIsSubqueryParen: Boolean);
  begin
    if StackLen = Length(Stack) then
      SetLength(Stack, Length(Stack) + 16);
    Stack[StackLen].BlockIndent := ABlockIndent;
    Stack[StackLen].Clause := AClause;
    Stack[StackLen].InBetween := False;
    Stack[StackLen].IsSubqueryParen := AIsSubqueryParen;
    Stack[StackLen].CaseDepth := 0;
    Inc(StackLen);
  end;

  procedure PopState;
  begin
    if StackLen > 1 then
      Dec(StackLen);
  end;

  function IndentStr(const ALevel: Integer): string;
  begin
    if ALevel <= 0 then
      Result := ''
    else
      Result := StringOfChar(' ', ALevel * AIndentSize);
  end;

  procedure EmitNewLine(const AIndentLevel: Integer);
  begin
    if (SB.Length > 0) then
      SB.Append(#13#10);
    if AIndentLevel > 0 then
      SB.Append(IndentStr(AIndentLevel));
    AtLineStart := True;
    NeedSpace := False;
  end;

  procedure EmitBlankLine;
  begin
    if SB.Length > 0 then
    begin
      SB.Append(#13#10#13#10);
      AtLineStart := True;
      NeedSpace := False;
    end;
  end;

  procedure EmitText(const AText: string);
  begin
    if NeedSpace and (not AtLineStart) then
      SB.Append(' ');
    SB.Append(AText);
    AtLineStart := False;
    NeedSpace := True;
  end;

  function NextToken(const AOffset: Integer = 1): TSqlToken;
  var
    Idx: Integer;
  begin
    Idx := I + AOffset;
    while (Idx < TokenCount) and (Tokens[Idx].Kind in [stkLineComment, stkBlockComment]) do
      Inc(Idx);
    if (Idx >= 0) and (Idx < TokenCount) then
      Result := Tokens[Idx]
    else
    begin
      Result.Kind := stkSemicolon;
      Result.Text := '';
      Result.Upper := '';
      Result.HadNewlineBefore := False;
    end;
  end;

  function IsUnaryOperator(const ATokText: string): Boolean;
  begin
    if (ATokText <> '-') and (ATokText <> '+') then
      Exit(False);
    if I = 0 then
      Exit(True);
    Result := (PrevTokKind in [stkLParen, stkComma, stkOperator, stkColon]) or
              ((PrevTokKind = stkWord) and IsInArray(PrevTokUpper, [
                'SELECT', 'WHERE', 'AND', 'OR', 'NOT', 'CASE', 'WHEN', 'THEN', 'ELSE',
                'IN', 'BETWEEN', 'LIKE', 'ILIKE', 'ON', 'SET', 'VALUES', 'RETURN', 'HAVING'
              ]));
  end;

  function IsJoinModifier(const AUpper: string): Boolean;
  begin
    Result := (AUpper = 'INNER') or (AUpper = 'LEFT') or (AUpper = 'RIGHT') or
              (AUpper = 'FULL') or (AUpper = 'CROSS') or (AUpper = 'NATURAL');
  end;

  function IsClauseStartWord(const AUpper: string; const ANextUpper: string): Boolean;
  begin
    Result := (AUpper = 'SELECT') or (AUpper = 'FROM') or (AUpper = 'WHERE') or
              (AUpper = 'HAVING') or (AUpper = 'VALUES') or (AUpper = 'RETURNING') or
              (AUpper = 'UNION') or (AUpper = 'INTERSECT') or (AUpper = 'EXCEPT') or
              (AUpper = 'MINUS') or (AUpper = 'ROWS') or (AUpper = 'FETCH') or
              (AUpper = 'OFFSET') or (AUpper = 'LIMIT') or (AUpper = 'JOIN') or
              (AUpper = 'PLAN') or
              ((AUpper = 'GROUP') and (ANextUpper = 'BY')) or
              ((AUpper = 'ORDER') and (ANextUpper = 'BY')) or
              (IsJoinModifier(AUpper) and ((ANextUpper = 'JOIN') or (ANextUpper = 'OUTER')));
  end;

  function FormatWordText(const ATok: TSqlToken): string;
  begin
    if (not PrevWasDot) and (not PrevWasColon) and IsSqlKeyword(ATok.Upper) then
      Result := ATok.Upper
    else
      Result := ATok.Text;
  end;

var
  Tok, NextTok: TSqlToken;
  WordOut: string;
  CurIndent, TargetIndent: Integer;
begin
  if Trim(ASql) = '' then
    Exit(ASql);

  Tokens := Tokenize(ASql);
  TokenCount := Length(Tokens);
  if TokenCount = 0 then
    Exit(ASql);

  SB := TStringBuilder.Create;
  try
    StackLen := 0;
    PushState(0, clNone, False);
    AtLineStart := True;
    NeedSpace := False;
    PrevWasDot := False;
    PrevWasColon := False;
    PrevTokKind := stkSemicolon;
    PrevTokUpper := '';
    PrevTokText := '';

    I := 0;
    while I < TokenCount do
    begin
      Tok := Tokens[I];
      NextTok := NextToken(1);

      { Comments }
      if Tok.Kind = stkLineComment then
      begin
        if Tok.HadNewlineBefore and (not AtLineStart) then
          EmitNewLine(CurrentState^.BlockIndent + Ord(CurrentState^.Clause in [clSelect, clWhere, clUpdateSet, clHaving]) + CurrentState^.CaseDepth);
        EmitText(Tok.Text);
        EmitNewLine(CurrentState^.BlockIndent + Ord(CurrentState^.Clause in [clSelect, clWhere, clUpdateSet, clHaving]) + CurrentState^.CaseDepth);
        Inc(I);
        Continue;
      end;

      if Tok.Kind = stkBlockComment then
      begin
        if Tok.HadNewlineBefore and (not AtLineStart) then
          EmitNewLine(CurrentState^.BlockIndent);
        EmitText(Tok.Text);
        if NextTok.HadNewlineBefore then
          EmitNewLine(CurrentState^.BlockIndent);
        Inc(I);
        Continue;
      end;

      { Semicolon }
      if Tok.Kind = stkSemicolon then
      begin
        NeedSpace := False;
        EmitText(';');
        CurrentState^.Clause := clNone;
        CurrentState^.InBetween := False;
        if I < TokenCount - 1 then
          EmitBlankLine;
        PrevWasDot := False;
        PrevWasColon := False;
        PrevTokKind := stkSemicolon;
        PrevTokUpper := '';
        PrevTokText := ';';
        Inc(I);
        Continue;
      end;

      { Dot }
      if Tok.Kind = stkDot then
      begin
        NeedSpace := False;
        EmitText('.');
        NeedSpace := False;
        PrevWasDot := True;
        PrevWasColon := False;
        PrevTokKind := stkDot;
        PrevTokUpper := '';
        PrevTokText := '.';
        Inc(I);
        Continue;
      end;

      { Colon (parameter prefix :param) }
      if Tok.Kind = stkColon then
      begin
        EmitText(':');
        NeedSpace := False;
        PrevWasDot := False;
        PrevWasColon := True;
        PrevTokKind := stkColon;
        PrevTokUpper := '';
        PrevTokText := ':';
        Inc(I);
        Continue;
      end;

      { Left Paren }
      if Tok.Kind = stkLParen then
      begin
        if (PrevTokKind = stkWord) and (not NeedsSpaceBeforeLParen(PrevTokUpper)) and (not PrevWasDot) then
          NeedSpace := False;
        EmitText('(');
        NeedSpace := False;

        if (NextTok.Kind = stkWord) and ((NextTok.Upper = 'SELECT') or (NextTok.Upper = 'WITH')) then
        begin
          PushState(CurrentState^.BlockIndent + 1, clNone, True);
          EmitNewLine(CurrentState^.BlockIndent);
        end
        else
        begin
          PushState(CurrentState^.BlockIndent, clNone, False);
        end;

        PrevWasDot := False;
        PrevWasColon := False;
        PrevTokKind := stkLParen;
        PrevTokUpper := '';
        PrevTokText := '(';
        Inc(I);
        Continue;
      end;

      { Right Paren }
      if Tok.Kind = stkRParen then
      begin
        if CurrentState^.IsSubqueryParen then
        begin
          PopState;
          if not AtLineStart then
            EmitNewLine(CurrentState^.BlockIndent);
        end
        else
          PopState;

        NeedSpace := False;
        EmitText(')');
        PrevWasDot := False;
        PrevWasColon := False;
        PrevTokKind := stkRParen;
        PrevTokUpper := '';
        PrevTokText := ')';
        Inc(I);
        Continue;
      end;

      { Comma }
      if Tok.Kind = stkComma then
      begin
        NeedSpace := False;
        EmitText(',');
        if (CurrentState^.CaseDepth = 0) and
           ((CurrentState^.Clause in [clSelect, clUpdateSet]) or
            ((CurrentState^.Clause = clWith) and (PrevTokKind = stkRParen))) then
        begin
          if CurrentState^.Clause = clWith then
            EmitNewLine(CurrentState^.BlockIndent)
          else
            EmitNewLine(CurrentState^.BlockIndent + 1);
        end;
        PrevWasDot := False;
        PrevWasColon := False;
        PrevTokKind := stkComma;
        PrevTokUpper := '';
        PrevTokText := ',';
        Inc(I);
        Continue;
      end;

      { Operators }
      if Tok.Kind = stkOperator then
      begin
        if (Tok.Text = '::') then
        begin
          NeedSpace := False;
          EmitText('::');
          NeedSpace := False;
        end
        else if (Tok.Text = '*') and ((PrevTokKind = stkDot) or (PrevTokKind = stkLParen)) then
        begin
          if PrevTokKind = stkLParen then
            NeedSpace := False;
          EmitText('*');
        end
        else if IsUnaryOperator(Tok.Text) then
        begin
          EmitText(Tok.Text);
          NeedSpace := False;
        end
        else
        begin
          EmitText(Tok.Text);
        end;
        PrevWasDot := False;
        PrevWasColon := False;
        PrevTokKind := stkOperator;
        PrevTokUpper := '';
        PrevTokText := Tok.Text;
        Inc(I);
        Continue;
      end;

      { Words / Keywords }
      if Tok.Kind = stkWord then
      begin
        WordOut := FormatWordText(Tok);
        CurIndent := CurrentState^.BlockIndent;

        if (not PrevWasDot) and (not PrevWasColon) then
        begin
          { CASE expression }
          if Tok.Upper = 'CASE' then
          begin
            EmitText('CASE');
            Inc(CurrentState^.CaseDepth);
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'CASE';
            PrevTokText := 'CASE';
            Inc(I);
            Continue;
          end;

          if (Tok.Upper = 'WHEN') and (CurrentState^.CaseDepth > 0) then
          begin
            TargetIndent := CurIndent + Ord(CurrentState^.Clause in [clSelect, clWhere, clHaving, clUpdateSet]) + CurrentState^.CaseDepth;
            EmitNewLine(TargetIndent);
            EmitText('WHEN');
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'WHEN';
            PrevTokText := 'WHEN';
            Inc(I);
            Continue;
          end;

          if (Tok.Upper = 'ELSE') and (CurrentState^.CaseDepth > 0) then
          begin
            TargetIndent := CurIndent + Ord(CurrentState^.Clause in [clSelect, clWhere, clHaving, clUpdateSet]) + CurrentState^.CaseDepth;
            EmitNewLine(TargetIndent);
            EmitText('ELSE');
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'ELSE';
            PrevTokText := 'ELSE';
            Inc(I);
            Continue;
          end;

          if (Tok.Upper = 'END') and (CurrentState^.CaseDepth > 0) then
          begin
            Dec(CurrentState^.CaseDepth);
            TargetIndent := CurIndent + Ord(CurrentState^.Clause in [clSelect, clWhere, clHaving, clUpdateSet]) + CurrentState^.CaseDepth;
            EmitNewLine(TargetIndent);
            EmitText('END');
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'END';
            PrevTokText := 'END';
            Inc(I);
            Continue;
          end;

          { WITH }
          if (Tok.Upper = 'WITH') and (CurrentState^.Clause = clNone) then
          begin
            if not AtLineStart then
              EmitNewLine(CurIndent);
            CurrentState^.Clause := clWith;
            EmitText('WITH');
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'WITH';
            PrevTokText := 'WITH';
            Inc(I);
            Continue;
          end;

          { SELECT }
          if Tok.Upper = 'SELECT' then
          begin
            if not AtLineStart then
              EmitNewLine(CurIndent);
            CurrentState^.Clause := clSelect;
            CurrentState^.InBetween := False;
            EmitText('SELECT');
            { Keep DISTINCT / FIRST n / SKIP n / TOP n on SELECT line; otherwise break first column to new line }
            if (NextTok.Kind <> stkSemicolon) and
               not ((NextTok.Kind = stkWord) and ((NextTok.Upper = 'DISTINCT') or (NextTok.Upper = 'ALL') or
                    (NextTok.Upper = 'FIRST') or (NextTok.Upper = 'SKIP') or (NextTok.Upper = 'TOP'))) then
              EmitNewLine(CurIndent + 1);
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'SELECT';
            PrevTokText := 'SELECT';
            Inc(I);
            Continue;
          end;

          { After DISTINCT / FIRST n / SKIP n / TOP n inside SELECT, break before first column }
          if (CurrentState^.Clause = clSelect) and
             ((Tok.Upper = 'DISTINCT') or (Tok.Upper = 'ALL')) and
             (PrevTokUpper = 'SELECT') then
          begin
            EmitText(WordOut);
            if not ((NextTok.Kind = stkWord) and ((NextTok.Upper = 'FIRST') or (NextTok.Upper = 'SKIP') or (NextTok.Upper = 'TOP'))) then
              EmitNewLine(CurIndent + 1);
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := Tok.Upper;
            PrevTokText := WordOut;
            Inc(I);
            Continue;
          end;

          { UPDATE ... SET }
          if (Tok.Upper = 'UPDATE') and (CurrentState^.Clause = clNone) then
          begin
            if not AtLineStart then
              EmitNewLine(CurIndent);
            CurrentState^.Clause := clOther;
            EmitText('UPDATE');
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'UPDATE';
            PrevTokText := 'UPDATE';
            Inc(I);
            Continue;
          end;

          if (Tok.Upper = 'SET') and (CurrentState^.Clause in [clOther, clNone]) then
          begin
            if not AtLineStart then
              EmitNewLine(CurIndent);
            CurrentState^.Clause := clUpdateSet;
            EmitText('SET');
            EmitNewLine(CurIndent + 1);
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := 'SET';
            PrevTokText := 'SET';
            Inc(I);
            Continue;
          end;

          { DELETE / INSERT / MERGE }
          if (Tok.Upper = 'DELETE') or (Tok.Upper = 'INSERT') or (Tok.Upper = 'MERGE') then
          begin
            if not AtLineStart then
              EmitNewLine(CurIndent);
            if Tok.Upper = 'INSERT' then
              CurrentState^.Clause := clInsert
            else
              CurrentState^.Clause := clOther;
            EmitText(WordOut);
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := Tok.Upper;
            PrevTokText := WordOut;
            Inc(I);
            Continue;
          end;

          { Clause keywords: FROM, WHERE, GROUP BY, HAVING, ORDER BY, JOIN, UNION, etc. }
          if IsClauseStartWord(Tok.Upper, NextTok.Upper) then
          begin
            { Note: avoid breaking on 'FROM' inside EXTRACT(YEAR FROM x) or SUBSTRING(s FROM 1 FOR 2) }
            if (Tok.Upper = 'FROM') and (StackLen > 1) and (not CurrentState^.IsSubqueryParen) then
            begin
              EmitText('FROM');
            end
            else if (Tok.Upper = 'FOR') and (StackLen > 1) and (not CurrentState^.IsSubqueryParen) then
            begin
              EmitText('FOR');
            end
            else if (Tok.Upper = 'JOIN') and IsJoinModifier(PrevTokUpper) then
            begin
              EmitText('JOIN');
              CurrentState^.Clause := clJoin;
            end
            else if (Tok.Upper = 'OUTER') and IsJoinModifier(PrevTokUpper) then
            begin
              EmitText('OUTER');
            end
            else
            begin
              if not AtLineStart then
                EmitNewLine(CurIndent);
              CurrentState^.InBetween := False;
              if Tok.Upper = 'FROM' then
                CurrentState^.Clause := clFrom
              else if (Tok.Upper = 'JOIN') or IsJoinModifier(Tok.Upper) then
                CurrentState^.Clause := clJoin
              else if Tok.Upper = 'WHERE' then
                CurrentState^.Clause := clWhere
              else if Tok.Upper = 'HAVING' then
                CurrentState^.Clause := clHaving
              else if Tok.Upper = 'GROUP' then
                CurrentState^.Clause := clGroupBy
              else if Tok.Upper = 'ORDER' then
                CurrentState^.Clause := clOrderBy
              else if Tok.Upper = 'VALUES' then
                CurrentState^.Clause := clValues
              else
                CurrentState^.Clause := clOther;

              EmitText(WordOut);
            end;

            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := Tok.Upper;
            PrevTokText := WordOut;
            Inc(I);
            Continue;
          end;

          { BETWEEN tracking }
          if Tok.Upper = 'BETWEEN' then
            CurrentState^.InBetween := True;

          { AND / OR in WHERE / HAVING / JOIN ON }
          if ((Tok.Upper = 'AND') or (Tok.Upper = 'OR')) and
             (CurrentState^.Clause in [clWhere, clHaving, clJoin]) and
             (CurrentState^.CaseDepth = 0) then
          begin
            if (Tok.Upper = 'AND') and CurrentState^.InBetween then
            begin
              CurrentState^.InBetween := False;
              EmitText('AND');
            end
            else
            begin
              EmitNewLine(CurIndent + 1);
              EmitText(Tok.Upper);
            end;
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := Tok.Upper;
            PrevTokText := Tok.Upper;
            Inc(I);
            Continue;
          end;

          { Break after FIRST N / SKIP N / TOP N in SELECT }
          if (CurrentState^.Clause = clSelect) and
             ((PrevTokUpper = 'FIRST') or (PrevTokUpper = 'SKIP') or (PrevTokUpper = 'TOP')) then
          begin
            EmitText(WordOut);
            if not ((NextTok.Kind = stkWord) and ((NextTok.Upper = 'SKIP') or (NextTok.Upper = 'DISTINCT'))) then
              EmitNewLine(CurIndent + 1);
            PrevWasDot := False;
            PrevWasColon := False;
            PrevTokKind := stkWord;
            PrevTokUpper := Tok.Upper;
            PrevTokText := WordOut;
            Inc(I);
            Continue;
          end;
        end;

        EmitText(WordOut);
        PrevWasDot := False;
        PrevWasColon := False;
        PrevTokKind := stkWord;
        PrevTokUpper := Tok.Upper;
        PrevTokText := WordOut;
        Inc(I);
        Continue;
      end;

      { Strings and Quoted Identifiers }
      EmitText(Tok.Text);
      PrevWasDot := False;
      PrevWasColon := False;
      PrevTokKind := Tok.Kind;
      PrevTokUpper := '';
      PrevTokText := Tok.Text;
      Inc(I);
    end;

    Result := TrimRight(SB.ToString);
  finally
    SB.Free;
  end;
end;

end.
