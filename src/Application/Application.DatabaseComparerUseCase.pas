unit Application.DatabaseComparerUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Domain.TableStructureTypes,
  Domain.DatabaseCompareTypes,
  Application.ManageDatabaseObjectsUseCase,
  Application.ManageTableStructureUseCase;

type
  TSnapshotCodeItem = class
  public
    Name: string;
    TableName: string;
    DDL: string;
  end;

  { Snapshot completo de metadados de uma base para comparação rápida em memória }
  TDatabaseSchemaSnapshot = class
  public
    Generators: TStringList;
    Tables: TStringList;
    Views: TStringList;
    Procedures: TStringList;
    Triggers: TStringList;
    constructor Create;
    destructor Destroy; override;
    function FindTable(const ATableName: string): TTableStructure;
    function FindOrAddTable(const ATableName: string): TTableStructure;
    procedure AddGenerator(const AName: string);
    function HasGenerator(const AName: string): Boolean;
    procedure AddView(const AName, ADDL: string);
    function FindView(const AName: string): TSnapshotCodeItem;
    procedure AddProcedure(const AName, ADDL: string);
    function FindProcedure(const AName: string): TSnapshotCodeItem;
    procedure AddTrigger(const AName, ATableName, ADDL: string);
    function FindTrigger(const AName: string): TSnapshotCodeItem;
  end;

  TCompareProgressCallback = procedure(const AStatusText: string) of object;
  TCompareCancelCheck = function: Boolean of object;

  TCompareDatabasesWorker = class;
  TApplyCompareScriptWorker = class;

  TCompareCompletedEvent = procedure(
    const AWorker: TCompareDatabasesWorker;
    const AResult: TCompareResult;
    const AErrorMessage: string
  ) of object;

  TApplyScriptProgressEvent = procedure(const ALogLine: string) of object;
  TApplyScriptCompletedEvent = procedure(
    const AWorker: TApplyCompareScriptWorker;
    const ASuccess: Boolean;
    const AExecutedCount: Integer;
    const AErrorMessage: string
  ) of object;

  { Caso de uso de comparação de bases e geração/aplicação de script de sincronização }
  TDatabaseComparerUseCase = class
  private
    FFactory: IDatabaseProviderFactory;
    procedure LoadFirebirdSnapshot(
      const ASession: IDatabaseSession;
      const ASnap: TDatabaseSchemaSnapshot;
      const AWarnings: TStrings;
      const ACancelCheck: TCompareCancelCheck
    );
    procedure LoadPostgresSnapshot(
      const ASession: IDatabaseSession;
      const ASnap: TDatabaseSchemaSnapshot;
      const AWarnings: TStrings;
      const ACancelCheck: TCompareCancelCheck
    );
  public
    constructor Create(const AFactory: IDatabaseProviderFactory);
    function CaptureSnapshot(
      const AProfile: TConnectionProfile;
      const AWarnings: TStrings = nil;
      const ACancelCheck: TCompareCancelCheck = nil
    ): TDatabaseSchemaSnapshot;
    function CompareDatabases(
      const ASourceProfile, ATargetProfile: TConnectionProfile;
      const AOptions: TCompareOptions;
      const AProgress: TCompareProgressCallback = nil;
      const ACancelCheck: TCompareCancelCheck = nil
    ): TCompareResult;
  end;

  { Thread em segundo plano para capturar snapshots e gerar o diff sem travar a UI }
  TCompareDatabasesWorker = class(TThread)
  private
    FFactory: IDatabaseProviderFactory;
    FSourceProfile: TConnectionProfile;
    FTargetProfile: TConnectionProfile;
    FOptions: TCompareOptions;
    FLock: TCriticalSection;
    FDetached: Boolean;
    FCancelRequested: Boolean;
    FPendingStatus: string;
    FResult: TCompareResult;
    FErrorMessage: string;
    FOnProgress: TCompareProgressCallback;
    FOnComplete: TCompareCompletedEvent;
    procedure ReportProgress(const AStatus: string);
    function CheckCancelled: Boolean;
    procedure DeliverProgressOnMainThread;
    procedure FinishOnMainThread;
  protected
    procedure Execute; override;
  public
    constructor Create(
      const AFactory: IDatabaseProviderFactory;
      const ASourceProfile, ATargetProfile: TConnectionProfile;
      const AOptions: TCompareOptions;
      const AOnProgress: TCompareProgressCallback;
      const AOnComplete: TCompareCompletedEvent
    );
    destructor Destroy; override;
    procedure RequestCancel;
    procedure Detach;
  end;

  { Thread em segundo plano para aplicar o script SQL gerado na base de destino }
  TApplyCompareScriptWorker = class(TThread)
  private
    FFactory: IDatabaseProviderFactory;
    FTargetProfile: TConnectionProfile;
    FScript: string;
    FLock: TCriticalSection;
    FDetached: Boolean;
    FCancelRequested: Boolean;
    FPendingLog: TStringList;
    FSuccess: Boolean;
    FExecutedCount: Integer;
    FErrorMessage: string;
    FOnProgress: TApplyScriptProgressEvent;
    FOnComplete: TApplyScriptCompletedEvent;
    procedure AppendLog(const ALine: string);
    procedure DeliverLogOnMainThread;
    procedure FinishOnMainThread;
  protected
    procedure Execute; override;
  public
    constructor Create(
      const AFactory: IDatabaseProviderFactory;
      const ATargetProfile: TConnectionProfile;
      const AScript: string;
      const AOnProgress: TApplyScriptProgressEvent;
      const AOnComplete: TApplyScriptCompletedEvent
    );
    destructor Destroy; override;
    procedure RequestCancel;
    procedure Detach;
  end;

procedure SplitSqlScriptStatements(
  const AScript: string;
  const ADbType: TDatabaseType;
  const ATarget: TStrings
);

function CompareSnapshots(
  const ADbType: TDatabaseType;
  const ATargetIsFirebird25: Boolean;
  const ASource, ATarget: TDatabaseSchemaSnapshot;
  const AOptions: TCompareOptions
): TCompareResult;

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
      RawStmt := Trim(Copy(AScript, StartPos, AEndIdx - StartPos + 1))
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

{ TDatabaseSchemaSnapshot }

constructor TDatabaseSchemaSnapshot.Create;
begin
  inherited Create;
  Generators := TStringList.Create;
  Generators.CaseSensitive := False;
  Generators.Sorted := True;
  Generators.Duplicates := dupIgnore;

  Tables := TStringList.Create;
  Tables.OwnsObjects := True;
  Tables.CaseSensitive := False;
  Tables.Sorted := True;
  Tables.Duplicates := dupIgnore;

  Views := TStringList.Create;
  Views.OwnsObjects := True;
  Views.CaseSensitive := False;
  Views.Sorted := True;
  Views.Duplicates := dupIgnore;

  Procedures := TStringList.Create;
  Procedures.OwnsObjects := True;
  Procedures.CaseSensitive := False;
  Procedures.Sorted := True;
  Procedures.Duplicates := dupIgnore;

  Triggers := TStringList.Create;
  Triggers.OwnsObjects := True;
  Triggers.CaseSensitive := False;
  Triggers.Sorted := True;
  Triggers.Duplicates := dupIgnore;
end;

destructor TDatabaseSchemaSnapshot.Destroy;
begin
  Triggers.Free;
  Procedures.Free;
  Views.Free;
  Tables.Free;
  Generators.Free;
  inherited Destroy;
end;

function TDatabaseSchemaSnapshot.FindTable(const ATableName: string): TTableStructure;
var
  Idx: Integer;
begin
  Result := nil;
  if Tables.Find(Trim(ATableName), Idx) then
    Result := TTableStructure(Tables.Objects[Idx]);
end;

function TDatabaseSchemaSnapshot.FindOrAddTable(const ATableName: string): TTableStructure;
var
  CleanName: string;
  Idx: Integer;
begin
  CleanName := Trim(ATableName);
  if Tables.Find(CleanName, Idx) then
    Exit(TTableStructure(Tables.Objects[Idx]));

  Result := TTableStructure.Create;
  Result.TableName := CleanName;
  Tables.AddObject(CleanName, Result);
end;

procedure TDatabaseSchemaSnapshot.AddGenerator(const AName: string);
begin
  if Trim(AName) <> '' then
    Generators.Add(Trim(AName));
end;

function TDatabaseSchemaSnapshot.HasGenerator(const AName: string): Boolean;
var
  Idx: Integer;
begin
  Result := Generators.Find(Trim(AName), Idx);
end;

procedure TDatabaseSchemaSnapshot.AddView(const AName, ADDL: string);
var
  Item: TSnapshotCodeItem;
  Clean: string;
  Idx: Integer;
begin
  Clean := Trim(AName);
  if Clean = '' then
    Exit;
  if Views.Find(Clean, Idx) then
  begin
    Item := TSnapshotCodeItem(Views.Objects[Idx]);
    Item.DDL := ADDL;
    Exit;
  end;
  Item := TSnapshotCodeItem.Create;
  Item.Name := Clean;
  Item.DDL := ADDL;
  Views.AddObject(Clean, Item);
end;

function TDatabaseSchemaSnapshot.FindView(const AName: string): TSnapshotCodeItem;
var
  Idx: Integer;
begin
  Result := nil;
  if Views.Find(Trim(AName), Idx) then
    Result := TSnapshotCodeItem(Views.Objects[Idx]);
end;

procedure TDatabaseSchemaSnapshot.AddProcedure(const AName, ADDL: string);
var
  Item: TSnapshotCodeItem;
  Clean: string;
  Idx: Integer;
begin
  Clean := Trim(AName);
  if Clean = '' then
    Exit;
  if Procedures.Find(Clean, Idx) then
  begin
    Item := TSnapshotCodeItem(Procedures.Objects[Idx]);
    Item.DDL := ADDL;
    Exit;
  end;
  Item := TSnapshotCodeItem.Create;
  Item.Name := Clean;
  Item.DDL := ADDL;
  Procedures.AddObject(Clean, Item);
end;

function TDatabaseSchemaSnapshot.FindProcedure(const AName: string): TSnapshotCodeItem;
var
  Idx: Integer;
begin
  Result := nil;
  if Procedures.Find(Trim(AName), Idx) then
    Result := TSnapshotCodeItem(Procedures.Objects[Idx]);
end;

procedure TDatabaseSchemaSnapshot.AddTrigger(const AName, ATableName, ADDL: string);
var
  Item: TSnapshotCodeItem;
  Clean: string;
  Idx: Integer;
begin
  Clean := Trim(AName);
  if Clean = '' then
    Exit;
  if Triggers.Find(Clean, Idx) then
  begin
    Item := TSnapshotCodeItem(Triggers.Objects[Idx]);
    Item.TableName := Trim(ATableName);
    Item.DDL := ADDL;
    Exit;
  end;
  Item := TSnapshotCodeItem.Create;
  Item.Name := Clean;
  Item.TableName := Trim(ATableName);
  Item.DDL := ADDL;
  Triggers.AddObject(Clean, Item);
end;

function TDatabaseSchemaSnapshot.FindTrigger(const AName: string): TSnapshotCodeItem;
var
  Idx: Integer;
begin
  Result := nil;
  if Triggers.Find(Trim(AName), Idx) then
    Result := TSnapshotCodeItem(Triggers.Objects[Idx]);
end;

{ Funções de geração parcial para Diff }

function BuildCreateTableCoreDDL(
  const ADbType: TDatabaseType;
  const AStruct: TTableStructure
): string;
var
  CloneStruct: TTableStructure;
