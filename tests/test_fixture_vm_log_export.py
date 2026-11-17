from pathlib import Path
import unittest,subprocess,shutil
R=Path(__file__).resolve().parents[1]
class FixtureVmLogExport(unittest.TestCase):
 def test_both_fixtures_bind_created_vm_and_export_in_finally(self):
  for f in ('scripts/check_manager_session_gui.ps1','tests/windows/check_helper_boundary.ps1'):
   s=(R/f).read_text();self.assertIn('New-FixtureVmLogBinding',s);self.assertIn('Export-FixtureVmLog',s)
   self.assertLess(s.index('New-FixtureVmLogBinding'),s.index("Oracle ('createvm"))
   self.assertIn('$fixtureVmLogBinding.uuid=$uuid',s)
   self.assertGreater(s.rindex('Export-FixtureVmLog'),s.rindex('finally {'))
 @unittest.skipUnless(shutil.which('pwsh'),'pwsh required')
 def test_actual_bounded_exporter(self):
  p=subprocess.run(['pwsh','-NoProfile','-File','tests/windows/check_fixture_vm_log_export.ps1'],cwd=R,text=True,capture_output=True,timeout=40)
  self.assertEqual(p.returncode,0,p.stdout+p.stderr);self.assertIn('FIXTURE_VM_LOG_EXPORT_PASS',p.stdout)
