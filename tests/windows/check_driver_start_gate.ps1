# Executes the real activation/Prepare blocks with Windows effects replaced at
# their boundaries. Never invokes SCM, registry writes, SDS or Oracle binaries.
param([string]$Repository, [ValidateSet('Start','Privileged','Manager')][string]$Target)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$env:GITHUB_STEP_SUMMARY=''
function Parse-Script([string]$Name) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository ('scripts/'+$Name)),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    return $ast
}
function Assert-True($Value,[string]$Message) { if (-not $Value) { throw $Message } }
# Select declarations only; never execute the protected worker's preamble.
function Get-RequiredFunction([string]$Source,[string]$Name) {
    $tokens=$null; $errors=$null
    $parsed=[Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Diagnostic function source did not parse' }
    $matches=@($parsed.FindAll({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    },$true))
    if ($matches.Count -ne 1) { throw "Expected exactly one required diagnostic function: $Name; found $($matches.Count)" }
    return [scriptblock]::Create($matches[0].Extent.Text)
}
function Test-SdsDiagnostics([string]$Source) {
    # Latch forbidden observations outside diagnostic exception guards. A
    # swallowed stub error must never make an accidental system query pass.
    $diagnosticObservations=@{Calls=0}
    function Get-Service { $diagnosticObservations.Calls++; throw 'Forbidden diagnostic SCM query' }
    function Get-ItemProperty { $diagnosticObservations.Calls++; throw 'Forbidden diagnostic registry query' }
    function Test-Path { $diagnosticObservations.Calls++; throw 'Forbidden diagnostic existence query' }
    function Get-Process { $diagnosticObservations.Calls++; throw 'Forbidden diagnostic process query' }
    function Get-CimInstance { $diagnosticObservations.Calls++; throw 'Forbidden diagnostic CIM query' }
    function Start-Process { $diagnosticObservations.Calls++; throw 'Forbidden diagnostic process launch' }
    # Catch missing, duplicate and invalid declarations rather than quietly
    # selecting a different function or dot-sourcing elevated initialization.
    foreach ($sample in @('function Selected {','function Other {}','function Selected {}; function Selected {}')) {
        $rejected=$false
        try { $null=Get-RequiredFunction $sample 'Selected' } catch { $rejected=$true }
        Assert-True $rejected 'Unsafe diagnostic AST selection was accepted'
    }
    . (Get-RequiredFunction "throw 'protected preamble must not run'; function Selected { 'declaration only' }" 'Selected')
    Assert-True ((Selected) -ceq 'declaration only') 'AST loader executed protected initialization'
    . (Get-RequiredFunction $Source 'ConvertTo-SdsDiagnosticLines')
    . (Get-RequiredFunction $Source 'Write-SdsRegistrationDiagnostics')

    $emptyProcess='PVBOX_SDS_DIAG_V1 kind=process authority=none operation=register requested_image=protected_app/VBoxSDS.exe launched_image=not_observed launch=unknown handle=unknown wait=not_observed completion=not_observed exit_code=unavailable elapsed_ms=unavailable deadline_ms=30000'
    $emptyRegistry='PVBOX_SDS_DIAG_V1 kind=registry authority=none key=VBoxSDS preflight=unknown source=not_observed query=not_observed image=unavailable type=unavailable start=unavailable account=unavailable gate=not_reached error=unknown exception_hresult=unavailable'
    function Assert-Records($Lines,[string]$Label) {
        Assert-True ($Lines.Count -eq 2) "$Label did not render exactly two records"
        Assert-True ($Lines[0] -cmatch '^PVBOX_SDS_DIAG_V1 kind=process authority=none ') "$Label lost fixed process record"
        Assert-True ($Lines[1] -cmatch '^PVBOX_SDS_DIAG_V1 kind=registry authority=none ') "$Label lost fixed registry record"
        $total=0
        foreach ($line in $Lines) {
            Assert-True ($line -is [string] -and $line -cnotmatch '[^\x20-\x7e]') "$Label emitted controls or Unicode"
            $bytes=[Text.Encoding]::UTF8.GetByteCount($line+"`r`n")
            Assert-True ($bytes -le 1024) "$Label exceeded record byte cap including CRLF"
            $total+=$bytes
        }
        Assert-True ($total -le 2048) "$Label exceeded total byte cap including CRLF"
    }
    foreach ($facts in @($null,@{})) {
        $lines=@(ConvertTo-SdsDiagnosticLines $facts)
        Assert-Records $lines 'Unavailable facts'
        Assert-True ($lines[0] -ceq $emptyProcess -and $lines[1] -ceq $emptyRegistry) 'Unavailable facts became observations or zero'
    }
    $requested='private/request/VBoxSDS.exe'
    $valid=@{RequestedImage=$requested;Preflight='absent';Launch='returned';Handle='nonzero';Wait='within_deadline';Completion='confirmed';ExitCode=0;ElapsedMs=1234L;RegistrySource='gate';RegistryValue=[pscustomobject]@{ImagePath=('"'+$requested+'"');Type=16;Start=3;ObjectName='LocalSystem'};RegistryError=$null;Gate='identity_match'}
    $validProcess='PVBOX_SDS_DIAG_V1 kind=process authority=none operation=register requested_image=protected_app/VBoxSDS.exe launched_image=not_observed launch=returned handle=nonzero wait=within_deadline completion=confirmed exit_code=0 elapsed_ms=1234 deadline_ms=30000'
    $validRegistry='PVBOX_SDS_DIAG_V1 kind=registry authority=none key=VBoxSDS preflight=absent source=gate query=present image=matches_requested type=16 start=3 account=LocalSystem gate=identity_match error=unknown exception_hresult=unavailable'
    $lines=@(ConvertTo-SdsDiagnosticLines $valid)
    Assert-Records $lines 'Valid facts'
    Assert-True ($lines[0] -ceq $validProcess -and $lines[1] -ceq $validRegistry) 'Valid facts lost fixed field order or normalized values'

    # Every allowed state round-trips; invented/case-changed tokens do not.
    foreach ($sample in @(
        @{Key='Launch';Field='launch';Values=@('not_attempted','returned','error','unknown')},
        @{Key='Handle';Field='handle';Values=@('not_observed','nonzero','zero','error','unknown')},
        @{Key='Wait';Field='wait';Values=@('not_observed','within_deadline','exceeded','unconfirmed')},
        @{Key='Completion';Field='completion';Values=@('not_observed','confirmed','unconfirmed')},
        @{Key='Preflight';Field='preflight';Values=@('not_observed','absent','present','error','unknown')},
        @{Key='RegistrySource';Field='source';Values=@('gate','not_observed')},
        @{Key='Gate';Field='gate';Values=@('not_reached','missing','observation_error','identity_mismatch','identity_match')}
    )) {
        foreach ($value in $sample.Values) {
            $facts=$valid.Clone(); $facts[$sample.Key]=$value
            $lines=@(ConvertTo-SdsDiagnosticLines $facts)
            Assert-Records $lines 'Allowed enum'
            Assert-True (($lines -join ' ').Contains(' '+$sample.Field+'='+$value+' ')) 'Allowed diagnostic token was replaced'
        }
    }
    # PowerShell permits method decoration even on an Int64. Formatting must
    # use the primitive numeric value, never an input-supplied ToString method.
    $decorated=([long]42) | Add-Member ScriptMethod ToString { param($culture) 'PRIVATE_NUMERIC_METHOD' } -Force -PassThru
    $facts=$valid.Clone(); $facts.ExitCode=$decorated; $facts.ElapsedMs=$decorated
    $lines=@(ConvertTo-SdsDiagnosticLines $facts)
    Assert-True ($lines[0].Contains(' exit_code=42 elapsed_ms=42 ') -and ($lines -join ' ') -cnotmatch 'PRIVATE') 'Numeric decoration leaked raw input'

    $stringEffects=@{Calls=0}
    $decoratedImage=('  "'+$requested.ToUpperInvariant()+'"  ') | Add-Member ScriptMethod Trim { param($characters) $stringEffects.Calls++; throw 'PRIVATE_TRIM_METHOD' } -Force -PassThru
    $facts=$valid.Clone(); $facts.RegistryValue=[pscustomobject]@{ImagePath=$decoratedImage;Type=16;Start=3;ObjectName='localsystem'}
    $lines=@(ConvertTo-SdsDiagnosticLines $facts)
    Assert-True ($lines[1].Contains(' image=matches_requested type=16 start=3 account=LocalSystem ') -and $stringEffects.Calls -eq 0) 'Renderer invoked an input-supplied string method'

    # These tests catch coercion (including fabricated zero), range mistakes,
    # raw input leaks, and culture-dependent numeric stringification.
    $oldCulture=[Threading.Thread]::CurrentThread.CurrentCulture
    $oldUiCulture=[Threading.Thread]::CurrentThread.CurrentUICulture
    try {
        $hostile=[Globalization.CultureInfo]::GetCultureInfo('ar-SA').Clone()
        $hostile.NumberFormat.NegativeSign='PRIVATE_NEGATIVE'
        $hostile.NumberFormat.PositiveSign='PRIVATE_POSITIVE'
        $hostile.NumberFormat.NumberGroupSeparator='PRIVATE_GROUP'
        $hostile.NumberFormat.NumberDecimalSeparator='PRIVATE_DECIMAL'
        [Threading.Thread]::CurrentThread.CurrentCulture=$hostile
        [Threading.Thread]::CurrentThread.CurrentUICulture=$hostile
        foreach ($sample in @(
            @{Value=[int]::MinValue;Want='-2147483648'},@{Value=[int]::MaxValue;Want='2147483647'},
            @{Value=[long]-2147483648;Want='-2147483648'},@{Value=[long]2147483647;Want='2147483647'},
            @{Value=[long]::MinValue;Want='unavailable'},@{Value=[long]::MaxValue;Want='unavailable'},
            @{Value=[long]-2147483649;Want='unavailable'},@{Value=[long]2147483648;Want='unavailable'},
            @{Value=[uint32]16;Want='unavailable'},@{Value=[int16]16;Want='unavailable'},@{Value='0';Want='unavailable'},@{Value=0.0;Want='unavailable'},@{Value=$false;Want='unavailable'},@{Value=$null;Want='unavailable'}
        )) {
            $facts=$valid.Clone(); $facts.ExitCode=$sample.Value
            $facts.RegistryValue=[pscustomobject]@{ImagePath=$requested;Type=$sample.Value;Start=$sample.Value;ObjectName='LocalSystem'}
            $lines=@(ConvertTo-SdsDiagnosticLines $facts)
            Assert-Records $lines 'Int32 primitive/range'
            Assert-True ($lines[0].Contains(' exit_code='+$sample.Want+' ')) 'ExitCode primitive/range/culture normalization failed'
            Assert-True ($lines[1].Contains(' type='+$sample.Want+' start='+$sample.Want+' ')) 'Registry Int32 primitive/range/culture normalization failed'
        }
        foreach ($sample in @(
            @{Value=0;Want='0'},@{Value=[int]::MaxValue;Want='2147483647'},@{Value=[long]::MaxValue;Want='9223372036854775807'},
            @{Value=-1;Want='unavailable'},@{Value=[long]::MinValue;Want='unavailable'},
            @{Value=[uint64]::MaxValue;Want='unavailable'},@{Value=[decimal]'9223372036854775808';Want='unavailable'},
            @{Value='1234';Want='unavailable'},@{Value=1.25;Want='unavailable'},@{Value=$true;Want='unavailable'},@{Value=$null;Want='unavailable'}
        )) {
            $facts=$valid.Clone(); $facts.ElapsedMs=$sample.Value
            $lines=@(ConvertTo-SdsDiagnosticLines $facts)
            Assert-Records $lines 'Elapsed primitive/range'
            Assert-True ($lines[0].Contains(' elapsed_ms='+$sample.Want+' deadline_ms=30000')) 'Elapsed primitive/range/culture normalization failed'
        }
        foreach ($sample in @(@{Value=[int]::MinValue;Want='-2147483648'},@{Value=[int]::MaxValue;Want='2147483647'})) {
            $facts=$valid.Clone(); $facts.RegistryValue=$null
            $exception=[Runtime.InteropServices.ExternalException]::new('PRIVATE_HRESULT',$sample.Value)
            $facts.RegistryError=[Management.Automation.ErrorRecord]::new($exception,'Private',[Management.Automation.ErrorCategory]::NotSpecified,$null)
            $lines=@(ConvertTo-SdsDiagnosticLines $facts)
            Assert-Records $lines 'Invariant HRESULT'
            Assert-True ($lines[1].EndsWith(' error=other exception_hresult='+$sample.Want)) 'HRESULT signs/digits depend on culture'
        }
    } finally {
        [Threading.Thread]::CurrentThread.CurrentCulture=$oldCulture
        [Threading.Thread]::CurrentThread.CurrentUICulture=$oldUiCulture
    }
    $huge=('PRIVATE_RAW_'+([char]0)+"`r`n"+[char]0x263a)*4096
    $getterEffects=@{Calls=0}
    $throwing=[pscustomobject]@{}
    foreach ($property in @('ImagePath','Type','Start','ObjectName')) {
        $throwing | Add-Member ScriptProperty $property { $getterEffects.Calls++; throw 'PRIVATE_GETTER_ERROR' }
    }
    $throwing | Add-Member ScriptMethod ToString { $getterEffects.Calls++; throw 'PRIVATE_TOSTRING_ERROR' } -Force
    foreach ($unexpected in @($huge,$throwing,@('returned','error'),@{private='PRIVATE_DICTIONARY'},17.5,$true)) {
        $facts=@{RequestedImage=$unexpected;Preflight=$unexpected;Launch=$unexpected;Handle=$unexpected;Wait=$unexpected;Completion=$unexpected;ExitCode=$unexpected;ElapsedMs=$unexpected;RegistrySource=$unexpected;RegistryValue=$unexpected;RegistryError=$unexpected;Gate=$unexpected;Private='PRIVATE_UNUSED'}
        $lines=@(ConvertTo-SdsDiagnosticLines $facts)
        Assert-Records $lines 'Malformed facts'
        Assert-True ($lines[0] -ceq $emptyProcess -and $lines[1] -ceq $emptyRegistry) 'Malformed facts leaked, coerced or became success'
    }
    foreach ($field in @('Launch','Handle','Wait','Completion','Preflight','RegistrySource','Gate')) {
        $facts=$valid.Clone(); $facts[$field]='RETURNED_PRIVATE_MALFORMED'
        $lines=@(ConvertTo-SdsDiagnosticLines $facts)
        Assert-Records $lines "Malformed $field"
        Assert-True (($lines -join ' ') -cnotmatch 'PRIVATE|private/request') "Malformed $field leaked raw data"
    }
    foreach ($sample in @(
        @{Value=$null;Want='query=unknown image=unavailable type=unavailable start=unavailable account=unavailable'},
        @{Value=[pscustomobject]@{};Want='query=unknown image=unavailable type=unavailable start=unavailable account=unavailable'},
        @{Value=$throwing;Want='query=unknown image=unavailable type=unavailable start=unavailable account=unavailable'},
        @{Value=[pscustomobject]@{ImagePath='other/private/path';Type=1;Start=2;ObjectName='OtherUser'};Want='query=present image=different type=1 start=2 account=different'},
        @{Value=[pscustomobject]@{ImagePath=$huge;Type='16';Start='3';ObjectName=$huge};Want='query=present image=different type=unavailable start=unavailable account=different'},
        @{Value=[pscustomobject]@{ImagePath=17;Type=16;Start=3;ObjectName=$true};Want='query=present image=malformed type=16 start=3 account=malformed'}
    )) {
        $facts=$valid.Clone(); $facts.RegistryValue=$sample.Value
        $lines=@(ConvertTo-SdsDiagnosticLines $facts)
        Assert-Records $lines 'Registry observations'
        Assert-True ($lines[1].Contains($sample.Want+' ')) 'Null/malformed/different registry facts became fabricated observations'
        Assert-True (($lines -join ' ') -cnotmatch 'PRIVATE|private/|OtherUser') 'Registry input leaked'
    }
    $key='HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
    foreach ($sample in @(
        @{Exception=[Management.Automation.ItemNotFoundException]::new('PRIVATE_MISSING');Id='PathNotFound,Microsoft.PowerShell.Commands.GetItemPropertyCommand';Category=[Management.Automation.ErrorCategory]::ObjectNotFound;Target=$key;Query='missing';Error='not_found'},
        @{Exception=[Management.Automation.ItemNotFoundException]::new('PRIVATE_MISSING');Id='Unrecognized';Category=[Management.Automation.ErrorCategory]::ObjectNotFound;Target=$key;Query='error';Error='other'},
        @{Exception=[Management.Automation.ItemNotFoundException]::new('PRIVATE_MISSING');Id='PathNotFound,Microsoft.PowerShell.Commands.GetItemPropertyCommand';Category=[Management.Automation.ErrorCategory]::ObjectNotFound;Target='different-private-key';Query='error';Error='other'},
        @{Exception=[UnauthorizedAccessException]::new('PRIVATE_DENIED');Id='Private';Category=[Management.Automation.ErrorCategory]::PermissionDenied;Target=$key;Query='error';Error='access_denied'},
        @{Exception=[Security.SecurityException]::new('PRIVATE_SECURITY');Id='Private';Category=[Management.Automation.ErrorCategory]::SecurityError;Target=$key;Query='error';Error='security'},
        @{Exception=[IO.IOException]::new('PRIVATE_IO');Id='Private';Category=[Management.Automation.ErrorCategory]::ReadError;Target=$key;Query='error';Error='io'},
        @{Exception=[Exception]::new('PRIVATE_OTHER');Id='Private';Category=[Management.Automation.ErrorCategory]::NotSpecified;Target=$key;Query='error';Error='other'}
    )) {
        $facts=$valid.Clone(); $facts.RegistryValue=$null; $facts.Gate='observation_error'
        $facts.RegistryError=[Management.Automation.ErrorRecord]::new($sample.Exception,$sample.Id,$sample.Category,$sample.Target)
        $lines=@(ConvertTo-SdsDiagnosticLines $facts)
        Assert-Records $lines 'Registry error'
        Assert-True ($lines[1].Contains(' query='+$sample.Query+' ')) 'Registry error incorrectly classified as missing/present'
        Assert-True ($lines[1].EndsWith('error='+$sample.Error+' exception_hresult='+$sample.Exception.HResult.ToString([Globalization.CultureInfo]::InvariantCulture))) 'Registry exception category or HRESULT lost'
        Assert-True (($lines -join ' ') -cnotmatch 'PRIVATE|private/|different-private-key') 'Registry exception data leaked'
    }
    # PSProperty also describes input-defined CLR getters. These real derived
    # objects must expose their fixed base facts without invoking hidden members.
    # Changing any base read back to ordinary member access trips the counter.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Management.Automation;
public static class SdsDiagnosticMemberCallbacks {
    public static int Calls;
    public static bool Throw;
    public static void Invoked() {
        Calls++;
        if (Throw) throw new InvalidOperationException("PRIVATE_CLR_MEMBER_CALLBACK");
    }
}
public sealed class SdsDiagnosticHiddenException : Exception {
    public SdsDiagnosticHiddenException() { base.HResult = -17; }
    public new int HResult { get { SdsDiagnosticMemberCallbacks.Invoked(); return 5; } }
}
public sealed class SdsDiagnosticHiddenIoException : IOException {
    public SdsDiagnosticHiddenIoException() { base.HResult = -18; }
    public new int HResult { get { SdsDiagnosticMemberCallbacks.Invoked(); return 5; } }
}
public sealed class SdsDiagnosticInheritedIoException : IOException {
    public SdsDiagnosticInheritedIoException() { base.HResult = -19; }
}
public sealed class SdsDiagnosticHiddenErrorRecord : ErrorRecord {
    public SdsDiagnosticHiddenErrorRecord(Exception exception, string id, ErrorCategory category, object target)
        : base(exception, id, category, target) { }
    public new Exception Exception {
        get { SdsDiagnosticMemberCallbacks.Invoked(); return new Exception("PRIVATE_CLR_EXCEPTION"); }
    }
    public new string FullyQualifiedErrorId {
        get { SdsDiagnosticMemberCallbacks.Invoked(); return "PRIVATE_CLR_ID"; }
    }
    public new ErrorCategoryInfo CategoryInfo {
        get { SdsDiagnosticMemberCallbacks.Invoked(); return base.CategoryInfo; }
    }
    public new object TargetObject {
        get { SdsDiagnosticMemberCallbacks.Invoked(); return "PRIVATE_CLR_TARGET"; }
    }
}
'@
    foreach ($throws in @($false,$true)) {
        [SdsDiagnosticMemberCallbacks]::Throw=$throws
        foreach ($sample in @(
            @{Exception=[SdsDiagnosticHiddenException]::new();Error='other';HResult='-17'},
            @{Exception=[SdsDiagnosticHiddenIoException]::new();Error='io';HResult='-18'},
            @{Exception=[SdsDiagnosticInheritedIoException]::new();Error='io';HResult='-19'}
        )) {
            $exception=$sample.Exception
            Assert-True ($exception.PSObject.Properties['HResult'] -is [Management.Automation.PSProperty]) 'CLR regression did not supply an adapted property'
            $record=[Management.Automation.ErrorRecord]::new($exception,'Private',[Management.Automation.ErrorCategory]::NotSpecified,$key)
            $facts=$valid.Clone(); $facts.RegistryValue=$null; $facts.RegistryError=$record; $facts.Gate='observation_error'
            [SdsDiagnosticMemberCallbacks]::Calls=0
            $lines=@(ConvertTo-SdsDiagnosticLines $facts)
            Assert-Records $lines 'Derived CLR exception'
            Assert-True ([SdsDiagnosticMemberCallbacks]::Calls -eq 0) "Renderer invoked hidden CLR HResult getter: calls=$([SdsDiagnosticMemberCallbacks]::Calls)"
            Assert-True ($lines[1] -ceq ('PVBOX_SDS_DIAG_V1 kind=registry authority=none key=VBoxSDS preflight=absent source=gate query=error image=unavailable type=unavailable start=unavailable account=unavailable gate=observation_error error='+$sample.Error+' exception_hresult='+$sample.HResult)) 'Derived exception lost fixed base facts or accepted hidden HRESULT'
        }
        $exception=[Management.Automation.ItemNotFoundException]::new('PRIVATE_BASE_MISSING')
        $record=[SdsDiagnosticHiddenErrorRecord]::new($exception,'PathNotFound,Microsoft.PowerShell.Commands.GetItemPropertyCommand',[Management.Automation.ErrorCategory]::ObjectNotFound,$key)
        foreach ($name in @('Exception','FullyQualifiedErrorId','CategoryInfo','TargetObject')) {
            Assert-True ($record.PSObject.Properties[$name] -is [Management.Automation.PSProperty]) 'CLR ErrorRecord regression did not supply an adapted property'
        }
        $facts=$valid.Clone(); $facts.RegistryValue=$null; $facts.RegistryError=$record; $facts.Gate='observation_error'
        [SdsDiagnosticMemberCallbacks]::Calls=0
        $lines=@(ConvertTo-SdsDiagnosticLines $facts)
        Assert-Records $lines 'Derived CLR ErrorRecord'
        Assert-True ([SdsDiagnosticMemberCallbacks]::Calls -eq 0) "Renderer invoked hidden CLR ErrorRecord getter: calls=$([SdsDiagnosticMemberCallbacks]::Calls)"
        Assert-True ($lines[1].Contains(' query=missing ') -and $lines[1].EndsWith(' error=not_found exception_hresult='+[Convert]::ToString($exception.HResult,[Globalization.CultureInfo]::InvariantCulture))) 'Derived ErrorRecord lost the fixed base missing-key facts'
        Assert-True (($lines -join ' ') -cnotmatch 'PRIVATE') 'Derived CLR member data leaked'
    }

    # A genuine ErrorRecord/exception can still carry PowerShell-added members.
    # Reject those members without invoking any input callback, including each
    # link in the missing-key classifier and the exception HRESULT.
    foreach ($sample in @(
        @{Owner='Record';Member='Exception'},
        @{Owner='Record';Member='FullyQualifiedErrorId'},
        @{Owner='Record';Member='CategoryInfo'},
        @{Owner='Record';Member='TargetObject'},
        @{Owner='Exception';Member='HResult'},
        @{Owner='Category';Member='Category'},
        @{Owner='IoException';Member='HResult'}
    )) {
        foreach ($memberKind in @('ScriptProperty','NoteProperty')) {
            $callbackEffects=@{Calls=0}
            $exception=if ($sample.Owner -eq 'IoException') { [IO.IOException]::new('PRIVATE_DECORATED_IO') } else { [Management.Automation.ItemNotFoundException]::new('PRIVATE_DECORATED_MISSING') }
            $record=[Management.Automation.ErrorRecord]::new($exception,'PathNotFound,Microsoft.PowerShell.Commands.GetItemPropertyCommand',[Management.Automation.ErrorCategory]::ObjectNotFound,$key)
            $owner=switch ($sample.Owner) {
                'Record' { $record }
                'Category' { $record.CategoryInfo }
                default { $exception }
            }
            if ($memberKind -eq 'ScriptProperty') {
                $owner | Add-Member ScriptProperty $sample.Member { $callbackEffects.Calls++; throw 'PRIVATE_ERROR_MEMBER_CALLBACK' } -Force
            } else {
                $owner | Add-Member NoteProperty $sample.Member 'PRIVATE_ERROR_MEMBER_OVERRIDE' -Force
            }
            $facts=$valid.Clone(); $facts.RegistryValue=$null; $facts.RegistryError=$record; $facts.Gate='observation_error'
            $lines=@(ConvertTo-SdsDiagnosticLines $facts)
            Assert-Records $lines "Decorated error $($sample.Owner).$($sample.Member)/$memberKind"
            Assert-True ($callbackEffects.Calls -eq 0) "Renderer invoked input ErrorRecord/exception callback: $($sample.Owner).$($sample.Member)"
            Assert-True ($lines[1] -ceq 'PVBOX_SDS_DIAG_V1 kind=registry authority=none key=VBoxSDS preflight=absent source=gate query=error image=unavailable type=unavailable start=unavailable account=unavailable gate=observation_error error=unknown exception_hresult=unavailable') 'Decorated error did not conservatively normalize to fixed unknown/unavailable'
        }
    }

    $facts=$valid.Clone(); $facts.RegistryValue=$null; $facts.RegistryError=$throwing
    $lines=@(ConvertTo-SdsDiagnosticLines $facts)
    Assert-True ($lines[1].Contains(' query=error ') -and $lines[1].EndsWith('error=unknown exception_hresult=unavailable')) 'Unknown error became missing or a fabricated HRESULT'

    Assert-True ($getterEffects.Calls -eq 0) 'Renderer invoked an input-supplied getter or ToString'

    # Record the actual production Console.Out.Write calls, including partial
    # output before a throw. No production sink seam or retry is introduced.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
public sealed class SdsDiagnosticTestWriter : TextWriter {
    public readonly List<string> Attempts = new List<string>();
    public readonly StringBuilder Captured = new StringBuilder();
    public List<string> Trace;
    public int FailOnAttempt;
    public int PartialChars;
    public override Encoding Encoding { get { return Encoding.UTF8; } }
    public override void Write(string value) {
        if (Trace != null) Trace.Add("diagnostic");
        Attempts.Add(value);
        if (Attempts.Count == FailOnAttempt) {
            Captured.Append(value.Substring(0, Math.Min(PartialChars, value.Length)));
            throw new IOException("PRIVATE_OUTPUT_FAILURE");
        }
        Captured.Append(value);
    }
}
'@
    foreach ($sample in @(
        @{Fail=0;Partial=0},@{Fail=1;Partial=0},@{Fail=1;Partial=13},@{Fail=2;Partial=0},@{Fail=2;Partial=19}
    )) {
        $sink=[SdsDiagnosticTestWriter]::new(); $sink.FailOnAttempt=$sample.Fail; $sink.PartialChars=$sample.Partial
        $savedOut=[Console]::Out
        try {
            [Console]::SetOut($sink)
            $returned=@(Write-SdsRegistrationDiagnostics $valid)
        } finally { [Console]::SetOut($savedOut) }
        Assert-True ($returned.Count -eq 0) 'Diagnostic writer returned a decision or error output'
        Assert-True ($sink.Attempts.Count -eq 2) 'Diagnostic writer skipped a bounded record or retried a failed write'
        Assert-True ($sink.Attempts[0] -ceq ($validProcess+"`r`n") -and $sink.Attempts[1] -ceq ($validRegistry+"`r`n")) 'Actual writer output/order/CRLF differs'
        $bytes=0
        foreach ($attempt in $sink.Attempts) {
            $length=[Text.Encoding]::UTF8.GetByteCount($attempt)
            Assert-True ($length -le 1024) 'Actual write attempt exceeded UTF-8 record cap'
            $bytes+=$length
        }
        Assert-True ($bytes -le 2048) 'Actual write attempts exceeded total byte cap'
        $wanted=if ($sample.Fail -eq 0) { $validProcess+"`r`n"+$validRegistry+"`r`n" } elseif ($sample.Fail -eq 1) { ($validProcess+"`r`n").Substring(0,$sample.Partial)+$validRegistry+"`r`n" } else { $validProcess+"`r`n"+($validRegistry+"`r`n").Substring(0,$sample.Partial) }
        Assert-True ($sink.Captured.ToString() -ceq $wanted) 'Writer retried partial output or logged recursively'
    }
    # The real writer validates every complete line before its first attempt.
    # Synthetic renderer results exercise exact byte boundaries independently
    # of the production renderer's much shorter fixed records.
    function ConvertTo-SdsDiagnosticLines { return $syntheticLines }
    foreach ($sample in @(
        @{Lines=@(('a'*1022),('b'*1022));Attempts=2;Bytes=2048},
        @{Lines=@($validProcess,('b'*1023));Attempts=0;Bytes=0},
        @{Lines=@(('a'*1023),$validRegistry);Attempts=0;Bytes=0},
        @{Lines=@($validProcess,('b'*1021+[char]0x263a));Attempts=0;Bytes=0},
        @{Lines=@($validProcess,('PRIVATE'+"`r`n"));Attempts=0;Bytes=0},
        @{Lines=@($validProcess,17);Attempts=0;Bytes=0},
        @{Lines=@();Attempts=0;Bytes=0},
        @{Lines=@($validProcess);Attempts=0;Bytes=0},
        @{Lines=@($validProcess,$validRegistry,$validRegistry);Attempts=0;Bytes=0}
    )) {
        $syntheticLines=$sample.Lines
        $sink=[SdsDiagnosticTestWriter]::new(); $savedOut=[Console]::Out
        try { [Console]::SetOut($sink); $returned=@(Write-SdsRegistrationDiagnostics $valid) } finally { [Console]::SetOut($savedOut) }
        Assert-True ($returned.Count -eq 0 -and $sink.Attempts.Count -eq $sample.Attempts) 'Writer did not validate all complete records before emission'
        Assert-True ([Text.Encoding]::UTF8.GetByteCount($sink.Captured.ToString()) -eq $sample.Bytes) 'Writer boundary ignored explicit CRLF/UTF-8 total'
    }

    # Failure of the renderer itself is also non-authoritative and silent.
    function ConvertTo-SdsDiagnosticLines { throw 'PRIVATE_RENDER_FAILURE' }
    $sink=[SdsDiagnosticTestWriter]::new(); $savedOut=[Console]::Out
    try { [Console]::SetOut($sink); $returned=@(Write-SdsRegistrationDiagnostics $valid) } finally { [Console]::SetOut($savedOut) }
    Assert-True ($returned.Count -eq 0 -and $sink.Attempts.Count -eq 0) 'Renderer failure escaped or produced recursive diagnostic output'
    Assert-True ($diagnosticObservations.Calls -eq 0) 'Diagnostics attempted system observations or process launch'
    Write-Host 'PASS bounded SDS diagnostic renderer and real writer'
}


# Exercise the real Prepare and Run-Sds with only their fixed effect boundaries
# replaced. These local files/receipts are synthetic evidence, not installation
# proof or a sandbox against arbitrary future source changes.
function Test-PrivilegedPrepare([string]$Source,[string]$TestRoot) {
    $tokens=$null; $errors=$null
    $parsed=[Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Prepare source did not parse' }
    $matches=@($parsed.FindAll({param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq "`$Action -eq 'Prepare'"
    },$true))
    Assert-True ($matches.Count -eq 1) 'Expected exactly one real Prepare branch'
    $prepare=$matches[0].Clauses[0].Item2
    # Fail closed on new commands/selectors before loading any production code.
    foreach ($selection in @(
        @{Ast=$prepare;Allowed=@('Test-Path','Join-Path','Get-Content','ConvertFrom-Json','Run-Sds','Get-ItemProperty','ConvertTo-Json','Set-Content','Write-Host','Write-SdsRegistrationDiagnostics')},
        @{Ast=(Get-RequiredFunction $Source 'Run-Sds').Ast;Allowed=@('Start-Process','Join-Path')},
        @{Ast=(Get-RequiredFunction $Source 'ConvertTo-SdsDiagnosticLines').Ast;Allowed=@('Get-DiagnosticToken','Get-DiagnosticNumber')},
        @{Ast=(Get-RequiredFunction $Source 'Write-SdsRegistrationDiagnostics').Ast;Allowed=@('ConvertTo-SdsDiagnosticLines')}
    )) {
        foreach ($command in @($selection.Ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))) {
            $name=$command.GetCommandName()
            if ($null -eq $name) {
                Assert-True ($selection.Ast -eq $prepare -and $command.CommandElements[0].Extent.Text -cin @("(Join-Path `$PSScriptRoot 'vbox_sup_standalone.ps1')","(Join-Path `$PSScriptRoot 'vbox_sup_start_owned.ps1')")) 'Unexpected dynamic Prepare command'
            } else { Assert-True ($name -cin $selection.Allowed) "Unexpected loaded command: $name" }
        }
    }
    . (Get-RequiredFunction $Source 'Run-Sds')
    . (Get-RequiredFunction $Source 'ConvertTo-SdsDiagnosticLines')
    . (Get-RequiredFunction $Source 'Write-SdsRegistrationDiagnostics')
    $realRenderer=Get-RequiredFunction $Source 'ConvertTo-SdsDiagnosticLines'
    $realReporter=Get-RequiredFunction $Source 'Write-SdsRegistrationDiagnostics'
    $fixture=Join-Path $TestRoot 'privileged-effects'
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $body=Join-Path $fixture 'prepare.ps1'
    Set-Content -LiteralPath $body -Value $prepare.Extent.Text.Substring(1,$prepare.Extent.Text.Length-2)
    Set-Content -LiteralPath (Join-Path $fixture 'vbox_sup_standalone.ps1') -Value @'
param($AppDir,$OutputDirectory)
if ($AppDir -cne $app -or $OutputDirectory -cne (Join-Path $session 'stage')) { $state.Forbidden++; throw 'Unexpected stage arguments' }
$state.Trace.Add('stage')
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$path=Join-Path $OutputDirectory 'sup-standalone.json'
[IO.File]::WriteAllText($path,'{"fixture":"deterministic-stage"}',[Text.UTF8Encoding]::new($false))
$state.Snapshots[$path]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
'@
    Set-Content -LiteralPath (Join-Path $fixture 'vbox_sup_start_owned.ps1') -Value @'
param($StandaloneReport,$OutputDirectory)
if ($StandaloneReport -cne (Join-Path $session 'stage\sup-standalone.json') -or $OutputDirectory -cne (Join-Path $session 'start')) { $state.Forbidden++; throw 'Unexpected start arguments' }
$state.Trace.Add('start')
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
if ($case.Name -ne 'MissingReceipt') {
    $path=Join-Path $OutputDirectory 'sup-start-results.json'
    $fixtureReceipt | ConvertTo-Json | Microsoft.PowerShell.Management\Set-Content -LiteralPath $path -Encoding utf8
    $state.Snapshots[$path]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
}
'@
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public sealed class SdsPrepareTestProcess {
    public List<string> Trace;
    public string Mode;
    public int ConfiguredExit;
    public IntPtr Handle { get { Trace.Add("handle"); if (Mode == "HandleError") throw new InvalidOperationException("FIXTURE_HANDLE_FAILURE"); return Mode == "ZeroHandle" ? IntPtr.Zero : new IntPtr(1); } }
    public bool WaitForExit(int milliseconds) {
        Trace.Add("wait:" + milliseconds);
        if (milliseconds != 30000) throw new InvalidOperationException("Unexpected wait deadline");
        if (Mode == "WaitError") throw new InvalidOperationException("FIXTURE_WAIT_FAILURE");
        return Mode != "Late" && Mode != "CompletionError";
    }
    public void WaitForExit() { Trace.Add("completion"); if (Mode == "CompletionError") throw new InvalidOperationException("FIXTURE_COMPLETION_FAILURE"); }
    public int ExitCode { get { Trace.Add("exit"); return ConfiguredExit; } }
    public void Dispose() { Trace.Add("dispose"); }
}
'@
    $cases=@(
        @{Name='Exact';Ok=$true;Gate='identity_match'},
        @{Name='Missing';Error='MISSING_KEY';Gate='observation_error'},
        @{Name='WrongImage';Error='SDS registration identity differs';Gate='identity_mismatch'},
        @{Name='WrongType';Error='SDS registration identity differs';Gate='identity_mismatch'},
        @{Name='WrongStart';Error='SDS registration identity differs';Gate='identity_mismatch'},
        @{Name='WrongAccount';Error='SDS registration identity differs';Gate='identity_mismatch'},
        @{Name='ReadError';Error='READ_DENIED';Gate='observation_error'},
        @{Name='Null';Error='The property';Gate='observation_error'},
        @{Name='MissingProperty';Error='The property';Gate='observation_error'},
        @{Name='MalformedAccount';Error='SDS registration identity differs';Gate='identity_mismatch'},
        # Characterize existing coercion, not a new strict diagnostic policy.
        @{Name='CoercedNumbers';Ok=$true;Gate='identity_match'},
        @{Name='PredicateMatch';Ok=$true;Gate='identity_match'},
        @{Name='PredicateMismatch';Error='SDS registration identity differs';Gate='identity_mismatch'},
        @{Name='PredicateThrow';Error='The property';Gate='observation_error'},
        @{Name='Exit5';Error='SDS operation unconfirmed; retain resources';Gate='not_reached';NoGate=$true;Exit=5},
        @{Name='Late0';Error='SDS operation exceeded safety deadline; child exited, state requires inspection';Gate='not_reached';NoGate=$true;Mode='Late'},
        @{Name='Late5';Error='SDS operation exceeded safety deadline; child exited, state requires inspection';Gate='not_reached';NoGate=$true;Mode='Late';Exit=5},
        @{Name='ZeroHandle';Error='SDS process handle unavailable';Gate='not_reached';NoGate=$true;Mode='ZeroHandle'},
        @{Name='HandleError';Ok=$true;Gate='identity_match';Mode='HandleError'},
        @{Name='WaitError';Error='FIXTURE_WAIT_FAILURE';Gate='not_reached';NoGate=$true;Mode='WaitError'},
        @{Name='CompletionError';Error='FIXTURE_COMPLETION_FAILURE';Gate='not_reached';NoGate=$true;Mode='CompletionError'},
        @{Name='LaunchError';Error='FIXTURE_LAUNCH_FAILURE';Gate='not_reached';NoGate=$true;Mode='LaunchError'},
        @{Name='Preexisting';Error='SDS appeared before our explicit registration';NoLaunch=$true},
        @{Name='PreflightError';Error='FIXTURE_PREFLIGHT_FAILURE';NoLaunch=$true},
        @{Name='BreakSds';Error='CI_TEST_BREAK_AFTER_SDS: protected service registration marker committed';Gate='identity_match';Marker=$true},
        @{Name='ReceiptError';Error='FIXTURE_RECEIPT_FAILURE';Gate='identity_match';Marker=$true},
        @{Name='MarkerError';Error='FIXTURE_MARKER_FAILURE';Gate='identity_match';MarkerAttempt=$true},
        @{Name='BreakStage';Error='CI_TEST_BREAK_AFTER_STAGE: protected installation report committed';NoLaunch=$true;Early=$true},
        @{Name='BreakStart';Error='CI_TEST_BREAK_AFTER_START: protected driver start report committed';NoLaunch=$true;Early=$true}
    )
    foreach ($name in @('ExitFailure','Timeout','Stopped','WrongExperiment','MissingReceipt','WrongInitial','ForeignServices','WmiStopped','MissingField','StringTrue')) { $cases+=@{Name=$name;Error=$(if ($name -eq 'MissingReceipt') { 'Cannot find path' } elseif ($name -eq 'MissingField') { 'The property' } else { 'Driver activation proof unconfirmed; preparation denied' });NoLaunch=$true;Early=$true} }
    foreach ($policy in @('Exact','Missing')) {
        foreach ($fault in @('Renderer','Reporter','Output','Partial')) {
            $cases+=@{Name=($policy+'-'+$fault);Policy=$policy;Fault=$fault;Ok=($policy -eq 'Exact');Error='MISSING_KEY';Gate=$(if ($policy -eq 'Exact') { 'identity_match' } else { 'observation_error' })}
        }
    }
    # All old policy paths execute before the first telemetry assertion. This
    # separates existing-policy characterization from meaningful telemetry RED.
    $observed=[Collections.Generic.List[object]]::new()
    foreach ($case in $cases) {
        $policy=if ($case.ContainsKey('Policy')) { $case.Policy } else { $case.Name }
        . $realRenderer
        . $realReporter
        if ($case['Fault'] -eq 'Renderer') { function ConvertTo-SdsDiagnosticLines { throw 'PRIVATE_RENDER_FAILURE' } }
        if ($case['Fault'] -eq 'Reporter') { function Write-SdsRegistrationDiagnostics { throw 'PRIVATE_REPORT_FAILURE' } }
        $session=Join-Path $TestRoot ('prepare-'+$case.Name); $root=$session; $app=Join-Path $session 'app64'
        New-Item -ItemType Directory -Path $session | Out-Null
        $state=@{Trace=[Collections.Generic.List[string]]::new();Snapshots=@{};Forbidden=0;Registry=0;Preflight=0;Launch=0;PropertyReads=[Collections.Generic.List[string]]::new()}
        $intent=Join-Path $session 'prepare-intent.json'
        [IO.File]::WriteAllText($intent,'{"fixture":"durable-intent"}',[Text.UTF8Encoding]::new($false))
        $state.Snapshots[$intent]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($intent))
        $state.Trace.Add('intent')
        $TestBreakAfter=switch ($policy) { 'BreakStage' {'Stage'} 'BreakStart' {'Start'} 'BreakSds' {'Sds'} default {'None'} }
        $ControllerPid=123; $ControllerCreated=456L; $controllerImage='controller.exe'
        $fixtureReceipt=@{experiment='owned-standalone-VBoxSup-start';start_status='EXITED';start_exit_code=0;driver_running=$true;initial_status='Stopped';service_status_after='Running';wmi_driver_state='Running';no_other_vbox_services_before=$true}
        switch ($policy) {
            'ExitFailure' { $fixtureReceipt.start_exit_code=5 }
            'Timeout' { $fixtureReceipt.start_status='TIMEOUT' }
            'Stopped' { $fixtureReceipt.driver_running=$false; $fixtureReceipt.service_status_after='Stopped' }
            'WrongExperiment' { $fixtureReceipt.experiment='unrelated' }
            'WrongInitial' { $fixtureReceipt.initial_status='Running' }
            'ForeignServices' { $fixtureReceipt.no_other_vbox_services_before=$false }
            'WmiStopped' { $fixtureReceipt.wmi_driver_state='Stopped' }
            'MissingField' { $fixtureReceipt.Remove('driver_running') }
            'StringTrue' { $fixtureReceipt.driver_running='true' }
        }
        $registry=[pscustomobject]@{ImagePath=(Join-Path $app 'VBoxSDS.exe');Type=16;Start=3;ObjectName='LocalSystem'}
        switch ($policy) {
            'WrongImage' { $registry.ImagePath='other-image' }
            'WrongType' { $registry.Type=1 }
            'WrongStart' { $registry.Start=2 }
            'WrongAccount' { $registry.ObjectName='OtherAccount' }
            'Null' { $registry=$null }
            'MissingProperty' { $registry.PSObject.Properties.Remove('ObjectName') }
            'MalformedAccount' { $registry.ObjectName=17 }
            'CoercedNumbers' { $registry.Type='16'; $registry.Start='3' }
            'PredicateMismatch' { $registry.Type=1 }
            'PredicateThrow' { $registry.PSObject.Properties.Remove('ObjectName') }
        }
        if ($policy -in @('PredicateMatch','PredicateMismatch','PredicateThrow')) {
            foreach ($property in @($registry.PSObject.Properties)) {
                $propertyName=$property.Name; $propertyValue=$property.Value; $reads=$state.PropertyReads
                $getter={ $reads.Add($propertyName); return $propertyValue }.GetNewClosure()
                $registry | Add-Member ScriptProperty $propertyName $getter -Force
            }
        }
        $key='HKLM:\SYSTEM\CurrentControlSet\Services\VBoxSDS'
        $primaryError=if ($policy -eq 'Missing') { [Management.Automation.ErrorRecord]::new([Management.Automation.ItemNotFoundException]::new('MISSING_KEY'),'PathNotFound,Microsoft.PowerShell.Commands.GetItemPropertyCommand',[Management.Automation.ErrorCategory]::ObjectNotFound,$key) } else { [Management.Automation.ErrorRecord]::new([UnauthorizedAccessException]::new('READ_DENIED'),'FIXTURE_READ_DENIED',[Management.Automation.ErrorCategory]::PermissionDenied,$key) }
        function Get-Service { $state.Forbidden++; throw 'Forbidden SCM observation' }
        function Get-CimInstance { $state.Forbidden++; throw 'Forbidden CIM observation' }
        function Get-Process { $state.Forbidden++; throw 'Forbidden process observation' }
        function Start-Sleep { $state.Forbidden++; throw 'Forbidden sleep' }
        function Test-Path {
            [CmdletBinding(DefaultParameterSetName='Path')]param([Parameter(ParameterSetName='Literal')][string]$LiteralPath,[Parameter(Position=0,ParameterSetName='Path')][string]$Path,[string]$PathType)
            $value=if ($LiteralPath) { $LiteralPath } else { $Path }
            if ($value -like 'HKLM:*') {
                if ($value -cne $key -or $LiteralPath -or $PathType) { $state.Forbidden++; throw 'Unexpected preflight selector' }
                $state.Preflight++; $state.Trace.Add('preflight')
                if ($policy -eq 'PreflightError') { throw 'FIXTURE_PREFLIGHT_FAILURE' }
                return $policy -eq 'Preexisting'
            }
            if ($value -cne $intent -or $PathType -cne 'Leaf') { $state.Forbidden++; throw 'Unexpected local Prepare probe' }
            return Microsoft.PowerShell.Management\Test-Path -LiteralPath $value -PathType Leaf
        }
        function Get-ItemProperty {
            [CmdletBinding()]param($LiteralPath)
            if ($LiteralPath -cne $key -or $PSBoundParameters['ErrorAction'] -ne 'Stop') { $state.Forbidden++; throw 'Unexpected authoritative selector' }
            $state.Registry++; $state.Trace.Add('registry')
            if ($policy -in @('Missing','ReadError')) { throw $primaryError }
            return $registry
        }
        function Get-Content {
            [CmdletBinding()]param($LiteralPath,[switch]$Raw,$Encoding)
            if ($LiteralPath -cne (Join-Path $session 'start\sup-start-results.json') -or -not $Raw -or $Encoding -cne 'UTF8' -or $PSBoundParameters['ErrorAction'] -ne 'Stop') { $state.Forbidden++; throw 'Unexpected Prepare receipt read' }
            Microsoft.PowerShell.Management\Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 -ErrorAction Stop
        }
        function Start-Process {
            [CmdletBinding()]param($FilePath,$ArgumentList,$WorkingDirectory,[switch]$NoNewWindow,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
            if ($FilePath -cne (Join-Path $app 'VBoxSDS.exe') -or $ArgumentList -cne '--regservice' -or $WorkingDirectory -cne $app -or -not $NoNewWindow -or -not $PassThru -or $RedirectStandardOutput -cne (Join-Path $session 'sds-register.stdout.txt') -or $RedirectStandardError -cne (Join-Path $session 'sds-register.stderr.txt')) { $state.Forbidden++; throw 'Unexpected SDS launch selector' }
            $state.Launch++; $state.Trace.Add('launch')
            if ($policy -eq 'LaunchError') { throw 'FIXTURE_LAUNCH_FAILURE' }
            [IO.File]::WriteAllText($RedirectStandardOutput,''); [IO.File]::WriteAllText($RedirectStandardError,'')
            $process=[SdsPrepareTestProcess]::new(); $process.Trace=$state.Trace; $process.Mode=$case['Mode']; $process.ConfiguredExit=if ($case.ContainsKey('Exit')) { $case.Exit } else { 0 }
            return $process
        }
        function Set-Content {
            [CmdletBinding()]param([Parameter(ValueFromPipeline)]$Value,$LiteralPath,$Encoding)
            process {
                if ($LiteralPath -ceq (Join-Path $session 'sds-registered.json')) { $state.Trace.Add('marker'); if ($policy -eq 'MarkerError') { throw 'FIXTURE_MARKER_FAILURE' } }
                elseif ($LiteralPath -ceq (Join-Path $session 'session.json')) { $state.Trace.Add('receipt'); if ($policy -eq 'ReceiptError') { throw 'FIXTURE_RECEIPT_FAILURE' } }
                else { $state.Forbidden++; throw 'Unexpected Prepare write' }
                $Value | Microsoft.PowerShell.Management\Set-Content -LiteralPath $LiteralPath -Encoding $Encoding
            }
        }
        $sink=[SdsDiagnosticTestWriter]::new(); $sink.Trace=$state.Trace
        if ($case['Fault'] -in @('Output','Partial')) { $sink.FailOnAttempt=1; if ($case.Fault -eq 'Partial') { $sink.PartialChars=13 } }
        $savedOut=[Console]::Out; $caught=$null
        try { [Console]::SetOut($sink); & $body } catch { $caught=$_ } finally { [Console]::SetOut($savedOut) }
        Assert-True ($state.Forbidden -eq 0) "$($case.Name) attempted a forbidden effect: $caught / $($state.Trace -join ',')"
        $ok=$case.ContainsKey('Ok') -and $case.Ok
        Assert-True (($null -eq $caught) -eq $ok) "$($case.Name) changed original gate outcome: $caught"
        if (-not $ok) {
            Assert-True ($caught.Exception.Message.Contains($case.Error)) "$($case.Name) changed primary refusal: $caught"
            if ($policy -in @('Null','MissingProperty','MissingField','PredicateThrow')) {
                Assert-True ($caught.FullyQualifiedErrorId -ceq 'PropertyNotFoundStrict' -and $caught.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::NotSpecified -and $caught.Exception -is [Management.Automation.PropertyNotFoundException]) "$($case.Name) replaced original property exception"
            } elseif ($policy -in @('WrongImage','WrongType','WrongStart','WrongAccount','MalformedAccount','PredicateMismatch','Exit5','Late0','Late5','ZeroHandle','Preexisting','BreakSds','BreakStage','BreakStart')) {
                Assert-True ($caught.Exception.Message -ceq $case.Error -and $caught.FullyQualifiedErrorId -ceq $case.Error -and $caught.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::OperationStopped) "$($case.Name) changed original explicit refusal record"
            }
            Assert-True ($caught.ScriptStackTrace.Contains($body)) "$($case.Name) lost original Prepare rethrow context"
            if ($policy -in @('Missing','ReadError')) {
                Assert-True ([object]::ReferenceEquals($caught.Exception,$primaryError.Exception) -and $caught.FullyQualifiedErrorId -ceq $primaryError.FullyQualifiedErrorId -and $caught.CategoryInfo.Category -eq $primaryError.CategoryInfo.Category) "$($case.Name) replaced original authoritative error"
            }
        }
        $launched=if ($case.ContainsKey('NoLaunch')) { 0 } else { 1 }
        $reads=if ($launched -eq 0 -or $case.ContainsKey('NoGate')) { 0 } else { 1 }
        Assert-True ($state.Preflight -eq $(if ($case.ContainsKey('Early')) { 0 } else { 1 })) "$($case.Name) changed preflight count"
        Assert-True ($state.Launch -eq $launched -and $state.Registry -eq $reads) "$($case.Name) gained a launch/registry query or skipped the gate"
        $wantTrace=if ($policy -eq 'BreakStage') { 'intent,stage' } elseif ($case.ContainsKey('Early')) { 'intent,stage,start' } else { 'intent,stage,start,preflight' }
        if ($launched) {
            $wantTrace+=',launch'
            if ($policy -ne 'LaunchError') {
                $wantTrace+=',handle'
                if ($policy -ne 'ZeroHandle') {
                    $wantTrace+=',wait:30000'
                    if ($policy -in @('Late0','Late5','CompletionError')) { $wantTrace+=',completion' }
                    elseif ($policy -ne 'WaitError') { $wantTrace+=',exit' }
                }
                $wantTrace+=',dispose'
            }
            if ($reads) { $wantTrace+=',registry' }
            if ($ok -or $case.ContainsKey('Marker') -or $case.ContainsKey('MarkerAttempt')) { $wantTrace+=',marker' }
            if ($ok -or $policy -eq 'ReceiptError') { $wantTrace+=',receipt' }
        }
        Assert-True ((@($state.Trace | Where-Object { $_ -ne 'diagnostic' }) -join ',') -ceq $wantTrace) "$($case.Name) changed original effect trace: $($state.Trace -join ',') expected $wantTrace"
        $firstDiagnostic=$state.Trace.IndexOf('diagnostic')
        Assert-True ($firstDiagnostic -eq -1 -or ($firstDiagnostic -ge $state.Trace.Count-2 -and @($state.Trace | Select-Object -Skip $firstDiagnostic | Where-Object { $_ -ne 'diagnostic' }).Count -eq 0)) "$($case.Name) reported before original effects/refusal"
        if ($policy -in @('PredicateMatch','PredicateMismatch','PredicateThrow')) {
            $wantedFields=switch ($policy) { 'PredicateMismatch' { 'ImagePath,Type' } 'PredicateThrow' { 'ImagePath,Type,Start' } default { 'ImagePath,Type,Start,ObjectName' } }
            Assert-True (($state.PropertyReads -join ',') -ceq $wantedFields) "$($case.Name) re-evaluated or reordered the original identity expression/getters"
        }
        $hasMarker=Microsoft.PowerShell.Management\Test-Path -LiteralPath (Join-Path $session 'sds-registered.json')
        $hasReceipt=Microsoft.PowerShell.Management\Test-Path -LiteralPath (Join-Path $session 'session.json')
        Assert-True ($hasMarker -eq ($ok -or $case.ContainsKey('Marker')) -and $hasReceipt -eq $ok) "$($case.Name) changed durable marker semantics"
        foreach ($path in $state.Snapshots.Keys) { Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ceq $state.Snapshots[$path]) "$($case.Name) changed immutable local evidence" }
        Write-Host "CHARACTERIZED $($case.Name): $wantTrace; registry=$($state.Registry); SCM=0; error=$(if ($caught) { $caught.FullyQualifiedErrorId+'|'+$caught.Exception.GetType().FullName+'|'+$caught.CategoryInfo.Category+'|'+$caught.Exception.Message } else { 'none' })"
        $observed.Add(@{Case=$case;Sink=$sink;State=$state;Error=$caught;Session=$session})
    }
    Write-Host 'PASS original real Prepare policy/effect characterization'
    foreach ($result in $observed) {
        $case=$result.Case
        if ($case.ContainsKey('NoLaunch')) {
            Assert-True ($result.Sink.Attempts.Count -eq $(if ($case.ContainsKey('Early')) { 0 } else { 2 })) "$($case.Name) reported before its region or lost preflight facts"
            if (-not $case.ContainsKey('Early')) { Assert-True ($result.Sink.Attempts[1].Contains(' preflight='+$(if ($case.Name -eq 'Preexisting') { 'present' } else { 'error' })+' source=not_observed query=not_observed ')) "$($case.Name) fabricated a registry observation" }
            continue
        }
        $writes=$result.Sink.Attempts
        if ($case['Fault'] -in @('Renderer','Reporter')) {
            Assert-True ($writes.Count -eq 0) "$($case.Name) retried failed optional reporting"
            continue
        }
        Assert-True ($writes.Count -eq 2) "$($case.Name) missing captured real Prepare diagnostic records (expected two, got $($writes.Count))"
        Assert-True ($writes[0] -cmatch '^PVBOX_SDS_DIAG_V1 kind=process authority=none ' -and $writes[1] -cmatch '^PVBOX_SDS_DIAG_V1 kind=registry authority=none ') "$($case.Name) lost diagnostic order/authority"
        Assert-True ($writes[1].Contains(' gate='+$case.Gate+' ')) "$($case.Name) lost observed gate result"
        $policy=if ($case.ContainsKey('Policy')) { $case.Policy } else { $case.Name }
        $processFacts=switch ($policy) {
            'LaunchError' { 'launch=error handle=not_observed wait=not_observed completion=not_observed exit_code=unavailable elapsed_ms=unavailable' }
            'ZeroHandle' { 'launch=returned handle=zero wait=not_observed completion=not_observed exit_code=unavailable elapsed_ms=unavailable' }
            'WaitError' { 'launch=returned handle=nonzero wait=unconfirmed completion=unconfirmed exit_code=unavailable elapsed_ms=unavailable' }
            'CompletionError' { 'launch=returned handle=nonzero wait=exceeded completion=unconfirmed exit_code=unavailable elapsed_ms=unavailable' }
            default { 'launch=returned handle='+$(if ($policy -eq 'HandleError') { 'unknown' } else { 'nonzero' })+' wait='+$(if ($policy -in @('Late0','Late5')) { 'exceeded' } else { 'within_deadline' })+' completion=confirmed exit_code='+$(if ($policy -in @('Late0','Late5')) { 'unavailable' } elseif ($policy -eq 'Exit5') { '5' } else { '0' })+' elapsed_ms=' }
        }
        Assert-True ($writes[0].StartsWith('PVBOX_SDS_DIAG_V1 kind=process authority=none operation=register requested_image=protected_app/VBoxSDS.exe launched_image=not_observed '+$processFacts)) "$($case.Name) changed captured process facts"
        if ($processFacts.EndsWith('elapsed_ms=')) { Assert-True ($writes[0] -cmatch ' elapsed_ms=[0-9]+ deadline_ms=30000\r\n$') "$($case.Name) lost optional elapsed observation" }
        else { Assert-True ($writes[0].EndsWith(' elapsed_ms=unavailable deadline_ms=30000'+"`r`n")) "$($case.Name) fabricated incomplete elapsed observation" }
        $registryFacts=switch ($policy) {
            'Missing' { 'source=gate query=missing image=unavailable type=unavailable start=unavailable account=unavailable' }
            'ReadError' { 'source=gate query=error image=unavailable type=unavailable start=unavailable account=unavailable' }
            'Null' { 'source=gate query=error image=unavailable type=unavailable start=unavailable account=unavailable' }
            'MissingProperty' { 'source=gate query=error image=unavailable type=unavailable start=unavailable account=unavailable' }
            'PredicateThrow' { 'source=gate query=error image=unavailable type=unavailable start=unavailable account=unavailable' }
            'PredicateMatch' { 'source=gate query=unknown image=unavailable type=unavailable start=unavailable account=unavailable' }
            'PredicateMismatch' { 'source=gate query=unknown image=unavailable type=unavailable start=unavailable account=unavailable' }
            default {
                if ($case.ContainsKey('NoGate')) { 'source=not_observed query=not_observed image=unavailable type=unavailable start=unavailable account=unavailable' }
                else { 'source=gate query=present image='+$(if ($policy -eq 'WrongImage') { 'different' } else { 'matches_requested' })+' type='+$(if ($policy -eq 'WrongType') { '1' } elseif ($policy -eq 'CoercedNumbers') { 'unavailable' } else { '16' })+' start='+$(if ($policy -eq 'WrongStart') { '2' } elseif ($policy -eq 'CoercedNumbers') { 'unavailable' } else { '3' })+' account='+$(if ($policy -eq 'MalformedAccount') { 'malformed' } elseif ($policy -eq 'WrongAccount') { 'different' } else { 'LocalSystem' }) }
            }
        }
        Assert-True ($writes[1].StartsWith('PVBOX_SDS_DIAG_V1 kind=registry authority=none key=VBoxSDS preflight=absent '+$registryFacts+' gate='+$case.Gate+' ')) "$($case.Name) fabricated/lost original registry observations"
        Write-Host ("OBSERVED $($case.Name): "+$writes[0].TrimEnd([char[]]"`r`n")+' | '+$writes[1].TrimEnd([char[]]"`r`n"))
        $bytes=0
        foreach ($write in $writes) {
            $length=[Text.Encoding]::UTF8.GetByteCount($write); $bytes+=$length
            Assert-True ($length -le 1024 -and $write.EndsWith("`r`n") -and $write.Substring(0,$write.Length-2) -cnotmatch '[^\x20-\x7e]') "$($case.Name) violated bounded ASCII/CRLF contract"
        }
        Assert-True ($bytes -le 2048) "$($case.Name) exceeded total diagnostic cap"
        $captured=if ($case['Fault'] -eq 'Output') { $writes[1] } elseif ($case['Fault'] -eq 'Partial') { $writes[0].Substring(0,13)+$writes[1] } else { $writes[0]+$writes[1] }
        Assert-True ($result.Sink.Captured.ToString() -ceq $captured) "$($case.Name) retried or changed partial output"
        if ($case.Name -eq 'Missing') { Assert-True ($writes[1].Contains(' source=gate query=missing ') -and $writes[1].Contains(' gate=observation_error error=not_found ')) 'Missing key did not retain original read-exception branch and renderer classification' }
        if ($case.Name -in @('Late0','Late5')) { Assert-True ($writes[0].Contains(' wait=exceeded completion=confirmed exit_code=unavailable ')) "$($case.Name) fabricated a late exit observation" }
        if ($case.Name -eq 'CoercedNumbers') { Assert-True ($writes[1].Contains(' type=unavailable start=unavailable ') -and $writes[1].Contains(' gate=identity_match ')) 'Strict diagnostic normalization hardened existing coercive policy' }
    }
    Write-Host 'PASS real Prepare captured SDS observations'
    return $observed
}

