# WinForge Plan 8 — Estado aplicado, drivers do Windows Update sem duplicata e feedback pós-instalação Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) The panel knows which tweaks are already applied on this system: rows show it, the recommendation checklist counts it, and "Aplicar" skips them instead of re-applying. (2) The Windows Update driver table shows one row per device (newest version), with the version parsed from the title. (3) After installing a driver, its row turns light green with "instalado", the button is disabled, failures show in red. Version 1.7.0.

**Architecture:** Applied state comes from the base's own detector `Invoke-WinUtilCurrentSystem -CheckBox tweaks` (registry/service/toggle comparison per entry), run inside the existing profile job (runspace) and stored as `$sync.AppliedTweaks` (HashSet of keys); `Update-WinForgeAppliedVisuals` (UI thread, idempotent, called from the same hook as the recommendation outlines) marks rows; an injection in the base apply loop (`Invoke-WPFtweaksbutton`) re-detects once at apply time and skips keys already applied, reporting the skips. WU dedupe is a pure function over the search rows; post-install state is a per-row `State` property + `DataTrigger` styles, kept in `$sync.DiagWUState[UpdateId]` for the session.

**Tech Stack:** Windows PowerShell 5.1, WPF DataGrid `RowStyle`/`DataTrigger`, existing profile job/runspace and SelfTest.

**Spec:** this plan is its own spec (bounded feedback round on 1.6.0: "o painel não verifica configurações já aplicadas"; "dois drivers iguais com versões diferentes"; "após instalar, desativar o botão e marcar em verde").

## Global Constraints

- Never edit `src/Engine/base/winutil-26.08.19.ps1` or `dist/`; edits in `src/Engine/{winforge,config,xaml}` + anchored injections in `src/Engine/build.ps1`.
- UTF-8 BOM + CRLF; pt-BR; functions `*-WinForge*`; brand/language/colour/description locks green; `docs/auditoria.md` byte-identical.
- SelfTest 0 errors plain and with `WINFORGE_SIMULATE_SERVER=iis,ad`; locks 83/84/22/57/137 unchanged. SelfTest never applies tweaks or installs drivers (`$sync.SelfTest`).
- Runspace rule: UI callbacks are file-scope scriptblocks; work in runspaces; `-ArgumentList` for data.
- Version → `1.7.0` in the last task. Conventional Commits + trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Branch `feat/plan8-estado`; finish with push + PR.

---

### Task 1: Applied-state detection, visuals, skip on apply

**Files:** `src/Engine/winforge/wf-recoui.ps1` (profile job: after rules, `$sync.AppliedTweaks`), new `src/Engine/winforge/wf-applied.ps1` (`Get-WinForgeAppliedTweaks`, `Update-WinForgeAppliedVisuals`, `Select-WinForgeTweaksToApply`), `src/Engine/winforge/wf-diag.ps1` (checklist rows + counter), `src/Engine/build.ps1` (injection in `Invoke-WPFtweaksbutton`, SelfTest).

**Interfaces (produces):**
- `Get-WinForgeAppliedTweaks` → `[string[]]` keys reported applied by `Invoke-WinUtilCurrentSystem -CheckBox tweaks` (call inside try/catch; on failure returns `@()` and logs WARN). Runs in the profile job runspace (after `Invoke-WinForgeRules`) and stores `$sync.AppliedTweaks = [System.Collections.Generic.HashSet[string]]`; also re-run by the existing "Detectar aplicados" buttons (they keep checking the boxes as today).
- `Update-WinForgeAppliedVisuals` (UI thread; idempotent; called right after `Update-WinForgeRecommendationVisuals` in the same hooks): for each created row whose key ∈ `$sync.AppliedTweaks`: append a muted `TextBlock` " · aplicado" (token `MutedForegroundColor`/`LabelboxForegroundColor`, once — guard with a Tag/name), tooltip prefix `✔ Já aplicado neste sistema. ` (kept together with the recommendation prefix); Toggles are excluded (their switch already shows the state).
- `Select-WinForgeTweaksToApply -Keys <string[]>` → `@{ Apply = [string[]]; Skipped = [string[]] }` using a FRESH `Get-WinForgeAppliedTweaks` (state may have changed since the job); `WPFTweaksRestorePoint` never skipped; entries of `Type Button`/`Combobox`/`Toggle` never skipped.
- Injection (build.ps1) in `Invoke-WPFtweaksbutton` right after `$Tweaks = $sync.selectedTweaks` (inside the runspace body, before the loop): `$wfSel = Select-WinForgeTweaksToApply -Keys @($Tweaks); $Tweaks = @($wfSel.Apply)`; when `$wfSel.Skipped.Count -gt 0`: progress label "Pulado(s) por já estarem aplicados: N" and a final summary line in the progress indicator "Aplicados: A · já estavam aplicados: S"; log each skipped key. Verify the loop's `$totalSteps` is computed from the filtered list (adjust the existing restore-point injection if needed).
- Diagnóstico checklist: rows for applied keys render with the " · aplicado" suffix and are excluded from "Marcar todos" (they can still be checked manually); counter becomes "N de M recomendados marcados · A já aplicados".

