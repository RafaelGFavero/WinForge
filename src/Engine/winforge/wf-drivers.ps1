#region ===== WinForge - drivers (consulta online) =====
# Descobre a versão mais recente do driver NVIDIA, monta o link de download de cada fabricante e
# pergunta ao Windows Update se há driver novo para este computador.
# Tudo aqui é opcional e tolerante a falha: sem internet, o perfil continua válido - cada função
# devolve 'indisponível', array vazio ou $null, nunca uma exceção que escape para quem chamou.

# ---- critério do agrupamento dos INFs sem versão do Windows Update ----------------------------
# TRÊS CONSTANTES PROVISÓRIAS, num lugar só, e é de propósito que elas são feias de achar em
# qualquer outro lugar: quem for ajustar o critério mexe aqui e em nada mais.
# A máquina do caso - desktop X99 com Xeon, dezenas de ofertas iguais em fornecedor, classe e data -
# NÃO é esta. A busca da WUA aqui devolve ZERO oferta de driver, e DriverClass, MaxDownloadSize e
# DriverHardwareID nunca foram vistos numa oferta real de INF sem versão. O corte de tamanho veio do
# DriverStore LOCAL (pacote sem binário: mediana 7.662 B; com binário: 180.064 B), que é parente do
# que o Windows Update oferece, não o mesmo dado.
# Chegando o levantamento da X99, MUDA-SE A CONSTANTE E MAIS NADA: nenhum teste do motor escreve
# estes valores à mão - todos leem daqui, e o -SelfTest cobra a marca na própria linha de cada uma.
$script:WinForgeNullDriverMaxBytes = 262144   # PROVISÓRIO - 256 KB; acima disso o pacote leva binário e instala driver de verdade
$script:WinForgeNullDriverMinGroup = 5        # PROVISÓRIO - abaixo de cinco a linha de grupo esconde mais do que economiza
$script:WinForgeNullDriverClasses  = @('', 'system', 'other hardware', 'unknown', 'outro hardware')  # PROVISÓRIO - lista de PERMISSÃO: classe nova, traduzida ou ausente fica VISÍVEL

function Get-WinForgeCacheRoot {
    <#
    .SYNOPSIS
        Pasta do cache do catálogo (%LocalAppData%\WinForge\cache). -Root existe para o -SelfTest não
        escrever no cache real.
    .DESCRIPTION
        A base vem de Get-WinForgeUserDataRoot (API de pastas), e não de $env:LOCALAPPDATA - ver lá
        por quê.

        ESTE CACHE É DE TELA. Ele mora no perfil do usuário, que qualquer processo de integridade
        média da mesma conta escreve, e por isso ele não decide nada: alimenta a coluna "Ação" da
        tabela de drivers (o rótulo "Baixar <versão>") e para por aí. O endereço e a versão que o
        motor elevado realmente baixa saem da consulta AO VIVO do clique - ver
        Resolve-WinForgeNvidiaDownloadTarget e Get-WinForgeNvidiaLatestDriver -NoCache.
    #>
    param([string]$Root)
    if ($Root) { return $Root }
    return (Join-Path (Get-WinForgeUserDataRoot) 'WinForge\cache')
}

function Get-WinForgeCacheItem {
    <#
    .SYNOPSIS
        Lê um JSON do cache local se ele ainda estiver dentro da validade.
    .DESCRIPTION
        Devolve $null quando o arquivo não existe, está velho ou não pôde ser lido - o chamador
        simplesmente consulta a rede de novo.
    #>
    param([Parameter(Mandatory)][string]$Name, [int]$MaxAgeHours = 24, [string]$Root)
    try {
        $file = Join-Path (Get-WinForgeCacheRoot $Root) $Name
        if (-not (Test-Path -LiteralPath $file)) { return $null }
        $age = (Get-Date) - (Get-Item -LiteralPath $file).LastWriteTime
        if ($age.TotalHours -gt $MaxAgeHours) { return $null }
        return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch { return $null }
}

function Set-WinForgeCacheItem {
    <#
    .SYNOPSIS
        Grava um JSON no cache local. Falha de escrita (pasta somente leitura, disco cheio) é ignorada.
    #>
    param([Parameter(Mandatory)][string]$Name, $Value, [string]$Root)
    try {
        $dir = Get-WinForgeCacheRoot $Root
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        ($Value | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $dir $Name) -Encoding UTF8
    } catch { }
}

function ConvertTo-WinForgeNvidiaModelName {
    <#
    .SYNOPSIS
        Normaliza o nome de uma placa NVIDIA para comparação ('NVIDIA GeForce RTX 3070' -> 'RTX 3070').
    .DESCRIPTION
        Tira o que o Windows e o catálogo da NVIDIA escrevem de forma diferente: marca, linha
        'GeForce', sufixo de notebook e espaços duplicados. O que sobra é o modelo puro.
    #>
    param([string]$Name)
    if (-not $Name) { return '' }
    $n = $Name -replace '(?i)\bNVIDIA\b', '' -replace '(?i)\bGeForce\b', ''
    $n = $n -replace '(?i)\bLaptop GPU\b', '' -replace '(?i)with Max-Q Design', ''
    return (($n -replace '\s+', ' ').Trim())
}

function Get-WinForgeNvidiaSeriesToken {
    <#
    .SYNOPSIS
        Reduz o nome da placa à família usada pelo catálogo da NVIDIA ('RTX 3070' -> '30', 'GTX 970M' -> '900M').
    .DESCRIPTION
        O catálogo agrupa por família, não por modelo. Modelo de quatro dígitos vira os dois
        primeiros (3070 -> 30, 1660 -> 16); de três dígitos, o primeiro mais '00' (970 -> 900);
        as MX viram MX<centena> (MX450 -> MX400). O 'M' final de notebook é preservado, porque
        o catálogo tem famílias separadas para ele. Devolve $null se não reconhecer o modelo.
    #>
    param([string]$Name)
    $n = ConvertTo-WinForgeNvidiaModelName $Name
    if (-not $n) { return $null }
    if ($n -match '(?i)\bMX\s*(\d)\d{2}\b') { return ('MX{0}00' -f $Matches[1]) }
    if ($n -match '(?i)\b(?:RTX|GTX|GTS|GS|GT)?\s*(\d{3,4})(M)?\b') {
        $digits = $Matches[1]
        $suffix = $(if ($Matches[2]) { 'M' } else { '' })
        if ($digits.Length -eq 4) { return ($digits.Substring(0, 2) + $suffix) }
        return ($digits.Substring(0, 1) + '00' + $suffix)
    }
    return $null
}

function Get-WinForgeNvidiaSeriesNameToken {
    <#
    .SYNOPSIS
        Extrai a família do nome de uma série do catálogo ('GeForce RTX 30 Series' -> '30').
    .DESCRIPTION
        Do outro lado da comparação com Get-WinForgeNvidiaSeriesToken. A NVIDIA não é consistente
        na escrita - a mesma família aparece como 'GeForce RTX 30 Series', 'GeForce 16 Series' e
        'GeForce GTX 16 Series (Notebooks)' -, então RTX/GTX/Go e o sufixo de notebook saem fora e
        só o número da família fica. Devolve $null para nomes fora do padrão ('GeForce 5 FX Series').
    #>
    param([string]$Name)
    if (-not $Name) { return $null }
    $n = $Name -replace '(?i)\s*\(Notebooks?\)\s*$', ''
    $n = $n -replace '(?i)\bGeForce\b', '' -replace '(?i)\b(?:RTX|GTX|Go)\b', ''
    $n = ($n -replace '\s+', ' ').Trim()
    if ($n -match '^(MX\d{3}|\d{1,4}M?)\s+Series$') { return $Matches[1] }
    return $null
}

function Get-WinForgeNvidiaCatalog {
    <#
    .SYNOPSIS
        Uma requisição ao catálogo da NVIDIA. É o único ponto deste arquivo que fala com a rede.
    .DESCRIPTION
        Existe para haver uma COSTURA: com -Resolver, a requisição é trocada por um bloco que
        devolve a resposta pronta. É assim que o -SelfTest exercita a consulta ao vivo inteira - as
        duas listas e a busca do driver - sem tirar um byte da rede, e é o que permite provar que
        um arquivo plantado no cache não chega ao caminho do download. Sem -Resolver isto é um
        Invoke-RestMethod e nada mais.
    #>
    param([Parameter(Mandatory)][string]$Uri, [int]$TimeoutSec = 5, [scriptblock]$Resolver)
    if ($Resolver) { return (& $Resolver $Uri) }
    return Invoke-RestMethod -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSec
}

function Get-WinForgeNvidiaLookupValues {
    <#
    .SYNOPSIS
        Lista séries (TypeID 2, ParentID 1) ou produtos de uma série (TypeID 3, ParentID <psid>)
        do catálogo da NVIDIA, em cache de 24 h.
    .DESCRIPTION
        Devolve array de objetos com Name e Value (o psid/pfid). Erro de rede sobe para o chamador,
        que traduz em status 'indisponível'.
    .PARAMETER NoCache
        Ignora o arquivo do cache e pergunta ao catálogo. O cache continua sendo GRAVADO: ele serve
        à tela, e mantê-lo fresco é justamente o que se quer. Quem baixa não lê o cache.
    #>
    param(
        [Parameter(Mandatory)][int]$TypeId,
        [Parameter(Mandatory)][int]$ParentId,
        [int]$TimeoutSec = 5,
        [switch]$NoCache,
        [string]$Root,
        [scriptblock]$Resolver
    )
    $cacheName = "nvidia-lookup-$TypeId-$ParentId.json"
    if (-not $NoCache) {
        $cached = Get-WinForgeCacheItem -Name $cacheName -Root $Root
        if ($cached) { return @($cached) }
    }
    $uri = "https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=$TypeId&ParentID=$ParentId"
    $xml = Get-WinForgeNvidiaCatalog -Uri $uri -TimeoutSec $TimeoutSec -Resolver $Resolver
    $values = @($xml.LookupValueSearch.LookupValues.LookupValue | Where-Object { $_.Name } | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.Name; Value = [string]$_.Value }
    })
    if ($values.Count) { Set-WinForgeCacheItem -Name $cacheName -Value $values -Root $Root }
    return $values
}

