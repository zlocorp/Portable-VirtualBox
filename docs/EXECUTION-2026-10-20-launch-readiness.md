# Integrated launcher readiness UI checkpoint (2026-10-20)

**Scope:** a real user-facing, non-destructive launch readiness action in the compiled RU/EN preview GUI, based on existing portable-profile and Windows read-only preflight implementations. This is NOT an implemented privileged Start/Stop button or a completed large Batch A.

## Changes
- `source/LauncherReadiness.au3` computes distinct states `PROFILE_MISSING`, `PROFILE_UNSAFE`, `APP_MISSING`, `HOST_CONFLICT` and `RUNTIME_DISABLED`. Unknown observations never become launch permission.
- `source/LauncherGui.au3` adds a working **Check launch readiness / Проверить готовность к запуску** button with localized result beneath the private-folder preparation button. No mutation or VM launch is authorized.
- `source/LauncherI18n.au3` adds RU/EN readiness messages with explicit explanation that a clear preflight does not enable runtime.
- `tests/native/test_launcher_readiness.au3` verifies ten native assertions including system VBox conflict refusal and truthful "runtime disabled" outcome.

## Verified CI

Executable checkpoint `14b292c64c5898752f701de5860c96f25c33c9fa`:
- [Native compiled AutoIt tests](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39490947648): all 15 native harnesses passed, including 10 new readiness assertions; no failures.
- [Core Python and Windows x64 compile](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39490947586): both static checks and compilation jobs completed successfully.

The README, larger product plan and current draft PR remain the source of overall roadmap. The compiled preview has a real user-facing readiness interaction, **not a real enabled Start button**. Real signed-driver setup/teardown is still limited to disposable research workflows and cannot be copied into the UI without ownership and security acceptance.

## Remaining large Batch A work

Next integrated change set must include a minimal privileged helper and a genuine AutoIt session that:
1. Detects installed VBox/process/service conflicts, preserves user VMs, and refuses uncertainty.
2. Prepares one signed pinned VBoxSup using exact ownership evidence, opens Oracle Manager under private `VBOX_USER_HOME` and explicitly chosen machine folder.
3. Waits for all session-owned VM activity to stop, unregisters exact owned VBoxSDS, stops and removes the exact driver package/service only when safe, and records non-clean state otherwise.
4. Exercises the above **from the compiled program** on a disposable test host, including failure scenarios, before enabling a normal Windows 11 GUI Start/Stop.

No one should interpret successful research PowerShell scripts as ready-to-ship real-system safety.
