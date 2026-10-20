#include-once
#include "LifecycleJournal.au3"
; Internal orchestration for trusted compiled callbacks, NOT a privilege boundary.
; No real Windows effect adapter is registered by the launcher. Tokens cannot be
; restored from snapshots. A receipt ticket must bind exclusive creation to the
; exact resource capability held by its adapter, not just a matching name/path.
Global $g_PC_Contexts[], $g_PC_Sessions[], $g_PC_Next = 1

Func _PC_Known($token)
    If Not IsInt($token) Then Return False
    If $token < 1 Or $token >= $g_PC_Next Then Return False
    Return MapExists($g_PC_Contexts, $token)
EndFunc

Func _PC_Set($token, $key, $value)
    Local $c = $g_PC_Contexts[$token]
    $c[$key] = $value
    $g_PC_Contexts[$token] = $c
EndFunc

Func _PC_New($session, $probe, $effect, $store, $directory = "")
    If Not _PJ_Token($session) Then Return 0
    If IsFunc($probe) <> 1 Or IsFunc($effect) <> 1 Or IsFunc($store) <> 1 Then Return 0
    If Not IsString($directory) Then Return 0
    If $g_PC_Next > 128 Or MapExists($g_PC_Sessions, StringLower($session)) Then Return 0
    Local $c[], $ops[]
    $c["session"] = $session
    $c["probe"] = $probe
    $c["effect"] = $effect
    $c["store"] = $store
    $c["directory"] = $directory
    $c["journal"] = _PJ_New($session)
    $c["ops"] = $ops
    $c["state"] = "OPEN"
    $c["reason"] = ""
    $c["cancelled"] = False
    $c["busy"] = False
    $c["sequence"] = 0
    Local $token = $g_PC_Next
    $g_PC_Next += 1
    $g_PC_Contexts[$token] = $c
    $g_PC_Sessions[StringLower($session)] = True
    Return $token
EndFunc

Func _PC_Status($token)
    Local $r[]
    $r["state"] = "INVALID"
    $r["reason"] = "invalid-token"
    $r["snapshot"] = ""
    $r["sequence"] = 0
    $r["cancelled"] = False
    If Not _PC_Known($token) Then Return $r
    Local $c = $g_PC_Contexts[$token], $j = $c["journal"]
    $r["state"] = $c["state"]
    $r["reason"] = $c["reason"]
    $r["sequence"] = $c["sequence"]
    $r["cancelled"] = $c["cancelled"]
    $r["snapshot"] = _PJ_Snapshot($j)
    Return $r
EndFunc

Func _PC_Cancel($token)
    If Not _PC_Known($token) Then Return False
    Local $c = $g_PC_Contexts[$token]
    If $c["state"] == "CLOSED" Or $c["state"] == "FROZEN" Then Return False
    _PC_Set($token, "cancelled", True)
    Return True
EndFunc

Func _PC_Freeze($token, $reason)
    _PC_Set($token, "state", "FROZEN")
    _PC_Set($token, "reason", $reason)
    Return "FROZEN"
EndFunc

Func _PC_Request($token, $op, $index, $verb)
    Local $c = $g_PC_Contexts[$token], $q = $op
    $q["session"] = $c["session"]
    $q["operation"] = $index
    $q["verb"] = $verb
    Return $q
EndFunc

Func _PC_Save($token, ByRef $j, $phase)
    _PC_Set($token, "journal", $j)
    Local $c = $g_PC_Contexts[$token]
    If $c["sequence"] >= 4096 Then
        _PC_Freeze($token, "snapshot-limit")
        Return False
    EndIf
    Local $q[]
    $q["session"] = $c["session"]
    $q["sequence"] = $c["sequence"] + 1
    $q["phase"] = $phase
    $q["directory"] = $c["directory"]
    $q["journal"] = $j
    $q["snapshot"] = _PJ_Snapshot($j)
    If @error Then
        _PC_Freeze($token, "invalid-journal")
        Return False
    EndIf
    _PC_Set($token, "sequence", $q["sequence"])
    Local $fn = $c["store"]
    Local $ok = $fn($q)
    Local $error = @error
    If $error Or Not IsBool($ok) Or Not $ok Then
        _PC_Freeze($token, "persistence-" & $phase)
        Return False
    EndIf
    Return True
