# Inventário das descrições visíveis (aba Ajustes, aba Config, aba Instalar).
#
# A descrição é o texto que decide se a pessoa marca ou não marca o item. Ela tem de dizer, em
# 1 a 3 frases: o que o item faz (mecanismo em palavras simples), que efeito prático isso tem e
# quando usar / o que custa. O -SelfTest do motor tem uma trava que reprova as formas conhecidas
# de descrição vazia (frase repetida dentro dela mesma, texto curto demais, texto que só repete o
# título, duas 'Origem:', 'CUIDADO:' escrito à mão). O que a trava NÃO consegue julgar é se o
# texto é bom - para isso serve esta lista: ela põe chave, título e descrição lado a lado, no
# tamanho de ler.
#
# Fontes, na mesma ordem em que Initialize-WinUtilBoostConfigs monta a tela:
#   - blocos JSON do arquivo base (src\Engine\base\winutil-26.08.19.ps1), já com a tradução por
#     chave de config\wf-i18n-configs.ps1 aplicada por cima;
#   - entradas do próprio WinForge (config\wb-config.ps1, wf-server-config.ps1,
#     wf-repair-config.ps1), que já nascem em português;
#   - as entradas de prioridade por jogo, que são geradas em winforge\wb-functions.ps1 a partir da
#     lista $sync.configs.wbgames - aqui só o gabarito é mostrado, uma vez, porque as ~70 linhas
#     são o mesmo texto com o nome do executável trocado.
# O prefixo "CUIDADO: <motivo>." que Initialize-WinForgeAudit cola em tempo de execução NÃO
# aparece aqui: o que se revisa é o texto de origem, que é o que dá para editar.
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    # Só as entradas de um grupo: tweaks, config ou apps.
    [ValidateSet('todos', 'tweaks', 'config', 'apps')]
    [string]$Grupo = 'todos',
    # Só as descrições com menos de N caracteres - as candidatas mais óbvias a reescrita.
    [int]$MenorQue = 0,
    # Uma linha por entrada, com tabulação entre os campos (para colar em planilha).
    [switch]$Csv
)
$ErrorActionPreference = 'Stop'

$engineDir = Join-Path $RepoRoot "src\Engine"
$basePath  = Join-Path $engineDir "base\winutil-26.08.19.ps1"
if (-not (Test-Path $basePath)) { throw "Arquivo base não encontrado: $basePath" }

