# WinForge Plan 2 — Auditoria de segurança dos tweaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every tweak/toggle in WinForge carries an explicit risk class (Seguro / Cuidado / Removido) enforced at build time: Removido entries disappear, Cuidado entries live only in the "Avançado (CUIDADO)" category with the cost stated in their description and never in a preset, and `docs/auditoria.md` is generated from the same data. Also closes the Plan 1 parked security finding (ProgramData folder ownership).

**Architecture:** A data file `src/Engine/config/wf-audit.ps1` declares `$sync.WinForgeAudit` (key → class, reason, optional property overrides). `Initialize-WinForgeAudit` (new file `src/Engine/winforge/wf-audit.ps1`) applies it right after `Initialize-WinForgeBoostConfigs`, mutating `$sync.configs.tweaks` and `$sync.configs.preset` in memory. SelfTest asserts completeness (every tweak classified), preset purity (Seguro only) and removals. `build.ps1` renders `docs/auditoria.md` from the same data so docs cannot drift.

**Tech Stack:** Windows PowerShell 5.1, existing build pipeline (`src/Engine/build.ps1`), C# net48 launcher + xUnit.

**Spec:** `docs/superpowers/specs/2026-09-07-winforge-design.md` §5.5 (audit), §7; Plan 1 ledger parked item (ProgramData owner).

## Global Constraints

- Never edit `src/Engine/base/winutil-26.08.19.ps1` or the generated `dist/engine/WinForge.ps1`; all changes go through `src/Engine/{winforge,config,xaml}` and `build.ps1` injections.
- Functions must be named `*-WinForge*` (runspace import filter `winforge|WPF`). New PowerShell files UTF-8 with BOM.
- Brand test / mojibake / marca antiga must stay 0; SelfTest 0 errors; `dotnet test` green; `build.cmd` ends with `OK: dist\WinForge.exe`.
- Class rules (spec §5.5): **Seguro** = reversible, no security or stability cost, may appear in presets. **Cuidado** = real trade-off; only in category `zz__Avançado (CUIDADO)`; description starts with `CUIDADO: <custo>. `; never in a preset. **Removido** = net-negative; entry and any preset reference deleted.
- Provenance text "Origem: ... Windows Boost - Essential" stays; no new "WindowsBoost"/CTT strings.
- Version bump to `1.1.0` in `version.props` in the last task; Conventional Commits with trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; branch `feat/plan2-auditoria` from `main`; finish with push + PR (never local merge).

---

## Classification table (single source for Task 2's data file — copy verbatim)

Keys not listed here and matching `WPFTweaksWBGame*` are Seguro automatically (per-game CPU priority, IFEO, reversible). Entries of `Type` Button/Combobox are exempt from classification (they are actions, not tweaks) except where listed.

