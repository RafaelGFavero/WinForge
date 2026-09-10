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
$serverConfig   = Read-Lf (Join-Path $PSScriptRoot "config\wf-server-config.ps1")
$auditBlock     = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-audit.ps1")
$profileBlock   = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-profile.ps1")
$driversBlock   = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-drivers.ps1")
$rulesBlock     = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-rules.ps1")
$recoUiBlock    = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-recoui.ps1")
$diagBlock      = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-diag.ps1")
$serverBlock    = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-server.ps1")
$auditData      = Read-Lf (Join-Path $PSScriptRoot "config\wf-audit.ps1")
$rulesData      = Read-Lf (Join-Path $PSScriptRoot "config\wf-rules.ps1")
$xamlNav        = Read-Lf (Join-Path $PSScriptRoot "xaml\wb-xaml-nav.xml")
$xamlTab        = Read-Lf (Join-Path $PSScriptRoot "xaml\wb-xaml-tab.xml")
$xamlDiagNav    = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-diag-nav.xml")
$xamlDiagTab    = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-diag-tab.xml")
$xamlServerNav  = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-server-nav.xml")
$xamlServerTab  = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-server-tab.xml")

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
# runspace que roda o script principal: Write-WinForgeLog usa isto para saber quem pode escrever
# no console (o transcript só captura o que sai desta runspace)
$sync.MainRunspaceId = [runspace]::DefaultRunspace.Id
'@ "sync init"

$src = Replace-Once $src '$winutildir = "$env:LocalAppData\winutil"' '$winutildir = "$env:LocalAppData\WinForge"' "winutildir"
$src = Replace-Once $src '$sync.logPath = "$logdir\winutil_$dateTime.log"' '$sync.logPath = "$logdir\WinForge_$dateTime.log"' "logPath"

# O transcript mantém o arquivo aberto em modo exclusivo enquanto roda: ninguém mais consegue
# anexar nele, nem o próprio processo. Como as threads do pool de runspaces (e os callbacks do
# Dispatcher disparados de dentro delas) NÃO são capturadas pelo transcript, o log da sessão
# precisa ser um arquivo separado - senão as entradas dessas threads se perdem.
$src = Replace-Once $src @'
$sync.transcriptPath = $sync.logPath
Start-Transcript -Path $sync.logPath -Append -NoClobber | Out-Null
'@ @'
$sync.transcriptPath = "$logdir\WinForge_$dateTime.console.log"

# São dois arquivos por sessão (log + console) e nada os apagava: a pasta crescia para sempre.
# Guarda as 30 sessões mais recentes de cada tipo. Arquivo em uso por outra instância não sai, e
# tudo bem - falha de poda não pode impedir o programa de abrir.
try {
    New-Item -ItemType Directory -Path $logdir -Force | Out-Null
    $wfConsoleLogs = @(Get-ChildItem -LiteralPath $logdir -Filter "WinForge_*.console.log" -File -ErrorAction SilentlyContinue)
    $wfSessionLogs = @(Get-ChildItem -LiteralPath $logdir -Filter "WinForge_*.log" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.console.log" })
    foreach ($wfLogSet in @($wfConsoleLogs, $wfSessionLogs)) {
        foreach ($wfOld in @($wfLogSet | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30)) {
            Remove-Item -LiteralPath $wfOld.FullName -Force -ErrorAction SilentlyContinue
        }
    }
} catch { }

Start-Transcript -Path $sync.transcriptPath -Append -NoClobber | Out-Null
'@ "transcript separado do log"

# Toda entrada do log vai para o arquivo, venha de onde vier (runspace do pool, callback do
# Dispatcher ou a runspace principal). O Write-Host continua só na runspace principal: é o que põe
# a linha no console e no transcript - e é de onde o -SelfTest captura o log com 6>&1.
$src = Replace-Once $src @'
        if (-not [string]::IsNullOrWhiteSpace($transcriptPath) -and $logPath -eq $transcriptPath) {
            Write-Host $line
            return
        }

        try {
            Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
        } catch [System.IO.IOException] {
            Write-Host $line
        }
'@ @'
        if (-not [string]::IsNullOrWhiteSpace($transcriptPath) -and $logPath -eq $transcriptPath) {
            # nunca acontece no WinForge (o transcript tem arquivo próprio); rede de segurança para
            # o caso de $logPath cair no transcript por falta de outro caminho
            Write-Host $line
            return
        }

        # Só a runspace principal escreve no console: o transcript não captura o que sai de uma
        # thread do pool de runspaces nem de um callback do Dispatcher disparado de dentro dela.
        $wfOnMainRunspace = $false
        try {
            if ($null -ne $sync -and $sync.ContainsKey("MainRunspaceId") -and $null -ne [runspace]::DefaultRunspace) {
                $wfOnMainRunspace = ([runspace]::DefaultRunspace.Id -eq $sync.MainRunspaceId)
            }
        } catch {
            $wfOnMainRunspace = $false
        }
        if ($null -ne $sync -and $sync.ContainsKey("ForceFileLog") -and $sync.ForceFileLog) {
            $wfOnMainRunspace = $false
        }

        # Duas runspaces podem anexar ao mesmo tempo: mutex nomeado por processo serializa a escrita.
        # Nada aqui pode estourar - uma falha de log não pode derrubar quem chamou.
        $wfMutex = $null
        try {
            if ($null -ne $sync) {
                if ($null -eq $sync.LogMutex) {
                    try { $sync.LogMutex = New-Object System.Threading.Mutex($false, "Local\WinForge.Log.$PID") } catch { $sync.LogMutex = $null }
                }
                $wfMutex = $sync.LogMutex
            }
        } catch {
            $wfMutex = $null
        }

        $wfHeld = $false
        try {
            if ($null -ne $wfMutex) {
                try { $wfHeld = $wfMutex.WaitOne(2000) } catch [System.Threading.AbandonedMutexException] { $wfHeld = $true }
            }
            [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
        } catch {
        } finally {
            if ($wfHeld) { try { $wfMutex.ReleaseMutex() } catch { } }
        }

        if ($wfOnMainRunspace) {
            Write-Host $line
        }
'@ "log de runspace no arquivo"
$src = Replace-Once $src '$Host.UI.RawUI.WindowTitle = "WinUtil"' '$Host.UI.RawUI.WindowTitle = "WinForge"' "window title console"

# ---------------------------------------------------------------- funções e configs
$src = Insert-Before $src "`$sync.configs.applications = @'" ($functionsBlock.TrimEnd() + "`n`n") "insert functions"
$src = Insert-Before $src "`$inputXML = @'" ($configBlock.TrimEnd() + "`n`n") "insert config"
$src = Insert-Before $src "`$inputXML = @'" ($serverConfig.TrimEnd() + "`n`n") "insert server config"
$src = Insert-Before $src "`$inputXML = @'" ($auditData.TrimEnd() + "`n`n") "insert audit data"
$src = Insert-Before $src "`$inputXML = @'" ($rulesData.TrimEnd() + "`n`n") "insert rules data"

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

# ---------------------------------------------------------------- regras de recomendação (motor)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($rulesBlock.TrimEnd() + "`n`n") "insert rules"

# ---------------------------------------------------------------- recomendações na interface (contornos, dicas, job)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($recoUiBlock.TrimEnd() + "`n`n") "insert reco ui"

# ---------------------------------------------------------------- aba Diagnóstico (cartões, drivers, relatório)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($diagBlock.TrimEnd() + "`n`n") "insert diag"

# ---------------------------------------------------------------- aba Servidor (comandos e visibilidade das abas)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($serverBlock.TrimEnd() + "`n`n") "insert server"

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

# ---------------------------------------------------------------- linha da grade dentro de um Border (contorno das recomendações)
# O contorno não pode ir no DockPanel/StackPanel da linha: a busca esconde esses painéis por
# Visibility e a borda sumiria junto com o layout. O Border embrulha a linha, guarda a chave na Tag
# (é assim que Update-WinForgeRecommendationVisuals reencontra a linha) e é ele quem a busca esconde.
# A linha do Combobox fica de fora: nenhuma regra recomenda combo, e embrulhá-la só criaria um
# Border sem uso para a busca desembrulhar.
$src = Replace-Once $src @'
                        $stackPanelContainer.Children.Add($dockPanel) | Out-Null
'@ @'
                        $wfRow = New-Object Windows.Controls.Border; $wfRow.BorderThickness = "0"; $wfRow.CornerRadius = "4"; $wfRow.Padding = "3,0"; $wfRow.Margin = "0,1"; $wfRow.Tag = $entryInfo.Name; $wfRow.Child = $dockPanel
                        $stackPanelContainer.Children.Add($wfRow) | Out-Null
'@ "row border toggle"

$src = Replace-Once $src @'
                        $stackPanelContainer.Children.Add($horizontalStackPanel) | Out-Null
                        $sync[$entryInfo.Name] = $checkBox
'@ @'
                        $wfRow = New-Object Windows.Controls.Border; $wfRow.BorderThickness = "0"; $wfRow.CornerRadius = "4"; $wfRow.Padding = "3,0"; $wfRow.Margin = "0,1"; $wfRow.Tag = $entryInfo.Name; $wfRow.Child = $horizontalStackPanel
                        $stackPanelContainer.Children.Add($wfRow) | Out-Null
                        $sync[$entryInfo.Name] = $checkBox
'@ "row border checkbox"

# ---------------------------------------------------------------- busca: desembrulha o Border da linha
# Find-TweaksByNameOrDescription reconhece a linha por tipo (DockPanel/StackPanel) e esconde o
# próprio $item. Com o Border no meio, nenhum ramo casaria e a busca deixaria tudo visível: aqui
# $item passa a ser o conteúdo (para o casamento) e $wfVisual o que some/aparece (o Border).
$src = Replace-Once $src @'
                            # Show all items in the category
                            foreach ($item in $items) {
                                if ($null -ne $item) {
                                    # Check if it's a category label (first Label in the container)
                                    if ($item -is [Windows.Controls.Label] -or $item.GetType().Name -eq "Label") {
                                        $item.Visibility = [Windows.Visibility]::Visible
                                    }
                                    elseif ($item -is [Windows.Controls.DockPanel] -or $item -is [Windows.Controls.StackPanel] -or $item.GetType().Name -eq "DockPanel" -or $item.GetType().Name -eq "StackPanel") {
                                        # Show all checkbox containers
                                        $item.Visibility = [Windows.Visibility]::Visible
                                    }
                                }
                            }
'@ @'
                            # Show all items in the category
                            foreach ($item in $items) {
                                if ($null -ne $item) {
                                    # WinForge: a linha vem embrulhada num Border (contorno das recomendações)
                                    $wfVisual = $item
                                    if ($item -is [Windows.Controls.Border] -and $item.Child) { $item = $item.Child }
                                    # Check if it's a category label (first Label in the container)
                                    if ($item -is [Windows.Controls.Label] -or $item.GetType().Name -eq "Label") {
                                        $wfVisual.Visibility = [Windows.Visibility]::Visible
                                    }
                                    elseif ($item -is [Windows.Controls.DockPanel] -or $item -is [Windows.Controls.StackPanel] -or $item.GetType().Name -eq "DockPanel" -or $item.GetType().Name -eq "StackPanel") {
                                        # Show all checkbox containers
                                        $wfVisual.Visibility = [Windows.Visibility]::Visible
                                    }
                                }
                            }
'@ "search reset unwrap"

$src = Replace-Once $src @'
                        foreach ($item in $items) {
                            if ($null -eq $item) {
                                continue
                            }
'@ @'
                        foreach ($item in $items) {
                            if ($null -eq $item) {
                                continue
                            }

                            # WinForge: a linha vem embrulhada num Border (contorno das recomendações)
                            $wfVisual = $item
                            if ($item -is [Windows.Controls.Border] -and $item.Child) { $item = $item.Child }
'@ "search loop unwrap"

$src = Replace-Once $src @'
                            if ($item -is [Windows.Controls.Label] -or $item.GetType().Name -eq "Label") {
                                $categoryLabel = $item
                                # Initially hide category label; show it only if matches found
                                $item.Visibility = [Windows.Visibility]::Collapsed
                            }
'@ @'
                            if ($item -is [Windows.Controls.Label] -or $item.GetType().Name -eq "Label") {
                                $categoryLabel = $item
                                # Initially hide category label; show it only if matches found
                                $wfVisual.Visibility = [Windows.Visibility]::Collapsed
                            }
'@ "search label visibility"

$src = Replace-Once $src @'
                                    $contentMatch = $labelContentStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                                    $toolTipMatch = $labelToolTipStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0

                                    if ($contentMatch -or $toolTipMatch) {
                                        $itemMatches = $true
                                    }
                                }

                                # Set visibility based on match result
                                if ($itemMatches) {
                                    $item.Visibility = [Windows.Visibility]::Visible
                                    $categoryHasMatch = $true
                                }
                                else {
                                    $item.Visibility = [Windows.Visibility]::Collapsed
                                }
'@ @'
                                    $contentMatch = $labelContentStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                                    $toolTipMatch = $labelToolTipStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0

                                    if ($contentMatch -or $toolTipMatch) {
                                        $itemMatches = $true
                                    }
                                }

                                # Set visibility based on match result
                                if ($itemMatches) {
                                    $wfVisual.Visibility = [Windows.Visibility]::Visible
                                    $categoryHasMatch = $true
                                }
                                else {
                                    $wfVisual.Visibility = [Windows.Visibility]::Collapsed
                                }
'@ "search dockpanel visibility"

$src = Replace-Once $src @'
                                    $contentMatch = $checkboxContentStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                                    $toolTipMatch = $checkboxToolTipStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0

                                    if ($contentMatch -or $toolTipMatch) {
                                        $itemMatches = $true
                                    }
                                }

                                # Set visibility based on match result
                                if ($itemMatches) {
                                    $item.Visibility = [Windows.Visibility]::Visible
                                    $categoryHasMatch = $true
                                }
                                else {
                                    $item.Visibility = [Windows.Visibility]::Collapsed
                                }
'@ @'
                                    $contentMatch = $checkboxContentStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                                    $toolTipMatch = $checkboxToolTipStr.IndexOf($searchTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0

                                    if ($contentMatch -or $toolTipMatch) {
                                        $itemMatches = $true
                                    }
                                }

                                # Set visibility based on match result
                                if ($itemMatches) {
                                    $wfVisual.Visibility = [Windows.Visibility]::Visible
                                    $categoryHasMatch = $true
                                }
                                else {
                                    $wfVisual.Visibility = [Windows.Visibility]::Collapsed
                                }
'@ "search stackpanel visibility"

# ---------------------------------------------------------------- contornos ao montar a aba
# A janela abre na aba Instalar: quando o diagnóstico termina, Tweaks e Jogos ainda não existem.
# Pintar de novo no fim de cada montagem é o que garante contorno em aba aberta depois.
$src = Replace-Once $src @'
    # Sync freshly built controls to any selections already in $sync.selected* (import/preset).
    Reset-WPFCheckBoxes -doToggles $true
}
'@ @'
    # Sync freshly built controls to any selections already in $sync.selected* (import/preset).
    Reset-WPFCheckBoxes -doToggles $true

    # WinForge: contorno/dica das recomendações nos controles recém-criados
    Update-WinForgeRecommendationVisuals | Out-Null
}
'@ "tab init reco visuals"

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
            Invoke-WPFUIElements -configVariable (Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab @("Jogos","Servidor") -Exclude) -targetGridName "tweakspanel" -columncount 2
        }
        "Jogos" {
            Invoke-WPFUIElements -configVariable (Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Jogos") -targetGridName "gamespanel" -columncount 2
        }
        "Servidor" {
            Invoke-WPFUIElements -configVariable (Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Servidor") -targetGridName "serverpanel" -columncount 2
        }
        "Diagnostico" {
            Initialize-WinForgeDiagnosticsTab
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
    } elseif ($sync.currentTab -eq "Servidor") {
        Find-TweaksByNameOrDescription -SearchString ""
    }
'@ "tab filter reset"

$src = Replace-Once $src 'if ($tabNumber -eq 0 -or $tabNumber -eq 1 -or $tabNumber -eq 5) {' 'if ($tabNumber -eq 0 -or $tabNumber -eq 1 -or $tabNumber -eq 5 -or $tabNumber -eq 6 -or $tabNumber -eq 8) {' "search visibility"

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
    } elseif ($null -ne $Sync.currentTab -and $Sync.currentTab -eq "Servidor") {
        $panelName = "serverpanel"
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
        "Servidor" {
            Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text
        }
    }
})
'@ "search timer"