begin
  if AStruct = nil then
    Exit('');
  CloneStruct := TTableStructure.Create;
  try
    CloneStruct.TableName := AStruct.TableName;
    CloneStruct.PrimaryKeyName := AStruct.PrimaryKeyName;
    CloneStruct.PrimaryKeyColumns := AStruct.PrimaryKeyColumns;
    CloneStruct.Columns := AStruct.Columns;
    CloneStruct.UniqueConstraints := AStruct.UniqueConstraints;
    CloneStruct.CheckConstraints := AStruct.CheckConstraints;
    // ForeignKeys e Indexes ficam após criação de todas as tabelas para evitar falha de ordem/referência circular
    Result := GenerateTableDDL(ADbType, CloneStruct, False);
  finally
    CloneStruct.Free;
  end;
end;

function BuildAddForeignKeyDDL(
  const ADbType: TDatabaseType;
  const ATableName: string;
  const AFK: TTableForeignKeyInfo
): string;
var
  RuleUpd, RuleDel: string;
begin
  Result := Format('ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s (%s)', [
    QuoteDbIdent(ADbType, ATableName),
    QuoteDbIdent(ADbType, AFK.ConstraintName),
    QuoteIdentList(ADbType, AFK.Columns),
    QuoteDbIdent(ADbType, AFK.RefTable),
    QuoteIdentList(ADbType, AFK.RefColumns)
  ]);
  RuleUpd := UpperCase(Trim(AFK.UpdateRule));
  RuleDel := UpperCase(Trim(AFK.DeleteRule));
  if (RuleUpd <> '') and (RuleUpd <> 'RESTRICT') and (RuleUpd <> 'NO ACTION') then
    Result := Result + ' ON UPDATE ' + RuleUpd;
  if (RuleDel <> '') and (RuleDel <> 'RESTRICT') and (RuleDel <> 'NO ACTION') then
    Result := Result + ' ON DELETE ' + RuleDel;
end;

function BuildIndexStatement(
  const ADbType: TDatabaseType;
  const ATableName: string;
  const AIdx: TTableIndexInfo
): string;
var
  Cols: TStringList;
begin
  Result := '';
  if (ADbType = dtPostgreSQL) and (Pos('CREATE ', UpperCase(TrimLeft(AIdx.ExpressionSource))) = 1) then
  begin
    Result := TrimRight(AIdx.ExpressionSource);
    Exit;
  end;

  if Trim(AIdx.ExpressionSource) <> '' then
  begin
    Result := 'CREATE ';
    if AIdx.IsUnique then
      Result := Result + 'UNIQUE ';
    if (ADbType = dtFirebird) and AIdx.IsDescending then
      Result := Result + 'DESCENDING ';
    Result := Result + Format('INDEX %s ON %s COMPUTED BY %s', [
      QuoteDbIdent(ADbType, AIdx.IndexName),
      QuoteDbIdent(ADbType, ATableName),
      Trim(AIdx.ExpressionSource)
    ]);
  end
  else
  begin
    Cols := ExtractCommaIdentList(AIdx.Columns);
    try
      Result := BuildCreateIndexDDL(ADbType, ATableName, AIdx.IndexName, Cols, AIdx.IsUnique, AIdx.IsDescending);
    finally
      Cols.Free;
    end;
  end;

  if (Result <> '') and (ADbType = dtFirebird) and (not AIdx.IsActive) then
    Result := Result + ';' + LineEnding + 'ALTER INDEX ' + QuoteDbIdent(dtFirebird, AIdx.IndexName) + ' INACTIVE';
end;

function CompareSnapshots(
  const ADbType: TDatabaseType;
  const ATargetIsFirebird25: Boolean;
  const ASource, ATarget: TDatabaseSchemaSnapshot;
  const AOptions: TCompareOptions
): TCompareResult;
var
  I, J: Integer;
  Item: TCompareDiffItem;
  SrcTbl, TgtTbl: TTableStructure;
  SrcCol, TgtCol: TTableColumnInfo;
  SrcIdx, TgtIdx: TTableIndexInfo;
  SrcFK, TgtFK: TTableForeignKeyInfo;
  SrcCode, TgtCode: TSnapshotCodeItem;
  EditStmts: TStringList;
  NormSrc, NormTgt, TempSql, TblIdent: string;
  IsDifferent: Boolean;

  function FindCol(const ATbl: TTableStructure; const AName: string; out AOutCol: TTableColumnInfo): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    if ATbl = nil then
      Exit;
    for K := 0 to High(ATbl.Columns) do
      if SameText(ATbl.Columns[K].ColumnName, AName) then
      begin
        AOutCol := ATbl.Columns[K];
        Exit(True);
      end;
  end;

  function FindIdx(const ATbl: TTableStructure; const AName: string; out AOutIdx: TTableIndexInfo): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    if ATbl = nil then
      Exit;
    for K := 0 to High(ATbl.Indexes) do
      if SameText(ATbl.Indexes[K].IndexName, AName) then
      begin
        AOutIdx := ATbl.Indexes[K];
        Exit(True);
      end;
  end;

  function FindFK(const ATbl: TTableStructure; const AName: string; out AOutFK: TTableForeignKeyInfo): Boolean;
  var
    K: Integer;
  begin
    Result := False;
    if ATbl = nil then
      Exit;
    for K := 0 to High(ATbl.ForeignKeys) do
      if SameText(ATbl.ForeignKeys[K].ConstraintName, AName) then
      begin
        AOutFK := ATbl.ForeignKeys[K];
        Exit(True);
      end;
  end;

  procedure InitDiffItem(
    out AOut: TCompareDiffItem;
    const ACat: TCompareObjectCategory;
    const AObjName, AParentName: string;
    const AStatus: TCompareDiffStatus;
    const ASummary, ASrcDDL, ATgtDDL, AUpdateSQL: string;
    const ANeedsSetTerm: Boolean = False
  );
  begin
    AOut.Selected := AStatus <> cdsExtraInTarget;
    AOut.Category := ACat;
    AOut.ObjectName := AObjName;
    AOut.ParentName := AParentName;
    AOut.Status := AStatus;
    AOut.Summary := ASummary;
    AOut.SourceDDL := ASrcDDL;
    AOut.TargetDDL := ATgtDDL;
    AOut.UpdateSQL := AUpdateSQL;
    AOut.NeedsSetTerm := ANeedsSetTerm;
  end;

