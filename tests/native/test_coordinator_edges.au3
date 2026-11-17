#include "..\..\source\LifecycleCoordinator.au3"
Global $n = 0, $failed = 0, $serial = 0, $token = 0, $live = False, $calls = 0, $saves = 0
Global $probeMode = "VALID", $effectMode = "VALID", $storeMode = "VALID"
Func Check($ok, $label)
    $n += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $label & @CRLF)
    EndIf
EndFunc
Func Probe($q)
    Local $r[]
    $r["kind"] = $q["kind"]
    $r["name"] = $q["name"]
    $r["status"] = "ABSENT"
    $r["identity"] = ""
    $r["ticket"] = ""
    If $live Then
        $r["status"] = "PRESENT"
        $r["identity"] = $q["identity"]
        $r["ticket"] = "edge-capability-0001"
    EndIf
    Switch $probeMode
        Case "SCALAR"
            Return 1
        Case "MISSING"
            MapRemove($r, "identity")
        Case "FOREIGN"
            $r["name"] = "other"
        Case "ERROR"
            Return SetError(5, 0, $r)
        Case "FALSE_ABSENCE"
            $r["identity"] = "nonempty"
        Case "WRONG_TICKET"
            If $live Then $r["ticket"] = "different-ticket-0001"
    EndSwitch
    Return SetError(0, 0, $r)
EndFunc
Func Effect($q)
    $calls += 1
    Local $r = $q
    $r["outcome"] = "CREATED"
    $r["ticket"] = "edge-capability-0001"
    $live = True
    If $q["verb"] == "release" Then
        $r["outcome"] = "RELEASED"
        $live = False
    EndIf
    Switch $effectMode
        Case "SCALAR"
            Return 0
        Case "MISSING"
            MapRemove($r, "outcome")
        Case "SESSION"
            $r["session"] = "foreign-session-0001"
        Case "OPERATION"
            $r["operation"] += 1
        Case "STRING_OPERATION"
            $r["operation"] = String($r["operation"])
        Case "KIND"
            $r["kind"] = "process"
        Case "NAME"
            $r["name"] = "other"
        Case "IDENTITY"
            $r["identity"] = "other"
        Case "VERB"
            $r["verb"] = "other"
        Case "TICKET"
            $r["ticket"] = ""
        Case "FOREIGN_TICKET"
            $r["ticket"] = "foreign-ticket-0001"
        Case "ERROR"
            Return SetError(5, 0, $r)
        Case "NO_EFFECT_LIE"
            $r["outcome"] = "NO_EFFECT"
            $r["ticket"] = ""
    EndSwitch
    Return SetError(0, 0, $r)
EndFunc
Func Store($q)
    $saves += 1
    If $storeMode == "ERROR" Then Return SetError(5, 0, True)
    If $storeMode == "STRING" Then Return SetError(0, 0, "true")
    Return SetError(0, 0, True)
EndFunc
Func WrongArity($first, $second)
    Return True
EndFunc
Func Reset()
    $serial += 1
    $live = False
    $calls = 0
    $saves = 0
    $probeMode = "VALID"
    $effectMode = "VALID"
    $storeMode = "VALID"
    $token = _PC_New("edge-coordinator-" & $serial, Probe, Effect, Store)
EndFunc

Local $bad[7] = [-1, 0, 999999, "1", 1.5, True, Null]
For $i = 0 To UBound($bad) - 1
    Check(_PC_Acquire($bad[$i], "service", "A", "id") == "BLOCKED", "invalid acquire token " & $i)
    Check(_PC_ReleaseNext($bad[$i]) == "BLOCKED", "invalid release token " & $i)
    Check(Not _PC_Cancel($bad[$i]), "invalid cancellation token " & $i)
    Local $s = _PC_Status($bad[$i])
    Check($s["state"] == "INVALID", "invalid status token " & $i)
Next
Reset()
Check(_PC_New("EDGE-COORDINATOR-1", Probe, Effect, Store) = 0, "session identifiers are not reused with different case")
Check(_PC_New("string-callback-0001", "Probe", Effect, Store) = 0, "callback names not accepted from strings")
Check(_PC_Acquire($token, "registry", "A", "id") == "BLOCKED", "unsupported resource kind refused")
Check(_PC_Acquire($token, "service", "bad/name", "id") == "BLOCKED", "invalid logical resource name refused")
Check(_PC_Acquire($token, "service", "A", "") == "BLOCKED", "missing descriptor refused")
Check($calls = 0 And $saves = 0, "invalid input has no effects or persistence")

Local $probeCases = StringSplit("SCALAR,MISSING,FOREIGN,ERROR,FALSE_ABSENCE", ",", 2)
For $i = 0 To UBound($probeCases) - 1
    Reset()
    $probeMode = $probeCases[$i]
    Check(_PC_Acquire($token, "service", "A", "id") == "BLOCKED", "bad initial probe " & $probeMode)
    Check($calls = 0 And $saves = 0, "invalid probe cannot dispatch " & $probeMode)
Next
Local $receiptCases = StringSplit("SCALAR,MISSING,SESSION,OPERATION,STRING_OPERATION,KIND,NAME,IDENTITY,VERB,TICKET,FOREIGN_TICKET,ERROR,NO_EFFECT_LIE", ",", 2)
For $i = 0 To UBound($receiptCases) - 1
    Reset()
    $effectMode = $receiptCases[$i]
    Check(_PC_Acquire($token, "service", "A", "id") == "FROZEN", "bad acquire receipt " & $effectMode)
    Check($calls = 1 And _PC_ReleaseNext($token) == "FROZEN", "invalid receipt never grants cleanup " & $effectMode)
Next
For $i = 0 To 1
    Reset()
    If $i = 0 Then
        $storeMode = "ERROR"
    Else
        $storeMode = "STRING"
    EndIf
    Check(_PC_Acquire($token, "service", "A", "id") == "FROZEN" And $calls = 0, "store acknowledgement strict " & $storeMode)
Next
Reset()
Check(_PC_Acquire($token, "service", "A", "id") == "ACQUIRED", "replacement fixture acquired")
$probeMode = "WRONG_TICKET"
Check(_PC_ReleaseNext($token) == "FROZEN" And $calls = 1, "same descriptor with changed capability blocked")
Reset()
_PC_Acquire($token, "service", "A", "id")
$effectMode = "FOREIGN_TICKET"
Check(_PC_ReleaseNext($token) == "FROZEN" And $calls = 2, "release receipt bound to acquisition capability")

; Programming errors at callback boundaries must be reported, not crash the host.
$token = _PC_New("wrong-arity-probe-0001", WrongArity, Effect, Store)
Check(_PC_Acquire($token, "service", "A", "id") == "BLOCKED", "probe argument-count failure is unknown")
$live = False
$token = _PC_New("wrong-arity-store-0001", Probe, Effect, WrongArity)
Check(_PC_Acquire($token, "service", "A", "id") == "FROZEN", "store argument-count failure freezes")
$token = _PC_New("wrong-arity-effect-0001", Probe, WrongArity, Store)
Check(_PC_Acquire($token, "service", "A", "id") == "FROZEN", "effect argument-count failure freezes")
ConsoleWrite("Native coordinator edge checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
