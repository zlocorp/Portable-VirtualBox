# Package preparation and lifecycle hardening implementation plan

> Execute inline, task by task, with failing regression tests before implementation. User authorized continuing development and hosted CI; no master merge or release is authorized.

**Goal:** Turn the preview into a tested development foundation for preparing Oracle packages and controlling future system changes, without using the user's PC.

**Architecture:** Keep AutoIt as the launcher and leave the inherited runtime quarantined. Python tools prepare verified files and exercise offline failure cases; native AutoIt tests cover reusable lifecycle policies. Package extraction must not install an MSI, start VirtualBox, or register drivers. Prefer passive extraction over GUI automation.

**Tech stack:** AutoIt 3.3.18.0, Python standard library, PowerShell 7, isolated GitHub Actions Linux/Windows runners.

**Spec:** `docs/MODERNIZATION-2026.md` and `docs/SECURITY-MODEL.md`.

## Global constraints

- Resume `dev/modernization-2026` at `3556db90e438c347e47857da9b1dba3db2164283`, based on original upstream `5b58dbbe`.
- Preserve `master`, `archive/legacy-zlocorp-2020`, and `work/upstream-baseline-2026`.
- No wholesale fork imports, license changes, driver installation, live VM mutation, automatic merge, or release.
- Target Oracle VirtualBox 7.2.x, not an implicit promise of 7.2 runtime compatibility.
- Repository and verified CI artifacts are the evidence. Green investigation is not successful extraction unless actual output checks pass.

## Review focus

1. A destination or partial file appears during a download: no overwrite or deletion of another operation's file.
2. Untrusted manifest, redirect, malformed PE/resource or XML input: fail closed and preserve the original.
3. Service or process identity changes between acquisition and cleanup: deny cleanup; PID equality alone is insufficient.
4. Partial acquisition or interrupted journal: report incomplete/unknown state rather than blindly cleaning it.
5. CI transport or compile success: do not mislabel as Windows 11, driver or VM acceptance.

## Task 1: Verify inputs and establish local regression evidence

Files: existing `scripts/oracle_release.py`, `scripts/vm_inventory.py`, tests, and CI configuration.

- [ ] Read current branch files, run the existing suite unchanged, record baseline.
- [ ] Add failing tests for download destination races, foreign partial files, redirect host changes and malformed input.
- [ ] Implement bounded writes/publication, strict release URL/filename validation, and owner-scoped temporary cleanup.
- [ ] Add XML encoding/DTD and Windows path regression cases; implement only required safety repairs.
- [ ] Run the complete Python suite on Linux and Windows.

Interfaces remain `release_root`, `parse_sha256_manifest`, `find_windows_installer`, `read_manifest`, `download_verified`, `inventory`, `summary`. Optional limits may be introduced without breaking existing CLI usage.

## Task 2: Resolve Oracle package extraction

Files: new isolated extraction helper and tests; `.github/workflows/inspect-oracle.yml`.

- [ ] Inspect Oracle's actual installer source to establish payload format and extraction behavior, rather than guessing command-line switches.
- [ ] Write fixture tests for valid and malformed payloads, bounds, filename traversal, duplicate entries, exact hash and no-overwrite behavior.
- [ ] Implement passive package extraction where the verified wrapper supports it, otherwise document and test a narrowly justified official extraction-only path.
- [ ] Retrieve the pinned Oracle installer in hosted CI, verify checksum and Authenticode, extract to a new staging directory, inspect the MSI metadata without installing it.
- [ ] Check expected output identity, version and architecture and unchanged VBox service state. Retain metadata, not Oracle redistributable payloads.

Acceptance is actual extracted output plus tests and logs; an empty result or timed-out GUI is failure, not success.

## Task 3: Implement a testable lifecycle journal/policy

Files: new AutoIt lifecycle module and native tests; existing safety helpers/preflight as required.

- [ ] Define explicit acquire/confirmed/cleanup/uncertain states; record only successful acquisitions as owned.
- [ ] Write native failing tests for existing resource, failed creation, changed identity, duplicate acquisition, reverse-order cleanup and retry after failure.
- [ ] Implement reusable lifecycle decisions without wiring unsafe legacy service commands back into the launcher.
- [ ] Run the same AutoIt implementation in a nonprivileged compiled test executable on hosted Windows.

Acceptance is the real policy implementation tested against synthetic resources. Windows service/driver adapters remain a separate gate and are not implied complete.

## Task 4: Integrate evidence and update the existing draft PR

- [ ] Strengthen CI timeouts, credentials scope and result checks; include native tests and source snapshots for review.
- [ ] Verify final code tree, unit suite, x64 compilation and native checks on the final executable-code commit.
- [ ] Record exact commits, run/job links, executed test counts, extraction outcome and remaining runtime work.
- [ ] Update draft PR #7 without merging it. Keep preview protections active.

## Execution ledger

- Plan created before this iteration's implementation. Existing roadmap is the approved scope; no repeated approval request.
- Local direct git clone could not resolve github.com. Use authenticated connector and a scoped CI source snapshot; this is an execution transport constraint, not a repository access failure.
- Current state: tasks pending; no new test or extraction outcome is claimed by this plan.
