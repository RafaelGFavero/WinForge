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

function Get-WinForgeCommandOutputRoot {
    <#
    .SYNOPSIS
        A pasta onde vivem os arquivos de saída de comando. Cria se não existir.
    .DESCRIPTION
        A mesma da sessão ($sync.logPath): quem for pedir ajuda já sabe olhar lá, e não aparece uma
        segunda pasta só para isso.

        Mora numa função própria porque tem DOIS donos - quem prepara um caminho novo e quem faz a
        retenção -, e a segunda não pode chamar a primeira: a primeira dispara a retenção, e as duas
        se chamariam em círculo.
    .OUTPUTS
        O caminho da pasta.
    #>
    param()

    $dir = $null
    if ($null -ne $sync -and $sync.logPath) { $dir = Split-Path -Parent $sync.logPath }
    # Get-WinForgeUserDataRoot, e não $env:LocalAppData: a mesma regra das outras pastas do motor.
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = Join-Path (Get-WinForgeUserDataRoot) 'WinForge\logs' }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return [string]$dir
}

function Get-WinForgeCommandOutputPath {
    <#
    .SYNOPSIS
        Prepara e devolve o caminho do arquivo de saída de um comando:
        <prefixo>-<Nome>-<aaaaMMdd-HHmmss>.txt na pasta de logs.
    .DESCRIPTION
        Com os segundos no nome, dois cliques seguidos não se sobrescrevem.

        O prefixo é de quem chama ('server', 'repair', 'command'): assim os arquivos de abas
        diferentes convivem na mesma pasta sem se confundirem, e uma listagem por prefixo continua
        trazendo só os de uma.

        PREPARA, e não só calcula: além de criar a pasta, é AQUI que a retenção do prefixo roda. Este
        é o único ponto por onde todo arquivo de saída passa - a aba Servidor, os botões de leitura e
        o fluxo ao vivo do reparo -, e pendurar a limpeza em quem CRIA o arquivo deixava de fora
        todos menos um: era só 'repair' que encolhia, e 'server' e 'command' cresciam para sempre.

        A limpeza roda antes de o arquivo desta execução existir, então a pasta fica com os 20
        anteriores MAIS o de agora. O teto é da fila que já estava lá, e não do conteúdo da pasta no
        instante seguinte - 21 arquivos em vez de 20 não é o que essa retenção existe para evitar.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Prefix = 'command'
    )

    $dir = Get-WinForgeCommandOutputRoot
    [void](Remove-WinForgeOldCommandOutput -Prefix $Prefix -Root $dir)
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

function Get-WinForgeOutputEncoding {
    <#
    .SYNOPSIS
        A decodificação da saída de um executável, escolhida pelo NOME: 'oem', 'ansi', 'utf8' ou
        'unicode'.
    .DESCRIPTION
        Os quatro destinos num lugar só, porque o mesmo nome serve aos dois caminhos de
        Invoke-WinForgeNativeCommand (a troca de code page do processo e o StandardOutputEncoding do
        fluxo ao vivo) e escrever a escolha duas vezes é escrevê-la para envelhecer pela metade.

        Não há regra geral: cada executável do Windows escolhe a sua, e a única forma de saber é
        MEDIR os bytes que ele escreve quando a saída é redirecionada. Medido nesta base de código
        numa máquina pt-BR (OEM 850, ANSI 1252), com o mesmo ProcessStartInfo do fluxo ao vivo:

        - 'oem' (padrão): DISM ('õ' = 0xE4), icacls ('à' = 0x85), w32tm ('ç' = 0x87) e
          takeown ('á' = 0xA0). São os bytes da code page 850.
        - 'ansi': chkdsk ('ó' = 0xF3, que em 850 seria 0xA2). Era o desvio invisível: lido como
          OEM, o "concluídos" dele chegava à janela como 'concluÝdos' e o "Estágio" como 'EstÃgio'.
        - 'utf8': winget e netsh (o 'ç' deles sai como 0xC3 0xA7, dois bytes). O netsh já estava
          medido assim no perfil e na aba Servidor; aqui ele estava marcado como OEM.
        - 'unicode' (UTF-16LE): sfc, que TROCA de codificação quando a saída é redirecionada. Lido
          como OEM, cada caractere vira uma letra seguida de um byte zero.

        Nome desconhecido cai em OEM em vez de estourar: um passo com a dica errada tem de mostrar
        acento embaralhado, não derrubar o reparo no meio. Quem cobra o nome certo é o -SelfTest,
        que confere a dica de todo passo de executável das linhas com fluxo ao vivo.

        UTF8Encoding($false): sem BOM. Com BOM, os três bytes iniciais entrariam no texto da primeira
        linha da saída.
    .PARAMETER Name
        'oem', 'ansi', 'utf8' ou 'unicode'. Vazio ou desconhecido vale 'oem'.
    .OUTPUTS
        [System.Text.Encoding].
    #>
    param([string]$Name = 'oem')

    switch (([string]$Name).Trim().ToLowerInvariant()) {
        'unicode' { return [System.Text.Encoding]::Unicode }
        'utf8' { return (New-Object System.Text.UTF8Encoding $false) }
        'ansi' {
            try { return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage) } catch { return [System.Text.Encoding]::Default }
        }
    }
    try { return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) } catch { return [System.Text.Encoding]::Default }
}

function Format-WinForgeProcessArguments {
    <#
    .SYNOPSIS
        Junta um vetor de argumentos na linha de comando única que o ProcessStartInfo exige.
    .DESCRIPTION
        O .NET Framework 4.x não tem ArgumentList: o ProcessStartInfo recebe UM texto, e quem separa
        os argumentos de volta é o analisador do próprio executável. A citação segue a regra do CRT
        do Windows, que é a que quase todo executável usa: aspas em volta do argumento que tem espaço
        ou aspas, barras invertidas dobradas antes de uma aspa.

        Argumento sem espaço e sem aspas sai como está - '/scannow' entre aspas confundiria mais de
        um utilitário antigo do Windows.

        Vale a mesma regra de Invoke-WinForgeNativeCommand: aqui só entram literais do próprio
        programa. Isto é montagem de linha de comando, não sanitização de entrada.
    .OUTPUTS
        Texto da linha de comando (sem o nome do executável).
    #>
    param([string[]]$Arguments = @())

    $partes = @()
    foreach ($arg in @($Arguments)) {
        $texto = [string]$arg
        if ($texto -notmatch '[\s"]') { $partes += $texto; continue }
        # Cada barra invertida imediatamente antes da aspa de fechamento (ou de uma aspa interna)
        # precisa ser dobrada, senão ela escapa a aspa e o argumento sangra para o seguinte.
        $escapado = [regex]::Replace($texto, '(\\*)"', '$1$1\"')
        $escapado = [regex]::Replace($escapado, '(\\+)$', '$1$1')
        $partes += '"' + $escapado + '"'
    }
    return ($partes -join ' ')
}

function Open-WinForgeStreamWriter {
    <#
    .SYNOPSIS
        O escritor PERSISTENTE do arquivo que a janela de saída acompanha. Um por caminho.
    .DESCRIPTION
        Era um StreamWriter novo POR LINHA - abrir, escrever, fechar. Numa fase 5 com 338 pastas,
        cada uma com o cabeçalho '> icacls ...' e a resposta do icacls, isso é abrir e fechar o
        mesmo arquivo milhares de vezes: medido, duas ordens de grandeza mais lento do que escrever
        pelo escritor que já está aberto.

        UM escritor por caminho, e é por isso que Invoke-WinForgeStreamedProcess também pega o dele
        AQUI em vez de abrir o seu: dois StreamWriter em ACRÉSCIMO sobre o mesmo arquivo não se
        somam. Cada FileStream guarda a própria posição, e o segundo escreve por cima do que o
        primeiro escreveu - e, antes disso, o próprio Windows recusa a segunda abertura, porque o
        compartilhamento padrão do StreamWriter(path, append) é FileShare.Read.

        O compartilhamento é ReadWrite|Delete de propósito: a janela lê o arquivo de meio em meio
        segundo enquanto ele é escrito (Invoke-WinForgeFollowTick abre com os mesmos três) e o
        -SelfTest apaga arquivos de prova com o escritor ainda aberto. Quem NÃO lê assim é
        '[System.IO.File]::ReadAllText', que pede FileShare.Read e recusa um arquivo com escritor
        aberto - MEDIDO; 'Get-Content' lê.

        AutoFlush ligado: sem o flush, a janela leria um arquivo vazio até o buffer de 4 KB encher,
        que num sfc é o comando inteiro. O BOM só é escrito quando o arquivo está VAZIO - o
        StreamWriter olha a posição do fluxo, e num acréscimo a um arquivo que já tem cabeçalho ela
        nasce maior que zero.

        Quem fecha é Close-WinForgeStreamWriter, no 'finally' do corpo da runspace. Até lá o
        escritor fica no cache e todo mundo que escreve neste caminho usa o mesmo.
    .OUTPUTS
        [System.IO.StreamWriter].
    #>
    param([Parameter(Mandatory)][string]$Path)

    $existente = $sync.WinForgeStreamWriters[$Path]
    if ($null -ne $existente) { return $existente }
    $fluxo = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    $escritor = New-Object System.IO.StreamWriter($fluxo, (New-Object System.Text.UTF8Encoding $true))
    $escritor.AutoFlush = $true
    $sync.WinForgeStreamWriters[$Path] = $escritor
    return $escritor
}

function Close-WinForgeStreamWriter {
    <#
    .SYNOPSIS
        Fecha o escritor persistente de um caminho e o tira do cache.
    .DESCRIPTION
        Sai do cache ANTES de ser fechado: um Dispose que estoure (o flush final num disco cheio)
        não pode deixar para trás um escritor morto que a próxima escrita neste caminho
        reutilizaria. Caminho sem escritor é silêncio, e não erro - o 'finally' do corpo da runspace
        chama esta função mesmo quando nenhum passo chegou a escrever coisa alguma.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $escritor = $sync.WinForgeStreamWriters[$Path]
    if ($null -eq $escritor) { return }
    [void]$sync.WinForgeStreamWriters.Remove($Path)
    try { $escritor.Dispose() } catch { }
}

function Write-WinForgeStreamLine {
    <#
    .SYNOPSIS
        Acrescenta uma linha ao arquivo que a janela de saída está acompanhando.
    .DESCRIPTION
        Existe para o cabeçalho de cada passo ('> netsh.exe winsock reset') e para as frases finais
        chegarem ao arquivo pelo MESMO caminho que a saída dos executáveis - mesmo escritor, mesma
        codificação, mesma forma de abrir o arquivo. O escritor é o persistente de
        Open-WinForgeStreamWriter, e é lá que está o porquê de ser um só por arquivo.

        Falha de escrita não derruba o comando: o passo seguinte importa mais do que uma linha de
        cabeçalho, e a saída de verdade continua indo para o mesmo arquivo.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Text = ''
    )

    try { (Open-WinForgeStreamWriter -Path $Path).WriteLine([string]$Text) } catch { }
}

