#include "..\..\source\CliSessionGate.au3"
#include "..\..\source\ManagerSession.au3"
If $CmdLine[0] = 3 And ($CmdLine[1] == "--lease" Or $CmdLine[1] == "--abandon") Then
    Local $open = DllCall($g_WinObsKernel32, "handle", "OpenMutexW", "dword", 0x100001, "bool", False, "wstr", $CmdLine[2])
    If @error Or $open[0] = 0 Then Exit 2
    Local $wait = DllCall($g_WinObsKernel32, "dword", "WaitForSingleObject", "handle", $open[0], "dword", 0)
    If @error Or $wait[0] <> 0 Then Exit 3
    Local $marker = FileOpen($CmdLine[3], 2)
    If $marker = -1 Then Exit 4
    FileWrite($marker, "held")
    FileClose($marker)
    Sleep(600)
    If $CmdLine[1] == "--lease" Then DllCall($g_WinObsKernel32, "bool", "ReleaseMutex", "handle", $open[0])
    ; Test-only natural process exit without release reproduces abandonment.
    Exit 0
EndIf
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL CLI gate: " & $label & @CRLF)
    EndIf
EndFunc
Check(_CG_Name(0, 1) == "", "zero PID refused")
Check(_CG_Name(123, 0) == "", "zero cycle refused")
Check(_CG_Name("123", 1) == "", "PID strings refused")
Check(_CG_Name(123, 1000) == "", "out-of-policy cycle refused")
For $state In StringSplit("MANAGER_OPEN,WAIT_GUESTS,WAIT_BACKGROUND,CLEANUP_DECLINED", ",", 2)
    Check(_CG_StateAllows($state), "client allowed: " & $state)
Next
For $state In StringSplit("IDLE,OPENING,PREPARING,REBIND_REGISTER,CLEANING,CONSENT_FINISH,FAILED,CLEAN", ",", 2)
    Check(Not _CG_StateAllows($state), "client refused: " & $state)
Next
Local $gate = _CG_Create(@AutoItPID, 997)
Check($gate["handle"] <> 0 And $gate["held"], "fresh gate is initially closed")
Local $duplicate = _CG_Create(@AutoItPID, 997)
Check($duplicate["handle"] = 0, "existing object never adopted")
Check(_CG_SetReady($gate, True) And _CG_Release($gate), "explicitly open gate")
; Execute the real controller state transitions, not a duplicated policy.
Local $session = _MS_New("C:\native-fixture", "C:\workspace")
$session["cli_gate"] = $gate
$session["owned"] = True
_MS_State($session, "MANAGER_OPEN")
$gate = $session["cli_gate"]
Local $readyState = DllCall($g_WinObsKernel32, "dword", "WaitForSingleObject", "handle", $gate["ready"], "dword", 0)
Check(Not $gate["held"] And $readyState[0] = 0, "actual Manager state opens command admission")
_MS_State($session, "CONSENT_FINISH")
$gate = $session["cli_gate"]
$readyState = DllCall($g_WinObsKernel32, "dword", "WaitForSingleObject", "handle", $gate["ready"], "dword", 0)
Check($readyState[0] = 258, "pending cleanup consent closes admission")
_MS_State($session, "CLEANUP_DECLINED")
$gate = $session["cli_gate"]
$readyState = DllCall($g_WinObsKernel32, "dword", "WaitForSingleObject", "handle", $gate["ready"], "dword", 0)
Check($readyState[0] = 0, "declined cleanup permits explicit ordinary commands again")
Local $root = EnvGet("PVBOX_NATIVE_TEST_DIR")
For $mode In StringSplit("--lease,--abandon", ",", 2)
    Local $marker = $root & "\gate-" & StringTrimLeft($mode, 2) & ".txt"
    Local $child = _MP_Start(@ScriptFullPath, $mode & ' "' & _CG_Name(@AutoItPID, 997) & '" "' & $marker & '"', @ScriptDir)
    Check($child["handle"] <> 0, "start native client")
    Local $timer = TimerInit()
    While Not FileExists($marker) And TimerDiff($timer) < 5000
        Sleep(20)
    WEnd
    Check(FileExists($marker), "client really holds mutex")
    Check(_CG_Acquire($gate) == "BUSY", "cleanup cannot overlap client")
    While _MP_Poll($child) <> "EXITED" And TimerDiff($timer) < 8000
        Sleep(20)
    WEnd
    Check($child["status"] == "EXITED" And $child["exit_code"] = 0, "client ended naturally")
    _MP_Release($child)
    If $mode == "--lease" Then
        Check(_CG_Acquire($gate) == "HELD", "confirmed exit permits lease")
        Check(_CG_SetReady($gate, False), "close before cleanup")
        Check(_CG_SetReady($gate, True) And _CG_Release($gate), "reopen for next fixture")
    Else
        Check(_CG_Acquire($gate) == "UNKNOWN" And $gate["poisoned"], "abandoned owner is not a cleanup permit")
        Check(Not _CG_Release($gate), "poisoned gate cannot reopen")
        Check(_CG_Acquire($gate) == "UNKNOWN", "abandonment is sticky")
    EndIf
Next
_CG_Close($gate)
Check($gate["handle"] = 0 And $gate["ready"] = 0, "gate handles released at end")
ConsoleWrite("Native CLI gate assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
