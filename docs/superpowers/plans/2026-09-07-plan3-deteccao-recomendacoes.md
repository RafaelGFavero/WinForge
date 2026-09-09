# WinForge Plan 3 — Detecção de hardware/drivers, regras de recomendação e aba Diagnóstico Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WinForge builds a complete system profile (OS, roles, machine type, CPU, RAM, GPUs with NVIDIA latest-driver lookup, storage, network, power, security state, driver inventory), evaluates a data-driven rule set into per-item recommendations, shows them in the UI (green outline = recomendado, orange = não recomendado, reason on hover, "Marcar recomendados" buttons) and adds a **Diagnóstico** tab (profile cards, driver table with vendor links and Windows Update driver search, recommendation list, HTML report export).

**Architecture:** Profile = `Get-WinForgeSystemProfile` (pure data, `[ordered]` hashtable, cached in `$sync.Profile`), computed in a runspace after the window renders and synchronously in SelfTest. Rules = `src/Engine/config/wf-rules.ps1` data (`$sync.WinForgeRules`: id, when-expression over `$p`, recommend[], avoid[], reason) evaluated by `Invoke-WinForgeRules` into `$sync.Recommended` / `$sync.Discouraged` (key → reason). UI visuals = rows wrapped in a `Border` at creation (`Invoke-WPFUIElements` injection) and colored by `Update-WinForgeRecommendationVisuals` (idempotent, runs on tab init and when the profile arrives). Diagnóstico tab = XAML piece + `Initialize-WinUtilTabContent` case + functions that fill it from `$sync.Profile`.

**Tech Stack:** Windows PowerShell 5.1, CIM/WMI, `Microsoft.Update.Session` COM, NVIDIA lookup endpoints (`nvidia.com/Download/API/lookupValueSearch.aspx`, `gfwsl.geforce.com/.../AjaxDriverService.php?func=DriverManualLookup`), WPF (Border, DataGrid), existing build pipeline + SelfTest.

**Spec:** `docs/superpowers/specs/2026-09-07-winforge-design.md` §5.2, §5.3, §5.4, §6.

## Global Constraints

- Never edit `src/Engine/base/winutil-26.08.19.ps1` or `dist/`. All edits via `src/Engine/{winforge,config,xaml}` and anchored injections in `src/Engine/build.ps1` (build fails on missing/ambiguous anchor; anchors use pre-rename `WinUtil` names when they come from the base).
- New functions named `*-WinForge*`; new `.ps1` files UTF-8 with BOM + CRLF; pt-BR user text; brand/mojibake/old-brand 0; SelfTest 0 errors (existing count locks 42/83/84 and audit 130/27/2 stay).
- Network calls: 5 s timeout, `try/catch`, never block the UI thread; offline → fields `$null` + `Status = 'indisponível'`. No driver downloads/installs.
- Rules may only recommend keys whose `risk` is `seguro` (SelfTest asserts); `avoid` may target any key. Every key named in a rule must exist (typo guard in SelfTest).
- Version → `1.2.0` in the last task. Conventional Commits + trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Branch `feat/plan3-diagnostico` from `main`; finish with push + PR.

## File map

| Path | Responsibility |
|---|---|
| `src/Engine/winforge/wf-profile.ps1` | `Get-WinForgeSystemProfile`, `Get-WinForgeDriverInventory`, `Get-WinForgeSimulatedProfile`, `ConvertTo-WinForgeNvidiaVersion` |
| `src/Engine/winforge/wf-drivers.ps1` | `Get-WinForgeNvidiaLatestDriver`, `Get-WinForgeVendorDriverUrl`, `Search-WinForgeWindowsUpdateDrivers` |
| `src/Engine/config/wf-rules.ps1` | `$sync.WinForgeRules` data |
| `src/Engine/winforge/wf-rules.ps1` | `Invoke-WinForgeRules`, `Select-WinForgeRecommended` |
| `src/Engine/winforge/wf-recoui.ps1` | `Update-WinForgeRecommendationVisuals`, `Start-WinForgeProfileJob` |
| `src/Engine/winforge/wf-diag.ps1` | Diagnóstico tab: `Initialize-WinForgeDiagnosticsTab`, `Update-WinForgeDiagnosticsTab`, `Export-WinForgeDiagnosticsReport`, `Invoke-WinForgeDriverUpdateSearch` |
| `src/Engine/xaml/wf-xaml-diag-nav.xml`, `src/Engine/xaml/wf-xaml-diag-tab.xml` | nav button `WPFTab8BT`, TabItem `WPFTab8` (Header `Diagnostico`) |
| `src/Engine/build.ps1` | inserts, anchors (row Border wrap, search unwrap, tab init, tab switch, Alt+D, profile job start), SelfTest additions |

---

### Task 1: System profile (`wf-profile.ps1`) with SelfTest summary and simulations

**Files:** Create `src/Engine/winforge/wf-profile.ps1`; Modify `src/Engine/build.ps1` (insert before `#region ===== WinForge - logo =====`; SelfTest block).

