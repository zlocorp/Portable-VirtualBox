#include "..\..\source\LifecycleJournal.au3"
Global $n = 0, $failed = 0
Func Check($condition, $label)
    $n += 1
    If Not $condition Then
        ConsoleWriteError("FAIL: " & $label & @CRLF)
        $failed += 1
    EndIf
EndFunc
Local $token = "test-session-20261018"
Local $j = _PJ_New($token)
Check(IsArray($j), "journal created")
Check(_PJ_Plan($j, "existing", "image-a", True) = 0, "pre-existing resource refused")
Check(_PJ_Plan($j, "unknown", "image-a", False, False) = 0, "unknown initial probe refused")
Local $a = _PJ_Plan($j, "VBoxSUP", "identity-a", False)
Check($a = 1, "first intent recorded")
Check(_PJ_NextCleanup($j) = -1, "unconfirmed creation blocks cleanup")
Check(_PJ_Plan($j, "vboxsup", "identity-a", False) = 0, "casefold duplicate refused")
Check(_PJ_Confirm($j, $a, "identity-a", True), "successful creation becomes owned")
Check(_PJ_NextCleanup($j) = $a, "owned creation eligible")
Local $b = _PJ_Plan($j, "VBoxSDS", "identity-b", False)
Check(_PJ_Confirm($j, $b, "identity-b", True), "second creation confirmed")
Check(_PJ_NextCleanup($j) = $b, "reverse acquisition order")
Check(Not _PJ_BeginCleanup($j, $a, "identity-a", $token), "out-of-order cleanup refused")
Check(Not _PJ_BeginCleanup($j, $b, "identity-b", "other-session-2026"), "foreign session refused")
Check(_PJ_BeginCleanup($j, $b, "identity-b", $token), "cleanup intent recorded")
Check(_PJ_NextCleanup($j) = -1, "in-flight release blocks concurrent cleanup")
Check(_PJ_CompleteCleanup($j, $b, False, False), "known failure recorded without false success")
Check(_PJ_NextCleanup($j) = $b, "failed release can be retried")
Check(_PJ_BeginCleanup($j, $b, "identity-b", $token), "retry allowed")
Check(_PJ_CompleteCleanup($j, $b, True, True), "verified release complete")
Check(_PJ_NextCleanup($j) = $a, "previous resource next")
Check(Not _PJ_BeginCleanup($j, $a, "replaced-resource", $token), "identity change refused")
Check(_PJ_NextCleanup($j) = -1, "changed resource becomes uncertain")
Local $k = _PJ_New($token)
Local $x = _PJ_Plan($k, "failed", "identity", False)
Check(_PJ_Confirm($k, $x, "", False), "failed acquisition recorded")
Check(_PJ_NextCleanup($k) = 0, "failed acquisition never released")
Local $y = _PJ_Plan($k, "interrupted", "identity", False)
Check(Not _PJ_Confirm($k, $y, "", False, False), "unknown operation outcome")
Check(_PJ_NextCleanup($k) = -1, "unknown outcome blocks cleanup")
Local $folder = EnvGet("PVBOX_NATIVE_TEST_DIR")
Check($folder <> "", "test has private scratch directory")
If $folder <> "" Then
    Local $snapshot = _PJ_Snapshot($j)
    Local $path = $folder & "\journal.tsv"
    Check(_PJ_SaveNew($j, $path), "exclusive journal snapshot written")
    Local $before = FileRead($path)
    Check($before = $snapshot, "snapshot readback exact")
    Check(Not _PJ_SaveNew($k, $path), "existing journal never overwritten")
    Check(FileRead($path) = $before, "failed write preserved original snapshot")
    Check(StringRight($before, 5) = "END" & @CRLF, "snapshot has complete footer")
EndIf
Check(Not IsArray(_PJ_New("invalid")), "invalid session token refused")
ConsoleWrite("Native lifecycle checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
