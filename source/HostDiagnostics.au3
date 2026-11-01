#include-once
#include "HostPreflight.au3"
#include "LauncherI18n.au3"
; Read-only Windows inventory. No secret paths, usernames or service accounts.

; Per-service presentation inspired by Deac2 NewMenuTest c11f76a8.
; Independent adaptation: existing query-only WinObs, no COM activation,
; elevation, service control, image/account output or ownership inference.
Func _PortableServiceState($r)
    If Not IsMap($r) Then Return "UNKNOWN"
    Local $keys[5] = ["kind", "status", "state", "error", "stage"]
    For $key In $keys
        If Not MapExists($r, $key) Then Return "UNKNOWN"
    Next
    If $r["kind"] <> "service" Or Not IsInt($r["error"]) Then Return "UNKNOWN"
    If $r["status"] == "ABSENT" And $r["error"] = 1060 And $r["stage"] == "open" Then Return "ABSENT"
    If $r["status"] <> "PRESENT" Or $r["error"] <> 0 Or Not IsInt($r["state"]) Then Return "UNKNOWN"
    Local $states[7] = ["STOPPED", "START_PENDING", "STOP_PENDING", "RUNNING", "CONTINUE_PENDING", "PAUSE_PENDING", "PAUSED"]
    If $r["state"] < 1 Or $r["state"] > 7 Then Return "UNKNOWN"
    Return $states[$r["state"] - 1]
EndFunc

Func _PortableServiceCollect()
    Local $names = _PortableServiceNames(), $rows[UBound($names)]
    For $i = 0 To UBound($names) - 1
        Local $r = _WinObsServiceSnapshot($names[$i])
        $r["name"] = $names[$i]
        $rows[$i] = $r
    Next
    Return $rows
EndFunc

Func _PortableServiceCount(ByRef $rows)
    If Not IsArray($rows) Then Return -1
    Local $count = 0
    For $r In $rows
        Local $state = _PortableServiceState($r)
        If $state == "UNKNOWN" Then Return -1
        If $state <> "ABSENT" Then $count += 1
    Next
    Return $count
EndFunc

Func _PortableServiceText(ByRef $rows, $language = "")
    If $language == "" Then $language = _LI_Language()
    Local $ru = $language == "ru"
    Local $text = "Service status (read-only; ownership not verified)" & @CRLF
    If $ru Then $text = "Состояние служб (только чтение; владение не проверено)" & @CRLF
    If Not IsArray($rows) Then Return $text & ($ru ? "НЕИЗВЕСТНО" : "UNKNOWN") & @CRLF
    For $r In $rows
        Local $state = _PortableServiceState($r), $name = "?", $error = -1
        If IsMap($r) Then
            If MapExists($r, "name") Then $name = _PortableServiceDisplayName($r["name"])
            If MapExists($r, "error") And IsInt($r["error"]) Then $error = $r["error"]
        EndIf
        If $ru Then
            Switch $state
                Case "ABSENT"
                    $state = "ОТСУТСТВУЕТ"
                Case "STOPPED"
                    $state = "ОСТАНОВЛЕНА"
                Case "RUNNING"
                    $state = "РАБОТАЕТ"
                Case "PAUSED"
                    $state = "ПРИОСТАНОВЛЕНА"
                Case "START_PENDING"
                    $state = "ЗАПУСКАЕТСЯ"
                Case "STOP_PENDING"
                    $state = "ОСТАНАВЛИВАЕТСЯ"
                Case "CONTINUE_PENDING"
                    $state = "ВОЗОБНОВЛЯЕТСЯ"
                Case "PAUSE_PENDING"
                    $state = "ПРИОСТАНАВЛИВАЕТСЯ"
                Case Else
                    $state = "НЕИЗВЕСТНО"
            EndSwitch
        EndIf
        $text &= StringFormat("%-15s %-20s", $name, $state)
        If $error <> 0 Then $text &= " Win32=" & $error
        $text &= @CRLF
    Next
    Return $text
EndFunc

Func _PortableServiceDisplayName($value)
    If Not IsString($value) Then Return "?"
    Local $names = _PortableServiceNames()
    For $name In $names
        If $value == $name Then Return $name
    Next
    Return "?"
EndFunc

