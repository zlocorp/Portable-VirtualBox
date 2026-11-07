#include "..\..\source\PortableVmBatchRecovery.au3"
; Deterministic filesystem-only fixtures. Never run Oracle or change drivers.
Global $checks = 0, $failures = 0
Global $recoveryPhaseClock = TimerInit()
; The CI runner exposes this private disposable test directory. On a
; native timeout it prints the last completed phase, never VM/user paths.
Func RecoveryPhase($name)
    Local $root = EnvGet("PVBOX_NATIVE_TEST_DIR")
    If $root == "" Then Return
    Local $h = FileOpen($root & "\batch-recovery-phase.txt", 1 + 256)
    If $h = -1 Then Return
    FileWrite($h, Int(TimerDiff($recoveryPhaseClock)) & "ms " & $name & @CRLF)
    FileClose($h)
EndFunc
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
; Clone ONLY the already re-observed small evidence maps for adversarial
; model tests. Do not rescan and rehash the whole data/ tree for every
; deliberately forged field; actual before/after snapshots are still read
; independently by _PVB_Reconcile at each simulated registry change.
Func CloneSnapshot($original)
    Local $copy = _PVB_RecoveryNew()
    For $field In MapKeys($original)
        $copy[$field] = $original[$field]
    Next
    Local $sourceStates = $original["states"], $sourcePaths = $original["paths"]
    Local $sourceHashes = $original["config_sha256"], $sourceOrder = $original["order"]
    Local $states[], $paths[], $hashes[], $order[UBound($sourceOrder)]
    For $uuid In MapKeys($sourceStates)
        $states[$uuid] = $sourceStates[$uuid]
    Next
    For $uuid In MapKeys($sourcePaths)
        $paths[$uuid] = $sourcePaths[$uuid]
    Next
    For $uuid In MapKeys($sourceHashes)
        $hashes[$uuid] = $sourceHashes[$uuid]
    Next
    For $i = 0 To UBound($sourceOrder) - 1
        $order[$i] = $sourceOrder[$i]
    Next
    $copy["states"] = $states
    $copy["paths"] = $paths
    $copy["config_sha256"] = $hashes
    $copy["order"] = $order
    Return $copy
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
RecoveryPhase("before-backup")
Local $copy = _PVB_Backup($root, $backup)
Check($copy["status"] == "BACKUP_ONLY", "create original full backup")
Check(_PBK_Verify($backup), "original backup independently verified")
Local $backupBefore = FileRead($backup & "\data\.VirtualBox\VirtualBox.xml")
Local $baseBefore = FileRead($folderB & "\disk.vdi")
Local $firstLocal = '<MachineEntry uuid="' & $uuidA & '" src="..\Machines\Первая ВМ\Первая ВМ.vbox"/>'
Local $secondLocal = '<MachineEntry uuid="' & $uuidB & '" src="..\Machines\Вторая ВМ\Вторая ВМ.vbox"/>'
RecoveryPhase("before-baseline-reconcile")
Local $state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["stale"] == 2 And $state["absent"] == 0 And $state["local"] == 0, "two stale registrations")
Check($state["next_action"] == "UNREGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidA), "first step is a hint, not an Oracle call")
Check(StringInStr(_PVB_RecoveryText($state), "NOT A COMMAND") > 0, "English explicitly says not a command")
_LI_Set("ru")
Check(StringInStr(_PVB_RecoveryText($state), "ТОЛЬКО ЧТЕНИЕ") > 0, "Russian explicitly read only")
_LI_Set("en")

RecoveryPhase("after-baseline-reconcile")
Local $originalObserved = $state
Check(WriteXml($registry, $prefix & $entryB & $suffix), "simulate first unregister in disposable XML")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["stale"] == 1 And $state["absent"] == 1 And $state["local"] == 0, "first unregister interrupted")
Check($state["next_action"] == "REGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidA), "missing entry addressed before any new unregister")
RecoveryPhase("after-first-unregister")
Check(_PVB_TransitionValid($originalObserved, $state, "UNREGISTER", StringLower($uuidA)), "only first unregister transition is valid")
Local $badCount = CloneSnapshot($state)
$badCount["absent"] = 0
Check(Not _PVB_TransitionValid($originalObserved, $badCount, "UNREGISTER", StringLower($uuidA)), "forged state count is rejected")
Local $badStatus = CloneSnapshot($state)
$badStatus["status"] = "COMPLETE"
Check(Not _PVB_TransitionValid($originalObserved, $badStatus, "UNREGISTER", StringLower($uuidA)), "premature COMPLETE is rejected")
Local $wrongHint = $originalObserved["next_uuid"]
$originalObserved["next_uuid"] = StringLower($uuidB)
Check(Not _PVB_TransitionValid($originalObserved, $state, "UNREGISTER", StringLower($uuidA)), "forged next step target is rejected")
$originalObserved["next_uuid"] = $wrongHint
Local $rogue = CloneSnapshot($state)
Local $rogueStates = $rogue["states"]
$rogueStates["{ffffffff-2222-3333-4444-abcdef123456}"] = "STALE"
$rogue["states"] = $rogueStates
Check(Not _PVB_TransitionValid($originalObserved, $rogue, "UNREGISTER", StringLower($uuidA)), "additional unseen state UUID is rejected")
Local $shifted = CloneSnapshot($state)
Local $shiftedOrder = $shifted["order"]
Local $firstKey = $shiftedOrder[0]
$shiftedOrder[0] = $shiftedOrder[1]
$shiftedOrder[1] = $firstKey
$shifted["order"] = $shiftedOrder
Check(Not _PVB_TransitionValid($originalObserved, $shifted, "UNREGISTER", StringLower($uuidA)), "reordered original UUID schedule is rejected")
Local $differentPath = CloneSnapshot($state)
Local $pathMap = $differentPath["paths"]
$pathMap[StringLower($uuidA)] = "C:\foreign\changed.vbox"
$differentPath["paths"] = $pathMap
Check(Not _PVB_TransitionValid($originalObserved, $differentPath, "UNREGISTER", StringLower($uuidA)), "changed VM target path is rejected")
Local $ignoredMissing = CloneSnapshot($state)
Local $ignoredStates = $ignoredMissing["states"]
$ignoredStates[StringLower($uuidB)] = "ABSENT"
$ignoredMissing["states"] = $ignoredStates
$ignoredMissing["stale"] = 0
$ignoredMissing["absent"] = 2
Check(_PVB_StateConsistent($ignoredMissing), "synthetic second unregister state is internally consistent")
Check(Not _PVB_TransitionValid($state, $ignoredMissing, "UNREGISTER", StringLower($uuidB)), "must recover ABSENT before unregistering another VM")
Check(_PVB_StateConsistent($state) And _PVB_StateConsistent($originalObserved), "adversarial clones do not mutate genuine observations")
Check(StringLen($originalObserved["current_registry_sha256"]) == 64 And _
        $originalObserved["current_registry_sha256"] <> $state["current_registry_sha256"], "successful unregister changes observed registry SHA-256")
Local $sameRegistry = CloneSnapshot($state)
$sameRegistry["current_registry_sha256"] = $originalObserved["current_registry_sha256"]
Check(Not _PVB_TransitionValid($originalObserved, $sameRegistry, "UNREGISTER", StringLower($uuidA)), "forged unchanged registry hash is rejected")
Local $changedHash = CloneSnapshot($state)
Local $hashMap = $changedHash["config_sha256"]
$hashMap[StringLower($uuidB)] = StringRepeat("a", 64)
$changedHash["config_sha256"] = $hashMap
Check(Not _PVB_TransitionValid($originalObserved, $changedHash, "UNREGISTER", StringLower($uuidA)), "forged VM configuration hash is rejected")
Local $invalidHash = CloneSnapshot($state)
$invalidHash["current_registry_sha256"] = "invalid"
Check(Not _PVB_TransitionValid($originalObserved, $invalidHash, "UNREGISTER", StringLower($uuidA)), "malformed registry SHA-256 is rejected")
RecoveryPhase("after-first-unregister-forgery")
Local $missingFirst = $state

Check(WriteXml($registry, $prefix & $firstLocal & $entryB & $suffix), "simulate first completed re-registration")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["local"] == 1 And $state["stale"] == 1 And $state["absent"] == 0, "first registration completed")
Check($state["next_action"] == "UNREGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidB), "second VM pending")
Check(_PVB_TransitionValid($missingFirst, $state, "REGISTER", StringLower($uuidA)), "only first register transition is valid")
Check(Not _PVB_TransitionValid($originalObserved, $state, "REGISTER", StringLower($uuidA)), "skipped unregister observation is not a transaction")
RecoveryPhase("after-first-register")
Local $firstFinished = $state

Check(WriteXml($registry, $prefix & $firstLocal & $suffix), "simulate second interrupted unregister")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "REVIEW_ONLY" And $state["local"] == 1 And $state["absent"] == 1 And $state["stale"] == 0, "second unregister interrupted")
Check($state["next_action"] == "REGISTER_HINT_ONLY" And $state["next_uuid"] == StringLower($uuidB), "second VM needs only registration")
Check(_PVB_TransitionValid($firstFinished, $state, "UNREGISTER", StringLower($uuidB)), "only second unregister transition is valid")
RecoveryPhase("after-second-unregister")
Local $missingSecond = $state

