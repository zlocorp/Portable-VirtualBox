"""Bounded source contract; this is not a whole-program security proof."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ObservationContractTests(unittest.TestCase):
    def test_diagnostics_do_not_use_ambiguous_registry_reads(self):
        source = (ROOT / 'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        active = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith(';'))
        self.assertNotIn('RegRead(', active, 'Diagnostic must distinguish UNKNOWN from ABSENT through the native adapter')
        self.assertIn('_PortableDiagnosticWrite()', active)

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
            calls = re.findall(r'DllCall\("[^"\n]+",\s*"[^"\n]+",\s*"([^"\n]+)"', source)
            self.assertTrue(calls, str(path))
            self.assertLessEqual(set(calls), allowed)
            for forbidden in ('Run(', 'RunWait(', 'ProcessClose(', 'RegWrite(', 'RegDelete(', 'FileDelete('):
                self.assertNotIn(forbidden, source)

if __name__ == '__main__':
    unittest.main()
