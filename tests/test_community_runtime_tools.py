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
        self.assertIn('_WinObsServiceSnapshot(', source)
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

    def test_snapshot_query_preserves_strict_runtime_boundary(self):
        probe = (ROOT / 'source/WindowsServiceProbe.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Return _WinObsServiceQuery($name, True)', probe)
        self.assertIn('Return _WinObsServiceQuery($name, False)', probe)
        self.assertIn('If $stable Then $second = _WinObsServiceRead($service, $name)', probe)
        self.assertIn('Return _WinObsServiceResolve($first, $second, $stable)', probe)
        self.assertIn('_WinObsServiceStable($first, $second)', probe)
        callers = {p.relative_to(ROOT).as_posix() for p in (ROOT / 'source').rglob('*.au3')
                   if '_WinObsServiceSnapshot(' in p.read_text(encoding='utf-8-sig')}
        self.assertEqual(callers, {'source/WindowsServiceProbe.au3', 'source/HostDiagnostics.au3'})

    def test_shared_service_inventory_and_stable_json(self):
        preflight = (ROOT / 'source/HostPreflight.au3').read_text(encoding='utf-8-sig')
        source = (ROOT / 'source/HostDiagnostics.au3').read_text(encoding='utf-8-sig')
        self.assertIn('Func _PortableServiceNames()', preflight)
        self.assertIn('Local $names = _PortableServiceNames()', preflight)
        self.assertIn('_PortableServiceNames()', source)
        self.assertNotIn('Local $names[10]', source)
        self.assertIn('Func _PortableServiceJson(ByRef $rows)', source)
        serializer = source.split('Func _PortableServiceJson(ByRef $rows)', 1)[1].split('EndFunc', 1)[0]
        for key in ('"schema"', '"services"', '"observation"', '"state"', '"win32_error"', '"ownership"'):
            self.assertIn(key, serializer)
        for forbidden in ('_WinObsService', '_LI_Language', '"image"', '"account"'):
            self.assertNotIn(forbidden, serializer)
        self.assertIn('UBound($rows, 0) <> 1', serializer)

    def test_compiled_service_cli_is_wired_and_rejects_extra_arguments(self):
        main = (ROOT / 'source/Portable-VirtualBox.au3').read_text(encoding='utf-8-sig')
        for command in ('--diagnose-services', '--diagnose-services-json'):
            self.assertIn('Case "' + command + '"', main)
            body = main.split('Case "' + command + '"', 1)[1].split('Case ', 1)[0]
            self.assertIn('If $CmdLine[0] <> $iFirst Then Exit 64', body)
        self.assertIn('check_service_diagnostics.ps1', (ROOT / '.github/workflows/ci.yml').read_text())
        native = (ROOT / 'tests/native/test_service_diagnostics.au3').read_text(encoding='utf-8-sig')
        for call in ('_WinObsServiceResolve(', '_PortableServiceJson(', '_WinObsServiceSnapshot('):
            self.assertIn(call, native)
