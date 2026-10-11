# Операции с STM32 CLI. Все внешние команды проходят через Invoke-Stm32Command,
# чтобы единообразно сохранить код возврата и текст диагностики утилиты.

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
        "Qt6Network.dll",
        "Qt6Qml.dll",
        "Qt6SerialPort.dll",
        "Qt6Xml.dll",
        "libcrypto-3-x64.dll",
        "liblzma-5.dll",
        "libminizip.dll",
        "libstdc++-6.dll",
        "libgcc_s_seh-1.dll",
        "libwinpthread-1.dll",
        "libzstd.dll"
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
            Error     = "Не найден полный совместимый набор DLL для STM32CubeProgrammer. Не копируйте только STM32_Programmer_CLI.exe: рядом с ним должны находиться все требуемые DLL из одного каталога bin одной версии."
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

    $saveFile = Get-UserFilePath -Config $Config -Mode Save -Extensions @("bin", "hex") `
        -Purpose "прочитанную прошивку с полётного контроллера" -DefaultFileName "firmware.bin"
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

    $selectedFile = Get-UserFilePath -Config $Config -Mode Open -Extensions @("bin", "hex") `
        -Purpose "прошивки для полётного контроллера"
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
        Show-FlightControllerHeader
        Show-Message -Message "Закройте Betaflight Configurator и другие программы, использующие COM-порты полётника." -Level "Warning" -NewLine
        Show-Message -Message "Программа автоматически проверит COM-порты, найдёт Betaflight FC и отправит запрос перехода в ROM bootloader." -Level "Info"
        Show-Message -Message "Нажмите Enter для продолжения..." -Input Enter -NewLine

        Show-Message -Message "Поиск Betaflight FC по COM-портам (не более 3 секунд)..." -Level "Status" -NewLine
        $result = Invoke-BetaflightBootloaderRequest
        if (-not $result.Succeeded) {
            Show-Message -Message "Не удалось автоматически обнаружить Betaflight FC или отправить запрос перехода в DFU." -Level "Error" -NewLine
            Show-Message -Message $result.Error -Level "Diagnostic"
            Show-Exit
            return
        }

        Show-Message -Message "Обнаружен Betaflight FC на $($result.Port)$(if ($result.BoardIdentifier) { " (target $($result.BoardIdentifier))" }). Ожидание переподключения в режиме DFU..." -Level "Info" -NewLine
        $dfuDevice = $null
        for ($attempt = 0; $attempt -lt 16; $attempt++) {
            Start-Sleep -Milliseconds 500
            try {
                $dfuDevices = @(Get-ConnectedStm32DfuDevices)
            }
            catch {
                Show-Message -Message "Запрос отправлен, но не удалось проверить появление DFU." -Level "Warning" -NewLine
                Show-Message -Message $_.Exception.Message -Level "Diagnostic"
                Show-Exit
                return
            }

            if ($dfuDevices.Count -gt 0) {
                $dfuDevice = $dfuDevices[0]
                break
            }
        }

        if ($dfuDevice) {
            Show-Message -Message "Полётный контроллер перешёл в режим DFU: $($dfuDevice.Name)" -Level "Success" -NewLine
        }
        else {
            Show-Message -Message "Запрос отправлен, но DFU-устройство не обнаружено за 8 секунд. Проверьте поддержку ROM bootloader этой платой." -Level "Warning" -NewLine
        }
        Show-Exit
        return
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
        Show-Message -Message "Команда выхода отправлена. Плата должна перезагрузиться в рабочий режим." -Level "Info" -NewLine
    }
    else {
        Show-Message -Message "Не удалось выполнить команду управления DFU." -Level "Error" -NewLine
        Show-Stm32CommandFailure -Result $result
    }
    Show-Exit
}

function New-BetaflightBootloaderRequest {
    New-BetaflightMspRequest -Command 68 -Payload ([byte[]]@(1))
}

function New-BetaflightMspRequest {
    param (
        [Parameter(Mandatory)]
        [ValidateRange(0, 255)]
        [int]$Command,
        [byte[]]$Payload = @()
    )

    if ($Payload.Length -gt 255) {
        throw "MSP v1 payload cannot exceed 255 bytes."
    }

    $checksum = $Payload.Length -bxor $Command
    foreach ($value in $Payload) {
        $checksum = $checksum -bxor $value
    }

    $packet = New-Object 'System.Collections.Generic.List[byte]'
    $packet.AddRange([byte[]]@(0x24, 0x4D, 0x3C, $Payload.Length, $Command))
    $packet.AddRange($Payload)
    $packet.Add([byte]$checksum)
    $packet.ToArray()
}

