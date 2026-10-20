#include-once
#include "HostPreflight.au3"
#include "LauncherI18n.au3"
; Read-only Windows inventory. No secret paths, usernames or service accounts.

Func _PortableDiagnosticCollect()
    Local $os = _WinObsOS(), $installed = _WinObsInstallation()
    Local $services = _PortableCountExistingServices(), $processes = _PortableCountVirtualBoxProcesses()
    Local $report[]
    Local $s = _LI("diag.header") & @CRLF
    $s &= _LI("diag.windows") & _LI_Observation("os", $os["status"]) & @CRLF
    If $os["status"] == "PRESENT" Then
        $s &= _LI("diag.build") & $os["build"] & @CRLF
        $s &= _LI("diag.product_type") & _LI_ProductType($os["product_type"]) & @CRLF
    Else
        $s &= _LI("diag.build") & _LI("diag.unknown") & @CRLF
        $s &= _LI("diag.product_type") & _LI("diag.unknown") & @CRLF
    EndIf
    $s &= _LI("diag.arch") & @OSArch & @CRLF
    $s &= _LI("diag.installed") & _LI_Observation("installation", $installed["status"]) & @CRLF
    If $services < 0 Then
        $s &= _LI("diag.services_unknown") & @CRLF
    Else
        $s &= _LI("diag.services") & $services & @CRLF
    EndIf
    If $processes < 0 Then
        $s &= _LI("diag.processes_unknown") & @CRLF
    Else
        $s &= _LI("diag.processes") & $processes & @CRLF
    EndIf
    $s &= _LI("diag.runtime") & @CRLF
    $report["text"] = $s
    If Not ($os["status"] == "PRESENT") Or $installed["status"] == "UNKNOWN" Or $services < 0 Or $processes < 0 Then
        $report["exit_code"] = 4
    Else
        $report["exit_code"] = 0
    EndIf
    Return $report
EndFunc

Func _PortableDiagnosticWrite()
    Local $report = _PortableDiagnosticCollect()
    _LI_Write($report["text"])
    Return $report["exit_code"]
EndFunc