| Key | Class | Reason (pt-BR, goes into description for Cuidado) | Override |
|---|---|---|---|
| WPFTweaksActivity | Seguro | — | |
| WPFTweaksHiber | Seguro | — (regras de hardware tratam notebook no Plano 3) | |
| WPFTweaksWidget | Seguro | — | |
| WPFTweaksRevertStartMenu | Cuidado | usa override interno de recurso (FeatureManagement) que a Microsoft pode remover; pode não ter efeito ou reverter sozinho | |
| WPFTweaksDisableStoreSearch | Cuidado | nega permissão ao banco da Microsoft Store (store.db); pode quebrar a busca e atualizações da Store até desfazer | |
| WPFTweaksLocation | Seguro | — | |
| WPFTweaksServices | Seguro | — | |
| WPFTweaksConsumerFeatures | Seguro | — | |
| WPFTweaksTelemetry | Seguro | — | |
| WPFTweaksDeliveryOptimization | Seguro | — | |
| WPFTweaksDisableBitLocker | Cuidado | descriptografa a unidade do sistema: perde a proteção contra roubo/acesso físico e demora muito em discos grandes | category → `zz__Avançado (CUIDADO)` |
| WPFTweaksRestorePoint | Seguro | — | |
| WPFTweaksEndTaskOnTaskbar | Seguro | — | |
| WPFTweaksWPBT | Seguro | — | |
| WPFTweaksPreventDeviceMetadataFromNetwork | Seguro | — | |
| WPFTweaksDiskCleanup | Seguro | — | InvokeScript → `@("cleanmgr.exe /d C: /VERYLOWDISK", "Dism.exe /online /Cleanup-Image /StartComponentCleanup")` (remove `/ResetBase`: ele impede desinstalar atualizações já aplicadas); Description → "Executa a Limpeza de Disco e o StartComponentCleanup do DISM (sem /ResetBase, para manter a possibilidade de desinstalar atualizações)." |
| WPFTweaksDeleteTempFiles | Seguro | — | |
| WPFTweaksDisableExplorerAutoDiscovery | Seguro | — | |
| WPFTweaksBraveDebloat | Seguro | — (só afeta o Brave, por política) | |
| WPFTweaksDisableWarningForUnsignedRdp | Cuidado | remove o aviso de segurança ao abrir arquivos .rdp não assinados | |
| WPFTweaksEdgeDebloat | Seguro | — | |
| WPFTweaksRemoveEdge | Cuidado | remove o navegador Edge; apps que dependem dele (Widgets, alguns instaladores, PDF padrão) deixam de funcionar; o Windows pode reinstalá-lo em atualizações | |
| WPFTweaksUTC | Cuidado | só faz sentido em dual boot com Linux; em PC só Windows o relógio fica errado até desfazer | |
| WPFTweaksRemoveOneDrive | Cuidado | desinstala o OneDrive e move arquivos para o perfil local; arquivos só na nuvem NÃO são baixados antes | |
| WPFTweaksRemoveHomeAndGallery | Seguro | — | |
| WPFTweaksDisplay | Seguro | — | |
| WPFTweaksReservedStorage | Cuidado | sem o armazenamento reservado, atualizações do Windows podem falhar quando o disco estiver quase cheio | |
| WPFTweaksStorage | Seguro | — | |
| WPFTweaksWindowsAI | Cuidado | remove o Copilot/Recall e componentes de IA (pacote CoreAI) do sistema; reinstalar exige atualização do Windows | |
| WPFTweaksRazerBlock | Seguro | — | |
| WPFTweaksDisableNotifications | Cuidado | desliga TODAS as notificações (toasts) e a Central de Ações, incluindo alertas de antivírus e de bateria | |
| WPFTweaksBlockAdobeNet | Cuidado | edita o arquivo hosts com uma lista baixada da internet; quebra login, licenciamento e atualização de produtos Adobe | |
| WPFTweaksRightClickMenu | Seguro | — | |
| WPFTweaksIPv46 | Seguro | — | |
| WPFTweaksTeredo | Cuidado | o Teredo é usado pelo Xbox Live (chat de festa, multiplayer de jogos Xbox no PC); desativar pode quebrar esses recursos | |
| WPFTweaksDisableIPv6 | Cuidado | desativa o IPv6 em todos os adaptadores; redes, VPNs e provedores que dependem de IPv6 param de funcionar | |
| WPFTweaksDisableBGapps | Cuidado | impede TODOS os apps da Store de rodar em segundo plano: e-mail, calendário e mensagens param de sincronizar/notificar | |
| WPFToggleDetailedBSoD | Seguro | — | |
| WPFToggleBatteryPercentage | Seguro | — | |
| WPFToggleDarkMode | Seguro | — | |
| WPFToggleShowExt | Seguro | — | |
| WPFToggleHiddenFiles | Seguro | — | |
| WPFToggleVerboseLogon | Seguro | — | |
| WPFToggleNewOutlook | Seguro | — | |
| WPFToggleScrollbars | Seguro | — | |
| WPFToggleMouseAcceleration | Seguro | — | |
| WPFToggleNumLock | Seguro | — | |
| WPFToggleWindowSnapping | Seguro | — | |
| WPFToggleStandbyFix | Seguro | — | |
| WPFToggleS3Sleep | Cuidado | força suspensão S3 em vez de Modern Standby; em notebooks modernos pode impedir a suspensão ou o despertar correto | |
| WPFToggleHideSettingsHome | Seguro | — | |
| WPFToggleBingSearch | Seguro | — | |
| WPFToggleLoginBlur | Seguro | — | |
| WPFTweaksDisableLockscreen | Seguro | — | |
| WPFToggleStartMenuRecommendations | Seguro | — | |
| WPFToggleStickyKeys | Seguro | — | |
| WPFToggleTaskbarAlignment | Seguro | — | |
| WPFToggleTaskbarSearch | Seguro | — | |
| WPFToggleTaskView | Seguro | — | |
| WPFToggleGameMode | Seguro | — | |
| WPFToggleLongPaths | Seguro | — | |
| WPFTweaksWBPowerSettings | Seguro | — (regras de notebook no Plano 3) | |
| WPFTweaksWBNtfsLastAccess | Seguro | — | |
| WPFTweaksWBServicesSafe | Seguro | — | |
| WPFTweaksWBAds | Seguro | — | |
| WPFTweaksWBCortana | Seguro | — | |
| WPFTweaksWBSearchSuggestions | Seguro | — | |
| WPFTweaksWBPrefetch | Cuidado | em HDD deixa o sistema mais lento; só faz sentido em SSD | |
| WPFTweaksWBSmartScreen | Removido | reduz a segurança sem ganho de desempenho (SmartScreen e marca de origem de downloads) | |
| WPFTweaksWBIndexing | Cuidado | a pesquisa do menu Iniciar, do Explorador e do Outlook fica lenta ou incompleta | |
| WPFTweaksWBServicesAggressive | Removido | pacote que desliga impressão, Bluetooth, RDP, Windows Hello e teclado touch de uma vez; substituído por 5 itens separados (Task 3) | |
| WPFTweaksWBVBS | Cuidado | reduz a segurança contra malware de kernel (VBS/HVCI); ganho de FPS em alguns jogos; exige reinício | |
| WPFTweaksWBHypervisorOff | Cuidado | quebra WSL2, Hyper-V, Windows Sandbox, WSA e emuladores baseados em Hyper-V; exige reinício | |
| WPFToggleWBTransparency | Seguro | — | |
| WPFToggleWBHAGS | Seguro | — | |
| WPFTweaksWBGameDVR | Seguro | — | |
| WPFTweaksWBMMCSSGames | Seguro | — | |
| WPFTweaksWBWin32PrioritySeparation | Seguro | — | |
| WPFTweaksWBXboxServices | Cuidado | quebra login no app Xbox, Game Pass, Minecraft Bedrock e jogos com conta Xbox | |
| WPFTweaksWBTimerBcdedit | Cuidado | altera timer do kernel via bcdedit; pode causar instabilidade, stutter ou consumo maior; exige reinício | |
| WPFTweaksWBNvidiaTelemetry | Seguro | — | |
| WPFTweaksWBNvidiaShadowPlay | Seguro | — | |
| WPFTweaksWBAmdTelemetry | Seguro | — | |
| WPFTweaksWBAmdULPS | Cuidado | altera o driver AMD (ULPS) em todas as instâncias; em notebooks pode aumentar consumo; exige reinício | |
| WPFTweaksWBAmdShaderCache | Seguro | — | |
| WPFTweaksWBAmdCrashDefender | Seguro | — | |
| WPFTweaksWBSvcSpooler | Cuidado | (criado na Task 3) desliga o Spooler: impressão e impressoras PDF param de funcionar | |
| WPFTweaksWBSvcBluetooth | Cuidado | (Task 3) desliga o Bluetooth (bthserv): mouses, teclados e fones Bluetooth param | |
| WPFTweaksWBSvcRdp | Cuidado | (Task 3) desliga a Área de Trabalho Remota (TermService): ninguém consegue acessar este PC por RDP | |
| WPFTweaksWBSvcHello | Cuidado | (Task 3) desliga a biometria (WbioSrvc): Windows Hello por rosto/digital deixa de funcionar | |
| WPFTweaksWBSvcTouchKeyboard | Cuidado | (Task 3) desliga o teclado virtual/caneta (TabletInputService): tablets e 2-em-1 perdem o teclado na tela | |

