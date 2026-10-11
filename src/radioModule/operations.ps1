# ESP32 RX/TX workflows based on the supplied esptool 5.4.0 commands.
# The ROI-specific direct RX profile preserves no-reset/no-stub; generic RX may use FC passthrough.
# TX follows the original default-reset behavior. Firmware images are selected by the user.

function Get-RadioModuleSerialPort {
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
        Show-Message -Message "Не удалось получить список COM-портов." -Level "Error" -NewLine
        Show-Message -Message $_.Exception.Message -Level "Diagnostic"
        Show-Exit
        return
    }

    if ($ports.Count -eq 0) {
        Show-Message -Message "Не найден ни один COM-порт. Проверьте USB-кабель и драйвер USB-UART модуля." -Level "Error" -NewLine
        Show-Exit
        return
    }

    Show-RadioModuleHeader
    Show-Message -Message "Доступные последовательные порты:" -Level "Status"
    for ($index = 0; $index -lt $ports.Count; $index++) {
        Show-Message -Message "$($index + 1). $($ports[$index])"
    }
    Show-Message -Message "0. Назад"

    $choice = Show-Message -Message "Выбери COM-порт [0-$($ports.Count)]: " -Input Choice -NewLine
    if ($null -eq $choice -or $choice -eq "0") {
        return
    }

    $portIndex = 0
    if (-not [int]::TryParse($choice, [ref]$portIndex) -or $portIndex -lt 1 -or $portIndex -gt $ports.Count) {
        Show-WrongInput -Menu "RadioModule"
        return
    }

    $ports[$portIndex - 1]
}

function Get-RadioModuleFirmwarePath {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config,
        [Parameter(Mandatory)]
        [string]$Title,
        [switch]$Save
    )

    if ($Save) {
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Title = $Title
        $dialog.InitialDirectory = $Config.RootDirectory
        $dialog.Filter = "Образ прошивки (*.bin)|*.bin|Все файлы (*.*)|*.*"
        $dialog.FileName = "flash_backup.bin"
        $dialog.AddExtension = $true
        $dialog.ValidateNames = $true
        $dialog.DefaultExt = ".bin"
    }
    else {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = $Title
        $dialog.InitialDirectory = $Config.RootDirectory
        $dialog.Filter = "Образ прошивки (*.bin)|*.bin|Все файлы (*.*)|*.*"
        $dialog.CheckFileExists = $true
    }

    if ($dialog.ShowDialog() -eq $true) {
        return $dialog.FileName
    }

    return $null
}

function Get-RxSegmentedFirmware {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $firmwarePath = Get-RadioModuleFirmwarePath -Config $Config -Title "Выберите BIN-файл прошивки RX (остальные файлы выберутся автоматически)"
    if ($null -eq $firmwarePath) {
        return $null
    }

    return , @(
        [pscustomobject]@{
            Name    = "Загрузчик"
            Address = "0x1000"
            Path    = Join-Path $Config.RootDirectory "files\radioModule\RX\bootloader.bin"
        }
        [pscustomobject]@{
            Name    = "Таблица разделов"
            Address = "0x8000"
            Path    = Join-Path $Config.RootDirectory "files\radioModule\RX\partitions.bin"
        }
        [pscustomobject]@{
            Name    = "boot_app0"
            Address = "0xe000"
            Path    = Join-Path $Config.RootDirectory "files\radioModule\RX\boot_app0.bin"
        }
        [pscustomobject]@{
            Name    = "Прошивка RX"
            Address = "0x10000"
            Path    = $firmwarePath
        }
    )
}

