# Запуск из корня проекта:
#   Invoke-Pester -Script .\tests\FlightController.Tests.ps1
#
# Эти примеры проверяют решения приложения без подключённого контроллера:
# Pester подменяет запрос оборудования, а проверка отсутствующей утилиты
# не запускает внешний процесс и не обращается к STM32.

. (Join-Path $PSScriptRoot "..\src\common\ui.ps1")
. (Join-Path $PSScriptRoot "..\src\flightController\devices.ps1")
. (Join-Path $PSScriptRoot "..\src\flightController\firmware.ps1")
. (Join-Path $PSScriptRoot "..\src\radioModule\operations.ps1")

Describe "Show-Message line breaks" {
    It "starts a new line only when the NewLine switch is provided" {
        $originalWriter = [Console]::Out
        $writer = New-Object System.IO.StringWriter

        try {
            [Console]::SetOut($writer)
            Show-Message -Message "Test message" -Level "Status" -NewLine
            $withNewLine = $writer.ToString()

            $writer.GetStringBuilder().Clear() | Out-Null
            Show-Message -Message "Test message" -Level "Status"
            $withoutNewLine = $writer.ToString()
        }
        finally {
            [Console]::SetOut($originalWriter)
            $writer.Dispose()
        }

        $withNewLine | Should Be ([Environment]::NewLine + "[СТАТУС] Test message" + [Environment]::NewLine)
        $withoutNewLine | Should Be ("[СТАТУС] Test message" + [Environment]::NewLine)
    }
}

Describe "Show-Message input prompts" {
    It "prints a choice prompt with a greater-than sign and returns the entered value" {
        $originalWriter = [Console]::Out
        $originalReader = [Console]::In
        $writer = New-Object System.IO.StringWriter
        $reader = New-Object System.IO.StringReader("2`n")

        try {
            [Console]::SetOut($writer)
            [Console]::SetIn($reader)
            $choice = Show-Message -Message "Выбери действие: " -Input Choice
            $prompt = $writer.ToString()
        }
        finally {
            [Console]::SetOut($originalWriter)
            [Console]::SetIn($originalReader)
            $writer.Dispose()
            $reader.Dispose()
        }

        $prompt | Should Be "> Выбери действие: "
        $choice | Should Be "2"
    }

    It "starts a new line before the input marker" {
        $originalWriter = [Console]::Out
        $originalReader = [Console]::In
        $writer = New-Object System.IO.StringWriter
        $reader = New-Object System.IO.StringReader("yes`n")

        try {
            [Console]::SetOut($writer)
            [Console]::SetIn($reader)
            $null = Show-Message -Message "Выбери действие: " -Input Choice -NewLine
            $prompt = $writer.ToString()
        }
        finally {
            [Console]::SetOut($originalWriter)
            [Console]::SetIn($originalReader)
            $writer.Dispose()
            $reader.Dispose()
        }

        $prompt | Should Be ([Environment]::NewLine + "> Выбери действие: ")
    }

    It "ignores typed keys and waits silently until Enter" {
        $originalWriter = [Console]::Out
        $writer = New-Object System.IO.StringWriter
        $script:inputKeys = New-Object System.Collections.Queue
        $script:inputKeys.Enqueue([pscustomobject]@{ Character = "x"; VirtualKeyCode = 88 })
        $script:inputKeys.Enqueue([pscustomobject]@{ Character = " "; VirtualKeyCode = 32 })
        $script:inputKeys.Enqueue([pscustomobject]@{ Character = "`r"; VirtualKeyCode = 13 })

        try {
            [Console]::SetOut($writer)
            Mock Read-InputKey { $script:inputKeys.Dequeue() }
            $result = Show-Message -Message "Нажми Enter для продолжения..." -Input Enter
            $prompt = $writer.ToString()
            Assert-MockCalled Read-InputKey -Times 3
        }
        finally {
            [Console]::SetOut($originalWriter)
            $writer.Dispose()
        }

        $prompt | Should Be "> Нажми Enter для продолжения..."
        $result | Should Be $null
    }
}

