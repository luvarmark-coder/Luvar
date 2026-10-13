# VoiceStudio installer wrapper for Windows (PowerShell 5+).
#   powershell -ExecutionPolicy Bypass -File install.ps1            # latest stable app
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Check     # inspect only
param([switch]$Check, [int]$Port = 3900)
$ErrorActionPreference = "Stop"

Write-Host "==> Device" -ForegroundColor Cyan
$os = Get-CimInstance Win32_OperatingSystem
Write-Host ("  OS:   {0} ({1})" -f $os.Caption, $env:PROCESSOR_ARCHITECTURE)
Write-Host ("  RAM:  {0:N0} GB" -f ($os.TotalVisibleMemorySize / 1MB))
Get-CimInstance Win32_VideoController | ForEach-Object { Write-Host "  GPU:  $($_.Name)" }
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { Write-Host "  CUDA: available" }
$drive = Get-PSDrive -Name ($env:LOCALAPPDATA.Substring(0,1))
Write-Host ("  Free disk: {0:N1} GB (need >= 10 GB)" -f ($drive.Free / 1GB))
if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { Write-Host "  !! Windows on ARM is experimental (CPU only)" -ForegroundColor Yellow }

try {
  $h = Invoke-RestMethod -Uri "http://localhost:$Port/health" -TimeoutSec 3
  Write-Host "==> VoiceStudio already running: $($h | ConvertTo-Json -Compress)" -ForegroundColor Green
  if (-not $Check) { exit 0 }
} catch {}
if ($Check) { exit 0 }

Write-Host "==> Running the official installer (https://voicestudio.sh/install)" -ForegroundColor Cyan
try {
  Invoke-RestMethod https://voicestudio.sh/install | Invoke-Expression
} catch {
  Write-Host "!! Installer unreachable. Download VoiceStudio-Electron-*-win-x64.exe from" -ForegroundColor Yellow
  Write-Host "   https://github.com/debpalash/VoiceStudio/releases/latest" -ForegroundColor Yellow
  exit 1
}
Write-Host "==> Done. Launch VoiceStudio, finish first-run setup, then: python scripts\vs.py doctor"
