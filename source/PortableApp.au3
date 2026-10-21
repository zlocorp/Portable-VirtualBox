#include-once
#include "PortableProfile.au3"
#include "LauncherI18n.au3"
; Independent completeness check motivated by upstream #103/#105 and Deac2
; first-run UX. See docs/COMMUNITY-ADOPTION.md COM-02; no external code copied.
; Reads attributes/sizes only. File presence is NOT signature or VM acceptance.

Func _PA_Required()
    Return StringSplit("VirtualBox.exe|VirtualBoxVM.exe|VBoxManage.exe|VBoxSVC.exe|VBoxSDS.exe|VBoxC.dll|VBoxRT.dll|VBoxVMM.dll|Qt6CoreVBox.dll|Qt6GuiVBox.dll|Qt6WidgetsVBox.dll|platforms\qwindowsVBox.dll|drivers\vboxsup\VBoxSup.sys|drivers\vboxsup\VBoxSup.inf|drivers\vboxsup\VBoxSup.cat", "|", 2)
EndFunc

; Check every component below root before following it. Distinguish access
; denial from absence. The already validated root is not modified.
Func _PA_FileState($root, $relative)
    Local $parts = StringSplit($relative, "\", 2), $path = $root
    For $i = 0 To UBound($parts) - 1
        $path &= "\" & $parts[$i]
        Local $a = DllCall("kernel32.dll", "dword", "GetFileAttributesW", "wstr", $path)
        If @error Then Return -1
        If $a[0] = -1 Or $a[0] = 4294967295 Then
            Local $e = DllCall("kernel32.dll", "dword", "GetLastError")
            If @error Then Return -1
            If $e[0] = 2 Or $e[0] = 3 Then Return 0
            Return -1
        EndIf
        If BitAND($a[0], 0x400) <> 0 Then Return -1
        If $i < UBound($parts) - 1 Then
            If BitAND($a[0], 0x10) = 0 Then Return -1
        Else
            If BitAND($a[0], 0x10) <> 0 Then Return -1
            Local $size = FileGetSize($path)
            If @error Then Return -1
            If $size = 0 Then Return 0
        EndIf
    Next
    Return 1
EndFunc

Func _PA_Inspect($root)
    Local $r[]
    $r["status"] = "UNSAFE"
    $r["missing"] = ""
    If Not _PP_RootSafe($root) Then Return $r
    If Not _PP_ParentsSafe($root) Then
        $r["missing"] = "root-or-ancestor-unreadable"
        ConsoleWriteError("Portable app observation: " & $r["missing"] & @CRLF)
        Return $r
    EndIf
    Local $state = _PP_DirectoryState($root & "\app64")
    If $state = 0 Then
        $r["status"] = "MISSING"
        Return $r
    EndIf
    If $state <> 1 Then
        $r["missing"] = "app64-directory-unreadable"
        ConsoleWriteError("Portable app observation: " & $r["missing"] & @CRLF)
        Return $r
    EndIf
    Local $files = _PA_Required()
    For $i = 0 To UBound($files) - 1
        $state = _PA_FileState($root, "app64\" & $files[$i])
        If $state < 0 Then
            $r["missing"] = $files[$i]
            ConsoleWriteError("Portable app observation: unsafe/unreadable " & $files[$i] & @CRLF)
            Return $r
        EndIf
        If $state = 0 Then
            If $r["missing"] <> "" Then $r["missing"] &= ", "
            $r["missing"] &= $files[$i]
        EndIf
    Next
    $r["status"] = "PRESENT"
    If $r["missing"] <> "" Then $r["status"] = "INCOMPLETE"
    Return $r
EndFunc

Func _PA_Message($r)
    Switch $r["status"]
        Case "MISSING"
            Return _LI("profile.appmissing")
        Case "INCOMPLETE"
            Return _LI("app.incomplete") & $r["missing"]
        Case "PRESENT"
            Return _LI("app.files_present")
        Case Else
            Return _LI("app.unsafe")
    EndSwitch
EndFunc