Describe "Shared file dialogs" {
    BeforeEach {
        $script:capturedFileDialog = $null
    }

    It "configures an open dialog with BIN and HEX choices and requires an existing file" {
        Mock New-Object {
            $dialog = [pscustomobject]@{
                FileName        = "selected.hex"
                InitialDirectory = ""
                Title           = ""
                Filter          = ""
                CheckFileExists = $false
            }
            Add-Member -InputObject $dialog -MemberType ScriptMethod -Name ShowDialog -Value { return $true }
            $script:capturedFileDialog = $dialog
            $dialog
        } -ParameterFilter { $TypeName -eq "Microsoft.Win32.OpenFileDialog" }

        $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        $path = Get-UserFilePath -Mode Open -Extensions @("bin", "hex") -Purpose "прошивки FC"

        $path | Should Be "selected.hex"
        $script:capturedFileDialog.InitialDirectory | Should Be $desktop
        $script:capturedFileDialog.CheckFileExists | Should Be $true
        $script:capturedFileDialog.Filter | Should Match "Сырой дамп памяти"
        $script:capturedFileDialog.Filter | Should Match "Intel HEX формат"
        $script:capturedFileDialog.Filter | Should Not Match "Все файлы"
    }

    It "configures a BIN save dialog with the default backup name and extension" {
        Mock New-Object {
            $dialog = [pscustomobject]@{
                FileName         = ""
                InitialDirectory = ""
                Title            = ""
                Filter           = ""
                AddExtension     = $false
                ValidateNames    = $false
                DefaultExt       = ""
            }
            Add-Member -InputObject $dialog -MemberType ScriptMethod -Name ShowDialog -Value { return $true }
            $script:capturedFileDialog = $dialog
            $dialog
        } -ParameterFilter { $TypeName -eq "Microsoft.Win32.SaveFileDialog" }

        $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        $path = Get-UserFilePath -Mode Save -Extensions "bin" `
            -Purpose "резервную копию RX" -DefaultFileName "flash_backup.bin"

        $path | Should Be "flash_backup.bin"
        $script:capturedFileDialog.InitialDirectory | Should Be $desktop
        $script:capturedFileDialog.AddExtension | Should Be $true
        $script:capturedFileDialog.ValidateNames | Should Be $true
        $script:capturedFileDialog.DefaultExt | Should Be ".bin"
        $script:capturedFileDialog.Filter | Should Not Match "Все файлы"
    }
}

Describe "STM32 DFU device detection" {
    It "accepts the STM32 bootloader VID/PID and ignores unrelated DFU-named devices" {
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{
                    Present  = $true
                    DeviceID = "USB\VID_0483&PID_DF11\STM32"
                    Name     = "STM32 Bootloader"
                }
                [pscustomobject]@{
                    Present  = $true
                    DeviceID = "USB\VID_1234&PID_5678\OTHER"
                    Name     = "Unrelated DFU Device"
                }
                [pscustomobject]@{
                    Present  = $false
                    DeviceID = "USB\VID_0483&PID_DF11\DISCONNECTED"
                    Name     = "Disconnected STM32"
                }
            )
        }

        $devices = @(Get-ConnectedStm32DfuDevices)

        $devices.Count | Should Be 1
        $devices[0].Name | Should Be "STM32 Bootloader"
    }
}

Describe "Betaflight bootloader request" {
    It "builds the MSP v1 reboot-to-ROM-bootloader packet with a valid checksum" {
        $packet = @(New-BetaflightBootloaderRequest)

        ($packet -join ",") | Should Be "36,77,60,1,68,1,68"
        ($packet[3] -bxor $packet[4] -bxor $packet[5]) | Should Be $packet[6]
    }

    It "builds a read-only MSP FC-variant probe packet" {
        $packet = @(New-BetaflightMspRequest -Command 2)

        ($packet -join ",") | Should Be "36,77,60,0,2,2"
    }
}

Describe "ImpulseRC result classification" {
    It "does not claim that ImpulseRC entered DFU when the device was already there" {
        $result = Get-ImpulseRCOutcome -ExitCode 0 -DfuBefore $true -DfuAfter $true

        $result.Status | Should Be "AlreadyInDfu"
    }

    It "reports the process exit code when ImpulseRC fails" {
        $result = Get-ImpulseRCOutcome -ExitCode 23 -DfuBefore $false -DfuAfter $false

        $result.Status | Should Be "Error"
        $result.Message | Should Match "23"
    }
}

Describe "Firmware write command construction" {
    It "passes a HEX path as one argument and does not launch the real programmer in the test" {
        $script:capturedArguments = @()
        $config = [pscustomobject]@{
            STM32ProgrammerPath = "unused-by-this-test.exe"
        }

        Mock Get-UserFilePath { "C:\firmware images\test.hex" }
        Mock Show-FlightControllerWait {}
        Mock Show-Message {}
        Mock Show-Exit {}
        Mock Invoke-Stm32Command {
            $script:capturedArguments = $Arguments
            [pscustomobject]@{
                Succeeded = $true
                ExitCode  = 0
                Output    = @()
                Error     = $null
            }
        }

        Invoke-FlightControllerFirmwareWrite -Config $config

        ($script:capturedArguments -join "|") |
            Should Be "-c|port=usb1|-w|C:\firmware images\test.hex|-v"
    }
}

Describe "Firmware read command construction" {
    It "reads one mebibyte once instead of overwriting the output with a second command" {
        $script:capturedReadArguments = @()
        $script:readOutputPath = Join-Path $TestDrive "firmware.bin"
        $config = [pscustomobject]@{
            RootDirectory       = $TestDrive
            STM32ProgrammerPath = "unused-by-this-test.exe"
        }

        Mock Get-UserFilePath { $script:readOutputPath }
        Mock Show-FlightControllerWait {}
        Mock Show-FlightControllerHeader {}
        Mock Show-Message {}
        Mock Show-Exit {}
        Mock Invoke-Stm32Command {
            $script:capturedReadArguments = $Arguments
            Set-Content -LiteralPath $Arguments[-1] -Value "mock firmware"
            [pscustomobject]@{
                Succeeded = $true
                ExitCode  = 0
                Output    = @()
                Error     = $null
            }
        }

        Invoke-FlightControllerFirmwareRead -Config $config

        Assert-MockCalled Invoke-Stm32Command -Times 1
        $script:capturedReadArguments[4] | Should Be "0x100000"
    }
}

Describe "STM32 CLI launch validation" {
    It "returns an explicit failure when the configured executable is missing" {
        $config = [pscustomobject]@{
            STM32ProgrammerPath = Join-Path $TestDrive "missing-cli.exe"
        }

        $result = Invoke-Stm32Command -Config $config -Arguments @("-h")

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be $null
        $result.Error | Should Match "не найден"
    }
}

Describe "STM32 runtime dependency lookup" {
    It "skips an incomplete compiler runtime earlier in PATH and finds the complete programmer runtime" {
        $originalPath = $env:PATH
        $toolDirectory = Join-Path $TestDrive "application-bin"
        $compilerDirectory = Join-Path $TestDrive "compiler-bin"
        $runtimeDirectory = Join-Path $TestDrive "programmer-bin"
        $null = New-Item -ItemType Directory -Path $toolDirectory, $compilerDirectory, $runtimeDirectory -Force

        foreach ($fileName in "libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll") {
            Set-Content -LiteralPath (Join-Path $compilerDirectory $fileName) -Value "compiler runtime"
        }
        foreach ($fileName in "Qt6Core.dll", "Qt6Network.dll", "Qt6Qml.dll", "Qt6SerialPort.dll", "Qt6Xml.dll", "libcrypto-3-x64.dll", "liblzma-5.dll", "libminizip.dll", "libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll", "libzstd.dll") {
            Set-Content -LiteralPath (Join-Path $runtimeDirectory $fileName) -Value "programmer runtime"
        }

        try {
            $env:PATH = "$compilerDirectory;$runtimeDirectory"
            $runtime = Get-Stm32RuntimeDirectory -ToolPath (Join-Path $toolDirectory "STM32_Programmer_CLI.exe")
        }
        finally {
            $env:PATH = $originalPath
        }

        $runtime | Should Be $runtimeDirectory
    }

    It "does not accept a runtime folder missing required DLLs" {
        $originalPath = $env:PATH
        $incompleteDirectory = Join-Path $TestDrive "incomplete-bin"
        $null = New-Item -ItemType Directory -Path $incompleteDirectory -Force
        Set-Content -LiteralPath (Join-Path $incompleteDirectory "Qt6Core.dll") -Value "only one library"

        try {
            $env:PATH = $incompleteDirectory
            $runtime = Get-Stm32RuntimeDirectory -ToolPath (Join-Path $incompleteDirectory "STM32_Programmer_CLI.exe")
        }
        finally {
            $env:PATH = $originalPath
        }

        $runtime | Should Be $null
    }

    It "refuses to launch the CLI when its runtime set is incomplete" {
        $originalPath = $env:PATH
        $toolDirectory = Join-Path $TestDrive "cli-without-runtime"
        $null = New-Item -ItemType Directory -Path $toolDirectory -Force
        $toolPath = Join-Path $toolDirectory "STM32_Programmer_CLI.exe"
        Set-Content -LiteralPath $toolPath -Value "placeholder"
        $config = [pscustomobject]@{
            STM32ProgrammerPath = $toolPath
        }

        try {
            $env:PATH = $toolDirectory
            $result = Invoke-Stm32Command -Config $config -Arguments @("-h")
        }
        finally {
            $env:PATH = $originalPath
        }

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be $null
        $result.Error | Should Match "Не найден полный совместимый набор DLL"
    }
}

Describe "esptool command profiles" {
    It "preserves the RX passthrough profile for a whole-image write" {
        $arguments = @(New-RxFullImageArguments -Port "COM7" -FirmwarePath "C:\firmware files\rx.bin")

        ($arguments -join "|") |
            Should Be "--chip|esp32|--port|COM7|--baud|420000|--before|no-reset|--after|no-reset|--no-stub|write-flash|--no-compress|--flash-mode|dio|--flash-freq|40m|--flash-size|4MB|0x0|C:\firmware files\rx.bin"
    }

    It "writes segmented RX firmware at the documented addresses in order" {
        $segments = @(
            [pscustomobject]@{ Address = "0x1000"; Path = "boot.bin" }
            [pscustomobject]@{ Address = "0x8000"; Path = "partitions.bin" }
            [pscustomobject]@{ Address = "0xe000"; Path = "boot_app0.bin" }
            [pscustomobject]@{ Address = "0x10000"; Path = "rx.bin" }
        )
        $arguments = @(New-RxSegmentedFirmwareArguments -Port "COM5" -Segments $segments)

        ($arguments[-8..-1] -join "|") |
            Should Be "0x1000|boot.bin|0x8000|partitions.bin|0xe000|boot_app0.bin|0x10000|rx.bin"
    }

    It "asks for only the RX application and fills the ROI support images from the bundled defaults" {
        $config = [pscustomobject]@{
            RootDirectory = Join-Path $PSScriptRoot ".."
        }
        Mock Get-UserFilePath { "rx-application.bin" }

        $segments = Get-RxSegmentedFirmware -Config $config

        $segments.Count | Should Be 4
        (($segments | ForEach-Object { "$($_.Address)|$([System.IO.Path]::GetFileName($_.Path))" }) -join ";") |
            Should Be "0x1000|bootloader.bin;0x8000|partitions.bin;0xe000|boot_app0.bin;0x10000|rx-application.bin"
        foreach ($segment in $segments[0..2]) {
            (Test-Path -LiteralPath $segment.Path -PathType Leaf) | Should Be $true
        }
        Assert-MockCalled Get-UserFilePath -Times 1
    }

    It "uses the supplied TX image offset and baud rate" {
        $arguments = @(New-TxFirmwareWriteArguments -Port "COM12" -FirmwarePath "tx.bin")

        ($arguments -join "|") | Should Be "--chip|esp32|--port|COM12|--baud|921600|write-flash|0x10000|tx.bin"
    }

    It "reads exactly 4 MiB for RX backups using the no-reset profile" {
        $arguments = @(New-RxFlashReadArguments -Port "COM4" -OutputPath "rx-backup.bin")

        ($arguments[-3..-1] -join "|") | Should Be "0|0x400000|rx-backup.bin"
        ($arguments -contains "--no-stub") | Should Be $true
        ($arguments -contains "no-reset") | Should Be $true
    }

    It "reads exactly 4 MiB for TX backups" {
        $arguments = @(New-TxFlashReadArguments -Port "COM8" -OutputPath "tx-backup.bin")

        ($arguments[-3..-1] -join "|") | Should Be "0|0x400000|tx-backup.bin"
        ($arguments -contains "921600") | Should Be $true
    }
}

Describe "Bundled esptool executable" {
    It "runs its version command without requiring a connected serial device" {
        $config = [pscustomobject]@{
            EsptoolPath = Join-Path $PSScriptRoot "..\files\ESPtool\esptool.exe"
        }
        Mock Show-Message {}

        $result = Invoke-EsptoolCommand -Config $config -Arguments @("version")

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
    }

    It "returns a nonzero status for an invalid esptool command" {
        $config = [pscustomobject]@{
            EsptoolPath = Join-Path $PSScriptRoot "..\files\ESPtool\esptool.exe"
        }

        $result = Invoke-EsptoolCommand -Config $config -Arguments @("not-a-command")

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Not Be 0
    }
}

Describe "FC passthrough RX profile" {
    It "selects ESP32 firmware and the chosen FC port without requesting a chip erase" {
        $arguments = @(New-FcPassthroughRxFlashArguments -Port "COM9" -FirmwarePath "C:\firmware files\rx.bin")

        ($arguments -join "|") |
            Should Be "--port|COM9|--baud|921600|--esp32|--file|C:\firmware files\rx.bin"
        ($arguments -contains "--erase") | Should Be $false
    }

    It "runs the supplied utility help without connecting to hardware" {
        $config = [pscustomobject]@{
            FCPassthroughPath = Join-Path $PSScriptRoot "..\files\FCPassthrough\flash_bin_bfpassthrough.exe"
        }

        $result = Invoke-FcPassthroughFlashCommand -Config $config -Arguments @("--help")

        $result.Succeeded | Should Be $true
        $result.ExitCode | Should Be 0
    }

    It "reports a missing utility instead of attempting to launch it" {
        $config = [pscustomobject]@{
            FCPassthroughPath = Join-Path $TestDrive "missing-flasher.exe"
        }

        $result = Invoke-FcPassthroughFlashCommand -Config $config -Arguments @("--help")

        $result.Succeeded | Should Be $false
        $result.ExitCode | Should Be $null
        $result.Error | Should Match "FC Passthrough"
    }
}
