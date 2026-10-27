#include "..\..\source\PortableVmRebind.au3"
Global $checks=0, $failed=0
Func Check($condition,$name)
    $checks+=1
    If Not $condition Then
        $failed+=1
        ConsoleWriteError("FAIL moved-VM rebind planner: " & $name & @CRLF)
    EndIf
EndFunc
Func WriteXml($path,$text)
    Local $h=FileOpen($path,2+256)
    If $h=-1 Then Return False
    Local $w=FileWrite($h,$text), $closed=FileClose($h)
    Return $w And $closed
EndFunc
Local $parent=@TempDir & "\PVR План " & @AutoItPID
Local $root=$parent & "\Перенесено", $old=$parent & "\Старый каталог", $backup=$parent & "\Копия"
Local $folder=$root & "\data\Machines\Имя ВМ"
Local $config=$folder & "\Имя ВМ.vbox", $registry=$root & "\data\.VirtualBox\VirtualBox.xml"
Local $oldPath=$old & "\data\Machines\Имя ВМ\Имя ВМ.vbox"
Local $uuid="{12345678-2222-3333-4444-abcdef123456}"
Check(DirCreate($folder & "\Snapshots"),"create VM snapshot tree")
Check(DirCreate($root & "\data\.VirtualBox"),"create global registry folder")
Check(FileWrite($folder & "\disk.vdi","PRIMARY-DISK")<>0,"base disk exists")
Check(FileWrite($folder & "\Snapshots\snap.vdi","DIFFERENCING-DISK")<>0,"snapshot disk exists")
Local $head='<VirtualBox xmlns="http://www.virtualbox.org/"><Machine name="Имя ВМ" uuid="' & $uuid & '"><MediaRegistry><HardDisks>'
Local $media='<HardDisk location="disk.vdi"/><HardDisk location="Snapshots/snap.vdi"/>'
Local $tail='</HardDisks></MediaRegistry><Snapshots><Snapshot name="Снимок"/></Snapshots></Machine></VirtualBox>'
Local $regHead='<VirtualBox xmlns="http://www.virtualbox.org/"><Global><MachineRegistry>'
Local $regTail='</MachineRegistry></Global></VirtualBox>'
Local $entry='<MachineEntry uuid="' & $uuid & '" src="' & $oldPath & '"/>'
Check(WriteXml($config,$head & $media & $tail),"VM config")
Check(WriteXml($registry,$regHead & $entry & $regTail),"stale original registry")
Local $plan=_PVR_Plan($root)
Check($plan["status"]=="READY","exact previously moved single VM plan")
Check($plan["uuid"]==StringLower($uuid),"plan UUID canonical")
Check($plan["snapshots"]=1 And $plan["media"]=2,"whole snapshot graph found")
Check($plan["new_path"]==$config And $plan["old_path"]==$oldPath,"old and new paths explicit")
Check(StringInStr(_PVR_Text($plan),"Registration was NOT changed")>0 Or _
      StringInStr(_PVR_Text($plan),"Регистрация не изменена")>0,"no changes promised")
Check(Not FileExists($old & "\data"),"planner never creates old folder")
Local $copy=_PVR_Backup($root,$backup)
Check($copy["status"]=="BACKED_UP","first verified file-only backup succeeded")
Check(_PBK_Verify($backup),"full copied data manifest checks out")
Check(FileRead($backup & "\data\Machines\Имя ВМ\Snapshots\snap.vdi")=="DIFFERENCING-DISK","snapshot bytes copied")
Check(FileRead($registry)==$regHead & $entry & $regTail,"backup never edits original registry")
Check(_PVR_Backup($root,$backup)["status"]=="BLOCKED","existing backup cannot be overwritten")
; Relative, already relocated registrations need no rebind.
Local $localEntry='<MachineEntry uuid="' & $uuid & '" src="..\Machines\Имя ВМ\Имя ВМ.vbox"/>'
Check(WriteXml($registry,$regHead & $localEntry & $regTail),"write ordinary local registry")
$plan=_PVR_Plan($root)
Check($plan["status"]=="NONE","already local registration is not stale")
; Ambiguous multiple registered VMs are not safe to repair automatically.
Check(WriteXml($registry,$regHead & $entry & $localEntry & $regTail),"write duplicate registration")
Check(_PVR_Plan($root)["status"]=="BLOCKED","second registration always blocks")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore stale registration")
; User media external to data cannot be called a complete file-copy.
Check(WriteXml($config,$head & $media & '<HardDisk location="E:\Other\private.vdi"/>' & $tail),"write external medium")
Check(_PVR_Plan($root)["status"]=="BLOCKED","external medium never accepted")
Check(WriteXml($config,$head & $media & $tail),"restore normal medium graph")
; Stale metadata forged with a different original UUID is refused.
Local $wrong='<MachineEntry uuid="{ffffffff-2222-3333-4444-abcdef123456}" src="' & $oldPath & '"/>'
Check(WriteXml($registry,$regHead & $wrong & $regTail),"write mismatched VM identity")
Check(_PVR_Plan($root)["status"]=="BLOCKED","old UUID cannot impersonate new VM")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore registry")
; Old disk still exists: user must not create two live machines with one UUID.
Check(DirCreate($old & "\data\Machines\Имя ВМ"),"create old collision folder")
Check(FileWrite($oldPath,"foreign config")<>0,"create old path collision")
Check(_PVR_Plan($root)["status"]=="BLOCKED","old live copy blocks repair")
FileDelete($oldPath)
Check(WriteXml($registry,'<!DOCTYPE VirtualBox [<!ENTITY leak SYSTEM "file:///C:/Windows/win.ini">]>' & $regHead & $entry & $regTail),"write XXE fixture")
Check(_PVR_Plan($root)["status"]=="BLOCKED","XXE/DOCTYPE blocks VM plan")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore safe XML")
FileDelete($folder & "\Snapshots\snap.vdi")
Check(_PVR_Plan($root)["status"]=="BLOCKED","missing snapshot disk blocks repair")
Check(FileRead($config)==$head & $media & $tail,"source machine never rewritten")
DirRemove($parent,1)
ConsoleWrite("Portable moved VM plan assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed>0)
