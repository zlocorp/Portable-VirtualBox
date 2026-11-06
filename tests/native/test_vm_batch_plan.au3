#include "..\..\source\PortableVmBatchPlan.au3"
; Deterministic filesystem-only fixtures. Never run Oracle or change drivers.
Global $checks = 0, $failures = 0
Func Check($pass, $label)
    $checks += 1
    If Not $pass Then
        $failures += 1
        ConsoleWriteError("FAIL batch plan: " & $label & @CRLF)
    EndIf
EndFunc
Func WriteXml($path, $text)
    Local $h = FileOpen($path, 2 + 256)
    If $h = -1 Then Return False
    Local $result = FileWrite($h, $text), $closed = FileClose($h)
    Return $result And $closed
EndFunc
Local $parent = @TempDir & "\PVB batch test " & @AutoItPID
Local $root = $parent & "\Новая папка", $old = $parent & "\Старая папка"
If FileExists($parent) Then Exit 2
Local $data = $root & "\data\Machines", $global = $root & "\data\.VirtualBox"
Local $folderA = $data & "\Первая ВМ", $folderB = $data & "\Вторая ВМ"
Check(DirCreate($folderA & "\Snapshots"), "make first VM snapshot folder")
Check(DirCreate($folderB & "\Snapshots"), "make second VM snapshot folder")
Check(DirCreate($global), "make private global registry folder")
Local $configA = $folderA & "\Первая ВМ.vbox", $configB = $folderB & "\Вторая ВМ.vbox"
Local $registry = $global & "\VirtualBox.xml"
Local $uuidA = "{11111111-2222-3333-4444-555555555555}", $uuidB = "{99999999-2222-3333-4444-555555555555}"
Local $sourceA = $old & "\data\Machines\Первая ВМ\Первая ВМ.vbox"
Local $sourceB = $old & "\data\Machines\Вторая ВМ\Вторая ВМ.vbox"
Local $fileA = '<VirtualBox xmlns="http://www.virtualbox.org/"><Machine name="Первая ВМ" uuid="' & $uuidA & '" snapshotFolder="Snapshots"><MediaRegistry><HardDisks><HardDisk location="disk.vdi"/><HardDisk location="Snapshots/snap.vdi"/></HardDisks></MediaRegistry><Snapshots><Snapshot name="Снимок A"/></Snapshots></Machine></VirtualBox>'
Local $fileB = '<VirtualBox xmlns="http://www.virtualbox.org/"><Machine name="Вторая ВМ" uuid="' & $uuidB & '" snapshotFolder="Snapshots"><MediaRegistry><HardDisks><HardDisk location="disk.vdi"/><HardDisk location="Snapshots/snap.vdi"/></HardDisks></MediaRegistry><Snapshots><Snapshot name="Снимок B"/></Snapshots></Machine></VirtualBox>'
Check(WriteXml($folderA & "\disk.vdi", "DISK-A"), "make first base disk")
Check(WriteXml($folderA & "\Snapshots\snap.vdi", "SNAP-A"), "make first difference disk")
Check(WriteXml($folderB & "\disk.vdi", "DISK-B"), "make second base disk")
Check(WriteXml($folderB & "\Snapshots\snap.vdi", "SNAP-B"), "make second difference disk")
Check(WriteXml($configA, $fileA), "first VM XML")
Check(WriteXml($configB, $fileB), "second VM XML")
Local $prefix = '<VirtualBox xmlns="http://www.virtualbox.org/"><Global><MachineRegistry>'
Local $suffix = '</MachineRegistry></Global></VirtualBox>'
Local $entryA = '<MachineEntry uuid="' & $uuidA & '" src="' & $sourceA & '"/>'
Local $entryB = '<MachineEntry uuid="' & $uuidB & '" src="' & $sourceB & '"/>'
Local $original = $prefix & $entryA & $entryB & $suffix
Check(WriteXml($registry, $original), "write original two-entry old-root registry")
Local $beforeA = FileRead($configA), $beforeB = FileRead($configB), $beforeRegistry = FileRead($registry)
Local $plan = _PVB_Plan($root)
Check($plan["status"] == "REVIEW_ONLY" And $plan["count"] == 2, "batch plan finds two relocated VMs")
Check($plan["snapshots"] == 2 And $plan["media"] == 4, "all snapshot and media counts included")
Check($plan["old_root"] == $old, "one exact previous portable root")
Check(StringInStr($plan["report"], $uuidA) > 0 And StringInStr($plan["report"], $uuidB) > 0, "both UUIDs in read-only plan")
Check(StringInStr($plan["report"], $sourceA) > 0 And StringInStr($plan["report"], $configB) > 0, "old and new paths displayed")
_LI_Set("ru")
Check(StringInStr(_PVB_Text($plan), "ТОЛЬКО ЧТЕНИЕ") > 0, "Russian batch report explicitly read-only")
_LI_Set("en")
Check(StringInStr(_PVB_Text($plan), "Batch changes and cleanup remain disabled") > 0, "batch report does not authorize any Oracle operation")
Check(_PVR_Plan($root)["status"] == "BLOCKED", "existing single-VM preparation is not authorized for batch")
Check(FileRead($configA) == $beforeA And FileRead($configB) == $beforeB And FileRead($registry) == $beforeRegistry, "batch plan does not change original XML")
Check(Not FileExists($old), "planning never creates previous root")

