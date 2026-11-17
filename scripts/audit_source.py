#!/usr/bin/env python3
"""Read-only risk inventory for the inherited AutoIt launcher.

This tool does NOT declare a script safe: it only locates patterns needing review.
It never runs or modifies the launcher, Windows installers, drivers or services.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
RULES = {
    "installer-process-kill": r"\btaskkill\b.*?/im\s+msiexec\.exe",
    "system-directory-copy": r"\bFileCopy\s*\([^\r\n]*@SystemDir",
    "system-directory-delete": r"\bFileDelete\s*\([^\r\n]*@SystemDir",
    "system-directory-delete-windows": r"\bFileDelete\s*\([^\r\n]*@WindowsDir",
    "service-command": r"\bsc\s+(?:create|delete|stop|start)\s+VBox\w*",
    "name-only-process-close": r'\bProcessClose\s*\(\s*["\'](?:VBox|VirtualBox)',
    "legacy-cmd-environment": r"\bcmd\s+/c\s+set\s+VBOX_USER_HOME=",
    "xml-string-rewrite": r"\bFileWrite\s*\([^\r\n]*StringReplace\s*\(",
}


def inspect(text: str) -> list[tuple[str, int, str]]:
    found: list[tuple[str, int, str]] = []
    patterns = [(name, re.compile(expr, re.IGNORECASE)) for name, expr in RULES.items()]
    for line_number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith(";"):
            continue
        for name, pattern in patterns:
            if pattern.search(line):
                found.append((name, line_number, line.strip()[:200]))
    return found


def markdown(items: list[tuple[str, int, str]], source: str) -> str:
    output = ["## Legacy AutoIt safety inventory", "", f"Source: `{source}`",
              f"Total matched operations: **{len(items)}**.", "",
              "These are findings for review, not proof of actual damage.",
              "Counts may include operations under conditional branches.", "",
              "| Rule | Line | Code |", "| --- | ---: | --- |"]
    for name, line, code in items:
        escaped = code.replace("|", "\\|").replace("`", "\\`")
        output.append(f"| {name} | {line} | `{escaped}` |")
    return "\n".join(output) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "source/Portable-VirtualBox.au3")
    parser.add_argument("--output", type=Path, help="Write Markdown report to this file")
    parser.add_argument("--enforce", action="store_true", help="Fail when any matched operation remains")
    args = parser.parse_args()
    data = args.source.read_text(encoding="utf-8-sig")
    hits = inspect(data)
    report = markdown(hits, str(args.source))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding="utf-8")
    else:
        sys.stdout.write(report)
    return 1 if args.enforce and hits else 0


if __name__ == "__main__":
    raise SystemExit(main())
