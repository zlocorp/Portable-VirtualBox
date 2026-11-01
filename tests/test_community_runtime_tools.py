"""Source/package guards supplement real native and Windows behavioral tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CommunityRuntimeTools(unittest.TestCase):
    def test_service_diagnostics_share_query_only_observations(self):
        source = (ROOT / 'source/HostDiagnostics.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _PortableServiceState(', source)
        self.assertIn('Func _PortableServiceCollect(', source)
        self.assertIn('Func _PortableServiceText(', source)
        self.assertIn('_WinObsService(', source)
        for forbidden in ('ObjCreate(', 'ProcessClose(', 'RegWrite(', 'Run(', 'RunWait(', '#RequireAdmin'):
            self.assertNotIn(forbidden, source)

    def test_manager_displays_services_without_making_them_cleanup_authority(self):
        window = (ROOT / 'source/ManagerWindow.au3').read_text(encoding='utf-8-sig')
        self.assertIn('_PortableServiceText(', window)
        self.assertIn('$serviceTick', window)
        session = (ROOT / 'source/ManagerSession.au3').read_text(encoding='utf-8-sig')
        self.assertNotIn('_PortableServiceState(', session)
        self.assertIn('_CG_Acquire(', session)
        self.assertIn('_CG_SetReady(', session)

    def test_cli_is_build_paired_and_not_in_diagnostic_package(self):
        path = ROOT / 'source/cli/PortableCli.cs'
        self.assertTrue(path.is_file(), 'Medium portable CLI adapter is missing')
        source = path.read_text(encoding='utf-8') + (path.parent / 'PortableCli.Files.cs').read_text(encoding='utf-8')
        for required in ('PinnedBuild.FrontendSha256', 'PinnedBuild.InventorySha256', 'TokenFacts.ReadHandle',
                         'Mutex.OpenExisting', 'VBOX_USER_HOME', 'UseShellExecute=false', 'WaitForExit',
                         'controller_created_filetime'):
            self.assertIn(required, source)
        for forbidden in ('Verb="runas"', 'Process.Kill', 'cmd.exe', 'sc.exe'):
            self.assertNotIn(forbidden, source)
        package = (ROOT / 'scripts/package_alpha.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('VBoxManagePortable.exe', package)
        self.assertIn('VBoxManage.cmd', package)
        preview = (ROOT / 'scripts/package_preview.py').read_text(encoding='utf-8')
        self.assertNotIn('VBoxManagePortable.exe', preview)
        self.assertNotIn('VBoxManage.cmd', preview)

    def test_native_and_actual_helper_tests_are_wired(self):
        native = ROOT / 'tests/native/test_cli_gate.au3'
        self.assertTrue(native.is_file(), 'Native cross-process gate test missing')
        behavior = ROOT / 'tests/windows/check_portable_cli.ps1'
        self.assertTrue(behavior.is_file(), 'Executable C# argument/binding tests missing')
        workflow = (ROOT / '.github/workflows/native-tests.yml').read_text(encoding='utf-8')
        self.assertIn('check_portable_cli.ps1', workflow)
        real = (ROOT / 'tests/windows/check_helper_boundary.ps1').read_text(encoding='utf-8')
        self.assertIn('VBoxManagePortable.exe', real)
        self.assertIn('portable_cli_verified', real)
