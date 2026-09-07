#region ===== WinForge - regras de recomendação (motor) =====
# Avalia $sync.WinForgeRules contra o perfil do sistema e devolve o que recomendar, o que evitar e
# os avisos informativos. Nada aqui aplica tweak: só marca caixas quando o usuário pedir
# (Select-WinForgeRecommended).
# Regra quebrada (expressão inválida, campo que o perfil não trouxe) é ignorada e vai para o log:
# uma recomendação a menos é aceitável, uma exceção no meio da inicialização não é.

function Invoke-WinForgeRules {
    <#
    .SYNOPSIS
        Roda todas as regras contra um perfil e preenche $sync.Recommended, $sync.Discouraged e
        $sync.RuleInfos.
    .DESCRIPTION
        A primeira regra que cita uma chave é quem dá o motivo dela (as regras estão em ordem de
        generalidade: a base primeiro, o hardware específico depois). 'Avoid' vence 'Recommend':
        uma chave desaconselhada por qualquer regra sai da lista de recomendadas, mesmo que outra
        regra a tenha sugerido antes - o custo (bateria, HDD lento, host da VM) pesa mais que o ganho.
    .PARAMETER Profile
        Perfil devolvido por Get-WinForgeSystemProfile ou Get-WinForgeSimulatedProfile.
    .OUTPUTS
        @{ Recommended = <ordered>; Discouraged = <ordered>; Infos = <List[string]>; Fired = <string[]> }
    #>
    param([Parameter(Mandatory)]$Profile)

    # nome curto porque é ele que as expressões das regras enxergam ('$p.Storage.HasSSD')
    $p = $Profile

    $recommended = [ordered]@{}
    $discouraged = [ordered]@{}
    $infos = [System.Collections.Generic.List[string]]::new()
    $fired = [System.Collections.Generic.List[string]]::new()

    foreach ($rule in @($sync.WinForgeRules)) {
        if (-not $rule -or -not $rule.When) { continue }
        $hit = $false
        try {
            $hit = [bool](& ([scriptblock]::Create([string]$rule.When)))
        } catch {
            Write-WinForgeLog -Component "Rules" -Level "WARN" -Message "Regra '$($rule.Id)' ignorada: $($_.Exception.Message)"
            continue
        }
        if (-not $hit) { continue }
        $fired.Add([string]$rule.Id)

        foreach ($key in @($rule.Recommend)) {
            if (-not $key) { continue }
            if (-not $recommended.Contains($key)) { $recommended[$key] = [string]$rule.Reason }
        }
        foreach ($key in @($rule.Avoid)) {
            if (-not $key) { continue }
            if (-not $discouraged.Contains($key)) { $discouraged[$key] = [string]$rule.Reason }
        }

        if ($rule.Info) {
            try {
                $text = [string](& ([scriptblock]::Create([string]$rule.Info)))
                if (-not [string]::IsNullOrWhiteSpace($text)) { $infos.Add($text) }
            } catch {
                Write-WinForgeLog -Component "Rules" -Level "WARN" -Message "Info da regra '$($rule.Id)' ignorada: $($_.Exception.Message)"
            }
        }
    }

    # 'Avoid' vence 'Recommend' (a cópia de Keys é obrigatória: remover durante a enumeração estoura)
    foreach ($key in @($discouraged.Keys)) {
        if ($recommended.Contains($key)) { $recommended.Remove($key) }
    }

    $sync.Recommended = $recommended
    $sync.Discouraged = $discouraged
    $sync.RuleInfos = $infos

    Write-WinForgeLog -Component "Rules" -Message ("Regras: {0} disparadas -> {1} recomendados, {2} evitados, {3} infos." -f $fired.Count, $recommended.Count, $discouraged.Count, $infos.Count)

    return @{
        Recommended = $recommended
        Discouraged = $discouraged
        Infos       = $infos
        Fired       = @($fired)
    }
}

function Select-WinForgeRecommended {
    <#
    .SYNOPSIS
        Marca na interface as caixas recomendadas pelas regras, na aba pedida.
    .DESCRIPTION
        Só mexe em chave que virou CheckBox nesta máquina: o filtro de compatibilidade
        (Test-WinForgeBoostEntryCompatible) pode ter escondido a entrada, e nesse caso $sync[<chave>]
        não existe. Marcar IsChecked dispara o handler Checked, que é quem atualiza
        $sync.selectedTweaks - por isso aqui não se toca nessa lista.
    .PARAMETER Tab
        'Tweaks' (entradas sem tab 'Jogos'), 'Jogos' ou 'All' (as duas).
    .OUTPUTS
        Quantidade de caixas marcadas.
    #>
    param([ValidateSet('Tweaks', 'Jogos', 'All')][string]$Tab = 'All')

    $count = 0
    foreach ($key in @($sync.Recommended.Keys)) {
        $control = $sync[$key]
        if ($control -isnot [System.Windows.Controls.CheckBox]) { continue }

        $entry = $sync.configs.tweaks.$key
        $entryTab = 'Tweaks'
        if ($entry -and $entry.PSObject.Properties['tab'] -and [string]$entry.tab -eq 'Jogos') { $entryTab = 'Jogos' }
        if ($Tab -ne 'All' -and $entryTab -ne $Tab) { continue }

        $control.IsChecked = $true
        $count++
    }
    Write-WinForgeLog -Component "Rules" -Message "Recomendados marcados na aba $Tab`: $count."
    return $count
}
#endregion
