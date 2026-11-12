# ------------------------------------------------------------------
#  DSRC CRM — автоматическая отправка в GitHub по расписанию
#  Создает задачу Планировщика Windows, которая каждые N минут
#  запускает sync.ps1 (скрыто). Работает, пока вы вошли в Windows.
#
#  Включить (каждые 30 минут):
#   powershell -ExecutionPolicy Bypass -File setup-schedule.ps1
#  Другой интервал:
#   powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -EveryMinutes 60
#  Выключить:
#   powershell -ExecutionPolicy Bypass -File setup-schedule.ps1 -Remove
# ------------------------------------------------------------------
param([int]$EveryMinutes = 30, [switch]$Remove)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$TaskName = "DSRC CRM - sync GitHub"

if ($Remove) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Задача «$TaskName» удалена." -ForegroundColor Yellow
    exit 0
}

$script = Join-Path $PSScriptRoot "sync.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`"" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $EveryMinutes)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Отправляет изменения папки $PSScriptRoot в GitHub (sync.ps1). Журнал: sync.log" -Force | Out-Null

Write-Host "Готово: каждые $EveryMinutes мин. изменения из папки отправляются в GitHub." -ForegroundColor Green
Write-Host "Журнал: $(Join-Path $PSScriptRoot 'sync.log')"
