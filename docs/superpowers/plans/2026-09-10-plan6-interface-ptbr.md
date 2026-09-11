# WinForge Plan 6 — Interface em pt-BR, abas, Diagnóstico e visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WinForge fully in pt-BR, opening on Diagnóstico with tabs in usage order (Diagnóstico, Ajustes, Jogos, Configurações, Atualizações, Instalar, ISO Win11, Servidor), Install tab with collapsed categories and 96 niche apps removed, Diagnóstico fixed (wheel scroll over the driver grid, recommendation checklist mirrored to the real controls, per-driver action button with NVIDIA official download and Windows Update install), and one consistent visual system (theme tokens, Segoe UI, button/tab/card styles) verified by an elevated screenshot walkthrough.

**Architecture:** Everything stays build-time injection over the untouched base. Translation is hybrid: per-key dictionary applied to the parsed JSON configs (`config/wf-i18n-configs.ps1`, applied in `Initialize-WinUtilBoostConfigs`) plus literal `Replace-Once` pairs for XAML/functions/messages (`config/wf-i18n-strings.ps1`, applied by `build.ps1` in a loop that throws on a missing anchor). Tab order = replace the nav `StackPanel` block; TabItems/names/Alt keys untouched. App removal = key list applied before UI build. Diagnóstico changes live in `wf-diag.ps1` + `xaml/wf-xaml-diag-tab.xml`; downloads reuse the protected-folder helpers from `wf-server.ps1` and the RDN signer parser pattern; WU install uses COM in a runspace via the generic command core. Visual = theme token replacement in the base `themes` JSON + style overrides injected into `Window.Resources`. QA = `tools/UI-Walkthrough.ps1` (elevated, real mouse clicks, PNGs in `dist/screenshots/`).

**Tech Stack:** Windows PowerShell 5.1, WPF (XAML, DataGrid, ItemsControl, styles), `Microsoft.Update.Session` COM (`IUpdateDownloader`/`IUpdateInstaller`), UI Automation + `mouse_event` for QA, existing build/SelfTest pipeline.

**Spec:** `docs/superpowers/specs/2026-09-10-interface-ptbr-design.md` (all sections).

## Global Constraints

- Never edit `src/Engine/base/winutil-26.08.19.ps1` or `dist/` by hand. Edits only in `src/Engine/{winforge,config,xaml}` and anchored injections in `src/Engine/build.ps1` (helpers throw on missing/ambiguous anchors). Anchors from the base use pre-rename `WinUtil` names.
- New `.ps1`/`.xml` UTF-8 with BOM + CRLF; functions `*-WinForge*`; pt-BR text without marketing prose; brand/mojibake/old-brand tests 0; `docs/auditoria.md` byte-identical unless descriptions change (then regenerate and commit; the auditoria doc is generated from Content/Reason so translation changes it — Task 3 commits the regenerated doc).
- SelfTest 0 errors plain and with `WINFORGE_SIMULATE_SERVER=iis,ad`; locks Tweaks 83 / Jogos 84 / Servidor 22 / Config 54 unchanged; new locks: apps 139, nav order, language sweep, dictionary coverage.
- SelfTest never downloads, installs or changes the machine (`$sync.SelfTest` guard + `-DryRun`); downloads only from the NVIDIA URL returned by the official API; installers verified by Authenticode with exact RDN `O=NVIDIA Corporation`; downloads go to `%ProgramData%\WinForge\downloads` created/verified with the snapshot-root helpers (`New-WinForgeSnapshotRoot`/`Confirm-WinForgeSnapshotRoot` with `-Root`).
- Runspace rule: UI callbacks are file-scope scriptblocks on the main runspace; long work in `Invoke-WPFRunspace`; one command at a time (`$sync.CommandRunning`).
- Screenshots: `tools/UI-Walkthrough.ps1` runs elevated with real mouse clicks; check `Get-Process cs2,csgo` first; never run while a game is open. It is manual QA, not CI.
- Version → `1.5.0` in the last task. Conventional Commits + trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Branch `feat/plan6-interface`; finish with push + PR (never local merge).

## File map

