# Build: gera dist\engine\WinForge.ps1 a partir do winutil.ps1 + blocos do WinForge.
# Cada substituição é ancorada em texto único do original; falha alto se a âncora sumir ou for ambígua.
param(
    # raiz do repositório: onde ficam version.props e dist\
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [switch]$SkipBrandTest
)
$ErrorActionPreference = 'Stop'
# WinUtil original (nunca editar à mão)
$Source  = Join-Path $PSScriptRoot "base\winutil-26.08.19.ps1"
$OutDir  = Join-Path $RepoRoot "dist\engine"
$Version = ([xml](Get-Content (Join-Path $RepoRoot "version.props") -Raw)).Project.PropertyGroup.Version
if (-not $Version) { throw "version.props sem <Version>" }

function Read-Lf([string]$path) {
    $t = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $t -replace "`r`n", "`n"
}

function Replace-Once([string]$text, [string]$old, [string]$new, [string]$what) {
    # $text vem de Read-Lf (só LF). As âncoras são here-strings deste arquivo, que o git entrega
    # com CRLF quando core.autocrlf está ligado - sem normalizar, nenhuma âncora de várias linhas casa.
    $old = $old -replace "`r`n", "`n"
    $new = $new -replace "`r`n", "`n"
    $idx = $text.IndexOf($old, [StringComparison]::Ordinal)
    if ($idx -lt 0) { throw "Âncora não encontrada: $what" }
    $idx2 = $text.IndexOf($old, $idx + 1, [StringComparison]::Ordinal)
    if ($idx2 -ge 0) { throw "Âncora ambígua (aparece mais de uma vez): $what" }
    return $text.Substring(0, $idx) + $new + $text.Substring($idx + $old.Length)
}

function Insert-Before([string]$text, [string]$anchor, [string]$block, [string]$what) {
    return Replace-Once $text $anchor ($block + $anchor) $what
}

function Insert-After([string]$text, [string]$anchor, [string]$block, [string]$what) {
    return Replace-Once $text $anchor ($anchor + $block) $what
}

function Replace-Between([string]$text, [string]$startAnchor, [string]$endAnchor, [string]$new, [string]$what) {
    $startAnchor = $startAnchor -replace "`r`n", "`n"
    $endAnchor   = $endAnchor   -replace "`r`n", "`n"
    $new         = $new         -replace "`r`n", "`n"
    $s = $text.IndexOf($startAnchor, [StringComparison]::Ordinal)
    if ($s -lt 0) { throw "Âncora inicial não encontrada: $what" }
    if ($text.IndexOf($startAnchor, $s + 1, [StringComparison]::Ordinal) -ge 0) { throw "Âncora inicial ambígua: $what" }
    $e = $text.IndexOf($endAnchor, $s + $startAnchor.Length, [StringComparison]::Ordinal)
    if ($e -lt 0) { throw "Âncora final não encontrada: $what" }
    return $text.Substring(0, $s) + $new + $text.Substring($e)
}

$src            = Read-Lf $Source
$functionsBlock = Read-Lf (Join-Path $PSScriptRoot "winforge\wb-functions.ps1")
$assetsBlock    = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-assets.ps1")
$launcherBlock  = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-launcher.ps1")
$configBlock    = Read-Lf (Join-Path $PSScriptRoot "config\wb-config.ps1")
$auditBlock     = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-audit.ps1")
$profileBlock   = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-profile.ps1")
$driversBlock   = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-drivers.ps1")
$auditData      = Read-Lf (Join-Path $PSScriptRoot "config\wf-audit.ps1")
$xamlNav        = Read-Lf (Join-Path $PSScriptRoot "xaml\wb-xaml-nav.xml")
$xamlTab        = Read-Lf (Join-Path $PSScriptRoot "xaml\wb-xaml-tab.xml")

# ---------------------------------------------------------------- cabeçalho / parâmetros
$src = Replace-Once $src @'
<#
.NOTES
    Author         : Chris Titus @christitustech
    Runspace Author: @DeveloperDurp
    GitHub         : https://github.com/ChrisTitusTech
    Version        : 26.08.19
#>
'@ @'
<#
.SYNOPSIS
    WinForge - ferramenta de otimização para Windows 10 e 11.

.DESCRIPTION
    Construída sobre um utilitário de código aberto (base 26.08.19, licença MIT - ver NOTICE), com:
      - pergunta opcional de Ponto de Restauração ao abrir (-RestorePoint / -NoRestorePoint)
      - recursos exclusivos do Windows 11 ocultos automaticamente no Windows 10
      - aba "Jogos" (prioridade de CPU por jogo, GameDVR, MMCSS, GPU NVIDIA/AMD/Intel)
      - tweaks e manutenção do repositório "Windows Boost - Essential" reescritos com Desfazer
        (energia, serviços, anúncios, Cortana, pesquisa, VBS, limpeza, backup do registro,
         cache de RAM, otimização de unidades, shader cache)

.PARAMETER RestorePoint
    Cria o ponto de restauração ao abrir, sem perguntar.
.PARAMETER NoRestorePoint
    Não pergunta nem cria ponto de restauração ao abrir.
.PARAMETER SelfTest
    Valida configurações e XAML e sai (não exige administrador).
.PARAMETER NoElevation
    Abre a interface sem exigir administrador (só para testar a interface; os tweaks falham sem admin).
.PARAMETER ReadyEvent
    Nome do EventWaitHandle que o WinForge.exe cria para saber quando a janela apareceu (fecha o splash).
.PARAMETER Console
    Reservado para o launcher (WinForge.exe): mantém o console visível; sem efeito ao rodar o .ps1 diretamente.
.PARAMETER HardwareRender
    Usa renderização WPF por hardware (padrão: software, mais compatível com drivers/overlays).

.NOTES
    WinForge __VERSION__
    Autor          : Rafael Favero
    Base           : versão 26.08.19 do projeto original (MIT) - ver NOTICE
#>
'@.Replace('__VERSION__', $Version) "cabeçalho"

$src = Replace-Once $src @'
    [switch]$Offline
)
'@ @'
    [switch]$Offline,
    [switch]$RestorePoint,
    [switch]$NoRestorePoint,
    [switch]$SelfTest,
    [switch]$NoElevation,
    [string]$ReadyEvent,
    [switch]$Console,
    [switch]$HardwareRender
)
'@ "param block"

$src = Replace-Once $src 'Write-Host "WinUtil is unable to run on your system. PowerShell execution is restricted by security policies." -ForegroundColor Red' 'Write-Host "O WinForge não pode rodar neste sistema: a execução do PowerShell está restrita por política de segurança (Constrained Language Mode)." -ForegroundColor Red' "msg language mode"

$src = Replace-Once $src 'if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {' 'if (-not $SelfTest -and -not $NoElevation -and !([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {' "admin check"

$src = Replace-Once $src 'Write-Output "WinUtil needs to be run as Administrator. Attempting to relaunch."' 'Write-Output "O WinForge precisa ser executado como Administrador. Reabrindo com elevação..."' "msg admin"

