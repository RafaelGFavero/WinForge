# WinForge Plan 1 — Base própria (estrutura, rebrand, logo, launcher .exe, build, CI, repo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the seeded repo into a buildable WinForge product: rebranded PowerShell engine (no Chris Titus Tech art/text), own logo, a C# `.NET Framework 4.8` launcher that ships as `WinForge.exe`, one-command build, SelfTest, CI and the public GitHub repository.

**Architecture:** The engine stays a single generated PowerShell file (`dist/engine/WinForge.ps1`) assembled by `src/Engine/build.ps1` from the untouched upstream WinUtil file plus WinForge blocks, then post-processed by a global rename pass (`WinUtil`→`WinForge`) and a CTT-removal pass. The launcher is a tiny WPF exe that embeds the engine as a resource, extracts it to `%LocalAppData%\WinForge\engine\<version>\`, runs `powershell.exe -STA` hidden, and shows a splash until the engine signals a named event.

**Tech Stack:** Windows PowerShell 5.1 (engine), WPF, C# 7.3 on `net48` built with .NET 8 SDK (SDK-style csproj), xUnit 2.x for launcher tests, GitHub Actions `windows-latest`, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-09-07-winforge-design.md` (sections 3, 4, 5.1, 6)

## Global Constraints

- Product name `WinForge`; first version `1.0.0`; single version source `version.props`.
- License MIT (Rafael Favero) + `NOTICE` keeping WinUtil (Chris Titus Tech, MIT) attribution. `NOTICE` is the ONLY file allowed to contain `Chris Titus`/`christitus`.
- Generated engine file must contain zero matches for `(?i)christitus|chris titus|\bCTT\b|sponsor|winutil` (function names included — global rename makes them `WinForge`).
- Engine output encoding UTF-8 with BOM, CRLF. Build fails on missing/ambiguous anchor.
- Launcher targets `net48` only, `requireAdministrator` manifest, no third-party NuGet packages in the shipped exe.
- New UI text in Portuguese (pt-BR); inherited WinUtil English text stays.
- Commits: Conventional Commits, end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Never edit `src/Engine/base/winutil-26.08.19.ps1` by hand.

---

## File map

| Path | Responsibility |
|------|----------------|
| `version.props` | MSBuild props with `<Version>1.0.0</Version>`; read by build.ps1 and csproj |
| `LICENSE`, `NOTICE`, `README.md` | licensing + attribution + user docs |
| `build.cmd` | engine build → SelfTest → `dotnet build` → copy exe to `dist/` |
| `src/Engine/build.ps1` | assembly (existing, moved paths) + rename pass + CTT removal + brand test + parse check |
| `src/Engine/winforge/wb-functions.ps1` | existing WinForge functions (renamed file later plans) |
| `src/Engine/winforge/wf-launcher.ps1` | `-ReadyEvent` handling, `Send-WinForgeReady` |
| `src/Engine/winforge/wf-assets.ps1` | new logo path data (`Get-WinForgeLogoPaths`) |
| `src/Engine/config/wb-config.ps1` | existing configs |
| `src/Engine/xaml/*.xml` | existing XAML pieces |
| `tests/engine/Test-Brand.ps1` | greps dist for forbidden strings, exit code = hits |
| `tools/Make-Icon.ps1` | renders logo to PNG sizes and packs `assets/winforge.ico` |
| `assets/winforge.ico`, `assets/logo.svg` | brand assets |
| `src/Launcher/WinForge.csproj`, `app.manifest`, `App.xaml(.cs)`, `SplashWindow.xaml(.cs)`, `EngineHost.cs`, `Program.cs` | launcher |
| `src/Launcher.Tests/Launcher.Tests.csproj`, `EngineHostTests.cs` | xUnit tests for pure logic |
| `.github/workflows/build.yml` | CI + release |

---

### Task 1: Repo scaffolding, version source, build.ps1 path move

**Files:**
- Create: `version.props`, `LICENSE`, `NOTICE`, `build.cmd`, `README.md`
- Modify: `src/Engine/build.ps1` (param defaults + input paths + version injection)
- Move: nothing else (files already under `src/Engine/{base,winforge,config,xaml}`)

**Interfaces:**
- Produces: `dist/engine/WinForge.ps1`; `build.ps1 -SkipBrandTest` switch (used until Task 3 makes the brand test pass); `$sync.version` injected from `version.props`.

- [ ] **Step 1: Create `version.props`**

```xml
<Project>
  <PropertyGroup>
    <Version>1.0.0</Version>
    <Product>WinForge</Product>
    <Company>Rafael Favero</Company>
    <Copyright>Copyright (c) 2026 Rafael Favero</Copyright>
  </PropertyGroup>
</Project>
```

- [ ] **Step 2: Create `LICENSE` (MIT, "Copyright (c) 2026 Rafael Favero") and `NOTICE`**

`NOTICE`:
```
WinForge
Copyright (c) 2026 Rafael Favero. Licensed under the MIT License (see LICENSE).

This product includes software derived from WinUtil
(https://github.com/ChrisTitusTech/winutil), Copyright (c) Chris Titus Tech,
licensed under the MIT License. The upstream file is kept unmodified at
src/Engine/base/winutil-26.08.19.ps1; all modifications are applied at build time.

The gaming, GPU, service, power and maintenance optimizations were derived from the
"Windows Boost - Essential" script collection and rewritten as reversible tweaks.
```

