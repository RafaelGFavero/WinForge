#region ===== WinForge - servidor (IIS/AD) =====
# Ações dos botões da aba Servidor, a visibilidade das abas que dependem do tipo de Windows e o
# ajuste do IIS (pools, sites e configuração do servidor) com backup dos valores anteriores.
# Os botões de comando (w32tm, Defender, netsh, dcdiag, repadmin, DNS, NTDS) só LEEM: rodam a
# ferramenta, guardam a saída num arquivo na pasta de logs e mostram o texto numa janela.

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

# ---------------------------------------------------------------------------
# Comandos de leitura da aba Servidor (Servidor e Active Directory)
#
# Todo botão desta aba cai em Invoke-WinForgeServerCommand -Name <nome curto>. O nome curto é a
# única coisa que a interface conhece: o QUE roda mora na tabela de Get-WinForgeServerCommand, o
# COMO roda mora no núcleo síncrono (Invoke-WinForgeServerCommandCore) e a janela que mostra o
# resultado é montada em código, sem XAML.
#
# Nada aqui altera o servidor. É de propósito: dcdiag, repadmin e afins são o primeiro lugar onde
# se olha num servidor com problema, e um botão que só lê pode ser clicado em produção sem medo.
# ---------------------------------------------------------------------------

function Get-WinForgeServerCommand {
    <#
    .SYNOPSIS
        Tabela dos comandos de leitura da aba Servidor: título, texto do comando e ferramenta exigida.
    .DESCRIPTION
        Separada da execução porque é dado puro: o -SelfTest confere os sete comandos (título, texto
        que compila, ferramenta exigida) em qualquer máquina, sem rodar nenhum deles.

        'Requires' é o nome de um executável ('dcdiag.exe') ou de um cmdlet ('Get-DnsServerScavenging')
        resolvido com Get-Command. Ausente, o comando não roda: vira uma frase dizendo qual ferramenta
        falta. É o caso normal - dcdiag e repadmin só existem com as ferramentas de AD instaladas, e
        Get-DnsServerScavenging só com o papel de DNS.
    .OUTPUTS
        Hashtable com Title, Command (texto do comando) e Requires (ou $null).
    #>
    param([Parameter(Mandatory)][string]$Name)

    switch ($Name) {
        'TimeCheck' {
            return @{
                Title    = 'Fonte de horário (w32tm)'
                Command  = 'w32tm /query /status; w32tm /query /source; w32tm /query /configuration'
                Requires = 'w32tm.exe'
            }
        }
        'DefenderExclusions' {
            return @{
                Title    = 'Exclusões do Microsoft Defender'
                Command  = 'Get-MpPreference | Select-Object ExclusionPath, ExclusionProcess, ExclusionExtension | Format-List'
                Requires = 'Get-MpPreference'
            }
        }
        'TcpShow' {
            return @{
                Title    = 'Parâmetros TCP (netsh)'
                Command  = 'netsh int tcp show global'
                Requires = 'netsh.exe'
            }
        }
        'Dcdiag' {
            return @{
                Title    = 'Diagnóstico do controlador de domínio (dcdiag /q)'
                Command  = 'dcdiag /q'
                Requires = 'dcdiag.exe'
            }
        }
        'ReplSummary' {
            return @{
                Title    = 'Resumo de replicação (repadmin /replsummary)'
                Command  = 'repadmin /replsummary'
                Requires = 'repadmin.exe'
            }
        }
        'DnsScavenging' {
            return @{
                Title    = 'Limpeza de registros DNS (scavenging)'
                Command  = 'Get-DnsServerScavenging | Format-List'
                Requires = 'Get-DnsServerScavenging'
            }
        }
        'NtdsLocation' {
            # Sem 'Requires': quem responde é o registro, que existe em qualquer Windows. Num
            # computador que não é controlador de domínio as chaves simplesmente não estão lá, e a
            # própria função diz isso - não é erro, é a resposta.
            return @{
                Title    = 'Onde estão NTDS e SYSVOL'
                Command  = 'Get-WinForgeServerNtdsLocationText'
                Requires = $null
            }
        }
    }
    throw "Comando de servidor desconhecido: '$Name'."
}

function Get-WinForgeServerNtdsLocationText {
    <#
    .SYNOPSIS
        Onde ficam o banco do AD (ntds.dit), os logs de transação e o SYSVOL, lidos do registro.
    .DESCRIPTION
        A pergunta atrás deste botão é sempre a mesma: "isso está no disco do sistema?". Banco e logs
        de transação no mesmo disco do Windows é a receita de um DC lento e de um C: que enche - por
        isso cada caminho sai marcado quando começa por %SystemDrive%.

        O nome NTDS vem do serviço; os caminhos moram em HKLM\...\Services\NTDS\Parameters, e o do
        SYSVOL em Netlogon\Parameters. Ler o registro não exige as ferramentas de AD instaladas.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    $ntds = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
    $netlogon = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    $itens = @(
        @('Banco de dados do AD (ntds.dit)', $ntds, 'DSA Database file'),
        @('Pasta de trabalho do NTDS', $ntds, 'DSA Working Directory'),
        @('Logs de transação do NTDS', $ntds, 'Database log files path'),
        @('SYSVOL', $netlogon, 'SysVol')
    )

    $linhas = New-Object System.Collections.Generic.List[string]
    foreach ($item in $itens) {
        $valor = $null
        try { $valor = (Get-ItemProperty -LiteralPath $item[1] -Name $item[2] -ErrorAction Stop).($item[2]) } catch { $valor = $null }
        $texto = [string]$valor
        if ([string]::IsNullOrWhiteSpace($texto)) { continue }
        $marca = ''
        if ($env:SystemDrive -and $texto.StartsWith($env:SystemDrive, [System.StringComparison]::OrdinalIgnoreCase)) { $marca = ' (disco do sistema)' }
        $linhas.Add(("{0}: {1}{2}" -f $item[0], $texto, $marca))
    }

    if ($linhas.Count -eq 0) { return "Este computador não é controlador de domínio (chaves NTDS ausentes)." }
    $linhas.Add('')
    $linhas.Add("Disco do sistema: $env:SystemDrive - banco e logs de transação fora dele costumam render um controlador de domínio mais rápido.")
    return ($linhas -join "`r`n")
}

