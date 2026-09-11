# WinForge Plan 7 — Aplicar no Diagnóstico, correções visíveis, permissões do disco C:, descrições Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Diagnóstico checklist can be applied/undone in place; the Config-tab "Correções" run off the UI thread with a live output window; a new "Permissões do disco C:" repair (verify / restore defaults / undo) with ACL backup; every tweak/feature/app description rewritten to say what it does, its effect and its cost, with SelfTest locks against generic or repeated text. Version 1.6.0.

**Architecture:** Reuse the command machinery (`wf-commands.ps1`): add streaming (`Invoke-WinForgeNativeCommand -StreamTo`) and a follow-mode output window (`Show-WinForgeOutputWindow -FollowPath`). Base fix buttons are re-routed by key in `Invoke-WPFButton` (same guard pattern as `WPFWFRep*`) to `Invoke-WinForgeRepairCommand`, whose table gains five entries whose helpers stream native commands or run the base function inside the runspace with `*>&1` to the stream file. Diagnóstico gets two buttons that call the base apply/undo. The ACL repair lives in `wf-repair.ps1` (report parser, backup via `icacls /save` into a protected folder, ordered plan with `-DryRun`). Descriptions are data: `config/wf-i18n-configs.ps1` (base entries) and the WinForge config files.

**Tech Stack:** Windows PowerShell 5.1, WPF, `System.Diagnostics.Process` with redirected streams, `icacls`/`secedit`/`takeown`/`chkdsk`/`sfc`/`DISM`/`netsh`/`w32tm`, existing build + SelfTest.

**Spec:** `docs/superpowers/specs/2026-09-11-correcoes-visiveis-design.md`.

## Global Constraints

- Never edit `src/Engine/base/winutil-26.08.19.ps1` or `dist/`; edits only in `src/Engine/{winforge,config,xaml}` + anchored injections in `src/Engine/build.ps1`.
- UTF-8 BOM + CRLF; pt-BR; functions `*-WinForge*`; brand, language, colour and description locks green; `docs/auditoria.md` regenerated and committed when Content/Description change (row count 142/30/2 unchanged).
- SelfTest 0 errors plain and with `WINFORGE_SIMULATE_SERVER=iis,ad`; locks 83/84/22/137 unchanged; Config lock 54 → **57** (3 ACL buttons) in Task 3.
- SelfTest never runs a repair (`$sync.SelfTest` + `-DryRun` + `Assert-WinForgeNotSelfTest`); ACL commands never run in SelfTest (parsers fed synthetic `icacls` output only).
- Runspace rule: UI callbacks are file-scope scriptblocks; runspace bodies get data via `-ArgumentList`; never command text from data; system exes via `Get-WinForgeSystemExe`; SIDs instead of localized account names.
- Trust paths via `[Environment]::GetFolderPath`; ACL backups under the protected chain (`Confirm-WinForgeSnapshotRoot -Root` semantics) at `%ProgramData%\WinForge\acl-backup`.
- Version → `1.6.0` in the last task. Conventional Commits + trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Branch `feat/plan7-correcoes`; finish with push + PR.

## File map

| Path | Responsibility |
|---|---|
| `src/Engine/winforge/wf-commands.ps1` | `Invoke-WinForgeNativeCommand -StreamTo`, `Show-WinForgeOutputWindow -FollowPath`, `Start-WinForgeStreamedCommand` (runspace + live window + status timer) |
| `src/Engine/winforge/wf-repair.ps1` | repair table entries `NetworkReset`, `NtpPool`, `SystemRepair`, `WindowsUpdateReset`, `WingetReinstall`, `AclVerify`, `AclRestore`, `AclUndo`; helpers `Get-WinForgeAclReport`, `ConvertFrom-WinForgeIcacls`, `Get-WinForgeAclRestorePlan`, `Invoke-WinForgeAclRestore`, `Invoke-WinForgeAclUndo` |
| `src/Engine/config/wf-repair-config.ps1` | 3 new buttons (`WPFWFRepAclVerify`, `WPFWFRepAclRestore`, `WPFWFRepAclUndo`) |
| `src/Engine/xaml/wf-xaml-diag-tab.xml`, `src/Engine/winforge/wf-diag.ps1` | buttons `WPFDiagApplySelected`, `WPFDiagUndoSelected` |
| `src/Engine/config/wf-i18n-configs.ps1`, `wb-config.ps1`, `wf-server-config.ps1`, `wf-repair-config.ps1` | rewritten descriptions |
| `src/Engine/build.ps1` | button routing for base fix keys, SelfTest |

