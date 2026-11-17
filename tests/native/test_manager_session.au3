#include "..\..\source\ManagerSession.au3"
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL manager policy: " & $label & @CRLF)
    EndIf
EndFunc
Func NativeMutexCapture($name)
    Local $a = DllCall($g_WinObsKernel32, "handle", "CreateMutexW", "ptr", 0, "bool", True, "wstr", $name)
    Local $dllerror = @error
    Local $lockerror = _WinObsLastError()
    Local $r[3] = [0, $dllerror, $lockerror]
    If IsArray($a) Then $r[0] = $a[0]
    Return $r
EndFunc
Func NativeMutexClose($handle)
    If $handle = 0 Then Return False
    Local $a = DllCall($g_WinObsKernel32, "bool", "CloseHandle", "handle", $handle)
    Return Not @error And IsArray($a) And $a[0] <> 0
EndFunc
Func NativeMutexRelease($handle)
    If $handle = 0 Then Return False
    Local $a = DllCall($g_WinObsKernel32, "bool", "ReleaseMutex", "handle", $handle)
    Return Not @error And IsArray($a) And $a[0] <> 0
EndFunc
Func NativeMutexHandleCount()
    Local $a = DllCall($g_WinObsKernel32, "bool", "GetProcessHandleCount", "handle", -1, "dword*", 0)
    If @error Or Not IsArray($a) Or Not $a[0] Then Return -1
    Return $a[2]
