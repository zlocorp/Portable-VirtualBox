#include-once
; Included by WindowsObservation.au3. SCM query rights only.
; Service snapshots are not atomic ownership proofs or cleanup capabilities.

Func _WinObsCloseService($h)
    Local $a = DllCall("advapi32.dll", "bool", "CloseServiceHandle", "handle", $h)
    If @error Then Return False
    Return $a[0] <> 0
EndFunc

; Validate every OS-returned string pointer against its owning query buffer.
; MULTI_SZ dependencies are kept as exact hex bytes, including both terminators.
Func _WinObsBufferString(ByRef $buffer, $p, $multi = False)
    If $p = 0 Then Return ""
    Local $offset = Number($p) - Number(DllStructGetPtr($buffer))
    Local $size = DllStructGetSize($buffer)
    If $offset < 0 Or $offset >= $size Or Mod($offset, 2) <> 0 Then Return SetError(1, 0, "")
    Local $count = Int(($size - $offset) / 2)
    If $count < 1 Then Return SetError(1, 0, "")
    Local $chars = DllStructCreate("ushort[" & $count & "]", $p)
    If @error Then Return SetError(1, 0, "")
    For $i = 1 To $count
        If DllStructGetData($chars, 1, $i) = 0 Then
            If Not $multi Then
                Local $text = DllStructCreate("wchar[" & $i & "]", $p)
                Return DllStructGetData($text, 1)
            EndIf
            If $i < $count And DllStructGetData($chars, 1, $i + 1) = 0 Then
                Local $bytes = DllStructCreate("byte[" & (($i + 1) * 2) & "]", $p)
                Return String(DllStructGetData($bytes, 1))
            EndIf
        EndIf
    Next
    Return SetError(1, 0, "")
EndFunc

Func _WinObsServiceRead($h, $name)
    ; Microsoft documents an 8 KiB maximum for QUERY_SERVICE_CONFIG.
    Local $buffer = DllStructCreate("byte[8192]")
    Local $a = DllCall("advapi32.dll", "bool", "QueryServiceConfigW", "handle", $h, _
        "struct*", $buffer, "dword", 8192, "dword*", 0)
    If @error Then Return _WinObsError("service", "config", -1)
    If Not $a[0] Then Return _WinObsError("service", "config", _WinObsLastError())
    Local $cfg = DllStructCreate("dword Type;dword Start;dword Error;ptr Image;ptr Group;dword Tag;ptr Dependencies;ptr Account;ptr Display", DllStructGetPtr($buffer))
    If @error Then Return _WinObsError("service", "config-buffer", -1)
    Local $r = _WinObsResult("service", "PRESENT")
    $r["name"] = $name
    $r["type"] = DllStructGetData($cfg, "Type")
    $r["start"] = DllStructGetData($cfg, "Start")
    $r["error_control"] = DllStructGetData($cfg, "Error")
    $r["tag"] = DllStructGetData($cfg, "Tag")
    Local $fields[5] = ["Image", "Group", "Dependencies", "Account", "Display"]
    Local $out[5] = ["image", "group", "dependencies", "account", "display"]
    For $i = 0 To 4
        Local $s = _WinObsBufferString($buffer, DllStructGetData($cfg, $fields[$i]), $i = 2)
        If @error Then Return _WinObsError("service", "config-string", -1)
        $r[$out[$i]] = $s
    Next
    If $r["image"] == "" Then Return _WinObsError("service", "empty-image", -1)
    Local $status = DllStructCreate("dword Type;dword State;dword Controls;dword Win32Exit;dword ServiceExit;dword Checkpoint;dword WaitHint;dword PID;dword Flags")
    $a = DllCall("advapi32.dll", "bool", "QueryServiceStatusEx", "handle", $h, "int", 0, _
        "struct*", $status, "dword", DllStructGetSize($status), "dword*", 0)
    If @error Then Return _WinObsError("service", "status", -1)
    If Not $a[0] Then Return _WinObsError("service", "status", _WinObsLastError())
    If DllStructGetData($status, "Type") <> $r["type"] Then Return _WinObsError("service", "changed-type", -1)
    $r["state"] = DllStructGetData($status, "State")
    If $r["state"] < 1 Or $r["state"] > 7 Then Return _WinObsError("service", "invalid-state", -1)
    ; A stopped or transitioning service PID is not reliable identity evidence.
    If $r["state"] = 4 Or $r["state"] = 7 Then $r["pid"] = DllStructGetData($status, "PID")
    $r["checkpoint"] = DllStructGetData($status, "Checkpoint")
    $r["wait_hint"] = DllStructGetData($status, "WaitHint")
    Return $r
EndFunc

Func _WinObsServiceStable(ByRef $first, ByRef $second)
    If Not IsMap($first) Or Not IsMap($second) Then Return False
    Local $fields = StringSplit("kind,status,error,name,type,start,error_control,tag,image,group,dependencies,account,display,state,pid,checkpoint,wait_hint", ",", 2)
    For $i = 0 To UBound($fields) - 1
        Local $key = $fields[$i]
        If Not MapExists($first, $key) Or Not MapExists($second, $key) Then Return False
        If Not ($first[$key] == $second[$key]) Then Return False
    Next
    If Not ($first["kind"] == "service") Or Not ($first["status"] == "PRESENT") Or $first["error"] <> 0 Then Return False
    Return $first["state"] = 1 Or $first["state"] = 4 Or $first["state"] = 7
EndFunc

Func _WinObsService($name)
    If Not IsString($name) Or StringLen($name) < 1 Or StringLen($name) > 256 Then Return _WinObsError("service", "name", 123)
    If StringRegExp($name, "[\\/\x00-\x1F]") Then Return _WinObsError("service", "name", 123)
    Local $a = DllCall("advapi32.dll", "handle", "OpenSCManagerW", "ptr", 0, "ptr", 0, "dword", 0x0001)
    If @error Then Return _WinObsError("service", "manager", -1)
    If $a[0] = 0 Then Return _WinObsError("service", "manager", _WinObsLastError())
    Local $manager = $a[0]
    ; SERVICE_QUERY_CONFIG (1) | SERVICE_QUERY_STATUS (4).
    $a = DllCall("advapi32.dll", "handle", "OpenServiceW", "handle", $manager, "wstr", $name, "dword", 0x0005)
    Local $dllerror = @error
    If $dllerror Or $a[0] = 0 Then
        Local $error = -1
        If Not $dllerror Then $error = _WinObsLastError()
        _WinObsCloseService($manager)
        Return _WinObsError("service", "open", $error)
    EndIf
    Local $service = $a[0]
    Local $first = _WinObsServiceRead($service, $name)
    Local $second = _WinObsServiceRead($service, $name)
    Local $closedService = _WinObsCloseService($service)
    Local $closedManager = _WinObsCloseService($manager)
    If Not $closedService Or Not $closedManager Then Return _WinObsError("service", "close", -1)
    If Not ($first["status"] == "PRESENT") Then Return $first
    If Not ($second["status"] == "PRESENT") Then Return $second
    If Not _WinObsServiceStable($first, $second) Then Return _WinObsError("service", "changed-or-pending", -1)
    Return $second
EndFunc