# ---------------------------------------------------------------- $sync inicial
$src = Replace-Once $src '$sync.version = "26.08.19"' ("`$sync.version = `"$Version`"`n`$sync.baseVersion = `"26.08.19`"") "version"

$src = Insert-After $src '$sync.currentTab = "Install"' @'

# WinForge
$sync.ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
$sync.ForceRestorePoint = [bool]$RestorePoint
$sync.NoRestorePointPrompt = [bool]$NoRestorePoint
$sync.RestorePointCreated = $false
$sync.ReadyEventName = $ReadyEvent
'@ "sync init"

$src = Replace-Once $src '$winutildir = "$env:LocalAppData\winutil"' '$winutildir = "$env:LocalAppData\WinForge"' "winutildir"
$src = Replace-Once $src '$sync.logPath = "$logdir\winutil_$dateTime.log"' '$sync.logPath = "$logdir\WinForge_$dateTime.log"' "logPath"
$src = Replace-Once $src '$Host.UI.RawUI.WindowTitle = "WinUtil"' '$Host.UI.RawUI.WindowTitle = "WinForge"' "window title console"

# ---------------------------------------------------------------- funções e configs
$src = Insert-Before $src "`$sync.configs.applications = @'" ($functionsBlock.TrimEnd() + "`n`n") "insert functions"
$src = Insert-Before $src "`$inputXML = @'" ($configBlock.TrimEnd() + "`n`n") "insert config"
$src = Insert-Before $src "`$inputXML = @'" ($auditData.TrimEnd() + "`n`n") "insert audit data"

# ---------------------------------------------------------------- logo
$src = Insert-Before $src "`$sync.configs.applications = @'" ($assetsBlock.TrimEnd() + "`n`n") "insert assets"

# ---------------------------------------------------------------- integração com o launcher (WinForge.exe)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($launcherBlock.TrimEnd() + "`n`n") "insert launcher"

# ---------------------------------------------------------------- auditoria de risco (aplicação)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($auditBlock.TrimEnd() + "`n`n") "insert audit functions"

# ---------------------------------------------------------------- perfil do sistema (detecção)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($profileBlock.TrimEnd() + "`n`n") "insert profile"

# ---------------------------------------------------------------- consulta de drivers (rede)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($driversBlock.TrimEnd() + "`n`n") "insert drivers"

# troca os três paths do logo original pelos quatro paths do WinForge (caso 'logo' de Invoke-WinUtilAssets)
$src = Replace-Between $src '          $LogoPathData1 = @"' '          $canvas.Children.Add($LogoPath1) | Out-Null' @'
          $wfLogoPaths = Get-WinForgeLogoPaths

'@ "logo paths"

$src = Replace-Once $src @'
          $canvas.Children.Add($LogoPath1) | Out-Null
          $canvas.Children.Add($LogoPath2) | Out-Null
          $canvas.Children.Add($LogoPath3) | Out-Null
'@ @'
          foreach ($wfPath in $wfLogoPaths) { $canvas.Children.Add($wfPath) | Out-Null }
'@ "logo add"

# ---------------------------------------------------------------- filtro de compatibilidade na UI
$src = Replace-Once $src @'
    foreach ($entry in $configHashtable.Keys) {
        $entryInfo = $configHashtable[$entry]

'@ @'
    foreach ($entry in $configHashtable.Keys) {
        $entryInfo = $configHashtable[$entry]

        # WinForge: oculta entradas que não se aplicam a este Windows (10/11) ou à GPU detectada
        if (-not (Test-WinUtilBoostEntryCompatible $entryInfo)) { continue }

'@ "UI compat filter"

$src = Replace-Once $src @'
                        [System.Windows.Automation.AutomationProperties]::SetName($button, $entryInfo.Content)
                        $stackPanelContainer.Children.Add($button) | Out-Null
'@ @'
                        [System.Windows.Automation.AutomationProperties]::SetName($button, $entryInfo.Content)
                        if ($entryInfo.Description) { $button.ToolTip = $entryInfo.Description }
                        $stackPanelContainer.Children.Add($button) | Out-Null
'@ "button tooltip"

# ---------------------------------------------------------------- filtro de compatibilidade nas seleções (presets/import)
$src = Replace-Once $src @'
        $nextSelections[$listName].Add($cbkey)
    }
'@ @'
        # WinForge: ignora seleções que não se aplicam a este Windows/GPU (ex.: tweaks só do Windows 11 rodando no 10)
        $selectionEntry = switch ($listName) {
            'selectedTweaks'   { $sync.configs.tweaks.$cbkey }
            'selectedToggles'  { $sync.configs.tweaks.$cbkey }
            'selectedFeatures' { $sync.configs.feature.$cbkey }
            'selectedAppx'     { $sync.configs.appxHashtable[$cbkey] }
            default            { $null }
        }
        if (-not (Test-WinUtilBoostEntryCompatible $selectionEntry)) {
            Write-WinUtilLog -Component "Boost" -Message "Seleção '$cbkey' ignorada: não se aplica a $($sync.OSName) / GPU detectada."
            continue
        }

        $nextSelections[$listName].Add($cbkey)
    }
'@ "selection compat filter"

$src = Replace-Once $src @'
                foreach ($checkboxName in $completedOperation.Checkboxes) {
                    $sync.$checkboxName.ischecked = $True
                }
'@ @'
                foreach ($checkboxName in $completedOperation.Checkboxes) {
                    if ($sync.$checkboxName) { $sync.$checkboxName.ischecked = $True }
                }
'@ "get installed guard"

# ---------------------------------------------------------------- aba Jogos: inicialização, navegação, busca
$src = Replace-Once $src @'
        "Tweaks" {
            Invoke-WPFUIElements -configVariable $sync.configs.tweaks -targetGridName "tweakspanel" -columncount 2
        }
'@ @'
        "Tweaks" {
            Invoke-WPFUIElements -configVariable (Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Jogos" -Exclude) -targetGridName "tweakspanel" -columncount 2
        }
        "Jogos" {
            Invoke-WPFUIElements -configVariable (Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Jogos") -targetGridName "gamespanel" -columncount 2
        }
'@ "tab init"

$src = Replace-Once $src @'
    } elseif ($sync.currentTab -eq "AppX") {
        # Reset AppX tab filter
        Find-TweaksByNameOrDescription -SearchString ""
    }
'@ @'
    } elseif ($sync.currentTab -eq "AppX") {
        # Reset AppX tab filter
        Find-TweaksByNameOrDescription -SearchString ""
    } elseif ($sync.currentTab -eq "Jogos") {
        Find-TweaksByNameOrDescription -SearchString ""
    }
'@ "tab filter reset"

$src = Replace-Once $src 'if ($tabNumber -eq 0 -or $tabNumber -eq 1 -or $tabNumber -eq 5) {' 'if ($tabNumber -eq 0 -or $tabNumber -eq 1 -or $tabNumber -eq 5 -or $tabNumber -eq 6) {' "search visibility"

$src = Replace-Once $src @'
    $panelName = "tweakspanel"
    if ($null -ne $Sync.currentTab -and $Sync.currentTab -eq "AppX") {
        $panelName = "appxpanel"
    }
'@ @'
    $panelName = "tweakspanel"
    if ($null -ne $Sync.currentTab -and $Sync.currentTab -eq "AppX") {
        $panelName = "appxpanel"
    } elseif ($null -ne $Sync.currentTab -and $Sync.currentTab -eq "Jogos") {
        $panelName = "gamespanel"
    }
'@ "search panel"

$src = Replace-Once $src @'
        "AppX" {
            Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text
        }
    }
})
'@ @'
        "AppX" {
            Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text
        }
        "Jogos" {
            Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text
        }
    }
})
'@ "search timer"

