# Community adoption: first public-UX package

Date: 2026-10-21. Working branch: `dev/modernization-2026`, based on `5111862f`. No master change, merge or release.

## Implemented changes

Independent adaptations of useful community behavior, not a blanket merge of old runtime code:

- Deac2-inspired explicit persistent RU/EN language and Windows-language reset; data-only versioned settings, bounded parsing, non-overwrite refusal for foreign/corrupt content, staged same-directory replacement.
- Native app64 completeness inspection using the same 15 required inputs as existing MSI staging; names missing/empty components and refuses directories/reparse paths. User-facing GUI readiness and `--app-status`/`--check-readiness` use it. Presence is not authenticity or runtime approval.
- Exact missing profile-folder names, especially `data/Machines` (upstream #92 scenario).
- Separate query-only Manager, GUI/headless guest and background counts (ThatAdminGuy / #90); existing aggregate conflict checks remain fail-closed. A snapshot is not cleanup authority.
- About credits in GUI/CLI; CREDITS and THIRD_PARTY_NOTICES required in the nine-file preview ZIP.
- Current English/Russian READMEs, CHANGELOG, FEATURES, CONTRIBUTING and a complete community-adoption ledger.

## Validation record

Before implementation, new Python package/provenance/public-wiring tests failed against the previous source: expected missing commands/documents and missing mandatory credits in the ZIP. After implementation the Linux suite reports **120 tests, zero failures, five platform skips**, and `check_active_tree.py` passes. This does not execute AutoIt.

Native behavioral checks are in `tests/native/test_community_adoption.au3`. The ordinary compiled interface is exercised by `scripts/check_community_ux.ps1`: separate-process language persistence, temporary override without disk mutation, root relocation, foreign-setting preservation, missing runtime files/folders, credits and activity categories. Core CI also validates exact ZIP membership.

Windows execution evidence must be appended only after inspecting completed jobs/logs. Existing privileged experiments remain disposable-host-only. No interactive GUI/DPI, Windows 11 UAC, user VM shutdown or real guest OS acceptance is claimed by this package.

## Sources and unfinished work

[CREDITS](../CREDITS.md) records author/source/adoption kind. [COMMUNITY-ADOPTION](COMMUNITY-ADOPTION.md) records every reviewed useful item as adapted, partial, covered, deferred or not adopted, with code/tests and remaining work. The production Manager/helper/shutdown/updater work is still unfinished; this package is not “all forks fully merged”.
