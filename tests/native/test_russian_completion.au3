#include "..\..\source\LauncherGui.au3"
; Local temporary fixtures only. No Oracle command, driver or elevation.
Global $checks = 0, $failed = 0
Func Check($ok, $label)
    $checks += 1
    If Not $ok Then
        $failed += 1
        ConsoleWriteError("FAIL Russian completion: " & $label & @CRLF)
    EndIf
EndFunc
Func XmlFixture($path, $text)
    Local $h = FileOpen($path, 2 + 256)
    If $h == -1 Then Return False
    Local $ok = FileWrite($h, $text)
    Return FileClose($h) And $ok
EndFunc
Local $keys = StringSplit("additional-registered-or-unregistered-vm|already-local|another-session|another-session-or-unknown-lock|background-not-idle|backup-does-not-describe-this-relocation|backup-incomplete-retain-staged-data|backup-missing-changed-or-does-not-match-current-data:|backup-must-contain-original-stale-registration|cancelled-but-host-state-not-clear|clean-host-never-stabilized-resources-retained|cleanup-worker-not-started|click-finish-to-retry-elevation|current-registration-is-not-the-backed-up-machine|current-vm-graph-differs-from-original-backup|disposable-host-only|elevation-cancelled-no-system-changes|exact-moved-vm-no-changes-applied|exact-uuid-verified-backup-no-delete|existing-or-unknown-VirtualBox|external-missing-or-unsafe-medium|frontend-must-be-non-administrator|host-not-offline|incomplete-app64|inspect-previous-protected-session-|invalid-or-existing-backup-destination|local-vbox-file-same-uuid|machine-metadata-differs-from-original-backup|manager-close-not-confirmed|manager-not-started|manager-window-timeout|missing-or-unsafe-portable-profile|new-machine-missing-or-unsafe|nonportable-or-ambiguous-registered-path|old-machine-still-present-or-unreadable|oracle-language-not-started|oracle-language-unverified|original-backup-verified-repair-stale-registration|original-backup-verified-resume-missing-registration|persistent-unknown-activity|portable-cli-abandoned-or-unknown-retain-resources|portable-cli-active|portable-cli-admission-unverified|portable-cli-gate-collision-or-error|portable-cli-gate-unverified-resources-retained|portable-cli-reobserve|post-rebind-configure-not-started|prepare-worker-not-started|profile-not-ready|rebind-|rebind-confirmed-proof-changed|rebind-first-command-not-started-retain-backup|rebind-postcondition-unverified-retain-backup|rebind-profile-missing|rebind-register-not-started-no-guessed-recovery|rebind-verified-configure-machine-folder|recovery-candidate-|recovery-consent-cancelled-resources-retained|recovery-foreign-or-active-processes|recovery-lock-failed|recovery-worker-not-started|registered-uuid-differs-from-machine|requires-exactly-one-registered-vm|saved-state-or-unsafe-ancillary-path|session-lock-create-failed-dll|session-lock-create-failed-win32-|session-lock-result-unknown-|source-changed-after-verified-backup|unexpected-services-after-prepare|unknown-process-or-manager-startup|unreadable-rebind-evidence|unsafe-or-ambiguous|unsupported-snapshot-or-media-graph|user-profile-configuration-not-started|verified-copy-created-registration-not-modified|worker-failed-no-guessed-cleanup-exit-|worker-not-confirmed-|worker-still-running-no-cleanup", "|", 2)
For $key In $keys
    Local $ru = _LI_Reason($key, "ru"), $en = _LI_Reason($key, "en")
    Check(StringRegExp(_LI_ReasonRu($key), "[А-Яа-яЁё]") = 1, "Russian explanation: " & $key)
    Check(StringInStr($ru, "Технический код: " & $key, 1) > 0, "original identifier retained: " & $key)
    Check($en == $key, "English technical output preserved: " & $key)
Next
Local $dynamic[5] = ["session-lock-create-failed-win32-5", "worker-not-confirmed-UNKNOWN", _
    "rebind-host-not-offline", "rebind-backup-missing-changed-or-does-not-match-current-data:current-file-differs:data\Моя ВМ.vbox", _
    "future-code:not-known-42"]
For $key In $dynamic
    Local $translated = _LI_Reason($key, "ru")
    Check(StringRegExp($translated, "[А-Яа-яЁё]") = 1, "dynamic reason has explanation")
    Check(StringRight($translated, StringLen($key)) == $key, "dynamic suffix and Unicode path preserved")
Next
Check(_LI_Reason("", "ru") == "", "empty reason stays empty")
Check(_LI_Reason(42, "ru") == _LI("diag.unknown", "ru"), "malformed reason does not imply success")
Check(_LI_Set("ru"), "select Russian")
Check(StringInStr(_MSW_Text("reopen"), "менеджер", 1) > 0, "localized Manager button")
Check(StringInStr(_MSW_Text("CONFIGURING_LANGUAGE"), "язык", 1) > 0, "new state has Russian explanation")
Check(Not _CG_StateAllows("CONFIGURING_LANGUAGE"), "CLI gate stays closed while applying language")
Local $refused = _PVR_New("BLOCKED", "host-not-offline")
Check(StringInStr(_PVR_Text($refused), "Исправление регистрации заблокировано", 1) > 0, "real rebind refusal uses explanation")

