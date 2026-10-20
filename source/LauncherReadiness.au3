#include-once
#include "LauncherI18n.au3"
#include "PortableProfile.au3"
#include "HostPreflight.au3"
; Stable, read-only decision for a user-facing launch-readiness button.
; Never grants OS mutation authority, even when all observations are clear.
Func _LR_Decide($profile, $blocker)
    Local $result[]
    $result["status"]="BLOCKED"
    $result["code"]="INVALID"
    $result["message"]=_LI("readiness.unknown")
    If Not IsMap($profile) Or Not MapExists($profile,"status") Or Not MapExists($profile,"app_present") Then Return $result
    Switch $profile["status"]
        Case "MISSING"
            $result["code"]="PROFILE_MISSING"
            $result["message"]=_LI("profile.missing")
            Return $result
        Case "BLOCKED"
            $result["code"]="PROFILE_UNSAFE"
            $result["message"]=_LI("profile.blocked")
            Return $result
        Case "READY"
        Case Else
            Return $result
    EndSwitch
    If Not $profile["app_present"] Then
        $result["code"]="APP_MISSING"
        $result["message"]=_LI("profile.appmissing")
        Return $result
    EndIf
    If Not IsString($blocker) Then Return $result
    If $blocker <> "" Then
        $result["code"]="HOST_CONFLICT"
        $result["message"]=_LI("preflight.blocked") & _LI_Blocker($blocker)
        Return $result
    EndIf
    $result["status"]="RESEARCH_ONLY"
    $result["code"]="RUNTIME_DISABLED"
    $result["message"]=_LI("readiness.disabled")
    Return $result
EndFunc

Func _LR_Inspect($root)
    Local $profile=_PP_Inspect($root)
    If $profile["status"] <> "READY" Or Not $profile["app_present"] Then Return _LR_Decide($profile,"")
    Return _LR_Decide($profile,_PortableReadOnlyPreflight())
EndFunc
