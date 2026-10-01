# Основное меню и функции для работы с прошивкой полётного контроллера

function Show-FlightControllerMenu {
    while ($true) {
        Show-FlightControllerHeader
        Get-DeviceStatus

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

        switch ($choice) {
            "1" { Get-FlightControllerRead }
            "2" { Get-FlightControllerWrite }
            "3" { Get-FlightControllerErase }
            "4" { Get-FlightControllerDFU }
            "5" { Get-FlightControllerImpulseRC }
            "0" { return }
            default { Show-WrongInput }
        }
    }
}
