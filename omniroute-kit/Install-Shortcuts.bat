@echo off
rem OmniRoute: create desktop shortcuts (run once)
chcp 65001 >nul
if exist "%~dp0install-shortcuts.ps1" goto run
echo.
echo   [X] install-shortcuts.ps1 not found next to this .bat file.
echo       Unpack the WHOLE archive first: right-click omniroute-kit.zip,
echo       "Izvlech vse..." (Extract All), then run this file from the unpacked folder.
echo       See README-RU.txt.
pause
exit /b 1
:run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-shortcuts.ps1" -NoPause
pause
