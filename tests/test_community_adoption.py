"""Contracts for public features and provenance, not Windows execution evidence."""
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

class CommunityAdoption(unittest.TestCase):
    def test_user_commands_are_wired(self):
        entry = (ROOT / 'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        for command in ('--save-language', '--app-status', '--about'):
            self.assertIn('Case "' + command + '"', entry)

    def test_runtime_checks_cover_real_oracle_staging_requirements(self):
        import sys
        sys.path.insert(0, str(ROOT / 'scripts'))
        from prepare_app64 import REQUIRED_PE, REQUIRED_DATA
        path = ROOT / 'source/PortableApp.au3'
        self.assertTrue(path.is_file(), 'Native completeness inspection is missing')
        source = path.read_text(encoding='utf-8-sig')
        for relative in REQUIRED_PE + REQUIRED_DATA:
            self.assertIn(relative.replace('/', '\\'), source)

    def test_user_docs_and_provenance_are_available(self):
        for name in ('CHANGELOG.md', 'FEATURES.md', 'CREDITS.md',
                     'README.ru.md', 'docs/COMMUNITY-ADOPTION.md'):
            with self.subTest(name=name):
                self.assertTrue((ROOT / name).is_file(), 'Missing product document: ' + name)

    def test_no_elevation_or_arbitrary_commands_in_settings(self):
        path = ROOT / 'source/LauncherSettings.au3'
        self.assertTrue(path.is_file())
        source = path.read_text(encoding='utf-8-sig')
        for forbidden in ('#RequireAdmin', 'RegWrite(', 'Run(', 'RunWait(', 'Execute('):
            self.assertNotIn(forbidden, source)

    def test_about_is_short_not_a_contributor_roster(self):
        source = (ROOT / 'source/LauncherAbout.au3').read_text(encoding='utf-8-sig')
        self.assertNotIn('_LI("about.community"', source)
        self.assertNotIn('Deac2, ThatAdminGuy', source)
        self.assertNotIn('THIRD_PARTY_NOTICES.md', source)
        self.assertIn('CREDITS.md', source)
        self.assertIn('CC BY-NC-SA 3.0', source)

    def test_notices_are_consolidated_without_losing_upstream(self):
        source = (ROOT / 'CREDITS.md').read_text(encoding='utf-8')
        for mark in ('Michael Meyer', 'vboxme', 'CC BY-NC-SA 3.0', 'AutoIt', 'Deac2', 'ThatAdminGuy', 'bitamind'):
            self.assertIn(mark, source)
        self.assertFalse((ROOT / 'THIRD_PARTY_NOTICES.md').exists())
