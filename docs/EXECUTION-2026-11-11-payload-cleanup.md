# Owner-bound private-payload cleanup: hosted execution record

Date: 2026-11-11. Tested source commit:
`b9db2b0ba3cfeecef915e107d3648104da551024`.
This is acceptance of a narrow hosted-tested increment, **not release approval**.
No primary/user Windows host was used. No merge or release was performed.

## Implemented boundary

After a successful, observed system teardown, the fixed helper can durably bind
its original private app64/code objects to a checkpoint and BEGIN/DONE ledger.
Same-controller Finish or absent-original-controller Recover may continue only
that fixed private deletion plan. It never reruns PowerShell or system teardown,
never recreates payload, and retains acquisition/cleanup evidence and VM data.
Original volume/file IDs, creation/type, native ACL, hashes and retained handles
are required. Unknown presence is not absence; deletion closes the target handle
and verifies native NOT_FOUND before DONE. Parent/root leases stay held.
See [the design](designs/owner-bound-cleanup-resume.md).

The Windows runs also found and fixed two important boundary assumptions:

- Managed FileSecurity hides an inactive inherit-only OWNER RIGHTS ACE on files.
  Validation and negative-test restore now use the exact retained-handle native
  descriptor, not a three-ACE managed projection. The original protected ACL
  creation policy was not relaxed. Medium-token DACL mutation remains denied.
- Metadata-only handles do not enforce the intended Windows rename lease.
  Helper, evidence and CLI ancestry leases now request actual read/list access,
  retain no-share-delete, and have native rename-denial regressions. No new
  write/delete/ACL permission was added.

## Exact-commit results

All 12 triggered workflow runs completed successfully on this source commit.
The important runnable results are:

- [Native Windows regressions, 43013521734](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43013521734):
  33 AutoIt harnesses; CLI 44, journal 3,310, fixed plan 854, native object 25 and
  integrated owner 141 assertions. Actual raw ACLs, wrong owner/ACL, extra or
  replaced files, hardlinks/reparse points, delete-pending, nonempty directories,
  and evidence/session/CLI rename locks are tested.
- [Private continuation, 43013521630](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43013521630):
  AfterFirstDelete resumes through the same controller's Finish; BeforeMarker
  resumes through a new controller's Recover after the original exits. Both
  preserve teardown evidence and VM sentinel data, avoid payload recreation and
  confirm removal of owned services. This fixture does not boot a guest.
- [Fixed helper, 43013521670](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43013521670):
  session-test and main-launcher jobs pass. Main-launcher boots Alpine, verifies
  guest VDI write/readback and snapshot preservation across two clean sessions.
  Manager/guest have medium tokens. Protected writes and live-guest cleanup are
  refused; runtime comes from the protected copy. The session-test variant does
  not claim Linux VDI readback.
- [Orphan recovery, 43013521648](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43013521648):
  live-owner and live-guest refusal; explicit exact-owned recovery and preserved
  original VM data.
- [Interrupted preparation, 43013521762](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43013521762):
  Stage/Start/Sds recovery checkpoints; old-owner, missing/forged-receipt and
  replay refusal; both tamper-stage and tamper-sds retain resources on refusal.
- [Noninteractive pending UAC, 43013521767](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43013521767):
  pending is not completion; no interactive consent acceptance is claimed.

Other successful runs: source snapshot 43013521780, ALPHA build/server refusal
43013521721, file-only Oracle preparation 43013531120, PR native 43013531090,
build push 43013521637 and build PR 43013531094. These are triggered checks, not
an assertion that every workflow in the repository was executed.

Local verification: 295 Python tests, six platform skips with PowerShell
available; journal 3,308 filesystem assertions (Windows sharing tests skipped
on Linux); plan 854; helper and owner fixture compile with C# 5 / .NET Framework
4.8 reference assemblies. Independent review verified the exact Windows runs
and accepted this increment's scope, not workstation/release readiness.

## Retained evidence identities

Downloaded archives were checked against the GitHub artifact SHA-256. Both
proof records name the exact tested source commit above. Artifacts expire
2026-11-18; the run links and this record are not a substitute for retaining
candidate evidence before a future release decision.

- Payload artifact `13852315498`, `payload-cleanup-recovery-evidence`:
  `99d12a316bd366d6bfc499d42ea031227c08a009c53707aea178946b9b208fc5`.
  Proof: both controlled cases completed, cleanup evidence unchanged,
  no payload recreation, original VM data preserved, all owned services removed.
- Main-launcher artifact `13851792246`, `fixed-helper-boundary-evidence-main-launcher`:
  `c2de0a64876ee99488a723866471778a9b008b5f27f26b08cac5071d9af3b8c7`.
  Proof: guest boot/disk/snapshot, medium-token boundary, protected-write denial,
  live-guest refusal, two clean cycles, portable CLI and durable journal checks.

These are direct-elevated test-invoker fixtures. GUI runas and interactive UAC
consent are explicitly false/unverified. The guest is started by the controlled
VBoxHeadless fixture; VBoxManage headless spawning is not thereby verified.

## Failed runs preserved

Do not reinterpret earlier failures as accepted tests or delete their evidence.

- At `3f3839b`, [orphan run 43011438064](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43011438064)
  failed during Prepare after VBoxSup ran: the expected VBoxSDS registry entry
  was absent after its registration command. Its cause is unresolved; the old
  collector omitted SDS output. No live-guest/recovery success is claimed for
  that run. Bounded SDS output collection was subsequently added.
- At `a6b81ad`, [orphan run 43012361086](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43012361086)
  prepared successfully but failed guest creation with Oracle
  `VERR_NEM_VM_CREATE_FAILED`. Recovery/cleanup was not verified by that run.
- Earlier native failures exposed the raw-ACL projection and metadata-only
  lease assumptions described above. They were corrected and rerun on the
  exact final code checkpoint, not dismissed as flaky checks.

## Remaining limits and next step

General system-effect retry is still blocked. One-shot proof/cleanup directories
can strand a refused or partially executed SDS/SCM/PnP attempt. A successful
worker followed by failure before the new durable payload checkpoint is also
unsupported. Cleanup JSON alone, same-name services, matching binary hashes or
an outstanding intent cannot reconstruct ownership or certify completion.

Missing/torn checkpoint or journal, replacements, unknown observations and an
abandoned mutex refuse continuation. Physical power-loss recovery is not
certified. Complete old sessions with their original paired build before an
upgrade; never remove protected receipts to bypass a mismatch.

The next increment starts with a separately reviewed system-effect protocol and
safe tests. No new retry authority is granted until resource continuity, durable
outcomes and child lifetime are proved. Isolated Windows 10/11 consent/denial,
UI scaling, candidate packaging, relocation and final host checks remain in
[the release gates](RELEASE-GATES.md). Multi-VM mutation, USB and updater behavior
are outside scope.
