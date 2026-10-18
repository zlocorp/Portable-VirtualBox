#!/usr/bin/env python3
"""Read-only VirtualBox.xml machine inventory for future migration planning.

Does NOT repair, rewrite or delete VM files; does not launch VirtualBox.
Default output suppresses UUIDs, VM names and filesystem paths.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
import re
import sys
import xml.etree.ElementTree as ET


@dataclass(frozen=True)
class Machine:
    uuid: str
    src: str
    inside_profile: bool
    file_present: bool
    duplicate_uuid: bool


def _tag_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _safe_machine_path(profile: Path, value: str) -> Path | None:
    if not value or "\x00" in value:
        return None
    windows = PureWindowsPath(value)
    if windows.is_absolute() or windows.drive or windows.root:
        return None
    parts = value.replace("\\", "/").split("/")
    if any(p in ("", ".", "..") for p in parts):
        return None
    base = profile.resolve()
    candidate = base.joinpath(*parts).resolve()
    if not candidate.is_relative_to(base):
        return None  # junction/symlink escapes also rejected on current OS
    return candidate


def inventory(xml: Path) -> list[Machine]:
    if not xml.is_file():
        raise ValueError("VirtualBox.xml was not found")
    if xml.stat().st_size > 4 * 1024 * 1024:
        raise ValueError("Unusually large VirtualBox.xml: refusing to parse")
    data = xml.read_bytes()
    if re.search(rb"<!\s*(?:DOCTYPE|ENTITY)\b", data, re.IGNORECASE):
        raise ValueError("DTD/entity declarations are not accepted")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise ValueError("Invalid VirtualBox.xml") from exc
    if _tag_name(root.tag) != "VirtualBox":
        raise ValueError("Not a VirtualBox registry")
    rows: list[Machine] = []
    seen: set[str] = set()
    for element in root.iter():
        if _tag_name(element.tag) != "MachineEntry":
            continue
        uuid = element.get("uuid", "").strip()
        src = element.get("src", "").strip()
        duplicate = not uuid or uuid.casefold() in seen
        if uuid:
            seen.add(uuid.casefold())
        candidate = _safe_machine_path(xml.parent, src)
        rows.append(Machine(
            uuid=uuid,
            src=src,
            inside_profile=candidate is not None,
            file_present=candidate.is_file() if candidate is not None else False,
            duplicate_uuid=duplicate,
        ))
    return rows


def summary(rows: list[Machine]) -> dict[str, int]:
    return {
        "machines": len(rows),
        "duplicate_or_missing_uuids": sum(m.duplicate_uuid for m in rows),
        "external_or_unsafe_paths": sum(not m.inside_profile for m in rows),
        "missing_local_files": sum(m.inside_profile and not m.file_present for m in rows),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml", type=Path, help="Path to an existing VirtualBox.xml")
    parser.add_argument("--details", action="store_true",
                        help="Explicitly show private UUIDs and source paths")
    args = parser.parse_args()
    try:
        rows = inventory(args.xml)
    except (OSError, ValueError) as exc:
        print("Inventory failed: " + str(exc), file=sys.stderr)
        return 2
    for key, value in summary(rows).items():
        print("{}: {}".format(key, value))
    if args.details:
        for machine in rows:
            status = "LOCAL" if machine.inside_profile else "EXTERNAL_OR_UNSAFE"
            if machine.inside_profile and not machine.file_present:
                status = "MISSING_LOCAL_FILE"
            if machine.duplicate_uuid:
                status += "+DUPLICATE_UUID"
            print("{} | {} | {}".format(status, machine.uuid, machine.src))
    print("Read-only inventory: no files modified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
