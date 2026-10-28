#!/usr/bin/env python3
"""Package ONLY a verified development launcher diagnostic preview.

This is neither a portable hypervisor release nor a VirtualBox redistributor.
The ZIP deliberately excludes Oracle binaries, drivers and inherited tools.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import sys
import zipfile

DOC_MEMBERS = ("LICENSE.md", "README.md", "README.ru.md", "CREDITS.md")
MEMBERS = DOC_MEMBERS + ("PREVIEW-NOT-A-HYPERVISOR.txt", "Portable-VirtualBox.exe", "Portable-VirtualBox-Setup.exe")
NOTICE = """Portable-VirtualBox development diagnostic preview

This is NOT a usable virtual machine hypervisor.
The ordinary user interface does not launch virtual machines,
install drivers, register Oracle services, or redistribute VirtualBox.
Normal use remains read-only except explicit portable-folder preparation,
saving the launcher language to data/launcher.ini, file-only Oracle
preparation from official HTTPS or a user-supplied pinned installer, and offline data/ backup
to a directory chosen by the user. Backup never installs VirtualBox.
An isolated GitHub Actions-only internal research command can exercise
Oracle VBoxSDS registration/cleanup; do not use it on a personal PC.

What works:
- RU/EN diagnostics, explicit saved language, completeness checks and built-in help
- concise About dialog; original license and consolidated notices included
- explicit first-run setup of data/.VirtualBox, data/Machines and logs
- preparation of app64 from the exact Oracle 7.2.22 package, obtained via official HTTPS or selected locally; no driver installation
- offline, copy-and-verify data/ backup without deleting any source files
- repeat setup without overwriting existing user files

The preparer can fetch the pinned Oracle 7.2.22 installer automatically or use a local copy.
Actual VM operation still requires a production-safe driver/service launcher.
The actual VM and signed driver CI experiments are NOT wired into
the regular launcher. No elevation is requested.

Do not copy this over an existing working VirtualBox installation.
Keep your own VM disks, snapshots and backups untouched.

Original license: LICENSE.md. Authors, reuse and external component notices: CREDITS.md.
"""

def _read_regular(path: Path, limit: int) -> bytes:
    if path.is_symlink():
        raise ValueError("Symbolic link forbidden: "+path.name)
    try:
        info = path.stat()
    except OSError as exc:
        raise ValueError("Missing required file: "+path.name) from exc
    if not stat.S_ISREG(info.st_mode) or info.st_size > limit or info.st_size == 0:
        raise ValueError("Invalid or excessive file: "+path.name)
    return path.read_bytes()


def _member(name: str, data: bytes) -> tuple[zipfile.ZipInfo, bytes]:
    entry = zipfile.ZipInfo(name, date_time=(2026, 10, 20, 0, 0, 0))
    entry.compress_type = zipfile.ZIP_DEFLATED
    entry.external_attr = 0o100644 << 16
    entry.create_system = 3
    return entry, data


def build_preview(root: Path, exe: Path, output: Path) -> dict:
    root, exe, output = Path(root), Path(exe), Path(output)
    if os.path.lexists(output) or os.path.lexists(output.with_suffix(".zip.sha256")):
        raise FileExistsError("Refusing to replace an existing preview artifact")
    if not output.parent.is_dir() or output.parent.is_symlink():
        raise ValueError("Existing regular output parent required")
    if exe.name != "Portable-VirtualBox_x64.exe":
        raise ValueError("Expected a compiled Portable-VirtualBox_x64.exe input")
    executable = _read_regular(exe, 64 * 1024 * 1024)
    if len(executable) < 10240 or executable[:2] != b"MZ":
        raise ValueError("Compiled launcher does not have a plausible PE header")
    # One-file non-admin offline preparer: the Python runtime is embedded in
    # this separately compiled binary. No Oracle installer/driver is bundled.
    setup = _read_regular(root / "build" / "Portable-VirtualBox-Setup.exe", 128 * 1024 * 1024)
    if len(setup) < 10240 or setup[:2] != b"MZ":
        raise ValueError("Compiled offline preparer has an invalid PE header")
    # Read every mandatory notice before creating the output: attribution is
    # required package content, not an optional README link.
    inputs = {name: _read_regular(root / name, 256 * 1024) for name in DOC_MEMBERS}
    inputs.update({
        "PREVIEW-NOT-A-HYPERVISOR.txt": NOTICE.encode("utf-8"),
        "Portable-VirtualBox.exe": executable,
        "Portable-VirtualBox-Setup.exe": setup,
    })
    with output.open("xb") as handle:
        with zipfile.ZipFile(handle, mode="w", compression=zipfile.ZIP_DEFLATED,
                             allowZip64=False) as archive:
            for name in sorted(inputs):
                header, data = _member(name, inputs[name])
                archive.writestr(header, data)
        handle.flush()
        os.fsync(handle.fileno())
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    with output.with_suffix(".zip.sha256").open("x", encoding="ascii") as handle:
        handle.write(checksum + "  " + output.name + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    return {"members": sorted(inputs), "sha256": checksum,
            "zip_size": output.stat().st_size, "oracle_payload_included": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    parser.add_argument("--repo", type=Path, default=root)
    parser.add_argument("--exe", type=Path,
                        default=root / "build" / "Portable-VirtualBox_x64.exe")
    parser.add_argument("--out", type=Path,
                        default=root / "build" / "Portable-VirtualBox-diagnostic-preview.zip")
    args = parser.parse_args()
    try:
        receipt = build_preview(args.repo, args.exe, args.out)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print("Diagnostic preview packaging failed: "+str(exc), file=sys.stderr)
        return 1
    print("Preview ZIP: "+str(args.out))
    print("SHA256: "+receipt["sha256"])
    print("Included: "+", ".join(receipt["members"]))
    print("No Oracle payload, old tool or VM runtime has been bundled.")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