EndFunc

Func _PC_Probe($token, $q)
    Local $unknown[]
    $unknown["kind"] = $q["kind"]
    $unknown["name"] = $q["name"]
    $unknown["status"] = "UNKNOWN"
    $unknown["identity"] = ""
    $unknown["ticket"] = ""
    Local $c = $g_PC_Contexts[$token], $fn = $c["probe"]
    Local $r = $fn($q)
    Local $error = @error
    If $error Or Not IsMap($r) Then Return $unknown
    Local $keys = StringSplit("kind,name,status,identity,ticket", ",", 2)
    For $i = 0 To UBound($keys) - 1
        If Not MapExists($r, $keys[$i]) Then Return $unknown
        If Not IsString($r[$keys[$i]]) Then Return $unknown
    Next
    If Not ($r["kind"] == $q["kind"]) Or Not ($r["name"] == $q["name"]) Then Return $unknown
    Switch $r["status"]
        Case "ABSENT"
            If Not ($r["identity"] == "") Or Not ($r["ticket"] == "") Then Return $unknown
        Case "PRESENT"
            If Not _PJ_Field($r["identity"], 4096) Then Return $unknown
        Case Else
            Return $unknown
    EndSwitch
    Return $r
EndFunc

Func _PC_ReceiptValid($r, $q, $acquire)
    If Not IsMap($r) Then Return False
    Local $keys = StringSplit("session,kind,name,identity,verb,outcome,ticket", ",", 2)
    For $i = 0 To UBound($keys) - 1
        If Not MapExists($r, $keys[$i]) Then Return False
        If Not IsString($r[$keys[$i]]) Then Return False
    Next
    If Not MapExists($r, "operation") Then Return False
    If Not IsInt($r["operation"]) Or $r["operation"] <> $q["operation"] Then Return False
    For $i = 0 To 4
        If Not ($r[$keys[$i]] == $q[$keys[$i]]) Then Return False
    Next
    If $acquire Then
        If $r["outcome"] == "CREATED" Then Return _PJ_Token($r["ticket"])
        Return $r["outcome"] == "NO_EFFECT" And $r["ticket"] == ""
    EndIf
    If Not _PJ_Token($q["ticket"]) Or Not ($r["ticket"] == $q["ticket"]) Then Return False
    Return $r["outcome"] == "RELEASED" Or $r["outcome"] == "NO_EFFECT"
EndFunc

Func _PC_Matches($observation, $q)
    Return $observation["status"] == "PRESENT" And $observation["identity"] == $q["identity"] And _
        _PJ_Token($q["ticket"]) And $observation["ticket"] == $q["ticket"]
EndFunc

Func _PC_Uncertain($token, ByRef $j, $index, $reason)
    Switch $j[$index][2]
        Case "PLANNED"
            _PJ_Confirm($j, $index, "", False, False)
        Case "OWNED"
            _PJ_BeginCleanup($j, $index, "", $j[0][1])
        Case "RELEASING"
            _PJ_CompleteCleanup($j, $index, False, False, False)
    EndSwitch
    _PC_Freeze($token, $reason)
    _PC_Save($token, $j, "UNCERTAIN")
    Return "FROZEN"
EndFunc

Func _PC_Acquire($token, $kind, $name, $identity)
    If Not _PC_Known($token) Then Return "BLOCKED"
    Local $c = $g_PC_Contexts[$token]
    If $c["busy"] Then Return "BUSY"
    If $c["state"] == "FROZEN" Then Return "FROZEN"
    If $c["cancelled"] Then Return "CANCELLED"
    If Not ($c["state"] == "OPEN") Then Return "BLOCKED"
    If Not IsString($kind) Or Not ($kind == "service" Or $kind == "process") Then Return "BLOCKED"
    If Not _PJ_Field($name, 112) Or Not _PJ_Field($identity, 4096) Then Return "BLOCKED"
    If Not StringRegExp($name, "^[A-Za-z0-9_.:-]+$") Then Return "BLOCKED"
    _PC_Set($token, "busy", True)
    Local $result = _PC_AcquireLocked($token, $kind, $name, $identity)
    _PC_Set($token, "busy", False)
    Return $result
