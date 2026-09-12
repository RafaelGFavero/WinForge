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

function Get-WinForgeStyleSection([string]$styles, [string]$name) {
    # Recorta um pedaço de xaml\wf-xaml-styles.xml. O arquivo é uma coleção de <Style>, não um XML
    # com raiz única: cada pedaço começa numa linha "@secao: <nome>" e vai até a próxima (ou até o
    # fim). Pedaço que não existe ESTOURA - é o que denuncia um nome trocado no build.
    $ini = "@secao: $name`n"
    $i = $styles.IndexOf($ini, [StringComparison]::Ordinal)
    if ($i -lt 0) { throw "estilos: seção '$name' não existe em wf-xaml-styles.xml" }
    if ($styles.IndexOf($ini, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "estilos: seção '$name' aparece mais de uma vez" }
    $i += $ini.Length
    $j = $styles.IndexOf("`n@secao: ", $i, [StringComparison]::Ordinal)
    if ($j -lt 0) { $j = $styles.Length }
    return $styles.Substring($i, $j - $i).Trim("`n")
}

function Set-WinForgeThemeTokens([string]$text, $tokens, $novos) {
    # Reescreve os VALORES do bloco de temas da base ($sync.configs.themes) token a token.
    #
    # Substituição por linha, e não por bloco inteiro: o bloco da base tem dezenas de tokens que o
    # WinForge não muda, e trocar o JSON inteiro faria o build engolir calado qualquer token novo
    # que a base passasse a usar. Aqui, token que sumiu ESTOURA (a base mudou de nome) e token novo
    # que já existe também ESTOURA (a base passou a ter o que o WinForge estava acrescentando).
    $blocoIni = "`$sync.configs.themes = @'`n"
    $s = $text.IndexOf($blocoIni, [StringComparison]::Ordinal)
    if ($s -lt 0) { throw "tema: bloco `$sync.configs.themes não encontrado" }
    if ($text.IndexOf($blocoIni, $s + 1, [StringComparison]::Ordinal) -ge 0) { throw "tema: bloco `$sync.configs.themes ambíguo" }
    $s += $blocoIni.Length
    $e = $text.IndexOf("`n'@ | ConvertFrom-Json", $s, [StringComparison]::Ordinal)
    if ($e -lt 0) { throw "tema: fim do bloco `$sync.configs.themes não encontrado" }

    $json = $text.Substring($s, $e - $s)
    $contagem = 0
    foreach ($secao in @('shared', 'Light', 'Dark')) {
        $secIni = "  `"$secao`": {`n"
        $i = $json.IndexOf($secIni, [StringComparison]::Ordinal)
        if ($i -lt 0) { throw "tema: seção '$secao' não encontrada no bloco de temas" }
        if ($json.IndexOf($secIni, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "tema: seção '$secao' ambígua" }
        $corpoIni = $i + $secIni.Length
        $j = $json.IndexOf("`n  }", $corpoIni, [StringComparison]::Ordinal)
        if ($j -lt 0) { throw "tema: fim da seção '$secao' não encontrado" }
        $corpo = $json.Substring($corpoIni, $j - $corpoIni)

        foreach ($nome in @($tokens[$secao].Keys)) {
            $marca = "    `"$nome`": `""
            $k = $corpo.IndexOf($marca, [StringComparison]::Ordinal)
            if ($k -lt 0) { throw "tema: token '$nome' não existe na seção '$secao' da base" }
            if ($corpo.IndexOf($marca, $k + 1, [StringComparison]::Ordinal) -ge 0) { throw "tema: token '$nome' aparece mais de uma vez na seção '$secao'" }
            $vIni = $k + $marca.Length
            $vFim = $corpo.IndexOf('"', $vIni)
            if ($vFim -lt 0) { throw "tema: valor de '$nome' na seção '$secao' sem aspas de fechamento" }
            $corpo = $corpo.Substring(0, $vIni) + $tokens[$secao][$nome] + $corpo.Substring($vFim)
            $contagem++
        }

        if ($novos -and $novos[$secao]) {
            foreach ($nome in @($novos[$secao].Keys)) {
                if ($corpo.IndexOf("    `"$nome`": ", [StringComparison]::Ordinal) -ge 0) { throw "tema: token novo '$nome' já existe na seção '$secao' da base" }
                $corpo = $corpo.TrimEnd() + ",`n    `"$nome`": `"$($novos[$secao][$nome])`""
                $contagem++
            }
        }

        $json = $json.Substring(0, $corpoIni) + $corpo + $json.Substring($j)
    }
    Write-Host "Tema: $contagem token(s) aplicado(s) em shared/Light/Dark"
    return $text.Substring(0, $s) + $json + $text.Substring($e)
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
$appliedBlock   = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-applied.ps1")
$themeFuncs     = Read-Lf (Join-Path $PSScriptRoot "winforge\wf-theme-functions.ps1")
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
$xamlStyles     = Read-Lf (Join-Path $PSScriptRoot "xaml\wf-xaml-styles.xml")
$appsData       = Read-Lf (Join-Path $PSScriptRoot "config\wf-apps.ps1")
$i18nConfigs    = Read-Lf (Join-Path $PSScriptRoot "config\wf-i18n-configs.ps1")

# Dicionário de tradução: é código, não bloco injetado, então tem de ser EXECUTADO. Dot-source do
# arquivo não serve (o PowerShell 5.1 lê .ps1 pela code page ANSI quando não há BOM); ler o texto em
# UTF-8 e rodar um scriptblock mantém os acentos independentemente do BOM.
. ([scriptblock]::Create([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "config\wf-i18n-strings.ps1"), [System.Text.Encoding]::UTF8)))

# Tabela de tokens do sistema visual: também é código, e pelo mesmo motivo (BOM/code page) entra
# por scriptblock em vez de dot-source do arquivo.
. ([scriptblock]::Create([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "config\wf-theme.ps1"), [System.Text.Encoding]::UTF8)))

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
$src = Insert-Before $src "`$inputXML = @'" ($i18nConfigs.TrimEnd() + "`n`n") "insert i18n configs"

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

# ---------------------------------------------------------------- estado já aplicado (detecção, marca na linha, pular na aplicação)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($appliedBlock.TrimEnd() + "`n`n") "insert applied"

# ---------------------------------------------------------------- sistema visual (contraste dos tokens)
$src = Insert-Before $src "#region ===== WinForge - logo =====" ($themeFuncs.TrimEnd() + "`n`n") "insert theme functions"

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
    # WinForge: marca " · aplicado" nas linhas cuja chave já está aplicada (depois da dica de
    # recomendação, porque o prefixo dela entra na frente do que a outra escreveu)
    Update-WinForgeAppliedVisuals | Out-Null
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
    $wfCorrecoes = @("WPFFixesNetwork", "WPFFixesNTPPool", "WPFPanelDISM", "WPFFixesUpdate", "WPFFixesWinget")
    if ($sync.configs.feature.$Button -and $Button -notlike "WPFWFRep*" -and $Button -notin $wfCorrecoes) {
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
    #
    # As cinco chaves de $wfCorrecoes vieram da BASE e saem daqui pelo mesmo motivo, com um a mais:
    # a função da base que elas apontavam rodava nesta thread - a da janela - e escrevia num console
    # que o lançador esconde. Um sfc ou um DISM congelava a aba inteira e não mostrava nada. Agora
    # elas caem em Invoke-WinForgeRepairCommand, que pergunta antes e roda em runspace com a saída
    # ao vivo numa janela. A chave 'function' delas também some, em Initialize-WinUtilBoostConfigs.
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
        "WPFWFRepAclVerify" {Invoke-WinForgeRepairCommand -Name AclVerify}
        "WPFWFRepAclRestore" {Invoke-WinForgeRepairCommand -Name AclRestore}
        "WPFWFRepAclUndo" {Invoke-WinForgeRepairCommand -Name AclUndo}
        "WPFWFRepAclCleanup" {Invoke-WinForgeRepairCommand -Name AclCleanup}
        # Correções (aba Config, vindas da base): mesma tabela e mesma máquina do reparo, com a
        # janela que se enche ao vivo. Antes cada uma destas chaves chamava a função da base pelo
        # campo "function" da config, na thread da janela.
        "WPFFixesNetwork" {Invoke-WinForgeRepairCommand -Name NetworkReset}
        "WPFFixesNTPPool" {Invoke-WinForgeRepairCommand -Name NtpPool}
        "WPFPanelDISM" {Invoke-WinForgeRepairCommand -Name SystemRepair}
        "WPFFixesUpdate" {Invoke-WinForgeRepairCommand -Name WindowsUpdateReset}
        "WPFFixesWinget" {Invoke-WinForgeRepairCommand -Name WingetReinstall}
        "WPFDiagRefresh" {Start-WinForgeProfileJob}
        "WPFDiagWUDrivers" {Invoke-WinForgeDriverUpdateSearch}
        "WPFDiagExport" {
            $wfRelatorio = Export-WinForgeDiagnosticsReport
            if (-not $wfRelatorio) { [System.Windows.MessageBox]::Show("O diagnóstico ainda não terminou. Tente de novo em alguns segundos.", "WinForge", "OK", "Warning") | Out-Null }
        }
        # Marcar/desmarcar tudo pela lista do Diagnóstico. Sem caixa de mensagem: quem conta o
        # resultado é o contador ao lado dos botões, e ele fica na tela depois do clique.
        "WPFDiagSelectRecommended" {Set-WinForgeDiagRecommendationSelection -Checked $true | Out-Null}
        "WPFDiagClearRecommended" {Set-WinForgeDiagRecommendationSelection -Checked $false | Out-Null}
        # Aplicar/desfazer sem sair do Diagnóstico. NÃO existe caminho de aplicação próprio daqui:
        # marcar a linha já marcou a caixa de verdade na aba de destino, e é ela que alimenta
        # $sync.selectedTweaks - a mesma variável que estes dois lêem. Então o botão daqui é o
        # botão da aba Ajustes, com a trava de $sync.ProcessRunning e o runspace da base.
        "WPFDiagApplySelected" {Invoke-WPFtweaksbutton}
        "WPFDiagUndoSelected" {Invoke-WPFundoall}
'@.TrimEnd() "button switch"

# ---------------------------------------------------------------- ícone da barra de tarefas: volta para a thread da janela
# taskbarItemInfo é objeto da JANELA, e escrever nele de outra thread morre com "o thread chamador
# não pode acessar este objeto porque um thread diferente é o proprietário". Na base isso nunca
# aparecia: as funções que chamam Set-WinUtilTaskbaritem sem passar pelo Dispatcher (Invoke-WPFFixesUpdate,
# Invoke-WPFFixesWinget, Invoke-WPFSystemRepair) rodavam NA thread da janela - que é justamente o
# congelamento que o WinForge está desfazendo. Agora duas delas são passos de um comando em runspace,
# e a segunda linha de Invoke-WPFFixesUpdate morreria antes de qualquer saída.
#
# O desvio fica na PRÓPRIA função, e não em quem chama: assim vale para qualquer caminho novo, da
# base ou do WinForge, sem depender de quem o escreveu ter lembrado do Dispatcher. Chamada que já
# vem da thread da janela (o caso de sempre, inclusive o do próprio callback) passa direto.
#
# E antes de tudo isso, a guarda de fechamento. Com a janela fechando o ícone da barra de tarefas
# está indo embora junto com ela, então escrever nele não vale nada - e da runspace vale menos que
# nada: o salto para o Dispatcher entraria numa fila que a thread da janela, já dentro do
# Add_Closing, não vai mais processar. Fica na PRIMEIRA linha, antes até do teste de thread, porque
# durante o fechamento nenhuma das duas pontas tem o que fazer aqui. A mesma recusa que
# Set-WinForgeDiagProgress já faz, pelo mesmo motivo.
$src = Replace-Once $src @'
        [string]$description
    )

    if ($value) {
        $sync["Form"].taskbarItemInfo.ProgressValue = $value
    }
'@ @'
        [string]$description
    )

    # WinForge: janela fechando - ninguém escreve mais no ícone (ver wf-commands.ps1).
    if ($sync.WinForgeClosing) {
        $sync.WinForgeTaskbarSkipped = $true
        return
    }

    # WinForge: de outra thread, o trabalho é remarcado para a thread da janela (ver wf-commands.ps1).
    # Um pacote POR CHAMADA, com chave própria, e não um slot compartilhado: duas chamadas
    # entrelaçadas perderiam uma atualização.
    if ($null -ne $sync.Form -and $null -ne $sync.Form.Dispatcher -and -not $sync.Form.Dispatcher.CheckAccess()) {
        $wfTbChaveNova = [guid]::NewGuid().ToString('N')
        $sync.WinForgeTaskbarArgs[$wfTbChaveNova] = @{ state = $state; value = $value; overlay = $overlay; description = $description }
        $sync.WinForgeTaskbarQueue.Enqueue($wfTbChaveNova)
        try {
            Invoke-WPFUIThread $sync.WinForgeTaskbarCallback
        } finally {
            # O callback pode não ter rodado (Dispatcher desligando, exceção no meio): o pacote não
            # pode ficar para trás esperando o callback da PRÓXIMA chamada encontrá-lo.
            if ($sync.WinForgeTaskbarArgs.ContainsKey($wfTbChaveNova)) {
                [void]$sync.WinForgeTaskbarArgs.Remove($wfTbChaveNova)
                try { if ($sync.WinForgeTaskbarQueue.Count -gt 0 -and [string]$sync.WinForgeTaskbarQueue.Peek() -eq $wfTbChaveNova) { [void]$sync.WinForgeTaskbarQueue.Dequeue() } } catch { }
            }
        }
        return
    }

    if ($value) {
        $sync["Form"].taskbarItemInfo.ProgressValue = $value
    }
'@ "taskbar cross-thread"

# ---------------------------------------------------------------- Windows Update - Redefinir: sem caixa em inglês
# A base termina a redefinição com uma MessageBox em inglês. Rodando em runspace, ela apareceria
# numa thread que não é a da janela - modal, sem dono, e segurando a trava de comando em andamento
# até alguém achá-la e fechá-la. O aviso de reinicialização já está na frase final do comando e na
# própria pergunta de confirmação; aqui ele vira uma linha da saída, que é onde a pessoa está olhando.
$src = Replace-Once $src @'
    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "Reset Windows Update "
    $Messageboxbody = ("Stock settings loaded.`n Please reboot your computer")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
'@ @'
    Write-Host "Configurações do Windows Update restauradas para o padrão. Reinicie o computador."
'@ "reset WU sem MessageBox"

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

# ---------------------------------------------------------------- "Detectar aplicados" alimenta o conjunto de aplicados
# O botão continua marcando as caixas como sempre; o que muda é que o resultado dele passa a ser a
# mesma verdade que a marca " · aplicado" e o filtro do botão Aplicar usam. Sem isto, detectar na
# mão deixaria as duas visões discordando até o próximo diagnóstico.
$src = Replace-Once $src @'
                foreach ($checkboxName in $completedOperation.Checkboxes) {
                    if ($sync.$checkboxName) { $sync.$checkboxName.ischecked = $True }
                }
            }
'@ @'
                foreach ($checkboxName in $completedOperation.Checkboxes) {
                    if ($sync.$checkboxName) { $sync.$checkboxName.ischecked = $True }
                }
                # Este bloco é um [Action] que o Dispatcher executa, e o caminho da base é
                # try/finally SEM catch: exceção aqui não tem para onde subir - ela sai pelo
                # BeginInvoke, longe de quem pudesse tratá-la, e leva junto o `finally` que
                # destrava $sync.ProcessRunning. O conjunto e as marcas são informação: não valem
                # o risco de derrubar o botão.
                try {
                    $null = Set-WinForgeAppliedTweaks -Keys @($completedOperation.Checkboxes)
                    Update-WinForgeAppliedVisuals | Out-Null
                } catch { Write-WinForgeLog -Component "Applied" -Level "WARN" -Message "Detectar aplicados: o conjunto e as marcas não puderam ser atualizados -> $($_.Exception.Message)" }
            }
'@ "detectar aplicados: guarda o conjunto"

# ---------------------------------------------------------------- não reaplicar o que já está aplicado
# A queixa era direta: marcar de novo uma chave que já está ativa fazia o WinForge reaplicá-la.
# A detecção é REFEITA na hora, e não lida do diagnóstico da abertura: entre abrir a janela e
# clicar em Aplicar o usuário pode ter desfeito alguma coisa, e pular um tweak que deixou de estar
# aplicado seria pior que reaplicar um que ainda está.
#
# Ela roda DENTRO do corpo do runspace, e não no clique. São ~80 entradas lidas do registro e dos
# serviços: na thread da janela isso é a interface parada, e nem o rótulo da barra aparece, porque
# quem pinta é o Dispatcher e o Dispatcher está parado dentro do próprio handler do clique (o mesmo
# laço descrito em Invoke-WinForgeDriverAction). Aqui o clique só despacha, e a primeira coisa que
# o corpo faz é dizer na barra o que está fazendo.
#
# O filtro entra ANTES do laço que aplica, e desconta os pulados do total: com o total original a
# barra pararia em "8/12" e pareceria travada.
$src = Insert-After $src @'
  Invoke-WPFRunspace -ParameterList @(("tweaks", $tweaksToRun), ("dnsProvider", $dnsProvider), ("completedSteps", $completedSteps), ("totalSteps", $totalSteps)) -ScriptBlock {
    param($tweaks, $dnsProvider, $completedSteps, $totalSteps)

    $sync.ProcessRunning = $true
'@ @'

    Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Conferindo o que já está aplicado..." -Percent 0
    $wfSel = Select-WinForgeTweaksToApply -Keys @($tweaks)
    $wfPulados = @($wfSel.Skipped)
    $tweaks = @($wfSel.Apply)
    $sync.WinForgeTweaksSkipped = $wfPulados.Count
    $totalSteps = [Math]::Max($totalSteps - $wfPulados.Count, 1)
    if ($wfPulados.Count -gt 0) {
      foreach ($wfPulado in $wfPulados) { Write-WinUtilLog -Component "Tweaks" -Message "Ajuste '$wfPulado' pulado: já está aplicado neste sistema." }
      Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Pulado(s) por já estarem aplicados: $($wfPulados.Count)" -Percent 0
    }
    # A detecção acabou de reescrever $sync.AppliedTweaks: quem repinta as marcas das linhas e o
    # contador do checklist é a thread da janela, com o bloco nascido na runspace principal.
    if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeAppliedResyncCallback }
'@.TrimEnd() "tweaks: pular aplicados"

# O bloco que o Dispatcher vai executar NASCE aqui, na runspace principal (esta função roda no
# clique): feito dentro do corpo do runspace, ele pertenceria à runspace do pool e travaria no
# primeiro pipeline - o mesmo laço descrito em Start-WinForgeProfileJob.
$src = Insert-After $src @'
  $Tweaks = $sync.selectedTweaks
'@ @'

  $sync.WinForgeTweaksSkipped = 0
  $sync.WinForgeAppliedResyncCallback = { Update-WinForgeAppliedAfterApply | Out-Null }
'@.TrimEnd() "tweaks: callback de repintura"

# Linha final da barra: com alguma coisa pulada, o "Ajustes concluídos" sozinho esconderia
# justamente o que mudou. A linha da base fica inteira (é ela que a tradução reconhece) e o resumo
# passa por cima logo depois. O contador dos pulados atravessa em $sync porque o corpo abaixo roda
# noutra runspace, que não enxerga as variáveis desta função.
#
# Antes da linha final vem a SEGUNDA repintura. A primeira, lá em cima, mostra o que a detecção do
# clique achou - a verdade de ANTES de aplicar. Sem esta, tudo o que o laço acabou de aplicar
# ficaria sem a marca " · aplicado" e fora do contador até o próximo diagnóstico: a tela mentindo
# no instante exato em que o usuário olha para ela para ver se funcionou. A detecção é refeita
# (Update-WinForgeAppliedFromSystem) porque repintar o conjunto velho não mudaria nada.
$src = Replace-Once $src @'
    Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Tweaks finished" -Percent 100
    $sync.ProcessRunning = $false
'@ @'
    $null = Update-WinForgeAppliedFromSystem
    if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeAppliedResyncCallback }
    Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Tweaks finished" -Percent 100
    if ([int]$sync.WinForgeTweaksSkipped -gt 0) {
      Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Aplicados: $completedSteps · já estavam aplicados: $([int]$sync.WinForgeTweaksSkipped)" -Percent 100
    }
    $sync.ProcessRunning = $false
'@ "tweaks: resumo final com pulados"

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
    # Pasta temporária com o nome LONGO: no runner do CI $env:TEMP vem na forma 8.3
    # (C:\Users\RUNNER~1\...), e as funções devolvem caminhos longos (GetFullPath/Get-Item).
    # Comparar os dois como texto falhava só lá. Get-Item resolve o nome curto para o longo.
    $wbSelfTestTemp = try { (Get-Item -LiteralPath ([System.IO.Path]::GetTempPath().TrimEnd('\'))).FullName } catch { $env:TEMP }
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
    if (@($sync.configs.feature.PSObject.Properties).Count -ne 58) { Write-Host "  [ERRO] Config: esperado 58 entradas" -ForegroundColor Red; $wbErrors++ }
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
    # ---- Sistema visual: tokens, tipografia e contraste
    # A fonte é o MESMO bloco que a janela lê ($sync.configs.themes), e não uma cópia da tabela:
    # assim a trava cobre o que a interface vai pintar de verdade. Trocar um hexadecimal é a
    # mudança mais fácil de fazer no projeto e a mais difícil de enxergar sem abrir o programa.
    # Toda cor de TEXTO contra toda superfície onde esse texto pode cair: fundo da janela, cartão
    # e dica. É produto cartesiano de propósito - a lista escrita à mão sempre esquece a
    # combinação que aparece numa aba só, e foi assim que o verde de "recomendado" ficou em 3,6:1
    # sobre o fundo escuro sem ninguém notar.
    $wfTemaFundos = @('MainBackgroundColor', 'CardBackgroundColor', 'ToolTipBackgroundColor')
    $wfTemaTextos = @('MainForegroundColor', 'LabelboxForegroundColor', 'RecommendedColor', 'DiscouragedColor', 'DangerColor')
    $wfTemaPares = @()
    foreach ($wfBgNome in $wfTemaFundos) {
        foreach ($wfFgNome in $wfTemaTextos) { $wfTemaPares += @{ Fg = $wfFgNome; Bg = $wfBgNome; Nome = "$wfFgNome sobre $wfBgNome" } }
    }
    $wfTemaPares += @{ Fg = 'ButtonForegroundColor';         Bg = 'ButtonBackgroundColor';          Nome = 'texto do botão' }
    $wfTemaPares += @{ Fg = 'ButtonForegroundColor';         Bg = 'ButtonBackgroundMouseoverColor'; Nome = 'texto do botão sob o mouse' }
    $wfTemaPares += @{ Fg = 'ButtonForegroundColor';         Bg = 'ButtonBackgroundPressedColor';   Nome = 'texto do botão pressionado' }
    $wfTemaPares += @{ Fg = 'ButtonForegroundSelectedColor'; Bg = 'ButtonBackgroundSelectedColor';  Nome = 'texto do botão selecionado' }
    $wfTemaPares += @{ Fg = 'MainForegroundColor';           Bg = 'AppInstallUnselectedColor';      Nome = 'nome do aplicativo' }
    $wfTemaPares += @{ Fg = 'MainForegroundColor';           Bg = 'AppInstallSelectedColor';        Nome = 'nome do aplicativo marcado' }
    # Linha instalada e linha que falhou na tabela do Windows Update: o texto da célula é o
    # MainForegroundColor do estilo da linha, e é ele que tem de sobreviver ao fundo colorido.
    $wfTemaPares += @{ Fg = 'MainForegroundColor';           Bg = 'RowSuccessBackgroundColor';      Nome = 'linha instalada' }
    $wfTemaPares += @{ Fg = 'MainForegroundColor';           Bg = 'RowFailureBackgroundColor';      Nome = 'linha que falhou' }
    foreach ($wfTemaNome in @('Dark', 'Light')) {
        $wfTemaSec = $sync.configs.themes.$wfTemaNome
        if ($null -eq $wfTemaSec) { Write-Host "  [ERRO] tema: seção '$wfTemaNome' não existe no bloco de temas" -ForegroundColor Red; $wbErrors++; continue }
        $wfPiorNome = ''; $wfPiorRazao = 99
        foreach ($wfPar in $wfTemaPares) {
            $wfFg = [string]$wfTemaSec.($wfPar.Fg)
            $wfBg = [string]$wfTemaSec.($wfPar.Bg)
            if (-not $wfFg -or -not $wfBg) {
                Write-Host "  [ERRO] tema $wfTemaNome ($($wfPar.Nome)): token ausente ($($wfPar.Fg)='$wfFg', $($wfPar.Bg)='$wfBg')" -ForegroundColor Red; $wbErrors++; continue
            }
            $wfRazao = Get-WinForgeContrastRatio -Fg $wfFg -Bg $wfBg
            if ($wfRazao -lt $wfPiorRazao) { $wfPiorRazao = $wfRazao; $wfPiorNome = $wfPar.Nome }
            if ($wfRazao -lt 4.5) {
                Write-Host "  [ERRO] contraste $wfTemaNome ($($wfPar.Nome)): $wfFg sobre $wfBg dá ${wfRazao}:1, mínimo 4,5:1" -ForegroundColor Red; $wbErrors++
            }
        }
        Write-Host "  Contraste $wfTemaNome : $($wfTemaPares.Count) par(es) conferido(s), pior caso ${wfPiorRazao}:1 ($wfPiorNome), mínimo 4,5:1"
    }
    # Tipografia: Segoe UI no corpo, Segoe UI Semibold nos títulos. O Consolas da base era a fonte
    # dos títulos de categoria; a única monoespaçada que sobra é a da janela de saída de comandos.
    $wfTipografia = [ordered]@{
        FontFamily                 = 'Segoe UI'
        ButtonFontFamily           = 'Segoe UI'
        HeaderFontFamily           = 'Segoe UI Semibold'
        FontSize                   = '13'
        HeaderFontSize             = '15'
        ButtonHeight               = '32'
        TabButtonWidth             = '118'
        TabButtonHeight            = '32'
        CheckBoxBulletDecoratorSize = '16'
        ButtonCornerRadius         = '4'
    }
    foreach ($wfTipoChave in @($wfTipografia.Keys)) {
        $wfTipoValor = [string]$sync.configs.themes.shared.$wfTipoChave
        if ($wfTipoValor -ne $wfTipografia[$wfTipoChave]) {
            Write-Host "  [ERRO] token compartilhado '$wfTipoChave': esperado '$($wfTipografia[$wfTipoChave])', veio '$wfTipoValor'" -ForegroundColor Red; $wbErrors++
        }
    }
    if ($inputXML -match 'Consolas') { Write-Host "  [ERRO] tipografia: sobrou 'Consolas' no XAML - a única monoespaçada do WinForge é a da janela de saída" -ForegroundColor Red; $wbErrors++ }
    if ($inputXML -match 'Arial')    { Write-Host "  [ERRO] tipografia: sobrou 'Arial' no XAML" -ForegroundColor Red; $wbErrors++ }
    $wfMonoDef = [string](Get-Command Show-WinForgeOutputWindow).Definition
    if ($wfMonoDef -notmatch "FontFamily 'Consolas'") { Write-Host "  [ERRO] tipografia: a janela de saída de comandos perdeu a fonte monoespaçada (Consolas)" -ForegroundColor Red; $wbErrors++ }
    # Estilos: um dicionário de recursos não aceita duas entradas com a mesma chave (nem dois
    # estilos implícitos para o mesmo TargetType). Um estilo do WinForge ADICIONADO em vez de
    # SUBSTITUIR o da base estouraria só na hora de carregar o XAML - aqui a contagem denuncia.
    $wfEstilosUnicos = [ordered]@{
        'x:Key="TabToggleButton"'    = 1
        '<Style TargetType="Button">' = 1
        '<Style TargetType="CheckBox">' = 1
        'x:Key="BorderStyle"'        = 1
        '<Style TargetType="DataGridRow">' = 1
        'x:Key="WFWindowsUpdateRow"' = 1
    }
    foreach ($wfEstiloChave in @($wfEstilosUnicos.Keys)) {
        $wfEstiloQtd = ([regex]::Matches($inputXML, [regex]::Escape($wfEstiloChave))).Count
        if ($wfEstiloQtd -ne $wfEstilosUnicos[$wfEstiloChave]) {
            Write-Host "  [ERRO] estilos: '$wfEstiloChave' aparece $wfEstiloQtd vez(es) no XAML, esperado $($wfEstilosUnicos[$wfEstiloChave])" -ForegroundColor Red; $wbErrors++
        }
    }
    foreach ($wfEstiloMarca in @('Name="WFHoverOverlay"', 'Name="WFSelectedAccent"', 'Name="WFFocusRing"')) {
        if ($inputXML.IndexOf($wfEstiloMarca, [StringComparison]::Ordinal) -lt 0) {
            Write-Host "  [ERRO] estilos: falta '$wfEstiloMarca' nos gabaritos de botão/aba" -ForegroundColor Red; $wbErrors++
        }
    }
    Write-Host "  Estilos: gabaritos únicos de Button/CheckBox/TabToggleButton/BorderStyle/DataGridRow, com realce, foco e faixa de aba"
    # Trava de idioma. A lista de termos é injetada pelo build logo acima ($sync.WinForgeEnglishSweep),
    # DEPOIS do dicionário de tradução - se ela viesse antes, o próprio dicionário a traduziria e a
    # trava passaria por não ter mais o que procurar. Aqui a varredura é sobre o XAML gerado; a
    # Tarefa 3 usa a mesma função no Content/Description das configurações.
    $wfIdiomaXaml = Test-WinForgeEnglishLeftovers -Text $inputXML -Where 'XAML' -Xaml
    if ($wfIdiomaXaml) { $wbErrors += $wfIdiomaXaml }
    else { Write-Host "  Idioma: $(@($sync.WinForgeEnglishSweep).Count) termo(s) em inglês procurados no XAML, nenhum encontrado" }
    # Cobertura do dicionário por chave (config\wf-i18n-configs.ps1). O texto dos três blocos JSON
    # não dá para traduzir por substituição literal como o resto - são centenas de frases parecidas -
    # então a tradução é por chave, e a prova de que nenhuma ficou de fora é esta.
    # As entradas do próprio WinForge já nascem em português: ficam fora POR PREFIXO, e não por
    # "parece português", que daria falso verde em qualquer texto curto.
    $wfI18nPrefixos = @('WPFTweaksWB', 'WPFTweaksWF', 'WPFToggleWB', 'WPFPanelWB', 'WPFWFRep', 'WPFWFSrv', 'WPFWFAd')
    $wfI18nAlvos = @(
        @{ Nome = 'tweaks';      Config = $sync.configs.tweaks;       Campos = @('Content', 'Description') }
        @{ Nome = 'Config';      Config = $sync.configs.feature;      Campos = @('Content', 'Description') }
        @{ Nome = 'aplicativos'; Config = $sync.configs.applications; Campos = @('description') }
    )
    $wfI18nDic = $sync.WinForgeI18n
    if ($null -eq $wfI18nDic) { $wfI18nDic = @{} }
    $wfI18nSemTraducao = @()
    $wfI18nExistentes = @{}
    $wfI18nTexto = New-Object System.Text.StringBuilder
    foreach ($wfAlvo in $wfI18nAlvos) {
        foreach ($p in $wfAlvo.Config.PSObject.Properties) {
            $wfI18nExistentes[$p.Name] = $true
            foreach ($wfCampo in $wfAlvo.Campos) {
                $wfProp = $p.Value.PSObject.Properties[$wfCampo]
                if ($wfProp) { [void]$wfI18nTexto.AppendLine([string]$wfProp.Value) }
            }
            $wfProprio = $false
            foreach ($wfPre in $wfI18nPrefixos) { if ($p.Name.StartsWith($wfPre, [StringComparison]::Ordinal)) { $wfProprio = $true; break } }
            if ($wfProprio) { continue }
            if (-not $wfI18nDic.ContainsKey($p.Name)) { $wfI18nSemTraducao += "$($wfAlvo.Nome):$($p.Name)" }
        }
    }
    if ($wfI18nSemTraducao.Count) {
        Write-Host "  [ERRO] dicionário: $($wfI18nSemTraducao.Count) entrada(s) da base sem tradução -> $($wfI18nSemTraducao -join ', ')" -ForegroundColor Red; $wbErrors++
    }
    # Sentido inverso: chave no dicionário que não existe em configuração nenhuma é tradução morta -
    # some da tela sem ninguém notar quando o arquivo base muda o nome de uma entrada.
    $wfI18nOrfas = @($wfI18nDic.Keys | Where-Object { -not $wfI18nExistentes.ContainsKey($_) } | Sort-Object)
    if ($wfI18nOrfas.Count) {
        Write-Host "  [ERRO] dicionário: $($wfI18nOrfas.Count) chave(s) sem entrada correspondente -> $($wfI18nOrfas -join ', ')" -ForegroundColor Red; $wbErrors++
    }
    if (-not $wfI18nSemTraducao.Count -and -not $wfI18nOrfas.Count) {
        Write-Host "  Dicionário por chave: $(@($wfI18nDic.Keys).Count) entrada(s), cobrindo tudo que veio da base"
    }
    # Mesma trava de idioma do XAML, agora sobre o texto que os três blocos mostram na tela. Sem
    # -Xaml: aqui o texto já é o visível (Content/Description), não tem marcação para extrair.
    $wfIdiomaConfigs = Test-WinForgeEnglishLeftovers -Text $wfI18nTexto.ToString() -Where 'configurações'
    if ($wfIdiomaConfigs) { $wbErrors += $wfIdiomaConfigs }
    else { Write-Host "  Idioma: nenhum termo em inglês no Content/Description de tweaks, Config e aplicativos" }
    # Qualidade da descrição. A descrição é o texto que decide se a pessoa marca ou não marca o
    # item, e o vício que ela tinha era escrever duas vezes a mesma frase dentro de si mesma
    # ("Desativa o IPv6." depois do título "IPv6 - Desativar") ou não dizer nada além do título.
    # As cinco regras abaixo não conseguem julgar se o texto é BOM, mas reprovam exatamente as
    # formas de ser vazio que já apareceram aqui.
    #
    # O texto conferido é o de ORIGEM: item de Cuidado chega nesta altura com o prefixo
    # "CUIDADO: <motivo>. " colado por Initialize-WinForgeAudit, e ele sai antes da conferência -
    # senão a trava cobraria do autor da descrição um texto que quem escreveu foi a auditoria. O
    # prefixo é remontado a partir do motivo, e não cortado "até o primeiro ponto": há motivo com
    # ponto no meio, e o corte ingênuo comeria metade da frase.
    $wfDescAlvos = @(
        @{ Nome = 'tweaks';      Config = $sync.configs.tweaks;       Campo = 'Description' }
        @{ Nome = 'Config';      Config = $sync.configs.feature;      Campo = 'Description' }
        @{ Nome = 'aplicativos'; Config = $sync.configs.applications; Campo = 'description' }
    )
    $wfDescMin = 40
    # (g) Descrição em branco só é permitida nestes 14 botões: eles abrem um painel conhecido do
    # Windows, o rótulo já é a resposta e não há efeito colateral a avisar. A lista é explícita de
    # propósito - a versão anterior pulava QUALQUER descrição vazia, então apagar o texto de um item
    # de risco passava calado pela trava, que é o oposto do que ela existe para fazer.
    $wfDescSemTexto = @(
        'WPFPanelComputer', 'WPFPanelControl', 'WPFPanelFirewall', 'WPFPanelMouse', 'WPFPanelNetwork'
        'WPFPanelPower', 'WPFPanelPrinter', 'WPFPanelPrograms', 'WPFPanelRegion', 'WPFPanelRestore'
        'WPFPanelSecurity', 'WPFPanelSound', 'WPFPanelSystem', 'WPFPanelTimedate'
    )
    # (f) Frase repetida ENTRE entradas. A regra (a) só via dentro de uma descrição, e o vício
    # apenas mudou de lugar: dois botões de driver traziam o mesmo par de frases, ponto por ponto.
    # Quem lê duas entradas seguidas e encontra o mesmo parágrafo aprende a não ler a terceira.
    # O corte em 60 caracteres deixa passar a ressalva curta ("Só lê, não altera nada.", "Exige
    # reinício.") e pega o bloco de texto copiado. Não há allowlist: as 68 linhas de prioridade por
    # jogo contam como UMA entrada porque são um só literal em wb-functions.ps1, parametrizado pela
    # lista de executáveis - contá-las de uma em uma acusaria 67 repetições de uma frase escrita
    # uma vez.
    $wfDescFraseMin = 60
    $wfDescCruzada = @{}
    $wfDescBranco = 0
    $wfDescProblemas = @()
    $wfDescTotal = 0
    foreach ($wfAlvo in $wfDescAlvos) {
        foreach ($p in $wfAlvo.Config.PSObject.Properties) {
            $wfDescProp = $p.Value.PSObject.Properties[$wfAlvo.Campo]
            $wfDesc = if ($wfDescProp) { ([string]$wfDescProp.Value).Trim() } else { '' }
            if ([string]::IsNullOrWhiteSpace($wfDesc)) {
                if ($wfDescSemTexto -contains $p.Name) { $wfDescBranco++; continue }
                $wfDescProblemas += "$($wfAlvo.Nome):$($p.Name) -> sem descrição, e a chave não está na lista dos painéis clássicos do Windows"
                continue
            }
            $wfDescAud = $sync.WinForgeAudit[$p.Name]
            if ($wfDescAud -and $wfDescAud.Class -eq 'Cuidado') {
                $wfDescPre = "CUIDADO: {0}. " -f ([string]$wfDescAud.Reason).TrimEnd('.')
                if ($wfDesc.StartsWith($wfDescPre, [StringComparison]::Ordinal)) { $wfDesc = $wfDesc.Substring($wfDescPre.Length).Trim() }
            }
            $wfDescTotal++
            $wfDescOnde = "$($wfAlvo.Nome):$($p.Name)"
            $wfDescTitulo = ''
            $wfDescPropC = $p.Value.PSObject.Properties['Content']
            if ($wfDescPropC) { $wfDescTitulo = ([string]$wfDescPropC.Value).Trim() }
            # (a) frase repetida dentro da mesma descrição
            $wfDescFrases = @()
            foreach ($wfFrase in [regex]::Split($wfDesc, '(?<=[.!?])\s+')) {
                $wfFraseN = ([regex]::Replace([string]$wfFrase, '\s+', ' ')).Trim().TrimEnd('.', '!', '?').ToLowerInvariant()
                if ($wfFraseN.Length -gt 0) { $wfDescFrases += $wfFraseN }
            }
            $wfDescRepetida = @($wfDescFrases | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
            if ($wfDescRepetida.Count) { $wfDescProblemas += "$wfDescOnde -> frase repetida: '$($wfDescRepetida[0])'" }
            # (f) as frases longas desta entrada vão para a conferência entre entradas
            $wfDescFamilia = if ($p.Name -like 'WPFTweaksWBGame*') { 'tweaks:WPFTweaksWBGame*' } else { $wfDescOnde }
            foreach ($wfFraseN in ($wfDescFrases | Select-Object -Unique)) {
                if ($wfFraseN.Length -le $wfDescFraseMin) { continue }
                if (-not $wfDescCruzada.ContainsKey($wfFraseN)) { $wfDescCruzada[$wfFraseN] = @() }
                if ($wfDescCruzada[$wfFraseN] -notcontains $wfDescFamilia) { $wfDescCruzada[$wfFraseN] += $wfDescFamilia }
            }
            # (b) tamanho mínimo: abaixo disso não cabe mecanismo + efeito
            if ($wfDesc.Length -lt $wfDescMin) { $wfDescProblemas += "$wfDescOnde -> $($wfDesc.Length) caractere(s), mínimo $wfDescMin" }
            # (c) descrição que só repete o título não informa nada
            if ($wfDescTitulo.Length -gt 0) {
                if ($wfDesc.Equals($wfDescTitulo, [StringComparison]::OrdinalIgnoreCase)) { $wfDescProblemas += "$wfDescOnde -> descrição igual ao Content" }
                elseif ($wfDesc.StartsWith($wfDescTitulo, [StringComparison]::OrdinalIgnoreCase)) { $wfDescProblemas += "$wfDescOnde -> descrição começa repetindo o Content" }
            }
            # (d) a procedência do Windows Boost é UMA, no fim
            $wfDescOrigem = ([regex]::Matches($wfDesc, 'Origem:')).Count
            if ($wfDescOrigem -gt 1) { $wfDescProblemas += "$wfDescOnde -> $wfDescOrigem 'Origem:' na mesma descrição" }
            # (e) quem escreve 'CUIDADO:' é a auditoria, não o texto de origem
            if ($wfDesc.IndexOf('CUIDADO:', [StringComparison]::Ordinal) -ge 0) { $wfDescProblemas += "$wfDescOnde -> 'CUIDADO:' escrito na descrição de origem (quem prefixa é a auditoria)" }
        }
    }
    foreach ($wfFraseChave in @($wfDescCruzada.Keys | Sort-Object)) {
        $wfDescDonos = @($wfDescCruzada[$wfFraseChave])
        if ($wfDescDonos.Count -gt 1) {
            $wfDescProblemas += "$($wfDescDonos -join ' = ') -> a mesma frase nas $($wfDescDonos.Count) entradas: '$wfFraseChave'"
        }
    }
    # A lista de dispensa envelhece calada: se um painel clássico ganhar descrição ou sumir da
    # config, ela passa a proteger uma chave que não existe mais.
    if ($wfDescBranco -ne $wfDescSemTexto.Count) {
        $wfDescProblemas += "painéis clássicos sem descrição: $wfDescBranco encontrado(s), $($wfDescSemTexto.Count) na lista de dispensa"
    }
    if ($wfDescProblemas.Count) {
        Write-Host "  [ERRO] descrições: $($wfDescProblemas.Count) problema(s) em $wfDescTotal descrição(ões)" -ForegroundColor Red; $wbErrors++
        foreach ($wfDescP in $wfDescProblemas) { Write-Host "         $wfDescP" -ForegroundColor Red }
    }
    else { Write-Host "  Descrições: $wfDescTotal com $wfDescMin+ caracteres, sem frase repetida dentro nem entre entradas, sem repetir o título e com no máximo uma 'Origem:' ($($wfDescSemTexto.Count) painéis clássicos dispensados)" }
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
    $wbIisRoot = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\iis-backup'
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
        $wbIisRootMau = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\iis-backup-aberto'
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
    $wbSecRoot = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\seguranca'
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
            elseif ([string]::IsNullOrWhiteSpace([string]$wbSecPadrao.Reason)) { Write-Host "  [ERRO] Backup (dono): recusou sem dizer por quê" -ForegroundColor Red; $wbErrors++ }
            # A recusa acima cai no PERFIL do usuário, antes de chegar na pasta de teste: com as
            # regras da pasta padrão a cadeia não para mais em %TEMP% (a parada é só da base da
            # máquina, ver Get-WinForgeSnapshotChainStop), e no caminho até %TEMP% tem elo que o
            # usuário escreve. Por isso a regra de DONO é cobrada onde ela mora, e não pelo texto
            # de uma recusa que depende de onde a pasta de teste foi parar.
            $wbSecDonoPadrao = Get-WinForgeSnapshotTrustedSid -Owner
            $wbSecDonoTeste = Get-WinForgeSnapshotTrustedSid -Owner -ExplicitRoot
            if ($wbSecDonoPadrao.ContainsKey($wbSecEu.Value)) { Write-Host "  [ERRO] Backup (dono): a identidade atual é dona aceitável da pasta PADRÃO" -ForegroundColor Red; $wbErrors++ }
            if (-not $wbSecDonoTeste.ContainsKey($wbSecEu.Value)) { Write-Host "  [ERRO] Backup (dono): com -ExplicitRoot a identidade atual deveria poder ser dona" -ForegroundColor Red; $wbErrors++ }
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
        # A máscara de ACE perigosa, direito a direito. A versão anterior somava FullControl
        # (0x1F01FF) e Modify (0x301BF) à máscara, e os dois carregam os bits de LEITURA: qualquer
        # ACE de 'Ler e executar' casava, e uma pasta com o 'Todos: Ler e executar' que metade do
        # %ProgramData% tem era recusada como se fosse escrita para todo mundo. O teste é o par:
        # leitura NÃO acusa, escrita acusa - e vale também para os nomes compostos, que continuam
        # sendo pegos pelos bits de escrita que carregam.
        $wbAceTodos = New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'
        $wbAceCasos = @(
            @{ Direito = 'ReadAndExecute';              Acusa = $false }
            @{ Direito = 'Read';                        Acusa = $false }
            @{ Direito = 'ListDirectory';               Acusa = $false }
            @{ Direito = 'ReadPermissions';             Acusa = $false }
            @{ Direito = 'Synchronize';                 Acusa = $false }
            @{ Direito = 'Write';                       Acusa = $true  }
            @{ Direito = 'WriteData';                   Acusa = $true  }
            @{ Direito = 'AppendData';                  Acusa = $true  }
            @{ Direito = 'Delete';                      Acusa = $true  }
            @{ Direito = 'DeleteSubdirectoriesAndFiles'; Acusa = $true }
            @{ Direito = 'ChangePermissions';           Acusa = $true  }
            @{ Direito = 'TakeOwnership';               Acusa = $true  }
            @{ Direito = 'Modify';                      Acusa = $true  }
            @{ Direito = 'FullControl';                 Acusa = $true  }
        )
        $wbAceOk = 0
        foreach ($wbAceCaso in $wbAceCasos) {
            $wbAceRegra = New-Object System.Security.AccessControl.FileSystemAccessRule ($wbAceTodos, [System.Security.AccessControl.FileSystemRights]$wbAceCaso.Direito, 'Allow')
            $wbAceQuem = Find-WinForgeSnapshotUnsafeAce -Access @($wbAceRegra) -Trusted @{}
            if ($wbAceCaso.Acusa -and -not $wbAceQuem) { Write-Host "  [ERRO] máscara de ACE: '$($wbAceCaso.Direito)' para 'Todos' deveria ser recusado" -ForegroundColor Red; $wbErrors++ }
            elseif (-not $wbAceCaso.Acusa -and $wbAceQuem) { Write-Host "  [ERRO] máscara de ACE: '$($wbAceCaso.Direito)' para 'Todos' é só leitura e foi acusado como escrita" -ForegroundColor Red; $wbErrors++ }
            else { $wbAceOk++ }
        }
        # E o SID confiável continua passando mesmo com escrita, senão a máscara recusaria a
        # própria pasta padrão (SYSTEM e Administradores têm FullControl nela).
        $wbAceSystem = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'
        $wbAceRegraS = New-Object System.Security.AccessControl.FileSystemAccessRule ($wbAceSystem, [System.Security.AccessControl.FileSystemRights]'FullControl', 'Allow')
        if (Find-WinForgeSnapshotUnsafeAce -Access @($wbAceRegraS) -Trusted @{ 'S-1-5-18' = $true }) { Write-Host "  [ERRO] máscara de ACE: SID da lista de confiança foi recusado" -ForegroundColor Red; $wbErrors++ }
        # Uma ACE de NEGAÇÃO de escrita não é permissão e não pode acusar ninguém.
        $wbAceNega = New-Object System.Security.AccessControl.FileSystemAccessRule ($wbAceTodos, [System.Security.AccessControl.FileSystemRights]'FullControl', 'Deny')
        if (Find-WinForgeSnapshotUnsafeAce -Access @($wbAceNega) -Trusted @{}) { Write-Host "  [ERRO] máscara de ACE: uma ACE de negação foi lida como permissão de escrita" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Máscara de ACE: $wbAceOk de $($wbAceCasos.Count) direito(s) classificado(s), leitura não acusa e escrita acusa"
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
    $wb3Base = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\rodada3'
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
    $wb4Base = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\rodada4'
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
    $wbSrvRoot = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\server-backup'
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
    $wfRepNomes = @('SecurityStatus','SmartReport','DotNetStatus','ChkdskScan','WmiRepair','StoreReregister','ChkdskSchedule','MemoryDiag','DotNet35Enable','VcRedist','PowerShell7','DirectX','AclVerify')
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
        # O caminho de download do DirectX continua morto: se alguma dessas funções voltar, este
        # teste cai. 'Split-WinForgeCertificateSubject' saiu desta lista na Tarefa 5 do Plano 6 - o
        # download do driver NVIDIA precisa ler o assunto do certificado -, mas ela sozinha não
        # baixa nada: é um analisador de texto. O que continua proibido é o DirectX baixar e abrir
        # um instalador de %TEMP%, que é gravável por integridade média. O download da NVIDIA vai
        # para %ProgramData%\WinForge\downloads, com a DACL de SYSTEM/Administradores e a mesma
        # conferência de dono e de reanálise da pasta de backup (Confirm-WinForgeDownloadRoot).
        foreach ($wfRepDxMorta in @('Install-WinForgeDirectX', 'Test-WinForgeMicrosoftSignature', 'Test-WinForgeMicrosoftSigner')) {
            if (Get-Command $wfRepDxMorta -ErrorAction SilentlyContinue) { Write-Host "  [ERRO] Reparo (DirectX): '$wfRepDxMorta' voltou ao programa - o WinForge não baixa executável para o DirectX" -ForegroundColor Red; $wbErrors++ }
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
        'Invoke-WinForgeChkdskSchedule', 'Invoke-WinForgeMemoryDiagSchedule',
        # Passos do botão "Servidor NTP - Ativar": mexem num serviço do Windows, então caem na mesma
        # regra - param() com -DryRun e recusa em modo SelfTest.
        'Start-WinForgeTimeService', 'Restart-WinForgeTimeService',
        # As ações de permissões do disco. Duas delas reescrevem DACL com elevação e a terceira
        # APAGA arquivo: se o -DryRun se perder em $args por falta de param(), a "simulação"
        # reescreve o disco de quem compila, ou esvazia a pasta de backup dele - que é exatamente o
        # estrago que criou esta lista.
        'Invoke-WinForgeAclRestore', 'Invoke-WinForgeAclUndo', 'Invoke-WinForgeAclCleanup'
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
    # ---------------------------------------------------------------- Correções da aba Config ao vivo
    # Os cinco botões do grupo "Correções" vieram da base e rodavam na THREAD DA JANELA, escrevendo
    # num console que o lançador esconde: durante um sfc/DISM a interface congelava e não aparecia
    # nada na tela. Agora eles passam pela mesma máquina de comandos do reparo - runspace para o
    # trabalho, janela que ACOMPANHA o arquivo de saída enquanto ele cresce.
    $wfStrNomes = @('NetworkReset', 'NtpPool', 'SystemRepair', 'WindowsUpdateReset', 'WingetReinstall')
    $wfStrChaves = @{
        NetworkReset       = 'WPFFixesNetwork'
        NtpPool            = 'WPFFixesNTPPool'
        SystemRepair       = 'WPFPanelDISM'
        WindowsUpdateReset = 'WPFFixesUpdate'
        WingetReinstall    = 'WPFFixesWinget'
    }
    $wfStrDir = Split-Path -Parent $sync.logPath
    # 1. O fluxo ao vivo em si, com um comando inofensivo: duas linhas têm de chegar ao ARQUIVO (é o
    # que a janela lê) e ao texto devolvido (é o que vai para o log).
    try {
        $wfStrArq = Join-Path $wfStrDir ("selftest-stream-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
        $wfStrRes = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'cmd.exe') -Arguments @('/c', 'echo a & echo b') -StreamTo $wfStrArq
        if ($wfStrRes.ExitCode -ne 0) { Write-Host "  [ERRO] Correções (fluxo): código de saída $($wfStrRes.ExitCode), esperado 0" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfStrLinha in @('a', 'b')) {
            if ([string]$wfStrRes.Text -notmatch "(?m)^$wfStrLinha\s*$") { Write-Host "  [ERRO] Correções (fluxo): a linha '$wfStrLinha' não voltou no texto" -ForegroundColor Red; $wbErrors++ }
        }
        if (-not (Test-Path -LiteralPath $wfStrArq)) {
            Write-Host "  [ERRO] Correções (fluxo): -StreamTo não gravou '$wfStrArq'" -ForegroundColor Red; $wbErrors++
        } else {
            $wfStrTexto = [System.IO.File]::ReadAllText($wfStrArq, [System.Text.Encoding]::UTF8)
            foreach ($wfStrLinha in @('a', 'b')) {
                if ($wfStrTexto -notmatch "(?m)^$wfStrLinha\s*$") { Write-Host "  [ERRO] Correções (fluxo): a linha '$wfStrLinha' não foi para o arquivo" -ForegroundColor Red; $wbErrors++ }
            }
            Write-Host "  Correções (fluxo): cmd /c echo a & echo b -> $(@($wfStrTexto -split "`r?`n" | Where-Object { $_ -ne '' }).Count) linha(s) no arquivo e no texto"
            Remove-Item -LiteralPath $wfStrArq -Force -ErrorAction SilentlyContinue
        }
        # E o escritor nasce ANTES do Start(): arquivo que não abre tem de estourar com o processo
        # ainda parado, e não deixar um sfc de meia hora rodando sem ninguém para ler a saída dele.
        $wfStrProc = [string](Get-Command Invoke-WinForgeStreamedProcess).ScriptBlock
        $wfStrProcEsc = $wfStrProc.IndexOf('$escritor = New-Object System.IO.StreamWriter', [StringComparison]::Ordinal)
        $wfStrProcIni = $wfStrProc.IndexOf('[void]$processo.Start()', [StringComparison]::Ordinal)
        if ($wfStrProcEsc -lt 0 -or $wfStrProcIni -lt 0) { Write-Host "  [ERRO] Correções (fluxo): não achei o escritor ou o Start() em Invoke-WinForgeStreamedProcess" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfStrProcEsc -gt $wfStrProcIni) { Write-Host "  [ERRO] Correções (fluxo): o arquivo de saída é aberto DEPOIS de o processo começar" -ForegroundColor Red; $wbErrors++ }
    } catch {
        Write-Host "  [ERRO] Correções (fluxo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 1b. A outra ponta de escrita: o passo do tipo 'Function'. A saída dele tem de chegar ao arquivo
    # LINHA A LINHA - um 'Out-File -Append' segura tudo no buffer até o passo terminar, e numa
    # redefinição do Windows Update isso é a janela em branco por vários minutos.
    try {
        $wfStrFn = Join-Path $wfStrDir ("selftest-passo-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
        Write-WinForgeStreamLine -Path $wfStrFn -Text '> primeiro'
        # O arquivo tem de ser legível JÁ, antes da segunda escrita: é isso que separa "ao vivo" de
        # "no fim". Com buffer, a leitura aqui traria vazio.
        $wfStrParcial = [System.IO.File]::ReadAllText($wfStrFn, [System.Text.Encoding]::UTF8)
        Write-WinForgeStreamLine -Path $wfStrFn -Text 'segundo, com acento: configuração'
        $wfStrFnTexto = [System.IO.File]::ReadAllText($wfStrFn, [System.Text.Encoding]::UTF8)
        if ($wfStrParcial -notmatch '> primeiro') { Write-Host "  [ERRO] Correções (passo): a primeira linha não estava no arquivo antes da segunda" -ForegroundColor Red; $wbErrors++ }
        if ($wfStrFnTexto -notmatch 'configuração') { Write-Host "  [ERRO] Correções (passo): o acréscimo perdeu o acento ou não aconteceu" -ForegroundColor Red; $wbErrors++ }
        if (([regex]::Matches($wfStrFnTexto, '> primeiro')).Count -ne 1) { Write-Host "  [ERRO] Correções (passo): o acréscimo reescreveu o arquivo em vez de acrescentar" -ForegroundColor Red; $wbErrors++ }
        $wfStrCorpo = [string](Get-Command Invoke-WinForgeStreamStep).ScriptBlock
        # '\| Out-File' e não só 'Out-File': o comentário que explica por que ele não está ali cita o
        # nome, e uma trava que casasse com o comentário nunca ficaria verde.
        if ($wfStrCorpo -match '\|\s*Out-File') { Write-Host "  [ERRO] Correções (passo): o passo de função voltou a usar Out-File, que segura a saída até o fim" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Correções (passo): função escreve linha a linha, em UTF-8 e em acréscimo"
        Remove-Item -LiteralPath $wfStrFn -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  [ERRO] Correções (passo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 2. A janela que acompanha o arquivo. Com -NoShow o relógio não é ligado (não há laço de
    # mensagens num build), então quem dá o tique é o próprio teste: é assim que dá para provar que
    # o texto CRESCE depois de o arquivo crescer, sem abrir janela nenhuma na máquina de quem compila.
    try {
        $wfStrSeg = Join-Path $wfStrDir ("selftest-follow-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
        [System.IO.File]::WriteAllText($wfStrSeg, "primeira linha`r`n", (New-Object System.Text.UTF8Encoding($true)))
        $wfStrJan = Show-WinForgeOutputWindow -Title 'SelfTest ao vivo' -FollowPath $wfStrSeg -NoShow
        if ($wfStrJan -isnot [System.Windows.Window]) {
            Write-Host "  [ERRO] Correções (janela ao vivo): -FollowPath -NoShow não devolveu uma janela" -ForegroundColor Red; $wbErrors++
        } else {
            $wfStrCaixa = $wfStrJan.FindName('WFOutputText')
            $wfStrCab = $wfStrJan.FindName('WFOutputHeader')
            if ($null -eq $wfStrCab) { Write-Host "  [ERRO] Correções (janela ao vivo): falta o cabeçalho 'WFOutputHeader'" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfStrCab.Text -notmatch 'Em andamento') { Write-Host "  [ERRO] Correções (janela ao vivo): o cabeçalho deveria dizer 'Em andamento', veio '$($wfStrCab.Text)'" -ForegroundColor Red; $wbErrors++ }
            if ($null -eq $wfStrCaixa) { Write-Host "  [ERRO] Correções (janela ao vivo): falta o TextBox 'WFOutputText'" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfStrCaixa.Text -notmatch 'primeira linha') { Write-Host "  [ERRO] Correções (janela ao vivo): a janela deveria abrir com o que o arquivo já tem" -ForegroundColor Red; $wbErrors++ }
            else {
                [System.IO.File]::AppendAllText($wfStrSeg, "segunda linha`r`n", (New-Object System.Text.UTF8Encoding($false)))
                Invoke-WinForgeFollowTick -Window $wfStrJan
                if ([string]$wfStrCaixa.Text -notmatch 'segunda linha') { Write-Host "  [ERRO] Correções (janela ao vivo): o tique não trouxe o que o arquivo ganhou" -ForegroundColor Red; $wbErrors++ }
                # A linha que já estava na tela não pode entrar de novo: o tique lê do ponto em que parou.
                if (([regex]::Matches([string]$wfStrCaixa.Text, 'primeira linha')).Count -ne 1) { Write-Host "  [ERRO] Correções (janela ao vivo): o tique repetiu o que já estava na tela" -ForegroundColor Red; $wbErrors++ }
                $sync.WinForgeStreamExit[$wfStrSeg] = 0
                $sync.WinForgeStreamDone[$wfStrSeg] = $true
                Invoke-WinForgeFollowTick -Window $wfStrJan
                if ([string]$wfStrCab.Text -notmatch 'Conclu') { Write-Host "  [ERRO] Correções (janela ao vivo): terminado, o cabeçalho deveria dizer 'Concluído', veio '$($wfStrCab.Text)'" -ForegroundColor Red; $wbErrors++ }
                elseif ([string]$wfStrCab.Text -notmatch 'código 0') { Write-Host "  [ERRO] Correções (janela ao vivo): o cabeçalho de conclusão deveria trazer o código de saída, veio '$($wfStrCab.Text)'" -ForegroundColor Red; $wbErrors++ }
                else { Write-Host "  Correções (janela ao vivo): abre com o arquivo, cresce no tique e fecha com '$($wfStrCab.Text)'" }
            }
        }
        Remove-Item -LiteralPath $wfStrSeg -Force -ErrorAction SilentlyContinue
        [void]$sync.WinForgeStreamDone.Remove($wfStrSeg)
        [void]$sync.WinForgeStreamExit.Remove($wfStrSeg)
    } catch {
        Write-Host "  [ERRO] Correções (janela ao vivo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 3. As cinco linhas da tabela. Executável sempre por CAMINHO COMPLETO dentro do System32: o
    # WinForge roda elevado e um 'netsh.exe' resolvido pelo PATH deixa a escolha do binário com uma
    # variável de ambiente que qualquer processo de integridade média escreve.
    try {
        $wfStrSys = [string][Environment]::SystemDirectory
        $wfStrPassos = 0
        foreach ($wfStrNome in $wfStrNomes) {
            $wfStrSpec = Get-WinForgeRepairCommand -Name $wfStrNome
            if ([string]$wfStrSpec.Kind -ne 'repair') { Write-Host "  [ERRO] Correções $wfStrNome`: tipo '$($wfStrSpec.Kind)', esperado 'repair'" -ForegroundColor Red; $wbErrors++ }
            if (-not $wfStrSpec.Stream) { Write-Host "  [ERRO] Correções $wfStrNome`: a linha deveria estar marcada com Stream" -ForegroundColor Red; $wbErrors++ }
            if ([string]::IsNullOrWhiteSpace($wfStrSpec.Title)) { Write-Host "  [ERRO] Correções $wfStrNome`: sem título" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfStrSpec.ConfigKey -ne $wfStrChaves[$wfStrNome]) { Write-Host "  [ERRO] Correções $wfStrNome`: ConfigKey '$($wfStrSpec.ConfigKey)', esperado '$($wfStrChaves[$wfStrNome])'" -ForegroundColor Red; $wbErrors++ }
            $wfStrLista = @($wfStrSpec.Steps)
            if (-not $wfStrLista.Count) { Write-Host "  [ERRO] Correções $wfStrNome`: sem passos" -ForegroundColor Red; $wbErrors++ }
            foreach ($wfStrPasso in $wfStrLista) {
                $wfStrPassos++
                if ($wfStrPasso.Function) {
                    if (-not (Get-Command ([string]$wfStrPasso.Function) -ErrorAction SilentlyContinue)) { Write-Host "  [ERRO] Correções $wfStrNome`: função '$($wfStrPasso.Function)' não existe" -ForegroundColor Red; $wbErrors++ }
                    continue
                }
                $wfStrExe = [string]$wfStrPasso.FilePath
                if ([string]::IsNullOrWhiteSpace($wfStrExe)) { Write-Host "  [ERRO] Correções $wfStrNome`: passo sem FilePath nem Function" -ForegroundColor Red; $wbErrors++; continue }
                if (-not [System.IO.Path]::IsPathRooted($wfStrExe)) { Write-Host "  [ERRO] Correções $wfStrNome`: '$wfStrExe' não é caminho completo" -ForegroundColor Red; $wbErrors++ }
                elseif (-not $wfStrExe.StartsWith($wfStrSys, [StringComparison]::OrdinalIgnoreCase)) { Write-Host "  [ERRO] Correções $wfStrNome`: '$wfStrExe' fora de '$wfStrSys'" -ForegroundColor Red; $wbErrors++ }
                elseif (-not (Test-Path -LiteralPath $wfStrExe -PathType Leaf)) { Write-Host "  [ERRO] Correções $wfStrNome`: '$wfStrExe' não existe nesta máquina" -ForegroundColor Red; $wbErrors++ }
                # A dica de decodificação é OBRIGATÓRIA e tem de ser um dos quatro nomes. Sem esta
                # trava a dica some por omissão e o passo cai calado em OEM - que foi exatamente o
                # que aconteceu com o chkdsk, cujo "concluídos" chegava à janela como 'concluÝdos'.
                $wfStrDica = ([string]$wfStrPasso.Encoding).Trim().ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($wfStrDica)) { Write-Host "  [ERRO] Correções $wfStrNome`: o passo '$(Split-Path -Leaf $wfStrExe)' não diz como decodificar a saída (Encoding)" -ForegroundColor Red; $wbErrors++ }
                elseif (@('oem', 'ansi', 'utf8', 'unicode') -notcontains $wfStrDica) { Write-Host "  [ERRO] Correções $wfStrNome`: Encoding '$wfStrDica' desconhecido (oem, ansi, utf8 ou unicode)" -ForegroundColor Red; $wbErrors++ }
            }
        }
        # A verificação de corrupção é chkdsk, sfc e DISM, NESTA ORDEM: o disco primeiro (um setor
        # ruim corrompe de novo o que o sfc acabou de consertar) e o DISM por último, porque é ele
        # que repõe a fonte de onde o sfc copia.
        $wfStrSR = @((Get-WinForgeRepairCommand -Name SystemRepair).Steps)
        if ($wfStrSR.Count -ne 3) { Write-Host "  [ERRO] Correções SystemRepair: $($wfStrSR.Count) passo(s), esperado 3" -ForegroundColor Red; $wbErrors++ }
        else {
            foreach ($wfStrPar in @(@(0, 'chkdsk.exe'), @(1, 'sfc.exe'), @(2, 'dism.exe'))) {
                $wfStrFolha = [string](Split-Path -Leaf ([string]$wfStrSR[$wfStrPar[0]].FilePath))
                if ($wfStrFolha -ne [string]$wfStrPar[1]) { Write-Host "  [ERRO] Correções SystemRepair: passo $($wfStrPar[0] + 1) é '$wfStrFolha', esperado '$($wfStrPar[1])'" -ForegroundColor Red; $wbErrors++ }
            }
        }
        Write-Host "  Correções (tabela): $($wfStrNomes.Count) linha(s) 'repair' com fluxo ao vivo, $wfStrPassos passo(s), executáveis por caminho completo"
    } catch {
        Write-Host "  [ERRO] Correções (tabela): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 3b. A DECODIFICAÇÃO de cada passo, que não tem regra geral: cada executável do Windows escolhe
    # a sua, e a única forma de saber é medir os bytes que ele escreve com a saída redirecionada.
    # Este bloco tranca as três pontas: o nome vira a code page certa, cada executável da tabela tem
    # o nome que foi MEDIDO nele, e a dica chega mesmo ao processo.
    #
    # Quem paga a conta desta trava é o chkdsk. Ele escreve ANSI (1252), e a tabela o dava como OEM:
    # numa execução elevada de verdade a janela mostrou 'concluÝdos', 'EstÃgio' e 'anÃlises' - o
    # 0xED do 'í' da 1252 lido na 850 é 'Ý'. O sfc, que já tinha dica própria, saiu correto.
    try {
        $wfEncEsperado = @{
            'chkdsk.exe' = 'ansi'
            'sfc.exe'    = 'unicode'
            'dism.exe'   = 'oem'
            'netsh.exe'  = 'utf8'
            'w32tm.exe'  = 'oem'
        }
        $wfEncPares = @{
            'oem'     = [int][System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
            'ansi'    = [int][System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
            'utf8'    = 65001
            'unicode' = 1200
        }
        foreach ($wfEncNome in @($wfEncPares.Keys)) {
            $wfEncObj = Get-WinForgeOutputEncoding -Name $wfEncNome
            if ([int]$wfEncObj.CodePage -ne [int]$wfEncPares[$wfEncNome]) { Write-Host "  [ERRO] Correções (codificação): '$wfEncNome' deu a code page $($wfEncObj.CodePage), esperado $($wfEncPares[$wfEncNome])" -ForegroundColor Red; $wbErrors++ }
        }
        # Nome desconhecido cai em OEM, e não estoura: um passo com a dica errada tem de mostrar
        # acento embaralhado, não derrubar o reparo no meio.
        if ([int](Get-WinForgeOutputEncoding -Name 'nao-existe').CodePage -ne [int]$wfEncPares['oem']) { Write-Host "  [ERRO] Correções (codificação): um nome desconhecido deveria cair em OEM" -ForegroundColor Red; $wbErrors++ }
        if ([int](Get-WinForgeOutputEncoding).CodePage -ne [int]$wfEncPares['oem']) { Write-Host "  [ERRO] Correções (codificação): sem -Name o padrão deveria ser OEM" -ForegroundColor Red; $wbErrors++ }
        # A tabela medida, executável por executável.
        $wfEncVistos = 0
        foreach ($wfEncCmd in $wfStrNomes) {
            foreach ($wfEncPasso in @((Get-WinForgeRepairCommand -Name $wfEncCmd).Steps)) {
                if ($wfEncPasso.Function) { continue }
                $wfEncFolha = [string](Split-Path -Leaf ([string]$wfEncPasso.FilePath))
                if (-not $wfEncEsperado.ContainsKey($wfEncFolha.ToLowerInvariant())) { Write-Host "  [ERRO] Correções (codificação): '$wfEncFolha' não está na tabela medida - meça a saída dele antes de pôr o passo na linha" -ForegroundColor Red; $wbErrors++; continue }
                $wfEncQuer = [string]$wfEncEsperado[$wfEncFolha.ToLowerInvariant()]
                $wfEncTem = ([string]$wfEncPasso.Encoding).Trim().ToLowerInvariant()
                if ($wfEncTem -ne $wfEncQuer) { Write-Host "  [ERRO] Correções (codificação): '$wfEncFolha' está como '$wfEncTem', medido '$wfEncQuer'" -ForegroundColor Red; $wbErrors++ }
                else { $wfEncVistos++ }
            }
        }
        # A prova do chkdsk, com bytes sintéticos: "concluídos" escrito em ANSI (o 'í' é 0xED) tem
        # de voltar acentuado pela codificação do PASSO do chkdsk, e tem de sair errado se lido em
        # OEM - que é o que a janela mostrou na máquina do usuário.
        $wfEncBytes = [byte[]]@(0x63, 0x6F, 0x6E, 0x63, 0x6C, 0x75, 0xED, 0x64, 0x6F, 0x73)
        $wfEncPassoChk = @((Get-WinForgeRepairCommand -Name SystemRepair).Steps)[0]
        $wfEncLido = [string](Get-WinForgeOutputEncoding -Name ([string]$wfEncPassoChk.Encoding)).GetString($wfEncBytes)
        $wfEncComoOem = [string](Get-WinForgeOutputEncoding -Name 'oem').GetString($wfEncBytes)
        if ($wfEncLido -ne 'concluídos') { Write-Host "  [ERRO] Correções (codificação): a saída do chkdsk decodificada pelo passo deu '$wfEncLido', esperado 'concluídos'" -ForegroundColor Red; $wbErrors++ }
        if ($wfEncComoOem -eq 'concluídos') { Write-Host "  [ERRO] Correções (codificação): o cenário não vale - em OEM estes bytes deveriam sair embaralhados" -ForegroundColor Red; $wbErrors++ }
        # E a dica chega mesmo ao processo: o takeown escreve OEM ('á' = 0xA0), e o mesmo '/?'
        # pedido como 'unicode' tem de voltar ilegível. É a única forma de provar que o
        # StandardOutputEncoding do fluxo ao vivo recebe o que o passo pediu. '/?' só imprime ajuda.
        if (([string](Get-Command Invoke-WinForgeStreamStep).ScriptBlock).IndexOf('-Encoding ([string]$Step.Encoding)', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (codificação): o passo não repassa a dica de decodificação ao comando" -ForegroundColor Red; $wbErrors++ }
        $wfEncArq = Join-Path $wfStrDir ("selftest-encoding-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
        $wfEncExe = Get-WinForgeSystemExe -Name 'takeown.exe'
        $wfEncCerto = [string](Invoke-WinForgeNativeCommand -FilePath $wfEncExe -Arguments @('/?') -StreamTo $wfEncArq -Encoding 'oem').Text
        $wfEncErrado = [string](Invoke-WinForgeNativeCommand -FilePath $wfEncExe -Arguments @('/?') -StreamTo $wfEncArq -Encoding 'unicode').Text
        # 'usuário' só existe na ajuda em português; noutro idioma (o runner do CI é en-US) a prova
        # é que a leitura OEM não tem caractere de substituição e difere da leitura como UTF-16.
        $wfEncPt = ([System.Globalization.CultureInfo]::CurrentUICulture.Name -like 'pt*')
        if ($wfEncPt -and $wfEncCerto.IndexOf('usuário', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (codificação): o takeown lido como OEM não trouxe 'usuário' acentuado" -ForegroundColor Red; $wbErrors++ }
        elseif (-not $wfEncPt -and ($wfEncCerto.IndexOf([char]0xFFFD) -ge 0 -or $wfEncCerto.Length -lt 50 -or $wfEncCerto -eq $wfEncErrado)) { Write-Host "  [ERRO] Correções (codificação): o takeown lido como OEM veio ilegível ou igual à leitura UTF-16 (idioma $([System.Globalization.CultureInfo]::CurrentUICulture.Name))" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfEncErrado.IndexOf('usuário', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Correções (codificação): a dica não chegou ao processo - lido como UTF-16 o texto saiu igual" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Correções (codificação): 4 nome(s) viram code page, $wfEncVistos passo(s) com a dica medida (chkdsk ANSI, sfc UTF-16, DISM/w32tm OEM, netsh UTF-8), dica conferida no processo" }
        Remove-Item -LiteralPath $wfEncArq -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  [ERRO] Correções (codificação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 4. Simulação e recusa. O -DryRun LISTA os passos e não roda nenhum; sem ele, em SelfTest, o
    # despacho é recusado - este build não redefine rede nem roda DISM na máquina de quem compila.
    try {
        $wfStrAntes = @(Get-ChildItem -LiteralPath $wfStrDir -Filter 'repair-*.txt' -ErrorAction SilentlyContinue).Count
        $wfStrTravaAntes = $sync.CommandRunning
        $wfStrSecos = 0
        foreach ($wfStrNome in $wfStrNomes) {
            $wfStrSpec = Get-WinForgeRepairCommand -Name $wfStrNome
            $wfStrLinhas = @(Start-WinForgeStreamedCommand -Name $wfStrNome -Spec $wfStrSpec -DryRun)
            if ($wfStrLinhas.Count -ne @($wfStrSpec.Steps).Count) { Write-Host "  [ERRO] Correções $wfStrNome`: -DryRun listou $($wfStrLinhas.Count) passo(s), esperado $(@($wfStrSpec.Steps).Count)" -ForegroundColor Red; $wbErrors++ }
            foreach ($wfStrLinha in $wfStrLinhas) {
                if (-not ([string]$wfStrLinha).StartsWith('[simulação] ')) { Write-Host "  [ERRO] Correções $wfStrNome`: -DryRun deveria prefixar '[simulação] ', veio '$wfStrLinha'" -ForegroundColor Red; $wbErrors++ }
                else { $wfStrSecos++ }
            }
            $wfStrRecusa = $null
            try { Start-WinForgeStreamedCommand -Name $wfStrNome -Spec $wfStrSpec | Out-Null } catch { $wfStrRecusa = [string]$_.Exception.Message }
            if ($null -eq $wfStrRecusa) { Write-Host "  [ERRO] Correções $wfStrNome`: rodou de verdade em modo SelfTest" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfStrRecusa -notmatch 'SelfTest') { Write-Host "  [ERRO] Correções $wfStrNome`: a recusa não fala em SelfTest: '$wfStrRecusa'" -ForegroundColor Red; $wbErrors++ }
            $wfStrDec = Invoke-WinForgeRepairCommand -Name $wfStrNome -NoUI
            if ($null -eq $wfStrDec -or $wfStrDec.Dispatched -or [string]$wfStrDec.Reason -ne 'confirmação') { Write-Host "  [ERRO] Correções $wfStrNome`: -NoUI deveria recusar com motivo 'confirmação', veio '$($wfStrDec.Reason)'" -ForegroundColor Red; $wbErrors++ }
        }
        $wfStrDepois = @(Get-ChildItem -LiteralPath $wfStrDir -Filter 'repair-*.txt' -ErrorAction SilentlyContinue).Count
        if ($wfStrDepois -ne $wfStrAntes) { Write-Host "  [ERRO] Correções: a simulação gravou arquivo na pasta de logs ($wfStrAntes -> $wfStrDepois)" -ForegroundColor Red; $wbErrors++ }
        if ($sync.CommandRunning -ne $wfStrTravaAntes) { Write-Host "  [ERRO] Correções: a trava de comando em andamento ficou presa depois da simulação" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Correções (simulação): $wfStrSecos passo(s) listados, nenhum rodado, nenhum arquivo gravado"
    } catch {
        Write-Host "  [ERRO] Correções (simulação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 5. A pergunta antes de agir. A descrição vem da MESMA entrada da config que vira a dica do
    # botão na aba Config; as duas que pedem reinicialização têm de dizer isso na própria pergunta.
    try {
        $wfStrConfOk = 0
        foreach ($wfStrNome in $wfStrNomes) {
            $wfStrChave = $wfStrChaves[$wfStrNome]
            $wfStrDesc = [string]$sync.configs.feature.$wfStrChave.Description
            if ([string]::IsNullOrWhiteSpace($wfStrDesc)) { Write-Host "  [ERRO] Correções (confirmação): $wfStrChave sem Description na config" -ForegroundColor Red; $wbErrors++; continue }
            $wfStrConf = [string](Get-WinForgeRepairConfirmText -Name $wfStrNome)
            if ($wfStrConf -notmatch [regex]::Escape($wfStrDesc.Trim())) { Write-Host "  [ERRO] Correções (confirmação) $wfStrNome`: o texto não veio da Description de $wfStrChave" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfStrConf -notmatch [regex]::Escape([string](Get-WinForgeRepairCommand -Name $wfStrNome).Title)) { Write-Host "  [ERRO] Correções (confirmação) $wfStrNome`: o texto não traz o título" -ForegroundColor Red; $wbErrors++ }
            elseif (([regex]::Matches($wfStrConf, 'Continuar')).Count -ne 1) { Write-Host "  [ERRO] Correções (confirmação) $wfStrNome`: 'Continuar' deveria aparecer uma vez" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfStrConf.Length -lt 120) { Write-Host "  [ERRO] Correções (confirmação) $wfStrNome`: texto curto demais ($($wfStrConf.Length) caractere(s))" -ForegroundColor Red; $wbErrors++ }
            else { $wfStrConfOk++ }
        }
        foreach ($wfStrNome in @('NetworkReset', 'WindowsUpdateReset')) {
            if ([string](Get-WinForgeRepairConfirmText -Name $wfStrNome) -notmatch 'einici') { Write-Host "  [ERRO] Correções (confirmação) $wfStrNome`: a pergunta não avisa que pode ser preciso reiniciar" -ForegroundColor Red; $wbErrors++ }
        }
        # Duas descrições prometiam menos do que a função da base FAZ, e a pessoa dizia "Sim" a algo
        # que não leu. A redefinição do Windows Update apaga a diretiva de grupo local inteira
        # (HKLM/HKCU\Software\Policies, as pastas GroupPolicy, secedit com o defltbase.inf e um
        # gpupdate /force) e mexe em IP e proxy do winhttp, não só no Winsock. A do WinGet não baixa
        # App Installer nenhum: instala um módulo da Galeria do PowerShell e chama Repair-WinGetPackageManager.
        foreach ($wfStrHonesta in @(
            @{ Chave = 'WPFFixesUpdate';  Exige = @('Policies', 'GroupPolicy', 'secedit', 'gpupdate', 'netsh', 'winhttp'); Proibe = @() }
            @{ Chave = 'WPFFixesWinget'; Exige = @('Microsoft.WinGet.Client', 'Repair-WinGetPackageManager', 'Galeria do PowerShell'); Proibe = @('App Installer') }
        )) {
            $wfStrHonTexto = [string]$sync.configs.feature."$($wfStrHonesta.Chave)".Description
            foreach ($wfStrHonTermo in $wfStrHonesta.Exige) {
                if ($wfStrHonTexto.IndexOf($wfStrHonTermo, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Write-Host "  [ERRO] Correções (confirmação) $($wfStrHonesta.Chave): a descrição não diz que a base mexe em '$wfStrHonTermo'" -ForegroundColor Red; $wbErrors++ }
            }
            foreach ($wfStrHonTermo in $wfStrHonesta.Proibe) {
                if ($wfStrHonTexto.IndexOf($wfStrHonTermo, [StringComparison]::OrdinalIgnoreCase) -ge 0) { Write-Host "  [ERRO] Correções (confirmação) $($wfStrHonesta.Chave): a descrição voltou a prometer '$wfStrHonTermo', que a base não faz" -ForegroundColor Red; $wbErrors++ }
            }
        }
        Write-Host "  Correções (confirmação): $wfStrConfOk texto(s) vindos da descrição da aba Config, com aviso de reinicialização onde cabe"
    } catch {
        Write-Host "  [ERRO] Correções (confirmação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 6. O caminho do clique no motor GERADO. Duas pontas: a guarda do lookup tira as cinco chaves do
    # caminho da config (que chamaria $buttonConfig.function SEM argumento) e o switch as despacha com
    # o -Name explícito. A chave 'function' também sai da entrada: sem ela, uma guarda quebrada cai no
    # switch em vez de voltar a congelar a janela com a função da base.
    try {
        $wfStrLookup = [string](Get-Command Invoke-WPFButton).ScriptBlock
        foreach ($wfStrNome in $wfStrNomes) {
            $wfStrChave = $wfStrChaves[$wfStrNome]
            if ($wfStrLookup -notmatch ([regex]::Escape("`"$wfStrChave`" {Invoke-WinForgeRepairCommand -Name $wfStrNome}"))) { Write-Host "  [ERRO] Correções (clique): o switch não despacha '$wfStrChave' para -Name $wfStrNome" -ForegroundColor Red; $wbErrors++ }
            $wfStrEntrada = $sync.configs.feature.$wfStrChave
            if ($null -eq $wfStrEntrada) { Write-Host "  [ERRO] Correções (clique): '$wfStrChave' não existe na config da aba Config" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfStrEntrada.PSObject.Properties['function']) { Write-Host "  [ERRO] Correções (clique): '$wfStrChave' ainda tem a chave 'function' morta ('$($wfStrEntrada.function)')" -ForegroundColor Red; $wbErrors++ }
        }
        # A guarda do lookup tem de nomear as cinco chaves E usá-las de verdade na condição: a lista
        # sozinha seria uma declaração bonita e morta.
        if ($wfStrLookup -notmatch "\`$Button -notin \`$wfCorrecoes") { Write-Host "  [ERRO] Correções (clique): a guarda do lookup não usa a lista de correções" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfStrChave in @($wfStrChaves.Values | Sort-Object)) {
            if ($wfStrLookup -notmatch "(?s)\`$wfCorrecoes = @\(.{0,300}?$([regex]::Escape($wfStrChave))") { Write-Host "  [ERRO] Correções (clique): a guarda do lookup não exclui '$wfStrChave'" -ForegroundColor Red; $wbErrors++ }
        }
        # E as funções da base que congelavam a janela não podem mais ser alcançadas por clique
        # nenhum: nem pelo switch, nem por uma entrada de config que ainda as aponte.
        foreach ($wfStrMorta in @('Invoke-WPFSystemRepair', 'Invoke-WPFFixesNetwork', 'Invoke-WPFFixesNTPPool')) {
            if ($wfStrLookup -match [regex]::Escape($wfStrMorta)) { Write-Host "  [ERRO] Correções (clique): '$wfStrMorta' ainda aparece em Invoke-WPFButton" -ForegroundColor Red; $wbErrors++ }
            $wfStrAponta = @($sync.configs.feature.PSObject.Properties | Where-Object { [string]$_.Value.function -eq $wfStrMorta } | ForEach-Object { $_.Name })
            if ($wfStrAponta.Count) { Write-Host "  [ERRO] Correções (clique): '$wfStrMorta' ainda é a função de $($wfStrAponta -join ', ')" -ForegroundColor Red; $wbErrors++ }
        }
        # Invoke-WPFFixesUpdate e Invoke-WPFFixesWinget continuam existindo - elas são o CONTEÚDO de
        # dois dos passos -, mas rodam dentro do runspace, e lá elas mexem no ícone da barra de
        # tarefas, que é objeto da janela. Sem a passagem pelo Dispatcher isso morre com "outra
        # thread é dona deste objeto" na primeira linha, antes de qualquer saída.
        $wfStrTbFonte = [string](Get-Command Set-WinUtilTaskbaritem).ScriptBlock
        if ($wfStrTbFonte -notmatch 'CheckAccess') { Write-Host "  [ERRO] Correções (clique): Set-WinUtilTaskbaritem não volta para a thread da janela" -ForegroundColor Red; $wbErrors++ }
        # E o que ela manda para lá é um pacote POR CHAMADA, com chave própria, e não um slot
        # compartilhado: duas chamadas entrelaçadas no slot único perderiam uma atualização. Hoje
        # as travas mantêm um escritor só, mas isso é acidente de quem chama, não garantia daqui.
        if ($wfStrTbFonte.IndexOf('$sync.WinForgeTaskbarQueue.Enqueue($wfTbChaveNova)', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (clique): o desvio do ícone da barra não enfileira um pacote por chamada" -ForegroundColor Red; $wbErrors++ }
        if ($wfStrTbFonte -match "WinForgeTaskbarArgs\['state'\]") { Write-Host "  [ERRO] Correções (clique): o desvio do ícone da barra voltou ao slot único compartilhado" -ForegroundColor Red; $wbErrors++ }
        if ([string]$sync.WinForgeTaskbarCallback -notmatch 'WinForgeTaskbarQueue\.Dequeue') { Write-Host "  [ERRO] Correções (clique): o callback do ícone da barra não consome a fila de pacotes" -ForegroundColor Red; $wbErrors++ }
        # E na prática: dois pacotes enfileirados, dois consumos, nada sobra no dicionário.
        $wfStrTbAntes = @($sync.WinForgeTaskbarArgs.Keys).Count
        $sync.WinForgeTaskbarArgs['selftest-a'] = @{ state = 'Normal'; value = 0.25; overlay = ''; description = 'a' }
        $sync.WinForgeTaskbarArgs['selftest-b'] = @{ state = 'Normal'; value = 0.75; overlay = ''; description = 'b' }
        $sync.WinForgeTaskbarQueue.Enqueue('selftest-a')
        $sync.WinForgeTaskbarQueue.Enqueue('selftest-b')
        & $sync.WinForgeTaskbarCallback
        & $sync.WinForgeTaskbarCallback
        if ($sync.WinForgeTaskbarArgs.ContainsKey('selftest-a') -or $sync.WinForgeTaskbarArgs.ContainsKey('selftest-b')) { Write-Host "  [ERRO] Correções (clique): o callback do ícone da barra não removeu o pacote que consumiu" -ForegroundColor Red; $wbErrors++ }
        if (@($sync.WinForgeTaskbarArgs.Keys).Count -ne $wfStrTbAntes) { Write-Host "  [ERRO] Correções (clique): sobrou pacote no dicionário do ícone da barra" -ForegroundColor Red; $wbErrors++ }
        $sync.WinForgeTaskbarArgs.Remove('selftest-a'); $sync.WinForgeTaskbarArgs.Remove('selftest-b')
        while ($sync.WinForgeTaskbarQueue.Count -gt 0) { [void]$sync.WinForgeTaskbarQueue.Dequeue() }
        Write-Host "  Correções (clique): $($wfStrNomes.Count) chave(s) fora do caminho da config e despachadas pelo switch com -Name"
    } catch {
        Write-Host "  [ERRO] Correções (clique): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 7. O CORPO da runspace, rodado de verdade, com passos inofensivos. Os cinco comandos continuam
    # sem rodar: os passos daqui são duas funções que só existem dentro do -SelfTest e um
    # 'cmd /c echo'. É o que transforma em comportamento o que antes era só texto - código POR PASSO,
    # cabeçalho final dizendo qual passo falhou, e as duas travas soltas no 'finally'.
    #
    # O passo que falha é o defeito que este bloco existe para pegar: Write-Error e Stop-Service que
    # não para são erros NÃO TERMINANTES. A função "termina bem", e a janela dizia
    # "Concluído (código 0)" depois de vinte linhas de erro. Agora o ErrorRecord vira '[erro] ...' e
    # o passo vale 1 - e o passo seguinte continua rodando, porque uma redefinição de Windows Update
    # que para no primeiro serviço teimoso deixa o sistema pior do que estava.
    function Test-WinForgeStreamProbeStep {
        $sync.WinForgeSelfTestLocks = "$($sync.CommandRunning)/$($sync.ProcessRunning)"
        Write-Host 'sonda das travas'
    }
    function Test-WinForgeStreamFailingStep {
        Write-Host 'linha normal antes do erro'
        Write-Error 'falha de propósito'
        Write-Host 'linha normal depois do erro'
    }
    try {
        $wfStrCorpoArq = Join-Path $wfStrDir ("selftest-corpo-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
        $wfStrCmdExe = Get-WinForgeSystemExe -Name 'cmd.exe'
        $wfStrCorpoPassos = @(
            @{ Function = 'Test-WinForgeStreamProbeStep' }
            @{ FilePath = $wfStrCmdExe; Arguments = @('/c', 'echo ok') }
            @{ Function = 'Test-WinForgeStreamFailingStep' }
        )
        $sync.WinForgeSelfTestLocks = ''
        # As duas travas ligadas, como Start-WinForgeStreamedCommand as liga antes de despachar.
        $sync.CommandRunning = $true
        $sync.ProcessRunning = $true
        & $sync.WinForgeStreamBody @{ Name = 'SelfTest'; Path = $wfStrCorpoArq; Steps = $wfStrCorpoPassos; Final = 'fim da simulação' }
        $wfStrCorpoTexto = if (Test-Path -LiteralPath $wfStrCorpoArq) { [System.IO.File]::ReadAllText($wfStrCorpoArq, [System.Text.Encoding]::UTF8) } else { '' }
        # (a) as travas: ligadas DURANTE o passo (a sonda leu as duas) e soltas depois dele.
        if ($sync.WinForgeSelfTestLocks -ne 'True/True') { Write-Host "  [ERRO] Correções (corpo): durante o passo as travas estavam '$($sync.WinForgeSelfTestLocks)', esperado 'True/True'" -ForegroundColor Red; $wbErrors++ }
        if ($sync.CommandRunning) { Write-Host "  [ERRO] Correções (corpo): `$sync.CommandRunning ficou presa depois do corpo" -ForegroundColor Red; $wbErrors++ }
        if ($sync.ProcessRunning) { Write-Host "  [ERRO] Correções (corpo): `$sync.ProcessRunning ficou presa depois do corpo" -ForegroundColor Red; $wbErrors++ }
        # (b) o passo que falha: linha '[erro]', código 1, e a saída DEPOIS do erro continua chegando.
        if ($wfStrCorpoTexto -notmatch '(?m)^\[erro\] falha de propósito') { Write-Host "  [ERRO] Correções (corpo): o Write-Error do passo não virou linha '[erro]'" -ForegroundColor Red; $wbErrors++ }
        if ($wfStrCorpoTexto -notmatch '(?m)^linha normal depois do erro') { Write-Host "  [ERRO] Correções (corpo): o passo parou no primeiro erro em vez de seguir" -ForegroundColor Red; $wbErrors++ }
        # (c) o código por passo, um por um, com o título de cada um.
        foreach ($wfStrEsp in @(
            '== Passo 1: Test-WinForgeStreamProbeStep — código 0 =='
            '== Passo 2: cmd.exe — código 0 =='
            '== Passo 3: Test-WinForgeStreamFailingStep — código 1 =='
        )) {
            if ($wfStrCorpoTexto.IndexOf($wfStrEsp, [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (corpo): falta a linha '$wfStrEsp' no arquivo" -ForegroundColor Red; $wbErrors++ }
        }
        # (d) o cabeçalho final diz QUAL passo falhou - num chkdsk + sfc + DISM, saber só o código
        # final não diz em qual dos três olhar.
        if ($wfStrCorpoTexto.IndexOf('== Falhou no passo 3 (Test-WinForgeStreamFailingStep): código 1 ==', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (corpo): o cabeçalho final não diz qual passo falhou" -ForegroundColor Red; $wbErrors++ }
        # (d2) e a frase de fechamento NÃO sai quando o comando falhou. Ela é escrita no presente do
        # indicativo ("Configuração de rede redefinida. Reinicie o computador."): imprimi-la logo
        # abaixo de '== Falhou no passo N ==' é dizer que deu certo no exato lugar em que a pessoa
        # está lendo que não deu. No lugar dela sai uma frase neutra, que aponta o passo.
        if ($wfStrCorpoTexto -match '(?m)^fim da simulação') { Write-Host "  [ERRO] Correções (corpo): a frase final de sucesso saiu num comando que FALHOU" -ForegroundColor Red; $wbErrors++ }
        if ($wfStrCorpoTexto.IndexOf('Terminou com erro no passo 3 (Test-WinForgeStreamFailingStep); veja acima. Nada mais foi feito.', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (corpo): falta a frase neutra de fechamento do comando que falhou" -ForegroundColor Red; $wbErrors++ }
        # (e) e o fim marcado para a janela: é o que troca 'Em andamento' por 'Concluído'.
        if ($sync.WinForgeStreamDone[$wfStrCorpoArq] -ne $true) { Write-Host "  [ERRO] Correções (corpo): o fim não foi marcado em `$sync.WinForgeStreamDone" -ForegroundColor Red; $wbErrors++ }
        if ([int]$sync.WinForgeStreamExit[$wfStrCorpoArq] -ne 1) { Write-Host "  [ERRO] Correções (corpo): o código final foi '$($sync.WinForgeStreamExit[$wfStrCorpoArq])', esperado 1" -ForegroundColor Red; $wbErrors++ }
        # (f) o mesmo corpo, sem o passo que falha: aí SIM a frase de fechamento sai, e a neutra não.
        # Sem este par a trava de cima passaria com um $Final que nunca é escrito.
        $wfStrCorpoArqOk = Join-Path $wfStrDir ("selftest-corpo-ok-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
        $sync.CommandRunning = $true
        $sync.ProcessRunning = $true
        & $sync.WinForgeStreamBody @{ Name = 'SelfTest'; Path = $wfStrCorpoArqOk; Steps = @(@{ FilePath = $wfStrCmdExe; Arguments = @('/c', 'echo ok') }); Final = 'fim da simulação' }
        $wfStrCorpoOkTexto = if (Test-Path -LiteralPath $wfStrCorpoArqOk) { [System.IO.File]::ReadAllText($wfStrCorpoArqOk, [System.Text.Encoding]::UTF8) } else { '' }
        if ($wfStrCorpoOkTexto -notmatch '(?m)^fim da simulação') { Write-Host "  [ERRO] Correções (corpo): a frase final não saiu num comando que deu certo" -ForegroundColor Red; $wbErrors++ }
        if ($wfStrCorpoOkTexto.IndexOf('Terminou com erro no passo', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Correções (corpo): a frase neutra de erro saiu num comando que deu certo" -ForegroundColor Red; $wbErrors++ }
        if ([int]$sync.WinForgeStreamExit[$wfStrCorpoArqOk] -ne 0) { Write-Host "  [ERRO] Correções (corpo): o código do comando sem falha foi '$($sync.WinForgeStreamExit[$wfStrCorpoArqOk])', esperado 0" -ForegroundColor Red; $wbErrors++ }
        Remove-Item -LiteralPath $wfStrCorpoArqOk -Force -ErrorAction SilentlyContinue
        [void]$sync.WinForgeStreamDone.Remove($wfStrCorpoArqOk)
        [void]$sync.WinForgeStreamExit.Remove($wfStrCorpoArqOk)
        Write-Host "  Correções (corpo): 3 passo(s) com código próprio, erro não terminante vira '[erro]' e derruba o passo, frase final só com código 0, travas soltas no fim"
        Remove-Item -LiteralPath $wfStrCorpoArq -Force -ErrorAction SilentlyContinue
        [void]$sync.WinForgeStreamDone.Remove($wfStrCorpoArq)
        [void]$sync.WinForgeStreamExit.Remove($wfStrCorpoArq)
    } catch {
        Write-Host "  [ERRO] Correções (corpo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        $sync.CommandRunning = $false
        $sync.ProcessRunning = $false
    }
    # 8. Fechar a janela no meio de um comando com fluxo ao vivo. Eram duas pontas do mesmo abraço:
    # Close-WinUtilRunspacePool é SÍNCRONO e espera a thread do pool terminar, enquanto a thread do
    # pool, dentro de Invoke-WPFFixesUpdate, chama Set-WinUtilTaskbaritem, que salta para o
    # Dispatcher da thread que está esperando por ela. Nenhuma das duas terminava: o programa só
    # saía pelo Gerenciador de Tarefas. A correção cortou as duas pontas, e as duas são conferidas.
    try {
        $wfStrFonte = ''
        try { if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) { $wfStrFonte = [IO.File]::ReadAllText($PSCommandPath) } } catch { $wfStrFonte = '' }
        if ([string]::IsNullOrWhiteSpace($wfStrFonte)) {
            Write-Host "  [ERRO] Correções (fechamento): o próprio arquivo do WinForge não pôde ser lido para conferir o Add_Closing" -ForegroundColor Red; $wbErrors++
        } elseif ($wfStrFonte -notmatch '\$sync\.ProfileJobRunning -or \$sync\.DiagWUSearchRunning -or \$sync\.CommandRunning') {
            Write-Host "  [ERRO] Correções (fechamento): o Add_Closing não desgruda do pool com um comando em andamento" -ForegroundColor Red; $wbErrors++
        }
        # Desgrudar do pool é abandonar a thread onde ela estiver. Para um reparo isso pode parar
        # entre a posse tomada e a posse devolvida, e é por isso que o fechamento PERGUNTA - com
        # "Não" como padrão, e cancelando o fechamento em qualquer resposta que não seja "Sim".
        if (-not [string]::IsNullOrWhiteSpace($wfStrFonte)) {
            foreach ($wfStrFechEsp in @(
                @('\$sync\.CommandRunning -and \[string\]\$sync\.WinForgeStreamKind -eq ''repair''', 'a pergunta de fechamento não é restrita aos reparos'),
                @('fechar agora pode deixar o sistema pela metade', 'a pergunta de fechamento não diz o que está em jogo'),
                @('\[System\.Windows\.MessageBoxResult\]::No\)', 'a pergunta de fechamento não tem "Não" como resposta padrão'),
                @('\$wfFechArgs\.Cancel = \$true', 'o fechamento não é cancelado quando a resposta não é "Sim"')
            )) {
                if ($wfStrFonte -notmatch $wfStrFechEsp[0]) { Write-Host "  [ERRO] Correções (fechamento): $($wfStrFechEsp[1])" -ForegroundColor Red; $wbErrors++ }
            }
            # E a pergunta vem ANTES de $sync.WinForgeClosing: ligada essa bandeira, cancelar o
            # fechamento deixaria a janela viva com o programa inteiro achando que ela morreu.
            $wfStrPosPergunta = $wfStrFonte.IndexOf('fechar agora pode deixar o sistema pela metade', [StringComparison]::Ordinal)
            $wfStrPosBandeira = $wfStrFonte.IndexOf('$sync.WinForgeClosing = $true', [StringComparison]::Ordinal)
            if ($wfStrPosPergunta -ge 0 -and $wfStrPosBandeira -ge 0 -and $wfStrPosPergunta -gt $wfStrPosBandeira) { Write-Host "  [ERRO] Correções (fechamento): a pergunta vem depois de `$sync.WinForgeClosing - cancelar deixaria a janela viva e o programa achando que ela fechou" -ForegroundColor Red; $wbErrors++ }
        }
        # O par que a pergunta consulta é escrito por Start-WinForgeStreamedCommand e apagado no
        # 'finally' do corpo: sem o apagamento, o próximo fechamento perguntaria sem motivo.
        $wfStrStartFonte = [string](Get-Command Start-WinForgeStreamedCommand).ScriptBlock
        foreach ($wfStrParEsp in @('$sync.WinForgeStreamName = [string]$Spec.Title', '$sync.WinForgeStreamKind = [string]$Spec.Kind')) {
            if ($wfStrStartFonte.IndexOf($wfStrParEsp, [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (fechamento): Start-WinForgeStreamedCommand não anota '$wfStrParEsp'" -ForegroundColor Red; $wbErrors++ }
        }
        if ([string]$sync.WinForgeStreamKind -ne '') { Write-Host "  [ERRO] Correções (fechamento): `$sync.WinForgeStreamKind ficou em '$($sync.WinForgeStreamKind)' depois do corpo" -ForegroundColor Red; $wbErrors++ }
        if ([string]$sync.WinForgeStreamName -ne '') { Write-Host "  [ERRO] Correções (fechamento): `$sync.WinForgeStreamName ficou em '$($sync.WinForgeStreamName)' depois do corpo" -ForegroundColor Red; $wbErrors++ }
        # A outra ponta, esta por comportamento: com a janela fechando, Set-WinUtilTaskbaritem
        # devolve na PRIMEIRA linha, sem saltar para o Dispatcher. A sonda é o que separa "recusou"
        # de "deu certo por acaso"; e a chamada nem poderia dar certo aqui, porque neste ponto do
        # SelfTest ainda não existe janela nenhuma para ter ícone.
        $wfStrFechAntes = $sync.WinForgeClosing
        $sync.WinForgeTaskbarSkipped = $false
        $sync.WinForgeClosing = $true
        $wfStrFechErro = $null
        try { Set-WinUtilTaskbaritem -state 'Indeterminate' -overlay 'logo' -description 'sonda de fechamento' } catch { $wfStrFechErro = [string]$_.Exception.Message }
        $sync.WinForgeClosing = $wfStrFechAntes
        if ($null -ne $wfStrFechErro) { Write-Host "  [ERRO] Correções (fechamento): Set-WinUtilTaskbaritem estourou com a janela fechando: $wfStrFechErro" -ForegroundColor Red; $wbErrors++ }
        if (-not $sync.WinForgeTaskbarSkipped) { Write-Host "  [ERRO] Correções (fechamento): Set-WinUtilTaskbaritem não recusou com `$sync.WinForgeClosing ligado" -ForegroundColor Red; $wbErrors++ }
        # E a trava de comando é ligada JUNTO com a de processo: é ela que o Add_Closing consulta.
        $wfStrStart = [string](Get-Command Start-WinForgeStreamedCommand).ScriptBlock
        if ($wfStrStart -notmatch '\$sync\.ProcessRunning = \$true') { Write-Host "  [ERRO] Correções (fechamento): Start-WinForgeStreamedCommand não liga `$sync.ProcessRunning" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Correções (fechamento): o Add_Closing pergunta antes de abandonar um reparo, desgruda do pool e o ícone da barra não é tocado"
    } catch {
        Write-Host "  [ERRO] Correções (fechamento): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 8b. Os dois botões de ação da aba Diagnóstico seguem $sync.ProcessRunning - e alguém tem de
    # repintá-los quando ela muda. Até aqui quem chamava Update-WinForgeDiagActionButtons era só o
    # contador de marcações: durante um comando eles ficavam habilitados (a caixa de mensagem da
    # base recusava, então era seguro, mas o aviso vinha DEPOIS do clique), e quem marcasse uma
    # caixa no meio do comando os via desabilitar e ficar assim até a marca seguinte.
    try {
        $wfBotFonteStart = [string](Get-Command Start-WinForgeStreamedCommand).ScriptBlock
        if ($wfBotFonteStart.IndexOf('Update-WinForgeDiagActionButtons', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (botões): Start-WinForgeStreamedCommand não repinta os botões da aba Diagnóstico ao tomar as travas" -ForegroundColor Red; $wbErrors++ }
        $wfBotFonteCorpo = [string]$sync.WinForgeStreamBody
        if ($wfBotFonteCorpo.IndexOf('$sync.WinForgeDiagButtonsCallback', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (botões): o corpo do comando não repinta os botões ao soltar as travas" -ForegroundColor Red; $wbErrors++ }
        # O callback nasce na runspace PRINCIPAL, como todos os outros que a thread da janela roda.
        if ($sync.WinForgeDiagButtonsCallback -isnot [scriptblock]) { Write-Host "  [ERRO] Correções (botões): `$sync.WinForgeDiagButtonsCallback não é um scriptblock de arquivo" -ForegroundColor Red; $wbErrors++ }
        # E o comportamento, com dois botões de mentira: ligada a trava, desabilitam; solta, voltam.
        $wfBotAntesProc = $sync.ProcessRunning
        $wfBotA = New-Object System.Windows.Controls.Button
        $wfBotB = New-Object System.Windows.Controls.Button
        $wfBotSalvoA = $sync['WPFDiagApplySelected']
        $wfBotSalvoB = $sync['WPFDiagUndoSelected']
        $sync['WPFDiagApplySelected'] = $wfBotA
        $sync['WPFDiagUndoSelected'] = $wfBotB
        try {
            $sync.ProcessRunning = $true
            & $sync.WinForgeDiagButtonsCallback
            if ($wfBotA.IsEnabled -or $wfBotB.IsEnabled) { Write-Host "  [ERRO] Correções (botões): com `$sync.ProcessRunning ligado os botões continuaram habilitados" -ForegroundColor Red; $wbErrors++ }
            $sync.ProcessRunning = $false
            & $sync.WinForgeDiagButtonsCallback
            if (-not $wfBotA.IsEnabled -or -not $wfBotB.IsEnabled) { Write-Host "  [ERRO] Correções (botões): com a trava solta os botões não voltaram a habilitar" -ForegroundColor Red; $wbErrors++ }
        } finally {
            $sync['WPFDiagApplySelected'] = $wfBotSalvoA
            $sync['WPFDiagUndoSelected'] = $wfBotSalvoB
            $sync.ProcessRunning = $wfBotAntesProc
        }
        Write-Host "  Correções (botões): 'Aplicar/Desfazer marcados' seguem a trava de processo no início e no fim do comando"
    } catch {
        Write-Host "  [ERRO] Correções (botões): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 8c. O 'Requires' das sete linhas com fluxo ao vivo era dado morto: só Invoke-WinForgeCommandCore
    # o consultava, e ele não passa por aqui. Num SKU sem w32tm.exe a falta virava exceção de
    # Start-Process dentro do runspace, depois de a janela já ter aberto e as travas já terem sido
    # tomadas - em vez da frase que a máquina de comandos tem para isso.
    try {
        $wfReqFonte = [string](Get-Command Start-WinForgeStreamedCommand).ScriptBlock
        if ($wfReqFonte.IndexOf('Test-WinForgeCommandRequirement -Requires', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Correções (ferramenta): Start-WinForgeStreamedCommand não confere o 'Requires' da linha" -ForegroundColor Red; $wbErrors++ }
        else {
            # E confere ANTES de tomar as travas: recusar depois deixaria as duas presas.
            $wfReqPosCheck = $wfReqFonte.IndexOf('Test-WinForgeCommandRequirement -Requires', [StringComparison]::Ordinal)
            $wfReqPosTrava = $wfReqFonte.IndexOf('$sync.CommandRunning = $true', [StringComparison]::Ordinal)
            if ($wfReqPosTrava -ge 0 -and $wfReqPosCheck -gt $wfReqPosTrava) { Write-Host "  [ERRO] Correções (ferramenta): o 'Requires' é conferido DEPOIS de tomar as travas" -ForegroundColor Red; $wbErrors++ }
        }
        # A função que responde: caminho absoluto que existe passa, caminho absoluto que não existe
        # não passa, vazio é sempre sim.
        if (-not (Test-WinForgeCommandRequirement -Requires (Get-WinForgeSystemExe -Name 'icacls.exe'))) { Write-Host "  [ERRO] Correções (ferramenta): o icacls.exe desta máquina foi dado como ausente" -ForegroundColor Red; $wbErrors++ }
        if (Test-WinForgeCommandRequirement -Requires (Join-Path ([string][Environment]::SystemDirectory) 'ferramenta-que-nao-existe.exe')) { Write-Host "  [ERRO] Correções (ferramenta): uma ferramenta inexistente foi dada como presente" -ForegroundColor Red; $wbErrors++ }
        $wfReqN = 0
        foreach ($wfReqNome in $wfStrNomes) {
            $wfReqSpec = Get-WinForgeRepairCommand -Name $wfReqNome
            if ([string]::IsNullOrWhiteSpace([string]$wfReqSpec.Requires)) { continue }
            $wfReqN++
            if (-not (Test-WinForgeCommandRequirement -Requires ([string]$wfReqSpec.Requires))) { Write-Host "  [ERRO] Correções (ferramenta): '$($wfReqSpec.Requires)' de $wfReqNome não existe nesta máquina" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Correções (ferramenta): 'Requires' conferido antes das travas; $wfReqN linha(s) com exigência, todas presentes nesta máquina"
    } catch {
        Write-Host "  [ERRO] Correções (ferramenta): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # ---------------------------------------------------------------- Permissões do disco do sistema
    # O caso real: uma atualização de fabricante derrubou a cadeia de permissões do disco do Windows,
    # e o dono da máquina ficou sem acesso às próprias pastas. São três botões - Verificar (só lê),
    # Restaurar padrões (chkdsk, backup, raiz, pasta a pasta, perfil, com takeown só em acesso
    # negado) e Desfazer (icacls /restore do conjunto de backup mais novo).
    #
    # Nenhum caminho REAL do sistema é escrito aqui: nada deste bloco roda icacls, takeown ou
    # chkdsk contra a raiz, uma pasta do sistema ou o perfil. O que roda de verdade é a LEITURA
    # (Get-Acl, somente leitura) e a comparação, que é função pura exercitada com listas de
    # permissão montadas na memória - é assim que dá para provar "acusa ACE faltando" e "acusa dono
    # errado" sem estragar as permissões da máquina de quem compila para depois consertá-las.
    #
    # A única exceção é o teste de SINTAXE (bloco 3b): ele roda as strings de concessão do plano
    # contra pastas descartáveis em %TEMP%, com o alvo trocado. Sem ele, um erro de sintaxe do
    # icacls (direito específico sem parênteses é código 87, "Parâmetro inválido") só apareceria na
    # máquina de quem clicou no botão - foi assim que 'AD' virou '(AD)'.
    $wfAclNomes = @('AclVerify', 'AclRestore', 'AclUndo', 'AclCleanup')
    # 1. A comparação. Ela é quem decide o veredito, e as três DACLs abaixo são o gabarito dela:
    # uma completa (nenhuma diferença), uma sem a ACE do SYSTEM e uma com o dono trocado.
    try {
        $wfAclSid = Get-WinForgeAclWellKnownSid
        $wfAclSystem = New-Object System.Security.Principal.SecurityIdentifier ([string]$wfAclSid.Sistema)
        $wfAclAdmin = New-Object System.Security.Principal.SecurityIdentifier ([string]$wfAclSid.Administradores)
        $wfAclUsers = New-Object System.Security.Principal.SecurityIdentifier ([string]$wfAclSid.Usuarios)
        $wfAclEsperado = @{
            Path  = 'C:\PastaSinteticaDoSelfTest'
            Nome  = 'pasta sintética do SelfTest'
            Donos = @([string]$wfAclSid.Sistema, [string]$wfAclSid.Administradores)
            Aces  = @(
                @{ Sid = [string]$wfAclSid.Sistema;         Rights = [int][System.Security.AccessControl.FileSystemRights]::FullControl;    Rotulo = 'SYSTEM: controle total' }
                @{ Sid = [string]$wfAclSid.Administradores; Rights = [int][System.Security.AccessControl.FileSystemRights]::FullControl;    Rotulo = 'Administradores: controle total' }
                @{ Sid = [string]$wfAclSid.Usuarios;        Rights = [int][System.Security.AccessControl.FileSystemRights]::ReadAndExecute; Rotulo = 'Usuários: ler e executar' }
            )
        }
        $wfAclMonta = {
            param($Dono, $Regras)
            $sd = New-Object System.Security.AccessControl.DirectorySecurity
            $sd.SetOwner($Dono)
            foreach ($r in @($Regras)) {
                $sd.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $r[0], $r[1], 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            }
            return $sd
        }
        $wfAclTodas = @(@($wfAclSystem, 'FullControl'), @($wfAclAdmin, 'FullControl'), @($wfAclUsers, 'ReadAndExecute'))
        $wfAclBoa = & $wfAclMonta $wfAclSystem $wfAclTodas
        $wfAclDifBoa = @(Compare-WinForgeAclExpected -Acl $wfAclBoa -Expected $wfAclEsperado)
        if ($wfAclDifBoa.Count) { Write-Host "  [ERRO] Permissões (comparação): a DACL completa deveria dar zero diferença, deu $($wfAclDifBoa.Count) ('$($wfAclDifBoa -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        # (b) sem a ACE do SYSTEM - é a falta que deixa o Windows sem acesso à própria pasta.
        $wfAclSemSystem = & $wfAclMonta $wfAclSystem @(@($wfAclAdmin, 'FullControl'), @($wfAclUsers, 'ReadAndExecute'))
        $wfAclDifSem = @(Compare-WinForgeAclExpected -Acl $wfAclSemSystem -Expected $wfAclEsperado)
        if ($wfAclDifSem.Count -ne 1) { Write-Host "  [ERRO] Permissões (comparação): sem a ACE do SYSTEM esperava 1 diferença, veio $($wfAclDifSem.Count) ('$($wfAclDifSem -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfAclDifSem[0] -notmatch 'SYSTEM') { Write-Host "  [ERRO] Permissões (comparação): a diferença não diz que falta o SYSTEM ('$($wfAclDifSem[0])')" -ForegroundColor Red; $wbErrors++ }
        # (c) dono trocado, DACL inteira: uma coisa só, e é o dono.
        $wfAclDonoRuim = & $wfAclMonta $wfAclUsers $wfAclTodas
        $wfAclDifDono = @(Compare-WinForgeAclExpected -Acl $wfAclDonoRuim -Expected $wfAclEsperado)
        if ($wfAclDifDono.Count -ne 1) { Write-Host "  [ERRO] Permissões (comparação): dono errado esperava 1 diferença, veio $($wfAclDifDono.Count) ('$($wfAclDifDono -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfAclDifDono[0] -notmatch 'dono') { Write-Host "  [ERRO] Permissões (comparação): a diferença não fala do dono ('$($wfAclDifDono[0])')" -ForegroundColor Red; $wbErrors++ }
        # (d) os bits GENÉRICOS. Uma ACE herdável de "somente herança" guarda GENERIC_READ/WRITE/
        # EXECUTE (0xE0010000 é a forma genérica de 'Modify'), e não os bits de arquivo. Sem traduzir
        # os quatro bits, a conferência acusaria permissão faltando numa pasta impecável - a raiz do
        # C: desta máquina tem exatamente essa ACE para os Usuários Autenticados.
        $wfAclGen = ConvertTo-WinForgeAclMask -Rights ([int]-536805376)
        $wfAclMod = ConvertTo-WinForgeAclMask -Rights ([int][System.Security.AccessControl.FileSystemRights]::Modify)
        if (($wfAclGen -band $wfAclMod) -ne $wfAclMod) { Write-Host "  [ERRO] Permissões (máscara): 0xE0010000 deveria conter 'Modify' depois de traduzido (genérica=$wfAclGen, modify=$wfAclMod)" -ForegroundColor Red; $wbErrors++ }
        # (e) ACE de NEGAÇÃO sobre uma DACL impecável. É o caso que some se a comparação só somar as
        # permissões: as três ACEs certas continuam lá, e o acesso está trancado assim mesmo.
        $wfAclComDeny = & $wfAclMonta $wfAclSystem $wfAclTodas
        $wfAclComDeny.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Deny'))
        $wfAclDifDeny = @(Compare-WinForgeAclExpected -Acl $wfAclComDeny -Expected $wfAclEsperado)
        if ($wfAclDifDeny.Count -ne 1) { Write-Host "  [ERRO] Permissões (negação): uma DACL completa com um Deny esperava 1 diferença, veio $($wfAclDifDeny.Count) ('$($wfAclDifDeny -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfAclDifDeny[0] -notmatch 'nega') { Write-Host "  [ERRO] Permissões (negação): a diferença não fala em negação ('$($wfAclDifDeny[0])')" -ForegroundColor Red; $wbErrors++ }
        # E a decisão do '/remove:d': ele só roda quando um dos SIDs procurados está negado.
        $wfAclNegados = @(Get-WinForgeAclDenySid -Acl $wfAclComDeny -Sids @('S-1-5-21-11-22-33-1001', 'S-1-1-0', 'S-1-5-11'))
        if ($wfAclNegados.Count -ne 1) { Write-Host "  [ERRO] Permissões (negação): esperava 1 SID negado, veio $($wfAclNegados.Count) ('$($wfAclNegados -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfAclNegados[0] -ne 'S-1-1-0') { Write-Host "  [ERRO] Permissões (negação): o SID negado deveria ser 'S-1-1-0', veio '$($wfAclNegados[0])'" -ForegroundColor Red; $wbErrors++ }
        $wfAclSemNeg = @(Get-WinForgeAclDenySid -Acl $wfAclBoa -Sids @('S-1-5-21-11-22-33-1001', 'S-1-1-0', 'S-1-5-11'))
        if ($wfAclSemNeg.Count) { Write-Host "  [ERRO] Permissões (negação): uma DACL sem Deny devolveu $($wfAclSemNeg.Count) SID(s) negado(s) - o '/remove:d' rodaria à toa" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (comparação): DACL completa=0 diferença, sem SYSTEM=1, dono trocado=1, negação=1, bits genéricos traduzidos"
    } catch {
        Write-Host "  [ERRO] Permissões (comparação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 2. O relatório rodando DE VERDADE nesta máquina. É leitura pura (Get-Acl) e é o conteúdo do
    # único dos três botões que despacha sem perguntar - um texto vazio seria uma janela em branco.
    try {
        $wfAclFonteRel = [string](Get-Command Get-WinForgeAclReport).ScriptBlock
        foreach ($wfAclProibido in @('Set-Acl', 'icacls', 'secedit', 'takeown', 'SetAccessControl')) {
            if ($wfAclFonteRel.IndexOf($wfAclProibido, [StringComparison]::OrdinalIgnoreCase) -ge 0) { Write-Host "  [ERRO] Permissões (verificação): Get-WinForgeAclReport cita '$wfAclProibido' e tem de ser só leitura" -ForegroundColor Red; $wbErrors++ }
        }
        $wfAclRel = Get-WinForgeAclReport -AsObject
        if ($null -eq $wfAclRel) { Write-Host "  [ERRO] Permissões (verificação): -AsObject não devolveu nada" -ForegroundColor Red; $wbErrors++ }
        else {
            if ([string]::IsNullOrWhiteSpace([string]$wfAclRel.Text)) { Write-Host "  [ERRO] Permissões (verificação): relatório sem texto" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfAclRel.Text -notmatch 'Veredito') { Write-Host "  [ERRO] Permissões (verificação): o texto não termina com um veredito" -ForegroundColor Red; $wbErrors++ }
            if ($wfAclRel.Differences -isnot [int]) { Write-Host "  [ERRO] Permissões (verificação): o veredito deveria ser um número, veio '$($wfAclRel.Differences)'" -ForegroundColor Red; $wbErrors++ }
            elseif ([int]$wfAclRel.Differences -lt 0) { Write-Host "  [ERRO] Permissões (verificação): veredito negativo ($($wfAclRel.Differences))" -ForegroundColor Red; $wbErrors++ }
            if (@($wfAclRel.Items).Count -lt 6) { Write-Host "  [ERRO] Permissões (verificação): $(@($wfAclRel.Items).Count) pasta(s) no relatório, esperado ao menos 6" -ForegroundColor Red; $wbErrors++ }
            # Sem -AsObject o botão recebe TEXTO: um hashtable na janela de saída viraria 'System.Collections.Hashtable'.
            $wfAclTexto = Get-WinForgeAclReport
            if ($wfAclTexto -isnot [string]) { Write-Host "  [ERRO] Permissões (verificação): sem -AsObject o relatório deveria ser texto, veio '$($wfAclTexto.GetType().Name)'" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Permissões (verificação): $(@($wfAclRel.Items).Count) pasta(s) lidas, veredito $($wfAclRel.Differences) diferença(s), $($wfAclTexto.Length) caractere(s) de texto" }
        }
    } catch {
        Write-Host "  [ERRO] Permissões (verificação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 3. O plano de restauração. Nenhum passo roda: o que se confere é a ORDEM das seis fases, o
    # caminho completo de cada executável e o fato de todo direito concedido sair por SID.
    try {
        $wfAclSys = [string][Environment]::SystemDirectory
        $wfAclRaiz = Get-WinForgeSystemDriveRoot
        $wfAclSistemaNomes = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Users\Public')
        $wfAclProtegidas = @($wfAclRaiz.TrimEnd('\')) + @($wfAclSistemaNomes | ForEach-Object { (Join-Path $wfAclRaiz $_).TrimEnd('\') })
        $wfAclPlano = @(Get-WinForgeAclRestorePlan -Profile 'C:\Users\PerfilDeTeste' -UserSid 'S-1-5-21-11-22-33-1001' -BackupRoot 'C:\ProgramData\WinForge\acl-backup' -Stamp '20260911-120000')
        if ($wfAclPlano.Count -lt 6) { Write-Host "  [ERRO] Permissões (plano): $($wfAclPlano.Count) passo(s), esperado ao menos 6" -ForegroundColor Red; $wbErrors++ }
        $wfAclFases = @($wfAclPlano | ForEach-Object { [int]$_.Phase })
        for ($wfAclI = 1; $wfAclI -lt $wfAclFases.Count; $wfAclI++) {
            if ($wfAclFases[$wfAclI] -lt $wfAclFases[$wfAclI - 1]) { Write-Host "  [ERRO] Permissões (plano): fase $($wfAclFases[$wfAclI]) depois da fase $($wfAclFases[$wfAclI - 1]) - a ordem é dependência, não gosto" -ForegroundColor Red; $wbErrors++; break }
        }
        foreach ($wfAclFase in 1..6) {
            if ($wfAclFase -notin $wfAclFases) { Write-Host "  [ERRO] Permissões (plano): falta a fase $wfAclFase" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($wfAclPasso in $wfAclPlano) {
            if ([string]::IsNullOrWhiteSpace([string]$wfAclPasso.Title)) { Write-Host "  [ERRO] Permissões (plano): passo da fase $($wfAclPasso.Phase) sem título" -ForegroundColor Red; $wbErrors++ }
            # Dois passos não chamam executável nenhum: o 'sddl' lê a DACL e o dono da pasta e grava
            # no índice, e o 'scope' é a caminhada que o MOTOR faz. A trava cobra isso dos dois
            # lados - sem FilePath tem de ser um desses dois, e nenhum deles pode ter FilePath.
            if (@('sddl', 'scope') -contains [string]$wfAclPasso.Kind) {
                if (-not [string]::IsNullOrWhiteSpace([string]$wfAclPasso.FilePath)) { Write-Host "  [ERRO] Permissões (plano): o passo '$($wfAclPasso.Kind)' de '$($wfAclPasso.Path)' traz um executável ('$($wfAclPasso.FilePath)')" -ForegroundColor Red; $wbErrors++ }
                if ($null -ne $wfAclPasso.Arguments) { Write-Host "  [ERRO] Permissões (plano): o passo '$($wfAclPasso.Kind)' de '$($wfAclPasso.Path)' traz argumentos" -ForegroundColor Red; $wbErrors++ }
                if ([string]::IsNullOrWhiteSpace([string]$wfAclPasso.Path)) { Write-Host "  [ERRO] Permissões (plano): passo '$($wfAclPasso.Kind)' sem pasta" -ForegroundColor Red; $wbErrors++ }
                continue
            }
            # O terceiro sem executável, e pelo mesmo motivo: as chamadas do 'inherit-list' saem de
            # Get-WinForgeAclInheritSteps, uma por pasta da lista que a fase 2 guardou. Um FilePath
            # ou um vetor aqui seria o '/T' voltando pela porta dos fundos, agora sem nem a trava
            # de '/T ⇒ /L' abaixo, que só olha vetor de argumentos.
            if ([string]$wfAclPasso.Kind -eq 'inherit-list') {
                if (-not [string]::IsNullOrWhiteSpace([string]$wfAclPasso.FilePath)) { Write-Host "  [ERRO] Permissões (plano): o passo 'inherit-list' de '$($wfAclPasso.Folder)' traz um executável ('$($wfAclPasso.FilePath)')" -ForegroundColor Red; $wbErrors++ }
                if ($null -ne $wfAclPasso.Arguments) { Write-Host "  [ERRO] Permissões (plano): o passo 'inherit-list' de '$($wfAclPasso.Folder)' traz argumentos - a lista é que manda as chamadas" -ForegroundColor Red; $wbErrors++ }
                if ([string]::IsNullOrWhiteSpace([string]$wfAclPasso.Folder)) { Write-Host "  [ERRO] Permissões (plano): passo 'inherit-list' sem pasta" -ForegroundColor Red; $wbErrors++ }
                continue
            }
            $wfAclExe = [string]$wfAclPasso.FilePath
            if ([string]::IsNullOrWhiteSpace($wfAclExe)) { Write-Host "  [ERRO] Permissões (plano): passo '$($wfAclPasso.Title)' sem executável e sem ser do tipo 'sddl', 'scope' ou 'inherit-list'" -ForegroundColor Red; $wbErrors++; continue }
            if (-not [System.IO.Path]::IsPathRooted($wfAclExe)) { Write-Host "  [ERRO] Permissões (plano): '$wfAclExe' não é caminho completo" -ForegroundColor Red; $wbErrors++ }
            elseif (-not $wfAclExe.StartsWith($wfAclSys, [StringComparison]::OrdinalIgnoreCase)) { Write-Host "  [ERRO] Permissões (plano): '$wfAclExe' fora de '$wfAclSys'" -ForegroundColor Red; $wbErrors++ }
            elseif (-not (Test-Path -LiteralPath $wfAclExe -PathType Leaf)) { Write-Host "  [ERRO] Permissões (plano): '$wfAclExe' não existe nesta máquina" -ForegroundColor Red; $wbErrors++ }
            foreach ($wfAclArg in @($wfAclPasso.Arguments)) {
                $wfAclA = [string]$wfAclArg
                # Direito concedido é sempre '<sid>:<permissão>', e o sid de icacls vem com '*'. Nome
                # localizado ('Administradores:(OI)(CI)F') quebraria em qualquer Windows em inglês.
                if ((-not $wfAclA.StartsWith('/', [StringComparison]::Ordinal)) -and ($wfAclA.IndexOf(':', [StringComparison]::Ordinal) -ge 0) -and (-not [System.IO.Path]::IsPathRooted($wfAclA)) -and (-not $wfAclA.StartsWith('*S-', [StringComparison]::Ordinal))) { Write-Host "  [ERRO] Permissões (plano): '$wfAclA' concede direito sem usar SID" -ForegroundColor Red; $wbErrors++ }
                if ($wfAclA -eq '/R') { Write-Host "  [ERRO] Permissões (plano): '/R' (recursivo do takeown) é proibido" -ForegroundColor Red; $wbErrors++ }
            }
            $wfAclArgs = @($wfAclPasso.Arguments | ForEach-Object { [string]$_ })
            if ((Split-Path -Leaf ([string]$wfAclPasso.FilePath)) -eq 'secedit.exe') { Write-Host "  [ERRO] Permissões (plano): o secedit voltou ao plano - no Windows 10 e 11 o defltbase.inf tem [File Security] e [Registry Keys] vazias e não repõe DACL nenhuma" -ForegroundColor Red; $wbErrors++ }
            # Dentro de um mesmo '/grant' o icacls guarda só a ÚLTIMA entrada de cada SID: duas
            # linhas do mesmo SID na mesma chamada viram uma ACE, e a outra some sem erro nenhum.
            if (($wfAclArgs -contains '/grant') -or ($wfAclArgs -contains '/grant:r')) {
                $wfAclSids = @($wfAclArgs | Where-Object { $_.StartsWith('*S-', [StringComparison]::Ordinal) } | ForEach-Object { ($_ -split ':', 2)[0] })
                $wfAclDup = @($wfAclSids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
                if ($wfAclDup.Count) { Write-Host "  [ERRO] Permissões (plano): '$($wfAclDup -join ', ')' aparece duas vezes no mesmo /grant de '$($wfAclPasso.Title)' - o icacls guardaria só a última" -ForegroundColor Red; $wbErrors++ }
            }
            # '/reset', '/T' e '/R' apontados para a raiz ou para uma pasta do sistema descem a
            # árvore inteira apagando o que o Windows sabe e o WinForge não.
            # '/T' desce a árvore SEGUINDO ponto de reanálise: dentro de um perfil isso é OneDrive,
            # pasta redirecionada e junção de compatibilidade, que apontam para fora (às vezes para
            # outro volume). '/L' manda trabalhar no LINK. Onde houver um, tem de haver o outro.
            if (($wfAclArgs -contains '/T') -and ($wfAclArgs -notcontains '/L')) { Write-Host "  [ERRO] Permissões (plano): '$($wfAclPasso.Title)' usa '/T' sem '/L' - a caminhada sai do alvo pelo primeiro ponto de reanálise" -ForegroundColor Red; $wbErrors++ }
            $wfAclAlvoPasso = ([string]@($wfAclPasso.Arguments)[0]).TrimEnd('\')
            if ($wfAclProtegidas -contains $wfAclAlvoPasso) {
                foreach ($wfAclFlag in @('/reset', '/T', '/R')) {
                    if ($wfAclArgs -contains $wfAclFlag) { Write-Host "  [ERRO] Permissões (plano): '$wfAclFlag' apontado para '$wfAclAlvoPasso' - ali só valem '/setowner' e '/inheritance:r /grant:r' na própria pasta" -ForegroundColor Red; $wbErrors++ }
                }
            }
        }
        # A fase 2 tem dois tipos de passo. O 'sddl' guarda a lista e o dono da PRÓPRIA pasta no
        # índice, e existe para toda pasta do conjunto - foi medido, elevado, que
        # 'icacls <pasta>\ /save' grava a entrada da própria pasta com o NOME VAZIO e que o
        # '/restore' NÃO a aplica (procura '<pasta>\<sddl>' e responde "arquivo não encontrado").
        # O 'scope' guarda o CONTEÚDO num arquivo no formato do icacls, escrito pelo MOTOR, e só o
        # perfil tem um: é a única pasta em que a restauração mexe no que está DENTRO (fase 5).
        $wfAclSddl = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'sddl' })
        $wfAclBk = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'scope' })
        $wfAclF2Outros = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 2 -and @('sddl', 'scope') -notcontains [string]$_.Kind })
        if ($wfAclF2Outros.Count) { Write-Host "  [ERRO] Permissões (plano): a fase 2 tem $($wfAclF2Outros.Count) passo(s) de tipo desconhecido ('$(@($wfAclF2Outros | ForEach-Object { [string]$_.Kind }) -join ', ')')" -ForegroundColor Red; $wbErrors++ }
        if ($wfAclSddl.Count -lt 2) { Write-Host "  [ERRO] Permissões (plano): a fase 2 guarda $($wfAclSddl.Count) lista(s) em SDDL, esperado a raiz, as pastas de primeiro nível, as aninhadas e o perfil" -ForegroundColor Red; $wbErrors++ }
        if ($wfAclBk.Count -ne 1) { Write-Host "  [ERRO] Permissões (plano): a fase 2 deveria ter exatamente um backup de conteúdo (o do perfil), tem $($wfAclBk.Count)" -ForegroundColor Red; $wbErrors++ }
        # A raiz NÃO pode ter arquivo de conteúdo: o '/restore' dela nunca aplicou nada, e manter o
        # passo era prometer um desfazer que não existe.
        if (@($wfAclBk | Where-Object { ([string]$_.Path).TrimEnd('\') -eq $wfAclRaiz.TrimEnd('\') }).Count) { Write-Host "  [ERRO] Permissões (plano): a raiz voltou a ter backup de conteúdo - o '/restore' da raiz não aplica a entrada de nome vazio" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfAclPasso in $wfAclBk) {
            if ([string]::IsNullOrWhiteSpace([string]$wfAclPasso.Backup)) { Write-Host "  [ERRO] Permissões (plano): passo de backup sem arquivo de destino" -ForegroundColor Red; $wbErrors++ }
            elseif (-not ([string]$wfAclPasso.Backup).StartsWith('C:\ProgramData\WinForge\acl-backup\', [StringComparison]::OrdinalIgnoreCase)) { Write-Host "  [ERRO] Permissões (plano): backup fora da pasta protegida ('$($wfAclPasso.Backup)')" -ForegroundColor Red; $wbErrors++ }
            elseif (([string]$wfAclPasso.Backup).IndexOf('20260911-120000', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (plano): o nome do backup não carrega o carimbo de tempo ('$($wfAclPasso.Backup)')" -ForegroundColor Red; $wbErrors++ }
            if ([string]::IsNullOrWhiteSpace([string]$wfAclPasso.Target)) { Write-Host "  [ERRO] Permissões (plano): backup sem a pasta de destino do /restore" -ForegroundColor Red; $wbErrors++ }
        }
        # O destino do /restore é a pasta a partir da qual o icacls gravou os nomes relativos: a
        # pasta ACIMA do perfil. Medido: o arquivo começa com a entrada do próprio perfil, e não
        # com a entrada de nome vazio que aparece quando o alvo é a mesma pasta da invocação.
        $wfAclAlvoPerfil = @($wfAclBk | Where-Object { [string]$_.Path -eq 'C:\Users\PerfilDeTeste' })
        if ($wfAclAlvoPerfil.Count -ne 1) { Write-Host "  [ERRO] Permissões (plano): o perfil deveria ter exatamente um backup de conteúdo, tem $($wfAclAlvoPerfil.Count)" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfAclAlvoPerfil[0].Target -ne 'C:\Users') { Write-Host "  [ERRO] Permissões (plano): o /restore do perfil deveria mirar 'C:\Users', mira '$($wfAclAlvoPerfil[0].Target)'" -ForegroundColor Red; $wbErrors++ }
        # Toda pasta que a fase 3 ou a fase 4 reescreve TEM de ter a lista DELA MESMA guardada na
        # fase 2, e é isso que o Desfazer reaplica. 'Users\Public' é o caso que a listagem de
        # primeiro nível não alcança; a raiz é o caso que o '/save' nunca soube desfazer.
        $wfAclSddlPorPasta = @{}
        foreach ($wfAclPasso in $wfAclSddl) { $wfAclSddlPorPasta[([string]$wfAclPasso.Path).TrimEnd('\')] = $wfAclPasso }
        foreach ($wfAclPastaP in (@($wfAclRaiz.TrimEnd('\')) + @($wfAclSistemaNomes | ForEach-Object { (Join-Path $wfAclRaiz $_).TrimEnd('\') }) + @('C:\Users\PerfilDeTeste'))) {
            if (-not $wfAclSddlPorPasta.ContainsKey($wfAclPastaP)) { Write-Host "  [ERRO] Permissões (plano): a restauração reescreve '$wfAclPastaP' e a fase 2 não guarda a lista dela em SDDL - o Desfazer não devolveria essa pasta" -ForegroundColor Red; $wbErrors++ }
        }
        $wfAclBkNomes = @($wfAclBk | ForEach-Object { [string](Split-Path -Leaf ([string]$_.Backup)) })
        $wfAclBkDup = @($wfAclBkNomes | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        if ($wfAclBkDup.Count) { Write-Host "  [ERRO] Permissões (plano): '$($wfAclBkDup -join ', ')' é o nome de dois backups - um sobrescreveria o outro e o índice apontaria duas pastas para o mesmo arquivo" -ForegroundColor Red; $wbErrors++ }
        $wfAclSddlDup = @(@($wfAclSddl | ForEach-Object { ([string]$_.Path).TrimEnd('\') }) | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        if ($wfAclSddlDup.Count) { Write-Host "  [ERRO] Permissões (plano): '$($wfAclSddlDup -join ', ')' aparece duas vezes na fase 2 - o índice teria duas entradas para a mesma pasta" -ForegroundColor Red; $wbErrors++ }
        # Fase 3: a segunda ACE dos Usuários Autenticados na raiz sai numa chamada PRÓPRIA.
        $wfAclRaizGrant = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 3 -and [string]$_.Kind -eq 'grant' })
        $wfAclRaizExtra = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 3 -and [string]$_.Kind -eq 'grant-extra' })
        if ($wfAclRaizGrant.Count -ne 1) { Write-Host "  [ERRO] Permissões (plano): a fase 3 deveria ter uma concessão, tem $($wfAclRaizGrant.Count)" -ForegroundColor Red; $wbErrors++ }
        if ($wfAclRaizExtra.Count -ne 1) { Write-Host "  [ERRO] Permissões (plano): '*S-1-5-11:(AD)' tem de sair numa chamada separada da raiz" -ForegroundColor Red; $wbErrors++ }
        elseif (@($wfAclRaizExtra[0].Arguments | ForEach-Object { [string]$_ }) -notcontains '*S-1-5-11:(AD)') { Write-Host "  [ERRO] Permissões (plano): a chamada separada da raiz não concede '*S-1-5-11:(AD)' - direito específico sem parênteses é código 87" -ForegroundColor Red; $wbErrors++ }
        # Fase 4: cada pasta do sistema, na PRÓPRIA pasta, com '/setowner' condicional e a tabela de
        # esperados. O secedit foi medido e não repõe nada no Windows 10/11 - ele não volta.
        $wfAclF4 = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 4 })
        $wfAclF4Pastas = @($wfAclF4 | ForEach-Object { ([string]$_.Folder).TrimEnd('\') } | Sort-Object -Unique)
        foreach ($wfAclNomeP in $wfAclSistemaNomes) {
            $wfAclEsperadaP = (Join-Path $wfAclRaiz $wfAclNomeP).TrimEnd('\')
            if ($wfAclF4Pastas -notcontains $wfAclEsperadaP) { Write-Host "  [ERRO] Permissões (plano): a fase 4 não cobre '$wfAclEsperadaP'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfAclF4Pastas.Count -ne $wfAclSistemaNomes.Count) { Write-Host "  [ERRO] Permissões (plano): a fase 4 mexe em $($wfAclF4Pastas.Count) pasta(s), esperado $($wfAclSistemaNomes.Count)" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfAclPasso in $wfAclF4) {
            $wfAclArgs4 = @($wfAclPasso.Arguments | ForEach-Object { [string]$_ })
            if (([string]@($wfAclPasso.Arguments)[0]).TrimEnd('\') -ne ([string]$wfAclPasso.Folder).TrimEnd('\')) { Write-Host "  [ERRO] Permissões (plano): o passo '$($wfAclPasso.Title)' não aponta para a própria pasta" -ForegroundColor Red; $wbErrors++ }
            switch ([string]$wfAclPasso.Kind) {
                'setowner' {
                    if (-not $wfAclPasso.Conditional) { Write-Host "  [ERRO] Permissões (plano): o '/setowner' de '$($wfAclPasso.Folder)' tem de ser condicional (só com o dono fora do padrão)" -ForegroundColor Red; $wbErrors++ }
                    if ($wfAclArgs4 -notcontains '/setowner') { Write-Host "  [ERRO] Permissões (plano): passo 'setowner' sem '/setowner'" -ForegroundColor Red; $wbErrors++ }
                }
                'grant' {
                    foreach ($wfAclEsp4 in @('/inheritance:r', '/grant:r')) {
                        if ($wfAclArgs4 -notcontains $wfAclEsp4) { Write-Host "  [ERRO] Permissões (plano): a concessão de '$($wfAclPasso.Folder)' sem '$wfAclEsp4'" -ForegroundColor Red; $wbErrors++ }
                    }
                }
                'grant-extra' {
                    if ($wfAclArgs4 -contains '/grant:r') { Write-Host "  [ERRO] Permissões (plano): a segunda chamada de '$($wfAclPasso.Folder)' usa '/grant:r' e apagaria a primeira" -ForegroundColor Red; $wbErrors++ }
                }
                'setowner-socorro' {
                    if (-not $wfAclPasso.Conditional) { Write-Host "  [ERRO] Permissões (plano): a posse de socorro de '$($wfAclPasso.Folder)' tem de ser condicional (só com acesso negado)" -ForegroundColor Red; $wbErrors++ }
                    if ($wfAclArgs4 -notcontains '*S-1-5-32-544') { Write-Host "  [ERRO] Permissões (plano): a posse de socorro de '$($wfAclPasso.Folder)' deveria ir para os Administradores" -ForegroundColor Red; $wbErrors++ }
                }
                'setowner-devolver' {
                    if (-not $wfAclPasso.Conditional) { Write-Host "  [ERRO] Permissões (plano): a devolução da posse de '$($wfAclPasso.Folder)' tem de ser condicional" -ForegroundColor Red; $wbErrors++ }
                    if ($wfAclArgs4 -contains '*S-1-5-32-544') { Write-Host "  [ERRO] Permissões (plano): a devolução da posse de '$($wfAclPasso.Folder)' deixaria os Administradores como donos" -ForegroundColor Red; $wbErrors++ }
                }
                default { Write-Host "  [ERRO] Permissões (plano): passo de tipo '$($wfAclPasso.Kind)' na fase 4" -ForegroundColor Red; $wbErrors++ }
            }
        }
        # O par de socorro existe em toda pasta da fase 4 que tem dono padrão, devolve a posse
        # EXATAMENTE para esse dono, e nunca entra na fila de execução: quem o chama é
        # Invoke-WinForgeAclOwnerFallback, e só depois de um código 5.
        foreach ($wfAclEsp4F in @(Get-WinForgeAclExpected | Where-Object { $_.Direta -and -not [string]::IsNullOrWhiteSpace([string]$_.Dono) })) {
            $wfAclPasta4F = ([string]$wfAclEsp4F.Path).TrimEnd('\')
            foreach ($wfAclTipo4F in @('setowner-socorro', 'setowner-devolver')) {
                $wfAclAchado = @($wfAclF4 | Where-Object { [string]$_.Kind -eq $wfAclTipo4F -and ([string]$_.Folder).TrimEnd('\') -eq $wfAclPasta4F })
                if ($wfAclAchado.Count -ne 1) { Write-Host "  [ERRO] Permissões (plano): '$wfAclPasta4F' deveria ter um passo '$wfAclTipo4F', tem $($wfAclAchado.Count)" -ForegroundColor Red; $wbErrors++ }
                elseif ($wfAclTipo4F -eq 'setowner-devolver' -and (@($wfAclAchado[0].Arguments | ForEach-Object { [string]$_ }) -notcontains "*$([string]$wfAclEsp4F.Dono)")) { Write-Host "  [ERRO] Permissões (plano): a devolução da posse de '$wfAclPasta4F' não repõe o dono '$($wfAclEsp4F.Dono)'" -ForegroundColor Red; $wbErrors++ }
            }
        }
        $wfAclFonteF4 = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        # A busca é pela CHAMADA ('-Plan' junto), e não pelo nome: ele também aparece no bloco de
        # ajuda da função, que passaria a trava sozinho.
        if ($wfAclFonteF4.IndexOf('Invoke-WinForgeAclOwnerFallback -Plan', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (plano): a fase 4 não chama Invoke-WinForgeAclOwnerFallback - um acesso negado em C:\Windows terminaria em erro" -ForegroundColor Red; $wbErrors++ }
        # A ordem dos três movimentos do socorro, lida do fonte: assumir a posse, repetir a
        # concessão, DEVOLVER a posse. Sem o terceiro a pasta do sistema fica com os
        # Administradores como dona e passa a aceitar alteração de qualquer processo elevado.
        $wfAclFonteFb = [string](Get-Command Invoke-WinForgeAclOwnerFallback).ScriptBlock
        $wfAclPosFb = @('$socorro[0].FilePath', '$Step.FilePath', '$devolver[0].FilePath') | ForEach-Object { $wfAclFonteFb.IndexOf($_, [StringComparison]::Ordinal) }
        if (@($wfAclPosFb | Where-Object { $_ -lt 0 }).Count) { Write-Host "  [ERRO] Permissões (socorro): a função não roda os três movimentos (posse, segunda tentativa, devolução)" -ForegroundColor Red; $wbErrors++ }
        elseif (-not ($wfAclPosFb[0] -lt $wfAclPosFb[1] -and $wfAclPosFb[1] -lt $wfAclPosFb[2])) { Write-Host "  [ERRO] Permissões (socorro): a ordem é posse -> segunda tentativa -> devolução, e o fonte está em outra" -ForegroundColor Red; $wbErrors++ }
        # Fase 5: conceder na RAIZ do perfil antes de ligar a herança do conteúdo. Ao contrário, a
        # herança propagaria o que ainda não foi concedido - e '/reset' não entra aqui, porque
        # apagaria as ACEs explícitas que os aplicativos põem dentro do perfil.
        $wfAclF5 = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 5 })
        $wfAclF5Tipos = @($wfAclF5 | ForEach-Object { [string]$_.Kind })
        $wfAclIdxGrant = [array]::IndexOf($wfAclF5Tipos, 'grant')
        $wfAclIdxHerda = [array]::IndexOf($wfAclF5Tipos, 'inherit-list')
        if ($wfAclIdxGrant -lt 0 -or $wfAclIdxHerda -lt 0) { Write-Host "  [ERRO] Permissões (plano): a fase 5 precisa da concessão na raiz do perfil e da herança do conteúdo" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfAclIdxGrant -gt $wfAclIdxHerda) { Write-Host "  [ERRO] Permissões (plano): a herança do conteúdo vem ANTES da concessão na raiz do perfil - nessa ordem ela propaga o que ainda não existe" -ForegroundColor Red; $wbErrors++ }
        else {
            # A herança mira a PASTA do perfil como escopo e nada mais: as chamadas de verdade saem
            # da lista da fase 2. Um alvo com '*' aqui, como o que existia até a 1.7.0, é o que
            # levava o '/T' para dentro de junção e OneDrive.
            if (([string]$wfAclF5[$wfAclIdxHerda].Folder).TrimEnd('\') -ne 'C:\Users\PerfilDeTeste') { Write-Host "  [ERRO] Permissões (plano): a herança do conteúdo aponta para '$($wfAclF5[$wfAclIdxHerda].Folder)', esperado o perfil" -ForegroundColor Red; $wbErrors++ }
            if (([string]$wfAclF5[$wfAclIdxHerda].Folder).IndexOf('*', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Permissões (plano): a herança do conteúdo voltou a mirar um curinga ('$($wfAclF5[$wfAclIdxHerda].Folder)')" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($wfAclPasso in $wfAclF5) {
            if (@($wfAclPasso.Arguments | ForEach-Object { [string]$_ }) -contains '/reset') { Write-Host "  [ERRO] Permissões (plano): '/reset' no perfil apagaria as ACEs explícitas dos aplicativos (AppData\Local\Packages, OneDrive)" -ForegroundColor Red; $wbErrors++ }
        }
        # As negações saem antes da concessão, na raiz e no perfil, e o passo é condicional.
        foreach ($wfAclFaseD in @(3, 5)) {
            $wfAclDeny = @($wfAclPlano | Where-Object { [int]$_.Phase -eq $wfAclFaseD -and [string]$_.Kind -eq 'remove-deny' })
            if ($wfAclDeny.Count -ne 1) { Write-Host "  [ERRO] Permissões (plano): a fase $wfAclFaseD deveria ter um passo de '/remove:d', tem $($wfAclDeny.Count)" -ForegroundColor Red; $wbErrors++ }
            elseif (-not $wfAclDeny[0].Conditional) { Write-Host "  [ERRO] Permissões (plano): o '/remove:d' da fase $wfAclFaseD tem de ser condicional (só com negação encontrada)" -ForegroundColor Red; $wbErrors++ }
            elseif (@($wfAclDeny[0].Arguments | ForEach-Object { [string]$_ } | Where-Object { $_ -eq '/remove:d' }).Count -ne 3) { Write-Host "  [ERRO] Permissões (plano): o '/remove:d' da fase $wfAclFaseD deveria cobrir os três SIDs (usuário, Todos, Autenticados)" -ForegroundColor Red; $wbErrors++ }
        }
        # Fase 6: o takeown é só da raiz, sem recursão, e só existe para o caso de acesso negado.
        $wfAclTo = @($wfAclPlano | Where-Object { [int]$_.Phase -eq 6 })
        if ($wfAclTo.Count -ne 1) { Write-Host "  [ERRO] Permissões (plano): a fase 6 deveria ter um passo, tem $($wfAclTo.Count)" -ForegroundColor Red; $wbErrors++ }
        elseif ((Split-Path -Leaf ([string]$wfAclTo[0].FilePath)) -ne 'takeown.exe') { Write-Host "  [ERRO] Permissões (plano): a fase 6 deveria chamar o takeown.exe" -ForegroundColor Red; $wbErrors++ }
        elseif (-not $wfAclTo[0].Conditional) { Write-Host "  [ERRO] Permissões (plano): o takeown tem de ser condicional (só com acesso negado na raiz)" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (plano): $($wfAclPlano.Count) passo(s) em 6 fases na ordem, executáveis por caminho completo, direitos só por SID, sem secedit"

        # A escolha das pastas da fase 4, com um relatório MONTADO: só 'Windows' acusado, e com o
        # dono fora do padrão. 'Users' está no padrão e não pode receber uma linha sequer - é aqui
        # que se prova que o botão não reescreve pasta saudável.
        $wfAclRelSint = @{
            Differences = 1
            Items       = @(
                @{ Path = (Join-Path $wfAclRaiz 'Windows');             Differences = @('falta SYSTEM podendo modificar'); Missing = $false; OwnerOk = $false }
                @{ Path = (Join-Path $wfAclRaiz 'Program Files');       Differences = @();                                 Missing = $false; OwnerOk = $true }
                @{ Path = (Join-Path $wfAclRaiz 'Program Files (x86)'); Differences = @('falta o que for');                Missing = $true;  OwnerOk = $true }
                @{ Path = (Join-Path $wfAclRaiz 'ProgramData');         Differences = @();                                 Missing = $false; OwnerOk = $false }
                @{ Path = (Join-Path $wfAclRaiz 'Users');               Differences = @();                                 Missing = $false; OwnerOk = $true }
                @{ Path = (Join-Path $wfAclRaiz 'Users\Public');        Differences = @();                                 Missing = $false; OwnerOk = $true }
            )
        }
        $wfAclEscolha = @(Select-WinForgeAclTargetedSteps -Plan $wfAclPlano -Report $wfAclRelSint)
        $wfAclEscolhaPastas = @($wfAclEscolha | ForEach-Object { ([string]$_.Folder).TrimEnd('\') } | Sort-Object -Unique)
        if ($wfAclEscolhaPastas.Count -ne 1 -or [string]$wfAclEscolhaPastas[0] -ne (Join-Path $wfAclRaiz 'Windows')) { Write-Host "  [ERRO] Permissões (escolha): esperava só '$(Join-Path $wfAclRaiz 'Windows')', veio '$($wfAclEscolhaPastas -join ', ')'" -ForegroundColor Red; $wbErrors++ }
        $wfAclEscolhaTipos = @($wfAclEscolha | ForEach-Object { [string]$_.Kind })
        # O par de socorro NUNCA entra na fila: rodá-lo sem o código 5 trocaria o dono de uma pasta
        # do sistema à toa, e o Desfazer devolve lista, não posse.
        if (@($wfAclEscolhaTipos | Where-Object { $_ -like 'setowner-*' }).Count) { Write-Host "  [ERRO] Permissões (escolha): o par de socorro de posse entrou na fila da fase 4 - ele só roda depois de um acesso negado" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfAclTipoEsp in @('setowner', 'grant', 'grant-extra')) {
            if ($wfAclEscolhaTipos -notcontains $wfAclTipoEsp) { Write-Host "  [ERRO] Permissões (escolha): a pasta acusada não recebeu o passo '$wfAclTipoEsp'" -ForegroundColor Red; $wbErrors++ }
        }
        # Mesmo relatório, mesma pasta, mas com o dono JÁ no padrão: o '/setowner' some e o resto fica.
        $wfAclRelDonoOk = @{ Differences = 1; Items = @(@{ Path = (Join-Path $wfAclRaiz 'Windows'); Differences = @('falta SYSTEM podendo modificar'); Missing = $false; OwnerOk = $true }) }
        $wfAclEscolha2 = @(Select-WinForgeAclTargetedSteps -Plan $wfAclPlano -Report $wfAclRelDonoOk)
        if (@($wfAclEscolha2 | Where-Object { [string]$_.Kind -eq 'setowner' }).Count) { Write-Host "  [ERRO] Permissões (escolha): '/setowner' escolhido numa pasta cujo dono já está no padrão" -ForegroundColor Red; $wbErrors++ }
        if ($wfAclEscolha2.Count -ne 2) { Write-Host "  [ERRO] Permissões (escolha): esperava 2 passo(s) sem o '/setowner', veio $($wfAclEscolha2.Count)" -ForegroundColor Red; $wbErrors++ }
        # Relatório limpo: a fase 4 não roda nada.
        $wfAclEscolha3 = @(Select-WinForgeAclTargetedSteps -Plan $wfAclPlano -Report @{ Differences = 0; Items = @(@{ Path = (Join-Path $wfAclRaiz 'Windows'); Differences = @(); Missing = $false; OwnerOk = $true }) })
        if ($wfAclEscolha3.Count) { Write-Host "  [ERRO] Permissões (escolha): relatório sem diferença escolheu $($wfAclEscolha3.Count) passo(s)" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (escolha): com 'Windows' acusado saem $($wfAclEscolha.Count) passo(s) só nessa pasta; dono no padrão tira o '/setowner'; relatório limpo não roda nada"
    } catch {
        Write-Host "  [ERRO] Permissões (plano): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 3a2. O apelido dos arquivos de backup tem de ser INJETIVO. O anterior trocava tudo que não
    # fosse '[A-Za-z0-9._-]' por '_', e 'Program Files' e 'Program_Files' viravam o MESMO nome:
    # qualquer Usuário Autenticado cria pasta na raiz do disco (a ACE '(AD)' que a fase 3 repõe),
    # então uma 'C:\Program_Files' plantada sem elevação sobrescrevia o backup da pasta do Windows
    # e o Desfazer devolvia a lista do invasor, calado. A prova é o par que colidia.
    try {
        $wfAclSlugPares = @(
            @('Program Files', 'Program_Files'),
            @('Program Files (x86)', 'Program_Files__x86_'),
            @('Users Public', 'Users.Public'),
            @('a b', 'a%20b')
        )
        $wfAclSlugRuins = 0
        foreach ($wfAclSlugPar in $wfAclSlugPares) {
            $wfAclSlugA = Get-WinForgeAclSlug -Text ([string]$wfAclSlugPar[0])
            $wfAclSlugB = Get-WinForgeAclSlug -Text ([string]$wfAclSlugPar[1])
            if ($wfAclSlugA -eq $wfAclSlugB) { Write-Host "  [ERRO] Permissões (apelido): '$($wfAclSlugPar[0])' e '$($wfAclSlugPar[1])' dão o MESMO apelido ('$wfAclSlugA')" -ForegroundColor Red; $wbErrors++; $wfAclSlugRuins++ }
            foreach ($wfAclSlugX in @($wfAclSlugA, $wfAclSlugB)) {
                if ($wfAclSlugX -notmatch '^[A-Za-z0-9%]*$') { Write-Host "  [ERRO] Permissões (apelido): '$wfAclSlugX' tem caractere fora de '[A-Za-z0-9%]' e não serve como nome de arquivo" -ForegroundColor Red; $wbErrors++; $wfAclSlugRuins++ }
            }
        }
        if ((Get-WinForgeAclSlug -Text 'abc123') -ne 'abc123') { Write-Host "  [ERRO] Permissões (apelido): texto já seguro não deveria mudar ('$(Get-WinForgeAclSlug -Text 'abc123')')" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeAclSlug -Text '') -ne '') { Write-Host "  [ERRO] Permissões (apelido): texto vazio deveria dar apelido vazio" -ForegroundColor Red; $wbErrors++ }
        # E o plano gerado com um perfil de nome ruim continua gravando dentro da pasta protegida.
        $wfAclSlugPlano = @(Get-WinForgeAclRestorePlan -Profile 'C:\Users\Fulano de Tal' -UserSid 'S-1-5-21-11-22-33-1001' -BackupRoot 'C:\ProgramData\WinForge\acl-backup' -Stamp '20260911-120000' | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'scope' })
        if ($wfAclSlugPlano.Count -ne 1) { Write-Host "  [ERRO] Permissões (apelido): o perfil 'Fulano de Tal' deveria dar um backup de conteúdo, deu $($wfAclSlugPlano.Count)" -ForegroundColor Red; $wbErrors++ }
        elseif ((Split-Path -Leaf ([string]$wfAclSlugPlano[0].Backup)) -notmatch '^acl-perfil-[A-Za-z0-9%]+-20260911-120000\.txt$') { Write-Host "  [ERRO] Permissões (apelido): o nome do backup do perfil saiu '$(Split-Path -Leaf ([string]$wfAclSlugPlano[0].Backup))'" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfAclSlugRuins) { Write-Host "  Permissões (apelido): $($wfAclSlugPares.Count) par(es) que colidiam no apelido antigo dão apelidos distintos" }
    } catch {
        Write-Host "  [ERRO] Permissões (apelido): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 3a3. A IDA E A VOLTA do SDDL, numa pasta descartável de %TEMP%. É a peça nova do Desfazer: a
    # lista da PRÓPRIA pasta não volta pelo 'icacls /restore'. Medido, elevado:
    # 'icacls <pasta>\ /save f /C' grava a entrada da própria pasta com o NOME VAZIO, e
    # 'icacls <pasta>\ /restore f /C /L' não a aplica - monta '<pasta>\<sddl>' e responde "arquivo
    # não encontrado", deixando a DACL alterada como estava. Aqui a pasta é mexida e devolvida, e a
    # igualdade é cobrada no texto do descritor. Sem elevação isto roda: a pasta é de %TEMP% e o
    # dono é a própria identidade. O '/restore' do CONTEÚDO do perfil continua fora do SelfTest -
    # ele precisa de SeRestorePrivilege e mora no plano, que o -DryRun lista sem rodar.
    try {
        $wfAclRtRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\sddl-ida-e-volta'
        New-Item -ItemType Directory -Path $wfAclRtRaiz -Force | Out-Null
        $wfAclRtSeg = Get-WinForgeAclFolderSecurity -Path $wfAclRtRaiz
        if (-not $wfAclRtSeg.Ok) { Write-Host "  [ERRO] Permissões (SDDL): a lista da pasta de teste não pôde ser lida ($($wfAclRtSeg.Reason))" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]::IsNullOrWhiteSpace([string]$wfAclRtSeg.OwnerSid)) { Write-Host "  [ERRO] Permissões (SDDL): o dono da pasta de teste veio sem SID" -ForegroundColor Red; $wbErrors++ }
        else {
            # A mexida: uma ACE de 'Todos' podendo modificar, que é o tipo de estrago que o botão
            # de restaurar padrões deixa para trás quando erra.
            $wfAclRtAcl = Get-Acl -LiteralPath $wfAclRtRaiz
            $wfAclRtAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            Set-Acl -LiteralPath $wfAclRtRaiz -AclObject $wfAclRtAcl
            $wfAclRtDepois = Get-WinForgeAclFolderSecurity -Path $wfAclRtRaiz
            if ([string]$wfAclRtDepois.Sddl -eq [string]$wfAclRtSeg.Sddl) { Write-Host "  [ERRO] Permissões (SDDL): a ACE plantada não mudou o descritor - o teste não está provando nada" -ForegroundColor Red; $wbErrors++ }
            # Antes da ida e volta, a prova de que as duas seções são INDEPENDENTES: devolver só o
            # DONO não pode encostar na lista. Isto não é teoria - com 'Set-Acl' era exatamente o
            # contrário: um descritor que só teve SetOwner() chamado reescrevia TAMBÉM a DACL e
            # deixava só as ACEs herdadas. Numa pasta do sistema restaurada com '/inheritance:r',
            # onde tudo é explícito, o passo do dono apagaria a lista que o passo anterior acabou
            # de devolver, e a única pista seria o disco continuar quebrado depois do Desfazer.
            $wfAclRtSoDono = Restore-WinForgeAclSddl -Path $wfAclRtRaiz -Sddl ([string]$wfAclRtDepois.Sddl) -OwnerSid ([string]$wfAclRtSeg.OwnerSid)
            if (-not $wfAclRtSoDono.DaclOk) { Write-Host "  [ERRO] Permissões (SDDL): a reaplicação da lista alterada falhou ($($wfAclRtSoDono.Reason))" -ForegroundColor Red; $wbErrors++ }
            elseif ((Get-WinForgeAclFolderSecurity -Path $wfAclRtRaiz).Sddl -ne [string]$wfAclRtDepois.Sddl) { Write-Host "  [ERRO] Permissões (SDDL): devolver o dono mexeu na lista - as duas seções têm de ser independentes" -ForegroundColor Red; $wbErrors++ }
            $wfAclRtRes = Restore-WinForgeAclSddl -Path $wfAclRtRaiz -Sddl ([string]$wfAclRtSeg.Sddl) -OwnerSid ([string]$wfAclRtSeg.OwnerSid)
            if (-not $wfAclRtRes.DaclOk) { Write-Host "  [ERRO] Permissões (SDDL): a lista não pôde ser devolvida ($($wfAclRtRes.Reason))" -ForegroundColor Red; $wbErrors++ }
            else {
                $wfAclRtVolta = Get-WinForgeAclFolderSecurity -Path $wfAclRtRaiz
                # A comparação ignora as flags de controle da DACL ('AI' = herança automática já
                # propagada, 'P' = protegida): no runner do CI a pasta recém-criada sai sem 'AI' e ganha
                # a flag na primeira gravação, sem nenhuma ACE ter mudado. O que importa é a lista de ACEs.
                $wfAclRtNorm = { param($s) [regex]::Replace([string]$s, '^D:[A-Z]*', 'D:') }
                if ((& $wfAclRtNorm $wfAclRtVolta.Sddl) -ne (& $wfAclRtNorm $wfAclRtSeg.Sddl)) { Write-Host "  [ERRO] Permissões (SDDL): a lista voltou diferente.`n    antes: $($wfAclRtSeg.Sddl)`n    volta: $($wfAclRtVolta.Sddl)" -ForegroundColor Red; $wbErrors++ }
                # O dono é operação SEPARADA, e é assim que uma falha nele (devolver a posse ao
                # TrustedInstaller exige SeRestorePrivilege) não derruba a volta da lista.
                if (-not $wfAclRtRes.OwnerTried) { Write-Host "  [ERRO] Permissões (SDDL): o dono nem chegou a ser tentado" -ForegroundColor Red; $wbErrors++ }
                elseif ($wfAclRtRes.OwnerOk -and [string]$wfAclRtVolta.OwnerSid -ne [string]$wfAclRtSeg.OwnerSid) { Write-Host "  [ERRO] Permissões (SDDL): disse que devolveu o dono e o SID ficou '$($wfAclRtVolta.OwnerSid)', esperado '$($wfAclRtSeg.OwnerSid)'" -ForegroundColor Red; $wbErrors++ }
                else { Write-Host "  Permissões (SDDL): DACL alterada e devolvida idêntica numa pasta de %TEMP%; dono tratado em operação separada (devolvido: $($wfAclRtRes.OwnerOk))" }
            }
            # SDDL inválido não pode passar por "deu certo".
            $wfAclRtRuim = Restore-WinForgeAclSddl -Path $wfAclRtRaiz -Sddl 'isto não é um descritor'
            if ($wfAclRtRuim.DaclOk) { Write-Host "  [ERRO] Permissões (SDDL): um descritor inválido foi dado como aplicado" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]::IsNullOrWhiteSpace([string]$wfAclRtRuim.Reason)) { Write-Host "  [ERRO] Permissões (SDDL): recusou o descritor inválido sem dizer por quê" -ForegroundColor Red; $wbErrors++ }
            # 3a4. O DONO volta pelo icacls, e não pelo .NET. O SetAccessControl nunca habilita o
            # SeRestorePrivilege: atribuir a posse a um SID que o chamador não possui - o
            # TrustedInstaller das pastas do sistema, que é o caso inteiro deste botão - responde
            # 1307 (ERROR_INVALID_OWNER) mesmo com o WinForge elevado. Medido nesta máquina, numa
            # pasta de %TEMP% e sem elevação: as DUAS vias falham em 1307 para o TrustedInstaller,
            # e a diferença só aparece elevado - onde o icacls habilita o privilégio sozinho, que é
            # o que a fase 4 já faz no 'setowner-devolver'. Aqui a prova é a que roda sem
            # elevação: a via, o vetor e a recusa do que não é SID.
            $wfAclRtFonte = [string](Get-Command Restore-WinForgeAclSddl).ScriptBlock
            foreach ($wfAclRtEsp in @(
                @("Get-WinForgeSystemExe -Name 'icacls.exe'", "o dono não volta pelo icacls do System32 (caminho completo)"),
                @("'/setowner', `"*`$sid`"", "o '/setowner' não recebe o SID pela forma '*<SID>'"),
                @("'/L', '/Q'", "o '/setowner' do dono não traz '/L' - numa pasta que virou ponto de reanálise ele trocaria o dono do DESTINO"),
                @('New-Object System.Security.Principal.SecurityIdentifier ([string]$OwnerSid)', 'o texto do índice vira argumento sem passar por SecurityIdentifier')
            )) {
                if ($wfAclRtFonte.IndexOf($wfAclRtEsp[0], [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (dono): $($wfAclRtEsp[1])" -ForegroundColor Red; $wbErrors++ }
            }
            if ($wfAclRtFonte.IndexOf('$so.SetOwner(', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Permissões (dono): a posse ainda é escrita pelo .NET (SetOwner + SetAccessControl), que não habilita o SeRestorePrivilege" -ForegroundColor Red; $wbErrors++ }
            # E o que NÃO é SID nem chega ao icacls: o índice é um arquivo, e um 'Administradores'
            # (ou um '/grant:r ...') plantado nele viraria argumento de um comando elevado.
            $wfAclRtNome = Restore-WinForgeAclSddl -Path $wfAclRtRaiz -Sddl ([string]$wfAclRtSeg.Sddl) -OwnerSid 'BUILTIN\Administradores'
            if (-not $wfAclRtNome.OwnerTried) { Write-Host "  [ERRO] Permissões (dono): um dono por NOME nem foi avaliado" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAclRtNome.OwnerOk) { Write-Host "  [ERRO] Permissões (dono): um dono por NOME foi aceito - o direito tem de ser só por SID" -ForegroundColor Red; $wbErrors++ }
            elseif (([string]$wfAclRtNome.OwnerReason).IndexOf('não é um SID válido', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (dono): o dono por NOME foi recusado pelo icacls, e não ANTES dele ('$($wfAclRtNome.OwnerReason)')" -ForegroundColor Red; $wbErrors++ }
            else { Write-Host "  Permissões (dono): a posse volta por 'icacls /setowner *<SID> /L /Q' do System32; dono por nome recusado antes de virar argumento" }
        }
        # E a contagem de entradas de um arquivo de '/save': é ela que separa um backup com
        # conteúdo de um arquivo que o icacls criou e não conseguiu preencher.
        $wfAclRtSalvo = Join-Path $wfAclRtRaiz 'save.txt'
        & (Get-WinForgeSystemExe -Name 'icacls.exe') $wfAclRtRaiz '/save' $wfAclRtSalvo '/C' '/Q' | Out-Null
        if (Test-Path -LiteralPath $wfAclRtSalvo) {
            if ((Measure-WinForgeAclSaveEntry -Path $wfAclRtSalvo) -lt 1) { Write-Host "  [ERRO] Permissões (SDDL): um arquivo de '/save' com conteúdo foi contado como vazio" -ForegroundColor Red; $wbErrors++ }
        }
        $wfAclRtVazio = Join-Path $wfAclRtRaiz 'vazio.txt'
        Set-Content -LiteralPath $wfAclRtVazio -Value '' -Encoding Unicode
        if ((Measure-WinForgeAclSaveEntry -Path $wfAclRtVazio) -ne 0) { Write-Host "  [ERRO] Permissões (SDDL): um arquivo sem entrada nenhuma foi contado como backup" -ForegroundColor Red; $wbErrors++ }
        if ((Measure-WinForgeAclSaveEntry -Path (Join-Path $wfAclRtRaiz 'nao-existe.txt')) -ne 0) { Write-Host "  [ERRO] Permissões (SDDL): arquivo inexistente deveria contar 0 entradas" -ForegroundColor Red; $wbErrors++ }
    } catch {
        Write-Host "  [ERRO] Permissões (SDDL): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        $wfAclRtLimpa = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\sddl-ida-e-volta'
        if (Test-Path -LiteralPath $wfAclRtLimpa) {
            Remove-Item -LiteralPath $wfAclRtLimpa -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $wfAclRtLimpa) { Write-Host "  [ERRO] Permissões (SDDL): a pasta de teste '$wfAclRtLimpa' não pôde ser apagada" -ForegroundColor Red; $wbErrors++ }
        }
    }
    # 3b. A SINTAXE do icacls, medida e não suposta. Cada string de concessão do plano é rodada de
    # verdade, com o alvo trocado por uma pasta descartável em %TEMP% - uma por passo, para que uma
    # concessão não deixe a próxima sem acesso. Ficam de fora o que não é concessão ('/save',
    # '/setowner', chkdsk, takeown) e tudo que tem '/T': recursão em pasta de teste não prova
    # sintaxe e custa tempo. Quem paga a conta desta trava é o 'AD' que precisava ser '(AD)': o
    # plano inteiro passava na revisão por leitura e o icacls respondia 87 na máquina do usuário.
    try {
        $wfAclSintRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\icacls-syntax'
        $wfAclSintExe = Get-WinForgeSystemExe -Name 'icacls.exe'
        # O plano do teste de sintaxe usa o SID REAL desta identidade: o icacls recusa um SID que
        # não existe na máquina com 1332 ("nenhum mapeamento"), e isso não é erro de sintaxe.
        $wfAclSintSid = [string][System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $wfAclSintPlano = @(Get-WinForgeAclRestorePlan -Profile (Join-Path $wfAclSintRaiz 'perfil') -UserSid $wfAclSintSid -BackupRoot 'C:\ProgramData\WinForge\acl-backup' -Stamp '20260911-120000')
        $wfAclSintPassos = @($wfAclSintPlano | Where-Object { @('grant', 'grant-extra') -contains [string]$_.Kind })
        if ($wfAclSintPassos.Count -lt 8) { Write-Host "  [ERRO] Permissões (sintaxe): $($wfAclSintPassos.Count) concessão(ões) no plano, esperado ao menos 8 (raiz, seis pastas e perfil)" -ForegroundColor Red; $wbErrors++ }
        $wfAclSintN = 0
        $wfAclSintRuins = @()
        foreach ($wfAclSintP in $wfAclSintPassos) {
            $wfAclSintArgs = @($wfAclSintP.Arguments | ForEach-Object { [string]$_ })
            if ($wfAclSintArgs -contains '/T') { continue }
            $wfAclSintN++
            $wfAclSintPasta = Join-Path $wfAclSintRaiz ("p{0:d2}" -f $wfAclSintN)
            New-Item -ItemType Directory -Path $wfAclSintPasta -Force | Out-Null
            $wfAclSintArgs[0] = $wfAclSintPasta
            $wfAclSintR = Invoke-WinForgeNativeCommand -FilePath $wfAclSintExe -Arguments $wfAclSintArgs
            if ([int]$wfAclSintR.ExitCode -ne 0) {
                $wfAclSintRuins += ("'{0}' -> código {1} ({2})" -f $wfAclSintP.Title, $wfAclSintR.ExitCode, (($wfAclSintArgs | Select-Object -Skip 1) -join ' '))
            }
        }
        foreach ($wfAclSintRuim in $wfAclSintRuins) { Write-Host "  [ERRO] Permissões (sintaxe): o icacls recusou $wfAclSintRuim" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfAclSintN) { Write-Host "  [ERRO] Permissões (sintaxe): nenhuma concessão foi rodada - a trava não está provando nada" -ForegroundColor Red; $wbErrors++ }
        elseif (-not $wfAclSintRuins.Count) { Write-Host "  Permissões (sintaxe): $wfAclSintN concessão(ões) do plano aceitas pelo icacls numa pasta de %TEMP%, nenhum caminho real tocado" }
    } catch {
        Write-Host "  [ERRO] Permissões (sintaxe): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        # As concessões tiram o acesso desta identidade das pastas de teste; sem devolver a herança
        # do %TEMP% antes, o Remove-Item deixaria a sujeira plantada (dono não é quem apaga).
        $wfAclSintLimpa = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\icacls-syntax'
        if (Test-Path -LiteralPath $wfAclSintLimpa) {
            & (Get-WinForgeSystemExe -Name 'icacls.exe') $wfAclSintLimpa '/reset' '/T' '/L' '/C' '/Q' | Out-Null
            Remove-Item -LiteralPath $wfAclSintLimpa -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $wfAclSintLimpa) { Write-Host "  [ERRO] Permissões (sintaxe): a pasta de teste '$wfAclSintLimpa' não pôde ser apagada" -ForegroundColor Red; $wbErrors++ }
        }
    }
    # 4. Simulação e recusa: com -DryRun as duas ações listam o que fariam; sem ele, em SelfTest,
    # recusam. Este build não reescreve as permissões do disco de quem compila.
    try {
        $wfAclSeco = @(Invoke-WinForgeAclRestore -DryRun)
        if ($wfAclSeco.Count -lt 6) { Write-Host "  [ERRO] Permissões (simulação): a restauração listou $($wfAclSeco.Count) linha(s), esperado ao menos 6" -ForegroundColor Red; $wbErrors++ }
        $wfAclSecoU = @(Invoke-WinForgeAclUndo -DryRun)
        if ($wfAclSecoU.Count -lt 1) { Write-Host "  [ERRO] Permissões (simulação): o desfazer não disse o que faria" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfAclLinha in @($wfAclSeco + $wfAclSecoU)) {
            if (-not ([string]$wfAclLinha).StartsWith('[simulação] ')) { Write-Host "  [ERRO] Permissões (simulação): '$wfAclLinha' deveria começar com '[simulação] '" -ForegroundColor Red; $wbErrors++ }
            if (([string]$wfAclLinha).IndexOf('secedit', [StringComparison]::OrdinalIgnoreCase) -ge 0) { Write-Host "  [ERRO] Permissões (simulação): '$wfAclLinha' ainda chama o secedit" -ForegroundColor Red; $wbErrors++ }
            if (([string]$wfAclLinha).IndexOf('defltbase', [StringComparison]::OrdinalIgnoreCase) -ge 0) { Write-Host "  [ERRO] Permissões (simulação): '$wfAclLinha' ainda cita o defltbase.inf" -ForegroundColor Red; $wbErrors++ }
        }
        # O par de socorro de posse aparece na simulação, e aparece MARCADO como condicional: ele
        # troca o dono de uma pasta do sistema, e ninguém pode ler isso como "vai acontecer".
        $wfAclSecoCond = @($wfAclSeco | Where-Object { ([string]$_).IndexOf('(condicional)', [StringComparison]::Ordinal) -ge 0 })
        if ($wfAclSecoCond.Count -lt 3) { Write-Host "  [ERRO] Permissões (simulação): $($wfAclSecoCond.Count) passo(s) marcados como condicionais, esperado ao menos 3" -ForegroundColor Red; $wbErrors++ }
        $wfAclSecoPosse = @($wfAclSeco | Where-Object { ([string]$_).IndexOf('/setowner *S-1-5-32-544', [StringComparison]::Ordinal) -ge 0 })
        if (-not $wfAclSecoPosse.Count) { Write-Host "  [ERRO] Permissões (simulação): o socorro de posse não aparece na simulação" -ForegroundColor Red; $wbErrors++ }
        elseif (@($wfAclSecoPosse | Where-Object { ([string]$_).IndexOf('(condicional)', [StringComparison]::Ordinal) -lt 0 }).Count) { Write-Host "  [ERRO] Permissões (simulação): o socorro de posse aparece sem a marca de condicional" -ForegroundColor Red; $wbErrors++ }
        # A fase 2 aparece na simulação dizendo o que guarda de cada pasta - e o SDDL é o que o
        # Desfazer reaplica na pasta EM SI.
        if (-not @($wfAclSeco | Where-Object { ([string]$_).IndexOf('(SDDL)', [StringComparison]::Ordinal) -ge 0 }).Count) { Write-Host "  [ERRO] Permissões (simulação): a guarda da lista em SDDL não aparece na simulação da restauração" -ForegroundColor Red; $wbErrors++ }
        # Todo passo de '/restore' que a simulação do Desfazer mostrar TEM de trazer '/L'. É o espelho da
        # trava de '/T ⇒ /L' do plano, e a razão é a mesma vista do outro lado: o backup do perfil
        # é gravado com '/T /L', então o arquivo tem uma entrada para cada JUNÇÃO de
        # compatibilidade de dentro dele ('Dados de aplicativos', 'Configurações locais',
        # 'Cookies'), com a DACL da própria junção - que carrega um Deny de travessia para Todos.
        # Sem '/L' o '/restore' abre cada item SEGUINDO o ponto de reanálise e derrama esse Deny em
        # AppData\Roaming, AppData\Local e InetCookies: o usuário fica trancado fora do próprio
        # AppData pelo botão que existe para destrancá-lo.
        foreach ($wfAclLinhaU in @($wfAclSecoU)) {
            if (([string]$wfAclLinhaU).IndexOf('/restore', [StringComparison]::Ordinal) -lt 0) { continue }
            if (([string]$wfAclLinhaU).IndexOf(' /L', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (simulação): '$wfAclLinhaU' faz '/restore' sem '/L' - a DACL das junções do perfil cairia nos destinos delas" -ForegroundColor Red; $wbErrors++ }
        }
        $wfAclFonteUndo = [string](Get-Command Invoke-WinForgeAclUndo).ScriptBlock
        # O vetor traz '/C' E '/L', e o '/C' é o OPOSTO do que a fase 5 faz - de propósito, porque a
        # pergunta é outra. Lá é um alvo único por chamada: não há o que continuar, e o código de
        # saída é o único sinal (medido: pasta inexistente sai 2 sem '/C' e 0 com). Aqui é UMA
        # chamada para um arquivo de centenas de entradas, e continuar apesar do erro é o
        # comportamento desejado: sem '/C' o icacls pode PARAR na primeira entrada morta, e uma
        # pasta que sumiu desde o backup não pode custar a restauração das outras. Abortar no meio é
        # pior do que contar errado - este botão é o último recurso de quem acabou de ter as
        # permissões do disco reescritas. O sinal de "aplicou mesmo" vem da conferência por
        # amostragem da Tarefa 5, e não do código de saída daqui.
        # O nome da variável do arquivo é '$arquivoUsado', e não mais '$item.File': o arquivo do
        # conteúdo pode estar na pasta protegida ou no disco que o usuário escolheu ('ExternalPath'),
        # e quem decide qual dos dois entra no vetor é o bloco que vem antes. O que esta trava cobra
        # continua sendo a FORMA do vetor.
        if ($wfAclFonteUndo.IndexOf("'/restore', `$arquivoUsado, '/C', '/L'", [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (desfazer): o vetor de argumentos do '/restore' não é '<pasta> /restore <arquivo> /C /L' - sem '/C' o icacls pode parar na primeira entrada morta; sem '/L' a DACL das junções cai nos destinos delas" -ForegroundColor Red; $wbErrors++ }
        if ($wfAclFonteUndo.IndexOf('Restore-WinForgeAclSddl -Path', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (desfazer): o Desfazer não reaplica a lista da pasta em si (SDDL)" -ForegroundColor Red; $wbErrors++ }
        # E a outra ponta: o que a fase 2 indexa. O arquivo do conteúdo só pode ser endurecido - e
        # daí indexado - depois de a caminhada ter terminado inteira, do espaço ter sido conferido
        # e de a gravação ter dito Ok. A ORDEM é a trava: um endurecimento antes da conferência
        # indexaria um arquivo que ninguém garantiu.
        $wfAclFonteRest = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if ($wfAclFonteRest.IndexOf('Get-WinForgeAclFolderSecurity -Path', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (desfazer): a fase 2 não guarda a lista da pasta em si (SDDL)" -ForegroundColor Red; $wbErrors++ }
        if ($wfAclFonteRest.IndexOf('ConvertTo-Json', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (desfazer): o índice não é gravado em JSON" -ForegroundColor Red; $wbErrors++ }
        $wfAclPosSave = $wfAclFonteRest.IndexOf('Fase 2 de 6 - $($passo.Title)', [StringComparison]::Ordinal)
        $wfAclPosProt = $wfAclFonteRest.IndexOf('Protect-WinForgeSnapshotFile -Path $parcial', [StringComparison]::Ordinal)
        if ($wfAclPosSave -lt 0 -or $wfAclPosProt -le $wfAclPosSave) { Write-Host "  [ERRO] Permissões (desfazer): não dá para achar o trecho da fase 2 que grava o backup do conteúdo" -ForegroundColor Red; $wbErrors++ }
        else {
            $wfAclTrechoF2 = $wfAclFonteRest.Substring($wfAclPosSave, $wfAclPosProt - $wfAclPosSave)
            foreach ($wfAclF2Esp in @(
                @('Get-WinForgeAclContentScope -Path', 'a caminhada não roda antes de o arquivo ser endurecido e indexado'),
                @('Test-WinForgeAclFreeSpace -Path', 'o espaço livre não é conferido antes de a gravação começar'),
                @('Write-WinForgeAclContentBackup -Path', 'o arquivo não é gravado pelo motor antes de ser endurecido')
            )) {
                if ($wfAclTrechoF2.IndexOf($wfAclF2Esp[0], [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (desfazer): $($wfAclF2Esp[1])" -ForegroundColor Red; $wbErrors++ }
            }
            # O espaço vem ANTES da gravação, e não depois: conferir com o arquivo já escrito é
            # conferir o que não adianta mais.
            $wfAclPosEsp = $wfAclTrechoF2.IndexOf('Test-WinForgeAclFreeSpace -Path', [StringComparison]::Ordinal)
            $wfAclPosGrav = $wfAclTrechoF2.IndexOf('Write-WinForgeAclContentBackup -Path', [StringComparison]::Ordinal)
            if ($wfAclPosEsp -ge 0 -and $wfAclPosGrav -ge 0 -and $wfAclPosEsp -gt $wfAclPosGrav) { Write-Host "  [ERRO] Permissões (desfazer): o espaço livre é conferido DEPOIS de a gravação começar" -ForegroundColor Red; $wbErrors++ }
        }
        # O índice de verdade, ida e volta: um conjunto MONTADO em %TEMP% (a máquina de quem
        # compila normalmente não tem nenhum), lido por Get-WinForgeAclBackupSet e transformado em
        # plano pelo -DryRun. É o que prova que os dois tipos de item sobrevivem ao JSON e que cada
        # um vira a ação certa - SDDL na pasta, '/restore /C /L' no conteúdo do perfil.
        $wfAclIdxRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-indice'
        try {
            New-Item -ItemType Directory -Path $wfAclIdxRaiz -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $wfAclIdxRaiz 'acl-perfil-teste-20260911-120000.txt') -Value '' -Encoding Unicode
            $wfAclIdxDados = [pscustomobject]@{
                Stamp = '20260911-120000'
                Items = @(
                    [pscustomobject]@{ Path = 'C:\'; Sddl = 'D:PAI(A;OICI;FA;;;BA)'; Owner = 'BUILTIN\Administradores'; OwnerSid = 'S-1-5-32-544'; File = ''; Target = '' }
                    [pscustomobject]@{ Path = 'C:\Users\Teste'; Sddl = ''; Owner = ''; OwnerSid = ''; File = 'acl-perfil-teste-20260911-120000.txt'; Target = 'C:\Users' }
                )
            }
            Set-Content -LiteralPath (Join-Path $wfAclIdxRaiz 'acl-index-20260911-120000.json') -Value ($wfAclIdxDados | ConvertTo-Json -Depth 4) -Encoding UTF8
            $wfAclIdxSet = Get-WinForgeAclBackupSet -Root $wfAclIdxRaiz
            if ([string]$wfAclIdxSet.Stamp -ne '20260911-120000') { Write-Host "  [ERRO] Permissões (índice): o carimbo veio '$($wfAclIdxSet.Stamp)'" -ForegroundColor Red; $wbErrors++ }
            if (@($wfAclIdxSet.Items).Count -ne 2) { Write-Host "  [ERRO] Permissões (índice): $(@($wfAclIdxSet.Items).Count) item(ns) lidos, esperado 2" -ForegroundColor Red; $wbErrors++ }
            else {
                if ([string]$wfAclIdxSet.Items[0].Sddl -ne 'D:PAI(A;OICI;FA;;;BA)') { Write-Host "  [ERRO] Permissões (índice): o SDDL da raiz não sobreviveu ao JSON" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wfAclIdxSet.Items[0].OwnerSid -ne 'S-1-5-32-544') { Write-Host "  [ERRO] Permissões (índice): o dono da raiz não sobreviveu ao JSON" -ForegroundColor Red; $wbErrors++ }
                # O nome do arquivo do índice vira caminho DENTRO da pasta protegida, e não um
                # caminho que o índice escolha: é o que impede um 'sub\..\..\Users\Public\x.txt'
                # plantado ali de virar argumento de um /restore elevado.
                if ([string]$wfAclIdxSet.Items[1].File -ne (Join-Path $wfAclIdxRaiz 'acl-perfil-teste-20260911-120000.txt')) { Write-Host "  [ERRO] Permissões (índice): o arquivo do perfil não foi reancorado na pasta protegida ('$($wfAclIdxSet.Items[1].File)')" -ForegroundColor Red; $wbErrors++ }
            }
            $wfAclIdxSeco = @(Invoke-WinForgeAclUndo -DryRun -BackupRoot $wfAclIdxRaiz)
            if ($wfAclIdxSeco.Count -ne 2) { Write-Host "  [ERRO] Permissões (índice): a simulação do Desfazer deu $($wfAclIdxSeco.Count) linha(s), esperado 2" -ForegroundColor Red; $wbErrors++ }
            else {
                if (([string]$wfAclIdxSeco[0]).IndexOf("devolver a lista (SDDL) de 'C:\'", [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (índice): a linha da raiz não é a devolução por SDDL ('$($wfAclIdxSeco[0])')" -ForegroundColor Red; $wbErrors++ }
                # O passo do dono aparece como o COMANDO que vai rodar: quem lê a simulação tem de
                # ver que a posse volta pelo icacls (a única via que habilita o SeRestorePrivilege)
                # e que o vetor traz o SID e o '/L'.
                elseif (([string]$wfAclIdxSeco[0]).IndexOf('/setowner *S-1-5-32-544 /L /Q', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (índice): a linha da raiz não mostra o '/setowner' do dono com SID e '/L' ('$($wfAclIdxSeco[0])')" -ForegroundColor Red; $wbErrors++ }
                elseif (([string]$wfAclIdxSeco[0]).IndexOf([string](Get-WinForgeSystemExe -Name 'icacls.exe'), [StringComparison]::OrdinalIgnoreCase) -lt 0) { Write-Host "  [ERRO] Permissões (índice): o '/setowner' da simulação não é o icacls por caminho completo ('$($wfAclIdxSeco[0])')" -ForegroundColor Red; $wbErrors++ }
                if (([string]$wfAclIdxSeco[1]).IndexOf('/restore', [StringComparison]::Ordinal) -lt 0 -or ([string]$wfAclIdxSeco[1]).IndexOf(' /L', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (índice): a linha do perfil não é um '/restore' com '/L' ('$($wfAclIdxSeco[1])')" -ForegroundColor Red; $wbErrors++ }
            }
            foreach ($wfAclIdxLinha in $wfAclIdxSeco) {
                if (-not ([string]$wfAclIdxLinha).StartsWith('[simulação] ')) { Write-Host "  [ERRO] Permissões (índice): '$wfAclIdxLinha' deveria começar com '[simulação] '" -ForegroundColor Red; $wbErrors++ }
            }
            # Índice ilegível não pode virar "nada a desfazer" silencioso nem estourar. O carimbo é
            # o MAIS ANTIGO da pasta de propósito: o Desfazer escolhe o mais antigo não consumido, e
            # um ilegível conta como não consumido - ninguém o desfez. Com um carimbo mais novo este
            # teste não exercitaria nada, porque o conjunto escolhido seria o bom ao lado.
            Set-Content -LiteralPath (Join-Path $wfAclIdxRaiz 'acl-index-20260911-110000.json') -Value 'isto não é json' -Encoding UTF8
            $wfAclIdxRuim = Get-WinForgeAclBackupSet -Root $wfAclIdxRaiz
            if (@($wfAclIdxRuim.Items).Count) { Write-Host "  [ERRO] Permissões (índice): um índice ilegível devolveu $(@($wfAclIdxRuim.Items).Count) item(ns)" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]::IsNullOrWhiteSpace([string]$wfAclIdxRuim.Reason)) { Write-Host "  [ERRO] Permissões (índice): um índice ilegível não disse por que não deu" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAclIdxRuim.Refused) { Write-Host "  [ERRO] Permissões (índice): um índice ilegível foi marcado como RECUSADO - são coisas diferentes, e só a recusa para tudo" -ForegroundColor Red; $wbErrors++ }
            # A ORDEM: com '-Trusted' o índice é conferido ANTES de ser aberto. A pasta é de %TEMP%
            # e os arquivos pertencem à identidade atual, então Test-WinForgeAclBackupFile recusa
            # todos - e é justamente isso que prova a ordem: um JSON QUEBRADO tem de sair como
            # 'Refused' (conferência do arquivo), e não como "não pôde ser lido" (analisador de
            # JSON). Antes a conferência vinha depois do ConvertFrom-Json e a resposta era a outra.
            $wfAclIdxTrust = Get-WinForgeAclBackupSet -Root $wfAclIdxRaiz -Trusted
            if (-not $wfAclIdxTrust.Refused) { Write-Host "  [ERRO] Permissões (índice): com '-Trusted' o índice de %TEMP% deveria ser recusado (dono fora de SYSTEM/Administradores)" -ForegroundColor Red; $wbErrors++ }
            elseif (@($wfAclIdxTrust.Items).Count) { Write-Host "  [ERRO] Permissões (índice): um índice recusado devolveu $(@($wfAclIdxTrust.Items).Count) item(ns)" -ForegroundColor Red; $wbErrors++ }
            elseif (([string]$wfAclIdxTrust.Reason).IndexOf('não pôde ser lido', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Permissões (índice): o índice adulterado foi ANALISADO antes de ser conferido ('$($wfAclIdxTrust.Reason)')" -ForegroundColor Red; $wbErrors++ }
            # E o Desfazer de verdade pede a conferência ANTES de ler: a chamada com '-Trusted' tem
            # de estar no caminho real, e a antiga conferência depois do fato não pode voltar.
            $wfAclIdxFonte = [string](Get-Command Invoke-WinForgeAclUndo).ScriptBlock
            if ($wfAclIdxFonte.IndexOf('Get-WinForgeAclBackupSet -Root $BackupRoot -Trusted', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (índice): o Desfazer lê o conjunto sem '-Trusted' - o índice seria analisado antes de conferido" -ForegroundColor Red; $wbErrors++ }
            if ($wfAclIdxFonte.IndexOf('Test-WinForgeAclBackupFile -Path ([string]$conjunto.Index)', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Permissões (índice): a conferência do índice voltou para DEPOIS da leitura" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Permissões (índice): JSON com 2 item(ns) lido de volta, SDDL e dono intactos, arquivo reancorado na pasta protegida, índice ilegível recusado com motivo, conferência antes da leitura"
        } finally {
            Remove-Item -LiteralPath $wfAclIdxRaiz -Recurse -Force -ErrorAction SilentlyContinue
        }
        # A simulação não pode criar a pasta de backup nem gravar arquivo nenhum.
        if (Test-Path -LiteralPath (Get-WinForgeAclBackupRoot)) {
            $wfAclNaPasta = @(Get-ChildItem -LiteralPath (Get-WinForgeAclBackupRoot) -File -ErrorAction SilentlyContinue).Count
            if ($wfAclNaPasta) { Write-Host "  [ERRO] Permissões (simulação): a pasta de backup tem $wfAclNaPasta arquivo(s) depois de uma simulação" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($wfAclTrava in @(
            @('Invoke-WinForgeAclRestore', { Invoke-WinForgeAclRestore }),
            @('Invoke-WinForgeAclUndo', { Invoke-WinForgeAclUndo }),
            @('Invoke-WinForgeAclCleanup', { Invoke-WinForgeAclCleanup })
        )) {
            $wfAclMsg = $null
            try { & $wfAclTrava[1] | Out-Null } catch { $wfAclMsg = [string]$_.Exception.Message }
            if ($null -eq $wfAclMsg) { Write-Host "  [ERRO] Permissões (trava): $($wfAclTrava[0]) sem -DryRun deveria recusar em SelfTest" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAclMsg -notmatch 'SelfTest') { Write-Host "  [ERRO] Permissões (trava): a recusa de $($wfAclTrava[0]) não fala em SelfTest ('$wfAclMsg')" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Permissões (simulação): $($wfAclSeco.Count) linha(s) de restauração e $($wfAclSecoU.Count) de desfazer, nenhuma rodada, as duas recusadas sem -DryRun, sem secedit"
    } catch {
        Write-Host "  [ERRO] Permissões (simulação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # 4b. A elevação é a PRIMEIRA pergunta depois da trava de SelfTest: sem ela a pasta de backup
    # nasceria com a identidade atual como dona e ficaria plantada em %ProgramData%, fazendo a
    # conferência recusar todas as restaurações seguintes desta máquina.
    #
    # Antes esta prova DESLIGAVA $sync.SelfTest e chamava as funções de verdade, apostando que
    # nenhum efeito colateral tinha sido posto antes da checagem de elevação - se alguém pusesse
    # um, ele rodaria em todo build não elevado. Hoje são três provas, todas com a trava LIGADA:
    # o -Probe (que responde à primeira porta e volta, sem tocar em nada), a ordem no fonte e a
    # lista de coisas que NÃO podem aparecer antes da checagem.
    try {
        $wfAclRaizFantasma = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-backup-nao-deve-nascer'
        foreach ($wfAclFn in @('Invoke-WinForgeAclRestore', 'Invoke-WinForgeAclUndo', 'Invoke-WinForgeAclCleanup')) {
            $wfAclFonteEl = [string](Get-Command $wfAclFn).ScriptBlock
            # A âncora é a trava de SelfTest, e não o começo da função: acima dela ficam o -DryRun
            # e o -Probe, que também citam Test-WinForgeRepairElevated e não escrevem nada. Medir a
            # partir do zero faria a trava olhar para a ocorrência do -Probe e aceitar um efeito
            # colateral posto no caminho de verdade.
            $wfAclPosTrava = $wfAclFonteEl.IndexOf("Assert-WinForgeNotSelfTest -Name '$wfAclFn'", [StringComparison]::Ordinal)
            if ($wfAclPosTrava -lt 0) { Write-Host "  [ERRO] Permissões (elevação): $wfAclFn não tem a trava de SelfTest no caminho de execução" -ForegroundColor Red; $wbErrors++; continue }
            $wfAclPosEl = $wfAclFonteEl.IndexOf('Test-WinForgeRepairElevated', $wfAclPosTrava, [StringComparison]::Ordinal)
            if ($wfAclPosEl -lt 0) { Write-Host "  [ERRO] Permissões (elevação): $wfAclFn não confere elevação depois da trava de SelfTest" -ForegroundColor Red; $wbErrors++; continue }
            # Nada que escreva, crie pasta ou rode processo pode aparecer ANTES da checagem. A
            # busca é pela CHAMADA ('-Root' junto, por exemplo), e não pelo nome solto: ele também
            # aparece no bloco de ajuda, que vem antes de tudo.
            foreach ($wfAclEfeito in @('Confirm-WinForgeAclBackupRoot -Root', 'Invoke-WinForgeNativeCommand -FilePath', 'Protect-WinForgeSnapshotFile -Path', 'New-WinForgeSnapshotRoot -Root', 'Set-Content -LiteralPath', 'Restore-WinForgeAclSddl -Path', 'Remove-Item -LiteralPath')) {
                $wfAclPosEfeito = $wfAclFonteEl.IndexOf($wfAclEfeito, $wfAclPosTrava, [StringComparison]::Ordinal)
                if ($wfAclPosEfeito -ge 0 -and $wfAclPosEfeito -lt $wfAclPosEl) { Write-Host "  [ERRO] Permissões (elevação): $wfAclFn chama '$wfAclEfeito' ANTES de perguntar pela elevação" -ForegroundColor Red; $wbErrors++ }
            }
            # E o -Probe, que é a checagem vista de fora: com a trava de SelfTest ligada, ele
            # responde o que a primeira porta responderia e não deixa rastro.
            $wfAclProbe = & $wfAclFn -Probe -BackupRoot $wfAclRaizFantasma
            if ($null -eq $wfAclProbe -or $wfAclProbe -isnot [hashtable]) { Write-Host "  [ERRO] Permissões (elevação): $wfAclFn -Probe não devolveu o veredito da elevação" -ForegroundColor Red; $wbErrors++; continue }
            if ([bool]$wfAclProbe.Elevated -ne [bool](Test-WinForgeRepairElevated)) { Write-Host "  [ERRO] Permissões (elevação): $wfAclFn -Probe discorda de Test-WinForgeRepairElevated" -ForegroundColor Red; $wbErrors++ }
            if (-not $wfAclProbe.Elevated) {
                if ([string]$wfAclProbe.Reason -notmatch 'administrador') { Write-Host "  [ERRO] Permissões (elevação): a recusa de $wfAclFn não fala em administrador ('$($wfAclProbe.Reason)')" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wfAclProbe.Reason -notmatch 'Nada foi') { Write-Host "  [ERRO] Permissões (elevação): a recusa de $wfAclFn não diz que nada foi feito ('$($wfAclProbe.Reason)')" -ForegroundColor Red; $wbErrors++ }
            }
            # A trava de SelfTest continua LIGADA e continua valendo: sem -DryRun e sem -Probe as
            # duas recusam. (A prova completa está no bloco 4; aqui é só a certeza de que o -Probe
            # não abriu uma porta nova.)
            $wfAclProbeMsg = $null
            try { & $wfAclFn -BackupRoot $wfAclRaizFantasma | Out-Null } catch { $wfAclProbeMsg = [string]$_.Exception.Message }
            if ($null -eq $wfAclProbeMsg -or $wfAclProbeMsg -notmatch 'SelfTest') { Write-Host "  [ERRO] Permissões (elevação): $wfAclFn deixou de recusar em SelfTest depois do -Probe" -ForegroundColor Red; $wbErrors++ }
        }
        if (Test-Path -LiteralPath $wfAclRaizFantasma) { Write-Host "  [ERRO] Permissões (elevação): a pasta '$wfAclRaizFantasma' foi criada mesmo sem nada ter rodado" -ForegroundColor Red; $wbErrors++ }
        if (-not $sync.SelfTest) { Write-Host "  [ERRO] Permissões (elevação): a trava de SelfTest foi desligada em algum ponto deste bloco" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (elevação): as duas ações conferem elevação antes de qualquer efeito colateral (elevado agora: $(Test-WinForgeRepairElevated)), com a trava de SelfTest ligada o tempo todo"
    } catch {
        Write-Host "  [ERRO] Permissões (elevação): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-backup-nao-deve-nascer') -Recurse -Force -ErrorAction SilentlyContinue
    }
    # 5. A pasta de backup e o arquivo que o Desfazer aceita. Valem as regras da pasta PADRÃO, sem o
    # afrouxamento de -ExplicitRoot: o /restore reescreve permissões do disco inteiro a partir do que
    # o arquivo mandar, então um arquivo que um processo de integridade média possa trocar é o
    # próprio ataque, não um detalhe.
    try {
        $wfAclFonteConf = [string](Get-Command Confirm-WinForgeAclBackupRoot).ScriptBlock
        if ($wfAclFonteConf.IndexOf('ExplicitRoot', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Permissões (pasta): Confirm-WinForgeAclBackupRoot não pode usar -ExplicitRoot" -ForegroundColor Red; $wbErrors++ }
        $wfAclFonteRaiz = [string](Get-Command Get-WinForgeAclBackupRoot).ScriptBlock
        if ($wfAclFonteRaiz.IndexOf('$env:', [StringComparison]::Ordinal) -ge 0) { Write-Host "  [ERRO] Permissões (pasta): a pasta de backup não pode sair de variável de ambiente" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeAclBackupRoot) -notlike '*\WinForge\acl-backup') { Write-Host "  [ERRO] Permissões (pasta): o padrão deveria terminar em 'WinForge\acl-backup', veio '$(Get-WinForgeAclBackupRoot)'" -ForegroundColor Red; $wbErrors++ }
        $wfAclRaizAberta = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-backup-aberto'
        New-Item -ItemType Directory -Path $wfAclRaizAberta -Force | Out-Null
        $wfAclAclAberta = Get-Acl -LiteralPath $wfAclRaizAberta
        $wfAclAclAberta.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        Set-Acl -LiteralPath $wfAclRaizAberta -AclObject $wfAclAclAberta
        $wfAclConf = Confirm-WinForgeAclBackupRoot -Root $wfAclRaizAberta
        if ($wfAclConf.Ok) { Write-Host "  [ERRO] Permissões (pasta): uma pasta em %TEMP% com escrita para 'Todos' foi aceita" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]::IsNullOrWhiteSpace([string]$wfAclConf.Reason)) { Write-Host "  [ERRO] Permissões (pasta): recusou sem dizer por quê" -ForegroundColor Red; $wbErrors++ }
        # E o arquivo: fora da pasta protegida, recusado antes de qualquer leitura de conteúdo.
        $wfAclFora = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-fora-da-pasta.txt'
        Set-Content -LiteralPath $wfAclFora -Value 'D:PAI(A;;FA;;;WD)' -Encoding UTF8
        $wfAclJulg = Test-WinForgeAclBackupFile -Path $wfAclFora -Root (Get-WinForgeAclBackupRoot)
        if ($wfAclJulg.Trusted) { Write-Host "  [ERRO] Permissões (arquivo): um arquivo em %TEMP% foi aceito como backup" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfAclJulg.Reason -notmatch 'fora da pasta') { Write-Host "  [ERRO] Permissões (arquivo): a recusa não diz que o arquivo está fora da pasta ('$($wfAclJulg.Reason)')" -ForegroundColor Red; $wbErrors++ }
        # Subpasta também não vale: o /restore só lê o que está diretamente na pasta protegida.
        $wfAclSub = Join-Path (Get-WinForgeAclBackupRoot) 'sub\acl-raiz-20260911-120000.txt'
        $wfAclJulgSub = Test-WinForgeAclBackupFile -Path $wfAclSub -Root (Get-WinForgeAclBackupRoot)
        if ($wfAclJulgSub.Trusted) { Write-Host "  [ERRO] Permissões (arquivo): um arquivo em subpasta foi aceito como backup" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (pasta): backup em '$(Get-WinForgeAclBackupRoot)' com as regras da pasta padrão; arquivo fora dela e em subpasta recusados"
    } catch {
        Write-Host "  [ERRO] Permissões (pasta): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-backup-aberto') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-fora-da-pasta.txt') -Force -ErrorAction SilentlyContinue
    }
    # 6. As três linhas da tabela, a entrada da config e a pergunta antes de agir.
    try {
        $wfAclChaves = @{ AclVerify = 'read'; AclRestore = 'repair'; AclUndo = 'repair'; AclCleanup = 'repair' }
        foreach ($wfAclNome in $wfAclNomes) {
            $wfAclSpec = Get-WinForgeRepairCommand -Name $wfAclNome
            if ([string]$wfAclSpec.Kind -ne $wfAclChaves[$wfAclNome]) { Write-Host "  [ERRO] Permissões $wfAclNome`: tipo '$($wfAclSpec.Kind)', esperado '$($wfAclChaves[$wfAclNome])'" -ForegroundColor Red; $wbErrors++ }
            if ([string]::IsNullOrWhiteSpace([string]$wfAclSpec.Title)) { Write-Host "  [ERRO] Permissões $wfAclNome`: sem título" -ForegroundColor Red; $wbErrors++ }
            if ($null -eq $sync.configs.feature."WPFWFRep$wfAclNome") { Write-Host "  [ERRO] Permissões $wfAclNome`: sem entrada 'WPFWFRep$wfAclNome' na config" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfAclSpec.Kind -eq 'read') { continue }
            if (-not $wfAclSpec.Stream) { Write-Host "  [ERRO] Permissões $wfAclNome`: a linha deveria estar marcada com Stream" -ForegroundColor Red; $wbErrors++ }
            $wfAclPassos = @($wfAclSpec.Steps)
            if ($wfAclPassos.Count -ne 1) { Write-Host "  [ERRO] Permissões $wfAclNome`: $($wfAclPassos.Count) passo(s), esperado 1 (a função conduz as fases)" -ForegroundColor Red; $wbErrors++ }
            elseif (-not (Get-Command ([string]$wfAclPassos[0].Function) -ErrorAction SilentlyContinue)) { Write-Host "  [ERRO] Permissões $wfAclNome`: função '$($wfAclPassos[0].Function)' não existe" -ForegroundColor Red; $wbErrors++ }
            if ([string]::IsNullOrWhiteSpace([string]$wfAclSpec.Confirm)) { Write-Host "  [ERRO] Permissões $wfAclNome`: ação '$($wfAclSpec.Kind)' sem texto de confirmação de reserva" -ForegroundColor Red; $wbErrors++ }
            $wfAclConfTexto = [string](Get-WinForgeRepairConfirmText -Name $wfAclNome)
            $wfAclDesc = [string]$sync.configs.feature."WPFWFRep$wfAclNome".Description
            if ([string]::IsNullOrWhiteSpace($wfAclDesc)) { Write-Host "  [ERRO] Permissões (confirmação) $wfAclNome`: sem Description na config" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAclConfTexto -notmatch [regex]::Escape($wfAclDesc.Trim())) { Write-Host "  [ERRO] Permissões (confirmação) $wfAclNome`: o texto não veio da Description da config" -ForegroundColor Red; $wbErrors++ }
            if (([regex]::Matches($wfAclConfTexto, 'Continuar')).Count -ne 1) { Write-Host "  [ERRO] Permissões (confirmação) $wfAclNome`: 'Continuar' deveria aparecer uma vez" -ForegroundColor Red; $wbErrors++ }
            if ($wfAclConfTexto.Length -lt 120) { Write-Host "  [ERRO] Permissões (confirmação) $wfAclNome`: texto curto demais ($($wfAclConfTexto.Length) caractere(s))" -ForegroundColor Red; $wbErrors++ }
            $wfAclDec = Invoke-WinForgeRepairCommand -Name $wfAclNome -NoUI
            if ($null -eq $wfAclDec -or $wfAclDec.Dispatched -or [string]$wfAclDec.Reason -ne 'confirmação') { Write-Host "  [ERRO] Permissões $wfAclNome`: -NoUI deveria recusar com motivo 'confirmação', veio '$($wfAclDec.Reason)'" -ForegroundColor Red; $wbErrors++ }
        }
        # A pergunta da restauração é a única do programa que promete minutos, reinicialização e um
        # backup: se ela perder qualquer uma das três, a pessoa diz "Sim" a algo que não leu.
        $wfAclPergunta = [string](Get-WinForgeRepairConfirmText -Name AclRestore)
        foreach ($wfAclTermo in @('minuto', 'einici', 'backup', 'icacls')) {
            if ($wfAclPergunta.IndexOf($wfAclTermo, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Write-Host "  [ERRO] Permissões (confirmação) AclRestore: a pergunta não fala em '$wfAclTermo'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfAclPergunta.IndexOf('secedit', [StringComparison]::OrdinalIgnoreCase) -ge 0) { Write-Host "  [ERRO] Permissões (confirmação) AclRestore: a pergunta promete secedit, que não existe mais no plano" -ForegroundColor Red; $wbErrors++ }
        # A RESERVA da tabela ('Confirm') só aparece se a entrada da config sumir - e foi por isso
        # que ela envelheceu prometendo secedit sem ninguém notar. Ela descreve as mesmas fases.
        $wfAclReserva = [string](Get-WinForgeRepairCommand -Name AclRestore).Confirm
        if ($wfAclReserva.IndexOf('secedit', [StringComparison]::OrdinalIgnoreCase) -ge 0) { Write-Host "  [ERRO] Permissões (confirmação) AclRestore: a reserva da tabela promete secedit, que não existe mais no plano" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfAclTermoR in @('chkdsk', 'backup', 'raiz', 'pastas do sistema', 'pasta de usuário', 'minuto', 'einici')) {
            if ($wfAclReserva.IndexOf($wfAclTermoR, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Write-Host "  [ERRO] Permissões (confirmação) AclRestore: a reserva da tabela não fala em '$wfAclTermoR'" -ForegroundColor Red; $wbErrors++ }
        }
        # O Desfazer diz o que NÃO devolve: /restore repõe a lista, nunca a posse.
        $wfAclPerguntaU = [string](Get-WinForgeRepairConfirmText -Name AclUndo)
        if ($wfAclPerguntaU.IndexOf('posse', [StringComparison]::OrdinalIgnoreCase) -lt 0) { Write-Host "  [ERRO] Permissões (confirmação) AclUndo: a pergunta não diz que o /restore não devolve a posse" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (tabela): $($wfAclNomes.Count) botão(ões) - 1 leitura e 3 com fluxo ao vivo, confirmação vinda da aba Config"
    } catch {
        Write-Host "  [ERRO] Permissões (tabela): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
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
    # ---------------------------------------------------------------- Permissões: a caminhada
    # O laço que encheu o disco em produção: 'AppData\Local\Dados de Aplicativos' é uma junção para
    # 'AppData\Local', alcançável por dois caminhos, e quem para a recursão é o limite de 63 saltos
    # de reparse - não o MAX_PATH. A caminhada nova não desce em ponto de reanálise E não o indexa:
    # o .NET lê a ACL do ALVO e o '/restore /L' a devolveria ao LINK, trocando permissão por
    # permissão. As duas coisas, e é isto que o teste cobra.
    $wfCamRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-caminhada'
    try {
        if (Test-Path -LiteralPath $wfCamRaiz) { Remove-Item -LiteralPath $wfCamRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        $wfCamPerfil = Join-Path $wfCamRaiz 'perfil'
        $wfCamLocal = Join-Path $wfCamPerfil 'AppData\Local'
        New-Item -ItemType Directory -Path $wfCamLocal -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $wfCamPerfil 'Documentos') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $wfCamPerfil 'nota.txt') -Value 'x' -Encoding UTF8
        # A junção auto-referente: 'Dados de Aplicativos' -> o próprio pai. É o laço exato da máquina real.
        $wfCamJuncao = Join-Path $wfCamLocal 'Dados de Aplicativos'
        cmd.exe /c mklink /J "$wfCamJuncao" "$wfCamLocal" | Out-Null
        if (-not (Test-Path -LiteralPath $wfCamJuncao)) { throw "a junção de teste não pôde ser criada em '$wfCamJuncao'" }
        # Herança bloqueada em UMA pasta: é ela, e só ela, que o filtro tem de guardar.
        $wfCamProt = New-Object System.IO.DirectoryInfo (Join-Path $wfCamPerfil 'Documentos')
        $wfCamSd = $wfCamProt.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $wfCamSd.SetAccessRuleProtection($true, $true)
        $wfCamProt.SetAccessControl($wfCamSd)

        $wfCamR = Get-WinForgeAclContentScope -Path $wfCamPerfil
        if (-not $wfCamR.Ok) { Write-Host "  [ERRO] Permissões (caminhada): devolveu Ok=`$false ('$($wfCamR.Reason)') numa pasta de teste íntegra" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamR.Reparse -lt 1) { Write-Host "  [ERRO] Permissões (caminhada): a junção não foi contada em Reparse (veio $($wfCamR.Reparse))" -ForegroundColor Red; $wbErrors++ }
        $wfCamNomes = @($wfCamR.Entries | ForEach-Object { [string]$_.Name })
        if (@($wfCamNomes | Where-Object { $_ -like '*Dados de Aplicativos*' }).Count) { Write-Host "  [ERRO] Permissões (caminhada): o ponto de reanálise virou ENTRADA ('$($wfCamNomes -join ' | ')') - o /restore /L aplicaria no link a ACL do destino" -ForegroundColor Red; $wbErrors++ }
        if (@($wfCamNomes | Sort-Object -Unique).Count -ne $wfCamNomes.Count) { Write-Host "  [ERRO] Permissões (caminhada): item visitado duas vezes ('$($wfCamNomes -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        # CONTAGEM EXATA, e não 'pelo menos': com uma entrada só, "sem duplicata" é vácuo, e contar o
        # reparse E empilhá-lo passaria verde com o laço inteiro vivo e invisível. São quatro pastas -
        # perfil, AppData, Local, Documentos - e nenhuma quinta: 'Scanned' conta pasta ENUMERADA, o
        # ponto de reanálise conta só em 'Reparse'. Descer na junção traria Local e Documentos de novo
        # e isto viraria 6.
        if ([int]$wfCamR.Scanned -ne 4) { Write-Host "  [ERRO] Permissões (caminhada): Scanned=$($wfCamR.Scanned), esperado exatamente 4 (perfil, AppData, Local, Documentos) - mais que isso é a junção sendo descida" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamR.Reparse -ne 1) { Write-Host "  [ERRO] Permissões (caminhada): Reparse=$($wfCamR.Reparse), esperado exatamente 1" -ForegroundColor Red; $wbErrors++ }
        if (@($wfCamR.Entries).Count -ne 1) { Write-Host "  [ERRO] Permissões (caminhada): o filtro é AreAccessRulesProtected - esperava 1 entrada, veio $(@($wfCamR.Entries).Count)" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfCamR.Entries[0].Name -notlike '*Documentos') { Write-Host "  [ERRO] Permissões (caminhada): a entrada guardada é '$($wfCamR.Entries[0].Name)', esperada a pasta com herança bloqueada" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]::IsNullOrWhiteSpace([string]$wfCamR.Entries[0].Sddl)) { Write-Host "  [ERRO] Permissões (caminhada): a entrada veio sem SDDL" -ForegroundColor Red; $wbErrors++ }
        # Nome RELATIVO à pasta ACIMA do perfil, com a folha do perfil na frente: é o que o
        # 'icacls <pasta acima> /restore' espera, e é o que o Desfazer vai consumir.
        if ([string]$wfCamR.Entries[0].Name -ne 'perfil\Documentos') { Write-Host "  [ERRO] Permissões (caminhada): o nome relativo veio '$($wfCamR.Entries[0].Name)', esperado 'perfil\Documentos'" -ForegroundColor Red; $wbErrors++ }
        # Arquivo fica FORA por padrão (84 protegidos em 294.011 na máquina medida, todos cache).
        # Contagem EXATA outra vez: há um único arquivo na árvore ('nota.txt'), então -IncludeFiles
        # soma exatamente 1. "Aumentou" passaria verde com a árvore inteira sendo varrida duas vezes.
        $wfCamArq = Get-WinForgeAclContentScope -Path $wfCamPerfil -IncludeFiles
        if ([int]$wfCamArq.Scanned -ne ([int]$wfCamR.Scanned + 1)) { Write-Host "  [ERRO] Permissões (caminhada): -IncludeFiles deu Scanned=$($wfCamArq.Scanned), esperado $([int]$wfCamR.Scanned + 1) (só 'nota.txt' entra)" -ForegroundColor Red; $wbErrors++ }

        # Os quatro tetos: Entries VAZIO, nunca o coletado até ali, e a frase de §1.6.
        # '@($h)[0]' NÃO é splat - é argumento posicional, e os quatro tetos rodariam com o padrão,
        # sem estourar nunca. Splat é '@nome', sobre uma VARIÁVEL.
        foreach ($wfCamTeto in @(
            @{ Nome = 'MaxItems';   Args = @{ MaxItems = 0 } },
            @{ Nome = 'MaxBytes';   Args = @{ MaxBytes = 1 } },
            @{ Nome = 'MaxDepth';   Args = @{ MaxDepth = 0 } },
            @{ Nome = 'MaxSeconds'; Args = @{ MaxSeconds = 0 } })) {
            $wfCamArgs = $wfCamTeto.Args
            $wfCamEstouro = Get-WinForgeAclContentScope -Path $wfCamPerfil @wfCamArgs
            if ($wfCamEstouro.Ok) { Write-Host "  [ERRO] Permissões (tetos): $($wfCamTeto.Nome) estourado devolveu Ok=`$true" -ForegroundColor Red; $wbErrors++ }
            if (@($wfCamEstouro.Entries).Count -ne 0) { Write-Host "  [ERRO] Permissões (tetos): $($wfCamTeto.Nome) devolveu $(@($wfCamEstouro.Entries).Count) entrada(s) - o parcial não pode sair" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfCamEstouro.Reason -notmatch 'nada foi alterado') { Write-Host "  [ERRO] Permissões (tetos): $($wfCamTeto.Nome) sem a frase de §1.6 ('$($wfCamEstouro.Reason)')" -ForegroundColor Red; $wbErrors++ }
        }
        # Caminho longo: sem o prefixo '\\?\' isto estoura PathTooLongException no PC do usuário,
        # porque LongPathsEnabled=1 não é o padrão.
        $wfCamLongo = $wfCamPerfil
        while ($wfCamLongo.Length -lt 294) { $wfCamLongo = Join-Path $wfCamLongo ('n' * 30) }
        [System.IO.Directory]::CreateDirectory('\\?\' + $wfCamLongo) | Out-Null
        # O prefixo '\\?\' não é só comprimento: ele desliga a normalização do Win32, e ISSO nenhum
        # LongPathsEnabled reverte. 'cache ' - com espaço no fim - é criada pelo prefixo e, sem ele,
        # o Win32 come o espaço, procura 'cache' e não acha: medido, Exists=False e GetAttributes e
        # GetAccessControl lançam, enquanto a enumeração da pasta acima devolve o nome do mesmo
        # jeito. É esta pasta, e não o comprimento, que mata a mutação do prefixo NESTA máquina:
        # aqui LongPathsEnabled=1, então o caminho de 300 caracteres abre sem prefixo nenhum.
        $wfCamEspaco = Join-Path $wfCamPerfil 'cache '
        [System.IO.Directory]::CreateDirectory('\\?\' + $wfCamEspaco) | Out-Null
        $wfCamRLongo = Get-WinForgeAclContentScope -Path $wfCamPerfil
        if (-not $wfCamRLongo.Ok) { Write-Host "  [ERRO] Permissões (caminho longo): a caminhada falhou ('$($wfCamRLongo.Reason)') - falta o prefixo \\?\" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamRLongo.Denied -ne 0) { Write-Host "  [ERRO] Permissões (caminho longo): $($wfCamRLongo.Denied) negada(s) - sem o prefixo \\?\ em TODA chamada a pasta 'cache ' (espaço no fim) some da árvore e o caminho de $($wfCamLongo.Length) caracteres não abre" -ForegroundColor Red; $wbErrors++ }

        # Atributo ilegível NÃO é "não é ponto de reanálise". Quando o GetAttributes lança, não se
        # sabe o que o item é, e descer nele é descer justamente no que não se conseguiu
        # identificar - o caminho de volta ao laço. A caminhada falha FECHADA: conta em Denied e não
        # desce. Caminho inexistente é a forma determinística de fazer o GetAttributes lançar mesmo
        # COM o prefixo. 'Scanned' exato é o que mata a mutação: falhando aberta ele vem 1, porque a
        # pasta é contada antes de o GetAccessControl recusar.
        $wfCamSumiu = Get-WinForgeAclContentScope -Path (Join-Path $wfCamPerfil 'pasta-que-nunca-existiu')
        if ([int]$wfCamSumiu.Scanned -ne 0) { Write-Host "  [ERRO] Permissões (atributo ilegível): Scanned=$($wfCamSumiu.Scanned), esperado 0 - o item cujo atributo não pôde ser lido foi visitado assim mesmo" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamSumiu.Denied -ne 1) { Write-Host "  [ERRO] Permissões (atributo ilegível): Denied=$($wfCamSumiu.Denied), esperado 1" -ForegroundColor Red; $wbErrors++ }
        if (@($wfCamSumiu.DeniedPaths).Count -ne 1 -or ([string](@($wfCamSumiu.DeniedPaths)[0])) -notlike '*pasta-que-nunca-existiu') { Write-Host "  [ERRO] Permissões (atributo ilegível): DeniedPaths veio '$(@($wfCamSumiu.DeniedPaths) -join ' | ')' - é esta lista que a Fase 2 mostra ao usuário" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamSumiu.Reparse -ne 0) { Write-Host "  [ERRO] Permissões (atributo ilegível): Reparse=$($wfCamSumiu.Reparse), esperado 0 - atributo ilegível não é ponto de reanálise" -ForegroundColor Red; $wbErrors++ }

        # Profundidade x laço: as duas causas estouram o MESMO teto, e mandar a mesma frase nas duas
        # esconde justamente o defeito que esta função existe para evitar. Controle negativo
        # PRIMEIRO, enquanto não há atalho nenhum no caminho da descida.
        $wfCamFundo = Get-WinForgeAclContentScope -Path $wfCamPerfil -MaxDepth 3
        if ([string]$wfCamFundo.Reason -notmatch 'níveis de pasta') { Write-Host "  [ERRO] Permissões (profundidade): árvore funda não deu a frase de profundidade ('$($wfCamFundo.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfCamFundo.Reason -match 'laço') { Write-Host "  [ERRO] Permissões (profundidade): árvore funda, sem atalho nenhum no caminho, foi chamada de laço ('$($wfCamFundo.Reason)')" -ForegroundColor Red; $wbErrors++ }
        # Agora três atalhos com nome em 'z'. O NTFS enumera em ordem e a pilha é LIFO, então eles
        # saem PRIMEIRO e a contagem de reparse já está alta quando a descida bate no teto - que é a
        # assinatura do laço de verdade.
        foreach ($wfCamZ in @('z1', 'z2', 'z3')) {
            cmd.exe /c mklink /J "$wfCamPerfil\$wfCamZ" "$wfCamPerfil\Documentos" | Out-Null
        }
        $wfCamLaco = Get-WinForgeAclContentScope -Path $wfCamPerfil -MaxDepth 4
        if ([string]$wfCamLaco.Reason -notmatch 'laço') { Write-Host "  [ERRO] Permissões (laço): $($wfCamLaco.Reparse) atalho(s) em $($wfCamLaco.Scanned) item(ns) e veio a frase de árvore funda ('$($wfCamLaco.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfCamLaco.Reason -notmatch 'nada foi alterado') { Write-Host "  [ERRO] Permissões (laço): a frase do laço não diz que nada foi alterado ('$($wfCamLaco.Reason)')" -ForegroundColor Red; $wbErrors++ }

        # 'Denied' POSITIVO, com pasta de verdade: negação explícita de "listar pasta" para o próprio
        # usuário. Medido: o DONO mantém READ_CONTROL por direito implícito, então o GetAccessControl
        # continua lendo a lista e a entrada entra no backup, mas a enumeração dos filhos é recusada.
        # É o caso da §1.2 - pasta que fica fora do backup sem que nada exploda - e o SDDL dela é o
        # único ACE de negação real desta árvore, o que prova a contagem de 'Deny' de ponta a ponta.
        $wfCamNegada = Join-Path $wfCamPerfil 'negada'
        New-Item -ItemType Directory -Path (Join-Path $wfCamNegada 'filha') -Force | Out-Null
        $wfCamEu = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $wfCamNegDi = New-Object System.IO.DirectoryInfo $wfCamNegada
        $wfCamNegSd = $wfCamNegDi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $wfCamNegSd.SetAccessRuleProtection($true, $true)
        $wfCamNegRegra = New-Object System.Security.AccessControl.FileSystemAccessRule($wfCamEu, [System.Security.AccessControl.FileSystemRights]::ListDirectory, [System.Security.AccessControl.InheritanceFlags]::None, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Deny)
        $wfCamNegSd.AddAccessRule($wfCamNegRegra)
        $wfCamNegDi.SetAccessControl($wfCamNegSd)
        try {
            $wfCamRNeg = Get-WinForgeAclContentScope -Path $wfCamPerfil
            if (-not $wfCamRNeg.Ok) { Write-Host "  [ERRO] Permissões (negada): uma pasta recusada derrubou a caminhada inteira ('$($wfCamRNeg.Reason)')" -ForegroundColor Red; $wbErrors++ }
            if ([int]$wfCamRNeg.Denied -ne 1) { Write-Host "  [ERRO] Permissões (negada): Denied=$($wfCamRNeg.Denied), esperado exatamente 1" -ForegroundColor Red; $wbErrors++ }
            if (-not @($wfCamRNeg.DeniedPaths | Where-Object { $_ -like '*\negada' }).Count) { Write-Host "  [ERRO] Permissões (negada): DeniedPaths não traz a pasta recusada ('$(@($wfCamRNeg.DeniedPaths) -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
            if ([int]$wfCamRNeg.Deny -ne 1) { Write-Host "  [ERRO] Permissões (negada): Deny=$($wfCamRNeg.Deny), esperado 1 - o ACE de negação da pasta recusada tem de ser contado" -ForegroundColor Red; $wbErrors++ }
        } finally {
            # Sai no finally: a pasta só volta a ser apagável depois que a negação some.
            $wfCamNegDi2 = New-Object System.IO.DirectoryInfo $wfCamNegada
            $wfCamNegSd2 = $wfCamNegDi2.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
            $null = $wfCamNegSd2.RemoveAccessRuleSpecific($wfCamNegRegra)
            $wfCamNegDi2.SetAccessControl($wfCamNegSd2)
        }

        # 'Denied' conta o GetAccessControl, a enumeração dos filhos e o GetAttributes que LANÇA. Em
        # pasta apenas negada o GetAttributes não lança (medido), e por isso não é ele quem detecta
        # negação; quando ele lança, o item é desconhecido e a caminhada falha fechada - é o que o
        # bloco do atributo ilegível acima cobra.
        $wfCamFonte = [string](Get-Command Get-WinForgeAclContentScope).ScriptBlock
        if ($wfCamFonte -match 'AllDirectories') { Write-Host "  [ERRO] Permissões (caminhada): EnumerateFileSystemEntries com AllDirectories é proibido - ele segue reparse point" -ForegroundColor Red; $wbErrors++ }
        if ($wfCamFonte -match 'AccessControlSections\]::All') { Write-Host "  [ERRO] Permissões (caminhada): AccessControlSections::All lança sem SeSecurityPrivilege" -ForegroundColor Red; $wbErrors++ }
        if ($wfCamFonte -notmatch 'GetSecurityDescriptorSddlForm') { Write-Host "  [ERRO] Permissões (caminhada): o SDDL tem de sair de GetSecurityDescriptorSddlForm('Access')" -ForegroundColor Red; $wbErrors++ }
        # O SDDL tem quatro formas de ACE de negação e o NTFS só sabe produzir uma: não existe pasta
        # que gere '(OD;'. Então o padrão é pescado do fonte pelo marcador SDDL-NEGACAO e aplicado em
        # SDDL sintético - é a única prova possível das outras três. A forma '(D;' já foi provada de
        # ponta a ponta na pasta recusada, acima.
        $wfCamNegPad = [regex]::Match($wfCamFonte, "'([^']+)'\s*#\s*SDDL-NEGACAO").Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($wfCamNegPad)) { Write-Host "  [ERRO] Permissões (negação): o marcador SDDL-NEGACAO sumiu do fonte - sem ele não há como provar o padrão" -ForegroundColor Red; $wbErrors++ }
        else {
            foreach ($wfCamNegCaso in @('D:P(A;;FA;;;SY)(D;;FA;;;WD)', 'D:P(A;;FA;;;SY)(OD;;CR;;;WD)', 'D:P(A;;FA;;;SY)(XD;;FA;;;WD)', 'D:P(A;;FA;;;SY)(ZD;;FA;;;WD)')) {
                if ($wfCamNegCaso -notmatch $wfCamNegPad) { Write-Host "  [ERRO] Permissões (negação): o padrão '$wfCamNegPad' não pega '$wfCamNegCaso'" -ForegroundColor Red; $wbErrors++ }
            }
            foreach ($wfCamNegNao in @('D:P(A;;FA;;;SY)(A;;FA;;;WD)', 'D:P(A;;FA;;;SY)(OA;;CR;;;WD)')) {
                if ($wfCamNegNao -match $wfCamNegPad) { Write-Host "  [ERRO] Permissões (negação): o padrão '$wfCamNegPad' pegou uma ACE de permissão ('$wfCamNegNao')" -ForegroundColor Red; $wbErrors++ }
            }
        }
        Write-Host "  Permissões (caminhada): junção auto-referente não é descida nem indexada, 1 entrada protegida, tetos devolvem lista vazia, caminho de $($wfCamLongo.Length) caracteres lido"
    } catch {
        Write-Host "  [ERRO] Permissões (caminhada): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        # Os atalhos primeiro, e por 'rmdir': medido, o Directory.Delete recursivo do .NET NÃO segue
        # ponto de reanálise - o arquivo do outro lado sobreviveu -, mas LANÇA ao tentar apagá-lo.
        # Depois o Delete COM prefixo, porque o Remove-Item deixa 'cache ' para trás: medido, ela
        # some do Win32 e a pasta fica em %TEMP% para sempre.
        foreach ($wfCamLixo in @('perfil\AppData\Local\Dados de Aplicativos', 'perfil\z1', 'perfil\z2', 'perfil\z3')) {
            try { cmd.exe /c rmdir "$wfCamRaiz\$wfCamLixo" 2>$null | Out-Null } catch { }
        }
        try { [System.IO.Directory]::Delete('\\?\' + $wfCamRaiz, $true) } catch { }
    }
    # ---------------------------------------------------------------- Permissões: o arquivo e a contraprova
    # É o único ponto do desenho sem prova: gravar o arquivo de conteúdo e conferir byte a byte que
    # ele é o que o icacls escreveria. Roda em %TEMP%, sem elevação.
    #
    # A prova NÃO é um '/restore'. Medido aqui, sem elevação: 'icacls <raiz> /restore <arq> /C /L'
    # responde 1300 ("Nem todos os privilégios ou grupos mencionados estão atribuídos ao chamador"),
    # diz "Processados com sucesso 0 arquivos" e deixa a DACL como estava - com QUALQUER combinação
    # de /C, /L e /Q, e mesmo com o arquivo que o próprio icacls acabou de gravar. Ele habilita
    # SeRestorePrivilege na entrada, antes de olhar o conteúdo, e o SelfTest roda sem admin. É a
    # mesma razão que já mantém o '/restore' do conteúdo fora do SelfTest (bloco 3a3).
    #
    # A contraprova é o '/save', que roda sem elevação E é o AUTOR do formato: o arquivo que ele
    # escreve para a MESMA árvore tem de trazer o mesmo nome relativo, o mesmo SDDL e o mesmo
    # encoding que o nosso. Um '/restore' que aceitasse o arquivo diria menos: ele aceita em
    # silêncio o que decodificar, e é justo o encoding que precisa ser cobrado.
    $wfArqRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-arquivo'
    $wfArqSelfAntes = $sync.SelfTest
    try {
        if (Test-Path -LiteralPath $wfArqRaiz) { Remove-Item -LiteralPath $wfArqRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        $wfArqPerfil = Join-Path $wfArqRaiz 'perfil'
        $wfArqAlvo = Join-Path $wfArqPerfil 'Protegida'
        New-Item -ItemType Directory -Path $wfArqAlvo -Force | Out-Null
        $wfArqDir = New-Object System.IO.DirectoryInfo $wfArqAlvo
        $wfArqSd = $wfArqDir.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $wfArqSd.SetAccessRuleProtection($true, $true)
        $wfArqDir.SetAccessControl($wfArqSd)
        $wfArqEscopo = Get-WinForgeAclContentScope -Path $wfArqPerfil
        if (-not $wfArqEscopo.Ok -or @($wfArqEscopo.Entries).Count -lt 1) { throw "o escopo de teste saiu vazio ($($wfArqEscopo.Reason))" }
        $wfArqSddlAntes = [string]@($wfArqEscopo.Entries)[0].Sddl

        $wfArqArquivo = Join-Path $wfArqRaiz 'conteudo.txt'
        # A gravação é o ÚNICO ponto que escreve o arquivo de conteúdo, e por isso recusa em
        # SelfTest. A trava é desligada só em volta desta chamada; o 'finally' a devolve mesmo se
        # algo estourar no meio.
        $sync.SelfTest = $false
        $wfArqGrav = Write-WinForgeAclContentBackup -Path $wfArqArquivo -Entries @($wfArqEscopo.Entries)
        $sync.SelfTest = $wfArqSelfAntes
        if (-not $sync.SelfTest) { Write-Host "  [ERRO] Permissões (arquivo): a trava de SelfTest não voltou depois da gravação" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfArqGrav.Ok) { throw "a gravação falhou: $($wfArqGrav.Reason)" }
        # UTF-16LE SEM BOM, pares de linhas - é o que o arquivo do icacls traz, conferido logo
        # abaixo. Cobrar só a AUSÊNCIA de 'FF FE' deixaria passar UTF-8, ASCII e arquivo vazio (o
        # mutante que troca o encoder por UTF8Encoding sobreviveria), por isso o teste afirma
        # o encoding: o primeiro nome é 'perfil\Protegida', então os dois primeiros bytes têm de ser
        # 0x70 ('p') e 0x00 (o byte alto do UTF-16LE).
        $wfArqBytes = [System.IO.File]::ReadAllBytes($wfArqArquivo)
        if ($wfArqBytes.Length -lt 4) { Write-Host "  [ERRO] Permissões (arquivo): o arquivo saiu com $($wfArqBytes.Length) byte(s)" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfArqBytes[0] -eq 0xFF -and $wfArqBytes[1] -eq 0xFE) { Write-Host "  [ERRO] Permissões (arquivo): o arquivo saiu COM BOM - o formato medido é UTF-16LE sem BOM" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfArqBytes[0] -ne 0x70 -or $wfArqBytes[1] -ne 0x00) { Write-Host "  [ERRO] Permissões (arquivo): os dois primeiros bytes são $('0x{0:X2} 0x{1:X2}' -f $wfArqBytes[0], $wfArqBytes[1]), esperado 0x70 0x00 - isto não é UTF-16LE" -ForegroundColor Red; $wbErrors++ }
        # Count no caminho feliz. Sozinha esta linha é fraca - compara a lista de entrada com ela
        # mesma -, e quem prova que 'Count' vem do ARQUIVO é o bloco "contagem" mais abaixo.
        if ([int]$wfArqGrav.Count -ne @($wfArqEscopo.Entries).Count) { Write-Host "  [ERRO] Permissões (arquivo): a gravação relatou Count=$($wfArqGrav.Count) para $(@($wfArqEscopo.Entries).Count) entrada(s)" -ForegroundColor Red; $wbErrors++ }
        if ([long]$wfArqGrav.Bytes -ne [long]$wfArqBytes.Length) { Write-Host "  [ERRO] Permissões (arquivo): a gravação relatou Bytes=$($wfArqGrav.Bytes) e o arquivo tem $($wfArqBytes.Length)" -ForegroundColor Red; $wbErrors++ }
        $wfArqLinhas = @([System.IO.File]::ReadAllText($wfArqArquivo, [System.Text.Encoding]::Unicode) -split "`r`n" | Where-Object { $_ -ne '' })
        if ($wfArqLinhas.Count -ne (2 * @($wfArqEscopo.Entries).Count)) { Write-Host "  [ERRO] Permissões (arquivo): $($wfArqLinhas.Count) linha(s) úteis para $(@($wfArqEscopo.Entries).Count) entrada(s) - o formato é um par por entrada" -ForegroundColor Red; $wbErrors++ }
        # -cne nas duas: o arquivo tem de trazer o texto que a caminhada leu, e não uma versão dele
        # com a caixa mexida. O icacls trata 'FA' e 'fa' como o mesmo direito, então uma comparação
        # sem caixa aceitaria um escritor que reescreve o que copia - e aí não é mais cópia.
        if ([string]$wfArqLinhas[0] -cne 'perfil\Protegida') { Write-Host "  [ERRO] Permissões (arquivo): a primeira linha é '$($wfArqLinhas[0])', esperado o nome relativo 'perfil\Protegida'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfArqLinhas[1] -cne $wfArqSddlAntes) { Write-Host "  [ERRO] Permissões (arquivo): o SDDL gravado difere do lido" -ForegroundColor Red; $wbErrors++ }
        if ((Measure-WinForgeAclSaveEntry -Path $wfArqArquivo) -ne @($wfArqEscopo.Entries).Count) { Write-Host "  [ERRO] Permissões (arquivo): a contagem de entradas não bate" -ForegroundColor Red; $wbErrors++ }

        # CONTRAPROVA: o arquivo que o PRÓPRIO icacls escreve para a mesma árvore.
        $wfArqIcacls = Get-WinForgeSystemExe -Name 'icacls.exe'
        $wfArqRef = Join-Path $wfArqRaiz 'referencia.txt'
        $wfArqRes = Invoke-WinForgeNativeCommand -FilePath $wfArqIcacls -Arguments @($wfArqPerfil, '/save', $wfArqRef, '/T', '/C', '/L') -Encoding 'oem'
        if ([int]$wfArqRes.ExitCode -ne 0) { Write-Host "  [ERRO] Permissões (contraprova): o /save terminou com código $($wfArqRes.ExitCode): $(([string]$wfArqRes.Text).Trim())" -ForegroundColor Red; $wbErrors++ }
        $wfArqRefBytes = [System.IO.File]::ReadAllBytes($wfArqRef)
        # A medida que justifica UnicodeEncoding($false, $false), feita AQUI e não copiada da
        # pesquisa: o arquivo do icacls não começa com a marca. Se um dia começar, é o nosso
        # escritor que passa a estar errado, e é este erro que avisa.
        if ($wfArqRefBytes.Length -lt 4) { Write-Host "  [ERRO] Permissões (contraprova): o /save gravou $($wfArqRefBytes.Length) byte(s)" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfArqRefBytes[0] -eq 0xFF -and $wfArqRefBytes[1] -eq 0xFE) { Write-Host "  [ERRO] Permissões (contraprova): o arquivo do icacls veio COM BOM - o formato medido mudou e o escritor tem de acompanhar" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfArqRefBytes[0] -ne 0x70 -or $wfArqRefBytes[1] -ne 0x00) { Write-Host "  [ERRO] Permissões (contraprova): o arquivo do icacls começa com $('0x{0:X2} 0x{1:X2}' -f $wfArqRefBytes[0], $wfArqRefBytes[1]), esperado 0x70 0x00" -ForegroundColor Red; $wbErrors++ }
        $wfArqRefLinhas = @([System.IO.File]::ReadAllText($wfArqRef, [System.Text.Encoding]::Unicode) -split "`r`n" | Where-Object { $_ -ne '' })
        # O nome relativo é escolha do icacls, não nossa: dado '<pasta>\perfil', ele grava
        # 'perfil\Protegida'. É o que a caminhada monta, e é aqui que as duas versões se encontram.
        $wfArqRefIdx = [array]::IndexOf($wfArqRefLinhas, 'perfil\Protegida')
        if ($wfArqRefIdx -lt 0 -or $wfArqRefIdx + 1 -ge $wfArqRefLinhas.Count) { Write-Host "  [ERRO] Permissões (contraprova): o icacls não gravou o par de 'perfil\Protegida' ($($wfArqRefLinhas.Count) linha(s) úteis)" -ForegroundColor Red; $wbErrors++ }
        # -cne: o SDDL é comparado com MAIÚSCULAS E MINÚSCULAS. 'FA' e 'fa' são o mesmo direito para
        # o icacls, mas uma diferença de caixa aqui significaria que o texto não saiu do mesmo lugar.
        elseif ([string]$wfArqRefLinhas[$wfArqRefIdx + 1] -cne $wfArqSddlAntes) { Write-Host "  [ERRO] Permissões (contraprova): o SDDL do .NET difere do que o icacls gravou`n    .NET  : $wfArqSddlAntes`n    icacls: $($wfArqRefLinhas[$wfArqRefIdx + 1])" -ForegroundColor Red; $wbErrors++ }
        # E a contagem lida num arquivo do PRÓPRIO icacls, que é o caso real: duas entradas, 'perfil'
        # e 'perfil\Protegida'. Contar só o arquivo que nós mesmos escrevemos deixaria passar um erro
        # que o escritor e o leitor cometessem juntos.
        if ((Measure-WinForgeAclSaveEntry -Path $wfArqRef) -ne 2) { Write-Host "  [ERRO] Permissões (contraprova): a contagem no arquivo do icacls deu $(Measure-WinForgeAclSaveEntry -Path $wfArqRef), esperado 2 ('perfil' e 'perfil\Protegida')" -ForegroundColor Red; $wbErrors++ }

        # SHA-256: um byte muda e a impressão digital muda.
        $wfArqH1 = Get-WinForgeAclContentHash -Path $wfArqArquivo
        # 64 hexadecimais em MAIÚSCULAS, cobrado com -cnotmatch: o índice grava esta impressão e
        # depois a compara como texto, então a caixa faz parte do contrato.
        if (-not $wfArqH1.Ok -or [string]$wfArqH1.Hash -cnotmatch '^[0-9A-F]{64}$') { Write-Host "  [ERRO] Permissões (SHA-256): '$($wfArqH1.Hash)' ($($wfArqH1.Reason))" -ForegroundColor Red; $wbErrors++ }
        Add-Content -LiteralPath $wfArqArquivo -Value ' ' -Encoding Unicode
        $wfArqH2 = Get-WinForgeAclContentHash -Path $wfArqArquivo
        if ([string]$wfArqH2.Hash -eq [string]$wfArqH1.Hash) { Write-Host "  [ERRO] Permissões (SHA-256): a impressão digital não mudou com o arquivo alterado" -ForegroundColor Red; $wbErrors++ }
        # Lista vazia não pode virar arquivo vazio: o índice contaria esse arquivo como rede de
        # segurança e ele não segura nada. Quem chama trata a recusa como "esta pasta fica fora".
        $wfArqVazioCam = Join-Path $wfArqRaiz 'vazio.txt'
        $sync.SelfTest = $false
        $wfArqVazio = Write-WinForgeAclContentBackup -Path $wfArqVazioCam -Entries @()
        $sync.SelfTest = $wfArqSelfAntes
        if ($wfArqVazio.Ok) { Write-Host "  [ERRO] Permissões (arquivo): a lista vazia devolveu Ok=`$true" -ForegroundColor Red; $wbErrors++ }
        if (Test-Path -LiteralPath $wfArqVazioCam) { Write-Host "  [ERRO] Permissões (arquivo): a lista vazia deixou um arquivo em '$wfArqVazioCam'" -ForegroundColor Red; $wbErrors++ }
        # CONTAGEM LIDA DO ARQUIVO, e não da lista de entrada. Medido: '[string]$e.Sddl' sobre uma
        # propriedade que LANÇA devolve '' em silêncio - o PowerShell engole erro de propriedade -, e
        # o par vira nome + linha em branco. Contando a lista, a função respondia Ok=$true com
        # Count=2 e um descritor só no disco: backup incompleto passando por bom, descoberto só na
        # hora de desfazer. A asserção de Count lá em cima não pega isto, porque compara a lista de
        # entrada com ela mesma.
        $wfArqMau = New-Object PSObject
        $wfArqMau | Add-Member -MemberType NoteProperty -Name Name -Value 'perfil\Explode'
        $wfArqMau | Add-Member -MemberType ScriptProperty -Name Sddl -Value { throw 'leitura do SDDL falhou' }
        $wfArqMeioCam = Join-Path $wfArqRaiz 'meio.txt'
        $sync.SelfTest = $false
        $wfArqMeio = Write-WinForgeAclContentBackup -Path $wfArqMeioCam -Entries @(@($wfArqEscopo.Entries)[0], $wfArqMau)
        $sync.SelfTest = $wfArqSelfAntes
        if ($wfArqMeio.Ok) { Write-Host "  [ERRO] Permissões (contagem): uma entrada que falha no meio devolveu Ok=`$true com Count=$($wfArqMeio.Count)" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfArqMeio.Reason -notmatch 'incompleta') { Write-Host "  [ERRO] Permissões (contagem): a recusa não diz que a cópia está incompleta ('$($wfArqMeio.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfArqMeio.Count -ne 0) { Write-Host "  [ERRO] Permissões (contagem): a gravação recusada relatou Count=$($wfArqMeio.Count), esperado 0" -ForegroundColor Red; $wbErrors++ }
        # §1.6: o arquivo pela metade não fica no disco.
        if (Test-Path -LiteralPath $wfArqMeioCam) { Write-Host "  [ERRO] Permissões (contagem): o arquivo pela metade ficou em '$wfArqMeioCam'" -ForegroundColor Red; $wbErrors++ }

        # ORDEM ORDINAL (§1.3). Não é estética: a fase 5 roda 'icacls <pasta> /inheritance:e' entrada
        # por entrada, SEM '/T', e depende do pai chegar antes do filho - garantia que só o ordinal
        # dá, porque nele um prefixo ordena sempre antes do que o estende. A lista de teste foi
        # escolhida para SEPARAR ordinal de cultura: por 'Sort-Object' ela sai
        # 'ab | a-b | AppData | AppData\Local | Zebra' (o hífen é ignorado, a caixa não separa); no
        # ordinal, 'A'(0x41) e 'Z'(0x5A) vêm antes de 'a'(0x61), e '-'(0x2D) antes de 'b'(0x62).
        $wfArqOrdEsperado = @('perfil\AppData', 'perfil\AppData\Local', 'perfil\Zebra', 'perfil\a-b', 'perfil\ab')
        $wfArqOrdEntradas = @(@('perfil\ab', 'perfil\a-b', 'perfil\Zebra', 'perfil\AppData\Local', 'perfil\AppData') | ForEach-Object { @{ Name = $_; Sddl = 'D:PAI(A;OICI;FA;;;SY)' } })
        $wfArqOrdCam = Join-Path $wfArqRaiz 'ordem.txt'
        $sync.SelfTest = $false
        $wfArqOrd = Write-WinForgeAclContentBackup -Path $wfArqOrdCam -Entries $wfArqOrdEntradas
        $sync.SelfTest = $wfArqSelfAntes
        if (-not $wfArqOrd.Ok) { Write-Host "  [ERRO] Permissões (ordem): a gravação de teste falhou ('$($wfArqOrd.Reason)')" -ForegroundColor Red; $wbErrors++ }
        else {
            $wfArqOrdSaiu = @(@([System.IO.File]::ReadAllText($wfArqOrdCam, [System.Text.Encoding]::Unicode) -split "`r`n" | Where-Object { $_ -ne '' }) | Where-Object { -not ([string]$_).StartsWith('D:', [StringComparison]::Ordinal) })
            if (($wfArqOrdSaiu -join ' | ') -cne ($wfArqOrdEsperado -join ' | ')) { Write-Host "  [ERRO] Permissões (ordem): saiu '$($wfArqOrdSaiu -join ' | ')', esperada a ordem ordinal '$($wfArqOrdEsperado -join ' | ')'" -ForegroundColor Red; $wbErrors++ }
            if ([int]$wfArqOrd.Count -ne $wfArqOrdEsperado.Count) { Write-Host "  [ERRO] Permissões (ordem): Count=$($wfArqOrd.Count) para $($wfArqOrdEsperado.Count) entrada(s)" -ForegroundColor Red; $wbErrors++ }
        }

        # Caminho RELATIVO recusado nas duas funções: StreamWriter e File::Open resolvem contra o
        # diretório do PROCESSO, e não contra a localização do PowerShell como o Set-Content faria.
        # O backup nasceria fora da pasta protegida sem ninguém ver.
        $sync.SelfTest = $false
        $wfArqRel = Write-WinForgeAclContentBackup -Path 'acl-relativo-do-selftest.txt' -Entries @($wfArqEscopo.Entries)
        $sync.SelfTest = $wfArqSelfAntes
        $wfArqRelH = Get-WinForgeAclContentHash -Path 'acl-relativo-do-selftest.txt'
        if ($wfArqRel.Ok) { Write-Host "  [ERRO] Permissões (caminho): a gravação aceitou caminho relativo" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfArqRel.Reason -notmatch 'absoluto') { Write-Host "  [ERRO] Permissões (caminho): a recusa da gravação não fala em caminho absoluto ('$($wfArqRel.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if ($wfArqRelH.Ok) { Write-Host "  [ERRO] Permissões (caminho): a impressão digital aceitou caminho relativo" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfArqRelH.Reason -notmatch 'absoluto') { Write-Host "  [ERRO] Permissões (caminho): a recusa da impressão digital não fala em caminho absoluto ('$($wfArqRelH.Reason)')" -ForegroundColor Red; $wbErrors++ }
        # E o prefixo '\\?\' provado por COMPORTAMENTO, não por grep no fonte. Duas medições feitas
        # aqui, e as duas custaram um mutante sobrevivente antes de aparecerem:
        #   1. COMPRIMENTO sozinho não prova nada nesta máquina: LongPathsEnabled=1, e 306
        #      caracteres abrem sem prefixo nenhum. Continua valendo para o PC do usuário, onde a
        #      chave é 0 - por isso o caminho fundo fica -, mas não mata mutação aqui.
        #   2. ESPAÇO no fim também não, para ESTAS chamadas: medido, 'Directory::Exists' sem
        #      prefixo responde False numa pasta 'cache ', mas o StreamWriter escreve no destino
        #      exato do mesmo jeito. (No bloco da caminhada o espaço MATA, porque lá quem pergunta é
        #      GetAttributes/GetAccessControl - outro caminho de normalização.)
        # Quem mata aqui é o PONTO no fim: o Win32 come o '.', o StreamWriter vai procurar a pasta
        # 'cache', não acha e estoura. O prefixo desliga essa normalização, e isso nenhuma chave de
        # registro reverte.
        $wfArqFundo = $wfArqRaiz
        while ($wfArqFundo.Length -lt 250) { $wfArqFundo = $wfArqFundo + '\' + ('n' * 30) }
        $wfArqFundo = $wfArqFundo + '\cache.'
        [System.IO.Directory]::CreateDirectory('\\?\' + $wfArqFundo) | Out-Null
        $wfArqLongoCam = $wfArqFundo + '\conteudo-longo.txt'
        $sync.SelfTest = $false
        $wfArqLongo = Write-WinForgeAclContentBackup -Path $wfArqLongoCam -Entries @($wfArqEscopo.Entries)
        $sync.SelfTest = $wfArqSelfAntes
        $wfArqLongoH = Get-WinForgeAclContentHash -Path $wfArqLongoCam
        if (-not $wfArqLongo.Ok) { Write-Host "  [ERRO] Permissões (caminho longo): a gravação em $($wfArqLongoCam.Length) caracteres falhou ('$($wfArqLongo.Reason)') - falta o prefixo \\?\" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfArqLongoH.Ok) { Write-Host "  [ERRO] Permissões (caminho longo): a impressão digital em $($wfArqLongoCam.Length) caracteres falhou ('$($wfArqLongoH.Reason)') - falta o prefixo \\?\" -ForegroundColor Red; $wbErrors++ }
        # E o arquivo foi mesmo parar DENTRO de 'cache.' - sem o prefixo ele nem chegaria lá.
        if (-not [System.IO.File]::Exists('\\?\' + $wfArqLongoCam)) { Write-Host "  [ERRO] Permissões (caminho longo): nada foi gravado em '$wfArqLongoCam' (a pasta com ponto no fim)" -ForegroundColor Red; $wbErrors++ }

        # E a gravação recusa em modo SelfTest - é o único ponto que escreve. Duas provas: a trava no
        # fonte e o COMPORTAMENTO, porque uma trava posta depois da abertura do arquivo passaria na
        # primeira e escreveria assim mesmo.
        $wfArqFonteW = [string](Get-Command Write-WinForgeAclContentBackup).ScriptBlock
        if ($wfArqFonteW -notmatch 'Assert-WinForgeNotSelfTest') { Write-Host "  [ERRO] Permissões (arquivo): Write-WinForgeAclContentBackup sem a trava de SelfTest" -ForegroundColor Red; $wbErrors++ }
        $wfArqRecusaCam = Join-Path $wfArqRaiz 'recusado.txt'
        $wfArqRecusa = $null
        try { Write-WinForgeAclContentBackup -Path $wfArqRecusaCam -Entries @($wfArqEscopo.Entries) | Out-Null } catch { $wfArqRecusa = [string]$_.Exception.Message }
        if ($null -eq $wfArqRecusa -or $wfArqRecusa -notmatch 'SelfTest') { Write-Host "  [ERRO] Permissões (arquivo): a gravação não recusou em modo SelfTest ('$wfArqRecusa')" -ForegroundColor Red; $wbErrors++ }
        if (Test-Path -LiteralPath $wfArqRecusaCam) { Write-Host "  [ERRO] Permissões (arquivo): a gravação recusada ainda deixou '$wfArqRecusaCam' no disco" -ForegroundColor Red; $wbErrors++ }
        # A porta do caminho ABSOLUTO, nas duas funções que tocam o arquivo de backup. Ela diz
        # "precisa ser absoluto" e até aqui perguntava 'IsPathRooted', que é outra pergunta. MEDIDO:
        # 'C:acl.txt' (relativo ao diretório corrente DAQUELE disco) e '\acl.txt' (relativo ao disco
        # corrente) são "rooted", passavam pela porta, viravam '\\?\C:acl.txt' e morriam adiante em
        # "Não foi possível localizar o arquivo". Falha fechada - nada é gravado, medido aqui
        # também -, mas com a mensagem culpando o disco por um caminho que o programa montou.
        # Quem separa os três casos é a RAIZ: 'C:\' e '\\servidor\share' já dizem onde estão;
        # 'C:', '\' e '' dependem de onde o processo está, e GetFullPath resolve cada uma para
        # outra coisa.
        $wfArqSelfAntes2 = $sync.SelfTest
        $sync.SelfTest = $false
        try {
            foreach ($wfArqRel in @('acl.txt', 'C:acl.txt', '\acl.txt')) {
                $wfArqRelG = Write-WinForgeAclContentBackup -Path $wfArqRel -Entries @($wfArqEscopo.Entries)
                if ($wfArqRelG.Ok) { Write-Host "  [ERRO] Permissões (absoluto): a gravação aceitou '$wfArqRel'" -ForegroundColor Red; $wbErrors++ }
                elseif ([string]$wfArqRelG.Reason -notmatch 'precisa ser absoluto') { Write-Host "  [ERRO] Permissões (absoluto): a gravação recusou '$wfArqRel' pelo motivo errado ('$($wfArqRelG.Reason)')" -ForegroundColor Red; $wbErrors++ }
                $wfArqRelH = Get-WinForgeAclContentHash -Path $wfArqRel
                if ($wfArqRelH.Ok) { Write-Host "  [ERRO] Permissões (absoluto): a impressão digital aceitou '$wfArqRel'" -ForegroundColor Red; $wbErrors++ }
                elseif ([string]$wfArqRelH.Reason -notmatch 'precisa ser absoluto') { Write-Host "  [ERRO] Permissões (absoluto): a impressão digital recusou '$wfArqRel' pelo motivo errado ('$($wfArqRelH.Reason)')" -ForegroundColor Red; $wbErrors++ }
            }
            # E nada foi para o disco por nenhum dos três: recusar com a frase certa e ainda assim
            # gravar seria trocar uma mentira por outra.
            foreach ($wfArqRelCam in @((Join-Path (Get-Location).Path 'acl.txt'), 'C:\acl.txt')) {
                if (Test-Path -LiteralPath $wfArqRelCam) { Write-Host "  [ERRO] Permissões (absoluto): a recusa ainda gravou '$wfArqRelCam'" -ForegroundColor Red; $wbErrors++ }
            }
        } finally { $sync.SelfTest = $wfArqSelfAntes2 }
        # A porta NÃO pode recusar caminho absoluto que só o prefixo '\\?\' alcança - é o caso que
        # ela existe para servir. MEDIDO: 'GetFullPath' sobre o caminho INTEIRO come o ponto final
        # de 'cache.' e resolve '..', então comparar o caminho todo recusaria justamente a pasta
        # criada acima. A comparação é sobre a raiz, e por isso estes dois passam.
        foreach ($wfArqAbs in @($wfArqLongoCam, ('\\?\' + $wfArqLongoCam))) {
            $wfArqAbsH = Get-WinForgeAclContentHash -Path $wfArqAbs
            if (-not $wfArqAbsH.Ok) { Write-Host "  [ERRO] Permissões (absoluto): '$wfArqAbs' foi recusado ('$($wfArqAbsH.Reason)') - a porta está comendo o ponto final de 'cache.'" -ForegroundColor Red; $wbErrors++ }
        }
        # Measure-WinForgeAclSaveEntry lê por FLUXO: 'Get-Content' sem -Raw materializa um array e um
        # backup antigo grande vira OutOfMemoryException numa função que só conta linhas.
        $wfArqFonteM = [string](Get-Command Measure-WinForgeAclSaveEntry).ScriptBlock
        if ($wfArqFonteM -match 'Get-Content') { Write-Host "  [ERRO] Permissões (contagem): Measure-WinForgeAclSaveEntry ainda usa Get-Content - tem de ler por StreamReader" -ForegroundColor Red; $wbErrors++ }
        if ($wfArqFonteM -notmatch 'StreamReader') { Write-Host "  [ERRO] Permissões (contagem): Measure-WinForgeAclSaveEntry não usa StreamReader" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (arquivo): UTF-16LE sem BOM, o par de 'perfil\Protegida' idêntico ao do 'icacls /save' da mesma árvore, contagem lida do arquivo, ordem ordinal em $($wfArqOrdEsperado.Count) nomes, caminho de $($wfArqLongoCam.Length) caracteres, SHA-256 sensível a um byte"
    } catch {
        Write-Host "  [ERRO] Permissões (arquivo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        $sync.SelfTest = $wfArqSelfAntes
        # Delete COM prefixo, como no bloco da caminhada: o Remove-Item não alcança o caminho de mais
        # de 250 caracteres criado aqui e deixaria a árvore plantada em %TEMP% para sempre.
        try { [System.IO.Directory]::Delete('\\?\' + $wfArqRaiz, $true) } catch { }
        Remove-Item -LiteralPath $wfArqRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- Permissões: a fase 2 no plano
    try {
        $wfF2Plano = @(Get-WinForgeAclRestorePlan -Profile 'C:\Users\fulano' -UserSid 'S-1-5-21-1-2-3-1001' -BackupRoot (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-plano') -Stamp '20260912-101010')
        $wfF2Save = @($wfF2Plano | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'save' })
        if ($wfF2Save.Count) { Write-Host "  [ERRO] Permissões (fase 2): o passo 'save' com 'icacls /T' continua no plano - ele é o laço que encheu o disco" -ForegroundColor Red; $wbErrors++ }
        $wfF2Escopo = @($wfF2Plano | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'scope' })
        if ($wfF2Escopo.Count -ne 1) { Write-Host "  [ERRO] Permissões (fase 2): esperava 1 passo 'scope', veio $($wfF2Escopo.Count)" -ForegroundColor Red; $wbErrors++ }
        else {
            if ($wfF2Escopo[0].FilePath) { Write-Host "  [ERRO] Permissões (fase 2): o passo 'scope' não pode ter executável - quem caminha é o motor" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfF2Escopo[0].Target -ne 'C:\Users') { Write-Host "  [ERRO] Permissões (fase 2): Target='$($wfF2Escopo[0].Target)', esperado 'C:\Users' (a pasta de onde o /restore roda)" -ForegroundColor Red; $wbErrors++ }
        }
        # Nenhum passo do plano inteiro pode carregar '/T' sobre a pasta de perfil. A varredura é
        # geral de novo: a fase 5 era a última exceção e caiu junto com o passo 'inherit', então o
        # pino que cobrava "exatamente uma" saiu daqui no mesmo commit. Exceção anotada que
        # sobrevive à própria causa vira moradia.
        foreach ($wfF2P in $wfF2Plano) {
            $wfF2Args = @($wfF2P.Arguments | ForEach-Object { [string]$_ })
            if (-not (($wfF2Args -contains '/T') -and ((@($wfF2Args) -join ' ') -like '*C:\Users\fulano*'))) { continue }
            Write-Host "  [ERRO] Permissões (plano): passo da fase $($wfF2P.Phase) ainda usa '/T' sobre a pasta de perfil ('$($wfF2Args -join ' ')')" -ForegroundColor Red; $wbErrors++
        }
        # Espaço livre conferido ANTES: pedir mais do que o disco tem recusa, e diz quanto há.
        $wfF2Esp = Test-WinForgeAclFreeSpace -Path $wbSelfTestTemp -Bytes ([long]1PB)
        if ($wfF2Esp.Ok) { Write-Host "  [ERRO] Permissões (espaço): 1 PB deveria ser recusado" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Esp.Reason -notmatch '\d') { Write-Host "  [ERRO] Permissões (espaço): a recusa não traz o número na tela ('$($wfF2Esp.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeAclFreeSpace -Path $wbSelfTestTemp -Bytes 103400).Ok) { Write-Host "  [ERRO] Permissões (espaço): 103,4 KB foram recusados" -ForegroundColor Red; $wbErrors++ }
        # 'Denied > 0' muda o VEREDITO: cabeçalho, contagem e as 20 primeiras pastas.
        $wfF2Ver = Get-WinForgeAclScopeVerdict -Scope @{ Ok = $true; Denied = 3; DeniedPaths = @('C:\Users\fulano\A', 'C:\Users\fulano\B', 'C:\Users\fulano\C'); Entries = @(1, 2) }
        if ([string]$wfF2Ver.Header -ne 'Concluído com ressalvas') { Write-Host "  [ERRO] Permissões (ressalvas): cabeçalho '$($wfF2Ver.Header)', esperado 'Concluído com ressalvas'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Ver.Text -notmatch 'não foram copiadas nem alteradas') { Write-Host "  [ERRO] Permissões (ressalvas): falta a frase de que essas pastas não foram copiadas nem alteradas" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Ver.Text -notmatch 'C:\\Users\\fulano\\A') { Write-Host "  [ERRO] Permissões (ressalvas): a lista de DeniedPaths não aparece no texto" -ForegroundColor Red; $wbErrors++ }
        # A CONTAGEM no texto, e não só a frase. §1.7 pede o número; sem esta linha, trocar
        # "$negadas pasta(s)" por "Algumas pasta(s)" passava verde - mutante que sobreviveu na
        # revisão da Tarefa 3.
        if ([string]$wfF2Ver.Text -notmatch '(?m)^3 pasta\(s\)') { Write-Host "  [ERRO] Permissões (ressalvas): o texto não abre com a CONTAGEM de pastas não lidas ('$([string]$wfF2Ver.Text -split "`n" | Select-Object -First 1)')" -ForegroundColor Red; $wbErrors++ }
        $wfF2Muitas = Get-WinForgeAclScopeVerdict -Scope @{ Ok = $true; Denied = 50; DeniedPaths = @(1..50 | ForEach-Object { "C:\p$_" }); Entries = @(1) }
        if (@([regex]::Matches([string]$wfF2Muitas.Text, 'C:\\p\d+')).Count -ne 20) { Write-Host "  [ERRO] Permissões (ressalvas): o texto tem de listar as 20 PRIMEIRAS, veio $(@([regex]::Matches([string]$wfF2Muitas.Text, 'C:\\p\d+')).Count)" -ForegroundColor Red; $wbErrors++ }
        # Contagem e lista de caminhos têm tetos DIFERENTES: a contagem não tem, a anotação de
        # caminhos para em 200. Com 500 negadas o texto dizia "500 pasta(s)" e emendava "As 20
        # primeiras, de 200" - quem lê conclui que 300 sumiram do relatório. Os números têm de
        # fechar, ou o texto tem de dizer por que não fecham.
        $wfF2Trunc = Get-WinForgeAclScopeVerdict -Scope @{ Ok = $true; Denied = 500; DeniedPaths = @(1..200 | ForEach-Object { "C:\q$_" }); Entries = @(1) }
        if ([string]$wfF2Trunc.Text -notmatch '(?m)^500 pasta\(s\)') { Write-Host "  [ERRO] Permissões (ressalvas): com a lista truncada a contagem total sumiu da primeira linha" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Trunc.Text -notmatch '300') { Write-Host "  [ERRO] Permissões (ressalvas): o texto não diz que 300 pastas foram contadas sem o caminho anotado - '500' e 'de 200' se contradizem na tela" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Trunc.Text -match 'primeiras, de 200') { Write-Host "  [ERRO] Permissões (ressalvas): o texto ainda emenda 'de 200' logo abaixo de '500 pasta(s)'" -ForegroundColor Red; $wbErrors++ }
        $wfF2Limpo = Get-WinForgeAclScopeVerdict -Scope @{ Ok = $true; Denied = 0; DeniedPaths = @(); Entries = @(1) }
        if ([string]$wfF2Limpo.Header -ne 'Concluído') { Write-Host "  [ERRO] Permissões (ressalvas): sem Denied o cabeçalho é 'Concluído', veio '$($wfF2Limpo.Header)'" -ForegroundColor Red; $wbErrors++ }
        # O arquivo parcial some no 'finally', e não dentro do laço: hoje o descarte não roda se o
        # processo morre no meio.
        $wfF2Fonte = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if ($wfF2Fonte -notmatch '(?s)finally\s*\{[^}]*Remove-Item[^}]*parcial') { Write-Host "  [ERRO] Permissões (parcial): falta o 'finally' que apaga o arquivo de conteúdo pela metade" -ForegroundColor Red; $wbErrors++ }
        if ($wfF2Fonte -notmatch 'Get-WinForgeAclContentScope') { Write-Host "  [ERRO] Permissões (fase 2): Invoke-WinForgeAclRestore não usa a caminhada" -ForegroundColor Red; $wbErrors++ }
        if ($wfF2Fonte -notmatch 'Get-WinForgeAclContentHash') { Write-Host "  [ERRO] Permissões (fase 2): o índice não recebe o SHA-256 do arquivo de conteúdo" -ForegroundColor Red; $wbErrors++ }
        # A linha acima prova que o hash é CALCULADO, não que ele CHEGA ao índice. Mutante que
        # sobreviveu na revisão da Tarefa 3: trocar 'Sha256 = $impressao' por 'Sha256 = ''' ficava
        # verde, e a Tarefa 5 - que recusa o backup cujo hash não bate - herdaria um campo vazio sem
        # aviso nenhum. As duas pontas da corrente, então: o hash sai da função, e o campo do índice
        # recebe esse valor.
        if ($wfF2Fonte -notmatch '\$impressao\s*=\s*\[string\]\$hash\.Hash') { Write-Host "  [ERRO] Permissões (fase 2): o SHA-256 do índice não sai de Get-WinForgeAclContentHash" -ForegroundColor Red; $wbErrors++ }
        if ($wfF2Fonte -notmatch 'Sha256\s*=\s*\$impressao') { Write-Host "  [ERRO] Permissões (fase 2): o item de conteúdo do índice não grava o SHA-256 calculado - um campo vazio ali passa por 'sem conferência' sem nenhum aviso" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (fase 2): passo 'scope' sem icacls, nenhum '/T' sobre o perfil, espaço conferido antes, veredito com ressalvas e finally do parcial"
    } catch {
        Write-Host "  [ERRO] Permissões (fase 2): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # ---------------------------------------------------------------- Permissões: a ordem das ACEs de negação
    # O SDDL da caminhada vem do .NET, em ordem CANÔNICA - negação antes de permissão. Numa lista só
    # de permissão isso é indiferente (34 das 338 do perfil medido diferem só nisso). Com NEGAÇÃO
    # não é: devolver a ordem canônica a uma pasta que não estava canônica faz a negação passar a
    # vencer, e o Desfazer TRANCA o usuário. Por isso a entrada que nega traz o texto do próprio
    # icacls. Aqui a pasta é criada em %TEMP%, com uma negação de verdade, e o que a função devolve
    # é comparado com o que o icacls escreve por fora - sem elevação: 'icacls /save' não precisa
    # dela numa pasta cuja dona é a própria identidade.
    $wfOrdRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-ordem'
    $wfOrdRegra = $null
    $wfOrdDi = $null
    try {
        if (Test-Path -LiteralPath $wfOrdRaiz) { Remove-Item -LiteralPath $wfOrdRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        $wfOrdPerfil = Join-Path $wfOrdRaiz 'perfil'
        $wfOrdAlvo = Join-Path $wfOrdPerfil 'Negada'
        New-Item -ItemType Directory -Path $wfOrdAlvo -Force | Out-Null
        $wfOrdDi = New-Object System.IO.DirectoryInfo $wfOrdAlvo
        $wfOrdSd = $wfOrdDi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $wfOrdSd.SetAccessRuleProtection($true, $true)
        $wfOrdRegra = New-Object System.Security.AccessControl.FileSystemAccessRule(([System.Security.Principal.WindowsIdentity]::GetCurrent().User), [System.Security.AccessControl.FileSystemRights]::WriteData, [System.Security.AccessControl.InheritanceFlags]::None, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Deny)
        $wfOrdSd.AddAccessRule($wfOrdRegra)
        $wfOrdDi.SetAccessControl($wfOrdSd)
        # 1. A caminhada marca a entrada, e não só conta: quem vai reler é o chamador, e ele precisa
        # saber QUAL entrada nega. Um segundo detector no chamador seria um segundo padrão a manter.
        $wfOrdEscopo = Get-WinForgeAclContentScope -Path $wfOrdPerfil
        if (-not $wfOrdEscopo.Ok) { throw "o escopo de teste falhou ($($wfOrdEscopo.Reason))" }
        $wfOrdNegadas = @(@($wfOrdEscopo.Entries) | Where-Object { $_.Deny })
        if ($wfOrdNegadas.Count -ne 1) { Write-Host "  [ERRO] Permissões (ordem de ACE): $($wfOrdNegadas.Count) entrada(s) marcadas com Deny, esperado 1 - sem a marca por entrada o chamador não sabe qual reler" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfOrdNegadas[0].Name -ne 'perfil\Negada') { Write-Host "  [ERRO] Permissões (ordem de ACE): a entrada marcada é '$($wfOrdNegadas[0].Name)', esperada 'perfil\Negada'" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfOrdEscopo.Deny -ne @(@($wfOrdEscopo.Entries) | Where-Object { $_.Deny }).Count) { Write-Host "  [ERRO] Permissões (ordem de ACE): o contador 'Deny' ($($wfOrdEscopo.Deny)) discorda das entradas marcadas" -ForegroundColor Red; $wbErrors++ }
        # 2. E o texto do icacls, comparado com o que ele mesmo escreve por fora. -cne: 'FA' e 'fa'
        # são o mesmo direito para o icacls, mas caixa diferente aqui significaria que o texto não
        # saiu do mesmo lugar.
        $wfOrdTrab = Join-Path $wfOrdRaiz 'trabalho.tmp'
        $wfOrdRes = Get-WinForgeAclIcaclsSddl -Path $wfOrdAlvo -WorkFile $wfOrdTrab
        if (-not $wfOrdRes.Ok) { Write-Host "  [ERRO] Permissões (ordem de ACE): o texto do icacls não pôde ser lido ('$($wfOrdRes.Reason)')" -ForegroundColor Red; $wbErrors++ }
        else {
            # MEDIDO: 'icacls <pasta absoluta> /save f /L /Q', sem barra no fim e sem '/T', sai com
            # UM par só, e o nome dele é a FOLHA da pasta - não um nome vazio e não os filhos. É
            # esse par que a função tem de devolver.
            $wfOrdRef = Join-Path $wfOrdRaiz 'referencia.txt'
            & (Get-WinForgeSystemExe -Name 'icacls.exe') $wfOrdAlvo '/save' $wfOrdRef '/L' '/Q' | Out-Null
            $wfOrdLinhas = @([System.IO.File]::ReadAllText($wfOrdRef, [System.Text.Encoding]::Unicode) -split "`r`n")
            if ([string]$wfOrdLinhas[0] -cne 'Negada') { Write-Host "  [ERRO] Permissões (ordem de ACE): o '/save' de referência nomeou a entrada '$($wfOrdLinhas[0])', esperada a folha 'Negada'" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfOrdRes.Sddl -cne [string]$wfOrdLinhas[1]) { Write-Host "  [ERRO] Permissões (ordem de ACE): o texto devolvido difere do que o icacls escreve`n    função: $($wfOrdRes.Sddl)`n    icacls: $($wfOrdLinhas[1])" -ForegroundColor Red; $wbErrors++ }
            # E o texto é mesmo uma lista com negação: sem isso a pasta de teste não exercitaria o
            # caminho que esta função existe para cobrir.
            if ([string]$wfOrdRes.Sddl -notmatch '\([OXZ]?D;') { Write-Host "  [ERRO] Permissões (ordem de ACE): o texto devolvido não tem ACE de negação ('$($wfOrdRes.Sddl)') - a pasta de teste não exercita o caminho" -ForegroundColor Red; $wbErrors++ }
        }
        # 3. O arquivo de trabalho não fica no disco: ele carrega a lista de permissões de uma pasta
        # do usuário e some assim que o texto é lido.
        if (Test-Path -LiteralPath $wfOrdTrab) { Write-Host "  [ERRO] Permissões (ordem de ACE): o arquivo de trabalho ficou em '$wfOrdTrab'" -ForegroundColor Red; $wbErrors++ }
        # 4. Pasta que não existe: recusa, com o CÓDIGO do icacls na frase. Duas medições feitas
        # aqui sustentam esta linha, e a primeira custou um mutante sobrevivente:
        #   1. COM '/C' o icacls sai com 0 mesmo sem achar a pasta - '/C' é "continue apesar do
        #      erro", e num alvo único ele só apaga o sinal de falha. Sem '/C' o mesmo caso sai com
        #      2. Por isso o '/C' ficou de fora desta chamada, ao contrário do resto do reparo.
        #   2. O arquivo de saída é TRUNCADO antes de o icacls falhar, então quem não conferir o
        #      código ainda assim recusa - só que pela frase errada ("não trouxe '' onde era
        #      esperada a folha"), que não diz nada a quem lê o log de um reparo elevado. O código
        #      na frase é o que esta asserção cobra.
        $wfOrdSumiu = Get-WinForgeAclIcaclsSddl -Path (Join-Path $wfOrdPerfil 'nunca-existiu') -WorkFile $wfOrdTrab
        if ($wfOrdSumiu.Ok) { Write-Host "  [ERRO] Permissões (ordem de ACE): uma pasta inexistente devolveu Ok=`$true" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfOrdSumiu.Reason -notmatch 'código \d+') { Write-Host "  [ERRO] Permissões (ordem de ACE): a recusa não diz com que código o icacls saiu ('$($wfOrdSumiu.Reason)')" -ForegroundColor Red; $wbErrors++ }
        # 5. A conferência do NOME, provada na raiz do volume - o caso em que o icacls escolhe outro
        # nome. Medido aqui, sem elevação: 'icacls C:\ /save f /L /Q' sai com 0 e grava a entrada
        # com o NOME VAZIO, enquanto a folha de 'C:\' é 'C:\'. É a mesma entrada de nome vazio que
        # o '/restore' nunca soube aplicar, e aceitá-la como resposta poria o descritor da RAIZ do
        # disco no backup do conteúdo do perfil. Sem a conferência de nome nada disso apareceria.
        $wfOrdRaizVol = Get-WinForgeAclIcaclsSddl -Path 'C:\' -WorkFile $wfOrdTrab
        if ($wfOrdRaizVol.Ok) { Write-Host "  [ERRO] Permissões (ordem de ACE): a raiz do volume foi aceita ('$($wfOrdRaizVol.Sddl)') - o icacls grava a entrada dela com o nome VAZIO e o nome não está sendo conferido" -ForegroundColor Red; $wbErrors++ }
        if (-not [string]::IsNullOrEmpty([string]$wfOrdRaizVol.Sddl)) { Write-Host "  [ERRO] Permissões (ordem de ACE): a recusa da raiz ainda devolveu um SDDL ('$($wfOrdRaizVol.Sddl)')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (ordem de ACE): a entrada que nega vem marcada da caminhada e o SDDL dela sai do próprio icacls, igual ao do '/save' de referência"
    } catch {
        Write-Host "  [ERRO] Permissões (ordem de ACE): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        # A negação sai antes da faxina: com ela no lugar a pasta não volta a ser apagável.
        if ($null -ne $wfOrdRegra -and $null -ne $wfOrdDi) {
            try {
                $wfOrdDi2 = New-Object System.IO.DirectoryInfo $wfOrdDi.FullName
                $wfOrdSd2 = $wfOrdDi2.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
                $null = $wfOrdSd2.RemoveAccessRuleSpecific($wfOrdRegra)
                $wfOrdDi2.SetAccessControl($wfOrdSd2)
            } catch { }
        }
        Remove-Item -LiteralPath $wfOrdRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- Permissões: a fase 5 sem /T
    # Conserta de quebra um defeito da 1.7.0: '/inheritance:e /T /L' liga herança FORA do perfil,
    # no destino de cada junção e no OneDrive. Uma chamada por entrada da lista da fase 2 não sai
    # do conjunto que o backup cobre - e é isso que mantém "guardado = alterado".
    try {
        $wfF5Entradas = @(
            @{ Name = 'fulano\AppData\Local\Pacotes'; Sddl = 'D:P(A;;FA;;;SY)' },
            @{ Name = 'fulano'; Sddl = 'D:P(A;;FA;;;SY)' },
            @{ Name = 'fulano\AppData'; Sddl = 'D:P(A;;FA;;;SY)' }
        )
        $wfF5Passos = @(Get-WinForgeAclInheritSteps -Root 'C:\Users' -Entries $wfF5Entradas)
        if ($wfF5Passos.Count -ne 3) { Write-Host "  [ERRO] Permissões (fase 5): $($wfF5Passos.Count) passo(s) para 3 entradas" -ForegroundColor Red; $wbErrors++ }
        $wfF5Ordem = @($wfF5Passos | ForEach-Object { [string]$_.Path })
        if ([string]$wfF5Ordem[0] -ne 'C:\Users\fulano') { Write-Host "  [ERRO] Permissões (fase 5): a ordem ordinal tem de entregar o pai primeiro, veio '$($wfF5Ordem -join ' | ')'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF5Ordem[2] -ne 'C:\Users\fulano\AppData\Local\Pacotes') { Write-Host "  [ERRO] Permissões (fase 5): o filho mais fundo tem de vir por último, veio '$($wfF5Ordem -join ' | ')'" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfF5P in $wfF5Passos) {
            $wfF5A = @($wfF5P.Arguments | ForEach-Object { [string]$_ })
            if ($wfF5A -contains '/T') { Write-Host "  [ERRO] Permissões (fase 5): '/T' voltou ao vetor ('$($wfF5A -join ' ')')" -ForegroundColor Red; $wbErrors++ }
            if ($wfF5A -notcontains '/inheritance:e') { Write-Host "  [ERRO] Permissões (fase 5): falta '/inheritance:e' ('$($wfF5A -join ' ')')" -ForegroundColor Red; $wbErrors++ }
            # E sem '/C'. MEDIDO nesta forma exata, sem elevação: pasta que não existe sai com 2 sem
            # '/C' e com 0 COM '/C'. Num alvo único não há o que "continuar"; o '/C' só apagaria o
            # código de saída, e com ele o 'if' do chamador vira código morto - a fase 5 poderia não
            # ligar herança em pasta nenhuma e o log dizer "Concluído".
            if ($wfF5A -contains '/C') { Write-Host "  [ERRO] Permissões (fase 5): '/C' voltou ao vetor ('$($wfF5A -join ' ')') - ele zera o código de saída e o chamador perde o sinal" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfF5P.FilePath -ne (Get-WinForgeSystemExe -Name 'icacls.exe')) { Write-Host "  [ERRO] Permissões (fase 5): o executável não é o icacls do System32 ('$($wfF5P.FilePath)')" -ForegroundColor Red; $wbErrors++ }
        }
        # O conjunto coberto é o conjunto alterado: mesma lista, mesma contagem.
        $wfF5Plano = @(Get-WinForgeAclRestorePlan -Profile 'C:\Users\fulano' -UserSid 'S-1-5-21-1-2-3-1001' -BackupRoot (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-plano') -Stamp '20260912-101010')
        $wfF5Velho = @($wfF5Plano | Where-Object { [int]$_.Phase -eq 5 -and [string]$_.Kind -eq 'inherit' })
        if ($wfF5Velho.Count) { Write-Host "  [ERRO] Permissões (fase 5): o passo 'inherit' com '/T' continua no plano" -ForegroundColor Red; $wbErrors++ }
        $wfF5Lista = @($wfF5Plano | Where-Object { [int]$_.Phase -eq 5 -and [string]$_.Kind -eq 'inherit-list' })
        if ($wfF5Lista.Count -ne 1) { Write-Host "  [ERRO] Permissões (fase 5): esperava 1 passo 'inherit-list', veio $($wfF5Lista.Count)" -ForegroundColor Red; $wbErrors++ }
        $wfF5Fonte = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if ($wfF5Fonte -notmatch 'Get-WinForgeAclInheritSteps') { Write-Host "  [ERRO] Permissões (fase 5): a fase 5 não monta os passos a partir da lista da fase 2" -ForegroundColor Red; $wbErrors++ }
        # A busca é pela CHAMADA ('-Root' junto), e não pelo nome. O nome também aparece no bloco de
        # ajuda de Invoke-WinForgeAclRestore, que entra no ScriptBlock e faria a linha acima passar
        # sozinha: um mutante que trocasse a chamada por um laço à mão sobreviveria. É a mesma trava
        # que a fase 4 já usa para Invoke-WinForgeAclOwnerFallback.
        if ($wfF5Fonte.IndexOf('Get-WinForgeAclInheritSteps -Root', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (fase 5): a fase 5 CITA Get-WinForgeAclInheritSteps mas não a chama - a lista da fase 2 não está virando chamada nenhuma" -ForegroundColor Red; $wbErrors++ }
        # Com o '/C' fora, o código de saída volta a dizer alguma coisa - mas ele NÃO serve para
        # separar "sumiu" de "falhou", e foi esse o defeito. MEDIDO nesta forma exata de chamada
        # ('icacls <alvo> /inheritance:e /Q', sem elevação e sem curinga): pasta inexistente com o
        # pai no lugar sai 2, mas PAI inexistente sai 3, pai inexistente a dois níveis sai 3 e
        # unidade inexistente sai 3 - e o curinga sem correspondência, que a descrição antiga
        # culpava pelo 3, sai 0.
        #
        # E pai e filho estão os DOIS nesta lista: a caminhada da fase 2 desce em toda pasta com
        # herança bloqueada, e 'AppData\Local\Packages\<app>' com '...\<app>\LocalCache' é o arranjo
        # normal de aplicativo da Loja. Desinstalado o aplicativo entre as fases, a ordem ordinal
        # manda o pai primeiro: o pai sai com 2 (aviso) e cada descendente com 3 (erro) - um reparo
        # que correu bem terminando numa lista de erros, que é o oposto do que o ramo existe para
        # fazer. Por isso a classificação é pela EXISTÊNCIA da pasta.
        $wfF5Existe = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-fase5-existe'
        $wfF5Espaco = ''
        try {
            if (Test-Path -LiteralPath $wfF5Existe) { Remove-Item -LiteralPath $wfF5Existe -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $wfF5Existe -Force | Out-Null
            $wfF5Sumiu = Join-Path $wfF5Existe 'nunca-existiu\mais-fundo'
            foreach ($wfF5Caso in @(
                @{ Path = $wfF5Existe; Code = 0; Esperado = 'ok';     Porque = 'chamada que deu certo' },
                @{ Path = $wfF5Existe; Code = 2; Esperado = 'falha';  Porque = 'a pasta está no lugar - código 2 aqui é falha de verdade' },
                @{ Path = $wfF5Existe; Code = 3; Esperado = 'falha';  Porque = 'a pasta está no lugar' },
                @{ Path = $wfF5Existe; Code = 5; Esperado = 'falha';  Porque = 'acesso negado numa pasta que existe' },
                @{ Path = $wfF5Sumiu;  Code = 2; Esperado = 'sumida'; Porque = 'a pasta foi apagada desde o backup' },
                @{ Path = $wfF5Sumiu;  Code = 3; Esperado = 'sumida'; Porque = 'o PAI foi apagado desde o backup - o 3 que o ramo antigo tratava como erro' },
                @{ Path = $wfF5Sumiu;  Code = 0; Esperado = 'ok';     Porque = 'código 0 responde antes de qualquer pergunta ao disco' },
                @{ Path = '';          Code = 3; Esperado = 'falha';  Porque = 'sem caminho não dá para AFIRMAR que sumiu' }
            )) {
                $wfF5Ver = [string](Get-WinForgeAclInheritOutcome -Path ([string]$wfF5Caso.Path) -ExitCode ([int]$wfF5Caso.Code))
                if ($wfF5Ver -ne [string]$wfF5Caso.Esperado) { Write-Host "  [ERRO] Permissões (fase 5): '$($wfF5Caso.Path)' com código $($wfF5Caso.Code) deu '$wfF5Ver', esperado '$($wfF5Caso.Esperado)' ($($wfF5Caso.Porque))" -ForegroundColor Red; $wbErrors++ }
            }
            # Pasta com ESPAÇO no fim do nome. Ela existe (o Windows cria por '\\?\'), e é a pergunta
            # pelo caminho longo que a enxerga: sem o prefixo, a API normaliza o nome, corta o espaço
            # e responde que não existe - a pasta viraria "sumiu desde o backup" e a falha de verdade
            # sairia como aviso, calada. O mesmo prefixo que a caminhada da fase 2 já usa.
            $wfF5Espaco = (Join-Path $wfF5Existe 'com espaco ')
            try { [void][System.IO.Directory]::CreateDirectory('\\?\' + $wfF5Espaco) } catch { $wfF5Espaco = '' }
            if ([string]::IsNullOrEmpty($wfF5Espaco)) { Write-Host "  [ERRO] Permissões (fase 5): a pasta com espaço no fim não pôde ser criada - o caso do caminho longo não foi exercitado" -ForegroundColor Red; $wbErrors++ }
            elseif ([string](Get-WinForgeAclInheritOutcome -Path $wfF5Espaco -ExitCode 5) -ne 'falha') { Write-Host "  [ERRO] Permissões (fase 5): pasta com espaço no fim do nome foi dada como sumida - a existência tem de ser perguntada pelo caminho longo ('\\?\')" -ForegroundColor Red; $wbErrors++ }
        } finally {
            if (-not [string]::IsNullOrEmpty($wfF5Espaco)) { try { [System.IO.Directory]::Delete('\\?\' + $wfF5Espaco) } catch { } }
            Remove-Item -LiteralPath $wfF5Existe -Recurse -Force -ErrorAction SilentlyContinue
        }
        # E a fase 5 CHAMA a classificação, em vez de só citá-la: o nome também aparece no bloco de
        # ajuda, que entra no ScriptBlock. A cobrança é pela chamada, com o parâmetro junto.
        if ($wfF5Fonte.IndexOf('Get-WinForgeAclInheritOutcome -Path', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (fase 5): a fase 5 não classifica o resultado por Get-WinForgeAclInheritOutcome" -ForegroundColor Red; $wbErrors++ }
        # E o veredito está LIGADO aos contadores. Chamar a classificação e depois ignorar o que ela
        # respondeu daria o mesmo resultado de não chamar - e a linha acima passaria. As duas agulhas
        # são montadas por concatenação: escritas inteiras, elas contêm o próprio '$sumidas5' e
        # ficariam sujeitas à expansão de variável na hora do teste.
        foreach ($wfF5Fio in @(("'ok'" + ') { continue }'), ("'sumida'" + ') { $sumidas5++'))) {
            if ($wfF5Fonte.IndexOf($wfF5Fio, [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (fase 5): o veredito da classificação não está ligado aos contadores (falta ""$wfF5Fio"")" -ForegroundColor Red; $wbErrors++ }
        }
        # A medição errada não pode voltar à descrição: era ela que atribuía o código 3 ao curinga, e
        # foi por ela que se concluiu que o 3 não era produzível nesta forma de chamada. MEDIDO aqui:
        # o curinga sem correspondência sai 0, e quem sai 3 é caminho inexistente ACIMA do alvo.
        $wfF5FonteP = [string](Get-Command Get-WinForgeAclInheritSteps).ScriptBlock
        if ($wfF5FonteP -match "curinga sem correspond.ncia\s*->\s*0 com '/C' e 3 sem") { Write-Host "  [ERRO] Permissões (fase 5): a descrição voltou a atribuir o código 3 ao curinga - medido, o curinga sem correspondência sai 0" -ForegroundColor Red; $wbErrors++ }
        if ($wfF5FonteP -notmatch 'PAI da pasta não existe') { Write-Host "  [ERRO] Permissões (fase 5): a descrição não registra que PAI inexistente sai 3 - foi a falta dessa linha que fez o código 3 parecer improduzível aqui" -ForegroundColor Red; $wbErrors++ }
        # E o ramo antigo não volta: separar aviso de erro por um código de saída, qualquer que seja
        # ele, reintroduz o defeito que esta trava existe para prender.
        if ($wfF5Fonte -match '\$c5\s*-eq\s*\d') { Write-Host "  [ERRO] Permissões (fase 5): a fase 5 voltou a separar aviso de erro pelo CÓDIGO de saída do icacls" -ForegroundColor Red; $wbErrors++ }
        if ($wfF5Fonte -notmatch 'sumidas5') { Write-Host "  [ERRO] Permissões (fase 5): o resumo não conta quantas pastas já não existiam" -ForegroundColor Red; $wbErrors++ }
        if ($wfF5Fonte -notmatch 'WinForgeAclScope') { Write-Host "  [ERRO] Permissões (fase 5): a fase 5 não lê o escopo guardado pela fase 2 - guardado e alterado divergiriam" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (fase 5): $($wfF5Passos.Count) chamada(s) '/inheritance:e' por entrada, pai antes de filho, nenhum '/T'; aviso e erro separados pela existência da pasta, não pelo código"
    } catch {
        Write-Host "  [ERRO] Permissões (fase 5): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # ---------------------------------------------------------------- Permissões: um índice por vez
    # Defeito da 1.7.0, confirmado no código (:3044 e :2760-2769): o Desfazer lia o índice MAIS NOVO.
    # Na 2ª execução a fase 5 da 1ª já tinha removido a proteção de herança, o escopo caía para perto
    # de zero e o índice novo - que continua com os itens 'sddl' das fases 3 e 4 - virava o único
    # visível. As 338 originais ficavam irrecuperáveis.
    $wfIdxRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-indices'
    try {
        if (Test-Path -LiteralPath $wfIdxRaiz) { Remove-Item -LiteralPath $wfIdxRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfIdxRaiz -Force | Out-Null
        $wfIdxOrigem = New-WinForgeAclIndexOrigin
        if ([string]::IsNullOrWhiteSpace([string]$wfIdxOrigem.MachineGuid) -or [string]::IsNullOrWhiteSpace([string]$wfIdxOrigem.ProfileSid)) { Write-Host "  [ERRO] Permissões (origem): New-WinForgeAclIndexOrigin veio incompleta ('$($wfIdxOrigem.MachineGuid)' / '$($wfIdxOrigem.ProfileSid)')" -ForegroundColor Red; $wbErrors++ }
        $wfIdxGrava = {
            param($Nome, $Consumido, $Origem)
            $conteudo = [pscustomobject]@{
                Stamp = $Nome; Consumed = $Consumido; Origin = $Origem
                Items = @([pscustomobject]@{ Path = 'C:\Users\fulano'; Sddl = 'D:P(A;;FA;;;SY)'; Owner = 'SYSTEM'; OwnerSid = 'S-1-5-18'; File = ''; Target = ''; Sha256 = ''; ExternalPath = '' })
            }
            Set-Content -LiteralPath (Join-Path $wfIdxRaiz "acl-index-$Nome.json") -Value ($conteudo | ConvertTo-Json -Depth 5) -Encoding UTF8
        }
        & $wfIdxGrava '20260101-000000' $false $wfIdxOrigem
        & $wfIdxGrava '20260202-000000' $false $wfIdxOrigem
        $wfIdxLista = @(Get-WinForgeAclIndexList -Root $wfIdxRaiz)
        if ($wfIdxLista.Count -ne 2) { Write-Host "  [ERRO] Permissões (índices): a lista trouxe $($wfIdxLista.Count), esperado 2" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfIdxLista[0].Stamp -ne '20260101-000000') { Write-Host "  [ERRO] Permissões (índices): a lista não vem do mais antigo para o mais novo ('$($wfIdxLista[0].Stamp)')" -ForegroundColor Red; $wbErrors++ }
        $wfIdxConj = Get-WinForgeAclBackupSet -Root $wfIdxRaiz
        if ([string]$wfIdxConj.Stamp -ne '20260101-000000') { Write-Host "  [ERRO] Permissões (Desfazer): o conjunto escolhido é '$($wfIdxConj.Stamp)', esperado o MAIS ANTIGO não consumido '20260101-000000'" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfIdxConj.Pending -ne 2) { Write-Host "  [ERRO] Permissões (Desfazer): Pending=$($wfIdxConj.Pending), esperado 2" -ForegroundColor Red; $wbErrors++ }
        # Consumido some da fila; o seguinte assume.
        if (-not (Set-WinForgeAclIndexConsumed -Path (Join-Path $wfIdxRaiz 'acl-index-20260101-000000.json')).Ok) { Write-Host "  [ERRO] Permissões (Consumed): a marcação falhou" -ForegroundColor Red; $wbErrors++ }
        $wfIdxConj2 = Get-WinForgeAclBackupSet -Root $wfIdxRaiz
        if ([string]$wfIdxConj2.Stamp -ne '20260202-000000') { Write-Host "  [ERRO] Permissões (Consumed): depois de consumido o primeiro, o conjunto é '$($wfIdxConj2.Stamp)', esperado '20260202-000000'" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfIdxConj2.Pending -ne 1) { Write-Host "  [ERRO] Permissões (Consumed): Pending=$($wfIdxConj2.Pending), esperado 1" -ForegroundColor Red; $wbErrors++ }
        # Índice de OUTRA máquina é recusado: SDDL com SIDs alheios entra como SID cru e tranca o perfil.
        $wfIdxOutra = Test-WinForgeAclIndexOrigin -Index ([pscustomobject]@{ Origin = [pscustomobject]@{ MachineGuid = '00000000-0000-0000-0000-000000000000'; ProfileSid = [string]$wfIdxOrigem.ProfileSid } })
        if ($wfIdxOutra.Ok) { Write-Host "  [ERRO] Permissões (origem): MachineGuid trocado foi aceito" -ForegroundColor Red; $wbErrors++ }
        $wfIdxOutroSid = Test-WinForgeAclIndexOrigin -Index ([pscustomobject]@{ Origin = [pscustomobject]@{ MachineGuid = [string]$wfIdxOrigem.MachineGuid; ProfileSid = 'S-1-5-21-9-9-9-1001' } })
        if ($wfIdxOutroSid.Ok) { Write-Host "  [ERRO] Permissões (origem): SID de perfil trocado foi aceito" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeAclIndexOrigin -Index ([pscustomobject]@{ Origin = $wfIdxOrigem })).Ok) { Write-Host "  [ERRO] Permissões (origem): o índice desta máquina foi recusado" -ForegroundColor Red; $wbErrors++ }
        # Índice da 1.7.0 NÃO tem origem: ele é aceito, com aviso. Recusá-lo mataria o Desfazer
        # justamente do backup que a guarda da segunda restauração manda desfazer - e a pasta
        # protegida já garante que quem escreveu ali estava elevado nesta máquina.
        $wfIdxVelho = Test-WinForgeAclIndexOrigin -Index ([pscustomobject]@{ Stamp = '20250101-000000' })
        if (-not $wfIdxVelho.Ok) { Write-Host "  [ERRO] Permissões (origem): um índice SEM o campo de origem (1.7.0) foi recusado - o Desfazer que a própria recusa manda usar deixaria de funcionar" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]::IsNullOrWhiteSpace([string]$wfIdxVelho.Reason)) { Write-Host "  [ERRO] Permissões (origem): o índice sem origem foi aceito CALADO - quem confere tem de dizer que não houve o que conferir" -ForegroundColor Red; $wbErrors++ }
        # Restauração NOVA é recusada enquanto houver índice não consumido, e diz o que fazer.
        $wfIdxProva = Test-WinForgeAclRestoreAllowed -Root $wfIdxRaiz
        if ($wfIdxProva.Ok) { Write-Host "  [ERRO] Permissões (segunda execução): com 1 índice não consumido a restauração foi permitida - é o defeito que destrói o backup bom" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfIdxProva.Reason -notmatch 'Limpar backups antigos') { Write-Host "  [ERRO] Permissões (segunda execução): a recusa não manda usar Desfazer ou 'Limpar backups antigos' ('$($wfIdxProva.Reason)')" -ForegroundColor Red; $wbErrors++ }
        $null = Set-WinForgeAclIndexConsumed -Path (Join-Path $wfIdxRaiz 'acl-index-20260202-000000.json')
        if (-not (Test-WinForgeAclRestoreAllowed -Root $wfIdxRaiz).Ok) { Write-Host "  [ERRO] Permissões (segunda execução): com todos consumidos a restauração continua recusada" -ForegroundColor Red; $wbErrors++ }
        # E a restauração CHAMA a guarda: exercer Test-WinForgeAclRestoreAllowed solto prova que ela
        # sabe responder, não que alguém pergunta. Implementá-la e nunca invocá-la deixaria o defeito
        # que destrói o backup bom inteiro, com o teste verde.
        $wfIdxFonteR = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if ($wfIdxFonteR -notmatch 'Test-WinForgeAclRestoreAllowed') { Write-Host "  [ERRO] Permissões (segunda execução): Invoke-WinForgeAclRestore não chama Test-WinForgeAclRestoreAllowed - a guarda existe e ninguém pergunta a ela" -ForegroundColor Red; $wbErrors++ }
        $wfIdxPosGuarda = $wfIdxFonteR.IndexOf('Test-WinForgeAclRestoreAllowed', [StringComparison]::Ordinal)
        $wfIdxPosEscopo = $wfIdxFonteR.IndexOf('Get-WinForgeAclContentScope', [StringComparison]::Ordinal)
        if ($wfIdxPosGuarda -lt 0 -or $wfIdxPosEscopo -lt 0 -or $wfIdxPosGuarda -gt $wfIdxPosEscopo) { Write-Host "  [ERRO] Permissões (segunda execução): a guarda é conferida DEPOIS da caminhada - a recusa tem de vir antes de qualquer trabalho" -ForegroundColor Red; $wbErrors++ }
        # As duas linhas acima pescam o NOME, e o nome também aparece em comentário e no bloco de
        # ajuda - que entram no ScriptBlock. Um mutante que apagasse a CHAMADA e deixasse o
        # comentário sobreviveria às duas. Aqui a cobrança é pela chamada, com o parâmetro junto, e
        # é ela que fixa também a POSIÇÃO.
        $wfIdxPosChamada = $wfIdxFonteR.IndexOf('Test-WinForgeAclRestoreAllowed -Root', [StringComparison]::Ordinal)
        if ($wfIdxPosChamada -lt 0) { Write-Host "  [ERRO] Permissões (segunda execução): Invoke-WinForgeAclRestore CITA Test-WinForgeAclRestoreAllowed e não a chama" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfIdxPosEscopo -ge 0 -and $wfIdxPosChamada -gt $wfIdxPosEscopo) { Write-Host "  [ERRO] Permissões (segunda execução): a guarda é CHAMADA depois da caminhada - a recusa tem de vir antes de qualquer trabalho" -ForegroundColor Red; $wbErrors++ }
        # E o índice que a fase 2 grava nasce com os dois campos novos: sem 'Consumed' a fila não
        # anda, e sem 'Origin' o Desfazer perde a única prova de que o índice é desta máquina.
        if ($wfIdxFonteR -notmatch 'Consumed\s*=\s*\$false') { Write-Host "  [ERRO] Permissões (índices): o índice gravado na fase 2 não nasce com Consumed = `$false" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteR.IndexOf('Origin = (New-WinForgeAclIndexOrigin)', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (índices): o índice gravado na fase 2 não anota a máquina de origem" -ForegroundColor Red; $wbErrors++ }
        # Toda recusa do Desfazer termina com a frase de §1.7.
        $wfIdxFonteU = [string](Get-Command Invoke-WinForgeAclUndo).ScriptBlock
        if ($wfIdxFonteU -notmatch 'coloque-a de volta em') { Write-Host "  [ERRO] Permissões (Desfazer): falta a frase 'Nada foi alterado. Se tiver uma cópia do arquivo original…'" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -notmatch 'Set-WinForgeAclIndexConsumed') { Write-Host "  [ERRO] Permissões (Desfazer): um Desfazer bem-sucedido não marca o índice como consumido" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -notmatch 'Test-WinForgeAclIndexOrigin') { Write-Host "  [ERRO] Permissões (Desfazer): a origem do índice não é conferida" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -notmatch 'Get-WinForgeAclContentHash') { Write-Host "  [ERRO] Permissões (Desfazer): o SHA-256 do arquivo de conteúdo não é recalculado" -ForegroundColor Red; $wbErrors++ }
        # As três travas acima pescam o NOME, e os três nomes também aparecem no bloco de ajuda da
        # função, que entra no ScriptBlock: um mutante que trocasse a CHAMADA por um valor fixo
        # sobreviveria a elas. Aqui a cobrança é pela chamada, com o parâmetro junto.
        foreach ($wfIdxChamada in @(
            @('Test-WinForgeAclIndexOrigin -Index', 'a origem do índice é CITADA, mas não conferida'),
            @('Get-WinForgeAclContentHash -Path', 'o SHA-256 do arquivo de conteúdo é CITADO, mas não recalculado'),
            @('Set-WinForgeAclIndexConsumed -Path', 'a marca de consumido é CITADA, mas não gravada - o conjunto ficaria na fila para sempre')
        )) {
            if ($wfIdxFonteU.IndexOf([string]$wfIdxChamada[0], [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (Desfazer): $($wfIdxChamada[1])" -ForegroundColor Red; $wbErrors++ }
        }
        # Ancorado no INDEXADOR, e não em 'Count - 1': essa string casa com qualquer comentário que
        # explique o defeito antigo, e o teste ficaria vermelho justamente na implementação correta.
        if ($wfIdxFonteU -match '\$indices\[\s*\$indices\.Count\s*-\s*1\s*\]') { Write-Host "  [ERRO] Permissões (Desfazer): ainda existe a escolha pelo índice mais novo (`$indices[`$indices.Count-1])" -ForegroundColor Red; $wbErrors++ }
        # AVISO INOFENSIVO NÃO É RECUSA. Os dois casos de "a pasta não existe mais" são pulos, não
        # falhas: a pasta sumiu entre o backup e o Desfazer, não há o que devolver nela, e o resto do
        # conjunto voltou inteiro. Contá-los como recusa prendia o conjunto na fila para sempre - a
        # restauração seguia recusada e o Desfazer repetia a mesma pasta sumida, sem saída.
        if (([regex]::Matches($wfIdxFonteU, '\$pulados\+\+')).Count -ne 2) { Write-Host "  [ERRO] Permissões (Desfazer): os dois casos de 'a pasta não existe mais' têm de contar como PULADOS, não como recusa ($(([regex]::Matches($wfIdxFonteU, '\$pulados\+\+')).Count) de 2)" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -notmatch 'pulada\(s\)') { Write-Host "  [ERRO] Permissões (Desfazer): o resumo não diz quantas pastas foram puladas" -ForegroundColor Red; $wbErrors++ }
        # E a porta que marca o conjunto como consumido continua sendo recusa + amostra, e não pulo.
        if ($wfIdxFonteU -notmatch '\$recusados -eq 0 -and \$amostraFora -eq 0') { Write-Host "  [ERRO] Permissões (Desfazer): a porta da marca de consumido deixou de ser 'nenhuma recusa e nenhuma divergência de amostra'" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -match '\$pulados -eq 0') { Write-Host "  [ERRO] Permissões (Desfazer): a porta da marca de consumido voltou a prender o conjunto por causa de pasta que sumiu" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (índices): Desfazer no mais antigo não consumido, Consumed avança a fila, origem por MachineGuid+SID, restauração recusada com pendente, pasta sumida é pulo e não recusa"
    } catch {
        Write-Host "  [ERRO] Permissões (índices): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfIdxRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- Permissões: limpar backups antigos
    # A saída de quem matou a 1.7.0 na fase 2 e ficou com centenas de GB numa pasta que só SYSTEM e
    # Administradores apagam. É também a outra metade da guarda da segunda restauração: numa máquina
    # que já rodou a 1.7.0 o índice antigo não tem a marca de consumido, conta como pendente e
    # recusa toda restauração nova - a recusa manda usar este botão, e sem ele não havia saída.
    $wfLimpRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-limpeza'
    try {
        if (Test-Path -LiteralPath $wfLimpRaiz) { Remove-Item -LiteralPath $wfLimpRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfLimpRaiz -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-perfil-fulano-20260101-000000.txt') -Value 'usado' -Encoding Unicode
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-perfil-fulano-19990101-000000.txt') -Value 'orfao' -Encoding Unicode
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-index-20260101-000000.json') -Value (([pscustomobject]@{
            Stamp = '20260101-000000'; Consumed = $false; Origin = (New-WinForgeAclIndexOrigin)
            Items = @([pscustomobject]@{ Path = 'C:\Users\fulano'; Sddl = ''; Owner = ''; OwnerSid = ''; File = 'acl-perfil-fulano-20260101-000000.txt'; Target = 'C:\Users'; Sha256 = ''; ExternalPath = '' })
        } | ConvertTo-Json -Depth 5)) -Encoding UTF8
        $wfLimpInv = @(Get-WinForgeAclBackupInventory -Root $wfLimpRaiz)
        if ($wfLimpInv.Count -ne 3) { Write-Host "  [ERRO] Permissões (limpeza): o inventário trouxe $($wfLimpInv.Count) item(ns), esperado 3" -ForegroundColor Red; $wbErrors++ }
        $wfLimpOrf = @($wfLimpInv | Where-Object { $_.Orphan })
        if ($wfLimpOrf.Count -ne 1) { Write-Host "  [ERRO] Permissões (limpeza): $($wfLimpOrf.Count) órfão(s), esperado 1" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfLimpOrf[0].Name -ne 'acl-perfil-fulano-19990101-000000.txt') { Write-Host "  [ERRO] Permissões (limpeza): o órfão apontado é '$($wfLimpOrf[0].Name)'" -ForegroundColor Red; $wbErrors++ }
        if (@($wfLimpInv | Where-Object { [string]$_.Name -eq 'acl-perfil-fulano-20260101-000000.txt' -and $_.Orphan }).Count) { Write-Host "  [ERRO] Permissões (limpeza): arquivo referenciado por índice foi marcado como órfão" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLimpI in $wfLimpInv) {
            if ([long]$wfLimpI.Bytes -le 0) { Write-Host "  [ERRO] Permissões (limpeza): '$($wfLimpI.Name)' sem tamanho" -ForegroundColor Red; $wbErrors++ }
            if ($null -eq $wfLimpI.Date) { Write-Host "  [ERRO] Permissões (limpeza): '$($wfLimpI.Name)' sem data" -ForegroundColor Red; $wbErrors++ }
        }
        # O tipo separa o índice do conteúdo: é ele que decide o que pode ser apagado junto de quê.
        $wfLimpTipos = @($wfLimpInv | Group-Object { [string]$_.Kind } | ForEach-Object { "$($_.Name)=$($_.Count)" } | Sort-Object)
        if (($wfLimpTipos -join ',') -ne 'conteudo=2,indice=1') { Write-Host "  [ERRO] Permissões (limpeza): os tipos do inventário saíram '$($wfLimpTipos -join ',')', esperado 'conteudo=2,indice=1'" -ForegroundColor Red; $wbErrors++ }
        # A linha nova existe e é 'repair'. O título é conferido AQUI, com o índice ainda pendente:
        # a recusa da segunda restauração cita o botão pelo nome, e quem lê a recusa vai procurar
        # esse nome na aba Config - um travessão de um lado com hífen do outro manda a pessoa
        # procurar um botão que ela não encontra.
        $wfLimpCmd = Get-WinForgeRepairCommand -Name 'AclCleanup'
        if ([string]$wfLimpCmd.Kind -ne 'repair') { Write-Host "  [ERRO] Permissões (limpeza): a linha AclCleanup é '$($wfLimpCmd.Kind)', esperado 'repair'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfLimpCmd.Title -ne 'Permissões do disco C: - Limpar backups antigos') { Write-Host "  [ERRO] Permissões (limpeza): título '$($wfLimpCmd.Title)'" -ForegroundColor Red; $wbErrors++ }
        $wfLimpRecusa = Test-WinForgeAclRestoreAllowed -Root $wfLimpRaiz
        if ($wfLimpRecusa.Ok) { Write-Host "  [ERRO] Permissões (limpeza): com um índice pendente a restauração deveria ser recusada - é a recusa que manda usar este botão" -ForegroundColor Red; $wbErrors++ }
        elseif (([string]$wfLimpRecusa.Reason).IndexOf([string]$wfLimpCmd.Title, [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (limpeza): a recusa da restauração não cita o botão com o título EXATO da tabela ('$($wfLimpCmd.Title)')" -ForegroundColor Red; $wbErrors++ }
        if ([string]$sync.configs.feature.WPFWFRepAclCleanup.Content -ne [string]$wfLimpCmd.Title) { Write-Host "  [ERRO] Permissões (limpeza): o Content da config ('$($sync.configs.feature.WPFWFRepAclCleanup.Content)') não é o título da tabela" -ForegroundColor Red; $wbErrors++ }
        $wfLimpSeco = @(Invoke-WinForgeAclCleanup -DryRun -BackupRoot $wfLimpRaiz)
        if (-not @($wfLimpSeco | Where-Object { [string]$_ -like '*[simulação]*' }).Count) { Write-Host "  [ERRO] Permissões (limpeza): -DryRun não devolveu linhas prefixadas com '[simulação] '" -ForegroundColor Red; $wbErrors++ }
        if (@($wfLimpSeco | Where-Object { [string]$_ -like '*20260101*' }).Count) { Write-Host "  [ERRO] Permissões (limpeza): a simulação apagaria um arquivo em uso" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-Path -LiteralPath (Join-Path $wfLimpRaiz 'acl-perfil-fulano-19990101-000000.txt'))) { Write-Host "  [ERRO] Permissões (limpeza): o -DryRun APAGOU arquivo" -ForegroundColor Red; $wbErrors++ }
        # Marcado o índice como desfeito, o conjunto INTEIRO passa a poder sair - o índice e o
        # arquivo que ele referencia. É a saída de quem já desfez e continua com a pasta cheia.
        $null = Set-WinForgeAclIndexConsumed -Path (Join-Path $wfLimpRaiz 'acl-index-20260101-000000.json')
        $wfLimpSeco2 = @(Invoke-WinForgeAclCleanup -DryRun -BackupRoot $wfLimpRaiz)
        if ($wfLimpSeco2.Count -ne 3) { Write-Host "  [ERRO] Permissões (limpeza): com o índice consumido a simulação apagaria $($wfLimpSeco2.Count) arquivo(s), esperado 3" -ForegroundColor Red; $wbErrors++ }
        if (-not @($wfLimpSeco2 | Where-Object { [string]$_ -like '*acl-index-20260101-000000.json*' }).Count) { Write-Host "  [ERRO] Permissões (limpeza): o índice já desfeito não entrou na simulação" -ForegroundColor Red; $wbErrors++ }
        # Varredura de abertura: acima de 1 GB ela RELATA, e não apaga nada.
        $wfLimpAviso = Get-WinForgeAclBackupSizeWarning -Root $wfLimpRaiz -LimitBytes 1
        if (-not $wfLimpAviso.Over) { Write-Host "  [ERRO] Permissões (varredura): 1 byte de limite deveria disparar o aviso" -ForegroundColor Red; $wbErrors++ }
        if ([long]$wfLimpAviso.Bytes -le 0) { Write-Host "  [ERRO] Permissões (varredura): o aviso não soma os bytes da pasta ($($wfLimpAviso.Bytes))" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfLimpAviso.Text -notmatch 'Limpar backups antigos') { Write-Host "  [ERRO] Permissões (varredura): o aviso não aponta o botão ('$($wfLimpAviso.Text)')" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeAclBackupSizeWarning -Root $wfLimpRaiz -LimitBytes 1073741824).Over) { Write-Host "  [ERRO] Permissões (varredura): três arquivos minúsculos dispararam o aviso de 1 GB" -ForegroundColor Red; $wbErrors++ }
        $wfLimpFonteV = [string](Get-Command Get-WinForgeAclBackupSizeWarning).ScriptBlock
        if ($wfLimpFonteV -match 'Remove-Item') { Write-Host "  [ERRO] Permissões (varredura): a varredura de abertura SÓ RELATA - não pode apagar nada" -ForegroundColor Red; $wbErrors++ }
        # Índice ILEGÍVEL cega o inventário: não dá para saber o que ele referenciava, e chutar
        # "órfão" aqui apagaria o backup que ele cobre. Nada é marcado, e a limpeza não acha alvo.
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-index-19990101-000000.json') -Value 'isto não é json' -Encoding UTF8
        $wfLimpCego = @(Get-WinForgeAclBackupInventory -Root $wfLimpRaiz | Where-Object { $_.Orphan })
        if ($wfLimpCego.Count) { Write-Host "  [ERRO] Permissões (limpeza): com um índice ilegível na pasta, $($wfLimpCego.Count) arquivo(s) foram marcados como órfãos - não há como saber o que ele referenciava" -ForegroundColor Red; $wbErrors++ }
        $wfLimpSecoCego = @(Invoke-WinForgeAclCleanup -DryRun -BackupRoot $wfLimpRaiz | Where-Object { [string]$_ -like '*acl-perfil-fulano-19990101*' })
        if ($wfLimpSecoCego.Count) { Write-Host "  [ERRO] Permissões (limpeza): a simulação apagaria um arquivo que um índice ilegível pode referenciar" -ForegroundColor Red; $wbErrors++ }
        # Mas o ÍNDICE ilegível em si é alvo SEMPRE, e essa era a outra ponta do beco sem saída: o
        # Desfazer não consegue aplicá-lo (Get-WinForgeAclBackupSet devolve zero item para ele), a
        # restauração fica recusada porque ele conta como pendente, e a limpeza respondia que não
        # havia nada para apagar. Decidir isso NÃO depende de interpretar o conteúdo dele.
        $wfLimpInvCego = @(Get-WinForgeAclBackupInventory -Root $wfLimpRaiz | Where-Object { [string]$_.Name -eq 'acl-index-19990101-000000.json' })
        if ($wfLimpInvCego.Count -ne 1) { Write-Host "  [ERRO] Permissões (limpeza): o índice ilegível não apareceu no inventário" -ForegroundColor Red; $wbErrors++ }
        elseif (-not $wfLimpInvCego[0].Unreadable) { Write-Host "  [ERRO] Permissões (limpeza): o índice ilegível não foi marcado com Unreadable" -ForegroundColor Red; $wbErrors++ }
        $wfLimpSecoIleg = @(Invoke-WinForgeAclCleanup -DryRun -BackupRoot $wfLimpRaiz | Where-Object { [string]$_ -like '*acl-index-19990101-000000.json*' })
        if (-not $wfLimpSecoIleg.Count) { Write-Host "  [ERRO] Permissões (limpeza): o índice ILEGÍVEL não entra na limpeza - a recusa da restauração manda limpar e a limpeza não acha nada, que é o beco sem saída" -ForegroundColor Red; $wbErrors++ }
        Remove-Item -LiteralPath (Join-Path $wfLimpRaiz 'acl-index-19990101-000000.json') -Force -ErrorAction SilentlyContinue
        # ---- O beco sem saída medido pelo revisor: um índice PENDENTE no formato da 1.7.0, sem as
        # marcas novas. A restauração é recusada por causa dele, e antes deste conserto a limpeza
        # respondia "nada a apagar". Basta uma pasta que sumiu, um hash divergente ou um índice
        # ilegível para o conjunto ficar pendente para sempre.
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-index-20250101-000000.json') -Value (([pscustomobject]@{
            Stamp = '20250101-000000'
            Items = @([pscustomobject]@{ Path = 'C:\Users\fulano'; Sddl = 'D:P(A;;FA;;;SY)'; Owner = ''; OwnerSid = ''; File = ''; Target = ''; Sha256 = ''; ExternalPath = '' })
        } | ConvertTo-Json -Depth 5)) -Encoding UTF8
        $wfLimpBeco = Test-WinForgeAclRestoreAllowed -Root $wfLimpRaiz
        if ($wfLimpBeco.Ok) { Write-Host "  [ERRO] Permissões (limpeza): com um índice da 1.7.0 na pasta a restauração deveria ser recusada" -ForegroundColor Red; $wbErrors++ }
        elseif (([string]$wfLimpBeco.Reason).IndexOf('inclusive os pendentes', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (limpeza): a recusa manda limpar sem dizer que a limpeza alcança conjunto pendente - foi essa a saída que não existia ('$($wfLimpBeco.Reason)')" -ForegroundColor Red; $wbErrors++ }
        $wfLimpSemDesc = @(Invoke-WinForgeAclCleanup -DryRun -BackupRoot $wfLimpRaiz | Where-Object { [string]$_ -like '*20250101*' })
        if ($wfLimpSemDesc.Count) { Write-Host "  [ERRO] Permissões (limpeza): sem o descarte pedido, a limpeza apagaria um conjunto que ninguém desfez" -ForegroundColor Red; $wbErrors++ }
        $wfLimpComDesc = @(Invoke-WinForgeAclCleanup -DryRun -DiscardPending -BackupRoot $wfLimpRaiz | Where-Object { [string]$_ -like '*20250101*' })
        if (-not $wfLimpComDesc.Count) { Write-Host "  [ERRO] Permissões (limpeza): com o descarte pedido o conjunto pendente continua fora - o beco sem saída volta inteiro" -ForegroundColor Red; $wbErrors++ }
        # A confirmação do descarte é DIGITADA, e distinta da caixa Sim/Não do clique.
        foreach ($wfLimpFrase in @(
            @{ Texto = 'APAGAR';      Vale = $true },
            @{ Texto = 'apagar';      Vale = $true },
            @{ Texto = '  APAGAR  ';  Vale = $true },
            @{ Texto = 'APAGA';       Vale = $false },
            @{ Texto = 'APAGAR TUDO'; Vale = $false },
            @{ Texto = '';            Vale = $false },
            @{ Texto = 'sim';         Vale = $false }
        )) {
            if ([bool](Test-WinForgeAclCleanupPhrase -Typed ([string]$wfLimpFrase.Texto)) -ne [bool]$wfLimpFrase.Vale) { Write-Host "  [ERRO] Permissões (descarte): '$($wfLimpFrase.Texto)' deveria $(if ($wfLimpFrase.Vale) { 'valer' } else { 'NÃO valer' }) como confirmação digitada" -ForegroundColor Red; $wbErrors++ }
        }
        $wfLimpJanela = Show-WinForgeAclCleanupConfirm -Stamps @('20250101-000000') -Bytes 1234 -NoShow
        if ($wfLimpJanela -isnot [System.Windows.Window]) { Write-Host "  [ERRO] Permissões (descarte): Show-WinForgeAclCleanupConfirm -NoShow não devolveu uma janela" -ForegroundColor Red; $wbErrors++ }
        else {
            $wfLimpOk = $wfLimpJanela.FindName('WFAclCleanupOk')
            $wfLimpCaixa = $wfLimpJanela.FindName('WFAclCleanupPhrase')
            $wfLimpTexto = $wfLimpJanela.FindName('WFAclCleanupText')
            if ($null -eq $wfLimpOk -or $null -eq $wfLimpCaixa -or $null -eq $wfLimpTexto) { Write-Host "  [ERRO] Permissões (descarte): a caixa de confirmação não registrou o botão, a caixa de texto ou a mensagem" -ForegroundColor Red; $wbErrors++ }
            else {
                if ($wfLimpOk.IsEnabled) { Write-Host "  [ERRO] Permissões (descarte): o botão de descartar nasce HABILITADO - a confirmação digitada não segura nada" -ForegroundColor Red; $wbErrors++ }
                $wfLimpCaixa.Text = 'APAGAR'
                if (-not $wfLimpOk.IsEnabled) { Write-Host "  [ERRO] Permissões (descarte): digitada a palavra, o botão continua desabilitado" -ForegroundColor Red; $wbErrors++ }
                $wfLimpCaixa.Text = 'APAG'
                if ($wfLimpOk.IsEnabled) { Write-Host "  [ERRO] Permissões (descarte): apagada a palavra, o botão continua habilitado" -ForegroundColor Red; $wbErrors++ }
                if (([string]$wfLimpTexto.Text).IndexOf('20250101-000000', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (descarte): a caixa não diz QUAIS conjuntos vão embora ('$($wfLimpTexto.Text)')" -ForegroundColor Red; $wbErrors++ }
            }
        }
        # E a limpeza de verdade PEDE essa confirmação antes de descartar pendente. A busca é pela
        # forma da CHAMADA, e não pelo nome: o nome também aparece no bloco de ajuda, que entra no
        # ScriptBlock - foi essa fresta que já pegou três implementadores desta leva.
        $wfLimpFonteC = [string](Get-Command Invoke-WinForgeAclCleanup).ScriptBlock
        if ($wfLimpFonteC.IndexOf('Request-WinForgeAclCleanupDiscard -Stamps', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (descarte): a limpeza não CHAMA a confirmação digitada antes de descartar conjunto pendente" -ForegroundColor Red; $wbErrors++ }
        # O salto para a thread da janela precisa do callback nascido na runspace PRINCIPAL. Sem ele
        # no lugar, o pedido morre no Dispatcher e o descarte nunca acontece - calado.
        if ($sync.WinForgeAclCleanupConfirmCallback -isnot [scriptblock]) { Write-Host "  [ERRO] Permissões (descarte): `$sync.WinForgeAclCleanupConfirmCallback não é um scriptblock - o pedido não chega à thread da janela" -ForegroundColor Red; $wbErrors++ }
        Remove-Item -LiteralPath (Join-Path $wfLimpRaiz 'acl-index-20250101-000000.json') -Force -ErrorAction SilentlyContinue
        # E a linha recusa despacho sem ninguém para confirmar.
        $wfLimpDesp = Invoke-WinForgeRepairCommand -Name 'AclCleanup' -NoUI
        if ($wfLimpDesp.Dispatched) { Write-Host "  [ERRO] Permissões (limpeza): a linha foi despachada no SelfTest" -ForegroundColor Red; $wbErrors++ }
        if ([string]::IsNullOrWhiteSpace([string]$sync.configs.feature.WPFWFRepAclCleanup.Description)) { Write-Host "  [ERRO] Permissões (limpeza): WPFWFRepAclCleanup sem Description na config" -ForegroundColor Red; $wbErrors++ }
        # A varredura de abertura está PENDURADA no gancho da janela. Exercitá-la solta prova que ela
        # sabe responder, não que alguém pergunta - e ninguém perguntando é a pasta crescendo calada.
        $wfLimpFonteG = ''
        try { if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) { $wfLimpFonteG = [IO.File]::ReadAllText($PSCommandPath) } } catch { $wfLimpFonteG = '' }
        # A agulha é MONTADA, e não escrita inteira: esta linha mora no mesmo arquivo que ela
        # procura, e um literal contíguo casaria consigo mesmo - um mutante que apagasse o gancho
        # sobreviveria com o teste verde. Medido: com a busca escrita inteira, ele sobreviveu.
        $wfLimpAlvoG = '::Background, [action]{ Show-WinForgeAcl' + 'BackupSizeWarning }'
        if ([string]::IsNullOrWhiteSpace($wfLimpFonteG)) { Write-Host "  [ERRO] Permissões (varredura): o próprio arquivo do WinForge não pôde ser lido para conferir o gancho de abertura" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfLimpFonteG.IndexOf($wfLimpAlvoG, [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (varredura): o gancho de abertura não chama Show-WinForgeAclBackupSizeWarning em DispatcherPriority::Background - a pasta cresceria calada" -ForegroundColor Red; $wbErrors++ }
        $wfLimpFonteS = [string](Get-Command Show-WinForgeAclBackupSizeWarning).ScriptBlock
        if ($wfLimpFonteS -match 'MessageBox') { Write-Host "  [ERRO] Permissões (varredura): a varredura de abertura abre caixa de mensagem - ela escreve no log e na barra, e nada mais" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLimpEsp in @('Write-WinForgeLog', 'Set-WinForgeProfileProgress')) {
            if ($wfLimpFonteS.IndexOf($wfLimpEsp, [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (varredura): a varredura de abertura não usa '$wfLimpEsp'" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Permissões (limpeza): inventário com tamanho e data, 1 órfão marcado, simulação não apaga, varredura de 1 GB só relata"
    } catch {
        Write-Host "  [ERRO] Permissões (limpeza): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfLimpRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- Permissões: conferência por amostragem
    # A dívida que o '/C' deixou no '/restore' do Desfazer: com ele o icacls sai 0 quase sempre, então
    # o '$aplicados++' de lá diz "o icacls rodou", e não "as entradas foram aplicadas". O sinal volta
    # por COMPORTAMENTO - reler a lista de algumas pastas e comparar com o descritor do arquivo -, e
    # nunca pela frase de resumo do icacls: a integração contínua deste projeto roda em inglês e uma
    # asserção presa ao idioma já quebrou antes.
    $wfAmRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-amostra'
    try {
        if (Test-Path -LiteralPath $wfAmRaiz) { Remove-Item -LiteralPath $wfAmRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfAmRaiz -Force | Out-Null
        $wfAmPai = [string](Split-Path -Parent $wfAmRaiz)
        $wfAmArq = Join-Path $wfAmRaiz 'amostra.txt'
        # O backup só guarda pasta com a herança BLOQUEADA, então o fixture bloqueia a herança das
        # quatro - é a mesma condição que a caminhada da fase 2 exige para indexar.
        $wfAmNomes = @('alfa', 'beta', 'gama', 'delta')
        foreach ($wfAmN in $wfAmNomes) {
            $wfAmP = Join-Path $wfAmRaiz $wfAmN
            New-Item -ItemType Directory -Path $wfAmP -Force | Out-Null
            $wfAmAcl = Get-Acl -LiteralPath $wfAmP
            $wfAmAcl.SetAccessRuleProtection($true, $true)
            Set-Acl -LiteralPath $wfAmP -AclObject $wfAmAcl
        }
        # Os pares saem da CAMINHADA de verdade, e não de uma segunda forma de ler a ACL: o que se
        # confere depois é exatamente o texto que a fase 2 teria gravado.
        $wfAmEsc = Get-WinForgeAclContentScope -Path $wfAmRaiz
        if (-not $wfAmEsc.Ok) { throw "a caminhada do fixture falhou: $($wfAmEsc.Reason)" }
        $wfAmEntradas = @($wfAmEsc.Entries)
        if ($wfAmEntradas.Count -ne 4) { Write-Host "  [ERRO] Permissões (amostragem): o fixture deu $($wfAmEntradas.Count) entrada(s), esperado 4" -ForegroundColor Red; $wbErrors++ }
        # Formato medido do 'icacls /save': pares <nome>CRLF<SDDL>CRLF em UTF-16LE SEM marca. Escrito
        # aqui à mão porque Write-WinForgeAclContentBackup se recusa a rodar sob -SelfTest, e é
        # justamente essa recusa que não se quer afrouxar.
        $wfAmGrava = {
            param($Destino, $Pares)
            $wfAmEnc = New-Object System.Text.UnicodeEncoding($false, $false)
            $wfAmW = New-Object System.IO.StreamWriter($Destino, $false, $wfAmEnc)
            try { foreach ($wfAmPar in $Pares) { $wfAmW.Write([string]$wfAmPar.Name); $wfAmW.Write("`r`n"); $wfAmW.Write([string]$wfAmPar.Sddl); $wfAmW.Write("`r`n") } } finally { $wfAmW.Dispose() }
        }
        & $wfAmGrava $wfAmArq $wfAmEntradas
        $wfAmTudo = Test-WinForgeAclRestoreSample -Root $wfAmPai -File $wfAmArq -Size 4
        if (-not $wfAmTudo.Ok) { Write-Host "  [ERRO] Permissões (amostragem): a conferência não rodou ($($wfAmTudo.Reason))" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfAmTudo.Checked -ne 4) { Write-Host "  [ERRO] Permissões (amostragem): conferiu $($wfAmTudo.Checked) pasta(s), esperado 4" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfAmTudo.Match -ne 4) { Write-Host "  [ERRO] Permissões (amostragem): $($wfAmTudo.Match) de 4 bateram com o backup logo depois de gravá-lo - a comparação está acusando o que não mudou" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfAmTudo.Differ -ne 0 -or [int]$wfAmTudo.Missing -ne 0) { Write-Host "  [ERRO] Permissões (amostragem): Differ=$($wfAmTudo.Differ) e Missing=$($wfAmTudo.Missing) num fixture intacto" -ForegroundColor Red; $wbErrors++ }
        # A prova de COMPORTAMENTO: uma pasta cuja lista mudou depois do backup tem de sair como
        # divergente. É este caso que o código de saída do icacls com '/C' não denuncia.
        #
        # A mexida vai por Restore-WinForgeAclSddl, e não por 'Get-Acl | Set-Acl': MEDIDO aqui, o
        # par Get-Acl/Set-Acl sobre uma pasta com a herança JÁ bloqueada tenta escrever a SACL junto
        # e morre com PrivilegeNotHeldException ('SeSecurityPrivilege'), deixando a pasta intacta -
        # o teste passaria a não mexer em nada e acusaria a comparação no lugar do fixture.
        $wfAmAlvo = Join-Path $wfAmRaiz 'beta'
        $wfAmSddlBeta = [string](@($wfAmEntradas | Where-Object { ([string]$_.Name) -like '*beta' })[0].Sddl)
        $wfAmMex = Restore-WinForgeAclSddl -Path $wfAmAlvo -Sddl ($wfAmSddlBeta + '(A;OICI;FA;;;WD)')
        if (-not $wfAmMex.DaclOk) { throw "a ACE plantada em 'beta' não foi aplicada: $($wfAmMex.Reason)" }
        if ([string](Get-WinForgeAclFolderSecurity -Path $wfAmAlvo).Sddl -eq $wfAmSddlBeta) { Write-Host "  [ERRO] Permissões (amostragem): a ACE plantada não mudou o descritor de 'beta' - o teste não está provando nada" -ForegroundColor Red; $wbErrors++ }
        $wfAmMexida = Test-WinForgeAclRestoreSample -Root $wfAmPai -File $wfAmArq -Size 4
        if ([int]$wfAmMexida.Differ -ne 1) { Write-Host "  [ERRO] Permissões (amostragem): uma pasta com a lista alterada deu Differ=$($wfAmMexida.Differ), esperado 1" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfAmMexida.Match -ne 3) { Write-Host "  [ERRO] Permissões (amostragem): Match=$($wfAmMexida.Match) com uma pasta alterada, esperado 3" -ForegroundColor Red; $wbErrors++ }
        if (@($wfAmMexida.Paths) -notcontains $wfAmAlvo) { Write-Host "  [ERRO] Permissões (amostragem): a divergente não foi nomeada ('$(@($wfAmMexida.Paths) -join '; ')')" -ForegroundColor Red; $wbErrors++ }
        # Pasta que sumiu desde o backup não é divergência: é o caso comum de pasta de cache.
        Remove-Item -LiteralPath (Join-Path $wfAmRaiz 'delta') -Recurse -Force
        $wfAmSumida = Test-WinForgeAclRestoreSample -Root $wfAmPai -File $wfAmArq -Size 4
        if ([int]$wfAmSumida.Missing -ne 1) { Write-Host "  [ERRO] Permissões (amostragem): a pasta apagada deu Missing=$($wfAmSumida.Missing), esperado 1" -ForegroundColor Red; $wbErrors++ }
        # A amostra ATRAVESSA o arquivo. Um '/restore' que morre no meio deixa o começo certo e o fim
        # intocado; uma amostra presa nas primeiras N entradas diria "tudo certo" exatamente aí. Aqui
        # só a ÚLTIMA das 20 entradas existe de verdade: quem não chega ao fim devolve Match=0.
        $wfAmLongo = Join-Path $wfAmRaiz 'amostra-longa.txt'
        $wfAmPares = @()
        for ($wfAmI = 1; $wfAmI -le 19; $wfAmI++) { $wfAmPares += @{ Name = ('acl-amostra\fantasma-{0:D2}' -f $wfAmI); Sddl = 'D:P(A;;FA;;;SY)' } }
        $wfAmPares += @($wfAmEntradas | Where-Object { ([string]$_.Name) -like '*alfa' })[0]
        & $wfAmGrava $wfAmLongo $wfAmPares
        $wfAmEspalhada = Test-WinForgeAclRestoreSample -Root $wfAmPai -File $wfAmLongo -Size 4
        if ([int]$wfAmEspalhada.Checked -ne 4) { Write-Host "  [ERRO] Permissões (amostragem): conferiu $($wfAmEspalhada.Checked) de 20 com -Size 4" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfAmEspalhada.Match -ne 1) { Write-Host "  [ERRO] Permissões (amostragem): a amostra não alcançou a ÚLTIMA entrada do arquivo (Match=$($wfAmEspalhada.Match), esperado 1) - presa no começo ela aprova um '/restore' que morreu no meio" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfAmEspalhada.Total -ne 20) { Write-Host "  [ERRO] Permissões (amostragem): Total=$($wfAmEspalhada.Total), esperado 20" -ForegroundColor Red; $wbErrors++ }
        # O tamanho padrão é 20, e é ele que roda no Desfazer de verdade.
        $wfAmPadrao = Test-WinForgeAclRestoreSample -Root $wfAmPai -File $wfAmLongo
        if ([int]$wfAmPadrao.Checked -ne 20) { Write-Host "  [ERRO] Permissões (amostragem): sem -Size conferiu $($wfAmPadrao.Checked) de 20, esperado 20" -ForegroundColor Red; $wbErrors++ }
        # Arquivo que não existe é recusa com motivo, e não uma conferência silenciosamente vazia.
        $wfAmSemArq = Test-WinForgeAclRestoreSample -Root $wfAmPai -File (Join-Path $wfAmRaiz 'nao-existe.txt')
        if ($wfAmSemArq.Ok) { Write-Host "  [ERRO] Permissões (amostragem): um arquivo inexistente passou por conferência boa" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]::IsNullOrWhiteSpace([string]$wfAmSemArq.Reason)) { Write-Host "  [ERRO] Permissões (amostragem): recusou o arquivo inexistente sem dizer por quê" -ForegroundColor Red; $wbErrors++ }
        # As duas normalizações da comparação, cobradas direto: 'P' (herança bloqueada) é semântica e
        # tem de separar; 'AI' aparece sozinha na primeira gravação de uma pasta nova e não pode
        # separar; e a ORDEM das ACEs não pode separar, porque o descritor guardado pode ter vindo do
        # icacls (pastas com negação) e a releitura vem do .NET, em ordem canônica.
        if (Test-WinForgeAclSddlSame -A 'D:P(A;;FA;;;SY)' -B 'D:(A;;FA;;;SY)') { Write-Host "  [ERRO] Permissões (amostragem): pasta com herança bloqueada e pasta sem foram dadas como iguais" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeAclSddlSame -A 'D:PAI(A;;FA;;;SY)' -B 'D:P(A;;FA;;;SY)')) { Write-Host "  [ERRO] Permissões (amostragem): a flag 'AI' separou dois descritores com a MESMA lista - ela aparece sozinha na primeira gravação de uma pasta nova" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeAclSddlSame -A 'D:P(A;;FA;;;SY)(A;;FA;;;BA)' -B 'D:P(A;;FA;;;BA)(A;;FA;;;SY)')) { Write-Host "  [ERRO] Permissões (amostragem): a ORDEM das ACEs separou duas listas iguais - o texto guardado pode vir do icacls e a releitura vem do .NET" -ForegroundColor Red; $wbErrors++ }
        if (Test-WinForgeAclSddlSame -A 'D:P(A;;FA;;;SY)' -B 'D:P(A;;FA;;;SY)(A;;FA;;;WD)') { Write-Host "  [ERRO] Permissões (amostragem): uma ACE a mais não separou os descritores" -ForegroundColor Red; $wbErrors++ }
        # O sinal é comportamento, não texto: nada de processo nem de frase do icacls. A integração
        # contínua roda em inglês e 'Processados com sucesso N arquivos' não aparece lá.
        $wfAmFonte = [string](Get-Command Test-WinForgeAclRestoreSample).ScriptBlock
        if ($wfAmFonte -match 'Invoke-WinForgeNativeCommand') { Write-Host "  [ERRO] Permissões (amostragem): a conferência roda um processo - ela tem de reler a ACL pelo .NET" -ForegroundColor Red; $wbErrors++ }
        if ($wfAmFonte -match '(?i)processad|processed|com sucesso|successfully') { Write-Host "  [ERRO] Permissões (amostragem): a conferência parseia a frase de resumo do icacls, que muda com o idioma do sistema" -ForegroundColor Red; $wbErrors++ }
        # E o Desfazer CHAMA a conferência, depois do '/restore' e não antes.
        $wfAmFonteU = [string](Get-Command Invoke-WinForgeAclUndo).ScriptBlock
        if ($wfAmFonteU.IndexOf('Test-WinForgeAclRestoreSample -Root', [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (amostragem): o Desfazer não chama a conferência por amostragem - a dívida do '/C' continua sem pagar" -ForegroundColor Red; $wbErrors++ }
        $wfAmPosRestore = $wfAmFonteU.IndexOf("'/restore'", [StringComparison]::Ordinal)
        $wfAmPosAmostra = $wfAmFonteU.IndexOf('Test-WinForgeAclRestoreSample -Root', [StringComparison]::Ordinal)
        if ($wfAmPosRestore -lt 0 -or $wfAmPosAmostra -lt 0 -or $wfAmPosAmostra -lt $wfAmPosRestore) { Write-Host "  [ERRO] Permissões (amostragem): a conferência vem ANTES do '/restore' - ali ela mediria o disco que ninguém restaurou ainda" -ForegroundColor Red; $wbErrors++ }
        if ($wfAmFonteU -notmatch 'amostragem') { Write-Host "  [ERRO] Permissões (amostragem): o resumo do Desfazer não diz ao usuário que a conferência é por amostra" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (amostragem): 4 de 4 conferem no fixture intacto, 1 divergente nomeada, 1 sumida separada, amostra espalhada alcança a última de 20, padrão 20"
    } catch {
        Write-Host "  [ERRO] Permissões (amostragem): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfAmRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- Permissões: destino do conteúdo
    # O backup de conteúdo é OBRIGATÓRIO (103,4 KB: não há o que economizar). O que é opcional é o
    # DESTINO. As sete recusas abaixo existem porque o que sai desta pasta volta por um /restore
    # elevado sobre o perfil inteiro.
    $wfDestRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-destino'
    try {
        if (Test-Path -LiteralPath $wfDestRaiz) { Remove-Item -LiteralPath $wfDestRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        $wfDestPerfil = Join-Path $wfDestRaiz 'perfil'
        $wfDestBom = Join-Path $wfDestRaiz 'destino'
        New-Item -ItemType Directory -Path $wfDestPerfil -Force | Out-Null
        New-Item -ItemType Directory -Path $wfDestBom -Force | Out-Null
        foreach ($wfDestCaso in @(
            @{ Nome = 'relativo';    Path = 'pasta\destino';                        Match = 'absoluto' },
            @{ Nome = 'UNC';         Path = '\\servidor\compartilhada\acl';         Match = 'rede' },
            @{ Nome = 'raiz';        Path = ([System.IO.Path]::GetPathRoot($wfDestRaiz)); Match = 'raiz' },
            @{ Nome = 'no perfil';   Path = (Join-Path $wfDestPerfil 'dentro');     Match = 'perfil' },
            @{ Nome = 'sobre o perfil'; Path = $wfDestRaiz;                          Match = 'perfil' })) {
            $wfDestR = Test-WinForgeAclContentRoot -Path ([string]$wfDestCaso.Path) -ProfilePath $wfDestPerfil
            if ($wfDestR.Ok) { Write-Host "  [ERRO] Permissões (destino): '$($wfDestCaso.Nome)' foi aceito ('$($wfDestCaso.Path)')" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfDestR.Reason -notmatch [string]$wfDestCaso.Match) { Write-Host "  [ERRO] Permissões (destino): a recusa de '$($wfDestCaso.Nome)' não diz o motivo ('$($wfDestR.Reason)')" -ForegroundColor Red; $wbErrors++ }
        }
        # A recusa de 'no perfil' acima é lida sobre uma pasta que NÃO EXISTE, e sozinha ela não
        # prova nada: o caminho do fixture tem a palavra 'perfil' dentro dele, então QUALQUER recusa
        # que cite o caminho casa com o padrão. Medido por mutação: com a conferência de "dentro do
        # perfil" desligada, o teste continuava passando pela recusa de "a pasta não existe". A
        # pasta abaixo EXISTE - sem a conferência ela seria ACEITA, e é isso que fecha o buraco.
        $wfDestDentro = Join-Path $wfDestPerfil 'dentro'
        New-Item -ItemType Directory -Path $wfDestDentro -Force | Out-Null
        $wfDestRD = Test-WinForgeAclContentRoot -Path $wfDestDentro -ProfilePath $wfDestPerfil
        if ($wfDestRD.Ok) { Write-Host "  [ERRO] Permissões (destino): uma pasta que EXISTE dentro do perfil foi aceita" -ForegroundColor Red; $wbErrors++ }
        # Ponto de reanálise na cadeia: o caminho aponta para outro lugar sem parecer que aponta.
        $wfDestLink = Join-Path $wfDestRaiz 'atalho'
        cmd.exe /c mklink /J "$wfDestLink" "$wfDestBom" | Out-Null
        if (Test-Path -LiteralPath $wfDestLink) {
            $wfDestRL = Test-WinForgeAclContentRoot -Path $wfDestLink -ProfilePath $wfDestPerfil
            if ($wfDestRL.Ok) { Write-Host "  [ERRO] Permissões (destino): pasta com ponto de reanálise na cadeia foi aceita" -ForegroundColor Red; $wbErrors++ }
        }
        # Sistema de arquivos e tipo de unidade são conferidos: exFAT/FAT32 não guardam DACL e não
        # dão erro - o arquivo sairia mudo e o Desfazer aplicaria lixo.
        $wfDestFonte = [string](Get-Command Test-WinForgeAclContentRoot).ScriptBlock
        foreach ($wfDestExig in @('DriveFormat', 'NTFS', 'DriveType', 'Fixed', 'Removable')) {
            if ($wfDestFonte -notmatch [regex]::Escape($wfDestExig)) { Write-Host "  [ERRO] Permissões (destino): a conferência não olha '$wfDestExig'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfDestFonte -match '\$env:') { Write-Host "  [ERRO] Permissões (destino): o caminho não pode vir de variável de ambiente" -ForegroundColor Red; $wbErrors++ }
        # Pasta boa passa e traz o aviso literal de §1.4.
        $wfDestOk = Test-WinForgeAclContentRoot -Path $wfDestBom -ProfilePath $wfDestPerfil
        if (-not $wfDestOk.Ok) { Write-Host "  [ERRO] Permissões (destino): a pasta de teste foi recusada ('$($wfDestOk.Reason)')" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfDestFrase in @('qualquer conta de administrador', 'recusa restaurar, mas não recupera arquivo apagado', 'disco desligado na hora de desfazer')) {
            if ([string]$wfDestOk.Warning -notmatch [regex]::Escape($wfDestFrase)) { Write-Host "  [ERRO] Permissões (destino): o aviso não traz '$wfDestFrase'" -ForegroundColor Red; $wbErrors++ }
        }
        # O arquivo de conteúdo, dentro ou fora do %ProgramData%, passa por Protect-WinForgeSnapshotFile.
        $wfDestFonteR = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if (@([regex]::Matches($wfDestFonteR, 'Protect-WinForgeSnapshotFile')).Count -lt 2) { Write-Host "  [ERRO] Permissões (destino): o arquivo de conteúdo externo não passa por Protect-WinForgeSnapshotFile" -ForegroundColor Red; $wbErrors++ }
        if ($wfDestFonteR -notmatch 'WinForgeAclExternalRoot') { Write-Host "  [ERRO] Permissões (destino): a runspace não lê o destino escolhido na thread da janela" -ForegroundColor Red; $wbErrors++ }
        # A caixa nasce DESMARCADA e o diálogo é criado na thread da janela.
        $wfDestFonteD = [string](Get-Command Show-WinForgeAclBackupDestination).ScriptBlock
        if ($wfDestFonteD -notmatch 'IsChecked\s*=\s*\$false') { Write-Host "  [ERRO] Permissões (destino): a caixa 'em outro disco' não nasce desmarcada" -ForegroundColor Red; $wbErrors++ }
        if ($wfDestFonteD -notmatch 'FolderBrowserDialog') { Write-Host "  [ERRO] Permissões (destino): o caminho não vem do seletor de pasta" -ForegroundColor Red; $wbErrors++ }
        # Desfazer: caminho externo ausente diz QUAL disco ligar, e a recusa termina com a frase de §1.7.
        $wfDestFonteU = [string](Get-Command Invoke-WinForgeAclUndo).ScriptBlock
        if ($wfDestFonteU -notmatch 'ExternalPath') { Write-Host "  [ERRO] Permissões (Desfazer): o item de conteúdo não considera ExternalPath" -ForegroundColor Red; $wbErrors++ }
        if ($wfDestFonteU -notmatch 'ligue o disco') { Write-Host "  [ERRO] Permissões (Desfazer): com o arquivo externo ausente, o texto não diz qual disco ligar" -ForegroundColor Red; $wbErrors++ }
        # Travas de FORMA DE CHAMADA, e não de nome solto, pelo mesmo motivo de
        # 'Test-WinForgeAclRestoreAllowed -Root' mais acima: o bloco de ajuda destas mesmas funções
        # explica o campo e cita o nome dele, então procurar pelo nome aceitaria a PROSA no lugar do
        # código. Não é hipótese - medido por mutação, trocar o FolderBrowserDialog por um seletor de
        # ARQUIVO passava batido, porque o nome continuava na descrição da função.
        #
        # As três últimas cobrem as recusas 3, 4 e 7, que são as que o -SelfTest não consegue
        # exercitar de verdade: esta máquina é NTFS e Fixed, e encher um volume para provar a
        # conferência de espaço seria um teste pior do que a falta dele.
        foreach ($wfDestChamada in @(
            @($wfDestFonteR, '[string]$sync.WinForgeAclExternalRoot', 'a restauração CITA o destino escolhido e não o LÊ'),
            @($wfDestFonteR, 'ExternalPath = [string]$externoArquivo', 'a restauração não anota o caminho externo no índice'),
            @($wfDestFonteU, '([string]$item.ExternalPath).Trim()', 'o Desfazer CITA o caminho externo e não o LÊ do item'),
            @($wfDestFonteD, 'New-Object System.Windows.Forms.FolderBrowserDialog', 'a caixa CITA o seletor de pasta e não o CRIA'),
            @($wfDestFonte, '$formato -ne ''NTFS''', 'a conferência não compara o sistema de arquivos com NTFS'),
            @($wfDestFonte, '$tipo -ne ''Fixed'' -and $tipo -ne ''Removable''', 'a conferência não separa disco interno e removível dos outros tipos'),
            @($wfDestFonte, 'Test-WinForgeAclFreeSpace -Path $completo -Bytes', 'a conferência do destino não pergunta pelo espaço livre')
        )) {
            if ([string]$wfDestChamada[0] -notmatch [regex]::Escape([string]$wfDestChamada[1])) { Write-Host "  [ERRO] Permissões (destino): $($wfDestChamada[2]) - '$($wfDestChamada[1])' não aparece no código" -ForegroundColor Red; $wbErrors++ }
        }
        # As travas acima leem FONTE, e fonte é prova fraca: um comentário que cite o nome do
        # campo as satisfaz. A parte da cadeia que dá para provar por COMPORTAMENTO sem elevação é
        # esta - o caminho externo atravessando o JSON do índice e chegando ao vetor do '/restore'.
        # É exatamente o trecho que some em silêncio se alguém trocar o campo por ''.
        $wfDestIdx = Join-Path $wfDestRaiz 'indice'
        New-Item -ItemType Directory -Path $wfDestIdx -Force | Out-Null
        $wfDestArqExt = Join-Path $wfDestBom 'acl-perfil-teste-20260912-120000.txt'
        Set-Content -LiteralPath $wfDestArqExt -Value '' -Encoding Unicode
        $wfDestDados = [pscustomobject]@{
            Stamp = '20260912-120000'
            Items = @(
                [pscustomobject]@{ Path = 'C:\Users\Teste'; Sddl = ''; Owner = ''; OwnerSid = ''; File = 'acl-perfil-teste-20260912-120000.txt'; Target = 'C:\Users'; Sha256 = 'ABC'; ExternalPath = $wfDestArqExt }
            )
        }
        Set-Content -LiteralPath (Join-Path $wfDestIdx 'acl-index-20260912-120000.json') -Value ($wfDestDados | ConvertTo-Json -Depth 4) -Encoding UTF8
        $wfDestConj = Get-WinForgeAclBackupSet -Root $wfDestIdx
        if (@($wfDestConj.Items).Count -ne 1) { Write-Host "  [ERRO] Permissões (destino): o índice com caminho externo deu $(@($wfDestConj.Items).Count) item(ns), esperado 1" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]@($wfDestConj.Items)[0].ExternalPath -ne $wfDestArqExt) { Write-Host "  [ERRO] Permissões (destino): o caminho externo não sobreviveu ao JSON do índice ('$([string]@($wfDestConj.Items)[0].ExternalPath)')" -ForegroundColor Red; $wbErrors++ }
        $wfDestSeco = @(Invoke-WinForgeAclUndo -DryRun -BackupRoot $wfDestIdx)
        if ($wfDestSeco.Count -ne 1) { Write-Host "  [ERRO] Permissões (destino): a simulação do Desfazer deu $($wfDestSeco.Count) linha(s), esperado 1" -ForegroundColor Red; $wbErrors++ }
        elseif (([string]$wfDestSeco[0]).IndexOf($wfDestArqExt, [StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Permissões (destino): o '/restore' da simulação não aponta para o arquivo de fora ('$($wfDestSeco[0])')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (destino): sete recusas de Test-WinForgeAclContentRoot, aviso literal, caixa desmarcada por padrão, proteção do arquivo externo e caminho externo do índice até o vetor do '/restore'"
    } catch {
        Write-Host "  [ERRO] Permissões (destino): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        try { cmd.exe /c rmdir "$wfDestRaiz\atalho" 2>$null | Out-Null } catch { }
        Remove-Item -LiteralPath $wfDestRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- Windows Update: uma linha por dispositivo
    # O Windows Update oferece a MESMA placa duas vezes quando o fabricante publica uma revisão: os
    # dois títulos trazem o mesmo DriverModel e versões diferentes. Mostrar as duas convida o usuário
    # a instalar a antiga. A versão sai do título porque a API não tem campo para ela - e o título
    # moderno traz o número entre parênteses, forma que o casamento antigo (número no FIM do título)
    # não reconhecia: era daí que vinha a coluna "Versão" inteira em "n/d".
    try {
        $wfWuVerCasos = @(
            @('Intel Corporation Display Driver Update (32.0.101.7088)', '32.0.101.7088'),
            @('Intel Driver Update (2546.9.2.0)', '2546.9.2.0'),
            @('Intel - Display - 32.0.101.7088', '32.0.101.7088'),
            @('Realtek Semiconductor Corp. - MEDIA - 6.0.9622.1', '6.0.9622.1'),
            @('Atualização de driver sem número', $null),
            @('', $null)
        )
        foreach ($wfWuVerCaso in $wfWuVerCasos) {
            $wfWuVerVeio = Get-WinForgeWindowsUpdateDriverVersion -Title ([string]$wfWuVerCaso[0])
            if ([string]$wfWuVerVeio -ne [string]$wfWuVerCaso[1]) { Write-Host "  [ERRO] versão pelo título: '$($wfWuVerCaso[0])' deu '$wfWuVerVeio', esperado '$($wfWuVerCaso[1])'" -ForegroundColor Red; $wbErrors++ }
        }
        # A busca real tem de usar ESTE parser, e não uma cópia do casamento antigo: ela é a única
        # parte do caminho que o SelfTest não exercita (fala com o serviço do Windows Update).
        if ([string]${function:Search-WinForgeWindowsUpdateDrivers} -notmatch 'Get-WinForgeWindowsUpdateDriverVersion') { Write-Host "  [ERRO] versão pelo título: Search-WinForgeWindowsUpdateDrivers não usa Get-WinForgeWindowsUpdateDriverVersion" -ForegroundColor Red; $wbErrors++ }
        # Cinco ofertas, quatro dispositivos: as duas primeiras são a mesma placa. Modelo e fornecedor
        # vêm com caixa diferente de propósito - o Windows Update não é consistente nisso.
        $wfWuLinhas = @(
            [pscustomobject]@{ Title = 'Intel Corporation Display Driver Update (32.0.101.7085)'; Driver = 'Intel(R) Iris(R) Xe Graphics'; Provider = 'Intel Corporation'; Version = '32.0.101.7085'; Date = '2026-08-01'; UpdateId = 'u-7085' },
            [pscustomobject]@{ Title = 'Intel Corporation Display Driver Update (32.0.101.7088)'; Driver = 'intel(r) iris(r) xe graphics'; Provider = 'INTEL CORPORATION'; Version = '32.0.101.7088'; Date = '2026-09-01'; UpdateId = 'u-7088' },
            [pscustomobject]@{ Title = 'Intel Corporation Display Driver Update (31.0.101.2111)'; Driver = 'Intel(R) UHD Graphics'; Provider = 'Intel Corporation'; Version = '31.0.101.2111'; Date = '2026-07-01'; UpdateId = 'u-uhd' },
            [pscustomobject]@{ Title = 'Realtek Semiconductor Corp. - MEDIA - 6.0.9622.1'; Driver = 'Realtek High Definition Audio'; Provider = 'Realtek'; Version = '6.0.9622.1'; Date = '2026-06-01'; UpdateId = 'u-realtek' },
            [pscustomobject]@{ Title = 'Atualização de driver sem modelo'; Driver = ''; Provider = 'Microsoft'; Version = $null; Date = '2026-05-01'; UpdateId = 'u-sem-modelo' }
        )
        $wfWuSel = Select-WinForgeWindowsUpdateLatest -Rows $wfWuLinhas
        $wfWuMantidos = @($wfWuSel.Kept)
        $wfWuOcultos = @($wfWuSel.Superseded)
        if ($wfWuMantidos.Count -ne 4) { Write-Host "  [ERRO] uma linha por dispositivo: ficaram $($wfWuMantidos.Count) linha(s), esperado 4" -ForegroundColor Red; $wbErrors++ }
        if (@($wfWuMantidos | Where-Object { [string]$_.UpdateId -eq 'u-7088' }).Count -ne 1) { Write-Host "  [ERRO] uma linha por dispositivo: a oferta mais nova (u-7088) não ficou" -ForegroundColor Red; $wbErrors++ }
        if (@($wfWuMantidos | Where-Object { [string]$_.UpdateId -eq 'u-7085' }).Count -ne 0) { Write-Host "  [ERRO] uma linha por dispositivo: a oferta antiga (u-7085) continua na lista" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfWuId in @('u-uhd', 'u-realtek', 'u-sem-modelo')) {
            if (@($wfWuMantidos | Where-Object { [string]$_.UpdateId -eq $wfWuId }).Count -ne 1) { Write-Host "  [ERRO] uma linha por dispositivo: '$wfWuId' é outro dispositivo e sumiu da lista" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfWuOcultos.Count -ne 1) { Write-Host "  [ERRO] uma linha por dispositivo: $($wfWuOcultos.Count) oferta(s) ocultada(s), esperado 1" -ForegroundColor Red; $wbErrors++ }
        else {
            if ([string]$wfWuOcultos[0].UpdateId -ne 'u-7085') { Write-Host "  [ERRO] uma linha por dispositivo: a ocultada é '$($wfWuOcultos[0].UpdateId)', esperado 'u-7085'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfWuOcultos[0].ReplacedBy -ne 'u-7088') { Write-Host "  [ERRO] uma linha por dispositivo: ReplacedBy veio '$($wfWuOcultos[0].ReplacedBy)', esperado 'u-7088'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfWuOcultos[0].Title -notlike '*32.0.101.7085*') { Write-Host "  [ERRO] uma linha por dispositivo: a ocultada não leva o título [$($wfWuOcultos[0].Title)]" -ForegroundColor Red; $wbErrors++ }
        }
        # Sem versão em lugar nenhum, quem decide é a data: DriverVerDate a API sempre traz.
        $wfWuData = Select-WinForgeWindowsUpdateLatest -Rows @(
            [pscustomobject]@{ Title = 'Driver sem número - antigo'; Driver = 'Placa X'; Provider = 'Fabricante'; Version = $null; Date = '2026-01-01'; UpdateId = 'd-velho' },
            [pscustomobject]@{ Title = 'Driver sem número - novo'; Driver = 'Placa X'; Provider = 'Fabricante'; Version = $null; Date = '2026-05-05'; UpdateId = 'd-novo' }
        )
        if (@($wfWuData.Kept).Count -ne 1 -or [string]@($wfWuData.Kept)[0].UpdateId -ne 'd-novo') { Write-Host "  [ERRO] uma linha por dispositivo (sem versão): ficou [$(@($wfWuData.Kept | ForEach-Object { $_.UpdateId }) -join ', ')], esperado só 'd-novo'" -ForegroundColor Red; $wbErrors++ }
        if (@($wfWuData.Superseded).Count -ne 1 -or [string]@($wfWuData.Superseded)[0].ReplacedBy -ne 'd-novo') { Write-Host "  [ERRO] uma linha por dispositivo (sem versão): a ocultada não aponta para 'd-novo'" -ForegroundColor Red; $wbErrors++ }
        # DriverModel vazio não identifica dispositivo nenhum: juntar duas linhas assim esconderia a
        # oferta de outra placa. Cada uma fica sozinha.
        $wfWuVazio = Select-WinForgeWindowsUpdateLatest -Rows @(
            [pscustomobject]@{ Title = 'Sem modelo A (1.0.0.0)'; Driver = ''; Provider = 'Microsoft'; Version = '1.0.0.0'; Date = '2026-01-01'; UpdateId = 'v-a' },
            [pscustomobject]@{ Title = 'Sem modelo B (2.0.0.0)'; Driver = ''; Provider = 'Microsoft'; Version = '2.0.0.0'; Date = '2026-02-01'; UpdateId = 'v-b' }
        )
        if (@($wfWuVazio.Kept).Count -ne 2) { Write-Host "  [ERRO] uma linha por dispositivo (sem modelo): $(@($wfWuVazio.Kept).Count) linha(s), esperado 2 - modelo vazio não pode agrupar" -ForegroundColor Red; $wbErrors++ }
        if (@($wfWuVazio.Superseded).Count -ne 0) { Write-Host "  [ERRO] uma linha por dispositivo (sem modelo): $(@($wfWuVazio.Superseded).Count) oculta(s), esperado 0" -ForegroundColor Red; $wbErrors++ }
        # Driver base e INF de extensão do MESMO dispositivo: o serviço manda os dois com o mesmo
        # DriverModel e o mesmo DriverProvider, e só a classe os separa. São dois pacotes que se
        # completam - agrupar pelos dois primeiros campos escondia metade da oferta.
        $wfWuClasse = Select-WinForgeWindowsUpdateLatest -Rows @(
            [pscustomobject]@{ Title = 'Realtek - MEDIA - 6.0.9622.1'; Driver = 'Realtek High Definition Audio'; Provider = 'Realtek'; Class = 'MEDIA'; Version = '6.0.9622.1'; Date = '2026-06-01'; UpdateId = 'c-media' },
            [pscustomobject]@{ Title = 'Realtek - Extension - 1.0.0.5'; Driver = 'Realtek High Definition Audio'; Provider = 'Realtek'; Class = 'Extension'; Version = '1.0.0.5'; Date = '2026-06-02'; UpdateId = 'c-ext' }
        )
        if (@($wfWuClasse.Kept).Count -ne 2) { Write-Host "  [ERRO] uma linha por dispositivo (classe): ficou [$(@($wfWuClasse.Kept | ForEach-Object { $_.UpdateId }) -join ', ')], esperado as duas - base e extensão são pacotes diferentes" -ForegroundColor Red; $wbErrors++ }
        if (@($wfWuClasse.Superseded).Count -ne 0) { Write-Host "  [ERRO] uma linha por dispositivo (classe): $(@($wfWuClasse.Superseded).Count) oculta(s), esperado 0" -ForegroundColor Red; $wbErrors++ }
        # Mesma classe (com caixa diferente, que o serviço não respeita) volta a ser o mesmo pacote.
        $wfWuClasseIgual = Select-WinForgeWindowsUpdateLatest -Rows @(
            [pscustomobject]@{ Title = 'Realtek - MEDIA - 6.0.9622.1'; Driver = 'Realtek High Definition Audio'; Provider = 'Realtek'; Class = 'MEDIA'; Version = '6.0.9622.1'; Date = '2026-06-01'; UpdateId = 'ci-velho' },
            [pscustomobject]@{ Title = 'Realtek - MEDIA - 6.0.9700.1'; Driver = 'Realtek High Definition Audio'; Provider = 'Realtek'; Class = 'media'; Version = '6.0.9700.1'; Date = '2026-07-01'; UpdateId = 'ci-novo' }
        )
        if (@($wfWuClasseIgual.Kept).Count -ne 1 -or [string]@($wfWuClasseIgual.Kept)[0].UpdateId -ne 'ci-novo') { Write-Host "  [ERRO] uma linha por dispositivo (mesma classe): ficou [$(@($wfWuClasseIgual.Kept | ForEach-Object { $_.UpdateId }) -join ', ')], esperado só 'ci-novo'" -ForegroundColor Red; $wbErrors++ }
        if (@($wfWuClasseIgual.Superseded).Count -ne 1) { Write-Host "  [ERRO] uma linha por dispositivo (mesma classe): $(@($wfWuClasseIgual.Superseded).Count) oculta(s), esperado 1" -ForegroundColor Red; $wbErrors++ }
        # A busca real tem de TRAZER a classe: sem o campo na linha, o agrupamento acima nunca vê
        # a diferença entre o driver base e a extensão, e o teste de cima passaria por engano.
        if ([string]${function:Search-WinForgeWindowsUpdateDrivers} -notmatch 'DriverClass') { Write-Host "  [ERRO] uma linha por dispositivo (classe): Search-WinForgeWindowsUpdateDrivers não captura DriverClass" -ForegroundColor Red; $wbErrors++ }
        if ([string]${function:Select-WinForgeWindowsUpdateLatest} -notmatch '\$linha\.Class') { Write-Host "  [ERRO] uma linha por dispositivo (classe): a chave de agrupamento não usa a classe" -ForegroundColor Red; $wbErrors++ }
        # Lista vazia é lista vazia, e não um item nulo.
        $wfWuNada = Select-WinForgeWindowsUpdateLatest -Rows @()
        if (@($wfWuNada.Kept).Count -ne 0 -or @($wfWuNada.Superseded).Count -ne 0) { Write-Host "  [ERRO] uma linha por dispositivo: lista vazia devolveu $(@($wfWuNada.Kept).Count)/$(@($wfWuNada.Superseded).Count)" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Windows Update (uma linha por dispositivo): $($wfWuVerCasos.Count) título(s) lidos | 5 ofertas -> $($wfWuMantidos.Count) dispositivo(s) e $($wfWuOcultos.Count) versão(ões) antiga(s) fora da tabela"
    } catch {
        Write-Host "  [ERRO] Windows Update (uma linha por dispositivo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }    # ---------------------------------------------------------------- ações por linha de driver
    # A coluna "Ação" da tabela de drivers e o botão "Instalar" da tabela do Windows Update. Nada
    # aqui baixa nem instala nada: o SelfTest exercita a DECISÃO (que ação cada linha oferece) e as
    # três travas do caminho que escreve - domínio da URL, assinatura do arquivo e modo SelfTest.
    try {
        # Que ação cada linha oferece. A linha da NVIDIA atrasada COM link oficial é a única que
        # ganha o botão de download; com o link fora do domínio da NVIDIA ela cai na página do
        # fabricante, que é o comportamento seguro.
        $wfAcCasos = @(
            @('NVIDIA atrasada com link oficial',      @{ Device = 'NVIDIA GeForce RTX 3070'; Vendor = 'nvidia'; Class = 'DISPLAY'; Status = 'atualizar'; Latest = '616.92'; LatestUrl = 'https://us.download.nvidia.com/Windows/616.92/616.92-desktop-win10-win11-64bit-international-dch-whql.exe'; Url = 'https://www.nvidia.com/pt-br/drivers/' }, 'nvidia-download', 'Baixar 616.92'),
            @('NVIDIA em dia',                         @{ Device = 'NVIDIA GeForce RTX 3070'; Vendor = 'nvidia'; Class = 'DISPLAY'; Status = 'ok'; Url = 'https://www.nvidia.com/pt-br/drivers/' }, 'vendor-page', 'Página do fabricante'),
            @('NVIDIA atrasada com link fora do domínio', @{ Device = 'NVIDIA GeForce RTX 3070'; Vendor = 'nvidia'; Class = 'DISPLAY'; Status = 'atualizar'; Latest = '616.92'; LatestUrl = 'https://nvidia.com.evil.com/616.92.exe'; Url = 'https://www.nvidia.com/pt-br/drivers/' }, 'vendor-page', 'Página do fabricante'),
            @('AMD com página do fabricante',          @{ Device = 'AMD Radeon'; Vendor = 'amd'; Class = 'DISPLAY'; Status = 'verificar'; Url = 'https://www.amd.com/pt/support/download/drivers.html' }, 'vendor-page', 'Página do fabricante'),
            @('sem link nenhum',                       @{ Device = 'Dispositivo genérico'; Vendor = 'outro'; Class = 'SYSTEM'; Status = 'ok' }, 'none', '')
        )
        $wfAcOk = 0
        foreach ($wfAcCaso in $wfAcCasos) {
            $wfAcVeio = Get-WinForgeDriverAction -Driver ([pscustomobject]$wfAcCaso[1])
            if ([string]$wfAcVeio.Kind -ne [string]$wfAcCaso[2]) { Write-Host "  [ERRO] Ação de driver ($($wfAcCaso[0])): veio '$($wfAcVeio.Kind)', esperado '$($wfAcCaso[2])'" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfAcVeio.Label -ne [string]$wfAcCaso[3]) { Write-Host "  [ERRO] Ação de driver ($($wfAcCaso[0])): rótulo '$($wfAcVeio.Label)', esperado '$($wfAcCaso[3])'" -ForegroundColor Red; $wbErrors++ }
            else { $wfAcOk++ }
        }
        # As linhas da tabela têm de CARREGAR a decisão: é delas que o botão do XAML tira o texto e
        # a visibilidade, e é a própria linha que viaja na Tag do botão até o handler.
        # O ',' de Get-WinForgeDiagDriverRows protege a coleção do desmembramento: '@(...)' em volta
        # da chamada daria UM item (a própria coleção). O pipe é o que a enumera.
        $wfAcLinhas = @((Get-WinForgeDiagDriverRows -Profile @{ Drivers = @($wfAcCasos | ForEach-Object { [pscustomobject]$_[1] }) }) | ForEach-Object { $_ })
        if ($wfAcLinhas.Count -ne $wfAcCasos.Count) { Write-Host "  [ERRO] Ação de driver: $($wfAcLinhas.Count) linha(s), esperado $($wfAcCasos.Count)" -ForegroundColor Red; $wbErrors++ }
        else {
            for ($wfAcI = 0; $wfAcI -lt $wfAcCasos.Count; $wfAcI++) {
                $wfAcLinha = $wfAcLinhas[$wfAcI]
                if ([string]$wfAcLinha.ActionKind -ne [string]$wfAcCasos[$wfAcI][2]) { Write-Host "  [ERRO] Ação de driver (linha '$($wfAcCasos[$wfAcI][0])'): ActionKind '$($wfAcLinha.ActionKind)', esperado '$($wfAcCasos[$wfAcI][2])'" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wfAcLinha.ActionLabel -ne [string]$wfAcCasos[$wfAcI][3]) { Write-Host "  [ERRO] Ação de driver (linha '$($wfAcCasos[$wfAcI][0])'): ActionLabel '$($wfAcLinha.ActionLabel)'" -ForegroundColor Red; $wbErrors++ }
                $wfAcVisEsperada = $(if ([string]$wfAcCasos[$wfAcI][2] -eq 'none') { 'Collapsed' } else { 'Visible' })
                if ([string]$wfAcLinha.ActionVisible -ne $wfAcVisEsperada) { Write-Host "  [ERRO] Ação de driver (linha '$($wfAcCasos[$wfAcI][0])'): ActionVisible '$($wfAcLinha.ActionVisible)', esperado '$wfAcVisEsperada'" -ForegroundColor Red; $wbErrors++ }
            }
        }
        # Domínio da URL de download. 'https://nvidia.com.evil.com' é o caso que um -like '*nvidia.com*'
        # deixaria passar: o host TERMINA em nvidia.com só na leitura da esquerda para a direita.
        $wfAcUrls = @(
            @('https://us.download.nvidia.com/Windows/616.92/x.exe', $true),
            @('https://international.download.nvidia.com/x.exe', $true),
            @('https://nvidia.com/x.exe', $true),
            @('http://us.download.nvidia.com/x.exe', $false),
            @('http://evil/x.exe', $false),
            @('https://nvidia.com.evil.com/x.exe', $false),
            @('https://www.nvidia.com.br/x.exe', $false),
            @('file:///C:/Windows/System32/calc.exe', $false),
            @('', $false)
        )
        $wfAcUrlOk = 0
        foreach ($wfAcUrl in $wfAcUrls) {
            $wfAcUrlVeio = [bool](Test-WinForgeNvidiaDownloadUrl -Url ([string]$wfAcUrl[0]))
            if ($wfAcUrlVeio -ne [bool]$wfAcUrl[1]) { Write-Host "  [ERRO] URL de download NVIDIA: '$($wfAcUrl[0])' deveria dar $($wfAcUrl[1]), deu $wfAcUrlVeio" -ForegroundColor Red; $wbErrors++ }
            else { $wfAcUrlOk++ }
        }
        # Recusa de redirecionamento: o download roda com -MaximumRedirection 0, mas no PowerShell
        # 5.1 quem diz que foi redirecionamento NÃO é a mensagem (que vem genérica) - é o
        # FullyQualifiedErrorId, que começa com 'MaximumRedirectExceeded'. Procurar 'redirec' na
        # mensagem deixava o usuário com um erro de rede qualquer no lugar da recusa. O mapeamento é
        # provado com ErrorRecord SINTÉTICO: nenhum byte de rede sai daqui.
        # Caso: @(nome, FQID, mensagem, ErrorDetails, esperado dizer 'redirecionar')
        $wfAcRedCasos = @(
            @('FQID (5.1)', 'MaximumRedirectExceeded,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', 'A operação não pôde ser concluída.', $null, $true),
            @('ErrorDetails', 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', 'Erro no servidor remoto.', 'O servidor respondeu com um redirecionamento.', $true),
            @('mensagem', 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', 'The maximum redirection count has been exceeded.', $null, $true),
            @('falha comum', 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', 'O tempo limite da operação foi atingido.', $null, $false)
        )
        $wfAcRedOk = 0
        foreach ($wfAcRedCaso in $wfAcRedCasos) {
            $wfAcRedErro = New-Object System.Management.Automation.ErrorRecord (
                (New-Object System.Net.WebException ([string]$wfAcRedCaso[2])),
                [string]$wfAcRedCaso[1],
                ([System.Management.Automation.ErrorCategory]::InvalidOperation),
                $null)
            if ($null -ne $wfAcRedCaso[3]) { $wfAcRedErro.ErrorDetails = New-Object System.Management.Automation.ErrorDetails ([string]$wfAcRedCaso[3]) }
            $wfAcRedTxt = [string](Get-WinForgeDownloadFailureText -ErrorRecord $wfAcRedErro)
            $wfAcRedViu = [bool]($wfAcRedTxt -like '*o servidor tentou redirecionar o download; recusado*')
            if ($wfAcRedViu -ne [bool]$wfAcRedCaso[4]) { Write-Host "  [ERRO] Recusa de redirecionamento ($($wfAcRedCaso[0])): esperado dizer redirecionamento = $($wfAcRedCaso[4]), veio '$wfAcRedTxt'" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAcRedTxt -notlike "*$($wfAcRedCaso[2])*") { Write-Host "  [ERRO] Recusa de redirecionamento ($($wfAcRedCaso[0])): a causa original sumiu do texto ('$wfAcRedTxt')" -ForegroundColor Red; $wbErrors++ }
            else { $wfAcRedOk++ }
        }
        # E o catch do download usa ESTE mapeamento, e não uma cópia dele.
        $wfAcRedDef = [string]${function:Install-WinForgeNvidiaDriver}
        if ($wfAcRedDef -notmatch 'Get-WinForgeDownloadFailureText -ErrorRecord \$_') { Write-Host "  [ERRO] Recusa de redirecionamento: Install-WinForgeNvidiaDriver não usa Get-WinForgeDownloadFailureText" -ForegroundColor Red; $wbErrors++ }
        # Simulação do download: devolve o caminho de destino dentro da pasta de downloads e NÃO
        # começa nada. Nenhum byte sai da rede e nenhum arquivo nasce no disco.
        $wfAcRaiz = Get-WinForgeDownloadRoot
        # A base esperada sai da API de pastas, e não de $env:ProgramData - se o teste cobrasse a
        # variável, ele passaria justamente no cenário que o conserto existe para impedir.
        if ($wfAcRaiz -ne (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'WinForge\downloads')) { Write-Host "  [ERRO] Get-WinForgeDownloadRoot: veio '$wfAcRaiz'" -ForegroundColor Red; $wbErrors++ }
        $wfAcSeco = Install-WinForgeNvidiaDriver -Url 'https://us.download.nvidia.com/Windows/616.92/616.92-desktop-win10-win11-64bit-international-dch-whql.exe' -Version '616.92' -DryRun
        if (-not ([string]$wfAcSeco.Path).StartsWith($wfAcRaiz, [StringComparison]::OrdinalIgnoreCase)) { Write-Host "  [ERRO] Install-WinForgeNvidiaDriver -DryRun: '$($wfAcSeco.Path)' fora da pasta de downloads '$wfAcRaiz'" -ForegroundColor Red; $wbErrors++ }
        if ($wfAcSeco.Started -ne $false) { Write-Host "  [ERRO] Install-WinForgeNvidiaDriver -DryRun: Started deveria ser `$false" -ForegroundColor Red; $wbErrors++ }
        if ($wfAcSeco.Verified -ne $false) { Write-Host "  [ERRO] Install-WinForgeNvidiaDriver -DryRun: Verified deveria ser `$false" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfAcSeco.Text -notmatch '616\.92') { Write-Host "  [ERRO] Install-WinForgeNvidiaDriver -DryRun: o texto não fala da versão ('$($wfAcSeco.Text)')" -ForegroundColor Red; $wbErrors++ }
        if (Test-Path -LiteralPath ([string]$wfAcSeco.Path)) { Write-Host "  [ERRO] Install-WinForgeNvidiaDriver -DryRun: a simulação criou '$($wfAcSeco.Path)'" -ForegroundColor Red; $wbErrors++ }
        # Limpeza dos instaladores antigos: cada versão são uns 700 MB, e antes nada apagava o
        # anterior. O que se prova aqui é a ESCOLHA - só 'nvidia-*.exe', nunca o recém-aberto,
        # nunca um arquivo que o WinForge não pôs ali - primeiro em simulação e depois apagando de
        # verdade, numa pasta de teste com arquivos criados aqui mesmo.
        $wfLimpDir = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\limpeza'
        New-Item -ItemType Directory -Path $wfLimpDir -Force | Out-Null
        $wfLimpNovo = Join-Path $wfLimpDir 'nvidia-616.92.exe'
        $wfLimpVelho = Join-Path $wfLimpDir 'nvidia-566.36.exe'
        $wfLimpAlheio = Join-Path $wfLimpDir 'outro-programa.exe'
        foreach ($wfLimpArq in @($wfLimpNovo, $wfLimpVelho, $wfLimpAlheio)) { Set-Content -LiteralPath $wfLimpArq -Value 'MZ' -Encoding Ascii }
        $wfLimpSeco = Remove-WinForgeOldNvidiaInstallers -Folder $wfLimpDir -Keep $wfLimpNovo -DryRun
        if (@($wfLimpSeco.Candidates).Count -ne 1 -or [string]@($wfLimpSeco.Candidates)[0] -ne $wfLimpVelho) {
            Write-Host "  [ERRO] limpeza de instaladores: a escolha deveria ser só '$wfLimpVelho', veio '$(@($wfLimpSeco.Candidates) -join ' | ')'" -ForegroundColor Red; $wbErrors++
        }
        if (@($wfLimpSeco.Removed).Count) { Write-Host "  [ERRO] limpeza de instaladores: a simulação apagou $(@($wfLimpSeco.Removed).Count) arquivo(s)" -ForegroundColor Red; $wbErrors++ }
        $wfLimpReal = Remove-WinForgeOldNvidiaInstallers -Folder $wfLimpDir -Keep $wfLimpNovo
        if (@($wfLimpReal.Removed).Count -ne 1 -or [string]@($wfLimpReal.Removed)[0] -ne $wfLimpVelho) {
            Write-Host "  [ERRO] limpeza de instaladores: apagou '$(@($wfLimpReal.Removed) -join ' | ')', esperado só '$wfLimpVelho'" -ForegroundColor Red; $wbErrors++
        }
        if (Test-Path -LiteralPath $wfLimpVelho) { Write-Host "  [ERRO] limpeza de instaladores: o instalador antigo continua no disco" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLimpArq in @($wfLimpNovo, $wfLimpAlheio)) {
            if (-not (Test-Path -LiteralPath $wfLimpArq)) { Write-Host "  [ERRO] limpeza de instaladores: '$wfLimpArq' foi apagado e não devia" -ForegroundColor Red; $wbErrors++ }
        }
        # A cadeia de pastas é reconferida antes de apagar: sem isso, uma junção plantada no lugar
        # de 'downloads' faria desta função um apagador de arquivos escolhidos por outra pessoa.
        $wfLimpDefL = [string]${function:Remove-WinForgeOldNvidiaInstallers}
        if ($wfLimpDefL.IndexOf('Test-WinForgeSnapshotRootPath', [StringComparison]::Ordinal) -lt 0 -or
            $wfLimpDefL.IndexOf('Test-WinForgeSnapshotRootPath', [StringComparison]::Ordinal) -gt $wfLimpDefL.IndexOf('Remove-Item -LiteralPath $velho', [StringComparison]::Ordinal)) {
            Write-Host "  [ERRO] limpeza de instaladores: a cadeia não é conferida antes de apagar" -ForegroundColor Red; $wbErrors++
        }
        # E é o Install que chama a limpeza, DEPOIS do Start-Process e com o pino já solto - apagar
        # exige DELETE, que é justamente o que o pino nega.
        $wfLimpDef = [string]${function:Install-WinForgeNvidiaDriver}
        if ($wfLimpDef -notmatch 'Remove-WinForgeOldNvidiaInstallers -Folder') { Write-Host "  [ERRO] limpeza de instaladores: Install-WinForgeNvidiaDriver não chama Remove-WinForgeOldNvidiaInstallers" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfLimpDef.IndexOf('Start-Process -FilePath $destino', [StringComparison]::Ordinal) -gt $wfLimpDef.IndexOf('Remove-WinForgeOldNvidiaInstallers -Folder', [StringComparison]::Ordinal)) {
            Write-Host "  [ERRO] limpeza de instaladores: a limpeza acontece antes do Start-Process" -ForegroundColor Red; $wbErrors++
        }
        # URL fora do domínio é recusada ANTES do -DryRun: uma simulação com URL de terceiro não é
        # simulação de nada, e o dia em que o -DryRun se perder de novo a recusa já terá acontecido.
        foreach ($wfAcRuim in @('http://evil/x.exe', 'https://nvidia.com.evil.com/x.exe')) {
            $wfAcErroUrl = $null
            try { Install-WinForgeNvidiaDriver -Url $wfAcRuim -Version '616.92' -DryRun | Out-Null } catch { $wfAcErroUrl = [string]$_.Exception.Message }
            if ($null -eq $wfAcErroUrl) { Write-Host "  [ERRO] Install-WinForgeNvidiaDriver: '$wfAcRuim' deveria ser recusada" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAcErroUrl -notmatch 'nvidia\.com') { Write-Host "  [ERRO] Install-WinForgeNvidiaDriver: a recusa de '$wfAcRuim' não fala do domínio ('$wfAcErroUrl')" -ForegroundColor Red; $wbErrors++ }
        }
        # Assinatura: arquivo sem assinatura nenhuma é recusado, e o nome da organização é comparado
        # por igualdade EXATA - 'NVIDIA Corporation Ltd' não é 'NVIDIA Corporation'.
        $wfAcTmpDir = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\assinatura'
        New-Item -ItemType Directory -Path $wfAcTmpDir -Force | Out-Null
        $wfAcTmpExe = Join-Path $wfAcTmpDir 'sem-assinatura.exe'
        Set-Content -LiteralPath $wfAcTmpExe -Value 'MZ este arquivo nao e um executavel assinado' -Encoding Ascii
        if (Test-WinForgeNvidiaSigner -Path $wfAcTmpExe) { Write-Host "  [ERRO] Test-WinForgeNvidiaSigner: arquivo sem assinatura foi aceito" -ForegroundColor Red; $wbErrors++ }
        if (Test-WinForgeNvidiaSigner -Path (Join-Path $wfAcTmpDir 'nao-existe.exe')) { Write-Host "  [ERRO] Test-WinForgeNvidiaSigner: arquivo inexistente foi aceito" -ForegroundColor Red; $wbErrors++ }
        $wfAcRdnCasos = @(
            @('CN=NVIDIA Corporation, OU=Digital ID, O=NVIDIA Corporation Ltd, L=Santa Clara, S=California, C=US', 'NVIDIA Corporation Ltd', $false),
            @('CN=NVIDIA Corporation, O=NVIDIA Corporation, L=Santa Clara, S=California, C=US', 'NVIDIA Corporation', $true),
            @('CN=Fulano, O="NVIDIA Corporation, Inc.", C=US', 'NVIDIA Corporation, Inc.', $false)
        )
        $wfAcRdnOk = 0
        foreach ($wfAcRdnCaso in $wfAcRdnCasos) {
            $wfAcRdn = Split-WinForgeCertificateSubject -Subject ([string]$wfAcRdnCaso[0])
            $wfAcOrgs = @($wfAcRdn['O'])
            if ($wfAcOrgs.Count -ne 1) { Write-Host "  [ERRO] Split-WinForgeCertificateSubject: '$($wfAcRdnCaso[0])' deu $($wfAcOrgs.Count) valor(es) de O" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfAcOrgs[0] -ne [string]$wfAcRdnCaso[1]) { Write-Host "  [ERRO] Split-WinForgeCertificateSubject: O veio '$($wfAcOrgs[0])', esperado '$($wfAcRdnCaso[1])'" -ForegroundColor Red; $wbErrors++ }
            elseif (([string]$wfAcOrgs[0] -eq 'NVIDIA Corporation') -ne [bool]$wfAcRdnCaso[2]) { Write-Host "  [ERRO] Split-WinForgeCertificateSubject: '$($wfAcRdnCaso[0])' bateu com 'NVIDIA Corporation' quando não devia (ou o contrário)" -ForegroundColor Red; $wbErrors++ }
            else { $wfAcRdnOk++ }
        }
        # Dois O no mesmo assunto: 'O=Evil, O=NVIDIA Corporation' não pode virar um O só.
        if (@((Split-WinForgeCertificateSubject -Subject 'CN=x, O=Evil, O=NVIDIA Corporation, C=US')['O']).Count -ne 2) { Write-Host "  [ERRO] Split-WinForgeCertificateSubject: dois O no assunto deveriam virar dois valores" -ForegroundColor Red; $wbErrors++ }
        # Windows Update: a simulação diz o que faria e não toca no COM. Fora dela, a lista de
        # objetos IUpdate é a de $sync.DiagWUUpdates, que no SelfTest está vazia.
        $wfAcWuSeco = Install-WinForgeWindowsUpdateDriver -UpdateId 'x' -DryRun
        if ([string]$wfAcWuSeco.Text -notlike '*(id x)*') { Write-Host "  [ERRO] Install-WinForgeWindowsUpdateDriver -DryRun: o texto não traz o id ('$($wfAcWuSeco.Text)')" -ForegroundColor Red; $wbErrors++ }
        if ($null -ne $wfAcWuSeco.ResultCode) { Write-Host "  [ERRO] Install-WinForgeWindowsUpdateDriver -DryRun: ResultCode deveria ser nulo, veio '$($wfAcWuSeco.ResultCode)'" -ForegroundColor Red; $wbErrors++ }
        if ($wfAcWuSeco.RebootRequired -ne $false) { Write-Host "  [ERRO] Install-WinForgeWindowsUpdateDriver -DryRun: RebootRequired deveria ser `$false" -ForegroundColor Red; $wbErrors++ }
        # As duas funções que escrevem recusam sem -DryRun enquanto o WinForge está em SelfTest.
        $wfAcTravas = @(
            @('Install-WinForgeNvidiaDriver', { Install-WinForgeNvidiaDriver -Url 'https://us.download.nvidia.com/Windows/616.92/x.exe' -Version '616.92' }),
            @('Install-WinForgeWindowsUpdateDriver', { Install-WinForgeWindowsUpdateDriver -UpdateId 'x' })
        )
        foreach ($wfAcTrava in $wfAcTravas) {
            $wfAcTravaMsg = $null
            try { & $wfAcTrava[1] | Out-Null } catch { $wfAcTravaMsg = [string]$_.Exception.Message }
            if ($null -eq $wfAcTravaMsg) { Write-Host "  [ERRO] Ação de driver (trava): $($wfAcTrava[0]) sem -DryRun deveria recusar em SelfTest" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAcTravaMsg -notmatch 'SelfTest') { Write-Host "  [ERRO] Ação de driver (trava): a recusa de $($wfAcTrava[0]) não fala em SelfTest ('$wfAcTravaMsg')" -ForegroundColor Red; $wbErrors++ }
        }
        # Pasta de downloads: as MESMAS regras da pasta de backup padrão, e sem o afrouxamento de
        # -ExplicitRoot. O instalador baixado é aberto com a elevação do WinForge - uma pasta que um
        # processo de integridade média escreve trocaria o arquivo entre a conferência e a abertura.
        $wfAcRaizAberta = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\downloads-aberto'
        New-Item -ItemType Directory -Path $wfAcRaizAberta -Force | Out-Null
        $wfAcAclAberta = Get-Acl -LiteralPath $wfAcRaizAberta
        $wfAcAclAberta.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        Set-Acl -LiteralPath $wfAcRaizAberta -AclObject $wfAcAclAberta
        $wfAcConfAberta = Confirm-WinForgeDownloadRoot -Root $wfAcRaizAberta
        # O motivo exato varia com a elevação de quem compila (sem elevação a pasta é recusada já
        # pelo dono, antes de a DACL ser olhada); o que se cobra aqui é a recusa COM motivo.
        if ($wfAcConfAberta.Ok) { Write-Host "  [ERRO] Confirm-WinForgeDownloadRoot: pasta com escrita para 'Todos' foi aceita" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]::IsNullOrWhiteSpace([string]$wfAcConfAberta.Reason)) { Write-Host "  [ERRO] Confirm-WinForgeDownloadRoot: recusou a pasta aberta sem dizer por quê" -ForegroundColor Red; $wbErrors++ }
        # A pasta do próprio usuário passa com as regras de -Root explícito e é RECUSADA aqui: é a
        # prova de que a pasta de downloads não pegou o atalho que a pasta de teste usa.
        $wfAcEu = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $wfAcSystemSid = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::LocalSystemSid), $null
        $wfAcAdminSid = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid), $null
        if ($wfAcEu.Value -eq $wfAcSystemSid.Value -or $wfAcEu.Value -eq $wfAcAdminSid.Value) {
            Write-Host "  Pasta de downloads (dono): teste pulado - este build roda como SYSTEM ou como o próprio grupo Administradores"
        } else {
            $wfAcRaizDono = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\downloads-dono'
            New-Item -ItemType Directory -Path $wfAcRaizDono -Force | Out-Null
            $wfAcAclDono = New-Object System.Security.AccessControl.DirectorySecurity
            $wfAcAclDono.SetAccessRuleProtection($true, $false)
            foreach ($wfAcSid in @($wfAcSystemSid, $wfAcAdminSid, $wfAcEu)) {
                $wfAcAclDono.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $wfAcSid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            }
            $wfAcAclDono.SetOwner($wfAcEu)
            Set-Acl -LiteralPath $wfAcRaizDono -AclObject $wfAcAclDono
            $wfAcComRoot = Test-WinForgeSnapshotRootTrusted -Root $wfAcRaizDono -ExplicitRoot
            if (-not $wfAcComRoot.Trusted) { Write-Host "  [ERRO] Pasta de downloads (dono): a pasta de teste deveria passar com -ExplicitRoot ('$($wfAcComRoot.Reason)')" -ForegroundColor Red; $wbErrors++ }
            $wfAcConfDono = Confirm-WinForgeDownloadRoot -Root $wfAcRaizDono
            if ($wfAcConfDono.Ok) { Write-Host "  [ERRO] Confirm-WinForgeDownloadRoot: pasta com dono fora de SYSTEM/Administradores foi aceita" -ForegroundColor Red; $wbErrors++ }
            # O motivo exato depende de onde a cadeia quebra primeiro - sem a parada de %TEMP% (que
            # só existe com -ExplicitRoot) ela sobe pelo perfil do usuário, e lá o elo aberto
            # aparece antes da pasta de teste. O que se cobra é a recusa COM motivo; a regra de dono
            # em si é cobrada em 'Backup (dono)', sobre as listas de SID.
            elseif ([string]::IsNullOrWhiteSpace([string]$wfAcConfDono.Reason)) { Write-Host "  [ERRO] Confirm-WinForgeDownloadRoot: recusou a pasta de usuário sem dizer por quê" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Ações de driver: $wfAcOk de $($wfAcCasos.Count) linha(s) com a ação certa, $wfAcUrlOk de $($wfAcUrls.Count) URL(s) julgada(s), $wfAcRdnOk de $($wfAcRdnCasos.Count) assunto(s) de certificado, $wfAcRedOk de $($wfAcRedCasos.Count) erro(s) de download traduzido(s), download e instalação recusados em SelfTest"
    } catch {
        Write-Host "  [ERRO] ações de driver: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\assinatura') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\limpeza') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\downloads-aberto') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\downloads-dono') -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- o cache do catálogo é de TELA
    # O cache do catálogo da NVIDIA mora no perfil do usuário, e o perfil do usuário é gravável por
    # qualquer processo de integridade média da mesma conta. Enquanto ele só pintava o rótulo
    # "Baixar <versão>" na tabela, tudo bem. O problema era que a LINHA - e portanto o cache -
    # também dizia ao motor ELEVADO que endereço baixar e abrir, e um
    # '{ "Version": "999.99", "DownloadURL": "https://us.download.nvidia.com/<outro pacote>" }'
    # plantado ali passava por TODAS as travas seguintes por construção: o host é da nvidia.com, a
    # assinatura é da NVIDIA, a pasta é a protegida. O usuário via "⬆ atualizar" e clicava.
    #
    # O conserto é o clique refazer as três consultas sem ler cache nenhum. O que se prova aqui, sem
    # um byte de rede (a costura -Resolver responde no lugar do catálogo):
    #   1. com cache, o veneno É lido - sem isto o teste não estaria provando nada;
    #   2. com -NoCache, as três respostas vêm do catálogo e nada do arquivo aparece;
    #   3. o clique (-DryRun) usa a consulta ao vivo, e não o que a linha carrega;
    #   4. o clique RECUSA quando a resposta ao vivo não serve - versão que não é mais nova que a
    #      instalada (o instalador antigo continua assinado e continua vindo do host certo),
    #      endereço fora do domínio, ou catálogo que não respondeu.
    function New-WinForgeSelfTestCachePoison {
        <#
        .SYNOPSIS
            Planta um cache de catálogo INTEIRO (as duas listas e a busca do driver) escolhendo
            psid, pfid, versão e endereço.
        #>
        param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Url)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        (@([pscustomobject]@{ Name = 'GeForce RTX 30 Series'; Value = '999' }) | ConvertTo-Json -Depth 6) |
            Set-Content -LiteralPath (Join-Path $Dir 'nvidia-lookup-2-1.json') -Encoding UTF8
        (@([pscustomobject]@{ Name = 'GeForce RTX 3070'; Value = '888' }) | ConvertTo-Json -Depth 6) |
            Set-Content -LiteralPath (Join-Path $Dir 'nvidia-lookup-3-999.json') -Encoding UTF8
        # A busca do driver é plantada para os DOIS pares psid/pfid: o do próprio veneno (999/888,
        # que é onde as listas envenenadas levam) e o que a consulta ao vivo encontra (101/202).
        # Sem o segundo, um -NoCache que esquecesse justamente esta terceira leitura passaria batido
        # - o arquivo com o nome do par ao vivo é o único jeito de flagrar isso.
        # E os dois osID (135 = Windows 11, 57 = Windows 10), porque o clique lê o do perfil desta
        # máquina e o teste não pode depender de em qual Windows o build está rodando.
        foreach ($wfCatPar in @('999-888', '101-202')) {
            foreach ($wfCatOs in @(135, 57)) {
                ([pscustomobject]@{ Version = '999.99'; DownloadURL = $Url; ReleaseDateTime = 'Thu Sep 03, 2026' } | ConvertTo-Json -Depth 6) |
                    Set-Content -LiteralPath (Join-Path $Dir "nvidia-$wfCatPar-$wfCatOs.json") -Encoding UTF8
            }
        }
    }
    $wfCatRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\catalogo'
    try {
        $wfCatVeneno = 'https://us.download.nvidia.com/Windows/999.99/veneno.exe'
        $wfCatVersaoViva = '616.92'
        $wfCatUrlViva = 'https://us.download.nvidia.com/Windows/616.92/616.92-desktop-win10-win11-64bit-international-dch-whql.exe'
        $wfCatFalha = $false
        # A costura: responde as três consultas do catálogo. psid/pfid diferentes dos do veneno de
        # propósito - é assim que se vê de qual das duas fontes cada número veio.
        $wfCatResolver = {
            param($wfCatUri)
            if ($wfCatFalha) { throw "catálogo fora do ar (simulado)" }
            if ($wfCatUri -match 'TypeID=2') {
                return [pscustomobject]@{ LookupValueSearch = [pscustomobject]@{ LookupValues = [pscustomobject]@{ LookupValue = @([pscustomobject]@{ Name = 'GeForce RTX 30 Series'; Value = '101' }) } } }
            }
            if ($wfCatUri -match 'TypeID=3') {
                if ($wfCatUri -notmatch 'ParentID=101') { throw "psid inesperado na consulta: '$wfCatUri'" }
                return [pscustomobject]@{ LookupValueSearch = [pscustomobject]@{ LookupValues = [pscustomobject]@{ LookupValue = @([pscustomobject]@{ Name = 'GeForce RTX 3070'; Value = '202' }) } } }
            }
            if ($wfCatUri -match 'DriverManualLookup') {
                if ($wfCatUri -notmatch 'psid=101&pfid=202&') { throw "produto inesperado na consulta: '$wfCatUri'" }
                return [pscustomobject]@{ IDS = @([pscustomobject]@{ downloadInfo = [pscustomobject]@{ Version = $wfCatVersaoViva; DownloadURL = $wfCatUrlViva; ReleaseDateTime = 'Thu Sep 03, 2026' } }) }
            }
            throw "consulta inesperada: '$wfCatUri'"
        }
        # 1. O cenário. Sem esta primeira metade, o teste seguinte passaria mesmo com o cache morto.
        $wfCatDirCache = Join-Path $wfCatRaiz 'com-cache'
        New-WinForgeSelfTestCachePoison -Dir $wfCatDirCache -Url $wfCatVeneno
        $wfCatComCache = Get-WinForgeNvidiaLatestDriver -GpuName 'NVIDIA GeForce RTX 3070' -Root $wfCatDirCache -Resolver $wfCatResolver
        if ([string]$wfCatComCache.Version -ne '999.99' -or [string]$wfCatComCache.Url -ne $wfCatVeneno) {
            Write-Host "  [ERRO] cache do catálogo: o cenário não vale - o cache plantado deveria ser lido sem -NoCache (veio '$($wfCatComCache.Version)' / '$($wfCatComCache.Url)')" -ForegroundColor Red; $wbErrors++
        }
        # 2. Com -NoCache o arquivo não é lido em NENHUMA das três consultas: nem a série (999), nem
        #    o produto (888), nem a versão/endereço.
        $wfCatDirVivo = Join-Path $wfCatRaiz 'ao-vivo'
        New-WinForgeSelfTestCachePoison -Dir $wfCatDirVivo -Url $wfCatVeneno
        $wfCatVivo = Get-WinForgeNvidiaLatestDriver -GpuName 'NVIDIA GeForce RTX 3070' -NoCache -Root $wfCatDirVivo -Resolver $wfCatResolver
        if ([string]$wfCatVivo.Status -ne 'ok') { Write-Host "  [ERRO] cache do catálogo: a consulta ao vivo deveria responder 'ok', veio '$($wfCatVivo.Status)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfCatVivo.Version -ne $wfCatVersaoViva -or [string]$wfCatVivo.Url -ne $wfCatUrlViva) {
            Write-Host "  [ERRO] cache do catálogo: a consulta ao vivo devolveu '$($wfCatVivo.Version)' / '$($wfCatVivo.Url)'" -ForegroundColor Red; $wbErrors++
        }
        if ([string]$wfCatVivo.Version -eq '999.99' -or [string]$wfCatVivo.Url -eq $wfCatVeneno) {
            Write-Host "  [ERRO] cache do catálogo: o arquivo plantado chegou à consulta ao vivo" -ForegroundColor Red; $wbErrors++
        }
        # 3 e 4. O clique. A linha carrega o veneno (é o que a tabela desenhou a partir do cache) e
        #        uma versão instalada de 616.56; o que sai é sempre o da consulta ao vivo.
        #        Caso: @(nome, versão ao vivo, endereço ao vivo, catálogo fora do ar, trecho esperado)
        $wfCatLinha = [pscustomobject]@{
            Device = 'NVIDIA GeForce RTX 3070'; Version = '32.0.16.1656'; Latest = '999.99'
            ActionKind = 'nvidia-download'; ActionLabel = 'Baixar 999.99'; ActionUrl = $wfCatVeneno
        }
        $wfCatCasos = @(
            @('versão nova',            '616.92', $wfCatUrlViva,                          $false, 'baixaria o driver NVIDIA 616.92'),
            @('mesma versão instalada', '616.56', $wfCatUrlViva,                          $false, 'não é mais nova que a instalada'),
            @('versão mais antiga',     '566.36', $wfCatUrlViva,                          $false, 'não é mais nova que a instalada'),
            @('endereço fora do domínio', '616.92', 'https://nvidia.com.evil.com/x.exe',  $false, 'não é um https de um host da nvidia.com'),
            @('catálogo fora do ar',    '616.92', $wfCatUrlViva,                          $true,  "respondeu 'indisponível'")
        )
        $wfCatCliqueOk = 0
        foreach ($wfCatCaso in $wfCatCasos) {
            $wfCatVersaoViva = [string]$wfCatCaso[1]
            $wfCatUrlViva = [string]$wfCatCaso[2]
            $wfCatFalha = [bool]$wfCatCaso[3]
            $wfCatDirCaso = Join-Path $wfCatRaiz ('clique-' + $wfCatCliqueOk)
            New-WinForgeSelfTestCachePoison -Dir $wfCatDirCaso -Url $wfCatVeneno
            $wfCatTexto = [string](Invoke-WinForgeDriverAction -Row $wfCatLinha -DryRun -Root $wfCatDirCaso -Resolver $wfCatResolver)
            if ($wfCatTexto -notmatch 'consulta ao vivo') { Write-Host "  [ERRO] clique de download ($($wfCatCaso[0])): o texto não diz que houve consulta ao vivo ('$wfCatTexto')" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfCatTexto -notlike "*$($wfCatCaso[4])*") { Write-Host "  [ERRO] clique de download ($($wfCatCaso[0])): esperado '$($wfCatCaso[4])' no texto, veio '$wfCatTexto'" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfCatTexto -match '999\.99' -or $wfCatTexto -match 'veneno') { Write-Host "  [ERRO] clique de download ($($wfCatCaso[0])): o que a linha carregava vazou para o texto ('$wfCatTexto')" -ForegroundColor Red; $wbErrors++ }
            else { $wfCatCliqueOk++ }
        }
        $wfCatFalha = $false
        # O tamanho da caixa de confirmação é informação, não trava: endereço que não passa na
        # conferência de domínio nem chega a virar requisição e volta com o texto genérico.
        if ((Get-WinForgeNvidiaDownloadSizeText -Url 'https://nvidia.com.evil.com/x.exe') -ne 'várias centenas de MB') {
            Write-Host "  [ERRO] tamanho do download: endereço fora do domínio deveria voltar o texto genérico" -ForegroundColor Red; $wbErrors++
        }
        Write-Host "  Cache do catálogo: é de tela - com cache o arquivo plantado é lido, com -NoCache não aparece em nenhuma das 3 consultas; clique julgado em $wfCatCliqueOk de $($wfCatCasos.Count) cenário(s) pela consulta ao vivo"
    } catch {
        Write-Host "  [ERRO] cache do catálogo: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path $wfCatRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- consulta ao vivo fora da thread da janela
    # A consulta ao vivo são três requisições de 5 s mais a do tamanho (10 s): rodando no clique,
    # a janela ficava até ~25 s sem responder e o rótulo "Consultando o catálogo..." nem chegava a
    # ser pintado - o Dispatcher estava parado dentro do próprio handler. Então o clique só liga a
    # trava, escreve na barra e despacha; quem pergunta ao catálogo é o runspace, e a caixa de
    # confirmação volta para a thread da janela pelo callback.
    try {
        # 1. O callback nasce no ESCOPO DO ARQUIVO, na runspace principal. Criado dentro do corpo do
        #    job ele pertenceria à runspace do pool e travaria no primeiro pipeline que o Dispatcher
        #    rodasse - o laço do Plano 3.
        if ($sync.WinForgeDriverConfirmCallback -isnot [scriptblock]) {
            Write-Host "  [ERRO] consulta ao vivo: `$sync.WinForgeDriverConfirmCallback não é um scriptblock de escopo de arquivo" -ForegroundColor Red; $wbErrors++
        }
        # 2. Trava de origem: no caminho do CLIQUE (depois da trava de SelfTest) nenhuma chamada a
        #    Resolve-WinForgeNvidiaDownloadTarget pode aparecer ANTES do corpo do runspace. O
        #    -DryRun continua chamando direto, e por isso o trecho começa na trava de SelfTest.
        $wfVivoDef = [string]${function:Invoke-WinForgeDriverAction}
        $wfVivoMarca = "Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeDriverAction (nvidia-download)'"
        $wfVivoIni = $wfVivoDef.IndexOf($wfVivoMarca)
        if ($wfVivoIni -lt 0) {
            Write-Host "  [ERRO] consulta ao vivo: não achei a trava de SelfTest do download no corpo de Invoke-WinForgeDriverAction" -ForegroundColor Red; $wbErrors++
        } else {
            $wfVivoClique = $wfVivoDef.Substring($wfVivoIni)
            $wfVivoCorpo = $wfVivoClique.IndexOf('$corpo = {')
            $wfVivoResolve = $wfVivoClique.IndexOf('Resolve-WinForgeNvidiaDownloadTarget')
            if ($wfVivoClique -notmatch 'Invoke-WPFRunspace') { Write-Host "  [ERRO] consulta ao vivo: o caminho do clique não despacha nada para um runspace" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfVivoCorpo -lt 0) { Write-Host "  [ERRO] consulta ao vivo: o caminho do clique não tem o corpo `$corpo do runspace" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfVivoResolve -lt 0) { Write-Host "  [ERRO] consulta ao vivo: o caminho do clique não consulta o catálogo" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfVivoResolve -lt $wfVivoCorpo) { Write-Host "  [ERRO] consulta ao vivo: Resolve-WinForgeNvidiaDownloadTarget roda na thread do clique, antes do corpo do runspace" -ForegroundColor Red; $wbErrors++ }
            if ($wfVivoClique -notmatch 'WinForgeDriverConfirmCallback') { Write-Host "  [ERRO] consulta ao vivo: o caminho do clique não volta à thread da janela pelo callback" -ForegroundColor Red; $wbErrors++ }
        }
        # 3. Recusa da consulta ao vivo solta a trava: sem isso a interface ficava "ocupada" para
        #    sempre depois de um clique sem rede, e nenhum outro comando começaria.
        $wfVivoAntes = $sync.CommandRunning
        $sync.CommandRunning = $true
        $sync.WinForgeDriverConfirm = @{ Ok = $false; Url = $null; Version = $null; SizeText = $null; Reason = 'recusa sintética do SelfTest' }
        try { & $sync.WinForgeDriverConfirmCallback } catch {
            Write-Host "  [ERRO] consulta ao vivo: o callback lançou '$($_.Exception.Message)' na recusa" -ForegroundColor Red; $wbErrors++
        }
        if ($sync.CommandRunning) { Write-Host "  [ERRO] consulta ao vivo: a trava `$sync.CommandRunning ficou ligada depois da recusa" -ForegroundColor Red; $wbErrors++ }
        $sync.CommandRunning = $wfVivoAntes
        $sync.WinForgeDriverConfirm = $null
        Write-Host "  Consulta ao vivo: fora da thread da janela, confirmação pelo callback de escopo de arquivo, trava solta na recusa"
    } catch {
        Write-Host "  [ERRO] consulta ao vivo: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # ---------------------------------------------------------------- cadeia inteira da pasta protegida
    # Conferir só a ÚLTIMA pasta deixava um caminho aberto: '%ProgramData%\WinForge' criado com a ACL
    # herdada de %ProgramData% dá FILE_DELETE_CHILD a um processo de integridade média da mesma conta.
    # Com ele, durante os minutos do download, dá para renomear 'downloads', plantar uma junção no
    # lugar e trocar o instalador entre a conferência da assinatura e o Start-Process - sem que a
    # última pasta jamais apareça como ponto de reanálise nem mude de dono.
    #
    # Então: a cadeia inteira nasce protegida (New-WinForgeSnapshotRoot) e a cadeia inteira é
    # conferida (Test-WinForgeSnapshotRootTrusted), de %ProgramData%/%TEMP% (exclusive) até a última
    # pasta (inclusive).
    $wfCadBase = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\seg'
    try {
        Remove-Item -Path $wfCadBase -Recurse -Force -ErrorAction SilentlyContinue
        $wfCadMeio = Join-Path $wfCadBase 'WinForge'
        $wfCadFolha = Join-Path $wfCadMeio 'downloads'
        New-WinForgeSnapshotRoot -Root $wfCadFolha | Out-Null
        if (-not (Test-Path -LiteralPath $wfCadFolha)) {
            Write-Host "  [ERRO] cadeia protegida: '$wfCadFolha' não foi criada" -ForegroundColor Red; $wbErrors++
        } else {
            # 1. Nenhuma pasta da cadeia herda a ACL do pai - nem as do meio, que antes nasciam de um
            #    New-Item -Force com a herança de %ProgramData% inteira.
            foreach ($wfCadDir in @($wfCadBase, $wfCadMeio, $wfCadFolha)) {
                if (-not (Get-Acl -LiteralPath $wfCadDir).AreAccessRulesProtected) {
                    Write-Host "  [ERRO] cadeia protegida: '$wfCadDir' nasceu herdando a ACL do pai" -ForegroundColor Red; $wbErrors++
                }
            }
            # 2. Com as regras da pasta de teste (-ExplicitRoot, a identidade atual pode ser dona) a
            #    cadeia recém-criada PASSA: a conferência dos ancestrais não pode estourar para fora
            #    de %TEMP% e reprovar C:\ (que dá 'criar pasta/acrescentar dados' ao grupo Usuários).
            $wfCadLimpa = Test-WinForgeSnapshotRootTrusted -Root $wfCadFolha -ExplicitRoot
            if (-not $wfCadLimpa.Trusted) { Write-Host "  [ERRO] cadeia protegida: a cadeia de teste recém-criada deveria passar com -ExplicitRoot ('$($wfCadLimpa.Reason)')" -ForegroundColor Red; $wbErrors++ }
            # 3. Com as regras da pasta PADRÃO a mesma cadeia é recusada, e por MAIS motivos do que
            #    antes: sem elevação nada aqui pertence a SYSTEM nem ao grupo Administradores, e
            #    sem a parada de %TEMP% (que só vale com -ExplicitRoot) a conferência ainda sobe
            #    pelo perfil do usuário, onde o próprio usuário escreve.
            $wfCadPadrao = Test-WinForgeSnapshotRootTrusted -Root $wfCadFolha
            if ($wfCadPadrao.Trusted) { Write-Host "  [ERRO] cadeia protegida: a cadeia de teste passou com as regras da pasta padrão" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]::IsNullOrWhiteSpace([string]$wfCadPadrao.Reason)) { Write-Host "  [ERRO] cadeia protegida: a recusa com as regras da pasta padrão veio sem motivo" -ForegroundColor Red; $wbErrors++ }
            # 4. A PROVA de que os ancestrais são conferidos: só a pasta do MEIO ganha escrita para
            #    'Todos'. A última pasta continua limpa (a ACL dela é protegida, a ACE nova não
            #    desce até lá), então uma conferência que olhasse só a folha diria que está tudo bem.
            # Só a seção DACL, por DirectoryInfo: Get-Acl/Set-Acl carregam a seção de AUDITORIA
            # junto, e gravá-la exige SeSecurityPrivilege - o mesmo motivo de
            # Repair-WinForgeSnapshotRootOwnerRight fazer assim.
            $wfCadSecao = [System.Security.AccessControl.AccessControlSections]::Access
            $wfCadPastaMeio = New-Object System.IO.DirectoryInfo $wfCadMeio
            $wfCadAclMeio = $wfCadPastaMeio.GetAccessControl($wfCadSecao)
            $wfCadAclMeio.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-1-0'), 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            $wfCadPastaMeio.SetAccessControl($wfCadAclMeio)
            $wfCadFolhaSo = Test-WinForgeSnapshotRootTrusted -Root $wfCadFolha -ExplicitRoot
            if ((Get-Acl -LiteralPath $wfCadFolha).Access | Where-Object { [string]$_.IdentityReference -match 'Todos|Everyone' }) {
                Write-Host "  [ERRO] cadeia protegida: a ACE de 'Todos' desceu até a última pasta - o teste não prova mais nada sobre os ancestrais" -ForegroundColor Red; $wbErrors++
            } elseif ($wfCadFolhaSo.Trusted) {
                Write-Host "  [ERRO] cadeia protegida: escrita para 'Todos' na pasta do MEIO passou batida - os ancestrais não estão sendo conferidos" -ForegroundColor Red; $wbErrors++
            } elseif ([string]$wfCadFolhaSo.Reason -notlike "*$wfCadMeio*") {
                Write-Host "  [ERRO] cadeia protegida: a recusa não nomeia a pasta do meio ('$($wfCadFolhaSo.Reason)')" -ForegroundColor Red; $wbErrors++
            }
            # 5. E a pasta de downloads recusa pelo mesmo motivo, com um texto para a barra de status.
            $wfCadConf = Confirm-WinForgeDownloadRoot -Root $wfCadFolha
            if ($wfCadConf.Ok) { Write-Host "  [ERRO] cadeia protegida: Confirm-WinForgeDownloadRoot aceitou uma cadeia com ancestral aberto" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Cadeia da pasta protegida: 3 pasta(s) criadas sem herança; ancestral com escrita para 'Todos' recusado e nomeado"
        }
    } catch {
        Write-Host "  [ERRO] cadeia protegida: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path $wfCadBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    # ---------------------------------------------------------------- raiz de confiança: API de pastas, não ambiente
    # %ProgramData% e %TEMP% são variáveis de USUÁRIO: moram em HKCU\Environment, qualquer processo
    # de integridade média da conta as reescreve, e o motor ELEVADO herda o ambiente de quem o abriu
    # (o launcher repassa o ambiente). Enquanto a raiz de confiança saía delas, era o atacante quem
    # escolhia onde o WinForge confia - e as duas metades do ataque são diferentes:
    #   1. 'ProgramData=C:\Users\Public\...' movia a pasta de backup E a de downloads para uma pasta
    #      dele, onde ele é dono e passa em toda conferência de dono e DACL;
    #   2. 'TEMP=%ProgramData%\WinForge' fazia a pasta do MEIO virar parada da cadeia e sair da
    #      conferência - justamente a pasta cuja ACL herdada dá FILE_DELETE_CHILD ao usuário, que é
    #      o que permite renomear 'downloads' e plantar uma junção no lugar.
    # As duas variáveis são apontadas para esses valores DE PROPÓSITO aqui, e nada pode mudar. Nada
    # é criado nem escrito: só se pergunta que caminho as funções montam e que cadeia elas conferem.
    #
    # %LOCALAPPDATA% entra na mesma lista. O que mora lá é do usuário e continua gravável por ele -
    # por isso o cache do catálogo é de TELA e o clique consulta ao vivo -, mas a PASTA não pode ser
    # escolhida pela variável: o relatório HTML é gravado pelo motor elevado e aberto em seguida com
    # Start-Process, e um 'LOCALAPPDATA=<pasta do atacante>' escolheria onde.
    $wfAmbPdAntes = $env:ProgramData
    $wfAmbTmpAntes = $env:TEMP
    $wfAmbLadAntes = $env:LOCALAPPDATA
    try {
        $wfAmbBase = [string][Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
        $wfAmbMeio = Join-Path $wfAmbBase 'WinForge'
        $env:ProgramData = 'C:\Users\Public\WinForge-Ambiente-Falso'
        $env:TEMP = $wfAmbMeio
        $env:LOCALAPPDATA = 'C:\Users\Public\WinForge-Ambiente-Falso'
        $wfAmbLadReal = ([string][Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)).TrimEnd('\')
        if ((Get-WinForgeUserDataRoot) -ne $wfAmbLadReal) { Write-Host "  [ERRO] raiz de confiança: com `$env:LOCALAPPDATA sequestrado, Get-WinForgeUserDataRoot veio '$(Get-WinForgeUserDataRoot)'" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeCacheRoot) -ne (Join-Path $wfAmbLadReal 'WinForge\cache')) { Write-Host "  [ERRO] raiz de confiança: com `$env:LOCALAPPDATA sequestrado, Get-WinForgeCacheRoot veio '$(Get-WinForgeCacheRoot)'" -ForegroundColor Red; $wbErrors++ }
        $wfAmbBk = Get-WinForgeSnapshotRoot
        $wfAmbDl = Get-WinForgeDownloadRoot
        if ($wfAmbBk -ne (Join-Path $wfAmbBase 'WinForge\iis-backup')) { Write-Host "  [ERRO] raiz de confiança: com `$env:ProgramData sequestrado, Get-WinForgeSnapshotRoot veio '$wfAmbBk'" -ForegroundColor Red; $wbErrors++ }
        if ($wfAmbDl -ne (Join-Path $wfAmbBase 'WinForge\downloads')) { Write-Host "  [ERRO] raiz de confiança: com `$env:ProgramData sequestrado, Get-WinForgeDownloadRoot veio '$wfAmbDl'" -ForegroundColor Red; $wbErrors++ }
        # A cadeia da pasta PADRÃO tem de continuar com as duas pastas - a do meio inclusive, que é
        # a que o %TEMP% sequestrado tentava transformar em parada.
        $wfAmbCad = @((Test-WinForgeSnapshotRootPath -Root $wfAmbDl).Chain)
        if ($wfAmbCad.Count -ne 2) { Write-Host "  [ERRO] raiz de confiança: a cadeia da pasta padrão deveria ter 2 pastas, veio $($wfAmbCad.Count) ($($wfAmbCad -join ' | '))" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfAmbCad[0] -ne $wfAmbMeio) { Write-Host "  [ERRO] raiz de confiança: `$env:TEMP tirou a pasta do meio da cadeia (veio '$($wfAmbCad[0])', esperado '$wfAmbMeio')" -ForegroundColor Red; $wbErrors++ }
        # A parada de %TEMP% também não existe SEM -ExplicitRoot: uma pasta de teste conferida com as
        # regras da pasta padrão sobe até a raiz do volume, como qualquer outra.
        $wfAmbParadas = Get-WinForgeSnapshotChainStop
        if ($wfAmbParadas.Count -ne 1) { Write-Host "  [ERRO] raiz de confiança: sem -ExplicitRoot deveria haver 1 parada, veio $($wfAmbParadas.Count)" -ForegroundColor Red; $wbErrors++ }
        elseif (-not $wfAmbParadas.ContainsKey($wfAmbBase.TrimEnd('\'))) { Write-Host "  [ERRO] raiz de confiança: a única parada deveria ser '$wfAmbBase' ($(@($wfAmbParadas.Keys) -join ' | '))" -ForegroundColor Red; $wbErrors++ }
    } catch {
        Write-Host "  [ERRO] raiz de confiança: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        $env:ProgramData = $wfAmbPdAntes
        $env:TEMP = $wfAmbTmpAntes
        $env:LOCALAPPDATA = $wfAmbLadAntes
    }
    # O teste não pode deixar o ambiente estragado para os blocos seguintes.
    if ($env:ProgramData -ne $wfAmbPdAntes -or $env:TEMP -ne $wfAmbTmpAntes -or $env:LOCALAPPDATA -ne $wfAmbLadAntes) { Write-Host "  [ERRO] raiz de confiança: o ambiente não voltou ao que era" -ForegroundColor Red; $wbErrors++ }
    # Com -ExplicitRoot (o caminho do -SelfTest) a parada de %TEMP% volta, e é o %TEMP% DE VERDADE:
    # a cadeia de uma pasta de teste começa logo abaixo dele. Sem a chave, a mesma pasta é conferida
    # até a raiz do volume - é essa diferença que faz a pasta padrão não ganhar parada de graça.
    try {
        $wfAmbTmpReal = ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())).TrimEnd('\')
        $wfAmbAlvo = Join-Path $wfAmbTmpReal 'WinForge-SelfTest\parada\folha'
        $wfAmbExp = @((Test-WinForgeSnapshotRootPath -Root $wfAmbAlvo -ExplicitRoot).Chain)
        if ($wfAmbExp.Count -ne 3) { Write-Host "  [ERRO] raiz de confiança (-ExplicitRoot): a cadeia deveria parar em '$wfAmbTmpReal' e ter 3 pastas, veio $($wfAmbExp.Count) ($($wfAmbExp -join ' | '))" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfAmbExp[0] -ne (Join-Path $wfAmbTmpReal 'WinForge-SelfTest')) { Write-Host "  [ERRO] raiz de confiança (-ExplicitRoot): a cadeia começa em '$($wfAmbExp[0])'" -ForegroundColor Red; $wbErrors++ }
        $wfAmbSem = @((Test-WinForgeSnapshotRootPath -Root $wfAmbAlvo).Chain)
        if ($wfAmbSem.Count -le 3) { Write-Host "  [ERRO] raiz de confiança: sem -ExplicitRoot a cadeia parou em %TEMP% assim mesmo ($($wfAmbSem -join ' | '))" -ForegroundColor Red; $wbErrors++ }
        # Ancestral que não pôde ser LIDO virou recusa (antes era pulado junto com o inexistente,
        # porque Test-Path devolve $false para os dois). O lado que dá para provar sem elevação é o
        # outro: pasta que simplesmente NÃO EXISTE continua confiável. É o caso da primeira
        # execução - se ele virasse recusa, nada mais gravaria backup nenhum.
        $wfAmbNova = Join-Path $wfAmbTmpReal ('WinForge-SelfTest\ainda-nao-existe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $wfAmbNovaT = Test-WinForgeSnapshotRootTrusted -Root $wfAmbNova -ExplicitRoot
        if (-not $wfAmbNovaT.Trusted) { Write-Host "  [ERRO] raiz de confiança: pasta inexistente deveria ser confiável ('$($wfAmbNovaT.Reason)')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Raiz de confiança: base e paradas vêm da API de pastas; `$env:ProgramData, `$env:TEMP e `$env:LOCALAPPDATA sequestrados não movem nada e o ambiente volta ao que era"
    } catch {
        Write-Host "  [ERRO] raiz de confiança (-ExplicitRoot): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
    # ---------------------------------------------------------------- pino do arquivo baixado
    # Entre a conferência da assinatura e o Start-Process havia uma janela: o caminho era conferido,
    # e depois RESOLVIDO de novo. O conserto é manter um handle aberto no arquivo final, com
    # FileShare.Read, desde a renomeação até o instalador subir - quem tenta renomear ou apagar o
    # arquivo nesse intervalo leva violação de compartilhamento.
    #
    # Este helper prova o mecanismo num arquivo de teste: com o pino aberto o rename FALHA, e mesmo
    # assim as três leituras de que o caminho depende continuam funcionando.
    function Test-WinForgeFilePinned {
        <#
        .SYNOPSIS
            $true se um handle com FileShare.Read impede a renomeação do arquivo.
        .DESCRIPTION
            Renomear exige DELETE no arquivo, e DELETE só é concedido a um segundo open se o handle
            já aberto tiver compartilhado FILE_SHARE_DELETE. FileShare.Read não compartilha, então a
            renomeação tem de falhar - é essa a garantia em que Install-WinForgeNvidiaDriver se apoia.
        #>
        param([Parameter(Mandatory)][string]$Path)
        $wfPinH = $null
        $wfPinRenomeou = $false
        $wfPinOutro = "$Path.trocado"
        try {
            $wfPinH = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try { [System.IO.File]::Move($Path, $wfPinOutro); $wfPinRenomeou = $true } catch { }
        } finally {
            if ($wfPinH) { $wfPinH.Dispose() }
        }
        if ($wfPinRenomeou) { try { [System.IO.File]::Move($wfPinOutro, $Path) } catch { } }
        return (-not $wfPinRenomeou)
    }
    $wfPinDir = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\pino'
    try {
        New-Item -ItemType Directory -Path $wfPinDir -Force | Out-Null
        $wfPinArq = Join-Path $wfPinDir 'instalador.exe'
        Set-Content -LiteralPath $wfPinArq -Value 'MZ arquivo de teste do pino' -Encoding Ascii
        if (-not (Test-WinForgeFilePinned -Path $wfPinArq)) {
            Write-Host "  [ERRO] pino do arquivo: com o handle aberto a renomeação deveria falhar" -ForegroundColor Red; $wbErrors++
        }
        # Sem o pino a renomeação passa - senão o teste acima estaria provando o nada.
        $wfPinSolto = Join-Path $wfPinDir 'solto.exe'
        Set-Content -LiteralPath $wfPinSolto -Value 'MZ arquivo solto' -Encoding Ascii
        $wfPinSoltoOk = $false
        try { [System.IO.File]::Move($wfPinSolto, "$wfPinSolto.trocado"); $wfPinSoltoOk = $true } catch { }
        if (-not $wfPinSoltoOk) { Write-Host "  [ERRO] pino do arquivo: sem pino a renomeação deveria passar - o teste do pino não prova nada" -ForegroundColor Red; $wbErrors++ }
        # As três operações que acontecem COM o pino aberto em Install-WinForgeNvidiaDriver.
        $wfPinH2 = $null
        try {
            $wfPinH2 = [System.IO.File]::Open($wfPinArq, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            # 1. Get-AuthenticodeSignature abre o arquivo por conta própria: com FileShare.Read ele lê.
            try { Get-AuthenticodeSignature -LiteralPath $wfPinArq -ErrorAction Stop | Out-Null }
            catch { Write-Host "  [ERRO] pino do arquivo: Get-AuthenticodeSignature não leu o arquivo com o pino aberto ($($_.Exception.Message))" -ForegroundColor Red; $wbErrors++ }
            # 2. Get-Acl (a conferência de dono e permissões).
            try { Get-Acl -LiteralPath $wfPinArq -ErrorAction Stop | Out-Null }
            catch { Write-Host "  [ERRO] pino do arquivo: Get-Acl falhou com o pino aberto ($($_.Exception.Message))" -ForegroundColor Red; $wbErrors++ }
            # 3. A gravação da DACL fechada (Protect-WinForgeSnapshotFile): WRITE_DAC não passa pelo
            #    modo de compartilhamento, que só governa leitura, escrita de DADOS e exclusão.
            try {
                $wfPinDacl = New-Object System.Security.AccessControl.FileSecurity
                $wfPinDacl.SetAccessRuleProtection($true, $false)
                $wfPinDacl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule ([System.Security.Principal.WindowsIdentity]::GetCurrent().User), 'FullControl', 'Allow'))
                (New-Object System.IO.FileInfo $wfPinArq).SetAccessControl($wfPinDacl)
            } catch { Write-Host "  [ERRO] pino do arquivo: a DACL não pôde ser fechada com o pino aberto ($($_.Exception.Message))" -ForegroundColor Red; $wbErrors++ }
        } finally {
            if ($wfPinH2) { $wfPinH2.Dispose() }
        }
        # O download em si não roda em SelfTest, então as duas travas que dependem dele são cobradas
        # no corpo da função: o pino e a recusa de redirecionamento.
        # Os padrões são o FORMATO DA CHAMADA, e não o nome solto: o bloco de ajuda da função
        # explica as três travas com essas mesmas palavras, e procurar o nome acharia o comentário.
        $wfPinDef = [string](Get-Command Install-WinForgeNvidiaDriver).Definition
        if ($wfPinDef -notmatch 'Invoke-WebRequest[^\r\n]*-MaximumRedirection 0') { Write-Host "  [ERRO] pino do arquivo: o download não recusa redirecionamento (-MaximumRedirection 0)" -ForegroundColor Red; $wbErrors++ }
        if ($wfPinDef -notmatch '\[System\.IO\.File\]::Open\(\$destino') { Write-Host "  [ERRO] pino do arquivo: Install-WinForgeNvidiaDriver não fixa o arquivo antes de conferir e abrir" -ForegroundColor Red; $wbErrors++ }
        if ($wfPinDef -notmatch 'Test-WinForgeSnapshotRootPath -Root \(Split-Path -Parent \$destino\)') { Write-Host "  [ERRO] pino do arquivo: a cadeia de pastas não é reconferida antes do Start-Process" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Pino do arquivo: renomeação bloqueada com o handle aberto, assinatura/ACL/DACL ainda acessíveis, redirecionamento recusado"
    } catch {
        Write-Host "  [ERRO] pino do arquivo: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -Path $wfPinDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
        [xml]$wbXaml = $inputXML
        $wbReader = New-Object System.Xml.XmlNodeReader $wbXaml
        $wbWindow = [Windows.Markup.XamlReader]::Load($wbReader)
        $wbTabs = @($wbWindow.FindName("WPFTabNav").Items | ForEach-Object { $_.Header })
        Write-Host "  XAML: OK - abas: $($wbTabs -join ', ')"
        foreach ($n in 'gamespanel','WPFTab7BT','WPFPresetWinForge','WPFPresetGamer','WPFAppxWinForgeSelection','WPFGamesApplyButton','WPFGamesUndoButton','WPFSelectRecommended','WPFGamesSelectRecommended','WPFTab8BT','WPFDiagCards','WPFDiagDrivers','WPFDiagRefresh','WPFDiagExport','WPFDiagStatus','WPFDiagInfos','WPFDiagRecs','WPFDiagWU','WPFDiagWULabel','WPFDiagWUDrivers','WPFDiagSelectRecommended','WPFDiagClearRecommended','WPFDiagApplySelected','WPFDiagUndoSelected','WPFDiagRecCount','WPFDiagScroll','serverpanel','WPFTab9BT','WPFServerApplyButton','WPFServerUndoButton','WPFServerSelectRecommended','WPFClearServerSelection','WPFGetInstalledServer') {
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
        # (A Tag, que é o que filtra de verdade, é conferida no BUILD: $sync.AppCategoryChips só é
        # atribuído lá no fim do arquivo, depois deste bloco, então aqui ela ainda é $null.)
        $wfChips = @($wbWindow.FindName('WPFSearchChips').Children | Where-Object { $_ -is [System.Windows.Controls.Primitives.ToggleButton] } | ForEach-Object { [string]$_.Content })
        $wfChipsGrupos = @($wfChips | Where-Object { $_ -ne 'Todos' } | Sort-Object)
        if (($wfChipsGrupos -join '|') -ne (($wfAppsCategorias | Sort-Object) -join '|')) { Write-Host "  [ERRO] chips da aba Instalar: '$($wfChipsGrupos -join ', ')' não bate com os grupos '$($wfAppsCategorias -join ', ')'" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Chips da aba Instalar: $($wfChips.Count) (Todos + $($wfChipsGrupos.Count) grupos)" }
        # monta cada aba sem mostrar a janela (exercita Invoke-WPFUIElements, filtros, toggles e botões)
        $sync["Form"] = $wbWindow
        $wbXaml.SelectNodes("//*[@Name]") | ForEach-Object { $sync["$($_.Name)"] = $sync["Form"].FindName($_.Name) }
        $sync.InitializedTabs = @{}
        # Aplica o tema de verdade nesta janela, como a inicialização faz. Sem isto o -SelfTest
        # montaria as abas com o dicionário de recursos VAZIO: toda referência dinâmica cairia no
        # nada e o teste ficaria cego justamente para o que a Tarefa 6 mudou. De quebra, é aqui
        # que um token com valor que o aplicador não converte (um Thickness torto, por exemplo)
        # aparece, porque Set-ThemeResourceProperty avisa e segue.
        foreach ($wfTemaAplicar in @('Light', 'Dark')) {
            $wfTemaAviso = @(Invoke-WinForgeThemeChange -theme $wfTemaAplicar 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            if ($wfTemaAviso.Count) { Write-Host "  [ERRO] tema $wfTemaAplicar : $($wfTemaAviso.Count) token(s) recusado(s) pelo aplicador -> $(@($wfTemaAviso | ForEach-Object { $_.Message }) -join '; ')" -ForegroundColor Red; $wbErrors++ }
        }
        # Fica no Escuro: é o tema em que as fotos de QA são tiradas e o padrão da máquina de teste.
        $wfTemaFaltando = @('MainBackgroundColor', 'CardBackgroundColor', 'ButtonForegroundSelectedColor', 'TabAccentColor', 'RecommendedColor', 'DiscouragedColor', 'DangerColor', 'FontFamily', 'HeaderFontFamily') |
            Where-Object { $null -eq $sync.Form.TryFindResource($_) }
        if ($wfTemaFaltando.Count) { Write-Host "  [ERRO] tema: recurso(s) que o XAML pede e o tema não define -> $($wfTemaFaltando -join ', ')" -ForegroundColor Red; $wbErrors++ }
        else { Write-Host "  Tema aplicado na janela: Claro e Escuro sem recusa, tokens novos resolvidos" }
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
        # Espelho da lista de recomendações do Diagnóstico: marcar a linha da lista tem de marcar a
        # caixa de verdade na aba de destino, e desmarcar a caixa de verdade tem de desmarcar a linha.
        # Roda ANTES do teste de "marcar recomendados" e de propósito com uma chave da aba Ajustes:
        # a aba Jogos continua desmontada aqui, então a trava seguinte ("as abas não foram montadas
        # sob demanda") não perde o dente.
        try {
            $wfEspelhos = $sync.WinForgeDiagMirrors
            if ($null -eq $wfEspelhos -or @($wfEspelhos.Keys).Count -eq 0) { throw "a lista do Diagnóstico não tem nenhuma caixa de espelho" }
            $wfEspChave = @(@($wfEspelhos.Keys) | Where-Object { (Get-WinForgeRecommendationTab -Key $_) -eq 'Tweaks' })[0]
            if (-not $wfEspChave) { throw "nenhuma recomendação da aba Ajustes para exercitar o espelho" }
            if ($sync.InitializedTabs['Tweaks']) { throw "a aba Ajustes já estava montada - o teste de montagem sob demanda não provaria nada" }
            $wfEspCaixa = $wfEspelhos[$wfEspChave]
            $wfEspCaixa.IsChecked = $true
            if (-not $sync.InitializedTabs['Tweaks']) { Write-Host "  [ERRO] espelho: a aba Ajustes não foi montada sob demanda" -ForegroundColor Red; $wbErrors++ }
            if ($sync[$wfEspChave] -isnot [System.Windows.Controls.CheckBox]) { Write-Host "  [ERRO] espelho: '$wfEspChave' não virou CheckBox depois da montagem" -ForegroundColor Red; $wbErrors++ }
            elseif (-not $sync[$wfEspChave].IsChecked) { Write-Host "  [ERRO] espelho: marcar na lista do Diagnóstico não marcou '$wfEspChave' na aba Ajustes" -ForegroundColor Red; $wbErrors++ }
            # volta: quem desmarca na aba de destino tem de apagar a marca da lista do Diagnóstico
            if ($sync[$wfEspChave] -is [System.Windows.Controls.CheckBox]) {
                $sync[$wfEspChave].IsChecked = $false
                if ($wfEspCaixa.IsChecked) { Write-Host "  [ERRO] espelho: desmarcar '$wfEspChave' na aba Ajustes não desmarcou a linha da lista" -ForegroundColor Red; $wbErrors++ }
            }
            if ($sync.WinForgeMirrorBusy) { Write-Host "  [ERRO] espelho: `$sync.WinForgeMirrorBusy ficou ligado depois do vaivém" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Espelho das recomendações: OK ('$wfEspChave' nos dois sentidos, aba Ajustes montada sob demanda)"
        } catch {
            Write-Host "  [ERRO] espelho das recomendações: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
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
            # $wfAclNomes traz as linhas de permissões que rodam com fluxo ao vivo: elas não têm
            # 'Command' e por isso ficam fora de $wfRepNomes, mas o botão delas está na mesma aba.
            $wfRepChaves = @(@($wfRepNomes + $wfAclNomes) | Sort-Object -Unique | ForEach-Object { "WPFWFRep$_" })
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
                # A cor vem do tema (RecommendedColor), não de um hexadecimal fixo: o verde do tema
                # Claro é outro. Comparar com o pincel que o tema aplicado nesta janela devolve é o
                # que mantém a trava válida nos dois temas - e ela quebra se a linha voltar a ser
                # pintada com cor fixa.
                $wfVerdeTema = [string]([System.Windows.Media.SolidColorBrush]$sync.Form.TryFindResource('RecommendedColor')).Color
                if (-not $wfVerdeTema) { Write-Host "  [ERRO] aba Servidor (contornos): o tema não define RecommendedColor" -ForegroundColor Red; $wbErrors++ }
                $wfSrvVerdes = @($wfSrvKeys | ForEach-Object { Get-WinForgeRecoRow -Key $_ } | Where-Object { $_ -and $_.Border.BorderBrush -and [string]$_.Border.BorderBrush.Color -eq $wfVerdeTema }).Count
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
                # O relatório é escrito num nome temporário e renomeado: o arquivo final nunca
                # existe pela metade, e o '.parcial' não pode ficar para trás.
                if (Test-Path -LiteralPath "$wfRelPath.parcial") { Write-Host "  [ERRO] Diagnóstico: o arquivo temporário '$wfRelPath.parcial' ficou no disco" -ForegroundColor Red; $wbErrors++ }
                # E o caminho padrão sai da API de pastas, não de $env:LocalAppData: o relatório é
                # gravado pelo motor elevado e aberto em seguida com Start-Process.
                $wfRelDef = [string]${function:Export-WinForgeDiagnosticsReport}
                if ($wfRelDef -match '\$env:LocalAppData') { Write-Host "  [ERRO] Diagnóstico: o caminho do relatório ainda vem de `$env:LocalAppData" -ForegroundColor Red; $wbErrors++ }
                if ($wfRelDef -notmatch 'Join-Path \(Get-WinForgeUserDataRoot\)') { Write-Host "  [ERRO] Diagnóstico: o caminho do relatório não vem de Get-WinForgeUserDataRoot" -ForegroundColor Red; $wbErrors++ }
                Write-Host "  Aba Diagnóstico: $wfCards cartões, $wfDrvUI drivers, $($sync.WPFDiagRecs.Items.Count) recomendações | relatório $([math]::Round($wfRelTam / 1KB)) KB"
                if (-not $env:WINFORGE_KEEP_REPORT) { Remove-Item -Path $wfRel -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            Write-Host "  [ERRO] aba Diagnóstico: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # Coluna "Ação" da tabela de drivers e coluna "Instalar" da tabela do Windows Update: as duas
        # são DataGridTemplateColumn com um Button que tira o texto da LINHA e leva a linha inteira na
        # Tag. É pela Tag que o handler sabe em que linha o usuário clicou - a tabela é redesenhada a
        # cada diagnóstico, e um índice guardado no clique apontaria para a linha da rodada anterior.
        try {
            $wfBtnColunas = @(
                @('WPFDiagDrivers', 'Ação',     'ActionLabel', 'ActionVisible'),
                @('WPFDiagWU',      'Instalar', $null,         $null)
            )
            # As duas ligações que fazem o botão dizer que precisa de elevação: 'IsEnabled' e a
            # dica. ToolTipService.ShowOnDisabled é o que falta em quase toda tela do Windows -
            # sem ele o WPF esconde a dica justamente quando o botão está desabilitado, que é o
            # único momento em que ela tem algo a explicar.
            foreach ($wfBtnCol in $wfBtnColunas) {
                $wfBtnGrade = $sync[$wfBtnCol[0]]
                $wfBtnColuna = @($wfBtnGrade.Columns | Where-Object { $_ -is [System.Windows.Controls.DataGridTemplateColumn] -and [string]$_.Header -eq [string]$wfBtnCol[1] })[0]
                if ($null -eq $wfBtnColuna) { Write-Host "  [ERRO] coluna de ação: $($wfBtnCol[0]) sem DataGridTemplateColumn '$($wfBtnCol[1])'" -ForegroundColor Red; $wbErrors++; continue }
                $wfBtnConteudo = $wfBtnColuna.CellTemplate.LoadContent()
                if ($wfBtnConteudo -isnot [System.Windows.Controls.Button]) { Write-Host "  [ERRO] coluna de ação: o modelo de '$($wfBtnCol[1])' não é um Button, é '$($wfBtnConteudo.GetType().Name)'" -ForegroundColor Red; $wbErrors++; continue }
                $wfBtnTag = [System.Windows.Data.BindingOperations]::GetBinding($wfBtnConteudo, [System.Windows.FrameworkElement]::TagProperty)
                if ($null -eq $wfBtnTag -or [string]$wfBtnTag.Path.Path -ne '') { Write-Host "  [ERRO] coluna de ação: a Tag do botão de '$($wfBtnCol[1])' não está ligada à linha inteira" -ForegroundColor Red; $wbErrors++ }
                if ($wfBtnCol[2]) {
                    $wfBtnTexto = [System.Windows.Data.BindingOperations]::GetBinding($wfBtnConteudo, [System.Windows.Controls.ContentControl]::ContentProperty)
                    if ($null -eq $wfBtnTexto -or [string]$wfBtnTexto.Path.Path -ne [string]$wfBtnCol[2]) { Write-Host "  [ERRO] coluna de ação: o texto do botão de '$($wfBtnCol[1])' não vem de $($wfBtnCol[2])" -ForegroundColor Red; $wbErrors++ }
                }
                if ($wfBtnCol[3]) {
                    $wfBtnVis = [System.Windows.Data.BindingOperations]::GetBinding($wfBtnConteudo, [System.Windows.UIElement]::VisibilityProperty)
                    if ($null -eq $wfBtnVis -or [string]$wfBtnVis.Path.Path -ne [string]$wfBtnCol[3]) { Write-Host "  [ERRO] coluna de ação: a visibilidade do botão de '$($wfBtnCol[1])' não vem de $($wfBtnCol[3])" -ForegroundColor Red; $wbErrors++ }
                }
                $wfBtnHab = [System.Windows.Data.BindingOperations]::GetBinding($wfBtnConteudo, [System.Windows.UIElement]::IsEnabledProperty)
                if ($null -eq $wfBtnHab -or [string]$wfBtnHab.Path.Path -ne 'ActionEnabled') { Write-Host "  [ERRO] coluna de ação: o botão de '$($wfBtnCol[1])' não liga IsEnabled em ActionEnabled" -ForegroundColor Red; $wbErrors++ }
                $wfBtnDica = [System.Windows.Data.BindingOperations]::GetBinding($wfBtnConteudo, [System.Windows.FrameworkElement]::ToolTipProperty)
                if ($null -eq $wfBtnDica -or [string]$wfBtnDica.Path.Path -ne 'ActionTip') { Write-Host "  [ERRO] coluna de ação: a dica do botão de '$($wfBtnCol[1])' não vem de ActionTip" -ForegroundColor Red; $wbErrors++ }
                if (-not [System.Windows.Controls.ToolTipService]::GetShowOnDisabled($wfBtnConteudo)) { Write-Host "  [ERRO] coluna de ação: a dica do botão de '$($wfBtnCol[1])' não aparece com o botão desabilitado (ToolTipService.ShowOnDisabled)" -ForegroundColor Red; $wbErrors++ }
            }
            # A tabela do Windows Update tem de carregar o id: é ele, e não o título, que identifica
            # a atualização na hora de instalar.
            $wfBtnWuAntes = $sync.DiagWUResults
            try {
                $sync.DiagWUResults = @([pscustomobject]@{ Title = 'Driver de teste - 1.2.3.4'; Driver = 'Teste'; Provider = 'WinForge'; Version = '1.2.3.4'; Date = '2026-09-10'; UpdateId = 'id-de-teste' })
                Update-WinForgeDiagnosticsWindowsUpdateGrid
                $wfBtnWuLinha = @($sync.WPFDiagWU.ItemsSource)[0]
                if ([string]$wfBtnWuLinha.UpdateId -ne 'id-de-teste') { Write-Host "  [ERRO] tabela do Windows Update: a linha não carrega o UpdateId (veio '$($wfBtnWuLinha.UpdateId)')" -ForegroundColor Red; $wbErrors++ }
                # Duas ofertas da MESMA placa: a tabela mostra só a mais nova, o rótulo conta as que
                # ficaram de fora e a dica diz QUAIS - sem ela, a linha sumida seria um mistério.
                $sync.DiagWUResults = @(
                    [pscustomobject]@{ Title = 'Intel Corporation Display Driver Update (32.0.101.7088)'; Driver = 'Intel(R) Iris(R) Xe Graphics'; Provider = 'Intel Corporation'; Version = '32.0.101.7088'; Date = '2026-09-01'; UpdateId = 'wu-novo' },
                    [pscustomobject]@{ Title = 'Intel Corporation Display Driver Update (32.0.101.7085)'; Driver = 'Intel(R) Iris(R) Xe Graphics'; Provider = 'Intel Corporation'; Version = '32.0.101.7085'; Date = '2026-08-01'; UpdateId = 'wu-velho' }
                )
                Update-WinForgeDiagnosticsWindowsUpdateGrid
                $wfBtnWuVisiveis = @($sync.WPFDiagWU.ItemsSource)
                if ($wfBtnWuVisiveis.Count -ne 1) { Write-Host "  [ERRO] tabela do Windows Update: $($wfBtnWuVisiveis.Count) linha(s) na tela, esperado 1 (mesma placa)" -ForegroundColor Red; $wbErrors++ }
                elseif ([string]$wfBtnWuVisiveis[0].UpdateId -ne 'wu-novo') { Write-Host "  [ERRO] tabela do Windows Update: sobrou '$($wfBtnWuVisiveis[0].UpdateId)', esperado 'wu-novo'" -ForegroundColor Red; $wbErrors++ }
                elseif ([string]$wfBtnWuVisiveis[0].Version -ne '32.0.101.7088') { Write-Host "  [ERRO] tabela do Windows Update: a coluna Versão veio '$($wfBtnWuVisiveis[0].Version)'" -ForegroundColor Red; $wbErrors++ }
                $wfBtnWuRotulo = 'Drivers oferecidos pelo Windows Update (1) · 1 versão(ões) mais antiga(s) oculta(s)'
                if ([string]$sync.WPFDiagWULabel.Text -ne $wfBtnWuRotulo) { Write-Host "  [ERRO] rótulo do Windows Update: veio '$($sync.WPFDiagWULabel.Text)', esperado '$wfBtnWuRotulo'" -ForegroundColor Red; $wbErrors++ }
                if ([string]$sync.WPFDiagWULabel.ToolTip -notlike '*32.0.101.7085*') { Write-Host "  [ERRO] rótulo do Windows Update: a dica não lista o título oculto (veio '$($sync.WPFDiagWULabel.ToolTip)')" -ForegroundColor Red; $wbErrors++ }
                # O que mudou foi a VISTA, não o que dá para instalar: o objeto COM da oferta antiga
                # continua no cache, indexado pelo id.
                # Nada oculto: nem sufixo no rótulo, nem dica pendurada da passada anterior.
                $sync.DiagWUResults = @([pscustomobject]@{ Title = 'Driver de teste - 1.2.3.4'; Driver = 'Teste'; Provider = 'WinForge'; Version = '1.2.3.4'; Date = '2026-09-10'; UpdateId = 'id-de-teste' })
                Update-WinForgeDiagnosticsWindowsUpdateGrid
                if ([string]$sync.WPFDiagWULabel.Text -ne 'Drivers oferecidos pelo Windows Update (1)') { Write-Host "  [ERRO] rótulo do Windows Update: sem nada oculto ele veio '$($sync.WPFDiagWULabel.Text)'" -ForegroundColor Red; $wbErrors++ }
                if ($null -ne $sync.WPFDiagWULabel.ToolTip) { Write-Host "  [ERRO] rótulo do Windows Update: a dica da passada anterior ficou pendurada ('$($sync.WPFDiagWULabel.ToolTip)')" -ForegroundColor Red; $wbErrors++ }            } finally {
                $sync.DiagWUResults = $wfBtnWuAntes
                Update-WinForgeDiagnosticsWindowsUpdateGrid
            }
            # O clique: um handler por tabela, registrado UMA vez em Initialize-WinForgeDiagnosticsTab.
            # A linha 'none' não faz nada e prova o caminho; a linha 'vendor-page' prova a trava - em
            # SelfTest nada abre, nem navegador nem caixa de mensagem.
            if (-not $sync.WinForgeDiagActionHandlerWired) { Write-Host "  [ERRO] clique de ação: `$sync.WinForgeDiagActionHandlerWired não foi ligado por Initialize-WinForgeDiagnosticsTab" -ForegroundColor Red; $wbErrors++ }
            $wfBtnCliques = @(
                @('none',        ([pscustomobject]@{ Device = 'x'; ActionKind = 'none'; ActionLabel = ''; ActionUrl = $null }),                                              'none'),
                @('vendor-page', ([pscustomobject]@{ Device = 'x'; ActionKind = 'vendor-page'; ActionLabel = 'Página do fabricante'; ActionUrl = 'https://www.amd.com/' }), 'erro')
            )
            foreach ($wfBtnClique in $wfBtnCliques) {
                $sync.LastDriverAction = $null
                $wfBtnFalso = New-Object System.Windows.Controls.Button
                $wfBtnFalso.Tag = $wfBtnClique[1]
                $wfBtnArgs = New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent), $wfBtnFalso
                $sync.WPFDiagDrivers.RaiseEvent($wfBtnArgs)
                if ([string]$wfBtnClique[2] -eq 'none') {
                    if ([string]$sync.LastDriverAction -ne 'none') { Write-Host "  [ERRO] clique de ação: linha sem ação deveria dar 'none', deu '$($sync.LastDriverAction)'" -ForegroundColor Red; $wbErrors++ }
                } else {
                    if ([string]$sync.LastDriverAction -notmatch 'SelfTest') { Write-Host "  [ERRO] clique de ação: a linha 'vendor-page' deveria ser recusada em SelfTest, deu '$($sync.LastDriverAction)'" -ForegroundColor Red; $wbErrors++ }
                }
            }
            # Botão sem Tag (o clique em qualquer outro botão que porventura caia na tabela) não pode
            # virar ação nenhuma.
            $sync.LastDriverAction = 'nao-mexer'
            $wfBtnSemTag = New-Object System.Windows.Controls.Button
            $sync.WPFDiagDrivers.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent), $wfBtnSemTag))
            if ([string]$sync.LastDriverAction -ne 'nao-mexer') { Write-Host "  [ERRO] clique de ação: botão sem Tag disparou a ação '$($sync.LastDriverAction)'" -ForegroundColor Red; $wbErrors++ }
            # A tabela do Windows Update tem handler próprio, e ele também recusa em SelfTest.
            $sync.LastDriverAction = $null
            $wfBtnWu = New-Object System.Windows.Controls.Button
            $wfBtnWu.Tag = [pscustomobject]@{ Title = 'Driver de teste'; UpdateId = 'id-de-teste' }
            $sync.WPFDiagWU.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent), $wfBtnWu))
            if ([string]$sync.LastDriverAction -notmatch 'SelfTest') { Write-Host "  [ERRO] clique de ação: o botão Instalar do Windows Update deveria ser recusado em SelfTest, deu '$($sync.LastDriverAction)'" -ForegroundColor Red; $wbErrors++ }
            # Nenhuma das duas tabelas pode escrever RowBackground: o valor é coagido para
            # DataGridRow.Background com precedência Local, que vence o Setter e o gatilho de
            # IsMouseOver do estilo. Com ele, o realce do mouse existia no XAML e nunca aparecia.
            foreach ($wfGradeNome in @('WPFDiagDrivers', 'WPFDiagWU')) {
                $wfGradeFonte = [System.Windows.DependencyPropertyHelper]::GetValueSource($sync[$wfGradeNome], [System.Windows.Controls.DataGrid]::RowBackgroundProperty).BaseValueSource
                if ([string]$wfGradeFonte -eq 'Local') { Write-Host "  [ERRO] realce da linha: $wfGradeNome tem RowBackground local, que mata o gatilho de IsMouseOver do estilo" -ForegroundColor Red; $wbErrors++ }
            }
            Write-Host "  Colunas de ação: 'Ação' e 'Instalar' com Button ligado à linha; clique roteado pelas duas tabelas e recusado em SelfTest | sem RowBackground local nas duas tabelas"
        } catch {
            Write-Host "  [ERRO] colunas de ação: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # ---------------------------------------------------------------- botões que exigem elevação
        # Sem elevação a pasta de downloads é recusada (ela é de SYSTEM/Administradores) e o Windows
        # Update não instala nada. Um botão que só descobre isso DEPOIS do clique é uma promessa
        # quebrada: ele nasce desabilitado, com a dica dizendo o que falta.
        try {
            $wfElevado = [bool](Test-WinForgeRepairElevated)
            $wfElevDica = 'Precisa de elevação (execute o WinForge como administrador)'
            $wfElevLinhas = @((Get-WinForgeDiagDriverRows -Profile @{ Drivers = @(
                [pscustomobject]@{ Device = 'NVIDIA GeForce RTX 3070'; Vendor = 'nvidia'; Class = 'DISPLAY'; Status = 'atualizar'; Latest = '616.92'; LatestUrl = 'https://us.download.nvidia.com/Windows/616.92/x.exe'; Url = 'https://www.nvidia.com/pt-br/drivers/' },
                [pscustomobject]@{ Device = 'AMD Radeon'; Vendor = 'amd'; Class = 'DISPLAY'; Status = 'verificar'; Url = 'https://www.amd.com/pt/support/download/drivers.html' }
            ) }) | ForEach-Object { $_ })
            $wfElevNv = $wfElevLinhas[0]
            $wfElevAmd = $wfElevLinhas[1]
            if ([bool]$wfElevNv.ActionEnabled -ne $wfElevado) { Write-Host "  [ERRO] botão sem elevação: 'Baixar' deveria estar $(if ($wfElevado) { 'habilitado' } else { 'desabilitado' }), veio ActionEnabled '$($wfElevNv.ActionEnabled)'" -ForegroundColor Red; $wbErrors++ }
            if (-not $wfElevado -and [string]$wfElevNv.ActionTip -ne $wfElevDica) { Write-Host "  [ERRO] botão sem elevação: a dica do 'Baixar' deveria ser '$wfElevDica', veio '$($wfElevNv.ActionTip)'" -ForegroundColor Red; $wbErrors++ }
            if ($wfElevado -and [string]$wfElevNv.ActionTip -eq $wfElevDica) { Write-Host "  [ERRO] botão sem elevação: com elevação a dica não pode ser a de elevação" -ForegroundColor Red; $wbErrors++ }
            # Abrir a página do fabricante é o navegador do usuário: não precisa de elevação nenhuma.
            if (-not $wfElevAmd.ActionEnabled) { Write-Host "  [ERRO] botão sem elevação: 'Página do fabricante' não depende de elevação e não pode nascer desabilitado" -ForegroundColor Red; $wbErrors++ }
            # E o 'Instalar' do Windows Update segue a mesma regra.
            $wfElevWuAntes = $sync.DiagWUResults
            try {
                $sync.DiagWUResults = @([pscustomobject]@{ Title = 'Driver de teste - 1.2.3.4'; Driver = 'Teste'; Provider = 'WinForge'; Version = '1.2.3.4'; Date = '2026-09-10'; UpdateId = 'id-de-teste' })
                Update-WinForgeDiagnosticsWindowsUpdateGrid
                $wfElevWu = @($sync.WPFDiagWU.ItemsSource)[0]
                if ([bool]$wfElevWu.ActionEnabled -ne $wfElevado) { Write-Host "  [ERRO] botão sem elevação: 'Instalar' do Windows Update veio ActionEnabled '$($wfElevWu.ActionEnabled)'" -ForegroundColor Red; $wbErrors++ }
                if (-not $wfElevado -and [string]$wfElevWu.ActionTip -ne $wfElevDica) { Write-Host "  [ERRO] botão sem elevação: a dica do 'Instalar' deveria ser '$wfElevDica', veio '$($wfElevWu.ActionTip)'" -ForegroundColor Red; $wbErrors++ }
            } finally {
                $sync.DiagWUResults = $wfElevWuAntes
                Update-WinForgeDiagnosticsWindowsUpdateGrid
            }
            Write-Host "  Botões que exigem elevação: este build roda $(if ($wfElevado) { 'ELEVADO' } else { 'SEM elevação' }) - 'Baixar' e 'Instalar' $(if ($wfElevado) { 'habilitados' } else { 'desabilitados, com a dica de elevação' })"
        } catch {
            Write-Host "  [ERRO] botões que exigem elevação: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # Estado de instalação na tabela do Windows Update. A queixa era direta: depois de instalar um
        # driver a tabela continuava idêntica - mesmo botão, mesma linha -, e não havia como saber se
        # tinha dado certo. Agora o estado da SESSÃO mora em $sync.DiagWUState (por id da atualização),
        # a coluna "Situação" diz em palavras e o fundo da linha diz em cor.
        # NADA aqui instala coisa alguma: todo estado é escrito à mão e desfeito no fim.
        $wfWuEstAntes = $sync.DiagWUResults
        $wfWuEstMapa = $sync.DiagWUState
        $wfWuEstElevSalvo = ${function:Test-WinForgeRepairElevated}
        try {
            $sync.DiagWUState = @{}
            # A elevação é forçada para $true enquanto este bloco roda, e devolvida no finally. Sem
            # isso o teste não prova nada numa máquina sem elevação: lá TODO botão já nasce
            # desabilitado, e "desabilitado porque já está instalado" ficaria indistinguível de
            # "desabilitado porque falta elevação" - que é exatamente a confusão que ele existe para
            # pegar. A troca é da FUNÇÃO, e não um parâmetro novo: a tabela não precisa de uma porta
            # de teste no código de produção para ser conferida.
            ${function:Test-WinForgeRepairElevated} = { return $true }
            $wfWuEstElevado = $true
            $sync.DiagWUResults = @(
                [pscustomobject]@{ Title = 'Driver de teste A'; Driver = 'A'; Provider = 'WinForge'; Version = '1.0'; Date = '2026-09-10'; UpdateId = 'wu-a' },
                [pscustomobject]@{ Title = 'Driver de teste B'; Driver = 'B'; Provider = 'WinForge'; Version = '1.0'; Date = '2026-09-10'; UpdateId = 'wu-b' },
                [pscustomobject]@{ Title = 'Driver de teste C'; Driver = 'C'; Provider = 'WinForge'; Version = '1.0'; Date = '2026-09-10'; UpdateId = 'wu-c' },
                [pscustomobject]@{ Title = 'Driver de teste D'; Driver = 'D'; Provider = 'WinForge'; Version = '1.0'; Date = '2026-09-10'; UpdateId = 'wu-d' }
            )
            # Texto solto no mapa vale como estado sem detalhe - é o formato mais fácil de escrever
            # errado, e é por isso que ele é aceito aqui em vez de estourar.
            $sync.DiagWUState['wu-a'] = 'instalado'
            $sync.DiagWUState['wu-b'] = @{ State = 'instalado'; Text = 'instalado (reinicie)' }
            $sync.DiagWUState['wu-c'] = @{ State = 'falhou'; Text = 'falhou (código 4)' }
            $sync.DiagWUState['wu-d'] = @{ State = 'instalando'; Text = 'instalando...' }
            Update-WinForgeDiagnosticsWindowsUpdateGrid
            $wfWuEstLinhas = @{}
            foreach ($wfWuEstL in @($sync.WPFDiagWU.ItemsSource)) { $wfWuEstLinhas[[string]$wfWuEstL.UpdateId] = $wfWuEstL }
            # Instalado e instalando não podem ser clicados de novo; falhou pode - é a hora de tentar
            # outra vez, e a única coisa que ainda barra o botão é a falta de elevação.
            foreach ($wfWuEstE in @(
                @('wu-a', 'instalado',  'instalado',            $false),
                @('wu-b', 'instalado',  'instalado (reinicie)', $false),
                @('wu-c', 'falhou',     'falhou (código 4)',    $wfWuEstElevado),
                @('wu-d', 'instalando', 'instalando...',        $false)
            )) {
                $wfWuEstLinha = $wfWuEstLinhas[[string]$wfWuEstE[0]]
                if ($null -eq $wfWuEstLinha) { Write-Host "  [ERRO] estado do Windows Update: a linha '$($wfWuEstE[0])' sumiu da tabela" -ForegroundColor Red; $wbErrors++; continue }
                if ([string]$wfWuEstLinha.State -ne [string]$wfWuEstE[1]) { Write-Host "  [ERRO] estado do Windows Update: '$($wfWuEstE[0])' veio State '$($wfWuEstLinha.State)', esperado '$($wfWuEstE[1])'" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wfWuEstLinha.StatusText -ne [string]$wfWuEstE[2]) { Write-Host "  [ERRO] estado do Windows Update: '$($wfWuEstE[0])' veio StatusText '$($wfWuEstLinha.StatusText)', esperado '$($wfWuEstE[2])'" -ForegroundColor Red; $wbErrors++ }
                if ([bool]$wfWuEstLinha.ActionEnabled -ne [bool]$wfWuEstE[3]) { Write-Host "  [ERRO] estado do Windows Update: '$($wfWuEstE[0])' veio ActionEnabled '$($wfWuEstLinha.ActionEnabled)', esperado '$([bool]$wfWuEstE[3])'" -ForegroundColor Red; $wbErrors++ }
            }
            # Linha sem estado nenhum: pendente, sem texto na coluna e botão preso só à elevação.
            $sync.DiagWUState = @{}
            Update-WinForgeDiagnosticsWindowsUpdateGrid
            $wfWuEstPend = @($sync.WPFDiagWU.ItemsSource)[0]
            if ([string]$wfWuEstPend.State -ne 'pendente') { Write-Host "  [ERRO] estado do Windows Update: linha sem estado veio '$($wfWuEstPend.State)', esperado 'pendente'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfWuEstPend.StatusText -ne '') { Write-Host "  [ERRO] estado do Windows Update: linha pendente deveria ter a coluna Situação vazia, veio '$($wfWuEstPend.StatusText)'" -ForegroundColor Red; $wbErrors++ }
            if ([bool]$wfWuEstPend.ActionEnabled -ne $wfWuEstElevado) { Write-Host "  [ERRO] estado do Windows Update: linha pendente veio ActionEnabled '$($wfWuEstPend.ActionEnabled)', esperado '$wfWuEstElevado'" -ForegroundColor Red; $wbErrors++ }
            # O resultado do serviço COM vira estado: 2 e 3 são sucesso (3 é "com avisos"), o resto é
            # falha. O código entra no texto porque é ele que o usuário tem para pesquisar.
            foreach ($wfWuEstRes in @(
                @(2,  $false, 'instalado', 'instalado'),
                @(2,  $true,  'instalado', 'instalado (reinicie)'),
                @(3,  $false, 'instalado', 'instalado'),
                @(4,  $false, 'falhou',    'falhou (código 4)'),
                @(-1, $false, 'falhou',    'falhou')
            )) {
                $wfWuEstR = Set-WinForgeWindowsUpdateInstallResult -UpdateId 'wu-a' -ResultCode ([int]$wfWuEstRes[0]) -RebootRequired ([bool]$wfWuEstRes[1])
                if ([string]$wfWuEstR.State -ne [string]$wfWuEstRes[2]) { Write-Host "  [ERRO] resultado do Windows Update: código $($wfWuEstRes[0]) virou State '$($wfWuEstR.State)', esperado '$($wfWuEstRes[2])'" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wfWuEstR.Text -ne [string]$wfWuEstRes[3]) { Write-Host "  [ERRO] resultado do Windows Update: código $($wfWuEstRes[0]) virou Text '$($wfWuEstR.Text)', esperado '$($wfWuEstRes[3])'" -ForegroundColor Red; $wbErrors++ }
                if ([string]$sync.DiagWUState['wu-a'].State -ne [string]$wfWuEstRes[2]) { Write-Host "  [ERRO] resultado do Windows Update: o mapa da sessão não guardou o estado do código $($wfWuEstRes[0])" -ForegroundColor Red; $wbErrors++ }
            }
            # A ação recusa linha já instalada, e -NoUI nunca instala nem mexe no mapa.
            $sync.DiagWUState = @{}
            $sync.DiagWUState['wu-a'] = 'instalado'
            Update-WinForgeDiagnosticsWindowsUpdateGrid
            $wfWuEstA = @(@($sync.WPFDiagWU.ItemsSource) | Where-Object { [string]$_.UpdateId -eq 'wu-a' })[0]
            $wfWuEstB = @(@($sync.WPFDiagWU.ItemsSource) | Where-Object { [string]$_.UpdateId -eq 'wu-b' })[0]
            $wfWuEstAcaoA = [string](Invoke-WinForgeWindowsUpdateAction -Row $wfWuEstA -NoUI)
            if ($wfWuEstAcaoA -ne 'já instalado') { Write-Host "  [ERRO] ação do Windows Update: linha já instalada deveria dar 'já instalado', deu '$wfWuEstAcaoA'" -ForegroundColor Red; $wbErrors++ }
            $wfWuEstAcaoB = [string](Invoke-WinForgeWindowsUpdateAction -Row $wfWuEstB -NoUI)
            if ($wfWuEstAcaoB -ne 'pendente') { Write-Host "  [ERRO] ação do Windows Update: -NoUI numa linha pendente deveria dar 'pendente', deu '$wfWuEstAcaoB'" -ForegroundColor Red; $wbErrors++ }
            if ($sync.DiagWUState.ContainsKey('wu-b')) { Write-Host "  [ERRO] ação do Windows Update: -NoUI escreveu estado para 'wu-b' - a simulação não pode mexer no mapa" -ForegroundColor Red; $wbErrors++ }
            # A coluna "Situação" é o mesmo texto, em palavras: a cor sozinha não serve a quem não a
            # distingue, e ela é a única parte da linha que sobrevive a uma captura de tela em cinza.
            $wfWuEstCol = @($sync.WPFDiagWU.Columns | Where-Object { [string]$_.Header -eq 'Situação' })[0]
            if ($null -eq $wfWuEstCol) { Write-Host "  [ERRO] tabela do Windows Update: falta a coluna 'Situação'" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfWuEstCol.Binding.Path.Path -ne 'StatusText') { Write-Host "  [ERRO] tabela do Windows Update: a coluna 'Situação' liga em '$($wfWuEstCol.Binding.Path.Path)', esperado 'StatusText'" -ForegroundColor Red; $wbErrors++ }
            # O fundo da linha. O estilo é PRÓPRIO da tabela do Windows Update (a de drivers não tem
            # estado de instalação) e herda o DataGridRow da janela - sem o BasedOn a linha perderia
            # altura, cor de texto e o realce do mouse.
            $wfWuEstEstilo = $sync.WPFDiagWU.RowStyle
            if ($null -eq $wfWuEstEstilo) { Write-Host "  [ERRO] fundo da linha: a tabela do Windows Update não tem RowStyle" -ForegroundColor Red; $wbErrors++ }
            else {
                if ($null -eq $wfWuEstEstilo.BasedOn) { Write-Host "  [ERRO] fundo da linha: o RowStyle da tabela do Windows Update não herda o estilo DataGridRow da janela" -ForegroundColor Red; $wbErrors++ }
                foreach ($wfWuEstPar in @(@('instalado', 'RowSuccessBackgroundColor'), @('falhou', 'RowFailureBackgroundColor'))) {
                    $wfWuEstTrig = @(@($wfWuEstEstilo.Triggers) | Where-Object { $_ -is [System.Windows.DataTrigger] -and [string]$_.Binding.Path.Path -eq 'State' -and [string]$_.Value -eq [string]$wfWuEstPar[0] })[0]
                    if ($null -eq $wfWuEstTrig) { Write-Host "  [ERRO] fundo da linha: sem gatilho para State='$($wfWuEstPar[0])'" -ForegroundColor Red; $wbErrors++; continue }
                    $wfWuEstSet = @(@($wfWuEstTrig.Setters) | Where-Object { $_.Property -eq [System.Windows.Controls.Control]::BackgroundProperty })[0]
                    if ($null -eq $wfWuEstSet) { Write-Host "  [ERRO] fundo da linha: o gatilho de '$($wfWuEstPar[0])' não pinta o Background" -ForegroundColor Red; $wbErrors++ }
                    elseif ([string]$wfWuEstSet.Value.ResourceKey -ne [string]$wfWuEstPar[1]) { Write-Host "  [ERRO] fundo da linha: o gatilho de '$($wfWuEstPar[0])' usa '$($wfWuEstSet.Value.ResourceKey)', esperado o recurso dinâmico '$($wfWuEstPar[1])'" -ForegroundColor Red; $wbErrors++ }
                    if ($sync.Form -and $sync.Form.TryFindResource($wfWuEstPar[1]) -isnot [System.Windows.Media.SolidColorBrush]) { Write-Host "  [ERRO] fundo da linha: '$($wfWuEstPar[1])' não chegou ao dicionário da janela como pincel" -ForegroundColor Red; $wbErrors++ }
                }
            }
            Write-Host "  Estado na tabela do Windows Update: pendente/instalando/instalado/falhou por id, coluna 'Situação', fundo verde e vermelho por gatilho, botão preso ao estado"
        } catch {
            Write-Host "  [ERRO] estado do Windows Update: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        } finally {
            ${function:Test-WinForgeRepairElevated} = $wfWuEstElevSalvo
            $sync.DiagWUState = $(if ($null -eq $wfWuEstMapa) { @{} } else { $wfWuEstMapa })
            $sync.DiagWUResults = $wfWuEstAntes
            Update-WinForgeDiagnosticsWindowsUpdateGrid
        }
        # Checklist das recomendações + contador na tela. Uma linha por recomendação, e caixa de
        # marcar só nas que a aba de destino aceita marcar: Toggle aplica o tweak no clique, e
        # recomendação não muda o sistema (mesma regra de Select-WinForgeRecommended).
        try {
            # A conta esperada NÃO passa por Test-WinForgeRecommendationToggle: usar a mesma função
            # que o checklist usa faria a trava concordar consigo mesma. A regra é escrita aqui do
            # mesmo jeito que Select-WinForgeRecommended a escreve.
            $wfChkEsperado = @(@($sync.Recommended.Keys) | Where-Object { $_ -and $sync.configs.tweaks.PSObject.Properties[$_] -and $_ -notlike 'WPFToggle*' -and [string]$sync.configs.tweaks.$_.Type -ne 'Toggle' }).Count
            $wfChkCaixas = 0
            foreach ($wfLinha in @($sync.WPFDiagRecs.Items)) {
                foreach ($wfFilho in @($wfLinha.Children)) { if ($wfFilho -is [System.Windows.Controls.CheckBox]) { $wfChkCaixas++ } }
            }
            if ($wfChkCaixas -ne $wfChkEsperado) { Write-Host "  [ERRO] checklist: $wfChkCaixas caixa(s) na lista do Diagnóstico, esperado $wfChkEsperado" -ForegroundColor Red; $wbErrors++ }
            if (@($sync.WinForgeDiagMirrors.Keys).Count -ne $wfChkEsperado) { Write-Host "  [ERRO] checklist: $(@($sync.WinForgeDiagMirrors.Keys).Count) espelho(s) registrado(s), esperado $wfChkEsperado" -ForegroundColor Red; $wbErrors++ }
            # "Marcar todos" / "Desmarcar todos": sem caixa de mensagem, com o contador na tela.
            # A limpeza antes do "Marcar todos" deixa a conta determinística: as linhas já aplicadas
            # ficam de fora da marcação em massa, e uma delas marcada de antes faria o N do contador
            # passar do que a função devolve.
            $null = Set-WinForgeDiagRecommendationSelection -Checked $false
            $wfChkAplicados = 0
            foreach ($wfChkK in @($sync.WinForgeDiagMirrors.Keys)) {
                if ($sync.WinForgeDiagMirrors[$wfChkK].IsEnabled -and (Test-WinForgeDiagRecApplied -Key $wfChkK)) { $wfChkAplicados++ }
            }
            $wfChkTodos = Set-WinForgeDiagRecommendationSelection -Checked $true
            if ($sync.WPFDiagRecCount.Text -notmatch '^\d+ de \d+ recomendados marcados · \d+ já aplicados$') { Write-Host "  [ERRO] contador: texto '$($sync.WPFDiagRecCount.Text)' fora do formato 'N de M recomendados marcados · A já aplicados'" -ForegroundColor Red; $wbErrors++ }
            if ($sync.WPFDiagRecCount.Text -ne "$wfChkTodos de $wfChkEsperado recomendados marcados · $wfChkAplicados já aplicados") { Write-Host "  [ERRO] contador depois de Marcar todos: '$($sync.WPFDiagRecCount.Text)', esperado '$wfChkTodos de $wfChkEsperado recomendados marcados · $wfChkAplicados já aplicados'" -ForegroundColor Red; $wbErrors++ }
            if ($wfChkTodos -ne ($wfChkEsperado - $wfChkAplicados)) { Write-Host "  [ERRO] Marcar todos: marcou $wfChkTodos linha(s), esperado $($wfChkEsperado - $wfChkAplicados) ($wfChkEsperado menos $wfChkAplicados já aplicada(s))" -ForegroundColor Red; $wbErrors++ }
            $wfChkMarcadosReais = @(@($sync.WinForgeDiagMirrors.Keys) | Where-Object { $sync[$_] -is [System.Windows.Controls.CheckBox] -and $sync[$_].IsChecked }).Count
            if ($wfChkMarcadosReais -ne $wfChkTodos) { Write-Host "  [ERRO] Marcar todos: $wfChkMarcadosReais caixa(s) real(is) marcada(s), esperado $wfChkTodos" -ForegroundColor Red; $wbErrors++ }
            $null = Set-WinForgeDiagRecommendationSelection -Checked $false
            if ($sync.WPFDiagRecCount.Text -ne "0 de $wfChkEsperado recomendados marcados · $wfChkAplicados já aplicados") { Write-Host "  [ERRO] contador depois de Desmarcar todos: '$($sync.WPFDiagRecCount.Text)'" -ForegroundColor Red; $wbErrors++ }
            $wfChkSobraram = @(@($sync.WinForgeDiagMirrors.Keys) | Where-Object { $sync[$_] -is [System.Windows.Controls.CheckBox] -and $sync[$_].IsChecked })
            if ($wfChkSobraram.Count) { Write-Host "  [ERRO] Desmarcar todos: continuam marcadas: $($wfChkSobraram -join ', ')" -ForegroundColor Red; $wbErrors++ }
            if ($sync.WinForgeMirrorBusy) { Write-Host "  [ERRO] checklist: `$sync.WinForgeMirrorBusy ficou ligado" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Checklist do Diagnóstico: $wfChkCaixas caixa(s), Marcar todos = $wfChkTodos, contador '$($sync.WPFDiagRecCount.Text)'"
        } catch {
            Write-Host "  [ERRO] checklist do Diagnóstico: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # "Aplicar marcados" / "Desfazer marcados": a lista do Diagnóstico deixou de ser só leitura.
        # Os dois botões NÃO têm caminho próprio de aplicação - eles chamam o mesmo
        # Invoke-WPFtweaksbutton / Invoke-WPFundoall da aba Ajustes, que leem $sync.selectedTweaks.
        # Por isso o que se prova aqui é a PONTE: marcar pela lista enche selectedTweaks, desmarcar
        # esvazia, e o switch dos botões manda para as funções da base (nada de caminho paralelo).
        try {
            if ([string]$sync.WPFDiagApplySelected.Content -ne 'Aplicar marcados') { Write-Host "  [ERRO] Diagnóstico: WPFDiagApplySelected deveria dizer 'Aplicar marcados', diz '$($sync.WPFDiagApplySelected.Content)'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$sync.WPFDiagUndoSelected.Content -ne 'Desfazer marcados') { Write-Host "  [ERRO] Diagnóstico: WPFDiagUndoSelected deveria dizer 'Desfazer marcados', diz '$($sync.WPFDiagUndoSelected.Content)'" -ForegroundColor Red; $wbErrors++ }
            $wfAplDef = [string](Get-Command Invoke-WPFButton).ScriptBlock
            foreach ($wfAplCaso in '"WPFDiagApplySelected" {Invoke-WPFtweaksbutton}', '"WPFDiagUndoSelected" {Invoke-WPFundoall}') {
                if ($wfAplDef.IndexOf($wfAplCaso, [System.StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] Diagnóstico: o switch de botões não tem o caso $wfAplCaso" -ForegroundColor Red; $wbErrors++ }
            }
            # A prova de que a base vai enxergar os itens: marcar pela lista tem de encher
            # $sync.selectedTweaks, que é literalmente a variável que Invoke-WPFtweaksbutton lê.
            $null = Set-WinForgeDiagRecommendationSelection -Checked $true
            # Chave já aplicada fica de fora do "Marcar todos" e, por isso, de selectedTweaks: é o
            # comportamento novo, não uma falha da ponte (ver o bloco "estado já aplicado" abaixo).
            $wfAplChaves = @(@($sync.WinForgeDiagMirrors.Keys) | Where-Object { $_ -like 'WPFTweaks*' -and $sync.WinForgeDiagMirrors[$_].IsEnabled -and -not (Test-WinForgeDiagRecApplied -Key $_) })
            if ($wfAplChaves.Count -eq 0) { Write-Host "  [ERRO] Aplicar marcados: nenhuma chave marcável na lista do Diagnóstico - o teste não provaria nada" -ForegroundColor Red; $wbErrors++ }
            $wfAplFora = @($wfAplChaves | Where-Object { -not $sync.selectedTweaks.Contains($_) })
            if ($wfAplFora.Count) { Write-Host "  [ERRO] Aplicar marcados: $($wfAplFora.Count) chave(s) da lista ficaram fora de selectedTweaks: $($wfAplFora -join ', ')" -ForegroundColor Red; $wbErrors++ }
            $null = Set-WinForgeDiagRecommendationSelection -Checked $false
            $wfAplSobra = @($wfAplChaves | Where-Object { $sync.selectedTweaks.Contains($_) })
            if ($wfAplSobra.Count) { Write-Host "  [ERRO] Desfazer marcados: $($wfAplSobra -join ', ') continuaram em selectedTweaks depois de desmarcar tudo" -ForegroundColor Red; $wbErrors++ }
            # Trabalho em andamento desabilita os dois: o caminho da base recusa com uma caixa de
            # mensagem, e o botão morto é esse aviso dado ANTES do clique.
            $sync.ProcessRunning = $true
            Update-WinForgeDiagRecommendationCount
            if ($sync.WPFDiagApplySelected.IsEnabled -or $sync.WPFDiagUndoSelected.IsEnabled) { Write-Host "  [ERRO] Aplicar/Desfazer marcados: continuaram habilitados com `$sync.ProcessRunning ligado" -ForegroundColor Red; $wbErrors++ }
            $sync.ProcessRunning = $false
            Update-WinForgeDiagRecommendationCount
            if (-not $sync.WPFDiagApplySelected.IsEnabled -or -not $sync.WPFDiagUndoSelected.IsEnabled) { Write-Host "  [ERRO] Aplicar/Desfazer marcados: não voltaram a ficar habilitados com o trabalho terminado" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Aplicar/Desfazer marcados: $($wfAplChaves.Count) chave(s) da lista entram e saem de selectedTweaks; botões seguem `$sync.ProcessRunning"
        } catch {
            Write-Host "  [ERRO] Aplicar/Desfazer marcados: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        } finally {
            $sync.ProcessRunning = $false
        }
        # Estado já aplicado. A queixa era que remarcar uma flag já ativa reaplicava tudo de novo:
        # agora o detector da base alimenta um conjunto, a linha ganha " · aplicado" e o botão
        # Aplicar não passa essas chaves adiante. NADA aqui aplica coisa alguma - a detecção é
        # leitura de registro e de serviço, e o conjunto sintético dos testes é desfeito no fim.
        try {
            # Matriz quando a detecção funciona; $null quando ela falha (e aí quem chama tem de
            # manter o que já sabia, que é o teste da falha simulada mais abaixo).
            $wfAplDetectado = Get-WinForgeAppliedTweaks
            if ($null -ne $wfAplDetectado -and $wfAplDetectado -isnot [array]) { Write-Host "  [ERRO] aplicados: Get-WinForgeAppliedTweaks devolveu '$($wfAplDetectado.GetType().Name)', esperado matriz ou `$null" -ForegroundColor Red; $wbErrors++ }
            $wfAplForaConfig = @(@($wfAplDetectado) | Where-Object { $_ -and -not $sync.configs.tweaks.PSObject.Properties[[string]$_] })
            if ($wfAplForaConfig.Count) { Write-Host "  [ERRO] aplicados: chave(s) fora de configs.tweaks -> $($wfAplForaConfig -join ', ')" -ForegroundColor Red; $wbErrors++ }

            # Duas chaves com linha de verdade na aba Ajustes, para o teste não depender do que esta
            # máquina por acaso já tenha aplicado.
            $wfAplCand = @(@($sync.configs.tweaks.PSObject.Properties.Name) | Where-Object { $_ -like 'WPFTweaks*' -and (Test-WinForgeAppliedEligible -Key $_) -and $null -ne (Get-WinForgeRecoRow -Key $_) })
            if ($wfAplCand.Count -lt 3) { throw "menos de 3 linhas montadas na aba Ajustes ($($wfAplCand.Count)) - o teste não provaria nada" }
            $wfAplFake = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $null = $wfAplFake.Add($wfAplCand[0])
            $null = $wfAplFake.Add($wfAplCand[1])

            # O seletor: o ponto de restauração passa sempre, a chave aplicada fica de fora e a que
            # não está aplicada passa.
            $wfAplSel = Select-WinForgeTweaksToApply -Keys @('WPFTweaksRestorePoint', $wfAplCand[0], $wfAplCand[2]) -Applied $wfAplFake
            if (@($wfAplSel.Apply) -join ',' -ne "WPFTweaksRestorePoint,$($wfAplCand[2])") { Write-Host "  [ERRO] seletor: Apply veio '$(@($wfAplSel.Apply) -join ', ')', esperado 'WPFTweaksRestorePoint, $($wfAplCand[2])'" -ForegroundColor Red; $wbErrors++ }
            if (@($wfAplSel.Skipped) -join ',' -ne $wfAplCand[0]) { Write-Host "  [ERRO] seletor: Skipped veio '$(@($wfAplSel.Skipped) -join ', ')', esperado '$($wfAplCand[0])'" -ForegroundColor Red; $wbErrors++ }
            # Toggle nunca é pulado, mesmo constando como aplicado: o interruptor já mostra o estado
            # e ele não passa pelo botão Aplicar.
            $wfAplTog = @(@($sync.configs.tweaks.PSObject.Properties.Name) | Where-Object { $_ -like 'WPFToggle*' })
            if ($wfAplTog.Count) {
                $wfAplTogSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $null = $wfAplTogSet.Add($wfAplTog[0])
                if (@((Select-WinForgeTweaksToApply -Keys @($wfAplTog[0]) -Applied $wfAplTogSet).Skipped).Count -ne 0) { Write-Host "  [ERRO] seletor: o Toggle '$($wfAplTog[0])' foi pulado" -ForegroundColor Red; $wbErrors++ }
            }

            # A marca na linha: exatamente duas, e rodar de novo não empilha uma terceira.
            $wfAplAntes = $sync.AppliedTweaks
            $sync.AppliedTweaks = $wfAplFake
            $wfAplMarcadas = Update-WinForgeAppliedVisuals
            if ($wfAplMarcadas -ne 2) { Write-Host "  [ERRO] marca 'aplicado': $wfAplMarcadas linha(s) marcada(s), esperado 2" -ForegroundColor Red; $wbErrors++ }
            $null = Update-WinForgeAppliedVisuals
            foreach ($wfAplK in @($wfAplCand[0], $wfAplCand[1])) {
                $wfAplPanel = $sync[$wfAplK].Parent
                $wfAplSufixos = @(@($wfAplPanel.Children) | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and [string]$_.Tag -eq "WFApplied_$wfAplK" })
                if ($wfAplSufixos.Count -ne 1) { Write-Host "  [ERRO] marca 'aplicado': '$wfAplK' ficou com $($wfAplSufixos.Count) sufixo(s) depois de duas passadas, esperado 1" -ForegroundColor Red; $wbErrors++ }
                elseif ([string]$wfAplSufixos[0].Text -ne ' · aplicado') { Write-Host "  [ERRO] marca 'aplicado': texto '$($wfAplSufixos[0].Text)'" -ForegroundColor Red; $wbErrors++ }
                if ([string]$sync[$wfAplK].ToolTip -notmatch '^✔ Já aplicado neste sistema\. ') { Write-Host "  [ERRO] marca 'aplicado': a dica de '$wfAplK' não começa com o aviso ('$($sync[$wfAplK].ToolTip)')" -ForegroundColor Red; $wbErrors++ }
            }
            # Saiu do conjunto, sai da tela: a marca e o prefixo da dica são desfeitos.
            $sync.AppliedTweaks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            if ((Update-WinForgeAppliedVisuals) -ne 0) { Write-Host "  [ERRO] marca 'aplicado': conjunto vazio deveria deixar 0 linha(s) marcada(s)" -ForegroundColor Red; $wbErrors++ }
            $wfAplSobrou = @(@($sync[$wfAplCand[0]].Parent.Children) | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and [string]$_.Tag -eq "WFApplied_$($wfAplCand[0])" })
            if ($wfAplSobrou.Count) { Write-Host "  [ERRO] marca 'aplicado': o sufixo de '$($wfAplCand[0])' não foi removido" -ForegroundColor Red; $wbErrors++ }
            if ([string]$sync[$wfAplCand[0]].ToolTip -match '^✔ Já aplicado neste sistema\. ') { Write-Host "  [ERRO] marca 'aplicado': o prefixo continuou na dica de '$($wfAplCand[0])'" -ForegroundColor Red; $wbErrors++ }

            # O contador do checklist ganhou a terceira conta.
            Update-WinForgeDiagRecommendationCount
            if ($sync.WPFDiagRecCount.Text -notmatch '\d+ de \d+ recomendados marcados · \d+ já aplicados') { Write-Host "  [ERRO] contador: '$($sync.WPFDiagRecCount.Text)' sem a conta de já aplicados" -ForegroundColor Red; $wbErrors++ }

            # Chave com InvokeScript NUNCA é pulada. O detector da base só compara registro e
            # serviço: um tweak cujo registro já bate mas cuja METADE de script nunca rodou
            # (WPFTweaksHiber grava duas chaves e chama 'powercfg /hibernate off') apareceria como
            # aplicado, e pular seria deixar o sistema pela metade para sempre.
            $wfAplScript = @(@($sync.configs.tweaks.PSObject.Properties.Name) | Where-Object { $sync.configs.tweaks.$_.InvokeScript -and ($sync.configs.tweaks.$_.registry -or $sync.configs.tweaks.$_.service) })
            if ($wfAplScript -notcontains 'WPFTweaksHiber') { Write-Host "  [ERRO] aplicados: WPFTweaksHiber deixou de ser registro+script - o teste não prova mais nada" -ForegroundColor Red; $wbErrors++ }
            foreach ($wfAplSc in $wfAplScript) {
                if (Test-WinForgeAppliedEligible -Key $wfAplSc) { Write-Host "  [ERRO] aplicados: '$wfAplSc' tem InvokeScript e mesmo assim pode ser pulado" -ForegroundColor Red; $wbErrors++ }
            }
            $wfAplScSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $null = $wfAplScSet.Add('WPFTweaksHiber')
            if (@((Select-WinForgeTweaksToApply -Keys @('WPFTweaksHiber') -Applied $wfAplScSet).Skipped).Count -ne 0) { Write-Host "  [ERRO] seletor: 'WPFTweaksHiber' (registro + script) foi pulado" -ForegroundColor Red; $wbErrors++ }

            # Depois que o filtro reescreve $sync.AppliedTweaks, quem repinta as linhas e o contador
            # é este ajudante - chamado pela thread da janela. Sem ele, as linhas ficariam com a
            # verdade do diagnóstico da abertura e o contador com outra.
            $sync.AppliedTweaks = $wfAplFake
            $sync.WPFDiagRecCount.Text = 'nada'
            $wfAplResync = Update-WinForgeAppliedAfterApply
            if ($wfAplResync -ne 2) { Write-Host "  [ERRO] repintura pós-aplicação: $wfAplResync linha(s) marcada(s), esperado 2" -ForegroundColor Red; $wbErrors++ }
            if ($sync.WPFDiagRecCount.Text -notmatch '\d+ já aplicados') { Write-Host "  [ERRO] repintura pós-aplicação: o contador não foi refeito ('$($sync.WPFDiagRecCount.Text)')" -ForegroundColor Red; $wbErrors++ }

            # Detecção que FALHA não pode APAGAR o que já se sabia. O caminho errado era mudo e
            # caro: o seletor gravava a lista vazia da falha em $sync.AppliedTweaks, as marcas
            # sumiam das linhas e o contador voltava a "0 já aplicados" - como se o sistema
            # estivesse limpo. A falha é simulada por $sync.WinForgeSelfTestAppliedFail, que é a
            # única forma de provar isto sem mexer no registro desta máquina.
            $sync.AppliedTweaks = $wfAplFake
            $sync.WinForgeSelfTestAppliedFail = $true
            try {
                $wfAplFalha = Get-WinForgeAppliedTweaks
                if ($null -ne $wfAplFalha) { Write-Host "  [ERRO] detecção com falha: devolveu '$(@($wfAplFalha).Count)' item(ns) em vez de `$null - quem chama não tem como distinguir 'nada aplicado' de 'não sei'" -ForegroundColor Red; $wbErrors++ }
                $wfAplSelFalha = Select-WinForgeTweaksToApply -Keys @($wfAplCand[0], $wfAplCand[1], $wfAplCand[2])
                if (@($wfAplSelFalha.Apply).Count -ne 3) { Write-Host "  [ERRO] detecção com falha: Apply veio com $(@($wfAplSelFalha.Apply).Count) chave(s), esperado as 3 pedidas - sem detecção nada pode ser pulado" -ForegroundColor Red; $wbErrors++ }
                if (@($wfAplSelFalha.Skipped).Count -ne 0) { Write-Host "  [ERRO] detecção com falha: $(@($wfAplSelFalha.Skipped).Count) chave(s) pulada(s), esperado 0" -ForegroundColor Red; $wbErrors++ }
                if (@($sync.AppliedTweaks).Count -ne 2) { Write-Host "  [ERRO] detecção com falha: `$sync.AppliedTweaks ficou com $(@($sync.AppliedTweaks).Count) chave(s), esperado as 2 que já estavam - a falha apagou o conjunto bom" -ForegroundColor Red; $wbErrors++ }
                if ((Update-WinForgeAppliedVisuals) -ne 2) { Write-Host "  [ERRO] detecção com falha: as marcas das linhas sumiram depois de uma detecção que falhou" -ForegroundColor Red; $wbErrors++ }
            } finally {
                $sync.WinForgeSelfTestAppliedFail = $false
            }

            # Trava de texto: a detecção roda DENTRO do corpo do runspace (ela lê registro e serviço
            # de ~80 entradas; no clique isso é a janela congelada sem nem pintar o rótulo, porque
            # quem pinta é o Dispatcher e o Dispatcher está parado dentro do handler) e ANTES do laço
            # que aplica - depois dele, o motor reaplicaria tudo antes de descobrir o que pular.
            $wfAplCorpo = [string](Get-Command Invoke-WPFtweaksbutton).ScriptBlock
            $wfAplDespacho = $wfAplCorpo.IndexOf('Invoke-WPFRunspace -ParameterList', [System.StringComparison]::Ordinal)
            $wfAplPos = $wfAplCorpo.IndexOf('$wfSel = Select-WinForgeTweaksToApply -Keys @($tweaks)', [System.StringComparison]::Ordinal)
            $wfAplLaco = $wfAplCorpo.IndexOf('Invoke-WinForgeTweaks $tweaks[$i]', [System.StringComparison]::Ordinal)
            if ($wfAplPos -lt 0) { Write-Host "  [ERRO] trava de texto: Invoke-WPFtweaksbutton não chama Select-WinForgeTweaksToApply" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAplLaco -lt 0) { Write-Host "  [ERRO] trava de texto: Invoke-WPFtweaksbutton não tem o laço de aplicação da base" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAplPos -gt $wfAplLaco) { Write-Host "  [ERRO] trava de texto: o filtro de aplicados vem DEPOIS do laço que aplica" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAplPos -lt $wfAplDespacho) { Write-Host "  [ERRO] trava de texto: a detecção do que já está aplicado ficou no caminho do clique - ela tem de rodar dentro do corpo do runspace" -ForegroundColor Red; $wbErrors++ }
            if ($wfAplCorpo.IndexOf('Conferindo o que já está aplicado', [System.StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] trava de texto: a barra não diz que está conferindo o que já está aplicado" -ForegroundColor Red; $wbErrors++ }
            # São DUAS repinturas, e é o par que importa. A primeira mostra o que a detecção do
            # clique achou (as linhas que serão puladas); a segunda roda depois do laço, com o
            # sistema já mexido - sem ela, o que ACABOU de ser aplicado ficaria sem marca até o
            # próximo diagnóstico, que é a tela mentindo justamente no instante em que o usuário
            # olha para ela.
            $wfAplRepinturas = @([regex]::Matches($wfAplCorpo, [regex]::Escape('Invoke-WPFUIThread $sync.WinForgeAppliedResyncCallback')))
            $wfAplRepintura = $(if ($wfAplRepinturas.Count) { $wfAplRepinturas[0].Index } else { -1 })
            if ($wfAplRepintura -lt 0) { Write-Host "  [ERRO] trava de texto: o corpo do runspace não repinta as linhas pela thread da janela depois da detecção" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAplRepintura -lt $wfAplPos) { Write-Host "  [ERRO] trava de texto: a repintura é agendada ANTES da detecção, e mostraria a verdade velha" -ForegroundColor Red; $wbErrors++ }
            if ($wfAplRepinturas.Count -ne 2) { Write-Host "  [ERRO] trava de texto: $($wfAplRepinturas.Count) repintura(s) no corpo do runspace, esperado 2 (antes e depois do laço que aplica)" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAplLaco -ge 0) {
                if ($wfAplRepinturas[0].Index -gt $wfAplLaco) { Write-Host "  [ERRO] trava de texto: a primeira repintura já vem depois do laço - ninguém mostra o que será pulado" -ForegroundColor Red; $wbErrors++ }
                if ($wfAplRepinturas[1].Index -lt $wfAplLaco) { Write-Host "  [ERRO] trava de texto: a segunda repintura vem ANTES do laço, e mostraria o sistema como ele era antes de aplicar" -ForegroundColor Red; $wbErrors++ }
            }
            # A segunda repintura precisa de verdade NOVA: repintar o mesmo conjunto depois do laço
            # não marcaria nada do que acabou de ser aplicado.
            $wfAplRedeteccao = $wfAplCorpo.IndexOf('Update-WinForgeAppliedFromSystem', [System.StringComparison]::Ordinal)
            if ($wfAplRedeteccao -lt 0) { Write-Host "  [ERRO] trava de texto: o corpo do runspace não refaz a detecção depois do laço que aplica" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAplLaco -ge 0 -and $wfAplRedeteccao -lt $wfAplLaco) { Write-Host "  [ERRO] trava de texto: a redetecção do fim ficou ANTES do laço que aplica" -ForegroundColor Red; $wbErrors++ }
            if ($wfAplCorpo.IndexOf('$sync.WinForgeAppliedResyncCallback = {', [System.StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] trava de texto: o bloco da repintura não nasce na runspace principal (no caminho do clique)" -ForegroundColor Red; $wbErrors++ }
            # "Detectar aplicados" roda dentro de um [Action] que o Dispatcher executa: exceção ali
            # não tem para onde subir e mata o BeginInvoke. O caminho da base é try/finally SEM
            # catch, então o catch tem de ser nosso.
            $wfAplGetCorpo = [string](Get-Command Invoke-WPFGetInstalled).ScriptBlock
            $wfAplGetSet = $wfAplGetCorpo.IndexOf('Set-WinForgeAppliedTweaks -Keys @($completedOperation.Checkboxes)', [System.StringComparison]::Ordinal)
            $wfAplGetCatch = $wfAplGetCorpo.IndexOf('catch { Write-WinForgeLog -Component "Applied" -Level "WARN" -Message "Detectar aplicados', [System.StringComparison]::Ordinal)
            if ($wfAplGetSet -lt 0) { Write-Host "  [ERRO] trava de texto: 'Detectar aplicados' não alimenta mais o conjunto de aplicados" -ForegroundColor Red; $wbErrors++ }
            elseif ($wfAplGetCatch -lt $wfAplGetSet) { Write-Host "  [ERRO] trava de texto: 'Detectar aplicados' atualiza o conjunto e as marcas sem catch - exceção ali escapa pelo Dispatcher" -ForegroundColor Red; $wbErrors++ }
            # A barra conta os passos que vão acontecer de verdade: sem descontar os pulados ela
            # pararia em "8/12" e pareceria travada.
            if ($wfAplCorpo.IndexOf('$totalSteps = [Math]::Max($totalSteps - $wfPulados.Count, 1)', [System.StringComparison]::Ordinal) -lt 0) { Write-Host "  [ERRO] trava de texto: o total de passos não desconta os ajustes pulados" -ForegroundColor Red; $wbErrors++ }
            Write-Host "  Estado já aplicado: $(@($wfAplDetectado).Count) chave(s) detectada(s) nesta máquina; marca, seletor e contador conferidos com conjunto sintético | chave com script nunca é pulada | detecção fora do clique | falha na detecção não apaga o conjunto | repintura antes e depois do laço"
        } catch {
            Write-Host "  [ERRO] estado já aplicado: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        } finally {
            $sync.AppliedTweaks = $wfAplAntes
            $null = Update-WinForgeAppliedVisuals
            Update-WinForgeDiagRecommendationCount
        }
        # Recomendação que NÃO se aplica a esta máquina. A linha existia habilitada e só descobria o
        # problema no clique: montava a aba de destino, não achava a caixa e aí se desabilitava - com
        # o total do contador já contando com ela. Agora a linha nasce desabilitada, com a dica na
        # frente, e fica de fora do M do contador. A entrada de teste é sintética e tem um papel de
        # servidor que não existe, então ela é escondida no cliente E no servidor simulado.
        try {
            $wfIndispChave = 'WPFTweaksWFSelfTestIndisponivel'
            $wfIndispRecAntes = $sync.Recommended
            try {
                $sync.configs.tweaks | Add-Member -NotePropertyName $wfIndispChave -NotePropertyValue ([pscustomobject]@{ Content = 'Item de teste indisponível'; Description = 'Só existe durante o SelfTest.'; Type = 'CheckBox'; role = 'papel-que-nao-existe'; risk = 'seguro'; category = 'z__Teste' }) -Force
                $wfIndispRec = @{}
                foreach ($wfIndispK in @($sync.Recommended.Keys)) { $wfIndispRec[$wfIndispK] = $sync.Recommended[$wfIndispK] }
                $wfIndispRec[$wfIndispChave] = 'linha sintética do SelfTest'
                $sync.Recommended = $wfIndispRec
                Update-WinForgeDiagnosticsTab
                $wfIndispLinha = $sync.WinForgeDiagMirrors[$wfIndispChave]
                if ($null -eq $wfIndispLinha) { throw "a linha da recomendação indisponível não foi criada" }
                if ($wfIndispLinha.IsEnabled) { Write-Host "  [ERRO] recomendação indisponível: a linha nasceu habilitada" -ForegroundColor Red; $wbErrors++ }
                if ([string]$wfIndispLinha.ToolTip -notmatch 'não se aplica') { Write-Host "  [ERRO] recomendação indisponível: a dica não diz que o item não se aplica ('$($wfIndispLinha.ToolTip)')" -ForegroundColor Red; $wbErrors++ }
                $wfIndispHab = @(@($sync.WinForgeDiagMirrors.Keys) | Where-Object { $sync.WinForgeDiagMirrors[$_].IsEnabled }).Count
                $wfIndispApl = @(@($sync.WinForgeDiagMirrors.Keys) | Where-Object { $sync.WinForgeDiagMirrors[$_].IsEnabled -and (Test-WinForgeDiagRecApplied -Key $_) }).Count
                if (@($sync.WinForgeDiagMirrors.Keys).Count -ne ($wfIndispHab + 1)) { Write-Host "  [ERRO] recomendação indisponível: esperado exatamente 1 linha desabilitada, veio $(@($sync.WinForgeDiagMirrors.Keys).Count - $wfIndispHab)" -ForegroundColor Red; $wbErrors++ }
                if ($sync.WPFDiagRecCount.Text -ne "0 de $wfIndispHab recomendados marcados · $wfIndispApl já aplicados") { Write-Host "  [ERRO] recomendação indisponível: contador '$($sync.WPFDiagRecCount.Text)', esperado '0 de $wfIndispHab recomendados marcados · $wfIndispApl já aplicados' (a linha desabilitada não entra no total)" -ForegroundColor Red; $wbErrors++ }
                $wfIndispTodos = Set-WinForgeDiagRecommendationSelection -Checked $true
                if ($wfIndispLinha.IsChecked) { Write-Host "  [ERRO] recomendação indisponível: 'Marcar todos' marcou a linha desabilitada" -ForegroundColor Red; $wbErrors++ }
                if ($wfIndispTodos -ne ($wfIndispHab - $wfIndispApl)) { Write-Host "  [ERRO] recomendação indisponível: 'Marcar todos' marcou $wfIndispTodos linha(s), esperado $($wfIndispHab - $wfIndispApl)" -ForegroundColor Red; $wbErrors++ }
                $null = Set-WinForgeDiagRecommendationSelection -Checked $false
                Write-Host "  Recomendação indisponível: linha desabilitada com dica, fora do total do contador ($wfIndispHab disponível(is))"
            } finally {
                $sync.Recommended = $wfIndispRecAntes
                $sync.configs.tweaks.PSObject.Properties.Remove($wfIndispChave)
                Update-WinForgeDiagnosticsTab
                $null = Set-WinForgeDiagRecommendationSelection -Checked $false
            }
        } catch {
            Write-Host "  [ERRO] recomendação indisponível: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
        }
        # Roda do mouse sobre as tabelas: o DataGrid tem rolagem própria e engolia a roda, deixando a
        # aba inteira parada. O conserto repassa o evento ao ScrollViewer da aba - e é isso que se
        # prova aqui, sem depender de a janela estar na tela.
        try {
            if (-not $sync.WinForgeDiagWheelHooked) { Write-Host "  [ERRO] roda do mouse: `$sync.WinForgeDiagWheelHooked não foi ligado por Initialize-WinForgeDiagnosticsTab" -ForegroundColor Red; $wbErrors++ }
            $sync.WinForgeTesteRoda = 0
            $wfRodaHandler = [System.Windows.Input.MouseWheelEventHandler] { param($eventSender, $eventArgs) $sync.WinForgeTesteRoda = $sync.WinForgeTesteRoda + 1 }
            # handledEventsToo: o próprio ScrollViewer trata MouseWheelEvent num class handler (é ele
            # que rola a aba, que é o que se quer) e marca o evento como tratado ANTES de qualquer
            # handler de instância. Sem o terceiro argumento esta sonda nunca seria chamada.
            $sync.WPFDiagScroll.AddHandler([System.Windows.UIElement]::MouseWheelEvent, $wfRodaHandler, $true)
            try {
                foreach ($wfGradeRoda in @($sync.WPFDiagDrivers, $sync.WPFDiagWU)) {
                    $wfRodaArgs = New-Object System.Windows.Input.MouseWheelEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, -120)
                    $wfRodaArgs.RoutedEvent = [System.Windows.UIElement]::PreviewMouseWheelEvent
                    $wfGradeRoda.RaiseEvent($wfRodaArgs)
                }
            } finally {
                $sync.WPFDiagScroll.RemoveHandler([System.Windows.UIElement]::MouseWheelEvent, $wfRodaHandler)
            }
            if ($sync.WinForgeTesteRoda -ne 2) { Write-Host "  [ERRO] roda do mouse: o ScrollViewer da aba recebeu $($sync.WinForgeTesteRoda) evento(s), esperado 2 (tabela de drivers e tabela do Windows Update)" -ForegroundColor Red; $wbErrors++ }
            # Rolagem de verdade: a janela nunca foi mostrada, então o layout é forçado na mão. Onde
            # o WPF sem tela não produz conteúdo mais alto que a viewport, a conferência acima (o
            # evento chegou ao ScrollViewer) é o que resta - e é ela que pega a regressão.
            $wfRodaOffset = 'sem layout (o WPF sem janela na tela não gerou conteúdo maior que a viewport)'
            try {
                $sync.WPFTabNav.SelectedItem = $sync.WPFTab8
                $sync.Form.Width = 1200
                $sync.Form.Height = 400
                # Layout na mão: a janela do SelfTest nunca é mostrada, então nada dispara Measure/
                # Arrange sozinho. Medir o ScrollViewer direto é o que dá extensão ao conteúdo e faz
                # ScrollableHeight deixar de ser zero.
                $sync.Form.Measure((New-Object System.Windows.Size(1200, 400)))
                $sync.Form.Arrange((New-Object System.Windows.Rect(0, 0, 1200, 400)))
                $sync.WPFDiagScroll.Measure((New-Object System.Windows.Size(1160, 300)))
                $sync.WPFDiagScroll.Arrange((New-Object System.Windows.Rect(0, 0, 1160, 300)))
                $sync.WPFDiagScroll.UpdateLayout()
                if ($sync.WPFDiagScroll.ScrollableHeight -gt 0) {
                    $sync.WPFDiagScroll.ScrollToVerticalOffset(0)
                    $sync.WPFDiagScroll.UpdateLayout()
                    $wfRodaArgs2 = New-Object System.Windows.Input.MouseWheelEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, -120)
                    $wfRodaArgs2.RoutedEvent = [System.Windows.UIElement]::PreviewMouseWheelEvent
                    $sync.WPFDiagDrivers.RaiseEvent($wfRodaArgs2)
                    $sync.WPFDiagScroll.UpdateLayout()
                    $wfRodaOffset = [string]$sync.WPFDiagScroll.VerticalOffset
                    if ($sync.WPFDiagScroll.VerticalOffset -le 0) { Write-Host "  [ERRO] roda do mouse: a roda sobre a tabela não rolou a aba (VerticalOffset = $($sync.WPFDiagScroll.VerticalOffset))" -ForegroundColor Red; $wbErrors++ }
                }
            } catch {
                $wfRodaOffset = "layout sem tela indisponível ($($_.Exception.Message))"
            }
            Write-Host "  Roda do mouse sobre as tabelas: repassada ao ScrollViewer da aba ($($sync.WinForgeTesteRoda) evento(s)) | rolagem: $wfRodaOffset"
        } catch {
            Write-Host "  [ERRO] roda do mouse: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
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
            # Uma AÇÃO de botão é o contrário do diagnóstico automático: o usuário clicou e está
            # esperando resposta, então ela escreve mesmo com outro trabalho em andamento - senão o
            # resultado do download ia só para o log. Janela fechando continua sendo recusa, porque
            # escrever é um Dispatcher.Invoke e o Dispatcher já está desligando.
            if ((Set-WinForgeDiagProgress -Label "ação do usuário com trabalho em andamento" -Percent 50) -ne $true) { Write-Host "  [ERRO] barra: Set-WinForgeDiagProgress cedeu a vez com ProcessRunning ligado" -ForegroundColor Red; $wbErrors++ }
            $sync.ProcessRunning = $false
            $sync.WinForgeClosing = $true
            if ((Set-WinForgeDiagProgress -Label "não deveria aparecer" -Percent 50) -ne $false) { Write-Host "  [ERRO] barra: Set-WinForgeDiagProgress escreveu com a janela fechando" -ForegroundColor Red; $wbErrors++ }
            $sync.WinForgeClosing = $false
            # E as duas ações da aba usam ESTA função, não a que cede a vez.
            foreach ($wfBarraFn in @('Invoke-WinForgeDriverAction', 'Invoke-WinForgeWindowsUpdateAction')) {
                $wfBarraDef = [string](Get-Command $wfBarraFn).ScriptBlock
                if ($wfBarraDef -match 'Set-WinForgeProfileProgress') { Write-Host "  [ERRO] barra: $wfBarraFn ainda escreve pela função que cede a vez" -ForegroundColor Red; $wbErrors++ }
                if ($wfBarraDef -notmatch 'Set-WinForgeDiagProgress') { Write-Host "  [ERRO] barra: $wfBarraFn não escreve na barra" -ForegroundColor Red; $wbErrors++ }
                # Um trabalho por vez vale para os dois tipos de trava: comando e processo.
                if ($wfBarraDef -notmatch '\$sync\.CommandRunning -or \$sync\.ProcessRunning') { Write-Host "  [ERRO] barra: $wfBarraFn não recusa com `$sync.ProcessRunning ligado" -ForegroundColor Red; $wbErrors++ }
            }
            # E o corpo do download cala o medidor de progresso do Invoke-WebRequest: no PowerShell
            # 5.1 ele emite um registro por bloco lido e fica uma ordem de grandeza mais lento num
            # arquivo de 700 MB. O corpo do download mora no callback da confirmação; o da consulta
            # ao vivo, na própria função - os dois chamam a rede, os dois calam o medidor.
            if ([string]${function:Invoke-WinForgeDriverAction} -notmatch "ProgressPreference = 'SilentlyContinue'") { Write-Host "  [ERRO] barra: o corpo da consulta ao vivo não desliga `$ProgressPreference" -ForegroundColor Red; $wbErrors++ }
            if ([string]$sync.WinForgeDriverConfirmCallback -notmatch "ProgressPreference = 'SilentlyContinue'") { Write-Host "  [ERRO] barra: o corpo do download não desliga `$ProgressPreference" -ForegroundColor Red; $wbErrors++ }
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
#
# $sync.CommandRunning entra na mesma lista, e não é teoria: um comando com fluxo ao vivo (a
# redefinição do Windows Update, a reinstalação do WinGet) roda Invoke-WPFFixesUpdate dentro da
# runspace, e essa função chama Set-WinUtilTaskbaritem, que de outra thread salta para o Dispatcher.
# Fechar a janela no meio disso era o abraço perfeito: a thread da janela parada dentro do
# Close-WinUtilRunspacePool esperando a runspace, e a runspace parada dentro do Dispatcher.Invoke
# esperando a thread da janela. Nem uma nem outra terminava, e o programa só saía pelo Gerenciador
# de Tarefas. A guarda de $sync.WinForgeClosing em Set-WinUtilTaskbaritem tira a segunda ponta; esta
# linha tira a primeira.
#
# O preço dessa saída é um abandono: as threads do pool morrem onde estiverem. Para um diagnóstico
# ou uma busca de driver isso é indiferente; para um REPARO não é. Uma restauração de permissões
# morta entre "posse para os Administradores" e "posse de volta ao TrustedInstaller" deixa a pasta
# do sistema aceitando alteração de qualquer processo elevado - o oposto do que o botão restaura -,
# e morta entre o backup e a gravação do índice deixa arquivos órfãos com o Desfazer dizendo "nada
# a desfazer". Por isso o fechamento PERGUNTA quando o que está rodando é 'repair', com "Não" como
# resposta padrão: quem apertou Enter no susto não interrompe nada. Leitura e diagnóstico seguem
# fechando direto.
$src = Replace-Once $src @'
$sync["Form"].Add_Closing({
    Close-WinUtilRunspacePool
    [System.GC]::Collect()
})
'@ @'
$sync["Form"].Add_Closing({
    param($wfFechSender, $wfFechArgs)

    if ($sync.CommandRunning -and [string]$sync.WinForgeStreamKind -eq 'repair') {
        $wfFechNome = if ([string]::IsNullOrWhiteSpace([string]$sync.WinForgeStreamName)) { 'Um reparo' } else { [string]$sync.WinForgeStreamName }
        $wfFechTexto = "$wfFechNome está em andamento; fechar agora pode deixar o sistema pela metade. Fechar mesmo assim?"
        $wfFechResp = [System.Windows.MessageBox]::Show(
            $sync["Form"],
            $wfFechTexto,
            "WinForge",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning,
            [System.Windows.MessageBoxResult]::No)
        if ($wfFechResp -ne [System.Windows.MessageBoxResult]::Yes) {
            if ($null -ne $wfFechArgs) { $wfFechArgs.Cancel = $true }
            return
        }
    }

    # avisa o diagnóstico e a busca de drivers: daqui em diante ninguém mais toca na interface
    $sync.WinForgeClosing = $true
    if ($sync.ProfileJobRunning -or $sync.DiagWUSearchRunning -or $sync.CommandRunning) {
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

    # WinForge: varredura da pasta de backup de permissões - acima de 1 GB ela RELATA, no log e na
    # barra de status, e não apaga nada. Quem apaga é o botão "Limpar backups antigos", com a lista
    # na tela e sob confirmação.
    $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ Show-WinForgeAclBackupSizeWarning }) | Out-Null

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

# ---------------------------------------------------------------- sistema visual: tokens de tema
# Antes dos estilos e do XAML: os gabaritos abaixo só referenciam nomes de token, e é aqui que os
# valores por trás desses nomes deixam de ser os da base.
$src = Set-WinForgeThemeTokens $src $WinForgeTheme $WinForgeThemeNovos

# ---------------------------------------------------------------- sistema visual: estilos
# Cada gabarito reescrito entra NO LUGAR do original. Acrescentar no fim do dicionário não serve:
# duas entradas com a mesma chave (ou dois estilos implícitos para o mesmo TargetType) estouram ao
# carregar o XAML, e mover o Button implícito para o fim quebraria o FilterChipStyle, que o
# referencia por StaticResource algumas linhas acima.
$src = Replace-Between $src @'
        <Style TargetType="Label">
'@ @'
        <Style x:Key="TabToggleButton"
'@ ((Get-WinForgeStyleSection $xamlStyles 'texto') + "`n`n") "estilos: rótulo e texto"

$src = Replace-Between $src @'
        <Style x:Key="TabToggleButton" TargetType="{x:Type ToggleButton}">
'@ @'
        <Style x:Key="ToggleButtonStyle" TargetType="ToggleButton">
'@ ((Get-WinForgeStyleSection $xamlStyles 'abas-e-botoes') + "`n`n") "estilos: abas e botões"

$src = Replace-Between $src @'
        <Style TargetType="CheckBox">
'@ @'
        <Style TargetType="RadioButton">
'@ ((Get-WinForgeStyleSection $xamlStyles 'caixas') + "`n") "estilos: caixas de seleção"

$src = Replace-Between $src @'
        <Style x:Key="BorderStyle" TargetType="Border">
'@ @'
        <Style TargetType="TextBox">
'@ ((Get-WinForgeStyleSection $xamlStyles 'cartoes') + "`n`n") "estilos: cartões"

# Estilos que a base não tem entram no fim do dicionário - não há chave para colidir.
$src = Insert-Before $src "    </Window.Resources>" ((Get-WinForgeStyleSection $xamlStyles 'novos') + "`n") "estilos: tabelas"

# Botões declarados nas configs (barra lateral da aba Instalar, painéis de Config e Atualizações)
# nasciam alinhados à esquerda e, sem a largura fixa de 200 px que o estilo da base impunha,
# cada um passou a ter a largura do próprio rótulo - uma coluna com a borda direita serrilhada.
# Esticados, a coluna volta a ter uma borda só.
$src = Replace-Once $src '                        $button.HorizontalAlignment = "Left"' '                        $button.HorizontalAlignment = "Stretch"' "alinhamento dos botões das configs"
# A largura declarada na config (ButtonWidth) sai de cena: com Width fixa e HorizontalAlignment
# "Stretch" o WPF trata o botão como "Center", e a aba Configurações ficava com uma fileira de
# botões de 350 px boiando no meio de uma coluna de 700 (foto light/04 da Tarefa 6). A Tarefa 6
# contornou devolvendo "Left" a esses botões, o que só trocou o defeito de lugar: a coluna voltava
# a ter a borda direita serrilhada. Sem largura nenhuma, todo botão de config estica na coluna e a
# coluna tem uma borda só. O campo continua no JSON da base - passa a ser ignorado.
$src = Replace-Once $src @'
                        if ($entryInfo.ButtonWidth) {
                            $baseWidth = [int]$entryInfo.ButtonWidth
                            $button.Width = [math]::Max($baseWidth, 350)
                        }
'@ @'
                        # WinForge: ButtonWidth da config é ignorado - o botão estica na coluna.
'@ "botão da config estica na coluna"

# A ordem dos botões da barra lateral da aba Instalar. A base ordena por tipo e depois pelo TEXTO,
# e o campo "Order" do JSON (que existe só em appnavigation, nas 11 entradas daquela barra) não é
# lido em lugar nenhum: em inglês a ordem alfabética ainda entregava "Install/Upgrade" primeiro por
# acaso; em português virou "Atualizar todos, Desinstalar, Instalar/atualizar" - a ação principal
# no fim. Aqui o Order passa a valer, e o texto continua desempatando quem não o declara.
$src = Replace-Once $src @'
            ButtonWidth = $entryInfo.ButtonWidth
            GroupName   = $entryInfo.GroupName  # Added for RadioButton groupings
'@ @'
            ButtonWidth = $entryInfo.ButtonWidth
            Order       = $entryInfo.Order
            GroupName   = $entryInfo.GroupName  # Added for RadioButton groupings
'@ "campo Order no objeto de entrada"
$src = Replace-Once $src @'
            }}, Content
'@ @'
            }}, @{Expression = { if ($_.Order) { [int]$_.Order } else { [int]::MaxValue } }}, Content
'@ "ordem declarada antes da alfabética"

# O hover do rótulo de categoria pintava a letra de branco fixo: no tema Claro é branco sobre
# fundo claro, ou seja, some. A cor de título serve nos dois temas.
$src = Replace-Once $src @'
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Foreground" Value="White" />
                </Trigger>
'@ @'
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Foreground" Value="{DynamicResource LabelboxForegroundColor}" />
                </Trigger>
'@ "hover do rótulo de categoria"

# ---------------------------------------------------------------- varredura visual (Tarefa 7)
# Estado desabilitado dos gabaritos que a base não deixou o WinForge reescrever (HoverButtonStyle,
# ToggleButtonStyle, FilterChipStyle e o botão de janela): a base pintava o fundo com
# ButtonBackgroundSelectedColor - que no WinForge é o AZUL DE SELEÇÃO -, ou seja, um controle
# desabilitado ficava com a mesma cor de um selecionado. Aqui vale a mesma regra dos gabaritos
# novos: fundo normal e 50 % de opacidade. Some junto o 'DimGray' fixo, que não é de tema nenhum.
$src = Replace-All $src @'
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundSelectedColor}"/>
                                <Setter Property="Foreground" Value="DimGray"/>
                            </Trigger>
'@ @'
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundColor}"/>
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
'@ "desabilitado sem a cor de seleção (BackgroundBorder)"
$src = Replace-Once $src @'
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ChipBorder" Property="Background" Value="{DynamicResource ButtonBackgroundSelectedColor}"/>
                                <Setter Property="Foreground" Value="DimGray"/>
                            </Trigger>
'@ @'
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ChipBorder" Property="Background" Value="{DynamicResource ButtonBackgroundColor}"/>
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
'@ "desabilitado sem a cor de seleção (ChipBorder)"

# Faixa de progresso/situação do rodapé: fundo de cartão e um fio de 1 px em cima, como pede o
# design (§7, "barra de status com fundo do cartão"). Com o fundo da janela ela não se separava
# do conteúdo - a barra aparecia como se fosse mais uma linha da aba.
$src = Replace-Once $src `
    '<Border Name="WPFTweaksProgressBar" Grid.Row="3" Background="{DynamicResource MainBackgroundColor}" Visibility="Collapsed" Padding="10,6">' `
    '<Border Name="WPFTweaksProgressBar" Grid.Row="3" Background="{DynamicResource CardBackgroundColor}" BorderBrush="{DynamicResource BorderColor}" BorderThickness="0,1,0,0" Visibility="Collapsed" Padding="10,6">' `
    "fundo da barra de status"
$src = Replace-Once $src `
    '<TextBlock Name="WPFTweaksProgressLabel" Text="" Foreground="{DynamicResource MainForegroundColor}" FontSize="13" Background="Transparent" Margin="0,0,0,4"/>' `
    '<TextBlock Name="WPFTweaksProgressLabel" Text="" Foreground="{DynamicResource MainForegroundColor}" FontSize="{DynamicResource FontSize}" Background="Transparent" Margin="0,0,0,4"/>' `
    "fonte da barra de status"

# Painel da direita da aba ISO: era o único cartão da interface desenhado na mão (fundo da JANELA,
# raio 5) em vez de usar BorderStyle. Ficava com a cor do fundo, sem se destacar de nada.
$src = Replace-Once $src @'
                                <Border Grid.Column="1"
                                        Background="{DynamicResource MainBackgroundColor}"
                                        BorderBrush="{DynamicResource BorderColor}"
                                        BorderThickness="1" CornerRadius="5"
                                        Margin="5" Padding="15">
'@ @'
                                <Border Grid.Column="1"
                                        Style="{StaticResource BorderStyle}"
                                        Margin="5" Padding="15">
'@ "cartão do painel da ISO"

# Cores fixas da aba ISO. O aviso "use uma ISO oficial" vira DiscouragedColor (é um alerta, e o
# token existe justamente para isso). Já os TRÊS BOTÕES destrutivos perdem a cor: 'OrangeRed' num
# botão não passa em contraste nos dois temas, e nenhum token passa - DiscouragedColor sobre o
# fundo de botão do tema Claro dá 4,23:1 e DangerColor sobre o do Escuro dá 3,82:1. O aviso fica
# no texto acima do botão, que está sobre cartão e passa folgado; o rótulo do botão já diz o que
# ele faz ("APAGA O PENDRIVE").
$src = Replace-Once $src `
    '                                                   Foreground="OrangeRed" Margin="0,0,0,10">' `
    '                                                   Foreground="{DynamicResource DiscouragedColor}" Margin="0,0,0,10">' `
    "aviso da ISO oficial"
$src = Replace-All $src "`n                                            Foreground=`"OrangeRed`"`n" "`n" "botões destrutivos da ISO sem cor fixa"
$src = Replace-Once $src "`n                                                Foreground=`"OrangeRed`"`n" "`n" "botão de gravar no pendrive sem cor fixa"

# Aba Atualizações. Os três cartões traziam título de 20 px em negrito e letra miúda de 11 - fora
# da escala do design (títulos 15 semibold, corpo 13). O cartão "Desativar atualizações" ainda
# pintava quatro textos de 'Red' fixo, inclusive o botão.
$src = Replace-All $src @'
                                                   FontSize="20"
                                                   FontWeight="Bold"
'@ @'
                                                   FontSize="{DynamicResource HeaderFontSize}"
                                                   FontWeight="SemiBold"
'@ "títulos dos cartões de Atualizações"
$src = Replace-All $src @'
                                                   FontSize="11"
'@ @'
                                                   FontSize="12"
'@ "letra miúda dos cartões de Atualizações"
$src = Replace-All $src @'
                                                   Foreground="Red"/>
'@ @'
                                                   Foreground="{DynamicResource DangerColor}"/>
'@ "vermelho fixo do cartão Desativar atualizações"
# O botão perde o vermelho pelo mesmo motivo dos botões da ISO (3,82:1 no tema Escuro). Quem passa
# a carregar o aviso é o CONTORNO do cartão, do jeito que o cartão "Recomendado" já fazia com o
# verde do progresso.
$src = Replace-Once $src "`n                                            Foreground=`"Red`"`n" "`n" "botão Desativar atualizações sem cor fixa"
$src = Replace-Once $src @'
                            <Border Style="{StaticResource BorderStyle}" Padding="16" MinHeight="300">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <StackPanel Grid.Row="0" Margin="0,0,0,14">
                                        <TextBlock Text="Disable Updates"
'@ @'
                            <Border Style="{StaticResource BorderStyle}"
                                    BorderBrush="{DynamicResource DangerColor}"
                                    BorderThickness="2"
                                    Padding="16" MinHeight="300">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="*"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <StackPanel Grid.Row="0" Margin="0,0,0,14">
                                        <TextBlock Text="Disable Updates"
'@ "contorno do cartão Desativar atualizações"

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

# ---------------------------------------------------------------- largura das faixas do console
# As faixas do tipo "--   AppX Install Finished   ---" ficam entre duas linhas de "=" de largura fixa.
# Se a tradução mudar o comprimento, o "---" da direita sai do lugar e a moldura fica torta. Aqui o
# build reprova o par inteiro em vez de esperar alguém olhar o console.
$wfFaixaRuim = @()
foreach ($pair in @($WinForgeI18nStrings) + @($WinForgeI18nRepeated)) {
    if ($pair[0] -match '^"-{2,}.*-"$' -and $pair[0].Length -ne $pair[1].Length) {
        $wfFaixaRuim += "  |$($pair[0])| ($($pair[0].Length)) -> |$($pair[1])| ($($pair[1].Length))"
    }
}
if ($wfFaixaRuim.Count) { throw "Faixa(s) do console com largura diferente do original:`n$($wfFaixaRuim -join "`n")" }
Write-Host "Faixas do console: largura igual à do original em todas"

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
# As DUAS linhas são cobradas separadamente e com o fim de linha junto. A conferência antiga
# procurava só o prefixo comum aos dois comentários, e a linha OFFLINE ("... (funciona offline)")
# o contém: bastava ela existir para o teste passar, mesmo que o caminho ONLINE tivesse voltado a
# abrir na aba Instalar - que é o caminho normal de quem tem internet.
foreach ($wfEsperado in @(
    "`$sync.currentTab = `"Diagnostico`"",
    "Invoke-WPFTab `"WPFTab8BT`"  # WinForge: abre no Diagnóstico`r`n",
    "Invoke-WPFTab `"WPFTab8BT`"  # WinForge: abre no Diagnóstico (funciona offline)`r`n"
)) {
    if ($final.IndexOf($wfEsperado, [StringComparison]::Ordinal) -lt 0) { throw "Motor gerado sem a aba de abertura no Diagnóstico: falta $($wfEsperado.TrimEnd("`r","`n"))" }
}
if ($final.IndexOf('Invoke-WPFTab "WPFTab1BT"', [StringComparison]::Ordinal) -ge 0) { throw "Motor gerado ainda abre na aba Instalar (Invoke-WPFTab `"WPFTab1BT`")" }
Write-Host "Aba de abertura: Diagnóstico"

# Tipografia. A única fonte monoespaçada do WinForge é a da janela de saída de comandos, montada
# em código - o XAML e a tabela de temas não podem ter nenhuma. A conferência é sobre os DOIS
# blocos de texto que viram interface, e não sobre o arquivo inteiro: as mensagens do -SelfTest
# falam de 'Consolas' de propósito e não são fonte de coisa nenhuma.
function Get-WinForgeGeneratedBlock([string]$text, [string]$startAnchor, [string]$endAnchor, [string]$what) {
    $s = $text.IndexOf($startAnchor, [StringComparison]::Ordinal)
    if ($s -lt 0) { throw "Motor gerado: bloco '$what' não encontrado" }
    if ($text.IndexOf($startAnchor, $s + 1, [StringComparison]::Ordinal) -ge 0) { throw "Motor gerado: bloco '$what' ambíguo" }
    $s += $startAnchor.Length
    $e = $text.IndexOf($endAnchor, $s, [StringComparison]::Ordinal)
    if ($e -lt 0) { throw "Motor gerado: fim do bloco '$what' não encontrado" }
    return $text.Substring($s, $e - $s)
}
$wfXamlFinal  = Get-WinForgeGeneratedBlock $final "`$inputXML = @'`r`n" "`r`n'@" 'XAML'
$wfTemaFinal  = Get-WinForgeGeneratedBlock $final "`$sync.configs.themes = @'`r`n" "`r`n'@" 'temas'
foreach ($wfFonteRuim in @('Consolas', 'Arial')) {
    foreach ($wfBloco in @(@{ Nome = 'XAML'; Texto = $wfXamlFinal }, @{ Nome = 'tabela de temas'; Texto = $wfTemaFinal })) {
        $wfQtd = ([regex]::Matches($wfBloco.Texto, $wfFonteRuim)).Count
        if ($wfQtd -ne 0) { throw "Motor gerado: '$wfFonteRuim' aparece $wfQtd vez(es) no bloco $($wfBloco.Nome)" }
    }
}
$wfMono = ([regex]::Matches($final, [regex]::Escape("New-Object System.Windows.Media.FontFamily 'Consolas'"))).Count
if ($wfMono -ne 1) { throw "Motor gerado: esperado exatamente 1 fonte monoespaçada (a janela de saída), achei $wfMono" }
if ($wfTemaFinal -notmatch '"HeaderFontFamily": "Segoe UI Semibold"') { throw "Motor gerado: HeaderFontFamily não é 'Segoe UI Semibold'" }
if ($wfTemaFinal -notmatch '"FontFamily": "Segoe UI"') { throw "Motor gerado: FontFamily não é 'Segoe UI'" }
Write-Host "Tipografia: Segoe UI no XAML e nos temas, Consolas só na janela de saída de comandos"

# Cor fixa no XAML. Todo pincel da interface tem de vir do tema: cor escrita à mão só funciona num
# dos dois temas (foi assim que 'Foreground="Red"' do cartão de Atualizações e 'OrangeRed' da aba
# ISO atravessaram o Plano 6 inteiro). A varredura é sobre os atributos que pintam alguma coisa e
# aceita só o que está na lista abaixo, com motivo. Cor nova = build vermelho.
$wfCorPermitida = @{
    'Background="Transparent"'  = 'sem pintura: o controle mostra o que está atrás'
    'BorderBrush="Transparent"' = 'sem contorno'
    'Fill="Transparent"'        = 'área clicável invisível'
    'Background="#8B0000"'      = 'faixa de modo offline: par fechado com o texto branco (10:1), não segue tema'
    'Foreground="White"'        = 'texto da faixa de modo offline, sobre o #8B0000 acima'
    'Background="#555555"'      = 'ToggleSwitchStyle: gabarito MORTO na base (nada o referencia)'
    'Background="Black"'        = 'ToggleSwitchStyle: gabarito MORTO na base (nada o referencia)'
}
$wfCorRegex = [regex]'(?<attr>Foreground|Background|BorderBrush|Fill|Stroke)="(?<val>[^"{}]+)"'
$wfCorNovas = @{}
foreach ($wfCorM in $wfCorRegex.Matches($wfXamlFinal)) {
    $wfCorTexto = '{0}="{1}"' -f $wfCorM.Groups['attr'].Value, $wfCorM.Groups['val'].Value
    if ($wfCorPermitida.ContainsKey($wfCorTexto)) { continue }
    if (-not $wfCorNovas.ContainsKey($wfCorTexto)) { $wfCorNovas[$wfCorTexto] = 0 }
    $wfCorNovas[$wfCorTexto]++
}
if ($wfCorNovas.Count) {
    $wfCorLista = @($wfCorNovas.GetEnumerator() | Sort-Object Name | ForEach-Object { "  $($_.Name) x$($_.Value)" })
    throw "Motor gerado: cor fixa no XAML fora da lista permitida:`n$($wfCorLista -join "`n")"
}
Write-Host "Cores: nenhuma cor fixa no XAML fora das $($wfCorPermitida.Count) exceções conhecidas"

# Chips de grupo da aba Instalar: rótulo x Tag. São DOIS literais independentes no motor - os
# <ToggleButton> do XAML e a tabela $sync.AppCategoryChips, que a inicialização copia para a Tag
# de cada chip. Quem filtra é a Tag; o rótulo é só o que se lê. Traduzir um e esquecer o outro dá
# um chip com nome certo que não casa com aplicativo nenhum, e isso não aparece em teste de tela.
# A conferência é aqui, e não no -SelfTest, porque a tabela só é atribuída depois do bloco dele.
$wfChipXaml = @()
foreach ($wfChipM in [regex]::Matches($wfXamlFinal, '<ToggleButton Name="(?<n>WPFSearchChip\w+)"\s+Content="(?<c>[^"]*)"')) {
    $wfChipXaml += [pscustomobject]@{ Name = $wfChipM.Groups['n'].Value; Content = $wfChipM.Groups['c'].Value }
}
if ($wfChipXaml.Count -lt 2) { throw "Motor gerado: não achei os chips de grupo no XAML" }
$wfChipTabelaTexto = Get-WinForgeGeneratedBlock $final "`$sync.AppCategoryChips = @(`r`n" "`r`n)`r`n" 'tabela de chips'
$wfChipTabela = @()
foreach ($wfChipM in [regex]::Matches($wfChipTabelaTexto, '@\{\s*Name\s*=\s*"(?<n>[^"]*)";\s*Category\s*=\s*"(?<c>[^"]*)"\s*\}')) {
    $wfChipTabela += [pscustomobject]@{ Name = $wfChipM.Groups['n'].Value; Category = $wfChipM.Groups['c'].Value }
}
$wfChipRuins = @()
if (($wfChipXaml.Name -join ',') -ne ($wfChipTabela.Name -join ',')) {
    $wfChipRuins += "os chips do XAML ($($wfChipXaml.Name -join ', ')) não são os da tabela ($($wfChipTabela.Name -join ', '))"
} else {
    for ($i = 0; $i -lt $wfChipXaml.Count; $i++) {
        $wfChipEsperada = if ($wfChipXaml[$i].Name -eq 'WPFSearchChipAll') { '' } else { $wfChipXaml[$i].Content }
        if ($wfChipTabela[$i].Category -ne $wfChipEsperada) {
            $wfChipRuins += "$($wfChipXaml[$i].Name) mostra '$($wfChipXaml[$i].Content)' e filtra por '$($wfChipTabela[$i].Category)'"
        }
    }
}
if ($wfChipRuins.Count) { throw "Motor gerado: chips de grupo inconsistentes:`n  $($wfChipRuins -join "`n  ")" }
Write-Host "Chips de grupo: $($wfChipXaml.Count) com rótulo e Tag iguais (o 'Todos' com Tag vazia)"

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
# ANSI, e bastaria um arquivo de config perder o BOM para "Ragnarök" virar "RagnarÃ¶k" no doc.
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

function Get-WinForgeI18nData {
    $sync = @{}
    . (Get-ConfigScriptBlock "config\wf-i18n-configs.ps1")
    return $sync
}

$auditSync  = Get-WinForgeAuditData
$audit      = $auditSync.WinForgeAudit
$configSync = Get-WinForgeConfigData
$jsonTweaks = @((Get-JsonConfigBlock $src 'tweaks'), (Get-JsonConfigBlock $src 'wbtweaks'), (Get-JsonConfigBlock $src 'wfserver'))

# O doc mostra o nome que o usuário vê na tela, e na tela o nome já está traduzido: sem aplicar o
# dicionário aqui, docs\auditoria.md sairia com o Content em inglês para tudo que veio da base.
# É a mesma tradução que Initialize-WinUtilBoostConfigs faz em tempo de execução - só que o doc lê
# os blocos JSON direto, sem passar por lá.
$i18nDict = (Get-WinForgeI18nData).WinForgeI18n

# ------------------------------------------------- travas do dicionário por chave
# As duas conferências que faltavam à cobertura do -SelfTest. Elas ficam AQUI e não lá porque
# dependem do texto ORIGINAL da base, e em tempo de execução ele já não existe: a tradução é
# aplicada em cima da própria entrada, então o -SelfTest só vê o resultado.
#
#   1. Content traduzido igual ao Content da base. A cobertura só perguntava "existe chave?".
#      Uma entrada copiada e colada do inglês (ou uma tradução esquecida no meio de um lote)
#      passava com nota máxima e ia para a tela em inglês.
#   2. Aplicativo com 'Content' no dicionário. O bloco de aplicativos guarda o NOME DO PRODUTO em
#      'content' e a busca de propriedade do PowerShell não diferencia maiúsculas: um 'Content' no
#      dicionário de um aplicativo renomearia o produto (o "Firefox" viraria a tradução) e a lista
#      de instalação deixaria de casar com o que o winget conhece.
# Os blocos vêm de $src, e não do arquivo base: as chaves da base passam pelo rename global
# (WPFWinUtilSSHServer -> WPFWinForgeSSHServer) e é a forma RENOMEADA que o dicionário usa. O
# Content ainda está em inglês aqui - a tradução por chave só acontece em tempo de execução, e
# nenhum par literal de config\wf-i18n-strings.ps1 mexe no Content de tweaks ou de feature (os
# que mexem em "Content" são todos da barra da aba Instalar, o bloco appnavigation).
$wfBaseTweaks = Get-JsonConfigBlock $src 'tweaks'
$wfBaseFeature = Get-JsonConfigBlock $src 'feature'
$wfBaseApps = Get-JsonConfigBlock $src 'applications'
$wfDicIguais = @(); $wfDicAppContent = @(); $wfDicSemBase = @()
foreach ($wfDicChave in @($i18nDict.Keys | Sort-Object)) {
    $wfDicEntrada = $i18nDict[$wfDicChave]
    $wfDicApp = $wfBaseApps.PSObject.Properties[$wfDicChave]
    if ($wfDicApp) {
        if ($wfDicEntrada.ContainsKey('Content')) { $wfDicAppContent += $wfDicChave }
        continue
    }
    if (-not $wfDicEntrada.ContainsKey('Content')) { continue }
    $wfDicBase = $wfBaseTweaks.PSObject.Properties[$wfDicChave]
    if (-not $wfDicBase) { $wfDicBase = $wfBaseFeature.PSObject.Properties[$wfDicChave] }
    if (-not $wfDicBase) { $wfDicSemBase += $wfDicChave; continue }
    if ([string]$wfDicBase.Value.Content -eq [string]$wfDicEntrada['Content']) { $wfDicIguais += "$wfDicChave ('$($wfDicEntrada['Content'])')" }
}
if ($wfDicAppContent.Count) { throw "Dicionário por chave: aplicativo com 'Content' (o nome do produto não se traduz): $($wfDicAppContent -join ', ')" }
if ($wfDicSemBase.Count) { throw "Dicionário por chave: 'Content' para chave que não existe em tweaks nem em feature da base: $($wfDicSemBase -join ', ')" }
if ($wfDicIguais.Count) { throw "Dicionário por chave: $($wfDicIguais.Count) Content igual ao original da base (tradução esquecida): $($wfDicIguais -join ', ')" }
Write-Host "Dicionário por chave: $(@($i18nDict.Keys).Count) entrada(s), nenhum Content igual ao original e nenhum aplicativo renomeado"

foreach ($o in $jsonTweaks) {
    foreach ($p in $o.PSObject.Properties) {
        $t = $i18nDict[$p.Name]
        if (-not $t -or -not $t.ContainsKey('Content')) { continue }
        $prop = $p.Value.PSObject.Properties['Content']
        if ($prop) { $prop.Value = $t['Content'] }
    }
}

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
