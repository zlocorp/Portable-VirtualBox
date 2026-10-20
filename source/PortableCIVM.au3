#include-once
#include "PortableCISession.au3"
#include "PortableCommand.au3"

; NON-SHIPPING research entrypoint. It boots/powers off one newly created,
; empty VirtualBox VM through the COM/driver stack from the compiled AutoIt EXE.
; The exact signed VBoxSup driver is provisioned/owned by the disposable hosted
; Windows CI workflow. This module NEVER installs/stops/deletes driver/services,
; kills any process, runs an arbitrary command, or boots a user's existing VM.
; VBoxSDS and VBoxSup cleanup follow in the gated CI workflow after success.
; GitHub environment markers prevent accidents; they are NOT an ACL boundary.

Func _PCVM_Allowed($actions, $runner, $os, $repo, $root, $temp)
    Return _PVS_Allowed($actions, $runner, $os, $repo, $root, $temp)
EndFunc

Func _PCVM_ExpectedSup($obs)
    If Not IsMap($obs) Then Return False
    Local $keys = StringSplit("kind,name,status,type,start,state,image", ",", 2)
    For $i = 0 To UBound($keys) - 1
        If Not MapExists($obs, $keys[$i]) Then Return False
    Next
    If Not IsString($obs["kind"]) Or Not IsString($obs["name"]) Or _
            Not IsString($obs["status"]) Or Not IsString($obs["image"]) Then Return False
    If Not IsInt($obs["type"]) Or Not IsInt($obs["start"]) Or Not IsInt($obs["state"]) Then Return False
    Return $obs["kind"] == "service" And $obs["name"] == "VBoxSup" And _
        $obs["status"] == "PRESENT" And $obs["type"] = 1 And _
        $obs["start"] = 1 And $obs["state"] = 4 And _
        StringLower($obs["image"]) == "\systemroot\system32\drivers\vboxsup.sys"
EndFunc

Func _PCVM_State($raw)
    If Not IsString($raw) Or StringLen($raw) > 262144 Then Return ""
    Local $matches = StringRegExp($raw, '(?m)^VMState="([a-z]+)"\r?$', 3)
    If Not IsArray($matches) Or UBound($matches) <> 1 Then Return ""
    Return $matches[0]
EndFunc

Func _PCVM_UUID($raw)
    If Not IsString($raw) Or StringLen($raw) > 262144 Then Return ""
    Local $matches = StringRegExp($raw, '(?im)^UUID="([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"\r?$', 3)
    If Not IsArray($matches) Or UBound($matches) <> 1 Then Return ""
    Return StringLower($matches[0])
EndFunc

Func _PCVM_Command($manager, $app, $name, $args)
    Local $result = _PXR_Run($manager, $args, $app, 45000)
    ConsoleWrite("Native VM " & $name & ": " & $result["status"] & "/" & $result["exit_code"] & @CRLF)
    If $result["status"] <> "EXITED" Or $result["exit_code"] <> 0 Then
        ; Only bounded diagnostics; guest paths/accounts are not printed.
        Local $err = $result["error_output"]
        If StringLen($err) > 300 Then $err = StringLeft($err, 300)
        If $err <> "" Then ConsoleWriteError("Native VM command returned error; details captured in test output." & @CRLF)
    EndIf
    Return $result
EndFunc

Func _PCVM_Succeeded($result)
    Return IsMap($result) And $result["status"] == "EXITED" And $result["exit_code"] = 0
EndFunc

; Write a tiny native success witness only AFTER UUID/poweroff were verified.
; The separate host observer still checks the live state and exact UUID.
; This CI witness file is not production ownership or cleanup authority.
Func _PCVM_SaveReceipt($path, $uuid)
    If Not _PP_RootSafe($path) Or FileExists($path) Then Return False
    If Not StringRegExp($uuid, "(?i)^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$") Then Return False
    Local $h = FileOpen($path, 258) ; WRITE(2) + UTF8-no-BOM(256)
    If $h = -1 Then Return False
    Local $ok = FileWrite($h, "Native VM: VERIFIED_OWN_BOOT_AND_POWEROFF, uuid=" & $uuid & @CRLF)
    Local $closed = FileClose($h)
    Return $ok <> 0 And $closed <> 0
EndFunc

