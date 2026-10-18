; Portable-VirtualBox development preview, based on vboxme snapshot 5b58dbbe.
; Upstream author: Michael Meyer (michaelm_007) and contributors.
; Preserve upstream license: CC BY-NC-SA 3.0; see ../LICENSE.md.
; No service, driver, installer, updater or VM mutation is compiled into this entrypoint.

; BEGIN MODERNIZATION DEVELOPMENT SAFETY GATE (remove only after runtime acceptance)
; Historical runtime is archived in legacy/Portable-VirtualBox.au3.disabled, not compiled.
; This experimental branch may be compiled and run with --version, --diagnose,
; or --selftest without administrator privileges or any service changes.
#include "RuntimeSafety.au3"
#include "HostPreflight.au3"
#NoTrayIcon

If $CmdLine[0] > 0 Then
    Switch $CmdLine[1]
        Case "--version"
            ConsoleWrite("Portable-VirtualBox development baseline 5b58dbbe" & @CRLF)
            Exit 0
        Case "--selftest"
            Local $iFailure = 0
            If Not _PortableSafeRelativePath("data\.VirtualBox") Then $iFailure += 1
            If _PortableSafeRelativePath("..\Windows") Then $iFailure += 1
            If _PortableSafeRelativePath("C:\Windows") Then $iFailure += 1
            If _PortableSafeRelativePath("\\server\share") Then $iFailure += 1
            If _PortableRelativeToRoot("C:\Portable VirtualBox", "data\VM") <> "C:\Portable VirtualBox\data\VM" Then $iFailure += 1
            If Not _PortableServiceOwned(True, False, "C:\Owned\driver.sys", "c:\owned\DRIVER.sys") Then $iFailure += 1
            If _PortableServiceOwned(True, True, "C:\Owned\driver.sys", "C:\Owned\driver.sys") Then $iFailure += 1
            If _PortableServiceOwned(False, False, "C:\Owned\driver.sys", "C:\Owned\driver.sys") Then $iFailure += 1
            If _PortableProcessOwned(300, 300) Then $iFailure += 1
            If _PortableProcessOwned(300, 301) Then $iFailure += 1
            If Not _PortableVersionFamilyAccepted("7.2.20") Then $iFailure += 1
            If _PortableVersionFamilyAccepted("7.0.20") Then $iFailure += 1
            If _PortableVersionFamilyAccepted("8.0.0") Then $iFailure += 1
            If _PortableVersionFamilyAccepted("7.3.0") Then $iFailure += 1
            If _PortableSafeRelativePath("CON") Then $iFailure += 1
            If _PortableSafeRelativePath("VM\AUX.txt") Then $iFailure += 1
            If _PortableSafeRelativePath("VM\bad. ") Then $iFailure += 1

            If _PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, 0, 0) <> "" Then $iFailure += 1
            If _PortablePreflightBlocker(26100, "X64", True, "7.2.20", True, 0, 0) = "" Then $iFailure += 1
            If _PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, 1, 0) = "" Then $iFailure += 1
            If _PortablePreflightBlocker(26100, "X64", True, "7.2.20", False, 0, 1) = "" Then $iFailure += 1
            If _PortablePreflightBlocker(20348, "X64", True, "7.2.20", False, 0, 0) = "" Then $iFailure += 1

            If $iFailure <> 0 Then
                ConsoleWriteError("Safety helper selftest FAIL: " & $iFailure & @CRLF)
                Exit 1
            EndIf
            ConsoleWrite("Safety helper selftest PASS" & @CRLF)
            Exit 0
        Case "--preflight"
            Local $sBlocker = _PortableReadOnlyPreflight()
            If $sBlocker <> "" Then
                ConsoleWrite("Preflight BLOCKED: " & $sBlocker & @CRLF)
                Exit 3
            EndIf
            ConsoleWrite("Preflight: no detected blocker (runtime still disabled)" & @CRLF)
            Exit 0
        Case "--diagnose"
            ConsoleWrite("Portable-VirtualBox: read-only diagnostics" & @CRLF)
            ConsoleWrite("OS: " & @OSVersion & @CRLF)
            ConsoleWrite("OS architecture: " & @OSArch & @CRLF)
            ConsoleWrite("Portable app64 VirtualBox.exe present: " & FileExists(@ScriptDir & "\app64\VirtualBox.exe") & @CRLF)
            Local $sInstalled = RegRead("HKLM64\SOFTWARE\Oracle\VirtualBox", "InstallDir")
            If @error Then
                ConsoleWrite("Installed VirtualBox path: not detected in HKLM64" & @CRLF)
            Else
                ConsoleWrite("Installed VirtualBox: detected (path withheld)" & @CRLF)
            EndIf
            ConsoleWrite("Runtime status: disabled pending service/driver safety validation" & @CRLF)
            Exit 0
        Case Else
            ConsoleWriteError("Unknown option: use --version, --diagnose, --preflight, --selftest" & @CRLF)
            Exit 64
    EndSwitch
EndIf
MsgBox(48, "Portable-VirtualBox development build", _
    "Runtime intentionally disabled during modernization." & @CRLF & _
    "This build does not install drivers or start virtual machines." & @CRLF & _
    "Use --diagnose for a read-only report.")
Exit 2
; END DEVELOPMENT SAFETY GATE
