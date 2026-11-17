#include "..\..\source\WindowsObservation.au3"
; A coordinator review found an invalid-negative-token native map crash.
; The existing process-query API must enforce the same boundary independently.
Global $n = 0, $failed = 0
Func Check($ok, $label)
    $n += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $label & @CRLF)
    EndIf
EndFunc
Local $own = _WinObsProcessOpen(@AutoItPID)
Check($own > 0, "self query acquired before invalid-token checks")
ConsoleWrite("Process-token regression: querying negative token" & @CRLF)
Local $bad[7] = [-1, -2147483648, 0, 999999, "1", True, 1.5]
For $i = 0 To UBound($bad) - 1
    Local $r = _WinObsProcessRead($bad[$i])
    Check($r["status"] == "UNKNOWN", "invalid query token " & $i)
    Check(Not _WinObsProcessClose($bad[$i]), "invalid close token " & $i)
Next
Local $live = _WinObsProcessRead($own)
Check($live["status"] == "PRESENT", "invalid tokens preserve retained handle")
Check(_WinObsProcessClose($own), "own handle closed normally")
ConsoleWrite("Native process-token regression checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
