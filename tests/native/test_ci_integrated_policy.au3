#include "..\..\source\PortableCIIntegrated.au3"
Global $checks=0,$failed=0
Func Check($ok,$name)
 $checks+=1
 If Not $ok Then
   $failed+=1
   ConsoleWriteError("FAIL integrated policy: "&$name&@CRLF)
 EndIf
EndFunc
Check(_PCI_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox", _
 "C:\runner\Portable Тест","C:\runner","C:\workspace\repo"),"valid synthetic CI shape")
Check(Not _PCI_Allowed("false","github-hosted","Windows","zlocorp/Portable-VirtualBox", _
 "C:\runner\Portable Тест","C:\runner","C:\workspace\repo"),"reject local invocation")
Check(Not _PCI_Allowed("true","self-hosted","Windows","zlocorp/Portable-VirtualBox", _
 "C:\runner\Portable Тест","C:\runner","C:\workspace\repo"),"reject self-hosted")
Check(Not _PCI_Allowed("true","github-hosted","Linux","zlocorp/Portable-VirtualBox", _
 "C:\runner\Portable Тест","C:\runner","C:\workspace\repo"),"reject non-Windows")
Check(Not _PCI_Allowed("true","github-hosted","Windows","other/repo", _
 "C:\runner\Portable Тест","C:\runner","C:\workspace\repo"),"reject other repository")
Check(Not _PCI_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox", _
 "C:\other\Portable Тест","C:\runner","C:\workspace\repo"),"reject outside private runner")
Check(Not _PCI_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox", _
 "C:\runner\Portable Тест","C:\runner","C:\runner\Portable Тест"),"reject workspace same as portable root")
Check(Not _PCI_Allowed("true","github-hosted","Windows","zlocorp/Portable-VirtualBox", _
 "C:\runner\Portable Тест","C:\runner","..\scripts"),"reject relative scripts root")
Check(_PCI_QuotePath("C:\Portable Тест\scripts\safe.ps1") == '"C:\Portable Тест\scripts\safe.ps1"', _
 "quote Cyrillic space path")
Check(_PCI_QuotePath("C:\safe\file.ps1") == '"C:\safe\file.ps1"', _
 "quote ordinary absolute path")
Check(_PCI_QuotePath("..\script.ps1") == "","reject relative path")
Check(_PCI_QuotePath("C:\safe\..\script.ps1") == "","reject traversal")
Check(_PCI_QuotePath('C:\safe" -Command Start-Process') == "","reject quote injection")
Check(_PCI_QuotePath("C:\safe" & @LF & "bad") == "","reject newline injection")
Check(_PCI_QuotePath("\\server\share\script.ps1") == "","reject UNC script")
ConsoleWrite("Integrated CI policy native assertions: "&$checks&"; failed: "&$failed&@CRLF)
Exit ($failed>0)
