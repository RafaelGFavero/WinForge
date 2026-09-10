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

function Replace-All([string]$text, [string]$old, [string]$new, [string]$what) {
    # Irmã do Replace-Once para texto que se repete de propósito (a mesma categoria em cada entrada
    # do JSON, a mesma mensagem em dois caminhos de código). Falha alto quando NÃO acha nada - é
    # esse o caso que denuncia uma âncora que sumiu do arquivo base.
    $old = $old -replace "`r`n", "`n"
    $new = $new -replace "`r`n", "`n"
    $count = 0
    $idx = 0
    while (($idx = $text.IndexOf($old, $idx, [StringComparison]::Ordinal)) -ge 0) {
        $text = $text.Substring(0, $idx) + $new + $text.Substring($idx + $old.Length)
        # avança pelo tamanho do NOVO texto: sem isso, uma tradução que contenha o original
        # (ou parte dele) faria o laço achar a si mesmo para sempre.
        $idx += $new.Length
        $count++
    }
    if ($count -eq 0) { throw "Âncora não encontrada: $what" }
    $script:wfI18nHits += $count
    return $text
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
$repairConfig   = Read-Lf (Join-Path $PSScriptRoot "config\wf-repair-config.ps1")
$auditBlock     = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-audit.ps1")
$profileBlock   = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-profile.ps1")
$driversBlock   = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-drivers.ps1")
$rulesBlock     = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-rules.ps1")
$recoUiBlock    = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-recoui.ps1")
$diagBlock      = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-diag.ps1")
$commandsBlock  = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-commands.ps1")
$repairBlock    = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-repair.ps1")
$serverBlock    = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-server.ps1")
$auditData      = Read-Lf (Join-Path $PSScriptRoot "config\wf-audit.ps1")
$rulesData      = Read-Lf (Join-Path $PSScriptRoot "config\wf-rules.ps1")
$xamlNav        = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-nav.xml")
$xamlTab        = Read-Lf (Join-Path $PSScriptRoot "xaml\wb-xaml-tab.xml")
$xamlDiagTab    = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-diag-tab.xml")
$xamlServerTab  = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-server-tab.xml")
$appsData       = Read-Lf (Join-Path $PSScriptRoot "config\wf-apps.ps1")

# Dicionário de tradução: é código, não bloco injetado, então tem de ser EXECUTADO. Dot-source do
# arquivo não serve (o PowerShell 5.1 lê .ps1 pela code page ANSI quando não há BOM); ler o texto em
# UTF-8 e rodar um scriptblock mantém os acentos independentemente do BOM.
. ([scriptblock]::Create([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "config\wf-i18n-strings.ps1"), [System.Text.Encoding]::UTF8)))
$wfI18nHits = 0

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
$src = Insert-Before $src "`$inputXML = @'" ($repairConfig.TrimEnd() + "`n`n") "insert repair config"
$src = Insert-Before $src "`$inputXML = @'" ($auditData.TrimEnd() + "`n`n") "insert audit data"
$src = Insert-Before $src "`$inputXML = @'" ($rulesData.TrimEnd() + "`n`n") "insert rules data"
$src = Insert-Before $src "`$inputXML = @'" ($appsData.TrimEnd() + "`n`n") "insert apps data"

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

# ---------------------------------------------------------------- comandos com janela de saída (núcleo genérico)
# ANTES do bloco da aba Servidor de propósito: todas as inserções usam a mesma âncora, e cada uma
# entra logo acima dela - então quem insere primeiro fica mais ACIMA no arquivo gerado. É o núcleo
# genérico que os invólucros da aba Servidor chamam, e ele nasce antes deles.
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($commandsBlock.TrimEnd() + "`n`n") "insert commands"

# ---------------------------------------------------------------- reparo de componentes (aba Config)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($repairBlock.TrimEnd() + "`n`n") "insert repair"

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
        "Install" {
            Initialize-WPFUI -targetGridName "appscategory"

            Initialize-WPFUI -targetGridName "appspanel"
        }
        "Tweaks" {
            Invoke-WPFUIElements -configVariable $sync.configs.tweaks -targetGridName "tweakspanel" -columncount 2
        }
'@ @'
        "Install" {
            Initialize-WPFUI -targetGridName "appscategory"

            Initialize-WPFUI -targetGridName "appspanel"

            # WinForge: a lista tem centenas de aplicativos em dez grupos. Aberta, ela obriga a
            # rolar muito antes de achar qualquer coisa - então nasce fechada, com os títulos dos
            # grupos à mostra.
            Set-WinForgeInstallCollapsed
        }
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
    if ($sync.configs.feature.$Button -and $Button -notlike "WPFWFRep*") {
        $buttonConfig = $sync.configs.feature.$Button
    } elseif ($sync.configs.tweaks.$Button -and $sync.configs.tweaks.$Button.Type -eq "Button" -and $Button -notlike "WPFWFSrv*" -and $Button -notlike "WPFWFAd*") {
        # WinForge: botões definidos na config de tweaks (aba Jogos)
        $buttonConfig = $sync.configs.tweaks.$Button
    }
    # Os botões da aba Servidor (WPFWFSrv*, WPFWFAd*) e os do reparo de componentes (WPFWFRep*, na
    # config de Config) ficam de fora de propósito: este caminho chama $buttonConfig.function SEM
    # argumento nenhum, e as funções deles precisam do -Name para saber qual comando rodar. Quem
    # despacha esses botões é o switch abaixo, com o -Name explícito por caso - por isso a config
    # deles também não declara "function": seria uma chave morta.
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
        # Reparo de componentes (aba Config): mesma regra dos botões da aba Servidor - o nome curto do
        # comando é dito AQUI, porque o caminho da config não passaria argumento nenhum.
        "WPFWFRepSecurityStatus" {Invoke-WinForgeRepairCommand -Name SecurityStatus}
        "WPFWFRepSmartReport" {Invoke-WinForgeRepairCommand -Name SmartReport}
        "WPFWFRepDotNetStatus" {Invoke-WinForgeRepairCommand -Name DotNetStatus}
        "WPFWFRepChkdskScan" {Invoke-WinForgeRepairCommand -Name ChkdskScan}
        "WPFWFRepWmiRepair" {Invoke-WinForgeRepairCommand -Name WmiRepair}
        "WPFWFRepStoreReregister" {Invoke-WinForgeRepairCommand -Name StoreReregister}
        "WPFWFRepChkdskSchedule" {Invoke-WinForgeRepairCommand -Name ChkdskSchedule}
        "WPFWFRepMemoryDiag" {Invoke-WinForgeRepairCommand -Name MemoryDiag}
        "WPFWFRepDotNet35Enable" {Invoke-WinForgeRepairCommand -Name DotNet35Enable}
        "WPFWFRepVcRedist" {Invoke-WinForgeRepairCommand -Name VcRedist}
        "WPFWFRepPowerShell7" {Invoke-WinForgeRepairCommand -Name PowerShell7}
        "WPFWFRepDirectX" {Invoke-WinForgeRepairCommand -Name DirectX}
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
$sync.configs.applicationsHashtable = @{}
$sync.configs.applications.PSObject.Properties | ForEach-Object {
    $sync.configs.applicationsHashtable[$_.Name] = $_.Value
}

$sync.configs.appxHashtable = @{}
$sync.configs.appx.PSObject.Properties | ForEach-Object {
    $sync.configs.appxHashtable[$_.Name] = $_.Value
}
$sync.preferences.theme = "Auto"
'@ @'
# WinForge: mescla tweaks/botões/presets/jogos, marca recursos só do Windows 11 e faz a curadoria
# da lista de aplicativos. Vem ANTES dos hashtables derivados: applicationsHashtable é a fonte da
# aba Instalar, então um aplicativo removido depois dele continuaria virando controle na tela.
Initialize-WinUtilBoostConfigs

$sync.configs.applicationsHashtable = @{}
$sync.configs.applications.PSObject.Properties | ForEach-Object {
    $sync.configs.applicationsHashtable[$_.Name] = $_.Value
}

$sync.configs.appxHashtable = @{}
$sync.configs.appx.PSObject.Properties | ForEach-Object {
    $sync.configs.appxHashtable[$_.Name] = $_.Value
}

# WinForge: aplica a classificação de risco (Seguro/Cuidado/Removido) em tweaks e presets
Initialize-WinForgeAudit

