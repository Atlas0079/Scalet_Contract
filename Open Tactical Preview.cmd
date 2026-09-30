@echo off
setlocal
set "GODOT_EXE=C:\MyResearch\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot executable not found: %GODOT_EXE%
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%~dp0godot" res://presentation/tactical/tactical.tscn
