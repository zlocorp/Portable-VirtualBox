#include-once
#include "ManagedProcess.au3"
#include "CliSessionGate.au3"
#include "PortableApp.au3"
#include "PortableCIVM.au3"
#include "PrivilegeBoundary.au3"
#include "PortableVmRebind.au3"
#include "OracleLanguage.au3"
; Adapted Manager/VM lifecycle flow from ThatAdminGuy a035d06b12 and
; skyshay001 upstream PR #90 (CC BY-NC-SA 3.0; original notices in LICENSE.md).
; Replace shell/name waits with retained process handles and asynchronous UI.
; System effects STILL use reviewed disposable-host research scripts. This
; controller is wired only to a separate non-distributed experiment EXE,
; not the ordinary diagnostic entrypoint. No production UAC claim.
Global $g_MS_Cycle = 0
Global $g_MS_Separated = False

Func _MS_Decide($manager, $seen, $total, $guests, $owned)
    If Not IsBool($owned) Or Not $owned Or Not IsBool($seen) Then Return "BLOCKED"
    If Not IsInt($total) Or Not IsInt($guests) Or $total < 0 Or $guests < 0 Or $guests > $total Then Return "BLOCKED"
    If $manager == "PRESENT" Then
        If $total < 1 Then Return "BLOCKED"
        Return "MANAGER_OPEN"
    EndIf
    If $manager <> "EXITED" Or Not $seen Then Return "BLOCKED"
    If $guests > 0 Then Return "WAIT_GUESTS"
    If $total > 0 Then Return "WAIT_BACKGROUND"
    Return "READY_TO_CLEAN"
EndFunc

; A completed cleanup receipt is not sufficient to reopen Manager: Oracle
; can briefly reappear while COM/Qt background teardown finishes. Require a
; stable, known empty host before releasing the session lock. Never attempt
; driver cleanup a second time or hide a truly foreign process.
Func _MS_HostClean($installed, $services, $processes)
    Return IsBool($installed) And Not $installed And IsInt($services) And IsInt($processes) And _
        $services = 0 And $processes = 0
EndFunc

; An explicit retry may re-run preflight after a transient observation; this
; does not override the preflight, lock, path or service ownership checks.
Func _MS_RetryAllowed($state, $detail)
    If Not IsString($state) Or Not IsString($detail) Then Return False
    Return $state == "IDLE" Or $state == "CLEAN" Or _
        ($state == "BLOCKED" And $detail == "existing-or-unknown-VirtualBox")
EndFunc

; Oracle's Manager persists geometry on a deferred timer. Closing immediately
; after first visibility can race that timer with COM teardown (observed in
; the real 7.2.22 GUI). Wait for an enabled, stable window, without sleeping
; the frontend or dismissing Oracle errors. This is not runtime authorization.
Func _MS_WindowReady($stable, $elapsedMs)
    If Not IsBool($stable) Or Not IsNumber($elapsedMs) Then Return False
    Return $stable And $elapsedMs >= 750
EndFunc

Func _MS_ObserveWindow(ByRef $s, ByRef $manager)
    Local $hwnd = _MP_Window($manager), $key = ""
    If $hwnd <> 0 And BitAND(WinGetState($hwnd), 4) Then
        Local $position = WinGetPos($hwnd)
        If Not @error And IsArray($position) Then _
            $key = String($hwnd) & ":" & $position[0] & ":" & $position[1] & ":" & $position[2] & ":" & $position[3]
    EndIf
    If $key == "" Or $key <> $s["window_key"] Then
        $s["window_key"] = $key
        $s["window_clock"] = TimerInit()
        Return False
    EndIf
    Return _MS_WindowReady(True, TimerDiff($s["window_clock"]))
EndFunc

Func _MS_New($root, $workspace)
    Local $s[]
    $s["root"] = $root
    $s["workspace"] = $workspace
    $s["state"] = "IDLE"
    $s["detail"] = ""
    $s["session"] = ""
    $s["separated"] = $g_MS_Separated
    $s["cycle"] = 0
    $s["former_pid"] = 0
    $s["app_system"] = $root & "\app64"
    $s["worker"] = _MP_New()
    $s["manager"] = _MP_New()
    $s["mutex"] = 0
    $s["cli_gate"] = _CG_New()
    $s["seen"] = False
    $s["owned"] = False
    $s["stopping"] = False
    $s["close_posted"] = False
    $s["window_key"] = ""
    $s["window_clock"] = TimerInit()
    $s["clock"] = TimerInit()
    $s["quiet"] = 0
    $s["guests"] = 0
    $s["uncertain"] = 0
    $s["worker_uncertain"] = 0
    $s["rebind"] = _PVR_New("NONE", "not-requested")
    $s["oracle_language"] = ""
    Return $s
