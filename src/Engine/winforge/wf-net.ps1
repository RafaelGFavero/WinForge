#region ===== WinForge - rede sem fio (rádio, sondas e bloqueios) =====
# A escada de botões da aba Diagnóstico começa em leitura e só termina em driver. O motivo está no
# relato que a originou: "mesmo conectado certinho, a rede e a navegação não funcionam". Rádio
# conectado é prova de que o driver FUNCIONA - um driver quebrado não associa a um ponto de acesso
# nem autentica, e o Windows nem mostra "conectado". O que sobra é endereço (DHCP/APIPA), nome
# (DNS), rota, proxy ou filtro de software na pilha de rede, nessa ordem. Por isso arrancar o
# driver é o ÚLTIMO degrau, atrás de um diagnóstico que só lê.
#
# Este arquivo é a base de detecção dessa escada e NADA aqui escreve: descobre o rádio, mede
# conexão e diz quando uma das ações perigosas não pode rodar. Quem executa vem depois.
#
# Três conselhos repetidos da internet estão errados e ficaram de fora, cada um com a medição que o
# derrubou. Eles moram AQUI, acima das funções, e não dentro delas: as travas de fonte do -SelfTest
# leem o corpo do scriptblock, e o corpo inclui o bloco de ajuda - citar o que é proibido dentro da
# função deixaria a trava vermelha com o código certo.
#
# 1. "$env:SESSIONNAME -ne 'Console' diz se a sessão é remota." Medido no Windows 11 build 26200:
#    a variável veio VAZIA numa sessão de console legítima, e a comparação diria "remota" para toda
#    gente - o botão sumiria justamente na máquina de quem está sentado na frente dela. Quem
#    responde isso é GetSystemMetrics(SM_REMOTESESSION), a API que o próprio Windows usa.
#
# 2. "Test-NetConnection -Port testa a porta." Testa, e cobra caro: medido em 5.443 ms por chamada,
#    porque antes do teste de porta ele ainda roda ping e rastreamento de rota. Três sondas seriam
#    quinze segundos de tela parada. A sonda daqui abre a conexão direto, com espera curta.
#
# 3. "Ache o Wi-Fi procurando 'Wi-Fi' no nome do adaptador." O nome muda com o idioma do Windows e
#    com o que o dono da máquina digitou em "Renomear adaptador". A pergunta certa é sobre a MÍDIA
#    FÍSICA, que é 'Native 802.11' em qualquer idioma. Nesta máquina o filtro por mídia separa o
#    rádio Intel dos seis adaptadores virtuais de VPN (OpenVPN e Fortinet) numa linha - medido:
#    8 adaptadores visíveis, 6 virtuais e 2 físicos; com os ocultos, 23.

function Test-WinForgeRemoteSession {
    <#
    .SYNOPSIS
        Diz se esta sessão do Windows está sendo usada de longe (Área de Trabalho Remota).
    .DESCRIPTION
        SM_REMOTESESSION = 0x1000. A resposta é sobre a SESSÃO, e não sobre o processo nem sobre
        uma variável de ambiente que qualquer coisa pode ter apagado - é isso que a torna confiável.

        RESSALVA que precisa ir no texto do botão, e não só aqui: isto NÃO enxerga AnyDesk,
        TeamViewer, RustDesk e afins. Essas ferramentas pintam a tela da sessão de CONSOLE, então
        para o Windows - e para esta função - quem está usando a máquina está sentado na frente
        dela. O bloqueio cobre a Área de Trabalho Remota, que é a que morre junto com a placa de
        rede; quem usa as outras continua podendo se derrubar sozinho.

        O tipo é criado uma vez por processo: 'as [type]' evita o custo de compilar de novo, e
        Add-Type levantaria erro na segunda chamada.
    .OUTPUTS
        [bool]
    #>
    param()

    if (-not ('WfSysMetrics' -as [type])) {
        Add-Type -Namespace '' -Name 'WfSysMetrics' -MemberDefinition '[DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);'
    }
    return ([WfSysMetrics]::GetSystemMetrics(0x1000) -ne 0)
}

function Get-WinForgeWifiAdapter {
    <#
    .SYNOPSIS
        Acha o rádio sem fio desta máquina pela mídia física do adaptador.
    .DESCRIPTION
        Dois descartes, e os dois são necessários nesta máquina:

        1. Mídia física fora de '*802.11*'. É o que separa o rádio dos seis adaptadores virtuais de
           VPN (OpenVPN, Fortinet) e da placa de cabo, sem olhar para o nome de ninguém. Medido
           nesta máquina: 8 adaptadores visíveis, 6 virtuais e 2 físicos.
        2. Adaptador marcado como virtual. 'Microsoft Wi-Fi Direct Virtual Adapter' e 'Microsoft
           Hosted Network Virtual Adapter' declaram a MESMA mídia física do rádio de verdade,
           porque é em cima dele que eles andam. Eles não têm driver próprio para remover, e trocar
           o driver deles não conserta nada - quem tem de sair da lista são eles, não o rádio.

        Sobrando mais de um rádio de verdade (o de dentro do notebook mais um dongle USB), ganha o
        que está conectado; empatou, ganha o de menor ifIndex, que é estável entre execuções e não
        depende da ordem em que o Windows resolveu listar.
    .PARAMETER Adapters
        Lista pronta de adaptadores. É a porta do -SelfTest: com ela a função não consulta a
        máquina. Sem ela, a lista sai de Get-NetAdapter.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Name; ifIndex = <int>; Status; Problem; DriverProvider;
           PhysicalMediaType }
    #>
    param([object[]]$Adapters)

    $daMaquina = -not $PSBoundParameters.ContainsKey('Adapters')
    $vazio = @{ Ok = $false; Reason = ''; Name = $null; ifIndex = 0; Status = $null; Problem = $null; DriverProvider = $null; PhysicalMediaType = $null }
    if ($daMaquina) {
        try { $Adapters = @(Get-NetAdapter -ErrorAction Stop) }
        catch {
            $vazio.Reason = "Não deu para listar os adaptadores de rede desta máquina: $($_.Exception.Message)"
            return $vazio
        }
    }

    $semFio = @(@($Adapters) | Where-Object { $null -ne $_ -and ([string]$_.PhysicalMediaType) -like '*802.11*' })
    $fisicos = @($semFio | Where-Object { -not [bool]$_.Virtual })
    if (-not $fisicos.Count) {
        if ($semFio.Count) { $vazio.Reason = "Esta máquina só tem adaptador sem fio VIRTUAL ($($semFio.Count)): não há rádio de verdade para mexer." }
        else { $vazio.Reason = 'Esta máquina não tem adaptador sem fio.' }
        return $vazio
    }

    $escolhido = @($fisicos | Sort-Object -Property @{ Expression = { ([string]$_.Status) -eq 'Up' }; Descending = $true },
                                                    @{ Expression = { [int]$_.ifIndex }; Descending = $false })[0]

    # Código do Gerenciador de Dispositivos (0 = sem problema, 22 = desabilitado, 43 = o Windows
    # parou o dispositivo). Win32_NetworkAdapter casa pelo ifIndex e existe desde sempre;
    # Get-PnpDevice só passou a expor 'Problem' no 1809, e o WinForge ainda atende o 1809.
    # A consulta só sai quando a lista veio DA MÁQUINA: com -Adapters o gabarito manda, e o
    # -SelfTest não pode disparar CIM por causa de uma linha de fixture.
    $problema = $null
    if ($escolhido.PSObject.Properties['Problem']) { $problema = $escolhido.Problem }
    elseif ($daMaquina) {
        try {
            $indice = [int]$escolhido.ifIndex
            $cim = @(Get-CimInstance -ClassName Win32_NetworkAdapter -Filter "InterfaceIndex=$indice" -ErrorAction Stop)
            if ($cim.Count) { $problema = [int]$cim[0].ConfigManagerErrorCode }
        } catch { $problema = $null }
    }

    return @{
        Ok                = $true
        Reason            = ''
        Name              = [string]$escolhido.Name
        ifIndex           = [int]$escolhido.ifIndex
        Status            = [string]$escolhido.Status
        Problem           = $problema
        DriverProvider    = [string]$escolhido.DriverProvider
        PhysicalMediaType = [string]$escolhido.PhysicalMediaType
    }
}

function Test-WinForgeTcpProbe {
    <#
    .SYNOPSIS
        Diz se dá para abrir uma conexão TCP até um destino dentro do tempo dado, e quanto demorou.
    .DESCRIPTION
        Conexão direta, com espera curta: o diagnóstico dispara três dessas seguidas (um endereço
        numérico, um nome e a porta 80 do endereço numérico) para separar "a rota está morta" de
        "só a resolução de nomes quebrou", e o usuário não pode ficar olhando tela parada enquanto
        isso acontece.

        O relógio começa ANTES da resolução de nome, porque para quem está esperando a espera é a
        mesma coisa. A forma com nome do BeginConnect resolve o nome de forma assíncrona, então um
        único AsyncWaitHandle cobre resolução e conexão - o tempo limite é de ponta a ponta e não
        tem como escapar pela metade cara.

        EndConnect é chamado dentro de try: é ele quem levanta a recusa do outro lado, e uma
        exceção escapando daqui viraria erro no meio do diagnóstico em vez de "não conectou".

        O soquete fecha no finally dê no que der. Sem isso, um destino que engole o pacote deixa um
        descritor pendurado por sonda, e o diagnóstico roda a cada abertura da janela.
    .PARAMETER TargetHost
        Nome ou endereço do destino.
    .PARAMETER Port
        Porta TCP.
    .PARAMETER TimeoutMs
        Teto da espera, em milissegundos.
    .OUTPUTS
        @{ Ok = <bool>; Ms = <int> }
    #>
    param(
        [Parameter(Mandatory)][string]$TargetHost,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 2000
    )

    $relogio = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    $cliente = $null
    try {
        $cliente = New-Object System.Net.Sockets.TcpClient
        $espera = $cliente.BeginConnect($TargetHost, $Port, $null, $null)
        if ($espera.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            try { $cliente.EndConnect($espera); $ok = [bool]$cliente.Connected } catch { $ok = $false }
        }
    } catch {
        $ok = $false
    } finally {
        if ($null -ne $cliente) { try { $cliente.Close() } catch { } }
        $relogio.Stop()
    }
    return @{ Ok = $ok; Ms = [int]$relogio.ElapsedMilliseconds }
}