EndFunc
Check(_MS_Decide("PRESENT", True, 3, 1, True) == "MANAGER_OPEN", "Manager and guest coexist")
Check(_MS_Decide("EXITED", True, 2, 1, True) == "WAIT_GUESTS", "closing Manager never implies stopped VM")
Check(_MS_Decide("EXITED", True, 1, 1, True) == "WAIT_GUESTS", "headless-only guest keeps driver")
Check(_MS_Decide("EXITED", True, 1, 0, True) == "WAIT_BACKGROUND", "background clients prevent cleanup")
Check(_MS_Decide("EXITED", True, 0, 0, True) == "READY_TO_CLEAN", "quiet owned session may request rechecked cleanup")
Check(_MS_Decide("UNKNOWN", True, 0, 0, True) == "BLOCKED", "unknown Manager never treated as closed")
Check(_MS_Decide("EXITED", True, -1, 0, True) == "BLOCKED", "unknown process enumeration blocks")
Check(_MS_Decide("EXITED", True, 0, -1, True) == "BLOCKED", "unknown guest count blocks")
Check(_MS_Decide("EXITED", True, 0, 1, True) == "BLOCKED", "contradictory observation blocks")
Check(_MS_Decide("EXITED", True, 0, 0, False) == "BLOCKED", "foreign resources never cleaned")
Check(_MS_Decide("EXITED", False, 0, 0, True) == "BLOCKED", "Manager startup never confirmed")
Check(_MS_Decide("PRESENT", True, 0, 0, True) == "BLOCKED", "live Manager contradicts empty list")
Check(_MS_Decide("EXITED", True, "0", 0, True) == "BLOCKED", "string count refused")
Check(Not _MS_WindowReady(True, 0), "first visibility is not initialized Manager")
Check(Not _MS_WindowReady(True, 749), "deferred geometry has not settled")
Check(_MS_WindowReady(True, 750), "stable enabled window passes after quiet interval")
Check(Not _MS_WindowReady(False, 900), "changed or disabled window never passes")
Check(Not _MS_WindowReady(True, "900"), "unknown elapsed observation refused")
Check(_MS_HostClean(False, 0, 0), "true clean host with no installed VBox")
Check(Not _MS_HostClean(True, 0, 0), "installed VBox is not clean")
Check(Not _MS_HostClean(False, -1, 0), "unknown service state is not clean")
Check(Not _MS_HostClean(False, 0, -1), "unknown process state is not clean")
Check(Not _MS_HostClean(False, 0, 1), "delayed Oracle activity prevents clean state")
Check(Not _MS_HostClean("False", 0, 0), "unknown install observation fails closed")
Check(_MS_WorkerUnknownWait(0), "unknown child observation may be transient")
Check(_MS_WorkerUnknownWait(4999), "retry same process handle only within bounded window")
Check(Not _MS_WorkerUnknownWait(5000), "persistent unknown child cannot be called exited")
Check(Not _MS_WorkerUnknownWait(-1), "invalid elapsed time cannot enable retry")
Check(Not _MS_WorkerUnknownWait("unknown"), "non-numeric timeout is not trusted")
Check(_MS_RetryAllowed("IDLE", ""), "idle can start")
Check(_MS_RetryAllowed("CLEAN", ""), "verified clean can start")
Check(_MS_RetryAllowed("BLOCKED", "existing-or-unknown-VirtualBox"), "explicit retry repeats preflight")
Check(Not _MS_RetryAllowed("BLOCKED", "another-session"), "foreign lock not retryable")
Check(Not _MS_RetryAllowed("FAILED", "worker-error"), "failed session not retryable")
Check(Not _MS_RetryAllowed("VERIFYING_CLEAN", ""), "reopen disabled until stable quiet")
; Sequential, test-owned Local objects only. No production session mutex,
; other process or wait is involved; existing objects are never acquired.
Local $mutexBaseline = NativeMutexHandleCount()
Check($mutexBaseline > 0, "mutex fixture handle baseline is available")
Local $mutexName = "Local\PortableVBox.NativeMutex." & @AutoItPID & "." & @MSEC
Local $newMutex = NativeMutexCapture($mutexName)
Check($newMutex[0] <> 0 And $newMutex[1] = 0 And $newMutex[2] = 0, "new private mutex reports exact new-object success")
Local $ownedExisting = NativeMutexCapture($mutexName)
Check($ownedExisting[0] <> 0 And $ownedExisting[1] = 0 And $ownedExisting[2] = 183, "already-owned private object reports exact existing-object refusal")
Check(NativeMutexClose($ownedExisting[0]), "close refused existing-object fixture handle")
Check(NativeMutexRelease($newMutex[0]), "release fixture ownership while retaining its object")
Local $unownedExisting = NativeMutexCapture($mutexName)
Check($unownedExisting[0] <> 0 And $unownedExisting[1] = 0 And $unownedExisting[2] = 183, "existing-but-unowned object still reports refusal")
Check(NativeMutexClose($unownedExisting[0]), "close refused unowned-object fixture handle")
Check(NativeMutexClose($newMutex[0]), "close original private fixture object")
Check(NativeMutexHandleCount() = $mutexBaseline, "mutex capture fixtures preserve handle balance")
Local $s = _MS_New("C:\not-a-runner\root", "C:\workspace")
Check(Not _MS_Start($s), "local directory cannot start privileged experiment")
Check($s["state"] == "BLOCKED", "refusal surfaced")
Check(Not _MS_Stop($s), "no stop without owned session")
Check(Not _MS_Reopen($s), "no reopen without owned session")
; Cleanup UI tickets request only the same protected action; they never mean
; that a previous attempt was preflight-only or grant system-effect replay.
Func RetryFixture($action)
    Local $r = _MS_New("C:\not-a-runner\root", "C:\workspace"), $w = _MP_New()
    $r["state"] = "FAILED"
    $r["separated"] = True
    $r["mutex"] = 1 ; synthetic eligibility only, never used for a native wait/close
    $r["cycle"] = 7
    $r["owned"] = $action == "Finish"
    $r["former_pid"] = ($action == "Recover" ? @AutoItPID + 1 : 0)
    $r["cleanup_retry_action"] = $action
    $w["status"] = "EXITED"
    $w["exit_code"] = 70
    $r["worker"] = $w
    Return $r
EndFunc
For $phase In StringSplit("CLEANING|CONSENT_FINISH", "|", 2)
    Check(_MS_CleanupFailureAction(True, $phase, 70) == "Finish", "confirmed finish phase ticket")
Next
For $phase In StringSplit("RECOVERING|CONSENT_RECOVER", "|", 2)
    Check(_MS_CleanupFailureAction(True, $phase, 70) == "Recover", "confirmed recovery phase ticket")
Next
For $phase In StringSplit("PREPARING|CONSENT_PREPARE|CONFIGURING|REBIND_REGISTER|FAILED|VERIFYING_CLEAN", "|", 2)
    Check(_MS_CleanupFailureAction(True, $phase, 70) == "", "unrelated failure has no cleanup ticket")
Next
Local $retryCodes[4] = [0, 1, 1223, -1]
For $code In $retryCodes
    Check(_MS_CleanupFailureAction(True, "CONSENT_FINISH", $code) == "", "other outcome cannot enable recheck")
