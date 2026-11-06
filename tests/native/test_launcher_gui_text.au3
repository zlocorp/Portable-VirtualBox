#include "..\..\source\LauncherGui.au3"
Global $checks=0,$failed=0
Func Check($ok,$label)
    $checks+=1
    If Not $ok Then
        $failed+=1
        ConsoleWriteError("FAIL GUI text: " & $label & @CRLF)
    EndIf
EndFunc
Check(_LI_Set("ru"), "Russian locale")
Local $p[]
$p["status"]="READY"
$p["app_present"]=False
Check(StringInStr(_LG_ProfileMessage($p), "app64")>0, "prepared folders do not hide missing Oracle files RU")
$p["app_present"]=True
Check(StringInStr(_LG_ProfileMessage($p), "app64")=0, "prepared folders and Oracle ready RU")
$p["status"]="BLOCKED"
Check(StringInStr(_LG_ProfileMessage($p), "Проверьте")>0, "blocked profile RU")
Check(_LI_Set("en"), "English locale")
$p["status"]="READY"
$p["app_present"]=False
Check(StringInStr(_LG_ProfileMessage($p), "not yet present")>0, "prepared folders do not hide missing Oracle files EN")
Check(_LG_DisplayPath("C:\root", 12) == "C:\root", "short root unchanged")
Local $path="C:\Portable Тест\data\Machines\Long Long Long Very Long Folder\VMs"
Local $short=_LG_DisplayPath($path, 36)
Check(StringLen($short)=36, "bounded path caption")
Check(StringLeft($short, 2)=="C:" And StringInStr($short, "...")>0, "display truncates middle only")
Check(_LG_DisplayPath($path, 0)=="", "invalid bound denied")
ConsoleWrite("Native GUI text checks: "&$checks&"; failed: "&$failed&@CRLF)
Exit ($failed>0)
