"""Keep real Oracle extraction changes connected to their acceptance workflows."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / '.github' / 'workflows'
EXTRACTION = ('scripts/inspect_oracle.ps1', 'scripts/prepare_app64.py',
              'scripts/oracle_extract.py', 'scripts/msi_staging.py',
              'scripts/windows_payload.py')

class AcceptanceWorkflowDependencies(unittest.TestCase):
    def paths(self, name):
        text = (WORKFLOWS / name).read_text(encoding='utf-8')
        paths = text.split('    paths:\n', 1)[1].split('  workflow_dispatch:', 1)[0]
        return {line.strip()[2:].strip('\'\"') for line in paths.splitlines()
                if line.strip().startswith('- ')}

    def test_russian_oracle_extraction_dependencies_trigger_acceptance(self):
        self.assertTrue(set(EXTRACTION).issubset(self.paths('manager-session.yml')))

    def test_relocation_extraction_dependencies_trigger_acceptance(self):
        self.assertTrue(set(EXTRACTION).issubset(self.paths('portable-relocation.yml')))

    def test_russian_acceptance_name_is_distinct_from_legacy_smoke(self):
        modern = (WORKFLOWS / 'manager-session.yml').read_text(encoding='utf-8').splitlines()[0]
        legacy = (WORKFLOWS / 'main-launcher-session.yml').read_text(encoding='utf-8').splitlines()[0]
        self.assertNotEqual(modern, legacy)
        self.assertIn('Russian Oracle', modern)
        self.assertIn('Alpine', modern)

if __name__ == '__main__':
    unittest.main()
