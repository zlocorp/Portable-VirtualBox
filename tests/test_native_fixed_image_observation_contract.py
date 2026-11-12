"""Independent stage-pinned fixed-image diagnostics; never mutation authority."""
import ast
import base64
import io
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh')
CASES = ('matching-image', 'digest-mismatch', 'size-mismatch', 'missing-image')
MAX_IMAGE = 16 * 1024 * 1024

@unittest.skipUnless(SHELL, 'PowerShell compiler required')
class FixedFixtureBuildContracts(unittest.TestCase):
    def run_script(self, script):
        return subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-Command', script],
                              capture_output=True, text=True, timeout=120)

    def test_all_owner_consumers_build_child_before_compile(self):
        # Observe the real compiler boundary and still compile. Old runners run
        # successfully, but have no completed pristine build at this boundary.
        observer = r'''
$ErrorActionPreference='Stop'
$global:observations=New-Object Collections.Generic.List[bool]
function Observe-OwnerBuild {
 $v=Get-Variable build -ErrorAction SilentlyContinue
 $ready=$false
 if ($null -ne $v) {
  $b=$v.Value
  $ready=(Test-Path -LiteralPath $b.PristineChild -PathType Leaf) -and (Test-Path -LiteralPath $b.ExpectationSource -PathType Leaf)
  if ($ready) { Assert-FixedFixtureBuild $b }
 }
 $global:observations.Add($ready)
}
function Add-Type {
 param([string[]]$Path)
 if (@($Path | Where-Object { [IO.Path]::GetFileName($_) -eq 'NativeChildCaptureNative.cs' }).Count -gt 0) {
  if (@($Path | Where-Object { [IO.Path]::GetFileName($_) -ceq 'NativeFixedImagePath.cs' }).Count -ne 1) { throw 'ASSERT owner Add-Type missing/duplicate shared path source' }
  foreach ($dependency in @('NativeFixedFixtureCommand.cs','NativeFixedImageComposition.cs')) {
   if (@($Path | Where-Object { [IO.Path]::GetFileName($_) -ceq $dependency }).Count -ne 1) { throw ('ASSERT owner Add-Type missing/duplicate '+$dependency) }
  }
  Observe-OwnerBuild
 }
 Microsoft.PowerShell.Utility\Add-Type -Path $Path
}
$null=Set-PSBreakpoint -Command Compile-FixedFixtureSources -Action {
 # PowerShell also notifies for nested compiler scriptblocks. Count only the
 # function entry, while still allowing the real compilation to complete.
 if ((Get-PSCallStack)[1].FunctionName -eq 'Compile-FixedFixtureSources' -and
     @($Sources | Where-Object { [IO.Path]::GetFileName($_) -eq 'NativeFixedImageIdentity.cs' }).Count -gt 0) {
  if (@($Sources | Where-Object { [IO.Path]::GetFileName($_) -ceq 'NativeFixedImagePath.cs' }).Count -ne 1) { throw 'ASSERT owner compiler missing/duplicate shared path source' }
  if (@($Sources | Where-Object { [IO.Path]::GetFileName($_) -ceq 'NativeFixedFixtureCommand.cs' }).Count -ne 1) { throw 'ASSERT image compiler missing/duplicate formatter' }
  if (@($Sources | Where-Object { [IO.Path]::GetFileName($_) -ceq 'NativeChildCaptureNative.cs' }).Count -gt 0 -and
      @($Sources | Where-Object { [IO.Path]::GetFileName($_) -ceq 'NativeFixedImageComposition.cs' }).Count -ne 1) { throw 'ASSERT actual owner compiler missing/duplicate composition' }
  Observe-OwnerBuild
 }
}
'''
        entries=[]
        for name in ('child_capture','launch_environment','fixed_image_observation','fixed_image_composition'):
            path=str(ROOT/'tests/windows'/('check_native_'+name+'.ps1')).replace("'","''")
            entries.append((name,"& '"+path+"' -ManagedOnly",5 if name=='fixed_image_observation' else 4 if name=='fixed_image_composition' else 1))
        for module,method in (('test_native_child_capture_contract.py','run_native_sentinel_contract'),
                              ('test_native_child_capture_contract.py','test_native_report_serializer_matches_schema_without_native_calls'),
                              ('test_native_launch_environment_contract.py','test_legacy_constructor_rejects_appended_mode_before_native_entry'),
                              ('test_native_launch_environment_contract.py','test_actual_native_serializer_emits_valid_failure_diagnostics')):
            tree=ast.parse((ROOT/'tests'/module).read_text())
            function=next(node for node in ast.walk(tree) if isinstance(node,ast.FunctionDef) and node.name==method)
            script=next(node.value for node in ast.walk(function) if isinstance(node,ast.Constant) and isinstance(node.value,str) and "$ErrorActionPreference='Stop'" in node.value)
            script=script.replace('__ROOT__',str(ROOT/'tests/windows').replace("'","''")).replace('__METHOD__','RunQueryAdapter')
            entries.append((method,script,1))
        for name,script,count in entries:
            result = self.run_script(observer+script+"\nWrite-Output ('BUILD_BOUNDARY '+[string]::Join(',',@($global:observations)))\n")
            with self.subTest(consumer=name):
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                boundaries=[line for line in result.stdout.splitlines() if line.startswith('BUILD_BOUNDARY ')]
                self.assertEqual(boundaries,['BUILD_BOUNDARY '+','.join(['True']*count)])

    def test_pristine_expectation_precedes_all_negative_setup(self):
        text=(ROOT/'tests/windows/check_native_fixed_image_observation.ps1').read_text()
        self.assertLess(text.index('New-FixedFixtureBuild'), text.index('foreach ($name in $names)'))
        self.assertLess(text.index('foreach ($name in $names)'), text.index('if ($ManagedOnly) { return }'))
        self.assertLess(text.index('if ($ManagedOnly) { return }'), text.index('$negative='))
        self.assertIn('Assert-FixedFixtureBuild $build', text[text.index('$append='):])
        injected=text.index('::RunInjectedOwners($pristineBytes)')
        self.assertLess(text.index('Assert-FixedFixtureBuild $build'), injected)
        self.assertLess(text.index('$pristineBytes=[IO.File]::ReadAllBytes($build.PristineChild)'), injected)
        self.assertLess(injected, text.index('if ($ManagedOnly) { return }'))
        self.assertEqual(text.count('::RunInjectedOwners('), 1)

    def test_helper_dependency_triggers_native_workflow(self):
        text=(ROOT/'.github/workflows/native-tests.yml').read_text()
        for name in ('NativeFixedFixtureBuild.ps1','NativeFixedImagePath.cs','check_native_fixed_image_paths.ps1'):
            self.assertIn('      - tests/windows/'+name+'\n', text)
        required=('      - name: Verify exact Windows Framework path comparison bridge\n'
                  '        shell: powershell\n'
                  '        run: python -X utf8 tests/test_native_fixed_image_observation_contract.py '
                  'FixedImageWindowsPathBridgeContracts.test_nonascii_bridge_uses_windows_framework -v\n')
        self.assertEqual(text.count(required),1)
        self.assertLess(text.index(required),text.index('      - name: Observe fixed harmless image bytes'))

    def test_missing_stale_expectation_and_pristine_bytes_fail_closed(self):
        script=r'''
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. '__HELPER__'
$global:realCompile=${function:Compile-FixedFixtureSources}
function Compile-FixedFixtureSources([string[]]$Sources,[string]$Output,[string]$MainType) {
 Write-Output ('CHILD_SOURCES '+(ConvertTo-Json -Compress -InputObject @($Sources | ForEach-Object { [IO.Path]::GetFileName($_) }))) | Write-Host
 & $global:realCompile $Sources $Output $MainType
}
$parent=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-build-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $parent | Out-Null
$build=New-FixedFixtureBuild $parent
$another=New-FixedFixtureBuild $parent
if ($build.Root -eq $another.Root) { throw 'ASSERT reused build root' }
$source=[IO.File]::ReadAllBytes($build.ExpectationSource)
$child=[IO.File]::ReadAllBytes($build.PristineChild)
function Require-Rejection([string]$Label,[scriptblock]$Action) {
 $rejected=$false
 try { & $Action | Out-Null } catch { $rejected=$true }
 if (-not $rejected) { throw ('ASSERT accepted '+$Label) }
 Write-Output ('REJECTED '+$Label)
}
Remove-Item -LiteralPath $build.ExpectationSource
Require-Rejection 'missing expectation' { Get-FixedFixtureConsumerSources $build @('NativeFixedImageIdentity.cs') }
[IO.File]::WriteAllBytes($build.ExpectationSource,($source+[byte]32))
Require-Rejection 'stale expectation' { Get-FixedFixtureConsumerSources $build @('NativeFixedImageIdentity.cs') }
[IO.File]::WriteAllBytes($build.ExpectationSource,$source)
$changed=[byte[]]$child.Clone();$changed[0]=$changed[0] -bxor 1
[IO.File]::WriteAllBytes($build.PristineChild,$changed)
Require-Rejection 'same-length pristine mutation' { Get-FixedFixtureConsumerSources $build @('NativeFixedImageIdentity.cs') }
$global:hashedInvalidPristine=$false
function Get-FileHash {
 param([string]$LiteralPath,[string]$Algorithm)
 if ($LiteralPath -ceq $build.PristineChild -and ((Get-Item -LiteralPath $LiteralPath).Length -eq 0 -or (Get-Item -LiteralPath $LiteralPath).Length -gt 16777216)) { $global:hashedInvalidPristine=$true }
 Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
}
[IO.File]::WriteAllBytes($build.PristineChild,([byte[]]@()))
Require-Rejection 'empty pristine' { Assert-FixedFixtureBuild $build }
$stream=[IO.File]::Open($build.PristineChild,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $stream.SetLength(16777217) } finally { $stream.Dispose() }
Require-Rejection 'oversize pristine' { Assert-FixedFixtureBuild $build }
if ($global:hashedInvalidPristine) { throw 'ASSERT hashed pristine bytes before enforcing size bound' }
[IO.File]::WriteAllBytes($build.PristineChild,$child)
$config=[IO.File]::ReadAllBytes(($build.PristineChild+'.config'))
[IO.File]::WriteAllText(($build.PristineChild+'.config'),'stale')
Require-Rejection 'stale pristine config' { Assert-FixedFixtureBuild $build }
[IO.File]::WriteAllBytes(($build.PristineChild+'.config'),$config)
foreach ($names in @(@('NativeDoesNotExist.cs'),@('../NativeFixedImageIdentity.cs'),@('NativeFixedImageIdentity.cs','NativeFixedImageIdentity.cs'))) {
 Require-Rejection ('source '+[string]::Join(',',$names)) { Get-FixedFixtureConsumerSources $build $names }
}
$paths=@(Get-FixedFixtureConsumerSources $build @('NativeFixedImageIdentity.cs'))
if ($paths.Count -ne 3 -or [IO.Path]::GetFileName($paths[1]) -cne 'NativeFixedImagePath.cs' -or $paths[2] -cne $build.ExpectationSource) { throw 'ASSERT unchecked source expansion' }
$explicit=@(Get-FixedFixtureConsumerSources $build @('NativeFixedImageIdentity.cs','NativeFixedImagePath.cs'))
if ($explicit.Count -ne 3 -or @($explicit | Where-Object { [IO.Path]::GetFileName($_) -ceq 'NativeFixedImagePath.cs' }).Count -ne 1) { throw 'ASSERT duplicated explicit path dependency' }
$independent=@(Get-FixedFixtureConsumerSources $build @('NativeSentinelObservation.cs'))
if ($independent.Count -ne 2 -or @($independent | Where-Object { [IO.Path]::GetFileName($_) -ceq 'NativeFixedImagePath.cs' }).Count -ne 0) { throw 'ASSERT independent source gained path dependency' }
Assert-FixedFixtureBuild $build
Write-Output ('BUILD_RECORD '+($build | ConvertTo-Json -Compress))
'''.replace('__HELPER__',str(ROOT/'tests/windows/NativeFixedFixtureBuild.ps1').replace("'","''"))
        result=self.run_script(script)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(result.stdout.count('REJECTED '),9,result.stdout)
        compiled=[json.loads(line[14:]) for line in result.stdout.splitlines() if line.startswith('CHILD_SOURCES ')]
        self.assertEqual(compiled,[['NativeCaptureFixtureChild.cs','NativeLaunchEnvironmentObservation.cs',
                                   'NativeSentinelObservation.cs','NativeSentinelObservationNative.cs']]*2)
        build=json.loads(next(line.removeprefix('BUILD_RECORD ') for line in result.stdout.splitlines() if line.startswith('BUILD_RECORD ')))
        child=Path(build['PristineChild']).read_bytes()
        source=Path(build['ExpectationSource']).read_bytes()
        self.assertTrue(child.startswith(b'MZ'))
        self.assertGreater(len(child),0)
        self.assertLessEqual(len(child),MAX_IMAGE)
        self.assertIn(('Length = '+str(len(child))+'L;').encode(),source)
        self.assertIn(hashlib.sha256(child).hexdigest().encode(),source)
        self.assertEqual(hashlib.sha256(source).hexdigest(),build['ExpectationSha256'])
        self.assertLessEqual(len(source),2048)

    def test_legacy_harnesses_have_verified_pristine_siblings(self):
        # Compile each runner's real fixed source array, copy siblings and check
        # refusal after corruption. No native executable is invoked here.
        script=r'''
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root='__ROOT__'
. (Join-Path $root 'NativeFixedFixtureBuild.ps1')
$parent=Join-Path ([IO.Path]::GetTempPath()) ('pvbox-build-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $parent | Out-Null
$build=New-FixedFixtureBuild $parent
foreach ($stem in @('child_capture','launch_environment')) {
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('check_native_'+$stem+'.ps1')),[ref]$tokens,[ref]$errors)
 $assignment=$ast.Find({param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -in @('$sources','$sourceNames') -and $a.Right.Extent.Text.StartsWith('@(') -and $a.Right.Extent.Text.Contains("'NativePipeTransport.cs'")},$true)
 $names=[string[]]@($assignment.Right.FindAll({param($a) $a -is [Management.Automation.Language.StringConstantExpressionAst]},$true) | ForEach-Object { $_.Value })
 $sources=@(Get-FixedFixtureConsumerSources $build $names)
 $directory=Join-Path $build.Root $stem
 New-Item -ItemType Directory -Path $directory | Out-Null
 $exe=Join-Path $directory 'ManagedCompileOnly.exe'
 $main=if ($stem -eq 'child_capture') { 'PortableVBox.NativeChildCaptureNativeTests' } else { 'PortableVBox.NativeLaunchEnvironmentNativeTests' }
 Compile-FixedFixtureSources $sources $exe $main
 Copy-FixedFixtureSibling $build $exe
 Assert-FixedFixtureSibling $build $exe
 $sibling=Join-Path $directory 'NativeCaptureFixtureChild.exe'
 Write-Output ('SIBLING '+(@{runner=$stem;child=$sibling;harness=$exe;sources=$names;resolved_sources=$sources;build=$build} | ConvertTo-Json -Compress -Depth 3))
 $bytes=[IO.File]::ReadAllBytes($sibling);$bytes[0]=$bytes[0] -bxor 1
 [IO.File]::WriteAllBytes($sibling,$bytes)
 $rejected=$false
 try { Assert-FixedFixtureSibling $build $exe } catch { $rejected=$true }
 if (-not $rejected) { throw 'ASSERT accepted changed sibling bytes' }
 Copy-FixedFixtureSibling $build $exe
 [IO.File]::WriteAllText(($sibling+'.config'),'stale')
 $rejected=$false
 try { Assert-FixedFixtureSibling $build $exe } catch { $rejected=$true }
 if (-not $rejected) { throw 'ASSERT accepted changed sibling config' }
 Copy-FixedFixtureSibling $build $exe
}
'''.replace('__ROOT__',str(ROOT/'tests/windows').replace("'","''"))
        result=self.run_script(script)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        records=[json.loads(line[8:]) for line in result.stdout.splitlines() if line.startswith('SIBLING ')]
        self.assertEqual(len(records),2,result.stdout)
        for record in records:
            with self.subTest(runner=record['runner']):
                common={'NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs',
                        'NativeChildCapture.cs','NativeSentinelObservation.cs','NativeSentinelObservationNative.cs',
                        'NativeChildCaptureNative.cs','NativeChildCaptureNativeTests.cs','NativeLaunchEnvironment.cs',
                        'NativeLaunchEnvironmentNative.cs','NativeFixedImageIdentity.cs','NativeFixedFixtureCommand.cs','NativeFixedImageComposition.cs'}
                extra=({'NativeChildCaptureTests.cs','NativeSentinelObservationNativeTests.cs'} if record['runner']=='child_capture'
                       else {'NativeLaunchEnvironmentObservation.cs','NativeLaunchEnvironmentObservationTests.cs',
                             'NativeLaunchEnvironmentNativeTests.cs','NativeLaunchEnvironmentTests.cs','NativeLaunchEnvironmentPolicyTests.cs'})
                self.assertEqual(set(record['sources']),common|extra)
                self.assertEqual(len(record['sources']),len(common|extra))
                resolved=[Path(path).name for path in record['resolved_sources']]
                self.assertEqual(set(resolved),common|extra|{'NativeFixedImagePath.cs','FixedFixtureBuildExpectation.g.cs'})
                self.assertEqual(len(resolved),len(common|extra)+2)
                sibling=Path(record['child']);pristine=Path(record['build']['PristineChild'])
                self.assertEqual(sibling.parent,Path(record['harness']).parent)
                self.assertNotEqual(sibling,pristine)
                self.assertEqual(sibling.read_bytes(),pristine.read_bytes())
                self.assertEqual(Path(str(sibling)+'.config').read_bytes(),Path(str(pristine)+'.config').read_bytes())
                text=(ROOT/'tests/windows'/('check_native_'+record['runner']+'.ps1')).read_text()
                self.assertLess(text.index('Copy-FixedFixtureSibling $build $exe'),text.index('& $exe |'))
                self.assertLess(text.index('Assert-FixedFixtureSibling $build $exe'),text.index('& $exe |'))

    def test_four_direct_owner_compiles_keep_checked_source_sets(self):
        common={'NativePipeTransport.cs','NativePipeTransportTests.cs','NativePipeTransportNative.cs',
                'NativeChildCapture.cs','NativeSentinelObservation.cs','NativeSentinelObservationNative.cs',
                'NativeChildCaptureNative.cs','NativeChildCaptureNativeTests.cs','NativeLaunchEnvironment.cs',
                'NativeLaunchEnvironmentNative.cs','NativeFixedImageIdentity.cs','NativeFixedFixtureCommand.cs','NativeFixedImageComposition.cs'}
        entries=(('test_native_child_capture_contract.py','run_native_sentinel_contract',
                  common|{'NativeChildCaptureTests.cs','NativeSentinelObservationNativeTests.cs'}),
                 ('test_native_child_capture_contract.py','test_native_report_serializer_matches_schema_without_native_calls',common),
                 ('test_native_launch_environment_contract.py','test_legacy_constructor_rejects_appended_mode_before_native_entry',common),
                 ('test_native_launch_environment_contract.py','test_actual_native_serializer_emits_valid_failure_diagnostics',
                  common|{'NativeLaunchEnvironmentObservation.cs','NativeLaunchEnvironmentObservationTests.cs',
                          'NativeLaunchEnvironmentNativeTests.cs','NativeLaunchEnvironmentTests.cs','NativeLaunchEnvironmentPolicyTests.cs'}))
        for module,method,expected in entries:
            tree=ast.parse((ROOT/'tests'/module).read_text())
            function=next(node for node in ast.walk(tree) if isinstance(node,ast.FunctionDef) and node.name==method)
            script=next(node.value for node in ast.walk(function) if isinstance(node,ast.Constant) and isinstance(node.value,str) and "$ErrorActionPreference='Stop'" in node.value)
            with self.subTest(method=method):
                names=re.findall(r"'([A-Za-z]+\.cs)'",script)
                self.assertEqual(set(names),expected)
                self.assertEqual(len(names),len(expected))
                self.assertLess(script.index('New-FixedFixtureBuild'),script.index('Add-Type -Path'))
                self.assertIn('Add-Type -Path @(Get-FixedFixtureConsumerSources $build $names)',script)
                # Also target-compile the exact direct consumer list, separately
                # from the actual Add-Type managed-host behavior tested there.
                prefix=script[:script.index('Add-Type -Path')].replace('__ROOT__',str(ROOT/'tests/windows').replace("'","''"))
                result=self.run_script(prefix+"\n$sources=@(Get-FixedFixtureConsumerSources $build $names)\nCompile-FixedFixtureSources $sources (Join-Path $build.Root 'DirectOwner.dll') ''\nWrite-Output 'DIRECT_NET48_PASS'\n")
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn('DIRECT_NET48_PASS',result.stdout)

