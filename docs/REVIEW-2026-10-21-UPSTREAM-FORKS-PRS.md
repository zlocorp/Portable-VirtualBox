# Review of upstream PRs and community forks

Review date: **2026-10-21**. Target: Portable-VirtualBox modernization in
`zlocorp/Portable-VirtualBox`, branch `dev/modernization-2026`.
This is **research and feature/test prioritization**, not authorization to
merge external code into the product.

## Coverage and provenance

- [Original upstream](https://github.com/vboxme/Portable-VirtualBox) `master`
  currently points to `5b58dbbe701c3e2eb348942a9059708063b0cb96`
  (2024-10-23). This is **already** the exact reference snapshot used by our
  modernization: merged PRs through then are part of the historic upstream,
  not newly missing source.
- Reviewed the **28 upstream pull request titles, statuses, dates** and
  inspected substantive patches for **#90, #91, #92, #95, #100, #68, #69,
  #70**. [PR list](https://github.com/vboxme/Portable-VirtualBox/pulls?q=is%3Apr+sort%3Aupdated-desc).
  Excluded our own upstream PR #106 from "other authors" conclusions.
- Examined current source/commits/README where relevant for
  [Deac2 (September 2026)](https://github.com/Deac2/Portable-VirtualBox),
  [Deac2 NewMenuTest](https://github.com/Deac2/Portable-VirtualBox_NewMenuTest),
  [Deac2 old-menu fork](https://github.com/Deac2/Portable-VirtualBox_PULL),
  [ThatAdminGuy](https://github.com/ThatAdminGuy/portable-virtualbox),
  [bitamind](https://github.com/bitamind/Portable-VirtualBox),
  [SpruceGuy7](https://github.com/SpruceGuy7/Portable-VirtualBox7).
  Git compare confirmed **Nizhal**, **AmesianX** and **alphastar868** forks'
  default `master` refs are *identical* to upstream, so they contain no
  unique changes to review.
- Upstream has roughly **246 forks**, but this is a focused review of
  substantive and recently updated candidates, **not every fork**.

## Relevant upstream PRs

| Source | Concrete finding | Decision |
| --- | --- | --- |
| [#90, merged (2024)](https://github.com/vboxme/Portable-VirtualBox/pull/90) | Exit splash could obscure a VM that was still running. Switches to tray feedback, updates driver service name and exit flow. | **Adopt test intent**: Manager close must not imply VM stopped, and status UI must not obscure the guest. Do **not** copy legacy `sc`/process-name logic. |
| [#92, merged (2024)](https://github.com/vboxme/Portable-VirtualBox/pull/92) | Partial download/frozen download, missing `Machines` directory on relocation, first-run language selector and network-driver installation fixes. | **High-value regression cases** for intact verified download, missing folder and drive relocation; native old installer/network-driver code is unsuitable. |
| [#95, closed, not merged (2024)](https://github.com/vboxme/Portable-VirtualBox/pull/95) | Author reports driver path with spaces and legacy UTF-16 locale encoding problems; PR diff actually removes large parts of old source. | **Test cases, not patch**. Our signed VBoxSup test already uses Unicode/space-containing runner path; keep checking the eventual GUI/helper. |
| [#100, open (2025)](https://github.com/vboxme/Portable-VirtualBox/pull/100) | Updated Oracle 7.x icon and retired splash image. | **Optional artwork review only** after the working GUI and attribution check. No functional improvement. |
| [#69 and #68, merged (2019)](https://github.com/vboxme/Portable-VirtualBox/pull/69) | English copy editing and old translated INIs. | Superseded by the new embedded RU/EN catalog. Do not restore old INIs. |
| [#91, merged (2024)](https://github.com/vboxme/Portable-VirtualBox/pull/91) | Broad legacy repackage including EXEs, language files and buildfast batch. | **Do not import**: it would undo the just-proven dependency cleanup. |

## Relevant forks and risk assessment

| Fork | Specific useful part | Why its runtime cannot be copied as-is |
| --- | --- | --- |
| [Deac2](https://github.com/Deac2/Portable-VirtualBox), updated **2026-09-13**; [NewMenuTest](https://github.com/Deac2/Portable-VirtualBox_NewMenuTest) | New setup/settings windows, more direct RU/EN language choices, first-run UX; menu screenshots/flow as reference for **Batch B**. | Active AutoIt source contains `#RequireAdmin` for the whole app, process-name termination and `VBoxSDS /RegService` or `/UnregService` paths without an independently reviewed per-run capability. Also has a global pseudo-single-instance window title. |
| [ThatAdminGuy](https://github.com/ThatAdminGuy/portable-virtualbox), last code **2023-05-24** | Explicitly considers `VirtualBox.exe`, `VirtualBoxVM.exe`, `VBoxHeadless.exe`, `VBoxSVC.exe` during shutdown; README calls out VC++ runtime availability and Hyper-V coexistence as environment concerns. | Code uses process-name waits and `#RequireAdmin`. Never kill another user's VM or change `bcdedit`/Hyper-V automatically. Replace with exact observed process identities and consented diagnostics. |
| [bitamind](https://github.com/bitamind/Portable-VirtualBox), last code **2025-09-25** | Recognizes Oracle-specific `VBoxSDS.exe /reregservice` and `/unregservice` rather than `sc create/delete`; reinforces need for service-aware cleanup. | Code also uses `ProcessClose("VBoxSVC.exe")` and service probes based on names. Our independently verified exact-owned SDS teardown is stricter; no adoption. |
| [SpruceGuy7](https://github.com/SpruceGuy7/Portable-VirtualBox7), last code **2023-11** | A [user report](https://github.com/SpruceGuy7/Portable-VirtualBox7/issues/2) describes the launcher EXE disappearing during extraction/update and Windows 11 guest issues. Useful for **Batch C packaging rollback testing**. | Older 7.0.x-era code and unsigned bundled tools; cannot establish VirtualBox 7.2.22 behavior. |
| [Deac2 old-menu fork](https://github.com/Deac2/Portable-VirtualBox_PULL) | Historical feature/translation comparison. | Old architecture and duplicated binaries; no advantage over modern code. |

## High-value upstream user reports

- [#104, 2025](https://github.com/vboxme/Portable-VirtualBox/issues/104):
  moving/renaming the portable root led to startup logs referring to an old
  `VirtualBoxVM.exe` path. Our relocation CI tested powered-off fixtures
  on one isolated host; **abandoned/stale service/driver registrations and
  VM medium chains across hosts remain unproven**.
- [#105, 2026](https://github.com/vboxme/Portable-VirtualBox/issues/105):
  first-run extraction/update-path loop. Stage new verified files atomically,
  report exact blockers and preserve existing data.
- [#98, 2024](https://github.com/vboxme/Portable-VirtualBox/issues/98):
  user reports failure adding a VM and next-launch error after exit. Test
  reentrancy, existing VM UUID, cancellation and partial shutdown.
- [#103, 2025](https://github.com/vboxme/Portable-VirtualBox/issues/103):
  missing `VBoxManage.exe` is a real-world failure, not an acceptable
  silent fallback. Our readiness already blocks absent `app64`.

## Product impact: targeted acceptance, not wholesale adoption

**Batch A priorities:** launch the real Manager through a *non-elevated*
AutoIt UI and narrowly scoped, reviewed elevated driver helper; check
all VM processes by native identity and state before teardown; demonstrate
two same-UUID cycles on isolated Windows 11; refuse foreign/stale VBoxSDS,
interrupted cleanup and relocation while a service points at the old path.
No forced global process-name termination, blanket `#RequireAdmin`,
unverified direct XML edits, or silent system Hyper-V/BCD changes.

**Batch B priorities:** user-selected portable paths, safe preflight for
old/missing `Machines` folders, Unicode/space/drive-change handling,
snapshot/differencing-media chain inspection, useful first-run settings
and language controls.

**Batch C priorities:** partial download and hash-failure rollback,
transactional staged update that never deletes the launcher EXE or VM data,
optional icon refresh after review, no legacy `7za`/DevCon/SnetCfg binaries.

**Already addressed or partly covered:** signed Oracle 7.2.22 app64 from
hash-checked installer, bounded verified download, Unicode-path driver
research, compiled empty-VM boot, exact-owned service teardown,
portable-root/VHDX relocation fixture. Those tests do not prove production
Windows 11 user/USB/snapshot/crash recovery.

**No external commits, release binaries, INI translations or art assets
were merged or copied** during this review. Original master remains untouched.
