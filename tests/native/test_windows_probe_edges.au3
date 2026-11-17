#include "..\..\source\WindowsObservation.au3"
#include "..\..\source\HostPreflight.au3"
If $CmdLine[0] = 1 And $CmdLine[1] == "--child" Then
    Sleep(1200)
    Exit 0
EndIf
Global $n = 0, $failed = 0
Func Check($condition, $label)
    $n += 1
    If Not $condition Then
        ConsoleWriteError("FAIL: " & $label & @CRLF)
        $failed += 1
    EndIf
EndFunc
Local $r = _WinObsProcessFromHandle(Ptr(0))
Check($r["status"] == "UNKNOWN" And $r["error"] = 6, "real invalid process handle error preserved")
$r = _WinObsServiceRead(Ptr(0), "RpcSs")
Check($r["status"] == "UNKNOWN" And $r["error"] = 6, "real invalid service handle error preserved")
Check(_WinObsProcessOpen(String(@AutoItPID)) = 0, "PID strings not coerced")
Check(_WinObsProcessOpen(4294967296) = 0, "PID overflow not truncated")
Local $token = _WinObsProcessOpen(Number(@AutoItPID, 3))
Check($token > 0, "integral Double PID accepted without truncating fractions")
Check(_WinObsProcessClose($token), "normalized PID handle closed")
Check(StringInStr(_PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, -1, 0), "service state is unknown") > 0, "service uncertainty reason preserved")
Check(StringInStr(_PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, 0, -1), "process state is unknown") > 0, "process uncertainty reason preserved")
Check(_PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, 0, 0, 3) <> "", "Server 2025 cannot masquerade as Windows 11")

Local $buffer = DllStructCreate("wchar[8]")
DllStructSetData($buffer, 1, "Тест")
Local $s = _WinObsBufferString($buffer, DllStructGetPtr($buffer))
Check(Not @error And $s == "Тест", "bounded UTF-16 service string")
$s = _WinObsBufferString($buffer, Ptr(Number(DllStructGetPtr($buffer)) + 1))
Check(@error <> 0, "unaligned pointer rejected")
$s = _WinObsBufferString($buffer, Ptr(Number(DllStructGetPtr($buffer)) + DllStructGetSize($buffer)))
Check(@error <> 0, "past-end pointer rejected")
Local $unterminated = DllStructCreate("ushort[3]")
For $i = 1 To 3
    DllStructSetData($unterminated, 1, 65, $i)
Next
$s = _WinObsBufferString($unterminated, DllStructGetPtr($unterminated))
Check(@error <> 0, "unterminated string rejected")

; Work exclusively in a private temporary directory supplied by the test runner.
Local $root = EnvGet("PVBOX_NATIVE_TEST_DIR")
Check($root <> "" And FileExists($root), "private test directory available")
If $root <> "" And FileExists($root) Then
    Local $dir = $root & "\Процесс с пробелами"
    Check(DirCreate($dir), "Unicode process fixture directory")
    Local $exe = $dir & "Тест процесса.exe"
    Check(FileCopy(@ScriptFullPath, $exe, 0), "private executable copy created")
    Local $pid = Run('"' & $exe & '" --child', $dir, @SW_HIDE)
    $token = _WinObsProcessOpen($pid)
    Check($token > 0, "Unicode-named child query handle")
    $r = _WinObsProcessRead($token)
    Check($r["status"] == "PRESENT" And StringLower($r["image"]) == StringLower($exe), "Unicode executable identity preserved")
    Check(_WinObsProcessClose($token), "Unicode child query handle closed")
    Check(ProcessWaitClose($pid, 5), "test child exits naturally without termination")
EndIf
ConsoleWrite("Native Windows edge checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