function Get-WinForgeNvidiaLatestDriver {
    <#
    .SYNOPSIS
        Versão mais recente do driver NVIDIA para uma placa, direto do catálogo do fabricante.
    .DESCRIPTION
        Três passos: acha a família da placa na lista de séries, acha o produto exato dentro dela e
        pergunta o driver mais novo (WHQL/DCH) para o Windows instalado. O resultado fica 24 h em
        %LocalAppData%\WinForge\cache\nvidia-<psid>-<pfid>-<osID>.json - cache de TELA, ver
        Get-WinForgeCacheRoot.
        Status: 'ok' (achou), 'não encontrado' (placa fora do catálogo) ou 'indisponível' (sem rede).
        Dois casos caem sempre em 'não encontrado', de propósito: placas profissionais (Quadro,
        RTX A2000) - o nome não tem a família de quatro dígitos que Get-WinForgeNvidiaSeriesToken
        procura - e o Windows Server, porque osID aqui é sempre o do cliente (135/57) e o catálogo
        tem identificadores próprios para as edições de servidor. Nos dois a aba mostra o link do
        fabricante, que é o que resta de útil.
    .PARAMETER GpuName
        Nome como o Windows reporta, por exemplo 'NVIDIA GeForce RTX 3070'.
    .PARAMETER IsWin11
        Windows 11 (osID 135) ou Windows 10 64 bits (osID 57).
    .PARAMETER IsLaptop
        Escolhe a série '(Notebooks)' em vez da de desktop.
    .PARAMETER NoCache
        Não lê NENHUM dos três arquivos de cache (as duas listas e a busca do driver): as três
        respostas vêm do catálogo agora. É o que o clique em "Baixar" usa, e é o que impede que um
        JSON plantado no perfil do usuário escolha psid, pfid, versão ou endereço do instalador que
        o motor elevado vai abrir. O cache continua sendo gravado, para a tela.
    .PARAMETER Root
        Pasta do cache própria (usada pelo -SelfTest). Não afrouxa nada: o cache não decide nada.
    .PARAMETER Resolver
        Costura de teste - ver Get-WinForgeNvidiaCatalog.
    #>
    param(
        [Parameter(Mandatory)][string]$GpuName,
        [bool]$IsWin11 = $true,
        [bool]$IsLaptop = $false,
        [int]$TimeoutSec = 5,
        [switch]$NoCache,
        [string]$Root,
        [scriptblock]$Resolver
    )
    $result = [ordered]@{ Version = $null; ReleaseDate = $null; Url = $null; Status = 'indisponível' }

    # Placa que não é NVIDIA nunca vai estar no catálogo: sai antes de qualquer requisição, senão
    # uma Intel/AMD com número parecido ('Radeon RX 7800') geraria uma consulta inútil de 5 s.
    if ($GpuName -notmatch '(?i)NVIDIA|GeForce|Quadro|RTX|GTX') { $result.Status = 'não encontrado'; return $result }

    $token = Get-WinForgeNvidiaSeriesToken $GpuName
    $model = ConvertTo-WinForgeNvidiaModelName $GpuName
    if (-not $token -or -not $model) { $result.Status = 'não encontrado'; return $result }
    $osId = $(if ($IsWin11) { 135 } else { 57 })

    try {
        # TLS 1.2 é obrigatório nos dois domínios da NVIDIA e o padrão do PowerShell 5.1 ainda é
        # SSL3/TLS1.0; soma em vez de substituir para não derrubar o que já estiver habilitado.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $series = @(Get-WinForgeNvidiaLookupValues -TypeId 2 -ParentId 1 -TimeoutSec $TimeoutSec -NoCache:$NoCache -Root $Root -Resolver $Resolver)
        $candidates = @($series | Where-Object { (Get-WinForgeNvidiaSeriesNameToken $_.Name) -eq $token })
        if (-not $candidates.Count) { $result.Status = 'não encontrado'; return $result }
        $pick = @($candidates | Where-Object { ($_.Name -match '(?i)\(Notebooks?\)') -eq $IsLaptop }) | Select-Object -First 1
        if (-not $pick) { $pick = $candidates[0] }
        $psid = [int]$pick.Value

        $products = @(Get-WinForgeNvidiaLookupValues -TypeId 3 -ParentId $psid -TimeoutSec $TimeoutSec -NoCache:$NoCache -Root $Root -Resolver $Resolver)
        $product = @($products | Where-Object { (ConvertTo-WinForgeNvidiaModelName $_.Name) -eq $model }) | Select-Object -First 1
        if (-not $product) { $result.Status = 'não encontrado'; return $result }
        $pfid = [int]$product.Value

        $cacheName = "nvidia-$psid-$pfid-$osId.json"
        $info = $null
        if (-not $NoCache) { $info = Get-WinForgeCacheItem -Name $cacheName -Root $Root }
        if (-not $info) {
            # Parâmetros extras (beta/upCRD/qnf/ctk/dltype) fazem esta consulta responder
            # DriverDownloadIDNotFound: só os abaixo.
            $uri = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=$psid&pfid=$pfid&osID=$osId&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1"
            $response = Get-WinForgeNvidiaCatalog -Uri $uri -TimeoutSec $TimeoutSec -Resolver $Resolver
            $info = @($response.IDS)[0].downloadInfo
            # 'Success' vem "1" quando achou e "0" quando não; o que decide mesmo é ter versão.
            if (-not $info -or -not $info.Version) { $result.Status = 'não encontrado'; return $result }
            Set-WinForgeCacheItem -Name $cacheName -Value $info -Root $Root
        }
        if (-not $info.Version) { $result.Status = 'não encontrado'; return $result }

        $result.Version = [string]$info.Version
        $result.Url     = [string]$info.DownloadURL
        $result.ReleaseDate = [string]$info.ReleaseDateTime
        # 'Thu Sep 03, 2026' -> '2026-09-03'; formato inesperado fica como veio.
        try {
            $d = [datetime]::ParseExact([string]$info.ReleaseDateTime, 'ddd MMM dd, yyyy', [cultureinfo]::InvariantCulture)
            $result.ReleaseDate = $d.ToString('yyyy-MM-dd')
        } catch { }
        $result.Status = 'ok'
    } catch {
        $result.Status = 'indisponível'
    }
    return $result
}

function Get-WinForgeVendorDriverUrl {
    <#
    .SYNOPSIS
        Página oficial de download de driver para um fabricante.
    .DESCRIPTION
        Quem fabrica o chip mas não distribui driver ao usuário final (Qualcomm, MediaTek, Broadcom)
        cai na página de suporte do fabricante do computador. Sem reconhecer o fabricante, devolve
        $null - melhor nenhum link do que um link errado.
    #>
    param([string]$Vendor, $Profile)
    $vendorUrls = @{
        nvidia   = 'https://www.nvidia.com/pt-br/drivers/'
        amd      = 'https://www.amd.com/pt/support/download/drivers.html'
        intel    = 'https://www.intel.com.br/content/www/br/pt/download-center/home.html'
        realtek  = 'https://www.realtek.com/Download/List?cate_id=584'
        logitech = 'https://support.logi.com/'
    }
    if ($vendorUrls.ContainsKey([string]$Vendor)) { return $vendorUrls[[string]$Vendor] }

    $manufacturer = ''
    try { if ($Profile -and $Profile.Machine) { $manufacturer = [string]$Profile.Machine.Manufacturer } } catch { }
    if (-not $manufacturer) { return $null }
    switch -Regex ($manufacturer) {
        'ASUS'                      { return 'https://www.asus.com/support/download-center/' }
        'Micro-Star|MSI'            { return 'https://www.msi.com/support/download' }
        'Gigabyte|GIGA-BYTE'        { return 'https://www.gigabyte.com/Support' }
        'ASRock'                    { return 'https://www.asrock.com/support/index.asp' }
        'Dell|Alienware'            { return 'https://www.dell.com/support/home/' }
        'Lenovo'                    { return 'https://support.lenovo.com/' }
        'HP|Hewlett'                { return 'https://support.hp.com/drivers' }
        'Acer'                      { return 'https://www.acer.com/support' }
        'Samsung'                   { return 'https://www.samsung.com/br/support/' }
        default                     { return $null }
    }
}

function Update-WinForgeProfileDriverStatus {
    <#
    .SYNOPSIS
        Completa o perfil com o que só a internet responde: driver NVIDIA mais novo e link de
        download por fabricante.
    .DESCRIPTION
        Nas GPUs NVIDIA compara a versão comercial instalada com a do catálogo e grava Latest,
        LatestDate e LatestStatus ('atualizar' se está atrás, 'ok' se em dia, 'não encontrado' ou
        'indisponível' quando a consulta não resolveu). GPUs de outros fabricantes ficam como
        estavam - não há catálogo equivalente para consultar.
        Em cada driver do inventário grava a Url do fabricante e o Status: 'atualizar' quando a
        placa NVIDIA está atrás, 'verificar' quando o driver está marcado como antigo pelo
        inventário (o prazo varia por classe - ver Get-WinForgeDriverInventory), senão 'ok'.
    #>
    param($Profile)
    if (-not $Profile) { return }

    $isWin11 = $true
    $isLaptop = $false
    try { if ($Profile.OS) { $isWin11 = [bool]$Profile.OS.IsWin11 } } catch { }
    try { if ($Profile.Machine) { $isLaptop = [bool]$Profile.Machine.IsLaptop } } catch { }

    $nvidiaBehind = $false
    $nvidiaLatest = $null
    $nvidiaUrl = $null
    foreach ($gpu in @($Profile.GPU)) {
        if (-not $gpu -or $gpu.Vendor -ne 'nvidia') { continue }
        $latest = Get-WinForgeNvidiaLatestDriver -GpuName ([string]$gpu.Name) -IsWin11 $isWin11 -IsLaptop $isLaptop
        if ($latest.Status -ne 'ok') {
            $gpu.LatestStatus = $latest.Status
            continue
        }
        $gpu.Latest     = $latest.Version
        $gpu.LatestDate = $latest.ReleaseDate
        $gpu.LatestUrl  = $latest.Url
        $gpu.LatestStatus = 'ok'
        # MarketingVersion é a versão comercial derivada do driver instalado (616.56); comparar como
        # texto diria que '616.8' é maior que '616.64', então a comparação é numérica.
        try {
            if ($gpu.MarketingVersion -and ([version]$gpu.MarketingVersion -lt [version]$latest.Version)) {
                $gpu.LatestStatus = 'atualizar'
                $nvidiaBehind = $true
                $nvidiaLatest = $latest.Version
                $nvidiaUrl = $latest.Url
            }
        } catch {
            # versão em formato inesperado dos dois lados: não dá para dizer que está em dia
            $gpu.LatestStatus = 'indisponível'
        }
    }

    foreach ($drv in @($Profile.Drivers)) {
        if (-not $drv) { continue }
        $drv.Url = Get-WinForgeVendorDriverUrl -Vendor ([string]$drv.Vendor) -Profile $Profile
        if ($nvidiaBehind -and $drv.Vendor -eq 'nvidia' -and $drv.Class -eq 'DISPLAY') {
            $drv.Status = 'atualizar'
            $drv.Latest = $nvidiaLatest
            # O link do instalador vem do catálogo, não é montado aqui: é ele que o botão "Baixar"
            # usa, e quem o valida antes de qualquer requisição é Test-WinForgeNvidiaDownloadUrl.
            $drv.LatestUrl = $nvidiaUrl
        } elseif ($drv.Old) {
            $drv.Status = 'verificar'
        } else {
            $drv.Status = 'ok'
        }
    }
}