- [ ] **Step 3: Update `src/Engine/build.ps1` header and paths**

Replace the `param(...)` block and the four `Read-Lf` lines with:

```powershell
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [switch]$SkipBrandTest
)
$ErrorActionPreference = 'Stop'
$Source  = Join-Path $PSScriptRoot "base\winutil-26.08.19.ps1"
$OutDir  = Join-Path $RepoRoot "dist\engine"
$Version = ([xml](Get-Content (Join-Path $RepoRoot "version.props") -Raw)).Project.PropertyGroup.Version
if (-not $Version) { throw "version.props sem <Version>" }
```
and
```powershell
$src            = Read-Lf $Source
$functionsBlock = Read-Lf (Join-Path $PSScriptRoot "winforge\wb-functions.ps1")
$configBlock    = Read-Lf (Join-Path $PSScriptRoot "config\wb-config.ps1")
$xamlNav        = Read-Lf (Join-Path $PSScriptRoot "xaml\wb-xaml-nav.xml")
$xamlTab        = Read-Lf (Join-Path $PSScriptRoot "xaml\wb-xaml-tab.xml")
```
Change the version replacement to use `$Version`:
```powershell
$src = Replace-Once $src '$sync.version = "26.08.19"' ("`$sync.version = `"$Version`"`n`$sync.baseVersion = `"26.08.19`"") "version"
```
Change output file name to `WinForge.ps1`:
```powershell
$outFile = Join-Path $OutDir "WinForge.ps1"
```

- [ ] **Step 4: Run the build**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1 -SkipBrandTest`
Expected: `Gerado: ...\dist\engine\WinForge.ps1 (...)` and `Sintaxe PowerShell: OK`

- [ ] **Step 5: Run SelfTest on the output**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
Expected: last line `== SelfTest concluído: 0 erro(s) ==`, exit code 0

- [ ] **Step 6: Create `build.cmd` and README stub**

`build.cmd`:
```bat
@echo off
setlocal
cd /d "%~dp0"
echo [1/4] Engine
powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1 || exit /b 1
echo [2/4] SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest || exit /b 1
echo [3/4] Launcher
dotnet build src\Launcher\WinForge.csproj -c Release -nologo || exit /b 1
echo [4/4] Copiar
copy /y src\Launcher\bin\Release\net48\WinForge.exe dist\WinForge.exe >nul || exit /b 1
echo OK: dist\WinForge.exe
```
`README.md`: title `WinForge`, one paragraph (pt-BR) "utilitário de otimização e reparo para Windows 10, 11 e Server", section "Como usar" (baixar `WinForge.exe`, executar, responder à pergunta de ponto de restauração), section "Compilar" (`build.cmd`, requer .NET SDK 8), section "Licença" (MIT, ver NOTICE). Steps [3/4] and [4/4] fail until Task 5; that is expected now.

- [ ] **Step 7: Commit**

```bash
git add version.props LICENSE NOTICE build.cmd README.md src/Engine/build.ps1
git commit -m "build: single version source, repo scaffolding, engine build outputs dist/engine/WinForge.ps1"
```

---

### Task 2: Brand test (red) and CTT-removal + rename pass in build.ps1

**Files:**
- Create: `tests/engine/Test-Brand.ps1`
- Modify: `src/Engine/build.ps1` (post-pass before writing output; call the brand test at the end)
- Modify: `src/Engine/config/wb-config.ps1` (no `christitus` links exist there; verify)

**Interfaces:**
- Produces: `Test-Brand.ps1 -File <path>` exits with number of forbidden hits, prints each `line: text`.

- [ ] **Step 1: Write `tests/engine/Test-Brand.ps1`**

```powershell
param([Parameter(Mandatory)][string]$File)
$forbidden = '(?i)christitus|chris\s*titus|\bCTT\b|sponsor|winutil'
$hits = Select-String -Path $File -Pattern $forbidden
foreach ($h in $hits) { Write-Host ("  {0}: {1}" -f $h.LineNumber, $h.Line.Trim().Substring(0, [Math]::Min(120, $h.Line.Trim().Length))) }
Write-Host "Brand test: $($hits.Count) ocorrência(s) proibida(s) em $File"
exit $hits.Count
```

- [ ] **Step 2: Run it against the current output to confirm it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\engine\Test-Brand.ps1 -File dist\engine\WinForge.ps1`
Expected: exit code > 0 (hundreds of hits)

- [ ] **Step 3: Add the CTT-removal pass to `build.ps1`** (insert right before `# ---------------------------------------------------------------- saída`)

