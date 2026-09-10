#region ===== WinForge - comandos com janela de saída =====
# A máquina de "botão que roda uma ferramenta e mostra o resultado numa janela", sem saber de que
# aba veio o botão. Nasceu na aba Servidor e foi generalizada aqui para o reparo de componentes
# reusá-la inteira: tabela de comandos -> núcleo síncrono -> despacho em runspace -> janela.
#
# Quem chama entrega uma ESPECIFICAÇÃO (hashtable) e três rótulos:
#   Spec       @{ Title; Command; Requires; Native; Kind; Confirm }
#   Name       nome curto do comando, usado no log e no nome do arquivo de saída
#   Component  o que aparece entre colchetes no log ('Server', 'Repair', ...)
#   Prefix     o começo do nome do arquivo de saída ('server' -> server-<Name>-<ts>.txt)
#
# 'Requires' é o nome de um executável ('dcdiag.exe') ou de um cmdlet ('Get-MpPreference') resolvido
# com Get-Command. Ausente, o comando não roda: vira uma frase dizendo qual ferramenta falta.
#
# 'Native' separa o que é EXECUTÁVEL do que é pipeline de cmdlet, e manda em duas coisas: só o
# executável passa pela troca de code page (w32tm, dcdiag e repadmin escrevem em OEM) e só ele tem
# código de saída.
#
# 'Kind' ('read', 'repair', 'install') e 'Confirm' não são lidos aqui: quem decide se pergunta antes
# de rodar é o dono da tabela. O núcleo genérico só executa o que mandarem executar.
# ---------------------------------------------------------------------------

function Split-WinForgeCertificateSubject {
    <#
    .SYNOPSIS
        Quebra o assunto de um certificado ('CN=..., O=..., C=US') nos seus RDNs.
    .DESCRIPTION
        Existe porque comparar o assunto INTEIRO com texto - ou procurar 'NVIDIA Corporation' dentro
        dele - aceita coisas que não deveria: 'O=NVIDIA Corporation Ltd' contém 'NVIDIA Corporation',
        e 'CN=NVIDIA Corporation' de um certificado de qualquer outra organização também. A pergunta
        certa é "o RDN O vale EXATAMENTE tal coisa", e para fazê-la é preciso separar os RDNs
        primeiro.

        Três detalhes do formato, e os três já apareceram em certificado de verdade:

        1. Vírgula dentro do valor. O .NET escreve o valor entre aspas quando ele tem vírgula
           ('O="Alguma Coisa, Inc."'); um split por vírgula partiria o valor no meio e o pedaço da
           direita viraria um RDN inventado.
        2. Barra invertida como escape ('O=Alguma Coisa\, Inc'), que algumas APIs usam no lugar das
           aspas.
        3. O MESMO RDN duas vezes ('O=Fulano, O=NVIDIA Corporation'). Por isso cada chave guarda uma
           LISTA: quem confere pode exigir que exista um só - um assunto com dois O não é o assunto
           do fabricante, é um assunto montado para passar por ele.
    .OUTPUTS
        Hashtable de RDN em MAIÚSCULAS ('CN', 'O', 'L') para o array de valores, na ordem em que
        aparecem. Assunto vazio devolve hashtable vazia.
    #>
    param([string]$Subject)

    $rdns = @{}
    if ([string]::IsNullOrWhiteSpace($Subject)) { return $rdns }

    # Quebra em partes de primeiro nível: vírgula fora de aspas e não escapada.
    $partes = [System.Collections.Generic.List[string]]::new()
    $atual = New-Object System.Text.StringBuilder
    $emAspas = $false
    for ($i = 0; $i -lt $Subject.Length; $i++) {
        $c = $Subject[$i]
        if ($c -eq '\' -and $i + 1 -lt $Subject.Length) {
            # O escape leva o caractere seguinte inteiro, e a barra some do valor.
            [void]$atual.Append($Subject[$i + 1])
            $i++
            continue
        }
        if ($c -eq '"') { $emAspas = -not $emAspas; continue }
        if ($c -eq ',' -and -not $emAspas) {
            [void]$partes.Add($atual.ToString())
            [void]$atual.Clear()
            continue
        }
        [void]$atual.Append($c)
    }
    [void]$partes.Add($atual.ToString())

    foreach ($parte in $partes) {
        $texto = $parte.Trim()
        if ([string]::IsNullOrWhiteSpace($texto)) { continue }
        $igual = $texto.IndexOf('=')
        if ($igual -le 0) { continue }
        $chave = $texto.Substring(0, $igual).Trim().ToUpperInvariant()
        $valor = $texto.Substring($igual + 1).Trim()
        if (-not $rdns.ContainsKey($chave)) { $rdns[$chave] = @() }
        $rdns[$chave] = @($rdns[$chave]) + @($valor)
    }
    return $rdns
}