Preset consequences: Advanced preset loses `WPFTweaksRemoveOneDrive` and `WPFTweaksWindowsAI` (Cuidado); Standard/WindowsBoost/Gamer keep `WPFTweaksDiskCleanup` because its script override makes it Seguro. Nothing else in any preset is Cuidado/Removido (SelfTest proves it).

---

### Task 1: ProgramData folder ownership (Plan 1 parked security finding)

**Files:**
- Modify: `src/Launcher/EngineHost.cs` (`BuildDirectorySecurity`, `EnsureEngine`)
- Modify: `src/Launcher.Tests/EngineHostTests.cs`

**Interfaces:**
- `EngineHost.BuildDirectorySecurity()` now also sets owner = BUILTIN\Administrators; `EnsureEngine` creates the base dir atomically with `Directory.CreateDirectory(path, security)` and re-applies security when the directory already exists.

- [ ] **Step 1: Extend the test** — in `EngineHostTests.cs`, in the existing `BuildDirectorySecurity` test add:
```csharp
var owner = security.GetOwner(typeof(System.Security.Principal.SecurityIdentifier)) as System.Security.Principal.SecurityIdentifier;
Assert.NotNull(owner);
Assert.True(owner.IsWellKnown(System.Security.Principal.WellKnownSidType.BuiltinAdministratorsSid));
```
Run: `dotnet test src\Launcher.Tests\Launcher.Tests.csproj -c Release -nologo` → 1 failing (owner null).

