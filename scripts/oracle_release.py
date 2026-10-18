#!/usr/bin/env python3
"""Fetch official Oracle VirtualBox installer metadata; optionally download safely.

Never executes an installer, never downloads Extension Packs and never touches
Windows services. Pin the desired release explicitly, e.g. 7.2.20.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import ssl
import sys
import urllib.request

VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+", re.ASCII)
SHA256_RE = re.compile(r"^([0-9a-fA-F]{64})[ \t]+[*]?([^/\x5c\r\n]+)$")


def release_root(version: str) -> str:
    if not VERSION_RE.fullmatch(version):
        raise ValueError("Release must be an explicit numeric X.Y.Z, not a URL or a moving alias")
    return "https://download.virtualbox.org/virtualbox/{}/".format(version)


def parse_sha256_manifest(data: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue
        match = SHA256_RE.fullmatch(line)
        if match is None:
            raise ValueError("Malformed Oracle checksum manifest line")
        checksum, filename = match.groups()
        if filename in entries:
            raise ValueError("Duplicate checksum entry: " + filename)
        if filename in (".", "..") or filename.startswith("."):
            raise ValueError("Unsafe filename")
        entries[filename] = checksum.lower()
    if not entries:
        raise ValueError("Empty manifest")
    return entries


def find_windows_installer(entries: dict[str, str], version: str) -> tuple[str, str]:
    matches = [
        name for name in entries
        if name.startswith("VirtualBox-" + version + "-") and name.endswith("-Win.exe")
    ]
    if len(matches) != 1:
        raise ValueError("Expected one official Windows installer, found {}".format(len(matches)))
    name = matches[0]
    return name, entries[name]


def read_manifest(version: str, opener=urllib.request.urlopen) -> dict[str, str]:
    url = release_root(version) + "SHA256SUMS"
    request = urllib.request.Request(url, headers={"User-Agent": "portable-vbox-build/1"})
    with opener(request, timeout=30) as response:
        if getattr(response, "url", url).split(":", 1)[0].lower() != "https":
            raise ValueError("Non-HTTPS checksum redirect")
        data = response.read(128 * 1024 + 1)
        if len(data) > 128 * 1024:
            raise ValueError("Unexpectedly large checksum manifest")
    return parse_sha256_manifest(data.decode("ascii"))


def download_verified(url: str, destination: Path, expected_sha256: str,
                      opener=urllib.request.urlopen) -> str:
    if not url.startswith("https://download.virtualbox.org/virtualbox/"):
        raise ValueError("Only official HTTPS release links may be downloaded")
    if not re.fullmatch(r"[a-f0-9]{64}", expected_sha256):
        raise ValueError("Invalid expected SHA-256")
    if destination.exists():
        raise FileExistsError("Refusing to overwrite: " + str(destination))
    if not destination.parent.is_dir():
        raise ValueError("Destination directory does not exist")
    temporary = destination.with_name(destination.name + ".partial")
    if temporary.exists():
        raise FileExistsError("Refusing to overwrite partial file")
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": "portable-vbox-build/1"})
    try:
        with opener(request, timeout=60) as response, temporary.open("xb") as handle:
            if getattr(response, "url", url).split(":", 1)[0].lower() != "https":
                raise ValueError("Non-HTTPS installer redirect")
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                handle.write(chunk)
        actual = digest.hexdigest()
        if actual != expected_sha256:
            raise ValueError("SHA-256 mismatch: expected {}, got {}".format(expected_sha256, actual))
        os.replace(temporary, destination)
        return actual
    finally:
        if temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Exact Oracle VirtualBox release, e.g. 7.2.20")
    parser.add_argument("--download", type=Path,
                        help="Write verified Windows installer here (never run it)")
    args = parser.parse_args()
    try:
        root = release_root(args.version)
        installer, checksum = find_windows_installer(read_manifest(args.version), args.version)
        print("Official installer: " + root + installer)
        print("Expected SHA256:   " + checksum)
        if args.download:
            actual = download_verified(root + installer, args.download, checksum)
            print("Verified download: {} (SHA256 {})".format(args.download, actual))
        else:
            print("Metadata only; no executable downloaded or run.")
    except (OSError, UnicodeError, ValueError) as exc:
        print("Verification failed: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
