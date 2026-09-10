#region ===== WinForge - servidor (IIS/AD) =====
# Ações dos botões da aba Servidor, a visibilidade das abas que dependem do tipo de Windows e o
# ajuste do IIS (pools, sites e configuração do servidor) com backup dos valores anteriores.
# Os botões de comando (w32tm, Defender, TCP, dcdiag, repadmin, DNS, NTDS) só LEEM: rodam a
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
# única coisa que a interface conhece: o QUE roda mora na tabela de Get-WinForgeServerCommand e o
# COMO roda mora na máquina genérica de comandos (wf-commands.ps1) - núcleo síncrono
# Invoke-WinForgeCommandCore, despacho Invoke-WinForgeCommandButton e a janela de saída montada em
# código, sem XAML. Daqui saem só a tabela e dois invólucros que amarram 'Server'/'server' a ela.
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

        'Native' separa o que é EXECUTÁVEL do que é pipeline de cmdlet, e manda em duas coisas:
        só o executável passa pela troca de code page (w32tm, dcdiag e repadmin escrevem em OEM) e
        só ele tem código de saída. Num pipeline de cmdlet, $LASTEXITCODE é o valor que a função
        acabou de zerar, e imprimir "Código de saída: 0" para um Get-MpPreference seria inventar um
        código que nunca existiu.
    .OUTPUTS
        Hashtable com Title, Command (texto do comando), Requires (ou $null) e Native.
    #>
    param([Parameter(Mandatory)][string]$Name)

    switch ($Name) {
        'TimeCheck' {
            # Caminho completo, e não 'w32tm': o WinForge roda elevado e o PATH escolhe o binário.
            # Get-WinForgeSystemExe monta %SystemRoot%\System32\<exe> uma vez, e o texto do comando
            # chama pelo operador & com o caminho entre aspas simples.
            $w32tm = Get-WinForgeSystemExe -Name 'w32tm.exe'
            return @{
                Title    = 'Fonte de horário (w32tm)'
                Command  = "& '$w32tm' /query /status; & '$w32tm' /query /source; & '$w32tm' /query /configuration"
                Requires = $w32tm
                Native   = $true
            }
        }
        'DefenderExclusions' {
            return @{
                Title    = 'Exclusões do Microsoft Defender'
                Command  = 'Get-MpPreference | Select-Object ExclusionPath, ExclusionProcess, ExclusionExtension | Format-List'
                Requires = 'Get-MpPreference'
                Native   = $false
            }
        }
        'TcpShow' {
            # Cmdlet, e não 'netsh int tcp show global': o netsh escreve UTF-8 quando a saída é um
            # cano (e OEM quando é console), então o texto do botão chegava embaralhado justamente no
            # processo sem janela que o lançador usa. Get-NetTCPSetting existe desde o Server 2012,
            # devolve objeto e não depende de idioma.
            return @{
                Title    = 'Parâmetros TCP'
                Command  = 'Get-NetTCPSetting -SettingName Internet | Format-List *; Get-NetOffloadGlobalSetting | Format-List *'
                Requires = 'Get-NetTCPSetting'
                Native   = $false
            }
        }
        'Dcdiag' {
            $dcdiag = Get-WinForgeSystemExe -Name 'dcdiag.exe'
            return @{
                Title    = 'Diagnóstico do controlador de domínio (dcdiag /q)'
                Command  = "& '$dcdiag' /q"
                Requires = $dcdiag
                Native   = $true
            }
        }
        'ReplSummary' {
            $repadmin = Get-WinForgeSystemExe -Name 'repadmin.exe'
            return @{
                Title    = 'Resumo de replicação (repadmin /replsummary)'
                Command  = "& '$repadmin' /replsummary"
                Requires = $repadmin
                Native   = $true
            }
        }
        'DnsScavenging' {
            return @{
                Title    = 'Limpeza de registros DNS (scavenging)'
                Command  = 'Get-DnsServerScavenging | Format-List'
                Requires = 'Get-DnsServerScavenging'
                Native   = $false
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
                Native   = $false
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

function Invoke-WinForgeServerCommandCore {
    <#
    .SYNOPSIS
        Invólucro da aba Servidor sobre o núcleo genérico: resolve o nome curto na tabela e roda.
    .DESCRIPTION
        Existe para o resto do programa (e o -SelfTest) continuar falando por nome curto. Todo o
        comportamento - ferramenta ausente virando texto, linha de código de saída só para comando
        executável, arquivo gravado em server-<Nome>-<aaaaMMdd-HHmmss>.txt na pasta de logs - mora em
        Invoke-WinForgeCommandCore, e é o mesmo do reparo de componentes.
    .OUTPUTS
        Hashtable com Name, Title, Text, Path e ExitCode.
    #>
    param([Parameter(Mandatory)][string]$Name)

    return Invoke-WinForgeCommandCore -Spec (Get-WinForgeServerCommand -Name $Name) -Name $Name -Component 'Server' -Prefix 'server'
}

function Invoke-WinForgeServerCommand {
    <#
    .SYNOPSIS
        Ação dos botões da aba Servidor: resolve o nome curto na tabela e despacha o comando.
    .DESCRIPTION
        Nome desconhecido morre AQUI, no clique, e não dentro do runspace: a tabela é desta aba, e uma
        caixa de mensagem dizendo qual botão está errado vale mais do que uma linha de log que
        ninguém vai ler. O resto - trava de um comando por vez, runspace do pool, janela de saída
        aberta pela thread da interface - é de Invoke-WinForgeCommandButton.
    #>
    param([Parameter(Mandatory)][string]$Name)

    try {
        $cmd = Get-WinForgeServerCommand -Name $Name
    } catch {
        Write-WinForgeLog -Component "Server" -Level "ERROR" -Message $_.Exception.Message
        [System.Windows.MessageBox]::Show($_.Exception.Message, "WinForge", "OK", "Error") | Out-Null
        return
    }

    Invoke-WinForgeCommandButton -Spec $cmd -Name $Name -Component 'Server' -Prefix 'server'
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
#    seguidas com backup dos dois lados gravaria um segundo arquivo já com os valores ajustados.
#    O Desfazer JUNTA todos os backups vivos do item e, para cada chave, fica com o valor mais
#    antigo - o de antes do WinForge - e depois arquiva os arquivos consumidos como
#    '<nome>.restored.json', para que uma aplicação seguinte comece de um backup limpo.
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

function Get-WinForgeSnapshotRoot {
    <#
    .SYNOPSIS
        Pasta dos backups (IIS e ajustes de servidor). -Root existe para o -SelfTest não escrever em
        %ProgramData%.
    .DESCRIPTION
        O caminho é normalizado UMA vez ([System.IO.Path]::GetFullPath): daqui para baixo todo mundo
        conta com a mesma forma - sem '..', sem barra dupla, sem caminho relativo -, e é essa forma
        que a checagem da cadeia de pastas confere.
    #>
    param([string]$Root)

    $alvo = if ($Root) { $Root } else { (Join-Path $env:ProgramData 'WinForge\iis-backup') }
    try { return [System.IO.Path]::GetFullPath($alvo) } catch { return $alvo }
}

function Get-WinForgeSnapshotTrustedSid {
    <#
    .SYNOPSIS
        Os SIDs em que a pasta de backup pode confiar. São DUAS listas, e a diferença entre elas é o
        que fecha o furo do UAC.
    .DESCRIPTION
        DONO (-Owner): só SYSTEM (S-1-5-18) e BUILTIN\Administradores (S-1-5-32-544). O dono guarda
        WRITE_DAC implícito - pode devolver a si mesmo a permissão de escrita a qualquer momento -,
        então dono é escrita. Aceitar a identidade atual como dona da pasta PADRÃO
        (%ProgramData%\WinForge\iis-backup) reabriria o ataque: um processo de integridade MÉDIA da
        MESMA conta de administrador cria a pasta antes da primeira execução, vira dono dela, escreve
        uma DACL bonita (SYSTEM, Administradores e ele mesmo) e passa em todas as checagens - e o
        Desfazer elevado depois aplica o JSON que ele plantou. Medium -> High é exatamente a fronteira
        que o UAC existe para separar.

        Por isso a identidade atual só entra quando quem chamou passou um -Root explícito
        (-ExplicitRoot): aí o caminho não é o da máquina, é o do -SelfTest numa pasta em %TEMP%.

        PERMISSÃO (padrão): as mesmas duas, mais CREATOR OWNER e OWNER RIGHTS, que são ACEs de molde
        (só valem para quem vier a criar objeto lá dentro, e criar exige escrita, que ninguém de fora
        das duas tem).
    .PARAMETER Owner
        Devolve a lista de DONO (mais curta), e não a de permissão.
    .PARAMETER ExplicitRoot
        Quem chamou passou -Root: a identidade atual entra nas duas listas.
    .OUTPUTS
        Hashtable com os SIDs (texto) como chave.
    #>
    param(
        [switch]$Owner,
        [switch]$ExplicitRoot
    )

    $tipos = @('LocalSystemSid', 'BuiltinAdministratorsSid')
    if (-not $Owner) { $tipos += 'CreatorOwnerSid' }
    $sids = @{}
    foreach ($tipo in $tipos) {
        try {
            $sid = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::$tipo), $null
            $sids[$sid.Value] = $true
        } catch { }
    }
    # S-1-3-4 (OWNER RIGHTS) não tem WellKnownSidType em todas as versões do .NET Framework.
    if (-not $Owner) { $sids['S-1-3-4'] = $true }
    if ($ExplicitRoot) {
        try { $sids[([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)] = $true } catch { }
    }
    return $sids
}

function Test-WinForgeSnapshotRootPath {
    <#
    .SYNOPSIS
        Confere a CADEIA de pastas até a raiz de backup: nenhuma delas pode ser ponto de reanálise.
    .DESCRIPTION
        Conferir só a última pasta deixava passar o desvio mais barato de todos. %ProgramData% deixa
        qualquer usuário criar subpasta, e criar subpasta inclui criar JUNÇÃO: com
        '%ProgramData%\WinForge' apontando para uma pasta do usuário, '%ProgramData%\WinForge\iis-backup'
        nasce - e é conferida - lá do outro lado, com a DACL de lá, e nenhum atributo de reanálise
        aparece na última pasta.

        Então o caminho é normalizado uma vez e cada ancestral EXISTENTE é conferido, da pasta final
        até a raiz do volume. Ancestral que não existe não é problema: quem o criar será o WinForge,
        com a DACL de New-WinForgeSnapshotRoot.
    .OUTPUTS
        @{ Trusted = <bool>; Reason = <string>; Path = <caminho normalizado> }.
    #>
    param([Parameter(Mandatory)][string]$Root)

    $full = $Root
    try { $full = [System.IO.Path]::GetFullPath($Root) }
    catch { return @{ Trusted = $false; Reason = "'$Root' não é um caminho válido: $($_.Exception.Message)"; Path = $Root } }

    $atual = $full
    while ($atual) {
        $item = $null
        try { $item = Get-Item -LiteralPath $atual -Force -ErrorAction Stop } catch { $item = $null }
        if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            return @{ Trusted = $false; Reason = "'$atual' é um ponto de reanálise (junção ou link)"; Path = $full }
        }
        $pai = $null
        try { $pai = Split-Path -Parent $atual } catch { $pai = $null }
        if ([string]::IsNullOrWhiteSpace($pai) -or $pai -eq $atual) { break }
        $atual = $pai
    }
    return @{ Trusted = $true; Reason = ''; Path = $full }
}

function Find-WinForgeSnapshotUnsafeAce {
    <#
    .SYNOPSIS
        Devolve o nome do primeiro SID de fora da lista que tem escrita numa DACL - de pasta OU de
        arquivo.
    .DESCRIPTION
        A regra é a mesma nos dois lugares, e estar escrita só na pasta era metade da tranca: um
        arquivo de backup com uma ACE de escrita para 'Todos' passava, porque a checagem do arquivo
        olhava só o dono. Escrita, modificação, controle total, exclusão, troca de DACL e troca de
        dono contam todas como escrita - quem pode reescrever a DACL pode devolver a si mesmo o
        resto.

        0x40000000 (GENERIC_WRITE) e 0x10000000 (GENERIC_ALL) não têm nome em FileSystemRights e
        aparecem crus numa ACE gravada por uma API antiga: sem eles, uma ACE de escrita genérica
        passaria batida.
    .OUTPUTS
        O nome (ou o SID) de quem tem escrita indevida, ou $null se a DACL está limpa.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Access,
        [Parameter(Mandatory)][hashtable]$Trusted
    )

    $perigo = [int][System.Security.AccessControl.FileSystemRights]::Write -bor
              [int][System.Security.AccessControl.FileSystemRights]::Modify -bor
              [int][System.Security.AccessControl.FileSystemRights]::FullControl -bor
              [int][System.Security.AccessControl.FileSystemRights]::Delete -bor
              [int][System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
              [int][System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
              [int][System.Security.AccessControl.FileSystemRights]::TakeOwnership -bor
              0x40000000 -bor 0x10000000
    foreach ($ace in $Access) {
        if ($ace.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        if (-not ([int]$ace.FileSystemRights -band [int]$perigo)) { continue }
        $sid = $ace.IdentityReference
        try { if ($sid -isnot [System.Security.Principal.SecurityIdentifier]) { $sid = $sid.Translate([System.Security.Principal.SecurityIdentifier]) } } catch { continue }
        if ($Trusted.ContainsKey($sid.Value)) { continue }
        $nome = $sid.Value
        try { $nome = $sid.Translate([System.Security.Principal.NTAccount]).Value } catch { }
        return $nome
    }
    return $null
}

function Test-WinForgeSnapshotRootTrusted {
    <#
    .SYNOPSIS
        Diz se a pasta de backup pode ser lida com segurança antes de um Desfazer.
    .DESCRIPTION
        O Desfazer roda elevado e reescreve o que o arquivo mandar. Três coisas desqualificam a pasta:

        1. Ter um ponto de reanálise (junção/link) em QUALQUER pasta do caminho, e não só na última:
           o caminho conferido não seria o caminho lido (ver Test-WinForgeSnapshotRootPath).
        2. Ter como dono alguém fora da lista de DONO - que na pasta padrão é SYSTEM e
           Administradores, e só isso. Dono guarda WRITE_DAC implícito e pode devolver a si mesmo a
           permissão de escrita a qualquer momento, então dono é escrita.
        3. Ter uma ACE de permissão que dê escrita, modificação ou controle total a um SID fora da
           lista de permissão.

        Pasta inexistente é confiável: não há nada para ler, e quem a criar será o próprio WinForge,
        com a DACL de New-WinForgeSnapshotRoot.
    .PARAMETER ExplicitRoot
        Quem chamou passou um -Root próprio (na prática, o -SelfTest com uma pasta em %TEMP%): a
        identidade atual pode ser dona. SEM esta chave valem as regras da pasta padrão
        (%ProgramData%\WinForge\iis-backup), onde dono fora de SYSTEM/Administradores é recusa - é o
        que impede um processo de integridade média da mesma conta de plantar a pasta antes da
        primeira execução.
    .OUTPUTS
        @{ Trusted = <bool>; Reason = <string> }.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$ExplicitRoot
    )

    # A cadeia de pastas é conferida ANTES de a pasta existir: a junção que desvia o backup mora num
    # ancestral, e ela pode estar lá antes da primeira execução.
    $caminho = Test-WinForgeSnapshotRootPath -Root $Root
    if (-not $caminho.Trusted) { return @{ Trusted = $false; Reason = $caminho.Reason } }
    $Root = $caminho.Path
    if (-not (Test-Path -LiteralPath $Root)) { return @{ Trusted = $true; Reason = '' } }
    try {
        $acl = Get-Acl -LiteralPath $Root -ErrorAction Stop
        $confiaveis = Get-WinForgeSnapshotTrustedSid -ExplicitRoot:$ExplicitRoot
        $donos = Get-WinForgeSnapshotTrustedSid -Owner -ExplicitRoot:$ExplicitRoot
        $dono = $null
        try { $dono = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]) } catch { }
        if ($null -eq $dono) { return @{ Trusted = $false; Reason = "não foi possível ler o dono de '$Root'" } }
        if (-not $donos.ContainsKey($dono.Value)) {
            $nome = $dono.Value
            try { $nome = $dono.Translate([System.Security.Principal.NTAccount]).Value } catch { }
            return @{ Trusted = $false; Reason = "'$Root' pertence a '$nome', fora de SYSTEM/Administradores" }
        }
        $mau = Find-WinForgeSnapshotUnsafeAce -Access @($acl.Access) -Trusted $confiaveis
        if ($mau) { return @{ Trusted = $false; Reason = "'$mau' tem permissão de escrita em '$Root'" } }
        return @{ Trusted = $true; Reason = '' }
    } catch {
        return @{ Trusted = $false; Reason = "não foi possível conferir '$Root': $($_.Exception.Message)" }
    }
}

function Test-WinForgeSnapshotFileTrusted {
    <#
    .SYNOPSIS
        Confere o arquivo de backup em si, antes de ele ser lido: dono, DACL e ponto de reanálise.
    .DESCRIPTION
        A pasta protegida já impede que alguém de fora escreva lá dentro. Esta checagem é a segunda
        tranca, para o caso de a pasta ter sido protegida DEPOIS de um arquivo estranho já estar lá
        (ou de um link apontando para fora). Um link é recusado porque o arquivo lido não seria o
        arquivo conferido.

        A regra de dono é a MESMA da pasta, e quem decide é quem chamou - não o código daqui. Esta
        chave já esteve fixa em -ExplicitRoot, e isso valia dizer "na pasta padrão o dono pode ser a
        conta atual": como dono guarda WRITE_DAC implícito, um processo de integridade MÉDIA da mesma
        conta de administrador podia reescrever a DACL do arquivo pelo caminho completo (a DACL da
        pasta não é conferida na abertura de um arquivo cujo caminho já se conhece) e plantar valores
        que o Desfazer elevado aplicaria. Na pasta padrão o dono tem de ser SYSTEM ou Administradores
        - e é New-WinForgeSnapshot que entrega o arquivo recém-gravado ao grupo Administradores, para
        que o backup bom continue passando.

        A DACL do arquivo é conferida com a MESMA regra da pasta (Find-WinForgeSnapshotUnsafeAce):
        olhar só o dono deixava passar o arquivo que já estava lá com uma ACE de escrita para
        'Todos' - o dono podia ser SYSTEM e qualquer um reescrever o conteúdo assim mesmo.
    .PARAMETER ExplicitRoot
        Quem chamou passou um -Root próprio (na prática, o -SelfTest em %TEMP%): a identidade atual
        pode ser dona do arquivo.
    .OUTPUTS
        @{ Trusted = <bool>; Reason = <string> }.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$ExplicitRoot
    )

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            return @{ Trusted = $false; Reason = "é um ponto de reanálise (link)" }
        }
        $donos = Get-WinForgeSnapshotTrustedSid -Owner -ExplicitRoot:$ExplicitRoot
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $dono = $null
        try { $dono = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]) } catch { }
        if ($null -eq $dono) { return @{ Trusted = $false; Reason = "o dono não pôde ser lido" } }
        if (-not $donos.ContainsKey($dono.Value)) {
            $nome = $dono.Value
            try { $nome = $dono.Translate([System.Security.Principal.NTAccount]).Value } catch { }
            return @{ Trusted = $false; Reason = "pertence a '$nome', fora de SYSTEM/Administradores" }
        }
        $mau = Find-WinForgeSnapshotUnsafeAce -Access @($acl.Access) -Trusted (Get-WinForgeSnapshotTrustedSid -ExplicitRoot:$ExplicitRoot)
        if ($mau) { return @{ Trusted = $false; Reason = "'$mau' tem permissão de escrita no arquivo" } }
        return @{ Trusted = $true; Reason = '' }
    } catch {
        return @{ Trusted = $false; Reason = $_.Exception.Message }
    }
}

