#include "..\..\source\PortableCIVM.au3"
Global $n = 0, $failed = 0
Func Check($condition, $label)
    $n += 1
    If Not $condition Then
        $failed += 1
        ConsoleWriteError("FAIL native VM policy: " & $label & @CRLF)
    EndIf
EndFunc
Local $runner = "D:\a\_temp", $root = $runner & "\Portable VM Тест"
Check(_PCVM_Allowed("true", "github-hosted", "Windows", "zlocorp/Portable-VirtualBox", $root, $runner), "disposable-host root accepted")
Check(Not _PCVM_Allowed("true", "self-hosted", "Windows", "zlocorp/Portable-VirtualBox", $root, $runner), "self-hosted refuses privileged VM research")
Check(Not _PCVM_Allowed("true", "github-hosted", "Windows", "another/repo", $root, $runner), "foreign repo blocked")
Check(Not _PCVM_Allowed("true", "github-hosted", "Windows", "zlocorp/Portable-VirtualBox", "D:\Other", $runner), "outside private root blocked")
Local $svc[]
$svc["kind"] = "service"
$svc["name"] = "VBoxSup"
$svc["status"] = "PRESENT"
$svc["type"] = 1
$svc["start"] = 1
$svc["state"] = 4
$svc["image"] = "\SystemRoot\System32\drivers\VBoxSup.sys"
Check(_PCVM_ExpectedSup($svc), "exact running oracle VBoxSup driver accepted")
$svc["state"] = 1
Check(Not _PCVM_ExpectedSup($svc), "stopped driver refused")
$svc["state"] = 4
$svc["name"] = "VBoxDrv"
Check(Not _PCVM_ExpectedSup($svc), "different service name refused")
$svc["name"] = "VBoxSup"
$svc["image"] = "C:\foreign\VBoxSup.sys"
Check(Not _PCVM_ExpectedSup($svc), "foreign driver image refused")
$svc["image"] = "\SystemRoot\System32\drivers\VBoxSup.sys"
$svc["type"] = "1"
Check(Not _PCVM_ExpectedSup($svc), "string driver type refused")
Check(Not _PCVM_ExpectedSup(0), "non-map driver observation refused")
Local $running = 'UUID="98b45345-621b-43d1-847a-57e466bb09c4"' & @CRLF & 'VMState="running"' & @CRLF
Check(_PCVM_State($running) == "running", "live VM output parsed")
Check(_PCVM_UUID($running) == "98b45345-621b-43d1-847a-57e466bb09c4", "VM UUID parsed")
Check(_PCVM_State('XVMState="running"' & @CRLF) == "", "substring does not impersonate state")
Check(_PCVM_State('VMState="stuck"' & @CRLF) == "stuck", "failed VM state preserved")
Check(_PCVM_State('VMState="running"' & @CRLF & 'VMState="poweroff"' & @CRLF) == "", "ambiguous state denied")
Check(_PCVM_UUID('UUID="BAD-UUID"' & @CRLF) == "", "invalid UUID refused")
Check(_PCVM_Execute("C:\NotAHostedRunner") = 9, "real mutations gated away from local Windows")
ConsoleWrite("Native VM session policy checks: " & $n & "; failed: " & $failed & @CRLF)
Exit($failed > 0)