# Dot-source de .ps1 sem BOM cai na code page ANSI no PowerShell 5.1; ler em UTF-8 e executar um
# scriptblock mantém os acentos (mesmo motivo do Get-ConfigScriptBlock do build).
function Get-ScriptBlockUtf8([string]$path) {
    return [scriptblock]::Create([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
}

function Get-JsonConfigBlock([string]$text, [string]$name) {
    $start = "`$sync.configs.$name = @'`n"
    $i = $text.IndexOf($start, [StringComparison]::Ordinal)
    if ($i -lt 0) { throw "Bloco JSON '$name' não encontrado em $basePath." }
    $i += $start.Length
    $e = $text.IndexOf("`n'@ | ConvertFrom-Json", $i, [StringComparison]::Ordinal)
    if ($e -lt 0) { throw "Fim do bloco JSON '$name' não encontrado." }
    return ($text.Substring($i, $e - $i) | ConvertFrom-Json)
}

$baseText = [System.IO.File]::ReadAllText($basePath, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n"

$sync = @{ configs = @{} }
. (Get-ScriptBlockUtf8 (Join-Path $engineDir "config\wf-apps.ps1"))
$removedApps = @($sync.WinForgeRemovedApps)
$removedFeature = @('WPFWinUtilInstallPSProfile', 'WPFWinUtilUninstallPSProfile')
$renomeadas = @{ 'WPFWinUtilSSHServer' = 'WPFWinForgeSSHServer' }

$sync = @{ configs = @{} }
. (Get-ScriptBlockUtf8 (Join-Path $engineDir "config\wf-i18n-configs.ps1"))
$dic = $sync.WinForgeI18n
if ($null -eq $dic) { $dic = @{} }

$sync = @{ configs = @{} }
. (Get-ScriptBlockUtf8 (Join-Path $engineDir "config\wb-config.ps1"))
. (Get-ScriptBlockUtf8 (Join-Path $engineDir "config\wf-server-config.ps1"))
. (Get-ScriptBlockUtf8 (Join-Path $engineDir "config\wf-repair-config.ps1"))
$wbtweaks  = $sync.configs.wbtweaks
$wbfeature = $sync.configs.wbfeatures
$wfserver  = $sync.configs.wfserver
$wfrepair  = $sync.configs.wfrepair
$wbgames   = @($sync.configs.wbgames)

# O gabarito da descrição das entradas de jogo mora no código, não numa config: é lido do fonte
# para não ficarem duas cópias do mesmo texto (uma delas envelhecendo em silêncio).
$funcText = [System.IO.File]::ReadAllText((Join-Path $engineDir "winforge\wb-functions.ps1"), [System.Text.Encoding]::UTF8)
# A âncora é o laço que gera as entradas, não o texto da descrição: ancorar no texto fazia o
# inventário dizer "gabarito não encontrado" no exato momento em que a descrição era reescrita.
$iGame = $funcText.IndexOf('foreach ($g in $sync.configs.wbgames)', [StringComparison]::Ordinal)
$mGame = if ($iGame -ge 0) { [regex]::Match($funcText.Substring($iGame), 'Description\s*=\s*"([^"]*)"') } else { $null }
$gabaritoJogo = if ($mGame -and $mGame.Success) { $mGame.Groups[1].Value } else { '(gabarito não encontrado em winforge\wb-functions.ps1)' }

$linhas = New-Object System.Collections.Generic.List[object]
function Add-Linha([string]$grupo, [string]$fonte, [string]$chave, [string]$titulo, [string]$desc) {
    $linhas.Add([pscustomobject]@{ Grupo = $grupo; Fonte = $fonte; Chave = $chave; Content = $titulo; Description = $desc })
}

# --- base, com a tradução por chave aplicada -------------------------------------------------
$blocos = @(
    @{ Grupo = 'tweaks'; Bloco = 'tweaks';       Titulo = 'Content'; Texto = 'Description'; Excluir = @() }
    @{ Grupo = 'config'; Bloco = 'feature';      Titulo = 'Content'; Texto = 'Description'; Excluir = $removedFeature }
    @{ Grupo = 'apps';   Bloco = 'applications'; Titulo = 'content'; Texto = 'description'; Excluir = $removedApps }
)
foreach ($b in $blocos) {
    $obj = Get-JsonConfigBlock $baseText $b.Bloco
    foreach ($p in $obj.PSObject.Properties) {
        if ($p.Name -in $b.Excluir) { continue }
        $chave = if ($renomeadas.ContainsKey($p.Name)) { $renomeadas[$p.Name] } else { $p.Name }
        $titulo = [string]$p.Value.PSObject.Properties[$b.Titulo].Value
        $propD = $p.Value.PSObject.Properties[$b.Texto]
        $desc = if ($propD) { [string]$propD.Value } else { '' }
        if ($dic.ContainsKey($chave)) {
            $t = $dic[$chave]
            if ($t.Content -and $b.Titulo -eq 'Content') { $titulo = [string]$t.Content }
            if ($t.Description) { $desc = [string]$t.Description }
        }
        Add-Linha $b.Grupo 'base + wf-i18n-configs.ps1' $chave $titulo $desc
    }
}

# --- entradas do próprio WinForge -------------------------------------------------------------
$proprias = @(
    @{ Grupo = 'tweaks'; Fonte = 'wb-config.ps1';        Obj = $wbtweaks }
    @{ Grupo = 'tweaks'; Fonte = 'wf-server-config.ps1'; Obj = $wfserver }
    @{ Grupo = 'config'; Fonte = 'wb-config.ps1';        Obj = $wbfeature }
    @{ Grupo = 'config'; Fonte = 'wf-repair-config.ps1'; Obj = $wfrepair }
)
foreach ($g in $proprias) {
    if ($null -eq $g.Obj) { continue }
    foreach ($p in $g.Obj.PSObject.Properties) {
        Add-Linha $g.Grupo $g.Fonte $p.Name ([string]$p.Value.Content) ([string]$p.Value.Description)
    }
}
Add-Linha 'tweaks' 'wb-functions.ps1 (gabarito)' "WPFTweaksWBGame<jogo> (x$($wbgames.Count))" '<nome do jogo>' $gabaritoJogo

$sel = @($linhas | Where-Object { $Grupo -eq 'todos' -or $_.Grupo -eq $Grupo })
if ($MenorQue -gt 0) { $sel = @($sel | Where-Object { $_.Description.Length -lt $MenorQue }) }

if ($Csv) {
    "Grupo`tChave`tContent`tDescription"
    foreach ($l in $sel) { "{0}`t{1}`t{2}`t{3}" -f $l.Grupo, $l.Chave, ($l.Content -replace "`t", ' '), ($l.Description -replace "`t", ' ') }
    exit 0
}

$grupoAtual = ''
foreach ($l in $sel) {
    if ($l.Grupo -ne $grupoAtual) {
        $grupoAtual = $l.Grupo
        $qtd = @($sel | Where-Object Grupo -eq $grupoAtual).Count
        Write-Host ""
        Write-Host ("== {0}: {1} entrada(s) ==" -f $grupoAtual, $qtd) -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host ("{0}  [{1}]" -f $l.Chave, $l.Fonte) -ForegroundColor Yellow
    Write-Host ("  Content     : {0}" -f $(if ($l.Content) { $l.Content } else { '(sem Content - é aplicativo)' }))
    Write-Host ("  Description : {0}" -f $(if ($l.Description) { $l.Description } else { '(vazia)' }))
    Write-Host ("  {0} caractere(s), {1} frase(s)" -f $l.Description.Length, @([regex]::Split($l.Description, '(?<=[.!?])\s+') | Where-Object { $_.Trim() }).Count) -ForegroundColor DarkGray
}
Write-Host ""
Write-Host ("Total: {0} descrição(ões) listada(s)." -f $sel.Count)
