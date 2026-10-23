#!/usr/bin/env python3
"""Read-only VirtualBox.xml machine inventory for future migration planning.

Does NOT repair, rewrite or delete VM files; does not launch VirtualBox.
Default output suppresses UUIDs, VM names and filesystem paths.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from safe_files import windows_relative_parts
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
    try:
        parts = windows_relative_parts(value)
    except ValueError:
        return None
    base = profile.resolve()
    candidate = base.joinpath(*parts).resolve()
    if not candidate.is_relative_to(base):
        return None
    return candidate


class NoDoctype(ET.TreeBuilder):
    def doctype(self, name, pubid, system):
        raise ValueError("DTD/entity declarations are not accepted")


def inventory(xml: Path) -> list[Machine]:
    if not xml.is_file():
        raise ValueError("VirtualBox.xml was not found")
    with xml.open("rb") as stream:
        data = stream.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        raise ValueError("Unusually large VirtualBox.xml: refusing to parse")
    try:
        root = ET.fromstring(data, parser=ET.XMLParser(target=NoDoctype()))
    except ET.ParseError as exc:
        raise ValueError("Invalid VirtualBox.xml") from exc
    if root.tag not in ("VirtualBox", "{http://www.virtualbox.org/}VirtualBox"):
        raise ValueError("Not a VirtualBox registry")
    namespace = root.tag.removesuffix("VirtualBox")
    rows: list[Machine] = []
    seen: set[str] = set()
    for element in root.findall(f"{namespace}Global/{namespace}MachineRegistry/{namespace}MachineEntry"):
        uuid = element.get("uuid", "").strip()
        src = element.get("src", "")
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
        print("Inventory failed: " + (str(exc) if args.details or isinstance(exc, ValueError) else "filesystem access error"), file=sys.stderr)
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
