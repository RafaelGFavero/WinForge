#region ===== WinForge - aba Diagnóstico =====
# Mostra o perfil coletado por Get-WinForgeSystemProfile em cartões, a tabela de drivers, o que as
# regras recomendaram e (sob demanda) os drivers que o Windows Update tem para este computador.
# Nada aqui aplica tweak: o único botão que mexe em seleção é "Marcar todos os recomendados", que
# só marca caixas (Select-WinForgeRecommended).
# O modelo de seções é montado uma vez (Get-WinForgeDiagSections) e serve tanto aos cartões da
# janela quanto ao relatório HTML - sem isso os dois sairiam contando histórias diferentes.

# Dica dos dois botões que exigem elevação (baixar driver NVIDIA, instalar pelo Windows Update).
# Uma constante e não duas cópias: as duas tabelas dizem a mesma coisa, e é isso que o -SelfTest
# cobra - o dia em que uma das duas mudar sozinha, a outra passa a mentir.
$WinForgeElevationTip = 'Precisa de elevação (execute o WinForge como administrador)'

function Format-WinForgeDiagValue {
    <#
    .SYNOPSIS
        Texto de um campo do perfil, com 'n/d' no lugar de vazio/desconhecido e sim/não para booleano.
    .DESCRIPTION
        Campo $null não é erro: Secure Boot, TPM e BitLocker ficam nulos sem elevação, e VBS fica nulo
        onde o Device Guard não responde. 'n/d' diz isso ao usuário sem fingir um valor.
    #>
    param($Value, [string]$Suffix = '')

    if ($null -eq $Value) { return 'n/d' }
    if ($Value -is [bool]) { return $(if ($Value) { 'sim' } else { 'não' }) }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return 'n/d' }
    return "$text$Suffix"
}

function New-WinForgeDiagSection {
    <#
    .SYNOPSIS
        Seção vazia do diagnóstico (título + lista de linhas chave/valor).
    #>
    param([Parameter(Mandatory)][string]$Title)
    return [pscustomobject]@{ Title = $Title; Lines = [System.Collections.Generic.List[object]]::new() }
}

function Add-WinForgeDiagLine {
    <#
    .SYNOPSIS
        Acrescenta uma linha "chave: valor" a uma seção.
    #>
    param([Parameter(Mandatory)]$Section, [Parameter(Mandatory)][string]$Key, $Value)
    $Section.Lines.Add([pscustomobject]@{ Key = $Key; Value = [string]$Value })
}

function Get-WinForgeDiagSections {
    <#
    .SYNOPSIS
        Modelo do diagnóstico: uma seção por área do perfil (Sistema, Máquina, CPU, Memória, GPU,
        Armazenamento, Rede, Energia, Segurança e estado) e, só no Windows Server, Servidor.
    .DESCRIPTION
        Fonte única dos cartões da janela e do relatório HTML. Área que a coleta não trouxe vira
        seção com linhas 'n/d' - o motivo real da falha aparece nas informações (perfil .Errors).
    .PARAMETER Profile
        Perfil devolvido por Get-WinForgeSystemProfile. Sem parâmetro usa $sync.Profile.
    .OUTPUTS
        Array de @{ Title; Lines = @(@{ Key; Value }) }.
    #>
    param($Profile)

    if ($null -eq $Profile) { $Profile = $sync.Profile }
    if ($null -eq $Profile) { return @() }

    $sections = [System.Collections.Generic.List[object]]::new()

    # ---- Sistema
    $os = $Profile.OS
    $sec = New-WinForgeDiagSection "Sistema"
    Add-WinForgeDiagLine $sec "Edição" (Format-WinForgeDiagValue $os.Caption)
    Add-WinForgeDiagLine $sec "Versão" ("{0} (build {1})" -f (Format-WinForgeDiagValue $os.DisplayVersion), (Format-WinForgeDiagValue $os.Build))
    Add-WinForgeDiagLine $sec "Arquitetura" (Format-WinForgeDiagValue $os.Architecture)
    Add-WinForgeDiagLine $sec "Instalado em" (Format-WinForgeDiagValue $os.InstallDate)
    Add-WinForgeDiagLine $sec "Ligado há" (Format-WinForgeDiagValue $os.UptimeHours ' h')
    if ($os.IsServer) {
        $roles = @()
        foreach ($r in @('IIS', 'AD', 'HyperV', 'DNS', 'DHCP', 'FileServer', 'RDS')) {
            if ($Profile.Roles.$r) { $roles += $r }
        }
        Add-WinForgeDiagLine $sec "Windows Server" "sim"
        Add-WinForgeDiagLine $sec "Funções instaladas" $(if ($roles.Count) { $roles -join ', ' } else { 'nenhuma detectada' })
    }
    $sections.Add($sec)

    # ---- Máquina
    $mc = $Profile.Machine
    $sec = New-WinForgeDiagSection "Máquina"
    Add-WinForgeDiagLine $sec "Fabricante" (Format-WinForgeDiagValue $mc.Manufacturer)
    Add-WinForgeDiagLine $sec "Modelo" (Format-WinForgeDiagValue $mc.Model)
    $tipo = if ($mc.IsVirtual) { 'máquina virtual' } elseif ($mc.IsLaptop) { 'notebook' } else { 'desktop' }
    Add-WinForgeDiagLine $sec "Tipo" $tipo
    Add-WinForgeDiagLine $sec "Hipervisor presente" (Format-WinForgeDiagValue $mc.HypervisorPresent)
    Add-WinForgeDiagLine $sec "Secure Boot" (Format-WinForgeDiagValue $mc.SecureBoot)
    Add-WinForgeDiagLine $sec "TPM" (Format-WinForgeDiagValue $mc.TpmVersion)
    Add-WinForgeDiagLine $sec "BitLocker" (Format-WinForgeDiagValue $mc.BitLocker)
    $sections.Add($sec)

    # ---- CPU
    $cpu = $Profile.CPU
    $sec = New-WinForgeDiagSection "Processador"
    Add-WinForgeDiagLine $sec "Modelo" (Format-WinForgeDiagValue $cpu.Name)
    Add-WinForgeDiagLine $sec "Núcleos" ("{0} físicos / {1} lógicos" -f (Format-WinForgeDiagValue $cpu.Cores), (Format-WinForgeDiagValue $cpu.Logical))
    Add-WinForgeDiagLine $sec "Frequência máxima" (Format-WinForgeDiagValue $cpu.MaxMHz ' MHz')
    Add-WinForgeDiagLine $sec "Núcleos híbridos (P/E)" (Format-WinForgeDiagValue $cpu.Hybrid)
    Add-WinForgeDiagLine $sec "Virtualização no firmware" (Format-WinForgeDiagValue $cpu.VirtualizationEnabled)
    $sections.Add($sec)

    # ---- Memória
    $ram = $Profile.RAM
    $sec = New-WinForgeDiagSection "Memória"
    Add-WinForgeDiagLine $sec "Total" (Format-WinForgeDiagValue $ram.TotalGB ' GB')
    Add-WinForgeDiagLine $sec "Livre" (Format-WinForgeDiagValue $ram.FreeGB ' GB')
    Add-WinForgeDiagLine $sec "Módulos" (Format-WinForgeDiagValue $ram.Modules)
    Add-WinForgeDiagLine $sec "Velocidade" (Format-WinForgeDiagValue $ram.SpeedMHz ' MHz')
    Add-WinForgeDiagLine $sec "Arquivo de paginação" (Format-WinForgeDiagValue $ram.PageFileGB ' GB')
    $sections.Add($sec)

    # ---- GPU (uma linha por adaptador, com driver instalado x mais recente)
    $sec = New-WinForgeDiagSection "Placa de vídeo"
    $gpus = @($Profile.GPU)
    if ($gpus.Count -eq 0) {
        Add-WinForgeDiagLine $sec "Adaptadores" "n/d"
    } else {
        foreach ($g in $gpus) {
            $instalado = Format-WinForgeDiagValue $g.DriverVersion
            if ($g.MarketingVersion) { $instalado = "$($g.MarketingVersion) ($($g.DriverVersion))" }
            $detalhe = "driver $instalado de $(Format-WinForgeDiagValue $g.DriverDate)"
            if ($g.VRAMGB) { $detalhe = "$($g.VRAMGB) GB, $detalhe" }
            if ($g.Latest) { $detalhe = "$detalhe | mais recente: $($g.Latest) de $(Format-WinForgeDiagValue $g.LatestDate)" }
            $detalhe = "$detalhe | situação: $(Format-WinForgeDiagValue $g.LatestStatus)"
            Add-WinForgeDiagLine $sec ([string]$g.Name) $detalhe
        }
    }
    $sections.Add($sec)

    # ---- Armazenamento
    $st = $Profile.Storage
    $sec = New-WinForgeDiagSection "Armazenamento"
    Add-WinForgeDiagLine $sec "Disco do sistema" (Format-WinForgeDiagValue $st.SystemDriveMedia)
    foreach ($d in @($st.Disks)) {
        Add-WinForgeDiagLine $sec ([string]$d.Name) ("{0} GB, {1}, barramento {2}, saúde {3}" -f (Format-WinForgeDiagValue $d.SizeGB), (Format-WinForgeDiagValue $d.MediaNormalized), (Format-WinForgeDiagValue $d.Bus), (Format-WinForgeDiagValue $d.Health))
    }
    foreach ($v in @($st.Volumes)) {
        Add-WinForgeDiagLine $sec ("Volume {0}:" -f (Format-WinForgeDiagValue $v.Letter)) ("{0} GB {1}, {2}% livre" -f (Format-WinForgeDiagValue $v.SizeGB), (Format-WinForgeDiagValue $v.FS), (Format-WinForgeDiagValue $v.FreePct))
    }
    $sections.Add($sec)

    # ---- Rede
    $net = $Profile.Network
    $sec = New-WinForgeDiagSection "Rede"
    Add-WinForgeDiagLine $sec "Adaptador" (Format-WinForgeDiagValue $net.Adapter)
    Add-WinForgeDiagLine $sec "Conexão" (Format-WinForgeDiagValue $net.Name)
    Add-WinForgeDiagLine $sec "Velocidade do enlace" (Format-WinForgeDiagValue $net.LinkSpeed)
    Add-WinForgeDiagLine $sec "Sem fio" (Format-WinForgeDiagValue $net.IsWifi)
    Add-WinForgeDiagLine $sec "DNS" $(if (@($net.Dns).Count) { @($net.Dns) -join ', ' } else { 'n/d' })
    Add-WinForgeDiagLine $sec "IPv6 ligado" (Format-WinForgeDiagValue $net.IPv6Enabled)
    $sections.Add($sec)

    # ---- Energia
    $pw = $Profile.Power
    $sec = New-WinForgeDiagSection "Energia"
    Add-WinForgeDiagLine $sec "Plano ativo" (Format-WinForgeDiagValue $pw.ActiveScheme)
    Add-WinForgeDiagLine $sec "GUID do plano" (Format-WinForgeDiagValue $pw.ActiveSchemeGuid)
    Add-WinForgeDiagLine $sec "Na bateria" (Format-WinForgeDiagValue $pw.OnBattery)
    Add-WinForgeDiagLine $sec "Hibernação" (Format-WinForgeDiagValue $pw.HibernationEnabled)
    $sections.Add($sec)

    # ---- Segurança e estado
    $stt = $Profile.State
    $sec = New-WinForgeDiagSection "Segurança e estado"
    Add-WinForgeDiagLine $sec "VBS (segurança por virtualização)" (Format-WinForgeDiagValue $stt.VBS)
    Add-WinForgeDiagLine $sec "HAGS (agendamento pela GPU)" (Format-WinForgeDiagValue $stt.HAGS)
    Add-WinForgeDiagLine $sec "Modo Jogo" (Format-WinForgeDiagValue $stt.GameMode)
    Add-WinForgeDiagLine $sec "SysMain" (Format-WinForgeDiagValue $stt.SysMain)
    Add-WinForgeDiagLine $sec "Windows Search" (Format-WinForgeDiagValue $stt.WSearch)
    Add-WinForgeDiagLine $sec "Inicialização rápida" (Format-WinForgeDiagValue $stt.FastStartup)
    $sections.Add($sec)

    # ---- Servidor (só no Windows Server; num cliente este cartão não existe)
    # O perfil de servidor traz uma área inteira que nenhum outro cartão mostra (SMB, TCP, horário,
    # IIS, AD). Sem este cartão o relatório de um servidor sairia igual ao de um desktop e as regras
    # de servidor pareceriam ter saído do nada.
    if ($os.IsServer) {
        $srv = $Profile.Server
        $sec = New-WinForgeDiagSection "Servidor"
        $papeis = @()
        foreach ($r in @('IIS', 'AD', 'HyperV', 'DNS', 'DHCP', 'FileServer', 'RDS')) {
            if ($Profile.Roles.$r) { $papeis += $r }
        }
        if ($Profile.Roles.IsDC) { $papeis += 'controlador de domínio' }
        Add-WinForgeDiagLine $sec "Papéis" $(if ($papeis.Count) { $papeis -join ', ' } else { 'nenhum detectado' })
        # Perfil montado sob simulação: sem esta linha, o relatório HTML de um teste afirmaria que a
        # máquina é servidor sem dizer que quem mandou isso foi uma variável de ambiente.
        if ($Profile.Simulated) { Add-WinForgeDiagLine $sec "Simulação" ([string]$Profile.Simulated) }
        # Área Servidor ausente (perfil antigo, coleta que falhou inteira): as linhas viram 'n/d' em
        # vez de sumir - o cartão continua contando o mesmo enredo, só sem os valores.
        Add-WinForgeDiagLine $sec "SMB1" (Format-WinForgeDiagValue $(if ($srv) { $srv.Smb1Enabled } else { $null }))
        Add-WinForgeDiagLine $sec "Assinatura SMB obrigatória" (Format-WinForgeDiagValue $(if ($srv) { $srv.SmbSigningRequired } else { $null }))
        Add-WinForgeDiagLine $sec "Ajuste automático TCP" (Format-WinForgeDiagValue $(if ($srv) { $srv.TcpAutotuning } else { $null }))
        Add-WinForgeDiagLine $sec "Fonte de horário" (Format-WinForgeDiagValue $(if ($srv) { $srv.TimeSource } else { $null }))
        $iis = if ($srv) { $srv.Iis } else { $null }
        if ($iis -and $iis.Installed) {
            Add-WinForgeDiagLine $sec "IIS" ("{0} pool(s), {1} site(s)" -f (Format-WinForgeDiagValue $iis.PoolCount), (Format-WinForgeDiagValue $iis.SiteCount))
            $logs = Format-WinForgeDiagValue $iis.LogDirectory
            if ($iis.LogOnOsDrive -eq $true) { $logs = "$logs (disco do sistema)" }
            Add-WinForgeDiagLine $sec "Logs do IIS" $logs
        } else {
            Add-WinForgeDiagLine $sec "IIS" "não instalado"
        }
        # NTDS/SYSVOL só existem num controlador de domínio: num servidor membro as duas linhas seriam
        # 'n/d' fixo, e 'n/d' que nunca muda é ruído, não informação.
        if ($Profile.Roles.IsDC) {
            $ad = if ($srv) { $srv.Ad } else { $null }
            foreach ($par in @(@('NTDS', 'NtdsPath', 'NtdsOnOsDrive'), @('SYSVOL', 'SysvolPath', 'SysvolOnOsDrive'))) {
                $texto = Format-WinForgeDiagValue $(if ($ad) { $ad."$($par[1])" } else { $null })
                if ($ad -and $ad."$($par[2])" -eq $true) { $texto = "$texto (disco do sistema)" }
                Add-WinForgeDiagLine $sec $par[0] $texto
            }
        }
        $sections.Add($sec)
    }

    return @($sections)
}

