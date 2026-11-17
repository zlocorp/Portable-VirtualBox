; Test-only host of the real coordination gate for the direct-helper fixture.
; This is NOT a production controller or a UAC acceptance surrogate.
#include "..\..\source\CliSessionGate.au3"
#include <GUIConstantsEx.au3>
If EnvGet("GITHUB_ACTIONS") <> "true" Or EnvGet("RUNNER_ENVIRONMENT") <> "github-hosted" Then Exit 9
If $CmdLine[0] <> 2 Then Exit 64
Local $gate = _CG_Create(Int($CmdLine[1]), Int($CmdLine[2]))
If $gate["handle"] = 0 Then Exit 3
Local $window = GUICreate("Portable CLI test gate", 260, 90)
GUICtrlCreateLabel("Fixture gate only; no UAC acceptance", 10, 15, 240, 60)
If Not _CG_SetReady($gate, True) Or Not _CG_Release($gate) Then Exit 4
GUISetState(@SW_SHOW, $window)
Local $closing = False
While 1
    If GUIGetMsg() = $GUI_EVENT_CLOSE Then $closing = True
    If $closing Then
        If Not _CG_SetReady($gate, False) Then Exit 5
        Local $lease = _CG_Acquire($gate)
        If $lease == "UNKNOWN" Then Exit 6
        If $lease == "HELD" Then ExitLoop
    EndIf
    Sleep(20)
WEnd
_CG_Close($gate)
Exit 0
