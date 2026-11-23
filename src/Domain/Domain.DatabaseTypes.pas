unit Domain.DatabaseTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TDatabaseType = (
    dtFirebird,
    dtPostgreSQL,
    dtMariaDB
  );

  TFirebirdVersion = (
    fvAuto,
    fv50,
    fv40,
    fv30,
    fv25
  );

  TSchemaObjectKind = (
    sokTables,
    sokViews,
    sokProcedures,
    sokTriggers,
    sokGenerators
  );

function DatabaseTypeToStr(const AType: TDatabaseType): string;
function StrToDatabaseType(const AValue: string): TDatabaseType;
function DefaultPortForDatabase(const AType: TDatabaseType): Word;
function FirebirdVersionToStr(const AVer: TFirebirdVersion): string;
function StrToFirebirdVersion(const AValue: string): TFirebirdVersion;
function FirebirdVersionFolder(const AVer: TFirebirdVersion): string;
function SchemaObjectKindToStr(const AKind: TSchemaObjectKind): string;

implementation

function DatabaseTypeToStr(const AType: TDatabaseType): string;
begin
  case AType of
    dtFirebird: Result := 'Firebird';
    dtPostgreSQL: Result := 'PostgreSQL';
    dtMariaDB: Result := 'MariaDB';
  else
    Result := 'Unknown';
  end;
end;

function StrToDatabaseType(const AValue: string): TDatabaseType;
var
  Normalized: string;
begin
  Normalized := LowerCase(Trim(AValue));
  if Normalized = 'firebird' then
    Result := dtFirebird
  else if (Normalized = 'postgresql') or (Normalized = 'postgres') then
    Result := dtPostgreSQL
  else if (Normalized = 'mariadb') or (Normalized = 'mysql') then
    Result := dtMariaDB
  else
    raise Exception.CreateFmt('Tipo de banco de dados não suportado: %s', [AValue]);
end;

function DefaultPortForDatabase(const AType: TDatabaseType): Word;
begin
  case AType of
    dtFirebird: Result := 3050;
    dtPostgreSQL: Result := 5432;
    dtMariaDB: Result := 3306;
  else
    Result := 0;
  end;
end;

function FirebirdVersionToStr(const AVer: TFirebirdVersion): string;
begin
  case AVer of
    fvAuto: Result := 'Auto';
    fv50: Result := '5.0';
    fv40: Result := '4.0';
    fv30: Result := '3.0';
    fv25: Result := '2.5';
  else
    Result := 'Auto';
  end;
end;

function StrToFirebirdVersion(const AValue: string): TFirebirdVersion;
var
  S: string;
begin
  S := LowerCase(Trim(AValue));
  if (S = '5.0') or (S = '5') or (S = 'firebird 5.0') then
    Result := fv50
  else if (S = '4.0') or (S = '4') or (S = 'firebird 4.0') then
    Result := fv40
  else if (S = '3.0') or (S = '3') or (S = 'firebird 3.0') then
    Result := fv30
  else if (S = '2.5') or (S = 'firebird 2.5') then
    Result := fv25
  else
    Result := fvAuto;
end;

function FirebirdVersionFolder(const AVer: TFirebirdVersion): string;
begin
  case AVer of
    fv50: Result := '5.0';
    fv40: Result := '4.0';
    fv30: Result := '3.0';
    fv25: Result := '2.5';
  else
    Result := '';
  end;
end;

function SchemaObjectKindToStr(const AKind: TSchemaObjectKind): string;
begin
  case AKind of
    sokTables: Result := 'Tabelas';
    sokViews: Result := 'Views';
    sokProcedures: Result := 'Procedures';
    sokTriggers: Result := 'Triggers';
    sokGenerators: Result := 'Generators / Sequences';
  else
    Result := 'Outros';
  end;
end;

end.
