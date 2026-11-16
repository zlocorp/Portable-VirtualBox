from pathlib import Path
import unittest, shutil, subprocess
ROOT=Path(__file__).resolve().parents[1]
class GuestConsoleReadiness(unittest.TestCase):
 def test_observed_gates_replace_blind_input(self):
  for path in ('tests/windows/check_helper_boundary.ps1','scripts/check_manager_session_gui.ps1'):
   s=(ROOT/path).read_text()
   self.assertIn('Invoke-ObservedGuestWrite',s)
   self.assertNotIn('Start-Sleep -Seconds 25',s)
  helper=(ROOT/'tests/windows/GuestConsoleReadiness.ps1').read_text()
  self.assertIn('guest-write-ack',helper)
  self.assertIn('&& sync &&',helper)
 @unittest.skipUnless(shutil.which('pwsh'),'PowerShell required')
 def test_real_decoder_and_observed_frame_regressions(self):
  p=subprocess.run(['pwsh','-NoProfile','-Command',"Add-Type -Path 'tests/windows/GuestConsoleObservation.cs','tests/windows/GuestConsoleObservationTests.cs'; [PortableVBox.Tests.GuestConsoleObservationTests]::Run('tests/fixtures/guest-console')"],cwd=ROOT,text=True,capture_output=True,timeout=60)
  self.assertEqual(p.returncode,0,p.stdout+p.stderr)
  self.assertIn('GUEST_CONSOLE_OBSERVATION_PASS',p.stdout)

 @unittest.skipUnless(shutil.which('pwsh'),'PowerShell required')
 def test_actual_orchestration_and_resource_budgets(self):
  p=subprocess.run(['pwsh','-NoProfile','-File','tests/windows/check_guest_console_readiness.ps1'],cwd=ROOT,text=True,capture_output=True,timeout=60)
  self.assertEqual(p.returncode,0,p.stdout+p.stderr)
  self.assertIn('GUEST_CONSOLE_SEQUENCE_PASS',p.stdout)