function Enter-WinForgeStreamProtected {
    <#
    .SYNOPSIS
        Abre a janela em que o cancelamento NÃO vale para este arquivo de saída.
    .DESCRIPTION
        Existe para o trecho que não pode ser interrompido no meio. O caso que a define: entre
        "posse da pasta para os Administradores" e "posse de volta ao dono padrão", parar deixa uma
        pasta do sistema pertencendo aos Administradores - aberta a qualquer processo elevado, que é
        um estrago pior do que o reparo não terminar.

        Dentro dela o pedido do usuário continua sendo GUARDADO: ele não some, só não vence. Quando
        a janela fecha, ele passa a valer no passo seguinte. Quem chama é a Tarefa 12.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $sync.WinForgeStreamProtected[$Path] = $true
}

function Exit-WinForgeStreamProtected {
    <#
    .SYNOPSIS
        Fecha a janela protegida deste arquivo de saída. O pedido guardado volta a valer.
    .DESCRIPTION
        Sai do dicionário em vez de virar $false: chave ausente e chave falsa respondem a mesma coisa
        em Test-WinForgeStreamCancelled, e uma a menos é uma a menos para limpar no fim.
    #>
    param([Parameter(Mandatory)][string]$Path)

    [void]$sync.WinForgeStreamProtected.Remove($Path)
}

function Test-WinForgeStreamCancelled {
    <#
    .SYNOPSIS
        Diz se o comando deste arquivo de saída foi cancelado. Só lê.
    .DESCRIPTION
        Responde $false enquanto a janela protegida estiver aberta, mesmo com o pedido levantado: é
        assim que o pedido fica GUARDADO em vez de vencer no meio de uma troca de posse. Quem
        pergunta é o laço dos passos, entre um passo e o seguinte.

        Falha de leitura responde $false. Um dicionário que não pôde ser lido não é motivo para
        interromper um reparo pela metade - o lado seguro aqui é continuar.
    .OUTPUTS
        [bool].
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        if ([bool]$sync.WinForgeStreamProtected[$Path]) { return $false }
        return [bool]$sync.WinForgeStreamCancel[$Path]
    } catch { return $false }
}

function Write-WinForgeStreamCancelNote {
    <#
    .SYNOPSIS
        Escreve, UMA vez por arquivo, a linha que diz que o resto não foi iniciado.
    .DESCRIPTION
        Depois do Parar, TODO passo seguinte passa pela recusa - e numa fase 5 de perfil são
        centenas deles. Uma linha por recusa seria o próximo despejo a encher a janela, e diria
        sempre a mesma coisa. A marca de "já avisei" mora em '$sync.WinForgeStreamCancelNoted', pela
        mesma chave e com o mesmo tempo de vida do escritor.

        Dois chamadores, e é por isso que ela é função: quem recusa o processo
        (Invoke-WinForgeStreamedProcess) e quem recusa o passo antes de escrever o cabeçalho
        (Invoke-WinForgeAclStreamStep). A contagem tem de ser a mesma para os dois.
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        if ([bool]$sync.WinForgeStreamCancelNoted[$Path]) { return }
        $sync.WinForgeStreamCancelNoted[$Path] = $true
    } catch { return }
    Write-WinForgeStreamLine -Path $Path -Text ''
    Write-WinForgeStreamLine -Path $Path -Text '== Parado a pedido: os passos seguintes não foram iniciados. =='
}

function Request-WinForgeStreamCancel {
    <#
    .SYNOPSIS
        Pede o cancelamento do comando deste arquivo de saída: levanta a marca e mata a árvore de
        processos.
    .DESCRIPTION
        Duas metades, e as duas fazem falta:

        1. A MARCA, que o laço dos passos lê entre um passo e o seguinte. Sozinha ela só impede o
           PRÓXIMO passo de começar - um sfc que já está rodando levaria meia hora para terminar.
        2. O JOB OBJECT, que mata o processo que está rodando AGORA e toda a árvore dele de uma vez.
           Medido: 'Stop-Process -Force' sobre o powershell.exe deixa vivo o filho iniciado com
           UseShellExecute=$false, e era assim que fechar o WinForge deixava um icacls.exe elevado
           reescrevendo permissões do sistema sem ninguém olhando.

        Dentro da janela protegida ele NÃO mata nada: a marca fica guardada e vale a partir do passo
        seguinte. É o que separa "parar" de "parar no pior instante possível".

        RESSALVA do '-NoElevate': ali o WinForge roda sem elevação e os processos filhos também, mas
        um comando que já tenha sido lançado elevado por outro caminho fica fora do alcance - MEDIDO,
        OpenProcess sobre processo elevado, a partir de pai não elevado, devolve handle 0 e erro 5.
        O Parar promete o que ele alcança, e num processo não elevado esse alcance é o próprio job.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string> }. 'Ok' é a marca levantada, e não a morte do processo:
        um comando entre passos não tem processo nenhum para matar, e isso é sucesso.
    #>
    param([Parameter(Mandatory)][string]$Path)

    try { $sync.WinForgeStreamCancel[$Path] = $true } catch { return @{ Ok = $false; Reason = 'o pedido de cancelamento não pôde ser registrado' } }
    $protegido = $false
    try { $protegido = [bool]$sync.WinForgeStreamProtected[$Path] } catch { $protegido = $false }
    if ($protegido) {
        return @{ Ok = $true; Reason = 'a etapa atual não pode ser interrompida no meio; o pedido foi guardado e vale a partir do próximo passo' }
    }
    $trabalho = [IntPtr]::Zero
    try { if ($null -ne $sync.WinForgeStreamJob[$Path]) { $trabalho = [IntPtr]$sync.WinForgeStreamJob[$Path] } } catch { $trabalho = [IntPtr]::Zero }
    if ($trabalho -eq [IntPtr]::Zero -or -not ('WfJob' -as [type])) {
        return @{ Ok = $true; Reason = 'nenhum processo em andamento; o comando para no próximo passo' }
    }
    try { [void][WfJob]::TerminateJobObject($trabalho, 1) } catch { return @{ Ok = $true; Reason = "a marca foi levantada, mas a árvore de processos não pôde ser encerrada ($($_.Exception.Message))" } }
    return @{ Ok = $true; Reason = '' }
}

