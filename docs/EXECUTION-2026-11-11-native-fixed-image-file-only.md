# Partial checkpoint: exact-source PUSH file-only image observations

## Status and scope

**Accepted scope: the exact-source PUSH file-only fixed-image observations only.**
The full checkpoint has **eight successful and three failed workflow runs**, all
on attempt 1, with no reruns. The failed build and native PR results remain
failures. This report does not accept the whole checkpoint, open the Task 2
composition gate, or establish production admission or release readiness.

The observed source is
[`b2229c53213470ec030dd5944416e9b25ccfe414`](https://github.com/zlocorp/Portable-VirtualBox/commit/b2229c53213470ec030dd5944416e9b25ccfe414),
with tree `345a370528010753e44ca95612a0aa3172ec63dc`. That tree matches the
independently reviewed implementation. Results below belong to this source;
later corrections require their own source-bound review and evidence.

The [fixed-image design](designs/native-fixed-image-observation.md) remains
test-only. This stage observes an owned harmless sibling file and never launches
that fixture child. The runner invokes the four fixed file-only harnesses.
Earlier child-capture and environment stages in the same job do launch their
existing harmless children; the zero-child-creation claim applies to the new
fixed-image stage.

## Exact native PUSH provenance

- [PUSH run 43090280267](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280267),
  [job 130765203647](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280267/job/130765203647),
  attempt 1, completed successfully.
- The actual checkout log records
  `b2229c53213470ec030dd5944416e9b25ccfe414` from `git log -1 --format=%H`
  at **2026-11-11 19:46:25.9042717 UTC**. GitHub run and commit metadata agree
  on the source and tree.
- Hosted Windows Server 2022 Datacenter, OS `10.0.20348`, image
  `windows-2022` version `20261101.353.1`, runner `2.338.2`, Azure westus2.
  The fixed-image step used Windows PowerShell through
  `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.EXE`.
- The run started at **19:46:16 UTC**. The fixed-image step began at
  **19:47:39.9789919 UTC**; its four actual case records appeared between
  **19:47:41.3140150 and 19:47:41.4688618 UTC**. Its PASS summary appeared at
  **19:47:41.4739621 UTC**, and both artifact-validator passes completed by
  **19:47:42.0044138 UTC**. The artifact finalized at **19:47:43.5180629 UTC**.

## Bounded artifact verification

The downloaded
[fixed-image artifact 13888596522](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280267/artifacts/13888596522)
is `native-fixed-image-observation-text-only`. Its **963-byte ZIP** contains
exactly `native-fixed-image-observation.jsonl`.

- ZIP SHA-256:
  `a78800ca5854d6e9341ad979f3cbc55348cd96fa3f9ad59f35c141e604efd06c`.
  The downloaded bytes match both GitHub artifact metadata and the actual upload
  log.
- JSONL SHA-256:
  `25a511e98687df8641f10ef8b28273d5ac60e65ce816655228af7228d71af2ed`.
- JSONL size: **3,446 bytes**. Its five newline-terminated records occupy
  1,137, 911, 630, 620 and 148 bytes, within the separate artifact bounds.
- The exact-source validator accepts the downloaded artifact with
  `require_pass=True`. All four case records and the summary match the actual
  job-log records. Separately labelled synthetic serializer and probe diagnostics
  are not being counted as native case evidence.

The JSON wire is ASCII-safe UTF-8. Decoding its escapes preserves the actual
Cyrillic/CJK directory segment in both fully observed paths:

```text
\\?\C:\Users\runneradmin\AppData\Local\Temp\pvbox-fixed-image-build-16a902e51841448d8d3b730843606550\fixed-Ж-漢\matching-image\NativeCaptureFixtureChild.exe
\\?\C:\Users\runneradmin\AppData\Local\Temp\pvbox-fixed-image-build-16a902e51841448d8d3b730843606550\fixed-Ж-漢\digest-mismatch\NativeCaptureFixtureChild.exe
```

Neither path contains character substitution from console transport. The size
and missing-image cases correctly leave paths and identity observations null
because their observations stop earlier.

## Four actual file-only observations

All four harnesses report the same compiled pristine expectation:

- Size: **11,776 bytes**.
- SHA-256: `1e91e99349b19786b50157eece6a89627489ac118329f9d2300edd514a2d0b37`.

The reviewed build sequence generates that expectation from the completed
pristine harmless child, compiles it unchanged into all four harnesses, and only
then prepares isolated negative copies. These text artifacts do not independently
attest the compiler or supply a downloaded pristine executable for rehashing.

1. **Matching image: PASS.** Actual size is 11,776 and actual SHA-256 equals the
   pristine expectation. All 11,776 bytes were hashed, `read_state=complete`, and
   the positive one-byte terminal read returned zero bytes. Native open and
   checked native close both returned success. The volume serial is
   `04a0a9caa0a9c312`; file ID is `a8e01200000005000000000000000000`.
   The separate `GENERIC_WRITE` and `DELETE` probes both used share mask 7 and
   `OPEN_EXISTING` disposition 3. Both returned failure/error 32 with
   `close_state=not-opened`.
2. **Same-length digest mismatch: PASS.** Actual size remains 11,776 and the full
   hash comparison was reached. Actual SHA-256 is
   `c341a489ec3aa250645f1ac8b639e4c48510b91ece077f7dc261cdb32d8dcbd7`,
   distinct from the embedded expectation. All 11,776 bytes were hashed with the
   same one-byte/zero-byte EOF proof. Native open and checked close succeeded.
   The file ID is `cbe01200000005000000000000000000` on the same observed volume.
   No sharing probes ran.
3. **Size mismatch: PASS.** Actual size is 11,777, producing a distinct size
   refusal. Reads were not entered, bytes hashed is zero, and actual digest and
   EOF observations remain null. Native open and checked close succeeded.
4. **Missing image: PASS.** Native open returned failure/error 2. No handle was
   opened, no reads or probes ran, and unavailable file observations remain null.

Every case reports `stage=file-only`, `create_calls=0`,
`process_observation=null`, and `mutation_authorized=false`. The ordered summary
is PASS with four cases, zero failures and `stop_reason=none`. Native close proof
comes from the reviewed checked `CloseHandle` path and its return evidence;
managed disposal and process teardown are not substituted for that proof.

## Previous nine plus three cases on PUSH

The same PUSH job records all nine existing child-capture cases PASS: `Empty`,
`Binary`, `Large`, `Nonzero`, `Exit259`, `PostCreateFault`, `CaptureFault`,
`EvidenceFault` and `WithheldEof`. Their summary reports nine cases, zero failures,
and all owners released. The three environment cases, `None`, `AfterCreate` and
`Evidence`, also pass with all owners released and the parent sentinel restored.
Each environment observation decodes to a **110-byte PVE1 record**; the separate
stdout byte counter is 118.

The downloaded artifact digests were checked against GitHub metadata:

- [PUSH child capture 13887388614](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280267/artifacts/13887388614):
  `25f6ada5a807014a912dca398c01e03f2e57f3487fdcf3f8d6ff017b23869cd2`.
- [PUSH environment 13887163941](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280267/artifacts/13887163941):
  `27d94d371b6332cbf2626e8c3e592dd0d7149c666caf7dc15e769f8f8c42f66e`.

These PUSH passes do not replace the failed PR observations below.

## Failed PR native run and numeric sentinel limitation

[PR run 43090294982](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090294982),
[job 130765254992](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090294982/job/130765254992),
failed at child-capture step 16. The environment and fixed-image execution and
upload steps were skipped. **There is no PR fixed-image evidence for this source.**

The actual PR checkout was synthetic merge
`5a41040734c3157b0618fcf968d14d3d151421dc`, merging the published source into
`5b58dbbe701c3e2eb348942a9059708063b0cb96`. GitHub reports the same tree
`345a370528010753e44ca95612a0aa3172ec63dc` for that merge.

[PR child artifact 13889290271](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090294982/artifacts/13889290271)
has verified ZIP SHA-256
`388227e8018b7fac7e907344f62da7ad5300ad564d7690e919501a2f369d86ee`.
It reports nine cases, two failures, and all owners released. `CaptureFault` and
`EvidenceFault` both fail assertion 4, the conjunction of `SentinelProbe` and
`SentinelUnsignaled`, with `sentinel_probe=false` and
`sentinel_unsignaled=true`. Their child exit, both EOF observations and resource
release completed. Their overall result remains `UNKNOWN`.

The observed stdout hash in both failures is `65cdac9628e12ef6`. Offline
reconstruction of the fixed body matches that hash when the child's probe
preamble reports a successful `SetEvent`; the expected FALSE/error-6 preamble
instead produces `545bbadcfe91085b`. The separately observed retained parent
sentinel remained unsignaled. The artifact records the hash, not raw preamble
bytes or the identity of the child object.

Numeric handle reuse is the supported explanation, not a directly observed
identity match: a parent-process handle number can identify an unrelated
child-local object. This is the conservative-failure limitation already noted in
the [child-capture design](designs/native-child-capture.md). The result does not
establish inheritance of the parent sentinel, and the probe is not a census of
all inherited handles. No unrelated child object can be named from this evidence.
The later `one_shot_refused=false` also does not demonstrate a one-shot defect:
assertion 4 stops the case before that assertion is exercised.

The failed PR artifact remains valid failure diagnostics and is rejected by
`require_pass`. No rerun, timeout increase or weakened assertion was used to
replace this outcome with a pass.

## Complete workflow inventory for this source

All eleven runs completed on attempt 1. Seven PUSH runs and one PR run succeeded;
one PUSH run and two PR runs failed.

| Workflow | Trigger | Run | Result |
| --- | --- | --- | --- |
| Commit-bound source snapshot | PUSH | [43090280141](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280141) | Success |
| Exact-owned orphan cleanup | PUSH | [43090280212](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280212) | Success |
| Fixed helper with medium user processes | PUSH | [43090280140](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280140) | Success |
| Guarded interrupted-preparation rollback | PUSH | [43090280254](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280254) | Success |
| Native AutoIt policy regressions | PUSH | [43090280267](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280267) | Success |
| Noninteractive UAC pending | PUSH | [43090280243](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280243) | Success |
| Private payload cleanup continuation | PUSH | [43090280196](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280196) | Success |
| Build-only CI | PUSH | [43090280360](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090280360) | Failure |
| Verified Oracle package preparation | PR | [43090294937](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090294937) | Success |
| Native AutoIt policy regressions | PR | [43090294982](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090294982) | Failure |
| Build-only CI | PR | [43090294963](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43090294963) | Failure |

Both build-only failures lack the mandatory `PVBOX_TEST_NET48_REFERENCES` input
for managed compilation against the official .NET Framework 4.8 references.
Those failures remain part of this checkpoint; a later build-configuration fix
cannot retroactively make these runs pass.

## Remaining gates and unproved properties

Whole-checkpoint acceptance and Task 2 remain blocked. Corrections to the build
configuration and the separately reviewed numeric sentinel diagnostic require
their own results; skipped PR stages require actual native evidence before they
can be accepted.

The accepted file-only observations do not attest the build, ancestors, ACLs,
dependencies, CLR, signatures or loaded process-image bytes. Sharing denial
describes ordinary new leaf opens, not every possible modification mechanism.
There is no new production launcher, privileged image admission, primary-host
acceptance, merge or release approval. The existing [release gates](RELEASE-GATES.md)
remain unchanged.
