# Community adoption ledger

Updated 2026-10-21. Author/source details: [CREDITS.md](../CREDITS.md). This ledger is the implementation follow-up to the [2026-10-21 review](REVIEW-2026-10-21-UPSTREAM-FORKS-PRS.md). “Useful” does not mean every legacy patch can be merged safely.

| ID | Source / useful behavior | Status in this branch | Implementation / validation | Still open |
| --- | --- | --- | --- | --- |
| COM-01 | Deac2: saved first-run language and settings UX | **Independently adapted** | `LauncherSettings.au3`, GUI Save/Windows-language, `--save-language`; native fixture and multi-launch public CLI tests | Full settings wizard, arbitrary profile paths and visual Windows 11 review |
| COM-02 | #103/#105: missing CLI/failed extraction must be explained | **Independently adapted** | `PortableApp.au3` checks the existing 15-file staging requirement; `--app-status` and GUI readiness; native partial/empty/collision fixtures | Signature/runtime compatibility is a separate gate, not proven by file presence |
| COM-03 | #92: missing Machines after relocation | **Independently adapted** | `PortableProfile.au3` reports precise missing folders; readiness names them; setup remains non-destructive | General cross-host and snapshot/medium-chain migration |
| COM-04 | ThatAdminGuy / #90: Manager is not a guest; headless process matters | **Integrated experimental flow** | Actual Start/Finish/Reopen GUI; retained Manager handle; wait for guests before exact-owned cleanup; [two-session acceptance](EXECUTION-2026-10-21-manager-session.md) | Production UAC/Windows 11 user path, crash recovery and real guest-OS acceptance |
| COM-05 | bitamind: Oracle VBoxSDS registration APIs | **Already covered independently in CI** | Existing exact-owned signed-SDS/driver operations now reused by the Manager session worker; dedicated quiescence proof for Manager-only cycles | Reviewed production privilege helper/UAC and abandoned service recovery |
| COM-06 | #92/#95: spaces, Unicode and full-root paths | **Existing coverage retained** | Unicode-path compilation/driver fixtures; saved preference relocation and missing folders additionally tested | Full user-selected paths and adversarial filesystem races |
| COM-07 | #92: partial/frozen downloads | **Existing developer safeguard** | `oracle_release.py` bounds downloads, checks exact hashes, refuses replacement and publishes only complete downloads | User-facing updater/cancellation UI |
| COM-08 | SpruceGuy7 #2: updater must not erase the launcher | **Deferred** | Requirement recorded; preview packaging is allowlisted/non-overwriting | Transactional updater/rollback with actual launcher survival test |
| COM-09 | #69/#68: English clarity and encoding | **Modern catalog maintained independently** | Embedded RU/EN, UTF-8 output, exhaustive key tests, persistent language | Additional locales and visual layout/DPI acceptance |
| COM-10 | #100: new 7.x icon/splash | **Not adopted** | No new assets copied; old splash stays removed | Optional design/licensing decision after functional runtime |

## Adoption approach

Use suitable code directly, with local interface/error-handling adaptations, retained author/license notices and behavioral checks. Independently reimplement only when there is a concrete incompatibility or unsafe operation. Do not reject a whole fork just because one function needs repair.

The “still open” column above previously mixed follow-up work with complete new features. Production Manager Start/Stop, cross-host VM migration and a transactional updater are not completed patch imports; they are still implementation work. Existing hash/download checks should be reused rather than duplicated. Optional artwork and unused legacy features are not required merely because a PR exists.

A finished adaptation means the intended public behavior works and its tests have run. A diagnostic category, test idea or backlog row does not finish a shutdown controller or updater.

Actual reuse is acknowledged once in CREDITS.md (plus preserved source headers). LICENSE.md and that same CREDITS file travel with the ZIP. The About dialog does not list community contributors. CHANGELOG/FEATURES and this development record stay in the repository.

## Remaining functional sequence

Manager/session startup and shutdown now work through a separate compiled test GUI using the existing driver/SDS operations. The main unfinished step is replacing the already-elevated disposable-host adapter with the reviewed narrow privileged helper and connecting that path to the ordinary user build. Do not postpone suitable code behind further attribution documents or generic infrastructure. Windows 11 standard-user/UAC acceptance remains a real test requirement, not a reason to avoid implementing the flow.
