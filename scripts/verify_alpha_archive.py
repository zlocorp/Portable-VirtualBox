#!/usr/bin/env python3
"""Verify a non-release ALPHA ZIP against the exact locally built executables.

SHA256SUMS is an integrity manifest, not a publisher signature. Verify it
independently; reject extra, renamed, duplicate, symlink and oversized members.
This tool neither extracts nor executes archive members.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import sys
from zipfile import ZipFile, BadZipFile

REQUIRED_FILES = frozenset({
    'Portable-VirtualBox.exe', 'Portable-VirtualBox-Setup.exe',
    'Portable-VirtualBox-Helper-Alpha.exe', 'VBoxManagePortable.exe',
    'VBoxManage.cmd', 'README.md', 'README.ru.md', 'LICENSE.md',
    'CREDITS.md', 'ALPHA-TEST-ONLY.md',
})
REQUIRED_SOURCE_PATHS = {
    'Portable-VirtualBox.exe': 'build/Portable-VirtualBox_x64.exe',
    'Portable-VirtualBox-Setup.exe': 'build/Portable-VirtualBox-Setup.exe',
    'Portable-VirtualBox-Helper-Alpha.exe': 'build/Portable-VirtualBox-Helper-Alpha.exe',
    'VBoxManagePortable.exe': 'build/VBoxManagePortable.exe',
    'VBoxManage.cmd': 'build/VBoxManage.cmd',
    'README.md': 'README.md',
    'README.ru.md': 'README.ru.md',
    'LICENSE.md': 'LICENSE.md',
    'CREDITS.md': 'CREDITS.md',
    'ALPHA-TEST-ONLY.md': 'docs/ALPHA-WINDOWS-TEST.md',
}
MANIFEST = 'SHA256SUMS.txt'
MAX_ARCHIVE_BYTES = 300 * 1024 * 1024
MAX_MEMBER_BYTES = 128 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024
MAX_MANIFEST_BYTES = 4096
LINE = re.compile(r'([0-9a-f]{64})  ([A-Za-z0-9.-]+)')


def hash_file(path: Path) -> str:
    path = Path(path)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
        raise ValueError('Missing, empty or linked package input: ' + str(path))
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify(archive: Path, frontend: Path, helper: Path, source_root: Path) -> dict:
    archive = Path(archive)
    info = archive.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_ARCHIVE_BYTES:
        raise ValueError('Archive is absent, linked, empty or too large')
    expected_pair = {
        'Portable-VirtualBox.exe': hash_file(frontend),
        'Portable-VirtualBox-Helper-Alpha.exe': hash_file(helper),
    }
    source_root = Path(source_root).resolve(strict=True)
    if not source_root.is_dir() or set(REQUIRED_SOURCE_PATHS) != REQUIRED_FILES:
        raise ValueError('Missing trusted checkout or incomplete expected inputs')
    source_checksums: dict[str, str] = {}
    for name, relative in REQUIRED_SOURCE_PATHS.items():
        path = source_root / relative
        parent = path.parent
        while parent != source_root:
            if parent.is_symlink() or not parent.is_dir():
                raise ValueError('Linked or missing source component: ' + str(parent))
            parent = parent.parent
        source_checksums[name] = hash_file(path)
    for name, expected in expected_pair.items():
        if source_checksums[name] != expected:
            raise ValueError('Paired executable does not match its source checkout')
    checksums: dict[str, str] = {}
    manifest: bytes | None = None
    required_names = REQUIRED_FILES | {MANIFEST}
    try:
        with ZipFile(archive) as package:
            entries = package.infolist()
            names = [member.filename for member in entries]
            if len(entries) != len(required_names) or set(names) != required_names or len(set(names)) != len(entries):
                raise ValueError('Package entries differ from exact non-release allowlist')
            if len({name.casefold() for name in names}) != len(names):
                raise ValueError('Case-colliding archive entries')
            total = 0
            for member in entries:
                mode = (member.external_attr >> 16) & 0o170000
                if (member.is_dir() or mode == stat.S_IFLNK or
                    (mode not in (0, stat.S_IFREG)) or member.flag_bits & 1):
                    raise ValueError('Directory, symlink, special or encrypted archive entry')
                limit = MAX_MANIFEST_BYTES if member.filename == MANIFEST else MAX_MEMBER_BYTES
                if not 0 < member.file_size <= limit or member.compress_size <= 0:
                    raise ValueError('Empty or oversized archive member')
                total += member.file_size
                if total > MAX_TOTAL_BYTES:
                    raise ValueError('Archive extracted size exceeds bound')
                digest = hashlib.sha256()
                remaining = member.file_size
                chunks = []
                with package.open(member, 'r') as stream:
                    while remaining:
                        chunk = stream.read(min(remaining, 1024 * 1024))
                        if not chunk:
                            raise ValueError('Truncated archive member')
                        digest.update(chunk)
                        if member.filename == MANIFEST:
                            chunks.append(chunk)
                        remaining -= len(chunk)
                    if stream.read(1):
                        raise ValueError('Decompressed member exceeds declared size')
                checksums[member.filename] = digest.hexdigest()
                if member.filename == MANIFEST:
                    manifest = b''.join(chunks)
    except (BadZipFile, EOFError, OSError) as exc:
        raise ValueError('Unreadable or invalid ZIP archive') from exc
    if manifest is None:
        raise ValueError('Missing integrity manifest')
    try:
        decoded = manifest.decode('ascii')
    except UnicodeError as exc:
        raise ValueError('Manifest is not ASCII') from exc
    rows = decoded.splitlines(keepends=True)
    if len(rows) != len(REQUIRED_FILES) or not decoded.endswith('\n'):
        raise ValueError('Manifest length or final terminator invalid')
    found: dict[str, str] = {}
    order = []
    for row in rows:
        if not row.endswith('\n'):
            raise ValueError('Manifest row is incomplete')
        line = row.rstrip('\r\n')
        matched = LINE.fullmatch(line)
        if matched is None:
            raise ValueError('Unexpected checksum row')
        digest, name = matched.groups()
        if name not in REQUIRED_FILES or name in found:
            raise ValueError('Unknown or duplicate checksum target')
        found[name] = digest
        order.append(name)
    if set(found) != REQUIRED_FILES or order != sorted(order):
        raise ValueError('Checksum manifest does not match sorted allowlist')
    for name, digest in found.items():
        if checksums.get(name) != digest:
            raise ValueError('Archive member SHA-256 mismatch: ' + name)
    for name, expected in source_checksums.items():
        if checksums[name] != expected:
            raise ValueError('Archive member differs from trusted build/checkout: ' + name)
    return {
        'entries': len(required_names),
        'verified_members': len(source_checksums),
        'archive_sha256': hash_file(archive),
        'frontend_sha256': expected_pair['Portable-VirtualBox.exe'],
        'helper_sha256': expected_pair['Portable-VirtualBox-Helper-Alpha.exe'],
        'bytes_uncompressed': total,
        'status': 'verified-non-release',
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--frontend', type=Path, required=True)
    parser.add_argument('--helper', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = verify(args.archive, args.frontend, args.helper, args.source_root)
    except (OSError, ValueError) as exc:
        print('ALPHA package verification failed: ' + str(exc), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
