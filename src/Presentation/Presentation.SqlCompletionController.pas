unit Presentation.SqlCompletionController;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Menus, LCLType,
  SynEdit, SynCompletion,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.SqlAliasResolver;

type
  TGetCompletionProfileEvent = function: TConnectionProfile of object;
  TExecuteMetadataQueryEvent = function(const ASQL: string): TQueryResult of object;

  { Controlador reutilizável de autocompletar SQL (Ctrl+Espaço) para Editores SQL, Views, Procedures e Triggers }
  TSqlCompletionController = class(TComponent)
  private
    FEditor: TSynEdit;
    FOnGetProfile: TGetCompletionProfileEvent;
    FOnExecuteMetadataQuery: TExecuteMetadataQueryEvent;
    FCompletion: TSynCompletion;
    FCachedTables: TStringList;
    FCachedColumns: TStringList;
    FAllCompletionCandidates: TStringList;
    FIsPopulatingCompletion: Boolean;
    FIncludeProceduralKeywords: Boolean;
    FDefaultTriggerTable: string;
    function CurrentProfile: TConnectionProfile;
    procedure EnsureTablesCached;
    function GetCaretByteOffsetInSQL: Integer;
    function ExtractPrefixBeforeCaret: string;
    function ExtractWordBeforeDot: string;
    function ExtractTriggerTargetTable(const ASQL: string): string;
    procedure LoadColumnsForTable(const ATableName: string; const ATarget: TStrings);
    procedure FilterCompletionList(const AFilter: string);
    procedure CompletionSearchPosition(var APosition: Integer);
    procedure CompletionExecute(Sender: TObject);
    procedure CompletionKeyNextChar(Sender: TObject);
    procedure CompletionKeyPrevChar(Sender: TObject);
  public
    constructor Create(
      AOwner: TComponent;
      const AEditor: TSynEdit;
      const AOnGetProfile: TGetCompletionProfileEvent;
      const AOnExecuteMetadataQuery: TExecuteMetadataQueryEvent
    ); reintroduce;
    destructor Destroy; override;
    procedure ClearMetadataCache;
    property IncludeProceduralKeywords: Boolean
      read FIncludeProceduralKeywords write FIncludeProceduralKeywords;
    property DefaultTriggerTable: string
      read FDefaultTriggerTable write FDefaultTriggerTable;
  end;

implementation

function UnquoteIdentifier(const AIdent: string): string;
var
  S: string;
begin
  S := Trim(AIdent);
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then
  begin
    S := Copy(S, 2, Length(S) - 2);
    S := StringReplace(S, '""', '"', [rfReplaceAll]);
  end;
  Result := Trim(S);
end;

constructor TSqlCompletionController.Create(
  AOwner: TComponent;
  const AEditor: TSynEdit;
  const AOnGetProfile: TGetCompletionProfileEvent;
  const AOnExecuteMetadataQuery: TExecuteMetadataQueryEvent
);
begin
  inherited Create(AOwner);
  FEditor := AEditor;
  FOnGetProfile := AOnGetProfile;
  FOnExecuteMetadataQuery := AOnExecuteMetadataQuery;
  FIsPopulatingCompletion := False;
  FIncludeProceduralKeywords := False;

  FCachedTables := TStringList.Create;
  FCachedTables.Sorted := True;
  FCachedTables.Duplicates := dupIgnore;

  FCachedColumns := TStringList.Create;
  FCachedColumns.OwnsObjects := True;
  FCachedColumns.CaseSensitive := False;
  FCachedColumns.Sorted := True;
  FCachedColumns.Duplicates := dupIgnore;

  FAllCompletionCandidates := TStringList.Create;

  FCompletion := TSynCompletion.Create(Self);
  FCompletion.Editor := FEditor;
  FCompletion.CaseSensitive := False;
  FCompletion.ShortCut := Menus.ShortCut(VK_SPACE, [ssCtrl]);
  FCompletion.OnExecute := @CompletionExecute;
  FCompletion.OnSearchPosition := @CompletionSearchPosition;
  FCompletion.OnKeyNextChar := @CompletionKeyNextChar;
  FCompletion.OnKeyPrevChar := @CompletionKeyPrevChar;
end;

destructor TSqlCompletionController.Destroy;
begin
  if FCompletion <> nil then
    FCompletion.Editor := nil;
  FreeAndNil(FCachedColumns);
  FreeAndNil(FAllCompletionCandidates);
  FreeAndNil(FCachedTables);
  inherited Destroy;
