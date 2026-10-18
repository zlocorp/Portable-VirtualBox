#include "..\..\source\RuntimeSafety.au3"
Global $n = 0, $failed = 0
Func Check($condition, $label)
    $n += 1
    If Not $condition Then
        ConsoleWriteError("FAIL: " & $label & @CRLF)
        $failed += 1
    EndIf
EndFunc
Check(Not _PortableProcessOwned(42, 42), "PID equality alone is not ownership")
Check(Not _PortableProcessOwned(42, 43), "different PID denied")
Check(Not _PortableProcessOwned(0, 0), "zero PID denied")
Check(Not _PortableSafeRelativePath("..\Windows"), "traversal denied")
Check(Not _PortableSafeRelativePath("CON.txt"), "device name denied")
Check(_PortableSafeRelativePath("Machines\Test VM\machine.vbox"), "relative VM path accepted")
ConsoleWrite("Native runtime checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
