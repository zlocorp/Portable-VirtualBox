#include-once
#include "PortableVmBatchPlan.au3"

; Strictly read-only reconciliation of one complete original full-tree
; backup against a partly migrated 2-16 VM registry. No transaction actions
; are granted by this result. A separate owned-session transaction must bind
; the verified backup and re-observe every mutation before it can be enabled.
Func _PVB_RecoveryNew()
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["reason"] = "unverified-batch-recovery"
    $r["count"] = 0
    $r["stale"] = 0
    $r["absent"] = 0
    $r["local"] = 0
    $r["next_action"] = ""
    $r["next_uuid"] = ""
    $r["next_path"] = ""
    $r["backup"] = ""
    $r["manifest_sha256"] = ""
    $r["origin_sha256"] = ""
    $r["root"] = ""
    Local $states[], $paths[], $order[0]
    $r["states"] = $states
    $r["paths"] = $paths
    $r["order"] = $order
    $r["report"] = ""
    Return $r
EndFunc

Func _PVB_RecoveryBlocked($r, $reason)
    $r["status"] = "BLOCKED"
    $r["reason"] = $reason
    $r["next_action"] = ""
    $r["next_uuid"] = ""
    $r["next_path"] = ""
    $r["report"] = ""
    Return $r
EndFunc

; Report composition is bounded and deliberately never an Oracle CLI script.
Func _PVB_RecoveryAppend(ByRef $r, $line)
    If Not IsString($line) Or StringLen($line) > 1200 Then Return False
    If StringRegExp($line, "[\x00-\x1f]") Then Return False
    If StringLen($r["report"]) + StringLen($line) > 26000 Then Return False
    $r["report"] &= $line & @CRLF
    Return True
EndFunc

