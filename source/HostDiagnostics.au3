#include-once
#include "HostPreflight.au3"
; Only status/counts: never expose image paths, usernames or service accounts.
Func _PortableDiagnosticWrite()
    Local $os = _WinObsOS(), $installed = _WinObsInstallation()
    Local $services = _PortableCountExistingServices(), $processes = _PortableCountVirtualBoxProcesses()
    ConsoleWrite("Portable-VirtualBox: read-only diagnostics" & @CRLF)
    ConsoleWrite("Windows observation: " & $os["status"] & @CRLF)
    ConsoleWrite("Windows build: " & $os["build"] & @CRLF)
    ConsoleWrite("Windows product type: " & $os["product_type"] & @CRLF)
    ConsoleWrite("OS architecture: " & @OSArch & @CRLF)
    ConsoleWrite("Installed VirtualBox: " & $installed["status"] & @CRLF)
    If $services < 0 Then
        ConsoleWrite("VBox services: UNKNOWN" & @CRLF)
    Else
        ConsoleWrite("VBox services count: " & $services & @CRLF)
    EndIf
    If $processes < 0 Then
        ConsoleWrite("VBox processes: UNKNOWN" & @CRLF)
    Else
        ConsoleWrite("VBox processes count: " & $processes & @CRLF)
    EndIf
    ConsoleWrite("Runtime status: DISABLED" & @CRLF)
    If Not ($os["status"] == "PRESENT") Or $installed["status"] == "UNKNOWN" Or $services < 0 Or $processes < 0 Then Return 4
    Return 0
EndFunc
