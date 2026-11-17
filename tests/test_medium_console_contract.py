"""Source guard for the observed Windows restricted-console startup regression.

The actual behavioral gate is check_helper_boundary.ps1, not this text test.
"""
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

class MediumConsoleContract(unittest.TestCase):
    def test_keep_restriction_but_inherit_console(self):
        s = (ROOT / 'tests/windows/MediumProcess.cs').read_text(encoding='utf-8-sig')
        flags = re.search(r'CreateProcessAsUser\(token,exe,command,IntPtr.Zero,IntPtr.Zero,true,0x([0-9A-Fa-f]+)', s)
        self.assertIsNotNone(flags)
        value = int(flags.group(1), 16)
        self.assertEqual(value & 0x08000000, 0, 'Do not create a hidden console for the restricted token')
        self.assertEqual(value & 4, 4, 'Measure suspended child token before running code')
        self.assertIn('LastFacts.Administrator || LastFacts.Integrity!=8192', s)
        self.assertIn('CreateRestrictedToken(old,5,1,ref deny', s)
        self.assertIn('ResumeThread(pi.Thread)', s)

    def test_direct_probe_does_not_lock_machine_during_startup(self):
        s = (ROOT / 'tests/windows/check_helper_boundary.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("guest_start_method='direct-VBoxHeadless-passive-log-gate'", s)
        self.assertIn('vboxmanage_headless_spawn_verified=$false', s)
        self.assertIn('interactive_uac_consent_verified=$false', s)
        self.assertIn('VBoxHeadless.exe', s)
        self.assertIn('Await-GuestLog', s)
        self.assertNotIn('$proof.vboxmanage_headless_spawn_verified=$true', s)
        begin = s.index('function Await-GuestLog')
        end = s.index('$proof=[ordered]', begin)
        self.assertNotIn('Oracle (', s[begin:end])