| Path | Responsibility |
|---|---|
| `src/Engine/config/wf-apps.ps1` | `$sync.WinForgeRemovedApps` (96 keys), `$sync.WinForgeAppCategoryMap` (EN→PT + migrations) |
| `src/Engine/config/wf-i18n-strings.ps1` | `$WinForgeI18nStrings = @(@('original','tradução'), ...)` applied by build.ps1 (XAML, functions, messages) |
| `src/Engine/config/wf-i18n-configs.ps1` | `$sync.WinForgeI18n = @{ '<key>' = @{ Content; Description } }` for tweaks/toggles/features/apps |
| `src/Engine/winforge/wb-functions.ps1` | `Initialize-WinUtilBoostConfigs`: app removal, category map, dictionary application; `Set-WinForgeInstallCollapsed` |
| `src/Engine/winforge/wf-diag.ps1` | wheel forwarding, recommendation checklist + mirror, driver action column, WU install, NVIDIA download |
| `src/Engine/winforge/wf-drivers.ps1` | `Install-WinForgeNvidiaDriver [-DryRun]`, `Install-WinForgeWindowsUpdateDriver -UpdateId [-DryRun]`, `Test-WinForgeNvidiaSigner` |
| `src/Engine/xaml/wf-xaml-nav.xml` | full nav `StackPanel` in the new order with pt-BR labels (replaces base block + WinForge nav pieces) |
| `src/Engine/xaml/wf-xaml-diag-tab.xml` | recommendation checklist template, Ação columns, counter/buttons |
| `src/Engine/xaml/wf-xaml-styles.xml` | style overrides (Button, ToggleButton tab, CheckBox, DataGrid, headers) |
| `src/Engine/config/wf-theme.ps1` | token values for Dark/Light applied by build to the base `themes` JSON |
| `src/Engine/build.ps1` | inserts, anchors, i18n loop, theme token replace, SelfTest |
| `tools/UI-Walkthrough.ps1` | elevated screenshot walkthrough |

---

### Task 1: Tab order, default tab, Install collapsed, app removal, QA tool

**Files:** Create `src/Engine/xaml/wf-xaml-nav.xml`, `src/Engine/config/wf-apps.ps1`, `tools/UI-Walkthrough.ps1`; Modify `src/Engine/winforge/wb-functions.ps1`, `src/Engine/build.ps1`; Delete `src/Engine/xaml/wb-xaml-nav.xml`, `wf-xaml-diag-nav.xml`, `wf-xaml-server-nav.xml` (merged into the new nav file).

**Interfaces (produces):** nav button names unchanged (`WPFTab1BT`..`WPFTab9BT`); `$sync.WinForgeRemovedApps` (string[]); `$sync.WinForgeAppCategoryMap` (hashtable EN→PT); `Set-WinForgeInstallCollapsed` (calls `Invoke-WPFToggleAllCategories -Action Collapse` when the Install tab mounts); SelfTest helpers `Get-WinForgeNavOrder` (returns the button names in visual order).

- [ ] **Step 1: Nav XAML.** `wf-xaml-nav.xml` = the whole `<StackPanel Name="NavDockPanel" ...> ... </StackPanel>` block (copy from base lines ~13805-13845 plus the WinForge buttons) in the order: WPFTab8BT (`<Underline>D</Underline>iagnóstico`), WPFTab2BT (`Ajus<Underline>t</Underline>es`), WPFTab7BT (`<Underline>J</Underline>ogos`), WPFTab3BT (`<Underline>C</Underline>onfigurações`), WPFTab9BT (`<Underline>S</Underline>ervidor`), WPFTab4BT (`At<Underline>u</Underline>alizações`), WPFTab1BT (`<Underline>I</Underline>nstalar`), WPFTab5BT (`ISO <Underline>W</Underline>in11`). Keep every attribute (styles, brushes) from the base; all buttons `Width="{DynamicResource TabButtonWidth}"` except none `Auto`. In `build.ps1` replace the base block with `Replace-Between $src '            <!-- Navigation Buttons Panel -->' '            <!-- Search Bar and Action Buttons -->' $navXaml "nav panel"` and delete the three old nav inserts.
- [ ] **Step 2: Default tab.** `Replace-Once $src '$sync.currentTab = "Install"' '$sync.currentTab = "Diagnostico"'` and `Replace-Once $src '        Invoke-WPFTab "WPFTab1BT"  # Default to install tab' '        Invoke-WPFTab "WPFTab8BT"  # WinForge: abre no Diagnóstico'`. Check the search-bar visibility logic keeps hiding the bar on tab 7 (index).
- [ ] **Step 3: Install collapsed.** In the `tab init` injection, the `"Install"` case (add one if the base has none — read `Initialize-WinUtilTabContent`) calls `Set-WinForgeInstallCollapsed` after building; function in `wb-functions.ps1` wraps `Invoke-WPFToggleAllCategories -Action "Collapse"` in try/catch with log.
- [ ] **Step 4: App removal + categories.** `wf-apps.ps1`:

```powershell
$sync.WinForgeRemovedApps = @(
  'WPFInstallchromium','WPFInstallfirefoxesr','WPFInstallfloorp','WPFInstallhelium','WPFInstallmullvadbrowser','WPFInstallungoogled','WPFInstallwaterfox',
  'WPFInstallbetterbird','WPFInstallchatterino','WPFInstalldorion','WPFInstallmatrix','WPFInstallprotonmail','WPFInstallqtox','WPFInstallteamspeak3','WPFInstallvesktop','WPFInstallviber',
  'WPFInstalljava25','WPFInstalljava8','WPFInstallbruno','WPFInstallclaude-code','WPFInstallcmake','WPFInstallcodex','WPFInstallfnm','WPFInstallgitextensions','WPFInstallgithubcli','WPFInstalllazygit','WPFInstallLua','WPFInstallneovim','WPFInstallnodejs','WPFInstallposh','WPFInstallpnpm','WPFInstallRuby','WPFInstallstarship','WPFInstallsysteminformer','WPFInstallunity','WPFInstalluv','WPFInstallvagrant','WPFInstallvisualstudio2026','WPFInstallvscodium','WPFInstallyarn','WPFInstallZed',
  'WPFInstalljoplin','WPFInstallokular','WPFInstallpdfgear','WPFInstallpdfsam','WPFInstallpdf-xchange','WPFInstallqownnotes','WPFInstallsimplenote','WPFInstallxournal','WPFInstallzotero',
  'WPFInstallcemu','WPFInstalles-de','WPFInstallheroiclauncher','WPFInstallitch','WPFInstallmodrinth','WPFInstallOverwolf','WPFInstallroblox','WPFInstallvrdesktopstreamer',
  'WPFInstalldotnet9','WPFInstalldismtools','WPFInstallntlite','WPFInstallnuget','WPFInstallrdcman',
  'WPFInstallfoobar','WPFInstallmpc-qt','WPFInstallnomacs',
  'WPFInstallangryipscanner','WPFInstallgsudo','WPFInstallmullvadvpn','WPFInstallnmap','WPFInstallsimplewall',
  'WPFInstalljellyfinmediaplayer','WPFInstalljellyfinserver','WPFInstallnetbird','WPFInstallnextclouddesktop','WPFInstallplex','WPFInstallsunshine',
  'WPFInstallblurautoclicker','WPFInstalldeskflow','WPFInstallenteauth','WPFInstallfiles','WPFInstallglazewm','WPFInstallhugo','WPFInstallxeheditor','WPFInstalljpegview','WPFInstallmsedgeredirect','WPFInstallnilesoftShell','WPFInstallOFGB','WPFInstallOPAutoClicker','WPFInstallpolicyplus','WPFInstallprotonauth','WPFInstallprotondrive','WPFInstallprotonpass','WPFInstallsignalrgb','WPFInstallWiseProgramUninstaller'
)
$sync.WinForgeAppCategoryMap = @{ 'Browsers' = 'Navegadores'; 'Communications' = 'Comunicação'; 'Development' = 'Desenvolvimento'; 'Document' = 'Documentos'; 'Games' = 'Jogos'; 'Microsoft Tools' = 'Ferramentas Microsoft'; 'Multimedia Tools' = 'Multimídia'; 'Pro Tools' = 'Ferramentas profissionais'; 'Utilities' = 'Utilitários'; 'Selfhosted Tools' = 'Utilitários' }
$sync.WinForgeAppCategoryOverride = @{ 'WPFInstallplexdesktop' = 'Multimídia'; 'WPFInstallkodi' = 'Multimídia' }
```

