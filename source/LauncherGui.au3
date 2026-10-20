#include-once
#include "LauncherI18n.au3"
#include "HostDiagnostics.au3"
#include "PortableProfile.au3"
#include "LauncherReadiness.au3"
#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsStylesConstants.au3>

; Honest preview: the GUI can prepare only private user folders, read Windows
; state and copy its diagnostics. No VM/driver actions are wired to this screen.
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

Func _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult)
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
    GUICtrlSetData($idPath, _LI("gui.path") & @ScriptDir)
    GUICtrlSetTip($idPath, @ScriptDir)
    Local $p = _PP_Inspect(@ScriptDir)
    GUICtrlSetData($idProfile, _LG_ProfileText($p["status"]))
    Local $diagnostic = _PortableDiagnosticCollect()
    GUICtrlSetData($idReport, $diagnostic["text"])
EndFunc

Func _LG_Show()
    Local $hGui = GUICreate(_LI("app.title"), 630, 640)
    GUISetBkColor(0xF7F9FC, $hGui)
    Local $idSubtitle = GUICtrlCreateLabel("", 22, 16, 575, 30)
    GUICtrlSetFont($idSubtitle, 14, 600, 0, "Segoe UI")
    Local $idWarning = GUICtrlCreateLabel("", 22, 53, 580, 52)
    GUICtrlSetFont($idWarning, 10, 400, 0, "Segoe UI")
    Local $idRu = GUICtrlCreateRadio("", 22, 114, 155, 25)
    Local $idEn = GUICtrlCreateRadio("", 180, 114, 155, 25)
    If _LI_Language() == "ru" Then
        GUICtrlSetState($idRu, $GUI_CHECKED)
    Else
        GUICtrlSetState($idEn, $GUI_CHECKED)
    EndIf
    Local $idSection = GUICtrlCreateLabel("", 22, 147, 565, 26)
    GUICtrlSetFont($idSection, 11, 600, 0, "Segoe UI")
    Local $idReport = GUICtrlCreateEdit("", 22, 176, 584, 216, BitOR($ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL))
    GUICtrlSetFont($idReport, 10, 400, 0, "Consolas")
    Local $idPath = GUICtrlCreateLabel("", 22, 404, 584, 21)
    Local $idProfile = GUICtrlCreateLabel("", 22, 428, 584, 21)
    Local $idPrepare = GUICtrlCreateButton("", 22, 455, 584, 35)
    Local $idReady = GUICtrlCreateButton("", 22, 498, 584, 35)
    Local $idResult = GUICtrlCreateLabel("", 22, 540, 584, 34)
    Local $idRefresh = GUICtrlCreateButton("", 22, 584, 185, 35)
    Local $idCopy = GUICtrlCreateButton("", 218, 584, 184, 35)
    Local $idClose = GUICtrlCreateButton("", 414, 584, 192, 35)
    _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
        $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult)
    GUISetState(@SW_SHOW, $hGui)
    While 1
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE, $idClose
                ExitLoop
            Case $idRu
                _LI_Set("ru")
                _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                    $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult)
            Case $idEn
                _LI_Set("en")
                _LG_Fill($hGui, $idSubtitle, $idWarning, $idSection, $idReport, _
                    $idRefresh, $idCopy, $idClose, $idRu, $idEn, $idPath, $idProfile, $idPrepare, $idReady, $idResult)
            Case $idPrepare
                Local $result = _PP_Ensure(@ScriptDir)
                GUICtrlSetData($idProfile, _LG_ProfileText($result["status"]))
                If $result["status"] == "READY" And Not $result["app_present"] Then
                    GUICtrlSetData($idProfile, _LG_ProfileText($result["status"]) & " " & _LI("profile.appmissing"))
                EndIf
            Case $idReady
                Local $status = _LR_Inspect(@ScriptDir)
                GUICtrlSetData($idResult, $status["message"])
            Case $idRefresh
                Local $diagnostic = _PortableDiagnosticCollect()
                GUICtrlSetData($idReport, $diagnostic["text"])
                Local $p = _PP_Inspect(@ScriptDir)
                GUICtrlSetData($idProfile, _LG_ProfileText($p["status"]))
            Case $idCopy
                ClipPut(GUICtrlRead($idReport))
        EndSwitch
    WEnd
    GUIDelete($hGui)
    Return 2
EndFunc
