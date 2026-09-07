#region ===== WinForge - auditoria de risco (aplicação) =====
function Initialize-WinForgeAudit {
    <#
    .SYNOPSIS
        Aplica a classificação de risco: remove entradas 'Removido', move 'Cuidado' para a categoria CUIDADO
        com o custo na descrição, marca 'risk' em todas e limpa presets. As chaves de jogo geradas da
        lista $sync.configs.wbgames (WPFTweaksWBGame<Jogo>) são Seguro.
    #>
    $audit = $sync.WinForgeAudit
    $caution = $sync.WinForgeCautionCategory
    $report = [System.Collections.Generic.List[object]]::new()

    # a categoria "avançada" da base perde os itens de risco (viraram Cuidado): o que sobra é Seguro.
    # 'y__' ordena antes de 'zz__', então a ordem final é Essential -> WinForge -> Avançado -> Avançado (CUIDADO).
    # Feito ANTES da classificação para que o relatório registre a categoria final de cada entrada.
    foreach ($p in $sync.configs.tweaks.PSObject.Properties) {
        if ($p.Value.category -eq 'z__Advanced Tweaks - CAUTION') {
            $p.Value | Add-Member -NotePropertyName category -NotePropertyValue 'y__Avançado' -Force
        }
    }

    foreach ($key in @($audit.Keys)) {
        $a = $audit[$key]
        $prop = $sync.configs.tweaks.PSObject.Properties[$key]
        if ($a.Class -eq 'Removido') {
            if ($prop) { $sync.configs.tweaks.PSObject.Properties.Remove($key) }
            foreach ($p in $sync.configs.preset.PSObject.Properties) { $p.Value = @($p.Value | Where-Object { $_ -ne $key }) }
            $report.Add([pscustomobject]@{ Key = $key; Content = $(if ($prop) { $prop.Value.Content } elseif ($a.Content) { $a.Content } else { $key }); Class = 'Removido'; Reason = $a.Reason; Category = '' })
            continue
        }
        if (-not $prop) { continue }   # entrada só existe depois dos serviços separados, ou foi filtrada
        $e = $prop.Value
        if ($a.Override) { foreach ($o in $a.Override.GetEnumerator()) { $e | Add-Member -NotePropertyName $o.Key -NotePropertyValue $o.Value -Force } }
        if ($a.Class -eq 'Cuidado') {
            $e | Add-Member -NotePropertyName category -NotePropertyValue $caution -Force
            if ($e.Description -notlike 'CUIDADO: *') { $e | Add-Member -NotePropertyName Description -NotePropertyValue ("CUIDADO: {0}. {1}" -f $a.Reason.TrimEnd('.'), $e.Description) -Force }
            foreach ($p in $sync.configs.preset.PSObject.Properties) { $p.Value = @($p.Value | Where-Object { $_ -ne $key }) }
        }
        $e | Add-Member -NotePropertyName risk -NotePropertyValue $a.Class.ToLower() -Force
        $report.Add([pscustomobject]@{ Key = $key; Content = $e.Content; Class = $a.Class; Reason = $a.Reason; Category = $e.category })
    }

    # prioridade de CPU por jogo (IFEO): reversível, sem custo - Seguro por padrão.
    # Conjunto EXATO derivado da lista de jogos, não o glob 'WPFTweaksWBGame*': o glob também casaria
    # com WPFTweaksWBGameDVR e com qualquer chave futura de nome parecido, dando a elas um 'seguro'
    # silencioso. Fora desse conjunto, quem não estiver na auditoria fica sem classe - e o -SelfTest
    # reprova ("tweaks sem classe de risco").
    $gameKeys = @{}
    foreach ($g in @($sync.configs.wbgames)) { $gameKeys["WPFTweaksWBGame$($g.Key)"] = $true }
    foreach ($p in $sync.configs.tweaks.PSObject.Properties) {
        if ($gameKeys.ContainsKey($p.Name) -and -not $p.Value.PSObject.Properties['risk']) {
            $p.Value | Add-Member -NotePropertyName risk -NotePropertyValue 'seguro' -Force
        }
    }

    $sync.WinForgeAuditReport = @($report | Sort-Object Class, Key)
    Write-WinForgeLog -Component "Audit" -Message ("Auditoria aplicada: {0} classificados, {1} removidos." -f $report.Count, @($report | Where-Object Class -eq 'Removido').Count)
}
#endregion
