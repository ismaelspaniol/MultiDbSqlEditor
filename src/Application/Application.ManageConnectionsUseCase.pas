unit Application.ManageConnectionsUseCase;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Domain.ConnectionProfile,
  Domain.Interfaces;

type
  TManageConnectionsUseCase = class
  private
    FRepository: IConnectionRepository;
  public
    constructor Create(const ARepository: IConnectionRepository);
    function ListAll: TConnectionProfileList;
    function FindById(const AId: string): TConnectionProfile;
    procedure Save(const AProfile: TConnectionProfile);
    procedure Delete(const AId: string);
    procedure Reorder(const AOrderedIds: TStrings);
    procedure GetFolders(const ATarget: TStrings);
    procedure AddFolder(const AFolderName: string);
    procedure RenameFolder(const AOldName, ANewName: string);
    procedure DeleteFolder(const AFolderName: string);
  end;

implementation

constructor TManageConnectionsUseCase.Create(const ARepository: IConnectionRepository);
begin
  inherited Create;
  FRepository := ARepository;
end;

function TManageConnectionsUseCase.ListAll: TConnectionProfileList;
begin
  Result := FRepository.GetAll;
end;

function TManageConnectionsUseCase.FindById(const AId: string): TConnectionProfile;
begin
  Result := FRepository.FindById(AId);
end;

procedure TManageConnectionsUseCase.Save(const AProfile: TConnectionProfile);
var
  Guid: TGUID;
begin
  if AProfile = nil then
    raise Exception.Create('Perfil de conexão não pode ser nulo.');

  AProfile.Validate;
  if Trim(AProfile.Id) = '' then
  begin
    CreateGUID(Guid);
    AProfile.Id := GUIDToString(Guid);
  end;
  FRepository.Save(AProfile);
end;

procedure TManageConnectionsUseCase.Delete(const AId: string);
begin
  if Trim(AId) = '' then
    raise Exception.Create('ID da conexão é obrigatório para exclusão.');
  FRepository.Delete(AId);
end;

procedure TManageConnectionsUseCase.Reorder(const AOrderedIds: TStrings);
begin
  if AOrderedIds <> nil then
    FRepository.Reorder(AOrderedIds);
end;

procedure TManageConnectionsUseCase.GetFolders(const ATarget: TStrings);
begin
  if ATarget <> nil then
    FRepository.GetFolders(ATarget);
end;

procedure TManageConnectionsUseCase.AddFolder(const AFolderName: string);
var
  CleanName: string;
begin
  CleanName := Trim(AFolderName);
  if CleanName = '' then
    raise Exception.Create('O nome da pasta não pode ficar em branco.');
  FRepository.AddFolder(CleanName);
end;

procedure TManageConnectionsUseCase.RenameFolder(const AOldName, ANewName: string);
var
  CleanOld, CleanNew: string;
begin
  CleanOld := Trim(AOldName);
  CleanNew := Trim(ANewName);
  if CleanOld = '' then
    raise Exception.Create('A pasta de origem é obrigatória.');
  if CleanNew = '' then
    raise Exception.Create('O novo nome da pasta não pode ficar em branco.');
  FRepository.RenameFolder(CleanOld, CleanNew);
end;

procedure TManageConnectionsUseCase.DeleteFolder(const AFolderName: string);
var
  CleanName: string;
begin
  CleanName := Trim(AFolderName);
  if CleanName = '' then
    Exit;
  FRepository.DeleteFolder(CleanName);
end;

end.
