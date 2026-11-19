# ------------------------------------------------------------------
#  DSRC CRM — синхронизация папки с GitHub (код + данные)
#  Запуск вручную: двойной клик по sync.bat
#  Автоматически:  задача Планировщика (см. setup-schedule.ps1)
#
#  Порядок: 1) проверка паролей  2) commit своих изменений
#           3) получение изменений из GitHub (merge)  4) push
#  Данные каждого компьютера лежат в своем файле data/nodes/<компьютер>.json,
#  поэтому в Git они не конфликтуют. Общие файлы data/latest и data/history
#  при конфликте берутся локальные — CRM всё равно пересоберет их после слияния.
#  Конфликт в коде (index.html и др.) скрипт НЕ решает сам — остановится.
# ------------------------------------------------------------------
param([string]$Message = "")

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Set-Location -LiteralPath $PSScriptRoot
$LogFile = Join-Path $PSScriptRoot "sync.log"

function Log([string]$t) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $t
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}
function RunGit { $cmd = $args[0]; $out = & git @args 2>&1; $code = $LASTEXITCODE; $out | ForEach-Object { if ("$_".Trim()) { Log "   git ${cmd}: $_" } }; return $code }

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git не установлен. Установите Git for Windows: https://git-scm.com/download/win" }
    & git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE) { throw "Папка не является git-репозиторием (сначала init-repo.ps1 или git clone)" }
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot ".git/MERGE_HEAD")) { throw "Есть незавершенное слияние. Откройте папку в GitHub Desktop или выполните: git merge --abort" }

    # 1. Собрать свои изменения + защита: пароли и полные копии не уходят
    & git add -A
    $staged = @(& git diff --cached --name-only)
    $bad = @()
    foreach ($f in $staged) {
        if ($f -like "data/backup/*") { $bad += $f; continue }
        if ($f -like "*.json" -and (Test-Path -LiteralPath $f)) {
            if (Select-String -LiteralPath $f -Pattern '"pw"\s*:' -Quiet) { $bad += $f }
        }
    }
    if ($bad.Count) { & git reset -q; throw "ОСТАНОВЛЕНО: файлы с паролями/полной копией: $($bad -join ', '). Проверьте .gitignore" }

    # 2. Commit своих изменений
    if ($staged.Count) {
        if (-not $Message) {
            $Message = "Обновление CRM {0:dd.MM.yyyy HH:mm} ({1})" -f (Get-Date), $env:COMPUTERNAME
            $meta = Join-Path $PSScriptRoot "data/latest/meta.json"
            if ((Test-Path -LiteralPath $meta) -and ($staged -like "data/*")) {
                try { $m = Get-Content -LiteralPath $meta -Raw -Encoding UTF8 | ConvertFrom-Json; $Message += " · данные: $($m.by), $($m.node)" } catch {}
            }
        }
        if ((RunGit commit -q -m $Message) -ne 0) { throw "git commit не прошел" }
        Log "Сохранено локально: файлов — $($staged.Count)"
    }

    # 3. Получить изменения из GitHub (с других компьютеров / новую версию кода)
    if ((RunGit fetch origin) -ne 0) { throw "Нет связи с GitHub (git fetch). Изменения сохранены локально и уйдут при следующем запуске" }
    $behind = [int](& git rev-list --count "HEAD..origin/main")
    if ($behind -gt 0) {
        & git merge --no-edit origin/main *> $null
        if ($LASTEXITCODE) {
            $conf = @(& git diff --name-only --diff-filter=U)
            $code = @($conf | Where-Object { $_ -notlike "data/latest/*" -and $_ -notlike "data/history/*" -and $_ -notlike "data/meta/*" -and $_ -notlike "data/nodes/*" })
            if ($code.Count) {
                & git merge --abort
                throw "Конфликт в коде: $($code -join ', '). Нужен ручной разбор (GitHub Desktop). Данные не пострадали"
            }
            foreach ($f in $conf) { & git checkout --ours -- $f; & git add -- $f }
            if ((RunGit commit -q --no-edit) -ne 0) { throw "Не удалось завершить слияние" }
            Log "Конфликт в общих выгрузках решен автоматически: $($conf.Count) файл(ов)"
        }
        Log "Получено из GitHub коммитов: $behind"
    }

    # 4. Отправить
    $ahead = [int](& git rev-list --count "origin/main..HEAD")
    if ($ahead -gt 0) {
        if ((RunGit push origin main) -ne 0) { throw "git push не прошел (нет сети или нет доступа). Повторится при следующем запуске" }
        Log "OK: отправлено в GitHub коммитов — $ahead"
    }
    elseif ($behind -eq 0) { Log "Изменений нет" }
    exit 0
}
catch {
    Log "ОШИБКА: $_"
    exit 1
}
