# Cleanup preflight admission implementation plan

**Goal:** Repeat only read-only full-cleanup preflight, without replaying effects.
**Architecture:** In-memory prospective proof is validated by the existing embedded
cleanup script; immutable proof/output admission follows successful validation.
**Spec:** ../designs/cleanup-preflight-admission.md
**Tech:** Windows PowerShell 5.1; existing fixed C# helper; Python contracts.

## Constraints and review focus

- Do not reset AttemptLedger, remove markers, adopt old/foreign sessions or add commands.
- No mutation before admission; all effects remain after committed proof/output.
- Changed resource, owner, partial query or error must not create a clean result.
- A write/flush failure must block effects and preserve any partial proof.
- Legacy file-proof and incomplete-preparation behavior must remain supported.
- No main-OS execution; use exact-commit disposable CI and retain failures.

## Tasks

- [x] Add failing actual-script fixture and Python ordering/packaging contracts.
- [x] Factor read-only preflight before proof/output admission in full cleanup;
      have fixed worker pass prospective proof without persisting it first.
- [x] Verify no-effect failures and retry, replay refusal, prospective-path validation,
      original effect sequence and legacy mode; run full existing source suite.
- [ ] Independent review, resolve blockers, publish exact tested tree to existing
      development branch and inspect naturally triggered Windows CI.

## Execution ledger

- Reconstructed remote 2b3eb85 exactly: tree 8b876174ba2666f0f423fe24c6b36853652eeeb9.
- Installed temporary official PowerShell 7.5.4 and hash-verified pinned net48
  reference assemblies for local behavioral tests. Windows PowerShell 5.1 and
  real service/driver behavior still require the disposable Windows jobs.
- Actual cleanup-script fixture covers 347 checks, including immutable CreateNew
  races and post-admission refusal. OS observers/effects are controlled doubles;
  these checks do not prove real service or driver behavior.
- Added a real helper-boundary CI case: exclusive read-only lock on the owned OEM
  INF causes Finish preflight refusal without admission/effects; unlocking permits
  a fresh Finish, while earlier journal and receipt hashes remain unchanged.
- Independent review found no demonstrated production-code blocker and requested
  additional fault coverage. Added real-prefix-write then throw, flush refusal
  after full write, output-directory refusal, missing/foreign receipts and partial
  service enumeration. Each verifies retained evidence/no effects or safe corrected
  preflight retry as applicable. Arbitrary storage-loss/crash recovery is not claimed.
- First full configured suite: 474 tests, seven expected skips, no failures. The
  expanded final fixture passed 347 checks; final full-suite recheck passed all
  474 tests with seven expected platform skips in 130.766 seconds.
- Windows CI results are pending publication. No workstation acceptance or
  successful real retry has yet been claimed for this tree.

## Windows evidence correction

- At published `72d8c20`, independent artifact inspection found both helper proofs
  had `preflight_refusal_then_cleanup_verified=false` despite green job status.
  The fixture iterates cycles 2 and 3, but the new case incorrectly selected 1.
  Thus those jobs do not prove the real locked-INF refusal/retry scenario.
- Correct both guards to cycle 2 and require the proof flag before any overall
  success claim. A regression contract failed with `1 not found in {2, 3}` before
  the fix and passed afterward. Independent source review accepted this correction.
  No production code or cleanup authority is changed by this follow-up.
- Exact-source successor Windows artifacts must show the flag true and actual
  failed-then-successful worker evidence; earlier green jobs remain historical.

- Final correction suite: 475 tests, seven expected skips, no failures (136.047 s).
