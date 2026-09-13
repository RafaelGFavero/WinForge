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
#    rádio Intel dos sete adaptadores virtuais de VPN (OpenVPN e Fortinet) numa linha.

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

        1. Mídia física fora de '*802.11*'. É o que separa o rádio dos sete adaptadores virtuais de
           VPN (OpenVPN, Fortinet) e da placa de cabo, sem olhar para o nome de ninguém.
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

    if ($PSBoundParameters.ContainsKey('Facts') -and $null -ne $Facts) {
        $f = $Facts
    } else {
        # ------------------------------------------------------------------ levantamento na máquina
        # Os padrões são o LADO SEGURO de cada pergunta: o que não deu para responder bloqueia em
        # vez de liberar. 'ExportOk' é a exceção e nasce $true, porque ele não é uma pergunta sobre
        # a máquina - é o resultado da cópia de segurança que o próprio chamador acabou de tentar,
        # e antes de tentar não há falha nenhuma.
        $f = @{
            Remote = $false; Build = 0; OtherAdapter = $false; Inbox = $false; ExportOk = $true
            OnBattery = $false; Virtual = $false; Server = $false; NeedRestart = $false
            FreeBytes = 0
            # O pacote de driver de rede exportado cabe folgado nisto; é piso, não estimativa fina.
            NeedBytes = 200MB
        }
        try { $f.Remote = [bool](Test-WinForgeRemoteSession) } catch { $f.Remote = $false }
        try { $f.Build = [int][Environment]::OSVersion.Version.Build } catch { $f.Build = 0 }

        if ($Action -ne 'NetDnsRenew') {
            # "É virtual?" é a única pergunta desta lista sem resposta barata e confiável fora do
            # perfil: quem separa um convidado de VMware de uma máquina física com Hyper-V ligado é
            # a assinatura de fabricante/modelo que Get-WinForgeSystemProfile já monta, e uma
            # segunda cópia dessa assinatura aqui só teria como futuro divergir da primeira.
            # Sem perfil, a resposta honesta não é "não é virtual" - é "ainda não sei", e a recusa
            # diz isso. Os botões de driver moram na aba Diagnóstico, que só se pinta depois do
            # perfil; o botão 3 não depende de nada disto e segue em frente.
            #
            # Esta porta é do LEVANTAMENTO, e não um degrau da escada: ela responde ANTES porque sem
            # perfil não há fato para a escada ler. Consequência assumida: numa sessão remota com o
            # diagnóstico pela metade o usuário lê esta frase em vez da do degrau 1. As duas
            # recusam, e esta ainda manda esperar - o que também é verdade.
            $perfil = $null
            try { $perfil = $sync.Profile } catch { $perfil = $null }
            if ($null -eq $perfil -or $null -eq $perfil.Machine -or $null -eq $perfil.OS -or $null -eq $perfil.Power) {
                $aindaNao = 'O diagnóstico desta aba ainda não terminou. Espere o cartão do computador aparecer e tente de novo: sem ele não dá para saber se esta máquina é virtual ou um Windows Server, e é aí que mexer no driver de rede sai caro.'
                return @{ Ok = $false; Hidden = $false; Reason = $aindaNao; Blocks = @($aindaNao) }
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

            # A lista de adaptadores é consultada UMA vez e reaproveitada pelos dois fatos que
            # dependem dela: Get-NetAdapter custa perto de 200 ms, e isto roda ao pintar a aba.
            #
            # "Outra via" é outro caminho para a internet enquanto o rádio está sem driver: cabo,
            # celular por USB, outro dongle. O próprio rádio não conta, e os virtuais também não -
            # VPN, Wi-Fi Direct e comutador de máquina virtual andam EM CIMA de um adaptador de
            # verdade e caem junto com ele. Nesta máquina são sete deles, e sem esse descarte a
            # resposta seria "tem outra via" com o cabo desligado.
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

            # O driver básico só é condição do botão que troca por ele; para os outros a pergunta
            # não existe, e nem a varredura de INF nem a consulta de IDs de hardware são pagas.
            if ($Action -eq 'WifiDriverGeneric') {
                $idRadio = ''
                if ($radio.Ok) {
                    $objRadio = @($adaptadores | Where-Object { [int]$_.ifIndex -eq [int]$radio.ifIndex })
                    if ($objRadio.Count) { $idRadio = [string]$objRadio[0].PnPDeviceID }
                }
                $f.Inbox = (-not [string]::IsNullOrWhiteSpace($idRadio)) -and (Test-WinForgeInboxWifiDriver -PnpDeviceId $idRadio)
            }
        }
    }

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

    $blocos = New-Object System.Collections.Generic.List[string]
    $motivo = ''
    $escondido = $false
    foreach ($degrau in $escada) {
        if (-not $degrau.Vale) { continue }
        if ($Action -in @($degrau.Absolutas)) {
            $blocos.Add([string]$degrau.Texto)
            $motivo = [string]$degrau.Texto
            $escondido = [bool]$degrau.Esconde
            break
        }
        if ($Action -in @($degrau.Avisos)) {
            $blocos.Add([string]$(if ($degrau.ContainsKey('TextoAviso')) { $degrau.TextoAviso } else { $degrau.Texto }))
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

        LIMITE CONHECIDO: 'net*.inf' é convenção, não regra do sistema. Um INF de rede da Microsoft
        com outro nome seria lido como ausente e o botão sumiria numa máquina em que ele
        funcionaria - erro para o lado de não estragar nada.
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
            $texto = $null
            try { $texto = [System.IO.File]::ReadAllText($arquivo.FullName) } catch { continue }
            foreach ($id in $ids) {
                if ($texto.IndexOf([string]$id, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
            }
        }
        return $false
    } catch {
        return $false
    }
}
#endregion
