@echo off
cd /d "%~dp0"
rem Windows tags downloaded files as "from the internet"; unblock this folder so the AI, ears and voice programs start without warnings
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File | Unblock-File" >nul 2>&1
start "" "%~dp0AutoHotkey64.exe" "%~dp0HyperBot.ahk"