Check(WriteXml($registry, $prefix & $firstLocal & $secondLocal & $suffix), "simulate completed original registration set")
$state = _PVB_Reconcile($root, $backup)
Check($state["status"] == "COMPLETE" And $state["local"] == 2 And $state["stale"] == 0 And $state["absent"] == 0, "all machines local and complete")
Check($state["next_action"] == "" And StringInStr(_PVB_RecoveryText($state), "No new changes required") > 0, "completed state never suggests repeating a mutation")
Check(_PVB_TransitionValid($missingSecond, $state, "REGISTER", StringLower($uuidB)), "only second register transition is valid")
Check(Not _PVB_TransitionValid($state, $originalObserved, "UNREGISTER", StringLower($uuidA)), "completed transaction may not regress to stale")
RecoveryPhase("before-trace-tests")
Local $traceSteps[5] = [$originalObserved, $missingFirst, $firstFinished, $missingSecond, $state]
Local $traceActions[4] = ["UNREGISTER", "REGISTER", "UNREGISTER", "REGISTER"]
Local $traceUuids[4] = [StringLower($uuidA), StringLower($uuidA), StringLower($uuidB), StringLower($uuidB)]
Check(_PVB_TraceValid($traceSteps, $traceActions, $traceUuids, True), "complete ordered transition trace accepted")
Check(_PVB_TraceValid($traceSteps, $traceActions, $traceUuids, False), "complete trace also valid for inspection")
Local $initialOnly[1] = [$originalObserved], $noActions[0], $noUuids[0]
Check(_PVB_TraceValid($initialOnly, $noActions, $noUuids, False), "initial verified snapshot may be inspected")
Check(Not _PVB_TraceValid($initialOnly, $noActions, $noUuids, True), "no-step trace is never a completed batch")
Local $partialTrace[2] = [$originalObserved, $missingFirst]
Local $partialActions[1] = ["UNREGISTER"], $partialUuids[1] = [StringLower($uuidA)]
Check(_PVB_TraceValid($partialTrace, $partialActions, $partialUuids, False), "interrupted first unregister trace is inspectable")
Check(Not _PVB_TraceValid($partialTrace, $partialActions, $partialUuids, True), "interrupted trace cannot claim complete")
Local $skippedTrace[3] = [$originalObserved, $missingFirst, $firstFinished]
Local $badActions[2] = ["UNREGISTER", "UNREGISTER"], $badUuids[2] = [StringLower($uuidA), StringLower($uuidB)]
Check(Not _PVB_TraceValid($skippedTrace, $badActions, $badUuids, False), "trace with skipped register is rejected")
Local $repeatedTrace[3] = [$originalObserved, $missingFirst, $missingFirst]
Local $repeatActions[2] = ["UNREGISTER", "UNREGISTER"], $repeatUuids[2] = [StringLower($uuidA), StringLower($uuidA)]
Check(Not _PVB_TraceValid($repeatedTrace, $repeatActions, $repeatUuids, False), "replayed unregister transition is rejected")
Local $wrongOrderUuids[4] = [StringLower($uuidB), StringLower($uuidA), StringLower($uuidB), StringLower($uuidB)]
Check(Not _PVB_TraceValid($traceSteps, $traceActions, $wrongOrderUuids, True), "out-of-order UUID step is rejected")
Local $prematureTrace[2] = [$missingFirst, $firstFinished], $registerAction[1] = ["REGISTER"], $registerUuid[1] = [StringLower($uuidA)]
Check(Not _PVB_TraceValid($prematureTrace, $registerAction, $registerUuid, True), "trace without original stale baseline is rejected")
Check(Not _PVB_TraceValid($traceSteps, $traceActions, $partialUuids, True), "incomplete UUID event list is rejected")
Local $wrongAction[4] = ["REGISTER", "REGISTER", "UNREGISTER", "REGISTER"]
RecoveryPhase("after-trace-tests")
Check(Not _PVB_TraceValid($traceSteps, $wrongAction, $traceUuids, True), "wrong first action is rejected")

