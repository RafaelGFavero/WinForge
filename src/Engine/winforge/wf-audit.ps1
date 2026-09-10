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

    # A categoria "avançada" da base chega aqui já como 'y__Avançado': quem renomeia é o dicionário
    # de tradução (config\wf-i18n-strings.ps1), no build. Ela perde os itens de risco (viraram
    # Cuidado), então o que sobra é Seguro. 'y__' ordena antes de 'zz__', e a ordem final na tela
    # fica Ajustes essenciais -> WinForge -> Avançado -> Avançado (CUIDADO).
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

function Test-WinForgeEnglishLeftovers {
    <#
    .SYNOPSIS
        Conta quantos termos da lista $sync.WinForgeEnglishSweep sobraram em inglês num texto.
    .DESCRIPTION
        Trava de idioma do -SelfTest. Quem traduz é o dicionário do build
        (config\wf-i18n-strings.ps1); esta função é a prova de que traduziu - e de que uma
        atualização do arquivo base não trouxe o rótulo em inglês de volta.

        A comparação ignora maiúsculas de propósito: "Recommended Selections" e "recommended
        selections" são o mesmo deslize.

        Devolve o número de termos encontrados (0 = tudo em português) e escreve uma linha [ERRO]
        para cada um, no formato que o -SelfTest já usa.
    .PARAMETER Text
        Texto a varrer: o XAML gerado ($inputXML) ou o texto visível das configurações.
    .PARAMETER Where
        Nome do lugar varrido, só para a mensagem de erro ficar acionável.
    .PARAMETER Xaml
        Trata $Text como XAML e varre só o que aparece na tela: valores de Content, Text, Header e
        ToolTip mais o miolo entre tags. Sem isso a varredura acusaria o que NÃO é interface -
        Name="WPFWin11ISOBrowseButton" (nome de controle, usado pelo código) e comentários como
        "STEP 1 : Select Windows 11 ISO" seriam erro de idioma sem nada aparecer em inglês na tela.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Where,
        [switch]$Xaml
    )
    if ($Xaml) {
        $semComentario = [regex]::Replace($Text, '(?s)<!--.*?-->', ' ')
        $visivel = New-Object System.Text.StringBuilder
        foreach ($m in [regex]::Matches($semComentario, '(?:Content|Text|Header|ToolTip)\s*=\s*"([^"]*)"')) {
            [void]$visivel.AppendLine($m.Groups[1].Value)
        }
        foreach ($m in [regex]::Matches($semComentario, '(?s)>([^<>]+)<')) {
            [void]$visivel.AppendLine($m.Groups[1].Value)
        }
        $Text = $visivel.ToString()
    }
    $achados = 0
    foreach ($termo in @($sync.WinForgeEnglishSweep)) {
        if ([string]::IsNullOrEmpty($termo)) { continue }
        if ($Text.IndexOf($termo, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Host "  [ERRO] inglês na interface ($Where): '$termo'" -ForegroundColor Red
            $achados++
        }
    }
    return $achados
}
#endregion
