"""Guardrails for the compiled first-run setup in the ordinary launcher."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]

class PortableSetupWiring(unittest.TestCase):
    def read(self,name):return (ROOT/name).read_text(encoding='utf-8-sig')

    def test_normal_gui_connects_offline_preparer_without_elevation(self):
        gui=self.read('source/LauncherGui.au3')
        self.assertIn('FileOpenDialog(_LI("setup.choose")',gui)
        self.assertIn('_PAS_Start(@ScriptDir, $installer)',gui)
        self.assertIn('_PAS_Complete(@ScriptDir, $setupWorker["exit_code"])',gui)
        self.assertNotIn('RunAs(',self.read('source/PortableAppSetup.au3'))
        self.assertNotIn('ShellExecuteExW',self.read('source/PortableAppSetup.au3'))
        self.assertNotIn('ProcessClose(',self.read('source/PortableAppSetup.au3'))

    def test_exclusive_existing_app64_and_foreign_process_refusal(self):
        s=self.read('source/PortableAppSetup.au3')
        for statement in ('_PP_DirectoryState($root & "\\app64") <> 0',
                          '_PortableCountExistingServices() <> 0',
                          '_PortableCountVirtualBoxProcesses() <> 0',
                          'Portable-VirtualBox-Setup.exe',
                          '_MP_Start(',
                          'app64\\.prepared.json'):
            self.assertIn(statement,s)

    def test_official_download_without_python_on_the_user_pc(self):
        gui=self.read('source/LauncherGui.au3')
        self.assertIn('_PAS_StartDownload(@ScriptDir)',gui)
        self.assertIn('setup.source',gui)
        self.assertIn('_PAS_ProgressText($setupWorker)',gui)
        self.assertIn('_PAS_StartDownload(@ScriptDir, True)',gui)
        adapter=self.read('source/PortableAppSetup.au3')
        self.assertIn('Func _PAS_StartDownload(',adapter)
        self.assertIn('Func _PAS_CanPrepareRoot(',adapter)
        self.assertIn('Func _PAS_RunDownload(',adapter)
        self.assertIn('Return _PAS_Wait(',adapter)
        entry=self.read('source/Portable-VirtualBox.au3')
        self.assertIn('Case "--download-app64"',entry)
        self.assertIn('_PAS_RunDownload(@ScriptDir)',entry)
        downloader=self.read('scripts/portable_prepare.py')
        self.assertIn('OFFICIAL_URL = "https://download.virtualbox.org/virtualbox/"',downloader)
        self.assertIn('download_verified',downloader)
        self.assertIn('class ProgressFile:',downloader)
        self.assertIn('progress=lambda done, total:',downloader)
        self.assertIn('TemporaryDirectory(prefix=".vbox-official-", dir=root)',downloader)

    def test_public_cli_not_hidden_ci_mode(self):
        entry=self.read('source/Portable-VirtualBox.au3')
        self.assertIn('Case "--prepare-app64"',entry)
        self.assertIn('_PAS_Run(@ScriptDir,',entry)
        self.assertIn('--prepare-app64 OFFICIAL_INSTALLER',entry)

    def test_packaged_helper_is_nonadmin_not_oracle_or_system_worker(self):
        build=self.read('scripts/build_portable_setup.ps1')
        self.assertIn('pyinstaller==',build)
        self.assertIn('Portable-VirtualBox-Setup.exe',build)
        package=self.read('scripts/package_preview.py')
        self.assertIn('"Portable-VirtualBox-Setup.exe"',package)
        self.assertNotIn('VBoxSup.sys',package)

if __name__=='__main__':unittest.main()