```powershell
# ---------------------------------------------------------------- remoção de referências CTT (antes do rename global)
# 1) links de documentação do WinUtil nas configs JSON (o glifo "(?)" some junto)
$src = [regex]::Replace($src, ',\n\s*"link": "https://winutil\.christitus\.com[^"]*"', '')
$src = [regex]::Replace($src, '\n\s*"link": "https://winutil\.christitus\.com[^"]*",', "`n")
# 2) menu Documentação -> README do WinForge
$src = Replace-Once $src 'Start-Process "https://winutil.christitus.com/"' 'Start-Process "https://github.com/rafaelfavero/WinForge#readme"' "docs url"
# 3) relaunch sem arquivo (irm do CTT) -> mensagem
$src = Replace-Once $src '"&([ScriptBlock]::Create((irm https://github.com/ChrisTitusTech/winutil/releases/latest/download/winutil.ps1))) $($argList -join '' '')"' '"Write-Host ''Execute o WinForge a partir do arquivo WinForge.exe ou WinForge.ps1.''"' "relaunch url"
# 4) função de sponsors
$src = Replace-Between $src 'Function Invoke-WinUtilSponsors {' 'function Invoke-WinUtilSSHServer {' '' "remove sponsors fn"
# 5) perfil PowerShell do CTT: entradas da aba Config
$src = [regex]::Replace($src, '(?s)\s*"WPFWinUtilInstallPSProfile": \{.*?\n  \},', '')
$src = [regex]::Replace($src, '(?s)\s*"WPFWinUtilUninstallPSProfile": \{.*?\n  \},', '')
$src = Replace-Once $src 'wt new-tab pwsh -NoExit -Command "irm https://github.com/ChrisTitusTech/powershell-profile/raw/main/setup.ps1 | iex"' 'Write-Host "Recurso removido no WinForge."' "profile installer"
$src = Replace-Once $src '    Write-Host "Successfully uninstalled CTT PowerShell Profile." -ForegroundColor Green' '    Write-Host "Recurso removido no WinForge." -ForegroundColor Yellow' "profile uninstall msg"
# 6) comentários/strings soltas
$src = $src -replace 'CTT logo preset:', 'logo preset:'
$src = $src -replace "Chris Titus Tech's Windows Utility", 'WinForge'
$src = Replace-Once $src '    Author         : Chris Titus @christitustech' '    Autor          : Rafael Favero' "header author"
$src = $src -replace '    Base           : Chris Titus @christitustech - WinUtil 26\.08\.19 \(https://github\.com/ChrisTitusTech/winutil\)', '    Base           : WinUtil 26.08.19 (MIT) - ver NOTICE'
$src = $src -replace '    Runspace Author: @DeveloperDurp\n', ''
$src = $src -replace '(?m)^    GitHub         : https://github\.com/ChrisTitusTech\n', ''
# 7) About/Créditos: texto sem links CTT (atribuição fica no NOTICE)
$src = [regex]::Replace($src, '<a href="https://github\.com/ChrisTitusTech/winutil">([^<]*)</a>', '$1')
$src = $src -replace '<a href="https://winutil\.christitus\.com/">winutil\.christitus\.com</a>', 'arquivo NOTICE'

# ---------------------------------------------------------------- rename global WinUtil -> WinForge (funções, variáveis, strings, pastas)
$src = $src -replace 'WinUtil', 'WinForge'
$src = $src -replace 'Winutil', 'WinForge'
$src = $src -replace 'winutil', 'winforge'
```
Note: the `$src -replace` operator uses regex; the patterns above contain no unescaped metacharacters except where intended. `Replace-Between` with an empty replacement deletes the sponsors function up to (excluding) the next function header.

- [ ] **Step 4: Fix things the rename breaks**

After rename, these identifiers in *our* blocks also change (`Invoke-WinUtilBoostRestorePoint` → `Invoke-WinForgeBoostRestorePoint`, `$winutildir` → `$winforgedir`, log dir `WindowsBoost` stays). Update the two hard-coded strings in `wb-functions.ps1` that must survive as WinForge names: none reference `WinUtil` as a literal in user-facing text except the credits/about text, which Step 3 already rewrote. Verify with:

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1` (brand test runs at the end, see Step 5)

- [ ] **Step 5: Call the brand test from `build.ps1`** (append after `Write-Host "Sintaxe PowerShell: OK"`)

```powershell
if (-not $SkipBrandTest) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "tests\engine\Test-Brand.ps1") -File $outFile
    if ($LASTEXITCODE -ne 0) { throw "Brand test falhou: $LASTEXITCODE ocorrência(s)." }
}
```

- [ ] **Step 6: Build, iterate until brand test = 0, then SelfTest**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1`
Expected: `Brand test: 0 ocorrência(s) proibida(s)`.
Run: `powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
Expected: `0 erro(s)`, and the line listing `Config:` count is 42 (two profile buttons removed).

- [ ] **Step 7: Commit**

```bash
git add tests/engine/Test-Brand.ps1 src/Engine/build.ps1
git commit -m "feat(engine): remove CTT references and rename engine to WinForge at build time"
```

---

### Task 3: Logo (`wf-assets.ps1`), dialog/nav rendering, `.ico` generation

**Files:**
- Create: `src/Engine/winforge/wf-assets.ps1`, `tools/Make-Icon.ps1`, `assets/logo.svg`, `assets/winforge.ico`, `assets/logo-256.png`
- Modify: `src/Engine/build.ps1` (read `wf-assets.ps1`; replace the three `$LogoPathData*`/`$LogoPath*` blocks inside `Invoke-WinUtilAssets` 'logo' case with a call to `Get-WinForgeLogoPaths`)

