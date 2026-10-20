#include-once
; Launcher translations only. Oracle VirtualBox Manager is localized by Oracle.
; All strings are embedded in the compiled EXE, no untrusted INI loading.
Global $g_LI_Language = "en"

Func _LI_Detect($sOSLang)
    If IsString($sOSLang) And StringRight(StringLower($sOSLang), 2) == "19" Then Return "ru"
    Return "en"
EndFunc

Func _LI_Set($sLanguage)
    If Not IsString($sLanguage) Then Return False
    Local $s = StringLower($sLanguage)
    If Not ($s == "ru" Or $s == "en") Then Return False
    $g_LI_Language = $s
    Return True
EndFunc

Func _LI_Language()
    Return $g_LI_Language
EndFunc

Func _LI($sKey, $sLanguage = "")
    Local $s = $sLanguage
    If Not IsString($s) Then $s = "en"
    If $s == "" Then $s = $g_LI_Language
    If Not ($s == "ru" Or $s == "en") Then $s = "en"
    Local $ru = $s == "ru"
    Switch $sKey
        Case "app.title"
            If $ru Then Return "Портативный VirtualBox"
            Return "Portable-VirtualBox"
        Case "app.subtitle"
            If $ru Then Return "Диагностика системы · предварительная версия"
            Return "System diagnostics · development preview"
        Case "app.disabled"
            If $ru Then Return "Запуск виртуальных машин временно отключён. Эта сборка предназначена только для диагностики."
            Return "Virtual machine startup is currently disabled. This build is for diagnostics only."
        Case "gui.diagnostics"
            If $ru Then Return "Состояние Windows и VirtualBox"
            Return "Windows and VirtualBox status"
        Case "gui.refresh"
            If $ru Then Return "Обновить данные"
            Return "Refresh diagnostics"
        Case "gui.copy"
            If $ru Then Return "Копировать отчёт"
            Return "Copy report"
        Case "gui.exit"
            If $ru Then Return "Закрыть"
            Return "Close"
        Case "gui.russian"
            If $ru Then Return "Русский"
            Return "Russian"
        Case "gui.english"
            If $ru Then Return "Английский"
            Return "English"
        Case "help.title"
            If $ru Then Return "Портативный VirtualBox: диагностическая сборка"
            Return "Portable-VirtualBox: diagnostic preview"
        Case "help.commands"
            If $ru Then Return "Доступные команды:"
            Return "Available commands:"
        Case "help.language"
            If $ru Then Return "Выбор языка: --lang ru или --lang en (перед командой)"
            Return "Select language: --lang ru or --lang en (before a command)"
        Case "help.warning"
            If $ru Then Return "Запуск ВМ, установка и удаление драйверов пока недоступны."
            Return "VM startup, driver installation and driver cleanup are not yet available."
        Case "preflight.ok"
            If $ru Then Return "Предварительная проверка: блокирующих условий не найдено (запуск ВМ отключён)"
            Return "Preflight: no blockers detected (VM startup still disabled)"
        Case "preflight.blocked"
            If $ru Then Return "Предварительная проверка заблокирована: "
            Return "Preflight BLOCKED: "
        Case "error.invalid_lang"
            If $ru Then Return "Ошибка: поддерживаются только языки ru и en."
            Return "Error: supported languages are ru and en only."
        Case "error.unknown"
            If $ru Then Return "Неизвестный параметр. Используйте --help."
            Return "Unknown option. Use --help."
        Case "diag.header"
            If $ru Then Return "Портативный VirtualBox: диагностика без изменений системы"
            Return "Portable-VirtualBox: read-only diagnostics"
        Case "diag.windows"
            If $ru Then Return "Состояние Windows: "
            Return "Windows observation: "
        Case "diag.build"
            If $ru Then Return "Сборка Windows: "
            Return "Windows build: "
        Case "diag.product_type"
            If $ru Then Return "Тип Windows: "
            Return "Windows product type: "
        Case "diag.arch"
            If $ru Then Return "Архитектура ОС: "
            Return "OS architecture: "
        Case "diag.installed"
            If $ru Then Return "Установленный VirtualBox: "
            Return "Installed VirtualBox: "
        Case "diag.services"
            If $ru Then Return "Количество служб VBox: "
            Return "VBox services count: "
        Case "diag.services_unknown"
            If $ru Then Return "Службы VBox: НЕТ ДАННЫХ"
            Return "VBox services: UNKNOWN"
        Case "diag.processes"
            If $ru Then Return "Количество процессов VBox: "
            Return "VBox processes count: "
        Case "diag.processes_unknown"
            If $ru Then Return "Процессы VBox: НЕТ ДАННЫХ"
            Return "VBox processes: UNKNOWN"
        Case "diag.runtime"
            If $ru Then Return "Запуск ВМ: ОТКЛЮЧЁН"
            Return "VM startup: DISABLED"
    EndSwitch
    Return $sKey
EndFunc

; AutoIt ConsoleWrite normally converts Unicode to the host ANSI code page.
; Encode as UTF-8 bytes first; matches the official AutoIt Unicode console guide.
Func _LI_Write($sText, $bError = False)
    Local $sEncoded = BinaryToString(StringToBinary($sText, 4), 1)
    If $bError Then Return ConsoleWriteError($sEncoded)
    Return ConsoleWrite($sEncoded)
EndFunc

; Translate *known* preflight diagnostics, never hide an unfamiliar blocker.
Func _LI_Blocker($sEnglish, $sLanguage = "")
    If $sEnglish == "" Then Return ""
    If $sLanguage <> "ru" Then
        If $sLanguage <> "" Then Return $sEnglish
        If _LI_Language() <> "ru" Then Return $sEnglish
    EndIf
    Switch $sEnglish
        Case "Unsupported architecture (x64 required)"
            Return "Необходима 64-разрядная архитектура x64."
        Case "Unsupported Windows product/build (Windows 11 workstation required)"
            Return "Нужна поддерживаемая клиентская Windows 11 x64."
        Case "VirtualBox installation state is unknown"
            Return "Не удалось определить, установлен ли системный VirtualBox."
        Case "VirtualBox service state is unknown"
            Return "Не удалось безопасно прочитать состояние служб VirtualBox."
        Case "VirtualBox process state is unknown"
            Return "Не удалось безопасно прочитать состояние процессов VirtualBox."
        Case "Portable executable state is unknown"
            Return "Не удалось определить наличие исполняемого файла VirtualBox."
        Case "A system VirtualBox installation is present"
            Return "Обнаружена существующая системная установка VirtualBox."
        Case "Pre-existing VirtualBox services detected"
            Return "Обнаружены ранее зарегистрированные службы VirtualBox."
        Case "Pre-existing VirtualBox processes detected"
            Return "Обнаружены уже работающие процессы VirtualBox."
        Case "Portable app64\VirtualBox.exe is absent"
            Return "В каталоге app64 отсутствует VirtualBox.exe."
        Case "Unsupported or unreadable VBox version"
            Return "Версия VirtualBox не поддерживается или не определяется."
        Case "Windows version observation is unknown"
            Return "Не удалось определить версию Windows."
    EndSwitch
    Return $sEnglish
EndFunc
