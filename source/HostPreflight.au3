#include-once
#include "WindowsObservation.au3"
; Read-only host preflight. Missing, inaccessible and changed are distinct states.

Func _PortableInstalledVBoxDetected()
    Local $r = _WinObsInstallation()
    If $r["status"] == "PRESENT" Then Return True
    If $r["status"] == "ABSENT" Then Return False
    Return SetError(1, $r["error"], "")
EndFunc

Func _PortableCountExistingServices()
    Local $names[10] = ["VBoxDrv", "VBoxSUP", "VBoxUSB", "VBoxUSBMon", "VBoxSDS", "VBoxNetAdp", "VBoxNetAdp6", "VBoxNetLwf", "VBoxNetFlt", "VBoxNetNAT"]
    Local $count = 0
    For $i = 0 To UBound($names) - 1
        Local $r = _WinObsService($names[$i])
        If $r["status"] == "UNKNOWN" Then Return SetError(1, $r["error"], -1)
        If $r["status"] == "PRESENT" Then $count += 1
    Next
    Return $count
EndFunc

; Distinct Manager/guest lifetimes: independent adaptation of the scenario in
; ThatAdminGuy's a035d06b12 and upstream PR #90. Never kill by image name.
Func _PortableProcessRole($name)
    If Not IsString($name) Then Return ""
    Switch StringLower($name)
        Case "virtualbox.exe"
            Return "manager"
        Case "virtualboxvm.exe", "vboxheadless.exe"
            Return "guest"
        Case "vboxsvc.exe", "vboxmanage.exe", "vboxsds.exe", "vboxnetdhcp.exe", "vboxnetnat.exe", "vboxballoonctrl.exe", "vboxautostart.exe"
            Return "background"
    EndSwitch
    Return ""
EndFunc

Func _PortableActivityCollect()
    Local $r[]
    $r["status"] = "UNKNOWN"
    $r["manager"] = -1
    $r["guest"] = -1
    $r["background"] = -1
    $r["total"] = -1
    Local $counts[]
    $counts["manager"] = 0
    $counts["guest"] = 0
    $counts["background"] = 0
    Local $names[10] = ["VirtualBox.exe", "VirtualBoxVM.exe", "VBoxSVC.exe", "VBoxManage.exe", "VBoxSDS.exe", "VBoxHeadless.exe", "VBoxNetDHCP.exe", "VBoxNetNAT.exe", "VBoxBalloonCtrl.exe", "VBoxAutostart.exe"]
    For $i = 0 To UBound($names) - 1
        Local $list = ProcessList($names[$i])
        If @error Or Not IsArray($list) Then Return $r
        For $k = 1 To $list[0][0]
            Local $token = _WinObsProcessOpen($list[$k][1])
            If $token = 0 Then Return $r
            Local $obs = _WinObsProcessRead($token)
            Local $closed = _WinObsProcessClose($token)
            If Not $closed Or Not ($obs["status"] == "PRESENT") Then Return $r
            Local $baseName = StringRegExpReplace($obs["image"], "^.*[\\/]", "")
            If Not (StringLower($baseName) == StringLower($names[$i])) Then Return $r
            Local $role = _PortableProcessRole($baseName)
            If $role == "" Then Return $r
            $counts[$role] += 1
        Next
    Next
    $r["status"] = "KNOWN"
    $r["manager"] = $counts["manager"]
    $r["guest"] = $counts["guest"]
    $r["background"] = $counts["background"]
    $r["total"] = $r["manager"] + $r["guest"] + $r["background"]
    ; This is a non-atomic read-only snapshot, NOT shutdown/cleanup authority.
    Return $r
EndFunc

Func _PortableCountVirtualBoxProcesses()
    Local $activity = _PortableActivityCollect()
    If $activity["status"] <> "KNOWN" Then Return SetError(1, 0, -1)
    Return $activity["total"]
EndFunc

Func _PortablePreflightBlocker($iWindowsBuild, $sArch, $bHasVBoxExecutable, $sVersion, _
        $bInstalled, $iServices, $iProcesses, $iProductType = 1)
    If Not IsString($sArch) Or StringUpper($sArch) <> "X64" Then Return "Unsupported architecture (x64 required)"
    If Not _WinObsWorkstationAccepted($iWindowsBuild, $iProductType) Then Return "Unsupported Windows product/build (Windows 10/11 workstation required)"
    If Not IsBool($bInstalled) Then Return "VirtualBox installation state is unknown"
    If Not IsInt($iServices) Or $iServices < 0 Then Return "VirtualBox service state is unknown"
    If Not IsInt($iProcesses) Or $iProcesses < 0 Then Return "VirtualBox process state is unknown"
    If Not IsBool($bHasVBoxExecutable) Then Return "Portable executable state is unknown"
    If $bInstalled Then Return "A system VirtualBox installation is present"
    If $iServices > 0 Then Return "Pre-existing VirtualBox services detected"
    If $iProcesses > 0 Then Return "Pre-existing VirtualBox processes detected"
    If Not $bHasVBoxExecutable Then Return "Portable app64\VirtualBox.exe is absent"
    If Not _PortableVersionFamilyAccepted($sVersion) Then Return "Unsupported or unreadable VBox version"
    Return ""
EndFunc

Func _PortableReadOnlyPreflight($root = @ScriptDir)
    Local $os = _WinObsOS()
    If Not ($os["status"] == "PRESENT") Then Return "Windows version observation is unknown"
    If Not _WinObsWorkstationAccepted($os["build"], $os["product_type"], $os["major"]) Then Return "Unsupported Windows product/build (Windows 10/11 workstation required)"
    Local $sApp = $root & "\app64\VirtualBox.exe"
    Local $bPresent = FileExists($sApp) <> 0, $sVersion = ""
    If $bPresent Then $sVersion = FileGetVersion($sApp)
    Local $installed = _PortableInstalledVBoxDetected()
    Local $services = _PortableCountExistingServices()
    Local $processes = _PortableCountVirtualBoxProcesses()
    Return _PortablePreflightBlocker($os["build"], @OSArch, $bPresent, $sVersion, _
        $installed, $services, $processes, $os["product_type"])
EndFunc
