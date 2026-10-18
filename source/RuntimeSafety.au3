#include-once
; Portable-VirtualBox modernization: side-effect-free checks.
; This library intentionally contains no service, registry-write or process-stop calls.

Func _PortableSafeRelativePath($sPath)
    If Not IsString($sPath) Or $sPath = "" Then Return False
    If StringLeft($sPath, 1) = "\" Or StringLeft($sPath, 1) = "/" Then Return False
    If StringInStr($sPath, ":") Then Return False
    If StringRegExp($sPath, "[<>|?*\x00-\x1F]") Or StringInStr($sPath, Chr(34)) Then Return False
    Local $aParts = StringSplit(StringReplace($sPath, "/", "\"), "\", 2)
    For $i = 0 To UBound($aParts) - 1
        If $aParts[$i] = "" Then Return False
        If StringRight($aParts[$i], 1) = "." Or StringRight($aParts[$i], 1) = " " Then Return False
        If StringRegExp($aParts[$i], "(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$") Then Return False
    Next
    If StringRegExp($sPath, "(^|[\\/])\.{1,2}($|[\\/])") Then Return False
    Return True
EndFunc

Func _PortableRelativeToRoot($sRoot, $sRelative)
    If Not _PortableSafeRelativePath($sRelative) Then Return SetError(1, 0, "")
    If Not IsString($sRoot) Or $sRoot = "" Then Return SetError(2, 0, "")
    Local $sBase = StringReplace($sRoot, "/", "\")
    $sBase = StringRegExpReplace($sBase, "\\+$", "")
    Local $sPart = StringReplace($sRelative, "/", "\")
    Return $sBase & "\" & $sPart
EndFunc

; Deliberately strict and conservative: only a service created during this
; session, absent at startup, with the exact expected image, is owned.
Func _PortableServiceOwned($bCreatedThisRun, $bExistedAtStart, $sImageInRegistry, $sExpectedImage)
    If Not $bCreatedThisRun Or $bExistedAtStart Then Return False
    If Not IsString($sImageInRegistry) Or $sImageInRegistry = "" Then Return False
    If Not IsString($sExpectedImage) Or $sExpectedImage = "" Then Return False
    Return StringLower($sImageInRegistry) == StringLower($sExpectedImage)
EndFunc

; Values must originate from a retained process handle, not a fresh PID lookup.
; This pure comparison does not query, own or terminate a Windows process.
Func _PortableProcessOwned($iPid, $iRecordedPid, $sObservedCreated = "", $sRecordedCreated = "", _
        $sObservedImage = "", $sRecordedImage = "", $bHandleBound = False)
    If Not IsInt($iPid) Or Not IsInt($iRecordedPid) Then Return False
    If $iPid < 1 Or $iPid <> $iRecordedPid Then Return False
    If Not IsBool($bHandleBound) Or Not $bHandleBound Then Return False
    If Not IsString($sObservedCreated) Or Not IsString($sRecordedCreated) Then Return False
    If $sObservedCreated == "" Or Not ($sObservedCreated == $sRecordedCreated) Then Return False
    If Not IsString($sObservedImage) Or Not IsString($sRecordedImage) Then Return False
    If Not StringRegExp($sObservedImage, "^[A-Za-z]:\\") Then Return False
    If Not _PortableSafeRelativePath(StringTrimLeft($sObservedImage, 3)) Then Return False
    Return StringLower($sObservedImage) == StringLower($sRecordedImage)
EndFunc

; Version policy: only 7.2.x. This is a release-family check,
; NOT a guarantee of driver, COM, USB or network compatibility.
Func _PortableVersionFamilyAccepted($sVersion)
    If Not IsString($sVersion) Then Return False
    Local $aMatch = StringRegExp($sVersion, "^(\d+)\.(\d+)\.(\d+)(?:\.\d+)?$", 1)
    If Not IsArray($aMatch) Then Return False
    Local $iMajor = Number($aMatch[0])
    Local $iMinor = Number($aMatch[1])
    Return ($iMajor = 7 And $iMinor = 2)
EndFunc
