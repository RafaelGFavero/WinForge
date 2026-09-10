# WinForge Plan 5 — Reparo de componentes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Config tab gains a **"WinForge - Reparo de componentes"** group of buttons that verify and repair essential Windows components (WMI repository, Store/App Installer, .NET 3.5/4.8, VC++ runtimes, DirectX runtime, PowerShell 7, disk check, SMART, memory diagnostic, TPM/Secure Boot/BitLocker status), each running off the UI thread with its output in the existing output window and a log file, and each state-changing action confirmed by the user first. Existing base buttons (sfc+DISM, Windows Update reset, network reset, WinGet reinstall) stay as they are.

**Architecture:** The output-window command machinery built for the Servidor tab (`Get-WinForgeServerCommand` table → synchronous core → runspace dispatch → `Show-WinForgeOutputWindow`) is generalized into `src/Engine/winforge/wf-commands.ps1` (spec-driven core + dispatcher + window), and the Servidor functions become thin wrappers so nothing changes for them. `src/Engine/winforge/wf-repair.ps1` holds the repair table (`Get-WinForgeRepairCommand -Name`) with a `Kind` (`read` runs at once; `repair`/`install` ask for confirmation with the description) and the helpers that need real code (WMI verify→salvage, .NET checks, winget path resolution under elevation, VC++ loop). Entries are Config-tab features (`$sync.configs.wfrepair`, merged like `wbfeatures`), Type Button without `function`, dispatched by explicit `button switch` cases (`WPFWFRep*` excluded from the base lookup exactly like `WPFWFSrv*`). SelfTest validates every table row and dry-runs every command (returns the command text, executes nothing), runs the read-only commands for real, and never executes a repair/install.

**Tech Stack:** Windows PowerShell 5.1, `winmgmt`, `Add-AppxPackage`, DISM/`Enable-WindowsOptionalFeature`, `winget` (resolved via `Microsoft.DesktopAppInstaller` package path), `chkdsk`/`fsutil`, `Get-PhysicalDisk`/`Get-StorageReliabilityCounter`, `bcdedit /bootsequence {memdiag}`, `Get-Tpm`/`Confirm-SecureBootUEFI`/`Get-BitLockerVolume`, WPF output window; existing build pipeline + SelfTest.

**Spec:** `docs/superpowers/specs/2026-09-07-winforge-design.md` §5.7.

## Global Constraints

- Never edit `src/Engine/base/winutil-26.08.19.ps1` or `dist/`. All edits via `src/Engine/{winforge,config,xaml}` and anchored injections in `src/Engine/build.ps1`.
- New functions `*-WinForge*`; new `.ps1` UTF-8 with BOM + CRLF; pt-BR user text; brand/mojibake/old-brand 0; `docs/auditoria.md` byte-identical (buttons are not audited).
- SelfTest 0 errors plain and with `WINFORGE_SIMULATE_SERVER=iis,ad`. Locks: Tweaks 83, Jogos 84, Servidor 22 unchanged; **Config 42 → 54** (12 new buttons). Existing Servidor SelfTest assertions must keep passing unchanged after the refactor.
- SelfTest never runs a `repair`/`install` command and never changes this machine (dry-run only); read commands may run.
- Runspace rule: UI callbacks are scriptblocks created on the main runspace and invoked via `Invoke-WPFUIThread`; one command at a time (shared flag `$sync.CommandRunning`, reset in `finally` and in the dispatch `catch`).
- No command text is built from data (arguments as arrays); downloads only from `download.microsoft.com`/`aka.ms` official URLs, saved under `%TEMP%\WinForge`, never executed silently without the user's confirmation click.
- Version → `1.4.0` in the last task. Conventional Commits + trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Branch `feat/plan5-reparo` from `main`; finish with push + PR.

## File map

| Path | Responsibility |
|---|---|
| `src/Engine/winforge/wf-commands.ps1` | generic: `Invoke-WinForgeCommandCore -Spec -Component -Prefix [-DryRun]`, `Invoke-WinForgeCommandButton -Spec -Component -Prefix -Name`, `Show-WinForgeOutputWindow`, `Invoke-WinForgeNativeCommand`, `Test-WinForgeCommandRequirement`, `$sync.WinForgeCommandOutputCallback` |
| `src/Engine/winforge/wf-server.ps1` | keeps `Get-WinForgeServerCommand`; `Invoke-WinForgeServerCommandCore`/`Invoke-WinForgeServerCommand` become wrappers |
| `src/Engine/winforge/wf-repair.ps1` | `Get-WinForgeRepairCommand`, `Invoke-WinForgeRepairCommand`, helpers (`Get-WinForgeWingetPath`, `Invoke-WinForgeWmiRepair`, `Get-WinForgeDotNetStatus`, `Install-WinForgeVcRedist`, `Get-WinForgeSecurityStatus`, `Get-WinForgeSmartReport`) |
| `src/Engine/config/wf-repair-config.ps1` | `$sync.configs.wfrepair` JSON (12 buttons) |
| `src/Engine/build.ps1` | inserts, `button lookup` guard for `WPFWFRep*` on the feature branch, `button switch` cases, SelfTest |