function Test-WinForgeServerRequirement {
    <#
    .SYNOPSIS
        Diz se a ferramenta exigida por um comando existe nesta máquina. Sem exigência, é sempre sim.
    #>
    param([string]$Requires)

    if ([string]::IsNullOrWhiteSpace($Requires)) { return $true }
    return [bool](Get-Command $Requires -ErrorAction SilentlyContinue)
}

function Get-WinForgeServerOutputPath {
    <#
    .SYNOPSIS
        Caminho do arquivo de saída de um comando: server-<Nome>-<aaaaMMdd-HHmmss>.txt na pasta de logs.
    .DESCRIPTION
        A pasta é a mesma da sessão ($sync.logPath): quem for pedir ajuda já sabe olhar lá, e não
        aparece uma segunda pasta só para isso. Com os segundos no nome, dois cliques seguidos não se
        sobrescrevem.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $dir = $null
    if ($null -ne $sync -and $sync.logPath) { $dir = Split-Path -Parent $sync.logPath }
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = Join-Path $env:LocalAppData 'WinForge\logs' }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir ("server-{0}-{1}.txt" -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss')))
}

function Invoke-WinForgeServerCommandCore {
    <#
    .SYNOPSIS
        Roda um comando de leitura da aba Servidor e grava a saída num arquivo. Síncrono, não mostra nada.
    .DESCRIPTION
        É o miolo do botão, sem interface nenhuma: é o que roda dentro do runspace e é o que o
        -SelfTest consegue exercitar sem abrir janela.

        Três decisões moram aqui:

        1. Ferramenta ausente NÃO é exceção. w32tm existe em qualquer Windows, dcdiag e repadmin não:
           o texto vira "Ferramenta 'x' não encontrada neste sistema.", o arquivo é gravado do mesmo
           jeito e o retorno tem a mesma forma do caso bem-sucedido. Quem chama nunca precisa de dois
           caminhos.
        2. '2>&1' antes do Out-String: dcdiag e repadmin escrevem parte do que interessa no fluxo de
           erro, e sem isso a janela sairia vazia justamente quando há problema. -Width 200 evita que
           uma tabela larga volte quebrada no meio.
        3. A code page da saída. w32tm, netsh, dcdiag e repadmin escrevem em OEM (850/437 no Brasil);
           o PowerShell decodifica pelo [Console]::OutputEncoding, que costuma estar em outra coisa -
           e toda palavra acentuada chega embaralhada. A troca é PROCESSO INTEIRO, então a janela é
           a menor possível: muda, roda o comando, devolve no finally. Nenhuma outra thread do
           programa lê saída de executável, e o próprio comando roda um de cada vez.
    .OUTPUTS
        Hashtable com Name, Title, Text (o que vai para a janela) e Path (arquivo gravado, ou $null).
    #>
    param([Parameter(Mandatory)][string]$Name)

    $cmd = Get-WinForgeServerCommand -Name $Name
    $inicio = Get-Date

    if (-not (Test-WinForgeServerRequirement -Requires $cmd.Requires)) {
        $texto = "Ferramenta '$($cmd.Requires)' não encontrada neste sistema."
        Write-WinForgeLog -Component "Server" -Level "WARN" -Message "$Name não executado: $texto"
    } else {
        $encodingAnterior = $null
        try {
            try {
                $encodingAnterior = [Console]::OutputEncoding
                [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
            } catch {
                $encodingAnterior = $null
            }
            $texto = & ([scriptblock]::Create($cmd.Command)) 2>&1 | Out-String -Width 200
        } catch {
            $texto = "Falha ao executar o comando: $($_.Exception.Message)"
            Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "$Name falhou: $($_.Exception.Message)"
        } finally {
            if ($null -ne $encodingAnterior) { try { [Console]::OutputEncoding = $encodingAnterior } catch { } }
        }
        # 'dcdiag /q' só fala quando encontra problema: saída vazia é a boa notícia, e uma janela em
        # branco pareceria o comando ter falhado.
        if ($Name -eq 'Dcdiag' -and [string]::IsNullOrWhiteSpace($texto)) { $texto = "Sem erros reportados pelo dcdiag." }
    }

    $texto = [string]$texto
    $arquivo = $null
    try {
        $arquivo = Get-WinForgeServerOutputPath -Name $Name
        $cabecalho = "WinForge - $($cmd.Title)`r`n$((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) - $env:COMPUTERNAME`r`nComando: $($cmd.Command)`r`n" + ('-' * 78)
        Set-Content -LiteralPath $arquivo -Value ($cabecalho + "`r`n" + $texto) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-WinForgeLog -Component "Server" -Level "WARN" -Message "$Name`: saída não pôde ser gravada em '$arquivo' -> $($_.Exception.Message)"
        $arquivo = $null
    }

    $segundos = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-WinForgeLog -Component "Server" -Message "$Name concluído em $segundos s: $($texto.Length) caractere(s)$(if ($arquivo) { " em $arquivo" } else { ' (sem arquivo)' })."
    return @{ Name = $Name; Title = $cmd.Title; Text = $texto; Path = $arquivo }
}

function Show-WinForgeOutputWindow {
    <#
    .SYNOPSIS
        Janela com a saída de um comando: texto somente leitura, Copiar, Abrir arquivo e Fechar.
    .DESCRIPTION
        Montada em código, e não em XAML, porque é uma janela só e nasce inteira aqui - um arquivo de
        XAML a mais só espalharia a mesma informação em dois lugares. As cores saem dos recursos do
        tema da janela principal, então ela acompanha claro/escuro sem tabela própria de cor.

        O TextBox é registrado com o nome 'WFOutputText' num NameScope da janela: sem isso,
        FindName() não acha nada numa árvore criada em código - e é por FindName que o -SelfTest
        confere o texto.
    .PARAMETER NoShow
        Monta e devolve a janela sem ShowDialog. É o que o -SelfTest usa: abrir uma janela modal
        durante o build deixaria o build parado para sempre esperando alguém clicar.
    .OUTPUTS
        A janela ([System.Windows.Window]).
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Text = '',
        [string]$Path,
        [switch]$NoShow
    )

    # Em uso normal o WPF já está carregado desde a montagem da janela principal. No -SelfTest não:
    # esta função roda antes do XAML, e sem os dois assemblies o primeiro [System.Windows.*] do
    # corpo falharia com "não é possível localizar o tipo".
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')

    $fundo = $null
    $frente = $null
    if ($null -ne $sync -and $null -ne $sync.Form) {
        try { $fundo = $sync.Form.Resources['MainBackgroundColor'] } catch { $fundo = $null }
        try { $frente = $sync.Form.Resources['MainForegroundColor'] } catch { $frente = $null }
    }
    if ($null -eq $fundo) { $fundo = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(35, 38, 41)) }
    if ($null -eq $frente) { $frente = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(230, 230, 230)) }

    $janela = New-Object System.Windows.Window
    $janela.Title = "WinForge - $Title"
    $janela.Width = 800
    $janela.Height = 500
    $janela.Background = $fundo
    $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    # Owner só depois de a janela principal ter aparecido: o WPF recusa como dona uma janela que
    # ainda não foi mostrada, e o -SelfTest roda antes de qualquer ShowDialog.
    if ($null -ne $sync -and $null -ne $sync.Form -and $sync.Form.IsVisible) {
        try {
            $janela.Owner = $sync.Form
            $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        } catch { }
    }

    $grade = New-Object System.Windows.Controls.Grid
    $grade.Margin = New-Object System.Windows.Thickness 10
    $linhaTexto = New-Object System.Windows.Controls.RowDefinition
    $linhaTexto.Height = New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star)
    $linhaBotoes = New-Object System.Windows.Controls.RowDefinition
    $linhaBotoes.Height = [System.Windows.GridLength]::Auto
    $grade.RowDefinitions.Add($linhaTexto)
    $grade.RowDefinitions.Add($linhaBotoes)

    $caixa = New-Object System.Windows.Controls.TextBox
    $caixa.Text = $Text
    $caixa.IsReadOnly = $true
    $caixa.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas'
    $caixa.FontSize = 12
    $caixa.AcceptsReturn = $true
    $caixa.TextWrapping = [System.Windows.TextWrapping]::NoWrap
    $caixa.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $caixa.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $caixa.Background = $fundo
    $caixa.Foreground = $frente
    [System.Windows.Controls.Grid]::SetRow($caixa, 0)
    $grade.Children.Add($caixa) | Out-Null

    $barra = New-Object System.Windows.Controls.StackPanel
    $barra.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $barra.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $barra.Margin = New-Object System.Windows.Thickness (0, 10, 0, 0)
    [System.Windows.Controls.Grid]::SetRow($barra, 1)
    $grade.Children.Add($barra) | Out-Null

    $novoBotao = {
        param($Conteudo)
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $Conteudo
        $b.MinWidth = 110
        $b.Margin = New-Object System.Windows.Thickness (8, 0, 0, 0)
        $b.Padding = New-Object System.Windows.Thickness (10, 4, 10, 4)
        return $b
    }

    $btnCopiar = & $novoBotao 'Copiar'
    $textoParaCopiar = $Text
    $btnCopiar.Add_Click({
        try {
            [System.Windows.Clipboard]::SetText($textoParaCopiar)
            Write-WinForgeLog -Component "Server" -Message "Saída de '$Title' copiada para a área de transferência."
        } catch {
            Write-WinForgeLog -Component "Server" -Level "WARN" -Message "Não foi possível copiar a saída: $($_.Exception.Message)"
        }
    }.GetNewClosure())
    $barra.Children.Add($btnCopiar) | Out-Null

    $btnArquivo = & $novoBotao 'Abrir arquivo'
    $caminhoArquivo = $Path
    $btnArquivo.IsEnabled = [bool]($caminhoArquivo -and (Test-Path -LiteralPath $caminhoArquivo))
    $btnArquivo.Add_Click({
        try { Start-Process $caminhoArquivo } catch {
            Write-WinForgeLog -Component "Server" -Level "WARN" -Message "Não foi possível abrir '$caminhoArquivo': $($_.Exception.Message)"
        }
    }.GetNewClosure())
    $barra.Children.Add($btnArquivo) | Out-Null

    $btnFechar = & $novoBotao 'Fechar'
    $btnFechar.Add_Click({ $janela.Close() }.GetNewClosure())
    $barra.Children.Add($btnFechar) | Out-Null

    $janela.Content = $grade
    [System.Windows.NameScope]::SetNameScope($janela, (New-Object System.Windows.NameScope))
    $janela.RegisterName('WFOutputText', $caixa)

    if (-not $NoShow) { $janela.ShowDialog() | Out-Null }
    return $janela
}