@unittest.skipUnless(SHELL, 'PowerShell compiler required')
class FixedImageCompositionContracts(unittest.TestCase):
    def test_real_composition_owner_contracts_run_with_pristine_bytes(self):
        result=subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
            str(ROOT/'tests/windows/check_native_fixed_image_observation.ps1'), '-ManagedOnly'],
            capture_output=True,text=True,timeout=180)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(result.stdout.count('PASS fixed image composition owners'),1,result.stdout)
        self.assertEqual(result.stdout.count('COMPOSITION_RUN_TRACE '),1,result.stdout)
        self.assertEqual(result.stdout.count('COMPOSITION_BOUNDARY_TRACE '),1,result.stdout)

    def test_composition_uses_one_formatter_and_the_existing_lifecycle(self):
        native=(ROOT/'tests/windows/NativeChildCaptureNative.cs').read_text()
        image=(ROOT/'tests/windows/NativeFixedImageIdentity.cs').read_text()
        composition=(ROOT/'tests/windows/NativeFixedImageComposition.cs').read_text()
        formatter=(ROOT/'tests/windows/NativeFixedFixtureCommand.cs').read_text()
        self.assertEqual(native.count('FixedFixtureCommand.Format('),1)
        self.assertEqual(image.count('FixedFixtureCommand.Format('),1)
        self.assertEqual(formatter.count('StringBuilder Format('),1)
        self.assertNotIn('new StringBuilder(',native)
        for method in ('void Run(', 'void Launch(', 'void Refresh(', 'void Release('):
            self.assertEqual(native.count(method),1)
            self.assertNotIn(method,composition)
        # File-only schemas and child sources stay independent of composition.
        self.assertNotIn('FixedImageComposition', (ROOT/'tests/windows/NativeFixedFixtureBuild.ps1').read_text())


@unittest.skipUnless(SHELL, 'PowerShell compiler required')
class FixedImageManagedContracts(unittest.TestCase):
    def test_recording_owner_has_no_residual_static_native_boundary(self):
        text=(ROOT/'tests/windows/NativeFixedImageIdentity.cs').read_text()
        owners=text[text.index(' internal sealed class FixedImageProbe {'):]
        methods=('CreateFileW','Attributes','GetFileSizeEx','Identity',
                 'GetFinalPathNameByHandleW','ReadFile','CloseHandle')
        for method in methods:
            self.assertNotIn('FixedImageNative.'+method+'(', owners)
            self.assertEqual(text.count('return FixedImageNative.'+method+'('), 1)
        self.assertNotIn('Marshal.GetLastWin32Error', owners)
        self.assertEqual(text.count('readonly IFixedImageNativeCalls calls;'), 2)
        self.assertEqual(text.count('internal FixedImageLaunchBinding BindBinaryLaunch(long candidate,string token)'),1)
        self.assertEqual(text.count('internal sealed class FixedImageLaunchBinding'),1)
        self.assertEqual(text.count('FixedFixtureCommand.Format(Application,"Binary",candidate,token)'),1)

    def test_runner_executes_injected_owner_contracts(self):
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
            str(ROOT/'tests/windows/check_native_fixed_image_observation.ps1'), '-ManagedOnly'],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(result.stdout.splitlines().count('PASS fixed image injected owners'), 1,
                         'Runner must execute real injected-owner assertions exactly once')

    def test_behavioral_contracts(self):
        result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
            str(ROOT/'tests/windows/check_native_fixed_image_observation.ps1'), '-ManagedOnly'],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS fixed image managed contracts', result.stdout)
        self.assertTrue((ROOT/'tests/windows/check_native_fixed_image_observation.ps1').read_text(encoding='utf-8').isascii(),
                        'Windows PowerShell 5.1 runner must remain encoding-safe ASCII source')
        retained=re.search(r'Generated fixed image build/evidence retained at (.+?)\. Process teardown',result.stdout)
        self.assertIsNotNone(retained)
        build=Path(retained.group(1));fixture=next(build.glob('fixed-fixture-*'))
        pristine=(fixture/'pristine/NativeCaptureFixtureChild.exe').read_bytes()
        generated=(fixture/'FixedFixtureBuildExpectation.g.cs').read_bytes()
        self.assertLessEqual(len(generated),2048)
        exact=('// Generated from completed pristine harmless build bytes. TEST ONLY.\n'
               'namespace PortableVBox { internal static class FixedFixtureBuildExpectation { '
               'internal const string Name = "NativeCaptureFixtureChild.exe"; internal const long Length = '
               +str(len(pristine))+'L; internal const string Sha256 = "'+hashlib.sha256(pristine).hexdigest()+'"; } }\n')
        self.assertEqual(generated,exact.encode('utf-8'))
        for name in CASES:
            directory=build/'fixed-Ж-漢'/name
            self.assertTrue((directory/'NativeFixedImageIdentityTests.exe').is_file())
            self.assertEqual((directory/'FixedFixtureCase.g.cs').read_text(),
                'namespace PortableVBox { internal static class FixedFixtureCase { internal const string Name = "'+name+'"; } }')
            self.assertFalse((directory/'NativeCaptureFixtureChild.exe').exists(),'Managed-only must never prepare or execute negative child copies')
        unicode_lines=[line.split(' ',1)[1] for line in result.stdout.splitlines()
                       if line.startswith('SERIALIZER_UNICODE ')]
        self.assertEqual(len(unicode_lines),1)
        wire=unicode_lines[0]
        self.assertTrue(wire.isascii(),'Every JSON UTF16 unit outside ASCII must be escaped')
        transported=wire.encode('cp437',errors='replace').decode('cp437')
        self.assertEqual(transported,wire,'Console transport must not substitute actual path units')
        unicode_record=json.loads(transported)
        self.assertEqual(unicode_record['held_path'],'C:\\Привет\\漢字-é-🙂\\NativeCaptureFixtureChild.exe')
        complete=samples();complete[0]=unicode_record
        self.assertTrue(validate_records(complete,True))
        probe_lines=[json.loads(line.split(' ',1)[1]) for line in result.stdout.splitlines()
                     if line.startswith('PROBE_DIAGNOSTIC ')]
        self.assertEqual(len(probe_lines),3)
        for record,open_state,close_state in zip(probe_lines,
                ('return-unknown','returned-success','returned-success'),
                ('not-opened','return-unknown','returned-failure')):
            self.assertEqual(record['write_probe']['open_state'],open_state)
            self.assertEqual(record['write_probe']['close_state'],close_state)
            self.assertIsNone(record['write_probe']['open_error'])
            self.assertEqual(record['close_state'],'not-entered','Unresolved probe must retain image owner')
            diagnostics=[record,summary(1,1,'unresolved-owner')]
            self.assertFalse(validate_records(diagnostics))
            with self.assertRaises(ValueError): validate_records(diagnostics,True)
            with self.assertRaises(ValueError):
                validate_records([record]+samples()[1:-1]+[summary(4,1,'case-failure')])
        serialized=[json.loads(line.split(' ',1)[1]) for line in result.stdout.splitlines()
                    if line.startswith('SERIALIZER_DIAGNOSTIC ')]
        self.assertEqual(len(serialized),3)
        for record in serialized:
            self.assertIsNone(record['read_error']);self.assertIsNone(record['actual_sha256'])
            self.assertEqual(record['read_state'],'known-incomplete')
            self.assertFalse(validate_records([record,summary(1,1,'case-failure')]))
            record['status']='PASS'
            with self.assertRaises(ValueError): validate_records([record,summary(1,0,'case-failure')])