function Get-WinForgeWindowsUpdateDriverVersion {
    <#
    .SYNOPSIS
        A versão do driver tirada do título da atualização.
    .DESCRIPTION
        A API do Windows Update não tem campo de versão (DriverVerDate é data), então o número só
        existe no título - e em duas formas. A moderna traz entre parênteses ("Intel Corporation
        Display Driver Update (32.0.101.7088)") e a antiga no fim ("Intel - Display - 32.0.101.7088").
        A dos parênteses vem primeiro porque o título dela TERMINA em ')': procurando só no fim, a
        coluna "Versão" da tabela ficava inteira em "n/d" mesmo com o número à vista.

        Sem número reconhecível devolve $null - melhor vazio do que uma data disfarçada de versão.
    #>
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    if ($Title -match '\((\d+(?:\.\d+){1,3})\)') { return $Matches[1] }
    if ($Title -match '(\d+(?:\.\d+){2,3})\s*$') { return $Matches[1] }
    return $null
}

function Select-WinForgeWindowsUpdateLatest {
    <#
    .SYNOPSIS
        Uma linha por dispositivo: da mesma placa fica só a oferta mais nova.
    .DESCRIPTION
        Quando o fabricante publica uma revisão, o Windows Update passa a oferecer as DUAS - mesmo
        DriverModel, versões diferentes. As duas na tabela é um convite a instalar a antiga.

        O agrupamento é por DriverModel + DriverProvider + DriverClass, sem ligar para caixa (o
        serviço não é consistente nisso). DriverModel vazio não identifica dispositivo nenhum: cada
        linha assim fica sozinha, senão ofertas de placas diferentes sumiriam uma atrás da outra.

        A classe entra na chave porque o mesmo dispositivo recebe DOIS pacotes que se completam: o
        driver base (classe 'MEDIA', 'Display', 'Net') e o INF de extensão (classe 'Extension'),
        publicados com o mesmo DriverModel e o mesmo DriverProvider. Sem ela, um escondia o outro
        como se fosse revisão antiga, e metade da oferta sumia da tabela.

        Quem ganha é a maior [version]. Sem versão dos dois lados (ou com número que não vira
        [version]), quem ganha é a data mais nova - DriverVerDate a API sempre traz. Empate fica
        com a primeira linha vista, e a ordem de saída é a da primeira aparição de cada dispositivo.

        Devolve @{ Kept; Superseded }, com Superseded trazendo @{ UpdateId; Title; ReplacedBy } de
        cada oferta escondida. Isto é uma escolha de VISTA: o mapa $sync.DiagWUUpdates continua com
        o objeto COM das duas, e instalar a antiga pelo id segue possível.
    #>
    param($Rows)

    $ordem  = [System.Collections.Generic.List[string]]::new()
    $grupos = @{}
    $i = 0
    foreach ($linha in @($Rows)) {
        if ($null -eq $linha) { continue }
        $modelo = [string]$linha.Driver
        # A chave leva o índice quando não há modelo: é o que impede duas placas anônimas de virarem
        # uma. O "`u{1}" separa os três campos para 'ab'+'c' não colidir com 'a'+'bc'.
        $chave = if ([string]::IsNullOrWhiteSpace($modelo)) { "#$i" } else { ($modelo + [char]1 + [string]$linha.Provider + [char]1 + [string]$linha.Class).ToLowerInvariant() }
        $i++
        if (-not $grupos.ContainsKey($chave)) {
            $ordem.Add($chave)
            $grupos[$chave] = @{ Winner = $linha; Losers = [System.Collections.Generic.List[object]]::new() }
            continue
        }
        $grupo = $grupos[$chave]
        if (Test-WinForgeWindowsUpdateNewer -Candidate $linha -Current $grupo.Winner) {
            $grupo.Losers.Add($grupo.Winner)
            $grupo.Winner = $linha
        } else {
            $grupo.Losers.Add($linha)
        }
    }

    $mantidos = [System.Collections.Generic.List[object]]::new()
    $ocultos  = [System.Collections.Generic.List[object]]::new()
    foreach ($chave in $ordem) {
        $grupo = $grupos[$chave]
        $mantidos.Add($grupo.Winner)
        foreach ($perdedor in $grupo.Losers) {
            $ocultos.Add([pscustomobject]@{
                UpdateId   = [string]$perdedor.UpdateId
                Title      = [string]$perdedor.Title
                ReplacedBy = [string]$grupo.Winner.UpdateId
            })
        }
    }
    return @{ Kept = @($mantidos); Superseded = @($ocultos) }
}

function Test-WinForgeWindowsUpdateNewer {
    <#
    .SYNOPSIS
        A oferta candidata é mais nova que a atual?
    .DESCRIPTION
        Versão primeiro, e só quando os DOIS lados viram [version]: comparar '32.0.101.7088' com
        '32.0.101.785' como texto diria que a segunda é maior. Quando um dos lados não tem número
        utilizável, a decisão passa para a data (texto 'yyyy-MM-dd', que ordena sozinho). Empate ou
        falta dos dois dados responde $false - quem chegou primeiro fica.
    #>
    param($Candidate, $Current)

    $vCand = $null; $vAtual = $null
    $okCand  = [version]::TryParse([string]$Candidate.Version, [ref]$vCand)
    $okAtual = [version]::TryParse([string]$Current.Version, [ref]$vAtual)
    if ($okCand -and $okAtual) { return ($vCand -gt $vAtual) }
    return ([string]$Candidate.Date -gt [string]$Current.Date)
}

function Group-WinForgeWindowsUpdateNullDrivers {
    <#
    .SYNOPSIS
        Dobra numa linha só os lotes de INF sem versão que o Windows Update oferece.
    .DESCRIPTION
        Num desktop X99 a tabela veio com dezenas de linhas iguais no que importa: fornecedor Intel,
        versão vazia, a mesma data de 2016 e títulos que são nomes de funções internas do processador
        (controlador de memória, barramento de anel, unidade de controle de energia, registradores de
        estado). São arquivos de informação do pacote de chipset: dão nome ao dispositivo no
        Gerenciador de Dispositivos e não instalam binário nenhum. Dezenas deles escondem os drivers
        que importam e custam dezenas de cliques.

        QUATRO CONDIÇÕES SIMULTÂNEAS, e nenhuma delas baixa coisa alguma:
        (1) Version vazio E nenhum número de VERSÃO no título. O número sai do mesmo parser da coluna
            "Versão", e não de "tem dígito": 'INTEL - System - 47' agrupa, 'INTEL - System - 10.1.1.44'
            não - o 47 é o contador do lote, o 10.1.1.44 é um driver de verdade.
        (2) Class numa LISTA DE PERMISSÃO fechada, comparada com .Trim().ToLowerInvariant() - classe
            nova, traduzida ou ausente fica VISÍVEL, porque é lista de permissão e não de proibição.
        (3) SizeBytes entre 1 e o corte. Tamanho DESCONHECIDO não agrupa: falta de dado é motivo para
            MOSTRAR.
        (4) o lote tem pelo menos MinGroup membros.

        Toda dúvida deixa a linha sozinha, e é uma escolha assimétrica: o erro caro aqui é esconder o
        driver que o usuário veio buscar, não mostrar uma linha a mais.

        A chave leva a DATA para amarrar o lote a uma publicação de INF, e o [char]1 separa os três
        campos para 'ab'+'c' não colidir com 'a'+'bc'. Os três limites são $script:WinForgeNullDriver*,
        constantes PROVISÓRIAS declaradas no topo deste arquivo.

        UpdateId = 'grupo:<hash da chave>' identifica a LINHA na tabela - é o que o clique carrega na
        Tag. Não é chave de estado: o estado de instalação é guardado por MEMBRO, e o da linha de
        grupo é derivado deles a cada remontagem. O que ele tem de ser é estável entre remontagens.
    .OUTPUTS
        @{ Rows; Groups }. Rows é a lista na ordem original, com a linha de grupo na posição da
        PRIMEIRA oferta que a originou; Groups traz um registro por lote dobrado.
    #>
    param(
        $Rows,
        [int]$MinGroup  = $script:WinForgeNullDriverMinGroup,
        [long]$MaxBytes = $script:WinForgeNullDriverMaxBytes,
        [string[]]$Classes = $script:WinForgeNullDriverClasses
    )

    $permitidas = @{}
    foreach ($permitida in @($Classes)) { $permitidas[([string]$permitida).Trim().ToLowerInvariant()] = $true }

    # Primeira passada: quem é elegível e a que lote pertence. A segunda passada precisa saber o
    # TAMANHO do lote antes de decidir, e por isso a decisão não cabe numa passada só.
    $entrada = [System.Collections.Generic.List[object]]::new()
    $lotes   = @{}
    foreach ($linha in @($Rows)) {
        if ($null -eq $linha) { continue }
        $tamanho = [long]0
        try { $tamanho = [long]$linha.SizeBytes } catch { $tamanho = [long]0 }
        $semVersao = ([string]::IsNullOrWhiteSpace([string]$linha.Version)) -and
                     ($null -eq (Get-WinForgeWindowsUpdateDriverVersion -Title ([string]$linha.Title)))
        $classe = ([string]$linha.Class).Trim().ToLowerInvariant()
        $chave  = ''
        if ($semVersao -and $permitidas.ContainsKey($classe) -and $tamanho -ge 1 -and $tamanho -le $MaxBytes) {
            $chave = ([string]$linha.Provider + [char]1 + [string]$linha.Class + [char]1 + [string]$linha.Date).ToLowerInvariant()
            if (-not $lotes.ContainsKey($chave)) { $lotes[$chave] = [System.Collections.Generic.List[object]]::new() }
            $lotes[$chave].Add($linha)
        }
        $entrada.Add([pscustomobject]@{ Row = $linha; Key = $chave })
    }

    $linhas = [System.Collections.Generic.List[object]]::new()
    $grupos = [System.Collections.Generic.List[object]]::new()
    $feitos = @{}
    foreach ($item in $entrada) {
        $chave = [string]$item.Key
        # Lote pequeno demais não vira grupo: cada linha dele volta sozinha, no lugar em que estava.
        if ([string]::IsNullOrEmpty($chave) -or $lotes[$chave].Count -lt $MinGroup) { $linhas.Add($item.Row); continue }
        if ($feitos.ContainsKey($chave)) { continue }
        $feitos[$chave] = $true
        $grupo = New-WinForgeWindowsUpdateNullDriverGroup -Key $chave -Members @($lotes[$chave])
        $grupos.Add($grupo)
        # Título neutro: o rótulo de tela nasce na camada da tabela, que é quem sabe o idioma da
        # coluna. SizeBytes = 0 de propósito - passar o resultado por esta função de novo deixa a
        # linha de grupo de fora, em vez de agrupar grupos.
        $linhas.Add([pscustomobject]@{
            Title     = "$([string]$grupo.Provider) - $(@($grupo.Members).Count) item(ns) agrupado(s)"
            Driver    = ''
            Provider  = [string]$grupo.Provider
            Class     = [string]$grupo.Class
            Version   = $null
            Date      = [string]$grupo.Date
            UpdateId  = (Get-WinForgeWindowsUpdateGroupId -Key $chave)
            SizeBytes = [long]0
            IsGroup   = $true
            Group     = $grupo
        })
    }
    return @{ Rows = @($linhas); Groups = @($grupos) }
}

function Test-WinForgeChipsetGroup {
    <#
    .SYNOPSIS
        Este lote é o pacote de informação de chipset da Intel?
    .DESCRIPTION
        Instalar de uma vez as N entradas do lote pela via do Windows Update É o utilitário de INF de
        chipset: é o mesmo pacote, assinado pela Microsoft, pelo canal que a máquina já usa. O WinForge
        não baixa nem executa instalador de fabricante para isto - a exceção que existe para a placa de
        vídeo se apoia numa consulta ao vivo à API pública do fabricante no clique, e não há
        equivalente aqui.

        TRÊS EXIGÊNCIAS, e as três juntas:
        1. Classe 'System', que é {4d36e97d-e325-11ce-bfc1-08002be10318} e não muda de nome com o
           idioma. Vídeo é 'Display', rede é 'Net', áudio é 'MEDIA'.
        2. Fornecedor casando '^intel$' sem ligar para a caixa. 'Intel Corporation' NÃO passa: quem
           publica o pacote de chipset assina 'INTEL', e o nome comprido é de outra família de driver.
        3. De REFORÇO, id de hardware começando em 'PCI\VEN_8086&DEV_' - 8086 é o código PCI da Intel.

        Classe vazia cai em NÃO CLASSIFICADO, jamais em "é chipset": o rótulo da linha de grupo é mais
        frouxo que este filtro de propósito, e é por isso que a palavra "chipset" não aparece lá.

        O reforço pede UM id com o prefixo, e não todos. O erro caro aqui é o da recusa: quem não passa
        instala SEM ponto de restauração, e é justamente este pacote que a Intel documenta (000023446)
        sobrescrevendo o driver funcional do SMBus. Um lote da Intel, classe System, com um id ACPI no
        meio continua sendo o caso que precisa da rede de segurança.

        ProblemCode NÃO é critério - ele é lido só para o texto, e é por isso que sai daqui como
        contagem. As linhas que este agrupamento existe para dobrar são justamente as de problema 28;
        usá-lo como critério faria o filtro sumir no dia em que o Windows resolvesse o problema.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; ProblemCount = <int> }
    #>
    param($Group)

    # 28 é CM_PROB_FAILED_INSTALL: o dispositivo está lá, sem driver, e aparece sem nome no
    # Gerenciador de Dispositivos. É a contagem que o texto da confirmação usa para dizer quantos.
    $semNome = @(@($Group.ProblemCodes) | Where-Object { [int]$_ -eq 28 }).Count
    if ([string]$Group.Class -ne 'System') { return @{ Ok = $false; Reason = "classe '$([string]$Group.Class)' não é System"; ProblemCount = $semNome } }
    if ([string]$Group.Provider -notmatch '^(?i)intel$') { return @{ Ok = $false; Reason = "fornecedor '$([string]$Group.Provider)' não é Intel"; ProblemCount = $semNome } }
    $daIntel = @(@($Group.HardwareIds) | Where-Object { [string]$_ -like 'PCI\VEN_8086&DEV_*' }).Count
    if ($daIntel -lt 1) { return @{ Ok = $false; Reason = 'nenhum id de hardware do lote começa em PCI\VEN_8086&DEV_'; ProblemCount = $semNome } }
    return @{ Ok = $true; Reason = ''; ProblemCount = $semNome }
}

