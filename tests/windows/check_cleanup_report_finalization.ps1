# Execute only the production finally block with a synthetic service observer.
# No registry, service, driver, process or elevation operations are performed.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/vbox_sup_cleanup.ps1'),[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Production cleanup parse error' }
$blocks=@($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] -and $null -ne $_.Finally })
if ($blocks.Count -ne 1) { throw 'Expected one top-level cleanup finally' }
$body=$blocks[0].Finally.Extent.Text
$finalizer=[scriptblock]::Create($body.Substring(1,$body.Length-2))
$root=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-final-report-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks=0
function Check([bool]$Pass,[string]$Name) { if (-not $Pass) { throw "FAIL cleanup report: $Name" }; $script:checks++ }
function Get-VBoxNames {
    switch ($script:observation) {
        'error' { throw [UnauthorizedAccessException]::new('fixture observation denied') }
        'partial-error' { 'VBoxSup'; throw [IO.IOException]::new('fixture partial observation') }
        'present' { 'VBoxSup' }
        'absent' { }
    }
}
try {
    foreach ($observation in @('error','partial-error','present','absent')) {
        foreach ($wasVerified in @($false,$true)) {
          foreach ($hadError in @($false,$true)) {
            $out=Join-Path $root ($observation+'-'+$wasVerified+'-'+$hadError)
            New-Item -ItemType Directory -Path $out | Out-Null
            $report=[ordered]@{cleanup_verified=$wasVerified;driver_package_removed=$true;
                sds_cleanup='CLEAN';service_stop='EXIT_0';driver_package_removal='EXIT_0';
                final_vbox_services=@();errors=@()}
            if ($hadError) { $report.errors+= 'original operation error' }
            $initialErrors=$report.errors.Count
            $failed=$false
            try { . $finalizer } catch { $failed=$true }
            Check (-not $failed) 'observation failure must not suppress report write'
            $saved=Get-Content -LiteralPath (Join-Path $out 'cleanup-results.json') -Raw | ConvertFrom-Json
            Check (($saved.errors -contains 'original operation error') -eq $hadError) 'original error state retained'
            Check ($saved.sds_cleanup -eq 'CLEAN' -and $saved.service_stop -eq 'EXIT_0' -and $saved.driver_package_removed) 'prior step evidence retained'
            if ($observation -in @('error','partial-error')) {
                Check ($null -eq $saved.final_vbox_services) 'unknown is not empty or partial service list'
                Check ($saved.final_vbox_services_observation -eq 'UNKNOWN') 'unknown explicit'
                Check (-not $saved.cleanup_verified -and $saved.errors.Count -eq ($initialErrors+1)) 'uncertainty invalidates cleanup and records failure'
            } elseif ($observation -eq 'present') {
                Check ($saved.final_vbox_services_observation -eq 'OBSERVED') 'presence observation explicit'
                Check (@($saved.final_vbox_services).Count -eq 1) 'observed service preserved'
                Check (-not $saved.cleanup_verified) 'late service invalidates clean claim'
                Check ($saved.errors.Count -eq ($initialErrors+1)) 'late service blocks worker success'
            } else {
                Check ($saved.final_vbox_services_observation -eq 'OBSERVED') 'absence observation explicit'
                Check (@($saved.final_vbox_services).Count -eq 0) 'observed absence list empty'
                Check ($saved.cleanup_verified -eq $wasVerified) 'final observation never promotes cleanup'
                Check ($saved.errors.Count -eq $initialErrors) 'no spurious observation error'
            }
          }
        }
    }
    # A write failure remains fatal; no fabricated saved result.
    $out=Join-Path $root 'missing-parent/child';$observation='absent';$failed=$false
    try { . $finalizer } catch { $failed=$true }
    Check $failed 'report write failure is not swallowed'
    Write-Host "CLEANUP_REPORT_FINALIZATION_PASS checks=$checks"
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
