#include "..\..\source\PortableCISession.au3"
Global $n = 0, $failed = 0
Func Check($ok, $label)
    $n += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $label & @CRLF)
    EndIf
EndFunc
Local $temp = "D:\a\_temp"
Local $root = "D:\a\_temp\Portable VBox Тест"
Check(_PVS_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox",$root,$temp), "exact CI runner accepted")
Check(Not _PVS_Allowed("true","self-hosted","Windows","zlocorp/Portable-VirtualBox",$root,$temp), "self-hosted blocked")
Check(Not _PVS_Allowed("true","github-hosted","Linux","zlocorp/Portable-VirtualBox",$root,$temp), "Linux blocked")
Check(Not _PVS_Allowed("false","github-hosted","Windows","zlocorp/Portable-VirtualBox",$root,$temp), "non-actions blocked")
Check(Not _PVS_Allowed("true","github-hosted","Windows","other/repo",$root,$temp), "other repository blocked")
Check(Not _PVS_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox","D:\Outside",$temp), "outside root blocked")
Check(Not _PVS_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox",$temp,$temp), "runner root not a safe app")
Check(Not _PVS_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox","D:\a\_temp-adjacent\app",$temp), "prefix lookalike blocked")
Check(Not _PVS_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox","D:\a\_temp\..\Windows",$temp), "path traversal blocked")
Check(_PVS_CanonicalImage('"C:\Portable VBox\app64\VBoxSDS.exe"') == "C:\Portable VBox\app64\VBoxSDS.exe", "quoted path unwrapped")
Check(_PVS_CanonicalImage('C:\Portable VBox\app64\VBoxSDS.exe') == "C:\Portable VBox\app64\VBoxSDS.exe", "unquoted path")
Check(_PVS_CanonicalImage('"C:\x.exe" extra') == "", "unexpected service argument refused")
Check(_PVS_CanonicalImage("") == "", "empty refused")
Check(_PVS_Execute("C:\NotRunner") == 9, "actual CI effects strictly fenced")
ConsoleWrite("Native CI session policy checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