function Invoke-WinForgeStreamedProcess {
    <#
    .SYNOPSIS
        Roda um executável escrevendo cada linha num arquivo enquanto ela sai. Devolve texto e código.
    .DESCRIPTION
        O miolo do -StreamTo de Invoke-WinForgeNativeCommand, separado porque não tem nada em comum
        com o outro caminho: não troca a code page do processo, não pega o mutex e não usa
        $LASTEXITCODE. Ver a documentação de -StreamTo para o porquê de cada uma dessas três.

        O escritor vem de Open-WinForgeStreamWriter (persistente, um por arquivo) e NÃO é fechado
        aqui: quem fecha é o 'finally' do corpo da runspace, quando o comando inteiro termina. Ele é
        pedido ANTES do Start(), e não depois: se o arquivo não puder ser aberto (a pasta sumiu, o
        disco encheu, um antivírus segurou o identificador), a falha acontece com o processo ainda
        parado, em vez de deixar um sfc de meia hora rodando sem ninguém para ler a saída dele - e
        sem ninguém para pará-lo, porque quem chama já terá recebido a exceção.

        OS DOIS FLUXOS SÃO LIDOS JUNTOS, linha a linha, com ReadLineAsync e Task.WaitAny na thread
        de quem chama. São três defeitos num desenho só, e cada peça responde por um:

        1. O ReadToEndAsync do fluxo de erro juntava o erro INTEIRO na memória até o processo
           terminar. Num icacls de perfil o erro É o volume, e era ele que a fase 5 empilhava.
        2. Ler a saída até o fim e SÓ ENTÃO olhar o erro trava os dois lados: o cano tem 4 KB, e um
           processo que enche o buffer de erro para de escrever enquanto nós esperamos a saída que
           ele não vai mandar. Esperar os dois juntos é o que impede isso.
        3. E o pump do erro NÃO pode ser uma Task do .NET rodando um scriptblock convertido em
           delegate: MEDIDO nesta máquina, no PowerShell 5.1, ele morre com "Não há Runspace
           disponível para executar scripts neste thread", a Task fica 'Faulted' e ninguém lê o
           fluxo de erro - o defeito 2 de volta, agora calado. É a mesma regra que já proíbe
           manipulador de evento aqui, e é por isso que a leitura assíncrona é de .NET puro: quem
           espera é esta thread, que tem runspace.

        Com uma thread só escrevendo no arquivo, não há duas linhas se intercalando no meio de um
        caractere - e nenhuma trava é necessária para garantir isso.
    .PARAMETER NoCapture
        Não junta o texto para devolver: 'Text' volta vazio. É para quem só quer o código de saída -
        as fases 3 a 5 das permissões -, porque acumular centenas de MB num StringBuilder para
        descartá-los no fim é exatamente o consumo de memória que o fluxo ao vivo existe para tirar.
    .OUTPUTS
        @{ Text = <string>; ExitCode = <int> }. Com -NoCapture, Text = ''.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$StreamTo,
        [Parameter(Mandatory)][System.Text.Encoding]$Encoding,
        [switch]$NoCapture
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = Format-WinForgeProcessArguments -Arguments $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Encoding
    $psi.StandardErrorEncoding = $Encoding

    $processo = New-Object System.Diagnostics.Process
    $processo.StartInfo = $psi
    $acumulado = if ($NoCapture) { $null } else { New-Object System.Text.StringBuilder }
    $codigo = $null
    try {
        $escritor = Open-WinForgeStreamWriter -Path $StreamTo
        # O Job Object nasce ANTES do processo, e a atribuição acontece na linha seguinte ao Start():
        # não há como atribuir um processo que ainda não existe, e este é o instante mais cedo
        # possível. KILL_ON_JOB_CLOSE fecha o outro buraco: morto o WinForge pelo Gerenciador de
        # Tarefas, o handle do job morre com ele e o Windows derruba a árvore - é o que impede um
        # icacls.exe elevado de continuar reescrevendo permissão sem ninguém olhando.
        #
        # A janela PROTEGIDA fica de fora de propósito: processo que não está em job nenhum não é
        # morto por TerminateJobObject, e é assim que a troca de posse da Fase 4 não pode ser
        # interrompida no meio nem por engano.
        #
        # Sem o tipo (chamada fora do corpo da runspace, como no -SelfTest) o comando roda igual,
        # só sem Parar: o job é um extra, não um pré-requisito.
        # O PARAR, conferido AQUI e não só entre passos. A restauração de permissões inteira é UM
        # passo para o motor, e as fases 3 a 5 disparam um processo atrás do outro: matar o processo
        # da vez não adiantava nada, porque o laço lançava o seguinte, com um job novo, até o fim -
        # a janela dizia "Parando" enquanto o reparo terminava inteiro.
        #
        # Esta é a conferência de PONTO ÚNICO: todo laço fica coberto sem ninguém precisar lembrar de
        # checar em cada um, porque todo processo do fluxo ao vivo passa por aqui. 1223 é
        # ERROR_CANCELLED, e não um código que algum icacls possa devolver por conta própria.
        if (Test-WinForgeStreamCancelled -Path $StreamTo) {
            Write-WinForgeStreamCancelNote -Path $StreamTo
            return @{ Text = ''; ExitCode = 1223 }
        }
        $trabalho = [IntPtr]::Zero
        $protegido = $false
        try { $protegido = [bool]$sync.WinForgeStreamProtected[$StreamTo] } catch { $protegido = $false }
        if (-not $protegido -and ('WfJob' -as [type])) {
            try {
                $trabalho = [WfJob]::CreateJobObject([IntPtr]::Zero, $null)
                if ($trabalho -ne [IntPtr]::Zero) {
                    # JOBOBJECT_EXTENDED_LIMIT_INFORMATION: 144 bytes em 64 bits, 112 em 32. O campo
                    # LimitFlags está em 16 nos dois, e 0x2000 é JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE.
                    $tamanho = $(if ([IntPtr]::Size -eq 8) { 144 } else { 112 })
                    $info = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($tamanho)
                    try {
                        for ($z = 0; $z -lt $tamanho; $z += 4) { [System.Runtime.InteropServices.Marshal]::WriteInt32($info, $z, 0) }
                        [System.Runtime.InteropServices.Marshal]::WriteInt32($info, 16, 0x2000)
                        [void][WfJob]::SetInformationJobObject($trabalho, 9, $info, [uint32]$tamanho)
                    } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($info) }
                    $sync.WinForgeStreamJob[$StreamTo] = $trabalho
                }
            } catch { $trabalho = [IntPtr]::Zero }
        }
        # O teto do ARQUIVO desta execução, já estourado por um passo anterior ou não. Passado o
        # teto, as linhas continuam sendo LIDAS (parar de ler enche o cano de 4 KB e trava os dois
        # lados) e deixam de ser escritas.
        $estourou = $false
        try { $estourou = [bool]$sync.WinForgeStreamCapped[$StreamTo] } catch { $estourou = $false }
        # De 2000 em 2000 linhas, e não a cada linha: o teto existe para pegar um arquivo que cresce
        # sem parar, e um Get-Item por linha seria um acesso a disco por linha.
        $desdeAConta = 0
        [void]$processo.Start()
        if ($trabalho -ne [IntPtr]::Zero) { try { [void][WfJob]::AssignProcessToJobObject($trabalho, $processo.Handle) } catch { } }
        $tSaida = $processo.StandardOutput.ReadLineAsync()
        $tErro = $processo.StandardError.ReadLineAsync()
        while ($null -ne $tSaida -or $null -ne $tErro) {
            if ($null -eq $tErro) { $tSaida.Wait() }
            elseif ($null -eq $tSaida) { $tErro.Wait() }
            else { [void][System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($tSaida, $tErro)) }
            if ($null -ne $tSaida -and $tSaida.IsCompleted) {
                $linha = $tSaida.Result
                if ($null -eq $linha) {
                    $tSaida = $null
                } else {
                    if (-not $estourou) {
                        $escritor.WriteLine($linha)
                        if ($null -ne $acumulado) { [void]$acumulado.AppendLine($linha) }
                        $desdeAConta++
                    }
                    $tSaida = $processo.StandardOutput.ReadLineAsync()
                }
            }
            if ($null -ne $tErro -and $tErro.IsCompleted) {
                $linha = $tErro.Result
                if ($null -eq $linha) {
                    $tErro = $null
                } else {
                    if (-not $estourou) {
                        $escritor.WriteLine("[erro] $linha")
                        if ($null -ne $acumulado) { [void]$acumulado.AppendLine("[erro] $linha") }
                        $desdeAConta++
                    }
                    $tErro = $processo.StandardError.ReadLineAsync()
                }
            }
            if ($desdeAConta -ge 2000) {
                $desdeAConta = 0
                $teto = Test-WinForgeStreamFileCap -Path $StreamTo
                if ($teto.Over) {
                    $estourou = $true
                    # UMA linha por arquivo, e não por processo: numa fase 5 de 338 pastas são 338
                    # chamadas de processo sobre o MESMO arquivo, e o aviso repetido seria o próximo
                    # despejo a encher o disco.
                    $escritor.WriteLine([string]$teto.Text)
                    $sync.WinForgeStreamCapped[$StreamTo] = $true
                }
            }
        }
        $processo.WaitForExit()
        $codigo = $processo.ExitCode
    } finally {
        # O handle sai do dicionário ANTES de ser fechado: um Parar que chegasse entre as duas
        # linhas encontraria um handle já morto. E o fechamento é o que dispara KILL_ON_JOB_CLOSE -
        # aqui o processo já terminou, e no caminho de exceção é exatamente o que se quer.
        if ($trabalho -ne [IntPtr]::Zero) {
            [void]$sync.WinForgeStreamJob.Remove($StreamTo)
            try { [void][WfJob]::CloseHandle($trabalho) } catch { }
        }
        try { $processo.Dispose() } catch { }
    }

    return @{ Text = $(if ($null -ne $acumulado) { $acumulado.ToString() } else { '' }); ExitCode = $codigo }
}