begin
  Result := TCompareResult.Create;
  Result.DatabaseType := ADbType;

  { 1. Generators / Sequences }
  if AOptions.CompareGenerators then
  begin
    for I := 0 to ASource.Generators.Count - 1 do
    begin
      if not ATarget.HasGenerator(ASource.Generators[I]) then
      begin
        if ADbType = dtPostgreSQL then
          TempSql := Format('CREATE SEQUENCE %s START 1', [QuoteDbIdent(dtPostgreSQL, ASource.Generators[I])])
        else
          TempSql := Format('CREATE GENERATOR %s', [QuoteDbIdent(dtFirebird, ASource.Generators[I])]);
        InitDiffItem(
          Item, cocGenerator, ASource.Generators[I], '',
          cdsMissingInTarget, 'Generator/Sequence ausente no destino',
          TempSql, '', TempSql
        );
        Result.AddItem(Item);
      end;
    end;

    if AOptions.IncludeDropsForExtraObjects then
    begin
      for I := 0 to ATarget.Generators.Count - 1 do
      begin
        if not ASource.HasGenerator(ATarget.Generators[I]) then
        begin
          if ADbType = dtPostgreSQL then
            TempSql := 'DROP SEQUENCE IF EXISTS ' + QuoteDbIdent(dtPostgreSQL, ATarget.Generators[I])
          else
            TempSql := 'DROP GENERATOR ' + QuoteDbIdent(dtFirebird, ATarget.Generators[I]);
          InitDiffItem(
            Item, cocGenerator, ATarget.Generators[I], '',
            cdsExtraInTarget, 'Existe apenas no destino',
            '', TempSql, TempSql
          );
          Result.AddItem(Item);
        end;
      end;
    end;
  end;

  { 2. Tabelas ausentes no destino (núcleo: colunas + PK + UNIQUE + CHECK) }
  if AOptions.CompareTablesAndColumns then
  begin
    for I := 0 to ASource.Tables.Count - 1 do
    begin
      SrcTbl := TTableStructure(ASource.Tables.Objects[I]);
      TgtTbl := ATarget.FindTable(SrcTbl.TableName);
      if TgtTbl = nil then
      begin
        TempSql := BuildCreateTableCoreDDL(ADbType, SrcTbl);
        InitDiffItem(
          Item, cocTable, SrcTbl.TableName, '',
          cdsMissingInTarget,
          Format('Tabela ausente (%d coluna(s))', [Length(SrcTbl.Columns)]),
          GenerateTableDDL(ADbType, SrcTbl, True),
          '',
          TempSql
        );
        Result.AddItem(Item);
      end;
    end;
  end;

  { 3. Colunas & Primary Keys de tabelas presentes em ambas }
  if AOptions.CompareTablesAndColumns then
  begin
    EditStmts := TStringList.Create;
    try
      for I := 0 to ASource.Tables.Count - 1 do
      begin
        SrcTbl := TTableStructure(ASource.Tables.Objects[I]);
        TgtTbl := ATarget.FindTable(SrcTbl.TableName);
        if TgtTbl = nil then
          Continue;

        for J := 0 to High(SrcTbl.Columns) do
        begin
          SrcCol := SrcTbl.Columns[J];
          if not FindCol(TgtTbl, SrcCol.ColumnName, TgtCol) then
          begin
            if SrcCol.IsComputed then
            begin
              TempSql := Format('ALTER TABLE %s ADD %s COMPUTED BY (%s)', [
                QuoteDbIdent(ADbType, SrcTbl.TableName),
                QuoteDbIdent(ADbType, SrcCol.ColumnName),
                Trim(SrcCol.ComputedSource)
              ]);
            end
            else
            begin
              TempSql := BuildAddColumnDDL(
                ADbType,
                SrcTbl.TableName,
                SrcCol.ColumnName,
                SrcCol.DataType,
                SrcCol.DefaultValue,
                SrcCol.NotNull
              );
            end;
            InitDiffItem(
              Item, cocColumn, SrcTbl.TableName + '.' + SrcCol.ColumnName, SrcTbl.TableName,
              cdsMissingInTarget,
              'Campo ausente no destino (' + SrcCol.DataType + ')',
              SrcCol.DataType,
              '',
              TempSql
            );
            Result.AddItem(Item);
          end
          else if (not SrcCol.IsComputed) and (not TgtCol.IsComputed) then
          begin
            EditStmts.Clear;
            BuildEditColumnDDL(
              ADbType,
              SrcTbl.TableName,
              TgtCol,
              TgtCol.ColumnName,
              SrcCol.DataType,
              SrcCol.DefaultValue,
              SrcCol.NotNull,
              ATargetIsFirebird25,
              EditStmts
            );
            if EditStmts.Count > 0 then
            begin
              TempSql := StringReplace(TrimRight(EditStmts.Text), LineEnding, ';' + LineEnding, [rfReplaceAll]);
              InitDiffItem(
                Item, cocColumn, SrcTbl.TableName + '.' + SrcCol.ColumnName, SrcTbl.TableName,
                cdsDifferent,
                Format('Origem: %s (NN=%s) | Destino: %s (NN=%s)', [
                  SrcCol.DataType, BoolToStr(SrcCol.NotNull, 'S', 'N'),
                  TgtCol.DataType, BoolToStr(TgtCol.NotNull, 'S', 'N')
                ]),
                SrcCol.DataType + ' DEFAULT ' + SrcCol.DefaultValue,
                TgtCol.DataType + ' DEFAULT ' + TgtCol.DefaultValue,
                TempSql
              );
              Result.AddItem(Item);
            end;
          end;
        end;

        if AOptions.IncludeDropsForExtraObjects then
        begin
          for J := 0 to High(TgtTbl.Columns) do
          begin
            TgtCol := TgtTbl.Columns[J];
            if not FindCol(SrcTbl, TgtCol.ColumnName, SrcCol) then
            begin
              TempSql := BuildDropColumnDDL(ADbType, SrcTbl.TableName, TgtCol.ColumnName);
              InitDiffItem(
                Item, cocColumn, SrcTbl.TableName + '.' + TgtCol.ColumnName, SrcTbl.TableName,
                cdsExtraInTarget,
                'Campo existe apenas no destino',
                '',
                TgtCol.DataType,
                TempSql
              );
              Result.AddItem(Item);
            end;
          end;
        end;

        { Primary Key da tabela existente }
        if AOptions.CompareConstraints then
        begin
          if (Trim(SrcTbl.PrimaryKeyColumns) <> '') and (Trim(TgtTbl.PrimaryKeyColumns) = '') then
          begin
            TblIdent := QuoteDbIdent(ADbType, SrcTbl.TableName);
            if (Trim(SrcTbl.PrimaryKeyName) <> '') and
               not ((ADbType = dtFirebird) and (Pos('INTEG_', UpperCase(Trim(SrcTbl.PrimaryKeyName))) = 1)) then
              TempSql := Format('ALTER TABLE %s ADD CONSTRAINT %s PRIMARY KEY (%s)', [
                TblIdent, QuoteDbIdent(ADbType, SrcTbl.PrimaryKeyName), QuoteIdentList(ADbType, SrcTbl.PrimaryKeyColumns)
              ])
            else
              TempSql := Format('ALTER TABLE %s ADD PRIMARY KEY (%s)', [
                TblIdent, QuoteIdentList(ADbType, SrcTbl.PrimaryKeyColumns)
              ]);
            InitDiffItem(
              Item, cocPrimaryKey, SrcTbl.TableName + ' (' + SrcTbl.PrimaryKeyColumns + ')', SrcTbl.TableName,
              cdsMissingInTarget,
              'Primary Key ausente no destino',
              TempSql,
              '',
              TempSql
            );
            Result.AddItem(Item);
          end
          else if (Trim(SrcTbl.PrimaryKeyColumns) <> '') and
                  (not SameText(Trim(SrcTbl.PrimaryKeyColumns), Trim(TgtTbl.PrimaryKeyColumns))) then
          begin
            TblIdent := QuoteDbIdent(ADbType, SrcTbl.TableName);
            TempSql := '';
            if Trim(TgtTbl.PrimaryKeyName) <> '' then
              TempSql := Format('ALTER TABLE %s DROP CONSTRAINT %s;%s', [
                TblIdent, QuoteDbIdent(ADbType, TgtTbl.PrimaryKeyName), LineEnding
              ]);
            TempSql := TempSql + Format('ALTER TABLE %s ADD CONSTRAINT %s PRIMARY KEY (%s)', [
              TblIdent,
              QuoteDbIdent(ADbType, SrcTbl.PrimaryKeyName),
              QuoteIdentList(ADbType, SrcTbl.PrimaryKeyColumns)
            ]);
            InitDiffItem(
              Item, cocPrimaryKey, SrcTbl.TableName + ' (' + SrcTbl.PrimaryKeyColumns + ')', SrcTbl.TableName,
              cdsDifferent,
              Format('PK diferente: Origem (%s) vs Destino (%s)', [SrcTbl.PrimaryKeyColumns, TgtTbl.PrimaryKeyColumns]),
              SrcTbl.PrimaryKeyColumns,
              TgtTbl.PrimaryKeyColumns,
              TempSql
            );
            Result.AddItem(Item);
          end;
        end;
      end;
    finally
      EditStmts.Free;
    end;
  end;

  { 4. Índices (inclui índices de tabelas novas também para permitir controle fino) }
  if AOptions.CompareIndexes then
  begin
    for I := 0 to ASource.Tables.Count - 1 do
    begin
      SrcTbl := TTableStructure(ASource.Tables.Objects[I]);
      TgtTbl := ATarget.FindTable(SrcTbl.TableName);
      for J := 0 to High(SrcTbl.Indexes) do
      begin
        SrcIdx := SrcTbl.Indexes[J];
        if SrcIdx.IsPrimaryKey or SrcIdx.IsForeignKey or (Trim(SrcIdx.ConstraintName) <> '') then
          Continue;

        if (TgtTbl = nil) or (not FindIdx(TgtTbl, SrcIdx.IndexName, TgtIdx)) then
        begin
          TempSql := BuildIndexStatement(ADbType, SrcTbl.TableName, SrcIdx);
          if TempSql <> '' then
          begin
            InitDiffItem(
              Item, cocIndex, SrcIdx.IndexName, SrcTbl.TableName,
              cdsMissingInTarget,
              Format('Índice ausente em %s (%s)', [SrcTbl.TableName, SrcIdx.Columns + SrcIdx.ExpressionSource]),
              TempSql,
              '',
              TempSql
            );
            Result.AddItem(Item);
          end;
        end
        else
        begin
          IsDifferent :=
            (not SameText(Trim(SrcIdx.Columns), Trim(TgtIdx.Columns))) or
            (SrcIdx.IsUnique <> TgtIdx.IsUnique) or
            (SrcIdx.IsDescending <> TgtIdx.IsDescending) or
            (not SameText(NormalizeCodeText(SrcIdx.ExpressionSource, True), NormalizeCodeText(TgtIdx.ExpressionSource, True)));
          if IsDifferent then
          begin
            TempSql := BuildDropIndexDDL(ADbType, TgtIdx.IndexName) + ';' + LineEnding +
              BuildIndexStatement(ADbType, SrcTbl.TableName, SrcIdx);
            InitDiffItem(
              Item, cocIndex, SrcIdx.IndexName, SrcTbl.TableName,
              cdsDifferent,
              Format('Definição divergente em %s', [SrcTbl.TableName]),
              BuildIndexStatement(ADbType, SrcTbl.TableName, SrcIdx),
              BuildIndexStatement(ADbType, SrcTbl.TableName, TgtIdx),
              TempSql
            );
            Result.AddItem(Item);
          end;
        end;
      end;

      if AOptions.IncludeDropsForExtraObjects and (TgtTbl <> nil) then
      begin
        for J := 0 to High(TgtTbl.Indexes) do
        begin
          TgtIdx := TgtTbl.Indexes[J];
          if TgtIdx.IsPrimaryKey or TgtIdx.IsForeignKey or (Trim(TgtIdx.ConstraintName) <> '') then
            Continue;
          if not FindIdx(SrcTbl, TgtIdx.IndexName, SrcIdx) then
          begin
            TempSql := BuildDropIndexDDL(ADbType, TgtIdx.IndexName);
            InitDiffItem(
              Item, cocIndex, TgtIdx.IndexName, SrcTbl.TableName,
              cdsExtraInTarget,
              'Índice existe apenas no destino',
              '',
              BuildIndexStatement(ADbType, SrcTbl.TableName, TgtIdx),
              TempSql
            );
            Result.AddItem(Item);
          end;
        end;
      end;
    end;
  end;

  { 5. Foreign Keys (emitidas após criação de todas as tabelas/índices) }
  if AOptions.CompareConstraints then
  begin
    for I := 0 to ASource.Tables.Count - 1 do
    begin
      SrcTbl := TTableStructure(ASource.Tables.Objects[I]);
      TgtTbl := ATarget.FindTable(SrcTbl.TableName);
      for J := 0 to High(SrcTbl.ForeignKeys) do
      begin
        SrcFK := SrcTbl.ForeignKeys[J];
        if (TgtTbl = nil) or (not FindFK(TgtTbl, SrcFK.ConstraintName, TgtFK)) then
        begin
          TempSql := BuildAddForeignKeyDDL(ADbType, SrcTbl.TableName, SrcFK);
          InitDiffItem(
            Item, cocForeignKey, SrcTbl.TableName + '.' + SrcFK.ConstraintName, SrcTbl.TableName,
            cdsMissingInTarget,
            Format('FK (%s) -> %s(%s)', [SrcFK.Columns, SrcFK.RefTable, SrcFK.RefColumns]),
            TempSql,
            '',
            TempSql
          );
          Result.AddItem(Item);
        end
        else
        begin
          IsDifferent :=
            (not SameText(Trim(SrcFK.Columns), Trim(TgtFK.Columns))) or
            (not SameText(Trim(SrcFK.RefTable), Trim(TgtFK.RefTable))) or
            (not SameText(Trim(SrcFK.RefColumns), Trim(TgtFK.RefColumns))) or
            (not SameText(Trim(SrcFK.UpdateRule), Trim(TgtFK.UpdateRule))) or
            (not SameText(Trim(SrcFK.DeleteRule), Trim(TgtFK.DeleteRule)));
          if IsDifferent then
          begin
            TempSql := Format('ALTER TABLE %s DROP CONSTRAINT %s;%s%s', [
              QuoteDbIdent(ADbType, SrcTbl.TableName),
              QuoteDbIdent(ADbType, TgtFK.ConstraintName),
              LineEnding,
              BuildAddForeignKeyDDL(ADbType, SrcTbl.TableName, SrcFK)
            ]);
            InitDiffItem(
              Item, cocForeignKey, SrcTbl.TableName + '.' + SrcFK.ConstraintName, SrcTbl.TableName,
              cdsDifferent,
              'Regra/colunas da FK diferentes no destino',
              BuildAddForeignKeyDDL(ADbType, SrcTbl.TableName, SrcFK),
              BuildAddForeignKeyDDL(ADbType, SrcTbl.TableName, TgtFK),
              TempSql
            );
            Result.AddItem(Item);
          end;
        end;
      end;

      if AOptions.IncludeDropsForExtraObjects and (TgtTbl <> nil) then
      begin
        for J := 0 to High(TgtTbl.ForeignKeys) do
        begin
          TgtFK := TgtTbl.ForeignKeys[J];
          if not FindFK(SrcTbl, TgtFK.ConstraintName, SrcFK) then
          begin
            TempSql := Format('ALTER TABLE %s DROP CONSTRAINT %s', [
              QuoteDbIdent(ADbType, SrcTbl.TableName),
              QuoteDbIdent(ADbType, TgtFK.ConstraintName)
            ]);
            InitDiffItem(
              Item, cocForeignKey, SrcTbl.TableName + '.' + TgtFK.ConstraintName, SrcTbl.TableName,
              cdsExtraInTarget,
              'FK existe apenas no destino',
              '',
              BuildAddForeignKeyDDL(ADbType, SrcTbl.TableName, TgtFK),
              TempSql
            );
            Result.AddItem(Item);
          end;
        end;
      end;
    end;
  end;

  { 6. Views }
  if AOptions.CompareViews then
  begin
    for I := 0 to ASource.Views.Count - 1 do
    begin
      SrcCode := TSnapshotCodeItem(ASource.Views.Objects[I]);
      TgtCode := ATarget.FindView(SrcCode.Name);
      if TgtCode = nil then
      begin
        InitDiffItem(
          Item, cocView, SrcCode.Name, '',
          cdsMissingInTarget, 'View ausente no destino',
          SrcCode.DDL, '', SrcCode.DDL
        );
        Result.AddItem(Item);
      end
      else
      begin
        NormSrc := NormalizeCodeText(SrcCode.DDL, AOptions.IgnoreWhitespaceInCode);
        NormTgt := NormalizeCodeText(TgtCode.DDL, AOptions.IgnoreWhitespaceInCode);
        if not SameText(NormSrc, NormTgt) then
        begin
          InitDiffItem(
            Item, cocView, SrcCode.Name, '',
            cdsDifferent, 'Definição da View diferente no destino',
            SrcCode.DDL, TgtCode.DDL, SrcCode.DDL
          );
          Result.AddItem(Item);
        end;
      end;
    end;

    if AOptions.IncludeDropsForExtraObjects then
    begin
      for I := 0 to ATarget.Views.Count - 1 do
      begin
        TgtCode := TSnapshotCodeItem(ATarget.Views.Objects[I]);
        if ASource.FindView(TgtCode.Name) = nil then
        begin
          TempSql := 'DROP VIEW ' + QuoteDbIdent(ADbType, TgtCode.Name);
          InitDiffItem(
            Item, cocView, TgtCode.Name, '',
            cdsExtraInTarget, 'View existe apenas no destino',
            '', TgtCode.DDL, TempSql
          );
          Result.AddItem(Item);
        end;
      end;
    end;
  end;

  { 7. Procedures / Functions }
  if AOptions.CompareProcedures then
  begin
    for I := 0 to ASource.Procedures.Count - 1 do
    begin
      SrcCode := TSnapshotCodeItem(ASource.Procedures.Objects[I]);
      TgtCode := ATarget.FindProcedure(SrcCode.Name);
      if TgtCode = nil then
      begin
        InitDiffItem(
          Item, cocProcedure, SrcCode.Name, '',
          cdsMissingInTarget, 'Procedure/Function ausente no destino',
          SrcCode.DDL, '', SrcCode.DDL, ADbType = dtFirebird
        );
        Result.AddItem(Item);
      end
      else
      begin
        NormSrc := NormalizeCodeText(SrcCode.DDL, AOptions.IgnoreWhitespaceInCode);
        NormTgt := NormalizeCodeText(TgtCode.DDL, AOptions.IgnoreWhitespaceInCode);
        if not SameText(NormSrc, NormTgt) then
        begin
          InitDiffItem(
            Item, cocProcedure, SrcCode.Name, '',
            cdsDifferent, 'Código da Procedure/Function diferente no destino',
            SrcCode.DDL, TgtCode.DDL, SrcCode.DDL, ADbType = dtFirebird
          );
          Result.AddItem(Item);
        end;
      end;
    end;

    if AOptions.IncludeDropsForExtraObjects then
    begin
      for I := 0 to ATarget.Procedures.Count - 1 do
      begin
        TgtCode := TSnapshotCodeItem(ATarget.Procedures.Objects[I]);
        if ASource.FindProcedure(TgtCode.Name) = nil then
        begin
          if ADbType = dtPostgreSQL then
            TempSql := 'DROP FUNCTION IF EXISTS ' + QuoteDbIdent(dtPostgreSQL, TgtCode.Name)
          else
            TempSql := 'DROP PROCEDURE ' + QuoteDbIdent(dtFirebird, TgtCode.Name);
          InitDiffItem(
            Item, cocProcedure, TgtCode.Name, '',
            cdsExtraInTarget, 'Procedure/Function existe apenas no destino',
            '', TgtCode.DDL, TempSql
          );
          Result.AddItem(Item);
        end;
      end;
    end;
  end;

  { 8. Triggers }
  if AOptions.CompareTriggers then
  begin
    for I := 0 to ASource.Triggers.Count - 1 do
    begin
      SrcCode := TSnapshotCodeItem(ASource.Triggers.Objects[I]);
      TgtCode := ATarget.FindTrigger(SrcCode.Name);
      if TgtCode = nil then
      begin
        InitDiffItem(
          Item, cocTrigger, SrcCode.Name, SrcCode.TableName,
          cdsMissingInTarget, 'Trigger ausente no destino',
          SrcCode.DDL, '', SrcCode.DDL, ADbType = dtFirebird
        );
        Result.AddItem(Item);
      end
      else
      begin
        NormSrc := NormalizeCodeText(SrcCode.DDL, AOptions.IgnoreWhitespaceInCode);
        NormTgt := NormalizeCodeText(TgtCode.DDL, AOptions.IgnoreWhitespaceInCode);
        if not SameText(NormSrc, NormTgt) then
        begin
          if (ADbType = dtPostgreSQL) and (SrcCode.TableName <> '') then
            TempSql := Format('DROP TRIGGER IF EXISTS %s ON %s;%s%s', [
              QuoteDbIdent(dtPostgreSQL, SrcCode.Name),
              QuoteDbIdent(dtPostgreSQL, SrcCode.TableName),
              LineEnding,
              SrcCode.DDL
            ])
          else
            TempSql := SrcCode.DDL;
          InitDiffItem(
            Item, cocTrigger, SrcCode.Name, SrcCode.TableName,
            cdsDifferent, 'Código da Trigger diferente no destino',
            SrcCode.DDL, TgtCode.DDL, TempSql, ADbType = dtFirebird
          );
          Result.AddItem(Item);
        end;
      end;
    end;

    if AOptions.IncludeDropsForExtraObjects then
    begin
      for I := 0 to ATarget.Triggers.Count - 1 do
      begin
        TgtCode := TSnapshotCodeItem(ATarget.Triggers.Objects[I]);
        if ASource.FindTrigger(TgtCode.Name) = nil then
        begin
          if (ADbType = dtPostgreSQL) and (TgtCode.TableName <> '') then
            TempSql := Format('DROP TRIGGER IF EXISTS %s ON %s', [
              QuoteDbIdent(dtPostgreSQL, TgtCode.Name),
              QuoteDbIdent(dtPostgreSQL, TgtCode.TableName)
            ])
          else
            TempSql := 'DROP TRIGGER ' + QuoteDbIdent(dtFirebird, TgtCode.Name);
          InitDiffItem(
            Item, cocTrigger, TgtCode.Name, TgtCode.TableName,
            cdsExtraInTarget, 'Trigger existe apenas no destino',
            '', TgtCode.DDL, TempSql
          );
          Result.AddItem(Item);
        end;
      end;
    end;
  end;

  { 9. Tabelas extras no destino (DROP opcional ao final) }
  if AOptions.CompareTablesAndColumns and AOptions.IncludeDropsForExtraObjects then
  begin
    for I := 0 to ATarget.Tables.Count - 1 do
    begin
      TgtTbl := TTableStructure(ATarget.Tables.Objects[I]);
      if ASource.FindTable(TgtTbl.TableName) = nil then
      begin
        TempSql := 'DROP TABLE ' + QuoteDbIdent(ADbType, TgtTbl.TableName);
        InitDiffItem(
          Item, cocTable, TgtTbl.TableName, '',
          cdsExtraInTarget, 'Tabela existe apenas no destino',
          '', GenerateTableDDL(ADbType, TgtTbl, True), TempSql
        );
        Result.AddItem(Item);
      end;
    end;
  end;