function Get-WinForgeNetworkFacts {
    <#
    .SYNOPSIS
        Levanta NA MÁQUINA os fatos que a escada de bloqueios pesa, e só os que a ação pedida usa.
    .DESCRIPTION
        Os padrões são o LADO SEGURO de cada pergunta: o que não deu para responder BLOQUEIA em vez
        de liberar. 'ExportOk' é a exceção e nasce $true, porque ele não é uma pergunta sobre a
        máquina - é o resultado da cópia de segurança que quem executa acabou de tentar, e antes de
        tentar não há falha nenhuma. Quem executa passa o valor medido por argumento OBRIGATÓRIO em
        Assert-WinForgeNetworkGuard; aqui ele é só o ponto de partida.

        O botão 3 (endereço e cache de nomes) não mexe em driver, então para ele só a sessão e o
        número do build são levantados: nada de adaptador, de perfil nem de varredura de INF.

        'SemPerfil' é fato, e não porta de saída. "É virtual?" é a única pergunta desta lista sem
        resposta barata e confiável fora do perfil - quem separa um convidado de VMware de uma
        máquina física com Hyper-V ligado é a assinatura de fabricante/modelo que
        Get-WinForgeSystemProfile já monta, e uma segunda cópia dessa assinatura aqui só teria como
        futuro divergir da primeira. Sem perfil, a resposta honesta não é "não é virtual", é "ainda
        não sei", e ela vira um degrau da escada como qualquer outro, na posição que lhe cabe.

        A hora deste levantamento importa: dois dos fatos são VOLÁTEIS entre pintar a aba e clicar
        no botão (o cabo ainda ligado, a máquina ainda na tomada). Por isso quem executa chama a
        asserção, que chama isto de novo, em vez de reusar o que a pintura levantou.
    .PARAMETER Action
        Qual ação vai ser pesada. É ela que decide o que é caro o bastante para não ser levantado.
    .OUTPUTS
        Hashtable com Remote, Build, OtherAdapter, Inbox, ExportOk, OnBattery, Virtual, Server,
        NeedRestart, FreeBytes, NeedBytes e SemPerfil.
    #>
    param([Parameter(Mandatory)][ValidateSet('NetDnsRenew', 'WifiDriverReinstall', 'WifiDriverGeneric', 'WifiDriverRestore')][string]$Action)

    $f = @{
        Remote = $false; Build = 0; OtherAdapter = $false; Inbox = $false; ExportOk = $true
        OnBattery = $false; Virtual = $false; Server = $false; NeedRestart = $false
        SemPerfil = $false
        FreeBytes = 0
        # O pacote de driver de rede exportado cabe folgado nisto; é piso, não estimativa fina.
        NeedBytes = 200MB
    }
    try { $f.Remote = [bool](Test-WinForgeRemoteSession) } catch { $f.Remote = $false }
    try { $f.Build = [int][Environment]::OSVersion.Version.Build } catch { $f.Build = 0 }
    if ($Action -eq 'NetDnsRenew') { return $f }

    $perfil = $null
    try { $perfil = $sync.Profile } catch { $perfil = $null }
    if ($null -eq $perfil -or $null -eq $perfil.Machine -or $null -eq $perfil.OS -or $null -eq $perfil.Power) {
        # Sem perfil não há o que levantar daqui para baixo, e os padrões seguros já estão postos.
        $f.SemPerfil = $true
        return $f
    }
    $f.Virtual   = [bool]$perfil.Machine.IsVirtual
    $f.Server    = [bool]$perfil.OS.IsServer
    $f.OnBattery = [bool]$perfil.Power.OnBattery

    # Reinício pendente: as três marcas clássicas, na ordem em que são baratas de ler.
    foreach ($chave in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                         'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path -LiteralPath $chave) { $f.NeedRestart = $true }
    }
    if (-not $f.NeedRestart) {
        try {
            $pendentes = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop).PendingFileRenameOperations
            $f.NeedRestart = (@(@($pendentes) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0)
        } catch { }
    }

    # A lista de adaptadores é consultada UMA vez e reaproveitada pelos dois fatos que dependem
    # dela: Get-NetAdapter custa perto de 200 ms.
    #
    # "Outra via" é outro caminho para a internet enquanto o rádio está sem driver: cabo, celular
    # por USB, outro dongle. O próprio rádio não conta, e os virtuais também não - VPN, Wi-Fi Direct
    # e comutador de máquina virtual andam EM CIMA de um adaptador de verdade e caem junto com ele.
    # Medido nesta máquina: 8 adaptadores visíveis, 6 deles virtuais (OpenVPN e Fortinet) e 2
    # físicos; com os ocultos são 23. Sem esse descarte, a resposta seria "tem outra via" com o cabo
    # desligado e o Wi-Fi sendo a única saída.
    $adaptadores = @()
    $radio = @{ Ok = $false; ifIndex = 0 }
    try {
        $adaptadores = @(Get-NetAdapter -ErrorAction Stop)
        $radio = Get-WinForgeWifiAdapter -Adapters $adaptadores
        $indiceRadio = [int]$radio.ifIndex
        $f.OtherAdapter = (@($adaptadores | Where-Object {
            ([string]$_.Status) -eq 'Up' -and -not [bool]$_.Virtual -and [int]$_.ifIndex -ne $indiceRadio
        }).Count -gt 0)
    } catch { $f.OtherAdapter = $false }

    try {
        $raizWindows = [string][Environment]::GetFolderPath('Windows')
        $f.FreeBytes = [long](New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($raizWindows))).AvailableFreeSpace
    } catch { $f.FreeBytes = 0 }

    # O driver básico só é condição do botão que troca por ele; para os outros a pergunta não
    # existe, e nem a varredura de INF nem a consulta de IDs de hardware são pagas.
    if ($Action -eq 'WifiDriverGeneric') {
        $idRadio = ''
        if ($radio.Ok) {
            $objRadio = @($adaptadores | Where-Object { [int]$_.ifIndex -eq [int]$radio.ifIndex })
            if ($objRadio.Count) { $idRadio = [string]$objRadio[0].PnPDeviceID }
        }
        $f.Inbox = (-not [string]::IsNullOrWhiteSpace($idRadio)) -and (Test-WinForgeInboxWifiDriver -PnpDeviceId $idRadio)
    }
    return $f
}

function Assert-WinForgeNetworkGuard {
    <#
    .SYNOPSIS
        LANÇA quando a ação de rede pedida não pode rodar nesta máquina. É a porta do caminho de
        execução, e não um conselho.
    .DESCRIPTION
        Test-WinForgeNetworkGuard devolve um objeto, e objeto devolvido depende de alguém lembrar de
        olhar. Esta base de código já pagou por isso uma vez: o bloco de ajuda de
        Assert-WinForgeNotSelfTest registra o estrago de quando a trava de simulação era consultiva -
        helpers sem param() engoliram o -DryRun e instaladores rodaram de verdade na máquina de um
        usuário. A conclusão de lá vale aqui: a trava que importa é a que LANÇA.

        Duas coisas que ela resolve além de lançar:

        1. O MOMENTO. Os fatos são levantados AQUI, no caminho de execução, e não na pintura do
           botão. Dois deles mudam entre uma coisa e outra - se ainda há cabo ligado e se a máquina
           ainda está na tomada -, e são justamente os que decidem se a ação é segura.
        2. A EXPORTAÇÃO. 'ExportOk' não é detectável: é o resultado da cópia de segurança que quem
           executa acabou de tentar. Como argumento OBRIGATÓRIO, ele deixa de depender de alguém
           lembrar de passá-lo - sem ele a chamada nem compila. E ele MANDA sobre qualquer tabela de
           fatos recebida: uma tabela dizendo que a cópia deu certo não pode desfazer o que quem
           executa acabou de medir.
    .PARAMETER Action
        A ação que está prestes a rodar.
    .PARAMETER ExportOk
        Se a cópia de segurança do driver atual deu certo. Quem não exporta nada passa $true.
    .PARAMETER Facts
        Fatos prontos, no lugar dos levantados na máquina. É a porta do -SelfTest; 'ExportOk'
        continua vindo do argumento obrigatório, e não daqui.
    .OUTPUTS
        O resultado do guarda quando ele libera. Quando ele recusa, uma exceção com o motivo.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('NetDnsRenew', 'WifiDriverReinstall', 'WifiDriverGeneric', 'WifiDriverRestore')][string]$Action,
        [Parameter(Mandatory)][bool]$ExportOk,
        [hashtable]$Facts
    )

    $f = $(if ($PSBoundParameters.ContainsKey('Facts') -and $null -ne $Facts) { @{} + $Facts } else { Get-WinForgeNetworkFacts -Action $Action })
    $f['ExportOk'] = $ExportOk
    $guarda = Test-WinForgeNetworkGuard -Action $Action -Facts $f
    if (-not $guarda.Ok) {
        throw "Recusado: '$Action' não pode rodar nesta máquina. $([string]$guarda.Reason)"
    }
    return $guarda
}

