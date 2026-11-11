# TEST ONLY: fixed sibling harmless child, owned pipes/files, no VBox or authority.
[CmdletBinding()]
param([switch]$ManagedOnly,[string]$EvidenceDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Invoke-ManagedContracts {
    Add-Type -Path @((Join-Path $PSScriptRoot 'NativePipeTransport.cs'),
        (Join-Path $PSScriptRoot 'NativeChildCapture.cs'),
        (Join-Path $PSScriptRoot 'NativeChildCaptureTests.cs'))
    if ([PortableVBox.NativeChildCaptureTests]::RunManaged() -ne 0) { throw 'Managed child capture contracts failed' }
}
if ($ManagedOnly) {
    Invoke-ManagedContracts
    return
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Output 'SKIP native child capture: Windows required'
    return
}
Invoke-ManagedContracts
$out=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-child-capture-build-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$writer=$null
$log=Join-Path $out 'native-child-capture.jsonl'
$validator=Join-Path (Split-Path $PSScriptRoot -Parent) 'test_native_child_capture_contract.py'
$nativeExit=1
$valid=$false
try {
    $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $child=Join-Path $out 'NativeCaptureFixtureChild.exe'
    & $csc /nologo /codepage:65001 /target:exe /platform:x64 /langversion:5 /warnaserror+ ('/out:'+$child) (Join-Path $PSScriptRoot 'NativeCaptureFixtureChild.cs') (Join-Path $PSScriptRoot 'NativeLaunchEnvironmentObservation.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Fixed harmless capture child compilation failed' }
    $exe=Join-Path $out 'NativeChildCaptureTests.exe'
    $sources=@('NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs',
        'NativeChildCapture.cs','NativeChildCaptureTests.cs','NativeChildCaptureNative.cs',
        'NativeChildCaptureNativeTests.cs','NativeLaunchEnvironment.cs','NativeLaunchEnvironmentNative.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    & $csc /nologo /codepage:65001 /target:exe /platform:x64 /langversion:5 /warnaserror+ /main:PortableVBox.NativeChildCaptureNativeTests ('/out:'+$exe) @sources
    if ($LASTEXITCODE -ne 0) { throw 'Native child capture contracts compilation failed' }
    foreach ($program in @($child,$exe)) {
        [IO.File]::WriteAllText(($program+'.config'),'<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup></configuration>')
    }
    $encoder=New-Object Text.UTF8Encoding($false,$true)
    $writer=New-Object IO.FileStream($log,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $total=0
    $records=0
    # Fixed harness only; no caller-supplied executable, command or evidence input.
    # Stream bounded records rather than accumulating the entire harness output.
    & $exe | ForEach-Object {
        $line=[string]$_
        if ($line.Length -gt 4095 -or $records -ge 10) { throw 'Native child evidence record bound exceeded' }
        $length=$encoder.GetByteCount($line)+1
        if ($length -gt 4096 -or $total+$length -gt 262144) { throw 'Native child UTF-8 evidence bound exceeded' }
        $bytes=$encoder.GetBytes($line+"`n")
        $writer.Write($bytes,0,$bytes.Length)
        $writer.Flush($true)
        $total+=$bytes.Length
        ++$records
        Write-Output $line
    }
    $nativeExit=$LASTEXITCODE
} finally {
    if ($null -ne $writer) { $writer.Dispose(); $writer=$null }
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        # Strictly validate failure diagnostics as well. This only controls publishing
        # text evidence; JSON fields and receipts never authorize resource release.
        & python $validator --validate-evidence $log
        $valid=($LASTEXITCODE -eq 0)
        if ($valid -and $EvidenceDirectory) {
            if (-not (Test-Path -LiteralPath $EvidenceDirectory)) { New-Item -ItemType Directory -Path $EvidenceDirectory | Out-Null }
            $source=New-Object IO.FileStream($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            $destination=$null
            try {
                if ($source.Length -gt 262144) { throw 'Child evidence artifact bound exceeded before copy' }
                $destination=New-Object IO.FileStream((Join-Path $EvidenceDirectory 'native-child-capture.jsonl'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                $buffer=New-Object byte[] 4096
                $copied=0
                while (($read=$source.Read($buffer,0,$buffer.Length)) -gt 0) {
                    if ($copied+$read -gt 262144) { throw 'Child evidence changed beyond copy bound' }
                    $destination.Write($buffer,0,$read)
                    $copied+=$read
                }
                $destination.Flush($true)
            } finally {
                $source.Dispose()
                if ($null -ne $destination) { $destination.Dispose() }
            }
        }
        if (-not $valid) { Write-Warning 'Invalid child evidence retained locally; it will not be published as verified JSONL' }
    }
    # Always preserve this generated directory. No serialized report, receipt,
    # exit code or count is resource-release authority. The native rooted owner
    # alone observes exact terminal operations and closes its owned resources.
    Write-Warning ('Generated child build/evidence retained at '+$out+'. Process teardown is not proof of explicit resource release.')
}
if ($nativeExit -ne 0) { throw ('Native child capture contracts failed: '+$nativeExit) }
if (-not $valid) { throw 'Native child capture evidence failed strict validation' }
& python $validator --validate-evidence $log --require-pass
if ($LASTEXITCODE -ne 0) { throw 'Native child capture did not report all nine passing observational contracts' }
