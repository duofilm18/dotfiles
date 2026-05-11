@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
start "" powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%SCRIPT_DIR%stats-server.ps1"

timeout /t 2 /nobreak >nul

set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" (
    start "" "%CHROME%" "http://127.0.0.1:8976/"
    exit /b 0
)

set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" (
    start "" "%CHROME%" "http://127.0.0.1:8976/"
    exit /b 0
)

start "" "http://127.0.0.1:8976/"