function Invoke-WinForgeNativeCommand {
    <#
    .SYNOPSIS
        Roda um comando externo e devolve o texto (decodificado como -Encoding pedir) junto com o
        código de saída.
    .DESCRIPTION
        Duas armadilhas de executável no PowerShell moram aqui, e é por isso que existe um lugar só
        para elas - a aba Servidor e o perfil do sistema caíam nas duas em separado:

        1. A code page. w32tm, dcdiag e repadmin escrevem em OEM (850/437 no Brasil); o winget e o
           netsh escrevem UTF-8, o chkdsk escreve ANSI e o sfc troca para UTF-16LE quando a saída é
           redirecionada. O PowerShell decodifica pelo [Console]::OutputEncoding, que costuma estar
           em outra coisa - e toda palavra acentuada chega embaralhada. Qual é qual está medido em
           Get-WinForgeOutputEncoding. A troca é PROCESSO INTEIRO, então a janela é a
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
    .PARAMETER Encoding
        Como decodificar a saída deste executável: 'oem' (padrão), 'ansi', 'utf8' ou 'unicode'. A
        escolha é POR EXECUTÁVEL e medida, não suposta - ver Get-WinForgeOutputEncoding, que tem a
        tabela dos bytes que cada um escreve. No caminho normal a troca é do PROCESSO INTEIRO e
        continua serializada pelo mesmo mutex; só o destino muda.
    .PARAMETER StreamTo
        Caminho de um arquivo que recebe cada linha ASSIM QUE ELA SAI, em vez de tudo no fim. É o que
        deixa a janela de saída mostrar um sfc ou um DISM enquanto eles rodam, em vez de ficar vazia
        por meia hora e despejar tudo de uma vez.

        Este caminho não passa pela troca de code page do processo (e portanto não passa pelo mutex):
        quem decodifica é o próprio Process, pelo StandardOutputEncoding, que vale só para ele. Como
        efeito colateral bom, dois comandos com fluxo ao vivo não disputam nada entre si.

        O fluxo de erro é lido linha a linha, de forma assíncrona e de .NET puro, ao mesmo tempo que
        o da saída - e não por um manipulador de evento em PowerShell nem por um scriptblock numa
        thread do pool de threads: os dois voltam a chamar o PowerShell de fora da runspace, que é a
        receita de travamento desta base de código. Sem leitura paralela nenhuma, um comando falante
        no fluxo de erro encheria o buffer do cano (4 KB) e ficaria parado esperando alguém
        esvaziá-lo enquanto nós esperamos o fluxo de saída - travamento dos dois lados. As linhas de
        erro entram no arquivo com o prefixo '[erro]', na ordem em que chegam.
    .PARAMETER NoCapture
        Só com -StreamTo: descarta o texto em vez de acumulá-lo, e 'Text' volta vazio. Para quem só
        precisa do código de saída - guardar centenas de MB num StringBuilder para jogar fora no fim
        é o consumo de memória que o fluxo ao vivo existe para tirar do caminho.
    .OUTPUTS
        @{ Text = <string>; ExitCode = <int> }. Com -NoCapture, Text = ''.
    #>
    param(
        [string]$Command,
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$StreamTo,
        [string]$Encoding = 'oem',
        [switch]$NoCapture
    )

    if ([string]::IsNullOrWhiteSpace($Command) -and [string]::IsNullOrWhiteSpace($FilePath)) {
        throw "Invoke-WinForgeNativeCommand precisa de -Command ou de -FilePath."
    }
    if (-not [string]::IsNullOrWhiteSpace($Command) -and -not [string]::IsNullOrWhiteSpace($FilePath)) {
        throw "Invoke-WinForgeNativeCommand aceita -Command OU -FilePath, não os dois."
    }
    if (-not [string]::IsNullOrWhiteSpace($StreamTo) -and [string]::IsNullOrWhiteSpace($FilePath)) {
        throw "Invoke-WinForgeNativeCommand -StreamTo só vale com -FilePath: pipeline de cmdlet não tem fluxo para acompanhar."
    }
    # -NoCapture sem -StreamTo seria descartar a saída sem tê-la mandado para lugar nenhum: o
    # chamador ficaria com o código de saída e com mais nada. É engano de quem chama, não opção.
    if ($NoCapture -and [string]::IsNullOrWhiteSpace($StreamTo)) {
        throw "Invoke-WinForgeNativeCommand -NoCapture só vale com -StreamTo: sem fluxo ao vivo, descartar o texto é descartar o resultado."
    }

    if (-not [string]::IsNullOrWhiteSpace($StreamTo)) {
        return Invoke-WinForgeStreamedProcess -FilePath $FilePath -Arguments $Arguments -StreamTo $StreamTo -Encoding (Get-WinForgeOutputEncoding -Name $Encoding) -NoCapture:$NoCapture
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
            [Console]::OutputEncoding = Get-WinForgeOutputEncoding -Name $Encoding
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
    .PARAMETER FollowPath
        Arquivo a ACOMPANHAR enquanto ele cresce, em vez de mostrar um texto pronto. A janela abre
        na hora com o que o arquivo já tem e um relógio de meio em meio segundo traz o resto
        (Invoke-WinForgeFollowTick). O cabeçalho diz "Em andamento: <título> (mm:ss)" e vira
        "Concluído em mm:ss (código N)" quando $sync.WinForgeStreamDone[<arquivo>] é marcado.

        Meio segundo é o intervalo porque é o que separa "ao vivo" de "piscando": um DISM escreve
        dezenas de linhas de progresso por segundo, e um relógio de 100 ms faria a caixa de texto
        rolar mais do que ler.
    .PARAMETER ExpectMinutes
        Quanto a linha que está rodando costuma levar, em minutos. Vai para a Tag e é o que deixa o
        cabeçalho ficar âmbar a 1,5x e urgente a 3x (Get-WinForgeFollowHeader). Zero desliga o aviso:
        sem estimativa não há atraso a acusar.
    .PARAMETER NoShow
        Monta e devolve a janela sem mostrá-la, e NÃO liga o relógio do -FollowPath. É o que o
        -SelfTest usa: abrir janela durante o build deixaria um build sem ninguém na frente exibindo
        coisa na tela, e um relógio sem laço de mensagens nunca bateria - quem dá o tique lá é o
        próprio teste, chamando Invoke-WinForgeFollowTick.
    .OUTPUTS
        A janela ([System.Windows.Window]).
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Text = '',
        [string]$Path,
        [string]$FollowPath,
        [int]$ExpectMinutes = 0,
        [string]$Component = 'Command',
        [switch]$NoShow
    )

    # Acompanhando um arquivo, é ele que o botão "Abrir arquivo" abre: não há outro.
    if ([string]::IsNullOrWhiteSpace($Path) -and -not [string]::IsNullOrWhiteSpace($FollowPath)) { $Path = $FollowPath }

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
    $linhaCabecalho = New-Object System.Windows.Controls.RowDefinition
    $linhaCabecalho.Height = [System.Windows.GridLength]::Auto
    $linhaTexto = New-Object System.Windows.Controls.RowDefinition
    $linhaTexto.Height = New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star)
    $linhaBotoes = New-Object System.Windows.Controls.RowDefinition
    $linhaBotoes.Height = [System.Windows.GridLength]::Auto
    $grade.RowDefinitions.Add($linhaCabecalho)
    $grade.RowDefinitions.Add($linhaTexto)
    $grade.RowDefinitions.Add($linhaBotoes)

    # O cabeçalho existe SEMPRE (é o que amarra a numeração das linhas da grade), mas só aparece
    # quando há algo acontecendo: numa saída pronta não há o que informar, e uma faixa vazia no topo
    # só roubaria altura do texto.
    $cabecalho = New-Object System.Windows.Controls.TextBlock
    $cabecalho.Foreground = $frente
    $cabecalho.Margin = New-Object System.Windows.Thickness (0, 0, 0, 8)
    $cabecalho.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $cabecalho.Visibility = [System.Windows.Visibility]::Collapsed
    [System.Windows.Controls.Grid]::SetRow($cabecalho, 0)
    $grade.Children.Add($cabecalho) | Out-Null

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
    [System.Windows.Controls.Grid]::SetRow($caixa, 1)
    $grade.Children.Add($caixa) | Out-Null

    $barra = New-Object System.Windows.Controls.StackPanel
    $barra.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $barra.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $barra.Margin = New-Object System.Windows.Thickness (0, 10, 0, 0)
    [System.Windows.Controls.Grid]::SetRow($barra, 2)
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
    # O texto sai da CAIXA, e não do parâmetro: numa janela que acompanha um arquivo o parâmetro
    # está vazio, e copiar o que a pessoa está vendo é o que ela espera dos dois jeitos.
    $componenteLog = $Component
    $btnCopiar.Add_Click({
        try {
            $textoParaCopiar = [string]$caixa.Text
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
    $janela.RegisterName('WFOutputHeader', $cabecalho)

    if (-not [string]::IsNullOrWhiteSpace($FollowPath)) {
        $cabecalho.Visibility = [System.Windows.Visibility]::Visible
        # As cores dos três níveis do cabeçalho, resolvidas UMA vez e guardadas na Tag: o tique bate
        # de meio em meio segundo, e perguntar ao dicionário de recursos a cada batida é trabalho sem
        # resposta nova. A reserva segue a mesma regra do fundo e do texto lá em cima - o -SelfTest
        # monta esta janela antes de a janela principal existir, e sem ela o cabeçalho ficaria sem
        # pincel nenhum justamente no teste que confere a troca de cor.
        $aviso = $null
        $urgente = $null
        if ($null -ne $sync -and $null -ne $sync.Form) {
            try { $aviso = $sync.Form.Resources['HeaderWarningColor'] } catch { $aviso = $null }
            try { $urgente = $sync.Form.Resources['HeaderUrgentColor'] } catch { $urgente = $null }
        }
        if ($null -eq $aviso) { $aviso = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(245, 158, 11)) }
        if ($null -eq $urgente) { $urgente = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(239, 68, 68)) }
        # Todo o estado do acompanhamento mora na Tag, e não em variáveis fechadas dentro de um
        # scriptblock: é o que deixa Invoke-WinForgeFollowTick ser uma função de arquivo, chamável
        # tanto pelo relógio quanto pelo -SelfTest, sem um scriptblock por janela.
        $janela.Tag = @{
            Path          = $FollowPath
            Offset        = [long]0
            Start         = (Get-Date)
            Title         = $Title
            Box           = $caixa
            Header        = $cabecalho
            Timer         = $null
            # Quanto esta linha costuma levar. É daqui que sai o âmbar de 1,5x e o urgente de 3x.
            ExpectMinutes = [int]$ExpectMinutes
            Pinceis       = @{ normal = $frente; ambar = $aviso; urgente = $urgente }
            # Quantos caracteres a caixa tem, contados por nós. Ler '$caixa.Text' MATERIALIZA a
            # string inteira - até 4 MB -, e perguntar o tamanho a cada meio segundo seria copiar
            # 4 MB por tique só para descobrir que não precisa cortar nada. Com o contador, a caixa
            # só é lida no tique em que o corte acontece.
            Chars         = [int]([string]$caixa.Text).Length
        }
        # Primeira leitura antes de mostrar: a janela abre já com o que o arquivo tem, e não em
        # branco por meio segundo.
        Invoke-WinForgeFollowTick -Window $janela
        if (-not $NoShow) {
            $relogio = New-Object System.Windows.Threading.DispatcherTimer
            $relogio.Interval = [TimeSpan]::FromMilliseconds(500)
            $relogio.Add_Tick({ Invoke-WinForgeFollowTick -Window $janela }.GetNewClosure())
            $janela.Tag.Timer = $relogio
            # Janela fechada no meio de um DISM: o comando continua (o arquivo é o resultado), mas
            # um relógio batendo sobre uma caixa de texto que já morreu não serve a ninguém.
            $janela.Add_Closed({ try { $relogio.Stop() } catch { } }.GetNewClosure())
            $relogio.Start()
        }
    }

    # .Show() e não .ShowDialog(): modal, a janela prenderia a thread da interface até alguém fechá-la,
    # e como o Dispatcher.Invoke que a abriu é síncrono, a runspace do pool ficaria presa junto - o
    # próximo comando só começaria depois de fechar esta. Modeless devolve na hora; o Owner (definido
    # acima) garante que ela continua por cima da janela principal e fecha com ela.
    if (-not $NoShow) { $janela.Show() }
    return $janela
}

function Limit-WinForgeStreamText {
    <#
    .SYNOPSIS
        O anel da caixa de texto: acima de 4 MB, volta para os últimos 2 MB, com uma marca no topo.
    .DESCRIPTION
        HISTERESE, e não corte por tique. Cortar sempre que passa de 2 MB faz a caixa copiar 2 MB a
        cada 512 KB que chegam - foi assim que o pico bateu 971 MB. Cortando só acima de 4 MB e
        voltando para 2 MB, a cópia acontece uma vez a cada 2 MB de saída: 274 MB de pico, medido.

        O corte cai na primeira quebra de linha a partir do ponto de 2 MB, e não no meio de uma
        linha: metade de um caminho de pasta no topo da caixa é ruído, não informação. Sem quebra de
        linha nenhuma no trecho (uma linha só, gigante), corta no ponto exato - é o único jeito de o
        teto valer para saída que não tem linha.

        Quem fica é o FIM do texto. A janela acompanha um comando em andamento: o que interessa é o
        que está acontecendo agora, e o começo continua inteiro no arquivo - é o que a marca diz.
    .OUTPUTS
        O texto, cortado ou não.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$MaxChars = 4194304,
        [int]$KeepChars = 2097152
    )

    if ($Text.Length -le $MaxChars) { return $Text }
    $corte = $Text.IndexOf("`n", $Text.Length - $KeepChars)
    $inicio = if ($corte -lt 0) { $Text.Length - $KeepChars } else { $corte + 1 }
    return "… (o começo desta parte ficou só no arquivo)`r`n" + $Text.Substring($inicio)
}

function Get-WinForgeFollowReadWindow {
    <#
    .SYNOPSIS
        Quanto do arquivo um tique lê: o pedaço inteiro, ou só a cauda quando ele cresceu demais.
        Função pura.
    .DESCRIPTION
        O tique lê de '$Offset' até o fim do arquivo. Isso vale enquanto o arquivo cresce meio
        segundo por vez; não vale quando a janela fica minimizada ou a thread da interface fica presa
        e o arquivo ganha dezenas de MB entre dois tiques - aí a leitura aloca um byte[] do tamanho
        do salto, decodifica tudo e joga quase tudo fora no teto do bloco. O pico vem dessa alocação,
        e não do que aparece na tela.

        Acima de 'MaxGrowth' (8 MB) o tique lê só o último 'TailBytes' (1 MB) e diz quanto pulou -
        quem quer o meio tem o arquivo, que continua completo. Abaixo disso não recorta nada: o caso
        normal é de alguns KB por tique, e recortar ali seria perder linha à toa.

        Ser pura é o que permite provar os dois lados com números, sem arquivo nenhum e sem janela.
    .OUTPUTS
        @{ Start = <long>; Count = <int>; Skipped = <long> }. 'Skipped' é 0 quando nada foi pulado.
    #>
    param(
        [Parameter(Mandatory)][long]$Offset,
        [Parameter(Mandatory)][long]$Length,
        [long]$MaxGrowth = 8388608,
        [long]$TailBytes = 1048576
    )

    $inicio = [long]$Offset
    if ($inicio -lt 0) { $inicio = 0 }
    if ($Length -le $inicio) { return @{ Start = $inicio; Count = 0; Skipped = [long]0 } }
    $cresceu = [long]($Length - $inicio)
    if ($cresceu -le $MaxGrowth) { return @{ Start = $inicio; Count = [int]$cresceu; Skipped = [long]0 } }
    $novoInicio = [long]($Length - $TailBytes)
    return @{ Start = $novoInicio; Count = [int]$TailBytes; Skipped = [long]($novoInicio - $inicio) }
}