**Interfaces:**
- Produces: `Get-WinForgeLogoPaths` → array of `[Windows.Shapes.Path]` on a 100×100 canvas; `assets/winforge.ico` (16/32/48/256, PNG-compressed entries).

- [ ] **Step 1: Write `src/Engine/winforge/wf-assets.ps1`**

```powershell
#region ===== WinForge - logo =====
function Get-WinForgeLogoPaths {
    <#
    .SYNOPSIS
        Logo do WinForge em um canvas 100x100: bigorna (aço) com um "W" de faíscas (laranja forja).
        Arte original do projeto WinForge.
    #>
    $anvil = New-Object Windows.Shapes.Path
    $anvil.Data = [Windows.Media.Geometry]::Parse("M 8,54 L 92,54 L 92,64 L 64,64 L 64,76 L 76,86 L 24,86 L 36,76 L 36,64 L 20,64 L 8,58 Z")
    $anvil.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5B6470")

    $horn = New-Object Windows.Shapes.Path
    $horn.Data = [Windows.Media.Geometry]::Parse("M 8,54 L 20,64 L 8,58 Z M 88,54 C 96,52 98,58 92,64 Z")
    $horn.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F4650")

    $w = New-Object Windows.Shapes.Path
    $w.Data = [Windows.Media.Geometry]::Parse("M 22,10 L 33,10 L 41,36 L 48,18 L 52,18 L 59,36 L 67,10 L 78,10 L 64,48 L 55,48 L 50,34 L 45,48 L 36,48 Z")
    $w.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF7A1A")

    $spark = New-Object Windows.Shapes.Path
    $spark.Data = [Windows.Media.Geometry]::Parse("M 84,20 L 87,28 L 95,31 L 87,34 L 84,42 L 81,34 L 73,31 L 81,28 Z")
    $spark.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFB347")

    return @($anvil, $horn, $w, $spark)
}
#endregion
```

- [ ] **Step 2: Splice it into `Invoke-WinUtilAssets` from `build.ps1`** (add after the functions insert)

```powershell
$assetsBlock = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-assets.ps1")
$src = Insert-Before $src "`$sync.configs.applications = @'" ($assetsBlock.TrimEnd() + "`n`n") "insert assets"
# substitui os três paths do logo original pelo logo WinForge
$src = Replace-Between $src "          `$LogoPathData1 = @`"" "          # Add the paths to the Canvas" @'
          $wfLogoPaths = Get-WinForgeLogoPaths

'@ "logo paths"
```
Then read the 8 lines after the original `# Add the paths to the Canvas` inside the 'logo' case (they do `$canvas.Children.Add($LogoPath1)` etc.) and replace them with:
```powershell
$src = Replace-Once $src @'
          $canvas.Children.Add($LogoPath1) | Out-Null
          $canvas.Children.Add($LogoPath2) | Out-Null
          $canvas.Children.Add($LogoPath3) | Out-Null
'@ @'
          foreach ($wfPath in $wfLogoPaths) { $canvas.Children.Add($wfPath) | Out-Null }
'@ "logo add"
```
(Confirm the exact three `Children.Add` lines with `grep -n 'Children.Add(\$LogoPath' src/Engine/base/winutil-26.08.19.ps1` before writing the anchor; use the exact text found.)

- [ ] **Step 3: Write `tools/Make-Icon.ps1`**

```powershell
# Renderiza o logo WinForge (mesmo path do engine) em PNGs e empacota assets/winforge.ico
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
. (Join-Path $RepoRoot "src\Engine\winforge\wf-assets.ps1")

function Render-Png([int]$size) {
    $canvas = New-Object Windows.Controls.Canvas
    $canvas.Width = 100; $canvas.Height = 100
    foreach ($p in (Get-WinForgeLogoPaths)) { $canvas.Children.Add($p) | Out-Null }
    $canvas.LayoutTransform = New-Object Windows.Media.ScaleTransform(($size / 100), ($size / 100))
    $canvas.Measure([Windows.Size]::new($size, $size)); $canvas.Arrange([Windows.Rect]::new(0, 0, $size, $size)); $canvas.UpdateLayout()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($size, $size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($canvas)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $ms = New-Object System.IO.MemoryStream; $enc.Save($ms); return $ms.ToArray()
}

$sizes = 16, 32, 48, 256
$pngs = @{}
foreach ($s in $sizes) { $pngs[$s] = Render-Png $s }
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "assets") | Out-Null
[IO.File]::WriteAllBytes((Join-Path $RepoRoot "assets\logo-256.png"), $pngs[256])

# ICO: header(6) + dir entries(16 each) + PNG payloads
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
foreach ($s in $sizes) {
    $b = $pngs[$s]
    $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s }))); $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$b.Length); $bw.Write([uint32]$offset)
    $offset += $b.Length
}
foreach ($s in $sizes) { $bw.Write($pngs[$s]) }
$bw.Flush()
[IO.File]::WriteAllBytes((Join-Path $RepoRoot "assets\winforge.ico"), $ms.ToArray())
Write-Host "assets\winforge.ico gerado ($($ms.Length) bytes) + assets\logo-256.png"
```

