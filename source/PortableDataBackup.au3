#include-once
#include "PortableProfile.au3"
#include "HostPreflight.au3"
#include <Crypt.au3>

; Public non-elevated, offline FILE copy of data/ (not a VM snapshot).
; No archive executables or Windows driver mutations. An absolute media path
; outside data/ is not included; the manifest proves only copied bytes.
; Git: CHANGELOG.md, FEATURES.md. Never delete a user file or failed stage.
Global Const $g_PBK_Header = "PortableVBox-data-backup-v1"

Func _PBK_IsUnder($path, $base)
    If Not IsString($path) Or Not IsString($base) Then Return False
    If StringLower($path) == StringLower($base) Then Return True
    Local $p = $base
    If StringRight($p, 1) <> "\" Then $p &= "\"
    Return StringLeft(StringLower($path), StringLen($p)) == StringLower($p)
EndFunc

Func _PBK_ValidPath($root, $target)
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Then Return False
    If Not _PP_RootSafe($target) Or StringLen($target) < 4 Then Return False
    If _PBK_IsUnder($target, $root) Or _PBK_IsUnder($root, $target) Then Return False
    Local $parent = StringRegExpReplace($target, "\\[^\\]+$", "")
    If Not _PP_RootSafe($parent) Or Not _PP_ParentsSafe($parent) Then Return False
    If _PP_DirectoryState($target) <> 0 Or _PP_DirectoryState($target & ".pending") <> 0 Then Return False
    If _PBK_PathState($target & ".cancel-request") <> 0 Then Return False
    Return True
EndFunc

; 0 absent, 1 regular file, 2 regular directory, -1 anything unsafe.
Func _PBK_PathState($path)
    Local $a = DllCall("kernel32.dll", "dword", "GetFileAttributesW", "wstr", $path)
    If @error Then Return -1
    If $a[0] = 4294967295 Or $a[0] = -1 Then
        Local $err = DllCall("kernel32.dll", "dword", "GetLastError")
        If @error Then Return -1
        If $err[0] = 2 Or $err[0] = 3 Then Return 0
        Return -1
    EndIf
    If BitAND($a[0], 0x400) <> 0 Then Return -1
    If BitAND($a[0], 0x10) <> 0 Then Return 2
    Return 1
EndFunc

Func _PBK_Offline()
    Local $installed = _PortableInstalledVBoxDetected()
    If Not IsBool($installed) Or $installed Then Return False
    Return _PortableCountExistingServices() = 0 And _PortableCountVirtualBoxProcesses() = 0
EndFunc

Func _PBK_GrabSessionLock()
    Local $a = DllCall("kernel32.dll", "handle", "CreateMutexW", "ptr", 0, "bool", True, "wstr", "Global\PortableVirtualBox.ManagerExperiment")
    If @error Or Not IsArray($a) Or $a[0] = 0 Then Return 0
    Local $h = $a[0]
    Local $e = DllCall("kernel32.dll", "dword", "GetLastError")
    If @error Or Not IsArray($e) Or $e[0] = 183 Then
        DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
        Return 0
    EndIf
    Return $h
EndFunc

Func _PBK_ReleaseSessionLock($handle)
    If $handle = 0 Then Return
    DllCall("kernel32.dll", "bool", "ReleaseMutex", "handle", $handle)
    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $handle)
EndFunc

Func _PBK_Hash($path)
    Local $hash = _Crypt_HashFile($path, $CALG_SHA_256)
    If @error Or Not IsBinary($hash) Then Return ""
    Return StringLower(StringTrimLeft(String($hash), 2))
EndFunc

Func _PBK_CancelRequested($dest)
    Return _PBK_PathState($dest & ".cancel-request") <> 0
EndFunc