$src = Replace-Once $src '            "W" { Invoke-WPFButton "WPFTab5BT"; $keyEventArgs.Handled = $true } # Navigate to Win11ISO tab' @'
            "W" { Invoke-WPFButton "WPFTab5BT"; $keyEventArgs.Handled = $true } # Navigate to Win11ISO tab
            "J" { Invoke-WPFButton "WPFTab7BT"; $keyEventArgs.Handled = $true } # WinForge: aba Jogos
'@.TrimEnd() "alt+j"

# ---------------------------------------------------------------- botões: lookup em tweaks + novos casos
$src = Replace-Once $src @'
    if ($sync.configs.feature.$Button) {
        $buttonConfig = $sync.configs.feature.$Button

'@ @'
    $buttonConfig = $null
    if ($sync.configs.feature.$Button) {
        $buttonConfig = $sync.configs.feature.$Button
    } elseif ($sync.configs.tweaks.$Button -and $sync.configs.tweaks.$Button.Type -eq "Button") {
        # WinForge: botões definidos na config de tweaks (aba Jogos)
        $buttonConfig = $sync.configs.tweaks.$Button
    }
    if ($buttonConfig) {

'@ "button lookup"

$src = Insert-After $src '        "WPFAdvanced" {Invoke-WPFPresets "Advanced" -checkboxfilterpattern "WPFTweak*"}' @'

        "WPFPresetWinForge" {Invoke-WPFPresets "WinForge" -checkboxfilterpattern "WPFTweak*"}
        "WPFPresetGamer" {Invoke-WPFPresets "Gamer" -checkboxfilterpattern "WPFTweak*"}
        "WPFClearGamesSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFTweak*"}
        "WPFGetInstalledGames" {Invoke-WPFGetInstalled -CheckBox "tweaks"}
        "WPFGamesApplyButton" {Invoke-WPFtweaksbutton}
        "WPFGamesUndoButton" {Invoke-WPFundoall}
        "WPFAppxWinForgeSelection" {Invoke-WPFPresets "AppxWinForge" -checkboxfilterpattern "WPFAppx*"}
'@.TrimEnd() "button switch"

# ---------------------------------------------------------------- preset vazio: não chamar Update-WinUtilSelections
# A auditoria pode esvaziar um preset (todos os itens viraram Cuidado/Removido). Sem esta guarda,
# Update-WinUtilSelections receberia $null no parâmetro obrigatório [string[]]$flatJson e lançaria erro.
$src = Replace-Once $src @'
    if ($preset) {
        Update-WinUtilSelections -flatJson $CheckBoxesToCheck
    }
'@ @'
    if ($preset -and @($CheckBoxesToCheck).Count -gt 0) {
        Update-WinUtilSelections -flatJson $CheckBoxesToCheck
    }
'@ "preset vazio"

# ---------------------------------------------------------------- ponto de restauração: não duplicar na mesma sessão
$src = Insert-After $src @'
  $tweaksToRun = @($Tweaks | Where-Object { $_ -ne $restorePointTweak })
  $totalSteps = [Math]::Max($Tweaks.Count, 1)
'@ @'

  if ($restorePointSelected -and $sync.RestorePointCreated) {
    Write-Host "Ponto de restauração já criado nesta sessão - não será criado outro." -ForegroundColor Yellow
    Write-WinUtilLog -Component "Tweaks" -Message "Restore point already created this session; skipping duplicate creation."
    $restorePointSelected = $false
    $totalSteps = [Math]::Max($tweaksToRun.Count, 1)
  }
'@.TrimEnd() "restore point skip"

$src = Insert-After $src '    Invoke-WinUtilTweaks $restorePointTweak' "`n    `$sync.RestorePointCreated = `$true" "restore point flag"

# ---------------------------------------------------------------- banner de inicialização
$src = Replace-Between $src "Write-Host @`"`n    CCCCCCCCCCCCC" "# Load the configuration files" @'
Get-WinUtilBoostSystemInfo
$wbGpuText = if ($sync.GPUNames -and $sync.GPUNames.Count -gt 0) { $sync.GPUNames -join ' | ' } else { 'não detectada' }
Write-Host @"

__        __ _         _____
\ \      / /(_) _ __  |  ___|  ___   _ __   __ _   ___
 \ \ /\ / / | || '_ \ | |_    / _ \ | '__| / _`` | / _ \
  \ V  V /  | || | | ||  _|  | (_) || |   | (_| ||  __/
   \_/\_/   |_||_| |_||_|     \___/ |_|    \__, | \___|
                                           |___/

  WinForge $($sync.version)  -  base: $($sync.baseVersion) (MIT, ver NOTICE)
  Sistema: $($sync.OSName) $($sync.OSDisplayVersion) (build $($sync.OSBuild))
  GPU    : $wbGpuText
  Log    : $($sync.logPath)

"@

'@ "banner"

# ---------------------------------------------------------------- mescla das configs + SelfTest
$src = Replace-Once $src @'
$sync.configs.appxHashtable = @{}
$sync.configs.appx.PSObject.Properties | ForEach-Object {
    $sync.configs.appxHashtable[$_.Name] = $_.Value
}
$sync.preferences.theme = "Auto"
'@ @'
$sync.configs.appxHashtable = @{}
$sync.configs.appx.PSObject.Properties | ForEach-Object {
    $sync.configs.appxHashtable[$_.Name] = $_.Value
}

# WinForge: mescla tweaks/botões/presets/jogos e marca recursos só do Windows 11
Initialize-WinUtilBoostConfigs

# WinForge: aplica a classificação de risco (Seguro/Cuidado/Removido) em tweaks e presets
Initialize-WinForgeAudit

if ($SelfTest) {
    Write-Host "== WinForge SelfTest =="
    $wbErrors = 0
    foreach ($p in $sync.configs.preset.PSObject.Properties) {
        foreach ($k in @($p.Value)) {
            $known = ($null -ne $sync.configs.tweaks.PSObject.Properties[$k]) -or $sync.configs.appxHashtable.ContainsKey($k) -or ($null -ne $sync.configs.feature.PSObject.Properties[$k]) -or $sync.configs.applicationsHashtable.ContainsKey($k)
            if (-not $known) { Write-Host "  [ERRO] preset $($p.Name): chave desconhecida '$k'" -ForegroundColor Red; $wbErrors++ }
        }
    }
    foreach ($t in $sync.configs.tweaks.PSObject.Properties) {
        $e = $t.Value
        foreach ($r in @($e.registry)) {
            if ($null -eq $r) { continue }
            if ($r.PSObject.Properties['Values']) { continue }
            if (-not $r.Path -or -not $r.Name -or $null -eq $r.Value -or -not $r.Type -or $null -eq $r.OriginalValue) { Write-Host "  [ERRO] $($t.Name): entrada de registro incompleta ($($r.Path)\$($r.Name))" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($s in @($e.service)) {
            if ($null -eq $s) { continue }
            if (-not $s.Name -or -not $s.StartupType -or -not $s.OriginalType) { Write-Host "  [ERRO] $($t.Name): entrada de serviço incompleta" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($s in (@($e.InvokeScript) + @($e.UndoScript))) {
            if ([string]::IsNullOrWhiteSpace($s)) { continue }
            try { [scriptblock]::Create($s) | Out-Null } catch { Write-Host "  [ERRO] $($t.Name): script inválido: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++ }
        }
        if ($e.function -and -not (Get-Command $e.function -ErrorAction SilentlyContinue)) { Write-Host "  [ERRO] $($t.Name): função '$($e.function)' não existe" -ForegroundColor Red; $wbErrors++ }
    }
    foreach ($t in $sync.configs.feature.PSObject.Properties) {
        $e = $t.Value
        if ($e.function -and -not (Get-Command $e.function -ErrorAction SilentlyContinue)) { Write-Host "  [ERRO] feature $($t.Name): função '$($e.function)' não existe" -ForegroundColor Red; $wbErrors++ }
        foreach ($s in @($e.InvokeScript)) {
            if ([string]::IsNullOrWhiteSpace($s)) { continue }
            try { [scriptblock]::Create($s) | Out-Null } catch { Write-Host "  [ERRO] feature $($t.Name): script inválido: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++ }
        }
    }
    $wbTweaksTab = Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Jogos" -Exclude
    $wbGamesTab  = Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Jogos"
    $wbHidden = @($sync.configs.tweaks.PSObject.Properties | Where-Object { -not (Test-WinUtilBoostEntryCompatible $_.Value) } | ForEach-Object { $_.Name })
    $wbHiddenAppx = @($sync.configs.appx.PSObject.Properties | Where-Object { -not (Test-WinUtilBoostEntryCompatible $_.Value) } | ForEach-Object { $_.Name })
    Write-Host "  Sistema: $($sync.OSName) $($sync.OSDisplayVersion) build $($sync.OSBuild) | GPU: $(if ($sync.GPUVendors.Count) { $sync.GPUVendors -join ',' } else { 'nenhuma' })"
    Write-Host "  Entradas -> aba Tweaks: $(@($wbTweaksTab.PSObject.Properties).Count) | aba Jogos: $(@($wbGamesTab.PSObject.Properties).Count) | Config: $(@($sync.configs.feature.PSObject.Properties).Count) | AppX: $(@($sync.configs.appx.PSObject.Properties).Count) | Presets: $(@($sync.configs.preset.PSObject.Properties).Count)"
    # trava de contagem: pega regex da limpeza de marca que coma entradas demais quando o arquivo base mudar
    if (@($sync.configs.feature.PSObject.Properties).Count -ne 42) { Write-Host "  [ERRO] Config: esperado 42 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbTweaksTab.PSObject.Properties).Count -ne 83) { Write-Host "  [ERRO] aba Tweaks: esperado 83 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbGamesTab.PSObject.Properties).Count -ne 84) { Write-Host "  [ERRO] aba Jogos: esperado 84 entradas" -ForegroundColor Red; $wbErrors++ }
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
    # a auditoria remove itens dos presets; um preset vazio depende da guarda em Invoke-WPFPresets para não estourar
    foreach ($p in $sync.configs.preset.PSObject.Properties) {
        if (@($p.Value).Count -eq 0) { Write-Host "  [ERRO] preset vazio: $($p.Name)" -ForegroundColor Red; $wbErrors++ }
    }
    foreach ($k in @($sync.WinForgeAudit.Keys | Where-Object { $sync.WinForgeAudit[$_].Class -eq 'Removido' })) {
        if ($sync.configs.tweaks.PSObject.Properties[$k]) { Write-Host "  [ERRO] $k deveria ter sido removido" -ForegroundColor Red; $wbErrors++ }
    }
    $wbCuidado = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.risk -eq 'cuidado' }).Count
    $wbSeguro  = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.risk -eq 'seguro' }).Count
    Write-Host "  Auditoria: $wbSeguro Seguro, $wbCuidado Cuidado, $(@($sync.WinForgeAudit.Keys | Where-Object { $sync.WinForgeAudit[$_].Class -eq 'Removido' }).Count) Removido"
    Write-Host "  Ocultos neste sistema (tweaks): $($wbHidden.Count) -> $($wbHidden -join ', ')"
    Write-Host "  Ocultos neste sistema (appx)  : $($wbHiddenAppx.Count) -> $($wbHiddenAppx -join ', ')"
    # Perfil do sistema: toda área tem de existir, o resultado tem de sobreviver ao ConvertTo-Json
    # (nada de objeto CIM escondido) e as simulações têm de devolver o mesmo formato.
    $wbProfile = Get-WinForgeSystemProfile -SkipNetwork
    foreach ($area in 'OS','Machine','CPU','RAM','GPU','Storage','Network','Power','State','Drivers') { if ($null -eq $wbProfile[$area]) { Write-Host "  [ERRO] perfil sem área $area" -ForegroundColor Red; $wbErrors++ } }
    if ($wbProfile.Errors.Count) { Write-Host "  Perfil: avisos -> $($wbProfile.Errors -join '; ')" }
    $null = $wbProfile | ConvertTo-Json -Depth 6 -Compress   # serializável
    Write-Host "  Perfil: $($wbProfile.OS.Caption) | $($wbProfile.CPU.Name) | RAM $($wbProfile.RAM.TotalGB) GB | GPU $(@($wbProfile.GPU | ForEach-Object { $_.Name }) -join ', ') | SSD=$($wbProfile.Storage.HasSSD) HDD=$($wbProfile.Storage.HasHDD) | laptop=$($wbProfile.Machine.IsLaptop) vm=$($wbProfile.Machine.IsVirtual) | drivers=$($wbProfile.Drivers.Count)"
    foreach ($sim in 'laptop','vm','server-iis','hdd','win10') {
        try {
            $sp = Get-WinForgeSimulatedProfile -Name $sim
            if ($sp.Simulated -ne $sim) { Write-Host "  [ERRO] simulação $sim" -ForegroundColor Red; $wbErrors++ }
        } catch { Write-Host "  [ERRO] simulação $sim`: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++ }
    }
    if ((ConvertTo-WinForgeNvidiaVersion '32.0.16.1656') -ne '616.56' -or (ConvertTo-WinForgeNvidiaVersion '32.0.15.6636') -ne '566.36') { Write-Host "  [ERRO] ConvertTo-WinForgeNvidiaVersion" -ForegroundColor Red; $wbErrors++ }
    # Consulta de drivers: a parte que não depende de rede roda sempre.
    foreach ($wbPair in @(@('NVIDIA GeForce RTX 3070', '30'), @('NVIDIA GeForce GTX 1660 SUPER', '16'), @('NVIDIA GeForce GTX 970M', '900M'), @('NVIDIA GeForce MX450', 'MX400'))) {
        if ((Get-WinForgeNvidiaSeriesToken $wbPair[0]) -ne $wbPair[1]) { Write-Host "  [ERRO] série NVIDIA de '$($wbPair[0])': esperado $($wbPair[1])" -ForegroundColor Red; $wbErrors++ }
    }
    if ((Get-WinForgeNvidiaSeriesNameToken 'GeForce RTX 30 Series') -ne '30' -or (Get-WinForgeNvidiaSeriesNameToken 'GeForce GTX 16 Series (Notebooks)') -ne '16') { Write-Host "  [ERRO] Get-WinForgeNvidiaSeriesNameToken" -ForegroundColor Red; $wbErrors++ }
    if (-not (Get-WinForgeVendorDriverUrl -Vendor 'nvidia')) { Write-Host "  [ERRO] Get-WinForgeVendorDriverUrl nvidia sem URL" -ForegroundColor Red; $wbErrors++ }
    if ((Get-WinForgeVendorDriverUrl -Vendor 'other' -Profile @{ Machine = @{ Manufacturer = 'ASUSTeK COMPUTER INC.' } }) -notmatch 'asus\.com') { Write-Host "  [ERRO] Get-WinForgeVendorDriverUrl OEM" -ForegroundColor Red; $wbErrors++ }
    if ($null -ne (Get-WinForgeVendorDriverUrl -Vendor 'other' -Profile @{ Machine = @{ Manufacturer = 'Fabricante Desconhecido' } })) { Write-Host "  [ERRO] Get-WinForgeVendorDriverUrl: OEM desconhecido deveria ser nulo" -ForegroundColor Red; $wbErrors++ }
    # A simulação 'vm' não tem GPU NVIDIA: Update não pode consultar rede nem mexer no LatestStatus.
    $wbVm = Get-WinForgeSimulatedProfile -Name 'vm'
    $wbVmBefore = @($wbVm.GPU | ForEach-Object { $_.LatestStatus }) -join '|'
    Update-WinForgeProfileDriverStatus -Profile $wbVm
    if ((@($wbVm.GPU | ForEach-Object { $_.LatestStatus }) -join '|') -ne $wbVmBefore) { Write-Host "  [ERRO] Update-WinForgeProfileDriverStatus mexeu em GPU não-NVIDIA" -ForegroundColor Red; $wbErrors++ }
    $wbSemUrl = @($wbVm.Drivers | Where-Object { $_.Vendor -in @('nvidia','amd','intel','realtek','logitech') -and -not $_.Url })
    if ($wbSemUrl.Count) { Write-Host "  [ERRO] drivers sem URL de fabricante: $(@($wbSemUrl | ForEach-Object { $_.Device }) -join ', ')" -ForegroundColor Red; $wbErrors++ }
    Write-Host "  Drivers: $(@($wbVm.Drivers | Where-Object Url).Count)/$($wbVm.Drivers.Count) com link de fabricante | status: $(@($wbVm.Drivers | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')"
    if ($env:WINFORGE_SELFTEST_NETWORK -eq '1') {
        $wbNv = Get-WinForgeNvidiaLatestDriver -GpuName 'NVIDIA GeForce RTX 3070'
        Write-Host "  NVIDIA (rede): status=$($wbNv.Status) versão=$($wbNv.Version) lançamento=$($wbNv.ReleaseDate)"
        if ($wbNv.Status -ne 'ok' -or $wbNv.Version -notmatch '^\d{3}\.\d{2}$') { Write-Host "  [ERRO] Get-WinForgeNvidiaLatestDriver: esperado status 'ok' e versão no formato 000.00" -ForegroundColor Red; $wbErrors++ }
    }
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
        [xml]$wbXaml = $inputXML
        $wbReader = New-Object System.Xml.XmlNodeReader $wbXaml
        $wbWindow = [Windows.Markup.XamlReader]::Load($wbReader)
        $wbTabs = @($wbWindow.FindName("WPFTabNav").Items | ForEach-Object { $_.Header })
        Write-Host "  XAML: OK - abas: $($wbTabs -join ', ')"
        foreach ($n in 'gamespanel','WPFTab7BT','WPFPresetWinForge','WPFPresetGamer','WPFAppxWinForgeSelection','WPFGamesApplyButton','WPFGamesUndoButton') {
            if ($null -eq $wbWindow.FindName($n)) { Write-Host "  [ERRO] XAML: elemento '$n' não encontrado" -ForegroundColor Red; $wbErrors++ }
        }
        # monta cada aba sem mostrar a janela (exercita Invoke-WPFUIElements, filtros, toggles e botões)
        $sync["Form"] = $wbWindow
        $wbXaml.SelectNodes("//*[@Name]") | ForEach-Object { $sync["$($_.Name)"] = $sync["Form"].FindName($_.Name) }
        $sync.InitializedTabs = @{}
        foreach ($tab in 'Install','Tweaks','Jogos','Config','AppX') {
            try {
                Initialize-WinUtilTabContent -TabName $tab
                $panel = switch ($tab) { 'Install' { 'appspanel' } 'Tweaks' { 'tweakspanel' } 'Jogos' { 'gamespanel' } 'Config' { 'featurespanel' } 'AppX' { 'appxpanel' } }
                $grid = $wbWindow.FindName($panel)
                $cbs = @($sync.Keys | Where-Object { $sync[$_] -is [System.Windows.Controls.CheckBox] }).Count
                Write-Host "  Aba $tab montada: $($grid.Children.Count) coluna(s), $cbs checkboxes/toggles no total até agora"
            } catch {
                Write-Host "  [ERRO] montar aba $tab`: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
            }
        }
        $wbLogo = Invoke-WinForgeAssets -Type "logo" -Size 25
        if ($null -eq $wbLogo -or @($wbLogo.Child.Children).Count -ne 4) { Write-Host "  [ERRO] logo: esperado 4 paths no canvas" -ForegroundColor Red; $wbErrors++ } else { Write-Host "  Logo: OK" }
        foreach ($n in 'WPFTweaksWBGameCS2','WPFTweaksWBGameDVR','WPFToggleWBHAGS','WPFTweaksWBPowerSettings','WPFPanelWBClearRam','WPFTweaksWBNvidiaShaderCache') {
            if ($null -eq $sync[$n]) { Write-Host "  [ERRO] controle '$n' não foi criado" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($n in @($wbHidden) + @($wbHiddenAppx)) {
            if ($null -ne $sync[$n]) { Write-Host "  [ERRO] controle oculto '$n' foi criado mesmo assim" -ForegroundColor Red; $wbErrors++ }
        }
        try {
            Invoke-WPFPresets "Gamer" -checkboxfilterpattern "WPFTweak*"
            Write-Host "  Preset Gamer: $($sync.selectedTweaks.Count) tweaks selecionados -> $($sync.selectedTweaks -join ', ')"
            Invoke-WPFPresets "AppxWinForge" -checkboxfilterpattern "WPFAppx*"
            Write-Host "  Preset AppxWinForge: $($sync.selectedAppx.Count) pacotes selecionados"
        } catch {
            Write-Host "  [ERRO] presets: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
    } catch {
        Write-Host "  [ERRO] XAML: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    Write-Host "== SelfTest concluído: $wbErrors erro(s) =="
    Stop-Transcript | Out-Null
    exit $wbErrors
}

$sync.preferences.theme = "Auto"
'@ "config merge + selftest"

# ---------------------------------------------------------------- modo de renderização WPF (software por padrão)
$src = Replace-Once $src @'
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML
'@ @'
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')

# WinForge: renderização por software por padrão (imune a hooks de D3D9/overlays/drivers quebrados em máquinas em reparo)
if (-not $HardwareRender) {
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')
    [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly
    Write-WinUtilLog -Component "UI" -Message "Renderização WPF: software (use -HardwareRender para GPU)."
} else {
    Write-WinUtilLog -Component "UI" -Message "Renderização WPF: hardware."
}

[xml]$XAML = $inputXML
'@ "render mode"

# ---------------------------------------------------------------- export: comando copiado para a área de transferência
$src = Replace-Once $src '"iex ""& { `$(irm https://christitus.com/win) } -Config ''$Config''""" | Set-Clipboard' '"& ''$(Join-Path $sync.ScriptRoot ''WinForge.ps1'')'' -Config ''$Config''" | Set-Clipboard' "export clipboard"

# ---------------------------------------------------------------- título da janela, sobre, créditos, pergunta do ponto de restauração
$src = Replace-Once $src '$sync["Form"].title = $sync["Form"].title + " " + $sync.version' '$sync["Form"].title = $sync["Form"].title + " " + $sync.version + "  -  " + $sync.OSName + " " + $sync.OSDisplayVersion' "form title"

$src = Replace-Between $src '$sync["AboutMenuItem"].Add_Click({' '$sync["DocumentationMenuItem"].Add_Click({' @'
$sync["AboutMenuItem"].Add_Click({
    Invoke-WPFPopup -Action "Hide" -Popups @("Settings")
    Show-WinUtilBoostAbout
})

'@ "about"

$src = Replace-Between $src '$sync["SponsorMenuItem"].Add_Click({' '# Font Scaling Event Handlers' @'
$sync["SponsorMenuItem"].Add_Click({
    Invoke-WPFPopup -Action "Hide" -Popups @("Settings")
    Show-WinUtilBoostCredits
})

'@ "credits"

$src = Insert-After $src '    $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ Initialize-WinUtilTaskbarOverlayAssets -IncludeLogo $false -IncludeStatusAssets $true }) | Out-Null' @'

    # WinForge: avisa o launcher que a janela apareceu (fecha o splash)
    Send-WinForgeReady

    # WinForge: pergunta (opcional) sobre ponto de restauração depois que a janela aparece
    $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [action]{ Invoke-WinUtilBoostRestorePointPrompt }) | Out-Null
'@.TrimEnd() "restore prompt hook"

# ---------------------------------------------------------------- falha ao carregar o XAML: libera o launcher e sai com 2
$src = Replace-Once $src @'
    Write-Host "Quitting WinUtil..." -ForegroundColor Red
    Close-WinUtilRunspacePool
    [System.GC]::Collect()
    exit 1
'@ @'
    Write-Host "Quitting WinUtil..." -ForegroundColor Red
    Close-WinUtilRunspacePool
    [System.GC]::Collect()
    Send-WinForgeReady -Failed
    exit 2
'@ "xaml failure exit"

$src = Replace-Once $src '    $winutilTextBlock.Text = "WinUtil"' '    $winutilTextBlock.Text = "WinForge"' "dialog logo text"

# links file:// nos diálogos (NOTICE.txt dos Créditos): abre pelo caminho local, sem %20 na URL
$src = Replace-Once $src 'Start-Process $eventSender.NavigateUri.AbsoluteUri' 'if ($eventSender.NavigateUri.IsFile) { Start-Process $eventSender.NavigateUri.LocalPath } else { Start-Process $eventSender.NavigateUri.AbsoluteUri }' "dialog file link"

# ---------------------------------------------------------------- XAML
$src = Replace-Once $src '        Title="WinUtil">' '        Title="WinForge">' "xaml title"
$src = Replace-Once $src 'Header="Sponsors" Name="SponsorMenuItem"' 'Header="Créditos" Name="SponsorMenuItem"' "xaml sponsors"
$src = Replace-Once $src 'Header="Documentation" Name="DocumentationMenuItem"' 'Header="Documentação" Name="DocumentationMenuItem"' "xaml docs"
$src = Replace-Once $src 'Header="About" Name="AboutMenuItem"' 'Header="Sobre" Name="AboutMenuItem"' "xaml about"

$src = Insert-Before $src @'
                <ToggleButton Style="{StaticResource TabToggleButton}" Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"
                    Background="{DynamicResource ButtonConfigBackgroundColor}"
'@ $xamlNav "xaml nav button"

$src = Insert-Before $src "        </TabControl>`n" $xamlTab "xaml games tab"

$src = Insert-After $src '                                    <Button Name="WPFAdvanced" Content=" Advanced " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>' @'

                                    <Button Name="WPFPresetWinForge" Content=" WinForge " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}" ToolTip="Preset Standard + serviços seguros, anúncios, Cortana, pesquisa, NTFS, energia e hibernação (WinForge)."/>
'@.TrimEnd() "xaml preset button"

$src = Insert-After $src '                                    <Button Name="WPFDefaultAppxSelection" Content=" Default " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>' @'

                                    <Button Name="WPFAppxWinForgeSelection" Content=" WinForge " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}" ToolTip="Seleção equivalente ao 'REMOVA TUDO DE UMA VEZ SÓ' do Windows Boost (sem a Microsoft Store)."/>