# Select exactly one known per-session collector pipeline. Parsing the outer
# workflow does not execute its ProgramData enumeration or proof collection.
function Get-RequiredSessionCollector([string]$RunText) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($RunText,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Collector run text did not parse' }
    $selector="Get-ChildItem -LiteralPath (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'PortableVirtualBox.Experiment') -Directory -Filter 'pvbox-manager-*' -ErrorAction SilentlyContinue"
    $pipelines=@($ast.FindAll({param($node)
        $node -is [Management.Automation.Language.PipelineAst] -and
        $node.PipelineElements[0] -is [Management.Automation.Language.CommandAst] -and
        $node.PipelineElements[0].Extent.Text -ceq $selector
    },$true))
    Assert-True ($pipelines.Count -eq 1) "Expected exactly one per-session collector pipeline; found $($pipelines.Count)"
    $pipeline=$pipelines[0]
    Assert-True ($pipeline.PipelineElements.Count -eq 2) 'Unexpected per-session collector pipeline shape'
    $command=$pipeline.PipelineElements[1]
    Assert-True ($command -is [Management.Automation.Language.CommandAst] -and $command.GetCommandName() -ceq 'ForEach-Object' -and $command.CommandElements.Count -eq 2 -and $command.CommandElements[1] -is [Management.Automation.Language.ScriptBlockExpressionAst]) 'Expected one per-session ForEach-Object AST body'
    $body=$command.CommandElements[1].ScriptBlock
    Assert-True ($body.EndBlock.Statements[0].Extent.Text -ceq '$folder=$_') 'Collector body no longer consumes the supplied session object'
    $allowed=@('Join-Path','New-Item','Out-Null','Test-Path','Copy-Item','Get-ChildItem','Where-Object','ForEach-Object','Get-Item')
    foreach ($call in @($body.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))) {
        Assert-True ($call.GetCommandName() -cin $allowed -and $call.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Unknown) 'Unexpected selected collector command'
    }
    # The current selected body has only these local path variables and no
    # method calls, types or declarations. This is reviewed fixture scope,
    # not a general sandbox for arbitrary future workflow edits.
    foreach ($variable in @($body.FindAll({param($node) $node -is [Management.Automation.Language.VariableExpressionAst]},$true))) {
        Assert-True ($variable.VariablePath.UserPath -cin @('_','folder','target','dest','relative','path','cleanup','cleanupDest','name','log')) 'Unexpected selected collector variable'
    }
    foreach ($member in @($body.FindAll({param($node) $node -is [Management.Automation.Language.MemberExpressionAst]},$true))) {
        Assert-True ($member.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and $member.Member.Value -cin @('Name','FullName','Length','Extension')) 'Unexpected selected collector member'
    }
    foreach ($literal in @($body.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst]},$true))) {
        Assert-True ($literal.Value -cnotmatch '^(?:[/\\]|[A-Za-z]:)|(?:^|[/\\])\.\.(?:[/\\]|$)|[\x00-\x1f]') 'Unexpected selected collector path literal'
    }
    Assert-True (@($body.FindAll({param($node) $node -is [Management.Automation.Language.ExpandableStringExpressionAst]},$true)).Count -eq 0) 'Unexpected selected collector path literal'
    Assert-True (@($body.FindAll({param($node)
        $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -or
        $node -is [Management.Automation.Language.TypeExpressionAst] -or
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    },$true)).Count -eq 0) 'Unexpected selected collector method/type/declaration'
    return [pscustomobject]@{Body=[scriptblock]::Create($body.Extent.Text.Substring(1,$body.Extent.Text.Length-2));RunText=$RunText;PipelineText=$pipeline.Extent.Text}
}
function Get-PayloadSessionCollector([string]$Workflow) {
    # Fixed YAML indentation is intentional. Reject absent/duplicate named
    # steps or alternate run encodings instead of guessing another block.
    $lines=@($Workflow -split '\r?\n')
    $matches=@(for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -ceq '      - name: Collect bounded evidence only, no executable or Oracle payload') { $i }
    })
    Assert-True ($matches.Count -eq 1) 'Expected exactly one named payload collector step'
    $begin=$matches[0]+1; $end=$lines.Count
    for ($i=$begin; $i -lt $lines.Count; $i++) { if ($lines[$i] -cmatch '^      - ') { $end=$i; break } }
    $step=@($lines[$begin..($end-1)])
    Assert-True (@($step | Where-Object { $_ -ceq '        if: always()' }).Count -eq 1) 'Collector must remain always-run'
    Assert-True (@($step | Where-Object { $_ -ceq '        shell: pwsh' }).Count -eq 1) 'Unexpected collector shell'
    $runs=@(for ($i=$begin; $i -lt $end; $i++) { if ($lines[$i] -ceq '        run: |') { $i } })
    Assert-True ($runs.Count -eq 1) 'Expected exactly one fixed-indentation collector run block'
    $run=@(for ($i=$runs[0]+1; $i -lt $end; $i++) {
        if ($lines[$i] -eq '') { ''; continue }
        Assert-True ($lines[$i].StartsWith('          ')) 'Unexpected collector run indentation'
        $lines[$i].Substring(10)
    }) -join "`n"
    return Get-RequiredSessionCollector $run
}

