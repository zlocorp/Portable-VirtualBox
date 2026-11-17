# Partial checkpoint: exclusive fixed-image ownership

## Accepted scope and blocked checkpoint

Independent review accepts the Task 2C source implementation and its limited
native/build proof at
[`6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff`](https://github.com/zlocorp/Portable-VirtualBox/commit/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff),
tree `e8ebd3522f130e7c818148d32136a65112d97e92`. The complete natural inventory
is **10 successes and one failure, all attempt 1**: eight PUSH and three PR runs.
No rerun, cancellation or manual dispatch was used. **The overall checkpoint is
blocked and Task 2D is paused.** The failed payload-continuation run remains a
failure even though both native and build workflows passed.

The limited acceptance covers irreversible single-winner image claims, permanent
facade disablement, live readiness, private lease operations and native-call
forwarding. Actual lease/owner fault checks use **managed recording calls**, even
when executed on Windows. Real file/probe forwarding is separately covered by
four native **standalone file-only** cases. There is **no completed native
image/process composition**. Tasks 2D and 2E remain unfinished, including actual
schema-2 comparison-guard/validator integration. No production lifetime repair,
cleanup retry, workstation acceptance, merge or release follows.

The earlier [build/path checkpoint](EXECUTION-2026-11-11-fixed-fixture-build-paths.md)
remains unchanged. Its 98bec8f results do not certify the new ownership source.
This record describes immutable 6a164db observations, not CI for later documentation
edits. Independent review of this record is required before publication.

## Complete natural workflow inventory

| Workflow | Trigger | Run | Result |
| --- | --- | --- | --- |
| Commit-bound source snapshot | PUSH | [43117916875](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916875) | Success, attempt 1 |
| Native AutoIt policy regressions | PUSH | [43117916926](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916926) | Success, attempt 1 |
| Portable-VirtualBox CI (build only) | PUSH | [43117916934](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916934) | Success, attempt 1 |
| Guarded rollback after interrupted VBox driver preparation (disposable host) | PUSH | [43117917012](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917012) | Success, attempt 1 |
| Exact-owned orphan cleanup after abandoned controller (no UAC acceptance) | PUSH | [43117917038](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917038) | Success, attempt 1 |
| Fixed helper with medium user processes (no UAC acceptance) | PUSH | [43117917129](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917129) | Success, attempt 1 |
| Private payload cleanup continuation (disposable host) | PUSH | [43117917218](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917218) | Failure, attempt 1 |
| Noninteractive UAC pending (no consent acceptance) | PUSH | [43117917252](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917252) | Success, attempt 1 |
| Verified Oracle package preparation (no installation) | PR | [43117926945](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117926945) | Success, attempt 1 |
| Portable-VirtualBox CI (build only) | PR | [43117926977](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117926977) | Success, attempt 1 |
| Native AutoIt policy regressions | PR | [43117927011](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117927011) | Success, attempt 1 |

The [full-source Actions inventory](https://api.github.com/repos/zlocorp/Portable-VirtualBox/actions/runs?head_sha=6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff&per_page=100)
returned total_count=11. Every run has that exact head SHA and attempt 1. Detailed
proof below covers native/build evidence and the failed payload run. Other success
conclusions do not imply a new detailed audit of every system-effect artifact.

## Actual checkouts, runtime and injected-owner checks

- Native PUSH [job 130850584242](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916926/job/130850584242)
  logs the exact published source checkout.
- Native PR [job 130850617051](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117927011/job/130850617051)
  logs synthetic merge `9a004fbba550a1e33c87b02dd7ab0ae8fd16fd26`. Its
  [Git commit object](https://api.github.com/repos/zlocorp/Portable-VirtualBox/git/commits/9a004fbba550a1e33c87b02dd7ab0ae8fd16fd26)
  has the identical source tree and parents `5b58dbbe701c3e2eb348942a9059708063b0cb96`
  and the published source. This is same-tree PR evidence, not a direct head checkout.
- Linux/build logs preserve that same PUSH versus PR-merge distinction. Both
  native hosts are **Windows Server 2022 Datacenter 10.0.20348**, image
  **windows-2022/20261101.353.1**, runner **2.338.2**. They are not the user's
  Windows 10/11 computer.

Each actual native runner log contains exactly one `PASS fixed image injected owners`
line, before all four native file-only case records. The
[exact runner](https://github.com/zlocorp/Portable-VirtualBox/blob/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff/tests/windows/check_native_fixed_image_observation.ps1)
verifies the pristine build, reads genuine child bytes, invokes integer-returning
RunInjectedOwners once and rejects nonzero before the ManagedOnly return and
negative-copy setup. Source ordering establishes the position before that unlogged
setup; actual logs establish the position before native case output.

The marker follows all six named real-owner contract methods. Their recording
adapter tests claim rejection/concurrency, permanent facade refusal, unopened
release, readiness revocation, actual preparation/hash/probe/release call order,
known failure and unavailable-return retention. It supplies cloned pristine bytes
verified against embedded expectations, without fake handles entering P/Invoke.
Existing synthetic diagnostic lines are not substituted for native artifact records.
The native harness still uses its standalone owner, and its checked release also
asserts readiness is revoked. It does not claim a composition lease.

Local witness history is narrower than six separate pre-implementation RED runs:
the original runner-invocation assertion failed before wiring, and the actual
owner readiness assertion failed before correction. Later weakened-guard controls
failed at each intended named assertion and final source passed again. Those are
regression-sensitivity controls, not retroactive individual RED claims.

## Actual Windows Framework bridge

Both native jobs execute the named real bridge assertion before the image step:

`python -X utf8 tests/test_native_fixed_image_observation_contract.py FixedImageWindowsPathBridgeContracts.test_nonascii_bridge_uses_windows_framework -v`

Both actual logs record:

```text
FIXED_IMAGE_PATH_HOST WindowsPowerShell=5.1;PSEdition=Desktop;FrameworkRelease=533509;CLR=4.0.30319.42000;CoreLibrary=mscorlib;OS=Win32NT
WINDOWS_FRAMEWORK_PATH_RESULT held=C:\u00e9 process=C:\u00c9 result=true
```

PUSH: **1 test in 0.382s, OK**. PR: **1 test in 0.456s, OK**. Neither named
assertion skips. The exact assertion first rejects portable proof for the changed
non-ASCII pair, then requires the real fixed Windows adapter result `[True]`.
The [fixed bridge](https://github.com/zlocorp/Portable-VirtualBox/blob/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff/tests/windows/check_native_fixed_image_paths.ps1)
requires **Framework >=4.8, Release >=528040**, Windows PowerShell 5.1/Desktop,
CLR major 4 and mscorlib. Observed Release **533509** is not labelled exact
Framework 4.8.0. Linux target compilation is not this Windows runtime proof.

## Native artifact integrity and preserved observations

All ten complete native ZIPs match GitHub metadata byte counts/SHA-256, pass ZIP
CRC, and extract without changing member bytes. Every one of the **55 JSONL
records per run** appears exactly once as a complete timestamp-stripped payload
line in the corresponding actual native log. Strict capture/environment/image
validators accept require_pass=True; the strict pipe validator also passes.
Independent checks reconstruct counts/hashes and decode environment framing.

| Trigger | Artifact | ZIP bytes | SHA-256 |
| --- | --- | ---: | --- |
| PUSH | [native-launch-observation (13899227402)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916926/artifacts/13899227402) | 10101 | `2f2f93fe7d18794769eb37e4840f59a35c3bb970d5bc227da1941bed6ca4bfd1` |
| PUSH | [native-fixed-image-observation-text-only (13899052695)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916926/artifacts/13899052695) | 964 | `b045658e324c3f081926086e2e04b90bd4d434e442f499c6101bfe09c8590348` |
| PUSH | [native-launch-environment-text-only (13899047753)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916926/artifacts/13899047753) | 677 | `1a1b4cbab884fd4419a129d5e6e5076faf1c2c2b3b2cf14324695d987451e442` |
| PUSH | [native-pipe-transport-text-only (13898598794)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916926/artifacts/13898598794) | 1658 | `604c89400418f9c5e9dc3fe87a4d707ab17b5f33f33263e0a9702bfb7aceada2` |
| PUSH | [native-child-capture-text-only (13898568888)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916926/artifacts/13898568888) | 1009 | `0ae1f6b88c1af3faebd6bb736b34de936256333da8cf2a4cac97ece3b5d88260` |
| PR | [native-fixed-image-observation-text-only (13898963112)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117927011/artifacts/13898963112) | 964 | `824b8c636680af53f4db7577e3866d617268e63ef442dddfde8dd42aff8d6098` |
| PR | [native-child-capture-text-only (13898733537)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117927011/artifacts/13898733537) | 1014 | `1e7631c76005ea2f72057f0b86a6baf1d5c9e08621fc21f5268fa52567c21c60` |
| PR | [native-pipe-transport-text-only (13898653545)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117927011/artifacts/13898653545) | 1668 | `9c52f7660dabb4828620ef0b37f8bd7d3a18611669661dc37fd240f7349b6998` |
| PR | [native-launch-observation (13898464067)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117927011/artifacts/13898464067) | 10109 | `7f6e35dd9b54897df3fddfed89289350d8b8bc95b92041446394e9de97b5d0ed` |
| PR | [native-launch-environment-text-only (13898249497)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117927011/artifacts/13898249497) | 677 | `101fd37bd81cd1663b60f92521fcb1e5aece9cdf847d708164658a3e6f9bf3ba` |

### Nine capture and three environment cases in each run

Independent PVC2/body reconstruction preserves all nine capture counts and FNV-1a64
hashes, including Binary stdout **4105 / 031381f5c4fbe740** and stderr
**257 / c98455caf71ceb86**. Empty has zero output; Large/CaptureFault/EvidenceFault
retain full-stream counts **196739/204829**. Nonzero exits **23**, Exit259 exits
**259**, other cases exit 0. Every case records both EOFs, released parent
resources, no retained owner, one create, one-shot refusal and terminal/fair IO.
PostCreateFault, CaptureFault, EvidenceFault and WithheldEof stay **UNKNOWN**;
passing their assertions does not promote their observations. Sentinel-probe and
independently unsignaled parent-event checks remain intact. Normalized PVC2 does
not identify an individual semantic branch or native comparison error.

None, AfterCreate and Evidence preserve exactly **110 PVE1 bytes**: version 1,
flags 30, absent parent-only sentinel, `Привет = fixture 🙂`, present empty string,
and two `C:\Windows` fields, with exact EOF. Captured stdout is **118 bytes**
including the eight-byte PVC2 offset; stderr is empty. All three exit 0 and record
both EOFs, environment/resource release and restoration. AfterCreate/Evidence
remain UNKNOWN; Evidence retains its one diagnostic byte at offset 8.
Both capture summaries pass 9/0 and both environment summaries pass 3/0.

### Four real standalone file-only image cases in each run

Matching-image, digest-mismatch, size-mismatch and missing-image retain **schema 1,
stage=file-only, create_calls=0, process_observation=null**. All use the same fresh
**19968-byte** expectation within their run:

- PUSH pristine SHA-256: `64be81c99008f3bbe2852cf1234e89cf8c683b34dd7bf48e1360f8d84a335357`.
- PR pristine SHA-256: `1627fe820d88f45108ddf56e6482bf490bedc9cddc979689a6ce28668e722eeb`.

Separate compiler outputs need not match. Matching/digest-negative cases hash all
19968 bytes through the held handle, retain actual identity and Unicode
`fixed-Ж-漢` path, and record a positive **one-byte EOF request returning zero**.
Matching equals the expectation. Same-size negative digests are
`d9a74c3fbfc3c9e41e54cb7fcf8a0734971f4edc0372d5c1670abd05e11e91ea` (PUSH) and
`86b9d420052c5dff5319d0ae618f002a477b426db20eeb6867a78e9ea36d6f9b` (PR).
Matching write/DELETE probes use **share=7, disposition=3**, return native error
**32** and acquire no handle. All acquired image handles close successfully.
Size mismatch is **19969 bytes**, refused before hashing; missing-image reports
error **2** without ownership. Both four-case summaries pass. No fixture child is
launched by these image harnesses.

Pipe evidence preserves **14 cases/573 checks**, all owners released. Launch
evidence preserves **64 managed checks/0 native calls** and **232 native
checks/11 calls**. Downloaded runtime-inspection files explicitly retain their
bounded-truncated inspection caveats, not complete control-flow attestation.

## Linux and build results

Linux PUSH [job 130850584822](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916934/job/130850584822)
and PR [job 130850616807](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117926977/job/130850616807)
execute the pinned official net48 provisioner before discovery and export its
verified reference directory. Exact source verifies the package and four reference
DLL hashes before making that directory usable. This is actual provisioning and
downstream execution, not an attached hosted-DLL rehash.

- PUSH: **425 tests in 91.680s, OK (skipped=7)**.
- PR: **425 tests in 69.367s, OK (skipped=7)**.

The seven skips are the six existing Windows platform cases plus the explicitly
Windows-only Framework bridge assertion. There are no missing-reference/compiler
skips. Ownership runner-invocation/static-boundary and host-frame regressions pass.
The real Windows runs above separately discharge the bridge gate. Windows compile
PUSH [job 130851386670](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117916934/job/130851386670)
and PR [job 130851228882](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117926977/job/130851228882)
also pass on attempt 1. These build-only checks do not launch the compiled product.

## Payload failure: first Prepare, no continuation coverage

Natural PUSH [run 43117917218](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917218),
[job 130850585547](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917218/job/130850585547),
attempt 1 failed in step 7, **Verify private payload continuation after system
teardown**, on the first case's Prepare:

`prepare-AfterFirstDelete-Finish helper exit=70, expected=0`

The [fixture](https://github.com/zlocorp/Portable-VirtualBox/blob/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff/tests/windows/check_payload_cleanup_recovery.ps1#L151-L180)
requires Prepare before enabling the controlled payload interruption. That
interruption and every continuation case were never reached. Proof records
**completed_cases: []**, not a failed payload-delete continuation.

The retained worker error says the **VBoxSDS service registry key does not exist**.
The [worker's exact source](https://github.com/zlocorp/Portable-VirtualBox/blob/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff/scripts/privileged_session_worker.ps1#L77-L127)
places this read immediately after Run-Sds registration. Reaching it means that
code observed process exit zero within its 30-second deadline; there is no
independent persisted SDS exit-code record. Both registration output files are
empty. This success-like process result did not establish the registration
postcondition. The protected worker exited 1 within deadline; the
[helper](https://github.com/zlocorp/Portable-VirtualBox/blob/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff/source/privilege/SessionHelper.Main.cs#L257-L307)
rejected the operation and returned 70.

Before that failure, receipts record signed exact VBoxSup staging, pnputil
EXITED/0, matching installed/package driver hash, then owned start EXITED/0 with
SCM and WMI Running and no other VBox services beforehand. **The last affirmative
driver snapshot is Running.** This is partial system preparation. Durable intent,
controller binding, stage/start receipts and an integrity-valid **incomplete
helper journal** exist; the journal records worker exit but no HELPER_COMPLETE.
There is no prepared-session receipt, SDS-registration marker, cleanup receipt,
payload checkpoint/journal or payload-removed marker in the collected evidence.

**No verified teardown or final data-preservation result exists for this run.**
The proof's false preservation/cleanup fields remain their initial values because
their assertions were never reached. They do not prove data destruction, and the
artifact contains no evidence of user-data deletion. Disposing controller wrappers,
GitHub orphan-process cleanup or eventual disposable-host teardown is not
per-resource cleanup proof. The fixture deliberately does no guessed fallback
cleanup on failure.

The [existing partial-recovery guard](https://github.com/zlocorp/Portable-VirtualBox/blob/6a164dbdc14bf5d4d6ddadb072d7f7586f8560ff/scripts/vbox_sup_partial_cleanup.ps1#L142-L148)
refuses absent durable SDS marker with registration output present:
`SDS may have registered without a durable marker`. This ambiguous state grants
no automatic partial-recovery authority. That refusal must remain intact.

The immediate failed postcondition is established; **the underlying cause is
unknown**. Current evidence cannot distinguish registration silently not taking
effect, delayed/delegated activity, observation anomalies or outside interference.
The earlier successful source does not explain this failure. It is not labelled
flaky or unrelated, and no blind sleep, registration retry, weakened identity
check or speculative cleanup is justified.

The failed run's [payload-cleanup-recovery-evidence artifact 13898513762](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43117917218/artifacts/13898513762)
is **6790 ZIP bytes / 17 files**, SHA-256
`1b224f5e9ec85d0bcd880f174739715511584077d61858383c2c02cd377ded26`.
Its size/digest match GitHub metadata and the upload log; CRC passes. This public
summary omits journal bindings and transient host details.

## Remaining gates

- The payload failure remains unresolved. A separate diagnostics-only proposal
  may establish bounded process/postcondition observations and non-destructive
  refusal coverage; no such diagnostic change or behavioral fix is accepted here.
- Task **2D is paused** pending that diagnosis and independent review before the
  next implementation stage. Contributions remain on the Draft branch.
  Shared command formatting, lease launch binding and real existing-owner
  process/query/drainage composition remain unfinished.
- Task **2E remains unfinished**, including actual stage-aware schema-2 serializer,
  composed validator/status-guard integration, native composition harness and its
  own changed-source evidence. File-only schema 1 cannot certify composed PASS.
- Earlier execution records and failed outcomes remain unchanged. Any future
  successful or diagnostic run requires a separate source-specific record.
- No primary-host operation, system-effect retry, production integration,
  interactive UAC/workstation acceptance, merge or release is authorized.