'@.TrimEnd() "xaml appx preset button"

# ---------------------------------------------------------------- remoção de referências ao projeto original (antes do rename global)
# 1) links de documentação nas configs JSON (o glifo "(?)" some junto)
$src = [regex]::Replace($src, ',\n\s*"link": "https://winutil\.christitus\.com[^"]*"', '')
$src = [regex]::Replace($src, '\n\s*"link": "https://winutil\.christitus\.com[^"]*",', "`n")
# 2) menu Documentação -> README do WinForge
$src = Replace-Once $src 'Start-Process "https://winutil.christitus.com/"' 'Start-Process "https://github.com/RafaelGFavero/WinForge#readme"' "docs url"
# 3) relaunch sem arquivo (irm do repositório original) -> mensagem
$src = Replace-Once $src '"&([ScriptBlock]::Create((irm https://github.com/ChrisTitusTech/winutil/releases/latest/download/winutil.ps1))) $($argList -join '' '')"' '"Write-Host ''Execute o WinForge a partir do arquivo WinForge.exe ou WinForge.ps1.''"' "relaunch url"
# 4) função de sponsors (o único chamador está no bloco de créditos, já substituído acima)
$src = Replace-Between $src 'Function Invoke-WinUtilSponsors {' 'function Invoke-WinUtilSSHServer {' '' "remove sponsors fn"
$src = $src -replace 'SponsorMenuItem', 'CreditsMenuItem'
# 5) perfil PowerShell do projeto original: entradas da aba Config
$src = [regex]::Replace($src, '(?s)\s*"WPFWinUtilInstallPSProfile": \{.*?\n  \},', '')
$src = [regex]::Replace($src, '(?s)\s*"WPFWinUtilUninstallPSProfile": \{.*?\n  \},', '')
$src = Replace-Once $src 'wt new-tab pwsh -NoExit -Command "irm https://github.com/ChrisTitusTech/powershell-profile/raw/main/setup.ps1 | iex"' 'Write-Host "Recurso removido no WinForge."' "profile installer"
$src = Replace-Once $src '    Write-Host "Successfully uninstalled CTT PowerShell Profile." -ForegroundColor Green' '    Write-Host "Recurso removido no WinForge." -ForegroundColor Yellow' "profile uninstall msg"
# 6) comentários/strings soltas
$src = $src -replace 'CTT logo preset:', 'logo preset:'
$src = $src -replace "Chris Titus Tech's Windows Utility", 'WinForge'

