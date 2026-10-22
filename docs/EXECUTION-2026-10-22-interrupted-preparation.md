# Recovery from committed-but-interrupted VBox driver preparation

Date: **2026-10-22**. Branch: `dev/modernization-2026`, PR #7 (Draft). Code [`511372bd`](https://github.com/zlocorp/Portable-VirtualBox/commit/511372bd55bfe75066846f75c573b8c39fb249f6); fix to the **test log lookup only**: [`d96518b6`](https://github.com/zlocorp/Portable-VirtualBox/commit/d96518b63162c753bf9f733a211101a72efbcbba).

## Real implementation

The existing privileged helper validates/pins a protected Oracle code copy and immutable controller identity. Before the first Windows effect it records a protected one-shot `prepare-intent.json`. Independently verified and durable operations then leave distinct evidence:

| Phase | Required evidence | Allowed recovery |
| --- | --- | --- |
| `Stage` | Pinned Oracle signed `VBoxSup.sys`, INF SHA, unique original published `oemNN.inf` from actual PnP transcript and exclusive stage report | Remove only that owned published package, verify no own services remain |
| `Start` | All Stage evidence plus successful signed driver Start report and current running service | Stop same verified driver and remove only that OEM package |
| `Sds` | All Stage/Start evidence plus owned registration marker and matching signed/stopped protected `VBoxSDS` image | Unregister exact owned SDS, stop driver and remove exact INF |

A new `Recover` selection in the **non-distributed experiment** finds a prior protected intent even where full `session.json` was never written. The helper verifies old owner process absent, new same-account medium-controller identity, original protected receipt and pinned paths, no additional VBox processes/services or system Oracle install, and one-shot replay semantics before any mutation.

If *anything* is missing, stale, foreign or ambiguous, it does **not** attempt a guessed driver cleanup. Code/VM data are not deleted. The existing separate full-session abandoned recovery remains intact.

## Tests and evidence

Actual workflow: [`39776758692`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776758692), hosted Windows Server 2022, job **success**. It prepared exact signed Oracle VirtualBox **7.2.22** (185 files) and compiled official AutoIt 3.3.18.0 and the fixed effect helper. It then physically installed/started the **signed** VBoxSup driver and registered/unregistered the **signed** VBoxSDS for each applicable phase.

Job output independently reports:

- `PASS: Stage partial recovery, owner/refusal/replay proof, after-recovery-clean, VM data preserved`
- `PASS: Start partial recovery, owner/refusal/replay proof, after-recovery-clean, VM data preserved`
- `PASS: Sds partial recovery, owner/refusal/replay proof, after-recovery-clean, VM data preserved`
- `PASS: protected PartialRecovery at Stage, Start, Sds checkpoints; old owner refused, missing-receipt-denied, after-recovery-clean, two_copies original_data_preserved; UAC NOT VERIFIED`

Downloaded [artifact **12424846534**](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776758692/artifacts/12424846534) and inspected its **94 entries** rather than inferring success from CI color. `interrupted-recovery-proof.json` reports:

```json
{
  "source_commit": "d96518b63162c753bf9f733a211101a72efbcbba",
  "interactive_uac_verified": false,
  "guest_os_booted": false,
  "validated_checkpoints": ["Stage","Start","Sds"],
  "original_data_preserved": true,
  "two_copies": true,
  "live_owner_denied": true,
  "missing_receipt_denied": true,
  "all_owned_services_removed": true,
  "unauthorized_cleanups": 0
}
```

Individual `cleanup-results.json` receipts confirm `cleanup_basis="PartialRecovery"`, each precise `validated_checkpoint`, `driver_package_removed=true`, `cleanup_verified=true` and empty `errors`. CI on final fix commit [`39776770375`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776770375) compiled x64 core; [`39776764216`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776764216) native AutoIt; [`39776764185`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776764185) Oracle preparation; [`39776758693`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776758693) separate medium-token helper; [`39776758646`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776758646) prior complete-session orphan recovery; all **passed**.

A *different*, earlier run [`39776449641`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776449641) experienced host `VERR_NEM_VM_CREATE_FAILED` under nested virtualization; another [`39776449725`](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39776449725) blocked a second GUI start due to `existing-or-unknown-VirtualBox` after one fully clean cycle. Neither earlier run is retroactively green; retain both as targeted regression investigations. Only the above phase-specific CI qualifies as proof of this recovery feature.

## Boundaries / pending

The recovery is for **already committed step receipts**, not a crash in the middle of `pnputil`, an uncommitted VBoxSup activation, an ambiguous `VBoxSDS` registration or physical restart. It will refuse these situations. No actual Windows 11 interactive UAC prompt/approval, guest OS boot, hostile race-security certification, user-PС elevated helper or release is implied.

The source/code effect modes remain CI/disposable-host only and excluded from the six-file diagnostic preview ZIP. Historical `master` unchanged. Exact author/license notices remain in CREDITS and LICENSE; no new external source imported.

## Independent tamper-refusal extension (2026-10-22)

Commit [`69ed57f5`](https://github.com/zlocorp/Portable-VirtualBox/commit/69ed57f513d815d0b77176a1ad2f81132513ab58) extends the same **real signed driver test** with a three-host matrix, not mocks.

[Windows workflow 39778793621](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39778793621) **all three jobs passed**:

| Dedicated disposable host | Expected result | Inspected protected evidence |
| --- | --- | --- |
| `normal` | Recover Stage, Start and Sds; all own services/INF removed | 94 files, `validated_checkpoints=["Stage","Start","Sds"]`, three confirmed `PartialRecovery` receipts, `unauthorized_cleanups=0` |
| `tamper-stage` | Forged protected `sup-standalone.json.system_driver_sha256` must be denied | 26 files, `forged_receipts_denied=true`, `system_effects_retained_due_to_refusal=true`, no cleanup receipt |
| `tamper-sds` | Forged protected `sds-registered.json.registered` must be denied | 28 files, same refusal flags, no cleanup receipt |

All three saved proofs have `interactive_uac_verified=false`, `guest_os_booted=false`, `original_data_preserved=true` and `unauthorized_cleanups=0`. A refusal leaves resources intact and the one-shot protected proof consumed. We therefore **do not** attempt to repair/retry on the same host: each denial test runs on its **own** disposable Windows runner, which is discarded afterward.

Artifact IDs independently downloaded and inspected: `12425846925` (normal), `12426220616` (forged Stage), `12425911770` (forged Sds). Successful source-contract/native/x64 jobs on the same head further establish this test-only change does not reenable the end-user hypervisor.

