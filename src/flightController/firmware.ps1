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

function Get-Stm32RuntimeDirectory {
    param (
        [Parameter(Mandatory)]
        [string]$ToolPath
    )

    $candidateDirectories = @(
        (Split-Path -Parent $ToolPath)
        $env:PATH -split [System.IO.Path]::PathSeparator
    ) | Where-Object { $_ } | Select-Object -Unique

    $requiredFiles = @(
        "Qt6Core.dll",
        "Qt6Xml.dll",
        "libstdc++-6.dll",
        "libgcc_s_seh-1.dll",
        "libwinpthread-1.dll"
    )

    foreach ($directory in $candidateDirectories) {
        $hasAllRuntimeFiles = $true
        foreach ($fileName in $requiredFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $directory $fileName) -PathType Leaf)) {
                $hasAllRuntimeFiles = $false
                break
            }
        }

        if (-not $hasAllRuntimeFiles) {
            continue
        }

        $coreVersion = (Get-Item -LiteralPath (Join-Path $directory "Qt6Core.dll")).VersionInfo.FileVersion
        $xmlVersion = (Get-Item -LiteralPath (Join-Path $directory "Qt6Xml.dll")).VersionInfo.FileVersion
        if ($coreVersion -and $xmlVersion -and $coreVersion -ne $xmlVersion) {
            continue
        }

        return $directory
    }

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

    $runtimeDirectory = Get-Stm32RuntimeDirectory -ToolPath $toolPath
    if (-not $runtimeDirectory) {
        return [pscustomobject]@{
            Succeeded = $false
            ExitCode  = $null
            Output    = @()
            Error     = "Не найден полный совместимый набор DLL для STM32CubeProgrammer. Не копируйте только STM32_Programmer_CLI.exe: разместите рядом с ним Qt6Core.dll, Qt6Xml.dll, libstdc++-6.dll, libgcc_s_seh-1.dll и libwinpthread-1.dll из одной папки bin одной версии."
        }
    }

    $originalPath = $env:PATH
    try {
        # STM32CubeCLT и Programmer могут поставлять разные libstdc++/libwinpthread.
        # Ставим DLL из каталога найденной установки раньше остальных записей PATH.
        $env:PATH = "$runtimeDirectory;$originalPath"
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
    finally {
        $env:PATH = $originalPath
    }
}

