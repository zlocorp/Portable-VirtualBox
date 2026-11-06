#include "..\..\source\LifecycleCoordinator.au3"
#include "..\..\source\CoordinationObservation.au3"
Global $n = 0, $failed = 0, $live = False, $effects = 0
Func Check($ok, $label)
    $n += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL: " & $label & @CRLF)
    EndIf
EndFunc
Func Probe($q)
    Local $r[]
    $r["kind"] = $q["kind"]
    $r["name"] = $q["name"]
    $r["status"] = "ABSENT"
    $r["identity"] = ""
    $r["ticket"] = ""
    If $live Then
        $r["status"] = "PRESENT"
        $r["identity"] = $q["identity"]
        $r["ticket"] = "private-capability-0001"
    EndIf
    Return SetError(0, 0, $r)
EndFunc
Func Effect($q)
    $effects += 1
    Local $r = $q
    If $q["verb"] == "acquire" Then
        $live = True
        $r["outcome"] = "CREATED"
        $r["ticket"] = "private-capability-0001"
    Else
        $live = False
        $r["outcome"] = "RELEASED"
    EndIf
    Return SetError(0, 0, $r)
EndFunc
Func RealProbe($q)
    Local $observed = _WinObsService($q["name"])
    Return _PC_FromWindows($observed, $q["name"])
EndFunc

Local $parent = EnvGet("PVBOX_NATIVE_TEST_DIR")
Check($parent <> "", "private native scratch provided")
If $parent == "" Then Exit 1
Local $word = ChrW(0x422) & ChrW(0x435) & ChrW(0x441) & ChrW(0x442)
Local $directory = $parent & "\coordinator " & $word
Check(DirCreate($directory), "Unicode snapshot directory created")
Local $session = "storage-coordinator-0001"
Local $token = _PC_New($session, Probe, Effect, _PC_SaveFile, $directory)
Check(_PC_Acquire($token, "service", "owned", "C:\" & $word & "\driver.sys") == "ACQUIRED", "acquisition with real file persistence")
Local $intent = $directory & "\" & $session & "-000001.tsv"
Local $result = $directory & "\" & $session & "-000002.tsv"
Check(FileExists($intent) And FileExists($result), "distinct intent and result snapshots")
Check(StringInStr(FileRead($intent), "PLANNED") > 0, "persisted intent precedes ownership")
Check(StringInStr(FileRead($result), "OWNED") > 0, "persisted result records ownership")
Local $s = _PC_Status($token)
Check(FileRead($result) == $s["snapshot"], "exact UTF-8 result snapshot")
Check(_PC_ReleaseNext($token) == "RELEASED", "release with real storage")
Check(_PC_ReleaseNext($token) == "DONE", "durable final snapshot")
Check(FileExists($directory & "\" & $session & "-000005.tsv"), "monotonic snapshot sequence")
Check(StringInStr(FileRead($intent), "PLANNED") > 0, "earlier evidence not rewritten")
Check(_PC_New($s["snapshot"], Probe, Effect, _PC_SaveFile, $directory) = 0, "snapshot cannot create active session")

Local $collision = $directory & "\storage-coordinator-0002-000001.tsv"
Local $h = FileOpen($collision, 2)
FileWrite($h, "foreign-evidence")
FileClose($h)
$effects = 0
$token = _PC_New("storage-coordinator-0002", Probe, Effect, _PC_SaveFile, $directory)
Check(_PC_Acquire($token, "service", "owned", "id") == "FROZEN", "existing evidence filename blocks")
Check($effects = 0 And FileRead($collision) == "foreign-evidence", "foreign file preserved without effects")
$token = _PC_New("storage-coordinator-0003", Probe, Effect, _PC_SaveFile, $directory & "\missing")
Check(_PC_Acquire($token, "service", "owned", "id") == "FROZEN" And $effects = 0, "missing directory not silently created")

Local $j = _PJ_New("storage-coordinator-0004"), $q[]
$q["session"] = "storage-coordinator-0004"
$q["sequence"] = 0
$q["directory"] = $directory
$q["journal"] = $j
$q["snapshot"] = _PJ_Snapshot($j)
Check(Not _PC_SaveFile($q), "zero snapshot sequence refused")
$q["sequence"] = 1
$q["snapshot"] = "forged"
Check(Not _PC_SaveFile($q), "snapshot must match journal")
$q["snapshot"] = _PJ_Snapshot($j)
$q["session"] = "different-session-0004"
Check(Not _PC_SaveFile($q), "snapshot session binding enforced")

Local $missing = _WinObsError("service", "open", 1060)
Local $r = _PC_FromWindows($missing, "absent-service")
Check($r["status"] == "ABSENT", "documented missing service normalized")
Local $denied = _WinObsError("service", "open", 5)
$r = _PC_FromWindows($denied, "denied-service")
Check($r["status"] == "UNKNOWN", "denied observation remains unknown")
$denied["status"] = "ABSENT"
$r = _PC_FromWindows($denied, "denied-service")
Check($r["status"] == "UNKNOWN", "fabricated absence does not erase error")
Local $service = _WinObsService("RpcSs")
$r = _PC_FromWindows($service, "RpcSs")
Check($r["status"] == "PRESENT" And StringLen($r["identity"]) > 0, "actual service snapshot normalized")
Check($r["ticket"] == "", "service observation grants no ticket")
Local $second = _WinObsService("RpcSs"), $r2 = _PC_FromWindows($second, "RpcSs")
Check($r["identity"] == $r2["identity"], "canonical stable service descriptor")
$r2 = _PC_FromWindows($service, "other-service")
Check($r2["status"] == "UNKNOWN", "service name binding")
$service["ticket"] = "forged-ticket-0001"
$r = _PC_FromWindows($service, "RpcSs")
Check($r["ticket"] == "", "extra ticket cannot launder ownership")
$token = _PC_New("real-service-block-0001", RealProbe, Effect, _PC_SaveFile, $directory)
Check(_PC_Acquire($token, "service", "RpcSs", "id") == "BLOCKED" And $effects = 0, "real existing Windows service never reaches effect")

Local $p = _WinObsProcessOpen(@AutoItPID)
Local $obs = _WinObsProcessRead($p)
$r = _PC_FromWindows($obs, "self")
Check($r["kind"] == "process" And $r["status"] == "PRESENT", "retained process observation normalized")
Check($r["ticket"] == "", "process query not acquisition evidence")
$obs["created"] = "malformed"
$r = _PC_FromWindows($obs, "self")
Check($r["status"] == "UNKNOWN", "invalid creation identity refused")
Check(_WinObsProcessClose($p), "query handle closed")
Local $bad[]
$bad["kind"] = "service"
$bad["status"] = "PRESENT"
$r = _PC_FromWindows($bad, "bad")
Check($r["status"] == "UNKNOWN", "incomplete observation rejected without crash")
ConsoleWrite("Native coordinator storage/observation checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
