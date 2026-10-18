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
Check(_PJ_Plan($j, "vboxsup", "identity-a", False) = 0, "casefold duplicate also refused after confirmation")
Local $b = _PJ_Plan($j, "VBoxSDS", "identity-b", False)
Check(_PJ_Confirm($j, $b, "identity-b", True), "second creation confirmed")
Check(_PJ_NextCleanup($j) = $b, "reverse acquisition order")
Check(Not _PJ_BeginCleanup($j, $a, "identity-a", $token), "out-of-order cleanup refused")
Check(Not _PJ_BeginCleanup($j, $b, "identity-b", "other-session-2026"), "foreign session refused")
Check(_PJ_BeginCleanup($j, $b, "identity-b", $token), "cleanup intent recorded")
Check(_PJ_Plan($j, "new-during-close", "id", False) = 0, "new acquisition refused after cleanup starts")
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
    Check($before == $snapshot, "snapshot readback exact")
    Check(Not _PJ_SaveNew($k, $path), "existing journal never overwritten")
    Check(FileRead($path) == $before, "failed write preserved original snapshot")
    Check(StringRight($before, 5) = "END" & @CRLF, "snapshot has complete footer")
EndIf
Check(Not IsArray(_PJ_New("invalid")), "invalid session token refused")

Local $bad = 0
Check(_PJ_NextCleanup($bad) = -1, "invalid journal cannot authorize cleanup")
Local $q = _PJ_New($token)
Check(_PJ_Plan($q, "resource" & @TAB & "injection", "id", False) = 0, "TSV name injection refused")
Check(_PJ_Plan($q, "resource", "id" & @LF & "injection", False) = 0, "TSV identity injection refused")
Local $c = _PJ_Plan($q, "resource", "id", False)
Check(Not _PJ_Confirm($q, $c, "other-id", True), "successful but replaced resource remains unowned")
Check(_PJ_NextCleanup($q) = -1, "identity mismatch blocks lifecycle")
Check(_PJ_Plan($q, "second", "id", False) = 0, "no acquisition after uncertain outcome")
Local $valid = _PJ_New($token)
Local $d = _PJ_Plan($valid, "resource", "id", False)
Check(_PJ_Confirm($valid, $d, "id", True), "recovery fixture owns resource")
Local $text = _PJ_Snapshot($valid)
Local $recovered = _PJ_InspectSnapshot($text)
Check(IsArray($recovered), "complete snapshot can be inspected")
Check(_PJ_NextCleanup($recovered) = -1, "disk snapshot never authorizes cleanup")
Check(Not _PJ_BeginCleanup($recovered, $d, "id", $token), "session token alone does not reactivate disk snapshot")
Check(Not IsArray(_PJ_InspectSnapshot(StringTrimRight($text, 1))), "truncated snapshot refused")
Check(Not IsArray(_PJ_InspectSnapshot(StringReplace($text, "OWNED", "FOREIGN"))), "unknown snapshot state refused")
Check(_PJ_BeginCleanup($valid, $d, "id", $token), "cleanup intent for failure case")
Check(Not _PJ_CompleteCleanup($valid, $d, False, False, False), "unknown cleanup result marked uncertain")
Check(_PJ_NextCleanup($valid) = -1, "uncertain cleanup is not retry permission")

Local $u = _PJ_New($token)
Local $word = ChrW(0x422) & ChrW(0x435) & ChrW(0x441) & ChrW(0x442)
Local $unicodeIdentity = "C:\" & $word & "\driver.sys"
Local $un = _PJ_Plan($u, "unicode-resource", $unicodeIdentity, False)
Check(_PJ_Confirm($u, $un, $unicodeIdentity, True), "Unicode identity preserved")
Local $unicodeSnapshot = _PJ_Snapshot($u)
If $folder <> "" Then
    Local $unicodePath = $folder & "\journal-" & $word & ".tsv"
    Check(_PJ_SaveNew($u, $unicodePath), "Unicode journal path supported")
    Check(FileRead($unicodePath) == $unicodeSnapshot, "UTF-8 snapshot round trip exact")
EndIf
Local $parsed = _PJ_InspectSnapshot($unicodeSnapshot)
Check(IsArray($parsed), "Unicode snapshot parse succeeds")
Check(Not _PJ_Confirm($parsed, 1, $unicodeIdentity, True), "recovery cannot confirm ownership")
Local $invalidCount = $u
$invalidCount[0][2] = 99
Check(_PJ_NextCleanup($invalidCount) = -1, "corrupt row count denies cleanup")
Local $invalidBoolean = _PJ_New($token)
Check(_PJ_Plan($invalidBoolean, "resource", "id", 0) = 0, "numeric false is not a verified absence")

ConsoleWrite("Native lifecycle checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