# Export contract: bytes originate in the real, effect-substituted refused
# Prepare above. This does not run the native helper or upload an artifact.
function Test-ControlledDiagnosticExport($Results,[string]$TestRoot) {
    $refused=@($Results | Where-Object { $_.Case.Name -ceq 'Missing' })
    Assert-True ($refused.Count -eq 1 -and $null -ne $refused[0].Error) 'Expected one captured missing-key Prepare refusal'
    $result=$refused[0]
    $source=$result.Session
    $dest=Join-Path $TestRoot 'controlled-export'
    New-Item -ItemType Directory -Path $dest | Out-Null
    $target=Join-Path $dest ([IO.Path]::GetFileName($source))
    # The 2048 cap covers added records only. Other worker output can still
    # push a real persisted helper stream beyond the collector's strict cutoff.
    $captured=[Text.Encoding]::UTF8.GetBytes($result.Sink.Captured.ToString())
    Assert-True ($result.Sink.Attempts.Count -eq 2 -and $captured.Length -le 2048) 'Refused Prepare did not capture two bounded actual records'
    $workflow=[IO.File]::ReadAllText((Join-Path $Repository '.github/workflows/windows-payload-cleanup-recovery.yml'))
    $collector=Get-PayloadSessionCollector $workflow
    # Fail-closed selection/inspection witnesses never execute rejected text.
    foreach ($sample in @(
        @{Label='missing named step';Text=$workflow.Replace('      - name: Collect bounded evidence only, no executable or Oracle payload','      - name: Other collector');Error='Expected exactly one named payload collector step'},
        @{Label='duplicate named step';Text=($workflow+"`n"+$workflow);Error='Expected exactly one named payload collector step'},
        @{Label='missing run block';Text=$workflow.Replace('        run: |','        run: >');Error='Expected exactly one fixed-indentation collector run block'}
    )) {
        $rejected=$false
        try { $null=Get-PayloadSessionCollector $sample.Text } catch { $rejected=$_.Exception.Message.Contains($sample.Error) }
        Assert-True $rejected "Collector accepted $($sample.Label) or rejected for the wrong reason"
        Write-Host "REJECTED collector $($sample.Label)"
    }
    foreach ($sample in @(
        @{Label='missing session selector';Text=$collector.RunText.Replace("-Directory -Filter 'pvbox-manager-*'","-Directory -Filter 'other-*'");Error='Expected exactly one per-session collector pipeline; found 0'},
        @{Label='ambiguous session selector';Text=($collector.RunText+"`n"+$collector.PipelineText);Error='Expected exactly one per-session collector pipeline; found 2'},
        @{Label='uninspected command';Text=$collector.RunText.Replace('Copy-Item','Get-Service');Error='Unexpected selected collector command'},
        @{Label='dynamic command';Text=$collector.RunText.Replace('Copy-Item','& $untrusted');Error='Unexpected selected collector command'},
        @{Label='out-of-scope variable';Text=$collector.RunText.Replace('$target','$env:ProgramData');Error='Unexpected selected collector variable'},
        @{Label='absolute path literal';Text=$collector.RunText.Replace('-LiteralPath $_.FullName',"-LiteralPath '/never-read-outside-owned-fixture'");Error='Unexpected selected collector path literal'},
        @{Label='parent directory member';Text=$collector.RunText.Replace('$folder.Name','$folder.Parent');Error='Unexpected selected collector member'},
        @{Label='invalid run syntax';Text='function Broken {';Error='Collector run text did not parse'}
    )) {
        $rejected=$false
        try { $null=Get-RequiredSessionCollector $sample.Text } catch { $rejected=$_.Exception.Message.Contains($sample.Error) }
        Assert-True $rejected "Collector accepted $($sample.Label) or rejected for the wrong reason"
        Write-Host "REJECTED collector $($sample.Label)"
    }
    Write-Host 'PASS unique collector AST selection and command inspection'
    [IO.File]::WriteAllBytes((Join-Path $source 'helper-Prepare-fixture.stdout.txt'),$captured)
    [IO.File]::WriteAllBytes((Join-Path $source 'helper-below-limit.txt'),[Text.Encoding]::ASCII.GetBytes(('b'*262143)))
    [IO.File]::WriteAllBytes((Join-Path $source 'helper-at-limit.txt'),[Text.Encoding]::ASCII.GetBytes(('a'*262144)))
    # Name/size selection, not executable-content filtering: all bytes below
    # are harmless text. The nested app64 entry is outside the selected scope.
    [IO.File]::WriteAllText((Join-Path $source 'helper-collector-boundary.exe'),'harmless text fixture, not an executable')
    [IO.File]::WriteAllText((Join-Path $source 'ordinary.txt'),'outside helper prefix')
    $nested=Join-Path $source 'app64'
    New-Item -ItemType Directory -Path $nested | Out-Null
    [IO.File]::WriteAllText((Join-Path $nested 'VBoxSDS.exe'),'harmless nested text fixture, not an executable')
    [IO.File]::WriteAllText((Join-Path $nested 'helper-nested.txt'),'nested helper name is outside nonrecursive selection')
    # The only pipeline input is this owned DirectoryInfo. Never run the
    # workflow's outer CommonApplicationData enumeration or other run text.
    Get-Item -LiteralPath $source | ForEach-Object -Process $collector.Body
    $stdout=Join-Path $target 'helper-Prepare-fixture.stdout.txt'
    Assert-True (Test-Path -LiteralPath $stdout -PathType Leaf) 'Controlled collector did not export captured refused-Prepare stdout'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($stdout)) -ceq [Convert]::ToBase64String($captured)) 'Collector changed actual refused-Prepare diagnostic bytes'
    $lines=@([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($stdout)).Split(@("`r`n"),[StringSplitOptions]::RemoveEmptyEntries))
    Assert-True ($lines.Count -eq 2 -and $lines[0]+"`r`n" -ceq $result.Sink.Attempts[0] -and $lines[1]+"`r`n" -ceq $result.Sink.Attempts[1]) 'Export lost complete real process/registry records or explicit CRLF'
    Assert-True ($result.State.Snapshots.Count -eq 3) 'Export fixture lacks original stage/start/intent snapshots'
    foreach ($path in $result.State.Snapshots.Keys) {
        $original=$result.State.Snapshots[$path]
        Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ceq $original) 'Export changed original stage/start/intent bytes'
        $copy=Join-Path $target ([IO.Path]::GetFileName($path))
        Assert-True ((Test-Path -LiteralPath $copy -PathType Leaf) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($copy)) -ceq $original) 'Collector changed or omitted original stage/start/intent bytes'
    }
    foreach ($name in @('sds-registered.json','session.json')) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $source $name)) -and -not (Test-Path -LiteralPath (Join-Path $target $name))) 'Refused export fabricated gate authority markers'
    }
    $below=Join-Path $target 'helper-below-limit.txt'
    Assert-True ((Test-Path -LiteralPath $below -PathType Leaf) -and (Get-Item -LiteralPath $below).Length -eq 262143) 'Collector excluded the 262143-byte helper boundary'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($below)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $source 'helper-below-limit.txt')))) 'Collector changed below-limit helper bytes'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'helper-at-limit.txt'))) 'Collector included the excluded 262144-byte helper boundary'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $target 'VBoxSDS.exe')) -and -not (Test-Path -LiteralPath (Join-Path $target 'app64'))) 'Collector included nested app64/VBoxSDS.exe fixture'
    $harmless=Join-Path $target 'helper-collector-boundary.exe'
    Assert-True ((Test-Path -LiteralPath $harmless -PathType Leaf) -and [IO.File]::ReadAllText($harmless) -ceq 'harmless text fixture, not an executable') 'Current helper name/size rule did not select harmless helper-*.exe text'
    $names=@(Get-ChildItem -LiteralPath $target -File | ForEach-Object { $_.Name } | Sort-Object)
    $expected=@('helper-Prepare-fixture.stdout.txt','helper-below-limit.txt','helper-collector-boundary.exe','prepare-intent.json','sds-register.stderr.txt','sds-register.stdout.txt','sup-standalone.json','sup-start-results.json') | Sort-Object
    Assert-True (($names -join '|') -ceq ($expected -join '|')) 'Collector selection widened beyond expected local evidence'
    Write-Host "EXPORTED actual refused-Prepare records=$($lines.Count); bytes=$($captured.Length); helper boundary=262143 included/262144 excluded; nested app64 omitted; harmless helper-*.exe selected"
    Write-Host 'PASS controlled refused Prepare diagnostic export'
}

