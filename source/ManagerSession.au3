#include-once
#include "ManagedProcess.au3"
#include "PortableApp.au3"
#include "PortableCIVM.au3"
#include "PrivilegeBoundary.au3"
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
    $s["app_system"] = $root & "\app64"
    $s["worker"] = _MP_New()
    $s["manager"] = _MP_New()
    $s["mutex"] = 0
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
    Return $s
EndFunc

Func _MS_State(ByRef $s, $state, $detail = "")
    If $s["state"] <> $state Or $s["detail"] <> $detail Then
        ConsoleWrite("Manager session: " & $state & " " & $detail & @CRLF)
        $s["clock"] = TimerInit()
    EndIf
    $s["state"] = $state
    $s["detail"] = $detail
EndFunc

Func _MS_Allowed($root, $workspace)
    If Not _PVS_Allowed(EnvGet("GITHUB_ACTIONS"), EnvGet("RUNNER_ENVIRONMENT"), EnvGet("RUNNER_OS"), _
            EnvGet("GITHUB_REPOSITORY"), $root, EnvGet("RUNNER_TEMP")) Then Return False
    If Not _PP_RootSafe($workspace) Or Not _PP_ParentsSafe($workspace) Then Return False
    Return _PP_ParentsSafe($root)
EndFunc

Func _MS_Quote($value)
    If Not _PP_RootSafe($value) Then Return ""
    Return '"' & $value & '"'
EndFunc

Func _MS_Worker(ByRef $s, $action)
    If $action <> "Prepare" And $action <> "Finish" Then Return False
    If $s["separated"] Then
        Local $privileged = _PB_Start($s["root"], $action, $s["cycle"])
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

Func _MS_Start(ByRef $s)
    If $s["state"] <> "IDLE" And $s["state"] <> "CLEAN" Then Return False
    If Not _MS_Allowed($s["root"], $s["workspace"]) Then
        _MS_State($s, "BLOCKED", "disposable-host-only")
        Return False
    EndIf
    If $s["separated"] And Not _PB_Medium() Then
        _MS_State($s, "BLOCKED", "frontend-must-be-non-administrator")
        Return False
    EndIf
    Local $app = _PA_Inspect($s["root"])
    If $app["status"] <> "PRESENT" Then
        _MS_State($s, "BLOCKED", "incomplete-app64")
        Return False
    EndIf
    Local $installed = _PortableInstalledVBoxDetected()
    If Not IsBool($installed) Or $installed Or _PortableCountExistingServices() <> 0 Or _PortableCountVirtualBoxProcesses() <> 0 Then
        _MS_State($s, "BLOCKED", "existing-or-unknown-VirtualBox")
        Return False
    EndIf
    ; Cross-root exclusion before system changes. Existence is a refusal, not
    ; an invitation to acquire a mutex/resources left by another process.
    Local $a = DllCall("kernel32.dll", "handle", "CreateMutexW", "ptr", 0, "bool", True, "wstr", "Global\PortableVirtualBox.ManagerExperiment")
    If @error Then
        _MS_State($s, "BLOCKED", "session-lock-create-failed-dll")
        Return False
    EndIf
    Local $h = $a[0], $e = DllCall("kernel32.dll", "dword", "GetLastError")
    If @error Then
        If $h <> 0 Then DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
        _MS_State($s, "BLOCKED", "session-lock-result-unknown")
        Return False
    EndIf
    If $h = 0 Then
        _MS_State($s, "BLOCKED", "session-lock-create-failed-win32-" & $e[0])
        Return False
    EndIf
    If $e[0] = 183 Then
        DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
        _MS_State($s, "BLOCKED", "another-session")
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
    _MS_State($s, "PREPARING")
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
    If $state == "PREPARING" Or $state == "CLEANING" Or $state == "CONFIGURING" Then
        Local $worker = $s["worker"], $status = _MP_Poll($worker)
        $s["worker"] = $worker
        If $status == "PRESENT" Then
            If TimerDiff($s["clock"]) > 180000 Then _MS_State($s, "FAILED", "worker-timeout-no-guessed-cleanup")
            Return
        EndIf
        If $status <> "EXITED" Then
            _MS_State($s, "FAILED", "worker-failed-no-guessed-cleanup")
            Return
        EndIf
        _MP_Release($worker)
        $s["worker"] = $worker
        If $s["separated"] And $worker["exit_code"] = 1223 Then
            If $state == "CLEANING" Then
                _MS_State($s, "CLEANUP_DECLINED", "click-finish-to-retry-elevation")
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
            _MS_State($s, "FAILED", "worker-failed-no-guessed-cleanup")
            Return
        EndIf
        If $state == "CLEANING" Then
            If _PortableCountExistingServices() <> 0 Or _PortableCountVirtualBoxProcesses() <> 0 Then
                _MS_State($s, "FAILED", "host-not-clean")
                Return
            EndIf
            $s["owned"] = False
            Local $manager = $s["manager"]
            If $manager["handle"] <> 0 Then _MP_Release($manager)
            $s["manager"] = $manager
            DllCall("kernel32.dll", "bool", "ReleaseMutex", "handle", $s["mutex"])
            DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $s["mutex"])
            $s["mutex"] = 0
            _MS_State($s, "CLEAN")
            Return
        EndIf
        If $state == "CONFIGURING" Then
            If Not _MS_OpenManager($s) Then _MS_State($s, "FAILED", "manager-not-started")
            Return
        EndIf
        Local $sup = _WinObsService("VBoxSup"), $sds = _WinObsService("VBoxSDS")
        If Not _PCVM_ExpectedSup($sup) Or Not _PVS_ExpectedSDS($sds, $s["app_system"] & "\VBoxSDS.exe") Then
            _MS_State($s, "FAILED", "unexpected-services-after-prepare")
            Return
        EndIf
        $s["owned"] = True
        If $s["separated"] Then
            ; This is a USER preference, never an elevated helper command.
            Local $profile = _PP_Inspect($s["root"])
            Local $configure = _MP_Start($s["app_system"] & "\VBoxManage.exe", 'setproperty machinefolder "' & $profile["machines"] & '"', _
                $s["app_system"], $profile["profile"])
            $s["worker"] = $configure
            If $configure["status"] <> "STARTED" Then
                _MS_State($s, "FAILED", "user-profile-configuration-not-started")
            Else
                _MS_State($s, "CONFIGURING")
            EndIf
            Return
        EndIf
        If Not _MS_OpenManager($s) Then _MS_State($s, "FAILED", "manager-not-started")
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
        If $s["quiet"] = 0 Then $s["quiet"] = TimerInit()
        _MS_State($s, "READY_TO_CLEAN")
        If TimerDiff($s["quiet"]) < 1500 Then Return
        If Not _MS_Worker($s, "Finish") Then
            _MS_State($s, "FAILED", "cleanup-worker-not-started")
        Else
            _MS_State($s, "CLEANING")
        EndIf
        Return
    EndIf
    $s["quiet"] = 0
    _MS_State($s, $next)
    If $next == "WAIT_BACKGROUND" And TimerDiff($s["clock"]) > 90000 Then _MS_State($s, "FAILED", "background-not-idle")
EndFunc
