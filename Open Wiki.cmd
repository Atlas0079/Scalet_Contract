@echo off
cd /d "%~dp0"
py -3 wiki\start.py
if errorlevel 1 pause