---

### Task 1: Diagnóstico "Aplicar marcados" / "Desfazer marcados"

**Files:** `src/Engine/xaml/wf-xaml-diag-tab.xml`, `src/Engine/winforge/wf-diag.ps1`, `src/Engine/build.ps1`.

- [ ] **Step 1: Failing SelfTest**: XAML has `WPFDiagApplySelected` (Content `Aplicar marcados`) and `WPFDiagUndoSelected` (`Desfazer marcados`) in the Diagnóstico toolbar; the generated `button switch` has cases `"WPFDiagApplySelected" {Invoke-WPFtweaksbutton}` and `"WPFDiagUndoSelected" {Invoke-WPFundoall}` (assert on the generated text); after "Marcar todos" headless, `$sync.selectedTweaks` contains every mirrored key (proves the base apply path will see them); both buttons are disabled while `$sync.ProcessRunning = $true` and re-enabled after (via the existing `Set-WinForgeDiagProgress`/progress hook or a small `Update-WinForgeDiagActionButtons` called from the mirror update).
- [ ] **Step 2: Implement** (buttons next to the counter; tooltip: "Aplica os itens marcados, igual ao botão da aba Ajustes; pode pedir ponto de restauração").
- [ ] **Step 3: SelfTest green, mutation-prove, build, commit** `feat(diag): apply and undo the marked recommendations from the Diagnostico tab`.

---

### Task 2: Correções with live output (Config tab)

**Files:** `src/Engine/winforge/wf-commands.ps1`, `wf-repair.ps1`, `src/Engine/build.ps1`.

**Interfaces (produces):**
- `Invoke-WinForgeNativeCommand -FilePath -Arguments -StreamTo <path> [-Utf8]` → same return `@{Text; ExitCode}` but writes each stdout/stderr line to `<path>` as it arrives (`Process` with `RedirectStandardOutput/Error`, `OutputDataReceived` events or synchronous `ReadLine` loop on stdout with stderr merged via `2>&1` argument? — use `ProcessStartInfo` with both redirected and read stdout line by line in the runspace; stderr via async event appended with `[erro]` prefix; OEM decoding as today).
- `Show-WinForgeOutputWindow -Title -Path -FollowPath [-NoShow]` → opens immediately with whatever the file has, `DispatcherTimer` 500 ms appends new bytes (track offset; UTF-8 with BOM file), header line "Em andamento…" replaced by "Concluído em mm:ss (código N)" when `$sync.WinForgeStreamDone[<path>]` is set; "Fechar" enabled always; `-NoShow` returns the window and the timer object so SelfTest can tick it manually (`$timer.Tag.Tick.Invoke()` or expose `Invoke-WinForgeFollowTick -Window`).
- `Start-WinForgeStreamedCommand -Name -Spec` → sets `$sync.CommandRunning`, creates the stream file under the logs folder (`repair-<Name>-<ts>.txt`), opens the follow window on the UI thread, runs the spec's `Steps` (array of `@{ FilePath; Arguments }` or `@{ Function = '<name>' }` executed inside the runspace with `*>&1 | Out-File -Append -Encoding utf8`) sequentially in a runspace (body created on the UI thread, `-ArgumentList`), status bar "Em andamento: <título> (mm:ss)" updated by the same timer, marks done, releases the flag in `finally`.
- Repair table entries (all `Kind repair`, `Stream = $true`): `NetworkReset` (steps `netsh winsock reset`, `netsh int ip reset`; text ends with "Reinicie o computador."), `NtpPool` (`net start w32time` equivalent via `Start-Service` in a `Function` step, `w32tm /config /update /manualpeerlist:pool.ntp.org,0x8 /syncfromflags:MANUAL`, `Restart-Service w32time`, `w32tm /resync`), `SystemRepair` (`chkdsk <sys> /scan /perf`, `sfc /scannow`, `DISM /Online /Cleanup-Image /RestoreHealth`), `WindowsUpdateReset` (`Function = 'Invoke-WPFFixesUpdate'`), `WingetReinstall` (`Function = 'Invoke-WPFFixesWinget'`). Exes via `Get-WinForgeSystemExe` (`netsh.exe`, `w32tm.exe`, `chkdsk.exe`, `sfc.exe`, `Dism.exe`).
- `build.ps1`: `Invoke-WPFButton` lookup guard extended so `WPFFixesNetwork`, `WPFFixesNTPPool`, `WPFPanelDISM`, `WPFFixesUpdate`, `WPFFixesWinget` skip the base `function` path; `button switch` cases route them to `Invoke-WinForgeRepairCommand -Name <X>`.

