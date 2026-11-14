# Accepted test-only checkpoint: query-only sentinel observation

## Source, review and result

Independent review accepts the bounded sentinel fixture at
[`519056432b4d9bd045140d2ba2bbe924e5c135e9`](https://github.com/zlocorp/Portable-VirtualBox/commit/519056432b4d9bd045140d2ba2bbe924e5c135e9),
tree `45d21240a2b93e79f69b7a0c415d34ed7acdd31f`.
All **11 naturally triggered workflows succeeded on attempt 1**: eight PUSH and
three PR. No rerun, cancellation or manual dispatch was used.

The preflight design was reviewed and revised before implementation. The pure
parser/PVC2/query-state stage passed independent review before the real adapter,
parent and child composition began. Independent composition and final integration
reviews found no blocking issue. One minor fixture-fidelity finding was then
corrected: the managed Binary-owner test now supplies its complete 4,105 stdout
and 257 stderr bytes rather than a short body. That one-file test-only correction
passed a demonstrated failing assertion followed by **32 focused tests and the
expanded managed host**, and a final scoped re-review. Runtime code did not
change in that correction.

The earlier local broad run was **403 tests, six existing platform skips** before
that last correction. The two hosted Linux runs below supply full **403/6**
coverage of the final published source/tree; the focused rerun is not presented
as another local full-suite run.

This accepts a test-only observation increment. Fixed-image file-to-child
composition remains unimplemented and requires its separate review. Production
outer-worker/nested VBoxSDS lifetimes, general cleanup retry, workstation acceptance,
merge and release gates remain open.

## Complete natural CI inventory

| Workflow | Trigger | Run | Result |
| --- | --- | --- | --- |
| Native AutoIt policy regressions | PR | [43101344284](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284) | Success, attempt 1 |
| Portable-VirtualBox CI (build only) | PR | [43101344275](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344275) | Success, attempt 1 |
| Verified Oracle package preparation (no installation) | PR | [43101344488](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344488) | Success, attempt 1 |
| Commit-bound source snapshot | PUSH | [43101336018](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101336018) | Success, attempt 1 |
| Noninteractive UAC pending (no consent acceptance) | PUSH | [43101335987](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335987) | Success, attempt 1 |
| Native AutoIt policy regressions | PUSH | [43101335942](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942) | Success, attempt 1 |
| Exact-owned orphan cleanup after abandoned controller (no UAC acceptance) | PUSH | [43101335977](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335977) | Success, attempt 1 |
| Portable-VirtualBox CI (build only) | PUSH | [43101336031](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101336031) | Success, attempt 1 |
| Guarded rollback after interrupted VBox driver preparation (disposable host) | PUSH | [43101335959](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335959) | Success, attempt 1 |
| Fixed helper with medium user processes (no UAC acceptance) | PUSH | [43101335929](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335929) | Success, attempt 1 |
| Private payload cleanup continuation (disposable host) | PUSH | [43101335826](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335826) | Success, attempt 1 |

The inventory is for the full source SHA and includes PUSH and PR workflows.
Detailed artifact acceptance below covers both native jobs and both Linux static
jobs. Other workflow conclusions are recorded without claiming a new detailed
audit of all their system-effect artifacts.

## Actual checkouts and Linux prerequisites

- Native PUSH [job 130793309130](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942/job/130793309130)
  checked out the exact published source SHA.
- Native PR [job 130793320428](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284/job/130793320428)
  checked out synthetic merge `9f34ce5dd52ad9cb83002b7d23cc51f9e15745f2`.
  Its [Git commit object](https://api.github.com/repos/zlocorp/Portable-VirtualBox/git/commits/9f34ce5dd52ad9cb83002b7d23cc51f9e15745f2)
  has parents `5b58dbbe701c3e2eb348942a9059708063b0cb96` and the published
  source, with the identical tree `45d21240a2b93e79f69b7a0c415d34ed7acdd31f`.
  Tree equality relates the evidence; the PR checkout is not labelled a PUSH head.
- Both native jobs used Windows Server 2022 Datacenter `10.0.20348`,
  image `windows-2022/20261101.353.1`, runner `2.338.2`.

Linux PUSH [job 130793303424](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101336031/job/130793303424)
and PR [job 130793332966](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344275/job/130793332966)
show the same direct-source/synthetic-merge checkouts. Both actual Ubuntu 24.04.5
logs invoke the pinned net48 provisioner before discovery and export its verified
reference path. Results are **403 tests in 56.629s, OK (skipped=6)** for PUSH and
**403 in 44.017s, OK (skipped=6)** for PR. The six skips remain the existing
Windows cabinet, payload and Windows PowerShell execution cases; no sentinel,
image or provisioner contract was skipped.

The [accepted provisioner contract](EXECUTION-2026-11-11-net48-reference-provisioning.md)
is unchanged. Hosted package/DLL bytes are not separate artifacts: provisioning
evidence is the exact reviewed fail-closed code, successful actual invocation,
export and downstream compilation/tests, not an independent hosted-file rehash.
Both build workflows' compile jobs also succeeded.

## Artifact integrity

All ten full ZIP downloads match the GitHub metadata byte counts and SHA-256
digests, also present in the actual upload logs. ZIP CRC checks pass. All
downloaded JSONL records match their corresponding actual native job log records.
The unchanged strict capture/environment/image validators accept
`require_pass=True`; the pipe validator also passes. Synthetic managed serializer
examples are not counted as native cases.

| Trigger | Artifact | ZIP bytes | SHA-256 |
| --- | --- | ---: | --- |
| PUSH | [native-launch-observation (13893155682)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942/artifacts/13893155682) | 10115 | `72c7082c04263f45ebda307a38eadfccfd9fb746862ec51ccc12a73227f67856` |
| PUSH | [native-child-capture-text-only (13892296746)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942/artifacts/13892296746) | 1009 | `efea5803bb24d7f03f896c3d740f659f9ab525aef803778bf9ae585d19963ede` |
| PUSH | [native-pipe-transport-text-only (13890794408)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942/artifacts/13890794408) | 1659 | `d4227191ac00b363698bce62b0c5d613de14e731a29e2bdb330cd609cdb818e3` |
| PUSH | [native-launch-environment-text-only (13890309808)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942/artifacts/13890309808) | 677 | `a90513fe4e7ce5528dbf6d80a10820f138304d8ab0e87a805b4590a2dc8dd640` |
| PUSH | [native-fixed-image-observation-text-only (13890094576)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101335942/artifacts/13890094576) | 966 | `e882a593477f44b51fe2652ffc3ba2aabaf23c626fad4875597c1ff1d246f18b` |
| PR | [native-pipe-transport-text-only (13892851683)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284/artifacts/13892851683) | 1667 | `23714043022224d7de252a3bcb010a32296da89a9f8931e19a7dab50e8a36b39` |
| PR | [native-launch-observation (13892656433)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284/artifacts/13892656433) | 10104 | `95a43d901cfbafb041ecd4e4e8522ad852a7c78b3470fc0bc4b5069d00805bac` |
| PR | [native-launch-environment-text-only (13892491535)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284/artifacts/13892491535) | 677 | `f2cbf041584e98517d70576f8317ed97bf837239132beaab96c8b361011daf9f` |
| PR | [native-fixed-image-observation-text-only (13892466645)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284/artifacts/13892466645) | 967 | `31073a0b5ee6011551aeef877e32a84527eaed215bb15fdb38255278a3529287` |
| PR | [native-child-capture-text-only (13891986413)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43101344284/artifacts/13891986413) | 1011 | `2f169ee2d403fde32f8457e91b63b8420d200c67f819260c363c2d305011a54e` |

## Actual nine capture cases on each run

| Case | stdout bytes / FNV-1a64 | stderr bytes / FNV-1a64 |
| --- | --- | --- |
| Empty | 0 / `cbf29ce484222325` | 0 / `cbf29ce484222325` |
| Binary | 4105 / `031381f5c4fbe740` | 257 / `c98455caf71ceb86` |
| Large, CaptureFault, EvidenceFault | 196739 / `c1f1accadf2339e9` | 204829 / `8b07499bc23a9f3e` |
| Nonzero, Exit259, PostCreateFault, WithheldEof | 25 / `e6a7f5deb30873c0` | 257 / `c98455caf71ceb86` |

These hashes were independently recomputed from the fixed PVC2 literal and
unchanged body rules, not the child's encoder or captured prefix. Artifacts retain
counts/hashes, not raw whole bodies. Empty emits no preamble or stream bytes.
Nonzero exits **23**, Exit259 exits **259**, and the other cases exit **0**.

Every case records both EOFs, parent resource release, no retained owner, one-shot
refusal, one create, positive wait/exit-code reads, equal issued/terminal I/O and
fair stream visits. Both summaries are PASS, nine cases, zero failed, all owners
released. All sentinel probes pass alongside the independent unsignaled parent
event observation.

The four controlled-fault/withheld-EOF cases retain overall **UNKNOWN**.
PostCreateFault/CaptureFault/EvidenceFault retain fault sites 1/2/3; only
EvidenceFault writes one diagnostic byte. CaptureFault and EvidenceFault each
retain eight stdout bytes and discard all 196,731 body bytes while still reaching
the exact full counts/hashes. WithheldEof records blocked EOF before eventual
EOF/release. Passing assertions do not turn these outcomes into OBSERVED.

## Actual Unicode environment and file-only image observations

Each run's three environment cases pass. Actual base64 decodes to a **110-byte
PVE1** record following the eight-byte PVC2 prefix, **118 stdout bytes** and no
stderr. Decoded fields are exactly absent parent sentinel,
`Привет = fixture 🙂`, present empty string, `C:\Windows`, `C:\Windows`.
Both EOFs, exit 0, environment/parent-resource release, parent restoration and
one-shot refusal are recorded. None is OBSERVED; AfterCreate and Evidence remain
UNKNOWN. Evidence fails its diagnostic write at byte 8 and still obtains the
complete observation, with one diagnostic byte written.

All four image cases remain **file-only**, with `create_calls=0` and
`process_observation=null`. Each run freshly builds its pristine **19,968-byte**
expectation: PUSH SHA-256
`37b1514a8800e70d6f8d6e2e45d299be8ec904a4833bf146c2971b2594d3a35d`,
PR `555a99d939a411bd3f3e3b1020d99356768653c569e7bf83604fa397d5ca4c04`.
Separate compiler outputs need not be byte-identical.

Matching and same-size digest-mismatch records include full-byte hashing, native
held-file identity, `fixed-Ж-漢` paths and a one-byte request returning zero at EOF.
The matching digest equals its build expectation; the negative digest differs.
Matching-image write/delete probes use compatible sharing and return native error
32 without acquiring handles. All acquired image handles have checked successful
closes. Size mismatch reports 19,969 bytes without reading; missing image reports
known error 2 with no acquired handle. Both summaries pass all four cases.

The prior pipe stage passes 14 cases/573 checks with all owners released. The
launch stage records 64 managed checks with zero native calls and a native
232-check/11-call PASS. Runtime inspection files are complete downloads but
explicitly report `inspection_status=bounded-truncated`; no full runtime
control-flow attestation is inferred.

## What is and is not established

The native result is the fixture's normalized **EXCLUDED** semantic result
(or Empty's exit-0 equivalent), which requires its owned-reference close.
The JSON `resources_released` field separately retains its parent-owner meaning.
The headers do **not** reveal whether any particular child took
ReferenceAllocatedAtCandidate, CandidateInvalidAtQuery or DifferentObject.
They do not establish native coverage of a particular comparison branch or
error 1656. Deterministic managed models and real-method/raw-call fakes cover
those decisions, freshness/collision refusal, stale errors and uncertain close
paths; they are not native collision/race experiments.

The strict comparison policy was not weakened. Unavailable or unexpected results
remain UNKNOWN. All diagnostics retain `mutation_authorized=false`; observation
does not grant cleanup, admission or retry authority, and is not hostile-child
attestation or a complete historical inheritance census.

The [b2229c5 partial checkpoint](EXECUTION-2026-11-11-native-fixed-image-file-only.md)
is unchanged: its native PR sentinel failure and two Linux prerequisite failures
remain failures, distinct from its successful PUSH. The later 33447ae native PR
pass is also not evidence for PVC2. This new record does not repair production
lifetimes or open the [release gates](RELEASE-GATES.md).

