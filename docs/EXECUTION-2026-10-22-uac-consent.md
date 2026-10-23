# Noninteractive UAC waiting: stable frontend and privileged-boundary regression

Date: **2026-10-22**. Tested code: [`f6677580`](https://github.com/zlocorp/Portable-VirtualBox/commit/f667758026ec34ba4d3f4917527a2e32bd832a38), branch `dev/modernization-2026`. Historical `master`, releases and user machines unchanged.

## Problem and correction

The real `ShellExecuteExW runas` consent path cannot be approved by a human on a normal GitHub-hosted Windows Server 2022 CI worker. An earlier GUI acceptance test required a `FAILED` result while the separate medium-token elevation request was still waiting; this conflated missing interactive consent with a completed helper operation.

There was a **separate correctness risk**: if a real human approval arrived after 180 seconds, marking the operation `FAILED` at that point would falsely abandon a still-live request that might mutate drivers later.

The experimental GUI now uses explicit `CONSENT_PREPARE` and `CONSENT_FINISH` states. Only confirmed **completed** request-worker outcomes advance to driver operations or complete cleanup. An outstanding UAC decision does not use the helper-execution timeout. The request process handle remains tracked. A confirmed Windows cancellation is handled separately, with non-destructive preflight rechecks for preparation and an explicit retry option for cleanup.

**No elevation bypass** was added. Real `runas` consent and cancellation still need an interactive Windows 11 acceptance host.

## Completed CI

| Run | Result and exactly what it proves |
| --- | --- |
| [Unattended GUI consent 39737034711](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39737034711) | **Pass:** compiled medium-token GUI showed `CONSENT_PREPARE` and remained responsive to UI queries; no unintended VBox service registration while the tampered input was pending. Recorded `interactive_uac_consent_verified=false`. |
| [Native AutoIt 39737034839](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39737034839) | **Pass:** 21 native harnesses; new phase/pending tests in `test_privilege_boundary.au3` (19 assertions in that harness, zero failures). |
| [Full existing Manager GUI 39737034865](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39737034865) | **Pass:** real Oracle Manager opening, VM remaining running after Manager closes, reopen, second-controller refusal, two exact cleanups and unchanged VM UUID; **already-elevated disposable-host experiment**, not UAC. |
| [Separated helper 39737034920](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39737034920) | **Pass:** actual medium-token Manager and guest, protected Oracle code copy, forged-inventory refusal, protected-write denial, live-guest cleanup refusal and two complete owned cleanups through direct elevated CI invoker. **No interactive UAC.** |
| [Core x64 39737034862](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39737034862) and [Oracle preparation 39737042675](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39737042675) | **Pass:** original non-distributed boundaries, x64 build, and pinned signed Oracle 7.2.22. |

Local Python TDD: **142 discovered tests, five platform skips, zero failures**; the new contract failed against previous code and passed after adding explicit consent states. Native AutoIt confirms actual syntax/policies. This is not visual inspection on Windows 11.

## Still required for normal users

- Actual user confirmation and cancellation of `ShellExecuteExW runas` on an **interactive, isolated Windows 11 x64 workstation** with a standard/non-elevated launcher.
- Correct helper exit paths, cleanup retry after denied UAC, crash/reboot recovery and foreign VBox coexistence without relying on CI-only environment markers.
- Production reviewed privilege broker/helper with clean deployment and no mutable code launched with administrative rights.
- Real guest OS/disk, media preservation, full GUI/DPI/accessibility acceptance.

The six-file diagnostic ZIP remains unchanged; the privileged experiment is not packaged. This is a **CI-reviewed prerequisite**, not completion of Batch A.
