# Inventário de texto em inglês no motor gerado.
#
# Lê dist\engine\WinForge.ps1 (o arquivo que o usuário realmente executa, já com todas as injeções
# e o rename aplicados) e lista o que ainda está em inglês em três frentes:
#   1. atributos do XAML ($inputXML): Content=, Text=, Header=, ToolTip=, Placeholder=, Watermark=
#   2. texto solto entre tags do XAML (o miolo de <TextBlock>...</TextBlock>)
#   3. mensagens de código: [System.Windows.MessageBox]::Show(...) e Write-Host (primeiro argumento)
#
# O filtro é heurístico: a linha só entra na lista se contiver alguma palavra da lista abaixo como
# palavra inteira. Serve para achar o que traduzir, não para provar que acabou - quem prova é a
# trava Test-WinForgeEnglishLeftovers do -SelfTest.
param(
    [string]$EnginePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "dist\engine\WinForge.ps1"),
    # Mostra também o que já está em português (útil para conferir se o filtro está comendo linha).
    [switch]$All,
    # Só as seções pedidas: Xaml, Inner, Code.
    [ValidateSet('Xaml', 'Inner', 'Code')]
    [string[]]$Section = @('Xaml', 'Inner', 'Code')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $EnginePath)) { throw "Motor não encontrado: $EnginePath (rode src\Engine\build.ps1 antes)" }

$englishWords = @(
    'the', 'to', 'and', 'for', 'with', 'your', 'this', 'select', 'please', 'click', 'install',
    'enable', 'disable', 'remove', 'run', 'reset', 'update', 'apply', 'restore', 'default', 'all',
    'none', 'file', 'folder', 'browse', 'ready', 'done', 'failed', 'error', 'warning', 'success',
    'log', 'status', 'step',
    # segunda leva: termos que aparecem nos rótulos do WinUtil e que a lista mínima não pegava
    # ("Recommended Selections:", "Standard", "AppX Removal", "Package Manager"...).
    'recommended', 'selection', 'selections', 'selected', 'standard', 'minimal', 'advanced',
    'clear', 'get', 'show', 'installed', 'uninstall', 'upgrade', 'package', 'manager', 'collapse',
    'expand', 'apps', 'free', 'open', 'source', 'software', 'page', 'download', 'mount', 'verify',
    'inject', 'refresh', 'save', 'write', 'erase', 'back', 'settings', 'minimize', 'close',
    'maximize', 'font', 'scaling', 'small', 'large', 'offline', 'mode', 'internet', 'connection',
    'import', 'export', 'actions', 'features', 'fixes', 'legacy', 'panels', 'remote', 'access',
    'performance', 'plans', 'essential', 'tweaks', 'customize', 'preferences', 'caution', 'note',
    'undo', 'dark', 'light', 'drive', 'edition', 'output', 'modify', 'creator', 'profiles'
)
$englishRegex = [regex]("(?i)\b(" + ($englishWords -join '|') + ")\b")

function Test-English([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    # Referência de recurso ({DynamicResource ...}), binding e caminho não são texto de interface.
    if ($s -match '^\s*\{') { return $false }
    return $englishRegex.IsMatch($s)
}

$lines = [System.IO.File]::ReadAllLines($EnginePath, [System.Text.Encoding]::UTF8)

# ---- região do XAML: de "$inputXML = @'" até o "'@" que fecha
$xamlStart = -1; $xamlEnd = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($xamlStart -lt 0 -and $lines[$i] -match '^\$inputXML\s*=\s*@''') { $xamlStart = $i; continue }
    if ($xamlStart -ge 0 -and $lines[$i] -match "^'@\s*$") { $xamlEnd = $i; break }
}
if ($xamlStart -lt 0 -or $xamlEnd -lt 0) { throw "Não achei a região do `$inputXML no motor gerado." }

$attrRegex  = [regex]'(?<attr>Content|Text|Header|ToolTip|Placeholder|Watermark)\s*=\s*"(?<val>[^"]*)"'
$msgRegex   = [regex]'\[System\.Windows\.MessageBox\]::Show\(\s*(?:"(?<val>[^"]*)"|''(?<val>[^'']*)'')'
$hostRegex  = [regex]'Write-Host\s+(?:"(?<val>[^"]*)"|''(?<val>[^'']*)'')'

$hits = New-Object System.Collections.Generic.List[object]

if ('Xaml' -in $Section) {
    for ($i = $xamlStart; $i -le $xamlEnd; $i++) {
        foreach ($m in $attrRegex.Matches($lines[$i])) {
            $v = $m.Groups['val'].Value
            if ($All -or (Test-English $v)) {
                $hits.Add([pscustomobject]@{ Kind = "XAML $($m.Groups['attr'].Value)"; Line = $i + 1; Value = $v })
            }
        }
    }
}

if ('Inner' -in $Section) {
    # O miolo de um TextBlock costuma ocupar várias linhas ("Note: Hover over items..."), então o
    # texto entre tags é procurado na região inteira de uma vez, não linha a linha.
    $xamlText = ($lines[$xamlStart..$xamlEnd] -join "`n")
    $xamlText = [regex]::Replace($xamlText, '(?s)<!--.*?-->', '')
    foreach ($m in [regex]::Matches($xamlText, '(?s)>(?<val>[^<>]+)<')) {
        $v = ($m.Groups['val'].Value -replace '\s+', ' ').Trim()
        if ($All -or (Test-English $v)) {
            $lineNo = $xamlStart + 1 + ([regex]::Matches($xamlText.Substring(0, $m.Index), "`n")).Count
            $hits.Add([pscustomobject]@{ Kind = 'XAML texto'; Line = $lineNo; Value = $v })
        }
    }
}

if ('Code' -in $Section) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ge $xamlStart -and $i -le $xamlEnd) { continue }
        $line = $lines[$i]
        foreach ($m in $msgRegex.Matches($line)) {
            $v = $m.Groups['val'].Value
            if ($All -or (Test-English $v)) { $hits.Add([pscustomobject]@{ Kind = 'MessageBox'; Line = $i + 1; Value = $v }) }
        }
        foreach ($m in $hostRegex.Matches($line)) {
            $v = $m.Groups['val'].Value
            if ($All -or (Test-English $v)) { $hits.Add([pscustomobject]@{ Kind = 'Write-Host'; Line = $i + 1; Value = $v }) }
        }
    }
}

$hits | Group-Object Kind | Sort-Object Name | ForEach-Object {
    Write-Host ""
    Write-Host "== $($_.Name) ($($_.Count)) ==" -ForegroundColor Cyan
    $_.Group | ForEach-Object { "{0,6}  {1}" -f $_.Line, $_.Value }
}
Write-Host ""
Write-Host "Total: $($hits.Count) ocorrência(s) em $EnginePath"
