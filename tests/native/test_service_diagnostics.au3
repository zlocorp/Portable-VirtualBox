#include "..\..\source\HostDiagnostics.au3"
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL service diagnostics: " & $label & @CRLF)
    EndIf
EndFunc
Local $states[7] = ["STOPPED", "START_PENDING", "STOP_PENDING", "RUNNING", "CONTINUE_PENDING", "PAUSE_PENDING", "PAUSED"]
For $i = 1 To 7
    Local $r = _WinObsResult("service", "PRESENT")
    $r["state"] = $i
    Check(_PortableServiceState($r) == $states[$i - 1], "native state " & $i)
Next
Local $absent = _WinObsError("service", "open", 1060)
Check(_PortableServiceState($absent) == "ABSENT", "documented missing service")
Local $denied = _WinObsError("service", "open", 5)
Check(_PortableServiceState($denied) == "UNKNOWN", "denied is not absent")
Local $zero = _WinObsError("service", "open", 0)
Check(_PortableServiceState($zero) == "UNKNOWN", "failed call with error zero is not absent")
$absent["error"] = 5
Check(_PortableServiceState($absent) == "UNKNOWN", "contradictory absence rejected")
$r["state"] = 8
Check(_PortableServiceState($r) == "UNKNOWN", "unsupported state remains unknown")
$r["state"] = "4"
Check(_PortableServiceState($r) == "UNKNOWN", "string state not coerced")
$r = _WinObsResult("process", "PRESENT")
$r["state"] = 4
Check(_PortableServiceState($r) == "UNKNOWN", "wrong observation kind")
Check(_PortableServiceState("RUNNING") == "UNKNOWN", "malformed observation")
Local $rows[2], $known = _WinObsResult("service", "PRESENT")
$known["state"] = 4
$known["name"] = "VBoxSup"
$known["image"] = "C:\PrivateUser\Secret\VBoxSup.sys"
$known["account"] = "PrivateUser"
$rows[0] = $known
$denied["name"] = "VBoxSDS"
$rows[1] = $denied
Check(_PortableServiceCount($rows) = -1, "one unknown row prevents known count")
Local $en = _PortableServiceText($rows, "en"), $ru = _PortableServiceText($rows, "ru")
Check(StringInStr($en, "RUNNING") And StringInStr($en, "UNKNOWN") And StringInStr($en, "Win32=5"), "statuses and exact diagnostic error")
Check(StringInStr($ru, "РАБОТАЕТ") And StringInStr($ru, "НЕИЗВЕСТНО"), "Russian states")
Check(Not StringInStr($en & $ru, "PrivateUser"), "paths and accounts never disclosed")
Check(StringInStr($en, "not verified") And StringInStr($ru, "не проверено"), "observation is not ownership")
$rows[1] = _WinObsError("service", "open", 1060)
Check(_PortableServiceCount($rows) = 1, "known count from same snapshot")
; Read only: exercises real SCM, never creates/starts/deletes a service.
Check(_PortableProcessRole("VBoxManagePortable.exe") == "background", "portable CLI blocks backup/cleanup during validation too")
Local $actual = _PortableServiceCollect()
Check(IsArray($actual) And UBound($actual) = 10, "full VBox service inventory")
Local $report = _PortableServiceText($actual, "en")
Check(StringInStr($report, "VBoxSup") And StringInStr($report, "VBoxSDS"), "actual inventory uses stable service names")
ConsoleWrite("Native service diagnostics assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
