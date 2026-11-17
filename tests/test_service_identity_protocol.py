"""Executable TEST-ONLY identity protocol; never evidence of SCM semantics."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
SHELL = os.environ.get('PVBOX_TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
class ServiceIdentityProtocol(unittest.TestCase):
    @unittest.skipUnless(SHELL, 'PowerShell unavailable')
    def test_managed_generation_observation_protocol(self):
        r = subprocess.run([SHELL, '-NoProfile', '-File', str(ROOT/'tests/windows/ServiceIdentityObservationTests.ps1')], capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertIn('SERVICE_IDENTITY_MODEL_PASS', r.stdout)
        self.assertIn('native_calls=0 mutation_authorized=false', r.stdout)
    @unittest.skipUnless(SHELL and os.environ.get('PVBOX_TEST_NET48_REFERENCES'), 'net48 references unavailable')
    def test_model_and_native_draft_compile_against_net48(self):
        # Compiler harness can reside in original checkout while proposal is isolated.
        harness = Path(os.environ.get('PVBOX_TEST_FIXTURE_BUILD', ROOT/'tests/windows/NativeFixedFixtureBuild.ps1'))
        with tempfile.TemporaryDirectory() as tmp:
            for entry, files in [('ServiceIdentityObservationTests', ['ServiceIdentityObservationModel.cs','ServiceIdentityObservationTests.cs']), ('ServiceIdentityNativeTests', ['ServiceIdentityNativeTests.cs'])]:
                sources = ','.join("'"+str(ROOT/'tests/windows'/f).replace("'", "''")+"'" for f in files)
                command = ". '"+str(harness).replace("'", "''")+"'; Compile-FixedFixtureSources @("+sources+") '"+str(Path(tmp)/'fixture.exe')+"' 'PortableVBox.ServiceIdentityModel."+entry+"'"
                r = subprocess.run([SHELL,'-NoProfile','-Command',command],capture_output=True,text=True,timeout=60)
                self.assertEqual(r.returncode,0,r.stdout+r.stderr)
                (Path(tmp)/'fixture.exe').unlink()

    def test_native_execution_is_explicit_disposable_only_and_checks_evidence(self):
        wrapper = (ROOT/'tests/windows/check_service_identity_native.ps1').read_text()
        self.assertIn("$env:GITHUB_REPOSITORY -ne 'zlocorp/Portable-VirtualBox'", wrapper)
        self.assertIn("$env:RUNNER_ENVIRONMENT -ne 'github-hosted'", wrapper)
        self.assertIn('--disposable-scm-identity', wrapper)
        self.assertIn('SERVICE_IDENTITY_NATIVE_PASS', wrapper)
        self.assertIn('production_authority=false', wrapper)
        workflow = (ROOT/'.github/workflows/native-tests.yml').read_text()
        self.assertIn('./tests/windows/check_service_identity_native.ps1', workflow)
