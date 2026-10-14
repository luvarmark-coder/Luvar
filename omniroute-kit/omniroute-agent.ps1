<#
  omniroute-agent.ps1 - "агент" для OmniRoute + Chatbox на Windows.
  Работает в Windows PowerShell 5.1. Права администратора не нужны.

  Обычно запускается ярлыком с рабочего стола или .bat-файлом:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File omniroute-agent.ps1 [действие] [-Silent] [-NoPause]

  Действия:
    start          запустить сервер, дождаться готовности, открыть панель и Chatbox
    stop           остановить сервер
    status         состояние, адреса, версии, модели
    open           открыть панель в браузере (если сервер выключен - запустить)
    chatbox        установить / подключить Chatbox к OmniRoute
    autostart-on   автозапуск при входе в Windows
    autostart-off  выключить автозапуск
    update         обновить OmniRoute (npm)
    doctor         диагностика
    move-data      перенести данные OmniRoute на диск E: (старая папка остаётся)
    tray-retry     снова пробовать режим со значком в трее (после неудач)
    help           как всё устроено и где что искать
    menu           меню (по умолчанию)

  -Silent   без вопросов, без браузера и Chatbox (для автозагрузки)
  -NoPause  не ждать Enter в конце (окно держит .bat-файл)
#>
param(
    [Parameter(Position = 0)]
    [string]$Action = 'menu',
    [switch]$Silent,
    [switch]$NoPause
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- настройки
$script:Port            = 20128
$script:PreferTray      = $true   # пробовать фон со значком в трее (omniroute serve --tray), если версия позволяет
# В OmniRoute до 3.8.52 "serve --tray" ждёт готовности ровно 60 с (без настройки) и потом убивает
# сервер (taskkill /T /F). Холодный старт на Windows дольше, поэтому на старых версиях трей не используется.
$script:TrayMinVersion  = '3.8.52'
$script:TrayReadyMs     = 420000  # OMNIROUTE_TRAY_READY_TIMEOUT_MS (3.8.52+): до 180 с старт + до 120 с npm systray2
$script:TrayTimeoutSec  = 435     # сколько агент ждёт режим трея (пересчитывается из TrayReadyMs)
$script:StartTimeoutSec = 180     # ожидание обычного запуска (холодный старт на Windows бывает долгим)
$script:TrayMaxFails    = 2       # после стольких неудач трея подряд (на той же версии) - свёрнутое окно
$script:NodeRangeDefault = '>=22.22.2 <23 || >=24.0.0 <27'   # как engines.node у OmniRoute 3.8.51
$script:OpenBrowser     = $true
$script:LaunchChatbox   = $true
$script:DefaultModel    = 'gc/grok-4.7'

$script:KitDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($script:KitDir)) { $script:KitDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:AgentPath        = Join-Path $script:KitDir 'omniroute-agent.ps1'
$script:TrayFlag         = Join-Path $script:KitDir 'tray-disabled.flag'
$script:ChatboxFlag      = Join-Path $script:KitDir 'chatbox-configured.flag'
$script:LogFile          = Join-Path $script:KitDir 'agent.log'
$script:PsExe            = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:StartupLnkName   = 'OmniRoute-Kit Autostart.lnk'
$script:OriginalDataDir  = $env:DATA_DIR
$script:NodeExe          = $null
$script:NodeVersion      = ''
$script:NpmCmd           = $null
$script:OmniCmd          = $null
$script:OmniVersion      = ''
$script:OmniNodeRange    = ''
$script:WarnCount        = 0
$script:KitMutex         = $null
$script:KitLockDepth     = 0

# ---------------------------------------------------------------- вывод
function Write-Info([string]$Text) { Write-Host "  $Text" }
function Write-Step([string]$Text) { Write-Host ''; Write-Host ">> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { $script:WarnCount++; Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text)  { $script:WarnCount++; Write-Host "  [X]  $Text" -ForegroundColor Red }

function Write-Log([string]$Text) {
    try {
        if ((Test-Path -LiteralPath $script:LogFile) -and ((Get-Item -LiteralPath $script:LogFile).Length -gt 524288)) {
            Move-Item -LiteralPath $script:LogFile -Destination ($script:LogFile + '.old') -Force
        }
        $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $Text + "`r`n"
        [System.IO.File]::AppendAllText($script:LogFile, $line, (New-Object System.Text.UTF8Encoding $true))
    } catch { }
}

function Initialize-Console {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
    try { $global:OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
    try { $Host.UI.RawUI.WindowTitle = 'OmniRoute - агент' } catch { }
}

function Read-YesNo {
    param([string]$Question, [bool]$Default = $false)
    if ($Silent) { return $Default }
    while ($true) {
        Write-Host ''
        Write-Host "  $Question" -ForegroundColor White
        $ans = Read-Host '  Введите 1 = Да, 0 = Нет'
        if ($null -eq $ans) { return $Default }
        $a = $ans.Trim().ToLower()
        if (@('1', 'y', 'yes', 'д', 'да') -contains $a) { return $true }
        if (@('0', 'n', 'no', 'нет') -contains $a) { return $false }
        Write-Warn 'Пожалуйста, введите 1 или 0.'
    }
}

function Wait-Enter([string]$Text = 'Нажмите Enter, чтобы закрыть окно') {
    if ($Silent) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

function Exit-Agent {
    param($Success = $true, [int]$AutoCloseSec = 0)
    if ($Success -is [array]) { if ($Success.Count -gt 0) { $Success = $Success[-1] } else { $Success = $false } }
    $Success = ($Success -eq $true)
    if ($Silent) { if ($Success) { exit 0 } else { exit 1 } }
    if ($Success -and $AutoCloseSec -gt 0 -and $script:WarnCount -gt 0) {
        # были предупреждения - окно не закрываем само (даже из .bat с -NoPause), чтобы их успели прочитать
        Write-Host ''
        Write-Info 'Выше есть предупреждения (жёлтым/красным) - прочитайте их.'
        Wait-Enter
        exit 0
    }
    if ($Success -and $AutoCloseSec -gt 0) {
        Write-Host ''
        Write-Info "Окно закроется через $AutoCloseSec сек."
        Start-Sleep -Seconds $AutoCloseSec
        exit 0
    }
    if (-not $NoPause) { Wait-Enter }
    if ($Success) { exit 0 } else { exit 1 }
}

# ---------------------------------------------------------------- окружение
function Update-SessionEnvironment {
    # Свежий PATH из реестра (Machine + User): лечит "node.exe не распознано" в старых окнах.
    $parts = New-Object System.Collections.Generic.List[string]
    $sources = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        $env:Path
    )
    foreach ($src in $sources) {
        if ([string]::IsNullOrEmpty($src)) { continue }
        foreach ($p in $src.Split(';')) {
            $t = $p.Trim()
            if ($t -eq '') { continue }
            $exists = $false
            foreach ($q in $parts) { if ($q.TrimEnd('\') -ieq $t.TrimEnd('\')) { $exists = $true; break } }
            if (-not $exists) { $parts.Add($t) }
        }
    }
    $env:Path = ($parts -join ';')
    foreach ($name in @('DATA_DIR', 'PORT', 'OMNIROUTE_SERVER_HOST', 'REQUIRE_API_KEY', 'OMNIROUTE_READY_TIMEOUT_MS', 'OMNIROUTE_TRAY_READY_TIMEOUT_MS', 'OMNIROUTE_LANG')) {
        $v = [Environment]::GetEnvironmentVariable($name, 'User')
        if ([string]::IsNullOrEmpty($v)) { $v = [Environment]::GetEnvironmentVariable($name, 'Machine') }
        if (-not [string]::IsNullOrEmpty($v)) { Set-Item -Path ('Env:' + $name) -Value $v }
    }
}

function Set-Urls {
    $script:LocalUrl  = 'http://127.0.0.1:' + $script:Port
    $script:DashUrl   = 'http://localhost:' + $script:Port
    $script:ApiBase   = 'http://localhost:' + $script:Port + '/v1'
    $script:ApiBaseIp = 'http://127.0.0.1:' + $script:Port + '/v1'
}

function Add-ToPath([string]$Dir) {
    if ([string]::IsNullOrEmpty($Dir)) { return }
    $have = $false
    foreach ($p in $env:Path.Split(';')) { if ($p.Trim().TrimEnd('\') -ieq $Dir.TrimEnd('\')) { $have = $true; break } }
    if (-not $have) { $env:Path = $Dir + ';' + $env:Path }
}

function Find-Node {
    $script:NodeExe = $null
    $cmd = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $script:NodeExe = $cmd.Path }
    if (-not $script:NodeExe) {
        $candidates = New-Object System.Collections.Generic.List[string]
        foreach ($root in @('HKLM:\SOFTWARE\Node.js', 'HKCU:\SOFTWARE\Node.js', 'HKLM:\SOFTWARE\WOW6432Node\Node.js')) {
            try {
                $ip = (Get-ItemProperty -Path $root -ErrorAction Stop).InstallPath
                if ($ip) { $candidates.Add((Join-Path $ip 'node.exe')) }
            } catch { }
        }
        foreach ($c in @('C:\Program Files\nodejs\node.exe', 'E:\Program Files\nodejs\node.exe', 'E:\nodejs\node.exe')) { $candidates.Add($c) }
        if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'nodejs\node.exe')) }
        if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe')) }
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath $c) {
                $script:NodeExe = $c
                Add-ToPath (Split-Path -Parent $c)
                break
            }
        }
    }
    if (-not $script:NodeExe) { return $false }
    try { $script:NodeVersion = ((& $script:NodeExe -v) | Out-String).Trim() } catch { $script:NodeVersion = '?' }
    return $true
}

function Find-Npm {
    if ($script:NpmCmd -and (Test-Path -LiteralPath $script:NpmCmd)) { return $true }
    $c = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $script:NpmCmd = $c.Path; return $true }
    if ($script:NodeExe) {
        $p = Join-Path (Split-Path -Parent $script:NodeExe) 'npm.cmd'
        if (Test-Path -LiteralPath $p) { $script:NpmCmd = $p; return $true }
    }
    return $false
}

function Find-OmniRoute {
    $script:OmniCmd = $null
    $c = Get-Command omniroute.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $script:OmniCmd = $c.Path }
    if (-not $script:OmniCmd -and $env:APPDATA) {
        $p = Join-Path $env:APPDATA 'npm\omniroute.cmd'
        if (Test-Path -LiteralPath $p) { $script:OmniCmd = $p }
    }
    if (-not $script:OmniCmd -and (Find-Npm)) {
        try {
            $prefix = ((& $script:NpmCmd config get prefix 2>$null) | Out-String).Trim()
            if ($prefix) {
                $p = Join-Path $prefix 'omniroute.cmd'
                if (Test-Path -LiteralPath $p) { $script:OmniCmd = $p }
            }
        } catch { }
    }
    if (-not $script:OmniCmd) { return $false }
    $dir = Split-Path -Parent $script:OmniCmd
    Add-ToPath $dir
    $script:OmniVersion = '?'
    $script:OmniNodeRange = ''
    $pkg = Join-Path $dir 'node_modules\omniroute\package.json'
    if (Test-Path -LiteralPath $pkg) {
        try {
            $j = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
            $script:OmniVersion = "$($j.version)"
            if ($j.engines -and $j.engines.node) { $script:OmniNodeRange = "$($j.engines.node)" }
        } catch { }
    }
    return $true
}

function ConvertTo-SemVer([string]$Text) {
    # '3.8.51' / 'v24.11.0' / '3.9.0-beta.1' -> [version] 3.8.51 (без суффикса); иначе $null
    if ("$Text".Trim() -match '^v?(\d+)\.(\d+)\.(\d+)') {
        return (New-Object System.Version -ArgumentList ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[3]))
    }
    return $null
}

function Test-VersionInRange {
    # Простой разбор диапазона semver вида '>=22.22.2 <23 || >=24.0.0 <27'.
    # Возвращает $true / $false, или $null, если запись непонятна.
    param([System.Version]$Version, [string]$Range)
    if (-not $Version -or [string]::IsNullOrWhiteSpace($Range)) { return $null }
    foreach ($alt in ($Range -split '\|\|')) {
        $okAll = $true
        $count = 0
        foreach ($c in ($alt.Trim() -split '\s+')) {
            if ($c -eq '') { continue }
            if ($c -notmatch '^(>=|<=|>|<)v?(\d+)(?:\.(\d+))?(?:\.(\d+))?$') { return $null }
            $op = $Matches[1]
            $minor = 0; $patch = 0
            if ($Matches[3]) { $minor = [int]$Matches[3] }
            if ($Matches[4]) { $patch = [int]$Matches[4] }
            $cv = New-Object System.Version -ArgumentList ([int]$Matches[2]), $minor, $patch
            $cmp = $Version.CompareTo($cv)
            $count++
            switch ($op) {
                '>=' { if ($cmp -lt 0) { $okAll = $false } }
                '>'  { if ($cmp -le 0) { $okAll = $false } }
                '<=' { if ($cmp -gt 0) { $okAll = $false } }
                '<'  { if ($cmp -ge 0) { $okAll = $false } }
            }
        }
        if ($count -gt 0 -and $okAll) { return $true }
    }
    return $false
}

