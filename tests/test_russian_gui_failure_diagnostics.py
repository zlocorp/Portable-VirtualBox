from pathlib import Path
import os, shutil, subprocess, unittest
ROOT=Path(__file__).resolve().parents[1]
class RussianFailureDiagnostics(unittest.TestCase):
 def test_source_preserves_gate_and_records_transport(self):
  s=(ROOT/'scripts/check_russian_gui.ps1').read_text()
  self.assertIn('LocaleProbeEvidence.Begin',s)
  self.assertIn('SetLastError(0);',s)
  self.assertIn('Marshal.GetLastWin32Error()',s)
  self.assertIn('3,250,out',s)
  self.assertIn("'failure.json'",s)
  self.assertIn('LocaleProbeEvidence]::Phase="Await"',s)
  self.assertIn('LocaleProbeEvidence]::Phase="Capture"',s)
  self.assertIn('LocaleProbeEvidence]::Phase="Click"',s)
 def test_text_observation_clears_dimensions_before_snapshot(self):
  s=(ROOT/'scripts/check_russian_gui.ps1').read_text()
  begin=s.split('public static void Begin(',1)[1].split('public static void End',1)[0]
  self.assertLess(begin.index('if(message==13){Width=0;Height=0;}'),begin.index('Last=new'))
 def test_top_level_identity_precedes_text_after_ownership_filter(self):
  s=(ROOT/'scripts/check_russian_gui.ps1').read_text()
  find=s.split('public static IntPtr Find',1)[1].split('public static Control[]',1)[0]
  self.assertLess(find.index('id==pid && IsWindowVisible(h)'),find.index('LocaleProbeEvidence.Owner=h.ToInt64();LocaleProbeEvidence.Index=-1;'))
  self.assertLess(find.index('LocaleProbeEvidence.Index=-1;'),find.index('if(Text(h)==title)'))
 def test_managed_and_writer_contracts(self):
  shell=os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh')
  if not shell:self.skipTest('PowerShell required')
  r=subprocess.run([shell,'-NoProfile','-File',str(ROOT/'tests/windows/check_russian_failure_diagnostics.ps1')],capture_output=True,text=True,timeout=30)
  self.assertEqual(r.returncode,0,r.stdout+r.stderr)
  self.assertIn('RUSSIAN_FAILURE_DIAGNOSTICS_PASS',r.stdout)