function Show-Stm32CommandFailure {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Result
    )

    if ($null -ne $Result.ExitCode) {
        Show-Message -Message "Код завершения STM32 CLI: $($Result.ExitCode)." -Level "Diagnostic"
    }
    if ($Result.Error) {
        Show-Message -Message $Result.Error -Level "Diagnostic"
    }
    foreach ($line in $Result.Output) {
        Show-Message -Message $line -Level "Diagnostic"
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
        Show-Message -Message "Операция отменена пользователем." -Level "Cancelled" -NewLine
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
        Show-Message -Message "Не удалось подготовить файл для чтения прошивки." -Level "Error" -NewLine
        Show-Message -Message $_.Exception.Message -Level "Diagnostic"
        Show-Exit
        return
    }

    $result = Invoke-Stm32Command -Config $Config -Arguments @(
        "-c", "port=usb1", "-r", "0x08000000", "0x100000", $saveFile
    )
    if (-not $result.Succeeded) {
        Show-Message -Message "Не удалось прочитать прошивку." -Level "Error" -NewLine
        Show-Stm32CommandFailure -Result $result
        if (Test-Path -LiteralPath $saveFile) {
            try {
                Remove-Item -LiteralPath $saveFile -Force -ErrorAction Stop
            }
            catch {
                Show-Message -Message "Не удалось удалить неполный файл прошивки: $($_.Exception.Message)" -Level "Diagnostic"
            }
        }
        Show-Exit
        return
    }

    if (Test-Path -LiteralPath $saveFile) {
        $fileSize = (Get-Item -LiteralPath $saveFile).Length
        if ($fileSize -gt 0) {
            Show-Message -Message "Прошивка сохранена в:`n$saveFile" -Level "Success" -NewLine
        }
        else {
            Show-Message -Message "Считанный файл пустой (0 байт); прошивка не сохранена." -Level "Error" -NewLine
            try {
                Remove-Item -LiteralPath $saveFile -Force -ErrorAction Stop
            }
            catch {
                Show-Message -Message "Не удалось удалить пустой файл: $($_.Exception.Message)" -Level "Diagnostic"
            }
        }
    }
    else {
        Show-Message -Message "STM32 CLI не сообщил об ошибке, но файл прошивки не был создан." -Level "Error" -NewLine
        foreach ($line in $result.Output) {
            Show-Message -Message $line -Level "Diagnostic"
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
        Show-Message -Message "Операция отменена пользователем." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    Show-FlightControllerWait
    Show-Message -Message "Запись файла: $(Split-Path $selectedFile -Leaf)" -Level "Info"
    $extension = [System.IO.Path]::GetExtension($selectedFile).ToLower()

    if ($extension -eq ".hex") {
        $arguments = @("-c", "port=usb1", "-w", $selectedFile, "-v")
    }
    else {
        $arguments = @("-c", "port=usb1", "-w", $selectedFile, "0x08000000", "-v")
    }

    $result = Invoke-Stm32Command -Config $Config -Arguments $arguments
    if ($result.Succeeded) {
        Show-Message -Message "Прошивка записана на полётный контроллер." -Level "Success" -NewLine
    }
    else {
        Show-Message -Message "Прошивка не записана." -Level "Error" -NewLine
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
        Show-Message -Message "Прошивка на полётном контроллере стёрта." -Level "Success" -NewLine
    }
    else {
        Show-Message -Message "Прошивка не стёрта." -Level "Error" -NewLine
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
    $dfuChoice = Show-Message -Message "Выбери действие [0-2]: " -Input Choice

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
            Show-Message -Message "Команда отправлена. Если плата поддерживает программный DFU, она переподключится." -Level "Info" -NewLine
        }
        else {
            Show-Message -Message "Команда выхода отправлена. Плата должна перезагрузиться в рабочий режим." -Level "Info" -NewLine
        }
    }
    else {
        Show-Message -Message "Не удалось выполнить команду управления DFU." -Level "Error" -NewLine
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
            Level   = "Error"
        }
    }
    if ($DfuAfter -and $DfuBefore) {
        return [pscustomobject]@{
            Status  = "AlreadyInDfu"
            Message = "Полётный контроллер уже находился в режиме DFU и остался доступен."
            Level   = "Status"
        }
    }
    if ($DfuAfter) {
        return [pscustomobject]@{
            Status  = "DfuDetected"
            Message = "Полётный контроллер обнаружен в режиме DFU и готов к прошивке."
            Level   = "Success"
        }
    }
    if ($DfuBefore) {
        return [pscustomobject]@{
            Status  = "DfuLost"
            Message = "Полётный контроллер был в режиме DFU до запуска ImpulseRC, но после запуска больше не обнаружен."
            Level   = "Error"
        }
    }

    [pscustomobject]@{
        Status  = "NoDfuDetected"
        Message = "После работы ImpulseRC полётный контроллер в режиме DFU не обнаружен."
        Level   = "Warning"
    }
}

function Invoke-ImpulseRCDriverFixer {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    Show-FlightControllerWait
    Show-Message -Message "Подожди завершения работы утилиты ImpulseRC Driver Fixer." -Level "Info" -NewLine

    try {
        if (-not (Test-Path -LiteralPath $Config.DriverFixerPath -PathType Leaf)) {
            throw "ImpulseRC Driver Fixer не найден: $($Config.DriverFixerPath)"
        }

        $dfuBefore = @(Get-ConnectedStm32DfuDevices).Count -gt 0
        $process = Start-Process -FilePath $Config.DriverFixerPath -PassThru -Wait -ErrorAction Stop
        Start-Sleep -Seconds 3
        $dfuAfter = @(Get-ConnectedStm32DfuDevices).Count -gt 0

        $outcome = Get-ImpulseRCOutcome -ExitCode $process.ExitCode -DfuBefore $dfuBefore -DfuAfter $dfuAfter
        Show-Message -Message $outcome.Message -Level $outcome.Level  -NewLine
    }
    catch {
        Show-Message -Message "Не удалось запустить ImpulseRC или проверить состояние DFU." -Level "Error"  -NewLine
        Show-Message -Message $_.Exception.Message -Level "Diagnostic"
    }

    Show-Exit
}
