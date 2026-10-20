#include-once
#include "RuntimeSafety.au3"
Func _PP_RootSafe($root)
    Return False
EndFunc
Func _PP_Inspect($root)
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["app_present"] = False
    $r["message"] = "interface only"
    Return $r
EndFunc
Func _PP_Ensure($root)
    Return _PP_Inspect($root)
EndFunc
