unit Domain.TableStructureTypes;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TTableColumnInfo = record
    Position: Integer;
    ColumnName: string;
    DataType: string;
    DomainName: string;
    DefaultValue: string;
    ComputedSource: string;
    Description: string;
    NotNull: Boolean;
    IsPrimaryKey: Boolean;
    IsComputed: Boolean;
  end;
  TTableColumnInfoArray = array of TTableColumnInfo;

  TTableIndexInfo = record
    IndexName: string;
    Columns: string;
    ExpressionSource: string;
    ConstraintName: string;
    IsUnique: Boolean;
    IsPrimaryKey: Boolean;
    IsForeignKey: Boolean;
    IsDescending: Boolean;
    IsActive: Boolean;
  end;
  TTableIndexInfoArray = array of TTableIndexInfo;

  TTableDependencyDirection = (tddDependentOnTable, tddTableDependsOn);

  TTableDependencyInfo = record
    Direction: TTableDependencyDirection;
    ObjectName: string;
    ObjectType: string;
    FieldOrDetail: string;
  end;
  TTableDependencyInfoArray = array of TTableDependencyInfo;

  TTableForeignKeyInfo = record
    ConstraintName: string;
    Columns: string;
    RefTable: string;
    RefColumns: string;
    UpdateRule: string;
    DeleteRule: string;
  end;
  TTableForeignKeyInfoArray = array of TTableForeignKeyInfo;

  TTableUniqueConstraintInfo = record
    ConstraintName: string;
    Columns: string;
  end;
  TTableUniqueConstraintInfoArray = array of TTableUniqueConstraintInfo;

  TTableCheckConstraintInfo = record
    ConstraintName: string;
    CheckSource: string;
  end;
  TTableCheckConstraintInfoArray = array of TTableCheckConstraintInfo;

  TTableTriggerInfo = record
    TriggerName: string;
    Timing: string;       // 'BEFORE', 'AFTER', 'INSTEAD OF'
    Events: string;       // 'INSERT', 'UPDATE', 'DELETE', 'INSERT OR UPDATE', ...
    HasInsert: Boolean;
    HasUpdate: Boolean;
    HasDelete: Boolean;
    Position: Integer;
    IsActive: Boolean;
    SourceBody: string;   // Firebird: RDB$TRIGGER_SOURCE; PostgreSQL: pg_get_triggerdef
    FullDDL: string;      // Complete CREATE [OR ALTER] TRIGGER ...
    FunctionName: string; // PostgreSQL trigger function name (empty on Firebird)
  end;
  TTableTriggerInfoArray = array of TTableTriggerInfo;

  { Estrutura completa de uma tabela (campos, índices, constraints, triggers e dependências) }
  TTableStructure = class
  public
    TableName: string;
    PrimaryKeyName: string;
    PrimaryKeyColumns: string;
    Columns: TTableColumnInfoArray;
    Indexes: TTableIndexInfoArray;
    ForeignKeys: TTableForeignKeyInfoArray;
    UniqueConstraints: TTableUniqueConstraintInfoArray;
    CheckConstraints: TTableCheckConstraintInfoArray;
    Triggers: TTableTriggerInfoArray;
    Dependencies: TTableDependencyInfoArray;
    constructor Create;
    procedure Clear;
  end;

implementation

constructor TTableStructure.Create;
begin
  inherited Create;
  Clear;
end;

procedure TTableStructure.Clear;
begin
  TableName := '';
  PrimaryKeyName := '';
  PrimaryKeyColumns := '';
  SetLength(Columns, 0);
  SetLength(Indexes, 0);
  SetLength(ForeignKeys, 0);
  SetLength(UniqueConstraints, 0);
  SetLength(CheckConstraints, 0);
  SetLength(Triggers, 0);
  SetLength(Dependencies, 0);
end;

end.
