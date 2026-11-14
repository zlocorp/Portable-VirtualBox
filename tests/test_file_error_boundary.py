"""File observations must retain their native failure reason across GUI callbacks."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBES = {
    "PortableProfile.au3": "_PP_DirectoryState",
    "PortableApp.au3": "_PA_FileState",
    "LauncherSettings.au3": "_LS_FileState",
    "PortableDataBackup.au3": "_PBK_PathState",
    "PortableVmInventory.au3": "_PVI_PathState",
}

class FileErrorBoundaryContract(unittest.TestCase):
    def test_paired_attribute_call_and_last_error_capture(self):
        for source, function in PROBES.items():
            with self.subTest(source=source):
                text = (ROOT / "source" / source).read_text(encoding="utf-8-sig")
                body = text.split("Func " + function + "(", 1)[1].split("EndFunc", 1)[0]
                self.assertRegex(body, r'(?s)DllCall\("kernel32\.dll", "dword", "GetFileAttributesW", "wstr", \$path\),\s*\$callError = @error,\s*_\s*\$last = DllCall\("kernel32\.dll", "dword", "GetLastError"\),\s*\$lastError = @error')
                self.assertIn('"SetLastError", "dword", 0', body)
                self.assertIn('If $callError Or Not IsArray($a) Then Return -1', body)
                self.assertIn('If $lastError Or Not IsArray($last) Then Return -1', body)

    def test_native_callback_regression_is_in_harness_list(self):
        path = ROOT / "tests/native/test_file_error_boundary.au3"
        self.assertTrue(path.exists())
        text = path.read_text(encoding="utf-8-sig")
        for function in PROBES.values():
            self.assertIn(function + "(", text)
        self.assertIn('AdlibRegister("DisturbFileError", 1)', text)
        self.assertIn('AdlibUnRegister("DisturbFileError")', text)

if __name__ == '__main__':
    unittest.main()