function Get-WinForgeDiagRecommendationItems {
    <#
    .SYNOPSIS
        Lista pronta para exibir do que as regras recomendaram e do que desaconselharam.
    .DESCRIPTION
        Só entra chave que existe na configuração de tweaks: uma regra pode citar uma entrada que a
        auditoria removeu, e mostrar o nome cru da chave não ajudaria ninguém. Recomendados primeiro,
        na ordem em que as regras os produziram.
    .OUTPUTS
        Array de @{ Key; Content; Reason; Icon; Resource; Hex; Kind }.
    #>
    $items = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $sync) { return @($items) }

    foreach ($group in @(
        @{ Map = $sync.Recommended; Icon = '✔'; Resource = 'RecommendedColor'; Hex = '#22C55E'; Kind = 'recomendado' },
        @{ Map = $sync.Discouraged; Icon = '⚠'; Resource = 'DiscouragedColor'; Hex = '#F59E0B'; Kind = 'evitar' }
    )) {
        if (-not $group.Map) { continue }
        foreach ($key in @($group.Map.Keys)) {
            if (-not $key) { continue }
            $entry = $sync.configs.tweaks.$key
            if ($null -eq $entry) { continue }
            $items.Add([pscustomobject]@{
                Key     = [string]$key
                Content = $(if ($entry.Content) { [string]$entry.Content } else { [string]$key })
                Reason  = [string]$group.Map[$key]
                Icon    = [string]$group.Icon
                Resource = [string]$group.Resource
                Hex     = [string]$group.Hex
                Kind    = [string]$group.Kind
            })
        }
    }
    return @($items)
}

function Get-WinForgeRecommendationTab {
    <#
    .SYNOPSIS
        Aba em que mora a caixa de verdade de uma chave recomendada ('Tweaks', 'Jogos' ou 'Servidor').
    .DESCRIPTION
        Mesma leitura que Select-WinForgeRecommended faz do campo 'tab' da entrada: sem esse campo (ou
        com um valor que não é aba própria) a entrada aparece na aba Ajustes.
    #>
    param([Parameter(Mandatory)][string]$Key)

    $entry = $sync.configs.tweaks.$Key
    if ($entry -and $entry.PSObject.Properties['tab'] -and [string]$entry.tab -in @('Jogos', 'Servidor')) { return [string]$entry.tab }
    return 'Tweaks'
}

function Test-WinForgeRecommendationToggle {
    <#
    .SYNOPSIS
        Diz se a chave recomendada é um Toggle (interruptor que aplica o tweak no clique).
    .DESCRIPTION
        Toggle não entra no checklist do Diagnóstico pelo mesmo motivo que Select-WinForgeRecommended
        o pula: marcar um Toggle APLICA a mudança na hora, e recomendar não é aplicar. A linha dele
        continua na lista, só sem caixa de marcar.
    #>
    param([Parameter(Mandatory)][string]$Key)

    if ($Key -like 'WPFToggle*') { return $true }
    $entry = $sync.configs.tweaks.$Key
    return ($entry -and [string]$entry.Type -eq 'Toggle')
}

function Test-WinForgeDiagRecApplied {
    <#
    .SYNOPSIS
        Diz se a chave de uma linha do checklist já está aplicada neste sistema.
    .DESCRIPTION
        Lê o conjunto guardado pelo diagnóstico ($sync.AppliedTweaks, ver wf-applied.ps1) - não
        detecta nada por conta própria: o checklist é redesenhado a cada marca, e uma varredura do
        registro por linha travaria a janela.
        Antes do primeiro diagnóstico o conjunto é nulo e a resposta é $false, que é o estado
        conservador: nenhuma linha nasce "aplicada" sem prova.
    #>
    param([Parameter(Mandatory)][string]$Key)

    if ($null -eq $sync.AppliedTweaks) { return $false }
    if (-not (Test-WinForgeAppliedEligible -Key $Key)) { return $false }
    return [bool]$sync.AppliedTweaks.Contains($Key)
}

function Test-WinForgeRecommendationAvailable {
    <#
    .SYNOPSIS
        Diz se a chave recomendada TEM uma caixa de verdade nesta máquina - sem montar aba nenhuma.
    .DESCRIPTION
        A linha do checklist precisa saber disso na hora em que é DESENHADA, e não no clique. Antes,
        a linha nascia habilitada, o usuário clicava, a aba de destino era montada, a caixa não
        existia e só aí a linha se desabilitava - com a marca já dada e o total do contador já
        contando com ela.
        A resposta sai do mesmo par de regras que esconde a entrada na aba: platform/role/os/gpu
        (Test-WinUtilBoostEntryCompatible) e a aba Servidor, que num cliente não é montada. Nenhuma
        das duas precisa da aba na tela, então a pergunta é barata e não tem efeito colateral.
    #>
    param([Parameter(Mandatory)][string]$Key)

    $entry = $sync.configs.tweaks.$Key
    if ($null -eq $entry) { return $false }
    if ((Get-WinForgeRecommendationTab -Key $Key) -eq 'Servidor' -and -not $sync.IsServer) { return $false }
    return [bool](Test-WinUtilBoostEntryCompatible $entry)
}

function Get-WinForgeRecommendationControl {
    <#
    .SYNOPSIS
        Caixa de verdade de uma chave recomendada, montando a aba de destino se ela ainda não existir.
    .DESCRIPTION
        As abas nascem sob demanda: enquanto Ajustes/Jogos/Servidor não forem abertas, $sync[<chave>]
        é nulo e o espelho não teria em que mexer. Montar é idempotente e custa o mesmo que abrir a
        aba na mão. A aba Servidor só é montada em Windows Server - num cliente todas as entradas dela
        têm platform 'server' e a montagem criaria zero controle.
    .OUTPUTS
        O CheckBox, ou $null quando o filtro de compatibilidade escondeu a entrada nesta máquina.
    #>
    param([Parameter(Mandatory)][string]$Key)

    $tab = Get-WinForgeRecommendationTab -Key $Key
    if ($tab -eq 'Servidor' -and -not $sync.IsServer) { return $null }
    if (-not ($sync.InitializedTabs -and $sync.InitializedTabs[$tab])) {
        if (Get-Command Initialize-WinForgeTabContent -ErrorAction SilentlyContinue) {
            try { Initialize-WinForgeTabContent -TabName $tab } catch {
                Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Não foi possível montar a aba $tab para o espelho de '$Key': $($_.Exception.Message)"
            }
        }
    }
    $control = $sync[$Key]
    if ($control -isnot [System.Windows.Controls.CheckBox]) { return $null }
    return $control
}

function Update-WinForgeDiagActionButtons {
    <#
    .SYNOPSIS
        Liga e desliga "Aplicar marcados" / "Desfazer marcados" conforme já existe trabalho em andamento.
    .DESCRIPTION
        Os dois botões chamam Invoke-WPFtweaksbutton / Invoke-WPFundoall, que recusam com
        $sync.ProcessRunning ligado mostrando uma caixa de mensagem. Desabilitar é dar esse aviso
        ANTES do clique, em vez de depois dele.
        ESTA FUNÇÃO NÃO ESCREVE EM $sync: ela é chamada de Update-WinForgeDiagRecommendationCount,
        que por sua vez roda dentro de Sync-WinForgeRecommendationMirror - caminho que percorre
        $sync com GetEnumerator() e derruba os presets se alguém escrever ali (ver o comentário
        daquela função). Ler $sync[<nome>] e mexer na propriedade do botão é seguro.
        Sai calada quando os botões ainda não existem: o contador roda antes de a janela estar
        montada (primeiro diagnóstico, SelfTest).
    #>
    if ($null -eq $sync) { return }

    $habilitado = -not $sync.ProcessRunning
    foreach ($nome in 'WPFDiagApplySelected', 'WPFDiagUndoSelected') {
        $botao = $sync[$nome]
        if ($botao -is [System.Windows.Controls.Button]) { $botao.IsEnabled = $habilitado }
    }
}

function Update-WinForgeDiagRecommendationCount {
    <#
    .SYNOPSIS
        Reescreve o contador "N de M recomendados marcados" da aba Diagnóstico.
    .DESCRIPTION
        Conta os espelhos, não os controles reais: a lista é o que o usuário está olhando.
        Linha DESABILITADA fica de fora dos dois números. Ela é uma recomendação que não se aplica a
        esta máquina - ninguém consegue marcá-la, e contá-la no M deixaria o contador parado em
        "15 de 16" com tudo marcado, o que parece defeito.
    #>
    if ($null -eq $sync) { return }
    # Antes da saída antecipada do contador: os botões de ação não dependem do rótulo existir, e
    # este é o ponto da interface que roda a cada marca, a cada diagnóstico e a cada aba montada.
    Update-WinForgeDiagActionButtons
    if ($null -eq $sync.WPFDiagRecCount) { return }

    $total = 0
    $marcados = 0
    $aplicados = 0
    if ($sync.WinForgeDiagMirrors) {
        foreach ($key in @($sync.WinForgeDiagMirrors.Keys)) {
            $mirror = $sync.WinForgeDiagMirrors[$key]
            if ($null -eq $mirror -or -not $mirror.IsEnabled) { continue }
            $total++
            if ($mirror.IsChecked) { $marcados++ }
            if (Test-WinForgeDiagRecApplied -Key $key) { $aplicados++ }
        }
    }
    # A terceira conta entra sempre, inclusive zerada: contador que muda de formato conforme o
    # resultado obriga quem lê (e quem testa) a decorar dois formatos.
    $sync.WPFDiagRecCount.Text = "$marcados de $total recomendados marcados · $aplicados já aplicados"
}

function Set-WinForgeRecommendationMirror {
    <#
    .SYNOPSIS
        Leva a marca de uma linha do checklist do Diagnóstico para a caixa de verdade da aba de destino.
    .DESCRIPTION
        Chamada pelos eventos Checked/Unchecked da linha. A trava $sync.WinForgeMirrorBusy existe
        porque o caminho de volta também existe: mexer no controle real dispara o handler que reescreve
        a linha, e sem a trava os dois ficariam se avisando em laço.
        Chave sem controle depois de montar a aba é entrada que o filtro de compatibilidade escondeu
        nesta máquina: a linha fica desabilitada, com a dica dizendo isso, em vez de mentir que marcou.
        A saída antecipada quando a caixa de verdade JÁ está no estado pedido não é otimização: é o
        que mantém esta função sem escrever em $sync quando ela é chamada de dentro do laço de
        Reset-WPFCheckBoxes, que enumera $sync - ver o comentário em Sync-WinForgeRecommendationMirror.
    .OUTPUTS
        $true se a caixa de verdade já está (ou acabou de ficar) no estado pedido.
    #>
    param([Parameter(Mandatory)][string]$Key, [bool]$Checked)

    if ($sync.WinForgeMirrorBusy) { return $false }

    $mirror = if ($sync.WinForgeDiagMirrors) { $sync.WinForgeDiagMirrors[$Key] } else { $null }
    $control = Get-WinForgeRecommendationControl -Key $Key

    if ($null -eq $control) {
        if ($mirror) {
            $mirror.IsEnabled = $false
            $mirror.ToolTip = "não se aplica a este computador"
            if ($mirror.IsChecked) { $mirror.IsChecked = $false }
        }
        Update-WinForgeDiagRecommendationCount
        return $false
    }

    if ([bool]$control.IsChecked -eq $Checked) {
        Update-WinForgeDiagRecommendationCount
        return $true
    }

    $sync.WinForgeMirrorBusy = $true
    try { $control.IsChecked = $Checked } finally { $sync.WinForgeMirrorBusy = $false }
    Update-WinForgeDiagRecommendationCount
    return $true
}