Local $backupKeys = StringSplit("backup.hint|backup.running|backup.verifying|backup.restoring|backup.cancelled|backup.failed|backup.created|backup.verified|backup.restored|backup.blocked|backup.unknown", "|", 2)
For $key In $backupKeys
    _LI_Set("ru")
    Local $ruText = _LG_BackupText($key, "D:\Копии\ВМ")
    _LI_Set("en")
    Local $enText = _LG_BackupText($key, "D:\Копии\ВМ")
    Check($ruText <> $enText, "backup state retranslates without changing state")
    Check(StringInStr($ruText, "D:\Копии\ВМ", 1) And StringInStr($enText, "D:\Копии\ВМ", 1), "backup target never translated")
Next
Local $settings[]
$settings["status"] = "READY"
$settings["language"] = "ru"
Check(_OL_Saved($settings) == "ru", "saved Russian maps to Oracle Russian")
Check(_LI_Set("en"), "temporary UI English")
Check(_OL_Saved($settings) == "ru", "temporary override cannot change saved Oracle selection")
$settings["language"] = "en"
Check(_OL_Saved($settings) == "C", "saved English maps to built-in C")
$settings["language"] = "auto"
Check(_OL_Saved($settings) == "", "auto preserves Oracle preference")
$settings["language"] = "RU"
Check(_OL_Saved($settings) == "", "invalid saved spelling is not coerced")
$settings["language"] = "ru"
$settings["status"] = "BLOCKED"
Check(_OL_Saved($settings) == "", "untrusted preference cannot write Oracle settings")
Local $empty[]
Check(_OL_Saved($empty) == "" And _OL_Saved("ru") == "", "missing and malformed preference ignored")
Check(_OL_Command("ru") == "setextradata global GUI/LanguageID ru", "exact Russian command")
Check(_OL_Command("C") == "setextradata global GUI/LanguageID C", "exact English command")
Local $badIds[6] = ["", "en", "RU", "ru --delete", 'ru" & other', "ru" & @CRLF]
For $id In $badIds
    Check(_OL_Command($id) == "", "arbitrary Oracle argument refused")
Next

Local $root = @TempDir & "\PVBox Русский " & @AutoItPID & "-" & Hex(Random(1, 2147483647, 1))
If FileExists($root) Then Exit 1 ; never adopt an existing fixture
If Not DirCreate($root) Then Exit 1
Local $profile = _PP_Ensure($root)
Check($profile["status"] == "READY", "create own temporary profile")
Local $xmlPath = $root & "\data\.VirtualBox\VirtualBox.xml"
Check(Not _OL_Verified($root, "ru"), "missing Oracle preference refused")
Local $head = '<VirtualBox xmlns="http://www.virtualbox.org/"><Global><ExtraData>'
Local $tail = '</ExtraData></Global></VirtualBox>'
Local $item = '<ExtraDataItem name="GUI/LanguageID" value="ru"/>'
Check(XmlFixture($xmlPath, $head & $item & $tail), "write synthetic Oracle preference")
Local $before = FileRead($xmlPath)
Check(_OL_Verified($root, "ru"), "exact single Russian preference verified")
Check(Not _OL_Verified($root, "C"), "wrong effective preference refused")
Check(FileRead($xmlPath) == $before, "verification never rewrites XML")
Check(XmlFixture($xmlPath, '<VirtualBox><Global><ExtraData><ExtraDataItem name="GUI/LanguageID" value="C"/></ExtraData></Global></VirtualBox>'), "legacy namespace-free fixture")
Check(_OL_Verified($root, "C"), "built-in English preference verified")
Local $badXml[7] = [$head & $item & $item & $tail, _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Global xmlns="urn:foreign"><ExtraData>' & $item & $tail, _
    $head & '<ExtraDataItem xmlns="urn:foreign" name="GUI/LanguageID" value="ru"/>' & $tail, _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Other><Global><ExtraData>' & $item & '</ExtraData></Global></Other></VirtualBox>', _
    $head & '<Other>' & $item & '</Other>' & $tail, _
    '<VirtualBox xmlns="http://www.virtualbox.org/"><Global><ExtraData/><ExtraData>' & $item & $tail, _
    '<!DOCTYPE VirtualBox [<!ENTITY bad SYSTEM "file:///C:/Windows/win.ini">]>' & $head & $item & $tail]
For $xml In $badXml
    Check(XmlFixture($xmlPath, $xml), "write invalid preference fixture")
    Check(Not _OL_Verified($root, "ru"), "duplicate, foreign, nested or DTD preference refused")
Next
Local $session = _MS_New($root, "")
$session["oracle_language"] = "ru"
Check(Not _MS_OpenLocalizedManager($session), "no command without owned preparation")
$session["owned"] = True
Local $worker = _MP_New()
$worker["handle"] = 123 ; guard only, never passed to Windows or released
$session["worker"] = $worker
Check(Not _MS_OpenLocalizedManager($session), "no concurrent language worker")
Check(Not FileExists($root & "\app64"), "tests never launch or install Oracle")
Check(DirRemove($root, 1), "remove only own local fixture")
ConsoleWrite("Native Russian completion assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