function Get-WinForgeRestorePointTime {
    <#
    .SYNOPSIS
        A data de criação de um ponto de restauração, nas três formas em que ela chega.
    .DESCRIPTION
        Get-ComputerRestorePoint devolve CreationTime no formato do WMI ('yyyyMMddHHmmss.ffffff±UUU'),
        e o próprio objeto sabe convertê-lo. Fixture de teste traz [datetime] direto. Data que não dá
        para ler devolve $null, e quem chama trata isso como "não sei quando" - nunca como "faz tempo".
    #>
    param($Point)

    if ($null -eq $Point) { return $null }
    $bruto = $Point.CreationTime
    if ($bruto -is [datetime]) { return $bruto }
    if ($null -eq $bruto) { return $null }
    try { if ($Point.PSObject.Methods['ConvertToDateTime']) { return [datetime]$Point.ConvertToDateTime($bruto) } } catch { }
    try { return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$bruto) } catch { }
    # TIPADA antes do [ref]: com $null o PS 5.1 não acha a sobrecarga e a linha estoura.
    [datetime]$lida = [datetime]::MinValue
    if ([datetime]::TryParse([string]$bruto, [ref]$lida)) { return $lida }
    return $null
}

function New-WinForgeChipsetRestorePoint {
    <#
    .SYNOPSIS
        Ponto de restauração antes do lote de chipset, CONFERIDO pela sequência.
    .DESCRIPTION
        Checkpoint-Computer é SILENCIOSAMENTE IGNORADO em dois casos comuns: com a Proteção do Sistema
        desligada no volume do Windows, e dentro da janela de 24 h desde o último ponto. Ele não
        devolve erro em nenhum dos dois - devolve sucesso e não cria nada. Acreditar nele seria
        prometer uma volta que não existe, e esta ação não tem Desfazer no WinForge.

        A única prova é a SEQUÊNCIA: a lista de pontos antes, a lista depois, e um número que não
        estava lá. Sem número novo, a resposta é não, com a razão dizendo os dois motivos e onde ligar
        a Proteção.
    .PARAMETER Before
    .PARAMETER After
        As duas listas prontas. É a porta do -SelfTest: com elas a função não cria ponto nenhum e não
        toca na máquina.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; SequenceNumber = <int> }
    #>
    param([object[]]$Before, [object[]]$After)

    # LER a lista é operação privilegiada por conta própria: medido nesta máquina, sem elevação
    # Get-ComputerRestorePoint responde 'Acesso negado' em vez de lista vazia. E falha de leitura NÃO
    # pode virar lista vazia em nenhuma das duas pontas: com a lista de ANTES vazia por erro, um ponto
    # ANTIGO conta como novo e a função responde sucesso sem nada ter sido criado - que é o caso mais
    # provável de todos, porque o Windows não cria um segundo ponto dentro de 24 h. O lote não roda
    # em nenhum dos dois casos, e o motivo diz qual foi.
    $wfRecusaLeitura = 'A lista de pontos de restauração não pôde ser lida, então não há como confirmar que o ponto foi criado. Por segurança o lote não foi instalado.'
    $daMaquina = -not ($PSBoundParameters.ContainsKey('Before') -and $PSBoundParameters.ContainsKey('After'))
    if ($daMaquina) {
        Assert-WinForgeNotSelfTest -Name 'New-WinForgeChipsetRestorePoint'
        try { $Before = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch {
            return @{ Ok = $false; Reason = $wfRecusaLeitura; SequenceNumber = 0 }
        }
        try {
            Checkpoint-Computer -Description 'WinForge - antes do lote do Windows Update' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        } catch {
            return @{ Ok = $false; Reason = "O ponto de restauração não pôde ser criado: $($_.Exception.Message)"; SequenceNumber = 0 }
        }
        try { $After = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch {
            return @{ Ok = $false; Reason = $wfRecusaLeitura; SequenceNumber = 0 }
        }
    }

    $antigos = @(@($Before) | ForEach-Object { [int]$_.SequenceNumber })
    $novos = @(@($After) | Where-Object { [int]$_.SequenceNumber -notin $antigos })
    if (-not $novos.Count) {
        # As duas causas mandam o usuário para lugares DIFERENTES, e a data que separa as duas já está
        # na lista que acabou de ser lida. Dizer "ligue a Proteção do Sistema" a quem a tem ligada -
        # e só esbarrou na janela de 24 h - é mandar consertar o que não está quebrado.
        $ultimo = @(@($After) | Sort-Object { [int]$_.SequenceNumber })[-1]
        $quando = Get-WinForgeRestorePointTime -Point $ultimo
        $recente = ($null -ne $quando -and ((Get-Date) - $quando).TotalHours -lt 24)
        $aMao = 'Você também pode criar o ponto à mão em Painel de Controle > Sistema > Proteção do Sistema > Criar.'
        if ($recente) {
            return @{ Ok = $false
                      Reason = "Não foi criado ponto de restauração: já existe um de $($quando.ToString('dd/MM/yyyy HH:mm')), e o Windows não cria outro nas 24 h seguintes. $aMao"
                      SequenceNumber = 0 }
        }
        return @{ Ok = $false
                  Reason = "Não foi criado ponto de restauração: a Proteção do Sistema está desligada no disco do Windows, e o Windows ignora o pedido em silêncio quando ela está. Ligue em Painel de Controle > Sistema > Proteção do Sistema e tente de novo. $aMao"
                  SequenceNumber = 0 }
    }
    return @{ Ok = $true; Reason = ''; SequenceNumber = [int](@($novos | ForEach-Object { [int]$_.SequenceNumber }) | Sort-Object)[-1] }
}

function Get-WinForgeChipsetConfirmText {
    <#
    .SYNOPSIS
        O texto da confirmação do lote de chipset: o que muda, o que não muda e o que não volta.
    .DESCRIPTION
        Estas entradas só informam ao Windows o nome do componente. O ganho é de NOME, e é assim que
        ele é dito - sem promessa de velocidade, que é o que o marketing de utilitário de fabricante
        promete e que este pacote não entrega.

        O que fica de fora ante o pacote do fabricante também é dito: ele traz cobertura offline,
        versão de pacote e entrada em Aplicativos e recursos. Nada disso vem por esta via.

        E o aviso do que não volta: o WinForge não tem Desfazer para isto. A única volta é
        Propriedades > Driver > Reverter Driver, dispositivo por dispositivo, e é por isso que o ponto
        de restauração vem antes.
    #>
    param($Group)

    $quantos = @(@($Group.Members)).Count
    $semNome = @(@($Group.ProblemCodes) | Where-Object { [int]$_ -eq 28 }).Count
    $linhas = [System.Collections.Generic.List[string]]::new()
    $linhas.Add("O WinForge vai instalar $quantos entradas de informação da Intel pelo Windows Update, uma de cada vez.")
    $linhas.Add('')
    if ($semNome -gt 0) {
        $linhas.Add("O que muda: $semNome dispositivo(s) deste PC hoje aparecem sem nome no Gerenciador de Dispositivos, e cada um passa a mostrar o nome real no Gerenciador de Dispositivos.")
    } else {
        $linhas.Add('Nenhum dispositivo deste PC está sem nome. Instalar não traria efeito visível.')
    }
    $linhas.Add('O que não muda: desempenho, estabilidade e consumo de energia - estas entradas não trazem programa nenhum, só informam ao Windows o nome do componente.')
    $linhas.Add('')
    $linhas.Add('O que o pacote do fabricante tem e esta via não tem: cobertura offline (o instalador da Intel roda sem internet), versão de pacote para conferência e entrada em Aplicativos e recursos.')
    $linhas.Add('')
    $linhas.Add('ATENÇÃO: não há como desfazer isto pelo WinForge. A única volta é abrir o Gerenciador de Dispositivos, entrar em Propriedades > Driver e usar Reverter Driver em cada dispositivo. Por isso o WinForge cria um ponto de restauração antes de começar.')
    return (@($linhas.ToArray()) -join [Environment]::NewLine)
}

function Get-WinForgeWindowsUpdateGroupId {
    <#
    .SYNOPSIS
        O id sintético de um lote: 'grupo:<hash da chave>'.
    .DESCRIPTION
        Existe como função porque DOIS lugares precisam do mesmo id a partir da mesma chave - o
        agrupamento, que monta a linha, e a formatação da linha de grupo da tabela, que recebe só o
        grupo. Duas cópias da fórmula seriam dois lugares para mudar, e o dia em que uma mudasse a
        linha deixaria de casar com o estado guardado por id.

        Ele identifica a LINHA, e não um estado: o estado de instalação é guardado por MEMBRO, e o da
        linha de grupo é derivado dos membros a cada remontagem - este id nunca é chave em
        $sync.DiagWUState. O que ele precisa ser é ESTÁVEL entre duas remontagens da mesma tabela,
        senão a linha trocaria de identidade a cada repintura, com a seleção e o clique junto.

        O hash é o da própria string e não é criptográfico de propósito:
        [SHA256]::Create() estoura em máquina com FIPS ligado, e esta conta acontece na thread da
        janela, montando a tabela - uma exceção ali apaga a tabela inteira.
    #>
    param([string]$Key)

    return ('grupo:' + ('{0:x8}' -f ([string]$Key).GetHashCode()))
}

function New-WinForgeWindowsUpdateNullDriverGroup {
    <#
    .SYNOPSIS
        O registro de um lote de INF sem versão: o que a linha de grupo mostra e o que o filtro de
        chipset vai perguntar.
    .DESCRIPTION
        Só COPIA - não decide nada. Fornecedor, classe e data saem do primeiro membro com a caixa
        ORIGINAL: a chave do agrupamento é minúscula porque o serviço não é consistente na caixa, mas
        o texto que a pessoa lê não tem por que ser.

        As quatro listas por membro saem na ORDEM ORIGINAL e com o mesmo comprimento. HardwareIds é
        obrigatório: é ele que o filtro de chipset usa para exigir o 'PCI\VEN_8086&DEV_' do
        fabricante, e sem ele aquele filtro leria vazio em produção e recusaria todo lote de verdade.

        A cópia dos campos por membro mora AQUI, e não em Group-WinForgeWindowsUpdateNullDrivers, por
        causa de uma trava: o -SelfTest proíbe o nome singular do campo de problema dentro da função
        do CRITÉRIO, que é onde ele realmente não pode entrar. Ele não decide nada em lugar nenhum -
        as linhas que este agrupamento existe para dobrar são justamente as de problema 28, e usá-lo
        como critério faria o agrupamento sumir no dia em que o Windows resolvesse o problema.
    #>
    param([string]$Key, $Members)

    $lista = @($Members)
    return @{
        Key          = [string]$Key
        Provider     = [string]$lista[0].Provider
        Class        = [string]$lista[0].Class
        Date         = [string]$lista[0].Date
        Members      = @($lista | ForEach-Object { [string]$_.UpdateId })
        MemberTitles = @($lista | ForEach-Object { [string]$_.Title })
        HardwareIds  = @($lista | ForEach-Object { [string]$_.HardwareId })
        ProblemCodes = @($lista | ForEach-Object { [int]$_.ProblemCode })
    }
}

function Search-WinForgeWindowsUpdateDrivers {
    <#
    .SYNOPSIS
        Drivers que o Windows Update tem para este computador e ainda não foram instalados.
    .DESCRIPTION
        Consulta que pode levar de 10 a 60 segundos (o serviço fala com os servidores da Microsoft),
        então quem chama deve rodá-la num runspace. Falha - serviço desligado, sem rede, política de
        WSUS - devolve array vazio e deixa a mensagem em $sync.LastWUError.

        As linhas devolvidas são TEXTO, para a tabela e para o relatório. O objeto IUpdate de cada
        uma fica em $sync.DiagWUUpdates, indexado pelo UpdateID: instalar exige o objeto COM
        original (a coleção que o downloader recebe é de IUpdate, não de título), e recriá-lo a
        partir da linha significaria uma segunda busca de um minuto. O mapa é refeito a cada busca -
        um objeto de uma busca anterior aponta para uma sessão que já foi embora.
    #>
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found    = $searcher.Search("IsInstalled=0 and Type='Driver'")
        try { if ($sync) { $sync.DiagWUUpdates = @{} } } catch { }
        return @(foreach ($u in $found.Updates) {
            $date = ''
            try { if ($u.DriverVerDate) { $date = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch { }
            # A versão não tem campo próprio na API: sai do título, nas duas formas que o serviço usa.
            $version = Get-WinForgeWindowsUpdateDriverVersion -Title ([string]$u.Title)
            $updateId = ''
            try { $updateId = [string]$u.Identity.UpdateID } catch { $updateId = '' }
            if ($updateId) { try { if ($sync -and $sync.DiagWUUpdates) { $sync.DiagWUUpdates[$updateId] = $u } } catch { } }
            # A classe separa o driver base do INF de extensão do MESMO dispositivo - os dois vêm
            # com DriverModel e DriverProvider iguais. Nem toda atualização traz o campo, e o
            # acesso a uma propriedade COM que não existe estoura: vazio é resposta válida.
            $class = ''
            try { if ($u.DriverClass) { $class = [string]$u.DriverClass } } catch { $class = '' }
            # Os três campos que o agrupamento dos INFs sem versão lê, cada um no SEU try/catch: são
            # propriedades de IWindowsDriverUpdate e o acesso a uma que não exista estoura - num try
            # só, a primeira que faltasse zeraria as outras duas. Zero é a resposta segura em todos:
            # tamanho desconhecido não agrupa, e o que não agrupa continua VISÍVEL na tabela.
            $sizeBytes = [long]0
            try { $sizeBytes = [long]$u.MaxDownloadSize } catch { $sizeBytes = [long]0 }
            # MaxDownloadSize é 0 em oferta que o serviço ainda não dimensionou; MinDownloadSize é o
            # mesmo número por outro caminho, e vale mais que desistir.
            if ($sizeBytes -le 0) { try { $sizeBytes = [long]$u.MinDownloadSize } catch { $sizeBytes = [long]0 } }
            $hardwareId = ''
            try { if ($u.DriverHardwareID) { $hardwareId = [string]$u.DriverHardwareID } } catch { $hardwareId = '' }
            # Só para o TEXTO da linha: o código de problema não decide agrupamento nenhum.
            $problema = 0
            try { $problema = [int]$u.DeviceProblemNumber } catch { $problema = 0 }
            [pscustomobject]@{
                Title       = [string]$u.Title
                Driver      = [string]$u.DriverModel
                Provider    = [string]$u.DriverProvider
                Class       = $class
                Version     = $version
                Date        = $date
                KB          = (@($u.KBArticleIDs) -join ',')
                UpdateId    = $updateId
                SizeBytes   = $sizeBytes
                HardwareId  = $hardwareId
                ProblemCode = $problema
            }
        })
    } catch {
        try { if ($sync) { $sync.LastWUError = $_.Exception.Message } } catch { }
        return @()
    }
}

function Test-WinForgeNvidiaDownloadUrl {
    <#
    .SYNOPSIS
        Diz se um endereço pode ser baixado como instalador oficial da NVIDIA.
    .DESCRIPTION
        Duas exigências, e as duas são sobre o que o WinForge vai ABRIR depois com a elevação dele:

        1. https. Em http qualquer um no caminho troca o corpo da resposta, e a conferência de
           assinatura viria depois de o arquivo já estar no disco.
        2. O HOST tem de ser nvidia.com ou terminar em '.nvidia.com'. A comparação é pelo host que
           o parser de URI extrai, e não por procurar 'nvidia.com' no texto: 'https://nvidia.com.evil.com/x.exe'
           contém 'nvidia.com' e é de outra pessoa. O ponto antes do domínio também é obrigatório -
           sem ele, 'www.nvidia.com.br' passaria.

        O endereço vem do catálogo da própria NVIDIA (campo DownloadURL), mas ele chega pela rede:
        é dado de fora, e dado de fora que vira caminho de execução é conferido.
    #>
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $uri = $null
    try { $uri = [uri]$Url } catch { return $false }
    if (-not $uri.IsAbsoluteUri) { return $false }
    if ($uri.Scheme -ne 'https') { return $false }
    $host_ = [string]$uri.Host
    if ([string]::IsNullOrWhiteSpace($host_)) { return $false }
    if ($host_ -eq 'nvidia.com') { return $true }
    return $host_.EndsWith('.nvidia.com', [StringComparison]::OrdinalIgnoreCase)
}

function Get-WinForgeDriverAction {
    <#
    .SYNOPSIS
        Que ação a linha de um driver oferece: baixar o driver oficial, abrir a página do fabricante
        ou nada.
    .DESCRIPTION
        Uma linha só ganha o botão de DOWNLOAD quando as três condições valem juntas: é uma placa
        NVIDIA, o catálogo diz que ela está atrás e o link do instalador passa pela conferência de
        domínio. Faltando qualquer uma delas, sobra a página do fabricante - que é abrir um endereço
        no navegador, sem download e sem execução. Sem nem isso, a linha não tem botão.

        Função pura: decide a partir da linha do inventário e não toca em rede nem em disco. Quem
        preenche 'LatestUrl' é Update-WinForgeProfileDriverStatus, com o link que veio do catálogo.
    .OUTPUTS
        @{ Kind = 'nvidia-download' | 'vendor-page' | 'none'; Label = <texto do botão>; Url = <endereço> }.
    #>
    param($Driver)

    $acao = @{ Kind = 'none'; Label = ''; Url = $null }
    if ($null -eq $Driver) { return $acao }

    $versao = [string]$Driver.Latest
    if ([string]$Driver.Vendor -eq 'nvidia' -and [string]$Driver.Status -eq 'atualizar' -and
        -not [string]::IsNullOrWhiteSpace($versao) -and (Test-WinForgeNvidiaDownloadUrl -Url ([string]$Driver.LatestUrl))) {
        $acao.Kind = 'nvidia-download'
        $acao.Label = "Baixar $versao"
        $acao.Url = [string]$Driver.LatestUrl
        return $acao
    }

    $pagina = [string]$Driver.Url
    if (-not [string]::IsNullOrWhiteSpace($pagina)) {
        $acao.Kind = 'vendor-page'
        $acao.Label = 'Página do fabricante'
        $acao.Url = $pagina
    }
    return $acao
}

function Resolve-WinForgeNvidiaDownloadTarget {
    <#
    .SYNOPSIS
        CONSULTA AO VIVO: pergunta ao catálogo da NVIDIA, agora, qual é o driver mais novo da placa
        da linha, e diz se ele pode ser baixado.
    .DESCRIPTION
        A tabela é desenhada a partir do cache do catálogo, que mora no perfil do usuário
        (Get-WinForgeCacheRoot) e por isso é gravável por qualquer processo de integridade média da
        mesma conta. Enquanto isso só pinta um rótulo na tela, tudo bem. Só que até aqui a LINHA -
        e portanto o cache - também dizia ao motor ELEVADO que endereço baixar e abrir, e um
        '{ "Version": "999.99", "DownloadURL": "https://us.download.nvidia.com/<outro pacote>" }'
        plantado ali passava por todas as travas seguintes por construção: o host é da nvidia.com,
        a assinatura é da NVIDIA, a pasta é a protegida. O usuário via "⬆ atualizar / Baixar 999.99"
        e clicava.

        Então o cache é DE TELA e mais nada. No clique, as três consultas são refeitas sem tocar em
        nenhum arquivo de cache (-NoCache: as duas listas e a busca do driver), e o que vai para
        Install-WinForgeNvidiaDriver é o par Url/Version que acabou de chegar do catálogo.

        Três recusas, e qualquer uma basta:
        1. A consulta ao vivo não respondeu 'ok' (sem rede, placa fora do catálogo).
        2. O endereço ao vivo não passa em Test-WinForgeNvidiaDownloadUrl.
        3. A versão ao vivo não é MAIOR que a instalada. Sem isso, o botão baixaria e abriria um
           instalador ANTIGO - que continua assinado pela NVIDIA e continua vindo do host certo, e
           é exatamente o que alguém escolheria para reintroduzir uma falha já corrigida. A versão
           instalada sai da própria linha (ConvertTo-WinForgeNvidiaVersion sobre a versão do
           inventário): não dá para compará-la, não se baixa - fecha fechado.
    .PARAMETER Row
        A linha da tabela (a que veio na Tag do botão). Usa só Device e Version.
    .PARAMETER Root
        Pasta de cache própria (usada pelo -SelfTest).
    .PARAMETER Resolver
        Costura de teste - ver Get-WinForgeNvidiaCatalog.
    .OUTPUTS
        @{ Ok; Url; Version; Installed; Reason }.
    #>
    param($Row, [string]$Root, [scriptblock]$Resolver)

    $alvo = @{ Ok = $false; Url = $null; Version = $null; Installed = $null; Reason = '' }
    if ($null -eq $Row) { $alvo.Reason = 'linha vazia'; return $alvo }

    $placa = [string]$Row.Device
    $isWin11 = $true
    $isLaptop = $false
    try { if ($sync -and $sync.Profile -and $sync.Profile.OS) { $isWin11 = [bool]$sync.Profile.OS.IsWin11 } } catch { }
    try { if ($sync -and $sync.Profile -and $sync.Profile.Machine) { $isLaptop = [bool]$sync.Profile.Machine.IsLaptop } } catch { }

    $vivo = Get-WinForgeNvidiaLatestDriver -GpuName $placa -IsWin11 $isWin11 -IsLaptop $isLaptop -NoCache -Root $Root -Resolver $Resolver
    if ([string]$vivo.Status -ne 'ok') {
        $alvo.Reason = "a consulta ao vivo ao catálogo da NVIDIA respondeu '$([string]$vivo.Status)'"
        return $alvo
    }
    if (-not (Test-WinForgeNvidiaDownloadUrl -Url ([string]$vivo.Url))) {
        $alvo.Reason = "o endereço que o catálogo devolveu agora não é um https de um host da nvidia.com"
        return $alvo
    }

    $instalada = ConvertTo-WinForgeNvidiaVersion ([string]$Row.Version)
    $alvo.Installed = $instalada
    if ([string]::IsNullOrWhiteSpace([string]$instalada)) {
        $alvo.Reason = "não foi possível ler a versão instalada da linha ('$([string]$Row.Version)') para comparar com a do catálogo"
        return $alvo
    }
    $maisNova = $false
    try { $maisNova = ([version][string]$vivo.Version -gt [version][string]$instalada) } catch { $maisNova = $false }
    if (-not $maisNova) {
        $alvo.Reason = "a versão do catálogo ($([string]$vivo.Version)) não é mais nova que a instalada ($instalada)"
        return $alvo
    }

    $alvo.Ok = $true
    $alvo.Url = [string]$vivo.Url
    $alvo.Version = [string]$vivo.Version
    return $alvo
}

function Get-WinForgeNvidiaDownloadSizeText {
    <#
    .SYNOPSIS
        Tamanho estimado do instalador, para a caixa de confirmação.
    .DESCRIPTION
        Um HEAD no mesmo endereço que seria baixado, com as mesmas regras do download
        (-MaximumRedirection 0, host conferido antes). Content-Length ausente, servidor que não
        responde a HEAD, tempo esgotado: volta o texto genérico. É informação para o usuário
        decidir, não uma trava - nada depende deste número.
    .OUTPUTS
        Texto pronto para a frase da caixa ('712 MB' ou 'várias centenas de MB').
    #>
    param([Parameter(Mandatory)][string]$Url, [int]$TimeoutSec = 10)

    $generico = 'várias centenas de MB'
    if (-not (Test-WinForgeNvidiaDownloadUrl -Url $Url)) { return $generico }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $resposta = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 0 -ErrorAction Stop
        $bruto = ''
        try { $bruto = [string](@($resposta.Headers['Content-Length'])[0]) } catch { $bruto = '' }
        [long]$bytes = 0
        if ([long]::TryParse($bruto, [ref]$bytes) -and $bytes -gt 0) {
            return ('{0} MB' -f [math]::Round($bytes / 1MB))
        }
    } catch { }
    return $generico
}

function Remove-WinForgeOldNvidiaInstallers {
    <#
    .SYNOPSIS
        Apaga os instaladores NVIDIA antigos da pasta de downloads, deixando só o que acabou de ser
        aberto.
    .DESCRIPTION
        Cada versão baixa um 'nvidia-<versão>.exe' de uns 700 MB em %ProgramData%\WinForge\downloads
        e ninguém apagava o anterior: quem atualiza três vezes deixa dois gigabytes parados numa
        pasta que ele nem sabe que existe.

        A limpeza roda DEPOIS do Start-Process e com o pino do arquivo já solto (apagar exige
        DELETE, e é justamente o que o pino nega), e só se a cadeia de pastas continuar confiável -
        uma junção plantada no lugar de 'downloads' transformaria esta função num apagador de
        arquivos escolhidos por outra pessoa. Cadeia reprovada: não apaga nada e diz por quê.

        O filtro é 'nvidia-*.exe', que é o nome que Install-WinForgeNvidiaDriver monta - arquivos
        que o WinForge não colocou ali não são dele para apagar.
    .PARAMETER Keep
        Caminho que NÃO deve ser apagado (o instalador recém-aberto).
    .PARAMETER DryRun
        Só lista o que apagaria, sem conferir cadeia e sem apagar.
    .OUTPUTS
        @{ Candidates = @(caminhos); Removed = @(caminhos); Reason = <string> }.
    #>
    param([Parameter(Mandatory)][string]$Folder, [string]$Keep, [switch]$DryRun)

    $res = @{ Candidates = @(); Removed = @(); Reason = '' }
    $res.Candidates = @(Get-ChildItem -LiteralPath $Folder -Filter 'nvidia-*.exe' -File -ErrorAction SilentlyContinue |
        Where-Object { -not ($Keep -and [string]::Equals([string]$_.FullName, [string]$Keep, [StringComparison]::OrdinalIgnoreCase)) } |
        ForEach-Object { [string]$_.FullName })
    if ($DryRun) { $res.Reason = '[simulação] nada foi apagado'; return $res }
    if (-not $res.Candidates.Count) { return $res }

    $cadeia = Test-WinForgeSnapshotRootPath -Root $Folder
    if (-not $cadeia.Trusted) {
        $res.Reason = "limpeza recusada: a pasta '$Folder' não é confiável ($($cadeia.Reason))"
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message $res.Reason
        return $res
    }
    $apagados = New-Object System.Collections.Generic.List[string]
    foreach ($velho in $res.Candidates) {
        try {
            Remove-Item -LiteralPath $velho -Force -ErrorAction Stop
            $apagados.Add($velho)
        } catch {
            Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Instalador antigo '$velho' não pôde ser apagado: $($_.Exception.Message)"
        }
    }
    $res.Removed = @($apagados)
    if ($res.Removed.Count) {
        Write-WinForgeLog -Component "Diag" -Message "Instalador(es) NVIDIA antigo(s) apagado(s) da pasta de downloads: $($res.Removed.Count)"
    }
    return $res
}

function Get-WinForgeDownloadRoot {
    <#
    .SYNOPSIS
        Pasta dos arquivos baixados (%ProgramData%\WinForge\downloads). -Root existe para o teste
        não escrever em %ProgramData%.
    .DESCRIPTION
        Só monta o caminho, normalizado uma vez ([System.IO.Path]::GetFullPath) como a pasta de
        backup: daqui para baixo todo mundo conta com a mesma forma. Quem cria e quem confere é
        Confirm-WinForgeDownloadRoot.

        A base é Get-WinForgeMachineDataRoot - a MESMA da pasta de backup e a mesma da parada da
        cadeia -, e não $env:ProgramData: variável de usuário não escolhe a pasta em que o motor
        elevado grava um instalador que ele mesmo vai abrir.
    #>
    param([string]$Root)

    $alvo = if ($Root) { $Root } else { (Join-Path (Get-WinForgeMachineDataRoot) 'WinForge\downloads') }
    try { return [System.IO.Path]::GetFullPath($alvo) } catch { return $alvo }
}

function Confirm-WinForgeDownloadRoot {
    <#
    .SYNOPSIS
        Garante que a pasta de downloads existe e é confiável, ANTES de qualquer byte chegar nela.
    .DESCRIPTION
        Mesmas regras da pasta de backup, e pelas mesmas funções: DACL própria sem herança
        (New-WinForgeSnapshotRoot), nenhuma pasta da cadeia pode ser ponto de reanálise, dono dentro
        de SYSTEM/Administradores e ninguém de fora deles com escrita
        (Test-WinForgeSnapshotRootTrusted), mais a ACE herdável de OWNER RIGHTS
        (Repair-WinForgeSnapshotRootOwnerRight).

        O que muda em relação a Confirm-WinForgeSnapshotRoot é uma coisa só, e é de propósito: aqui
        NUNCA se passa -ExplicitRoot, nem quando -Root vem preenchido. Aquele afrouxamento existe
        para a pasta de teste em %TEMP% poder ter a identidade atual como dona; a pasta de downloads
        não pode. O que sai daqui é um instalador que o WinForge ABRE com a elevação dele - se um
        processo de integridade média da mesma conta puder escrever na pasta, ele troca o arquivo
        entre a conferência da assinatura e o Start-Process, e o WinForge abre o dele. É exatamente
        o furo que tirou o download do DirectX do programa; a diferença aqui é a pasta protegida.

        Consequência prática: sem elevação a pasta nasce com a identidade atual como dona e esta
        função RECUSA. O download não acontece, e a mensagem diz por quê - melhor que baixar para
        uma pasta que a própria conta reescreve.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Path = <pasta> }.
    #>
    param([string]$Root)

    $dir = Get-WinForgeDownloadRoot $Root
    # Criar pode simplesmente não ser permitido: %ProgramData%\WinForge é de SYSTEM/Administradores,
    # e uma execução sem elevação não escreve lá dentro. Isso é recusa, não exceção - quem chamou
    # precisa de um motivo para mostrar, e não de uma pilha de erro.
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-WinForgeSnapshotRoot -Root $dir | Out-Null }
        catch { return @{ Ok = $false; Reason = "não foi possível criar '$dir': $($_.Exception.Message)"; Path = $dir } }
        if (-not (Test-Path -LiteralPath $dir)) { return @{ Ok = $false; Reason = "a pasta '$dir' não pôde ser criada"; Path = $dir } }
    }
    $t = Test-WinForgeSnapshotRootTrusted -Root $dir
    if (-not $t.Trusted) { return @{ Ok = $false; Reason = $t.Reason; Path = $dir } }
    $dono = Repair-WinForgeSnapshotRootOwnerRight -Root $dir
    if (-not $dono.Ok) { return @{ Ok = $false; Reason = "pasta de downloads sem proteção de dono ('$dir'): $($dono.Reason)"; Path = $dir } }
    return @{ Ok = $true; Reason = ''; Path = $dir }
}

