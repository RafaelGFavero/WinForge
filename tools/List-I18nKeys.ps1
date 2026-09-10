# Cobertura do dicionário por chave (Content/Description de tweaks, recursos e aplicativos).
#
# O dicionário de texto solto (config\wf-i18n-strings.ps1) traduz o arquivo gerado por
# substituição literal. Isso não serve para os blocos JSON de tweaks, feature e applications:
# são centenas de textos, muitos parecidos entre si, e um par literal errado esconderia a falha
# num Replace-Once que continua achando âncora. Para esses três blocos a tradução é POR CHAVE
# (config\wf-i18n-configs.ps1, aplicado em Initialize-WinUtilBoostConfigs).
#
# Este inventário é o outro lado da trava do -SelfTest: ele lista o que ainda FALTA no dicionário,
# já no formato de colar. A trava prova que acabou; aqui se descobre o que fazer.
#
# Fonte: os blocos JSON do arquivo BASE (src\Engine\base\winutil-26.08.19.ps1). Nenhuma
# transformação do build mexe em Content/Description desses três blocos, então o texto impresso
# aqui é exatamente o que o dicionário tem de casar. Ficam fora:
#   - as chaves 'Removido' da auditoria (config\wf-audit.ps1): somem do programa;
#   - os aplicativos de $sync.WinForgeRemovedApps (config\wf-apps.ps1): saem da aba Instalar;
#   - as duas entradas de perfil do PowerShell do projeto original, que o build apaga por regex.
# As entradas do próprio WinForge não estão no arquivo base e por isso nunca aparecem aqui - elas
# já nascem em português.
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    # Lista também as chaves que estão no dicionário sem existir na base (lixo depois de uma
    # atualização do arquivo base).
    [switch]$Orphans
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

$sync = @{}
. (Get-ScriptBlockUtf8 (Join-Path $engineDir "config\wf-audit.ps1"))
. (Get-ScriptBlockUtf8 (Join-Path $engineDir "config\wf-apps.ps1"))
$removidos   = @($sync.WinForgeAudit.Keys | Where-Object { $sync.WinForgeAudit[$_].Class -eq 'Removido' })
$removedApps = @($sync.WinForgeRemovedApps)
# Apagadas por regex em src\Engine\build.ps1 (perfil do PowerShell do projeto original).
$removedFeature = @('WPFWinUtilInstallPSProfile', 'WPFWinUtilUninstallPSProfile')
# O rename global do build (WinUtil -> WinForge) também pega o NOME da chave, não só o texto:
# a chave que o motor procura em tempo de execução é a renomeada, e é ela que o dicionário usa.
$renomeadas = @{ 'WPFWinUtilSSHServer' = 'WPFWinForgeSSHServer' }

$dictPath = Join-Path $engineDir "config\wf-i18n-configs.ps1"
$dict = @{}
if (Test-Path $dictPath) {
    $sync = @{}
    . (Get-ScriptBlockUtf8 $dictPath)
    if ($sync.WinForgeI18n) { $dict = $sync.WinForgeI18n }
}

# Campo do texto visível: nos tweaks e nos recursos é Content/Description; nos aplicativos o nome
# ('content') fica em inglês de propósito - é nome de produto - e só a 'description' é traduzida.
$grupos = @(
    @{ Nome = 'tweaks';       Bloco = 'tweaks';       Titulo = 'Content'; Texto = 'Description'; Excluir = $removidos }
    @{ Nome = 'feature';      Bloco = 'feature';      Titulo = 'Content'; Texto = 'Description'; Excluir = $removedFeature }
    @{ Nome = 'applications'; Bloco = 'applications'; Titulo = $null;     Texto = 'description'; Excluir = $removedApps }
)

$faltando = 0
$vistos = @{}
foreach ($g in $grupos) {
    $obj = Get-JsonConfigBlock $baseText $g.Bloco
    $linhas = New-Object System.Collections.Generic.List[string]
    foreach ($p in $obj.PSObject.Properties) {
        if ($p.Name -in $g.Excluir) { continue }
        $chave = if ($renomeadas.ContainsKey($p.Name)) { $renomeadas[$p.Name] } else { $p.Name }
        $vistos[$chave] = $true
        if ($dict.ContainsKey($chave)) { continue }
        $partes = New-Object System.Collections.Generic.List[string]
        foreach ($campo in @($g.Titulo, $g.Texto)) {
            if (-not $campo) { continue }
            $prop = $p.Value.PSObject.Properties[$campo]
            if (-not $prop -or [string]::IsNullOrWhiteSpace([string]$prop.Value)) { continue }
            $nomeDic = if ($campo -eq 'description') { 'Description' } else { $campo }
            $partes.Add("$nomeDic = '" + ([string]$prop.Value).Replace("'", "''") + "'")
        }
        $linhas.Add("    '$chave' = @{ " + ($partes -join '; ') + " }")
    }
    if ($linhas.Count) {
        $faltando += $linhas.Count
        Write-Host ""
        Write-Host "== $($g.Nome): $($linhas.Count) chave(s) sem tradução ==" -ForegroundColor Yellow
        $linhas | ForEach-Object { $_ }
    }
}

if ($Orphans) {
    $orfas = @($dict.Keys | Where-Object { -not $vistos.ContainsKey($_) } | Sort-Object)
    if ($orfas.Count) {
        Write-Host ""
        Write-Host "== dicionário: $($orfas.Count) chave(s) sem entrada correspondente na base ==" -ForegroundColor Yellow
        $orfas | ForEach-Object { "    $_" }
    }
}

if ($faltando -eq 0) {
    Write-Host "Cobertura do dicionário: completa ($($vistos.Count) chave(s) da base traduzidas)."
    exit 0
}
Write-Host ""
Write-Host "Faltam $faltando chave(s) em $dictPath" -ForegroundColor Yellow
exit 1
