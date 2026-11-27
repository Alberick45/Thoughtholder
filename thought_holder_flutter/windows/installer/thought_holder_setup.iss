; ThoughtHolder Windows Inno Setup Script
#ifndef MyAppVersion
#define MyAppVersion "1.4.1"
#endif

#define MyAppName "ThoughtHolder"
#define MyAppPublisher "A3PK Labs"
#define MyAppURL "https://github.com/Alberick45/Thoughtholder"
#define MyAppExeName "thought_holder_flutter.exe"
#define MyBuildOutputDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{E68A91DC-6091-4D02-86FD-A8643194B4D8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={userpf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UsePreviousAppDir=yes
AllowNoIcons=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=thoughtholder-setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Primary application executable and dependencies from Flutter Windows release build
Source: "{#MyBuildOutputDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: User data, database, audio recordings, and XP are stored exclusively in %APPDATA%
; and are NEVER installed or overwritten by this installer.

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#MyAppExeName}"; Flags: nowait runascurrentuser

[UninstallDelete]
; Only delete files installed in {app}, NEVER delete user data in %APPDATA% or %LOCALAPPDATA%
Type: filesandordirs; Name: "{app}"

[Code]
function GetOldMachineInstallPath(out OldPath: String): Boolean;
var
  UninstallKey1: String;
  UninstallKey2: String;
begin
  Result := False;
  OldPath := '';
  UninstallKey1 := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{E68A91DC-6091-4D02-86FD-A8643194B4D8}_is1';
  UninstallKey2 := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{E68A91DC-6091-4D02-86FD-A8643194B4D8}_is1';

  if RegQueryStringValue(HKLM, UninstallKey1, 'InstallLocation', OldPath) then
  begin
    Result := True;
    Exit;
  end;
  if RegQueryStringValue(HKLM, UninstallKey2, 'InstallLocation', OldPath) then
  begin
    Result := True;
    Exit;
  end;
  if RegQueryStringValue(HKLM64, UninstallKey1, 'InstallLocation', OldPath) then
  begin
    Result := True;
    Exit;
  end;
  if RegQueryStringValue(HKLM64, UninstallKey2, 'InstallLocation', OldPath) then
  begin
    Result := True;
    Exit;
  end;
end;

function InitializeSetup(): Boolean;
var
  OldPath: String;
  Msg: String;
begin
  Result := True;
  if GetOldMachineInstallPath(OldPath) then
  begin
    if OldPath = '' then
      OldPath := '(unknown location)';
    Msg := 'An older all-users install of ThoughtHolder was found at ' + OldPath + '.' + #13#10 + #13#10 +
      'Uninstall it from Settings > Apps after this setup finishes, to avoid two copies. ' +
      'Your thoughts are not affected.';
    MsgBox(Msg, mbInformation, MB_OK);
  end;
end;
