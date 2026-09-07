# WinForge — Design Spec

Date: 2026-09-07
Status: approved by Rafael Favero (chat), pending implementation plan

## 1. Goal

Turn the "Windows Boost 1.0" prototype (a WinUtil 26.08.19 fork with the *Windows Boost - Essential* scripts merged in) into a professional, public, reliable optimization utility for Windows 10, Windows 11 and Windows Server:

- ship as a real executable (`WinForge.exe`), not a bare `.ps1`;
- own branding (no Chris Titus Tech art, logo, sponsor or profile references), MIT license with WinUtil attribution kept in `NOTICE`;
- audit every tweak and remove or quarantine the ones that damage Windows;
- detect hardware, drivers and roles, and turn that into per-item recommendations shown in the UI (green outline + reason on hover);
- add Windows Server, IIS, Active Directory support and an "essential components repair" toolbox.

## 2. Non-goals

- Rewriting the WinUtil engine in C#. The engine stays PowerShell/WPF; the launcher is C#.
- Automatic download/installation of third-party drivers. Detection, comparison and official links only.
- Installer (MSI/Inno). First release is a portable `WinForge.exe`.
- Translating the inherited WinUtil UI strings. New content is Portuguese; inherited English stays.

## 3. Repository layout

```
WinForge/
  LICENSE                     MIT (Rafael Favero)
  NOTICE                      WinUtil attribution (MIT, Chris Titus Tech)
  README.md
  build.cmd                   builds engine + launcher -> dist/
  src/Engine/
    base/winutil-26.08.19.ps1 upstream WinUtil, never edited by hand
    winforge/*.ps1            WinForge functions (profile, rules, server, repair, UI helpers)
    config/*.ps1|*.json       tweaks, features, presets, games, rules
    xaml/*.xml                nav button, Jogos tab, Diagnóstico tab, Servidor tab
    build.ps1                 anchored text injection -> dist/engine/WinForge.ps1 (+ SelfTest)
  src/Launcher/               C# .NET Framework 4.8 WPF project (WinForge.csproj)
  docs/
    superpowers/specs/        this spec
    auditoria.md              safety classification of every tweak
    changelog.md
  .github/workflows/build.yml build + release on tag
```

## 4. Launcher (`src/Launcher`)

- Target `net48`, `UseWPF`, SDK-style csproj built by the .NET 8 SDK. Runs on Windows 10/11 and Server 2016+ without installing a runtime.
- `app.manifest` with `requestedExecutionLevel level="requireAdministrator"`, DPI awareness, Windows 10 compatibility GUIDs.
- Assembly metadata: product WinForge, version from `Directory.Build.props`, icon `winforge.ico` generated from the SVG logo.
- Embedded resource: `WinForge.ps1` (engine) plus `engine.sha256`.
- Startup sequence:
  1. Show a small splash window (logo, version, "Iniciando o motor...").
  2. Extract the engine to `%LocalAppData%\WinForge\engine\<version>\WinForge.ps1` if missing or if the SHA-256 differs.
  3. Locate `powershell.exe` (Windows PowerShell 5.1; `pwsh` optional if present and `-UsePwsh` passed).
  4. Start `powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File <engine> <args>`, passing through all launcher arguments (`-RestorePoint`, `-NoRestorePoint`, `-Preset`, `-Config`, `-SelfTest`, `-Console`).
  5. `-Console` keeps the PowerShell console visible (troubleshooting). Default hides it; engine output goes to the log file.
  6. Close the splash when the engine reports readiness (named event `WinForge.Ready`) or after 60 s; show an error dialog if the engine process exits non-zero before readiness.
- Exit code of the launcher = exit code of the engine.

## 5. Engine changes

### 5.1 Rebrand
- New logo: original SVG path (anvil + spark forming a "W"), rendered by `Invoke-WinUtilAssets -Type logo` (path data replaced) and exported to `.ico` for the launcher.
- Remove: Sponsors menu, CTT PowerShell profile buttons, `christitus.com` links (the "(?)" link glyph is dropped when no `link`), `winutil.christitus.com` documentation menu, ASCII banner, "WinUtil"/"Winutil" strings in UI messages and dialog titles.
- Keep internal function names (`*-WinUtil*`) unchanged; new code uses `*-WinForge*` and the runspace import filter is widened to `winutil|winforge|WPF`.
- Window title: `WinForge <version> - <OS> <edition>`.

