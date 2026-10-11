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

function Get-UserFilePath {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config,
        [Parameter(Mandatory)]
        [ValidateSet("Open", "Save")]
        [string]$Mode,
        [Parameter(Mandatory)]
        [ValidateSet("bin", "hex")]
        [string[]]$Extensions,
        [Parameter(Mandatory)]
        [string]$Purpose,
        [string]$DefaultFileName
    )

    $normalizedExtensions = @($Extensions | ForEach-Object { $_.TrimStart(".").ToLowerInvariant() } | Select-Object -Unique)
    $extensionPattern = ($normalizedExtensions | ForEach-Object { "*.$_" }) -join ";"
    if ($normalizedExtensions -contains "bin" -and $normalizedExtensions -contains "hex") {
        $filter = "Файлы прошивок ($extensionPattern)|$extensionPattern|Сырой дамп памяти (*.bin)|*.bin|Intel HEX формат (*.hex)|*.hex|Все файлы (*.*)|*.*"
    }
    else {
        $filter = "Образ прошивки ($extensionPattern)|$extensionPattern|Все файлы (*.*)|*.*"
    }

    if ($Mode -eq "Save") {
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Title = "Выберите, куда сохранить: $Purpose"
        $dialog.Filter = $filter
        $dialog.FileName = if ($DefaultFileName) { $DefaultFileName } else { "firmware.$($normalizedExtensions[0])" }
        $dialog.AddExtension = $true
        $dialog.ValidateNames = $true
        $dialog.DefaultExt = ".$($normalizedExtensions[0])"
    }
    else {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "Выберите файл: $Purpose"
        $dialog.Filter = $filter
        $dialog.CheckFileExists = $true
    }

    $dialog.InitialDirectory = $Config.RootDirectory
    if ($dialog.ShowDialog() -eq $true) {
        return $dialog.FileName
    }

    return $null
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
