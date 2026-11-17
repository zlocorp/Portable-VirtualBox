"""VirtualBox.xml inventory tests using disposable, namespaced XML fixtures."""
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from vm_inventory import inventory, summary  # noqa: E402


def doc(registry: str) -> str:
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<VirtualBox xmlns="http://www.virtualbox.org/" version="1.12-windows">'
            '<Global><MachineRegistry>' + registry
            + '</MachineRegistry></Global></VirtualBox>')


class VirtualBoxInventoryTests(unittest.TestCase):
    def test_existing_cyrillic_machine_is_local(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / "Machines" / "Тестовая VM" / "Тестовая VM.vbox"
            path.parent.mkdir(parents=True)
            path.write_text("test", encoding="utf-8")
            xml = root / "VirtualBox.xml"
            xml.write_text(doc('<MachineEntry uuid="{1234}" src="Machines\\Тестовая VM\\Тестовая VM.vbox"/>'),
                           encoding="utf-8")
            rows = inventory(xml)
            self.assertEqual(summary(rows), dict(machines=1, duplicate_or_missing_uuids=0,
                                                 external_or_unsafe_paths=0, missing_local_files=0))

    def test_rejects_external_paths_and_uuid_duplicates_without_modifying_files(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            xml = root / "VirtualBox.xml"
            content = doc(
                '<MachineEntry uuid="{a}" src="D:\\Other\\box.vbox"/>'
                '<MachineEntry uuid="{a}" src="..\\escape.vbox"/>'
                '<MachineEntry uuid="{b}" src="Machines/not-found.vbox"/>')
            xml.write_text(content, encoding="utf-8")
            before = xml.read_bytes()
            stats = summary(inventory(xml))
            self.assertEqual(stats["machines"], 3)
            self.assertEqual(stats["external_or_unsafe_paths"], 2)
            self.assertEqual(stats["duplicate_or_missing_uuids"], 1)
            self.assertEqual(stats["missing_local_files"], 1)
            self.assertEqual(xml.read_bytes(), before)

    def test_rejects_dtd_and_malformed_xml(self):
        with TemporaryDirectory() as folder:
            xml = Path(folder) / "VirtualBox.xml"
            for invalid in ("<!DOCTYPE x [<!ENTITY x 'unsafe'>]>" + doc(""),
                            "<VirtualBox><broken",
                            "<NotVirtualBox/>"):
                with self.subTest(invalid=invalid):
                    xml.write_text(invalid, encoding="utf-8")
                    with self.assertRaises(ValueError):
                        inventory(xml)


if __name__ == "__main__":
    unittest.main()
