"""Regression fixture derived from Oracle's public 7.2.20 SHA256SUMS."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from oracle_release import parse_sha256_manifest, find_windows_installer

class OfficialManifestTests(unittest.TestCase):
    def test_debian_tilde_filename_does_not_block_windows_selection(self):
        text = (
            'a81777d2b36380ce042a29e9c554cf032eb46a793f62e3cc82e7411e535c2c26 *VirtualBox-7.2.20-175154-Win.exe\n'
            '0d6fa256eb2682278a1770ba2a8c0433ee19010d894783b78677c4dd58da3c0d *virtualbox-7.2_7.2.20-175154~Debian~bookworm_amd64.deb\n')
        entries = parse_sha256_manifest(text)
        self.assertEqual(len(entries), 2)
        self.assertEqual(find_windows_installer(entries, '7.2.20')[0], 'VirtualBox-7.2.20-175154-Win.exe')

if __name__ == '__main__':
    unittest.main()
