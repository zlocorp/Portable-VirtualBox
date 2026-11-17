# TEST ONLY: build completed harmless bytes before compiling any owner consumer.
# This helper never loads or executes the child and never prepares negative copies.
function Get-FixedFixtureRuntimeConfig {
    return '<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup></configuration>'
}
function Compile-FixedFixtureSources([string[]]$Sources,[string]$Output,[string]$MainType) {
    if (Test-Path -LiteralPath $Output) { throw 'Fixed fixture output already exists' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        $target=if ($MainType) { '/target:exe' } else { '/target:library' }
        $arguments=@('/nologo','/codepage:65001',$target,'/platform:x64','/langversion:5','/warnaserror+',('/out:'+$Output))
        if ($MainType) { $arguments+=('/main:'+$MainType) }
        & $csc @arguments @Sources
        if ($LASTEXITCODE -ne 0) { throw 'Fixed fixture C#5/x64/net48 compilation failed' }
    } else {
        # Compilation only. Official Framework references are not a native runtime.
        if (-not $env:PVBOX_TEST_NET48_REFERENCES) { throw 'Fixed fixture compilation requires PVBOX_TEST_NET48_REFERENCES' }
        Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.dll')
        Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll')
        $parse=[Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::new([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp5)
        $trees=[Microsoft.CodeAnalysis.SyntaxTree[]]@($Sources | ForEach-Object { [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText($_),$parse) })
        $references=[Microsoft.CodeAnalysis.MetadataReference[]]@(@('mscorlib.dll','System.dll','System.Core.dll','System.Security.dll') | ForEach-Object { [Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $env:PVBOX_TEST_NET48_REFERENCES $_)) })
        $kind=if ($MainType) { [Microsoft.CodeAnalysis.OutputKind]::ConsoleApplication } else { [Microsoft.CodeAnalysis.OutputKind]::DynamicallyLinkedLibrary }
        $options=[Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new($kind)
        $options=$options.WithPlatform([Microsoft.CodeAnalysis.Platform]::X64).WithGeneralDiagnosticOption([Microsoft.CodeAnalysis.ReportDiagnostic]::Error)
        if ($MainType) { $options=$options.WithMainTypeName($MainType) }
        $compile=[Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create([IO.Path]::GetFileNameWithoutExtension($Output),$trees,$references,$options)
        $stream=[IO.File]::Open($Output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try { $result=$compile.Emit($stream) } finally { $stream.Dispose() }
        if (-not $result.Success) { $result.Diagnostics | ForEach-Object { Write-Output $_.ToString() };throw 'Fixed fixture C#5/x64/net48 compilation failed' }
    }
    [IO.File]::WriteAllText(($Output+'.config'),(Get-FixedFixtureRuntimeConfig),(New-Object Text.UTF8Encoding($false,$true)))
}
function Get-FixedFixtureExpectationText([long]$Length,[string]$Digest) {
    if ($Length -le 0 -or $Length -gt 16777216 -or $Digest -cnotmatch '\A[0-9a-f]{64}\z') { throw 'Pristine image expectation bound/syntax' }
    return "// Generated from completed pristine harmless build bytes. TEST ONLY.`nnamespace PortableVBox { internal static class FixedFixtureBuildExpectation { internal const string Name = `"NativeCaptureFixtureChild.exe`"; internal const long Length = "+$Length.ToString([Globalization.CultureInfo]::InvariantCulture)+"L; internal const string Sha256 = `""+$Digest+"`"; } }`n"
}
function New-FixedFixtureBuild([string]$Parent) {
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) { throw 'Fixed fixture parent must exist' }
    $root=Join-Path $Parent ('fixed-fixture-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root | Out-Null
    $pristine=Join-Path $root 'pristine'
    New-Item -ItemType Directory -Path $pristine | Out-Null
    $child=Join-Path $pristine 'NativeCaptureFixtureChild.exe'
    $childNames=@('NativeCaptureFixtureChild.cs','NativeLaunchEnvironmentObservation.cs','NativeSentinelObservation.cs','NativeSentinelObservationNative.cs')
    $childSources=@($childNames | ForEach-Object { Join-Path $PSScriptRoot $_ })
    Compile-FixedFixtureSources $childSources $child 'PortableVBox.NativeCaptureFixtureChild'
    # Compiler output is closed before these completed pristine bytes are read.
    $length=(Get-Item -LiteralPath $child).Length
    if ($length -le 0 -or $length -gt 16777216) { throw 'Pristine image size bound' }
    $digest=(Get-FileHash -LiteralPath $child -Algorithm SHA256).Hash.ToLowerInvariant()
    $source=Get-FixedFixtureExpectationText $length $digest
    $encoder=New-Object Text.UTF8Encoding($false,$true)
    if ($encoder.GetByteCount($source) -gt 2048) { throw 'Generated expectation source bound' }
    $expectation=Join-Path $root 'FixedFixtureBuildExpectation.g.cs'
    [IO.File]::WriteAllText($expectation,$source,$encoder)
    $build=[pscustomobject]@{ Root=$root;PristineChild=$child;ExpectationSource=$expectation;ExpectationSha256=(Get-FileHash -LiteralPath $expectation -Algorithm SHA256).Hash.ToLowerInvariant() }
    Assert-FixedFixtureBuild $build
    return $build
}
function Assert-FixedFixtureBuild($Build) {
    if ($null -eq $Build -or -not (Test-Path -LiteralPath $Build.Root -PathType Container) -or
        $Build.PristineChild -cne (Join-Path (Join-Path $Build.Root 'pristine') 'NativeCaptureFixtureChild.exe') -or
        $Build.ExpectationSource -cne (Join-Path $Build.Root 'FixedFixtureBuildExpectation.g.cs')) { throw 'Invalid fixed fixture build paths' }
    foreach ($path in @($Build.PristineChild,($Build.PristineChild+'.config'),$Build.ExpectationSource)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Missing pristine child/config or expectation' }
    }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes(($Build.PristineChild+'.config'))) -cne
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-FixedFixtureRuntimeConfig)))) { throw 'Stale pristine runtime config' }
    if ((Get-Item -LiteralPath $Build.ExpectationSource).Length -gt 2048 -or
        $Build.ExpectationSha256 -cnotmatch '\A[0-9a-f]{64}\z' -or
        (Get-FileHash -LiteralPath $Build.ExpectationSource -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Build.ExpectationSha256) { throw 'Missing or stale pristine expectation' }
    $length=(Get-Item -LiteralPath $Build.PristineChild).Length
    if ($length -le 0 -or $length -gt 16777216) { throw 'Pristine image size bound' }
    $digest=(Get-FileHash -LiteralPath $Build.PristineChild -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected=Get-FixedFixtureExpectationText $length $digest
    $actual=[IO.File]::ReadAllBytes($Build.ExpectationSource)
    if ([Convert]::ToBase64String($actual) -cne [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($expected))) { throw 'Pristine bytes do not match retained expectation' }
}
function Get-FixedFixtureConsumerSources($Build,[string[]]$Names) {
    Assert-FixedFixtureBuild $Build
    if ($Names.Count -eq 0 -or @($Names | Select-Object -Unique).Count -ne $Names.Count) { throw 'Invalid fixed consumer source list' }
    # The pure path grammar is an image-owner dependency, never a child source.
    # Preserve the caller's explicit list and add this one checked dependency.
    if ($Names -ccontains 'NativeFixedImageIdentity.cs' -and $Names -cnotcontains 'NativeFixedImagePath.cs') {
        $Names=@($Names)+@('NativeFixedImagePath.cs')
    }
    foreach ($name in $Names) {
        if ($name -cnotmatch '\ANative[A-Za-z0-9]+\.cs\z') { throw 'Fixed consumer requires repository source leaf names' }
        $path=Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('Missing fixed consumer source: '+$name) }
        $path
    }
    $Build.ExpectationSource
}
function Copy-FixedFixtureSibling($Build,[string]$Harness) {
    Assert-FixedFixtureBuild $Build
    $sibling=Join-Path (Split-Path $Harness -Parent) 'NativeCaptureFixtureChild.exe'
    Copy-Item -LiteralPath $Build.PristineChild -Destination $sibling
    Copy-Item -LiteralPath ($Build.PristineChild+'.config') -Destination ($sibling+'.config')
    Assert-FixedFixtureSibling $Build $Harness
}
function Assert-FixedFixtureSibling($Build,[string]$Harness) {
    Assert-FixedFixtureBuild $Build
    $sibling=Join-Path (Split-Path $Harness -Parent) 'NativeCaptureFixtureChild.exe'
    if (-not (Test-Path -LiteralPath $Harness -PathType Leaf) -or -not (Test-Path -LiteralPath $sibling -PathType Leaf) -or
        -not (Test-Path -LiteralPath ($sibling+'.config') -PathType Leaf)) { throw 'Missing fixed harness sibling/config' }
    if ((Get-Item -LiteralPath $sibling).Length -ne (Get-Item -LiteralPath $Build.PristineChild).Length -or
        (Get-FileHash -LiteralPath $sibling -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $Build.PristineChild -Algorithm SHA256).Hash -or
        (Get-FileHash -LiteralPath ($sibling+'.config') -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath ($Build.PristineChild+'.config') -Algorithm SHA256).Hash) { throw 'Stale fixed harness sibling/config' }
}
