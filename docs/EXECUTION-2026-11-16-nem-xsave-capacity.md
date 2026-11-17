# Observed Oracle NEM XSAVE-capacity refusal

## Exact failed execution

- Source: `342f8b7d9ddd959d07a5e1dc02dcaa4f7e9d40de` (test-only changes; production launch/driver logic unchanged).
- [Helper boundary run 43859239115](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43859239115), main-launcher job `133271381991`: failure. The separate session-test variant succeeded; it does not establish guest-OS acceptance for main-launcher.
- [Artifact 14222482588](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/43859239115/artifacts/14222482588): ZIP SHA-256 `ce11e4653afb714628f7b844b2a5c444b677d3219f4463d8005fe3beaaed20eb`, independently recomputed with ZIP CRC verified.
- Exported `Logs/VBox.log`: 47,064 bytes, offset zero, not truncated. UUID `f08240e2-0303-4e13-8ae2-bb290070ca97` matches the fixture creation evidence.
- Oracle VirtualBox reports 7.2.22. The direct guest process exited 0 while printing a VM-start error; the fixture correctly refused to equate that process exit with a running guest.

All 12 naturally triggered workflows finished: 11 successes and this one failed helper workflow. No diagnostic rerun was requested. The failed main-launcher variant is not covered by the successful session-test variant.

## What the actual log establishes

The Windows NEM backend created a Hyper-V partition, then reported `cbXSaveArea=10752`. Its next capacity assertion states:

```
Returned XSAVE area exceeds what VirtualBox supported (10752 > 8192)
```

It destroyed the partition and returned `VERR_NEM_VM_CREATE_FAILED`; the VM state became PoweredOff. This is a concrete host/Oracle NEM XSAVE-capacity incompatibility observed on this run, not a guest-login/readiness failure, an SDS registration refusal or evidence of driver-cleanup failure.

The failed host exposes Intel family/model/stepping `6/cf/2`, host XCR0 `0x600e7`. Earlier independently verified successful NEM artifacts at `c717bed` show:

| Artifact | Host observation | NEM XSAVE bytes | Result |
| --- | --- | ---: | --- |
| 14216967576, helper main | AMD `19/1/1`, XCR0 `0x7` | 872 | guest/cleanup accepted in its scope |
| 14216809083, helper session | AMD `19/1/1`, XCR0 `0x7` | 872 | narrow session fixture accepted |
| 14217257978, Main GUI | AMD `19/11/1`, XCR0 `0xe7` | 2472 | GUI fixture accepted, no guest ISO |
| 14217651491, Alpine | AMD `19/11/1` | 872 | guest/readback accepted in its scope |

Both successful and failed logs use NEM/Hyper-V and contain the physical-address-width capability warning. That warning alone does not distinguish the failure. These are observations from different hosted machines, not a controlled experiment proving a particular CPU feature is the sole causal variable.

## Upstream corroboration, not an applied fix

The [official VBox-7.2 backend source](https://github.com/VirtualBox/virtualbox/blob/VBox-7.2/src/VBox/VMM/VMMR3/target-x86/NEMR3Native-win-x86.cpp) queries the Windows hypervisor XSAVE size and returns the same error when it exceeds the guest-state storage capacity. This is branch-source corroboration, not a verified reconstruction of the exact binary build.

[Official issue #430](https://github.com/VirtualBox/virtualbox/issues/430) reports the same capacity mismatch on Hyper-V/AMX-capable hosts. It was open when checked on 2026-11-16. The matching report is not proof of a safe workaround or an upstream fix in the pinned package.

## What remains unproved

The failed artifact has no successful cleanup receipt. Its guest boot/write/readback/snapshot and two-cycle-clean flags remain false. Do not report that this failed host was cleaned successfully. Its eventual disposable-runner teardown is not application recovery evidence.

No rerun, host-feature change, Hyper-V/security disabling, CPU masking, Oracle replacement or cleanup replay was performed. This new log does not retroactively prove the cause of earlier NEM failures that lacked exported VM logs. SDS exit-0/missing-key failures are a separate unresolved problem.

The ALPHA archive at this source has independently checked manifest/hash/pairing integrity, but this runtime refusal and the missing isolated Windows 10/11 interactive acceptance prevent promoting it as an everyday-use release. A compatible hosted run elsewhere cannot erase this failure. Any future compatibility policy must be explicit and evidence-backed; do not turn the refusal into a passing test or automatic destructive retry.