function Get-WinForgeSystemExe {
    <#
    .SYNOPSIS
        Caminho completo de um executável do Windows dentro de %SystemRoot%\System32.
    .DESCRIPTION
        Existe para nenhum executável de sistema ser resolvido pelo PATH. O WinForge roda SEMPRE
        elevado (o manifesto do lançador pede administrador), e chamar 'chkdsk.exe' pelo nome deixa a
        escolha do binário com a variável PATH: normalmente o System32 vem primeiro, mas um PATH de
        sistema editado por instalador (que prepende a própria pasta) muda isso, e aí um executável
        de terceiro roda com token de administrador. O nome vira caminho aqui, uma vez só, e quem
        chama passa o caminho inteiro para -FilePath.

        O 'Name' pode trazer subpasta: o winmgmt mora em System32\wbem, não em System32
        ('wbem\winmgmt.exe').

        A âncora é [Environment]::SystemDirectory, e NÃO %SystemRoot%. A diferença é a mesma história
        do PATH, um passo adiante: variável de ambiente de processo nasce do bloco do usuário em
        HKCU\Environment, que qualquer processo de integridade MÉDIA da conta escreve. Com
        'SystemRoot' apontando para uma pasta do perfil, todo caminho montado aqui sairia de lá - e o
        WinForge, elevado, abriria o 'chkdsk.exe' de quem plantou. [Environment]::SystemDirectory vem
        da API GetSystemDirectory, que lê a pasta real do Windows e não passa por variável nenhuma.
        Só se ela vier vazia sobra o padrão 'C:\Windows\System32'.

        Função pura: monta texto e não toca no disco. Quem confere se o arquivo existe é
        Test-WinForgeCommandRequirement, que aceita caminho absoluto.
    .OUTPUTS
        Caminho completo do executável.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $raiz = $null
    try { $raiz = [string][Environment]::SystemDirectory } catch { $raiz = $null }
    if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = 'C:\Windows\System32' }
    return (Join-Path $raiz $Name)
}

function Test-WinForgeCommandRequirement {
    <#
    .SYNOPSIS
        Diz se a ferramenta exigida por um comando existe nesta máquina. Sem exigência, é sempre sim.
    .DESCRIPTION
        Duas formas de exigência, e a diferença importa:

        - CAMINHO ABSOLUTO ('C:\Windows\System32\fsutil.exe'): a pergunta é se o arquivo está lá, e
          quem responde é Test-Path. É a forma dos executáveis do sistema, que não passam mais pelo
          PATH (Get-WinForgeSystemExe) - resolver um caminho absoluto com Get-Command devolveria o
          mesmo arquivo na maioria das máquinas e nenhum na que tem o PATH quebrado, sem motivo.
        - NOME ('Get-MpPreference', 'dcdiag.exe'): cmdlet ou ferramenta opcional do Windows, que só
          o Get-Command sabe encontrar (módulo a carregar, pasta de RSAT).
    #>
    param([string]$Requires)

    if ([string]::IsNullOrWhiteSpace($Requires)) { return $true }
    if ([System.IO.Path]::IsPathRooted($Requires)) { return (Test-Path -LiteralPath $Requires -PathType Leaf) }
    return [bool](Get-Command $Requires -ErrorAction SilentlyContinue)
}

