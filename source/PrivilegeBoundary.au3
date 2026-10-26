#include-once
#include "ManagedProcess.au3"
; Explicit, non-shipping Windows workstation candidate mode is only entered
; through --alpha-runtime or the corresponding same-EXE elevation worker.
Global $g_MS_AlphaMode = False
; Fixed compiled helper only. ShellExecuteExW runas returns the process handle;
; do not fall back to shell commands, scheduled tasks or direct elevated effects.
; In CI it is wired to the exact compiled main EXE too; production effects remain disabled.

Func _PB_Outcome($ok, $error, $handle)
    If Not $ok And $error = 1223 Then Return "CANCELLED"
    If Not $ok Or $handle = 0 Then Return "FAILED"
    Return "STARTED"
EndFunc

Func _PB_Medium()
    If IsAdmin() Then Return False
    Local $t = DllCall("advapi32.dll", "bool", "OpenProcessToken", "handle", Ptr(-1), "dword", 8, "handle*", 0)
    If @error Or Not $t[0] Then Return False
    Local $token = $t[3], $buffer = DllStructCreate("byte[256]")
    Local $r = DllCall("advapi32.dll", "bool", "GetTokenInformation", "handle", $token, "int", 25, "struct*", $buffer, "dword", 256, "dword*", 0)
    Local $ok = Not @error
    If $ok Then $ok = $r[0] <> 0
    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $token)
    If Not $ok Then Return False
    Local $label = DllStructCreate("ptr sid;dword attr", DllStructGetPtr($buffer))
    Local $sid = DllStructGetData($label, "sid")
    $r = DllCall("advapi32.dll", "ptr", "GetSidSubAuthorityCount", "ptr", $sid)
    If @error Or $r[0] = 0 Then Return False
    Local $count = DllStructGetData(DllStructCreate("byte", $r[0]), 1)
    If $count < 1 Then Return False
    $r = DllCall("advapi32.dll", "ptr", "GetSidSubAuthority", "ptr", $sid, "dword", $count - 1)
    If @error Or $r[0] = 0 Then Return False
    Local $rid = DllStructGetData(DllStructCreate("dword", $r[0]), 1)
    Return $rid >= 8192 And $rid < 12288
EndFunc

Func _PB_HelperName()
    If $g_MS_AlphaMode Then Return "Portable-VirtualBox-Helper-Alpha.exe"
    Return "Portable-VirtualBox-Helper-Test.exe"
EndFunc

Func _PB_WorkerVerb()
    If $g_MS_AlphaMode Then Return "--alpha-elevation-worker"
    Return "--elevation-worker"
EndFunc

