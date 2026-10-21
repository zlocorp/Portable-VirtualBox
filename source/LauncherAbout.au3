#include-once
#include "LauncherI18n.au3"
; Compiled credits travel with the EXE; full provenance also ships in CREDITS.md.
Func _LA_Text($language = "")
    Return _LI("about.summary", $language) & @CRLF & @CRLF & _
        _LI("about.upstream", $language) & "Michael Meyer (michaelm_007), vboxme / Runar Buvik" & @CRLF & _
        _LI("about.maintainer", $language) & "zlocorp" & @CRLF & _
        _LI("about.community", $language) & "Deac2, ThatAdminGuy, bitamind, skyshay001, janpio, araname, SpruceGuy7" & @CRLF & @CRLF & _
        "CC BY-NC-SA 3.0 | LICENSE.md | CREDITS.md | THIRD_PARTY_NOTICES.md" & @CRLF & _
        "https://github.com/zlocorp/Portable-VirtualBox" & @CRLF & @CRLF & _
        _LI("about.boundary", $language)
EndFunc
