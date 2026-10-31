#include "..\..\source\ManagerSession.au3"
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
Local $snapshotUuid="{55555555-2222-3333-4444-abcdef123456}"
Local $baseUuid="{66666666-2222-3333-4444-abcdef123456}", $diffUuid="{77777777-2222-3333-4444-abcdef123456}"
Local $launcherSettings="[launcher]" & @LF & "language=en" & @LF
Check(DirCreate($folder & "\Snapshots"),"create VM snapshot tree")
Check(DirCreate($root & "\data\.VirtualBox"),"create global registry folder")
Check(FileWrite($folder & "\disk.vdi","PRIMARY-DISK")<>0,"base disk exists")
Check(FileWrite($folder & "\Snapshots\snap.vdi","DIFFERENCING-DISK")<>0,"snapshot disk exists")
Check(WriteXml($root & "\data\launcher.ini",$launcherSettings),"launcher settings are also protected data")
Local $head='<VirtualBox xmlns="http://www.virtualbox.org/"><Machine name="Имя ВМ" uuid="' & $uuid & '" snapshotFolder="Snapshots" currentSnapshot="' & $snapshotUuid & '"><MediaRegistry><HardDisks>'
Local $media='<HardDisk uuid="' & $baseUuid & '" location="disk.vdi"/><HardDisk uuid="' & $diffUuid & '" location="Snapshots/snap.vdi"/>'
Local $tail='</HardDisks></MediaRegistry><Snapshots><Snapshot uuid="' & $snapshotUuid & '" name="Снимок"/></Snapshots></Machine></VirtualBox>'
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
Local $verified=_PVR_VerifyBackup($root,$backup)
Check($verified["status"]=="VERIFIED","entire matching backup accepted for exact rebind")
Check($verified["mode"]=="UNREGISTER_REGISTER","original stale entry requires both fixed commands")
Check(_PVR_StillExact($root,$verified),"frozen UUID and full snapshot/VDI bytes still match")
Check(_PVR_SameProof($verified,_PVR_VerifyBackup($root,$backup)),"displayed proof matches an independent fresh verification")
Check(StringLen($verified["backup_manifest_sha256"])=64,"original manifest identity frozen in proof")
Check(Not _PVR_CanRegister($root,$verified),"register cannot run while original registration remains")
Check(_PVR_BackupMatchesData($root,$backup),"source and backup have same all-file SHA-256 rows")
Check(StringInStr(_PVR_Text($verified),"verified")>0 Or _
      StringInStr(_PVR_Text($verified),"Проверена")>0,"backup verification described to user")
