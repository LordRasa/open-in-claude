@echo off
rem Launcher. The script hides its own console (a brief flash is normal).
rem Do NOT add -WindowStyle Hidden / start /min here: those suppress the app window too.
rem For a flash-free, double-clickable build, run build.ps1 to make OpenInClaude.exe.
start "" powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0OpenInClaude.ps1"