Func _PCVM_Execute($root, $receiptPath = "")
    If Not _PCVM_Allowed(EnvGet("GITHUB_ACTIONS"), EnvGet("RUNNER_ENVIRONMENT"), _
            EnvGet("RUNNER_OS"), EnvGet("GITHUB_REPOSITORY"), $root, EnvGet("RUNNER_TEMP")) Then Return 9
    If Not _PP_ParentsSafe($root) Then Return 9
    Local $profile = _PP_Inspect($root)
    If $profile["status"] <> "READY" Or Not $profile["app_present"] Then Return 3
    Local $app = $profile["app"], $manager = $app & "\VBoxManage.exe"
    Local $headless = $app & "\VirtualBoxVM.exe"
    If Not FileExists($manager) Or Not FileExists($headless) Then Return 3
    If Not _PortableVersionFamilyAccepted(FileGetVersion($manager)) Then Return 3
    Local $installed = _PortableInstalledVBoxDetected()
    If @error Or Not IsBool($installed) Or $installed Then Return 4
    Local $driver = _WinObsService("VBoxSup")
    If Not _PCVM_ExpectedSup($driver) Then Return 4
    If _PortableCountExistingServices() <> 1 Or _PortableCountVirtualBoxProcesses() <> 0 Then Return 4
    ; Preserve all preexisting user machines. This is a freshly initialized
    ; disposable CI fixture ONLY, never reuse a user's existing VM.
    Local $vm = "pvbox_compiled_native_fixture"
    Local $vmFolder = $profile["machines"] & "\" & $vm
    If FileExists($vmFolder) Or FileExists($profile["profile"] & "\VirtualBox.xml") Then Return 4
    Local $oldHome = EnvGet("VBOX_USER_HOME")
    Local $status = 5, $created = False, $started = False, $stopped = False, $uuid = ""
    EnvSet("VBOX_USER_HOME", $profile["profile"])
    Do
        Local $r = _PCVM_Command($manager, $app, "machinefolder", 'setproperty machinefolder "' & $profile["machines"] & '"')
        If Not _PCVM_Succeeded($r) Then ExitLoop
        $r = _PCVM_Command($manager, $app, "createvm", 'createvm --name ' & $vm & ' --platform-architecture x86 --register')
        If Not _PCVM_Succeeded($r) Then ExitLoop
        $created = True
        $r = _PCVM_Command($manager, $app, "configure", 'modifyvm ' & $vm & ' --memory 128 --cpus 1 --nic1 none --boot1 none --boot2 none --boot3 none --boot4 none')
        If Not _PCVM_Succeeded($r) Then ExitLoop
        $r = _PCVM_Command($manager, $app, "before", 'showvminfo ' & $vm & ' --machinereadable')
        If Not _PCVM_Succeeded($r) Then ExitLoop
        If _PCVM_State($r["output"]) <> "poweroff" Then ExitLoop
        $uuid = _PCVM_UUID($r["output"])
        If $uuid == "" Then ExitLoop
        If Not FileExists($vmFolder & "\" & $vm & ".vbox") Then ExitLoop
        $r = _PCVM_Command($manager, $app, "start", 'startvm ' & $vm & ' --type headless')
        If Not _PCVM_Succeeded($r) Then ExitLoop
        $started = True
        $r = _PCVM_Command($manager, $app, "running", 'showvminfo ' & $vm & ' --machinereadable')
        If Not _PCVM_Succeeded($r) Or _PCVM_State($r["output"]) <> "running" Then ExitLoop
        If _PCVM_UUID($r["output"]) <> $uuid Then ExitLoop
        $r = _PCVM_Command($manager, $app, "poweroff", 'controlvm ' & $vm & ' poweroff')
        If Not _PCVM_Succeeded($r) Then ExitLoop
        $r = _PCVM_Command($manager, $app, "after", 'showvminfo ' & $vm & ' --machinereadable')
        If Not _PCVM_Succeeded($r) Or _PCVM_State($r["output"]) <> "poweroff" Then ExitLoop
        If _PCVM_UUID($r["output"]) <> $uuid Then ExitLoop
        $stopped = True
        ; VBoxSDS and VBoxSup remain owned by the disposable workflow, which
        ; revalidates process absence and removes exact resources afterward.
        If Not FileExists($profile["profile"] & "\VirtualBox.xml") Then ExitLoop
        ConsoleWrite("Native VM: VERIFIED_OWN_BOOT_AND_POWEROFF, uuid=" & $uuid & @CRLF)
        $status = 0
    Until True
    If $oldHome == "" Then
        EnvSet("VBOX_USER_HOME")
    Else
        EnvSet("VBOX_USER_HOME", $oldHome)
    EndIf
    If $status = 0 And $receiptPath <> "" Then
        If Not _PCVM_SaveReceipt($receiptPath, $uuid) Then $status = 6
    EndIf
    If $status <> 0 Then
        ConsoleWriteError("Native VM: INCOMPLETE; created=" & $created & ", started=" & $started & _
            ", poweroff_verified=" & $stopped & ". No automated resource deletion." & @CRLF)
    EndIf
    Return $status
EndFunc