function Get-WinForgeCommandOutputPath {
    <#
    .SYNOPSIS
        Caminho do arquivo de saída de um comando: <prefixo>-<Nome>-<aaaaMMdd-HHmmss>.txt na pasta de logs.
    .DESCRIPTION
        A pasta é a mesma da sessão ($sync.logPath): quem for pedir ajuda já sabe olhar lá, e não
        aparece uma segunda pasta só para isso. Com os segundos no nome, dois cliques seguidos não se
        sobrescrevem.

        O prefixo é de quem chama ('server', 'repair'): assim os arquivos de abas diferentes convivem
        na mesma pasta sem se confundirem, e uma listagem por prefixo continua trazendo só os de uma.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Prefix = 'command'
    )

    $dir = $null
    if ($null -ne $sync -and $sync.logPath) { $dir = Split-Path -Parent $sync.logPath }
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = Join-Path $env:LocalAppData 'WinForge\logs' }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir ("{0}-{1}-{2}.txt" -f $Prefix, $Name, (Get-Date -Format 'yyyyMMdd-HHmmss')))
}

function Invoke-WinForgeCommandText {
    <#
    .SYNOPSIS
        Roda um texto de comando e devolve a saída como texto, junto com o $LASTEXITCODE resultante.
    .DESCRIPTION
        O miolo comum dos dois modos (executável e pipeline de cmdlet). Duas escolhas moram aqui:

        1. ErrorRecord vira TEXTO antes do Out-String. Com '2>&1' cru, a linha que dcdiag ou repadmin
           manda para o fluxo de erro chega como System.Management.Automation.ErrorRecord e o
           Out-String a formata com o bloco '+ CategoryInfo / + FullyQualifiedErrorId' no meio da
           saída normal. O .ToString() do registro é exatamente a linha que a ferramenta escreveu.
        2. $LASTEXITCODE é zerado ANTES e lido logo depois: ele é global e sobrevive à chamada
           anterior, então sem zerar um pipeline de cmdlet devolveria o código de outro comando.

        REGRA: o texto é COMPILADO como PowerShell. Só entram aqui literais escritos no próprio
        programa - as tabelas de comando (Get-WinForgeServerCommand e afins). Nada que tenha vindo de
        um arquivo de backup, do registro ou da saída de outro comando pode ser concatenado neste
        texto: seria execução de código com a elevação do WinForge. Para isso existe
        Invoke-WinForgeNativeCommand -FilePath/-Arguments, que passa cada argumento inteiro.
    .OUTPUTS
        @{ Text = <string>; ExitCode = <int> }.
    #>
    param([Parameter(Mandatory)][string]$Command)

    $global:LASTEXITCODE = 0
    $texto = & ([scriptblock]::Create($Command)) 2>&1 |
        ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ } } |
        Out-String -Width 4096
    return @{ Text = [string]$texto; ExitCode = $global:LASTEXITCODE }
}

