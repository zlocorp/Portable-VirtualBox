#include-once
#include "PortableVmRebind.au3"

; Public, read-only discovery of several VMs relocated together.
; A separate explicit backup action calls the existing verified full data/
; copier. Neither action authorizes registration changes or cleanup.
; The sole mutation-capable rebind controller retains its single-VM proof gate.
Global Const $g_PVB_MAX_CANDIDATES = 16

Func _PVB_New()
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["reason"] = "unverified-batch"
    $r["count"] = 0
    $r["old_root"] = ""
    $r["snapshots"] = 0
    $r["media"] = 0
    $r["report"] = ""
    $r["registry_sha256"] = ""
    $r["backup"] = ""
    $r["backup_manifest_sha256"] = ""
    Return $r
EndFunc

Func _PVB_Fail($r, $reason)
    $r["status"] = "BLOCKED"
    $r["reason"] = $reason
    $r["report"] = ""
    $r["count"] = 0
    Return $r
EndFunc

; `REVIEW_ONLY` is deliberately different from the existing single-VM READY.
; It MUST NOT be passed to _PVR_ProofValid or a privileged action.
Func _PVB_Plan($root)
    Local $r = _PVB_New()
    If Not _PBK_Offline() Then Return _PVB_Fail($r, "host-not-offline")
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Then Return _PVB_Fail($r, "unsafe-root")
    Local $registry = $root & "\data\.VirtualBox\VirtualBox.xml"
    If _PVI_PathState($root & "\data") <> 2 Or _
            _PVI_PathState($root & "\data\Machines") <> 2 Or _
            _PVI_PathState($root & "\data\.VirtualBox") <> 2 Or _
            _PVI_PathState($registry) <> 1 Then Return _PVB_Fail($r, "missing-or-unsafe-profile")
    Local $xml = _PVI_LoadXml($registry)
    If Not IsObj($xml) Then Return _PVB_Fail($r, "invalid-registry-xml")
    Local $entries = _PVI_RegistryEntries($xml)
    If Not IsObj($entries) Then Return _PVB_Fail($r, "invalid-registry-structure")
    If $entries.length < 2 Then
        $r["status"] = "NONE"
        $r["reason"] = "use-single-vm-plan"
        Return $r
    EndIf
    If $entries.length > $g_PVB_MAX_CANDIDATES Then Return _PVB_Fail($r, "batch-exceeds-limit")
    Local $registryHash = _PBK_Hash($registry)
    If StringLen($registryHash) <> 64 Then Return _PVB_Fail($r, "unreadable-registry")
    ; Every local .vbox must be accounted for, all registration entries must
    ; be stale absolute paths, and no medium may be missing or outside data/.
    Local $audit = _PVI_Inspect($root)
    If $audit["status"] <> "REVIEW" Or $audit["vm_count"] <> $entries.length Or _
            $audit["registered_count"] <> $entries.length Or _
            $audit["external_registry_count"] <> $entries.length Or _
            $audit["external_count"] <> 0 Or $audit["missing_count"] <> 0 Then _
            Return _PVB_Fail($r, "ambiguous-or-incomplete-vm-inventory")
    Local $seen = "|", $sourceRoot = ""
    For $i = 0 To $entries.length - 1
        Local $entry = $entries.item($i)
        Local $uuid = StringLower($entry.getAttribute("uuid")), $source = $entry.getAttribute("src")
        If Not StringRegExp($uuid, "^\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}$") Then _
                Return _PVB_Fail($r, "invalid-machine-uuid")
        If StringInStr($seen, "|" & $uuid & "|", 1) > 0 Then Return _PVB_Fail($r, "duplicate-machine-uuid")
        $seen &= $uuid & "|"
        Local $candidate = _PVR_StaleSource($root, $source)
        If Not $candidate["ok"] Then Return _PVB_Fail($r, "nonportable-or-local-registration")
        If $sourceRoot == "" Then $sourceRoot = $candidate["old_root"]
        If StringLower($sourceRoot) <> StringLower($candidate["old_root"]) Then _
                Return _PVB_Fail($r, "different-prior-roots")
        ; An unknown/unsafe old path does not prove physical relocation.
        If _PVI_PathState($source) <> 0 Then Return _PVB_Fail($r, "old-source-exists-or-unknown")
        Local $newPath = _PVR_LocalMachine($root, $candidate["relative"])
        If $newPath == "" Then Return _PVB_Fail($r, "new-machine-missing-or-unsafe")
        Local $beforeHash = _PBK_Hash($newPath)
        If StringLen($beforeHash) <> 64 Then Return _PVB_Fail($r, "unreadable-new-config")
        Local $config = _PVI_LoadXml($newPath)
        If Not IsObj($config) Then Return _PVB_Fail($r, "invalid-new-machine-xml")
        Local $machine = _PVI_DirectMachine($config)
        If Not IsObj($machine) Then Return _PVB_Fail($r, "invalid-machine-structure")
        Local $name = $machine.getAttribute("name"), $actualUuid = StringLower($machine.getAttribute("uuid"))
        If Not IsString($name) Or StringLen($name) < 1 Or StringLen($name) > 180 Or _
                StringRegExp($name, "[\x00-\x1f]") Or $actualUuid <> $uuid Then _
                Return _PVB_Fail($r, "registered-machine-identity-mismatch")
        Local $folder = StringRegExpReplace($newPath, "\\[^\\]+$", "")
        If Not _PVR_AncillaryLocal($config, $folder) Then Return _PVB_Fail($r, "saved-or-external-ancillary-file")
        Local $snapshots = $config.selectNodes('//*[local-name()="Snapshot"]')
        Local $media = $config.selectNodes('//*[@location]')
        If Not IsObj($snapshots) Or Not IsObj($media) Or $snapshots.length > $g_PVI_MaxMedia Or _
                $media.length < 1 Or $media.length > $g_PVI_MaxMedia Then _
                Return _PVB_Fail($r, "unsupported-media-graph")
        For $j = 0 To $media.length - 1
            If _PVI_MediaLocation($folder, $media.item($j).getAttribute("location")) <> "LOCAL" Then _
                    Return _PVB_Fail($r, "external-or-missing-medium")
        Next
        If _PBK_Hash($newPath) <> $beforeHash Then Return _PVB_Fail($r, "machine-changed-during-audit")
        Local $line = "VM " & ($i + 1) & "/" & $entries.length & ": " & $name & " | UUID " & $uuid & @CRLF & _
                "  " & $source & @CRLF & "  -> " & $newPath & @CRLF & _
                "  .vbox SHA-256: " & $beforeHash & " | snapshots=" & $snapshots.length & " | media=" & $media.length
        ; The report is bounded and a user-facing diagnostic, never proof.
        If StringLen($line) > 1500 Or StringLen($r["report"]) + StringLen($line) > 26000 Then _
                Return _PVB_Fail($r, "report-too-large")
        $r["report"] &= $line & @CRLF
        $r["count"] += 1
        $r["snapshots"] += $snapshots.length
        $r["media"] += $media.length
    Next
    If _PBK_Hash($registry) <> $registryHash Then Return _PVB_Fail($r, "registry-changed-during-audit")
    If Not _PBK_Offline() Then Return _PVB_Fail($r, "host-state-changed")
    $r["old_root"] = $sourceRoot
    $r["registry_sha256"] = $registryHash
    $r["status"] = "REVIEW_ONLY"
    $r["reason"] = "no-batch-repair-authorization"
    Return $r
