#include "..\..\source\LauncherGui.au3"
; Regression inputs inspired by Deac2 first-run UX, upstream PR #92/#95,
; issue #103 and ThatAdminGuy's distinct Manager/guest lifetimes. See CREDITS.md.
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL community adoption: " & $label & @CRLF)
    EndIf
EndFunc

Local $root = @TempDir & "\Community Portable Тест " & @AutoItPID
Check(DirCreate($root), "new private fixture")
Local $s = _LS_Load($root)
Check($s["status"] == "ABSENT", "no initial settings")
Check(Not FileExists($root & "\data"), "loading settings never creates data")
Check(_LS_Select("auto", "0419") == "ru", "auto uses Russian host")
Check(_LS_Select("en", "0419") == "en", "saved preference overrides host")
Check(_LS_Select("invalid", "0409") == "en", "invalid preference safely defaults")
Check(_LS_Parse("[PortableVirtualBox]" & @CRLF & "version=1" & @CRLF & "language=ru" & @CRLF) == "ru", "strict config parses")
Check(_LS_Parse("[PortableVirtualBox]" & @LF & "version=1" & @LF & "language=auto" & @LF) == "auto", "LF allowed")
Check(_LS_Parse("[Other]" & @CRLF & "language=ru" & @CRLF) == "", "foreign ini rejected")
Check(_LS_Parse("[PortableVirtualBox]" & @LF & "version=2" & @LF & "language=ru" & @LF) == "", "future schema refused")
Check(Not _LS_Save($root, "fr"), "unsupported saved locale refused")
Check(Not FileExists($root & "\data"), "invalid preference does not create profile")
Check(_LS_Save($root, "ru"), "persist Russian")
$s = _LS_Load($root)
Check($s["status"] == "READY" And $s["language"] == "ru", "read back Russian")
Check(_LS_Save($root, "en"), "replace own preference")
$s = _LS_Load($root)
Check($s["language"] == "en", "read back English")
Check(Not FileExists($root & "\data\launcher.ini.pending"), "successful save leaves no pending file")
Local $sentinel = $root & "\data\.VirtualBox\user.xml"
FileWrite($sentinel, "user-data-preserved")
Check(_LS_Save($root, "auto"), "reset to host language without removing other data")
Check(FileRead($sentinel) == "user-data-preserved", "Oracle/user data unchanged")
Local $moved = $root & " moved"
Check(DirMove($root, $moved), "move root with spaces and Cyrillic")
$root = $moved
$s = _LS_Load($root)
Check($s["status"] == "READY" And $s["language"] == "auto", "preferences survive root move")
FileWrite($root & "\data\launcher.ini.pending", "unfinished-other-session")
Check(Not _LS_Save($root, "ru"), "stale pending file refuses overwrite")
Check(FileRead($root & "\data\launcher.ini.pending") == "unfinished-other-session", "pending evidence preserved")
FileDelete($root & "\data\launcher.ini.pending")
Local $h = FileOpen($root & "\data\launcher.ini", 2)
FileWrite($h, "not-our-configuration")
FileClose($h)
Check(Not _LS_Save($root, "ru"), "malformed or foreign settings not overwritten")
Check(FileRead($root & "\data\launcher.ini") == "not-our-configuration", "foreign settings intact")
$s = _LS_Load($root)
Check($s["status"] == "BLOCKED", "invalid file surfaced to UI")

Local $a = _PA_Inspect($root)
Check($a["status"] == "MISSING", "absent app64 detected")
DirCreate($root & "\app64")
FileWrite($root & "\app64\VirtualBox.exe", "fixture")
$a = _PA_Inspect($root)
Check($a["status"] == "INCOMPLETE", "one EXE is not a complete VirtualBox")
Check(StringInStr($a["missing"], "VBoxManage.exe") > 0, "missing CLI identified")
Local $required = _PA_Required()
Check(UBound($required) = 15, "same 15 required inputs as verified MSI staging")
For $i = 0 To UBound($required) - 1
    Local $file = $root & "\app64\" & $required[$i]
    DirCreate(StringRegExpReplace($file, "\\[^\\]+$", ""))
    If Not FileExists($file) Then FileWrite($file, "fixture")
Next
$a = _PA_Inspect($root)
Check($a["status"] == "PRESENT", "complete file set detected, not an authenticity verdict")
Check($a["missing"] == "", "complete set has no missing names")
FileDelete($root & "\app64\VBoxManage.exe")
DirCreate($root & "\app64\VBoxManage.exe")
$a = _PA_Inspect($root)
Check($a["status"] == "UNSAFE", "directory masquerading as executable blocked")
DirRemove($root & "\app64\VBoxManage.exe")
FileWrite($root & "\app64\VBoxManage.exe", "")
$a = _PA_Inspect($root)
Check($a["status"] == "INCOMPLETE", "empty payload rejected")
DirRemove($root & "\data\Machines")
Local $p = _PP_Inspect($root)
Check(StringInStr($p["missing_folders"], "data\Machines") > 0, "missing Machines directory reported specifically")
Local $r = _LR_Decide($p, "")
Check(StringInStr($r["message"], "data\Machines") > 0, "readiness explains exact missing directory")

Check(_PortableProcessRole("VirtualBox.exe") == "manager", "Manager is not a guest")
Check(_PortableProcessRole("VirtualBoxVM.exe") == "guest", "GUI guest is a guest process")
Check(_PortableProcessRole("VBoxHeadless.exe") == "guest", "headless guest is a guest process")
Check(_PortableProcessRole("VBoxSVC.exe") == "background", "COM service is separate from Manager")
Check(_PortableProcessRole("VBoxSDS.exe") == "background", "SDS is separate from guest")
Check(_PortableProcessRole("other.exe") == "", "unknown image is not classified as ours")
Check(_PortableProcessRole("virtualboxvm.EXE") == "guest", "process name comparison ignores case")
Check(StringInStr(_LA_Text("ru"), "Michael Meyer") > 0, "About retains original author")
Check(StringInStr(_LA_Text("en"), "CC BY-NC-SA 3.0") > 0, "About retains license")
Check(StringInStr(_LA_Text("ru"), "Deac2") > 0, "About names community reference")
Check(StringInStr(_LA_Text("en"), "not") > 0, "About has honest preview limitation")
DirRemove($root, 1)
ConsoleWrite("Community adoption checks: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
