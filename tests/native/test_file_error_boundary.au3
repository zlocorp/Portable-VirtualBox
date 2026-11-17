#include "..\..\source\LauncherGui.au3"
#include <GUIConstantsEx.au3>
; Read-only stress: callbacks overwrite thread last-error between AutoIt
; statements. Missing files mean exact error 2/3, not ACCESS_DENIED.
Global $ticks = 0, $failures = 0
Func DisturbFileError()
    $ticks += 1
    DllCall("kernel32.dll", "none", "SetLastError", "dword", 5)
EndFunc
Local $g = GUICreate("File attribute error-boundary", 260, 80)
GUICtrlCreateLabel("Read-only native file probes", 15, 12, 220, 24)
GUISetState(@SW_SHOW, $g)
Local $missing = @TempDir & "\PVBox-NotExisting-" & @AutoItPID
If FileExists($missing) Then Exit 2
AdlibRegister("DisturbFileError", 1)
For $i = 1 To 1000
    If _PP_DirectoryState($missing) <> 0 Then $failures += 1
    If _PVI_PathState($missing) <> 0 Then $failures += 1
    If _PBK_PathState($missing) <> 0 Then $failures += 1
    If _LS_FileState($missing) <> 0 Then $failures += 1
    If _PA_FileState(@TempDir, "PVBox-NotExisting-" & @AutoItPID) <> 0 Then $failures += 1
Next
AdlibUnRegister("DisturbFileError")
GUIDelete($g)
ConsoleWrite("Native file last-error boundary: queries=5000 callbacks=" & $ticks & " failed=" & $failures & @CRLF)
If $ticks = 0 Then Exit 2
Exit ($failures > 0)
