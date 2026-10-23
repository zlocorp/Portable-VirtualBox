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

Func _PAS_CanPrepare($root, $installer)
    If _PAS_Args($root, $installer) == "" Then Return False
    If Not _PP_ParentsSafe($root) Or Not FileExists($installer) Then Return False
    If _PA_FileState($root, "Portable-VirtualBox-Setup.exe") <> 1 Then Return False
    ; A partial app64 must not be overwritten. Explicit user inspection only.
    If _PP_DirectoryState($root & "\app64") <> 0 Then Return False
    Local $installed = _PortableInstalledVBoxDetected()
    If Not IsBool($installed) Or $installed Then Return False
    If _PortableCountExistingServices() <> 0 Or _PortableCountVirtualBoxProcesses() <> 0 Then Return False
    Return True
EndFunc

Func _PAS_Start($root, $installer)
    If Not _PAS_CanPrepare($root, $installer) Then Return _MP_New()
    Return _MP_Start($root & "\Portable-VirtualBox-Setup.exe", _PAS_Args($root, $installer), $root)
EndFunc

Func _PAS_Complete($root, $exitCode)
    If Not IsInt($exitCode) Or $exitCode <> 0 Then Return False
    Local $app = _PA_Inspect($root)
    Return $app["status"] == "PRESENT" And _PA_FileState($root, "app64\.prepared.json") = 1
EndFunc

; Public CLI is synchronous; the GUI uses _PAS_Start directly and polls it.
Func _PAS_Run($root, $installer)
    Local $p = _PAS_Start($root, $installer)
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
