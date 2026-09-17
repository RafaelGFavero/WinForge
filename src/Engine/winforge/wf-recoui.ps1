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

function Set-WinForgeStatusBrush {
    <#
    .SYNOPSIS
        Liga uma propriedade de pincel a um token de cor de situação do tema, com plano B.
    .DESCRIPTION
        Referência de recurso, e não pincel pronto: a cor de "recomendado" muda entre o tema Claro
        e o Escuro, e quem troca de tema com a lista já desenhada não redesenha a lista - só os
        recursos da janela mudam. Se o token não existir (janela sem tema aplicado), cai no
        hexadecimal do plano B para nunca deixar o contorno invisível.
    #>
    param(
        [Parameter(Mandatory)]$Element,
        [Parameter(Mandatory)]$Property,
        [Parameter(Mandatory)][string]$Resource,
        [Parameter(Mandatory)][string]$Fallback
    )
    $Element.SetResourceReference($Property, $Resource)
    if ($null -eq $Element.GetValue($Property)) { $Element.SetValue($Property, (New-WinForgeRecoBrush -Hex $Fallback)) }
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
        # ClearValue, e não '= $null': a cor entrou como referência de recurso (Set-WinForgeStatusBrush)
        # e um nulo local por cima deixaria a linha presa nesse nulo na próxima pintura.
        $row.Border.ClearValue([System.Windows.Controls.Border]::BorderBrushProperty)
        $row.Tip.ToolTip = $orig[$key]
    }

    # Antes do primeiro diagnóstico as duas listas são $null: a janela abre e monta a aba Instalar
    # muito antes de o job terminar. @($null).Keys devolve uma chave nula, e indexar o plano com ela
    # estoura ("não é possível indexar em uma matriz nula") - daí as guardas. Sem regras não há o que
    # pintar, só o que despintar (o laço acima).
    # 'Evitar' depois de 'Recomendar': se uma chave estiver nas duas listas, quem fica é o laranja
    $plan = [ordered]@{}
    if ($sync.Recommended) {
        foreach ($key in @($sync.Recommended.Keys)) {
            if (-not $key) { continue }
            $plan[$key] = @{ Resource = "RecommendedColor"; Hex = "#22C55E"; Prefix = "✔ Recomendado: "; Reason = [string]$sync.Recommended[$key] }
        }
    }
    if ($sync.Discouraged) {
        foreach ($key in @($sync.Discouraged.Keys)) {
            if (-not $key) { continue }
            $plan[$key] = @{ Resource = "DiscouragedColor"; Hex = "#F59E0B"; Prefix = "⚠ Não recomendado neste sistema: "; Reason = [string]$sync.Discouraged[$key] }
        }
    }

    $painted = 0
    foreach ($key in @($plan.Keys)) {
        $row = Get-WinForgeRecoRow -Key $key
        if ($null -eq $row) { continue }

        $item = $plan[$key]
        Set-WinForgeStatusBrush -Element $row.Border -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Resource $item.Resource -Fallback $item.Hex
        $row.Border.BorderThickness = New-Object System.Windows.Thickness(1.5)

        if (-not $orig.ContainsKey($key)) { $orig[$key] = $row.Tip.ToolTip }
        $before = [string]$orig[$key]
        $head = $item.Prefix + $item.Reason
        $row.Tip.ToolTip = if ([string]::IsNullOrWhiteSpace($before)) { $head } else { "$head`n`n$before" }

        $painted++
    }

    # Caminho de volta do checklist do Diagnóstico: a caixa marcada aqui, na aba Ajustes/Jogos/
    # Servidor, tem de acender a linha correspondente lá. É aqui porque esta função roda no fim de
    # toda montagem de aba - é o primeiro momento em que os controles existem.
    # Um handler por controle, e não por passada: esta função também roda a cada diagnóstico, e um
    # handler novo por rodada escreveria N vezes na mesma linha.
    if ($null -eq $sync.WinForgeMirrorHooked) { $sync.WinForgeMirrorHooked = @{} }
    if ($sync.Recommended -and (Get-Command Sync-WinForgeRecommendationMirror -ErrorAction SilentlyContinue)) {
        foreach ($key in @($sync.Recommended.Keys)) {
            if (-not $key -or $sync.WinForgeMirrorHooked[$key]) { continue }
            $control = $sync[$key]
            if ($control -isnot [System.Windows.Controls.CheckBox]) { continue }
            if (Test-WinForgeRecommendationToggle -Key $key) { continue }
            $control.Add_Checked({
                [System.Object]$Sender = $args[0]
                Sync-WinForgeRecommendationMirror -Key ([string]$Sender.Name) -Checked $true
            })
            $control.Add_Unchecked({
                [System.Object]$Sender = $args[0]
                Sync-WinForgeRecommendationMirror -Key ([string]$Sender.Name) -Checked $false
            })
            $sync.WinForgeMirrorHooked[$key] = $true
        }
    }

    # Só registra quando o número muda: esta função roda no fim de cada montagem de aba e a cada
    # diagnóstico, e cinco linhas iguais no log só atrapalham quem lê depois.
    if ($painted -ne $sync.LastOutlineCount) {
        Write-WinForgeLog -Component "Rules" -Message "Contornos de recomendação aplicados: $painted linha(s)."
        $sync.LastOutlineCount = $painted
    }
    return $painted
}

