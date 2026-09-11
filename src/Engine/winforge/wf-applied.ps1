#region ===== WinForge - estado já aplicado =====
# Descobre o que JÁ está aplicado neste sistema, mostra isso na linha e tira essas chaves do
# caminho de aplicação. O detector é o da base (Invoke-WinForgeCurrentSystem -CheckBox tweaks):
# ele compara o registro e os serviços de cada entrada com o valor que o tweak grava e devolve as
# chaves que já batem. Nada aqui escreve no sistema - é leitura de registro e de serviço.

function Test-WinForgeAppliedEligible {
    <#
    .SYNOPSIS
        Diz se a chave pode ser marcada como "já aplicada" (e, por isso, pulada na aplicação).
    .DESCRIPTION
        Toggle fica de fora porque o próprio interruptor já mostra o estado - e porque marcar um
        Toggle APLICA a mudança no clique, então ele nunca passa pelo botão Aplicar. Button e
        Combobox ficam de fora porque não têm estado de "aplicado": o primeiro é uma ação, e o
        segundo guarda uma escolha entre vários valores.
        Chave que não existe em $sync.configs.tweaks também é $false: sem entrada não há como
        afirmar que está aplicada, e no caminho da aplicação isso significa "não pule".

        Entrada com InvokeScript fica de fora pelo mesmo motivo, e é o caso mais perigoso dos três:
        o detector da base olha SÓ registro e serviço. WPFTweaksHiber grava duas chaves de registro
        E chama 'powercfg.exe /hibernate off'; com as chaves já gravadas e o comando nunca
        executado - outro programa, uma imagem corporativa, uma aplicação interrompida no meio -,
        o detector diria "aplicado" e nós pularíamos para sempre a metade que falta. Quem não
        consegue provar o estado inteiro não tem direito de pular.
    #>
    param([Parameter(Mandatory)][string]$Key)

    if ($Key -like 'WPFToggle*') { return $false }
    $entry = $sync.configs.tweaks.$Key
    if ($null -eq $entry) { return $false }
    if ($entry.InvokeScript) { return $false }
    return ([string]$entry.Type -notin @('Toggle', 'Button', 'Combobox'))
}

function Get-WinForgeAppliedTweaks {
    <#
    .SYNOPSIS
        Chaves de tweak que o sistema já tem aplicadas, segundo o detector da base.
    .DESCRIPTION
        Invoke-WinForgeCurrentSystem cria a unidade HKU: se ela não existir e lê registro e
        serviços - tudo leitura, e tudo sem exigir elevação. Falha ali não pode derrubar o
        diagnóstico nem o botão Aplicar: vira aviso no log e $null.

        $null e lista vazia são coisas DIFERENTES, e confundir as duas custava caro: lista vazia é
        "detectei e não achei nada aplicado", $null é "não sei". Devolvendo @() na falha, quem
        chama gravava a ignorância por cima do que já sabia - as marcas sumiam das linhas e o
        contador voltava a "0 já aplicados", com o sistema exatamente como estava. Agora $null quer
        dizer "mantenha o que você tinha", e ninguém é pulado enquanto a dúvida durar.

        O 2>$null existe porque o detector da base chama Get-Service sem -ErrorAction: serviço que
        não existe nesta máquina escreve no fluxo de erro sem interromper nada, e essas linhas só
        sujariam a saída do SelfTest.
    .OUTPUTS
        [string[]] com o que está aplicado, ou $null quando a detecção falha.
    #>
    try {
        # A falha só acontece de verdade em máquina com registro ou serviço fora do lugar; sem esta
        # porta o SelfTest não teria como provar que ela preserva o conjunto bom.
        if ($sync -and $sync.SelfTest -and $sync.WinForgeSelfTestAppliedFail) { throw "falha de detecção simulada pelo SelfTest" }
        return @(Invoke-WinForgeCurrentSystem -CheckBox tweaks 2>$null)
    } catch {
        Write-WinForgeLog -Component "Applied" -Level "WARN" -Message "Não foi possível detectar o que já está aplicado: $($_.Exception.Message)"
        return $null
    }
}

