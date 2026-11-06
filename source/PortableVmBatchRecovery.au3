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
    Local $states[]
    $r["states"] = $states
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
    Local $expected[], $order[0]
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
    $r["manifest_sha256"] = $manifest
    Return $r
EndFunc

; Pure model-level transition check for independently re-observed states.
; It is NOT runtime authority. Every future Oracle operation would need an
; owned controller, verified backup, exact child exit and postcondition scan.
Func _PVB_TransitionValid($before, $after, $action, $uuid)
    If Not IsMap($before) Or Not IsMap($after) Or Not IsString($uuid) Then Return False
    Local $required = StringSplit("status|count|manifest_sha256|origin_sha256|root|backup|states", "|", 2)
    For $key In $required
        If Not MapExists($before, $key) Or Not MapExists($after, $key) Then Return False
    Next
    If $before["status"] <> "REVIEW_ONLY" Or _
            ($after["status"] <> "REVIEW_ONLY" And $after["status"] <> "COMPLETE") Then Return False
    If $before["count"] < 2 Or $before["count"] > $g_PVB_MAX_CANDIDATES Or _
            $before["count"] <> $after["count"] Or _
            $before["manifest_sha256"] <> $after["manifest_sha256"] Or _
            $before["origin_sha256"] <> $after["origin_sha256"] Or _
            $before["root"] <> $after["root"] Or $before["backup"] <> $after["backup"] Then Return False
    Local $statesBefore = $before["states"], $statesAfter = $after["states"]
    If Not IsMap($statesBefore) Or Not IsMap($statesAfter) Then Return False
    Local $keys = MapKeys($statesBefore)
    If UBound($keys) <> $before["count"] Then Return False
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
    If $statesBefore[$uuid] <> $from Or $statesAfter[$uuid] <> $to Then Return False
    For $key In $keys
        If Not MapExists($statesAfter, $key) Then Return False
        If $key <> $uuid And $statesBefore[$key] <> $statesAfter[$key] Then Return False
    Next
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
