@echo off
setlocal
cd /d "%~dp0"
set "SC_GODOT=%GODOT_BIN%"
if defined SC_GODOT if exist "%SC_GODOT%\Godot_v4.7.1-stable_win64.exe" set "SC_GODOT=%SC_GODOT%\Godot_v4.7.1-stable_win64.exe"
if not defined SC_GODOT if exist "..\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe" set "SC_GODOT=%~dp0..\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
if not defined SC_GODOT if exist "..\Godot_v4.7.1-stable_win64.exe" set "SC_GODOT=%~dp0..\Godot_v4.7.1-stable_win64.exe"
if not defined SC_GODOT (
    echo Godot 4.7 executable not found. Set GODOT_BIN to its full file path.
    pause
    exit /b 1
)
if not exist "%SC_GODOT%" (
    echo GODOT_BIN does not point to an existing Godot executable.
    pause
    exit /b 1
)
if not exist "%~dp0godot\.godot\global_script_class_cache.cfg" (
    start "" /wait "%SC_GODOT%" --headless --editor --path "%~dp0godot" --import --quit
    if errorlevel 1 exit /b 1
)
start "" "%SC_GODOT%" --path "%~dp0godot" %*
endlocal