EndFunc

; Creates only an independent SHA-256 verified FULL data/ backup in a new
; directory. The returned BACKUP_ONLY status is not an authorization for
; unregister/register, even if all VM candidates and files match afterward.
Func _PVB_Backup($root, $dest)
    Local $before = _PVB_Plan($root)
    If $before["status"] <> "REVIEW_ONLY" Then Return $before
    If Not _PBK_ValidPath($root, $dest) Then Return _PVB_Fail($before, "invalid-or-existing-backup-destination")
    Local $result = _PBK_Create($root, $dest)
    If $result = 2 Then Return _PVB_Fail($before, "backup-blocked-or-busy")
    If $result <> 0 Or Not _PBK_Verify($dest) Then
        $before["status"] = "FAILED"
        $before["reason"] = "backup-incomplete-retain-staged-data"
        Return $before
    EndIf
    Local $after = _PVB_Plan($root)
    If $after["status"] <> "REVIEW_ONLY" Or $after["count"] <> $before["count"] Or _
            $after["old_root"] <> $before["old_root"] Or _
            $after["report"] <> $before["report"] Or _
            $after["registry_sha256"] <> $before["registry_sha256"] Or _
            $after["snapshots"] <> $before["snapshots"] Or $after["media"] <> $before["media"] Then
        ; Do not delete a completed backup or claim it proves this batch.
        $before["status"] = "FAILED"
        $before["reason"] = "source-changed-after-verified-backup"
        Return $before
    EndIf
    Local $manifestHash = _PBK_Hash($dest & "\SHA256SUMS.txt")
    If StringLen($manifestHash) <> 64 Or Not _PBK_Verify($dest) Then
        $before["status"] = "FAILED"
        $before["reason"] = "backup-verification-unknown-retain-files"
        Return $before
    EndIf
    $before["status"] = "BACKUP_ONLY"
    $before["reason"] = "no-batch-repair-authorization"
    $before["backup"] = $dest
    $before["backup_manifest_sha256"] = $manifestHash
    Return $before