function Confirm-RadioModuleFlash {
    param (
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [string]$OperationDescription
    )

    Show-RadioModuleHeader
    Show-Separator
    Show-Message -Message "Будет записана прошивка: $OperationDescription" -Level "Warning"
    Show-Message -Message "Выбран порт: $Port" -Level "Status"
    Show-Message -Message "Убедитесь, что на этом порту находится именно нужный модуль и он подготовлен к прошивке."
    Show-Message -Message "Запись изменит содержимое Flash и может стереть затронутые разделы." -Level "Warning"
    Show-Separator

    $confirmation = Show-Message -Message "Для подтверждения введите '111': " -Input Choice -NewLine
    $confirmation -ceq "111"
}

function New-RxFullImageArguments {
    param (
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [string]$FirmwarePath
    )

    @(
        "--chip", "esp32", "--port", $Port, "--baud", "420000",
        "--before", "no-reset", "--after", "no-reset", "--no-stub",
        "write-flash", "--no-compress", "--flash-mode", "dio",
        "--flash-freq", "40m", "--flash-size", "4MB", "0x0", $FirmwarePath
    )
}

function New-RxSegmentedFirmwareArguments {
    param (
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [object[]]$Segments
    )

    $arguments = @(
        "--chip", "esp32", "--port", $Port, "--baud", "420000",
        "--before", "no-reset", "--after", "no-reset", "--no-stub",
        "write-flash", "--no-compress", "--flash-mode", "dio",
        "--flash-freq", "40m", "--flash-size", "4MB"
    )
    foreach ($segment in $Segments) {
        $arguments += @($segment.Address, $segment.Path)
    }

    $arguments
}