function Set-WinForgeProfileProgress {
    <#
    .SYNOPSIS
        Escreve na barra de progresso da janela em nome do diagnóstico, se ela ainda for dele.
    .DESCRIPTION
        A barra é uma só para tweaks, AppX, Win11 Creator e diagnóstico. Enquanto um desses trabalhos
        estiver rodando ($sync.ProcessRunning), o diagnóstico fica calado: perder o texto dele é bem
        melhor que apagar o texto do trabalho que o usuário mandou fazer e está olhando.
        Com a janela fechando ($sync.WinForgeClosing) também não escreve: escrever é um
        Dispatcher.Invoke, e a thread do pool ficaria parada esperando um Dispatcher que já está
        desligando - exatamente o travamento que o handler de Closing existe para evitar.
        O rótulo escrito fica em $sync.ProfileJobLabel, para quem precisar saber o que está na barra.
    .OUTPUTS
        $true se escreveu, $false se cedeu a vez.
    #>
    param([string]$Label, [int]$Percent)

    if ($sync.WinForgeClosing -or $sync.ProcessRunning) { return $false }
    $sync.ProfileJobLabel = $Label
    Set-WinForgeTweaksProgressIndicator -Visible $true -Label $Label -Percent $Percent
    return $true
}

function Set-WinForgeDiagProgress {
    <#
    .SYNOPSIS
        Escreve na barra de progresso em nome de uma AÇÃO pedida pelo usuário na aba Diagnóstico
        (download de driver, instalação pelo Windows Update), mesmo com outro trabalho em andamento.
    .DESCRIPTION
        Set-WinForgeProfileProgress cede a vez enquanto $sync.ProcessRunning está ligado, e é o
        certo para o diagnóstico automático: ninguém pediu por ele, e apagar o texto do trabalho que
        o usuário está olhando seria pior que ficar calado. Uma ação de BOTÃO é o contrário disso -
        o usuário clicou, está esperando resposta, e sem esta função o resultado do download ia só
        para o log. Cedida a vez, escreve direto.
        A janela fechando continua sendo recusa: escrever é um Dispatcher.Invoke, e a thread do pool
        ficaria parada esperando um Dispatcher que já está desligando.
    .OUTPUTS
        $true se escreveu, $false se a janela está fechando.
    #>
    param([string]$Label, [int]$Percent)

    if (Set-WinForgeProfileProgress -Label $Label -Percent $Percent) { return $true }
    if ($sync.WinForgeClosing) { return $false }
    Set-WinForgeTweaksProgressIndicator -Visible $true -Label $Label -Percent $Percent
    return $true
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
        Começo e fim vão para o log ("Diagnóstico iniciado (job)." / "Diagnóstico pronto: ..."): sem
        isso não há como saber, depois, se o caminho do runspace chegou a rodar na janela real.
    .PARAMETER Force
        Roda mesmo com outro diagnóstico em andamento (usado pelo botão "Atualizar diagnóstico").
    .PARAMETER Synchronous
        Roda o mesmo corpo na thread atual, sem runspace (é assim que o -SelfTest exercita este
        caminho: sem janela mostrada não há Add_ContentRendered para disparar o job).
    .PARAMETER SkipNetwork
        Não consulta a internet atrás de driver mais novo (repassado a Get-WinForgeSystemProfile).
    #>
    param([switch]$Force, [switch]$Synchronous, [switch]$SkipNetwork)

    if ($sync.ProfileJobRunning -and -not $Force) {
        # Sem esta linha na barra o botão "Atualizar diagnóstico" pareceria morto: o pedido ignorado
        # só apareceria no log da sessão, que ninguém abre no meio do clique.
        Write-WinForgeLog -Component "Profile" -Message "Diagnóstico já em andamento; pedido ignorado."
        $null = Set-WinForgeProfileProgress -Label "Diagnóstico já em andamento - aguarde o fim da coleta." -Percent 50
        return
    }
    $sync.ProfileJobRunning = $true

    # O QUE ATUALIZA A JANELA PRECISA NASCER AQUI, e não dentro do corpo do job.
    # Um scriptblock guarda a runspace em que foi criado. O Dispatcher executa o do job na thread da
    # janela, mas ainda na runspace do pool - e essa runspace está parada em Dispatcher.Invoke,
    # esperando o callback terminar. Enquanto o callback só chama funções e mexe em propriedades,
    # tudo corre na própria thread e ninguém percebe; no primeiro pipeline (um Where-Object basta)
    # o motor precisa da runspace, que nunca fica livre - as duas threads travam para sempre, sem
    # exceção e sem linha no log. Foi assim que o diagnóstico morreu calado na janela real.
    # Esta função é chamada da thread da janela (ContentRendered, botão Atualizar, -SelfTest), então
    # o scriptblock criado aqui pertence à runspace principal, cuja pipeline roda nessa mesma thread:
    # aninhar nela é o que todo handler de clique já faz, e pipeline volta a ser permitido.
    $sync.WinForgeProfileUiRefresh = {
        # Nada pode escapar: exceção aqui volta pelo Dispatcher para o job, e o job morreria antes
        # de escrever a linha final - exatamente o silêncio que este bloco existe para evitar.
        try {
            Update-WinForgeRecommendationVisuals | Out-Null
            # Depois da dica de recomendação: o prefixo "já aplicado" entra na frente do que ela
            # escreveu, e a passada dela restaura a dica original de quem saiu das recomendações.
            if (Get-Command Update-WinForgeAppliedVisuals -ErrorAction SilentlyContinue) { Update-WinForgeAppliedVisuals | Out-Null }
            if (Get-Command Update-WinForgeDiagnosticsTab -ErrorAction SilentlyContinue) { Update-WinForgeDiagnosticsTab }
        } catch {
            Write-WinForgeLog -Component "Profile" -Level "ERROR" -Message "Diagnóstico: falha ao atualizar a interface -> $($_.Exception.Message)"
        }
    }

    # o corpo é um só: o runspace recebe o texto dele, o modo síncrono o executa aqui mesmo
    $wfBody = {
        param($wfSkipNetwork)
        try {
            Write-WinForgeLog -Component "Profile" -Message "Diagnóstico iniciado (job)."
            $null = Set-WinForgeProfileProgress -Label "Coletando informações do sistema..." -Percent 0
            $sync.Profile = if ($wfSkipNetwork) { Get-WinForgeSystemProfile -SkipNetwork } else { Get-WinForgeSystemProfile }
            $null = Set-WinForgeProfileProgress -Label "Avaliando recomendações..." -Percent 70
            $wfRules = Invoke-WinForgeRules -Profile $sync.Profile

            # O que JÁ está aplicado. Roda aqui, no job, porque é leitura de registro e de serviço
            # de todas as entradas e leva alguns segundos - na thread da janela isso apareceria
            # como travamento. Falha não derruba o diagnóstico nem apaga o conjunto anterior: a
            # função devolve $null e o que já se sabia continua valendo.
            $null = Set-WinForgeProfileProgress -Label "Conferindo o que já está aplicado..." -Percent 85
            $null = Update-WinForgeAppliedFromSystem

            # Janela fechando: Invoke-WPFUIThread é síncrono e esperaria por um Dispatcher que está
            # sendo desligado. Não há mais interface para atualizar - o job só termina de se despedir.
            if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeProfileUiRefresh }

            $wfDone = "Diagnóstico pronto: {0} recomendações, {1} a evitar, {2} infos, {3} erros de coleta." -f $wfRules.Recommended.Count, $wfRules.Discouraged.Count, $wfRules.Infos.Count, @($sync.Profile.Errors).Count
            # a barra fica no 100% com o resumo, sem esconder depois: um Start-Sleep aqui só serviria
            # para, quatro segundos mais tarde, apagar o texto de outro trabalho que tivesse começado
            $null = Set-WinForgeProfileProgress -Label $wfDone -Percent 100
            Write-WinForgeLog -Component "Profile" -Message $wfDone

            # A varredura da pasta de backup de permissões vem ENCADEADA aqui, e não no gancho da
            # abertura da janela, porque a barra é a MESMA. Pendurada lá, ela escrevia o aviso e o
            # "Coletando informações do sistema..." deste job o cobria em milissegundos: quem tinha
            # trezentos gigabytes presos numa pasta que só SYSTEM e Administradores apagam não via
            # nada, e o aviso ia só para o arquivo de log. Aqui ela é a ÚLTIMA a escrever.
            # Só relata - quem apaga é o botão, com a lista na tela e sob confirmação.
            $null = Show-WinForgeAclBackupSizeWarning
            # E o marcador de posse pendente, no mesmo gancho e DEPOIS da varredura: ele é mais
            # grave (uma pasta do Windows pode estar com o dono errado agora) e a barra guarda a
            # ÚLTIMA mensagem escrita. Só relata - devolver posse de pasta de sistema sozinho, na
            # abertura, sem ninguém olhando, é o oposto do que estes botões prometem.
            $null = Show-WinForgeAclOwnerPending

            # Os botões que mexem no driver de rede dependem do PERFIL (é ele que diz se a máquina
            # é virtual ou um servidor), então eles só podem ser pintados DEPOIS dele. As decisões
            # são tomadas AQUI, no job: levantar os fatos custa perto de meio segundo por botão
            # (adaptadores, identificadores de hardware e a varredura de INF), e meio segundo na
            # thread da janela é travamento visível. Para lá vai só o resultado.
            $wfNetDecisoes = @{}
            foreach ($wfNetAcao in @('WifiDriverReinstall', 'WifiDriverRestore', 'WifiDriverGeneric')) {
                try { $wfNetDecisoes[$wfNetAcao] = Test-WinForgeNetworkGuard -Action $wfNetAcao } catch { }
            }
            $sync.WinForgeNetworkGuards = $wfNetDecisoes
            # O bloco vem de $sync, escrito em escopo de arquivo: criado aqui dentro, ele nasceria
            # na runspace do pool e travaria a janela na primeira pipeline que rodasse nele.
            if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeNetworkButtonsCallback }
        } catch {
            # a barra fica visível com o erro: o usuário precisa saber que não há recomendação nenhuma
            $null = Set-WinForgeProfileProgress -Label "Diagnóstico falhou: $($_.Exception.Message)" -Percent 0
            Write-WinForgeLog -Component "Profile" -Level "ERROR" -Message "Diagnóstico falhou: $($_.Exception.Message)"
        } finally {
            $sync.ProfileJobRunning = $false
        }
    }

    if ($Synchronous) {
        & $wfBody $SkipNetwork.IsPresent
        return
    }

    # Se o despacho falhar (pool fechado, sem thread livre), o corpo do job nunca roda e o `finally`
    # dele também não: quem zera a trava é este catch. Sem ele $sync.ProfileJobRunning ficaria ligado
    # para sempre e o botão Atualizar nunca mais começaria um diagnóstico.
    try {
        Invoke-WPFRunspace -ScriptBlock $wfBody -ArgumentList $SkipNetwork.IsPresent | Out-Null
    } catch {
        $sync.ProfileJobRunning = $false
        Write-WinForgeLog -Component "Profile" -Level "ERROR" -Message "Diagnóstico não pôde começar: $($_.Exception.Message)"
        $null = Set-WinForgeProfileProgress -Label "Diagnóstico não pôde começar: $($_.Exception.Message)" -Percent 0
    }
}
#endregion