EndFunc

Func _PC_AcquireLocked($token, $kind, $name, $identity)
    Local $c = $g_PC_Contexts[$token], $j = $c["journal"], $ops = $c["ops"], $op[]
    $op["kind"] = $kind
    $op["name"] = $name
    $op["identity"] = $identity
    $op["ticket"] = ""
    Local $q = _PC_Request($token, $op, $j[0][2] + 1, "acquire")
    Local $before = _PC_Probe($token, $q)
    If Not ($before["status"] == "ABSENT") Then Return "BLOCKED"
    $c = $g_PC_Contexts[$token]
    If $c["cancelled"] Then Return "CANCELLED"
    Local $index = _PJ_Plan($j, $kind & ":" & $name, $identity, False, True)
    If $index = 0 Then Return "BLOCKED"
    $ops[$index] = $op
    _PC_Set($token, "ops", $ops)
    If Not _PC_Save($token, $j, "ACQUIRE_INTENT") Then Return "FROZEN"
    Local $fresh = _PC_Probe($token, $q)
    If Not ($fresh["status"] == "ABSENT") Then Return _PC_Uncertain($token, $j, $index, "acquire-recheck")
    $c = $g_PC_Contexts[$token]
    If $c["cancelled"] Then
        _PJ_Confirm($j, $index, "", False, True)
        _PC_Set($token, "state", "CLEANUP")
        If Not _PC_Save($token, $j, "ACQUIRE_CANCELLED") Then Return "FROZEN"
        Return "CANCELLED"
    EndIf
    Local $fn = $c["effect"]
    Local $receipt = $fn($q)
    Local $error = @error
    Local $valid = Not $error And _PC_ReceiptValid($receipt, $q, True)
    If $valid Then $q["ticket"] = $receipt["ticket"]
    Local $after = _PC_Probe($token, $q)
    If Not $valid Then Return _PC_Uncertain($token, $j, $index, "acquire-receipt")
    If $receipt["outcome"] == "CREATED" And _PC_Matches($after, $q) Then
        If Not _PJ_Confirm($j, $index, $after["identity"], True, True) Then Return _PC_Uncertain($token, $j, $index, "acquire-confirm")
        $op["ticket"] = $receipt["ticket"]
        $ops[$index] = $op
        _PC_Set($token, "ops", $ops)
        If Not _PC_Save($token, $j, "ACQUIRE_RESULT") Then Return "FROZEN"
        $c = $g_PC_Contexts[$token]
        If $c["cancelled"] Then
            _PC_Set($token, "state", "CLEANUP")
            Return "CANCELLED"
        EndIf
        Return "ACQUIRED"
    EndIf
    If $receipt["outcome"] == "NO_EFFECT" And $after["status"] == "ABSENT" Then
        _PJ_Confirm($j, $index, "", False, True)
        _PC_Set($token, "state", "CLEANUP")
        If Not _PC_Save($token, $j, "ACQUIRE_RESULT") Then Return "FROZEN"
        Return "FAILED"
    EndIf
    Return _PC_Uncertain($token, $j, $index, "acquire-outcome")
EndFunc

Func _PC_ReleaseNext($token)
    If Not _PC_Known($token) Then Return "BLOCKED"
    Local $c = $g_PC_Contexts[$token]
    If $c["busy"] Then Return "BUSY"
    If $c["state"] == "FROZEN" Then Return "FROZEN"
    If $c["state"] == "CLOSED" Then Return "DONE"
    _PC_Set($token, "busy", True)
    Local $result = _PC_ReleaseLocked($token)
    _PC_Set($token, "busy", False)
    Return $result
EndFunc

