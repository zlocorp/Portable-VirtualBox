#include-once
#include "LifecycleJournal.au3"
; Interface-only red checkpoint. No effects are implemented here.
Func _PC_New($session, $probe, $effect, $store, $directory = "")
    Return 0
EndFunc
Func _PC_Acquire($token, $kind, $name, $identity)
    Return "BLOCKED"
EndFunc
Func _PC_ReleaseNext($token)
    Return "BLOCKED"
EndFunc
Func _PC_Cancel($token)
    Return False
EndFunc
Func _PC_Status($token)
    Local $r[]
    $r["state"] = "INVALID"
    $r["reason"] = ""
    $r["snapshot"] = ""
    $r["sequence"] = 0
    Return $r
EndFunc
Func _PC_SaveFile($request)
    Return False
EndFunc
