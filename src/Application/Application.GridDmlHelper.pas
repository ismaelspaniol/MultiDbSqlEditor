unit Application.GridDmlHelper;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes,
  Domain.DatabaseTypes,
  Domain.ConnectionProfile,
  Domain.QueryResult,
  Domain.Interfaces,
  Application.ManageDatabaseObjectsUseCase;

type
  { Helper reutilizável para DML (UPDATE / INSERT / DELETE) a partir de grids editáveis }
  TGridDmlHelper = class
  private
    FTableName: string;
    FPKsLoaded: Boolean;
    FTablePKs: array of string;
    FWritableCols: array of string;
  public
    procedure Reset(const ATableName: string = '');
    procedure EnsureMetadataLoaded(const AProfile: TConnectionProfile; const ASession: IDatabaseSession);
    function IsWritableCol(const AColName: string): Boolean;
    class function FormatCellSqlLiteral(
      const ADbType: TDatabaseType;
      const AColType: string;
      const AIsNull: Boolean;
      const AValue: string
    ): string;
    function BuildWhereClause(
      const AProfile: TConnectionProfile;
      const ASession: IDatabaseSession;
      const AResult: TQueryResult;
      const AOldRow: TQueryRow
    ): string;
    function ExecuteUpdateCell(
      const AProfile: TConnectionProfile;
      const ASession: IDatabaseSession;
      const AResult: TQueryResult;
      const AColIndex: Integer;
      const AOldRow: TQueryRow;
      const ANewIsNull: Boolean;
      const ANewValue: string;
      const AAutoCommit: Boolean;
      out AExecutedSQL: string;
      out AError: string
    ): Boolean;
    function ExecuteInsertRow(
      const AProfile: TConnectionProfile;
      const ASession: IDatabaseSession;
      const AResult: TQueryResult;
      const ANewRow: TQueryRow;
      const AAutoCommit: Boolean;
      out AExecutedSQL: string;
      out AError: string
    ): Boolean;
    function ExecuteDeleteRow(
      const AProfile: TConnectionProfile;
      const ASession: IDatabaseSession;
      const AResult: TQueryResult;
      const AOldRow: TQueryRow;
      const AAutoCommit: Boolean;
      out AExecutedSQL: string;
      out AError: string
    ): Boolean;

    property TableName: string read FTableName;
  end;

implementation

procedure TGridDmlHelper.Reset(const ATableName: string);
begin
  FTableName := Trim(ATableName);
  FPKsLoaded := False;
  SetLength(FTablePKs, 0);
  SetLength(FWritableCols, 0);
end;

procedure TGridDmlHelper.EnsureMetadataLoaded(
  const AProfile: TConnectionProfile;
  const ASession: IDatabaseSession
);
var
  SQL, SafeTbl: string;
  Res: TQueryResult;
  I: Integer;
