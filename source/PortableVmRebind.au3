#include-once
#include "PortableVmInventory.au3"
#include "PortableDataBackup.au3"

; User-facing, NON-MUTATING relocation plan for one exact stale VM registration.
; A plan or backup is NEVER authority to call VBoxManage, install VBoxSDS,
; rewrite VirtualBox.xml, change a snapshot, or delete a MachineEntry.
; Native Oracle registration changes require a separate approved live session.

Func _PVR_Trace($label)
    ; Diagnostic hints only. No tracing, path logging or performance work
    ; is performed in normal GUI or CLI mode.
    If EnvGet("PVBOX_CI_REBIND_TRACE") == "1" Then ConsoleWriteError("PVR_STAGE_" & $label & @CRLF)
EndFunc

Func _PVR_New($status = "BLOCKED", $reason = "unsafe-or-ambiguous")
    Local $r[]
    $r["status"] = $status
    $r["reason"] = $reason
    $r["uuid"] = ""
    $r["name"] = ""
    $r["old_root"] = ""
    $r["old_path"] = ""
    $r["new_path"] = ""
    $r["machine_sha256"] = ""
    $r["registry_sha256"] = ""
    $r["snapshots"] = 0
    $r["media"] = 0
    $r["backup"] = ""
    Return $r
EndFunc

