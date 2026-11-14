# Cleanup Reconciliation Implementation Plan

**Goal:** Diagnose partial payload removal without acquiring recovery authority.

**Architecture:** A standalone read-only Python observer uses the existing Oracle
manifest pin and current fixed script inventory. Bounded repeated observations
classify retained/missing bytes and label untrusted cleanup markers as claims.

**Tech Stack:** Python standard library; existing `safe_files` path validation;
Windows file-only CI fixture. No new dependencies or runtime/helper wiring.

**Spec:** `docs/designs/cleanup-reconciliation.md`

## Global Constraints

- No system mutation, cleanup retries, helper verbs, packaging changes or VM data.
- Always `resume_authorized=false`, `ownership=UNVERIFIED`, `system_state=NOT_OBSERVED`.
- `REVIEW_ONLY` never means safe to replay or remove.

## Review Focus

- Symlink/reparse/hardlink or case-colliding entries: refuse rather than follow.
- Invalid/duplicate JSON keys or forged canonical inventory: refuse.
- Missing manifest after partial removal: require separately pinned original.
- A cleanup receipt claiming success: never infer Windows or owner state.
- Mid-read replacement, missing or inaccessible input: refuse uncertainty.

## Task 1: Observer, negative tests and evidence

Files: create `scripts/reconcile_cleanup.py`, `tests/test_cleanup_reconcile.py`;
create `tests/windows/check_cleanup_reconciliation.ps1`; update
`.github/workflows/inspect-oracle.yml` and relevant safety documentation.

Interfaces: `reconcile(session, manifest, expected_pin, script_sources)` returns
a JSON-compatible report. CLI always supplies the repository's existing pin and
fixed helper script sources; tests supply small independently pinned fixtures.

- [x] Write failing file-only tests for intact/partial/absent payload and all five review-focus classes.
- [x] Run `python -m unittest tests.test_cleanup_reconcile -v`; verify expected missing-feature failure.
- [x] Implement bounded manifest/remaining-byte comparison and observational JSON.
- [x] Run focused tests and the full Python suite; audit writes/process calls.
- [x] Exercise the genuine 185-file pinned Oracle manifest in disposable Windows
      using copied file-only fixtures, never a protected live session or drivers.
- [x] Document the observer, authority limits and unchanged release blocker.
- [x] Obtain independent review; address bounded enumeration and nonblocking-open findings.
- [x] Publish the scoped change and verify CI.

Local verification: 23 focused tests and 291 full-suite tests pass (6 platform
skips), including the available PowerShell file-only tests. Source safety checks
and `git diff --check` pass. The genuine Windows file-only rehearsal passed separately at
`157a6158f667eb1385b2a9c64aaea211964bd8da`: [run 42982570559](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/42982570559).
It independently checked 185 pinned Oracle files, intact/partial/absent copies,
and unchanged originals. The Windows Python suite passed 291 tests (2 skips);
all seven automatically triggered workflows for that code checkpoint passed.
These checks do not authorize cleanup replay or constitute workstation sign-off.

Windows compatibility regression: directory-entry cached metadata must not be
used as link-count evidence; fresh `lstat` retains strict type/reparse/hardlink
checks. The first Windows run refused intact inputs because cached link counts
were zero. The added portable regression reproduces that failure before the fix.

Cross-method Windows identity compares only normalized synthetic execute bits
and creation time; full same-method path/handle stamps still detect metadata
changes. File identity, size, modification time, link count, attributes and
creation-time availability remain strict. Negative cases cover each field.