function Test-WinForgeStreamFileCap {
    <#
    .SYNOPSIS
        Diz se o arquivo de saída desta execução passou do teto, e com que linha avisar. Só lê.
    .DESCRIPTION
        O teto é do ARQUIVO, e é a última rede: o anel da caixa protege a memória da janela, e este
        protege o disco de quem clicou. Um reparo de permissões num perfil grande, ou um DISM que
        entra em laço de erro, escreve sem parar enquanto o usuário está fora da frente da máquina -
        e foi disco cheio, não só memória, o que o usuário relatou.

        256 MB é folgado de propósito: nenhuma execução legítima chega perto, e o que chega lá não
        está mais dizendo nada de novo. O que passa disso vira UMA linha e silêncio - e a linha diz
        que os detalhes foram descartados, porque um arquivo que simplesmente para de crescer é
        indistinguível de um comando que travou.

        Arquivo que não existe, ou que não pode ser medido, responde 'não passou': o teto não é lugar
        de derrubar um comando por não conseguir ler um tamanho.
    .OUTPUTS
        @{ Over = <bool>; Bytes = <long>; Text = <string> }.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [long]$MaxBytes = 268435456
    )

    $bytes = [long]0
    try { $bytes = [long](Get-Item -LiteralPath $Path -ErrorAction Stop).Length } catch { return @{ Over = $false; Bytes = [long]0; Text = '' } }
    if ($bytes -le $MaxBytes) { return @{ Over = $false; Bytes = $bytes; Text = '' } }
    return @{
        Over  = $true
        Bytes = $bytes
        Text  = ("== Teto de {0} MB alcançado: os detalhes daqui em diante foram descartados. O comando continua rodando, e o fim dele ainda aparece nesta janela. ==" -f [int]($MaxBytes / 1MB))
    }
}

function Remove-WinForgeOldCommandOutput {
    <#
    .SYNOPSIS
        Retenção dos arquivos de saída de um prefixo: 30 dias e 20 arquivos. Apaga o excedente.
    .DESCRIPTION
        Os arquivos de saída nunca eram apagados. Um DISM de 40 MB por clique, numa máquina que usa o
        botão toda semana, é a pasta de logs crescendo para sempre - e a queixa que abriu esta leva
        começou com disco cheio.

        POR PREFIXO, e as duas regras somam: sai o que tem mais de 30 dias, e depois sai o que
        sobrar além dos 20 mais novos. O prefixo é o que mantém 'server' e 'repair' independentes -
        vinte diagnósticos de servidor não podem empurrar para fora os reparos, que são o histórico
        que alguém vai querer ler depois de uma restauração de permissões dar errado.

        A ordem é do mais NOVO para o mais velho, e o corte é no fim da fila: apagar do começo seria
        apagar exatamente o arquivo que o usuário acabou de gerar.

        Falha de remoção não é erro: o arquivo pode estar aberto na janela de outra execução. Ele
        fica, e a limpeza da execução seguinte tenta de novo.
    .PARAMETER Root
        A pasta. Vazio, é a mesma de Get-WinForgeCommandOutputPath.
    .OUTPUTS
        @{ Removed = @(<string>) } com os nomes apagados.
    #>
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [int]$MaxAgeDays = 30,
        [int]$MaxFiles = 20,
        [string]$Root = ''
    )

    # Get-WinForgeCommandOutputRoot, e NÃO Get-WinForgeCommandOutputPath: aquela dispara esta
    # função, e as duas se chamariam em círculo até a pilha acabar.
    $dir = $Root
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = Get-WinForgeCommandOutputRoot }
    $apagados = @()
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @{ Removed = @() } }
    $arquivos = @(Get-ChildItem -LiteralPath $dir -File -Filter ("{0}-*.txt" -f $Prefix) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $limite = (Get-Date).AddDays(-[math]::Abs($MaxAgeDays))
    $n = 0
    foreach ($f in $arquivos) {
        $n++
        if ($n -le $MaxFiles -and [datetime]$f.LastWriteTime -ge $limite) { continue }
        Remove-Item -LiteralPath ([string]$f.FullName) -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath ([string]$f.FullName))) { $apagados += [string]$f.Name }
    }
    return @{ Removed = @($apagados) }
}

function Get-WinForgeFollowHeader {
    <#
    .SYNOPSIS
        O texto e o nível do cabeçalho da janela que acompanha um comando. Só conta: função pura.
    .DESCRIPTION
        O caso que deu origem a isto: 404 minutos olhando um contador subir, sem nada na tela dizendo
        se aquilo era normal. Um cronômetro sozinho não informa - ele só mede. O que informa é a
        comparação com o que AQUELA linha costuma levar.

        Os cortes são 1,5x e 3x do ESPERADO, e não um número fixo de minutos: um DISM de vinte
        minutos e um Desfazer de dez não têm o mesmo "está demorando". Sem 'ExpectMinutes' o nível é
        sempre 'normal' - comando sem estimativa não pode acusar atraso que ninguém sabe medir, e
        inventar um teto fixo faria o botão mais lento da tabela viver em âmbar.

        'Cancelado em mm:ss' vem ANTES de 'Concluído': quem apertou Parar sabe que parou, e ver
        "Concluído" depois disso é o programa dizendo que fez o que não fez.

        Tempo NEGATIVO existe de verdade aqui: 'Servidor NTP - Ativar' roda 'w32tm /resync' com esta
        janela aberta, e a hora do sistema pode recuar no meio. Sem a guarda, o cabeçalho mostraria
        '-1:59'. O relógio volta para 00:00 e segue - a alternativa seria guardar um contador
        monotônico por janela para um caso que dura um tique.

        Ser pura é o que permite provar os três níveis e os dois cortes com números, sem janela.
    .PARAMETER ExpectMinutes
        Quanto esta linha costuma levar, em minutos. Zero (ou ausente) desliga o âmbar.
    .PARAMETER ExitCode
        O código de saída, só com -Done. Nulo vira 'n/d': a runspace pode ter morrido antes de gravar
        um, e 'código ' sozinho é pior do que dizer que não se sabe.
    .OUTPUTS
        @{ Text = <string>; Level = 'normal'|'ambar'|'urgente' }.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [Parameter(Mandatory)][timespan]$Elapsed,
        [int]$ExpectMinutes = 0,
        [switch]$Done,
        $ExitCode = $null,
        [switch]$Cancelled
    )

    $minutos = [double]$Elapsed.TotalMinutes
    $segundos = [int]$Elapsed.Seconds
    if ($minutos -lt 0) { $minutos = 0; $segundos = 0 }
    $mmss = '{0:00}:{1:00}' -f [int][math]::Floor($minutos), $segundos
    if ($Cancelled) { return @{ Text = "Cancelado em $mmss"; Level = 'normal' } }
    if ($Done) { return @{ Text = "Concluído em $mmss (código $(if ($null -ne $ExitCode) { $ExitCode } else { 'n/d' }))"; Level = 'normal' } }

    $andamento = "Em andamento: $Title ($mmss)"
    if ($ExpectMinutes -le 0) { return @{ Text = $andamento; Level = 'normal' } }
    $vezes = $minutos / $ExpectMinutes
    # A frase diz as três coisas que a pessoa na frente da tela precisa saber, nesta ordem: que está
    # fora do normal, que mesmo assim continua andando, e o que fazer se quiser sair. Sem a segunda,
    # o aviso vira "travou"; sem a terceira, vira "e agora?".
    if ($vezes -ge 3) {
        return @{ Text = "$andamento - Está demorando MUITO mais que o normal (o comum são $ExpectMinutes minutos, e já passou do triplo disso). Continua rodando: isto não é travamento. Não feche esta janela; se quiser interromper agora, use o botão Parar."; Level = 'urgente' }
    }
    if ($vezes -ge 1.5) {
        return @{ Text = "$andamento - Está demorando mais que o normal (o comum são $ExpectMinutes minutos). Continua rodando: isto não é travamento. Não feche esta janela; para interromper, use o botão Parar."; Level = 'ambar' }
    }
    return @{ Text = $andamento; Level = 'normal' }
}

