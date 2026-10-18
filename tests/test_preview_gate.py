"""Guardrail: no legacy Windows-side effects are reachable from the preview CLI."""
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "source" / "Portable-VirtualBox.au3").read_text(encoding="utf-8-sig")


class PreviewEntryPointTests(unittest.TestCase):
    def test_guard_before_any_legacy_runtime(self):
        gate = SOURCE.split("; END DEVELOPMENT SAFETY GATE")[0]
        self.assertIn('Case "--diagnose"', gate)
        self.assertIn('Case "--selftest"', gate)
        self.assertIn("Exit 2", gate)
        self.assertNotIn("RunWait(", gate)
        self.assertNotIn("RegWrite(", gate)
        self.assertNotIn("sc delete", gate)
        self.assertNotIn("ProcessClose(", gate)
        self.assertNotIn("FileDelete(", gate)

    def test_old_unscoped_privilege_is_inactive(self):
        uncommented = [line.strip() for line in SOURCE.splitlines() if not line.lstrip().startswith(";")]
        self.assertNotIn("#RequireAdmin", uncommented)


if __name__ == "__main__":
    unittest.main()
