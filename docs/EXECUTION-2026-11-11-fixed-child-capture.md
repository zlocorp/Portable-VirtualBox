# Fixed-child capture execution record

Date: 2026-11-11. Source commit
`50262c86658ce99453845a021786b781d68aae87`, tree
`fbd47a53e549db1af4f6ac94f82ffe83ca0d6a79`.
This is a test-only hosted observation, not production integration or release approval.

## Implemented and locally verified

The new fixed harmless C# child writes synchronous binary stdout/stderr into two
preconnected pipes. The parent uses the earlier unchanged overlapped slots, roots
its native owners before launch, retains original process/thread handles and
limits inheritance to stdin NUL and the two writers. Capture is bounded to 64 KiB
per stream and continues draining/discarding after controlled diagnostic faults.

Nine cases exercise genuine empty streams, binary/large output, nonzero and 259
exit codes, post-create setup/capture/evidence faults, and a retained duplicate
writer withholding EOF after actual child exit. The selected fault site, actual
one-byte diagnostic write return, native call counts and per-stream counts/hashes
are separate observations. No serialized report authorizes release or mutation.

Independent source review accepted the test-only increment. Two managed RED/GREEN
cycles covered unknown create return and one-shot transition refusal. The final
local suite passed 345 Python tests with six platform skips; both new executables
compiled C# 5/x64 against official .NET Framework 4.8 references with warnings as
errors. PowerShell syntax, active-tree, enforced source audit and whitespace checks
passed. Linux did not run the Windows native cases.

## Hosted run ledger

The independently rechecked GitHub source-head inventory contains **11 naturally
triggered workflows, all successful on attempt 1**: eight push and three PR runs.
There was no rerun, cancellation or manual dispatch. This is the full associated
run inventory, not every workflow in the repository and not a claim for later
documentation commits.

- Native push: [43077242025](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077242025),
  job [130720183693](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077242025/job/130720183693).
- Native PR: [43077254540](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077254540).
- Build push: [43077241629](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077241629).
- Build PR: [43077254499](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077254499).
- Oracle preparation PR: [43077254383](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077254383).
- Source snapshot: [43077241833](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077241833).
- Interrupted preparation: [43077241827](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077241827).
- Private payload continuation: [43077241649](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077241649).
- Orphan recovery: [43077241610](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077241610).
- Fixed helper: [43077241592](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077241592).
- Noninteractive pending UAC: [43077241634](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43077241634).

The native push checkout is the exact source commit. The native PR job
`130720226465` checked out synthetic merge
`cc47573496fad6d6133b3e17c9d818c77c6f2337` of that source into base
`5b58dbbe701c3e2eb348942a9059708063b0cb96`. Workflow head SHA alone is not
checkout evidence. Both native runs passed on attempt 1.

## Independently checked native evidence

Both jobs ran Windows Server 2022, build 10.0.20348, with Windows PowerShell.
Their actual fixed-child steps succeeded, taking approximately 3.66 seconds
(push) and 3.58 seconds (PR), including compilation/validation in that step.
The child artifact does not independently record its loaded CLR version.

Each artifact contains only `native-child-capture.jsonl`: 8,146 bytes, ten strict
records and a maximum line length of 913 bytes. Both downloaded ZIP digests match
GitHub metadata/upload logs, and their JSON records exactly match execution logs.

- Push artifact `13880429900`, ZIP 1,012 bytes: SHA-256
  `ba6dfa473721f5cabac025fc480fe9477bd08158425dcaaf07e8cfd7837a662f`.
  JSONL SHA-256:
  `44b58fd70879b6818a239b428513e4d9bc247f801e3b4fec184a262e383060bc`.
- PR artifact `13882148341`, ZIP 1,011 bytes: SHA-256
  `af9b982ad2f96a2fb4ae83541290bd05fc7bd8a240bb3abb19dcffa53c50e15a`.
  JSONL SHA-256:
  `e019c4f2ff4a91f977bf25acab12cd7c798c147d9c9fbb583ce287313249b58f`.

Independent review recomputed the bytes and streaming FNV-1a hashes of all 18
streams in each run. Empty observed zero bytes on both streams, exit 0 and both
EOFs. Nonzero observed exit 23; Exit259 observed a signaled exact process and
exit code 259 with completed capture. Post-create/capture/evidence cases reached
fault sites 1/2/3; only EvidenceFault recorded the one-byte write return.
CaptureFault and EvidenceFault each retained eight stdout bytes and discarded
196,731 more while hashing the full stream.

WithheldEof observed the duplicate writer preventing EOF after child exit, then
actual EOF and explicit release after the duplicate closed. UNKNOWN remained
sticky. Every case reported one create, one successful exit-code observation,
equal issued/terminal reads, fair visits with maximum gap one, both EOFs and
explicit owner release. Every record has `mutation_authorized=false`.

These are observations for the fixed owned fixture. FNV-1a is a data-integrity
check, not authentication. Preserve archives with their run/source/digest
association because hosted artifacts expire.

## Limits retained

The fixture inherits ambient environment, launches only its fixed sibling image,
and has no descendants. The held image leaf does not attest trusted ancestry,
loaded bytes, configuration or dependencies. A numeric sentinel probe is a bounded
fixture check, not a general inheritance census. Empty infers its probe result
from its dedicated exact exit-code branch; the other cases carry a binary preamble.

Known-return terminal I/O and confirmed handle closes remain necessary for explicit
release. Unavailable native submission, persistent wait failure, real OOM and
power loss are not native fault observations. Retaining an unresolved owner until
harness teardown is fail-closed retention, not completed cancellation or cleanup.

Neither `SessionHelper.Main`'s exceptional Process.Start/capture/wait gap nor the
nested VBoxSDS start-before-handle gap is repaired. General system-effect retry,
admission, lineage, interactive Windows 10/11 UAC, DPI/security/final-host checks
and final-candidate packaging remain independent release gates. No primary Windows
host, valuable VM, merge or release was involved.