function Invoke-WinForgeFollowTick {
    <#
    .SYNOPSIS
        Um tique da janela que acompanha um arquivo: traz o que o arquivo ganhou e atualiza o cabeçalho.
    .DESCRIPTION
        Função de ARQUIVO, e não um scriptblock preso ao relógio de cada janela, por dois motivos:
        o -SelfTest consegue dar o tique à mão (num build não há laço de mensagens, e um
        DispatcherTimer nunca bateria), e a regra desta base de código - nada de scriptblock de
        interface nascido dentro de uma runspace do pool - continua valendo de graça.

        Três detalhes que já morderam:

        1. A leitura é INCREMENTAL, por deslocamento em BYTES. Reler o arquivo inteiro a cada meio
           segundo repintaria a caixa e jogaria a rolagem para o começo a cada tique - num DISM de
           vinte minutos, ninguém conseguiria ler nada.
        2. O corte é na ÚLTIMA QUEBRA DE LINHA. Sem isso, um tique que pega o arquivo no meio de um
           caractere acentuado (UTF-8 usa dois bytes) mostraria um losango na tela e o deslocamento
           sairia do lugar para sempre. O resto fica para o tique seguinte - menos no último, quando
           já não há tique seguinte e o que sobrou tem de aparecer.
        3. O BOM do arquivo só é pulado na primeira leitura, e conta no deslocamento: sem contá-lo,
           os três bytes voltariam como texto no tique seguinte.
        4. O que vai para a caixa por tique tem TETO (512 KB). Um passo pode despejar dezenas de MB
           de uma vez - o 'icacls /save /T' sem '/Q' num perfil é o caso conhecido -, e um
           AppendText desse tamanho congela a thread da interface por muito tempo. O deslocamento
           avança sobre o bloco inteiro de qualquer jeito: o arquivo continua completo, e é ele o
           resultado. A caixa recebe a última parte, precedida de um aviso.
        5. E são TRÊS tetos, não um, porque são três consumos diferentes:
           - o do byte[] LIDO (Get-WinForgeFollowReadWindow, 8 MB de crescimento / 1 MB de cauda):
             a janela minimizada ou a thread presa deixam o arquivo crescer dezenas de MB entre dois
             tiques, e alocar esse salto inteiro para descartá-lo no teto do bloco é o pico que não
             aparece na tela;
           - o do BLOCO por tique (512 KB, item 4), que é o custo do AppendText;
           - o da CAIXA (Limit-WinForgeStreamText, 4 MB com volta para 2 MB), que é o que fica na
             memória depois. O teto do bloco sozinho não segura este: 512 KB por tique, meia hora de
             DISM, é a caixa com centenas de MB dentro.
    #>
    param([Parameter(Mandatory)]$Window)

    $estado = $Window.Tag
    if ($null -eq $estado -or [string]::IsNullOrWhiteSpace([string]$estado.Path)) { return }

    $concluido = $false
    try { $concluido = [bool]$sync.WinForgeStreamDone[[string]$estado.Path] } catch { $concluido = $false }

    try {
        $arquivo = [System.IO.File]::Open([string]$estado.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            if ($arquivo.Length -gt [long]$estado.Offset) {
                # Quanto ler, e de onde: acima de 8 MB de crescimento o tique pega só a cauda de
                # 1 MB e pula o resto - o arquivo continua completo, e quem quer o meio tem ele.
                $janelaLeitura = Get-WinForgeFollowReadWindow -Offset ([long]$estado.Offset) -Length ([long]$arquivo.Length)
                $pulou = [long]$janelaLeitura.Skipped
                [void]$arquivo.Seek([long]$janelaLeitura.Start, [System.IO.SeekOrigin]::Begin)
                $bytes = New-Object byte[] ([int]$janelaLeitura.Count)
                $lidos = $arquivo.Read($bytes, 0, $bytes.Length)
                $inicio = 0
                if ([long]$janelaLeitura.Start -eq 0 -and $lidos -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $inicio = 3 }
                # O começo da CAUDA cai num byte qualquer, e ele pode ser a continuação de um
                # caractere de vários bytes. Um byte de continuação solto vira U+FFFD, que tem TRÊS
                # bytes em UTF-8: o GetByteCount lá embaixo contaria 3 onde 1 foi consumido, e o
                # deslocamento sairia do lugar - para sempre, porque ele é cumulativo. MEDIDO antes
                # deste laço: deslocamento 8686019 num arquivo de 8686017 bytes, dois bytes além do
                # fim, e a linha seguinte chegando à janela com as primeiras letras comidas.
                #
                # É o mesmo cuidado que o corte na última quebra de linha já tem com o FIM da
                # janela. Só vale quando houve salto: no começo do arquivo o primeiro byte nunca é
                # continuação, e pular bytes ali comeria texto de verdade.
                if ([long]$janelaLeitura.Start -gt 0) {
                    while ($inicio -lt $lidos -and ($bytes[$inicio] -band 0xC0) -eq 0x80) { $inicio++ }
                }
                $texto = [System.Text.Encoding]::UTF8.GetString($bytes, $inicio, $lidos - $inicio)
                if (-not $concluido) {
                    $corte = $texto.LastIndexOf("`n")
                    $texto = if ($corte -lt 0) { '' } else { $texto.Substring(0, $corte + 1) }
                }
                $avanco = $inicio + [System.Text.Encoding]::UTF8.GetByteCount($texto)
                if ($texto.Length -gt 524288) {
                    # A PRIMEIRA quebra de linha a partir do teto, e não a última antes dele: é o
                    # que garante que o pedaço mostrado tem no máximo o tamanho do teto, e não o
                    # tamanho da distância até a quebra anterior.
                    $corteTeto = $texto.IndexOf("`n", $texto.Length - 524288)
                    $texto = "… (o começo desta parte ficou só no arquivo)`r`n" + $texto.Substring($(if ($corteTeto -lt 0) { $texto.Length - 524288 } else { $corteTeto + 1 }))
                }
                if ($pulou -gt 0) { $texto = ("… ({0} MB desta parte ficaram só no arquivo)`r`n" -f [int][math]::Ceiling($pulou / 1MB)) + $texto }
                if ($texto.Length -gt 0) {
                    $estado.Box.AppendText($texto)
                    $estado.Chars = [int]$estado.Chars + $texto.Length
                    # O ANEL, e só depois do acréscimo: o teto do bloco acima limita o que ENTRA por
                    # tique, e este limita o que FICA. A caixa só é LIDA no tique em que o corte
                    # acontece - ler '.Text' materializa a string inteira, e fazer isso a cada meio
                    # segundo seria copiar 4 MB por tique para descobrir que não há o que cortar.
                    if ([int]$estado.Chars -gt 4194304) {
                        $cortado = Limit-WinForgeStreamText -Text ([string]$estado.Box.Text)
                        $estado.Box.Text = $cortado
                        $estado.Chars = $cortado.Length
                    }
                    $estado.Box.ScrollToEnd()
                }
                $estado.Offset = [long]$janelaLeitura.Start + $avanco
            }
        } finally { $arquivo.Dispose() }
    } catch {
        # Arquivo ainda não criado, ou momentaneamente travado por quem escreve: o tique seguinte
        # pega a mesma coisa meio segundo depois. Uma exceção aqui mataria o relógio.
    }

    # O tique só PINTA: quem decide o texto e o nível é Get-WinForgeFollowHeader, que é pura e cabe
    # num teste sem janela. Os três pincéis foram resolvidos uma vez, na montagem - perguntar ao
    # dicionário de recursos de meio em meio segundo é trabalho sem resposta nova.
    $codigo = $null
    if ($concluido) { try { $codigo = $sync.WinForgeStreamExit[[string]$estado.Path] } catch { $codigo = $null } }
    $cabecalho = Get-WinForgeFollowHeader -Title ([string]$estado.Title) -Elapsed ((Get-Date) - [datetime]$estado.Start) -ExpectMinutes ([int]$estado.ExpectMinutes) -Done:$concluido -ExitCode $codigo
    $estado.Header.Text = [string]$cabecalho.Text
    $pincel = $estado.Pinceis[[string]$cabecalho.Level]
    if ($null -ne $pincel) { $estado.Header.Foreground = $pincel }
    if ($concluido -and $null -ne $estado.Timer) { try { $estado.Timer.Stop() } catch { } }
}

# Saída pendente de janela: um slot POR CHAMADA, com chave própria, e não um único global. O slot
# nasce no runspace do comando e morre no callback, que o remove assim que o lê - nada sobrevive à
# janela. A fila guarda a ORDEM das chaves, porque o callback é chamado sem argumento e precisa
# saber qual slot é o dele.
$sync.CommandOutputs = [System.Collections.Hashtable]::Synchronized(@{})
$sync.CommandOutputQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))

# Fim de um comando com fluxo ao vivo, por arquivo: quem escreve é a runspace, quem lê é o relógio
# da janela na thread da interface. Sincronizadas porque são exatamente isso - uma variável
# atravessando duas threads. A chave é o caminho do arquivo, então duas janelas acompanhando dois
# arquivos diferentes não se confundem.
$sync.WinForgeStreamDone = [System.Collections.Hashtable]::Synchronized(@{})
$sync.WinForgeStreamExit = [System.Collections.Hashtable]::Synchronized(@{})

# O escritor persistente de cada arquivo com fluxo ao vivo, pela mesma chave dos dois de cima. Um
# por caminho, e não um por chamador: dois StreamWriter em acréscimo sobre o mesmo arquivo escrevem
# por cima um do outro, quando o Windows não recusa a segunda abertura antes disso. Quem abre é
# Open-WinForgeStreamWriter, quem fecha é o 'finally' do corpo da runspace.
$sync.WinForgeStreamWriters = [System.Collections.Hashtable]::Synchronized(@{})

# O encanamento do Parar, pela mesma chave e com o mesmo tempo de vida dos dois de cima:
#
# - 'Cancel' é o pedido do usuário. Quem levanta é a thread da janela; quem lê é a runspace do pool.
# - 'Job' é o handle do Job Object do processo que está rodando agora. Medido: 'powershell.exe'
#   morto com Stop-Process -Force DEIXA VIVO o filho iniciado com UseShellExecute=$false - fechar o
#   WinForge deixava um icacls.exe ELEVADO reescrevendo ACL de pasta do sistema, sem ninguém olhando.
#   Um handle de job mata a árvore inteira de uma vez, e é a única forma que faz isso.
# - 'Protected' é a janela em que o cancelamento NÃO vale. Ela existe para o trecho entre "posse aos
#   Administradores" e "posse de volta ao dono padrão": parar ali deixa a pasta do sistema aberta a
#   qualquer processo elevado, que é pior do que não parar. Quem a usa é a Tarefa 12; aqui ela nasce.
#
# Sincronizadas porque são exatamente isso - variáveis atravessando duas threads.
$sync.WinForgeStreamCancel = [System.Collections.Hashtable]::Synchronized(@{})
$sync.WinForgeStreamJob = [System.Collections.Hashtable]::Synchronized(@{})
$sync.WinForgeStreamProtected = [System.Collections.Hashtable]::Synchronized(@{})

# Quais arquivos já passaram do teto de tamanho desta execução. Mora ao lado do escritor porque é a
# mesma chave e o mesmo tempo de vida: o aviso de "os detalhes daqui em diante foram descartados"
# sai UMA vez por arquivo, e não uma por chamada de processo - a fase 5 de um perfil são centenas
# de chamadas sobre o mesmo arquivo.
$sync.WinForgeStreamCapped = [System.Collections.Hashtable]::Synchronized(@{})

# Em quais arquivos a linha "Parado a pedido" já foi escrita. Mesma chave e mesmo tempo de vida dos
# de cima, e existe pelo mesmo motivo do teto: depois do Parar, todo passo seguinte passa pela
# recusa, e uma linha por recusa seriam centenas delas numa fase 5 de perfil. A frase sai UMA vez.
$sync.WinForgeStreamCancelNoted = [System.Collections.Hashtable]::Synchronized(@{})

# O arquivo que o comando com fluxo ao vivo está escrevendo AGORA. É como um passo do tipo
# 'Function' - que roda com todos os fluxos redirecionados para o arquivo, sem receber argumento
# nenhum - descobre para onde escrever quando ele próprio quer mandar a saída de um executável
# direto para lá, sem passar pelo Write-Host: é o caso das fases 3 a 5 de Invoke-WinForgeAclRestore,
# onde o texto do icacls chega a centenas de MB. Escrito e apagado no corpo da runspace, junto com o
# nome e o tipo do que está rodando.
$sync.WinForgeStreamPath = ''

# O ícone da barra de tarefas é objeto da JANELA: escrever nele de uma runspace do pool morre com
# "outra thread é dona deste objeto". As funções da base que rodam dentro dos passos
# (Invoke-WPFFixesUpdate, Invoke-WPFFixesWinget) chamam Set-WinUtilTaskbaritem sem passar pelo
# Dispatcher - na base elas rodavam na thread da janela e isso bastava. O build desvia a chamada
# para cá quando ela vem de outra thread; o pacote de argumentos viaja por $sync porque
# Invoke-WPFUIThread chama o bloco SEM argumento.
#
# UM PACOTE POR CHAMADA, com chave própria, e não um slot único: era um hashtable só, escrito pela
# runspace e lido pelo callback. Hoje $sync.CommandRunning e $sync.ProcessRunning mantêm o comando
# com fluxo ao vivo e a runspace de ajustes mutuamente exclusivos, então só existe um escritor -
# mas no dia em que um terceiro chamador (busca de drivers, job de perfil) chamar a função do pool,
# duas chamadas entrelaçadas perderiam uma atualização. A fila guarda a ORDEM das chaves, porque o
# callback é chamado sem argumento e precisa saber qual pacote é o dele. É o mesmo desenho de
# $sync.CommandOutputs.
#
# Com a janela FECHANDO o desvio não acontece: Set-WinUtilTaskbaritem devolve na hora (o build põe
# a guarda de $sync.WinForgeClosing na primeira linha dela). Enquanto o Add_Closing roda, a thread
# da janela está desligando o Dispatcher; um salto para lá de dentro da runspace ficaria esperando
# uma fila que ninguém mais vai processar, e o ícone da barra de tarefas está indo embora de
# qualquer jeito.
$sync.WinForgeTaskbarArgs = [System.Collections.Hashtable]::Synchronized(@{})
$sync.WinForgeTaskbarQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$sync.WinForgeTaskbarCallback = {
    try {
        $wfTbChaveAtual = $null
        try { if ($sync.WinForgeTaskbarQueue.Count -gt 0) { $wfTbChaveAtual = [string]$sync.WinForgeTaskbarQueue.Dequeue() } } catch { $wfTbChaveAtual = $null }
        if ([string]::IsNullOrWhiteSpace($wfTbChaveAtual)) { return }
        $wfTbPacote = $sync.WinForgeTaskbarArgs[$wfTbChaveAtual]
        # Removido AQUI: o pacote é desta chamada e de mais ninguém.
        [void]$sync.WinForgeTaskbarArgs.Remove($wfTbChaveAtual)
        if ($null -eq $wfTbPacote) { return }
        $wfTb = @{}
        foreach ($wfTbChave in @('state', 'overlay', 'description')) {
            $wfTbValor = [string]$wfTbPacote[$wfTbChave]
            if (-not [string]::IsNullOrWhiteSpace($wfTbValor)) { $wfTb[$wfTbChave] = $wfTbValor }
        }
        $wfTbValue = [double]$wfTbPacote['value']
        if ($wfTbValue) { $wfTb['value'] = $wfTbValue }
        if ($wfTb.Count) { Set-WinUtilTaskbaritem @wfTb }
    } catch { }
}

