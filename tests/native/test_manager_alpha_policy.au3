#include "..\..\source\ManagerSession.au3"
Global $checks=0,$failed=0
Func Check($result,$name)
    $checks+=1
    If Not $result Then
        $failed+=1
        ConsoleWriteError("FAIL alpha policy: "&$name&@CRLF)
    EndIf
EndFunc
Check(Not _MS_AlphaPolicy(False,"X64","PRESENT",10,26100,1),"not automatically enabled")
Check(_MS_AlphaPolicy(True,"X64","PRESENT",10,19045,1),"Windows 10 x64 workstation accepted")
Check(_MS_AlphaPolicy(True,"X64","PRESENT",10,26100,1),"Windows 11 x64 workstation accepted")
Check(Not _MS_AlphaPolicy(True,"ARM64","PRESENT",10,26100,1),"Windows ARM64 refused")
Check(Not _MS_AlphaPolicy(True,"X64","PRESENT",10,26100,3),"server refused even newer build")
Check(Not _MS_AlphaPolicy(True,"X64","PRESENT",10,18363,1),"old Windows 10 refused")
Check(Not _MS_AlphaPolicy(True,"X64","UNKNOWN",10,26100,1),"unknown OS refused")
Check(Not _MS_AlphaPolicy(True,"X64","PRESENT",6,26100,1),"wrong NT major refused")
Check(Not _MS_AlphaAllowed("C:\missing-alpha-runtime"),"missing root/helper is blocked")
ConsoleWrite("Alpha host-policy assertions: "&$checks&"; failed: "&$failed&@CRLF)
Exit ($failed>0)