function Sync-WinForgeRecommendationMirror {
    <#
    .SYNOPSIS
        Caminho de volta: a caixa marcada na aba Ajustes/Jogos/Servidor reescreve a linha do checklist.
    .DESCRIPTION
        Ligada uma vez por controle em Update-WinForgeRecommendationVisuals. Sai calada quando a
        recomendação não tem linha (a aba Diagnóstico ainda não foi redesenhada, ou a chave deixou de
        ser recomendada no último diagnóstico).
        ESTA FUNÇÃO NÃO ESCREVE EM $sync, nem para ligar a trava. Ela roda dentro dos eventos
        Checked/Unchecked da caixa de verdade, e um deles é disparado de dentro de Reset-WPFCheckBoxes,
        que percorre $sync com GetEnumerator(). Qualquer escrita em $sync ali - inclusive trocar o
        valor de uma chave que já existe - invalida o enumerador e derruba a aplicação de presets com
        "coleção foi modificada". O laço de volta se fecha sozinho: marcar a linha dispara
        Set-WinForgeRecommendationMirror, que vê a caixa de verdade já no estado pedido e para.
    #>
    param([Parameter(Mandatory)][string]$Key, [bool]$Checked)

    if ($sync.WinForgeMirrorBusy) { return }
    $mirror = if ($sync.WinForgeDiagMirrors) { $sync.WinForgeDiagMirrors[$Key] } else { $null }
    if ($null -eq $mirror -or [bool]$mirror.IsChecked -eq $Checked) { return }

    $mirror.IsChecked = $Checked
    Update-WinForgeDiagRecommendationCount
}

function Set-WinForgeDiagRecommendationSelection {
    <#
    .SYNOPSIS
        Marca ou desmarca todas as linhas do checklist do Diagnóstico (botões "Marcar todos" e
        "Desmarcar todos").
    .DESCRIPTION
        Mexe nas linhas, não nos controles reais: o evento de cada linha é que leva a marca para a aba
        de destino, montando-a se preciso. Linha desabilitada (entrada que não existe nesta máquina)
        fica de fora.
        Linha JÁ APLICADA fica de fora do "Marcar todos", e só dele: marcar em massa o que já está
        no sistema é exatamente o trabalho repetido que o usuário reclamou. Quem quiser reaplicar
        uma delas continua podendo marcá-la na mão, e "Desmarcar todos" continua limpando tudo.
    .OUTPUTS
        Quantidade de linhas que terminaram no estado pedido.
    #>
    param([bool]$Checked)

    if ($null -eq $sync.WinForgeDiagMirrors) { return 0 }

    $count = 0
    foreach ($key in @($sync.WinForgeDiagMirrors.Keys)) {
        $mirror = $sync.WinForgeDiagMirrors[$key]
        if ($null -eq $mirror -or -not $mirror.IsEnabled) { continue }
        if ($Checked -and (Test-WinForgeDiagRecApplied -Key $key)) { continue }
        $mirror.IsChecked = $Checked
        if ([bool]$mirror.IsChecked -eq $Checked) { $count++ }
    }
    Update-WinForgeDiagRecommendationCount
    Write-WinForgeLog -Component "Diag" -Message "Checklist do Diagnóstico: $count linha(s) $(if ($Checked) { 'marcada(s)' } else { 'desmarcada(s)' })."
    return $count
}

function New-WinForgeDiagRecRow {
    <#
    .SYNOPSIS
        Uma linha da lista de recomendações: caixa de marcar (quando dá para marcar) + o motivo.
    .DESCRIPTION
        Recomendação comum vira CheckBox espelhada na aba de destino. Item a evitar e Toggle viram
        texto: o primeiro não é para marcar, e o segundo aplicaria a mudança no clique.
        DockPanel, e não StackPanel horizontal: o motivo é a última filha e precisa quebrar linha
        dentro do espaço que sobra, senão a lista sai da largura da janela.
    #>
    param([Parameter(Mandatory)]$Item)

    $row = New-Object System.Windows.Controls.DockPanel
    $row.LastChildFill = $true
    $row.Margin = New-Object System.Windows.Thickness(0, 2, 0, 2)

    $key = [string]$Item.Key
    if ($Item.Kind -eq 'recomendado' -and -not (Test-WinForgeRecommendationToggle -Key $key)) {
        $head = New-Object System.Windows.Controls.CheckBox
        $head.Tag = $key
        # O sufixo vai no próprio texto da linha, e não num TextBlock ao lado como na aba Ajustes:
        # aqui a lista inteira é redesenhada a cada diagnóstico, então não há marca velha para
        # reconhecer nem para tirar.
        $head.Content = "$($Item.Icon) $($Item.Content)$(if (Test-WinForgeDiagRecApplied -Key $key) { ' · aplicado' })"
        Set-WinForgeStatusBrush -Element $head -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Resource ([string]$Item.Resource) -Fallback ([string]$Item.Hex)
        $head.VerticalAlignment = 'Center'
        $head.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        # A disponibilidade é perguntada AGORA, na hora de desenhar, e não no clique: a linha de uma
        # recomendação que não existe nesta máquina nasce desabilitada, com a dica dizendo por quê,
        # em vez de aceitar a marca e se desabilitar depois (ver Test-WinForgeRecommendationAvailable).
        if (Test-WinForgeRecommendationAvailable -Key $key) {
            $head.ToolTip = "Marca também a caixa correspondente na aba $(Get-WinForgeRecommendationTab -Key $key)."
        } else {
            $head.IsEnabled = $false
            $head.ToolTip = "não se aplica a este computador"
        }
        $head.SetResourceReference([System.Windows.Controls.Control]::FontSizeProperty, "FontSize")
        [System.Windows.Automation.AutomationProperties]::SetName($head, [string]$Item.Content)
        # O handler lê a chave da Tag do controle que disparou: a lista é redesenhada a cada
        # diagnóstico, e um scriptblock que guardasse $key apontaria para a linha da rodada anterior.
        $head.Add_Checked({
            [System.Object]$Sender = $args[0]
            Set-WinForgeRecommendationMirror -Key ([string]$Sender.Tag) -Checked $true | Out-Null
        })
        $head.Add_Unchecked({
            [System.Object]$Sender = $args[0]
            Set-WinForgeRecommendationMirror -Key ([string]$Sender.Tag) -Checked $false | Out-Null
        })
        if ($null -eq $sync.WinForgeDiagMirrors) { $sync.WinForgeDiagMirrors = @{} }
        $sync.WinForgeDiagMirrors[$key] = $head
    } else {
        $head = New-Object System.Windows.Controls.TextBlock
        $head.Text = "$($Item.Icon) $($Item.Content)"
        Set-WinForgeStatusBrush -Element $head -Property ([System.Windows.Controls.TextBlock]::ForegroundProperty) -Resource ([string]$Item.Resource) -Fallback ([string]$Item.Hex)
        $head.VerticalAlignment = 'Center'
        $head.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        $head.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSize")
    }
    [System.Windows.Controls.DockPanel]::SetDock($head, 'Left')
    $row.Children.Add($head) | Out-Null

    $reason = New-Object System.Windows.Controls.TextBlock
    $reason.Text = "— $($Item.Reason)"
    $reason.TextWrapping = 'Wrap'
    $reason.VerticalAlignment = 'Center'
    $reason.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSize")
    $reason.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MainForegroundColor")
    $row.Children.Add($reason) | Out-Null

    return $row
}

function Get-WinForgeDiagDriverRows {
    <#
    .SYNOPSIS
        Linhas da tabela de drivers a partir do inventário do perfil.
    .DESCRIPTION
        'Url' vira $null quando não há página de fabricante conhecida: o relatório HTML liga o texto
        ao endereço, e uma string vazia ali só produziria um link morto.

        A LINHA carrega a ação (ActionKind/ActionLabel/ActionUrl) porque é ela que viaja na Tag do
        botão da coluna "Ação" até o handler - a tabela é redesenhada a cada diagnóstico, e um índice
        guardado no clique apontaria para a linha da rodada anterior. 'ActionVisible' é texto de
        Visibility ('Visible'/'Collapsed') e não booleano: é o que o XAML liga direto na propriedade,
        sem precisar de conversor.

        'ActionEnabled' desabilita o botão de download quando o WinForge não está elevado. A pasta
        %ProgramData%\WinForge\downloads é de SYSTEM/Administradores e Confirm-WinForgeDownloadRoot
        recusa criá-la sem elevação - antes disso o botão aceitava o clique, confirmava com o
        usuário e só então dizia que não dava. Abrir a página do fabricante continua habilitado:
        isso é o navegador do usuário, não precisa de elevação nenhuma.
    .OUTPUTS
        ObservableCollection de PSCustomObject (o DataGrid liga direto nela).
    #>
    param($Profile)

    if ($null -eq $Profile) { $Profile = $sync.Profile }
    # Uma pergunta só para a tabela inteira: a elevação não muda entre uma linha e outra.
    $elevado = [bool](Test-WinForgeRepairElevated)
    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($d in @($Profile.Drivers)) {
        if ($null -eq $d) { continue }
        $status = [string]$d.Status
        if ([string]::IsNullOrWhiteSpace($status)) { $status = 'ok' }
        $icon = switch ($status) { 'atualizar' { '⬆' } 'verificar' { '⚠' } default { '✓' } }
        $url = [string]$d.Url
        if ([string]::IsNullOrWhiteSpace($url)) { $url = $null }
        $acao = Get-WinForgeDriverAction -Driver $d
        $rows.Add([pscustomobject]@{
            Device        = [string]$d.Device
            Class         = [string]$d.Class
            Version       = (Format-WinForgeDiagValue $d.Version)
            Date          = (Format-WinForgeDiagValue $d.Date)
            Provider      = [string]$d.Provider
            Status        = $status
            StatusText    = "$icon $status"
            Latest        = [string]$d.Latest
            Url           = $url
            UrlLabel      = $(if ($url) { 'página do fabricante' } else { '' })
            ActionKind    = [string]$acao.Kind
            ActionLabel   = [string]$acao.Label
            ActionUrl     = $acao.Url
            ActionVisible = $(if ([string]$acao.Kind -eq 'none') { 'Collapsed' } else { 'Visible' })
            ActionEnabled = $([bool]($elevado -or [string]$acao.Kind -ne 'nvidia-download'))
            ActionTip     = $(if (-not $elevado -and [string]$acao.Kind -eq 'nvidia-download') { $WinForgeElevationTip } else { switch ([string]$acao.Kind) {
                'nvidia-download' { "Baixa o instalador oficial do driver $($acao.Label -replace '^Baixar ', '') do site da NVIDIA, confere a assinatura e abre o instalador." }
                'vendor-page'     { "Abre a página de download do fabricante no navegador." }
                default           { $null }
            } })
        })
    }
    return ,$rows
}

# Resultado da consulta ao vivo esperando a thread da janela: quem escreve é o runspace, quem lê é
# o callback abaixo. Um slot só, porque um trabalho por vez ($sync.CommandRunning) já é a regra.
$sync.WinForgeDriverConfirm = $null

# A caixa de confirmação do download NVIDIA, de volta na thread da janela. Nasce AQUI, no escopo do
# arquivo e portanto na runspace principal, e não dentro do corpo do job: um scriptblock criado numa
# runspace do pool e executado pelo Dispatcher trava na primeira pipeline - a thread da janela pede
# a runspace de origem, que está parada esperando o Dispatcher terminar. É o mesmo laço que matou o
# diagnóstico calado na tarefa do Plano 3, e a razão de $sync.WinForgeCommandOutputCallback existir.
#
# Invoke-WPFUIThread chama o bloco SEM argumento (Dispatcher.Invoke([action]) não passa parâmetro),
# então o resultado da consulta viaja pelo slot $sync.WinForgeDriverConfirm.
#
# A trava $sync.CommandRunning foi ligada no clique e é SEGURADA até aqui: ela só solta quando não
# há mais nada por vir - recusa da consulta, "Não" na caixa, ou despacho do download que falhou. No
# "Sim" ela continua ligada e quem solta é o 'finally' do corpo do download.
$sync.WinForgeDriverConfirmCallback = {
    $pendente = $sync.WinForgeDriverConfirm
    $sync.WinForgeDriverConfirm = $null
    try {
        if ($null -eq $pendente) {
            $sync.CommandRunning = $false
            return
        }
        if (-not $pendente.Ok) {
            $recusa = "Download do driver NVIDIA recusado: $([string]$pendente.Reason)."
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $recusa
            $null = Set-WinForgeDiagProgress -Label $recusa -Percent 0
            $sync.CommandRunning = $false
            return
        }

        $versao = [string]$pendente.Version
        $null = Set-WinForgeDiagProgress -Label "Catálogo da NVIDIA: versão $versao disponível." -Percent 0
        $resposta = [System.Windows.MessageBox]::Show($sync.Form,
            "Baixar o driver NVIDIA $versao do site oficial ($([string]$pendente.SizeText))? O instalador abrirá para você concluir.",
            "WinForge", "YesNo", "Warning")
        if ($resposta -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-WinForgeLog -Component "Diag" -Message "Download do driver NVIDIA $versao cancelado pelo usuário."
            $null = Set-WinForgeDiagProgress -Label "Download do driver NVIDIA cancelado." -Percent 0
            $sync.CommandRunning = $false
            return
        }

        # Nasce na thread da janela, que é a runspace principal - mesma regra do callback.
        $corpoDownload = {
            param($wfArgs)
            # Sem isto o Invoke-WebRequest do PowerShell 5.1 emite um registro de progresso por bloco
            # lido e fica uma ordem de grandeza mais lento num arquivo de 700 MB - e o corpo roda num
            # runspace preso ao host do console, que desenha esses registros.
            $ProgressPreference = 'SilentlyContinue'
            try {
                $null = Set-WinForgeDiagProgress -Label "Baixando o driver NVIDIA $($wfArgs.Version) do site oficial..." -Percent 10
                $wfRes = Install-WinForgeNvidiaDriver -Url $wfArgs.Url -Version $wfArgs.Version
                $null = Set-WinForgeDiagProgress -Label ([string]$wfRes.Text) -Percent $(if ($wfRes.Started) { 100 } else { 0 })
            } catch {
                Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Download do driver NVIDIA falhou: $($_.Exception.Message)"
                $null = Set-WinForgeDiagProgress -Label "Download do driver NVIDIA falhou: $($_.Exception.Message)" -Percent 0
            } finally {
                $sync.CommandRunning = $false
            }
        }
        try {
            # O par Url/Version é o que a consulta ao vivo acabou de trazer, e viaja como ARGUMENTO:
            # o endereço vem da rede, e texto de fora não vira código.
            Invoke-WPFRunspace -ScriptBlock $corpoDownload -ArgumentList @{ Url = [string]$pendente.Url; Version = $versao } | Out-Null
        } catch {
            # Despacho que falha (pool fechado, sem thread livre) nunca roda o 'finally' do corpo:
            # sem este catch a trava ficaria ligada e nenhum outro comando começaria.
            $sync.CommandRunning = $false
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Download do driver NVIDIA não pôde começar: $($_.Exception.Message)"
            $null = Set-WinForgeDiagProgress -Label "Download do driver NVIDIA não pôde começar: $($_.Exception.Message)" -Percent 0
        }
    } catch {
        $sync.CommandRunning = $false
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Confirmação do download do driver NVIDIA falhou: $($_.Exception.Message)"
    }
}