# ---------------------------------------------------------------- rename global WinUtil -> WinForge (funções, variáveis, strings, pastas)
# -creplace (sensível a maiúsculas): com -replace, o primeiro padrão comeria todas as grafias e
# produziria "WinForgeity" (de WinUtility) e "$WinForgedir" (de $winutildir).
$src = $src -creplace 'WinUtility', 'WinForge'   # clr-namespace do XAML
$src = $src -creplace 'WinUtil',    'WinForge'
$src = $src -creplace 'Winutil',    'WinForge'
$src = $src -creplace 'winutil',    'winforge'
$src = $src -replace  'winutil',    'winforge'   # rede de segurança para qualquer outra grafia

# ---------------------------------------------------------------- saída
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$outFile = Join-Path $OutDir "WinForge.ps1"
$final = $src -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($outFile, $final, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "Gerado: $outFile ($([math]::Round((Get-Item $outFile).Length / 1KB)) KB, $(($final -split "`r`n").Count) linhas)"

# verificação de sintaxe
$tokens = $null; $parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($outFile, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors -and $parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Host "  [PARSE] linha $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }
    throw "Erros de sintaxe no arquivo gerado."
}
Write-Host "Sintaxe PowerShell: OK"

# ---------------------------------------------------------------- teste de marca no motor gerado
# Antes de gerar o doc: uma falha de marca no motor e sobre o produto e tem de aparecer primeiro.
$brandTest = Join-Path $RepoRoot "tests\engine\Test-Brand.ps1"
if (-not $SkipBrandTest) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $brandTest -File $outFile
    if ($LASTEXITCODE -ne 0) { throw "Brand test falhou: $LASTEXITCODE ocorrência(s)." }
}