if ($SelfTest) {
    # PRIMEIRA linha do bloco, antes de qualquer teste: daqui para baixo toda função que ESCREVE no
    # sistema se recusa a rodar (Assert-WinForgeNotSelfTest e a trava de Invoke-WinForgeCommandCore).
    # A execução normal do WinForge nunca define esta chave, e chave ausente em hashtable é $null.
    $sync.SelfTest = $true
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
    if (@($sync.configs.feature.PSObject.Properties).Count -ne 54) { Write-Host "  [ERRO] Config: esperado 54 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbTweaksTab.PSObject.Properties).Count -ne 83) { Write-Host "  [ERRO] aba Tweaks: esperado 83 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbGamesTab.PSObject.Properties).Count -ne 84) { Write-Host "  [ERRO] aba Jogos: esperado 84 entradas" -ForegroundColor Red; $wbErrors++ }
    if (@($wbServerTab.PSObject.Properties).Count -ne 22) { Write-Host "  [ERRO] aba Servidor: esperado 22 entradas" -ForegroundColor Red; $wbErrors++ }
    # Aba Instalar: a curadoria de wf-apps.ps1 tem de ter rodado ANTES de applicationsHashtable -
    # é dele que a aba nasce, então uma chave removida tarde demais volta como controle na tela.
    $wfApps = @($sync.configs.applications.PSObject.Properties)
    $wfAppsCategorias = @($wfApps | ForEach-Object { [string]$_.Value.Category } | Sort-Object -Unique)
    Write-Host "  Aba Instalar: $($wfApps.Count) aplicativo(s) em $($wfAppsCategorias.Count) grupo(s) -> $($wfAppsCategorias -join ', ')"
    if ($wfApps.Count -ne 137) { Write-Host "  [ERRO] aba Instalar: esperado 137 aplicativos, veio $($wfApps.Count)" -ForegroundColor Red; $wbErrors++ }
    if (@($sync.WinForgeRemovedApps).Count -ne 95) { Write-Host "  [ERRO] aba Instalar: esperado 95 chaves em WinForgeRemovedApps, veio $(@($sync.WinForgeRemovedApps).Count)" -ForegroundColor Red; $wbErrors++ }
    $wfSobrando = @($sync.WinForgeRemovedApps | Where-Object { $sync.configs.applications.PSObject.Properties[$_] -or $sync.configs.applicationsHashtable.ContainsKey($_) })
    if ($wfSobrando.Count) { Write-Host "  [ERRO] aba Instalar: aplicativo(s) que deveriam ter saído continuam na lista: $($wfSobrando -join ', ')" -ForegroundColor Red; $wbErrors++ }
    # Todo grupo na tela tem de sair do mapa (ou de um override) de wf-apps.ps1: uma categoria nova
    # na base, ou uma linha que sumiu do mapa, apareceria em inglês no meio dos outros.
    $wfGruposPermitidos = @(@($sync.WinForgeAppCategoryMap.Values) + @($sync.WinForgeAppCategoryOverride.Values) | Sort-Object -Unique)
    $wfIngles = @($wfAppsCategorias | Where-Object { $_ -notin $wfGruposPermitidos })
    if ($wfIngles.Count) { Write-Host "  [ERRO] aba Instalar: grupo(s) fora do mapa pt-BR: $($wfIngles -join ', ')" -ForegroundColor Red; $wbErrors++ }
    if ([string]$sync.configs.applications.WPFInstallplexdesktop.Category -ne 'Multimídia') { Write-Host "  [ERRO] aba Instalar: WPFInstallplexdesktop deveria estar em Multimídia, está em '$($sync.configs.applications.WPFInstallplexdesktop.Category)'" -ForegroundColor Red; $wbErrors++ }
    if ([string]$sync.configs.applications.WPFInstalllocalsend.Category -ne 'Utilitários') { Write-Host "  [ERRO] aba Instalar: WPFInstalllocalsend deveria estar em Utilitários, está em '$($sync.configs.applications.WPFInstalllocalsend.Category)'" -ForegroundColor Red; $wbErrors++ }
    if ($sync.currentTab -ne "Diagnostico") { Write-Host "  [ERRO] aba de abertura: `$sync.currentTab = '$($sync.currentTab)', esperado 'Diagnostico'" -ForegroundColor Red; $wbErrors++ }
    # Trava de idioma. A lista de termos é injetada pelo build logo acima ($sync.WinForgeEnglishSweep),
    # DEPOIS do dicionário de tradução - se ela viesse antes, o próprio dicionário a traduziria e a
    # trava passaria por não ter mais o que procurar. Aqui a varredura é sobre o XAML gerado; a
    # Tarefa 3 usa a mesma função no Content/Description das configurações.
    $wfIdiomaXaml = Test-WinForgeEnglishLeftovers -Text $inputXML -Where 'XAML' -Xaml
    if ($wfIdiomaXaml) { $wbErrors += $wfIdiomaXaml }
    else { Write-Host "  Idioma: $(@($sync.WinForgeEnglishSweep).Count) termo(s) em inglês procurados no XAML, nenhum encontrado" }
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
        # Sob simulação o perfil relata ProductType 3 numa máquina que é 1: sem esta marca, o
        # relatório HTML afirmaria um tipo de produto que não é o da máquina, sem ressalva nenhuma.
        if ($wbProfile.Simulated -ne 'env:WINFORGE_SIMULATE_SERVER') { Write-Host "  [ERRO] perfil simulado: esperado Simulated = 'env:WINFORGE_SIMULATE_SERVER', veio '$($wbProfile.Simulated)'" -ForegroundColor Red; $wbErrors++ }
        if ($null -eq $wbProfile.Server) { Write-Host "  [ERRO] perfil simulado: Server não deveria ser null sob WINFORGE_SIMULATE_SERVER" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Perfil simulado: servidor=$($wbProfile.OS.IsServer) IIS=$($wbProfile.Roles.IIS) DC=$($wbProfile.Roles.IsDC) | Server.TimeSource=$(if ($null -eq $wbProfile.Server.TimeSource) { '(null)' } else { $wbProfile.Server.TimeSource })" }
    } elseif ($wbProfile.OS.IsServer -ne $true -and $null -ne $wbProfile.Server) {
        Write-Host "  [ERRO] perfil: Server deveria ser null num cliente sem simulação" -ForegroundColor Red; $wbErrors++
    } elseif ($null -ne $wbProfile.Simulated) {
        Write-Host "  [ERRO] perfil: Simulated deveria ser null sem simulação (veio '$($wbProfile.Simulated)')" -ForegroundColor Red; $wbErrors++
    }
    # Detecção do tipo de Windows: o registro responde primeiro (12 ms contra 100-190 ms do CIM) e é
    # o único caminho que sobrevive a um repositório WMI corrompido, onde a aba Servidor sumia calada.
    $wbProdTipo = Get-WinForgeWindowsProductType
    if ($wbProdTipo.Source -ne 'registry') { Write-Host "  [ERRO] detecção: o tipo de produto deveria vir do registro, veio de '$($wbProdTipo.Source)'" -ForegroundColor Red; $wbErrors++ }
    if ($wbProdTipo.IsServer -ne ([int](Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)) { Write-Host "  [ERRO] detecção: registro e CIM discordam sobre ser servidor (registro '$($wbProdTipo.ProductType)')" -ForegroundColor Red; $wbErrors++ }
    # A simulação monta a aba, mas não pode liberar escrita no SMB/energia/TCP/RDP da máquina real.
    if ((Test-WinForgeRealServer) -ne $wbProdTipo.IsServer) { Write-Host "  [ERRO] detecção: Test-WinForgeRealServer não acompanha o ProductType real" -ForegroundColor Red; $wbErrors++ }
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
        # Perfil simulado: o cartão (e o relatório HTML que sai dele) tem de dizer de onde veio o
        # "servidor" - sem essa linha o relatório de um teste passa por relatório de máquina real.
        $wbSecSrvObj = @(Get-WinForgeDiagSections -Profile $wbSims['server-iis'] | Where-Object { [string]$_.Title -eq 'Servidor' })
        if ($wbSecSrvObj.Count -and 'Simulação' -notin @($wbSecSrvObj[0].Lines | ForEach-Object { [string]$_.Key })) { Write-Host "  [ERRO] Diagnóstico (server-iis): o cartão Servidor de um perfil simulado deveria trazer a linha 'Simulação'" -ForegroundColor Red; $wbErrors++ }
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
        $wbIisFile = New-WinForgeSnapshot -Name 'AlwaysRunning' -Values @{ 'pool:A:startMode' = 'OnDemand'; 'pool:A:autoStart' = 'False' } -Root $wbIisRoot
        if (-not $wbIisFile -or -not (Test-Path $wbIisFile)) { Write-Host "  [ERRO] IIS: New-WinForgeSnapshot não gravou arquivo ('$wbIisFile')" -ForegroundColor Red; $wbErrors++ }
        # A pasta nasce protegida: sem herança e sem ninguém de fora de SYSTEM/Administradores (ou da
        # identidade atual, quando o teste roda sem elevação) com permissão de escrita. É essa
        # proteção que impede um usuário comum de plantar um JSON que o Desfazer aplicaria elevado.
        $wbIisAcl = Get-Acl -LiteralPath $wbIisRoot
        if (-not $wbIisAcl.AreAccessRulesProtected) { Write-Host "  [ERRO] IIS: a pasta de backup nasceu herdando permissões" -ForegroundColor Red; $wbErrors++ }
        # -ExplicitRoot porque esta pasta é a do teste, em %TEMP%: sem elevação ela nasce com a
        # identidade atual como dona, e é justamente isso que a pasta PADRÃO recusa (ver o bloco de
        # segurança mais abaixo, que cobra a recusa na mesma pasta sem esta chave).
        $wbIisTrust = Test-WinForgeSnapshotRootTrusted -Root $wbIisRoot -ExplicitRoot
        if (-not $wbIisTrust.Trusted) { Write-Host "  [ERRO] IIS: a pasta recém-criada não passou na checagem de confiança ('$($wbIisTrust.Reason)')" -ForegroundColor Red; $wbErrors++ }
        # Pasta com escrita para 'Todos' (Everyone, S-1-1-0) é o cenário do ataque: tem de ser recusada.
        $wbIisRootMau = Join-Path $env:TEMP 'WinForge-SelfTest\iis-backup-aberto'
        New-Item -ItemType Directory -Path $wbIisRootMau -Force | Out-Null
        $wbIisAclMau = Get-Acl -LiteralPath $wbIisRootMau
        $wbIisAclMau.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        Set-Acl -LiteralPath $wbIisRootMau -AclObject $wbIisAclMau
        $wbIisTrustMau = Test-WinForgeSnapshotRootTrusted -Root $wbIisRootMau
        if ($wbIisTrustMau.Trusted) { Write-Host "  [ERRO] IIS: pasta com escrita para 'Todos' foi considerada confiável" -ForegroundColor Red; $wbErrors++ }
        New-WinForgeSnapshot -Name 'AlwaysRunning' -Values @{ 'pool:A:startMode' = 'OnDemand' } -Root $wbIisRootMau | Out-Null
        $wbIisBloq = Get-WinForgeSnapshot -Name 'AlwaysRunning' -Root $wbIisRootMau -AllowedKey (Get-WinForgeIisAllowedKey -Name AlwaysRunning)
        if ($null -eq $wbIisBloq -or -not $wbIisBloq.Blocked) { Write-Host "  [ERRO] IIS: backup em pasta não confiável deveria ser recusado" -ForegroundColor Red; $wbErrors++ }
        # Segundo backup no MESMO segundo, de propósito: o nome carrega milissegundo, então os dois
        # arquivos coexistem e o primeiro - o dos valores originais - continua no disco. Com precisão
        # de segundo, este é o cenário que apagava o backup bom (aplicar duas vezes seguidas).
        Start-Sleep -Milliseconds 20
        # O segundo backup traz a MESMA chave com outro valor (o pool já ajustado por uma primeira
        # aplicação) e uma chave nova (um pool criado depois). Juntando os dois, 'startMode' tem de
        # voltar como 'OnDemand' - o valor de antes do WinForge - e não como 'AlwaysRunning'.
        $wbIisFile2 = New-WinForgeSnapshot -Name 'AlwaysRunning' -Values @{ 'pool:A:startMode' = 'AlwaysRunning'; 'pool:D:startMode' = 'OnDemand' } -Root $wbIisRoot
        if ($wbIisFile2 -eq $wbIisFile) { Write-Host "  [ERRO] IIS: o segundo backup do mesmo segundo caiu no mesmo arquivo ($wbIisFile2)" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-Path -LiteralPath $wbIisFile)) { Write-Host "  [ERRO] IIS: o primeiro backup desapareceu depois do segundo ($wbIisFile)" -ForegroundColor Red; $wbErrors++ }
        if (@(Get-ChildItem -LiteralPath $wbIisRoot -Filter 'AlwaysRunning-*.json').Count -ne 2) { Write-Host "  [ERRO] IIS: esperado 2 arquivos de backup, veio $(@(Get-ChildItem -LiteralPath $wbIisRoot -Filter 'AlwaysRunning-*.json').Count)" -ForegroundColor Red; $wbErrors++ }
        $wbIisMerge = Get-WinForgeSnapshot -Name 'AlwaysRunning' -Root $wbIisRoot -AllowedKey (Get-WinForgeIisAllowedKey -Name AlwaysRunning)
        if ($null -eq $wbIisMerge) { Write-Host "  [ERRO] IIS: Get-WinForgeSnapshot não achou os backups gravados" -ForegroundColor Red; $wbErrors++ }
        else {
            if ($wbIisMerge.Values['pool:A:startMode'] -ne 'OnDemand') { Write-Host "  [ERRO] IIS: na junção dos backups o MAIS ANTIGO deveria vencer em 'pool:A:startMode' (veio '$($wbIisMerge.Values['pool:A:startMode'])', esperado 'OnDemand')" -ForegroundColor Red; $wbErrors++ }
            if ($wbIisMerge.Values['pool:A:autoStart'] -ne 'False') { Write-Host "  [ERRO] IIS: chave só do backup antigo perdida na junção ('pool:A:autoStart' veio '$($wbIisMerge.Values['pool:A:autoStart'])')" -ForegroundColor Red; $wbErrors++ }
            if ($wbIisMerge.Values['pool:D:startMode'] -ne 'OnDemand') { Write-Host "  [ERRO] IIS: chave só do backup novo perdida na junção ('pool:D:startMode' veio '$($wbIisMerge.Values['pool:D:startMode'])')" -ForegroundColor Red; $wbErrors++ }
            if (@($wbIisMerge.Paths).Count -ne 2) { Write-Host "  [ERRO] IIS: a junção deveria consumir os 2 arquivos, veio $(@($wbIisMerge.Paths).Count)" -ForegroundColor Red; $wbErrors++ }
        }
        # Chave que o item NÃO escreve (uma seção qualquer do applicationHost.config) e valor que não
        # é texto: os dois entram no arquivo e os dois têm de ficar de fora da restauração.
        $wbIisFile3 = New-WinForgeSnapshot -Name 'AlwaysRunning' -Values @{ 'server:system.webServer/security/authentication/anonymousAuthentication:enabled' = 'True'; 'pool:Z:queueLength' = '1000'; 'pool:Y:startMode' = @('nao', 'texto') } -Root $wbIisRoot
        $wbIisFiltrado = Get-WinForgeSnapshot -Name 'AlwaysRunning' -Root $wbIisRoot -AllowedKey (Get-WinForgeIisAllowedKey -Name AlwaysRunning)
        foreach ($wbIisMa in @('server:system.webServer/security/authentication/anonymousAuthentication:enabled', 'pool:Z:queueLength', 'pool:Y:startMode')) {
            if ($wbIisFiltrado.Values.ContainsKey($wbIisMa)) { Write-Host "  [ERRO] IIS: chave '$wbIisMa' deveria ter sido recusada no Desfazer de AlwaysRunning" -ForegroundColor Red; $wbErrors++ }
        }
        # Arquivo consumido vira '.restored.json' e some das juntadas seguintes: sem isso, uma nova
        # aplicação depois do Desfazer voltaria ao estado de duas aplicações atrás.
        Complete-WinForgeSnapshot -Paths $wbIisFiltrado.Paths | Out-Null
        if (@(Get-ChildItem -LiteralPath $wbIisRoot -Filter '*.restored.json').Count -ne 3) { Write-Host "  [ERRO] IIS: esperado 3 backups arquivados como .restored.json, veio $(@(Get-ChildItem -LiteralPath $wbIisRoot -Filter '*.restored.json').Count)" -ForegroundColor Red; $wbErrors++ }
        if ($null -ne (Get-WinForgeSnapshot -Name 'AlwaysRunning' -Root $wbIisRoot -AllowedKey (Get-WinForgeIisAllowedKey -Name AlwaysRunning))) { Write-Host "  [ERRO] IIS: backup arquivado ainda foi lido pela junção seguinte" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  IIS: backup em $(Split-Path -Leaf $wbIisFile2) | pasta protegida, o mais ANTIGO vence na junção, chave estranha recusada, consumido vira .restored.json"
    } catch {
        Write-Host "  [ERRO] IIS (backup): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path (Split-Path -Parent $wbIisRoot) -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- backup: forma do valor, dono da pasta, crivo inteiro
    # Segunda rodada de revisão de segurança. Os três buracos fechados aqui tinham o mesmo fim -
    # escrita elevada a partir de um arquivo que outra conta plantou:
    #   1. o valor do backup virava TEXTO DE COMANDO ('powercfg /setactive <valor do JSON>'), então
    #      'x; algo' era compilado e executado como PowerShell no Desfazer;
    #   2. o crivo de 'server:' aceitava a forma curta ('server:<atributo>'), e com ela QUALQUER
    #      seção do applicationHost.config passava pelo Desfazer de um item que só mexe em uma;
    #   3. a pasta padrão aceitava a conta atual como DONA, e dono guarda WRITE_DAC - um processo de
    #      integridade média da mesma conta de administrador criava a pasta antes da primeira
    #      execução, escrevia uma DACL de aparência correta e passava em todas as checagens.
    foreach ($wbSecCaso in @(
        @('ActiveSchemeGuid', 'x; echo pwned', $false),
        @('ActiveSchemeGuid', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', $true),
        @('ActiveSchemeGuid', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; calc', $false),
        @('AutoTuningLevelLocal', 'Normal', $true),
        @('AutoTuningLevelLocal', 'Normal; calc', $false),
        @('EnableSMB1Protocol', 'False', $true),
        @('EnableSMB1Protocol', 'False; calc', $false),
        @('MaxIdleTime', '1800000', $true),
        @('MaxIdleTime', '<RemoveEntry>', $true),
        @('MaxIdleTime', '0; rm -rf', $false),
        @('pool:A:startMode', 'OnDemand', $true),
        @('pool:A:startMode', 'OnDemand & calc', $false),
        @('pool:A:processModel.idleTimeout', '00:20:00', $true),
        @('pool:A:processModel.idleTimeout', '30.00:00:00', $true),
        @('pool:A:processModel.idleTimeout', '00:20:00; calc', $false),
        @('pool:A:queueLength', '5000', $true),
        @('pool:A:queueLength', '5000; calc', $false),
        @('server:system.webServer/caching:enabled', 'True', $true),
        @('server:system.webServer/caching:enabled', 'True; calc', $false),
        @('pool:A:propriedadeQueNinguemEscreve', 'x', $false)
    )) {
        $wbSecVeio = [bool](Test-WinForgeSnapshotValue -Key $wbSecCaso[0] -Value $wbSecCaso[1])
        if ($wbSecVeio -ne [bool]$wbSecCaso[2]) { Write-Host "  [ERRO] Backup (forma do valor): '$($wbSecCaso[0])' = '$($wbSecCaso[1])' deveria dar $($wbSecCaso[2]), veio $wbSecVeio" -ForegroundColor Red; $wbErrors++ }
    }
    # A recusa mora TAMBÉM no ponto de escrita: nada chega ao powercfg nem ao IIS com valor plantado.
    foreach ($wbSecEscrita in @(
        @('Servidor', { Set-WinForgeServerSettingValue -Key 'ActiveSchemeGuid' -Value 'x; echo pwned' }),
        @('Servidor', { Set-WinForgeServerSettingValue -Key 'AutoTuningLevelLocal' -Value 'Normal; calc' }),
        @('IIS', { Set-WinForgeIisValue -Key 'pool:A:startMode' -Value 'OnDemand; calc' })
    )) {
        $wbSecMsg = ''
        try { & $wbSecEscrita[1] } catch { $wbSecMsg = [string]$_.Exception.Message }
        if ($wbSecMsg -notmatch 'forma esperada') { Write-Host "  [ERRO] Backup ($($wbSecEscrita[0])): a escrita com valor plantado deveria ser recusada pela forma ('$wbSecMsg')" -ForegroundColor Red; $wbErrors++ }
    }
    # O crivo de 'server:' agora cobra a chave INTEIRA: seção e atributo.
    $wbSecOc = Get-WinForgeIisAllowedKey -Name OutputCache
    if (Test-WinForgeSnapshotKey -Key 'server:system.webServer/directoryBrowse:enabled' -AllowedKey $wbSecOc) { Write-Host "  [ERRO] Backup (crivo): OutputCache aceitou 'server:system.webServer/directoryBrowse:enabled' (forma curta)" -ForegroundColor Red; $wbErrors++ }
    if (-not (Test-WinForgeSnapshotKey -Key 'server:system.webServer/caching:enabled' -AllowedKey $wbSecOc)) { Write-Host "  [ERRO] Backup (crivo): OutputCache recusou a própria chave 'server:system.webServer/caching:enabled'" -ForegroundColor Red; $wbErrors++ }
    $wbSecRoot = Join-Path $env:TEMP 'WinForge-SelfTest\seguranca'
    try {
        if (Test-Path $wbSecRoot) { Remove-Item -Path $wbSecRoot -Recurse -Force -ErrorAction SilentlyContinue }
        # Backup plantado com um GUID que não é GUID: a chave sai da leitura (vai para Ignored) e o
        # backup BOM gravado depois continua respondendo por ela - a tranca não pode comer o bom.
        New-WinForgeSnapshot -Name 'setting-HighPerf' -Values @{ 'ActiveSchemeGuid' = 'x; echo pwned' } -Root $wbSecRoot | Out-Null
        Start-Sleep -Milliseconds 20
        New-WinForgeSnapshot -Name 'setting-HighPerf' -Values @{ 'ActiveSchemeGuid' = '381b4222-f694-41f0-9685-ff5bb260df2e' } -Root $wbSecRoot | Out-Null
        $wbSecLido = Get-WinForgeSnapshot -Name 'setting-HighPerf' -Root $wbSecRoot -AllowedKey @{ 'ActiveSchemeGuid' = $true }
        if ($null -eq $wbSecLido) { Write-Host "  [ERRO] Backup (valor plantado): Get-WinForgeSnapshot não leu nada" -ForegroundColor Red; $wbErrors++ }
        else {
            if (@($wbSecLido.Ignored) -notcontains 'ActiveSchemeGuid') { Write-Host "  [ERRO] Backup (valor plantado): 'ActiveSchemeGuid' inválido não entrou na lista de recusados" -ForegroundColor Red; $wbErrors++ }
            if ($wbSecLido.Values['ActiveSchemeGuid'] -ne '381b4222-f694-41f0-9685-ff5bb260df2e') { Write-Host "  [ERRO] Backup (valor plantado): esperado o GUID válido do segundo backup, veio '$($wbSecLido.Values['ActiveSchemeGuid'])'" -ForegroundColor Red; $wbErrors++ }
        }
        # Desfazer que falhou não arquiva: o arquivo é a única cópia do valor anterior da chave.
        $wbSecArq = New-WinForgeSnapshot -Name 'setting-RdpNla' -Values @{ 'MaxIdleTime' = '1800000' } -Root $wbSecRoot
        if ((Complete-WinForgeSnapshot -Paths @($wbSecArq) -FailedKey @('MaxIdleTime')) -ne 0) { Write-Host "  [ERRO] Backup (arquivamento): com chave que falhou, nada podia ser arquivado" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-Path -LiteralPath $wbSecArq)) { Write-Host "  [ERRO] Backup (arquivamento): o arquivo sumiu mesmo com uma chave que falhou" -ForegroundColor Red; $wbErrors++ }
        if ((Complete-WinForgeSnapshot -Paths @($wbSecArq)) -ne 1) { Write-Host "  [ERRO] Backup (arquivamento): sem falha, o arquivo deveria ser arquivado" -ForegroundColor Red; $wbErrors++ }
        # Dono da pasta: a MESMA pasta passa com -Root explícito (o caminho do teste) e é recusada
        # pelas regras da pasta padrão. É a prova de que %ProgramData%\WinForge\iis-backup recusa
        # pasta de usuário - sem escrever nada em %ProgramData%.
        $wbSecEu = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $wbSecSystem = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::LocalSystemSid), $null
        $wbSecAdmin = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid), $null
        if ($wbSecEu.Value -eq $wbSecSystem.Value -or $wbSecEu.Value -eq $wbSecAdmin.Value) {
            Write-Host "  Backup (dono): teste pulado - este build roda como SYSTEM ou como o próprio grupo Administradores"
        } else {
            $wbSecDono = Join-Path $wbSecRoot 'dono-usuario'
            New-Item -ItemType Directory -Path $wbSecDono -Force | Out-Null
            $wbSecAcl = New-Object System.Security.AccessControl.DirectorySecurity
            $wbSecAcl.SetAccessRuleProtection($true, $false)
            foreach ($wbSecSid in @($wbSecSystem, $wbSecAdmin, $wbSecEu)) {
                $wbSecAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $wbSecSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            }
            $wbSecAcl.SetOwner($wbSecEu)
            Set-Acl -LiteralPath $wbSecDono -AclObject $wbSecAcl
            $wbSecComRoot = Test-WinForgeSnapshotRootTrusted -Root $wbSecDono -ExplicitRoot
            if (-not $wbSecComRoot.Trusted) { Write-Host "  [ERRO] Backup (dono): pasta de teste com -Root explícito deveria passar ('$($wbSecComRoot.Reason)')" -ForegroundColor Red; $wbErrors++ }
            $wbSecPadrao = Test-WinForgeSnapshotRootTrusted -Root $wbSecDono
            if ($wbSecPadrao.Trusted) { Write-Host "  [ERRO] Backup (dono): pasta com dono fora de SYSTEM/Administradores passou nas regras da pasta PADRÃO" -ForegroundColor Red; $wbErrors++ }
            elseif ($wbSecPadrao.Reason -notmatch 'SYSTEM') { Write-Host "  [ERRO] Backup (dono): o motivo da recusa não fala do dono ('$($wbSecPadrao.Reason)')" -ForegroundColor Red; $wbErrors++ }
        }
        # Aplicar numa pasta que qualquer um escreve: recusa antes de tudo, sem arquivo e sem
        # alteração. -CaptureOnly porque é o único caminho de aplicação que roda num cliente, e ele
        # só LÊ o registro do RDP.
        $wbSecAberto = Join-Path $wbSecRoot 'aberta'
        New-Item -ItemType Directory -Path $wbSecAberto -Force | Out-Null
        $wbSecAclA = Get-Acl -LiteralPath $wbSecAberto
        $wbSecAclA.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        Set-Acl -LiteralPath $wbSecAberto -AclObject $wbSecAclA
        $wbSecCap = Invoke-WinForgeServerSetting -Name 'RdpNla' -CaptureOnly -Root $wbSecAberto
        if ($wbSecCap.Changed -ne 0) { Write-Host "  [ERRO] Backup (pasta aberta): a captura alterou $($wbSecCap.Changed) valor(es)" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wbSecCap.Skipped -notmatch 'não confiável') { Write-Host "  [ERRO] Backup (pasta aberta): o motivo não diz que a pasta não é confiável ('$($wbSecCap.Skipped)')" -ForegroundColor Red; $wbErrors++ }
        if ($null -ne $wbSecCap.Snapshot) { Write-Host "  [ERRO] Backup (pasta aberta): gravou backup numa pasta não confiável ('$($wbSecCap.Snapshot)')" -ForegroundColor Red; $wbErrors++ }
        if (@(Get-ChildItem -LiteralPath $wbSecAberto -Filter '*.json' -ErrorAction SilentlyContinue).Count -ne 0) { Write-Host "  [ERRO] Backup (pasta aberta): sobrou arquivo JSON na pasta não confiável" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Backup (segurança): forma do valor cobrada na leitura e na escrita, crivo 'server:' inteiro, pasta padrão só de SYSTEM/Administradores, aplicação recusada em pasta aberta"
    } catch {
        Write-Host "  [ERRO] Backup (segurança): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path $wbSecRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- backup: dono do ARQUIVO e cadeia de pastas
    # Terceira rodada de revisão de segurança, e os dois furos são da mesma família do anterior:
    #   1. a checagem do ARQUIVO aceitava a identidade atual como dona SEMPRE (o -ExplicitRoot estava
    #      fixo no código). Na pasta PADRÃO isso devolvia o WRITE_DAC implícito do dono a um processo
    #      de integridade média da mesma conta de administrador: ele reescrevia a DACL do arquivo pelo
    #      caminho completo e plantava valores que o Desfazer elevado aplicaria. Agora quem decide é
    #      quem chamou, e na pasta padrão o dono tem de ser SYSTEM ou Administradores.
    #   2. o ponto de reanálise era conferido só na ÚLTIMA pasta. Uma junção em %ProgramData%\WinForge
    #      fazia a pasta de backup nascer fora de %ProgramData%, com a DACL de onde a junção aponta.
    #      Agora o caminho é normalizado uma vez e TODA a cadeia de ancestrais é conferida.
    $wb3Base = Join-Path $env:TEMP 'WinForge-SelfTest\rodada3'
    $wb3Root = Join-Path $wb3Base 'backup'
    try {
        if (Test-Path $wb3Base) { Remove-Item -Path $wb3Base -Recurse -Force -ErrorAction SilentlyContinue }
        # Com -Root próprio (o teste roda sem elevação) o backup continua saindo e continua sendo lido:
        # endurecer dono/DACL é obrigação da pasta PADRÃO, não uma trava que quebra o -SelfTest.
        $wb3Arq = New-WinForgeSnapshot -Name 'setting-RdpNla' -Values @{ 'MaxIdleTime' = '1800000' } -Root $wb3Root
        if (-not $wb3Arq -or -not (Test-Path -LiteralPath $wb3Arq)) { Write-Host "  [ERRO] Backup (rodada 3): New-WinForgeSnapshot não gravou arquivo com -Root próprio ('$wb3Arq')" -ForegroundColor Red; $wbErrors++ }
        else {
            $wb3Lido = Get-WinForgeSnapshot -Name 'setting-RdpNla' -Root $wb3Root -AllowedKey @{ 'MaxIdleTime' = $true }
            if ($null -eq $wb3Lido -or $wb3Lido.Values['MaxIdleTime'] -ne '1800000') { Write-Host "  [ERRO] Backup (rodada 3): o backup gravado não voltou na leitura ('$($wb3Lido.Values['MaxIdleTime'])')" -ForegroundColor Red; $wbErrors++ }
            # Dono do arquivo: o MESMO arquivo passa com -ExplicitRoot (é o do teste, em %TEMP%) e é
            # recusado pelas regras da pasta padrão. Só faz sentido cobrar quando o dono é mesmo a
            # conta atual - num build elevado o próprio New-WinForgeSnapshot já o entrega a
            # Administradores, e aí as duas checagens passam.
            $wb3Dono = (Get-Acl -LiteralPath $wb3Arq).GetOwner([System.Security.Principal.SecurityIdentifier])
            $wb3System = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::LocalSystemSid), $null
            $wb3Admin = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid), $null
            $wb3Exp = Test-WinForgeSnapshotFileTrusted -Path $wb3Arq -ExplicitRoot
            if (-not $wb3Exp.Trusted) { Write-Host "  [ERRO] Backup (rodada 3): o arquivo do teste deveria passar com -ExplicitRoot ('$($wb3Exp.Reason)')" -ForegroundColor Red; $wbErrors++ }
            $wb3Pad = Test-WinForgeSnapshotFileTrusted -Path $wb3Arq
            if ($wb3Dono.Value -eq $wb3System.Value -or $wb3Dono.Value -eq $wb3Admin.Value) {
                if (-not $wb3Pad.Trusted) { Write-Host "  [ERRO] Backup (rodada 3): arquivo de SYSTEM/Administradores foi recusado nas regras da pasta PADRÃO ('$($wb3Pad.Reason)')" -ForegroundColor Red; $wbErrors++ }
            } else {
                if ($wb3Pad.Trusted) { Write-Host "  [ERRO] Backup (rodada 3): arquivo com dono fora de SYSTEM/Administradores passou nas regras da pasta PADRÃO" -ForegroundColor Red; $wbErrors++ }
                elseif ($wb3Pad.Reason -notmatch 'SYSTEM') { Write-Host "  [ERRO] Backup (rodada 3): o motivo da recusa do arquivo não fala do dono ('$($wb3Pad.Reason)')" -ForegroundColor Red; $wbErrors++ }
            }
        }
        # Junção NO MEIO do caminho (não na última pasta): a raiz tem de ser recusada mesmo com
        # -ExplicitRoot, porque o caminho conferido não seria o caminho escrito.
        $wb3Alvo = Join-Path $wb3Base 'real'
        New-Item -ItemType Directory -Path $wb3Alvo -Force | Out-Null
        $wb3Junc = Join-Path $wb3Base 'junc'
        New-Item -ItemType Junction -Path $wb3Junc -Target $wb3Alvo -ErrorAction Stop | Out-Null
        $wb3Cadeia = Test-WinForgeSnapshotRootTrusted -Root (Join-Path $wb3Junc 'backup') -ExplicitRoot
        if ($wb3Cadeia.Trusted) { Write-Host "  [ERRO] Backup (rodada 3): raiz com junção na cadeia de pastas foi considerada confiável" -ForegroundColor Red; $wbErrors++ }
        elseif ($wb3Cadeia.Reason -notmatch 'reanálise') { Write-Host "  [ERRO] Backup (rodada 3): o motivo da recusa não fala do ponto de reanálise ('$($wb3Cadeia.Reason)')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Backup (rodada 3): backup com -Root próprio grava e lê, dono do arquivo cobrado pela pasta de quem chamou, junção na cadeia de pastas recusada"
    } catch {
        Write-Host "  [ERRO] Backup (rodada 3): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path $wb3Base -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- backup: OWNER RIGHTS na pasta que já existe e DACL do arquivo
    # Quarta rodada. Os dois furos são o resto da anterior:
    #   1. a ACE herdável de OWNER RIGHTS (S-1-3-4, só leitura) só era escrita na CRIAÇÃO da pasta.
    #      Numa pasta que já existia sem ela, o dono do backup recém-gravado guardava o WRITE_DAC
    #      implícito entre a gravação e o Protect - a janela que a ACE existe para fechar.
    #   2. a checagem do ARQUIVO olhava só o dono: um backup com ACE de escrita para 'Todos' passava
    #      mesmo com o dono certo.
    $wb4Base = Join-Path $env:TEMP 'WinForge-SelfTest\rodada4'
    try {
        if (Test-Path $wb4Base) { Remove-Item -Path $wb4Base -Recurse -Force -ErrorAction SilentlyContinue }
        $wb4Root = Join-Path $wb4Base 'backup'
        New-Item -ItemType Directory -Path $wb4Root -Force | Out-Null
        $wb4Eu = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $wb4System = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::LocalSystemSid), $null
        $wb4Admin = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid), $null
        # Pasta LEGADA: protegida e com os donos certos, mas sem a ACE de OWNER RIGHTS.
        $wb4Acl = New-Object System.Security.AccessControl.DirectorySecurity
        $wb4Acl.SetAccessRuleProtection($true, $false)
        foreach ($wb4Sid in @($wb4System, $wb4Admin, $wb4Eu)) {
            $wb4Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $wb4Sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        }
        Set-Acl -LiteralPath $wb4Root -AclObject $wb4Acl
        $wb4TemOwner = {
            param($caminho)
            $rx = [int][System.Security.AccessControl.FileSystemRights]::ReadAndExecute
            foreach ($ace in (Get-Acl -LiteralPath $caminho).Access) {
                if ($ace.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
                $sid = $ace.IdentityReference
                try { if ($sid -isnot [System.Security.Principal.SecurityIdentifier]) { $sid = $sid.Translate([System.Security.Principal.SecurityIdentifier]) } } catch { continue }
                if ($sid.Value -eq 'S-1-3-4' -and ([int]$ace.FileSystemRights -band $rx) -eq $rx) { return $true }
            }
            return $false
        }
        if (& $wb4TemOwner $wb4Root) { Write-Host "  [ERRO] Backup (rodada 4): a pasta de teste já nasceu com a ACE de OWNER RIGHTS - o teste não prova nada" -ForegroundColor Red; $wbErrors++ }
        $wb4Conf = Confirm-WinForgeSnapshotRoot -Root $wb4Root
        if (-not $wb4Conf.Ok) { Write-Host "  [ERRO] Backup (rodada 4): a pasta legada deveria ser aceita depois do conserto ('$($wb4Conf.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if (-not (& $wb4TemOwner $wb4Root)) { Write-Host "  [ERRO] Backup (rodada 4): Confirm-WinForgeSnapshotRoot não acrescentou a ACE de OWNER RIGHTS (S-1-3-4) na pasta que já existia" -ForegroundColor Red; $wbErrors++ }
        # Arquivo de backup bom passa; o MESMO arquivo com uma ACE de escrita para 'Todos' é recusado
        # - dono certo não salva DACL aberta.
        $wb4Arq = New-WinForgeSnapshot -Name 'setting-RdpNla' -Values @{ 'MaxIdleTime' = '1800000' } -Root $wb4Root
        if (-not $wb4Arq -or -not (Test-Path -LiteralPath $wb4Arq)) { Write-Host "  [ERRO] Backup (rodada 4): New-WinForgeSnapshot não gravou arquivo ('$wb4Arq')" -ForegroundColor Red; $wbErrors++ }
        else {
            $wb4Bom = Test-WinForgeSnapshotFileTrusted -Path $wb4Arq -ExplicitRoot
            if (-not $wb4Bom.Trusted) { Write-Host "  [ERRO] Backup (rodada 4): o arquivo recém-gravado deveria passar com -ExplicitRoot ('$($wb4Bom.Reason)')" -ForegroundColor Red; $wbErrors++ }
            $wb4Info = New-Object System.IO.FileInfo $wb4Arq
            $wb4AclArq = $wb4Info.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
            $wb4AclArq.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'Write', 'None', 'None', 'Allow'))
            $wb4Info.SetAccessControl($wb4AclArq)
            $wb4Mau = Test-WinForgeSnapshotFileTrusted -Path $wb4Arq -ExplicitRoot
            if ($wb4Mau.Trusted) { Write-Host "  [ERRO] Backup (rodada 4): arquivo com escrita para 'Todos' foi considerado confiável" -ForegroundColor Red; $wbErrors++ }
            elseif ($wb4Mau.Reason -notmatch 'escrita') { Write-Host "  [ERRO] Backup (rodada 4): o motivo da recusa do arquivo não fala da permissão de escrita ('$($wb4Mau.Reason)')" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Backup (rodada 4): pasta que já existia recebe a ACE de OWNER RIGHTS, arquivo com DACL aberta recusado"
    } catch {
        Write-Host "  [ERRO] Backup (rodada 4): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path $wb4Base -Recurse -Force -ErrorAction SilentlyContinue
    }
    # O crivo do Desfazer tem de dizer o mesmo que o plano do item. Só dá para cobrar isso nos dois
    # itens de nível de servidor: o plano dos itens de pool/site precisa do provedor IIS:\ para
    # listar os alvos, e numa máquina sem IIS ele vem vazio.
    foreach ($wbIisPar in @(@('OutputCache', 'server:system.webServer/caching'), @('Compression', 'server:system.webServer/urlCompression'))) {
        try {
            $wbIisPermitido = Get-WinForgeIisAllowedKey -Name $wbIisPar[0]
            foreach ($wbIisAlvo in @((Get-WinForgeIisTweakPlan -Name $wbIisPar[0]).Targets.Keys)) {
                if (-not (Test-WinForgeSnapshotKey -Key $wbIisAlvo -AllowedKey $wbIisPermitido)) { Write-Host "  [ERRO] IIS: '$wbIisAlvo' está no plano de $($wbIisPar[0]) mas o crivo do Desfazer recusa" -ForegroundColor Red; $wbErrors++ }
            }
            if (Test-WinForgeSnapshotKey -Key "$($wbIisPar[1]):outraCoisa" -AllowedKey $wbIisPermitido) { Write-Host "  [ERRO] IIS: o crivo de $($wbIisPar[0]) aceitou um atributo que o item não escreve" -ForegroundColor Red; $wbErrors++ }
        } catch {
            Write-Host "  [ERRO] IIS (crivo de $($wbIisPar[0])): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
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
    # ---------------------------------------------------------------- ajustes de servidor com captura
    # Estes itens não moram no registro (SMB, energia, TCP, RDP): o Desfazer deles só é honesto porque
    # o estado anterior vai para um backup antes da mudança. Nada aqui pode ALTERAR a máquina do
    # build - é um cliente, e mexer no SMB ou no plano de energia de quem compila seria estrago. As
    # duas coisas cobradas são exatamente essas: numa máquina que não é servidor, aplicar recusa
    # limpo; e a captura (-CaptureOnly, que nunca escreve) traz valor de verdade onde o cmdlet existe.
    $wbSrvRoot = Join-Path $env:TEMP 'WinForge-SelfTest\server-backup'
    try {
        if (Test-Path $wbSrvRoot) { Remove-Item -Path $wbSrvRoot -Recurse -Force -ErrorAction SilentlyContinue }
        $wbSrvItens = @(
            @('Smb1Off', 'Get-SmbServerConfiguration', 'EnableSMB1Protocol'),
            @('SmbSigning', 'Get-SmbServerConfiguration', 'RequireSecuritySignature'),
            @('HighPerf', (Get-WinForgeSystemExe -Name 'powercfg.exe'), 'ActiveSchemeGuid'),
            @('TcpAutotuning', 'Get-NetTCPSetting', 'AutoTuningLevelLocal'),
            @('RdpNla', $null, 'UserAuthentication')
        )
        $wbSrvCapturados = 0
        foreach ($wbSrvItem in $wbSrvItens) {
            # Aplicar num cliente: sem exceção, sem alteração e com um motivo que diga por quê.
            # Num Windows Server de verdade (o runner do CI é um) o apply mudaria SMB/RDP da máquina:
            # ali este passo não roda - só a recusa em cliente, o Desfazer sem backup e a captura.
            if (-not (Test-WinForgeRealServer)) {
                $wbSrvApl = Invoke-WinForgeServerSetting -Name $wbSrvItem[0] -Root $wbSrvRoot
                if ($null -eq $wbSrvApl) { Write-Host "  [ERRO] Servidor (ajuste): '$($wbSrvItem[0])' não devolveu resultado" -ForegroundColor Red; $wbErrors++; continue }
                if ($wbSrvApl.Changed -ne 0) { Write-Host "  [ERRO] Servidor (ajuste): '$($wbSrvItem[0])' alterou $($wbSrvApl.Changed) valor(es) num cliente" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wbSrvApl.Skipped -notmatch 'Windows Server') { Write-Host "  [ERRO] Servidor (ajuste): '$($wbSrvItem[0])' num cliente deveria dizer que só vale no Windows Server ('$($wbSrvApl.Skipped)')" -ForegroundColor Red; $wbErrors++ }
                if ($null -ne $wbSrvApl.Snapshot) { Write-Host "  [ERRO] Servidor (ajuste): '$($wbSrvItem[0])' gravou backup num cliente ('$($wbSrvApl.Snapshot)')" -ForegroundColor Red; $wbErrors++ }
            }
            # Desfazer sem backup: mensagem, nenhuma alteração e nenhuma exceção.
            $wbSrvUnd = Invoke-WinForgeServerSetting -Name $wbSrvItem[0] -Undo -Root $wbSrvRoot
            if ($wbSrvUnd.Changed -ne 0) { Write-Host "  [ERRO] Servidor (ajuste): Desfazer de '$($wbSrvItem[0])' sem backup alterou $($wbSrvUnd.Changed) valor(es)" -ForegroundColor Red; $wbErrors++ }
            # Captura: só onde a ferramenta existe nesta máquina. Nada é escrito no sistema.
            # A exigência pode ser um cmdlet (nome) ou um executável do sistema (caminho absoluto):
            # quem sabe responder pelos dois é Test-WinForgeCommandRequirement.
            if ($wbSrvItem[1] -and -not (Test-WinForgeCommandRequirement -Requires $wbSrvItem[1])) { continue }
            $wbSrvCap = Invoke-WinForgeServerSetting -Name $wbSrvItem[0] -CaptureOnly -Root $wbSrvRoot
            if ($wbSrvCap.Changed -ne 0) { Write-Host "  [ERRO] Servidor (captura): '$($wbSrvItem[0])' com -CaptureOnly alterou $($wbSrvCap.Changed) valor(es)" -ForegroundColor Red; $wbErrors++ }
            if (-not $wbSrvCap.Snapshot -or -not (Test-Path -LiteralPath $wbSrvCap.Snapshot)) { Write-Host "  [ERRO] Servidor (captura): '$($wbSrvItem[0])' não gravou backup ('$($wbSrvCap.Snapshot)')" -ForegroundColor Red; $wbErrors++; continue }
            $wbSrvPermitidas = @{}
            foreach ($wbSrvK in (Get-WinForgeServerSettingSpec -Name $wbSrvItem[0]).Keys) { $wbSrvPermitidas[$wbSrvK] = $true }
            $wbSrvLido = Get-WinForgeSnapshot -Name "setting-$($wbSrvItem[0])" -Root $wbSrvRoot -AllowedKey $wbSrvPermitidas
            if ($null -eq $wbSrvLido -or [string]::IsNullOrWhiteSpace([string]$wbSrvLido.Values[$wbSrvItem[2]])) { Write-Host "  [ERRO] Servidor (captura): '$($wbSrvItem[0])' não guardou '$($wbSrvItem[2])' (veio '$($wbSrvLido.Values[$wbSrvItem[2]])')" -ForegroundColor Red; $wbErrors++ }
            else { $wbSrvCapturados++ }
        }
        # O crivo é por item: o backup do SMB não pode reescrever o RDP.
        if (Test-WinForgeSnapshotKey -Key 'MaxIdleTime' -AllowedKey @{ 'EnableSMB1Protocol' = $true }) { Write-Host "  [ERRO] Servidor (captura): o crivo de Smb1Off aceitou uma chave do RDP" -ForegroundColor Red; $wbErrors++ }
        $wbSrvSpecErro = $false
        try { Get-WinForgeServerSettingSpec -Name 'NaoExiste' | Out-Null } catch { $wbSrvSpecErro = $true }
        if (-not $wbSrvSpecErro) { Write-Host "  [ERRO] Servidor (ajuste): Get-WinForgeServerSettingSpec aceitou um item desconhecido" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Servidor (ajustes com captura): $($wbSrvItens.Count) item(ns) recusados sem servidor, $wbSrvCapturados capturado(s) sem alterar nada"
    } catch {
        Write-Host "  [ERRO] Servidor (ajustes com captura): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path (Split-Path -Parent $wbSrvRoot) -Recurse -Force -ErrorAction SilentlyContinue
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
    if ((Get-WinForgeServerCommand -Name Dcdiag).Requires -ne (Get-WinForgeSystemExe -Name 'dcdiag.exe')) { Write-Host "  [ERRO] Servidor: Dcdiag deveria exigir '$(Get-WinForgeSystemExe -Name 'dcdiag.exe')', veio '$((Get-WinForgeServerCommand -Name Dcdiag).Requires)'" -ForegroundColor Red; $wbErrors++ }
    # 'Native' separa executável de pipeline de cmdlet: só o executável tem código de saída e só ele
    # passa pela troca de code page. Marcar um pipeline como nativo faria a janela imprimir um
    # "Código de saída: 0" que nunca existiu.
    foreach ($wbSrvNat in @(@('TimeCheck', $true), @('Dcdiag', $true), @('ReplSummary', $true), @('TcpShow', $false), @('DefenderExclusions', $false), @('DnsScavenging', $false), @('NtdsLocation', $false))) {
        $wbSrvNatCmd = Get-WinForgeServerCommand -Name $wbSrvNat[0]
        if ([bool]$wbSrvNatCmd.Native -ne [bool]$wbSrvNat[1]) { Write-Host "  [ERRO] Servidor: '$($wbSrvNat[0])' deveria ter Native = $($wbSrvNat[1])" -ForegroundColor Red; $wbErrors++ }
    }
    # netsh escreve UTF-8 quando a saída é um cano: nenhum comando da aba pode mais depender dele.
    foreach ($wbSrvNome in $wbSrvNomes) {
        if ([string](Get-WinForgeServerCommand -Name $wbSrvNome).Command -match '(?i)\bnetsh\b') { Write-Host "  [ERRO] Servidor: '$wbSrvNome' ainda chama o netsh" -ForegroundColor Red; $wbErrors++ }
    }
    # ErrorRecord vira texto antes do Out-String: sem isso, a linha que dcdiag manda para o fluxo de
    # erro chegaria formatada com o bloco '+ CategoryInfo / + FullyQualifiedErrorId' no meio da saída.
    $wbSrvErr = Invoke-WinForgeCommandText -Command 'Write-Error "falha de teste" 2>&1'
    if ([string]$wbSrvErr.Text -notmatch 'falha de teste') { Write-Host "  [ERRO] Servidor: a linha de erro não chegou ao texto ('$([string]$wbSrvErr.Text)')" -ForegroundColor Red; $wbErrors++ }
    if ([string]$wbSrvErr.Text -match 'CategoryInfo|FullyQualifiedErrorId') { Write-Host "  [ERRO] Servidor: o texto trouxe o bloco de ErrorRecord em vez da linha da ferramenta" -ForegroundColor Red; $wbErrors++ }
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
        if ([string]$wbSrvTcp.Text -match 'Código de saída') { Write-Host "  [ERRO] Servidor: TcpShow é pipeline de cmdlet e não pode trazer linha de código de saída" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wbSrvTcp.Text -notmatch '(?i)AutoTuningLevelLocal') { Write-Host "  [ERRO] Servidor: TcpShow deveria trazer AutoTuningLevelLocal na saída" -ForegroundColor Red; $wbErrors++ }
        if (-not $wbSrvTcp.Path -or -not (Test-Path -LiteralPath $wbSrvTcp.Path)) { Write-Host "  [ERRO] Servidor: TcpShow não gravou o arquivo ('$($wbSrvTcp.Path)')" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Servidor (comandos): TcpShow -> $(([string]$wbSrvTcp.Text).Length) caractere(s) em $(Split-Path -Leaf $wbSrvTcp.Path)" }
        # w32tm é executável: aí a linha do código de saída existe e é ela que separa "não achou
        # nada" de "falhou".
        $wbSrvHora = Invoke-WinForgeServerCommandCore -Name TimeCheck
        if ([string]$wbSrvHora.Text -notmatch 'Código de saída') { Write-Host "  [ERRO] Servidor: TimeCheck é executável e deveria trazer a linha de código de saída" -ForegroundColor Red; $wbErrors++ }
    } catch {
        Write-Host "  [ERRO] Servidor: Invoke-WinForgeServerCommandCore -Name TcpShow lançou '$($_.Exception.Message)'" -ForegroundColor Red; $wbErrors++
    }
    if (Test-Path -LiteralPath (Get-WinForgeSystemExe -Name 'dcdiag.exe') -PathType Leaf) {
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
    # -DryRun no núcleo genérico: devolve o texto do comando prefixado com '[simulação] ', não roda
    # nada e não grava arquivo nenhum - nem a checagem de ferramenta acontece. É o que deixa o
    # SelfTest exercitar QUALQUER linha de uma tabela de comandos, inclusive uma que repara o
    # sistema, sem tocar na máquina de quem compila. A contagem de arquivos antes/depois é a prova
    # de que a simulação não escreveu: um 'if' esquecido gravaria o arquivo do mesmo jeito.
    try {
        $wbCmdDir = Split-Path -Parent $sync.logPath
        $wbCmdAntes = @(Get-ChildItem -LiteralPath $wbCmdDir -Filter 'server-*.txt' -ErrorAction SilentlyContinue).Count
        $wbCmdSeco = Invoke-WinForgeCommandCore -Spec (Get-WinForgeServerCommand -Name TcpShow) -Name TcpShow -Component Server -Prefix server -DryRun
        # O segundo tiro usa um nome que não é de comando nenhum, e é ele que sustenta a contagem: o
        # nome do arquivo tem os segundos, então uma simulação que gravasse com o nome 'TcpShow'
        # sobrescreveria em silêncio o arquivo do TcpShow de verdade rodado logo acima, no mesmo
        # segundo, e a contagem não mudaria. Com um nome inédito, gravar é sempre um arquivo a mais.
        $wbCmdSecoUnico = Invoke-WinForgeCommandCore -Spec (Get-WinForgeServerCommand -Name TcpShow) -Name 'SimulacaoSelfTest' -Component Server -Prefix server -DryRun
        if ($null -ne $wbCmdSecoUnico.Path) { Write-Host "  [ERRO] Comandos: -DryRun não pode devolver caminho de arquivo (veio '$($wbCmdSecoUnico.Path)')" -ForegroundColor Red; $wbErrors++ }
        # StartsWith e não -like: em curinga do PowerShell '[...]' é classe de caracteres, e
        # "-like '[simulação]*'" casaria com qualquer texto começando por uma daquelas letras.
        if (-not ([string]$wbCmdSeco.Text).StartsWith('[simulação] ')) { Write-Host "  [ERRO] Comandos: -DryRun deveria devolver '[simulação] <comando>', veio '$([string]$wbCmdSeco.Text)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wbCmdSeco.Text -notmatch 'Get-NetTCPSetting') { Write-Host "  [ERRO] Comandos: -DryRun não trouxe o texto do comando" -ForegroundColor Red; $wbErrors++ }
        if ($null -ne $wbCmdSeco.Path) { Write-Host "  [ERRO] Comandos: -DryRun não pode devolver caminho de arquivo (veio '$($wbCmdSeco.Path)')" -ForegroundColor Red; $wbErrors++ }
        $wbCmdDepois = @(Get-ChildItem -LiteralPath $wbCmdDir -Filter 'server-*.txt' -ErrorAction SilentlyContinue).Count
        if ($wbCmdDepois -ne $wbCmdAntes) { Write-Host "  [ERRO] Comandos: -DryRun gravou arquivo na pasta de logs ($wbCmdAntes -> $wbCmdDepois)" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Comandos (simulação): TcpShow devolveu o texto do comando sem rodar nada e sem gravar arquivo" }
    } catch {
        Write-Host "  [ERRO] Comandos (simulação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # Reparo de componentes: a tabela INTEIRA passa pela simulação, inclusive as linhas que reparam e
    # instalam. É o único jeito de o SelfTest provar que cada linha tem título, comando que compila e
    # tipo válido sem tocar na máquina de quem compila - e a contagem de arquivos antes/depois é o
    # que sustenta o "não tocou": um -DryRun quebrado gravaria o arquivo do mesmo jeito.
    $wfRepNomes = @('SecurityStatus','SmartReport','DotNetStatus','ChkdskScan','WmiRepair','StoreReregister','ChkdskSchedule','MemoryDiag','DotNet35Enable','VcRedist','PowerShell7','DirectX')
    try {
        $wfRepDir = Split-Path -Parent $sync.logPath
        $wfRepAntes = @(Get-ChildItem -LiteralPath $wfRepDir -Filter 'repair-*.txt' -ErrorAction SilentlyContinue).Count
        $wfRepPorTipo = @{}
        foreach ($wfRepNome in $wfRepNomes) {
            $wfRepSpec = Get-WinForgeRepairCommand -Name $wfRepNome
            if ([string]::IsNullOrWhiteSpace($wfRepSpec.Title)) { Write-Host "  [ERRO] Reparo $wfRepNome`: sem título" -ForegroundColor Red; $wbErrors++ }
            if ([string]::IsNullOrWhiteSpace($wfRepSpec.Command)) { Write-Host "  [ERRO] Reparo $wfRepNome`: sem comando" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfRepSpec.Kind -notin @('read','repair','install')) { Write-Host "  [ERRO] Reparo $wfRepNome`: tipo inválido '$($wfRepSpec.Kind)'" -ForegroundColor Red; $wbErrors++ }
            if ($wfRepSpec.Native) { Write-Host "  [ERRO] Reparo $wfRepNome`: toda linha chama função do WinForge, Native tem de ser falso" -ForegroundColor Red; $wbErrors++ }
            # Ação que muda a máquina sem texto de confirmação seria uma pergunta em branco na etapa
            # seguinte do plano - a hora de pegar isso é agora, na tabela.
            if ([string]$wfRepSpec.Kind -ne 'read' -and [string]::IsNullOrWhiteSpace($wfRepSpec.Confirm)) { Write-Host "  [ERRO] Reparo $wfRepNome`: ação '$($wfRepSpec.Kind)' sem texto de confirmação" -ForegroundColor Red; $wbErrors++ }
            try { [scriptblock]::Create($wfRepSpec.Command) | Out-Null } catch { Write-Host "  [ERRO] Reparo $wfRepNome`: comando não compila: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++ }
            # O comando é o nome de uma função do próprio programa: se ela não existir, o botão só
            # falharia no clique de quem estivesse com o problema que ele conserta.
            $wfRepFuncao = ([string]$wfRepSpec.Command -split '\s+')[0]
            if (-not (Get-Command $wfRepFuncao -ErrorAction SilentlyContinue)) { Write-Host "  [ERRO] Reparo $wfRepNome`: função '$wfRepFuncao' não existe" -ForegroundColor Red; $wbErrors++ }
            if ($wfRepSpec.Requires -and -not ($wfRepSpec.Requires -is [string])) { Write-Host "  [ERRO] Reparo $wfRepNome`: Requires deveria ser texto" -ForegroundColor Red; $wbErrors++ }
            # Nome inédito por linha: o nome do arquivo de saída tem os segundos, então uma simulação
            # que gravasse com o nome do comando poderia sobrescrever um arquivo do mesmo segundo e a
            # contagem não mudaria.
            $wfRepSeco = Invoke-WinForgeCommandCore -Spec $wfRepSpec -Name "SimulacaoRep$wfRepNome" -Component Repair -Prefix repair -DryRun
            if (-not ([string]$wfRepSeco.Text).StartsWith('[simulação] ')) { Write-Host "  [ERRO] Reparo $wfRepNome`: -DryRun deveria devolver '[simulação] <comando>', veio '$([string]$wfRepSeco.Text)'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfRepSeco.Text -notmatch [regex]::Escape([string]$wfRepSpec.Command)) { Write-Host "  [ERRO] Reparo $wfRepNome`: -DryRun não trouxe o texto do comando" -ForegroundColor Red; $wbErrors++ }
            if ($null -ne $wfRepSeco.Path) { Write-Host "  [ERRO] Reparo $wfRepNome`: -DryRun não pode devolver caminho de arquivo (veio '$($wfRepSeco.Path)')" -ForegroundColor Red; $wbErrors++ }
            $wfRepPorTipo[[string]$wfRepSpec.Kind] = 1 + [int]$wfRepPorTipo[[string]$wfRepSpec.Kind]
        }
        $wfRepDepois = @(Get-ChildItem -LiteralPath $wfRepDir -Filter 'repair-*.txt' -ErrorAction SilentlyContinue).Count
        if ($wfRepDepois -ne $wfRepAntes) { Write-Host "  [ERRO] Reparo: -DryRun gravou arquivo na pasta de logs ($wfRepAntes -> $wfRepDepois)" -ForegroundColor Red; $wbErrors++ }
        $wfRepDesconhecido = $false
        try { Get-WinForgeRepairCommand -Name 'NaoExisteEsteComando' | Out-Null } catch { $wfRepDesconhecido = $true }
        if (-not $wfRepDesconhecido) { Write-Host "  [ERRO] Reparo: nome desconhecido deveria lançar" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Reparo (simulação): $($wfRepNomes.Count) comando(s) - $(@($wfRepPorTipo.Keys | Sort-Object | ForEach-Object { "$_=$($wfRepPorTipo[$_])" }) -join ', ') - sem rodar nada e sem gravar arquivo"
    } catch {
        Write-Host "  [ERRO] Reparo (simulação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # Despacho: nesta etapa só leitura vai para o runspace, e com -NoUI nem isso. O SelfTest roda sem
    # ninguém na frente - se um destes botões despachasse aqui, o build repararia a máquina de quem
    # compila (ou abriria uma janela num processo sem laço de mensagens).
    try {
        $wfRepTravaAntes = $sync.CommandRunning
        foreach ($wfRepNome in $wfRepNomes) {
            $wfRepDec = Invoke-WinForgeRepairCommand -Name $wfRepNome -NoUI
            if ($null -eq $wfRepDec) { Write-Host "  [ERRO] Reparo $wfRepNome`: -NoUI deveria devolver a decisão" -ForegroundColor Red; $wbErrors++; continue }
            if ($wfRepDec.Dispatched) { Write-Host "  [ERRO] Reparo $wfRepNome`: -NoUI não pode despachar nada" -ForegroundColor Red; $wbErrors++ }
            if ([string]::IsNullOrWhiteSpace($wfRepDec.Reason)) { Write-Host "  [ERRO] Reparo $wfRepNome`: -NoUI sem motivo da recusa" -ForegroundColor Red; $wbErrors++ }
            $wfRepEsperado = if ([string]$wfRepDec.Kind -eq 'read') { 'NoUI' } else { 'confirmação' }
            if ([string]$wfRepDec.Reason -ne $wfRepEsperado) { Write-Host "  [ERRO] Reparo $wfRepNome`: motivo '$($wfRepDec.Reason)', esperado '$wfRepEsperado'" -ForegroundColor Red; $wbErrors++ }
        }
        $wfRepDecRuim = Invoke-WinForgeRepairCommand -Name 'NaoExisteEsteComando' -NoUI
        if ($wfRepDecRuim.Dispatched -or [string]$wfRepDecRuim.Reason -ne 'desconhecido') { Write-Host "  [ERRO] Reparo: nome desconhecido deveria recusar com motivo 'desconhecido'" -ForegroundColor Red; $wbErrors++ }
        if ($sync.CommandRunning -ne $wfRepTravaAntes) { Write-Host "  [ERRO] Reparo: a trava de comando em andamento mudou sem nenhum despacho" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Reparo (despacho): $($wfRepNomes.Count) botão(ões) recusados com -NoUI, nada rodou"
    } catch {
        Write-Host "  [ERRO] Reparo (despacho): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # As três leituras rodam DE VERDADE nesta máquina: são o conteúdo dos únicos botões que esta
    # etapa despacha, e uma função que devolve texto vazio (ou lança sem elevação) seria uma janela
    # em branco na cara de quem clicou. Sem admin as partes que exigem elevação viram 'n/d' - o texto
    # continua saindo.
    foreach ($wfRepPar in @(@('Get-WinForgeSecurityStatus','segurança'), @('Get-WinForgeSmartReport','discos'), @('Get-WinForgeDotNetStatus','.NET'))) {
        try {
            $wfRepTexto = [string](& $wfRepPar[0])
            if ([string]::IsNullOrWhiteSpace($wfRepTexto)) { Write-Host "  [ERRO] Reparo (leitura $($wfRepPar[1])): $($wfRepPar[0]) devolveu texto vazio" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Reparo (leitura $($wfRepPar[1])): $($wfRepTexto.Length) caractere(s), $(@($wfRepTexto -split "`r?`n").Count) linha(s)" }
        } catch {
            Write-Host "  [ERRO] Reparo (leitura $($wfRepPar[1])): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
    }
    # Uma linha da tabela rodando de verdade pelo núcleo, de ponta a ponta: é o que prova que o
    # invólucro do reparo amarra 'Repair'/'repair' ao núcleo e que o arquivo de saída sai com o
    # prefixo certo. Só SecurityStatus: é leitura pura e responde em milissegundos (o chkdsk /scan,
    # que também é leitura, levaria minutos e não cabe num build).
    try {
        $wfRepReal = Invoke-WinForgeRepairCommandCore -Name SecurityStatus
        if ([string]::IsNullOrWhiteSpace($wfRepReal.Text)) { Write-Host "  [ERRO] Reparo (execução): SecurityStatus voltou sem texto" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfRepReal.Text -match 'Código de saída') { Write-Host "  [ERRO] Reparo (execução): SecurityStatus não é executável e não pode trazer linha de código de saída" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfRepReal.Path -or -not (Test-Path -LiteralPath $wfRepReal.Path)) { Write-Host "  [ERRO] Reparo (execução): SecurityStatus não gravou o arquivo ('$($wfRepReal.Path)')" -ForegroundColor Red; $wbErrors++ }
        elseif ((Split-Path -Leaf $wfRepReal.Path) -notlike 'repair-*') { Write-Host "  [ERRO] Reparo (execução): arquivo fora do prefixo 'repair' ($(Split-Path -Leaf $wfRepReal.Path))" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Reparo (execução): SecurityStatus -> $(([string]$wfRepReal.Text).Length) caractere(s) em $(Split-Path -Leaf $wfRepReal.Path)" }
    } catch {
        Write-Host "  [ERRO] Reparo (execução): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # winget fora do PATH é o caso normal logo depois de um logon novo, e é por isso que a busca não
    # é um Get-Command: o que ela não pode é lançar - nem devolver um caminho que não existe, que
    # viraria "o sistema não pode encontrar o arquivo" dentro do runspace, longe do botão.
    try {
        $wfRepWinget = Get-WinForgeWingetPath
        if ($wfRepWinget -and -not (Test-Path -LiteralPath $wfRepWinget -PathType Leaf)) { Write-Host "  [ERRO] Reparo (winget): caminho devolvido não existe ('$wfRepWinget')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Reparo (winget): $(if ($wfRepWinget) { $wfRepWinget } else { 'não encontrado nesta máquina' })"
    } catch {
        Write-Host "  [ERRO] Reparo (winget): Get-WinForgeWingetPath lançou '$($_.Exception.Message)'" -ForegroundColor Red; $wbErrors++
    }
    # Versão de pacote Appx é TEXTO: '1.9.0.0' é maior que '1.25.0.0' em ordem alfabética e menor em
    # ordem de versão. Quem escolhe errado aponta o winget para uma pasta de instalação antiga que
    # pode nem existir mais - por isso a escolha é uma função pura, testada com a lista sintética.
    try {
        $wfRepPacotes = @(
            [pscustomobject]@{ Version = '1.9.0.0';  InstallLocation = 'C:\antigo' },
            [pscustomobject]@{ Version = '1.25.0.0'; InstallLocation = 'C:\novo' },
            [pscustomobject]@{ Version = '1.10.0.0'; InstallLocation = 'C:\meio' }
        )
        $wfRepNovo = Select-WinForgeNewestPackage -Package $wfRepPacotes
        if ([string]$wfRepNovo.Version -ne '1.25.0.0') { Write-Host "  [ERRO] Reparo (versão): a mais nova de 1.9.0.0/1.25.0.0/1.10.0.0 deveria ser 1.25.0.0, veio '$($wfRepNovo.Version)'" -ForegroundColor Red; $wbErrors++ }
        if ($null -ne (Select-WinForgeNewestPackage -Package @())) { Write-Host "  [ERRO] Reparo (versão): lista vazia deveria devolver nulo" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Reparo (versão): 1.25.0.0 escolhido sobre 1.10.0.0 e 1.9.0.0 (ordem de versão, não de texto)" }
    } catch {
        Write-Host "  [ERRO] Reparo (versão): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # Confirmação: o texto que aparece na caixa antes de mexer na máquina. Ele nasce do título e da
    # descrição da config - a mesma frase que o usuário já leu no botão -, e termina perguntando.
    # Uma ação que muda o sistema sem o título na pergunta seria uma caixa dizendo "Continuar?" sem
    # dizer continuar o quê.
    try {
        $wfRepConfOk = 0
        foreach ($wfRepNome in $wfRepNomes) {
            $wfRepSpec = Get-WinForgeRepairCommand -Name $wfRepNome
            if ([string]$wfRepSpec.Kind -eq 'read') { continue }
            $wfRepConf = [string](Get-WinForgeRepairConfirmText -Name $wfRepNome)
            if ($wfRepConf -notmatch [regex]::Escape([string]$wfRepSpec.Title)) { Write-Host "  [ERRO] Reparo (confirmação) $wfRepNome`: o texto não traz o título" -ForegroundColor Red; $wbErrors++ }
            if ($wfRepConf -notmatch 'Continuar') { Write-Host "  [ERRO] Reparo (confirmação) $wfRepNome`: o texto não pergunta 'Continuar'" -ForegroundColor Red; $wbErrors++ }
            if (([regex]::Matches($wfRepConf, 'Continuar')).Count -ne 1) { Write-Host "  [ERRO] Reparo (confirmação) $wfRepNome`: 'Continuar' aparece mais de uma vez" -ForegroundColor Red; $wbErrors++ }
            if ($wfRepConf.Length -lt 120) { Write-Host "  [ERRO] Reparo (confirmação) $wfRepNome`: texto curto demais ($($wfRepConf.Length) caractere(s)) para explicar o que muda" -ForegroundColor Red; $wbErrors++ }
            $wfRepConfOk++
        }
        # A descrição da caixa TEM de ser a mesma frase que o usuário lê ao lado do botão na aba
        # Config. Sem esta conferência, alguém trocaria a fonte por um texto escrito só para a caixa e
        # os dois envelheceriam separados - a aba prometendo uma coisa e a confirmação outra.
        $wfRepDescWmi = [string]$sync.configs.feature.WPFWFRepWmiRepair.Description
        if ([string]::IsNullOrWhiteSpace($wfRepDescWmi)) { Write-Host "  [ERRO] Reparo (confirmação): WPFWFRepWmiRepair sem Description na config" -ForegroundColor Red; $wbErrors++ }
        elseif ([string](Get-WinForgeRepairConfirmText -Name WmiRepair) -notmatch [regex]::Escape($wfRepDescWmi.Trim())) { Write-Host "  [ERRO] Reparo (confirmação): o texto de WmiRepair não veio da Description da config" -ForegroundColor Red; $wbErrors++ }
        # A caixa é de Sim/Não com ícone de aviso: um "OK" não é confirmação, é aviso, e o botão
        # rodaria de qualquer jeito.
        $wfRepFonte = [string](Get-Command Invoke-WinForgeRepairCommand).ScriptBlock
        if ($wfRepFonte -notmatch 'YesNo') { Write-Host "  [ERRO] Reparo (confirmação): a caixa deveria ser YesNo" -ForegroundColor Red; $wbErrors++ }
        # Dona da janela: sem owner a caixa pode nascer ATRÁS do programa, e uma confirmação escondida
        # é uma confirmação que alguém fecha no susto para achar o que sumiu.
        # Não basta o texto '$sync.Form' aparecer na função: ele tem de ser a CONDIÇÃO do ramo que
        # chama a caixa E o primeiro argumento dela. Um 'if ($false)' na frente deixaria a linha lá,
        # bonita e morta.
        if ($wfRepFonte -notmatch '(?s)if \(\$sync\.Form\).{0,200}?MessageBox\]::Show\(\s*\$sync\.Form') { Write-Host "  [ERRO] Reparo (confirmação): a caixa deveria ter `$sync.Form como dona quando a janela existe" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Reparo (confirmação): $wfRepConfOk texto(s) com título, descrição da config e uma pergunta"
    } catch {
        Write-Host "  [ERRO] Reparo (confirmação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # O instalador do Visual C++ em simulação: a lista de ids sai sem o winget rodar. É o único jeito
    # de o build conferir a lista (as duas arquiteturas de cada ano, na ordem) sem instalar doze
    # pacotes na máquina de quem compila.
    try {
        $wfRepIdsEsperados = @(
            'Microsoft.VCRedist.2005.x86', 'Microsoft.VCRedist.2005.x64',
            'Microsoft.VCRedist.2008.x86', 'Microsoft.VCRedist.2008.x64',
            'Microsoft.VCRedist.2010.x86', 'Microsoft.VCRedist.2010.x64',
            'Microsoft.VCRedist.2012.x86', 'Microsoft.VCRedist.2012.x64',
            'Microsoft.VCRedist.2013.x86', 'Microsoft.VCRedist.2013.x64',
            'Microsoft.VCRedist.2015+.x86', 'Microsoft.VCRedist.2015+.x64'
        )
        $wfRepIds = @(Install-WinForgeVcRedist -DryRun)
        if ($wfRepIds.Count -ne $wfRepIdsEsperados.Count) { Write-Host "  [ERRO] Reparo (VcRedist simulado): $($wfRepIds.Count) id(s), esperado $($wfRepIdsEsperados.Count)" -ForegroundColor Red; $wbErrors++ }
        elseif (($wfRepIds -join '|') -ne ($wfRepIdsEsperados -join '|')) { Write-Host "  [ERRO] Reparo (VcRedist simulado): lista fora de ordem ou diferente: $($wfRepIds -join ', ')" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Reparo (VcRedist simulado): $($wfRepIds.Count) id(s) na ordem, sem chamar o winget" }
    } catch {
        Write-Host "  [ERRO] Reparo (VcRedist simulado): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # DirectX: o WinForge NÃO baixa executável. O botão abre a página oficial da Microsoft e quem
    # baixa e roda o instalador web é o usuário, no navegador, com o token dele. A versão anterior
    # baixava o dxwebsetup.exe para %TEMP% (gravável por integridade média) e o abria elevado, com
    # uma janela entre a conferência da assinatura e o Start-Process.
    #
    # A linha é 'read' e mesmo assim NUNCA roda no SelfTest: 'OpensExternal' marca isso, e o build
    # confere o marcador em vez de abrir um navegador na máquina de quem compila.
    try {
        $wfRepDx = Get-WinForgeRepairCommand -Name DirectX
        if ([string]$wfRepDx.Kind -ne 'read') { Write-Host "  [ERRO] Reparo (DirectX): abrir uma página é leitura, veio Kind '$($wfRepDx.Kind)'" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfRepDx.OpensExternal) { Write-Host "  [ERRO] Reparo (DirectX): a linha deveria estar marcada com OpensExternal" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfRepDx.Command -notmatch "^Start-Process 'https://www\.microsoft\.com/download/details\.aspx\?id=35'$") { Write-Host "  [ERRO] Reparo (DirectX): o comando deveria ser um Start-Process da página oficial, veio '$($wfRepDx.Command)'" -ForegroundColor Red; $wbErrors++ }
        # Nenhuma função de download sobrou no programa: se alguma voltar, este teste cai.
        foreach ($wfRepDxMorta in @('Install-WinForgeDirectX', 'Test-WinForgeMicrosoftSignature', 'Test-WinForgeMicrosoftSigner', 'Split-WinForgeCertificateSubject')) {
            if (Get-Command $wfRepDxMorta -ErrorAction SilentlyContinue) { Write-Host "  [ERRO] Reparo (DirectX): '$wfRepDxMorta' voltou ao programa - o WinForge não baixa executável" -ForegroundColor Red; $wbErrors++ }
        }
        # E o marcador tem de valer de verdade: nenhuma linha com OpensExternal pode estar na lista
        # que o SelfTest roda de ponta a ponta.
        $wfRepExecutadas = @('SecurityStatus')
        foreach ($wfRepNome in $wfRepExecutadas) {
            if ((Get-WinForgeRepairCommand -Name $wfRepNome).OpensExternal) { Write-Host "  [ERRO] Reparo (DirectX): '$wfRepNome' abre coisa fora do WinForge e não pode rodar no SelfTest" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Reparo (DirectX): botão de leitura que abre a página oficial, sem download e sem execução no SelfTest"
    } catch {
        Write-Host "  [ERRO] Reparo (DirectX): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # Confiança do pacote Appx: é ela que decide de qual pasta sai o winget.exe que o WinForge roda
    # ELEVADO. '-Name Microsoft.DesktopAppInstaller' filtra pela identidade do manifesto, que quem
    # instala escolhe - um pacote sideloaded com esse nome e versão 99.0.0.0 vencia a ordenação e
    # apontava para uma pasta gravável por integridade média. Os casos são sintéticos de propósito:
    # a prova não pode depender do que está instalado em quem compila.
    try {
        # A raiz sai de [Environment]::GetFolderPath(ProgramFiles), como na própria porteira:
        # %ProgramFiles% vem do bloco de ambiente do usuário e é gravável em integridade média.
        $wfRepPfRaiz = [string][Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
        # Desde que a varredura de reanálise passou a RECUSAR o que não consegue ler, um caminho
        # inventado dentro de WindowsApps deixou de servir como caso positivo - ele é agora um caso
        # negativo, e está na tabela como tal. Os positivos precisam de uma pasta que exista de
        # verdade sob WindowsApps, e a única que dá para descobrir sem listar a pasta (a listagem é
        # negada até para administrador) é a do pacote realmente instalado. Sem App Installer na
        # máquina, os quatro casos que dependem dela ficam de fora, com aviso - as três recusas que
        # não dependem de pasta continuam valendo.
        $wfRepBoaPasta = $null
        try {
            $wfRepBoaPasta = [string](@(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.InstallLocation) -and (Test-Path -LiteralPath ([string]$_.InstallLocation) -PathType Container) } |
                Select-Object -First 1).InstallLocation
        } catch { $wfRepBoaPasta = $null }
        $wfRepPastaInventada = Join-Path $wfRepPfRaiz 'WindowsApps\Microsoft.DesktopAppInstaller_1.25.0.0_x64__8wekyb3d8bbwe'
        $wfRepConfCasos = @(
            @('pasta inventada',      @{ PublisherId = '8wekyb3d8bbwe'; SignatureKind = 'Store';     InstallLocation = $wfRepPastaInventada }, $false),
            @('pasta do usuário',     @{ PublisherId = '8wekyb3d8bbwe'; SignatureKind = 'Store';     InstallLocation = (Join-Path $env:LocalAppData 'Microsoft\WindowsApps') }, $false),
            @('sem pasta',            @{ PublisherId = '8wekyb3d8bbwe'; SignatureKind = 'Store';     InstallLocation = '' }, $false),
            @('nulo',                 $null, $false)
        )
        if ([string]::IsNullOrWhiteSpace($wfRepBoaPasta)) {
            Write-Host "  Reparo (pacote confiável): sem Microsoft.DesktopAppInstaller instalado - os casos com pasta real ficaram de fora"
        } else {
            $wfRepConfCasos = @(
                @('Store em WindowsApps', @{ PublisherId = '8wekyb3d8bbwe'; SignatureKind = 'Store';     InstallLocation = $wfRepBoaPasta }, $true),
                @('do sistema',           @{ PublisherId = '8wekyb3d8bbwe'; SignatureKind = 'System';    InstallLocation = $wfRepBoaPasta }, $true),
                @('outro editor',         @{ PublisherId = 'abcdefghijklm'; SignatureKind = 'Store';     InstallLocation = $wfRepBoaPasta }, $false),
                @('modo desenvolvedor',   @{ PublisherId = '8wekyb3d8bbwe'; SignatureKind = 'Developer'; InstallLocation = $wfRepBoaPasta }, $false)
            ) + $wfRepConfCasos
        }
        $wfRepConfOkAppx = 0
        foreach ($wfRepConfCaso in $wfRepConfCasos) {
            $wfRepConfObj = if ($null -eq $wfRepConfCaso[1]) { $null } else { [pscustomobject]$wfRepConfCaso[1] }
            $wfRepConfVeio = [bool](Test-WinForgeTrustedAppxPackage -Package $wfRepConfObj)
            if ($wfRepConfVeio -ne [bool]$wfRepConfCaso[2]) { Write-Host "  [ERRO] Reparo (pacote confiável): '$($wfRepConfCaso[0])' deveria dar $($wfRepConfCaso[2]), deu $wfRepConfVeio" -ForegroundColor Red; $wbErrors++ }
            else { $wfRepConfOkAppx++ }
        }
        # A porteira tem de estar no caminho, e não só existir: quem escolhe o winget e quem escolhe
        # o manifesto a registrar chamam a mesma função.
        foreach ($wfRepConfFn in @('Get-WinForgeWingetPath', 'Invoke-WinForgeStoreReregister')) {
            if ([string](Get-Command $wfRepConfFn).ScriptBlock -notmatch 'Test-WinForgeTrustedAppxPackage') { Write-Host "  [ERRO] Reparo (pacote confiável): '$wfRepConfFn' não passa pelo filtro de confiança" -ForegroundColor Red; $wbErrors++ }
        }
        # E o PATH está fora: um alias de execução em %LOCALAPPDATA%\Microsoft\WindowsApps é
        # gravável por integridade média, e o botão do Visual C++ o rodaria com token de admin.
        if ([string](Get-Command Get-WinForgeWingetPath).ScriptBlock -match "Get-Command\s+'?winget[^']*'?\s+-ErrorAction") { Write-Host "  [ERRO] Reparo (pacote confiável): Get-WinForgeWingetPath voltou a resolver o winget pelo PATH" -ForegroundColor Red; $wbErrors++ }
        # A raiz de WindowsApps também não pode sair de %ProgramFiles%: é variável do bloco do
        # usuário, gravável em integridade média, e com ela apontando para uma pasta do perfil o
        # "prefixo de WindowsApps" viraria um caminho que qualquer um escreve. Com a variável
        # plantada, o pacote bom tem de continuar passando - se a função voltar a lê-la, ele é
        # recusado e a prova cai.
        if (-not [string]::IsNullOrWhiteSpace($wfRepBoaPasta)) {
            $wfRepPfAntes = $env:ProgramFiles
            $wfRepPfVeio = $null
            try {
                $env:ProgramFiles = 'C:\WinForge-ProgramFiles-Plantado'
                $wfRepPfVeio = [bool](Test-WinForgeTrustedAppxPackage -Package ([pscustomobject]@{ PublisherId = '8wekyb3d8bbwe'; SignatureKind = 'Store'; InstallLocation = $wfRepBoaPasta }))
            } finally {
                if ($null -eq $wfRepPfAntes) { Remove-Item -LiteralPath 'Env:\ProgramFiles' -ErrorAction SilentlyContinue } else { $env:ProgramFiles = $wfRepPfAntes }
            }
            if (-not $wfRepPfVeio) { Write-Host "  [ERRO] Reparo (pacote confiável): com %ProgramFiles% plantado o pacote bom foi recusado - a raiz tem de sair de [Environment]::GetFolderPath" -ForegroundColor Red; $wbErrors++ }
            if ($env:ProgramFiles -ne $wfRepPfAntes) { Write-Host "  [ERRO] Reparo (pacote confiável): %ProgramFiles% não foi devolvida depois da prova" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Reparo (pacote confiável): $wfRepConfOkAppx de $($wfRepConfCasos.Count) caso(s) - só editor 8wekyb3d8bbwe, assinatura Store/System e pasta EXISTENTE em WindowsApps passam"
    } catch {
        Write-Host "  [ERRO] Reparo (pacote confiável): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # Executável do sistema por caminho completo. O WinForge roda SEMPRE elevado: chamar 'chkdsk.exe'
    # pelo nome deixa a escolha do binário com o PATH, e um PATH de sistema editado por instalador
    # (que prepende a própria pasta) faz um executável de terceiro rodar com token de administrador.
    # O winmgmt tem uma armadilha a mais: ele mora em System32\wbem, e sem essa pasta no PATH a
    # chamada por nome nem encontra nada.
    try {
        $wfExeEsperado = Join-Path ([Environment]::SystemDirectory) 'fsutil.exe'
        if ((Get-WinForgeSystemExe -Name 'fsutil.exe') -ne $wfExeEsperado) { Write-Host "  [ERRO] Executáveis: Get-WinForgeSystemExe -Name fsutil.exe deveria dar '$wfExeEsperado', deu '$(Get-WinForgeSystemExe -Name 'fsutil.exe')'" -ForegroundColor Red; $wbErrors++ }
        # E a âncora não pode ser %SystemRoot%: essa variável nasce do bloco de ambiente do USUÁRIO
        # (HKCU\Environment), que qualquer processo de integridade média da conta escreve. Com ela
        # apontando para uma pasta do perfil, todo executável de sistema do WinForge - que roda
        # ELEVADO - sairia de lá. A prova planta o valor por um instante e o devolve no finally.
        $wfExeRootAntes = $env:SystemRoot
        $wfExeSob = $null
        try {
            $env:SystemRoot = 'C:\WinForge-SystemRoot-Plantado'
            $wfExeSob = Get-WinForgeSystemExe -Name 'fsutil.exe'
        } finally {
            if ($null -eq $wfExeRootAntes) { Remove-Item -LiteralPath 'Env:\SystemRoot' -ErrorAction SilentlyContinue } else { $env:SystemRoot = $wfExeRootAntes }
        }
        if ($wfExeSob -ne $wfExeEsperado) { Write-Host "  [ERRO] Executáveis: com %SystemRoot% plantado o caminho virou '$wfExeSob' - a âncora tem de ser [Environment]::SystemDirectory" -ForegroundColor Red; $wbErrors++ }
        if ($env:SystemRoot -ne $wfExeRootAntes) { Write-Host "  [ERRO] Executáveis: %SystemRoot% não foi devolvida depois da prova" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeSystemExe -Name 'wbem\winmgmt.exe') -ne (Join-Path ([Environment]::SystemDirectory) 'wbem\winmgmt.exe')) { Write-Host "  [ERRO] Executáveis: o winmgmt deveria sair em System32\wbem" -ForegroundColor Red; $wbErrors++ }
        if (-not [System.IO.Path]::IsPathRooted((Get-WinForgeSystemExe -Name 'chkdsk.exe'))) { Write-Host "  [ERRO] Executáveis: Get-WinForgeSystemExe devolveu caminho relativo" -ForegroundColor Red; $wbErrors++ }
        # A exigência por caminho absoluto é conferida com Test-Path, não com Get-Command.
        if (-not (Test-WinForgeCommandRequirement -Requires (Get-WinForgeSystemExe -Name 'fsutil.exe'))) { Write-Host "  [ERRO] Executáveis: o fsutil por caminho completo deveria existir nesta máquina" -ForegroundColor Red; $wbErrors++ }
        if (Test-WinForgeCommandRequirement -Requires (Join-Path ([Environment]::SystemDirectory) 'nao-existe-este-executavel.exe')) { Write-Host "  [ERRO] Executáveis: caminho absoluto inexistente deveria ser recusado" -ForegroundColor Red; $wbErrors++ }
        # Nenhum nome solto sobrou no programa inteiro: todo -FilePath literal é caminho absoluto, e
        # toda linha 'Native' da tabela do servidor chama o executável por caminho absoluto.
        $wfExeFonte = ''
        try { if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) { $wfExeFonte = [IO.File]::ReadAllText($PSCommandPath) } } catch { $wfExeFonte = '' }
        if ([string]::IsNullOrWhiteSpace($wfExeFonte)) {
            Write-Host "  [ERRO] Executáveis: o próprio arquivo do WinForge não pôde ser lido para a conferência de -FilePath" -ForegroundColor Red; $wbErrors++
        } else {
            $wfExeSoltos = @()
            foreach ($wfExeM in [regex]::Matches($wfExeFonte, "-FilePath\s+'([^']+)'")) {
                $wfExeVal = [string]$wfExeM.Groups[1].Value
                if (-not [System.IO.Path]::IsPathRooted($wfExeVal)) { $wfExeSoltos += $wfExeVal }
            }
            if ($wfExeSoltos.Count) { Write-Host "  [ERRO] Executáveis: -FilePath com nome solto (resolvido pelo PATH): $(@($wfExeSoltos | Sort-Object -Unique) -join ', ')" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Executáveis: $(([regex]::Matches($wfExeFonte, "-FilePath\s+'([^']+)'")).Count) -FilePath literal(is), todos com caminho absoluto" }
            # A varredura acima só olha uma forma ('-FilePath' com aspas simples), e foi por uma
            # fresta dessas que o powercfg do perfil sobreviveu: ele era chamado pelo NOME, solto no
            # meio de um pipeline, e o w32tm ia como texto em "-Command 'w32tm /query /source'" - as
            # duas formas passavam batido. Aqui a conferência é sobre o CÓDIGO das quatro áreas do
            # WinForge que chamam ferramenta de sistema, e cobre as três formas.
            #
            # O recorte por região é o que torna isso possível: o utilitário de base sobre o qual o
            # WinForge é construído chama 'netsh' e afins por Start-Process -FilePath "netsh", e esse
            # arquivo não é nosso para editar. As marcas '#region ===== WinForge - ... =====' e
            # '#endregion' delimitam exatamente os blocos que saem de src\Engine\winforge. O '?' no
            # nome de uma região é curinga de -like, para a conferência não depender de o acento
            # chegar inteiro até aqui.
            $wfExeRegioes = @('perfil do sistema', 'comandos com janela de sa?da', 'reparo de componentes', 'servidor (IIS/AD)')
            $wfExeNomes = 'w32tm|powercfg|netsh|fsutil|bcdedit|chkdsk|winmgmt|dcdiag|repadmin'
            $wfExeLinhas = @($wfExeFonte -split "`r?`n")
            $wfExeCodigo = @()
            foreach ($wfExeReg in $wfExeRegioes) {
                $wfExeIni = -1
                for ($wfExeI = 0; $wfExeI -lt $wfExeLinhas.Count; $wfExeI++) {
                    if ($wfExeLinhas[$wfExeI] -like "#region ===== WinForge - $wfExeReg =====") { $wfExeIni = $wfExeI; break }
                }
                if ($wfExeIni -lt 0) { Write-Host "  [ERRO] Executáveis: região '$wfExeReg' não encontrada no motor - a varredura de nome solto ficaria cega" -ForegroundColor Red; $wbErrors++; continue }
                # Comentário de BLOCO fora: os cabeçalhos de ajuda falam de w32tm, netsh e dcdiag o
                # tempo todo, em prosa. Comentário de linha idem - cortar no '#' só tira texto, então
                # no máximo esconde uma chamada, nunca inventa uma.
                $wfExeEmBloco = $false
                for ($wfExeI = $wfExeIni + 1; $wfExeI -lt $wfExeLinhas.Count; $wfExeI++) {
                    $wfExeL = [string]$wfExeLinhas[$wfExeI]
                    if ($wfExeL -eq '#endregion') { break }
                    if ($wfExeEmBloco) {
                        $wfExeFim = $wfExeL.IndexOf('#>')
                        if ($wfExeFim -lt 0) { continue }
                        $wfExeL = $wfExeL.Substring($wfExeFim + 2)
                        $wfExeEmBloco = $false
                    }
                    while ($true) {
                        $wfExeAb = $wfExeL.IndexOf('<#')
                        if ($wfExeAb -lt 0) { break }
                        $wfExeFim = $wfExeL.IndexOf('#>', $wfExeAb + 2)
                        if ($wfExeFim -lt 0) { $wfExeL = $wfExeL.Substring(0, $wfExeAb); $wfExeEmBloco = $true; break }
                        $wfExeL = $wfExeL.Substring(0, $wfExeAb) + $wfExeL.Substring($wfExeFim + 2)
                    }
                    $wfExeL = [regex]::Replace($wfExeL, '#.*$', '')
                    if (-not [string]::IsNullOrWhiteSpace($wfExeL)) { $wfExeCodigo += ,@($wfExeReg, ($wfExeI + 1), $wfExeL) }
                }
            }
            $wfExeAchados = @()
            foreach ($wfExeItem in $wfExeCodigo) {
                $wfExeTexto = [string]$wfExeItem[2]
                # 1. "-Command '<exe> ...'": o texto é COMPILADO, e o nome solto lá dentro volta a
                #    ser resolvido pelo PATH.
                foreach ($wfExePadrao in @("-Command\s+'([^']+)'", '-Command\s+"([^"]+)"')) {
                    foreach ($wfExeM in [regex]::Matches($wfExeTexto, $wfExePadrao)) {
                        $wfExeVal = ([string]$wfExeM.Groups[1].Value).TrimStart()
                        if ($wfExeVal -match "^&?\s*'?($wfExeNomes)(\.exe)?'?(\s|$)") { $wfExeAchados += "$($wfExeItem[0]):$($wfExeItem[1]) -Command '$wfExeVal'" }
                    }
                }
                # 2. '-FilePath "..."': a outra aspa, que a varredura do arquivo inteiro não olha.
                #    "$variavel" fica de fora do padrão - ali o valor não está no texto.
                foreach ($wfExeM in [regex]::Matches($wfExeTexto, '-FilePath\s+"([^"$]+)"')) {
                    if (-not [System.IO.Path]::IsPathRooted([string]$wfExeM.Groups[1].Value)) { $wfExeAchados += "$($wfExeItem[0]):$($wfExeItem[1]) -FilePath ""$($wfExeM.Groups[1].Value)""" }
                }
                # 3. O executável chamado direto, fora de qualquer literal. Os literais saem antes -
                #    é neles que moram os '-Name ''powercfg.exe''' de Get-WinForgeSystemExe.
                $wfExeSem = [regex]::Replace($wfExeTexto, "'[^']*'", ' ')
                $wfExeSem = [regex]::Replace($wfExeSem, '"[^"]*"', ' ')
                foreach ($wfExeM in [regex]::Matches($wfExeSem, "(?:^|[\s({|;&=])($wfExeNomes)(\.exe)?(?=\s|\)|$)")) {
                    $wfExeAchados += "$($wfExeItem[0]):$($wfExeItem[1]) '$($wfExeM.Groups[1].Value)' solto"
                }
            }
            if ($wfExeAchados.Count) {
                Write-Host "  [ERRO] Executáveis: $($wfExeAchados.Count) chamada(s) de ferramenta de sistema fora de Get-WinForgeSystemExe" -ForegroundColor Red; $wbErrors++
                foreach ($wfExeA in @($wfExeAchados | Sort-Object -Unique)) { Write-Host "           $wfExeA" -ForegroundColor Red }
            } else {
                Write-Host "  Executáveis: $($wfExeCodigo.Count) linha(s) de código em $($wfExeRegioes.Count) região(ões) - nenhum w32tm/powercfg/netsh/fsutil/bcdedit/chkdsk/winmgmt/dcdiag/repadmin fora de Get-WinForgeSystemExe"
            }
        }
        foreach ($wbSrvNome in $wbSrvNomes) {
            $wbSrvCmd = Get-WinForgeServerCommand -Name $wbSrvNome
            if (-not $wbSrvCmd.Native) { continue }
            if ([string]$wbSrvCmd.Requires -and -not [System.IO.Path]::IsPathRooted([string]$wbSrvCmd.Requires)) { Write-Host "  [ERRO] Executáveis: '$wbSrvNome' exige '$($wbSrvCmd.Requires)' pelo PATH" -ForegroundColor Red; $wbErrors++ }
            foreach ($wbSrvChamada in [regex]::Matches([string]$wbSrvCmd.Command, "&\s+'([^']+)'")) {
                if (-not [System.IO.Path]::IsPathRooted([string]$wbSrvChamada.Groups[1].Value)) { Write-Host "  [ERRO] Executáveis: '$wbSrvNome' chama '$($wbSrvChamada.Groups[1].Value)' pelo PATH" -ForegroundColor Red; $wbErrors++ }
            }
            if ([string]$wbSrvCmd.Command -notmatch "&\s+'") { Write-Host "  [ERRO] Executáveis: '$wbSrvNome' é Native e não chama executável por caminho entre aspas" -ForegroundColor Red; $wbErrors++ }
        }
    } catch {
        Write-Host "  [ERRO] Executáveis: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # Recusa em modo SelfTest. Esta parte nasceu de um estrago real: uma chamada de teste a um
    # ajudante que ainda não tinha bloco param() engoliu o '-DryRun' em $args, e o instalador web do
    # DirectX foi baixado e ABERTO na máquina de quem estava compilando - com o winget instalando os
    # doze redistribuíveis na mesma rodada. Uma função PowerShell sem param() aceita qualquer switch
    # em silêncio. A resposta tem duas camadas, e as duas são provadas aqui: TODA função que escreve
    # declara -DryRun de verdade, e TODA função que escreve recusa quando $sync.SelfTest está ligado.
    $wfRepEscrevem = @(
        'Invoke-WinForgeWmiRepair', 'Invoke-WinForgeStoreReregister', 'Enable-WinForgeDotNet35',
        'Install-WinForgeVcRedist', 'Install-WinForgePowerShell7',
        'Invoke-WinForgeChkdskSchedule', 'Invoke-WinForgeMemoryDiagSchedule'
    )
    try {
        if (-not $sync.SelfTest) { Write-Host "  [ERRO] Reparo (trava): `$sync.SelfTest deveria estar ligado dentro do SelfTest" -ForegroundColor Red; $wbErrors++ }
        $wfRepSemParam = @($wfRepEscrevem | Where-Object {
            $wfRepInfo = Get-Command $_ -ErrorAction SilentlyContinue
            ($null -eq $wfRepInfo) -or (-not $wfRepInfo.Parameters.ContainsKey('DryRun'))
        })
        if ($wfRepSemParam.Count) { Write-Host "  [ERRO] Reparo (trava): função que escreve sem bloco param() com -DryRun: $($wfRepSemParam -join ', ')" -ForegroundColor Red; $wbErrors++ }
        # Com -DryRun elas continuam respondendo DENTRO do SelfTest: a trava vem depois do retorno da
        # simulação de propósito, senão o próprio SelfTest não conseguiria exercitar as tabelas.
        $wfRepSecoOk = 0
        foreach ($wfRepFn in $wfRepEscrevem) {
            try {
                $wfRepSecoR = & $wfRepFn -DryRun
                if ($null -eq $wfRepSecoR) { Write-Host "  [ERRO] Reparo (trava): $wfRepFn -DryRun não devolveu nada" -ForegroundColor Red; $wbErrors++ }
                else { $wfRepSecoOk++ }
            } catch {
                Write-Host "  [ERRO] Reparo (trava): $wfRepFn -DryRun lançou '$($_.Exception.Message)' - a simulação tem de funcionar em SelfTest" -ForegroundColor Red; $wbErrors++
            }
        }
        if ($wfRepSecoOk -ne $wfRepEscrevem.Count) { Write-Host "  [ERRO] Reparo (trava): $wfRepSecoOk de $($wfRepEscrevem.Count) simulação(ões) responderam" -ForegroundColor Red; $wbErrors++ }
        # A trava direta, na função compartilhada: a mensagem tem de dizer QUEM foi recusado.
        $wfRepAssert = $null
        try { Assert-WinForgeNotSelfTest -Name 'FuncaoDeTeste'; } catch { $wfRepAssert = [string]$_.Exception.Message }
        if ($null -eq $wfRepAssert) { Write-Host "  [ERRO] Reparo (trava): Assert-WinForgeNotSelfTest não recusou com `$sync.SelfTest ligado" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfRepAssert -notmatch 'SelfTest' -or $wfRepAssert -notmatch 'FuncaoDeTeste') { Write-Host "  [ERRO] Reparo (trava): mensagem sem o nome da função ou sem 'SelfTest': '$wfRepAssert'" -ForegroundColor Red; $wbErrors++ }
        # O chkdsk é o caso que mais dói: não existe 'fsutil dirty clear', e um bit ligado por engano
        # faz o Windows verificar o disco em TODA reinicialização até o autochk se dar por satisfeito.
        # Por isso a prova é nele - e o estado do volume antes e depois tem de ser o mesmo. A leitura
        # ('fsutil dirty query') costuma exigir elevação; sem ela, a prova fica só na recusa.
        $wfRepVolume = if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { 'C:' } else { $env:SystemDrive }
        $wfRepSujoAntes = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'fsutil.exe') -Arguments @('dirty', 'query', $wfRepVolume)
        $wfRepRecusa = $null
        try { Invoke-WinForgeChkdskSchedule | Out-Null } catch { $wfRepRecusa = [string]$_.Exception.Message }
        if ($null -eq $wfRepRecusa) { Write-Host "  [ERRO] Reparo (trava): Invoke-WinForgeChkdskSchedule sem -DryRun deveria recusar em SelfTest" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfRepRecusa -notmatch 'SelfTest') { Write-Host "  [ERRO] Reparo (trava): a recusa do chkdsk não fala em SelfTest: '$wfRepRecusa'" -ForegroundColor Red; $wbErrors++ }
        $wfRepSujoDepois = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'fsutil.exe') -Arguments @('dirty', 'query', $wfRepVolume)
        if ([int]$wfRepSujoAntes.ExitCode -eq 0 -and [int]$wfRepSujoDepois.ExitCode -eq 0) {
            if ([string]$wfRepSujoAntes.Text -ne [string]$wfRepSujoDepois.Text) { Write-Host "  [ERRO] Reparo (trava): o estado de '$wfRepVolume' mudou depois da recusa do chkdsk" -ForegroundColor Red; $wbErrors++ }
            $wfRepSujoNota = 'estado do volume inalterado'
        } else {
            $wfRepSujoNota = "estado do volume não conferível sem elevação (fsutil dirty query saiu com $($wfRepSujoAntes.ExitCode))"
        }
        # O funil genérico: linha de tabela com Kind que não é 'read' e sem -DryRun morre aqui, antes
        # de qualquer coisa. A linha é sintética e o comando é inofensivo de propósito - se a trava
        # cair, o que roda é um Get-Date, e não um instalador.
        $wfRepNucleoSpec = @{ Title = 'Trava de SelfTest'; Command = 'Get-Date'; Kind = 'install'; Native = $false; Requires = $null }
        $wfRepNucleoRecusa = $null
        try { Invoke-WinForgeCommandCore -Spec $wfRepNucleoSpec -Name 'TravaSelfTest' -Component Repair -Prefix repair | Out-Null } catch { $wfRepNucleoRecusa = [string]$_.Exception.Message }
        if ($null -eq $wfRepNucleoRecusa) { Write-Host "  [ERRO] Reparo (trava): o núcleo rodou uma linha 'install' em SelfTest" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfRepNucleoRecusa -notmatch 'SelfTest') { Write-Host "  [ERRO] Reparo (trava): a recusa do núcleo não fala em SelfTest: '$wfRepNucleoRecusa'" -ForegroundColor Red; $wbErrors++ }
        # E a mesma linha COM -DryRun continua passando: a trava não pode cegar a simulação.
        $wfRepNucleoSeco = Invoke-WinForgeCommandCore -Spec $wfRepNucleoSpec -Name 'TravaSelfTestSeco' -Component Repair -Prefix repair -DryRun
        if (-not ([string]$wfRepNucleoSeco.Text).StartsWith('[simulação] ')) { Write-Host "  [ERRO] Reparo (trava): -DryRun de uma linha 'install' deveria continuar simulando em SelfTest" -ForegroundColor Red; $wbErrors++ }
        # 'OpensExternal' é o outro lado: a linha é 'read' (abrir uma página não altera nada) e mesmo
        # assim não pode rodar num build, porque abriria o navegador na máquina de quem compila. Isso
        # era só uma convenção conferida por fora ("nenhuma linha marcada está na lista que o SelfTest
        # roda"); agora é recusa no próprio núcleo. A linha é sintética e o comando é um Get-Date - se
        # a trava cair, o que roda é isso, e não um navegador.
        $wfRepAbreSpec = @{ Title = 'Trava de OpensExternal'; Command = 'Get-Date'; Kind = 'read'; Native = $false; Requires = $null; OpensExternal = $true }
        $wfRepAbreRecusa = $null
        try { Invoke-WinForgeCommandCore -Spec $wfRepAbreSpec -Name 'TravaAbreExterno' -Component Repair -Prefix repair | Out-Null } catch { $wfRepAbreRecusa = [string]$_.Exception.Message }
        if ($null -eq $wfRepAbreRecusa) { Write-Host "  [ERRO] Reparo (trava): o núcleo rodou uma linha 'OpensExternal' em SelfTest" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfRepAbreRecusa -notmatch 'SelfTest' -or $wfRepAbreRecusa -notmatch 'OpensExternal') { Write-Host "  [ERRO] Reparo (trava): a recusa de OpensExternal não fala em SelfTest e no marcador: '$wfRepAbreRecusa'" -ForegroundColor Red; $wbErrors++ }
        $wfRepAbreSeco = Invoke-WinForgeCommandCore -Spec $wfRepAbreSpec -Name 'TravaAbreExternoSeco' -Component Repair -Prefix repair -DryRun
        if (-not ([string]$wfRepAbreSeco.Text).StartsWith('[simulação] ')) { Write-Host "  [ERRO] Reparo (trava): -DryRun de uma linha 'OpensExternal' deveria continuar simulando em SelfTest" -ForegroundColor Red; $wbErrors++ }
        # O clique sem -NoUI também não pode abrir caixa nenhuma durante o SelfTest: não há ninguém
        # para responder e o build ficaria pendurado. A ordem é conferida na fonte (chamar a função
        # sem -NoUI aqui abriria a caixa se a trava estivesse quebrada, o que é justamente o risco).
        $wfRepOrdem = [string](Get-Command Invoke-WinForgeRepairCommand).ScriptBlock
        $wfRepIdxTrava = $wfRepOrdem.IndexOf('Assert-WinForgeNotSelfTest')
        $wfRepIdxCaixa = $wfRepOrdem.IndexOf('YesNo')
        if ($wfRepIdxTrava -lt 0) { Write-Host "  [ERRO] Reparo (trava): Invoke-WinForgeRepairCommand sem a trava de SelfTest" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfRepIdxCaixa -lt 0 -or $wfRepIdxTrava -gt $wfRepIdxCaixa) { Write-Host "  [ERRO] Reparo (trava): a trava de SelfTest tem de vir ANTES da caixa de confirmação" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Reparo (trava): $($wfRepEscrevem.Count) função(ões) com -DryRun e recusando em SelfTest; núcleo recusa 'install' e 'OpensExternal'; $wfRepSujoNota"
    } catch {
        Write-Host "  [ERRO] Reparo (trava): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # Leitura de 'winget list': a saída é uma TABELA de largura fixa e o id longo sai cortado na
    # coluna. Procurar o id inteiro dá "não instalado" para um pacote que está lá, e o botão reinstala
    # os doze redistribuíveis à toa - minutos de winget para não mudar nada.
    try {
        $wfRepWgCasos = @(
            @('Microsoft.VCRedist.2015+.x64', 0, "Nome    Id                       Versão`r`nMicrosoft Visual C++    Microsoft.VCRedist.2015…  14.40.33810.0", $true),
            @('Microsoft.VCRedist.2015+.x64', 0, "Nome    Id    Versão`r`nMicrosoft.VCRedist.2015+.x64  14.40.33810.0", $true),
            @('Microsoft.VCRedist.2005.x86',  0, 'Nenhum pacote instalado encontrado com os critérios de entrada.', $false),
            @('Microsoft.VCRedist.2005.x86',  1, 'Microsoft.VCRedist.2005.x86', $false),
            @('Microsoft.PowerShell',         0, '', $false)
        )
        $wfRepWgOk = 0
        foreach ($wfRepWgCaso in $wfRepWgCasos) {
            $wfRepWgVeio = [bool](Test-WinForgeWingetInstalled -Id $wfRepWgCaso[0] -ExitCode $wfRepWgCaso[1] -Text $wfRepWgCaso[2])
            if ($wfRepWgVeio -ne [bool]$wfRepWgCaso[3]) { Write-Host "  [ERRO] Reparo (winget list): '$($wfRepWgCaso[0])' código $($wfRepWgCaso[1]) deveria dar $($wfRepWgCaso[3]), deu $wfRepWgVeio" -ForegroundColor Red; $wbErrors++ }
            else { $wfRepWgOk++ }
        }
        # O prefixo usado na busca não pode ser o id inteiro: seria voltar ao caso que quebra.
        if ((Test-WinForgeWingetInstalled -Id 'Microsoft.VCRedist.2015+.x64' -ExitCode 0 -Text 'Microsoft.VCRedist.2') -ne $true) { Write-Host "  [ERRO] Reparo (winget list): a busca deveria caber nos 20 primeiros caracteres do id" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Reparo (winget list): $wfRepWgOk de $($wfRepWgCasos.Count) leitura(s) - id cortado na coluna conta como instalado, código diferente de 0 não"
    } catch {
        Write-Host "  [ERRO] Reparo (winget list): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # A guarda do lookup de Invoke-WPFButton: sem ela o caminho da config chamaria $buttonConfig.function
    # (inexistente nestas entradas) e o clique morreria antes de chegar ao switch que passa o -Name.
    try {
        $wfRepLookup = [string](Get-Command Invoke-WPFButton).ScriptBlock
        if ($wfRepLookup -notmatch '\$Button -notlike "WPFWFRep\*"') { Write-Host "  [ERRO] Reparo: o lookup de Invoke-WPFButton não exclui as chaves WPFWFRep*" -ForegroundColor Red; $wbErrors++ }
        $wfRepSemEntrada = @($wfRepNomes | Where-Object { $null -eq $sync.configs.feature."WPFWFRep$_" })
        if ($wfRepSemEntrada.Count) { Write-Host "  [ERRO] Reparo: sem entrada na config da aba Config: $($wfRepSemEntrada -join ', ')" -ForegroundColor Red; $wbErrors++ }
        $wfRepComFuncao = @($wfRepNomes | Where-Object { $wfRepEntrada = $sync.configs.feature."WPFWFRep$_"; $wfRepEntrada -and $wfRepEntrada.PSObject.Properties['function'] })
        if ($wfRepComFuncao.Count) { Write-Host "  [ERRO] Reparo: entradas com chave 'function' morta: $($wfRepComFuncao -join ', ')" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Reparo (lookup): WPFWFRep* fora do caminho da config, despacho pelo switch com -Name" }
    } catch {
        Write-Host "  [ERRO] Reparo (lookup): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
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
        # Ordem da barra de navegação: é a ordem de leitura da ferramenta (diagnosticar, ajustar,
        # depois instalar), não a da base. Vale nos dois modos - quem esconde botão em servidor é
        # Update-WinForgeTabVisibility, que mexe em Visibility e não na ordem.
        $wfNavEsperada = @('WPFTab8BT','WPFTab2BT','WPFTab7BT','WPFTab3BT','WPFTab9BT','WPFTab4BT','WPFTab1BT','WPFTab5BT')
        $wfNavOrdem = Get-WinForgeNavOrder -Window $wbWindow
        if (($wfNavOrdem -join ',') -ne ($wfNavEsperada -join ',')) { Write-Host "  [ERRO] barra de navegação: ordem '$($wfNavOrdem -join ',')', esperada '$($wfNavEsperada -join ',')'" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Barra de navegação: $($wfNavOrdem.Count) botão(ões) na ordem $($wfNavOrdem -join ' > ')" }
        # Chips de filtro da aba Instalar: o filtro compara o texto do chip com a categoria do
        # aplicativo, então o conjunto de chips (fora "Todos") tem de ser exatamente o conjunto de
        # grupos da lista. Um grupo novo sem chip fica sem filtro; um chip sem grupo não filtra nada.
        $wfChips = @($wbWindow.FindName('WPFSearchChips').Children | Where-Object { $_ -is [System.Windows.Controls.Primitives.ToggleButton] } | ForEach-Object { [string]$_.Content })
        $wfChipsGrupos = @($wfChips | Where-Object { $_ -ne 'Todos' } | Sort-Object)
        if (($wfChipsGrupos -join '|') -ne (($wfAppsCategorias | Sort-Object) -join '|')) { Write-Host "  [ERRO] chips da aba Instalar: '$($wfChipsGrupos -join ', ')' não bate com os grupos '$($wfAppsCategorias -join ', ')'" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Chips da aba Instalar: $($wfChips.Count) (Todos + $($wfChipsGrupos.Count) grupos)" }
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
        # Grupos fechados na montagem: a trava é sobre os controles, não sobre a chamada. Cada
        # grupo é um StackPanel com o rótulo em Children[0] e o WrapPanel dos aplicativos em
        # Children[1] - fechado quer dizer WrapPanel Collapsed e rótulo começando com "+ ".
        try {
            $wfGrupos = @($sync.ItemsControl.Items | Where-Object { $_ -is [System.Windows.Controls.StackPanel] -and $_.Children.Count -ge 2 })
            $wfAbertos = @($wfGrupos | Where-Object { $_.Children[1].Visibility -ne [Windows.Visibility]::Collapsed -or [string]$_.Children[0].Content -notlike '+ *' })
            if ($wfGrupos.Count -lt 5) { Write-Host "  [ERRO] aba Instalar: esperado ao menos 5 grupos montados, veio $($wfGrupos.Count)" -ForegroundColor Red; $wbErrors++ }
            if ($wfAbertos.Count) { Write-Host "  [ERRO] aba Instalar: $($wfAbertos.Count) grupo(s) abertos na montagem: $(@($wfAbertos | ForEach-Object { $_.Children[0].Content }) -join ', ')" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Aba Instalar: $($wfGrupos.Count) grupo(s) fechados na montagem" }
        } catch {
            Write-Host "  [ERRO] aba Instalar (grupos fechados): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
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
        # Aba Config: os botões de reparo têm de existir DEPOIS de a aba ser montada de verdade. A
        # trava é sobre o controle na janela, não sobre a config: uma entrada com categoria ou painel
        # errado continuaria na config e nunca apareceria na tela.
        try {
            $wfRepChaves = @($wfRepNomes | ForEach-Object { "WPFWFRep$_" })
            $wfRepFaltando = @($wfRepChaves | Where-Object { $sync[$_] -isnot [System.Windows.Controls.Button] })
            if ($wfRepFaltando.Count) { Write-Host "  [ERRO] aba Config (reparo): botão(ões) ausentes: $($wfRepFaltando -join ', ')" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Aba Config (reparo): $($wfRepChaves.Count) botão(ões) na tela" }
        } catch {
            Write-Host "  [ERRO] aba Config (reparo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
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

# A barra de navegação inteira vem do WinForge: são oito botões em ordem própria (Diagnóstico
# primeiro, Instalar perto do fim) com rótulos em pt-BR, e emendar isso com inserções pontuais na
# barra da base só produziria a ordem original com remendos. O NavLogoPanel continua dentro do
# StackPanel, no mesmo lugar - é ali que o logo é desenhado em tempo de execução.
$src = Replace-Between $src '            <!-- Navigation Buttons Panel -->' '            <!-- Search Bar and Action Buttons -->' ($xamlNav.TrimEnd() + "`n`n") "nav panel"

# ---------------------------------------------------------------- aba de abertura: Diagnóstico
# A primeira tela do WinForge é o diagnóstico da máquina, não a lista de aplicativos: é ele que diz
# o que este PC precisa, e as recomendações das outras abas saem daí.
$src = Replace-Once $src '$sync.currentTab = "Install"' '$sync.currentTab = "Diagnostico"' "default tab variable"
$src = Replace-Once $src '        Invoke-WPFTab "WPFTab1BT"  # Default to install tab' '        Invoke-WPFTab "WPFTab8BT"  # WinForge: abre no Diagnóstico' "default tab online"
# Sem internet a base desviava para Ajustes "em vez da aba Instalar". Agora a aba de abertura é o
# Diagnóstico, que funciona offline: o desvio perdeu o motivo e viraria uma aba diferente só porque
# a máquina está sem rede.
$src = Replace-Once $src '        Invoke-WPFTab "WPFTab2BT"  # Switch to Tweaks tab instead' '        Invoke-WPFTab "WPFTab8BT"  # WinForge: abre no Diagnóstico (funciona offline)' "default tab offline"

# ---------------------------------------------------------------- filtros da aba Instalar
# Os chips filtram comparando o texto da Tag com a categoria do aplicativo. Como a curadoria
# (wf-apps.ps1) reescreve as categorias em pt-BR, um chip com Tag em inglês passa a não casar com
# nada - por isso rótulo e Tag mudam juntos. O chip "Selfhosted Tools" some: aquele grupo foi
# absorvido por Utilitários e o filtro ficaria vazio para sempre.
$src = Replace-Once $src @'
                        <ToggleButton Name="WPFSearchChipAll"             Content="All"               Style="{StaticResource FilterChipToggleStyle}" IsChecked="True"/>
                        <ToggleButton Name="WPFSearchChipBrowsers"        Content="Browsers"          Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipCommunications"  Content="Communications"    Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipDevelopment"     Content="Development"       Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipDocument"        Content="Document"          Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipGames"           Content="Games"             Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipMicrosoftTools"  Content="Microsoft Tools"   Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipMultimediaTools" Content="Multimedia Tools"  Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipProTools"        Content="Pro Tools"         Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipSelfhostedTools" Content="Selfhosted Tools"  Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipUtilities"       Content="Utilities"         Style="{StaticResource FilterChipToggleStyle}"/>
'@ @'
                        <ToggleButton Name="WPFSearchChipAll"             Content="Todos"                     Style="{StaticResource FilterChipToggleStyle}" IsChecked="True"/>
                        <ToggleButton Name="WPFSearchChipBrowsers"        Content="Navegadores"               Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipCommunications"  Content="Comunicação"               Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipDevelopment"     Content="Desenvolvimento"           Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipDocument"        Content="Documentos"                Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipGames"           Content="Jogos"                     Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipMicrosoftTools"  Content="Ferramentas Microsoft"     Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipMultimediaTools" Content="Multimídia"                Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipProTools"        Content="Ferramentas profissionais" Style="{StaticResource FilterChipToggleStyle}"/>
                        <ToggleButton Name="WPFSearchChipUtilities"       Content="Utilitários"               Style="{StaticResource FilterChipToggleStyle}"/>
'@ "xaml chips pt-BR"

$src = Replace-Once $src 'ToolTip="Filter by category. Ctrl click to select more than one."' 'ToolTip="Filtra por grupo. Ctrl+clique para escolher mais de um."' "xaml chips tooltip"

$src = Replace-Once $src @'
    @{ Name = "WPFSearchChipBrowsers";        Category = "Browsers" }
    @{ Name = "WPFSearchChipCommunications";  Category = "Communications" }
    @{ Name = "WPFSearchChipDevelopment";     Category = "Development" }
    @{ Name = "WPFSearchChipDocument";        Category = "Document" }
    @{ Name = "WPFSearchChipGames";           Category = "Games" }
    @{ Name = "WPFSearchChipMicrosoftTools";  Category = "Microsoft Tools" }
    @{ Name = "WPFSearchChipMultimediaTools"; Category = "Multimedia Tools" }
    @{ Name = "WPFSearchChipProTools";        Category = "Pro Tools" }
    @{ Name = "WPFSearchChipSelfhostedTools"; Category = "Selfhosted Tools" }
    @{ Name = "WPFSearchChipUtilities";       Category = "Utilities" }
'@ @'
    @{ Name = "WPFSearchChipBrowsers";        Category = "Navegadores" }
    @{ Name = "WPFSearchChipCommunications";  Category = "Comunicação" }
    @{ Name = "WPFSearchChipDevelopment";     Category = "Desenvolvimento" }
    @{ Name = "WPFSearchChipDocument";        Category = "Documentos" }
    @{ Name = "WPFSearchChipGames";           Category = "Jogos" }
    @{ Name = "WPFSearchChipMicrosoftTools";  Category = "Ferramentas Microsoft" }
    @{ Name = "WPFSearchChipMultimediaTools"; Category = "Multimídia" }
    @{ Name = "WPFSearchChipProTools";        Category = "Ferramentas profissionais" }
    @{ Name = "WPFSearchChipUtilities";       Category = "Utilitários" }
'@ "chips pt-BR"

$src = Replace-Once $src "`$sync[`"WPFSearchChipSelfhostedTools`"].Add_Click({ Invoke-WinUtilAppCategoryChip -Chip `$this })`n" '' "chip selfhosted click"

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

                                    <Button Name="WPFPresetWinForge" Content=" WinForge " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}" ToolTip="Preset Padrão + serviços seguros, anúncios, Cortana, pesquisa, NTFS, energia e hibernação (WinForge)."/>
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

# ---------------------------------------------------------------- tradução da interface (pt-BR)
# ÚLTIMA transformação, depois das injeções, da limpeza de marca e do rename global. O plano pedia
# esta etapa antes da limpeza/rename; ficou depois por dois motivos concretos:
#   1. o rename troca WinUtil por WinForge dentro de textos que estão nesta lista ("Change the
#      WinUtil UI Theme", "settings managed by WinUtil"). Antes dele, cada par teria de usar a
#      grafia antiga - divergindo do que o arquivo gerado mostra e do que o inventário imprime.
#   2. a limpeza de marca reescreve um Write-Host inteiro ("Successfully uninstalled CTT PowerShell
#      Profile."). Traduzir primeiro apagaria aquela âncora e o build quebraria ali.
# Rodando por último, o lado esquerdo de cada par é exatamente o texto do arquivo gerado - o mesmo
# que tools\List-EnglishStrings.ps1 lista - e nenhuma âncora anterior corre risco. A proteção contra
# mudança do arquivo base continua igual: Replace-Once falha se o texto sumir ou ficar ambíguo, e
# Replace-All falha se não achar nada.
$wfI18nOnce = 0
foreach ($pair in $WinForgeI18nStrings) {
    $src = Replace-Once $src $pair[0] $pair[1] "i18n: $($pair[0])"
    $wfI18nOnce++
}
$wfI18nHits = 0
foreach ($pair in $WinForgeI18nRepeated) {
    $src = Replace-All $src $pair[0] $pair[1] "i18n (repetido): $($pair[0])"
}
Write-Host "Tradução: $wfI18nOnce texto(s) único(s) + $($WinForgeI18nRepeated.Count) repetido(s) em $wfI18nHits ocorrência(s)"

# Trava de idioma do -SelfTest: a lista de termos é injetada AQUI, depois do laço, senão o próprio
# laço traduziria a lista (e a trava passaria por não ter mais o que procurar).
$wfEnglishSweep = @(
    'Recommended Selections', 'Run Tweaks', 'Undo Selected', 'Install/Upgrade', 'Uninstall Applications',
    'Upgrade all', 'Clear Selection', 'Collapse All', 'Expand All', 'Selected Apps', 'Show Installed',
    'Get Installed', 'Windows Update Profiles', 'Apply Recommended', 'Restore Defaults', 'Disable Updates',
    'Status Log', 'Browse', 'Open Microsoft Download', 'Legacy Windows Panels', 'Essential Tweaks',
    'Customize Preferences', 'Advanced Tweaks', 'Performance Plans', 'Remote Access', 'Install Features',
    'Package Manager', 'Free and Open Source', 'No ISO selected', 'Select Windows 11 ISO'
) + @(' - Disable', ' - Enable', ' - Remove', ' - Run', ' - Reset', ' - Create', ' - Reinstall')
$wfSweepLiteral = "    `$sync.WinForgeEnglishSweep = @(" + (($wfEnglishSweep | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ', ') + ")`n"
$src = Insert-After $src "    `$sync.SelfTest = `$true`n" $wfSweepLiteral "lista da trava de idioma"

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

# ---------------------------------------------------------------- travas de texto no motor gerado
# A aba de abertura é decidida em duas linhas soltas do arquivo, longe uma da outra. Replace-Once
# já falha se a âncora sumir, mas nada impediria uma substituição posterior de desfazer o resultado
# - por isso a conferência é sobre o texto final.
foreach ($wfEsperado in @('$sync.currentTab = "Diagnostico"', 'Invoke-WPFTab "WPFTab8BT"  # WinForge: abre no Diagnóstico')) {
    if ($final.IndexOf($wfEsperado, [StringComparison]::Ordinal) -lt 0) { throw "Motor gerado sem a aba de abertura no Diagnóstico: falta $wfEsperado" }
}
if ($final.IndexOf('Invoke-WPFTab "WPFTab1BT"', [StringComparison]::Ordinal) -ge 0) { throw "Motor gerado ainda abre na aba Instalar (Invoke-WPFTab `"WPFTab1BT`")" }
Write-Host "Aba de abertura: Diagnóstico"

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
