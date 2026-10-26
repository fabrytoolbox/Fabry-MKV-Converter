@echo off
REM Launcher per Fabry-MKV-to-MP4.ps1
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fabry-MKV-to-MP4.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Errore durante l'esecuzione.
    pause
)
endlocal
