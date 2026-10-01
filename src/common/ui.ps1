# Основные функции для работы с консолью и пользовательским интерфейсом

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

function Show-Wait {
    Show-Header
    Show-Message -Message "`nПрограмма выполняется..." -Color "Gray"
}

function Show-Exit {
    Show-Message -Message "`n> Нажми любую клавишу для возврата в меню..." -Color "White"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