function New-WinForgeSnapshotRoot {
    <#
    .SYNOPSIS
        Cria a pasta de backup com uma DACL própria: sem herança, SYSTEM e Administradores com
        controle total, dono Administradores.
    .DESCRIPTION
        %ProgramData% deixa qualquer usuário criar subpasta, e quem cria é dono. Uma pasta de backup
        criada por herança nasceria com CREATOR OWNER dando controle total ao usuário sobre os
        arquivos dele - ou seja, um JSON plantado que o Desfazer aplicaria como administrador. Por
        isso a pasta nasce com a DACL escrita à mão, sem herdar nada.

        Sem elevação não dá para atribuir o grupo Administradores como dono (o Windows recusa). Nesse
        caminho - que na prática é só o -SelfTest, que usa uma pasta em %TEMP% - a pasta nasce com a
        mesma DACL protegida mais uma ACE para a identidade atual, e fica registrado no log.
    .OUTPUTS
        $true se a pasta existe ao final.
    #>
    param([Parameter(Mandatory)][string]$Root)

    if (Test-Path -LiteralPath $Root) { return $true }
    $pai = Split-Path -Parent $Root
    if ($pai -and -not (Test-Path -LiteralPath $pai)) { New-Item -ItemType Directory -Path $pai -Force | Out-Null }

    $novaDacl = {
        $s = New-Object System.Security.AccessControl.DirectorySecurity
        $s.SetAccessRuleProtection($true, $false)
        foreach ($tipo in @('LocalSystemSid', 'BuiltinAdministratorsSid')) {
            $sid = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::$tipo), $null
            $s.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        }
        # OWNER RIGHTS (S-1-3-4) herdável, só leitura: sem esta ACE, o DONO de um arquivo criado aqui
        # dentro guarda WRITE_DAC implícito e pode devolver a si mesmo a escrita. Com ela, o Windows
        # troca os direitos implícitos do dono por estes - e um processo de integridade média da mesma
        # conta deixa de conseguir reescrever a DACL do backup pelo caminho completo.
        $s.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-3-4'), 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        return $s
    }

    try {
        $sec = & $novaDacl
        $sec.SetOwner((New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid), $null))
        [System.IO.Directory]::CreateDirectory($Root, $sec) | Out-Null
        Write-WinForgeLog -Component "IIS" -Message "Pasta de backup criada com DACL protegida (SYSTEM e Administradores): $Root"
        return $true
    } catch {
        try {
            $sec = & $novaDacl
            $eu = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $sec.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $eu, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            [System.IO.Directory]::CreateDirectory($Root, $sec) | Out-Null
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Pasta de backup criada sem elevação: $Root (dono é a identidade atual, DACL protegida)."
            return $true
        } catch {
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Pasta de backup criada com as permissões herdadas: $Root -> $($_.Exception.Message)"
            return (Test-Path -LiteralPath $Root)
        }
    }
}

