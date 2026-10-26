#include "..\..\source\WindowsObservation.au3"
#include "..\..\source\RuntimeSafety.au3"
#include "..\..\source\HostPreflight.au3"
; The only process started by this harness is another copy that exits naturally.
If $CmdLine[0] = 1 And $CmdLine[1] = "--child" Then
    Sleep(1500)
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
Func Handles()
    Local $a = DllCall("kernel32.dll", "bool", "GetProcessHandleCount", "handle", -1, "dword*", 0)
    If @error Or Not $a[0] Then Return -1
    Return $a[2]
EndFunc

Check(_WinObsFailure("service", "open", 1060) == "ABSENT", "only missing service is absent")
Check(_WinObsFailure("service", "manager", 1060) == "UNKNOWN", "SCM failure is not service absence")
Check(_WinObsFailure("service", "open", 5) == "UNKNOWN", "access denied is unknown")
Check(_WinObsFailure("service", "query", 1060) == "UNKNOWN", "query failure is not absence")
Check(_WinObsFailure("installation", "open", 2) == "ABSENT", "missing install key is absent")
Check(_WinObsFailure("installation", "open", 3) == "ABSENT", "missing install path is absent")
Check(_WinObsFailure("installation", "open", 5) == "UNKNOWN", "denied install key is unknown")
Check(_WinObsFailure("process", "open", 87) == "UNKNOWN", "invalid PID is not proof of absence")
Check(_WinObsFailure("process", "read", 6) == "UNKNOWN", "invalid handle is unknown")
Check(Not _WinObsWorkstationAccepted(26100, 3), "new Server build is not Windows 11")
Check(_WinObsWorkstationAccepted(26100, 1), "workstation Windows 11 accepted")
Check(_WinObsWorkstationAccepted(19045, 1), "Windows 10 22H2 workstation supported")
Check(_WinObsWorkstationAccepted(19041, 1), "conservative Windows 10 minimum included")
Check(Not _WinObsWorkstationAccepted(18363, 1), "older Windows 10 build blocked")
Check(Not _WinObsWorkstationAccepted(20348, 3), "Windows Server 2022 remains blocked")
Check(Not _WinObsWorkstationAccepted(26100, 0), "unknown product type blocked")
Check(_PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, -1, 0) <> "", "unknown service count blocks")
Check(_PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, 0, -1) <> "", "unknown process count blocks")
Check(_PortablePreflightBlocker(26100, "X64", True, "7.2.20", "", 0, 0) <> "", "unknown installation blocks")

Local $missing = _WinObsService("PVBoxNoSuchService_" & @AutoItPID & "_" & @MSEC)
Check($missing["status"] == "ABSENT", "real missing service classified")
Check($missing["error"] = 1060, "missing service keeps Win32 error")
Local $bad = _WinObsService("invalid/service")
Check($bad["status"] == "UNKNOWN", "invalid service name blocked")
Local $svc = _WinObsService("RpcSs"), $svc2 = _WinObsService("RpcSs")
Check($svc["status"] == "PRESENT", "real built-in service is readable")
Check($svc["image"] <> "", "service configuration image captured")
Check($svc["state"] = 4, "RPC service is running")
Check(_WinObsServiceStable($svc, $svc2), "stable read-only service identity")
Local $changed = $svc
$changed["image"] = "C:\different.exe"
Check(Not _WinObsServiceStable($svc, $changed), "changed service image rejected")
$changed = $svc
$changed["state"] = 2
Check(Not _WinObsServiceStable($svc, $changed), "pending service is not stable")
$changed = $svc
$changed["status"] = "UNKNOWN"
Check(Not _WinObsServiceStable($svc, $changed), "unknown service never stable")

Local $startHandles = Handles()
Local $token = _WinObsProcessOpen(@AutoItPID)
Check($token > 0, "query-only self handle retained")
Local $self = _WinObsProcessRead($token)
Check($self["status"] == "PRESENT", "self process present")
Check($self["pid"] = @AutoItPID, "same handle reports PID")
Check(StringRegExp($self["created"], "^[0-9A-F]{16}$") = 1, "FILETIME exact hex identity")
Check(StringLower($self["image"]) == StringLower(@ScriptFullPath), "same handle reports image")
Check(_WinObsProcessMatches($token, $self), "retained handle matches original observation")
Local $other = $self
$other["created"] = "0000000000000000"
Check(Not _WinObsProcessMatches($token, $other), "changed creation time rejected")
$other = $self
$other["image"] = "C:\wrong.exe"
Check(Not _WinObsProcessMatches($token, $other), "changed image rejected")
Check(_WinObsProcessClose($token), "own query handle closed")
Check(Not _WinObsProcessClose($token), "double close does not close another handle")
$self = _WinObsProcessRead($token)
Check($self["status"] == "UNKNOWN", "closed token is not reopened by PID")
Check(Not _WinObsProcessMatches($token, $other), "closed token never matches")
Check(_WinObsProcessOpen(0) = 0, "zero PID refused")
Check(_WinObsProcessOpen(-1) = 0, "negative PID refused")
Check(_WinObsProcessOpen(1.5) = 0, "fractional PID refused")
For $i = 1 To 25
    $token = _WinObsProcessOpen(@AutoItPID)
    Check($token > 0 And _WinObsProcessClose($token), "bounded handle iteration " & $i)
Next
Check(Handles() = $startHandles, "query handles do not leak")

Local $pid = Run('"' & @ScriptFullPath & '" --child', @ScriptDir, @SW_HIDE)
Check($pid > 0, "test-owned child started")
$token = _WinObsProcessOpen($pid)
Check($token > 0, "child retained before exit")
$self = _WinObsProcessRead($token)
Check($self["status"] == "PRESENT", "child initially present")
Local $timer = TimerInit(), $final = $self
While TimerDiff($timer) < 5000
    $final = _WinObsProcessRead($token)
    If $final["status"] == "EXITED" Then ExitLoop
    Sleep(50)
WEnd
Check($final["status"] == "EXITED", "natural child exit detected via same handle")
Check(Not _WinObsProcessMatches($token, $self), "exited process never matches live identity")
Check(_WinObsProcessClose($token), "exited process query handle closed")

Local $os = _WinObsOS()
Check($os["status"] == "PRESENT", "native OS version readable")
Check($os["build"] >= 20348, "native build captured")
Check($os["product_type"] >= 1 And $os["product_type"] <= 3, "native workstation/server type captured")
Local $installed = _WinObsInstallation()
Check($installed["status"] == "ABSENT", "hosted test has no Oracle installation")
ConsoleWrite("Native Windows observation checks: " & $n & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