function Invoke-WinForgeNativeCommand {
    <#
    .SYNOPSIS
        Roda um comando externo e devolve o texto (decodificado em OEM) junto com o código de saída.
    .DESCRIPTION
        Duas armadilhas de executável no PowerShell moram aqui, e é por isso que existe um lugar só
        para elas - a aba Servidor e o perfil do sistema caíam nas duas em separado:

        1. A code page. w32tm, netsh, dcdiag e repadmin escrevem em OEM (850/437 no Brasil); o
           PowerShell decodifica pelo [Console]::OutputEncoding, que costuma estar em outra coisa - e
           toda palavra acentuada chega embaralhada. A troca é PROCESSO INTEIRO, então a janela é a
           menor possível: muda, roda o comando, devolve no finally. E como é do processo inteiro,
           duas runspaces do pool podem se atropelar (o levantamento do perfil e um botão da aba
           Servidor rodam em paralelo): um mutex nomeado por processo serializa trocar-rodar-devolver,
           no mesmo estilo do mutex de log. Sem o mutex a função roda assim mesmo - acento
           embaralhado é melhor que botão travado.
        2. O código de saída. $LASTEXITCODE é global e sobrevive à chamada anterior: sem zerar antes,
           um comando que não é executável devolveria o código de outro. Ele é lido na linha seguinte
           ao comando, antes que qualquer outra coisa o sobrescreva.

        '2>&1' antes do Out-String porque dcdiag e repadmin escrevem parte do que interessa no fluxo
        de erro, e sem isso a saída sairia vazia justamente quando há problema. -Width 4096 porque o
        padrão do Out-String é a largura do console (80 em runspace sem janela): tabela larga voltava
        cortada, e o corte ia direto para o arquivo.

        Só para EXECUTÁVEL: é o w32tm/dcdiag/repadmin que escreve em OEM. Pipeline de cmdlet passa
        por Invoke-WinForgeCommandText, que não mexe na code page nem em código de saída.
    .PARAMETER Command
        Texto de comando, montado por [scriptblock]::Create. SÓ para literais do próprio programa
        (as tabelas de comando). Dado que veio de arquivo, registro ou saída de outro comando NUNCA
        entra aqui: use -FilePath/-Arguments.
    .PARAMETER FilePath
        Executável a chamar. Os argumentos vão num VETOR, um a um, sem passar por interpretador:
        é o que impede um valor de backup ('x; algo-perigoso') de virar comando. Um GUID plantado
        no JSON chega ao powercfg como um argumento só - inválido, e ele reclama.
    .PARAMETER Utf8
        Decodifica a saída como UTF-8 em vez de OEM. É o caso do winget, que escreve UTF-8: com a
        troca para OEM, todo acento do texto localizado dele ("Nenhum pacote instalado encontrado")
        e dos nomes de pacote chega embaralhado ao relatório. A troca continua sendo do PROCESSO
        INTEIRO e continua serializada pelo mesmo mutex - só o destino muda.
    .OUTPUTS
        @{ Text = <string>; ExitCode = <int> }.
    #>
    param(
        [string]$Command,
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$Utf8
    )

    if ([string]::IsNullOrWhiteSpace($Command) -and [string]::IsNullOrWhiteSpace($FilePath)) {
        throw "Invoke-WinForgeNativeCommand precisa de -Command ou de -FilePath."
    }
    if (-not [string]::IsNullOrWhiteSpace($Command) -and -not [string]::IsNullOrWhiteSpace($FilePath)) {
        throw "Invoke-WinForgeNativeCommand aceita -Command OU -FilePath, não os dois."
    }

    $encodingAnterior = $null
    $texto = ''
    $codigo = $null
    $mutex = $null
    $preso = $false
    try { $mutex = New-Object System.Threading.Mutex($false, "Local\WinForge.ConsoleEncoding.$PID") } catch { $mutex = $null }
    try {
        if ($null -ne $mutex) {
            try { $preso = $mutex.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $preso = $true } catch { $preso = $false }
        }
        try {
            $encodingAnterior = [Console]::OutputEncoding
            if ($Utf8) {
                # UTF8Encoding($false): sem BOM. Com BOM, os três bytes iniciais entrariam no texto
                # da primeira linha da saída.
                [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
            } else {
                [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
            }
        } catch {
            $encodingAnterior = $null
        }
        if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
            $global:LASTEXITCODE = 0
            $texto = [string](& $FilePath @Arguments 2>&1 |
                ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ } } |
                Out-String -Width 4096)
            $codigo = $global:LASTEXITCODE
        } else {
            $bruto = Invoke-WinForgeCommandText -Command $Command
            $texto = $bruto.Text
            $codigo = $bruto.ExitCode
        }
    } finally {
        if ($null -ne $encodingAnterior) { try { [Console]::OutputEncoding = $encodingAnterior } catch { } }
        if ($preso) { try { $mutex.ReleaseMutex() } catch { } }
        if ($null -ne $mutex) { try { $mutex.Dispose() } catch { } }
    }

    return @{ Text = [string]$texto; ExitCode = $codigo }
}