; A candidate MUST have been registered under an earlier absolute portable
; root with precisely the same data\Machines relative layout. Accept neither
; arbitrary paths nor old media outside the portable root.
Func _PVR_StaleSource($root, $source)
    Local $candidate[]
    $candidate["ok"] = False
    $candidate["old_root"] = ""
    $candidate["relative"] = ""
    If Not IsString($root) Or Not IsString($source) Or StringLen($source) > 512 Then Return $candidate
    If StringInStr($source, "/") Or StringRegExp($source, '[\x00-\x1f"]') Then Return $candidate
    If Not StringRegExp($source, "^[A-Za-z]:\\") Then Return $candidate
    Local $marker = "\data\Machines\"
    Local $at = StringInStr($source, $marker, 0, 1)
    If $at < 5 Or StringInStr($source, $marker, 0, 2) > 0 Then Return $candidate
    Local $old = StringLeft($source, $at - 1)
    Local $relative = StringTrimLeft($source, $at + StringLen($marker) - 1)
    If Not _PP_RootSafe($old) Or Not _PortableSafeRelativePath($relative) Then Return $candidate
    If StringLower($old) == StringLower($root) Then Return $candidate
    If Not StringRegExp($relative, "(?i)\.vbox$") Or StringInStr($relative, "\") = 0 Then Return $candidate
    $candidate["ok"] = True
    $candidate["old_root"] = $old
    $candidate["relative"] = $relative
    Return $candidate
EndFunc

; Follow each local path component without accepting junctions or symbolic
; links. A missing or unreadable old path must not be mistaken for an absent
; new VM; the old source has to be proved ABSENT independently.
Func _PVR_LocalMachine($root, $relative)
    If Not _PP_RootSafe($root) Or Not _PortableSafeRelativePath($relative) Then Return ""
    Local $base = $root & "\data\Machines"
    If _PVI_PathState($base) <> 2 Then Return ""
    Local $parts = StringSplit($relative, "\", 2)
    For $i = 0 To UBound($parts) - 1
        $base &= "\" & $parts[$i]
        Local $state = _PVI_PathState($base)
        If $i < UBound($parts) - 1 Then
            If $state <> 2 Then Return ""
        Else
            If $state <> 1 Then Return ""
        EndIf
    Next
    Return $base
EndFunc

Func _PVR_Plan($root)
    _PVR_Trace("BEGIN")
    Local $r = _PVR_New()
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Then Return $r
    ; All candidate discovery must be read-only and offline. An existing
    ; VBoxSDS/VBoxSup or even UNKNOWN host state refuses a relocation plan.
    _PVR_Trace("ROOT")
    If Not _PBK_Offline() Then
        $r["reason"] = "host-not-offline"
        Return $r
    EndIf
    Local $registry = $root & "\data\.VirtualBox\VirtualBox.xml"
    If _PVI_PathState($root & "\data\Machines") <> 2 Or _
            _PVI_PathState($root & "\data\.VirtualBox") <> 2 Or _
            _PVI_PathState($registry) <> 1 Then
        $r["reason"] = "missing-or-unsafe-portable-profile"
        Return $r
    EndIf
    _PVR_Trace("OFFLINE")
    Local $xml = _PVI_LoadXml($registry)
    If Not IsObj($xml) Then Return $r
    Local $entries = $xml.selectNodes('//*[local-name()="MachineEntry"]')
    If Not IsObj($entries) Or $entries.length <> 1 Then
        $r["reason"] = "requires-exactly-one-registered-vm"
        Return $r
    EndIf
    Local $entry = $entries.item(0)
    Local $source = $entry.getAttribute("src"), $registeredUuid = $entry.getAttribute("uuid")
    If Not IsString($source) Or Not IsString($registeredUuid) Then Return $r
    If Not StringRegExp($registeredUuid, "(?i)^\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}$") Then Return $r
    If _PVI_RegistryTarget($root, $source) <> "" Then Return _PVR_New("NONE", "already-local")
    _PVR_Trace("REGISTRY")
    Local $candidate = _PVR_StaleSource($root, $source)
    If Not $candidate["ok"] Then
        $r["reason"] = "nonportable-or-ambiguous-registered-path"
        Return $r
    EndIf
    ; The source must genuinely be gone. If a second copy remains on the old
    ; disk, never make two live configurations point at the same UUID.
    If _PVI_PathState($source) <> 0 Then
        $r["reason"] = "old-machine-still-present-or-unreadable"
        Return $r
    EndIf
    Local $newPath = _PVR_LocalMachine($root, $candidate["relative"])
    If $newPath == "" Then
        $r["reason"] = "new-machine-missing-or-unsafe"
        Return $r
    EndIf
    _PVR_Trace("CANDIDATE")
    Local $config = _PVI_LoadXml($newPath)
    If Not IsObj($config) Then Return $r
    Local $machines = $config.selectNodes('//*[local-name()="Machine"]')
    If Not IsObj($machines) Or $machines.length <> 1 Then Return $r
    Local $machine = $machines.item(0)
    Local $name = $machine.getAttribute("name"), $uuid = $machine.getAttribute("uuid")
    If Not IsString($name) Or StringLen($name) < 1 Or StringLen($name) > 180 Or _
            StringRegExp($name, "[\x00-\x1f]") Or _
            Not IsString($uuid) Or StringLower($uuid) <> StringLower($registeredUuid) Then
        $r["reason"] = "registered-uuid-differs-from-machine"
        Return $r
    EndIf
    Local $snapshots = $config.selectNodes('//*[local-name()="Snapshot"]')
    Local $media = $config.selectNodes('//*[@location]')
    If Not IsObj($snapshots) Or Not IsObj($media) Or _
            $snapshots.length > $g_PVI_MaxMedia Or $media.length < 1 Or $media.length > $g_PVI_MaxMedia Then
        $r["reason"] = "unsupported-snapshot-or-media-graph"
        Return $r
    EndIf
    Local $machineFolder = StringRegExpReplace($newPath, "\\[^\\]+$", "")
    For $i = 0 To $media.length - 1
        If _PVI_MediaLocation($machineFolder, $media.item($i).getAttribute("location")) <> "LOCAL" Then
            $r["reason"] = "external-missing-or-unsafe-medium"
            Return $r
        EndIf
    Next
    ; Reject any other VM/registry entries, unregistered configs or additional
    ; external media. Only this ONE fully local saved machine can be proposed.
    _PVR_Trace("MEDIA")
    Local $audit = _PVI_Inspect($root)
    If $audit["status"] <> "REVIEW" Or $audit["vm_count"] <> 1 Or _
            $audit["registered_count"] <> 1 Or $audit["external_registry_count"] <> 1 Or _
            $audit["external_count"] <> 0 Or $audit["missing_count"] <> 0 Then
        $r["reason"] = "additional-registered-or-unregistered-vm"
        Return $r
    EndIf
    _PVR_Trace("AUDIT")
    Local $regHash = _PBK_Hash($registry), $vmHash = _PBK_Hash($newPath)
    _PVR_Trace("HASH")
    If StringLen($regHash) <> 64 Or StringLen($vmHash) <> 64 Then Return $r
    _PVR_Trace("READY")
    $r["status"] = "READY"
    $r["reason"] = "exact-moved-vm-no-changes-applied"
    $r["uuid"] = StringLower($uuid)
    $r["name"] = $name
    $r["old_root"] = $candidate["old_root"]
    $r["old_path"] = $source
    $r["new_path"] = $newPath
    $r["registry_sha256"] = $regHash
    $r["machine_sha256"] = $vmHash
    $r["snapshots"] = $snapshots.length
    $r["media"] = $media.length
    Return $r
EndFunc

; The only writable step: call the EXISTING full offline data/ backup with
; durable SHA-256 inventory, a new destination and no overwrite. Verify that
; the exact VM/registry still describe the same candidate after the backup.
; This function intentionally does not re-register or rewrite a VM.
Func _PVR_Backup($root, $dest)
    Local $before = _PVR_Plan($root)
    If $before["status"] <> "READY" Then Return $before
    If Not _PBK_ValidPath($root, $dest) Then
        $before["status"] = "BLOCKED"
        $before["reason"] = "invalid-or-existing-backup-destination"
        Return $before
    EndIf
    Local $result = _PBK_Create($root, $dest)
    If $result <> 0 Or Not _PBK_Verify($dest) Then
        $before["status"] = "FAILED"
        $before["reason"] = "backup-incomplete-retain-staged-data"
        Return $before
    EndIf
    Local $after = _PVR_Plan($root)
    If $after["status"] <> "READY" Or $after["uuid"] <> $before["uuid"] Or _
            $after["old_path"] <> $before["old_path"] Or _
            $after["new_path"] <> $before["new_path"] Or _
            $after["registry_sha256"] <> $before["registry_sha256"] Or _
            $after["machine_sha256"] <> $before["machine_sha256"] Then
        $before["status"] = "FAILED"
        $before["reason"] = "source-changed-after-verified-backup"
        Return $before
    EndIf
    $before["status"] = "BACKED_UP"
    $before["reason"] = "verified-copy-created-registration-not-modified"
    $before["backup"] = $dest
    Return $before
EndFunc

Func _PVR_Text($r)
    _PVR_Trace("TEXT")
    If Not IsMap($r) Or Not MapExists($r, "status") Then Return ""
    Local $ru = _LI_Language() == "ru"
    Switch $r["status"]
        Case "NONE"
            If $ru Then Return "Перенесенная регистрация ВМ не обнаружена. Изменения не нужны."
            Return "No relocated VM registration found. No changes required."
        Case "READY", "BACKED_UP"
            Local $out = ""
            If $ru Then
                $out = "Обнаружена одна перенесенная ВМ (план только для чтения): " & $r["name"] & @CRLF & _
                    "UUID: " & $r["uuid"] & @CRLF & _
                    "Снимки / носители: " & $r["snapshots"] & " / " & $r["media"] & @CRLF & _
                    "Старая регистрация: " & $r["old_path"] & @CRLF & "Новый файл: " & $r["new_path"] & @CRLF
            Else
                $out = "Exactly one relocated VM (read-only plan): " & $r["name"] & @CRLF & _
                    "UUID: " & $r["uuid"] & @CRLF & _
                    "Snapshots / media: " & $r["snapshots"] & " / " & $r["media"] & @CRLF & _
                    "Old registration: " & $r["old_path"] & @CRLF & "New file: " & $r["new_path"] & @CRLF
            EndIf
            If $r["status"] == "BACKED_UP" Then
                If $ru Then Return $out & "Резервная копия с SHA-256 подтверждена: " & $r["backup"] & @CRLF & "Регистрация не изменена."
                Return $out & "SHA-256 verified backup: " & $r["backup"] & @CRLF & "Registration was NOT changed."
            EndIf
            If $ru Then Return $out & "Перед исправлением нужна проверенная копия: --prepare-vm-rebind ПУТЬ_К_НОВОЙ_ПАПКЕ. Регистрация не изменена."
            Return $out & "First create a verified backup: --prepare-vm-rebind NEW_BACKUP_FOLDER. Registration was NOT changed."
        Case Else
            If $ru Then Return "Проверка переноса заблокирована: " & $r["reason"] & ". Никаких изменений регистрации."
            Return "Relocation check blocked: " & $r["reason"] & ". No registration changes."
    EndSwitch
EndFunc
