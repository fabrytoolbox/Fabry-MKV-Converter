@echo off
REM Launcher per Fabry-MKV-H265-to-H264.ps1
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fabry-MKV-H265-to-H264.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Errore durante l'esecuzione.
    pause
)
endlocal