Next
Check(_MS_CleanupFailureAction(False, "CLEANING", 70) == "", "legacy worker cannot receive protected ticket")
Check(_MS_CleanupFailureAction(True, "CLEANING", "70") == "", "string status refused")
Local $retry = RetryFixture("Finish")
Check(_MS_CleanupRetryAction($retry) == "Finish", "failed finish offers explicit recheck only")
Check(Not _MS_RetryAllowed($retry["state"], $retry["detail"]), "failed cleanup still cannot Start or rebind")
Check(Not _CG_StateAllows($retry["state"]), "failed cleanup never reopens CLI gate")
Check(Not _MS_Stop($retry), "unsafe root cannot actually request elevated retry")
$retry["owned"] = False
Check(_MS_CleanupRetryAction($retry) == "", "finish without owned session refused")
$retry = RetryFixture("Finish")
$retry["mutex"] = 0
Check(_MS_CleanupRetryAction($retry) == "", "missing retained lock refused")
$retry = RetryFixture("Finish")
Local $retryWorker = $retry["worker"]
$retryWorker["handle"] = 123
$retry["worker"] = $retryWorker
Check(_MS_CleanupRetryAction($retry) == "", "live or retained worker handle blocks repeated clicks")
$retryWorker["handle"] = 0
$retryWorker["status"] = "UNKNOWN"
$retry["worker"] = $retryWorker
Check(_MS_CleanupRetryAction($retry) == "", "unknown worker cannot enable recheck")
$retry = RetryFixture("Recover")
Check(_MS_CleanupRetryAction($retry) == "Recover", "recovery retains original action and PID")
$retry["former_pid"] = @AutoItPID
Check(_MS_CleanupRetryAction($retry) == "", "self owner never becomes abandoned recovery")
$retry = RetryFixture("Recover")
$retry["cleanup_retry_action"] = "Prepare"
Check(_MS_CleanupRetryAction($retry) == "", "arbitrary ticket action refused")
$retry = RetryFixture("Finish")
Check(_MS_TakeCleanupRetry($retry) == "Finish", "explicit click consumes same action")
Check($retry["state"] == "CONSENT_FINISH" And $retry["cleanup_retry_action"] == "", "ticket consumed before request launch")
Check(_MS_TakeCleanupRetry($retry) == "", "second click cannot create another request")
Check(Not _CG_StateAllows($retry["state"]), "pending recheck keeps CLI closed")
$retry = RetryFixture("Recover")
Check(_MS_TakeCleanupRetry($retry) == "Recover" And $retry["state"] == "CONSENT_RECOVER", "recovery retry does not become Finish")
Check(_MS_CleanupFailureAction(True, "CONSENT_FINISH", 70) == "Finish", "post-admission is never inferred safe: ticket remains only a request")
; Actual retained harmless child, not a fake exit-code assignment. No helper or
; system-effect command is launched; the retry itself remains a pure state test.
Local $workerMutex = NativeMutexCapture("Local\PortableVBox.RetryPolicy." & @AutoItPID & "." & @MSEC)
Check($workerMutex[0] <> 0 And $workerMutex[2] = 0, "private retry fixture lock created")
Local $observed = RetryFixture("Finish")
$observed["state"] = "CONSENT_FINISH"
$observed["cleanup_retry_action"] = ""
$observed["mutex"] = $workerMutex[0]
$observed["worker"] = _MP_Start(@ComSpec, "/d /c exit 70", @TempDir)
Local $child = $observed["worker"]
Check($child["status"] == "STARTED", "harmless exit fixture actually started")
Local $deadline = TimerInit()
While $observed["state"] == "CONSENT_FINISH" And TimerDiff($deadline) < 5000
    _MS_Tick($observed)
    Sleep(10)
