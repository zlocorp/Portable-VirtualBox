# Verified relocation of portable VirtualBox root

Date: 2026-10-20. Based on development branch checkpoint `d161a40c2d93319bbce5a29c41efd12c1aed8c06`.

## Evidence

[Windows CI run 39421860040](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39421860040) completed both independent matrix jobs:
- `relocate-root (directory)`: full root moved from one Unicode path under RUNNER_TEMP to another on the same volume.
- `relocate-root (vhd-letter)`: the same privately created/mounted VHDX volume was reassigned **P: → Q:**; the portable root was reached under the new letter.

Each job reconstructed Oracle VirtualBox 7.2.20 `app64` from verified official MSI/CAB inputs without running the installer, created a small disposable VDI and .vbox in a private portable root, registered a VM, and captured original VM UUID and disk SHA-256.

A supported `VBoxManage unregistervm <UUID>` **without `--delete`** removed the registration while preserving the .vbox and VDI. The experiment then waited for VBoxSDS to become idle and unregistered the service associated with the old app64 image, before moving the root/reassigning the letter.

Under the new path it set `VBOX_USER_HOME`, configured `machinefolder`, and ran `registervm` on the relocated .vbox. The same UUID, disk hash and new media path were verified, with no paths to the old root in the reported disk listing. Finally, the new VBoxSDS was unregistered; no VBox services or processes remained.

Actual logger summary in BOTH jobs:
`moved=True, UUID=True, VDI=True, path=True, service-cleanups=2, succeeded=True`.

## Scope limits

- No guest OS was booted during these migration experiments. Prior two-session VM boot from the same unchanged root was separately proven in [run 39416531988](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39416531988).
- The VHDX letter-change trial emulates changing a removable drive letter. It is not physical USB unplug/replug, a transfer to another computer, or migration of snapshots and differencing disks.
- Unregistration and re-registration were deliberate **when the VM was powered off**; a shipping launcher must not unregister existing user VMs automatically without consent, backups and rollback.
- Both scenarios ran with no system VirtualBox installation, no other VBox clients and no driver installation; they did not test coexistence, crash recovery, Windows 11 standard-user permissions, USB or bridged networking.
- The experiment deliberately did not modify arbitrary `VirtualBox.xml` with text replacement, did not force-kill unrelated processes and did not use `unregistervm --delete`.
- Existing checkout `master` and archived legacy code remain unchanged, and the new production AutoIt launcher is still not connected to privileged operations.

## Expanded real snapshot and stale-registration acceptance (2026-10-27)

[Four independent Windows Server 2022 jobs #40462477639](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40462477639) passed on `392579d7`. Two test modes physically moved the Unicode root directory, and two changed the backing test VHDX letter **P: -> Q:**. For each, the fixture created a real powered-off Oracle snapshot and its differencing VDI. In each geography, one scenario unregistered before the move, while the `-stale` scenario intentionally preserved the old absolute `MachineEntry` until after the move.

Downloaded evidence from all modes confirms `same_uuid`, `same_snapshot_uuid`, `attached_disk_survived`, `snapshot_bytes_preserved`, `snapshot_path_relocated`, `disk_attachment_points_to_new_root` and `machinefolder_points_to_new_root` all **true**. `stale_registration_unregistered` is also **true** in both stale scenarios; Oracle's supported `unregistervm` did not use `--delete`. Every run performed **two** exact-image VBoxSDS cleanups (old/new root), with `services_remaining=[]`, `processes_remaining=[]`, `succeeded=true`, `problems=[]`.

The initial snapshot attempts also exposed a useful Oracle CLI peculiarity: differencing VDI `Location` prints `Snapshots/{UUID}.vdi` inside a Windows path. The test now normalizes **only the read-only listing** before comparing, and never rewrites arbitrary `.vbox` / `VirtualBox.xml` text.

**Not shown:** real USB physical removal, another host CPU/security state, a running VM move, a power-loss during rebind or an approved end-user migration wizard. A manual opt-in repair must still validate local registrations, preserve backups and avoid deleting files.

## Next deliverables

1. Implement an explicit, non-destructive **relocation preflight/plan**, not an automatic migration, that records old/new paths, VM UUIDs, media references and creates recovery backups before any mutation. The plan must remain read-only until the user authorizes migration.
2. Test a VM with snapshot/differencing disk references and deliberate interrupted relocation in isolated Windows.
3. Begin minimal UI/runtime integration using reviewed service and driver adapters, separated from the archived launcher. The release gate is not satisfied by these standalone research workflows.