Check(FileRead($backup & "\data\Machines\Имя ВМ\Snapshots\snap.vdi")=="DIFFERENCING-DISK","snapshot bytes copied")
Check(FileRead($registry)==$regHead & $entry & $regTail,"backup never edits original registry")
Check(_PVR_Backup($root,$backup)["status"]=="BLOCKED","existing backup cannot be overwritten")
; A backup alone, a malformed map or a different confirmation is not consent.
Local $malformed[]
$malformed["status"]="VERIFIED"
Check(Not _PVR_SameProof(0,$verified),"missing confirmation refused")
Check(Not _PVR_SameProof($malformed,$verified),"incomplete proof refused without reading missing keys")
Check(Not _PVR_StillExact($root,$malformed),"malformed proof cannot authorize first command")
Check(Not _PVR_CanRegister($root,$malformed),"malformed proof cannot authorize register")
Check(Not _PVR_Rebound($root,$malformed),"malformed proof cannot claim completion")
Local $changedProof=$verified
$changedProof["backup_manifest_sha256"]="0000000000000000000000000000000000000000000000000000000000000000"
Check(Not _PVR_StillExact($root,$changedProof),"changed manifest identity invalidates previously confirmed proof")
$changedProof=$verified
$changedProof["mode"]="REGISTER_ONLY"
Check(Not _PVR_SameProof($changedProof,$verified),"confirmation binds the command mode")
Local $unconfirmed=_MS_New($root,"C:\unused-workspace")
Check(Not _MS_Start($unconfirmed,$backup),"backup without displayed proof cannot start")
Check($unconfirmed["detail"]=="rebind-confirmed-proof-changed" And $unconfirmed["mutex"]=0,"missing confirmation refused before helper or lock")
Local $changedSession=_MS_New($root,"C:\unused-workspace")
Check(Not _MS_Start($changedSession,$backup,$changedProof),"a different displayed mode cannot start")
Check($changedSession["detail"]=="rebind-confirmed-proof-changed" And $changedSession["mutex"]=0,"changed proof refused before preparation")
; Owned Prepare may rewrite global formatting/properties after raw bytes
; were bound by the pre-UAC confirmation. Registration identity stays exact.
Local $preparedRegistry=$regHead & @LF & $entry & '</MachineRegistry><SystemProperties defaultMachineFolder="C:\portable\Machines"/></Global></VirtualBox>'
Check(WriteXml($registry,$preparedRegistry),"owned-prepare global property rewrite fixture")
Local $preparedProof=_PVR_VerifyBackup($root,$backup)
Check($preparedProof["status"]=="VERIFIED" And $preparedProof["mode"]=="UNREGISTER_REGISTER","same stale registration survives profile property rewrite")
Check(Not _PVR_SameProof($verified,$preparedProof),"raw registry change before preparation requires new confirmation")
Check(_PVR_StillExact($root,$verified),"owned Prepare may rewrite profile while registration and VM bytes remain")
Check(WriteXml($registry,$regHead & StringReplace($entry,$uuid,"{ffffffff-2222-3333-4444-abcdef123456}") & $regTail),"changed registration UUID after prepare")
Check(Not _PVR_StillExact($root,$verified),"post-Prepare UUID drift still blocked")
Check(WriteXml($registry,$regHead & StringReplace($entry,$oldPath,$old & "\data\Machines\Other\Other.vbox") & $regTail),"changed registration path after prepare")
Check(Not _PVR_StillExact($root,$verified),"post-Prepare old-path drift still blocked")
Check(WriteXml($registry,$regHead & $entry & $entry & $regTail),"extra registration after prepare")
Check(Not _PVR_StillExact($root,$verified),"post-Prepare extra registration still blocked")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore original pre-Prepare registry")
; Simulate the observable filesystem state after a successful unregister.
; The original verified backup, not the empty registry, proves its identity.
Local $badRegistries[6]=[ _
    '<VirtualBox><Global/></VirtualBox>', _
    '<VirtualBox><Global><MachineRegistry/></Global><Global><MachineRegistry/></Global></VirtualBox>', _
    '<VirtualBox><Global><MachineRegistry/><MachineRegistry/></Global></VirtualBox>', _
    '<VirtualBox><Global><MachineRegistry/>' & $entry & '</Global></VirtualBox>', _
    $head & $media & $tail, _
    $regHead & '<Unexpected>' & $entry & '</Unexpected>' & $regTail]
For $i=0 To UBound($badRegistries)-1
    Check(WriteXml($registry,$badRegistries[$i]),"malformed registry structure fixture " & $i)
    Check(_PVR_Plan($root)["status"]=="BLOCKED","malformed registry is never a stale plan " & $i)
    Check(_PVR_VerifyBackup($root,$backup)["status"]=="BLOCKED","malformed registry is not an absent registration " & $i)
    Check(Not _PVR_CanRegister($root,$verified),"malformed registry cannot enable register " & $i)
