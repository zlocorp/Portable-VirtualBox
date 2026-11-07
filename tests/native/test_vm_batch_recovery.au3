#include "..\..\source\PortableVmBatchRecovery.au3"
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
Local $parent = @TempDir & "\PVB recovery test " & @AutoItPID
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
Local $backup = $parent & "\Original-Full-Backup"
Local $copy = _PVB_Backup($root, $backup)
Check($copy["status"] == "BACKUP_ONLY", "create original full backup")
Check(_PBK_Verify($backup), "original backup independently verified")
Local $backupBefore = FileRead($backup & "\data\.VirtualBox\VirtualBox.xml")
Local $baseBefore = FileRead($folderB & "\disk.vdi")
Local $firstLocal = '<MachineEntry uuid="' & $uuidA & '" src="..\Machines\Первая ВМ\Первая ВМ.vbox"/>'
Local $secondLocal = '<MachineEntry uuid="' & $uuidB & '" src="..\Machines\Вторая ВМ\Вторая ВМ.vbox"/>'
Local $state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["stale"] == 2 And $state["absent"] == 0 And $state["local"] == 0, "two stale registrations")
Check($state["next_action"] == "UNREGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidA), "first step is a hint, not an Oracle call")
Check(StringInStr(_PVB_RecoveryText($state), "NOT A COMMAND") > 0, "English explicitly says not a command")
_LI_Set("ru")
Check(StringInStr(_PVB_RecoveryText($state), "ТОЛЬКО ЧТЕНИЕ") > 0, "Russian explicitly read only")
_LI_Set("en")

Local $originalObserved = $state
Check(WriteXml($registry, $prefix & $entryB & $suffix), "simulate first unregister in disposable XML")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["stale"] == 1 And $state["absent"] == 1 And $state["local"] == 0, "first unregister interrupted")
Check($state["next_action"] == "REGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidA), "missing entry addressed before any new unregister")
Check(_PVB_TransitionValid($originalObserved, $state, "UNREGISTER", StringLower($uuidA)), "only first unregister transition is valid")
Local $badCount = _PVB_Reconcile($root, $backup)
$badCount["absent"] = 0
Check(Not _PVB_TransitionValid($originalObserved, $badCount, "UNREGISTER", StringLower($uuidA)), "forged state count is rejected")
Local $badStatus = _PVB_Reconcile($root, $backup)
$badStatus["status"] = "COMPLETE"
Check(Not _PVB_TransitionValid($originalObserved, $badStatus, "UNREGISTER", StringLower($uuidA)), "premature COMPLETE is rejected")
Local $wrongHint = $originalObserved["next_uuid"]
$originalObserved["next_uuid"] = StringLower($uuidB)
Check(Not _PVB_TransitionValid($originalObserved, $state, "UNREGISTER", StringLower($uuidA)), "forged next step target is rejected")
$originalObserved["next_uuid"] = $wrongHint
Local $rogue = _PVB_Reconcile($root, $backup)
Local $rogueStates = $rogue["states"]
$rogueStates["{ffffffff-2222-3333-4444-abcdef123456}"] = "STALE"
$rogue["states"] = $rogueStates
Check(Not _PVB_TransitionValid($originalObserved, $rogue, "UNREGISTER", StringLower($uuidA)), "additional unseen state UUID is rejected")
Local $shifted = _PVB_Reconcile($root, $backup)
Local $shiftedOrder = $shifted["order"]
Local $firstKey = $shiftedOrder[0]
$shiftedOrder[0] = $shiftedOrder[1]
$shiftedOrder[1] = $firstKey
$shifted["order"] = $shiftedOrder
Check(Not _PVB_TransitionValid($originalObserved, $shifted, "UNREGISTER", StringLower($uuidA)), "reordered original UUID schedule is rejected")
Local $differentPath = _PVB_Reconcile($root, $backup)
Local $pathMap = $differentPath["paths"]
$pathMap[StringLower($uuidA)] = "C:\foreign\changed.vbox"
$differentPath["paths"] = $pathMap
Check(Not _PVB_TransitionValid($originalObserved, $differentPath, "UNREGISTER", StringLower($uuidA)), "changed VM target path is rejected")
Local $ignoredMissing = _PVB_Reconcile($root, $backup)
Local $ignoredStates = $ignoredMissing["states"]
$ignoredStates[StringLower($uuidB)] = "ABSENT"
$ignoredMissing["states"] = $ignoredStates
$ignoredMissing["stale"] = 0
$ignoredMissing["absent"] = 2
Check(_PVB_StateConsistent($ignoredMissing), "synthetic second unregister state is internally consistent")
Check(Not _PVB_TransitionValid($state, $ignoredMissing, "UNREGISTER", StringLower($uuidB)), "must recover ABSENT before unregistering another VM")
Local $missingFirst = $state

Check(WriteXml($registry, $prefix & $firstLocal & $entryB & $suffix), "simulate first completed re-registration")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["local"] == 1 And $state["stale"] == 1 And $state["absent"] == 0, "first registration completed")
Check($state["next_action"] == "UNREGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidB), "second VM pending")
Check(_PVB_TransitionValid($missingFirst, $state, "REGISTER", StringLower($uuidA)), "only first register transition is valid")
Check(Not _PVB_TransitionValid($originalObserved, $state, "REGISTER", StringLower($uuidA)), "skipped unregister observation is not a transaction")
Local $firstFinished = $state

Check(WriteXml($registry, $prefix & $firstLocal & $suffix), "simulate second interrupted unregister")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["local"] == 1 And $state["absent"] == 1 And $state["stale"] == 0, "second unregister interrupted")
Check($state["next_action"] == "REGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidB), "second VM needs only registration")
Check(_PVB_TransitionValid($firstFinished, $state, "UNREGISTER", StringLower($uuidB)), "only second unregister transition is valid")
Local $missingSecond = $state

Check(WriteXml($registry, $prefix & $firstLocal & $secondLocal & $suffix), "simulate completed original registration set")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "COMPLETE" And $state["local"] == 2 And $state["stale"] == 0 And $state["absent"] == 0, "all machines local and complete")
Check($state["next_action"] == "" And StringInStr(_PVB_RecoveryText($state), "No new changes required") > 0, "completed state never suggests repeating a mutation")
Check(_PVB_TransitionValid($missingSecond, $state, "REGISTER", StringLower($uuidB)), "only second register transition is valid")
Check(Not _PVB_TransitionValid($state, $originalObserved, "UNREGISTER", StringLower($uuidA)), "completed transaction may not regress to stale")

