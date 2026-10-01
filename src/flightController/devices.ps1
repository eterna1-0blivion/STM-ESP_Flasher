# Функция опроса оборудования для поиска подключенного полётного контроллера (STM32) и отображения его статуса

function Get-DeviceStatus {
    # Сначала говорим пользователю, что программа думает
    Show-Message -Message "Поиск подключенного оборудования..." -Color "Gray"
    
    $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue
    
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
