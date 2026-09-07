#region ===== WinForge - recomendações na interface =====
# Pinta o contorno das linhas recomendadas (verde) e desaconselhadas (laranja) e prefixa a dica de
# cada uma com o motivo que veio das regras. Nada aqui aplica tweak: é só sinalização visual.
# O contorno mora num Border que embrulha a linha (injetado em Invoke-WPFUIElements pelo build):
# mexer no DockPanel/StackPanel da linha estragaria o layout da busca, que os esconde por Visibility.

function Get-WinForgeRecoRow {
    <#
    .SYNOPSIS
        Devolve o Border da linha e o controle que carrega a dica, para uma chave de tweak.
    .DESCRIPTION
        Só existe linha para chave que virou CheckBox nesta máquina (o filtro de compatibilidade pode
        ter escondido a entrada) e cuja aba já foi montada - antes disso $sync[<chave>] é nulo.
        O Border é reconhecido pela Tag (a chave): subir a árvore sem esse conforto acabaria no Border
        da categoria, que não é nosso e não deve ganhar cor.
    .OUTPUTS
        @{ Border = <Border>; Tip = <CheckBox|Label> } ou $null quando a linha não existe.
    #>
    param([Parameter(Mandatory)][string]$Key)

    $control = $sync[$Key]
    if ($control -isnot [System.Windows.Controls.CheckBox]) { return $null }

    $row = $control.Parent
    if ($null -eq $row) { return $null }

    $border = $null
    $node = $row
    for ($i = 0; $i -lt 3 -and $null -ne $node; $i++) {
        if ($node -is [System.Windows.Controls.Border] -and [string]$node.Tag -eq $Key) { $border = $node; break }
        $node = $node.Parent
    }
    if ($null -eq $border) { return $null }

    # o toggle põe a descrição no Label ao lado da chave; a caixa comum guarda a dica nela mesma
    $tip = $control
    if ($row -is [System.Windows.Controls.DockPanel]) {
        $label = @($row.Children | Where-Object { $_ -is [System.Windows.Controls.Label] })[0]
        if ($label) { $tip = $label }
    }

    return @{ Border = $border; Tip = $tip }
}

function New-WinForgeRecoBrush {
    <#
    .SYNOPSIS
        Pincel congelado a partir de uma cor hexadecimal (congelado = pode cruzar threads sem cópia).
    #>
    param([Parameter(Mandatory)][string]$Hex)
    $color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $brush = New-Object System.Windows.Media.SolidColorBrush($color)
    $brush.Freeze()
    return $brush
}

