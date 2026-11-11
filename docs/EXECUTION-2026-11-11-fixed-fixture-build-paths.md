# Accepted test-only checkpoint: fixed-fixture build and path comparison

## Source, review and result

Independent review accepts Tasks **2A–2B**, the child-first build graph and bounded
fixed-image path comparison, at
[`98bec8f6fb035b90156b02fec8c63e9278deb010`](https://github.com/zlocorp/Portable-VirtualBox/commit/98bec8f6fb035b90156b02fec8c63e9278deb010),
tree `c92ed011a8097b7c135d06f75585ad45b4c72a9a`. All **11 naturally triggered workflows succeeded on attempt 1**:
eight PUSH and three PR. No rerun, cancellation or manual dispatch was used.

Both actual native artifact sets preserve nine capture, three Unicode environment
and four file-only image cases. Both native jobs execute the named real Windows
Framework bridge assertion, including its changed non-ASCII comparison. This
satisfies the changed-source build/path prerequisite for beginning Task 2C.

The design/preflight and each scoped implementation received independent review.
A final review correction bounded adapter host stderr to nonempty exact bytes of
at most 256 bytes before decoding or relay. Its oversized matching-host regression
failed before correction and passed afterward. The earlier local broad result was
**421 tests, seven skips**. The correction then passed **six bridge tests** and
**33 focused image-module tests, one skip**, followed by scoped re-review. That
focused rerun was not another local full suite. Both hosted Linux jobs below test
the final published source with **423 tests, seven skips**, including the two
host-frame regressions. The earlier Task 2A-only local result was 409 tests/six
skips; it is not substituted for final-source coverage.

The accepted implementation is limited to 2A–2B. **Tasks 2C–2E remain unfinished**
and require their own implementation/review and changed-source evidence. The
schema-independent path-comparison status guard exists, but its integration into
the actual composed-artifact validator remains **Task 2E**. Schema 1 remains
file-only; there is no accepted schema-2/composed artifact. Production lifetime,
cleanup retry, workstation, merge and release gates remain open.

## Complete natural CI inventory

| Workflow | Trigger | Run | Result |
| --- | --- | --- | --- |
| Verified Oracle package preparation (no installation) | PR | [43113074332](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074332) | Success, attempt 1 |
| Portable-VirtualBox CI (build only) | PR | [43113074130](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074130) | Success, attempt 1 |
| Native AutoIt policy regressions | PR | [43113074200](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074200) | Success, attempt 1 |
| Native AutoIt policy regressions | PUSH | [43113061248](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061248) | Success, attempt 1 |
| Exact-owned orphan cleanup after abandoned controller (no UAC acceptance) | PUSH | [43113061092](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061092) | Success, attempt 1 |
| Portable-VirtualBox CI (build only) | PUSH | [43113061076](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061076) | Success, attempt 1 |
| Fixed helper with medium user processes (no UAC acceptance) | PUSH | [43113061080](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061080) | Success, attempt 1 |
| Guarded rollback after interrupted VBox driver preparation (disposable host) | PUSH | [43113061033](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061033) | Success, attempt 1 |
| Commit-bound source snapshot | PUSH | [43113061053](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061053) | Success, attempt 1 |
| Noninteractive UAC pending (no consent acceptance) | PUSH | [43113061047](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061047) | Success, attempt 1 |
| Private payload cleanup continuation (disposable host) | PUSH | [43113062162](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113062162) | Success, attempt 1 |

The [full-source Actions inventory](https://api.github.com/repos/zlocorp/Portable-VirtualBox/actions/runs?head_sha=98bec8f6fb035b90156b02fec8c63e9278deb010&per_page=100)
returned total_count=11, including both PUSH and PR events. Every listed run has
the exact head SHA and attempt 1. Detailed acceptance below covers the native
artifacts and build/Linux jobs. Other conclusions do not imply a new detailed
audit of all system-effect artifacts.

## Actual checkouts and runtime

- Native PUSH [job 130833867601](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061248/job/130833867601)
  records the exact published source checkout.
- Native PR [job 130833911821](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074200/job/130833911821)
  records synthetic merge `473074410cedce904af24bb03a295a12d2ca9a51`.
  Its [Git commit object](https://api.github.com/repos/zlocorp/Portable-VirtualBox/git/commits/473074410cedce904af24bb03a295a12d2ca9a51)
  has parents `5b58dbbe701c3e2eb348942a9059708063b0cb96` and the published
  source, with the identical tree `c92ed011a8097b7c135d06f75585ad45b4c72a9a`.
  This is same-tree PR evidence, not a direct head checkout.
- Both native jobs use **Microsoft Windows Server 2022 Datacenter 10.0.20348**,
  image **windows-2022/20261101.353.1**, runner **2.338.2**. They are GitHub-hosted
  observations, not observations on the user's Windows 10/11 machine.

## Actual Windows Framework bridge assertion

Both native jobs complete **Verify exact Windows Framework path comparison
bridge** before the existing file-only image step. The exact command executes:

`python -X utf8 tests/test_native_fixed_image_observation_contract.py FixedImageWindowsPathBridgeContracts.test_nonascii_bridge_uses_windows_framework -v`

Both logs identify the shell as
`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.EXE` and record:

```text
FIXED_IMAGE_PATH_HOST WindowsPowerShell=5.1;PSEdition=Desktop;FrameworkRelease=533509;CLR=4.0.30319.42000;CoreLibrary=mscorlib;OS=Win32NT
WINDOWS_FRAMEWORK_PATH_RESULT held=C:\u00e9 process=C:\u00c9 result=true
```

PUSH: **Ran 1 test in 0.335s, OK**. PR: **Ran 1 test in 0.433s, OK**. Neither
named Windows assertion skipped. The
[exact source assertion and adapter](https://github.com/zlocorp/Portable-VirtualBox/blob/98bec8f6fb035b90156b02fec8c63e9278deb010/tests/test_native_fixed_image_observation_contract.py)
supply actual strings `C:\é` and `C:\É`, require the portable comparator to
return None, call the fixed adapter directly and require `[True]`. The successful
result does not come from a mocked response or the portable safe fast path.

The fixed adapter invokes only the SystemRoot Windows PowerShell executable and
[fixed bridge script](https://github.com/zlocorp/Portable-VirtualBox/blob/98bec8f6fb035b90156b02fec8c63e9278deb010/tests/windows/check_native_fixed_image_paths.ps1).
It validates ordered Boolean response framing, <=64 stdout bytes and nonempty
<=256 host bytes. The script compiles the fixed shared path source plus a constant
managed wrapper, accepts <=4 exact pairs/131072 UTF-8 bytes, and calls the real
`FixedImagePath.Agree` with `StringComparison.OrdinalIgnoreCase`. The result
marker is printed only after the real `[True]` response assertion. It is not a
separate raw-response artifact; its interpretation is bound to this exact source.

The gate requires **Framework >=4.8 (Release >=528040)**. The actual observed
Release is **533509**, with CLR **4.0.30319.42000**, Desktop and mscorlib as above.
This is not labelled exactly Framework 4.8.0 or inferred to have a particular
marketing version. Linux net48-target compilation and pwsh/.NET managed execution
cannot establish Windows Unicode equivalence. These two actual Windows assertions
discharge the gate for this source only.

## Artifact integrity

All ten full native ZIP downloads match GitHub metadata sizes and SHA-256 digests;
ZIP CRC checks pass. Extracted bytes match their ZIP members. Every JSONL record
matches its actual native job log. Exact strict capture/environment/image
validators accept require_pass=True; the bounded strict pipe validator passes.
Independent checks below use the actual records, not managed synthetic examples.

| Trigger | Artifact | ZIP bytes | SHA-256 |
| --- | --- | ---: | --- |
| PUSH | [native-fixed-image-observation-text-only (13897835622)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061248/artifacts/13897835622) | 965 | `551bea7a95806bca78b7d7063ac9352b1085a7eb52826ff88214ac1375e8e1e3` |
| PUSH | [native-pipe-transport-text-only (13897666106)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061248/artifacts/13897666106) | 1667 | `3674bbe43cffe230d2c0f5f26506ccb71351ae28e08ed42b6a37bce88acc4ad0` |
| PUSH | [native-launch-observation (13897666095)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061248/artifacts/13897666095) | 10105 | `7e7bc424e490e610fb6df78770b9b38fe8c938e7e9cd35bfccfbca7e934805de` |
| PUSH | [native-child-capture-text-only (13897556347)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061248/artifacts/13897556347) | 1012 | `b876b4568dc34c91dc6f199b2b2d3c6f8b40a949c6e6c264bedc471515309ff1` |
| PUSH | [native-launch-environment-text-only (13897446530)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061248/artifacts/13897446530) | 677 | `0b7526ebed18efac675f0751778bc8e7c0ffc9f4332dc33b1d57fd872b3a3ccb` |
| PR | [native-pipe-transport-text-only (13896708228)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074200/artifacts/13896708228) | 1667 | `cc185f1931202e310ddea7bc1a228490205082211f688a36fcfca7068433d6fc` |
| PR | [native-launch-observation (13896314020)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074200/artifacts/13896314020) | 10107 | `75d841fe054fbd1e92c5e2fb5c812e6d9f34c9fe5d72c6f4e649b5c49a3a922a` |
| PR | [native-child-capture-text-only (13896274082)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074200/artifacts/13896274082) | 1007 | `dbcdd7e1843e8d03c9cadf26817fae828eac53ad08922ac2646ec5be3e2cde71` |
| PR | [native-launch-environment-text-only (13896264097)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074200/artifacts/13896264097) | 677 | `0b7526ebed18efac675f0751778bc8e7c0ffc9f4332dc33b1d57fd872b3a3ccb` |
| PR | [native-fixed-image-observation-text-only (13896209185)](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074200/artifacts/13896209185) | 966 | `5dc992e2f558b110337944b6e3dbe842965a158c97c9236665350b019cdd2db8` |

## Actual nine capture cases in each run

| Cases | stdout bytes / FNV-1a64 | stderr bytes / FNV-1a64 |
| --- | --- | --- |
| Empty | 0 / `cbf29ce484222325` | 0 / `cbf29ce484222325` |
| Binary | 4105 / `031381f5c4fbe740` | 257 / `c98455caf71ceb86` |
| Large, CaptureFault, EvidenceFault | 196739 / `c1f1accadf2339e9` | 204829 / `8b07499bc23a9f3e` |
| Nonzero, Exit259, PostCreateFault, WithheldEof | 25 / `e6a7f5deb30873c0` | 257 / `c98455caf71ceb86` |

Independent reconstruction uses the literal PVC2 header `50 56 43 32 01 00 00 a5`,
unchanged body pattern `(offset*31+seed)&255`, stdout seed 0, stderr seed 71 and
FNV-1a64. All actual counts/hashes agree. Empty emits genuinely zero header/body
bytes. Nonzero exits **23**, Exit259 exits **259**, and all other cases exit 0.

Every case records both EOFs, released parent resources/no retained owner,
one-shot refusal, exactly one create, positive wait/exit-code reads, matched
issued/terminal IO and fair visits. Both summaries are **PASS, 9 cases, 0 failed,
all owners released**. All semantic sentinel probes pass alongside the independent
unsignaled parent-event observation.

PostCreateFault/CaptureFault/EvidenceFault/WithheldEof retain **UNKNOWN**. Fault
sites 1/2/3 and EvidenceFault's one diagnostic byte are unchanged. CaptureFault
and EvidenceFault retain eight stdout header bytes and discard all 196731 body
bytes while preserving full-stream hashes/counts. WithheldEof records blocked
EOF before eventual EOF/release. Passing assertions do not promote UNKNOWN.

Artifacts retain counts/hashes, not raw whole capture bodies. The normalized PVC2
EXCLUDED result, or Empty's exit-0 equivalent, does not identify which semantic
exclusion branch ran or its native comparison error. No particular branch or
error 1656 is inferred. Child-reference close is part of the trusted fixture's
successful semantic result; `resources_released` separately describes parent
ownership.

## Actual environment and file-only image observations

Each run's None, AfterCreate and Evidence cases pass. Canonical base64 independently
decodes to exactly **110 PVE1 bytes**, version 1, flags 30, five fields and exact
EOF: absent parent-only sentinel, `Привет = fixture 🙂`, present empty string,
`C:\Windows`, `C:\Windows`. Captured stdout is **118 bytes**, including the
eight-byte PVC2 prefix; stderr is empty.

All record exit 0, both EOFs, ReturnedTrue/exactly one create, environment/parent
resource release, restoration, one-shot refusal and no retained owner. None stays
OBSERVED; AfterCreate and Evidence stay UNKNOWN. Evidence records fault site 3,
one diagnostic byte and fault_at_bytes=8 before the completed PVE1 stream. Both
summaries are PASS, three cases, zero failed.

The four image cases retain **schema 1, stage=file-only, create_calls=0 and
process_observation=null**. Each run uses a fresh **19968-byte** pristine expectation:

- PUSH: `80ddb2674d2da24c3dd49c9a72b0417a1ea02eef21cb179b9f0313e2b90f4108`.
- PR: `5636d98d62afaa6635c959399e105731e3b02959cc238fa40c419f9bbfd4ed96`.

Separate compiler outputs need not be byte-identical. Matching and digest-negative
files each hash all 19968 bytes, retain actual held-file ID/volume and
`fixed-Ж-漢` paths, and record a positive one-byte request returning zero at EOF.
The matching digest equals its run's expectation. Same-size negative digests are
`5402bf2af7d2553e83abb4bb5908b68c8c10df2e6c36abe87b833111d9363c91`
(PUSH) and
`7e233f76213d68ea1a9254f78f8bbea09846e387701a65d67783f71b7f8f4400`
(PR), each unequal to its pristine expectation.

The matching case's write/delete probes use share=7/disposition=3 and return native
error **32**, without acquired probe handles. No probes are inferred for negative
cases. Every acquired image handle has a checked successful close. Size mismatch
is **19969 bytes** and is refused before hashing. Missing-image records known
error **2** with no owned handle. Both summaries pass all four cases.

The existing pipe artifacts pass **14 cases/573 checks**, all owners released.
Launch artifacts retain **64 managed checks/0 native calls** and **232 native
checks/11 calls**. Runtime-inspection files are complete downloads but explicitly
report bounded-truncated inspection, not full method-body attestation.

## Final Linux/build coverage

Linux PUSH [job 130833867362](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061076/job/130833867362)
and PR [job 130833911559](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074130/job/130833911559)
record the same exact-head/same-tree-merge distinction. Both successfully invoke
the [unchanged pinned reference provisioner](EXECUTION-2026-11-11-net48-reference-provisioning.md)
before discovery and export its verified reference path through
PVBOX_TEST_NET48_REFERENCES. The exact source verifies the official package and
four reference DLL hashes before producing a compiler-consumable path. Hosted DLL
bytes are not separate artifacts; this evidence is actual provisioning, export and
downstream tests with reviewed fail-closed code, not a separate hosted-file rehash.

- PUSH: **423 tests in 77.749s, OK (skipped=7)**.
- PR: **423 tests in 81.786s, OK (skipped=7)**.

Both host-frame regressions explicitly pass. The actual seven skips are the six
existing Windows platform cases (three cabinet path/workspace assertions,
main-manager Windows PowerShell execution, cabinet extraction and invalid-MSI
API assertion), plus the explicitly Windows-only Framework bridge assertion.
There are no missing compiler/reference prerequisite skips. The two native
Windows executions separately satisfy that bridge gate.

Both build workflows finish successfully on attempt 1. Compile jobs
[130834816930](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113061076/job/130834816930)
and [130834816472](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43113074130/job/130834816472)
also succeed; their full logs contain no GitHub error marker. These final hosted
423/7 results cover the published correction; they do not relabel the earlier
local 421/7 or focused 33/1 results.

## Preserved history and remaining gates

Independent comparison against 5190564 preserves the closed existing schema
field declarations and exact child/runtime/native-case source bytes. All
observations retain mutation_authorized=false. The
[prior sentinel record](EXECUTION-2026-11-11-native-sentinel-observation.md),
[reference-pack successor](EXECUTION-2026-11-11-net48-reference-provisioning.md)
and [earlier partial file-only record](EXECUTION-2026-11-11-native-fixed-image-file-only.md)
remain separate historical evidence, including the earlier failed native PR and
missing-reference Linux failures. None is replaced or erased by this checkpoint.

The [design](designs/native-fixed-image-observation.md) and
[plan](plans/2026-11-11-native-fixed-image-observation.md) mark only 2A–2B accepted.
Task 2C ownership transfer, 2D composition/query and 2E schema/integration/native
acceptance remain unfinished. The reusable comparison guard does not yet enforce
actual composed artifacts. No new observation repairs production outer-worker or
nested VBoxSDS lifetimes, grants cleanup/retry authority, or satisfies interactive
Windows 10/11, whole-product safety, merge or release approval. See the unchanged
[release gates](RELEASE-GATES.md).
