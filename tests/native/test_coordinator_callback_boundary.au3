#include "..\..\source\LifecycleCoordinator.au3"
Global $n = 0, $failed = 0
Func Check($ok, $label)
    $n += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $label & @CRLF)
    EndIf
EndFunc
Func RewriteRequest(ByRef $q)
    $q["session"] = "changed-session-0001"
    Return $q
EndFunc
Func ReportError($q)
    Return SetError(23, 45, False)
EndFunc
Func WrongArity($a, $b)
    Return True
EndFunc
Local $q[]
$q["session"] = "original-session-0001"
Local $r = _PC_Invoke(RewriteRequest, $q)
Local $error = @error
Check($error = 0 And IsMap($r), "ByRef callback executes with local copy")
If IsMap($r) Then Check($r["session"] == "changed-session-0001", "callback result remains inspectable")
Check($q["session"] == "original-session-0001", "caller context cannot be rewritten through ByRef")
$r = _PC_Invoke(ReportError, $q)
Local $e = @error, $x = @extended
Check($e = 23 And $x = 45 And IsBool($r) And Not $r, "callback error flags preserved exactly")
$r = _PC_Invoke(WrongArity, $q)
$e = @error
Check($e <> 0, "argument-count mismatch is a reported failure")
$r = _PC_Invoke("RewriteRequest", $q)
$e = @error
Check($e <> 0, "string callback identifiers refused")
ConsoleWrite("Native callback boundary checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
