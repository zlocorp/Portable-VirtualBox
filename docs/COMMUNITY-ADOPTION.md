# Community adoption ledger

Updated 2026-10-21. Author/source details: [CREDITS.md](../CREDITS.md). This ledger is the implementation follow-up to the [2026-10-21 review](REVIEW-2026-10-21-UPSTREAM-FORKS-PRS.md). “Useful” does not mean every legacy patch can be merged safely.

| ID | Source / useful behavior | Status in this branch | Implementation / validation | Still open |
| --- | --- | --- | --- | --- |
| COM-01 | Deac2: saved first-run language and settings UX | **Independently adapted** | `LauncherSettings.au3`, GUI Save/Windows-language, `--save-language`; native fixture and multi-launch public CLI tests | Full settings wizard, arbitrary profile paths and visual Windows 11 review |
| COM-02 | #103/#105: missing CLI/failed extraction must be explained | **Independently adapted** | `PortableApp.au3` checks the existing 15-file staging requirement; `--app-status` and GUI readiness; native partial/empty/collision fixtures | Signature/runtime compatibility is a separate gate, not proven by file presence |
| COM-03 | #92: missing Machines after relocation | **Independently adapted** | `PortableProfile.au3` reports precise missing folders; readiness names them; setup remains non-destructive | General cross-host and snapshot/medium-chain migration |
| COM-04 | ThatAdminGuy / #90: Manager is not a guest; headless process matters | **Partial adaptation** | Shared query-only process scanner now supplies separate diagnostic categories; same strict retained-handle validation | Production session tracking and safe shutdown after Manager closes; no claim of stopping guests |
| COM-05 | bitamind: Oracle VBoxSDS registration APIs | **Already covered independently in CI** | Exact-owned signed-SDS experiments and native integrated lifecycle existed before this package | Reviewed production privilege helper/UAC and abandoned service recovery |
| COM-06 | #92/#95: spaces, Unicode and full-root paths | **Existing coverage retained** | Unicode-path compilation/driver fixtures; saved preference relocation and missing folders additionally tested | Full user-selected paths and adversarial filesystem races |
| COM-07 | #92: partial/frozen downloads | **Existing developer safeguard** | `oracle_release.py` bounds downloads, checks exact hashes, refuses replacement and publishes only complete downloads | User-facing updater/cancellation UI |
| COM-08 | SpruceGuy7 #2: updater must not erase the launcher | **Deferred** | Requirement recorded; preview packaging is allowlisted/non-overwriting | Transactional updater/rollback with actual launcher survival test |
| COM-09 | #69/#68: English clarity and encoding | **Modern catalog maintained independently** | Embedded RU/EN, UTF-8 output, exhaustive key tests, persistent language | Additional locales and visual layout/DPI acceptance |
| COM-10 | #100: new 7.x icon/splash | **Not adopted** | No new assets copied; old splash stays removed | Optional design/licensing decision after functional runtime |

## Reuse rules

1. Record author, original URL and immutable commit/PR where possible, applicable license and reuse type: inherited code, copied/adapted code, independently implemented behavior, test scenario, dependency or reviewed-only reference.
2. Preserve original notices and identify local changes. Do not claim a source was copied when only its idea was used, or call a planned feature implemented.
3. Add behavior checks before implementation and record which environments really ran them. Source-text contracts alone do not prove Windows behavior.
4. Update CHANGELOG, FEATURES, CREDITS and the relevant README sections with every adopted feature. Include the notices in the ZIP and keep compiled About credits useful even without the repository.
5. Do not import blanket `#RequireAdmin`, global process-name termination, unconditional `sc delete`, arbitrary XML replacement, unverified binaries or automatic Hyper-V/BCD changes.

## Remaining functional sequence

The next production runtime milestone is still Batch A: a non-elevated Manager GUI paired with a reviewed minimal privileged helper and exact ownership/recovery checks, then isolated Windows 11 standard-user/UAC acceptance. The ledger records the full useful backlog; this first public-UX package does **not** finish all fork-derived work.
