#include "..\..\source\LifecycleCoordinator.au3"
Global $live = False
Func BoundaryProbe($q)
    ConsoleWrite("BOUNDARY probe " & $q["verb"] & " live=" & $live & @CRLF)
    Local $r[]
    $r["kind"] = $q["kind"]
    $r["name"] = $q["name"]
    $r["status"] = "ABSENT"
    $r["identity"] = ""
    $r["ticket"] = ""
    If $live Then
        $r["status"] = "PRESENT"
        $r["identity"] = $q["identity"]
        $r["ticket"] = "boundary-ticket-0001"
    EndIf
    Return SetError(0, 0, $r)
EndFunc
Func BoundaryEffect($q)
    ConsoleWrite("BOUNDARY effect " & $q["verb"] & @CRLF)
    Local $r = $q
    $r["outcome"] = "CREATED"
    $r["ticket"] = "boundary-ticket-0001"
    $live = True
    If $q["verb"] == "release" Then
        $live = False
        $r["outcome"] = "RELEASED"
    EndIf
    Return SetError(0, 0, $r)
EndFunc
Func BoundaryStore($q)
    ConsoleWrite("BOUNDARY store " & $q["phase"] & @CRLF)
    Return SetError(0, 0, True)
EndFunc
ConsoleWrite("BOUNDARY invalid session " & _PC_New("bad", BoundaryProbe, BoundaryEffect, BoundaryStore) & @CRLF)
ConsoleWrite("BOUNDARY native callback " & _PC_New("native-callback-test", BoundaryProbe, MsgBox, BoundaryStore) & @CRLF)
Local $token = _PC_New("boundary-coordinator-0001", BoundaryProbe, BoundaryEffect, BoundaryStore)
ConsoleWrite("BOUNDARY new token " & $token & @CRLF)
Local $status = _PC_Status($token)
ConsoleWrite("BOUNDARY status " & $status["state"] & @CRLF)
ConsoleWrite("BOUNDARY acquire " & _PC_Acquire($token, "service", "boundary", "id") & @CRLF)
ConsoleWrite("BOUNDARY release " & _PC_ReleaseNext($token) & @CRLF)
ConsoleWrite("BOUNDARY done " & _PC_ReleaseNext($token) & @CRLF)
