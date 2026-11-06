#!/usr/bin/env python3
"""Ensure retired upstream binaries and language assets cannot return to the active tree.

No system changes or code execution. The old launcher source stays archived in
source/legacy and remains readable from Git history.
"""
from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RETIRED_DIRECTORIES = (
    "source/Aut2Exe",
    "source/i_data",
)
RETIRED_EXTENSIONS = {".exe", ".dll", ".sys", ".msi", ".cab", ".cat", ".com"}
LEGACY_BUILD_REFERENCES = (
    "source\\aut2exe",
    "source\\i_data",
    "7za.exe",
    "devcon",
    "snetcfg",
)


def problems(root: Path) -> list[str]:
    root = Path(root)
    findings: list[str] = []
    for relative in RETIRED_DIRECTORIES:
        path = root / relative
        if path.exists() or path.is_symlink():
            findings.append("Retired asset directory is still present: " + relative)
    source = root / "source"
    if source.is_dir():
        for item in source.rglob("*"):
            if item.is_file() and item.suffix.casefold() in RETIRED_EXTENSIONS:
                findings.append("Unexpected executable or installer in active source: "
                                + item.relative_to(root).as_posix())
    batch = root / "build.bat"
    if batch.is_file():
        contents = batch.read_text(encoding="utf-8-sig").lower().replace("/", "\\")
        for legacy_reference in LEGACY_BUILD_REFERENCES:
            if legacy_reference in contents:
                findings.append("Legacy executable dependency in build.bat: "
                                + legacy_reference)
        if "scripts\\build.ps1" not in contents:
            findings.append("build.bat is not delegating to the modern build.ps1")
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    findings = problems(args.root)
    if findings:
        for problem in findings:
            print("FAIL: " + problem)
        return 1
    print("PASS: no retired AutoIt, 7za, DevCon, SnetCfg, INI or splash assets "
          "in the active source tree; modern build entrypoint only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