# O callback da interface nasce AQUI, na runspace principal, e não dentro do runspace do comando.
# Scriptblock criado numa runspace do pool e executado pelo Dispatcher trava na primeira pipeline
# que ele tenta rodar - a thread da janela pede a runspace de origem, que está parada esperando o
# Dispatcher terminar. Foi assim que o diagnóstico morreu calado na tarefa do Plano 3.
# Invoke-WPFUIThread chama o bloco SEM argumento (Dispatcher.Invoke([action])), então o que mostrar
# viaja por $sync.ServerCommandOutput; os parâmetros continuam aceitos para quem chamar direto.
$sync.WinForgeServerOutputCallback = {
    param($Title, $Text, $Path)

    try {
        $pendente = $sync.ServerCommandOutput
        if ($null -ne $pendente) {
            if (-not $Title) { $Title = [string]$pendente.Title }
            if (-not $Text) { $Text = [string]$pendente.Text }
            if (-not $Path) { $Path = [string]$pendente.Path }
        }
        Show-WinForgeOutputWindow -Title $Title -Text $Text -Path $Path | Out-Null
    } catch {
        Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "Janela de saída falhou: $($_.Exception.Message)"
    }
}

function Invoke-WinForgeServerCommand {
    <#
    .SYNOPSIS
        Ação dos botões da aba Servidor: roda o comando fora da thread da janela e mostra a saída.
    .DESCRIPTION
        A thread da janela não pode esperar por um dcdiag: são segundos (às vezes minutos) com a
        interface congelada. O comando roda num runspace do pool e a janela de saída é aberta pela
        thread da interface, com o callback que nasceu na runspace principal.

        Um de cada vez ($sync.ServerCommandRunning). A trava é zerada no 'finally' do corpo E no
        'catch' do despacho: se o Invoke-WPFRunspace falhar (pool fechado, sem thread livre), o corpo
        nunca roda, o 'finally' dele também não, e sem esse catch o botão ficaria morto até fechar o
        programa.

        Ferramenta que não existe nem chega a virar runspace: a resposta é imediata e cabe num aviso.
    #>
    param([Parameter(Mandatory)][string]$Name)

    try {
        $cmd = Get-WinForgeServerCommand -Name $Name
    } catch {
        Write-WinForgeLog -Component "Server" -Level "ERROR" -Message $_.Exception.Message
        [System.Windows.MessageBox]::Show($_.Exception.Message, "WinForge", "OK", "Error") | Out-Null
        return
    }

    if ($sync.ServerCommandRunning) {
        [System.Windows.MessageBox]::Show("Já existe um comando da aba Servidor em andamento. Espere ele terminar.", "WinForge", "OK", "Warning") | Out-Null
        return
    }

    if (-not (Test-WinForgeServerRequirement -Requires $cmd.Requires)) {
        $aviso = "Ferramenta '$($cmd.Requires)' não encontrada neste sistema."
        Write-WinForgeLog -Component "Server" -Level "WARN" -Message "$Name não executado: $aviso"
        [System.Windows.MessageBox]::Show($aviso, "WinForge", "OK", "Information") | Out-Null
        return
    }

    $sync.ServerCommandRunning = $true
    $corpo = {
        param($wfName)
        try {
            $wfRes = Invoke-WinForgeServerCommandCore -Name $wfName
            $sync.ServerCommandOutput = @{ Title = $wfRes.Title; Text = $wfRes.Text; Path = $wfRes.Path }
            # Janela fechando: Invoke-WPFUIThread é síncrono e esperaria por um Dispatcher que está
            # sendo desligado. Não há mais janela para mostrar nada - o arquivo já está gravado.
            if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeServerOutputCallback }
        } catch {
            Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "$wfName falhou: $($_.Exception.Message)"
        } finally {
            $sync.ServerCommandRunning = $false
        }
    }

    Write-WinForgeLog -Component "Server" -Message "$Name iniciado: $($cmd.Command)"
    try {
        Invoke-WPFRunspace -ScriptBlock $corpo -ArgumentList $Name | Out-Null
    } catch {
        $sync.ServerCommandRunning = $false
        Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "$Name não pôde começar: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("O comando não pôde começar: $($_.Exception.Message)", "WinForge", "OK", "Error") | Out-Null
    }
}