end;

{ TDatabaseComparerUseCase }

constructor TDatabaseComparerUseCase.Create(const AFactory: IDatabaseProviderFactory);
begin
  inherited Create;
  FFactory := AFactory;
end;

procedure TDatabaseComparerUseCase.LoadFirebirdSnapshot(
  const ASession: IDatabaseSession;
  const ASnap: TDatabaseSchemaSnapshot;
  const AWarnings: TStrings;
  const ACancelCheck: TCompareCancelCheck
);

  function ExecChecked(const ASQL: string): TQueryResult;
  begin
    if Assigned(ACancelCheck) and ACancelCheck() then
      raise Exception.Create('Comparação cancelada pelo usuário.');
    Result := ASession.ExecuteSQL(ASQL, False, 0);
    if not Result.Success then
    begin
      try
        raise Exception.Create(Result.MessageText);
      except
        Result.Free;
        raise;
      end;
    end;
  end;

var
  Res: TQueryResult;
  I, J, PType, TrigSeq, TrigType, IsInactive, IdxPos: Integer;
  Row: TQueryRow;
  TblName, IdxName, SegCol, ConName, ConType, FkCols, RefTbl, RefCols, SrcText, ColDef: string;
  Tbl: TTableStructure;
  Col: TTableColumnInfo;
  IdxInfo: TTableIndexInfo;
  ViewColsMap, ProcInMap, ProcOutMap, IdxSegMap: TStringList;
  CurList: TStringList;
  ParamStr, DDLText, ActiveStr, EventsStr, InP, OutP: string;