; This public function is strictly offline. A caller must not interpret
; the next_action hint as proof or authority to run any Oracle command.
Func _PVB_Reconcile($root, $backup)
    Local $r = _PVB_RecoveryNew()
    If Not _PBK_Offline() Then Return _PVB_RecoveryBlocked($r, "host-not-offline")
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Or _
            Not _PP_RootSafe($backup) Or Not _PP_ParentsSafe($backup) Or _
            _PBK_IsUnder($root, $backup) Or _PBK_IsUnder($backup, $root) Then _
            Return _PVB_RecoveryBlocked($r, "unsafe-or-overlapping-backup")
    If Not _PBK_Verify($backup) Then Return _PVB_RecoveryBlocked($r, "original-backup-invalid")
    Local $manifest = _PBK_Hash($backup & "\SHA256SUMS.txt")
    If StringLen($manifest) <> 64 Then Return _PVB_RecoveryBlocked($r, "original-manifest-unreadable")
    Local $mismatch = ""
    If Not _PVR_DataMatches($root, $backup, True, $mismatch) Then _
            Return _PVB_RecoveryBlocked($r, "changed-user-data:" & $mismatch)

    ; Backup MUST describe the original complete stale registry, not a newly
    ; created empty registry or arbitrary copy of an unregistered VM folder.
    Local $original = _PVB_Plan($backup)
    If $original["status"] <> "REVIEW_ONLY" Then _
            Return _PVB_RecoveryBlocked($r, "backup-not-original-moved-root")
    Local $originalXml = _PVI_LoadXml($backup & "\data\.VirtualBox\VirtualBox.xml")
    Local $originalEntries = _PVI_RegistryEntries($originalXml)
    If Not IsObj($originalEntries) Or $originalEntries.length <> $original["count"] Then _
            Return _PVB_RecoveryBlocked($r, "original-registry-structure-changed")
    Local $expected[], $paths[], $order[0]
    For $i = 0 To $originalEntries.length - 1
        Local $entry = $originalEntries.item($i)
        Local $uuid = StringLower($entry.getAttribute("uuid")), $old = $entry.getAttribute("src")
        Local $where = _PVR_StaleSource($root, $old)
        Local $savedWhere = _PVR_StaleSource($backup, $old)
        If Not $where["ok"] Or Not $savedWhere["ok"] Or _
                StringLower($where["relative"]) <> StringLower($savedWhere["relative"]) Or _
                StringLower($where["old_root"]) <> StringLower($original["old_root"]) Then _
                Return _PVB_RecoveryBlocked($r, "original-root-or-relative-path-mismatch")
        If MapExists($expected, $uuid) Then Return _PVB_RecoveryBlocked($r, "duplicate-original-uuid")
        If _PVI_PathState($old) <> 0 Then Return _PVB_RecoveryBlocked($r, "old-vm-source-not-absent")
        Local $savedFile = _PVR_LocalMachine($backup, $where["relative"])
        Local $currentFile = _PVR_LocalMachine($root, $where["relative"])
        If $savedFile == "" Or $currentFile == "" Or _
                _PBK_Hash($savedFile) <> _PBK_Hash($currentFile) Then _
                Return _PVB_RecoveryBlocked($r, "machine-config-not-original")
        Local $record[]
        $record["uuid"] = $uuid
        $record["old"] = $old
        $record["new"] = $currentFile
        $expected[$uuid] = $record
        $paths[$uuid] = $currentFile
        ReDim $order[UBound($order) + 1]
        $order[UBound($order) - 1] = $uuid
    Next

    Local $registry = $root & "\data\.VirtualBox\VirtualBox.xml"
    Local $registryBefore = _PBK_Hash($registry)
    If StringLen($registryBefore) <> 64 Then Return _PVB_RecoveryBlocked($r, "current-registry-unreadable")
    Local $xml = _PVI_LoadXml($registry)
    Local $entries = _PVI_RegistryEntries($xml)
    If Not IsObj($entries) Or $entries.length > $original["count"] Then _
            Return _PVB_RecoveryBlocked($r, "current-registry-invalid-or-extra")
    Local $seen[], $states[]
    For $i = 0 To $entries.length - 1
        Local $entry = $entries.item($i)
        Local $uuid = StringLower($entry.getAttribute("uuid")), $source = $entry.getAttribute("src")
        If Not MapExists($expected, $uuid) Or MapExists($seen, $uuid) Then _
                Return _PVB_RecoveryBlocked($r, "foreign-or-duplicate-registration")
        Local $record = $expected[$uuid], $kind = ""
        If StringLower($source) == StringLower($record["old"]) Then
            $kind = "STALE"
        Else
            Local $target = _PVI_RegistryTarget($root, $source)
            If $target <> "" And StringLower($target) == StringLower($record["new"]) Then $kind = "LOCAL"
        EndIf
        If $kind == "" Then Return _PVB_RecoveryBlocked($r, "foreign-or-mismatched-registration-path")
        $seen[$uuid] = True
        $states[$uuid] = $kind
    Next
    ; A valid XML registry plus unchanged complete media inventory is required
    ; even when some of the original registrations were unregistered.
    Local $audit = _PVI_Inspect($root)
    If ($audit["status"] <> "REVIEW" And $audit["status"] <> "CLEAN") Or _
            $audit["vm_count"] <> $original["count"] Or _
            $audit["registered_count"] <> $entries.length Or _
            $audit["external_count"] <> 0 Or $audit["missing_count"] <> 0 Or _
            $audit["snapshot_count"] <> $original["snapshots"] Or _
            $audit["media_count"] <> $original["media"] Then _
            Return _PVB_RecoveryBlocked($r, "current-vm-inventory-does-not-match-backup")

    For $uuid In $order
        Local $record = $expected[$uuid], $state = "ABSENT"
        If MapExists($states, $uuid) Then $state = $states[$uuid]
        ; ABSENT is an observed state, not an omitted map key.
        ; A transition proof requires the same complete UUID set on both sides.
        $states[$uuid] = $state
        Switch $state
            Case "STALE"
                $r["stale"] += 1
            Case "ABSENT"
                $r["absent"] += 1
            Case "LOCAL"
                $r["local"] += 1
            Case Else
                Return _PVB_RecoveryBlocked($r, "invalid-reconciliation-state")
        EndSwitch
        If Not _PVB_RecoveryAppend($r, $uuid & "  " & $state & "  " & $record["new"]) Then _
                Return _PVB_RecoveryBlocked($r, "reconciliation-report-too-large")
        ; Resume missing registration before unregistering any new original.
        If $r["next_action"] == "" And $state == "ABSENT" Then
            $r["next_action"] = "REGISTER_HINT_ONLY"
            $r["next_uuid"] = $uuid
            $r["next_path"] = $record["new"]
        EndIf
    Next
    If $r["next_action"] == "" Then
        For $uuid In $order
            If $states[$uuid] == "STALE" Then
                Local $record = $expected[$uuid]
                $r["next_action"] = "UNREGISTER_HINT_ONLY"
                $r["next_uuid"] = $uuid
                $r["next_path"] = $record["new"]
                ExitLoop
            EndIf
        Next
    EndIf
    If _PBK_Hash($registry) <> $registryBefore Or _PBK_Hash($backup & "\SHA256SUMS.txt") <> $manifest Or _
            Not _PBK_Offline() Then Return _PVB_RecoveryBlocked($r, "state-changed-during-observation")
    $r["status"] = ($r["local"] == $original["count"] ? "COMPLETE" : "REVIEW_ONLY")
    $r["reason"] = "no-batch-mutation-authority"
    $r["count"] = $original["count"]
    $r["backup"] = $backup
    $r["root"] = $root
    $r["origin_sha256"] = $original["registry_sha256"]
    $r["states"] = $states
    $r["paths"] = $paths
    $r["order"] = $order
    $r["manifest_sha256"] = $manifest
    Return $r
