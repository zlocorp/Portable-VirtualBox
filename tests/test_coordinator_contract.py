"""Bounded source guardrails; native tests establish runtime behavior separately."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def active(path: str) -> str:
    source = (ROOT / path).read_text(encoding="utf-8-sig")
    return "\n".join(line for line in source.splitlines() if not line.lstrip().startswith(";"))


class CoordinatorContractTests(unittest.TestCase):
    def test_no_system_changing_adapter_is_enabled(self):
        source = active("source/LifecycleCoordinator.au3")
        self.assertNotRegex(source, r"(?i)\b(?:Run|RunWait|ProcessClose|RegWrite|RegDelete|FileDelete)\s*\(")
        calls = re.findall(r'DllCall\("[^"\n]+",\s*"[^"\n]+",\s*"([^"\n]+)"', source)
        self.assertEqual(calls, ["GetFileAttributesW"])
        self.assertIn("_PJ_SaveNew($j, $path)", source)

    def test_preview_does_not_dispatch_coordinator_effects(self):
        source = active("source/Portable-VirtualBox.au3")
        self.assertNotIn("LifecycleCoordinator.au3", source)
        self.assertNotRegex(source, r"_PC_(?:New|Acquire|ReleaseNext)\s*\(")
        self.assertIn("Exit 2", source)

    def test_query_normalizer_does_not_issue_capabilities(self):
        source = active("source/CoordinationObservation.au3")
        assignments = re.findall(r'\$r\["ticket"\]\s*=\s*([^\r\n]+)', source)
        self.assertEqual(assignments, ['""'])
        self.assertNotIn("_PC_Acquire(", source)
        self.assertNotRegex(source, r"(?i)\b(?:Run|RunWait|ProcessClose|RegWrite|RegDelete)\s*\(")


if __name__ == "__main__":
    unittest.main()
