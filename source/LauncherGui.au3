#include-once
#include "LauncherI18n.au3"
#include "HostDiagnostics.au3"
#include "PortableProfile.au3"
#include "LauncherReadiness.au3"
#include "LauncherSettings.au3"
#include "LauncherAbout.au3"
#include "ManagedProcess.au3"
#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsStylesConstants.au3>

; Non-privileged user-facing preview: no Oracle VM launch or driver mutation.
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
        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult, _
        $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idCancel, _
        $showReadiness = False)
    WinSetTitle($hGui, "", _LI("app.title"))
    GUICtrlSetData($idSubtitle, _LI("app.subtitle"))
    GUICtrlSetData($idWarning, _LI("app.disabled"))
    GUICtrlSetData($idSection, _LI("gui.diagnostics"))
    GUICtrlSetData($idRefresh, _LI("gui.refresh"))
    GUICtrlSetData($idCopy, _LI("gui.copy"))
    GUICtrlSetData($idClose, _LI("gui.exit"))
    GUICtrlSetData($idRu, _LI("gui.russian"))
    GUICtrlSetData($idEn, _LI("gui.english"))
    GUICtrlSetData($idPrepare, _LI("gui.prepare"))
    GUICtrlSetData($idReady, _LI("gui.readiness"))
    GUICtrlSetData($idSave, _LI("gui.save_language"))
    GUICtrlSetData($idAuto, _LI("gui.auto_language"))
    GUICtrlSetData($idAbout, _LI("gui.about"))
    GUICtrlSetData($idBackup, _LI("backup.create"))
    GUICtrlSetData($idVerify, _LI("backup.verify"))
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
    GUICtrlSetData($idReport, $diagnostic["text"])
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
    Local $idPrepare = GUICtrlCreateButton("", 22, 492, 634, 37)
    Local $idReady = GUICtrlCreateButton("", 22, 537, 634, 37)
    Local $idResult = GUICtrlCreateEdit("", 22, 583, 634, 56, BitOR($ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL))
    Local $idBackup = GUICtrlCreateButton("", 22, 648, 206, 37)
    Local $idVerify = GUICtrlCreateButton("", 238, 648, 206, 37)
    Local $idCancel = GUICtrlCreateButton("", 454, 648, 202, 37)
    Local $idBackupStatus = GUICtrlCreateEdit("", 22, 694, 634, 56, BitOR($ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL))
    Local $idRefresh = GUICtrlCreateButton("", 22, 761, 150, 35)
    Local $idCopy = GUICtrlCreateButton("", 184, 761, 150, 35)
    Local $idAbout = GUICtrlCreateButton("", 346, 761, 150, 35)
    Local $idClose = GUICtrlCreateButton("", 508, 761, 148, 35)
    Local $checked = False
    Local $backupWorker = _MP_New(), $backupTarget = "", $backupAction = ""
    GUICtrlSetData($idBackupStatus, _LI("backup.hint"))
    GUICtrlSetState($idCancel, $GUI_DISABLE)
    _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult, $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idCancel)
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
                    $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult, $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idCancel, $checked)
            Case $idSave, $idAuto
                Local $preference = _LI_Language()
                If $event = $idAuto Then $preference = "auto"
                If _LS_Save(@ScriptDir, $preference) Then
                    _LI_Set(_LS_Select($preference, @OSLang))
                    _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult, _
                        $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idCancel, $checked)
                Else
                    GUICtrlSetData($idSettings, _LI("settings.save_failed"))
                EndIf
            Case $idAbout
                MsgBox(64, _LI("gui.about"), _LA_Text(), 0, $hGui)
            Case $idPrepare
                Local $result = _PP_Ensure(@ScriptDir)
                GUICtrlSetData($idProfile, _LG_ProfileMessage($result))
                If $checked Then
                    Local $readiness = _LR_Inspect(@ScriptDir)
                    GUICtrlSetData($idResult, $readiness["message"])
                EndIf
            Case $idReady
                $checked = True
                Local $readiness = _LR_Inspect(@ScriptDir)
                GUICtrlSetData($idResult, $readiness["message"])
            Case $idRefresh
                _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                    $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult, $idSave, $idAuto, $idSettings, $idAbout, $idBackup, $idVerify, $idCancel, $checked)
            Case $idBackup, $idVerify
                If $backupWorker["handle"] = 0 Then
                    Local $chosen = FileSelectFolder(_LI("backup.choose"), "", 2)
                    If $chosen <> "" Then
                        If StringRight($chosen, 1) == "\" Then $chosen = StringTrimRight($chosen, 1)
                        $backupTarget = $chosen
                        $backupAction = "--verify-backup"
                        If $event = $idBackup Then
                            $backupAction = "--backup-data"
                            $backupTarget &= "\PortableVBox-Backup-" & @YEAR & @MON & @MDAY & "-" & @HOUR & @MIN & @SEC
                        EndIf
                        Local $args = $backupAction & ' "' & $backupTarget & '"'
                        $backupWorker = _MP_Start(@ScriptFullPath, $args, @ScriptDir)
                        If $backupWorker["status"] == "STARTED" Then
                            GUICtrlSetState($idBackup, $GUI_DISABLE)
                            GUICtrlSetState($idVerify, $GUI_DISABLE)
                            If $backupAction == "--backup-data" Then GUICtrlSetState($idCancel, $GUI_ENABLE)
                            GUICtrlSetData($idBackupStatus, _LI("backup.running") & @CRLF & $backupTarget)
                        Else
                            GUICtrlSetData($idBackupStatus, _LI("backup.failed") & @CRLF & $backupTarget)
                        EndIf
                    EndIf
                EndIf
            Case $idCancel
                If $backupWorker["handle"] <> 0 And $backupAction == "--backup-data" Then
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
        If $backupWorker["handle"] <> 0 Then
            Local $status = _MP_Poll($backupWorker)
            If $status == "EXITED" Then
                Local $message = _LI("backup.failed")
                If $backupWorker["exit_code"] = 0 Then $message = _LI("backup.verified")
                If $backupWorker["exit_code"] = 2 Then $message = _LI("backup.blocked")
                GUICtrlSetData($idBackupStatus, $message & @CRLF & $backupTarget)
                _MP_Release($backupWorker)
                GUICtrlSetState($idBackup, $GUI_ENABLE)
                GUICtrlSetState($idVerify, $GUI_ENABLE)
                GUICtrlSetState($idCancel, $GUI_DISABLE)
            ElseIf $status == "UNKNOWN" Then
                GUICtrlSetData($idBackupStatus, _LI("backup.unknown") & @CRLF & $backupTarget)
                ; Fail closed. Do not kill, discard or release an unknown worker.
            EndIf
        EndIf
    WEnd
    GUIDelete($hGui)
    Return 2
EndFunc