# ---------------------------------------------------------------------------
# IIS: ajuste de pools, sites e configuração do servidor
#
# Diferente do resto do programa, aqui não existe "valor original" que caiba na config: o padrão de
# um pool depende de como ele foi criado, e num servidor de produção quem manda é o que está lá
# agora, não o que a Microsoft entrega. Por isso todo item de IIS grava os valores ANTES de mudar
# num JSON em %ProgramData%\WinForge\iis-backup e o Desfazer lê esse arquivo de volta.
#
# Os valores são endereçados por chave de texto, para caber num JSON e num hashtable:
#   pool:<nome do pool>:<caminho da propriedade>   -> IIS:\AppPools\<nome>
#   site:<nome do site>:<caminho da propriedade>   -> IIS:\Sites\<nome>
#   server:<seção>:<atributo>                      -> Get/Set-WebConfigurationProperty no APPHOST
# Tudo é guardado como texto ('00:00:00', 'True', '5000'): o WebAdministration aceita string nessas
# propriedades, então restaurar é reescrever o mesmo texto, sem adivinhar tipo.
#
# Duas regras valem para TODA conversa com o provedor IIS:\ daqui para baixo.
#
# 1. -LiteralPath, nunca -Path. Nome de pool ou site com '[' ou ']' (o IIS aceita) é um curinga para
#    -Path: o caminho não casa com nada, o cmdlet não devolve valor NEM lança - a leitura viraria ''
#    e a escrita, um nada silencioso que ainda contaria como alteração.
# 2. Só entra no backup (e na escrita) a chave cujo valor atual DIFERE do alvo. Aplicar duas vezes
#    seguidas com backup dos dois lados gravaria um segundo arquivo já com os valores ajustados, e
#    o Desfazer - que pega o mais novo - restauraria justamente o que se queria desfazer.
# ---------------------------------------------------------------------------

