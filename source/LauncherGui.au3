#include-once
#include "LauncherI18n.au3"
#include "HostDiagnostics.au3"
#include "PortableProfile.au3"
#include "LauncherReadiness.au3"
#include "LauncherSettings.au3"
#include "LauncherAbout.au3"
#include "PortableAppSetup.au3"
#include "PortableVmInventory.au3"
#include "ManagedProcess.au3"
#include "ManagerWindow.au3"
#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsStylesConstants.au3>

; The standard GUI includes real session controls. Privileged effects remain
; disabled outside the disposable-host acceptance boundary until Windows 11 signoff.
Func _LG_ProfileText($status)
    Switch $status
        Case "READY"
            Return _LI("profile.ready")
        Case "MISSING"
            Return _LI("profile.missing")
        Case Else
            Return _LI("profile.blocked")
    EndSwitch
EndFunc

; A ready data directory alone is not enough for a usable VirtualBox.
Func _LG_ProfileMessage($profile)
    If Not IsMap($profile) Or Not MapExists($profile, "status") Or _
            Not MapExists($profile, "app_present") Then Return _LI("profile.blocked")
    Local $message = _LG_ProfileText($profile["status"])
    If $profile["status"] == "READY" And Not $profile["app_present"] Then _
        $message &= " " & _LI("profile.appmissing")
    Return $message
EndFunc

; Keep long portable roots legible at standard DPI. The tooltip holds the full
; path; this is display-only, never fed into any filesystem operation.
Func _LG_DisplayPath($root, $maxChars = 58)
    If Not IsString($root) Then Return ""
    If Not IsInt($maxChars) Or $maxChars < 12 Then Return ""
    If StringLen($root) <= $maxChars Then Return $root
    Local $left = Int(($maxChars - 3) / 2)
    Return StringLeft($root, $left) & "..." & StringRight($root, $maxChars - 3 - $left)
EndFunc

Func _LG_SettingsText($s)
    If $s["status"] == "BLOCKED" Then Return _LI("settings.blocked")
    If $s["language"] == "auto" Then Return _LI("settings.auto_status")
    Return _LI("settings.saved") & $s["language"]
EndFunc

Func _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idManager, $idReady, $idVmAudit, $idResult, _
        $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idRestore, $idCancel, _
        $showReadiness = False, $showInventory = False)
    WinSetTitle($hGui, "", _LI("app.title"))
    GUICtrlSetData($idSubtitle, _LI("app.subtitle"))
    GUICtrlSetData($idWarning, _LI("app.disabled"))
    If $showInventory Then
        GUICtrlSetData($idSection, _LI("vm.header"))
    Else
        GUICtrlSetData($idSection, _LI("gui.diagnostics"))
    EndIf
    GUICtrlSetData($idRefresh, _LI("gui.refresh"))
    GUICtrlSetData($idCopy, _LI("gui.copy"))
    GUICtrlSetData($idClose, _LI("gui.exit"))
    GUICtrlSetData($idRu, _LI("gui.russian"))
    GUICtrlSetData($idEn, _LI("gui.english"))
    GUICtrlSetData($idPrepare, _LI("gui.prepare"))
    GUICtrlSetData($idManager, _LI("gui.manager"))
    GUICtrlSetData($idReady, _LI("gui.readiness"))
    GUICtrlSetData($idVmAudit, _LI("gui.vm_audit"))
    GUICtrlSetData($idSave, _LI("gui.save_language"))
    GUICtrlSetData($idAuto, _LI("gui.auto_language"))
    GUICtrlSetData($idAbout, _LI("gui.about"))
    GUICtrlSetData($idBackup, _LI("backup.create"))
    GUICtrlSetData($idVerify, _LI("backup.verify"))
    GUICtrlSetData($idRestore, _LI("backup.restore"))
    GUICtrlSetData($idCancel, _LI("backup.cancel"))
    GUICtrlSetData($idSettings, _LG_SettingsText(_LS_Load(@ScriptDir)))
    If _LI_Language() == "ru" Then
        GUICtrlSetState($idRu, $GUI_CHECKED)
    Else
        GUICtrlSetState($idEn, $GUI_CHECKED)
    EndIf
    GUICtrlSetData($idPath, _LI("gui.path") & _LG_DisplayPath(@ScriptDir))
    GUICtrlSetTip($idPath, @ScriptDir)
    Local $p = _PP_Inspect(@ScriptDir)
    GUICtrlSetData($idProfile, _LG_ProfileMessage($p))
    Local $diagnostic = _PortableDiagnosticCollect()
    If $showInventory Then
        Local $inventory = _PVI_Inspect(@ScriptDir)
        GUICtrlSetData($idReport, $inventory["report"])
    Else
        GUICtrlSetData($idReport, $diagnostic["text"])
    EndIf
    ; Never retain a Russian status in English UI (or vice versa).
    ; Refresh a previously requested readiness probe after locale/preflight changes.
    If $showReadiness Then
        Local $readiness = _LR_Inspect(@ScriptDir)
        GUICtrlSetData($idResult, $readiness["message"])
    Else
        GUICtrlSetData($idResult, "")
    EndIf
