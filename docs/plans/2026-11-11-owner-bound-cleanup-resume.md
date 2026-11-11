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
- [ ] Publish and verify full affected CI; report exact limits.
- [ ] Evaluate the next system-effect increment against durable-generation and child-lifetime limits.

Files owned by the first increment:
- source/privilege/PayloadCleanupJournal.cs: bounded durable step state.
- source/privilege/SessionHelper.PayloadCleanup.cs: owner/checkpoint/plan validation and fixed private-file effects.
- source/privilege/SessionHelper.Main.cs and SessionHelper.cs: narrow dispatch and checkpoint integration.
- scripts/build_session_helper.ps1: compile the new fixed helper sources.
- tests/windows/PayloadCleanupJournalTests.cs and payload helper fixtures: executable behavioral evidence.
- tests/test_payload_cleanup_contract.py and affected workflows: wiring and regression coverage.

Existing DurableJournal, existing replay guards for system effects, and the
read-only reconciliation observer remain non-authoritative for Windows effects.

Local verification: journal 3,308 real-file assertions; plan 854 checks; Python 295 tests, six platform skips with portable PowerShell available. Full helper and owner-gate test entrypoint compile with C# 5 against Microsoft .NET Framework 4.8 references. Native Windows execution and candidate CI are still pending.

Independent static review permits disposable Windows CI, not release acceptance. Full-helper observe/owner tests now include nonempty-directory refusal, preserved BEGIN/child bytes and retained session locks. Native ACL/share/delete-pending behavior awaits the exact published commit.