begin
  if FPKsLoaded or (FTableName = '') or (AProfile = nil) or (ASession = nil) then
    Exit;
  FPKsLoaded := True;
  SetLength(FTablePKs, 0);
  SetLength(FWritableCols, 0);

  SafeTbl := StringReplace(FTableName, '''', '''''', [rfReplaceAll]);
  if AProfile.DatabaseType = dtPostgreSQL then
    SQL := Format(
      'SELECT a.attname ' +
      'FROM pg_constraint con ' +
      'JOIN pg_class c ON c.oid = con.conrelid ' +
      'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'JOIN unnest(con.conkey) WITH ORDINALITY AS ord(attnum, pos) ON true ' +
      'JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ord.attnum ' +
      'WHERE n.nspname = current_schema() AND lower(c.relname) = lower(''%s'') AND con.contype = ''p'' ' +
      'ORDER BY ord.pos',
      [SafeTbl]
    )
  else if AProfile.DatabaseType = dtMariaDB then
    SQL := Format(
      'SELECT column_name ' +
      'FROM information_schema.key_column_usage ' +
      'WHERE table_schema = DATABASE() AND LOWER(table_name) = LOWER(''%s'') ' +
      '  AND constraint_name = ''PRIMARY'' ' +
      'ORDER BY ordinal_position',
      [SafeTbl]
    )
  else
    SQL := Format(
      'SELECT TRIM(s.RDB$FIELD_NAME) ' +
      'FROM RDB$RELATION_CONSTRAINTS rc ' +
      'JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME ' +
      'WHERE UPPER(TRIM(rc.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND rc.RDB$CONSTRAINT_TYPE = ''PRIMARY KEY'' ' +
      'ORDER BY s.RDB$FIELD_POSITION',
      [SafeTbl]
    );

  try
    Res := ASession.ExecuteSQL(SQL, False, 0);
    if Res <> nil then
    begin
      try
        if Res.Success then
        begin
          SetLength(FTablePKs, Res.RowCount);
          for I := 0 to Res.RowCount - 1 do
            FTablePKs[I] := Trim(Res.GetRow(I)[0].AsText);
        end;
      finally
        Res.Free;
      end;
    end;
  except
    SetLength(FTablePKs, 0);
  end;

  if AProfile.DatabaseType = dtPostgreSQL then
    SQL := Format(
      'SELECT a.attname ' +
      'FROM pg_attribute a ' +
      'JOIN pg_class c ON c.oid = a.attrelid ' +
      'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
      'WHERE n.nspname = current_schema() AND lower(c.relname) = lower(''%s'') AND a.attnum > 0 AND NOT a.attisdropped',
      [SafeTbl]
    )
  else if AProfile.DatabaseType = dtMariaDB then
    SQL := Format(
      'SELECT column_name ' +
      'FROM information_schema.columns ' +
      'WHERE table_schema = DATABASE() AND LOWER(table_name) = LOWER(''%s'') ' +
      '  AND UPPER(COALESCE(extra, '''')) NOT LIKE ''%%VIRTUAL%%'' ' +
      '  AND UPPER(COALESCE(extra, '''')) NOT LIKE ''%%STORED%%''',
      [SafeTbl]
    )
  else
    SQL := Format(
      'SELECT TRIM(rf.RDB$FIELD_NAME) ' +
      'FROM RDB$RELATION_FIELDS rf ' +
      'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE ' +
      'WHERE UPPER(TRIM(rf.RDB$RELATION_NAME)) = UPPER(''%s'') ' +
      '  AND f.RDB$COMPUTED_SOURCE IS NULL',
      [SafeTbl]
    );

  try
    Res := ASession.ExecuteSQL(SQL, False, 0);
    if Res <> nil then
    begin
      try
        if Res.Success then
        begin
          SetLength(FWritableCols, Res.RowCount);
          for I := 0 to Res.RowCount - 1 do
            FWritableCols[I] := Trim(Res.GetRow(I)[0].AsText);
        end;
      finally
        Res.Free;
      end;
    end;
  except
    SetLength(FWritableCols, 0);
  end;
end;

function TGridDmlHelper.IsWritableCol(const AColName: string): Boolean;
var
  I: Integer;
begin
  if Length(FWritableCols) = 0 then
    Exit(True);
  for I := 0 to High(FWritableCols) do
    if SameText(FWritableCols[I], AColName) then
      Exit(True);
  Result := False;
end;

class function TGridDmlHelper.FormatCellSqlLiteral(
  const ADbType: TDatabaseType;
  const AColType: string;
  const AIsNull: Boolean;
  const AValue: string
): string;
var
  UpperT, NormNum: string;
  IVal: Int64;
  FVal: Double;
  FS: TFormatSettings;
begin
  if AIsNull then
    Exit('NULL');
  UpperT := UpperCase(AColType);
  if (Pos('INT', UpperT) > 0) or (Pos('SMALLINT', UpperT) > 0) or (Pos('BIGINT', UpperT) > 0) then
  begin
    if TryStrToInt64(Trim(AValue), IVal) then
      Exit(IntToStr(IVal));
  end;
  if (Pos('FLOAT', UpperT) > 0) or (Pos('BCD', UpperT) > 0) or
     (Pos('FMTBCD', UpperT) > 0) or (Pos('NUMERIC', UpperT) > 0) or
     (Pos('DECIMAL', UpperT) > 0) or (Pos('DOUBLE', UpperT) > 0) then
  begin
    NormNum := StringReplace(Trim(AValue), ',', '.', [rfReplaceAll]);
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    if TryStrToFloat(NormNum, FVal, FS) then
      Exit(NormNum);
  end;
  if (Pos('BOOL', UpperT) > 0) and (ADbType = dtPostgreSQL) then
  begin
    if SameText(Trim(AValue), 'true') or (Trim(AValue) = '1') or SameText(Trim(AValue), 't') then
      Exit('TRUE')
    else if SameText(Trim(AValue), 'false') or (Trim(AValue) = '0') or SameText(Trim(AValue), 'f') then
      Exit('FALSE');
  end;
  Result := '''' + StringReplace(AValue, '''', '''''', [rfReplaceAll]) + '''';
