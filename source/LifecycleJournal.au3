#include-once
; Interface checkpoint for regression tests. No Windows operations are implemented.
Func _PJ_New($token)
    Return 0
EndFunc
Func _PJ_Plan(ByRef $j, $name, $identity, $existed, $probeKnown = True)
    Return 0
EndFunc
Func _PJ_Confirm(ByRef $j, $index, $identity, $success, $outcomeKnown = True)
    Return False
EndFunc
Func _PJ_NextCleanup(ByRef $j)
    Return -1
EndFunc
Func _PJ_BeginCleanup(ByRef $j, $index, $identity, $token)
    Return False
EndFunc
Func _PJ_CompleteCleanup(ByRef $j, $index, $success, $absent, $outcomeKnown = True)
    Return False
EndFunc
Func _PJ_Snapshot(ByRef $j)
    Return ""
EndFunc
Func _PJ_InspectSnapshot($text)
    Return 0
EndFunc
Func _PJ_SaveNew(ByRef $j, $path)
    Return False
EndFunc