function Test-WinForgeIisAvailable {
    <#
    .SYNOPSIS
        Diz se dá para falar com o IIS nesta máquina (módulo WebAdministration + provedor IIS:\).
    #>
    try {
        Import-Module WebAdministration -ErrorAction Stop
        return [bool](Test-Path -LiteralPath 'IIS:\')
    } catch {
        return $false
    }
}

function Get-WinForgeIisSnapshotRoot {
    <#
    .SYNOPSIS
        Pasta dos backups de IIS. -Root existe para o -SelfTest não escrever em %ProgramData%.
    #>
    param([string]$Root)

    if ($Root) { return $Root }
    return (Join-Path $env:ProgramData 'WinForge\iis-backup')
}

function New-WinForgeIisSnapshot {
    <#
    .SYNOPSIS
        Grava os valores anteriores de um item de IIS num JSON com data e hora no nome.
    .DESCRIPTION
        O nome carrega os milissegundos ('-fff'): com precisão de segundo, dois backups do mesmo item
        no mesmo segundo cairiam no MESMO arquivo e o primeiro - o que tem os valores originais -
        seria sobrescrito. Milissegundo mantém a ordenação por nome (o campo é de largura fixa).
    .OUTPUTS
        Caminho do arquivo gravado.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Values,
        [string]$Root
    )

    $dir = Get-WinForgeIisSnapshotRoot $Root
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir ("{0}-{1}.json" -f $Name, (Get-Date).ToString('yyyyMMdd-HHmmss-fff'))
    @{ Name = $Name; Date = (Get-Date).ToString('s'); Values = $Values } | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
    Write-WinForgeLog -Component "IIS" -Message "Valores anteriores de $Name guardados em $path ($($Values.Count) item(ns))."
    return $path
}

function Get-WinForgeIisSnapshot {
    <#
    .SYNOPSIS
        Devolve o backup mais recente de um item de IIS, ou $null se não houver nenhum.
    .DESCRIPTION
        O nome do arquivo é '<Item>-<yyyyMMdd-HHmmss-fff>.json': ordenar por nome em ordem decrescente
        coloca o mais novo primeiro sem depender da data do sistema de arquivos (que uma cópia de
        pasta reescreve). Os valores voltam como hashtable, e não como o PSCustomObject do
        ConvertFrom-Json, porque quem restaura precisa iterar chave a chave.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Root
    )

    $dir = Get-WinForgeIisSnapshotRoot $Root
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $file = Get-ChildItem -LiteralPath $dir -Filter "$Name-*.json" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $file) { return $null }
    $o = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $values = @{}
    foreach ($p in $o.Values.PSObject.Properties) { $values[$p.Name] = $p.Value }
    return @{ Name = $o.Name; Date = $o.Date; Values = $values; Path = $file.FullName }
}

function Split-WinForgeIisKey {
    <#
    .SYNOPSIS
        Quebra 'pool:<nome>:<propriedade>' nas três partes. O limite de 3 pedaços é de propósito:
        a seção do servidor ('system.webServer/urlCompression') não tem dois-pontos, mas o caminho
        da propriedade pode ganhar um no futuro e não pode ser cortado.
    #>
    param([Parameter(Mandatory)][string]$Key)

    $parts = $Key -split ':', 3
    if ($parts.Count -ne 3 -or [string]::IsNullOrWhiteSpace($parts[1]) -or [string]::IsNullOrWhiteSpace($parts[2])) {
        throw "Chave de IIS inválida: '$Key' (esperado 'pool:<nome>:<propriedade>', 'site:<nome>:<propriedade>' ou 'server:<seção>:<atributo>')."
    }
    return @{ Kind = $parts[0]; Target = $parts[1]; Property = $parts[2] }
}

function Get-WinForgeIisFilter {
    <#
    .SYNOPSIS
        Normaliza o nome da seção para o filtro do Get/Set-WebConfigurationProperty ('/seção').
    #>
    param([Parameter(Mandatory)][string]$Section)

    if ($Section.StartsWith('/')) { return $Section }
    return ('/' + $Section)
}

function ConvertTo-WinForgeIisString {
    <#
    .SYNOPSIS
        Converte o valor devolvido pelo WebAdministration em texto que o próprio WebAdministration
        aceita de volta ('00:00:00', 'True', '5000').
    .DESCRIPTION
        Algumas propriedades voltam cruas (bool, número, TimeSpan), outras dentro de um objeto de
        configuração com .Value. O desembrulho é por EXCLUSÃO: qualquer coisa que não seja string nem
        tipo por valor é candidata, então um ConfigurationAttribute cai nele sem que a lista de tipos
        crus precise ser mantida à mão (a versão anterior listava int/long e deixava uint32 escapar
        para o desembrulho). Hashtable e dicionário entram pela chave 'Value', que não aparece em
        PSObject.Properties - sem esse ramo, @{ Value = ... } viraria o texto 'System.Collections.
        Hashtable' e o backup guardaria isso.

        TimeSpan é formatado à mão porque o ToString() padrão vira '1.02:00:00' acima de um dia,
        formato que o IIS não aceita de volta; aqui viram 26 horas ('26:00:00'). Essa mesma forma
        normalizada é o que Test-WinForgeIisValueMatch compara.
    #>
    param($Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains('Value')) { $Value = $Value['Value'] }
    } elseif ($Value -isnot [string] -and $Value -isnot [System.ValueType]) {
        $inner = $Value.PSObject.Properties['Value']
        if ($inner) { $Value = $inner.Value }
    }
    if ($null -eq $Value) { return '' }
    if ($Value -is [System.TimeSpan]) { return ('{0:00}:{1:00}:{2:00}' -f [int][math]::Floor($Value.TotalHours), $Value.Minutes, $Value.Seconds) }
    if ($Value -is [bool]) { if ($Value) { return 'True' } else { return 'False' } }
    return [string]$Value
}