function Repair-WinForgeSnapshotRootOwnerRight {
    <#
    .SYNOPSIS
        Garante a ACE herdável de OWNER RIGHTS (S-1-3-4, só leitura) na pasta de backup que JÁ existe.
    .DESCRIPTION
        A ACE só era escrita na CRIAÇÃO da pasta. Numa pasta que já existia sem ela - a criada por
        uma versão anterior do WinForge, ou por qualquer outro caminho - o dono do arquivo
        recém-gravado continuava com o WRITE_DAC implícito: entre o New-WinForgeSnapshot e o
        Protect-WinForgeSnapshotFile havia uma janela em que um processo de integridade média da
        mesma conta reescrevia a DACL do backup pelo caminho completo e plantava valores que o
        Desfazer elevado aplicaria. Com a ACE herdável, o Windows troca os direitos implícitos do
        dono por estes - e a janela fecha.

        A ACE existente só conta se for herdável (pasta E arquivo) e trouxer os direitos de leitura:
        uma ACE de OWNER RIGHTS só na própria pasta não protege os arquivos de dentro.
    .OUTPUTS
        @{ Ok = <bool>; Added = <bool>; Reason = <string> }.
    #>
    param([Parameter(Mandatory)][string]$Root)

    $rx = [int][System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    $heranca = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
               [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $tem = {
        param($acl)
        foreach ($ace in $acl.Access) {
            if ($ace.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
            $sid = $ace.IdentityReference
            try { if ($sid -isnot [System.Security.Principal.SecurityIdentifier]) { $sid = $sid.Translate([System.Security.Principal.SecurityIdentifier]) } } catch { continue }
            if ($sid.Value -ne 'S-1-3-4') { continue }
            if (([int]$ace.FileSystemRights -band $rx) -ne $rx) { continue }
            if (([int]$ace.InheritanceFlags -band [int]$heranca) -ne [int]$heranca) { continue }
            return $true
        }
        return $false
    }

    try {
        # Só a seção DACL, e por DirectoryInfo: Get-Acl/Set-Acl carregam também a seção de AUDITORIA,
        # e gravar SACL exige SeSecurityPrivilege - privilégio que o WinForge não tem e não precisa.
        $pasta = New-Object System.IO.DirectoryInfo $Root
        $secao = [System.Security.AccessControl.AccessControlSections]::Access
        $acl = $pasta.GetAccessControl($secao)
        if (& $tem $acl) { return @{ Ok = $true; Added = $false; Reason = '' } }
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-3-4'), 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        $pasta.SetAccessControl($acl)
        # Relido do disco: a gravação pode ser aceita e a ACE não ficar (filtro de driver, volume sem
        # ACL). Quem confia é o disco, não a cópia em memória.
        if (-not (& $tem ((New-Object System.IO.DirectoryInfo $Root).GetAccessControl($secao)))) {
            return @{ Ok = $false; Added = $false; Reason = 'a ACE de OWNER RIGHTS não ficou gravada' }
        }
        return @{ Ok = $true; Added = $true; Reason = '' }
    } catch {
        return @{ Ok = $false; Added = $false; Reason = $_.Exception.Message }
    }
}

function Confirm-WinForgeSnapshotRoot {
    <#
    .SYNOPSIS
        Garante que a pasta de backup existe E é confiável, ANTES de qualquer alteração.
    .DESCRIPTION
        New-WinForgeSnapshotRoot só sabia criar: numa pasta que já existia ele devolvia $true sem
        olhar para ela, e a aplicação gravava o backup ali mesmo - inclusive numa pasta plantada por
        outra conta. Aplicar assim é o pior dos mundos: o servidor muda e o "Desfazer" passa a ser um
        arquivo que outra pessoa escreve.

        Então a ordem é esta: não existe -> cria com a DACL protegida; existe -> confere; não passou
        -> quem chamou RECUSA a aplicação inteira, sem alterar nada.

        Passar na conferência ainda não basta: a pasta que já existia pode estar sem a ACE herdável
        de OWNER RIGHTS (ver Repair-WinForgeSnapshotRootOwnerRight), e sem ela o dono do backup
        recém-gravado guarda WRITE_DAC até o Protect. A ACE é acrescentada aqui, antes de qualquer
        gravação; se não der para acrescentar, a pasta vale como NÃO confiável.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Path = <pasta> }.
    #>
    param([string]$Root)

    $dir = Get-WinForgeSnapshotRoot $Root
    $explicito = -not [string]::IsNullOrWhiteSpace($Root)
    if (-not (Test-Path -LiteralPath $dir)) { New-WinForgeSnapshotRoot -Root $dir | Out-Null }
    $t = Test-WinForgeSnapshotRootTrusted -Root $dir -ExplicitRoot:$explicito
    if (-not $t.Trusted) { return @{ Ok = $false; Reason = $t.Reason; Path = $dir } }
    $dono = Repair-WinForgeSnapshotRootOwnerRight -Root $dir
    if (-not $dono.Ok) {
        return @{ Ok = $false; Reason = "pasta de backup sem proteção de dono ('$dir'): $($dono.Reason)"; Path = $dir }
    }
    if ($dono.Added) {
        if ($null -eq $script:WinForgeSnapshotOwnerRightLogged) { $script:WinForgeSnapshotOwnerRightLogged = @{} }
        if (-not $script:WinForgeSnapshotOwnerRightLogged.ContainsKey($dir)) {
            $script:WinForgeSnapshotOwnerRightLogged[$dir] = $true
            try { Write-WinForgeLog -Component "IIS" -Message "Pasta de backup existente recebeu a ACE de OWNER RIGHTS (só leitura): $dir" } catch { }
        }
    }
    return @{ Ok = $true; Reason = ''; Path = $dir }
}

function Protect-WinForgeSnapshotFile {
    <#
    .SYNOPSIS
        Entrega o backup recém-gravado ao grupo Administradores e fecha a DACL dele em SYSTEM +
        Administradores.
    .DESCRIPTION
        O Windows dá ao CRIADOR a propriedade do arquivo (a política "dono padrão dos objetos criados
        por administradores" vem como "criador do objeto" desde o XP), então um backup gravado elevado
        nasce pertencendo à CONTA do administrador, não ao grupo. Dono guarda WRITE_DAC implícito: um
        processo de integridade MÉDIA da mesma conta abre o arquivo pelo caminho completo, reescreve a
        DACL e planta valores que o Desfazer elevado aplica. Trocar o dono para
        BUILTIN\Administradores (S-1-5-32-544) tira esse poder do processo médio, que tem o grupo como
        SID de negação.

        O dono vai PRIMEIRO e sozinho: sem elevação ele é recusado, e aí a DACL fechada também não é
        escrita - fechá-la sem poder trocar o dono só trancaria o próprio WinForge para fora do
        arquivo que ele acabou de gravar.
    .OUTPUTS
        @{ Hardened = <bool>; Reason = <string> }.
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        $system = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::LocalSystemSid), $null
        $admin = New-Object System.Security.Principal.SecurityIdentifier ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid), $null
        $arquivo = New-Object System.IO.FileInfo $Path

        $sd = New-Object System.Security.AccessControl.FileSecurity
        $sd.SetOwner($admin)
        $arquivo.SetAccessControl($sd)   # só a seção de dono: o objeto novo só tem ela modificada

        $dacl = New-Object System.Security.AccessControl.FileSecurity
        $dacl.SetAccessRuleProtection($true, $false)
        foreach ($sid in @($system, $admin)) {
            $dacl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $sid, 'FullControl', 'Allow'))
        }
        $arquivo.SetAccessControl($dacl)
        return @{ Hardened = $true; Reason = '' }
    } catch {
        return @{ Hardened = $false; Reason = $_.Exception.Message }
    }
}

