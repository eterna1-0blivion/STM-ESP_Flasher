# author: eterna1_0blivion
$version = 'v0.0.1'

# Некоторые пред-установки
$theme = '$Host.UI.RawUI.BackgroundColor = "Black"; $Host.UI.RawUI.ForegroundColor = "Gray"; Clear-Host'
$exit = 'Read-Host -Prompt "Press Enter to exit"; Break'

# Устанавливаем заголовок консоли, меняем тему и выводим первую строку
$Host.UI.RawUI.WindowTitle = "STM32 Mini-Flasher ($version)"
Invoke-Expression $theme

# Корректное определение папки запуска для EXE и для обычного скрипта PS
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    $ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$CurrentDir = $ScriptDir


#TODO: добавить статус обнаруженнвх подключений (COM и DFU устройств)
#TODO: дать возможность перевести подключенный полётник в режим DFU или вывести его из этого режима - инициировать переподключение
#TODO: добавить выход из программы при пустом вводе (enter)

function Show-Message {
    param (
            [string]$Message,
            [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta",
            "DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
            [string]$Color

        )
        [Console]::ForegroundColor = [ConsoleColor]::$Color
        [Console]::WriteLine("$Message")
}

function Show-Input {
        param (
            [string]$Message
        )
        [Console]::Write("$Message")
}

function Show-Header {
    Clear-Host
    Show-Message -Message "=== Работа с прошивкой Полётного Контроллера ===" -Color "Cyan"
}

function Show-Menu {
    Show-Header
    Show-Message -Message "
    1. Считать прошивку с FC (Сохранить в fw.bin)
    2. Записать прошивку на FC (Из файла fw.bin)
    3. Полностью стереть прошивку на FC
    4. Выход из программы
    " -Color "White"

    Show-Input "`n> Выберите действие [1-4]: "
}

function Show-Wait {
    Show-Header
    Show-Message -Message "`nПрограмма выполняется..." -Color "Gray"
}

function Show-Exit {
    Show-Message -Message "`n> Нажми любую клавишу для возврата в меню..." -Color "White"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

while ($true) {
    Show-Menu
    $choice = [Console]::ReadLine()

    switch ($choice) {
        # Read FW
        "1" {
            Show-Wait
            $TargetFile = Join-Path $ScriptDir "fw.bin"
            if (Test-Path $TargetFile) { Remove-Item $TargetFile -Force -ErrorAction SilentlyContinue }
            
            # Попытка чтения 512КБ, затем 1МБ
            & "$CurrentDir\bin\stm32pr.exe" -c port=usb1 -r 0x08000000 0x80000 "$TargetFile" | Out-Null
            & "$CurrentDir\bin\stm32pr.exe" -c port=usb1 -r 0x08000000 0x100000 "$TargetFile" | Out-Null

            if (Test-Path $TargetFile) {
                Show-Message -Message "`nОперация выполнена - прошивка 'fw.bin' находится в папке программы." -Color "Green"                
            } else {
                Show-Message -Message "`nПрошивка НЕ сохранена. Возможно, полётник не в режиме DFU." -Color "Yellow"
            }
            Show-Exit
        }
        # Write FW
        "2" {
            Show-Wait
            $SourceFile = Join-Path $ScriptDir "fw.bin"

            if (-not (Test-Path $SourceFile)) {
                Show-Message -Message "`nПрошивка НЕ записана. Файл 'fw.bin' не найден в папке с программой." -Color "Yellow"
            } else {
                & "$CurrentDir\bin\stm32pr.exe" -c port=usb1 -w "$SourceFile" 0x08000000 -v | Out-Null
                
                if ($LastExitCode -eq 0) {
                    Show-Message -Message "`nОперация выполнена - прошивка 'fw.bin' записана на полётник." -Color "Green"
                } else {
                    Show-Message -Message "`nПрошивка НЕ записана. Возможно, полётник не в режиме DFU." -Color "Yellow"
                }
            }
            Show-Exit
        }
        # Erase FW
        "3" {
            Show-Wait

            & "$CurrentDir\bin\stm32pr.exe" -c port=usb1 -e all | Out-Null
            
            if ($LastExitCode -eq 0) {
                Show-Message -Message "`nОперация выполнена - прошивка на полётнике стёрта." -Color "Green"
            } else {
                Show-Message -Message "`nПрошивка НЕ стёрта. Возможно, полётник не в режиме DFU." -Color "Yellow"
            }
            Show-Exit
        }
        # Exit Flasher
        "4" {
            exit
        }
    }
}
