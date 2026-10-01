# Операции с STM32 CLI. Все внешние команды проходят через Invoke-Stm32Command,
# чтобы единообразно сохранить код возврата и текст диагностики утилиты.

function Get-SaveFilePath {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.InitialDirectory = $Config.RootDirectory
    $dialog.Title = "Выбери, куда сохранить прочитанную прошивку с полётного контроллера"
    $dialog.Filter = "Сырой дамп памяти (*.bin)|*.bin|Intel HEX формат (*.hex)|*.hex"
    $dialog.FileName = "fw.bin"
    $dialog.ValidateNames = $true
    if ($dialog.ShowDialog() -eq $true) { return $dialog.FileName }
    return $null
}

function Get-OpenFilePath {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.InitialDirectory = $Config.RootDirectory
    $dialog.Title = "Выбери файл прошивки для записи на полётный контроллер"
    $dialog.Filter = "Файлы прошивок (*.bin;*.hex)|*.bin;*.hex|Сырой дамп памяти (*.bin)|*.bin|Intel HEX формат (*.hex)|*.hex"
    if ($dialog.ShowDialog() -eq $true) { return $dialog.FileName }
    return $null
}

function Invoke-Stm32Command {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $toolPath = $Config.STM32ProgrammerPath
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        return [pscustomobject]@{
            Succeeded = $false
            ExitCode  = $null
            Output    = @()
            Error     = "STM32 CLI не найден: $toolPath"
        }
    }

    try {
        $output = @(& $toolPath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE

        return [pscustomobject]@{
            Succeeded = ($exitCode -eq 0)
            ExitCode  = $exitCode
            Output    = $output
            Error     = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Succeeded = $false
            ExitCode  = $null
            Output    = @()
            Error     = $_.Exception.Message
        }
    }
}

function Show-Stm32CommandFailure {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Result
    )

    if ($null -ne $Result.ExitCode) {
        Show-Message -Message "Код завершения STM32 CLI: $($Result.ExitCode)." -Color "Red"
    }
    if ($Result.Error) {
        Show-Message -Message $Result.Error -Color "DarkRed"
    }
    foreach ($line in $Result.Output) {
        Show-Message -Message $line -Color "DarkRed"
    }
}

function Invoke-FlightControllerFirmwareRead {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $saveFile = Get-SaveFilePath -Config $Config
    if ($null -eq $saveFile) {
        Show-FlightControllerHeader
        Show-Message -Message "`nОперация отменена пользователем." -Color "Yellow"
        Show-Exit
        return
    }

    Show-FlightControllerWait
    try {
        if (Test-Path -LiteralPath $saveFile) {
            Remove-Item -LiteralPath $saveFile -Force -ErrorAction Stop
        }
    }
    catch {
        Show-Message -Message "`nНе удалось подготовить файл для чтения прошивки." -Color "Red"
        Show-Message -Message $_.Exception.Message -Color "DarkRed"
        Show-Exit
        return
    }

    $result = Invoke-Stm32Command -Config $Config -Arguments @(
        "-c", "port=usb1", "-r", "0x08000000", "0x100000", $saveFile
    )
    if (-not $result.Succeeded) {
        Show-Message -Message "`nНе удалось прочитать прошивку. Диагностика STM32 CLI:" -Color "Red"
        Show-Stm32CommandFailure -Result $result
        if (Test-Path -LiteralPath $saveFile) {
            try {
                Remove-Item -LiteralPath $saveFile -Force -ErrorAction Stop
            }
            catch {
                Show-Message -Message "Не удалось удалить неполный файл прошивки: $($_.Exception.Message)" -Color "DarkRed"
            }
        }
        Show-Exit
        return
    }

    if (Test-Path -LiteralPath $saveFile) {
        $fileSize = (Get-Item -LiteralPath $saveFile).Length
        if ($fileSize -gt 0) {
            Show-Message -Message "`nОперация выполнена - прошивка сохранена в:`n$saveFile" -Color "Green"                
        }
        else {
            Show-Message -Message "`nОшибка! Скачанный файл оказался пустым (0 КБ). Прошивка не сохранена." -Color "Red"
            try {
                Remove-Item -LiteralPath $saveFile -Force -ErrorAction Stop
            }
            catch {
                Show-Message -Message "Не удалось удалить пустой файл: $($_.Exception.Message)" -Color "DarkRed"
            }
        }
    }
    else {
        Show-Message -Message "`nSTM32 CLI не сообщил об ошибке, но файл прошивки не был создан." -Color "Red"
        foreach ($line in $result.Output) {
            Show-Message -Message $line -Color "DarkRed"
        }
    }
    Show-Exit
}

function Invoke-FlightControllerFirmwareWrite {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $selectedFile = Get-OpenFilePath -Config $Config
    if ($null -eq $selectedFile) {
        Show-FlightControllerHeader
        Show-Message -Message "`nОперация отменена пользователем." -Color "Yellow"
        Show-Exit
        return
    }

    Show-FlightControllerWait
    Show-Message -Message "Запись файла: $(Split-Path $selectedFile -Leaf)" -Color "Gray"
    $extension = [System.IO.Path]::GetExtension($selectedFile).ToLower()

    if ($extension -eq ".hex") {
        $arguments = @("-c", "port=usb1", "-w", $selectedFile, "-v")
    }
    else {
        $arguments = @("-c", "port=usb1", "-w", $selectedFile, "0x08000000", "-v")
    }

    $result = Invoke-Stm32Command -Config $Config -Arguments $arguments
    if ($result.Succeeded) {
        Show-Message -Message "`nОперация выполнена - прошивка записана на полётник." -Color "Green"
    }
    else {
        Show-Message -Message "`nПрошивка НЕ записана." -Color "Red"
        Show-Stm32CommandFailure -Result $result
    }
    Show-Exit
}

