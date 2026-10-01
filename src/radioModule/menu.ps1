# Меню работы с модулями управления (ESPtool)

function Show-RadioModuleMenu {
    Show-Header
    
    Show-Message -Message @"
    На данный момент функционал работы с модулями управления (ESPtool) находится в разработке.

    0. Вернуться в главное меню
"@ -Color "White"

    Show-Input "`n> Выбери действие [0]: "
    $choice = [Console]::ReadLine()

    switch ($choice) {
        "0" { return }
        default {
            Show-Message -Message "Такого пункта не предусмотрено." -Color "Yellow"
            Show-Exit
        }
    }
}
