#!/usr/bin/env python3
"""Verify Oracle release metadata and optionally download, never execute it."""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile
import time
import urllib.parse
import urllib.request
import sys
from safe_files import windows_relative_parts, publish_new

VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+", re.ASCII)
# Oracle's manifest also includes Debian/Ubuntu filenames containing '~'.
SHA256_RE = re.compile(r"^([0-9a-fA-F]{64})[ \t]+[*]?([A-Za-z0-9][A-Za-z0-9._+~-]*)$")
MAX_INSTALLER_BYTES = 1024 * 1024 * 1024


def release_root(version: str) -> str:
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
        raise ValueError("Release must be an explicit numeric X.Y.Z")
    return "https://download.virtualbox.org/virtualbox/{}/".format(version)


def validate_official_url(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.netloc != "download.virtualbox.org"
            or parsed.query or parsed.fragment
            or not re.fullmatch(r"/virtualbox/[0-9]+\.[0-9]+\.[0-9]+/[A-Za-z0-9._+-]+", parsed.path)):
        raise ValueError("Only exact official HTTPS release URLs are accepted")
    return url


class OfficialRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_official_url(newurl)
        if urllib.parse.urlsplit(newurl).path != urllib.parse.urlsplit(req.full_url).path:
            raise ValueError("Release identity changed during redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def official_open(request, *, timeout):
    validate_official_url(request.full_url)
    return urllib.request.build_opener(OfficialRedirect()).open(request, timeout=timeout)


def _validate_response(response, requested: str) -> None:
    final = validate_official_url(getattr(response, "url", requested))
    if final != requested:
        raise ValueError("Unexpected response URL")


def parse_sha256_manifest(data: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    folded = set()
    for line in data.splitlines():
        if not line.strip():
            continue
        match = SHA256_RE.fullmatch(line)
        if match is None:
            raise ValueError("Malformed Oracle checksum manifest line")
        checksum, filename = match.groups()
        if len(windows_relative_parts(filename)) != 1:
            raise ValueError("Unsafe filename")
        if filename.casefold() in folded:
            raise ValueError("Duplicate checksum entry")
        folded.add(filename.casefold())
        entries[filename] = checksum.lower()
    if not entries:
        raise ValueError("Empty manifest")
    return entries


def find_windows_installer(entries: dict[str, str], version: str) -> tuple[str, str]:
    release_root(version)
    pattern = re.compile(r"VirtualBox-" + re.escape(version) + r"-[0-9]+-Win\.exe")
    matches = [name for name in entries if pattern.fullmatch(name)]
    if len(matches) != 1:
        raise ValueError("Expected exactly one Windows installer")
    return matches[0], entries[matches[0]]


def read_manifest(version: str, opener=official_open) -> dict[str, str]:
    url = release_root(version) + "SHA256SUMS"
    request = urllib.request.Request(url, headers={"User-Agent": "portable-vbox-build/1"})
    with opener(request, timeout=30) as response:
        _validate_response(response, url)
        data = response.read(128 * 1024 + 1)
        if len(data) > 128 * 1024:
            raise ValueError("Unexpectedly large checksum manifest")
    return parse_sha256_manifest(data.decode("ascii"))


def download_verified(url: str, destination: Path, expected_sha256: str,
                      opener=official_open, *, max_bytes: int = MAX_INSTALLER_BYTES,
                      progress=None) -> str:
    validate_official_url(url)
    version, filename = urllib.parse.urlsplit(url).path.split("/")[-2:]
    find_windows_installer({filename: expected_sha256}, version)
    if not re.fullmatch(r"[a-f0-9]{64}", expected_sha256):
        raise ValueError("Invalid expected SHA-256")
    if type(max_bytes) is not int or max_bytes <= 0:
        raise ValueError("Invalid download size limit")
    destination = Path(destination)
    if os.path.lexists(destination):
        raise FileExistsError("Refusing to overwrite destination")
    if not destination.parent.is_dir():
        raise ValueError("Destination directory does not exist")
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": "portable-vbox-build/1"})
    with tempfile.TemporaryDirectory(prefix=".vbox-download-", dir=destination.parent) as folder:
        temporary = Path(folder) / "payload"
        deadline = time.monotonic() + 1200
        total = 0
        with opener(request, timeout=60) as response, temporary.open("xb") as handle:
            _validate_response(response, url)
            raw_length = getattr(response, "headers", {}).get("Content-Length")
            expected_length = 0
            if raw_length is not None:
                if not isinstance(raw_length, str) or not raw_length.isascii() or not raw_length.isdecimal():
                    raise ValueError("Invalid official Content-Length")
                expected_length = int(raw_length)
                if not 0 < expected_length <= max_bytes:
                    raise ValueError("Official Content-Length exceeds permitted size")
            if progress is not None:
                progress(0, expected_length)
            while True:
                if time.monotonic() > deadline:
                    raise TimeoutError("Download deadline exceeded")
                chunk = response.read(min(1024 * 1024, max_bytes - total + 1))
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    raise ValueError("Installer exceeds size limit")
                digest.update(chunk)
                handle.write(chunk)
                if progress is not None:
                    progress(total, expected_length)
            if expected_length and total != expected_length:
                raise ValueError("Truncated or inconsistent official download")
            handle.flush()
            os.fsync(handle.fileno())
        actual = digest.hexdigest()
        if actual != expected_sha256:
            raise ValueError("SHA-256 mismatch: expected {}, got {}".format(expected_sha256, actual))
        publish_new(temporary, destination)
    return actual


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Exact Oracle VirtualBox release, e.g. 7.2.22")
    parser.add_argument("--download", type=Path, help="Write verified installer here; never run it")
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
