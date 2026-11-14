# Portable root relocation: isolated Windows research plan

Date: 2026-10-20. Source: `dev/modernization-2026` at `9e555f65723cc7027b49b4a28dc6578c8a217842`.

## Goal

Demonstrate that a fully self-contained Oracle VirtualBox 7.2.20 `app64` and VM profile can be moved **as one directory** to a different full path without corrupting a VM definition, losing its UUID, or leaving a service pointing to the old location.

## Scope and boundaries

- Run only on an **ephemeral GitHub-hosted Windows Server 2022** VM with no existing Oracle VirtualBox installation, services or processes.
- Use the verified, reconstructed signed Oracle `app64`, not an installed system package.
- No guest OS boots, no kernel driver installation, no external real-world disks/VMs, no `unregistervm --delete`, XML text replacement or process-name termination.
- Build a disposable VM and a small attached virtual disk entirely under a temporary source root. `VBOX_USER_HOME` and `machinefolder` must both be located inside the root.
- Record original UUID and disk SHA-256. Unregister **without deletion**, then gracefully retire the exact session-owned `VBoxSDS` service, ensuring its old-root image path is gone **before** moving the whole root.
- Move the entire root once to a distinct path containing spaces/Cyrillic. Set `VBOX_USER_HOME` to the new root, register the existing `.vbox` using `VBoxManage registervm`, and set the default machine folder to its new location. Verify same UUID, registered machine, disk hash, and the existing disk attachment.
- Retire the newly auto-registered VBoxSDS with exact image/path identity and no live VBox processes; verify no services and no private VM files outside the relocated root.
- Do not publish Oracle binaries or the VM. Only bounded JSON outcomes and redacted CLI diagnostics.

## Acceptance

1. Initial clean host and exact signed binary checks pass; environment/profile are isolated under RUNNER_TEMP.
2. Before the move: VM is powered off, its UUID and attached VDI are confirmed, no other VM is registered, and the VDI/VM file are within the portable root. Backups stay private.
3. No VBoxSDS points to the source root at move time, and no VBox process remains.
4. After moving: both source and destination may not exist simultaneously; the source root is gone and the new root exists.
5. `registervm` recognizes the same UUID and attached VDI; disk hash matches. A path alias to the old root is not accepted as success.
6. New-root VBoxSDS cleanup leaves no service/process entries; VM files stay intact.
7. If any check fails: preserve evidence and VM files, **do not** attempt speculative cleanup, overwrite a destination or mutate unrelated installations.
8. Run Python contract tests on Windows/Linux and this actual Windows executable test. Record exact commit/run IDs.

## Not demonstrated

Removable USB unplug/replug, a *different physical volume* or drive letter, snapshot/differencing disk relocation, cross-machine VM compatibility, live guest OS boot, dirty shutdown/crash recovery, installed Oracle coexistence and production-service ownership in AutoIt.

## Next

If same-volume root relocation passes, test drive-letter remapping on a hosted disposable machine separately. The shipping launcher should use a read-only preflight plus explicit, reversible steps, not automatically edit arbitrary VM XML.