EndFunc

Func _MS_State(ByRef $s, $state, $detail = "")
    Local $gate = $s["cli_gate"]
    If $gate["handle"] <> 0 Then
        Local $ready = $s["owned"] And _CG_StateAllows($state)
        Local $ok = _CG_SetReady($gate, $ready)
        If $ready And $ok Then $ok = _CG_Release($gate)
        If Not $ok Then
            _CG_SetReady($gate, False)
            $state = "FAILED"
            $detail = "portable-cli-gate-unverified-resources-retained"
        EndIf
        If $ok And ($state == "CLEAN" Or $state == "IDLE") Then _CG_Close($gate)
        $s["cli_gate"] = $gate
    EndIf
    If $s["state"] <> $state Or $s["detail"] <> $detail Then
        ConsoleWrite("Manager session: " & $state & " " & $detail & @CRLF)
        $s["clock"] = TimerInit()
    EndIf
    $s["state"] = $state
    $s["detail"] = $detail
EndFunc

Func _MS_AlphaPolicy($explicit, $arch, $status, $major, $build, $product)
    If Not IsBool($explicit) Or Not $explicit Then Return False
    If Not IsString($arch) Or StringUpper($arch) <> "X64" Then Return False
    If Not IsString($status) Or $status <> "PRESENT" Then Return False
    Return _WinObsWorkstationAccepted($build, $product, $major)
EndFunc

; An ALPHA helper cannot be invoked by a mere environment variable, and the
; ordinary double-click preview retains its disabled system-operation controls.
; This policy only enables an explicit opt-in on a real workstation when the
; paired candidate helper is present. The elevated helper independently
; validates its own host, exact frontend hash/user and Oracle driver inventory.
Func _MS_AlphaAllowed($root)
    If Not _PP_RootSafe($root) Or Not _PP_ParentsSafe($root) Then Return False
    If StringLower(@ScriptFullPath) <> StringLower($root & "\Portable-VirtualBox.exe") Then Return False
    If _PA_FileState($root, "Portable-VirtualBox-Helper-Alpha.exe") <> 1 Then Return False
    If Not _PB_Medium() Then Return False
    Local $os = _WinObsOS()
    Return _MS_AlphaPolicy($g_MS_AlphaMode, @OSArch, $os["status"], $os["major"], $os["build"], $os["product_type"])
EndFunc

Func _MS_Allowed($root, $workspace)
    If $g_MS_AlphaMode Then Return _MS_AlphaAllowed($root)
    If Not _PVS_Allowed(EnvGet("GITHUB_ACTIONS"), EnvGet("RUNNER_ENVIRONMENT"), EnvGet("RUNNER_OS"), _
            EnvGet("GITHUB_REPOSITORY"), $root, EnvGet("RUNNER_TEMP")) Then Return False
    If Not _PP_RootSafe($workspace) Or Not _PP_ParentsSafe($workspace) Then Return False
    Return _PP_ParentsSafe($root)
EndFunc

Func _MS_Quote($value)
    If Not _PP_RootSafe($value) Then Return ""
    Return '"' & $value & '"'
EndFunc

; Consent waits are not bounded helper operations: ShellExecuteExW may wait
; indefinitely for a HUMAN decision on Windows' secure desktop. The medium
; request worker remains tracked; never mark it failed on a wall-clock timeout
; because approval could arrive after that and mutate services asynchronously.
Func _MS_ConsentPending($state)
    Return IsString($state) And ($state == "CONSENT_PREPARE" Or $state == "CONSENT_FINISH" Or $state == "CONSENT_RECOVER")
EndFunc

Func _MS_ConsentPhase($separated, $action)
    If Not IsBool($separated) Then Return "BLOCKED"
    Switch $action
        Case "Prepare"
            If $separated Then Return "CONSENT_PREPARE"
            Return "PREPARING"
        Case "Finish"
            If $separated Then Return "CONSENT_FINISH"
            Return "CLEANING"
        Case "Recover"
            If $separated Then Return "CONSENT_RECOVER"
            Return "BLOCKED"
        Case Else
            Return "BLOCKED"
    EndSwitch
EndFunc

Func _MS_WorkerUnknownWait($elapsedMs)
    Return IsNumber($elapsedMs) And $elapsedMs >= 0 And $elapsedMs < 5000
EndFunc

