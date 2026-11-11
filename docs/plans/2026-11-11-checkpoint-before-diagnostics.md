# Checkpoint before cleanup diagnostics: narrow follow-up

Status: implementation candidate, locally tested; independent review and exact-commit
Windows CI still required. No release or interactive Windows acceptance is claimed.

**Goal:** a failure writing optional helper stdout/stderr/facts must not erase the
opportunity to explicitly continue private payload cleanup after verified system
teardown. Keep failure result 70; do not introduce best-effort success.

**Prior ordering:** `SessionHelper.Main.cs` durably recorded worker exit, wrote three
diagnostic files, checked deadline/exit/controller, then created the payload
checkpoint. A diagnostic write failure can strand a successful teardown without
a checkpoint. This candidate narrows that gap; it cannot eliminate arbitrary
crashes before checkpoint durability or enable system-effect replay.

## Ordering and scope

- Keep the actual worker process handle until its observed exit. Record and
  verify WorkerExited, finish both capture tasks, then determine eligibility.
- Only Finish/Recover with timely zero child exit, a live exact controller and
  the existing successful receipt/ownership/system checks may create a checkpoint.
- Create and reread that checkpoint before diagnostic WriteNew calls. Keep all
  diagnostic failures fail-closed. Do not start private deletion if they fail.
- Failed/unknown workers still attempt the available diagnostic writes and then
  fail; do not lose their stdout/stderr merely because outcome gates moved.
  Diagnostic failure must not replace the original rejection reason.
- On checkpoint/check failure, preserve available diagnostics but do not continue
  deletion. Never rebuild a missing checkpoint from old cleanup JSON.
- Prepare behavior and all owner/build/ACL/retained-child rules remain unchanged.
- The separate explicit Finish/Recover entry may use an intact checkpoint through
  the existing payload-only path, without another system worker.

This uses a small shared sequencing unit actually used by Main, with trusted
compiled operations only, or equivalent tests of the real path. A parallel model
and source-index assertions alone are insufficient. Do not add caller-selected
callbacks, command names, paths, privileges, or a generalized cleanup engine.

## Required executable gates before implementation is accepted

- [x] Worker persistence/capture failure, nonzero exit, missed deadline or departed
  controller never invokes checkpoint creation or payload deletion.
- [ ] Receipt/system-check/checkpoint write/readback failure never invokes Continue.
- [ ] Independently fault stdout, stderr and facts writes after a verified checkpoint:
  result remains 70, checkpoint survives, and private payload is still intact.
- [x] Failed/unknown worker diagnostics remain available; original cause is retained.
- [x] Prepare diagnostic failures retain old behavior and never create this checkpoint.
- [ ] Disposable Windows fixture resumes an intact pre-deletion checkpoint through
  both same-owner Finish and absent-owner Recover. No second worker/system effect,
  receipt change, payload recreation or VM sentinel change is allowed.
- [ ] Independent actual-diff review, C# 5 / .NET Framework 4.8 compile, full source
  suite and exact-commit native/payload/helper/orphan/interrupted CI all pass.

## Local evidence and limits

The private `CompleteCleanupWorker` is called only from the fixed cleanup branch
of Main. Prepare retains its previous sequencing. Executable managed tests compile
and invoke that exact private method, with trusted test-only operation callbacks;
there is no input-selected operation or new recovery entrypoint. Both capture tasks
are drained independently. Primary worker rejection survives diagnostic failures.
A checkpoint-operation exception (including receipt/system checks or its write and
readback) prevents normal return and therefore prevents Main's continuation.

The hosted fixture adds `BeforeStdout`, `BeforeStderr`, and `BeforeFacts` through
the existing CI-only interruption hook. Each has both explicit Finish and Recover
continuation cases. It compares every private payload path and file hash before
and after failure, requires no deletion journal/marker yet, then uses the existing
evidence hash and creation-watcher checks. A seventh diagnostic case starts with
Recover after the original controller has exited, faults before facts, and explicitly
resumes Recover with the same live recovery initiator. Its proof label is
`BeforeFacts-Recover-InitialRecover`; the preceding six diagnostic labels are unchanged.
All seven diagnostic cases have NOT run locally.
The controlled hook throws immediately before the diagnostic write; the managed
sequencing tests separately exercise failures in each write operation.

Local gates: combined Python suite 313 tests OK, 6 platform-specific skips;
464 actual sequencing assertions across 52 cases pass, including double faults.
An in-memory mutation restoring checkpoint-after-diagnostics is rejected. Helper
and file-only fixtures compile against official .NET Framework 4.8 references in C# 5 mode.
The compile-only pin produces the existing unreachable-code warning; Windows
execution, real checkpoint durability and original-owner continuation remain CI
gates. The tests are not evidence of physical power-loss tolerance.

Capture failures and crashes before the checkpoint still retain the old fail-closed
limitation. General SDS/SCM/PnP retry, arbitrary power loss, and interactive Windows 10/11 acceptance
remain separate blockers. No tests are to run on a primary Windows host.
