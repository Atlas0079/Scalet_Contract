@echo off
cd /d "%~dp0"
if exist "release\v1.4.1\ScarletContract\ScarletContract.exe" (
    start "" "release\v1.4.1\ScarletContract\ScarletContract.exe"
) else (
    ".venv\Scripts\python.exe" "combat_demo\main.py"
)
