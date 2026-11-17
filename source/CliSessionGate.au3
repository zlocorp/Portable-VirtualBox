#include-once
#include "WindowsObservation.au3"
; Same-user command/cleanup coordination, NOT privileged ownership authority.
; Only the controller creates fresh objects; clients must open existing ones.
; An abandoned command never becomes a successful cleanup permit.
Func _CG_New()
    Local $g[]
    $g["handle"] = 0
    $g["ready"] = 0
    $g["held"] = False
    $g["poisoned"] = False
    Return $g
EndFunc

Func _CG_Name($pid, $cycle)
    If Not IsInt($pid) Or Not IsInt($cycle) Then Return ""
    If $pid < 1 Or $pid > 999999999 Or $cycle < 1 Or $cycle > 999 Then Return ""
    Return "Local\PortableVirtualBox.Cli." & $pid & "." & $cycle
EndFunc

Func _CG_StateAllows($state)
    Return IsString($state) And ($state == "MANAGER_OPEN" Or $state == "WAIT_GUESTS" Or _
        $state == "WAIT_BACKGROUND" Or $state == "CLEANUP_DECLINED")
EndFunc

Func _CG_Create($pid, $cycle)
    Local $g = _CG_New(), $name = _CG_Name($pid, $cycle)
    If $name == "" Then Return $g
    DllCall($g_WinObsKernel32, "none", "SetLastError", "dword", 0)
    Local $m = DllCall($g_WinObsKernel32, "handle", "CreateMutexW", "ptr", 0, "bool", True, "wstr", $name)
    Local $transport = @error, $error = _WinObsLastError()
    If $transport Or Not IsArray($m) Then Return $g
    If $m[0] = 0 Then Return $g
    If $error <> 0 Then
        DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $m[0])
        Return $g
    EndIf
    $g["handle"] = $m[0]
    $g["held"] = True
    DllCall($g_WinObsKernel32, "none", "SetLastError", "dword", 0)
    Local $e = DllCall($g_WinObsKernel32, "handle", "CreateEventW", "ptr", 0, "bool", True, "bool", False, "wstr", $name & ".Ready")
    $transport = @error
    $error = _WinObsLastError()
    If Not $transport And IsArray($e) Then
        If $e[0] <> 0 And $error = 0 Then
            $g["ready"] = $e[0]
            Return $g
        EndIf
        If $e[0] <> 0 Then DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $e[0])
    EndIf
    _CG_Close($g)
    Return $g
EndFunc

Func _CG_SetReady(ByRef $g, $ready)
    If Not IsBool($ready) Or $g["ready"] = 0 Then Return False
    If $ready And $g["poisoned"] Then Return False
    Local $fn = "ResetEvent"
    If $ready Then $fn = "SetEvent"
    Local $a = DllCall($g_WinObsKernel32, "bool", $fn, "handle", $g["ready"])
    Return Not @error And IsArray($a) And $a[0] <> 0
EndFunc

Func _CG_Acquire(ByRef $g)
    If $g["handle"] = 0 Or $g["poisoned"] Then Return "UNKNOWN"
    If $g["held"] Then Return "HELD"
    Local $a = DllCall($g_WinObsKernel32, "dword", "WaitForSingleObject", "handle", $g["handle"], "dword", 0)
    If @error Or Not IsArray($a) Then Return "UNKNOWN"
    Switch $a[0]
        Case 0
            $g["held"] = True
            Return "HELD"
        Case 258
            Return "BUSY"
        Case 128
            $g["held"] = True
            $g["poisoned"] = True
            _CG_SetReady($g, False)
    EndSwitch
    Return "UNKNOWN"
EndFunc

Func _CG_Release(ByRef $g)
    If $g["handle"] = 0 Or $g["poisoned"] Then Return False
    If Not $g["held"] Then Return True
    Local $a = DllCall($g_WinObsKernel32, "bool", "ReleaseMutex", "handle", $g["handle"])
    If @error Or Not IsArray($a) Then Return False
    If $a[0] = 0 Then Return False
    $g["held"] = False
    Return True
EndFunc

Func _CG_Close(ByRef $g)
    If $g["ready"] <> 0 Then
        _CG_SetReady($g, False)
        DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $g["ready"])
    EndIf
    If $g["handle"] <> 0 Then
        If $g["held"] Then DllCall($g_WinObsKernel32, "bool", "ReleaseMutex", "handle", $g["handle"])
        DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $g["handle"])
    EndIf
    $g = _CG_New()
EndFunc
