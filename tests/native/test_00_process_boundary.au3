#include "..\..\source\WindowsObservation.au3"
; Temporary boundary evidence, not an acceptance test. No private paths printed.
Local $token = _WinObsProcessOpen(@AutoItPID)
Local $e = @error, $x = @extended
ConsoleWrite("PROCESS_BOUNDARY requested_type=" & VarGetType(@AutoItPID) & "; upper_bound=" & 0xFFFFFFFF & "; token=" & $token & "; error=" & $e & "; win32=" & $x & @CRLF)
Local $r = _WinObsProcessFromHandle(Ptr(-1))
ConsoleWrite("PROCESS_BOUNDARY direct_status=" & $r["status"] & "; stage=" & $r["stage"] & "; win32=" & $r["error"] & "; pid_type=" & VarGetType($r["pid"]) & @CRLF)
If $token > 0 Then _WinObsProcessClose($token)
Exit 0
