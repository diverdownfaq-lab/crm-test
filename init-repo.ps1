# ------------------------------------------------------------------
#  DSRC CRM — первичная настройка репозитория (запускается ОДИН раз)
#  Пример:
#   powershell -ExecutionPolicy Bypass -File init-repo.ps1 -RepoUrl https://github.com/<логин>/dsrc-crm.git
#  Перед запуском создайте на github.com ПУСТОЙ приватный репозиторий
#  (без README, без .gitignore), скопируйте его адрес.
# ------------------------------------------------------------------
param([Parameter(Mandatory = $true)][string]$RepoUrl)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Set-Location -LiteralPath $PSScriptRoot

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Git не установлен: https://git-scm.com/download/win" -ForegroundColor Red; exit 1 }

# имя и почта для подписи коммитов (один раз на компьютер)
if (-not (& git config --global user.name)) {
    $n = Read-Host "Ваше имя для коммитов (например, Aruzhan B.)"
    & git config --global user.name $n
}
if (-not (& git config --global user.email)) {
    $e = Read-Host "Почта, которая указана в GitHub"
    & git config --global user.email $e
}

# проверка GitHub Actions: шаблон лежит в setup\check.yml, копируем на штатное место
$wf = Join-Path $PSScriptRoot ".github\workflows"
if (-not (Test-Path -LiteralPath (Join-Path $wf "check.yml"))) {
    New-Item -ItemType Directory -Force -Path $wf | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "setup\check.yml") -Destination (Join-Path $wf "check.yml")
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot ".git"))) {
    & git init -b main
}
& git add -A
& git commit -m "Первая версия DSRC CRM (тестовый этап: только код)"
if (& git remote) { & git remote set-url origin $RepoUrl } else { & git remote add origin $RepoUrl }

Write-Host "Отправка в GitHub. Если откроется окно входа — войдите в свой аккаунт GitHub в браузере." -ForegroundColor Cyan
& git push -u origin main
if ($LASTEXITCODE) { Write-Host "Не удалось отправить. Проверьте адрес репозитория и вход в GitHub." -ForegroundColor Red; exit 1 }
Write-Host "Готово. Дальше для отправки изменений используйте sync.bat" -ForegroundColor Green
