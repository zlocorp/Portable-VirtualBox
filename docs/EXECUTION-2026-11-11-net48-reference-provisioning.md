# Accepted test-only checkpoint: net48 provisioning and native PR file observations

## Status and source

Independent review accepts the hosted Linux reference-pack correction and the
native PR file-only observations at
[`33447ae2ff048230675c05c72509857d252fceee`](https://github.com/zlocorp/Portable-VirtualBox/commit/33447ae2ff048230675c05c72509857d252fceee),
tree `b88bc27ebaf4693571e3f3505c6d3404962d7ab3`. Task 1 is accepted as a
test-only file-observation stage. Task 2 composition remains unimplemented and
requires separate review. The known numeric sentinel diagnostic limitation is
being hardened separately before composition.

All **five naturally triggered workflows succeeded on attempt 1**, without a
replay, manual rerun or manual dispatch. These are source-specific results, not
whole-product readiness or production admission. The earlier
[`b2229c5` partial checkpoint](EXECUTION-2026-11-11-native-fixed-image-file-only.md)
remains unchanged: eight successes and three failures, including the two missing
reference-pack failures and the native PR sentinel failure.

## Complete run inventory

| Workflow | Trigger | Run | Result |
| --- | --- | --- | --- |
| Build-only CI | PUSH | [43093958865](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093958865) | Success, attempt 1 |
| Commit-bound source snapshot | PUSH | [43093958993](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093958993) | Success, attempt 1 |
| Verified Oracle package preparation | PR | [43093970934](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093970934) | Success, attempt 1 |
| Build-only CI | PR | [43093970986](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093970986) | Success, attempt 1 |
| Native AutoIt policy regressions | PR | [43093971010](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093971010) | Success, attempt 1 |

**There is no native PUSH run for this source.** The earlier native PUSH at
`b2229c5` is not relabelled as a `33447ae` run. The detailed evidence review below
covers both Linux static jobs and the native PR job; the inventory also records
the other completed workflow outcomes without claiming a new audit of every
build or Oracle artifact.

## Actual Linux provisioning and managed checks

The [PUSH static job 130777894160](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093958865/job/130777894160)
and [PR static job 130777935438](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093970986/job/130777935438)
used Ubuntu 24.04.5 LTS, image `ubuntu-24.04` version `20261101.360.1`,
runner `2.338.2`.

Both actual logs show the mandatory preparation step invoking
`tests/prepare_native_fixed_image_toolchain.py` in its default download mode,
without an offline package argument. The reviewed helper downloads only the fixed
official NuGet `Microsoft.NETFramework.ReferenceAssemblies.net48` package,
version **1.0.3**, with package SHA-256:

`8a7e348538e7eb91351696911689f49e3d4f63f8bab517432bbe159b8b1104a2`

It verifies that package before ZIP processing, selects only the four exact
reference DLLs, checks their independent source-pinned digests and writes them to
a fresh directory only after all four validate. Downloads and reads are bounded.
There is no alternate source, host-runtime retargeting, reference fallback or
skip-on-missing behavior. The package supplies compiler reference metadata;
nothing from it is installed or executed.

The preparation shell ran with `bash -e`, then exported the verified path through
`GITHUB_ENV`. The following mandatory unit-test step in each actual log contains:

```text
PVBOX_TEST_NET48_REFERENCES: /home/runner/work/_temp/pvbox-net48-reference-pack/references
```

The hosted package and DLLs were not uploaded as artifacts, and no separate
per-file hash receipt was printed. Hosted verification therefore rests on the
exact reviewed fail-closed implementation, its actual default invocation,
successful export and downstream real compilation/tests, rather than an
independent rehash of downloaded hosted files.

- **PUSH:** the actual checkout log reports
  `33447ae2ff048230675c05c72509857d252fceee` at **20:10:18.6647738 UTC**.
  Preparation began at **20:10:18.7934229** and mandatory unit discovery at
  **20:10:19.1203997**. Final result: **392 tests in 31.056 seconds,
  OK (skipped=6)** at **20:10:50.3495155 UTC**.
- **PR:** the actual checkout log reports synthetic merge
  `7f66505650b282efcff8fb08841619c03ec9211b` at **20:10:23.3176075 UTC**.
  Preparation began at **20:10:23.4886774** and mandatory unit discovery at
  **20:10:23.7956118**. Final result: **392 tests in 42.841 seconds,
  OK (skipped=6)** at **20:11:06.9873155 UTC**.

All times are on **2026-11-11**. Both logs show all **13 fixed-image observation
tests** and **10 provisioner tests** passing. The previously failing managed
contract actually compiles the harmless child and four C# 5/x64/net48 harnesses,
then executes its pure contracts and serializer checks without launching a
fixture child.

The six unchanged skips are Windows-only cabinet Unicode paths, invalid cabinet,
cabinet workspace staging, the Windows CI PowerShell execution case, native
cabinet extraction and invalid MSI handling. No new image or provisioning test
was skipped. This fixes the dependency failure for the new source; it does not
change either historical failed build run.

## Native PR checkout, platform and artifact verification

[Native PR job 130777936014](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093971010/job/130777936014)
actually checked out synthetic merge
`7f66505650b282efcff8fb08841619c03ec9211b`, recorded at
**20:10:29.6542521 UTC**. GitHub's commit API confirms its parents are base
`5b58dbbe701c3e2eb348942a9059708063b0cb96` and head
`33447ae2ff048230675c05c72509857d252fceee`. Its tree is exactly
`b88bc27ebaf4693571e3f3505c6d3404962d7ab3`, equal to the published source tree.
Tree equality supplies the source relationship; the PR checkout SHA is not
reported as the PUSH head SHA.

The job used Windows Server 2022 Datacenter `10.0.20348`, image `windows-2022`
version `20261101.353.1`, runner `2.338.2`. The fixed-image step ran under Windows
PowerShell from **20:11:39.2285876 UTC**. Its four actual case records appeared
between **20:11:40.5508078 and 20:11:40.6802086 UTC**, followed by a PASS summary
at **20:11:40.6858258 UTC**. Both validator passes completed by
**20:11:41.2491344 UTC**.

Downloaded ZIP bytes independently match both GitHub metadata and the actual
upload-log digests:

| Artifact | ZIP bytes | SHA-256 |
| --- | ---: | --- |
| [Fixed image 13889822095](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093971010/artifacts/13889822095) | 965 | `f7195b013cc9e500ab7d590b1cb78b2f75ee8b2022cb500ae9a663f37a30a3fe` |
| [Child capture 13890371499](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093971010/artifacts/13890371499) | 1000 | `65bacf501aa8c7491e6e38a978789811d184be01ad74ddf11ff47ab1954cefa4` |
| [Environment 13890750550](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43093971010/artifacts/13890750550) | 677 | `46392cab44c0ca2f3d6cc540fd7446b9c60e54f4043c483b4fe59a36fa4d9e9f` |

Each ZIP contains exactly its expected text JSONL member. All three exact-source
validators independently accept `require_pass=True`, and every downloaded record
matches the corresponding actual native log record. Synthetic managed diagnostic
records are excluded from this native evidence.

## Actual four-case fixed-image result

The fixed-image JSONL contains five bounded newline-terminated records, totaling
**3,446 bytes**. Its SHA-256 is
`27d28a9b7bd5f9475e178d06b1d8a02155ae94604913d2fba493d8dc9dcc1330`.

All four harnesses embed pristine size **11,776** and SHA-256
`adc8eb8f7e96ff7e5e951781693c5b910ef50a4c06b5072781baad5b40342ee8`.
This newly built digest need not equal the earlier run's digest: unchanged
expectations within this build are required, not reproducible compiler output.

1. **Matching image: PASS.** Actual size and digest equal the embedded values;
   all 11,776 bytes were hashed. The complete read includes a positive one-byte
   terminal request returning zero bytes. Native open and checked native close
   returned success. `GENERIC_WRITE` and `DELETE` probes each used share mask 7
   and `OPEN_EXISTING` disposition 3, returned failure/error 32 and never owned a
   probe handle.
2. **Same-length digest mismatch: PASS.** Actual size is still 11,776, with
   complete SHA-256
   `78b284337f57b08fcd33bdb03f0910c459390e27e101e1bc48f822bae51bf754`.
   The comparison was reached and differs from the pristine expectation. It has
   the same full byte count and one-byte/zero-byte EOF proof, then successful
   checked native close. No probes ran.
3. **Size mismatch: PASS.** Actual size is 11,777, with no read entry, zero hashed
   bytes and null digest, EOF, identity and path observations. Native open and
   checked close returned success.
4. **Missing image: PASS.** Native open returned failure/error 2; no handle was
   opened, no read or probe ran, and unavailable file observations remain null.

The first two cases report volume serial `04a0a9caa0a9c312` and distinct file IDs
`3b950f00000005000000000000000000` and `3c950f00000005000000000000000000`.
Their actual paths retain the Cyrillic/CJK segment after ASCII-safe JSON transport:

```text
\\?\C:\Users\runneradmin\AppData\Local\Temp\pvbox-fixed-image-build-41ff433c80d54d28a9d29d8669d4f459\fixed-Ж-漢\matching-image\NativeCaptureFixtureChild.exe
\\?\C:\Users\runneradmin\AppData\Local\Temp\pvbox-fixed-image-build-41ff433c80d54d28a9d29d8669d4f459\fixed-Ж-漢\digest-mismatch\NativeCaptureFixtureChild.exe
```

All four cases have `stage=file-only`, `create_calls=0`,
`process_observation=null` and `mutation_authorized=false`. The summary is PASS,
four cases, zero failures, `stop_reason=none`. This stage launches no fixture
child; earlier child-capture and environment stages retain their existing
harmless child launches. Managed disposal and process teardown are not counted
as checked native close proof.

## Actual nine capture and three environment results

All nine child-capture cases pass: `Empty`, `Binary`, `Large`, `Nonzero`,
`Exit259`, `PostCreateFault`, `CaptureFault`, `EvidenceFault` and `WithheldEof`.
Their summary reports nine cases, zero failures and all owners released. The
fault cases retain their intended `UNKNOWN` overall results despite passing their
assertions. Stream counts/hashes, terminal I/O, sentinel and one-shot checks
remain intact in the accepted records.

All three environment cases pass: `None`, `AfterCreate` and `Evidence`. Their
summary reports three cases, zero failures, all owners released and the parent
sentinel restored. Each actual observation decodes to a **110-byte PVE1 record**;
the separate stdout byte counter is 118. Every record retains
`mutation_authorized=false`.

Passing the unchanged numeric sentinel probe in this run does not remove the
limitation demonstrated by the historical failed PR. Handle numbers are
process-local; that diagnostic is not a complete inheritance census and does not
identify a potentially unrelated child object. Its separate hardening remains
required before composition. The prior failure is preserved, not reclassified.

## Remaining boundaries

The exact-source file-only prerequisite is met for Task 1. Task 2 remains
unimplemented, with separate composition review after sentinel diagnostic
hardening. `stage=composed` remains unavailable. No test-only acceptance here
attests compiler output, signatures, ancestors, ACLs, dependencies, loaded process
bytes or all possible image-modification mechanisms.

No production lifetime repair, new launcher, system-effect retry authority,
primary-host Windows acceptance, merge or release approval follows from these
results. The existing [release gates](RELEASE-GATES.md) remain open. This report
records naturally triggered hosted execution; the evidence review itself used
only read-only retrieval and offline artifact validation, without rerunning CI
or replaying native operations.
