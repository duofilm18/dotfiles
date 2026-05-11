@echo off
setlocal

set "APP_DIR=%~dp0CpuUsageWidget.Wpf"
set "PUBLISH_EXE=%APP_DIR%\bin\Release\net8.0-windows\win-x64\publish\CpuUsageWidget.Wpf.exe"
set "DEBUG_EXE=%APP_DIR%\bin\Debug\net8.0-windows\CpuUsageWidget.Wpf.exe"

if exist "%PUBLISH_EXE%" (
    start "" "%PUBLISH_EXE%"
    exit /b 0
)

if exist "%DEBUG_EXE%" (
    start "" "%DEBUG_EXE%"
    exit /b 0
)

where dotnet >nul 2>&1
if errorlevel 1 (
    echo.
    echo CPU Usage WPF could not start.
    echo.
    echo Reason:
    echo   .NET SDK is not installed, and no built EXE was found.
    echo.
    echo Fix:
    echo   Install .NET 8 SDK first.
    echo.
    pause
    exit /b 1
)

cd /d "%APP_DIR%"
echo.
echo Building CPU Usage WPF...
dotnet publish -c Release -r win-x64 --self-contained false
if errorlevel 1 (
    echo.
    echo Build failed.
    echo Review the error above.
    echo.
    pause
    exit /b 1
)

if exist "%PUBLISH_EXE%" (
    start "" "%PUBLISH_EXE%"
    exit /b 0
)
echo.
echo Build finished but EXE was not found:
echo   %PUBLISH_EXE%
echo.
pause
exit /b 1
