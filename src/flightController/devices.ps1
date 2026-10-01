# Функция опроса оборудования для поиска подключенного полётного контроллера (STM32) и отображения его статуса

function Show-DeviceStatus {
    Show-Message -Message "`nПоиск подключенного оборудования..." -Color "Gray"

    try {
        $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
    }
    catch {
        Show-Message -Message "[ОШИБКА] Не удалось проверить подключённые устройства." -Color "Red"
        Show-Message -Message $_.Exception.Message -Color "DarkRed"
        return
    }
    
    # Фильтруем строго по вхождению "(COM" с открывающей скобкой, чтобы отсечь сторонние компоненты
    $comDevices = $allDevices | Where-Object { $_.Present -and ($_.Name -like "*STMicroelectronics*" -or $_.Name -like "*(COM*") }
    $dfuDevices = $allDevices | Where-Object { $_.Present -and ($_.Name -like "*DFU*" -or $_.DeviceID -like "*VID_0483&PID_DF11*") }

    Show-FlightControllerHeader
    Show-Separator
    if ($comDevices) {
        foreach ($dev in $comDevices) {
            Show-Message -Message "[СТАТУС] Обнаружен полётник в обычном режиме: $($dev.Name)" -Color "Cyan"
        }
    }
    if ($dfuDevices) {
        foreach ($dev in $dfuDevices) {
            Show-Message -Message "[СТАТУС] Обнаружен полётник в режиме прошивки: $($dev.Name) (DFU)" -Color "Green"
        }
    }
    if (-not $comDevices -and -not $dfuDevices) {
        Show-Message -Message "[СТАТУС] Полётный контроллер не обнаружен." -Color "DarkYellow"
    }
    Show-Separator
}
