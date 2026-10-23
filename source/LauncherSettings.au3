#include-once
#include "PortableProfile.au3"
#include "LauncherI18n.au3"
; Independent adaptation of Deac2's remembered first-run language UX.
; Source/provenance: CREDITS.md and docs/COMMUNITY-ADOPTION.md (COM-01).
; User preferences only: never a driver/cleanup authority. No Oracle XML writes.
; Staged same-directory replacement is not a claim of power-loss recovery or
; protection against a malicious process running under the same account.

Func _LS_Valid($language)
    Return IsString($language) And ($language == "auto" Or $language == "ru" Or $language == "en")
EndFunc

Func _LS_Parse($text)
    If Not IsString($text) Or StringLen($text) > 128 Then Return ""
    Local $m = StringRegExp($text, "\A\[PortableVirtualBox\]\r?\nversion=1\r?\nlanguage=(auto|ru|en)\r?\n\z", 1)
    If Not IsArray($m) Then Return ""
    Return $m[0]
EndFunc

Func _LS_Select($language, $hostLanguage)
    If $language == "ru" Or $language == "en" Then Return $language
    Return _LI_Detect($hostLanguage)
EndFunc

; Missing = 0, regular non-reparse file = 1, unsafe/unknown = -1.
Func _LS_FileState($path)
    Local $a = DllCall("kernel32.dll", "dword", "GetFileAttributesW", "wstr", $path)
    If @error Then Return -1
    If $a[0] = -1 Or $a[0] = 4294967295 Then
        Local $e = DllCall("kernel32.dll", "dword", "GetLastError")
        If @error Then Return -1
        If $e[0] = 2 Or $e[0] = 3 Then Return 0
        Return -1
    EndIf
    If BitAND($a[0], 0x410) <> 0 Then Return -1 ; directory/reparse
    Return 1
EndFunc

Func _LS_Load($root)
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["language"] = "auto"
    Local $p = _PP_Inspect($root)
    If $p["status"] == "BLOCKED" Then Return $r
    Local $path = $root & "\data\launcher.ini", $state = _LS_FileState($path)
    If $state = 0 Then
        $r["status"] = "ABSENT"
        Return $r
    EndIf
    If $state <> 1 Then Return $r
    Local $h = FileOpen($path, 16) ; binary, bounded read; no encoding guess
    If $h = -1 Then Return $r
    Local $bytes = FileRead($h, 129)
    Local $closed = FileClose($h)
    If Not $closed Or BinaryLen($bytes) > 128 Then Return $r
    Local $language = _LS_Parse(BinaryToString($bytes, 4))
    If Not _LS_Valid($language) Then Return $r
    $r["status"] = "READY"
    $r["language"] = $language
    Return $r
EndFunc

Func _LS_Save($root, $language)
    If Not _LS_Valid($language) Then Return False
    Local $before = _LS_Load($root)
    If $before["status"] == "BLOCKED" Then Return False
    Local $p = _PP_Ensure($root)
    If $p["status"] <> "READY" Then Return False
    Local $path = $root & "\data\launcher.ini", $pending = $path & ".pending"
    ; CREATE_NEW below serializes cooperating writers and never replaces a
    ; stale pending file. A stale file is surfaced for manual inspection.
    Local $a = DllCall("kernel32.dll", "handle", "CreateFileW", "wstr", $pending, _
        "dword", 0x40000000, "dword", 0, "ptr", 0, "dword", 1, "dword", 0x80, "ptr", 0)
    If @error Then Return False
    If $a[0] = Ptr(-1) Then Return False
    Local $h = $a[0]
    Local $bytes = StringToBinary("[PortableVirtualBox]" & @CRLF & "version=1" & @CRLF & "language=" & $language & @CRLF, 4)
    Local $size = BinaryLen($bytes), $buffer = DllStructCreate("byte[" & $size & "]")
    DllStructSetData($buffer, 1, $bytes)
    $a = DllCall("kernel32.dll", "bool", "WriteFile", "handle", $h, "struct*", $buffer, "dword", $size, "dword*", 0, "ptr", 0)
    Local $ok = False
    If Not @error And IsArray($a) Then $ok = $a[0] <> 0 And $a[4] = $size
    If $ok Then
        $a = DllCall("kernel32.dll", "bool", "FlushFileBuffers", "handle", $h)
        If @error Then
            $ok = False
        Else
            $ok = $a[0] <> 0
        EndIf
    EndIf
    $a = DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
    If @error Then Return False
    If Not $a[0] Or Not $ok Then Return False ; retain failed write evidence
    Local $fresh = _LS_Load($root)
    If $fresh["status"] <> $before["status"] Or $fresh["language"] <> $before["language"] Then Return False
    Local $flags = 8 ; WRITE_THROUGH, same volume, never copy or reboot
    If $before["status"] == "READY" Then $flags = 9 ; replace our validated schema only
    $a = DllCall("kernel32.dll", "bool", "MoveFileExW", "wstr", $pending, "wstr", $path, "dword", $flags)
    If @error Then Return False
    If Not $a[0] Then Return False
    $fresh = _LS_Load($root)
    Return $fresh["status"] == "READY" And $fresh["language"] == $language
EndFunc
