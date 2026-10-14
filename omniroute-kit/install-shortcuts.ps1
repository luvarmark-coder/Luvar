<#
  install-shortcuts.ps1 - создаёт ярлыки OmniRoute на рабочем столе.
  Работает в Windows PowerShell 5.1, права администратора не нужны.
  Запускается через Install-Shortcuts.bat.
#>
param([switch]$NoPause)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
try { $Host.UI.RawUI.WindowTitle = 'OmniRoute - установка ярлыков' } catch { }

function Write-Info([string]$Text) { Write-Host "  $Text" }
function Write-Ok([string]$Text)   { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text)  { Write-Host "  [X]  $Text" -ForegroundColor Red }

function Read-YesNo([string]$Question) {
    while ($true) {
        Write-Host ''
        Write-Host "  $Question" -ForegroundColor White
        $ans = Read-Host '  Введите 1 = Да, 0 = Нет'
        if ($null -eq $ans) { return $false }
        $a = $ans.Trim().ToLower()
        if (@('1', 'y', 'yes', 'д', 'да') -contains $a) { return $true }
        if (@('0', 'n', 'no', 'нет') -contains $a) { return $false }
        Write-Warn 'Пожалуйста, введите 1 или 0.'
    }
}

function Complete-Install([bool]$Ok) {
    if (-not $NoPause) { Write-Host ''; [void](Read-Host '  Нажмите Enter, чтобы закрыть окно') }
    if ($Ok) { exit 0 } else { exit 1 }
}

$kitFiles = @(
    'omniroute-agent.ps1', 'install-shortcuts.ps1',
    'Start-OmniRoute.bat', 'Stop-OmniRoute.bat', 'OmniRoute-Menu.bat', 'Install-Shortcuts.bat',
    'README-RU.txt'
)
$recommended = 'E:\OmniRoute-Kit'
$kit = $PSScriptRoot
if ([string]::IsNullOrEmpty($kit)) { $kit = Split-Path -Parent $MyInvocation.MyCommand.Path }
$kit = $kit.TrimEnd('\')

Write-Host ''
Write-Host '  Установка ярлыков OmniRoute' -ForegroundColor Cyan
Write-Host '  ---------------------------' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath (Join-Path $kit 'omniroute-agent.ps1'))) {
    Write-Err "Рядом с этим файлом нет omniroute-agent.ps1 ($kit)."
    Write-Info 'Распакуйте архив целиком (правый щелчок по ZIP -> "Извлечь всё...") и запустите Install-Shortcuts.bat из распакованной папки.'
    Complete-Install $false
}

# Запуск прямо из ZIP: Проводник распаковывает файлы во временную папку, которая потом исчезает.
$tempRoot = [System.IO.Path]::GetTempPath().TrimEnd('\')
$inTemp = ($kit -like ($tempRoot + '\*')) -or ($kit -match '\\Temp\\') -or ($kit -match '\.zip')

$target = $kit
if ($kit -ine $recommended) {
    Write-Info "Ярлыки будут ссылаться на папку набора: $kit"
    Write-Warn 'Если эту папку потом переместить или удалить, ярлыки перестанут работать.'
    if ($inTemp) { Write-Warn 'Похоже, файл запущен прямо из ZIP-архива или из временной папки.' }
    if (Test-Path -LiteralPath 'E:\') {
        Write-Info "Рекомендуется держать набор в папке $recommended"
        if (Read-YesNo "Скопировать набор в $recommended и сделать ярлыки оттуда?") {
            try {
                New-Item -ItemType Directory -Force -Path $recommended -ErrorAction Stop | Out-Null
                foreach ($f in $kitFiles) {
                    $src = Join-Path $kit $f
                    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $recommended $f) -Force -ErrorAction Stop }
                }
                $target = $recommended
                Write-Ok "Набор скопирован в $recommended (исходные файлы не тронуты)."
            } catch {
                Write-Err "Не удалось скопировать: $($_.Exception.Message)"
                if ($inTemp) { Complete-Install $false }
            }
        } elseif ($inTemp) {
            Write-Err 'Сначала распакуйте архив (правый щелчок -> "Извлечь всё..."), потом запустите Install-Shortcuts.bat из распакованной папки.'
            Complete-Install $false
        }
    } else {
        Write-Warn 'Диск E: не найден - оставляю набор там, где он сейчас.'
        if ($inTemp) {
            Write-Err 'Сначала распакуйте архив в постоянную папку, потом запустите Install-Shortcuts.bat оттуда.'
            Complete-Install $false
        }
    }
}

