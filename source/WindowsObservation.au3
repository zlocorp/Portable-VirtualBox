#include-once
; Interface checkpoint for red/green native tests. No OS effects.
Func _WinObsResult($kind, $status = "UNKNOWN", $error = 0, $stage = "")
    Local $r[]
    $r["kind"] = $kind
    $r["status"] = $status
    $r["error"] = $error
    $r["stage"] = $stage
    $r["pid"] = 0
    $r["created"] = ""
    $r["image"] = ""
    $r["state"] = 0
    $r["build"] = 0
    $r["product_type"] = 0
    Return $r
EndFunc
Func _WinObsFailure($kind, $stage, $error)
    Return "UNKNOWN"
EndFunc
Func _WinObsWorkstationAccepted($build, $product)
    Return False
EndFunc
Func _WinObsService($name)
    Return _WinObsResult("service")
EndFunc
Func _WinObsServiceStable(ByRef $first, ByRef $second)
    Return False
EndFunc
Func _WinObsProcessOpen($pid)
    Return 0
EndFunc
Func _WinObsProcessRead($token)
    Return _WinObsResult("process")
EndFunc
Func _WinObsProcessMatches($token, ByRef $reference)
    Return False
EndFunc
Func _WinObsProcessClose($token)
    Return False
EndFunc
Func _WinObsOS()
    Return _WinObsResult("os")
EndFunc
Func _WinObsInstallation()
    Return _WinObsResult("installation")
EndFunc
