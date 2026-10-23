#include "..\..\source\PrivilegeBoundary.au3"
#include "..\..\source\ManagerSession.au3"
Global $checks=0,$failed=0
Func Check($value,$name)
    $checks+=1
    If Not $value Then
        $failed+=1
        ConsoleWriteError("FAIL privilege boundary: " & $name & @CRLF)
    EndIf
EndFunc
Check(_PB_Outcome(False,1223,0)=="CANCELLED","UAC cancellation separate from failure")
Check(_PB_Outcome(False,5,0)=="FAILED","access denied cannot authorize cleanup")
Check(_PB_Outcome(True,0,0)=="FAILED","missing process handle denied")
Check(_PB_Outcome(True,0,Ptr(123))=="STARTED","retained handle required")
Check(_PB_Outcome(False,0,Ptr(123))=="FAILED","failed API cannot authorize operation")
Local $bad=_PB_Start("C:\Temp","arbitrary",1)
Check($bad["handle"]=0,"arbitrary action cannot elevate")
$bad=_PB_Start("C:\Temp","Prepare",-1)
Check($bad["handle"]=0,"invalid cycle cannot elevate")
If IsAdmin() Then Check(Not _PB_Medium(),"elevated frontend cannot claim to be ordinary user")
Local $s=_MS_New("C:\Temp","C:\workspace")
$s["state"]="CLEANUP_DECLINED"
Check(_MS_Stop($s),"explicit finish retries declined cleanup")
Check($s["state"]=="READY_TO_CLEAN","no automatic elevation loop")
Check(_MS_ConsentPhase(True, "Prepare") == "CONSENT_PREPARE", "split prepare awaits consent")
Check(_MS_ConsentPhase(True, "Finish") == "CONSENT_FINISH", "split cleanup awaits consent")
Check(_MS_ConsentPhase(False, "Prepare") == "PREPARING", "legacy CI preparation unchanged")
Check(_MS_ConsentPhase(False, "Finish") == "CLEANING", "legacy CI cleanup unchanged")
Check(_MS_ConsentPhase(True, "Invalid") == "BLOCKED", "unknown action denied")
Check(_MS_ConsentPending("CONSENT_PREPARE"), "prepare consent pending")
Check(_MS_ConsentPending("CONSENT_FINISH"), "cleanup consent pending")
Check(Not _MS_ConsentPending("CONFIGURING"), "user profile configuration is not UAC")
Check(Not _MS_ConsentPending("CLEANING"), "legacy CI cleanup is not UAC")
ConsoleWrite("Privilege boundary native assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed>0)
