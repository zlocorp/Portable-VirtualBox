#include-once
#include "WindowsObservation.au3"
; Read-only host preflight. Missing, inaccessible and changed are distinct states.

; Refusal diagnostics format the original observation only. Callers opt in;
; fixed service/process basenames never expose image paths or account names.
Func _PortableOfflineDiagnosticText($kind, $status, $count, $reason, $error, $pid = 0, $name = "", $stage = "")
    Local $line = "Portable offline refusal: " & $kind & " status=" & $status & " count=" & $count & _
        " reason=" & $reason & " error=" & $error & " pid=" & $pid & " name=" & $name & " stage=" & $stage
    Return StringLeft(StringRegExpReplace($line, "[\x00-\x1f\x7f]", "?"), 512)
EndFunc

Func _PortableInstalledVBoxDetected($diagnostic = False)
    Local $r = _WinObsInstallation()
    If $diagnostic And $r["status"] <> "ABSENT" Then
        Local $count = -1
        If $r["status"] == "PRESENT" Then $count = 1
        ConsoleWrite(_PortableOfflineDiagnosticText("installation", $r["status"], $count, "installation-observation", _
            $r["error"], 0, "", $r["stage"]) & @CRLF)
    EndIf
    If $r["status"] == "PRESENT" Then Return True
    If $r["status"] == "ABSENT" Then Return False
    Return SetError(1, $r["error"], "")
EndFunc

; One fixed inventory for strict preflight and query-only presentation.
Func _PortableServiceNames()
    Local $names[10] = ["VBoxDrv", "VBoxSup", "VBoxUSB", "VBoxUSBMon", "VBoxSDS", "VBoxNetAdp", "VBoxNetAdp6", "VBoxNetLwf", "VBoxNetFlt", "VBoxNetNAT"]
    Return $names
EndFunc

Func _PortableCountExistingServices($diagnostic = False)
    Local $names = _PortableServiceNames()
    Local $count = 0, $presentNames = ""
    For $i = 0 To UBound($names) - 1
        Local $r = _WinObsService($names[$i])
        If $r["status"] == "UNKNOWN" Then
            If $diagnostic Then ConsoleWrite(_PortableOfflineDiagnosticText("services", "UNKNOWN", -1, "service-observation", _
                $r["error"], 0, $names[$i], $r["stage"]) & @CRLF)
            Return SetError(1, $r["error"], -1)
        EndIf
        If $r["status"] == "PRESENT" Then
            $count += 1
            If $diagnostic Then
                If $presentNames <> "" Then $presentNames &= ","
                $presentNames &= $names[$i]
            EndIf
        EndIf
    Next
    If $diagnostic And $count > 0 Then ConsoleWrite(_PortableOfflineDiagnosticText("services", "PRESENT", $count, _
        "services-present", 0, 0, $presentNames, "complete") & @CRLF)
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
        Case "vboxsvc.exe", "vboxmanageportable.exe", "vboxmanage.exe", "vboxsds.exe", "vboxnetdhcp.exe", "vboxnetnat.exe", "vboxballoonctrl.exe", "vboxautostart.exe"
            Return "background"
    EndSwitch
    Return ""
EndFunc

; Attach evidence to the existing UNKNOWN result without changing its counts
; or collecting again. An unavailable close error is explicitly -1.
Func _PortableActivityFailure(ByRef $r, $reason, $error, $pid, $name, $stage = "")
    $r["reason"] = $reason
    $r["error"] = $error
    $r["pid"] = $pid
    $r["name"] = $name
    $r["stage"] = $stage
    Return $r
EndFunc

Func _PortableActivityCollect()
    Local $r[]
    $r["status"] = "UNKNOWN"
    $r["manager"] = -1
    $r["guest"] = -1
    $r["background"] = -1
    $r["total"] = -1
    $r["reason"] = ""
    $r["error"] = 0
    $r["pid"] = 0
    $r["name"] = ""
    $r["stage"] = ""
    Local $counts[]
    $counts["manager"] = 0
    $counts["guest"] = 0
    $counts["background"] = 0
    Local $names[11] = ["VBoxManagePortable.exe", "VirtualBox.exe", "VirtualBoxVM.exe", "VBoxSVC.exe", "VBoxManage.exe", "VBoxSDS.exe", "VBoxHeadless.exe", "VBoxNetDHCP.exe", "VBoxNetNAT.exe", "VBoxBalloonCtrl.exe", "VBoxAutostart.exe"]
    For $i = 0 To UBound($names) - 1
        Local $list = ProcessList($names[$i])
        Local $listError = @error
        If $listError Or Not IsArray($list) Then Return _PortableActivityFailure($r, "process-list", $listError, 0, $names[$i], "list")
        For $k = 1 To $list[0][0]
            Local $token = _WinObsProcessOpen($list[$k][1])
            Local $openError = @extended
            If $token = 0 Then Return _PortableActivityFailure($r, "process-open", $openError, $list[$k][1], $names[$i], "open")
            Local $obs = _WinObsProcessRead($token)
            Local $closed = _WinObsProcessClose($token)
            If Not $closed Then Return _PortableActivityFailure($r, "process-close", -1, $list[$k][1], $names[$i], "close")
            If Not ($obs["status"] == "PRESENT") Then Return _PortableActivityFailure($r, "process-read-" & $obs["status"], _
                $obs["error"], $list[$k][1], $names[$i], $obs["stage"])
            Local $baseName = StringRegExpReplace($obs["image"], "^.*[\\/]", "")
            If Not (StringLower($baseName) == StringLower($names[$i])) Then Return _PortableActivityFailure($r, "process-name-changed", -1, $list[$k][1], $names[$i], "identity")
            Local $role = _PortableProcessRole($baseName)
            If $role == "" Then Return _PortableActivityFailure($r, "process-role-unknown", -1, $list[$k][1], $names[$i], "role")
            $counts[$role] += 1
            If $r["pid"] = 0 Then
                $r["pid"] = $list[$k][1]
                $r["name"] = $names[$i]
            EndIf
        Next
    Next
    $r["status"] = "KNOWN"
    $r["manager"] = $counts["manager"]
    $r["guest"] = $counts["guest"]
    $r["background"] = $counts["background"]
    $r["total"] = $r["manager"] + $r["guest"] + $r["background"]
    $r["reason"] = "no-matching-processes"
    If $r["total"] > 0 Then $r["reason"] = "matching-processes"
    $r["stage"] = "complete"
    ; This is a non-atomic read-only snapshot, NOT shutdown/cleanup authority.
    Return $r
EndFunc

Func _PortableCountVirtualBoxProcesses($diagnostic = False)
    Local $activity = _PortableActivityCollect()
    If $diagnostic And ($activity["status"] <> "KNOWN" Or $activity["total"] <> 0) Then
        ConsoleWrite(_PortableOfflineDiagnosticText("processes", $activity["status"], $activity["total"], $activity["reason"], _
            $activity["error"], $activity["pid"], $activity["name"], $activity["stage"]) & @CRLF)
    EndIf
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