Check(WriteXml($registry, $prefix & $firstLocal & '<MachineEntry uuid="{ffffffff-2222-3333-4444-abcdef123456}" src="..\Machines\Вторая ВМ\Вторая ВМ.vbox"/>' & $suffix), "foreign registration fixture")
Check(_PVB_Reconcile($root, $backup)["status"] == "BLOCKED", "unknown registration refused")
Check(WriteXml($registry, $prefix & $firstLocal & $entryB & $suffix), "restore known partial state")
Check(WriteXml($folderB & "\disk.vdi", "FOREIGN-DISK-CHANGES"), "change guest disk bytes")
Check(_PVB_Reconcile($root, $backup)["status"] == "BLOCKED", "changed virtual disk refused")
Check(WriteXml($folderB & "\disk.vdi", $baseBefore), "restore original second base disk")
Check(_PVB_Reconcile($root, $backup)["status"] == "REVIEW_ONLY", "original incomplete state recovered after rejecting changes")
Check(FileRead($backup & "\data\.VirtualBox\VirtualBox.xml") == $backupBefore And _PBK_Verify($backup), "original backup unchanged")
Check(DirRemove($parent, 1), "remove only private test fixture")
ConsoleWrite("Native batch registration reconciliation assertions: " & $checks & " failed=" & $failures & @CRLF)
Exit ($failures > 0)
