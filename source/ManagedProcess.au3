#include-once
#include "WindowsObservation.au3"
#include "PortableProfile.au3"
; Exact process handles from CreateProcessW, not PID/name-based ownership.
; Used by the Manager controller and its worker. Never force-terminate.

Func _MP_New()
    Local $p[]
    $p["handle"] = 0
    $p["pid"] = 0
    $p["image"] = ""
    $p["created"] = ""
    $p["status"] = "BLOCKED"
    $p["exit_code"] = -1
    Return $p
EndFunc

Func _MP_Start($exe, $arguments, $cwd, $home = "", $visible = False)
    Local $p = _MP_New()
    If Not IsString($exe) Or Not IsString($arguments) Or Not IsString($cwd) Then Return $p
    If Not _PP_RootSafe($exe) Or Not _PP_RootSafe($cwd) Or StringLen($arguments) > 4096 Then Return $p
    If StringRegExp($arguments, "[\x00\r\n]") Or Not FileExists($exe) Then Return $p
    If $home <> "" And Not _PP_RootSafe($home) Then Return $p
    Local $si = DllStructCreate("dword cb;ptr reserved;ptr desktop;ptr title;dword x;dword y;dword cx;dword cy;dword xchars;dword ychars;dword fill;dword flags;ushort show;ushort reserved2;ptr reserved3;handle stdin;handle stdout;handle stderr")
    Local $pi = DllStructCreate("handle process;handle thread;dword pid;dword tid")
    DllStructSetData($si, "cb", DllStructGetSize($si))
    DllStructSetData($si, "flags", 1) ; STARTF_USESHOWWINDOW, no inherited handles
    DllStructSetData($si, "show", Number($visible))
    Local $command = '"' & $exe & '" ' & $arguments
    Local $buffer = DllStructCreate("wchar[" & (StringLen($command) + 1) & "]")
    DllStructSetData($buffer, 1, $command)
    Local $previous = EnvGet("VBOX_USER_HOME")
    If $home <> "" Then EnvSet("VBOX_USER_HOME", $home)
    Local $a = DllCall("kernel32.dll", "bool", "CreateProcessW", "wstr", $exe, "struct*", $buffer, _
        "ptr", 0, "ptr", 0, "bool", False, "dword", 0, "ptr", 0, "wstr", $cwd, "struct*", $si, "struct*", $pi)
    Local $callError = @error
    If $home <> "" Then
        If $previous == "" Then
            EnvSet("VBOX_USER_HOME")
        Else
            EnvSet("VBOX_USER_HOME", $previous)
        EndIf
    EndIf
    If $callError Then Return $p
    If Not $a[0] Then Return $p
    $p["handle"] = DllStructGetData($pi, "process")
    $p["pid"] = DllStructGetData($pi, "pid")
    $p["image"] = $exe
    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", DllStructGetData($pi, "thread"))
    ; Retain this very handle even if a fast child exits before observation.
    $p["status"] = "STARTED"
    Local $obs = _WinObsProcessFromHandle($p["handle"])
    If $obs["status"] == "PRESENT" Then
        If StringLower($obs["image"]) <> StringLower($exe) Or $obs["pid"] <> $p["pid"] Then
            $p["status"] = "UNKNOWN"
        Else
            $p["created"] = $obs["created"]
        EndIf
    ElseIf $obs["status"] <> "EXITED" Then
        $p["status"] = "UNKNOWN"
    EndIf
    Return $p
EndFunc

Func _MP_Poll(ByRef $p)
    If Not IsMap($p) Then Return "UNKNOWN"
    If $p["handle"] = 0 Then Return "UNKNOWN"
    Local $a = DllCall("kernel32.dll", "dword", "WaitForSingleObject", "handle", $p["handle"], "dword", 0)
    If @error Then Return "UNKNOWN"
    If $a[0] = 0 Then
        $a = DllCall("kernel32.dll", "bool", "GetExitCodeProcess", "handle", $p["handle"], "dword*", 0)
        If @error Then Return "UNKNOWN"
        If Not $a[0] Then Return "UNKNOWN"
        $p["exit_code"] = $a[2]
        $p["status"] = "EXITED"
        Return "EXITED"
    EndIf
    If $a[0] <> 258 Then Return "UNKNOWN"
    Local $obs = _WinObsProcessFromHandle($p["handle"])
    If $obs["status"] <> "PRESENT" Then Return "UNKNOWN"
    If StringLower($obs["image"]) <> StringLower($p["image"]) Or $obs["pid"] <> $p["pid"] Then Return "UNKNOWN"
    If $p["created"] <> "" And $obs["created"] <> $p["created"] Then Return "UNKNOWN"
    $p["created"] = $obs["created"]
    Return "PRESENT"
EndFunc

Func _MP_Window(ByRef $p)
    If _MP_Poll($p) <> "PRESENT" Then Return HWnd(0)
    Local $windows = WinList()
    For $i = 1 To $windows[0][0]
        Local $hwnd = $windows[$i][1]
        If WinGetProcess($hwnd) = $p["pid"] And BitAND(WinGetState($hwnd), 2) Then
            ; Main top-level window, not its popup/owned dialog.
            Local $owner = DllCall("user32.dll", "hwnd", "GetWindow", "hwnd", $hwnd, "uint", 4)
            If Not @error And $owner[0] = 0 Then Return $hwnd
        EndIf
    Next
    Return HWnd(0)
EndFunc

Func _MP_RequestClose(ByRef $p)
    Local $hwnd = _MP_Window($p)
    If $hwnd = 0 Then Return False
    If _MP_Poll($p) <> "PRESENT" Or WinGetProcess($hwnd) <> $p["pid"] Then Return False
    ; WM_CLOSE is a request; the application can defer/refuse it. No kill.
    Local $a = DllCall("user32.dll", "bool", "PostMessageW", "hwnd", $hwnd, "uint", 0x0010, "wparam", 0, "lparam", 0)
    If @error Then Return False
    Return $a[0] <> 0
EndFunc

Func _MP_Release(ByRef $p)
    If Not IsMap($p) Or $p["handle"] = 0 Then Return False
    Local $h = $p["handle"]
    $p["handle"] = 0
    Local $a = DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
    If @error Then Return False
    Return $a[0] <> 0
EndFunc
