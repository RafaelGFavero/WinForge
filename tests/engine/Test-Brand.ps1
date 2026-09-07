# Verifica que o arquivo gerado nao contem referencias de marca do projeto original.
# Sai com o numero de ocorrencias proibidas (limitado a 255, pois o exit code do Windows e um byte).
param([Parameter(Mandatory)][string]$File)
$forbidden = '(?i)christitus|chris\s*titus|\bCTT\b|sponsor|winutil'
$hits = @(Select-String -Path $File -Pattern $forbidden)
foreach ($h in $hits) { Write-Host ("  {0}: {1}" -f $h.LineNumber, $h.Line.Trim().Substring(0, [Math]::Min(120, $h.Line.Trim().Length))) }
Write-Host "Brand test: $($hits.Count) ocorrência(s) proibida(s) em $File"
exit ([Math]::Min($hits.Count, 255))
