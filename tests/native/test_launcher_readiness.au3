#include "..\..\source\LauncherReadiness.au3"
Global $checks=0,$failed=0
Func Check($ok,$name)
 $checks+=1
 If Not $ok Then
   $failed+=1
   ConsoleWriteError("FAIL readiness: "&$name&@CRLF)
 EndIf
EndFunc
Local $p[]
$p["status"]="MISSING"
$p["app_present"]=False
Local $r=_LR_Decide($p,"")
Check($r["status"]=="BLOCKED","missing data folder blocks")
Check($r["code"]=="PROFILE_MISSING","reason for missing data")
$p["status"]="BLOCKED"
$r=_LR_Decide($p,"")
Check($r["code"]=="PROFILE_UNSAFE","unsafe profile blocked")
$p["status"]="READY"
$r=_LR_Decide($p,"")
Check($r["code"]=="APP_MISSING","missing app64 blocked")
$p["app_present"]=True
$r=_LR_Decide($p,"A system VirtualBox installation is present")
Check($r["code"]=="HOST_CONFLICT","existing system VBox blocks")
Check(StringInStr($r["message"],"VirtualBox")>0,"localized conflict explanation")
$r=_LR_Decide($p,"")
Check($r["status"]=="RESEARCH_ONLY","clear preflight not a permission to launch")
Check($r["code"]=="RUNTIME_DISABLED","clear preflight explicit runtime gate")
Check(_LI_Set("ru"),"select Russian locale")
$r=_LR_Decide($p,"")
Check(StringInStr($r["message"],"запуск")>0,"Russian report")
ConsoleWrite("Native launcher readiness checks: "&$checks&"; failed: "&$failed&@CRLF)
Exit ($failed>0)
