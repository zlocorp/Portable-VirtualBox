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

; Test the SAME selection function used after native query/handle cleanup,
; not only the label mapper. Pending observations must remain display-only.
Local $stable = _WinObsService("RpcSs")
Check($stable["status"] == "PRESENT", "real stable service fixture")
For $i = 1 To 7
    Local $first = $stable, $second
    $first["state"] = $i
    $second = $first
    Local $snapshot = _WinObsServiceResolve($first, $second, False)
    Check(_PortableServiceState($snapshot) == $states[$i - 1], "query result preserves state " & $i)
    Local $strict = _WinObsServiceResolve($first, $second, True)
    If $i = 1 Or $i = 4 Or $i = 7 Then
        Check($strict["status"] == "PRESENT", "strict stable state " & $i)
    Else
        Check($strict["status"] == "UNKNOWN" And $strict["stage"] == "changed-or-pending", "pending never authorizes strict use " & $i)
    EndIf
Next
$first = $stable
$second = $stable
$second["checkpoint"] += 1
$strict = _WinObsServiceResolve($first, $second, True)
Check($strict["status"] == "UNKNOWN", "changed stable observation still refused")
$first = _WinObsError("service", "status", 5)
$snapshot = _WinObsServiceResolve($first, $second, False)
Check($snapshot["status"] == "UNKNOWN" And $snapshot["error"] = 5, "snapshot preserves query failure")
$first = $stable
$second = _WinObsError("service", "status", 5)
$strict = _WinObsServiceResolve($first, $second, True)
Check($strict["status"] == "UNKNOWN" And $strict["error"] = 5, "strict second read failure retained")
Local $missingSnapshot = _WinObsServiceSnapshot("PVBoxSnapshotMissing_" & @AutoItPID)
Check($missingSnapshot["status"] == "ABSENT" And $missingSnapshot["error"] = 1060, "real missing snapshot")

Local $names = _PortableServiceNames(), $jsonRows[UBound($names)]
For $i = 0 To UBound($names) - 1
    Local $entry = _WinObsError("service", "open", 1060)
    $entry["name"] = $names[$i]
    $jsonRows[$i] = $entry
Next
_LI_Set("ru")
Local $jsonRu = _PortableServiceJson($jsonRows)
_LI_Set("en")
Check($jsonRu == _PortableServiceJson($jsonRows), "JSON independent of UI language")
Check(StringInStr($jsonRu, '"schema":1') And StringInStr($jsonRu, '"exit_code":0'), "known absence is report success only")
$entry = $stable
$entry["name"] = $names[0]
$entry["state"] = 2
$entry["image"] = "C:\PrivateUser\Secret.exe"
$entry["account"] = "PrivateUser"
$jsonRows[0] = $entry
$entry = _WinObsError("service", "open", 5)
$entry["name"] = $names[1]
$jsonRows[1] = $entry
Local $json = _PortableServiceJson($jsonRows)
Check(StringInStr($json, '"state":"START_PENDING"'), "JSON preserves pending observation")
Check(StringInStr($json, '"state":"UNKNOWN","win32_error":5'), "JSON exact access denial")
Check(StringInStr($json, '"ownership":"UNVERIFIED"') And StringInStr($json, '"ownership":"NOT_APPLICABLE"'), "explicit non-authoritative ownership")
Check(StringInStr($json, '"exit_code":4') And Not StringInStr($json, "PrivateUser"), "JSON unknown exit and privacy")
$entry["error"] = "5"
$jsonRows[1] = $entry
Check(StringInStr(_PortableServiceJson($jsonRows), '"win32_error":-1'), "untyped error not serialized")
$entry["name"] = "VBoxSecretInjected"
$jsonRows[1] = $entry
Check(_PortableServiceJson($jsonRows) == "", "out-of-order or unapproved name rejected")
Check(Not StringInStr(_PortableServiceText($jsonRows), "VBoxSecretInjected"), "text uses same fixed name allowlist")
Local $badShape[10][2], $notRows = 0, $shortRows[2]
Check(_PortableServiceJson($badShape) == "", "multidimensional JSON input rejected")
Check(_PortableServiceJson($notRows) == "", "non-array JSON input rejected")
Check(_PortableServiceJson($shortRows) == "", "incomplete inventory rejected")

ConsoleWrite("Native service diagnostics assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
