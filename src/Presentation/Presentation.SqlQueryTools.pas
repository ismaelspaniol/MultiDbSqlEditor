unit Presentation.SqlQueryTools;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, LCLType, SynEdit, SynHighlighterSQL, fpjson, jsonparser,
  Domain.DatabaseTypes,
  Domain.QueryResult;

function PromptAndResolveSqlParameters(
  const ASQL: string;
  const ADbType: TDatabaseType;
  out AResolvedSQL: string
): Boolean;

function IsDestructiveSqlForProduction(
  const ASQL: string;
  out AReason: string
): Boolean;

procedure SplitSelectStatements(
  const ASQL: string;
  const AStatements: TStrings
);

function ShowSqlSnippetsDialog(
  const ASynEdit: TSynEdit;
  const ADbType: TDatabaseType
): Boolean;

implementation

type
  TSnippetItem = record
    Title: string;
    Category: string;
    SqlText: string;
  end;

var
  GParamValueCache: TStringList = nil;

function GetParamCache: TStringList;
begin
  if GParamValueCache = nil then
    GParamValueCache := TStringList.Create;
  Result := GParamValueCache;
end;

function StartsWithSqlKeyword(const AUpperSQL, AKeyword: string): Boolean;
var
  LenK: Integer;
begin
  LenK := Length(AKeyword);
  if Copy(AUpperSQL, 1, LenK) <> AKeyword then
    Exit(False);
  if Length(AUpperSQL) = LenK then
    Exit(True);
  Result := AUpperSQL[LenK + 1] in [#0..' ', '(', ';'];
end;

function ShouldScanParametersForSQL(const ASQL: string): Boolean;
var
  Upper: string;
begin
  Upper := UpperCase(StripLeadingSqlComments(ASQL));
  if Upper = '' then
    Exit(False);
  if StartsWithSqlKeyword(Upper, 'CREATE') or
     StartsWithSqlKeyword(Upper, 'ALTER') or
     StartsWithSqlKeyword(Upper, 'RECREATE') or
     StartsWithSqlKeyword(Upper, 'EXECUTE') or
     StartsWithSqlKeyword(Upper, 'DO') then
    Exit(False);

  Result := StartsWithSqlKeyword(Upper, 'SELECT') or
            StartsWithSqlKeyword(Upper, 'WITH') or
            StartsWithSqlKeyword(Upper, 'INSERT') or
            StartsWithSqlKeyword(Upper, 'UPDATE') or
            StartsWithSqlKeyword(Upper, 'DELETE');
end;

procedure ExtractSqlParameters(
  const ASQL: string;
  const ANames: TStrings;
  out AStarts, ALengths: array of Integer
);
begin
  { Unused stub - implemented directly below with dynamic arrays }
end;

type
  TParamOccurrence = record
    Name: string;
    StartPos: Integer;
    LengthChars: Integer;
  end;

function FindSqlParameters(
  const ASQL: string;
  const AUniqueNames: TStrings;
  out AOccurrences: array of TParamOccurrence
): Integer;
begin
  Result := 0;
end;

function CollectSqlParameterOccurrences(
  const ASQL: string;
  const AUniqueNames: TStrings;
  var AOccurrences: array of TParamOccurrence
): Integer;
begin
  Result := 0;
end;

function PromptAndResolveSqlParameters(
  const ASQL: string;
  const ADbType: TDatabaseType;
  out AResolvedSQL: string
): Boolean;
type
  TOccRec = record
    Name: string;
    StartPos: Integer;
    Len: Integer;
  end;
var
  Occs: array of TOccRec;
  OccCount, OccCap, I, Len, NameStart: Integer;
  InSingle, InDouble, InLineComment, InBlockComment: Boolean;
  UniqueNames, Cache: TStringList;
  ParamName, CachedVal, RawVal, IsNullStr, Replacement: string;
  Frm: TForm;
  Lbl: TLabel;
  Grd: TStringGrid;
  PnlBtn: TPanel;
  BtnOk, BtnCancel: TButton;
  InvFmt: TFormatSettings;
  DummyFloat: Double;
  OutSql: string;
  LastPos: Integer;

  procedure AddOccurrence(const AName: string; const AStart, ALen: Integer);
  begin
    if OccCount >= OccCap then
    begin
      OccCap := OccCap * 2;
      SetLength(Occs, OccCap);
    end;
    Occs[OccCount].Name := AName;
    Occs[OccCount].StartPos := AStart;
    Occs[OccCount].Len := ALen;
    Inc(OccCount);
    if UniqueNames.IndexOf(AName) < 0 then
      UniqueNames.Add(AName);
  end;

begin
  AResolvedSQL := ASQL;
  if not ShouldScanParametersForSQL(ASQL) then
    Exit(True);

  UniqueNames := TStringList.Create;
  UniqueNames.CaseSensitive := False;
  try
    OccCount := 0;
    OccCap := 16;
    SetLength(Occs, OccCap);

    Len := Length(ASQL);
    I := 1;
    InSingle := False;
    InDouble := False;
    InLineComment := False;
    InBlockComment := False;

    while I <= Len do
    begin
      if InLineComment then
      begin
        if ASQL[I] in [#10, #13] then
          InLineComment := False;
        Inc(I);
        Continue;
      end;
      if InBlockComment then
      begin
        if (ASQL[I] = '*') and (I < Len) and (ASQL[I + 1] = '/') then
        begin
          InBlockComment := False;
          Inc(I, 2);
          Continue;
        end;
        Inc(I);
        Continue;
      end;
      if InSingle then
      begin
        if ASQL[I] = '''' then
        begin
          if (I < Len) and (ASQL[I + 1] = '''') then
            Inc(I, 2)
          else
          begin
            InSingle := False;
            Inc(I);
          end;
          Continue;
        end;
        Inc(I);
        Continue;
      end;
      if InDouble then
      begin
        if ASQL[I] = '"' then
          InDouble := False;
        Inc(I);
        Continue;
      end;

      if (ASQL[I] = '-') and (I < Len) and (ASQL[I + 1] = '-') then
      begin
        InLineComment := True;
        Inc(I, 2);
        Continue;
      end;
      if (ASQL[I] = '/') and (I < Len) and (ASQL[I + 1] = '*') then
      begin
        InBlockComment := True;
        Inc(I, 2);
        Continue;
      end;
      if ASQL[I] = '''' then
      begin
        InSingle := True;
        Inc(I);
        Continue;
      end;
      if ASQL[I] = '"' then
      begin
        InDouble := True;
        Inc(I);
        Continue;
      end;

      if ASQL[I] = ':' then
      begin
        { Ignore PostgreSQL :: type cast and PSQL := assignment }
        if (I < Len) and (ASQL[I + 1] in [':', '=']) then
        begin
          Inc(I, 2);
          Continue;
        end;
        if (I > 1) and (ASQL[I - 1] = ':') then
        begin
          Inc(I);
          Continue;
        end;
        if (I < Len) and (ASQL[I + 1] in ['A'..'Z', 'a'..'z', '_']) then
        begin
          NameStart := I + 1;
          Inc(I, 2);
          while (I <= Len) and (ASQL[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
            Inc(I);
          ParamName := Copy(ASQL, NameStart, I - NameStart);
          AddOccurrence(ParamName, NameStart - 1, I - (NameStart - 1));
          Continue;
        end;
      end;
      Inc(I);
    end;

    if UniqueNames.Count = 0 then
      Exit(True);

    Cache := GetParamCache;
    Frm := TForm.CreateNew(nil);
    try
      Frm.Caption := 'Parâmetros da Consulta SQL';
      Frm.Position := poScreenCenter;
      Frm.Width := 480;
      Frm.Height := 300;
      Frm.BorderStyle := bsSizeable;

      Lbl := TLabel.Create(Frm);
      Lbl.Parent := Frm;
      Lbl.Align := alTop;
      Lbl.BorderSpacing.Around := 8;
      Lbl.Caption := 'Informe os valores para os parâmetros detectados (use N ou vazio na 3ª coluna para texto/número; S para NULL):';
      Lbl.WordWrap := True;

      PnlBtn := TPanel.Create(Frm);
      PnlBtn.Parent := Frm;
      PnlBtn.Align := alBottom;
      PnlBtn.Height := 42;
      PnlBtn.BevelOuter := bvNone;

      BtnCancel := TButton.Create(Frm);
      BtnCancel.Parent := PnlBtn;
      BtnCancel.Caption := 'Cancelar';
      BtnCancel.ModalResult := mrCancel;
      BtnCancel.Cancel := True;
      BtnCancel.Width := 90;
      BtnCancel.Height := 26;
      BtnCancel.Left := PnlBtn.Width - 100;
      BtnCancel.Top := 8;
      BtnCancel.Anchors := [akTop, akRight];

      BtnOk := TButton.Create(Frm);
      BtnOk.Parent := PnlBtn;
      BtnOk.Caption := 'Executar';
      BtnOk.ModalResult := mrOk;
      BtnOk.Default := True;
      BtnOk.Width := 90;
      BtnOk.Height := 26;
      BtnOk.Left := BtnCancel.Left - 98;
      BtnOk.Top := 8;
      BtnOk.Anchors := [akTop, akRight];

      Grd := TStringGrid.Create(Frm);
      Grd.Parent := Frm;
      Grd.Align := alClient;
      Grd.BorderSpacing.Left := 8;
      Grd.BorderSpacing.Right := 8;
      Grd.ColCount := 3;
      Grd.FixedCols := 1;
      Grd.FixedRows := 1;
      Grd.RowCount := UniqueNames.Count + 1;
      Grd.Options := [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goEditing, goAlwaysShowEditor, goColSizing];
      Grd.Cells[0, 0] := 'Parâmetro';
      Grd.Cells[1, 0] := 'Valor';
      Grd.Cells[2, 0] := 'NULL (S/N)';
      Grd.ColWidths[0] := 140;
      Grd.ColWidths[1] := 220;
      Grd.ColWidths[2] := 85;

      for I := 0 to UniqueNames.Count - 1 do
      begin
        Grd.Cells[0, I + 1] := ':' + UniqueNames[I];
        CachedVal := Cache.Values[LowerCase(UniqueNames[I])];
        if CachedVal = '__NULL__' then
        begin
          Grd.Cells[1, I + 1] := '';
          Grd.Cells[2, I + 1] := 'S';
        end
        else
        begin
          Grd.Cells[1, I + 1] := CachedVal;
          Grd.Cells[2, I + 1] := 'N';
        end;
      end;

      if Grd.RowCount > 1 then
      begin
        Grd.Col := 1;
        Grd.Row := 1;
      end;

      if Frm.ShowModal <> mrOk then
        Exit(False);

      InvFmt := DefaultFormatSettings;
      InvFmt.DecimalSeparator := '.';

      for I := 0 to UniqueNames.Count - 1 do
      begin
        IsNullStr := UpperCase(Trim(Grd.Cells[2, I + 1]));
        RawVal := Grd.Cells[1, I + 1];
        if IsNullStr = 'S' then
          Cache.Values[LowerCase(UniqueNames[I])] := '__NULL__'
        else
          Cache.Values[LowerCase(UniqueNames[I])] := RawVal;
      end;

      OutSql := '';
      LastPos := 1;
      for I := 0 to OccCount - 1 do
      begin
        OutSql := OutSql + Copy(ASQL, LastPos, Occs[I].StartPos - LastPos);
        NameStart := UniqueNames.IndexOf(Occs[I].Name);
        IsNullStr := UpperCase(Trim(Grd.Cells[2, NameStart + 1]));
        RawVal := Grd.Cells[1, NameStart + 1];
        if IsNullStr = 'S' then
          Replacement := 'NULL'
        else if (Trim(RawVal) <> '') and
                ((LowerCase(Trim(RawVal)) = 'true') or (LowerCase(Trim(RawVal)) = 'false')) and
                (ADbType = dtPostgreSQL) then
          Replacement := LowerCase(Trim(RawVal))
        else if (Trim(RawVal) <> '') and
                TryStrToFloat(Trim(RawVal), DummyFloat, InvFmt) and
                (not ((Length(Trim(RawVal)) > 1) and (Trim(RawVal)[1] = '0') and (Pos('.', Trim(RawVal)) = 0))) then
          Replacement := Trim(RawVal)
        else
          Replacement := '''' + StringReplace(RawVal, '''', '''''', [rfReplaceAll]) + '''';

        OutSql := OutSql + Replacement;
        LastPos := Occs[I].StartPos + Occs[I].Len;
      end;
      OutSql := OutSql + Copy(ASQL, LastPos, MaxInt);
      AResolvedSQL := OutSql;
      Result := True;
    finally
      Frm.Free;
    end;
  finally
    UniqueNames.Free;
  end;
end;

function IsDestructiveSqlForProduction(
  const ASQL: string;
  out AReason: string
): Boolean;
var
  Stmts: TStringList;
  I: Integer;
  CleanUpper: string;

  function HasTopLevelWhere(const S: string): Boolean;
  begin
    Result := (Pos(' WHERE ', S) > 0) or (Pos(#10'WHERE ', S) > 0) or
              (Pos(#9'WHERE ', S) > 0) or (Pos(' WHERE'#13, S) > 0) or
              (Pos(' WHERE'#10, S) > 0);
  end;

begin
  Result := False;
  AReason := '';
  Stmts := TStringList.Create;
  try
    SplitSelectStatements(ASQL, Stmts);
    for I := 0 to Stmts.Count - 1 do
    begin
      CleanUpper := ' ' + StringReplace(StringReplace(UpperCase(StripLeadingSqlComments(Stmts[I])), #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]) + ' ';
      if Pos(' DROP ', CleanUpper) > 0 then
      begin
        AReason := 'Comando DROP detectado em conexão de PRODUÇÃO.';
        Exit(True);
      end;
      if Pos(' TRUNCATE ', CleanUpper) > 0 then
      begin
        AReason := 'Comando TRUNCATE detectado em conexão de PRODUÇÃO.';
        Exit(True);
      end;
      if (Pos(' DELETE ', CleanUpper) > 0) and (not HasTopLevelWhere(CleanUpper)) then
      begin
        AReason := 'DELETE sem cláusula WHERE detectado em conexão de PRODUÇÃO.';
        Exit(True);
      end;
      if (Pos(' UPDATE ', CleanUpper) > 0) and (not HasTopLevelWhere(CleanUpper)) then
      begin
        AReason := 'UPDATE sem cláusula WHERE detectado em conexão de PRODUÇÃO.';
        Exit(True);
      end;
    end;
  finally
    Stmts.Free;
  end;
end;

procedure SplitSelectStatements(
  const ASQL: string;
  const AStatements: TStrings
);
var
  I, Len, StartIdx: Integer;
  InSingle, InDouble, InLineComment, InBlockComment: Boolean;
  Piece: string;
begin
  if AStatements = nil then
    Exit;
  AStatements.Clear;
  Len := Length(ASQL);
  I := 1;
  StartIdx := 1;
  InSingle := False;
  InDouble := False;
  InLineComment := False;
  InBlockComment := False;

  while I <= Len do
  begin
    if InLineComment then
    begin
      if ASQL[I] in [#10, #13] then
        InLineComment := False;
      Inc(I);
      Continue;
    end;
    if InBlockComment then
    begin
      if (ASQL[I] = '*') and (I < Len) and (ASQL[I + 1] = '/') then
      begin
        InBlockComment := False;
        Inc(I, 2);
        Continue;
      end;
      Inc(I);
      Continue;
    end;
    if InSingle then
    begin
      if ASQL[I] = '''' then
      begin
        if (I < Len) and (ASQL[I + 1] = '''') then
          Inc(I, 2)
        else
        begin
          InSingle := False;
          Inc(I);
        end;
        Continue;
      end;
      Inc(I);
      Continue;
    end;
    if InDouble then
    begin
      if ASQL[I] = '"' then
        InDouble := False;
      Inc(I);
      Continue;
    end;

    if (ASQL[I] = '-') and (I < Len) and (ASQL[I + 1] = '-') then
    begin
      InLineComment := True;
      Inc(I, 2);
      Continue;
    end;
    if (ASQL[I] = '/') and (I < Len) and (ASQL[I + 1] = '*') then
    begin
      InBlockComment := True;
      Inc(I, 2);
      Continue;
    end;
    if ASQL[I] = '''' then
    begin
      InSingle := True;
      Inc(I);
      Continue;
    end;
    if ASQL[I] = '"' then
    begin
      InDouble := True;
      Inc(I);
      Continue;
    end;

    if ASQL[I] = ';' then
    begin
      Piece := Trim(Copy(ASQL, StartIdx, I - StartIdx));
      if Piece <> '' then
        AStatements.Add(Piece);
      StartIdx := I + 1;
    end;
    Inc(I);
  end;

  Piece := Trim(Copy(ASQL, StartIdx, Len - StartIdx + 1));
  if Piece <> '' then
    AStatements.Add(Piece);
end;

function SnippetsFilePath: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'snippets.json';
end;

procedure LoadSnippetsList(var AItems: array of TSnippetItem);
begin
  { Unused }
end;

type
  TSnippetArray = array of TSnippetItem;

procedure EnsureDefaultSnippets(var ASnippets: TSnippetArray);
begin
  SetLength(ASnippets, 7);
  ASnippets[0].Title := 'Contagem agrupada';
  ASnippets[0].Category := 'Consultas';
  ASnippets[0].SqlText := 'SELECT COLUNA, COUNT(*) AS QTD' + LineEnding + 'FROM TABELA' + LineEnding + 'GROUP BY COLUNA' + LineEnding + 'ORDER BY 2 DESC;';

  ASnippets[1].Title := 'Localizar registros duplicados';
  ASnippets[1].Category := 'Diagnóstico';
  ASnippets[1].SqlText := 'SELECT CAMPO_CHAVE, COUNT(*) AS QTD' + LineEnding + 'FROM TABELA' + LineEnding + 'GROUP BY CAMPO_CHAVE' + LineEnding + 'HAVING COUNT(*) > 1;';

  ASnippets[2].Title := 'Consulta com parâmetros (:dt_ini, :dt_fim)';
  ASnippets[2].Category := 'Consultas';
  ASnippets[2].SqlText := 'SELECT *' + LineEnding + 'FROM TABELA' + LineEnding + 'WHERE DATA_CADASTRO BETWEEN :dt_ini AND :dt_fim;';

  ASnippets[3].Title := 'Firebird: Primeiros 100 registros';
  ASnippets[3].Category := 'Firebird';
  ASnippets[3].SqlText := 'SELECT FIRST 100 *' + LineEnding + 'FROM TABELA' + LineEnding + 'ORDER BY 1 DESC;';

  ASnippets[4].Title := 'PostgreSQL: Tamanho das tabelas';
  ASnippets[4].Category := 'PostgreSQL';
  ASnippets[4].SqlText := 'SELECT relname AS tabela,' + LineEnding + '       pg_size_pretty(pg_total_relation_size(relid)) AS tamanho_total' + LineEnding + 'FROM pg_catalog.pg_statio_user_tables' + LineEnding + 'ORDER BY pg_total_relation_size(relid) DESC;';

  ASnippets[5].Title := 'PostgreSQL: Locks e bloqueios ativos';
  ASnippets[5].Category := 'PostgreSQL';
  ASnippets[5].SqlText := 'SELECT pid, usename, state, wait_event_type, wait_event, query' + LineEnding + 'FROM pg_stat_activity' + LineEnding + 'WHERE state <> ''idle''' + LineEnding + 'ORDER BY query_start;';

  ASnippets[6].Title := 'Firebird: Transações ativas (MON$)';
  ASnippets[6].Category := 'Firebird';
  ASnippets[6].SqlText := 'SELECT t.MON$TRANSACTION_ID, a.MON$USER, a.MON$REMOTE_ADDRESS, s.MON$SQL_TEXT' + LineEnding + 'FROM MON$TRANSACTIONS t' + LineEnding + 'JOIN MON$ATTACHMENTS a ON a.MON$ATTACHMENT_ID = t.MON$ATTACHMENT_ID' + LineEnding + 'LEFT JOIN MON$STATEMENTS s ON s.MON$TRANSACTION_ID = t.MON$TRANSACTION_ID' + LineEnding + 'ORDER BY t.MON$TIMESTAMP;';
end;

procedure LoadSnippetsFromFile(out ASnippets: TSnippetArray);
var
  SL: TStringList;
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
begin
  SetLength(ASnippets, 0);
  if not FileExists(SnippetsFilePath) then
  begin
    EnsureDefaultSnippets(ASnippets);
    Exit;
  end;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(SnippetsFilePath, TEncoding.UTF8);
    if Trim(SL.Text) = '' then
    begin
      EnsureDefaultSnippets(ASnippets);
      Exit;
    end;
    Data := GetJSON(SL.Text);
    try
      if Data is TJSONArray then
      begin
        Arr := TJSONArray(Data);
        SetLength(ASnippets, Arr.Count);
        for I := 0 to Arr.Count - 1 do
        begin
          if Arr.Items[I] is TJSONObject then
          begin
            Obj := TJSONObject(Arr.Items[I]);
            ASnippets[I].Title := Obj.Get('title', '');
            ASnippets[I].Category := Obj.Get('category', 'Geral');
            ASnippets[I].SqlText := Obj.Get('sql', '');
          end;
        end;
      end;
    finally
      Data.Free;
    end;
  except
    EnsureDefaultSnippets(ASnippets);
  end;
  SL.Free;
end;

procedure SaveSnippetsToFile(const ASnippets: TSnippetArray);
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  SL: TStringList;
  I: Integer;
begin
  Arr := TJSONArray.Create;
  SL := TStringList.Create;
  try
    for I := 0 to High(ASnippets) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('title', ASnippets[I].Title);
      Obj.Add('category', ASnippets[I].Category);
      Obj.Add('sql', ASnippets[I].SqlText);
      Arr.Add(Obj);
    end;
    SL.Text := Arr.FormatJSON([], 2);
    SL.SaveToFile(SnippetsFilePath, TEncoding.UTF8);
  finally
    SL.Free;
    Arr.Free;
  end;
end;

type
  TSnippetsDialogHelper = class
  public
    Snippets: TSnippetArray;
    VisibleIndices: array of Integer;
    EdtSearch: TEdit;
    LbList: TListBox;
    SynPreview: TSynEdit;
    EditorSyn: TSynEdit;
    Frm: TForm;
    Inserted: Boolean;
    procedure PopulateList;
    procedure OnSearchChange(Sender: TObject);
    procedure OnListClick(Sender: TObject);
    procedure OnListDblClick(Sender: TObject);
    procedure OnInsertClick(Sender: TObject);
    procedure OnSaveCurrentClick(Sender: TObject);
    procedure OnDeleteClick(Sender: TObject);
  end;

procedure TSnippetsDialogHelper.PopulateList;
var
  FilterLower: string;
  I, Cnt: Integer;
begin
  FilterLower := LowerCase(Trim(EdtSearch.Text));
  LbList.Items.BeginUpdate;
  try
    LbList.Items.Clear;
    SetLength(VisibleIndices, Length(Snippets));
    Cnt := 0;
    for I := 0 to High(Snippets) do
    begin
      if (FilterLower = '') or
         (Pos(FilterLower, LowerCase(Snippets[I].Title)) > 0) or
         (Pos(FilterLower, LowerCase(Snippets[I].Category)) > 0) or
         (Pos(FilterLower, LowerCase(Snippets[I].SqlText)) > 0) then
      begin
        VisibleIndices[Cnt] := I;
        Inc(Cnt);
        LbList.Items.Add(Format('[%s] %s', [Snippets[I].Category, Snippets[I].Title]));
      end;
    end;
    SetLength(VisibleIndices, Cnt);
    if LbList.Items.Count > 0 then
    begin
      LbList.ItemIndex := 0;
      OnListClick(nil);
    end
    else
      SynPreview.Clear;
  finally
    LbList.Items.EndUpdate;
  end;
end;

procedure TSnippetsDialogHelper.OnSearchChange(Sender: TObject);
begin
  PopulateList;
end;

procedure TSnippetsDialogHelper.OnListClick(Sender: TObject);
var
  Idx: Integer;
begin
  if (LbList.ItemIndex >= 0) and (LbList.ItemIndex <= High(VisibleIndices)) then
  begin
    Idx := VisibleIndices[LbList.ItemIndex];
    SynPreview.Lines.Text := Snippets[Idx].SqlText;
  end
  else
    SynPreview.Clear;
end;

procedure TSnippetsDialogHelper.OnListDblClick(Sender: TObject);
begin
  OnInsertClick(Sender);
end;

procedure TSnippetsDialogHelper.OnInsertClick(Sender: TObject);
var
  SqlToInsert: string;
begin
  SqlToInsert := SynPreview.Lines.Text;
  if Trim(SqlToInsert) = '' then
    Exit;
  if EditorSyn <> nil then
  begin
    if Trim(EditorSyn.Lines.Text) = '' then
      EditorSyn.Lines.Text := SqlToInsert
    else
      EditorSyn.SelText := LineEnding + SqlToInsert + LineEnding;
  end;
  Inserted := True;
  Frm.ModalResult := mrOk;
end;

procedure TSnippetsDialogHelper.OnSaveCurrentClick(Sender: TObject);
var
  CurSql, TitleStr, CatStr: string;
  N: Integer;
begin
  if EditorSyn = nil then
    Exit;
  if EditorSyn.SelAvail then
    CurSql := Trim(EditorSyn.SelText)
  else
    CurSql := Trim(EditorSyn.Lines.Text);
  if CurSql = '' then
  begin
    MessageDlg('Snippets', 'Digite ou selecione um SQL no editor antes de salvar como favorito.', mtInformation, [mbOK], 0);
    Exit;
  end;
  TitleStr := InputBox('Novo Snippet / Favorito', 'Título do snippet:', 'Meu Snippet SQL');
  if Trim(TitleStr) = '' then
    Exit;
  CatStr := InputBox('Categoria', 'Categoria (ex: Consultas, Relatórios, Manutenção):', 'Favoritos');
  if Trim(CatStr) = '' then
    CatStr := 'Favoritos';

  N := Length(Snippets);
  SetLength(Snippets, N + 1);
  Snippets[N].Title := Trim(TitleStr);
  Snippets[N].Category := Trim(CatStr);
  Snippets[N].SqlText := CurSql;
  SaveSnippetsToFile(Snippets);
  PopulateList;
end;

procedure TSnippetsDialogHelper.OnDeleteClick(Sender: TObject);
var
  Idx, K: Integer;
begin
  if (LbList.ItemIndex < 0) or (LbList.ItemIndex > High(VisibleIndices)) then
    Exit;
  Idx := VisibleIndices[LbList.ItemIndex];
  if MessageDlg('Excluir Snippet', Format('Remover "%s"?', [Snippets[Idx].Title]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  for K := Idx to High(Snippets) - 1 do
    Snippets[K] := Snippets[K + 1];
  SetLength(Snippets, Length(Snippets) - 1);
  SaveSnippetsToFile(Snippets);
  PopulateList;
end;

function ShowSqlSnippetsDialog(
  const ASynEdit: TSynEdit;
  const ADbType: TDatabaseType
): Boolean;
var
  Helper: TSnippetsDialogHelper;
  PnlTop, PnlBottom: TPanel;
  LblSearch: TLabel;
  BtnInsert, BtnSaveCurrent, BtnDelete, BtnClose: TButton;
  SynHl: TSynSQLSyn;
begin
  Result := False;
  Helper := TSnippetsDialogHelper.Create;
  try
    Helper.EditorSyn := ASynEdit;
    Helper.Inserted := False;
    LoadSnippetsFromFile(Helper.Snippets);
    if not FileExists(SnippetsFilePath) then
      SaveSnippetsToFile(Helper.Snippets);

    Helper.Frm := TForm.CreateNew(nil);
    try
      Helper.Frm.Caption := 'Biblioteca de Snippets e Favoritos SQL';
      Helper.Frm.Position := poScreenCenter;
      Helper.Frm.Width := 820;
      Helper.Frm.Height := 520;

      PnlTop := TPanel.Create(Helper.Frm);
      PnlTop.Parent := Helper.Frm;
      PnlTop.Align := alTop;
      PnlTop.Height := 40;
      PnlTop.BevelOuter := bvNone;

      LblSearch := TLabel.Create(Helper.Frm);
      LblSearch.Parent := PnlTop;
      LblSearch.Left := 10;
      LblSearch.Top := 12;
      LblSearch.Caption := 'Buscar:';

      Helper.EdtSearch := TEdit.Create(Helper.Frm);
      Helper.EdtSearch.Parent := PnlTop;
      Helper.EdtSearch.Left := 58;
      Helper.EdtSearch.Top := 8;
      Helper.EdtSearch.Width := 280;
      Helper.EdtSearch.TextHint := 'Filtrar por título, categoria ou SQL...';
      Helper.EdtSearch.OnChange := @Helper.OnSearchChange;

      BtnSaveCurrent := TButton.Create(Helper.Frm);
      BtnSaveCurrent.Parent := PnlTop;
      BtnSaveCurrent.Left := 350;
      BtnSaveCurrent.Top := 7;
      BtnSaveCurrent.Width := 190;
      BtnSaveCurrent.Height := 26;
      BtnSaveCurrent.Caption := '+ Salvar SQL Atual como Favorito';
      BtnSaveCurrent.OnClick := @Helper.OnSaveCurrentClick;

      BtnDelete := TButton.Create(Helper.Frm);
      BtnDelete.Parent := PnlTop;
      BtnDelete.Left := 548;
      BtnDelete.Top := 7;
      BtnDelete.Width := 95;
      BtnDelete.Height := 26;
      BtnDelete.Caption := 'Excluir';
      BtnDelete.OnClick := @Helper.OnDeleteClick;

      PnlBottom := TPanel.Create(Helper.Frm);
      PnlBottom.Parent := Helper.Frm;
      PnlBottom.Align := alBottom;
      PnlBottom.Height := 42;
      PnlBottom.BevelOuter := bvNone;

      BtnClose := TButton.Create(Helper.Frm);
      BtnClose.Parent := PnlBottom;
      BtnClose.Caption := 'Fechar';
      BtnClose.ModalResult := mrCancel;
      BtnClose.Cancel := True;
      BtnClose.Width := 90;
      BtnClose.Height := 26;
      BtnClose.Left := PnlBottom.Width - 100;
      BtnClose.Top := 8;
      BtnClose.Anchors := [akTop, akRight];

      BtnInsert := TButton.Create(Helper.Frm);
      BtnInsert.Parent := PnlBottom;
      BtnInsert.Caption := 'Inserir no Editor';
      BtnInsert.Default := True;
      BtnInsert.Width := 130;
      BtnInsert.Height := 26;
      BtnInsert.Left := BtnClose.Left - 138;
      BtnInsert.Top := 8;
      BtnInsert.Anchors := [akTop, akRight];
      BtnInsert.OnClick := @Helper.OnInsertClick;

      Helper.LbList := TListBox.Create(Helper.Frm);
      Helper.LbList.Parent := Helper.Frm;
      Helper.LbList.Align := alLeft;
      Helper.LbList.Width := 310;
      Helper.LbList.BorderSpacing.Left := 8;
      Helper.LbList.OnClick := @Helper.OnListClick;
      Helper.LbList.OnDblClick := @Helper.OnListDblClick;

      SynHl := TSynSQLSyn.Create(Helper.Frm);
      if ADbType = dtPostgreSQL then
        SynHl.SQLDialect := sqlPostgres
      else
        SynHl.SQLDialect := sqlFirebird40;

      Helper.SynPreview := TSynEdit.Create(Helper.Frm);
      Helper.SynPreview.Parent := Helper.Frm;
      Helper.SynPreview.Align := alClient;
      Helper.SynPreview.BorderSpacing.Left := 6;
      Helper.SynPreview.BorderSpacing.Right := 8;
      Helper.SynPreview.ReadOnly := True;
      Helper.SynPreview.Highlighter := SynHl;

      Helper.PopulateList;
      Helper.Frm.ShowModal;
      Result := Helper.Inserted;
    finally
      Helper.Frm.Free;
    end;
  finally
    Helper.Free;
  end;
end;

initialization

finalization
  FreeAndNil(GParamValueCache);

end.