function Test-WinForgeNvidiaSigner {
    <#
    .SYNOPSIS
        Diz se o arquivo está assinado pela NVIDIA Corporation, com assinatura válida.
    .DESCRIPTION
        Duas perguntas, e as duas precisam de resposta:

        1. Get-AuthenticodeSignature devolve 'Valid'? Isso cobre arquivo sem assinatura, assinatura
           quebrada (o arquivo mudou depois de assinado) e cadeia que não chega a uma raiz confiável.
        2. O RDN 'O' do assunto do certificado é EXATAMENTE 'NVIDIA Corporation'? Procurar o texto
           dentro do assunto inteiro aceitaria 'O=NVIDIA Corporation Ltd' e qualquer certificado com
           'CN=NVIDIA Corporation' - a linha que diz de quem é a organização é o O, e a comparação é
           por igualdade.

        Um assunto com DOIS RDN 'O' é recusado: assunto legítimo tem um só, e dois é a forma óbvia
        de esconder o nome do fabricante ao lado do de quem assinou de verdade.
    .OUTPUTS
        $true ou $false. O motivo da recusa vai para o log.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Assinatura: '$Path' não existe."
        return $false
    }
    $sig = $null
    try { $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop } catch {
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Assinatura de '$Path' não pôde ser lida: $($_.Exception.Message)"
        return $false
    }
    if ($null -eq $sig -or [string]$sig.Status -ne 'Valid') {
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Assinatura de '$Path': situação '$(if ($sig) { $sig.Status } else { 'nenhuma' })', esperado 'Valid'."
        return $false
    }
    $cert = $sig.SignerCertificate
    if ($null -eq $cert) {
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Assinatura de '$Path': sem certificado de quem assinou."
        return $false
    }
    $orgs = @((Split-WinForgeCertificateSubject -Subject ([string]$cert.Subject))['O'])
    if ($orgs.Count -ne 1 -or [string]$orgs[0] -ne 'NVIDIA Corporation') {
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Assinatura de '$Path': organização '$($orgs -join ' | ')', esperado exatamente 'NVIDIA Corporation'."
        return $false
    }
    return $true
}

