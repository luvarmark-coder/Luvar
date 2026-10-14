@echo off
rem OmniRoute: stop server
chcp 65001 >nul
if exist "%~dp0omniroute-agent.ps1" goto run
echo.
echo   [X] omniroute-agent.ps1 not found next to this .bat file.
echo       Unpack the WHOLE archive first: right-click omniroute-kit.zip,
echo       "Izvlech vse..." (Extract All), then run this file from the unpacked folder.
echo       See README-RU.txt.
pause
exit /b 1
:run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0omniroute-agent.ps1" stop -NoPause
pause
