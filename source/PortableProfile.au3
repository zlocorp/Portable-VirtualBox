#include-once
#include "RuntimeSafety.au3"

; Self-contained portable user DATA only. No executable creation/installation,
; registry changes, service operations, VM launch, XML rewrite or deletion.
; Existing files are never modified. Caller must supply an existing root.

Func _PP_RootSafe($root)
    If Not IsString($root) Or StringLen($root) < 3 Or StringLen($root) > 230 Then Return False
    If Not StringRegExp($root, "^[A-Za-z]:\\") Then Return False
    If StringInStr($root, "/") Or StringInStr($root, "\\", 0, 1, 4) Then Return False
    If StringLen($root) = 3 Then Return True ; syntactically valid, not an init target
    If StringRight($root, 1) == "\" Then Return False
    Return _PortableSafeRelativePath(StringTrimLeft($root, 3))
EndFunc

; 1 = existing regular directory, 0 = absent, -1 = file/link/unknown.
Func _PP_DirectoryState($path)
    Local $a = DllCall("kernel32.dll", "dword", "GetFileAttributesW", "wstr", $path)
    If @error Then Return -1
    If $a[0] = 4294967295 Or $a[0] = -1 Then
        ; A missing object is not necessarily an access failure: fail closed
        ; if the last Windows error is not FILE_NOT_FOUND / PATH_NOT_FOUND.
        Local $e = DllCall("kernel32.dll", "dword", "GetLastError")
        If @error Then Return -1
        If $e[0] = 2 Or $e[0] = 3 Then Return 0
        Return -1
    EndIf
    If BitAND($a[0], 0x400) <> 0 Then Return -1
    If BitAND($a[0], 0x10) = 0 Then Return -1
    Return 1
EndFunc

; Validate every *existing* parent, rejecting junctions/reparse points even
; when they occur above the portable folder.
Func _PP_ParentsSafe($root)
    Local $path = StringLeft($root, 3)
    If _PP_DirectoryState($path) <> 1 Then Return False
    If StringLen($root) = 3 Then Return True
    Local $parts = StringSplit(StringTrimLeft($root, 3), "\", 2)
    For $i = 0 To UBound($parts) - 1
        $path &= $parts[$i]
        If _PP_DirectoryState($path) <> 1 Then Return False
        If $i < UBound($parts) - 1 Then $path &= "\"
    Next
    Return True
EndFunc

Func _PP_NewResult($root)
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["message"] = ""
    $r["root"] = $root
    $r["data"] = ""
    $r["profile"] = ""
    $r["machines"] = ""
    $r["logs"] = ""
    $r["app"] = ""
    $r["app_present"] = False
    $r["missing_folders"] = ""
    Return $r
EndFunc

Func _PP_Inspect($root)
    Local $r = _PP_NewResult($root)
    If Not _PP_RootSafe($root) Then
        $r["message"] = "invalid-root"
        Return $r
    EndIf
    If Not _PP_ParentsSafe($root) Then
        $r["message"] = "root-not-private-regular-directory"
        Return $r
    EndIf
    $r["data"] = $root & "\data"
    $r["profile"] = $root & "\data\.VirtualBox"
    $r["machines"] = $root & "\data\Machines"
    $r["logs"] = $root & "\logs"
    $r["app"] = $root & "\app64"
    $r["app_present"] = FileExists($r["app"] & "\VirtualBox.exe") <> 0
    Local $folders[4] = [$r["data"], $r["profile"], $r["machines"], $r["logs"]]
    Local $missing = False
    For $i = 0 To UBound($folders) - 1
        Local $state = _PP_DirectoryState($folders[$i])
        If $state < 0 Then
            $r["message"] = "path-collision-or-reparse"
            Return $r
        EndIf
        If $state = 0 Then
            $missing = True
            If $r["missing_folders"] <> "" Then $r["missing_folders"] &= ", "
            $r["missing_folders"] &= StringTrimLeft($folders[$i], StringLen($root) + 1)
        EndIf
    Next
    If $missing Then
        $r["status"] = "MISSING"
        $r["message"] = "private-folders-not-created"
    Else
        $r["status"] = "READY"
        $r["message"] = "private-folders-ready"
    EndIf
    Return $r
EndFunc

Func _PP_Ensure($root)
    Local $r = _PP_Inspect($root)
    If $r["status"] == "BLOCKED" Then Return $r
    If StringLen($root) = 3 Then
        $r["status"] = "BLOCKED"
        $r["message"] = "drive-root-not-allowed"
        Return $r
    EndIf
    If $r["status"] == "READY" Then Return $r
    ; The entire proposed directory layout was inspected before any write.
    Local $folders[4] = [$r["data"], $r["profile"], $r["machines"], $r["logs"]]
    For $i = 0 To UBound($folders) - 1
        Local $state = _PP_DirectoryState($folders[$i])
        If $state < 0 Then ExitLoop
        If $state = 0 Then
            If Not DirCreate($folders[$i]) Then ExitLoop
        EndIf
        If _PP_DirectoryState($folders[$i]) <> 1 Then ExitLoop
    Next
    $r = _PP_Inspect($root)
    If $r["status"] <> "READY" Then
        $r["status"] = "BLOCKED"
        $r["message"] = "folder-creation-incomplete"
    EndIf
    Return $r
EndFunc