function Test-WinForgeNetworkGuard {
    <#
    .SYNOPSIS
        Diz se uma das ações de rede pode rodar nesta máquina e, quando não pode, explica por quê.
    .DESCRIPTION
        A escada de bloqueios, do mais barato de responder ao mais caro:

            sessão remota -> versão do Windows -> máquina virtual / Windows Server ->
            reinício pendente -> outra via de rede -> bateria -> espaço em disco ->
            driver básico do Windows -> cópia de segurança do driver

        Disparou um bloqueio ABSOLUTO, a escada para ali: a recusa é uma frase em português que diz
        o que fazer antes de tentar de novo, e NÃO existe "continuar mesmo assim". Um botão que
        arranca o driver de rede de uma máquina sem outra via para a internet não é uma escolha que
        o usuário possa fazer bem informado no meio do problema - é como ele fica sem internet.

        Três coisas que a devolução separa de propósito:

        - Ok  = a ação pode rodar. Vira botão clicável.
        - Hidden = o botão nem aparece. Só duas coisas escondem um botão: build abaixo do 1903
          (os verbos '/remove-device' e '/scan-devices' do pnputil não existem lá, então o botão
          seria um erro garantido) e a exceção D3, que é o botão do driver básico numa máquina
          para a qual o Windows não tem driver básico nenhum. Nos dois casos não há o que o
          usuário possa fazer para destravar, e botão desabilitado que nunca habilita é ruído.
        - Blocks = TUDO que disparou, inclusive o que é só aviso. O caso que existe hoje é "não há
          outra via de rede": no botão que troca pelo driver básico isso é absoluto (se o básico
          não servir, acabou a internet), no botão que só reinstala o mesmo driver é aviso (o
          caminho normal é o Windows repor o que estava lá). Quem pinta a tela lê Blocks; quem
          decide se clica lê Ok.

        Ordem dos textos importa mais do que parece: o primeiro que dispara é o que o usuário lê, e
        os mais baratos são também os mais fundamentais (não adianta falar de espaço em disco para
        quem está acessando a máquina de longe).
    .PARAMETER Action
        Qual das ações está sendo pesada.
    .PARAMETER Facts
        Fatos já levantados. É a porta do -SelfTest: com ela a função não consulta nada da máquina.
        Sem ela, os mesmos fatos são levantados aqui, e só os que a ação pedida pode usar.
    .OUTPUTS
        @{ Ok = <bool>; Hidden = <bool>; Reason = <string>; Blocks = @(<string>) }
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('NetDnsRenew', 'WifiDriverReinstall', 'WifiDriverGeneric', 'WifiDriverRestore')][string]$Action,
        [hashtable]$Facts
    )

    $todas      = @('NetDnsRenew', 'WifiDriverReinstall', 'WifiDriverGeneric', 'WifiDriverRestore')
    $driver     = @('WifiDriverReinstall', 'WifiDriverGeneric', 'WifiDriverRestore')
    $tiraDriver = @('WifiDriverReinstall', 'WifiDriverGeneric')

    $f = $(if ($PSBoundParameters.ContainsKey('Facts') -and $null -ne $Facts) { $Facts } else { Get-WinForgeNetworkFacts -Action $Action })

    $build      = [int]$f.Build
    $livre      = [long]$f.FreeBytes
    $preciso    = [long]$f.NeedBytes
    $livreMB    = [math]::Round($livre / 1MB)
    $precisoMB  = [math]::Round($preciso / 1MB)

    # A escada. 'Absolutas' = ações em que o fato RECUSA; 'Avisos' = ações em que ele só avisa e a
    # escada continua. 'Esconde' tira o botão da tela em vez de desabilitá-lo.
    $escada = @(
        @{ Vale = [bool]$f.Remote; Absolutas = $todas
           Texto = 'Você está usando este computador de longe, por Área de Trabalho Remota. Toda ação desta escada mexe na conexão que está te trazendo até aqui, e se ela cair não há como desfazer de longe. Faça isto sentado na frente da máquina.' },
        @{ Vale = ($build -lt 18362); Absolutas = $tiraDriver; Esconde = $true
           Texto = "A versão do Windows desta máquina (build $build) é anterior à 1903, e os comandos que removem e reinstalam o driver não existem nela. Atualize o Windows para usar este botão." },
        @{ Vale = [bool]$f.SemPerfil; Absolutas = $driver
           Texto = 'O diagnóstico desta aba ainda não terminou. Espere o cartão do computador aparecer e tente de novo: sem ele não dá para saber se esta máquina é virtual ou um Windows Server, e é aí que mexer no driver de rede sai caro.' },
        @{ Vale = [bool]$f.Virtual; Absolutas = $driver
           Texto = 'Esta é uma máquina virtual. A placa de rede que você está vendo é do programa de virtualização, não do computador: trocar o driver dela não conserta o Wi-Fi da máquina de verdade e derruba a rede do convidado. Faça isto no computador que hospeda a máquina virtual.' },
        @{ Vale = [bool]$f.Server; Absolutas = $driver
           Texto = 'Este é um Windows Server. Aqui a rede costuma ser a única porta de administração da máquina, e a lista de quem fica sem serviço quando ela cai não é só de quem está na frente dela. Troque o driver por uma janela de manutenção combinada, com acesso local garantido.' },
        @{ Vale = [bool]$f.NeedRestart; Absolutas = $driver
           Texto = 'Há uma atualização esperando para terminar de se instalar. Reinicie o computador primeiro: mexer no driver antes disso mistura duas instalações na mesma pasta de drivers e a que falhar leva a outra junto.' },
        @{ Vale = (-not [bool]$f.OtherAdapter); Absolutas = @('WifiDriverGeneric'); Avisos = @('WifiDriverReinstall')
           Texto = 'Não há outra forma de entrar na internet nesta máquina agora. Este botão troca o driver do Wi-Fi pelo básico do Windows, e se o básico não servir você fica sem internet nenhuma para baixar o driver do fabricante. Ligue um cabo de rede, ou compartilhe a internet do celular por USB, e tente de novo.'
           TextoAviso = 'Não há outra forma de entrar na internet nesta máquina agora (nenhum cabo de rede nem celular por USB). O normal é o Windows repor o mesmo driver sozinho em segundos, mas se isso não acontecer você fica sem internet para baixar o driver do fabricante.' },
        @{ Vale = [bool]$f.OnBattery; Absolutas = $driver
           Texto = 'O computador está na bateria. Ligue-o na tomada antes: se ele desligar no meio da troca, a máquina reinicia sem driver de rede nenhum.' },
        @{ Vale = ($livre -lt $preciso); Absolutas = $tiraDriver
           Texto = "Falta espaço no disco do Windows: há $livreMB MB livres e são necessários pelo menos $precisoMB MB para guardar a cópia de segurança do driver atual antes de removê-lo. Libere espaço e tente de novo." },
        @{ Vale = (-not [bool]$f.Inbox); Absolutas = @('WifiDriverGeneric'); Esconde = $true
           Texto = 'O Windows não tem driver básico para este rádio sem fio: o único driver que existe para ele é o do fabricante, que já está instalado. Não há por que trocar, e remover o que está lá deixaria a máquina sem Wi-Fi até você instalar o do fabricante de novo por outra via.' },
        @{ Vale = (-not [bool]$f.ExportOk); Absolutas = $tiraDriver
           Texto = 'A cópia de segurança do driver atual falhou, então não há caminho de volta se a troca der errado. Este botão só roda com a cópia guardada.' }
    )

    # ESCONDER é propriedade do BOTÃO; EXPLICAR é do degrau. Os dois são decididos separadamente, e
    # de propósito.
    #
    # O laço abaixo para no primeiro degrau absoluto, porque a explicação que o usuário lê é a do
    # motivo mais fundamental. Se 'Hidden' saísse desse mesmo laço - como saía -, bastaria um degrau
    # anterior disparar para o botão voltar a aparecer: um notebook SEM driver básico e na BATERIA
    # mostrava o botão mais perigoso da escada desabilitado, dizendo "ligue na tomada". É o estado
    # exato que a decisão de ESCONDER existe para impedir, porque botão desabilitado faz a pessoa
    # procurar na internet como habilitá-lo, e o que ela acha é a opção de forçar.
    #
    # Então basta UM degrau que esconde estar valendo para esta ação: a varredura é sobre a escada
    # inteira e não depende de quem interrompeu o laço.
    $queEscondem = @($escada | Where-Object { $_.Vale -and $_.Esconde -and ($Action -in @($_.Absolutas)) })
    $escondido = [bool]$queEscondem.Count

    $blocos = New-Object System.Collections.Generic.List[string]
    $motivo = ''
    if ($escondido) {
        # QUEM ESCONDE É QUEM EXPLICA. Um botão que sumiu da tela explicado por outro degrau é a
        # confusão mais cara desta escada: "ligue o computador na tomada" para um botão que não está
        # ali não diz nada a ninguém, e quem for procurar o botão vai procurar pelo motivo errado.
        # Sem isto, um notebook sem driver básico e na bateria some com o botão 5 e culpa a bateria.
        $motivo = [string]$queEscondem[0].Texto
        $blocos.Add($motivo)
    } else {
        foreach ($degrau in $escada) {
            if (-not $degrau.Vale) { continue }
            if ($Action -in @($degrau.Absolutas)) {
                $blocos.Add([string]$degrau.Texto)
                $motivo = [string]$degrau.Texto
                break
            }
            if ($Action -in @($degrau.Avisos)) {
                $blocos.Add([string]$(if ($degrau.ContainsKey('TextoAviso')) { $degrau.TextoAviso } else { $degrau.Texto }))
            }
        }
    }

    return @{ Ok = ($motivo -eq ''); Hidden = $escondido; Reason = $motivo; Blocks = @($blocos.ToArray()) }
}