- [ ] **Step 4: Run it and look at the PNG**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\Make-Icon.ps1`
Expected: `assets\winforge.ico gerado (...)`. Open `assets\logo-256.png` (Read tool) and confirm: gray anvil bottom half, orange "W" above it, small light spark top-right, nothing clipped. Adjust path numbers in `wf-assets.ps1` if shapes overlap or clip; re-run.

- [ ] **Step 5: Write `assets/logo.svg`** with the same four paths (viewBox `0 0 100 100`, same fills) so the README and GitHub can show it.

- [ ] **Step 6: Build + SelfTest + brand test**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1` then `powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
Expected: brand test 0, SelfTest 0 erros. Add to SelfTest (in build.ps1's SelfTest block, XAML section) one line that renders the logo: `$null = Invoke-WinForgeAssets -Type "logo" -Size 25; Write-Host "  Logo: OK"` (name after rename).

- [ ] **Step 7: Commit**

```bash
git add src/Engine/winforge/wf-assets.ps1 tools/Make-Icon.ps1 assets/ src/Engine/build.ps1
git commit -m "feat(brand): WinForge logo (anvil + spark W), icon generator, engine logo replaced"
```

---

### Task 4: Engine readiness signal and launcher-facing parameters

**Files:**
- Create: `src/Engine/winforge/wf-launcher.ps1`
- Modify: `src/Engine/build.ps1` (param block gains `-ReadyEvent`, `-Console`; insert file; call `Send-WinForgeReady` in `Add_ContentRendered`; on fatal exit call `Send-WinForgeReady -Failed`)

**Interfaces:**
- Consumes: launcher passes `-ReadyEvent WinForge.Ready.<launcherPid>`.
- Produces: engine sets the named `EventWaitHandle` when the window is rendered; exit code 2 when XAML fails.

- [ ] **Step 1: Write `wf-launcher.ps1`**

```powershell
#region ===== WinForge - integração com o launcher =====
function Send-WinForgeReady {
    <#
    .SYNOPSIS
        Sinaliza ao WinForge.exe que a janela está pronta (fecha o splash). Sem launcher, não faz nada.
    #>
    param([switch]$Failed)
    if ([string]::IsNullOrWhiteSpace($sync.ReadyEventName)) { return }
    try {
        $evt = [System.Threading.EventWaitHandle]::OpenExisting($sync.ReadyEventName)
        $evt.Set() | Out-Null
        $evt.Dispose()
        Write-WinForgeLog -Component "Launcher" -Message ("Evento de prontidão sinalizado ({0})." -f $(if ($Failed) { "falha" } else { "ok" }))
    } catch {
        Write-WinForgeLog -Level "WARN" -Component "Launcher" -Message "Não foi possível sinalizar $($sync.ReadyEventName): $($_.Exception.Message)"
    }
}
#endregion
```
(`Write-WinForgeLog` is `Write-WinUtilLog` after the rename pass; write the file with the post-rename name because it is inserted before the rename pass — the pass does not touch `WinForge` tokens.)

- [ ] **Step 2: Wire it in `build.ps1`**

Param block: add `[string]$ReadyEvent,` and `[switch]$Console` after `[switch]$NoElevation`. After `$sync.RestorePointCreated = $false` add `$sync.ReadyEventName = $ReadyEvent`. Insert the file before `$sync.configs.applications = @'` like the others. In the `Add_ContentRendered` insert (restore prompt hook), add before the restore prompt line: `    Send-WinForgeReady`. In the XAML failure branch (`Write-Host "Quitting WinUtil..."` — after rename `Quitting WinForge...`) add `Send-WinForgeReady -Failed` before `exit 1`, and change `exit 1` to `exit 2`.

- [ ] **Step 3: Verify manually**

Run in PowerShell:
```powershell
$e = New-Object System.Threading.EventWaitHandle($false, 'ManualReset', 'WinForge.Ready.test')
$p = Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -STA -File dist\engine\WinForge.ps1 -NoElevation -NoRestorePoint -ReadyEvent WinForge.Ready.test' -PassThru
"ready=$($e.WaitOne(60000))"; Stop-Process -Id $p.Id -Force
```
Expected: `ready=True` within a few seconds. Do NOT run while the user is in a full-screen game; check first with `Get-Process cs2 -ErrorAction SilentlyContinue`.

- [ ] **Step 4: Commit**

```bash
git add src/Engine/winforge/wf-launcher.ps1 src/Engine/build.ps1
git commit -m "feat(engine): ready-event signal and launcher parameters"
```

---

### Task 5: Launcher project (C# net48 WPF) with tests

**Files:**
- Create: `src/Launcher/WinForge.csproj`, `src/Launcher/app.manifest`, `src/Launcher/App.xaml`, `src/Launcher/App.xaml.cs`, `src/Launcher/SplashWindow.xaml`, `src/Launcher/SplashWindow.xaml.cs`, `src/Launcher/EngineHost.cs`, `src/Launcher/Program.cs`
- Create: `src/Launcher.Tests/Launcher.Tests.csproj`, `src/Launcher.Tests/EngineHostTests.cs`
- Create: `WinForge.sln`