- [ ] **Step 1: Failing SelfTest**: `-StreamTo` with `cmd.exe /c echo a & echo b` writes two lines to the file and returns them in `Text`; follow window `-NoShow` appended text after a manual tick when the file grows; five specs valid (`Kind repair`, `Stream`, steps with absolute exes), `-DryRun` lists the steps without running, all refused in SelfTest; generated engine routes the five base keys (text assertions on lookup guard + switch); `Invoke-WPFSystemRepair` is no longer reachable from the button (assert the switch case text).
- [ ] **Step 2: Implement.** Keep `Invoke-WinForgeRepairCommand`'s confirmation for these (Description from the config — base features' Descriptions come from the dictionary; add ones if missing).
- [ ] **Step 3: Verify live** — run the engine non-elevated (`-NoElevation -NoRestorePoint`) and click "Servidor NTP - Ativar" via UIA Invoke? That changes NTP config — NO. Instead verify with a harmless streamed spec in a scratch run (`SelfTest` covers the mechanism); for the real window, only confirm that clicking "Rede - Redefinir" shows the confirmation box (answer Não via UIA) and that the status/window plumbing exists. Document.
- [ ] **Step 4: SelfTest green, mutation-prove, build, commit** `feat(repair): Config fixes run off the UI thread with a live output window`.

---

### Task 3: Permissões do disco C: (verify / restore defaults / undo)

**Files:** `src/Engine/winforge/wf-repair.ps1`, `src/Engine/config/wf-repair-config.ps1`, `src/Engine/build.ps1`.

