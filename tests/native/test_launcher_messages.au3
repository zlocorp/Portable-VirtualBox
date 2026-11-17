#include "..\..\source\LauncherGui.au3"
; Presentation and read-only diagnostics only. No GUI loop or runtime operations.
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL launcher messages: " & $label & @CRLF)
    EndIf
EndFunc

Local $languages[2] = ["ru", "en"]
Local $actions[3] = ["--backup-data", "--verify-backup", "--restore-backup"]
Local $progress[3] = ["backup.running", "backup.verifying", "backup.restoring"]
Local $success[3] = ["backup.created", "backup.verified", "backup.restored"]
Local $profile[]
$profile["status"] = "READY"
$profile["app_present"] = True
For $language In $languages
    _LI_Set($language)
    Local $ordinary = _LR_Decide($profile, "")
    Local $alpha = _LR_Decide($profile, "", True)
    Check($ordinary["status"] == "RESEARCH_ONLY" And $alpha["status"] == "RESEARCH_ONLY", "mode does not grant readiness authority")
    Check($ordinary["code"] == "RUNTIME_DISABLED" And $alpha["code"] == "RUNTIME_DISABLED", "mode does not change readiness code")
    Check($ordinary["message"] == _LI("readiness.disabled"), "ordinary readiness keeps launch disabled")
    Check($alpha["message"] == _LI("readiness.alpha"), "ALPHA readiness explains selected experiment")
    Check(StringInStr($alpha["message"], "ALPHA", 1) > 0, "ALPHA readiness is visibly experimental")
    Local $blocked = _LR_Decide($profile, "A system VirtualBox installation is present", True)
    Local $blockedOrdinary = _LR_Decide($profile, "A system VirtualBox installation is present")
    Check($blocked["status"] == "BLOCKED" And $blocked["code"] == "HOST_CONFLICT", "ALPHA cannot bypass host refusal")
    Check($blocked["message"] == $blockedOrdinary["message"], "host refusal is unchanged by mode")
    $profile["app_present"] = False
    $blocked = _LR_Decide($profile, "", True)
    Check($blocked["status"] == "BLOCKED" And $blocked["code"] == "APP_MISSING", "ALPHA cannot bypass missing app")
    $profile["app_present"] = True
    $profile["status"] = "MISSING"
    $blocked = _LR_Decide($profile, "", True)
    Check($blocked["code"] == "PROFILE_MISSING", "ALPHA cannot bypass missing profile")
    $profile["status"] = "BLOCKED"
    $blocked = _LR_Decide($profile, "", True)
    Check($blocked["code"] == "PROFILE_UNSAFE", "ALPHA cannot bypass unsafe profile")
    $profile["status"] = "READY"

    Local $ordinaryReport = _PortableDiagnosticCollect()
    Local $alphaReport = _PortableDiagnosticCollect(True)
    Check(StringRight($ordinaryReport["text"], StringLen(_LI("diag.runtime")) + 2) == _LI("diag.runtime") & @CRLF, "ordinary diagnostic ends with disabled mode")
    Check(StringRight($alphaReport["text"], StringLen(_LI("diag.runtime_alpha")) + 2) == _LI("diag.runtime_alpha") & @CRLF, "ALPHA diagnostic ends with experimental mode")
    Check(StringInStr(_LA_Text($language), _LI("app.disabled"), 1) > 0, "ordinary About keeps launch disabled")
    Check(StringInStr(_LA_Text($language, True), _LI("app.alpha_runtime"), 1) > 0, "ALPHA About explains selected experiment")
    Check(StringInStr(_LA_Text($language, True), _LI("app.disabled"), 1) == 0, "ALPHA About does not repeat ordinary prohibition")
    Local $modeKeys[3] = ["app.alpha_runtime", "diag.runtime_alpha", "readiness.alpha"]
    For $key In $modeKeys
        Local $modeText = _LI($key)
        Check(StringInStr($modeText, ($language == "ru" ? "явно" : "opt-in")) > 0, "ALPHA is explicit opt-in: " & $key)
        Check(StringInStr($modeText, ($language == "ru" ? "не релиз" : "not a release")) > 0, "ALPHA is not release approval: " & $key)
        Check(StringInStr($modeText, ($language == "ru" ? "не завершена" : "incomplete")) > 0, "Windows interactive acceptance remains incomplete: " & $key)
    Next

    For $i = 0 To UBound($actions) - 1
        Check(_LG_BackupProgressKey($actions[$i]) == $progress[$i], "progress describes actual action")
        Check(_LG_BackupSuccessKey($actions[$i]) == $success[$i], "success describes actual action")
        Local $shown = _LG_BackupText(_LG_BackupSuccessKey($actions[$i]), "D:\Копии\ВМ")
        Check($shown == _LI($success[$i]) & @CRLF & "D:\Копии\ВМ", "localized result retains exact path")
    Next
    Check(StringRegExp(_LI("backup.verified"), "(?i)created|создан") == 0, "verification never claims creation")
    Check(StringRegExp(_LI("backup.verifying"), "(?i)copy and|созда") == 0, "verification progress never claims copying")
    Check(_LG_BackupSuccessKey("unknown") == "backup.failed", "unknown operation cannot claim success")
    Check(_LG_BackupProgressKey("unknown") == "backup.unknown", "unknown operation cannot claim copying")
Next
Check(Not $g_MS_AlphaMode, "display parameters never opt into ALPHA runtime")
ConsoleWrite("Native launcher message checks: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
