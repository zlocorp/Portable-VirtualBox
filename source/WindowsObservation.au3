#include-once
#include "RuntimeSafety.au3"
; Query-only Windows observations. No observation authorizes resource mutation.
; Default callers must not print private image paths or service account names.

Func _WinObsResult($kind, $status = "UNKNOWN", $error = 0, $stage = "")
    Local $r[]
    $r["kind"] = $kind
    $r["status"] = $status
    $r["error"] = $error
    $r["stage"] = $stage
    $r["pid"] = 0
    $r["created"] = ""
    $r["image"] = ""
    $r["state"] = 0
    $r["build"] = 0
    $r["product_type"] = 0
    Return $r
EndFunc

Func _WinObsLastError()
    Local $a = DllCall("kernel32.dll", "dword", "GetLastError")
    If @error Then Return -1
    Return $a[0]
EndFunc

; Absence is meaningful only at the documented open boundary.
Func _WinObsFailure($kind, $stage, $error)
    If Not IsInt($error) Or $stage <> "open" Then Return "UNKNOWN"
    If $kind == "service" And $error = 1060 Then Return "ABSENT"
    If $kind == "installation" And ($error = 2 Or $error = 3) Then Return "ABSENT"
    Return "UNKNOWN"
EndFunc

Func _WinObsError($kind, $stage, $error)
    Return _WinObsResult($kind, _WinObsFailure($kind, $stage, $error), $error, $stage)
EndFunc

Func _WinObsWorkstationAccepted($build, $product, $major = 10)
    If Not IsInt($build) Or Not IsInt($product) Or Not IsInt($major) Then Return False
    Return $major = 10 And $build >= 22000 And $product = 1
EndFunc

Func _WinObsOS()
    Local $v = DllStructCreate("dword Size;dword Major;dword Minor;dword Build;dword Platform;wchar CSD[128];ushort SPMajor;ushort SPMinor;ushort Suite;byte Product;byte Reserved")
    If @error Then Return _WinObsError("os", "buffer", -1)
    DllStructSetData($v, "Size", DllStructGetSize($v))
    Local $a = DllCall("ntdll.dll", "long", "RtlGetVersion", "struct*", $v)
    If @error Then Return _WinObsError("os", "version", -1)
    If $a[0] <> 0 Then Return _WinObsError("os", "version", $a[0])
    Local $r = _WinObsResult("os", "PRESENT")
    $r["build"] = DllStructGetData($v, "Build")
    $r["major"] = DllStructGetData($v, "Major")
    $r["product_type"] = DllStructGetData($v, "Product")
    If $r["product_type"] < 1 Or $r["product_type"] > 3 Then Return _WinObsError("os", "product", -1)
    Return $r
EndFunc

Func _WinObsInstallationKey($key, $view)
    ; HKEY_LOCAL_MACHINE is a sign-extended predefined handle on x64.
    ; KEY_QUERY_VALUE | explicitly selected WOW64 view, not KEY_ALL_ACCESS.
    Local $a = DllCall("advapi32.dll", "long", "RegOpenKeyExW", "handle", Ptr(-2147483646), _
        "wstr", $key, "dword", 0, "dword", BitOR(1, $view), "handle*", 0)
    If @error Then Return _WinObsError("installation", "open", -1)
    If $a[0] <> 0 Then Return _WinObsError("installation", "open", $a[0])
    Local $close = DllCall("advapi32.dll", "long", "RegCloseKey", "handle", $a[5])
    If @error Then Return _WinObsError("installation", "close", -1)
    If $close[0] <> 0 Then Return _WinObsError("installation", "close", $close[0])
    ; Even an empty stale vendor key is a review blocker, not permission to clean.
    Return _WinObsResult("installation", "PRESENT")
EndFunc

Func _WinObsInstallation()
    Local $keys[2] = ["SOFTWARE\Oracle\VirtualBox", "SOFTWARE\Sun\VirtualBox"]
    Local $views[2] = [0x100, 0x200], $unknown = _WinObsResult("installation", "ABSENT")
    For $i = 0 To 1
        For $k = 0 To 1
            Local $r = _WinObsInstallationKey($keys[$i], $views[$k])
            If $r["status"] == "PRESENT" Then Return $r
            If $r["status"] == "UNKNOWN" Then $unknown = $r
        Next
    Next
    Return $unknown
EndFunc

#include "WindowsServiceProbe.au3"
#include "WindowsProcessProbe.au3"