Next
Local $badOriginal=$parent & "\Malformed original backup"
Check(_PBK_Create($root,$badOriginal)=0,"complete copy of malformed original registry fixture")
Check(_PVR_VerifyBackup($root,$badOriginal)["status"]=="BLOCKED","backup's misplaced registration also fails structure gate")
Check(WriteXml($registry,$regHead & $regTail),"registration absent between Oracle commands")
Check(_PVR_Plan($root)["status"]=="BLOCKED","unregistered machine alone is never a repair plan")
Local $resume=_PVR_VerifyBackup($root,$backup)
Check($resume["status"]=="VERIFIED" And $resume["mode"]=="REGISTER_ONLY","original backup permits exact register-only resume")
Check($resume["uuid"]==$verified["uuid"] And $resume["backup_manifest_sha256"]==$verified["backup_manifest_sha256"],"resume retains original UUID and backup manifest")
Check(_PVR_CanRegister($root,$verified),"successful first step may continue using original confirmed evidence")
Check(_PVR_CanRegister($root,$resume) And _PVR_StillExact($root,$resume),"new resume confirmation is frozen against the absent registry")
Check(Not _PVR_StillExact($root,$verified) And Not _PVR_SameProof($verified,$resume),"stale confirmation cannot silently switch to resume")
Check(Not _PVR_Rebound($root,$resume),"missing registration is never completion")
Local $emptyBackup=$parent & "\Копия без регистрации"
Check(_PBK_Create($root,$emptyBackup)=0,"independent backup of unregistered fixture created")
Check(_PVR_VerifyBackup($root,$emptyBackup)["status"]=="BLOCKED","backup without original stale entry cannot invent repair authority")
; Allow only the known Oracle profile churn, never a VM or launcher exemption.
Check(WriteXml($root & "\data\.VirtualBox\VirtualBox.xml-prev",$regHead & $entry & $regTail),"Oracle previous registry fixture")
Check(WriteXml($root & "\data\.VirtualBox\VBoxSVC.log","Oracle log"),"Oracle profile log fixture")
Check(WriteXml($root & "\data\.VirtualBox\VBoxSVC.log.1","Oracle rotated log"),"Oracle profile log rotation fixture")
Check(WriteXml($root & "\data\.VirtualBox\selectorwindow.log","Oracle Manager log"),"Oracle Manager profile log fixture")
Check(WriteXml($root & "\data\.VirtualBox\selectorwindow.log.10","Oracle Manager rotated log"),"Oracle Manager tenth rotation fixture")
Check(_PVR_CanRegister($root,$resume),"known profile registry and logs may change between commands")
Check(Not _PVR_BackupMatchesData($root,$backup),"ordinary full backup comparison remains exact")
Check(WriteXml($root & "\data\.VirtualBox\unexpected.log","not an Oracle exception"),"unknown profile file fixture")
Check(Not _PVR_CanRegister($root,$resume),"unknown profile file is not excluded")
FileDelete($root & "\data\.VirtualBox\unexpected.log")
Check(WriteXml($folder & "\VBoxSVC.log","VM-owned file"),"same log name inside VM fixture")
Check(Not _PVR_CanRegister($root,$resume),"log exemption cannot extend into VM directory")
FileDelete($folder & "\VBoxSVC.log")
Check(WriteXml($root & "\data\launcher.ini","changed launcher setting"),"changed launcher fixture")
Local $drift=_PVR_VerifyBackup($root,$backup)
Check($drift["status"]=="BLOCKED" And StringInStr($drift["reason"],"data\launcher.ini")>0,"changed launcher file reported with bounded relative path")
Check(Not _PVR_CanRegister($root,$resume),"launcher files remain bound to original backup")
Check(WriteXml($root & "\data\launcher.ini",$launcherSettings),"restore launcher fixture")
Check(WriteXml($config,StringReplace($head & $media & $tail,$snapshotUuid,"{88888888-2222-3333-4444-abcdef123456}")),"changed snapshot UUID at same count")
Check(Not _PVR_CanRegister($root,$resume),"snapshot identity drift prevents registration")
Check(WriteXml($config,StringReplace($head & $media & $tail,$diffUuid,"{99999999-2222-3333-4444-abcdef123456}")),"changed media UUID at same count")
Check(Not _PVR_CanRegister($root,$resume),"media identity drift prevents registration")
Check(WriteXml($config,$head & $media & $tail),"restore original metadata graph")
Check(WriteXml($folder & "\disk.vdi","PRIMARY-DISX"),"same-length base disk mutation")
Check(Not _PVR_CanRegister($root,$resume),"base disk SHA-256 drift prevents registration")
Check(WriteXml($folder & "\disk.vdi","PRIMARY-DISK"),"restore original base disk")
Check(WriteXml($folder & "\Snapshots\snap.vdi","DIFFERENCING-DISX"),"same-length differencing disk mutation")
Check(Not _PVR_CanRegister($root,$resume),"snapshot disk SHA-256 drift prevents registration")
Check(WriteXml($folder & "\Snapshots\snap.vdi","DIFFERENCING-DISK"),"restore original differencing disk")
Check(_PVR_CanRegister($root,$resume),"only exact restored original data remains eligible")
; Relative, already relocated registrations need no rebind.
Local $localEntry='<MachineEntry uuid="' & $uuid & '" src="..\Machines\Имя ВМ\Имя ВМ.vbox"/>'
Check(WriteXml($registry,$regHead & $localEntry & $regTail),"write ordinary local registry")
$plan=_PVR_Plan($root)
Check($plan["status"]=="NONE","already local registration is not stale")
Check(_PVR_Rebound($root,$verified),"registered same UUID and media chain read-only verified")
Check(_PVR_Rebound($root,$resume),"register-only resume has the same strict final postcondition")
Check(_PVR_VerifyBackup($root,$backup)["status"]=="NONE","repeated completed repair requires no command")
Check(Not _PVR_CanRegister($root,$verified) And Not _PVR_CanRegister($root,$resume),"completed registration cannot be repeated")
Check(Not _PVR_StillExact($root,$verified),"old-stale proof not reusable after registration")
Check(WriteXml($config,StringReplace($head & $media & $tail,$snapshotUuid,"{88888888-2222-3333-4444-abcdef123456}")),"post-register snapshot identity mutation")
Check(Not _PVR_Rebound($root,$verified),"same snapshot count cannot hide changed identity at completion")
Check(WriteXml($config,$head & $media & $tail),"restore completed VM metadata")
Check(WriteXml($folder & "\Snapshots\snap.vdi","DIFFERENCING-DISX"),"post-register disk byte mutation")
Check(Not _PVR_Rebound($root,$verified),"same media count cannot hide changed disk bytes at completion")
Check(WriteXml($folder & "\Snapshots\snap.vdi","DIFFERENCING-DISK"),"restore completed snapshot bytes")
; Ambiguous multiple registered VMs are not safe to repair automatically.
Check(WriteXml($registry,$regHead & $entry & $localEntry & $regTail),"write duplicate registration")
Check(_PVR_Plan($root)["status"]=="BLOCKED","second registration always blocks")
Check(Not _PVR_Rebound($root,$verified),"extra registered machine blocks rebound verification")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore stale registration")
; User media external to data cannot be called a complete file-copy.
Check(WriteXml($config,$head & $media & '<HardDisk location="E:\Other\private.vdi"/>' & $tail),"write external medium")
Check(_PVR_Plan($root)["status"]=="BLOCKED","external medium never accepted")
Check(WriteXml($config,$head & $media & $tail),"restore normal medium graph")
; This repair scope excludes saved memory, including snapshot memory.
Check(WriteXml($config,StringReplace($head,'<Machine name=','<Machine stateFile="Snapshots/memory.sav" name=') & $media & $tail),"write local saved-state reference")
Check(_PVR_Plan($root)["reason"]=="saved-state-or-unsafe-ancillary-path","saved VM is refused before a backup promise")
Check(WriteXml($config,$head & $media & StringReplace($tail,'<Snapshot uuid=','<Snapshot stateFile="E:\Other\memory.sav" uuid=')),"write external snapshot saved state")
Check(_PVR_Plan($root)["status"]=="BLOCKED","saved snapshot cannot bypass powered-off scope")
Check(WriteXml($config,StringReplace($head,'snapshotFolder="Snapshots"','snapshotFolder="E:\Other"') & $media & $tail),"write external snapshot destination")
Check(_PVR_Plan($root)["status"]=="BLOCKED","future snapshot folder must stay local")
Check(WriteXml($config,StringReplace($head,'<MediaRegistry>','<Hardware><NVRAM path="firmware.nvram"/></Hardware><MediaRegistry>') & $media & $tail),"write missing NVRAM path")
Check(_PVR_Plan($root)["status"]=="BLOCKED","missing NVRAM cannot be called backed up")
Check(WriteXml($folder & "\firmware.nvram","LOCAL-NVRAM"),"create local NVRAM fixture")
Check(_PVR_Plan($root)["status"]=="READY","present contained NVRAM can be included in a new full backup")
Check(WriteXml($config,StringReplace($head,'<MediaRegistry>','<Hardware><NVRAM path="E:\Other\firmware.nvram"/></Hardware><MediaRegistry>') & $media & $tail),"write external NVRAM path")
Check(_PVR_Plan($root)["status"]=="BLOCKED","external NVRAM cannot be excluded from preservation proof")
FileDelete($folder & "\firmware.nvram")
Check(WriteXml($config,$head & $media & $tail),"restore supported powered-off graph")
; Stale metadata forged with a different original UUID is refused.
Local $wrong='<MachineEntry uuid="{ffffffff-2222-3333-4444-abcdef123456}" src="' & $oldPath & '"/>'
Check(WriteXml($registry,$regHead & $wrong & $regTail),"write mismatched VM identity")
Check(_PVR_Plan($root)["status"]=="BLOCKED","old UUID cannot impersonate new VM")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore registry")
; Old disk still exists: user must not create two live machines with one UUID.
Check(DirCreate($old & "\data\Machines\Имя ВМ"),"create old collision folder")
Check(FileWrite($oldPath,"foreign config")<>0,"create old path collision")
Check(_PVR_Plan($root)["status"]=="BLOCKED","old live copy blocks repair")
Check(WriteXml($registry,$regHead & $regTail),"resume candidate with original path reappeared")
Check(_PVR_VerifyBackup($root,$backup)["status"]=="BLOCKED","old path reappearance also blocks fresh resume")
Check(Not _PVR_CanRegister($root,$resume),"old path reappearance blocks next register command")
FileDelete($oldPath)
Check(WriteXml($registry,'<!DOCTYPE VirtualBox [<!ENTITY leak SYSTEM "file:///C:/Windows/win.ini">]>' & $regHead & $entry & $regTail),"write XXE fixture")
Check(_PVR_Plan($root)["status"]=="BLOCKED","XXE/DOCTYPE blocks VM plan")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore safe XML")
; A .vbox path accepted by discovery must also fit the fixed command quoting
; policy, so a long path cannot fail only after the VM was unregistered.
Local $longRoot=$parent & "\LongRoot", $longName=""
Local $longPrefix=$longRoot & "\data\Machines\"
For $i=1 To 231-StringLen($longPrefix)-StringLen("\vm.vbox")
    $longName &= "x"