Func _PBK_Scan($root, $relative, ByRef $rows, ByRef $count, $target = "", $dest = "", $manifest = 0)
    Local $dir = $root & "\" & $relative
    If _PBK_PathState($dir) <> 2 Then Return False
    Local $find = FileFindFirstFile($dir & "\*")
    If $find = -1 Then
        Local $error = DllCall("kernel32.dll", "dword", "GetLastError")
        If @error Then Return False
        ; Win32: empty enumeration, not access denied or an unknown failure.
        Return $error[0] = 2 Or $error[0] = 18
    EndIf
    Local $ok = True
    While 1
        Local $name = FileFindNextFile($find)
        If @error Then ExitLoop
        If $name == "." Or $name == ".." Or StringRegExp($name, "[\x00-\x1f]") Then
            $ok = False
            ExitLoop
        EndIf
        Local $rel = $relative & "\" & $name
        If Not _PortableSafeRelativePath($rel) Then
            $ok = False
            ExitLoop
        EndIf
        Local $source = $root & "\" & $rel
        Local $state = _PBK_PathState($source)
        If $state = 2 Then
            If $target <> "" Then
                If Not DirCreate($target & "\" & $rel) Then
                    $ok = False
                    ExitLoop
                EndIf
            EndIf
            If Not _PBK_Scan($root, $rel, $rows, $count, $target, $dest, $manifest) Then
                $ok = False
                ExitLoop
            EndIf
        ElseIf $state = 1 Then
            If $count >= 100000 Or ($dest <> "" And _PBK_CancelRequested($dest)) Then
                $ok = False
                ExitLoop
            EndIf
            Local $key = StringLower($rel)
            If MapExists($rows, $key) Then
                $ok = False
                ExitLoop
            EndIf
            Local $size = FileGetSize($source)
            If @error Or $size < 0 Then
                $ok = False
                ExitLoop
            EndIf
            Local $hash = _PBK_Hash($source)
            If StringLen($hash) <> 64 Then
                $ok = False
                ExitLoop
            EndIf
            If $target <> "" Then
                Local $copy = $target & "\" & $rel
                If _PBK_PathState($copy) <> 0 Or Not FileCopy($source, $copy, 0) Then
                    $ok = False
                    ExitLoop
                EndIf
                If FileGetSize($copy) <> $size Or _PBK_Hash($copy) <> $hash Or _PBK_Hash($source) <> $hash Then
                    $ok = False
                    ExitLoop
                EndIf
                FileWrite($manifest, $hash & @TAB & $size & @TAB & $rel & @LF)
                If @error Then
                    $ok = False
                    ExitLoop
                EndIf
            EndIf
            $rows[$key] = $hash & @TAB & $size
            $count += 1
        Else
            $ok = False
            ExitLoop
        EndIf
    WEnd
    FileClose($find)
    Return $ok
EndFunc

; Return 0 success, 2 blocked/unsafe, 3 incomplete/failed. Staged bytes are
; intentionally retained for manual inspection on error and never published.
Func _PBK_Create($root, $dest)
    If Not _PBK_ValidPath($root, $dest) Or _PBK_PathState($root & "\data") <> 2 Then Return 2
    Local $lock = _PBK_GrabSessionLock()
    If $lock = 0 Then Return 2
    Local $result = 3
    If _PBK_Offline() And _PBK_ValidPath($root, $dest) Then
        Local $pending = $dest & ".pending"
        If DirCreate($pending & "\data") Then
            Local $manifest = FileOpen($pending & "\SHA256SUMS.txt", 2 + 256)
            If $manifest <> -1 Then
                FileWrite($manifest, $g_PBK_Header & @LF)
                Local $rows[], $count = 0
                _Crypt_Startup()
                Local $ok = _PBK_Scan($root, "data", $rows, $count, $pending, $dest, $manifest)
                FileClose($manifest)
                If $ok And _PBK_Offline() And Not _PBK_CancelRequested($dest) Then
                    ; Refuse a copied file that changed after its initial hash.
                    Local $fresh[], $verified = 0
                    $ok = _PBK_Scan($root, "data", $fresh, $verified, "", $dest)
                    If $ok And $verified = $count Then
                        Local $keys = MapKeys($rows)
                        For $key In $keys
                            If Not MapExists($fresh, $key) Or $fresh[$key] <> $rows[$key] Then
                                $ok = False
                                ExitLoop
                            EndIf
                        Next
                    Else
                        $ok = False
                    EndIf
                Else
                    $ok = False
                EndIf
                If $ok And _PBK_VerifyInternal($pending) And _PBK_Offline() And Not _PBK_CancelRequested($dest) Then
                    Local $m = DllCall("kernel32.dll", "bool", "MoveFileExW", "wstr", $pending, "wstr", $dest, "dword", 8)
                    If Not @error And IsArray($m) Then
                        If $m[0] Then $result = 0
                    EndIf
                EndIf
                _Crypt_Shutdown()
            EndIf
        EndIf
    EndIf
    _PBK_ReleaseSessionLock($lock)
    Return $result
EndFunc

Func _PBK_VerifyInternal($dir)
    If _PBK_PathState($dir) <> 2 Or _PBK_PathState($dir & "\data") <> 2 Then Return False
    If _PBK_PathState($dir & "\SHA256SUMS.txt") <> 1 Then Return False
    Local $f = FileOpen($dir & "\SHA256SUMS.txt", 256)
    If $f = -1 Then Return False
    Local $raw = FileRead($f, 10000000)
    Local $close = FileClose($f)
    If Not $close Or StringLen($raw) > 9999999 Then Return False
    Local $lines = StringSplit(StringStripCR($raw), @LF, 2)
    If UBound($lines) < 2 Or $lines[0] <> $g_PBK_Header Then Return False
    Local $rows[], $count = 0
    For $i = 1 To UBound($lines) - 1
        If $lines[$i] == "" Then
            If $i <> UBound($lines) - 1 Then Return False
            ContinueLoop
        EndIf
        Local $p = StringSplit($lines[$i], @TAB, 2)
        If UBound($p) <> 3 Or Not StringRegExp($p[0], "^[0-9a-f]{64}$") Or _PortableSafeRelativePath($p[2]) = False Then Return False
        If StringLeft($p[2], 5) <> "data\" Or Not StringRegExp($p[1], "^(0|[1-9][0-9]*)$") Then Return False
        Local $key = StringLower($p[2])
        If MapExists($rows, $key) Then Return False
        $rows[$key] = $p[0] & @TAB & $p[1]
        $count += 1
        If $count > 100000 Then Return False
    Next
    Local $actual[], $n = 0
    If Not _PBK_Scan($dir, "data", $actual, $n) Or $n <> $count Then Return False
    Local $keys = MapKeys($rows)
    For $key In $keys
        If Not MapExists($actual, $key) Or $actual[$key] <> $rows[$key] Then Return False
    Next
    Return True
EndFunc

Func _PBK_Verify($dir)
    If Not _PP_RootSafe($dir) Or Not _PP_ParentsSafe($dir) Then Return False
    _Crypt_Startup()
    Local $r = _PBK_VerifyInternal($dir)
    _Crypt_Shutdown()
    Return $r
EndFunc

; Restore verified backup into a NEW, otherwise nonexistent root. Never merge
; with an existing VM/profile, overwrite a launcher or touch live Oracle files.
; Caller must separately install an approved launcher and Oracle app64 later.
Func _PBK_Restore($backup, $target)
    If Not _PBK_ValidPath($backup, $target) Then Return 2
    If _PBK_IsUnder($target, @ScriptDir) Or _PBK_IsUnder(@ScriptDir, $target) Then Return 2
    If Not _PBK_Verify($backup) Then Return 2
    Local $lock = _PBK_GrabSessionLock()
    If $lock = 0 Then Return 2
    Local $result = 3
    If _PBK_Offline() And _PBK_ValidPath($backup, $target) Then
        Local $pending = $target & ".pending"
        If DirCreate($pending & "\data") Then
            Local $manifest = FileOpen($pending & "\SHA256SUMS.txt", 2 + 256)
            If $manifest <> -1 Then
                FileWrite($manifest, $g_PBK_Header & @LF)
                Local $rows[], $count = 0
                _Crypt_Startup()
                Local $ok = _PBK_Scan($backup, "data", $rows, $count, $pending, $target, $manifest)
                FileClose($manifest)
                If $ok And _PBK_VerifyInternal($pending) And _PBK_VerifyInternal($backup) And _PBK_Offline() And Not _PBK_CancelRequested($target) Then
                    Local $m = DllCall("kernel32.dll", "bool", "MoveFileExW", "wstr", $pending, "wstr", $target, "dword", 8)
                    If Not @error And IsArray($m) Then
                        If $m[0] Then $result = 0
                    EndIf
                EndIf
                _Crypt_Shutdown()
            EndIf
        EndIf
    EndIf
    _PBK_ReleaseSessionLock($lock)
    Return $result
EndFunc
