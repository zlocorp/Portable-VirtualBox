# End-to-end exercise of the actual compiled buttons and Oracle Manager.
# Test fixture commands operate only on the freshly created, empty, named VM.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PortableRoot,[switch]$SeparatePrivileges,[switch]$UnattendedConsentProbe,[switch]$MainLauncher,
    [string]$GuestIso='', [string]$GuestIsoSha256='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox') { throw 'Disposable hosted Windows required' }
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$runner=(Resolve-Path -LiteralPath $env:RUNNER_TEMP).Path.TrimEnd('\')+'\'
if (-not $root.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase)) { throw 'Root outside temporary host' }
if ($UnattendedConsentProbe -and -not $SeparatePrivileges) { throw 'Consent probe requires a medium frontend' }
if ($MainLauncher -and $SeparatePrivileges -and -not $UnattendedConsentProbe) {
    throw 'Main launcher UAC acceptance cannot be automated on hosted Windows'
}
if ($GuestIso) {
    if (-not $MainLauncher -or $SeparatePrivileges -or $UnattendedConsentProbe) {
        throw 'Guest ISO requires the actual main GUI on the disposable CI runner'
    }
    $isoFull=[IO.Path]::GetFullPath($GuestIso)
    if (-not $isoFull.StartsWith($runner,[StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $isoFull -PathType Leaf) -or
        $GuestIsoSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        (Get-FileHash -LiteralPath $isoFull -Algorithm SHA256).Hash.ToLowerInvariant() -ne $GuestIsoSha256.ToLowerInvariant()) {
        throw 'Guest ISO missing, outside disposable runner or SHA-256 mismatch'
    }
}
$out=Join-Path $env:RUNNER_TEMP 'manager-gui-proof'
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
$exe=Join-Path $root $(if($MainLauncher){'Portable-VirtualBox.exe'}else{'Portable-VirtualBox-Session-Test.exe'})
$runtime=Join-Path $root 'app64'
$cli=Join-Path $runtime 'VBoxManage.exe'
$protectedStore=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PortableVirtualBox.Experiment'
if ($SeparatePrivileges) {
    Add-Type -Path @((Join-Path $PSScriptRoot '../source/privilege/TokenFacts.cs'),(Join-Path $PSScriptRoot '../tests/windows/MediumProcess.cs'))
    $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $accessProbe=Join-Path $env:RUNNER_TEMP 'ProtectedWriteProbe.exe'
    & $csc /nologo /target:exe /platform:x64 ("/out:"+$accessProbe) (Join-Path $PSScriptRoot '../tests/windows/ProtectedWriteProbe.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Access probe compilation failed' }
    $helper=Join-Path $root 'Portable-VirtualBox-Helper-Test.exe'
    foreach($bad in @('Unrecognized 1 1',('Prepare '+$PID+' 1'))) {
        $p=Start-Process -FilePath $helper -ArgumentList $bad -Wait -PassThru
        if ($p.ExitCode -notin @(64,70)) { throw 'Helper accepted unauthorised controller or action' }
    }
    if (Test-Path -LiteralPath $protectedStore) { throw 'Negative helper calls wrote protected state' }
}
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ManagerUiProbe {
  public delegate bool Callback(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback f, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, Callback f, IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint id);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder b,int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr SendMessageTimeoutW(IntPtr h,uint m,UIntPtr w,StringBuilder b,uint flags,uint t,out UIntPtr r);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h,uint cmd);
  public static string Text(IntPtr h) {
    var b=new StringBuilder(8192); UIntPtr r;
    if(SendMessageTimeoutW(h,13,(UIntPtr)8192,b,2,1000,out r)==IntPtr.Zero) return "";
    return b.ToString();
  }
  public static IntPtr Window(int pid) {
    IntPtr found=IntPtr.Zero;
    EnumWindows((h,p)=> { uint id; GetWindowThreadProcessId(h,out id);
      if(id==pid && IsWindowVisible(h) && GetWindow(h,4)==IntPtr.Zero) { found=h; return false; } return true;
    },IntPtr.Zero); return found;
  }
  public static IntPtr Child(IntPtr window,string name,bool byClass) {
    IntPtr found=IntPtr.Zero;
    EnumChildWindows(window,(h,p)=> { var b=new StringBuilder(256); GetClassName(h,b,256);
      if((byClass ? b.ToString() : Text(h))==name) { found=h; return false; } return true;
    },IntPtr.Zero); return found;
  }
}
'@
function Window-For([Diagnostics.Process]$Process) {
    $Process.Refresh()
    if ($Process.HasExited) { throw "Controller exited early: $($Process.ExitCode)" }
    return [ManagerUiProbe]::Window($Process.Id)
}
function State-Of([Diagnostics.Process]$Process) {
    $window=Window-For $Process
    if ($window -eq [IntPtr]::Zero) { return '' }
    $edit=[ManagerUiProbe]::Child($window,'Edit',$true)
    if ($edit -eq [IntPtr]::Zero) { return '' }
    return ([ManagerUiProbe]::Text($edit) -split '\r?\n')[0]
}
function Await-State([Diagnostics.Process]$Process,[string]$Expected,[int]$Seconds=150) {
    $timer=[Diagnostics.Stopwatch]::StartNew(); $last=''
    while($timer.Elapsed.TotalSeconds -lt $Seconds) {
        $state=State-Of $Process
        if ($state -ne $last) { Write-Host "UI observed: $state"; $last=$state }
        if ($state -eq $Expected) { return }
        if ($state -in @('FAILED','BLOCKED') -and $state -ne $Expected) {
            throw "Controller $($Process.Id): $state, expected $Expected; $([ManagerUiProbe]::Text([ManagerUiProbe]::Child((Window-For $Process),'Edit',$true)))"
        }
        Start-Sleep -Milliseconds 150
    }
    throw "Timeout awaiting $Expected; actual $last"
}
function Click-Button([Diagnostics.Process]$Process,[string]$Caption) {
    $button=[ManagerUiProbe]::Child((Window-For $Process),$Caption,$false)
    if ($button -eq [IntPtr]::Zero -or -not [ManagerUiProbe]::IsWindowEnabled($button)) { throw "Button unavailable: $Caption" }
    if (-not [ManagerUiProbe]::PostMessageW($button,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) { throw "Cannot click $Caption" }
}
# Startup is asynchronous: the top-level window may exist before AutoIt
# has assigned localized button captions. Never bypass the disabled safety gate.
function Wait-MainButton([Diagnostics.Process]$Process,[int]$Seconds=20) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while($timer.Elapsed.TotalSeconds -lt $Seconds) {
        $window=Window-For $Process
        if ($window -ne [IntPtr]::Zero) {
            $button=[ManagerUiProbe]::Child($window,'Start / Stop VirtualBox',$false)
            if ($button -ne [IntPtr]::Zero) {
                if (-not [ManagerUiProbe]::IsWindowEnabled($button)) {
                    throw 'Main launcher Start/Stop disabled by safety gate; no automatic override'
                }
                return $button
            }
        }
        Start-Sleep -Milliseconds 150
    }
    throw ('Main launcher button not visible after '+$Seconds+'s; check GUI localization and initialization')
}
# The ordinary compiled EXE owns its normal GUI. Opening the Manager session
# is a genuine user click on its own primary window, not a separate test EXE.
function Open-SessionWindow([Diagnostics.Process]$Process) {
    if ($MainLauncher) {
        $button=Wait-MainButton $Process
        if (-not [ManagerUiProbe]::PostMessageW($button,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)) { throw 'Cannot open main launcher Manager session' }
    }
    Await-State $Process 'IDLE' 20
}
function Oracle([string]$Arguments,[string]$Label) {
    $log=Join-Path $out ($Label+'.stdout.txt'); $err=Join-Path $out ($Label+'.stderr.txt')
    $old=[Environment]::GetEnvironmentVariable('VBOX_USER_HOME','Process')
    try {
        $env:VBOX_USER_HOME=Join-Path $root 'data\.VirtualBox'
        if ($SeparatePrivileges) {
            $p=[MediumProcess]::Start($cli,$Arguments,(Split-Path $cli -Parent),$log,$err)
        } else {
            $p=Start-Process -FilePath $cli -ArgumentList $Arguments -WorkingDirectory (Split-Path $cli -Parent) -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError $err
        }
        try {
            if (-not $p.WaitForExit(40000)) { throw "Fixture command timed out: $Label" }
            if ($p.ExitCode -ne 0) { throw "Fixture $Label failed: $(Get-Content -LiteralPath $err -Raw)" }
        } finally { $p.Dispose() }
    } finally { [Environment]::SetEnvironmentVariable('VBOX_USER_HOME',$old,'Process') }
    return [string](Get-Content -LiteralPath $log -Raw)
}
function Observe-Manager {
    $found=@(Get-Process -Name VirtualBox -ErrorAction Stop)
    if ($found.Count -ne 1 -or $found[0].MainModule.FileName -ine (Join-Path $runtime 'VirtualBox.exe') -or
        [ManagerUiProbe]::Window($found[0].Id) -eq [IntPtr]::Zero) { throw 'No exact real Oracle Manager window' }
    if ($SeparatePrivileges) {
        $facts=[PortableVBox.TokenFacts]::Read($found[0].Id)
        if ($facts.Administrator -or $facts.Integrity -ne 8192) { throw 'Oracle Manager was elevated' }
        $facts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ('manager-token-'+$found[0].Id+'.json')) -Encoding utf8
    }
    return $found[0].Id
}
function Assert-Clean([string]$Label) {
    $services=@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | Where-Object PSChildName -match '^VBox')
    $processes=@(Get-Process | Where-Object ProcessName -match '^(VBox|VirtualBox)')
    if ($services.Count -ne 0 -or $processes.Count -ne 0 -or (Test-Path (Join-Path $env:SystemRoot 'System32\drivers\VBoxSup.sys'))) { throw "Not clean after $Label" }
}
function Start-Controller([string]$Label) {
    if ($SeparatePrivileges) {
        $args=if ($MainLauncher) { '--lang en' } else { '--lang en --separate-privileges' }
        $p=[MediumProcess]::Start($exe,$args,$root,(Join-Path $out ($Label+'.stdout.txt')),(Join-Path $out ($Label+'.stderr.txt')))
        [MediumProcess]::LastFacts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ($Label+'-token.json')) -Encoding utf8
        return $p
    }
    return Start-Process -FilePath $exe -ArgumentList '--lang en' -WorkingDirectory $root -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $out ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $out ($Label+'.stderr.txt'))
}
$front=$null; $other=$null; $badFront=$null
$proof=[ordered]@{source_commit=$env:GITHUB_SHA;real_manager_opened=$false;guest_survived_manager_close=$false;manager_reopened_with_guest=$false;second_controller_refused=$false;two_sessions_clean=$false;uuid_preserved=$false;guest_os_booted=$false;guest_iso_attached=$false;guest_64bit_cpu_configured=$false;guest_screen_capture=$false;guest_disk_io_confirmed=$false;virtual_disk_created=$false;disk_preserved_after_cleanup=$false;snapshot_created=$false;snapshot_preserved_after_cleanup=$false;interactive_uac_consent_verified=$false;unattended_ui_responsive=$false;main_entrypoint_tested=[bool]$MainLauncher}
try {
    Assert-Clean 'initial baseline'
    if ($SeparatePrivileges) {
        # A forged user manifest must not bless modified elevated DLL inputs.
        $payload=Join-Path $root 'app64\VBoxRT.dll'
        $original=[IO.File]::ReadAllBytes($payload)
        $manifestPath=Join-Path $root 'app64\.prepared.json'
        $manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
        try {
            $changed=[byte[]]$original.Clone();$changed[128]=$changed[128] -bxor 1
            [IO.File]::WriteAllBytes($payload,$changed)
            $forged=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $row=$forged.files | Where-Object path -eq 'VBoxRT.dll'
            $row.size=(Get-Item -LiteralPath $payload).Length
            $row.sha256=(Get-FileHash -LiteralPath $payload).Hash.ToLowerInvariant()
            $forged | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding utf8
            $badFront=Start-Controller 'tampered-payload'
            Open-SessionWindow $badFront
            Click-Button $badFront 'Start VirtualBox'
            if ($UnattendedConsentProbe) {
                # Hosted Windows cannot supply a human response on UAC's secure
                # desktop. Assert the medium GUI remains RESPONSIVE while its
                # separate request process waits; never call this UAC acceptance.
                Await-State $badFront 'CONSENT_PREPARE' 25
                Start-Sleep -Seconds 2
                if ((State-Of $badFront) -ne 'CONSENT_PREPARE') { throw 'Consent state lost without user action' }
                Assert-Clean 'no unapproved elevated effects'
                $proof.unattended_ui_responsive=$true
                $proof.main_uac_request_pending=[bool]$MainLauncher
                Write-Host 'PASS: actual compiled frontend stayed responsive during runas request; unattended Windows did not approve/cancel consent'
                return
            }
            Await-State $badFront 'FAILED' 90
            Assert-Clean 'tampered DLL refusal'
            Click-Button $badFront 'Close'
            if (-not $badFront.WaitForExit(10000) -or $badFront.ExitCode -ne 3) { throw 'Failed payload controller did not leave safely' }
            $badFront.Dispose()
            $proof["tampered_payload_refused"]=$true
        } finally {
            [IO.File]::WriteAllBytes($payload,$original)
            [IO.File]::WriteAllBytes($manifestPath,$manifestBytes)
        }
    }
    $front=Start-Controller 'controller'
    Open-SessionWindow $front
    Click-Button $front 'Start VirtualBox'
    Await-State $front 'MANAGER_OPEN'
    if ($SeparatePrivileges) {
        $runtime=Join-Path $protectedStore ('pvbox-manager-'+$front.Id+'-1\app64')
        $cli=Join-Path $runtime 'VBoxManage.exe'
    }
    $manager1=Observe-Manager
    $proof.real_manager_opened=$true
    if ($SeparatePrivileges) {
        $firstSession=Join-Path $protectedStore ('pvbox-manager-'+$front.Id+'-1')
        $p=[MediumProcess]::Start($accessProbe,('"'+$firstSession+'"'),$root,(Join-Path $out 'acl.stdout.txt'),(Join-Path $out 'acl.stderr.txt'))
        try { if (-not $p.WaitForExit(15000) -or $p.ExitCode -ne 0) { throw 'Medium user could modify protected helper/payload/ownership state' } } finally { $p.Dispose() }
        $proof["protected_cache_write_denied"]=$true
        $sds=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
        if (([string]$sds.ImagePath).Trim().Trim('"') -ine (Join-Path $firstSession 'app64\VBoxSDS.exe')) { throw 'Service executes from user-writable root' }
        $proof["service_uses_protected_copy"]=$true
    }
    # The second controller must not mutate another live session.
    $other=Start-Controller 'second-controller'
    Open-SessionWindow $other
    Click-Button $other 'Start VirtualBox'
    Await-State $other 'BLOCKED' 20
    if ((Observe-Manager) -ne $manager1) { throw 'Refused controller changed the live Manager' }
    Click-Button $other 'Close'
    if ($MainLauncher) { Start-Sleep -Milliseconds 250;Click-Button $other 'Close' }
    if (-not $other.WaitForExit(10000) -or $other.ExitCode -ne $(if($MainLauncher){2}else{0})) { throw 'Refused controller did not exit normally' }
    $proof.second_controller_refused=$true
    $guestType=if ($GuestIso) { 'Linux_64' } else { 'Other' }
    $created=Oracle ('createvm --name pvbox_manager_gui_fixture --ostype '+$guestType+' --register') 'create'
    if ($created -notmatch '(?im)^UUID:\s*([0-9a-f-]{36})\s*$') { throw 'No exact fixture UUID' }
    $uuid=$Matches[1]
    $null=Oracle ('modifyvm '+$uuid+' --memory 128 --nic1 none --audio-driver none') 'configure'
    # Create a real portable VDI under the disposable fixture only.
    $disk=Join-Path $root 'data\Machines\pvbox_manager_gui_fixture\portable-fixture.vdi'
    if (Test-Path -LiteralPath $disk) { throw 'Fixture VDI unexpectedly pre-exists' }
    $null=Oracle ('createmedium disk --filename "'+$disk+'" --size 64 --format VDI') 'create-virtual-disk'
    if (-not (Test-Path -LiteralPath $disk -PathType Leaf) -or
        (Get-Item -LiteralPath $disk).Length -lt 4096) { throw 'Fresh VDI absent or too small' }
    $null=Oracle ('storagectl '+$uuid+' --name SATA --add sata --controller IntelAhci') 'create-storage-controller'
    $null=Oracle ('storageattach '+$uuid+' --storagectl SATA --port 0 --device 0 --type hdd --medium "'+$disk+'"') 'attach-virtual-disk'
    $diskInfo=Oracle ('showmediuminfo disk "'+$disk+'"') 'medium-info'
    if ($diskInfo -notmatch '(?im)^Storage format:\s+VDI' -or
        $diskInfo -notmatch '(?im)^UUID:\s+[a-f0-9-]{36}') { throw 'Oracle did not register the VDI' }
    $proof.virtual_disk_created=$true
    if ($GuestIso) {
        # Attach real guest boot media, never execute it on the Windows host.
        $null=Oracle ('modifyvm '+$uuid+' --memory 256 --x86-long-mode on --boot1 dvd --boot2 disk --boot3 none --boot4 none') 'configure-guest-boot'
        $null=Oracle ('storageattach '+$uuid+' --storagectl SATA --port 1 --device 0 --type dvddrive --medium "'+$isoFull+'"') 'attach-guest-iso'
        $proof.guest_iso_attached=$true
    }
    $null=Oracle ('startvm '+$uuid+' --type headless') 'start-guest'
    $running=Oracle ('showvminfo '+$uuid+' --machinereadable') 'guest-running'
    if ($running -notmatch '(?m)^VMState="running"') { throw 'Fixture did not reach running' }
    if ($GuestIso) {
        if ($running -notmatch '(?m)^longmode="on"') {
            throw 'Guest CPU long mode is not enabled: refusing false x86-64 boot evidence'
        }
        $proof.guest_64bit_cpu_configured=$true
        # Oracle screenshotpng captures the *guest display*. It is visual
        # evidence only, not proof of completed Linux boot or guest disk I/O.
        Start-Sleep -Seconds 25
        $screenshot=Join-Path $out 'guest-boot-alpine.png'
        if (Test-Path -LiteralPath $screenshot) { throw 'Guest screenshot pre-exists' }
        $null=Oracle ('controlvm '+$uuid+' screenshotpng "'+$screenshot+'"') 'alpine-guest-screen'
        $png=[IO.File]::ReadAllBytes($screenshot)
        if ($png.Length -lt 1024 -or [BitConverter]::ToString($png,0,8) -ne '89-50-4E-47-0D-0A-1A-0A') {
            throw 'Guest display screenshot is not a nonempty PNG'
        }
        $proof.guest_screen_capture=$true
        # Alpine's ISO console uses root without a password. Send all keys
        # through Oracle's supported virtual keyboard to the guest, never a
        # host shell. The marker can only be accepted from raw disk readback.
        $marker='PVBOX_GUEST_WRITE_OK_20261027'
        $guestCommand='echo '+$marker+' | dd of=/dev/sda bs=512 seek=2048 conv=notrunc; sync'
        $null=Oracle ('controlvm '+$uuid+' keyboardputstring root') 'guest-root-login'
        $null=Oracle ('controlvm '+$uuid+' keyboardputscancode 1c 9c') 'guest-login-enter'
        Start-Sleep -Seconds 3
        $null=Oracle ('controlvm '+$uuid+' keyboardputstring "'+$guestCommand+'"') 'guest-disk-write-command'
        $null=Oracle ('controlvm '+$uuid+' keyboardputscancode 1c 9c') 'guest-command-enter'
        Start-Sleep -Seconds 8
        $guestCommandScreen=Join-Path $out 'guest-disk-command.png'
        $null=Oracle ('controlvm '+$uuid+' screenshotpng "'+$guestCommandScreen+'"') 'guest-write-screen'
        Write-Host 'Guest disk write requested via virtual keyboard; not yet trusted until offline sector readback'
    }
    if ($SeparatePrivileges) {
        $guest=Get-Process -Name VBoxHeadless -ErrorAction Stop
        $facts=[PortableVBox.TokenFacts]::Read($guest.Id)
        if ($facts.Administrator -or $facts.Integrity -ne 8192) { throw 'Guest inherited elevated rights' }
        $facts | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'guest-token.json') -Encoding utf8
        $proof["frontend_manager_guest_medium"]=$true
        $p=Start-Process -FilePath $helper -ArgumentList ('Finish '+$front.Id+' 1') -PassThru -Wait
        if ($p.ExitCode -ne 70 -or (Get-Service VBoxSup).Status -ne 'Running') { throw 'Privileged helper accepted cleanup while VM runs' }
        $proof["live_guest_cleanup_refused"]=$true
    }
    Click-Button $front 'Finish session'
    Await-State $front 'WAIT_GUESTS' 40
    $running=Oracle ('showvminfo '+$uuid+' --machinereadable') 'guest-after-manager-close'
    if ($running -notmatch '(?m)^VMState="running"' -or (Get-Service VBoxSup).Status -ne 'Running') { throw 'Manager close stopped guest or driver' }
    $proof.guest_survived_manager_close=$true
    Click-Button $front 'Reopen Manager'
    Await-State $front 'MANAGER_OPEN' 40
    $manager2=Observe-Manager
    if ($manager2 -eq $manager1) { throw 'Manager process was not really replaced' }
    $proof.manager_reopened_with_guest=$true
    Click-Button $front 'Finish session'
    Await-State $front 'WAIT_GUESTS' 40
    $null=Oracle ('controlvm '+$uuid+' poweroff') 'fixture-poweroff'
    Await-State $front 'CLEAN'
    Assert-Clean 'first session'
    $vm=Join-Path $root 'data\Machines\pvbox_manager_gui_fixture\pvbox_manager_gui_fixture.vbox'
    if (-not (Test-Path -LiteralPath $vm)) { throw 'Fixture configuration lost' }
    if (-not (Test-Path -LiteralPath $disk -PathType Leaf)) { throw 'Portable VDI deleted during driver cleanup' }
    $proof.disk_preserved_after_cleanup=$true
    $vmBefore=(Get-FileHash -LiteralPath $vm).Hash
    # Repeat a session, preserve the registered UUID, no need to invent a
    # boot receipt for a Manager-only second cycle.
    Click-Button $front 'Start VirtualBox'
    Await-State $front 'MANAGER_OPEN'
    if ($SeparatePrivileges) {
        $runtime=Join-Path $protectedStore ('pvbox-manager-'+$front.Id+'-2\app64')
        $cli=Join-Path $runtime 'VBoxManage.exe'
    }
    $null=Observe-Manager
    $again=Oracle ('showvminfo '+$uuid+' --machinereadable') 'same-uuid-second-session'
    if ($again -notmatch ('(?mi)^UUID="'+[regex]::Escape($uuid)+'"') -or $again -notmatch '(?m)^VMState="poweroff"') { throw 'Second Manager session lost fixture UUID/state' }
    $proof.uuid_preserved=$true
    $againDisk=Oracle ('showmediuminfo disk "'+$disk+'"') 'same-virtual-disk'
    if ($againDisk -notmatch '(?im)^Storage format:\s+VDI' -or
        $againDisk -notmatch '(?im)^UUID:\s+[a-f0-9-]{36}') { throw 'VDI not registered after restart' }
    if ($GuestIso) {
        # Read the *same VDI* after actual VM shutdown and a full driver
        # teardown/restart. VBoxManage clones the logical disk to RAW;
        # only the exact fixed guest-written sector marker proves guest I/O.
        $raw=Join-Path $out 'guest-vdi-readback.raw'
        if (Test-Path -LiteralPath $raw) { throw 'Disk readback unexpectedly exists' }
        $null=Oracle ('clonemedium disk "'+$disk+'" "'+$raw+'" --format RAW') 'guest-vdi-offline-readback'
        try {
            $fs=[IO.File]::Open($raw,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                [void]$fs.Seek(2048*512,[IO.SeekOrigin]::Begin)
                $expected=[Text.Encoding]::ASCII.GetBytes($marker)
                $observed=New-Object byte[] $expected.Length
                $n=$fs.Read($observed,0,$observed.Length)
                if ($n -ne $expected.Length -or
                    [Text.Encoding]::ASCII.GetString($observed) -cne $marker) {
                    throw 'No guest-written VDI sector marker after restart and cleanup'
                }
                $proof.guest_disk_io_confirmed=$true
                $proof.guest_os_booted=$true
                Write-Host 'PASS: real Alpine guest booted and wrote verified bytes to the portable VDI'
            } finally { $fs.Dispose() }
        } finally {
            # This disposable RAW copy is not part of the portable VM, and
            # must not be included in public artifacts or user ZIP files.
            Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue
        }
    }
    # Snapshot is taken while the guest is powered off; Oracle creates a
    # differencing VDI under this VM's portable Snapshots directory.
    $null=Oracle ('snapshot '+$uuid+' take portable-baseline') 'take-snapshot'
    $snapshotList=Oracle ('snapshot '+$uuid+' list --machinereadable') 'inspect-snapshot'
    if ($snapshotList -notmatch 'portable-baseline') { throw 'Oracle did not list the snapshot' }
    $proof.snapshot_created=$true
    Click-Button $front 'Finish session'
    Await-State $front 'CLEAN'
    Assert-Clean 'second session'
    $snapshotDir=Join-Path $root 'data\Machines\pvbox_manager_gui_fixture\Snapshots'
    if (-not (Test-Path -LiteralPath $disk -PathType Leaf) -or
        -not (Test-Path -LiteralPath $snapshotDir -PathType Container) -or
        @(Get-ChildItem -LiteralPath $snapshotDir -File -Filter '*.vdi').Count -lt 1 -or
        -not (Test-Path -LiteralPath $vm -PathType Leaf)) {
        throw 'Portable snapshot media/configuration lost after own-driver cleanup'
    }
    $proof.snapshot_preserved_after_cleanup=$true
    $proof.two_sessions_clean=$true
    $proof.uuid=$uuid
    $proof.manager_pids=@($manager1,$manager2)
    $proof.vm_config_present_after_cleanup=(Test-Path -LiteralPath $vm)
    $evidenceRoot=if ($SeparatePrivileges) { $protectedStore } else { $env:RUNNER_TEMP }
    $sessionFolders=@(Get-ChildItem -LiteralPath $evidenceRoot -Directory -Filter ('pvbox-manager-'+$front.Id+'-*'))
    if ($sessionFolders.Count -ne 2) { throw 'Expected two independent session receipts' }
    foreach ($folder in $sessionFolders) {
        if ($SeparatePrivileges -and ((Test-Path -LiteralPath (Join-Path $folder.FullName 'app64')) -or (Test-Path -LiteralPath (Join-Path $folder.FullName 'code')) -or -not (Test-Path -LiteralPath (Join-Path $folder.FullName 'payload-removed.json')))) { throw 'Privileged payload/code cache retained after successful cleanup' }
        $clean=Get-Content -LiteralPath (Join-Path $folder.FullName 'cleanup\cleanup-results.json') -Raw | ConvertFrom-Json
        if (-not $clean.cleanup_verified -or -not $clean.driver_package_removed -or $clean.cleanup_basis -ne $(if($SeparatePrivileges){'PrivilegedSession'}else{'Session'}) -or $clean.vm_powered_off_before_cleanup) { throw 'Incorrect cleanup evidence or false VM boot claim' }
    }
    if ($SeparatePrivileges) {
        $helpers=@($sessionFolders | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'helper-*.json' -File } | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
        $successful=@($helpers | Where-Object childExit -eq 0)
        if ($successful.Count -ne 4) { throw 'Missing two elevated prepare/finish pairs' }
        foreach($h in $helpers) {
            if (-not $h.helper.Administrator -or $h.helper.Integrity -lt 12288 -or $h.controller.Administrator -or $h.controller.Integrity -ne 8192) { throw 'Privilege separation proof inconsistent' }
        }
        $proof["only_helper_elevated"]=$true
        $proof["helper_verbs"]='ShellExecuteExW runas'
        $proof["interactive_uac_consent_verified"]=$false
    }
    Click-Button $front 'Close'
    if ($MainLauncher) { Start-Sleep -Milliseconds 250;Click-Button $front 'Close' }
    if (-not $front.WaitForExit(10000) -or $front.ExitCode -ne $(if($MainLauncher){2}else{0})) { throw 'Completed frontend did not exit cleanly' }
    Write-Host 'PASS: real compiled GUI Start/Finish/Reopen, real Oracle Manager, live guest preserved, second controller refused, two exact-owned cleanups, same UUID retained'
} catch {
    $proof.error=$_.Exception.Message
    throw
} finally {
    $proof | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'manager-gui-proof.json') -Encoding utf8
    if ($null -ne $other) { $other.Dispose() }
    if ($null -ne $front) { $front.Dispose() }
    if ($null -ne $badFront) { $badFront.Dispose() }
    # No speculative cleanup or global kills on failure. Disposable host only.
}
