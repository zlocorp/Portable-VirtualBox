# Two full standalone VirtualBox 7.2.20 empty-VM sessions with cleanup

Date: 2026-10-20. Branch: `dev/modernization-2026` only. **Not a production-safe portable launcher.**

## Scope and evidence

Exact tested code checkpoint: `503b435931655ecb15089e7eea7c96536d58fe53`.

[Windows x64 disposable runner 39416531988](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39416531988) executed **two consecutive sessions on the same GitHub-hosted Windows Server 2022 instance**. Both used an Oracle VirtualBox 7.2.20 binary tree reconstructed from the signed official wrapper, without the Oracle MSI installing the main application. `VBoxSup` was installed separately from its exact pinned Microsoft-signed INF/CAT/SYS through PnPUtil. No USB/bridged networking or Extension Pack was installed.

Each session staged/started VBoxSup, booted an empty headless VM without a guest OS or virtual disk, powered it off, then removed its owned VBoxSDS and VBoxSup resources. The second session reused **the same `VBOX_USER_HOME` and .vbox definition created in the first**. It never ran `createvm` or created a replacement VM. A matching first and second UUID was verified from actual `VBoxManage showvminfo --machinereadable` output.

### Verified two-session sequence

| Observation | First session | Second session |
| --- | --- | --- |
| `pnputil /add-driver VBoxSup.inf /install` | exit 0 | exit 0 |
| `sc.exe start VBoxSup` | exit 0, driver Running | exit 0, driver Running |
| `VBoxManage startvm ... --type headless` | exit 0 | exit 0 |
| Poweroff command and resulting VM state | exit 0; `poweroff` | exit 0; `poweroff` |
| VM UUID | `5cec274b-4386-442c-b12f-21efd3b003cc` | **exact same UUID** |
| `VirtualBox.xml` and original .vbox definition | present | **still present** |
| Orphaned VirtualBoxVM processes | 0 | 0 |
| `VBoxSDS.exe --unregservice` | cleanup confirmed | cleanup confirmed |
| `sc.exe stop VBoxSup` | exit 0 | exit 0 |
| `pnputil /delete-driver oem13.inf /uninstall` | exit 0 | exit 0 |
| Residual `VBoxSup` service removal | guarded `sc.exe delete VBoxSup` exit 0 | guarded `sc.exe delete VBoxSup` exit 0 |
| Final VBox services | **0** | **0** |
| Driver-store INF and `System32\drivers\VBoxSup.sys` | absent | absent |

The JSON evidence artifacts from run 39416531988 were independently read: first and second `cleanup-results.json` both contain `cleanup_verified=true`, `driver_package_removed=true`, `final_vbox_services=[]`, and no errors. Second `vm-boot-results.json` contains `same_vm_identity=true`, `startvm_returned_zero=true`, `poweroff_succeeded=true`, `final_vm_state=poweroff` and zero orphaned VM processes.

### Important Windows primitive-driver finding

Initial tests found that Microsoft PnPUtil can report **driver package uninstalled and deleted successfully** while a `VBoxSup` kernel service entry remains registered and Stopped. This is not a failed INF deletion: the published `oem13.inf` file and `System32\drivers\VBoxSup.sys` were both **absent** after PnPUtil returned exit zero. Waiting 25 seconds did not remove the stale service entry.

On this strictly isolated clean host, and *only* after revalidating the earlier empty VBox baseline, matching signed driver identity, completion of our own VM, absence of VBox processes and both driver files, the test issued **exact** `sc.exe delete VBoxSup`. There was no wildcard deletion, `/force`, and no process termination by name. Final service/driver/INF absence was asserted. Do **not** generalize this guarded experimental step into an unconditional cleanup in the shipping launcher. Windows service deletion still has races and installed-VirtualBox coexistence requirements.

Related failed evidence: [run 39415153143](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39415153143) established PnPUtil success with an orphaned VBoxSup service; [run 39415393006](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39415393006) confirmed the orphan persisted after a bounded wait; [run 39415779193](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39415779193) verified cleanup with the guarded exact service deletion.

## Regression gates

At checkpoint `503b435`, the following independent CI jobs passed:

- [Core Windows x64 build / Linux Python](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39416539292): **89 discovered Python tests, 5 Windows-only skips**, zero failures; x64 compilation, read-only launcher selftests and Unicode-path build pass.
- [Oracle preparation / Windows Python](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39416539308): **89 discovered tests, 1 symlink-privilege skip**, zero failures; verified 185 files / 247,738,522 bytes from Oracle package.
- [Native AutoIt](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39416539319): 9 compiled native test harnesses, **351 assertions, zero failed**.
- [Two full disposable Windows sessions](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39416531988): passed, with both cleanup results and identical original VM UUID.

Different Python platform runs are not additive unique tests. Later documentation commits are not evidence of a new executable-code checkpoint.

## Not yet established

- Running an actual guest OS from a disk, guest additions, snapshots, durable disk data, or bridged/USB networking.
- A safe service/driver strategy on a host with an existing VirtualBox installation, active VM or other VBox service.
- Privilege separation, Windows 11 standard-user behavior, concurrent-process cancellation, crash/reboot recovery, time-of-check races and rollback on arbitrary user systems.
- Moving the portable data directory / USB drive between paths or drive letters, and restoring registered VM paths.
- A working shipping AutoIt launcher: its previous unreviewed privileged runtime is still intentionally excluded from compilation.
- A driver-store uninstall algorithm suitable for any Oracle version or language, as opposed to the exact signed 7.2.20 image on an English disposable Windows Server 2022 runner.

## Next work

Research portable-profile **relocation** between two directories (change of root/drive letter) without copying or rewriting users' XML in place. Prefer supported `VBoxManage unregistervm` (without `--delete`) / `registervm` on disposable fixtures with backup/rollback and carefully validated UUID paths if needed. Separately design the smallest reviewed runtime startup/shutdown orchestration, using the proven guarded actions but never allowing a preexisting system VBox to be stopped/deleted.