# O atalho segue a aba: Win11ISO e Jogos não existem no servidor e Servidor não existe no cliente.
# Sem a guarda, Alt+W num servidor levaria a uma aba escondida (Invoke-WPFTab seleciona pelo índice,
# não pela visibilidade) e o usuário ficaria numa tela sem botão de volta. O Handled = $true fica
# nos três de qualquer jeito: a tecla foi tratada, mesmo quando a decisão é não ir a lugar nenhum.
$src = Replace-Once $src '            "W" { Invoke-WPFButton "WPFTab5BT"; $keyEventArgs.Handled = $true } # Navigate to Win11ISO tab' @'
            "W" { if (-not $sync.IsServer) { Invoke-WPFButton "WPFTab5BT" }; $keyEventArgs.Handled = $true } # Navigate to Win11ISO tab
            "J" { if (-not $sync.IsServer) { Invoke-WPFButton "WPFTab7BT" }; $keyEventArgs.Handled = $true } # WinForge: aba Jogos
            "D" { Invoke-WPFButton "WPFTab8BT"; $keyEventArgs.Handled = $true } # WinForge: aba Diagnóstico
            "S" { if ($sync.IsServer) { Invoke-WPFButton "WPFTab9BT" }; $keyEventArgs.Handled = $true } # WinForge: aba Servidor
'@.TrimEnd() "alt+j"

# ---------------------------------------------------------------- botões: lookup em tweaks + novos casos
$src = Replace-Once $src @'
    if ($sync.configs.feature.$Button) {
        $buttonConfig = $sync.configs.feature.$Button

'@ @'
    $buttonConfig = $null
    if ($sync.configs.feature.$Button) {
        $buttonConfig = $sync.configs.feature.$Button
    } elseif ($sync.configs.tweaks.$Button -and $sync.configs.tweaks.$Button.Type -eq "Button" -and $Button -notlike "WPFWFSrv*" -and $Button -notlike "WPFWFAd*") {
        # WinForge: botões definidos na config de tweaks (aba Jogos)
        $buttonConfig = $sync.configs.tweaks.$Button
    }
    # Os botões da aba Servidor (WPFWFSrv*, WPFWFAd*) ficam de fora de propósito: este caminho chama
    # $buttonConfig.function SEM argumento nenhum, e as funções deles precisam do -Name para saber
    # qual comando rodar. Quem despacha esses botões é o switch abaixo, com o -Name explícito por
    # caso - por isso a config deles também não declara "function": seria uma chave morta.
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
        "WPFSelectRecommended" {Select-WinForgeRecommended -Tab "Tweaks" | Out-Null}
        "WPFGamesSelectRecommended" {Select-WinForgeRecommended -Tab "Jogos" | Out-Null}
        "WPFServerSelectRecommended" {Select-WinForgeRecommended -Tab "Servidor" | Out-Null}
        "WPFClearServerSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFTweak*"}
        "WPFGetInstalledServer" {Invoke-WPFGetInstalled -CheckBox "tweaks"}
        "WPFServerApplyButton" {Invoke-WPFtweaksbutton}
        "WPFServerUndoButton" {Invoke-WPFundoall}
        # Os botões da aba Servidor chegam aqui por nome: Invoke-WPFButton chama $buttonConfig.function
        # sem argumento nenhum, então quem diz QUAL comando é este switch, não a config.
        "WPFWFSrvTimeCheck" {Invoke-WinForgeServerCommand -Name TimeCheck}
        "WPFWFSrvDefenderExclusions" {Invoke-WinForgeServerCommand -Name DefenderExclusions}
        "WPFWFSrvTcpShow" {Invoke-WinForgeServerCommand -Name TcpShow}
        "WPFWFAdDcdiag" {Invoke-WinForgeServerCommand -Name Dcdiag}
        "WPFWFAdReplSummary" {Invoke-WinForgeServerCommand -Name ReplSummary}
        "WPFWFAdDnsScavenging" {Invoke-WinForgeServerCommand -Name DnsScavenging}
        "WPFWFAdNtdsLocation" {Invoke-WinForgeServerCommand -Name NtdsLocation}
        "WPFDiagRefresh" {Start-WinForgeProfileJob}
        "WPFDiagWUDrivers" {Invoke-WinForgeDriverUpdateSearch}
        "WPFDiagExport" {
            $wfRelatorio = Export-WinForgeDiagnosticsReport
            if (-not $wfRelatorio) { [System.Windows.MessageBox]::Show("O diagnóstico ainda não terminou. Tente de novo em alguns segundos.", "WinForge", "OK", "Warning") | Out-Null }
        }
        "WPFDiagSelectRecommended" {
            $wfMarcados = Select-WinForgeRecommended -Tab "All"
            [System.Windows.MessageBox]::Show("$wfMarcados item(ns) recomendado(s) marcado(s) nas abas de ajustes.", "WinForge", "OK", "Information") | Out-Null
        }
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
$wbServerText = if ($sync.IsServer) { "  Papéis: $(if (@($sync.ServerRoles).Count) { @($sync.ServerRoles) -join ', ' } else { 'nenhum' })" } else { '' }
Write-Host @"