Func _PB_Start($root, $action, $cycle)
    Local $p = _MP_New()
    If Not _PB_Medium() Or Not _PP_RootSafe($root) Or StringLower($root) <> StringLower(@ScriptDir) Then Return $p
    If $action <> "Prepare" And $action <> "Finish" Then Return $p
    If Not IsInt($cycle) Or $cycle < 1 Or $cycle > 999 Then Return $p
    If Not FileExists($root & "\" & _PB_HelperName()) Then Return $p
    ; A same-binary medium worker waits for Windows consent off the GUI thread.
    Return _MP_Start(@ScriptFullPath, _PB_WorkerVerb() & " " & $action & " " & @AutoItPID & " " & $cycle, $root)
EndFunc

; Recovery has an explicit former PID and cycle only, never a path. The
; elevated helper validates protected receipts and the departed owner.
Func _PB_StartRecover($root, $formerPid, $cycle)
    Local $p = _MP_New()
    If Not _PB_Medium() Or Not _PP_RootSafe($root) Or StringLower($root) <> StringLower(@ScriptDir) Then Return $p
    If Not IsInt($formerPid) Or $formerPid < 1 Or $formerPid = @AutoItPID Then Return $p
    If Not IsInt($cycle) Or $cycle < 1 Or $cycle > 999 Then Return $p
    If Not FileExists($root & "\" & _PB_HelperName()) Then Return $p
    Return _MP_Start(@ScriptFullPath, _PB_WorkerVerb() & " Recover " & @AutoItPID & " " & $formerPid & " " & $cycle, $root)
EndFunc

Func _PB_RunRequest($root, $action, $controller, $cycle, $formerPid = 0)
    If Not _PB_Medium() Or Not IsInt($controller) Or $controller < 1 Or $controller = @AutoItPID Then Return 64
    If $action <> "Prepare" And $action <> "Finish" And $action <> "Recover" Then Return 64
    If Not IsInt($cycle) Or $cycle < 1 Or $cycle > 999 Then Return 64
    If $action == "Recover" And (Not IsInt($formerPid) Or $formerPid < 1 Or $formerPid == $controller) Then Return 64
    Local $token = _WinObsProcessOpen($controller)
    If $token = 0 Then Return 70
    Local $parent = _WinObsProcessRead($token)
    If $parent["status"] <> "PRESENT" Or StringLower($parent["image"]) <> StringLower(@ScriptFullPath) Then
        _WinObsProcessClose($token)
        Return 70
    EndIf
    Local $init = DllCall("ole32.dll", "long", "CoInitializeEx", "ptr", 0, "dword", 2)
    If @error Then
        _WinObsProcessClose($token)
        Return 70
    EndIf
    If $init[0] <> 0 And $init[0] <> 1 Then
        _WinObsProcessClose($token)
        Return 70
    EndIf
    Local $p = _PB_RequestBlocking($root, $action, $controller, $cycle, $formerPid), $result = 70
    If $p["status"] == "CANCELLED" Then
        $result = 1223
    ElseIf $p["status"] == "STARTED" Then
        ; The fixed elevated helper may still be performing a system effect
        ; after 180 seconds. Do NOT detach on elapsed time or controller loss:
        ; that would turn a still-live operation into a fake completed failure.
        ; This worker is separate from the responsive Manager GUI thread.
        Local $controllerPresent = True
        While 1
            Local $status = _PB_PollHelper($p)
            If $status == "EXITED" Then
                If $controllerPresent And $p["exit_code"] = 0 Then $result = 0
                ExitLoop
            EndIf
            If $status <> "PRESENT" Then ExitLoop ; unknown is never success
            $parent = _WinObsProcessRead($token)
            If $parent["status"] <> "PRESENT" Then $controllerPresent = False
            Sleep(100)
        WEnd
    EndIf
    If $p["handle"] <> 0 Then _MP_Release($p)
    DllCall("ole32.dll", "none", "CoUninitialize")
    _WinObsProcessClose($token)
    Return $result
EndFunc

; ShellExecuteExW itself can wait for UAC, so only the request worker calls it.
Func _PB_RequestBlocking($root, $action, $controller, $cycle, $formerPid = 0)
    Local $p = _MP_New()
    If Not _PB_Medium() Or Not _PP_RootSafe($root) Then Return $p
    If $action <> "Prepare" And $action <> "Finish" And $action <> "Recover" Then Return $p
    If Not IsInt($cycle) Or $cycle < 1 Or $cycle > 999 Then Return $p
    If $action == "Recover" And (Not IsInt($formerPid) Or $formerPid < 1 Or $formerPid == $controller) Then Return $p
    Local $exe = $root & "\" & _PB_HelperName()
    If Not FileExists($exe) Then Return $p
    Local $args = $action & " " & $controller & " " & $cycle
    If $action == "Recover" Then $args = $action & " " & $controller & " " & $formerPid & " " & $cycle
    Local $s = DllStructCreate("dword size;ulong mask;hwnd window;ptr verb;ptr file;ptr parameters;ptr directory;int show;handle instance;ptr idlist;ptr class;handle key;dword hotkey;handle icon;handle process")
    Local $verb = DllStructCreate("wchar[6]"), $file = DllStructCreate("wchar[" & (StringLen($exe)+1) & "]")
    Local $parameters = DllStructCreate("wchar[" & (StringLen($args)+1) & "]"), $directory = DllStructCreate("wchar[" & (StringLen($root)+1) & "]")
    DllStructSetData($verb, 1, "runas")
    DllStructSetData($file, 1, $exe)
    DllStructSetData($parameters, 1, $args)
    DllStructSetData($directory, 1, $root)
    DllStructSetData($s, "size", DllStructGetSize($s))
    DllStructSetData($s, "mask", 0x140) ; NOCLOSEPROCESS | NOASYNC
    DllStructSetData($s, "verb", DllStructGetPtr($verb))
    DllStructSetData($s, "file", DllStructGetPtr($file))
    DllStructSetData($s, "parameters", DllStructGetPtr($parameters))
    DllStructSetData($s, "directory", DllStructGetPtr($directory))
    DllStructSetData($s, "show", 0)
    ConsoleWrite("Elevation request: " & $action & " cycle=" & $cycle & @CRLF)
    Local $a = DllCall("shell32.dll", "bool", "ShellExecuteExW", "struct*", $s)
    Local $dllError = @error, $ok = False
    If Not $dllError Then $ok = $a[0] <> 0
    Local $e = DllCall("kernel32.dll", "dword", "GetLastError"), $error = 0
    If Not @error Then $error = $e[0]
    Local $handle = DllStructGetData($s, "process")
    $p["status"] = _PB_Outcome($ok, $error, $handle)
    ConsoleWrite("Elevation result: " & $p["status"] & " win32=" & $error & @CRLF)
    If $p["status"] <> "STARTED" Then Return $p
    $p["handle"] = $handle
    $p["image"] = $exe
    $a = DllCall("kernel32.dll", "dword", "GetProcessId", "handle", $handle)
    If @error Or $a[0] = 0 Then
        $p["status"] = "UNKNOWN"
        Return $p
    EndIf
    $p["pid"] = $a[0]
    Return $p
EndFunc

Func _PB_Store()
    Local $path = DllStructCreate("wchar[260]")
    Local $a = DllCall("shell32.dll", "long", "SHGetFolderPathW", "hwnd", 0, "int", 35, "handle", 0, "dword", 0, "struct*", $path)
    If @error Or $a[0] <> 0 Then Return ""
    If $g_MS_AlphaMode Then Return DllStructGetData($path, 1) & "\PortableVirtualBox.Alpha"
    Return DllStructGetData($path, 1) & "\PortableVirtualBox.Experiment"
EndFunc

; Elevated helper identity is checked by its own fixed-action protocol.
; The lower-integrity worker only waits on the retained ShellExecuteEx handle.
Func _PB_PollHelper(ByRef $p)
    If Not IsMap($p) Or $p["handle"] = 0 Then Return "UNKNOWN"
    Local $a = DllCall("kernel32.dll", "dword", "WaitForSingleObject", "handle", $p["handle"], "dword", 0)
    If @error Then Return "UNKNOWN"
    If $a[0] = 258 Then Return "PRESENT"
    If $a[0] <> 0 Then Return "UNKNOWN"
    $a = DllCall("kernel32.dll", "bool", "GetExitCodeProcess", "handle", $p["handle"], "dword*", 0)
    If @error Or Not $a[0] Then Return "UNKNOWN"
    $p["exit_code"] = $a[2]
    Return "EXITED"
EndFunc
