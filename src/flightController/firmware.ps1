# Функции для работы с прошивкой полётного контроллера (STM32)

# Нативный диалог сохранения Windows
function Get-SaveFilePath {
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.InitialDirectory = $scriptDir
    $dialog.Title = "Выбери, куда сохранить считанную прошивку"
    $dialog.Filter = "Сырой дамп памяти (*.bin)|*.bin|Intel HEX формат (*.hex)|*.hex"
    $dialog.FileName = "fw.bin"
    $dialog.ValidateNames = $true
    if ($dialog.ShowDialog() -eq $true) { return $dialog.FileName }
    return $null
}

# Нативный диалог открытия Windows (Высокая чёткость DPI и поддержка Темной темы)
function Get-OpenFilePath {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.InitialDirectory = $scriptDir
    $dialog.Title = "Выбери файл прошивки для записи на полётник"
    $dialog.Filter = "Файлы прошивок (*.bin;*.hex)|*.bin;*.hex|Сырой дамп памяти (*.bin)|*.bin|Intel HEX формат (*.hex)|*.hex"
    if ($dialog.ShowDialog() -eq $true) { return $dialog.FileName }
    return $null
}

# Read FW (Чтение с выбором пути сохранения)
function Get-FlightControllerRead {
    $saveFile = Get-SaveFilePath
    if ($null -eq $saveFile) {
        Show-FlightControllerHeader
        Show-Message -Message "`nОперация отменена пользователем." -Color "Yellow"
        Show-Exit
        return
    }

    Show-FlightControllerWait
    if (Test-Path $saveFile) { Remove-Item $saveFile -Force -ErrorAction SilentlyContinue }
            
    & $stm32Tool -c port=usb1 -r 0x08000000 0x80000 "$saveFile" | Out-Null
    & $stm32Tool -c port=usb1 -r 0x08000000 0x100000 "$saveFile" | Out-Null

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
function Get-FlightControllerWrite {
    $selectedFile = Get-OpenFilePath
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
        & $stm32Tool -c port=usb1 -w "$selectedFile" -v | Out-Null
    }
    else {
        & $stm32Tool -c port=usb1 -w "$selectedFile" 0x08000000 -v | Out-Null
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
function Get-FlightControllerErase {
    Show-FlightControllerWait
    & $stm32Tool -c port=usb1 -e all | Out-Null
            
    if ($LastExitCode -eq 0) {
        Show-Message -Message "`nОперация выполнена - прошивка на полётнике стёрта." -Color "Green"
    }
    else {
        Show-Message -Message "`nПрошивка НЕ стёрта. Возможно, полётник не в режиме DFU (попробуй запустить ImpulseRC)" -Color "Yellow"
    }
    Show-Exit
}

# Управление режимом DFU
function Get-FlightControllerDFU {
    Show-FlightControllerHeader
    Show-Message -Message "
    Управление состоянием контроллера:

    1. Попробовать перевести подключенный ПК в режим DFU (через USB)
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
        & $stm32Tool -c port=usb1 -s | Out-Null
        Show-Message -Message "`nКоманда отправлена. Если плата поддерживает программный DFU, она переподключится." -Color "Green"
        Show-Exit
    }
    elseif ($dfuChoice -eq "2") {
        Show-FlightControllerWait
        & $stm32Tool -c port=usb1 -g 0x08000000 | Out-Null
        Show-Message -Message "`nКоманда выхода отправлена. Плата перезагружается в рабочий режим." -Color "Green"
        Show-Exit
    }
    else {
        Show-WrongInput -Menu "FlightController"
    }
}

# Исправление драйверов ImpulseRC с чистой аппаратной проверкой
function Get-FlightControllerImpulseRC {
    try {
        Show-FlightControllerWait
        Show-Message -Message "`nПодожди завершения работы утилиты ImpulseRC Driver Fixer." -Color "Gray"
        
        # 1. Фиксируем статус DFU устройства ДО запуска через универсальный CIM
        $allDevsBefore = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
        $dfuBefore = $allDevsBefore | Where-Object { $_.Present -and ($_.Name -like "*DFU*" -or $_.DeviceID -like "*VID_0483&PID_DF11*") }
        $hadDfu = $null -ne $dfuBefore
        # 2. Запускаем процесс и ждем его закрытия
        $proc = Start-Process $driverTool -PassThru -Wait
        # Короткая пауза для обновления конфигурации оборудования операционной системой
        Start-Sleep -Seconds 3
        # 3. Делаем повторный аппаратный опрос системы ПОСЛЕ закрытия утилиты
        $allDevsAfter = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
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
