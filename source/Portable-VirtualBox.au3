; Portable-VirtualBox development preview, based on vboxme snapshot 5b58dbbe.
; Upstream author: Michael Meyer (michaelm_007) and contributors.
; Preserve upstream license: CC BY-NC-SA 3.0; see ../LICENSE.md.
; Normal user GUI/CLI cannot install drivers or start VMs. A separate,
; explicitly gated CI-only test mode DOES run a disposable empty VM; it is
; compiled for research but is not an approved end-user startup feature.

; BEGIN MODERNIZATION DEVELOPMENT SAFETY GATE (remove only after runtime acceptance)
; Historical runtime is archived in legacy/Portable-VirtualBox.au3.disabled, not compiled.
; This experimental branch may be compiled and run with --version, --diagnose,
; or --selftest without administrator privileges or any service changes.
#include "RuntimeSafety.au3"
#include "HostPreflight.au3"
#include "HostDiagnostics.au3"
#include "LauncherI18n.au3"
#include "LauncherGui.au3"
#include "PortableDataBackup.au3"
#include "PortableVmInventory.au3"
#include "PortableProfile.au3"
#include "LauncherSettings.au3"
#include "PortableApp.au3"
#include "PortableAppSetup.au3"
#include "LauncherAbout.au3"
#include "PortableCISession.au3"
#include "PortableCIVM.au3"
#include "PortableCIIntegrated.au3"
#NoTrayIcon

; Saved launcher language overrides the host; --lang overrides this invocation
; only. Reads never create files. Explicit save touches only data/launcher.ini.
Local $savedLanguage = _LS_Load(@ScriptDir)
_LI_Set(_LS_Select($savedLanguage["language"], @OSLang))
Local $iFirst = 1
If $CmdLine[0] > 0 Then
    If StringLeft($CmdLine[1], 7) == "--lang=" Then
        If Not _LI_Set(StringTrimLeft($CmdLine[1], 7)) Then
            _LI_Write(_LI("error.invalid_lang") & @CRLF, True)
            Exit 64
        EndIf
        $iFirst = 2
    ElseIf $CmdLine[1] == "--lang" Then
        If $CmdLine[0] < 2 Then
            _LI_Write(_LI("error.invalid_lang") & @CRLF)
            Exit 64
        EndIf
        If Not _LI_Set($CmdLine[2]) Then
            _LI_Write(_LI("error.invalid_lang") & @CRLF)
            Exit 64
        EndIf
        $iFirst = 3
    EndIf
EndIf

