# Embedded in the fixed compiled helper; never chosen by a frontend argument.
# System effects only. User profile configuration and Manager run in the frontend.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Finish','Recover')][string]$Action,
    [Parameter(Mandatory)][string]$PortableRoot,
    [Parameter(Mandatory)][string]$SessionDir,
    [Parameter(Mandatory)][int]$ControllerPid,
    [Parameter(Mandatory)][long]$ControllerCreated,
    [Parameter(Mandatory)][ValidateSet('Portable-VirtualBox.exe','Portable-VirtualBox-Session-Test.exe')][string]$FrontendName,
    [Parameter(Mandatory)][ValidateSet('Portable-VirtualBox-Helper-Test.exe','Portable-VirtualBox-Helper-Alpha.exe')][string]$HelperName,
    [ValidateRange(0,2147483647)][int]$OriginalControllerPid = 0,
    [ValidateRange(0,9223372036854775807)][long]$OriginalControllerCreated = 0,
    [switch]$IncompletePreparation,
    [ValidateSet('None','Stage','Start','Sds')][string]$TestBreakAfter = 'None'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# The system worker is always launched from the OS-owned x64 Windows PowerShell,
# never an optionally installed pwsh or user-selected executable.
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'Only Windows PowerShell 5.1 is accepted for the protected effect worker'
}
# The candidate mode is supplied only by the pinned C# helper after its
# independent Windows workstation/owner/SHA-256 checks. Environment markers
# below are anti-accident checks, NOT authority to mutate system resources.
# Pure locator validation only. The parent helper owns filesystem identity,
# ACL and hash admission and supplies RUNNER_TEMP in its cleared environment.
# Do not resolve CommonApplicationData again in the stripped child environment.
function Assert-CanonicalAlphaLocator([string]$Store,[string]$Session) {
    foreach ($value in @($Store,$Session)) {
        if ([string]::IsNullOrEmpty($value) -or $value.Length -gt 240 -or
            $value -cnotmatch '\A[A-Za-z]:\\' -or
            $value.Substring(3) -match '[\x00-\x1f\x7f-\x9f/:*?"<>|~]') {
            throw 'Protected alpha locator is not canonical'
        }
        foreach ($part in $value.Substring(3).Split([char]'\')) {
            if ($part.Length -eq 0 -or $part -eq '.' -or $part -eq '..' -or
                $part.EndsWith('.') -or $part.Trim() -cne $part -or
                $part -match '\A(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\.|\z)') {
                throw 'Protected alpha locator is not canonical'
            }
        }
    }
    if ($Store.Substring($Store.LastIndexOf('\')+1) -ine 'PortableVirtualBox.Alpha' -or
        -not [string]::Equals($Store,$Session.Substring(0,$Session.LastIndexOf('\')),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Protected alpha session base mismatched'
    }
}
function Assert-PortableFixedHelper {
    if ($env:PVBOX_FIXED_HELPER_MODE -ne 'ALPHA') { throw 'Not a candidate fixed-helper worker' }
    Assert-CanonicalAlphaLocator -Store $env:RUNNER_TEMP -Session $SessionDir
    if (-not [Environment]::Is64BitProcess -or -not [Environment]::Is64BitOperatingSystem) {
        throw 'Only Windows x64 is permitted'
    }
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 19041) {
        throw 'Not a supported Windows 10/11 workstation'
    }
}
if ($env:PVBOX_FIXED_HELPER_MODE -eq 'ALPHA') {
    if ($FrontendName -ne 'Portable-VirtualBox.exe' -or $HelperName -ne 'Portable-VirtualBox-Helper-Alpha.exe') {
        throw 'Candidate helper/frontend pair mismatched'
    }
    Assert-PortableFixedHelper
} elseif ($env:PVBOX_FIXED_HELPER_MODE -eq 'CI') {
    if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
        $env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox' -or $env:RUNNER_OS -ne 'Windows') {
        throw 'Disposable Windows only'
    }
} else { throw 'Unrecognized fixed-helper build mode' }
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Elevated helper token required' }
$root=(Resolve-Path -LiteralPath $PortableRoot).Path
$session=(Resolve-Path -LiteralPath $SessionDir).Path
$app=Join-Path $session 'app64'
$parentId=(Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
$parent=[Diagnostics.Process]::GetProcessById($parentId)
try {
    if ($parent.MainModule.FileName -ine (Join-Path $root $HelperName)) { throw 'Not the exact fixed compiled helper' }
} finally { $parent.Dispose() }
$caller=[Diagnostics.Process]::GetProcessById($ControllerPid)
try {
    if ($caller.MainModule.FileName -ine (Join-Path $root $FrontendName) -or
        $caller.StartTime.ToFileTimeUtc() -ne $ControllerCreated) { throw 'Controller generation changed' }
    $controllerImage=$caller.MainModule.FileName
} finally { $caller.Dispose() }
# Missing PID means the old controller is gone. A recycled PID or an
# inaccessible process is UNKNOWN and forbids all recovery mutations.
function Test-OriginalControllerAbsent([int]$OldPid) {
    if ($OldPid -le 0) { return $false }
    $observed=Get-CimInstance Win32_Process -Filter "ProcessId=$OldPid" -ErrorAction Stop
    return $null -eq $observed
}
function VBox-Processes { return @(Get-Process -ErrorAction Stop | Where-Object ProcessName -match '^(VBox|VirtualBox)') }
# Optional evidence only: normalize captured facts without observing the system.
# This format is never an admission, cleanup or child-lifetime authority.
function ConvertTo-SdsDiagnosticLines([hashtable]$Facts) {
    function Get-DiagnosticToken($Value,[string[]]$Allowed,[string]$Fallback) {
        if ($Value -is [string] -and $Allowed -ccontains $Value) { return $Value }
        return $Fallback
    }
    function Get-DiagnosticNumber($Value,[long]$Minimum,[long]$Maximum) {
        if (($Value -is [int] -or $Value -is [long]) -and $Value -ge $Minimum -and $Value -le $Maximum) {
            return [Convert]::ToString([long]$Value,[Globalization.CultureInfo]::InvariantCulture)
        }
        return 'unavailable'
    }
    if ($null -eq $Facts) { $Facts=@{} }
    $launch=Get-DiagnosticToken $Facts['Launch'] @('not_attempted','returned','error','unknown') 'unknown'
    $handle=Get-DiagnosticToken $Facts['Handle'] @('not_observed','nonzero','zero','error','unknown') 'unknown'
    $wait=Get-DiagnosticToken $Facts['Wait'] @('not_observed','within_deadline','exceeded','unconfirmed') 'not_observed'
    $completion=Get-DiagnosticToken $Facts['Completion'] @('not_observed','confirmed','unconfirmed') 'not_observed'
    $exitCode=Get-DiagnosticNumber $Facts['ExitCode'] ([int]::MinValue) ([int]::MaxValue)
    $elapsed=Get-DiagnosticNumber $Facts['ElapsedMs'] 0 ([long]::MaxValue)
    $preflight=Get-DiagnosticToken $Facts['Preflight'] @('not_observed','absent','present','error','unknown') 'unknown'
    $source=Get-DiagnosticToken $Facts['RegistrySource'] @('gate','not_observed') 'not_observed'
    $gate=Get-DiagnosticToken $Facts['Gate'] @('not_reached','missing','observation_error','identity_mismatch','identity_match') 'not_reached'
    $query='not_observed'; $image='unavailable'; $type='unavailable'; $start='unavailable'; $account='unavailable'
    $errorCategory='unknown'; $hresult='unavailable'
    if ($source -ceq 'gate') {
        $query='unknown'
        $registryError=$Facts['RegistryError']
        if ($null -ne $registryError) {
            $query='error'
            if ($registryError -is [Management.Automation.ErrorRecord]) {
                # Recognize only the original fixed Get-ItemProperty missing-key
                # shape. No error text parsing or later registry query is used.
                try {
                    # Keep rejecting PowerShell overrides, but PSProperty alone
                    # also admits hidden CLR getters. Read only these fixed base
                    # members, whose nonvirtual getters cannot dispatch to input.
                    $members=@{
                        Exception=[Management.Automation.ErrorRecord].GetProperty('Exception')
                        FullyQualifiedErrorId=[Management.Automation.ErrorRecord].GetProperty('FullyQualifiedErrorId')
                        CategoryInfo=[Management.Automation.ErrorRecord].GetProperty('CategoryInfo')
                        TargetObject=[Management.Automation.ErrorRecord].GetProperty('TargetObject')
                        HResult=[Exception].GetProperty('HResult')
                        Category=[Management.Automation.ErrorCategoryInfo].GetProperty('Category')
                    }
                    foreach ($member in $members.Values) {
                        if ($null -eq $member -or $null -eq $member.GetGetMethod() -or $member.GetGetMethod().IsVirtual) {
                            throw 'Unsupported diagnostic base member'
                        }
                    }
                    foreach ($name in @('Exception','FullyQualifiedErrorId','CategoryInfo','TargetObject')) {
                        if ($registryError.PSObject.Properties[$name] -isnot [Management.Automation.PSProperty]) {
                            throw 'Extended diagnostic error member'
                        }
                    }
                    $exception=$members['Exception'].GetValue($registryError,$null)
                    $categoryInfo=$members['CategoryInfo'].GetValue($registryError,$null)
                    if ($exception -isnot [Exception] -or $categoryInfo -isnot [Management.Automation.ErrorCategoryInfo] -or
                        $exception.PSObject.Properties['HResult'] -isnot [Management.Automation.PSProperty] -or
                        $categoryInfo.PSObject.Properties['Category'] -isnot [Management.Automation.PSProperty]) {
                        throw 'Extended diagnostic exception/category member'
                    }
                    $hresult=Get-DiagnosticNumber ($members['HResult'].GetValue($exception,$null)) ([int]::MinValue) ([int]::MaxValue)
                    if ($exception -is [Management.Automation.ItemNotFoundException] -and
                        ($members['FullyQualifiedErrorId'].GetValue($registryError,$null)) -ceq 'PathNotFound,Microsoft.PowerShell.Commands.GetItemPropertyCommand' -and
                        ($members['Category'].GetValue($categoryInfo,$null)) -eq [Management.Automation.ErrorCategory]::ObjectNotFound -and
                        ($members['TargetObject'].GetValue($registryError,$null)) -is [string] -and
                        ($members['TargetObject'].GetValue($registryError,$null)) -ceq 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS') {
                        $query='missing'; $errorCategory='not_found'
                    } elseif ($exception -is [UnauthorizedAccessException]) { $errorCategory='access_denied'
                    } elseif ($exception -is [Security.SecurityException]) { $errorCategory='security'
                    } elseif ($exception -is [IO.IOException]) { $errorCategory='io'
                    } elseif ($exception -is [Exception]) { $errorCategory='other' }
                } catch { $query='error'; $errorCategory='unknown'; $hresult='unavailable' }
            }
        } elseif ($Facts['RegistryValue'] -is [Management.Automation.PSCustomObject]) {
            # The original registry result carries note properties, not getters.
            # Do not invoke scripted/adapted getters on malformed input.
            $observed=@{}
            foreach ($name in @('ImagePath','Type','Start','ObjectName')) {
                try {
                    $property=$Facts['RegistryValue'].PSObject.Properties[$name]
                    if ($property -is [Management.Automation.PSNoteProperty]) { $observed[$name]=$property.Value }
                } catch { }
            }
            if ($observed.Count -gt 0) { $query='present' }
            $type=Get-DiagnosticNumber $observed['Type'] ([int]::MinValue) ([int]::MaxValue)
            $start=Get-DiagnosticNumber $observed['Start'] ([int]::MinValue) ([int]::MaxValue)
            $imageValue=$observed['ImagePath']; $requested=$Facts['RequestedImage']
            if ($null -ne $imageValue) {
                if ($imageValue -isnot [string] -or [string]::IsNullOrWhiteSpace($imageValue)) { $image='malformed'
                } elseif ($requested -is [string] -and -not [string]::IsNullOrWhiteSpace($requested)) {
                    # Copy the primitive string before instance operations so
                    # input-supplied PowerShell methods cannot run.
                    $imageText=[string]::new([char[]]$imageValue)
                    if ([string]::Equals($imageText.Trim().Trim('"'),$requested,[StringComparison]::OrdinalIgnoreCase)) { $image='matches_requested'
                    } else { $image='different' }
                }
            }
            $accountValue=$observed['ObjectName']
            if ($null -ne $accountValue) {
                if ($accountValue -isnot [string] -or [string]::IsNullOrWhiteSpace($accountValue)) { $account='malformed'
                } elseif ([string]::Equals($accountValue,'LocalSystem',[StringComparison]::OrdinalIgnoreCase)) { $account='LocalSystem'
                } else { $account='different' }
            }
        }
    }
    $lines=[string[]]@(
        "PVBOX_SDS_DIAG_V1 kind=process authority=none operation=register requested_image=protected_app/VBoxSDS.exe launched_image=not_observed launch=$launch handle=$handle wait=$wait completion=$completion exit_code=$exitCode elapsed_ms=$elapsed deadline_ms=30000",
        "PVBOX_SDS_DIAG_V1 kind=registry authority=none key=VBoxSDS preflight=$preflight source=$source query=$query image=$image type=$type start=$start account=$account gate=$gate error=$errorCategory exception_hresult=$hresult"
    )
    # Validate the complete records before any emission, including the explicit
    # CRLF the writer will add. Never truncate a token into different evidence.
    $total=0
    foreach ($line in $lines) {
        $bytes=[Text.Encoding]::UTF8.GetByteCount($line+"`r`n")
        if ($bytes -gt 1024 -or $line -cmatch '[^\x20-\x7e]') { throw 'Diagnostic record bounds exceeded' }
        $total+=$bytes
    }
    if ($total -gt 2048) { throw 'Diagnostic total bounds exceeded' }
    return $lines
}
function Write-SdsRegistrationDiagnostics([hashtable]$Facts) {
    try { $lines=@(ConvertTo-SdsDiagnosticLines $Facts) } catch { return }
    # Recheck both complete lines before writing, so an unexpected renderer
    # result cannot add writes or exceed either cap. Rendering failure is silent.
    try {
        if ($lines.Count -ne 2) { return }
        $total=0
        foreach ($line in $lines) {
            if ($line -isnot [string]) { return }
            $bytes=[Text.Encoding]::UTF8.GetByteCount($line+"`r`n")
            if ($bytes -gt 1024 -or $line -cmatch '[^\x20-\x7e]') { return }
            $total+=$bytes
        }
        if ($total -gt 2048) { return }
    } catch { return }
    foreach ($line in $lines) {
        try { [Console]::Out.Write($line+"`r`n") } catch { }
    }
}
# Loaded only from the exact embedded resource installed and hash-leased by
# the parent helper. Never load the mutable portable-root helper assembly.
function Initialize-ProtectedEffects {
    if ($env:PVBOX_FIXED_HELPER_MODE -notin @('CI','ALPHA')) { throw 'Unknown protected SDS mode' }
    # Resolve before GetNewClosure: generated dynamic modules have no trustworthy
    # defining-file locator. Never adopt a preloaded assembly or caller path.
    $definition=$MyInvocation.MyCommand.ScriptBlock.File
    if ([string]::IsNullOrEmpty($definition) -or -not [IO.Path]::IsPathRooted($definition) -or
        [IO.Path]::GetFileName($definition) -cne 'privileged_session_worker.ps1') {
        throw 'Unknown protected SDS function definition'
    }
    $purpose=if ($Action -ceq 'Prepare') { 'Preparation' }
        elseif ($Action -ceq 'Finish' -or ($Action -ceq 'Recover' -and -not $IncompletePreparation)) { 'FullCleanup' }
        elseif ($Action -ceq 'Recover' -and $IncompletePreparation) { 'PartialCleanup' }
        else { throw 'Unknown protected effect purpose' }
    $bridgePath=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($definition)) 'PortableVBox.SdsBridge.dll'))
    $existing=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'PortableVBox.SdsBridge' })
    if ($existing.Count -ne 0) { throw 'Unexpected preloaded SDS bridge assembly' }
    $assembly=[Reflection.Assembly]::LoadFrom($bridgePath)
    if ($assembly.Location -cne $bridgePath) { throw 'SDS bridge assembly origin changed' }
    $facade=$assembly.GetType('PortableVBox.SdsBridge',$true,$false)
    $contextType=$assembly.GetType('PortableVBox.FixedEffectContext',$true,$false)
    $purposeType=$assembly.GetType('PortableVBox.EffectPurpose',$true,$false)
    $sdsType=$assembly.GetType('PortableVBox.SdsOperation',$true,$false)
    $driverType=$assembly.GetType('PortableVBox.DriverOperation',$true,$false)
    foreach ($type in @($facade,$contextType,$purposeType,$sdsType,$driverType)) {
        if (-not [object]::ReferenceEquals($type.Assembly,$assembly)) { throw 'SDS bridge type origin changed' }
    }
    $context=$facade::Open([Enum]::Parse($purposeType,$purpose,$false))
    if ($null -eq $context -or -not [object]::ReferenceEquals($context.GetType(),$contextType)) {
        throw 'Protected effect context identity changed'
    }
    $exactContext=$context
    $sdsCall={
        param([ValidateSet('Register','UnregisterFull','UnregisterPartial')][string]$Operation,[int]$TimeoutSeconds)
        if (-not [object]::ReferenceEquals($context,$exactContext) -or
            -not [object]::ReferenceEquals($context.GetType(),$contextType) -or
            -not [object]::ReferenceEquals($contextType.Assembly,$assembly) -or
            -not [object]::ReferenceEquals($sdsType.Assembly,$assembly)) {
            throw 'Protected effect context identity changed'
        }
        return $context.RunSds([Enum]::Parse($sdsType,$Operation,$false),$TimeoutSeconds)
    }.GetNewClosure()
    $driverCall={
        param([ValidateSet('AddSupPackage','StartSup','StopSup','RemoveSupPackage','DeleteSupService')][string]$Operation,[int]$TimeoutSeconds)
        if (-not [object]::ReferenceEquals($context,$exactContext) -or
            -not [object]::ReferenceEquals($context.GetType(),$contextType) -or
            -not [object]::ReferenceEquals($contextType.Assembly,$assembly) -or
            -not [object]::ReferenceEquals($driverType.Assembly,$assembly)) {
            throw 'Protected effect context identity changed'
        }
        return $context.RunDriver([Enum]::Parse($driverType,$Operation,$false),$TimeoutSeconds)
    }.GetNewClosure()
    return @{Sds=$sdsCall;Driver=$driverCall}
}
function Run-Sds([string]$Argument,[string]$Label,[hashtable]$DiagnosticFacts=$null) {
    if ($Argument -cne '--regservice' -or $Label -cne 'sds-register') { throw 'Unknown fixed SDS registration selector' }
    if ($env:PVBOX_FIXED_HELPER_MODE) {
        if ($env:PVBOX_FIXED_HELPER_MODE -notin @('CI','ALPHA')) { throw 'Unknown protected SDS mode' }
        try { $result=Invoke-ProtectedSds -Operation Register -TimeoutSeconds 30 } catch {
            # The bridge can throw after measured child exit (capture/file/query).
            # An atomic failed call alone does not identify its launch stage.
            try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['Launch']='unknown' } } catch { }
            throw
        }
        try {
            if ($null -ne $DiagnosticFacts) {
                $DiagnosticFacts['Launch']='returned';$DiagnosticFacts['Handle']='nonzero'
                $DiagnosticFacts['Wait']=if ($result.WithinDeadline) { 'within_deadline' } else { 'exceeded' }
                $DiagnosticFacts['Completion']='confirmed';$DiagnosticFacts['ElapsedMs']=$result.ElapsedMs
            }
        } catch { }
        if (-not $result.WithinDeadline) { throw 'SDS operation exceeded safety deadline; child exited, state requires inspection' }
        if (-not $result.ExitCodeKnown) { throw 'SDS process exit code unavailable' }
        try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['ExitCode']=$result.ExitCode } } catch { }
        if ($result.ExitCode -ne 0) { throw 'SDS operation unconfirmed; retain resources' }
        return
    }
    # Separate legacy standalone test path; never a fallback from bridge failure.
    $timer=$null
    if ($null -ne $DiagnosticFacts) {
        try { $timer=[Diagnostics.Stopwatch]::StartNew() } catch { }
    }
    # Launch remains outside the existing process try/finally. A launch error
    # does not establish that no child was created or repair its lifetime.
    try {
        $p=Start-Process -FilePath (Join-Path $app 'VBoxSDS.exe') -ArgumentList $Argument -WorkingDirectory $app -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $session ($Label+'.stdout.txt')) -RedirectStandardError (Join-Path $session ($Label+'.stderr.txt'))
    } catch {
        try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['Launch']='error' } } catch { }
        throw
    }
    try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['Launch']='returned' } } catch { }
    try {
        try { $ownedHandle=$p.Handle } catch {
            try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['Handle']='error' } } catch { }
            throw
        }
        try {
            if ($null -ne $DiagnosticFacts) {
                $DiagnosticFacts['Handle']=if ($ownedHandle -isnot [IntPtr]) { 'unknown' } elseif ($ownedHandle -eq [IntPtr]::Zero) { 'zero' } else { 'nonzero' }
            }
        } catch { }
        if ($ownedHandle -eq [IntPtr]::Zero) { throw 'SDS process handle unavailable' }
        try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['Wait']='unconfirmed'; $DiagnosticFacts['Completion']='unconfirmed' } } catch { }
        if (-not $p.WaitForExit(30000)) {
            try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['Wait']='exceeded' } } catch { }
            # Registration/unregistration is a persistent Windows service
            # mutation. Retain the exact child even when it runs too long.
            $p.WaitForExit()
            try {
                if ($null -ne $DiagnosticFacts) {
                    $DiagnosticFacts['Completion']='confirmed'
                    if ($null -ne $timer) { $DiagnosticFacts['ElapsedMs']=$timer.ElapsedMilliseconds }
                }
            } catch { }
            throw 'SDS operation exceeded safety deadline; child exited, state requires inspection'
        }
        try {
            if ($null -ne $DiagnosticFacts) {
                $DiagnosticFacts['Wait']='within_deadline'; $DiagnosticFacts['Completion']='confirmed'
                if ($null -ne $timer) { $DiagnosticFacts['ElapsedMs']=$timer.ElapsedMilliseconds }
            }
        } catch { }
        $exitCode=$p.ExitCode
        try { if ($null -ne $DiagnosticFacts) { $DiagnosticFacts['ExitCode']=$exitCode } } catch { }
        if ($exitCode -ne 0) { throw 'SDS operation unconfirmed; retain resources' }
    } finally { $p.Dispose() }
}
# One admitted context, created before stage/start/cleanup. The callable closures
# retain exact objects, not a mutable script/global cache or assembly-name lookup.
$protectedCalls=Initialize-ProtectedEffects
Set-Item -LiteralPath Function:Invoke-ProtectedSds -Value $protectedCalls.Sds
Set-Item -LiteralPath Function:Invoke-ProtectedDriver -Value $protectedCalls.Driver
$protectedCalls=$null
try {
    if ($Action -eq 'Prepare') {
        # Helper created and fsync'd protected prepare-intent.json BEFORE
        # launching any system action. This worker only emits post-effect proof.
        if (-not (Test-Path -LiteralPath (Join-Path $session 'prepare-intent.json') -PathType Leaf)) {
            throw 'Missing durable protected pre-effect intent'
        }
        & (Join-Path $PSScriptRoot 'vbox_sup_standalone.ps1') -AppDir $app -OutputDirectory (Join-Path $session 'stage')
        if ($TestBreakAfter -eq 'Stage') { throw 'CI_TEST_BREAK_AFTER_STAGE: protected installation report committed' }
        & (Join-Path $PSScriptRoot 'vbox_sup_start_owned.ps1') -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -OutputDirectory (Join-Path $session 'start')
        # Independently require the durable activation proof before SDS,
        # user-profile operations or any prepared-session receipt.
        $started=Get-Content -LiteralPath (Join-Path $session 'start\sup-start-results.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if ($started.experiment -ne 'owned-standalone-VBoxSup-start' -or
            $started.start_status -ne 'EXITED' -or $started.start_exit_code -ne 0 -or
            $started.driver_running -isnot [bool] -or $started.driver_running -ne $true -or
            $started.initial_status -ne 'Stopped' -or $started.service_status_after -ne 'Running' -or
            $started.wmi_driver_state -ne 'Running' -or
            $started.no_other_vbox_services_before -isnot [bool] -or $started.no_other_vbox_services_before -ne $true) {
            throw 'Driver activation proof unconfirmed; preparation denied'
        }
        if ($TestBreakAfter -eq 'Start') { throw 'CI_TEST_BREAK_AFTER_START: protected driver start report committed' }
        $sdsFacts=$null
        try {
            $sdsFacts=@{RequestedImage=(Join-Path $app 'VBoxSDS.exe');Preflight='not_observed';Launch='not_attempted';Handle='not_observed';Wait='not_observed';Completion='not_observed';ExitCode=$null;ElapsedMs=$null;RegistrySource='not_observed';RegistryValue=$null;RegistryError=$null;Gate='not_reached'}
        } catch { }
        $sdsPreflight=$null; $sdsPreflightError=$null; $sds=$null; $sdsReadReturned=$false; $sdsReadError=$null
        $sdsIdentityDiffers=$null; $sdsIdentityError=$null
        try {
            try {
                if (($sdsPreflight=Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS')) { throw 'SDS appeared before our explicit registration' }
            } catch { $sdsPreflightError=$_; throw }
            Run-Sds '--regservice' 'sds-register' $sdsFacts
            try {
                $sds=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS' -ErrorAction Stop
            } catch { $sdsReadError=$_; throw }
            $sdsReadReturned=$true
            try {
                if (($sdsIdentityDiffers=(([string]$sds.ImagePath).Trim().Trim('"') -ine (Join-Path $app 'VBoxSDS.exe') -or
                    $sds.Type -ne 16 -or $sds.Start -ne 3 -or $sds.ObjectName -ne 'LocalSystem'))) { throw 'SDS registration identity differs' }
            } catch { $sdsIdentityError=$_; throw }
            # The final SDS effect is recorded independently BEFORE the final
            # prepared session receipt. A crash between registration and this marker
            # remains ambiguous and requires manual handling, not guessed cleanup.
            [ordered]@{schema=1;registered=$true;protected_app=$app;
                controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();
                sds_image=(Join-Path $app 'VBoxSDS.exe');source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'sds-registered.json') -Encoding utf8
            if ($TestBreakAfter -eq 'Sds') { throw 'CI_TEST_BREAK_AFTER_SDS: protected service registration marker committed' }
            [ordered]@{schema=1;portable_root=$root;protected_app=$app;controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();controller_image=$controllerImage;prepared=$true;source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $session 'session.json') -Encoding utf8
            Write-Host 'PRIVILEGED_PREPARED_WITHOUT_USER_PROFILE_EXECUTION'
        } finally {
            # Only translate observations after the original marker/receipt or
            # refusal. Optional reporting cannot replace a propagating error.
            try {
                if ($null -ne $sdsFacts) {
                    $sdsFacts['Preflight']=if ($sdsPreflight -isnot [bool]) { if ($null -ne $sdsPreflightError) { 'error' } else { 'unknown' } } elseif ($sdsPreflight) { 'present' } else { 'absent' }
                    if ($sdsReadReturned -or $null -ne $sdsReadError) {
                        $sdsFacts['RegistrySource']='gate'; $sdsFacts['RegistryValue']=$sds
                        if ($sdsIdentityDiffers -is [bool]) {
                            $sdsFacts['Gate']=if ($sdsIdentityDiffers) { 'identity_mismatch' } else { 'identity_match' }
                        } else {
                            $sdsFacts['Gate']='observation_error'
                            $sdsFacts['RegistryError']=if ($null -ne $sdsReadError) { $sdsReadError } else { $sdsIdentityError }
                        }
                    }
                }
                Write-SdsRegistrationDiagnostics $sdsFacts
            } catch { }
        }
    } else {
        if ($Action -eq 'Recover' -and $IncompletePreparation) {
            # A protected intent alone is not a driver ownership receipt. Stage
            # result must have committed; earlier and uncertain phases refuse.
            if (-not (Test-Path -LiteralPath (Join-Path $session 'stage\sup-standalone.json') -PathType Leaf)) {
                throw 'Incomplete preparation has no exclusive driver staging proof'
            }
            if (Test-Path -LiteralPath (Join-Path $session 'session.json')) { throw 'Completed session is not an interrupted preparation' }
            $intent=Get-Content -LiteralPath (Join-Path $session 'prepare-intent.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            # Name the failing invariant without printing private user paths,
            # SIDs or protected receipt contents. All checks remain fail-closed.
            $reject=@()
            if ($intent.schema -ne 1) { $reject+='intent-schema' }
            if ($intent.phase -ne 'pre-system-effects') { $reject+='intent-phase' }
            if ($intent.portable_root -ine $root) { $reject+='portable-root' }
            if ($intent.protected_app -ine $app) { $reject+='protected-app' }
            if ($intent.controller_pid -ne $OriginalControllerPid) { $reject+='former-pid' }
            if ($intent.controller_created_filetime -ne $OriginalControllerCreated.ToString()) { $reject+='former-created' }
            if ($OriginalControllerPid -le 0 -or $OriginalControllerPid -eq $ControllerPid) { $reject+='former-generation' }
            if (-not (Test-OriginalControllerAbsent $OriginalControllerPid)) { $reject+='former-still-live' }
            if (Test-Path -LiteralPath (Join-Path $session 'cleanup')) { $reject+='cleanup-already-exists' }
            if (Test-Path -LiteralPath (Join-Path $session 'partial-recovery-quiescent.json')) { $reject+='replay-marker' }
            if ($reject.Count -ne 0) {
                throw ('Incomplete preparation protected owner mismatch or replay: ' + ($reject -join ','))
            }
            if (@(VBox-Processes).Count -ne 0) { throw 'Active VBox activity; partial preparation recovery denied' }
            $partialProof=Join-Path $session 'partial-recovery-quiescent.json'
            [ordered]@{schema=1;experiment='partial-protected-manager-quiescent';portable_root=$root;
                protected_app=$app;original_controller_pid=$OriginalControllerPid;
                original_controller_created_filetime=$OriginalControllerCreated.ToString();
                controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();
                controller_image=$controllerImage;no_vbox_processes_verified=$true;source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath $partialProof -Encoding utf8
            if (-not (Test-OriginalControllerAbsent $OriginalControllerPid)) { throw 'Old owner reappeared before partial recovery' }
            & (Join-Path $PSScriptRoot 'vbox_sup_partial_cleanup.ps1') -AppDir $app -SessionDir $session -PartialRecoveryReport $partialProof -OutputDirectory (Join-Path $session 'cleanup') -OriginalControllerCreated $OriginalControllerCreated
            $clean=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $clean.cleanup_verified -or -not $clean.driver_package_removed -or @(VBox-Processes).Count -ne 0) {
                throw 'Partial preparation teardown unconfirmed'
            }
            Write-Host 'PRIVILEGED_INCOMPLETE_PREPARATION_RECOVERED'
            exit 0
        }
        $receipt=Get-Content -LiteralPath (Join-Path $session 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($receipt.schema -ne 1 -or -not $receipt.prepared -or $receipt.portable_root -ine $root -or $receipt.protected_app -ine $app) {
            throw 'Not our protected session'
        }
        if ($Action -eq 'Recover') {
            if ($OriginalControllerPid -le 0 -or $OriginalControllerPid -eq $ControllerPid -or $OriginalControllerCreated -le 0 -or
                $receipt.controller_pid -ne $OriginalControllerPid -or
                $receipt.controller_created_filetime -ne $OriginalControllerCreated.ToString() -or
                $receipt.controller_image -ine $controllerImage -or
                -not (Test-OriginalControllerAbsent $OriginalControllerPid) -or
                (Test-Path -LiteralPath (Join-Path $session 'cleanup'))) {
                throw 'Untrusted original controller for crash recovery'
            }
        } else {
            if ($receipt.controller_pid -ne $ControllerPid -or $receipt.controller_created_filetime -ne $ControllerCreated.ToString() -or
                $receipt.controller_image -ine $controllerImage) { throw 'Changed controller for regular cleanup' }
        }
        if (@(VBox-Processes).Count -ne 0) { throw 'VM/Manager/background activity still present; refusing cleanup' }
        $proof=Join-Path $session $(if ($Action -eq 'Recover') { 'recovery-quiescent.json' } else { 'quiescent-session.json' })
        if ((Test-Path -LiteralPath $proof) -or (Test-Path -LiteralPath (Join-Path $session 'quiescent-session.json')) -or
            (Test-Path -LiteralPath (Join-Path $session 'recovery-quiescent.json'))) { throw 'Refusing cleanup replay' }
        if ($Action -eq 'Recover') {
            # The new live controller's identity and missing former owner are
            # independently revalidated by the cleanup script before effects.
            [ordered]@{experiment='orphan-manager-quiescent';portable_root=$root;protected_app=$app;
                stage_report=(Join-Path $session 'stage\sup-standalone.json');driver_start_report=(Join-Path $session 'start\sup-start-results.json');
                original_controller_pid=$OriginalControllerPid;original_controller_created_filetime=$OriginalControllerCreated.ToString();
                controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();controller_image=$controllerImage;
                no_vbox_processes_verified=$true;source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath $proof -Encoding utf8
            if (-not (Test-OriginalControllerAbsent $OriginalControllerPid)) { throw 'Old controller reappeared before cleanup' }
            & (Join-Path $PSScriptRoot 'vbox_sup_cleanup.ps1') -AppDir $app -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -DriverStartReport (Join-Path $session 'start\sup-start-results.json') -RecoveryReport $proof -OutputDirectory (Join-Path $session 'cleanup')
        } else {
            [ordered]@{experiment='privilege-separated-manager-quiescent';portable_root=$root;protected_app=$app;
                stage_report=(Join-Path $session 'stage\sup-standalone.json');driver_start_report=(Join-Path $session 'start\sup-start-results.json');
                controller_pid=$ControllerPid;controller_created_filetime=$ControllerCreated.ToString();controller_image=$controllerImage;
                no_vbox_processes_verified=$true;source_commit=$env:GITHUB_SHA} |
                ConvertTo-Json | Set-Content -LiteralPath $proof -Encoding utf8
            & (Join-Path $PSScriptRoot 'vbox_sup_cleanup.ps1') -AppDir $app -StandaloneReport (Join-Path $session 'stage\sup-standalone.json') -DriverStartReport (Join-Path $session 'start\sup-start-results.json') -PrivilegedReport $proof -OutputDirectory (Join-Path $session 'cleanup')
        }
        $clean=Get-Content -LiteralPath (Join-Path $session 'cleanup\cleanup-results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $clean.cleanup_verified -or -not $clean.driver_package_removed -or @(VBox-Processes).Count -ne 0) { throw 'Cleanup not confirmed' }
        Write-Host 'PRIVILEGED_SESSION_CLEAN'
    }
} catch { Write-Error $_; exit 1 }
exit 0
