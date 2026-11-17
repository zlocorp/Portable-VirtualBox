# Native pipe transport and launcher messages execution record

Date: 2026-11-11. Tested source commit:
`c42ce9791925c40dce5c9b6e987a125515eaa3aa`, tree
`dbc34ac011beb99dbfc310ec8b4b0d9a344437ad`.
Independent final review accepted the **test-only hosted transport observation**.
This is not production integration, workstation acceptance or release approval.

## Scope and source-associated checks

Two commits were published in one branch update:

- `d49314f8c3cd303136d6eb20595f0dff6e08c7cd` clarifies Russian/English
  ordinary-versus-ALPHA explanations and create/verify/restore backup messages.
  Source changes pass a display-mode argument and select explanatory text; the
  readiness codes and actual backup/runtime gates are unchanged.
- `c42ce9791925c40dce5c9b6e987a125515eaa3aa` adds the test-only bounded
  two-pipe fixture, its contracts, native CI step and documentation. It changes
  no privileged helper, worker or system-operation code.

Local verification passed: 324 Python tests total, with six platform skips;
source audit with `--enforce`; active-tree and whitespace checks; and C# 5/x64
compilation against official .NET Framework 4.8 reference assemblies with
warnings as errors. Linux ran the managed decisions, not Windows native I/O.

**All 17 naturally triggered workflow runs passed on attempt 1**, associated
with the source head SHA above, with no rerun, cancellation or manual dispatch.
The GitHub runs API was independently rechecked using the exact `head_sha`
filter: 14 push runs and three pull-request runs, all successful at attempt 1. Push runs checked out that source commit; PR runs use a
synthetic merge checkout and are not direct execution of the source commit:

- Build PR [43036309104](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036309104).
- Oracle preparation [43036309111](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036309111).
- Native PR [43036308877](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036308877),
  job [130575924719](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036308877/job/130575924719).
- Interrupted preparation [43036296720](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296720).
- Orphan recovery [43036296492](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296492).
- Build push [43036296469](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296469),
  job [130576167026](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296469/job/130576167026).
- Fixed helper [43036296716](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296716).
- Source snapshot [43036296631](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296631).
- Offline preparation [43036297038](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036297038).
- ALPHA packaging [43036296723](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296723).
- Noninteractive pending UAC [43036296799](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296799).
- Portable session/SDS [43036296793](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296793).
- Empty VM/driver [43036296737](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296737).
- Native push [43036297288](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036297288),
  job [130575882714](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036297288/job/130575882714).
- Russian Oracle/Alpine [43036296393](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296393).
- Private payload continuation [43036296715](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296715).
- Manager GUI [43036296361](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43036296361).

This is the complete naturally triggered run ledger for this update, not every
workflow in the repository. These results identify the tested source checkpoint,
not later documentation commits or a final release candidate.

The native PR job checkout log explicitly records synthetic merge
`5a1e6f2f4d94a318e05c45e1214a7626b8560f2a` of the source head into base
`5b58dbbe701c3e2eb348942a9059708063b0cb96`. No identical-tree claim is
made here. The native push job executed the exact source head. Workflow/artifact
`head_sha` metadata associates a run with a PR source head but alone does not
identify its checked-out revision.

The hosted Windows observations ran on **Windows Server 2022, build
10.0.20348**, not Windows 10/11 workstations. The actual payload-continuation,
main-launcher helper/Alpine, Manager GUI and Russian Oracle/Alpine test steps
completed successfully, not just their workflow wrappers. This does not mean
every optional step ran: the helper's session-test flavor intentionally skips
its Alpine ISO fetch.

## Native transport evidence

Push artifact `13862379933`, `native-pipe-transport-text-only`, contains only
`native-pipe-transport.jsonl`: 20,731 bytes and 16 strict UTF-8 JSON records.
The downloaded ZIP SHA-256 is
`7bf33f7c506b8b7aa6a965e2c7dbab332770394b811e5d192cbaa1e1a57bdc31`.
The GitHub API's artifact `workflow_run.head_sha` identifies the full tested
source commit above. Retain the archive with its run/SHA/digest association;
hosted artifacts are not permanent evidence storage.

