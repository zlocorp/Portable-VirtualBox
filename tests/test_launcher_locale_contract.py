"""Prevent untranslated/untested RU/EN strings in the active AutoIt launcher.

This is a source contract; native Windows CI still exercises real AutoIt
translates and GUI text independently. Legacy INI translations are archived.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source"
I18N = (SOURCE / "LauncherI18n.au3").read_text(encoding="utf-8-sig")
PREFLIGHT = (SOURCE / "HostPreflight.au3").read_text(encoding="utf-8-sig")


def function_body(text: str, name: str) -> str:
    pattern = r"(?ms)^Func " + re.escape(name) + r"\([^\n]*\)\n(.*?)^EndFunc\s*$"
    match = re.search(pattern, text)
    if match is None:
        raise AssertionError(f"Missing function {name}")
    return match.group(1)


def case_segments(body: str) -> dict[str, str]:
    starts = list(re.finditer(r'(?m)^\s*Case "([^"]+)"\s*$', body))
    result: dict[str, str] = {}
    for index, start in enumerate(starts):
        key = start.group(1)
        if key in result:
            raise AssertionError("Duplicate catalog case: " + key)
        finish = starts[index + 1].start() if index + 1 < len(starts) else len(body)
        result[key] = body[start.end():finish]
    return result


class LauncherLocalizations(unittest.TestCase):
    def test_all_used_keys_exist_and_are_tested_in_both_languages(self):
        cases = case_segments(function_body(I18N, "_LI"))
        native = (ROOT / "tests/native/test_launcher_i18n.au3").read_text(encoding="utf-8")
        match = re.search(r'Local \$keys = StringSplit\("([^"]+)", "\\|", 2\)', native)
        self.assertIsNotNone(match, "Missing native exhaustive key list")
        listed = match.group(1).split("|")
        self.assertEqual(len(listed), len(set(listed)), "Duplicate native catalog key")
        self.assertEqual(set(listed), set(cases), "Every catalog entry requires native RU/EN checks")
        used: set[str] = set()
        for file in SOURCE.glob("*.au3"):
            if file.name == "LauncherI18n.au3":
                continue
            data = file.read_text(encoding="utf-8-sig")
            used.update(re.findall(r'_LI\("([^"]+)"', data))
        self.assertTrue(used)
        self.assertEqual(used - set(cases), set(), "Missing translated UI keys")
        for key, body in cases.items():
            with self.subTest(key=key):
                self.assertRegex(body, r'If \$ru Then Return "[^"]+"')
                self.assertRegex(body, r'(?m)^\s*Return "[^"]+"')
                ru = re.search(r'If \$ru Then Return "([^"]+)"', body).group(1)
                en = re.search(r'(?m)^\s*Return "([^"]+)"', body).group(1)
                self.assertNotEqual(ru, en)

    def test_preflight_blockers_have_russian_translations(self):
        section = function_body(PREFLIGHT, "_PortablePreflightBlocker")
        other = function_body(PREFLIGHT, "_PortableReadOnlyPreflight")
        reasons = set(re.findall(r'Return "([^"]+)"', section + other)) - {""}
        translations = case_segments(function_body(I18N, "_LI_Blocker"))
        self.assertEqual(reasons - set(translations), set(), "Untranslated preflight reasons")
        for reason in reasons:
            with self.subTest(reason=reason):
                self.assertRegex(translations[reason], r'Return "[^"]+"')


if __name__ == "__main__":
    unittest.main()
