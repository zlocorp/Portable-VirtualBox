#include "..\..\source\PortableProfile.au3"
Global $n = 0, $failed = 0
Func Check($b, $name)
    $n += 1
    If Not $b Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $name & @CRLF)
    EndIf
EndFunc
Local $root = @TempDir & "\Portable Profile Test Тест " & @AutoItPID
Local $external = $root & "-sentinel.txt"
Check(Not _PP_RootSafe("relative\root"), "relative rejected")
Check(Not _PP_RootSafe("\\server\share"), "UNC rejected")
Check(Not _PP_RootSafe("C:\folder\..\Windows"), "dot-dot rejected")
Check(Not _PP_RootSafe("C:\CON"), "device path rejected")
Check(Not _PP_RootSafe("C:\Temp\bad. "), "trailing dot/space rejected")
Check(_PP_RootSafe("C:\Portable VirtualBox Тест"), "spaces Cyrillic accepted")
Check(_PP_RootSafe("C:\"), "drive root is syntactically valid")
Check(DirCreate($root), "create private fixture root")
Local $plan = _PP_Inspect($root)
Check($plan["status"] == "MISSING", "read-only inspect does not create")
Check(Not FileExists($root & "\data"), "inspect has no effects")
Local $result = _PP_Ensure($root)
Check($result["status"] == "READY", "first-run prepares profile")
Check(FileExists($root & "\data\.VirtualBox"), "global profile inside root")
Check(FileExists($root & "\data\Machines"), "portable machines inside root")
Check(FileExists($root & "\logs"), "private logs inside root")
Check(Not FileExists($root & "\app64"), "initialization does not fake Oracle binaries")
Check($result["app_present"] == False, "app64 absence reported")
Local $sentinel = $root & "\data\.VirtualBox\preserve.ini"
Local $h = FileOpen($sentinel, 2)
FileWrite($h, "keep-me")
FileClose($h)
$result = _PP_Ensure($root)
Check($result["status"] == "READY", "repeat initialization idempotent")
Check(FileRead($sentinel) == "keep-me", "no existing data overwrite")
Local $ready = _PP_Inspect($root)
Check($ready["status"] == "READY", "read-only inspect READY")
Local $root2 = @TempDir & "\Profile Collision " & @AutoItPID
Check(DirCreate($root2), "create collision root")
Local $h2 = FileOpen($root2 & "\data", 2)
FileWrite($h2, "foreign-file")
FileClose($h2)
$result = _PP_Ensure($root2)
Check($result["status"] == "BLOCKED", "existing data file blocks")
Check(FileRead($root2 & "\data") == "foreign-file", "existing unrelated file never overwritten")
Check(Not FileExists($root2 & "\logs"), "validation prevents partial mutation")
Check(Not _PP_RootSafe("C:\VirtualBox" & Chr(1)), "control character rejected")
Check(Not FileExists($external), "no write outside root")
DirRemove($root, 1)
DirRemove($root2, 1)
ConsoleWrite("Native portable profile checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
