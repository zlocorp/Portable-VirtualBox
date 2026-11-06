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
ConsoleWrite("Native Manager session assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
