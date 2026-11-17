# TEST ONLY: owned file/IPC fixtures, no child/VBox/elevation/production entry.
[CmdletBinding()]
param([switch]$ManagedOnly,[string]$EvidenceDirectory='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($ManagedOnly) {
    Add-Type -Path @((Join-Path $PSScriptRoot 'NativePipeTransport.cs'),(Join-Path $PSScriptRoot 'NativePipeTransportTests.cs'))
    if ([PortableVBox.NativePipeTransportTests]::RunManaged() -ne 0) { throw 'Managed pipe contracts failed' }
    return
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Output 'SKIP native pipe transport: Windows required'
    return
}
$out=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-pipe-build-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$started=$false
$safeToCleanup=$false
$writer=$null
$summary=$null
$log=Join-Path $out 'native-pipe-transport.jsonl'
$nativeExit=1
try {
    $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $exe=Join-Path $out 'NativePipeTransportTests.exe'
    $sources=@('NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs',
        'NativePipeTransportNativeTests.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    & $csc /nologo /target:exe /platform:x64 /langversion:5 /warnaserror+ /main:PortableVBox.NativePipeTransportNativeTests ('/out:'+$exe) @sources
    if ($LASTEXITCODE -ne 0) { throw 'Native pipe transport compilation failed' }
    [IO.File]::WriteAllText(($exe+'.config'),'<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup></configuration>')
    $encoder=New-Object Text.UTF8Encoding($false,$true)
    $writer=New-Object IO.FileStream($log,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $total=0
    $records=0
    $started=$true
    # Streaming consumption, never @(& exe) or accumulating an unbounded text blob.
    & $exe | ForEach-Object {
        $line=[string]$_
        if ($line.Length -gt 4095 -or $records -ge 64) { throw 'Native evidence record bound exceeded' }
        $length=$encoder.GetByteCount($line)+1
        if ($length -gt 4096 -or $total+$length -gt 262144) { throw 'Native UTF-8 evidence bound exceeded' }
        $report=$line | ConvertFrom-Json
        if ($report.mutation_authorized -isnot [bool] -or $report.mutation_authorized) { throw 'Observations cannot authorize mutation' }
        if ($report.kind -eq 'native_pipe_summary') {
            if ($null -ne $summary) { throw 'Duplicate native summary' }
            $summary=$report
        }
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
        # Validate failure records too. Python uses bounded reads before UTF-8/JSON parsing,
        # rejects duplicate keys/non-JSON numbers, and grants no release/admission authority.
        $validator=Join-Path (Split-Path $PSScriptRoot -Parent) 'test_native_pipe_transport_contract.py'
        & python $validator --validate-evidence $log
        $valid=($LASTEXITCODE -eq 0)
        if ($valid -and $null -ne $summary -and $summary.all_owners_released -is [bool] -and $summary.all_owners_released) {
            $receipt=Join-Path $out 'pipe-fixture-released'
            if ((Test-Path -LiteralPath $receipt -PathType Leaf) -and (Get-Item -LiteralPath $receipt).Length -le 128) {
                $safeToCleanup=([IO.File]::ReadAllText($receipt) -ceq "all rooted native fixture resources explicitly released`n")
            }
        }
        if ($valid -and $EvidenceDirectory) {
            if (-not (Test-Path -LiteralPath $EvidenceDirectory)) { New-Item -ItemType Directory -Path $EvidenceDirectory | Out-Null }
            $source=New-Object IO.FileStream($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            $destination=$null
            try {
                if ($source.Length -gt 262144) { throw 'Evidence artifact bound exceeded before copy' }
                $destination=New-Object IO.FileStream((Join-Path $EvidenceDirectory 'native-pipe-transport.jsonl'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
                $buffer=New-Object byte[] 4096
                $copied=0
                while (($read=$source.Read($buffer,0,$buffer.Length)) -gt 0) {
                    if ($copied+$read -gt 262144) { throw 'Evidence changed beyond copy bound' }
                    $destination.Write($buffer,0,$read)
                    $copied+=$read
                }
                $destination.Flush($true)
            } finally {
                $source.Dispose()
                if ($null -ne $destination) { $destination.Dispose() }
            }
        }
        if (-not $valid) { Write-Warning 'Invalid native evidence retained for local inspection; it will not be published as verified JSONL' }
    }
    if (-not $started -or $safeToCleanup) {
        # Only this generated build root; no paths from reports, no external resources.
        Remove-Item -LiteralPath $out -Recurse -Force
    } else {
        Write-Warning ('UNRESOLVED: exact native resource release not proved; generated resources/evidence preserved at '+$out+'. Process teardown is not successful explicit cancellation.')
    }
}
if ($nativeExit -ne 0) { throw ('Native pipe transport contracts failed: '+$nativeExit) }
if (-not $safeToCleanup) { throw 'Native pipe transport did not prove explicit resource release' }
if ($null -eq $summary -or $summary.status -cne 'PASS') { throw 'Native pipe transport summary is not PASS' }
