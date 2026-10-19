#ifndef AppVersion
  #error AppVersion must be provided by scripts/build-windows-installer.ps1
#endif
#ifndef RepositoryRoot
  #error RepositoryRoot must be provided by scripts/build-windows-installer.ps1
#endif

[Setup]
AppId={{D6728CEC-8B4B-40E6-900A-B2E4EE09B6A7}
AppName=Cappella
AppVersion={#AppVersion}
AppPublisher=Cappella
DefaultDirName={localappdata}\Programs\Cappella
DefaultGroupName=Cappella
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#RepositoryRoot}\dist
OutputBaseFilename=Cappella-{#AppVersion}-Windows-x64-Setup
SetupIconFile={#RepositoryRoot}\dist\Cappella-Windows-x64\Resources\AppIcon.ico
UninstallDisplayIcon={app}\Cappella.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: unchecked

[Files]
; Prerequisites first so solid compression does not require extracting the app to reach them.
Source: "{#RepositoryRoot}\.windows\installer\WindowsAppRuntimeInstall-x64.exe"; Flags: dontcopy
Source: "{#RepositoryRoot}\windows\Installer-runtime.ps1"; Flags: dontcopy
Source: "{#RepositoryRoot}\dist\Cappella-Windows-x64\*"; DestDir: "{app}"; Excludes: "Installer-runtime.ps1,LIRE-MOI.md"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Cappella"; Filename: "{app}\Cappella.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Cappella"; Filename: "{app}\Cappella.exe"; WorkingDir: "{app}"; Tasks: desktopicon

; Register Open with choices without overwriting the user's default application.
[Registry]
Root: HKCU; Subkey: "Software\Classes\.detx\OpenWithProgids"; ValueType: string; ValueName: "Cappella.DetX"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.cappellaproject\OpenWithProgids"; ValueType: string; ValueName: "Cappella.Project"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\Cappella.DetX"; ValueType: string; ValueData: "Détection Cappella"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Cappella.DetX\DefaultIcon"; ValueType: string; ValueData: """{app}\Cappella.exe"",0"
Root: HKCU; Subkey: "Software\Classes\Cappella.DetX\shell\open\command"; ValueType: string; ValueData: """{app}\Cappella.exe"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\Cappella.Project"; ValueType: string; ValueData: "Projet Cappella"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Cappella.Project\DefaultIcon"; ValueType: string; ValueData: """{app}\Cappella.exe"",0"
Root: HKCU; Subkey: "Software\Classes\Cappella.Project\shell\open\command"; ValueType: string; ValueData: """{app}\Cappella.exe"" ""%1"""

[Run]
Filename: "{app}\Cappella.exe"; Description: "Lancer Cappella"; Flags: nowait postinstall skipifsilent

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  PowerShell: String;
  Parameters: String;
begin
  Result := '';
  WizardForm.StatusLabel.Caption := 'Vérification et installation du runtime Microsoft…';
  ExtractTemporaryFile('WindowsAppRuntimeInstall-x64.exe');
  ExtractTemporaryFile('Installer-runtime.ps1');
  PowerShell := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{tmp}\Installer-runtime.ps1') + '" -RuntimeInstaller "' +
    ExpandConstant('{tmp}\WindowsAppRuntimeInstall-x64.exe') + '"';
  if not Exec(PowerShell, Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := 'Impossible de lancer la préparation du runtime Microsoft : ' + SysErrorMessage(ResultCode)
  else if ResultCode <> 0 then
    Result := 'Installation du runtime Microsoft impossible (code ' + IntToStr(ResultCode) +
      '). Vérifiez que le déploiement des applications Windows est autorisé, puis réessayez.';
end;