**Interfaces:**
- Produces: `EngineHost` static class: `string ComputeSha256(byte[] data)`, `bool NeedsExtract(string targetFile, string expectedHash)`, `string BuildArguments(string enginePath, string readyEvent, string[] passthrough)`, `string EnginePath(string localAppData, string version)`.

- [ ] **Step 1: Test project + failing tests**

`src/Launcher.Tests/Launcher.Tests.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <IsPackable>false</IsPackable>
    <LangVersion>7.3</LangVersion>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\Launcher\WinForge.csproj" />
  </ItemGroup>
</Project>
```
`EngineHostTests.cs`:
```csharp
using System;
using System.IO;
using System.Text;
using WinForge;
using Xunit;

public class EngineHostTests
{
    [Fact]
    public void ComputeSha256_KnownVector()
    {
        var hash = EngineHost.ComputeSha256(Encoding.ASCII.GetBytes("abc"));
        Assert.Equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", hash);
    }

    [Fact]
    public void NeedsExtract_WhenFileMissing_True()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ps1");
        Assert.True(EngineHost.NeedsExtract(path, "00"));
    }

    [Fact]
    public void NeedsExtract_WhenHashMatches_False()
    {
        var path = Path.GetTempFileName();
        File.WriteAllBytes(path, Encoding.ASCII.GetBytes("abc"));
        Assert.False(EngineHost.NeedsExtract(path, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
        File.Delete(path);
    }

    [Fact]
    public void BuildArguments_QuotesPathAndPassesThrough()
    {
        var args = EngineHost.BuildArguments(@"C:\x y\WinForge.ps1", "WinForge.Ready.42", new[] { "-NoRestorePoint", "-Preset", "Gamer" }, hideWindow: true);
        Assert.Equal("-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\x y\\WinForge.ps1\" -ReadyEvent WinForge.Ready.42 -NoRestorePoint -Preset Gamer", args);
    }

    [Fact]
    public void BuildArguments_ConsoleFlag_NotForwardedAndWindowVisible()
    {
        var args = EngineHost.BuildArguments(@"C:\e.ps1", "ev", new[] { "-Console" }, hideWindow: false);
        Assert.Equal("-STA -NoProfile -ExecutionPolicy Bypass -File \"C:\\e.ps1\" -ReadyEvent ev", args);
    }

    [Fact]
    public void EnginePath_UsesVersionFolder()
    {
        Assert.Equal(@"C:\LAD\WinForge\engine\1.0.0\WinForge.ps1", EngineHost.EnginePath(@"C:\LAD", "1.0.0"));
    }
}
```

- [ ] **Step 2: Launcher csproj, manifest, and minimal `EngineHost` so tests compile and fail**

`src/Launcher/WinForge.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <Import Project="..\..\version.props" />
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net48</TargetFramework>
    <UseWPF>true</UseWPF>
    <LangVersion>7.3</LangVersion>
    <RootNamespace>WinForge</RootNamespace>
    <AssemblyName>WinForge</AssemblyName>
    <ApplicationIcon>..\..\assets\winforge.ico</ApplicationIcon>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <StartupObject>WinForge.Program</StartupObject>
    <AssemblyVersion>$(Version)</AssemblyVersion>
    <FileVersion>$(Version)</FileVersion>
    <InformationalVersion>$(Version)</InformationalVersion>
    <Description>WinForge - otimização e reparo para Windows 10, 11 e Server</Description>
    <GenerateDocumentationFile>false</GenerateDocumentationFile>
    <Nullable>disable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <EmbeddedResource Include="..\..\dist\engine\WinForge.ps1" Link="Resources\WinForge.ps1" LogicalName="WinForge.Engine" />
  </ItemGroup>
</Project>
```
`app.manifest`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="WinForge.app"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}" />
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </windowsSettings>
  </application>
