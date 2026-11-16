from pathlib import Path
import unittest,subprocess,tempfile,json,hashlib,os,shutil
R=Path(__file__).resolve().parents[1]
class FullOwnerImportFaults(unittest.TestCase):
 def test_generator_preserves_source_bodies_and_refuses_drift(self):
  from tests.generate_owner_fault_fixture import generate
  source=(R/'source/privilege/FixedEffectWorker.cs').read_bytes()
  generated,manifest=generate(source)
  self.assertEqual(manifest['source_sha256'],hashlib.sha256(source).hexdigest())
  self.assertTrue(manifest['reversible_source_identity'])
  for name in ('RunCore','ObserveAndWait','RetainUnknown','Prepare','Dispose'):
   self.assertIn(name,manifest['unchanged_bodies'])
  with self.assertRaises(ValueError):generate(source.replace(b'static extern uint WaitForSingleObject',b'static extern int WaitForSingleObject'))
  self.assertNotIn(b'OwnerFault',source)
 @unittest.skipUnless(shutil.which('pwsh') and os.environ.get('PVBOX_TEST_NET48_REFERENCES'),'net48 refs required')
 def test_compile_instrumented_owner_and_harness(self):
  with tempfile.TemporaryDirectory() as d:
   command=f"python tests/generate_owner_fault_fixture.py '{d}'; if($LASTEXITCODE){{exit 1}}; . ./tests/windows/NativeFixedFixtureBuild.ps1; Compile-FixedFixtureSources @('{d}/FixedEffectWorker.instrumented.cs','tests/windows/FullOwnerFaultBoundary.cs','tests/windows/FullOwnerFaultProbe.cs') '{d}/probe.exe' 'PortableVBox.FullOwnerFaultProbe'"
   p=subprocess.run(['pwsh','-NoProfile','-Command',command],cwd=R,text=True,capture_output=True,timeout=60)
   self.assertEqual(p.returncode,0,p.stdout+p.stderr)
 def test_only_declaration_whole_source_allowlist(self):
  from tests.generate_owner_fault_fixture import generate,PAIRS,declaration_pairs
  source=(R/'source/privilege/FixedEffectWorker.cs').read_bytes();changed,meta=generate(source)
  for old,new in reversed(declaration_pairs(source)):changed=changed.replace(new,old)
  self.assertEqual(changed,source)
  self.assertEqual(meta['declaration_replacements'],5)
  for old,new in PAIRS:
   self.assertTrue(old.startswith(b'  [DllImport') or old==b'internal sealed class FixedEffectWorker : IDisposable {')
  for script in ('scripts/build_session_helper.ps1','scripts/package_alpha.ps1','scripts/package_preview.py'):
   text=(R/script).read_text()
   for forbidden in ('FullOwnerFault','FixedEffectWorker.instrumented','generate_owner_fault_fixture'):
    self.assertNotIn(forbidden,text)
  build=(R/'scripts/build_session_helper.ps1').read_text()
  self.assertIn('source/privilege/FixedEffectWorker.cs',build)
  self.assertIn(r'source\privilege\FixedEffectWorker.cs',build)
 def test_closed_harness_no_owner_adoption_or_forced_lifetime(self):
  boundary=(R/'tests/windows/FullOwnerFaultBoundary.cs').read_text();probe=(R/'tests/windows/FullOwnerFaultProbe.cs').read_text()
  self.assertIn('0x00101000,false,0',boundary)
  self.assertIn('FaultObserverReady',boundary)
  self.assertIn('FixedEffectWorker.Run(info)',probe)
  self.assertIn('childExitCodeKnown&&childCode==23',probe)
  for forbidden in ('TerminateProcess','Process.Kill','Thread.Abort','thread.Interrupt','Thread.Interrupt','OpenProcess','GetMethod(','GetField(','DUPLICATE_CLOSE_SOURCE'):
   self.assertNotIn(forbidden,probe+boundary)
  self.assertNotIn('CloseHandle(',probe)
  self.assertIn('runFinally',probe);self.assertIn('Volatile.Read(ref FixedEffectWorker.FaultOriginalCloses)==0',probe)
  self.assertIn('fixture_mutex_reacquired=false',probe)
  self.assertNotIn('owner.Dispose()',probe)
  runner=(R/'tests/windows/check_full_owner_import_faults.ps1').read_text()
  self.assertIn('FULL_OWNER_IMPORT_CASES_PASS',runner)
  self.assertIn('$global:LASTEXITCODE=0',runner)
  self.assertIn('check_full_owner_import_faults.ps1',(R/'.github/workflows/native-tests.yml').read_text())
 @unittest.skipUnless(shutil.which('pwsh'),'PowerShell required')
 def test_actual_runner_tail_checks_every_status_marker(self):
  for scenario in ['pass']+[f'{mode}-{phase}-{fault}' for mode in ('wait','false','alias') for phase in ('normal','negative') for fault in ('status','marker')]+['alias-normal-evidence','alias-negative-evidence']:
   with self.subTest(scenario=scenario):
    p=subprocess.run(['pwsh','-NoProfile','-File','tests/windows/check_full_owner_import_runner_contract.ps1','-Scenario',scenario],cwd=R,text=True,capture_output=True,timeout=30)
    self.assertEqual(p.returncode,0 if scenario=='pass' else 91,p.stdout+p.stderr)
    self.assertEqual('FULL_OWNER_RUNNER_NESTED_RETURNED' in p.stdout,scenario=='pass')
 @unittest.skipUnless(shutil.which('pwsh'),'PowerShell required')
 def test_actual_false_absence_guard_requires_all_four_empty(self):
  from tests.generate_owner_fault_fixture import generate
  with tempfile.TemporaryDirectory() as d:
   generated=Path(d)/'owner.cs';generated.write_bytes(generate((R/'source/privilege/FixedEffectWorker.cs').read_bytes())[0])
   command=f"Add-Type -Path '{generated}','tests/windows/FullOwnerFaultBoundary.cs','tests/windows/FullOwnerFaultProbe.cs'; for($m=0;$m -lt 16;$m++){{$p=[IntPtr]::new(($m -band 1));$t=[IntPtr]::new(($m -band 2));$a=[PortableVBox.FullOwnerFaultProbe]::NativeFalseHasNoOutputs($p,$t,[uint32]($m -band 4),[uint32]($m -band 8));if($a -ne ($m -eq 0)){{throw 'Four-field native FALSE guard'}}}}; foreach($p in @(0,-1,12,13)){{foreach($t in @(0,-1,12,13)){{$expected=$p -notin @(0,-1) -and $t -notin @(0,-1) -and $p -ne $t;if([PortableVBox.FullOwnerFaultProbe]::GenuineHandlesDistinct([IntPtr]::new($p),[IntPtr]::new($t)) -ne $expected){{throw 'Genuine distinct guard'}}}}}}; 'FALSE_ABSENCE_GUARD_PASS 16'"
   p=subprocess.run(['pwsh','-NoProfile','-Command',command],cwd=R,text=True,capture_output=True,timeout=40)
   self.assertEqual(p.returncode,0,p.stdout+p.stderr)
   self.assertIn('FALSE_ABSENCE_GUARD_PASS 16',p.stdout)
  probe=(R/'tests/windows/FullOwnerFaultProbe.cs').read_text()
  self.assertIn('else if(!NativeFalseHasNoOutputs(FixedEffectWorker.FaultOriginalProcess,FixedEffectWorker.FaultOriginalThread,FixedEffectWorker.FaultOriginalPid,FixedEffectWorker.FaultOriginalTid))Unknown',probe)
 def test_thread_start_uncertainty_is_entered_before_invocation(self):
  probe=(R/'tests/windows/FullOwnerFaultProbe.cs').read_text()
  self.assertIn('startEntered=true;thread.Start();',probe)
  self.assertIn('if(startEntered){',probe)
  self.assertIn('if(Volatile.Read(ref runFinally)==0||Volatile.Read(ref FixedEffectWorker.FaultCreateEntered)!=0)Unknown',probe)
  self.assertNotIn('thread.Start();startEntered=true',probe)

 def test_generator_preserves_windows_line_endings_without_body_normalization(self):
  from tests.generate_owner_fault_fixture import generate,declaration_pairs
  source=(R/'source/privilege/FixedEffectWorker.cs').read_bytes().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
  changed,meta=generate(source)
  self.assertEqual(meta['line_ending'],'CRLF')
  for old,new in reversed(declaration_pairs(source)):changed=changed.replace(new,old)
  self.assertEqual(changed,source)
  with self.assertRaises(ValueError):generate(source.replace(b'\r\n',b'\n',1))

 def test_cross_thread_counter_reads_are_volatile(self):
  import re
  probe=(R/'tests/windows/FullOwnerFaultProbe.cs').read_text()
  names='CreateEntered|CreateReturned|Created|BoundaryComplete|Injected|WaitCalls|ExitQueries|OriginalCloses|CreateAttempts|DuplicateError|ObserverReady'
  self.assertIsNone(re.search(r'(?<!ref )FixedEffectWorker\.Fault(?:'+names+r')\b',probe))

 def test_true_alias_preserves_genuine_snapshot_and_observer(self):
  boundary=(R/'tests/windows/FullOwnerFaultBoundary.cs').read_text();probe=(R/'tests/windows/FullOwnerFaultProbe.cs').read_text()
  assignment='process.Thread=process.Process;'
  self.assertIn(assignment,boundary)
  self.assertLess(boundary.index('FaultOriginalThread=process.Thread'),boundary.index(assignment))
  self.assertLess(boundary.index('DuplicateHandle(GetCurrentProcess(),process.Process'),boundary.index(assignment))
  self.assertIn('FaultInjectedProcess=process.Process;FaultInjectedThread=process.Thread;',boundary)
  self.assertIn('GenuineHandlesDistinct(FixedEffectWorker.FaultOriginalProcess,FixedEffectWorker.FaultOriginalThread)',probe)
  self.assertIn('FixedEffectWorker.FaultInjectedThread==FixedEffectWorker.FaultOriginalProcess',probe)
  self.assertIn('true-aliased-outputs',probe)
  self.assertIn('genuine_handles_distinct=true injected_handles_equal=true owner_wait_calls=0',probe)
  runner=(R/'tests/windows/check_full_owner_import_faults.ps1').read_text()
  self.assertIn("'true-aliased-outputs'",runner)
  self.assertIn('fault_modes=3 hosts=6 expected_failures=3',runner)
