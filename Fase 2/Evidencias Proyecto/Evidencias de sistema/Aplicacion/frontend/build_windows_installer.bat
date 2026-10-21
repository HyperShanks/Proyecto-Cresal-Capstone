@echo off
echo =======================================================
echo  1/2: Compilando Cresal App para Windows en Release...
echo =======================================================
cd /d "%~dp0"
call flutter build windows --release
if %errorlevel% neq 0 (
    echo [ERROR] Fallo la compilacion de Flutter para Windows.
    pause
    exit /b %errorlevel%
)

echo.
echo =======================================================
echo  2/2: Generando Instalador Cresal_Setup.exe con Inno Setup...
echo =======================================================
set "ISCC_EXE="
if exist "%LocalAppData%\Programs\Inno Setup 6\iscc.exe" set "ISCC_EXE=%LocalAppData%\Programs\Inno Setup 6\iscc.exe"
if not defined ISCC_EXE if exist "%ProgramFiles(x86)%\Inno Setup 6\iscc.exe" set "ISCC_EXE=%ProgramFiles(x86)%\Inno Setup 6\iscc.exe"
if not defined ISCC_EXE if exist "%ProgramFiles%\Inno Setup 6\iscc.exe" set "ISCC_EXE=%ProgramFiles%\Inno Setup 6\iscc.exe"
if not defined ISCC_EXE (
    where iscc >nul 2>&1
    if not errorlevel 1 set "ISCC_EXE=iscc"
)

if not defined ISCC_EXE goto :no_iscc

"%ISCC_EXE%" "%~dp0windows\installer\cresal_setup.iss"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Fallo la creacion del instalador con Inno Setup.
    pause
    exit /b %errorlevel%
)
goto :success

:no_iscc
echo.
echo [ADVERTENCIA] No se pudo encontrar el compilador de Inno Setup (iscc.exe).
echo Si aun no has instalado Inno Setup 6, descargalo gratis en:
echo https://jrsoftware.org/isdl.php
echo O abre windows\installer\cresal_setup.iss directamente desde Inno Setup GUI.
pause
exit /b 1

:success

echo.
echo =======================================================
echo  [EXITO] Instalador generado correctamente en:
echo  frontend\build\installer\Cresal_Setup.exe
echo =======================================================
pause
