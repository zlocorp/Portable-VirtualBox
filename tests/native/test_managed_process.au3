#include "..\..\source\ManagedProcess.au3"
#include <GUIConstantsEx.au3>
If $CmdLine[0] = 1 And $CmdLine[1] == "--child" Then
    Local $gui = GUICreate("Owned child " & @AutoItPID, 300, 110)
    GUISetState(@SW_SHOW, $gui)
    Local $limit = TimerInit()
    While TimerDiff($limit) < 8000
        If GUIGetMsg() = $GUI_EVENT_CLOSE Then ExitLoop
        Sleep(20)
    WEnd
    GUIDelete($gui)
    Exit 0
EndIf
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL managed process: " & $label & @CRLF)
    EndIf
EndFunc
Local $original = EnvGet("VBOX_USER_HOME")
EnvSet("VBOX_USER_HOME", "unchanged-parent")
Local $a = _MP_Start(@ScriptFullPath, "--child", @ScriptDir, @TempDir, True)
Local $b = _MP_Start(@ScriptFullPath, "--child", @ScriptDir, @TempDir, True)
Check($a["status"] == "STARTED" And $b["status"] == "STARTED", "two native children")
Check(EnvGet("VBOX_USER_HOME") == "unchanged-parent", "parent environment restored")
Local $t = TimerInit()
While TimerDiff($t) < 2500 And _MP_Window($a) = 0
    Sleep(30)
WEnd
Check(_MP_Window($a) <> 0, "actual child window belongs to retained process")
Check(_MP_Poll($a) == "PRESENT", "exact handle live")
Check(_MP_RequestClose($a), "graceful WM_CLOSE request")
$t = TimerInit()
While TimerDiff($t) < 2500 And _MP_Poll($a) <> "EXITED"
    Sleep(30)
WEnd
Check(_MP_Poll($a) == "EXITED" And $a["exit_code"] = 0, "first child cleanly exited")
Check(_MP_Poll($b) == "PRESENT", "same-name second child untouched")
Check(_MP_Release($a), "close exact handle")
Check(Not _MP_RequestClose($a), "released handle cannot address process")
Check(_MP_RequestClose($b), "close second own child explicitly")
$t = TimerInit()
While TimerDiff($t) < 2500 And _MP_Poll($b) <> "EXITED"
    Sleep(30)
WEnd
Check(_MP_Poll($b) == "EXITED", "second child cleanly exited")
Check(_MP_Release($b), "release second handle")
If $original == "" Then
    EnvSet("VBOX_USER_HOME")
Else
    EnvSet("VBOX_USER_HOME", $original)
EndIf
ConsoleWrite("Native owned-process assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
