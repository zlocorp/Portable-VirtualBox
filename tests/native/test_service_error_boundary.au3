#include "..\..\source\WindowsObservation.au3"
#include <GUIConstantsEx.au3>
; Read-only regression for last-error interference while a GUI is alive.
; The callback deliberately writes the observed GUI error; no service exists
; with this unique name, and no system resource is created or modified.
Global $ticks = 0, $wrong = 0
Func DisturbLastError()
    $ticks += 1
    DllCall($g_WinObsKernel32, "none", "SetLastError", "dword", 1400)
EndFunc
Local $gui = GUICreate("Service error-boundary regression", 360, 100)
GUICtrlCreateLabel("Query-only missing-service checks", 12, 12, 330, 35)
GUISetState(@SW_SHOW, $gui)
Local $name = "PVBoxErrorBoundaryMissing_" & @AutoItPID
AdlibRegister("DisturbLastError", 1)
For $i = 1 To 3000
    Local $r = _WinObsService($name)
    If $r["status"] <> "ABSENT" Or $r["error"] <> 1060 Or $r["stage"] <> "open" Then
        $wrong += 1
        If $wrong <= 5 Then ConsoleWrite("Observed error-boundary failure: status=" & $r["status"] & " error=" & $r["error"] & " stage=" & $r["stage"] & @CRLF)
    EndIf
Next
AdlibUnRegister("DisturbLastError")
GUIDelete($gui)
ConsoleWrite("Native service error-boundary: queries=3000 callbacks=" & $ticks & " failures=" & $wrong & @CRLF)
If $ticks = 0 Then Exit 2
Exit ($wrong > 0)
