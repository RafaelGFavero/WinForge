# Verifica que o arquivo gerado nao contem referencias de marca do projeto original.
# Sai com o numero de ocorrencias proibidas (limitado a 255, pois o exit code do Windows e um byte).
param([Parameter(Mandatory)][string]$File)
$forbidden = '(?i)christitus|chris\s*titus|\bCTT\b|sponsor|winutil'
$hits = @(Select-String -Path $File -Pattern $forbidden)
foreach ($h in $hits) { Write-Host ("  {0}: {1}" -f $h.LineNumber, $h.Line.Trim().Substring(0, [Math]::Min(120, $h.Line.Trim().Length))) }
Write-Host "Brand test: $($hits.Count) ocorrência(s) proibida(s) em $File"

# Mojibake: UTF-8 lido como ANSI em algum ponto da geracao (ex.: "não" -> "nÃ£o").
# "Ã" e "Â" sozinhos nao servem como padrao: sao letras validas em portugues ("ATENÇÃO", "CÂMARA").
# No mojibake elas vem SEMPRE seguidas de outro caractere nao-ASCII (o segundo byte do UTF-8 reinterpretado).
$mojibake = '[ÃÂ][^\x00-\x7F]|â€'
$mojiHits = @(Select-String -Path $File -Pattern $mojibake -CaseSensitive -AllMatches)
$mojiCount = 0
foreach ($m in $mojiHits) {
    $mojiCount += $m.Matches.Count
    Write-Host ("  {0}: {1}" -f $m.LineNumber, $m.Line.Trim().Substring(0, [Math]::Min(120, $m.Line.Trim().Length)))
}
Write-Host "Mojibake: $mojiCount ocorrência(s)"

exit ([Math]::Min($hits.Count + $mojiCount, 255))
