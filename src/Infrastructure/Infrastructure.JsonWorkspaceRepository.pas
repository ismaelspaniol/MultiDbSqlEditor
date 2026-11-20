unit Infrastructure.JsonWorkspaceRepository;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  Generics.Collections,
  fpjson,
  jsonparser;

type
  TWorkspaceTabState = record
    Title: string;
    ProfileId: string;
    SqlText: string;
    BatchSize: string;
    MemoryLimit: string;
    AutoCommit: Boolean;
  end;

  TWorkspaceState = class
  public
    ActiveTabIndex: Integer;
    WindowWidth: Integer;
    WindowHeight: Integer;
    WindowMaximized: Boolean;
    LeftPanelWidth: Integer;
    LeftPanelVisible: Boolean;
    Tabs: array of TWorkspaceTabState;
    constructor Create;
    procedure AddTab(const ATab: TWorkspaceTabState);
  end;

  { Salva e restaura as abas SQL abertas em workspace.json }
  TJsonWorkspaceRepository = class
  private
    FFilePath: string;
  public
    constructor Create(const AFilePath: string = '');
    function Load: TWorkspaceState;
    procedure Save(const AState: TWorkspaceState);
  end;

implementation

constructor TWorkspaceState.Create;
begin
  inherited Create;
  ActiveTabIndex := 0;
  WindowWidth := 0;
  WindowHeight := 0;
  WindowMaximized := False;
  LeftPanelWidth := 0;
  LeftPanelVisible := True;
  SetLength(Tabs, 0);
end;

procedure TWorkspaceState.AddTab(const ATab: TWorkspaceTabState);
var
  Idx: Integer;
begin
  Idx := Length(Tabs);
  SetLength(Tabs, Idx + 1);
  Tabs[Idx] := ATab;
end;

constructor TJsonWorkspaceRepository.Create(const AFilePath: string);
begin
  inherited Create;
  if Trim(AFilePath) <> '' then
    FFilePath := AFilePath
  else
    FFilePath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'workspace.json';
end;

function TJsonWorkspaceRepository.Load: TWorkspaceState;
var
  SL: TStringList;
  Data: TJSONData;
  Root, TabObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Tab: TWorkspaceTabState;
begin
  Result := TWorkspaceState.Create;
  if not FileExists(FFilePath) then
    Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(FFilePath, TEncoding.UTF8);
      if Trim(SL.Text) = '' then
        Exit;

      Data := GetJSON(SL.Text);
      try
        if not (Data is TJSONObject) then
          Exit;
        Root := TJSONObject(Data);
        Result.ActiveTabIndex := Root.Get('activeTabIndex', 0);
        Result.WindowWidth := Root.Get('windowWidth', 0);
        Result.WindowHeight := Root.Get('windowHeight', 0);
        Result.WindowMaximized := Root.Get('windowMaximized', False);
        Result.LeftPanelWidth := Root.Get('leftPanelWidth', 0);
        Result.LeftPanelVisible := Root.Get('leftPanelVisible', True);

        Arr := Root.Get('tabs', TJSONArray(nil));
        if Arr <> nil then
        begin
          for I := 0 to Arr.Count - 1 do
          begin
            if Arr.Items[I] is TJSONObject then
            begin
              TabObj := TJSONObject(Arr.Items[I]);
              Tab.Title := TabObj.Get('title', '');
              Tab.ProfileId := TabObj.Get('profileId', '');
              Tab.SqlText := TabObj.Get('sql', '');
              Tab.BatchSize := TabObj.Get('batchSize', '100');
              Tab.MemoryLimit := TabObj.Get('memoryLimit', '128 MB');
              Tab.AutoCommit := TabObj.Get('autoCommit', False);
              Result.AddTab(Tab);
            end;
          end;
        end;
      finally
        Data.Free;
      end;
    except
      { Se o arquivo estiver corrompido, inicia limpo }
    end;
  finally
    SL.Free;
  end;
end;

procedure TJsonWorkspaceRepository.Save(const AState: TWorkspaceState);
var
  Root, TabObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  SL: TStringList;
  Dir: string;
begin
  if AState = nil then
    Exit;

  Dir := ExtractFileDir(FFilePath);
  if (Dir <> '') and (not DirectoryExists(Dir)) then
    ForceDirectories(Dir);

  Root := TJSONObject.Create;
  try
    Root.Add('activeTabIndex', AState.ActiveTabIndex);
    Root.Add('windowWidth', AState.WindowWidth);
    Root.Add('windowHeight', AState.WindowHeight);
    Root.Add('windowMaximized', AState.WindowMaximized);
    Root.Add('leftPanelWidth', AState.LeftPanelWidth);
    Root.Add('leftPanelVisible', AState.LeftPanelVisible);
    Arr := TJSONArray.Create;
    for I := 0 to High(AState.Tabs) do
    begin
      TabObj := TJSONObject.Create;
      TabObj.Add('title', AState.Tabs[I].Title);
      TabObj.Add('profileId', AState.Tabs[I].ProfileId);
      TabObj.Add('sql', AState.Tabs[I].SqlText);
      TabObj.Add('batchSize', AState.Tabs[I].BatchSize);
      TabObj.Add('memoryLimit', AState.Tabs[I].MemoryLimit);
      TabObj.Add('autoCommit', AState.Tabs[I].AutoCommit);
      Arr.Add(TabObj);
    end;
    Root.Add('tabs', Arr);

    SL := TStringList.Create;
    try
      SL.Text := Root.FormatJSON;
      SL.SaveToFile(FFilePath, TEncoding.UTF8);
    finally
      SL.Free;
    end;
  finally
    Root.Free;
  end;
end;

end.
