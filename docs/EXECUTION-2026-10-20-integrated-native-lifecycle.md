# Integrated native AutoIt VBox lifecycle: CI proof

**Date:** 2026-10-20. **Branch:** `dev/modernization-2026`.
**Executable commit:** [79a5991b](https://github.com/zlocorp/Portable-VirtualBox/commit/79a5991b091e0b76b308a85486d67a8d313791d9).

## What the compiled EXE now does

The hidden `--ci-integrated-session` first rejects ordinary/untrusted context, existing system VirtualBox/services/processes, unsafe portable roots and stale output receipts. It then uses explicit bounded processes to invoke signed pinned VBoxSup staging/start research adapters, checks a running VBoxSup service, runs the real compiled AutoIt VM engine to create/boot/poweroff an empty fixture, independently rechecks its UUID/state through a host verifier, and finally invokes the exact-owned VBoxSDS/VBoxSup cleanup adapter with the stage/start/boot evidence. Cleanup is refused on failed or unknown steps rather than guessed. VM config files remain under the private portable profile.

The PowerShell CI wrapper now only launches the compiled EXE and validates the independent final evidence. A fresh run cannot resume prior receipts.

## Actual verification

- [End-to-end Windows workflow 39494324031](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494324031): **PASS** on a disposable Windows Server 2022 host. Its independent wrapper confirmed successful native VM boot/poweroff, expected signed driver state and service cleanup, preserved VM configuration, `cleanup_verified=true`, `driver_package_removed=true`, zero final VBox services/processes and no report errors. Job log: `PASS: compiled AutoIt orchestrated signed driver install/start, native VM, independent check and owned SDS/driver teardown`.
- [Native AutoIt workflow 39494330200](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494330200): **16 harnesses**, zero failures; new integrated mode policy test has 15 assertions, zero failures.
- [Static + Windows x64 workflow 39494330205](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39494330205): **PASS**, including refusal to enable the integrated mode from the ordinary checkout.

This result tests a real kernel-driver/empty-VM session on **Windows Server 2022**. It is not merely a mock and it is not a Windows 11 compatibility claim.

## Remaining Batch A blockers

- The privileged effects are still *separately executed CI-only PowerShell research adapters*. The compiled EXE controls their order but there is **no production-reviewed, privilege-separated helper**, trusted invocation or standard-user UAC consent flow. GitHub environment markers can be forged and are NOT a security boundary.
- The regular RU/EN GUI still returns `RUNTIME_DISABLED` and does not start/stop Oracle Manager. No normal user access to VM Start/Stop, no runtime window/session tracking or graceful shutdown UX.
- No production crash, reboot, cancellation, removable-drive loss, ownership recovery, real guest disk/OS boot or Windows 11 existing-system-VBox coexistence acceptance.
- CI abandons any uncertain system state to destruction of its disposable host; a user's PC cannot use that recovery strategy.

**No release, master merge or end-user execution is authorized by this research result.** Next: minimal reviewed elevated helper, normal GUI Manager lifecycle and isolated Windows 11 x64 acceptance with existing-install refusal and repeated same-UUID VM sessions.

## Verified Oracle 7.2.22 follow-up (2026-10-20)

Version refreshed from 7.2.20 to **7.2.22-r175245** with the official Oracle SHA256SUMS manifest and fresh exact VBoxSup SYS/INF/CAT hashes. [Package CI 39497891196](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39497891196) verified 185 app64 files (247834716 bytes), signed x64 package and unchanged Windows services. [Compiled native blank VM boot and owned driver teardown CI 39498269366](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39498269366) passed with independent verification on disposable Windows Server 2022. Neither test verifies Windows 11 GUI/UAC or a real guest OS with disk.