EndFunc

Func _LG_Show()
    Local $hGui = GUICreate(_LI("app.title"), 680, 814)
    GUISetBkColor(0xF7F9FC, $hGui)
    Local $idSubtitle = GUICtrlCreateLabel("", 22, 16, 625, 32)
    GUICtrlSetFont($idSubtitle, 14, 600, 0, "Segoe UI")
    Local $idWarning = GUICtrlCreateLabel("", 22, 53, 630, 52)
    GUICtrlSetFont($idWarning, 10, 400, 0, "Segoe UI")
    Local $idRu = GUICtrlCreateRadio("", 22, 116, 155, 25)
    Local $idEn = GUICtrlCreateRadio("", 180, 116, 155, 25)
    If _LI_Language() == "ru" Then
        GUICtrlSetState($idRu, $GUI_CHECKED)
    Else
        GUICtrlSetState($idEn, $GUI_CHECKED)
    EndIf
    Local $idSave = GUICtrlCreateButton("", 342, 112, 152, 31)
    Local $idAuto = GUICtrlCreateButton("", 502, 112, 154, 31)
    Local $idSettings = GUICtrlCreateLabel("", 22, 148, 634, 37)
    Local $idSection = GUICtrlCreateLabel("", 22, 188, 630, 26)
    GUICtrlSetFont($idSection, 11, 600, 0, "Segoe UI")
    Local $idReport = GUICtrlCreateEdit("", 22, 217, 634, 186, BitOR($ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL))
    GUICtrlSetFont($idReport, 10, 400, 0, "Consolas")
    Local $idPath = GUICtrlCreateLabel("", 22, 410, 634, 28)
    Local $idProfile = GUICtrlCreateLabel("", 22, 445, 634, 42)
    Local $idPrepare = GUICtrlCreateButton("", 22, 492, 310, 37)
    Local $idManager = GUICtrlCreateButton("", 346, 492, 310, 37)
    Local $idReady = GUICtrlCreateButton("", 22, 537, 310, 37)
    Local $idVmAudit = GUICtrlCreateButton("", 346, 537, 310, 37)
    Local $idResult = GUICtrlCreateEdit("", 22, 583, 634, 56, BitOR($ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL))
    Local $idBackup = GUICtrlCreateButton("", 22, 648, 150, 37)
    Local $idVerify = GUICtrlCreateButton("", 184, 648, 150, 37)
    Local $idRestore = GUICtrlCreateButton("", 346, 648, 150, 37)
    Local $idCancel = GUICtrlCreateButton("", 508, 648, 148, 37)
    Local $idBackupStatus = GUICtrlCreateEdit("", 22, 694, 634, 56, BitOR($ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL))
    Local $idRefresh = GUICtrlCreateButton("", 22, 761, 150, 35)
    Local $idCopy = GUICtrlCreateButton("", 184, 761, 150, 35)
    Local $idAbout = GUICtrlCreateButton("", 346, 761, 150, 35)
    Local $idClose = GUICtrlCreateButton("", 508, 761, 148, 35)
    Local $checked = False, $showInventory = False
    Local $backupWorker = _MP_New(), $backupTarget = "", $backupAction = "", $restoreSource = ""
    Local $setupWorker = _MP_New(), $setupInstaller = ""
    GUICtrlSetData($idBackupStatus, _LI("backup.hint"))
    GUICtrlSetState($idCancel, $GUI_DISABLE)
    ; Hosted disposable-root only until helper/UAC production acceptance.
    ; A disabled button is deliberate: never make an enabled, inert Start.
    If Not _MS_Allowed(@ScriptDir, EnvGet("GITHUB_WORKSPACE")) Then
        GUICtrlSetState($idManager, $GUI_DISABLE)
        GUICtrlSetTip($idManager, _LI("gui.manager_blocked"))
    EndIf
    _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idManager, $idReady, $idVmAudit, $idResult, $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idRestore, $idCancel)
    GUISetState(@SW_SHOW, $hGui)
    While 1
        Local $event = GUIGetMsg()
        Switch $event
            Case $GUI_EVENT_CLOSE, $idClose
                ExitLoop
            Case $idRu, $idEn
                If GUICtrlRead($idRu) == $GUI_CHECKED Then
                    _LI_Set("ru")
                Else
                    _LI_Set("en")
                EndIf
                _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                    $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idManager, $idReady, $idVmAudit, $idResult, $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idRestore, $idCancel, $checked, $showInventory)
            Case $idSave, $idAuto
                Local $preference = _LI_Language()
                If $event = $idAuto Then $preference = "auto"
                If _LS_Save(@ScriptDir, $preference) Then
                    _LI_Set(_LS_Select($preference, @OSLang))
                    _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idManager, $idReady, $idVmAudit, $idResult, _
                        $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idRestore, $idCancel, $checked, $showInventory)
                Else
                    GUICtrlSetData($idSettings, _LI("settings.save_failed"))
                EndIf
            Case $idAbout
                MsgBox(64, _LI("gui.about"), _LA_Text(), 0, $hGui)
            Case $idManager
                If _MS_Allowed(@ScriptDir, EnvGet("GITHUB_WORKSPACE")) And $backupWorker["handle"] = 0 Then
                    GUISetState(@SW_HIDE, $hGui)
                    _MSW_Show(@ScriptDir, EnvGet("GITHUB_WORKSPACE"))
                    GUISetState(@SW_SHOW, $hGui)
                    ; Previous services and activity are not assumed clean.
                    _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idManager, $idReady, $idVmAudit, $idResult, _
                        $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idRestore, $idCancel, $checked, $showInventory)
                EndIf
            Case $idPrepare
                If $setupWorker["handle"] <> 0 Or $backupWorker["handle"] <> 0 Then ContinueLoop
                Local $result = _PP_Ensure(@ScriptDir)
                GUICtrlSetData($idProfile, _LG_ProfileMessage($result))
                If $result["status"] == "READY" Then
                    Local $app = _PA_Inspect(@ScriptDir)
                    If $app["status"] == "MISSING" Then
                        If _PA_FileState(@ScriptDir, "Portable-VirtualBox-Setup.exe") <> 1 Then
                            GUICtrlSetData($idResult, _LI("setup.blocked"))
                        Else
                            ; First-run setup selects an already-downloaded pinned Oracle
                            ; installer. No network fetch, Python installation or UAC.
                            Local $installer = FileOpenDialog(_LI("setup.choose"), @ScriptDir, "Oracle VirtualBox installer (*.exe)", 1, "", $hGui)
                            If $installer <> "" Then
                                $setupWorker = _PAS_Start(@ScriptDir, $installer)
                                If $setupWorker["status"] == "STARTED" Then
                                    $setupInstaller = $installer
                                    GUICtrlSetState($idPrepare, $GUI_DISABLE)
                                    GUICtrlSetData($idResult, _LI("setup.running"))
                                Else
                                    GUICtrlSetData($idResult, _LI("setup.blocked"))
                                EndIf
                            EndIf
                        EndIf
                    EndIf
                EndIf
                If $checked And $setupWorker["handle"] = 0 Then
                    Local $readiness = _LR_Inspect(@ScriptDir)
                    GUICtrlSetData($idResult, $readiness["message"])
                EndIf
            Case $idReady
                $checked = True
                Local $readiness = _LR_Inspect(@ScriptDir)
                GUICtrlSetData($idResult, $readiness["message"])
            Case $idVmAudit
                $showInventory = True
                Local $inventory = _PVI_Inspect(@ScriptDir)
                GUICtrlSetData($idSection, _LI("vm.header"))
                GUICtrlSetData($idReport, $inventory["report"])
            Case $idRefresh
                _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                    $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idManager, $idReady, $idVmAudit, $idResult, $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idRestore, $idCancel, $checked, $showInventory)
            Case $idBackup, $idVerify, $idRestore
                If $setupWorker["handle"] <> 0 Then ContinueLoop
                If $event == $idBackup Then
                    Local $risk = _PVI_Inspect(@ScriptDir)
                    If $risk["status"] == "REVIEW" Or $risk["status"] == "BLOCKED" Then
                        If MsgBox(0x34, _LI("vm.header"), _LI("vm.backup_warning"), 0, $hGui) <> 6 Then ContinueLoop
                    EndIf
                EndIf
                If $backupWorker["handle"] = 0 Then
                    Local $chosen = FileSelectFolder(_LI("backup.choose"), "", 2)
                    If $chosen <> "" Then
                        If StringRight($chosen, 1) == "\" Then $chosen = StringTrimRight($chosen, 1)
                        $backupTarget = $chosen
                        $backupAction = "--verify-backup"
                        $restoreSource = ""
                        If $event = $idRestore Then
                            $restoreSource = $backupTarget
                            Local $parent = FileSelectFolder(_LI("backup.choose"), "", 2)
                            If $parent == "" Then ContinueLoop
                            If StringRight($parent, 1) == "\" Then $parent = StringTrimRight($parent, 1)
                            $backupTarget = $parent & "\PortableVBox-Restored-" & @YEAR & @MON & @MDAY & "-" & @HOUR & @MIN & @SEC
                            $backupAction = "--restore-backup"
                        EndIf
                        If $event = $idBackup Then
                            $backupAction = "--backup-data"
                            $backupTarget &= "\PortableVBox-Backup-" & @YEAR & @MON & @MDAY & "-" & @HOUR & @MIN & @SEC
                        EndIf
                        Local $args = $backupAction & ' "' & $backupTarget & '"'
                        If $backupAction == "--restore-backup" Then $args = $backupAction & ' "' & $restoreSource & '" "' & $backupTarget & '"'
                        $backupWorker = _MP_Start(@ScriptFullPath, $args, @ScriptDir)
                        If $backupWorker["status"] == "STARTED" Then
                            GUICtrlSetState($idManager, $GUI_DISABLE) ; backup is active
                            GUICtrlSetState($idBackup, $GUI_DISABLE)
                            GUICtrlSetState($idVerify, $GUI_DISABLE)
                            GUICtrlSetState($idRestore, $GUI_DISABLE)
                            If $backupAction == "--backup-data" Or $backupAction == "--restore-backup" Then GUICtrlSetState($idCancel, $GUI_ENABLE)
                            GUICtrlSetData($idBackupStatus, _LI("backup.running") & @CRLF & $backupTarget)
                        Else
                            GUICtrlSetData($idBackupStatus, _LI("backup.failed") & @CRLF & $backupTarget)
                        EndIf
                    EndIf
                EndIf
            Case $idCancel
                If $backupWorker["handle"] <> 0 And ($backupAction == "--backup-data" Or $backupAction == "--restore-backup") Then
                    Local $cancel = FileOpen($backupTarget & ".cancel-request", 1)
                    If $cancel <> -1 Then
                        FileWrite($cancel, "cancel")
                        FileClose($cancel)
                        GUICtrlSetData($idBackupStatus, _LI("backup.cancelled") & @CRLF & $backupTarget)
                        GUICtrlSetState($idCancel, $GUI_DISABLE)
                    EndIf
                EndIf
            Case $idCopy
                ClipPut(GUICtrlRead($idReport))
        EndSwitch
        If $setupWorker["handle"] <> 0 Then
            Local $state = _MP_Poll($setupWorker)
            If $state == "EXITED" Then
                Local $success = _PAS_Complete(@ScriptDir, $setupWorker["exit_code"])
                _MP_Release($setupWorker)
                GUICtrlSetState($idPrepare, $GUI_ENABLE)
                If $success Then
                    GUICtrlSetData($idResult, _LI("setup.done"))
                Else
                    GUICtrlSetData($idResult, _LI("setup.failed"))
                EndIf
                Local $preparedProfile = _PP_Inspect(@ScriptDir)
                GUICtrlSetData($idProfile, _LG_ProfileMessage($preparedProfile))
            ElseIf $state == "UNKNOWN" Then
                GUICtrlSetData($idResult, _LI("setup.unknown"))
                GUICtrlSetState($idPrepare, $GUI_DISABLE)
            EndIf
        EndIf
        If $backupWorker["handle"] <> 0 Then
            Local $status = _MP_Poll($backupWorker)
            If $status == "EXITED" Then
                Local $message = _LI("backup.failed")
                If $backupWorker["exit_code"] = 0 Then
                    $message = _LI("backup.verified")
                    If $backupAction == "--restore-backup" Then $message = _LI("backup.restored")
                EndIf
                If $backupWorker["exit_code"] = 2 Then $message = _LI("backup.blocked")
                GUICtrlSetData($idBackupStatus, $message & @CRLF & $backupTarget)
                _MP_Release($backupWorker)
                GUICtrlSetState($idBackup, $GUI_ENABLE)
                GUICtrlSetState($idVerify, $GUI_ENABLE)
                GUICtrlSetState($idRestore, $GUI_ENABLE)
                GUICtrlSetState($idCancel, $GUI_DISABLE)
                If _MS_Allowed(@ScriptDir, EnvGet("GITHUB_WORKSPACE")) Then GUICtrlSetState($idManager, $GUI_ENABLE) ; backup finished
            ElseIf $status == "UNKNOWN" Then
                GUICtrlSetData($idBackupStatus, _LI("backup.unknown") & @CRLF & $backupTarget)
                ; Fail closed. Do not kill, discard or release an unknown worker.
            EndIf
        EndIf
    WEnd
    GUIDelete($hGui)
    Return 2
EndFunc