Func _MS_Worker(ByRef $s, $action)
    If $action <> "Prepare" And $action <> "Finish" And $action <> "Recover" Then Return False
    $s["worker_uncertain"] = 0
    If $s["separated"] Then
        Local $privileged = _MP_New()
        If $action == "Recover" Then
            $privileged = _PB_StartRecover($s["root"], $s["former_pid"], $s["cycle"])
        Else
            $privileged = _PB_Start($s["root"], $action, $s["cycle"])
        EndIf
        $s["worker"] = $privileged
        Return $privileged["status"] == "STARTED"
    EndIf
    Local $exe = @ProgramFilesDir & "\PowerShell\7\pwsh.exe"
    Local $script = $s["workspace"] & "\scripts\manager_session_worker.ps1"
    If Not FileExists($exe) Or Not FileExists($script) Then Return False
    Local $args = "-NoLogo -NoProfile -NonInteractive -File " & _MS_Quote($script) & _
        " -Action " & $action & " -PortableRoot " & _MS_Quote($s["root"]) & " -SessionDir " & _MS_Quote($s["session"])
    Local $p = _MP_Start($exe, $args, $s["workspace"])
    $s["worker"] = $p
    Return $p["status"] == "STARTED"
EndFunc

; Read-only candidate discovery is a convenience to propose ONE old protected
; session. It is NEVER cleanup authority: the helper revalidates the exact
; protected original receipt, SID, driver and service identities. Multiple
; candidates, live owner, unreadable directory or reparse paths always block.
Func _MS_FindRecoverable($root)
    Local $out[]
    $out["status"] = "NONE"
    $out["old_pid"] = 0
    $out["cycle"] = 0
    Local $store = _PB_Store()
    If $store == "" Then
        $out["status"] = "UNKNOWN"
        Return $out
    EndIf
    If Not FileExists($store) Then Return $out
    If _PP_DirectoryState($store) <> 1 Then
        $out["status"] = "UNKNOWN"
        Return $out
    EndIf
    Local $h = FileFindFirstFile($store & "\pvbox-manager-*")
    If $h = -1 Then Return $out
    While 1
        Local $name = FileFindNextFile($h)
        If @error Then ExitLoop
        If Not StringRegExp($name, "^pvbox-manager-[1-9][0-9]{0,8}-[1-9][0-9]{0,2}$") Then ContinueLoop
        Local $folder = $store & "\" & $name
        If _PP_DirectoryState($folder) <> 1 Then
            $out["status"] = "UNKNOWN"
            ExitLoop
        EndIf
        ; An interrupted preparation has protected intent but no final
        ; session.json. Discovery proposes it; only the elevated helper can
        ; authenticate the exact old generation and stage checkpoints.
        If Not FileExists($folder & "\controller.json") Then ContinueLoop
        If Not FileExists($folder & "\session.json") And Not FileExists($folder & "\prepare-intent.json") Then ContinueLoop
        If FileExists($folder & "\payload-removed.json") Then ContinueLoop
        Local $parts = StringRegExp($name, "^pvbox-manager-([1-9][0-9]{0,8})-([1-9][0-9]{0,2})$", 1)
        If Not IsArray($parts) Then
            $out["status"] = "UNKNOWN"
            ExitLoop
        EndIf
        Local $former = Int($parts[0]), $cycle = Int($parts[1])
        If $former == @AutoItPID Or ProcessExists($former) Then ContinueLoop
        If $out["status"] == "FOUND" Then
            $out["status"] = "AMBIGUOUS"
            ExitLoop
        EndIf
        $out["status"] = "FOUND"
        $out["old_pid"] = $former
        $out["cycle"] = $cycle
    WEnd
    FileClose($h)
    Return $out
EndFunc

; Explicit, CI-only orphan cleanup with a fresh non-admin controller.
Func _MS_Recover(ByRef $s)
    If ($s["state"] <> "IDLE" And $s["state"] <> "BLOCKED") Or Not $s["separated"] Or Not _MS_Allowed($s["root"], $s["workspace"]) Or Not _PB_Medium() Then Return False
    Local $choice = _MS_FindRecoverable($s["root"])
    If $choice["status"] <> "FOUND" Then
        _MS_State($s, "BLOCKED", "recovery-candidate-" & $choice["status"])
        Return False
    EndIf
    Local $installed = _PortableInstalledVBoxDetected(), $activity = _PortableCountVirtualBoxProcesses()
    If Not IsBool($installed) Or $installed Or $activity <> 0 Then
        _MS_State($s, "BLOCKED", "recovery-foreign-or-active-processes")
        Return False
    EndIf
    Local $a = DllCall($g_WinObsKernel32, "handle", "CreateMutexW", "ptr", 0, "bool", True, "wstr", "Global\PortableVirtualBox.ManagerExperiment")
    Local $dllerror = @error
    Local $lockerror = _WinObsLastError()
    Local $h = 0
    If IsArray($a) Then $h = $a[0]
    If $dllerror Or $h = 0 Then
        If $h <> 0 Then DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $h)
        _MS_State($s, "BLOCKED", "recovery-lock-failed")
        Return False
    EndIf
    If $lockerror <> 0 Then
        DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $h)
        _MS_State($s, "BLOCKED", "another-session-or-unknown-lock")
        Return False
    EndIf
    $s["mutex"] = $h
    $s["former_pid"] = $choice["old_pid"]
    $s["cycle"] = $choice["cycle"]
    $s["session"] = _PB_Store() & "\pvbox-manager-" & $s["former_pid"] & "-" & $s["cycle"]
    $s["app_system"] = $s["session"] & "\app64"
    If Not _MS_Worker($s, "Recover") Then
        _MS_State($s, "FAILED", "recovery-worker-not-started")
        Return False
    EndIf
    _MS_State($s, "CONSENT_RECOVER")
    Return True
