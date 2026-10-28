"""Portable unit tests: no admin rights, VirtualBox or Windows drivers required."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from audit_source import inspect, markdown  # noqa: E402


class SourceAuditTests(unittest.TestCase):
    def test_recognizes_unsafe_operations(self):
        fixture = """
RunWait ("cmd /c taskkill /im msiexec.exe /f", @ScriptDir, @SW_HIDE)
FileCopy ("a.dll", @SystemDir, 9)
FileDelete (@SystemDir & "\\msvcrt.dll")
RunWait ("sc delete VBoxSDS", @ScriptDir)
ProcessClose ("VBoxSDS.exe")
RunWait ("cmd /c set VBOX_USER_HOME=%CD%\\VM & .\\VBoxManage.exe")
FileWrite ($file, StringReplace ($content, $old, $new))
"""
        names = {name for name, _, _ in inspect(fixture)}
        self.assertIn("installer-process-kill", names)
        self.assertIn("system-directory-copy", names)
        self.assertIn("system-directory-delete", names)
        self.assertIn("service-command", names)
        self.assertIn("name-only-process-close", names)
        self.assertIn("legacy-cmd-environment", names)
        self.assertIn("xml-string-rewrite", names)

    def test_ignores_comment_lines_and_does_not_execute(self):
        self.assertEqual(inspect('; RunWait ("sc delete VBoxSDS")\n'), [])
        self.assertEqual(inspect('ConsoleWrite("safe")\n'), [])

    def test_report_contains_locations(self):
        report = markdown([("service-command", 12, "sc stop VBoxDRV")], "launcher.au3")
        self.assertIn("| service-command | 12 |", report)


if __name__ == "__main__":
    unittest.main()