end;

function TGridDmlHelper.BuildWhereClause(
  const AProfile: TConnectionProfile;
  const ASession: IDatabaseSession;
  const AResult: TQueryResult;
  const AOldRow: TQueryRow
): string;
var
  I, K, ColIdx: Integer;
  Col: TQueryColumn;
  Cond: string;
  UsedPK: Boolean;
begin
  Result := '';
  if (AResult = nil) or (AProfile = nil) then
    Exit;

  EnsureMetadataLoaded(AProfile, ASession);
  UsedPK := False;

  if Length(FTablePKs) > 0 then
  begin
    for I := 0 to High(FTablePKs) do
    begin
      ColIdx := -1;
      for K := 0 to AResult.ColumnCount - 1 do
        if SameText(AResult.GetColumn(K).Name, FTablePKs[I]) then
        begin
          ColIdx := K;
          Break;
        end;
      if ColIdx < 0 then
      begin
        Result := '';
        Break;
      end;
      Col := AResult.GetColumn(ColIdx);
      if (ColIdx >= Length(AOldRow)) or AOldRow[ColIdx].IsNull then
        Cond := QuoteDbIdent(AProfile.DatabaseType, Col.Name) + ' IS NULL'
      else
        Cond := QuoteDbIdent(AProfile.DatabaseType, Col.Name) + ' = ' +
          FormatCellSqlLiteral(AProfile.DatabaseType, Col.DataTypeName, False, AOldRow[ColIdx].AsText);
      if Result <> '' then
        Result := Result + ' AND ';
      Result := Result + Cond;
      UsedPK := True;
    end;
  end;

  if not UsedPK then
  begin
    Result := '';
    for I := 0 to AResult.ColumnCount - 1 do
    begin
      Col := AResult.GetColumn(I);
      if Pos('BLOB', UpperCase(Col.DataTypeName)) > 0 then
        Continue;
      if (I >= Length(AOldRow)) or AOldRow[I].IsNull then
        Cond := QuoteDbIdent(AProfile.DatabaseType, Col.Name) + ' IS NULL'
      else
        Cond := QuoteDbIdent(AProfile.DatabaseType, Col.Name) + ' = ' +
          FormatCellSqlLiteral(AProfile.DatabaseType, Col.DataTypeName, False, AOldRow[I].AsText);
      if Result <> '' then
        Result := Result + ' AND ';
      Result := Result + Cond;
    end;
  end;
end;

function TGridDmlHelper.ExecuteUpdateCell(
  const AProfile: TConnectionProfile;
  const ASession: IDatabaseSession;
  const AResult: TQueryResult;
  const AColIndex: Integer;
  const AOldRow: TQueryRow;
  const ANewIsNull: Boolean;
  const ANewValue: string;
  const AAutoCommit: Boolean;
  out AExecutedSQL: string;
  out AError: string
): Boolean;
var
  Col: TQueryColumn;
  WhereSQL: string;
  Res: TQueryResult;
begin
  Result := False;
  AExecutedSQL := '';
  AError := '';
  if (AProfile = nil) or (ASession = nil) or (AResult = nil) or (FTableName = '') then
  begin
    AError := 'Tabela editável não identificada.';
    Exit;
  end;

  WhereSQL := BuildWhereClause(AProfile, ASession, AResult, AOldRow);
  if WhereSQL = '' then
  begin
    AError := 'Não foi possível montar a cláusula WHERE para atualizar esta linha.';
    Exit;
  end;

  Col := AResult.GetColumn(AColIndex);
  if not IsWritableCol(Col.Name) then
  begin
    AError := Format('A coluna "%s" é calculada (COMPUTED BY) ou um alias de consulta e não pode ser alterada.', [Col.Name]);
    Exit;
  end;

  AExecutedSQL := Format('UPDATE %s SET %s = %s WHERE %s', [
    QuoteDbIdent(AProfile.DatabaseType, FTableName),
    QuoteDbIdent(AProfile.DatabaseType, Col.Name),
    FormatCellSqlLiteral(AProfile.DatabaseType, Col.DataTypeName, ANewIsNull, ANewValue),
    WhereSQL
  ]);

  Res := ASession.ExecuteSQL(AExecutedSQL, AAutoCommit, 0);
  try
    if not Res.Success then
    begin
      AError := Res.MessageText;
      Exit;
    end;
    Result := True;
  finally
    Res.Free;
  end;