In `Initialize-WinUtilBoostConfigs` (before the existing merges): remove keys from `$sync.configs.applications` (error-free if missing), map categories, apply overrides. Check every place the base derives the category filter buttons and `applicationsHashtable` from `$sync.configs.applications` runs AFTER this (the base builds `applicationsHashtable` near the appx hashtable — move the WinForge call before it if needed; verify in the generated engine).
- [ ] **Step 5: QA tool.** `tools/UI-Walkthrough.ps1` — the scratch script from this session, cleaned: params `-Launch` (starts `dist\WinForge.exe`, waits for the window), `-OutDir` (default `dist\screenshots`), refuses when `cs2`/`csgo` run, real mouse clicks via `mouse_event`, one PNG per tab plus Diagnóstico scrolled twice and once with the cursor over the driver grid, log file. Self-elevates with `Start-Process -Verb RunAs` when not admin. README "Compilar" mentions it (Task 7 docs).
- [ ] **Step 6: SelfTest.** Nav order: after XAML load, `@($wbWindow.FindName('NavDockPanel').Children | Where-Object { $_ -is [System.Windows.Controls.Primitives.ToggleButton] } | ForEach-Object Name)` equals `WPFTab8BT,WPFTab2BT,WPFTab7BT,WPFTab3BT,WPFTab9BT,WPFTab4BT,WPFTab1BT,WPFTab5BT` (assert in both modes; visibility is handled by `Update-WinForgeTabVisibility`). Generated engine contains `$sync.currentTab = "Diagnostico"` and `Invoke-WPFTab "WPFTab8BT"`. Apps: count 139, none of the removed keys present, no app with an English category, `WPFInstallplexdesktop` in `Multimídia`, `WPFInstalllocalsend` in `Utilitários`. Install tab mounted headless → every category expander `IsExpanded -eq $false` (find the expander control type the base uses).
- [ ] **Step 7: Build, SelfTest ×2, commit** `feat(ui): tab order with Diagnostico first, collapsed Install categories, curated app list`.

---

### Task 2: Translation infrastructure + XAML/functions/messages dictionary + language lock

**Files:** Create `src/Engine/config/wf-i18n-strings.ps1`; Modify `src/Engine/build.ps1`, existing `src/Engine/xaml/*.xml` where English remains.

**Interfaces (produces):** `$WinForgeI18nStrings` array of `@('original','tradução')`; build loop `foreach ($pair in $WinForgeI18nStrings) { $src = Replace-Once $src $pair[0] $pair[1] "i18n: $($pair[0])" }` placed AFTER all other injections and BEFORE the CTT-removal/rename passes (translations must not break later anchors: audit which anchors contain English text and order accordingly — or run the loop last, after rename; decide by trying, document in the report). `$sync.WinForgeEnglishSweep` list in build.ps1 for the SelfTest lock.

