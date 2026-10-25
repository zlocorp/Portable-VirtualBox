#include "..\..\source\PortableAppSetup.au3"
Global $checks = 0, $failed = 0
Func Check($condition, $name)
    $checks += 1
    If Not $condition Then
        $failed += 1
        ConsoleWriteError("FAIL offline setup: " & $name & @CRLF)
    EndIf
EndFunc
Check(_PAS_Args("C:\Portable VBox", "C:\Downloads\VirtualBox-7.2.22-175245-Win.exe") == _
    '--installer "C:\Downloads\VirtualBox-7.2.22-175245-Win.exe" --root "C:\Portable VBox"', "unicode/space-safe quoted args")
Check(_PAS_Args("C:\Portable VBox", "\\server\share\installer.exe") == "", "UNC source refused")
Check(_PAS_Args("C:\Portable VBox", "C:\Temp\bad" & @CRLF & "line.exe") == "", "control characters refused")
Check(_PAS_Args("C:\Portable VBox", "C:\Temp\bad" & Chr(34) & "quote.exe") == "", "quotes refused")
Check(_PAS_Args("C:\Portable VBox", "") == "", "empty installer refused")
Check(_PAS_DownloadArgs("C:\Portable VBox") == '--download --root "C:\Portable VBox"', "pinned online CLI args")
Check(_PAS_DownloadArgs("\\server\share") == "", "online UNC root refused")
Check(_PAS_DownloadArgs("C:\bad" & @CRLF & "root") == "", "online newline refused")
Check(Not _PAS_CanPrepareRoot("C:\nonexistent-PortableVBox"), "online root safety required")
Local $online = _PAS_StartDownload("C:\nonexistent-PortableVBox")
Check($online["status"] <> "STARTED", "online must not run with missing root")
Check(Not _PAS_CanPrepare("C:\no-such-vbox-dir", "C:\Temp\file.exe"), "no effects at nonexistent root")
Check(Not _PAS_Complete("C:\no-such-vbox-dir", 0), "zero exit without verified app64 is not success")
Check(Not _PAS_Complete("C:\no-such-vbox-dir", 3), "failed helper cannot mark success")
Local $p = _PAS_Start("C:\no-such-vbox-dir", "C:\Temp\file.exe")
Check($p["status"] <> "STARTED" And $p["handle"] = 0, "no arbitrary process started")
ConsoleWrite("Offline portable app setup native assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed > 0)