__        __ _         _____
\ \      / /(_) _ __  |  ___|  ___   _ __   __ _   ___
 \ \ /\ / / | || '_ \ | |_    / _ \ | '__| / _`` | / _ \
  \ V  V /  | || | | ||  _|  | (_) || |   | (_| ||  __/
   \_/\_/   |_||_| |_||_|     \___/ |_|    \__, | \___|
                                           |___/

  WinForge $($sync.version)  -  base: $($sync.baseVersion) (MIT, ver NOTICE)
  Sistema: $($sync.OSName) $($sync.OSDisplayVersion) (build $($sync.OSBuild))$wbServerText
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
    $wbTweaksTab = Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab @("Jogos","Servidor") -Exclude
    $wbGamesTab  = Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Jogos"
    $wbServerTab = Get-WinUtilBoostConfigSubset -Config $sync.configs.tweaks -Tab "Servidor"
    $wbHidden = @($sync.configs.tweaks.PSObject.Properties | Where-Object { -not (Test-WinUtilBoostEntryCompatible $_.Value) } | ForEach-Object { $_.Name })
    $wbHiddenAppx = @($sync.configs.appx.PSObject.Properties | Where-Object { -not (Test-WinUtilBoostEntryCompatible $_.Value) } | ForEach-Object { $_.Name })
    Write-Host "  Sistema: $($sync.OSName) $($sync.OSDisplayVersion) build $($sync.OSBuild) | GPU: $(if ($sync.GPUVendors.Count) { $sync.GPUVendors -join ',' } else { 'nenhuma' })"
    Write-Host "  Entradas -> aba Tweaks: $(@($wbTweaksTab.PSObject.Properties).Count) | aba Jogos: $(@($wbGamesTab.PSObject.Properties).Count) | aba Servidor: $(@($wbServerTab.PSObject.Properties).Count) | Config: $(@($sync.configs.feature.PSObject.Properties).Count) | AppX: $(@($sync.configs.appx.PSObject.Properties).Count) | Presets: $(@($sync.configs.preset.PSObject.Properties).Count)"
    # trava de contagem: pega regex da limpeza de marca que coma entradas demais quando o arquivo base mudar
    if (@($sync.configs.feature.PSObject.Properties).Count -ne 42) { Write-Host "  [ERRO] Config: esperado 42 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbTweaksTab.PSObject.Properties).Count -ne 83) { Write-Host "  [ERRO] aba Tweaks: esperado 83 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbGamesTab.PSObject.Properties).Count -ne 84) { Write-Host "  [ERRO] aba Jogos: esperado 84 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbServerTab.PSObject.Properties).Count -ne 22) { Write-Host "  [ERRO] aba Servidor: esperado 22 entradas" -ForegroundColor Red; $wbErrors++ }
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
    # Preset é para máquina de usuário: um item de servidor num preset seria aplicado em massa numa
    # máquina em produção por quem só clicou em "Standard". A auditoria não pega isso (item de
    # servidor pode ser Seguro), então a trava é o platform.
    $wbPresetServer = @()
    foreach ($p in $sync.configs.preset.PSObject.Properties) {
        foreach ($k in @($p.Value)) {
            $e = $sync.configs.tweaks.$k
            if ($e -and $e.PSObject.Properties['platform'] -and [string]$e.platform -eq 'server') { $wbPresetServer += "$($p.Name):$k" }
        }
    }
    if ($wbPresetServer.Count) { Write-Host "  [ERRO] presets com itens de servidor: $($wbPresetServer -join ', ')" -ForegroundColor Red; $wbErrors++ }
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
    # A área Servidor existe sempre, mas no cliente o valor é $null: o que se cobra é a CHAVE,
    # senão os cartões da aba Servidor teriam de adivinhar se o perfil é velho ou é cliente.
    if (-not $wbProfile.Contains('Server')) { Write-Host "  [ERRO] perfil sem a chave Server" -ForegroundColor Red; $wbErrors++ }
    if ($wbProfile.Roles.IsDC -isnot [bool]) { Write-Host "  [ERRO] perfil: Roles.IsDC deveria ser booleano (veio '$($wbProfile.Roles.IsDC)')" -ForegroundColor Red; $wbErrors++ }
    # Perfil x banner sob WINFORGE_SIMULATE_SERVER: os dois têm de contar a mesma história. Enquanto
    # o perfil ignorava a variável, o SelfTest "de servidor" rodava com Server = $null e não exercitava
    # nada da aba Servidor - o cartão só quebraria na máquina de verdade.
    if ($null -ne $env:WINFORGE_SIMULATE_SERVER) {
        $wbSimRoles = @($sync.ServerRoles)
        if ($wbProfile.OS.IsServer -ne $true) { Write-Host "  [ERRO] perfil simulado: OS.IsServer deveria ser true sob WINFORGE_SIMULATE_SERVER" -ForegroundColor Red; $wbErrors++ }
        if (('iis' -in $wbSimRoles) -and $wbProfile.Roles.IIS -ne $true) { Write-Host "  [ERRO] perfil simulado: Roles.IIS deveria ser true (papéis: $($wbSimRoles -join ','))" -ForegroundColor Red; $wbErrors++ }
        if (('ad' -in $wbSimRoles) -and $wbProfile.Roles.IsDC -ne $true) { Write-Host "  [ERRO] perfil simulado: Roles.IsDC deveria ser true (papéis: $($wbSimRoles -join ','))" -ForegroundColor Red; $wbErrors++ }
        # a hashtable Server tem de existir; os campos podem ser $null (os cmdlets de servidor não
        # existem no cliente), e nesse caso o que se cobra é a linha em .Errors, não a exceção
        if ($null -eq $wbProfile.Server) { Write-Host "  [ERRO] perfil simulado: Server não deveria ser null sob WINFORGE_SIMULATE_SERVER" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Perfil simulado: servidor=$($wbProfile.OS.IsServer) IIS=$($wbProfile.Roles.IIS) DC=$($wbProfile.Roles.IsDC) | Server.TimeSource=$(if ($null -eq $wbProfile.Server.TimeSource) { '(null)' } else { $wbProfile.Server.TimeSource })" }
    } elseif ($wbProfile.OS.IsServer -ne $true -and $null -ne $wbProfile.Server) {
        Write-Host "  [ERRO] perfil: Server deveria ser null num cliente sem simulação" -ForegroundColor Red; $wbErrors++
    }
    # TimeSource guarda a fonte de horário, não a mensagem do w32tm: com o serviço W32Time parado o
    # comando escreve "Ocorreu o seguinte erro..." no stdout e com código != 0 - isso vai para .Errors.
    if ($wbProfile.Server -and $wbProfile.Server.TimeSource -and ([string]$wbProfile.Server.TimeSource -match '(?i)erro|error')) {
        Write-Host "  [ERRO] perfil: Server.TimeSource guardou uma mensagem de erro ('$($wbProfile.Server.TimeSource)')" -ForegroundColor Red; $wbErrors++
    }
    if ($wbProfile.Errors.Count) { Write-Host "  Perfil: avisos -> $($wbProfile.Errors -join '; ')" }
    $null = $wbProfile | ConvertTo-Json -Depth 6 -Compress   # serializável
    Write-Host "  Perfil: $($wbProfile.OS.Caption) | $($wbProfile.CPU.Name) | RAM $($wbProfile.RAM.TotalGB) GB | GPU $(@($wbProfile.GPU | ForEach-Object { $_.Name }) -join ', ') | SSD=$($wbProfile.Storage.HasSSD) HDD=$($wbProfile.Storage.HasHDD) | laptop=$($wbProfile.Machine.IsLaptop) vm=$($wbProfile.Machine.IsVirtual) | drivers=$($wbProfile.Drivers.Count)"
    # Cada simulação monta o perfil inteiro de novo (~3 s): guarda para reusar nas regras e nos drivers.
    $wbSims = @{}
    foreach ($sim in 'laptop','vm','server-iis','server-ad','hdd','win10') {
        try {
            $sp = Get-WinForgeSimulatedProfile -Name $sim
            if ($sp.Simulated -ne $sim) { Write-Host "  [ERRO] simulação $sim" -ForegroundColor Red; $wbErrors++ }
            $wbSims[$sim] = $sp
        } catch { Write-Host "  [ERRO] simulação $sim`: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++ }
    }
    # As simulações de servidor são a única forma de exercitar a área Servidor num cliente:
    # se elas pararem de preencher IIS/DC, os cartões e regras da aba Servidor ficam sem teste.
    if ($wbSims['server-iis'] -and $wbSims['server-iis'].Server.Iis.Installed -ne $true) { Write-Host "  [ERRO] simulação server-iis: Server.Iis.Installed deveria ser true" -ForegroundColor Red; $wbErrors++ }
    if ($wbSims['server-ad'] -and $wbSims['server-ad'].Roles.IsDC -ne $true) { Write-Host "  [ERRO] simulação server-ad: Roles.IsDC deveria ser true" -ForegroundColor Red; $wbErrors++ }
    # Compatibilidade platform/role: força os dois estados e devolve o que estava, para o teste
    # valer igual no cliente e sob WINFORGE_SIMULATE_SERVER.
    $wbWasServer = $sync.IsServer; $wbWasRoles = $sync.ServerRoles
    try {
        $sync.IsServer = $false; $sync.ServerRoles = @()
        if (Test-WinUtilBoostEntryCompatible ([pscustomobject]@{ platform = 'server' })) { Write-Host "  [ERRO] compat: platform='server' deveria ser oculto no cliente" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinUtilBoostEntryCompatible ([pscustomobject]@{ platform = 'client' }))) { Write-Host "  [ERRO] compat: platform='client' deveria aparecer no cliente" -ForegroundColor Red; $wbErrors++ }
        $sync.IsServer = $true; $sync.ServerRoles = @('iis')
        if (-not (Test-WinUtilBoostEntryCompatible ([pscustomobject]@{ platform = 'server' }))) { Write-Host "  [ERRO] compat: platform='server' deveria aparecer no servidor" -ForegroundColor Red; $wbErrors++ }
        if (Test-WinUtilBoostEntryCompatible ([pscustomobject]@{ platform = 'client' })) { Write-Host "  [ERRO] compat: platform='client' deveria ser oculto no servidor" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinUtilBoostEntryCompatible ([pscustomobject]@{ role = 'iis' }))) { Write-Host "  [ERRO] compat: role='iis' deveria aparecer com o papel IIS presente" -ForegroundColor Red; $wbErrors++ }
        if (Test-WinUtilBoostEntryCompatible ([pscustomobject]@{ role = 'ad' })) { Write-Host "  [ERRO] compat: role='ad' deveria ser oculto sem o papel AD" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinUtilBoostEntryCompatible ([pscustomobject]@{ role = @('ad','iis') }))) { Write-Host "  [ERRO] compat: role=@('ad','iis') deveria aparecer (basta um papel)" -ForegroundColor Red; $wbErrors++ }
    } finally {
        $sync.IsServer = $wbWasServer; $sync.ServerRoles = $wbWasRoles
    }
    Write-Host "  Compatibilidade: platform/role OK | servidor=$($sync.IsServer) papéis=$(if (@($sync.ServerRoles).Count) { @($sync.ServerRoles) -join ',' } else { 'nenhum' })"
    # Regras de recomendação: as chaves citadas têm de existir, o que é recomendado tem de ser Seguro
    # (nada de preset disfarçado de recomendação) e cada perfil simulado tem de cair na regra dele.
    $wbRuleKeys = @($sync.WinForgeRules | ForEach-Object { @($_.Recommend) + @($_.Avoid) } | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($k in $wbRuleKeys) {
        if ($null -eq $sync.configs.tweaks.PSObject.Properties[$k]) { Write-Host "  [ERRO] regras: chave desconhecida '$k'" -ForegroundColor Red; $wbErrors++ }
    }
    foreach ($k in @($sync.WinForgeRules | ForEach-Object { @($_.Recommend) } | Where-Object { $_ } | Sort-Object -Unique)) {
        $e = $sync.configs.tweaks.$k
        if ($e -and $e.risk -ne 'seguro') { Write-Host "  [ERRO] regras: '$k' é recomendado mas o risco é '$($e.risk)'" -ForegroundColor Red; $wbErrors++ }
        # Toggle aplica o tweak no próprio evento Checked: recomendar um seria aplicar sozinho, e
        # "nada é marcado sozinho" deixaria de ser verdade. Select-WinForgeRecommended pula toggles;
        # esta trava impede que uma regra nova torne esse pulo silencioso.
        if ($e -and [string]$e.Type -eq 'Toggle') { Write-Host "  [ERRO] regras: '$k' é Toggle (marcar aplicaria o tweak na hora)" -ForegroundColor Red; $wbErrors++ }
    }
    foreach ($wbCase in @(@('laptop','WPFTweaksWBPowerSettings'), @('vm','WPFToggleWBHAGS'), @('hdd','WPFTweaksWBPrefetch'), @('server-iis','WPFTweaksWBGameDVR'))) {
        $sp = $wbSims[$wbCase[0]]
        if (-not $sp) { continue }   # a simulação já foi acusada acima
        $r = Invoke-WinForgeRules -Profile $sp
        if (-not $r.Discouraged.Contains($wbCase[1])) { Write-Host "  [ERRO] regras ($($wbCase[0])): '$($wbCase[1])' deveria estar em Evitar" -ForegroundColor Red; $wbErrors++ }
        if ($r.Recommended.Contains($wbCase[1])) { Write-Host "  [ERRO] regras ($($wbCase[0])): '$($wbCase[1])' evitado mas ainda recomendado" -ForegroundColor Red; $wbErrors++ }
    }
    # 'Finalizar tarefa' é recurso do Windows 11: no 10 a regra não pode disparar (a chave existe nas duas)
    if ($wbSims['win10']) {
        $wbW10 = Invoke-WinForgeRules -Profile $wbSims['win10']
        if ($wbW10.Recommended.Contains('WPFTweaksEndTaskOnTaskbar')) { Write-Host "  [ERRO] regras (win10): 'WPFTweaksEndTaskOnTaskbar' não deveria ser recomendado" -ForegroundColor Red; $wbErrors++ }
    }
    # Regras de servidor: as simulações são o único jeito de exercitá-las num cliente. 'server-iis'
    # tem o papel IIS e SMB1 ligado; 'server-ad' é controlador de domínio SEM IIS - é esse par que
    # prova que as recomendações de IIS não vazam para um DC e que as regras de informação disparam.
    if ($wbSims['server-iis']) {
        $wbSrvIis = Invoke-WinForgeRules -Profile $wbSims['server-iis']
        foreach ($wbSrvK in @('WPFTweaksWFIisAlwaysRunning', 'WPFTweaksWFSrvSmb1Off')) {
            if (-not $wbSrvIis.Recommended.Contains($wbSrvK)) { Write-Host "  [ERRO] regras (server-iis): '$wbSrvK' deveria ser recomendado" -ForegroundColor Red; $wbErrors++ }
        }
        if (-not $wbSrvIis.Discouraged.Contains('WPFTweaksWBGameDVR')) { Write-Host "  [ERRO] regras (server-iis): 'WPFTweaksWBGameDVR' deveria estar em Evitar" -ForegroundColor Red; $wbErrors++ }
        $wbSrvInfo = @($wbSrvIis.Infos | Where-Object { $_ -match 'Logs do IIS' })
        if ($wbSrvInfo.Count -ne 1) { Write-Host "  [ERRO] regras (server-iis): esperado 1 info citando 'Logs do IIS', veio $($wbSrvInfo.Count)" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Regras (server-iis): $($wbSrvIis.Recommended.Count) recomendados, info -> $($wbSrvInfo[0])" }
    }
    if ($wbSims['server-ad']) {
        $wbSrvAd = Invoke-WinForgeRules -Profile $wbSims['server-ad']
        foreach ($wbSrvId in @('ad-dc', 'dc-ntds-os-drive')) {
            if ($wbSrvId -notin @($wbSrvAd.Fired)) { Write-Host "  [ERRO] regras (server-ad): a regra '$wbSrvId' deveria ter disparado (disparadas: $(@($wbSrvAd.Fired) -join ', '))" -ForegroundColor Red; $wbErrors++ }
        }
        $wbSrvAdIis = @(@($wbSrvAd.Recommended.Keys) | Where-Object { $_ -like 'WPFTweaksWFIis*' })
        if ($wbSrvAdIis.Count) { Write-Host "  [ERRO] regras (server-ad): um DC sem IIS não pode receber $($wbSrvAdIis -join ', ')" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Regras (server-ad): $(@($wbSrvAd.Fired) -join ', ')" }
    }
    # Cartão Servidor: existe no perfil de servidor e NÃO existe num cliente - o relatório HTML sai
    # das mesmas seções, então esta é a trava dos dois de uma vez.
    if ($wbSims['server-iis']) {
        $wbSecSrv = @(Get-WinForgeDiagSections -Profile $wbSims['server-iis'] | ForEach-Object { [string]$_.Title })
        if ('Servidor' -notin $wbSecSrv) { Write-Host "  [ERRO] Diagnóstico (server-iis): esperada a seção 'Servidor' (veio: $($wbSecSrv -join ', '))" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Diagnóstico (server-iis): $($wbSecSrv.Count) seções, com 'Servidor'" }
    }
    # por último o perfil real, para que $sync.Recommended fique com o desta máquina
    # (Invoke-WinForgeRules sobrescreve $sync.Recommended: as simulações acima deixaram lixo lá)
    $sync.Profile = $wbProfile
    $wbRules = Invoke-WinForgeRules -Profile $wbProfile
    Write-Host "  Regras: $($wbRules.Fired.Count) disparadas no perfil real -> $($wbRules.Recommended.Count) recomendados, $($wbRules.Discouraged.Count) evitados, $($wbRules.Infos.Count) infos"
    Write-Host "    disparadas : $($wbRules.Fired -join ', ')"
    Write-Host "    recomendar : $(@($wbRules.Recommended.Keys) -join ', ')"
    Write-Host "    evitar     : $(@($wbRules.Discouraged.Keys) -join ', ')"
    foreach ($wbInfo in @($wbRules.Infos)) { Write-Host "    info       : $wbInfo" }
    # Num cliente de verdade nada de servidor pode ser recomendado, e o Diagnóstico não pode ganhar o
    # cartão Servidor: as entradas WF* nem existem na janela aqui, e recomendar chave invisível seria
    # uma recomendação que ninguém consegue marcar.
    if (-not $wbProfile.OS.IsServer) {
        $wbCliSrv = @(@($wbRules.Recommended.Keys) | Where-Object { $_ -like 'WPFTweaksWF*' })
        if ($wbCliSrv.Count) { Write-Host "  [ERRO] regras (cliente real): nada de servidor deveria ser recomendado, veio $($wbCliSrv -join ', ')" -ForegroundColor Red; $wbErrors++ }
        $wbCliSec = @(Get-WinForgeDiagSections -Profile $wbProfile | ForEach-Object { [string]$_.Title })
        if ('Servidor' -in $wbCliSec) { Write-Host "  [ERRO] Diagnóstico (cliente real): a seção 'Servidor' não deveria existir" -ForegroundColor Red; $wbErrors++ }
    }
    # ---------------------------------------------------------------- IIS: helpers puros (sem IIS)
    # Nenhum destes helpers toca no provedor IIS:\, então dão para exercitar em qualquer máquina - e
    # eles são o miolo do endereçamento, da conversão de valores e da comparação que decide o que
    # entra no backup. A comparação é o que sustenta a idempotência: chave já no alvo fica fora do
    # backup, senão aplicar duas vezes gravaria um backup com os valores já ajustados e o Desfazer
    # (que pega o mais novo) restauraria justamente o que se queria desfazer.
    $wbIisKey = Split-WinForgeIisKey -Key 'pool:My Pool:processModel.idleTimeout'
    if ($wbIisKey.Kind -ne 'pool' -or $wbIisKey.Target -ne 'My Pool' -or $wbIisKey.Property -ne 'processModel.idleTimeout') { Write-Host "  [ERRO] IIS: Split-WinForgeIisKey veio kind='$($wbIisKey.Kind)' alvo='$($wbIisKey.Target)' prop='$($wbIisKey.Property)'" -ForegroundColor Red; $wbErrors++ }
    $wbIisKeySrv = Split-WinForgeIisKey -Key 'server:system.webServer/caching:enableKernelCache'
    if ($wbIisKeySrv.Kind -ne 'server' -or $wbIisKeySrv.Target -ne 'system.webServer/caching' -or $wbIisKeySrv.Property -ne 'enableKernelCache') { Write-Host "  [ERRO] IIS: Split-WinForgeIisKey (server) veio kind='$($wbIisKeySrv.Kind)' alvo='$($wbIisKeySrv.Target)' prop='$($wbIisKeySrv.Property)'" -ForegroundColor Red; $wbErrors++ }
    if ((Get-WinForgeIisFilter 'system.webServer/caching') -ne '/system.webServer/caching' -or (Get-WinForgeIisFilter '/system.webServer/caching') -ne '/system.webServer/caching') { Write-Host "  [ERRO] IIS: Get-WinForgeIisFilter não normalizou a seção" -ForegroundColor Red; $wbErrors++ }
    # TimeSpan acima de 24 h tem de virar hora corrida ('26:00:00'): o ToString() padrão daria
    # '1.02:00:00', que o IIS recusa de volta. uint32 e valor embrulhado em .Value (PSObject ou
    # hashtable) também têm de sair como texto simples - '@{Value=5000}' no backup é backup perdido.
    foreach ($wbIisCase in @(
        @([TimeSpan]'1.02:00:00', '26:00:00'),
        @([TimeSpan]::FromMinutes(20), '00:20:00'),
        @([TimeSpan]::Zero, '00:00:00'),
        @($true, 'True'),
        @($false, 'False'),
        @([uint32]5000, '5000'),
        @([int64]1048576, '1048576'),
        @([pscustomobject]@{ Value = 'OnDemand' }, 'OnDemand'),
        @([pscustomobject]@{ Value = [TimeSpan]'1.02:00:00' }, '26:00:00'),
        @(@{ Value = '5000' }, '5000'),
        @($null, '')
    )) {
        $wbIisGot = ConvertTo-WinForgeIisString $wbIisCase[0]
        if ($wbIisGot -ne $wbIisCase[1]) { Write-Host "  [ERRO] IIS: ConvertTo-WinForgeIisString veio '$wbIisGot', esperado '$($wbIisCase[1])'" -ForegroundColor Red; $wbErrors++ }
    }
    foreach ($wbIisM in @(
        @([TimeSpan]::Zero, '00:00:00', $true),
        @('alwaysrunning', 'AlwaysRunning', $true),
        @([pscustomobject]@{ Value = $true }, 'True', $true),
        @([TimeSpan]::FromMinutes(20), '00:00:00', $false),
        @([uint32]1000, '5000', $false)
    )) {
        $wbIisMGot = Test-WinForgeIisValueMatch -Current $wbIisM[0] -Target $wbIisM[1]
        if ($wbIisMGot -ne $wbIisM[2]) { Write-Host "  [ERRO] IIS: Test-WinForgeIisValueMatch ('$($wbIisM[0])' vs '$($wbIisM[1])') veio $wbIisMGot, esperado $($wbIisM[2])" -ForegroundColor Red; $wbErrors++ }
    }
    # As duas pontas da faixa de memória privada, com a RAM vinda por parâmetro para o resultado não
    # depender da máquina que roda o teste.
    foreach ($wbIisMem in @(
        @(2097152, 4, 1048576),
        @(33554432, 4, 5033164),
        @(33554432, 1, 8388608)
    )) {
        $wbIisMemGot = Get-WinForgeIisPrivateMemoryLimitKb -PoolCount $wbIisMem[1] -TotalKb $wbIisMem[0]
        if ($wbIisMemGot -ne $wbIisMem[2]) { Write-Host "  [ERRO] IIS: memória privada com $($wbIisMem[0]) KB / $($wbIisMem[1]) pool(s) veio $wbIisMemGot, esperado $($wbIisMem[2])" -ForegroundColor Red; $wbErrors++ }
    }
    # As duas chaves de registro do ASP.NET: a de 64 bits e a de 32 bits (Wow6432Node), que é a que
    # o pool em modo 32 bits lê. Com uma só, metade dos pools ficaria sem o ajuste - e o Desfazer,
    # que apaga o que a entrada criou, deixaria a outra chave para trás.
    $wbIisConc = @($sync.configs.tweaks.'WPFTweaksWFIisConcurrency'.registry)
    if ($wbIisConc.Count -ne 2 -or @($wbIisConc | Where-Object { $_.Path -like '*\Wow6432Node\*' }).Count -ne 1 -or @($wbIisConc | Where-Object { $_.Name -eq 'MaxConcurrentRequestsPerCPU' -and $_.OriginalValue -eq '<RemoveEntry>' }).Count -ne 2) { Write-Host "  [ERRO] IIS: WPFTweaksWFIisConcurrency deveria ter as duas chaves MaxConcurrentRequestsPerCPU (64 e 32 bits) com Original <RemoveEntry>, veio $($wbIisConc.Count): $(@($wbIisConc | ForEach-Object { $_.Path }) -join ' | ')" -ForegroundColor Red; $wbErrors++ }
    # Alvos de dois itens: OutputCache e Compression são os únicos que não listam pools/sites, então
    # o plano deles pode ser conferido sem IIS.
    $wbIisPlanOc = Get-WinForgeIisTweakPlan -Name 'OutputCache'
    $wbIisOcKeys = @($wbIisPlanOc.Targets.Keys)
    if ($wbIisOcKeys.Count -ne 2 -or $wbIisPlanOc.Targets['server:system.webServer/caching:enabled'] -ne 'True' -or $wbIisPlanOc.Targets['server:system.webServer/caching:enableKernelCache'] -ne 'True') { Write-Host "  [ERRO] IIS: alvos de OutputCache vieram '$($wbIisOcKeys -join ', ')'" -ForegroundColor Red; $wbErrors++ }
    $wbIisPlanCp = Get-WinForgeIisTweakPlan -Name 'Compression'
    if ($wbIisPlanCp.Targets['server:system.webServer/urlCompression:doStaticCompression'] -ne 'True') { Write-Host "  [ERRO] IIS: Compression sem doStaticCompression = True (veio '$($wbIisPlanCp.Targets['server:system.webServer/urlCompression:doStaticCompression'])')" -ForegroundColor Red; $wbErrors++ }
    # Sem o recurso de compressão dinâmica a chave sai da lista, mas o motivo tem de dizer isso -
    # ficar de fora calado seria um item que promete duas coisas e entrega uma.
    if (-not $wbIisPlanCp.Targets.Contains('server:system.webServer/urlCompression:doDynamicCompression') -and [string]$wbIisPlanCp.Skipped -notmatch 'Web-Dyn-Compression') { Write-Host "  [ERRO] IIS: compressão dinâmica fora dos alvos sem citar Web-Dyn-Compression ('$($wbIisPlanCp.Skipped)')" -ForegroundColor Red; $wbErrors++ }
    $wbIisPlanThrew = $false
    try { Get-WinForgeIisTweakPlan -Name 'ItemQueNaoExiste' | Out-Null } catch { $wbIisPlanThrew = $true }
    if (-not $wbIisPlanThrew) { Write-Host "  [ERRO] IIS: Get-WinForgeIisTweakPlan aceitou um item desconhecido" -ForegroundColor Red; $wbErrors++ }
    # O que entra no backup, com os cinco casos que decidem a reversibilidade do item: leitura que
    # falhou (chave ausente), valor vazio, valor nulo, valor já no alvo e valor diferente. Só o
    # último pode entrar no backup e na escrita - vazio no backup viraria um Desfazer que apaga a
    # propriedade, e "já no alvo" no backup viraria um Desfazer que restaura o valor ajustado.
    $wbIisAlvos = [ordered]@{
        'pool:A:startMode'                  = 'AlwaysRunning'
        'pool:B:startMode'                  = 'AlwaysRunning'
        'pool:C:startMode'                  = 'AlwaysRunning'
        'pool:D:startMode'                  = 'AlwaysRunning'
        'pool:E:processModel.idleTimeout'   = '00:00:00'
    }
    $wbIisAtual = @{
        'pool:B:startMode'                = ''
        'pool:C:startMode'                = $null
        'pool:D:startMode'                = 'alwaysrunning'
        'pool:E:processModel.idleTimeout' = [TimeSpan]::FromMinutes(20)
    }
    $wbIisSet = Get-WinForgeIisChangeSet -Targets $wbIisAlvos -Current $wbIisAtual
    if ((@($wbIisSet.Pending) -join ',') -ne 'pool:E:processModel.idleTimeout') { Write-Host "  [ERRO] IIS: conjunto de mudanças deveria ter só a chave diferente, veio '$(@($wbIisSet.Pending) -join ',')'" -ForegroundColor Red; $wbErrors++ }
    if ((@($wbIisSet.Unreadable) -join ',') -ne 'pool:A:startMode,pool:B:startMode,pool:C:startMode') { Write-Host "  [ERRO] IIS: não lidas deveriam ser A (ausente), B (vazia) e C (nula), veio '$(@($wbIisSet.Unreadable) -join ',')'" -ForegroundColor Red; $wbErrors++ }
    if ((@($wbIisSet.Already) -join ',') -ne 'pool:D:startMode') { Write-Host "  [ERRO] IIS: 'já no alvo' deveria ser só D, veio '$(@($wbIisSet.Already) -join ',')'" -ForegroundColor Red; $wbErrors++ }
    if ($wbIisSet.Previous.Count -ne 1 -or $wbIisSet.Previous['pool:E:processModel.idleTimeout'] -ne '00:20:00') { Write-Host "  [ERRO] IIS: backup deveria ter só E = '00:20:00', veio $($wbIisSet.Previous.Count) item(ns) ('$($wbIisSet.Previous['pool:E:processModel.idleTimeout'])')" -ForegroundColor Red; $wbErrors++ }
    # Item inteiro já aplicado: nada a escrever, e é por isso que Invoke não grava backup nesse caso.
    $wbIisSetOk = Get-WinForgeIisChangeSet -Targets $wbIisAlvos -Current @{
        'pool:A:startMode'                = 'AlwaysRunning'
        'pool:B:startMode'                = 'AlwaysRunning'
        'pool:C:startMode'                = 'AlwaysRunning'
        'pool:D:startMode'                = 'AlwaysRunning'
        'pool:E:processModel.idleTimeout' = [TimeSpan]::Zero
    }
    if (@($wbIisSetOk.Pending).Count -ne 0 -or $wbIisSetOk.Previous.Count -ne 0 -or @($wbIisSetOk.Already).Count -ne 5) { Write-Host "  [ERRO] IIS: item já aplicado deveria dar 0 a escrever, 0 no backup e 5 no alvo (veio $(@($wbIisSetOk.Pending).Count)/$($wbIisSetOk.Previous.Count)/$(@($wbIisSetOk.Already).Count))" -ForegroundColor Red; $wbErrors++ }
    Write-Host "  IIS (helpers): chave, filtro, $(@($wbIisOcKeys).Count) alvos de OutputCache, conversão de valor, comparação, faixa de memória e conjunto de mudanças OK"
    # ---------------------------------------------------------------- IIS: backup dos valores anteriores
    # O backup é o que torna os itens de IIS reversíveis: sem arquivo, "Desfazer" não tem para onde
    # voltar. Numa máquina sem IIS dá para provar duas coisas, e são as duas cobradas aqui: o
    # round-trip do arquivo (numa raiz temporária, nunca em %ProgramData%) e a recusa limpa de
    # Invoke-WinForgeIisTweak quando o módulo WebAdministration não existe.
    $wbIisRoot = Join-Path $env:TEMP 'WinForge-SelfTest\iis-backup'
    try {
        if (Test-Path $wbIisRoot) { Remove-Item -Path $wbIisRoot -Recurse -Force -ErrorAction SilentlyContinue }
        $wbIisFile = New-WinForgeIisSnapshot -Name 'SelfTest' -Values @{ 'pool:DefaultAppPool:startMode' = 'OnDemand' } -Root $wbIisRoot
        if (-not $wbIisFile -or -not (Test-Path $wbIisFile)) { Write-Host "  [ERRO] IIS: New-WinForgeIisSnapshot não gravou arquivo ('$wbIisFile')" -ForegroundColor Red; $wbErrors++ }
        $wbIisSnap = Get-WinForgeIisSnapshot -Name 'SelfTest' -Root $wbIisRoot
        if ($null -eq $wbIisSnap) { Write-Host "  [ERRO] IIS: Get-WinForgeIisSnapshot não achou o backup recém-gravado" -ForegroundColor Red; $wbErrors++ }
        elseif ($wbIisSnap.Values['pool:DefaultAppPool:startMode'] -ne 'OnDemand') { Write-Host "  [ERRO] IIS: valor do backup veio '$($wbIisSnap.Values['pool:DefaultAppPool:startMode'])', esperado 'OnDemand'" -ForegroundColor Red; $wbErrors++ }
        # Segundo backup no MESMO segundo, de propósito: o nome carrega milissegundo, então os dois
        # arquivos coexistem e o primeiro - o dos valores originais - continua no disco. Com precisão
        # de segundo, este é o cenário que apagava o backup bom (aplicar duas vezes seguidas).
        Start-Sleep -Milliseconds 20
        $wbIisFile2 = New-WinForgeIisSnapshot -Name 'SelfTest' -Values @{ 'pool:DefaultAppPool:startMode' = 'AlwaysRunning' } -Root $wbIisRoot
        if ($wbIisFile2 -eq $wbIisFile) { Write-Host "  [ERRO] IIS: o segundo backup do mesmo segundo caiu no mesmo arquivo ($wbIisFile2)" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-Path -LiteralPath $wbIisFile)) { Write-Host "  [ERRO] IIS: o primeiro backup desapareceu depois do segundo ($wbIisFile)" -ForegroundColor Red; $wbErrors++ }
        if (@(Get-ChildItem -LiteralPath $wbIisRoot -Filter 'SelfTest-*.json').Count -ne 2) { Write-Host "  [ERRO] IIS: esperado 2 arquivos de backup, veio $(@(Get-ChildItem -LiteralPath $wbIisRoot -Filter 'SelfTest-*.json').Count)" -ForegroundColor Red; $wbErrors++ }
        $wbIisNovo = Get-WinForgeIisSnapshot -Name 'SelfTest' -Root $wbIisRoot
        if ($null -eq $wbIisNovo -or $wbIisNovo.Values['pool:DefaultAppPool:startMode'] -ne 'AlwaysRunning') { Write-Host "  [ERRO] IIS: o backup mais novo deveria vencer (veio '$($wbIisNovo.Values['pool:DefaultAppPool:startMode'])')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  IIS: backup em $(Split-Path -Leaf $wbIisFile2) | round-trip OK, o mais novo vence, mesmo segundo não sobrescreve"
    } catch {
        Write-Host "  [ERRO] IIS (backup): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path (Split-Path -Parent $wbIisRoot) -Recurse -Force -ErrorAction SilentlyContinue
    }
    # Sem IIS instalado (todo cliente e boa parte dos servidores), aplicar um item de IIS não pode
    # estourar: tem de sair 0 alteração e um motivo que diga que foi o IIS que faltou.
    if (-not (Test-WinForgeIisAvailable)) {
        try {
            $wbIisRes = Invoke-WinForgeIisTweak -Name AlwaysRunning
            if ($null -eq $wbIisRes) { Write-Host "  [ERRO] IIS ausente: Invoke-WinForgeIisTweak não devolveu resultado" -ForegroundColor Red; $wbErrors++ }
            else {
                if ($wbIisRes.Changed -ne 0) { Write-Host "  [ERRO] IIS ausente: esperado Changed = 0, veio $($wbIisRes.Changed)" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wbIisRes.Skipped -notmatch 'IIS') { Write-Host "  [ERRO] IIS ausente: o motivo não cita o IIS ('$($wbIisRes.Skipped)')" -ForegroundColor Red; $wbErrors++ }
                Write-Host "  IIS ausente: recusa limpa -> $($wbIisRes.Skipped)"
            }
        } catch {
            Write-Host "  [ERRO] IIS ausente: Invoke-WinForgeIisTweak lançou '$($_.Exception.Message)'" -ForegroundColor Red; $wbErrors++
        }
    } else {
        Write-Host "  IIS presente: teste de recusa pulado (o módulo WebAdministration existe nesta máquina)"
    }
    # ---------------------------------------------------------------- comandos de leitura da aba Servidor
    # Nada aqui exige servidor: a tabela de comandos é dado puro, o núcleo é síncrono e o netsh
    # existe em qualquer Windows. O caso do dcdiag prova o contrário do TcpShow - ferramenta que
    # não existe tem de virar texto explicando isso, e não exceção no meio do runspace.
    $wbSrvNomes = @('TimeCheck', 'DefenderExclusions', 'TcpShow', 'Dcdiag', 'ReplSummary', 'DnsScavenging', 'NtdsLocation')
    foreach ($wbSrvNome in $wbSrvNomes) {
        $wbSrvCmd = Get-WinForgeServerCommand -Name $wbSrvNome
        if ($null -eq $wbSrvCmd -or [string]::IsNullOrWhiteSpace($wbSrvCmd.Title) -or [string]::IsNullOrWhiteSpace($wbSrvCmd.Command)) { Write-Host "  [ERRO] Servidor: comando '$wbSrvNome' sem título ou sem texto de comando" -ForegroundColor Red; $wbErrors++; continue }
        try { [scriptblock]::Create($wbSrvCmd.Command) | Out-Null } catch { Write-Host "  [ERRO] Servidor: comando '$wbSrvNome' não compila: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++ }
    }
    if ((Get-WinForgeServerCommand -Name Dcdiag).Requires -ne 'dcdiag.exe') { Write-Host "  [ERRO] Servidor: Dcdiag deveria exigir 'dcdiag.exe', veio '$((Get-WinForgeServerCommand -Name Dcdiag).Requires)'" -ForegroundColor Red; $wbErrors++ }
    if ($null -ne (Get-WinForgeServerCommand -Name NtdsLocation).Requires) { Write-Host "  [ERRO] Servidor: NtdsLocation não deveria exigir ferramenta nenhuma (veio '$((Get-WinForgeServerCommand -Name NtdsLocation).Requires)')" -ForegroundColor Red; $wbErrors++ }
    $wbSrvDesconhecido = $false
    try { Get-WinForgeServerCommand -Name 'NaoExiste' | Out-Null } catch { $wbSrvDesconhecido = $true }
    if (-not $wbSrvDesconhecido) { Write-Host "  [ERRO] Servidor: Get-WinForgeServerCommand aceitou um comando desconhecido" -ForegroundColor Red; $wbErrors++ }
    # O código de saída é o que separa "dcdiag não achou nada" de "dcdiag falhou": tem de sobreviver
    # ao Out-String e chegar ao texto. E a code page volta ao que era - trocá-la é processo inteiro.
    $wbNatAntes = [Console]::OutputEncoding
    $wbNat = Invoke-WinForgeNativeCommand -Command 'cmd /c exit 3'
    if ($wbNat.ExitCode -ne 3) { Write-Host "  [ERRO] Servidor: Invoke-WinForgeNativeCommand deveria devolver código 3, veio '$($wbNat.ExitCode)'" -ForegroundColor Red; $wbErrors++ }
    if ([Console]::OutputEncoding -ne $wbNatAntes) { Write-Host "  [ERRO] Servidor: Invoke-WinForgeNativeCommand não devolveu a code page do console" -ForegroundColor Red; $wbErrors++ }
    $wbNatEco = Invoke-WinForgeNativeCommand -Command 'cmd /c echo alo'
    if ([string]$wbNatEco.Text -notmatch 'alo' -or $wbNatEco.ExitCode -ne 0) { Write-Host "  [ERRO] Servidor: Invoke-WinForgeNativeCommand não capturou a saída ('$([string]$wbNatEco.Text)', código $($wbNatEco.ExitCode))" -ForegroundColor Red; $wbErrors++ }
    else { Write-Host "  Servidor (comando externo): código de saída e texto OK, code page devolvida" }
    try {
        $wbSrvTcp = Invoke-WinForgeServerCommandCore -Name TcpShow
        if ([string]::IsNullOrWhiteSpace($wbSrvTcp.Text)) { Write-Host "  [ERRO] Servidor: TcpShow voltou sem texto" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wbSrvTcp.Text -notmatch 'Código de saída: 0') { Write-Host "  [ERRO] Servidor: TcpShow deveria trazer 'Código de saída: 0' no texto" -ForegroundColor Red; $wbErrors++ }
        if (-not $wbSrvTcp.Path -or -not (Test-Path -LiteralPath $wbSrvTcp.Path)) { Write-Host "  [ERRO] Servidor: TcpShow não gravou o arquivo ('$($wbSrvTcp.Path)')" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Servidor (comandos): TcpShow -> $(([string]$wbSrvTcp.Text).Length) caractere(s) em $(Split-Path -Leaf $wbSrvTcp.Path)" }
    } catch {
        Write-Host "  [ERRO] Servidor: Invoke-WinForgeServerCommandCore -Name TcpShow lançou '$($_.Exception.Message)'" -ForegroundColor Red; $wbErrors++
    }
    if (Get-Command 'dcdiag.exe' -ErrorAction SilentlyContinue) {
        Write-Host "  Servidor (comandos): recusa do dcdiag pulada (a ferramenta existe nesta máquina)"
    } else {
        try {
            $wbSrvDc = Invoke-WinForgeServerCommandCore -Name Dcdiag
            if ([string]$wbSrvDc.Text -notmatch 'não encontrada') { Write-Host "  [ERRO] Servidor: dcdiag ausente deveria dizer 'não encontrada', veio '$([string]$wbSrvDc.Text)'" -ForegroundColor Red; $wbErrors++ }
            if (-not $wbSrvDc.Path -or -not (Test-Path -LiteralPath $wbSrvDc.Path)) { Write-Host "  [ERRO] Servidor: dcdiag ausente deveria gravar o arquivo mesmo assim ('$($wbSrvDc.Path)')" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Servidor (comandos): ferramenta ausente -> $(([string]$wbSrvDc.Text).Trim())" }
        } catch {
            Write-Host "  [ERRO] Servidor: dcdiag ausente lançou '$($_.Exception.Message)'" -ForegroundColor Red; $wbErrors++
        }
    }
    # A janela de saída é montada em código, sem XAML: o -NoShow existe para o SelfTest provar que o
    # TextBox nasce com o texto certo sem abrir nada na tela (ShowDialog aqui travaria o build).
    try {
        $wbSrvTexto = "primeira linha`r`nsegunda linha com acento: configuração"
        $wbSrvJanela = Show-WinForgeOutputWindow -Title 'SelfTest' -Text $wbSrvTexto -NoShow
        if ($wbSrvJanela -isnot [System.Windows.Window]) { Write-Host "  [ERRO] Servidor: Show-WinForgeOutputWindow -NoShow não devolveu uma janela" -ForegroundColor Red; $wbErrors++ }
        else {
            $wbSrvCaixa = $wbSrvJanela.FindName('WFOutputText')
            if ($null -eq $wbSrvCaixa) { Write-Host "  [ERRO] Servidor: a janela de saída não tem o TextBox 'WFOutputText'" -ForegroundColor Red; $wbErrors++ }
            elseif ($wbSrvCaixa.Text -ne $wbSrvTexto) { Write-Host "  [ERRO] Servidor: o texto da janela veio '$($wbSrvCaixa.Text)'" -ForegroundColor Red; $wbErrors++ }
            elseif (-not $wbSrvCaixa.IsReadOnly) { Write-Host "  [ERRO] Servidor: o TextBox da janela de saída deveria ser somente leitura" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Servidor (janela de saída): WFOutputText com $($wbSrvCaixa.Text.Length) caractere(s), somente leitura, sem ShowDialog" }
        }
    } catch {
        Write-Host "  [ERRO] Servidor (janela de saída): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
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
    $wbVm = $wbSims['vm']
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
        foreach ($n in 'gamespanel','WPFTab7BT','WPFPresetWinForge','WPFPresetGamer','WPFAppxWinForgeSelection','WPFGamesApplyButton','WPFGamesUndoButton','WPFSelectRecommended','WPFGamesSelectRecommended','WPFTab8BT','WPFDiagCards','WPFDiagDrivers','WPFDiagRefresh','WPFDiagExport','WPFDiagStatus','WPFDiagInfos','WPFDiagRecs','WPFDiagWU','WPFDiagWULabel','WPFDiagWUDrivers','WPFDiagSelectRecommended','serverpanel','WPFTab9BT','WPFServerApplyButton','WPFServerUndoButton','WPFServerSelectRecommended','WPFClearServerSelection','WPFGetInstalledServer') {
            if ($null -eq $wbWindow.FindName($n)) { Write-Host "  [ERRO] XAML: elemento '$n' não encontrado" -ForegroundColor Red; $wbErrors++ }
        }
        # monta cada aba sem mostrar a janela (exercita Invoke-WPFUIElements, filtros, toggles e botões)
        $sync["Form"] = $wbWindow
        $wbXaml.SelectNodes("//*[@Name]") | ForEach-Object { $sync["$($_.Name)"] = $sync["Form"].FindName($_.Name) }
        $sync.InitializedTabs = @{}
        # Antes do diagnóstico terminar, $sync.Recommended/$sync.Discouraged são nulos - é o estado
        # real da janela recém-aberta. Enumerar .Keys de $null dava uma chave nula e uma exceção por
        # montagem de aba ("não é possível indexar em uma matriz nula"), com zero contornos.
        try {
            $sync.Recommended = $null
            $sync.Discouraged = $null
            $wbSemRegras = Update-WinForgeRecommendationVisuals
            if ($wbSemRegras -ne 0) { Write-Host "  [ERRO] contornos sem diagnóstico: esperado 0, veio $wbSemRegras" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Contornos sem diagnóstico: OK (0 linha(s), sem exceção)"
        } catch {
            Write-Host "  [ERRO] contornos sem diagnóstico: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        } finally {
            $null = Invoke-WinForgeRules -Profile $wbProfile   # devolve $sync.Recommended ao perfil real
        }
        # Ordem da janela real: o diagnóstico termina com a janela ainda na aba Instalar, ou seja,
        # ANTES de a aba Diagnóstico existir de fato. O job tem de chegar ao fim assim mesmo - foi
        # justamente aqui que ele morria calado, sem 'pronto' e sem 'falhou'.
        try {
            $sync.Profile = $null
            $sync.ProfileJobRunning = $false
            $wbJobAntes = (Start-WinForgeProfileJob -Synchronous -SkipNetwork 6>&1 | Out-String -Width 500)
            if ($wbJobAntes -notmatch 'Diagnóstico pronto') { Write-Host "  [ERRO] job antes das abas: log sem 'Diagnóstico pronto'" -ForegroundColor Red; $wbErrors++ }
            if ($wbJobAntes -match 'Diagnóstico falhou|falha ao atualizar a interface') { Write-Host "  [ERRO] job antes das abas: $($wbJobAntes.Trim())" -ForegroundColor Red; $wbErrors++ }
            if ($sync.ProfileJobRunning) { Write-Host "  [ERRO] job antes das abas: ProfileJobRunning ficou ligado" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Job de diagnóstico antes das abas: OK ($($sync.WPFDiagCards.Children.Count) cartões já desenhados)"
        } catch {
            Write-Host "  [ERRO] job antes das abas: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # "Marcar todos os recomendados" no caminho real: janela recém-aberta, abas Tweaks e Jogos
        # ainda não montadas. Este teste tem de vir ANTES do laço de montagem abaixo - depois dele
        # as abas existem e o problema (marcar zero item) não aparece mais.
        # A aba Instalar é montada primeiro porque a janela real faz isso antes de aparecer, e
        # Reset-WPFCheckBoxes (chamada no fim de toda montagem) escreve em controles que nascem lá.
        Initialize-WinForgeTabContent -TabName 'Install'
        try {
            $wfMarcadosCedo = Select-WinForgeRecommended -Tab All
            if ($wfMarcadosCedo -le 0) { Write-Host "  [ERRO] marcar recomendados antes das abas: nenhuma caixa marcada" -ForegroundColor Red; $wbErrors++ }
            if (-not $sync.InitializedTabs['Tweaks'] -or -not $sync.InitializedTabs['Jogos']) { Write-Host "  [ERRO] marcar recomendados antes das abas: as abas não foram montadas sob demanda" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Marcar recomendados antes das abas: OK ($wfMarcadosCedo item(ns) marcado(s), abas montadas sob demanda)"
        } catch {
            Write-Host "  [ERRO] marcar recomendados antes das abas: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        foreach ($tab in 'Install','Tweaks','Jogos','Config','AppX','Diagnostico','Servidor') {
            try {
                Initialize-WinUtilTabContent -TabName $tab
                $panel = switch ($tab) { 'Install' { 'appspanel' } 'Tweaks' { 'tweakspanel' } 'Jogos' { 'gamespanel' } 'Config' { 'featurespanel' } 'AppX' { 'appxpanel' } 'Diagnostico' { 'WPFDiagCards' } 'Servidor' { 'serverpanel' } }
                $grid = $wbWindow.FindName($panel)
                $cbs = @($sync.Keys | Where-Object { $sync[$_] -is [System.Windows.Controls.CheckBox] }).Count
                Write-Host "  Aba $tab montada: $($grid.Children.Count) coluna(s), $cbs checkboxes/toggles no total até agora"
            } catch {
                Write-Host "  [ERRO] montar aba $tab`: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
            }
        }
        # Aba Servidor: no cliente ela monta VAZIA (todo item tem platform 'server' e o filtro de
        # compatibilidade esconde tudo) e isso não pode virar exceção - a aba existe na janela em
        # qualquer Windows, só o botão de navegação some. Sob WINFORGE_SIMULATE_SERVER as caixas
        # têm de aparecer de verdade; sem esta metade, o SelfTest "de servidor" só provaria que a
        # aba não explode vazia.
        try {
            $wfSrvGrid = $wbWindow.FindName('serverpanel')
            $wfSrvKeys = @($wbServerTab.PSObject.Properties | Where-Object { [string]$_.Value.Type -ne 'Button' } | ForEach-Object { $_.Name })
            $wfSrvCaixas = @($wfSrvKeys | Where-Object { $sync[$_] -is [System.Windows.Controls.CheckBox] }).Count
            if ($sync.IsServer) {
                if ($wfSrvCaixas -lt 8) { Write-Host "  [ERRO] aba Servidor: esperado ao menos 8 caixas no servidor, veio $wfSrvCaixas" -ForegroundColor Red; $wbErrors++ }
                if ($wfSrvGrid.Children.Count -eq 0) { Write-Host "  [ERRO] aba Servidor: painel vazio no servidor" -ForegroundColor Red; $wbErrors++ }
                # As 7 entradas de IIS têm role "iis": num servidor sem o papel elas somem, e é isso
                # que se quer. A trava só vale quando o papel está presente - sem ela, o SelfTest
                # "de servidor com IIS" passaria com a categoria IIS inteira invisível.
                if ('iis' -in @($sync.ServerRoles)) {
                    $wfIisCaixas = @($wfSrvKeys | Where-Object { $_ -like 'WPFTweaksWFIis*' -and $sync[$_] -is [System.Windows.Controls.CheckBox] }).Count
                    if ($wfIisCaixas -ne 7) { Write-Host "  [ERRO] aba Servidor: esperado 7 caixas de IIS com o papel IIS presente, veio $wfIisCaixas" -ForegroundColor Red; $wbErrors++ }
                    Write-Host "  Aba Servidor (IIS): $wfIisCaixas caixa(s) de IIS com o papel presente"
                }
                # Mesma regra para os botões de Active Directory (role "ad"): eles são a única coisa
                # da aba que roda dcdiag/repadmin, e num servidor com o papel presente têm de estar
                # na tela. Sem esta trava, um erro de categoria os esconderia sem ninguém notar.
                if ('ad' -in @($sync.ServerRoles)) {
                    $wfAdBotoes = @(@('WPFWFAdDcdiag', 'WPFWFAdReplSummary', 'WPFWFAdDnsScavenging', 'WPFWFAdNtdsLocation') | Where-Object { $sync[$_] -is [System.Windows.Controls.Button] }).Count
                    if ($wfAdBotoes -ne 4) { Write-Host "  [ERRO] aba Servidor: esperado 4 botões de Active Directory com o papel AD presente, veio $wfAdBotoes" -ForegroundColor Red; $wbErrors++ }
                    Write-Host "  Aba Servidor (AD): $wfAdBotoes botão(ões) de Active Directory com o papel presente"
                }
            } else {
                if ($wfSrvCaixas -ne 0) { Write-Host "  [ERRO] aba Servidor: $wfSrvCaixas caixa(s) criada(s) num cliente, esperado 0" -ForegroundColor Red; $wbErrors++ }
                if ($wfSrvGrid.Children.Count -ne 0) { Write-Host "  [ERRO] aba Servidor: painel com $($wfSrvGrid.Children.Count) coluna(s) num cliente, esperado 0" -ForegroundColor Red; $wbErrors++ }
            }
            Write-Host "  Aba Servidor: $wfSrvCaixas caixa(s), $($wfSrvGrid.Children.Count) coluna(s) | servidor=$($sync.IsServer)"
        } catch {
            Write-Host "  [ERRO] aba Servidor: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # Contornos verdes na aba Servidor: as regras de servidor só valem alguma coisa se chegarem à
        # tela. Roda com o perfil simulado 'server-iis' (o perfil real desta máquina pode ser cliente),
        # conta as linhas verdes de serverpanel e devolve $sync.Recommended ao perfil real - as
        # conferências seguintes (lista do Diagnóstico, contornos) contam com ele.
        if ($sync.IsServer -and $wbSims['server-iis']) {
            try {
                $null = Invoke-WinForgeRules -Profile $wbSims['server-iis']
                Update-WinForgeRecommendationVisuals | Out-Null
                $wfSrvVerdes = @($wfSrvKeys | ForEach-Object { Get-WinForgeRecoRow -Key $_ } | Where-Object { $_ -and $_.Border.BorderBrush -and [string]$_.Border.BorderBrush.Color -eq '#FF2E7D32' }).Count
                if ($wfSrvVerdes -lt 5) { Write-Host "  [ERRO] aba Servidor: esperado ao menos 5 contornos verdes em serverpanel, veio $wfSrvVerdes" -ForegroundColor Red; $wbErrors++ }
                else { Write-Host "  Aba Servidor (contornos): $wfSrvVerdes linha(s) verde(s) com as regras de server-iis" }
            } catch {
                Write-Host "  [ERRO] aba Servidor (contornos): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
            } finally {
                $null = Invoke-WinForgeRules -Profile $wbProfile
                Update-WinForgeRecommendationVisuals | Out-Null
            }
        }
        # Visibilidade das abas: a MESMA função que roda antes do ShowDialog, chamada nos dois
        # estados. Forçar $sync.IsServer aqui é o que permite testar o lado "servidor" num cliente
        # (e o lado "cliente" quando o SelfTest roda sob WINFORGE_SIMULATE_SERVER).
        try {
            $wfEraServidor = $sync.IsServer
            try {
                $sync.IsServer = $true
                Update-WinForgeTabVisibility | Out-Null
                if ($sync.WPFTab7BT.Visibility -ne [Windows.Visibility]::Collapsed) { Write-Host "  [ERRO] abas (servidor): WPFTab7BT (Jogos) deveria estar oculto" -ForegroundColor Red; $wbErrors++ }
                if ($sync.WPFTab5BT.Visibility -ne [Windows.Visibility]::Collapsed) { Write-Host "  [ERRO] abas (servidor): WPFTab5BT (Win11ISO) deveria estar oculto" -ForegroundColor Red; $wbErrors++ }
                # A aba AppX não tem botão na barra: o caminho até ela é o 'AppX Removal' da aba Tweaks.
                if ($sync.WPFAppxRemoval.Visibility -ne [Windows.Visibility]::Collapsed) { Write-Host "  [ERRO] abas (servidor): WPFAppxRemoval (AppX) deveria estar oculto" -ForegroundColor Red; $wbErrors++ }
                if ($sync.WPFTab9BT.Visibility -ne [Windows.Visibility]::Visible) { Write-Host "  [ERRO] abas (servidor): WPFTab9BT (Servidor) deveria estar visível" -ForegroundColor Red; $wbErrors++ }
                $sync.IsServer = $false
                Update-WinForgeTabVisibility | Out-Null
                if ($sync.WPFTab7BT.Visibility -ne [Windows.Visibility]::Visible) { Write-Host "  [ERRO] abas (cliente): WPFTab7BT (Jogos) deveria estar visível" -ForegroundColor Red; $wbErrors++ }
                if ($sync.WPFTab9BT.Visibility -ne [Windows.Visibility]::Collapsed) { Write-Host "  [ERRO] abas (cliente): WPFTab9BT (Servidor) deveria estar oculto" -ForegroundColor Red; $wbErrors++ }
                if ($sync.WPFAppxRemoval.Visibility -ne [Windows.Visibility]::Visible) { Write-Host "  [ERRO] abas (cliente): WPFAppxRemoval (AppX) deveria estar visível" -ForegroundColor Red; $wbErrors++ }
            } finally {
                $sync.IsServer = $wfEraServidor
                Update-WinForgeTabVisibility | Out-Null
            }
            Write-Host "  Visibilidade das abas: OK nos dois estados (estado final: servidor=$($sync.IsServer))"
        } catch {
            Write-Host "  [ERRO] visibilidade das abas: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # Aba Diagnóstico: cartões, tabela de drivers, lista de recomendações e relatório HTML.
        # A contagem esperada de recomendações é recalculada aqui a partir de $sync.Recommended/
        # Discouraged - repetir a conta da UI não provaria nada.
        try {
            $wfCards = $sync.WPFDiagCards.Children.Count
            # 9 cartões fixos (Sistema, Máquina, Processador, Memória, Placa de vídeo, Armazenamento,
            # Rede, Energia, Segurança e estado) + o cartão Servidor, que só existe no Windows Server.
            $wfCardsEsperado = 9 + $(if ($sync.IsServer) { 1 } else { 0 })
            if ($wfCards -ne $wfCardsEsperado) { Write-Host "  [ERRO] Diagnóstico: esperado $wfCardsEsperado cartões (servidor=$($sync.IsServer)), veio $wfCards" -ForegroundColor Red; $wbErrors++ }
            $wfDrvUI = $sync.WPFDiagDrivers.Items.Count
            $wfDrvPerfil = @($sync.Profile.Drivers).Count
            if ($wfDrvUI -ne $wfDrvPerfil) { Write-Host "  [ERRO] Diagnóstico: tabela com $wfDrvUI driver(s), perfil com $wfDrvPerfil" -ForegroundColor Red; $wbErrors++ }
            $wfRecEsperado = @(@($sync.Recommended.Keys) + @($sync.Discouraged.Keys) | Where-Object { $_ -and $sync.configs.tweaks.PSObject.Properties[$_] }).Count
            if ($sync.WPFDiagRecs.Items.Count -ne $wfRecEsperado) { Write-Host "  [ERRO] Diagnóstico: $($sync.WPFDiagRecs.Items.Count) recomendação(ões) na lista, esperado $wfRecEsperado" -ForegroundColor Red; $wbErrors++ }
            $wfRelPath = Join-Path $env:TEMP "winforge-diag-selftest.html"
            $wfRel = Export-WinForgeDiagnosticsReport -Path $wfRelPath -NoOpen
            if (-not $wfRel -or -not (Test-Path $wfRel)) {
                Write-Host "  [ERRO] Diagnóstico: relatório HTML não foi gerado" -ForegroundColor Red; $wbErrors++
            } else {
                $wfRelTam = (Get-Item $wfRel).Length
                $wfRelHtml = [System.IO.File]::ReadAllText($wfRel, [System.Text.Encoding]::UTF8)
                if ($wfRelTam -lt 5KB) { Write-Host "  [ERRO] Diagnóstico: relatório com $wfRelTam byte(s), esperado mais de 5 KB" -ForegroundColor Red; $wbErrors++ }
                $wfCpuHtml = [System.Net.WebUtility]::HtmlEncode([string]$sync.Profile.CPU.Name)
                if (-not $wfRelHtml.Contains($wfCpuHtml)) { Write-Host "  [ERRO] Diagnóstico: relatório sem o nome da CPU ('$wfCpuHtml')" -ForegroundColor Red; $wbErrors++ }
                Write-Host "  Aba Diagnóstico: $wfCards cartões, $wfDrvUI drivers, $($sync.WPFDiagRecs.Items.Count) recomendações | relatório $([math]::Round($wfRelTam / 1KB)) KB"
                if (-not $env:WINFORGE_KEEP_REPORT) { Remove-Item -Path $wfRel -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            Write-Host "  [ERRO] aba Diagnóstico: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        $wbLogo = Invoke-WinForgeAssets -Type "logo" -Size 25
        if ($null -eq $wbLogo -or @($wbLogo.Child.Children).Count -ne 4) { Write-Host "  [ERRO] logo: esperado 4 paths no canvas" -ForegroundColor Red; $wbErrors++ } else { Write-Host "  Logo: OK" }
        foreach ($n in 'WPFTweaksWBGameCS2','WPFTweaksWBGameDVR','WPFToggleWBHAGS','WPFTweaksWBPowerSettings','WPFPanelWBClearRam','WPFTweaksWBNvidiaShaderCache') {
            if ($null -eq $sync[$n]) { Write-Host "  [ERRO] controle '$n' não foi criado" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($n in @($wbHidden) + @($wbHiddenAppx)) {
            if ($null -ne $sync[$n]) { Write-Host "  [ERRO] controle oculto '$n' foi criado mesmo assim" -ForegroundColor Red; $wbErrors++ }
        }
        # Contornos: Update-WinForgeRecommendationVisuals roda no fim de cada montagem de aba, então
        # o perfil real já tem de ter pintado alguma linha aqui (as regras rodaram antes do mount).
        try {
            $wbPintadas = @(@($sync.Recommended.Keys) + @($sync.Discouraged.Keys) | Sort-Object -Unique | ForEach-Object { Get-WinForgeRecoRow -Key $_ } | Where-Object { $_ -and $_.Border.BorderBrush })
            if (@($sync.Recommended.Keys).Count -gt 0 -and $wbPintadas.Count -eq 0) { Write-Host "  [ERRO] contornos: nenhuma linha recebeu BorderBrush" -ForegroundColor Red; $wbErrors++ }
            # idempotência: a segunda passada não pode empilhar prefixo nem perder a dica original
            if ($wbPintadas.Count -gt 0) {
                $wbTipAntes = [string]$wbPintadas[0].Tip.ToolTip
                Update-WinForgeRecommendationVisuals | Out-Null
                $wbTipDepois = [string]$wbPintadas[0].Tip.ToolTip
                if ($wbTipAntes -ne $wbTipDepois) { Write-Host "  [ERRO] contornos: dica mudou na segunda passada (prefixo empilhado?)" -ForegroundColor Red; $wbErrors++ }
                if (-not $wbPintadas[0].Border.BorderBrush) { Write-Host "  [ERRO] contornos: BorderBrush perdido na segunda passada" -ForegroundColor Red; $wbErrors++ }
            }
            Write-Host "  Contornos: $($wbPintadas.Count) linha(s) com contorno de recomendação"
        } catch {
            Write-Host "  [ERRO] contornos: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # Busca com as linhas embrulhadas em Border: quem some/aparece é o Border, não o painel interno
        try {
            $sync.currentTab = "Tweaks"
            $wbBordaCortana = (Get-WinForgeRecoRow -Key 'WPFTweaksWBCortana').Border
            $wbBordaActivity = (Get-WinForgeRecoRow -Key 'WPFTweaksActivity').Border
            Find-TweaksByNameOrDescription -SearchString 'Cortana'
            if ($wbBordaCortana.Visibility -ne [Windows.Visibility]::Visible) { Write-Host "  [ERRO] busca 'Cortana': WPFTweaksWBCortana deveria estar visível" -ForegroundColor Red; $wbErrors++ }
            if ($wbBordaActivity.Visibility -ne [Windows.Visibility]::Collapsed) { Write-Host "  [ERRO] busca 'Cortana': WPFTweaksActivity deveria estar oculto" -ForegroundColor Red; $wbErrors++ }
            Find-TweaksByNameOrDescription -SearchString ""
            if ($wbBordaCortana.Visibility -ne [Windows.Visibility]::Visible -or $wbBordaActivity.Visibility -ne [Windows.Visibility]::Visible) { Write-Host "  [ERRO] busca vazia: as duas linhas deveriam voltar a aparecer" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Busca: filtro e reset OK com as linhas embrulhadas em Border"
        } catch {
            Write-Host "  [ERRO] busca: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        try {
            Invoke-WPFPresets "Gamer" -checkboxfilterpattern "WPFTweak*"
            Write-Host "  Preset Gamer: $($sync.selectedTweaks.Count) tweaks selecionados -> $($sync.selectedTweaks -join ', ')"
            Invoke-WPFPresets "AppxWinForge" -checkboxfilterpattern "WPFAppx*"
            Write-Host "  Preset AppxWinForge: $($sync.selectedAppx.Count) pacotes selecionados"
        } catch {
            Write-Host "  [ERRO] presets: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # depois dos presets, porque Invoke-WPFPresets desmarca o que não é do preset
        try {
            $wbSelTweaks = Select-WinForgeRecommended -Tab "Tweaks"
            $wbSelJogos  = Select-WinForgeRecommended -Tab "Jogos"
            $wbSelServer = Select-WinForgeRecommended -Tab "Servidor"
            $wbSelAll    = Select-WinForgeRecommended -Tab "All"
            # No cliente a aba Servidor não entra em 'All' (nem existe na janela): a soma esperada
            # muda com $sync.IsServer, e é isso que a segunda rodada do SelfTest exercita.
            $wbSelEsperado = $wbSelTweaks + $wbSelJogos + $(if ($sync.IsServer) { $wbSelServer } else { 0 })
            if ($wbSelAll -ne $wbSelEsperado) { Write-Host "  [ERRO] Select-WinForgeRecommended: All ($wbSelAll) != Tweaks ($wbSelTweaks) + Jogos ($wbSelJogos) + Servidor ($wbSelServer, servidor=$($sync.IsServer))" -ForegroundColor Red; $wbErrors++ }
            if ($wbSelAll -le 0) { Write-Host "  [ERRO] Select-WinForgeRecommended: nenhuma caixa marcada no perfil real" -ForegroundColor Red; $wbErrors++ }
            foreach ($k in @($sync.Recommended.Keys)) {
                if ($sync[$k] -isnot [System.Windows.Controls.CheckBox]) { continue }
                # toggle é CheckBox mas aplica o tweak ao ser marcado: a função pula, e aqui a
                # mensagem tem de dizer isso, não "não foi marcado"
                if ($k -like 'WPFToggle*' -or [string]$sync.configs.tweaks.$k.Type -eq 'Toggle') {
                    Write-Host "  [ERRO] Select-WinForgeRecommended: '$k' é Toggle e não pode entrar em recomendação" -ForegroundColor Red; $wbErrors++
                    continue
                }
                if (-not $sync[$k].IsChecked) { Write-Host "  [ERRO] Select-WinForgeRecommended: '$k' não foi marcado" -ForegroundColor Red; $wbErrors++ }
                # marcar dispara o handler Checked, que é quem alimenta $sync.selectedTweaks
                if ($k -like 'WPFTweaks*' -and -not $sync.selectedTweaks.Contains($k)) { Write-Host "  [ERRO] Select-WinForgeRecommended: '$k' não entrou em selectedTweaks" -ForegroundColor Red; $wbErrors++ }
            }
            Write-Host "  Recomendados marcados: $wbSelAll (Tweaks $wbSelTweaks, Jogos $wbSelJogos, Servidor $wbSelServer) | selectedTweaks=$($sync.selectedTweaks.Count)"
        } catch {
            Write-Host "  [ERRO] Select-WinForgeRecommended: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # Job de diagnóstico: mesmo corpo que roda na janela real, aqui na thread atual (sem janela
        # mostrada não há Add_ContentRendered). Write-WinForgeLog vai para o host quando o log é o
        # próprio transcript, então o 6>&1 é o que captura as linhas do log para conferir.
        try {
            $sync.Profile = $null
            $sync.ProfileJobRunning = $false
            $wbJobLog = (Start-WinForgeProfileJob -Synchronous -SkipNetwork 6>&1 | Out-String -Width 500)
            Write-Host $wbJobLog.TrimEnd()
            if ($null -eq $sync.Profile) { Write-Host "  [ERRO] job: `$sync.Profile continuou nulo" -ForegroundColor Red; $wbErrors++ }
            if ($sync.ProfileJobRunning) { Write-Host "  [ERRO] job: ProfileJobRunning ficou ligado no fim" -ForegroundColor Red; $wbErrors++ }
            if ($wbJobLog -notmatch 'Diagnóstico iniciado \(job\)') { Write-Host "  [ERRO] job: log sem 'Diagnóstico iniciado'" -ForegroundColor Red; $wbErrors++ }
            if ($wbJobLog -notmatch 'Diagnóstico pronto') { Write-Host "  [ERRO] job: log sem 'Diagnóstico pronto'" -ForegroundColor Red; $wbErrors++ }
            if ($wbJobLog -match 'Diagnóstico falhou') { Write-Host "  [ERRO] job: o diagnóstico falhou" -ForegroundColor Red; $wbErrors++ }
            # a barra é compartilhada: com outro trabalho rodando o diagnóstico não pode escrever nela
            $sync.ProcessRunning = $true
            $wbLabelAntes = $sync.ProfileJobLabel
            if ((Set-WinForgeProfileProgress -Label "não deveria aparecer" -Percent 50) -ne $false) { Write-Host "  [ERRO] job: escreveu na barra com ProcessRunning ligado" -ForegroundColor Red; $wbErrors++ }
            if ($sync.ProfileJobLabel -ne $wbLabelAntes) { Write-Host "  [ERRO] job: rótulo da barra mudou com ProcessRunning ligado" -ForegroundColor Red; $wbErrors++ }
            $sync.ProcessRunning = $false
            Write-Host "  Job de diagnóstico: OK | barra: $($sync.ProfileJobLabel)"
        } catch {
            Write-Host "  [ERRO] job de diagnóstico: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # O job real roda em uma runspace do pool, e o transcript não captura nada do que sai de lá.
        # Esta sonda é a prova de que uma entrada escrita de dentro do pool chega ao arquivo do log.
        try {
            $wfOpenedPool = $false
            if (-not $sync.runspace) { Initialize-WinForgeRunspacePool | Out-Null; $wfOpenedPool = $true }
            $null = Invoke-WPFRunspace -ScriptBlock { Write-WinForgeLog -Component "Probe" -Message "runspace-log-probe" }
            $wfProbeOk = $false
            $wfDeadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $wfDeadline) {
                Start-Sleep -Milliseconds 200
                try { $wfTail = @(Get-Content -Path $sync.logPath -Tail 50 -ErrorAction Stop) } catch { $wfTail = @() }
                if ($wfTail -match 'runspace-log-probe') { $wfProbeOk = $true; break }
            }
            if ($wfOpenedPool) { Close-WinForgeRunspacePool }
            if ($wfProbeOk) { Write-Host "  Log de runspace: OK" }
            else { Write-Host "  [ERRO] log de runspace não chegou ao arquivo" -ForegroundColor Red; $wbErrors++ }
        } catch {
            Write-Host "  [ERRO] log de runspace: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # O diagnóstico DE VERDADE (sem -Synchronous): o corpo vai para uma runspace do pool e pede a
        # atualização da janela pelo Dispatcher, atravessando a fronteira entre as duas runspaces.
        # É o único ponto do SelfTest que exercita esse caminho - e era exatamente ali que o job
        # morria calado, porque o Dispatcher executa o pedido na runspace de quem criou o scriptblock:
        # criado dentro do job, ele trava no primeiro pipeline (a runspace do pool está parada em
        # Dispatcher.Invoke esperando o callback, e o callback espera a runspace).
        # Aviso: se a regressão voltar, este teste não acusa erro - ele TRAVA junto, porque quem fica
        # preso dentro do callback é esta mesma thread. SelfTest que não termina aqui é o sintoma.
        try {
            $wfOpenedPool2 = $false
            if (-not $sync.runspace) { Initialize-WinForgeRunspacePool | Out-Null; $wfOpenedPool2 = $true }
            $sync.Profile = $null
            $sync.ProfileJobRunning = $false
            $sync.ProfileJobLabel = $null
            $sync.WPFDiagStatus.Text = ''
            $sync.WPFDiagCards.Children.Clear()
            Start-WinForgeProfileJob -Force -SkipNetwork
            # Sem bombear a fila do Dispatcher aqui, o pedido da outra runspace nunca seria atendido:
            # esta thread criou a janela, mas no SelfTest não roda laço de mensagens nenhum.
            $wfUiDeadline = (Get-Date).AddSeconds(90)
            while ($sync.ProfileJobRunning -and (Get-Date) -lt $wfUiDeadline) {
                $sync.Form.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{})
                Start-Sleep -Milliseconds 100
            }
            if ($wfOpenedPool2) { Close-WinForgeRunspacePool }
            if ($sync.ProfileJobRunning) {
                Write-Host "  [ERRO] job na runspace do pool: não terminou em 90 s" -ForegroundColor Red; $wbErrors++
            } elseif ([string]$sync.ProfileJobLabel -notmatch 'Diagnóstico pronto') {
                Write-Host "  [ERRO] job na runspace do pool: terminou sem 'Diagnóstico pronto' (barra = '$($sync.ProfileJobLabel)')" -ForegroundColor Red; $wbErrors++
            } elseif ($sync.WPFDiagStatus.Text -notmatch '^Diagnóstico de') {
                Write-Host "  [ERRO] job na runspace do pool: a aba não foi redesenhada (status = '$($sync.WPFDiagStatus.Text)')" -ForegroundColor Red; $wbErrors++
            } else {
                Write-Host "  Job na runspace do pool: OK ($($sync.WPFDiagCards.Children.Count) cartões redesenhados pela thread da janela)"
            }
        } catch {
            Write-Host "  [ERRO] job na runspace do pool: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
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

# ---------------------------------------------------------------- fechamento da janela com job em andamento
# Close-WinUtilRunspacePool é síncrono: para cada pipeline e ESPERA a thread do pool terminar. Como
# o diagnóstico agora roda a cada abertura (e a busca no Windows Update é uma chamada COM que não se
# interrompe), fechar a janela no meio de um deles congelava a janela por até um minuto - ou travava
# de vez, se a thread do pool estivesse dentro de um Dispatcher.Invoke esperando esta mesma thread.
$src = Replace-Once $src @'
$sync["Form"].Add_Closing({
    Close-WinUtilRunspacePool
    [System.GC]::Collect()
})
'@ @'
$sync["Form"].Add_Closing({
    # avisa o diagnóstico e a busca de drivers: daqui em diante ninguém mais toca na interface
    $sync.WinForgeClosing = $true
    if ($sync.ProfileJobRunning -or $sync.DiagWUSearchRunning) {
        # Fecha sem esperar: as threads do pool são de segundo plano e morrem com o processo.
        try { $sync.runspace.BeginClose($null, $null) | Out-Null } catch { }
        $sync.Remove("runspace")
    } else {
        Close-WinUtilRunspacePool
    }
    [System.GC]::Collect()
})
'@ "closing hook"

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

    # WinForge: diagnóstico do sistema em segundo plano (perfil + regras -> contornos e aba Diagnóstico)
    $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ Start-WinForgeProfileJob }) | Out-Null

    # WinForge: pergunta (opcional) sobre ponto de restauração depois que a janela aparece
    $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [action]{ Invoke-WinUtilBoostRestorePointPrompt }) | Out-Null
'@.TrimEnd() "restore prompt hook"

# ---------------------------------------------------------------- abas por tipo de Windows (servidor x cliente)
# Antes do ShowDialog e na thread da janela: em servidor somem Win11ISO, AppX e Jogos e aparece a
# aba Servidor; no cliente é o contrário. Feito aqui, e não no Add_ContentRendered acima, para que
# a barra de navegação já apareça certa - dentro do ContentRendered a janela já está desenhada e o
# usuário veria as abas piscarem.
$src = Insert-Before $src '$sync["Form"].ShowDialog() | out-null' @'
# WinForge: esconde as abas que não fazem sentido neste Windows (servidor x cliente)
Update-WinForgeTabVisibility | Out-Null

'@ "tab visibility startup"

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

# Depois do de Jogos e na mesma âncora: o bloco inserido por último fica mais perto dela, então o
# botão do Diagnóstico aparece à direita do de Jogos na barra de navegação.
$src = Insert-Before $src @'
                <ToggleButton Style="{StaticResource TabToggleButton}" Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"
                    Background="{DynamicResource ButtonConfigBackgroundColor}"
'@ $xamlDiagNav "xaml diag nav button"

# Por último na mesma âncora: o botão da aba Servidor fica à direita do de Diagnóstico.
$src = Insert-Before $src @'
                <ToggleButton Style="{StaticResource TabToggleButton}" Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"
                    Background="{DynamicResource ButtonConfigBackgroundColor}"
'@ $xamlServerNav "xaml server nav button"

$src = Insert-Before $src "        </TabControl>`n" $xamlTab "xaml games tab"

# Precisa vir DEPOIS do insert da aba Jogos: Invoke-WPFTab mapeia WPFTab<N>BT para Items[N-1], então
# o TabItem do Diagnóstico (WPFTab8) tem de ser o oitavo do TabControl - e, na mesma âncora, quem
# insere por último fica mais perto dela, ou seja, depois de Jogos.
$src = Insert-Before $src "        </TabControl>`n" $xamlDiagTab "xaml diag tab"

# Mesma regra: WPFTab9BT -> Items[8], então o TabItem da aba Servidor tem de ser o nono do
# TabControl - e quem insere por último na âncora fica mais perto dela, ou seja, depois do
# Diagnóstico.
$src = Insert-Before $src "        </TabControl>`n" $xamlServerTab "xaml server tab"

$src = Insert-After $src '                                    <Button Name="WPFAdvanced" Content=" Advanced " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>' @'

                                    <Button Name="WPFPresetWinForge" Content=" WinForge " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}" ToolTip="Preset Standard + serviços seguros, anúncios, Cortana, pesquisa, NTFS, energia e hibernação (WinForge)."/>
                                    <Button Name="WPFSelectRecommended" Content=" Marcar recomendados " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}" ToolTip="Marca os itens que o diagnóstico recomenda para este PC (contorno verde)."/>
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
$jsonTweaks = @((Get-JsonConfigBlock $src 'tweaks'), (Get-JsonConfigBlock $src 'wbtweaks'), (Get-JsonConfigBlock $src 'wfserver'))

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