function Update-WinForgeAppliedFromSystem {
    <#
    .SYNOPSIS
        Detecta o que está aplicado e, SÓ se a detecção funcionar, regrava $sync.AppliedTweaks.
    .DESCRIPTION
        O par Get/Set aparecia solto em três lugares, e em todos eles a falha da detecção apagava o
        conjunto bom. Este é o único caminho que os três usam agora: detecção que falha devolve
        $null e não escreve nada em $sync - o que se sabia continua valendo até a próxima passada.
    .OUTPUTS
        O HashSet gravado, ou $null quando a detecção falhou.
    #>
    $detectado = Get-WinForgeAppliedTweaks
    if ($null -eq $detectado) { return $null }
    return Set-WinForgeAppliedTweaks -Keys $detectado
}

function Set-WinForgeAppliedTweaks {
    <#
    .SYNOPSIS
        Guarda em $sync.AppliedTweaks o conjunto de chaves já aplicadas.
    .DESCRIPTION
        Conjunto pronto e UMA escrita em $sync, como $sync.Recommended: montar aqui e atribuir
        depois evita mexer numa coleção que outra thread possa estar percorrendo.
        HashSet com comparador que ignora maiúsculas porque as chaves circulam como texto entre a
        config, os controles e o log, e ninguém garante a grafia no caminho.
    .OUTPUTS
        O HashSet gravado.
    #>
    param([string[]]$Keys)

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @($Keys)) {
        if ($key) { $null = $set.Add([string]$key) }
    }
    $sync.AppliedTweaks = $set
    return $set
}

function Select-WinForgeTweaksToApply {
    <#
    .SYNOPSIS
        Separa as chaves pedidas entre as que serão aplicadas e as que já estão aplicadas.
    .DESCRIPTION
        A detecção é REFEITA na hora, e não lida de $sync.AppliedTweaks: entre o diagnóstico da
        abertura e o clique em Aplicar o usuário pode ter desfeito coisas, e pular um tweak que
        deixou de estar aplicado seria pior que reaplicar um que ainda está.
        O ponto de restauração nunca é pulado - ele não é um estado do sistema, é uma ação, e quem
        decide se ele se repete é a trava de sessão ($sync.RestorePointCreated).

        Detecção que FALHA não apaga o que já se sabia: o conjunto local vira vazio (nada é pulado,
        que é o lado seguro do erro) e $sync.AppliedTweaks fica como estava, com as marcas nas
        linhas e o contador do checklist intactos.
    .PARAMETER Keys
        As chaves selecionadas na interface.
    .PARAMETER Applied
        Conjunto já detectado, para não pagar a detecção de novo (usado pelo SelfTest).
    .OUTPUTS
        @{ Apply = [string[]]; Skipped = [string[]] }
    #>
    param(
        [string[]]$Keys,
        $Applied
    )

    $set = if ($null -ne $Applied) { $Applied } else { Update-WinForgeAppliedFromSystem }
    if ($null -eq $set) { $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }

    $apply = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Keys)) {
        if (-not $key) { continue }
        $texto = [string]$key
        if ($texto -ne 'WPFTweaksRestorePoint' -and (Test-WinForgeAppliedEligible -Key $texto) -and $set -and $set.Contains($texto)) {
            $skipped.Add($texto)
        } else {
            $apply.Add($texto)
        }
    }

    return @{ Apply = @($apply); Skipped = @($skipped) }
}

function Get-WinForgeAppliedSuffix {
    <#
    .SYNOPSIS
        O TextBlock " · aplicado" de uma linha, se ela já tiver um.
    .DESCRIPTION
        A marca é reconhecida pela Tag ("WFApplied_<chave>") e não pela posição: a linha pode ter o
        "(?)" do link depois da caixa, e a próxima passada precisa achar a marca que ela mesma criou
        em vez de empilhar outra.
    #>
    param($Panel, [Parameter(Mandatory)][string]$Key)

    if ($null -eq $Panel -or $null -eq $Panel.Children) { return $null }
    foreach ($child in @($Panel.Children)) {
        if ($child -is [System.Windows.Controls.TextBlock] -and [string]$child.Tag -eq "WFApplied_$Key") { return $child }
    }
    return $null
}