### 5.2 System profile (`Get-WinForgeSystemProfile`)
Returns `$sync.Profile`, computed once at startup (runspace) and refreshable from the Diagnóstico tab:

| Area | Fields |
|------|--------|
| OS | build, display version, edition, `IsServer`, `IsWin11`, install type, uptime, activation state |
| Roles (Server) | installed Windows features: `Web-Server` (IIS), `AD-Domain-Services` + DC state, `Hyper-V`, `DHCP`, `DNS`, `FS-FileServer`, `Remote-Desktop-Services` |
| Machine | manufacturer/model, `IsVirtual` (hypervisor vendor), `IsLaptop` (battery/chassis), Secure Boot, TPM version, BitLocker state |
| CPU | name, vendor, physical/logical cores, hybrid (P/E) flag, max clock, virtualization enabled |
| RAM | total GB, speed, channels/slots used, page file size, ECC |
| GPU | one entry per adapter: vendor, model, VRAM, driver version/date, WHQL; NVIDIA: latest version from the official NVIDIA driver-lookup API (with timeout and offline fallback) |
| Storage | per volume: letter, size, free %, media (NVMe/SSD/HDD), SMART health, TRIM enabled |
| Network | active adapter, link speed, Wi-Fi vs Ethernet, DNS servers, IPv6 state, RSS/offload |
| Power | active scheme, on battery, Ultimate Performance available |
| State | VBS/HVCI on, HAGS on, Game Mode, hibernation, fast startup, SysMain, WSearch, Windows Update policy |
| Drivers | table of `Win32_PnPSignedDriver` (device, vendor, version, date, signer) filtered to display, network, audio, chipset, storage |

Driver freshness: NVIDIA compared to API; others flagged `verificar` when older than 180 days; each row carries the official vendor download URL for the detected vendor (NVIDIA, AMD, Intel, Realtek, ASUS, MSI, Gigabyte, ASRock, Dell, Lenovo, HP). A "Buscar drivers no Windows Update" button runs the WU COM search for optional driver updates and lists them (install stays a user action via Settings).

### 5.3 Rules engine (`config/rules.json`, `Invoke-WinForgeRules`)
Each rule: `{ "id", "when": "<PowerShell expression over $p>", "recommend": [keys], "avoid": [keys], "reason": "<pt-BR text>" }`. Evaluated after the profile exists; produces `$sync.Recommended[key] = reason` and `$sync.Avoid[key] = reason`. Initial rule set (extendable):

- SSD-only system → recommend Prefetch/Superfetch off, NTFS last access off; HDD present → avoid Prefetch off.
- Laptop or on battery → avoid CPU 100% power tweak and Ultimate Performance; recommend USB suspend kept.
- RAM ≤ 8 GB → recommend safe services, ads off, hibernation off; avoid SysMain off.
- Virtual machine → avoid bcdedit timer, HAGS, GPU tweaks, VBS changes.
- NVIDIA/AMD/Intel GPU present → recommend that vendor's telemetry off; Game DVR off on any dedicated GPU desktop.
- Windows 11 → recommend End task on taskbar; Widgets removal when no Widgets use.
- Server → recommend Server category items; avoid consumer items (Game DVR, Xbox, AppX removals).
- IIS role → recommend IIS pool tuning; AD DC → recommend AD checks; DC on same disk as OS → warn.
- Driver older than 180 days or NVIDIA behind → recommend "Atualizar driver <device>" entry in Diagnóstico.
- VBS on + dedicated GPU + no VM → informational (never auto-recommend disabling security).

### 5.4 UI
- `Invoke-WPFUIElements` wraps each checkbox/toggle row in a `Border`: green (`#2E7D32`, 1.5 px, radius 4) when recommended, orange (`#EF6C00`) when discouraged; tooltip prefixed `✔ Recomendado: <motivo>` / `⚠ Não recomendado neste sistema: <motivo>` before the item description.
- "Marcar recomendados" button on Tweaks, Jogos and Servidor tabs selects every recommended key of that tab.
- New tab **Diagnóstico** (Alt+D): profile cards (OS, CPU, RAM, GPU, discos, rede, energia), driver table with status column and links, recommendations list with "Marcar todos", "Atualizar diagnóstico" button, "Exportar relatório" (HTML file).
- New tab **Servidor** shown only when `IsServer`; Jogos, AppX and Win11 Creator tabs hidden on Server.
- Compatibility fields extended: `os` (`win10|win11`), `platform` (`client|server`), `gpu`, `role` (`iis|ad|hyperv`).

