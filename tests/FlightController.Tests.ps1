# Запуск из корня проекта:
#   Invoke-Pester -Script .\tests\FlightController.Tests.ps1
#
# Эти примеры проверяют решения приложения без подключённого контроллера:
# Pester подменяет запрос оборудования, а проверка отсутствующей утилиты
# не запускает внешний процесс и не обращается к STM32.

. (Join-Path $PSScriptRoot "..\src\common\ui.ps1")
. (Join-Path $PSScriptRoot "..\src\flightController\devices.ps1")
. (Join-Path $PSScriptRoot "..\src\flightController\firmware.ps1")

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