**Interfaces (produces):**
- `Get-WinForgeSystemProfile [-SkipNetwork]` → `[ordered]@{ OS; Roles; Machine; CPU; RAM; GPU (array); Storage (array); Network; Power; State; Drivers (array); GeneratedAt }` — every leaf is a plain value/array (no CIM objects) so it can be serialized with `ConvertTo-Json -Depth 6`.
- `Get-WinForgeSimulatedProfile -Name laptop|vm|server-iis|hdd|win10` → same shape, deterministic fixtures (used by SelfTest and rule tests).
- `ConvertTo-WinForgeNvidiaVersion '32.0.16.1656'` → `'616.56'` (take last two groups `16.1656` → `161656` → last 5 digits → `616.56`).

- [ ] **Step 1: Write `wf-profile.ps1`** with these fields (all wrapped in `try/catch` per area; a failing area yields `$null` fields + `Errors += "<area>: <msg>"`):

```powershell
#region ===== WinForge - perfil do sistema =====
function ConvertTo-WinForgeNvidiaVersion { param([string]$DriverVersion)
    if ($DriverVersion -match '^\d+\.\d+\.(\d+)\.(\d+)$') { $digits = ($Matches[1] + $Matches[2]); if ($digits.Length -ge 5) { $d = $digits.Substring($digits.Length - 5); return ('{0}.{1}' -f $d.Substring(0,3), $d.Substring(3)) } }
    return $null }

function Get-WinForgeDriverInventory {
    # Win32_PnPSignedDriver filtrado: DISPLAY, NET, MEDIA, HDC, SCSIADAPTER, SYSTEM (chipset), USB, BLUETOOTH; ignora DriverProviderName 'Microsoft'
    $classes = 'DISPLAY','NET','MEDIA','HDC','SCSIADAPTER','SYSTEM','USB','BLUETOOTH'
    $cutoff = (Get-Date).AddDays(-180)
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.DeviceClass -in $classes -and $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' -and $_.DeviceName } |
      Sort-Object DeviceClass, DeviceName -Unique | ForEach-Object {
        [pscustomobject]@{ Device = $_.DeviceName; Class = $_.DeviceClass; Version = $_.DriverVersion; Date = $(if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '' }); Provider = $_.DriverProviderName; Signed = [bool]$_.IsSigned; Signer = $_.Signer
                          Vendor = (Get-WinForgeVendorKey $_.DriverProviderName $_.DeviceName); Old = $(if ($_.DriverDate) { $_.DriverDate -lt $cutoff } else { $false }); Status = 'ok'; Latest = $null; Url = $null } } }

function Get-WinForgeVendorKey { param([string]$Provider, [string]$Device)
    $t = "$Provider $Device"
    switch -Regex ($t) { 'NVIDIA' { 'nvidia'; break } 'AMD|Radeon|ATI ' { 'amd'; break } 'Intel' { 'intel'; break } 'Realtek' { 'realtek'; break } 'Qualcomm|Atheros' { 'qualcomm'; break } 'MediaTek' { 'mediatek'; break } 'Broadcom' { 'broadcom'; break } 'Logitech' { 'logitech'; break } default { 'other' } } }

function Get-WinForgeSystemProfile { param([switch]$SkipNetwork)
    $p = [ordered]@{ GeneratedAt = (Get-Date).ToString('s'); Errors = @() }
    # OS
    try { $os = Get-CimInstance Win32_OperatingSystem; $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
      $p.OS = [ordered]@{ Caption = $os.Caption; Build = [int][Environment]::OSVersion.Version.Build; DisplayVersion = [string]$cv.DisplayVersion; IsWin11 = ([Environment]::OSVersion.Version.Build -ge 22000); IsServer = ($os.ProductType -ne 1); ProductType = [int]$os.ProductType; InstallDate = $os.InstallDate.ToString('yyyy-MM-dd'); UptimeHours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1); Architecture = $os.OSArchitecture } } catch { $p.Errors += "OS: $($_.Exception.Message)" }
    # Roles (Server only; Get-WindowsFeature exists only on Server)
    $p.Roles = [ordered]@{ IIS = $false; AD = $false; HyperV = $false; DNS = $false; DHCP = $false; FileServer = $false; RDS = $false }
    if ($p.OS.IsServer -and (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) { try { $f = Get-WindowsFeature | Where-Object Installed | Select-Object -ExpandProperty Name; $p.Roles.IIS = 'Web-Server' -in $f; $p.Roles.AD = 'AD-Domain-Services' -in $f; $p.Roles.HyperV = 'Hyper-V' -in $f; $p.Roles.DNS = 'DNS' -in $f; $p.Roles.DHCP = 'DHCP' -in $f; $p.Roles.FileServer = 'FS-FileServer' -in $f; $p.Roles.RDS = 'RDS-RD-Server' -in $f } catch { $p.Errors += "Roles: $($_.Exception.Message)" } }
    # Machine
    try { $cs = Get-CimInstance Win32_ComputerSystem; $enc = Get-CimInstance Win32_SystemEnclosure; $chassis = @($enc.ChassisTypes); $laptopTypes = 8,9,10,11,12,14,18,21,30,31,32
      $p.Machine = [ordered]@{ Manufacturer = $cs.Manufacturer; Model = $cs.Model; IsVirtual = [bool]$cs.HypervisorPresent -or ($cs.Model -match 'Virtual|VMware|VirtualBox|KVM|QEMU|Hyper-V'); IsLaptop = (($chassis | Where-Object { $_ -in $laptopTypes }).Count -gt 0) -or [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue); ChassisTypes = $chassis; SecureBoot = $null; TpmVersion = $null; BitLocker = $null }
      try { $p.Machine.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $p.Machine.SecureBoot = $null }
      try { $tpm = Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop; if ($tpm) { $p.Machine.TpmVersion = ($tpm.SpecVersion -split ',')[0].Trim() } } catch { }
      try { $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; $p.Machine.BitLocker = [string]$bl.ProtectionStatus } catch { }
    } catch { $p.Errors += "Machine: $($_.Exception.Message)" }
    # CPU
    try { $c = Get-CimInstance Win32_Processor | Select-Object -First 1; $vendor = switch -Regex ($c.Manufacturer) { 'Intel' { 'intel' } 'AMD' { 'amd' } default { 'other' } }
      $p.CPU = [ordered]@{ Name = $c.Name.Trim(); Vendor = $vendor; Cores = [int]$c.NumberOfCores; Logical = [int]$c.NumberOfLogicalProcessors; MaxMHz = [int]$c.MaxClockSpeed; Hybrid = ($vendor -eq 'intel' -and $c.Name -match '1[2-9]\d{3}|Core Ultra'); VirtualizationEnabled = [bool]$c.VirtualizationFirmwareEnabled } } catch { $p.Errors += "CPU: $($_.Exception.Message)" }
    # RAM
    try { $m = @(Get-CimInstance Win32_PhysicalMemory); $osm = Get-CimInstance Win32_OperatingSystem
      $p.RAM = [ordered]@{ TotalGB = [math]::Round(($m | Measure-Object Capacity -Sum).Sum / 1GB, 1); Modules = $m.Count; SpeedMHz = [int]($m | Select-Object -First 1).ConfiguredClockSpeed; FreeGB = [math]::Round($osm.FreePhysicalMemory / 1MB, 1); PageFileGB = [math]::Round(((Get-CimInstance Win32_PageFileUsage | Measure-Object AllocatedBaseSize -Sum).Sum) / 1KB, 1) } } catch { $p.Errors += "RAM: $($_.Exception.Message)" }
    # GPU
    try { $p.GPU = @(Get-CimInstance Win32_VideoController | Where-Object Name | ForEach-Object { $n = $_.Name; $v = Get-WinForgeVendorKey $_.AdapterCompatibility $n
        [ordered]@{ Name = $n; Vendor = $v; VRAMGB = $(if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1GB, 1) } else { $null }); DriverVersion = $_.DriverVersion; DriverDate = $(if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '' }); MarketingVersion = $(if ($v -eq 'nvidia') { ConvertTo-WinForgeNvidiaVersion $_.DriverVersion } else { $null }); Latest = $null; LatestDate = $null; LatestStatus = 'não consultado' } }) } catch { $p.Errors += "GPU: $($_.Exception.Message)" }
    # Storage
    try { $disks = @(Get-PhysicalDisk); $p.Storage = [ordered]@{ Disks = @($disks | ForEach-Object { [ordered]@{ Name = $_.FriendlyName; Media = [string]$_.MediaType; Bus = [string]$_.BusType; Health = [string]$_.HealthStatus; SizeGB = [math]::Round($_.Size / 1GB) } }); HasHDD = (($disks | Where-Object MediaType -eq 'HDD').Count -gt 0); HasSSD = (($disks | Where-Object MediaType -in 'SSD' ).Count -gt 0); SystemDriveMedia = $null
        Volumes = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object { [ordered]@{ Letter = [string]$_.DriveLetter; FS = $_.FileSystem; SizeGB = [math]::Round($_.Size / 1GB); FreePct = $(if ($_.Size) { [math]::Round($_.SizeRemaining / $_.Size * 100) } else { 0 }) } }) }
      try { $sysDisk = Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') | Get-Disk | Get-PhysicalDisk; $p.Storage.SystemDriveMedia = [string]$sysDisk.MediaType } catch { }
    } catch { $p.Errors += "Storage: $($_.Exception.Message)" }
    # Network
    try { $a = Get-NetAdapter | Where-Object Status -eq 'Up' | Sort-Object -Property @{Expression={ $_.MediaType -eq '802.3' }; Descending=$true}, LinkSpeed -Descending | Select-Object -First 1
      $dns = @((Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | Select-Object -First 1).ServerAddresses)
      $p.Network = [ordered]@{ Adapter = $a.InterfaceDescription; Name = $a.Name; LinkSpeed = [string]$a.LinkSpeed; IsWifi = ($a.MediaType -match '802\.11|Native 802.11|Wireless'); Dns = $dns; IPv6Enabled = [bool](Get-NetAdapterBinding -Name $a.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue).Enabled } } catch { $p.Errors += "Network: $($_.Exception.Message)" }
    # Power
    try { $scheme = (powercfg /getactivescheme) -replace '.*:\s*', ''; $p.Power = [ordered]@{ ActiveScheme = $scheme.Trim(); OnBattery = $(try { (Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1).BatteryStatus -eq 1 } catch { $false }); HibernationEnabled = [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HibernateEnabled } } catch { $p.Errors += "Power: $($_.Exception.Message)" }
    # State (registry/services)
    try { $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
      $p.State = [ordered]@{ VBS = $(if ($dg) { $dg.VirtualizationBasedSecurityStatus -eq 2 } else { $null }); HAGS = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue).HwSchMode -eq 2); GameMode = ((Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue).AutoGameModeEnabled -ne 0); SysMain = [string](Get-Service SysMain -ErrorAction SilentlyContinue).StartType; WSearch = [string](Get-Service WSearch -ErrorAction SilentlyContinue).StartType; FastStartup = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled -ne 0) } } catch { $p.Errors += "State: $($_.Exception.Message)" }
    # Drivers
    try { $p.Drivers = @(Get-WinForgeDriverInventory) } catch { $p.Errors += "Drivers: $($_.Exception.Message)"; $p.Drivers = @() }
    if (-not $SkipNetwork) { try { Update-WinForgeProfileDriverStatus -Profile $p } catch { $p.Errors += "DriverLookup: $($_.Exception.Message)" } }
    return $p }

function Get-WinForgeSimulatedProfile { param([Parameter(Mandatory)][ValidateSet('laptop','vm','server-iis','hdd','win10')][string]$Name)
    $base = Get-WinForgeSystemProfile -SkipNetwork
    switch ($Name) {
      'laptop'     { $base.Machine.IsLaptop = $true; $base.Power.OnBattery = $true }
      'vm'         { $base.Machine.IsVirtual = $true; $base.GPU = @([ordered]@{ Name='Microsoft Basic Display'; Vendor='other'; VRAMGB=$null; DriverVersion='10.0'; DriverDate=''; MarketingVersion=$null; Latest=$null; LatestDate=$null; LatestStatus='n/a' }) }
      'server-iis' { $base.OS.IsServer = $true; $base.OS.ProductType = 3; $base.Roles.IIS = $true }
      'hdd'        { $base.Storage.HasHDD = $true; $base.Storage.HasSSD = $false; $base.Storage.SystemDriveMedia = 'HDD' }
      'win10'      { $base.OS.IsWin11 = $false; $base.OS.Build = 19045 }
    }
    $base.Simulated = $Name; return $base }
#endregion
```
`Update-WinForgeProfileDriverStatus` is defined in Task 2; in this task add a stub in `wf-profile.ps1`: `function Update-WinForgeProfileDriverStatus { param($Profile) }` that Task 2 replaces (Task 2 removes the stub).