The report contains 85 managed decision checks, 14 native case records and a
summary of 573 separate native/harness checks. Those 573 checks do not include
the 85 managed checks. Review independently recomputed streaming FNV-1a hashes,
byte counts, issued/terminal counts, fair visits and release facts. The cases
observed 2,078,127 bytes in total. Every record has
`mutation_authorized=false`.

- Empty, short, exact-4-KiB and binary cases exercised exact counts and EOF;
  prefilled reads completed immediately and empty reads actually pended.
- Large and backpressure cases drained both streams past the 64-KiB retention
  limit. The backpressure case observed both current writes as incomplete
  before any reads, with six exact result queries across 16 ms in the push run
  and a 10-ms observation in the PR run. Historical pending returns alone were
  not counted as this evidence.
- The hot-stream case read the other stream's small marker before the hot
  stream finished. Both readers and producers were visited every owner round.
- Both injected diagnostic fault sites were reached. The affected stream
  retained its first 4,096 bytes, then discarded while both streams continued
  draining. The evidence-write fault followed 16 actual diagnostic bytes.
  Overall UNKNOWN remained sticky after successful terminal I/O and release.
- A retained duplicate writer actually withheld EOF. Closing it allowed actual
  EOF, but did not erase the earlier EOF-budget UNKNOWN.
- `CancelBefore` and `OneStreamFailure` observed successful cancellation
  requests and terminal `ERROR_OPERATION_ABORTED` (995). The second stream
  continued draining in the one-stream failure case. `CancelAfter` observed
  `ERROR_NOT_FOUND` (1168) after completion and terminal success (0).
- `CancelRace` observed the completion-winning outcome, 1168/0, in both runs.
  The abort-winning race branch was **not observed**. Separate pending-read
  cancellation cases establish abort results, not both outcomes of this race.

Every native case reported exact terminal completion and explicit fixture
release, including its duplicate writer where present. This is evidence for
owned, fixed, in-process producers only. Unknown submission, uncertain close,
stale generation, error 232 and partial-setup decisions are managed negative
tests, not induced native failures. No actual OOM, persistent native WAIT_FAILED
or power loss was reproduced. FNV-1a checks accidental byte corruption, not
authenticity or ownership.

## Russian/English message evidence

The native jobs ran 34 AutoIt harnesses, including
`test_launcher_messages` with 75 checks and zero failures. Mode-specific
explanations and backup action messages were checked without changing dispatch,
readiness status or cleanup authority.

The build executed `scripts/check_offline_backup.ps1` against the compiled
launcher. Strict output assertions passed for Russian and English backup
creation and verification, distinguishing creation from verification-only
success. This is actual CLI execution, not merely a source-string assertion.

Build artifact `13863815350` contains the compiled launcher RU -> EN -> RU
screenshots and their JSON observations. Its downloaded ZIP SHA-256 is
`16ccec9c6cc4d8f2fe37a0f74672001fb941ed699e6095764d6c140b2c4c64cd`.
All three screenshots were visually inspected: text and buttons were readable
at runner DPI, and the changed ordinary-mode warning fit. No ALPHA-dialog pixel
inspection, 100%/150%/200% scaling result or interactive UAC acceptance is
inferred from these images or the message contracts.

## Remaining release gates

The test fixture launches no child, inherits no handles and establishes no
production environment, admission or descendant-lifetime boundary. The
`SessionHelper.Main` Process.Start/capture/wait gap and nested VBoxSDS lifetime
gap remain open. General system-effect retry, cross-attempt lineage and
admission are not granted by successful transport capture.

Isolated Windows 10/11 interactive UAC, DPI/security configurations, final host
condition, power-loss limits and final-candidate packaging remain release
gates. No primary Windows host, valuable VM, merge or release was involved.
Multi-VM mutation, USB and updater work remain outside this increment. See the
[transport design](designs/native-pipe-transport.md),
[implementation ledger](plans/2026-11-11-native-pipe-transport.md) and
[release gates](RELEASE-GATES.md).
