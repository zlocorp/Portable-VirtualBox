#include-once
#include "WindowsObservation.au3"
#include "LifecycleJournal.au3"
; Normalize query-only observations for coordinator callbacks. Always return an
; EMPTY ticket: observing a resource cannot prove that this launcher acquired it.
; Descriptors are private diagnostic data, not public logs or file signatures.
Func _PC_FromWindows($observation, $logicalName)
    Local $r[]
    $r["kind"] = "unknown"
    $r["name"] = $logicalName
    $r["status"] = "UNKNOWN"
    $r["identity"] = ""
    $r["ticket"] = ""
    If Not IsMap($observation) Or Not _PJ_Field($logicalName, 112) Then Return $r
    Local $base = StringSplit("kind,status,error,stage", ",", 2)
    For $i = 0 To UBound($base) - 1
        If Not MapExists($observation, $base[$i]) Then Return $r
    Next
    If Not IsString($observation["kind"]) Or Not IsString($observation["status"]) Or Not IsString($observation["stage"]) Then Return $r
    If Not IsInt($observation["error"]) Then Return $r
    Local $kind = $observation["kind"]
    If Not ($kind == "service" Or $kind == "process") Then Return $r
    $r["kind"] = $kind
    If $kind == "service" And $observation["status"] == "ABSENT" Then
        If _WinObsFailure($kind, $observation["stage"], $observation["error"]) == "ABSENT" Then $r["status"] = "ABSENT"
        Return $r
    EndIf
    If $kind == "process" And $observation["status"] == "EXITED" And $observation["error"] = 0 Then
        $r["status"] = "ABSENT"
        Return $r
    EndIf
    If Not ($observation["status"] == "PRESENT") Or $observation["error"] <> 0 Then Return $r
    Local $fields
    If $kind == "service" Then
        If Not _WinObsServiceStable($observation, $observation) Then Return $r
        If Not IsString($observation["name"]) Or Not ($observation["name"] == $logicalName) Then Return $r
        Local $numbers = StringSplit("type,start,error_control,tag,state,pid,checkpoint,wait_hint", ",", 2)
        For $i = 0 To UBound($numbers) - 1
            Local $v = $observation[$numbers[$i]]
            If Not IsInt($v) Or $v < 0 Or $v > 4294967295 Then Return $r
        Next
        Local $strings = StringSplit("name,image,group,dependencies,account,display", ",", 2)
        For $i = 0 To UBound($strings) - 1
            Local $v = $observation[$strings[$i]]
            If Not IsString($v) Or StringRegExp($v, "[\x00-\x1F\x7F]") Then Return $r
        Next
        $fields = StringSplit("name,type,start,error_control,tag,image,group,dependencies,account,display,state,pid", ",", 2)
    Else
        $fields = StringSplit("pid,created,image", ",", 2)
        For $i = 0 To UBound($fields) - 1
            If Not MapExists($observation, $fields[$i]) Then Return $r
        Next
        If Not IsString($observation["created"]) Then Return $r
        If Not StringRegExp($observation["created"], "^[0-9A-Fa-f]{16}$") Then Return $r
        If Not _PortableProcessOwned($observation["pid"], $observation["pid"], _
            $observation["created"], $observation["created"], $observation["image"], $observation["image"], True) Then Return $r
    EndIf
    ; Length-delimited values prevent accidental delimiter collisions.
    Local $identity = $kind & "-observation-v1;"
    For $i = 0 To UBound($fields) - 1
        Local $s = String($observation[$fields[$i]])
        $identity &= $fields[$i] & "=" & StringLen($s) & ":" & $s & ";"
    Next
    If Not _PJ_Field($identity, 4096) Then Return $r
    $r["identity"] = $identity
    $r["status"] = "PRESENT"
    Return SetError(0, 0, $r)
EndFunc