WEnd
Check($observed["state"] == "FAILED" And _MS_CleanupRetryAction($observed) == "Finish", "confirmed harmless worker exit generates explicit request ticket")
$child = $observed["worker"]
Check($child["handle"] = 0 And $child["status"] == "EXITED" And $child["exit_code"] = 70, "original worker exit and release remain observed")
Check(NativeMutexRelease($workerMutex[0]) And NativeMutexClose($workerMutex[0]), "release only private fixture lock")
Check(_MS_GateFailureState("CONSENT_FINISH", "FAILED", 123) == "CONSENT_FINISH", "gate failure preserves existing cleanup worker phase")
Check(_MS_GateFailureState("READY_TO_CLEAN", "CONSENT_FINISH", 123) == "CONSENT_FINISH", "new retained child keeps requested polling phase")
Check(_MS_GateFailureState("FAILED", "CONSENT_FINISH", 0) == "FAILED", "gate failure before launch cannot enter consent")
Check(_MS_GateFailureState("CONSENT_FINISH", "VERIFYING_CLEAN", 0) == "FAILED", "gate failure never reports clean after child release")
Check(_MS_GateFailureState("FAILED", "FAILED", 123) == "FAILED", "unknown phase is not invented from a handle")
; Exercise the old persistent-UNKNOWN Tick path, including its real gate error.
; This is only a harmless fixed sleep/exit child with deliberately contradictory
; observation metadata, not an elevated helper or system mutation.
Local $unknown = _MS_New("C:\not-a-runner\root", "C:\workspace")
$unknown["state"] = "CONSENT_FINISH"
$unknown["separated"] = True
Local $unknownChild = _MP_Start(@SystemDir & "\WindowsPowerShell\v1.0\powershell.exe", '-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 7000; exit 70"', @TempDir)
Check($unknownChild["handle"] <> 0, "harmless unknown-observation child retained")
$unknownChild["image"] = "C:\deliberately-not-the-child.exe"
$unknown["worker"] = $unknownChild
Local $brokenGate = _CG_New()
$brokenGate["handle"] = 1 ; synthetic, never passed to a native API here
$brokenGate["ready"] = 0 ; SetReady fails before making a native call
$unknown["cli_gate"] = $brokenGate
Local $unknownClock = TimerInit(), $sawGatePending = False
While TimerDiff($unknownClock) < 15000
    _MS_Tick($unknown)
    $unknownChild = $unknown["worker"]
    If $unknown["detail"] == "portable-cli-gate-unverified-resources-retained" And _
            $unknown["state"] == "CONSENT_FINISH" And $unknownChild["handle"] <> 0 Then $sawGatePending = True
    If $unknownChild["handle"] = 0 Then ExitLoop
    Sleep(20)
WEnd
Check($sawGatePending, "persistent unknown worker remains polled despite CLI gate failure")
Check($unknownChild["status"] == "EXITED" And $unknownChild["exit_code"] = 70 And $unknownChild["handle"] = 0, "unknown worker eventually reports exact exit and releases original handle")
Check($unknown["state"] == "FAILED" And _MS_CleanupRetryAction($unknown) == "", "gate failure never creates verified clean state")
; Cancelling a recheck must not reopen CLI or release the uncertain session.
For $cancelAction In StringSplit("Finish|Recover", "|", 2)
    Local $cancelled = RetryFixture($cancelAction)
    Check(_MS_TakeCleanupRetry($cancelled) == $cancelAction, "bind recheck before simulated consent cancellation")
    Local $cancelWorker = $cancelled["worker"]
    $cancelWorker["exit_code"] = 1223
    $cancelled["worker"] = $cancelWorker
    Check(_MS_RecheckCancelled($cancelled), "recheck cancellation distinguished from first cleanup cancellation")
    Check($cancelled["state"] == "FAILED" And Not _CG_StateAllows($cancelled["state"]), "cancelled recheck cannot reopen CLI admission")
    Check($cancelled["mutex"] = 1 And _MS_CleanupRetryAction($cancelled) == $cancelAction, "cancelled recheck retains original lock and action")
    Check(_MS_TakeCleanupRetry($cancelled) == $cancelAction And _MS_TakeCleanupRetry($cancelled) == "", "cancelled recheck permits one later explicit request only")
Next
Local $firstCancel = RetryFixture("Finish")
$firstCancel["state"] = "CONSENT_FINISH"
$firstCancel["cleanup_retry_action"] = ""
Local $firstCancelWorker = $firstCancel["worker"]
$firstCancelWorker["exit_code"] = 1223
$firstCancel["worker"] = $firstCancelWorker
Check(Not _MS_RecheckCancelled($firstCancel), "ordinary first cancellation cannot invent a prior failed request")
Local $realCancel = RetryFixture("Finish")
Check(_MS_TakeCleanupRetry($realCancel) == "Finish", "bind actual harmless cancellation-status child")
$realCancel["worker"] = _MP_Start(@ComSpec, "/d /c exit 1223", @TempDir)
Local $cancelClock = TimerInit()
While $realCancel["state"] == "CONSENT_FINISH" And TimerDiff($cancelClock) < 5000
    _MS_Tick($realCancel)
    Sleep(10)
WEnd
Check($realCancel["state"] == "FAILED" And _MS_CleanupRetryAction($realCancel) == "Finish", "actual retained exit1223 preserves failed-session retry ticket, not UAC acceptance")
Check(Not _CG_StateAllows($realCancel["state"]), "actual cancelled recheck leaves CLI closed")
ConsoleWrite("Native Manager session assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
