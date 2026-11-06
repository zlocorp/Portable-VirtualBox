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
Check(DirCreate($root & "\data\.VirtualBox"), "private registry directory")
Local $registry = $root & "\data\.VirtualBox\VirtualBox.xml"
Local $regHead = '<VirtualBox xmlns="http://www.virtualbox.org/"><Global><MachineRegistry>'
Local $regTail = '</MachineRegistry></Global></VirtualBox>'
Local $regEntry = '<MachineEntry uuid="' & $uuid & '" src="..\Machines\Имя ВМ\Имя ВМ.vbox"/>'
Check(WriteXml($registry, $regHead & $regEntry & $regTail), "portable registry created")
$r = _PVI_Inspect($root)
Check($r["status"] == "CLEAN", "two local media and one snapshot parsed")
Check($r["vm_count"] == 1 And $r["snapshot_count"] == 1 And $r["media_count"] == 2, "correct counts")
Check($r["registered_count"] == 1 And $r["external_registry_count"] == 0, "global VM registry counted and in-root")
Check(StringInStr($r["report"], _LI("vm.registered")) > 0, "registry summary displayed")
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
; A registered VM entirely outside the copied data tree is a risk even
; when every discovered .vbox has local media.
Check(WriteXml($registry, $regHead & $regEntry & '<MachineEntry uuid="{99999999-2222-3333-4444-555555555555}" src="D:\Outside\VM.vbox"/>' & $regTail), "external machine registry entry")
$r = _PVI_Inspect($root)
Check($r["status"] == "REVIEW" And $r["external_registry_count"] == 1, "external registered VM requires review")
Check(StringInStr($r["report"], "D:\Outside") > 0, "external registered machine path visible")
Check(WriteXml($registry, $regHead & $regTail), "empty registry written")
$r = _PVI_Inspect($root)
Check($r["status"] == "REVIEW" And StringInStr($r["report"], _LI("vm.unregistered")) > 0, "saved .vbox not silently assumed registered")
FileDelete($registry)
$r = _PVI_Inspect($root)
Check($r["status"] == "REVIEW" And StringInStr($r["report"], _LI("vm.registry_missing")) > 0, "missing VirtualBox.xml is a review warning")
Check(WriteXml($registry, '<!DOCTYPE VirtualBox [<!ENTITY leak SYSTEM "file:///C:/Windows/win.ini">]>' & $regHead & $regEntry & $regTail), "registry DTD fixture")
$r = _PVI_Inspect($root)
Check($r["status"] == "BLOCKED", "global VirtualBox.xml DTD / XXE blocked")
Check(WriteXml($registry, $regHead & $regEntry & $regTail), "restore clean registry")
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
; Reject fake .vbox Machine payloads nested under an unrelated node,
; or with a different XML namespace, before declaring all media portable.
Local $badMachineInputs[3] = [ _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Wrapper><Machine uuid="' & $uuid & '" name="Имя ВМ"><HardDisk location="disk.vdi"/></Machine></Wrapper></VirtualBox>', _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Machine xmlns="urn:foreign" uuid="' & $uuid & '" name="Имя ВМ"><HardDisk location="disk.vdi"/></Machine></VirtualBox>', _
    $prefix & $normal & $suffix ]
; The third case uses an extra root-level element, not a second VirtualBox root.
$badMachineInputs[2] = StringReplace($prefix & $normal & $suffix, '</VirtualBox>', '<Other /></VirtualBox>')
For $i = 0 To UBound($badMachineInputs) - 1
    Check(WriteXml($file, $badMachineInputs[$i]), "write malformed machine input")
    $r = _PVI_Inspect($root)
    Check($r["status"] == "BLOCKED", _
        ($i = 0 ? "nested Machine blocks inventory" : ($i = 1 ? "foreign Machine namespace blocks inventory" : "extra top-level Machine sibling blocks inventory")))