function Get-NodeSupport {
    # Совпадает ли версия Node.js с тем, что требует OmniRoute (engines.node; иначе диапазон 3.8.51).
    # Иначе omniroute завершается сразу: "Node.js ... is not supported".
    $range = $script:OmniNodeRange
    $v = ConvertTo-SemVer $script:NodeVersion
    $res = $null
    if ($range) { $res = Test-VersionInRange -Version $v -Range $range }
    if ($null -eq $res) { $range = $script:NodeRangeDefault; $res = Test-VersionInRange -Version $v -Range $range }
    $state = 'unknown'
    if ($res -eq $true) { $state = 'ok' } elseif ($res -eq $false) { $state = 'bad' }
    return [pscustomobject]@{ State = $state; Range = $range; Version = $v }
}

function Show-NodeSupportWarning($Support) {
    $nv = $script:NodeVersion
    $major = 0
    if ($Support.Version) { $major = $Support.Version.Major }
    if ($major -ge 27 -or ($major -eq 23)) {
        Write-Warn "Node.js $nv OmniRoute не поддерживает (нужно: $($Support.Range)) - команда omniroute не запустится."
    } else {
        Write-Warn "Node.js $nv слишком старый для OmniRoute (нужно: $($Support.Range)) - команда omniroute не запустится."
    }
    Write-Info '     Установите Node.js 24 LTS с https://nodejs.org (файл .msi), затем закройте все окна PowerShell.'
}

function Test-TraySupported {
    # Режим трея только в OmniRoute 3.8.52+ (там время ожидания настраивается).
    $v = ConvertTo-SemVer $script:OmniVersion
    if (-not $v) { return $false }
    return ($v -ge [System.Version]$script:TrayMinVersion)
}

function Initialize-TrayTiming {
    # Для OmniRoute 3.8.52+: родитель "serve --tray" ждёт OMNIROUTE_TRAY_READY_TIMEOUT_MS (по умолчанию 240 с).
    if ([string]::IsNullOrEmpty($env:OMNIROUTE_TRAY_READY_TIMEOUT_MS)) { $env:OMNIROUTE_TRAY_READY_TIMEOUT_MS = "$($script:TrayReadyMs)" }
    $ms = 0
    if ([int]::TryParse("$env:OMNIROUTE_TRAY_READY_TIMEOUT_MS", [ref]$ms) -and $ms -gt 0) {
        $script:TrayTimeoutSec = [math]::Max(60, [int]($ms / 1000) + 15)
    }
}

function Install-OmniRoute {
    if (-not (Find-Npm)) { Write-Err 'Не найден npm (он ставится вместе с Node.js).'; return $false }
    Write-Step 'Устанавливаю OmniRoute: npm install -g omniroute'
    Write-Info 'Это может занять несколько минут. Нужен интернет.'
    & $script:NpmCmd install -g omniroute | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Err "npm завершился с ошибкой (код $LASTEXITCODE)."; return $false }
    return (Find-OmniRoute)
}

function Initialize-Agent {
    param([bool]$NeedOmni = $true)
    Update-SessionEnvironment
    if ($env:PORT -match '^\d{2,5}$') { $script:Port = [int]$env:PORT }
    Set-Urls
    if (-not (Find-Node)) {
        Write-Err 'Не найден Node.js (node.exe).'
        Write-Info 'Что сделать:'
        Write-Info '  1) Откройте https://nodejs.org и скачайте версию LTS (24) - файл .msi для Windows.'
        Write-Info '  2) Установите с настройками по умолчанию (пункт "Add to PATH" должен быть включён).'
        Write-Info '  3) Закройте ВСЕ окна PowerShell и снова запустите ярлык OmniRoute.'
        Write-Log 'init: node.exe not found'
        return $false
    }
    if (-not (Find-OmniRoute)) {
        Write-Warn 'OmniRoute не найден (нет команды omniroute).'
        $installed = $false
        if (Read-YesNo 'Установить OmniRoute сейчас командой "npm install -g omniroute"?' $false) { $installed = Install-OmniRoute }
        if (-not $installed -and $NeedOmni) { Write-Log 'init: omniroute not found'; return $false }
    }
    $ns = Get-NodeSupport
    if ($ns.State -eq 'bad') {
        Show-NodeSupportWarning $ns
        Write-Log "init: node $($script:NodeVersion) outside $($ns.Range)"
    }
    # Только для этого окна и запускаемых из него процессов:
    if ([string]::IsNullOrEmpty($env:OMNIROUTE_LANG)) { $env:OMNIROUTE_LANG = 'ru' }                         # русские сообщения CLI
    if ([string]::IsNullOrEmpty($env:OMNIROUTE_READY_TIMEOUT_MS)) { $env:OMNIROUTE_READY_TIMEOUT_MS = '180000' } # медленный старт Windows
    # Слушать только этот компьютер: по умолчанию OmniRoute открыт всей сети (0.0.0.0) без ключа API,
    # и любой в той же Wi-Fi сети мог бы пользоваться вашим Grok Build. Своё значение в переменной - уважаем.
    if ([string]::IsNullOrEmpty($env:OMNIROUTE_SERVER_HOST)) { $env:OMNIROUTE_SERVER_HOST = '127.0.0.1' }
    $info = Get-DataDirInfo
    $env:DATA_DIR = $info.Path
    return $true
}

# ---------------------------------------------------------------- папка данных
function Get-DataDirInfo {
    $userVal    = [Environment]::GetEnvironmentVariable('DATA_DIR', 'User')
    $machineVal = [Environment]::GetEnvironmentVariable('DATA_DIR', 'Machine')
    $appDir  = Join-Path $env:APPDATA 'omniroute'
    $homeDir = Join-Path $env:USERPROFILE '.omniroute'
    $r = [pscustomobject]@{
        Path      = $null
        Source    = ''
        Persisted = $false
        Ambiguous = $false
        AppDir    = $appDir
        HomeDir   = $homeDir
        AppHasDb  = (Test-Path -LiteralPath (Join-Path $appDir 'storage.sqlite'))
        HomeHasDb = (Test-Path -LiteralPath (Join-Path $homeDir 'storage.sqlite'))
    }
    $explicit = $userVal
    if ([string]::IsNullOrEmpty($explicit)) { $explicit = $machineVal }
    if ([string]::IsNullOrEmpty($explicit)) { $explicit = $script:OriginalDataDir }
    if (-not [string]::IsNullOrEmpty($explicit)) {
        $r.Path = $explicit.Trim().Trim('"')
        $r.Source = 'задана переменной DATA_DIR'
        $r.Persisted = -not ([string]::IsNullOrEmpty($userVal) -and [string]::IsNullOrEmpty($machineVal))
        return $r
    }
    if ($r.AppHasDb -and $r.HomeHasDb) {
        $r.Ambiguous = $true
        $a = Get-DbStat $appDir
        $h = Get-DbStat $homeDir
        $r | Add-Member -NotePropertyName AppStat -NotePropertyValue $a
        $r | Add-Member -NotePropertyName HomeStat -NotePropertyValue $h
        if ($h.Bytes -gt $a.Bytes) { $r.Path = $homeDir } else { $r.Path = $appDir }
        $r.Source = 'найдены две папки, предварительно выбрана та, где база больше'
    } elseif ($r.AppHasDb) {
        $r.Path = $appDir;  $r.Source = 'найдена база в AppData\Roaming\omniroute'
    } elseif ($r.HomeHasDb) {
        $r.Path = $homeDir; $r.Source = 'найдена база в .omniroute'
    } else {
        $r.Path = $appDir;  $r.Source = 'по умолчанию (база ещё не создана)'
    }
    return $r
}

function Get-DbStat([string]$Dir) {
    # Размер базы вместе с журналом storage.sqlite-wal (после жёсткой остановки там бывает почти всё свежее)
    # и время последнего изменения.
    $bytes = [long]0
    $time = [datetime]::MinValue
    $db = Join-Path $Dir 'storage.sqlite'
    foreach ($f in @($db, ($db + '-wal'))) {
        $it = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        if ($it) {
            $bytes += $it.Length
            if ($it.LastWriteTime -gt $time) { $time = $it.LastWriteTime }
        }
    }
    return [pscustomobject]@{ Bytes = $bytes; Time = $time }
}

function Format-DbStat($Stat) {
    if (-not $Stat) { return '?' }
    $mb = [math]::Round($Stat.Bytes / 1MB, 2)
    $when = '?'
    if ($Stat.Time -gt [datetime]::MinValue) { $when = $Stat.Time.ToString('dd.MM.yyyy HH:mm') }
    return ("база {0} МБ, последнее изменение {1}" -f $mb, $when)
}

function Read-DataDirChoice($Info) {
    # Две папки с базой: показать обе и спросить, где настройки пользователя. Возвращает путь.
    $rec = 1
    if ($Info.Path -ieq $Info.HomeDir) { $rec = 2 }
    $m1 = ''; $m2 = ''
    if ($rec -eq 1) { $m1 = '   <- похоже, ваша (база больше)' } else { $m2 = '   <- похоже, ваша (база больше)' }
    Write-Warn 'Найдены ДВЕ папки данных OmniRoute, в каждой своя база:'
    Write-Info "  1) $($Info.AppDir)"
    Write-Info "       $(Format-DbStat $Info.AppStat)$m1"
    Write-Info "  2) $($Info.HomeDir)"
    Write-Info "       $(Format-DbStat $Info.HomeStat)$m2"
    Write-Info 'Ваши настройки (пароль, подключение Grok Build) обычно там, где база больше и менялась,'
    Write-Info 'когда вы последний раз работали в панели. Пустая папка (пароль CHANGEME) - маленькая.'
    if ($Silent) { return $null }
    while ($true) {
        $ans = Read-Host "  Какая папка ваша? Введите 1 или 2 (просто Enter = $rec)"
        if ($null -eq $ans) { $ans = '' }
        $a = $ans.Trim()
        if ($a -eq '') { $a = "$rec" }
        if ($a -eq '1') { return $Info.AppDir }
        if ($a -eq '2') { return $Info.HomeDir }
        Write-Host '  Пожалуйста, введите 1 или 2.' -ForegroundColor Yellow
    }
}

function Save-UserEnvDefault([string]$Name, [string]$Value, [string]$Why) {
    # Сохранить переменную пользователя, только если её ещё нет (своё значение пользователя не трогаем).
    try {
        $u = [Environment]::GetEnvironmentVariable($Name, 'User')
        $m = [Environment]::GetEnvironmentVariable($Name, 'Machine')
        if (-not [string]::IsNullOrEmpty($u) -or -not [string]::IsNullOrEmpty($m)) { return }
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        Write-Ok "Сохранена настройка $Name = $Value"
        if ($Why) { Write-Info "     ($Why)" }
        Write-Log "user env $Name=$Value saved"
    } catch {
        Write-Log "user env $Name save failed: $($_.Exception.Message)"
    }
}