function Invoke-WinForgeDriverAction {
    <#
    .SYNOPSIS
        O que o botão da coluna "Ação" faz: abrir a página do fabricante ou baixar o driver NVIDIA.
    .DESCRIPTION
        Recebe a LINHA da tabela (a que veio na Tag do botão), não um índice. A página do fabricante
        abre direto - é o navegador do usuário abrindo um endereço, sem download e sem execução. O
        download da NVIDIA pergunta antes, porque são centenas de megabytes e porque o instalador vai
        abrir uma janela na cara de quem clicou.

        O que a linha diz sobre a VERSÃO e o ENDEREÇO do driver não é usado para baixar nada: a
        linha foi desenhada a partir do cache do catálogo, que mora no perfil do usuário. No clique,
        Resolve-WinForgeNvidiaDownloadTarget refaz a consulta ao catálogo ao vivo e é o resultado
        DELA que vai para Install-WinForgeNvidiaDriver - inclusive a versão que aparece na caixa de
        confirmação. Recusa da consulta ao vivo (sem rede, endereço fora do domínio, versão que não
        é mais nova que a instalada) não vira caixa nenhuma: vai para a barra de status e para o log.

        A trava de SelfTest vem ANTES da caixa de confirmação, pela mesma razão de
        Invoke-WinForgeRepairCommand: num build sem ninguém na frente, uma caixa modal pendura tudo.

        A CONSULTA em si não roda no clique. São três requisições de 5 s mais a do tamanho (10 s):
        na thread da janela isso era até ~25 s congelado, com o agravante de o rótulo "Consultando
        o catálogo..." nunca aparecer - quem pinta é o Dispatcher, e o Dispatcher estava parado
        dentro do handler do clique. O clique liga a trava, escreve na barra e despacha; o runspace
        consulta e guarda o resultado em $sync.WinForgeDriverConfirm; a caixa de confirmação volta
        para a thread da janela por Invoke-WPFUIThread com $sync.WinForgeDriverConfirmCallback, e é
        de lá que sai o runspace do download, já com o par Url/Version que acabou de chegar.

        O corpo do job e o callback nascem os dois na runspace PRINCIPAL (esta função roda no
        clique; o callback é de escopo de arquivo). Um scriptblock criado dentro do corpo do job
        pertenceria à runspace do pool e travaria no primeiro pipeline quando o Dispatcher o
        executasse - o mesmo laço descrito em Start-WinForgeProfileJob. E os dados viajam como
        ARGUMENTO, nunca concatenados num texto de comando: o endereço vem da rede, e texto de fora
        não vira código.
    .PARAMETER DryRun
        Faz a consulta ao vivo e devolve o que FARIA, sem caixa, sem rede de download e sem disco.
        É o que o -SelfTest usa para provar que o endereço vem da consulta e não da linha.
    .PARAMETER Root
        Pasta de cache própria (usada pelo -SelfTest).
    .PARAMETER Resolver
        Costura de teste da consulta ao catálogo - ver Get-WinForgeNvidiaCatalog.
    .OUTPUTS
        Texto curto com o que foi feito ('none', 'vendor-page', 'nvidia-download', 'ocupado',
        'recusado').
    #>
    param($Row, [switch]$DryRun, [string]$Root, [scriptblock]$Resolver)

    if ($null -eq $Row) { return 'none' }
    $tipo = [string]$Row.ActionKind
    if ([string]::IsNullOrWhiteSpace($tipo) -or $tipo -eq 'none') { return 'none' }

    if ($tipo -eq 'vendor-page') {
        Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeDriverAction (vendor-page)'
        $endereco = [string]$Row.ActionUrl
        # O endereço sai de uma tabela literal do programa (Get-WinForgeVendorDriverUrl), mas quem
        # chega até aqui é a LINHA, e Start-Process abre tanto endereço quanto arquivo: sem conferir
        # o esquema, uma linha com um caminho no lugar da URL viraria execução com a elevação do
        # WinForge. Duas linhas de conferência custam menos que confiar na origem do dado.
        $uri = $null
        try { $uri = [uri]$endereco } catch { $uri = $null }
        if ($null -eq $uri -or -not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https')) {
            Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Endereço recusado para '$($Row.Device)': '$endereco' não é http/https."
            return 'vendor-page'
        }
        try {
            Start-Process $endereco
            Write-WinForgeLog -Component "Diag" -Message "Página do fabricante aberta para '$($Row.Device)': $endereco"
        } catch {
            Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Não foi possível abrir '$endereco': $($_.Exception.Message)"
        }
        return 'vendor-page'
    }

    if ($tipo -ne 'nvidia-download') { return 'none' }

    # A simulação sai antes da trava de SelfTest e antes de qualquer caixa: ela existe justamente
    # para o -SelfTest poder exercitar a consulta ao vivo com a costura de Get-WinForgeNvidiaCatalog.
    if ($DryRun) {
        $alvoSeco = Resolve-WinForgeNvidiaDownloadTarget -Row $Row -Root $Root -Resolver $Resolver
        if (-not $alvoSeco.Ok) { return "[simulação] consulta ao vivo recusou o download: $($alvoSeco.Reason)" }
        return "[simulação] consulta ao vivo: baixaria o driver NVIDIA $($alvoSeco.Version) de '$($alvoSeco.Url)'"
    }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeDriverAction (nvidia-download)'

    # ProcessRunning junto com CommandRunning: um ajuste, um AppX ou a criação do ISO também mexem
    # na máquina e também podem pedir reinício, e a barra de progresso é uma só para todos.
    if ($sync.CommandRunning -or $sync.ProcessRunning) {
        [System.Windows.MessageBox]::Show("Já existe um trabalho em andamento. Espere ele terminar.", "WinForge", "OK", "Warning") | Out-Null
        return 'ocupado'
    }

    # A consulta ao vivo NÃO roda aqui. São três requisições de 5 s mais a do tamanho (10 s): na
    # thread do clique isso é até ~25 s de janela congelada, e o rótulo abaixo nem chegava a ser
    # pintado, porque quem pinta é o Dispatcher e o Dispatcher estava parado dentro deste handler.
    # Então o clique faz três coisas instantâneas - liga a trava, escreve na barra, despacha - e
    # quem pergunta ao catálogo é o runspace.
    $sync.CommandRunning = $true
    $sync.WinForgeDriverConfirm = $null
    $null = Set-WinForgeDiagProgress -Label "Consultando o catálogo da NVIDIA..." -Percent 5
    $corpo = {
        param($wfArgs)
        $ProgressPreference = 'SilentlyContinue'
        try {
            # Continua sendo a consulta ao vivo que decide o texto da caixa: perguntar por uma versão
            # e baixar outra seria pedir permissão para uma coisa e fazer outra. O que mudou é só a
            # thread em que ela roda.
            $wfAlvo = Resolve-WinForgeNvidiaDownloadTarget -Row $wfArgs.Row -Root $wfArgs.Root -Resolver $wfArgs.Resolver
            if ($wfAlvo.Ok) {
                $sync.WinForgeDriverConfirm = @{
                    Ok = $true; Url = [string]$wfAlvo.Url; Version = [string]$wfAlvo.Version
                    SizeText = [string](Get-WinForgeNvidiaDownloadSizeText -Url ([string]$wfAlvo.Url)); Reason = ''
                }
            } else {
                $sync.WinForgeDriverConfirm = @{ Ok = $false; Url = $null; Version = $null; SizeText = $null; Reason = [string]$wfAlvo.Reason }
            }
        } catch {
            $sync.WinForgeDriverConfirm = @{ Ok = $false; Url = $null; Version = $null; SizeText = $null; Reason = [string]$_.Exception.Message }
        }
        # Janela fechando: o Dispatcher já está desligando e Invoke-WPFUIThread ficaria parado
        # esperando por ele. Sem ninguém para mostrar a caixa, a trava solta aqui mesmo.
        if ($sync.WinForgeClosing) { $sync.CommandRunning = $false; return }
        Invoke-WPFUIThread $sync.WinForgeDriverConfirmCallback
    }
    try {
        # A linha e a costura de teste viajam como ARGUMENTO, nunca concatenadas num texto de
        # comando: o endereço vem da rede, e texto de fora não vira código.
        Invoke-WPFRunspace -ScriptBlock $corpo -ArgumentList @{ Row = $Row; Root = $Root; Resolver = $Resolver } | Out-Null
    } catch {
        # Despacho que falha (pool fechado, sem thread livre) nunca roda o corpo nem o callback: sem
        # este catch a trava ficaria ligada e nenhum outro comando começaria.
        $sync.CommandRunning = $false
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Consulta ao catálogo da NVIDIA não pôde começar: $($_.Exception.Message)"
        $null = Set-WinForgeDiagProgress -Label "Consulta ao catálogo da NVIDIA não pôde começar: $($_.Exception.Message)" -Percent 0
    }
    return 'nvidia-download'
}

function Get-WinForgeWindowsUpdateRowState {
    <#
    .SYNOPSIS
        O estado de instalação de uma atualização nesta sessão.
    .DESCRIPTION
        O mapa é $sync.DiagWUState, indexado pelo id da atualização, e vale só enquanto a janela
        estiver aberta: o Windows Update é a fonte da verdade entre uma sessão e outra, e guardar
        "instalado" em disco significaria mentir na próxima abertura se a instalação for revertida.
        Aceita tanto o registro completo (@{ State; Text }) quanto um texto solto com o nome do
        estado - o texto é a forma mais fácil de escrever à mão, inclusive nos testes.
        Id desconhecido é 'pendente' com texto vazio: a coluna "Situação" fica em branco enquanto
        nada aconteceu, que é o que uma tabela recém-buscada tem a dizer.
    .OUTPUTS
        @{ State = 'pendente'|'instalando'|'instalado'|'falhou'; Text = [string] }
    #>
    param([string]$UpdateId)

    $vazio = @{ State = 'pendente'; Text = '' }
    if ([string]::IsNullOrWhiteSpace($UpdateId) -or $null -eq $sync.DiagWUState) { return $vazio }
    $bruto = $sync.DiagWUState[[string]$UpdateId]
    if ($null -eq $bruto) { return $vazio }
    if ($bruto -is [string]) { return @{ State = [string]$bruto; Text = [string]$bruto } }
    $estado = [string]$bruto.State
    if ([string]::IsNullOrWhiteSpace($estado)) { return $vazio }
    return @{ State = $estado; Text = [string]$bruto.Text }
}

function Set-WinForgeWindowsUpdateRowState {
    <#
    .SYNOPSIS
        Escreve o estado de instalação de uma atualização no mapa da sessão.
    .DESCRIPTION
        Escrita só pela thread da janela (o clique e o callback), que é a mesma que lê o mapa ao
        remontar a tabela - por isso uma tabela de hash comum basta.
    .OUTPUTS
        O registro gravado.
    #>
    param(
        [Parameter(Mandatory)][string]$UpdateId,
        [Parameter(Mandatory)][string]$State,
        [string]$Text
    )

    if ($null -eq $sync.DiagWUState) { $sync.DiagWUState = @{} }
    $registro = @{ State = $State; Text = [string]$Text }
    $sync.DiagWUState[$UpdateId] = $registro
    return $registro
}

function Set-WinForgeWindowsUpdateInstallResult {
    <#
    .SYNOPSIS
        Transforma o resultado do serviço COM no estado que a linha vai mostrar.
    .DESCRIPTION
        2 e 3 são os códigos de sucesso do Windows Update (3 é "concluído com avisos"); qualquer
        outro é falha. O código entra no texto da linha porque é a única coisa pesquisável que
        sobra de uma falha do Windows Update - menos o -1, que é a nossa marca para "estourou antes
        de chegar a um código" e não significa nada para quem for procurar.
        Função à parte do callback de propósito: assim o -SelfTest prova o mapeamento sem precisar
        de janela, de caixa de mensagem e, principalmente, sem instalar nada.
    .OUTPUTS
        O registro gravado (@{ State; Text }).
    #>
    param(
        [Parameter(Mandatory)][string]$UpdateId,
        [int]$ResultCode,
        [bool]$RebootRequired
    )

    if ($ResultCode -in @(2, 3)) {
        $texto = $(if ($RebootRequired) { 'instalado (reinicie)' } else { 'instalado' })
        return (Set-WinForgeWindowsUpdateRowState -UpdateId $UpdateId -State 'instalado' -Text $texto)
    }
    $textoFalha = $(if ($ResultCode -gt 0) { "falhou (código $ResultCode)" } else { 'falhou' })
    return (Set-WinForgeWindowsUpdateRowState -UpdateId $UpdateId -State 'falhou' -Text $textoFalha)
}

