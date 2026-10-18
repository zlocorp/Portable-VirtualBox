; Read-only Windows host inventory for a future privileged runtime.
; Does not create, stop, delete, reconfigure or install services.

Func _PortableInstalledVBoxDetected()
    Local $sInstalled = RegRead("HKLM64\SOFTWARE\Oracle\VirtualBox", "InstallDir")
    If Not @error And $sInstalled <> "" Then Return True
    $sInstalled = RegRead("HKLM\SOFTWARE\Oracle\VirtualBox", "InstallDir")
    If Not @error And $sInstalled <> "" Then Return True
    Return False
EndFunc

Func _PortableCountExistingServices()
    Local $aServices[10] = ["VBoxDrv", "VBoxSUP", "VBoxUSB", "VBoxUSBMon", "VBoxSDS", "VBoxNetAdp", "VBoxNetAdp6", "VBoxNetLwf", "VBoxNetFlt", "VBoxNetNAT"]
    Local $iCount = 0
    For $i = 0 To UBound($aServices) - 1
        Local $sKey = "HKLM\SYSTEM\CurrentControlSet\Services\" & $aServices[$i]
        RegRead($sKey, "Type")
        If Not @error Then
            $iCount += 1
        Else
            RegRead($sKey, "ImagePath")
            If Not @error Then $iCount += 1
        EndIf
    Next
    Return $iCount
EndFunc

Func _PortableCountVirtualBoxProcesses()
    Local $aNames[5] = ["VirtualBox.exe", "VirtualBoxVM.exe", "VBoxSVC.exe", "VBoxManage.exe", "VBoxSDS.exe"]
    Local $iCount = 0
    For $i = 0 To UBound($aNames) - 1
        Local $aList = ProcessList($aNames[$i])
        If IsArray($aList) Then $iCount += $aList[0][0]
    Next
    Return $iCount
EndFunc

; A pure policy function suitable for headless testing. An empty reason does
; NOT authorize starting VirtualBox: it only means this preflight found no blocker.
Func _PortablePreflightBlocker($iWindowsBuild, $sArch, $bHasVBoxExecutable, $sVersion, _
        $bInstalled, $iServices, $iProcesses)
    If StringUpper($sArch) <> "X64" Then Return "Unsupported architecture (x64 required)"
    ; Windows 11 starts at build 22000. Server editions are not certified.
    If Number($iWindowsBuild) < 22000 Then Return "Unsupported Windows build (Windows 11 required)"
    If $bInstalled Then Return "A system VirtualBox installation is present"
    If $iServices > 0 Then Return "Pre-existing VirtualBox services detected"
    If $iProcesses > 0 Then Return "Pre-existing VirtualBox processes detected"
    If Not $bHasVBoxExecutable Then Return "Portable app64\VirtualBox.exe is absent"
    If Not _PortableVersionFamilyAccepted($sVersion) Then Return "Unsupported or unreadable VBox version"
    Return ""
EndFunc

Func _PortableReadOnlyPreflight()
    Local $sApp = @ScriptDir & "\app64\VirtualBox.exe"
    Local $bPresent = FileExists($sApp)
    Local $sVersion = ""
    If $bPresent Then $sVersion = FileGetVersion($sApp)
    Return _PortablePreflightBlocker(@OSBuild, @OSArch, $bPresent, $sVersion, _
        _PortableInstalledVBoxDetected(), _PortableCountExistingServices(), _
        _PortableCountVirtualBoxProcesses())
EndFunc
