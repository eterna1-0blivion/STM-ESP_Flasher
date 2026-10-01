# author: eterna1_0blivion
$version = 'v0.1.1'

# *Способы компиляции в .exe*: Подумать над альтернативами взамен долгого запуска через SFX.
# *Раздел ESPtool*: Реализовать связку с ESPtool для работы с модулями управления.
# *Раздел цифрового видеопередатчика*: Разработать модуль поддержки Caddx/Walksnail.

# Принудительно заставляем любую версию PowerShell работать в UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Подгружаем сборку графических диалогов WPF для совместимости с PowerShell 5.0
Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

# Устанавливаем заголовок консоли, меняем задний фон
$Host.UI.RawUI.WindowTitle = "FPV-Flasher ($version)"
$Host.UI.RawUI.BackgroundColor = "Black"
Clear-Host

# Корректное определение папки запуска для EXE и для обычного скрипта PS
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
else {
    $scriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

# Путь до STM32 CLI
$stm32Tool = Join-Path $scriptDir "files\STM32CubeCLT\bin\STM32_Programmer_CLI.exe"
$driverTool = Join-Path $scriptDir "files\ImpulseRC_Driver_Fixer.exe"

. (Join-Path $scriptDir "src\common\ui.ps1")
. (Join-Path $scriptDir "src\flightController\devices.ps1")
. (Join-Path $scriptDir "src\flightController\firmware.ps1")
. (Join-Path $scriptDir "src\flightController\menu.ps1")
. (Join-Path $scriptDir "src\radioModule\menu.ps1")

function Show-MainMenu {
    Show-MainHeader
    Show-Separator
    Show-Message -Message @"
    1. Работа с полётным контроллером (STM32)
    2. Работа с модулем управления (ESPtool)

    0. Выход из программы
"@ -Color "White"

    Show-Input "`n> Введи команду [0-2]: "
}

while ($true) {
    Show-MainMenu
    $choice = [Console]::ReadLine()

    switch ($choice) {
        "1" { Show-FlightControllerMenu }
        "2" { Show-RadioModuleMenu }
        "0" { exit }
        default { Show-WrongInput -Menu "Main" }
    }
}
