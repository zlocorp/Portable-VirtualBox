# Explicit launch environment execution record

Date: 2026-11-11. Source commit
`929c3463d1c717f6bceefabb276e4f3b63f38691`, tree
`5ebc240f85619ef23d5aa4fbdc8cc9b32fb5d211`.
This accepts a test-only hosted observation, not privileged image admission,
production integration, workstation acceptance or release approval.

## Scope and local verification

The retained fixed-child owner now has an opt-in closed four-key environment
policy. SystemRoot and WINDIR come from one bounded native OS query; the other
values are fixed Unicode text and a present-empty entry. The serializer validates
name/count/UTF-16/size limits before allocating a bounded UTF-16LE block.
One-shot allocation/release and explicit create-entry states retain uncertain
resources. The native launch entry accepts no arbitrary environment map.

A separate three-case environment harness observes normal operation, a controlled
post-create fault and a controlled diagnostic-sink fault. Only environment mode
uses 16-byte read requests. Diagnostic failure does not poison the retained
observation capture. The nine prior child-capture cases, their assertions and
report schema remain unchanged. Production source/scripts are unchanged.

Independent source review accepted the implementation. Final local verification
passed 369 Python tests with six platform skips, including 24 new environment
contracts independently rerun with PowerShell. Managed tests passed 372 codec and
73 policy assertions plus bounded observation/parser/free, sentinel and fragmented
capture contracts. The environment harness, baseline harness and child compiled
C# 5/x64/net48 with warnings as errors. Both Windows compiler runners explicitly
select UTF-8 source decoding. PowerShell/YAML parsing, active-tree, enforced source
audit and whitespace checks passed. Linux did not run the Windows native cases.

## Source-associated workflows

The exact source-head inventory contains 11 naturally triggered workflows (eight
push, three PR). All 11 passed on attempt 1, with no rerun, cancellation or
manual dispatch. These results apply to this source, not later documentation heads.

- Native push [43080434777](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080434777),
  job [130731260659](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080434777/job/130731260659).
- Native PR [43080444665](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080444665),
  job [130731291607](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080444665/job/130731291607).
- Build push [43080434589](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080434589).
- Build PR [43080444625](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080444625).
- Oracle preparation PR [43080444990](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080444990).
- Source snapshot [43080435754](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080435754).
- Fixed helper [43080434992](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080434992).
- Noninteractive pending UAC [43080435202](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080435202).
- Interrupted preparation [43080434456](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080434456).
- Orphan recovery [43080434435](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080434435).
- Private payload continuation [43080434437](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43080434437).

Both native runs passed on attempt 1. Push checked out the exact source commit;
PR checked out synthetic merge `dcb89ac8a59e6ee51b51814884508cfec7e51f75`.
Workflow head SHA is not sufficient to identify a PR job's actual checkout.
Both jobs ran Windows Server 2022 build 10.0.20348, runner image 20261101.353.1.
The environment step and existing child, launch and pipe steps actually executed
successfully; the workflow wrapper alone was not used as evidence.

## Independent artifact verification

Each environment artifact contains only `native-launch-environment.jsonl`:
2,525 bytes, four strict records, at most 793 bytes per line including newline.
The push and PR environment JSONLs are identical, SHA-256
`e8882b83bdafe3945d73ecc3a310bd87851defbd887cc6a25e77e2751b9812bd`.
Both ZIPs are 677 bytes; their ZIP digests differ because archive bytes differ.

- Push environment artifact `13883058955`: ZIP SHA-256
  `ba1cfba791dbb24538f6f7412d0fdf535691f3ce423786beb35fd1d657cf7733`.
- PR environment artifact `13884376521`: ZIP SHA-256
  `ded0bf8ad026e562ec6149b38d70a7731384ef45f7dd3844a4852cbc09735430`.
- Push baseline artifact `13883213959`: ZIP SHA-256
  `7bfa9438ef6f89395bdb04345963737c4a0460f8fc674bfca070a1933180e87a`.
- PR baseline artifact `13884596123`: ZIP SHA-256
  `fa6cb4be3c77c6f61584c8d0e4aba47a2a04c327f9a5fdfb05af04268c9bb8b6`.

Downloaded ZIP digests match GitHub metadata. Independent review decoded the
actual 110-byte PVE1 record in each case, separately from the OS-query expectation:

- The ambient sentinel is absent in the child.
- The text is exactly `Привет = fixture 🙂`, including the supplementary scalar.
- The empty value is present with zero length, not absent.
- Both directory values are `C:\Windows`, matching the separate OS query.

Each case captured 118 stdout bytes: the eight-byte handle probe plus the full
110-byte environment record. The diagnostic fault was observed at byte eight,
before that record arrived. All bytes were nevertheless retained and parsed.
All three cases report actual child exit, both EOFs, explicit owned-resource
release and exact parent-sentinel restoration. The two fault cases remain UNKNOWN
while their expected-fault test assertions pass. Every record has
`mutation_authorized=false`.

All nine baseline stream counts/hashes and exit codes were independently
recomputed at this new source. Their lifetime facts and stable semantics match
both earlier reviewed baseline artifacts. This rechecks the shared implementation
rather than assuming its prior results survived the environment extension.

## Limits retained

The child's environment observation is a fixed-fixture self-report with actual
captured bytes. It is not a general process-environment census, image attestation,
loader/dependency isolation or proof against a malicious child. Matching disk
bytes, protected ancestry and loaded-image identity are separate unanswered
questions. The existing fixed sibling image lease remains managed-disposal
evidence, not a newly established checked native file-handle close.

Native unavailable-create returns, persistent wait failure, real OOM and physical
power loss were not induced. Managed state tests do not become native fault
observations. The current production outer-worker launch/capture/wait and nested
VBoxSDS lifetime gaps remain; no production helper path was replaced. General
system-effect retry, lineage/admission authority and isolated Windows 10/11
interactive UAC/DPI/security/final-host acceptance remain release gates.
No primary Windows host, valuable VM, merge or release was involved.