- [ ] **Step 2: SelfTest** — in `build.ps1` SelfTest block (after the audit checks) add:
```powershell
    $wbProfile = Get-WinForgeSystemProfile -SkipNetwork
    foreach ($area in 'OS','Machine','CPU','RAM','GPU','Storage','Network','Power','State','Drivers') { if ($null -eq $wbProfile[$area]) { Write-Host "  [ERRO] perfil sem área $area" -ForegroundColor Red; $wbErrors++ } }
    if ($wbProfile.Errors.Count) { Write-Host "  Perfil: avisos -> $($wbProfile.Errors -join '; ')" }
    $null = $wbProfile | ConvertTo-Json -Depth 6 -Compress   # serializável
    Write-Host "  Perfil: $($wbProfile.OS.Caption) | $($wbProfile.CPU.Name) | RAM $($wbProfile.RAM.TotalGB) GB | GPU $(@($wbProfile.GPU | ForEach-Object { $_.Name }) -join ', ') | SSD=$($wbProfile.Storage.HasSSD) HDD=$($wbProfile.Storage.HasHDD) | laptop=$($wbProfile.Machine.IsLaptop) vm=$($wbProfile.Machine.IsVirtual) | drivers=$($wbProfile.Drivers.Count)"
    foreach ($sim in 'laptop','vm','server-iis','hdd','win10') { $sp = Get-WinForgeSimulatedProfile -Name $sim; if ($sp.Simulated -ne $sim) { Write-Host "  [ERRO] simulação $sim" -ForegroundColor Red; $wbErrors++ } }
    if ((ConvertTo-WinForgeNvidiaVersion '32.0.16.1656') -ne '616.56' -or (ConvertTo-WinForgeNvidiaVersion '32.0.15.6636') -ne '566.36') { Write-Host "  [ERRO] ConvertTo-WinForgeNvidiaVersion" -ForegroundColor Red; $wbErrors++ }
```
Non-admin note: `Confirm-SecureBootUEFI`/TPM/BitLocker return `$null` unelevated — fine (SelfTest runs unelevated).