</assembly>
```
`EngineHost.cs` (full implementation, tests drive it):
```csharp
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace WinForge
{
    public static class EngineHost
    {
        public const string ResourceName = "WinForge.Engine";

        public static string ComputeSha256(byte[] data)
        {
            using (var sha = SHA256.Create())
            {
                var hash = sha.ComputeHash(data);
                var sb = new StringBuilder(hash.Length * 2);
                foreach (var b in hash) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        public static string EnginePath(string localAppData, string version)
        {
            return Path.Combine(localAppData, "WinForge", "engine", version, "WinForge.ps1");
        }

        public static bool NeedsExtract(string targetFile, string expectedHash)
        {
            if (!File.Exists(targetFile)) return true;
            var current = ComputeSha256(File.ReadAllBytes(targetFile));
            return !string.Equals(current, expectedHash, StringComparison.OrdinalIgnoreCase);
        }

        public static byte[] ReadEmbeddedEngine()
        {
            using (var s = typeof(EngineHost).Assembly.GetManifestResourceStream(ResourceName))
            {
                if (s == null) throw new InvalidOperationException("Recurso do engine não encontrado no executável.");
                using (var ms = new MemoryStream()) { s.CopyTo(ms); return ms.ToArray(); }
            }
        }

        public static string EnsureEngine(string version)
        {
            var bytes = ReadEmbeddedEngine();
            var hash = ComputeSha256(bytes);
            var path = EnginePath(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), version);
            if (NeedsExtract(path, hash))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                File.WriteAllBytes(path, bytes);
                File.WriteAllText(path + ".sha256", hash);
            }
            return path;
        }

        public static string BuildArguments(string enginePath, string readyEvent, string[] passthrough, bool hideWindow)
        {
            var sb = new StringBuilder("-STA -NoProfile -ExecutionPolicy Bypass");
            if (hideWindow) sb.Append(" -WindowStyle Hidden");
            sb.Append(" -File \"").Append(enginePath).Append("\"");
            sb.Append(" -ReadyEvent ").Append(readyEvent);
            foreach (var a in passthrough)
            {
                if (string.Equals(a, "-Console", StringComparison.OrdinalIgnoreCase)) continue;
                sb.Append(' ').Append(a.IndexOf(' ') >= 0 ? "\"" + a + "\"" : a);
            }
            return sb.ToString();
        }

        public static string FindPowerShell()
        {
            var sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
            var ps = Path.Combine(sys, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(ps)) throw new FileNotFoundException("powershell.exe não encontrado", ps);
            return ps;
        }

        public static Process Start(string enginePath, string readyEvent, string[] passthrough, bool hideWindow)
        {
            var psi = new ProcessStartInfo
            {
                FileName = FindPowerShell(),
                Arguments = BuildArguments(enginePath, readyEvent, passthrough, hideWindow),
                UseShellExecute = false,
                CreateNoWindow = hideWindow,
                WorkingDirectory = Path.GetDirectoryName(enginePath)
            };
            return Process.Start(psi);
        }
    }
}
```

- [ ] **Step 3: Run tests (expect compile OK, all green — EngineHost is fully implemented; if any test fails, fix EngineHost, not the test)**

Run: `dotnet test src\Launcher.Tests\Launcher.Tests.csproj -nologo`
Expected: `Passed! - Failed: 0, Passed: 6`. (Requires `dist/engine/WinForge.ps1` to exist for the EmbeddedResource; run `src\Engine\build.ps1` first.)

- [ ] **Step 4: Splash + Program**

`SplashWindow.xaml`:
```xml
<Window x:Class="WinForge.SplashWindow" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinForge" Width="420" Height="200" WindowStyle="None" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Background="#1B1F24" AllowsTransparency="False" Topmost="True" ShowInTaskbar="True">
  <Grid Margin="24">
    <Grid.ColumnDefinitions><ColumnDefinition Width="96"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Image x:Name="Logo" Grid.Column="0" Width="80" Height="80" VerticalAlignment="Center"/>
    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="16,0,0,0">
      <TextBlock Text="WinForge" Foreground="#FF7A1A" FontSize="30" FontWeight="Bold"/>
      <TextBlock x:Name="VersionText" Foreground="#9AA4B2" FontSize="13"/>
      <TextBlock x:Name="StatusText" Text="Iniciando o motor..." Foreground="#E6E9EE" FontSize="14" Margin="0,14,0,0"/>
      <ProgressBar IsIndeterminate="True" Height="4" Margin="0,10,0,0" Foreground="#FF7A1A" Background="#2A3038" BorderThickness="0"/>
    </StackPanel>
  </Grid>
</Window>
```
`SplashWindow.xaml.cs`: constructor sets `VersionText.Text = "versão " + version` and loads the icon into `Logo.Source` via `System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/WinForge;component/winforge.ico"))` — add `<Resource Include="..\..\assets\winforge.ico" Link="winforge.ico" />` to the csproj. Expose `void SetStatus(string text)`.

`App.xaml`: `<Application x:Class="WinForge.App" ... ShutdownMode="OnExplicitShutdown" />`. `App.xaml.cs`: empty partial.