function Test-WinForgeInboxWifiDriver {
    <#
    .SYNOPSIS
        Diz se o Windows traz driver próprio para o rádio sem fio desta máquina.
    .DESCRIPTION
        O Windows não tem um driver 802.11 universal, como tem para placa de cabo. "Básico" aqui é
        o INF que a própria Microsoft empacotou para ESTE rádio, e ele só existe se algum INF de
        classe Net da pasta %SystemRoot%\INF citar um dos IDs de hardware do dispositivo - que é
        exatamente o critério que o Windows usa para casar driver com dispositivo.

        Os INF de terceiro que o Windows copiou para essa pasta são renomeados 'oemNN.inf', então
        o filtro 'net*.inf' - a convenção de nome da classe Net - já os deixa de fora, e de quebra
        derruba a varredura de ~600 arquivos para os 89 desta máquina (medido: 13 ms para listar,
        64 ms para ler todos).

        TETO EXPLÍCITO mesmo assim, porque isto roda na abertura da janela: um relógio de 3 s
        interrompe a varredura. Estourou o teto, deu erro, ou não achou o rádio, a resposta é NÃO -
        e o botão some. É o lado seguro do erro: arrancar o driver que funciona pela metade sem ter
        o que pôr no lugar deixa a máquina sem rede nenhuma.

        DESVIO DECLARADO da especificação, que manda analisar a saída da ferramenta de drivers. Ela
        NÃO responde a esta pergunta, e a medição é esta, feita nesta máquina:

        - 'pnputil /enum-drivers' devolveu 985 linhas e 95 pacotes, e os 95 são 'oemNN.inf' - só os
          pacotes de TERCEIRO publicados no repositório de drivers. Os INF embutidos que moram em
          %SystemRoot%\INF não aparecem.
        - Nenhuma linha da saída traz ID DE HARDWARE. Sem ele não há como responder "o Windows tem
          driver para ESTE rádio": sobraria adivinhar pelo nome do arquivo, que é exatamente a
          fragilidade que se quer evitar.
        - A saída é LOCALIZADA ('Nome Original:', 'Nome do Provedor:'). Parseá-la quebraria num
          Windows em inglês, falha que este repositório já pagou duas vezes (o takeown do Plano 7 e
          o campo de TCP da aba Servidor).

        O que a crítica do revisor tinha de certo foi consertado: a busca não é mais no arquivo
        inteiro. Linha de comentário (que começa por ';') e a seção [Strings] ficam de fora, que são
        os dois lugares onde um ID de hardware aparece sem ser declaração de modelo.

        LIMITE CONHECIDO que fica: 'net*.inf' é convenção, não regra do sistema, e a conferência não
        interpreta as diretivas do INF. Um INF de rede da Microsoft com outro nome seria lido como
        ausente e o botão sumiria numa máquina em que ele funcionaria - erro para o lado de não
        estragar nada.
    .PARAMETER PnpDeviceId
        Identificador do dispositivo do rádio (PnPDeviceID do adaptador).
    .OUTPUTS
        [bool]
    #>
    param([Parameter(Mandatory)][string]$PnpDeviceId)

    try {
        # -InstanceId recebe o valor como PARÂMETRO: nada aqui monta texto de comando, de consulta
        # nem de caminho com o que veio do dispositivo.
        $ids = @((Get-PnpDeviceProperty -InstanceId $PnpDeviceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop).Data |
                 Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if (-not $ids.Count) { return $false }

        $pastaInf = Join-Path ([string][Environment]::GetFolderPath('Windows')) 'INF'
        $relogio = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($arquivo in @(Get-ChildItem -LiteralPath $pastaInf -Filter 'net*.inf' -File -ErrorAction Stop)) {
            if ($relogio.ElapsedMilliseconds -gt 3000) { return $false }
            $linhas = $null
            try { $linhas = [System.IO.File]::ReadAllLines($arquivo.FullName) } catch { continue }
            $naTabelaDeTextos = $false
            foreach ($linha in $linhas) {
                $corte = ([string]$linha).Trim()
                if ($corte.Length -eq 0) { continue }
                # Comentário não declara modelo nenhum: um ID citado ali é prosa.
                if ($corte[0] -eq ';') { continue }
                if ($corte[0] -eq '[') {
                    # A tabela de textos guarda os nomes bonitos dos dispositivos, e alguns deles
                    # trazem o ID escrito por extenso - de novo, não é declaração de modelo.
                    $naTabelaDeTextos = $corte.StartsWith('[Strings', [StringComparison]::OrdinalIgnoreCase)
                    continue
                }
                if ($naTabelaDeTextos) { continue }
                foreach ($id in $ids) {
                    if ($corte.IndexOf([string]$id, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
                }
            }
        }
        return $false
    } catch {
        return $false
    }
}

function Get-WinForgeWinsockEntries {
    <#
    .SYNOPSIS
        Lê o catálogo de protocolos do Winsock no registro e devolve uma entrada por provedor.
    .DESCRIPTION
        O catálogo mora em HKLM\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\Protocol_Catalog9,
        e ele são DOIS: 'Catalog_Entries' e 'Catalog_Entries64', um por arquitetura. Cada um tem uma
        subchave por provedor, e cada subchave guarda a estrutura empacotada 'PackedCatalogItem'.

        Ler só um dos dois é o defeito que esta função já teve: medido nesta máquina, 14 provedores
        em cada, 28 no total, e a leitura de um só afirmava 14. O custo não é o número errado no
        relatório - é um filtro de terceiro registrado apenas no catálogo da OUTRA arquitetura
        passar despercebido, que é exatamente o que este degrau existe para achar. Entrada sintética
        não pega isso; só a leitura da máquina de verdade pega.

        O registro é a fonte porque ele não depende de idioma: a saída de texto do netsh muda de
        língua com o Windows, e esta base de código já perdeu um campo inteiro por parsear texto
        localizado.

        A estrutura foi CONFERIDA byte a byte nesta máquina (Windows 11 26200, 14 provedores, todos
        do sistema, 888 bytes cada):

          offset   0, 260 bytes  caminho da DLL do provedor, ANSI, terminado em zero (MAX_PATH)
          offset 260, 628 bytes  WSAPROTOCOL_INFOW, e dentro dela:
          offset 300,   4 bytes  ProtocolChain.ChainLen (o número de elos da cadeia)
          offset 376, 512 bytes  szProtocol, o nome do provedor, em UTF-16

        O caminho vem com variável de ambiente por dentro ('%SystemRoot%\system32\mswsock.dll'), que
        é como o Windows o gravou; ele é expandido aqui para a comparação de pasta poder ser feita.

        Entrada curta demais ou ilegível é PULADA, e não vira entrada vazia: uma linha em branco no
        relatório seria lida como "tem um provedor estranho aqui".
    .OUTPUTS
        Array de @{ Name = <string>; Path = <string>; ChainLength = <int> }.
    #>
    param()

    $lidas = @()
    $chaves = @()
    foreach ($arquitetura in @('Catalog_Entries', 'Catalog_Entries64')) {
        $raiz = "HKLM:\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\Protocol_Catalog9\$arquitetura"
        try { $chaves += @(Get-ChildItem -LiteralPath $raiz -ErrorAction Stop) } catch { continue }
    }
    foreach ($chave in $chaves) {
        try {
            $bytes = (Get-ItemProperty -LiteralPath $chave.PSPath -Name 'PackedCatalogItem' -ErrorAction Stop).PackedCatalogItem
            if ($null -eq $bytes -or $bytes.Length -lt 888) { continue }
            $caminho = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 260)
            $zero = $caminho.IndexOf([char]0)
            if ($zero -ge 0) { $caminho = $caminho.Substring(0, $zero) }
            $nome = [System.Text.Encoding]::Unicode.GetString($bytes, 376, 512)
            $zeroN = $nome.IndexOf([char]0)
            if ($zeroN -ge 0) { $nome = $nome.Substring(0, $zeroN) }
            $lidas += @{
                Name        = [string]$nome
                Path        = [string][Environment]::ExpandEnvironmentVariables([string]$caminho)
                ChainLength = [int][System.BitConverter]::ToInt32($bytes, 300)
            }
        } catch { continue }
    }
    return @($lidas)
}

function Test-WinForgeWinsockCatalog {
    <#
    .SYNOPSIS
        Diz se o catálogo de protocolos do Winsock só tem provedores do próprio Windows.
    .DESCRIPTION
        São DOIS sinais, e cada um pega um jeito diferente de se enfiar na pilha de rede:

        1. CAMINHO fora da pasta do Windows. Numa máquina saudável todo provedor aponta para a
           mswsock.dll debaixo de %SystemRoot%; uma DLL em Program Files é software de terceiro
           metido entre o programa e o soquete.
        2. CADEIA com mais de um elo. É a marca do provedor em camadas (o LSP clássico): ele se
           declara como uma corrente que passa pelo provedor de baixo, e é exatamente assim que ele
           enxerga e altera o tráfego de todo mundo. Um provedor de base tem cadeia de UM elo.

        Os dois valem sozinhos, e é de propósito: um LSP instalado dentro da pasta do Windows tem
        caminho de sistema e cadeia longa, e um provedor de base de terceiro tem caminho estranho e
        cadeia curta. Cobrar os dois juntos deixaria os dois casos passar.

        Este degrau só DETECTA e NOMEIA. O WinForge não desliga, não reconfigura e não desinstala
        produto de segurança de terceiro - mesma regra que o faz não executar instalador baixado.
    .PARAMETER Entries
        As entradas do catálogo, cada uma com Name, Path e ChainLength. Sem o parâmetro, a lista sai
        de Get-WinForgeWinsockEntries.
    .OUTPUTS
        @{ Ok = <bool>; Third = @(@{ Name; Path; ChainLength }); Count = <int> }
    #>
    param([object[]]$Entries)

    if (-not $PSBoundParameters.ContainsKey('Entries')) { $Entries = @(Get-WinForgeWinsockEntries) }
    $lista = @(@($Entries) | Where-Object { $null -ne $_ })

    $pastaWindows = 'C:\Windows'
    try {
        $lida = [string][Environment]::GetFolderPath('Windows')
        if (-not [string]::IsNullOrWhiteSpace($lida)) { $pastaWindows = $lida }
    } catch { $pastaWindows = 'C:\Windows' }
    $prefixo = $pastaWindows.TrimEnd('\') + '\'

    $terceiros = @()
    foreach ($e in $lista) {
        $caminho = [string]$e.Path
        # A comparação é sem diferenciar maiúsculas porque o Windows grava 'C:\WINDOWS' numa máquina
        # e 'C:\Windows' na outra, e as duas são a mesma pasta.
        $deDentro = $caminho.StartsWith($prefixo, [StringComparison]::OrdinalIgnoreCase)
        $encadeado = ([int]$e.ChainLength -gt 1)
        if ((-not $deDentro) -or $encadeado) {
            $terceiros += @{ Name = [string]$e.Name; Path = $caminho; ChainLength = [int]$e.ChainLength }
        }
    }
    return @{ Ok = (-not @($terceiros).Count); Third = @($terceiros); Count = @($lista).Count }
}

function Get-WinForgeNetworkVerdict {
    <#
    .SYNOPSIS
        A frase que fecha o relatório de rede, escolhida de uma lista FECHADA de cinco.
    .DESCRIPTION
        Cinco frases, nenhuma inventada na hora, e a ordem é a da escada de reparo:

        1. FILTRO DE TERCEIRO, na frente de tudo - MAS só quando há SINTOMA de falha. Se um filtro
           de antivírus ou de VPN é a causa, remover e reinstalar o driver do Wi-Fi não conserta
           nada e ainda arrisca deixar a máquina sem rádio, e por isso ele vem antes de todo degrau
           que mexe em driver. É a única frase montada com dados (o nome do produto e onde
           desligá-lo), e mesmo ela é um molde fixo.

           A condição do sintoma foi medida e custou caro: SEM ela, esta máquina de
           desenvolvimento - com a internet perfeita e um filtro de VPN corporativa instalado -
           apontava o filtro como causa, e a frase "não encontrei nada errado" nunca apareceria em
           máquina corporativa nenhuma. Um diagnóstico que acusa sempre não é diagnóstico. Com a
           rede funcionando, o filtro sai como OBSERVAÇÃO no fim da frase limpa: o produto é
           nomeado, para quem voltar aqui depois saber por onde começar, e ninguém é mandado
           desligar coisa nenhuma.
        2. ENDEREÇO. 169.254.x.x é o endereço que o Windows dá a si mesmo quando o roteador não
           respondeu: sem endereço não há nome nem saída, e falar de DNS aqui seria desperdiçar a
           atenção de quem lê.
        3. NOME. Só vale quando o servidor de nomes configurado está mudo E o 1.1.1.1 responde -
           é essa diferença que separa "o servidor de nomes está errado" de "nada sai daqui". A
           frase AFIRMA que o 1.1.1.1 responde; sem a segunda metade da condição, ela mentiria.
        4. SAÍDA. Endereço e nome funcionam e mesmo assim nada chega lá fora: o problema está no
           roteador ou no provedor, e não neste computador.
        5. LIMPO, quando nenhuma das outras quatro se aplica.
    .PARAMETER Facts
        @{ Apipa; DnsOk; DnsPublicoOk; SaidaOk; Lsp }. 'Lsp' é a lista de filtros de terceiro, cada
        um com Name e Menu.
    .OUTPUTS
        Uma das cinco frases.
    #>
    param([Parameter(Mandatory)][hashtable]$Facts)

    # SINTOMA é falha observada, e são estes três: endereço que o roteador não deu, nome que não
    # resolve, ou nada saindo para fora. Sem nenhum deles a rede está funcionando, e nada pode ser
    # apontado como causa de um problema que não existe.
    $sintoma = ([bool]$Facts.Apipa) -or (-not $Facts.DnsOk) -or (-not $Facts.SaidaOk)

    if (@($Facts.Lsp).Count -and $sintoma) {
        return ("Há um filtro do {0} preso em todos os adaptadores. Desligue-o em {1} e teste de novo antes de mexer em driver." -f [string]@($Facts.Lsp)[0].Name, [string]@($Facts.Lsp)[0].Menu)
    }
    if ($Facts.Apipa) {
        return 'O computador não pegou endereço do roteador (está em 169.254.x.x). Comece por "Limpar cache de DNS e pegar endereço novo".'
    }
    if ((-not $Facts.DnsOk) -and $Facts.DnsPublicoOk) {
        return 'O endereço está certo, mas o servidor de nomes configurado não responde e o 1.1.1.1 responde. O problema é o servidor de nomes, não o Wi-Fi.'
    }
    if (-not $Facts.SaidaOk) {
        return 'O roteador entrega endereço e nome, mas nada sai para fora. O problema está no roteador ou no provedor, não neste computador.'
    }
    $limpo = 'Não encontrei nada errado na rede deste computador.'
    if (@($Facts.Lsp).Count) {
        # A OBSERVAÇÃO, e ela vem depois da frase limpa de propósito: quem lê a primeira linha lê
        # "está tudo bem", que é a verdade medida agora. O nome do produto fica registrado para
        # quem voltar aqui no dia em que a navegação falhar.
        return ("{0} Observação: há um filtro do {1} preso em todos os adaptadores; hoje ele não está atrapalhando, mas é o primeiro a testar se a navegação voltar a falhar." -f $limpo, [string]@($Facts.Lsp)[0].Name)
    }
    return $limpo
}

function Invoke-WinForgeNetworkDiagnostic {
    <#
    .SYNOPSIS
        O relatório de rede do primeiro degrau da escada: doze leituras e uma frase no fim.
    .DESCRIPTION
        SÓ LÊ. Este botão não altera adaptador, driver, pilha de rede nem configuração, e é por isso
        que ele é o primeiro: "conectado certinho e sem navegar" quase nunca é driver, e a única
        forma de descobrir o que é sem estragar nada é olhar.

        As doze leituras, na ordem: rádio sem fio, perfil da rede, endereço, rota padrão, servidor de
        nomes contra o 1.1.1.1, saída para a internet (as sondas e o indicador do próprio Windows),
        proxy, filtros presos aos adaptadores, catálogo de protocolos, MTU, IPv6 e código de problema
        do dispositivo.

        Cada leitura roda dentro do seu próprio try: uma consulta que falha vira uma linha dizendo
        que falhou, e não um relatório pela metade. O relatório é para uma pessoa leiga, então cada
        bloco diz o que leu e o que aquilo significa.

        A frase do fim é o veredito, e ela sai de lista fechada (Get-WinForgeNetworkVerdict).
    .PARAMETER Facts
        Fatos prontos para o veredito, no lugar dos levantados aqui. As doze leituras continuam
        saindo; o que muda é só a frase do fim.
    .OUTPUTS
        O texto do relatório, com o veredito na última linha.
    #>
    param([hashtable]$Facts)

    $L = New-Object System.Collections.Generic.List[string]
    $fatos = @{ Apipa = $false; DnsOk = $true; DnsPublicoOk = $true; SaidaOk = $true; Lsp = @() }

    $L.Add('Diagnóstico de rede do WinForge.')
    $L.Add('Tudo aqui é leitura: nenhum adaptador, driver ou configuração é alterado por este botão.')

    # ---- 1. Rádio sem fio
    $radio = @{ Ok = $false; Reason = 'não consultado'; ifIndex = 0 }
    $L.Add('')
    $L.Add('1. Rádio sem fio')
    try {
        $radio = Get-WinForgeWifiAdapter
        if ($radio.Ok) { $L.Add("   $($radio.Name) (ifIndex $($radio.ifIndex)), driver de $($radio.DriverProvider), mídia $($radio.PhysicalMediaType), situação $($radio.Status).") }
        else { $L.Add("   $($radio.Reason)") }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 2. Perfil da rede
    $L.Add('')
    $L.Add('2. Perfil da rede')
    try {
        $perfis = @(Get-NetConnectionProfile -ErrorAction Stop)
        if (-not $perfis.Count) { $L.Add('   Nenhuma rede ativa: nem cabo nem sem fio estão conectados.') }
        foreach ($p in $perfis) { $L.Add("   $($p.Name) em $($p.InterfaceAlias): categoria $($p.NetworkCategory), o Windows classifica a conexão como '$($p.IPv4Connectivity)'.") }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 3. Endereço (e o APIPA)
    $L.Add('')
    $L.Add('3. Endereço IP')
    try {
        $enderecos = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { [string]$_.InterfaceAlias -notlike '*Loopback*' })
        if (-not $enderecos.Count) { $L.Add('   Nenhum endereço IPv4 fora do laço local.') }
        # Quem lê isto clicou porque a internet parou, e uma parede de 169.254 iguais esconde a
        # única linha que interessa. Medido nesta máquina: NOVE das dez linhas eram 169.254 de
        # adaptadores virtuais de VPN parados, que é o estado normal deles. As que têm endereço de
        # verdade saem uma a uma; o resto vira uma linha de resumo, com a explicação junto.
        $ligados = @($enderecos | Where-Object { [string]$_.IPAddress -notlike '169.254.*' })
        $parados = @($enderecos | Where-Object { [string]$_.IPAddress -like '169.254.*' })
        foreach ($e in $ligados) { $L.Add("   $($e.InterfaceAlias): $($e.IPAddress)/$($e.PrefixLength) (origem $($e.PrefixOrigin)).") }
        if ($parados.Count -eq 1) { $L.Add("   $($parados[0].InterfaceAlias): $($parados[0].IPAddress) - endereço que o Windows dá a si mesmo quando ninguém respondeu.") }
        elseif ($parados.Count -gt 1) { $L.Add("   Mais $($parados.Count) adaptador(es) em 169.254.x.x ($(@($parados | ForEach-Object { [string]$_.InterfaceAlias }) -join ', ')): é o endereço que o Windows dá a si mesmo quando não há ninguém do outro lado, e é o normal para adaptador de VPN parado ou placa sem cabo.") }
        # 169.254 é o endereço que o Windows dá a si mesmo quando ninguém respondeu ao pedido de
        # DHCP. Só conta nos adaptadores FÍSICOS e LIGADOS, e as duas metades foram medidas nesta
        # máquina: um adaptador desconectado guarda o último endereço que teve (o rádio desta
        # máquina está em 169.254 com o cabo ligado e navegando), e os seis adaptadores virtuais de
        # VPN ficam em 169.254 o tempo todo, por desenho. Sem as duas, a frase "o computador não
        # pegou endereço do roteador" sairia numa máquina com internet perfeita.
        $ativos = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Up' -and -not [bool]$_.Virtual } | ForEach-Object { [int]$_.ifIndex })
        $apipas = @($enderecos | Where-Object { [string]$_.IPAddress -like '169.254.*' -and ([int]$_.InterfaceIndex -in $ativos) })
        $fatos.Apipa = [bool]$apipas.Count
        if ($fatos.Apipa) { $L.Add('   ATENÇÃO: 169.254.x.x é o endereço que o Windows dá a si mesmo quando o roteador não respondeu.') }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 4. Rota padrão
    $L.Add('')
    $L.Add('4. Rota padrão (o caminho para fora)')
    try {
        $rotas = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop)
        if (-not $rotas.Count) { $L.Add('   Não há rota padrão: sem ela nada sai desta máquina, mesmo com endereço válido.') }
        # O NOME do adaptador, e não o índice: 'ifIndex 14' não diz nada para quem clicou porque a
        # internet parou, e é o nome que essa pessoa vê em "Conexões de Rede".
        $nomePorIndice = @{}
        try { foreach ($a in @(Get-NetAdapter -ErrorAction Stop)) { $nomePorIndice[[int]$a.ifIndex] = [string]$a.Name } } catch { }
        foreach ($r in $rotas) {
            $quem = [string]$nomePorIndice[[int]$r.ifIndex]
            if ([string]::IsNullOrWhiteSpace($quem)) { $quem = "adaptador $([int]$r.ifIndex)" }
            $L.Add("   Sai pelo $quem, através do roteador $($r.NextHop) (prioridade $($r.RouteMetric)).")
        }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 5. Servidor de nomes, contra o 1.1.1.1
    $L.Add('')
    $L.Add('5. Servidor de nomes (DNS)')
    try {
        $servidores = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { @($_.ServerAddresses).Count } | ForEach-Object { "$($_.InterfaceAlias): $(@($_.ServerAddresses) -join ', ')" })
        if ($servidores.Count) { foreach ($s in $servidores) { $L.Add("   $s") } }
        else { $L.Add('   Nenhum servidor de nomes configurado.') }
    } catch { $L.Add("   não deu para ler a lista de servidores: $($_.Exception.Message)") }
    # O mesmo nome é perguntado DUAS vezes: ao servidor configurado e ao 1.1.1.1. É a diferença
    # entre as duas respostas que separa "o servidor de nomes está errado" de "nada sai daqui" -
    # uma pergunta só não distingue os dois casos.
    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
        $nomeAlvo = 'www.microsoft.com'
        try { $null = Resolve-DnsName -Name $nomeAlvo -Type A -DnsOnly -QuickTimeout -ErrorAction Stop; $fatos.DnsOk = $true }
        catch { $fatos.DnsOk = $false }
        try { $null = Resolve-DnsName -Name $nomeAlvo -Type A -Server '1.1.1.1' -DnsOnly -QuickTimeout -ErrorAction Stop; $fatos.DnsPublicoOk = $true }
        catch { $fatos.DnsPublicoOk = $false }
        $L.Add("   '$nomeAlvo' pelo servidor configurado: $(if ($fatos.DnsOk) { 'respondeu' } else { 'NÃO respondeu' }).")
        $L.Add("   '$nomeAlvo' pelo 1.1.1.1: $(if ($fatos.DnsPublicoOk) { 'respondeu' } else { 'NÃO respondeu' }).")
    } else {
        $L.Add('   Resolve-DnsName não existe neste Windows: as duas consultas foram puladas.')
    }

    # ---- 6. Saída para a internet: as sondas e o indicador do Windows
    $L.Add('')
    $L.Add('6. Saída para a internet')
    $sondas = @(
        @{ Rotulo = 'DNS do Cloudflare (1.1.1.1:53)'; Alvo = '1.1.1.1'; Porta = 53 },
        @{ Rotulo = 'DNS do Google (8.8.8.8:53)';     Alvo = '8.8.8.8'; Porta = 53 },
        @{ Rotulo = 'HTTPS do Cloudflare (1.1.1.1:443)'; Alvo = '1.1.1.1'; Porta = 443 }
    )
    $passou = 0
    foreach ($s in $sondas) {
        try {
            $r = Test-WinForgeTcpProbe -TargetHost ([string]$s.Alvo) -Port ([int]$s.Porta) -TimeoutMs 2000
            if ($r.Ok) { $passou++ }
            $L.Add("   $($s.Rotulo): $(if ($r.Ok) { 'abriu' } else { 'não abriu' }) em $($r.Ms) ms.")
        } catch { $L.Add("   $($s.Rotulo): não deu para sondar: $($_.Exception.Message)") }
    }
    $fatos.SaidaOk = ($passou -gt 0)
    try {
        $conect = @(Get-NetConnectionProfile -ErrorAction Stop | ForEach-Object { [string]$_.IPv4Connectivity })
        if ($conect.Count) { $L.Add("   O indicador do próprio Windows diz: $($conect -join ', ').") }
    } catch { }

    # ---- 7. Proxy
    $L.Add('')
    $L.Add('7. Proxy')
    try {
        $ie = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ([int]$ie.ProxyEnable -eq 1) { $L.Add("   Proxy do usuário LIGADO: $($ie.ProxyServer). Um proxy morto derruba a navegação com a rede intacta.") }
        else { $L.Add('   Proxy do usuário desligado.') }
        if (-not [string]::IsNullOrWhiteSpace([string]$ie.AutoConfigURL)) { $L.Add("   Script de configuração automática: $($ie.AutoConfigURL)") }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }
    try {
        # O proxy do WinHTTP é um blob binário, e o TAMANHO dele não diz nada: medido nesta máquina,
        # ele tem 20 bytes com o netsh respondendo "acesso direto, nenhum servidor proxy". Quem
        # responde é o campo, não o tamanho:
        #
        #   [ 0..3]  versão (24 aqui)
        #   [ 4..7]  sinalizadores
        #   [ 8..11] tipo de acesso (1 = sem proxy, 3 = proxy nomeado)
        #   [12..15] tamanho do texto do servidor, em bytes
        #   [16.. ]  o texto do servidor, ANSI
        #
        # Só há proxy quando o tamanho do texto é maior que zero, e aí o texto é lido e mostrado:
        # mandar a pessoa procurar um proxy sem dizer qual é não resolve o problema dela.
        $wh = @((Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections' -Name 'WinHttpSettings' -ErrorAction Stop).WinHttpSettings)
        $tamanho = 0
        if ($wh.Count -ge 16) { $tamanho = [int][System.BitConverter]::ToInt32([byte[]]$wh, 12) }
        if ($tamanho -gt 0 -and $wh.Count -ge (16 + $tamanho)) {
            $L.Add("   O WinHTTP (usado por serviços e pelo Windows Update) aponta para o proxy $([System.Text.Encoding]::ASCII.GetString([byte[]]$wh, 16, $tamanho)).")
        } else {
            $L.Add('   O WinHTTP (usado por serviços e pelo Windows Update) está sem proxy.')
        }
    } catch { $L.Add('   O WinHTTP (usado por serviços e pelo Windows Update) está sem proxy.') }

    # ---- 8. Filtros presos aos adaptadores
    # É o degrau que este relatório existe para ter. Filtro de terceiro ligado em TODOS os
    # adaptadores físicos é o primeiro suspeito de "conecta e não navega", e ele é sempre de um
    # programa instalado: antivírus, firewall ou cliente de VPN. O WinForge nomeia e diz onde
    # desligar; quem desliga é a pessoa.
    $L.Add('')
    $L.Add('8. Filtros presos aos adaptadores')
    try {
        $fisicos = @(Get-NetAdapter -ErrorAction Stop | Where-Object { -not [bool]$_.Virtual })
        $ligacoes = @(Get-NetAdapterBinding -ErrorAction Stop | Where-Object { [string]$_.ComponentID -notlike 'ms_*' -and $_.Enabled })
        if (-not $ligacoes.Count) { $L.Add('   Nenhum filtro de terceiro ligado. Só os componentes do próprio Windows.') }
        foreach ($grupo in @($ligacoes | Group-Object ComponentID)) {
            $nome = [string]@($grupo.Group)[0].DisplayName
            $onde = @(@($grupo.Group) | ForEach-Object { [string]$_.Name })
            $emTodos = ($fisicos.Count -gt 0) -and (@($fisicos | Where-Object { $onde -contains [string]$_.Name }).Count -eq $fisicos.Count)
            $L.Add("   $nome ($($grupo.Name)): ligado em $($onde.Count) adaptador(es)$(if ($emTodos) { ', inclusive em TODOS os físicos' } else { '' }).")
            if ($emTodos) {
                $fatos.Lsp += @{
                    Name = $nome
                    Path = [string]$grupo.Name
                    # O caminho de menu é o do PRÓPRIO WINDOWS, e não o das configurações do
                    # produto: ele vale para qualquer antivírus, firewall ou cliente de VPN, é
                    # reversível com um clique e cita o nome exatamente como ele aparece na caixa
                    # que a pessoa vai abrir. Adivinhar o menu de cada fabricante envelheceria a
                    # cada atualização deles e mandaria o usuário para uma tela que não existe.
                    Menu = "Painel de Controle → Rede e Internet → Conexões de Rede → botão direito no adaptador → Propriedades → desmarcar `"$nome`""
                }
            }
        }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 9. Catálogo de protocolos (Winsock)
    $L.Add('')
    $L.Add('9. Catálogo de protocolos (Winsock)')
    try {
        $cat = Test-WinForgeWinsockCatalog
        $L.Add("   $($cat.Count) provedor(es) no catálogo.")
        if ($cat.Ok) { $L.Add('   Todos são do próprio Windows, com cadeia de um elo só.') }
        foreach ($t in @($cat.Third)) {
            $L.Add("   DE TERCEIRO: '$($t.Name)' em $($t.Path), cadeia de $($t.ChainLength) elo(s).")
            $fatos.Lsp += @{
                Name = [string]$t.Name
                Path = [string]$t.Path
                Menu = 'nas configurações do programa que o instalou, na parte de proteção de rede ou firewall'
            }
        }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 10. MTU
    $L.Add('')
    $L.Add('10. Tamanho máximo de pacote (MTU)')
    try {
        # [long], e não [int]: o laço local (Loopback Pseudo-Interface) declara NlMtu 4294967295,
        # que é UInt32.MaxValue e ESTOURA a conversão para Int32. Medido aqui: a exceção derrubava a
        # seção inteira no meio da lista, e só a primeira placa aparecia no relatório. O laço local
        # também sai da lista - o MTU dele não é do interesse de ninguém.
        foreach ($i in @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop | Where-Object { [string]$_.ConnectionState -eq 'Connected' -and [string]$_.InterfaceAlias -notlike '*Loopback*' })) {
            $mtu = [long]$i.NlMtu
            $aviso = if ($mtu -lt 1280) { ' (baixo demais: páginas grandes travam pela metade)' } else { '' }
            $L.Add("   $($i.InterfaceAlias): $mtu bytes$aviso.")
        }
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 11. IPv6
    $L.Add('')
    $L.Add('11. IPv6')
    try {
        $v6 = @(Get-NetAdapterBinding -ComponentID 'ms_tcpip6' -ErrorAction Stop | Where-Object { $_.Enabled })
        $L.Add("   Ligado em $($v6.Count) adaptador(es).")
    } catch { $L.Add("   não deu para ler: $($_.Exception.Message)") }

    # ---- 12. Código de problema do dispositivo
    $L.Add('')
    $L.Add('12. Código de problema do rádio')
    if ($radio.Ok -and $null -ne $radio.Problem) {
        $texto = switch ([int]$radio.Problem) {
            0  { 'sem problema.' }
            22 { 'o dispositivo está DESABILITADO no Gerenciador de Dispositivos.' }
            28 { 'faltam os drivers deste dispositivo.' }
            43 { 'o Windows PAROU o dispositivo porque ele relatou um problema.' }
            default { 'código do Gerenciador de Dispositivos.' }
        }
        $L.Add("   Código $($radio.Problem): $texto")
    } else {
        $L.Add('   Sem código para relatar.')
    }

    if ($PSBoundParameters.ContainsKey('Facts') -and $null -ne $Facts) { $fatos = $Facts }
    $L.Add('')
    $L.Add('Veredito')
    $L.Add((Get-WinForgeNetworkVerdict -Facts $fatos))
    return ($L -join "`r`n")
}

# =============================================================== o pnputil, e as três armadilhas
# Daqui para baixo é o mecanismo que REMOVE e INSTALA driver de rede. A régua sobe: uma máquina que
# erra aqui fica sem nenhum meio de conexão, e o caso que abriu esta leva é um notebook.
#
# Três armadilhas, todas MEDIDAS nesta máquina, e nenhuma delas aparece com entrada sintética:
#
# (a) CÓDIGO DE SAÍDA. '$LASTEXITCODE -gt 0' trata -536870340 como sucesso, porque ele é NEGATIVO.
#     Só 0 é sucesso, e é por isso que a pergunta virou função em vez de comparação solta.
# (b) DECODIFICAÇÃO. O pnputil escreve CP1252 quando a saída é redirecionada, e não OEM 850 -
#     medido: a code page ANSI desta máquina é 1252, e 'Versão do Driver' volta com o acento certo
#     em 'ansi' e embaralhado em 'oem'.
# (c) SAÍDA COM CÓDIGO 0 E DISPOSITIVO EM FALHA. Medido: '/enum-devices /class Net /problem'
#     devolveu o 'Fortinet SSL VPN Virtual Ethernet Adapter #2' com
#     'Código do Problema: 10 (0x0A) [CM_PROB_FAILED_START]' e SAIU COM 0. Confiar no código de
#     saída para saber se há dispositivo quebrado é confiar em nada; a saída tem de ser lida.
#
# E uma quarta coisa, que não é armadilha e sim limite: 'pnputil /enum-drivers' lista SÓ pacotes de
# terceiro. Medido aqui: 96 blocos, 96 deles 'oemNN.inf', NENHUM com uma só linha '.inf'. Não há
# opção de listar os embutidos (o /? mostra /class, /files, /ids e /devices, e nada de inbox). Ou
# seja: alimentado com a saída de uma máquina de verdade, Select-WinForgeWifiInboxDriver responde
# "não há embutido" SEMPRE. Quem responde de fato a essa pergunta é a varredura de INF de
# Test-WinForgeInboxWifiDriver; esta função existe para a outra metade, que é saber QUAIS pacotes
# de terceiro estão instalados para exportar antes de mexer neles.

function Get-WinForgeDriverStoreEntry {
    <#
    .SYNOPSIS
        Quebra a saída de 'pnputil /enum-drivers' em uma entrada por pacote de driver.
    .DESCRIPTION
        A saída é LOCALIZADA, e por isso os RÓTULOS não servem de âncora: o mesmo campo é
        'Published Name', 'Nome Publicado' ou 'Nome do arquivo INF publicado' conforme a versão e o
        idioma. Os VALORES servem, e são eles que ancoram tudo aqui:

        - Os blocos são separados por linha em branco.
        - Dentro do bloco, o PRIMEIRO valor terminado em '.inf' é o nome publicado, e o SEGUNDO,
          quando existe, é o nome original. Medido: o bloco de um pacote de terceiro tem DUAS
          linhas '.inf' e o de um embutido teria UMA. Confundir a segunda com um embutido é o que
          some com o botão do driver básico.
        - A linha do GUID de classe é reconhecível pelo VALOR ({8-4-4-4-12}), e ela ancora as duas
          de cima: o provedor e o nome da classe. É posição, mas posição RELATIVA a uma linha que se
          identifica sozinha, e não contagem a partir do topo do bloco.
        - A data e a versão saem do único valor com a forma 'dd/mm/aaaa <números e pontos>'.

        'Get-WindowsDriver -Online -All' traz um campo '.Inbox' que responderia parte disto de forma
        direta, e foi descartado: ele EXIGE ELEVAÇÃO, e o -SelfTest roda sem administrador.
    .PARAMETER Text
        A saída do comando, já decodificada.
    .OUTPUTS
        Array de @{ Published; Original; Provider; Class; Date; Version; IsOem = <bool> }.
    #>
    param([string]$Text)

    $entradas = @()
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    foreach ($bloco in @($Text -split "(?:\r?\n){2,}")) {
        $infs = @([regex]::Matches($bloco, '(?m)^\s*[^:\r\n]+:\s*(\S+\.inf)\s*$') | ForEach-Object { $_.Groups[1].Value })
        if (-not $infs.Count) { continue }
        $linhas = @(@($bloco -split "\r?\n") | Where-Object { $_ -match ':' })

        $iGuid = -1
        for ($k = 0; $k -lt $linhas.Count; $k++) {
            if ($linhas[$k] -match ':\s*\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}\s*$') { $iGuid = $k; break }
        }
        $provedor = ''
        $classe = ''
        if ($iGuid -ge 1) { $classe = ((($linhas[$iGuid - 1]) -split ':', 2)[1]).Trim() }
        if ($iGuid -ge 2) { $provedor = ((($linhas[$iGuid - 2]) -split ':', 2)[1]).Trim() }

        $data = ''
        $versao = ''
        foreach ($linha in $linhas) {
            if ($linha -match ':\s*(\d{1,2}/\d{1,2}/\d{4})\s+([\d.]+)\s*$') { $data = $Matches[1]; $versao = $Matches[2]; break }
        }

        $publicado = [string]$infs[0]
        $entradas += @{
            Published = $publicado
            Original  = $(if ($infs.Count -gt 1) { [string]$infs[1] } else { '' })
            Provider  = $provedor
            Class     = $classe
            Date      = $data
            Version   = $versao
            IsOem     = [bool]($publicado -match '^oem\d+\.inf$')
        }
    }
    return @($entradas)
}

function Select-WinForgeWifiInboxDriver {
    <#
    .SYNOPSIS
        Separa, entre os pacotes lidos, o driver embutido do Windows e os pacotes de terceiro, só na
        classe de rede.
    .DESCRIPTION
        A classe é filtrada porque a lista traz a máquina inteira: impressora, vídeo e áudio não
        têm nada a ver com o rádio, e um pacote de terceiro de outra classe na lista de exportação
        significaria copiar 120 MB do driver errado.

        'Found' é a informação, e não a decisão: quem decide se o botão do driver básico aparece é
        Test-WinForgeNetworkGuard, pelo fato 'Inbox'.

        LIMITE, e está medido no comentário da região: alimentada com a saída de uma máquina de
        verdade, esta função responde 'Found = $false' SEMPRE, porque o pnputil não lista pacote
        embutido nenhum. Ela responde de verdade quando a lista vem de outra fonte - e a metade que
        importa hoje é 'Oem', que é o que o botão exporta antes de mexer.
    .PARAMETER Entries
        As entradas devolvidas por Get-WinForgeDriverStoreEntry.
    .OUTPUTS
        @{ Found = <bool>; Published = <string>; Oem = @(<string>) }
    #>
    param([Parameter(Mandatory)][object[]]$Entries)

    $rede = @(@($Entries) | Where-Object { $null -ne $_ -and ([string]$_.Class -eq 'Net') })
    $embutidos = @($rede | Where-Object { -not [bool]$_.IsOem })
    $terceiros = @($rede | Where-Object { [bool]$_.IsOem } | ForEach-Object { [string]$_.Published })
    return @{
        Found     = [bool]$embutidos.Count
        Published = $(if ($embutidos.Count) { [string]$embutidos[0].Published } else { '' })
        Oem       = @($terceiros)
    }
}

function Test-WinForgePnputilExit {
    <#
    .SYNOPSIS
        Diz se uma execução do pnputil deu certo. Só o código 0 dá.
    .DESCRIPTION
        Existe como função, e não como comparação solta, por causa de um número: -536870340. Ele é
        NEGATIVO, então '$LASTEXITCODE -gt 0' o trata como sucesso - e o passo seguinte do botão
        seria remover o driver de rede achando que a cópia de segurança tinha sido feita.

        3010 também não passa. Ele significa "deu certo, mas precisa reiniciar", e para esta escada
        isso não é sucesso: a próxima coisa que o botão faria é mexer no driver de uma máquina com
        operação pendente, que é o degrau 'reinício pendente' inteiro sendo pulado por dentro.
    .OUTPUTS
        [bool]
    #>
    param([Parameter(Mandatory)][int]$ExitCode)

    return ($ExitCode -eq 0)
}

function Test-WinForgePnputilProblem {
    <#
    .SYNOPSIS
        Lê a saída de 'pnputil /enum-devices /class Net /problem' e diz se há dispositivo de rede em
        falha, nomeando cada um.
    .DESCRIPTION
        É obrigatório LER a saída, e a medição é a razão: nesta máquina o comando achou o
        'Fortinet SSL VPN Virtual Ethernet Adapter #2' com código de problema 10 e SAIU COM CÓDIGO
        0. Quem confiar no código de saída para saber se há dispositivo quebrado não descobre nada.

        Duas âncoras, as duas por VALOR e não por rótulo:

        - O código do problema vem da linha cujo valor tem a forma '<n> (0x..) [CM_PROB_...]'. O
          'CM_PROB_' é constante do Windows e não é traduzido.
        - O nome vem da linha SEGUINTE à da ID de instância, que se identifica pelo valor
          ('ROOT\NET\0005', 'PCI\VEN_...': letras, barra invertida e o resto).
    .PARAMETER Text
        A saída do comando, já decodificada.
    .OUTPUTS
        @{ Any = <bool>; Devices = @(@{ Name; Problem }) }
    #>
    param([string]$Text)

    $dispositivos = @()
    if ([string]::IsNullOrWhiteSpace($Text)) { return @{ Any = $false; Devices = @() } }

    foreach ($bloco in @($Text -split "(?:\r?\n){2,}")) {
        $linhas = @($bloco -split "\r?\n")
        $codigo = -1
        foreach ($linha in $linhas) {
            if ($linha -match ':\s*(\d+)\s*\(0x[0-9A-Fa-f]+\)\s*\[CM_PROB_') { $codigo = [int]$Matches[1]; break }
        }
        if ($codigo -lt 0) { continue }
        $nome = ''
        for ($k = 0; $k -lt ($linhas.Count - 1); $k++) {
            if ($linhas[$k] -match ':\s*[A-Za-z]+\\\S+\s*$') {
                $seguinte = [string]$linhas[$k + 1]
                if ($seguinte -match ':') { $nome = (($seguinte -split ':', 2)[1]).Trim() }
                break
            }
        }
        $dispositivos += @{ Name = $nome; Problem = $codigo }
    }
    return @{ Any = [bool]@($dispositivos).Count; Devices = @($dispositivos) }
}

function Get-WinForgeWifiDriverBackupRoot {
    <#
    .SYNOPSIS
        A pasta onde as cópias de segurança de driver de rede ficam.
    .DESCRIPTION
        %ProgramData%\WinForge\driver-backup, pela API de pastas e nunca por variável de ambiente -
        a mesma regra do resto do programa.

        NUNCA o %TEMP%, e isto é medição e não gosto: o export de um pacote de driver de rede desta
        família deu 10 arquivos e 120 MB, com um 'WiFi.msi' e um 'Setup.exe' de 17 MB. O %TEMP% é
        apagado por limpeza de disco, pelo próprio Windows e por qualquer faxina que o usuário rode -
        e o que estaria sendo apagado é a única volta depois de remover o driver da placa.
    .OUTPUTS
        Caminho da pasta raiz.
    #>
    param()

    $base = [string][Environment]::GetFolderPath('CommonApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'C:\ProgramData' }
    return (Join-Path (Join-Path $base 'WinForge') 'driver-backup')
}

function Export-WinForgeWifiDriverBackup {
    <#
    .SYNOPSIS
        Copia os pacotes de driver indicados para fora do repositório de drivers, e CONFERE a cópia
        antes de dizer que deu certo.
    .DESCRIPTION
        É a rede de segurança do botão que remove driver: sem ela, "não deu certo" vira "não deu
        certo e agora não há driver".

        O NOME DO PACOTE É CONFERIDO antes de virar argumento. Ele vem de uma leitura de texto, e
        texto lido é dado, não comando: só '^oem<números>.inf$' passa. Um '..\..\algo' ali seria um
        caminho escolhido por quem escreveu a saída, e não por nós, e um nome com um espaço e mais
        alguma coisa atrás seria uma OPÇÃO a mais na linha de comando - inclusive uma das duas que
        esta função existe para nunca passar. Nome fora da forma aborta tudo, sem criar pasta
        nenhuma.

        A chamada não leva a opção que força nem a que reinicia. As duas transformam "não deu, nada
        mudou" em "não deu, e agora não há driver" - e os nomes delas não são citados nesta ajuda de
        propósito, porque a trava que as proíbe lê o corpo do scriptblock, e o bloco de ajuda faz
        parte do corpo.

        QUATRO CONFERÊNCIAS depois do comando, e qualquer uma que falhe aborta sem seguir adiante:

        1. O código de saída, por Test-WinForgePnputilExit (ver a armadilha (a) da região).
        2. Um '.inf' no destino. Sem ele não há o que reinstalar.
        3. Um '.cat' no destino. É o catálogo de assinatura; sem ele o Windows recusa o pacote na
           volta, e a recusa só apareceria na hora do desespero.
        4. O total em bytes, que é o que a tela mostra: um export de 0 byte com código 0 é o pior
           dos casos, porque parece ter dado certo.

        O 'Ok' devolvido é o que o passo que exporta passa adiante como argumento obrigatório da
        asserção de rede. Ninguém herda esse valor de lugar nenhum.
    .PARAMETER Published
        Os nomes publicados dos pacotes ('oem22.inf').
    .PARAMETER Root
        A pasta raiz das cópias. Sem o parâmetro, a de Get-WinForgeWifiDriverBackupRoot.
    .PARAMETER DryRun
        Diz o que faria e para por aí: nada roda, nenhuma pasta é criada.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Path = <string>; Files = <int>; Bytes = <long> }
    #>
    param(
        [Parameter(Mandatory)][string[]]$Published,
        [string]$Root,
        [switch]$DryRun
    )

    $raiz = $(if ([string]::IsNullOrWhiteSpace($Root)) { Get-WinForgeWifiDriverBackupRoot } else { [string]$Root })
    $vazio = @{ Ok = $false; Reason = ''; Path = ''; Files = 0; Bytes = [long]0 }

    $nomes = @(@($Published) | ForEach-Object { [string]$_ })
    if (-not $nomes.Count) { $vazio.Reason = 'Nenhum pacote de driver foi indicado para copiar.'; return $vazio }
    foreach ($nome in $nomes) {
        if ($nome -notmatch '^oem\d+\.inf$') {
            $vazio.Reason = "O nome de pacote '$nome' não tem a forma 'oem<número>.inf' e não vira argumento de comando."
            return $vazio
        }
    }
    if (-not [System.IO.Path]::IsPathRooted($raiz)) { $vazio.Reason = "A pasta de destino '$raiz' não é um caminho absoluto."; return $vazio }

    $carimbo = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $destino = Join-Path $raiz ("{0}-{1}" -f ([string]$nomes[0]).Replace('.inf', ''), $carimbo)

    if ($DryRun) {
        return @{ Ok = $true; Reason = "[simulação] copiaria $($nomes.Count) pacote(s) para '$destino'"; Path = $destino; Files = 0; Bytes = [long]0 }
    }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    New-Item -ItemType Directory -Path $destino -Force -ErrorAction Stop | Out-Null
    foreach ($nome in $nomes) {
        $passo = @{
            FilePath  = (Get-WinForgeSystemExe -Name 'pnputil.exe')
            Arguments = @('/export-driver', $nome, $destino)
            # 'ansi' porque o pnputil escreve CP1252 quando a saída é redirecionada; lida como a
            # code page de console, a mensagem dele chega com o acento embaralhado.
            Encoding  = 'ansi'
        }
        $saida = Invoke-WinForgeNativeCommand -FilePath $passo.FilePath -Arguments $passo.Arguments -Encoding $passo.Encoding
        $codigo = [int]$saida.ExitCode
        if (-not (Test-WinForgePnputilExit -ExitCode $codigo)) {
            return @{ Ok = $false; Reason = "A cópia de '$nome' falhou com o código $codigo. $([string]$saida.Text)"; Path = $destino; Files = 0; Bytes = [long]0 }
        }
    }

    $infs = @(Get-ChildItem -LiteralPath $destino -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)
    $cats = @(Get-ChildItem -LiteralPath $destino -Filter '*.cat' -File -Recurse -ErrorAction SilentlyContinue)
    $todos = @(Get-ChildItem -LiteralPath $destino -File -Recurse -ErrorAction SilentlyContinue)
    $soma = [long](@($todos | Measure-Object -Property Length -Sum).Sum)
    if (-not $infs.Count) { return @{ Ok = $false; Reason = "A cópia terminou sem nenhum arquivo .inf em '$destino': não haveria o que reinstalar."; Path = $destino; Files = @($todos).Count; Bytes = $soma } }
    if (-not $cats.Count) { return @{ Ok = $false; Reason = "A cópia terminou sem nenhum catálogo .cat em '$destino': o Windows recusaria o pacote na volta."; Path = $destino; Files = @($todos).Count; Bytes = $soma } }
    if ($soma -le 0) { return @{ Ok = $false; Reason = "A cópia terminou com 0 byte em '$destino'."; Path = $destino; Files = @($todos).Count; Bytes = $soma } }

    return @{ Ok = $true; Reason = ''; Path = $destino; Files = @($todos).Count; Bytes = [long]$soma }
}

function Get-WinForgeWifiDriverBackupSet {
    <#
    .SYNOPSIS
        Acha a cópia de segurança de driver mais recente, para o botão que restaura saber se tem o
        que restaurar. SÓ LÊ.
    .DESCRIPTION
        Pasta inexistente e pasta vazia são a mesma resposta: 'Found = $false'. O botão que restaura
        usa isso para dizer que não há nada guardado, em vez de tentar e falhar no meio.
    .PARAMETER Root
        A pasta raiz das cópias. Sem o parâmetro, a de Get-WinForgeWifiDriverBackupRoot.
    .OUTPUTS
        @{ Found = <bool>; Path = <string>; Stamp = <string>; Files = <int>; Bytes = <long> }
    #>
    param([string]$Root)

    $raiz = $(if ([string]::IsNullOrWhiteSpace($Root)) { Get-WinForgeWifiDriverBackupRoot } else { [string]$Root })
    $nada = @{ Found = $false; Path = ''; Stamp = ''; Files = 0; Bytes = [long]0 }
    if (-not (Test-Path -LiteralPath $raiz)) { return $nada }

    $conjuntos = @()
    try { $conjuntos = @(Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction Stop | Where-Object { [string]$_.Name -match '-(\d{8}-\d{6})$' }) } catch { return $nada }
    if (-not $conjuntos.Count) { return $nada }

    $novo = @($conjuntos | Sort-Object -Property Name -Descending)[0]
    $carimbo = ''
    if ([string]$novo.Name -match '-(\d{8}-\d{6})$') { $carimbo = [string]$Matches[1] }
    $arquivos = @(Get-ChildItem -LiteralPath $novo.FullName -File -Recurse -ErrorAction SilentlyContinue)
    return @{
        Found = $true
        Path  = [string]$novo.FullName
        Stamp = $carimbo
        Files = @($arquivos).Count
        Bytes = [long](@($arquivos | Measure-Object -Property Length -Sum).Sum)
    }
}
#endregion