function Invoke-WinForgeWindowsUpdateAction {
    <#
    .SYNOPSIS
        O que o botão "Instalar" da tabela do Windows Update faz.
    .DESCRIPTION
        Mesmo desenho da ação de driver: trava de SelfTest antes da caixa, confirmação, um trabalho
        por vez ($sync.CommandRunning) e o serviço COM rodando fora da thread da janela - ele baixa e
        instala, e isso são minutos de interface congelada se rodar no clique.

        A caixa de mensagem no fim só aparece quando é preciso REINICIAR: o resto do resultado vai
        para a barra de status e para o log, que é onde o usuário já está olhando. Reinício pendente
        é a única coisa que ele precisa saber antes de continuar mexendo na máquina.

        Linha já instalada (ou instalando) é recusada AQUI, e não só pelo botão desabilitado: o
        botão é uma cortesia da tela, e o clique pode chegar por um caminho que não passou pela
        última remontagem da tabela. Instalar o mesmo driver duas vezes é minutos de máquina
        ocupada para nada.
    .PARAMETER NoUI
        Devolve o que FARIA, sem caixa, sem rede e sem instalar nada. É o que o -SelfTest usa para
        provar a recusa da linha já instalada.
    .OUTPUTS
        Texto curto com o que foi feito.
    #>
    param($Row, [switch]$NoUI)

    if ($null -eq $Row) { return 'none' }
    $id = [string]$Row.UpdateId
    if ([string]::IsNullOrWhiteSpace($id)) { return 'none' }

    $estadoAtual = [string](Get-WinForgeWindowsUpdateRowState -UpdateId $id).State
    if ($estadoAtual -eq 'instalado') {
        Write-WinForgeLog -Component "Diag" -Message "Instalação de '$($Row.Title)' recusada: já foi instalada nesta sessão."
        return 'já instalado'
    }
    if ($estadoAtual -eq 'instalando') {
        Write-WinForgeLog -Component "Diag" -Message "Instalação de '$($Row.Title)' recusada: já está em andamento."
        return 'instalando'
    }
    if ($NoUI) { return 'pendente' }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeWindowsUpdateAction'

    # ProcessRunning junto com CommandRunning: instalar driver pelo Windows Update no meio de uma
    # leva de ajustes é mexer na máquina duas vezes ao mesmo tempo, e os dois pedem reinício.
    if ($sync.CommandRunning -or $sync.ProcessRunning) {
        [System.Windows.MessageBox]::Show("Já existe um trabalho em andamento. Espere ele terminar.", "WinForge", "OK", "Warning") | Out-Null
        return 'ocupado'
    }

    $titulo = [string]$Row.Title
    $resposta = [System.Windows.MessageBox]::Show($sync.Form, "Instalar '$titulo' pelo Windows Update?", "WinForge", "YesNo", "Warning")
    if ($resposta -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-WinForgeLog -Component "Diag" -Message "Instalação de '$titulo' pelo Windows Update cancelada pelo usuário."
        return 'cancelado'
    }

    # Nasce na runspace principal, como todo bloco que o Dispatcher vai executar. Ele roda em TODO
    # desfecho, e não só quando é preciso reiniciar: é ele que pinta a linha de verde ou vermelho,
    # e uma instalação que falha calada é exatamente a queixa que trouxe este estado até aqui.
    $sync.WinForgeWUInstallCallback = {
        try {
            $wfEstado = Set-WinForgeWindowsUpdateInstallResult -UpdateId ([string]$sync.LastWUInstallId) -ResultCode ([int]$sync.LastWUInstallCode) -RebootRequired ([bool]$sync.LastWUInstallReboot)
            # Remontar a tabela inteira é o refresco mais simples que existe aqui: as linhas são
            # pscustomobject, que não avisa a interface quando um campo muda, e trocar isso por uma
            # classe com INotifyPropertyChanged seria um Add-Type inteiro para pintar uma linha.
            Update-WinForgeDiagnosticsWindowsUpdateGrid
            Write-WinForgeLog -Component "Diag" -Message "Windows Update: '$($sync.LastWUInstallId)' -> $($wfEstado.State) ($($wfEstado.Text))."
            if ($sync.LastWUInstallReboot) {
                [System.Windows.MessageBox]::Show($sync.Form, [string]$sync.LastWUInstallText + "`r`n`r`nÉ preciso reiniciar o computador para concluir.", "WinForge", "OK", "Information") | Out-Null
            }
        } catch { }
    }

    # O estado entra ANTES do despacho, ainda na thread da janela: é o que apaga o botão e escreve
    # "instalando..." na linha no mesmo instante do clique. Sem isto, a única resposta ao clique
    # seria a barra lá embaixo, e o usuário clicaria de novo.
    $null = Set-WinForgeWindowsUpdateRowState -UpdateId $id -State 'instalando' -Text 'instalando...'
    Update-WinForgeDiagnosticsWindowsUpdateGrid

    $sync.CommandRunning = $true
    $corpo = {
        param($wfArgs)
        $sync.LastWUInstallId = [string]$wfArgs.UpdateId
        $sync.LastWUInstallCode = -1
        $sync.LastWUInstallReboot = $false
        try {
            $null = Set-WinForgeDiagProgress -Label "Instalando '$($wfArgs.Title)' pelo Windows Update..." -Percent 10
            $wfRes = Install-WinForgeWindowsUpdateDriver -UpdateId $wfArgs.UpdateId
            $sync.LastWUInstallCode = [int]$wfRes.ResultCode
            $sync.LastWUInstallReboot = [bool]$wfRes.RebootRequired
            $sync.LastWUInstallText = [string]$wfRes.Text
            $null = Set-WinForgeDiagProgress -Label ([string]$wfRes.Text) -Percent $(if ([int]$wfRes.ResultCode -in @(2, 3)) { 100 } else { 0 })
        } catch {
            $sync.LastWUInstallText = "Instalação pelo Windows Update falhou: $($_.Exception.Message)"
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $sync.LastWUInstallText
            $null = Set-WinForgeDiagProgress -Label ([string]$sync.LastWUInstallText) -Percent 0
        } finally {
            $sync.CommandRunning = $false
            # Janela fechando: o Dispatcher já está desligando e Invoke-WPFUIThread ficaria parado
            # esperando por ele. A linha não tem mais para quem ser pintada.
            if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeWUInstallCallback }
        }
    }
    try {
        Invoke-WPFRunspace -ScriptBlock $corpo -ArgumentList @{ UpdateId = $id; Title = $titulo } | Out-Null
    } catch {
        # Despacho que falha nunca roda o corpo nem o callback: a linha ficaria "instalando..." para
        # sempre, com o botão apagado e nada acontecendo.
        $sync.CommandRunning = $false
        $null = Set-WinForgeWindowsUpdateRowState -UpdateId $id -State 'pendente' -Text ''
        Update-WinForgeDiagnosticsWindowsUpdateGrid
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Instalação pelo Windows Update não pôde começar: $($_.Exception.Message)"
        $null = Set-WinForgeDiagProgress -Label "Instalação pelo Windows Update não pôde começar: $($_.Exception.Message)" -Percent 0
    }
    return 'windows-update'
}

