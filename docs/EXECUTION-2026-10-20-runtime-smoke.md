# Runtime smoke experiments: portable VirtualBox 7.2.20 vs official Windows installation

Date: 2026-10-20. Environment: independent disposable GitHub-hosted Windows Server 2022 x64 runners. This is **not** Windows 11 guest/driver/VM execution acceptance.

## Scope and guardrails

From original `vboxme/master` modernization branch. Tests never use the user's PC. No actual guest VM was started, and the modernized AutoIt preview launcher remains deliberately disabled for runtime operations.

Three independent workflows now exist:

- [Prepared app64 CLI smoke](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39399187350): read-only CLI commands against an isolated Unicode `VBOX_USER_HOME`, from a freshly prepared Oracle 7.2.20 file tree. The workflow deliberately fails when it detects auto-registration of a Windows service.
- [Official install reference](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39399299608): a **separate** disposable runner installs the pinned, hash-verified official MSI with only `ADDLOCAL=VBoxApplication`, `/qn /norestart REBOOT=ReallySuppress`, an explicit wait limit and an MSI log. No USB/network optional features are intentionally selected. It then executes the same CLI probes from the installation directory.
- [Portable VM configuration fixture](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39400449110): another fresh uninstalled runner sets a portable machine folder, creates/registers one VM configuration and lists it. No disk images, guest OS or VM execution are involved.

All three workflows pin Oracle **VirtualBox 7.2.20 r175154**, Windows wrapper SHA-256 `a81777d2b36380ce042a29e9c554cf032eb46a793f62e3cc82e7411e535c2c26`. The existing preparation chain validates the Oracle Authenticode signature and reconstructs 185 application files / 247,738,522 bytes from MSI/CAB without running an installer. CI artifacts retain reports and stdout/stderr, **not** Oracle executables, MSI/CAB, VM data, or drivers.

## Actual observations

| Observation | Portable from app64, no install | Official VBoxApplication-only install |
| --- | --- | --- |
| `VBoxManage --version` | Exit 0, `7.2.20r175154` | Exit 0, same version |
| `VBoxManage list vms` | Exit 0, empty list | Exit 0, empty list |
| `VBoxManage list systemproperties` | Exit 0 | Exit 0 |
| VBoxSDS service | **Created automatically by Oracle CLI** | Created by MSI |
| VBoxSup driver service | **Absent** | **Present** |
| VBoxSDS service image path | The prepared `app64\VBoxSDS.exe` under a temporary, Unicode path | `C:\Program Files\Oracle\VirtualBox\VBoxSDS.exe` |
| VBoxSDS service settings | Start=3 (demand), Type=16, LocalSystem | Same |
| VBoxSup settings | Not present | Start=1, Type=1, ImagePath `\SystemRoot\system32\DRIVERS\VBoxSup.sys` |
| Processes after CLI | VBoxSDS and VBoxSVC observed | VBoxSDS and VBoxSVC observed |

**Important:** portable CLI execution had a system side effect. `VBoxSDS` was newly registered with a persistent service image path under the removable/temporary application directory. A drive-letter change or disconnection may leave a broken system registration. It is not sufficient to treat `VBoxManage list vms` as completely read-only. The initial smoke workflow correctly failed its service-registration guard, despite all three CLI commands exiting with code zero.

On a disposable *administrator* runner this auto-registration succeeded. The same behavior under an ordinary standard user, with an existing system VirtualBox installation, or with a mismatched pre-existing VBoxSDS has **not** been established. Do not generalize this result beyond the host tested.

The official MSI install returned **exit 0 in 6.9 seconds without reboot**; its CLI probe also passed three commands. It installed the core VBoxSup driver registration and VBoxSDS service. These observations **do not prove** that a guest VM can start, that the kernel driver loaded successfully, or that installation/cleanup is portable.

## Portable configuration fixture

The uninstalled app64 run additionally passed all **four** steps with exit zero:

1. `VBoxManage setproperty machinefolder <private portable folder>`
2. `VBoxManage list systemproperties` and verify the new path, including spaces and Cyrillic
3. `VBoxManage createvm --name portable_probe_fixture --platform-architecture x86 --register`
4. `VBoxManage list vms` and find the newly registered fixture

Checks passed: `VirtualBox.xml` exists under isolated `VBOX_USER_HOME`; the new VM folder is the private portable directory; exactly one `*.vbox` VM definition exists there; list contains the fixture UUID. The test deliberately does **not** call `startvm` or `unregistervm --delete`.

The first attempt failed because the test script tried to assign the read-only PowerShell `$HOME`; that was fixed. The next attempt set the machinefolder correctly but supplied invalid `createvm` arguments (exit 2); after switching to the documented `--name VALUE --platform-architecture x86` form the entire fixture passed. Failed CI attempts are preserved for audit.

The initial `VBoxManage list systemproperties` without a `setproperty` still reported the machine folder under `C:\Users\runneradmin\VirtualBox VMs`, even with `VBOX_USER_HOME` set. **Both profile path and machine folder must be explicitly handled** by a proper portable launcher.

## Verified CI gates for the development branch

At code/test checkpoint `ca4afd6c4e224c35a197f034ab1ed5615523a9d8`:

- [Core CI](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39400458249): Linux Python **68 tests, 5 Windows-specific skips, zero failures**, and x64 AutoIt compile/diagnostics pass.
- [Oracle preparation](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39400458261): Windows Python **68 tests, 1 symlink privilege skip, zero failures**, plus real 185-file preparation pass.
- [Native AutoIt regressions](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39400458208): all nine native harnesses pass with zero failures (prior coordinator and observation coverage).
- [Portable profile fixture](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39400449110): four commands and portable file assertions pass.
- [Official-install reference](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39399299608): official MSI and CLI checks pass.
- [First portable CLI](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39399187350): commands succeed; workflow intentionally red for VBoxSDS service registration side effect.

The full Python suite currently contains 68 distinct discovered tests; counts from Windows/Linux are not additive. The green CI jobs certify preparation and diagnostic behavior, not VM execution or safe service/driver cleanup.

## Next implementation decisions

1. Do not put code that silently launches VBoxManage into the production entrypoint until a safe VBoxSDS registration/cleanup strategy is specified and verified against pre-existing system installations and concurrent clients.
2. Define how the signed VBoxSup Windows driver is installed and removed *only when created by this run*. Test in disposable Windows before any user's machine. Avoid copying arbitrary DLL files into Windows system directories or terminating processes by name.
3. Implement a portable configuration setup that sets `VBOX_USER_HOME`, configures the default machine folder and preserves user VM registries/VM data. Do not rewrite user VM XML blindly; test drive-letter changes and backup/restore separately.
4. Only after the previous gates, perform VM launch/stop and clean shutdown on a suitable isolated Windows environment. Hosted GitHub runners may lack required nested virtualization, so a successful `VBoxManage` command is not a guarantee of a running guest.
5. Keep `master` and `archive/legacy-zlocorp-2020` unchanged; keep draft PR #7 open and do not publish a usable release.

**Status: successful file preparation, portable CLI and VM configuration management; no proven safe production runtime yet.**
