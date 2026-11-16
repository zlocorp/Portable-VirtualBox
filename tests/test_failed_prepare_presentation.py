from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
def source(name):return (ROOT/'source'/name).read_text(encoding='utf-8-sig')
def function(s,name):return s.split('Func '+name+'(',1)[1].split('\nEndFunc',1)[0]
class FailedPreparePresentation(unittest.TestCase):
 def test_phase_saved_only_after_confirmed_exit(self):
  s=source('ManagerSession.au3');tick=function(s,'_MS_Tick')
  self.assertIn('$s["failed_worker_phase"] = $state',tick)
  self.assertLess(tick.index('If $status <> "EXITED" Then'),tick.index('$s["failed_worker_phase"] = $state'))
  self.assertIn('$s["failed_worker_phase"] = ""',function(s,'_MS_Worker'))
 def test_presentation_uses_existing_rows_without_effects(self):
  s=source('ManagerWindow.au3')
  for name in ('_MSW_ServicePresence','_MSW_FailedPrepareHint'):
   body=function(s,name)
   for forbidden in ('DllCall(', '_MS_Worker(', '_PortableServiceCollect(', 'FileRead(', 'Run('):self.assertNotIn(forbidden,body)
  self.assertIn('_MSW_FailedPrepareHint($s, $serviceRows, TimerDiff($serviceTick))',s)
  self.assertIn('_MS_FailedPreparation($s)',function(s,'_MSW_FailedPrepareHint'))
 def test_native_actual_methods_harness_is_discovered(self):
  s=(ROOT/'tests/native/test_failed_prepare_presentation.au3').read_text(encoding='utf-8-sig')
  for marker in ('ManagerWindow.au3','_MSW_FailedPrepareHint','_MS_CleanupRetryAction','duplicate','UNKNOWN','CONSENT_PREPARE','retained'):
   self.assertIn(marker,s)