function Get-WinForgeWindowsUpdateGroupState {
    <#
    .SYNOPSIS
        O estado da linha de grupo, DERIVADO do estado de cada membro.
    .DESCRIPTION
        Derivado a cada remontagem, NUNCA armazenado. Guardar um estado próprio do grupo criaria uma
        segunda verdade sobre a mesma coisa, e as duas discordariam no primeiro membro que falhasse
        ou no primeiro clique numa linha solta. A única verdade é $sync.DiagWUState, por id.

        O texto conta o que aconteceu com os membros, e é ele que sobrevive a uma captura de tela em
        cinza - a cor da linha sozinha não serve a quem não a distingue. O '(reinicie)' sobe de
        qualquer membro: um reinício pendente vale para a máquina inteira, não para a linha.

        O botão fica clicável enquanto sobrar membro para instalar e nada estiver em andamento -
        falha INCLUÍDA, porque é justamente a hora de tentar de novo.
    .OUTPUTS
        @{ State = 'pendente'|'instalando'|'instalado'|'falhou'; StatusText; ActionLabel; ActionEnabled }
    #>
    param([string[]]$Members)

    $ids = @(@($Members) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $total = $ids.Count
    if ($total -eq 0) { return @{ State = 'pendente'; StatusText = ''; ActionLabel = 'Instalar todos (0)'; ActionEnabled = $false } }

    $instalados = 0; $instalando = 0; $falharam = 0; $reinicio = $false
    foreach ($id in $ids) {
        $estado = Get-WinForgeWindowsUpdateRowState -UpdateId ([string]$id)
        switch ([string]$estado.State) {
            'instalado'  { $instalados++; if ([string]$estado.Text -match '\(reinicie\)') { $reinicio = $true } }
            'instalando' { $instalando++ }
            'falhou'     { $falharam++ }
        }
    }
    $pendentes = $total - $instalados - $instalando - $falharam
    $faltam    = $total - $instalados

    $texto = ''
    $situacao = 'pendente'
    if ($instalando -gt 0) {
        $situacao = 'instalando'
        $texto = "instalando $instalando de $total..."
    } elseif ($instalados -eq $total) {
        $situacao = 'instalado'
        $texto = "$total de $total instalados" + $(if ($reinicio) { ' (reinicie)' } else { '' })
    } elseif ($instalados -eq 0 -and $falharam -eq 0) {
        # Nada aconteceu ainda: a coluna "Situação" fica em branco, como na linha solta recém-buscada.
        $texto = ''
    } else {
        # O lote parou no meio - por falha, por cancelamento ou pelos dois. As três parcelas somam o
        # total, e é assim que a pessoa sabe o que ainda tem para fazer.
        $partes = @("$instalados de $total instalados")
        if ($falharam -gt 0)  { $partes += $(if ($falharam -eq 1)  { '1 falhou' }   else { "$falharam falharam" }) }
        if ($pendentes -gt 0) { $partes += $(if ($pendentes -eq 1) { '1 pendente' } else { "$pendentes pendentes" }) }
        $texto = ($partes -join ', ')
        if ($falharam -gt 0 -and $pendentes -eq 0) { $situacao = 'falhou' }
    }

    $rotulo = $(if ($instalados -eq 0 -and $falharam -eq 0) { "Instalar todos ($total)" }
                elseif ($faltam -gt 0) { "Instalar os $faltam que faltam" }
                else { "Instalar todos ($total)" })
    return @{
        State         = $situacao
        StatusText    = $texto
        ActionLabel   = $rotulo
        ActionEnabled = ($instalando -eq 0 -and $faltam -gt 0)
    }
}

function Format-WinForgeWindowsUpdateGroupRow {
    <#
    .SYNOPSIS
        A linha da tabela que representa um lote de INF sem versão.
    .DESCRIPTION
        As colunas mostram texto já formatado, e por isso o GRUPO CRU viaja inteiro no campo Group:
        o filtro de chipset precisa de Class, Provider, HardwareIds e ProblemCodes como vieram, e
        'Date' aqui já pode ter virado a frase 'sem data confiável'.

        O rótulo nasce de Provider e do tamanho do lote, e NÃO diz "chipset": o critério que junta
        estas linhas (fornecedor, classe e data) é mais frouxo do que o que permitiria afirmar de
        que peça elas são. Dizer "chipset" aqui seria afirmar o que este agrupamento não apurou.

        Data anterior a 1990 vira 'sem data confiável': é carimbo de fábrica de INF, não data de
        publicação, e mostrá-la faria a coluna ordenar o lote como se fosse o driver mais velho da
        máquina. O mesmo vale para data ausente ou ilegível.
    .OUTPUTS
        A linha, com o grupo original em .Group.
    #>
    param($Group)

    if ($null -eq $Group) { return $null }
    $membros = @(@($Group.Members) | ForEach-Object { [string]$_ })
    $quantos = $membros.Count
    $estado  = Get-WinForgeWindowsUpdateGroupState -Members $membros

    # 1990: antes disso não existia driver para este Windows. A data que vem nesses INF é carimbo de
    # fábrica (1968, 1970), e o que ela informaria seria falso.
    $anoMinimo = 1990
    $data = [string]$Group.Date
    # TIPADA antes do [ref]: com $null o PowerShell 5.1 não acha a sobrecarga de cinco argumentos de
    # TryParseExact e a linha inteira estoura - medido, e o estouro derrubava a tabela.
    [datetime]$quando = [datetime]::MinValue
    if ([string]::IsNullOrWhiteSpace($data) -or
        -not [datetime]::TryParseExact($data, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$quando) -or
        $quando.Year -lt $anoMinimo) {
        $data = 'sem data confiável'
    }

    return [pscustomobject]@{
        Title    = "$([string]$Group.Provider) — $quantos itens que só dão nome a componentes da placa-mãe"
        Driver   = "$quantos dispositivos"
        Provider = [string]$Group.Provider
        Version  = 'sem número de versão'
        Date     = $data
        UpdateId = (Get-WinForgeWindowsUpdateGroupId -Key ([string]$Group.Key))
        IsGroup  = $true
        Members  = $membros
        MemberTitles = @(@($Group.MemberTitles) | ForEach-Object { [string]$_ })
        State         = [string]$estado.State
        StatusText    = [string]$estado.StatusText
        ActionLabel   = [string]$estado.ActionLabel
        ActionEnabled = [bool]$estado.ActionEnabled
        ActionTip     = "Baixa e instala os $quantos itens desta linha pelo Windows Update, um de cada vez."
        DetailsVisible = 'Visible'
        Group         = $Group
    }
}

function Show-WinForgeWindowsUpdateGroupList {
    <#
    .SYNOPSIS
        O que o botão "Ver lista" da linha de grupo mostra: os títulos de todos os membros.
    .DESCRIPTION
        Na janela de saída, e não numa célula que se abre. Gabarito próprio de célula
        (RowDetailsTemplate, Expander) quebra a rolagem da aba - medido no Plano 9, Tarefa 4: com
        gabarito próprio a roda repassada à aba deixa de mover o ScrollViewer. A janela de saída já
        existe, já rola, já tem "Copiar" e já sabe fechar.
    .PARAMETER NoShow
        Monta a janela sem mostrar. É a porta do -SelfTest.
    .OUTPUTS
        A janela montada.
    #>
    param($Row, [switch]$NoShow)

    if ($null -eq $Row) { return $null }
    $titulos = @(@($Row.MemberTitles) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($titulos.Count -eq 0) { $titulos = @('Esta linha não trouxe a lista de títulos.') }
    return (Show-WinForgeOutputWindow -Title ([string]$Row.Title) -Text ($titulos -join "`r`n") -Component 'Diag' -NoShow:$NoShow)
}

function Invoke-WinForgeWindowsUpdateGroupAction {
    <#
    .SYNOPSIS
        O que o botão "Instalar todos" da linha de grupo faz.
    .DESCRIPTION
        UM despacho para a pilha de runspaces, com o laço DENTRO dele. Um trabalho por membro
        disputaria $sync.CommandRunning consigo mesmo: o segundo veria a trava do primeiro e seria
        recusado, e o lote pararia no item 2 de 47.

        Cada membro dá um tique pelo caminho que já existe ($sync.LastWUInstall* mais
        Invoke-WPFUIThread), e os dois blocos que a thread da janela executa nascem AQUI, na runspace
        principal: bloco criado dentro da runspace do pool e invocado pelo Dispatcher trava a janela
        no primeiro pipeline.

        Falha de um membro não interrompe o lote - o que falhou fica vermelho na linha dele e o resto
        continua. Entre um membro e outro, duas saídas: a janela fechando e o pedido de parada.

        UMA caixa de reinício, no fim. Uma por membro seriam dezenas de caixas para dizer a mesma
        coisa, e é justamente o incômodo que este agrupamento existe para acabar.

        Os membros que não chegaram a ser instalados voltam a PENDENTE no fim. Sem isso, parar no
        meio deixaria as linhas restantes em "instalando..." para sempre, com o botão apagado.
    .PARAMETER NoUI
        Diz o que faria, sem caixa, sem rede e sem instalar nada. É a porta do -SelfTest.
    .OUTPUTS
        Texto curto com o que foi feito.
    #>
    param($Row, [switch]$NoUI)

    if ($null -eq $Row) { return 'none' }
    $membros = @(@($Row.Members) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($membros.Count -eq 0) { return 'none' }

    $estado = Get-WinForgeWindowsUpdateGroupState -Members $membros
    if ([string]$estado.State -eq 'instalando') {
        Write-WinForgeLog -Component "Diag" -Message "Instalação do lote '$($Row.Title)' recusada: já está em andamento."
        return 'instalando'
    }
    # Só o que FALTA. O segundo clique não reinstala o que já entrou: são minutos de máquina ocupada
    # para nada, e o Windows Update pede reinício de novo por cada um deles.
    $faltam = @($membros | Where-Object { [string](Get-WinForgeWindowsUpdateRowState -UpdateId ([string]$_)).State -ne 'instalado' })
    if ($faltam.Count -eq 0) {
        Write-WinForgeLog -Component "Diag" -Message "Instalação do lote '$($Row.Title)' recusada: os $($membros.Count) itens já foram instalados nesta sessão."
        return 'já instalado'
    }
    if ($NoUI) { return "instalaria $($faltam.Count) de $($membros.Count)" }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeWindowsUpdateGroupAction'

    if ($sync.CommandRunning -or $sync.ProcessRunning) {
        [System.Windows.MessageBox]::Show("Já existe um trabalho em andamento. Espere ele terminar.", "WinForge", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return 'ocupado'
    }
    $pergunta = "Instalar os $($faltam.Count) itens desta linha pelo Windows Update, um de cada vez?" + "`r`n`r`n" +
                "Eles não trazem driver novo: são arquivos que só dão nome a componentes da placa-mãe no Gerenciador de Dispositivos. Pode levar vários minutos."
    $resposta = [System.Windows.MessageBox]::Show($sync.Form, $pergunta, "WinForge", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($resposta -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-WinForgeLog -Component "Diag" -Message "Instalação do lote '$($Row.Title)' cancelada pelo usuário."
        return 'cancelado'
    }

    # O estado entra ANTES do despacho, na thread da janela: é o que apaga o botão e escreve
    # "instalando..." nas linhas no mesmo instante do clique.
    foreach ($wfMembro in $faltam) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId ([string]$wfMembro) -State 'instalando' -Text 'instalando...' }
    $sync.WUGroupMembers = @($faltam | ForEach-Object { [string]$_ })
    $sync.WUGroupCancel = $false
    $sync.WUGroupReboot = $false
    Update-WinForgeDiagnosticsWindowsUpdateGrid

    $sync.WinForgeWUGroupTickCallback = {
        try {
            $null = Set-WinForgeWindowsUpdateInstallResult -UpdateId ([string]$sync.LastWUInstallId) -ResultCode ([int]$sync.LastWUInstallCode) -RebootRequired ([bool]$sync.LastWUInstallReboot)
            Update-WinForgeDiagnosticsWindowsUpdateGrid
        } catch { }
    }

    $sync.CommandRunning = $true
    $corpo = {
        param($wfArgs)
        $wfIds = @($wfArgs.Ids)
        $wfTotal = $wfIds.Count
        $wfFeitos = 0
        try {
            foreach ($wfId in $wfIds) {
                if ($sync.WinForgeClosing -or $sync.WUGroupCancel) { break }
                $wfFeitos++
                $sync.LastWUInstallId = [string]$wfId
                $sync.LastWUInstallCode = -1
                $sync.LastWUInstallReboot = $false
                try {
                    $null = Set-WinForgeDiagProgress -Label "Instalando $wfFeitos de $wfTotal pelo Windows Update..." -Percent ([int](100 * $wfFeitos / $wfTotal))
                    $wfRes = Install-WinForgeWindowsUpdateDriver -UpdateId ([string]$wfId)
                    $sync.LastWUInstallCode = [int]$wfRes.ResultCode
                    $sync.LastWUInstallReboot = [bool]$wfRes.RebootRequired
                    $sync.LastWUInstallText = [string]$wfRes.Text
                } catch {
                    $sync.LastWUInstallText = "Instalação pelo Windows Update falhou: $($_.Exception.Message)"
                    Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $sync.LastWUInstallText
                }
                if ([bool]$sync.LastWUInstallReboot) { $sync.WUGroupReboot = $true }
                if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeWUGroupTickCallback }
            }
        } finally {
            $sync.CommandRunning = $false
            $null = Set-WinForgeDiagProgress -Label "Windows Update: $wfFeitos de $wfTotal item(ns) do lote processado(s)." -Percent 100
            if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeWUGroupDoneCallback }
        }
    }

    $sync.WinForgeWUGroupDoneCallback = {
        try {
            foreach ($wfPendente in @($sync.WUGroupMembers)) {
                if ([string](Get-WinForgeWindowsUpdateRowState -UpdateId ([string]$wfPendente)).State -eq 'instalando') {
                    $null = Set-WinForgeWindowsUpdateRowState -UpdateId ([string]$wfPendente) -State 'pendente' -Text ''
                }
            }
            Update-WinForgeDiagnosticsWindowsUpdateGrid
            if ($sync.WUGroupReboot) {
                [System.Windows.MessageBox]::Show($sync.Form, "Alguns itens só terminam de se instalar depois de reiniciar o computador.", "WinForge", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
        } catch { }
    }

    try {
        Invoke-WPFRunspace -ScriptBlock $corpo -ArgumentList @{ Ids = @($faltam | ForEach-Object { [string]$_ }) } | Out-Null
    } catch {
        # Despacho que falha nunca roda o corpo nem os blocos da janela: as linhas ficariam
        # "instalando..." para sempre, com o botão apagado e nada acontecendo.
        $sync.CommandRunning = $false
        foreach ($wfMembro in $faltam) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId ([string]$wfMembro) -State 'pendente' -Text '' }
        Update-WinForgeDiagnosticsWindowsUpdateGrid
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Instalação do lote pelo Windows Update não pôde começar: $($_.Exception.Message)"
        $null = Set-WinForgeDiagProgress -Label "Instalação do lote pelo Windows Update não pôde começar: $($_.Exception.Message)" -Percent 0
    }
    return 'windows-update-grupo'
}

function New-WinForgeDiagLineBlock {
    <#
    .SYNOPSIS
        TextBlock de uma linha do cartão: chave em negrito, valor normal.
    #>
    param([string]$Key, [string]$Value)

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'
    $tb.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSize")
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MainForegroundColor")

    $keyRun = New-Object System.Windows.Documents.Run("${Key}: ")
    $keyRun.FontWeight = [System.Windows.FontWeights]::Bold
    $tb.Inlines.Add($keyRun)
    $tb.Inlines.Add((New-Object System.Windows.Documents.Run([string]$Value)))
    return $tb
}

function New-WinForgeDiagCard {
    <#
    .SYNOPSIS
        Cartão (Border no estilo da janela) com o título da seção e uma linha por campo.
    #>
    param([Parameter(Mandatory)]$Section)

    $border = New-Object System.Windows.Controls.Border
    $border.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, "BorderStyle")
    $border.Width = 360
    $border.VerticalAlignment = 'Top'

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Orientation = 'Vertical'

    $header = New-Object System.Windows.Controls.TextBlock
    $header.Text = [string]$Section.Title
    $header.TextWrapping = 'Wrap'
    $header.FontWeight = [System.Windows.FontWeights]::Bold
    $header.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
    $header.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "HeaderFontSize")
    $header.SetResourceReference([System.Windows.Controls.TextBlock]::FontFamilyProperty, "HeaderFontFamily")
    $header.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "LabelboxForegroundColor")
    $stack.Children.Add($header) | Out-Null

    foreach ($line in @($Section.Lines)) {
        $stack.Children.Add((New-WinForgeDiagLineBlock -Key ([string]$line.Key) -Value ([string]$line.Value))) | Out-Null
    }

    $border.Child = $stack
    return $border
}

