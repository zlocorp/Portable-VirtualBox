#include "..\..\source\LifecycleCoordinator.au3"
Func BoundaryProbe($q)
    Local $r[]
    $r["kind"] = $q["kind"]
    $r["name"] = $q["name"]
    $r["status"] = "ABSENT"
    $r["identity"] = ""
    $r["ticket"] = ""
    Return $r
EndFunc
Func BoundaryEffect($q)
    Local $r = $q
    $r["outcome"] = "NO_EFFECT"
    Return $r
EndFunc
Func BoundaryStore($q)
    ConsoleWrite("BOUNDARY store callback reached" & @CRLF)
    Return True
EndFunc
ConsoleWrite("BOUNDARY begin" & @CRLF)
Local $q[]
$q["kind"] = "service"
$q["name"] = "boundary"
Local $fn = BoundaryProbe
Local $r = $fn($q)
ConsoleWrite("BOUNDARY direct callback OK" & @CRLF)
Local $holder[]
$holder["fn"] = $fn
ConsoleWrite("BOUNDARY map callback stored" & @CRLF)
Local $copy = $holder, $fn2 = $copy["fn"]
$r = $fn2($q)
ConsoleWrite("BOUNDARY copied callback OK" & @CRLF)
Local $token = _PC_New("boundary-coordinator-0001", BoundaryProbe, BoundaryEffect, BoundaryStore)
ConsoleWrite("BOUNDARY new token " & $token & @CRLF)
Local $status = _PC_Status($token)
ConsoleWrite("BOUNDARY status " & $status["state"] & @CRLF)
ConsoleWrite("BOUNDARY acquire " & _PC_Acquire($token, "service", "boundary", "id") & @CRLF)
