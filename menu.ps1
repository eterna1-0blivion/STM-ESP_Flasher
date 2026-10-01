# author: eterna1_0blivion
$version = 'v0.0.7'

# Принудительно заставляем любую версию PowerShell работать в UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Устанавливаем заголовок консоли, меняем задний фон
$Host.UI.RawUI.WindowTitle = "STM32 Mini-Flasher ($version)"
$Host.UI.RawUI.BackgroundColor = "Black"
Clear-Host

# Корректное определение папки запуска для EXE и для обычного скрипта PS
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
else {
    $scriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$currentDir = $scriptDir

# Подгружаем системную графическую библиотеку для работы с окнами Windows
Add-Type -AssemblyName System.Windows.Forms

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

# Кроссплатформенный опрос оборудования с защитой от ложных срабатываний (Component)
function Get-DeviceStatus {
    $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue
    
    # Фильтруем строго по вхождению "(COM" с открывающей скобкой, чтобы отсечь сторонние компоненты
    $comDevices = $allDevices | Where-Object { $_.Present -and ($_.Name -like "*STMicroelectronics*" -or $_.Name -like "*(COM*") }
    $dfuDevices = $allDevices | Where-Object { $_.Present -and ($_.Name -like "*DFU*" -or $_.DeviceID -like "*VID_0483&PID_DF11*") }

    Show-Message -Message "---------------------------------------------------------" -Color "DarkGray"
    if ($comDevices) {
        foreach ($dev in $comDevices) {
            Show-Message -Message "[СТАТУС] Обнаружен полётник в обычном режиме: $($dev.Name)" -Color "Cyan"
        }
    }
    if ($dfuDevices) {
        foreach ($dev in $dfuDevices) {
            Show-Message -Message "[СТАТУС] Обнаружен полётник в режиме прошивки: $($dev.Name) (DFU)" -Color "Green"
        }
    }
    if (-not $comDevices -and -not $dfuDevices) {
        Show-Message -Message "[СТАТУС] Полётный контроллер не обнаружен." -Color "DarkYellow"
    }
    Show-Message -Message "---------------------------------------------------------" -Color "DarkGray"
}

# Интерактивное окно сохранения файла прошивки через Проводник Windows
function Get-SaveFilePath {
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.InitialDirectory = $scriptDir
    $dialog.Title = "Выбери, куда сохранить считанную прошивку"
    $dialog.Filter = "Сырой дамп памяти (*.bin)|*.bin|Intel HEX формат (*.hex)|*.hex"
    $dialog.FileName = "fw.bin" # имя по умолчанию
    
    # Показываем окно поверх консоли
    $result = $dialog.ShowDialog((New-Object System.Windows.Forms.NativeWindow))
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

# Интерактивное окно выбора файла для записи через Проводник Windows
function Get-OpenFilePath {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = $scriptDir
    $dialog.Title = "Выбери файл прошивки для записи на полётник"
    # Добавлена полная поддержка BIN и HEX стандартов Betaflight
    $dialog.Filter = "Файлы прошивок (*.bin;*.hex)|*.bin;*.hex|Сырой дамп (*.bin)|*.bin|Intel HEX (*.hex)|*.hex"
    
    $result = $dialog.ShowDialog((New-Object System.Windows.Forms.NativeWindow))
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Show-Header {
    Clear-Host
    Show-Message -Message "=== Работа с прошивкой Полётного Контроллера ===" -Color "Cyan"
}

function Show-Menu {
    Show-Header
    Get-DeviceStatus
    
    Show-Message -Message "
    1. Считать прошивку с FC (Выбрать куда сохранить)
    2. Записать прошивку на FC (Выбрать файл на диске)
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
        # Read FW (Чтение с выбором пути сохранения)
        "1" {
            $saveFile = Get-SaveFilePath
            if ($null -eq $saveFile) {
                Show-Header
                Show-Message -Message "`nОперация отменена пользователем." -Color "Yellow"
                Show-Exit
                continue
            }

            Show-Wait
            if (Test-Path $saveFile) { Remove-Item $saveFile -Force -ErrorAction SilentlyContinue }
            
            # Определяем размер считывания в зависимости от расширения, выбранного пользователем
            # По умолчанию шьем стандартные размеры для полетников
            & "$currentDir\bin\stm32pr.exe" -c port=usb1 -r 0x08000000 0x80000 "$saveFile" | Out-Null
            & "$currentDir\bin\stm32pr.exe" -c port=usb1 -r 0x08000000 0x100000 "$saveFile" | Out-Null

            if (Test-Path $saveFile) {
                $fileSize = (Get-Item $saveFile).Length
                if ($fileSize -gt 0) {
                    Show-Message -Message "`nОперация выполнена - прошивка сохранена в:`n$saveFile" -Color "Green"                
                }
                else {
                    Remove-Item $saveFile -Force -ErrorAction SilentlyContinue
                    Show-Message -Message "`nОшибка! Скачанный файл оказался пустым (0 КБ). Прошивка не сохранена." -Color "Red"
                }
            }
            else {
                Show-Message -Message "`nПрошивка НЕ сохранена. Возможно, полётник не в режиме DFU (попробуй запустить ImpulseRC)" -Color "Yellow"
            }
            Show-Exit
        }
        
        # Write FW (Запись через Проводник с автоматическим парсингом BIN/HEX)
        "2" {
            $selectedFile = Get-OpenFilePath
            if ($null -eq $selectedFile) {
                Show-Header
                Show-Message -Message "`nОперация отменена пользователем." -Color "Yellow"
                Show-Exit
                continue
            }

            Show-Wait
            Show-Message -Message "Запись файла: $(Split-Path $selectedFile -Leaf)" -Color "Gray"
            
            $extension = [System.IO.Path]::GetExtension($selectedFile).ToLower()

            if ($extension -eq ".hex") {
                # Для HEX-файлов адрес указывать не нужно, stm32pr берет его из структуры самого HEX
                & "$currentDir\bin\stm32pr.exe" -c port=usb1 -w "$selectedFile" -v | Out-Null
            }
            else {
                # Для BIN-файлов адрес начала секторов обязателен
                & "$currentDir\bin\stm32pr.exe" -c port=usb1 -w "$selectedFile" 0x08000000 -v | Out-Null
            }
            
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

        # Исправление драйверов ImpulseRC с чистой аппаратной проверкой
        "5" {
            Show-Wait
            $DriverTool = Join-Path $scriptDir "ImpulseRC.exe"
            
            try {
                Show-Message -Message "Запуск ImpulseRC Driver Fixer... Пожалуйста, подожди завершения работы утилиты." -Color "Gray"
                
                # 1. Фиксируем статус DFU устройства ДО запуска через универсальный CIM
                $allDevsBefore = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue
                $dfuBefore = $allDevsBefore | Where-Object { $_.Present -and ($_.Name -like "*DFU*" -or $_.DeviceID -like "*VID_0483&PID_DF11*") }
                $hadDfu = $null -ne $dfuBefore
                # 2. Запускаем процесс и ждем его закрытия
                $proc = Start-Process $DriverTool -PassThru -Wait
                # Короткая пауза для обновления конфигурации оборудования операционной системой
                Start-Sleep -Seconds 3
                # 3. Делаем повторный аппаратный опрос системы ПОСЛЕ закрытия утилиты
                $allDevsAfter = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue
                $dfuAfter = $allDevsAfter | Where-Object { $_.Present -and ($_.Name -like "*DFU*" -or $_.DeviceID -like "*VID_0483&PID_DF11*") }
                $hasDfuNow = $null -ne $dfuAfter
                # 4. Анализируем реальное изменение конфигурации железа
                if ($proc.ExitCode -ne 0) {
                    Show-Message -Message "`n[ОШИБКА]: Утилита ImpulseRC Driver Fixer завершила работу с системной ошибкой: $($proc.ExitCode)." -Color "Red"
                }
                elseif ($hasDfuNow) {
                    Show-Message -Message "`n[УСПЕХ]: Полётник успешно переведён в режим DFU и готов к прошивке!" -Color "Green"
                }
                elseif ($hadDfu -and -not $hasDfuNow) {
                    Show-Message -Message "`n[ОШИБКА]: Полётник отключился или вышел из режима DFU после работы утилиты." -Color "Red"
                }
                else {
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
