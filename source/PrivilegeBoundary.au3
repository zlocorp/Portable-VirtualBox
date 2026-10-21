#include-once
#include "ManagedProcess.au3"
; Fixed compiled helper only. ShellExecuteExW runas returns the process handle;
; do not fall back to shell commands, scheduled tasks or direct elevated effects.
; This module is wired only to the separate, non-distributed session experiment.

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

Func _PB_Start($root, $action, $cycle)
    Local $p = _MP_New()
    If Not _PB_Medium() Or Not _PP_RootSafe($root) Then Return $p
    If $action <> "Prepare" And $action <> "Finish" Then Return $p
    If Not IsInt($cycle) Or $cycle < 1 Or $cycle > 999 Then Return $p
    Local $exe = $root & "\Portable-VirtualBox-Helper-Test.exe"
    If Not FileExists($exe) Then Return $p
    Local $args = $action & " " & @AutoItPID & " " & $cycle
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
    Local $a = DllCall("shell32.dll", "bool", "ShellExecuteExW", "struct*", $s)
    Local $dllError = @error, $ok = False
    If Not $dllError Then $ok = $a[0] <> 0
    Local $e = DllCall("kernel32.dll", "dword", "GetLastError"), $error = 0
    If Not @error Then $error = $e[0]
    Local $handle = DllStructGetData($s, "process")
    $p["status"] = _PB_Outcome($ok, $error, $handle)
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
    Return DllStructGetData($path, 1) & "\PortableVirtualBox.Experiment"
EndFunc