- [ ] **Step 1: Failing SelfTest**: `Get-WinForgeAppliedTweaks` returns an array (this machine) and every key exists in `$sync.configs.tweaks`; `Select-WinForgeTweaksToApply -Keys @('WPFTweaksRestorePoint', <one applied key from the set>, <one not applied>)` returns RestorePoint + the not-applied one in `Apply` and the applied one in `Skipped` (use the real set; if the set is empty on this machine, seed `$sync.AppliedTweaks` synthetically for the test and call the selector with `-Applied <set>` param); after mounting Ajustes with a synthetic `$sync.AppliedTweaks` containing 2 keys, `Update-WinForgeAppliedVisuals` marks exactly 2 rows (find the suffix TextBlock) and running it twice does not duplicate; checklist counter text matches `'\d+ de \d+ recomendados marcados · \d+ já aplicados'`; generated engine contains the injection (`Select-WinForgeTweaksToApply` inside `Invoke-WPFtweaksbutton`'s body, before the loop) — text lock.
- [ ] **Step 2: Implement**, mutation-prove, build, commit `feat(tweaks): detect applied settings; skip them on apply; show state in rows and checklist`.

---

### Task 2: Windows Update drivers — one row per device, version from title

**Files:** `src/Engine/winforge/wf-drivers.ps1` (`Search-WinForgeWindowsUpdateDrivers`, new `Select-WinForgeWindowsUpdateLatest`), `src/Engine/winforge/wf-diag.ps1`, `src/Engine/build.ps1`.

- [ ] **Step 1: Failing SelfTest**: version parser accepts `Intel Corporation Display Driver Update (32.0.101.7088)` → `32.0.101.7088` and `Intel Driver Update (2546.9.2.0)` → `2546.9.2.0`; `Select-WinForgeWindowsUpdateLatest -Rows <synthetic 5 rows incl. two "Intel Corporation Display Driver Update" for the same `Driver`+`Provider` with versions 32.0.101.7085/7088>` returns 4 rows, keeps 7088, and marks the dropped one in `Superseded` (list of `@{ UpdateId; Title; ReplacedBy }`); when versions are missing, keep the newest `Date`; rows with different `Driver` never collapse.
- [ ] **Step 2: Implement**: regex `\((\d+(?:\.\d+){1,3})\)` first, then the old end-of-title form; dedupe by `(Driver, Provider)` case-insensitive; grid shows the kept rows; label "Drivers oferecidos pelo Windows Update (N) · M versão(ões) mais antiga(s) oculta(s)"; a tooltip on the label lists the hidden titles. Commit `fix(diag): one Windows Update driver per device, newest version, version parsed from the title`.

---

### Task 3: Post-install feedback in the WU table

**Files:** `src/Engine/xaml/wf-xaml-diag-tab.xml` (WU grid `RowStyle` with `DataTrigger`s on `State`; Instalar button `IsEnabled` bound to `ActionEnabled`), `src/Engine/winforge/wf-diag.ps1` (`Invoke-WinForgeWindowsUpdateAction` sets `State` = `instalando` at dispatch, `instalado` (ResultCode 2/3) or `falhou` (else) in the UI callback; `$sync.DiagWUState[UpdateId]` persists for the session and is applied when the grid is rebuilt; `ActionEnabled` false for `instalando`/`instalado`; `StatusText` column value: `instalado (reinicie)` when reboot required, `instalado`, `falhou (código N)`), `src/Engine/config/wf-theme.ps1` (tokens `RowSuccessBackgroundColor` light green with ≥ 4.5:1 text on both themes, `RowFailureBackgroundColor`), `src/Engine/build.ps1` (SelfTest, contrast pairs).

- [ ] **Step 1: Failing SelfTest**: a synthetic row with `State='instalado'` bound into the grid has the row background = `RowSuccessBackgroundColor` brush (read the generated `DataGridRow` style triggers or check `$row.Background` after `UpdateLayout`), `ActionEnabled=$false`; `State='falhou'` uses the failure brush; `Update-WinForgeDiagnosticsWindowsUpdateGrid` after `$sync.DiagWUState['x']='instalado'` produces that state for the row with `UpdateId 'x'`; contrast gate includes the two new pairs in both themes; `Invoke-WinForgeWindowsUpdateAction -Row <row with State instalado> -NoUI` refuses (`'já instalado'`).
- [ ] **Step 2: Implement** (callback on the main runspace updates the row object — rows are `pscustomobject`; to refresh bindings replace the item in the `ObservableCollection` or use a small class with `INotifyPropertyChanged` via `Add-Type`; simplest: rebuild the collection through `Update-WinForgeDiagnosticsWindowsUpdateGrid` after updating `$sync.DiagWUState`). Commit `feat(diag): installed/failed state per Windows Update driver row`.

---

### Task 4: Docs, 1.7.0

README (Ajustes: "já aplicado" e o que Aplicar faz com eles; Diagnóstico: uma linha por dispositivo, estado após instalar), `docs/changelog.md` `## 1.7.0 (2026-09-11)`, `version.props` 1.7.0; `build.cmd`, `dotnet test` 22/22, `git diff --exit-code -- docs/auditoria.md`. Commit `docs: estado aplicado e drivers do Windows Update; release 1.7.0`.

## Self-review
- Coverage of the three feedback items ✔; no placeholders; names consistent (`$sync.AppliedTweaks`, `Select-WinForgeTweaksToApply -Keys [-Applied]`, `Select-WinForgeWindowsUpdateLatest -Rows`, `State`/`StatusText`, `$sync.DiagWUState`, tokens `RowSuccessBackgroundColor`/`RowFailureBackgroundColor`).
