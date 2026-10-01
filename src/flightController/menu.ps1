# Основное меню и функции для работы с прошивкой полётного контроллера

function Show-FlightControllerMenu {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    while ($true) {
        Show-FlightControllerHeader
        Show-DeviceStatus

        Show-Message -Message @"
    1. ПРОЧИТАТЬ прошивку с полётного контроллера (Выбрать куда сохранить)
    2. ЗАПИСАТЬ прошивку на полётный контроллер (Выбрать файл на диске)
    3. СТЕРЕТЬ прошивку на полётном контроллере (Полная очистка памяти)
    4. Управление режимом DFU (Вход / Выход)
    5. Помощник исправления драйверов (ImpulseRC)

    0. Вернуться в главное меню
"@ -Color "White"

        Show-Input "`n> Выбери действие [0-5]: "
        $choice = [Console]::ReadLine()
        if ($null -eq $choice) {
            return
        }

        switch ($choice) {
            "1" { Invoke-FlightControllerFirmwareRead -Config $Config }
            "2" { Invoke-FlightControllerFirmwareWrite -Config $Config }
            "3" { Invoke-FlightControllerFirmwareErase -Config $Config }
            "4" { Invoke-FlightControllerDFU -Config $Config }
            "5" { Invoke-ImpulseRCDriverFixer -Config $Config }
            "0" { return }
            default { Show-WrongInput -Menu "FlightController" }
        }
    }
}