; Serialize this already-collected ordered snapshot, never probe a second
; time or export raw paths/accounts. The schema does not depend on UI locale.
Func _PortableServiceJson(ByRef $rows)
    If Not IsArray($rows) Then Return ""
    If UBound($rows, 0) <> 1 Then Return ""
    Local $names = _PortableServiceNames()
    If UBound($rows) <> UBound($names) Then Return ""
    Local $json = '{"schema":1,"services":[', $unknown = False
    For $i = 0 To UBound($names) - 1
        Local $r = $rows[$i]
        If Not IsMap($r) Then Return ""
        If Not MapExists($r, "name") Then Return ""
        If Not ($r["name"] == $names[$i]) Then Return ""
        Local $state = _PortableServiceState($r), $observation = "PRESENT", $error = -1, $ownership = "UNVERIFIED"
        If $state == "ABSENT" Then
            $observation = "ABSENT"
            $ownership = "NOT_APPLICABLE"
        ElseIf $state == "UNKNOWN" Then
            $observation = "UNKNOWN"
            $unknown = True
        EndIf
        If MapExists($r, "error") Then
            If IsInt($r["error"]) Then $error = $r["error"]
        EndIf
        If $i > 0 Then $json &= ","
        $json &= '{"name":"' & $names[$i] & '","observation":"' & $observation & _
            '","state":"' & $state & '","win32_error":' & $error & _
            ',"ownership":"' & $ownership & '"}'
    Next
    Return $json & '],"exit_code":' & ($unknown ? 4 : 0) & '}'
EndFunc

; Exit 0 means known observations, not host readiness or cleanup permission.
Func _PortableServiceWrite($json = False)
    Local $rows = _PortableServiceCollect(), $text
    If $json Then
        $text = _PortableServiceJson($rows)
        If $text == "" Then Return 4
        $text &= @CRLF
    Else
        $text = _PortableServiceText($rows)
    EndIf
    _LI_Write($text)
    If _PortableServiceCount($rows) < 0 Then Return 4
    Return 0
EndFunc

Func _PortableDiagnosticCollect()
    Local $os = _WinObsOS(), $installed = _WinObsInstallation()
    Local $serviceRows = _PortableServiceCollect()
    Local $services = _PortableServiceCount($serviceRows), $activity = _PortableActivityCollect()
    Local $processes = $activity["total"]
    Local $report[]
    Local $s = _LI("diag.header") & @CRLF
    $s &= _LI("diag.windows") & _LI_Observation("os", $os["status"]) & @CRLF
    If $os["status"] == "PRESENT" Then
        $s &= _LI("diag.build") & $os["build"] & @CRLF
        $s &= _LI("diag.product_type") & _LI_ProductType($os["product_type"]) & @CRLF
    Else
        $s &= _LI("diag.build") & _LI("diag.unknown") & @CRLF
        $s &= _LI("diag.product_type") & _LI("diag.unknown") & @CRLF
    EndIf
    $s &= _LI("diag.arch") & @OSArch & @CRLF
    $s &= _LI("diag.installed") & _LI_Observation("installation", $installed["status"]) & @CRLF
    If $services < 0 Then
        $s &= _LI("diag.services_unknown") & @CRLF
    Else
        $s &= _LI("diag.services") & $services & @CRLF
    EndIf
    If $processes < 0 Then
        $s &= _LI("diag.processes_unknown") & @CRLF
    Else
        $s &= _LI("diag.processes") & $processes & @CRLF
        $s &= _LI("diag.manager_processes") & $activity["manager"] & @CRLF
        $s &= _LI("diag.guest_processes") & $activity["guest"] & @CRLF
        $s &= _LI("diag.background_processes") & $activity["background"] & @CRLF
    EndIf
    $s &= @CRLF & _PortableServiceText($serviceRows)
    $s &= _LI("diag.runtime") & @CRLF
    $report["text"] = $s
    If Not ($os["status"] == "PRESENT") Or $installed["status"] == "UNKNOWN" Or $services < 0 Or $processes < 0 Then
        $report["exit_code"] = 4
    Else
        $report["exit_code"] = 0
    EndIf
    Return $report
EndFunc

Func _PortableDiagnosticWrite()
    Local $report = _PortableDiagnosticCollect()
    _LI_Write($report["text"])
    Return $report["exit_code"]
EndFunc
