#include "..\..\source\ManagerSession.au3"
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL manager policy: " & $label & @CRLF)
    EndIf
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
Local $s = _MS_New("C:\not-a-runner\root", "C:\workspace")
Check(Not _MS_Start($s), "local directory cannot start privileged experiment")
Check($s["state"] == "BLOCKED", "refusal surfaced")
Check(Not _MS_Stop($s), "no stop without owned session")
Check(Not _MS_Reopen($s), "no reopen without owned session")
ConsoleWrite("Native Manager session assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