- [ ] **Step 2: Implement** — in `BuildDirectorySecurity()` add `security.SetOwner(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null));` before returning. In `EnsureEngine`, replace the create-then-ACL sequence for the base dir with:
```csharp
var baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "WinForge");
var security = BuildDirectorySecurity();
if (!Directory.Exists(baseDir)) Directory.CreateDirectory(baseDir, security);
else new DirectoryInfo(baseDir).SetAccessControl(security);
```
Setting the owner to Administrators requires the caller to hold SeRestorePrivilege or be that principal — the launcher runs elevated as a member of Administrators, which is allowed to take ownership for the Administrators group. If `SetAccessControl` throws `InvalidOperationException`/`UnauthorizedAccessException` on owner, catch that specific failure, retry once without the owner (build security without `SetOwner`) and log to `%LocalAppData%\WinForge\launcher.log` a line `owner not set: <message>`; never continue with an unprotected DACL.

- [ ] **Step 3: Run tests** → all pass (8 + extended). `dotnet build src\Launcher\WinForge.csproj -c Release -nologo` → 0 warnings.

- [ ] **Step 4: Commit** — `fix(launcher): reclaim ownership of ProgramData folder, atomic protected create`

---

### Task 2: Audit data + `Initialize-WinForgeAudit` + SelfTest assertions (TDD)

**Files:**
- Create: `src/Engine/config/wf-audit.ps1` (data), `src/Engine/winforge/wf-audit.ps1` (functions)
- Modify: `src/Engine/build.ps1` (read/insert both files; call `Initialize-WinForgeAudit` after `Initialize-WinForgeBoostConfigs`; SelfTest assertions)

**Interfaces:**
- `$sync.WinForgeAudit` : hashtable `key -> @{ Class = 'Seguro'|'Cuidado'|'Removido'; Reason = '<pt-BR>'; Override = @{ <property> = <value> } }` (Override optional).
- `Initialize-WinForgeAudit` mutates `$sync.configs.tweaks` / `$sync.configs.preset`; adds `risk` NoteProperty (`seguro`|`cuidado`) to every surviving tweak; exports `$sync.WinForgeAuditReport` (list of `[pscustomobject]@{Key;Content;Class;Reason;Category}`) for docs/SelfTest.
- Constant category name: `zz__Avançado (CUIDADO)`.

