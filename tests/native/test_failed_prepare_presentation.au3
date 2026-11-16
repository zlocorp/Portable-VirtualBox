#include "..\..\source\ManagerWindow.au3"
; Pure presentation calls only. No windows, services, helper or child are started.
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL failed preparation presentation: " & $label & @CRLF)
    EndIf
EndFunc
Local $s = _MS_New("unused", "unused"), $worker = _MP_New()
$worker["status"] = "EXITED"
$worker["exit_code"] = 70
$s["worker"] = $worker
$s["state"] = "FAILED"
$s["failed_worker_phase"] = "PREPARING"
Local $sup = _WinObsResult("service", "PRESENT")
$sup["name"] = "VBoxSup"
$sup["state"] = 4
Local $sds = _WinObsError("service", "open", 1060)
$sds["name"] = "VBoxSDS"
Local $rows[2] = [$sup, $sds]
Check(_MSW_ServicePresence($rows, "VBoxSup") == "PRESENT", "existing Sup observation")
Check(_MSW_ServicePresence($rows, "VBoxSDS") == "ABSENT", "exact SCM1060 absence")
For $phase In StringSplit("PREPARING|CONSENT_PREPARE", "|", 2)
    $s["failed_worker_phase"] = $phase
    For $language In StringSplit("ru|en", "|", 2)
        _LI_Set($language)
        Local $text = _MSW_FailedPrepareHint($s, $rows, 0)
        Check(StringInStr($text, ($language == "ru" ? "Последняя проверка служб Windows:" : "Last Windows service check:")) And Not StringInStr($text, "SCM") And Not StringInStr($text, ChrW(0x2014)), "plain localized observation label")
        Check(StringLen($text) > 0 And StringInStr($text, "VBoxSup") And StringInStr($text, "VBoxSDS"), "localized preparation context")
        Check(StringInStr($text, ($language == "ru" ? "не подтверждение владения или отката" : "does not establish ownership or rollback")), "no authority claim")
        Check(StringInStr($text, ($language == "ru" ? "может быть отклонено" : "may be refused")), "no promised recovery")
    Next
    Check(Not _MS_RetryAllowed($s["state"], $s["detail"]), "Start remains blocked")
    Check(_MS_CleanupRetryAction($s) == "", "Prepare has no cleanup retry")
    Check($s["state"] == "FAILED" And $worker["exit_code"] = 70, "presentation does not repair outcome")
Next
For $error In StringSplit("0|5|1072", "|", 2)
    $sds = _WinObsError("service", "open", Int($error))
    $sds["name"] = "VBoxSDS"
    $rows[1] = $sds
    Check(_MSW_ServicePresence($rows, "VBoxSDS") == "UNKNOWN", "error is not absence")
    _LI_Set("en")
    Check(StringInStr(_MSW_FailedPrepareHint($s, $rows, 0), "VBoxSDS unknown"), "unknown text not absent/clean")
Next
For $age In StringSplit("-1|2501|10000", "|", 2)
    Check(StringInStr(_MSW_FailedPrepareHint($s, $rows, Int($age)), "VBoxSup unknown; VBoxSDS unknown"), "stale or unavailable observation UNKNOWN")
Next
Check(StringInStr(_MSW_FailedPrepareHint($s, $rows), "VBoxSup unknown; VBoxSDS unknown"), "missing observation age UNKNOWN")
Local $badTyped = $sds
$badTyped["status"] = 0
$rows[1] = $badTyped
Check(_MSW_ServicePresence($rows, "VBoxSDS") == "UNKNOWN", "nonstring status unknown")
$rows[1] = $sds
Local $duplicate[3] = [$sup, $sds, $sds]
Check(_MSW_ServicePresence($duplicate, "VBoxSDS") == "UNKNOWN", "duplicate cannot establish absence")
Local $missing[1] = [$sup]
Check(_MSW_ServicePresence($missing, "VBoxSDS") == "UNKNOWN", "missing row unknown")
Local $malformed[2] = [$sup, "not a row"]
Check(_MSW_ServicePresence($malformed, "VBoxSDS") == "UNKNOWN", "malformed row unknown")
For $phase In StringSplit("CLEANING|CONSENT_FINISH|RECOVERING|CONSENT_RECOVER|OPENING", "|", 2)
    $s["failed_worker_phase"] = $phase
    Check(_MSW_FailedPrepareHint($s, $rows, 0) == "", "other failures retain existing presentation")
Next
$s["failed_worker_phase"] = "PREPARING"
For $state In StringSplit("PREPARING|CONSENT_PREPARE|IDLE|CLEAN|BLOCKED", "|", 2)
    $s["state"] = $state
    Check(_MSW_FailedPrepareHint($s, $rows, 0) == "", "pending and nonfailed excluded")
Next
$s["state"] = "FAILED"
$worker["handle"] = 123
$s["worker"] = $worker
Check(_MSW_FailedPrepareHint($s, $rows, 0) == "", "retained child excluded even if state inconsistent")
$worker["handle"] = 0
$worker["handle"] = "0"
$s["worker"] = $worker
Check(_MSW_FailedPrepareHint($s, $rows, 0) == "", "string handle is not confirmed released")
$worker["handle"] = 0
For $status In StringSplit("RUNNING|UNKNOWN", "|", 2)
    $worker["status"] = $status
    $s["worker"] = $worker
    Check(_MSW_FailedPrepareHint($s, $rows, 0) == "", "unconfirmed child excluded")
Next
$worker["status"] = "EXITED"
For $code In StringSplit("0|1223", "|", 2)
    $worker["exit_code"] = Int($code)
    $s["worker"] = $worker
    Check(_MSW_FailedPrepareHint($s, $rows, 0) == "", "success and UAC cancellation excluded")
Next
Check(Not _MS_FailedPreparation("bad state"), "malformed state excluded")
ConsoleWrite("Failed preparation presentation checks: " & $checks & "; failures: " & $failed & @CRLF)
Exit ($failed > 0 ? 1 : 0)
