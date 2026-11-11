# Fixed-child capture implementation plan

> **For agentic workers:** Execute task-by-task with TDD and independent review.

**Goal:** Test exact fixed-child lifetime plus bounded fair stdout/stderr capture.
**Architecture:** Immutable previous pipe APIs, new rooted composite native owner,
fixed synchronous writer child, strict observational JSONL and hosted Windows CI.
**Tech Stack:** C# 5 x64 .NET Framework 4.8, Windows PowerShell 5.1, Python unittest.
**Spec:** ../designs/native-child-capture.md

## Constraints and review focus

No production edits, existing prototype edits, merge, release or primary
Windows host. Examine missing return, partial setup, retained duplicate writer,
exit code 259, and faults during capture/evidence. No report is cleanup authority.

- [x] Write managed decision tests: independent exit/EOF/terminal/close requirements,
  one-shot consumption, unknown return retention, sticky fault and fair discard.
- [x] Witness assertion RED with deliberately incomplete decision implementation.
- [x] Implement decisions and witness GREEN on restored pwsh; compile C# 5/net48.
- [x] Add fixed child and owner, native assertions covering all nine cases and
  sentinel exclusion; preserve unknown ownership on all failures.
- [x] Add strict Python parser behavior tests and PS5.1 runner; narrow workflow
  path triggers and text artifact only; keep job timeout six minutes.
- [x] Run full Python suite and active-tree check, compile all new sources against
  net48, inspect diff; distinguish hosted native tests still pending.
- [x] Obtain independent review before branch publication.

## Verification record

Managed decision TDD was witnessed with an intentionally incomplete release
predicate: RED `Unknown create return must retain owner`, then GREEN after the
independent known-return / terminal-I/O / observed-exit predicate was implemented.
A second RED `one-shot refusal` preceded rejecting repeated or premature native
create entry/results; the completed managed contracts then passed. These are
executable behavior tests, not source-text substitutes.

Both new executables compile with C# 5, x64, warnings-as-errors and official .NET
Framework 4.8 reference assemblies. The active-tree check and diff whitespace check
pass. Native Windows execution was pending at local verification; the subsequent
source-associated hosted results below establish the native observation. Linux
compilation and managed tests alone are not Windows observation evidence.

Final local aggregate: `python -X utf8 -m unittest discover -s tests -v` passed
345 tests with 6 platform skips, using the restored PowerShell for managed tests.
The 21 new tests include strict evidence rejection cases and the actual managed
C# report serializer without calling Prepare, Run, or any native API; those
synthetic serializer records are not presented as OS evidence. PowerShell/YAML
parsing also passed.

## Hosted source checkpoint

Source `50262c86658ce99453845a021786b781d68aae87` passed all 11 naturally
triggered workflows on attempt 1. Native push tested the exact source; native PR
tested synthetic merge `cc47573496fad6d6133b3e17c9d818c77c6f2337`. Independent
review accepted both nine-case runs, recomputed all 18 stream counts/hashes per
run and checked observed faults, fair terminal reads and explicit owner release.
The actual child steps took approximately 3.66 and 3.58 seconds on Windows Server
2022. See the [execution record and limits](../EXECUTION-2026-11-11-fixed-child-capture.md).
No production lifetime repair, sanitized environment or workstation approval follows.