If $CmdLine[0] >= $iFirst Then
    Switch $CmdLine[$iFirst]
        Case "--help", "-h"
            _LI_Write(_LI("help.title") & @CRLF & _LI("help.commands") & @CRLF & _
                "  --version  --diagnose  --preflight  --selftest  --profile-status  --prepare-profile  --prepare-app64 OFFICIAL_INSTALLER  --download-app64  --app-status  --check-readiness  --save-language ru|en|auto  --backup-data PATH  --verify-backup PATH  --restore-backup SOURCE NEW_DEST  --audit-vms  --about  --help" & @CRLF & _
                _LI("help.language") & @CRLF & _LI("help.warning") & @CRLF)
            Exit 0
        Case "--ci-service-smoke"
            ; Explicitly gated disposable-host experiment only: not in help/GUI.
            Exit _PVS_Execute(@ScriptDir)
        Case "--ci-vm-session"
            ; Genuine VM boot from compiled native AutoIt; disposable runner only.
            ; NOT exposed through the user GUI or regular CLI help.
            Exit _PCVM_Execute(@ScriptDir)
        Case "--ci-integrated-session"
            ; Only a disposable CI runner may drive privileged experiments.
            Exit _PCI_Execute(@ScriptDir)
        Case "--save-language"
            If $CmdLine[0] <> $iFirst + 1 Then
                _LI_Write(_LI("settings.invalid") & @CRLF, True)
                Exit 64
            EndIf
            If Not _LS_Valid($CmdLine[$iFirst + 1]) Then
                _LI_Write(_LI("settings.invalid") & @CRLF, True)
                Exit 64
            EndIf
            If Not _LS_Save(@ScriptDir, $CmdLine[$iFirst + 1]) Then
                _LI_Write(_LI("settings.save_failed") & @CRLF, True)
                Exit 3
            EndIf
            _LI_Set(_LS_Select($CmdLine[$iFirst + 1], @OSLang))
            _LI_Write(_LI("settings.saved") & $CmdLine[$iFirst + 1] & @CRLF)
            Exit 0
        Case "--restore-backup"
            If $CmdLine[0] <> $iFirst + 2 Then
                _LI_Write(_LI("backup.syntax") & @CRLF, True)
                Exit 64
            EndIf
            Local $restored = _PBK_Restore($CmdLine[$iFirst + 1], $CmdLine[$iFirst + 2])
            If $restored = 0 Then
                _LI_Write(_LI("backup.restored") & " " & $CmdLine[$iFirst + 2] & @CRLF)
                Exit 0
            EndIf
            If $restored = 2 Then
                _LI_Write(_LI("backup.blocked") & @CRLF, True)
                Exit 2
            EndIf
            _LI_Write(_LI("backup.failed") & " " & $CmdLine[$iFirst + 2] & ".pending" & @CRLF, True)
            Exit 3
        Case "--backup-data", "--verify-backup"
            If $CmdLine[0] <> $iFirst + 1 Then
                _LI_Write(_LI("backup.syntax") & @CRLF, True)
                Exit 64
            EndIf
            Local $backupPath = $CmdLine[$iFirst + 1]
            If $CmdLine[$iFirst] == "--verify-backup" Then
                If _PBK_Verify($backupPath) Then
                    _LI_Write(_LI("backup.verified") & " " & $backupPath & @CRLF)
                    Exit 0
                EndIf
                _LI_Write(_LI("backup.invalid") & " " & $backupPath & @CRLF, True)
                Exit 3
            EndIf
            Local $risk = _PVI_Inspect(@ScriptDir)
            If $risk["status"] == "REVIEW" Or $risk["status"] == "BLOCKED" Then _LI_Write(_LI("vm.backup_warning") & @CRLF, True)
            Local $backupResult = _PBK_Create(@ScriptDir, $backupPath)
            Switch $backupResult
                Case 0
                    _LI_Write(_LI("backup.verified") & " " & $backupPath & @CRLF)
                    Exit 0
                Case 2
                    _LI_Write(_LI("backup.blocked") & @CRLF, True)
                    Exit 2
                Case Else
                    _LI_Write(_LI("backup.failed") & " " & $backupPath & ".pending" & @CRLF, True)
                    Exit 3
            EndSwitch
        Case "--audit-vms"
            If $CmdLine[0] <> $iFirst Then Exit 64
            Local $audit = _PVI_Inspect(@ScriptDir)
            _LI_Write($audit["report"])
            Switch $audit["status"]
                Case "CLEAN"
                    Exit 0
                Case "EMPTY", "REVIEW"
                    Exit 2
                Case Else
                    Exit 3
            EndSwitch
        Case "--download-app64"
            If $CmdLine[0] <> $iFirst Then Exit 64
            Local $downloaded = _PAS_RunDownload(@ScriptDir)
            If $downloaded = 0 Then
                _LI_Write(_LI("setup.done") & @CRLF)
                Exit 0
            EndIf
            If $downloaded = 2 Then
                _LI_Write(_LI("setup.blocked") & @CRLF, True)
                Exit 2
            EndIf
            _LI_Write(_LI("setup.failed") & @CRLF, True)
            Exit 3
        Case "--prepare-app64"
            If $CmdLine[0] <> $iFirst + 1 Then Exit 64
            Local $prepared = _PAS_Run(@ScriptDir, $CmdLine[$iFirst + 1])
            If $prepared = 0 Then
                _LI_Write(_LI("setup.done") & @CRLF)
                Exit 0
            EndIf
            If $prepared = 2 Then
                _LI_Write(_LI("setup.blocked") & @CRLF, True)
                Exit 2
            EndIf
            _LI_Write(_LI("setup.failed") & @CRLF, True)
            Exit 3
        Case "--app-status"
            Local $app = _PA_Inspect(@ScriptDir)
            _LI_Write(_PA_Message($app) & @CRLF)
            If $app["status"] == "PRESENT" Then Exit 0
            If $app["status"] == "MISSING" Then Exit 2
            Exit 3
        Case "--check-readiness"
            Local $ready = _LR_Inspect(@ScriptDir)
            _LI_Write($ready["message"] & @CRLF)
            If $ready["status"] == "RESEARCH_ONLY" Then Exit 2
            Exit 3
        Case "--about"
            _LI_Write(_LA_Text() & @CRLF)
            Exit 0
        Case "--profile-status"
            Local $profile = _PP_Inspect(@ScriptDir)
            Switch $profile["status"]
                Case "READY"
                    _LI_Write(_LI("profile.ready") & @CRLF)
                    If Not $profile["app_present"] Then _LI_Write(_LI("profile.appmissing") & @CRLF)
                    Exit 0
                Case "MISSING"
                    _LI_Write(_LI("profile.missing") & @CRLF)
                    Exit 2
                Case Else
                    _LI_Write(_LI("profile.blocked") & @CRLF, True)
                    Exit 3
            EndSwitch
        Case "--prepare-profile"
            Local $profile = _PP_Ensure(@ScriptDir)
            If $profile["status"] <> "READY" Then
                _LI_Write(_LI("profile.blocked") & @CRLF, True)
                Exit 3
            EndIf
            _LI_Write(_LI("profile.ready") & @CRLF)
            If Not $profile["app_present"] Then _LI_Write(_LI("profile.appmissing") & @CRLF)
            Exit 0
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
                _LI_Write(_LI("preflight.blocked") & _LI_Blocker($sBlocker) & @CRLF)
                Exit 3
            EndIf
            _LI_Write(_LI("preflight.ok") & @CRLF)
            Exit 0
        Case "--diagnose"
            Exit _PortableDiagnosticWrite()
        Case Else
            _LI_Write(_LI("error.unknown") & @CRLF, True)
            Exit 64
    EndSwitch
EndIf
_LG_Show()
Exit 2
; END DEVELOPMENT SAFETY GATE
