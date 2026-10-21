; Separate non-distributed runtime experiment. Original project and adapted
; lifecycle flow: CC BY-NC-SA 3.0, see LICENSE.md and CREDITS.md.
; No #RequireAdmin in the frontend. The current effect worker still requires
; an already elevated disposable runner; production UAC is not implemented.
#include "ManagerWindow.au3"
#NoTrayIcon
If Not _MS_Allowed(@ScriptDir, EnvGet("GITHUB_WORKSPACE")) Then
    ConsoleWriteError("Manager session experiment is restricted to a disposable hosted Windows root." & @CRLF)
    Exit 9
EndIf
Local $preferences = _LS_Load(@ScriptDir)
_LI_Set(_LS_Select($preferences["language"], @OSLang))
Local $arg = 1
While $arg <= $CmdLine[0]
    Switch $CmdLine[$arg]
        Case "--lang"
            If $arg >= $CmdLine[0] Then Exit 64
            $arg += 1
            If Not _LI_Set($CmdLine[$arg]) Then Exit 64
        Case "--separate-privileges"
            $g_MS_Separated = True
        Case Else
            Exit 64
    EndSwitch
    $arg += 1
WEnd
Exit _MSW_Show(@ScriptDir, EnvGet("GITHUB_WORKSPACE"))