function New-RxFlashReadArguments {
    param (
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    @(
        "--chip", "esp32", "--port", $Port, "--baud", "420000",
        "--before", "no-reset", "--after", "no-reset", "--no-stub",
        "read-flash", "0", "0x400000", $OutputPath
    )
}

function New-TxFirmwareWriteArguments {
    param (
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [string]$FirmwarePath
    )

    @(
        "--chip", "esp32", "--port", $Port, "--baud", "921600",
        "write-flash", "0x10000", $FirmwarePath
    )
}

function New-TxFlashReadArguments {
    param (
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    @(
        "--chip", "esp32", "--port", $Port, "--baud", "921600",
        "read-flash", "0", "0x400000", $OutputPath
    )
}

function New-FcPassthroughRxFlashArguments {
    param (
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [string]$FirmwarePath
    )

    @(
        "--port", $Port, "--baud", "921600", "--esp32", "--file", $FirmwarePath
    )
}

function Invoke-EsptoolCommand {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $toolPath = $Config.EsptoolPath
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        return [pscustomobject]@{
            Succeeded = $false
            ExitCode  = $null
            Error     = "esptool.exe не найден: $toolPath"
        }
    }

    try {
        # Do not pipe the native output: esptool uses carriage returns to redraw progress in place.
        $quotedArguments = @($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' })
        $process = Start-Process -FilePath $toolPath -ArgumentList ($quotedArguments -join " ") `
            -NoNewWindow -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode

        [pscustomobject]@{
            Succeeded = ($exitCode -eq 0)
            ExitCode  = $exitCode
            Error     = $null
        }
    }
    catch {
        [pscustomobject]@{
            Succeeded = $false
            ExitCode  = $null
            Error     = $_.Exception.Message
        }
    }
}

function Invoke-FcPassthroughFlashCommand {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $toolPath = $Config.FCPassthroughPath
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
        return [pscustomobject]@{
            Succeeded = $false
            ExitCode  = $null
            Error     = "Утилита FC Passthrough не найдена: $toolPath"
        }
    }

    try {
        $quotedArguments = @($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' })
        $process = Start-Process -FilePath $toolPath -ArgumentList ($quotedArguments -join " ") `
            -NoNewWindow -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode

        [pscustomobject]@{
            Succeeded = ($exitCode -eq 0)
            ExitCode  = $exitCode
            Error     = $null
        }
    }
    catch {
        [pscustomobject]@{
            Succeeded = $false
            ExitCode  = $null
            Error     = $_.Exception.Message
        }
    }
}

function Invoke-RadioModuleOperation {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Config,
        [Parameter(Mandatory)]
        [string]$Port,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [Parameter(Mandatory)]
        [string]$SuccessMessage,
        [Parameter(Mandatory)]
        [string]$ErrorMessage
    )

    Show-RadioModuleHeader
    Show-Message -Message "Операция выполняется через esptool $($Config.EsptoolVersion)." -Level "Info" -NewLine
    Show-Message -Message "Используется порт $Port." -Level "Status"
    $result = Invoke-EsptoolCommand -Config $Config -Arguments $Arguments
    if ($result.Succeeded) {
        Show-Message -Message $SuccessMessage -Level "Success" -NewLine
    }
    else {
        Show-Message -Message $ErrorMessage -Level "Error" -NewLine
        if ($null -ne $result.ExitCode) {
            Show-Message -Message "Код завершения esptool: $($result.ExitCode)." -Level "Diagnostic"
        }
        if ($result.Error) {
            Show-Message -Message $result.Error -Level "Diagnostic"
        }
    }
    Show-Exit
}

function Invoke-FcPassthroughRxFirmwareWrite {
    param ([Parameter(Mandatory)][pscustomobject]$Config)

    $port = Get-RadioModuleSerialPort
    if (-not $port) { return }

    Show-RadioModuleHeader
    Show-Message -Message "Подключите полётный контроллер по USB и убедитесь, что приёмник подключён к поддерживаемому UART." -Level "Info" -NewLine
    Show-Message -Message "Этот способ использует Betaflight FC Passthrough; совместимость зависит от прошивки и конфигурации полётника." -Level "Warning"
    $firmware = Get-RadioModuleFirmwarePath -Config $Config -Title "Выберите BIN-образ прошивки ESP32 RX"
    if (-not $firmware) {
        Show-Message -Message "Выбор прошивки отменён." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    if (-not (Confirm-RadioModuleFlash -Port $port -OperationDescription "прошивка ESP32 RX через FC Passthrough (Betaflight)")) {
        Show-Message -Message "Прошивка не запускалась." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    Show-RadioModuleHeader
    Show-Message -Message "Прошивка RX через FC Passthrough выполняется." -Level "Info" -NewLine
    Show-Message -Message "Используется порт полётного контроллера $port." -Level "Status"
    $arguments = New-FcPassthroughRxFlashArguments -Port $port -FirmwarePath $firmware
    $result = Invoke-FcPassthroughFlashCommand -Config $Config -Arguments $arguments
    if ($result.Succeeded) {
        Show-Message -Message "Прошивка ESP32 RX через полётный контроллер завершена." -Level "Success" -NewLine
    }
    else {
        Show-Message -Message "Не удалось прошить ESP32 RX через полётный контроллер." -Level "Error" -NewLine
        if ($null -ne $result.ExitCode) {
            Show-Message -Message "Код завершения утилиты FC Passthrough: $($result.ExitCode)." -Level "Diagnostic"
        }
        if ($result.Error) {
            Show-Message -Message $result.Error -Level "Diagnostic"
        }
    }
    Show-Exit
}

function Invoke-RxFullImageWrite {
    param ([Parameter(Mandatory)][pscustomobject]$Config)

    $port = Get-RadioModuleSerialPort
    if (-not $port) { return }
    Show-Message -Message "Профиль RX не управляет reset: заранее переведите модуль в режим загрузчика." -Level "Info" -NewLine

    $firmware = Get-RadioModuleFirmwarePath -Config $Config -Title "Выберите цельный 4 МиБ образ прошивки RX"
    if (-not $firmware) {
        Show-Message -Message "Выбор прошивки отменён." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    if (-not (Confirm-RadioModuleFlash -Port $port -OperationDescription "цельный образ RX по адресу 0x0")) {
        Show-Message -Message "Прошивка не запускалась." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    $arguments = New-RxFullImageArguments -Port $port -FirmwarePath $firmware
    Invoke-RadioModuleOperation -Config $Config -Port $port -Arguments $arguments `
        -SuccessMessage "Образ RX записан. Модуль оставлен без reset; перезагрузите его вручную." `
        -ErrorMessage "Не удалось записать образ RX."
}

function Invoke-RxSegmentedFirmwareWrite {
    param ([Parameter(Mandatory)][pscustomobject]$Config)

    $port = Get-RadioModuleSerialPort
    if (-not $port) { return }
    Show-Message -Message "Профиль RX не управляет reset: заранее переведите модуль в режим загрузчика." -Level "Info" -NewLine

    $segments = Get-RxSegmentedFirmware -Config $Config
    if ($null -eq $segments) {
        Show-Message -Message "Выбор прошивки RX отменён." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    if (-not (Confirm-RadioModuleFlash -Port $port -OperationDescription "прошивка RX с фиксированными компонентами ROI и выбранным BIN")) {
        Show-Message -Message "Прошивка не запускалась." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    $arguments = New-RxSegmentedFirmwareArguments -Port $port -Segments $segments
    Invoke-RadioModuleOperation -Config $Config -Port $port -Arguments $arguments `
        -SuccessMessage "Составная прошивка RX записана. Модуль оставлен без reset; перезагрузите его вручную." `
        -ErrorMessage "Не удалось записать составную прошивку RX."
}

function Invoke-RxFlashRead {
    param ([Parameter(Mandatory)][pscustomobject]$Config)

    $port = Get-RadioModuleSerialPort
    if (-not $port) { return }
    Show-Message -Message "Профиль RX не управляет reset: заранее переведите модуль в режим загрузчика." -Level "Info" -NewLine

    $outputPath = Get-RadioModuleFirmwarePath -Config $Config -Title "Укажите файл для резервной копии RX" -Save
    if (-not $outputPath) {
        Show-Message -Message "Выбор файла отменён." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    $arguments = New-RxFlashReadArguments -Port $port -OutputPath $outputPath
    Invoke-RadioModuleOperation -Config $Config -Port $port -Arguments $arguments `
        -SuccessMessage "Резервная копия Flash RX сохранена в: $outputPath" -ErrorMessage "Не удалось прочитать Flash RX."
}

function Invoke-TxFirmwareWrite {
    param ([Parameter(Mandatory)][pscustomobject]$Config)

    $port = Get-RadioModuleSerialPort
    if (-not $port) { return }

    $firmware = Get-RadioModuleFirmwarePath -Config $Config -Title "Выберите файл прошивки TX"
    if (-not $firmware) {
        Show-Message -Message "Выбор прошивки отменён." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    if (-not (Confirm-RadioModuleFlash -Port $port -OperationDescription "прошивка TX по адресу 0x10000")) {
        Show-Message -Message "Прошивка не запускалась." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    $arguments = New-TxFirmwareWriteArguments -Port $port -FirmwarePath $firmware
    Invoke-RadioModuleOperation -Config $Config -Port $port -Arguments $arguments `
        -SuccessMessage "Прошивка TX записана." -ErrorMessage "Не удалось записать прошивку TX."
}

function Invoke-TxFlashRead {
    param ([Parameter(Mandatory)][pscustomobject]$Config)

    $port = Get-RadioModuleSerialPort
    if (-not $port) { return }

    $outputPath = Get-RadioModuleFirmwarePath -Config $Config -Title "Укажите файл для резервной копии TX" -Save
    if (-not $outputPath) {
        Show-Message -Message "Выбор файла отменён." -Level "Cancelled" -NewLine
        Show-Exit
        return
    }

    $arguments = New-TxFlashReadArguments -Port $port -OutputPath $outputPath
    Invoke-RadioModuleOperation -Config $Config -Port $port -Arguments $arguments `
        -SuccessMessage "Резервная копия Flash TX сохранена в: $outputPath" -ErrorMessage "Не удалось прочитать Flash TX."
}