function Update-WinForgeDiagnosticsTab {
    <#
    .SYNOPSIS
        Redesenha a aba Diagnóstico a partir de $sync.Profile, $sync.Recommended, $sync.Discouraged
        e $sync.RuleInfos.
    .DESCRIPTION
        Tem de rodar na thread da interface (quem chama de dentro do job usa Invoke-WPFUIThread) e,
        por causa dos pipelines daqui, num scriptblock da runspace principal - veja o comentário em
        Start-WinForgeProfileJob.
        Rodar com a aba fechada é normal e seguro: os controles nascem com o XAML, não com a montagem
        da aba, e o diagnóstico costuma terminar com a janela ainda na aba Instalar. Quem abre a aba
        depois cai em Initialize-WinForgeDiagnosticsTab, que liga os hyperlinks e redesenha.
    #>
    # Todos os controles da aba nascem com o XAML, muito antes de a aba ser aberta: a guarda pega a
    # janela que ainda não carregou (e o -SelfTest antes de $sync.Form existir), não a aba fechada.
    if ($null -eq $sync) { return }
    foreach ($wfCtl in @('WPFDiagCards', 'WPFDiagRecs', 'WPFDiagRecCount', 'WPFDiagInfos', 'WPFDiagDrivers', 'WPFDiagStatus')) {
        if ($null -eq $sync[$wfCtl]) { return }
    }

    $p = $sync.Profile
    if ($null -eq $p) {
        $sync.WPFDiagStatus.Text = "Coletando informações do sistema..."
        return
    }

    # ---- cartões
    $sync.WPFDiagCards.Children.Clear()
    foreach ($section in (Get-WinForgeDiagSections -Profile $p)) {
        $sync.WPFDiagCards.Children.Add((New-WinForgeDiagCard -Section $section)) | Out-Null
    }

    # ---- recomendações (checklist espelhado nas abas Ajustes/Jogos/Servidor)
    # O mapa de espelhos é refeito junto com a lista: as caixas antigas foram descartadas com os
    # Items, e um mapa velho faria o caminho de volta escrever em controle que saiu da tela.
    $sync.WPFDiagRecs.Items.Clear()
    $sync.WinForgeDiagMirrors = @{}
    $recItems = @(Get-WinForgeDiagRecommendationItems)
    foreach ($item in $recItems) {
        $sync.WPFDiagRecs.Items.Add((New-WinForgeDiagRecRow -Item $item)) | Out-Null
    }
    # A lista nasce desmarcada, mas a aba de destino pode já ter caixas marcadas (preset, importação,
    # o próprio usuário): sem esta passada o checklist abriria mentindo. Marcar a linha dispara
    # Set-WinForgeRecommendationMirror, que encontra a caixa de verdade já marcada e não faz nada.
    foreach ($key in @($sync.WinForgeDiagMirrors.Keys)) {
        $control = $sync[$key]
        if ($control -isnot [System.Windows.Controls.CheckBox] -or -not $control.IsChecked) { continue }
        $sync.WinForgeDiagMirrors[$key].IsChecked = $true
    }
    Update-WinForgeDiagRecommendationCount

    # ---- informações das regras + falhas de coleta
    $infos = [System.Collections.Generic.List[string]]::new()
    foreach ($i in @($sync.RuleInfos)) { if ($i) { $infos.Add("• $i") } }
    foreach ($e in @($p.Errors)) { if ($e) { $infos.Add("• Falha ao coletar -> $e") } }
    if ($infos.Count -gt 0) {
        $sync.WPFDiagInfos.Text = ($infos -join [Environment]::NewLine)
        $sync.WPFDiagInfos.Visibility = 'Visible'
    } else {
        $sync.WPFDiagInfos.Text = ''
        $sync.WPFDiagInfos.Visibility = 'Collapsed'
    }

    # ---- drivers
    $sync.WPFDiagDrivers.ItemsSource = (Get-WinForgeDiagDriverRows -Profile $p)

    # $sync.Recommended pode ser $null (nenhum diagnóstico rodou ainda): @($null.Keys) tem um item,
    # não zero - daí as guardas, senão a linha de resumo mentiria "1 recomendação".
    $nRec = $(if ($sync.Recommended) { @($sync.Recommended.Keys).Count } else { 0 })
    $nEvi = $(if ($sync.Discouraged) { @($sync.Discouraged.Keys).Count } else { 0 })
    $pendentes = @(@($p.Drivers) | Where-Object { $_ -and $_.Status -ne 'ok' }).Count
    $sync.WPFDiagStatus.Text = "Diagnóstico de {0} | {1} recomendação(ões), {2} a evitar | {3} driver(s), {4} para conferir | {5} falha(s) de coleta" -f `
        (Format-WinForgeDiagValue $p.GeneratedAt), $nRec, $nEvi, @($p.Drivers).Count, $pendentes, @($p.Errors).Count

    Write-WinForgeLog -Component "Diag" -Message "Aba Diagnóstico atualizada: $($sync.WPFDiagCards.Children.Count) cartões, $(@($p.Drivers).Count) drivers, $($recItems.Count) recomendações."
}

function Update-WinForgeDiagnosticsWindowsUpdateGrid {
    <#
    .SYNOPSIS
        Preenche a tabela dos drivers oferecidos pelo Windows Update ($sync.DiagWUResults).
    .DESCRIPTION
        Roda na thread da interface. A tabela e o título só aparecem depois da primeira busca - antes
        disso não há nada a dizer, e uma tabela vazia parada na aba sugeriria que a busca já rodou.
    #>
    if ($null -eq $sync -or $null -eq $sync.WPFDiagWU) { return }

    # Instalar pelo Windows Update é o serviço COM baixando e instalando driver: sem elevação ele
    # recusa. Mesma regra do botão de download da NVIDIA - o botão nasce desabilitado dizendo isso.
    $elevado = [bool](Test-WinForgeRepairElevated)
    # Uma linha por dispositivo. A filtragem é da VISTA: $sync.DiagWUResults e o mapa de objetos COM
    # continuam inteiros, e é por isso que ela mora aqui e não na busca.
    $selecao = Select-WinForgeWindowsUpdateLatest -Rows @($sync.DiagWUResults)
    $ocultos = @($selecao.Superseded)
    # Os lotes de INF sem versão viram UMA linha. Também é filtragem de VISTA, pelo mesmo motivo da
    # linha acima, e por isso vem depois dela: o agrupamento trabalha sobre o que a tabela mostraria.
    $agrupado = Group-WinForgeWindowsUpdateNullDrivers -Rows @($selecao.Kept)
    # Publicado a CADA remontagem, inclusive quando é zero. Publicando só quando há lote, o relatório
    # HTML - que só repete este número - passaria a citar a contagem da busca anterior, que é o pior
    # tipo de erro numa tela de diagnóstico: um número certo para uma máquina que não é mais esta.
    $sync.DiagWUGrouped = [int](@(@($agrupado.Groups) | ForEach-Object { @($_.Members).Count }) | Measure-Object -Sum).Sum
    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($u in @($agrupado.Rows)) {
        if ($null -eq $u) { continue }
        if ([bool]$u.IsGroup) {
            $linhaGrupo = Format-WinForgeWindowsUpdateGroupRow -Group $u.Group
            # A elevação manda no botão do lote pela mesma regra da linha solta - o estado derivado
            # não sabe nada de elevação, e é a tabela que sabe.
            $linhaGrupo.ActionEnabled = ([bool]$linhaGrupo.ActionEnabled -and $elevado)
            if (-not $elevado) { $linhaGrupo.ActionTip = $WinForgeElevationTip }
            $rows.Add($linhaGrupo)
            continue
        }
        # O estado da sessão é reaplicado a CADA remontagem: a tabela é refeita inteira depois de
        # cada instalação (é assim que a linha muda de cor), e sem isto ela voltaria a dizer
        # "pendente" justamente na linha que acabou de ser instalada.
        $wuId = [string]$u.UpdateId
        $estado = Get-WinForgeWindowsUpdateRowState -UpdateId $wuId
        $emAndamento = ([string]$estado.State -in @('instalando', 'instalado'))
        $rows.Add([pscustomobject]@{
            Title    = [string]$u.Title
            Driver   = (Format-WinForgeDiagValue $u.Driver)
            Provider = (Format-WinForgeDiagValue $u.Provider)
            Version  = (Format-WinForgeDiagValue $u.Version)
            Date     = (Format-WinForgeDiagValue $u.Date)
            # O id, e não o título, é o que identifica a atualização na hora de instalar: dois
            # drivers do mesmo dispositivo saem com títulos parecidos e ids diferentes.
            UpdateId = $wuId
            # State pinta a linha (gatilho do estilo WFWindowsUpdateRow); StatusText é a mesma
            # informação em palavras, na coluna "Situação".
            State      = [string]$estado.State
            StatusText = [string]$estado.Text
            # Falhou continua clicável: é a hora de tentar de novo. Instalado e instalando, não.
            ActionEnabled = ($elevado -and -not $emAndamento)
            ActionTip     = $(if (-not $elevado) { $WinForgeElevationTip }
                              elseif ([string]$estado.State -eq 'instalado') { 'Este driver já foi instalado nesta sessão.' }
                              elseif ([string]$estado.State -eq 'instalando') { 'Instalação em andamento.' }
                              else { 'Baixa e instala este driver pelo Windows Update.' })
            # Os quatro campos que a linha de grupo usa, escritos também aqui: uma coluna ligada a um
            # campo que só metade das linhas tem produz erro de ligação em silêncio a cada remontagem,
            # e o botão "Ver lista" apareceria na linha solta se DetailsVisible viesse vazio.
            IsGroup        = $false
            ActionLabel    = 'Instalar'
            DetailsVisible = 'Collapsed'
            Group          = $null
        })
    }

    $sync.WPFDiagWU.ItemsSource = $rows
    $sync.WPFDiagWU.Visibility = 'Visible'
    $sync.WPFDiagWULabel.Visibility = 'Visible'
    # A dica é redefinida nos DOIS caminhos: sem o $null, a lista de títulos de uma busca anterior
    # ficaria pendurada num rótulo que não esconde mais nada.
    $sync.WPFDiagWULabel.ToolTip = $null
    $sync.WPFDiagWULabel.Text = if ($rows.Count -gt 0) {
        $texto = "Drivers oferecidos pelo Windows Update ($($rows.Count))"
        if ($ocultos.Count -gt 0) {
            $texto += " · $($ocultos.Count) versão(ões) mais antiga(s) oculta(s)"
            $sync.WPFDiagWULabel.ToolTip = ((@($ocultos | ForEach-Object { "• $($_.Title)" })) -join [Environment]::NewLine)
        }
        # O que foi reunido é dito no rótulo pelo mesmo motivo das versões ocultas: linha que some da
        # tabela sem explicação é um mistério, e aqui somem dezenas de uma vez.
        if ([int]$sync.DiagWUGrouped -gt 0) { $texto += " · $([int]$sync.DiagWUGrouped) item(ns) reunido(s) em linha(s) de grupo" }
        $texto
    } elseif ($sync.LastWUError) {
        "Windows Update: a consulta falhou -> $($sync.LastWUError)"
    } else {
        "Windows Update: nenhum driver pendente para este computador"
    }
}

function Invoke-WinForgeDriverUpdateSearch {
    <#
    .SYNOPSIS
        Pergunta ao Windows Update quais drivers ele tem para este computador, fora da thread da
        interface.
    .DESCRIPTION
        A consulta COM fala com os servidores da Microsoft e pode levar de 10 a 60 segundos: na thread
        da janela ela congelaria tudo. Uma busca por vez; a barra de progresso só é usada quando nenhum
        outro trabalho está nela (o texto do que o usuário mandou fazer vale mais que o desta consulta).
    #>
    if ($sync.DiagWUSearchRunning) {
        Write-WinForgeLog -Component "Diag" -Message "Busca de drivers no Windows Update já em andamento; pedido ignorado."
        return
    }
    $sync.DiagWUSearchRunning = $true
    $sync.LastWUError = $null
    if (-not $sync.ProcessRunning) {
        Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Consultando o Windows Update (pode levar até um minuto)..." -Percent 0
    }
    Write-WinForgeLog -Component "Diag" -Message "Busca de drivers no Windows Update iniciada."

    # Criado aqui, na runspace principal (esta função roda no clique do botão): um scriptblock feito
    # dentro do corpo do job pertenceria à runspace do pool e travaria no primeiro pipeline quando o
    # Dispatcher o executasse - o mesmo laço descrito em Start-WinForgeProfileJob.
    $sync.WinForgeWUUiRefresh = {
        try {
            Update-WinForgeDiagnosticsWindowsUpdateGrid
        } catch {
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Windows Update: falha ao atualizar a tabela -> $($_.Exception.Message)"
        }
    }

    # A consulta COM não é interrompível: quando a janela fecha no meio dela, o processo já está
    # indo embora e nada mais aqui pode tocar a interface - escrever na barra ou pedir o Dispatcher
    # seria esperar por uma thread que está desligando.
    $wfBody = {
        try {
            $sync.DiagWUResults = @(Search-WinForgeWindowsUpdateDrivers)
            if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeWUUiRefresh }
            $wfMsg = if ($sync.LastWUError) {
                "Windows Update: a consulta falhou -> $($sync.LastWUError)"
            } else {
                "Windows Update: $(@($sync.DiagWUResults).Count) driver(s) disponível(is) para este computador."
            }
            if (-not $sync.ProcessRunning -and -not $sync.WinForgeClosing) {
                Set-WinForgeTweaksProgressIndicator -Visible $true -Label $wfMsg -Percent 100
            }
            Write-WinForgeLog -Component "Diag" -Message $wfMsg
        } catch {
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Busca no Windows Update falhou: $($_.Exception.Message)"
            if (-not $sync.ProcessRunning -and -not $sync.WinForgeClosing) {
                Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Busca no Windows Update falhou: $($_.Exception.Message)" -Percent 0
            }
        } finally {
            $sync.DiagWUSearchRunning = $false
        }
    }

    # Se o despacho falhar (pool fechado, sem thread livre), quem zera a trava é este catch: sem ele
    # $sync.DiagWUSearchRunning ficaria ligado para sempre e o botão nunca mais responderia.
    try {
        Invoke-WPFRunspace -ScriptBlock $wfBody | Out-Null
    } catch {
        $sync.DiagWUSearchRunning = $false
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Busca no Windows Update não pôde começar: $($_.Exception.Message)"
        if (-not $sync.ProcessRunning) {
            Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Busca no Windows Update não pôde começar: $($_.Exception.Message)" -Percent 0
        }
    }
}

function Initialize-WinForgeDiagnosticsTab {
    <#
    .SYNOPSIS
        Monta a aba Diagnóstico (chamada por Initialize-WinForgeTabContent na primeira vez que a aba
        é aberta).
    .DESCRIPTION
        Os botões DO XAML já são ligados a Invoke-WPFButton pelo laço geral da janela; o que falta
        aqui são dois eventos roteados: o clique nos botões das colunas "Ação" e "Instalar" e a roda
        do mouse sobre as tabelas.

        Os botões das duas colunas nascem e morrem com as linhas, então não dá para ligar um handler
        em cada um: quem escuta é a TABELA, uma vez só, no evento Click que sobe de qualquer botão
        de dentro dela. Quem clicou é lido de $e.OriginalSource, e a linha vem na Tag do botão.

        Todos os handlers são registrados uma única vez - a aba pode ser redesenhada muitas vezes, e
        um handler por redesenho baixaria o mesmo driver várias vezes no mesmo clique e rolaria a
        página várias vezes por giro da roda.
    #>
    if ($null -eq $sync -or $null -eq $sync.WPFDiagDrivers) { return }

    # Roda do mouse sobre as tabelas. O DataGrid tem ScrollViewer próprio e marca o evento como
    # tratado mesmo com as barras desligadas: o giro morria ali e a aba inteira ficava parada.
    # PreviewMouseWheel chega antes desse ScrollViewer interno; daqui o evento é repassado ao
    # ScrollViewer da aba, que é quem tem o que rolar.
    if (-not $sync.WinForgeDiagWheelHooked -and $sync.WPFDiagScroll) {
        foreach ($wfGrade in @($sync.WPFDiagDrivers, $sync.WPFDiagWU)) {
            if ($null -eq $wfGrade) { continue }
            $wfGrade.Add_PreviewMouseWheel({
                param($eventSender, $eventArgs)
                $eventArgs.Handled = $true
                $wfRoda = New-Object System.Windows.Input.MouseWheelEventArgs($eventArgs.MouseDevice, $eventArgs.Timestamp, $eventArgs.Delta)
                $wfRoda.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
                $wfRoda.Source = $eventSender
                $sync.WPFDiagScroll.RaiseEvent($wfRoda)
            })
        }
        $sync.WinForgeDiagWheelHooked = $true
    }

    # Clique nos botões de linha. O resultado fica em $sync.LastDriverAction: é o que o -SelfTest lê
    # para provar que o clique chegou ao lugar certo, e é onde a recusa aparece quando a ação é
    # barrada (modo SelfTest, trabalho em andamento) - sem isso a exceção morreria calada dentro do
    # handler, que é o único lugar de onde ela não tem para onde subir.
    if (-not $sync.WinForgeDiagActionHandlerWired) {
        $sync.WPFDiagDrivers.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
            param($eventSender, $eventArgs)
            $wfBotao = $eventArgs.OriginalSource
            if ($wfBotao -isnot [System.Windows.Controls.Button] -or $null -eq $wfBotao.Tag) { return }
            $eventArgs.Handled = $true
            try { $sync.LastDriverAction = Invoke-WinForgeDriverAction -Row $wfBotao.Tag } catch {
                $sync.LastDriverAction = "erro: $($_.Exception.Message)"
                Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Ação de driver falhou: $($_.Exception.Message)"
            }
        })
        if ($null -ne $sync.WPFDiagWU) {
            $sync.WPFDiagWU.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
                param($eventSender, $eventArgs)
                $wfBotao = $eventArgs.OriginalSource
                if ($wfBotao -isnot [System.Windows.Controls.Button] -or $null -eq $wfBotao.Tag) { return }
                $eventArgs.Handled = $true
                # Três botões chegam por aqui, e o que os separa é o Uid do gabarito - não o texto do
                # Content, que na coluna "Instalar" muda com o estado da linha. Uid é propriedade do
                # elemento e sobrevive ao gabarito; Name, dentro de um DataTemplate, não chega ao
                # dicionário da janela.
                $wfLinha = $wfBotao.Tag
                try {
                    if ([string]$wfBotao.Uid -eq 'WFWUGroupDetails') {
                        $null = Show-WinForgeWindowsUpdateGroupList -Row $wfLinha
                        $sync.LastDriverAction = 'windows-update-lista'
                    } elseif ([bool]$wfLinha.IsGroup) {
                        $sync.LastDriverAction = Invoke-WinForgeWindowsUpdateGroupAction -Row $wfLinha
                    } else {
                        $sync.LastDriverAction = Invoke-WinForgeWindowsUpdateAction -Row $wfLinha
                    }
                } catch {
                    $sync.LastDriverAction = "erro: $($_.Exception.Message)"
                    Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Instalação pelo Windows Update falhou: $($_.Exception.Message)"
                }
            })
        }
        $sync.WinForgeDiagActionHandlerWired = $true
    }

    Update-WinForgeDiagnosticsTab
}

function ConvertTo-WinForgeDiagHtml {
    <#
    .SYNOPSIS
        Texto seguro para o relatório (escapa &, <, > e aspas).
    #>
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Export-WinForgeDiagnosticsReport {
    <#
    .SYNOPSIS
        Gera o relatório HTML do diagnóstico e o abre no navegador.
    .DESCRIPTION
        Arquivo único, sem nada externo (CSS embutido, tema escuro): pode ser enviado por e-mail ou
        aberto em outra máquina. Gravado em UTF-8 com BOM para que navegador e Bloco de Notas leiam
        os acentos sem depender da code page do sistema.
    .PARAMETER Path
        Caminho do arquivo. Sem parâmetro:
        %LocalAppData%\WinForge\reports\diagnostico-<aaaaMMdd-HHmmss>.html, com a base vinda da API
        de pastas (Get-WinForgeUserDataRoot) e não da variável de ambiente - o arquivo é gravado
        pelo motor elevado e aberto logo em seguida com Start-Process.
        Com os segundos no nome, dois relatórios seguidos não se sobrescrevem.
    .PARAMETER NoOpen
        Não abre o arquivo depois de gravar (usado pelo -SelfTest).
    .OUTPUTS
        Caminho do arquivo gerado, ou $null se o diagnóstico ainda não terminou.
    #>
    param([string]$Path, [switch]$NoOpen)

    $p = $sync.Profile
    if ($null -eq $p) {
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Relatório não gerado: o diagnóstico ainda não terminou."
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path (Get-WinForgeUserDataRoot) ("WinForge\reports\diagnostico-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $html = New-Object System.Text.StringBuilder
    [void]$html.AppendLine('<!DOCTYPE html>')
    [void]$html.AppendLine('<html lang="pt-br"><head><meta charset="utf-8">')
    [void]$html.AppendLine("<title>WinForge - diagnóstico de $(ConvertTo-WinForgeDiagHtml $env:COMPUTERNAME)</title>")
    [void]$html.AppendLine('<style>')
    [void]$html.AppendLine(@'
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; padding: 24px; background: #1b1e21; color: #e6e6e6;
       font-family: "Segoe UI", Tahoma, Arial, sans-serif; font-size: 14px; line-height: 1.5; }
h1 { font-size: 24px; margin: 0 0 4px 0; color: #ffffff; }
h2 { font-size: 18px; margin: 32px 0 12px 0; color: #ffffff;
     border-bottom: 1px solid #3a3f44; padding-bottom: 6px; }
.sub { color: #9aa0a6; margin: 0 0 8px 0; }
.cards { display: flex; flex-wrap: wrap; gap: 16px; }
.card { background: #232629; border: 1px solid #3a3f44; border-radius: 6px;
        padding: 14px 16px; min-width: 320px; flex: 1 1 320px; }
.card h3 { font-size: 15px; margin: 0 0 8px 0; color: #7ec8ff; }
.card div { margin: 2px 0; word-break: break-word; }
.card b { color: #cfd3d7; }
table { border-collapse: collapse; width: 100%; margin-top: 8px; }
th, td { border-bottom: 1px solid #3a3f44; padding: 6px 8px; text-align: left; vertical-align: top; }
th { color: #cfd3d7; background: #232629; font-weight: 600; }
tr:hover td { background: #232629; }
a { color: #7ec8ff; }
ul { margin: 8px 0; padding-left: 20px; }
li { margin: 3px 0; }
.ok { color: #7dc97d; }
.warn { color: #f9a825; }
.upd { color: #ef6c00; }
.rec { color: #7dc97d; }
.avoid { color: #ef8a3c; }
footer { margin-top: 40px; color: #7d8288; font-size: 12px;
         border-top: 1px solid #3a3f44; padding-top: 10px; }
'@)
    [void]$html.AppendLine('</style></head><body>')

    [void]$html.AppendLine("<h1>WinForge - relatório de diagnóstico</h1>")
    [void]$html.AppendLine("<p class=""sub"">Computador: $(ConvertTo-WinForgeDiagHtml $env:COMPUTERNAME) &middot; Coletado em: $(ConvertTo-WinForgeDiagHtml $p.GeneratedAt) &middot; WinForge $(ConvertTo-WinForgeDiagHtml $sync.version)</p>")

    # ---- cartões
    [void]$html.AppendLine('<h2>Sistema</h2>')
    [void]$html.AppendLine('<div class="cards">')
    foreach ($section in (Get-WinForgeDiagSections -Profile $p)) {
        [void]$html.AppendLine('<div class="card">')
        [void]$html.AppendLine("<h3>$(ConvertTo-WinForgeDiagHtml $section.Title)</h3>")
        foreach ($line in @($section.Lines)) {
            [void]$html.AppendLine("<div><b>$(ConvertTo-WinForgeDiagHtml $line.Key):</b> $(ConvertTo-WinForgeDiagHtml $line.Value)</div>")
        }
        [void]$html.AppendLine('</div>')
    }
    [void]$html.AppendLine('</div>')

    # ---- recomendações
    [void]$html.AppendLine('<h2>Recomendações para este computador</h2>')
    $recItems = @(Get-WinForgeDiagRecommendationItems)
    if ($recItems.Count -eq 0) {
        [void]$html.AppendLine('<p>Nenhuma recomendação específica para este sistema.</p>')
    } else {
        [void]$html.AppendLine('<ul>')
        foreach ($item in $recItems) {
            $cls = if ($item.Kind -eq 'recomendado') { 'rec' } else { 'avoid' }
            [void]$html.AppendLine("<li class=""$cls"">$(ConvertTo-WinForgeDiagHtml $item.Icon) <b>$(ConvertTo-WinForgeDiagHtml $item.Content)</b> &mdash; $(ConvertTo-WinForgeDiagHtml $item.Reason)</li>")
        }
        [void]$html.AppendLine('</ul>')
    }

    # ---- informações e falhas de coleta
    $infos = [System.Collections.Generic.List[string]]::new()
    foreach ($i in @($sync.RuleInfos)) { if ($i) { $infos.Add([string]$i) } }
    foreach ($e in @($p.Errors)) { if ($e) { $infos.Add("Falha ao coletar -> $e") } }
    if ($infos.Count -gt 0) {
        [void]$html.AppendLine('<h2>Observações</h2><ul>')
        foreach ($i in $infos) { [void]$html.AppendLine("<li>$(ConvertTo-WinForgeDiagHtml $i)</li>") }
        [void]$html.AppendLine('</ul>')
    }

    # ---- drivers
    [void]$html.AppendLine('<h2>Drivers instalados</h2>')
    [void]$html.AppendLine('<table><tr><th>Dispositivo</th><th>Classe</th><th>Versão</th><th>Data</th><th>Fornecedor</th><th>Status</th><th>Fabricante</th></tr>')
    foreach ($row in (Get-WinForgeDiagDriverRows -Profile $p)) {
        $cls = switch ($row.Status) { 'atualizar' { 'upd' } 'verificar' { 'warn' } default { 'ok' } }
        $link = if ($row.Url) { "<a href=""$(ConvertTo-WinForgeDiagHtml $row.Url)"">$(ConvertTo-WinForgeDiagHtml $row.UrlLabel)</a>" } else { '' }
        [void]$html.AppendLine("<tr><td>$(ConvertTo-WinForgeDiagHtml $row.Device)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Class)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Version)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Date)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Provider)</td><td class=""$cls"">$(ConvertTo-WinForgeDiagHtml $row.StatusText)</td><td>$link</td></tr>")
    }
    [void]$html.AppendLine('</table>')

    # ---- Windows Update (só se a busca já rodou nesta sessão)
    $wu = @($sync.DiagWUResults)
    if ($wu.Count -gt 0) {
        [void]$html.AppendLine('<h2>Drivers oferecidos pelo Windows Update</h2>')
        [void]$html.AppendLine('<table><tr><th>Atualização</th><th>Driver</th><th>Classe</th><th>Fornecedor</th><th>Versão</th><th>Data</th></tr>')
        foreach ($u in $wu) {
            if ($null -eq $u) { continue }
            [void]$html.AppendLine("<tr><td>$(ConvertTo-WinForgeDiagHtml $u.Title)</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Driver))</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Class))</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Provider))</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Version))</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Date))</td></tr>")
        }
        [void]$html.AppendLine('</table>')
        # A tabela acima é CRUA de propósito: uma linha por oferta, como o serviço respondeu, porque
        # o relatório é o que a pessoa manda para quem for ajudar - dobrar linha ali esconderia o
        # dado de quem está justamente procurando o que a tela não mostrou.
        # Quem dobra os lotes de INF sem versão é a ABA, e é ela que publica quantas ofertas dobrou
        # em $sync.DiagWUGrouped; aqui o número é só REPETIDO. Sem número não sai nota nenhuma: um
        # relatório gerado antes de a tabela ser montada não pode afirmar um agrupamento que não
        # aconteceu.
        $dobradas = 0
        try { $dobradas = [int]$sync.DiagWUGrouped } catch { $dobradas = 0 }
        if ($dobradas -gt 0) {
            [void]$html.AppendLine("<p class=""sub"">Lista crua: uma linha por oferta. A aba Diagnóstico mostra $dobradas dessas ofertas reunidas em linha(s) de grupo.</p>")
        }
    }

    [void]$html.AppendLine("<footer>Gerado pelo WinForge $(ConvertTo-WinForgeDiagHtml $sync.version) em $(ConvertTo-WinForgeDiagHtml (Get-Date).ToString('dd/MM/yyyy HH:mm')). Este relatório descreve o estado do computador; nenhuma alteração foi aplicada ao gerá-lo.</footer>")
    [void]$html.AppendLine('</body></html>')

    # BOM: sem ele o navegador pode adivinhar a code page do sistema e comer os acentos.
    # A gravação é em nome temporário e só depois vira o nome final. Dois motivos: um relatório
    # interrompido no meio não fica no disco com cara de relatório pronto, e a escrita do conteúdo
    # não acontece num nome que alguém possa ter transformado em link entre a criação da pasta e a
    # gravação - o Move-Item para o nome final é uma operação só.
    $temporario = "$Path.parcial"
    Remove-Item -LiteralPath $temporario -Force -ErrorAction SilentlyContinue
    [System.IO.File]::WriteAllText($temporario, $html.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temporario -Destination $Path -Force
    Write-WinForgeLog -Component "Diag" -Message "Relatório de diagnóstico gerado: $Path"

    if (-not $NoOpen) {
        try { Start-Process $Path } catch {
            Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Relatório gerado, mas não foi possível abri-lo: $($_.Exception.Message)"
        }
    }
    return $Path
}
#endregion
