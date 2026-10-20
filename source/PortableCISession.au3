#include-once
#include "PortableProfile.au3"
#include "HostPreflight.au3"

; *** NON-SHIPPING RESEARCH ENTRYPOINT ***
; Runs one genuinely compiled AutoIt->Oracle CLI->VBoxSDS service lifecycle
; on a disposable *GitHub-hosted* Windows runner, with no guest VM or drivers.
; Environment markers are a guard against ACCIDENTAL local execution, NOT
; a malicious-user or elevation security boundary. Never enable in normal UI.

Func _PVS_Allowed($actions, $runner, $os, $repo, $root, $temp)
    If Not ($actions == "true") Or Not ($runner == "github-hosted") Then Return False
    If Not ($os == "Windows") Or Not ($repo == "zlocorp/Portable-VirtualBox") Then Return False
    If Not _PP_RootSafe($root) Or Not _PP_RootSafe($temp) Then Return False
    Local $prefix = $temp
    If StringRight($prefix, 1) <> "\" Then $prefix &= "\"
    Return StringLeft(StringLower($root), StringLen($prefix)) == StringLower($prefix)
EndFunc

Func _PVS_CanonicalImage($text)
    If Not IsString($text) Or $text == "" Then Return ""
    Local $s = StringStripWS($text, 3)
    If StringLeft($s, 1) == Chr(34) Then
        If StringRight($s, 1) <> Chr(34) Or StringLen($s) < 4 Then Return ""
        $s = StringTrimLeft(StringTrimRight($s, 1), 1)
    EndIf
    If StringInStr($s, Chr(34)) Then Return ""
    If Not _PP_RootSafe(StringRegExpReplace($s, "\\[^\\]+$", "")) Then Return ""
    If Not StringRegExp($s, "^[A-Za-z]:\\.*\\VBoxSDS\.exe$") Then Return ""
    Return $s
EndFunc

Func _PVS_ExpectedSDS($service, $image)
    If Not IsMap($service) Then Return False
    If $service["status"] <> "PRESENT" Or $service["name"] <> "VBoxSDS" Then Return False
    If $service["type"] <> 16 Or $service["start"] <> 3 Then Return False
    If $service["account"] <> "LocalSystem" Then Return False
    Local $observed = _PVS_CanonicalImage($service["image"])
    Return $observed <> "" And StringLower($observed) == StringLower($image)
EndFunc

; Only monitor the PID returned by Run. Never terminate any process by name.
Func _PVS_RunBounded($exe, $args, $folder, $waitSeconds)
    Local $pid = Run('"' & $exe & '" ' & $args, $folder, @SW_HIDE)
    If @error Or $pid = 0 Then Return False
    Return ProcessWaitClose($pid, $waitSeconds) <> 0
EndFunc

Func _PVS_Execute($root)
    If Not _PVS_Allowed(EnvGet("GITHUB_ACTIONS"), EnvGet("RUNNER_ENVIRONMENT"), _
            EnvGet("RUNNER_OS"), EnvGet("GITHUB_REPOSITORY"), $root, EnvGet("RUNNER_TEMP")) Then Return 9
    If Not _PP_ParentsSafe($root) Then Return 9
    Local $profile = _PP_Inspect($root)
    If $profile["status"] <> "READY" Then Return 3
    Local $app = $root & "\app64"
    Local $manager = $app & "\VBoxManage.exe"
    Local $sds = $app & "\VBoxSDS.exe"
    If Not FileExists($manager) Or Not FileExists($sds) Then Return 3
    If Not _PortableVersionFamilyAccepted(FileGetVersion($manager)) Then Return 3
    Local $installed = _PortableInstalledVBoxDetected()
    If @error Or Not IsBool($installed) Or $installed Then Return 4
    If _PortableCountExistingServices() <> 0 Then Return 4
    If _PortableCountVirtualBoxProcesses() <> 0 Then Return 4
    Local $old = EnvGet("VBOX_USER_HOME")
    EnvSet("VBOX_USER_HOME", $profile["profile"])
    ConsoleWrite("CI native session: start (no VM, no VBoxSup)" & @CRLF)
    Local $ok = _PVS_RunBounded($manager, 'setproperty machinefolder "' & $profile["machines"] & '"', $app, 25)
    If $old == "" Then
        EnvSet("VBOX_USER_HOME")
    Else
        EnvSet("VBOX_USER_HOME", $old)
    EndIf
    If Not $ok Then Return 5 ; Unknown child outcome; do not guess cleanup.
    Local $service = _WinObsService("VBoxSDS")
    If Not _PVS_ExpectedSDS($service, $sds) Then Return 6
    ConsoleWrite("CI native session: VBoxSDS image matched" & @CRLF)
    ; Give Oracle's own COM service and clients time to exit naturally.
    Local $t = TimerInit(), $idle = False
    While TimerDiff($t) < 35000
        $service = _WinObsService("VBoxSDS")
        Local $count = _PortableCountVirtualBoxProcesses()
        If _PVS_ExpectedSDS($service, $sds) And $service["state"] = 1 And $count = 0 Then
            $idle = True
            ExitLoop
        EndIf
        Sleep(300)
    WEnd
    If Not $idle Then Return 7
    ; Recheck exact registration identity immediately before Oracle's
    ; supported unregistration (no raw service deletion or process killing).
    $service = _WinObsService("VBoxSDS")
    If Not _PVS_ExpectedSDS($service, $sds) Or $service["state"] <> 1 Then Return 7
    If _PortableCountVirtualBoxProcesses() <> 0 Then Return 7
    ConsoleWrite("CI native session: unregistration requested" & @CRLF)
    If Not _PVS_RunBounded($sds, "--unregservice", $app, 20) Then Return 7
    $t = TimerInit()
    While TimerDiff($t) < 18000
        $service = _WinObsService("VBoxSDS")
        If $service["status"] == "ABSENT" And _PortableCountExistingServices() = 0 And _
                _PortableCountVirtualBoxProcesses() = 0 Then
            ConsoleWrite("CI native session: CLEAN" & @CRLF)
            Return 0
        EndIf
        Sleep(250)
    WEnd
    Return 8 ; Leave unknown state for the disposable runner to destroy.
EndFunc