- [ ] **Step 1: Write the SelfTest assertions first (RED)** — in `build.ps1`'s SelfTest block, after the count locks, add:
```powershell
    # Auditoria de risco
    $wbUnclassified = @(); $wbPresetViolations = @()
    foreach ($t in $sync.configs.tweaks.PSObject.Properties) {
        $e = $t.Value
        if ($e.Type -in @('Button','Combobox','Note','ToggleButton')) { continue }
        if (-not $e.PSObject.Properties['risk']) { $wbUnclassified += $t.Name }
        if ($e.risk -eq 'cuidado' -and $e.category -ne 'zz__Avançado (CUIDADO)') { Write-Host "  [ERRO] $($t.Name): Cuidado fora da categoria CUIDADO ($($e.category))" -ForegroundColor Red; $wbErrors++ }
        if ($e.risk -eq 'cuidado' -and $e.Description -notlike 'CUIDADO: *') { Write-Host "  [ERRO] $($t.Name): descrição de Cuidado sem prefixo" -ForegroundColor Red; $wbErrors++ }
    }
    if ($wbUnclassified.Count) { Write-Host "  [ERRO] tweaks sem classe de risco: $($wbUnclassified -join ', ')" -ForegroundColor Red; $wbErrors++ }
    foreach ($p in $sync.configs.preset.PSObject.Properties) {
        foreach ($k in @($p.Value)) {
            $e = $sync.configs.tweaks.$k
            if ($null -eq $e) { continue }   # appx/apps keys
            if ($e.risk -ne 'seguro') { $wbPresetViolations += "$($p.Name):$k" }
        }
    }
    if ($wbPresetViolations.Count) { Write-Host "  [ERRO] presets com itens não-Seguro: $($wbPresetViolations -join ', ')" -ForegroundColor Red; $wbErrors++ }
    foreach ($k in @($sync.WinForgeAudit.Keys | Where-Object { $sync.WinForgeAudit[$_].Class -eq 'Removido' })) {
        if ($sync.configs.tweaks.PSObject.Properties[$k]) { Write-Host "  [ERRO] $k deveria ter sido removido" -ForegroundColor Red; $wbErrors++ }
    }
    $wbCuidado = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.risk -eq 'cuidado' }).Count
    $wbSeguro  = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.risk -eq 'seguro' }).Count
    Write-Host "  Auditoria: $wbSeguro Seguro, $wbCuidado Cuidado, $(@($sync.WinForgeAudit.Keys | Where-Object { $sync.WinForgeAudit[$_].Class -eq 'Removido' }).Count) Removido"
```
Build + SelfTest → expect errors (`tweaks sem classe de risco: ...`). That is RED.

