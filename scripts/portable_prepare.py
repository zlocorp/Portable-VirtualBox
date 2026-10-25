#!/usr/bin/env python3
"""Offline, non-admin first-run Oracle file preparation for ordinary users.

An exact compiled-in Oracle release hash is the trust root, never the caller's
claim. Nothing is installed or executed from the Oracle wrapper or MSI.
"""
from __future__ import annotations
import argparse
from contextlib import nullcontext
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

from oracle_release import download_verified
from prepare_app64 import prepare, regular_file, sha256

RELEASE = "7.2.22"
INSTALLER = "VirtualBox-7.2.22-175245-Win.exe"
PINNED_SHA256 = "afd0ff1656cbe04ed88ce619594ae021419d97cce89fa9bdc443e9a963f1713f"
FILE_COUNT = 185
TOTAL_BYTES = 247834716
MAX_INSTALLER_SIZE = 1024 * 1024 * 1024
OFFICIAL_URL = "https://download.virtualbox.org/virtualbox/" + RELEASE + "/" + INSTALLER


class ProgressFile:
    """Display-only status owned by this nonprivileged preparer, never authority."""

    def __init__(self, root: Path, path: Path):
        self.path = Path(path)
        if (self.path.parent != Path(root) or
                not re.fullmatch(r"\.pvbox-setup-[0-9]{1,10}-[0-9]{14}-[0-9]{1,3}\.progress", self.path.name)):
            raise ValueError("Progress file must be a reserved leaf inside portable root")
        self.stream = None

    def __enter__(self):
        # CREATE_NEW never replaces a stale file, reparse point or user document.
        self.stream = self.path.open("x+", encoding="ascii")
        return self

    def update(self, phase: str, done: int = 0, total: int = 0) -> None:
        if phase not in ("DOWNLOAD", "VERIFY", "EXTRACT", "DONE"):
            raise ValueError("Unexpected setup progress phase")
        if not 0 <= done <= 1024 ** 3 or not 0 <= total <= 1024 ** 3:
            raise ValueError("Invalid setup byte counts")
        self.stream.seek(0)
        self.stream.write(f"{phase}|{done}|{total}\n")
        self.stream.truncate()
        self.stream.flush()

    def __exit__(self, _type, _value, _tb):
        # Do not delete a replacement file if an interrupted GUI or another
        # same-user process changed the leaf while the handle was open.
        same_file = False
        try:
            same_file = os.path.samestat(os.fstat(self.stream.fileno()),
                                        self.path.stat(follow_symlinks=False))
        except OSError:
            pass
        self.stream.close()
        if same_file:
            self.path.unlink(missing_ok=True)


def safe_ancestors(path: Path) -> bool:
    """Never traverse an existing junction/symlink on a privileged-looking path."""
    if not path.is_absolute():
        return False
    for item in (path, *path.parents):
        try:
            info = item.lstat()
        except OSError:
            return False
        if not stat.S_ISDIR(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 0x400):
            return False
    return True


def check_root(root: Path, *, require_windows: bool = True) -> None:
    if require_windows and os.name != "nt":
        raise ValueError("This preparer runs on Windows only")
    if not safe_ancestors(root):
        raise ValueError("Portable root is unsafe or inaccessible")
    if root == root.anchor or root.name in ("", ".", ".."):
        raise ValueError("A drive root is not a portable application folder")
    if os.path.lexists(root / "app64"):
        raise FileExistsError("app64 already exists: refusing replacement")


def candidate(installer: Path, root: Path, *, require_windows: bool = True) -> None:
    """Raise before making any filesystem changes or executing another process."""
    check_root(root, require_windows=require_windows)
    if installer.name != INSTALLER:
        raise ValueError("Only the pinned official Oracle Windows installer is accepted")
    if not safe_ancestors(installer.parent):
        raise ValueError("Installer has an unsafe/reparse parent")
    info = regular_file(installer)
    if not 1024 * 1024 < info.st_size <= MAX_INSTALLER_SIZE:
        raise ValueError("Installer file size is not plausible")
    if sha256(installer) != PINNED_SHA256:
        raise ValueError("Oracle installer does not match the built-in pinned SHA-256")


def offline_prepare(installer: Path, root: Path, *, require_windows: bool = True, progress=None) -> dict:
    root, installer = Path(root), Path(installer)
    if progress is not None:
        progress.update("VERIFY")
    candidate(installer, root, require_windows=require_windows)
    if progress is not None:
        progress.update("EXTRACT")
    result = prepare(installer, root / "app64", PINNED_SHA256, RELEASE)
    if result.get("file_count") != FILE_COUNT or result.get("total_bytes") != TOTAL_BYTES:
        # A success result with unexpected inventory MUST NOT be advertised as ready.
        # prepare() also validates all 185 files before publication.
        raise ValueError("Published Oracle file inventory differs from pinned distribution")
    return result


def online_prepare(root: Path, *, downloader=None, require_windows: bool = True, progress=None) -> dict:
    """Retrieve only the pinned official Oracle wrapper; never execute it.

    The download and its partial state live in our own temporary directory.
    The completed app64 is published by the existing non-overwriting validator.
    """
    root = Path(root)
    check_root(root, require_windows=require_windows)
    built_in_downloader = downloader is None
    if downloader is None:
        downloader = download_verified
    with tempfile.TemporaryDirectory(prefix=".vbox-official-", dir=root) as folder:
        installer = Path(folder) / INSTALLER
        if progress is not None:
            progress.update("DOWNLOAD")
        if built_in_downloader and progress is not None:
            downloader(OFFICIAL_URL, installer, PINNED_SHA256,
                       progress=lambda done, total: progress.update("DOWNLOAD", done, total))
        else:
            downloader(OFFICIAL_URL, installer, PINNED_SHA256)
        return offline_prepare(installer, root, require_windows=require_windows, progress=progress)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--installer", type=Path)
    source.add_argument("--download", action="store_true",
                        help="Download pinned Oracle package from official HTTPS site")
    parser.add_argument("--root", type=Path)
    parser.add_argument("--progress-file", type=Path,
                        help="Optional transient read-only-for-UI status inside portable root")
    parser.add_argument("--version", action="store_true", help="Print pinned release; no filesystem changes")
    args = parser.parse_args(argv)
    if args.version:
        if args.installer or args.root or args.download or args.progress_file:
            parser.error("--version must not mix with file operations")
        print("Portable-VirtualBox offline file preparation: Oracle " + RELEASE)
        return 0
    if args.root is None or (args.installer is None and not args.download):
        parser.error("--root and exactly one input mode are required")
    try:
        check_root(args.root)
        context = ProgressFile(args.root, args.progress_file) if args.progress_file else nullcontext()
        with context as progress:
            result = (online_prepare(args.root, progress=progress) if args.download
                      else offline_prepare(args.installer, args.root, progress=progress))
            if progress is not None:
                progress.update("DONE")
    except FileExistsError as e:
        print("Preparation blocked: " + str(e), file=sys.stderr)
        return 2
    except (OSError, ValueError) as e:
        print("Preparation failed: " + str(e), file=sys.stderr)
        return 3
    print("Prepared app64: {} signed-package files, {} bytes (no installer or MSI executed).".format(
        result["file_count"], result["total_bytes"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
