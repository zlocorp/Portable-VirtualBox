#include-once
#include "PortableProfile.au3"
#include "LauncherI18n.au3"

; User-visible, strictly read-only inventory of VirtualBox .vbox XML and
; referenced media. No VBoxManage, admin privileges, XML writes or mounts.
; The result is a portability warning, NOT a filesystem backup verification
; or permission to run/modify a VM. No external paths are ever opened.
Global Const $g_PVI_MaxConfigs = 256
Global Const $g_PVI_MaxEntries = 12000
Global Const $g_PVI_MaxMedia = 1024

Func _PVI_PathState($path)
    Local $a = DllCall("kernel32.dll", "dword", "GetFileAttributesW", "wstr", $path)
    If @error Or Not IsArray($a) Then Return -1
    If $a[0] = 4294967295 Or $a[0] = -1 Then
        Local $e = DllCall("kernel32.dll", "dword", "GetLastError")
        If @error Or Not IsArray($e) Then Return -1
        If $e[0] = 2 Or $e[0] = 3 Then Return 0
        Return -1
    EndIf
    If BitAND($a[0], 0x400) Then Return -1 ; junction/reparse point
    If BitAND($a[0], 0x10) Then Return 2
    Return 1
EndFunc

Func _PVI_New()
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["vm_count"] = 0
    $r["snapshot_count"] = 0
    $r["media_count"] = 0
    $r["external_count"] = 0
    $r["missing_count"] = 0
    $r["entries"] = 0
    $r["detail"] = ""
    $r["report"] = ""
    Return $r
EndFunc

Func _PVI_Add(ByRef $r, $message)
    ; Keep output bounded for a Windows edit control. Long or unprintable
    ; information causes a visible refusal instead of silent truncation.
    If Not IsString($message) Or StringLen($message) > 2048 Then Return False
    If StringRegExp($message, "[\x00-\x08\x0b\x0c\x0e-\x1f]") Then Return False
    If StringLen($r["report"]) + StringLen($message) > 30000 Then Return False
    $r["report"] &= $message & @CRLF
    Return True
EndFunc