- [ ] **Step 2: Data file `src/Engine/config/wf-audit.ps1`** — `#region ===== WinForge - auditoria de risco =====` then `$sync.WinForgeAudit = @{ ... }` with one entry per row of the Classification table (Reason for Seguro rows = `''`; Override hashtable only where the table's Override column is non-empty: `WPFTweaksDisableBitLocker` category, `WPFTweaksDiskCleanup` InvokeScript + Description). Also `$sync.WinForgeCautionCategory = 'zz__Avançado (CUIDADO)'`.

- [ ] **Step 3: Functions file `src/Engine/winforge/wf-audit.ps1`**
```powershell
#region ===== WinForge - auditoria de risco (aplicação) =====
function Initialize-WinForgeAudit {
    <#
    .SYNOPSIS
        Aplica a classificação de risco: remove entradas 'Removido', move 'Cuidado' para a categoria CUIDADO
        com o custo na descrição, marca 'risk' em todas e limpa presets. Jogos (WPFTweaksWBGame*) são Seguro.
    #>
    $audit = $sync.WinForgeAudit
    $caution = $sync.WinForgeCautionCategory
    $report = [System.Collections.Generic.List[object]]::new()

    foreach ($key in @($audit.Keys)) {
        $a = $audit[$key]
        $prop = $sync.configs.tweaks.PSObject.Properties[$key]
        if ($a.Class -eq 'Removido') {
            if ($prop) { $sync.configs.tweaks.PSObject.Properties.Remove($key) }
            foreach ($p in $sync.configs.preset.PSObject.Properties) { $p.Value = @($p.Value | Where-Object { $_ -ne $key }) }
            $report.Add([pscustomobject]@{ Key = $key; Content = $(if ($prop) { $prop.Value.Content } else { $key }); Class = 'Removido'; Reason = $a.Reason; Category = '' })
            continue
        }
        if (-not $prop) { continue }   # entrada só existe após Task 3 (serviços separados) ou foi filtrada
        $e = $prop.Value
        if ($a.Override) { foreach ($o in $a.Override.GetEnumerator()) { $e | Add-Member -NotePropertyName $o.Key -NotePropertyValue $o.Value -Force } }
        if ($a.Class -eq 'Cuidado') {
            $e | Add-Member -NotePropertyName category -NotePropertyValue $caution -Force
            if ($e.Description -notlike 'CUIDADO: *') { $e | Add-Member -NotePropertyName Description -NotePropertyValue ("CUIDADO: {0}. {1}" -f $a.Reason.TrimEnd('.'), $e.Description) -Force }
            foreach ($p in $sync.configs.preset.PSObject.Properties) { $p.Value = @($p.Value | Where-Object { $_ -ne $key }) }
        }
        $e | Add-Member -NotePropertyName risk -NotePropertyValue $a.Class.ToLower() -Force
        $report.Add([pscustomobject]@{ Key = $key; Content = $e.Content; Class = $a.Class; Reason = $a.Reason; Category = $e.category })
    }
    foreach ($p in $sync.configs.tweaks.PSObject.Properties) {
        if ($p.Name -like 'WPFTweaksWBGame*' -and -not $p.Value.PSObject.Properties['risk']) {
            $p.Value | Add-Member -NotePropertyName risk -NotePropertyValue 'seguro' -Force
        }
    }
    $sync.WinForgeAuditReport = $report
    Write-WinForgeLog -Component "Audit" -Message ("Auditoria aplicada: {0} classificados, {1} removidos." -f $report.Count, @($report | Where-Object Class -eq 'Removido').Count)
}
#endregion
```
Note on `$p.Value = @(...)` for preset properties: `PSNoteProperty.Value` is settable; verify with a quick `powershell -Command` snippet before relying on it; if not settable, use `$sync.configs.preset | Add-Member -NotePropertyName $p.Name -NotePropertyValue @(...) -Force`.
Also the WinUtil preset `Advanced` references `WPFTweaksRemoveOneDrive`/`WPFTweaksWindowsAI` → they are dropped automatically by the Cuidado branch.
The category label shown to users strips everything up to `__`, so `zz__Avançado (CUIDADO)` displays as `Avançado (CUIDADO)` and sorts last; the WinUtil category `z__Advanced Tweaks - CAUTION` keeps its Seguro members (Brave, Edge debloat, Display, Storage, Razer, IPv46, RemoveHomeAndGallery, RightClickMenu) — rename it in the same function to `Avançado (WinUtil)`: `foreach ($p in $sync.configs.tweaks.PSObject.Properties) { if ($p.Value.category -eq 'z__Advanced Tweaks - CAUTION') { $p.Value | Add-Member -NotePropertyName category -NotePropertyValue 'y__Avançado' -Force } }` so that ordering is Essential → WinForge → Avançado → Avançado (CUIDADO). Note: the ordering trick relies on `Sort-Object` of category names; `y__` < `zz__`.

- [ ] **Step 4: Wire in `build.ps1`** — read both files (`Read-Lf`), insert the functions file before `#region ===== WinForge - logo =====` (like `wf-launcher.ps1`), insert the data file right after the existing config block insert (before `$inputXML = @'`); after the line `Initialize-WinForgeBoostConfigs` in the startup insert add `Initialize-WinForgeAudit`. Because the data file uses the `$sync.WinForgeAudit` name (already `WinForge`), the rename pass leaves it alone.

- [ ] **Step 5: Build + SelfTest (GREEN)** → `Auditoria: N Seguro, M Cuidado, 2 Removido`, 0 errors. Update the count locks: Tweaks-tab count changes (Removido −2 from tab Tweaks; Task 3 adds +5): after this task expect `Tweaks: 78`; set the lock to 78 now and to 83 in Task 3. Jogos stays 84, Config 42.

- [ ] **Step 6: Commit** — `feat(engine): risk audit data and enforcement (Seguro/Cuidado/Removido), SelfTest gates`

---

### Task 3: Split the aggressive services bundle into five Cuidado items; drop SmartScreen entry from config

**Files:**
- Modify: `src/Engine/config/wb-config.ps1` (remove `WPFTweaksWBServicesAggressive` and `WPFTweaksWBSmartScreen` JSON objects; add five entries), `src/Engine/build.ps1` (count lock 83)

- [ ] **Step 1: Remove the two JSON objects** (`WPFTweaksWBSmartScreen`, `WPFTweaksWBServicesAggressive`) from `wb-config.ps1`. Keep their rows in the audit data as `Removido` (documentation + SelfTest guard against re-adding).

- [ ] **Step 2: Add five entries** (category can be anything — the audit moves them to CUIDADO — use `"category": "zz__Avançado (CUIDADO)"`, `"panel": "1"`):
```json
  "WPFTweaksWBSvcSpooler":       { "Content": "Serviço de impressão (Spooler) - Desativar",          "Description": "Desativa o Spooler de Impressão. Origem: 'Desativar seviços.bat'.", "category": "zz__Avançado (CUIDADO)", "panel": "1", "service": [ { "Name": "Spooler",            "StartupType": "Disabled", "OriginalType": "Automatic" } ] },
  "WPFTweaksWBSvcBluetooth":     { "Content": "Bluetooth (bthserv) - Desativar",                      "Description": "Desativa o serviço de suporte a Bluetooth. Origem: 'Desativar seviços.bat'.", "category": "zz__Avançado (CUIDADO)", "panel": "1", "service": [ { "Name": "bthserv",            "StartupType": "Disabled", "OriginalType": "Manual" } ] },
  "WPFTweaksWBSvcRdp":           { "Content": "Área de Trabalho Remota (TermService) - Desativar",   "Description": "Desativa o serviço de Área de Trabalho Remota. Origem: 'Desativar seviços.bat'.", "category": "zz__Avançado (CUIDADO)", "panel": "1", "service": [ { "Name": "TermService",        "StartupType": "Disabled", "OriginalType": "Manual" } ] },
  "WPFTweaksWBSvcHello":         { "Content": "Biometria / Windows Hello (WbioSrvc) - Desativar",   "Description": "Desativa o serviço de biometria. Origem: 'Desativar seviços.bat'.", "category": "zz__Avançado (CUIDADO)", "panel": "1", "service": [ { "Name": "WbioSrvc",           "StartupType": "Disabled", "OriginalType": "Manual" } ] },
  "WPFTweaksWBSvcTouchKeyboard": { "Content": "Teclado virtual e caneta (TabletInputService) - Desativar", "Description": "Desativa o teclado na tela e o painel de caneta. Origem: 'Desativar seviços.bat'.", "category": "zz__Avançado (CUIDADO)", "panel": "1", "service": [ { "Name": "TabletInputService", "StartupType": "Disabled", "OriginalType": "Manual" } ] }
```
- [ ] **Step 3: Count lock → 83; build + SelfTest** → `Auditoria: ... Cuidado` includes the five; presets unaffected; brand 0.
- [ ] **Step 4: Commit** — `refactor(config): split aggressive services into five CUIDADO items, drop SmartScreen tweak`

---

### Task 4: Generated `docs/auditoria.md`, README/changelog, version 1.1.0

**Files:**
- Modify: `src/Engine/build.ps1` (render audit doc), `README.md`, `docs/changelog.md`, `version.props`
- Create (generated, committed): `docs/auditoria.md`

- [ ] **Step 1: Render in build.ps1** — after the parse check, dot-source the data file into a throwaway `$sync` (`$sync = @{}; . (Join-Path $PSScriptRoot 'config\wf-audit.ps1')`) and also load the tweak Contents by parsing the generated file's tweaks JSON (same extraction used in Plan 2 inventory: substring between `` $sync.configs.tweaks = @' `` and `'@ | ConvertFrom-Json`, then `ConvertFrom-Json`; the WB tweaks are in the `wbtweaks` block — parse both). Write `docs/auditoria.md` (UTF-8 no BOM, LF) with: header "Gerado por src/Engine/build.ps1 — não editar à mão", the class rules, then three tables (Seguro / Cuidado / Removido) with columns Chave | Nome | Motivo, sorted by key. Fail the build if a key in the audit data does not exist in either JSON block and is not one of the five Task-3 keys (typo guard) — i.e., all audit keys must resolve.
- [ ] **Step 2: README** — new section "Classificação de risco" (3 classes, link to `docs/auditoria.md`, "itens Cuidado nunca entram em presets"); update the Roadmap (auditoria done). `docs/changelog.md`: `## 1.1.0 (2026-09-07)` bullets: auditoria, SmartScreen/pacote agressivo removidos, 5 itens de serviço separados, Disk Cleanup sem /ResetBase, BitLocker movido para CUIDADO, ProgramData ownership.
- [ ] **Step 3: `version.props` → 1.1.0**; `build.cmd` → `OK: dist\WinForge.exe`; `git diff --stat` shows `docs/auditoria.md` regenerated identically on a second build (idempotent).
- [ ] **Step 4: Commit** — `docs: generated risk audit, README section, changelog; release 1.1.0`
