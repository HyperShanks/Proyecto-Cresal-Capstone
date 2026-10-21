; Script de Inno Setup para Empaquetado y Auto-Actualización de Cresal App en Windows
; ==============================================================================
; INSTRUCCIONES DE USO:
; 1. Compilar Flutter para Windows en modo Release:
;    flutter build windows --release
; 2. Compilar este instalador:
;    - Desde Inno Setup Compiler GUI: Abrir este archivo y presionar F9 (Compile)
;    - O por línea de comandos: iscc cresal_setup.iss
; 3. El instalador resultante estará en: frontend/build/installer/Cresal_Setup.exe
; ==============================================================================

#define MyAppName "Cresal"
#define MyAppVersion "1.0.10"
#define MyAppPublisher "Cresal Automotriz SpA"
#define MyAppURL "https://cresal.cl"
#define MyAppExeName "Cresal.exe"

[Setup]
; Identificador único de aplicación (GUID) para reconocer instalaciones previas
AppId={{D3F95C48-9F5E-4B07-A77E-97A2E5B1A801}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; Configuración para permitir actualización silenciosa en caliente:
; Cierra la aplicación antigua antes de copiar y la vuelve a abrir automáticamente
CloseApplications=yes
RestartApplications=yes
CloseApplicationsFilter=*{#MyAppExeName}*

; Icono del instalador y de desinstalación
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

OutputDir=..\..\build\installer
OutputBaseFilename=Cresal_Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copiar todo el directorio de Release de Flutter Windows
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Si se ejecuta con /SILENT durante una actualización automática, no muestra el wizard
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
