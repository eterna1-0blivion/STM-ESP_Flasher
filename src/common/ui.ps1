# Основные функции для работы с консолью и пользовательским интерфейсом

# Вывод сообщений в консоль
function Show-Message {
    param (
        [string]$Message,
        [ValidateSet("None", "Success", "Status", "Error", "Cancelled", "Info", "Warning", "Diagnostic")]
        [string]$Level = "None",
        [switch]$NewLine,
        [Alias("Input")]
        [ValidateSet("Choice", "Enter")]
        [string]$InputMode,
        [ValidateSet("Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta",
            "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan", "Red", "Magenta", "Yellow", "White")]
        [string]$Color = "White"
    )

    if ($Level -ne "None") {
        # Text labels remain meaningful even in hosts that render console colors poorly.
        $labels = @{
            Success    = "[УСПЕХ]"
            Status     = "[СТАТУС]"
            Error      = "[ОШИБКА]"
            Cancelled  = "[ОТМЕНА]"
            Info       = "[ИНФО]"
            Warning    = "[ВНИМАНИЕ]"
            Diagnostic = "[ДИАГНОСТИКА]"
        }
        $levelColors = @{
            Success    = "Green"
            Status     = "Blue"
            Error      = "Red"
            Cancelled  = "Yellow"
            Info       = "Gray"
            Warning    = "DarkYellow"
            Diagnostic = "DarkGray"
        }

        $Message = "$($labels[$Level]) $($Message.TrimStart())"
        if (-not $PSBoundParameters.ContainsKey("Color")) {
            $Color = $levelColors[$Level]
        }
    }

    [Console]::ForegroundColor = [ConsoleColor]::$Color

    if ($PSBoundParameters.ContainsKey("InputMode")) {
        if ($NewLine) {
            [Console]::WriteLine()
        }

        [Console]::Write("> $Message")
        [Console]::Out.Flush()

        if ($InputMode -eq "Enter") {
            do {
                $key = Read-InputKey
            } until ($key.Character -eq "`r" -or $key.VirtualKeyCode -eq 13)

            return
        }

        return [Console]::ReadLine()
    }

    if ($NewLine) {
        $Message = [Environment]::NewLine + $Message
    }

    [Console]::WriteLine($Message)
}

function Read-InputKey {
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-FlightControllerWait {
    Show-FlightControllerHeader
    Show-Message -Message "Программа выполняется..." -Level "Info" -NewLine
}

function Show-Exit {
    Show-Message -Message "Нажми Enter для возврата в меню..." -Level "None" -Input Enter -NewLine
}

function Show-WrongInput {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Main", "FlightController", "RadioModule")]
        [string]$Menu
    )

    switch ($Menu) {
        "Main" { Show-MainHeader }
        "FlightController" { Show-FlightControllerHeader }
        "RadioModule" { Show-RadioModuleHeader }
    }

    Show-Message -Message "Такого пункта не предусмотрено." -Level "Warning" -NewLine
    Show-Exit
}

function Show-MainHeader {
    Clear-Host
    Show-Message -Message @"
==========   Меню FPV-Flasher   ==========
"@ -Color "Cyan"
}

function Show-FlightControllerHeader {
    Clear-Host
    Show-Message -Message @"
==========   Работа с полётным контроллером   ==========
"@ -Color "Cyan"
}

function Show-RadioModuleHeader {
    Clear-Host
    Show-Message -Message @"
==========   Работа с модулем управления   ==========
"@ -Color "Cyan"
}

function Show-Separator {
    Show-Message -Message @"
------------------------------------------------------------
"@ -Color "DarkGray"
}
