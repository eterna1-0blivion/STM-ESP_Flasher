# Запуск из корня проекта:
#   Invoke-Pester -Script .\tests\FlightController.Tests.ps1
#
# Эти примеры проверяют решения приложения без подключённого контроллера:
# Pester подменяет запрос оборудования, а проверка отсутствующей утилиты
# не запускает внешний процесс и не обращается к STM32.

. (Join-Path $PSScriptRoot "..\src\common\ui.ps1")
. (Join-Path $PSScriptRoot "..\src\flightController\devices.ps1")
. (Join-Path $PSScriptRoot "..\src\flightController\firmware.ps1")

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

        Mock Get-OpenFilePath { "C:\firmware images\test.hex" }
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

        Mock Get-SaveFilePath { $script:readOutputPath }
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
        foreach ($fileName in "Qt6Core.dll", "Qt6Xml.dll", "libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll") {
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
