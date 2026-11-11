"""Independent fixed-image file-only diagnostics; never mutation authority."""
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
  Observe-OwnerBuild
 }
}
'''
        entries=[]
        for name in ('child_capture','launch_environment','fixed_image_observation'):
            path=str(ROOT/'tests/windows'/('check_native_'+name+'.ps1')).replace("'","''")
            entries.append((name,"& '"+path+"' -ManagedOnly",4 if name=='fixed_image_observation' else 1))
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
                        'NativeLaunchEnvironmentNative.cs','NativeFixedImageIdentity.cs'}
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
                'NativeLaunchEnvironmentNative.cs','NativeFixedImageIdentity.cs'}
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
        self.assertNotIn('BindBinaryLaunch', text)
        self.assertNotIn('FixedImageLaunchBinding', text)

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
    return dict(kind='fixed_image_summary',schema=1,stage=stage,status='PASS' if reason=='none' else 'FAIL',
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
    """Reusable status guard; actual composed-schema integration belongs to 2E."""
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


def validate_case(record):
    if type(record) is not dict or set(record)!=CASE_FIELDS: raise ValueError('Unexpected exact case fields')
    strings(record)
    if record['kind']!='fixed_image_case' or type(record['schema']) is not int or record['schema']!=1: raise ValueError('Case version')
    if record['stage']!='file-only' or record['case'] not in CASES or record['status'] not in ('PASS','FAIL'):
        raise ValueError('Case labels')
    if record['mutation_authorized'] is not False: raise ValueError('Observations never authorize mutation')
    if record['refusal'] not in ('none','digest-mismatch','size-mismatch','missing-image','observation-failure'): raise ValueError('Refusal label')
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
    if record['create_calls']!=0 or record['process_observation'] is not None: raise ValueError('Task 1 has no create/query')
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


def unresolved_owner(record):
    unresolved=record['open_state']=='return-unknown' or (record['open_state']=='returned-success' and record['close_state']!='returned-success')
    for key in ('write_probe','delete_probe'):
        value=record[key]
        if value is not None:
            unresolved=unresolved or value['open_state']=='return-unknown' or (value['open_state']=='returned-success' and value['close_state']!='returned-success')
    return unresolved


def validate_records(records,require_pass=False):
    if not 1<=len(records)<=5: raise ValueError('At most four cases and summary')
    cases=records[:-1];end=records[-1]
    if type(end) is not dict or set(end)!=SUMMARY_FIELDS: raise ValueError('Missing exact final summary')
    strings(end)
    if end['kind']!='fixed_image_summary' or type(end['schema']) is not int or end['schema']!=1 or end['stage']!='file-only' or end['status'] not in ('PASS','FAIL') or end['mutation_authorized'] is not False: raise ValueError('Summary labels/version')
    integer(end['cases'],4);integer(end['failed'],4)
    if end['stop_reason'] not in ('none','case-failure','unresolved-owner','build-failure','evidence-failure'): raise ValueError('Summary stop reason')
    expected=None
    for index,record in enumerate(cases):
        validate_case(record)
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


def validate_evidence(path,require_pass=False):
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
    return validate_records(records,require_pass)


if __name__=='__main__':
    if '--validate-evidence' in sys.argv:
        import argparse
        parser=argparse.ArgumentParser(description='Validate fixed-image diagnostics only, never resource authority')
        parser.add_argument('--validate-evidence',required=True);parser.add_argument('--require-pass',action='store_true')
        args=parser.parse_args()
        try:
            passed=validate_evidence(args.validate_evidence,args.require_pass)
            print('PASS fixed image evidence schema'+(' and all cases' if passed else ' (FAIL diagnostics only)'))
        except (OSError,ValueError) as error:
            print('Invalid fixed image evidence: '+str(error),file=sys.stderr);sys.exit(1)
    else: unittest.main()