EndFunc

; Validate the ENTIRE re-observed state model before examining a step.
; These fields are only offline evidence and NEVER sufficient authority for
; an Oracle write, protected helper action, or cleanup.
Func _PVB_StateConsistent($r)
    If Not IsMap($r) Then Return False
    Local $required = StringSplit("status|count|stale|absent|local|next_action|next_uuid|next_path|manifest_sha256|origin_sha256|root|backup|states|paths|order", "|", 2)
    For $key In $required
        If Not MapExists($r, $key) Then Return False
    Next
    If Not IsInt($r["count"]) Or $r["count"] < 2 Or $r["count"] > $g_PVB_MAX_CANDIDATES Then Return False
    If Not IsInt($r["stale"]) Or Not IsInt($r["absent"]) Or Not IsInt($r["local"]) Then Return False
    If Not IsString($r["manifest_sha256"]) Or Not StringRegExp($r["manifest_sha256"], "^[0-9a-f]{64}$") Then Return False
    If Not IsString($r["origin_sha256"]) Or Not StringRegExp($r["origin_sha256"], "^[0-9a-f]{64}$") Then Return False
    If Not IsString($r["root"]) Or Not IsString($r["backup"]) Or $r["root"] == "" Or $r["backup"] == "" Then Return False
    If Not IsString($r["next_action"]) Or Not IsString($r["next_uuid"]) Or Not IsString($r["next_path"]) Then Return False
    If $r["status"] <> "REVIEW_ONLY" And $r["status"] <> "COMPLETE" Then Return False
    Local $states = $r["states"], $paths = $r["paths"], $order = $r["order"]
    If Not IsMap($states) Or Not IsMap($paths) Or Not IsArray($order) Then Return False
    If UBound($order) <> $r["count"] Then Return False
    Local $stateKeys = MapKeys($states), $pathKeys = MapKeys($paths)
    If UBound($stateKeys) <> $r["count"] Or UBound($pathKeys) <> $r["count"] Then Return False
    Local $seen[], $countStale = 0, $countAbsent = 0, $countLocal = 0
    Local $firstAbsent = "", $firstStale = ""
    For $uuid In $order
        If Not IsString($uuid) Or Not StringRegExp($uuid, "^\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}$") Then Return False
        If MapExists($seen, $uuid) Or Not MapExists($states, $uuid) Or Not MapExists($paths, $uuid) Then Return False
        $seen[$uuid] = True
        If Not IsString($paths[$uuid]) Or $paths[$uuid] == "" Then Return False
        Switch $states[$uuid]
            Case "STALE"
                $countStale += 1
                If $firstStale == "" Then $firstStale = $uuid
            Case "ABSENT"
                $countAbsent += 1
                If $firstAbsent == "" Then $firstAbsent = $uuid
            Case "LOCAL"
                $countLocal += 1
            Case Else
                Return False
        EndSwitch
    Next
    If $countStale <> $r["stale"] Or $countAbsent <> $r["absent"] Or $countLocal <> $r["local"] Then Return False
    Local $expectedAction = "", $expectedUuid = "", $expectedPath = ""
    If $firstAbsent <> "" Then
        $expectedAction = "REGISTER_HINT_ONLY"
        $expectedUuid = $firstAbsent
    ElseIf $firstStale <> "" Then
        $expectedAction = "UNREGISTER_HINT_ONLY"
        $expectedUuid = $firstStale
    EndIf
    If $expectedUuid <> "" Then $expectedPath = $paths[$expectedUuid]
    If $r["next_action"] <> $expectedAction Or $r["next_uuid"] <> $expectedUuid Or _
            $r["next_path"] <> $expectedPath Then Return False
    If $r["status"] == "COMPLETE" Then Return $countLocal == $r["count"]
    Return $countLocal <> $r["count"]