function Update-WinForgeRecommendationVisuals {
    <#
    .SYNOPSIS
        Aplica contorno e prefixo de dica nas linhas recomendadas/desaconselhadas pelas regras.
    .DESCRIPTION
        Idempotente: a dica original de cada linha é guardada uma vez em $sync.WinForgeTooltipOrig e
        toda execução começa restaurando o que já foi pintado antes - sem isso, um segundo diagnóstico
        empilharia prefixos e a linha que deixou de ser recomendada ficaria verde para sempre.
        Rodar antes das abas existirem é normal (a janela abre na aba Instalar): chave sem controle
        é ignorada, e a chamada no fim de Initialize-WinForgeTabContent pinta a aba quando ela nascer.
    .OUTPUTS
        Quantidade de linhas pintadas.
    #>
    if ($null -eq $sync.WinForgeTooltipOrig) { $sync.WinForgeTooltipOrig = @{} }
    $orig = $sync.WinForgeTooltipOrig

    # restaura tudo que já foi pintado (a linha pode ter saído das recomendações neste diagnóstico)
    foreach ($key in @($orig.Keys)) {
        $row = Get-WinForgeRecoRow -Key $key
        if ($null -eq $row) { continue }
        $row.Border.BorderThickness = New-Object System.Windows.Thickness(0)
        $row.Border.BorderBrush = $null
        $row.Tip.ToolTip = $orig[$key]
    }

    # 'Evitar' depois de 'Recomendar': se uma chave estiver nas duas listas, quem fica é o laranja
    $plan = [ordered]@{}
    foreach ($key in @($sync.Recommended.Keys)) {
        $plan[$key] = @{ Hex = "#2E7D32"; Prefix = "✔ Recomendado: "; Reason = [string]$sync.Recommended[$key] }
    }
    foreach ($key in @($sync.Discouraged.Keys)) {
        $plan[$key] = @{ Hex = "#EF6C00"; Prefix = "⚠ Não recomendado neste sistema: "; Reason = [string]$sync.Discouraged[$key] }
    }

    $brushes = @{}
    $painted = 0
    foreach ($key in @($plan.Keys)) {
        $row = Get-WinForgeRecoRow -Key $key
        if ($null -eq $row) { continue }

        $item = $plan[$key]
        if (-not $brushes.ContainsKey($item.Hex)) { $brushes[$item.Hex] = New-WinForgeRecoBrush -Hex $item.Hex }
        $row.Border.BorderBrush = $brushes[$item.Hex]
        $row.Border.BorderThickness = New-Object System.Windows.Thickness(1.5)

        if (-not $orig.ContainsKey($key)) { $orig[$key] = $row.Tip.ToolTip }
        $before = [string]$orig[$key]
        $head = $item.Prefix + $item.Reason
        $row.Tip.ToolTip = if ([string]::IsNullOrWhiteSpace($before)) { $head } else { "$head`n`n$before" }

        $painted++
    }

    Write-WinForgeLog -Component "Rules" -Message "Contornos de recomendação aplicados: $painted linha(s)."
    return $painted
}

function Start-WinForgeProfileJob {
    <#
    .SYNOPSIS
        Coleta o perfil do sistema e roda as regras fora da thread da interface, atualizando os
        contornos e a aba de diagnóstico quando terminar.
    .DESCRIPTION
        Chamada logo depois que a janela aparece: o perfil leva alguns segundos (CIM, disco, rede) e
        travaria a interface se rodasse na thread dela. Um diagnóstico por vez - o segundo pedido é
        ignorado, porque dois deles gravando $sync.Recommended ao mesmo tempo deixariam os contornos
        e a aba de diagnóstico discordando entre si.
    .PARAMETER Force
        Roda mesmo com outro diagnóstico em andamento (usado pelo botão "Atualizar diagnóstico").
    #>
    param([switch]$Force)

    if ($sync.ProfileJobRunning -and -not $Force) {
        Write-WinForgeLog -Component "Profile" -Message "Diagnóstico já em andamento; pedido ignorado."
        return
    }
    $sync.ProfileJobRunning = $true

    Invoke-WPFRunspace -ScriptBlock {
        try {
            Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Coletando informações do sistema..." -Percent 0
            $sync.Profile = Get-WinForgeSystemProfile
            Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Avaliando recomendações..." -Percent 70
            $null = Invoke-WinForgeRules -Profile $sync.Profile

            Invoke-WPFUIThread {
                Update-WinForgeRecommendationVisuals
                if (Get-Command Update-WinForgeDiagnosticsTab -ErrorAction SilentlyContinue) { Update-WinForgeDiagnosticsTab }
            }

            $done = "Diagnóstico pronto: {0} recomendações, {1} a evitar" -f @($sync.Recommended.Keys).Count, @($sync.Discouraged.Keys).Count
            Set-WinForgeTweaksProgressIndicator -Visible $true -Label $done -Percent 100
            Write-WinForgeLog -Component "Profile" -Message $done
            Start-Sleep -Seconds 4
            Set-WinForgeTweaksProgressIndicator -Visible $false -Label "" -Percent 0
        } catch {
            # a barra fica visível com o erro: o usuário precisa saber que não há recomendação nenhuma
            Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Diagnóstico falhou: $($_.Exception.Message)" -Percent 0
            Write-WinForgeLog -Component "Profile" -Level "ERROR" -Message "Diagnóstico falhou: $($_.Exception.Message)"
        } finally {
            $sync.ProfileJobRunning = $false
        }
    } | Out-Null
}
#endregion