# Repintar os dois botões de ação da aba Diagnóstico. Nasce aqui, na runspace principal, pela
# mesma regra dos outros callbacks; roda na thread da janela porque mexe em IsEnabled de Button.
# Sai calado quando a aba ainda não foi montada (a função já cuida disso).
$sync.WinForgeDiagButtonsCallback = {
    try { Update-WinForgeDiagActionButtons } catch { }
}

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

function Invoke-WinForgeStreamStep {
    <#
    .SYNOPSIS
        Roda UM passo de um comando com fluxo ao vivo e devolve o código dele.
    .DESCRIPTION
        Um passo é @{ FilePath; Arguments; Encoding } (executável) ou @{ Function } (função do motor
        ou da base). O 'Encoding' é a dica de decodificação DAQUELE executável ('oem', 'ansi',
        'utf8' ou 'unicode'): não há regra geral, e a tabela medida está em
        Get-WinForgeOutputEncoding. O que os dois têm em comum, e por isso moram aqui, é a promessa
        do fluxo ao vivo: cada linha chega ao arquivo ASSIM QUE SAI, e o passo devolve um código que
        diz se deu certo.

        No passo de FUNÇÃO o código não existe - não há processo, não há ExitCode. Antes disso ser
        admitido, o passo sempre valia 0: um 'Write-Error' ou um 'Stop-Service' que falha dentro de
        Invoke-WPFFixesUpdate são erros NÃO TERMINANTES, o pipeline continua, a função "termina
        bem" e a janela dizia "Concluído (código 0)" depois de vinte linhas de erro. Agora o
        ErrorRecord é reconhecido no meio do fluxo: vira uma linha '[erro] <mensagem>' e derruba o
        código do passo para 1. Derruba, e SEGUE - a redefinição do Windows Update falha em partes,
        e parar no primeiro serviço que não para deixaria o sistema pior do que estava.

        '*>&1' porque as funções da base falam por Write-Host, Write-Warning e Write-Error em
        partes iguais, e sem isso a janela ficaria vazia num passo que está falando o tempo todo.

        Linha a linha, e NÃO 'Out-File -Append': o Out-File segura a saída no buffer do próprio
        escritor e só a solta quando o pipeline acaba - ou seja, quando o passo TERMINA. Numa
        redefinição do Windows Update isso é a janela em branco por vários minutos, que é
        exatamente o problema que este botão tinha antes. Abrir e fechar o arquivo por linha é o
        preço de a linha aparecer na hora, e são dezenas de linhas, não milhares.
    .OUTPUTS
        O código do passo: 0 quando deu certo, o ExitCode do processo, ou 1 quando uma função
        escreveu no fluxo de erro.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Step
    )

    if ($Step.Function) {
        Write-WinForgeStreamLine -Path $Path -Text ""
        Write-WinForgeStreamLine -Path $Path -Text "> $($Step.Function)"
        $codigo = 0
        & ([string]$Step.Function) *>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $codigo = 1
                Write-WinForgeStreamLine -Path $Path -Text "[erro] $($_.Exception.Message)"
            } else {
                Write-WinForgeStreamLine -Path $Path -Text ([string]$_)
            }
        }
        return $codigo
    }

    Write-WinForgeStreamLine -Path $Path -Text ""
    Write-WinForgeStreamLine -Path $Path -Text "> $($Step.FilePath) $(@($Step.Arguments) -join ' ')"
    # -NoCapture: as duas linhas abaixo só leem o código de saída, e o texto já foi para o arquivo
    # linha a linha. Sem ele, um DISM ou um sfc é acumulado inteiro num StringBuilder para ser
    # descartado no retorno - o mesmo desperdício que as fases das permissões tinham.
    $res = Invoke-WinForgeNativeCommand -FilePath ([string]$Step.FilePath) -Arguments @($Step.Arguments) -StreamTo $Path -Encoding ([string]$Step.Encoding) -NoCapture
    if ($null -eq $res.ExitCode) { return 0 }
    return [int]$res.ExitCode
}

function Invoke-WinForgeStreamedSteps {
    <#
    .SYNOPSIS
        Roda os passos de um comando com fluxo ao vivo, EM SEQUÊNCIA, e devolve o código final.
    .DESCRIPTION
        Separado do corpo da runspace por um motivo só: assim dá para provar a máquina inteira -
        passo que falha, código por passo, cabeçalho final - com passos inofensivos, sem abrir
        janela, sem pool de runspaces e sem rodar nenhum dos cinco comandos de verdade.

        Cada passo fecha com uma linha '== Passo N: <título> — código X =='. Sem ela, a janela
        mostrava a saída de três comandos emendada e um único código no fim: num chkdsk + sfc +
        DISM não dava para saber qual dos três falhou sem saber ler a saída de cada um.

        O código que fica é o do PRIMEIRO passo que falhou, e o cabeçalho final diz QUAL foi: um
        DISM bem-sucedido depois de um chkdsk com erro não pode apagar o erro do chkdsk.

        A frase de fechamento ($Final) só sai com código 0. Ela é a última linha que a pessoa lê, e
        é escrita no presente do indicativo ("Configuração de rede redefinida. Reinicie o
        computador."): imprimi-la depois de um '== Falhou no passo N ==' é dizer que deu certo
        logo abaixo da linha que diz que não deu. Com erro sai uma frase neutra, que aponta para o
        passo e não promete nada.
    .OUTPUTS
        O código final: 0 se todos os passos deram certo, senão o código do primeiro que falhou.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][array]$Steps,
        [string]$Final = ''
    )

    $codigo = 0
    $falhou = ''
    $n = 0
    $cancelado = $false
    foreach ($passo in @($Steps)) {
        # ENTRE passos, e não dentro de um: o processo que já está rodando é morto pelo job (ver
        # Request-WinForgeStreamCancel), e o que esta pergunta decide é se o PRÓXIMO começa. Parar
        # antes de começar é a única interrupção que não deixa nada pela metade.
        if (Test-WinForgeStreamCancelled -Path $Path) { $cancelado = $true; break }
        $n++
        $titulo = if ($passo.Function) { [string]$passo.Function } else { [string](Split-Path -Leaf ([string]$passo.FilePath)) }
        $passoCodigo = [int](Invoke-WinForgeStreamStep -Path $Path -Step $passo)
        Write-WinForgeStreamLine -Path $Path -Text ("== Passo {0}: {1} — código {2} ==" -f $n, $titulo, $passoCodigo)
        if ($codigo -eq 0 -and $passoCodigo -ne 0) { $codigo = $passoCodigo; $falhou = "$n ($titulo)" }
    }
    Write-WinForgeStreamLine -Path $Path -Text ""
    if ($cancelado) {
        # A frase de fechamento ($Final) NÃO sai aqui, pelo mesmo motivo que não sai num comando que
        # falhou: ela está no presente do indicativo ("Configuração de rede redefinida."), e
        # imprimi-la depois de uma interrupção é dizer que fez o que não fez.
        Write-WinForgeStreamLine -Path $Path -Text ("== Interrompido a pedido depois de {0} passo(s): os seguintes não rodaram. ==" -f $n)
        Write-WinForgeStreamLine -Path $Path -Text ""
        Write-WinForgeStreamLine -Path $Path -Text "O que já tinha sido feito continua feito; o que faltava não foi começado."
        return $codigo
    }
    if ($codigo -eq 0) {
        Write-WinForgeStreamLine -Path $Path -Text ("== Concluído: {0} passo(s), todos com código 0 ==" -f $n)
        if (-not [string]::IsNullOrWhiteSpace($Final)) {
            Write-WinForgeStreamLine -Path $Path -Text ""
            Write-WinForgeStreamLine -Path $Path -Text ([string]$Final)
        }
    } else {
        Write-WinForgeStreamLine -Path $Path -Text ("== Falhou no passo {0}: código {1} ==" -f $falhou, $codigo)
        Write-WinForgeStreamLine -Path $Path -Text ""
        Write-WinForgeStreamLine -Path $Path -Text ("Terminou com erro no passo {0}; veja acima. Nada mais foi feito." -f $falhou)
    }
    return $codigo
}