function New-WinForgeSnapshot {
    <#
    .SYNOPSIS
        Grava os valores anteriores de um item num JSON com data e hora no nome.
    .DESCRIPTION
        O nome carrega os milissegundos ('-fff'): com precisão de segundo, dois backups do mesmo item
        no mesmo segundo cairiam no MESMO arquivo e o primeiro - o que tem os valores originais -
        seria sobrescrito. Milissegundo mantém a ordenação por nome (o campo é de largura fixa).

        O prefixo é o -Name: 'AlwaysRunning' para os itens de IIS, 'setting-Smb1Off' para os ajustes
        de servidor. Um prefixo, uma pasta, as mesmas regras de proteção e de leitura.

        Gravado o arquivo, ele é ENDURECIDO (Protect-WinForgeSnapshotFile): dono Administradores e
        DACL fechada. Na pasta PADRÃO isso não é opcional - um backup que não pôde ser protegido é um
        arquivo que a própria conta pode reescrever de um processo não elevado, então ele é APAGADO e
        a função devolve $null, e quem chamou recusa a aplicação inteira sem alterar nada. Com -Root
        próprio (o -SelfTest em %TEMP%, ou uma execução sem elevação) fica só uma linha de WARN, uma
        vez por sessão.
    .OUTPUTS
        Caminho do arquivo gravado, ou $null se o backup da pasta padrão não pôde ser protegido.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Values,
        [string]$Root
    )

    $dir = Get-WinForgeSnapshotRoot $Root
    $explicito = -not [string]::IsNullOrWhiteSpace($Root)
    New-WinForgeSnapshotRoot -Root $dir | Out-Null
    $path = Join-Path $dir ("{0}-{1}.json" -f $Name, (Get-Date).ToString('yyyyMMdd-HHmmss-fff'))
    @{ Name = $Name; Date = (Get-Date).ToString('s'); Values = $Values } | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8

    $prot = Protect-WinForgeSnapshotFile -Path $path
    if (-not $prot.Hardened) {
        if (-not $explicito) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message "não foi possível proteger o backup de $Name ($($prot.Reason)); o arquivo foi apagado."
            return $null
        }
        if (-not $script:WinForgeSnapshotHardenWarned) {
            $script:WinForgeSnapshotHardenWarned = $true
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Backup gravado sem endurecer dono e DACL (pasta de backup própria, sem elevação): $($prot.Reason)"
        }
    }
    Write-WinForgeLog -Component "IIS" -Message "Valores anteriores de $Name guardados em $path ($($Values.Count) item(ns))."
    return $path
}

function Get-WinForgeSnapshotFile {
    <#
    .SYNOPSIS
        Os arquivos de backup vivos de um item, do mais antigo para o mais novo.
    .DESCRIPTION
        Ordenado por NOME e não pela data do sistema de arquivos, que uma cópia de pasta reescreve -
        o nome carrega '<aaaaMMdd-HHmmss-fff>', campo de largura fixa. Os arquivos já consumidos por
        um Desfazer terminam em '.restored.json' e ficam de fora: eles são histórico, não estado.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Root
    )

    $dir = Get-WinForgeSnapshotRoot $Root
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Filter "$Name-*.json" -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike '*.restored.json' } |
             Sort-Object Name)
}