function Set-DataDirPinned {
    # Важно: режим трея и обновление создают папку %USERPROFILE%\.omniroute. Без DATA_DIR OmniRoute
    # при следующем старте начал бы работать с ней (пустая база, пароль CHANGEME, нет Grok Build).
    # Возвращает $true, когда папка данных закреплена в переменной DATA_DIR пользователя.
    $info = Get-DataDirInfo
    $env:DATA_DIR = $info.Path
    # Эти же настройки получат и окна PowerShell, открытые позже, и "omniroute", запущенный вручную:
    Save-UserEnvDefault 'OMNIROUTE_SERVER_HOST' '127.0.0.1' 'OmniRoute доступен только с этого компьютера, а не всей сети. Chatbox и браузер работают как раньше.'
    Save-UserEnvDefault 'OMNIROUTE_READY_TIMEOUT_MS' '180000' 'OmniRoute ждёт запуска до 3 минут - холодный старт на Windows бывает долгим.'
    if ($info.Persisted) {
        # DATA_DIR задана, но базы там нет, а в стандартной папке она есть: скорее всего, переменную задали
        # вручную до переноса данных. Предложить вернуть папку с настройками (данные не трогаем).
        $hasDb = Test-Path -LiteralPath (Join-Path $info.Path 'storage.sqlite')
        if (-not $hasDb -and ($info.AppHasDb -or $info.HomeHasDb)) {
            $found = $info.AppDir
            if (-not $info.AppHasDb) { $found = $info.HomeDir }
            Write-Warn "В переменной DATA_DIR указана папка без базы OmniRoute: $($info.Path)"
            Write-Info "     Ваши настройки (пароль, Grok Build), похоже, лежат здесь: $found"
            Write-Info '     Если оставить как есть, OmniRoute откроет пустой профиль (пароль CHANGEME, нет Grok Build).'
            if (Read-YesNo "Переключить DATA_DIR на $found ?" $true) {
                try {
                    [Environment]::SetEnvironmentVariable('DATA_DIR', $found, 'User')
                    $env:DATA_DIR = $found
                    Write-Ok "Папка данных закреплена: $found"
                    Write-Info '     Перенести данные на диск E: правильно можно через Меню -> 10.'
                    Write-Log "DATA_DIR switched from empty $($info.Path) to $found"
                } catch {
                    Write-Warn "Не удалось сохранить переменную DATA_DIR: $($_.Exception.Message)"
                }
            }
        }
        return $true
    }
    if ($info.Ambiguous) {
        $choice = Read-DataDirChoice $info
        if (-not $choice) {
            # без вопросов (автозагрузка): ничего не закрепляем, решит пользователь при следующем запуске ярлыком
            Write-Log "DATA_DIR ambiguous, not pinned in silent mode (using $($info.Path) for this run)"
            return $false
        }
        $info.Path = $choice
        $info.Source = 'выбрана пользователем из двух папок'
        $env:DATA_DIR = $choice
    }
    try {
        [Environment]::SetEnvironmentVariable('DATA_DIR', $info.Path, 'User')
        Write-Ok "Папка данных закреплена: $($info.Path)"
        Write-Info '     (переменная DATA_DIR - чтобы OmniRoute всегда открывал ваши настройки, а не создавал новые)'
        Write-Warn 'Если запускаете "omniroute" вручную - только в НОВОМ окне PowerShell. Окно, открытое до этой минуты,'
        Write-Info '     не знает про DATA_DIR: OmniRoute там откроет пустой профиль (пароль CHANGEME, нет Grok Build).'
        Write-Info '     Закройте такое окно - ваши данные на месте.'
        if ($info.Ambiguous) {
            $other = $info.AppDir
            if ($info.Path -ieq $info.AppDir) { $other = $info.HomeDir }
            Write-Info '     Проверьте в панели, что Grok Build на месте. Если нет - выбрана не та папка; вернуть другую'
            Write-Info "     (в PowerShell): [Environment]::SetEnvironmentVariable('DATA_DIR','$other','User')"
        }
        Write-Log "DATA_DIR pinned to $($info.Path) ($($info.Source))"
        return $true
    } catch {
        Write-Warn "Не удалось сохранить переменную DATA_DIR: $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------- сеть и процессы
function Invoke-Http {
    param([string]$Url, [int]$TimeoutMs = 3000)
    $resp = $null
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'GET'
        $req.Timeout = $TimeoutMs
        $req.Proxy = $null              # не ходить на localhost через системный прокси
        try { $req.ReadWriteTimeout = $TimeoutMs } catch { }
        $resp = $req.GetResponse()
    } catch {
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
        if ($ex -and $ex.Response) { $resp = $ex.Response } else { return $null }
    }
    $code = 0
    $body = ''
    try {
        $code = [int]$resp.StatusCode
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $body = $sr.ReadToEnd()
        $sr.Close()
    } catch { } finally { try { $resp.Close() } catch { } }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Test-ServerUp {
    # /api/health - публичная проверка "жив ли сервер" (без входа); /livez - запасная.
    $r = Invoke-Http ($script:LocalUrl + '/api/health') 3000
    if ($r -and $r.Code -eq 200) { return $true }
    $r = Invoke-Http ($script:LocalUrl + '/livez') 3000
    if ($r -and $r.Code -eq 200) { return $true }
    return $false
}

function Get-PortOwners {
    $ids = New-Object System.Collections.Generic.List[int]
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $conns = Get-NetTCPConnection -LocalPort $script:Port -State Listen -ErrorAction SilentlyContinue
        foreach ($c in @($conns)) {
            if ($c -and $c.OwningProcess -gt 0 -and -not $ids.Contains([int]$c.OwningProcess)) { $ids.Add([int]$c.OwningProcess) }
        }
    } else {
        $lines = @()
        try { $lines = @(netstat.exe -ano 2>$null) } catch { }
        foreach ($line in $lines) {
            $f = ("$line".Trim() -split '\s+')
            # слушающий сокет: чужой адрес оканчивается на :0 (не зависит от языка Windows)
            if ($f.Count -ge 5 -and $f[0] -eq 'TCP' -and $f[1] -match (':' + $script:Port + '$') -and $f[2] -match ':0$' -and $f[4] -match '^\d+$') {
                $id = [int]$f[4]
                if ($id -gt 0 -and -not $ids.Contains($id)) { $ids.Add($id) }
            }
        }
    }
    $result = @()
    foreach ($id in $ids) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        $name = '?'; $path = ''
        if ($p) { $name = $p.ProcessName; try { $path = $p.Path } catch { } }
        $result += [pscustomobject]@{ Pid = $id; Name = $name; Path = $path }
    }
    return $result
}

function Read-OmniPidFile([string]$Service) {
    # <DATA_DIR>\supervisor\.pid или <DATA_DIR>\server\.pid -> номер процесса (0, если нет)
    if ([string]::IsNullOrEmpty($env:DATA_DIR)) { return 0 }
    $pidFile = Join-Path (Join-Path $env:DATA_DIR $Service) '.pid'
    if (-not (Test-Path -LiteralPath $pidFile)) { return 0 }
    try {
        $txt = (Get-Content -LiteralPath $pidFile -Raw)
        if ($txt -match '"?pid"?\s*[:=]\s*(\d+)') { return [int]$Matches[1] }
        if ($txt -match '(\d+)') { return [int]$Matches[1] }
    } catch { }
    return 0
}

function Get-ProcInfo([int]$Id) {
    # Имя, родитель и командная строка процесса (Win32_Process). $null, если процесса нет.
    if ($Id -le 0) { return $null }
    $w = $null
    try { $w = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId=" + $Id) -ErrorAction Stop } catch {
        try { $w = Get-WmiObject -Class Win32_Process -Filter ("ProcessId=" + $Id) -ErrorAction Stop } catch { }
    }
    $p = Get-Process -Id $Id -ErrorAction SilentlyContinue
    if (-not $w -and -not $p) { return $null }
    $name = ''; $parent = 0; $cmdLine = ''; $started = $null
    if ($w) { $name = "$($w.Name)"; $parent = [int]$w.ParentProcessId; $cmdLine = "$($w.CommandLine)" }
    elseif ($p) { $name = $p.ProcessName + '.exe' }
    if ($p) { try { $started = $p.StartTime } catch { } }
    return [pscustomobject]@{ Pid = $Id; Name = $name; ParentPid = $parent; CommandLine = $cmdLine; Started = $started }
}

function Test-OmniNodeProc($Info) {
    # node.exe именно OmniRoute (а не другой программы на Node.js с тем же номером процесса)
    if (-not $Info) { return $false }
    if ($Info.Name -inotlike 'node*') { return $false }
    if ([string]::IsNullOrEmpty($Info.CommandLine)) { return $true }   # командная строка недоступна - верим имени
    return ($Info.CommandLine -match 'omniroute')
}

function Test-ServerStarting {
    # Есть ли живой процесс node OmniRoute из PID-файлов (сервер ещё стартует).
    foreach ($svc in @('supervisor', 'server')) {
        $id = Read-OmniPidFile $svc
        if ($id -gt 0 -and (Test-OmniNodeProc (Get-ProcInfo $id))) { return $true }
    }
    return $false
}

function Wait-ServerReady {
    param([int]$TimeoutSec = 180, $Proc = $null, [switch]$TrayMode)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = 'timeout'
    $nextMark = 30
    Write-Host '  Жду ответа сервера ' -NoNewline
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $up = Test-ServerUp
        $exited = $false
        $code = $null
        if ($null -ne $Proc) {
            try { $exited = $Proc.HasExited; if ($exited) { $code = $Proc.ExitCode } } catch { }
        }
        if ($TrayMode) {
            # omniroute serve --tray сам возвращается, когда сервер и значок готовы (код 0)
            if ($exited -and $null -ne $code -and $code -ne 0) { $result = 'proc-failed'; break }
            if ($exited -and $up) { $result = 'ok'; break }
        } else {
            if ($up) { $result = 'ok'; break }
            if ($exited) { $result = 'proc-failed'; break }
        }
        Start-Sleep -Seconds 2
        Write-Host '.' -NoNewline
        if ($sw.Elapsed.TotalSeconds -ge $nextMark) { Write-Host (' ' + $nextMark + ' сек ') -NoNewline; $nextMark += 30 }
    }
    Write-Host ''
    if ($result -eq 'timeout' -and (Test-ServerUp)) { $result = 'ok' }
    return $result
}

# ---------------------------------------------------------------- запуск
function Get-OmniMjs {
    # Тот же файл, который вызывает omniroute.cmd: ...\node_modules\omniroute\bin\omniroute.mjs
    if (-not $script:OmniCmd -or -not $script:NodeExe) { return $null }
    $mjs = Join-Path (Split-Path -Parent $script:OmniCmd) 'node_modules\omniroute\bin\omniroute.mjs'
    if (Test-Path -LiteralPath $mjs) { return $mjs }
    return $null
}

function Start-TrayMode {
    # omniroute serve --tray: скрытый фоновый сервер с наблюдателем (перезапуск при сбое) и значком в трее.
    try {
        $mjs = Get-OmniMjs
        if ($mjs) {
            $p = Start-Process -FilePath $script:NodeExe -ArgumentList ('"' + $mjs + '" serve --tray') -WindowStyle Hidden -PassThru -ErrorAction Stop
        } else {
            $p = Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ""' + $script:OmniCmd + '" serve --tray"') -WindowStyle Hidden -PassThru -ErrorAction Stop
        }
        $null = $p.Handle   # чтобы потом был доступен ExitCode
        return $p
    } catch {
        Write-Warn "Не удалось запустить режим трея: $($_.Exception.Message)"
        return $null
    }
}

function Start-ConsoleMode {
    # Запасной вариант: отдельное свёрнутое окно с "omniroute serve --no-open".
    $mjs = Get-OmniMjs
    if ($mjs) { $cmdLine = '"' + $script:NodeExe + '" "' + $mjs + '" serve --no-open' }
    else { $cmdLine = '"' + $script:OmniCmd + '" serve --no-open' }
    $argLine = '/c title OmniRoute - сервер - не закрывайте это окно & ' + $cmdLine
    try {
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList $argLine -WindowStyle Minimized -PassThru -ErrorAction Stop
        $null = $p.Handle
        return $p
    } catch {
        Write-Err "Не удалось запустить OmniRoute: $($_.Exception.Message)"
        return $null
    }
}