EndFunc

; Pure model-level transition check for independently re-observed states.
; It is NOT runtime authority. Every future Oracle operation would need an
; owned controller, verified backup, exact child exit and postcondition scan.
Func _PVB_TransitionValid($before, $after, $action, $uuid)
    If Not IsString($uuid) Or Not _PVB_StateConsistent($before) Or Not _PVB_StateConsistent($after) Then Return False
    If $before["status"] <> "REVIEW_ONLY" Then Return False
    If $before["count"] < 2 Or $before["count"] > $g_PVB_MAX_CANDIDATES Or _
            $before["count"] <> $after["count"] Or _
            $before["manifest_sha256"] <> $after["manifest_sha256"] Or _
            $before["origin_sha256"] <> $after["origin_sha256"] Or _
            $before["root"] <> $after["root"] Or $before["backup"] <> $after["backup"] Then Return False
    Local $statesBefore = $before["states"], $statesAfter = $after["states"]
    Local $pathsBefore = $before["paths"], $pathsAfter = $after["paths"]
    Local $orderBefore = $before["order"], $orderAfter = $after["order"]
    For $i = 0 To $before["count"] - 1
        If $orderBefore[$i] <> $orderAfter[$i] Then Return False
    Next
    Local $keys = MapKeys($statesBefore)
    For $key In $keys
        If Not MapExists($pathsAfter, $key) Or $pathsBefore[$key] <> $pathsAfter[$key] Then Return False
    Next
    If Not MapExists($statesBefore, $uuid) Or Not MapExists($statesAfter, $uuid) Then Return False
    Local $from = "", $to = ""
    Switch $action
        Case "UNREGISTER"
            $from = "STALE"
            $to = "ABSENT"
        Case "REGISTER"
            $from = "ABSENT"
            $to = "LOCAL"
        Case Else
            Return False
    EndSwitch
    ; Never unregister a different VM while an interrupted registration
    ; remains ABSENT. The bound next UUID/action is deterministic and a hint,
    ; not an executable command or privilege grant.
    If $before["next_uuid"] <> $uuid Then Return False
    If $before["next_path"] <> $pathsBefore[$uuid] Then Return False
    If $action == "UNREGISTER" And $before["next_action"] <> "UNREGISTER_HINT_ONLY" Then Return False
    If $action == "REGISTER" And $before["next_action"] <> "REGISTER_HINT_ONLY" Then Return False
    If $statesBefore[$uuid] <> $from Or $statesAfter[$uuid] <> $to Then Return False
    For $key In $keys
        If Not MapExists($statesAfter, $key) Then Return False
        If $key <> $uuid And $statesBefore[$key] <> $statesAfter[$key] Then Return False
    Next
    Return True
