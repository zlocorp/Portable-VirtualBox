#include-once
#include "ManagedProcess.au3"
#include "PortableApp.au3"
#include "HostPreflight.au3"
; First-run app64 FILE preparation only. No driver/UAC/system service effects.
; Python runtime is bundled in the separately compiled offline helper, not
; required on the user's computer. Oracle installer identity is pinned in it.

Func _PAS_Args($root, $installer)
    If Not IsString($installer) Or Not IsString($root) Then Return ""
    If Not _PP_RootSafe($root) Or Not _PP_RootSafe($installer) Then Return ""
    If StringRegExp($root & $installer, '["\x00-\x1f]') Then Return ""
    Return '--installer "' & $installer & '" --root "' & $root & '"'
EndFunc

Func _PAS_CanPrepareRoot($root)
    If Not IsString($root) Or Not _PP_RootSafe($root) Then Return False
    If StringRegExp($root, '["\x00-\x1f]') Then Return False
    If Not _PP_ParentsSafe($root) Then Return False
    If _PA_FileState($root, "Portable-VirtualBox-Setup.exe") <> 1 Then Return False
    ; An existing app64 cannot be overwritten, even if incomplete.
    If _PP_DirectoryState($root & "\app64") <> 0 Then Return False
    Local $installed = _PortableInstalledVBoxDetected()
    If Not IsBool($installed) Or $installed Then Return False
    If _PortableCountExistingServices() <> 0 Or _PortableCountVirtualBoxProcesses() <> 0 Then Return False
    Return True
EndFunc

Func _PAS_CanPrepare($root, $installer)
    If _PAS_Args($root, $installer) == "" Or Not FileExists($installer) Then Return False
    Return _PAS_CanPrepareRoot($root)
EndFunc

Func _PAS_DownloadArgs($root)
    If Not IsString($root) Or Not _PP_RootSafe($root) Then Return ""
    If StringRegExp($root, '["\x00-\x1f]') Then Return ""
    Return '--download --root "' & $root & '"'
EndFunc

; Optional status is a hint for the GUI only, not an app64 readiness receipt.
; Create a new reserved name each attempt; never overwrite stale progress.
Func _PAS_ProgressPath($root)
    If Not _PP_RootSafe($root) Then Return ""
    Local $stamp = @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC
    For $i = 1 To 999
        Local $path = $root & "\.pvbox-setup-" & @AutoItPID & "-" & $stamp & "-" & $i & ".progress"
        If Not FileExists($path) Then Return $path
    Next
    Return ""
EndFunc

Func _PAS_AttachProgress($root, $args, $enabled)
    Local $p = _MP_New()
    If Not IsBool($enabled) Then Return $p
    Local $progress = ""
    If $enabled Then
        $progress = _PAS_ProgressPath($root)
        If $progress == "" Then Return $p
        $args &= ' --progress-file "' & $progress & '"'
    EndIf
    $p = _MP_Start($root & "\Portable-VirtualBox-Setup.exe", $args, $root)
    $p["progress"] = $progress
    Return $p
EndFunc

Func _PAS_StartDownload($root, $showProgress = False)
    If Not _PAS_CanPrepareRoot($root) Then Return _MP_New()
    Local $args = _PAS_DownloadArgs($root)
    If $args == "" Then Return _MP_New()
    Return _PAS_AttachProgress($root, $args, $showProgress)
EndFunc

Func _PAS_Start($root, $installer, $showProgress = False)
    If Not _PAS_CanPrepare($root, $installer) Then Return _MP_New()
    Return _PAS_AttachProgress($root, _PAS_Args($root, $installer), $showProgress)
EndFunc

Func _PAS_ProgressText($p)
    If Not IsMap($p) Or Not MapExists($p, "progress") Or $p["progress"] == "" Then Return ""
    Local $path = $p["progress"]
    Local $size = FileGetSize($path)
    If @error Or $size < 1 Or $size > 80 Then Return ""
    Local $line = StringStripWS(FileRead($path), 3)
    Local $match = StringRegExp($line, "^(DOWNLOAD|VERIFY|EXTRACT|DONE)\|([0-9]{1,13})\|([0-9]{1,13})$", 1)
    If Not IsArray($match) Then Return ""
    Local $bytes = Number($match[1]), $total = Number($match[2])
    If $bytes > 1073741824 Or $total > 1073741824 Or ($total > 0 And $bytes > $total) Then Return ""
    Switch $match[0]
        Case "DOWNLOAD"
            Local $text = _LI("setup.progress_download") & " " & StringFormat("%.1f", $bytes / 1048576) & " MiB"
            If $total > 0 Then $text &= " / " & StringFormat("%.1f", $total / 1048576) & " MiB (" & Int($bytes * 100 / $total) & "%)"
            Return $text
        Case "VERIFY"
            Return _LI("setup.progress_verify")
        Case "EXTRACT"
            Return _LI("setup.progress_extract")
        Case "DONE"
            Return _LI("setup.done")
    EndSwitch
    Return ""
EndFunc

Func _PAS_Complete($root, $exitCode)
    If Not IsInt($exitCode) Or $exitCode <> 0 Then Return False
    Local $app = _PA_Inspect($root)
    Return $app["status"] == "PRESENT" And _PA_FileState($root, "app64\.prepared.json") = 1
EndFunc

; Public CLI is synchronous; GUI starts either worker asynchronously.
Func _PAS_Run($root, $installer)
    Return _PAS_Wait(_PAS_Start($root, $installer), $root)
EndFunc

Func _PAS_RunDownload($root)
    Return _PAS_Wait(_PAS_StartDownload($root), $root)
EndFunc

Func _PAS_Wait($p, $root)
    If $p["status"] <> "STARTED" Then Return 2
    Local $clock = TimerInit()
    While TimerDiff($clock) < 1200000
        Local $status = _MP_Poll($p)
        If $status == "EXITED" Then
            Local $code = $p["exit_code"]
            _MP_Release($p)
            If _PAS_Complete($root, $code) Then Return 0
            If $code = 2 Then Return 2
            Return 3
        EndIf
        If $status <> "PRESENT" Then Return 3 ; unknown child; never assume success
        Sleep(150)
    WEnd
    ; A running nonprivileged preparer may finish later; never kill by name.
    Return 3
EndFunc
