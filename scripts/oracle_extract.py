#!/usr/bin/env python3
"""Extract a hash-pinned Oracle installer without executing it or Windows Installer.

Reads neutral PE RCDATA MANIFEST/HDR_nn/BIN_nn resources documented by Oracle's
VBoxStubBld format. This is not a generic SFX extractor or an MSI installer.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys
from pe_resources import read_rcdata
from safe_files import windows_relative_parts

MAX_BYTES = 1024 * 1024 * 1024
MAGIC = b'VBoxInstV1' + b'\0' * 5
ARCHITECTURES = {1: 'all', 2: 'x86', 3: 'amd64', 4: 'arm64'}
CFB_MAGIC = bytes.fromhex('d0cf11e0a1b11ae1')


@dataclass(frozen=True)
class Package:
    name: str
    architecture: str
    payload: memoryview


def _cstring(raw) -> str:
    data = bytes(raw)
    if b'\0' not in data:
        raise ValueError('Unterminated package header field')
    try:
        return data.split(b'\0', 1)[0].decode('ascii')
    except UnicodeError as exc:
        raise ValueError('Non-ASCII package header field') from exc


def inspect_packages(data: bytes) -> list[Package]:
    resources = read_rcdata(data)
    manifest = resources.get('MANIFEST', b'')
    if len(manifest) != 16 or bytes(manifest[:15]) != MAGIC or not 1 <= manifest[15] <= 128:
        raise ValueError('Invalid Oracle VBoxInstV1 manifest')
    result = []
    names = set()
    for index in range(manifest[15]):
        header = resources.get(f'HDR_{index:02d}', b'')
        if len(header) != 256:
            raise ValueError('Invalid package header size')
        arch = int.from_bytes(header[:4], 'little')
        resource_name = _cstring(header[4:32])
        name = _cstring(header[32:])
        if arch not in ARCHITECTURES or resource_name != f'BIN_{index:02d}':
            raise ValueError('Unknown package architecture/resource identity')
        if len(windows_relative_parts(name)) != 1 or name.casefold() in names:
            raise ValueError('Unsafe or duplicate package filename')
        if name.casefold() in ('packages.json', '.incomplete'):
            raise ValueError('Reserved output filename')
        payload = resources.get(resource_name)
        if payload is None or len(payload) == 0:
            raise ValueError('Package payload is missing')
        if name.lower().endswith('.msi') and (len(payload) < 512 or bytes(payload[:8]) != CFB_MAGIC):
            raise ValueError('MSI payload is not a compound file')
        names.add(name.casefold())
        result.append(Package(name, ARCHITECTURES[arch], payload))
    if not any(p.name.lower().endswith('.msi') and p.architecture in ('amd64', 'all') for p in result):
        raise ValueError('No x64-compatible MSI in package manifest')
    return result


def extract_packages(installer: Path, output: Path, expected_sha256: str) -> list[dict]:
    if not re.fullmatch('[0-9a-f]{64}', expected_sha256):
        raise ValueError('An exact trusted SHA-256 is required')
    with installer.open('rb') as handle:
        if installer.stat().st_size > MAX_BYTES:
            raise ValueError('Installer exceeds size limit')
        data = handle.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES or hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError('Installer SHA-256 or size mismatch')
    packages = inspect_packages(data)
    output.mkdir(exist_ok=False)
    marker = output / '.incomplete'
    marker.write_text('Do not use until packages.json exists and this marker is removed.\n')
    reports = []
    for package in packages:
        with (output / package.name).open('xb') as handle:
            handle.write(package.payload)
        reports.append({'name': package.name, 'architecture': package.architecture,
                        'size': len(package.payload), 'sha256': hashlib.sha256(package.payload).hexdigest()})
    # I/O failure retains an explicitly incomplete directory, never deletes it.
    with (output / 'packages.json').open('x', encoding='utf-8') as handle:
        json.dump({'installer_sha256': expected_sha256, 'packages': reports,
                   'installer_executed': False, 'msi_installed': False}, handle, indent=2)
        handle.write('\n')
    marker.unlink()
    return reports


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('installer', type=Path)
    parser.add_argument('output', type=Path, help='A new staging directory')
    parser.add_argument('--sha256', required=True, help='Trusted wrapper checksum, lowercase hex')
    args = parser.parse_args()
    try:
        packages = extract_packages(args.installer, args.output, args.sha256)
    except (ValueError, OSError) as exc:
        print('Extraction failed: ' + str(exc), file=sys.stderr)
        return 1
    print(json.dumps(packages, indent=2))
    print('Passive extraction complete. No executable or MSI was run.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