- [ ] **Step 1: Inventory.** Script (kept as `tools/List-EnglishStrings.ps1`) that prints every `Content=/Text=/Header=/ToolTip=` literal from the generated XAML and every `MessageBox::Show(` / user-facing `Write-Host` string from the generated engine, minus those already in Portuguese (heuristic: contains any of a list of common English words). Use it to build the pairs.
- [ ] **Step 2: Pairs.** Cover: nav labels (already in Task 1), Install tab (`Actions`, `Install/Upgrade Applications`, `Uninstall Applications`, `Upgrade all Applications`, `Package Manager`, `Selection`, `Clear Selection`, `Collapse All Categories`, `Expand All Categories`, `Selected Apps:`, `Show Installed Apps`, `Free and Open Source Software`, `All`), Tweaks (`Recommended Selections:`, `Standard`, `Minimal`, `Advanced`, `Clear`, `Get Installed Tweaks`, `AppX Removal`, `Run Tweaks`, `Undo Selected Tweaks`, category headers `Essential Tweaks`→`Ajustes essenciais`, `Customize Preferences`→`Preferências`, `z__Advanced Tweaks - CAUTION`→`zz__Avançado (CUIDADO)` (check the audit category constant stays consistent), `Performance Plans - NOT FOR LAPTOPS`), Config (`Features`→`Recursos do Windows`, `Fixes`→`Correções`, `Legacy Windows Panels`→`Painéis clássicos do Windows`, `Remote Access`→`Acesso remoto`, `Install Features`, button Contents of the base features — by key in Task 3, but the category strings here), Updates page (all texts: `Windows Update Profiles`, `Choose how Windows receives updates...`, `Recommended`, `Balanced security and stability`, bullet lines, `Apply Recommended`, `Windows Default`, `Return control to Windows`, `Restore Defaults`, `Disable Updates`, `Advanced use only`, `Security updates will not be installed...`, footer), Win11 Creator page (`Step 1 - Select Windows 11 ISO`, `Browse...`, `No ISO selected...`, `!!WARNING!!...`, `Open Microsoft Download Page`, `Status Log`, `Ready. Please select...`, and every later step label visible in the XAML), AppX tab labels, search placeholder, theme/font/settings tooltips, `Internet connection required for installing applications.`, common MessageBox texts (restart prompts, "Please select..."), `Write-Host` lines shown in the console during tweaks (`Running Script for`, `Completed`, etc. — only the user-visible ones; keep log text in English is acceptable? No: translate the console ones the user sees in the WinForge console window; log file lines may stay).
- [ ] **Step 3: Language lock.** SelfTest: `$wbEnglish = @('Recommended Selections','Run Tweaks','Undo Selected','Install/Upgrade','Uninstall Applications','Upgrade all','Clear Selection','Collapse All','Expand All','Selected Apps','Show Installed','Get Installed','Windows Update Profiles','Apply Recommended','Restore Defaults','Disable Updates','Status Log','Browse','Open Microsoft Download','Legacy Windows Panels','Essential Tweaks','Customize Preferences','Advanced Tweaks','Performance Plans','Remote Access','Install Features','Package Manager','Free and Open Source','No ISO selected','Select Windows 11 ISO')` + per-item suffixes `' - Disable'`, `' - Enable'`, `' - Remove'`, `' - Run'`, `' - Reset'`, `' - Create'`, `' - Reinstall'` — none may appear in the generated XAML (`$inputXML`) nor in any `Content`/`Description` of `$sync.configs.tweaks/feature` after Task 3 (this task asserts the XAML part; Task 3 extends to configs). Mutation: remove one pair → build fails or lock fires.
- [ ] **Step 4: Build, SelfTest ×2, commit** `feat(i18n): interface strings in pt-BR with build-time dictionary and language lock`.

---

### Task 3: Per-key dictionary (tweaks, toggles, features, updates, apps)

**Files:** Create `src/Engine/config/wf-i18n-configs.ps1`; Modify `src/Engine/winforge/wb-functions.ps1`, `src/Engine/build.ps1`; regenerate `docs/auditoria.md`.

**Interfaces:** `$sync.WinForgeI18n` hashtable; `Initialize-WinUtilBoostConfigs` applies it to `$sync.configs.tweaks`, `feature`, `applications` (apps: `description` only; `content` untouched) after merges and BEFORE `Initialize-WinForgeAudit` (the audit prefixes `CUIDADO:` on Descriptions and must see the translated text; verify order).