---

### Task 1: Generalize the command machinery (`wf-commands.ps1`), Servidor becomes a client of it

**Files:** Create `src/Engine/winforge/wf-commands.ps1`; Modify `src/Engine/winforge/wf-server.ps1`, `src/Engine/build.ps1` (insert `wf-commands.ps1` BEFORE `wf-server.ps1`; SelfTest).

**Interfaces (produces):**
- Spec hashtable (same shape as today's server rows plus two optional keys): `@{ Title; Command (text, static literal); Requires ($null|exe|cmdlet); Native (bool); Kind ('read'|'repair'|'install', default 'read'); Confirm (text shown before a non-read command, default = Title) }`.
- `Invoke-WinForgeCommandCore -Spec <hashtable> -Name <string> -Component <string> -Prefix <string> [-DryRun]` → `@{ Text; Path; ExitCode }`; with `-DryRun` returns `Text = "[simulação] " + Command`, writes no file, runs nothing.
- `Invoke-WinForgeCommandButton -Spec -Name -Component -Prefix` → the runspace dispatch + output window (flag `$sync.CommandRunning` replaces `$sync.ServerCommandRunning`; keep the old name as an alias property set/reset together so existing SelfTest assertions still hold, or update those assertions).
- `Invoke-WinForgeServerCommandCore -Name` = `Invoke-WinForgeCommandCore -Spec (Get-WinForgeServerCommand -Name $Name) -Name $Name -Component Server -Prefix server`; `Invoke-WinForgeServerCommand -Name` = `Invoke-WinForgeCommandButton ...`. Output file names unchanged (`server-<Name>-<ts>.txt`).
- The UI callback becomes `$sync.WinForgeCommandOutputCallback` (created at file scope in `wf-commands.ps1`); `$sync.WinForgeServerOutputCallback` removed (update SelfTest references).

- [ ] **Step 1: Move code.** Cut `Invoke-WinForgeNativeCommand`, `Test-WinForgeServerRequirement` (rename `Test-WinForgeCommandRequirement`), `Invoke-WinForgeServerCommandCore` body, `Show-WinForgeOutputWindow`, the callback and `Invoke-WinForgeServerCommand` body into `wf-commands.ps1`, parameterized by `-Spec/-Name/-Component/-Prefix`. Add `-DryRun`. Keep the OEM code-page mutex, `Native` exit-code rule, ErrorRecord mapping, requirement check inside the runspace body.
- [ ] **Step 2: Wrappers** in `wf-server.ps1` (3-line functions). `build.ps1`: `$commandsBlock = Read-Lf ... "winforge\wf-commands.ps1"`, insert before `wf-server.ps1`'s insert (both `Insert-Before "#region ===== WinForge - logo ====="` — insert the server block first, then the commands block, so commands ends up above server).
- [ ] **Step 3: SelfTest**: existing Servidor command assertions unchanged and green; add: `Invoke-WinForgeCommandCore -Spec (Get-WinForgeServerCommand -Name TcpShow) -Name TcpShow -Component Server -Prefix server -DryRun` returns `Text -like '[simulação]*'`, `Path -eq $null`, and no new file under the logs dir (count before/after). Mutation-prove.
- [ ] **Step 4: Build, SelfTest ×2, commit** `refactor(engine): generic command core and output window shared by Servidor and repair`.

---

### Task 2: Repair table, Config entries, wiring, dry-run SelfTest

**Files:** Create `src/Engine/winforge/wf-repair.ps1`, `src/Engine/config/wf-repair-config.ps1`; Modify `src/Engine/winforge/wb-functions.ps1` (`Initialize-WinUtilBoostConfigs`: merge `$sync.configs.wfrepair` into `$sync.configs.feature` after `wbfeatures`), `src/Engine/build.ps1`.

**Interfaces (produces):** `Get-WinForgeRepairCommand -Name` (throws on unknown name) for these names; `Invoke-WinForgeRepairCommand -Name [-NoUI]`: in this task it dispatches ONLY `Kind read` and refuses other kinds with a MessageBox "Disponível na próxima etapa" (with `-NoUI` it returns `@{ Dispatched = $false; Reason = '...' }` instead of showing anything); Task 3 replaces the refusal with the confirmation flow.

| Name | Kind | Title | Command (literal text) | Requires / Native |
|---|---|---|---|---|
| `SecurityStatus` | read | Estado de TPM, Secure Boot e BitLocker | `Get-WinForgeSecurityStatus` | `$null` / `$false` |
| `SmartReport` | read | Saúde dos discos (SMART) | `Get-WinForgeSmartReport` | `Get-PhysicalDisk` / `$false` |
| `DotNetStatus` | read | Estado do .NET Framework 3.5 e 4.8 | `Get-WinForgeDotNetStatus` | `$null` / `$false` |
| `WmiRepair` | repair | Repositório WMI: verificar e recuperar | `Invoke-WinForgeWmiRepair` | `winmgmt.exe` / `$false` (the helper calls winmgmt itself via `Invoke-WinForgeNativeCommand -FilePath 'winmgmt.exe' -Arguments @('/verifyrepository')`, then `/salvagerepository` only when the output is not consistent, then verifies again) |
| `StoreReregister` | repair | Microsoft Store e App Installer: registrar de novo | `Invoke-WinForgeStoreReregister` | `Get-AppxPackage` / `$false` (re-registers `Microsoft.WindowsStore`, `Microsoft.DesktopAppInstaller`, `Microsoft.StorePurchaseApp` for all users via `Add-AppxPackage -DisableDevelopmentMode -Register "<InstallLocation>\AppXManifest.xml"`, reports each) |
| `DotNet35Enable` | install | .NET Framework 3.5: habilitar (DISM) | `Enable-WinForgeDotNet35` | `$null` / `$false` (`Get-WindowsOptionalFeature -Online -FeatureName NetFx3`; if not Enabled → `Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart`; text says it needs internet/Windows Update) |
| `VcRedist` | install | Visual C++ 2005–2022 (x86/x64) via winget | `Install-WinForgeVcRedist` | `winget` (resolved by `Get-WinForgeWingetPath`) / `$false` |
| `DirectX` | install | DirectX (instalador web da Microsoft) | `Install-WinForgeDirectX` | `$null` / `$false` (downloads `https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe` to `%TEMP%\WinForge\dxwebsetup.exe` with `Invoke-WebRequest` (30 s timeout), then `Start-Process` it — interactive installer, user drives it; text explains) |
| `PowerShell7` | install | PowerShell 7 via winget | `Install-WinForgePowerShell7` | winget / `$false` (`winget install --id Microsoft.PowerShell -e --silent --accept-package-agreements --accept-source-agreements`) |
| `ChkdskScan` | read | Verificar disco do sistema agora (chkdsk /scan) | `chkdsk $env:SystemDrive /scan` → use `Invoke-WinForgeNativeCommand -FilePath chkdsk.exe -Arguments @($env:SystemDrive, '/scan')` inside a helper `Invoke-WinForgeChkdskScan` | `chkdsk.exe` / `$false` (helper handles native) |
| `ChkdskSchedule` | repair | Agendar chkdsk /f na próxima reinicialização | `Invoke-WinForgeChkdskSchedule` (`fsutil dirty set <SystemDrive>`; reports `fsutil dirty query`) | `fsutil.exe` / `$false` |
| `MemoryDiag` | repair | Diagnóstico de memória na próxima reinicialização | `Invoke-WinForgeMemoryDiagSchedule` (`bcdedit /bootsequence {memdiag}`; shows resulting `bcdedit /enum {bootmgr}` bootsequence line) | `bcdedit.exe` / `$false` |

That is 12 names; the Config lock becomes **54** (42 + 12). Buttons in `wf-repair-config.ps1` (`category "WinForge - Reparo de componentes"`, `panel "1"`, Type Button, `ButtonWidth "350"`, key `WPFWFRep<Name>`, Content = Title, Description = what it does + what changes + prerequisite). Also `Get-WinForgeWingetPath`: `Get-Command winget.exe` first; else `(Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller | Sort-Object Version -Descending | Select-Object -First 1).InstallLocation\winget.exe`; `$null` when absent (commands then report "winget não encontrado: use 'WinGet - Reinstall'").

- [ ] **Step 1: Failing SelfTest**: for each of the 12 names: `Get-WinForgeRepairCommand` returns Title/Command/Kind valid, `[scriptblock]::Create($Command)` parses; `Invoke-WinForgeCommandCore -Spec ... -DryRun` returns `[simulação]` text and no file; `Invoke-WinForgeRepairCommand` for a non-read name (headless: `-NoUI` switch returning the decision instead of showing a MessageBox) does not run anything; `Get-WinForgeSecurityStatus`, `Get-WinForgeSmartReport`, `Get-WinForgeDotNetStatus` run for real and return non-empty text; XAML: all 12 `WPFWFRep*` buttons exist after mounting the Config tab; Config lock 54; the `button lookup` guard excludes `WPFWFRep*` on the feature branch.
- [ ] **Step 2: Implement** table, helpers (read helpers return text; write helpers implemented but only reachable via Kind repair/install), config JSON, merge, `build.ps1`: `$repairConfig`/`$repairBlock` reads and inserts (config after `insert audit data`; block before logo after server), `button lookup` feature branch: `if ($sync.configs.feature.$Button -and $Button -notlike "WPFWFRep*")`, `button switch` cases `"WPFWFRepSecurityStatus" { Invoke-WinForgeRepairCommand -Name SecurityStatus }` … (12).
- [ ] **Step 3: SelfTest passes** (both modes), mutation-proof, commit `feat(repair): component repair buttons in Config with read-only actions`.

---

### Task 3: Confirmation for repair/install actions, winget/DirectX helpers hardened

**Files:** Modify `src/Engine/winforge/wf-repair.ps1`, `src/Engine/winforge/wf-commands.ps1`, `src/Engine/build.ps1`.

- [ ] **Step 1: Failing SelfTest**: `Invoke-WinForgeRepairCommand -Name WmiRepair -NoUI` returns `@{ Dispatched = $false; Reason = 'confirmação' }` (the headless path never dispatches a non-read command); `Get-WinForgeRepairConfirmText -Name WmiRepair` returns text containing the Title and the word `Continuar`; `Get-WinForgeWingetPath` returns `$null` or an existing file; `Install-WinForgeVcRedist -DryRun` returns the 12 package ids in order (`Microsoft.VCRedist.2005.x86`, `.2005.x64`, `.2008.x86`, `.2008.x64`, `.2010.x86`, `.2010.x64`, `.2012.x86`, `.2012.x64`, `.2013.x86`, `.2013.x64`, `.2015+.x86`, `.2015+.x64` — 12 ids) without running winget; `Install-WinForgeDirectX -DryRun` returns the URL and target path without downloading.
- [ ] **Step 2: Implement**: `Invoke-WinForgeRepairCommand`: `Kind read` → dispatch; else `[System.Windows.MessageBox]::Show(<confirm text>, "WinForge", YesNo, Warning)`; No → log + return; Yes → dispatch via `Invoke-WinForgeCommandButton` with `-Component Repair -Prefix repair`. Confirm text: Title + Description + "Continuar?". Install helpers: winget invoked with `Invoke-WinForgeNativeCommand -FilePath <path> -Arguments @(...)` per package, skipping ids already installed (`winget list --id <id> -e` exit code 0 and output contains the id), collecting a per-package line; DirectX download with `[Net.ServicePointManager]::SecurityProtocol = Tls12`, verify `Authenticode` signature is `Valid` and signer subject contains `Microsoft Corporation` before `Start-Process`, otherwise delete and report.
- [ ] **Step 3: SelfTest passes**, commit `feat(repair): confirmation for repair and install actions; winget and DirectX helpers`.

---

### Task 4: Docs, version 1.4.0

**Files:** `README.md` (section "Reparo de componentes" after "Windows Server": list of buttons, what each does, confirmation rule, where output/log files go, winget/internet prerequisites, "nada roda sem clique + confirmação"; Roadmap: remove the component-repair item; if the roadmap becomes empty, replace with "Sugestões e correções: abra uma issue."), `docs/changelog.md` (`## 1.4.0 (<today>)`), `version.props` → `1.4.0`.

- [ ] **Step 1: Write docs, run `build.cmd` (engine → SelfTest ×2 → dotnet build → exe 1.4.0), `dotnet test src/Launcher.Tests` (22/22), `git diff --exit-code -- docs/auditoria.md`.**
- [ ] **Step 2: Commit** `docs: component repair; release 1.4.0`.

---

## Self-review

- **Spec §5.7 coverage:** WMI ✔, Store/AppX re-register ✔, WinGet repair (existing button kept) + App Installer re-register ✔, .NET 3.5 (DISM) + 4.8 check ✔, VC++ 2005–2022 x86/x64 via winget ✔, DirectX web installer ✔, PowerShell 7 ✔, chkdsk /scan now + /f scheduled ✔, SMART report ✔, memory diagnostic schedule ✔, TPM/Secure Boot/BitLocker status ✔, sfc+DISM / WU reset / network reset (existing base buttons) ✔.
- **Placeholders:** none. Task 2's `Invoke-WinForgeRepairCommand` explicitly refuses non-read names until Task 3 (stated behaviour, tested).
- **Type consistency:** `Kind` values `read|repair|install` used in Tasks 2–3; `-DryRun` on core (Task 1) and on install helpers (Task 3); names `WPFWFRep<Name>` match table names; Config lock 54.
