"""Auditor must inspect bundled executable metadata, never execute untrusted tools."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
class BundledToolContracts(unittest.TestCase):
    def test_inventory_signatures_versions_and_hashes_without_execution(self):
        s=(ROOT/"scripts/audit_bundled_tools.ps1").read_text(encoding="utf-8")
        for key in ("Get-FileHash","Get-AuthenticodeSignature","FileVersion","devcon_x64.exe","devcon_x86.exe","snetcfg_x64.exe","snetcfg_x86.exe","7za.exe","Aut2exe_x64.exe","bundled-tools.json"):
            self.assertIn(key,s)
        for risk in ("Start-Process","Invoke-Expression","& $binary","Remove-Item"):
            self.assertNotIn(risk,s)

if __name__=="__main__": unittest.main()
