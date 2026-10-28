#include "..\..\source\PortableCommand.au3"
Global $n = 0, $failed = 0
Func Check($ok, $label)
    $n += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $label & @CRLF)
    EndIf
EndFunc

If $CmdLine[0] > 0 Then
    Switch $CmdLine[1]
        Case "--child-success"
            Sleep(150)
            ConsoleWrite("PRIVATE_CHILD_OK" & @CRLF)
            Exit 0
        Case "--child-error"
            Sleep(150)
            ConsoleWriteError("PRIVATE_CHILD_ERROR" & @CRLF)
            Exit 17
        Case "--child-slow"
            Sleep(900)
            Exit 0
    EndSwitch
EndIf
Local $folder = @TempDir & "\Portable Command Тест " & @AutoItPID
Check(DirCreate($folder), "private Unicode child directory")
Local $child = $folder & "\child Тест.exe"
Check(FileCopy(@ScriptFullPath, $child, 0) = 1, "copy current compiled harmless worker")
Local $ok = _PXR_Run($child, "--child-success", $folder, 4000)
Check($ok["status"] == "EXITED" And $ok["exit_code"] = 0, "native child exit zero")
Check(StringInStr($ok["output"], "PRIVATE_CHILD_OK") > 0, "native stdout captured")
Check($ok["pid"] > 0, "native run tracks concrete PID")
Local $bad = _PXR_Run($child, "--child-error", $folder, 4000)
Check($bad["status"] == "EXITED" And $bad["exit_code"] = 17, "nonzero exit preserved")
Check(StringInStr($bad["error_output"], "PRIVATE_CHILD_ERROR") > 0, "stderr captured")
Local $slow = _PXR_Run($child, "--child-slow", $folder, 80)
Check($slow["status"] == "TIMEOUT", "bounded wait never reports timeout as success")
If $slow["pid"] > 0 Then Check(ProcessWaitClose($slow["pid"], 4) = 1, "timeout child exits naturally")
Local $missing = _PXR_Run($folder & "\not-there.exe", "", $folder, 3000)
Check($missing["status"] <> "EXITED", "missing command refused")
Check($missing["pid"] = 0, "missing command never grants PID")
Check(Not FileExists($folder & "\unexpected.txt"), "no unrelated writes")
DirRemove($folder, 1)
ConsoleWrite("Native portable command checks: " & $n & "; failed: " & $failed & @CRLF)
Exit($failed > 0)