function Invoke-FlightControllerFirmwareErase {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    Show-FlightControllerWait
    $result = Invoke-Stm32Command -Config $Config -Arguments @("-c", "port=usb1", "-e", "all")
            
    if ($result.Succeeded) {
        Show-Message -Message "`nОперация выполнена - прошивка на полётнике стёрта." -Color "Green"
    }
    else {
        Show-Message -Message "`nПрошивка НЕ стёрта." -Color "Red"
        Show-Stm32CommandFailure -Result $result
    }
    Show-Exit
}

function Invoke-FlightControllerDFU {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    Show-FlightControllerHeader
    Show-Message -Message "
    Управление состоянием контроллера:

    1. Попробовать перевести полётный контроллер в режим DFU
    2. Выйти из режима DFU и перезагрузить плату
    
    0. Назад
            " -Color "White"
    Show-Input "> Выбери действие [0-2]: "
    $dfuChoice = [Console]::ReadLine()

    if ($null -eq $dfuChoice -or $dfuChoice -eq "0") {
        return
    }

    if ($dfuChoice -eq "1") {
        Show-FlightControllerWait
        $result = Invoke-Stm32Command -Config $Config -Arguments @("-c", "port=usb1", "-s")
    }
    elseif ($dfuChoice -eq "2") {
        Show-FlightControllerWait
        $result = Invoke-Stm32Command -Config $Config -Arguments @("-c", "port=usb1", "-g", "0x08000000")
    }
    else {
        Show-WrongInput -Menu "FlightController"
        return
    }

    if ($result.Succeeded) {
        if ($dfuChoice -eq "1") {
            Show-Message -Message "`nКоманда отправлена. Если плата поддерживает программный DFU, она переподключится." -Color "Green"
        }
        else {
            Show-Message -Message "`nКоманда выхода отправлена. Плата перезагружается в рабочий режим." -Color "Green"
        }
    }
    else {
        Show-Message -Message "`nНе удалось выполнить команду управления DFU." -Color "Red"
        Show-Stm32CommandFailure -Result $result
    }
    Show-Exit
}

function Get-ImpulseRCOutcome {
    param (
        [Parameter(Mandatory)]
        [int]$ExitCode,
        [Parameter(Mandatory)]
        [bool]$DfuBefore,
        [Parameter(Mandatory)]
        [bool]$DfuAfter
    )

    if ($ExitCode -ne 0) {
        return [pscustomobject]@{
            Status  = "Error"
            Message = "ImpulseRC завершился с кодом $ExitCode."
            Color   = "Red"
        }
    }
    if ($DfuAfter -and $DfuBefore) {
        return [pscustomobject]@{
            Status  = "AlreadyInDfu"
            Message = "Полётный контроллер уже находился в режиме DFU и остался доступен."
            Color   = "Cyan"
        }
    }
    if ($DfuAfter) {
        return [pscustomobject]@{
            Status  = "DfuDetected"
            Message = "Полётный контроллер обнаружен в режиме DFU и готов к прошивке."
            Color   = "Green"
        }
    }
    if ($DfuBefore) {
        return [pscustomobject]@{
            Status  = "DfuLost"
            Message = "Полётный контроллер был в режиме DFU до запуска ImpulseRC, но после запуска больше не обнаружен."
            Color   = "Red"
        }
    }

    [pscustomobject]@{
        Status  = "NoDfuDetected"
        Message = "После работы ImpulseRC полётный контроллер в режиме DFU не обнаружен."
        Color   = "Yellow"
    }
}

function Invoke-ImpulseRCDriverFixer {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    Show-FlightControllerWait
    Show-Message -Message "`nПодожди завершения работы утилиты ImpulseRC Driver Fixer." -Color "Gray"

    try {
        if (-not (Test-Path -LiteralPath $Config.DriverFixerPath -PathType Leaf)) {
            throw "ImpulseRC Driver Fixer не найден: $($Config.DriverFixerPath)"
        }

        $dfuBefore = @(Get-ConnectedStm32DfuDevices).Count -gt 0
        $process = Start-Process -FilePath $Config.DriverFixerPath -PassThru -Wait -ErrorAction Stop
        Start-Sleep -Seconds 3
        $dfuAfter = @(Get-ConnectedStm32DfuDevices).Count -gt 0

        $outcome = Get-ImpulseRCOutcome -ExitCode $process.ExitCode -DfuBefore $dfuBefore -DfuAfter $dfuAfter
        Show-Message -Message "`n$($outcome.Message)" -Color $outcome.Color
    }
    catch {
        Show-Message -Message "`nНе удалось запустить ImpulseRC или проверить состояние DFU." -Color "Red"
        Show-Message -Message $_.Exception.Message -Color "DarkRed"
    }

    Show-Exit
}
