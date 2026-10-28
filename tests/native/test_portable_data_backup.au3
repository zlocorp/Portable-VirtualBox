#include "..\..\source\PortableDataBackup.au3"
Global $checks = 0, $failed = 0
Func Check($ok, $name)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL offline data backup: " & $name & @CRLF)
    EndIf
EndFunc
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
