# Owner-bound cleanup continuation plan

Goal: continue only proven safe cleanup steps and retain uncertainty.
Design: [owner-bound cleanup continuation](../designs/owner-bound-cleanup-resume.md).

- [x] Trace the existing helper/worker/cleanup ownership and replay boundaries.
- [x] Select a separately authenticated payload-only branch as the first increment.
- [x] Implement and execute the bounded per-object journal tests first, then its implementation.
- [x] Add strict fixed-plan/checkpoint validation and file-only negative tests.
- [x] Integrate checkpoint creation and payload continuation without re-entering system workers.
- [x] Add disposable Windows interruption tests and preserve VM/acquisition evidence.
- [x] Obtain independent review; fix findings with regressions.
- [x] Publish and verify full affected CI; report exact limits.
- [x] Evaluate the next system-effect increment against durable-generation and child-lifetime limits.
- [ ] Specify and test a separate system-effect protocol before granting any new retry authority.

Files owned by the first increment:
- source/privilege/PayloadCleanupJournal.cs: bounded durable step state.
- source/privilege/SessionHelper.PayloadCleanup.cs: owner/checkpoint/plan validation and fixed private-file effects.
- source/privilege/SessionHelper.Main.cs and SessionHelper.cs: narrow dispatch and checkpoint integration.
- scripts/build_session_helper.ps1: compile the new fixed helper sources.
- tests/windows/PayloadCleanupJournalTests.cs and payload helper fixtures: executable behavioral evidence.
- tests/test_payload_cleanup_contract.py and affected workflows: wiring and regression coverage.

Existing DurableJournal, existing replay guards for system effects, and the
read-only reconciliation observer remain non-authoritative for Windows effects.

Local verification: journal 3,308 real-file assertions; plan 854 checks; Python 295 tests, six platform skips with portable PowerShell available. Full helper and owner-gate test entrypoint compile with C# 5 against Microsoft .NET Framework 4.8 references.

Exact published code checkpoint `b9db2b0ba3cfeecef915e107d3648104da551024`: all 12 triggered workflows succeeded. Native Windows: 33 AutoIt harnesses, CLI 44, journal 3,310, plan 854, native-object 25 and integrated-owner 141 assertions. Payload continuation, orphan recovery, interrupted preparation including both tamper cases, and both full-helper frontends passed. The main-launcher fixture booted Alpine and verified guest VDI write/readback, snapshots and two clean cycles. [Execution record](../EXECUTION-2026-11-11-payload-cleanup.md).

Independent review accepted this narrow hosted-tested increment. It does not close general system-effect retry, the worker-success-before-checkpoint gap, interactive UAC or Windows 10/11 acceptance. The next protocol must distinguish a committed effect from an outstanding uncertain intent, and must not transfer authority to a same-name replacement resource.
