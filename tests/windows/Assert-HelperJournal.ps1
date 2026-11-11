# Independent test-only decoder for fixed-helper evidence. Never executes a helper action.
function Assert-HelperJournal([string]$Path,[string]$Action,[int]$Cycle,[bool]$Complete,
    [object]$Controller,[string]$Root,[string]$Frontend,[int]$OriginalPid=0,[string]$OriginalCreated='0') {
    # Independent decoder: do not trust the writer's own Inspect implementation.
    $bytes=[IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 1 -or $bytes.Length -gt 65536) { throw 'Journal size mismatch' }
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $text=$utf8.GetString($bytes)
    $lines=$text.Split([char]10)
    $count=if($Complete){3}else{2}
    if ($lines.Count -ne $count+2 -or $lines[-1] -ne '' -or $lines[0] -notmatch '^PVBJ1\t([^\t]+)$') { throw 'Journal framing mismatch' }
    $binding=$utf8.GetString([Convert]::FromBase64String($Matches[1])) | ConvertFrom-Json
    $facts=$Controller
    if ($binding.attempt -notmatch '^[0-9a-f]{32}$' -or
        (Split-Path $Path -Leaf) -cne ('helper-'+$Action+'-'+$binding.attempt+'.journal') -or
        $binding.schema -ne 1 -or $binding.action -cne $Action -or $binding.mode -cne 'CI' -or
        $binding.controller_pid -ne $facts.Pid -or $binding.controller_created_filetime -cne ([string]$facts.Created) -or
        $binding.sid -cne $facts.Sid -or $binding.desktop_session -ne $facts.Session -or
        $binding.cycle -ne $Cycle -or $binding.portable_root -cne $Root -or
        $binding.protected_session -cne (Split-Path $Path -Parent) -or
        $binding.frontend_sha256 -cne (Get-FileHash -LiteralPath $Frontend -Algorithm SHA256).Hash.ToLowerInvariant() -or
        $binding.original_controller_pid -ne $OriginalPid -or $binding.original_controller_created_filetime -cne $OriginalCreated) { throw 'Journal owner/build binding mismatch' }
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $previous=[BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($lines[0]+"`n"))).Replace('-','').ToLowerInvariant()
        $kinds=@('INTENT','WORKER_EXIT','HELPER_COMPLETE')
        for($i=0;$i -lt $count;$i++) {
            $fields=$lines[$i+1].Split([char]9)
            if($fields.Count -ne 5 -or $fields[0] -cne ([string]$i) -or $fields[1] -cne $kinds[$i] -or $fields[3] -cne $previous) { throw 'Journal event order mismatch' }
            $prefix=$fields[0..3] -join "`t"
            $previous=[BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($prefix))).Replace('-','').ToLowerInvariant()
            if($fields[4] -cne $previous) { throw 'Journal event hash mismatch' }
            $payload=$utf8.GetString([Convert]::FromBase64String($fields[2]))
            if($i -eq 0 -and $payload -cne $Action) { throw 'Journal action mismatch' }
            if($i -eq 1) {
                $exit=$payload | ConvertFrom-Json
                if(-not $exit.within_deadline -or ($Complete -and $exit.child_exit -ne 0) -or (-not $Complete -and $exit.child_exit -eq 0)) { throw 'Journal child result mismatch' }
            }
            if($i -eq 2 -and -not ($payload | ConvertFrom-Json).helper_checks_completed) { throw 'Missing final helper checks' }
        }
    } finally { $sha.Dispose() }
}
function Get-JournalHashes([string]$Session) {
    $hashes=@{}
    Get-ChildItem -LiteralPath $Session -Filter '*.journal' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    return $hashes
}
function Assert-PriorJournals([string]$Session,[hashtable]$Before) {
    foreach($name in $Before.Keys) {
        $path=Join-Path $Session $name
        if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $Before[$name]) { throw 'Prior helper journal changed or disappeared' }
    }
}
