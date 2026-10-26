"""Bounded source contract; this is not a whole-program security proof."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MUTATIONS = re.compile(r'\b(?:Run|RunWait|ProcessClose|RegWrite|RegDelete|FileDelete)\s*\(', re.IGNORECASE)

class ObservationContractTests(unittest.TestCase):
    def test_windows10_11_host_policy_and_server_exclusion(self):
        obs=(ROOT / 'source/WindowsObservation.au3').read_text(encoding='utf-8-sig')
        self.assertIn('$build >= 19041 And $product = 1',obs)
        p=(ROOT / 'source/HostPreflight.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Windows 10/11 workstation required',p)
        self.assertNotIn('Windows 11 workstation required',p)
        native=(ROOT / 'tests/native/test_windows_observation.au3').read_text(encoding='utf-8')
        for code in ('19041, 1', '19045, 1', '18363, 1', '26100, 3'):
            self.assertIn(code,native)

    def test_diagnostics_do_not_use_ambiguous_registry_reads(self):
        source = (ROOT / 'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        active = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith(';'))
        self.assertNotIn('RegRead(', active, 'Diagnostic must distinguish UNKNOWN from ABSENT through the native adapter')
        self.assertIn('_PortableDiagnosticWrite()', active)

    def test_mutation_matcher_uses_identifier_boundaries(self):
        self.assertIsNone(MUTATIONS.search('_WinObsProcessClose($token)'))
        self.assertIsNotNone(MUTATIONS.search('ProcessClose ("foreign.exe")'))
        self.assertIsNotNone(MUTATIONS.search('ProcessClose("foreign.exe")'))
        self.assertIsNotNone(MUTATIONS.search('RegWrite ($key, "value")'))

    def test_adapter_dll_surface_remains_query_only(self):
        paths = [ROOT / 'source' / name for name in ('WindowsObservation.au3', 'WindowsServiceProbe.au3', 'WindowsProcessProbe.au3')]
        for path in paths:
            self.assertTrue(path.exists(), str(path))
        allowed = {
            'GetLastError', 'RtlGetVersion', 'RegOpenKeyExW', 'RegCloseKey',
            'CloseServiceHandle', 'QueryServiceConfigW', 'QueryServiceStatusEx',
            'OpenSCManagerW', 'OpenServiceW', 'WaitForSingleObject', 'GetProcessId',
            'GetProcessTimes', 'QueryFullProcessImageNameW', 'OpenProcess', 'CloseHandle',
        }
        for path in paths:
            source = path.read_text(encoding='utf-8-sig')
            active = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith(';'))
            calls = re.findall(r'DllCall\("[^"\n]+",\s*"[^"\n]+",\s*"([^"\n]+)"', active)
            self.assertTrue(calls, str(path))
            self.assertLessEqual(set(calls), allowed)
            self.assertIsNone(MUTATIONS.search(active), str(path))

if __name__ == '__main__':
    unittest.main()
