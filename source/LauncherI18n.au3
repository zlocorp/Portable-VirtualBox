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
            If $ru Then Return "Запуск ВМ пока отключён. Доступны диагностика и копирование переносимых данных."
            Return "VM startup is disabled. Diagnostics and offline portable-data backup are available."
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
        Case "gui.readiness"
            If $ru Then Return "Проверить готовность к запуску"
            Return "Check launch readiness"
        Case "readiness.unknown"
            If $ru Then Return "Не удалось безопасно определить готовность к запуску."
            Return "Unable to establish launch readiness safely."
        Case "readiness.disabled"
            If $ru Then Return "Предварительные проверки пройдены, но запуск ВМ ещё не включён в этой сборке."
            Return "Preflight checks passed, but VM launch is not enabled in this build."
        Case "gui.prepare"
            If $ru Then Return "Подготовить переносимые папки"
            Return "Prepare portable folders"
        Case "gui.path"
            If $ru Then Return "Переносимая папка: "
            Return "Portable directory: "
        Case "profile.ready"
            If $ru Then Return "Папки настроек, ВМ и журналов готовы."
            Return "Portable profile, VM and log folders are ready."
        Case "profile.missing"
            If $ru Then Return "Переносимые папки пока не созданы."
            Return "Portable data folders have not been created."
        Case "profile.blocked"
            If $ru Then Return "Не удалось безопасно подготовить папки. Проверьте путь и права доступа."
            Return "Cannot safely prepare folders. Check path and permissions."
        Case "profile.appmissing"
            If $ru Then Return "Файлы Oracle VirtualBox в app64 пока отсутствуют."
            Return "Oracle VirtualBox files are not yet present in app64."
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
        Case "diag.unknown"
            If $ru Then Return "НЕИЗВЕСТНО"
            Return "UNKNOWN"
        Case "diag.os.present"
            If $ru Then Return "ОПРЕДЕЛЕНО"
            Return "DETECTED"
        Case "diag.os.absent"
            If $ru Then Return "НЕ ОПРЕДЕЛЕНО"
            Return "NOT DETECTED"
        Case "diag.installed.present"
            If $ru Then Return "ОБНАРУЖЕН"
            Return "DETECTED"
        Case "diag.installed.absent"
            If $ru Then Return "НЕ ОБНАРУЖЕН"
            Return "NOT DETECTED"
        Case "diag.product.workstation"
            If $ru Then Return "Рабочая станция"
            Return "Workstation"
        Case "diag.product.domain"
            If $ru Then Return "Контроллер домена"
            Return "Domain controller"
        Case "diag.product.server"
            If $ru Then Return "Сервер"
            Return "Server"
        Case "gui.save_language"
            If $ru Then Return "Запомнить язык"
            Return "Save language"
        Case "gui.auto_language"
            If $ru Then Return "Язык Windows"
            Return "Windows language"
        Case "gui.about"
            If $ru Then Return "О программе"
            Return "About"
        Case "settings.saved"
            If $ru Then Return "Сохранённый язык: "
            Return "Saved language: "
        Case "settings.auto_status"
            If $ru Then Return "Язык выбирается по настройкам Windows."
            Return "Language follows Windows settings."
        Case "settings.blocked"
            If $ru Then Return "Файл data\launcher.ini не прочитан или имеет неизвестный формат. Он не изменён."
            Return "data\launcher.ini could not be read or has an unknown format. The file was not changed."
        Case "settings.save_failed"
            If $ru Then Return "Не удалось сохранить язык. Проверьте права доступа, launcher.ini и launcher.ini.pending."
            Return "Could not save the language. Check permissions, launcher.ini and launcher.ini.pending."
        Case "settings.invalid"
            If $ru Then Return "Укажите ru, en или auto после --save-language."
            Return "Specify ru, en or auto after --save-language."
        Case "app.incomplete"
            If $ru Then Return "Отсутствуют или пусты файлы app64: "
            Return "Missing or empty app64 files: "
        Case "app.unsafe"
            If $ru Then Return "Путь app64 недоступен или содержит ссылки либо папки вместо файлов."
            Return "The app64 path is inaccessible or contains links or directories in place of files."
        Case "app.files_present"
            If $ru Then Return "Обязательные файлы app64 найдены. Это не проверка подписей и не разрешение запуска ВМ."
            Return "Required app64 files are present. This is not signature verification or permission to start a VM."
        Case "diag.manager_processes"
            If $ru Then Return "Процессы окна управления: "
            Return "Manager processes: "
        Case "diag.guest_processes"
            If $ru Then Return "Процессы ВМ (GUI/headless): "
            Return "VM processes (GUI/headless): "
        Case "diag.background_processes"
            If $ru Then Return "Фоновые процессы VirtualBox: "
            Return "VirtualBox background processes: "
        Case "about.summary"
            If $ru Then Return "Portable-VirtualBox: модернизация 2026 года, предварительная сборка."
            Return "Portable-VirtualBox: 2026 modernization, development preview."
        Case "about.upstream"
            If $ru Then Return "Исходный проект и авторы: "
            Return "Original project and authors: "
        Case "about.maintainer"
            If $ru Then Return "Разработка этой ветки: "
            Return "Modernization maintained by: "
        Case "about.community"
            If $ru Then Return "Идеи и сценарии сообщества: "
            Return "Community ideas and regression references: "
        Case "backup.create"
            If $ru Then Return "Копировать данные ВМ"
            Return "Back up portable data"
        Case "backup.verify"
            If $ru Then Return "Проверить копию"
            Return "Verify backup"
        Case "backup.cancel"
            If $ru Then Return "Отменить копирование"
            Return "Cancel copy"
        Case "backup.choose"
            If $ru Then Return "Выберите папку для резервной копии или существующую копию для проверки"
            Return "Select backup destination parent, or an existing backup to verify"
        Case "backup.hint"
            If $ru Then Return "Резервная копия охватывает только data. Внешние диски ВМ не включены."
            Return "Backs up data only. VM disks outside data are not included."
        Case "backup.syntax"
            If $ru Then Return "Укажите полный путь к папке после --backup-data или --verify-backup."
            Return "Provide an absolute folder path after --backup-data or --verify-backup."
        Case "backup.running"
            If $ru Then Return "Создаётся проверяемая копия. Не запускайте ВМ до завершения."
            Return "Copy and SHA-256 verification in progress. Do not start VMs."
        Case "backup.cancelled"
            If $ru Then Return "Запрошена отмена. Незавершённая папка .pending будет сохранена для проверки."
            Return "Cancellation requested. Incomplete .pending data remains for inspection."
        Case "backup.verified"
            If $ru Then Return "Резервная копия создана и проверена (SHA-256)."
            Return "Backup created and verified (SHA-256)."
        Case "backup.invalid"
            If $ru Then Return "Копия повреждена, неполная или содержит небезопасный путь."
            Return "Backup is damaged, incomplete or contains an unsafe path."
        Case "backup.failed"
            If $ru Then Return "Копирование не завершено. Исходные данные не менялись; проверьте .pending."
            Return "Backup incomplete. Source data unchanged; inspect .pending."
        Case "backup.blocked"
            If $ru Then Return "Копирование заблокировано: VirtualBox работает, путь небезопасен или занята сессия."
            Return "Backup blocked: active VirtualBox, unsafe path or busy session."
        Case "backup.unknown"
            If $ru Then Return "Состояние копирования неизвестно. Не удаляйте промежуточные файлы автоматически."
            Return "Backup process state unknown. Do not automatically delete staged files."
        Case "about.boundary"
            If $ru Then Return "Запуск ВМ в обычном интерфейсе ещё недоступен. Упоминание авторов не означает их одобрения этой сборки."
            Return "This is not a usable VM launcher yet. Attribution does not imply endorsement of this build."
    EndSwitch
    Return $sKey
EndFunc

; Localize public host observations without confusing unknown state with absence.
Func _LI_Observation($kind, $status, $language = "")
    If Not IsString($kind) Or Not IsString($status) Then Return _LI("diag.unknown", $language)
    Switch $kind & "." & $status
        Case "os.PRESENT"
            Return _LI("diag.os.present", $language)
        Case "os.ABSENT"
            Return _LI("diag.os.absent", $language)
        Case "installation.PRESENT"
            Return _LI("diag.installed.present", $language)
        Case "installation.ABSENT"
            Return _LI("diag.installed.absent", $language)
        Case Else
            Return _LI("diag.unknown", $language)
    EndSwitch
EndFunc

Func _LI_ProductType($kind, $language = "")
    If Not IsInt($kind) Then Return _LI("diag.unknown", $language)
    Switch $kind
        Case 1
            Return _LI("diag.product.workstation", $language)
        Case 2
            Return _LI("diag.product.domain", $language)
        Case 3
            Return _LI("diag.product.server", $language)
        Case Else
            Return _LI("diag.unknown", $language)
    EndSwitch
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
