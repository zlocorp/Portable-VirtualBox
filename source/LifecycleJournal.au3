#include-once
#include "RuntimeSafety.au3"
; Lifecycle decisions only. No service, driver, registry or process mutation.
; The future OS adapter must verify identities and persist intent BEFORE effects.
; A disk snapshot is diagnostic evidence, never authority to resume cleanup.

Func _PJ_Field($s, $iLimit)
    If Not IsString($s) Then Return False
    Return StringLen($s) > 0 And StringLen($s) <= $iLimit And Not StringRegExp($s, "[\x00-\x1F\x7F]")
EndFunc

Func _PJ_Token($s)
    If Not IsString($s) Then Return False
    Return StringRegExp($s, "^[A-Za-z0-9_-]{16,128}$") = 1
EndFunc

Func _PJ_Valid(ByRef $j)
    If Not IsArray($j) Then Return False
    If UBound($j, 0) <> 2 Then Return False
    If UBound($j, 1) < 1 Or UBound($j, 2) <> 4 Then Return False
    If Not ($j[0][0] == "PVJ1") Or Not _PJ_Token($j[0][1]) Then Return False
    If Not IsInt($j[0][2]) Then Return False
    Local $n = $j[0][2]
    If $n < 0 Or $n > 128 Or UBound($j, 1) <> $n + 1 Then Return False
    If Not StringRegExp($j[0][3], "^(ACQUIRE|CLEANUP|READONLY)$") Then Return False
    For $i = 1 To $n
        If Not _PJ_Field($j[$i][0], 128) Or Not _PJ_Field($j[$i][1], 4096) Then Return False
        If Not StringRegExp($j[$i][0], "^[A-Za-z0-9_.:-]+$") Then Return False
        If Not StringRegExp($j[$i][2], "^(PLANNED|OWNED|FAILED|RELEASING|RELEASED|UNCERTAIN)$") Then Return False
        If Not IsInt($j[$i][3]) Or $j[$i][3] <> $i Then Return False
        For $k = 1 To $i - 1
            If StringLower($j[$k][0]) == StringLower($j[$i][0]) Then Return False
        Next
    Next
    Return True
EndFunc

Func _PJ_Index(ByRef $j, $i)
    If Not _PJ_Valid($j) Or Not IsInt($i) Then Return False
    Return $i >= 1 And $i <= $j[0][2]
EndFunc

Func _PJ_New($sSession)
    If Not _PJ_Token($sSession) Then Return SetError(1, 0, 0)
    Local $j[1][4] = [["PVJ1", $sSession, 0, "ACQUIRE"]]
    Return $j
EndFunc

Func _PJ_NextCleanup(ByRef $j)
    If Not _PJ_Valid($j) Then Return -1
    If $j[0][3] == "READONLY" Then Return -1
    For $i = 1 To $j[0][2]
        If StringRegExp($j[$i][2], "^(PLANNED|RELEASING|UNCERTAIN)$") Then Return -1
    Next
    For $i = $j[0][2] To 1 Step -1
        If $j[$i][2] == "OWNED" Then Return $i
    Next
    Return 0
EndFunc

Func _PJ_Plan(ByRef $j, $sName, $sExpectedIdentity, $bExisted, $bProbeKnown = True)
    If Not _PJ_Valid($j) Then Return 0
    If Not IsBool($bExisted) Or Not IsBool($bProbeKnown) Then Return 0
    If $bExisted Or Not $bProbeKnown Or Not ($j[0][3] == "ACQUIRE") Then Return 0
    If _PJ_NextCleanup($j) = -1 Or $j[0][2] >= 128 Then Return 0
    If Not _PJ_Field($sName, 128) Or Not _PJ_Field($sExpectedIdentity, 4096) Then Return 0
    If Not StringRegExp($sName, "^[A-Za-z0-9_.:-]+$") Then Return 0
    For $i = 1 To $j[0][2]
        If StringLower($j[$i][0]) == StringLower($sName) Then Return 0
    Next
    Local $n = $j[0][2] + 1
    ReDim $j[$n + 1][4]
    $j[0][2] = $n
    $j[$n][0] = $sName
    $j[$n][1] = $sExpectedIdentity
    $j[$n][2] = "PLANNED"
    $j[$n][3] = $n
    Return $n
EndFunc

; A known failed acquisition means the adapter VERIFIED that no resource exists.
; An error exit code without a successful absence probe is an unknown outcome.
Func _PJ_Confirm(ByRef $j, $i, $sObservedIdentity, $bSuccess, $bOutcomeKnown = True)
    If Not _PJ_Index($j, $i) Then Return False
    If Not ($j[0][3] == "ACQUIRE") Or Not ($j[$i][2] == "PLANNED") Then Return False
    If Not IsBool($bSuccess) Or Not IsBool($bOutcomeKnown) Then Return False
    $j[$i][2] = "UNCERTAIN"
    If Not $bOutcomeKnown Then Return False
    If Not $bSuccess Then
        If Not IsString($sObservedIdentity) Or $sObservedIdentity <> "" Then Return False
        $j[$i][2] = "FAILED"
        Return True
    EndIf
    If Not _PJ_Field($sObservedIdentity, 4096) Then Return False
    If Not ($sObservedIdentity == $j[$i][1]) Then Return False
    $j[$i][2] = "OWNED"
    Return True
EndFunc

Func _PJ_BeginCleanup(ByRef $j, $i, $sFreshIdentity, $sSession)
    If Not _PJ_Index($j, $i) Then Return False
    If Not _PJ_Token($sSession) Or Not ($sSession == $j[0][1]) Then Return False
    If _PJ_NextCleanup($j) <> $i Then Return False
    If Not _PJ_Field($sFreshIdentity, 4096) Or Not ($sFreshIdentity == $j[$i][1]) Then
        $j[$i][2] = "UNCERTAIN"
        Return False
    EndIf
    $j[0][3] = "CLEANUP"
    $j[$i][2] = "RELEASING"
    Return True
