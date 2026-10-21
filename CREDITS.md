# Credits and provenance

## Original project

This is an adaptation of **Portable-VirtualBox**, based on [vboxme/Portable-VirtualBox](https://github.com/vboxme/Portable-VirtualBox) at [`5b58dbbe701c3e2eb348942a9059708063b0cb96`](https://github.com/vboxme/Portable-VirtualBox/tree/5b58dbbe701c3e2eb348942a9059708063b0cb96).

The inherited source credits **Michael Meyer (michaelm_007) and contributors**. We also acknowledge the **vboxme / Runar Buvik** project and its contributors. Original notices remain in source and [LICENSE.md](LICENSE.md), **CC BY-NC-SA 3.0**. The 2026 changes are maintained in **zlocorp/Portable-VirtualBox** and are explicitly identified as modifications, not an official upstream or Oracle release.

## Community ideas and independently adapted behavior

The following entries describe the **kind of reuse**, rather than implying wholesale code imports. Community runtime code was not cherry-picked by this package; source links document the ideas and scenarios that informed independent implementations.

| Author / source | Material used | Adoption and location |
| --- | --- | --- |
| **Deac2**, [current project README/settings](https://github.com/Deac2/Portable-VirtualBox/blob/main/README.md), reviewed 2026-10-21 (source snapshot `b48539aec1`) | First-run language selection, remembered preference and readable settings UX | Independently adapted in `LauncherSettings.au3` and GUI Save/Windows-language controls. No external language file or runtime source copied. |
| **Deac2**, [upstream PR #92](https://github.com/vboxme/Portable-VirtualBox/pull/92) | Missing Machines directory and relocation/download failure scenarios | Exact missing-directory messages and regression coverage; full migration/updater work is still pending. The old merged patch was already part of the inherited baseline. |
| **t1m013y**, [upstream issue #103](https://github.com/vboxme/Portable-VirtualBox/issues/103), plus [extraction report #105](https://github.com/vboxme/Portable-VirtualBox/issues/105) | Missing/undiscoverable VBoxManage and failed extraction concerns | Motivated the native `app64` completeness inspection. The 15-file requirement itself comes from this project's already verified MSI staging contract. |
| **ThatAdminGuy**, [commit a035d06b12](https://github.com/ThatAdminGuy/portable-virtualbox/commit/a035d06b12) | Manager, GUI VM and headless VM have separate lifetimes | Independently implemented diagnostic categories in `HostPreflight.au3`; no process-name killing or legacy shell commands copied. Full production shutdown remains pending. |
| **skyshay001**, [upstream PR #90](https://github.com/vboxme/Portable-VirtualBox/pull/90) | A closing Manager/splash must not imply the guest exited | Diagnostic/regression scenario and acceptance requirement; no new tray UI or shutdown claim. |
| **bitamind**, [VBoxSDS commit 4ffc9e097f](https://github.com/bitamind/Portable-VirtualBox/commit/4ffc9e097f) | Oracle-specific registration/unregistration commands | Research reference for the pre-existing independently verified CI-only SDS lifecycle, not a production helper import. |
| **janpio**, [PR #69](https://github.com/vboxme/Portable-VirtualBox/pull/69), and **araname**, [PR #68](https://github.com/vboxme/Portable-VirtualBox/pull/68) | Clear English wording and locale/encoding pitfalls | Historical language-review references. Modern RU/EN strings are maintained independently; old INIs are not restored. |

## Reviewed, but not used as shipped code or artwork

**SpruceGuy7**'s [issue #2](https://github.com/SpruceGuy7/Portable-VirtualBox7/issues/2) informs a **pending** updater regression: preserve the launcher and user data on extraction failure. **alphastar868**'s [PR #100](https://github.com/vboxme/Portable-VirtualBox/pull/100) offers optional 7.x artwork; **neither icon nor splash was imported**. The Deac2 NewMenuTest layout is a future UX reference, not a copied UI.

For per-item status, code/test locations and remaining work, see the [adoption ledger](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/COMMUNITY-ADOPTION.md). External runtimes/toolkits have separate notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Attribution does **not** imply endorsement, sponsorship or responsibility for this fork. Future direct source imports must record exact upstream commits, preserve copyright/license headers, identify modifications and add any required license text before distribution.
