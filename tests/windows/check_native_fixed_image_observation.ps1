# TEST ONLY: file-only fixed sibling harnesses, never launch the fixture child.
[CmdletBinding()]
param([switch]$ManagedOnly,[string]$EvidenceDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$windows=([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
if (-not $ManagedOnly -and -not $windows) {
    Write-Output 'SKIP native fixed image observation: Windows required'
    return
}
$out=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-fixed-image-build-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$encoder=New-Object Text.UTF8Encoding($false,$true)
$names=@('matching-image','digest-mismatch','size-mismatch','missing-image')
$log=Join-Path $out 'native-fixed-image-observation.jsonl'
$validator=Join-Path (Split-Path $PSScriptRoot -Parent) 'test_native_fixed_image_observation_contract.py'
$writer=$null
$records=0
$total=0
$failed=0
$stop='none'
$valid=$false
function Compile-Fixed([string[]]$Sources,[string]$Output,[string]$MainType) {
    if ($windows) {
        $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        & $csc /nologo /codepage:65001 /target:exe /platform:x64 /langversion:5 /warnaserror+ ('/main:'+$MainType) ('/out:'+$Output) @Sources
        if ($LASTEXITCODE -ne 0) { throw 'Fixed image C#5/x64 compilation failed' }
    } else {
        # Managed-only compilation against explicitly provided official net48 refs.
        # This path never invokes a generated executable or supplies native inputs.
        if (-not $ManagedOnly -or -not $env:PVBOX_TEST_NET48_REFERENCES) { throw 'Managed-only compilation requires PVBOX_TEST_NET48_REFERENCES' }
        Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.dll')
        Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll')
        $parse=[Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::new([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp5)
        $trees=[Microsoft.CodeAnalysis.SyntaxTree[]]@($Sources | ForEach-Object { [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText($_),$parse) })
        $references=[Microsoft.CodeAnalysis.MetadataReference[]]@(@('mscorlib.dll','System.dll','System.Core.dll','System.Security.dll') | ForEach-Object { [Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $env:PVBOX_TEST_NET48_REFERENCES $_)) })
        $options=[Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::ConsoleApplication)
        $options=$options.WithPlatform([Microsoft.CodeAnalysis.Platform]::X64).WithGeneralDiagnosticOption([Microsoft.CodeAnalysis.ReportDiagnostic]::Error).WithMainTypeName($MainType)
        $compile=[Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create([IO.Path]::GetFileNameWithoutExtension($Output),$trees,$references,$options)
        $stream=[IO.File]::Open($Output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try { $result=$compile.Emit($stream) } finally { $stream.Dispose() }
        if (-not $result.Success) { $result.Diagnostics | ForEach-Object { Write-Output $_.ToString() };throw 'Managed-only C#5/x64/net48 compilation failed' }
    }
    [IO.File]::WriteAllText(($Output+'.config'),'<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup></configuration>',$encoder)
}
function Write-Record([string]$Line) {
    if ($Line.Length -gt 16383 -or $script:records -ge 5) { throw 'Fixed image record bound' }
    $bytes=$encoder.GetBytes($Line+"`n")
    if ($bytes.Length -gt 16384 -or $script:total+$bytes.Length -gt 131072) { throw 'Fixed image UTF8 artifact bound' }
    $writer.Write($bytes,0,$bytes.Length);$writer.Flush($true)
    $script:total+=$bytes.Length;++$script:records
    Write-Output $Line
}
try {
    $pristine=Join-Path $out 'pristine'
    New-Item -ItemType Directory -Path $pristine | Out-Null
    $child=Join-Path $pristine 'NativeCaptureFixtureChild.exe'
    Compile-Fixed @((Join-Path $PSScriptRoot 'NativeCaptureFixtureChild.cs'),(Join-Path $PSScriptRoot 'NativeLaunchEnvironmentObservation.cs')) $child 'PortableVBox.NativeCaptureFixtureChild'
    # Hash completed pristine bytes ONCE, before any negative copy is prepared.
    $length=(Get-Item -LiteralPath $child).Length
    if ($length -le 0 -or $length -gt 16777216) { throw 'Pristine image size bound' }
    $digest=(Get-FileHash -LiteralPath $child -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($digest -cnotmatch '\A[0-9a-f]{64}\z') { throw 'Pristine digest syntax' }
    $expectation=Join-Path $out 'FixedFixtureBuildExpectation.g.cs'
    $generated="// Generated from completed pristine harmless build bytes. TEST ONLY.`nnamespace PortableVBox { internal static class FixedFixtureBuildExpectation { internal const string Name = `"NativeCaptureFixtureChild.exe`"; internal const long Length = "+$length.ToString([Globalization.CultureInfo]::InvariantCulture)+"L; internal const string Sha256 = `""+$digest+"`"; } }`n"
    if ($encoder.GetByteCount($generated) -gt 2048) { throw 'Generated expectation source bound' }
    [IO.File]::WriteAllText($expectation,$generated,$encoder)
    $expectationDigest=(Get-FileHash -LiteralPath $expectation -Algorithm SHA256).Hash
    $harnesses=@()
    # Fixed Cyrillic+CJK case segment; keep script bytes ASCII for Windows PS 5.1.
    $caseRoot=Join-Path $out ('fixed-'+[char]0x0416+'-'+[char]0x6f22)
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    # Each harness has one compile-time allowlisted case. No runtime selectors.
    foreach ($name in $names) {
        $directory=Join-Path $caseRoot $name
        New-Item -ItemType Directory -Path $directory | Out-Null
        $caseSource=Join-Path $directory 'FixedFixtureCase.g.cs'
        [IO.File]::WriteAllText($caseSource,('namespace PortableVBox { internal static class FixedFixtureCase { internal const string Name = "'+$name+'"; } }'),$encoder)
        $exe=Join-Path $directory 'NativeFixedImageIdentityTests.exe'
        if (-not (Test-Path -LiteralPath $expectation -PathType Leaf) -or (Get-FileHash -LiteralPath $expectation -Algorithm SHA256).Hash -ne $expectationDigest) { throw 'Missing or stale pristine expectation' }
        Compile-Fixed @((Join-Path $PSScriptRoot 'NativeFixedImageIdentity.cs'),(Join-Path $PSScriptRoot 'NativeFixedImageIdentityTests.cs'),(Join-Path $PSScriptRoot 'NativeFixedImageIdentityNativeTests.cs'),$expectation,$caseSource) $exe 'PortableVBox.NativeFixedImageIdentityNativeTests'
        $harnesses+=,$exe
    }
    [Reflection.Assembly]::LoadFile($harnesses[0]) | Out-Null
    if ([PortableVBox.NativeFixedImageIdentityTests]::RunManaged() -ne 0) { throw 'Fixed image managed contracts failed' }
    for ($i=0;$i -lt 3;++$i) { Write-Output ('SERIALIZER_DIAGNOSTIC '+[PortableVBox.NativeFixedImageIdentityTests]::IncompleteReport($i)) }
    if ($ManagedOnly) { return }
    # Negative setup occurs only after ALL harnesses embed unchanged pristine input.
    for ($i=0;$i -lt 3;++$i) { Copy-Item -LiteralPath $child -Destination (Join-Path (Split-Path $harnesses[$i] -Parent) 'NativeCaptureFixtureChild.exe') }
    $negative=Join-Path (Split-Path $harnesses[1] -Parent) 'NativeCaptureFixtureChild.exe'
    $bytes=[IO.File]::ReadAllBytes($negative);$bytes[0]=$bytes[0] -bxor 1
    [IO.File]::WriteAllBytes($negative,$bytes)
    if ((Get-Item -LiteralPath $negative).Length -ne $length) { throw 'Digest negative changed length' }
    $larger=Join-Path (Split-Path $harnesses[2] -Parent) 'NativeCaptureFixtureChild.exe'
    $append=[IO.File]::Open($larger,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $append.WriteByte(0);$append.Flush($true) } finally { $append.Dispose() }
    if ((Get-FileHash -LiteralPath $expectation -Algorithm SHA256).Hash -ne $expectationDigest) { throw 'Pristine expectation changed after negative setup' }
    $writer=[IO.File]::Open($log,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    foreach ($exe in $harnesses) {
        $seen=0
        $caseStatus=''
        & $exe | ForEach-Object {
            ++$seen;if ($seen -ne 1) { throw 'Expected exactly one case record per fixed harness' }
            $line=[string]$_
            if ($line.Length -gt 16383) { throw 'Fixed case record character bound' }
            $decoded=$line | ConvertFrom-Json
            if ($decoded.status -notin @('PASS','FAIL')) { throw 'Missing case status' }
            $caseStatus=[string]$decoded.status
            Write-Record $line
            if ($caseStatus -eq 'FAIL') { ++$script:failed }
        }
        $code=$LASTEXITCODE
        if ($seen -ne 1 -or $code -notin @(0,1,2) -or (($code -eq 0) -ne ($caseStatus -eq 'PASS'))) { throw 'Fixed harness missing record or inconsistent exit' }
        if ($code -eq 2) { $stop='unresolved-owner';break }
    }
    if ($stop -eq 'none' -and $failed -gt 0) { $stop='case-failure' }
} catch {
    if ($ManagedOnly) { throw }
    if ($null -eq $writer) { $writer=[IO.File]::Open($log,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$stop='build-failure' }
    else { $stop='evidence-failure' }
    Write-Warning $_.Exception.Message
} finally {
    if (-not $ManagedOnly) {
        if ($null -ne $writer) {
            $status=if ($stop -eq 'none' -and $records -eq 4 -and $failed -eq 0) { 'PASS' } else { 'FAIL' }
            if ($status -eq 'FAIL' -and $stop -eq 'none') { $stop='evidence-failure' }
            try { Write-Record ('{"kind":"fixed_image_summary","schema":1,"stage":"file-only","status":"'+$status+'","cases":'+$records+',"failed":'+$failed+',"stop_reason":"'+$stop+'","mutation_authorized":false}') }
            finally { $writer.Dispose();$writer=$null }
        }
        if (Test-Path -LiteralPath $log -PathType Leaf) {
            & python $validator --validate-evidence $log
            $valid=($LASTEXITCODE -eq 0)
            if ($valid -and $EvidenceDirectory) {
                if (-not (Test-Path -LiteralPath $EvidenceDirectory)) { New-Item -ItemType Directory -Path $EvidenceDirectory | Out-Null }
                # The validator bounded this retained text. Copy only that separate artifact.
                $source=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                $destination=$null
                try {
                    if ($source.Length -gt 131072) { throw 'Fixed image copy source bound' }
                    $destination=[IO.File]::Open((Join-Path $EvidenceDirectory 'native-fixed-image-observation.jsonl'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                    $buffer=New-Object byte[] 16384;$copied=0
                    while (($read=$source.Read($buffer,0,$buffer.Length)) -gt 0) {
                        if ($copied+$read -gt 131072) { throw 'Fixed image evidence changed beyond bound' }
                        $destination.Write($buffer,0,$read);$copied+=$read
                    }
                    $destination.Flush($true)
                } finally { $source.Dispose();if ($null -ne $destination) { $destination.Dispose() } }
            }
        }
    }
    # Keep generated constants/builds. Diagnostic records never authorize cleanup/retry.
    Write-Warning ('Generated fixed image build/evidence retained at '+$out+'. Process teardown is not explicit native release evidence.')
}
if (-not $valid) { throw 'Fixed image diagnostics failed strict validation' }
& python $validator --validate-evidence $log --require-pass
if ($LASTEXITCODE -ne 0) { throw 'Fixed image file-only cases did not all pass' }
