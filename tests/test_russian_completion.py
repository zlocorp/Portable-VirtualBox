"""Source contracts and real-file preparation tests; not Windows GUI acceptance."""
from pathlib import Path
import re
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import prepare_app64
sys.path.insert(0, str(ROOT / 'tests'))
from pe_fixture import make_pe

def source(name):
    return (ROOT / 'source' / name).read_text(encoding='utf-8-sig')

class RussianCompletion(unittest.TestCase):
    def test_user_reason_catalog_covers_manager_and_rebind_codes(self):
        manager, rebind, i18n = map(source, ('ManagerSession.au3', 'PortableVmRebind.au3', 'LauncherI18n.au3'))
        codes = set(re.findall(r'_MS_State\(\$s, (?:"[^"]+"|\$state), "([^"]+)"', manager))
        codes |= set(re.findall(r'\["reason"\] = "([^"]+)"', rebind))
        codes |= set(re.findall(r'_PVR_New\("[^"]+", "([^"]+)"', rebind))
        for code in codes | {'unsafe-or-ambiguous'}:
            with self.subTest(code=code):
                self.assertIn('Case "' + code + '"', i18n)
        self.assertIn('Func _LI_Reason(', i18n)
        self.assertIn('_LI_Reason($s["detail"])', source('ManagerWindow.au3'))
        self.assertIn('_LI_Reason($r["reason"])', rebind)

    def test_language_selection_does_not_use_temporary_ui_override(self):
        manager = source('ManagerSession.au3')
        self.assertIn('_OL_Saved(_LS_Load($s["root"]))', manager)
        self.assertIn('"CONFIGURING_LANGUAGE"', manager)
        self.assertIn('_OL_Verified(', manager)
        self.assertNotIn('GUI/LanguageID', source('LauncherSettings.au3'))

    def test_language_module_is_fixed_command_and_readonly_evidence(self):
        file = ROOT / 'source/OracleLanguage.au3'
        self.assertTrue(file.exists(), 'Oracle language coordination is missing')
        text = file.read_text(encoding='utf-8-sig')
        self.assertIn('setextradata global GUI/LanguageID ', text)
        self.assertIn('Case "ru"', text)
        self.assertIn('Case "en"', text)
        self.assertIn('Return "C"', text)
        self.assertIn('_PVI_LoadXml(', text)
        self.assertIn('nodes.length <> 1', text)
        for forbidden in ('FileWrite(', 'RegWrite(', '#RequireAdmin', 'Run(', '.save(', 'StringReplace('):
            self.assertNotIn(forbidden, text)

    def test_preparer_requires_both_russian_resources(self):
        for name in ('nls/VirtualBox_ru.qm', 'nls/qt_ru.qm'):
            self.assertIn(name, prepare_app64.REQUIRED_DATA)
            self.assertIn(name.replace('/', '\\'), source('PortableApp.au3'))

    def test_missing_or_empty_ru_resource_refuses_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in prepare_app64.REQUIRED_PE:
                p = root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(make_pe({}, plus=True))
            for name in prepare_app64.REQUIRED_DATA:
                p = root / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(b'fixture')
            for name in ('nls/VirtualBox_ru.qm', 'nls/qt_ru.qm'):
                path = root / name
                path.unlink()
                with self.subTest(resource=name, case='missing'):
                    with self.assertRaises((ValueError, OSError)):
                        prepare_app64.validate_runtime(root)
                path.write_bytes(b'')
                with self.subTest(resource=name, case='empty'):
                    with self.assertRaises(ValueError):
                        prepare_app64.validate_runtime(root)
                path.write_bytes(b'fixture')
            self.assertEqual(prepare_app64.validate_runtime(root)['required_data_count'], 4)

    def test_real_oracle_language_acceptance_is_not_just_xml_readback(self):
        harness = (ROOT / 'scripts/check_manager_session_gui.ps1').read_text(encoding='utf-8-sig')
        workflow = (ROOT / '.github/workflows/manager-session.yml').read_text(encoding='utf-8-sig')
        for term in ('[switch]$RussianOracle', 'function Assert-OracleLanguage',
                     'getextradata global GUI/LanguageID', 'AutomationElement',
                     "Assert-OracleLanguage 'ru'", "Assert-OracleLanguage 'C'",
                     'oracle_russian_captions_verified', 'oracle_english_captions_verified'):
            self.assertIn(term, harness)
        self.assertIn('-RussianOracle', workflow)
        reopen = source('ManagerSession.au3').split('Func _MS_Reopen(')[1].split('EndFunc')[0]
        self.assertNotIn('_MS_OpenLocalizedManager', reopen)

    def test_native_locale_and_compiled_gui_probes_are_registered(self):
        self.assertTrue((ROOT / 'tests/native/test_russian_completion.au3').is_file())
        workflow = (ROOT / '.github/workflows/ci.yml').read_text(encoding='utf-8-sig')
        self.assertIn('check_russian_gui.ps1', workflow)

if __name__ == '__main__':
    unittest.main()