EndFunc

Func _MS_Start(ByRef $s, $backup = "", $confirmedProof = 0)
    If Not _MS_RetryAllowed($s["state"], $s["detail"]) Or $s["mutex"] <> 0 Then Return False
    ; Never create an elevation request without the confirmed original full
    ; backup and unchanged VM/launcher data. Only named Oracle profile churn
    ; may differ during an interrupted repair. Standard Start is unchanged.
    $s["rebind"] = _PVR_New("NONE", "not-requested")
    If $backup <> "" Then
        Local $proof = _PVR_VerifyBackup($s["root"], $backup)
        If $proof["status"] <> "VERIFIED" Then
            _MS_State($s, "BLOCKED", "rebind-" & $proof["reason"])
            Return False
        EndIf
        If Not _PVR_SameProof($confirmedProof, $proof) Then
            _MS_State($s, "BLOCKED", "rebind-confirmed-proof-changed")
            Return False
        EndIf
        $s["rebind"] = $proof
    EndIf
    If Not _MS_Allowed($s["root"], $s["workspace"]) Then
        _MS_State($s, "BLOCKED", "disposable-host-only")
        Return False
    EndIf
    If ($s["separated"] And Not _PB_Medium()) Or ($g_MS_AlphaMode And Not $s["separated"]) Then
        _MS_State($s, "BLOCKED", "frontend-must-be-non-administrator")
        Return False
    EndIf
    Local $app = _PA_Inspect($s["root"])
    If $app["status"] <> "PRESENT" Then
        _MS_State($s, "BLOCKED", "incomplete-app64")
        Return False
    EndIf
    $s["oracle_language"] = _OL_Saved(_LS_Load($s["root"]))
    Local $installed = _PortableInstalledVBoxDetected(True)
    If $s["separated"] Then
        Local $abandoned = _MS_FindRecoverable($s["root"])
        If $abandoned["status"] <> "NONE" Then
            _MS_State($s, "BLOCKED", "inspect-previous-protected-session-" & $abandoned["status"])
            Return False
        EndIf
    EndIf
    If Not IsBool($installed) Or $installed Or _PortableCountExistingServices(True) <> 0 Or _PortableCountVirtualBoxProcesses(True) <> 0 Then
        _MS_State($s, "BLOCKED", "existing-or-unknown-VirtualBox")
        Return False
    EndIf
    ; Cross-root exclusion before system changes. Existence is a refusal, not
    ; an invitation to acquire a mutex/resources left by another process.
    Local $a = DllCall($g_WinObsKernel32, "handle", "CreateMutexW", "ptr", 0, "bool", True, "wstr", "Global\PortableVirtualBox.ManagerExperiment")
    Local $dllerror = @error
    Local $lockerror = _WinObsLastError()
    Local $h = 0
    If IsArray($a) Then $h = $a[0]
    If $dllerror Or Not IsArray($a) Then
        If $h <> 0 Then DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $h)
        _MS_State($s, "BLOCKED", "session-lock-create-failed-dll")
        Return False
    EndIf
    If $h = 0 Then
        _MS_State($s, "BLOCKED", "session-lock-create-failed-win32-" & $lockerror)
        Return False
    EndIf
    If $lockerror <> 0 Then
        DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $h)
        If $lockerror = 183 Then
            _MS_State($s, "BLOCKED", "another-session")
        Else
            _MS_State($s, "BLOCKED", "session-lock-result-unknown-" & $lockerror)
        EndIf
        Return False
    EndIf
    $s["mutex"] = $h
    Local $profile = _PP_Ensure($s["root"])
    If $profile["status"] <> "READY" Then
        _MS_State($s, "FAILED", "profile-not-ready")
        Return False
    EndIf
    $g_MS_Cycle += 1
    $s["cycle"] = $g_MS_Cycle
    $s["session"] = EnvGet("RUNNER_TEMP") & "\pvbox-manager-" & @AutoItPID & "-" & $g_MS_Cycle
    If $s["separated"] Then
        $s["session"] = _PB_Store() & "\pvbox-manager-" & @AutoItPID & "-" & $s["cycle"]
        $s["app_system"] = $s["session"] & "\app64"
        Local $gate = _CG_Create(@AutoItPID, $s["cycle"])
        $s["cli_gate"] = $gate
        If $gate["handle"] = 0 Then
            _MS_State($s, "FAILED", "portable-cli-gate-collision-or-error")
            Return False
        EndIf
    EndIf
    $s["seen"] = False
    $s["owned"] = False
    $s["stopping"] = False
    $s["close_posted"] = False
    $s["window_key"] = ""
    $s["window_clock"] = TimerInit()
    $s["quiet"] = 0
    If FileExists($s["session"]) Or Not _MS_Worker($s, "Prepare") Then
        _MS_State($s, "FAILED", "prepare-worker-not-started")
        Return False
    EndIf
    _MS_State($s, _MS_ConsentPhase($s["separated"], "Prepare"))
    Return True