`Program.cs`:
```csharp
using System;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace WinForge
{
    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
            var app = new App();
            app.InitializeComponent();
            var splash = new SplashWindow(version);
            splash.Show();

            bool console = args.Any(a => string.Equals(a, "-Console", StringComparison.OrdinalIgnoreCase));
            bool selfTest = args.Any(a => string.Equals(a, "-SelfTest", StringComparison.OrdinalIgnoreCase));
            string readyName = "WinForge.Ready." + Process.GetCurrentProcess().Id;
            int exitCode = 1;

            Task.Run(() =>
            {
                Process engine = null;
                try
                {
                    var enginePath = EngineHost.EnsureEngine(version);
                    using (var ready = new EventWaitHandle(false, EventResetMode.ManualReset, readyName))
                    {
                        engine = EngineHost.Start(enginePath, readyName, args, hideWindow: !console && !selfTest);
                        splash.Dispatcher.Invoke(() => splash.SetStatus("Carregando a interface..."));
                        var handles = new WaitHandle[] { ready, new ProcessWaitHandle(engine) };
                        int signaled = WaitHandle.WaitAny(handles, TimeSpan.FromSeconds(90));
                        if (signaled == 1 || signaled == WaitHandle.WaitTimeout)
                        {
                            if (engine.HasExited && engine.ExitCode != 0)
                                splash.Dispatcher.Invoke(() => MessageBox.Show("O motor do WinForge terminou com erro (código " + engine.ExitCode + ").\nLog: %LocalAppData%\\WindowsBoost\\logs", "WinForge", MessageBoxButton.OK, MessageBoxImage.Error));
                            else if (signaled == WaitHandle.WaitTimeout)
                                splash.Dispatcher.Invoke(() => MessageBox.Show("O motor do WinForge não respondeu em 90 s. Execute WinForge.exe -Console para ver detalhes.", "WinForge", MessageBoxButton.OK, MessageBoxImage.Warning));
                        }
                    }
                    splash.Dispatcher.Invoke(splash.Close);
                    if (engine != null) { engine.WaitForExit(); exitCode = engine.ExitCode; }
                }
                catch (Exception ex)
                {
                    splash.Dispatcher.Invoke(() => { MessageBox.Show("Falha ao iniciar o WinForge:\n" + ex.Message, "WinForge", MessageBoxButton.OK, MessageBoxImage.Error); splash.Close(); });
                }
                finally { app.Dispatcher.Invoke(app.Shutdown); }
            });

            app.Run();
            return exitCode;
        }

        private sealed class ProcessWaitHandle : WaitHandle
        {
            public ProcessWaitHandle(Process p) { SafeWaitHandle = new Microsoft.Win32.SafeHandles.SafeWaitHandle(p.Handle, false); }
        }
    }
}
```
`ShutdownMode="OnExplicitShutdown"` keeps the app alive while the engine runs after the splash closes; `app.Shutdown` runs when the engine exits.

- [ ] **Step 5: Build, then run the exe with `-SelfTest`**

Run: `dotnet build src\Launcher\WinForge.csproj -c Release -nologo`
Expected: `WinForge -> ...\bin\Release\net48\WinForge.exe`, 0 warnings about missing resource.
Run (UAC prompt appears; the user must accept — ask first): `src\Launcher\bin\Release\net48\WinForge.exe -SelfTest -Console`
Expected: console shows the SelfTest, exit code 0, `%LocalAppData%\WinForge\engine\1.0.0\WinForge.ps1` + `.sha256` exist.

- [ ] **Step 6: `WinForge.sln`** with both projects (`dotnet new sln -n WinForge; dotnet sln add src\Launcher\WinForge.csproj src\Launcher.Tests\Launcher.Tests.csproj`). Run `build.cmd` end to end.
Expected: `OK: dist\WinForge.exe`.

- [ ] **Step 7: Commit**

```bash
git add WinForge.sln src/Launcher src/Launcher.Tests
git commit -m "feat(launcher): WinForge.exe (net48 WPF) embeds engine, splash, ready-event handshake, tests"
```

---

### Task 6: CI workflow, public repository, first tag

**Files:**
- Create: `.github/workflows/build.yml`
- Modify: `README.md` (badge, download link), `docs/changelog.md`

- [ ] **Step 1: Write `.github/workflows/build.yml`**

```yaml
name: build
on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: '8.0.x' }
      - name: Engine
        shell: powershell
        run: powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1
      - name: SelfTest
        shell: powershell
        run: powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest
      - name: Launcher tests
        run: dotnet test src\Launcher.Tests\Launcher.Tests.csproj -c Release -nologo
      - name: Launcher
        run: dotnet build src\Launcher\WinForge.csproj -c Release -nologo
      - name: Package
        shell: powershell
        run: |
          New-Item -ItemType Directory -Force dist | Out-Null
          Copy-Item src\Launcher\bin\Release\net48\WinForge.exe dist\
          $v = ([xml](Get-Content version.props)).Project.PropertyGroup.Version
          Compress-Archive -Path dist\WinForge.exe, README.md, LICENSE, NOTICE -DestinationPath "dist\WinForge-$v.zip" -Force
      - uses: actions/upload-artifact@v4
        with: { name: WinForge, path: dist/* }
      - name: Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: |
            dist/WinForge.exe
            dist/WinForge-*.zip
```

- [ ] **Step 2: Create the public repo and push** (requires `gh auth status` OK — ask the user to run `gh auth login --web` if not)

```bash
gh repo create WinForge --public --source . --description "Otimização e reparo para Windows 10, 11 e Server" --push
```
Expected: repo URL printed; `git remote -v` shows origin. Update the docs URL in `build.ps1` Task 2 step 3 if the GitHub username differs from `rafaelfavero` (read it from `gh api user -q .login`), rebuild, commit.

- [ ] **Step 3: Watch CI**

Run: `gh run watch` (or `gh run list --limit 1`). Expected: green. If SelfTest fails on the runner because WPF cannot render, wrap the logo/tab-mount part of SelfTest in a check for `$env:CI` that skips only the rendering step and prints `pulado no CI`; keep config and XAML parse checks.

- [ ] **Step 4: Tag `v1.0.0` and verify release assets**

```bash
git tag v1.0.0 && git push origin v1.0.0
gh release view v1.0.0
```
Expected: `WinForge.exe` and `WinForge-1.0.0.zip` attached.

- [ ] **Step 5: Commit README/changelog**

```bash
git add README.md docs/changelog.md .github/workflows/build.yml
git commit -m "ci: build, test and release workflow; README with download link"
git push
```
