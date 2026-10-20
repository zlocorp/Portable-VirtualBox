#include "..\..\source\LifecycleCoordinator.au3"
Global $n = 0, $failed = 0, $serial = 0, $token = 0
Global $resources[], $snapshots[], $events = "", $probes = 0, $saves = 0, $creates = 0, $releases = 0
Global $failSave = 0, $raceProbe = 0, $cancelSave = 0, $cancelEffect = False, $receiptMode = "CREATED", $releaseMode = "RELEASED"
Global $unknownProbe = 0, $reenter = False, $nested = "", $badStore = False
Func Check($ok, $label)
    $n += 1
    ConsoleWrite("CHECK " & $n & ": " & $label & @CRLF)
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $label & @CRLF)
    EndIf
EndFunc
Func Reset()
    ConsoleWrite("RESET begin " & $serial & @CRLF)
    Local $empty[]
    $resources = $empty
    $snapshots = $empty
    $events = ""
    $probes = 0
    $saves = 0
    $creates = 0
    $releases = 0
    $failSave = 0
    $raceProbe = 0
    $unknownProbe = 0
    $cancelSave = 0
    $cancelEffect = False
    $receiptMode = "CREATED"
    $releaseMode = "RELEASED"
    $reenter = False
    $nested = ""
    $badStore = False
    $serial += 1
    $token = _PC_New("coordinator-test-" & $serial, Probe, Effect, Store)
    ConsoleWrite("RESET token " & $token & @CRLF)
    Return $token
EndFunc
Func Probe($q)
    $probes += 1
    ConsoleWrite("PROBE " & $probes & " " & $q["name"] & @CRLF)
    $events &= "probe:" & $q["name"] & ";"
    Local $r[]
    $r["kind"] = $q["kind"]
    $r["name"] = $q["name"]
    $r["status"] = "ABSENT"
    $r["identity"] = ""
    $r["ticket"] = ""
    If $probes = $raceProbe Then
        Local $foreign[]
        $foreign["identity"] = "foreign"
        $foreign["ticket"] = "foreign-ticket-0001"
        $resources[$q["name"]] = $foreign
    EndIf
    If MapExists($resources, $q["name"]) Then
        Local $item = $resources[$q["name"]]
        $r["status"] = "PRESENT"
        $r["identity"] = $item["identity"]
        $r["ticket"] = $item["ticket"]
    EndIf
    If $probes = $unknownProbe Then $r["status"] = "UNKNOWN"
    Return SetError(0, 0, $r)
EndFunc
Func Effect($q)
    ConsoleWrite("EFFECT " & $q["verb"] & " " & $q["name"] & @CRLF)
    Local $r = $q
    If $q["verb"] == "acquire" Then
        $creates += 1
        $events &= "acquire:" & $q["name"] & ";"
        $r["outcome"] = $receiptMode
        $r["ticket"] = ""
        If Not ($receiptMode == "NO_EFFECT") Then
            Local $item[]
            $item["identity"] = $q["identity"]
            $item["ticket"] = "capability-ticket-" & $serial & "-" & $creates
            $resources[$q["name"]] = $item
            $r["ticket"] = $item["ticket"]
        EndIf
        If $receiptMode == "WRONG_SESSION" Then
            $r["outcome"] = "CREATED"
            $r["session"] = "foreign-session-0001"
        EndIf
        If $cancelEffect Then _PC_Cancel($token)
    Else
        $releases += 1
        $events &= "release:" & $q["name"] & ";"
        $r["outcome"] = $releaseMode
        If $releaseMode == "RELEASED" Then MapRemove($resources, $q["name"])
    EndIf
    Return SetError(0, 0, $r)
EndFunc
Func Store($q)
    $saves += 1
    ConsoleWrite("STORE " & $saves & " " & $q["phase"] & @CRLF)
    $events &= "save:" & $q["phase"] & ";"
    If $reenter Then
        $reenter = False
        $nested = _PC_Acquire($token, "service", "nested", "nested-id")
    EndIf
    If $saves = $cancelSave Then _PC_Cancel($token)
    If $saves = $failSave Then Return SetError(0, 0, False)
    If $badStore Then Return SetError(0, 0, 1)
    $snapshots[$q["sequence"]] = $q["snapshot"]
    Return SetError(0, 0, True)
EndFunc
Func State()
    Local $s = _PC_Status($token)
    Return $s["state"]
EndFunc

Check(_PC_New("bad", Probe, Effect, Store) = 0, "invalid session denied")
Check(_PC_New("native-callback-test", Probe, MsgBox, Store) = 0, "native callback denied")
Reset()
Check($token > 0, "new session created")
Check(_PC_Acquire($token, "service", "A", "id-a") == "ACQUIRED", "first acquisition")
Check($events == "probe:A;save:ACQUIRE_INTENT;probe:A;acquire:A;probe:A;save:ACQUIRE_RESULT;", "intent and fresh probes bracket acquisition")
Check(_PC_Acquire($token, "service", "a", "id-a") == "BLOCKED", "casefold duplicate blocked")
Check($creates = 1, "duplicate did not dispatch")
Check(_PC_Acquire($token, "service", "B", "id-b") == "ACQUIRED", "second acquisition")
Check(_PC_ReleaseNext($token) == "RELEASED", "release latest")
Check(Not MapExists($resources, "B") And MapExists($resources, "A"), "reverse cleanup order")
Check(_PC_Acquire($token, "service", "C", "id-c") == "BLOCKED", "no acquisition during cleanup")
Check(_PC_ReleaseNext($token) == "RELEASED", "release first")
Check(_PC_ReleaseNext($token) == "DONE", "session completes")
Check(State() == "CLOSED", "closed terminal state")
Check(_PC_ReleaseNext($token) == "DONE" And $releases = 2, "completion idempotent")

