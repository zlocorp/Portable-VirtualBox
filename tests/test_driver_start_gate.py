"""Behavioral driver activation gates; no host services or drivers are touched."""
import os
import re
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = os.environ.get("PVBOX_TEST_POWERSHELL") or shutil.which("powershell") or shutil.which("pwsh")


class SdsDiagnosticSourceContracts(unittest.TestCase):
    """Read-only integration contracts, independent of PowerShell availability.

    These do not prove native capture, eventual worker completion, persistence
    success or a GitHub upload. The behavioral fixture executes only the actual
    collector's selected per-session body on owned local evidence.
    """

    def source(self, name):
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def unique_region(self, text, start, end):
        self.assertEqual(text.count(start), 1, start)
        region = text.split(start, 1)[1]
        self.assertIn(end, region)
        return region.split(end, 1)[0]

    def step(self, name):
        workflow = self.source(".github/workflows/windows-payload-cleanup-recovery.yml")
        start = "      - name: " + name + "\n"
        self.assertEqual(workflow.count(start), 1, start)
        return workflow.split(start, 1)[1].split("      - name: ", 1)[0]

    def test_diagnostics_reuse_only_original_prepare_observations(self):
        worker = self.source("scripts/privileged_session_worker.ps1")
        # A new diagnostic registry/SCM/process query in these regions fails
        # even if an exception guard would hide it at runtime.
        diagnostic_region = self.unique_region(
            worker, "function ConvertTo-SdsDiagnosticLines", "\n    if ($Action -eq 'Prepare') {")
        prepare = self.unique_region(worker, "\n    if ($Action -eq 'Prepare') {", "\n    } else {")
        code = re.sub(r"(?m)^\s*#.*$", "", diagnostic_region + prepare)
        for command in ("Get-Service", "Get-CimInstance", "Get-WmiObject", "Get-Process",
                        "Get-Item", "Get-ChildItem", "Get-ItemPropertyValue", "Invoke-Command",
                        "Start-Sleep", "sc.exe", "reg.exe"):
            self.assertNotRegex(code, r"(?i)(?<![\w-])" + re.escape(command) + r"(?![\w-])")
        self.assertEqual(len(re.findall(r"\bGet-ItemProperty\b", code)), 1)
        self.assertIn("$sds=Get-ItemProperty -LiteralPath 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\VBoxSDS' -ErrorAction Stop", prepare)
        self.assertEqual(len(re.findall(r"\bTest-Path\b", code)), 2)  # intent + original preflight
        self.assertIn("$sdsPreflight=Test-Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\VBoxSDS'", prepare)
        self.assertRegex(prepare, r"Run-Sds '--regservice' 'sds-register' \$sdsFacts\s+try \{\s+\$sds=Get-ItemProperty")
        run = self.unique_region(worker, "function Run-Sds(", "\ntry {")
        self.assertEqual(run.count("Start-Process "), 1)
        self.assertEqual(run.count("$p.Handle"), 1)
        self.assertEqual(run.count("$p.ExitCode"), 1)
        self.assertIn("$p.WaitForExit(30000)", run)
        self.assertIn("$p.WaitForExit()", run)

    def test_worker_embedding_retains_same_fixed_resource_route(self):
        names = ["privileged_session_worker.ps1", "vbox_sup_standalone.ps1",
                 "vbox_sup_start_owned.ps1", "vbox_sup_cleanup.ps1",
                 "vbox_sup_partial_cleanup.ps1", "vbox_sup_package_identity.ps1"]
        build = self.source("scripts/build_session_helper.ps1")
        helper = self.source("source/privilege/SessionHelper.cs")
        resources = re.findall(r"foreach\(\$name in @\(([^\n]+)\)\)", build)
        self.assertEqual(len(resources), 1)
        self.assertEqual(re.findall(r"'([^']+)'", resources[0]), names)
        self.assertIn("$arguments+=('/resource:'+(Join-Path $repo ('scripts\\'+$name))+','+$name)", build)
        scripts = re.findall(r"static readonly string\[\] Scripts=\{([^}]+)\}", helper)
        self.assertEqual(len(scripts), 1)
        self.assertEqual(re.findall(r'"([^"]+)"', scripts[0]), names)
        self.assertIn("Assembly.GetExecutingAssembly().GetManifestResourceStream(name)", helper)
        main = self.source("source/privilege/SessionHelper.Main.cs")
        self.assertIn('Quote(Path.Combine(working,"privileged_session_worker.ps1"))+" -Action "+args[0]', main)

    def test_prepare_streams_persist_before_rejection_after_worker_completion(self):
        main = self.source("source/privilege/SessionHelper.Main.cs")
        # This ordering is conditional on worker completion and successful
        # drains/writes. The parameterless wait can still delay all persistence.
        region = self.unique_region(main, "using(var process=new Process {StartInfo=info}) {", "CompleteCleanupWorker(")
        ordered = [
            "process.Start();var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();",
            "bool withinDeadline=process.WaitForExit(150000);",
            "if(!withinDeadline) process.WaitForExit();",
            "if(prepare) {",
            "journal.WorkerExited(",
            'WriteNew(Path.Combine(session,"helper-"+args[0]+"-"+evidenceId+".stdout.txt"),Encoding.UTF8.GetBytes(stdout.GetAwaiter().GetResult()));',
            'WriteNew(Path.Combine(session,"helper-"+args[0]+"-"+evidenceId+".stderr.txt"),Encoding.UTF8.GetBytes(stderr.GetAwaiter().GetResult()));',
            'if(!withinDeadline) throw new InvalidOperationException("Fixed effect exceeded deadline (child completed); inspect protected receipts");',
            'if(process.ExitCode!=0) throw new InvalidOperationException("Fixed effect worker rejected operation");',
        ]
        positions = []
        for fragment in ordered:
            self.assertEqual(region.count(fragment), 1, fragment)
            positions.append(region.index(fragment))
        self.assertEqual(positions, sorted(positions))

    def test_payload_collector_and_upload_always_run_with_strict_helper_cutoff(self):
        collect = self.step("Collect bounded evidence only, no executable or Oracle payload")
        upload = self.step("Upload evidence, not runnable experimental distribution")
        for step in (collect, upload):
            self.assertEqual(step.count("        if: always()\n"), 1)
        self.assertIn("        shell: pwsh\n        run: |\n", collect)
        self.assertIn("          $dest='results/manager-session'\n", collect)
        helper_selection = "            Get-ChildItem -LiteralPath $folder.FullName -File -Filter 'helper-*' | Where-Object { $_.Length -lt 262144 } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target }\n"
        self.assertEqual(collect.count(helper_selection), 1)
        self.assertEqual(collect.count("-Filter 'helper-*'"), 1)
        self.assertIn("        uses: actions/upload-artifact@", upload)
        self.assertIn("          path: results/manager-session/\n", upload)
        self.assertIn("          if-no-files-found: warn\n", upload)

    def test_export_diagnostics_are_not_consumed_as_admission_or_cleanup_authority(self):
        for name in ("source/privilege/SessionHelper.Main.cs", "source/privilege/SessionHelper.cs",
                     "scripts/build_session_helper.ps1", "scripts/manager_session_worker.ps1",
                     "scripts/vbox_sup_cleanup.ps1", "scripts/vbox_sup_partial_cleanup.ps1"):
            text = self.source(name)
            for diagnostic in ("PVBOX_SDS_DIAG_V1", "ConvertTo-SdsDiagnosticLines",
                               "Write-SdsRegistrationDiagnostics"):
                self.assertNotIn(diagnostic, text, name)


@unittest.skipUnless(POWERSHELL, "PowerShell required for isolated activation gate tests")
class DriverStartGateTests(unittest.TestCase):
    def run_gate(self, target):
        result = subprocess.run(
            [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
             str(ROOT / "tests/windows/check_driver_start_gate.ps1"), "-Repository", str(ROOT), "-Target", target],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"PASS {target} driver start gate", result.stdout)

    def test_failed_stopped_recovery_requires_exact_known_state(self):
        result = subprocess.run(
            [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
             str(ROOT / "tests/windows/check_failed_start_recovery.ps1"), "-Repository", str(ROOT)],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS failed-stopped recovery", result.stdout)

    def test_activation_failure_preserves_evidence_and_throws(self):
        self.run_gate("Start")

    def test_privileged_prepare_requires_confirmed_start_before_sds(self):
        self.run_gate("Privileged")

    def test_manager_prepare_requires_confirmed_start_before_oracle(self):
        self.run_gate("Manager")

if __name__ == "__main__":
    unittest.main()
