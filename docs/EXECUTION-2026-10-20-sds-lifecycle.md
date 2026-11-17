# Disposable VBoxSDS lifecycle verification

Date: 2026-10-20. Development branch `dev/modernization-2026`.

## Verified result

[GitHub Actions run 39413275084](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39413275084) completed successfully on an isolated GitHub-hosted Windows Server 2022 x64 runner.

The tested source is `scripts/vbox_sds_lifecycle.ps1`, with automated contract tests and the separate `.github/workflows/sds-lifecycle.yml`.

- A fresh runner had no existing VirtualBox installation, VBox services or relevant processes.
- The official Oracle 7.2.20 wrapper checksum/signature and passive MSI/CAB extraction were verified. `app64` was prepared without Oracle MSI execution.
- `VBoxManage --version`, `list vms`, `list systemproperties`: all exited zero.
- VBoxSDS was registered by the CLI and its service configuration was verified to refer to the exact prepared `app64\VBoxSDS.exe`, run as LocalSystem with demand-start service settings.
- The test waited for the service to stop naturally and for all VBox processes to exit. It did **not** kill processes by image name or stop a potentially shared service.
- Only after matching the original absence and current expected service image/configuration did it execute Oracle's own `VBoxSDS.exe --unregservice`.
- Final validation found no VBox service registrations or VBox processes remaining.

Logged summary: `registered=True, identity_verified=True, cleanup_allowed=True, result=CLEAN`.

## Important limits

This verifies **a controlled clean-host path**, not a production-safe general cleanup implementation. In particular:

- No installed VirtualBox coexistence, active unrelated VMs, denied service permissions, unexpected process crash or arbitrary changed service configuration was exercised.
- In-service races are not eliminated just by the two snapshots. A future production launcher must track and revalidate acquisition evidence, exact service image/identity, native operation outcomes and any concurrent clients.
- A run that cannot positively prove ownership must not delete the service.
- This experiment does not uninstall or clean up the VBoxSup kernel driver. Signed VBoxSup was separately installed/started and used to boot a blank VM on a disposable Windows runner in [run 39411612414](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39411612414), but full driver removal, reboots and coexistence remain outstanding.
- The preview launcher still does not implement the real protected driver/service lifecycle and is not a functional release. Nothing here was performed on the user's PC or merged into master.

## Next bounded work

1. Test exact-owned standalone VBoxSup *stop and driver-store removal* after a private VM has powered off, with a fail-closed refusal if ownership or idle state cannot be verified. Do not remove pre-existing driver packages.
2. Verify an entirely clean, repeatable two-cycle portable session on a **single disposable Windows host**, preserving a private VM definition between runs. Separate system registration/cleanup from user VM data preservation.
3. Implement reviewed service/driver operations in the AutoIt runtime only after the disposable-host procedures and failure modes are understood. Preserve the archived runtime disabled.