EndFunc

Func _MS_RebindStep(ByRef $s, $action)
    Local $proof = $s["rebind"]
    Local $active = $s["worker"]
    If Not _PVR_ProofValid($proof) Then Return False
    If Not $s["owned"] Or $active["handle"] <> 0 Then Return False
    Local $profile = _PP_Inspect($s["root"])
    If $profile["status"] <> "READY" Then Return False
    Local $args = ""
    Switch $action
        Case "unregister"
            ; The helper has prepared ONLY our pinned driver. Oracle below
            ; runs with the same ordinary token as the portable user profile.
            If $proof["mode"] <> "UNREGISTER_REGISTER" Or Not _PVR_StillExact($s["root"], $proof) Then Return False
            $args = "unregistervm " & $proof["uuid"] ; NO --delete
        Case "register"
            ; A continuation follows the exact successful unregister child;
            ; a resume has separately confirmed the original backup proof.
            ; Both require zero registrations and unchanged VM/backup bytes.
            If Not _PVR_CanRegister($s["root"], $proof) Then Return False
            $args = "registervm " & _MS_Quote($proof["new_path"])
        Case Else
            Return False
    EndSwitch
    Local $worker = _MP_Start($s["app_system"] & "\VBoxManage.exe", $args, _
        $s["app_system"], $profile["profile"])
    $s["worker"] = $worker
    $s["worker_uncertain"] = 0
    If $worker["status"] <> "STARTED" Then Return False
    If $action == "unregister" Then
        _MS_State($s, "REBIND_UNREGISTER", "exact-uuid-verified-backup-no-delete")
    Else
        _MS_State($s, "REBIND_REGISTER", "local-vbox-file-same-uuid")
    EndIf
    Return True
EndFunc

; Called only after owned preparation and any rebind postconditions/configuration.
; Reopen does not call this: changing a preference must never race live guests.
Func _MS_OpenLocalizedManager(ByRef $s)
    Local $active = $s["worker"]
    If Not $s["owned"] Or $active["handle"] <> 0 Then Return False
    If $s["oracle_language"] == "" Then Return _MS_OpenManager($s)
    Local $args = _OL_Command($s["oracle_language"])
    If $args == "" Then Return False
    Local $profile = _PP_Inspect($s["root"])
    If $profile["status"] <> "READY" Then Return False
    Local $worker = _MP_Start($s["app_system"] & "\VBoxManage.exe", $args, _
        $s["app_system"], $profile["profile"])
    $s["worker"] = $worker
    $s["worker_uncertain"] = 0
    If $worker["status"] <> "STARTED" Then Return False
    _MS_State($s, "CONFIGURING_LANGUAGE")
    Return True
EndFunc

Func _MS_OpenManager(ByRef $s)
    Local $old = $s["manager"]
    If $old["handle"] <> 0 Then
        If _MP_Poll($old) <> "EXITED" Then Return False
        _MP_Release($old)
    EndIf
    Local $profile = _PP_Inspect($s["root"])
    If $profile["status"] <> "READY" Then Return False
    ; Code comes from the helper-validated protected copy in separated mode.
    ; The process token and portable user profile remain non-administrative.
    Local $p = _MP_Start($s["app_system"] & "\VirtualBox.exe", "", $s["app_system"], $profile["profile"], True)
    $s["manager"] = $p
    If $p["status"] <> "STARTED" Then Return False
    $s["seen"] = False
    $s["stopping"] = False
    $s["close_posted"] = False
    $s["window_key"] = ""
    $s["window_clock"] = TimerInit()
    $s["quiet"] = 0
    _MS_State($s, "OPENING")
    Return True
EndFunc

