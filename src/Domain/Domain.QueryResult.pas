unit Domain.QueryResult;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TQueryResult = class;

  TQueryColumn = record
    Name: string;
    DataTypeName: string;
    IsNullable: Boolean;
  end;

  TQueryCell = record
    IsNull: Boolean;
    AsText: string;
  end;

  TQueryRow = array of TQueryCell;

  { Cursor para carregamento sob demanda (paginação estilo IBExpert/DBeaver) }
  IResultSetCursor = interface
    ['{8F6A52F0-8A2C-4E1C-A31B-6C9E01B5A010}']
    function HasMore: Boolean;
    function FetchNext(const ABatchSize: Integer; const ATarget: TQueryResult): Integer;
    procedure CloseCursor;
  end;

  { Resultado padronizado de execução SQL (SELECT, DML ou DDL) }
  TQueryResult = class
  private
    FSuccess: Boolean;
    FHasResultSet: Boolean;
    FColumns: array of TQueryColumn;
    FRows: array of TQueryRow;
    FRowsAffected: Int64;
    FExecutionTimeMs: Int64;
    FMessageText: string;
    FErrorCode: Integer;
    FCursor: IResultSetCursor;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetColumns(const AColumns: array of TQueryColumn);
    procedure AddRow(const ARow: TQueryRow);
    function ColumnCount: Integer;
    function RowCount: Integer;
    function GetColumn(const AIndex: Integer): TQueryColumn;
    function GetRow(const AIndex: Integer): TQueryRow;
    function HasMoreRows: Boolean;
    function FetchMore(const ABatchSize: Integer = 100): Integer;
    function FetchAll: Integer;
    procedure SortByColumn(const AColIndex: Integer; const AAscending: Boolean);
    procedure CloseCursor;

    property Success: Boolean read FSuccess write FSuccess;
    property HasResultSet: Boolean read FHasResultSet write FHasResultSet;
    property RowsAffected: Int64 read FRowsAffected write FRowsAffected;
    property ExecutionTimeMs: Int64 read FExecutionTimeMs write FExecutionTimeMs;
    property MessageText: string read FMessageText write FMessageText;
    property ErrorCode: Integer read FErrorCode write FErrorCode;
    property Cursor: IResultSetCursor read FCursor write FCursor;
  end;

implementation

constructor TQueryResult.Create;
begin
  inherited Create;
  FSuccess := False;
  FHasResultSet := False;
  FRowsAffected := 0;
  FExecutionTimeMs := 0;
  FErrorCode := 0;
  FCursor := nil;
end;

destructor TQueryResult.Destroy;
begin
  CloseCursor;
  inherited Destroy;
end;

procedure TQueryResult.SetColumns(const AColumns: array of TQueryColumn);
var
  I: Integer;
begin
  SetLength(FColumns, Length(AColumns));
  for I := 0 to High(AColumns) do
    FColumns[I] := AColumns[I];
end;

procedure TQueryResult.AddRow(const ARow: TQueryRow);
var
  Idx: Integer;
begin
  Idx := Length(FRows);
  SetLength(FRows, Idx + 1);
  FRows[Idx] := ARow;
end;

function TQueryResult.ColumnCount: Integer;
begin
  Result := Length(FColumns);
end;

function TQueryResult.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TQueryResult.GetColumn(const AIndex: Integer): TQueryColumn;
begin
  Result := FColumns[AIndex];
end;

function TQueryResult.GetRow(const AIndex: Integer): TQueryRow;
begin
  Result := FRows[AIndex];
end;

function TQueryResult.HasMoreRows: Boolean;
begin
  Result := (FCursor <> nil) and FCursor.HasMore;
end;

function TQueryResult.FetchMore(const ABatchSize: Integer): Integer;
begin
  if not HasMoreRows then
  begin
    Result := 0;
    Exit;
  end;
  Result := FCursor.FetchNext(ABatchSize, Self);
  FRowsAffected := RowCount;
end;

function TQueryResult.FetchAll: Integer;
var
  StepCount: Integer;
begin
  Result := 0;
  while HasMoreRows do
  begin
    StepCount := FCursor.FetchNext(1000, Self);
    if StepCount <= 0 then
      Break;
    Inc(Result, StepCount);
  end;
  FRowsAffected := RowCount;
end;

procedure TQueryResult.SortByColumn(const AColIndex: Integer; const AAscending: Boolean);
var
  InvFormat: TFormatSettings;

  function CompareCells(const A, B: TQueryCell): Integer;
  var
    NumA, NumB: Double;
    IsNumA, IsNumB: Boolean;
  begin
    if A.IsNull and B.IsNull then
    begin
      Result := 0;
      Exit;
    end;
    if A.IsNull then
    begin
      Result := 1; // NULLs por último
      Exit;
    end;
    if B.IsNull then
    begin
      Result := -1;
      Exit;
    end;

    IsNumA := TryStrToFloat(A.AsText, NumA, InvFormat) or TryStrToFloat(A.AsText, NumA);
    IsNumB := TryStrToFloat(B.AsText, NumB, InvFormat) or TryStrToFloat(B.AsText, NumB);
    if IsNumA and IsNumB then
    begin
      if NumA < NumB then
        Result := -1
      else if NumA > NumB then
        Result := 1
      else
        Result := 0;
    end
    else
      Result := AnsiCompareText(A.AsText, B.AsText);

    if not AAscending then
      Result := -Result;
  end;

  procedure QuickSortRows(L, R: Integer);
  var
    I, J: Integer;
    Pivot, Temp: TQueryRow;
  begin
    I := L;
    J := R;
    Pivot := FRows[(L + R) div 2];
    repeat
      while CompareCells(FRows[I][AColIndex], Pivot[AColIndex]) < 0 do
        Inc(I);
      while CompareCells(FRows[J][AColIndex], Pivot[AColIndex]) > 0 do
        Dec(J);
      if I <= J then
      begin
        if I <> J then
        begin
          Temp := FRows[I];
          FRows[I] := FRows[J];
          FRows[J] := Temp;
        end;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then
      QuickSortRows(L, J);
    if I < R then
      QuickSortRows(I, R);
  end;

begin
  if (AColIndex < 0) or (AColIndex >= ColumnCount) or (RowCount <= 1) then
    Exit;
  InvFormat := DefaultFormatSettings;
  InvFormat.DecimalSeparator := '.';
  QuickSortRows(0, RowCount - 1);
end;

procedure TQueryResult.CloseCursor;
begin
  if FCursor <> nil then
  begin
    try
      FCursor.CloseCursor;
    except
    end;
    FCursor := nil;
  end;
end;

end.
