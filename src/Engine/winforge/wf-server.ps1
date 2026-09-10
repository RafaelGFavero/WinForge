#region ===== WinForge - servidor (IIS/AD) =====
# Ações dos botões da aba Servidor e a visibilidade das abas que dependem do tipo de Windows.
# Os comandos de verdade (w32tm, Defender, netsh, IIS, AD) chegam na tarefa 4; até lá o botão
# avisa que ainda não existe, em vez de falhar calado.

function Invoke-WinForgeServerCommand {
    <#
    .SYNOPSIS
        Executa um comando de leitura da aba Servidor pelo nome curto (placeholder da tarefa 2).
    #>
    param([string]$Name)

    [System.Windows.MessageBox]::Show("Comando '$Name' ainda não implementado.", "WinForge", "OK", "Information") | Out-Null
}

function Update-WinForgeTabVisibility {
    <#
    .SYNOPSIS
        Esconde as abas que não fazem sentido no Windows em uso.
    .DESCRIPTION
        Em servidor somem as entradas de consumidor - Win11ISO (WPFTab5BT), AppX e Jogos
        (WPFTab7BT) - e aparece a aba Servidor (WPFTab9BT). No cliente é o contrário: a aba
        Servidor some e as outras voltam.

        A aba AppX não tem botão na barra de navegação: quem leva até ela é o botão 'AppX Removal'
        (WPFAppxRemoval), dentro da aba Tweaks. Por isso ele está na lista - esconder um
        'WPFTab6BT' que não existe não tiraria a aba AppX do alcance de ninguém. O nome fica na
        lista assim mesmo, sem custo, para o dia em que a barra ganhar esse botão.

        Os dois lados são escritos de propósito: a função é chamada de novo pelo -SelfTest com
        $sync.IsServer forçado nos dois estados, e uma versão que só colapsa deixaria a aba errada
        escondida na segunda chamada.

        Só mexe nos controles de navegação, não nos TabItem: quem seleciona a aba é Invoke-WPFTab,
        pelo índice do botão, e o TabControl continua com todos os itens.
    .OUTPUTS
        Quantidade de controles de navegação alterados.
    #>
    $consumerTabs = @('WPFTab5BT', 'WPFTab6BT', 'WPFTab7BT', 'WPFAppxRemoval')
    $serverTab = 'WPFTab9BT'

    $consumerVisibility = if ($sync.IsServer) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $serverVisibility = if ($sync.IsServer) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }

    $changed = 0
    foreach ($name in $consumerTabs) {
        if ($null -eq $sync[$name]) { continue }
        if ($sync[$name].Visibility -ne $consumerVisibility) { $changed++ }
        $sync[$name].Visibility = $consumerVisibility
    }
    if ($null -ne $sync[$serverTab]) {
        if ($sync[$serverTab].Visibility -ne $serverVisibility) { $changed++ }
        $sync[$serverTab].Visibility = $serverVisibility
    }

    Write-WinForgeLog -Component "Server" -Message ("Abas ajustadas para {0}: {1} botão(ões) de navegação alterado(s)." -f $(if ($sync.IsServer) { "servidor" } else { "cliente" }), $changed)
    return $changed
}
#endregion