; Media paths outside the VM directory are deliberately reported as needing
; review. Even a relative .. can refer to shared/external disks; do not resolve
; or open it while auditing. In-directory symlinks are also rejected.
Func _PVI_MediaLocation($configDir, $location)
    If Not IsString($configDir) Or Not IsString($location) Or $location == "" Then Return "UNSAFE"
    If StringLen($location) > 512 Or StringRegExp($location, "[\x00-\x1f]") Then Return "UNSAFE"
    Local $p = StringReplace($location, "/", "\")
    If StringRegExp($p, "^[A-Za-z]:") Or StringLeft($p, 1) == "\" Or StringInStr($p, "%") Or StringInStr($p, ":") Then Return "EXTERNAL"
    If Not _PortableSafeRelativePath($p) Then Return "EXTERNAL"
    If Not _PP_RootSafe($configDir) Then Return "UNSAFE"
    Local $parts = StringSplit($p, "\", 2), $base = $configDir
    For $i = 0 To UBound($parts) - 1
        $base &= "\" & $parts[$i]
        If StringLen($base) > 245 Then Return "EXTERNAL"
        Local $state = _PVI_PathState($base)
        If $i < UBound($parts) - 1 Then
            If $state == 0 Then Return "MISSING"
            If $state <> 2 Then Return "UNSAFE"
        Else
            If $state == 0 Then Return "MISSING"
            If $state <> 1 Then Return "UNSAFE"
        EndIf
    Next
    Return "LOCAL"
EndFunc

Func _PVI_ReadMachine($configPath, ByRef $r)
    If _PVI_PathState($configPath) <> 1 Then Return False
    Local $size = FileGetSize($configPath)
    If @error Or $size < 30 Or $size > 4194304 Then Return False
    Local $h = FileOpen($configPath, 256)
    If $h == -1 Then Return False
    Local $xmlText = FileRead($h, 4194305)
    Local $closed = FileClose($h)
    If Not $closed Or StringLen($xmlText) > 4194304 Then Return False
    If StringRegExp($xmlText, "(?i)<!\s*(doctype|entity)\b") Then Return False
    Local $xml = ObjCreate("Msxml2.DOMDocument.6.0")
    If @error Or Not IsObj($xml) Then Return False
    $xml.async = False
    $xml.validateOnParse = False
    $xml.resolveExternals = False
    $xml.setProperty("ProhibitDTD", True)
    If Not $xml.loadXML($xmlText) Then Return False
    If $xml.documentElement.nodeName <> "VirtualBox" Then Return False
    Local $machines = $xml.selectNodes('//*[local-name()="Machine"]')
    If Not IsObj($machines) Or $machines.length <> 1 Then Return False
    Local $machine = $machines.item(0)
    Local $name = $machine.getAttribute("name"), $uuid = $machine.getAttribute("uuid")
    If Not IsString($name) Or StringLen($name) < 1 Or StringLen($name) > 180 Then Return False
    If StringRegExp($name, "[\x00-\x1f]") Or Not IsString($uuid) Then Return False
    If Not StringRegExp($uuid, "(?i)^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$") Then Return False
    Local $snapshots = $xml.selectNodes('//*[local-name()="Snapshot"]')
    Local $media = $xml.selectNodes('//*[@location]')
    If Not IsObj($snapshots) Or Not IsObj($media) Then Return False
    If $snapshots.length > $g_PVI_MaxMedia Or $media.length > $g_PVI_MaxMedia Then Return False
    $r["vm_count"] += 1
    $r["snapshot_count"] += $snapshots.length
    $r["media_count"] += $media.length
    If Not _PVI_Add($r, _LI("vm.machine") & $name & " | " & $uuid & " | " & _LI("vm.snapshots") & $snapshots.length) Then Return False
    Local $configDir = StringRegExpReplace($configPath, "\\[^\\]+$", "")
    For $i = 0 To $media.length - 1
        Local $location = $media.item($i).getAttribute("location")
        Local $state = _PVI_MediaLocation($configDir, $location)
        Switch $state
            Case "LOCAL"
                ContinueLoop
            Case "EXTERNAL"
                $r["external_count"] += 1
                If Not _PVI_Add($r, _LI("vm.external") & $location) Then Return False
            Case "MISSING"
                $r["missing_count"] += 1
                If Not _PVI_Add($r, _LI("vm.missing") & $location) Then Return False
            Case Else
                Return False
        EndSwitch
    Next
    Return True
EndFunc

Func _PVI_Walk($root, $relative, $depth, ByRef $r)
    If $depth > 8 Then Return False
    Local $base = $root & "\" & $relative
    If _PVI_PathState($base) <> 2 Then Return False
    Local $find = FileFindFirstFile($base & "\*")
    If $find = -1 Then
        Local $e = DllCall("kernel32.dll", "dword", "GetLastError")
        If @error Or Not IsArray($e) Then Return False
        Return $e[0] == 2 Or $e[0] == 18
    EndIf
    Local $ok = True
    While 1
        Local $name = FileFindNextFile($find)
        If @error Then ExitLoop
        Local $rel = $relative & "\" & $name
        If Not _PortableSafeRelativePath($rel) Then
            $ok = False
            ExitLoop
        EndIf
        Local $path = $root & "\" & $rel
        Local $state = _PVI_PathState($path)
        $r["entries"] += 1
        If $r["entries"] > $g_PVI_MaxEntries Or $state < 0 Then
            $ok = False
            ExitLoop
        EndIf
        If $state == 2 Then
            If Not _PVI_Walk($root, $rel, $depth + 1, $r) Then
                $ok = False
                ExitLoop
            EndIf
        ElseIf $state == 1 And StringRegExp($name, "(?i)\.vbox$") Then
            If $r["vm_count"] >= $g_PVI_MaxConfigs Or Not _PVI_ReadMachine($path, $r) Then
                $ok = False
                ExitLoop
            EndIf
        EndIf
    WEnd
    FileClose($find)
    Return $ok
EndFunc

Func _PVI_Inspect($root)
    Local $r = _PVI_New()
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Then Return $r
    Local $directory = $root & "\data\Machines"
    Local $state = _PVI_PathState($directory)
    If $state == 0 Then
        $r["status"] = "EMPTY"
        $r["report"] = _LI("vm.empty") & @CRLF
        Return $r
    EndIf
    If $state <> 2 Or Not _PVI_Walk($root, "data\Machines", 0, $r) Then
        $r["status"] = "BLOCKED"
        $r["report"] = _LI("vm.blocked") & @CRLF
        Return $r
    EndIf
    If $r["vm_count"] == 0 Then
        $r["status"] = "EMPTY"
        $r["report"] = _LI("vm.empty") & @CRLF
        Return $r
    EndIf
    Local $status = "CLEAN"
    If $r["missing_count"] > 0 Or $r["external_count"] > 0 Then $status = "REVIEW"
    $r["status"] = $status
    $r["report"] = _LI("vm.header") & @CRLF & $r["report"] & @CRLF & _LI("vm.summary") & _
        $r["vm_count"] & " / " & $r["snapshot_count"] & " / " & $r["media_count"] & " / " & _
        $r["external_count"] & " / " & $r["missing_count"] & @CRLF
    If $status == "CLEAN" Then
        $r["report"] &= _LI("vm.clean") & @CRLF
    Else
        $r["report"] &= _LI("vm.review") & @CRLF
    EndIf
    Return $r
EndFunc