function Get-WinForgeSnapshot {
    <#
    .SYNOPSIS
        Junta TODOS os backups vivos de um item e devolve o estado anterior à primeira aplicação.
    .DESCRIPTION
        Três decisões, todas nascidas de estragos reais:

        1. O MAIS ANTIGO vence. Aplicar 'AlwaysRunning' com os pools A, B e C grava o backup 1; o
           administrador cria o pool D, aplica de novo e o backup 2 tem só D (os outros já estavam no
           alvo). Desfazer lendo só o mais novo devolveria D e deixaria A, B e C mexidos para sempre.
           Juntando os dois, cada chave fica com o valor mais antigo já visto - que é o valor de
           antes do WinForge. Chave que aparece uma vez só entra como está.
        2. Chave que o item não mexe é IGNORADA. Sem isso, um JSON plantado na pasta poderia escrever
           qualquer atributo do applicationHost.config ('server:<qualquer seção>:<qualquer atributo>')
           na primeira vez que alguém clicasse em Desfazer. -AllowedKey traz o conjunto
           '<tipo>:<propriedade>' que o item de fato escreve; o resto vira linha de WARN.
        3. Valor tem de ser texto simples. O backup é gravado como texto; um objeto ou um vetor no
           JSON só pode ter vindo de fora.

        Pasta não confiável (ver Test-WinForgeSnapshotRootTrusted) não é lida: volta
        @{ Blocked = $true; Reason = ... } e quem chamou recusa o Desfazer inteiro.
    .OUTPUTS
        $null (nenhum backup), @{ Blocked = $true; Reason } ou
        @{ Name; Values (hashtable); Paths (arquivos consumidos); Ignored (chaves recusadas) }.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Root,
        [hashtable]$AllowedKey
    )

    $dir = Get-WinForgeSnapshotRoot $Root
    $trust = Test-WinForgeSnapshotRootTrusted -Root $dir -ExplicitRoot:(-not [string]::IsNullOrWhiteSpace($Root))
    if (-not $trust.Trusted) { return @{ Blocked = $true; Reason = $trust.Reason } }

    $files = @(Get-WinForgeSnapshotFile -Name $Name -Root $Root)
    if (-not $files.Count) { return $null }

    $values = @{}
    $paths = @()
    $ignored = @()
    foreach ($file in $files) {
        # O arquivo também é conferido, e antes de ser lido: pasta protegida depois de um arquivo
        # estranho já estar lá, ou um link apontando para fora, não podem virar Desfazer.
        $fileTrust = Test-WinForgeSnapshotFileTrusted -Path $file.FullName -ExplicitRoot:(-not [string]::IsNullOrWhiteSpace($Root))
        if (-not $fileTrust.Trusted) {
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Backup não confiável, ignorado: $($file.FullName) -> $($fileTrust.Reason)"
            continue
        }
        $o = $null
        try { $o = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch {
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Backup ilegível, ignorado: $($file.FullName) -> $($_.Exception.Message)"
            continue
        }
        if ($null -eq $o -or $null -eq $o.Values) {
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Backup sem valores, ignorado: $($file.FullName)"
            continue
        }
        $paths += $file.FullName
        foreach ($p in $o.Values.PSObject.Properties) {
            if ($values.ContainsKey($p.Name)) { continue }   # o mais antigo já respondeu por esta chave
            if ($null -ne $AllowedKey -and -not (Test-WinForgeSnapshotKey -Key $p.Name -AllowedKey $AllowedKey)) {
                $ignored += $p.Name
                Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Chave fora do que '$Name' altera, ignorada no Desfazer: '$($p.Name)' ($($file.Name))."
                continue
            }
            if ($p.Value -isnot [string]) {
                $ignored += $p.Name
                Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Valor de '$($p.Name)' no backup não é texto, ignorado no Desfazer ($($file.Name))."
                continue
            }
            if (-not (Test-WinForgeSnapshotValue -Key $p.Name -Value $p.Value)) {
                $ignored += $p.Name
                Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Valor de '$($p.Name)' no backup não tem a forma esperada, ignorado no Desfazer: '$([string]$p.Value)' ($($file.Name))."
                continue
            }
            $values[$p.Name] = [string]$p.Value
        }
    }
    if (-not $paths.Count) { return $null }
    return @{ Name = $Name; Values = $values; Paths = $paths; Ignored = $ignored; Path = $paths[-1] }
}

function Test-WinForgeSnapshotValue {
    <#
    .SYNOPSIS
        Diz se o valor lido de um backup tem a FORMA que aquela chave aceita.
    .DESCRIPTION
        O crivo de chave (Test-WinForgeSnapshotKey) responde "esta propriedade é minha"; este aqui
        responde "este texto é um valor de verdade para ela". Faltava o segundo, e faltava caro: um
        'ActiveSchemeGuid' com 'x; algo-perigoso' era montado num texto de comando e executado
        elevado no Desfazer. O texto de comando saiu (agora o powercfg recebe o GUID como argumento),
        mas a forma continua sendo cobrada nos DOIS pontos - ao ler o backup e antes de escrever -
        porque uma tranca só é uma tranca que alguém remove sem perceber.

        Cada padrão é ancorado nas duas pontas e só descreve o formato real do valor: GUID é
        hexadecimal com hífen, booleano é True/False, DWORD é dígito, TimeSpan é hh:mm:ss (com o
        'd.' opcional na frente, que o processModel.idleTimeout usa a partir de um dia), o nível do
        TCP é um dos cinco nomes que o Windows aceita e o registro pode ainda trazer a sentinela
        '<RemoveEntry>'. Chave sem padrão conhecido é recusada - o padrão é negar.
    .OUTPUTS
        $true se o valor serve.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        $Value
    )

    if ($Value -isnot [string]) { return $false }

    $prop = $Key
    if ($Key -match '^(pool|site|server):') {
        $k = $null
        try { $k = Split-WinForgeIisKey -Key $Key } catch { return $false }
        $prop = $k.Property
    }

    $booleano = '^(True|False)$'
    $dword    = '^\d{1,10}$'
    $tempo    = '^(\d{1,5}\.)?\d{2,}:\d{2}:\d{2}$'
    $padrao = switch ($prop) {
        'EnableSMB1Protocol'                      { $booleano; break }
        'RequireSecuritySignature'                { $booleano; break }
        'ActiveSchemeGuid'                        { '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'; break }
        'AutoTuningLevelLocal'                    { '^(Disabled|HighlyRestricted|Restricted|Normal|Experimental)$'; break }
        'UserAuthentication'                      { '^(\d{1,10}|<RemoveEntry>)$'; break }
        'SecurityLayer'                           { '^(\d{1,10}|<RemoveEntry>)$'; break }
        'MaxIdleTime'                             { '^(\d{1,10}|<RemoveEntry>)$'; break }
        'startMode'                               { '^(OnDemand|AlwaysRunning)$'; break }
        'autoStart'                               { $booleano; break }
        'applicationDefaults.preloadEnabled'      { $booleano; break }
        'processModel.idleTimeout'                { $tempo; break }
        'recycling.periodicRestart.time'          { $tempo; break }
        'recycling.periodicRestart.privateMemory' { $dword; break }
        'queueLength'                             { $dword; break }
        'doStaticCompression'                     { $booleano; break }
        'doDynamicCompression'                    { $booleano; break }
        'enabled'                                 { $booleano; break }
        'enableKernelCache'                       { $booleano; break }
        default                                   { $null }
    }
    if (-not $padrao) { return $false }
    return [bool][regex]::IsMatch($Value, [string]$padrao)
}

function Test-WinForgeSnapshotKey {
    <#
    .SYNOPSIS
        Diz se uma chave de backup está entre as que o item realmente escreve.
    .DESCRIPTION
        Para pool e site a comparação é 'pool:<propriedade>' - o ALVO (nome do pool ou do site) fica
        de fora de propósito: o backup pode ter sido gravado quando existia um pool que já foi
        apagado, e o que importa aqui é que ninguém consiga escrever uma propriedade que o item não
        mexe. O pior que a forma curta permite é escrever uma propriedade que o item DE FATO mexe num
        pool que talvez não exista mais.

        Para 'server:' NÃO existe forma curta, e é uma correção de segurança: com
        'server:<propriedade>' na tabela, um backup plantado com
        'server:system.webServer/directoryBrowse:enabled' passava pelo crivo do OutputCache - a
        seção, que é o que diz QUAL parte do applicationHost.config será escrita, ficava de fora da
        comparação. Aqui a chave tem de bater inteira: seção e atributo.

        Para os ajustes de servidor a chave é o nome curto do valor ('EnableSMB1Protocol'), e a
        comparação é direta.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][hashtable]$AllowedKey
    )

    if ($AllowedKey.ContainsKey($Key)) { return $true }
    $k = $null
    try { $k = Split-WinForgeIisKey -Key $Key } catch { return $false }
    if ($k.Kind -eq 'server') { return $false }
    return $AllowedKey.ContainsKey("$($k.Kind):$($k.Property)")
}

