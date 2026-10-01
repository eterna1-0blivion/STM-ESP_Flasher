# author: eterna1_0blivion
$version = 'v0.0.4b'

# Устанавливаем заголовок консоли и меняем задний фон
$Host.UI.RawUI.WindowTitle = "STM32 Mini-Flasher ($version)"; $Host.UI.RawUI.BackgroundColor = "Black"

# Корректное определение папки запуска для EXE и для обычного скрипта PS
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
else {
    $scriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$currentDir = $scriptDir

# Вывод сообщений в консоль
function Show-Message {
    param (
        [string]$Message,
        [ValidateSet("Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta",
            "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan", "Red", "Magenta", "Yellow", "White")]
        [string]$Color = "White"
    )
    [Console]::ForegroundColor = [ConsoleColor]::$Color
    [Console]::WriteLine("$Message")
}

# Ввод от пользователя
function Show-Input {
    param (
        [string]$Message
    )
    [Console]::ForegroundColor = [ConsoleColor]::White
    [Console]::Write("$Message")
}

# Динамическое определение статуса подключений COM и DFU устройств
function Get-DeviceStatus {
    $comDevices = Get-PnpDevice -PresentOnly -Class "Ports" -ErrorAction SilentlyContinue 
    | Where-Object { $_.FriendlyName -like "*STMicroelectronics*" -or $_.FriendlyName -like "*COM*" }
    $dfuDevices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue 
    | Where-Object { $_.FriendlyName -like "*DFU*" -or $_.InstanceId -like "*USB\VID_0483&PID_DF11*" }

    Show-Message -Message "---------------------------------------------------------" -Color "DarkGray"
    if ($comDevices) {
        foreach ($dev in $comDevices) {
            Show-Message -Message "[СТАТУС] Обнаружен полётник в обычном режиме: $($dev.FriendlyName)" -Color "Cyan"
        }
    }
    if ($dfuDevices) {
        foreach ($dev in $dfuDevices) {
            Show-Message -Message "[СТАТУС] Обнаружен полётник в режиме прошивки: $($dev.FriendlyName) (DFU)" -Color "Green"
        }
    }
    if (-not $comDevices -and -not $dfuDevices) {
        Show-Message -Message "[СТАТУС] Полётный контроллер не обнаружен." -Color "DarkYellow"
    }
    Show-Message -Message "---------------------------------------------------------" -Color "DarkGray"
}

# Выбор файлов прошивки
function Select-FirmwareFile {
    $binFiles = Get-ChildItem -Path $scriptDir -Filter *.bin | Where-Object { $_.Name -ne "fw.bin" }
    $defaultFile = Join-Path $scriptDir "fw.bin"
    
    if ($binFiles.Count -eq 0) {
        if (Test-Path $defaultFile) { return $defaultFile }
        return $null
    }

    Show-Header
    $fileMenu = "`nВ папке программы найдены файлы прошивок. Выбери нужный:`n"
    if (Test-Path $defaultFile) { 
        $defTime = (Get-Item $defaultFile).LastWriteTime.ToString("dd.MM.yyyy HH:mm")
        $fileMenu += "`n1. Стандартный файл: fw.bin [$defTime]" 
    }
    
    $fileList = @()
    if (Test-Path $defaultFile) { $fileList += , $defaultFile }
    
    $startIndex = $fileList.Count + 1
    for ($i = 0; $i -lt $binFiles.Count; $i++) {
        $fileList += , $binFiles[$i].FullName
        $fileTime = $binFiles[$i].LastWriteTime.ToString("dd.MM.yyyy HH:mm")
        $fileMenu += "`n$($startIndex + $i). $($binFiles[$i].Name) [$fileTime]"
    }
    $fileMenu += "`n0. Отмена операции"
    
    Show-Message -Message $fileMenu -Color "White"

    while ($true) {
        Show-Input "`n> Введи номер файла: "
        $fChoice = [Console]::ReadLine()
        if ($fChoice -eq "0") { return $null }
        
        $parsedIndex = 0
        if ([int]::TryParse($fChoice, [ref]$parsedIndex) -and $parsedIndex -le $fileList.Count -and $parsedIndex -gt 0) {
            return $fileList[$parsedIndex - 1]
        }
        Show-Message -Message "Команда не найдена. Попробуй другую." -Color "Yellow"
    }
}

function Show-Header {
    Clear-Host
    Show-Message -Message "=== Работа с прошивкой Полётного Контроллера ===" -Color "Cyan"
}

function Show-Menu {
    Show-Header
    Get-DeviceStatus
    
    Show-Message -Message "
    1. Считать прошивку с FC (Сохранить в fw.bin)
    2. Записать прошивку на FC (Выбор файла)
    3. Полностью стереть прошивку на FC
    4. Управление режимом DFU (Вход / Выход)
    5. Помощник исправления драйверов (ImpulseRC)

    0. Выход из программы
    " -Color "White"

    Show-Input "> Выбери действие [0-5]: "
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
            $TargetFile = Join-Path $scriptDir "fw.bin"
            if (Test-Path $TargetFile) { Remove-Item $TargetFile -Force -ErrorAction SilentlyContinue }
            
            & "$currentDir\bin\stm32pr.exe" -c port=usb1 -r 0x08000000 0x80000 "$TargetFile" | Out-Null
            & "$currentDir\bin\stm32pr.exe" -c port=usb1 -r 0x08000000 0x100000 "$TargetFile" | Out-Null

            if (Test-Path $TargetFile) {
                $fileSize = (Get-Item $TargetFile).Length
                if ($fileSize -gt 0) {
                    Show-Message -Message "`nОперация выполнена - прошивка 'fw.bin' находится в папке программы." -Color "Green"                
                }
                else {
                    Remove-Item $TargetFile -Force -ErrorAction SilentlyContinue
                    Show-Message -Message "`nОшибка! Скачанный файл оказался пустым (0 КБ). Прошивка не сохранена." -Color "Red"
                }
            }
            else {
                Show-Message -Message "`nПрошивка НЕ сохранена. Возможно, полётник не в режиме DFU (попробуй запустить ImpulseRC)" -Color "Yellow"
            }
            Show-Exit
        }
        
        # Write FW
        "2" {
            $SelectedFile = Select-FirmwareFile
            if ($null -eq $SelectedFile) {
                Show-Header
                Show-Message -Message "`nОперация отменена или файлы прошивки (.bin) не обнаружены." -Color "Yellow"
                Show-Exit
                continue
            }

            Show-Wait
            Show-Message -Message "Запись файла: $(Split-Path $SelectedFile -Leaf)" -Color "Gray"
            
            & "$currentDir\bin\stm32pr.exe" -c port=usb1 -w "$SelectedFile" 0x08000000 -v | Out-Null
            
            if ($LastExitCode -eq 0) {
                Show-Message -Message "`nОперация выполнена - прошивка записана на полётник." -Color "Green"
            }
            else {
                Show-Message -Message "`nПрошивка НЕ записана. Возможно, полётник не в режиме DFU (попробуй запустить ImpulseRC)" -Color "Yellow"
            }
            Show-Exit
        }
        
        # Erase FW
        "3" {
            Show-Wait
            & "$currentDir\bin\stm32pr.exe" -c port=usb1 -e all | Out-Null
            
            if ($LastExitCode -eq 0) {
                Show-Message -Message "`nОперация выполнена - прошивка на полётнике стёрта." -Color "Green"
            }
            else {
                Show-Message -Message "`nПрошивка НЕ стёрта. Возможно, полётник не в режиме DFU (попробуй запустить ImpulseRC)" -Color "Yellow"
            }
            Show-Exit
        }

            # Управление режимом DFU
        "4" {
            Show-Header
            Show-Message -Message "
    Управление состоянием контроллера:

    1. Попробовать перевести подключенный ПК в режим DFU (через USB)
    2. Выйти из режима DFU и перезагрузить плату
    
    0. Назад
            " -Color "White"
            Show-Input "> Выбери действие [0-2]: "
            $dfuChoice = [Console]::ReadLine()

            # Если выбрали Назад, мгновенно прыгаем в начало главного цикла while
            if ($dfuChoice -eq "0") {
                continue
            }

            if ($dfuChoice -eq "1") {
                Show-Wait
                & "$currentDir\bin\stm32pr.exe" -c port=usb1 -s | Out-Null
                Show-Message -Message "`nКоманда отправлена. Если плата поддерживает программный DFU, она переподключится." -Color "Green"
                Show-Exit
            }
            elseif ($dfuChoice -eq "2") {
                Show-Wait
                & "$currentDir\bin\stm32pr.exe" -c port=usb1 -g 0x08000000 | Out-Null
                Show-Message -Message "`nКоманда выхода отправлена. Плата перезагружается в рабочий режим." -Color "Green"
                Show-Exit
            }
            else {
                Show-Message -Message "`nНеверный ввод. Возврат в меню..." -Color "Yellow"
                Show-Exit
            }
        }

         # Исправление драйверов ImpulseRC с аппаратной проверкой результата
        "5" {
            Show-Wait
            $DriverTool = Join-Path $scriptDir "ImpulseRC.exe"
            
            try {
                Show-Message -Message "Запуск ImpulseRC Driver Fixer... Пожалуйста, подожди завершения работы утилиты." -Color "Gray"
                
                # 1. Фиксируем, было ли DFU устройство в системе ДО запуска
                $dfuBefore = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like "*DFU*" -or $_.InstanceId -like "*USB\VID_0483&PID_DF11*" }
                $hadDfu = $null -ne $dfuBefore

                # 2. Запускаем процесс и ждем его закрытия
                $proc = Start-Process $DriverTool -PassThru -Wait
                
                # Небольшая пауза для Chrome и для того, чтобы Windows обновила список оборудования
                Start-Sleep -Seconds 3
                
                # Глушим паразитные окна Chrome
                $parasiteWindows = Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*Warning*" -or $_.MainWindowTitle -like "*Предупреждение*" }
                if ($parasiteWindows) {
                    $parasiteWindows | Stop-Process -Force -ErrorAction SilentlyContinue
                }

                # 3. Делаем повторный аппаратный опрос системы ПОСЛЕ закрытия утилиты
                $dfuAfter = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like "*DFU*" -or $_.InstanceId -like "*USB\VID_0483&PID_DF11*" }
                $hasDfuNow = $null -ne $dfuAfter

                # 4. Анализируем реальное изменение конфигурации железа
                if ($proc.ExitCode -ne 0) {
                    # Если сама ОС выдала ошибку запуска (например, файл поврежден)
                    Show-Message -Message "`nУтилита ImpulseRC Driver Fixer завершила работу с системной ошибкой: $($proc.ExitCode)." -Color "Red"
                }
                elseif ($hasDfuNow) {
                    # Если устройство в режиме DFU сейчас физически существует в диспетчере задач
                    Show-Message -Message "`n[УСПЕХ]: Полётник успешно переведён в режим DFU и готов к прошивке!" -Color "Green"
                }
                elseif ($hadDfu -and -not $hasDfuNow) {
                    # Редкий случай: устройство было в DFU, но после утилиты пропало
                    Show-Message -Message "`n[СТАТУС]: Полётник отключился или вышел из режима DFU после работы утилиты." -Color "Yellow"
                }
                else {
                    # Единственный логический вывод: DFU как не было, так и нет. Значит, утилиту закрыли вручную или она зависла
                    Show-Message -Message "`n[ОТМЕНА]: Изменений в драйверах не обнаружено. Возможно, утилита была закрыта вручную." -Color "Yellow"
                }
            }
            catch {
                Show-Message -Message "`n[ОШИБКА]: Не удалось корректно запустить или обработать ImpulseRC Driver Fixer." -Color "Red"
                Show-Message -Message $_.Exception.Message -Color "DarkRed"
            }
            Show-Exit
        }

        # Exit Flasher
        "0" {
            exit
        }
    }
}