Next
Check(WriteXml($file, $prefix & $normal & $suffix), "valid machine fixture restored after malformed inputs")
$r = _PVI_Inspect($root)
Check($r["status"] == "CLEAN", "valid direct Machine with official namespace remains portable")
; Multi-VM inventory is observational. This test never registers or mutates
; machines using Oracle. Bulk rebind remains unimplemented.
Local $secondUuid = "{99999999-2222-3333-4444-555555555555}"
Local $secondDir = $root & "\data\Machines\Вторая ВМ", $secondConfig = $secondDir & "\Вторая ВМ.vbox"
Check(DirCreate($secondDir & "\Snapshots"), "create second machine")
Check(FileWrite($secondDir & "\disk.vdi", "SECOND-BASE") <> 0, "second base VDI")
Check(FileWrite($secondDir & "\Snapshots\snap.vdi", "SECOND-DIFF") <> 0, "second snapshot")
Local $secondBody = StringReplace(StringReplace($prefix & $normal & $suffix, $uuid, $secondUuid), "Имя ВМ", "Вторая ВМ")
Check(WriteXml($secondConfig, $secondBody), "second machine config")
Local $secondEntry = '<MachineEntry uuid="' & $secondUuid & '" src="..\Machines\Вторая ВМ\Вторая ВМ.vbox"/>'
Check(WriteXml($registry, $regHead & $regEntry & $secondEntry & $regTail), "two local registrations")
$r = _PVI_Inspect($root)
Check($r["status"] == "CLEAN" And $r["vm_count"] == 2 And $r["registered_count"] == 2, "two registered local VMs remain clean")
Check($r["snapshot_count"] == 2 And $r["media_count"] == 4, "both VM snapshot graphs counted")
Local $swapped = $regHead & StringReplace($regEntry, $uuid, $secondUuid) & StringReplace($secondEntry, $secondUuid, $uuid) & $regTail
Check(WriteXml($registry, $swapped), "swap registration UUIDs")
$r = _PVI_Inspect($root)
Check($r["status"] == "BLOCKED", "registration UUID must match config UUID")
Check(WriteXml($registry, $regHead & $regEntry & $secondEntry & $regTail), "restore correct registrations")
Check(WriteXml($secondConfig, StringReplace($secondBody, $secondUuid, $uuid)), "duplicate machine UUID fixture")
$r = _PVI_Inspect($root)
Check($r["status"] == "BLOCKED", "duplicate VM config UUID is blocked")
Check(WriteXml($secondConfig, $secondBody), "restore second VM UUID")
Local $invalidEntries[7] = [ _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Global><Other>' & $regEntry & '</Other></Global></VirtualBox>', _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><MachineRegistry>' & $regEntry & '</MachineRegistry></VirtualBox>', _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Global><MachineRegistry><Other>' & $regEntry & '</Other></MachineRegistry></Global></VirtualBox>', _
    '<VirtualBox xmlns="urn:foreign"><Global><MachineRegistry>' & $regEntry & '</MachineRegistry></Global></VirtualBox>', _
    $regHead & '<MachineEntry uuid="bad" src="..\Machines\Имя ВМ\Имя ВМ.vbox"/>' & $regTail, _
    $regHead & $regEntry & '<MachineEntry uuid="' & $uuid & '" src="..\Machines\Вторая ВМ\Вторая ВМ.vbox"/>' & $regTail, _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Global><MachineRegistry xmlns="urn:foreign">' & $regEntry & '</MachineRegistry></Global></VirtualBox>']
For $value In $invalidEntries
    Check(WriteXml($registry, $value), "malformed registry fixture")
    $r = _PVI_Inspect($root)
    Check($r["status"] == "BLOCKED", "nested or malformed registry is blocked")
Next
Check(WriteXml($registry, $regHead & $regEntry & $regEntry & $regTail), "duplicate UUID test fixture")
$r = _PVI_Inspect($root)
Check($r["status"] == "BLOCKED", "duplicate registration UUID is blocked")
Check(WriteXml($registry, $regHead & $regEntry & $secondEntry & $regTail), "restore multi-VM registry")
Check(FileRead($file) == ($prefix & $normal & $suffix), "first VM bytes unchanged by audit")
Check(FileRead($secondConfig) == $secondBody, "second VM bytes unchanged by audit")
DirRemove($root, 1)
ConsoleWrite("Portable VM inventory assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