# ---------------------------------------------------------------- docs\auditoria.md (gerado)
# Fonte única: config\wf-audit.ps1. Os nomes visíveis vêm dos blocos JSON do arquivo gerado
# (tweaks da base + wbtweaks do WinForge) e da lista de jogos de config\wb-config.ps1.

# Dot-source de arquivo NAO serve aqui: o PowerShell 5.1 decodifica um .ps1 sem BOM pela code page
# ANSI, e config\wb-config.ps1 e UTF-8 sem BOM - "Ragnarök" chegaria como "RagnarÃ¶k" no doc.
# Ler o texto em UTF-8 e executar um scriptblock mantem o encoding independente do BOM.
function Get-ConfigScriptBlock([string]$relativePath) {
    $full = Join-Path $PSScriptRoot $relativePath
    $code = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
    return [scriptblock]::Create($code)
}

function Get-WinForgeAuditData {
    $sync = @{}
    . (Get-ConfigScriptBlock "config\wf-audit.ps1")
    return $sync
}

function Get-WinForgeConfigData {
    $sync = @{ configs = @{} }
    . (Get-ConfigScriptBlock "config\wb-config.ps1")
    return $sync
}

function Get-JsonConfigBlock([string]$text, [string]$name) {
    # o gerado traz: $sync.configs.<name> = @' ... '@ | ConvertFrom-Json
    $start = "`$sync.configs.$name = @'`n"
    $i = $text.IndexOf($start, [StringComparison]::Ordinal)
    if ($i -lt 0) { throw "Bloco JSON '$name' não encontrado no arquivo gerado." }
    $i += $start.Length
    $e = $text.IndexOf("`n'@ | ConvertFrom-Json", $i, [StringComparison]::Ordinal)
    if ($e -lt 0) { throw "Fim do bloco JSON '$name' não encontrado." }
    return ($text.Substring($i, $e - $i) | ConvertFrom-Json)
}