function Invoke-WinForgeCommandCore {
    <#
    .SYNOPSIS
        Roda um comando de uma tabela e grava a saída num arquivo. Síncrono, não mostra nada.
    .DESCRIPTION
        É o miolo do botão, sem interface nenhuma: é o que roda dentro do runspace e é o que o
        -SelfTest consegue exercitar sem abrir janela.

        Quatro decisões moram aqui (a code page e o código de saída são de Invoke-WinForgeNativeCommand):

        1. Ferramenta ausente NÃO é exceção. w32tm existe em qualquer Windows, dcdiag e repadmin não:
           o texto vira "Ferramenta 'x' não encontrada neste sistema.", o arquivo é gravado do mesmo
           jeito e o retorno tem a mesma forma do caso bem-sucedido. Quem chama nunca precisa de dois
           caminhos.
        2. O código de saída entra no PRÓPRIO texto, e não só no cabeçalho do arquivo: "dcdiag falhou"
           e "dcdiag não achou nada" saem parecidos na tela, e sem o código o usuário não distingue
           os dois. Uma linha só, no topo, para o arquivo e a janela contarem a mesma coisa - e só
           para comando EXECUTÁVEL ('Native'): pipeline de cmdlet não tem código de saída, e a linha
           "Código de saída: 0" num Get-MpPreference é um sucesso inventado.
        3. A checagem da ferramenta roda AQUI, dentro do runspace, e não no clique. Get-Command
           'Get-MpPreference' faz o Windows carregar o módulo do Defender (perto de um segundo na
           primeira vez), e na thread da janela isso é a interface congelada antes de o trabalho
           começar. Ferramenta ausente vira texto na janela de saída, como qualquer outro resultado.
        4. -DryRun é a PRIMEIRA coisa conferida, antes de tudo. Ver o item 3: até a checagem da
           ferramenta tem efeito colateral (carregar módulo), e uma simulação que carrega módulo não
           é simulação. Ele existe para o -SelfTest poder passar por toda linha de uma tabela -
           inclusive a que repara o sistema - sem tocar na máquina de quem compila.
        5. Em modo SelfTest ($sync.SelfTest), linha com 'Kind' diferente de 'read' e sem -DryRun é
           RECUSADA com exceção. É a trava que faltava quando um -DryRun engolido fez o instalador do
           DirectX rodar de verdade na máquina de quem compilava: aqui ela vale para toda a tabela,
           inclusive para uma linha nova cujo autor não tenha lembrado da trava.
        6. Ainda em modo SelfTest, linha marcada com 'OpensExternal' também é recusada, mesmo sendo
           'read'. Abrir uma página não altera o sistema, mas abre um navegador na máquina de quem
           compila - e num build sem ninguém na frente isso é lixo na tela, no melhor caso.
    .PARAMETER Spec
        A linha da tabela: @{ Title; Command; Requires; Native; ... }.
    .PARAMETER Component
        Rótulo do log ('Server', 'Repair').
    .PARAMETER Prefix
        Começo do nome do arquivo de saída ('server' -> server-<Name>-<ts>.txt).
    .PARAMETER DryRun
        Devolve o texto do comando prefixado com '[simulação] ' e para por aí: nada roda, nada é
        gravado, nenhuma ferramenta é procurada.
    .OUTPUTS
        Hashtable com Name, Title, Text (o que vai para a janela), Path (arquivo gravado, ou $null)
        e ExitCode (código do executável, ou $null).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Spec,
        [Parameter(Mandatory)][string]$Name,
        [string]$Component = 'Command',
        [string]$Prefix = 'command',
        [switch]$DryRun
    )

    $cmd = $Spec
    if ($DryRun) {
        return @{ Name = $Name; Title = [string]$cmd.Title; Text = "[simulação] " + [string]$cmd.Command; Path = $null; ExitCode = $null }
    }

    # A trava de SelfTest fica aqui, no funil por onde TODA linha de tabela passa, e não só dentro de
    # cada ajudante: uma linha nova que altere o sistema chega barrada de nascença, sem depender de
    # quem a escreveu ter lembrado da trava. Linha sem 'Kind' conta como 'read' - é o caso da tabela
    # do servidor, que só lê e que o -SelfTest roda de verdade.
    $tipo = [string]$cmd.Kind
    if ([string]::IsNullOrWhiteSpace($tipo)) { $tipo = 'read' }
    if ($sync.SelfTest -and $tipo -ne 'read') {
        throw "Recusado: '$Name' é uma ação do tipo '$tipo', que altera o sistema, e o WinForge está em modo SelfTest."
    }
    # 'OpensExternal' é o outro lado da mesma trava, e o item 5 sozinho não o cobre: a linha do
    # DirectX é 'read' (abrir uma página não altera o sistema) e mesmo assim não pode rodar num
    # SelfTest, porque abriria o navegador na máquina de quem compila - sem ninguém para fechá-lo, e
    # com o build pendurado. Até aqui isso era só uma convenção conferida no build ("nenhuma linha
    # com OpensExternal está na lista que o SelfTest roda"); agora é recusa no próprio funil, e uma
    # linha nova marcada assim chega barrada mesmo que alguém a acrescente àquela lista. O -DryRun
    # não cai aqui: ele já retornou lá em cima, e simular continua permitido.
    if ($sync.SelfTest -and $cmd.OpensExternal) {
        throw "Recusado: '$Name' abre algo fora do WinForge (OpensExternal) e o WinForge está em modo SelfTest."
    }

    $inicio = Get-Date
    # $null enquanto nada de externo rodou (ferramenta ausente, exceção): 0 seria mentira de sucesso.
    $codigo = $null

    if (-not (Test-WinForgeCommandRequirement -Requires $cmd.Requires)) {
        $texto = "Ferramenta '$($cmd.Requires)' não encontrada neste sistema."
        Write-WinForgeLog -Component $Component -Level "WARN" -Message "$Name não executado: $texto"
    } else {
        try {
            if ($cmd.Native) {
                $exec = Invoke-WinForgeNativeCommand -Command $cmd.Command
                $codigo = $exec.ExitCode
            } else {
                $exec = Invoke-WinForgeCommandText -Command $cmd.Command
            }
            $texto = $exec.Text
        } catch {
            $texto = "Falha ao executar o comando: $($_.Exception.Message)"
            Write-WinForgeLog -Component $Component -Level "ERROR" -Message "$Name falhou: $($_.Exception.Message)"
        }
        # 'dcdiag /q' só fala quando encontra problema: saída vazia é a boa notícia, e uma janela em
        # branco pareceria o comando ter falhado.
        if ($Name -eq 'Dcdiag' -and [string]::IsNullOrWhiteSpace($texto)) { $texto = "Sem erros reportados pelo dcdiag." }
    }

    $texto = [string]$texto
    if ($null -ne $codigo) { $texto = "Código de saída: $codigo`r`n`r`n$texto" }
    $arquivo = $null
    try {
        $arquivo = Get-WinForgeCommandOutputPath -Name $Name -Prefix $Prefix
        $cabecalho = "WinForge - $($cmd.Title)`r`n$((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) - $env:COMPUTERNAME`r`nComando: $($cmd.Command)`r`n" + ('-' * 78)
        Set-Content -LiteralPath $arquivo -Value ($cabecalho + "`r`n" + $texto) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-WinForgeLog -Component $Component -Level "WARN" -Message "$Name`: saída não pôde ser gravada em '$arquivo' -> $($_.Exception.Message)"
        $arquivo = $null
    }

    $segundos = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    Write-WinForgeLog -Component $Component -Message "$Name concluído em $segundos s (código $(if ($null -ne $codigo) { $codigo } else { 'n/d' })): $($texto.Length) caractere(s)$(if ($arquivo) { " em $arquivo" } else { ' (sem arquivo)' })."
    return @{ Name = $Name; Title = $cmd.Title; Text = $texto; Path = $arquivo; ExitCode = $codigo }
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
    .PARAMETER Component
        Rótulo do log das ações da janela (Copiar, Abrir arquivo). Quem abre a janela sabe de que
        aba veio o comando; a janela em si, não.
    .PARAMETER NoShow
        Monta e devolve a janela sem mostrá-la. É o que o -SelfTest usa: abrir janela durante o build
        deixaria um build sem ninguém na frente exibindo coisa na tela.
    .OUTPUTS
        A janela ([System.Windows.Window]).
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Text = '',
        [string]$Path,
        [string]$Component = 'Command',
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
    $componenteLog = $Component
    $btnCopiar.Add_Click({
        try {
            # Clipboard.SetText lança com texto vazio ("O valor não pode ser nulo"). Saída vazia é
            # cenário normal aqui (dcdiag /q calado), e um erro no clique não ajudaria ninguém.
            if ([string]::IsNullOrEmpty($textoParaCopiar)) {
                Write-WinForgeLog -Component $componenteLog -Message "Nada a copiar: a saída de '$Title' está vazia."
                return
            }
            [System.Windows.Clipboard]::SetText($textoParaCopiar)
            Write-WinForgeLog -Component $componenteLog -Message "Saída de '$Title' copiada para a área de transferência."
        } catch {
            Write-WinForgeLog -Component $componenteLog -Level "WARN" -Message "Não foi possível copiar a saída: $($_.Exception.Message)"
        }
    }.GetNewClosure())
    $barra.Children.Add($btnCopiar) | Out-Null

    $btnArquivo = & $novoBotao 'Abrir arquivo'
    $caminhoArquivo = $Path
    $btnArquivo.IsEnabled = [bool]($caminhoArquivo -and (Test-Path -LiteralPath $caminhoArquivo))
    $btnArquivo.Add_Click({
        try { Start-Process $caminhoArquivo } catch {
            Write-WinForgeLog -Component $componenteLog -Level "WARN" -Message "Não foi possível abrir '$caminhoArquivo': $($_.Exception.Message)"
        }
    }.GetNewClosure())
    $barra.Children.Add($btnArquivo) | Out-Null

    $btnFechar = & $novoBotao 'Fechar'
    $btnFechar.Add_Click({ $janela.Close() }.GetNewClosure())
    $barra.Children.Add($btnFechar) | Out-Null

    $janela.Content = $grade
    [System.Windows.NameScope]::SetNameScope($janela, (New-Object System.Windows.NameScope))
    $janela.RegisterName('WFOutputText', $caixa)

    # .Show() e não .ShowDialog(): modal, a janela prenderia a thread da interface até alguém fechá-la,
    # e como o Dispatcher.Invoke que a abriu é síncrono, a runspace do pool ficaria presa junto - o
    # próximo comando só começaria depois de fechar esta. Modeless devolve na hora; o Owner (definido
    # acima) garante que ela continua por cima da janela principal e fecha com ela.
    if (-not $NoShow) { $janela.Show() }
    return $janela
}