function Update-WinForgeAppliedVisuals {
    <#
    .SYNOPSIS
        Escreve " · aplicado" ao lado das linhas cuja chave já está aplicada neste sistema.
    .DESCRIPTION
        Roda na thread da janela, logo depois de Update-WinForgeRecommendationVisuals e nos mesmos
        pontos que ela: fim de cada montagem de aba e fim de cada diagnóstico.
        Idempotente pelos dois lados. Cada passada começa DESFAZENDO o que a anterior escreveu
        (a chave pode ter saído do conjunto porque o usuário desfez o tweak), e a dica volta ao que
        era tirando o prefixo literal - sem guardar cópia. Guardar cópia seria errado aqui: a dica
        também é reescrita por Update-WinForgeRecommendationVisuals, e a cópia envelheceria entre
        as duas.
        O prefixo da dica fica NA FRENTE do que já estava, inclusive do "✔ Recomendado: ...":
        "já aplicado" é a informação que muda a decisão de marcar a caixa.
    .OUTPUTS
        Quantidade de linhas marcadas.
    #>
    $prefixo = "✔ Já aplicado neste sistema. "
    if ($null -eq $sync.WinForgeAppliedPainted) { $sync.WinForgeAppliedPainted = @{} }
    $pintadas = $sync.WinForgeAppliedPainted

    foreach ($key in @($pintadas.Keys)) {
        $pintadas.Remove($key)
        $control = $sync[$key]
        if ($control -isnot [System.Windows.Controls.CheckBox]) { continue }
        $panel = $control.Parent
        $velho = Get-WinForgeAppliedSuffix -Panel $panel -Key $key
        if ($velho) { $panel.Children.Remove($velho) }
        $dica = [string]$control.ToolTip
        if ($dica.StartsWith($prefixo)) { $control.ToolTip = $dica.Substring($prefixo.Length) }
    }

    $marcadas = 0
    foreach ($key in @($sync.AppliedTweaks)) {
        if (-not $key) { continue }
        $texto = [string]$key
        if (-not (Test-WinForgeAppliedEligible -Key $texto)) { continue }
        # o Border com a Tag é o que prova que a linha é desta chave e já foi montada
        if ($null -eq (Get-WinForgeRecoRow -Key $texto)) { continue }

        $control = $sync[$texto]
        $panel = $control.Parent
        if ($null -eq $panel -or $null -eq $panel.Children) { continue }

        if ($null -eq (Get-WinForgeAppliedSuffix -Panel $panel -Key $texto)) {
            $marca = New-Object System.Windows.Controls.TextBlock
            $marca.Tag = "WFApplied_$texto"
            $marca.Text = " · aplicado"
            $marca.VerticalAlignment = 'Center'
            $marca.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSize")
            $marca.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "LabelboxForegroundColor")
            $panel.Children.Add($marca) | Out-Null
        }

        $dica = [string]$control.ToolTip
        if (-not $dica.StartsWith($prefixo)) { $control.ToolTip = $prefixo + $dica }

        $pintadas[$texto] = $true
        $marcadas++
    }

    if ($marcadas -ne $sync.LastAppliedCount) {
        Write-WinForgeLog -Component "Applied" -Message "Linhas marcadas como já aplicadas: $marcadas."
        $sync.LastAppliedCount = $marcadas
    }
    return $marcadas
}

function Update-WinForgeAppliedAfterApply {
    <#
    .SYNOPSIS
        Repinta as linhas e o contador depois que o filtro de aplicação refez a detecção.
    .DESCRIPTION
        Select-WinForgeTweaksToApply REESCREVE $sync.AppliedTweaks com a detecção da hora do
        clique. Sem esta passada, as marcas " · aplicado" e o contador do checklist continuariam
        mostrando o resultado do diagnóstico da abertura - duas verdades diferentes na mesma tela,
        e a mais visível delas sendo a velha.
        Ela é chamada DUAS vezes por aplicação: uma com a verdade de antes (o que será pulado) e
        outra depois do laço, com a detecção refeita, para que o que acabou de ser aplicado apareça
        marcado sem esperar o próximo diagnóstico.
        Roda na thread da janela (quem chama de dentro do runspace usa Invoke-WPFUIThread com um
        scriptblock nascido na runspace principal).
        O contador vem depois e num try próprio: ele depende dos controles da aba Diagnóstico, que
        podem não existir ainda, e a marca nas linhas não pode se perder por causa disso.
    .OUTPUTS
        Quantidade de linhas marcadas.
    #>
    $marcadas = Update-WinForgeAppliedVisuals
    try { Update-WinForgeDiagRecommendationCount } catch {
        Write-WinForgeLog -Component "Applied" -Level "WARN" -Message "Contador do checklist não pôde ser refeito: $($_.Exception.Message)"
    }
    return $marcadas
}
#endregion
