#include-once
; Included by WindowsObservation.au3. Query handles never grant termination rights.
; Tokens are process-local, monotonic and never re-used. Do not persist them.
Global $g_WinObsProcesses[], $g_WinObsNextToken = 1

Func _WinObsProcessFromHandle($h)
    Local $r = _WinObsResult("process")
    Local $a = DllCall("kernel32.dll", "dword", "WaitForSingleObject", "handle", $h, "dword", 0)
    If @error Then Return _WinObsError("process", "wait", -1)
    If $a[0] = 0 Then Return _WinObsResult("process", "EXITED")
    If $a[0] <> 258 Then Return _WinObsError("process", "wait", _WinObsLastError())
    $a = DllCall("kernel32.dll", "dword", "GetProcessId", "handle", $h)
    If @error Then Return _WinObsError("process", "pid", -1)
    If $a[0] = 0 Then Return _WinObsError("process", "pid", _WinObsLastError())
    $r["pid"] = $a[0]
    Local $created = DllStructCreate("dword Low;dword High")
    Local $exited = DllStructCreate("dword Low;dword High")
    Local $kernel = DllStructCreate("dword Low;dword High")
    Local $user = DllStructCreate("dword Low;dword High")
    $a = DllCall("kernel32.dll", "bool", "GetProcessTimes", "handle", $h, _
        "struct*", $created, "struct*", $exited, "struct*", $kernel, "struct*", $user)
    If @error Then Return _WinObsError("process", "times", -1)
    If Not $a[0] Then Return _WinObsError("process", "times", _WinObsLastError())
    ; Never convert the 64-bit FILETIME through a floating point timestamp.
    $r["created"] = Hex(DllStructGetData($created, "High"), 8) & Hex(DllStructGetData($created, "Low"), 8)
    Local $image = DllStructCreate("wchar[32768]")
    $a = DllCall("kernel32.dll", "bool", "QueryFullProcessImageNameW", "handle", $h, _
        "dword", 0, "struct*", $image, "dword*", 32768)
    If @error Then Return _WinObsError("process", "image", -1)
    If Not $a[0] Then Return _WinObsError("process", "image", _WinObsLastError())
    $r["image"] = DllStructGetData($image, 1)
    If $a[4] < 1 Or $a[4] >= 32768 Or StringLen($r["image"]) <> $a[4] Then Return _WinObsError("process", "image-size", -1)
    $a = DllCall("kernel32.dll", "dword", "WaitForSingleObject", "handle", $h, "dword", 0)
    If @error Then Return _WinObsError("process", "wait", -1)
    If $a[0] = 0 Then
        $r["status"] = "EXITED"
    ElseIf $a[0] = 258 Then
        $r["status"] = "PRESENT"
    Else
        Return _WinObsError("process", "wait", _WinObsLastError())
    EndIf
    Return $r
EndFunc

Func _WinObsProcessOpen($pid)
    If Not IsInt($pid) Or $pid < 1 Or $pid > 0xFFFFFFFF Then Return SetError(1, 87, 0)
    If UBound(MapKeys($g_WinObsProcesses)) >= 128 Or $g_WinObsNextToken >= 0x7FFFFFFF Then Return SetError(1, 4, 0)
    ; SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION. No inheritance or mutation.
    Local $a = DllCall("kernel32.dll", "handle", "OpenProcess", "dword", 0x00101000, "bool", False, "dword", $pid)
    If @error Then Return SetError(1, -1, 0)
    If $a[0] = 0 Then Return SetError(1, _WinObsLastError(), 0)
    Local $h = $a[0], $initial = _WinObsProcessFromHandle($h)
    If Not ($initial["status"] == "PRESENT") Or $initial["pid"] <> $pid Then
        DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
        Return SetError(1, $initial["error"], 0)
    EndIf
    Local $entry[]
    $entry["handle"] = $h
    $entry["initial"] = $initial
    Local $token = $g_WinObsNextToken
    $g_WinObsNextToken += 1
    $g_WinObsProcesses[$token] = $entry
    Return $token
EndFunc

Func _WinObsProcessRead($token)
    If Not IsInt($token) Or Not MapExists($g_WinObsProcesses, $token) Then Return _WinObsError("process", "token", 6)
    Local $entry = $g_WinObsProcesses[$token], $initial = $entry["initial"]
    Local $r = _WinObsProcessFromHandle($entry["handle"])
    If Not ($r["status"] == "PRESENT") Then Return $r
    If Not _PortableProcessOwned($r["pid"], $initial["pid"], $r["created"], $initial["created"], _
        $r["image"], $initial["image"], True) Then Return _WinObsError("process", "changed-identity", -1)
    Return $r
EndFunc

; Identity match only, not ownership. Creation evidence is required separately.
Func _WinObsProcessMatches($token, ByRef $reference)
    If Not IsMap($reference) Then Return False
    Local $fields = StringSplit("kind,status,pid,created,image", ",", 2)
    For $i = 0 To UBound($fields) - 1
        If Not MapExists($reference, $fields[$i]) Then Return False
    Next
    If Not ($reference["kind"] == "process") Or Not ($reference["status"] == "PRESENT") Then Return False
    Local $r = _WinObsProcessRead($token)
    If Not ($r["status"] == "PRESENT") Then Return False
    Return _PortableProcessOwned($r["pid"], $reference["pid"], $r["created"], $reference["created"], _
        $r["image"], $reference["image"], True)
EndFunc

Func _WinObsProcessClose($token)
    If Not IsInt($token) Or Not MapExists($g_WinObsProcesses, $token) Then Return False
    Local $entry = $g_WinObsProcesses[$token]
    ; Invalidate even if close fails: a stale token must never target a reused handle.
    MapRemove($g_WinObsProcesses, $token)
    Local $a = DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $entry["handle"])
    If @error Then Return False
    Return $a[0] <> 0
EndFunc