# Saída pendente de janela: um slot POR CHAMADA, com chave própria, e não um único global. O slot
# nasce no runspace do comando e morre no callback, que o remove assim que o lê - nada sobrevive à
# janela. A fila guarda a ORDEM das chaves, porque o callback é chamado sem argumento e precisa
# saber qual slot é o dele.
$sync.CommandOutputs = [System.Collections.Hashtable]::Synchronized(@{})
$sync.CommandOutputQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))

# O callback da interface nasce AQUI, na runspace principal, e não dentro do runspace do comando.
# Scriptblock criado numa runspace do pool e executado pelo Dispatcher trava na primeira pipeline
# que ele tenta rodar - a thread da janela pede a runspace de origem, que está parada esperando o
# Dispatcher terminar. Foi assim que o diagnóstico morreu calado na tarefa do Plano 3.
# Invoke-WPFUIThread chama o bloco SEM argumento (Dispatcher.Invoke([action]) não passa parâmetro),
# então o que mostrar viaja pelo slot da vez; os parâmetros continuam aceitos para quem chamar direto.
$sync.WinForgeCommandOutputCallback = {
    param($Title, $Text, $Path)

    $componente = 'Command'
    try {
        if ([string]::IsNullOrWhiteSpace($Title) -and [string]::IsNullOrWhiteSpace($Text)) {
            $chave = $null
            try { if ($sync.CommandOutputQueue.Count -gt 0) { $chave = [string]$sync.CommandOutputQueue.Dequeue() } } catch { $chave = $null }
            $pendente = $null
            if (-not [string]::IsNullOrWhiteSpace($chave)) {
                $pendente = $sync.CommandOutputs[$chave]
                # Removido AQUI, e não depois de a janela abrir: o slot é desta chamada e de mais
                # ninguém. Era um único $sync.CommandOutput global, e um segundo comando que
                # terminasse antes de o Dispatcher processar o primeiro trocava o texto da janela.
                [void]$sync.CommandOutputs.Remove($chave)
            }
            if ($null -ne $pendente) {
                $Title = [string]$pendente.Title
                $Text = [string]$pendente.Text
                $Path = [string]$pendente.Path
                if ($pendente.Component) { $componente = [string]$pendente.Component }
            }
        }
        Show-WinForgeOutputWindow -Title $Title -Text $Text -Path $Path -Component $componente | Out-Null
    } catch {
        Write-WinForgeLog -Component $componente -Level "ERROR" -Message "Janela de saída falhou: $($_.Exception.Message)"
    }
}