function Show-StartFailure {
    Write-Err 'OmniRoute не ответил вовремя.'
    if ($env:DATA_DIR) {
        $crash = Join-Path $env:DATA_DIR 'server\crash.log'
        if (Test-Path -LiteralPath $crash) {
            Write-Info "Последние строки журнала сбоев ($crash):"
            Get-Content -LiteralPath $crash -Tail 15 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
    }
    Write-Info 'Что можно сделать:'
    Write-Info '  - подождать минуту и снова нажать "OmniRoute - Запустить" (первый старт на Windows бывает долгим);'
    Write-Info '  - открыть "OmniRoute - Меню" -> 9 "Диагностика";'
    Write-Info "  - журнал агента: $($script:LogFile)"
    return $false
}

function Open-Dashboard([string]$SubPath = '') {
    $url = $script:DashUrl + $SubPath
    try { Start-Process $url; Write-Ok "Открываю в браузере: $url" } catch { Write-Warn "Откройте вручную в браузере: $url" }
}

function Open-AfterStart {
    param([switch]$NoBrowser, [switch]$NoChatbox)
    if ($Silent) { return }
    if ($script:OpenBrowser -and -not $NoBrowser) { Open-Dashboard '' }
    if ($script:LaunchChatbox -and -not $NoChatbox) {
        $exe = Find-Chatbox
        if ($exe) {
            if (Get-Process -Name 'Chatbox' -ErrorAction SilentlyContinue) {
                Write-Info 'Chatbox уже открыт.'
            } else {
                try { Start-Process -FilePath $exe; Write-Ok 'Открываю Chatbox.' } catch { Write-Warn "Не удалось открыть Chatbox: $($_.Exception.Message)" }
            }
            if (-not (Test-Path -LiteralPath $script:ChatboxFlag)) { Write-Info 'Совет: подключить Chatbox к OmniRoute - "OmniRoute - Меню" -> пункт 5.' }
        } else {
            Write-Info 'Chatbox не найден. Установить и подключить его поможет "OmniRoute - Меню" -> пункт 5.'
        }
    }
}

# ---------------------------------------------------------------- защита от двойного запуска
function Enter-KitLock {
    # Именованный mutex: два окна агента (двойной щелчок по ярлыку, автозапуск + ярлык) не запускают
    # OmniRoute одновременно. Повторный вход из этого же окна (обновление -> запуск) разрешён.
    if ($script:KitLockDepth -gt 0) { $script:KitLockDepth++; return $true }
    try {
        if (-not $script:KitMutex) { $script:KitMutex = New-Object System.Threading.Mutex -ArgumentList $false, 'Local\OmniRouteKitStart' }
        $got = $false
        try { $got = $script:KitMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        if ($got) { $script:KitLockDepth = 1 }
        return $got
    } catch {
        Write-Log "lock: mutex unavailable ($($_.Exception.Message))"
        return $true   # без mutex лучше запустить, чем не запустить вовсе
    }
}

function Exit-KitLock {
    if ($script:KitLockDepth -le 0) { return }
    $script:KitLockDepth--
    if ($script:KitLockDepth -eq 0 -and $script:KitMutex) { try { $script:KitMutex.ReleaseMutex() } catch { } }
}

function Get-OtherStartWaitSec {
    $s = $script:StartTimeoutSec
    if ($script:PreferTray -and (Test-TraySupported)) { Initialize-TrayTiming; $s = [math]::Max($s, $script:TrayTimeoutSec) }
    return $s
}

# ---------------------------------------------------------------- режим трея: учёт неудач
function Get-TrayFailState {
    # tray-disabled.flag: "<число неудач подряд>|<версия OmniRoute>|<дата>"
    $r = [pscustomobject]@{ Count = 0; Version = ''; Disabled = $false }
    if (-not (Test-Path -LiteralPath $script:TrayFlag)) { return $r }
    try {
        $txt = ((Get-Content -LiteralPath $script:TrayFlag -Raw) | Out-String).Trim()
        $parts = $txt.Split('|')
        if ($parts.Count -ge 2 -and $parts[0] -match '^\d+$') { $r.Count = [int]$parts[0]; $r.Version = $parts[1].Trim() }
    } catch { }
    # после обновления OmniRoute (другая версия) трей пробуется снова; старый формат файла - тоже
    $r.Disabled = ($r.Count -ge $script:TrayMaxFails) -and ($r.Version -eq "$($script:OmniVersion)")
    return $r
}

function Add-TrayFailure {
    $st = Get-TrayFailState
    $n = 1
    if ($st.Version -eq "$($script:OmniVersion)") { $n = $st.Count + 1 }
    try { Set-Content -LiteralPath $script:TrayFlag -Value ("{0}|{1}|{2}" -f $n, $script:OmniVersion, (Get-Date -Format s)) -Encoding Ascii } catch { }
    return $n
}

function Reset-TrayFailures {
    if (Test-Path -LiteralPath $script:TrayFlag) { Remove-Item -LiteralPath $script:TrayFlag -Force -ErrorAction SilentlyContinue }
}

function Invoke-TrayRetry {
    Write-Step 'Режим со значком в трее'
    Reset-TrayFailures
    if (Test-TraySupported) {
        Write-Ok 'Готово: при следующем запуске агент снова попробует режим со значком в трее.'
    } else {
        Write-Info "Счётчик неудач сброшен. Но в OmniRoute $($script:OmniVersion) режим трея набор не использует:"
        Write-Info "до версии $($script:TrayMinVersion) он ждёт запуска сервера ровно 60 с и потом сам его останавливает."
        Write-Info 'Сервер запускается в свёрнутом окне "OmniRoute - сервер". Когда выйдет новая версия - Меню -> 8 "Обновить".'
    }
    return $true
}

# ---------------------------------------------------------------- запуск (основная часть)
function Invoke-Start {
    param([switch]$NoBrowser, [switch]$NoChatbox)
    Write-Step 'Запуск OmniRoute'
    if (Test-ServerUp) {
        Write-Ok "OmniRoute уже работает: $($script:DashUrl)"
        Write-Log 'start: already running'
        Open-AfterStart -NoBrowser:$NoBrowser -NoChatbox:$NoChatbox
        return $true
    }
    if (-not (Enter-KitLock)) {
        Write-Info 'Запуск уже идёт в другом окне агента - жду...'
        Write-Log 'start: another agent window is starting OmniRoute, waiting'
        $res = Wait-ServerReady -TimeoutSec (Get-OtherStartWaitSec)
        if ($res -eq 'ok') {
            Write-Ok 'OmniRoute запущен.'
            Open-AfterStart -NoBrowser:$NoBrowser -NoChatbox:$NoChatbox
            return $true
        }
        Write-Warn 'Другое окно агента ещё не закончило запуск (или ждёт ответа на вопрос).'
        Write-Info 'Посмотрите на панели задач окно "OmniRoute - агент", подождите и нажмите "Запустить" снова.'
        return $false
    }
    try {
        return (Invoke-StartLocked -NoBrowser:$NoBrowser -NoChatbox:$NoChatbox)
    } finally {
        Exit-KitLock
    }
}

function Invoke-StartLocked {
    param([switch]$NoBrowser, [switch]$NoChatbox)
    # проверяем ещё раз, уже под защитой от двойного запуска
    if (Test-ServerUp) {
        Write-Ok "OmniRoute уже работает: $($script:DashUrl)"
        Open-AfterStart -NoBrowser:$NoBrowser -NoChatbox:$NoChatbox
        return $true
    }
    $owners = @(Get-PortOwners)
    if ($owners.Count -gt 0 -or (Test-ServerStarting)) {
        $foreign = @($owners | Where-Object { $_.Name -ne '?' -and $_.Name -ine 'node' })
        if ($foreign.Count -gt 0) {
            Write-Err "Порт $($script:Port) занят другой программой: $($foreign[0].Name) (PID $($foreign[0].Pid))."
            Write-Info 'Закройте эту программу и попробуйте снова (подробности: Меню -> 9 "Диагностика").'
            Write-Log "start: port busy by $($foreign[0].Name)"
            return $false
        }
        Write-Info 'Похоже, OmniRoute уже запускается (например, автозапуском). Жду...'
        $res = Wait-ServerReady -TimeoutSec (Get-OtherStartWaitSec)
        if ($res -eq 'ok') {
            Write-Ok 'OmniRoute запущен.'
            Open-AfterStart -NoBrowser:$NoBrowser -NoChatbox:$NoChatbox
            return $true
        }
        # Второй экземпляр не запускаем: он перезаписал бы PID-файлы первого и подрался бы с ним за порт.
        Write-Log 'start: earlier start did not finish, second instance NOT launched'
        Write-Warn 'OmniRoute уже запущен, но пока не отвечает (ещё стартует или завис). Второй раз не запускаю.'
        Write-Info 'Подождите пару минут и нажмите "OmniRoute - Запустить" снова.'
        Write-Info 'Не помогло: "OmniRoute - Остановить", затем "OmniRoute - Запустить". Подробности: Меню -> 9 "Диагностика".'
        return $false
    }

    $pinned = Set-DataDirPinned
    $traySupported = Test-TraySupported
    $trayState = Get-TrayFailState
    $useTray = $script:PreferTray -and $pinned -and $traySupported -and -not $trayState.Disabled
    if ($script:PreferTray -and -not $traySupported) { Write-Log "start: tray skipped (OmniRoute $($script:OmniVersion) < $($script:TrayMinVersion))" }
    $ok = $false
    if ($useTray) {
        Initialize-TrayTiming
        Write-Info 'Запускаю в фоне со значком в трее (возле часов): omniroute serve --tray'
        Write-Info ('Первый запуск может занять несколько минут (до {0} мин) - OmniRoute докачивает модуль для значка.' -f [math]::Ceiling($script:TrayTimeoutSec / 60))
        $p = Start-TrayMode
        if ($p) {
            $res = Wait-ServerReady -TimeoutSec $script:TrayTimeoutSec -Proc $p -TrayMode
            if ($res -eq 'ok') {
                $ok = $true
                Reset-TrayFailures
                Write-Log 'start: tray mode ok'
            } elseif ($res -eq 'proc-failed') {
                Start-Sleep -Seconds 2
                if (Test-ServerUp) {
                    # сервер отвечает (например, его успел запустить кто-то ещё) - трей тут ни при чём
                    $ok = $true
                    Write-Log "start: tray parent exit $($p.ExitCode), but server is up"
                } else {
                    $n = Add-TrayFailure
                    Write-Warn 'Режим со значком в трее не запустился. Запускаю в свёрнутом окне.'
                    Write-Log "start: tray failed (exit $($p.ExitCode)), failure $n of $($script:TrayMaxFails)"
                    if ($n -ge $script:TrayMaxFails) {
                        Write-Info "Режим со значком не сработал $n раза подряд - дальше агент сразу запускает свёрнутое окно."
                        Write-Info 'Попробовать значок снова: Меню -> 12 (или само после обновления OmniRoute).'
                    }
                }
            } else {
                Write-Log 'start: tray timeout'
                Write-Warn 'Сервер долго не отвечает - возможно, он ещё запускается.'
                return (Show-StartFailure)
            }
        }
    }
    if (-not $ok) {
        Write-Info 'Запускаю сервер в отдельном свёрнутом окне (оно на панели задач, заголовок "OmniRoute - сервер").'
        Write-Info 'Не закрывайте это окно - иначе сервер остановится. Остановить: ярлык "OmniRoute - Остановить".'
        $p = Start-ConsoleMode
        if (-not $p) { return (Show-StartFailure) }
        $res = Wait-ServerReady -TimeoutSec $script:StartTimeoutSec -Proc $p
        if ($res -ne 'ok') { Write-Log "start: console mode $res"; return (Show-StartFailure) }
        Write-Log 'start: console mode ok'
    }
    Write-Ok 'OmniRoute работает!'
    Write-Info "Панель управления:   $($script:DashUrl)"
    Write-Info "Адрес для программ:  $($script:ApiBaseIp)"
    Open-AfterStart -NoBrowser:$NoBrowser -NoChatbox:$NoChatbox
    return $true
}

function Invoke-Open {
    if (Test-ServerUp) { Open-Dashboard ''; return $true }
    Write-Warn 'Сервер OmniRoute сейчас не запущен - запускаю.'
    return (Invoke-Start -NoChatbox)
}

# ---------------------------------------------------------------- остановка
function Stop-TrayLeftovers {
    # значок systray2 OmniRoute (лежит в %USERPROFILE%\.omniroute\runtime), если остался после остановки
    try {
        $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'tray_windows*' })
        foreach ($p in $procs) {
            $path = ''
            try { $path = $p.Path } catch { }
            if ($path -and $path -like '*\.omniroute\*') { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { } }
        }
    } catch { }
}

function Get-OmniKillTargets {
    # Кого завершать, если "omniroute stop" не освободил порт. Сначала НАБЛЮДАТЕЛЯ (supervisor):
    # если убить только сервер (владельца порта), наблюдатель сочтёт это сбоем и запустит сервер снова.
    param([object[]]$PortNodes)
    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $sup = Read-OmniPidFile 'supervisor'
    if ($sup -gt 0) {
        $si = Get-ProcInfo $sup
        if (Test-OmniNodeProc $si) { $list.Add([pscustomobject]@{ Pid = $sup; Role = 'наблюдатель (supervisor)' }); $seen[$sup] = $true }
    }
    foreach ($o in $PortNodes) {
        $ci = Get-ProcInfo $o.Pid
        if (-not $ci -or $ci.ParentPid -le 0 -or $seen.ContainsKey($ci.ParentPid)) { continue }
        $pi = Get-ProcInfo $ci.ParentPid
        if (-not (Test-OmniNodeProc $pi)) { continue }
        # номер родителя мог достаться другому процессу: родитель должен быть старше сервера
        if ($pi.Started -and $ci.Started -and $pi.Started -gt $ci.Started) { continue }
        $list.Add([pscustomobject]@{ Pid = $pi.Pid; Role = 'наблюдатель (supervisor)' })
        $seen[$pi.Pid] = $true
    }
    foreach ($o in $PortNodes) {
        if ($seen.ContainsKey([int]$o.Pid)) { continue }
        $list.Add([pscustomobject]@{ Pid = [int]$o.Pid; Role = 'сервер (порт ' + $script:Port + ')' })
        $seen[[int]$o.Pid] = $true
    }
    return $list.ToArray()
}