function Format-MdCell([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '—' }
    return ($s -replace '\|', '\|' -replace '\s+', ' ').Trim()
}

# Ordenacao ordinal (por ponto de codigo), nao a de Sort-Object, que depende da cultura da maquina:
# o mesmo commit tem de gerar o mesmo arquivo em qualquer locale.
# A sobrecarga Sort(keys, items, comparer) nao serve: sob o PowerShell 5.1 o segundo array chega
# por copia e $items volta na ordem original. Comparacao in-place sobre o proprio array e o unico
# jeito de o resultado sair ordenado; a virgula no return impede que o array seja desempacotado.
function Sort-RowsByKeyOrdinal([object[]]$rows) {
    $items = [object[]]@($rows)
    [array]::Sort($items, [System.Comparison[object]]{ param($a, $b) [System.StringComparer]::Ordinal.Compare([string]$a.Key, [string]$b.Key) })
    return ,$items
}

$auditSync  = Get-WinForgeAuditData
$audit      = $auditSync.WinForgeAudit
$configSync = Get-WinForgeConfigData
$jsonTweaks = @((Get-JsonConfigBlock $src 'tweaks'), (Get-JsonConfigBlock $src 'wbtweaks'))

function Get-TweakEntry([string]$key) {
    foreach ($o in $jsonTweaks) {
        $p = $o.PSObject.Properties[$key]
        if ($p) { return $p.Value }
    }
    return $null
}

# trava de digitação: toda chave da auditoria tem de casar com um tweak real; as 'Removido'
# são o inverso - se ainda existirem na config, a remoção não aconteceu.
$auditProblems = @()
$auditKeys = [string[]]@($audit.Keys)
[array]::Sort($auditKeys, [System.StringComparer]::Ordinal)
foreach ($key in $auditKeys) {
    $entry = Get-TweakEntry $key
    if ($audit[$key].Class -eq 'Removido') {
        if ($entry) { $auditProblems += "${key}: marcado como Removido mas ainda existe na config" }
    } elseif (-not $entry) {
        $auditProblems += "${key}: sem tweak correspondente nas configs (erro de digitação?)"
    }
}
if ($auditProblems.Count -gt 0) {
    $auditProblems | ForEach-Object { Write-Host "  [AUDITORIA] $_" -ForegroundColor Red }
    throw "Auditoria inconsistente: $($auditProblems.Count) problema(s)."
}