@unittest.skipUnless(SHELL, 'PowerShell compiler required')
class FixedImageComposedContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = subprocess.run([SHELL, '-NoProfile', '-NonInteractive', '-File',
            str(ROOT/'tests/windows/check_native_fixed_image_observation.ps1'), '-ManagedOnly'],
            capture_output=True, text=True, timeout=120)
        cls.records = {}
        for line in cls.result.stdout.splitlines():
            if line.startswith('COMPOSED_DIAGNOSTIC '):
                label, wire = line.removeprefix('COMPOSED_DIAGNOSTIC ').split(' ', 1)
                cls.records[label] = strict_json(wire)

    def observed(self):
        self.assertEqual(self.result.returncode, 0, self.result.stdout+self.result.stderr)
        self.assertIn('ok', self.records, 'Real recording owner must feed the actual schema-2 serializer')
        return copy.deepcopy(self.records)

    def diagnostic(self, record):
        # Matrix diagnostics use the first case label so each is an attempted prefix.
        record = copy.deepcopy(record);record['case']='matching-image'
        retained=record['composition']['owner_release_state']=='retained'
        end=summary(1,1,'unresolved-owner' if retained else 'case-failure',stage='composed')
        return [record,end]

    def acceptance_fixture(self):
        # Explicit synthetic acceptance fixture, derived from real managed serializer
        # output. Native activity is NOT claimed: the rig has zero real pipe visits.
        rows=self.observed()
        records=[rows[name] for name in ('ok','digest','size','missing')]
        for record,name in zip(records,CASES):
            record['case']=name;record['status']='PASS'
        c=records[0]['composition']['capture'];c['rounds']=4
        # Two stdout data completions (4096+9), one stderr data completion
        # (257), then a separate synchronous FALSE/error109 EOF per channel.
        # That EOF increments terminal, but neither pending nor immediate.
        for channel,issued,immediate in zip(c['channels'],(3,2),(2,1)):
            channel.update(read_issued=issued,read_terminal=issued,read_pending=0,
                           read_immediate=immediate,read_visits=4,max_read_gap=1)
        return records+[summary(stage='composed')]

    def reject(self, records, **kwargs):
        with self.assertRaises(ValueError):
            validate_records(records,expected_stage='composed',**kwargs)

    def test_composed_native_runner_is_closed_and_preserves_full_binary(self):
        runner=ROOT/'tests/windows/check_native_fixed_image_composition.ps1'
        self.assertTrue(runner.is_file(),'Separate composed runner is required; file-only output is not composed proof')
        result=subprocess.run([SHELL,'-NoProfile','-NonInteractive','-File',str(runner),'-ManagedOnly'],
                              capture_output=True,text=True,timeout=120)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASS fixed image composition owners',result.stdout)
        self.assertTrue(runner.read_text().isascii())
        retained=re.search(r'Generated fixed image build/evidence retained at (.+?)\. Process teardown',result.stdout)
        self.assertIsNotNone(retained)
        build=Path(retained.group(1));fixture=next(build.glob('fixed-fixture-*'))
        pristine=fixture/'pristine/NativeCaptureFixtureChild.exe'
        self.assertTrue(pristine.read_bytes().startswith(b'MZ'))
        expectation=(fixture/'FixedFixtureBuildExpectation.g.cs').read_bytes()
        self.assertIn(hashlib.sha256(pristine.read_bytes()).hexdigest().encode(),expectation)
        for name in CASES:
            directory=build/'fixed-Ж-漢'/name
            self.assertTrue((directory/'NativeFixedImageCompositionTests.exe').is_file())
            self.assertEqual((directory/'FixedFixtureCase.g.cs').read_text(),
                'namespace PortableVBox { internal static class FixedFixtureCase { internal const string Name = "'+name+'"; } }')
            self.assertFalse((directory/'NativeCaptureFixtureChild.exe').exists())
        # The full inherited native assertion body is frozen, visibility only.
        native=(ROOT/'tests/windows/NativeChildCaptureNativeTests.cs').read_text()
        assertion=native[native.index('  internal static void AssertCase('):native.index('  public static int Main(')]
        self.assertEqual(hashlib.sha256(assertion.encode()).hexdigest(),'60af033800586b9f9875c5e86155d18115f0ce0b2e8c8087127584666d6404d6')
        harness=(ROOT/'tests/windows/NativeFixedImageCompositionNativeTests.cs').read_text()
        self.assertIn('public static int Main()',harness)
        self.assertIn('NativeChildCaptureNativeTests.AssertCase(root)',harness)
        self.assertNotIn('TryRelease(',harness,'Transferred image release belongs solely to real owner gates')
        for stem,stage in (('observation','file-only'),('composition','composed')):
            text=(ROOT/'tests/windows'/('check_native_fixed_image_'+stem+'.ps1')).read_text()
            self.assertEqual(text.count('--expected-stage '+stage),2)
        workflow=(ROOT/'.github/workflows/native-tests.yml').read_text()
        for name in ('NativeFixedFixtureCommand.cs','NativeFixedImageComposition.cs','NativeFixedImageCompositionTests.cs',
                     'NativeFixedImageCompositionNativeTests.cs','check_native_fixed_image_composition.ps1'):
            self.assertIn('      - tests/windows/'+name+'\n',workflow)
        text=runner.read_text()
        self.assertLess(text.index('if ($ManagedOnly) { return }'),text.index('Copy-FixedFixtureSibling $build $harnesses[0]'))
        self.assertLess(text.index('[IO.File]::WriteAllBytes($negative,$bytes)'),text.index('Copy-FixedFixtureSibling $build $harnesses[2]'))
        self.assertLess(text.index('$append.Dispose()'),text.index('Missing-image case must remain absent'))
        self.assertIn('timeout-minutes: 6',workflow)
        self.assertIn('name: native-fixed-image-composition-text-only',workflow)
        self.assertIn('pvbox-native-fixed-composition-evidence/native-fixed-image-observation.jsonl',workflow)

    def test_composed_stage_rejects_file_only_and_mixed_schema(self):
        records=self.acceptance_fixture()
        self.assertTrue(validate_records(records,True,expected_stage='composed'))
        self.assertTrue(validate_records(samples(),True,expected_stage='file-only'))
        self.reject(samples())
        with self.assertRaises(ValueError): validate_records(records)
        for index in range(5):
            bad=copy.deepcopy(records);bad[index]['schema']=1;self.reject(bad)
            bad=copy.deepcopy(records);bad[index]['stage']='file-only';self.reject(bad)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'evidence'
            path.write_text(''.join(json.dumps(r)+'\n' for r in records),encoding='utf-8')
            self.assertTrue(validate_evidence(path,True,expected_stage='composed'))
            with self.assertRaises(ValueError): validate_evidence(path,True)

    def test_composed_failure_matrix_nullability_and_owner_consistency(self):
        rows=self.observed()
        expected={
            'ok':('ReturnedTrue','valid','released'),
            'digest':('NotEntered','not-observed','released'),
            'size':('NotEntered','not-observed','released'),
            'missing':('NotEntered','not-observed','released'),
            'probe-error':('NotEntered','not-observed','released'),
            'probe-success':('NotEntered','not-observed','released'),
            'probe-write-unavailable':('NotEntered','not-observed','retained'),
            'probe-delete-unavailable':('NotEntered','not-observed','retained'),
            'probe-close-false':('NotEntered','not-observed','retained'),
            'probe-close-unavailable':('NotEntered','not-observed','retained'),
            'image-open-unavailable':('NotEntered','not-observed','retained'),
            'image-read-unavailable':('NotEntered','not-observed','retained'),
            'image-read-false':('NotEntered','not-observed','released'),
            'create-false':('ReturnedFalse','not-observed','released'),
            'create-unavailable':('EnteredReturnUnknown','not-observed','retained'),
            'process-zero':('ReturnedTrue','invalid','retained'),
            'thread-zero':('ReturnedTrue','invalid','retained'),
            'process-invalid':('ReturnedTrue','invalid','retained'),
            'thread-invalid':('ReturnedTrue','invalid','retained'),
        }
        for fault in ('query-false','query-unavailable','query-truncated','query-count','malformed','unsupported','nul','empty','different'):
            expected[fault]=('ReturnedTrue','valid','released')
        for fault in ('wait-unavailable','wait-timeout','wait-failed','exit-code-unavailable','exit-code-false',
                      'image-close-false','image-close-unavailable','thread-close-false','thread-close-unavailable',
                      'process-close-false','process-close-unavailable','stdout-eof-missing','stderr-eof-missing'):
            expected[fault]=('ReturnedTrue','valid','retained')
        self.assertEqual(set(rows),set(expected))
        for fault,want in expected.items():
            with self.subTest(fault=fault):
                record=rows[fault];c=record['composition']
                self.assertEqual((c['create_state'],c['original_handles_state'],c['owner_release_state']),want)
                self.assertEqual(record['status'],'FAIL','Managed records must never claim native acceptance')
                self.assertEqual(record['create_calls'],0 if want[0]=='NotEntered' else 1)
                self.assertEqual(c['image_release_state'],want[2])
                self.assertEqual(c['capture'] is not None,want[1]=='valid')
                self.assertEqual(record['process_observation'] is not None,want[1]=='valid')
                self.assertFalse(validate_records(self.diagnostic(record),expected_stage='composed'))
                self.reject(self.diagnostic(record),require_pass=True)
                if fault not in ('ok','digest','size','missing'):
                    self.assertEqual(c['overall'],'UNKNOWN')
        self.assertEqual(rows['ok']['composition']['original_handles_state'],'valid','Released handles must not erase the recorded check')
        self.assertEqual(rows['create-false']['composition']['create_error'],2)
        self.assertIsNone(rows['create-unavailable']['composition']['create_error'])
        paths={'query-false':'unavailable','query-unavailable':'unavailable','query-truncated':'truncated',
               'query-count':'truncated','malformed':'malformed','unsupported':'unsupported','nul':'malformed','empty':'malformed','different':'valid','ok':'valid'}
        for fault,state in paths.items():
            q=rows[fault]['process_observation']
            self.assertEqual(q['path_state'],state)
            if state in ('unavailable','truncated','malformed'): self.assertIsNone(q['image_path'])
            if state=='unsupported': self.assertEqual(q['image_path'],r'\\server\share\image')
            if fault.startswith('query-') and fault in ('query-false','query-unavailable'): self.assertIsNone(q['query_return_chars'])
        self.assertIsNone(rows['wait-unavailable']['process_observation']['exit_wait_result'])
        self.assertEqual(rows['wait-timeout']['process_observation']['exit_wait_result'],258)
        self.assertEqual(rows['wait-failed']['process_observation']['exit_wait_error'],4294967295 & 6)
        self.assertIsNone(rows['exit-code-false']['process_observation']['exit_code'])
        # Every new field is required, typed, and has no optional escape hatch.
        record=rows['ok']
        for parent in (('composition',),('process_observation',),('composition','capture'),('composition','capture','channels',0)):
            for key in self.at(record,parent):
                for replacement in ('delete',None,{},[]):
                    bad=self.diagnostic(record);target=self.at(bad[0],parent)
                    if replacement=='delete': del target[key]
                    else: target[key]=replacement
                    if replacement is None and self.at(record,parent)[key] is None: continue
                    with self.subTest(path=parent,key=key,replacement=replacement): self.reject(bad)
        for fault,path,value in [
            ('ok',('composition','claim_state'),'unclaimed'),
            ('ok',('composition','create_error'),0),
            ('ok',('composition','capture'),None),
            ('ok',('create_calls',),2),
            ('create-false',('composition','create_error'),None),
            ('create-unavailable',('composition','image_release_state'),'released'),
            ('image-close-false',('composition','owner_release_state'),'released'),
            ('wait-unavailable',('process_observation','exit_wait_result'),0),
            ('query-false',('process_observation','query_return_chars'),32768),
            ('query-false',('process_observation','query_error'),None),
            ('query-truncated',('process_observation','path_state'),'valid'),
            ('ok',('process_observation','comparison'),'mismatch'),
            ('ok',('process_observation','exit_wait_error'),0),
            ('ok',('process_observation','exit_code_error'),0),
        ]:
            bad=self.diagnostic(rows[fault]);self.at(bad[0],path[:-1])[path[-1]]=value
            with self.subTest(fault=fault,path=path): self.reject(bad)
        bad=self.diagnostic(rows['missing']);bad[0]['process_observation']=rows['ok']['process_observation'];self.reject(bad)

    @staticmethod
    def at(value,path):
        for key in path: value=value[key]
        return value

    def test_composed_retained_owner_stops_prefix(self):
        rows=self.observed()
        for fault,record in rows.items():
            if record['composition']['owner_release_state']!='retained': continue
            prefix=self.diagnostic(record)
            self.assertFalse(validate_records(prefix,expected_stage='composed'))
            bad=prefix[:-1]+self.acceptance_fixture()[1:-1]+[summary(4,1,'unresolved-owner',stage='composed')]
            with self.subTest(fault=fault): self.reject(bad)
            bad=copy.deepcopy(prefix);bad[-1]['stop_reason']='case-failure';self.reject(bad)
        retained=copy.deepcopy(rows['ok'])
        retained['composition'].update(owner_release_state='retained',overall='UNKNOWN')
        self.assertFalse(unresolved_file_owner(retained))
        self.assertFalse(validate_records(self.diagnostic(retained),expected_stage='composed'))
        bad=self.diagnostic(retained);bad[-1]['stop_reason']='case-failure';self.reject(bad)
        # Query diagnosis alone does not require retained ownership or stop later cases.
        records=self.acceptance_fixture();records[0]=rows['query-false']
        records[-1]=summary(4,1,'case-failure',stage='composed')
        self.assertFalse(validate_records(records,expected_stage='composed'))

    def test_composed_image_release_requires_exit_eof_and_slots_with_retained_owner(self):
        rows=self.observed()
        for fault in ('wait-unavailable','wait-timeout','wait-failed','exit-code-false',
                      'exit-code-unavailable','stdout-eof-missing','stderr-eof-missing'):
            with self.subTest(fault=fault):
                records=self.diagnostic(rows[fault])
                self.assertFalse(validate_records(records,expected_stage='composed'))
                self.assertEqual(records[0]['composition']['owner_release_state'],'retained')
                records[0]['close_state']='returned-success'
                records[0]['composition']['image_release_state']='released'
                self.reject(records)
        # Image release and whole-owner release remain distinct. Complete exit,
        # EOF and slot observations permit this isolated retained-owner diagnostic.
        retained=copy.deepcopy(rows['ok'])
        retained['composition'].update(owner_release_state='retained',overall='UNKNOWN')
        self.assertFalse(validate_records(self.diagnostic(retained),expected_stage='composed'))
        variants=[('io-terminal',('io_terminal',))]
        variants += [(key+'-'+str(index),('channels',index,key))
                     for index in (0,1) for key in ('read_released','connect_released')]
        for label,path in variants:
            with self.subTest(slot=label):
                record=copy.deepcopy(retained)
                record['close_state']='not-entered'
                record['composition']['image_release_state']='retained'
                self.at(record['composition']['capture'],path[:-1])[path[-1]]=False
                records=self.diagnostic(record)
                self.assertFalse(validate_records(records,expected_stage='composed'))
                records[0]['close_state']='returned-success'
                records[0]['composition']['image_release_state']='released'
                self.reject(records)

    def test_composed_image_close_entry_requires_known_acquisition_and_exit(self):
        rows=self.observed()
        faults=('create-unavailable','process-zero','thread-zero','process-invalid','thread-invalid',
                'wait-unavailable','wait-timeout','wait-failed','exit-code-unavailable','exit-code-false',
                'stdout-eof-missing','stderr-eof-missing')
        for fault in faults:
            self.assertFalse(validate_records(self.diagnostic(rows[fault]),expected_stage='composed'))
            for close in ('return-unknown','returned-failure','returned-success'):
                with self.subTest(fault=fault,close=close):
                    bad=self.diagnostic(rows[fault]);bad[0]['close_state']=close
                    # Keep the exact image ledger and aggregate consistent, so
                    # failed/unknown close entries cannot hide behind retention.
                    bad[0]['composition']['image_release_state']='released' if close=='returned-success' else 'retained'
                    self.reject(bad)

    def test_composed_image_close_entry_requires_resolved_probes(self):
        rows=self.observed()
        for fault in ('probe-write-unavailable','probe-delete-unavailable',
                      'probe-close-false','probe-close-unavailable'):
            for close in ('return-unknown','returned-failure','returned-success'):
                with self.subTest(fault=fault,close=close):
                    bad=self.diagnostic(rows[fault]);bad[0]['close_state']=close
                    # Even successful image close leaves this aggregate retained
                    # because a probe is unresolved. Entry itself is forbidden.
                    self.assertEqual(bad[0]['composition']['image_release_state'],'retained')
                    self.reject(bad)
        for key in ('write_probe','delete_probe'):
            for probe_open,probe_close in (('not-entered','not-opened'),('returned-success','not-entered'),
                                           ('returned-success','return-unknown'),('returned-success','returned-failure')):
                for image_close in ('return-unknown','returned-failure','returned-success'):
                    with self.subTest(probe=key,probe_open=probe_open,probe_close=probe_close,image_close=image_close):
                        record=copy.deepcopy(rows['probe-success'])
                        record[key].update(open_state=probe_open,open_error=None,close_state=probe_close)
                        record['close_state']='not-entered'
                        record['composition'].update(image_release_state='retained',owner_release_state='retained',overall='UNKNOWN')
                        self.assertFalse(validate_records(self.diagnostic(record),expected_stage='composed'))
                        record['close_state']=image_close
                        self.reject(self.diagnostic(record))

    def test_composed_image_close_entry_requires_each_terminal_released_slot(self):
        rows=self.observed()
        paths=[('io_terminal',)]+[('channels',index,key) for index in (0,1)
                                for key in ('read_released','connect_released')]
        for path in paths:
            record=copy.deepcopy(rows['ok']);record['close_state']='not-entered'
            record['composition'].update(image_release_state='retained',owner_release_state='retained',overall='UNKNOWN')
            self.at(record['composition']['capture'],path[:-1])[path[-1]]=False
            self.assertFalse(validate_records(self.diagnostic(record),expected_stage='composed'))
            for close in ('return-unknown','returned-failure','returned-success'):
                with self.subTest(slot=path,close=close):
                    bad=self.diagnostic(record);bad[0]['close_state']=close
                    bad[0]['composition']['image_release_state']='released' if close=='returned-success' else 'retained'
                    self.reject(bad)

    def test_composed_image_close_failure_remains_valid_after_resolved_gates(self):
        rows=self.observed()
        # Known precreate refusal, known FALSE create, and completed successful
        # creation all permit close entry. Query failure alone does not block it.
        for source in ('digest','size','probe-error','probe-success','image-read-false',
                       'create-false','ok','query-false','image-close-false','image-close-unavailable'):
            for close in ('return-unknown','returned-failure'):
                with self.subTest(source=source,close=close):
                    record=copy.deepcopy(rows[source]);record['close_state']=close
                    record['composition'].update(image_release_state='retained',owner_release_state='retained',overall='UNKNOWN')
                    self.assertFalse(validate_records(self.diagnostic(record),expected_stage='composed'))

    def test_composed_binary_accepts_conservative_native_read_accounting(self):
        # Synthetic validator inputs only, never relabel the recording rig as
        # native evidence. Each tuple is issued, pending, immediate per channel.
        profiles=[
            ('immediate-data-false-eof',4,((3,0,2),(2,0,1))),
            ('pending-data-false-eof',4,((3,2,0),(2,1,0))),
            ('immediate-data-pending-eof',4,((3,1,2),(2,1,1))),
            ('pending-data-and-eof',4,((3,3,0),(2,2,0))),
            ('extra-partial-or-zero-results',8,((6,3,2),(4,0,3))),
        ]
        for label,rounds,channels in profiles:
            with self.subTest(profile=label):
                records=self.acceptance_fixture();capture=records[0]['composition']['capture']
                capture.update(rounds=rounds,wait_calls=rounds)
                for channel,(issued,pending,immediate) in zip(capture['channels'],channels):
                    channel.update(read_issued=issued,read_terminal=issued,read_pending=pending,
                                   read_immediate=immediate,read_visits=rounds,max_read_gap=1)
                self.assertTrue(validate_records(records,True,expected_stage='composed'))
        observed=self.observed()['ok'];capture=observed['composition']['capture']
        self.assertEqual(capture['rounds'],0)
        for channel in capture['channels']:
            self.assertEqual(tuple(channel[key] for key in ('read_issued','read_terminal','read_pending',
                                                           'read_immediate','read_visits','max_read_gap')),(0,0,0,0,0,0))
        self.assertFalse(validate_records(self.diagnostic(observed),expected_stage='composed'))
        records=self.acceptance_fixture();records[0]['composition']['capture']=capture
        self.reject(records,require_pass=True)

    def test_composed_binary_rejects_impossible_read_byte_eof_round_accounting(self):
        records=self.acceptance_fixture()
        for index,data_reads in ((0,2),(1,1)):
            changes=[
                ('insufficient-data-capacity',dict(read_pending=0,read_immediate=data_reads-1)),
                ('missing-separate-eof',dict(read_issued=data_reads,read_terminal=data_reads,
                                           read_pending=0,read_immediate=data_reads)),
                ('zero-known-data-submissions',dict(read_pending=0,read_immediate=0)),
                ('consumed-read-needs-later-visit',dict(read_issued=4,read_terminal=4,
                                                      read_pending=0,read_immediate=3)),
                ('missing-first-visit-gap',dict(max_read_gap=0)),
            ]
            for label,change in changes:
                with self.subTest(channel=index,defect=label):
                    bad=copy.deepcopy(records);bad[0]['composition']['capture']['channels'][index].update(change)
                    self.reject(bad,require_pass=True)
        for rounds in (1,2,3):
            with self.subTest(rounds=rounds):
                bad=copy.deepcopy(records);capture=bad[0]['composition']['capture'];capture['rounds']=rounds
                for channel in capture['channels']: channel['read_visits']=rounds
                self.reject(bad,require_pass=True)
        # The original one-read/one-round oracle must independently fail.
        with self.subTest(defect='original-one-read-one-round-oracle'):
            bad=copy.deepcopy(records);capture=bad[0]['composition']['capture'];capture['rounds']=1
            for channel in capture['channels']:
                channel.update(read_issued=1,read_terminal=1,read_immediate=1,read_visits=1)
            self.reject(bad,require_pass=True)
        for key,value in (('wait_calls',5),('exit_code_reads',2)):
            with self.subTest(counter=key):
                bad=copy.deepcopy(records);bad[0]['composition']['capture'][key]=value
                self.reject(bad,require_pass=True)

    def test_composed_fail_capture_faults_require_sticky_unknown(self):
        rows=self.observed()
        for key,value in (('sentinel_probe',False),('sentinel_unsignaled',False),
                          ('fault_site',1),('evidence_bytes_written',1),('held_writer_blocked_eof',True)):
            with self.subTest(fault=key):
                bad=self.diagnostic(rows['ok']);bad[0]['composition']['capture'][key]=value
                self.assertEqual(bad[0]['composition']['owner_release_state'],'released')
                self.assertEqual(bad[0]['composition']['overall'],'OBSERVED')
                self.reject(bad)
                bad[0]['composition']['overall']='UNKNOWN'
                self.assertFalse(validate_records(bad,expected_stage='composed'))

    def test_composed_fail_snapshot_requires_one_shot_refusal(self):
        rows=self.observed()
        for source in ('ok','query-false','image-close-false'):
            with self.subTest(source=source):
                bad=self.diagnostic(rows[source]);bad[0]['composition']['capture']['one_shot_refused']=False
                self.reject(bad)

    def test_composed_external_assertion_failure_can_remain_observed(self):
        # A failed external assertion is not a native owner fault. Neither the
        # honest recording output nor a plausible FAIL oracle must invent UNKNOWN.
        rows=self.observed();records=self.diagnostic(rows['ok'])
        self.assertEqual(records[0]['composition']['overall'],'OBSERVED')
        self.assertFalse(validate_records(records,expected_stage='composed'))
        records=self.acceptance_fixture();records[0]['status']='FAIL'
        records[-1]=summary(4,1,'case-failure',stage='composed')
        self.assertEqual(records[0]['composition']['overall'],'OBSERVED')
        self.assertFalse(validate_records(records,expected_stage='composed'))
        self.reject(records,require_pass=True)

    def test_composed_runner_stops_after_retained_attempt(self):
        rows=self.observed();record=rows['create-unavailable']
        # Execute the actual runner loop and bounded writer with managed functions
        # in place of native executables. Never invoke a child or native harness.
        runner=ROOT/'tests/windows/check_native_fixed_image_composition.ps1'
        self.assertTrue(runner.is_file())
        script=r"""
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile('__RUNNER__',[ref]$tokens,[ref]$errors)
if ($errors.Count -ne 0) { throw 'Runner parse failed' }
$loop=$ast.Find({param($a) $a -is [Management.Automation.Language.ForEachStatementAst] -and $a.Variable.Extent.Text -ceq '$exe'},$true)
$function=$ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq 'Write-Record'},$true)
$writer=New-Object IO.MemoryStream
$encoder=New-Object Text.UTF8Encoding($false,$true)
$records=0;$total=0;$failed=0;$stop='none';$invocations=0
$harnesses=@('First','Second')
function First { ++$script:invocations;$global:LASTEXITCODE=2;Write-Output '__RECORD__' }
function Second { throw 'ASSERT later case entered after retained owner' }
. ([scriptblock]::Create($function.Extent.Text))
. ([scriptblock]::Create($loop.Extent.Text))
if ($invocations -ne 1 -or $records -ne 1 -or $failed -ne 1 -or $stop -cne 'unresolved-owner') { throw 'ASSERT retained prefix runner state' }
Write-Output 'PASS actual composed runner retained prefix'
""".replace('__RUNNER__',str(runner).replace("'","''")).replace('__RECORD__',json.dumps(record,separators=(',',':')).replace("'","''"))
        # The real writer's durable Flush(bool) expects a FileStream, not MemoryStream.
        script=script.replace('$writer=New-Object IO.MemoryStream',"$log=[IO.Path]::GetTempFileName();$writer=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read)")
        script+='\n$writer.Dispose()\n'
        result=subprocess.run([SHELL,'-NoProfile','-NonInteractive','-Command',script],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASS actual composed runner retained prefix',result.stdout)

    def test_composed_bounds_keys_return_states_and_cli(self):
        records=self.acceptance_fixture()
        for path in ((),('composition',),('process_observation',),('composition','capture'),('composition','capture','channels',1)):
            bad=copy.deepcopy(records);self.at(bad[0],path)['unknown']=False;self.reject(bad)
        rows=self.observed()
        # Real serializer FAIL rows admit only their exact observed nullability.
        for fault in ('query-unavailable','query-false','query-truncated','query-count','empty','malformed','unsupported',
                      'create-unavailable','process-invalid','wait-unavailable','wait-failed','wait-timeout','exit-code-unavailable','exit-code-false'):
            diagnostic=self.diagnostic(rows[fault])
            for container in ('composition','process_observation'):
                value=diagnostic[0][container]
                if value is None: continue
                for key,actual in value.items():
                    if actual is None:
                        bad=copy.deepcopy(diagnostic);bad[0][container][key]=0
                        with self.subTest(fault=fault,key=key): self.reject(bad)
            bad=copy.deepcopy(diagnostic);bad[0]['composition']['overall']='OBSERVED';self.reject(bad)
        for fault in ('process-zero','thread-zero','create-unavailable','create-false','missing'):
            bad=self.diagnostic(rows[fault]);bad[0]['composition']['original_handles_state']='valid';self.reject(bad)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'evidence';raw=''.join(json.dumps(r)+'\n' for r in records).encode()
            path.write_bytes(raw)
            for args,success in [(['--expected-stage','composed','--require-pass'],True),
                                 (['--expected-stage','file-only'],False),([],False)]:
                result=subprocess.run([sys.executable,str(Path(__file__)),'--validate-evidence',str(path)]+args,
                                      capture_output=True,text=True,timeout=30)
                self.assertEqual(result.returncode==0,success,result.stdout+result.stderr)
            for bad in (raw[:-1],raw+b'{}\n',raw.replace(b'"claim_state": "claimed"',b'"claim_state": "claimed","claim_state":"claimed"',1),
                        b'x'*16384+b'\n',b'\xff\n',b'x'*131073):
                path.write_bytes(bad)
                with self.assertRaises(ValueError): validate_evidence(path,expected_stage='composed')
        bad=copy.deepcopy(records);bad[0]['held_path']='C:\\'+'x'*20000
        bad[0]['process_observation'].update(image_path=bad[0]['held_path'],query_return_chars=20003)
        self.reject(bad)

    def test_composed_binary_assertions_are_complete(self):
        records=self.acceptance_fixture()
        self.assertTrue(validate_records(records,True,expected_stage='composed'))
        c=records[0]['composition']['capture']
        self.assertEqual((c['stdout_bytes'],c['stderr_bytes'],c['stdout_hash'],c['stderr_hash']),
                         (4105,257,'031381f5c4fbe740','c98455caf71ceb86'))
        for key,value in [('stdout_bytes',4104),('stderr_bytes',256),('stdout_hash','0'*16),('stderr_hash','0'*16),
                          ('eof_stdout',False),('eof_stderr',False),('io_terminal',False),('sentinel_probe',False),
                          ('sentinel_unsignaled',False),('one_shot_refused',False),('rounds',0),('fault_site',1),
                          ('evidence_bytes_written',1),('held_writer_blocked_eof',True),('wait_calls',0),('exit_code_reads',0)]:
            bad=copy.deepcopy(records);bad[0]['composition']['capture'][key]=value
            with self.subTest(field=key): self.reject(bad)
        for index in (0,1):
            for key,value in [('retained',0),('discarded',1),('read_terminal',0),('read_visits',0),
                              ('max_read_gap',2),('read_released',False),('connect_released',False)]:
                bad=copy.deepcopy(records);bad[0]['composition']['capture']['channels'][index][key]=value
                with self.subTest(channel=index,field=key): self.reject(bad)
        for field,value in [('exit_wait_result',258),('exit_code',259)]:
            bad=copy.deepcopy(records);bad[0]['process_observation'][field]=value;self.reject(bad)
        def unavailable(_pairs): raise PathComparisonUnavailable('exact Windows comparison unavailable')
        for require_pass in (False,True):
            bad=copy.deepcopy(records);bad[0]['held_path']='C:\\é';bad[0]['process_observation'].update(image_path='C:\\É',query_return_chars=4)
            with self.assertRaisesRegex(ValueError,'Unavailable exact path comparison'):
                validate_records(bad,require_pass,expected_stage='composed',path_comparer=unavailable)
            self.assertTrue(validate_records(bad,require_pass,expected_stage='composed',path_comparer=lambda pairs:[True]))
            self.reject(bad,require_pass=require_pass,path_comparer=lambda pairs:[False])
        diagnostic=self.diagnostic(self.observed()['ok']);diagnostic[0]['composition']['overall']='UNKNOWN'
        diagnostic[0]['held_path']='C:\\é';diagnostic[0]['process_observation'].update(image_path='C:\\É',query_return_chars=4)
        self.assertFalse(validate_records(diagnostic,expected_stage='composed',path_comparer=unavailable))
        diagnostic[-1]['status']='PASS'
        with self.assertRaisesRegex(ValueError,'Unavailable exact path comparison'):
            validate_records(diagnostic,expected_stage='composed',path_comparer=unavailable)


class FixedImagePathContracts(unittest.TestCase):
    def test_path_grammar_cc_utf16_and_prefix_parity(self):
        for path in ('C:\\', 'z:\\fixed', '\\\\?\\C:\\fixed',
                     'C:\\Привет\\漢字-é-🙂', 'C:\\a/../b ', 'C:\\'+'x'*32764,
                     'C:\\'+'🙂'*16382):
            with self.subTest(accepted=ascii(path[:40])):
                self.assertEqual(local_path(path),path)
        rejected=[None,0,'','C:relative','C:/slash','/root','\\root',
                  '\\\\server\\share','\\\\?\\UNC\\server\\share',
                  '\\\\.\\C:\\file','\\\\?\\Volume{abc}\\file','\\\\?\\\\\\?\\C:\\file',
                  'C:\\bad\ud800','C:\\bad\udc00','C:\\'+'x'*32765,'C:\\'+'🙂'*16383]
        rejected += ['C:\\bad'+chr(c)+'path' for c in (*range(32),*range(127,160))]
        for path in rejected:
            with self.subTest(rejected=ascii(path)[:80]):
                with self.assertRaises(ValueError): local_path(path)

    def test_paired_surrogates_preserve_utf16_units(self):
        paired='C:\\'+chr(0xd83d)+chr(0xde42)
        scalar='C:\\🙂'
        try: validated=local_path(paired)
        except ValueError: self.fail('Well-formed paired UTF16 surrogates were rejected')
        self.assertEqual(validated,paired)
        self.assertTrue(portable_paths_agree(paired,scalar))
        self.assertEqual(json.loads(path_pair_input([{'held':paired,'process':scalar}]))[0]['held'],scalar)

    def test_existing_c1_controls_are_rejected(self):
        for code in (128,133,159):
            with self.subTest(code=code):
                with self.assertRaises(ValueError): local_path('C:\\bad'+chr(code)+'path')

    def test_ordinal_path_comparison_never_uses_casefold(self):
        pairs=[('\\\\?\\C:\\Fixed','c:\\fixed',True),
               ('C:\\Привет-漢字-🙂-A','c:\\Привет-漢字-🙂-a',True),
               ('C:\\same','C:\\other',False),('C:\\a/b','C:\\a\\b',False),
               ('C:\\a\\..\\b','C:\\b',False),('C:\\Straße','C:\\STRASSE',False),
               ('C:\\é','C:\\e\u0301',False),('C:\\x','C:\\x ',False)]
        def forbidden(_pairs): self.fail('Portable proof unexpectedly used exact bridge')
        for held,process,want in pairs:
            with self.subTest(held=held,process=process):
                self.assertIs(paths_agree(held,process,path_comparer=forbidden),want)
        raw='\\\\?\\C:\\Привет-🙂'
        self.assertEqual(local_path(raw),raw)
        self.assertEqual(comparable_path(raw),'C:\\Привет-🙂')

    def test_nonascii_case_requires_exact_framework_bridge(self):
        for held,process in [('C:\\é','C:\\É'),('C:\\ж','C:\\Ж'),
                             ('C:\\a-ж','C:\\b-Ж'),('C:\\漢','C:\\字')]:
            with self.subTest(held=held):
                self.assertIsNone(portable_paths_agree(held,process))
                def unavailable(_pairs): raise PathComparisonUnavailable('test unavailable exact host')
                with self.assertRaises(PathComparisonUnavailable):
                    paths_agree(held,process,path_comparer=unavailable)
        # A supplied adapter must return a correctly shaped Boolean batch.
        self.assertTrue(paths_agree('C:\\é','C:\\É',path_comparer=lambda pairs: [True]))
        self.assertFalse(paths_agree('C:\\漢','C:\\字',path_comparer=lambda pairs: [False]))
        for malformed in (True,[],[1],[True,False],{'results':[True]}):
            with self.subTest(malformed=malformed):
                with self.assertRaises(PathComparisonUnavailable):
                    paths_agree('C:\\é','C:\\É',path_comparer=lambda pairs: malformed)

    def test_require_pass_rejects_known_comparison_diagnostics(self):
        with self.assertRaisesRegex(ValueError,'Diagnostics'):
            validate_path_comparison('C:\\x','C:\\y','mismatch','FAIL','UNKNOWN','FAIL',True)

    def test_unavailable_exact_comparison_rejects_pass_summary_without_require_pass(self):
        def unavailable(_pairs): raise PathComparisonUnavailable('unavailable exact host')
        for require_pass in (False,True):
            for status,overall,summary_status in [('PASS','OBSERVED','PASS'),('FAIL','UNKNOWN','PASS')]:
                with self.subTest(require_pass=require_pass,status=status):
                    with self.assertRaisesRegex(ValueError,'Unavailable exact path comparison'):
                        validate_path_comparison('C:\\é','C:\\É','match',status,overall,
                                                 summary_status,require_pass,unavailable)
        self.assertIsNone(validate_path_comparison('C:\\é','C:\\É','match','FAIL','UNKNOWN',
                                                   'FAIL',False,unavailable))
        for status,overall,summary_status,require_pass in [('PASS','UNKNOWN','FAIL',False),
                ('FAIL','OBSERVED','FAIL',False),('FAIL','UNKNOWN','FAIL',True)]:
            with self.assertRaises(ValueError):
                validate_path_comparison('C:\\é','C:\\É','match',status,overall,
                                         summary_status,require_pass,unavailable)
        with self.assertRaises(ValueError):
            validate_path_comparison('C:\\x','C:\\y','match','FAIL','UNKNOWN','FAIL')
        self.assertFalse(validate_path_comparison('C:\\x','C:\\y','mismatch','FAIL','UNKNOWN','FAIL'))


class FixedImagePathBridgeContracts(unittest.TestCase):
    def test_fixed_adapter_rejects_unavailable_and_malformed_output(self):
        pair=[{'held':'C:\\é','process':'C:\\É'}]
        host='FIXED_IMAGE_PATH_HOST WindowsPowerShell=5.1;PSEdition=Desktop;FrameworkRelease=528040;CLR=4.0.30319.42000;CoreLibrary=mscorlib;OS=Win32NT'
        with mock.patch.object(os,'name','nt'), mock.patch.dict(os.environ,{'SystemRoot':'C:\\Windows'}):
            for output in ('','true\n','[1]\n','[true,false]\n','[true]\nextra','[true,]','{"results":[true]}'):
                with self.subTest(output=output), mock.patch.object(subprocess,'run',return_value=subprocess.CompletedProcess([],0,output.encode(),host.encode())):
                    with self.assertRaises(PathComparisonUnavailable): fixed_framework_path_comparer(pair)
            for stderr,code in [('',0),(host,1),('FIXED_IMAGE_PATH_HOST Core',0),(host.replace('528040','461808'),0)]:
                with mock.patch.object(subprocess,'run',return_value=subprocess.CompletedProcess([],code,b'[true]\n',stderr.encode())):
                    with self.assertRaises(PathComparisonUnavailable): fixed_framework_path_comparer(pair)
            observed=[]
            def boundary(command,**kwargs):
                observed.append((command,kwargs['input']))
                return subprocess.CompletedProcess(command,0,b'[true]\n',host.encode())
            with mock.patch.object(subprocess,'run',side_effect=boundary), mock.patch.object(sys,'stderr',io.StringIO()):
                self.assertEqual(fixed_framework_path_comparer(pair),[True])
            command,wire=observed[0]
            self.assertEqual(command,[os.path.join(r'C:\Windows','System32','WindowsPowerShell','v1.0','powershell.exe'),
                '-NoProfile','-NonInteractive','-File',str(ROOT/'tests/windows/check_native_fixed_image_paths.ps1')])
            self.assertEqual(json.loads(wire),pair)
        with mock.patch.object(os,'name','posix'), self.assertRaises(PathComparisonUnavailable):
            fixed_framework_path_comparer(pair)

    def test_adapter_rejects_oversized_matching_host_before_relay(self):
        pair=[{'held':'C:\\é','process':'C:\\É'}]
        host=(b'FIXED_IMAGE_PATH_HOST WindowsPowerShell=5.1;PSEdition=Desktop;'
              b'FrameworkRelease=528040;CLR=4.'+b'0'*100000+b';CoreLibrary=mscorlib;OS=Win32NT')
        relay=io.StringIO()
        with mock.patch.object(os,'name','nt'), mock.patch.dict(os.environ,{'SystemRoot':'C:\\Windows'}), \
             mock.patch.object(subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'[true]\n',host)), \
             mock.patch.object(sys,'stderr',relay):
            with self.assertRaisesRegex(PathComparisonUnavailable,'host bound/type'):
                fixed_framework_path_comparer(pair)
        self.assertEqual(relay.getvalue(),'','Oversized host frame must never be relayed')

    def test_adapter_rejects_untyped_and_malformed_host_frames(self):
        pair=[{'held':'C:\\é','process':'C:\\É'}]
        host=b'FIXED_IMAGE_PATH_HOST WindowsPowerShell=5.1;PSEdition=Desktop;FrameworkRelease=528040;CLR=4.0.30319.42000;CoreLibrary=mscorlib;OS=Win32NT'
        for frame in (None,host.decode(),bytearray(host),b'',b'\xff',host+b'\nextra',host+b' '*257):
            relay=io.StringIO()
            with self.subTest(frame_type=type(frame).__name__), \
                 mock.patch.object(os,'name','nt'), mock.patch.dict(os.environ,{'SystemRoot':'C:\\Windows'}), \
                 mock.patch.object(subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'[true]\n',frame)), \
                 mock.patch.object(sys,'stderr',relay):
                with self.assertRaises(PathComparisonUnavailable): fixed_framework_path_comparer(pair)
                self.assertEqual(relay.getvalue(),'','Invalid host frame must never be relayed')

    def test_adapter_bounds_and_pair_shape_precede_execution(self):
        pair={'held':'C:\\x','process':'C:\\x'}
        for pairs in (None,{},[pair]*5,[{'held':'C:\\x','process':None}],
                      [dict(pair,extra='x')],[{'held':'C:\\bad\ud800','process':'C:\\x'}],
                      [{'held':'C:\\'+'漢'*32764,'process':'C:\\'+'漢'*32764}]):
            with self.subTest(pairs=repr(pairs)[:80]), mock.patch.object(subprocess,'run',side_effect=AssertionError('Invalid input reached external bridge')):
                with self.assertRaises(ValueError): fixed_framework_path_comparer(pairs)

    @unittest.skipUnless(SHELL,'PowerShell compiler required')
    def test_wrong_runtime_and_arguments_refuse_without_results(self):
        if os.name=='nt' and Path(SHELL).name.lower()=='powershell.exe':
            self.skipTest('Wrong-runtime rejection needs pwsh/.NET Core, not the valid Framework host')
        path=str(ROOT/'tests/windows/check_native_fixed_image_paths.ps1')
        for args,want in [([],b'Windows PowerShell 5.1/.NET Framework 4.8 required'),
                          (['unexpected'],b'No arguments accepted')]:
            result=subprocess.run([SHELL,'-NoProfile','-NonInteractive','-File',path]+args,
                                  input=b'[]',capture_output=True,timeout=30)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(result.stdout,b'')
            self.assertIn(want,result.stderr)

    @unittest.skipUnless(SHELL,'PowerShell compiler required')
    def test_actual_constant_bridge_parser_bounds_and_framing(self):
        # Exercise the actual fixed wrapper on this managed host. This is not a
        # substitute for executing the runtime-gated Windows bridge.
        valid=[{'held':'\\\\?\\C:\\Fixed-漢-🙂','process':'c:\\fixed-漢-🙂'},
               {'held':'C:\\x','process':'C:\\y'},{'held':'C:\\é','process':'C:\\é'}]
        invalid=[b'',b'{}',b'[null]',b'[[]]',b'[true]',b'[{}]',
                 b'[{"held":"C:\\\\x","process":null}]',
                 b'[{"held":"C:\\\\x","process":"C:\\\\x","extra":"x"}]',
                 b'[{"held":"C:\\\\x","held":"C:\\\\x","process":"C:\\\\x"}]',
                 b'[',b'[]x',b'[]\x00',b'\xff',b'\xef\xbb\xbf[]',b' '*131073]
        invalid += [json.dumps(value,ensure_ascii=True).encode() for value in
            ([{'held':'C:\\x','process':'C:\\x'}]*5,
             [{'held':'C:\\bad'+chr(133),'process':'C:\\x'}],
             [{'held':'C:\\bad\ud800','process':'C:\\x'}],
             [{'held':'C:\\'+'x'*32765,'process':'C:\\x'}])]
        cases=[(json.dumps(valid,ensure_ascii=False).encode(), '[true,false,false]\n'),
               (json.dumps([{'process':'c:\\fixed','held':'C:\\Fixed'}]*4).encode(), '[true,true,true,true]\n'),
               (b'[]','[]\n'),(b'[]'+b' '*131070,'[]\n')]
        cases += [(wire,None) for wire in invalid]
        encoded=json.dumps([{'input':base64.b64encode(wire).decode(),'expected':expected}
                            for wire,expected in cases])
        script=r'''
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile('__BRIDGE__',[ref]$tokens,[ref]$errors)
if ($errors.Count -ne 0) { throw 'Bridge PowerShell parse failed' }
$assignment=$ast.Find({param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -ceq '$bridgeSource'},$true)
$wrapper=$assignment.Right.Find({param($a) $a -is [Management.Automation.Language.StringConstantExpressionAst]},$true).Value
Add-Type -TypeDefinition ([IO.File]::ReadAllText('__PATH__')+"`n"+$wrapper)
$cases=ConvertFrom-Json -InputObject '__CASES__'
foreach ($case in $cases) {
 $bytes=[Convert]::FromBase64String($case.input)
 $stream=New-Object IO.MemoryStream(,$bytes)
 $writer=New-Object IO.StringWriter
 $rejected=$false
 try { [PortableVBox.FixedImagePathBridge]::Run($stream,$writer) } catch { $rejected=$true }
 finally { $stream.Dispose() }
 if ($null -eq $case.expected) {
  if (-not $rejected -or $writer.ToString().Length -ne 0) { throw 'ASSERT malformed bridge input produced results' }
 } elseif ($rejected -or $writer.ToString() -cne $case.expected) { throw 'ASSERT bridge ordering/framing or exact bound' }
}
Write-Output ('PASS actual constant bridge parser '+$cases.Count+' cases; local managed host only')
'''.replace('__BRIDGE__',str(ROOT/'tests/windows/check_native_fixed_image_paths.ps1')).replace('__PATH__',str(ROOT/'tests/windows/NativeFixedImagePath.cs')).replace('__CASES__',encoded.replace("'","''"))
        # Keep the large exact-bound corpus off command-line limits.
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'bridge-contract.ps1';path.write_text(script,encoding='utf-8')
            result=subprocess.run([SHELL,'-NoProfile','-NonInteractive','-File',str(path)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('PASS actual constant bridge parser',result.stdout)


class FixedImageWindowsPathBridgeContracts(unittest.TestCase):
    def test_nonascii_bridge_uses_windows_framework(self):
        if os.name!='nt':
            self.skipTest('PENDING: actual Windows PowerShell 5.1/.NET Framework 4.8 bridge execution')
        held,process='C:\\é','C:\\É'
        self.assertIsNone(portable_paths_agree(held,process),'Must force changed non-ASCII UTF16 units')
        # The fixed adapter must fail, never skip, if the exact executable,
        # source, runtime gate or correctly framed result is unavailable here.
        self.assertEqual(fixed_framework_path_comparer([{'held':held,'process':process}]),[True])
        print('WINDOWS_FRAMEWORK_PATH_RESULT held=C:\\u00e9 process=C:\\u00c9 result=true',flush=True)


class FixedImageArtifactContracts(unittest.TestCase):
    def test_accept_complete_independent_fixture(self):
        self.assertTrue(validate_records(samples(), require_pass=True))

    def test_composed_stage_not_available_in_task1(self):
        records=samples()
        for record in records: record['stage']='composed'
        with self.assertRaises(ValueError): validate_records(records)

    def test_mutations(self):
        changes = [('mutation_authorized', True), ('hash_matches', True),
            ('actual_sha256', ''), ('actual_size', None), ('bytes_hashed', 0),
            ('eof_request_bytes', 0), ('eof_request_bytes', 2), ('eof_return_bytes', 1), ('volume_serial', ''),
            ('held_path', ''), ('create_calls', 1), ('process_observation', {}),
            ('read_state', 'known-incomplete'), ('read_error', 5), ('close_state', 'returned-failure')]
        for key, value in changes:
            with self.subTest(key=key):
                records=samples();records[0][key]=value
                with self.assertRaises(ValueError): validate_records(records, True)

    def test_failure_prefix_is_diagnostic_only(self):
        records=samples()[:1];records[0].update(status='FAIL', refusal='observation-failure', close_state='return-unknown')
        records.append(summary(1, 1, 'unresolved-owner'))
        self.assertFalse(validate_records(records))
        with self.assertRaises(ValueError): validate_records(records, True)

    def test_known_incomplete_diagnostics(self):
        for request, returned, hashed in [(65536,0,1),(1,1,17),(None,None,1)]:
            records=samples()[:1];records[0].update(status='FAIL', refusal='observation-failure',
                read_state='known-incomplete', actual_sha256=None, read_error=None,
                eof_request_bytes=request,eof_return_bytes=returned,bytes_hashed=hashed,write_probe=None,delete_probe=None)
            records.append(summary(1,1,'case-failure'))
            self.assertFalse(validate_records(records))
            records[0]['status']='PASS'
            with self.assertRaises(ValueError): validate_records(records)

    def test_native_unknown_and_known_failure_diagnostics(self):
        unknown=samples()[3];unknown.update(case='matching-image',status='FAIL',refusal='observation-failure',
            open_state='return-unknown',open_error=None)
        self.assertFalse(validate_records([unknown,summary(1,1,'unresolved-owner')]))
        unknown['close_state']='returned-success'
        with self.assertRaises(ValueError): validate_records([unknown,summary(1,1,'unresolved-owner')])
        for state,error,close,reason in [('return-unknown',None,'not-entered','unresolved-owner'),
                                         ('returned-failure',5,'returned-success','case-failure')]:
            record=samples()[0];record.update(status='FAIL',refusal='observation-failure',read_state=state,
                read_error=error,actual_sha256=None,bytes_hashed=3,eof_request_bytes=None,eof_return_bytes=None,
                write_probe=None,delete_probe=None,close_state=close)
            self.assertFalse(validate_records([record,summary(1,1,reason)]))

    def test_forged_pass_prefix_is_not_acceptance(self):
        for count in range(4):
            with self.assertRaises(ValueError): validate_records(samples()[:count]+[summary(count,0)],True)

    def test_sequence_and_summary_mutations_independent(self):
        for records in [samples()[:1]+samples(), [samples()[1],samples()[0]]+samples()[2:],
                        samples()+[samples()[-1]], samples()[:-1], samples()[1:]]:
            with self.assertRaises(ValueError): validate_records(records)
        for key,value in [('cases',3),('failed',1),('stop_reason','case-failure'),('schema',True)]:
            records=samples();records[-1][key]=value
            with self.assertRaises(ValueError): validate_records(records)

    def test_probe_contract_and_native_result_consistency(self):
        for key,value in [('share',1),('disposition',2),('access','DELETE'),('open_error',0),
                          ('open_state','returned-success'),('close_state','returned-success')]:
            records=samples();records[0]['write_probe'][key]=value
            with self.assertRaises(ValueError): validate_records(records)
        for index,key,value in [(3,'open_error',3),(3,'actual_size',0),(2,'read_state','complete'),
                                (1,'actual_sha256','a'*64),(0,'open_error',0)]:
            records=samples();records[index][key]=value
            with self.assertRaises(ValueError): validate_records(records)

    def test_unresolved_owner_must_stop_later_cases(self):
        for state in ('return-unknown','returned-failure','not-entered'):
            records=samples();records[0].update(status='FAIL',close_state=state)
            records[-1]=summary(4,1,'case-failure')
            with self.assertRaises(ValueError): validate_records(records)
        records=samples()[:1];records[0].update(status='FAIL',close_state='return-unknown')
        records.append(summary(1,1,'case-failure'))
        with self.assertRaises(ValueError): validate_records(records)

    def test_nullability_types_and_stale_expectation(self):
        for key,value in [('schema',True),('expected_size',True),('bytes_hashed',1.0),
                          ('open_state',''),('read_state',''),('actual_sha256','A'*64),
                          ('held_path','C:\\bad\ud800'),('held_path','C:\\bad\0path'),
                          ('held_path','\\\\server\\file'),('eof_request_bytes',False),
                          ('file_id',None),('volume_serial',True)]:
            records=samples();records[0][key]=value
            with self.assertRaises(ValueError): validate_records(records)
        records=samples();records[1]['expected_sha256']='c'*64
        with self.assertRaises(ValueError): validate_records(records)
        self.assertFalse(validate_records([summary(0,0,'build-failure')]))
        with self.assertRaises(ValueError): validate_records([summary(0,0,'build-failure')],True)

    def test_utf8_bounds_duplicates_and_truncation(self):
        raw=''.join(json.dumps(r)+'\n' for r in samples()).encode()
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'evidence'
            path.write_bytes(raw);self.assertTrue(validate_evidence(path,True))
            for bad in [raw[:-1],raw.replace(b'"schema": 1',b'"schema": 1,"schema":1',1),
                        b' '*16384+b'\n',b'\xff\n',raw+b'{}\n',raw[:-20],b'\n',b'x'*131073]:
                path.write_bytes(bad)
                with self.assertRaises(ValueError): validate_evidence(path)


CASE_FIELDS=frozenset(('kind','schema','stage','case','status','mutation_authorized','refusal',
    'create_calls','expected_size','expected_sha256','open_state','open_error','actual_size',
    'actual_sha256','bytes_hashed','read_state','read_error','eof_request_bytes','eof_return_bytes',
    'volume_serial','file_id','held_path','write_probe','delete_probe','close_state','process_observation'))
SUMMARY_FIELDS=frozenset(('kind','schema','stage','status','cases','failed','stop_reason','mutation_authorized'))
PROBE_FIELDS=frozenset(('access','share','disposition','open_state','open_error','close_state'))
OPEN_STATES=('not-entered','return-unknown','returned-failure','returned-success')
CLOSE_STATES=('not-opened','not-entered','return-unknown','returned-failure','returned-success')
READ_STATES=('not-entered','return-unknown','returned-failure','known-incomplete','complete')


def summary(cases=4,failed=0,reason='none',stage='file-only'):
    return dict(kind='fixed_image_summary',schema=2 if stage=='composed' else 1,stage=stage,status='PASS' if reason=='none' else 'FAIL',
                cases=cases,failed=failed,stop_reason=reason,mutation_authorized=False)


def samples():
    """Independent synthetic fixtures, never evidence of Windows execution."""
    records=[]
    for index,name in enumerate(CASES):
        record=dict(kind='fixed_image_case',schema=1,stage='file-only',case=name,status='PASS',
            mutation_authorized=False,refusal=('none','digest-mismatch','size-mismatch','missing-image')[index],
            create_calls=0,expected_size=17,expected_sha256='a'*64,open_state='returned-success',open_error=None,
            actual_size=17,actual_sha256='a'*64,bytes_hashed=17,read_state='complete',read_error=None,
            eof_request_bytes=1,eof_return_bytes=0,volume_serial='0000000000000000',file_id='01'*16,
            held_path='\\\\?\\C:\\fixed\\NativeCaptureFixtureChild.exe',write_probe=None,delete_probe=None,
            close_state='returned-success',process_observation=None)
        if index==0:
            for key,access in [('write_probe','GENERIC_WRITE'),('delete_probe','DELETE')]:
                record[key]=dict(access=access,share=7,disposition=3,open_state='returned-failure',open_error=32,close_state='not-opened')
        if index==1: record['actual_sha256']='b'*64
        if index>=2:
            record.update(actual_size=18 if index==2 else None,actual_sha256=None,bytes_hashed=0,
                read_state='not-entered',eof_request_bytes=None,eof_return_bytes=None,volume_serial=None,file_id=None,held_path=None)
        if index==3: record.update(open_state='returned-failure',open_error=2,close_state='not-opened')
        records.append(record)
    return records+[summary()]


def integer(value, maximum, minimum=0):
    if type(value) is not int or not minimum<=value<=maximum: raise ValueError('Invalid bounded integer')


def hex_value(value,length,nullable=False):
    if nullable and value is None: return
    if type(value) is not str or re.fullmatch('[0-9a-f]{'+str(length)+'}',value) is None:
        raise ValueError('Invalid exact lowercase hex observation')


def utf16_units(value):
    raw=value.encode('utf-16-le',errors='surrogatepass')
    return [int.from_bytes(raw[i:i+2],'little') for i in range(0,len(raw),2)]


def strings(value):
    if type(value) is str:
        if '\0' in value: raise ValueError('NUL in evidence string')
        # Python can represent a supplementary scalar either as one character
        # or as two explicit surrogates. Validate the actual UTF16 code units.
        units=utf16_units(value)
        index=0
        while index<len(units):
            unit=units[index]
            if 0xd800<=unit<=0xdbff:
                index+=1
                if index>=len(units) or not 0xdc00<=units[index]<=0xdfff: raise ValueError('Invalid UTF16 string')
            elif 0xdc00<=unit<=0xdfff: raise ValueError('Invalid UTF16 string')
            index+=1
    elif type(value) is dict:
        for key,item in value.items(): strings(key);strings(item)
    elif type(value) is list:
        for item in value: strings(item)


def local_path(value):
    if type(value) is not str or not value: raise ValueError('Missing local DOS path')
    strings(value)
    if len(utf16_units(value))>=32768: raise ValueError('Local DOS path UTF16 bound')
    plain=value[4:] if value.startswith('\\\\?\\') else value
    if re.match(r'\A[A-Za-z]:\\',plain) is None or any(ord(c)<=31 or 127<=ord(c)<=159 for c in value):
        raise ValueError('Unsupported non-local-DOS path/control')
    return value


def comparable_path(value):
    raw=local_path(value)
    return raw[4:] if raw.startswith('\\\\?\\') else raw


def portable_paths_agree(held,process):
    """Prove only the safe UTF16 subset; None means the exact host is needed."""
    left=utf16_units(comparable_path(held))
    right=utf16_units(comparable_path(process))
    if len(left)!=len(right): return False
    units=list(zip(left,right))
    # Inspect every difference before deciding, even if an earlier ASCII pair
    # already differs. Never infer cross-runtime non-ASCII casing behavior.
    if any(a!=b and (a>127 or b>127) for a,b in units): return None
    def ascii_fold(unit): return unit+32 if 65<=unit<=90 else unit
    return all(a==b or ascii_fold(a)==ascii_fold(b) for a,b in units)


class PathComparisonUnavailable(ValueError):
    pass


def path_pair_input(pairs):
    if type(pairs) is not list or len(pairs)>4: raise ValueError('At most four exact path pairs')
    for pair in pairs:
        if type(pair) is not dict or set(pair)!={'held','process'}: raise ValueError('Exact held/process path-pair keys')
        local_path(pair['held']);local_path(pair['process'])
    raw=json.dumps(pairs,ensure_ascii=True,separators=(',',':')).encode('utf-8',errors='strict')
    if len(raw)>131072: raise ValueError('Path comparison UTF8 input bound')
    return raw


def fixed_framework_path_comparer(pairs):
    """Fixed Windows Framework route only, independent of artifacts and env shell."""
    raw=path_pair_input(pairs)
    if os.name!='nt' or not os.environ.get('SystemRoot'):
        raise PathComparisonUnavailable('Unavailable exact path comparison: Windows Framework host required')
    executable=os.path.join(os.environ['SystemRoot'],'System32','WindowsPowerShell','v1.0','powershell.exe')
    command=[executable,'-NoProfile','-NonInteractive','-File',
             str(ROOT/'tests/windows/check_native_fixed_image_paths.ps1')]
    try:
        result=subprocess.run(command,input=raw,capture_output=True,timeout=30)
        if result.returncode!=0: raise ValueError('Fixed bridge refused host/input')
        if type(result.stdout) is not bytes or len(result.stdout)>64: raise ValueError('Bridge output bound/type')
        output=result.stdout.decode('utf-8',errors='strict')
        values=strict_json(output)
        if type(values) is not list or len(values)!=len(pairs) or any(type(value) is not bool for value in values):
            raise ValueError('Ordered Boolean bridge results required')
        # No extra stdout framing, text, BOM, or duplicate JSON documents.
        if output!=json.dumps(values,separators=(',',':'))+'\n': raise ValueError('Exact bridge result framing')
        if type(result.stderr) is not bytes or not 0<len(result.stderr)<=256: raise ValueError('Bridge host bound/type')
        host=result.stderr.decode('utf-8',errors='strict')
        if re.fullmatch(r'FIXED_IMAGE_PATH_HOST WindowsPowerShell=5\.1;PSEdition=Desktop;FrameworkRelease=([0-9]+);CLR=4\.[0-9.]+;CoreLibrary=mscorlib;OS=Win32NT\r?\n?',host) is None:
            raise ValueError('Missing actual Windows Framework host identity')
        release=int(re.search(r'FrameworkRelease=([0-9]+)',host)[1])
        if release<528040: raise ValueError('Framework 4.8 host required')
    except (OSError,subprocess.SubprocessError,ValueError,UnicodeError) as error:
        raise PathComparisonUnavailable('Unavailable exact path comparison: '+str(error)) from error
    # Host identity is diagnostic stderr, never part of the Boolean result stream.
    print(host.rstrip(),file=sys.stderr,flush=True)
    return values


def paths_agree(held,process,path_comparer=None):
    known=portable_paths_agree(held,process)
    if known is not None: return known
    compare=fixed_framework_path_comparer if path_comparer is None else path_comparer
    values=compare([{'held':held,'process':process}])
    if type(values) is not list or len(values)!=1 or type(values[0]) is not bool:
        raise PathComparisonUnavailable('Unavailable exact path comparison: ordered Boolean batch required')
    return values[0]


def validate_path_comparison(held,process,comparison,case_status,overall,summary_status,
                             require_pass=False,path_comparer=None):
    """Exact relation/status guard shared by the composed-schema validator."""
    if comparison not in ('match','mismatch') or case_status not in ('PASS','FAIL') or overall not in ('OBSERVED','UNKNOWN') or summary_status not in ('PASS','FAIL'):
        raise ValueError('Invalid path comparison/status labels')
    try: relation=paths_agree(held,process,path_comparer)
    except PathComparisonUnavailable:
        if summary_status!='FAIL' or case_status!='FAIL' or overall!='UNKNOWN' or require_pass:
            raise ValueError('Unavailable exact path comparison cannot certify PASS or OBSERVED')
        return None  # Structural FAIL diagnostics only, not a certified relation.
    if relation!=(comparison=='match'): raise ValueError('Path comparison disagrees with actual relation')
    if require_pass and summary_status!='PASS': raise ValueError('Diagnostics are not acceptance')
    return relation


def native_open(record):
    if record['open_state'] not in OPEN_STATES: raise ValueError('Unknown open state')
    if record['close_state'] not in CLOSE_STATES: raise ValueError('Unknown close state')
    if record['open_state']=='returned-failure': integer(record['open_error'],4294967295)
    elif record['open_error'] is not None: raise ValueError('Unavailable open error must be null')
    if record['open_state']!='returned-success' and record['close_state']!='not-opened':
        raise ValueError('Cannot close unowned/unknown handle')
    if record['open_state']=='returned-success' and record['close_state']=='not-opened':
        raise ValueError('Successful open owns exact handle')


def probe(value,access):
    if value is None: return
    if type(value) is not dict or set(value)!=PROBE_FIELDS: raise ValueError('Probe fields')
    if value['access']!=access or type(value['share']) is not int or value['share']!=7 or type(value['disposition']) is not int or value['disposition']!=3:
        raise ValueError('Probe exact compatible sharing/access/disposition')
    native_open(value)


def validate_case(record,expected_stage='file-only'):
    composed=expected_stage=='composed'
    fields=CASE_FIELDS|{'composition'} if composed else CASE_FIELDS
    if type(record) is not dict or set(record)!=fields: raise ValueError('Unexpected exact case fields')
    strings(record)
    if record['kind']!='fixed_image_case' or type(record['schema']) is not int or record['schema']!=(2 if composed else 1): raise ValueError('Case version')
    if record['stage']!=expected_stage or record['case'] not in CASES or record['status'] not in ('PASS','FAIL'):
        raise ValueError('Case labels')
    if record['mutation_authorized'] is not False: raise ValueError('Observations never authorize mutation')
    if record['refusal'] not in ('none','digest-mismatch','size-mismatch','missing-image','observation-failure')+(('sharing-failure',) if composed else ()): raise ValueError('Refusal label')
    integer(record['expected_size'],MAX_IMAGE,1);hex_value(record['expected_sha256'],64)
    integer(record['create_calls'],2147483647);integer(record['bytes_hashed'],MAX_IMAGE)
    if record['bytes_hashed']>record['expected_size']: raise ValueError('Hashed bytes exceed expectation')
    if record['actual_size'] is not None:
        integer(record['actual_size'],9223372036854775807)
        if record['bytes_hashed']>record['actual_size']: raise ValueError('Hashed bytes exceed held size')
    hex_value(record['actual_sha256'],64,True);hex_value(record['volume_serial'],16,True);hex_value(record['file_id'],32,True)
    if (record['volume_serial'] is None)!=(record['file_id'] is None): raise ValueError('Identity query is atomic')
    if record['held_path'] is not None: local_path(record['held_path'])
    native_open(record)
    if record['read_state'] not in READ_STATES: raise ValueError('Read state')
    if record['read_state']=='returned-failure': integer(record['read_error'],4294967295)
    elif record['read_error'] is not None: raise ValueError('Unavailable read error must be null')
    if (record['eof_request_bytes'] is None)!=(record['eof_return_bytes'] is None): raise ValueError('Terminal read pair')
    if record['eof_request_bytes'] is not None:
        integer(record['eof_request_bytes'],65536,1);integer(record['eof_return_bytes'],4294967295)
        if record['read_state'] not in ('complete','known-incomplete'): raise ValueError('Only successful terminal read has counts')
    if record['open_state']!='returned-success':
        if any(record[key] is not None for key in ('actual_size','actual_sha256','volume_serial','file_id','held_path','write_probe','delete_probe')) or record['read_state']!='not-entered' or record['bytes_hashed']!=0:
            raise ValueError('No observations without known successful open')
    if record['read_state']=='not-entered':
        if record['bytes_hashed']!=0 or record['actual_sha256'] is not None or record['eof_request_bytes'] is not None: raise ValueError('Read not entered observations unavailable')
    else:
        if record['actual_size']!=record['expected_size'] or record['volume_serial'] is None or record['held_path'] is None:
            raise ValueError('Read requires size, identity and path preflight')
    if record['read_state']=='return-unknown' and record['close_state']!='not-entered': raise ValueError('Unknown read forbids close reuse')
    if record['read_state']=='complete':
        if record['actual_sha256'] is None or record['bytes_hashed']!=record['expected_size'] or record['eof_request_bytes']!=1 or record['eof_return_bytes']!=0:
            raise ValueError('Complete requires full digest and positive one-byte EOF proof')
    elif record['actual_sha256'] is not None: raise ValueError('Incomplete read has no actual image digest')
    probe(record['write_probe'],'GENERIC_WRITE');probe(record['delete_probe'],'DELETE')
    if record['case']!='matching-image' and (record['write_probe'] is not None or record['delete_probe'] is not None): raise ValueError('Probes confined to matching case')
    if any(record[key] is not None for key in ('write_probe','delete_probe')):
        if record['read_state']!='complete' or record['actual_sha256']!=record['expected_sha256']: raise ValueError('Probes require complete matching image')
    if record['refusal']=='none' and (record['read_state']!='complete' or record['actual_sha256']!=record['expected_sha256']): raise ValueError('No refusal requires observed digest match')
    if record['refusal']=='digest-mismatch' and (record['read_state']!='complete' or record['actual_sha256']==record['expected_sha256']): raise ValueError('Digest refusal requires comparison reached')
    if record['refusal']=='size-mismatch' and (record['actual_size'] is None or record['actual_size']==record['expected_size'] or record['read_state']!='not-entered'): raise ValueError('Size refusal differs from digest refusal')
    if record['refusal']=='missing-image' and (record['open_state']!='returned-failure' or record['open_error']!=2): raise ValueError('Missing sibling requires actual error 2')
    if not composed and (record['create_calls']!=0 or record['process_observation'] is not None): raise ValueError('Task 1 has no create/query')
    if record['status']=='PASS':
        name=record['case']
        if record['read_state']=='known-incomplete': raise ValueError('Incomplete never PASS')
        if record['refusal']!=('none','digest-mismatch','size-mismatch','missing-image')[CASES.index(name)]: raise ValueError('Wrong expected refusal')
        if name!='missing-image' and (record['open_state']!='returned-success' or record['close_state']!='returned-success'): raise ValueError('PASS requires checked image release')
        if name in ('matching-image','digest-mismatch'):
            if record['read_state']!='complete' or record['volume_serial'] is None or record['file_id'] is None or record['held_path'] is None: raise ValueError('PASS requires actual complete held-file observation')
        if name=='matching-image':
            for key in ('write_probe','delete_probe'):
                value=record[key]
                if value is None or value['open_state']!='returned-failure' or value['open_error']!=32 or value['close_state']!='not-opened': raise ValueError('PASS requires actual sharing denial')


def unresolved_file_owner(record):
    unresolved=record['open_state']=='return-unknown' or (record['open_state']=='returned-success' and record['close_state']!='returned-success')
    for key in ('write_probe','delete_probe'):
        value=record[key]
        if value is not None:
            unresolved=unresolved or value['open_state']=='return-unknown' or (value['open_state']=='returned-success' and value['close_state']!='returned-success')
    return unresolved


COMPOSITION_FIELDS=frozenset(('claim_state','create_state','create_error','original_handles_state',
    'overall','image_release_state','owner_release_state','capture'))
PROCESS_FIELDS=frozenset(('query_state','query_error','query_return_chars','image_path','path_state','comparison',
    'exit_wait_state','exit_wait_result','exit_wait_error','exit_code_state','exit_code_error','exit_code'))
CAPTURE_BOOLS=frozenset(('eof_stdout','eof_stderr','io_terminal','sentinel_probe','sentinel_unsignaled',
    'one_shot_refused','held_writer_blocked_eof'))
CAPTURE_COUNTS={'stdout_bytes':300000,'stderr_bytes':300000,'rounds':32768,'fault_site':3,
    'evidence_bytes_written':1,'wait_calls':32768,'exit_code_reads':32768}
CAPTURE_FIELDS=CAPTURE_BOOLS|CAPTURE_COUNTS.keys()|{'stdout_hash','stderr_hash','channels'}
CHANNEL_COUNTS={'retained':65536,'discarded':300000,'read_issued':32768,'read_terminal':32768,
    'read_pending':32768,'read_immediate':32768,'read_visits':32768,'max_read_gap':1}
CHANNEL_FIELDS=CHANNEL_COUNTS.keys()|{'read_released','connect_released'}


def exact_object(value,fields,label):
    if type(value) is not dict or set(value)!=fields: raise ValueError('Exact '+label+' fields required')


def nullable_uint(value,present):
    if present: integer(value,4294967295)
    elif value is not None: raise ValueError('Unavailable return/error must be null')


def validate_capture(c):
    exact_object(c,CAPTURE_FIELDS,'capture')
    for key in CAPTURE_BOOLS:
        if type(c[key]) is not bool: raise ValueError('Capture Boolean required')
    # CompositionSnapshot refuses every snapshot until this assertion, even FAIL.
    if not c['one_shot_refused']: raise ValueError('Composed snapshot requires one-shot refusal')
    for key,limit in CAPTURE_COUNTS.items(): integer(c[key],limit)
    hex_value(c['stdout_hash'],16);hex_value(c['stderr_hash'],16)
    if type(c['channels']) is not list or len(c['channels'])!=2: raise ValueError('Ordered stdout/stderr channels required')
    for channel,total in zip(c['channels'],(c['stdout_bytes'],c['stderr_bytes'])):
        exact_object(channel,CHANNEL_FIELDS,'channel')
        for key,limit in CHANNEL_COUNTS.items(): integer(channel[key],limit)
        for key in ('read_released','connect_released'):
            if type(channel[key]) is not bool: raise ValueError('Channel release Boolean required')
        if channel['retained']+channel['discarded']!=total: raise ValueError('Channel byte accounting')
        if channel['read_terminal']>channel['read_issued']: raise ValueError('Terminal count exceeds issued')
        if channel['read_pending']+channel['read_immediate']>channel['read_issued']: raise ValueError('Known returns exceed issued')
        if channel['read_visits']!=c['rounds']: raise ValueError('Fair channel visits required')
        if c['io_terminal'] and channel['read_terminal']!=channel['read_issued']: raise ValueError('Terminal IO contradicts pending reads')
        if channel['read_released'] and channel['read_terminal']!=channel['read_issued']: raise ValueError('Released read cannot be pending')


def validate_process(q,record,end,require_pass,path_comparer):
    exact_object(q,PROCESS_FIELDS,'process')
    if q['query_state'] not in OPEN_STATES: raise ValueError('Query return state')
    nullable_uint(q['query_error'],q['query_state']=='returned-failure')
    nullable_uint(q['query_return_chars'],q['query_state']=='returned-success')
    if q['path_state'] not in ('not-observed','unavailable','malformed','truncated','unsupported','valid'): raise ValueError('Path state')
    if q['comparison'] not in ('not-performed','match','mismatch'): raise ValueError('Comparison label')
    if q['query_state']!='returned-success':
        if q['path_state']!=('not-observed' if q['query_state']=='not-entered' else 'unavailable') or q['image_path'] is not None or q['comparison']!='not-performed':
            raise ValueError('No path without known TRUE query')
    else:
        count=q['query_return_chars'];state=q['path_state'];raw=q['image_path']
        if state not in ('malformed','truncated','unsupported','valid'): raise ValueError('TRUE query path classification required')
        if state in ('malformed','truncated'):
            if raw is not None or q['comparison']!='not-performed': raise ValueError('Invalid query cannot publish repaired path/comparison')
            if count==0 and state!='malformed': raise ValueError('Zero query count is malformed')
        else:
            if type(raw) is not str or not 0<count<32768 or count!=len(utf16_units(raw)): raise ValueError('Actual complete query UTF16 count required')
            if state=='valid':
                local_path(raw);local_path(record['held_path'])
                validate_path_comparison(record['held_path'],raw,q['comparison'],record['status'],
                    record['composition']['overall'],end['status'],require_pass,path_comparer)
            else:
                try: local_path(raw)
                except ValueError: pass
                else: raise ValueError('Unsupported path was actually supported')
                if q['comparison']!='not-performed': raise ValueError('Unsupported path cannot compare')
    if q['exit_wait_state'] not in ('not-entered','return-unknown','returned'): raise ValueError('Wait state')
    nullable_uint(q['exit_wait_result'],q['exit_wait_state']=='returned')
    nullable_uint(q['exit_wait_error'],q['exit_wait_state']=='returned' and q['exit_wait_result']==4294967295)
    if q['exit_code_state'] not in OPEN_STATES: raise ValueError('Exit-code state')
    nullable_uint(q['exit_code_error'],q['exit_code_state']=='returned-failure')
    nullable_uint(q['exit_code'],q['exit_code_state']=='returned-success')
    if q['exit_code_state']!='not-entered' and (q['exit_wait_state']!='returned' or q['exit_wait_result']!=0):
        raise ValueError('Exit-code call requires actual signaled wait')


def validate_composition(record,end,require_pass,path_comparer):
    c=record['composition'];exact_object(c,COMPOSITION_FIELDS,'composition')
    if c['claim_state']!='claimed': raise ValueError('Actual transferred claim required')
    if c['create_state'] not in ('NotEntered','EnteredReturnUnknown','ReturnedFalse','ReturnedTrue'): raise ValueError('Create state')
    integer(record['create_calls'],1)
    if record['create_calls']!=(0 if c['create_state']=='NotEntered' else 1): raise ValueError('One create entry count')
    nullable_uint(c['create_error'],c['create_state']=='ReturnedFalse')
    if c['original_handles_state'] not in ('not-observed','valid','invalid'): raise ValueError('Original check state')
    if (c['original_handles_state']!='not-observed')!=(c['create_state']=='ReturnedTrue'): raise ValueError('Original check follows known TRUE create only')
    if c['overall'] not in ('OBSERVED','UNKNOWN'): raise ValueError('Overall observation state')
    if c['image_release_state'] not in ('released','retained') or c['owner_release_state'] not in ('released','retained'): raise ValueError('Release state')
    if (c['image_release_state']=='retained')!=unresolved_file_owner(record): raise ValueError('Image release contradicts exact file/probe ledger')
    if c['owner_release_state']=='released' and c['image_release_state']!='released': raise ValueError('Owner release requires image/probes released')
    unknown_acquisition=c['create_state']=='EnteredReturnUnknown' or c['original_handles_state']=='invalid'
    if unknown_acquisition and (c['image_release_state']!='retained' or c['owner_release_state']!='retained'): raise ValueError('Uncertain acquisition retains image and owner')
    # Release gates apply before CloseHandle entry, not just a successful return.
    # Aggregate retention may reflect this close failure or an unresolved probe.
    image_close_entered=record['close_state'] in ('return-unknown','returned-failure','returned-success')
    # FixedImageProbeState.Resolved requires known open failure or known close
    # success. A present but not-yet-entered probe is not resolved either.
    unresolved_probe=any(value is not None and value['open_state']!='returned-failure' and
        value['close_state']!='returned-success' for value in (record['write_probe'],record['delete_probe']))
    if image_close_entered and (unknown_acquisition or unresolved_probe):
        raise ValueError('Image close entry requires known acquisition and resolved probes')
    valid=c['create_state']=='ReturnedTrue' and c['original_handles_state']=='valid'
    if valid:
        validate_capture(c['capture']);validate_process(record['process_observation'],record,end,require_pass,path_comparer)
    elif c['capture'] is not None or record['process_observation'] is not None: raise ValueError('No query/capture outside valid original success')
    denials=all(record[key] is not None and record[key]['open_state']=='returned-failure' and record[key]['open_error']==32 and record[key]['close_state']=='not-opened' for key in ('write_probe','delete_probe'))
    if record['create_calls'] and (record['refusal']!='none' or not denials or record['read_state']!='complete' or record['actual_sha256']!=record['expected_sha256']):
        raise ValueError('Create requires completed image and both sharing denials')
    bad_probe=any(record[key] is not None and (record[key]['open_state']!='returned-failure' or record[key]['open_error']!=32) for key in ('write_probe','delete_probe'))
    if (record['refusal']=='sharing-failure')!=bad_probe: raise ValueError('Sharing refusal requires actual failed sharing proof')
    diagnostic=c['create_state']!='ReturnedTrue' or c['original_handles_state']!='valid'
    if valid:
        q=record['process_observation'];capture=c['capture']
        exited=q['exit_wait_state']=='returned' and q['exit_wait_result']==0 and q['exit_code_state']=='returned-success'
        # These recorded capture faults call MarkUnknown in the real owner.
        # Successful cleanup or an external assertion result cannot clear it.
        diagnostic=(q['path_state']!='valid' or q['comparison']!='match' or not exited or
                    not capture['sentinel_probe'] or not capture['sentinel_unsignaled'] or
                    capture['fault_site']!=0 or capture['evidence_bytes_written']!=0 or capture['held_writer_blocked_eof'])
        if (capture['wait_calls']==0)!=(q['exit_wait_state']=='not-entered'): raise ValueError('Wait entry/counter mismatch')
        # Earlier polls can have read codes; latest attempt's returned ledger stays independent.
        if q['exit_code_state']!='not-entered' and capture['exit_code_reads']==0: raise ValueError('Exit-code entry/counter mismatch')
        if image_close_entered and (not exited or not capture['io_terminal'] or not capture['eof_stdout'] or not capture['eof_stderr'] or not all(ch['read_released'] and ch['connect_released'] for ch in capture['channels'])):
            raise ValueError('Image close entry lacks exit/EOF/terminal released slots')
    if (diagnostic or c['owner_release_state']=='retained' or bad_probe) and c['overall']!='UNKNOWN': raise ValueError('Failure state cannot be OBSERVED')
    if record['status']=='PASS':
        if c['owner_release_state']!='released' or c['image_release_state']!='released': raise ValueError('PASS retains owner')
        if record['case']!='matching-image':
            if c['create_state']!='NotEntered': raise ValueError('Expected negative must have zero creation')
        else:
            if not valid or c['overall']!='OBSERVED' or q['path_state']!='valid' or q['comparison']!='match' or q['exit_code']!=0 or not exited:
                raise ValueError('PASS requires observed matching query and actual exit zero')
            required=('eof_stdout','eof_stderr','io_terminal','sentinel_probe','sentinel_unsignaled','one_shot_refused')
            if not all(capture[key] for key in required) or capture['rounds']==0 or capture['fault_site']!=0 or capture['evidence_bytes_written']!=0 or capture['held_writer_blocked_eof'] or not 1<=capture['wait_calls']<=capture['rounds'] or capture['exit_code_reads']!=1:
                raise ValueError('Full Binary independent capture proof required')
            if (capture['stdout_bytes'],capture['stderr_bytes'],capture['stdout_hash'],capture['stderr_hash'])!=(4105,257,'031381f5c4fbe740','c98455caf71ceb86'):
                raise ValueError('Exact full Binary bytes/hash including PVC2 exclusion required')
            for channel,total in zip(capture['channels'],(capture['stdout_bytes'],capture['stderr_bytes'])):
                if not channel['read_released'] or not channel['connect_released'] or channel['read_issued']==0 or channel['read_issued']!=channel['read_terminal'] or channel['discarded']!=0:
                    raise ValueError('Binary slots terminal/released with complete retained capture')
                # ReadStep consumes at most 4096 data bytes, then observes EOF
                # on a separate terminal error. Data needs TRUE/IO_PENDING;
                # synchronous FALSE/error109 EOF counts in neither return bin.
                # Partial/zero-byte reads can increase counts: these are minima.
                data_reads=(total+4095)//4096
                if channel['read_pending']+channel['read_immediate']<data_reads or channel['read_terminal']<data_reads+1:
                    raise ValueError('Binary data and separate EOF require enough completed reads')
                # Prepare issues no reads. Each ReadStep consumes before issuing,
                # so even immediate completion needs a later visit. PASS cannot
                # use recovery polls, which necessarily make the owner UNKNOWN.
                if channel['read_issued']>=capture['rounds'] or channel['max_read_gap']!=1:
                    raise ValueError('Binary read consumption requires later fair visits')


def unresolved_owner(record):
    return unresolved_file_owner(record) or (record['stage']=='composed' and record['composition']['owner_release_state']=='retained')


def validate_records(records,require_pass=False,expected_stage='file-only',path_comparer=None):
    if expected_stage not in ('file-only','composed'): raise ValueError('Explicit supported stage required')
    if type(records) is not list or not 1<=len(records)<=5: raise ValueError('At most four cases and summary')
    if expected_stage=='composed':
        # Also bound direct-record callers. File readers independently check exact
        # input bytes (including whitespace), without truncating observations.
        total=0
        for record in records:
            try: size=len(json.dumps(record,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode('utf-8',errors='surrogatepass'))+1
            except (TypeError,ValueError,RecursionError) as error: raise ValueError('Invalid bounded record') from error
            total+=size
            if size>16384 or total>131072: raise ValueError('Composed record UTF8 bound')
    cases=records[:-1];end=records[-1]
    if type(end) is not dict or set(end)!=SUMMARY_FIELDS: raise ValueError('Missing exact final summary')
    strings(end)
    if end['kind']!='fixed_image_summary' or type(end['schema']) is not int or end['schema']!=(2 if expected_stage=='composed' else 1) or end['stage']!=expected_stage or end['status'] not in ('PASS','FAIL') or end['mutation_authorized'] is not False: raise ValueError('Summary labels/version')
    integer(end['cases'],4);integer(end['failed'],4)
    if end['stop_reason'] not in ('none','case-failure','unresolved-owner','build-failure','evidence-failure'): raise ValueError('Summary stop reason')
    expected=None
    for index,record in enumerate(cases):
        validate_case(record,expected_stage)
        if expected_stage=='composed': validate_composition(record,end,require_pass,path_comparer)
        if record['case']!=CASES[index] or record['stage']!=end['stage']: raise ValueError('Ordered case prefix/stage')
        value=(record['expected_size'],record['expected_sha256'])
        if expected is not None and value!=expected: raise ValueError('Cases must retain same pristine build expectation')
        expected=value
        if unresolved_owner(record) and (index!=len(cases)-1 or end['stop_reason']!='unresolved-owner'):
            raise ValueError('Unresolved owner must stop later cases with retained diagnostics')
    if end['cases']!=len(cases) or end['failed']!=sum(r['status']=='FAIL' for r in cases): raise ValueError('Summary count mismatch')
    passed=end['status']=='PASS'
    if passed:
        if len(cases)!=4 or end['failed']!=0 or end['stop_reason']!='none': raise ValueError('PASS requires all four ordered PASS cases')
    elif end['stop_reason']=='none': raise ValueError('FAIL requires stop reason')
    if end['stop_reason']=='build-failure' and cases: raise ValueError('Build failure precedes native cases')
    if end['stop_reason']=='case-failure' and (not cases or end['failed']==0): raise ValueError('Case failure requires actual failed case')
    if end['stop_reason']=='unresolved-owner':
        if not cases or cases[-1]['status']!='FAIL': raise ValueError('Unresolved owner requires attempted failed case')
        if not unresolved_owner(cases[-1]): raise ValueError('Unresolved-owner stop requires retained native ownership')
    if require_pass and not passed: raise ValueError('Diagnostics are not acceptance')
    return passed


def strict_json(line):
    def pairs(items):
        result={}
        for key,value in items:
            if key in result: raise ValueError('Duplicate JSON key')
            result[key]=value
        return result
    def invalid(value): raise ValueError('Nonfinite JSON value')
    try: return json.loads(line,object_pairs_hook=pairs,parse_constant=invalid)
    except (RecursionError,json.JSONDecodeError) as error: raise ValueError('Invalid bounded JSON') from error


def validate_evidence(path,require_pass=False,expected_stage='file-only',path_comparer=None):
    path=Path(path)
    if not 0<path.stat().st_size<=131072: raise ValueError('Artifact total bound')
    records=[];total=0
    with path.open('rb') as stream:
        while True:
            line=stream.readline(16385)
            if not line: break
            total+=len(line)
            if len(line)>16384 or total>131072 or len(records)>=5 or not line.endswith(b'\n'): raise ValueError('Record bound/truncation')
            try: value=strict_json(line.decode('utf-8',errors='strict'))
            except UnicodeDecodeError as error: raise ValueError('Invalid UTF8 evidence') from error
            records.append(value)
    return validate_records(records,require_pass,expected_stage,path_comparer)


if __name__=='__main__':
    if '--validate-evidence' in sys.argv:
        import argparse
        parser=argparse.ArgumentParser(description='Validate fixed-image diagnostics only, never resource authority')
        parser.add_argument('--validate-evidence',required=True);parser.add_argument('--require-pass',action='store_true')
        parser.add_argument('--expected-stage',choices=('file-only','composed'),default='file-only')
        args=parser.parse_args()
        try:
            passed=validate_evidence(args.validate_evidence,args.require_pass,args.expected_stage)
            print('PASS fixed image evidence schema'+(' and all cases' if passed else ' (FAIL diagnostics only)'))
        except (OSError,ValueError) as error:
            print('Invalid fixed image evidence: '+str(error),file=sys.stderr);sys.exit(1)
    else: unittest.main()
