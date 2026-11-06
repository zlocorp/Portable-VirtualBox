# Isolated Windows 10/11 x64 alpha test (NOT a release)

This is an **unverified developer candidate**, not a stable VirtualBox launcher.
Never run it on the only copy of a useful Windows system or valuable VMs.
GitHub-hosted Windows Server tests verify refusal, not interactive Windows 11
driver installation or UAC approval/cancellation. The same compiled main
launcher has independently booted Alpine Linux x86-64 and verified a real
guest-written VDI sector after full driver teardown/restart in
[isolated CI #40407596523](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40407596523);
that does **not** certify its privileged ALPHA build on a workstation.

Use only an isolated, disposable Windows 10 22H2 or Windows 11 x64 workstation
with a recoverable host snapshot, no installed VirtualBox and no foreign VBox
drivers/services/processes. The non-elevated launcher currently requires an
administrator account running with a **medium UAC split token**. Elevation by
entering another administrator's credentials from a standard account is not
yet supported: the helper rejects a different user SID.

Extract the archive into a new writable regular folder (no junctions). Verify
SHA256SUMS.txt, then run `./Portable-VirtualBox.exe --alpha-runtime` from a
**non-elevated** PowerShell window. Plain double-click still opens the
diagnostic-only frontend. Click **Prepare VirtualBox / folders** and choose an
official download or local pinned Oracle 7.2.22 EXE. No installed Python is
needed and preparation never executes Oracle MSI.

Select **Start / Stop VirtualBox**, then **Start VirtualBox**. The fixed-action
helper requests UAC for system driver operations. In the actual Oracle Manager,
create a disposable VM with a small VDI, run a test guest OS, power it off,
close/reopen Manager, verify VM disk and snapshots, then Finish session.
Confirm owned VBoxSup/VBoxSDS are absent and user VM files remain. Repeat once.

Deny UAC on a clean Start, then test a successful Start and a cancelled Finish.
Cancelled Finish retains protected resources; explicitly retry Finish. You may
also click Close and **confirm** leaving drivers/services installed. That action
exits the entire original controller and leaves exact protected receipts so a
fresh `--alpha-runtime` launch can choose Recover. Never assume cancel means
resources were deleted. If a
controller crashed, Recover abandoned session uses one-shot protected receipts.
Uncertain original owner, disk or driver status requires restoring the disposable
host snapshot, never forced process kills or guessed `sc delete` commands.
If the Manager window reports **FAILED**, the ALPHA build now explicitly warns
that VM processes, services or drivers may remain active. A confirmed exit
closes the whole controller and preserves receipts for manual inspection or
later one-shot recovery. Canceling the warning keeps the controller running;
never interpret FAILED as proof that cleanup completed.

Protected alpha receipts live in `%ProgramData%/PortableVirtualBox.Alpha`,
separate from CI experiments. Do not edit those receipts. The package includes
no Oracle binaries, guest OS disks or running VMs. It is **not a release**:
unsigned frontend executables may trigger Windows publisher warnings; do not
disable UAC, AV, HVCI or SmartScreen to bypass them.

Before attempting any relocation, finish all guests and verify exact-owned
driver cleanup. After moving the entire portable root, use the normal main
EXE's read-only `--plan-vm-rebind`, then
`--prepare-vm-rebind "NEW_BACKUP_FOLDER"` on an idle host. Preparation requires
**one** powered-off local VM/snapshot chain and an absent original VM path.
It makes a verified full data copy and **does not edit VirtualBox.xml or run
Oracle to repair the stale entry**. Keep that original backup intact.

**Multiple-VM registration repair is still unavailable.** The independent
`--prepare-multi-vm-rebind "NEW_BACKUP_FOLDER"` CLI action can now create a
SHA-256 verified full `data/` copy for a read-only 2–16 VM candidate.
It requires an idle host, a fresh destination and a second exact candidate
check after copying. A `BACKUP_ONLY` result verifies files, **not**
registration repair, ownership or permission for any system operation.
Preserve the original root and independently inspect the backup manifest.
Do not perform repeated single-VM ALPHA repairs to simulate a transaction.

**Multiple-VM relocation is currently inspection-only.** On an idle host,
`Portable-VirtualBox.exe --plan-multi-vm-rebind` can report 2–16 machines
that appear to share the same absent original portable root. It verifies
registered UUID/path identity, local VDI/snapshot and ancillary files, and
unchanged observed configuration data. Exit 0 is **REVIEW_ONLY**, not an
authorization to call Oracle or clean drivers. The command does not back up
or repair anything. Preserve the entire original root and an independently
verified offline backup. `--prepare-vm-rebind` and the ALPHA repair button
remain limited to exactly one VM; do not apply them repeatedly to a batch.
No physical cross-host, saved-state or interrupted multi-VM transaction
acceptance exists.

For the separate explicit repair acceptance on the disposable workstation:

1. Open the Manager-session window under `--alpha-runtime` and select
   **Repair moved VM**. First cancel folder selection and then try again and
   answer **No** at confirmation. Both refusals must preserve registration,
   VM files, backup and system resources.
2. Select the original verified backup again. Check the displayed UUID, old
   and new paths, backup location and `UNREGISTER_REGISTER` action before
   confirming. The existing protected session prepares owned components;
   ordinary-token Oracle unregisters without deletion and registers the
   unchanged local VM. An unknown result must stop advancement.
3. In Manager, verify the original VM and snapshot, then finish the session
   and confirm owned cleanup. Repeat **Repair moved VM**: already-local
   registration must report that no change is required, with no preparation.

If an earlier repair stopped after unregister, first complete any required
explicit owned-session recovery. A fresh controller may use the **same
original backup** to confirm `REGISTER_ONLY` when the registry is valid and
empty and all protected VM/backup data still match. This never authorizes
deletion or another unregister. Changed or ambiguous data require inspection.
Do not create an interruption by deleting XML entries or power-cutting a
valuable host; arbitrary power-loss recovery remains unaccepted.

The four directory/drive-letter relocation variants passed on disposable CI
hosts ([results](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/40462477639)).
Current explicit GUI repair and reconstructed inter-command recovery results
are tracked in [Draft PR #7](https://github.com/zlocorp/Portable-VirtualBox/pull/7).
Saved-state migration, multiple-VM repair and physical cross-host transfer
still require separate acceptance. No automatic registration repair is enabled.

A real interactive isolated Windows host is required to complete acceptance.

## Service diagnostics and portable CLI

Capture `./Portable-VirtualBox.exe --diagnose-services-json` before Prepare,
during the session and after Finish. The text equivalent is
`--lang ru --diagnose-services` (or `en`). No Oracle runtime or elevation is
required for these reports. JSON schema 1 has the fixed service list and no
private image/account paths. Exit 0 means readable observations, not readiness;
4 is unknown and 64 is invalid arguments. `UNVERIFIED` ownership must never be
used to decide that a service can be removed. Pending states are visible only
in the presentation snapshot; strict runtime checks remain unchanged.

After ALPHA Prepare has completed and Manager is open, from an ordinary terminal:

```powershell
.\VBoxManage.cmd --portable-help
.\VBoxManage.cmd list vms
.\VBoxManage.cmd list runningvms
```

The wrapper uses the build-paired `VBoxManagePortable.exe`, the live protected
session's verified Oracle copy and this root's `data\.VirtualBox`. It must refuse
Oracle commands before preparation and after cleanup, or while cleanup owns the
command gate. Keep the launcher alive and finish the session there. Do not use
administrator elevation or a different build's adapter to bypass a refusal.
Oracle commands can mutate VM data; this is not a safety sandbox. Destructive
`unregistervm --delete` is explicitly refused, but other user-selected Oracle
commands still require care and backups. Adapter arguments/cwd/exit-code and
lease tests run in Windows CI; workstation acceptance remains a separate gate.


## Russian localization: CI results and workstation acceptance

At `3301638`, the [compiled launcher](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/41537264954)
and [extended Oracle/Alpine scenario](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/41537257180)
passed on disposable Windows Server CI. Native tests passed 309 new localization
assertions. The RU/EN/RU launcher screenshots and all three Oracle language
captures were inspected. Oracle's visible USB-enumeration warning is retained;
USB passthrough is not part of this acceptance. These checks do not replace
interactive UAC, every DPI or ordinary workstation driver acceptance.

For the remaining workstation procedure, use only the existing isolated host
and disposable VM procedure above. Do not use personal VMs.

1. In the ordinary launcher select Russian. Check all captions, disabled-button
   tooltip, installer picker filter and long backup buttons. Switch RU -> EN ->
   RU: backup status must retain its meaning and target, not a stale language.
   The read-only GUI test must not create data/app64/logs or start Oracle.
2. Save `ru` explicitly. Start a full ALPHA session using the normal consent
   path. Both `nls/VirtualBox_ru.qm` and `nls/qt_ru.qm` must be present from the
   pinned Oracle preparation. Require actual Russian menu/button captions in
   Oracle Manager, not just a successful language-key readback.
3. Close/reopen Manager while the disposable guest runs. Language remains
   Russian; guest and snapshot behavior remains unchanged. The reopen path
   must not issue another language-setting command.
4. Finish and verify exact-owned cleanup. Save `en`, start another complete
   session and require Oracle's English interface (`GUI/LanguageID=C`).
   The previous VM UUID, disks and snapshots must remain intact.
5. With launcher preference `auto`, or with a temporary `--lang ru/en`, verify
   Oracle's independently saved language is not overwritten. Unknown or
   malformed preference evidence must not become a success or cleanup permit.

The CI variant keeps its launcher controls in temporary English to retain the
existing GUI harness, while using saved RU/EN for Oracle; it is not interactive
Windows 11 UAC acceptance. Artifacts must include actual Oracle accessibility
captions and screenshots plus the existing guest/repair/cleanup proof. The
standalone GUI artifact includes measured captions and screenshots; metric
checks alone do not establish correct rendering at every DPI or screen size.