$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-start-gate-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    if ($Target -eq 'Start') {
        $ast=Parse-Script 'vbox_sup_start_owned.ps1'
        # The preceding code proves exclusive staging, signature and initially
        # stopped state. Exercise every real statement from native launch on.
        $begin=@($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$proc'
        })[0].Extent.StartOffset
        $body=[scriptblock]::Create($ast.Extent.Text.Substring($begin))
        foreach ($case in @('Success','ExitFailure','ExitFailureStopped','Stopped','MissingService','MissingWmi','WmiStopped','Pending','TimeoutRunning','LaunchError')) {
            $out=Join-Path $testRoot $case
            New-Item -ItemType Directory -Path $out | Out-Null
            $sc='never-executed'; $stdout=Join-Path $out 'stdout'; $stderr=Join-Path $out 'stderr'; $TimeoutSeconds=5
            function Start-Process {
                if ($case -eq 'LaunchError') { throw 'simulated launch failure' }
                $p=[pscustomobject]@{Handle=[IntPtr]1;ExitCode=$(if ($case -in @('ExitFailure','ExitFailureStopped')) { 5 } else { 0 })}
                $p | Add-Member ScriptMethod WaitForExit { param($ms) if ($null -ne $ms) { return $case -ne 'TimeoutRunning' } }
                $p | Add-Member ScriptMethod Dispose {}
                return $p
            }
            function Get-Service {
                if ($case -eq 'MissingService') { return $null }
                return [pscustomobject]@{Status=$(if ($case -in @('Stopped','ExitFailureStopped')) { 'Stopped' } elseif ($case -eq 'Pending') { 'StartPending' } else { 'Running' })}
            }
            function Get-CimInstance {
                if ($case -eq 'MissingWmi') { return $null }
                return [pscustomobject]@{State=$(if ($case -in @('WmiStopped','ExitFailureStopped')) { 'Stopped' } else { 'Running' })}
            }
            function Start-Sleep {}
            $failed=$false
            try { & $body } catch { $failed=$true }
            $report=Get-Content -LiteralPath (Join-Path $out 'sup-start-results.json') -Raw | ConvertFrom-Json
            Assert-True ($report.experiment -eq 'owned-standalone-VBoxSup-start') "$case lost diagnostic evidence"
            Assert-True ($failed -eq ($case -ne 'Success')) "$case activation returned success without confirmed driver start"
            if ($case -eq 'TimeoutRunning') { Assert-True ($report.start_status -eq 'TIMEOUT') 'Late completion became success' }
        }
    } elseif ($Target -eq 'Privileged') {
        $ast=Parse-Script 'privileged_session_worker.ps1'
        Test-SdsDiagnostics $ast.Extent.Text
        $prepareResults=@(Test-PrivilegedPrepare $ast.Extent.Text $testRoot)
        Test-ControlledDiagnosticExport $prepareResults $testRoot
    } else {
        $ast=Parse-Script 'manager_session_worker.ps1'
        $prepare=$ast.Find({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq "`$Action -eq 'Prepare'"},$true)
        Assert-True ($null -ne $prepare) 'Prepare branch not found'
        $block=$prepare.Clauses[0].Item2.Extent.Text
        $fixture=Join-Path $testRoot 'effects'
        New-Item -ItemType Directory -Path $fixture | Out-Null
        $body=Join-Path $fixture 'prepare.ps1'
        Set-Content -LiteralPath $body -Value $block.Substring(1,$block.Length-2)
        Set-Content -LiteralPath (Join-Path $fixture 'vbox_sup_standalone.ps1') -Value 'param($AppDir,$OutputDirectory)'
        Set-Content -LiteralPath (Join-Path $fixture 'vbox_sup_start_owned.ps1') -Value @'
param($StandaloneReport,$OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
if ($case -ne 'MissingReceipt') {
    $fixtureReceipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'sup-start-results.json')
}
'@
        foreach ($case in @('Success','ExitFailure','Timeout','Stopped','WrongExperiment','MissingReceipt','WrongInitial','ForeignServices','WmiStopped','MissingField','StringTrue')) {
            $session=Join-Path $testRoot $case; $root=$session; $app=Join-Path $session 'app64'
            $PSScriptRoot=$fixture
            $TestBreakAfter='None'; $ControllerPid=123; $ControllerCreated=456L; $controllerImage='controller.exe'; $parentId=123; $parentStart='456'; $parentPath='controller.exe'
            $fixtureReceipt=@{experiment='owned-standalone-VBoxSup-start';start_status='EXITED';start_exit_code=0;driver_running=$true;initial_status='Stopped';service_status_after='Running';wmi_driver_state='Running';no_other_vbox_services_before=$true}
            switch ($case) {
                'ExitFailure' { $fixtureReceipt.start_exit_code=5 }
                'Timeout' { $fixtureReceipt.start_status='TIMEOUT' }
                'Stopped' { $fixtureReceipt.driver_running=$false; $fixtureReceipt.service_status_after='Stopped' }
                'WrongExperiment' { $fixtureReceipt.experiment='unrelated' }
                'WrongInitial' { $fixtureReceipt.initial_status='Running' }
                'ForeignServices' { $fixtureReceipt.no_other_vbox_services_before=$false }
                'WmiStopped' { $fixtureReceipt.wmi_driver_state='Stopped' }
                'MissingField' { $fixtureReceipt.Remove('driver_running') }
                'StringTrue' { $fixtureReceipt.driver_running='true' }
            }
            $effects=@{Calls=0}
            function Check-App {}
            function Run-Oracle { $effects.Calls++ }
            function Get-ItemProperty { return [pscustomobject]@{ImagePath=(Join-Path $app 'VBoxSDS.exe');Type=16;Start=3;ObjectName='LocalSystem'} }
            # Only the HKLM existence probe is synthetic. Local receipt reads
            # and writes use the real filesystem and ConvertFrom-Json.
            function Test-Path {
                param($LiteralPath,$Path,$PathType)
                $value=if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($value -like 'HKLM:*') { return $false }
                return Microsoft.PowerShell.Management\Test-Path -LiteralPath $value
            }
            $failed=$false
            try { & $body } catch { $failed=$true; if ($case -eq 'Success') { throw } }
            Assert-True ($failed -eq ($case -ne 'Success')) "$Target/$case preparation did not fail closed"
            Assert-True ($effects.Calls -eq $(if ($case -eq 'Success') { 1 } else { 0 })) "$Target/$case ran downstream effects before confirmation"
            Assert-True ((Test-Path -LiteralPath (Join-Path $session 'session.json')) -eq ($case -eq 'Success')) "$Target/$case emitted invalid prepared receipt"
            if ($case -ne 'Success') { Assert-True (-not (Test-Path -LiteralPath (Join-Path $session 'sds-registered.json'))) "$Target/$case emitted SDS receipt" }
        }
    }
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
Write-Host "PASS $Target driver start gate"