Func _MS_Reopen(ByRef $s)
    If $s["state"] <> "WAIT_GUESTS" And $s["state"] <> "WAIT_BACKGROUND" Then Return False
    If Not $s["owned"] Then Return False
    Return _MS_OpenManager($s)
EndFunc

Func _MS_CanLeaveDeclined($state, $owned, $workerHandle)
    Return IsString($state) And $state == "CLEANUP_DECLINED" And IsBool($owned) And $owned And _
        IsNumber($workerHandle) And $workerHandle = 0
EndFunc

Func _MS_Stop(ByRef $s)
    If $s["state"] == "CLEANUP_DECLINED" Then
        $s["quiet"] = 0
        _MS_State($s, "READY_TO_CLEAN")
        Return True
    EndIf
    If $s["state"] <> "MANAGER_OPEN" And $s["state"] <> "OPENING" Then Return False
    ; Queue a request; the event loop posts WM_CLOSE only when the observed
    ; window is stable. Do not race Qt's deferred geometry persistence.
    $s["stopping"] = True
    $s["close_posted"] = False
    _MS_State($s, "CLOSING")
    Return True
EndFunc

Func _MS_Tick(ByRef $s)
    Local $state = $s["state"]
    If $state == "VERIFYING_CLEAN" Then
        ; Hold the cross-root lock until the host remains genuinely empty for
        ; 2.5s. A transient process/unknown read resets the quiet interval.
        ; Never claim CLEAN on a negative count, foreign service or installed VBox.
        Local $installed = _PortableInstalledVBoxDetected()
        Local $services = _PortableCountExistingServices()
        Local $processes = _PortableCountVirtualBoxProcesses()
        If _MS_HostClean($installed, $services, $processes) Then
            If $s["quiet"] = 0 Then $s["quiet"] = TimerInit()
            If TimerDiff($s["quiet"]) > 2500 Then
                $s["owned"] = False
                Local $manager = $s["manager"]
                If $manager["handle"] <> 0 Then _MP_Release($manager)
                $s["manager"] = $manager
                DllCall("kernel32.dll", "bool", "ReleaseMutex", "handle", $s["mutex"])
                DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $s["mutex"])
                $s["mutex"] = 0
                _MS_State($s, "CLEAN")
            EndIf
        Else
            $s["quiet"] = 0
        EndIf
        If $s["state"] == "VERIFYING_CLEAN" And TimerDiff($s["clock"]) > 45000 Then _
            _MS_State($s, "FAILED", "clean-host-never-stabilized-resources-retained")
        Return
    EndIf
    If $state == "PREPARING" Or $state == "CLEANING" Or $state == "CONFIGURING" Or $state == "CONFIGURING_LANGUAGE" Or _
            $state == "REBIND_UNREGISTER" Or $state == "REBIND_REGISTER" Or _
            _MS_ConsentPending($state) Or $state == "RECOVERING" Then
        Local $worker = $s["worker"], $status = _MP_Poll($worker)
        $s["worker"] = $worker
        If $status == "PRESENT" Then
            ; Never dismiss a still-live fixed helper because of elapsed time.
            ; The GUI stays responsive and retains its worker/controller handle.
            If Not _MS_ConsentPending($state) And TimerDiff($s["clock"]) > 180000 Then _
                _MS_State($s, $state, "worker-still-running-no-cleanup")
            Return
        EndIf
        If $status == "UNKNOWN" Then
            ; Windows can release a fast VBoxManage/pwsh child between the
            ; retained-handle WAIT_TIMEOUT and its read-only identity probe.
            ; Poll the SAME handle again; never synthesize a successful exit.
            If $s["worker_uncertain"] = 0 Then $s["worker_uncertain"] = TimerInit()
            If _MS_WorkerUnknownWait(TimerDiff($s["worker_uncertain"])) Then Return
        EndIf
        If $status <> "EXITED" Then
            ; A persistent unknown handle must not allow the controller to
            ; vanish while its elevated effect could still be in progress.
            ; Remain in the same pending phase, retaining all locks/handles.
            _MS_State($s, $state, "worker-not-confirmed-" & $status & "-retain-session")
            Return
        EndIf
        $s["worker_uncertain"] = 0
        _MP_Release($worker)
        $s["worker"] = $worker
        If $s["separated"] And $worker["exit_code"] = 1223 Then
            If $state == "CLEANING" Or $state == "CONSENT_FINISH" Then
                _MS_State($s, "CLEANUP_DECLINED", "click-finish-to-retry-elevation")
            ElseIf $state == "CONSENT_RECOVER" Or $state == "RECOVERING" Then
                ; A denied recovery does not change the old protected session.
                If $s["mutex"] <> 0 Then
                    DllCall("kernel32.dll", "bool", "ReleaseMutex", "handle", $s["mutex"])
                    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $s["mutex"])
                    $s["mutex"] = 0
                EndIf
                _MS_State($s, "IDLE", "recovery-consent-cancelled-resources-retained")
            Else
                Local $installed = _PortableInstalledVBoxDetected()
                If Not IsBool($installed) Or $installed Or FileExists($s["session"]) Or _PortableCountExistingServices() <> 0 Or _PortableCountVirtualBoxProcesses() <> 0 Then
                    _MS_State($s, "FAILED", "cancelled-but-host-state-not-clear")
                    Return
                EndIf
                DllCall("kernel32.dll", "bool", "ReleaseMutex", "handle", $s["mutex"])
                DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $s["mutex"])
                $s["mutex"] = 0
                _MS_State($s, "IDLE", "elevation-cancelled-no-system-changes")
            EndIf
            Return
        EndIf
        If $worker["exit_code"] <> 0 Then
            _MS_State($s, "FAILED", "worker-failed-no-guessed-cleanup-exit-" & $worker["exit_code"])
            Return
        EndIf
        If $state == "CLEANING" Or $state == "CONSENT_FINISH" Or $state == "CONSENT_RECOVER" Or $state == "RECOVERING" Then
            ; The helper has confirmed exact-owned teardown. Wait for any
            ; delayed Oracle COM background work to disappear *stably* before
            ; reporting CLEAN and allowing another Start.
            $s["quiet"] = 0
            _MS_State($s, "VERIFYING_CLEAN")
            Return
        EndIf
        If $state == "CONFIGURING_LANGUAGE" Then
            If Not _OL_Verified($s["root"], $s["oracle_language"]) Then
                _MS_State($s, "FAILED", "oracle-language-unverified")
            ElseIf Not _MS_OpenManager($s) Then
                _MS_State($s, "FAILED", "manager-not-started")
            EndIf
            Return
        EndIf
        If $state == "CONFIGURING" Then
            If Not _MS_OpenLocalizedManager($s) Then _MS_State($s, "FAILED", "oracle-language-not-started")
            Return
        EndIf
        If $state == "REBIND_UNREGISTER" Then
            If Not _MS_RebindStep($s, "register") Then _MS_State($s, "FAILED", "rebind-register-not-started-no-guessed-recovery")
            Return
        EndIf
        If $state == "REBIND_REGISTER" Then
            If Not _PVR_Rebound($s["root"], $s["rebind"]) Then
                _MS_State($s, "FAILED", "rebind-postcondition-unverified-retain-backup")
                Return
            EndIf
            ; The user's default machine folder is configured only AFTER
            ; Oracle has confirmed the relocated VM registration.
            Local $reboundProfile = _PP_Inspect($s["root"])
            If $reboundProfile["status"] <> "READY" Then
                _MS_State($s, "FAILED", "rebind-profile-missing")
                Return
            EndIf
            Local $nextConfigure = _MP_Start($s["app_system"] & "\VBoxManage.exe", _
                'setproperty machinefolder "' & $reboundProfile["machines"] & '"', _
                $s["app_system"], $reboundProfile["profile"])
            $s["worker"] = $nextConfigure
            $s["worker_uncertain"] = 0
            If $nextConfigure["status"] <> "STARTED" Then
                _MS_State($s, "FAILED", "post-rebind-configure-not-started")
            Else
                _MS_State($s, "CONFIGURING", "rebind-verified-configure-machine-folder")
            EndIf
            Return
        EndIf
        Local $sup = _WinObsService("VBoxSup"), $sds = _WinObsService("VBoxSDS")
        If Not _PCVM_ExpectedSup($sup) Or Not _PVS_ExpectedSDS($sds, $s["app_system"] & "\VBoxSDS.exe") Then
            _MS_State($s, "FAILED", "unexpected-services-after-prepare")
            Return
        EndIf
        $s["owned"] = True
        Local $rebindProof = $s["rebind"]
        If $rebindProof["status"] == "VERIFIED" Then
            ; The user confirmed this *specific* backup and UUID in the GUI.
            ; No new elevated verb or arbitrary filesystem command is exposed.
            Local $firstRebind = "unregister"
            If $rebindProof["mode"] == "REGISTER_ONLY" Then $firstRebind = "register"
            If Not _MS_RebindStep($s, $firstRebind) Then _
                _MS_State($s, "FAILED", "rebind-first-command-not-started-retain-backup")
            Return
        EndIf
        If $s["separated"] Then
            ; This is a USER preference, never an elevated helper command.
            Local $profile = _PP_Inspect($s["root"])
            Local $configure = _MP_Start($s["app_system"] & "\VBoxManage.exe", 'setproperty machinefolder "' & $profile["machines"] & '"', _
                $s["app_system"], $profile["profile"])
            $s["worker"] = $configure
            $s["worker_uncertain"] = 0
            If $configure["status"] <> "STARTED" Then
                _MS_State($s, "FAILED", "user-profile-configuration-not-started")
            Else
                _MS_State($s, "CONFIGURING")
            EndIf
            Return
        EndIf
        If Not _MS_OpenLocalizedManager($s) Then _MS_State($s, "FAILED", "oracle-language-not-started")
        Return
    EndIf
    If $state <> "OPENING" And $state <> "MANAGER_OPEN" And $state <> "CLOSING" And _
            $state <> "WAIT_GUESTS" And $state <> "WAIT_BACKGROUND" And $state <> "READY_TO_CLEAN" Then Return
    Local $manager = $s["manager"], $status = _MP_Poll($manager), $windowReady = False
    If $status == "PRESENT" Then
        $windowReady = _MS_ObserveWindow($s, $manager)
        If $windowReady Then $s["seen"] = True
    EndIf
    $s["manager"] = $manager
    Local $activity = _PortableActivityCollect()
    $s["guests"] = $activity["guest"]
    If $activity["status"] <> "KNOWN" Or $status == "UNKNOWN" Then
        ; A short-lived VBoxManage may exit during observation. Never treat
        ; that race as idle: retry a bounded interval, then retain resources.
        If $s["uncertain"] = 0 Then $s["uncertain"] = TimerInit()
        If TimerDiff($s["uncertain"]) > 5000 Then _MS_State($s, "FAILED", "persistent-unknown-activity")
        Return
    EndIf
    $s["uncertain"] = 0
    Local $next = _MS_Decide($status, $s["seen"], $activity["total"], $activity["guest"], $s["owned"])
    If $next == "BLOCKED" Then
        _MS_State($s, "FAILED", "unknown-process-or-manager-startup")
        Return
    EndIf
    If $next == "MANAGER_OPEN" Then
        If Not $s["seen"] Then
            If TimerDiff($s["clock"]) > 30000 Then _MS_State($s, "FAILED", "manager-window-timeout")
            Return
        EndIf
        If $s["stopping"] Then
            If Not $s["close_posted"] And $windowReady Then
                If _MP_RequestClose($manager) Then
                    $s["close_posted"] = True
                    $s["clock"] = TimerInit()
                    ConsoleWrite("Manager session: graceful close posted after stable window" & @CRLF)
                EndIf
                $s["manager"] = $manager
            EndIf
            If TimerDiff($s["clock"]) > 30000 Then _MS_State($s, "FAILED", "manager-close-not-confirmed")
        Else
            _MS_State($s, "MANAGER_OPEN")
        EndIf
        Return
    EndIf
    If $next == "READY_TO_CLEAN" Then
        Local $gate = $s["cli_gate"]
        If $gate["handle"] <> 0 Then
            ; Close admission BEFORE taking the lease. If a client won the
            ; race, retain resources until its exact process exit releases it.
            If Not _CG_SetReady($gate, False) Then
                _MS_State($s, "FAILED", "portable-cli-admission-unverified")
                Return
            EndIf
            Local $lease = _CG_Acquire($gate)
            $s["cli_gate"] = $gate
            If $lease == "BUSY" Then
                $s["quiet"] = 0
                _MS_State($s, "WAIT_BACKGROUND", "portable-cli-active")
                Return
            EndIf
            If $lease <> "HELD" Then
                _MS_State($s, "FAILED", "portable-cli-abandoned-or-unknown-retain-resources")
                Return
            EndIf
            ; A new command may have run between the first observation and
            ; lease acquisition. Reobserve while holding the admission lock.
            Local $afterLease = _PortableActivityCollect()
            If $afterLease["status"] <> "KNOWN" Or $afterLease["total"] <> 0 Then
                $s["quiet"] = 0
                _MS_State($s, "WAIT_BACKGROUND", "portable-cli-reobserve")
                Return
            EndIf
        EndIf
        If $s["quiet"] = 0 Then $s["quiet"] = TimerInit()
        _MS_State($s, "READY_TO_CLEAN")
        If TimerDiff($s["quiet"]) < 1500 Then Return
        If Not _MS_Worker($s, "Finish") Then
            _MS_State($s, "FAILED", "cleanup-worker-not-started")
        Else
            _MS_State($s, _MS_ConsentPhase($s["separated"], "Finish"))
        EndIf
        Return
    EndIf
    $s["quiet"] = 0
    _MS_State($s, $next)
    If $next == "WAIT_BACKGROUND" And TimerDiff($s["clock"]) > 90000 Then _MS_State($s, "FAILED", "background-not-idle")
EndFunc
