# TEST ONLY: file-only fixed sibling harnesses, never launch the fixture child.
[CmdletBinding()]
param([switch]$ManagedOnly,[string]$EvidenceDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NativeFixedFixtureBuild.ps1')
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
function Write-Record([string]$Line) {
    if ($Line.Length -gt 16383 -or $script:records -ge 5) { throw 'Fixed image record bound' }
    $bytes=$encoder.GetBytes($Line+"`n")
    if ($bytes.Length -gt 16384 -or $script:total+$bytes.Length -gt 131072) { throw 'Fixed image UTF8 artifact bound' }
    $writer.Write($bytes,0,$bytes.Length);$writer.Flush($true)
    $script:total+=$bytes.Length;++$script:records
    Write-Output $Line
}
try {
    $build=New-FixedFixtureBuild $out
    $child=$build.PristineChild
    $length=(Get-Item -LiteralPath $child).Length
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
        $sources=@(Get-FixedFixtureConsumerSources $build @('NativeFixedImageIdentity.cs','NativeFixedImageIdentityTests.cs','NativeFixedImageIdentityNativeTests.cs'))
        Compile-FixedFixtureSources @($sources+$caseSource) $exe 'PortableVBox.NativeFixedImageIdentityNativeTests'
        $harnesses+=,$exe
    }
    [Reflection.Assembly]::LoadFile($harnesses[0]) | Out-Null
    if ([PortableVBox.NativeFixedImageIdentityTests]::RunManaged() -ne 0) { throw 'Fixed image managed contracts failed' }
    Assert-FixedFixtureBuild $build
    $pristineBytes=[IO.File]::ReadAllBytes($build.PristineChild)
    if ([PortableVBox.NativeFixedImageIdentityTests]::RunInjectedOwners($pristineBytes) -ne 0) { throw 'Fixed image injected owners failed' }
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
    Assert-FixedFixtureBuild $build
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