function Get-WinForgeDownloadFailureText {
    <#
    .SYNOPSIS
        Traduz o erro de um download que falhou para o texto que vai para o log e para a barra de
        status, dizendo REDIRECIONAMENTO quando foi disso que se tratou.
    .DESCRIPTION
        O download roda com -MaximumRedirection 0 de propósito: os endereços do catálogo da NVIDIA
        são diretos, e seguir um redirecionamento é aceitar um host que Test-WinForgeNvidiaDownloadUrl
        nunca viu. Só que a recusa precisa CHEGAR ao usuário, e no PowerShell 5.1 ela não vem escrita
        na mensagem: o Invoke-WebRequest levanta um erro cujo Exception.Message é genérico, e a única
        coisa que nomeia o motivo é o FullyQualifiedErrorId, que começa com 'MaximumRedirectExceeded'.
        Procurar 'redirec' na mensagem - que era o que se fazia - só funcionava por acaso, e não
        funcionava no 5.1: o usuário via um erro de rede qualquer no lugar de "recusei porque
        tentaram me mandar para outro lugar".

        Então são quatro sinais, e qualquer um deles basta: o FQID, o texto da mensagem, o
        ErrorDetails.Message (que é onde alguns cmdlets põem o texto de verdade) e um código de
        resposta 3xx. 'redirec' pega tanto "redirection" quanto "redirecionamento" - a mensagem do
        Invoke-WebRequest vem no idioma do Windows.
    .PARAMETER ErrorRecord
        O erro capturado no catch.
    .OUTPUTS
        O texto da causa, em português.
    #>
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $causa = ''
    try { $causa = [string]$ErrorRecord.Exception.Message } catch { $causa = '' }
    if ([string]::IsNullOrWhiteSpace($causa)) { $causa = [string]$ErrorRecord }
    $fqid = ''
    try { $fqid = [string]$ErrorRecord.FullyQualifiedErrorId } catch { $fqid = '' }
    $detalhe = ''
    try { if ($ErrorRecord.ErrorDetails) { $detalhe = [string]$ErrorRecord.ErrorDetails.Message } } catch { $detalhe = '' }
    $codigo = $null
    try { $codigo = [int]$ErrorRecord.Exception.Response.StatusCode } catch { $codigo = $null }

    $redirecionou = ($fqid -like 'MaximumRedirectExceeded*') -or
                    ($causa -match 'redirec') -or ($detalhe -match 'redirec') -or
                    ($null -ne $codigo -and $codigo -ge 300 -and $codigo -lt 400)
    if ($redirecionou) { return "o servidor tentou redirecionar o download; recusado ($causa)" }
    return $causa
}