# Снять пометку "скачано из интернета", чтобы Windows не блокировала файлы набора.
foreach ($f in $kitFiles) {
    $p = Join-Path $target $f
    if (Test-Path -LiteralPath $p) { try { Unblock-File -LiteralPath $p -ErrorAction Stop } catch { } }
}

$desktop = [Environment]::GetFolderPath('Desktop')   # учитывает рабочий стол в OneDrive
if ([string]::IsNullOrEmpty($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
    Write-Err 'Не удалось найти папку рабочего стола.'
    Complete-Install $false
}

$psExe    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$agent    = Join-Path $target 'omniroute-agent.ps1'
$shell32  = Join-Path $env:SystemRoot 'System32\shell32.dll'
$wsh = New-Object -ComObject WScript.Shell

function New-AgentShortcut([string]$Name, [string]$AgentAction, [string]$Icon, [int]$Style, [string]$Description) {
    $path = Join-Path $desktop ($Name + '.lnk')
    try {
        $s = $wsh.CreateShortcut($path)
        $s.TargetPath = $psExe
        $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $agent + '" ' + $AgentAction
        $s.WorkingDirectory = $target
        $s.IconLocation = $Icon
        $s.WindowStyle = $Style
        $s.Description = $Description
        $s.Save()
        Write-Ok "Ярлык: $Name"
        return $true
    } catch {
        Write-Err "Не удалось создать ярлык $Name : $($_.Exception.Message)"
        return $false
    }
}

Write-Host ''
Write-Info "Создаю ярлыки на рабочем столе: $desktop"
$results = @(
    (New-AgentShortcut 'OmniRoute — Запустить'         'start' ($shell32 + ',24')   1 'Запустить OmniRoute, открыть панель и Chatbox'),
    (New-AgentShortcut 'OmniRoute — Остановить'        'stop'  ($shell32 + ',27')   1 'Остановить сервер OmniRoute'),
    (New-AgentShortcut 'OmniRoute — Меню'              'menu'  ($shell32 + ',21')   1 'Все действия OmniRoute: состояние, Chatbox, автозапуск, обновление, диагностика'),
    (New-AgentShortcut 'OmniRoute — Панель (браузер)'  'open'  ($shell32 + ',13')   1 'Открыть панель OmniRoute http://localhost:20128 (запустит сервер, если нужно)')
)

# Инструкция (Блокнот)
$readme = Join-Path $target 'README-RU.txt'
if (Test-Path -LiteralPath $readme) {
    try {
        $s = $wsh.CreateShortcut((Join-Path $desktop 'OmniRoute — Инструкция.lnk'))
        $s.TargetPath = Join-Path $env:SystemRoot 'System32\notepad.exe'
        $s.Arguments = '"' + $readme + '"'
        $s.WorkingDirectory = $target
        $s.Description = 'Инструкция по набору OmniRoute'
        $s.Save()
        Write-Ok 'Ярлык: OmniRoute — Инструкция'
    } catch { Write-Warn "Ярлык инструкции не создан: $($_.Exception.Message)" }
}

if (@($results | Where-Object { $_ -ne $true }).Count -gt 0) {
    Write-Err 'Часть ярлыков создать не удалось (см. выше).'
    Complete-Install $false
}

Write-Host ''
Write-Ok 'Готово! Ярлыки на рабочем столе:'
Write-Info '  OmniRoute — Запустить        - запуск сервера, панель в браузере и Chatbox'
Write-Info '  OmniRoute — Остановить       - остановка сервера'
Write-Info '  OmniRoute — Панель (браузер) - открыть панель управления'
Write-Info '  OmniRoute — Меню             - все остальные действия'
Write-Info '  OmniRoute — Инструкция       - памятка'
Write-Host ''
Write-Warn "Не перемещайте и не удаляйте папку $target - ярлыки ссылаются на неё."
Write-Info '(Если переместили - запустите Install-Shortcuts.bat ещё раз из новой папки.)'

if (Read-YesNo 'Запустить OmniRoute прямо сейчас?') {
    try {
        Start-Process -FilePath $psExe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $agent + '" start') -WorkingDirectory $target
    } catch { Write-Err "Не удалось запустить: $($_.Exception.Message)" }
}
Complete-Install $true