function Read-BetaflightMspResponse {
    param (
        [Parameter(Mandatory)]
        [System.IO.Ports.SerialPort]$SerialPort,
        [Parameter(Mandatory)]
        [ValidateRange(0, 255)]
        [int]$Command,
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $state = 0
    $size = 0
    $responseCommand = 0
    $checksum = 0
    $payload = New-Object 'System.Collections.Generic.List[byte]'

    while ($timer.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        try {
            $value = $SerialPort.ReadByte()
        }
        catch [System.TimeoutException] {
            continue
        }

        switch ($state) {
            0 {
                if ($value -eq 0x24) { $state = 1 }
            }
            1 {
                if ($value -eq 0x4D) { $state = 2 }
                elseif ($value -ne 0x24) { $state = 0 }
            }
            2 {
                if ($value -eq 0x3E) { $state = 3 }
                else { $state = 0 }
            }
            3 {
                $size = $value
                $checksum = $size
                $payload.Clear()
                $state = 4
            }
            4 {
                $responseCommand = $value
                $checksum = $checksum -bxor $responseCommand
                $state = if ($size -eq 0) { 6 } else { 5 }
            }
            5 {
                $payload.Add([byte]$value)
                $checksum = $checksum -bxor $value
                if ($payload.Count -eq $size) { $state = 6 }
            }
            6 {
                if ($value -eq $checksum -and $responseCommand -eq $Command) {
                    return ,([byte[]]$payload.ToArray())
                }
                $state = 0
            }
        }
    }

    return $null
}

function Invoke-BetaflightMspProbe {
    param (
        [Parameter(Mandatory)]
        [System.IO.Ports.SerialPort]$SerialPort
    )

    $SerialPort.DiscardInBuffer()
    $variantRequest = New-BetaflightMspRequest -Command 2
    $SerialPort.Write($variantRequest, 0, $variantRequest.Length)
    $variant = Read-BetaflightMspResponse -SerialPort $SerialPort -Command 2 -TimeoutMilliseconds 180
    if ($null -eq $variant -or $variant.Length -lt 4) {
        return $null
    }

    $variantName = [System.Text.Encoding]::ASCII.GetString($variant, 0, 4)
    if ($variantName -cne "BTFL") {
        return $null
    }

    $boardRequest = New-BetaflightMspRequest -Command 4
    $SerialPort.DiscardInBuffer()
    $SerialPort.Write($boardRequest, 0, $boardRequest.Length)
    $boardInfo = Read-BetaflightMspResponse -SerialPort $SerialPort -Command 4 -TimeoutMilliseconds 180

    $boardIdentifier = $null
    if ($null -ne $boardInfo -and $boardInfo.Length -ge 4) {
        $candidate = [System.Text.Encoding]::ASCII.GetString($boardInfo, 0, 4)
        if ($candidate -match '^[A-Z0-9]{4}$') {
            $boardIdentifier = $candidate
        }
    }

    [pscustomobject]@{
        Variant         = $variantName
        BoardIdentifier = $boardIdentifier
    }
}

function Invoke-BetaflightBootloaderRequest {
    try {
        $ports = @(
            [System.IO.Ports.SerialPort]::GetPortNames() |
                Sort-Object {
                    if ($_ -match '^COM(\d+)$') { [int]$matches[1] }
                    else { [int]::MaxValue }
                }
        )
    }
    catch {
        return [pscustomobject]@{
            Succeeded = $false
            Error     = "Не удалось получить список COM-портов: $($_.Exception.Message)"
        }
    }
    if ($ports.Count -eq 0) {
        return [pscustomobject]@{
            Succeeded = $false
            Error     = "Не найдено ни одного COM-порта."
        }
    }

    $scanTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastError = $null
    foreach ($port in $ports) {
        if ($scanTimer.ElapsedMilliseconds -ge 3000) {
            break
        }

        $serialPort = New-Object -TypeName System.IO.Ports.SerialPort `
            -ArgumentList @($port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
        $serialPort.ReadTimeout = 25
        $serialPort.WriteTimeout = 250

        try {
            $serialPort.Open()
            $controller = Invoke-BetaflightMspProbe -SerialPort $serialPort
            if ($null -eq $controller) {
                continue
            }

            $request = New-BetaflightBootloaderRequest
            $serialPort.Write($request, 0, $request.Length)
            $serialPort.BaseStream.Flush()
            Start-Sleep -Milliseconds 150

            return [pscustomobject]@{
                Succeeded       = $true
                Error           = $null
                Port            = $port
                BoardIdentifier = $controller.BoardIdentifier
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        finally {
            if ($serialPort.IsOpen) {
                $serialPort.Close()
            }
            $serialPort.Dispose()
        }
    }

    $errorMessage = "За 3 секунды не найден отвечающий на Betaflight MSP полётный контроллер."
    if ($lastError) {
        $errorMessage += " Последняя ошибка COM-порта: $lastError"
    }
    [pscustomobject]@{
        Succeeded = $false
        Error     = $errorMessage
    }
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
