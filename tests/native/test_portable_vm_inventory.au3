#include "..\..\source\PortableVmInventory.au3"
Global $checks = 0, $failed = 0
Func Check($condition, $name)
    $checks += 1
    If Not $condition Then
        $failed += 1
        ConsoleWriteError("FAIL VM inventory: " & $name & @CRLF)
    EndIf
EndFunc
Func WriteXml($path, $content)
    Local $h = FileOpen($path, 2 + 256) ; UTF-8 for Cyrillic VM names on English Windows
    If $h == -1 Then Return False
    Local $written = FileWrite($h, $content)
    Local $closed = FileClose($h)
    Return $written And $closed
EndFunc
Local $root = @TempDir & "\PVI Аудит " & @AutoItPID
Check(DirCreate($root), "fixture root created")
Local $r = _PVI_Inspect($root)
Check($r["status"] == "EMPTY", "no profile never creates folders")
Check(Not FileExists($root & "\data"), "read-only absence")
Check(DirCreate($root & "\data\Machines\Имя ВМ\Snapshots"), "nested VM folder")
Local $machineDir = $root & "\data\Machines\Имя ВМ", $file = $machineDir & "\Имя ВМ.vbox"
FileWrite($machineDir & "\disk.vdi", "example disk")
FileWrite($machineDir & "\Snapshots\snap.vdi", "example differencing disk")
Local $uuid = "{11111111-2222-3333-4444-555555555555}"
Local $prefix = '<VirtualBox xmlns="http://www.virtualbox.org/" version="1.20-windows"><Machine uuid="' & $uuid & '" name="Имя ВМ"><MediaRegistry><HardDisks>'
Local $suffix = '</HardDisks></MediaRegistry><Snapshots><Snapshot name="снимок"/></Snapshots></Machine></VirtualBox>'
Local $normal = '<HardDisk location="disk.vdi"/><HardDisk location="Snapshots/snap.vdi"/>'
Check(WriteXml($file, $prefix & $normal & $suffix), "UTF8 config written")
$r = _PVI_Inspect($root)
Check($r["status"] == "CLEAN", "two local media and one snapshot parsed")
Check($r["vm_count"] == 1 And $r["snapshot_count"] == 1 And $r["media_count"] == 2, "correct counts")
Check($r["external_count"] == 0 And $r["missing_count"] == 0, "only local media")
Check(StringInStr($r["report"], "Имя ВМ") > 0, "Unicode VM displayed")
Check(_PVI_MediaLocation($machineDir, "disk.vdi") == "LOCAL", "existing relative medium")
Check(_PVI_MediaLocation($machineDir, "Snapshots/snap.vdi") == "LOCAL", "nested medium")
Check(_PVI_MediaLocation($machineDir, "C:\Old Host\out.vdi") == "EXTERNAL", "absolute Windows medium")
Check(_PVI_MediaLocation($machineDir, "..\shared.vdi") == "EXTERNAL", "relative parent cannot silently count as copied")
Check(_PVI_MediaLocation($machineDir, "missing.vdi") == "MISSING", "local missing disk")
Check(_PVI_MediaLocation($machineDir, "Snapshots\..\disk.vdi") == "EXTERNAL", "ambiguous traversal")
Check(_PVI_MediaLocation($machineDir, "") == "UNSAFE", "blank location invalid")
Check(_PVI_MediaLocation($machineDir, "Snapshots\snap.vdi:ads") == "EXTERNAL", "ADS not traversed")
FileDelete($file)
Check(WriteXml($file, $prefix & $normal & '<HardDisk location="D:\\OtherDrive\\disk.vdi"/>' & '<HardDisk location="missing.vdi"/>' & $suffix), "external fixture written")
$r = _PVI_Inspect($root)
Check($r["status"] == "REVIEW" And $r["external_count"] == 1 And $r["missing_count"] == 1, "external/missing media require review")
Check(StringInStr($r["report"], "D:\\OtherDrive") > 0, "external disk shown without opening it")
Check(StringInStr($r["report"], "missing.vdi") > 0, "missing disk shown")
FileDelete($file)
Check(WriteXml($file, '<!DOCTYPE VirtualBox [<!ENTITY x SYSTEM "file:///C:/Windows/win.ini">]>' & $prefix & $normal & $suffix), "bad-DTD fixture written")
$r = _PVI_Inspect($root)
Check($r["status"] == "BLOCKED", "DOCTYPE/XXE rejected")
FileDelete($file)
Check(WriteXml($file, '<VirtualBox><Machine name="x" uuid="not-a-valid-uuid"/></VirtualBox>'), "invalid identity fixture written")
$r = _PVI_Inspect($root)
Check($r["status"] == "BLOCKED", "invalid machine identity blocks catalog")
FileDelete($file)
Check(WriteXml($file, $prefix & $normal & $suffix), "restored config written")
FileWrite($machineDir & "\not-vm.vbox-prev", "invalid")
$r = _PVI_Inspect($root)
Check($r["status"] == "CLEAN", "historic vbox-prev is not treated as live config")
DirRemove($root, 1)
ConsoleWrite("Portable VM inventory assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