end;

function TGridDmlHelper.ExecuteInsertRow(
  const AProfile: TConnectionProfile;
  const ASession: IDatabaseSession;
  const AResult: TQueryResult;
  const ANewRow: TQueryRow;
  const AAutoCommit: Boolean;
  out AExecutedSQL: string;
  out AError: string
): Boolean;
var
  ColsSQL, ValsSQL: string;
  I: Integer;
  Col: TQueryColumn;
  Res: TQueryResult;
begin
  Result := False;
  AExecutedSQL := '';
  AError := '';
  if (AProfile = nil) or (ASession = nil) or (AResult = nil) or (FTableName = '') then
  begin
    AError := 'Tabela editável não identificada.';
    Exit;
  end;

  EnsureMetadataLoaded(AProfile, ASession);
  ColsSQL := '';
  ValsSQL := '';
  for I := 0 to AResult.ColumnCount - 1 do
  begin
    if (I < Length(ANewRow)) and (not ANewRow[I].IsNull) then
    begin
      Col := AResult.GetColumn(I);
      if not IsWritableCol(Col.Name) then
        Continue;
      if ColsSQL <> '' then
      begin
        ColsSQL := ColsSQL + ', ';
        ValsSQL := ValsSQL + ', ';
      end;
      ColsSQL := ColsSQL + QuoteDbIdent(AProfile.DatabaseType, Col.Name);
      ValsSQL := ValsSQL + FormatCellSqlLiteral(AProfile.DatabaseType, Col.DataTypeName, False, ANewRow[I].AsText);
    end;
  end;

  if ColsSQL = '' then
  begin
    AError := 'Preencha ao menos uma coluna antes de gravar a nova linha.';
    Exit;
  end;

  AExecutedSQL := Format('INSERT INTO %s (%s) VALUES (%s)', [
    QuoteDbIdent(AProfile.DatabaseType, FTableName),
    ColsSQL,
    ValsSQL
  ]);

  Res := ASession.ExecuteSQL(AExecutedSQL, AAutoCommit, 0);
  try
    if not Res.Success then
    begin
      AError := Res.MessageText;
      Exit;
    end;
    Result := True;
  finally
    Res.Free;
  end;
end;

function TGridDmlHelper.ExecuteDeleteRow(
  const AProfile: TConnectionProfile;
  const ASession: IDatabaseSession;
  const AResult: TQueryResult;
  const AOldRow: TQueryRow;
  const AAutoCommit: Boolean;
  out AExecutedSQL: string;
  out AError: string
): Boolean;
var
  WhereSQL: string;
  Res: TQueryResult;
begin
  Result := False;
  AExecutedSQL := '';
  AError := '';
  if (AProfile = nil) or (ASession = nil) or (AResult = nil) or (FTableName = '') then
  begin
    AError := 'Tabela editável não identificada.';
    Exit;
  end;

  WhereSQL := BuildWhereClause(AProfile, ASession, AResult, AOldRow);
  if WhereSQL = '' then
  begin
    AError := 'Não foi possível montar a cláusula WHERE para excluir esta linha.';
    Exit;
  end;

  AExecutedSQL := Format('DELETE FROM %s WHERE %s', [
    QuoteDbIdent(AProfile.DatabaseType, FTableName),
    WhereSQL
  ]);

  Res := ASession.ExecuteSQL(AExecutedSQL, AAutoCommit, 0);
  try
    if not Res.Success then
    begin
      AError := Res.MessageText;
      Exit;
    end;
    Result := True;
  finally
    Res.Free;
  end;
end;

end.