EndFunc

; This accepts a bounded sequence of independently observed snapshots only.
; It does not create/modify receipts, execute Oracle, prove authenticated
; ownership or permit cleanup. Any missing intermediate observation refuses
; a complete trace instead of guessing which command may have succeeded.
Func _PVB_TraceValid($observations, $actions, $uuids, $requireComplete = False)
    If Not IsArray($observations) Or Not IsArray($actions) Or Not IsArray($uuids) Or _
            Not IsBool($requireComplete) Then Return False
    Local $steps = UBound($actions)
    If $steps <> UBound($uuids) Or UBound($observations) <> $steps + 1 Or _
            $steps > 2 * $g_PVB_MAX_CANDIDATES Then Return False
    If Not _PVB_StateConsistent($observations[0]) Then Return False
    Local $start = $observations[0]
    If $start["status"] <> "REVIEW_ONLY" Or $start["stale"] <> $start["count"] Or _
            $start["absent"] <> 0 Or $start["local"] <> 0 Then Return False
    For $i = 0 To $steps - 1
        If Not IsString($actions[$i]) Or Not IsString($uuids[$i]) Then Return False
        If Not _PVB_TransitionValid($observations[$i], $observations[$i + 1], _
                $actions[$i], $uuids[$i]) Then Return False
    Next
    Local $last = $observations[$steps]
    If Not _PVB_StateConsistent($last) Then Return False
    If $requireComplete Then Return $last["status"] == "COMPLETE" And $steps = 2 * $last["count"]
    Return True
EndFunc

Func _PVB_RecoveryText($r)
    If Not IsMap($r) Or Not MapExists($r, "status") Then Return ""
    Local $ru = _LI_Language() == "ru"
    Switch $r["status"]
        Case "REVIEW_ONLY", "COMPLETE"
            Local $label = "Partial multi-VM registration inspection ONLY: "
            If $ru Then $label = "Проверка частичного восстановления нескольких ВМ, ТОЛЬКО ЧТЕНИЕ: "
            Local $text = $label & $r["count"] & @CRLF & $r["report"] & _
                "STALE=" & $r["stale"] & " ABSENT=" & $r["absent"] & " LOCAL=" & $r["local"] & @CRLF
            If $r["status"] == "COMPLETE" Then
                If $ru Then Return $text & "Все регистрации локальны. Повторное изменение не требуется."
                Return $text & "All registrations local. No new changes required."
            EndIf
            If $ru Then Return $text & "Следующий возможный этап (НЕ КОМАНДА): " & $r["next_action"] & " " & $r["next_uuid"] & @CRLF & _
                "Нужны отдельная защищенная сессия и подтверждение. Изменения здесь не выполняются."
            Return $text & "Possible next stage (NOT A COMMAND): " & $r["next_action"] & " " & $r["next_uuid"] & @CRLF & _
                "A separate verified owned session and explicit consent are required. No changes are made here."
        Case Else
            If $ru Then Return "Восстановление регистраций нескольких ВМ заблокировано: " & $r["reason"] & @CRLF & "Никаких изменений."
            Return "Multiple-VM registration reconciliation blocked: " & $r["reason"] & @CRLF & "No changes were made."
    EndSwitch
EndFunc