Func _PC_ReleaseLocked($token)
    Local $c = $g_PC_Contexts[$token], $j = $c["journal"], $ops = $c["ops"]
    Local $index = _PJ_NextCleanup($j)
    If $index < 0 Then Return _PC_Freeze($token, "journal-blocked")
    _PC_Set($token, "state", "CLEANUP")
    If $index = 0 Then
        If Not _PC_Save($token, $j, "SESSION_CLOSED") Then Return "FROZEN"
        _PC_Set($token, "state", "CLOSED")
        Return "DONE"
    EndIf
    If Not MapExists($ops, $index) Then Return _PC_Freeze($token, "missing-capability")
    Local $op = $ops[$index], $q = _PC_Request($token, $op, $index, "release")
    Local $fresh = _PC_Probe($token, $q)
    If Not _PC_Matches($fresh, $q) Then Return _PC_Uncertain($token, $j, $index, "release-identity")
    If Not _PJ_BeginCleanup($j, $index, $fresh["identity"], $c["session"]) Then Return _PC_Uncertain($token, $j, $index, "release-begin")
    If Not _PC_Save($token, $j, "RELEASE_INTENT") Then Return "FROZEN"
    $fresh = _PC_Probe($token, $q)
    If Not _PC_Matches($fresh, $q) Then Return _PC_Uncertain($token, $j, $index, "release-recheck")
    Local $fn = $c["effect"]
    Local $receipt = $fn($q)
    Local $error = @error
    Local $valid = Not $error And _PC_ReceiptValid($receipt, $q, False)
    Local $after = _PC_Probe($token, $q)
    If Not $valid Then Return _PC_Uncertain($token, $j, $index, "release-receipt")
    If $receipt["outcome"] == "RELEASED" And $after["status"] == "ABSENT" Then
        If Not _PJ_CompleteCleanup($j, $index, True, True, True) Then Return _PC_Uncertain($token, $j, $index, "release-confirm")
        If Not _PC_Save($token, $j, "RELEASE_RESULT") Then Return "FROZEN"
        Return "RELEASED"
    EndIf
    If $receipt["outcome"] == "NO_EFFECT" And _PC_Matches($after, $q) Then
        _PJ_CompleteCleanup($j, $index, False, False, True)
        If Not _PC_Save($token, $j, "RELEASE_RETRY") Then Return "FROZEN"
        Return "RETRY"
    EndIf
    Return _PC_Uncertain($token, $j, $index, "release-outcome")
EndFunc

; The caller owns an existing private directory. Check its leaf attributes,
; create a fresh sequenced file exclusively, and flush before acknowledging.
; Parent topology against a same-account/admin attacker is outside this contract.
Func _PC_SaveFile($request)
    If Not IsMap($request) Then Return False
    Local $keys = StringSplit("session,sequence,directory,journal,snapshot", ",", 2)
    For $i = 0 To UBound($keys) - 1
        If Not MapExists($request, $keys[$i]) Then Return False
    Next
    If Not _PJ_Token($request["session"]) Or Not IsInt($request["sequence"]) Then Return False
    If $request["sequence"] < 1 Or $request["sequence"] > 4096 Then Return False
    Local $j = $request["journal"], $directory = $request["directory"]
    If Not _PJ_Valid($j) Or Not IsString($request["snapshot"]) Then Return False
    If Not ($j[0][1] == $request["session"]) Then Return False
    If Not (_PJ_Snapshot($j) == $request["snapshot"]) Then Return False
    If Not IsString($directory) Or Not StringRegExp($directory, "^[A-Za-z]:\\") Then Return False
    If Not _PortableSafeRelativePath(StringTrimLeft($directory, 3)) Then Return False
    Local $a = DllCall("kernel32.dll", "dword", "GetFileAttributesW", "wstr", $directory)
    If @error Then Return False
    If $a[0] = 4294967295 Or $a[0] = -1 Then Return False
    If BitAND($a[0], 0x10) = 0 Or BitAND($a[0], 0x400) <> 0 Then Return False
    Local $path = $directory & "\" & $request["session"] & "-" & StringFormat("%06d", $request["sequence"]) & ".tsv"
    Return _PJ_SaveNew($j, $path)
EndFunc