EndFunc

Func _PVB_Text($r)
    If Not IsMap($r) Or Not MapExists($r, "status") Then Return ""
    Local $ru = _LI_Language() == "ru"
    Switch $r["status"]
        Case "BACKUP_ONLY"
            If $ru Then Return "Проверенная полная SHA-256 копия нескольких ВМ создана: " & $r["backup"] & @CRLF & _
                "Манифест SHA-256: " & $r["backup_manifest_sha256"] & @CRLF & $r["report"] & _
                "ВНИМАНИЕ: регистрация ВМ не изменена. Копия не разрешает массовое исправление или очистку."
            Return "Verified full multi-VM SHA-256 backup: " & $r["backup"] & @CRLF & _
                "SHA-256 manifest: " & $r["backup_manifest_sha256"] & @CRLF & $r["report"] & _
                "WARNING: no VM registration was repaired. This backup does not authorize batch repair or cleanup."
        Case "REVIEW_ONLY"
            If $ru Then Return "Предварительный план переноса нескольких ВМ (ТОЛЬКО ЧТЕНИЕ): " & $r["count"] & @CRLF & _
                "Исходная папка: " & $r["old_root"] & @CRLF & $r["report"] & _
                "ВНИМАНИЕ: регистрация ВМ не исправлена. Массовые изменения и очистка запрещены; нужна отдельная проверенная процедура с резервной копией."
            Return "Multiple moved VMs (READ-ONLY discovery): " & $r["count"] & @CRLF & _
                "Previous root: " & $r["old_root"] & @CRLF & $r["report"] & _
                "WARNING: no VM registration was repaired. Batch changes and cleanup remain disabled until an independently verified backup/transaction is implemented."
        Case "FAILED"
            If $ru Then Return "Резервная копия нескольких ВМ не подтверждена. Код: " & $r["reason"] & @CRLF & _
                "Не удаляйте существующую копию или папку .pending без проверки; исходные ВМ не менялись."
            Return "Multiple-VM backup is not verified: " & $r["reason"] & @CRLF & _
                "Keep existing backup or .pending for inspection. Original VM registration was not changed."
        Case "NONE"
            If $ru Then Return "Несколько перенесенных ВМ не обнаружены. Для одной машины используйте --plan-vm-rebind."
            Return "No multiple-VM relocation detected. Use --plan-vm-rebind for one machine."
        Case Else
            If $ru Then Return "Нельзя безопасно составить план переноса нескольких ВМ. Код: " & $r["reason"] & @CRLF & _
                "Регистрация и файлы ВМ не изменялись."
            Return "Multiple-VM relocation discovery blocked: " & $r["reason"] & @CRLF & _
                "VM registration and files were not changed."
    EndSwitch
EndFunc
