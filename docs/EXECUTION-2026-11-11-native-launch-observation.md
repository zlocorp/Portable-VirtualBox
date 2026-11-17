# Test-only native launch observation execution record

Date: 2026-11-11. Tested source commit:
`f9bff11790b5f8324218a4c3d67be171b8526627`.
Independent actual-diff and final artifact review accepted this **test-only**
observer. Production source and scripts remain at the accepted `175e6a4` runtime
checkpoint. This adds no production launch/capture replacement, retry authority,
build/package input or release approval.

## Exact-commit execution and evidence

All **11 naturally triggered workflow runs passed on attempt 1** at the full
source SHA above, with no failure, cancellation, rerun or manual dispatch:

- Native push [43027196442](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196442),
  job [130544785030](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196442/job/130544785030),
  and native PR [43027208962](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027208962).
- Builds [43027209171](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027209171)
  and [43027196261](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196261).
- Oracle file-only preparation [43027209696](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027209696).
- Source snapshot [43027196246](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196246).
- Noninteractive pending UAC [43027196066](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196066).
- Interrupted preparation [43027196119](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196119).
- Fixed helper [43027196102](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196102).
- Orphan recovery [43027196090](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196090).
- Private payload continuation [43027196340](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43027196340).

Existing broad `tests/windows/**` filters caused the additional workflow runs.
These are the 11 triggered runs, not every workflow in the repository and not
workstation or release acceptance.

Push artifact `13857099063`, `native-launch-observation`, contains exactly
`native-launch-observations.jsonl` and `runtime-process-inspection.json`.
Its downloaded SHA-256 matches the GitHub artifact digest:
`4b8c6c20e623781bdc01485e2ff3e94ba57387c0ff78f1e53647311a12dc0e60`.
The GitHub API's artifact `workflow_run.head_sha` binds this evidence to the full
commit above; the text records themselves need not contain a source SHA.
The artifact expires **2026-11-18 at 13:14:50 UTC**. Retain the archive and its
run/SHA/digest association before a later candidate decision; a green badge is
not a permanent evidence store.

## Observed native lifetime

Independent review reconciled 16 distinct attempts and 17 snapshots: the
controlled WAIT_FAILED attempt has separate before/after trusted-drain records.
The 11 P/Invoke invocation-boundary entries produced one observed native FALSE
with error 2 and ten created children. The counter records entry to the invocation
boundary, not proof of OS execution when marshalling or the return is unavailable.

All ten children were drained through their original retained process handles:
native signal, exit-code query, then handle close. Exit codes 0, 70 and 259 were
observed; 259 **after a signal** is a real exit code, not evidence of a live child.
The actual timeout remained overall UNKNOWN after eventual zero exit. Injected
post-create, wait-wrapper, identity and evidence faults also remained UNKNOWN.
The controlled WAIT_FAILED retained the handle before a separate trusted drain
and remained UNKNOWN afterward. No persistent real native WAIT_FAILED was induced.

All requested injection sites were reached, including the recorder fault stages.
The reported 232 checks **include** the 64 managed checks, leaving 168 further
native-case checks; they are not 232 additional native checks. The unavailable
native-return case is a managed decision simulation, not reproduction of a
marshalling or allocation failure. Every observation has
`mutation_authorized=false`.

## Actual loaded private method evidence

The inspector captured `System.Diagnostics.Process.StartWithCreateProcess` from
the loaded `System` module, MVID `9c83289f-802b-45ce-b0d0-615c55db0a6c`, on CLR
`4.0.30319.42000`. Separately, the on-disk `System.dll` path reported file version
`4.8.9363.0 built by: NET481REL1LAST_25H2_B` and SHA-256
`15adc79ede47ebfa67c9cbac1bfdc98493cddfcdff743fcfc10f4be4224a14aa`.
That disk hash is **not** an attestation of the loaded module's bytes.

The overall inspector status is `bounded-truncated`: verbose instructions,
sparse records and locals were truncated. It nevertheless retained all 1,272 raw
IL bytes, the full 114-call list/scan, all five exception-handling regions and
zero unresolved tokens. Independent review decoded all 441 instructions from
that raw IL and validated all 57 branch targets, rather than treating call order
alone as control-flow proof.

On the successful CreateProcess path, the call at offset 843 stores TRUE at 848;
the branch at 963 reaches 1009 and the finally chain reaches 1046. With the
helper's stdout/stderr redirection flags, execution reaches the blocks
1101–1165 and 1165–1229, including StreamReader construction at 1155 and 1219,
before `SetProcessHandle` at 1242 and `SetProcessId` at 1254. All five local
exception-handling regions end by 1046; none protects the later stream
construction. This establishes ordering and the lack of local protection in
**this actual loaded private method**, strengthening the earlier reference-source
family evidence. It is not attestation of the complete outer Start/Dispose/
finalizer/JIT chain, an observed OOM, or a finding across all serviced Framework
builds.

Runner setup identifies Windows Server 2022, build `10.0.20348`. The inspector's
`Environment.OSVersion` value `6.2.9200` is compatibility reporting, not Windows 8
or workstation acceptance. The prototype requests no elevation; the CI host may
already be elevated. These observations establish no medium/elevated token claim.

## Verification and remaining work

Local pre-publication checks ran 317 Python tests, OK with six platform skips,
plus four focused observation tests. Both test executables compiled as C# 5/x64
against official .NET Framework 4.8 reference assemblies with warnings-as-errors.
Those local results are separate from the Windows execution above. The prototype
uses a fixed harmless child and owned temporary files only, with no kill,
suspension, pipe capture, environment hardening, admission, lineage or VBox/system
effects. No primary/user Windows host, merge or release was involved.

The helper's exceptional launch/capture/wait lifetime gap remains **unfixed**.
The accepted [checkpoint-before-diagnostics result](EXECUTION-2026-11-11-checkpoint-before-diagnostics.md)
operates only after genuine worker exit and the existing checks. A native
**two-pipe capture prototype is future work**, requiring its own bounded tests
and review; it is not an implemented or accepted production solution.
General SDS/SCM/PnP retry, cross-attempt lineage, isolated interactive Windows
10/11 UAC, physical power-loss recovery, 100%/150%/200% UI scaling and final
candidate packaging/distribution remain gates. See the
[design](designs/native-launch-observation.md),
[implementation plan](plans/2026-11-11-native-launch-observation.md) and
[release gates](RELEASE-GATES.md).