EndFunc

; False/False with known=True requires a VERIFIED unchanged resource and permits
; retry; unknown state always blocks. Success requires a verified absence probe.
Func _PJ_CompleteCleanup(ByRef $j, $i, $bSuccess, $bAbsent, $bOutcomeKnown = True)
    If Not _PJ_Index($j, $i) Then Return False
    If Not ($j[0][3] == "CLEANUP") Or Not ($j[$i][2] == "RELEASING") Then Return False
    If Not IsBool($bSuccess) Or Not IsBool($bAbsent) Or Not IsBool($bOutcomeKnown) Then Return False
    $j[$i][2] = "UNCERTAIN"
    If Not $bOutcomeKnown Then Return False
    If $bSuccess And $bAbsent Then
        $j[$i][2] = "RELEASED"
        Return True
    EndIf
    If Not $bSuccess And Not $bAbsent Then
        $j[$i][2] = "OWNED"
        Return True
    EndIf
    Return False
EndFunc

Func _PJ_Snapshot(ByRef $j)
    If Not _PJ_Valid($j) Then Return SetError(1, 0, "")
    Local $s = "PVJ1" & @TAB & $j[0][1] & @TAB & $j[0][3] & @TAB & $j[0][2] & @CRLF
    For $i = 1 To $j[0][2]
        $s &= $i & @TAB & $j[$i][0] & @TAB & $j[$i][1] & @TAB & $j[$i][2] & @CRLF
    Next
    Return $s & "END" & @CRLF
EndFunc

Func _PJ_InspectSnapshot($s)
    If Not IsString($s) Then Return SetError(1, 0, 0)
    If StringLen($s) > 600000 Or StringRight($s, 5) <> "END" & @CRLF Then Return SetError(1, 0, 0)
    Local $lines = StringSplit(StringTrimRight($s, 2), @CRLF, 3)
    If UBound($lines) < 2 Then Return SetError(1, 0, 0)
    Local $header = StringSplit($lines[0], @TAB, 2)
    If UBound($header) <> 4 Then Return SetError(1, 0, 0)
    If Not ($header[0] == "PVJ1") Or Not _PJ_Token($header[1]) Then Return SetError(1, 0, 0)
    If Not StringRegExp($header[2], "^(ACQUIRE|CLEANUP|READONLY)$") Then Return SetError(1, 0, 0)
    If Not StringRegExp($header[3], "^(0|[1-9][0-9]{0,2})$") Then Return SetError(1, 0, 0)
    Local $n = Int($header[3])
    If $n > 128 Or UBound($lines) <> $n + 2 Then Return SetError(1, 0, 0)
    Local $j = _PJ_New($header[1])
    ReDim $j[$n + 1][4]
    $j[0][2] = $n
    $j[0][3] = "READONLY"
    For $i = 1 To $n
        Local $fields = StringSplit($lines[$i], @TAB, 2)
        If UBound($fields) <> 4 Then Return SetError(1, 0, 0)
        If Not ($fields[0] == String($i)) Then Return SetError(1, 0, 0)
        $j[$i][0] = $fields[1]
        $j[$i][1] = $fields[2]
        $j[$i][2] = $fields[3]
        $j[$i][3] = $i
    Next
    If Not _PJ_Valid($j) Then Return SetError(1, 0, 0)
    For $i = 1 To $n
        If Not StringRegExp($j[$i][2], "^(FAILED|RELEASED)$") Then $j[$i][2] = "UNCERTAIN"
    Next
    Return $j
EndFunc

; Save a new snapshot exclusively, never replacing an existing path. The caller
; supplies an existing private, non-reparse directory and a fresh absolute path.
; This is a snapshot primitive, not a complete crash-safe privileged transaction.
Func _PJ_SaveNew(ByRef $j, $sPath)
    Local $s = _PJ_Snapshot($j)
    If @error Or $s == "" Then Return False
    If Not IsString($sPath) Or Not StringRegExp($sPath, "^[A-Za-z]:\\") Then Return False
    If Not _PortableSafeRelativePath(StringTrimLeft($sPath, 3)) Then Return False
    Local $binary = StringToBinary($s, 4)
    Local $size = BinaryLen($binary)
    Local $buffer = DllStructCreate("byte[" & $size & "]")
    If @error Then Return False
    DllStructSetData($buffer, 1, $binary)
    If @error Then Return False
    Local $r = DllCall("kernel32.dll", "handle", "CreateFileW", "wstr", $sPath, _
        "dword", 0x40000000, "dword", 0, "ptr", 0, "dword", 1, "dword", 0x80, "ptr", 0)
    If @error Then Return False
    Local $h = $r[0]
    If $h = Ptr(-1) Then Return False
    Local $ok = False
    $r = DllCall("kernel32.dll", "bool", "WriteFile", "handle", $h, "ptr", DllStructGetPtr($buffer), _
        "dword", $size, "dword*", 0, "ptr", 0)
    If Not @error Then $ok = $r[0] And $r[4] = $size
    If $ok Then
        $r = DllCall("kernel32.dll", "bool", "FlushFileBuffers", "handle", $h)
        If @error Then
            $ok = False
        Else
            $ok = $r[0] <> 0
        EndIf
    EndIf
    $r = DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
    If @error Then Return False
    ; Any failed/partial write remains visible; do not delete evidence on error.
    Return $ok And $r[0] <> 0
EndFunc