Reset()
$raceProbe = 1
Check(_PC_Acquire($token, "service", "A", "id-a") == "BLOCKED", "pre-existing resource blocked")
Check($creates = 0 And $saves = 0, "pre-existing state untouched")
Reset()
$unknownProbe = 1
Check(_PC_Acquire($token, "service", "A", "id-a") == "BLOCKED", "unknown initial state blocks")
Check($creates = 0, "unknown has no effect")
Reset()
$failSave = 1
Check(_PC_Acquire($token, "service", "A", "id-a") == "FROZEN", "intent persistence failure freezes")
Check($creates = 0, "no effect without persisted intent")
Reset()
$failSave = 2
Check(_PC_Acquire($token, "service", "A", "id-a") == "FROZEN", "result persistence failure freezes")
Check($creates = 1 And MapExists($resources, "A"), "created resource retained on storage failure")
Check(_PC_ReleaseNext($token) == "FROZEN" And $releases = 0, "no speculative cleanup after storage failure")
Reset()
$raceProbe = 2
Check(_PC_Acquire($token, "service", "A", "id-a") == "FROZEN", "race after persisted intent blocked")
Check($creates = 0 And MapExists($resources, "A"), "foreign race resource preserved")
Reset()
$receiptMode = "UNKNOWN"
Check(_PC_Acquire($token, "service", "A", "id-a") == "FROZEN", "partial acquisition is uncertain")
Check(_PC_ReleaseNext($token) == "FROZEN" And $releases = 0, "uncertainty not ownership")
Reset()
$receiptMode = "WRONG_SESSION"
Check(_PC_Acquire($token, "service", "A", "id-a") == "FROZEN", "receipt bound to session")
Reset()
Check(_PC_Acquire($token, "service", "A", "id-a") == "ACQUIRED", "partial batch first resource")
$receiptMode = "NO_EFFECT"
Check(_PC_Acquire($token, "service", "B", "id-b") == "FAILED", "known acquisition failure")
Check(_PC_ReleaseNext($token) == "RELEASED" And $releases = 1, "partial batch cleans only confirmed resource")
Check(_PC_ReleaseNext($token) == "DONE", "failed acquisition not released")

Reset()
Check(_PC_Cancel($token), "cancellation accepted")
Check(_PC_Acquire($token, "service", "A", "id-a") == "CANCELLED" And $creates = 0, "early cancellation has no effects")
Reset()
$cancelSave = 1
Check(_PC_Acquire($token, "service", "A", "id-a") == "CANCELLED", "cancel during intent storage")
Check($creates = 0 And $saves = 2, "cancelled intent finalized without effect")
Reset()
$cancelEffect = True
Check(_PC_Acquire($token, "service", "A", "id-a") == "CANCELLED", "cancel during effect reported after completion")
Check($creates = 1 And $saves = 2, "effect result persisted despite cancellation")
Check(_PC_ReleaseNext($token) == "RELEASED", "cancelled session can clean owned resources")
Reset()
$reenter = True
Check(_PC_Acquire($token, "service", "A", "id-a") == "ACQUIRED", "outer operation succeeds")
Check($nested == "BUSY" And $creates = 1, "reentrant operation cannot dispatch")
Reset()
$badStore = True
Check(_PC_Acquire($token, "service", "A", "id-a") == "FROZEN" And $creates = 0, "numeric success is not storage acknowledgement")

Reset()
_PC_Acquire($token, "service", "A", "id-a")
$raceProbe = $probes + 1
Check(_PC_ReleaseNext($token) == "FROZEN" And $releases = 0, "changed cleanup identity blocked")
Reset()
_PC_Acquire($token, "service", "A", "id-a")
$raceProbe = $probes + 2
Check(_PC_ReleaseNext($token) == "FROZEN" And $releases = 0, "identity rechecked after release intent")
Reset()
_PC_Acquire($token, "service", "A", "id-a")
$releaseMode = "NO_EFFECT"
Check(_PC_ReleaseNext($token) == "RETRY", "verified unchanged failed release permits explicit retry")
Check($releases = 1 And MapExists($resources, "A"), "no automatic retry")
$releaseMode = "RELEASED"
Check(_PC_ReleaseNext($token) == "RELEASED" And $releases = 2, "explicit retry succeeds")
Reset()
_PC_Acquire($token, "service", "A", "id-a")
$releaseMode = "UNKNOWN"
Check(_PC_ReleaseNext($token) == "FROZEN", "unknown release outcome freezes")
Check(_PC_ReleaseNext($token) == "FROZEN" And $releases = 1, "unknown release never retried")
Reset()
_PC_Acquire($token, "service", "A", "id-a")
$failSave = $saves + 1
Check(_PC_ReleaseNext($token) == "FROZEN" And $releases = 0, "release cannot precede persisted intent")
Reset()
_PC_Acquire($token, "service", "A", "id-a")
$failSave = $saves + 2
Check(_PC_ReleaseNext($token) == "FROZEN" And $releases = 1, "failed release-result persistence blocks progress")
Local $s = _PC_Status($token)
Local $recovered = _PJ_InspectSnapshot($s["snapshot"])
Check(_PJ_NextCleanup($recovered) = -1, "snapshot recovery remains diagnostic only")
Check(_PC_ReleaseNext(-1) == "BLOCKED", "invalid coordinator token blocked")
ConsoleWrite("Native coordinator checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