RecoveryPhase("before-foreign-fixture")
Check(WriteXml($registry, $prefix & $firstLocal & '<MachineEntry uuid="{ffffffff-2222-3333-4444-abcdef123456}" src="..\Machines\Вторая ВМ\Вторая ВМ.vbox"/>' & $suffix), "foreign registration fixture")
Check(_PVB_Reconcile($root, $backup)["status"] == "BLOCKED", "unknown registration refused")
Check(WriteXml($registry, $prefix & $firstLocal & $entryB & $suffix), "restore known partial state")
Check(WriteXml($folderB & "\disk.vdi", "FOREIGN-DISK-CHANGES"), "change guest disk bytes")
Check(_PVB_Reconcile($root, $backup)["status"] == "BLOCKED", "changed virtual disk refused")
Check(WriteXml($folderB & "\disk.vdi", $baseBefore), "restore original second base disk")
Check(_PVB_Reconcile($root, $backup)["status"] == "REVIEW_ONLY", "original incomplete state recovered after rejecting changes")
Check(FileRead($backup & "\data\.VirtualBox\VirtualBox.xml") == $backupBefore And _PBK_Verify($backup), "original backup unchanged")
RecoveryPhase("before-fixture-cleanup")
Check(DirRemove($parent, 1), "remove only private test fixture")
ConsoleWrite("Native batch registration reconciliation assertions: " & $checks & " failed=" & $failures & @CRLF)
Exit ($failures > 0)
