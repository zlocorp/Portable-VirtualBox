# Community adoption: first public-UX package

Date: 2026-10-21. Working branch: `dev/modernization-2026`, based on `5111862f`. Tested implementation: [`183f35da951e4e814a011c14e3a90da85098610c`](https://github.com/zlocorp/Portable-VirtualBox/commit/183f35da951e4e814a011c14e3a90da85098610c). No master change, merge or release.

## Implemented changes

Independent adaptations of useful community behavior, not a blanket merge of old runtime code:

- Deac2-inspired explicit persistent RU/EN language and Windows-language reset; data-only versioned settings, bounded parsing, non-overwrite refusal for foreign/corrupt content, staged same-directory replacement.
- Native app64 completeness inspection using the same 15 required inputs as existing MSI staging; names missing/empty components and refuses directories/reparse paths. User-facing GUI readiness and `--app-status`/`--check-readiness` use it. Presence is not authenticity or runtime approval.
- Exact missing profile-folder names, especially `data/Machines` (upstream #92 scenario).
- Separate query-only Manager, GUI/headless guest and background counts (ThatAdminGuy / #90); existing aggregate conflict checks remain fail-closed. A snapshot is not cleanup authority.
- About credits in GUI/CLI; CREDITS and THIRD_PARTY_NOTICES required in the nine-file preview ZIP.
- Current English/Russian READMEs, CHANGELOG, FEATURES, CONTRIBUTING and a complete community-adoption ledger.

## Local validation

Before implementation, new Python package/provenance/public-wiring tests failed against the previous source: expected missing commands/documents and missing mandatory credits in the ZIP. After implementation the Linux suite discovered **120 tests: 115 passed, five platform skips, zero failures**. `check_active_tree.py` and `git diff --check` passed. This does not execute AutoIt.

Native behavioral checks are in `tests/native/test_community_adoption.au3`. The ordinary compiled interface is exercised by `scripts/check_community_ux.ps1`: separate-process language persistence, temporary override without disk mutation, root relocation, foreign-setting preservation, missing runtime files/folders, credits and activity categories.

## Completed Windows CI for 183f35da

| Check | Result and scope |
| --- | --- |
| [Core static checks / x64 build / public CLI / ZIP, 39548219426](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219426) | **Success**. Official external AutoIt, direct `build.bat`, safety diagnostics, non-destructive profile preparation, ordinary compiled language/app/credits checks, Unicode-path rebuild, exact ZIP membership and unpacked first-run tests all completed successfully. |
| [Native AutoIt, 39548219415](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219415) | **18 compiled harnesses**, zero failures. New community harness: **47 assertions**. RU/EN catalog: **214 assertions**. GUI text: **10 assertions**. Counts verified from job 119051156738 logs. |
| [Oracle file-only preparation, 39548219418](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219418) | **Success**. Windows Python regressions and pinned Oracle 7.2.22 signed package / passive MSI/CAB preparation remained valid. |
| [Native service session, 39548214328](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548214328) | **Success**. Compiled AutoIt used the isolated profile and cleaned its exact VBoxSDS registration on a disposable Windows host. |
| [Native empty-VM / signed-driver lifecycle, 39548214487](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548214487) | **Success**. Existing compiled AutoIt driver/VM/independent-check/exact-cleanup integration completed after the changes. No ordinary-user runtime was enabled. |

The ordinary compiled CLI test verified RU persistence across separate process launches, temporary EN override without changing the saved file, reset to `auto`, unsupported-locale refusal, retained settings after root relocation, preserved user sentinel, refusal to overwrite foreign configuration, named missing `VBoxManage.exe`/`VBoxSup.sys`, exact missing `data/Machines`, separate activity labels and compiled author/license text.

## Downloaded-artifact inspection

Downloaded the actual diagnostic-preview artifact **12322328294** from core run **39548219426**, rather than relying only on packaging source or a green workflow icon. Verified the artifact digest, inner ZIP against its SHA-256 sidecar, and these **nine exact members**:

`Portable-VirtualBox.exe`, `PREVIEW-NOT-A-HYPERVISOR.txt`, `LICENSE.md`, `README.md`, `README.ru.md`, `CHANGELOG.md`, `FEATURES.md`, `CREDITS.md`, `THIRD_PARTY_NOTICES.md`.

Inner diagnostic ZIP SHA-256:
`b485cabe2dc8b1d1ff798fc282c97002b571273f6626ee69980becff3e5e5905`.

The seven Markdown files match the tested source content after normalizing Windows checkout CRLF to repository LF. The warning explicitly says the ordinary interface does not launch virtual machines; credits contain the original author, community sources and unchanged project license. No Oracle payload or retired tools are present. The EXE has a Windows PE header; actual execution was verified by Windows CI, not locally.

Also downloaded source snapshot **12321992243** from run **39548214354**, checked its commit marker and archive checksum, and compared all **27 changed files** against the locally tested content: all matched exactly.

## Limits and unfinished work

No interactive GUI/DPI, Windows 11 standard-user/UAC, production guest shutdown, real guest OS/disk boot or general crash recovery is claimed. These tests used Linux and disposable Windows Server 2022. Read-only process categories do not prove VM state or authorize teardown. Settings replacement is not a promise of power-loss recovery or protection from a malicious same-account process.

[CREDITS](../CREDITS.md) records author/source/adoption kind. [COMMUNITY-ADOPTION](COMMUNITY-ADOPTION.md) records each reviewed useful item as adapted, partial, covered, deferred or not adopted, with code/tests and remaining work. The production Manager/helper/shutdown/updater work is still unfinished; this package is not “all forks fully merged”.

Subsequent documentation-only commits record these completed results; the tested code remains 183f35da unless a later report explicitly identifies another code revision.
