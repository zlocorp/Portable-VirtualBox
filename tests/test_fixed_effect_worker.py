"""Production owner managed behavior and Framework compilation, not native proof."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")

class FixedEffectWorker(unittest.TestCase):
    @unittest.skipUnless(PWSH, "PowerShell unavailable")
    def test_actual_managed_reader_and_interrupted_join(self):
        result = subprocess.run([PWSH, "-NoProfile", "-File", str(ROOT / "tests/windows/check_fixed_effect_worker_managed.ps1")],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("FIXED_EFFECT_MANAGED_PASS assertions=121", result.stdout)

    @unittest.skipUnless(PWSH and os.environ.get("PVBOX_TEST_NET48_REFERENCES"), "net48 compiler references unavailable")
    def test_exact_native_fixture_compiles_against_net48(self):
        with tempfile.TemporaryDirectory() as temp:
            output = str(Path(temp) / "owner.exe").replace("'", "''")
            command = (". ./tests/windows/NativeFixedFixtureBuild.ps1; "
                       "Compile-FixedFixtureSources @((Resolve-Path source/privilege/FixedEffectWorker.cs).Path,"
                       "(Resolve-Path tests/windows/FixedEffectWorkerNativeTests.cs).Path) '"
                       + output + "' 'PortableVBox.FixedEffectWorkerNativeTests'")
            result = subprocess.run([PWSH, "-NoProfile", "-Command", command],
                                    cwd=ROOT, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_closed_sds_wrapper_preserves_distinct_environment_and_deadlines(self):
        owner = (ROOT / "source/privilege/FixedEffectWorker.cs").read_text()
        self.assertIn("return RunCore(info,image,150000,false)", owner)
        self.assertIn("internal static FixedEffectWorker RunSds(string image,bool unregister,int timeoutSeconds)", owner)
        self.assertIn('unregister?"--unregservice":"--regservice"', owner)
        self.assertIn("return RunCore(info,image,checked((uint)timeoutSeconds*1000),true)", owner)
        self.assertIn("if(!inheritEnvironment)environment=Marshal.StringToHGlobalUni(BuildEnvironment(info))", owner)
        self.assertNotIn("public static FixedEffectWorker", owner)

    def test_parent_transports_only_verified_store_locator(self):
        main = (ROOT / "source/privilege/SessionHelper.Main.cs").read_text()
        self.assertIn('info.EnvironmentVariables["ProgramData"]=commonData;', main)
        self.assertIn('info.EnvironmentVariables["RUNNER_TEMP"]=store;', main)
        self.assertNotIn('ALLUSERSPROFILE', main)
        self.assertIn('string store=Path.Combine(commonData,', main)
        self.assertLess(main.index("String.IsNullOrEmpty(commonData)"), main.index("string store=Path.Combine(commonData,"))
        owner = (ROOT / "source/privilege/FixedEffectWorker.cs").read_text()
        self.assertNotIn('ALLUSERSPROFILE', owner)

    def test_exit_is_persisted_before_capture_and_success_gates(self):
        main = (ROOT / "source/privilege/SessionHelper.Main.cs").read_text()
        self.assertIn("exit_code_known=process.ExitCodeKnown", main)
        prepare = main[main.index("using(var process=FixedEffectWorker.Run(info))"):main.index("CompleteCleanupWorker(withinDeadline")]
        self.assertLess(prepare.index("journal.WorkerExited("), prepare.index("stdout.GetAwaiter().GetResult()"))
        self.assertLess(prepare.index("process.VerifyImageObservation()"), prepare.index("if(process.ExitCode!=0)"))
        owner = (ROOT / "source/privilege/FixedEffectWorker.cs").read_text()
        self.assertIn("WaitForSingleObject(original.Process,deadline)", owner)
        self.assertIn("if(wait==258)wait=WaitForSingleObject(original.Process,0xffffffff)", owner)
        self.assertNotIn("TerminateProcess", owner)
        self.assertIn("catch(ThreadInterruptedException)", owner)
        self.assertIn("if(created && (!stdout.Eof||!stderr.Eof))RetainUnknown()", owner)

if __name__ == "__main__":
    unittest.main()