$auditRows = @()
foreach ($key in @($audit.Keys)) {
    $a = $audit[$key]
    $entry = Get-TweakEntry $key
    $name = if ($a.Override -and $a.Override.ContainsKey('Content')) { $a.Override.Content }
            elseif ($entry) { $entry.Content }
            elseif ($a.Content) { $a.Content }
            else { $key }
    $auditRows += [pscustomobject]@{ Key = $key; Name = $name; Class = $a.Class; Reason = $a.Reason }
}
# prioridade de CPU por jogo (IFEO): geradas em tempo de execução, Seguro por definição.
# Se uma dessas chaves sintetizadas colidir com uma chave da auditoria (ou com outro jogo), o doc
# teria duas linhas para a mesma chave, com classes possivelmente diferentes - falha alto.
$gameKeysSeen = @{}
foreach ($g in @($configSync.configs.wbgames)) {
    $gameKey = "WPFTweaksWBGame$($g.Key)"
    if ($audit.ContainsKey($gameKey)) {
        throw "Colisão de chave: '$gameKey' é gerada da lista de jogos e também existe em wf-audit.ps1."
    }
    if ($gameKeysSeen.ContainsKey($gameKey)) {
        throw "Colisão de chave: '$gameKey' aparece mais de uma vez na lista de jogos."
    }
    $gameKeysSeen[$gameKey] = $true
    $auditRows += [pscustomobject]@{ Key = $gameKey; Name = $g.Name; Class = 'Seguro'; Reason = '' }
}

# Cobertura no sentido inverso da trava de digitação acima: lá toda chave da auditoria tem de existir
# na config; aqui todo tweak classificável da config tem de estar na auditoria ou ser um jogo. Sem
# isto, uma entrada nova entra no programa sem classe e some do doc - o -SelfTest só pegaria depois,
# no motor montado. Os tipos ignorados são os mesmos do -SelfTest: não são itens de risco.
$uncovered = @()
foreach ($o in $jsonTweaks) {
    foreach ($p in $o.PSObject.Properties) {
        if ($p.Value.Type -in @('Button', 'Combobox', 'Note', 'ToggleButton')) { continue }
        if ($audit.ContainsKey($p.Name) -or $gameKeysSeen.ContainsKey($p.Name)) { continue }
        $uncovered += $p.Name
    }
}
if ($uncovered.Count -gt 0) {
    [array]::Sort($uncovered, [System.StringComparer]::Ordinal)
    throw "Tweak sem classificação na auditoria: $($uncovered -join ', ')"
}

$auditClasses = @(
    @{ Name = 'Seguro';   Title = 'Seguro' }
    @{ Name = 'Cuidado';  Title = 'Cuidado' }
    @{ Name = 'Removido'; Title = 'Removido' }
)
$counts = @{}
foreach ($c in $auditClasses) { $counts[$c.Name] = @($auditRows | Where-Object { $_.Class -eq $c.Name }).Count }
$gamesCount = @($configSync.configs.wbgames).Count
$cautionCategory = ($auditSync.WinForgeCautionCategory -replace '^[a-z_]+__', '')

$md = New-Object System.Text.StringBuilder
$mdHeader = @"
# Auditoria de risco

> Arquivo gerado por ``src/Engine/build.ps1`` a partir de ``src/Engine/config/wf-audit.ps1``.
> Não editar à mão: qualquer alteração é sobrescrita no próximo build.

Todo tweak e toggle do WinForge tem uma classe de risco. A classe não é só documentação — o motor
a aplica ao carregar as configurações:

- **Seguro** — reversível, sem custo de segurança ou estabilidade; pode aparecer em preset.
- **Cuidado** — tem um custo real; vive só na categoria "$cautionCategory", com o custo no início
  da descrição, e nunca entra em preset.
- **Removido** — saldo negativo; a entrada e qualquer referência a ela em preset somem.

Total: **$($counts['Seguro']) Seguro** · **$($counts['Cuidado']) Cuidado** · **$($counts['Removido']) Removido**.

"@
[void]$md.Append(($mdHeader -replace "`r`n", "`n"))

$emittedRows = 0
foreach ($c in $auditClasses) {
    # sem @() em volta: a funcao ja devolve o array inteiro (return ,$items) e um @() extra o
    # embrulharia num array de um elemento so - a tabela sairia com uma linha e todas as chaves.
    $rows = Sort-RowsByKeyOrdinal @($auditRows | Where-Object { $_.Class -eq $c.Name })
    if ($rows.Count -ne $counts[$c.Name]) {
        throw "Tabela '$($c.Name)': $($rows.Count) linha(s) depois da ordenação, esperado $($counts[$c.Name])."
    }
    $emittedRows += $rows.Count
    [void]$md.Append("`n## $($c.Title) ($($rows.Count))`n`n")
    if ($c.Name -eq 'Seguro') {
        # '<Jogo>' e não o glob 'WPFTweaksWBGame*': o glob também casaria com WPFTweaksWBGameDVR,
        # que é o toggle do Game DVR e está na auditoria, não na lista de jogos - $gamesCount não o conta.
        [void]$md.Append("As chaves ``WPFTweaksWBGame<Jogo>`` ($gamesCount entradas, contadas a partir da lista de jogos) são a`nprioridade de CPU por jogo (IFEO): uma chave de registro por executável, removida ao desfazer.`n`n")
    } elseif ($c.Name -eq 'Cuidado') {
        [void]$md.Append("O motivo abaixo é o mesmo texto que aparece como ``CUIDADO: ...`` no início da descrição do item`nna interface.`n`n")
    } else {
        [void]$md.Append("Estas entradas não existem no programa; ficam aqui para registrar por que saíram.`n`n")
    }
    [void]$md.Append("| Chave | Nome | Motivo |`n|---|---|---|`n")
    foreach ($r in $rows) {
        [void]$md.Append("| ``$($r.Key)`` | $(Format-MdCell $r.Name) | $(Format-MdCell $r.Reason) |`n")
    }
}
# Contagem impressa e contagem escrita vêm de caminhos diferentes ($auditRows x tabelas geradas):
# se a ordenação voltar a devolver o array embrulhado, o doc sai com 3 linhas e os totais certos.
if ($emittedRows -ne $auditRows.Count) {
    throw "Doc com $emittedRows linha(s) de tabela, esperado $($auditRows.Count)."
}

$auditDoc = Join-Path $RepoRoot "docs\auditoria.md"
New-Item -ItemType Directory -Path (Split-Path -Parent $auditDoc) -Force | Out-Null
[System.IO.File]::WriteAllText($auditDoc, $md.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Auditoria: $auditDoc ($($counts['Seguro']) Seguro, $($counts['Cuidado']) Cuidado, $($counts['Removido']) Removido)"

# O doc é um arquivo commitado: se qualquer fonte dele voltar a ser lida na code page errada,
# o acento aparece corrompido no repositório. Aqui só o contador de mojibake faz sentido -
# as marcas proibidas são sobre o motor, não sobre um texto em português.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $brandTest -File $auditDoc -MojibakeOnly
if ($LASTEXITCODE -ne 0) { throw "Mojibake em $auditDoc`: $LASTEXITCODE ocorrência(s)." }