- [ ] **Step 3: Build + SelfTest** (0 errors; profile line printed). Commit `feat(engine): system profile with simulations and NVIDIA version mapping`.

---

### Task 2: Driver lookups (`wf-drivers.ps1`): NVIDIA latest, vendor URLs, Windows Update search

**Files:** Create `src/Engine/winforge/wf-drivers.ps1`; Modify `wf-profile.ps1` (remove stub), `build.ps1` (insert; SelfTest).

**Interfaces (produces):**
- `Get-WinForgeNvidiaLatestDriver -GpuName 'NVIDIA GeForce RTX 3070' [-IsWin11 $true] [-TimeoutSec 5]` → `@{ Version='616.64'; ReleaseDate='2026-09-03'; Url=...; Status='ok'|'indisponível'|'não encontrado' }`. Cached 24 h in `%LocalAppData%\WinForge\cache\nvidia-<psid>-<pfid>.json`.
- `Get-WinForgeVendorDriverUrl -Vendor nvidia|amd|intel|realtek|... -Profile $p` → URL string (manufacturer pages: NVIDIA `https://www.nvidia.com/pt-br/drivers/`, AMD `https://www.amd.com/pt/support/download/drivers.html`, Intel `https://www.intel.com.br/content/www/br/pt/download-center/home.html`, Realtek `https://www.realtek.com/Download/List?cate_id=584`, Qualcomm/MediaTek/Broadcom → OEM page by `Machine.Manufacturer` (ASUS `https://www.asus.com/support/download-center/`, MSI `https://www.msi.com/support/download`, Gigabyte `https://www.gigabyte.com/Support`, ASRock `https://www.asrock.com/support/index.asp`, Dell `https://www.dell.com/support/home/`, Lenovo `https://support.lenovo.com/`, HP `https://support.hp.com/drivers`, Acer `https://www.acer.com/support`, Samsung `https://www.samsung.com/br/support/`), Logitech `https://support.logi.com/`, other → OEM page or `$null`.
- `Update-WinForgeProfileDriverStatus -Profile $p` — fills `GPU[].Latest/LatestDate/LatestStatus` for NVIDIA (compares `MarketingVersion` vs `Latest` as `[version]`), sets `Drivers[].Url` via vendor map, `Drivers[].Status` = `'atualizar'` (NVIDIA behind), `'verificar'` (Old = true), `'ok'`.
- `Search-WinForgeWindowsUpdateDrivers` → array of `@{ Title; Driver; Version; Date; KB }` from `Microsoft.Update.Session` search `"IsInstalled=0 and Type='Driver'"` (may take 10–60 s; caller runs it in a runspace).

- [ ] **Step 1: NVIDIA lookup** — exact-name matching (series list `TypeID=2&ParentID=1`; pick the series whose name is contained in the GPU name after normalizing `NVIDIA `/`GeForce ` prefixes — e.g. GPU `NVIDIA GeForce RTX 3070` → series candidates whose names match `RTX 30 Series` (not `(Notebooks)` unless `$Profile.Machine.IsLaptop`); product list `TypeID=3&ParentID=<psid>` → exact `GeForce RTX 3070`); query `https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=<psid>&pfid=<pfid>&osID=<135 if Win11 else 57>&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1`; read `IDS[0].downloadInfo.Version`, `ReleaseDateTime`, `DownloadURL`; `Success` `"3"` = found. Verified today: psid 120 / pfid 933 → 616.64 (2026-09-03).
- [ ] **Step 2: SelfTest** — offline-safe: `Get-WinForgeVendorDriverUrl -Vendor nvidia` returns a URL; `Update-WinForgeProfileDriverStatus` on the simulated `vm` profile leaves GPU `LatestStatus` unchanged (no NVIDIA); if `$env:WINFORGE_SELFTEST_NETWORK -eq '1'` also call `Get-WinForgeNvidiaLatestDriver -GpuName 'NVIDIA GeForce RTX 3070'` and assert `Status -eq 'ok'` and `Version -match '^\d{3}\.\d{2}$'` (controller runs this once).
- [ ] **Step 3: Build + SelfTest** (both modes). Commit `feat(engine): NVIDIA latest-driver lookup, vendor driver URLs, Windows Update driver search`.

---

### Task 3: Rules engine (`config/wf-rules.ps1` + `winforge/wf-rules.ps1`) with SelfTest on simulated profiles

**Files:** Create both; Modify `build.ps1` (inserts; call `Invoke-WinForgeRules` after the profile exists; SelfTest).

**Interfaces:**
- Rule shape: `@{ Id='ssd-only'; When='$p.Storage.HasSSD -and -not $p.Storage.HasHDD'; Recommend=@('WPFTweaksWBNtfsLastAccess'); Avoid=@(); Reason='SSD sem HDD: ...' }`.
- `Invoke-WinForgeRules -Profile $p` → sets `$sync.Recommended` (ordered hashtable key→reason, first rule wins) and `$sync.Discouraged`; returns `@{ Recommended; Discouraged; Fired = @(ids) }`. `Avoid` overrides `Recommend` for the same key.
- `Select-WinForgeRecommended -Tab Tweaks|Jogos|All` → checks every recommended checkbox present in `$sync` for that tab (uses `Invoke-WPFSelectedCheckboxesUpdate` semantics by setting `IsChecked = $true`).

- [ ] **Step 1: Initial rule set** (`$sync.WinForgeRules = @(...)`, all reasons pt-BR):
  1. `base-privacy` — When `$true` → Recommend `WPFTweaksActivity, WPFTweaksConsumerFeatures, WPFTweaksTelemetry, WPFTweaksDeliveryOptimization, WPFTweaksWBAds, WPFTweaksWBSearchSuggestions, WPFTweaksWBServicesSafe, WPFTweaksRestorePoint` — "Base segura para qualquer PC: privacidade, sem anúncios, serviços dispensáveis e ponto de restauração".
  2. `ssd-only` — `$p.Storage.HasSSD -and -not $p.Storage.HasHDD` → Recommend `WPFTweaksWBNtfsLastAccess` — "Só SSD: menos escrita de metadados".
  3. `hdd-present` — `$p.Storage.HasHDD` → Avoid `WPFTweaksWBPrefetch, WPFTweaksWBIndexing` — "Há HDD: Prefetch/Superfetch e indexação ajudam discos mecânicos".
  4. `laptop` — `$p.Machine.IsLaptop` → Avoid `WPFTweaksWBPowerSettings, WPFTweaksHiber, WPFTweaksWBTimerBcdedit` — "Notebook: CPU a 100% e sem hibernação gastam bateria e esquentam".
  5. `desktop` — `-not $p.Machine.IsLaptop -and -not $p.Machine.IsVirtual` → Recommend `WPFTweaksHiber, WPFTweaksWBPowerSettings` — "Desktop na tomada: hibernação inútil; energia sem suspensão USB/throttle reduz latência".
  6. `low-ram` — `$p.RAM.TotalGB -le 8` → Recommend `WPFTweaksWBServicesSafe, WPFTweaksDisableBGapps`?? — NO: `WPFTweaksDisableBGapps` is Cuidado; use Recommend `WPFTweaksWBServicesSafe, WPFTweaksWBAds, WPFTweaksDisplay`; Avoid `WPFTweaksWBPrefetch` — "8 GB ou menos: cada serviço conta; Superfetch ajuda".
  7. `vm` — `$p.Machine.IsVirtual` → Avoid `WPFTweaksWBTimerBcdedit, WPFToggleWBHAGS, WPFTweaksWBVBS, WPFTweaksWBHypervisorOff, WPFTweaksWBPowerSettings` — "Máquina virtual: timer, HAGS, VBS e energia são controlados pelo host".
  8. `nvidia` — `@($p.GPU | Where-Object Vendor -eq 'nvidia').Count -gt 0` → Recommend `WPFTweaksWBNvidiaTelemetry, WPFTweaksWBGameDVR` — "GPU NVIDIA: telemetria da NVIDIA e Game DVR gastam recursos".
  9. `amd` — `@($p.GPU | Where-Object Vendor -eq 'amd').Count -gt 0` → Recommend `WPFTweaksWBAmdTelemetry, WPFTweaksWBGameDVR`.
  10. `dedicated-gpu-desktop` — `(@($p.GPU | Where-Object { $_.Vendor -in 'nvidia','amd' }).Count -gt 0) -and -not $p.Machine.IsLaptop` → Recommend `WPFTweaksWBMMCSSGames, WPFTweaksWBWin32PrioritySeparation` — "PC de jogo: prioridade de mídia/primeiro plano".
  11. `win11` — `$p.OS.IsWin11` → Recommend `WPFTweaksEndTaskOnTaskbar` — "Windows 11: finalizar tarefa pela barra".
  12. `server` — `$p.OS.IsServer` → Avoid `WPFTweaksWBGameDVR, WPFTweaksWBXboxServices, WPFTweaksWBMMCSSGames, WPFTweaksWBWin32PrioritySeparation, WPFTweaksWidget, WPFTweaksWBAds` — "Servidor: itens de consumidor/jogos não se aplicam".
  13. `vbs-on-gaming` — `$p.State.VBS -eq $true -and (@($p.GPU | Where-Object { $_.Vendor -in 'nvidia','amd' }).Count -gt 0) -and -not $p.Machine.IsVirtual` → Avoid `@()` Recommend `@()`; `Info='VBS/Isolamento de Núcleo ativo: custa 5-15% de FPS em alguns jogos; desligar reduz a segurança (item em Avançado (CUIDADO))'` — informational (Info rules go to `$sync.RuleInfos` list, shown in Diagnóstico).
  14. `nvidia-driver-behind` — `@($p.GPU | Where-Object { $_.Vendor -eq 'nvidia' -and $_.LatestStatus -eq 'atualizar' }).Count -gt 0` → Info "Driver NVIDIA desatualizado: instalado X, disponível Y" (computed in reason via `$p`).
  15. `old-drivers` — `@($p.Drivers | Where-Object Old).Count -gt 0` → Info "N drivers com mais de 180 dias — veja a tabela".
  When-expressions are evaluated with `[scriptblock]::Create($rule.When)` in a scope where `$p` is defined; errors → rule skipped + logged.
- [ ] **Step 2: SelfTest** — evaluate rules on the real profile and on each simulated profile; assert: `laptop` → `WPFTweaksWBPowerSettings` in Discouraged and not in Recommended; `vm` → `WPFToggleWBHAGS` in Discouraged; `hdd` → `WPFTweaksWBPrefetch` in Discouraged; `server-iis` → `WPFTweaksWBGameDVR` in Discouraged; every Recommend key has `risk -eq 'seguro'` (typo/risk guard); every Recommend/Avoid key exists in `$sync.configs.tweaks`; print `Regras: N disparadas no perfil real → R recomendados, A evitados`.
- [ ] **Step 3: Commit** `feat(engine): recommendation rules engine with simulated-profile tests`.

---

### Task 4: Recommendation visuals (Border outline + tooltip), search unwrap, "Marcar recomendados"

**Files:** Create `src/Engine/winforge/wf-recoui.ps1`; Modify `build.ps1` (anchors in `Invoke-WPFUIElements` and `Find-TweaksByNameOrDescription`, tab init, XAML buttons, button switch); Modify `src/Engine/xaml/wb-xaml-tab.xml` (Jogos preset row gets `WPFGamesSelectRecommended`).

- [ ] **Step 1: Row wrapping at creation** — anchored `Replace-Once` on the base lines (pre-rename text; three sites):
  - base 7175: `                        $stackPanelContainer.Children.Add($dockPanel) | Out-Null` (toggle) →
    ```powershell
                        $wfRow = New-Object Windows.Controls.Border; $wfRow.BorderThickness = "0"; $wfRow.CornerRadius = "4"; $wfRow.Padding = "3,0"; $wfRow.Margin = "0,1"; $wfRow.Tag = $entryInfo.Name; $wfRow.Child = $dockPanel
                        $stackPanelContainer.Children.Add($wfRow) | Out-Null
    ```
  - base 7517 (checkbox default branch): same with `$horizontalStackPanel`. (Base 7293 is the combobox row — leave it.)
  Verify anchor uniqueness: 7175 text appears once; the `$horizontalStackPanel` add appears twice (7293 combobox, 7517 checkbox) — anchor the checkbox one by including the following line `                        $sync[$entryInfo.Name] = $checkBox` in the old text.
- [ ] **Step 2: Search unwrap** — in `Find-TweaksByNameOrDescription`, both loops iterate `$items` (children of the category StackPanel). Inject at the top of each `foreach ($item in $items) {` body: `$wfVisual = $item; if ($item -is [Windows.Controls.Border] -and $item.Child) { $item = $item.Child }` and change every `$item.Visibility = ...` assignment inside those loops to `$wfVisual.Visibility = ...` (grep the exact lines in the base; there are ~6). Use `Replace-Once` per distinct line; if a line text repeats, include one preceding line in the anchor. SelfTest addition: after mounting tabs, call `Find-TweaksByNameOrDescription -SearchString 'Cortana'` and assert the Border wrapping `WPFTweaksWBCortana` is Visible and the one wrapping `WPFTweaksActivity` is Collapsed; then `-SearchString ""` restores both Visible.
- [ ] **Step 3: `Update-WinForgeRecommendationVisuals`** — for every `$sync.Recommended`/`$sync.Discouraged` key with a control in `$sync`: find the Border (`$ctl.Parent` for toggle is DockPanel → its Parent is the Border; for checkbox `$ctl.Parent` is StackPanel → Parent Border; combobox rows are not wrapped → skip), set `BorderBrush` `#2E7D32` / `#EF6C00`, `BorderThickness` `1.5`; tooltip: prefix `"✔ Recomendado: <motivo>`n`n"` / `"⚠ Não recomendado neste sistema: <motivo>`n`n"` on the CheckBox tooltip (checkbox) or the Label tooltip (toggle) — store the original tooltip in `$ctl.Tag` (`@{Orig=...}`) the first time so re-runs do not stack prefixes. Call it at the end of `Initialize-WinUtilTabContent` (after `Reset-WPFCheckBoxes`) and from the profile job completion. Keys present in both lists → Discouraged wins.
- [ ] **Step 4: Profile job** — `Start-WinForgeProfileJob`: `Invoke-WPFRunspace` computing `Get-WinForgeSystemProfile` (with network) → `$sync.Profile`, `Invoke-WinForgeRules`, then `Invoke-WPFUIThread { Update-WinForgeRecommendationVisuals; Update-WinForgeDiagnosticsTab }` (the latter exists from Task 5; guard with `Get-Command`). Start it from `Add_ContentRendered` right after `Send-WinForgeReady` (anchor in build.ps1: the line `    Send-WinForgeReady`). SelfTest: run the profile + rules synchronously before mounting tabs (already computed in Task 1/3 SelfTest) so visuals apply during the tab-mount test; assert at least one Border has `BorderBrush` set when `$sync.Recommended.Count -gt 0`.
- [ ] **Step 5: Buttons** — Tweaks tab XAML: after `WPFPresetWinForge` add `<Button Name="WPFSelectRecommended" Content=" Marcar recomendados " ... ToolTip="Marca os itens que o diagnóstico recomenda para este PC (contorno verde)."/>`; Jogos tab: `WPFGamesSelectRecommended`. `Invoke-WPFButton` switch: `"WPFSelectRecommended" {Select-WinForgeRecommended -Tab Tweaks}`, `"WPFGamesSelectRecommended" {Select-WinForgeRecommended -Tab Jogos}`. SelfTest: call `Select-WinForgeRecommended -Tab All` and assert `$sync.selectedTweaks` contains every recommended key that has a control.
- [ ] **Step 6: Build + SelfTest; controller runs the exe once (UAC) to eyeball green outlines.** Commit `feat(ui): recommendation outlines and tooltips, select-recommended buttons, search-aware row wrapping`.

---

### Task 5: Diagnóstico tab

**Files:** Create `src/Engine/xaml/wf-xaml-diag-nav.xml`, `src/Engine/xaml/wf-xaml-diag-tab.xml`, `src/Engine/winforge/wf-diag.ps1`; Modify `build.ps1` (insert nav before the WPFTab3BT block like Jogos; TabItem before `</TabControl>`; `Initialize-WinUtilTabContent` case `"Diagnostico"`; `Invoke-WPFTab` search visibility unchanged (no search on this tab); Alt+D → `WPFTab8BT`; button switch entries).

- [ ] **Step 1: XAML** — nav ToggleButton `WPFTab8BT` (`<Underline>D</Underline>iagnóstico`), TabItem `Header="Diagnostico"` `Name="WPFTab8"` (Header without accent because `$sync.currentTab` compares headers in code) containing a ScrollViewer with: top button row (`WPFDiagRefresh` "Atualizar diagnóstico", `WPFDiagWUDrivers` "Buscar drivers no Windows Update", `WPFDiagExport` "Exportar relatório HTML", `WPFDiagSelectRecommended` "Marcar todos os recomendados"); a `WrapPanel Name="WPFDiagCards"` (cards built in code: Border with title + lines for Sistema, Máquina, CPU, Memória, GPU, Armazenamento, Rede, Energia, Segurança); a `TextBlock Name="WPFDiagInfos"` (Info rules); a `DataGrid Name="WPFDiagDrivers"` (AutoGenerateColumns false; columns Dispositivo, Classe, Versão, Data, Fornecedor, Status, Página do fabricante (hyperlink via `DataGridHyperlinkColumn`)); a `DataGrid Name="WPFDiagWU"` for Windows Update results (hidden until searched); a `ItemsControl Name="WPFDiagRecs"` listing `✔ <Content> — <motivo>` and `⚠ ...`.
- [ ] **Step 2: Functions** — `Initialize-WinForgeDiagnosticsTab` (wires buttons; first fill if profile exists, else shows "Coletando informações do sistema..."); `Update-WinForgeDiagnosticsTab` (rebuilds cards/grids from `$sync.Profile`, `$sync.Recommended`, `$sync.Discouraged`, `$sync.RuleInfos`; must run on the UI thread); `Invoke-WinForgeDriverUpdateSearch` (runspace → `Search-WinForgeWindowsUpdateDrivers` → UI grid; progress via `Set-WinForgeTweaksProgressIndicator`); `Export-WinForgeDiagnosticsReport` (writes `%LocalAppData%\WinForge\reports\diagnostico-<yyyyMMdd-HHmm>.html` — self-contained HTML, dark theme, same sections; opens it with `Start-Process`); `WPFDiagRefresh` → `Start-WinForgeProfileJob -Force`.
- [ ] **Step 3: Wiring** — `Initialize-WinUtilTabContent` case; `Invoke-WPFTab` handles tab index 7 (8th TabItem — Diagnóstico must be appended AFTER Jogos in the TabControl so indices stay: Install 0, Tweaks 1, Config 2, Updates 3, Win11ISO 4, AppX 5, Jogos 6, Diagnostico 7); key events `"D"`; SelfTest: mount `Diagnostico` headless with the real profile, assert `WPFDiagCards` has ≥ 8 children, `WPFDiagDrivers.Items.Count -eq $sync.Profile.Drivers.Count`, export report to a temp path (parameter `-Path`) and assert file > 5 KB containing the CPU name.
- [ ] **Step 4: Commit** `feat(ui): Diagnostico tab with profile cards, driver table, Windows Update driver search and HTML report`.

---

### Task 6: Docs, version 1.2.0

- [ ] README: sections "Diagnóstico e recomendações" (how outlines work, what is detected, NVIDIA check, WU driver search, HTML report; no automatic driver installs) and roadmap update; `docs/changelog.md` `## 1.2.0 (2026-09-07)`; `version.props` 1.2.0; `build.cmd` OK; commit `docs: diagnostics and recommendations; release 1.2.0`.