Check(WriteXml($registry, $prefix & $entryA & StringReplace($entryB, $old, $parent & "\Other Old Root") & $suffix), "different root fixture")
Check(_PVB_Plan($root)["status"] == "BLOCKED", "different prior roots block batch plan")
Check(WriteXml($registry, $original), "restore original batch registry")
Check(WriteXml($registry, $prefix & $entryA & StringReplace($entryB, $uuidB, "{ffffffff-2222-3333-4444-555555555555}") & $suffix), "wrong UUID fixture")
Check(_PVB_Plan($root)["status"] == "BLOCKED", "changed UUID blocks entire batch")
Check(WriteXml($registry, $original), "restore correct UUID")
Check(WriteXml($registry, $prefix & $entryA & '<MachineEntry uuid="' & $uuidB & '" src="..\Machines\Вторая ВМ\Вторая ВМ.vbox"/>' & $suffix), "one local registration fixture")
Check(_PVB_Plan($root)["status"] == "BLOCKED", "mixed old and local registrations are refused")
Check(WriteXml($registry, $original), "restore all stale entries")
Check(WriteXml($configB, '<VirtualBox xmlns="http://www.virtualbox.org/"><Wrapper>' & StringTrimRight(StringTrimLeft($fileB, StringLen('<VirtualBox xmlns="http://www.virtualbox.org/">')), StringLen('</VirtualBox>')) & '</Wrapper></VirtualBox>'), "nested second VM fixture")
Check(_PVB_Plan($root)["status"] == "BLOCKED", "one malformed machine blocks entire batch")
Check(WriteXml($configB, $fileB), "restore correct second VM XML")
Check(FileDelete($folderB & "\Snapshots\snap.vdi"), "remove second snapshot medium")
Check(_PVB_Plan($root)["status"] == "BLOCKED", "missing media blocks entire batch")
Check(WriteXml($folderB & "\Snapshots\snap.vdi", "SNAP-B"), "restore second snapshot medium")
Check(WriteXml($configB, StringReplace($fileB, '<Machine name=', '<Machine stateFile="Snapshots/memory.sav" name=')), "saved state fixture")
Check(_PVB_Plan($root)["status"] == "BLOCKED", "saved guest state blocks entire batch")
Check(WriteXml($configB, $fileB), "restore powered-off metadata")
Check(DirCreate(StringRegExpReplace($sourceB, "\\[^\\]+$", "")), "create old source collision folder")
Check(WriteXml($sourceB, "OLD-VM-STILL-EXISTS"), "create old source collision")
Check(_PVB_Plan($root)["status"] == "BLOCKED", "live old source blocks entire batch")
Check(FileDelete($sourceB), "remove old collision file")
Check(DirRemove($old, 1), "remove only private old test tree")
Check(WriteXml($registry, $prefix & $entryA & $suffix), "single entry fixture")
Check(_PVB_Plan($root)["status"] == "NONE", "single VM must use existing single-VM planner")
Check(WriteXml($registry, $original), "restore two-entry registry")
$plan = _PVB_Plan($root)
Check($plan["status"] == "REVIEW_ONLY" And $plan["count"] == 2, "clean batch report restored after adversarial inputs")
Check(FileRead($configA) == $beforeA And FileRead($configB) == $beforeB And FileRead($registry) == $beforeRegistry, "every byte preserved after read-only checks")
Check(DirRemove($parent, 1), "remove only private fixture")
ConsoleWrite("Native multi-VM read-only plan assertions: " & $checks & " failed=" & $failures & @CRLF)
Exit ($failures > 0)
