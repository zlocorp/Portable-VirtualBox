#include "..\..\source\LauncherI18n.au3"
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL i18n: " & $label & @CRLF)
    EndIf
EndFunc
Check(_LI_Detect("0419") == "ru", "Russian host locale")
Check(_LI_Detect("0819") == "ru", "Russian locale suffix")
Check(_LI_Detect("0409") == "en", "English host locale")
Check(_LI_Detect("0411") == "en", "unsupported locale falls back to English")
Check(_LI_Set("ru"), "select Russian")
Check(_LI_Language() == "ru", "selected locale stored")
Check(Not _LI_Set("fr"), "unknown locale rejected")
Check(_LI_Language() == "ru", "invalid locale does not change state")
Local $keys = StringSplit("app.title|app.subtitle|app.disabled|gui.diagnostics|gui.refresh|gui.copy|gui.exit|gui.russian|gui.english|gui.readiness|readiness.unknown|readiness.disabled|gui.prepare|gui.path|profile.ready|profile.missing|profile.blocked|profile.appmissing|help.title|help.commands|help.language|help.warning|preflight.ok|preflight.blocked|error.invalid_lang|error.unknown|diag.header|diag.windows|diag.build|diag.product_type|diag.arch|diag.installed|diag.services|diag.services_unknown|diag.processes|diag.processes_unknown|diag.runtime|diag.unknown|diag.os.present|diag.os.absent|diag.installed.present|diag.installed.absent|diag.product.workstation|diag.product.domain|diag.product.server|gui.save_language|gui.auto_language|gui.about|settings.saved|settings.auto_status|settings.blocked|settings.save_failed|settings.invalid|app.incomplete|app.unsafe|app.files_present|diag.manager_processes|diag.guest_processes|diag.background_processes|about.summary|about.upstream|about.maintainer|about.community|about.boundary|backup.create|backup.verify|backup.cancel|backup.choose|backup.hint|backup.syntax|backup.running|backup.cancelled|backup.verified|backup.invalid|backup.failed|backup.blocked|backup.unknown|backup.restore|backup.restored", "|", 2)
For $i = 0 To UBound($keys) - 1
    Local $en = _LI($keys[$i], "en")
    Local $ru = _LI($keys[$i], "ru")
    Check(StringLen($en) > 2 And $en <> $keys[$i], $keys[$i] & " EN coverage")
    Check(StringLen($ru) > 2 And $ru <> $keys[$i], $keys[$i] & " RU coverage")
    Check($ru <> $en, $keys[$i] & " different translations")
Next
Check(StringInStr(_LI("app.disabled","ru"), "Запуск ВМ") > 0 And StringInStr(_LI("app.disabled","ru"), "копирование") > 0, "Russian runtime disclaimer and offline backups")
Check(_LI("missing.unused.key","ru") == "missing.unused.key", "unknown key explicit")
Check(_LI_Blocker("Unsupported architecture (x64 required)","ru") <> "Unsupported architecture (x64 required)", "preflight reason localized")
Check(_LI_Blocker("Unexpected reason","ru") == "Unexpected reason", "unrecognized preflight result preserved")
Check(_LI("help.title", "fr") == _LI("help.title","en"), "unknown catalog defaults to English")
Check(_LI_Observation("installation", "PRESENT", "ru") == "ОБНАРУЖЕН", "installed status localized RU")
Check(_LI_Observation("installation", "ABSENT", "en") == "NOT DETECTED", "installed status localized EN")
Check(_LI_Observation("os", "PRESENT", "ru") == "ОПРЕДЕЛЕНО", "OS status localized RU")
Check(_LI_Observation("installation", "UNKNOWN", "ru") == "НЕИЗВЕСТНО", "unknown is not treated as absence")
Check(_LI_Observation("other", "PRESENT", "en") == "UNKNOWN", "unknown source denied")
Check(_LI_ProductType(1, "ru") == "Рабочая станция", "workstation product type RU")
Check(_LI_ProductType(2, "en") == "Domain controller", "domain controller product type EN")
Check(_LI_ProductType(3, "ru") == "Сервер", "server product type RU")
Check(_LI_ProductType(0, "ru") == "НЕИЗВЕСТНО", "invalid product type remains unknown")
ConsoleWrite("Native launcher i18n checks: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
