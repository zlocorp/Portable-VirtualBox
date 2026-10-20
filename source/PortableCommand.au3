#include-once
; Interface-only checkpoint: native process runner not implemented.
Func _PXR_Run($exe, $args, $cwd, $timeoutMs)
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["exit_code"] = -1
    $r["output"] = ""
    $r["error_output"] = ""
    $r["pid"] = 0
    Return $r
EndFunc