Next
Local $longFolder=$longPrefix & $longName, $longConfig=$longFolder & "\vm.vbox"
Check(StringLen($longConfig)=231 And _MS_Quote($longConfig)=="","full VM path crosses the established 230-character command limit")
Check(DirCreate($longFolder & "\Snapshots"),"create readable long-path VM fixture")
Check(DirCreate($longRoot & "\data\.VirtualBox"),"create long-path profile fixture")
Check(WriteXml($longFolder & "\disk.vdi","PRIMARY-DISK"),"long-path base disk fixture")
Check(WriteXml($longFolder & "\Snapshots\snap.vdi","DIFFERENCING-DISK"),"long-path differencing disk fixture")
Check(WriteXml($longConfig,$head & $media & $tail),"long-path VM config fixture")
Local $longEntry='<MachineEntry uuid="' & $uuid & '" src="' & $old & '\data\Machines\' & $longName & '\vm.vbox"/>'
Check(WriteXml($longRoot & "\data\.VirtualBox\VirtualBox.xml",$regHead & $longEntry & $regTail),"long-path stale registry fixture")
Check(_PVR_Plan($longRoot)["status"]=="BLOCKED","unquotable full VM path cannot reach a ready plan")
Local $longProof=$verified
$longProof["new_path"]=$longConfig
Check(Not _PVR_ProofValid($longProof),"frozen proof cannot smuggle an unquotable VM path")
; Ignored current profile files are still covered inside the full backup.
Check(WriteXml($backup & "\data\.VirtualBox\VBoxSVC.log","unverified extra backup byte"),"change original backup profile")
Check(Not _PBK_Verify($backup),"changed original backup no longer verifies")
Check(WriteXml($registry,$regHead & $regTail),"missing registration with damaged backup")
Check(_PVR_VerifyBackup($root,$backup)["status"]=="BLOCKED","changed backup cannot supply resume proof")
Check(Not _PVR_CanRegister($root,$resume),"old confirmed proof cannot bypass changed backup")
Check(WriteXml($registry,$regHead & $entry & $regTail),"restore original source registration")
FileDelete($folder & "\Snapshots\snap.vdi")
Check(_PVR_Plan($root)["status"]=="BLOCKED","missing snapshot disk blocks repair")
Check(FileRead($config)==$head & $media & $tail,"source machine never rewritten")
DirRemove($parent,1)
ConsoleWrite("Portable moved VM plan assertions: " & $checks & "; failed: " & $failed & @CRLF)
Exit ($failed>0)