function Complete-WinForgeSnapshot {
    <#
    .SYNOPSIS
        Arquiva os backups já consumidos por um Desfazer, renomeando-os para '<nome>.restored.json'.
    .DESCRIPTION
        Sem isto, uma aplicação depois do Desfazer teria de conviver com backups antigos, e a regra
        "o mais antigo vence" devolveria o estado de duas aplicações atrás. Renomear (em vez de
        apagar) mantém o histórico no disco para quem for investigar, e Get-WinForgeSnapshotFile
        deixa esses arquivos de fora.

        "Já consumido" só vale se o Desfazer tiver dado certo INTEIRO. Com uma chave que falhou, o
        arquivo é a única cópia do valor anterior dela: arquivá-lo é jogar fora a chance de tentar de
        novo, e o servidor fica com metade do estado antigo e nenhum registro do resto. Nesse caso os
        arquivos ficam onde estão e o log diz quais chaves seguram o arquivamento.
    .PARAMETER FailedKey
        Chaves que não puderam ser restauradas. Qualquer uma cancela o arquivamento.
    .OUTPUTS
        Quantidade de arquivos arquivados.
    #>
    param(
        [string[]]$Paths,
        [string[]]$FailedKey = @()
    )

    if (@($FailedKey).Count) {
        Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Backups mantidos (não arquivados): $(@($FailedKey).Count) chave(s) não puderam ser restauradas: $(@($FailedKey) -join ', ')."
        return 0
    }
    $n = 0
    foreach ($p in @($Paths)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        try {
            $destino = [System.IO.Path]::ChangeExtension($p, '.restored.json')
            if (Test-Path -LiteralPath $destino) { Remove-Item -LiteralPath $destino -Force -ErrorAction Stop }
            Rename-Item -LiteralPath $p -NewName (Split-Path -Leaf $destino) -ErrorAction Stop
            $n++
        } catch {
            Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Backup consumido não pôde ser arquivado: $p -> $($_.Exception.Message)"
        }
    }
    return $n
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

        A forma do valor é cobrada AQUI também, e não só na leitura do backup: quem escreve é esta
        função, e uma checagem que mora longe do ponto de escrita é uma checagem que a próxima
        alteração esquece de chamar.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)]$Value
    )

    $texto = ConvertTo-WinForgeIisString $Value
    if (-not (Test-WinForgeSnapshotValue -Key $Key -Value $texto)) {
        throw "Valor recusado para '$Key': '$texto' não tem a forma esperada para essa propriedade."
    }
    $k = Split-WinForgeIisKey -Key $Key
    switch ($k.Kind) {
        'pool'   { Set-ItemProperty -LiteralPath ("IIS:\AppPools\" + $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
        'site'   { Set-ItemProperty -LiteralPath ("IIS:\Sites\" + $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
        'server' { Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter (Get-WinForgeIisFilter $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
    }
    throw "Chave de IIS inválida: '$Key' (tipo '$($k.Kind)' desconhecido)."
}

function Get-WinForgeIisAllowedKey {
    <#
    .SYNOPSIS
        As propriedades que cada item de IIS escreve, na forma '<tipo>:<propriedade>'.
    .DESCRIPTION
        É o crivo do Desfazer: só volta do backup a propriedade que o item de fato mexe. A tabela é
        estática de propósito - Get-WinForgeIisTweakPlan precisa do provedor IIS:\ para listar pools
        e sites, e num item cujo plano ficou vazio (nenhum pool, recurso Web-AppInit desinstalado
        depois da aplicação) um crivo derivado do plano recusaria o backup inteiro justamente quando
        ele é mais necessário. O -SelfTest cobra que as duas coisas continuem dizendo o mesmo nos
        itens de nível de servidor, que são os únicos cujo plano não depende de IIS instalado.
    .OUTPUTS
        Hashtable com as chaves permitidas.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $pares = switch ($Name) {
        'AlwaysRunning'   { @('pool:startMode', 'pool:autoStart') }
        'NoIdleTimeout'   { @('pool:processModel.idleTimeout') }
        'MemoryRecycling' { @('pool:recycling.periodicRestart.time', 'pool:recycling.periodicRestart.privateMemory') }
        'Preload'         { @('site:applicationDefaults.preloadEnabled') }
        'Compression'     { @('server:system.webServer/urlCompression:doStaticCompression', 'server:system.webServer/urlCompression:doDynamicCompression') }
        'OutputCache'     { @('server:system.webServer/caching:enabled', 'server:system.webServer/caching:enableKernelCache') }
        'Concurrency'     { @('pool:queueLength') }
        default           { throw "Item de IIS desconhecido: '$Name'." }
    }
    # As chaves de nível de servidor entram INTEIRAS ('server:<seção>:<atributo>') e só assim: a
    # seção faz parte do que o item mexe. A versão anterior também gravava a forma curta
    # ('server:<atributo>'), e era ela que desfazia o próprio crivo - Test-WinForgeSnapshotKey cai na
    # forma curta quando a longa não bate, então 'server:<QUALQUER seção>:enabled' passava.
    $tabela = @{}
    foreach ($par in $pares) { $tabela[$par] = $true }
    return $tabela
}

function Restore-WinForgeIisSnapshot {
    <#
    .SYNOPSIS
        Reescreve os valores anteriores de um item de IIS, juntando todos os backups vivos dele.
    .OUTPUTS
        @{ Changed; Skipped; Snapshot } - Skipped preenchido quando nada pôde ser restaurado.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Root
    )

    $snap = Get-WinForgeSnapshot -Name $Name -Root $Root -AllowedKey (Get-WinForgeIisAllowedKey -Name $Name)
    if ($null -ne $snap -and $snap.Blocked) {
        $motivo = "IIS: pasta de backup não confiável: $($snap.Reason). Nada foi alterado."
        Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message $motivo
        return @{ Changed = 0; Skipped = $motivo; Snapshot = $null }
    }
    if (-not $snap) {
        $motivo = "IIS: sem backup para desfazer '$Name' - nenhum valor foi alterado."
        Write-WinForgeLog -Component "IIS" -Level "WARN" -Message $motivo
        return @{ Changed = 0; Skipped = $motivo; Snapshot = $null }
    }
    $restored = 0
    $falhas = @()
    foreach ($key in @($snap.Values.Keys)) {
        try {
            Set-WinForgeIisValue -Key $key -Value $snap.Values[$key]
            $restored++
        } catch {
            $falhas += $key
            Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message "Falha ao restaurar '$key' -> $($_.Exception.Message)"
            Write-Host "IIS: falha ao restaurar '$key' -> $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    $arquivados = Complete-WinForgeSnapshot -Paths $snap.Paths -FailedKey $falhas
    Write-WinForgeLog -Component "IIS" -Message "Backup de $Name restaurado: $restored de $(@($snap.Values.Keys).Count) valor(es), de $(@($snap.Paths).Count) arquivo(s); $arquivados arquivado(s) como .restored.json."
    $skipped = ''
    if (@($snap.Ignored).Count) { $skipped = "IIS: $(@($snap.Ignored).Count) chave(s) do backup ficaram de fora por não pertencerem a '$Name' ou por não terem a forma esperada." }
    if (@($falhas).Count) { $skipped = ($skipped + " IIS: $(@($falhas).Count) chave(s) não puderam ser restauradas ($(@($falhas) -join ', ')); os backups foram mantidos para nova tentativa.").Trim() }
    return @{ Changed = $restored; Skipped = $skipped; Snapshot = $snap.Path }
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
        inteiro já aplicado não grava arquivo nenhum. O Desfazer junta todos os backups vivos do
        item e devolve, chave por chave, o valor mais antigo - o de antes da primeira aplicação -,
        depois arquiva os arquivos consumidos.
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
            $undo = Restore-WinForgeIisSnapshot -Name $Name -Root $Root
            $result.Changed = [int]$undo.Changed
            $result.Skipped = [string]$undo.Skipped
            $result.Snapshot = $undo.Snapshot
            if ($result.Changed -eq 0) {
                # Backup lido mas nenhuma escrita deu certo: cada falha já saiu em vermelho acima, e
                # sem esta linha o item terminaria com uma mensagem vazia.
                if (-not $result.Skipped) { $result.Skipped = "IIS: '$Name' desfeito sem alterar nada - nenhum valor do backup pôde ser reescrito." }
                Write-Host $result.Skipped -ForegroundColor Yellow
            } else {
                if ($result.Skipped) { Write-Host $result.Skipped -ForegroundColor Yellow }
                Write-Host "IIS: '$Name' desfeito - $($result.Changed) valor(es) restaurado(s)."
            }
            return $result
        }

        # Antes de qualquer leitura ou escrita: a pasta de backup tem de existir E ser confiável.
        # Sem backup confiável não se mexe no servidor - um Desfazer que outra conta pode reescrever
        # é pior que não aplicar.
        $raiz = Confirm-WinForgeSnapshotRoot -Root $Root
        if (-not $raiz.Ok) {
            $result.Skipped = "pasta de backup não confiável: $($raiz.Reason)"
            Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message "$Name recusado: $($result.Skipped) Nada foi alterado."
            Write-Host "IIS: $($result.Skipped) - nada foi alterado." -ForegroundColor Red
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
        $result.Snapshot = New-WinForgeSnapshot -Name $Name -Values $previous -Root $Root
        # Sem backup protegido não se altera nada: o arquivo é o que um Desfazer elevado reescreve no
        # servidor, e um que a própria conta pode reescrever sem elevação não serve para isso.
        if (-not $result.Snapshot) {
            $result.Changed = 0
            $result.Skipped = "IIS: não foi possível proteger o backup de '$Name'; nada foi alterado."
            Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message $result.Skipped
            Write-Host $result.Skipped -ForegroundColor Red
            return $result
        }

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

# ---------------------------------------------------------------------------
# Ajustes de servidor que não moram no registro (SMB, energia, TCP, RDP)
#
# Estes itens não têm bloco "registry" na configuração, então o padrão do programa - guardar o
# OriginalValue na própria entrada - não serve para eles: o "valor anterior" de um servidor de
# produção é o que o administrador deixou lá, não o que a Microsoft entrega. Escrever um Desfazer
# fixo era um estrago à espera de acontecer:
#
#   - SMB1 já vinha desligado (padrão do Server 2019+). Marcar "Desativar o SMB1" não muda nada, e
#     um "Desfazer selecionados" depois LIGAVA o SMB1 num servidor onde ele nunca esteve ligado.
#   - Num controlador de domínio a assinatura SMB é obrigatória por política. Desfazer a DESLIGAVA
#     até o próximo GPO.
#   - Alto desempenho já ativo: Desfazer jogava o servidor para Equilibrado.
#
# A saída é a mesma do IIS: LER antes de escrever, guardar o que foi lido num JSON na mesma pasta
# protegida (com o prefixo 'setting-<Item>') e fazer o Desfazer reescrever o que está no arquivo.
# Sem arquivo, o Desfazer não faz nada - é melhor que chutar o padrão da Microsoft por cima do que
# o administrador configurou.
# ---------------------------------------------------------------------------

function Get-WinForgeServerSettingSpec {
    <#
    .SYNOPSIS
        O que cada ajuste de servidor lê, o que ele escreve e qual ferramenta precisa existir.
    .OUTPUTS
        Hashtable com Keys (as chaves do backup), Targets (chave -> valor alvo) e Requires.
    #>
    param([Parameter(Mandatory)][string]$Name)

    switch ($Name) {
        'Smb1Off' {
            return @{ Keys = @('EnableSMB1Protocol'); Targets = @{ 'EnableSMB1Protocol' = 'False' }; Requires = 'Get-SmbServerConfiguration' }
        }
        'SmbSigning' {
            return @{ Keys = @('RequireSecuritySignature'); Targets = @{ 'RequireSecuritySignature' = 'True' }; Requires = 'Get-SmbServerConfiguration' }
        }
        'HighPerf' {
            # O plano de energia é identificado pelo GUID, não pelo nome: 'Alto desempenho' e 'High
            # performance' são o mesmo 8c5e7fda no mundo inteiro, e o nome muda com o idioma.
            return @{ Keys = @('ActiveSchemeGuid'); Targets = @{ 'ActiveSchemeGuid' = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }; Requires = (Get-WinForgeSystemExe -Name 'powercfg.exe') }
        }
        'TcpAutotuning' {
            return @{ Keys = @('AutoTuningLevelLocal'); Targets = @{ 'AutoTuningLevelLocal' = 'Normal' }; Requires = 'Get-NetTCPSetting' }
        }
        'RdpNla' {
            return @{
                Keys     = @('UserAuthentication', 'SecurityLayer', 'MaxIdleTime')
                Targets  = @{ 'UserAuthentication' = '1'; 'SecurityLayer' = '2'; 'MaxIdleTime' = '1800000' }
                Requires = $null
            }
        }
    }
    throw "Ajuste de servidor desconhecido: '$Name'."
}

function Get-WinForgeServerSettingRegistryPath {
    <#
    .SYNOPSIS
        Onde mora cada valor do item de RDP.
    #>
    param([Parameter(Mandatory)][string]$Key)

    switch ($Key) {
        'UserAuthentication' { return 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' }
        'SecurityLayer'      { return 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' }
        'MaxIdleTime'        { return 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' }
    }
    throw "Valor de RDP desconhecido: '$Key'."
}

function Get-WinForgeServerSettingState {
    <#
    .SYNOPSIS
        Lê o estado atual de um ajuste de servidor, como texto.
    .DESCRIPTION
        Chave cuja leitura falhou fica FORA da hashtable: para quem chama, "ausente" é "não lida", e
        valor não lido não entra no backup - guardar '' faria o Desfazer escrever vazio.

        Valor de registro que não existe vira '<RemoveEntry>', a mesma sentinela que o resto do
        programa usa: desfazer um MaxIdleTime que não existia é APAGAR a política, não escrever zero.
    .OUTPUTS
        Hashtable chave -> texto.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $estado = @{}
    switch ($Name) {
        { $_ -in @('Smb1Off', 'SmbSigning') } {
            try {
                $smb = Get-SmbServerConfiguration -ErrorAction Stop
                if ($Name -eq 'Smb1Off') { $estado['EnableSMB1Protocol'] = $(if ($smb.EnableSMB1Protocol) { 'True' } else { 'False' }) }
                else { $estado['RequireSecuritySignature'] = $(if ($smb.RequireSecuritySignature) { 'True' } else { 'False' }) }
            } catch {
                Write-WinForgeLog -Component "Server" -Level "WARN" -Message "SMB: estado atual não pôde ser lido -> $($_.Exception.Message)"
            }
            break
        }
        'HighPerf' {
            try {
                $saida = (Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'powercfg.exe') -Arguments @('/getactivescheme')).Text
                if ([string]$saida -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $estado['ActiveSchemeGuid'] = $Matches[1].ToLower() }
            } catch {
                Write-WinForgeLog -Component "Server" -Level "WARN" -Message "Energia: plano ativo não pôde ser lido -> $($_.Exception.Message)"
            }
            break
        }
        'TcpAutotuning' {
            try {
                $nivel = [string](Get-NetTCPSetting -SettingName Internet -ErrorAction Stop).AutoTuningLevelLocal
                if (-not [string]::IsNullOrWhiteSpace($nivel)) { $estado['AutoTuningLevelLocal'] = $nivel }
            } catch {
                Write-WinForgeLog -Component "Server" -Level "WARN" -Message "TCP: nível de ajuste automático não pôde ser lido -> $($_.Exception.Message)"
            }
            break
        }
        'RdpNla' {
            foreach ($chave in @('UserAuthentication', 'SecurityLayer', 'MaxIdleTime')) {
                $caminho = Get-WinForgeServerSettingRegistryPath -Key $chave
                try {
                    $item = Get-ItemProperty -LiteralPath $caminho -Name $chave -ErrorAction Stop
                    $estado[$chave] = [string]$item.$chave
                } catch {
                    $estado[$chave] = '<RemoveEntry>'
                }
            }
            break
        }
        default { throw "Ajuste de servidor desconhecido: '$Name'." }
    }
    return $estado
}

function Set-WinForgeServerSettingValue {
    <#
    .SYNOPSIS
        Escreve um valor de ajuste de servidor. O valor vem como texto - é assim que ele sai do backup.
    .DESCRIPTION
        Texto que veio de um arquivo de backup é dado de FORA, mesmo quando o arquivo é nosso: quem
        conseguir escrever lá dentro escolhe o que esta função recebe. Duas regras, as duas por causa
        do mesmo estrago:

        1. A forma do valor é conferida antes de qualquer escrita (Test-WinForgeSnapshotValue).
        2. Nenhum valor vira TEXTO DE COMANDO. O powercfg recebe o GUID como argumento, num vetor -
           antes ele era formatado dentro de "powercfg /setactive {0}" e compilado como PowerShell,
           e um 'ActiveSchemeGuid' com ponto-e-vírgula plantado no JSON rodava elevado no Desfazer.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    if (-not (Test-WinForgeSnapshotValue -Key $Key -Value $Value)) {
        throw "Valor recusado para '$Key': '$Value' não tem a forma esperada para esse ajuste."
    }

    switch ($Key) {
        'EnableSMB1Protocol' {
            Set-SmbServerConfiguration -EnableSMB1Protocol ([bool]::Parse($Value)) -Force -ErrorAction Stop
            return
        }
        'RequireSecuritySignature' {
            Set-SmbServerConfiguration -RequireSecuritySignature ([bool]::Parse($Value)) -Force -ErrorAction Stop
            return
        }
        'ActiveSchemeGuid' {
            $r = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'powercfg.exe') -Arguments @('/setactive', $Value)
            if ($r.ExitCode -ne 0) { throw "powercfg.exe /setactive $Value devolveu código $($r.ExitCode): $([string]$r.Text)" }
            return
        }
        'AutoTuningLevelLocal' {
            Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal $Value -ErrorAction Stop
            return
        }
        { $_ -in @('UserAuthentication', 'SecurityLayer', 'MaxIdleTime') } {
            $caminho = Get-WinForgeServerSettingRegistryPath -Key $Key
            if ($Value -eq '<RemoveEntry>') {
                if (Test-Path -LiteralPath $caminho) { Remove-ItemProperty -LiteralPath $caminho -Name $Key -Force -ErrorAction SilentlyContinue }
                return
            }
            if (-not (Test-Path -LiteralPath $caminho)) { New-Item -Path $caminho -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -LiteralPath $caminho -Name $Key -Value ([int]$Value) -Type DWord -Force -ErrorAction Stop
            return
        }
    }
    throw "Valor de ajuste de servidor desconhecido: '$Key'."
}

function Invoke-WinForgeServerSetting {
    <#
    .SYNOPSIS
        Aplica (ou desfaz) um ajuste de servidor que não mora no registro, guardando antes o estado atual.
    .DESCRIPTION
        Nunca lança: roda dentro do runspace de tweaks, onde uma exceção mataria a fila inteira de
        itens marcados. Erro vira linha de log, aviso amarelo no console e Changed = 0.

        Só roda em Windows Server DE VERDADE. WINFORGE_SIMULATE_SERVER monta a aba e as regras num
        cliente para poder testá-las, mas mexer no SMB, no plano de energia ou no RDP da máquina de
        quem está testando não é simulação - é estrago. A checagem lê o ProductType do registro, que
        a simulação não mexe.
    .PARAMETER CaptureOnly
        Lê e grava o backup sem aplicar nada. É o que o -SelfTest usa para provar que a captura
        funciona sem alterar a máquina onde o build roda.
    .OUTPUTS
        [pscustomobject] Name, Changed, Skipped, Snapshot, Captured (chaves lidas).
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Smb1Off', 'SmbSigning', 'HighPerf', 'TcpAutotuning', 'RdpNla')]
        [string]$Name,
        [switch]$Undo,
        [switch]$CaptureOnly,
        [string]$Root
    )

    $result = [pscustomobject]@{ Name = $Name; Changed = 0; Skipped = ''; Snapshot = $null; Captured = @() }
    try {
        $spec = Get-WinForgeServerSettingSpec -Name $Name
        $permitidas = @{}
        foreach ($k in $spec.Keys) { $permitidas[$k] = $true }

        # -CaptureOnly não escreve nada, então passa por aqui: é como o -SelfTest prova a captura numa
        # máquina cliente sem mexer em coisa nenhuma dela.
        if (-not $CaptureOnly -and -not (Test-WinForgeRealServer)) {
            $result.Skipped = "Servidor: '$Name' só se aplica ao Windows Server - nada foi alterado nesta máquina."
            Write-WinForgeLog -Component "Server" -Level "WARN" -Message $result.Skipped
            Write-Host $result.Skipped -ForegroundColor Yellow
            return $result
        }

        if ($Undo) {
            $snap = Get-WinForgeSnapshot -Name "setting-$Name" -Root $Root -AllowedKey $permitidas
            if ($null -ne $snap -and $snap.Blocked) {
                $result.Skipped = "Servidor: pasta de backup não confiável: $($snap.Reason). Nada foi alterado."
                Write-WinForgeLog -Component "Server" -Level "ERROR" -Message $result.Skipped
                Write-Host $result.Skipped -ForegroundColor Yellow
                return $result
            }
            if (-not $snap) {
                $result.Skipped = "Servidor: sem backup para desfazer '$Name' - nenhum valor foi alterado."
                Write-WinForgeLog -Component "Server" -Level "WARN" -Message $result.Skipped
                Write-Host $result.Skipped -ForegroundColor Yellow
                return $result
            }
            $falhas = @()
            foreach ($chave in @($snap.Values.Keys)) {
                try {
                    Set-WinForgeServerSettingValue -Key $chave -Value $snap.Values[$chave]
                    $result.Changed++
                } catch {
                    $falhas += $chave
                    Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "Falha ao restaurar '$chave' de '$Name' -> $($_.Exception.Message)"
                    Write-Host "Servidor: falha ao restaurar '$chave' -> $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            if (@($snap.Ignored).Count) {
                $result.Skipped = "Servidor: $(@($snap.Ignored).Count) chave(s) do backup ficaram de fora por não pertencerem a '$Name' ou por não terem a forma esperada."
            }
            if (@($falhas).Count) {
                $result.Skipped = ($result.Skipped + " Servidor: $(@($falhas).Count) chave(s) não puderam ser restauradas ($(@($falhas) -join ', ')); os backups foram mantidos para nova tentativa.").Trim()
            }
            $result.Snapshot = $snap.Path
            Complete-WinForgeSnapshot -Paths $snap.Paths -FailedKey $falhas | Out-Null
            Write-WinForgeLog -Component "Server" -Message "'$Name' desfeito: $($result.Changed) valor(es) restaurado(s) de $(@($snap.Paths).Count) backup(s)."
            Write-Host "Servidor: '$Name' desfeito - $($result.Changed) valor(es) restaurado(s)."
            return $result
        }

        # Aplicar (e capturar) exige pasta de backup confiável, pelo mesmo motivo do IIS: o arquivo
        # que sai daqui é o que um Desfazer elevado vai reescrever no servidor.
        $raiz = Confirm-WinForgeSnapshotRoot -Root $Root
        if (-not $raiz.Ok) {
            $result.Skipped = "pasta de backup não confiável: $($raiz.Reason)"
            Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "'$Name' recusado: $($result.Skipped) Nada foi alterado."
            Write-Host "Servidor: $($result.Skipped) - nada foi alterado." -ForegroundColor Red
            return $result
        }

        $atual = Get-WinForgeServerSettingState -Name $Name
        $result.Captured = @($atual.Keys)
        if ($atual.Count -eq 0) {
            $result.Skipped = "Servidor: o estado atual de '$Name' não pôde ser lido nesta máquina$(if ($spec.Requires) { " ('$($spec.Requires)' ausente ou sem resposta)" }); nada foi alterado."
            Write-WinForgeLog -Component "Server" -Level "WARN" -Message $result.Skipped
            Write-Host $result.Skipped -ForegroundColor Yellow
            return $result
        }

        # Só entra no backup (e na escrita) a chave que ainda não está no alvo: a mesma regra dos
        # itens de IIS, e é ela que impede um segundo backup já com os valores ajustados.
        $anterior = @{}
        $pendentes = @()
        foreach ($chave in $spec.Keys) {
            if (-not $atual.ContainsKey($chave)) { continue }
            if ([string]::Equals([string]$atual[$chave], [string]$spec.Targets[$chave], [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $anterior[$chave] = [string]$atual[$chave]
            $pendentes += $chave
        }

        if ($CaptureOnly) {
            $tudo = @{}
            foreach ($chave in $spec.Keys) { if ($atual.ContainsKey($chave)) { $tudo[$chave] = [string]$atual[$chave] } }
            $result.Snapshot = New-WinForgeSnapshot -Name "setting-$Name" -Values $tudo -Root $Root
            if (-not $result.Snapshot) {
                $result.Changed = 0
                $result.Skipped = "Servidor: não foi possível proteger o backup de '$Name'; nada foi alterado."
                Write-WinForgeLog -Component "Server" -Level "ERROR" -Message $result.Skipped
                Write-Host $result.Skipped -ForegroundColor Red
                return $result
            }
            $result.Skipped = "Servidor: '$Name' apenas capturado ($($tudo.Count) valor(es)); nada foi alterado."
            return $result
        }

        if ($pendentes.Count -eq 0) {
            $result.Skipped = "Servidor: '$Name' já aplicado - $($atual.Count) valor(es) já estavam no alvo; nada foi alterado e nenhum backup foi gravado."
            Write-WinForgeLog -Component "Server" -Level "WARN" -Message $result.Skipped
            Write-Host $result.Skipped -ForegroundColor Yellow
            return $result
        }

        $result.Snapshot = New-WinForgeSnapshot -Name "setting-$Name" -Values $anterior -Root $Root
        # Mesma regra do IIS: backup que não pôde ser protegido não autoriza alteração nenhuma.
        if (-not $result.Snapshot) {
            $result.Changed = 0
            $result.Skipped = "Servidor: não foi possível proteger o backup de '$Name'; nada foi alterado."
            Write-WinForgeLog -Component "Server" -Level "ERROR" -Message $result.Skipped
            Write-Host $result.Skipped -ForegroundColor Red
            return $result
        }
        foreach ($chave in $pendentes) {
            try {
                Set-WinForgeServerSettingValue -Key $chave -Value ([string]$spec.Targets[$chave])
                $result.Changed++
            } catch {
                Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "Falha ao ajustar '$chave' de '$Name' -> $($_.Exception.Message)"
                Write-Host "Servidor: falha ao ajustar '$chave' -> $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-WinForgeLog -Component "Server" -Message "'$Name' aplicado: $($result.Changed) valor(es) alterado(s); backup em $($result.Snapshot)."
        Write-Host "Servidor: '$Name' aplicado - $($result.Changed) valor(es) alterado(s). Backup: $($result.Snapshot)"
    } catch {
        Write-WinForgeLog -Component "Server" -Level "ERROR" -Message "Falha em '$Name': $($_.Exception.Message)"
        Write-Host "Servidor: falha em '$Name' -> $($_.Exception.Message)" -ForegroundColor Red
        $result.Changed = 0
    }
    return $result
}
#endregion
