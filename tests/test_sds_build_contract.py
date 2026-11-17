"""Closed protected SDS bridge packaging, not native lifecycle acceptance."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
class SdsBuild(unittest.TestCase):
 def test_bridge_is_embedded_and_leased_not_distributed_selector(self):
  build=(R/'scripts/build_session_helper.ps1').read_text()
  helper=(R/'source/privilege/SessionHelper.cs').read_text()
  self.assertIn("'/target:library'",build)
  for name in ('FixedEffectWorker.cs','SdsBridge.cs','SdsDiagnosticFiles.cs'):self.assertIn(name,build)
  self.assertIn("'/resource:'+$bridge+',PortableVBox.SdsBridge.dll'",build)
  self.assertIn('"PortableVBox.SdsBridge.dll"',helper)
  self.assertIn('var f=OpenLocked(p);HoldLock(f,p);',helper)
  self.assertIn('if(Hash(f)!=Hash(bytes))',helper)
  self.assertIn('finally { if (Test-Path -LiteralPath $bridge) { Remove-Item -LiteralPath $bridge -Force } }',build)
