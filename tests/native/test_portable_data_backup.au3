#include "..\..\source\PortableDataBackup.au3"
Global $checks = 0, $failed = 0
Func Check($ok, $name)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL offline data backup: " & $name & @CRLF)
    EndIf
EndFunc
; Diagnostic formatting consumes already captured observations. It must keep
; refusal status/error/PID visible without introducing another host query.
Local $diagnostic=_PortableOfflineDiagnosticText("installation","UNKNOWN",-1,"installation-observation",5,0,"","open")
Check(StringInStr($diagnostic,"installation status=UNKNOWN count=-1")>0 And StringInStr($diagnostic,"error=5")>0 And StringInStr($diagnostic,"stage=open")>0,"unknown installation diagnostic retains original status and error")
$diagnostic=_PortableOfflineDiagnosticText("installation","PRESENT",1,"installation-observation",0)
Check(StringInStr($diagnostic,"installation status=PRESENT count=1")>0,"present installation diagnostic remains a refusal")
$diagnostic=_PortableOfflineDiagnosticText("services","PRESENT",2,"services-present",0,0,"VBoxSUP,VBoxSDS","complete")
Check(StringInStr($diagnostic,"services status=PRESENT count=2")>0 And StringInStr($diagnostic,"name=VBoxSUP,VBoxSDS")>0,"service diagnostic retains count and fixed observed names")
$diagnostic=_PortableOfflineDiagnosticText("processes","UNKNOWN",-1,"process-open",5,1234,"VBoxSVC.exe","open")
Check(StringInStr($diagnostic,"processes status=UNKNOWN count=-1")>0 And StringInStr($diagnostic,"reason=process-open error=5 pid=1234")>0,"unknown process diagnostic retains failure reason error and PID")
$diagnostic=_PortableOfflineDiagnosticText("processes","KNOWN",1,"matching-processes",0,4321,"VBoxSVC.exe","complete")
Check(StringInStr($diagnostic,"processes status=KNOWN count=1")>0 And StringInStr($diagnostic,"pid=4321 name=VBoxSVC.exe")>0,"known process diagnostic identifies the observed blocker")
$diagnostic=_PortableOfflineDiagnosticText("processes","UNKNOWN",-1,"process-read" & @CRLF & "injected",5)
Check(StringRegExp($diagnostic,"[\x00-\x1f\x7f]")=0,"diagnostics cannot inject another log line")
Local $longDiagnostic=""
For $i=1 To 600
    $longDiagnostic &= "x"
Next
Check(StringLen(_PortableOfflineDiagnosticText("processes","UNKNOWN",-1,$longDiagnostic,5))=512,"diagnostic record stays bounded")
Local $parent = @TempDir & "\Portable Backup Тест " & @AutoItPID
Local $root = $parent & "\root", $outside = $parent & "\destination"
Check(DirCreate($root), "create source root")
Check(DirCreate($outside), "create destination parent")
Local $profile = _PP_Ensure($root)
Check($profile["status"] == "READY", "create private data folders")
Local $machines = $root & "\data\Machines\ВМ с пробелами\Snapshots"
Check(DirCreate($machines), "create nested VM snapshot folder")
FileWrite($root & "\data\Machines\ВМ с пробелами\machine.vbox", "VM XML fixture")
FileWrite($machines & "\snapshot.vdi", "Virtual disk byte fixture")
Local $empty = FileOpen($machines & "\zero.bin", 2)
FileClose($empty)
Local $dest = $outside & "\backup-one"
Check(Not _PBK_ValidPath($root, $root & "\data\nested"), "cannot place backup inside source")
Check(Not _PBK_ValidPath($root, $parent), "cannot place backup above source")
Check(_PBK_ValidPath($root, $dest), "destination permitted outside portable root")
Local $result = _PBK_Create($root, $dest)
Check($result == 0, "SHA-256 backup published successfully")
Check(_PBK_Verify($dest), "backup independently verifies")
Check(FileRead($dest & "\data\Machines\ВМ с пробелами\machine.vbox") == "VM XML fixture", "VM config preserved")
Check(FileRead($dest & "\data\Machines\ВМ с пробелами\Snapshots\snapshot.vdi") == "Virtual disk byte fixture", "nested snapshot byte copy")
Check(FileExists($dest & "\data\Machines\ВМ с пробелами\Snapshots\zero.bin"), "empty file retained")
Local $restored = $outside & "\restored-root"
Check(_PBK_Restore($dest, $restored) == 0, "restore to a new root succeeds")
Check(_PBK_Verify($restored), "restored root verifies independently")
Check(FileRead($restored & "\data\Machines\ВМ с пробелами\machine.vbox") == "VM XML fixture", "restored VM configuration bytes match")
Check(_PBK_Restore($dest, $restored) == 2, "restoring cannot overwrite existing root")
Check(Not FileExists($restored & "\Portable-VirtualBox.exe"), "restore does not fake launcher executable")
Check(_PBK_Create($root, $dest) == 2, "existing backup never overwritten")
Check(Not FileExists($dest & ".pending"), "successful backup removed staging")
FileWrite($dest & "\data\extra.bin", "unexpected file")
Check(Not _PBK_Verify($dest), "extra file invalidates manifest coverage")
FileDelete($dest & "\data\extra.bin")
Check(_PBK_Verify($dest), "original copy verifies after removing extra fixture")
FileWrite($dest & "\data\Machines\ВМ с пробелами\machine.vbox", "CORRUPT")
Check(Not _PBK_Verify($dest), "changed payload is detected")
Check(_PBK_Restore($dest, $outside & "\bad-restore") == 2, "damaged backup never restored")
Check(Not FileExists($outside & "\bad-restore"), "bad restore leaves no target directory")
Local $cancel = $outside & "\cancelled"
FileWrite($cancel & ".cancel-request", "cancel")
Check(Not _PBK_ValidPath($root, $cancel), "preexisting cancellation marker blocks replacement")
Check(_PBK_Create($root, $cancel) == 2, "blocked backup does not copy anything")
Check(Not FileExists($cancel), "cancelled final folder absent")
Check(FileRead($root & "\data\Machines\ВМ с пробелами\machine.vbox") == "VM XML fixture", "original VM file untouched")
DirRemove($parent, 1)
ConsoleWrite("Native offline data backup checks: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