end;

procedure TSqlCompletionController.ClearMetadataCache;
begin
  if FCachedTables <> nil then
    FCachedTables.Clear;
  if FCachedColumns <> nil then
    FCachedColumns.Clear;
  if FAllCompletionCandidates <> nil then
    FAllCompletionCandidates.Clear;
end;

function TSqlCompletionController.CurrentProfile: TConnectionProfile;
begin
  if Assigned(FOnGetProfile) then
    Result := FOnGetProfile()
  else
    Result := nil;
end;

procedure TSqlCompletionController.EnsureTablesCached;
var
  Profile: TConnectionProfile;
  SQL, TblName: string;
  Res: TQueryResult;
  I: Integer;
begin
  if (FCachedTables = nil) or (FCachedTables.Count > 0) then
    Exit;
  if not Assigned(FOnExecuteMetadataQuery) then
    Exit;

  Profile := CurrentProfile;
  if Profile = nil then
    Exit;

  if Profile.DatabaseType = dtPostgreSQL then
    SQL :=
      'SELECT table_name FROM information_schema.tables WHERE table_schema = current_schema() ' +
      'UNION ' +
      'SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = current_schema() ' +
      'ORDER BY 1'
  else if Profile.DatabaseType = dtMariaDB then
    SQL := 'SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY 1'
  else
    SQL :=
      'SELECT TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ' +
      'UNION ' +
      'SELECT TRIM(RDB$PROCEDURE_NAME) FROM RDB$PROCEDURES WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY 1';

  try
    Res := FOnExecuteMetadataQuery(SQL);
    if Res = nil then
      Exit;
    try
      if Res.Success and Res.HasResultSet and (Res.ColumnCount > 0) then
      begin
        for I := 0 to Res.RowCount - 1 do
        begin
          TblName := Trim(Res.GetRow(I)[0].AsText);
          if TblName <> '' then
            FCachedTables.Add(TblName);
        end;
      end;
    finally
      Res.Free;
    end;
  except
  end;
end;

function TSqlCompletionController.GetCaretByteOffsetInSQL: Integer;
var
  Caret: TPoint;
  I: Integer;
  FullSQL: string;
begin
  Result := 1;
  if FEditor = nil then
    Exit;

  Caret := FEditor.LogicalCaretXY;
  for I := 0 to Min(Caret.Y - 2, FEditor.Lines.Count - 1) do
    Inc(Result, Length(FEditor.Lines[I]) + Length(LineEnding));
  Result := Result + Max(0, Caret.X - 1);

  FullSQL := FEditor.Lines.Text;
  if Result > Length(FullSQL) + 1 then
    Result := Length(FullSQL) + 1;
end;

function TSqlCompletionController.ExtractPrefixBeforeCaret: string;
var
  Line: string;
  EndPos, StartPos: Integer;
begin
  Result := '';
  if FEditor = nil then
    Exit;

  Line := FEditor.LineText;
  EndPos := FEditor.LogicalCaretXY.X - 1;
  if EndPos > Length(Line) then
    EndPos := Length(Line);
  if EndPos < 1 then
    Exit;

  StartPos := EndPos;
  while (StartPos >= 1) and ((Line[StartPos] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) or (Ord(Line[StartPos]) >= 128)) do
    Dec(StartPos);
  Inc(StartPos);
  if StartPos <= EndPos then
    Result := Copy(Line, StartPos, EndPos - StartPos + 1);
end;

function TSqlCompletionController.ExtractWordBeforeDot: string;
var
  Line, PrefixBefore: string;
  P, StartPos: Integer;
begin
  Result := '';
  if FEditor = nil then
    Exit;

  Line := FEditor.LineText;
  PrefixBefore := ExtractPrefixBeforeCaret;
  P := FEditor.LogicalCaretXY.X - 1 - Length(PrefixBefore);
  if P > Length(Line) then
    P := Length(Line);
  if (P >= 1) and (Line[P] = '.') then
  begin
    Dec(P);
    if (P >= 1) and (Line[P] = '"') then
    begin
      StartPos := P - 1;
      while StartPos >= 1 do
      begin
        if Line[StartPos] = '"' then
        begin
          if (StartPos > 1) and (Line[StartPos - 1] = '"') then
            Dec(StartPos, 2)
          else
            Break;
        end
        else
          Dec(StartPos);
      end;
      if (StartPos >= 1) and (Line[StartPos] = '"') then
        Result := Copy(Line, StartPos, P - StartPos + 1);
    end
    else
    begin
      StartPos := P;
      while (StartPos >= 1) and ((Line[StartPos] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) or (Ord(Line[StartPos]) >= 128)) do
        Dec(StartPos);
      Inc(StartPos);
      if StartPos <= P then
        Result := Copy(Line, StartPos, P - StartPos + 1);
    end;
  end;