function Invoke-WinForgeCommandButton {
    <#
    .SYNOPSIS
        Ação de um botão de comando: roda fora da thread da janela e mostra a saída numa janela.
    .DESCRIPTION
        A thread da janela não pode esperar por um dcdiag ou por um DISM: são segundos (às vezes
        minutos) com a interface congelada. O comando roda num runspace do pool e a janela de saída é
        aberta pela thread da interface, com o callback que nasceu na runspace principal.

        Um de cada vez ($sync.CommandRunning), e a trava é do PROGRAMA INTEIRO, não de uma aba: dois
        comandos em paralelo disputariam a troca de code page e a janela de saída. A trava é
        SEGURADA até o callback da janela voltar, e não solta assim que o comando termina: soltá-la
        antes deixava dois comandos entregando saída ao mesmo tempo, e o Dispatcher podia processar o
        segundo antes do primeiro. Como ela vale por toda a entrega, existe no máximo um slot de
        saída pendente por vez. O 'finally' do corpo cobre o caminho de exceção e a limpeza do slot;
        ela é zerada também no 'catch' do despacho: se o Invoke-WPFRunspace falhar (pool fechado, sem
        thread livre), o corpo nunca roda, o 'finally' dele também não, e sem esse catch o botão
        ficaria morto até fechar o programa.

        Quem confere a ferramenta é o núcleo, dentro do runspace: Get-Command sobre 'Get-MpPreference'
        ou 'Get-DnsServerScavenging' faz o Windows carregar o módulo correspondente na primeira vez,
        e na thread da janela isso é congelamento antes do primeiro caractere de saída. Ferramenta
        ausente vira texto na janela, não caixa de mensagem.

        A especificação viaja para o runspace num pacote só: Invoke-WPFRunspace passa UM argumento
        posicional (AddArgument), então spec, nome, componente e prefixo vão juntos num hashtable.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Spec,
        [Parameter(Mandatory)][string]$Name,
        [string]$Component = 'Command',
        [string]$Prefix = 'command'
    )

    if ($sync.CommandRunning) {
        [System.Windows.MessageBox]::Show("Já existe um comando em andamento. Espere ele terminar.", "WinForge", "OK", "Warning") | Out-Null
        return
    }

    $sync.CommandRunning = $true
    $corpo = {
        param($wfArgs)
        $wfChave = $null
        try {
            $wfRes = Invoke-WinForgeCommandCore -Spec $wfArgs.Spec -Name $wfArgs.Name -Component $wfArgs.Component -Prefix $wfArgs.Prefix
            # Janela fechando: Invoke-WPFUIThread é síncrono e esperaria por um Dispatcher que está
            # sendo desligado. Não há mais janela para mostrar nada - o arquivo já está gravado.
            if (-not $sync.WinForgeClosing) {
                # Slot próprio, com chave própria: o callback lê ESTE resultado e o remove. Nenhum
                # global é lido depois que a trava cai, porque a trava só cai abaixo, no 'finally'.
                $wfChave = [guid]::NewGuid().ToString('N')
                $sync.CommandOutputs[$wfChave] = @{ Title = $wfRes.Title; Text = $wfRes.Text; Path = $wfRes.Path; Component = $wfArgs.Component }
                $sync.CommandOutputQueue.Enqueue($wfChave)
                Invoke-WPFUIThread $sync.WinForgeCommandOutputCallback
            }
        } catch {
            Write-WinForgeLog -Component $wfArgs.Component -Level "ERROR" -Message "$($wfArgs.Name) falhou: $($_.Exception.Message)"
        } finally {
            # A janela pode não ter aberto (sem Dispatcher, programa fechando, exceção no meio): o
            # slot não pode ficar para trás esperando o callback do PRÓXIMO comando encontrá-lo.
            if ($wfChave -and $sync.CommandOutputs.ContainsKey($wfChave)) {
                [void]$sync.CommandOutputs.Remove($wfChave)
                try { if ($sync.CommandOutputQueue.Count -gt 0 -and [string]$sync.CommandOutputQueue.Peek() -eq $wfChave) { [void]$sync.CommandOutputQueue.Dequeue() } } catch { }
            }
            $sync.CommandRunning = $false
        }
    }

    Write-WinForgeLog -Component $Component -Message "$Name iniciado: $($Spec.Command)"
    try {
        Invoke-WPFRunspace -ScriptBlock $corpo -ArgumentList @{ Spec = $Spec; Name = $Name; Component = $Component; Prefix = $Prefix } | Out-Null
    } catch {
        $sync.CommandRunning = $false
        Write-WinForgeLog -Component $Component -Level "ERROR" -Message "$Name não pôde começar: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("O comando não pôde começar: $($_.Exception.Message)", "WinForge", "OK", "Error") | Out-Null
    }
}

#endregion
