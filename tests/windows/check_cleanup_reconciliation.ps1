# File-only rehearsal on COPIES of the pinned Oracle payload. No helper,
# service, registry, VirtualBox process or driver actions; never inspect a live session.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AppDir)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$app=(Resolve-Path -LiteralPath $AppDir).Path
$manifest=Join-Path $app '.prepared.json'
$original=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
$before=@(Get-ChildItem -LiteralPath $app -Recurse -File | Get-FileHash -Algorithm SHA256 | Sort-Object Path | Select-Object Path,Hash | ConvertTo-Json -Compress)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-cleanup-review-'+[guid]::NewGuid().ToString('N'))
$session=Join-Path $temp 'session'
New-Item -ItemType Directory -Path $session -Force | Out-Null
function Review([string]$ExpectedState,[int]$ExpectedCode=0) {
    $output=& python -B -X utf8 (Join-Path $repo 'scripts/reconcile_cleanup.py') $session --manifest $manifest
    if ($LASTEXITCODE -ne $ExpectedCode) { throw "Unexpected reconciliation exit: $LASTEXITCODE $output" }
    $result=$output | ConvertFrom-Json
    if ($result.resume_authorized -ne $false -or $result.ownership -ne 'UNVERIFIED' -or $result.system_state -ne 'NOT_OBSERVED') {
        throw 'File observation manufactured cleanup authority'
    }
    if ($ExpectedCode -eq 0 -and ($result.status -ne 'REVIEW_ONLY' -or $result.oracle_payload.state -ne $ExpectedState)) {
        throw 'Wrong read-only payload observation'
    }
    if ($ExpectedCode -ne 0 -and $result.status -ne 'BLOCKED') { throw 'Unsafe input accepted' }
    return $result
}
try {
    Copy-Item -LiteralPath $app -Destination (Join-Path $session 'app64') -Recurse
    $code=New-Item -ItemType Directory -Path (Join-Path $session 'code')
    foreach($name in @('privileged_session_worker.ps1','vbox_sup_standalone.ps1','vbox_sup_start_owned.ps1','vbox_sup_cleanup.ps1','vbox_sup_partial_cleanup.ps1','vbox_sup_package_identity.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repo ('scripts/'+$name)) -Destination $code.FullName
    }
    $result=Review 'INTACT'
    if ($result.oracle_payload.present_count -ne 185 -or $result.script_payload.present_count -ne 6) { throw 'Wrong pinned inventory counts' }
    # Malformed and extra fixture data must not be interpreted as residue to delete.
    $extra=Join-Path $session 'app64/unknown.dll'
    [IO.File]::WriteAllText($extra,'unowned');Review '' 3 | Out-Null
    Remove-Item -LiteralPath $extra
    $removed=Join-Path $session ('app64/'+$original.files[0].path)
    Remove-Item -LiteralPath $removed
    $result=Review 'PARTIAL'
    if ($result.oracle_payload.missing_count -ne 1) { throw 'Partial payload count mismatch' }
    Remove-Item -LiteralPath (Join-Path $session 'app64/.prepared.json')
    $result=Review 'PARTIAL'
    if ($result.manifest_copy -ne 'ABSENT') { throw 'Missing protected manifest hidden' }
    Remove-Item -LiteralPath (Join-Path $session 'app64') -Recurse
    $result=Review 'FILES_ABSENT'
    if ($result.script_payload.state -ne 'INTACT') { throw 'Remaining code was hidden' }
    Remove-Item -LiteralPath $code.FullName -Recurse
    New-Item -ItemType Directory -Path (Join-Path $session 'cleanup') | Out-Null
    [IO.File]::WriteAllText((Join-Path $session 'cleanup/cleanup-results.json'),'{"cleanup_verified":true,"driver_package_removed":true,"errors":[]}')
    [IO.File]::WriteAllText((Join-Path $session 'payload-removed.json'),'{"protected_payload_removed":true}')
    $result=Review 'FILES_ABSENT'
    if ($result.cleanup_receipt -ne 'CLAIMS_VERIFIED' -or $result.script_payload.state -ne 'FILES_ABSENT') { throw 'Claims or empty code misclassified' }
    $after=@(Get-ChildItem -LiteralPath $app -Recurse -File | Get-FileHash -Algorithm SHA256 | Sort-Object Path | Select-Object Path,Hash | ConvertTo-Json -Compress)
    if (($before | Out-String) -cne ($after | Out-String)) { throw 'Original pinned app64 changed during read-only inspection' }
    Write-Host 'PASS cleanup reconciliation: genuine 185-file pin; intact/partial/absent; originals unchanged; no authority or system effects'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
