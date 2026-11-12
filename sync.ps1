# ------------------------------------------------------------------
#  DSRC CRM — отправка изменений в GitHub
#  Запуск вручную: двойной клик по sync.bat
#  Автоматически:  задача Планировщика (см. setup-schedule.ps1)
#  Что делает: забирает изменения коллег (pull) -> проверяет, что нет
#  паролей -> commit -> push. Журнал пишется в sync.log рядом.
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
    if ($LASTEXITCODE) { throw "Папка не является git-репозиторием. Сначала запустите init-repo.ps1" }

    # 1. Забрать изменения коллег (если они правили код в GitHub)
    if ((RunGit pull --rebase --autostash) -ne 0) {
        throw "git pull не прошел (конфликт или нет сети). Откройте папку в GitHub Desktop и разберите вручную"
    }

    # 2. Собрать изменения (с учетом .gitignore)
    & git add -A
    $staged = @(& git diff --cached --name-only)
    if ($staged.Count -eq 0) { Log "Изменений нет — отправлять нечего"; exit 0 }

    # 3. Защита: пароли и полные копии в GitHub не уходят
    $bad = @()
    foreach ($f in $staged) {
        if ($f -like "data/backup/*") { $bad += $f; continue }
        if ($f -like "*.json" -and (Test-Path -LiteralPath $f)) {
            if (Select-String -LiteralPath $f -Pattern '"pw"\s*:' -Quiet) { $bad += $f }
        }
    }
    if ($bad.Count) {
        & git reset -q
        throw "ОСТАНОВЛЕНО: в коммит попали файлы с паролями/полной копией: $($bad -join ', '). Проверьте .gitignore"
    }

    # 4. Commit + push
    if (-not $Message) {
        $Message = "Обновление CRM {0:dd.MM.yyyy HH:mm} ({1})" -f (Get-Date), $env:USERNAME
        $meta = Join-Path $PSScriptRoot "data/latest/meta.json"
        if ((Test-Path -LiteralPath $meta) -and ($staged -like "data/*")) {
            try { $m = Get-Content -LiteralPath $meta -Raw -Encoding UTF8 | ConvertFrom-Json; $Message += " · данные от $($m.exportedAt), выгрузил $($m.by)" } catch {}
        }
    }
    if ((RunGit commit -q -m $Message) -ne 0) { throw "git commit не прошел" }
    if ((RunGit push) -ne 0) { throw "git push не прошел (нет сети или нет доступа к репозиторию)" }
    Log "OK: отправлено файлов — $($staged.Count). $Message"
    exit 0
}
catch {
    Log "ОШИБКА: $_"
    exit 1
}