**Interfaces (produces):**
- `ConvertFrom-WinForgeIcacls -Text` → rows `@{ Path; Aces = @(@{ Sid|Name; Rights; Flags }) }` from `icacls <path>` output (both `NT AUTHORITY\SYSTEM` and localized names; the report compares by SID using `icacls <path> /save` or `Get-Acl` with `IdentityReference.Translate([SecurityIdentifier])`) — use `Get-Acl` for the report (owner + `Access` with SIDs), `icacls` only for backup/restore.
- `Get-WinForgeAclReport [-Paths]` → text + `@{ Differences = <int>; Items = @(...) }`: for `C:\`, `Windows`, `Program Files`, `Program Files (x86)`, `ProgramData`, `Users`, `Users\Public`, current profile — expected owner/ACEs table by SID (`S-1-5-18`, `S-1-5-32-544`, `S-1-5-32-545`, `S-1-5-11`, `S-1-5-80-956008885-...` TrustedInstaller for `Windows`/`Program Files`); flags each missing mandatory ACE or wrong owner; verdict.
- `Get-WinForgeAclRestorePlan -Profile <path> -UserSid <sid>` → ordered steps (chkdsk scan → backup saves → root icacls (SIDs) → secedit → profile icacls → profile reset) as `@{ Title; FilePath; Arguments }`; `-DryRun` on `Invoke-WinForgeAclRestore` prints the plan and returns.
- `Invoke-WinForgeAclRestore` (`repair`, `Stream`): backup with `icacls <p> /save "<root>\acl-<name>-<ts>.txt" /C` (root + each top-level folder non-recursive; profile `/T`) into `%ProgramData%\WinForge\acl-backup` (protected chain via the snapshot-root helpers with `-Root` = that folder path resolved from `GetFolderPath('CommonApplicationData')`); refuse when the backup folder is untrusted; run the plan streaming; stop after chkdsk when its exit code ≠ 0 with the message to schedule `/f`; `takeown /F C:\ /A` only if the root icacls fails with access denied (exit 5) then retry once; final text with reboot advice.
- `Invoke-WinForgeAclUndo` (`repair`): newest backup set → `icacls <folder> /restore <file>` per saved file (validate the file is inside the trusted folder, owner Administrators; refuse otherwise).
- Buttons: `WPFWFRepAclVerify` "Permissões do disco C: - Verificar", `WPFWFRepAclRestore` "Permissões do disco C: - Restaurar padrões", `WPFWFRepAclUndo` "Permissões do disco C: - Desfazer (restaurar backup)" in the repair group; Config lock 57.

- [ ] **Step 1: Failing SelfTest**: report parser on synthetic `Get-Acl`-like objects (build with `New-Object System.Security.AccessControl.DirectorySecurity` + rules) flags a missing SYSTEM ACE and a wrong owner; on this machine `Get-WinForgeAclReport` runs (read-only) and returns text + a numeric verdict (any value); restore plan `-DryRun` lists the 6 phases in order with absolute exes and SIDs (no localized names), never runs; `Invoke-WinForgeAclRestore`/`Undo` throw in SelfTest without `-DryRun`; backup folder trust check refuses a temp folder with default-root semantics; undo refuses a backup file outside the trusted folder; Config lock 57; XAML buttons exist.
- [ ] **Step 2: Implement.** Confirmation text spells out: duration (minutes), what changes, reboot needed, backup location, and that `Windows`/`Program Files` are handled by `secedit`, not by icacls on the whole disk.
- [ ] **Step 3: SelfTest green, mutation-prove, build, commit** `feat(repair): verify, restore and undo default permissions of the system drive`.

---

### Task 4: Descriptions rewrite + locks

**Files:** `src/Engine/config/wf-i18n-configs.ps1` (all base entries), `src/Engine/config/wb-config.ps1`, `wf-server-config.ps1`, `wf-repair-config.ps1`, `src/Engine/winforge/wb-functions.ps1` (game entries' generated Description), `src/Engine/build.ps1` (locks), `tools/List-Descriptions.ps1`.

- [ ] **Step 1: Locks first (failing)**: for every entry with a Description in `$sync.configs.tweaks`/`feature`/`applications` (after merge/translation): (a) no repeated sentence (split on `(?<=[.!?])\s+`, normalize case/spaces, no duplicates), (b) length ≥ 40, (c) Description ≠ Content and does not start with the Content, (d) at most one `Origem:`, (e) no `CUIDADO:` outside the audit prefix path; report offenders with keys. Expect many failures now.
- [ ] **Step 2: Rewrite.** `tools/List-Descriptions.ps1` prints key, Content, current Description for review. For each entry research the actual effect (Microsoft Learn / vendor docs; the base's registry/service/script fields tell exactly what changes) and write 1–3 sentences: what it does (mechanism in plain words), practical effect, when to use / cost or caveat. Direct, pt-BR, no marketing, no "melhora o desempenho" without saying how. Keep proper nouns; keep the `Origem: '<script>.bat/.reg'` provenance once at the end for Windows Boost entries. Apps: one sentence on what the app is + one on why one would install it. Server/IIS/repair entries: keep the prerequisite/backup sentences but remove repetition.
- [ ] **Step 3: SelfTest green (locks pass), audit doc regenerated + committed, build, commit** `docs(config): rewrite every description with mechanism, effect and cost`.

---

### Task 5: Docs, 1.6.0

`README.md` (Diagnóstico: aplicar/desfazer; Configurações: correções com janela ao vivo; novo grupo Permissões do disco C: com o passo a passo e o backup), `docs/changelog.md` `## 1.6.0 (2026-09-11)`, `version.props` 1.6.0; `build.cmd`, `dotnet test` 22/22, `git diff --exit-code -- docs/auditoria.md` (or committed regeneration). Commit `docs: correções visíveis e permissões do disco; release 1.6.0`.

## Self-review

- Spec §2 → Task 1; §3 → Task 2; §4 → Task 3; §5 → Task 4; §6 tests distributed. No placeholders. Names consistent: `Start-WinForgeStreamedCommand`, `-StreamTo`, `-FollowPath`, `Get-WinForgeAclReport`, `Get-WinForgeAclRestorePlan`, `Invoke-WinForgeAclRestore`, `Invoke-WinForgeAclUndo`, buttons `WPFDiagApplySelected/UndoSelected`, `WPFWFRepAcl*`.