begin
  { 1. Generators }
  Res := ExecChecked(
    'SELECT TRIM(RDB$GENERATOR_NAME) FROM RDB$GENERATORS ' +
    'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1'
  );
  try
    for I := 0 to Res.RowCount - 1 do
      ASnap.AddGenerator(Res.GetRow(I)[0].AsText);
  finally
    Res.Free;
  end;

  { 2. Tabelas }
  Res := ExecChecked(
    'SELECT TRIM(RDB$RELATION_NAME) FROM RDB$RELATIONS ' +
    'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NULL ORDER BY 1'
  );
  try
    for I := 0 to Res.RowCount - 1 do
      ASnap.FindOrAddTable(Res.GetRow(I)[0].AsText);
  finally
    Res.Free;
  end;

  { 3. Colunas em lote }
  Res := ExecChecked(
    'SELECT ' +
    '  TRIM(rf.RDB$RELATION_NAME), ' +
    '  rf.RDB$FIELD_POSITION, ' +
    '  TRIM(rf.RDB$FIELD_NAME), ' +
    '  TRIM(rf.RDB$FIELD_SOURCE), ' +
    '  f.RDB$FIELD_TYPE, ' +
    '  f.RDB$FIELD_SUB_TYPE, ' +
    '  f.RDB$FIELD_LENGTH, ' +
    '  f.RDB$FIELD_PRECISION, ' +
    '  f.RDB$FIELD_SCALE, ' +
    '  f.RDB$CHARACTER_LENGTH, ' +
    '  COALESCE(rf.RDB$NULL_FLAG, f.RDB$NULL_FLAG, 0), ' +
    '  rf.RDB$DEFAULT_SOURCE, ' +
    '  f.RDB$DEFAULT_SOURCE, ' +
    '  f.RDB$COMPUTED_SOURCE ' +
    'FROM RDB$RELATION_FIELDS rf ' +
    'JOIN RDB$RELATIONS r ON r.RDB$RELATION_NAME = rf.RDB$RELATION_NAME ' +
    'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE ' +
    'WHERE COALESCE(r.RDB$SYSTEM_FLAG, 0) = 0 AND r.RDB$VIEW_BLR IS NULL ' +
    'ORDER BY rf.RDB$RELATION_NAME, rf.RDB$FIELD_POSITION'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      TblName := Trim(Row[0].AsText);
      Tbl := ASnap.FindTable(TblName);
      if Tbl = nil then
        Continue;

      FillChar(Col, SizeOf(Col), 0);
      Col.Position := StrToIntDef(Trim(Row[1].AsText), Length(Tbl.Columns));
      Col.ColumnName := Trim(Row[2].AsText);
      if Pos('RDB$', UpperCase(Trim(Row[3].AsText))) <> 1 then
        Col.DomainName := Trim(Row[3].AsText);
      Col.DataType := DecodeFirebirdFieldType(
        '',
        StrToIntDef(Trim(Row[4].AsText), 0),
        StrToIntDef(Trim(Row[5].AsText), 0),
        StrToIntDef(Trim(Row[6].AsText), 0),
        StrToIntDef(Trim(Row[7].AsText), 0),
        StrToIntDef(Trim(Row[8].AsText), 0),
        StrToIntDef(Trim(Row[9].AsText), 0)
      );
      Col.NotNull := StrToIntDef(Trim(Row[10].AsText), 0) = 1;
      ColDef := '';
      if not Row[11].IsNull then
        ColDef := StripLeadingDefaultKeyword(Row[11].AsText);
      if (ColDef = '') and (not Row[12].IsNull) then
        ColDef := StripLeadingDefaultKeyword(Row[12].AsText);
      Col.DefaultValue := ColDef;
      if not Row[13].IsNull then
        Col.ComputedSource := Trim(Row[13].AsText);
      Col.IsComputed := Col.ComputedSource <> '';

      SetLength(Tbl.Columns, Length(Tbl.Columns) + 1);
      Tbl.Columns[High(Tbl.Columns)] := Col;
    end;
  finally
    Res.Free;
  end;

  { 4. Constraints (PK e UNIQUE) em lote }
  Res := ExecChecked(
    'SELECT TRIM(rc.RDB$RELATION_NAME), TRIM(rc.RDB$CONSTRAINT_NAME), ' +
    '  TRIM(rc.RDB$CONSTRAINT_TYPE), TRIM(s.RDB$FIELD_NAME) ' +
    'FROM RDB$RELATION_CONSTRAINTS rc ' +
    'JOIN RDB$RELATIONS r ON r.RDB$RELATION_NAME = rc.RDB$RELATION_NAME ' +
    'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME ' +
    'WHERE COALESCE(r.RDB$SYSTEM_FLAG, 0) = 0 AND r.RDB$VIEW_BLR IS NULL ' +
    '  AND rc.RDB$CONSTRAINT_TYPE IN (''PRIMARY KEY'', ''UNIQUE'') ' +
    'ORDER BY rc.RDB$RELATION_NAME, rc.RDB$CONSTRAINT_NAME, s.RDB$FIELD_POSITION'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      Tbl := ASnap.FindTable(Row[0].AsText);
      if Tbl = nil then
        Continue;
      ConName := Trim(Row[1].AsText);
      ConType := UpperCase(Trim(Row[2].AsText));
      SegCol := Trim(Row[3].AsText);
      if ConType = 'PRIMARY KEY' then
      begin
        if Tbl.PrimaryKeyName = '' then
          Tbl.PrimaryKeyName := ConName;
        if SegCol <> '' then
        begin
          if Tbl.PrimaryKeyColumns <> '' then
            Tbl.PrimaryKeyColumns := Tbl.PrimaryKeyColumns + ', ';
          Tbl.PrimaryKeyColumns := Tbl.PrimaryKeyColumns + SegCol;
          for J := 0 to High(Tbl.Columns) do
            if SameText(Tbl.Columns[J].ColumnName, SegCol) then
            begin
              Tbl.Columns[J].IsPrimaryKey := True;
              Tbl.Columns[J].NotNull := True;
            end;
        end;
      end
      else
      begin
        IdxPos := -1;
        for J := 0 to High(Tbl.UniqueConstraints) do
          if SameText(Tbl.UniqueConstraints[J].ConstraintName, ConName) then
          begin
            IdxPos := J;
            Break;
          end;
        if IdxPos < 0 then
        begin
          IdxPos := Length(Tbl.UniqueConstraints);
          SetLength(Tbl.UniqueConstraints, IdxPos + 1);
          Tbl.UniqueConstraints[IdxPos].ConstraintName := ConName;
          Tbl.UniqueConstraints[IdxPos].Columns := SegCol;
        end
        else if SegCol <> '' then
          Tbl.UniqueConstraints[IdxPos].Columns := Tbl.UniqueConstraints[IdxPos].Columns + ', ' + SegCol;
      end;
    end;
  finally
    Res.Free;
  end;

  { 5. Foreign Keys em lote }
  Res := ExecChecked(
    'SELECT ' +
    '  TRIM(child_rc.RDB$RELATION_NAME), ' +
    '  TRIM(child_rc.RDB$CONSTRAINT_NAME), ' +
    '  TRIM(cs.RDB$FIELD_NAME), ' +
    '  TRIM(parent_rc.RDB$RELATION_NAME), ' +
    '  TRIM(ps.RDB$FIELD_NAME), ' +
    '  TRIM(COALESCE(ref.RDB$UPDATE_RULE, '''')), ' +
    '  TRIM(COALESCE(ref.RDB$DELETE_RULE, '''')) ' +
    'FROM RDB$RELATION_CONSTRAINTS child_rc ' +
    'JOIN RDB$REF_CONSTRAINTS ref ON ref.RDB$CONSTRAINT_NAME = child_rc.RDB$CONSTRAINT_NAME ' +
    'JOIN RDB$RELATION_CONSTRAINTS parent_rc ON parent_rc.RDB$CONSTRAINT_NAME = ref.RDB$CONST_NAME_UQ ' +
    'JOIN RDB$INDEX_SEGMENTS cs ON cs.RDB$INDEX_NAME = child_rc.RDB$INDEX_NAME ' +
    'JOIN RDB$INDEX_SEGMENTS ps ON ps.RDB$INDEX_NAME = parent_rc.RDB$INDEX_NAME AND ps.RDB$FIELD_POSITION = cs.RDB$FIELD_POSITION ' +
    'WHERE child_rc.RDB$CONSTRAINT_TYPE = ''FOREIGN KEY'' ' +
    'ORDER BY child_rc.RDB$RELATION_NAME, child_rc.RDB$CONSTRAINT_NAME, cs.RDB$FIELD_POSITION'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      Tbl := ASnap.FindTable(Row[0].AsText);
      if Tbl = nil then
        Continue;
      ConName := Trim(Row[1].AsText);
      FkCols := Trim(Row[2].AsText);
      RefTbl := Trim(Row[3].AsText);
      RefCols := Trim(Row[4].AsText);
      IdxPos := -1;
      for J := 0 to High(Tbl.ForeignKeys) do
        if SameText(Tbl.ForeignKeys[J].ConstraintName, ConName) then
        begin
          IdxPos := J;
          Break;
        end;
      if IdxPos < 0 then
      begin
        IdxPos := Length(Tbl.ForeignKeys);
        SetLength(Tbl.ForeignKeys, IdxPos + 1);
        Tbl.ForeignKeys[IdxPos].ConstraintName := ConName;
        Tbl.ForeignKeys[IdxPos].Columns := FkCols;
        Tbl.ForeignKeys[IdxPos].RefTable := RefTbl;
        Tbl.ForeignKeys[IdxPos].RefColumns := RefCols;
        Tbl.ForeignKeys[IdxPos].UpdateRule := Trim(Row[5].AsText);
        Tbl.ForeignKeys[IdxPos].DeleteRule := Trim(Row[6].AsText);
      end
      else
      begin
        if FkCols <> '' then
          Tbl.ForeignKeys[IdxPos].Columns := Tbl.ForeignKeys[IdxPos].Columns + ', ' + FkCols;
        if RefCols <> '' then
          Tbl.ForeignKeys[IdxPos].RefColumns := Tbl.ForeignKeys[IdxPos].RefColumns + ', ' + RefCols;
      end;
    end;
  finally
    Res.Free;
  end;

  { 6. Índices em lote }
  IdxSegMap := TStringList.Create;
  IdxSegMap.OwnsObjects := True;
  IdxSegMap.CaseSensitive := False;
  IdxSegMap.Sorted := True;
  try
    Res := ExecChecked(
      'SELECT TRIM(s.RDB$INDEX_NAME), TRIM(s.RDB$FIELD_NAME) ' +
      'FROM RDB$INDEX_SEGMENTS s ' +
      'JOIN RDB$INDICES i ON i.RDB$INDEX_NAME = s.RDB$INDEX_NAME ' +
      'WHERE COALESCE(i.RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY s.RDB$INDEX_NAME, s.RDB$FIELD_POSITION'
    );
    try
      for I := 0 to Res.RowCount - 1 do
      begin
        IdxName := Trim(Res.GetRow(I)[0].AsText);
        SegCol := Trim(Res.GetRow(I)[1].AsText);
        if not IdxSegMap.Find(IdxName, IdxPos) then
        begin
          CurList := TStringList.Create;
          IdxSegMap.AddObject(IdxName, CurList);
        end
        else
          CurList := TStringList(IdxSegMap.Objects[IdxPos]);
        if SegCol <> '' then
          CurList.Add(SegCol);
      end;
    finally
      Res.Free;
    end;

    Res := ExecChecked(
      'SELECT ' +
      '  TRIM(i.RDB$RELATION_NAME), ' +
      '  TRIM(i.RDB$INDEX_NAME), ' +
      '  COALESCE(i.RDB$UNIQUE_FLAG, 0), ' +
      '  COALESCE(i.RDB$INDEX_TYPE, 0), ' +
      '  COALESCE(i.RDB$INDEX_INACTIVE, 0), ' +
      '  TRIM(COALESCE(rc.RDB$CONSTRAINT_TYPE, '''')), ' +
      '  TRIM(COALESCE(rc.RDB$CONSTRAINT_NAME, '''')), ' +
      '  i.RDB$EXPRESSION_SOURCE ' +
      'FROM RDB$INDICES i ' +
      'LEFT JOIN RDB$RELATION_CONSTRAINTS rc ON rc.RDB$INDEX_NAME = i.RDB$INDEX_NAME ' +
      'WHERE COALESCE(i.RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY i.RDB$RELATION_NAME, i.RDB$INDEX_NAME'
    );
    try
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        Tbl := ASnap.FindTable(Row[0].AsText);
        if Tbl = nil then
          Continue;
        FillChar(IdxInfo, SizeOf(IdxInfo), 0);
        IdxInfo.IndexName := Trim(Row[1].AsText);
        IdxInfo.IsUnique := StrToIntDef(Trim(Row[2].AsText), 0) = 1;
        IdxInfo.IsDescending := StrToIntDef(Trim(Row[3].AsText), 0) = 1;
        IdxInfo.IsActive := StrToIntDef(Trim(Row[4].AsText), 0) = 0;
        ConType := Trim(Row[5].AsText);
        IdxInfo.ConstraintName := Trim(Row[6].AsText);
        IdxInfo.IsPrimaryKey := SameText(ConType, 'PRIMARY KEY');
        IdxInfo.IsForeignKey := SameText(ConType, 'FOREIGN KEY');
        if not Row[7].IsNull then
          IdxInfo.ExpressionSource := Trim(Row[7].AsText);
        if IdxSegMap.Find(IdxInfo.IndexName, IdxPos) then
        begin
          CurList := TStringList(IdxSegMap.Objects[IdxPos]);
          for J := 0 to CurList.Count - 1 do
          begin
            if IdxInfo.Columns <> '' then
              IdxInfo.Columns := IdxInfo.Columns + ', ';
            IdxInfo.Columns := IdxInfo.Columns + CurList[J];
          end;
        end;
        SetLength(Tbl.Indexes, Length(Tbl.Indexes) + 1);
        Tbl.Indexes[High(Tbl.Indexes)] := IdxInfo;
      end;
    finally
      Res.Free;
    end;
  finally
    IdxSegMap.Free;
  end;

  { 7. Views em lote }
  ViewColsMap := TStringList.Create;
  ViewColsMap.OwnsObjects := True;
  ViewColsMap.CaseSensitive := False;
  ViewColsMap.Sorted := True;
  try
    Res := ExecChecked(
      'SELECT TRIM(rf.RDB$RELATION_NAME), TRIM(rf.RDB$FIELD_NAME) ' +
      'FROM RDB$RELATION_FIELDS rf ' +
      'JOIN RDB$RELATIONS r ON r.RDB$RELATION_NAME = rf.RDB$RELATION_NAME ' +
      'WHERE COALESCE(r.RDB$SYSTEM_FLAG, 0) = 0 AND r.RDB$VIEW_BLR IS NOT NULL ' +
      'ORDER BY rf.RDB$RELATION_NAME, rf.RDB$FIELD_POSITION'
    );
    try
      for I := 0 to Res.RowCount - 1 do
      begin
        TblName := Trim(Res.GetRow(I)[0].AsText);
        SegCol := Trim(Res.GetRow(I)[1].AsText);
        if not ViewColsMap.Find(TblName, IdxPos) then
        begin
          CurList := TStringList.Create;
          ViewColsMap.AddObject(TblName, CurList);
        end
        else
          CurList := TStringList(ViewColsMap.Objects[IdxPos]);
        CurList.Add(SegCol);
      end;
    finally
      Res.Free;
    end;

    Res := ExecChecked(
      'SELECT TRIM(RDB$RELATION_NAME), RDB$VIEW_SOURCE ' +
      'FROM RDB$RELATIONS ' +
      'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NOT NULL ' +
      'ORDER BY 1'
    );
    try
      for I := 0 to Res.RowCount - 1 do
      begin
        TblName := Trim(Res.GetRow(I)[0].AsText);
        SrcText := Trim(Res.GetRow(I)[1].AsText);
        DDLText := 'CREATE OR ALTER VIEW ' + QuoteDbIdent(dtFirebird, TblName);
        if ViewColsMap.Find(TblName, IdxPos) then
        begin
          CurList := TStringList(ViewColsMap.Objects[IdxPos]);
          if CurList.Count > 0 then
          begin
            ParamStr := '';
            for J := 0 to CurList.Count - 1 do
            begin
              if ParamStr <> '' then
                ParamStr := ParamStr + ',' + LineEnding + '  ';
              ParamStr := ParamStr + QuoteDbIdent(dtFirebird, CurList[J]);
            end;
            DDLText := DDLText + ' (' + LineEnding + '  ' + ParamStr + LineEnding + ')';
          end;
        end;
        DDLText := DDLText + LineEnding + 'AS' + LineEnding + SrcText;
        ASnap.AddView(TblName, DDLText);
      end;
    finally
      Res.Free;
    end;
  finally
    ViewColsMap.Free;
  end;

  { 8. Procedures em lote }
  ProcInMap := TStringList.Create;
  ProcInMap.OwnsObjects := True;
  ProcInMap.CaseSensitive := False;
  ProcInMap.Sorted := True;
  ProcOutMap := TStringList.Create;
  ProcOutMap.OwnsObjects := True;
  ProcOutMap.CaseSensitive := False;
  ProcOutMap.Sorted := True;
  try
    Res := ExecChecked(
      'SELECT ' +
      '  TRIM(pp.RDB$PROCEDURE_NAME), ' +
      '  pp.RDB$PARAMETER_TYPE, ' +
      '  TRIM(pp.RDB$PARAMETER_NAME), ' +
      '  TRIM(pp.RDB$FIELD_SOURCE), ' +
      '  COALESCE(f.RDB$FIELD_TYPE, 0), ' +
      '  COALESCE(f.RDB$FIELD_SUB_TYPE, 0), ' +
      '  COALESCE(f.RDB$FIELD_LENGTH, 0), ' +
      '  COALESCE(f.RDB$FIELD_PRECISION, 0), ' +
      '  COALESCE(f.RDB$FIELD_SCALE, 0), ' +
      '  COALESCE(f.RDB$CHARACTER_LENGTH, 0) ' +
      'FROM RDB$PROCEDURE_PARAMETERS pp ' +
      'JOIN RDB$PROCEDURES p ON p.RDB$PROCEDURE_NAME = pp.RDB$PROCEDURE_NAME ' +
      'LEFT JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = pp.RDB$FIELD_SOURCE ' +
      'WHERE COALESCE(p.RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY pp.RDB$PROCEDURE_NAME, pp.RDB$PARAMETER_TYPE, pp.RDB$PARAMETER_NUMBER'
    );
    try
      for I := 0 to Res.RowCount - 1 do
      begin
        Row := Res.GetRow(I);
        TblName := Trim(Row[0].AsText);
        PType := StrToIntDef(Trim(Row[1].AsText), 0);
        ParamStr := '  ' + QuoteDbIdent(dtFirebird, Row[2].AsText) + ' ' +
          DecodeFirebirdFieldType(
            Row[3].AsText,
            StrToIntDef(Trim(Row[4].AsText), 0),
            StrToIntDef(Trim(Row[5].AsText), 0),
            StrToIntDef(Trim(Row[6].AsText), 0),
            StrToIntDef(Trim(Row[7].AsText), 0),
            StrToIntDef(Trim(Row[8].AsText), 0),
            StrToIntDef(Trim(Row[9].AsText), 0)
          );
        if PType = 0 then
        begin
          if not ProcInMap.Find(TblName, IdxPos) then
          begin
            CurList := TStringList.Create;
            ProcInMap.AddObject(TblName, CurList);
          end
          else
            CurList := TStringList(ProcInMap.Objects[IdxPos]);
          CurList.Add(ParamStr);
        end
        else
        begin
          if not ProcOutMap.Find(TblName, IdxPos) then
          begin
            CurList := TStringList.Create;
            ProcOutMap.AddObject(TblName, CurList);
          end
          else
            CurList := TStringList(ProcOutMap.Objects[IdxPos]);
          CurList.Add(ParamStr);
        end;
      end;
    finally
      Res.Free;
    end;

    Res := ExecChecked(
      'SELECT TRIM(RDB$PROCEDURE_NAME), RDB$PROCEDURE_SOURCE ' +
      'FROM RDB$PROCEDURES ' +
      'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ' +
      'ORDER BY 1'
    );
    try
      for I := 0 to Res.RowCount - 1 do
      begin
        TblName := Trim(Res.GetRow(I)[0].AsText);
        SrcText := Res.GetRow(I)[1].AsText;
        InP := '';
        if ProcInMap.Find(TblName, IdxPos) then
        begin
          CurList := TStringList(ProcInMap.Objects[IdxPos]);
          for J := 0 to CurList.Count - 1 do
          begin
            if InP <> '' then
              InP := InP + ',' + LineEnding;
            InP := InP + CurList[J];
          end;
        end;
        OutP := '';
        if ProcOutMap.Find(TblName, IdxPos) then
        begin
          CurList := TStringList(ProcOutMap.Objects[IdxPos]);
          for J := 0 to CurList.Count - 1 do
          begin
            if OutP <> '' then
              OutP := OutP + ',' + LineEnding;
            OutP := OutP + CurList[J];
          end;
        end;

        DDLText := 'CREATE OR ALTER PROCEDURE ' + QuoteDbIdent(dtFirebird, TblName);
        if InP <> '' then
          DDLText := DDLText + ' (' + LineEnding + InP + LineEnding + ')';
        if OutP <> '' then
          DDLText := DDLText + LineEnding + 'RETURNS (' + LineEnding + OutP + LineEnding + ')';
        if not StartsWithAsKw(SrcText) then
          DDLText := DDLText + LineEnding + 'AS';
        DDLText := DDLText + LineEnding + TrimRight(SrcText);
        ASnap.AddProcedure(TblName, DDLText);
      end;
    finally
      Res.Free;
    end;
  finally
    ProcOutMap.Free;
    ProcInMap.Free;
  end;

  { 9. Triggers em lote }
  Res := ExecChecked(
    'SELECT ' +
    '  TRIM(t.RDB$TRIGGER_NAME), ' +
    '  TRIM(COALESCE(t.RDB$RELATION_NAME, '''')), ' +
    '  COALESCE(t.RDB$TRIGGER_SEQUENCE, 0), ' +
    '  COALESCE(t.RDB$TRIGGER_TYPE, 0), ' +
    '  COALESCE(t.RDB$TRIGGER_INACTIVE, 0), ' +
    '  t.RDB$TRIGGER_SOURCE ' +
    'FROM RDB$TRIGGERS t ' +
    'WHERE COALESCE(t.RDB$SYSTEM_FLAG, 0) = 0 ' +
    '  AND NOT EXISTS (SELECT 1 FROM RDB$CHECK_CONSTRAINTS cc WHERE cc.RDB$TRIGGER_NAME = t.RDB$TRIGGER_NAME) ' +
    'ORDER BY t.RDB$TRIGGER_NAME'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      TblName := Trim(Row[0].AsText);
      RefTbl := Trim(Row[1].AsText);
      TrigSeq := StrToIntDef(Trim(Row[2].AsText), 0);
      TrigType := StrToIntDef(Trim(Row[3].AsText), 1);
      IsInactive := StrToIntDef(Trim(Row[4].AsText), 0);
      SrcText := Row[5].AsText;

      if IsInactive <> 0 then
        ActiveStr := 'INACTIVE'
      else
        ActiveStr := 'ACTIVE';
      EventsStr := DecodeFirebirdTriggerType(TrigType);

      DDLText := 'CREATE OR ALTER TRIGGER ' + QuoteDbIdent(dtFirebird, TblName);
      if RefTbl <> '' then
        DDLText := DDLText + ' FOR ' + QuoteDbIdent(dtFirebird, RefTbl);
      DDLText := DDLText + LineEnding + ActiveStr + ' ' + EventsStr + ' POSITION ' + IntToStr(TrigSeq);
      if not StartsWithAsKw(SrcText) then
        DDLText := DDLText + LineEnding + 'AS';
      DDLText := DDLText + LineEnding + TrimRight(SrcText);
      ASnap.AddTrigger(TblName, RefTbl, DDLText);
    end;
  finally
    Res.Free;
  end;
end;

procedure TDatabaseComparerUseCase.LoadPostgresSnapshot(
  const ASession: IDatabaseSession;
  const ASnap: TDatabaseSchemaSnapshot;
  const AWarnings: TStrings;
  const ACancelCheck: TCompareCancelCheck
);

  function ExecChecked(const ASQL: string): TQueryResult;
  begin
    if Assigned(ACancelCheck) and ACancelCheck() then
      raise Exception.Create('Comparação cancelada pelo usuário.');
    Result := ASession.ExecuteSQL(ASQL, False, 0);
    if not Result.Success then
    begin
      try
        raise Exception.Create(Result.MessageText);
      except
        Result.Free;
        raise;
      end;
    end;
  end;

var
  Res: TQueryResult;
  I: Integer;
  Row: TQueryRow;
  Tbl: TTableStructure;
  Col: TTableColumnInfo;
  IdxInfo: TTableIndexInfo;
  ConType, ViewKind, DefStr, DDLText: string;
begin
  { 1. Sequences }
  Res := ExecChecked(
    'SELECT sequence_name FROM information_schema.sequences ' +
    'WHERE sequence_schema = ''public'' ORDER BY 1'
  );
  try
    for I := 0 to Res.RowCount - 1 do
      ASnap.AddGenerator(Res.GetRow(I)[0].AsText);
  finally
    Res.Free;
  end;

  { 2. Tabelas }
  Res := ExecChecked(
    'SELECT table_name FROM information_schema.tables ' +
    'WHERE table_schema = ''public'' AND table_type = ''BASE TABLE'' ORDER BY 1'
  );
  try
    for I := 0 to Res.RowCount - 1 do
      ASnap.FindOrAddTable(Res.GetRow(I)[0].AsText);
  finally
    Res.Free;
  end;

  { 3. Colunas em lote }
  Res := ExecChecked(
    'SELECT ' +
    '  c.relname, ' +
    '  a.attnum, ' +
    '  a.attname, ' +
    '  format_type(a.atttypid, a.atttypmod), ' +
    '  CASE WHEN t.typtype = ''d'' THEN t.typname ELSE '''' END, ' +
    '  COALESCE(pg_get_expr(ad.adbin, ad.adrelid), ''''), ' +
    '  a.attnotnull ' +
    'FROM pg_attribute a ' +
    'JOIN pg_class c ON c.oid = a.attrelid AND c.relkind IN (''r'', ''p'') ' +
    'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'JOIN pg_type t ON t.oid = a.atttypid ' +
    'LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum ' +
    'WHERE n.nspname = ''public'' AND a.attnum > 0 AND NOT a.attisdropped ' +
    'ORDER BY c.relname, a.attnum'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      Tbl := ASnap.FindTable(Row[0].AsText);
      if Tbl = nil then
        Continue;
      FillChar(Col, SizeOf(Col), 0);
      Col.Position := StrToIntDef(Trim(Row[1].AsText), Length(Tbl.Columns) + 1);
      Col.ColumnName := Trim(Row[2].AsText);
      Col.DataType := Trim(Row[3].AsText);
      Col.DomainName := Trim(Row[4].AsText);
      Col.DefaultValue := Trim(Row[5].AsText);
      Col.NotNull := SameText(Trim(Row[6].AsText), 't') or SameText(Trim(Row[6].AsText), 'true') or (Trim(Row[6].AsText) = '1');
      SetLength(Tbl.Columns, Length(Tbl.Columns) + 1);
      Tbl.Columns[High(Tbl.Columns)] := Col;
    end;
  finally
    Res.Free;
  end;

  { 4. Constraints em lote }
  Res := ExecChecked(
    'SELECT ' +
    '  c.relname, ' +
    '  con.conname, ' +
    '  con.contype::text, ' +
    '  COALESCE((SELECT string_agg(a.attname, '', '' ORDER BY ord.pos) ' +
    '            FROM unnest(con.conkey) WITH ORDINALITY AS ord(attnum, pos) ' +
    '            JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ord.attnum), ''''), ' +
    '  COALESCE(ref_tbl.relname, ''''), ' +
    '  COALESCE((SELECT string_agg(pa.attname, '', '' ORDER BY pord.pos) ' +
    '            FROM unnest(con.confkey) WITH ORDINALITY AS pord(attnum, pos) ' +
    '            JOIN pg_attribute pa ON pa.attrelid = con.confrelid AND pa.attnum = pord.attnum), ''''), ' +
    '  CASE con.confupdtype WHEN ''c'' THEN ''CASCADE'' WHEN ''n'' THEN ''SET NULL'' WHEN ''d'' THEN ''SET DEFAULT'' WHEN ''r'' THEN ''RESTRICT'' ELSE ''NO ACTION'' END, ' +
    '  CASE con.confdeltype WHEN ''c'' THEN ''CASCADE'' WHEN ''n'' THEN ''SET NULL'' WHEN ''d'' THEN ''SET DEFAULT'' WHEN ''r'' THEN ''RESTRICT'' ELSE ''NO ACTION'' END, ' +
    '  pg_get_constraintdef(con.oid, true) ' +
    'FROM pg_constraint con ' +
    'JOIN pg_class c ON c.oid = con.conrelid ' +
    'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'LEFT JOIN pg_class ref_tbl ON ref_tbl.oid = con.confrelid ' +
    'WHERE n.nspname = ''public'' ' +
    'ORDER BY c.relname, con.contype, con.conname'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      Tbl := ASnap.FindTable(Row[0].AsText);
      if Tbl = nil then
        Continue;
      ConType := Trim(Row[2].AsText);
      if ConType = 'p' then
      begin
        Tbl.PrimaryKeyName := Trim(Row[1].AsText);
        Tbl.PrimaryKeyColumns := Trim(Row[3].AsText);
      end
      else if ConType = 'u' then
      begin
        SetLength(Tbl.UniqueConstraints, Length(Tbl.UniqueConstraints) + 1);
        Tbl.UniqueConstraints[High(Tbl.UniqueConstraints)].ConstraintName := Trim(Row[1].AsText);
        Tbl.UniqueConstraints[High(Tbl.UniqueConstraints)].Columns := Trim(Row[3].AsText);
      end
      else if ConType = 'f' then
      begin
        SetLength(Tbl.ForeignKeys, Length(Tbl.ForeignKeys) + 1);
        Tbl.ForeignKeys[High(Tbl.ForeignKeys)].ConstraintName := Trim(Row[1].AsText);
        Tbl.ForeignKeys[High(Tbl.ForeignKeys)].Columns := Trim(Row[3].AsText);
        Tbl.ForeignKeys[High(Tbl.ForeignKeys)].RefTable := Trim(Row[4].AsText);
        Tbl.ForeignKeys[High(Tbl.ForeignKeys)].RefColumns := Trim(Row[5].AsText);
        Tbl.ForeignKeys[High(Tbl.ForeignKeys)].UpdateRule := Trim(Row[6].AsText);
        Tbl.ForeignKeys[High(Tbl.ForeignKeys)].DeleteRule := Trim(Row[7].AsText);
      end
      else if ConType = 'c' then
      begin
        SetLength(Tbl.CheckConstraints, Length(Tbl.CheckConstraints) + 1);
        Tbl.CheckConstraints[High(Tbl.CheckConstraints)].ConstraintName := Trim(Row[1].AsText);
        Tbl.CheckConstraints[High(Tbl.CheckConstraints)].CheckSource := Trim(Row[8].AsText);
      end;
    end;
  finally
    Res.Free;
  end;

  { 5. Índices em lote }
  Res := ExecChecked(
    'SELECT ' +
    '  tbl.relname, ' +
    '  idx_cls.relname, ' +
    '  COALESCE(string_agg(att.attname, '', '' ORDER BY ord.pos), ''''), ' +
    '  COALESCE(pg_get_indexdef(idx.indexrelid), ''''), ' +
    '  idx.indisunique, ' +
    '  idx.indisprimary, ' +
    '  idx.indisvalid, ' +
    '  COALESCE((SELECT con.conname FROM pg_constraint con WHERE con.conindid = idx.indexrelid LIMIT 1), '''') ' +
    'FROM pg_index idx ' +
    'JOIN pg_class tbl ON tbl.oid = idx.indrelid ' +
    'JOIN pg_namespace n ON n.oid = tbl.relnamespace ' +
    'JOIN pg_class idx_cls ON idx_cls.oid = idx.indexrelid ' +
    'LEFT JOIN LATERAL unnest(idx.indkey) WITH ORDINALITY AS ord(attnum, pos) ON true ' +
    'LEFT JOIN pg_attribute att ON att.attrelid = tbl.oid AND att.attnum = ord.attnum AND ord.attnum > 0 ' +
    'WHERE n.nspname = ''public'' ' +
    'GROUP BY tbl.relname, idx_cls.relname, idx.indexrelid, idx.indisunique, idx.indisprimary, idx.indisvalid ' +
    'ORDER BY tbl.relname, idx_cls.relname'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      Tbl := ASnap.FindTable(Row[0].AsText);
      if Tbl = nil then
        Continue;
      FillChar(IdxInfo, SizeOf(IdxInfo), 0);
      IdxInfo.IndexName := Trim(Row[1].AsText);
      IdxInfo.Columns := Trim(Row[2].AsText);
      DefStr := Trim(Row[3].AsText);
      if IdxInfo.Columns = '' then
        IdxInfo.ExpressionSource := DefStr;
      IdxInfo.IsUnique := SameText(Trim(Row[4].AsText), 't') or SameText(Trim(Row[4].AsText), 'true') or (Trim(Row[4].AsText) = '1');
      IdxInfo.IsPrimaryKey := SameText(Trim(Row[5].AsText), 't') or SameText(Trim(Row[5].AsText), 'true') or (Trim(Row[5].AsText) = '1');
      IdxInfo.IsActive := SameText(Trim(Row[6].AsText), 't') or SameText(Trim(Row[6].AsText), 'true') or (Trim(Row[6].AsText) = '1');
      IdxInfo.ConstraintName := Trim(Row[7].AsText);
      IdxInfo.IsDescending := Pos(' DESC', UpperCase(DefStr)) > 0;
      SetLength(Tbl.Indexes, Length(Tbl.Indexes) + 1);
      Tbl.Indexes[High(Tbl.Indexes)] := IdxInfo;
    end;
  finally
    Res.Free;
  end;

  { 6. Views }
  Res := ExecChecked(
    'SELECT c.relname, c.relkind::text, pg_get_viewdef(c.oid, true) ' +
    'FROM pg_class c ' +
    'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE n.nspname = ''public'' AND c.relkind IN (''v'', ''m'') ORDER BY c.relname'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      ViewKind := Trim(Row[1].AsText);
      if ViewKind = 'm' then
        DDLText := 'CREATE MATERIALIZED VIEW ' + QuoteDbIdent(dtPostgreSQL, Row[0].AsText) + ' AS' + LineEnding + Trim(Row[2].AsText)
      else
        DDLText := 'CREATE OR REPLACE VIEW ' + QuoteDbIdent(dtPostgreSQL, Row[0].AsText) + ' AS' + LineEnding + Trim(Row[2].AsText);
      ASnap.AddView(Row[0].AsText, DDLText);
    end;
  finally
    Res.Free;
  end;

  { 7. Functions / Procedures }
  Res := ExecChecked(
    'SELECT p.proname, pg_get_functiondef(p.oid) ' +
    'FROM pg_proc p ' +
    'JOIN pg_namespace n ON n.oid = p.pronamespace ' +
    'WHERE n.nspname = ''public'' ' +
    '  AND NOT EXISTS (SELECT 1 FROM pg_aggregate a WHERE a.aggfnoid = p.oid) ' +
    'ORDER BY p.proname, p.oid'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      ASnap.AddProcedure(Row[0].AsText, TrimRight(Row[1].AsText));
    end;
  finally
    Res.Free;
  end;

  { 8. Triggers }
  Res := ExecChecked(
    'SELECT t.tgname, c.relname, pg_get_triggerdef(t.oid, true) ' +
    'FROM pg_trigger t ' +
    'JOIN pg_class c ON c.oid = t.tgrelid ' +
    'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE n.nspname = ''public'' AND NOT t.tgisinternal ' +
    'ORDER BY t.tgname'
  );
  try
    for I := 0 to Res.RowCount - 1 do
    begin
      Row := Res.GetRow(I);
      ASnap.AddTrigger(Row[0].AsText, Row[1].AsText, TrimRight(Row[2].AsText));
    end;
  finally
    Res.Free;
  end;
end;

function TDatabaseComparerUseCase.CaptureSnapshot(
  const AProfile: TConnectionProfile;
  const AWarnings: TStrings;
  const ACancelCheck: TCompareCancelCheck
): TDatabaseSchemaSnapshot;
var
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
begin
  if (AProfile = nil) or (FFactory = nil) then
    raise Exception.Create('Conexão inválida para captura de schema.');

  Result := TDatabaseSchemaSnapshot.Create;
  try
    Provider := FFactory.GetProvider(AProfile.DatabaseType);
    Session := Provider.CreateSession(AProfile);
    Session.Connect;
    try
      if AProfile.DatabaseType = dtPostgreSQL then
        LoadPostgresSnapshot(Session, Result, AWarnings, ACancelCheck)
      else
        LoadFirebirdSnapshot(Session, Result, AWarnings, ACancelCheck);
    finally
      try
        if Session.InTransaction then
          Session.Rollback;
        Session.Disconnect;
      except
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TDatabaseComparerUseCase.CompareDatabases(
  const ASourceProfile, ATargetProfile: TConnectionProfile;
  const AOptions: TCompareOptions;
  const AProgress: TCompareProgressCallback;
  const ACancelCheck: TCompareCancelCheck
): TCompareResult;
var
  StartTick: QWord;
  SrcSnap, TgtSnap: TDatabaseSchemaSnapshot;
  Warnings: TStringList;
  IsTargetFb25: Boolean;
begin
  if (ASourceProfile = nil) or (ATargetProfile = nil) then
    raise Exception.Create('Selecione as conexões de Origem e Destino.');
  if ASourceProfile.DatabaseType <> ATargetProfile.DatabaseType then
    raise Exception.Create('A comparação requer que ambas as bases sejam do mesmo SGBD (ambas Firebird ou ambas PostgreSQL).');
  if SameText(ASourceProfile.Id, ATargetProfile.Id) then
    raise Exception.Create('Selecione duas conexões diferentes para comparar.');

  StartTick := GetTickCount64;
  Warnings := TStringList.Create;
  SrcSnap := nil;
  TgtSnap := nil;
  try
    if Assigned(AProgress) then
      AProgress(Format('Lendo schema da base ORIGEM (%s)...', [ASourceProfile.Name]));
    SrcSnap := CaptureSnapshot(ASourceProfile, Warnings, ACancelCheck);

    if Assigned(AProgress) then
      AProgress(Format('Lendo schema da base DESTINO (%s)...', [ATargetProfile.Name]));
    TgtSnap := CaptureSnapshot(ATargetProfile, Warnings, ACancelCheck);

    if Assigned(AProgress) then
      AProgress('Comparando objetos e gerando script de atualização...');
    IsTargetFb25 := (ATargetProfile.DatabaseType = dtFirebird) and (ATargetProfile.FirebirdVersion = fv25);
    Result := CompareSnapshots(ATargetProfile.DatabaseType, IsTargetFb25, SrcSnap, TgtSnap, AOptions);
    Result.SourceProfileName := ASourceProfile.Name;
    Result.TargetProfileName := ATargetProfile.Name;
    Result.ElapsedMs := Int64(GetTickCount64 - StartTick);
    Result.Warnings.Assign(Warnings);
  finally
    TgtSnap.Free;
    SrcSnap.Free;
    Warnings.Free;
  end;
end;

{ TCompareDatabasesWorker }

constructor TCompareDatabasesWorker.Create(
  const AFactory: IDatabaseProviderFactory;
  const ASourceProfile, ATargetProfile: TConnectionProfile;
  const AOptions: TCompareOptions;
  const AOnProgress: TCompareProgressCallback;
  const AOnComplete: TCompareCompletedEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FFactory := AFactory;
  FSourceProfile := ASourceProfile.Clone;
  FTargetProfile := ATargetProfile.Clone;
  FOptions := AOptions;
  FOnProgress := AOnProgress;
  FOnComplete := AOnComplete;
  FDetached := False;
  FCancelRequested := False;
  FPendingStatus := '';
  FResult := nil;
  FErrorMessage := '';
end;

destructor TCompareDatabasesWorker.Destroy;
begin
  FreeAndNil(FResult);
  FSourceProfile.Free;
  FTargetProfile.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TCompareDatabasesWorker.RequestCancel;
begin
  FLock.Acquire;
  try
    FCancelRequested := True;
  finally
    FLock.Release;
  end;
end;

procedure TCompareDatabasesWorker.Detach;
begin
  FLock.Acquire;
  try
    FDetached := True;
    FCancelRequested := True;
    FOnProgress := nil;
    FOnComplete := nil;
  finally
    FLock.Release;
  end;
end;

function TCompareDatabasesWorker.CheckCancelled: Boolean;
begin
  FLock.Acquire;
  try
    Result := FCancelRequested or FDetached;
  finally
    FLock.Release;
  end;
end;

procedure TCompareDatabasesWorker.ReportProgress(const AStatus: string);
var
  DetachedCopy: Boolean;
begin
  FLock.Acquire;
  try
    DetachedCopy := FDetached;
    if not DetachedCopy then
      FPendingStatus := AStatus;
  finally
    FLock.Release;
  end;
  if not DetachedCopy then
    Queue(nil, @DeliverProgressOnMainThread);
end;

procedure TCompareDatabasesWorker.DeliverProgressOnMainThread;
var
  DetachedCopy: Boolean;
  Cb: TCompareProgressCallback;
  StatusCopy: string;
begin
  FLock.Acquire;
  try
    DetachedCopy := FDetached;
    Cb := FOnProgress;
    StatusCopy := FPendingStatus;
  finally
    FLock.Release;
  end;
  if (not DetachedCopy) and Assigned(Cb) and (StatusCopy <> '') then
    Cb(StatusCopy);
end;

procedure TCompareDatabasesWorker.Execute;
var
  UC: TDatabaseComparerUseCase;
begin
  UC := TDatabaseComparerUseCase.Create(FFactory);
  try
    try
      FResult := UC.CompareDatabases(
        FSourceProfile,
        FTargetProfile,
        FOptions,
        @ReportProgress,
        @CheckCancelled
      );
    except
      on E: Exception do
        FErrorMessage := E.Message;
    end;
  finally
    UC.Free;
  end;
  Queue(nil, @FinishOnMainThread);
end;

procedure TCompareDatabasesWorker.FinishOnMainThread;
var
  WasDetached: Boolean;
  Cb: TCompareCompletedEvent;
  ResCopy: TCompareResult;
  ErrCopy: string;
begin
  WaitFor;
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Cb := FOnComplete;
    FOnComplete := nil;
    FOnProgress := nil;
    ResCopy := FResult;
    FResult := nil;
    ErrCopy := FErrorMessage;
  finally
    FLock.Release;
  end;

  try
    if WasDetached or (not Assigned(Cb)) then
      ResCopy.Free
    else
      Cb(Self, ResCopy, ErrCopy);
  finally
    Free;
  end;
end;

{ TApplyCompareScriptWorker }

constructor TApplyCompareScriptWorker.Create(
  const AFactory: IDatabaseProviderFactory;
  const ATargetProfile: TConnectionProfile;
  const AScript: string;
  const AOnProgress: TApplyScriptProgressEvent;
  const AOnComplete: TApplyScriptCompletedEvent
);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FPendingLog := TStringList.Create;
  FFactory := AFactory;
  FTargetProfile := ATargetProfile.Clone;
  FScript := AScript;
  FOnProgress := AOnProgress;
  FOnComplete := AOnComplete;
  FDetached := False;
  FCancelRequested := False;
  FSuccess := False;
  FExecutedCount := 0;
  FErrorMessage := '';
end;

destructor TApplyCompareScriptWorker.Destroy;
begin
  FPendingLog.Free;
  FTargetProfile.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TApplyCompareScriptWorker.RequestCancel;
begin
  FLock.Acquire;
  try
    FCancelRequested := True;
  finally
    FLock.Release;
  end;
end;

procedure TApplyCompareScriptWorker.Detach;
begin
  FLock.Acquire;
  try
    FDetached := True;
    FCancelRequested := True;
    FOnProgress := nil;
    FOnComplete := nil;
  finally
    FLock.Release;
  end;
end;

procedure TApplyCompareScriptWorker.AppendLog(const ALine: string);
var
  DetachedCopy: Boolean;
begin
  FLock.Acquire;
  try
    DetachedCopy := FDetached;
    if not DetachedCopy then
      FPendingLog.Add(ALine);
  finally
    FLock.Release;
  end;
  if not DetachedCopy then
    Queue(nil, @DeliverLogOnMainThread);
end;

procedure TApplyCompareScriptWorker.DeliverLogOnMainThread;
var
  DetachedCopy: Boolean;
  Cb: TApplyScriptProgressEvent;
  LinesCopy: TStringList;
  I: Integer;
begin
  LinesCopy := TStringList.Create;
  try
    FLock.Acquire;
    try
      DetachedCopy := FDetached;
      Cb := FOnProgress;
      LinesCopy.Assign(FPendingLog);
      FPendingLog.Clear;
    finally
      FLock.Release;
    end;
    if (not DetachedCopy) and Assigned(Cb) then
    begin
      for I := 0 to LinesCopy.Count - 1 do
        Cb(LinesCopy[I]);
    end;
  finally
    LinesCopy.Free;
  end;
end;

procedure TApplyCompareScriptWorker.Execute;
var
  Stmts: TStringList;
  Provider: IDatabaseProvider;
  Session: IDatabaseSession;
  Res: TQueryResult;
  I: Integer;
  CancelCopy: Boolean;
  StmtPreview: string;
begin
  Stmts := TStringList.Create;
  try
    try
      SplitSqlScriptStatements(FScript, FTargetProfile.DatabaseType, Stmts);
      if Stmts.Count = 0 then
      begin
        FErrorMessage := 'Nenhum comando SQL executável encontrado no script.';
        Queue(nil, @FinishOnMainThread);
        Exit;
      end;

      Provider := FFactory.GetProvider(FTargetProfile.DatabaseType);
      Session := Provider.CreateSession(FTargetProfile);
      Session.Connect;
      try
        Session.StartTransaction;
        try
          for I := 0 to Stmts.Count - 1 do
          begin
            FLock.Acquire;
            try
              CancelCopy := FCancelRequested or FDetached;
            finally
              FLock.Release;
            end;
            if CancelCopy then
              raise Exception.Create('Aplicação do script cancelada pelo usuário.');

            StmtPreview := StringReplace(Trim(Stmts[I]), LineEnding, ' ', [rfReplaceAll]);
            if Length(StmtPreview) > 100 then
              StmtPreview := Copy(StmtPreview, 1, 100) + '...';
            AppendLog(Format('[%d/%d] Executando: %s', [I + 1, Stmts.Count, StmtPreview]));

            Res := Session.ExecuteSQL(Stmts[I], False, 0);
            try
              if not Res.Success then
                raise Exception.CreateFmt('Erro no comando %d/%d (%s): %s', [
                  I + 1, Stmts.Count, StmtPreview, Res.MessageText
                ]);
              Inc(FExecutedCount);
            finally
              Res.Free;
            end;
          end;

          Session.Commit;
          FSuccess := True;
          AppendLog(Format('Script aplicado com sucesso (%d comando(s), transação confirmada).', [FExecutedCount]));
        except
          on E: Exception do
          begin
            if Session.InTransaction then
            begin
              try
                Session.Rollback;
              except
              end;
            end;
            FSuccess := False;
            FErrorMessage := E.Message;
            AppendLog('ERRO (ROLLBACK executado): ' + E.Message);
          end;
        end;
      finally
        try
          Session.Disconnect;
        except
        end;
      end;
    except
      on E: Exception do
      begin
        FSuccess := False;
        if FErrorMessage = '' then
          FErrorMessage := E.Message;
      end;
    end;
  finally
    Stmts.Free;
  end;
  Queue(nil, @FinishOnMainThread);
end;

procedure TApplyCompareScriptWorker.FinishOnMainThread;
var
  WasDetached, SuccessCopy: Boolean;
  Cb: TApplyScriptCompletedEvent;
  ExecCountCopy: Integer;
  ErrCopy: string;
begin
  DeliverLogOnMainThread;
  WaitFor;
  FLock.Acquire;
  try
    WasDetached := FDetached;
    Cb := FOnComplete;
    FOnComplete := nil;
    FOnProgress := nil;
    SuccessCopy := FSuccess;
    ExecCountCopy := FExecutedCount;
    ErrCopy := FErrorMessage;
  finally
    FLock.Release;
  end;

  try
    if (not WasDetached) and Assigned(Cb) then
      Cb(Self, SuccessCopy, ExecCountCopy, ErrCopy);
  finally
    Free;
  end;
end;

end.
