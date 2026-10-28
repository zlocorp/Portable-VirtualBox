"""Small file/path primitives shared by the read-only preparation tools.

Destination parent directories are trusted, user-selected locations. This module
is not a security boundary against an administrator changing directory topology.
"""
from __future__ import annotations
import os
from pathlib import Path, PureWindowsPath
import re

_RESERVED = re.compile(r'(?i)^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\..*)?$')


def windows_relative_parts(value: str) -> tuple[str, ...]:
    if not isinstance(value, str) or not value or len(value) > 32767:
        raise ValueError('Invalid relative Windows path')
    if any(ord(c) < 32 or c in '<>:"|?*' for c in value):
        raise ValueError('Special character in Windows path')
    win = PureWindowsPath(value)
    if win.drive or win.root:
        raise ValueError('Absolute or drive-relative path not allowed')
    parts = tuple(value.replace('\\', '/').split('/'))
    for part in parts:
        if not part or part in ('.', '..') or part.endswith(('.', ' ')) or _RESERVED.fullmatch(part):
            raise ValueError('Ambiguous or reserved Windows path component')
    return parts


def publish_new(source: Path, destination: Path) -> None:
    """Atomically publish without replacing a concurrently created destination.

    Windows rename refuses an existing destination, including on FAT/exFAT.
    POSIX uses link() because rename() would overwrite. Unsupported filesystems
    fail closed; never fall back to an overwriting rename or copy.
    """
    if os.name == 'nt':
        os.rename(source, destination)
    else:
        os.link(source, destination)
        source.unlink()
