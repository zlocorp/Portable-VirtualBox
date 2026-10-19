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

Func _PortableCountVirtualBoxProcesses()
    Local $names[10] = ["VirtualBox.exe", "VirtualBoxVM.exe", "VBoxSVC.exe", "VBoxManage.exe", "VBoxSDS.exe", "VBoxHeadless.exe", "VBoxNetDHCP.exe", "VBoxNetNAT.exe", "VBoxBalloonCtrl.exe", "VBoxAutostart.exe"]
    Local $count = 0
    For $i = 0 To UBound($names) - 1
        Local $list = ProcessList($names[$i])
        If @error Or Not IsArray($list) Then Return SetError(1, 0, -1)
        For $k = 1 To $list[0][0]
            Local $token = _WinObsProcessOpen($list[$k][1])
            If $token = 0 Then Return SetError(1, @extended, -1)
            Local $r = _WinObsProcessRead($token)
            Local $closed = _WinObsProcessClose($token)
            If Not $closed Or Not ($r["status"] == "PRESENT") Then Return SetError(1, 0, -1)
            Local $baseName = StringRegExpReplace($r["image"], "^.*[\\/]", "")
            If Not (StringLower($baseName) == StringLower($names[$i])) Then Return SetError(1, 0, -1)
            $count += 1
        Next
    Next
    Return $count
EndFunc

Func _PortablePreflightBlocker($iWindowsBuild, $sArch, $bHasVBoxExecutable, $sVersion, _
        $bInstalled, $iServices, $iProcesses, $iProductType = 1)
    If Not IsString($sArch) Or StringUpper($sArch) <> "X64" Then Return "Unsupported architecture (x64 required)"
    If Not _WinObsWorkstationAccepted($iWindowsBuild, $iProductType) Then Return "Unsupported Windows product/build (Windows 11 workstation required)"
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

Func _PortableReadOnlyPreflight()
    Local $os = _WinObsOS()
    If Not ($os["status"] == "PRESENT") Then Return "Windows version observation is unknown"
    If Not _WinObsWorkstationAccepted($os["build"], $os["product_type"], $os["major"]) Then Return "Unsupported Windows product/build (Windows 11 workstation required)"
    Local $sApp = @ScriptDir & "\app64\VirtualBox.exe"
    Local $bPresent = FileExists($sApp) <> 0, $sVersion = ""
    If $bPresent Then $sVersion = FileGetVersion($sApp)
    Local $installed = _PortableInstalledVBoxDetected()
    Local $services = _PortableCountExistingServices()
    Local $processes = _PortableCountVirtualBoxProcesses()
    Return _PortablePreflightBlocker($os["build"], @OSArch, $bPresent, $sVersion, _
        $installed, $services, $processes, $os["product_type"])
EndFunc
