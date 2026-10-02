# author: eterna1_0blivion
$version = 'v0.1.10'

# Планируемые направления: поддержка ESPtool и цифровых видеопередатчиков.

# Принудительно заставляем любую версию PowerShell работать в UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Подгружаем сборку графических диалогов WPF для совместимости с PowerShell 5.0
Add-Type -AssemblyName PresentationFramework

# Устанавливаем заголовок консоли, меняем задний фон
$Host.UI.RawUI.WindowTitle = "FPV-Flasher ($version)"
$Host.UI.RawUI.BackgroundColor = "Black"
Clear-Host

# Все пути ресурсов вычисляются от каталога приложения, независимо от текущего каталога PowerShell.
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
else {
    $scriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

# Передаём зависимости явно в рабочие функции, а не полагаемся на переменные из области видимости скрипта.
$appConfig = [pscustomobject]@{
    RootDirectory       = $scriptDir
    STM32ProgrammerPath = Join-Path $scriptDir "files\STM32CubeCLT\bin\STM32_Programmer_CLI.exe"
    DriverFixerPath      = Join-Path $scriptDir "files\ImpulseRC_Driver_Fixer.exe"
}

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

    Show-Message -Message "Выбери действие [0-2]: " -Input Choice -NewLine
}

while ($true) {
    $choice = Show-MainMenu
    if ($null -eq $choice) {
        return
    }

    switch ($choice) {
        "1" { Show-FlightControllerMenu -Config $appConfig }
        "2" { Show-RadioModuleMenu }
        "0" { return }
        default { Show-WrongInput -Menu "Main" }
    }
}
