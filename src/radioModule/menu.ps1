# Верхнее меню модуля управления делит операции по типу устройства.

function Show-RadioModuleMenu {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    while ($true) {
        Show-RadioModuleHeader
        Show-Separator
        Show-Message -Message @"
    1. Приёмники (RX)
    2. Передатчики (TX)

    0. Вернуться в главное меню
"@ -Color "White"

        $choice = Show-Message -Message "Выбери раздел [0-2]: " -Input Choice -NewLine
        if ($null -eq $choice) {
            return
        }

        switch ($choice) {
            "0" { return }
            "1" { Show-RxModuleMenu -Config $Config }
            "2" { Show-TxModuleMenu -Config $Config }
            default { Show-WrongInput -Menu "RadioModule" }
        }
    }
}

function Show-RxModuleMenu {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    while ($true) {
        Show-RadioModuleHeader
        Show-Message -Message "Приёмники (RX)" -Level "Status" -NewLine
        Show-Separator
        Show-Message -Message @"
    ROI — прямая прошивка esptool (только для дронов ROI):
    1. Записать цельный образ RX
    2. Записать RX-прошивку (стандартные файлы + выбранный BIN)
    3. Прочитать резервную копию RX (4 МиБ)

    Другие совместимые дроны:
    4. Прошить ESP32 RX через полётный контроллер (FC Passthrough)

    0. Назад
"@ -Color "White"

        $choice = Show-Message -Message "Выбери действие [0-4]: " -Input Choice -NewLine
        if ($null -eq $choice) {
            return
        }

        switch ($choice) {
            "0" { return }
            "1" { Invoke-RxFullImageWrite -Config $Config }
            "2" { Invoke-RxSegmentedFirmwareWrite -Config $Config }
            "3" { Invoke-RxFlashRead -Config $Config }
            "4" { Invoke-FcPassthroughRxFirmwareWrite -Config $Config }
            default { Show-WrongInput -Menu "RadioModule" }
        }
    }
}

function Show-TxModuleMenu {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    while ($true) {
        Show-RadioModuleHeader
        Show-Message -Message "Передатчики (TX)" -Level "Status" -NewLine
        Show-Separator
        Show-Message -Message @"
    1. Записать прошивку TX (ESP32)
    2. Прочитать резервную копию TX (4 МиБ)

    0. Назад
"@ -Color "White"

        $choice = Show-Message -Message "Выбери действие [0-2]: " -Input Choice -NewLine
        if ($null -eq $choice) {
            return
        }

        switch ($choice) {
            "1" { Invoke-TxFirmwareWrite -Config $Config }
            "2" { Invoke-TxFlashRead -Config $Config }
            "0" { return }
            default { Show-WrongInput -Menu "RadioModule" }
        }
    }
}
