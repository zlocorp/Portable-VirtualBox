#include-once
#include "LauncherI18n.au3"
; Keep About focused on the product. Detailed notices live in CREDITS.md.
Func _LA_Text($language = "")
    Return _LI("about.summary", $language) & @CRLF & @CRLF & _
        "https://github.com/zlocorp/Portable-VirtualBox" & @CRLF & _
        "CC BY-NC-SA 3.0 | LICENSE.md | CREDITS.md" & @CRLF & @CRLF & _
        _LI("app.disabled", $language)
EndFunc