end;

function TSqlCompletionController.ExtractTriggerTargetTable(const ASQL: string): string;
var
  I, Len, StartI: Integer;
  Tok, UpperTok: string;
  SawTrigger, NeedTriggerName, ExpectForTable, ExpectOnTable: Boolean;

  function ReadNextToken(out AIsWord: Boolean): string;
  var
    C: Char;
    Buf: string;
  begin
    AIsWord := False;
    Result := '';
    while I <= Len do
    begin
      C := ASQL[I];
      if C in [' ', #9, #10, #13] then
      begin
        Inc(I);
        Continue;
      end;
      if (C = '-') and (I < Len) and (ASQL[I + 1] = '-') then
      begin
        Inc(I, 2);
        while (I <= Len) and not (ASQL[I] in [#10, #13]) do
          Inc(I);
        Continue;
      end;
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
      if C = '''' then
      begin
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
        Result := '''''';
        Exit;
      end;
      if C = '"' then
      begin
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
        AIsWord := True;
        Result := Trim(Buf);
        Exit;
      end;
      if (C in ['A'..'Z', 'a'..'z', '_', '$']) or (Ord(C) >= 128) then
      begin
        StartI := I;
        Inc(I);
        while (I <= Len) and ((ASQL[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) or (Ord(ASQL[I]) >= 128)) do
          Inc(I);
        AIsWord := True;
        Result := Copy(ASQL, StartI, I - StartI);
        Exit;
      end;
      Result := C;
      Inc(I);
      Exit;
    end;
  end;

  function ReadTableIdent(const AFirstPart: string): string;
  var
    SavedI: Integer;
    Part1, Part2: string;
    IsW: Boolean;
  begin
    Result := UnquoteIdentifier(AFirstPart);
    SavedI := I;
    Part1 := ReadNextToken(IsW);
    if Part1 = '.' then
    begin
      Part2 := ReadNextToken(IsW);
      if IsW and (Part2 <> '') then
        Result := UnquoteIdentifier(Part2);
    end
    else
      I := SavedI;
  end;

var
  IsWord: Boolean;
begin
  Result := '';
  Len := Length(ASQL);
  I := 1;
  SawTrigger := False;
  NeedTriggerName := False;
  ExpectForTable := False;
  ExpectOnTable := False;

  while I <= Len do
  begin
    Tok := ReadNextToken(IsWord);
    if Tok = '' then
      Break;
    UpperTok := UpperCase(Tok);

    if ExpectForTable then
    begin
      if IsWord then
        Result := ReadTableIdent(Tok);
      Exit;
    end;

    if ExpectOnTable then
    begin
      if IsWord then
      begin
        { Trigger de banco Firebird: ON CONNECT/DISCONNECT/TRANSACTION }
        if (UpperTok = 'CONNECT') or (UpperTok = 'DISCONNECT') or (UpperTok = 'TRANSACTION') then
          Exit('');
        Result := ReadTableIdent(Tok);
      end;
      Exit;
    end;

    if NeedTriggerName then
    begin
      if IsWord then
      begin
        { Pula eventual schema.nome_trigger no Postgres }
        while (I <= Len) do
        begin
          Tok := ReadNextToken(IsWord);
          if Tok = '.' then
            ReadNextToken(IsWord)
          else
          begin
            { Reprocessa o token lido após o nome da trigger }
            UpperTok := UpperCase(Tok);
            if UpperTok = 'FOR' then
              ExpectForTable := True
            else if UpperTok = 'ON' then
              ExpectOnTable := True
            else if (UpperTok = 'AS') or (UpperTok = 'BEGIN') or (UpperTok = 'EXECUTE') or (Tok = ';') then
              Exit;
            Break;
          end;
        end;
        NeedTriggerName := False;
      end;
      Continue;
    end;

    if not SawTrigger then
    begin
      if IsWord and (UpperTok = 'TRIGGER') then
      begin
        SawTrigger := True;
        NeedTriggerName := True;
      end;
    end
    else
    begin
      if IsWord then
      begin
        if UpperTok = 'FOR' then
          ExpectForTable := True
        else if UpperTok = 'ON' then
          ExpectOnTable := True
        else if (UpperTok = 'AS') or (UpperTok = 'BEGIN') or (UpperTok = 'EXECUTE') then
          Exit;
      end
      else if Tok = ';' then
        Exit;
    end;
  end;
end;

procedure TSqlCompletionController.LoadColumnsForTable(const ATableName: string; const ATarget: TStrings);
var
  Profile: TConnectionProfile;
  CacheKey, SQL, SafeTable: string;
  I, CacheIdx: Integer;
  CachedList, ColList: TStringList;

  function LoadColumnsFromQuery(const AQuerySQL: string; const AOutList: TStrings): Boolean;
  var
    Res: TQueryResult;
    J: Integer;
    ColName: string;
  begin
    Result := False;
    try
      Res := FOnExecuteMetadataQuery(AQuerySQL);
      if Res = nil then
        Exit;
      try
        if Res.Success and Res.HasResultSet and (Res.ColumnCount > 0) then
        begin
          for J := 0 to Res.RowCount - 1 do
          begin
            ColName := Trim(Res.GetRow(J)[0].AsText);
            if ColName <> '' then
              AOutList.Add(ColName);
          end;
          Result := AOutList.Count > 0;
        end;
      finally
        Res.Free;
      end;
    except
    end;
  end;

begin
  CacheKey := UnquoteIdentifier(ATableName);
  if (CacheKey = '') or (ATarget = nil) or (not Assigned(FOnExecuteMetadataQuery)) then
    Exit;

  if (FCachedColumns <> nil) and FCachedColumns.Find(CacheKey, CacheIdx) then
  begin
    CachedList := TStringList(FCachedColumns.Objects[CacheIdx]);
    if CachedList <> nil then
    begin
      for I := 0 to CachedList.Count - 1 do
        ATarget.Add(CachedList[I]);
    end;
    Exit;
  end;

  Profile := CurrentProfile;
  if Profile = nil then
    Exit;

  SafeTable := StringReplace(CacheKey, '''', '''''', [rfReplaceAll]);
  if Profile.DatabaseType = dtPostgreSQL then
    SQL := Format(
      'SELECT column_name FROM information_schema.columns WHERE table_schema = current_schema() AND lower(table_name) = lower(''%s'') ORDER BY ordinal_position',
      [SafeTable]
    )
  else if Profile.DatabaseType = dtMariaDB then
    SQL := Format(
      'SELECT column_name FROM information_schema.columns WHERE table_schema = DATABASE() AND LOWER(table_name) = LOWER(''%s'') ORDER BY ordinal_position',
      [SafeTable]
    )
  else
    SQL := Format(
      'SELECT TRIM(RDB$FIELD_NAME) FROM RDB$RELATION_FIELDS WHERE UPPER(TRIM(RDB$RELATION_NAME)) = UPPER(''%s'') ORDER BY RDB$FIELD_POSITION',
      [SafeTable]
    );

  ColList := TStringList.Create;
  try
    if not LoadColumnsFromQuery(SQL, ColList) then
    begin
      if Profile.DatabaseType = dtFirebird then
      begin
        SQL := Format(
          'SELECT TRIM(RDB$PARAMETER_NAME) ' +
          'FROM RDB$PROCEDURE_PARAMETERS ' +
          'WHERE UPPER(TRIM(RDB$PROCEDURE_NAME)) = UPPER(''%s'') ' +
          '  AND RDB$PARAMETER_TYPE = 1 ' +
          'ORDER BY RDB$PARAMETER_NUMBER',
          [SafeTable]
        );
        LoadColumnsFromQuery(SQL, ColList);
      end
      else if Profile.DatabaseType = dtPostgreSQL then
      begin
        SQL := Format(
          'SELECT u.arg_name ' +
          'FROM ( ' +
          '  SELECT p.proargnames, p.proargmodes ' +
          '  FROM pg_proc p ' +
          '  JOIN pg_namespace n ON n.oid = p.pronamespace ' +
          '  WHERE n.nspname = current_schema() ' +
          '    AND lower(p.proname) = lower(''%s'') ' +
          '    AND p.proargnames IS NOT NULL ' +
          '  ORDER BY p.oid ' +
          '  LIMIT 1 ' +
          ') proc ' +
          'CROSS JOIN LATERAL unnest(proc.proargnames, COALESCE(proc.proargmodes, ARRAY[]::char[])) WITH ORDINALITY AS u(arg_name, arg_mode, ord) ' +
          'WHERE COALESCE(u.arg_name, '''') <> '''' ' +
          '  AND u.arg_mode IN (''o'', ''b'', ''t'') ' +
          'ORDER BY u.ord',
          [SafeTable]
        );
        if not LoadColumnsFromQuery(SQL, ColList) then
        begin
          SQL := Format(
            'SELECT a.attname ' +
            'FROM pg_proc p ' +
            'JOIN pg_namespace n ON n.oid = p.pronamespace ' +
            'JOIN pg_type t ON t.oid = p.prorettype ' +
            'JOIN pg_attribute a ON a.attrelid = t.typrelid ' +
            'WHERE n.nspname = current_schema() ' +
            '  AND lower(p.proname) = lower(''%s'') ' +
            '  AND t.typrelid <> 0 ' +
            '  AND a.attnum > 0 ' +
            '  AND NOT a.attisdropped ' +
            'ORDER BY a.attnum',
            [SafeTable]
          );
          LoadColumnsFromQuery(SQL, ColList);
        end;
      end;
    end;

    for I := 0 to ColList.Count - 1 do
      ATarget.Add(ColList[I]);

    if (ColList.Count > 0) and (FCachedColumns <> nil) then
    begin
      FCachedColumns.AddObject(CacheKey, ColList);
      ColList := nil;
    end;
  finally
    ColList.Free;
  end;
end;

procedure TSqlCompletionController.FilterCompletionList(const AFilter: string);
var
  CleanFilter, CandLower: string;
  I, MatchPos: Integer;
  PrefixMatches, SubstringMatches: TStringList;
begin
  if FCompletion = nil then
    Exit;

  FCompletion.ItemList.BeginUpdate;
  try
    FCompletion.ItemList.Clear;
    if FAllCompletionCandidates = nil then
      Exit;

    CleanFilter := LowerCase(Trim(AFilter));
    if CleanFilter = '' then
    begin
      for I := 0 to FAllCompletionCandidates.Count - 1 do
        FCompletion.ItemList.Add(FAllCompletionCandidates[I]);
      Exit;
    end;

    PrefixMatches := TStringList.Create;
    SubstringMatches := TStringList.Create;
    try
      for I := 0 to FAllCompletionCandidates.Count - 1 do
      begin
        CandLower := LowerCase(FAllCompletionCandidates[I]);
        MatchPos := Pos(CleanFilter, CandLower);
        if MatchPos = 1 then
          PrefixMatches.Add(FAllCompletionCandidates[I])
        else if MatchPos > 1 then
          SubstringMatches.Add(FAllCompletionCandidates[I]);
      end;

      for I := 0 to PrefixMatches.Count - 1 do
        FCompletion.ItemList.Add(PrefixMatches[I]);
      for I := 0 to SubstringMatches.Count - 1 do
        FCompletion.ItemList.Add(SubstringMatches[I]);
    finally
      SubstringMatches.Free;
      PrefixMatches.Free;
    end;
  finally
    FCompletion.ItemList.EndUpdate;
  end;
end;

procedure TSqlCompletionController.CompletionSearchPosition(var APosition: Integer);
begin
  if FIsPopulatingCompletion then
    Exit;
  FilterCompletionList(FCompletion.CurrentString);
  if FCompletion.ItemList.Count > 0 then
    APosition := 0
  else
    APosition := -1;
end;

procedure TSqlCompletionController.CompletionExecute(Sender: TObject);
const
  SqlKeywords: array[0..30] of string = (
    'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IN', 'IS NULL', 'IS NOT NULL',
    'ORDER BY', 'GROUP BY', 'HAVING', 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'ON',
    'AS', 'DISTINCT', 'FIRST 100', 'LIMIT 100', 'INSERT INTO', 'VALUES',
    'UPDATE', 'SET', 'DELETE FROM', 'COUNT(*)', 'SUM(', 'AVG(', 'MIN(', 'MAX(',
    'COALESCE('
  );
  ProceduralKeywords: array[0..23] of string = (
    'BEGIN', 'END', 'DECLARE VARIABLE', 'DECLARE', 'RETURNS',
    'IF', 'THEN', 'ELSE', 'ELSIF', 'WHILE', 'DO',
    'FOR SELECT', 'INTO', 'SUSPEND', 'EXIT', 'EXCEPTION',
    'EXECUTE PROCEDURE', 'RETURNING', 'NEW.', 'OLD.',
    'PERFORM', 'RETURN', 'RETURN NEXT', 'RAISE EXCEPTION'
  );
var
  Prefix, WordBeforeDot, TargetTable, FullSQL, StmtSQL: string;
  CaretOff, I: Integer;
  Aliases: TSqlTableAliasArray;
  Seen: TStringList;

  procedure AddUniqueCandidate(const AValue: string);
  begin
    if (Trim(AValue) <> '') and (Seen.IndexOf(AValue) < 0) then
    begin
      Seen.Add(AValue);
      FAllCompletionCandidates.Add(AValue);
    end;
  end;

begin
  if FAllCompletionCandidates = nil then
    FAllCompletionCandidates := TStringList.Create;
  if FEditor = nil then
    Exit;

  FIsPopulatingCompletion := True;
  try
    FAllCompletionCandidates.Clear;
    Prefix := ExtractPrefixBeforeCaret;
    FullSQL := FEditor.Lines.Text;
    CaretOff := GetCaretByteOffsetInSQL;
    WordBeforeDot := ExtractWordBeforeDot;

    if WordBeforeDot <> '' then
    begin
      if SameText(WordBeforeDot, 'NEW') or SameText(WordBeforeDot, 'OLD') then
      begin
        TargetTable := ExtractTriggerTargetTable(FullSQL);
        if TargetTable = '' then
          TargetTable := FDefaultTriggerTable;
        if TargetTable <> '' then
          LoadColumnsForTable(TargetTable, FAllCompletionCandidates);
      end;

      if FAllCompletionCandidates.Count = 0 then
      begin
        TargetTable := ResolveSqlTableAlias(FullSQL, CaretOff, WordBeforeDot);
        LoadColumnsForTable(TargetTable, FAllCompletionCandidates);
        if (FAllCompletionCandidates.Count = 0) and (not SameText(TargetTable, WordBeforeDot)) then
          LoadColumnsForTable(WordBeforeDot, FAllCompletionCandidates);
      end;
    end
    else
    begin
      Seen := TStringList.Create;
      Seen.CaseSensitive := False;
      Seen.Sorted := True;
      try
        StmtSQL := ExtractStatementAtOffset(FullSQL, CaretOff);
        Aliases := ExtractSqlTableAliases(StmtSQL);
        for I := 0 to High(Aliases) do
          AddUniqueCandidate(Aliases[I].AliasName);

        EnsureTablesCached;
        for I := 0 to FCachedTables.Count - 1 do
          AddUniqueCandidate(FCachedTables[I]);
        for I := Low(SqlKeywords) to High(SqlKeywords) do
          AddUniqueCandidate(SqlKeywords[I]);
        if FIncludeProceduralKeywords then
        begin
          for I := Low(ProceduralKeywords) to High(ProceduralKeywords) do
            AddUniqueCandidate(ProceduralKeywords[I]);
        end;
      finally
        Seen.Free;
      end;
    end;

    FilterCompletionList(Prefix);
    FCompletion.CurrentString := Prefix;
    if FCompletion.ItemList.Count > 0 then
      FCompletion.Position := 0
    else
      FCompletion.Position := -1;
  finally
    FIsPopulatingCompletion := False;
  end;
end;

procedure TSqlCompletionController.CompletionKeyNextChar(Sender: TObject);
var
  Pt: TPoint;
begin
  if FEditor = nil then
    Exit;
  Pt := FEditor.LogicalCaretXY;
  if Pt.X <= Length(FEditor.LineText) then
  begin
    Inc(Pt.X);
    FEditor.LogicalCaretXY := Pt;
  end;
  CompletionExecute(FCompletion);
end;

procedure TSqlCompletionController.CompletionKeyPrevChar(Sender: TObject);
var
  Pt: TPoint;
begin
  if FEditor = nil then
    Exit;
  Pt := FEditor.LogicalCaretXY;
  if Pt.X > 1 then
  begin
    Dec(Pt.X);
    FEditor.LogicalCaretXY := Pt;
  end;
  CompletionExecute(FCompletion);
end;

end.