# Corpo da runspace de um comando com fluxo ao vivo. Mora aqui, no mesmo lugar e pelo mesmo motivo
# que $sync.WinForgeCommandOutputCallback: scriptblock que vai para o pool nasce na runspace
# PRINCIPAL, nunca dentro de outra. De quebra, sendo um valor com nome, o -SelfTest o roda de
# verdade com passos inofensivos - é como as travas, o código por passo e o cabeçalho final são
# provados sem abrir janela nenhuma e sem rodar nenhum dos cinco comandos.
#
# O 'finally' é a única saída: sem ele, um passo que lançasse deixaria a janela dizendo "em
# andamento" para sempre e as duas travas presas até fechar o programa.
$sync.WinForgeStreamBody = {
    param($wfArgs)
    $wfCaminho = [string]$wfArgs.Path
    $wfCodigo = 0
    # Para onde um passo do tipo 'Function' manda a saída de um executável sem passar pelo Write-Host.
    # É o que as fases 3 a 5 das permissões consultam - ver $sync.WinForgeStreamPath.
    $sync.WinForgeStreamPath = $wfCaminho
    # O tipo do Job Object nasce AQUI, dentro da runspace do POOL, e não na principal: MEDIDO, um
    # tipo criado por Add-Type na runspace principal NÃO é visto nas runspaces do pool, e um segundo
    # Add-Type do mesmo nome falha com "o tipo já existe". A guarda resolve as duas pontas - o
    # primeiro comando cria, os seguintes encontram.
    #
    # O NOME da guarda e o NOME do tipo têm de ser o mesmo: com -Namespace preenchido o tipo nasceria
    # 'Espaco.WfJob', a guarda nunca o encontraria e o segundo Add-Type é que estouraria.
    try {
        if (-not ('WfJob' -as [type])) {
            Add-Type -Namespace '' -Name 'WfJob' -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr a, string lpName);
[DllImport("kernel32.dll")] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
[DllImport("kernel32.dll")] public static extern bool TerminateJobObject(IntPtr job, uint exitCode);
[DllImport("kernel32.dll")] public static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint len);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
'@
        }
    } catch {
        # Sem o tipo o comando roda igual, só sem Parar. Derrubar um reparo porque o P/Invoke não
        # compilou seria trocar um problema pequeno por um grande.
        Write-WinForgeLog -Component "Repair" -Level "WARN" -Message "O cancelamento por Job Object não pôde ser preparado: $($_.Exception.Message)"
    }
    try {
        $wfCodigo = [int](Invoke-WinForgeStreamedSteps -Path $wfCaminho -Steps @($wfArgs.Steps) -Final ([string]$wfArgs.Final))
    } catch {
        $wfCodigo = -1
        Write-WinForgeStreamLine -Path $wfCaminho -Text "[erro] $($_.Exception.Message)"
        Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message "$($wfArgs.Name) falhou: $($_.Exception.Message)"
    } finally {
        # O escritor persistente fecha AQUI, e antes de a janela ser avisada do fim: ela lê o arquivo
        # de meio em meio segundo e o último tique tem de encontrar tudo o que foi escrito. É também
        # a única saída - um passo que estoure passa por este 'finally', e sem ele o identificador
        # do arquivo ficaria aberto até o programa fechar.
        Close-WinForgeStreamWriter -Path $wfCaminho
        [void]$sync.WinForgeStreamCapped.Remove($wfCaminho)
        [void]$sync.WinForgeStreamCancelNoted.Remove($wfCaminho)
        # O encanamento do Parar sai junto: pedido, handle de job e janela protegida são deste
        # comando e de mais nenhum. Deixá-los para trás faria o comando SEGUINTE, com outro arquivo,
        # conviver com lixo - e um pedido esquecido no dicionário é um Parar que ninguém pediu.
        [void]$sync.WinForgeStreamCancel.Remove($wfCaminho)
        [void]$sync.WinForgeStreamJob.Remove($wfCaminho)
        [void]$sync.WinForgeStreamProtected.Remove($wfCaminho)
        $sync.WinForgeStreamPath = ''
        $sync.WinForgeStreamExit[$wfCaminho] = $wfCodigo
        $sync.WinForgeStreamDone[$wfCaminho] = $true
        $sync.CommandRunning = $false
        $sync.ProcessRunning = $false
        # O nome e o tipo do que estava rodando saem JUNTO com as travas: é o par que o Add_Closing
        # consulta para decidir se pergunta antes de fechar, e deixá-lo para trás faria a pergunta
        # aparecer num fechamento em que não há mais nada em andamento.
        $sync.WinForgeStreamName = ''
        $sync.WinForgeStreamKind = ''
        # Os dois botões da aba Diagnóstico ("Aplicar marcados", "Desfazer marcados") são
        # habilitados por $sync.ProcessRunning, e quem os repinta é Update-WinForgeDiagActionButtons
        # - que até aqui só rodava no contador de marcações. Sem esta chamada eles ficavam
        # desabilitados depois do fim do comando até alguém marcar uma caixa.
        if (-not $sync.WinForgeClosing) {
            try { Invoke-WPFUIThread $sync.WinForgeDiagButtonsCallback } catch { }
        }
        Write-WinForgeLog -Component "Repair" -Message "$($wfArgs.Name) concluído (código $wfCodigo): $wfCaminho"
    }
}

function Start-WinForgeStreamedCommand {
    <#
    .SYNOPSIS
        Ação de um botão cujo comando DEMORA: roda os passos fora da thread da janela e mostra a
        saída numa janela que se enche enquanto o trabalho acontece.
    .DESCRIPTION
        A diferença para Invoke-WinForgeCommandButton é só o momento de mostrar. Lá o comando roda
        inteiro, devolve um texto e a janela abre com ele pronto - serve para um dcdiag de três
        segundos. Um sfc, um DISM ou uma redefinição do Windows Update levam de minutos a mais de uma
        hora, e uma janela que só aparece no fim é indistinguível de um botão quebrado: era
        exatamente o que acontecia com estes cinco botões, que ainda por cima rodavam NA thread da
        janela e a congelavam enquanto isso.

        A ordem importa e é esta:

        1. O arquivo nasce primeiro, com o cabeçalho. A janela precisa de algo para ler.
        2. A janela abre AQUI, na thread da interface (este é o handler do botão, que já roda nela) e
           ANTES de a runspace começar. Abrir depois seria abrir de dentro da runspace, e a regra
           desta base de código é que interface nasce na thread da interface.
        3. Só então a runspace começa, com o corpo de $sync.WinForgeStreamBody, que recebe tudo num
           hashtable: Invoke-WPFRunspace passa um argumento posicional só.
        4. O fim é marcado em $sync.WinForgeStreamDone/$sync.WinForgeStreamExit, no 'finally' do
           corpo. É o que troca o cabeçalho da janela de "Em andamento" para "Concluído" e para o
           relógio, e é onde as duas travas são soltas.

        Cada passo é @{ FilePath; Arguments; Encoding } (executável, com a saída indo linha a linha
        para o arquivo) ou @{ Function } (função do próprio motor ou da base, com todos os fluxos
        redirecionados para o mesmo arquivo). Os passos rodam em SEQUÊNCIA, na ordem da tabela: o
        chkdsk antes do sfc antes do DISM não é gosto, é dependência.
    .PARAMETER DryRun
        Devolve a lista dos passos prefixada com '[simulação] ' e para por aí: nada roda, nenhum
        arquivo é criado, nenhuma janela abre. É como o -SelfTest passa por estas cinco linhas sem
        redefinir a rede de quem compila.
    .OUTPUTS
        Com -DryRun, a lista de passos. Sem ele, nada.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Spec,
        [switch]$DryRun
    )

    $passos = @($Spec.Steps)
    if ($DryRun) {
        return @($passos | ForEach-Object {
            if ($_.Function) { "[simulação] $($_.Function)" }
            else { ("[simulação] $($_.FilePath) $(@($_.Arguments) -join ' ')").TrimEnd() }
        })
    }
    # Segunda camada da trava de SelfTest, no mesmo lugar em que Invoke-WinForgeCommandCore põe a
    # dela: o -DryRun já retornou acima, então daqui para baixo é execução de verdade.
    Assert-WinForgeNotSelfTest -Name "Start-WinForgeStreamedCommand ($Name)"

    if ($sync.CommandRunning) {
        [System.Windows.MessageBox]::Show("Já existe um comando em andamento. Espere ele terminar.", "WinForge", "OK", "Warning") | Out-Null
        return
    }
    if (-not $passos.Count) {
        Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message "$Name não tem passos para rodar."
        return
    }
    # A ferramenta exigida, conferida ANTES de abrir janela e de tomar as travas. Invoke-WinForgeCommandCore
    # já fazia isso no caminho de leitura; aqui o 'Requires' era dado morto. Hoje todos eles são
    # caminhos do System32 que existem em qualquer Windows com interface gráfica, mas num SKU sem
    # w32tm.exe a falta virava exceção de Start-Process dentro do runspace, e não esta frase.
    if (-not (Test-WinForgeCommandRequirement -Requires ([string]$Spec.Requires))) {
        $wfFalta = "Ferramenta necessária não encontrada nesta máquina: $($Spec.Requires). Nada foi feito."
        Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message "$Name não pôde começar: $wfFalta"
        [System.Windows.MessageBox]::Show($wfFalta, "WinForge", "OK", "Warning") | Out-Null
        return
    }

    # As DUAS travas, e não só a de comando: $sync.ProcessRunning é a que os botões da base olham
    # (instalar, desinstalar, aplicar ajustes, instalar recursos). Sem ela, uma redefinição do
    # Windows Update de vinte minutos convivia com um "Aplicar ajustes" clicado no meio - dois
    # escritores no mesmo ícone da barra de tarefas, no mesmo log e, no caso do WinGet, no mesmo
    # gerenciador de pacotes. Os dois são soltos no 'finally' do corpo da runspace.
    $sync.CommandRunning = $true
    $sync.ProcessRunning = $true
    # QUEM está rodando, para o Add_Closing: fechar a janela no meio de um 'repair' mata as threads
    # do pool onde elas estiverem, e uma restauração de permissões morta entre "posse para os
    # Administradores" e "posse de volta ao TrustedInstaller" deixa a pasta do sistema aberta a
    # qualquer processo elevado. Com isto aqui o fechamento pergunta antes; sem 'repair' ele segue
    # direto, como já fazia para o diagnóstico e a busca de drivers.
    $sync.WinForgeStreamName = [string]$Spec.Title
    $sync.WinForgeStreamKind = [string]$Spec.Kind
    # Os botões da aba Diagnóstico desabilitam na hora, e não no próximo clique numa caixa de
    # marcação (esta função já roda na thread da janela: é o handler do botão).
    try { Update-WinForgeDiagActionButtons } catch { }
    $caminho = $null
    try {
        $caminho = Get-WinForgeCommandOutputPath -Name $Name -Prefix 'repair'
        $cabecalho = "WinForge - $($Spec.Title)`r`n$((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) - $env:COMPUTERNAME`r`n" + ('-' * 78)
        Set-Content -LiteralPath $caminho -Value $cabecalho -Encoding UTF8 -ErrorAction Stop
        $sync.WinForgeStreamDone[$caminho] = $false
        $sync.WinForgeStreamExit[$caminho] = $null

        # A estimativa vem da LINHA, e é ela que deixa o cabeçalho ficar âmbar a 1,5x e urgente a 3x.
        # Linha sem 'ExpectMinutes' vira zero, e zero desliga o aviso em vez de inventar um teto.
        Show-WinForgeOutputWindow -Title $Spec.Title -FollowPath $caminho -ExpectMinutes ([int]$Spec.ExpectMinutes) -Component 'Repair' | Out-Null

        Write-WinForgeLog -Component "Repair" -Message "$Name iniciado: $($passos.Count) passo(s), saída ao vivo em $caminho"
        Invoke-WPFRunspace -ScriptBlock $sync.WinForgeStreamBody -ArgumentList @{ Name = $Name; Path = $caminho; Steps = $passos; Final = $Spec.Final } | Out-Null
    } catch {
        # O corpo pode nem ter começado (pool fechado, arquivo não gravável): sem isto as travas
        # ficariam presas e todos os botões de comando morreriam até fechar o programa.
        $sync.CommandRunning = $false
        $sync.ProcessRunning = $false
        $sync.WinForgeStreamName = ''
        $sync.WinForgeStreamKind = ''
        try { Update-WinForgeDiagActionButtons } catch { }
        if ($caminho) { $sync.WinForgeStreamDone[$caminho] = $true }
        Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message "$Name não pôde começar: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("O comando não pôde começar: $($_.Exception.Message)", "WinForge", "OK", "Error") | Out-Null
    }
}

#endregion