function Install-WinForgeNvidiaDriver {
    <#
    .SYNOPSIS
        Baixa o instalador oficial do driver NVIDIA para a pasta protegida, confere a assinatura e o
        abre para o usuário concluir.
    .DESCRIPTION
        A ordem das travas é o que faz esta função ser diferente do download que saiu do programa no
        Plano 5:

        1. O endereço é conferido ANTES de tudo, inclusive antes do -DryRun: uma simulação com URL
           de terceiro não simula nada, e a recusa acontece mesmo no dia em que o -DryRun se perder
           outra vez em $args.
        2. -DryRun devolve só o endereço e o caminho de destino, sem tocar em rede nem em disco.
        3. Assert-WinForgeNotSelfTest logo depois: em modo SelfTest nada é baixado.
        4. A pasta de destino é criada e conferida (Confirm-WinForgeDownloadRoot) - sem elevação,
           ela recusa e o download não começa.
        5. O arquivo baixa com nome '.parcial' e só depois vira o nome final: um download
           interrompido não deixa para trás algo com cara de instalador pronto. O download não
           segue redirecionamento (-MaximumRedirection 0): os links da NVIDIA são diretos, e um
           redirecionamento levaria o arquivo para um host que a conferência de endereço já julgou.
        6. Renomeado, o arquivo é FIXADO: um handle aberto com FileShare.Read fica preso nele até o
           instalador subir. Renomear ou apagar exige DELETE, e DELETE só é concedido se o handle
           aberto tiver compartilhado FILE_SHARE_DELETE - que este não compartilha. É o que fecha a
           janela entre a conferência e o Start-Process. WRITE_DAC e WRITE_OWNER não passam pelo
           modo de compartilhamento (ele só governa leitura, escrita de dados e exclusão), e leitura
           está compartilhada: por isso o endurecimento e o Get-AuthenticodeSignature continuam
           funcionando com o pino aberto.
        7. Com o pino na mão: ENDURECIDO (dono Administradores, DACL SYSTEM+Administradores),
           reconferido (Test-WinForgeSnapshotFileTrusted) e só então a assinatura. Reprovou - ou
           qualquer passo acima falhou - o pino é solto, o arquivo é APAGADO, e a recusa vai para o
           log e para a barra de status.
        8. Imediatamente antes do Start-Process a cadeia de pastas é reconferida
           (Test-WinForgeSnapshotRootPath): o pino prende o ARQUIVO, mas o Start-Process resolve o
           CAMINHO de novo, e uma junção plantada no meio do caminho apontaria para outro arquivo.

        9. Com o instalador no ar, o pino é solto e os instaladores de versões anteriores são
           apagados da pasta (Remove-WinForgeOldNvidiaInstallers), com a cadeia conferida de novo.

        Quem instala é o usuário: o instalador da NVIDIA é interativo (licença, tipo de instalação,
        reinício), e fingir que o WinForge conduz isso seria mentira. O WinForge abre a janela dele.

        O par Url/Version NÃO vem da tabela: quem clica em "Baixar" passa por
        Resolve-WinForgeNvidiaDownloadTarget, que refaz a consulta ao catálogo na hora.
    .PARAMETER Root
        Pasta de downloads própria (usada pelos testes). Não afrouxa nenhuma regra - ver
        Confirm-WinForgeDownloadRoot.
    .OUTPUTS
        @{ Path; Verified; Started; Text }.
    #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Version,
        [string]$Root,
        [switch]$DryRun
    )

    if (-not (Test-WinForgeNvidiaDownloadUrl -Url $Url)) {
        throw "Recusado: '$Url' não é um endereço https de um host da nvidia.com."
    }

    # O nome do arquivo é montado AQUI, e não tirado do fim da URL: o último segmento de um endereço
    # é texto de fora, e texto de fora não escolhe caminho no disco.
    $limpa = ([string]$Version) -replace '[^0-9A-Za-z\.\-]', '_'
    if ([string]::IsNullOrWhiteSpace($limpa)) { $limpa = 'driver' }
    $nome = "nvidia-$limpa.exe"
    $destino = Join-Path (Get-WinForgeDownloadRoot $Root) $nome

    if ($DryRun) {
        return @{ Path = $destino; Verified = $false; Started = $false; Text = "[simulação] baixaria o driver NVIDIA $Version de '$Url' para '$destino'" }
    }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $raiz = Confirm-WinForgeDownloadRoot -Root $Root
    if (-not $raiz.Ok) {
        $msg = "Download recusado: a pasta '$($raiz.Path)' não é confiável -> $($raiz.Reason)"
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $msg
        return @{ Path = $null; Verified = $false; Started = $false; Text = $msg }
    }
    $destino = Join-Path $raiz.Path $nome
    $parcial = "$destino.parcial"

    try {
        # TLS 1.2 somado ao que já estiver habilitado, como na consulta ao catálogo: o padrão do
        # PowerShell 5.1 ainda é SSL3/TLS1.0 e os servidores da NVIDIA recusam.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Remove-Item -LiteralPath $parcial -Force -ErrorAction SilentlyContinue
        Write-WinForgeLog -Component "Diag" -Message "Baixando o driver NVIDIA $Version de $Url"
        # -UseBasicParsing: sem ele o Invoke-WebRequest tenta o motor do Internet Explorer, que não
        # existe em instalação limpa.
        # -TimeoutSec 600 limita a ESPERA PELOS CABEÇALHOS (é o HttpWebRequest.Timeout), e não a
        # transferência do corpo - um instalador de 700 MB numa linha lenta demora o que tiver de
        # demorar e não é cortado por este número. Os 600 s são para o servidor que aceita a conexão
        # e nunca responde.
        # -MaximumRedirection 0: os links do catálogo da NVIDIA são diretos. Seguir um
        # redirecionamento é aceitar um host que Test-WinForgeNvidiaDownloadUrl nunca viu.
        Invoke-WebRequest -Uri $Url -OutFile $parcial -UseBasicParsing -TimeoutSec 600 -MaximumRedirection 0 -ErrorAction Stop
        Move-Item -LiteralPath $parcial -Destination $destino -Force -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $parcial -Force -ErrorAction SilentlyContinue
        # Quem nomeia o motivo é Get-WinForgeDownloadFailureText: no PowerShell 5.1 a recusa de
        # redirecionamento só aparece no FullyQualifiedErrorId, não na mensagem.
        $causa = Get-WinForgeDownloadFailureText -ErrorRecord $_
        $msg = "Download do driver NVIDIA $Version falhou: $causa"
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $msg
        return @{ Path = $null; Verified = $false; Started = $false; Text = $msg }
    }

    # O PINO. Daqui até o instalador subir o arquivo não pode ser renomeado nem apagado por ninguém
    # - ver a nota 6 da descrição. Ele é solto no 'finally', depois de o Start-Process voltar.
    $pino = $null
    try {
        $recusa = $null
        try {
            $pino = [System.IO.File]::Open($destino, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        } catch {
            $recusa = "o arquivo baixado não pôde ser fixado para conferência ($($_.Exception.Message))"
        }
        if (-not $recusa) {
            $prot = Protect-WinForgeSnapshotFile -Path $destino
            if (-not $prot.Hardened) { $recusa = "o arquivo baixado não pôde ser protegido ($($prot.Reason))" }
        }
        if (-not $recusa) {
            $conf = Test-WinForgeSnapshotFileTrusted -Path $destino
            if (-not $conf.Trusted) { $recusa = "o arquivo baixado não passou na conferência de dono e permissões ($($conf.Reason))" }
        }
        if (-not $recusa -and -not (Test-WinForgeNvidiaSigner -Path $destino)) {
            $recusa = "o arquivo baixado não está assinado pela NVIDIA Corporation"
        }
        # A última coisa antes de abrir: o pino prende o arquivo, não o caminho.
        if (-not $recusa) {
            $cadeia = Test-WinForgeSnapshotRootPath -Root (Split-Path -Parent $destino)
            if (-not $cadeia.Trusted) { $recusa = "a pasta do download mudou entre a conferência e a abertura ($($cadeia.Reason))" }
        }
        if ($recusa) {
            # O pino sai ANTES do Remove-Item: apagar exige DELETE, e é justamente isso que ele nega.
            if ($pino) { $pino.Dispose(); $pino = $null }
            Remove-Item -LiteralPath $destino -Force -ErrorAction SilentlyContinue
            $msg = "Driver NVIDIA $Version recusado: $recusa. O arquivo foi apagado."
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $msg
            return @{ Path = $null; Verified = $false; Started = $false; Text = $msg }
        }

        try {
            Start-Process -FilePath $destino -ErrorAction Stop
        } catch {
            $msg = "Driver NVIDIA $Version baixado e conferido em '$destino', mas o instalador não abriu: $($_.Exception.Message)"
            Write-WinForgeLog -Component "Diag" -Level "WARN" -Message $msg
            return @{ Path = $destino; Verified = $true; Started = $false; Text = $msg }
        }
        $msg = "Driver NVIDIA $Version baixado, assinatura conferida, instalador aberto: $destino"
        Write-WinForgeLog -Component "Diag" -Message $msg
        # O instalador já subiu: o pino sai (apagar exige DELETE, que ele nega) e as versões
        # anteriores saem com ele - ver Remove-WinForgeOldNvidiaInstallers.
        if ($pino) { $pino.Dispose(); $pino = $null }
        Remove-WinForgeOldNvidiaInstallers -Folder (Split-Path -Parent $destino) -Keep $destino | Out-Null
        return @{ Path = $destino; Verified = $true; Started = $true; Text = $msg }
    } finally {
        if ($pino) { $pino.Dispose() }
    }
}