function Stop-ProcessTree([int]$Id) {
    # taskkill /T /F завершает процесс вместе с дочерними (сервером, значком трея)
    try { & taskkill.exe /PID $Id /T /F 2>&1 | Out-Null } catch { }
    if (Get-Process -Id $Id -ErrorAction SilentlyContinue) {
        try { Stop-Process -Id $Id -Force -ErrorAction Stop } catch { }
    }
    Start-Sleep -Milliseconds 300
    return (-not (Get-Process -Id $Id -ErrorAction SilentlyContinue))
}

function Test-ServerStopped {
    return (-not (Test-ServerUp)) -and (@(Get-PortOwners).Count -eq 0) -and (-not (Test-ServerStarting))
}

function Invoke-Stop {
    Write-Step 'Остановка OmniRoute'
    $wasUp = Test-ServerUp
    $owners = @(Get-PortOwners)
    if (-not $wasUp -and $owners.Count -eq 0 -and -not (Test-ServerStarting)) {
        Write-Ok 'Сервер не запущен - останавливать нечего.'
        Stop-TrayLeftovers
        return $true
    }
    if ($script:OmniCmd) {
        Write-Info 'Выполняю: omniroute stop  (на Windows это занимает около 5 секунд)'
        & $script:OmniCmd stop | Out-Host
        Write-Log "stop: omniroute stop exit $LASTEXITCODE"
    }
    for ($i = 0; $i -lt 10; $i++) {
        if (-not (Test-ServerUp) -and @(Get-PortOwners).Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }
    $owners = @(Get-PortOwners)
    if ($owners.Count -gt 0 -or (Test-ServerUp) -or (Test-ServerStarting)) {
        if ($owners.Count -gt 0) {
            Write-Warn "Порт $($script:Port) всё ещё занят:"
            foreach ($o in $owners) { Write-Info ("     PID {0}  {1}  {2}" -f $o.Pid, $o.Name, $o.Path) }
        } else {
            Write-Warn 'Процесс OmniRoute ещё работает (возможно, перезапускает сервер).'
        }
        $nodes = @($owners | Where-Object { $_.Name -ieq 'node' })
        $others = @($owners | Where-Object { $_.Name -ine 'node' })
        if ($others.Count -gt 0) { Write-Warn 'Это не node.exe - такие процессы агент не трогает.' }
        $targets = @(Get-OmniKillTargets -PortNodes $nodes)
        if ($targets.Count -gt 0 -and (Read-YesNo 'Завершить процессы OmniRoute (node.exe) принудительно?' $false)) {
            foreach ($t in $targets) {
                if (Stop-ProcessTree $t.Pid) {
                    Write-Ok "Завершён: $($t.Role), PID $($t.Pid)."
                    Write-Log "stop: killed tree pid $($t.Pid) ($($t.Role))"
                } elseif (Get-Process -Id $t.Pid -ErrorAction SilentlyContinue) {
                    Write-Err "Не удалось завершить PID $($t.Pid)."
                }
            }
            # ждём дольше пары секунд: если наблюдатель выжил, он поднимает сервер через 1-10 с
            Write-Host '  Проверяю, что сервер не поднялся снова ' -NoNewline
            for ($i = 0; $i -lt 15; $i++) {
                Start-Sleep -Seconds 1
                Write-Host '.' -NoNewline
                if ($i -ge 7 -and (Test-ServerStopped)) { break }
            }
            Write-Host ''
        }
    }
    if (Test-ServerStopped) {
        Stop-TrayLeftovers
        Write-Ok 'OmniRoute остановлен.'
        return $true
    }
    Write-Err 'Сервер всё ещё работает.'
    Write-Info 'Если он упорно возвращается: перезагрузите компьютер или посмотрите Меню -> 9 "Диагностика".'
    return $false
}

# ---------------------------------------------------------------- состояние
function Get-ModelIds {
    $r = Invoke-Http ($script:LocalUrl + '/v1/models') 8000
    if (-not $r -or $r.Code -ne 200) { return @() }
    try {
        $j = $r.Body | ConvertFrom-Json
        return @($j.data | ForEach-Object { $_.id } | Where-Object { $_ })
    } catch { return @() }
}

function Get-AutostartState {
    $startup = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrEmpty($startup)) { $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup' }
    $vbs = Join-Path $startup 'OmniRoute.vbs'
    $lnk = Join-Path $startup $script:StartupLnkName
    $reg = $null
    try { $reg = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OmniRoute' -ErrorAction Stop).OmniRoute } catch { }
    $vbsOn = Test-Path -LiteralPath $vbs
    $lnkOn = Test-Path -LiteralPath $lnk
    $parts = @()
    if ($vbsOn) { $parts += 'включён (OmniRoute.vbs в автозагрузке, фон со значком в трее)' }
    if ($lnkOn) { $parts += 'включён (ярлык набора в автозагрузке)' }
    if ($reg)   { $parts += 'есть старая запись в реестре Run' }
    $text = 'выключен'
    if ($parts.Count -gt 0) { $text = $parts -join '; ' }
    return [pscustomobject]@{ Vbs = $vbs; Lnk = $lnk; VbsOn = $vbsOn; LnkOn = $lnkOn; Reg = [bool]$reg; On = ($parts.Count -gt 0); Text = $text }
}

function Show-Status {
    Write-Step 'Состояние'
    $up = Test-ServerUp
    if ($up) { Write-Ok "Сервер OmniRoute: РАБОТАЕТ (порт $($script:Port))" } else { Write-Warn 'Сервер OmniRoute: остановлен' }
    foreach ($o in @(Get-PortOwners)) { Write-Info ("     порт {0} слушает: PID {1} {2}" -f $script:Port, $o.Pid, $o.Name) }
    Write-Host ''
    Write-Info "Панель управления (браузер): $($script:DashUrl)"
    Write-Info "Адрес API для Chatbox:       $($script:ApiBaseIp)   (то же самое: $($script:ApiBase))"
    Write-Info "Модель Grok:                 $($script:DefaultModel)"
    Write-Host ''
    Write-Info "Node.js:     $($script:NodeVersion)   $($script:NodeExe)"
    if ($script:OmniCmd) { Write-Info "OmniRoute:   $($script:OmniVersion)   $($script:OmniCmd)" } else { Write-Warn 'OmniRoute: не установлен' }
    $info = Get-DataDirInfo
    Write-Info "Данные:      $($info.Path)   [$($info.Source)]"
    if (-not $info.Persisted) { Write-Info '             (папка ещё не закреплена - закрепится при первом запуске через ярлык)' }
    if ($info.Ambiguous) { Write-Warn 'Найдены две папки данных - подробности в "Диагностике".' }
    $as = Get-AutostartState
    Write-Info "Автозапуск:  $($as.Text)"
    if ($as.VbsOn -and -not (Test-TraySupported)) { Write-Warn 'OmniRoute.vbs в автозагрузке может не запустить сервер в этой версии OmniRoute. Включите автозапуск заново: Меню -> 6.' }
    $cb = Find-Chatbox
    if ($cb) {
        $state = 'закрыт'
        if (Get-Process -Name 'Chatbox' -ErrorAction SilentlyContinue) { $state = 'открыт' }
        Write-Info "Chatbox:     $state   $cb"
    } else { Write-Info 'Chatbox:     не найден (Меню -> 5)' }
    if ($up) {
        $models = @(Get-ModelIds)
        if ($models.Count -gt 0) {
            $gc = @($models | Where-Object { $_ -like 'gc/*' })
            Write-Host ''
            Write-Info "Моделей доступно: $($models.Count). Модели Grok Build (gc/...):"
            if ($gc.Count -eq 0) { Write-Warn 'нет моделей gc/... - проверьте в панели раздел "Провайдеры" (подключение Grok Build).' }
            foreach ($m in @($gc | Select-Object -First 12)) { Write-Info "     $m" }
        }
    }
}

# ---------------------------------------------------------------- автозапуск
function New-KitShortcut {
    param([string]$Path, [string]$Arguments, [int]$WindowStyle = 1, [string]$Description = '', [string]$Icon = '')
    $shell = New-Object -ComObject WScript.Shell
    $s = $shell.CreateShortcut($Path)
    $s.TargetPath = $script:PsExe
    $s.Arguments = $Arguments
    $s.WorkingDirectory = $script:KitDir
    $s.WindowStyle = $WindowStyle
    if ($Description) { $s.Description = $Description }
    if ($Icon) { $s.IconLocation = $Icon }
    $s.Save()
}

function Enable-Autostart {
    Write-Step 'Включение автозапуска при входе в Windows'
    if (-not (Set-DataDirPinned)) {
        Write-Err 'Без закреплённой папки данных автозапуск мог бы открыть "пустой" OmniRoute. Отменено.'
        return $false
    }
    $state = Get-AutostartState
    # Всегда свой ярлык набора ("агент start -Silent"), а не OmniRoute.vbs от "omniroute autostart enable":
    # VBS запускает "serve --tray" без настроек набора - в OmniRoute 3.8.51 его ждёт 60-секундный предел
    # (на холодном старте Windows сервер убивается), и всё происходит скрыто, без единого сообщения.
    # Ярлык набора задаёт время ожидания 3 минуты, слушает только этот ПК и сам выбирает трей или свёрнутое окно.
    if (($state.VbsOn -or $state.Reg) -and $script:OmniCmd) {
        Write-Info 'Убираю OmniRoute.vbs из автозагрузки (вместо него будет ярлык набора): omniroute autostart disable'
        & $script:OmniCmd autostart disable | Out-Host
    }
    if (Test-Path -LiteralPath $state.Vbs) {
        try { Remove-Item -LiteralPath $state.Vbs -Force -ErrorAction Stop } catch { Write-Warn "Не удалось удалить $($state.Vbs): $($_.Exception.Message)" }
    }
    try {
        $args2 = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script:AgentPath + '" start -Silent'
        New-KitShortcut -Path $state.Lnk -Arguments $args2 -WindowStyle 7 -Description 'Автозапуск OmniRoute (OmniRoute-Kit)'
        Write-Ok 'Автозапуск включён: после входа в Windows OmniRoute запустится сам (браузер и Chatbox не открываются).'
        if (Test-TraySupported) { Write-Info 'Сервер будет работать в фоне со значком у часов (или в свёрнутом окне "OmniRoute - сервер").' }
        else { Write-Info 'Сервер будет работать в свёрнутом окне "OmniRoute - сервер" на панели задач - не закрывайте его.' }
        Write-Info "Не перемещайте папку набора ($($script:KitDir)), иначе ярлык перестанет работать."
        Write-Log 'autostart: kit shortcut created'
        return $true
    } catch {
        Write-Err "Не удалось создать ярлык автозагрузки: $($_.Exception.Message)"
        return $false
    }
}

function Disable-Autostart {
    Write-Step 'Выключение автозапуска'
    $state = Get-AutostartState
    if (-not $state.On) { Write-Ok 'Автозапуск и так выключен.'; return $true }
    if (($state.VbsOn -or $state.Reg) -and $script:OmniCmd) {
        Write-Info 'Выполняю: omniroute autostart disable'
        & $script:OmniCmd autostart disable | Out-Host
    }
    if (Test-Path -LiteralPath $state.Lnk) {
        try { Remove-Item -LiteralPath $state.Lnk -Force -ErrorAction Stop; Write-Ok 'Ярлык набора убран из автозагрузки.' } catch { Write-Err $_.Exception.Message }
    }
    $state = Get-AutostartState
    if ($state.VbsOn) {
        if (Read-YesNo "Файл автозапуска $($state.Vbs) всё ещё на месте. Удалить его? (это только ярлык запуска, данные не трогаются)" $true) {
            try { Remove-Item -LiteralPath $state.Vbs -Force -ErrorAction Stop } catch { Write-Err $_.Exception.Message }
        }
    }
    $state = Get-AutostartState
    if (-not $state.VbsOn -and -not $state.LnkOn) {
        Write-Ok 'Автозапуск выключен.'
        Write-Log 'autostart: disabled'
        return $true
    }
    Write-Warn "Автозапуск: $($state.Text)"
    return $false
}

# ---------------------------------------------------------------- обновление
function Get-NpmConfigValue([string]$Key) {
    try {
        $out = @(& $script:NpmCmd config get $Key 2>$null)
        $vals = @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
        if ($vals.Count -gt 0) { return $vals[-1] }
    } catch { }
    return ''
}

function Get-DriveFreeGb([string]$Path) {
    # Свободно на диске, где лежит путь (ГБ, одна цифра после запятой); $null - не удалось узнать
    if ([string]::IsNullOrEmpty($Path)) { return $null }
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if ([string]::IsNullOrEmpty($root) -or $root.StartsWith('\\')) { return $null }
        $d = New-Object System.IO.DriveInfo -ArgumentList $root
        if (-not $d.IsReady) { return $null }
        return [math]::Round($d.AvailableFreeSpace / 1GB, 1)
    } catch { return $null }
}

function Get-UpdateSpaceProblems([double]$NeedGb) {
    # OmniRoute 3.8.51 - около 550 МБ и 27 000 файлов; npm на время установки держит старую и новую копию
    # и ещё кладёт архив в свой кэш. Проверяем диск глобальных пакетов npm и диск кэша npm.
    $items = @(
        [pscustomobject]@{ Label = 'папка глобальных пакетов npm'; Path = (Get-NpmConfigValue 'prefix') },
        [pscustomobject]@{ Label = 'кэш npm'; Path = (Get-NpmConfigValue 'cache') }
    )
    $low = @()
    foreach ($it in $items) {
        $free = Get-DriveFreeGb $it.Path
        if ($null -ne $free -and $free -lt $NeedGb) {
            $low += [pscustomobject]@{ Label = $it.Label; Path = $it.Path; Drive = ([System.IO.Path]::GetPathRoot($it.Path)).TrimEnd('\'); Free = $free }
        }
    }
    return $low
}

function Test-UpdateDiskSpace {
    # Возвращает $true, если места для обновления достаточно. Сервер при этом не трогается.
    $need = 2
    $low = @(Get-UpdateSpaceProblems $need)
    if ($low.Count -eq 0) { return $true }
    foreach ($l in $low) {
        Write-Err ("На диске {0} свободно {1} ГБ, для обновления нужно около {2} ГБ ({3}: {4})." -f $l.Drive, $l.Free, $need, $l.Label, $l.Path)
    }
    Write-Info 'Сервер не останавливался, установленный OmniRoute не тронут.'
    $cacheLow = @($low | Where-Object { $_.Label -eq 'кэш npm' })
    if ($cacheLow.Count -gt 0) {
        $cachePath = $cacheLow[0].Path
        if ((Test-Path -LiteralPath 'E:\') -and ($cachePath -notlike 'E:*')) {
            if (Read-YesNo 'Перенести кэш npm на диск E: (папка E:\npm-cache)? Старый кэш на C: будет очищен - там только скачанные копии пакетов.' $true) {
                Write-Info 'Выполняю: npm cache clean --force'
                & $script:NpmCmd cache clean --force | Out-Host
                Write-Info 'Выполняю: npm config set cache E:\npm-cache'
                & $script:NpmCmd config set cache 'E:\npm-cache' | Out-Host
                Write-Log 'update: npm cache cleaned and moved to E:\npm-cache'
            }
        } elseif (Read-YesNo 'Очистить кэш npm (npm cache clean --force)? Это безопасно: там только скачанные копии пакетов.' $true) {
            Write-Info 'Выполняю: npm cache clean --force'
            & $script:NpmCmd cache clean --force | Out-Host
            Write-Log 'update: npm cache cleaned'
        }
        $low = @(Get-UpdateSpaceProblems $need)
        if ($low.Count -eq 0) { Write-Ok 'Места теперь хватает.'; return $true }
    }
    foreach ($l in $low) { Write-Warn ("Всё ещё мало места на диске {0}: свободно {1} ГБ." -f $l.Drive, $l.Free) }
    Write-Info 'Освободите место (например: Пуск -> "Очистка диска", удалить ненужные файлы из "Загрузки") и повторите обновление.'
    Write-Log 'update: refused, low disk space'
    return $false
}

function Invoke-Update {
    Write-Step 'Обновление OmniRoute'
    if (-not (Find-Npm)) { Write-Err 'npm не найден (ставится вместе с Node.js).'; return $false }
    Write-Info "Установлена версия: $($script:OmniVersion)"
    Write-Info 'Проверяю последнюю версию (нужен интернет)...'
    $latest = ''
    try { $latest = ((& $script:NpmCmd view omniroute version 2>$null) | Out-String).Trim() } catch { }
    if ($latest) { Write-Info "Последняя версия:   $latest" } else { Write-Warn 'Не удалось узнать последнюю версию (нет интернета?).' }
    if ($latest -and $latest -eq $script:OmniVersion) { Write-Ok 'У вас уже последняя версия.'; return $true }
    # место проверяем ДО вопроса и ДО остановки сервера: при нехватке места npm мог бы оставить OmniRoute недоустановленным
    if (-not (Test-UpdateDiskSpace)) { return $false }
    if (-not (Read-YesNo 'Обновить OmniRoute сейчас? Сервер будет остановлен и запущен снова.' $false)) { Write-Info 'Отменено.'; return $true }
    if (-not (Enter-KitLock)) {
        Write-Err 'В другом окне агента сейчас запускается OmniRoute. Дождитесь окончания и повторите обновление.'
        return $false
    }
    try {
        $wasUp = (Test-ServerUp) -or (@(Get-PortOwners).Count -gt 0)
        if ($wasUp) {
            if (-not (Invoke-Stop)) { Write-Err 'Сервер не остановился - обновление отменено (файлы были бы заняты).'; return $false }
        }
        [void](Set-DataDirPinned)   # обновление делает резервную копию в %USERPROFILE%\.omniroute
        Write-Info 'Выполняю: npm install -g omniroute@latest --include=optional --legacy-peer-deps'
        & $script:NpmCmd install -g omniroute@latest --include=optional --legacy-peer-deps | Out-Host
        $code = $LASTEXITCODE
        [void](Find-OmniRoute)
        if ($code -ne 0) {
            Write-Err "npm завершился с ошибкой (код $code)."
            Write-Info 'Частые причины: нет интернета; файлы заняты (закройте все окна OmniRoute); мало места на диске C:.'
            Write-Log "update: npm failed ($code)"
            if ($wasUp) { Write-Info 'Запускаю OmniRoute обратно...'; [void](Invoke-Start -NoBrowser -NoChatbox) }
            return $false
        }
        Write-Ok "Готово. Версия OmniRoute: $($script:OmniVersion)"
        Write-Log "update: ok -> $($script:OmniVersion)"
        if ($wasUp) { [void](Invoke-Start -NoChatbox) }
        return $true
    } finally {
        Exit-KitLock
    }
}

# ---------------------------------------------------------------- диагностика
function Get-FolderSizeMb([string]$Path) {
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if (-not $sum) { $sum = 0 }
        return [math]::Round($sum / 1MB, 1)
    } catch { return 0 }
}

function Invoke-Doctor {
    Write-Step 'Диагностика'
    Write-Info "Windows PowerShell: $($PSVersionTable.PSVersion)"
    try {
        $pol = @(Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" })
        Write-Info ('Политика скриптов: ' + ($pol -join ', '))
        $eff = "$(Get-ExecutionPolicy)"
        if (@('Restricted', 'AllSigned') -contains $eff) {
            Write-Warn 'Команда "omniroute" напрямую в PowerShell может блокироваться. Ярлыки набора это обходят (-ExecutionPolicy Bypass).'
            Write-Info '     Разрешить для себя (без прав администратора): Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'
        }
    } catch { }

    # Node.js: тот же диапазон, что проверяет сам OmniRoute (engines.node), иначе omniroute сразу завершается
    $nv = $script:NodeVersion
    $ns = Get-NodeSupport
    if ($ns.State -eq 'ok') { Write-Ok "Node.js $nv  ($($script:NodeExe))  - подходит (нужно: $($ns.Range))" }
    elseif ($ns.State -eq 'bad') { Show-NodeSupportWarning $ns }
    else { Write-Warn "Node.js $nv - не удалось проверить версию. Рекомендуется 24 LTS (https://nodejs.org)." }

    # npm
    if (Find-Npm) {
        $prefix = ''; $cache = ''
        try { $prefix = ((& $script:NpmCmd config get prefix 2>$null) | Out-String).Trim() } catch { }
        try { $cache = ((& $script:NpmCmd config get cache 2>$null) | Out-String).Trim() } catch { }
        Write-Info "npm: $($script:NpmCmd)"
        Write-Info "     глобальные пакеты: $prefix"
        Write-Info "     кэш npm:           $cache"
        if ($cache -like 'C:*') { Write-Info '     (кэш можно перенести на E:, если мало места: npm config set cache E:\npm-cache)' }
    } else { Write-Warn 'npm не найден.' }

    # OmniRoute
    if ($script:OmniCmd) { Write-Ok "OmniRoute $($script:OmniVersion)  ($($script:OmniCmd))" } else { Write-Err 'OmniRoute не установлен (npm install -g omniroute).' }

    # данные
    $info = Get-DataDirInfo
    Write-Info "Папка данных: $($info.Path)  [$($info.Source)]"
    $userDd = [Environment]::GetEnvironmentVariable('DATA_DIR', 'User')
    if ($userDd) { Write-Info "     DATA_DIR (пользователь) = $userDd" } else { Write-Warn 'DATA_DIR не закреплена (закрепится при запуске через ярлык).' }
    foreach ($d in @($info.AppDir, $info.HomeDir)) {
        if (Test-Path -LiteralPath $d) {
            $db = Test-Path -LiteralPath (Join-Path $d 'storage.sqlite')
            $envf = Test-Path -LiteralPath (Join-Path $d '.env')
            Write-Info ("     {0}: база={1}, .env(ключ шифрования)={2}, размер={3} МБ" -f $d, $db, $envf, (Get-FolderSizeMb $d))
        }
    }
    if ($info.Ambiguous) {
        Write-Warn 'Есть ДВЕ папки с базой, и ни одна не закреплена. При запуске ярлыком "OmniRoute - Запустить"'
        Write-Warn 'агент покажет обе и спросит, какая ваша (там пароль и Grok Build).'
        Write-Info ("     1) {0}: {1}" -f $info.AppDir, (Format-DbStat $info.AppStat))
        Write-Info ("     2) {0}: {1}" -f $info.HomeDir, (Format-DbStat $info.HomeStat))
    }
    if ($info.Path -and -not (Test-Path -LiteralPath (Join-Path $info.Path '.env')) -and (Test-Path -LiteralPath (Join-Path $info.Path 'storage.sqlite'))) {
        Write-Warn 'В папке данных нет .env - без ключа шифрования сохранённые входы провайдеров не расшифруются.'
    }

    # порт и сервер
    $owners = @(Get-PortOwners)
    if ($owners.Count -eq 0) { Write-Info "Порт $($script:Port): свободен" }
    foreach ($o in $owners) { Write-Info ("Порт {0}: занят PID {1} {2} {3}" -f $script:Port, $o.Pid, $o.Name, $o.Path) }
    if (Test-ServerUp) {
        Write-Ok "Сервер отвечает: $($script:LocalUrl)/api/health"
        $ping = Invoke-Http ($script:LocalUrl + '/api/health/ping') 5000
        if ($ping -and $ping.Code -eq 200) { Write-Ok 'База данных отвечает (/api/health/ping)' }
        elseif ($ping) { Write-Warn "База данных: код $($ping.Code) (/api/health/ping)" }
    } else { Write-Warn 'Сервер не отвечает.' }

    # диски
    foreach ($letter in @('C', 'E')) {
        $drv = Get-PSDrive -Name $letter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($drv -and $null -ne $drv.Free) {
            $free = [math]::Round($drv.Free / 1GB, 1)
            if ($letter -eq 'C' -and $free -lt 2) { Write-Warn "Диск C: свободно всего $free ГБ - OmniRoute и npm могут работать с ошибками." }
            else { Write-Info "Диск ${letter}: свободно $free ГБ" }
        } elseif ($letter -eq 'E') { Write-Info 'Диск E: не найден' }
    }

    # прочее
    $as = Get-AutostartState
    Write-Info "Автозапуск: $($as.Text)"
    if ($as.VbsOn -and -not (Test-TraySupported)) { Write-Warn 'В автозагрузке OmniRoute.vbs: в этой версии OmniRoute он может не запустить сервер (предел 60 с). Включите автозапуск заново: Меню -> 6.' }
    if (-not (Test-TraySupported)) {
        Write-Info "Режим со значком в трее: не используется - в OmniRoute $($script:OmniVersion) он ждёт запуска только 60 с (исправлено в $($script:TrayMinVersion)). Сервер запускается в свёрнутом окне."
    } else {
        $ts = Get-TrayFailState
        if ($ts.Disabled) { Write-Info "Режим со значком в трее отключён после $($ts.Count) неудач подряд. Попробовать снова: Меню -> 12." }
        elseif ($ts.Count -gt 0 -and $ts.Version -eq "$($script:OmniVersion)") { Write-Info "Режим со значком в трее: неудач подряд - $($ts.Count) (после $($script:TrayMaxFails) агент переходит на свёрнутое окно)." }
        else { Write-Info 'Режим со значком в трее: используется.' }
    }
    $hostVal = "$env:OMNIROUTE_SERVER_HOST"
    if (@('127.0.0.1', 'localhost', '::1', '[::1]') -contains $hostVal) { Write-Ok "Доступ к OmniRoute: только с этого компьютера (OMNIROUTE_SERVER_HOST=$hostVal)" }
    elseif ($hostVal) { Write-Warn "OmniRoute открыт для сети (OMNIROUTE_SERVER_HOST=$hostVal): без REQUIRE_API_KEY=true им может пользоваться любой в вашей сети." }
    $cb = Find-Chatbox
    if ($cb) { Write-Info "Chatbox: $cb" } else { Write-Info 'Chatbox: не найден' }
    if ($info.Path) {
        $crash = Join-Path $info.Path 'server\crash.log'
        if (Test-Path -LiteralPath $crash) {
            Write-Warn "Есть журнал сбоев: $crash (последние строки):"
            Get-Content -LiteralPath $crash -Tail 10 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        }
        $appLog = Join-Path $info.Path 'logs\application\app.log'
        if (Test-Path -LiteralPath $appLog) { Write-Info "Журнал приложения: $appLog" }
    }
    Write-Info "Журнал агента: $($script:LogFile)"

    if ($script:OmniCmd) {
        Write-Step 'Встроенная проверка OmniRoute: omniroute doctor'
        & $script:OmniCmd doctor | Out-Host
    }
}

# ---------------------------------------------------------------- Chatbox
function Find-Chatbox {
    try {
        $p = Get-Process -Name 'Chatbox' -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
        if ($p) { return $p.Path }
    } catch { }
    $cands = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA) { $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\Chatbox\Chatbox.exe')) }
    if ($env:ProgramFiles) { $cands.Add((Join-Path $env:ProgramFiles 'Chatbox\Chatbox.exe')) }
    foreach ($c in @('E:\Programs\Chatbox\Chatbox.exe', 'E:\Program Files\Chatbox\Chatbox.exe', 'E:\Chatbox\Chatbox.exe')) { $cands.Add($c) }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        foreach ($k in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if (-not $props -or -not $props.DisplayName -or -not ("$($props.DisplayName)" -like 'Chatbox*')) { continue }
            if ($props.InstallLocation) {
                $e = Join-Path ("$($props.InstallLocation)".Trim('"')) 'Chatbox.exe'
                if (Test-Path -LiteralPath $e) { return $e }
            }
            if ($props.DisplayIcon) {
                $e = ("$($props.DisplayIcon)" -replace ',\s*-?\d+$', '').Trim('"')
                if ($e -like '*.exe' -and (Test-Path -LiteralPath $e)) { return $e }
            }
        }
    }
    try {
        $cmd = (Get-ItemProperty -Path 'Registry::HKEY_CLASSES_ROOT\chatbox\shell\open\command' -ErrorAction Stop).'(default)'
        if ("$cmd" -match '^\s*"([^"]+\.exe)"') { if (Test-Path -LiteralPath $Matches[1]) { return $Matches[1] } }
    } catch { }
    $lnks = @()
    if ($env:APPDATA) { $lnks += (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Chatbox.lnk') }
    if ($env:ProgramData) { $lnks += (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Chatbox.lnk') }
    foreach ($lnk in $lnks) {
        if (-not (Test-Path -LiteralPath $lnk)) { continue }
        try {
            $t = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath
            if ($t -and (Test-Path -LiteralPath $t)) { return $t }
        } catch { }
    }
    return $null
}

function Get-KeyFromOutput([string]$Text) {
    # Ключ OmniRoute: sk-{machineId}-{keyId}-{crc}
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    try {
        $start = $Text.IndexOf('{')
        $end = $Text.LastIndexOf('}')
        if ($start -ge 0 -and $end -gt $start) {
            $j = $Text.Substring($start, $end - $start + 1) | ConvertFrom-Json
            foreach ($cand in @($j.key, $j.data.key, $j.apiKey, $j.data.apiKey, $j.result.key)) {
                if ($cand -and ("$cand" -match '^sk-[0-9A-Za-z_-]+$') -and ("$cand" -notmatch '\*')) { return "$cand" }
            }
        }
    } catch { }
    $m = [regex]::Match($Text, 'sk-[0-9A-Za-z]{6,}-[0-9A-Za-z]{4,}-[0-9A-Za-z]{4,}')
    if ($m.Success) { return $m.Value }
    return $null
}

function New-OmniApiKey {
    if (-not $script:OmniCmd) { return $null }
    $tmp = Join-Path $env:TEMP 'omniroute-kit-newkey.json'
    $out = ''
    $code = 1
    try {
        # файл в ASCII (без BOM): PowerShell 5.1 портит кавычки в JSON-аргументах, а BOM ломает JSON.parse
        Set-Content -LiteralPath $tmp -Value '{"name":"Chatbox"}' -Encoding Ascii
        Write-Info 'Создаю ключ: omniroute api api-keys post-api-keys --body @файл'
        $out = (& $script:OmniCmd api api-keys post-api-keys --body ('@' + $tmp) --output json 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } catch {
        $out = ''
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    Write-Log "newkey: exit $code"
    if ($code -ne 0) { return $null }
    return (Get-KeyFromOutput $out)
}

function New-ChatboxConfigJson {
    param([string]$ApiHost, [string]$ApiKey, [string[]]$Models)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($m in $Models) { $list.Add([ordered]@{ modelId = $m; type = 'chat' }) }
    $cfg = [ordered]@{
        id       = 'omniroute-local'
        name     = 'OmniRoute'
        type     = 'openai'
        isCustom = $true
        settings = [ordered]@{
            apiHost = $ApiHost
            apiPath = '/chat/completions'
            apiKey  = $ApiKey
            models  = $list.ToArray()
        }
    }
    return ($cfg | ConvertTo-Json -Depth 6 -Compress)
}

function Show-ChatboxManual {
    Write-Host ''
    Write-Info 'Ручная настройка Chatbox (если понадобится):'
    Write-Info '  Настройки -> Провайдер моделей -> Добавить -> "Добавить своего провайдера"'
    Write-Info '  Имя: OmniRoute;  Режим API: "Совместимо с OpenAI API" -> Добавить'
    Write-Info "  Хост API: $($script:ApiBaseIp)      Путь API: /chat/completions"
    Write-Info '  API Key:  ваш ключ OmniRoute (sk-...)'
    Write-Info "  Модели:   кнопка ""Получить"" и добавить $($script:DefaultModel) (или ""Новый"" и ввести вручную), затем ""Проверить"""
    Write-Info '  Важно: адрес начинается с http:// (не https).'
}

function Invoke-ChatboxSetup {
    Write-Step 'Chatbox + OmniRoute'
    $exe = Find-Chatbox
    if (-not $exe) {
        Write-Warn 'Chatbox на этом компьютере не найден.'
        Write-Info 'Как установить:'
        Write-Info '  1) Скачайте установщик для Windows: https://chatboxai.app/?c=download-windows'
        Write-Info '  2) При установке выберите "Только для меня" и папку, например E:\Programs\Chatbox (чтобы не занимать диск C:).'
        Write-Info '     Если установщик попросит Microsoft Visual C++ Redistributable - согласитесь.'
        Write-Info '  3) Снова выберите этот пункт меню - агент подключит Chatbox к OmniRoute.'
        if (Read-YesNo 'Открыть страницу загрузки Chatbox в браузере?' $true) {
            try { Start-Process 'https://chatboxai.app/?c=download-windows' } catch { Write-Warn 'Откройте адрес вручную.' }
        }
        return $true
    }
    Write-Ok "Chatbox найден: $exe"
    if (-not (Test-ServerUp)) {
        Write-Info 'Для подключения нужен работающий OmniRoute. Запускаю...'
        if (-not (Invoke-Start -NoBrowser -NoChatbox)) { return $false }
    }
    if (-not (Read-YesNo 'Добавить в Chatbox провайдера "OmniRoute" автоматически?' $true)) {
        Show-ChatboxManual
        return $true
    }

    Write-Host ''
    Write-Info 'Chatbox нужен ключ OmniRoute (вида sk-...).'
    Write-Info 'Если ключ уже есть - вставьте его (правый щелчок мыши в этом окне = вставить).'
    $key = Read-Host '  Ключ (или просто Enter - агент создаст новый ключ сам)'
    if ($null -eq $key) { $key = '' }
    $key = $key.Trim()
    if ($key -eq '') {
        $key = New-OmniApiKey
        if ($key) {
            Write-Ok "Создан новый ключ: $key"
            Write-Info 'Ключ показывается только один раз. Он будет сохранён в Chatbox, но лучше перепишите его себе.'
        } else {
            Write-Warn 'Создать ключ автоматически не получилось. Сделаем вручную в панели:'
            Write-Info '  "Менеджер API" -> "Создать ключ API" -> имя Chatbox -> "Создать ключ API" -> "Копировать".'
            Open-Dashboard '/dashboard/api-manager'
            $key = Read-Host '  Вставьте скопированный ключ и нажмите Enter (Enter без ключа - пропустить)'
            if ($null -eq $key) { $key = '' }
            $key = $key.Trim()
            if ($key -eq '') {
                $key = 'sk-omniroute-local'
                Write-Warn 'Ставлю временную заглушку. Она работает, пока в OmniRoute выключен REQUIRE_API_KEY (так по умолчанию).'
            }
        }
    }

    $models = New-Object System.Collections.Generic.List[string]
    $all = @(Get-ModelIds)
    if ($all -contains $script:DefaultModel) { $models.Add($script:DefaultModel) }
    foreach ($m in $all) {
        if ($models.Count -ge 8) { break }
        if ($m -like 'gc/*' -and -not $models.Contains($m)) { $models.Add($m) }
    }
    if ($models.Count -eq 0) { $models.Add($script:DefaultModel) }

    $json = New-ChatboxConfigJson -ApiHost $script:ApiBaseIp -ApiKey $key -Models $models.ToArray()
    try { Set-Clipboard -Value $json } catch { }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
    $link = 'chatbox://provider/import?config=' + $b64
    $sent = $false
    try { Start-Process -FilePath $exe -ArgumentList $link -ErrorAction Stop; $sent = $true } catch { }
    if (-not $sent) { try { Start-Process $link -ErrorAction Stop; $sent = $true } catch { } }
    Write-Log "chatbox: import link sent=$sent models=$($models -join ',')"
    if ($sent) {
        Write-Ok 'Настройки отправлены в Chatbox.'
        Write-Info 'В Chatbox должно появиться окно "Импорт конфигурации провайдера" - нажмите "Сохранить".'
    } else {
        Write-Warn 'Не удалось открыть Chatbox со ссылкой импорта.'
    }
    Write-Info 'Если окно не появилось: Chatbox -> Настройки -> Провайдер моделей -> Добавить ->'
    Write-Info '"Импортировать из буфера обмена" (настройки уже скопированы в буфер обмена).'
    Write-Info "Затем в чате выберите модель $($models[0]) (провайдер OmniRoute) и напишите сообщение."
    Show-ChatboxManual
    try { Set-Content -LiteralPath $script:ChatboxFlag -Value (Get-Date -Format s) -Encoding Ascii } catch { }
    return $true
}

# ---------------------------------------------------------------- перенос данных
function Move-OmniData {
    Write-Step 'Перенос данных OmniRoute на диск E:'
    $info = Get-DataDirInfo
    if ($info.Ambiguous) {
        # сначала выяснить, какая из двух папок ваша - переносить нужно именно её
        if (-not (Set-DataDirPinned)) { Write-Err 'Папка данных не выбрана - перенос отменён.'; return $false }
        $info = Get-DataDirInfo
    }
    $src = "$($info.Path)".TrimEnd('\')
    Write-Info "Сейчас данные лежат в: $src"
    if (-not (Test-Path -LiteralPath (Join-Path $src 'storage.sqlite'))) { Write-Warn 'В этой папке нет базы storage.sqlite - переносить нечего.'; return $false }
    if (-not (Test-Path -LiteralPath 'E:\')) { Write-Err 'Диск E: не найден.'; return $false }
    if ($src -like 'E:\*') { Write-Ok 'Данные уже на диске E:.'; return $true }
    $default = 'E:\OmniRoute\data'
    $target = Read-Host "  Новая папка (Enter = $default)"
    if ([string]::IsNullOrWhiteSpace($target)) { $target = $default }
    $target = $target.Trim().Trim('"').TrimEnd('\')
    if ($target -notmatch '^[A-Za-z]:\\.+') { Write-Err 'Укажите полный путь, например E:\OmniRoute\data'; return $false }
    if (Test-Path -LiteralPath $target) {
        if (@(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-Err "Папка $target не пустая. Чтобы ничего не перезаписать, выберите пустую или новую папку."
            return $false
        }
    }
    Write-Info ("Размер данных: {0} МБ" -f (Get-FolderSizeMb $src))
    Write-Info 'Что сделает агент:'
    Write-Info '  1) остановит сервер;'
    Write-Info "  2) СКОПИРУЕТ все файлы (включая .env с ключом шифрования) в $target;"
    Write-Info '  3) пропишет DATA_DIR = новая папка;'
    Write-Info '  4) запустит сервер уже с новой папкой.'
    Write-Info "Старая папка НЕ удаляется - она останется резервной копией: $src"
    if (-not (Read-YesNo 'Продолжить?' $false)) { Write-Info 'Отменено.'; return $true }
    if (-not (Enter-KitLock)) {
        Write-Err 'В другом окне агента сейчас запускается OmniRoute. Дождитесь окончания и повторите перенос.'
        return $false
    }
    try { return (Move-OmniDataLocked -Src $src -Target $target -Info $info) } finally { Exit-KitLock }
}

function Move-OmniDataLocked {
    param([string]$Src, [string]$Target, $Info)
    $src = $Src; $target = $Target; $info = $Info
    if ((Test-ServerUp) -or @(Get-PortOwners).Count -gt 0 -or (Test-ServerStarting)) {
        if (-not (Invoke-Stop)) { Write-Err 'Сервер не остановился - перенос отменён, ничего не изменено.'; return $false }
    }
    try { New-Item -ItemType Directory -Force -Path $target -ErrorAction Stop | Out-Null } catch { Write-Err "Не удалось создать папку: $($_.Exception.Message)"; return $false }
    $rcArgs = @($src, $target, '/E', '/R:1', '/W:1', '/XF', '.pid', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
    if ($src -ieq "$($info.HomeDir)".TrimEnd('\')) { $rcArgs += @('/XD', (Join-Path $src 'runtime')) }
    Write-Info 'Копирую...'
    & robocopy.exe @rcArgs | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) { Write-Err "Копирование не удалось (robocopy, код $rc). DATA_DIR не менялась, старая папка на месте."; return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'storage.sqlite'))) { Write-Err 'После копирования нет storage.sqlite - перенос отменён, DATA_DIR не менялась.'; return $false }
    if ((Test-Path -LiteralPath (Join-Path $src '.env')) -and -not (Test-Path -LiteralPath (Join-Path $target '.env'))) {
        Write-Err 'Не скопировался .env (ключ шифрования) - перенос отменён, DATA_DIR не менялась.'
        return $false
    }
    try {
        [Environment]::SetEnvironmentVariable('DATA_DIR', $target, 'User')
        $env:DATA_DIR = $target
    } catch { Write-Err "Не удалось сохранить DATA_DIR: $($_.Exception.Message)"; return $false }
    Write-Ok "Данные скопированы. DATA_DIR = $target"
    Write-Log "move-data: $src -> $target"
    $ok = Invoke-Start -NoChatbox
    Write-Host ''
    Write-Info 'Проверьте в панели: вход прежним паролем, в "Провайдеры" есть Grok Build.'
    Write-Info 'Если что-то не так - вернуть старую папку можно командой в PowerShell:'
    Write-Info "  [Environment]::SetEnvironmentVariable('DATA_DIR','$src','User')"
    Write-Info "Когда всё проверите (через пару дней), старую папку $src можно удалить вручную - это освободит место на C:."
    return $ok
}

# ---------------------------------------------------------------- справка
function Show-Help {
    $lines = @(
        '',
        '  КАК ВСЁ СВЯЗАНО',
        '  ---------------',
        '  1) PowerShell / ярлык - это только "кнопка запуска". Он запускает OmniRoute.',
        '  2) OmniRoute - программа-сервер на ВАШЕМ компьютере, адрес localhost, порт 20128.',
        '     У неё два "входа" на одном адресе:',
        '       http://localhost:20128      - панель управления в браузере (ключи, провайдеры, настройки);',
        '       http://127.0.0.1:20128/v1   - вход для программ-чатов (OpenAI-совместимый API).',
        '  3) Chatbox - окно чата. Он отправляет ваш вопрос в OmniRoute (на /v1),',
        '     OmniRoute пересылает его в Grok через ваш вход Grok Build и возвращает ответ.',
        '',
        '     [Ярлык] --запускает--> [OmniRoute :20128] ----> [Grok, вход Grok Build]',
        '                                   ^',
        '     [Chatbox] --вопрос/ответ------+',
        '',
        '  ПОРЯДОК',
        '    1. Запустить OmniRoute (ярлык "OmniRoute - Запустить").',
        '    2. Один раз: подключить Chatbox (Меню -> 5; ключ создаётся сам).',
        '    3. Писать в Chatbox, модель gc/grok-4.7.',
        '    OmniRoute выключен -> Chatbox покажет ошибку соединения.',
        '    "omniroute", запущенный вручную в окне PowerShell, останавливается, если закрыть это окно.',
        '    Ярлык запускает сервер в отдельном свёрнутом окне "OmniRoute - сервер"',
        '    (в OmniRoute 3.8.52 и новее - в фоне со значком у часов).',
        '    OmniRoute слушает только этот компьютер (127.0.0.1): с других устройств сети он недоступен.',
        '',
        '  ГДЕ ЧТО ИСКАТЬ - панель OmniRoute (http://localhost:20128):',
        '    Провайдеры       - подключённые аккаунты (Grok Build), кнопка "Тест".',
        '    Менеджер API     - "Создать ключ API" (ключ показывают ОДИН раз - сразу скопируйте).',
        '    Конечные точки   - адрес для программ http://localhost:20128/v1.',
        '    Модели и комбо   - список моделей, кнопка "Проверить".',
        '    Площадка         - чат-тест прямо в браузере.',
        '    Журналы          - история запросов и ошибок.',
        '    Настройки -> Безопасность - смена пароля (по умолчанию CHANGEME).',
        '',
        '  ГДЕ ЧТО ИСКАТЬ - Chatbox:',
        '    Настройки -> Провайдер моделей -> OmniRoute: Хост API, API Key, Модели, кнопка "Проверить".',
        '    Хост API: http://127.0.0.1:20128/v1   Путь API: /chat/completions   Модель: gc/grok-4.7',
        '',
        '  КОМАНДЫ ВРУЧНУЮ - только в НОВОМ окне PowerShell:',
        '    (окно, открытое до первого запуска ярлыком, не знает папку ваших данных DATA_DIR,',
        '     и OmniRoute там откроет пустой профиль: пароль CHANGEME, нет Grok Build.',
        '     Закройте такое окно и откройте новое - ваши данные на месте.)',
        '    omniroute             - запустить (окно не закрывать)',
        '    omniroute stop        - остановить',
        '    omniroute health      - работает ли сервер',
        '    omniroute models gc   - модели Grok Build (сервер должен работать)',
        '    omniroute doctor      - диагностика'
    )
    foreach ($l in $lines) { Write-Host $l }
}

# ---------------------------------------------------------------- меню
function Show-Menu {
    while ($true) {
        try { Clear-Host } catch { }
        $up = Test-ServerUp
        Write-Host ''
        Write-Host '  ================================================' -ForegroundColor DarkCyan
        Write-Host '     OmniRoute - меню агента' -ForegroundColor Cyan
        Write-Host '  ================================================' -ForegroundColor DarkCyan
        if ($up) { Write-Host "     Сервер: РАБОТАЕТ   $($script:DashUrl)" -ForegroundColor Green }
        else { Write-Host '     Сервер: остановлен' -ForegroundColor Yellow }
        Write-Host ''
        Write-Host '    1  Запустить всё (сервер + браузер + Chatbox)'
        Write-Host '    2  Остановить сервер'
        Write-Host '    3  Состояние (адреса, версии, модели)'
        Write-Host '    4  Открыть панель OmniRoute в браузере'
        Write-Host '    5  Chatbox: установить / подключить к OmniRoute'
        Write-Host '    6  Включить автозапуск при входе в Windows'
        Write-Host '    7  Выключить автозапуск'
        Write-Host '    8  Обновить OmniRoute'
        Write-Host '    9  Диагностика (если что-то не работает)'
        Write-Host '   10  Перенести данные OmniRoute на диск E:'
        Write-Host '   11  Как всё устроено и где что искать'
        Write-Host '   12  Снова пробовать режим со значком в трее'
        Write-Host '    0  Выход'
        Write-Host ''
        $choice = Read-Host '  Введите номер и нажмите Enter'
        if ($null -eq $choice) { return }
        $choice = $choice.Trim()
        if ($choice -eq '') { continue }
        if ($choice -eq '0') { return }
        try {
            switch ($choice) {
                '1'  { [void](Invoke-Start) }
                '2'  { [void](Invoke-Stop) }
                '3'  { Show-Status }
                '4'  { [void](Invoke-Open) }
                '5'  { [void](Invoke-ChatboxSetup) }
                '6'  { [void](Enable-Autostart) }
                '7'  { [void](Disable-Autostart) }
                '8'  { [void](Invoke-Update) }
                '9'  { Invoke-Doctor }
                '10' { [void](Move-OmniData) }
                '11' { Show-Help }
                '12' { [void](Invoke-TrayRetry) }
                default { Write-Warn 'Нет такого пункта.' }
            }
        } catch {
            Write-Err "Ошибка: $($_.Exception.Message)"
            Write-Log "menu error: $($_.Exception.Message)"
        }
        Wait-Enter 'Нажмите Enter, чтобы вернуться в меню'
    }
}

# ---------------------------------------------------------------- точка входа
Initialize-Console
$act = "$Action".Trim().ToLower()
$known = @('start', 'stop', 'status', 'open', 'chatbox', 'autostart-on', 'autostart-off', 'update', 'doctor', 'move-data', 'tray-retry', 'help', 'menu')
if ($known -notcontains $act) {
    Write-Err "Неизвестное действие: $Action"
    Write-Info ('Доступные действия: ' + ($known -join ', '))
    Exit-Agent $false
}
if ($act -eq 'help') { Show-Help; Exit-Agent $true }

try {
    $needOmni = -not (@('status', 'doctor') -contains $act)
    if (-not (Initialize-Agent -NeedOmni $needOmni)) { Exit-Agent $false }
    switch ($act) {
        'start'         { $ok = Invoke-Start;        Exit-Agent $ok 6 }
        'stop'          { $ok = Invoke-Stop;         Exit-Agent $ok }
        'status'        { Show-Status;               Exit-Agent $true }
        'open'          { $ok = Invoke-Open;         Exit-Agent $ok 2 }
        'chatbox'       { $ok = Invoke-ChatboxSetup; Exit-Agent $ok }
        'autostart-on'  { $ok = Enable-Autostart;    Exit-Agent $ok }
        'autostart-off' { $ok = Disable-Autostart;   Exit-Agent $ok }
        'update'        { $ok = Invoke-Update;       Exit-Agent $ok }
        'doctor'        { Invoke-Doctor;             Exit-Agent $true }
        'move-data'     { $ok = Move-OmniData;       Exit-Agent $ok }
        'tray-retry'    { $ok = Invoke-TrayRetry;    Exit-Agent $ok }
        'menu'          { Show-Menu;                 exit 0 }
    }
} catch {
    Write-Err "Непредвиденная ошибка: $($_.Exception.Message)"
    Write-Log "fatal ($act): $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"
    Exit-Agent $false
}
