#include-once
#include "PortableVmInventory.au3"
#include "PortableDataBackup.au3"

; User-facing, NON-MUTATING relocation plan for one exact stale VM registration.
; A plan or backup is NEVER authority to call VBoxManage, install VBoxSDS,
; rewrite VirtualBox.xml, change a snapshot, or delete a MachineEntry.
; Native Oracle registration changes require a separate approved live session.

Func _PVR_New($status = "BLOCKED", $reason = "unsafe-or-ambiguous")
    Local $r[]
    $r["status"] = $status
    $r["reason"] = $reason
    $r["mode"] = ""
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
    $r["backup_registry_sha256"] = ""
    $r["backup_manifest_sha256"] = ""
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
    ; The later fixed register command uses _MS_Quote, whose path policy is
    ; _PP_RootSafe. Refuse an unquotable full path before any unregister.
    If Not _PP_RootSafe($base) Then Return ""
    Return $base
EndFunc

; A snapshot destination may not exist yet, but every existing component
; must be an ordinary in-machine directory. Absolute paths and parent escapes
; cannot be called portable, even when all currently attached disks are local.
Func _PVR_LocalFolder($base, $relative)
    If Not IsString($relative) Or StringInStr($relative, "%") Then Return False
    $relative = StringReplace($relative, "/", "\")
    If Not _PP_RootSafe($base) Or Not _PortableSafeRelativePath($relative) Then Return False
    Local $parts = StringSplit($relative, "\", 2)
    For $part In $parts
        $base &= "\" & $part
        If StringLen($base) > 245 Then Return False
        Local $state = _PVI_PathState($base)
        If $state <> 0 And $state <> 2 Then Return False
    Next
    Return True
EndFunc

; This rebind scope is powered-off machines and powered-off snapshots only.
; Saved memory is not covered by the location-only media inventory. Explicit
; NVRAM files must be present locally; the complete backup also binds bytes.
Func _PVR_AncillaryLocal($config, $folder)
    If Not IsObj($config) Then Return False
    Local $states = $config.selectNodes('//*[@stateFile]')
    Local $folders = $config.selectNodes('//*[@snapshotFolder]')
    Local $nvram = $config.selectNodes('//*[local-name()="NVRAM"][@path]')
    Local $path = ""
    If Not IsObj($states) Or Not IsObj($folders) Or Not IsObj($nvram) Then Return False
    For $i = 0 To $states.length - 1
        If $states.item($i).getAttribute("stateFile") <> "" Then Return False
    Next
    For $i = 0 To $folders.length - 1
        $path = $folders.item($i).getAttribute("snapshotFolder")
        If $path <> "" And Not _PVR_LocalFolder($folder, $path) Then Return False
    Next
    For $i = 0 To $nvram.length - 1
        $path = $nvram.item($i).getAttribute("path")
        If $path <> "" And _PVI_MediaLocation($folder, $path) <> "LOCAL" Then Return False
    Next
    Return True
EndFunc

Func _PVR_Plan($root)
    ; All candidate discovery must be read-only and offline. An existing
    ; VBoxSDS/VBoxSup or even UNKNOWN host state refuses a relocation plan.
    If Not _PBK_Offline() Then Return _PVR_New("BLOCKED", "host-not-offline")
    Return _PVR_ReadPlan($root)
EndFunc

; Oracle serializes one direct Global/MachineRegistry even when no machines
; remain. Missing, duplicate or misplaced containers/entries are corruption,
; not evidence that the exact unregister operation completed.
Func _PVR_RegistryEntries($xml)
    If Not IsObj($xml) Then Return 0
    Local $rootChildren = $xml.documentElement.selectNodes('*')
    Local $globals = $xml.selectNodes('/*[local-name()="VirtualBox"]/*[local-name()="Global"]')
    Local $allGlobals = $xml.selectNodes('//*[local-name()="Global"]')
    If Not IsObj($rootChildren) Or Not IsObj($globals) Or Not IsObj($allGlobals) Then Return 0
    If $rootChildren.length <> 1 Or $globals.length <> 1 Or $allGlobals.length <> 1 Then Return 0
    Local $registries = $globals.item(0).selectNodes('*[local-name()="MachineRegistry"]')
    Local $allRegistries = $xml.selectNodes('//*[local-name()="MachineRegistry"]')
    If Not IsObj($registries) Or Not IsObj($allRegistries) Then Return 0
    If $registries.length <> 1 Or $allRegistries.length <> 1 Then Return 0
    Local $entries = $registries.item(0).selectNodes('*[local-name()="MachineEntry"]')
    Local $allEntries = $xml.selectNodes('//*[local-name()="MachineEntry"]')
    Local $children = $registries.item(0).selectNodes('*')
    If Not IsObj($entries) Or Not IsObj($allEntries) Or Not IsObj($children) Then Return 0
    If $entries.length <> $allEntries.length Or $children.length <> $entries.length Then Return 0
    Return $entries
EndFunc

; Filesystem-only candidate inspection is shared with backup revalidation
; inside an already owned session. It never authorizes an Oracle operation.
Func _PVR_ReadPlan($root)
    Local $r = _PVR_New()
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Then Return $r
    Local $registry = $root & "\data\.VirtualBox\VirtualBox.xml"
    If _PVI_PathState($root & "\data") <> 2 Or _
            _PVI_PathState($root & "\data\Machines") <> 2 Or _
            _PVI_PathState($root & "\data\.VirtualBox") <> 2 Or _
            _PVI_PathState($registry) <> 1 Then
        $r["reason"] = "missing-or-unsafe-portable-profile"
        Return $r
    EndIf
    Local $xml = _PVI_LoadXml($registry)
    If Not IsObj($xml) Then Return $r
    Local $entries = _PVR_RegistryEntries($xml)
    If Not IsObj($entries) Or $entries.length <> 1 Then
        $r["reason"] = "requires-exactly-one-registered-vm"
        Return $r
    EndIf
    Local $entry = $entries.item(0)
    Local $source = $entry.getAttribute("src"), $registeredUuid = $entry.getAttribute("uuid")
    If Not IsString($source) Or Not IsString($registeredUuid) Then Return $r
    If Not StringRegExp($registeredUuid, "(?i)^\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}$") Then Return $r
    If _PVI_RegistryTarget($root, $source) <> "" Then Return _PVR_New("NONE", "already-local")
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
    If Not _PVR_AncillaryLocal($config, $machineFolder) Then
        $r["reason"] = "saved-state-or-unsafe-ancillary-path"
        Return $r
    EndIf
    For $i = 0 To $media.length - 1
        If _PVI_MediaLocation($machineFolder, $media.item($i).getAttribute("location")) <> "LOCAL" Then
            $r["reason"] = "external-missing-or-unsafe-medium"
            Return $r
        EndIf
    Next
    ; Reject any other VM/registry entries, unregistered configs or additional
    ; external media. Only this ONE fully local saved machine can be proposed.
    Local $audit = _PVI_Inspect($root)
    If $audit["status"] <> "REVIEW" Or $audit["vm_count"] <> 1 Or _
            $audit["registered_count"] <> 1 Or $audit["external_registry_count"] <> 1 Or _
            $audit["external_count"] <> 0 Or $audit["missing_count"] <> 0 Then
        $r["reason"] = "additional-registered-or-unregistered-vm"
        Return $r
    EndIf
    Local $regHash = _PBK_Hash($registry), $vmHash = _PBK_Hash($newPath)
    If StringLen($regHash) <> 64 Or StringLen($vmHash) <> 64 Then Return $r
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

; Oracle's UICommon.cpp and Windows svcmain.cpp create selectorwindow.log
; and VBoxSVC.log in VBOX_USER_HOME with ten rotations. Only these names
; and the global registry/previous registry are expected profile churn.
; No VM folder, arbitrary .log, launcher file or whole profile is exempted.
; Backup integrity always includes these files as well.
Func _PVR_ProfileChurn($relative)
    If Not IsString($relative) Then Return False
    Local $prefix = "data\.virtualbox\", $key = StringLower($relative)
    If StringLeft($key, StringLen($prefix)) <> $prefix Then Return False
    Local $name = StringTrimLeft($key, StringLen($prefix))
    Return $name == "virtualbox.xml" Or $name == "virtualbox.xml-prev" Or _
        StringRegExp($name, "^(vboxsvc|selectorwindow)\.log(?:\.([1-9]|10))?$") = 1
EndFunc

; An independently verified FULL backup is mandatory even when Oracle has
; already changed its registry/logs. Every other data file must have precisely
; the same relative path, size and SHA-256, including all VM metadata/media.
Func _PVR_DataMatches($root, $backup, $allowProfileChurn, ByRef $mismatch)
    $mismatch = "unsafe-path-or-overlapping-backup"
    If Not IsBool($allowProfileChurn) Then Return False
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Or _
            Not _PP_RootSafe($backup) Or Not _PP_ParentsSafe($backup) Or _
            _PBK_IsUnder($root, $backup) Or _PBK_IsUnder($backup, $root) Then Return False
    $mismatch = "backup-manifest-or-bytes-invalid"
    If Not _PBK_Verify($backup) Then Return False
    Local $before[], $after[], $countA = 0, $countB = 0, $equal = True
    _Crypt_Startup()
    If Not _PBK_Scan($root, "data", $before, $countA) Then
        $mismatch = "current-data-tree-unreadable"
        $equal = False
    ElseIf Not _PBK_Scan($backup, "data", $after, $countB) Then
        $mismatch = "backup-data-tree-unreadable"
        $equal = False
    Else
        Local $keys = MapKeys($before)
        For $key In $keys
            If $allowProfileChurn And _PVR_ProfileChurn($key) Then ContinueLoop
            If Not MapExists($after, $key) Or $before[$key] <> $after[$key] Then
                $mismatch = "current-file-differs:" & StringLeft($key, 180)
                $equal = False
                ExitLoop
            EndIf
        Next
        $keys = MapKeys($after)
        For $key In $keys
            If $allowProfileChurn And _PVR_ProfileChurn($key) Then ContinueLoop
            If Not MapExists($before, $key) Or $before[$key] <> $after[$key] Then
                $mismatch = "original-file-differs:" & StringLeft($key, 180)
                $equal = False
                ExitLoop
            EndIf
        Next
    EndIf
    _Crypt_Shutdown()
    If $equal Then $mismatch = ""
    Return $equal
EndFunc

; Preserve the original exact full-tree comparison for backup callers.
Func _PVR_BackupMatchesData($root, $backup)
    Local $mismatch = ""
    Return _PVR_DataMatches($root, $backup, False, $mismatch)
EndFunc

Func _PVR_ProofValid($proof)
    If Not IsMap($proof) Then Return False
    Local $fields = StringSplit("status|mode|uuid|name|old_root|old_path|new_path|backup|machine_sha256|registry_sha256|backup_registry_sha256|backup_manifest_sha256|snapshots|media", "|", 2)
    For $key In $fields
        If Not MapExists($proof, $key) Then Return False
    Next
    If Not IsString($proof["status"]) Or Not IsString($proof["mode"]) Then Return False
    If $proof["status"] <> "VERIFIED" Or _
            ($proof["mode"] <> "UNREGISTER_REGISTER" And $proof["mode"] <> "REGISTER_ONLY") Then Return False
    Local $paths = StringSplit("name|old_root|old_path|new_path|backup", "|", 2)
    For $key In $paths
        If Not IsString($proof[$key]) Or StringLen($proof[$key]) < 1 Or _
                StringLen($proof[$key]) > 512 Or StringRegExp($proof[$key], "[\x00-\x1f]") Then Return False
    Next
    If Not _PP_RootSafe($proof["new_path"]) Or Not _PP_RootSafe($proof["backup"]) Or _
            Not _PP_RootSafe($proof["old_root"]) Then Return False
    If Not IsString($proof["uuid"]) Or Not StringRegExp($proof["uuid"], "^\{[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\}$") Then Return False
    Local $hashes = StringSplit("machine_sha256|registry_sha256|backup_registry_sha256|backup_manifest_sha256", "|", 2)
    For $key In $hashes
        If Not IsString($proof[$key]) Or Not StringRegExp($proof[$key], "^[0-9a-f]{64}$") Then Return False
    Next
    Return IsInt($proof["snapshots"]) And $proof["snapshots"] >= 0 And $proof["snapshots"] <= $g_PVI_MaxMedia And _
        IsInt($proof["media"]) And $proof["media"] > 0 And $proof["media"] <= $g_PVI_MaxMedia
EndFunc

; Compare immutable evidence separately from the current Oracle registry,
; whose expected changes are checked by the explicit transition below.
Func _PVR_SameCandidate($before, $after)
    If Not IsMap($before) Or Not IsMap($after) Then Return False
    Local $fields = StringSplit("uuid|name|old_root|old_path|new_path|backup|machine_sha256|backup_registry_sha256|backup_manifest_sha256|snapshots|media", "|", 2)
    For $key In $fields
        If Not MapExists($before, $key) Or Not MapExists($after, $key) Then Return False
        If $before[$key] <> $after[$key] Then Return False
    Next
    Return True
EndFunc

; This binds the displayed confirmation to the proof re-read BEFORE UAC.
; Owned Prepare may subsequently rewrite Oracle's global profile properties.
Func _PVR_SameProof($confirmed, $fresh)
    If Not _PVR_ProofValid($confirmed) Or Not _PVR_ProofValid($fresh) Then Return False
    Return _PVR_SameCandidate($confirmed, $fresh) And $confirmed["mode"] == $fresh["mode"] And _
        $confirmed["registry_sha256"] == $fresh["registry_sha256"]
EndFunc

Func _PVR_Registration($root, $proof)
    Local $registry = _PVI_LoadXml($root & "\data\.VirtualBox\VirtualBox.xml")
    If Not IsObj($registry) Then Return "BLOCKED"
    Local $entries = _PVR_RegistryEntries($registry)
    If Not IsObj($entries) Then Return "BLOCKED"
    If $entries.length = 0 Then Return "ABSENT"
    If $entries.length <> 1 Then Return "BLOCKED"
    Local $entry = $entries.item(0)
    Local $uuid = $entry.getAttribute("uuid"), $source = $entry.getAttribute("src")
    If Not IsString($uuid) Or Not IsString($source) Then Return "BLOCKED"
    If StringLower($uuid) <> $proof["uuid"] Then Return "BLOCKED"
    If StringLower($source) == StringLower($proof["old_path"]) Then Return "STALE"
    Local $target = _PVI_RegistryTarget($root, $source)
    If $target <> "" And StringLower($target) == StringLower($proof["new_path"]) Then Return "LOCAL"
    Return "BLOCKED"
EndFunc

; The selected original backup is the durable recovery evidence. It MUST
; contain the original single stale registration. An arbitrary unregistered
; machine or a new backup of an empty registry cannot enter this route.
; This filesystem-only routine is also re-used under an owned live session.
Func _PVR_FromBackup($root, $backup)
    Local $mismatch = ""
    If Not _PVR_DataMatches($root, $backup, True, $mismatch) Then _
        Return _PVR_New("BLOCKED", "backup-missing-changed-or-does-not-match-current-data:" & $mismatch)
    Local $plan = _PVR_ReadPlan($backup)
    If $plan["status"] <> "READY" Then Return _PVR_New("BLOCKED", "backup-must-contain-original-stale-registration")
    Local $candidate = _PVR_StaleSource($root, $plan["old_path"])
    If Not $candidate["ok"] Then Return _PVR_New("BLOCKED", "backup-does-not-describe-this-relocation")
    Local $newPath = _PVR_LocalMachine($root, $candidate["relative"])
    If $newPath == "" Or _PBK_Hash($newPath) <> $plan["machine_sha256"] Then _
        Return _PVR_New("BLOCKED", "machine-metadata-differs-from-original-backup")
    $plan["new_path"] = $newPath
    $plan["backup"] = $backup
    $plan["backup_registry_sha256"] = $plan["registry_sha256"]
    $plan["backup_manifest_sha256"] = _PBK_Hash($backup & "\SHA256SUMS.txt")
    $plan["registry_sha256"] = _PBK_Hash($root & "\data\.VirtualBox\VirtualBox.xml")
    If StringLen($plan["backup_manifest_sha256"]) <> 64 Or StringLen($plan["registry_sha256"]) <> 64 Then _
        Return _PVR_New("BLOCKED", "unreadable-rebind-evidence")
    Local $registration = _PVR_Registration($root, $plan), $audit = _PVI_Inspect($root)
    If ($audit["status"] <> "REVIEW" And $audit["status"] <> "CLEAN") Or _
            $audit["vm_count"] <> 1 Or $audit["external_count"] <> 0 Or $audit["missing_count"] <> 0 Or _
            $audit["snapshot_count"] <> $plan["snapshots"] Or $audit["media_count"] <> $plan["media"] Then _
        Return _PVR_New("BLOCKED", "current-vm-graph-differs-from-original-backup")
    Switch $registration
        Case "STALE"
            If $audit["registered_count"] <> 1 Or $audit["external_registry_count"] <> 1 Then Return _PVR_New()
            $plan["mode"] = "UNREGISTER_REGISTER"
            $plan["reason"] = "original-backup-verified-repair-stale-registration"
        Case "ABSENT"
            If $audit["registered_count"] <> 0 Or $audit["external_registry_count"] <> 0 Then Return _PVR_New()
            $plan["mode"] = "REGISTER_ONLY"
            $plan["reason"] = "original-backup-verified-resume-missing-registration"
        Case "LOCAL"
            If $audit["status"] <> "CLEAN" Or $audit["registered_count"] <> 1 Or $audit["external_registry_count"] <> 0 Then Return _PVR_New()
            $plan["status"] = "NONE"
            $plan["reason"] = "already-local"
            Return $plan
        Case Else
            Return _PVR_New("BLOCKED", "current-registration-is-not-the-backed-up-machine")
    EndSwitch
    $plan["status"] = "VERIFIED"
    Return $plan
EndFunc

; A verified backup is not runtime authority. Public preparation stays offline;
; only the existing owned Manager session may use its separately confirmed proof.
Func _PVR_VerifyBackup($root, $backup)
    If Not _PBK_Offline() Then Return _PVR_New("BLOCKED", "host-not-offline")
    Local $plan = _PVR_FromBackup($root, $backup)
    If Not _PBK_Offline() Then Return _PVR_New("BLOCKED", "host-not-offline")
    Return $plan
EndFunc

; Re-read immutable evidence and the same exact registration mode after
; owned Prepare. That phase may configure machinefolder and rewrite the
; global registry; the stricter raw hash was already bound before UAC.
Func _PVR_StillExact($root, $proof)
    If Not _PVR_ProofValid($proof) Then Return False
    Local $fresh = _PVR_FromBackup($root, $proof["backup"])
    If Not _PVR_ProofValid($fresh) Then
        ConsoleWrite("VM rebind proof changed: " & $fresh["reason"] & @CRLF)
        Return False
    EndIf
    Return $proof["mode"] == $fresh["mode"] And _PVR_SameCandidate($proof, $fresh)
EndFunc

; Only the exact missing registration is eligible for the second command.
; Oracle may have changed its profile, but every VM file and the original
; backup/manifest must still match the evidence the user confirmed.
Func _PVR_CanRegister($root, $proof)
    If Not _PVR_ProofValid($proof) Then Return False
    Local $fresh = _PVR_FromBackup($root, $proof["backup"])
    If Not _PVR_ProofValid($fresh) Then
        ConsoleWrite("VM rebind registration blocked: " & $fresh["reason"] & @CRLF)
        Return False
    EndIf
    Return $fresh["mode"] == "REGISTER_ONLY" And _PVR_SameCandidate($proof, $fresh)
EndFunc

; Success requires the original VM metadata (including snapshot UUIDs and
; attachment graph) AND every base/differencing disk's SHA-256 bytes, not just
; equal counts. No speculative XML rewrite or second mutation is performed.
Func _PVR_Rebound($root, $proof)
    If Not _PVR_ProofValid($proof) Then Return False
    Local $fresh = _PVR_FromBackup($root, $proof["backup"])
    Local $complete = $fresh["status"] == "NONE" And $fresh["reason"] == "already-local" And _
        _PVR_SameCandidate($proof, $fresh)
    If Not $complete Then ConsoleWrite("VM rebind completion unverified: " & $fresh["reason"] & @CRLF)
    Return $complete
EndFunc

Func _PVR_Text($r)
    If Not IsMap($r) Or Not MapExists($r, "status") Then Return ""
    Local $ru = _LI_Language() == "ru"
    Switch $r["status"]
        Case "NONE"
            If $ru Then Return "Перенесенная регистрация ВМ не обнаружена. Изменения не нужны."
            Return "No relocated VM registration found. No changes required."
        Case "READY", "BACKED_UP", "VERIFIED"
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
            If $r["status"] == "VERIFIED" Then
                If Not _PVR_ProofValid($r) Then Return ""
                If $ru Then
                    $out &= "Проверена полная SHA-256 копия: " & $r["backup"] & @CRLF & "Режим: " & $r["mode"] & @CRLF
                    If $r["mode"] == "REGISTER_ONLY" Then _
                        $out &= "Исходная регистрация отсутствует. Будет повторена только регистрация исходного файла ВМ; снятие регистрации не повторяется." & @CRLF
                    Return $out & "Только выключенные ВМ и снимки без сохранённой памяти. Требуется отдельное подтверждение внутри изолированной сессии."
                EndIf
                $out &= "Full matching SHA-256 backup verified: " & $r["backup"] & @CRLF & "Mode: " & $r["mode"] & @CRLF
                If $r["mode"] == "REGISTER_ONLY" Then _
                    $out &= "The original registration is absent. Only registration of the original VM file will be retried; unregister will not be repeated." & @CRLF
                Return $out & "Powered-off VMs and snapshots without saved memory only. Registration changes require explicit consent inside an isolated session."
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
