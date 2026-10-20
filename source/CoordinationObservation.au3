#include-once
#include "WindowsObservation.au3"
#include "LifecycleJournal.au3"
; Interface-only checkpoint: query data must never mint an ownership ticket.
Func _PC_FromWindows($observation, $logicalName)
    Local $r[]
    $r["kind"] = "service"
    $r["name"] = $logicalName
    $r["status"] = "UNKNOWN"
    $r["identity"] = ""
    $r["ticket"] = ""
    Return $r
EndFunc
