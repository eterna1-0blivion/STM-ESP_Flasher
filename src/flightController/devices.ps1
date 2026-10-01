# STM32CubeCLT содержит базу идентификаторов микроконтроллеров, а не список плат и их USB VID/PID.
# Поэтому только стандартный USB DFU-идентификатор STM32 подтверждает режим прошивки;
# найденный COM-порт показывается как кандидат, но не объявляется полётным контроллером.

function Show-DeviceStatus {
    Show-Message -Message "Поиск подключённого оборудования..." -Level "Info" -NewLine

    try {
        $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
    }
    catch {
        Show-Message -Message "Не удалось проверить подключённые устройства." -Level "Error"
        Show-Message -Message $_.Exception.Message -Level "Diagnostic"
        return
    }
    $comDevices = @(
        $allDevices | Where-Object {
            $_.Present -and $_.Name -match '\(COM\d+\)'
        }
    )
    $dfuDevices = @(Get-Stm32DfuDevices -Devices $allDevices)

    Show-FlightControllerHeader
    Show-Separator
    if ($dfuDevices.Count -gt 0) {
        foreach ($dev in $dfuDevices) {
            Show-Message -Message "Полётный контроллер обнаружен в режиме прошивки: $($dev.Name)" -Level "Status"
        }
    }

    if ($comDevices.Count -gt 0) {
        foreach ($dev in $comDevices) {
            Show-Message -Message "Возможный полётный контроллер: $($dev.Name)" -Level "Status"
        }
    }

    if ($comDevices.Count -eq 0 -and $dfuDevices.Count -eq 0) {
        Show-Message -Message "Полётный контроллер не обнаружен." -Level "Status"
    }
    Show-Separator
}

function Get-Stm32DfuDevices {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Devices
    )

    @(
        $Devices | Where-Object {
            $_.Present -and $_.DeviceID -match 'VID_0483&PID_DF11'
        }
    )
}

function Get-ConnectedStm32DfuDevices {
    $devices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
    @(Get-Stm32DfuDevices -Devices @($devices))
}