- [ ] **Step 1: Generator.** `tools/List-I18nKeys.ps1` prints every base key with `Content`/`Description` (tweaks incl. toggles, features, apps' `description`) that is NOT already in the dictionary, so coverage is mechanical.
- [ ] **Step 2: Dictionary.** ~120 tweak/toggle/feature entries + 139 app descriptions. Rules: `Content` keeps the `<thing> - <ação>` shape in pt-BR (`Histórico de atividades - Desativar`), proper nouns stay (`Copilot`, `OneDrive`, `Edge`), `Description` is a faithful translation (no new claims). WinForge's own entries (`WPFTweaksWB*`, `WPFTweaksWF*`, `WPFPanelWB*`, `WPFWFRep*`) are already pt-BR and are NOT in the dictionary (coverage gate ignores keys whose Content has no ASCII-only English pattern? simpler: gate = every key of the BASE configs (present in the base JSON) must be in the dictionary; WinForge keys are exempt by prefix list `WB|WF`).
- [ ] **Step 3: Apply + gates.** Coverage gate in SelfTest (every base key translated; every dictionary key exists); language lock extended to `Content/Description`; audit doc regenerated (Content changes) and committed; `docs/auditoria.md` row count unchanged.
- [ ] **Step 4: Build, SelfTest ×2, commit** `feat(i18n): tweaks, features, updates and app descriptions in pt-BR`.

---

### Task 4: Diagnóstico — wheel scroll, recommendation checklist with mirror, counters

**Files:** Modify `src/Engine/winforge/wf-diag.ps1`, `src/Engine/xaml/wf-xaml-diag-tab.xml`, `src/Engine/winforge/wf-rules.ps1` (reuse), `src/Engine/build.ps1`.

- [ ] **Step 1: Failing SelfTest**: after mounting Diagnóstico with `$sync.Recommended` from the real profile, `WPFDiagRecs` has N `CheckBox` children (N = recommended count, Toggle keys excluded); setting the first to `IsChecked = $true` checks `$sync[<key>]` (Tweaks tab mounted on demand); setting `$sync[<key>].IsChecked = $false` unchecks the mirror; `$sync.WinForgeMirrorBusy` is `$false` afterwards; `WPFDiagRecCount.Text` matches `'\d+ de \d+'`; a `PreviewMouseWheel` handler is attached to `WPFDiagDrivers` and `WPFDiagWU` (assert via a flag set in `Initialize-WinForgeDiagnosticsTab`, e.g. `$sync.WinForgeDiagWheelHooked -eq $true`, plus a real `MouseWheelEventArgs` raised on the grid moves the parent `ScrollViewer.VerticalOffset` when content is taller than the viewport — do it headless by giving the window a fixed height in the test).
- [ ] **Step 2: Implement.** Wheel: `$grid.Add_PreviewMouseWheel({ param($s,$e) $e.Handled = $true; $args2 = New-Object System.Windows.Input.MouseWheelEventArgs($e.MouseDevice, $e.Timestamp, $e.Delta); $args2.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent; $args2.Source = $s; $sync.WPFDiagScroll.RaiseEvent($args2) })` (name the tab's `ScrollViewer` `WPFDiagScroll`). Checklist: XAML `ItemsControl` with a `DataTemplate` (CheckBox + two TextBlocks) OR build rows in code (simpler with `$sync` wiring): for each recommended key create `CheckBox` (Tag = key, Content = translated `Content`), `TextBlock` reason (muted colour), attach `Checked/Unchecked` → `Set-WinForgeRecommendationMirror -Key -Checked` which mounts the target tab (`Initialize-WinForgeTabContent`) and sets the real control unless `$sync.WinForgeMirrorBusy`; hook the real control's `Checked/Unchecked` (once, when the Tweaks/Jogos/Servidor tab mounts — `Update-WinForgeRecommendationVisuals` is the existing hook point) to update the mirror. Buttons `WPFDiagSelectRecommended` → "Marcar todos" (no MessageBox; sets all mirrors), new `WPFDiagClearRecommended` "Desmarcar todos"; `WPFDiagRecCount` TextBlock "N de M recomendados marcados" refreshed by the mirror.
- [ ] **Step 3: SelfTest green, mutation-prove, build, commit** `feat(diag): recommendation checklist mirrored to the tabs; wheel scroll over grids`.

---

### Task 5: Diagnóstico — driver actions (NVIDIA download, vendor page, Windows Update install)

**Files:** Modify `src/Engine/winforge/wf-drivers.ps1`, `wf-diag.ps1`, `src/Engine/xaml/wf-xaml-diag-tab.xml`, `src/Engine/build.ps1`.

**Interfaces (produces):**
- `Get-WinForgeDownloadRoot` → `%ProgramData%\WinForge\downloads` (reuses `New-WinForgeSnapshotRoot -Root`/`Confirm-WinForgeSnapshotRoot -Root` semantics: DACL, owner, reparse; refuse when untrusted).
- `Test-WinForgeNvidiaSigner -Path` → `$true` only for Authenticode `Valid` with subject RDN `O` exactly `NVIDIA Corporation` (reuse `Split-WinForgeCertificateSubject` if still present, else re-add it in `wf-commands.ps1`).
- `Install-WinForgeNvidiaDriver -Url -Version [-DryRun]` → `@{ Path; Verified; Started; Text }`; DryRun returns URL + target path only. Real run: `Invoke-WebRequest` (TLS 1.2, 10-minute timeout, progress via `$sync` status bar), signer check, `Start-Process` (user drives the NVIDIA installer), log.
- `Install-WinForgeWindowsUpdateDriver -UpdateId <string> [-DryRun]` → `@{ ResultCode; RebootRequired; Text }`; uses the `IUpdate` objects cached in `$sync.DiagWUResults` (keep the COM objects in a parallel `$sync.DiagWUUpdates[UpdateId]`), `UpdateCollection` → `CreateUpdateDownloader` → `CreateUpdateInstaller`; DryRun returns title + id.
- Both write helpers call `Assert-WinForgeNotSelfTest` after the DryRun return.

- [ ] **Step 1: Failing SelfTest**: driver rows carry `ActionKind` (`nvidia-download` when Vendor nvidia and LatestStatus atualizar and Url present, `vendor-page` when a URL exists, `none` otherwise) and `ActionLabel` (`Baixar 616.92` / `Página do fabricante`); simulated profile row for NVIDIA behind produces `nvidia-download`; `Install-WinForgeNvidiaDriver -Url 'https://us.download.nvidia.com/x.exe' -Version '616.92' -DryRun` returns Path under the downloads root and `Started -eq $false`; `Test-WinForgeNvidiaSigner` rejects an unsigned temp file and the RDN parser rejects `O=NVIDIA Corporation Ltd`; `Install-WinForgeWindowsUpdateDriver -UpdateId 'x' -DryRun` returns `Text` containing `x` and does not throw; with `$sync.SelfTest` both helpers throw without `-DryRun`; XAML has `DataGridTemplateColumn` "Ação" in `WPFDiagDrivers` and "Instalar" in `WPFDiagWU` with a `Button` whose `Tag` is the row.
- [ ] **Step 2: Implement.** Button click handlers: created once in `Initialize-WinForgeDiagnosticsTab` via a class handler (`[System.Windows.EventManager]::RegisterClassHandler`? simpler: the template Button uses `Command`-less click; add a `Click` handler in the DataGrid's `LoadingRow`? Use the pattern: `$grid.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler]{ param($s,$e) $btn = $e.OriginalSource; if ($btn -is [System.Windows.Controls.Button] -and $btn.Tag) { Invoke-WinForgeDriverAction -Row $btn.Tag } })` on the grid). `Invoke-WinForgeDriverAction`: `vendor-page` → `Start-Process url`; `nvidia-download` → MessageBox confirm (version, ~size unknown → "vários centenas de MB") → `Invoke-WinForgeCommandButton` with a spec whose Command is `Install-WinForgeNvidiaDriver -Url '<url>' -Version '<v>'`? NO command text from data: instead dispatch a runspace body that calls the function with parameters (build the body as `{ param($u,$v) Install-WinForgeNvidiaDriver -Url $u -Version $v }` and pass `-ArgumentList`), progress via `Set-WinForgeProfileProgress`. WU install: confirm → runspace → result to status bar + log + MessageBox only when a reboot is required.
- [ ] **Step 3: SelfTest green, mutation-prove, build, commit** `feat(diag): driver actions - NVIDIA official download with signature check, vendor page, Windows Update install`.

---

### Task 6: Visual system — theme tokens, typography, control styles

**Files:** Create `src/Engine/config/wf-theme.ps1`, `src/Engine/xaml/wf-xaml-styles.xml`; Modify `src/Engine/build.ps1`.

- [ ] **Step 1: Tokens.** `wf-theme.ps1` = `$WinForgeTheme = @{ shared = @{ FontFamily = 'Segoe UI'; HeaderFontFamily = 'Segoe UI Semibold'; FontSize = '13'; HeaderFontSize = '15'; ButtonHeight = '32'; ButtonWidth = '200'; TabButtonWidth = '118'; TabButtonHeight = '32'; CheckBoxBulletDecoratorSize = '16'; ... }; Dark = @{ MainBackgroundColor = '#0B1220'; ... per spec §7 }; Light = @{ ... } }`. `build.ps1` rewrites each `"<Token>": "<value>"` line inside the base `themes` JSON (`Replace-Once` per token per section; the section is isolated with `Replace-Between` markers `"shared": {`, `"Light": {`, `"Dark": {`). Add SelfTest contrast check: helper `Get-WinForgeContrastRatio -Fg -Bg` (WCAG relative luminance) ≥ 4.5 for pairs (MainForegroundColor/MainBackgroundColor, ButtonForegroundColor/ButtonBackgroundColor, LabelboxForegroundColor/MainBackgroundColor, selected button text/bg) in both themes.
- [ ] **Step 2: Styles.** `wf-xaml-styles.xml` inserted at the end of `Window.Resources` (anchor `    </Window.Resources>`): implicit `Button` style override (Height from token, `MinWidth 120`, `Padding 14,0`, `CornerRadius 4`, hover animation 200 ms via `VisualStateManager` or `Trigger` with `ColorAnimation`), `TabToggleButton` restyle (equal width, selected background `ButtonBackgroundSelectedColor`, radius 4, 2 px bottom accent), `CheckBox` row spacing, DataGrid row height 26 + header semibold, card `Border` style used by `New-WinForgeDiagCard` (padding 12, radius 6). Keep existing `x:Key` names so base code keeps working; where the base sets `FontFamily="Consolas"` inline for category labels (`$label.SetResourceReference(... "HeaderFontFamily")` already uses the token — good), ensure no literal `Consolas` remains (SelfTest asserts the generated XAML/engine has no `Consolas` except in the output window's monospace TextBox).
- [ ] **Step 3: Screenshots** with `tools/UI-Walkthrough.ps1` (elevated) of all tabs in Dark and Light (toggle theme via the base theme button using UIA); attach paths in the report; fix clipped/misaligned items found.
- [ ] **Step 4: SelfTest ×2, build, commit** `feat(ui): WinForge visual system - tokens, typography and control styles`.

---

### Task 7: Sweep, docs, 1.5.0

**Files:** whatever the sweep finds (config/xaml/build only), `README.md`, `docs/changelog.md`, `version.props`.

- [ ] **Step 1: Full walkthrough** (`tools/UI-Walkthrough.ps1 -Launch`), review every PNG for: English leftovers (add pairs/keys), clipped text, buttons without auto width, wrong fonts, misaligned cards, status texts, tooltips. Fix; rerun the language lock and walkthrough.
- [ ] **Step 2: Docs.** README: rewrite the "Como usar" and tab names in pt-BR order, new section "Interface" (order, atalhos, temas), Diagnóstico section updated (checklist, ações de driver, Windows Update install rule: sempre com confirmação), Install section (139 apps, categorias), "Compilar" mentions `tools/UI-Walkthrough.ps1` and `tools/List-I18nKeys.ps1`; changelog `## 1.5.0 (<today>)`; `version.props` 1.5.0.
- [ ] **Step 3: `build.cmd`, `dotnet test` (22/22), `git diff --exit-code -- docs/auditoria.md`, commit** `docs: interface em pt-BR e Diagnóstico; release 1.5.0`.

---

## Self-review

- **Spec coverage:** §3 translation (T2 strings, T3 keys, locks) ✔; §4 order/default (T1) ✔; §5 Install (T1 collapse + removal + categories; T3 app descriptions) ✔; §6 Diagnóstico (T4 scroll + checklist; T5 actions + WU install) ✔; §7 visual (T6) ✔; §8 QA tool + sweep (T1 tool, T6/T7 use) ✔; §9 tests distributed per task ✔.
- **Placeholders:** none; where the plan leaves an implementation choice (row buttons handler, i18n loop position) it names the options and requires the report to state the decision.
- **Type consistency:** `$sync.WinForgeRemovedApps`/`WinForgeAppCategoryMap` (T1) used only in T1; `$sync.WinForgeI18n` (T3) applied in `Initialize-WinUtilBoostConfigs`; `Install-WinForgeNvidiaDriver -Url -Version [-DryRun]` and `Install-WinForgeWindowsUpdateDriver -UpdateId [-DryRun]` consistent between interface and SelfTest; `WPFDiagScroll`, `WPFDiagRecCount`, `WPFDiagClearRecommended` names used in T4 only.