function Test-WinForgeIisValueMatch {
    <#
    .SYNOPSIS
        Diz se o valor atual de uma chave já é o valor alvo.
    .DESCRIPTION
        Os dois lados passam por ConvertTo-WinForgeIisString antes da comparação, então TimeSpan cru
        e o texto '00:00:00' que veio da config são a mesma coisa. Sem diferenciar maiúsculas:
        'alwaysrunning' devolvido pelo IIS e 'AlwaysRunning' escrito aqui são o mesmo startMode, e
        tratá-los como diferentes faria o item se reaplicar para sempre.
    #>
    param($Current, $Target)

    $a = (ConvertTo-WinForgeIisString $Current).Trim()
    $b = (ConvertTo-WinForgeIisString $Target).Trim()
    return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-WinForgeIisValue {
    <#
    .SYNOPSIS
        Lê o valor atual de uma chave de IIS, como texto.
    .DESCRIPTION
        -LiteralPath: com -Path, um pool chamado 'App [teste]' não casaria com nada e a leitura
        voltaria vazia sem erro nenhum (nem com -ErrorAction Stop).
    #>
    param([Parameter(Mandatory)][string]$Key)

    $k = Split-WinForgeIisKey -Key $Key
    switch ($k.Kind) {
        'pool'   { return (ConvertTo-WinForgeIisString (Get-ItemProperty -LiteralPath ("IIS:\AppPools\" + $k.Target) -Name $k.Property -ErrorAction Stop)) }
        'site'   { return (ConvertTo-WinForgeIisString (Get-ItemProperty -LiteralPath ("IIS:\Sites\" + $k.Target) -Name $k.Property -ErrorAction Stop)) }
        'server' { return (ConvertTo-WinForgeIisString (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter (Get-WinForgeIisFilter $k.Target) -Name $k.Property -ErrorAction Stop)) }
    }
    throw "Chave de IIS inválida: '$Key' (tipo '$($k.Kind)' desconhecido)."
}

function Set-WinForgeIisValue {
    <#
    .SYNOPSIS
        Escreve um valor numa chave de IIS. O valor vai como texto - é assim que ele sai do backup.
    .DESCRIPTION
        -LiteralPath pelo mesmo motivo da leitura, com consequência pior: com -Path, um nome com
        colchetes não casa com nada, a escrita não acontece e nada reclama - a alteração entraria na
        contagem de 'Changed' sem ter mexido em nada.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)]$Value
    )

    $k = Split-WinForgeIisKey -Key $Key
    switch ($k.Kind) {
        'pool'   { Set-ItemProperty -LiteralPath ("IIS:\AppPools\" + $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
        'site'   { Set-ItemProperty -LiteralPath ("IIS:\Sites\" + $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
        'server' { Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter (Get-WinForgeIisFilter $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
    }
    throw "Chave de IIS inválida: '$Key' (tipo '$($k.Kind)' desconhecido)."
}

function Restore-WinForgeIisSnapshot {
    <#
    .SYNOPSIS
        Reescreve os valores do backup mais recente de um item de IIS.
    .OUTPUTS
        Quantidade de valores restaurados.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Root
    )

    $snap = Get-WinForgeIisSnapshot -Name $Name -Root $Root
    if (-not $snap) {
        Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Sem backup para desfazer $Name."
        return 0
    }
    $restored = 0
    foreach ($key in @($snap.Values.Keys)) {
        try {
            Set-WinForgeIisValue -Key $key -Value $snap.Values[$key]
            $restored++
        } catch {
            Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message "Falha ao restaurar '$key' -> $($_.Exception.Message)"
            Write-Host "IIS: falha ao restaurar '$key' -> $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-WinForgeLog -Component "IIS" -Message "Backup $($snap.Path) restaurado: $restored de $(@($snap.Values.Keys).Count) valor(es)."
    return $restored
}

function Test-WinForgeIisFeature {
    <#
    .SYNOPSIS
        Diz se um recurso do Windows Server está instalado.
    .DESCRIPTION
        Get-WindowsFeature só existe em servidor. Onde não dá para perguntar, a resposta é $true e a
        tentativa segue: se o recurso faltar mesmo, quem reclama é o próprio IIS e o erro é tratado
        como qualquer outro. Nada aqui instala recurso nenhum.
    #>
    param([Parameter(Mandatory)][string]$Feature)

    if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) { return $true }
    try {
        $f = Get-WindowsFeature -Name $Feature -ErrorAction Stop
        if (-not $f) { return $false }
        return [bool]$f.Installed
    } catch {
        return $true
    }
}

function Get-WinForgeIisPrivateMemoryLimitKb {
    <#
    .SYNOPSIS
        Limite de memória privada por pool, em KB: 60% da RAM dividido pelos pools, preso entre 1 GB
        e 8 GB. Sem essa faixa, um servidor com 4 GB e 10 pools recicla o tempo todo e um com 512 GB
        nunca recicla.
    .PARAMETER TotalKb
        RAM total em KB. Existe para o -SelfTest exercitar as duas pontas da faixa sem depender da
        memória da máquina onde o teste roda; em uso normal fica de fora e a RAM vem do CIM.
    #>
    param(
        [int]$PoolCount = 1,
        [int64]$TotalKb = 0
    )

    $totalKb = $TotalKb
    if ($totalKb -le 0) {
        try { $totalKb = [int64](((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory) / 1024) } catch { $totalKb = 0 }
    }
    if ($PoolCount -lt 1) { $PoolCount = 1 }
    $limitKb = 1048576
    if ($totalKb -gt 0) { $limitKb = [int64][math]::Floor($totalKb * 0.6 / $PoolCount) }
    if ($limitKb -lt 1048576) { $limitKb = 1048576 }
    if ($limitKb -gt 8388608) { $limitKb = 8388608 }
    return [int64]$limitKb
}

function Get-WinForgeIisChangeSet {
    <#
    .SYNOPSIS
        Decide, chave por chave, o que entra no backup e na escrita.
    .DESCRIPTION
        Recebe os alvos do plano e os valores ATUAIS já lidos (chave ausente = a leitura falhou) e
        devolve as quatro listas. Fica separada de Invoke-WinForgeIisTweak porque é aqui que moram as
        duas decisões que tornam o item reversível, e nenhuma delas precisa de IIS para ser testada:

        - Valor vazio ou nulo conta como NÃO LIDO. Guardar '' no backup faria o Desfazer escrever
          vazio na propriedade, e escrever vazio não é o mesmo que devolver o valor de antes.
        - Chave que já está no alvo fica fora do backup E da escrita. Sem isso, aplicar duas vezes
          gravaria um segundo backup com os valores já ajustados e o Desfazer - que pega o mais
          novo - restauraria exatamente o que se queria desfazer.

        Os valores do backup saem normalizados por ConvertTo-WinForgeIisString: é texto que vai para
        o JSON e volta de lá para o Set-WinForgeIisValue.
    .OUTPUTS
        Hashtable com Previous (chave -> texto anterior, o que vai para o backup), Pending (chaves a
        escrever, na ordem do plano), Unreadable e Already (listas de chaves).
    #>
    param(
        [Parameter(Mandatory)]$Targets,
        [Parameter(Mandatory)][hashtable]$Current
    )

    $previous = @{}
    $pending = @()
    $unreadable = @()
    $already = @()
    foreach ($key in @($Targets.Keys)) {
        if (-not $Current.ContainsKey($key)) { $unreadable += $key; continue }
        $text = ConvertTo-WinForgeIisString $Current[$key]
        if ([string]::IsNullOrWhiteSpace($text)) { $unreadable += $key; continue }
        if (Test-WinForgeIisValueMatch -Current $text -Target $Targets[$key]) { $already += $key; continue }
        $previous[$key] = $text
        $pending += $key
    }
    return @{ Previous = $previous; Pending = $pending; Unreadable = $unreadable; Already = $already }
}

function Get-WinForgeIisTweakPlan {
    <#
    .SYNOPSIS
        Monta a lista de chaves e valores novos de um item de IIS, mais o que foi pulado e por quê.
    .DESCRIPTION
        Separado de Invoke-WinForgeIisTweak para que "o que este item mexe" seja legível num lugar
        só. Os pools e sites são lidos da máquina: o ajuste vale para todos os que existirem.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $targets = [ordered]@{}
    $skipped = @()
    $pools = @()
    $sites = @()

    if ($Name -in @('AlwaysRunning', 'NoIdleTimeout', 'MemoryRecycling', 'Concurrency')) {
        $pools = @(Get-ChildItem -LiteralPath 'IIS:\AppPools' -ErrorAction Stop | ForEach-Object { $_.Name })
        if (-not $pools.Count) { $skipped += "IIS: nenhum pool de aplicativos encontrado." }
    }
    if ($Name -eq 'Preload') {
        $sites = @(Get-ChildItem -LiteralPath 'IIS:\Sites' -ErrorAction Stop | ForEach-Object { $_.Name })
        if (-not $sites.Count) { $skipped += "IIS: nenhum site encontrado." }
    }

    switch ($Name) {
        'AlwaysRunning' {
            foreach ($p in $pools) {
                $targets["pool:${p}:startMode"] = 'AlwaysRunning'
                $targets["pool:${p}:autoStart"] = 'True'
            }
        }
        'NoIdleTimeout' {
            foreach ($p in $pools) { $targets["pool:${p}:processModel.idleTimeout"] = '00:00:00' }
        }
        'MemoryRecycling' {
            $limitKb = Get-WinForgeIisPrivateMemoryLimitKb -PoolCount $pools.Count
            foreach ($p in $pools) {
                $targets["pool:${p}:recycling.periodicRestart.time"] = '00:00:00'
                $targets["pool:${p}:recycling.periodicRestart.privateMemory"] = [string]$limitKb
            }
        }
        'Preload' {
            if (-not (Test-WinForgeIisFeature -Feature 'Web-AppInit')) {
                $skipped += "IIS: pré-carregamento ignorado - o recurso Web-AppInit (Inicialização de Aplicativos) não está instalado. O WinForge não instala recursos."
            } else {
                foreach ($s in $sites) { $targets["site:${s}:applicationDefaults.preloadEnabled"] = 'True' }
            }
        }
        'Compression' {
            $targets['server:system.webServer/urlCompression:doStaticCompression'] = 'True'
            if (Test-WinForgeIisFeature -Feature 'Web-Dyn-Compression') {
                $targets['server:system.webServer/urlCompression:doDynamicCompression'] = 'True'
            } else {
                $skipped += "IIS: compressão dinâmica ignorada - o recurso Web-Dyn-Compression não está instalado. O WinForge não instala recursos."
            }
        }
        'OutputCache' {
            $targets['server:system.webServer/caching:enabled'] = 'True'
            $targets['server:system.webServer/caching:enableKernelCache'] = 'True'
        }
        'Concurrency' {
            foreach ($p in $pools) { $targets["pool:${p}:queueLength"] = '5000' }
        }
        default { throw "Item de IIS desconhecido: '$Name'." }
    }

    return @{ Targets = $targets; Skipped = ($skipped -join ' ') }
}

function Invoke-WinForgeIisTweak {
    <#
    .SYNOPSIS
        Aplica (ou desfaz) um ajuste de IIS, guardando antes os valores anteriores em disco.
    .DESCRIPTION
        Nunca lança: roda dentro do runspace de tweaks, onde uma exceção mataria a fila inteira de
        itens marcados. Erro vira linha de log, aviso vermelho no console e Changed = 0.
        Desfazer não tem "valor padrão" embutido: ele só reescreve o que o backup guardou. Sem
        backup (item nunca aplicado), não faz nada - é melhor que chutar o padrão da Microsoft por
        cima do que o administrador configurou.

        Aplicar é IDEMPOTENTE: chave que já está no alvo fica fora do backup e da escrita, e um item
        inteiro já aplicado não grava arquivo nenhum. É isso que mantém o Desfazer honesto - o
        Desfazer pega o backup mais novo, então um segundo backup gravado com os valores já
        ajustados restauraria exatamente o que se queria desfazer.
    .OUTPUTS
        [pscustomobject] Name, Changed (quantos valores mudaram), Skipped (motivo, se algo ficou de
        fora), Snapshot (caminho do backup usado ou gravado).
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AlwaysRunning', 'NoIdleTimeout', 'MemoryRecycling', 'Preload', 'Compression', 'OutputCache', 'Concurrency')]
        [string]$Name,
        [switch]$Undo,
        [string]$Root
    )

    $result = [pscustomobject]@{ Name = $Name; Changed = 0; Skipped = ''; Snapshot = $null }
    try {
        if (-not (Test-WinForgeIisAvailable)) {
            $result.Skipped = "IIS não encontrado nesta máquina (módulo WebAdministration ausente): nada foi alterado."
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "$Name ignorado: $($result.Skipped)"
            Write-Host $result.Skipped -ForegroundColor Yellow
            return $result
        }

        if ($Undo) {
            $snap = Get-WinForgeIisSnapshot -Name $Name -Root $Root
            if (-not $snap) {
                $result.Skipped = "IIS: sem backup para desfazer '$Name' - nenhum valor foi alterado."
                Write-WinForgeLog -Component "IIS" -Level "WARN" -Message $result.Skipped
                Write-Host $result.Skipped -ForegroundColor Yellow
                return $result
            }
            $result.Snapshot = $snap.Path
            $result.Changed = Restore-WinForgeIisSnapshot -Name $Name -Root $Root
            Write-Host "IIS: '$Name' desfeito - $($result.Changed) valor(es) restaurado(s) de $($snap.Path)."
            return $result
        }

        $plan = Get-WinForgeIisTweakPlan -Name $Name
        $result.Skipped = [string]$plan.Skipped
        $keys = @($plan.Targets.Keys)
        if ($keys.Count -eq 0) {
            if (-not $result.Skipped) { $result.Skipped = "IIS: '$Name' não tinha nada para alterar." }
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "$Name sem alvos: $($result.Skipped)"
            Write-Host $result.Skipped -ForegroundColor Yellow
            return $result
        }

        # Ler tudo ANTES de escrever qualquer coisa. Chave que a leitura não deu conta nem entra no
        # hashtable: para Get-WinForgeIisChangeSet, "ausente" é o mesmo que "não lida".
        $current = @{}
        foreach ($key in $keys) {
            try { $current[$key] = Get-WinForgeIisValue -Key $key }
            catch {
                Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Não foi possível ler '$key': $($_.Exception.Message)"
            }
        }
        $set = Get-WinForgeIisChangeSet -Targets $plan.Targets -Current $current
        $previous = $set.Previous
        $pending = @($set.Pending)
        $unreadable = @($set.Unreadable)
        $already = @($set.Already).Count
        # A leitura que falhou já foi registrada com a mensagem do erro; a que voltou vazia (chave
        # presente no hashtable, valor sem conteúdo) precisa da linha dela.
        foreach ($key in $unreadable) {
            if ($current.ContainsKey($key)) {
                Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Valor de '$key' voltou vazio: a propriedade fica fora do backup e não será alterada."
            }
        }
        if ($pending.Count -eq 0) {
            if ($already -gt 0) {
                $result.Skipped = ("IIS: '$Name' já aplicado - $already valor(es) já estavam no alvo; nada foi alterado e nenhum backup foi gravado. " + $result.Skipped).Trim()
            } else {
                $result.Skipped = ("IIS: nenhum valor de '$Name' pôde ser lido; nada foi alterado. " + $result.Skipped).Trim()
            }
            if ($unreadable.Count) {
                $result.Skipped = ($result.Skipped + " IIS: $($unreadable.Count) propriedade(s) não lida(s): $($unreadable -join ', ').").Trim()
            }
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "$Name sem alterações: $($result.Skipped)"
            Write-Host $result.Skipped -ForegroundColor Yellow
            return $result
        }
        $result.Snapshot = New-WinForgeIisSnapshot -Name $Name -Values $previous -Root $Root

        foreach ($key in $pending) {
            try {
                Set-WinForgeIisValue -Key $key -Value $plan.Targets[$key]
                $result.Changed++
            } catch {
                Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message "Falha ao ajustar '$key': $($_.Exception.Message)"
                Write-Host "IIS: falha ao ajustar '$key' -> $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        if ($already -gt 0) {
            $result.Skipped = ($result.Skipped + " IIS: $already valor(es) já estavam no alvo e ficaram fora do backup.").Trim()
        }
        if ($unreadable.Count) {
            $result.Skipped = ($result.Skipped + " IIS: $($unreadable.Count) propriedade(s) não lida(s): $($unreadable -join ', ').").Trim()
        }
        Write-WinForgeLog -Component "IIS" -Message "$Name aplicado: $($result.Changed) valor(es) alterado(s); backup em $($result.Snapshot)."
        if ($result.Skipped) { Write-Host $result.Skipped -ForegroundColor Yellow }
        Write-Host "IIS: '$Name' aplicado - $($result.Changed) valor(es) alterado(s). Backup: $($result.Snapshot)"
    } catch {
        Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message "Falha em '$Name': $($_.Exception.Message)"
        Write-Host "IIS: falha em '$Name' -> $($_.Exception.Message)" -ForegroundColor Red
        $result.Changed = 0
    }
    return $result
}
#endregion
