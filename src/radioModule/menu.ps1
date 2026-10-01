# Меню работы с модулями управления (ESPtool)

function Show-RadioModuleMenu {
    while ($true) {
        Show-RadioModuleHeader
        Show-Separator
    
        Show-Message -Message @"
    На данный момент функционал работы с модулем управления (ESPtool) находится в разработке.

    0. Вернуться в главное меню
"@ -Color "White"

        Show-Input "`n> Выбери действие [0]: "
        $choice = [Console]::ReadLine()
        if ($null -eq $choice) {
            return
        }

        switch ($choice) {
            "0" { return }
            default { Show-WrongInput -Menu "RadioModule" }
        }
    }
}