### 5.5 Tweak audit (`docs/auditoria.md`)
Every entry (WinUtil + Windows Boost) classified:
- **Seguro**: reversible, no security or stability cost; may appear in presets.
- **Cuidado**: real trade-off; lives only in the "Avançado (CUIDADO)" category, never in presets, description states the cost.
- **Removido**: net-negative. Initial list: SmartScreen off, download zone-info off, aggressive services bundle (replaced by five separate Cuidado items: Spooler, Bluetooth, RDP, Windows Hello, teclado touch), WPFTweaksRemoveEdge on Server, Teredo/IPv6 disable moved to Cuidado, UTC time moved to Cuidado, "Restore Point - Create" stays.
- Rules engine can additionally mark Cuidado items as `avoid` for the current hardware.

### 5.6 Windows Server
Category **Servidor** (platform=server): Server Manager not at logon, IE Enhanced Security off (admins), Shutdown Event Tracker off, telemetry minimum, Delivery Optimization off, High Performance plan, hibernation off, NTP source check, RDP NLA on + idle timeout, Windows Update security-only profile pointer, SMB tuning (SMB1 removed, signing state shown), TCP autotuning normal, Defender exclusions review (informational).
Category **IIS** (role=iis): app pools `startMode=AlwaysRunning`, `idleTimeout=0`, `periodicRestart.time=0` with memory-based recycling, site `preloadEnabled`, static + dynamic compression, output caching for static, `maxConcurrentRequestsPerCPU`, request queue limit, log folder on non-OS drive check. All with Undo (previous values captured to a JSON file before change).
Category **Active Directory** (role=ad, DC only): buttons `dcdiag /q`, `repadmin /replsummary`, DNS scavenging status, NTDS/SYSVOL location check, time hierarchy check (`w32tm /query /status`).

### 5.7 Component repair (Config tab, "Reparo de componentes")
Buttons, each with a log: WMI repository (`winmgmt /verifyrepository` → `/salvagerepository`), Store/AppX re-register, WinGet repair (existing) + App Installer, .NET Framework 3.5 (DISM) and 4.8 check, VC++ 2005–2022 x86/x64 (winget), DirectX runtime (web installer), PowerShell 7 (winget), `chkdsk /scan` now + `/f` scheduled, SMART report, Windows Memory Diagnostic schedule, TPM/Secure Boot/BitLocker status, `sfc`+`DISM` (existing), Windows Update reset (existing), network reset (existing).

## 6. Build, test, release

- `src/Engine/build.ps1`: anchored injection (fails on missing/ambiguous anchor), output `dist/engine/WinForge.ps1` UTF-8 BOM, parse check, then copies into `src/Launcher/Resources/`.
- `WinForge.ps1 -SelfTest`: preset keys, registry/service entries, scripts parse, XAML load, every tab mounted headless, hidden entries not created, rules evaluated on the real profile and on simulated profiles (`WINFORGE_SIMULATE=win10|server-iis|laptop|vm`), report counts, exit code = error count.
- `build.cmd`: engine build + `dotnet build -c Release` + copy `WinForge.exe` to `dist/`.
- GitHub Actions: on push/PR run engine SelfTest (`windows-latest`) and launcher build; on tag `v*` create release with `WinForge.exe` and `WinForge-<version>.zip` (exe + README + NOTICE).
- Version single source: `version.json` read by build.ps1 and Directory.Build.props.

## 7. Risks

- Antivirus heuristics on a launcher that extracts and runs PowerShell: mitigated by signed-looking metadata, no obfuscation, engine extracted to user profile with a fixed name; code signing certificate is a later step.
- NVIDIA API shape changes: wrapped in try/catch with 5 s timeout; UI shows "não foi possível consultar".
- IIS changes on production servers: every IIS tweak captures previous values and has Undo; none is in a preset.
- WinUtil upstream updates: base file replaced wholesale; anchors verified by build.
