unit Infrastructure.ProviderFactory;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Generics.Collections,
  Domain.DatabaseTypes,
  Domain.Interfaces;

type
  TProviderMap = specialize TDictionary<TDatabaseType, IDatabaseProvider>;

  { Fábrica concreta que registra e resolve provedores por tipo de banco }
  TDatabaseProviderFactory = class(TInterfacedObject, IDatabaseProviderFactory)
  private
    FProviders: TProviderMap;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterProvider(const AProvider: IDatabaseProvider);
    function GetProvider(const AType: TDatabaseType): IDatabaseProvider;
  end;

implementation

constructor TDatabaseProviderFactory.Create;
begin
  inherited Create;
  FProviders := TProviderMap.Create;
end;

destructor TDatabaseProviderFactory.Destroy;
begin
  FProviders.Free;
  inherited Destroy;
end;

procedure TDatabaseProviderFactory.RegisterProvider(const AProvider: IDatabaseProvider);
begin
  if AProvider = nil then
    raise Exception.Create('Provedor não pode ser nulo.');
  FProviders.AddOrSetValue(AProvider.DatabaseType, AProvider);
end;

function TDatabaseProviderFactory.GetProvider(const AType: TDatabaseType): IDatabaseProvider;
begin
  if not FProviders.TryGetValue(AType, Result) then
    raise Exception.CreateFmt('Nenhum provedor registrado para o banco: %s', [DatabaseTypeToStr(AType)]);
end;

end.
