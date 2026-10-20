"""Require the blank-VM probe to accept a strictly validated standalone driver
receipt as well as a traditional verified Oracle MSI installation report."""
import unittest
from pathlib import Path
SCRIPT=Path(__file__).resolve().parents[1]/"scripts/vbox_vm_boot_probe.ps1"
class StandaloneVmBootContract(unittest.TestCase):
    def test_clean_standalone_report_is_explicitly_bound(self):
        s=SCRIPT.read_text(encoding="utf-8")
        for expected in ("StandaloneDriverReport","standalone-VBoxSup-primitive-INF-pnputil",
                         "system_driver_matches_package","pnputil_exit_code",
                         "RUNNER_TEMP","VBoxSup","Get-AuthenticodeSignature"):
            self.assertIn(expected,s)
    def test_no_driver_start_or_host_changes_inside_boot_probe(self):
        s="\n".join(x for x in SCRIPT.read_text(encoding="utf-8").splitlines() if not x.lstrip().startswith("#"))
        for forbidden in ("Start-Service","Stop-Service","Remove-Service","msiexec","pnputil.exe","sc.exe","taskkill"):
            self.assertNotIn(forbidden,s)
if __name__=="__main__":unittest.main()
