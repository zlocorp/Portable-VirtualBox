# Isolated Windows 10/11 x64 alpha test (NOT a release)

This is an **unverified developer candidate**, not a stable VirtualBox launcher.
Never run it on the only copy of a useful Windows system or valuable VMs.
GitHub-hosted Windows Server tests verify refusal, not interactive Windows 11
driver installation or UAC approval/cancellation.

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

Protected alpha receipts live in `%ProgramData%/PortableVirtualBox.Alpha`,
separate from CI experiments. Do not edit those receipts. The package includes
no Oracle binaries, guest OS disks or running VMs. It is **not a release**:
unsigned frontend executables may trigger Windows publisher warnings; do not
disable UAC, AV, HVCI or SmartScreen to bypass them.

A real interactive isolated Windows host is required to complete acceptance.