function Install-WinForgeWindowsUpdateDriver {
    <#
    .SYNOPSIS
        Instala um driver oferecido pelo Windows Update, pelo id da atualização.
    .DESCRIPTION
        O objeto IUpdate da busca é obrigatório: a coleção que o downloader e o instalador recebem é
        de IUpdate, não de título nem de id. Ele fica em $sync.DiagWUUpdates desde
        Search-WinForgeWindowsUpdateDrivers; se não estiver mais lá (o programa foi reaberto, ou uma
        busca nova refez o mapa), a função avisa e pede uma busca nova em vez de adivinhar.

        A licença é aceita antes do download quando a atualização exige - sem isso o download volta
        com erro de EULA. Aceitar aqui é o que o usuário já disse ao confirmar a instalação.

        Códigos de resultado do Windows Update: 2 concluída, 3 concluída com avisos, 4 falhou,
        5 cancelada. Eles vão para o texto, porque "instalado" e "instalado com aviso" são coisas
        diferentes para quem vai reiniciar a máquina depois.
    .OUTPUTS
        @{ ResultCode; RebootRequired; Text }.
    #>
    param(
        [Parameter(Mandatory)][string]$UpdateId,
        [switch]$DryRun
    )

    $titulo = '(não está mais na lista)'
    try {
        foreach ($linha in @($sync.DiagWUResults)) {
            if ($linha -and [string]$linha.UpdateId -eq $UpdateId) { $titulo = [string]$linha.Title; break }
        }
    } catch { }

    if ($DryRun) {
        return @{ ResultCode = $null; RebootRequired = $false; Text = "[simulação] instalaria '$titulo' (id $UpdateId)" }
    }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $update = $null
    try { if ($sync.DiagWUUpdates) { $update = $sync.DiagWUUpdates[$UpdateId] } } catch { $update = $null }
    if ($null -eq $update) {
        $msg = "A atualização '$UpdateId' não está mais na lista desta sessão. Busque os drivers no Windows Update de novo."
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message $msg
        return @{ ResultCode = $null; RebootRequired = $false; Text = $msg }
    }

    try {
        if (-not $update.EulaAccepted) { $update.AcceptEula() }
        $colecao = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$colecao.Add($update)
        $sessao = New-Object -ComObject Microsoft.Update.Session

        $baixador = $sessao.CreateUpdateDownloader()
        $baixador.Updates = $colecao
        $resDown = $baixador.Download()
        if ([int]$resDown.ResultCode -notin @(2, 3)) {
            $msg = "Download de '$titulo' pelo Windows Update terminou com código $($resDown.ResultCode)."
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $msg
            return @{ ResultCode = [int]$resDown.ResultCode; RebootRequired = $false; Text = $msg }
        }

        $instalador = $sessao.CreateUpdateInstaller()
        $instalador.Updates = $colecao
        $res = $instalador.Install()
        $codigo = [int]$res.ResultCode
        $reinicio = [bool]$res.RebootRequired
        $situacao = switch ($codigo) {
            2 { 'instalado' }
            3 { 'instalado com avisos' }
            4 { 'falhou' }
            5 { 'cancelado' }
            default { "código $codigo" }
        }
        $msg = "Windows Update: '$titulo' -> $situacao$(if ($reinicio) { ' (é preciso reiniciar)' } else { '' })."
        Write-WinForgeLog -Component "Diag" -Level $(if ($codigo -in @(2, 3)) { 'INFO' } else { 'ERROR' }) -Message $msg
        return @{ ResultCode = $codigo; RebootRequired = $reinicio; Text = $msg }
    } catch {
        $msg = "Instalação de '$titulo' pelo Windows Update falhou: $($_.Exception.Message)"
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message $msg
        return @{ ResultCode = $null; RebootRequired = $false; Text = $msg }
    }
}
#endregion
