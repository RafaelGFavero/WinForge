#region ===== WinForge - drivers (consulta online) =====
# Descobre a versão mais recente do driver NVIDIA, monta o link de download de cada fabricante e
# pergunta ao Windows Update se há driver novo para este computador.
# Tudo aqui é opcional e tolerante a falha: sem internet, o perfil continua válido - cada função
# devolve 'indisponível', array vazio ou $null, nunca uma exceção que escape para quem chamou.

function Get-WinForgeCacheItem {
    <#
    .SYNOPSIS
        Lê um JSON do cache local (%LocalAppData%\WinForge\cache) se ele ainda estiver dentro da validade.
    .DESCRIPTION
        Devolve $null quando o arquivo não existe, está velho ou não pôde ser lido - o chamador
        simplesmente consulta a rede de novo.
    #>
    param([Parameter(Mandatory)][string]$Name, [int]$MaxAgeHours = 24)
    try {
        $file = Join-Path (Join-Path $env:LOCALAPPDATA 'WinForge\cache') $Name
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
    param([Parameter(Mandatory)][string]$Name, $Value)
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'WinForge\cache'
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

function Get-WinForgeNvidiaLookupValues {
    <#
    .SYNOPSIS
        Lista séries (TypeID 2, ParentID 1) ou produtos de uma série (TypeID 3, ParentID <psid>)
        do catálogo da NVIDIA, em cache de 24 h.
    .DESCRIPTION
        Devolve array de objetos com Name e Value (o psid/pfid). Erro de rede sobe para o chamador,
        que traduz em status 'indisponível'.
    #>
    param([Parameter(Mandatory)][int]$TypeId, [Parameter(Mandatory)][int]$ParentId, [int]$TimeoutSec = 5)
    $cacheName = "nvidia-lookup-$TypeId-$ParentId.json"
    $cached = Get-WinForgeCacheItem -Name $cacheName
    if ($cached) { return @($cached) }
    $uri = "https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=$TypeId&ParentID=$ParentId"
    $xml = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec $TimeoutSec
    $values = @($xml.LookupValueSearch.LookupValues.LookupValue | Where-Object { $_.Name } | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.Name; Value = [string]$_.Value }
    })
    if ($values.Count) { Set-WinForgeCacheItem -Name $cacheName -Value $values }
    return $values
}

function Get-WinForgeNvidiaLatestDriver {
    <#
    .SYNOPSIS
        Versão mais recente do driver NVIDIA para uma placa, direto do catálogo do fabricante.
    .DESCRIPTION
        Três passos: acha a família da placa na lista de séries, acha o produto exato dentro dela e
        pergunta o driver mais novo (WHQL/DCH) para o Windows instalado. O resultado fica 24 h em
        %LocalAppData%\WinForge\cache\nvidia-<psid>-<pfid>-<osID>.json.
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
    #>
    param(
        [Parameter(Mandatory)][string]$GpuName,
        [bool]$IsWin11 = $true,
        [bool]$IsLaptop = $false,
        [int]$TimeoutSec = 5
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

        $series = @(Get-WinForgeNvidiaLookupValues -TypeId 2 -ParentId 1 -TimeoutSec $TimeoutSec)
        $candidates = @($series | Where-Object { (Get-WinForgeNvidiaSeriesNameToken $_.Name) -eq $token })
        if (-not $candidates.Count) { $result.Status = 'não encontrado'; return $result }
        $pick = @($candidates | Where-Object { ($_.Name -match '(?i)\(Notebooks?\)') -eq $IsLaptop }) | Select-Object -First 1
        if (-not $pick) { $pick = $candidates[0] }
        $psid = [int]$pick.Value

        $products = @(Get-WinForgeNvidiaLookupValues -TypeId 3 -ParentId $psid -TimeoutSec $TimeoutSec)
        $product = @($products | Where-Object { (ConvertTo-WinForgeNvidiaModelName $_.Name) -eq $model }) | Select-Object -First 1
        if (-not $product) { $result.Status = 'não encontrado'; return $result }
        $pfid = [int]$product.Value

        $cacheName = "nvidia-$psid-$pfid-$osId.json"
        $info = Get-WinForgeCacheItem -Name $cacheName
        if (-not $info) {
            # Parâmetros extras (beta/upCRD/qnf/ctk/dltype) fazem esta consulta responder
            # DriverDownloadIDNotFound: só os abaixo.
            $uri = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=$psid&pfid=$pfid&osID=$osId&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1"
            $response = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec $TimeoutSec
            $info = @($response.IDS)[0].downloadInfo
            # 'Success' vem "1" quando achou e "0" quando não; o que decide mesmo é ter versão.
            if (-not $info -or -not $info.Version) { $result.Status = 'não encontrado'; return $result }
            Set-WinForgeCacheItem -Name $cacheName -Value $info
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
            # A API do Windows Update não expõe a versão do driver em campo próprio (DriverVerDate é
            # data, não versão): o número só existe no fim do título ("... - 32.0.15.6636").
            # Sem esse número no título, Version fica $null - melhor vazio do que uma data disfarçada.
            $version = $null
            if ([string]$u.Title -match '(\d+(?:\.\d+){2,3})\s*$') { $version = $Matches[1] }
            $updateId = ''
            try { $updateId = [string]$u.Identity.UpdateID } catch { $updateId = '' }
            if ($updateId) { try { if ($sync -and $sync.DiagWUUpdates) { $sync.DiagWUUpdates[$updateId] = $u } } catch { } }
            [pscustomobject]@{
                Title    = [string]$u.Title
                Driver   = [string]$u.DriverModel
                Provider = [string]$u.DriverProvider
                Version  = $version
                Date     = $date
                KB       = (@($u.KBArticleIDs) -join ',')
                UpdateId = $updateId
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

function Get-WinForgeDownloadRoot {
    <#
    .SYNOPSIS
        Pasta dos arquivos baixados (%ProgramData%\WinForge\downloads). -Root existe para o teste
        não escrever em %ProgramData%.
    .DESCRIPTION
        Só monta o caminho, normalizado uma vez ([System.IO.Path]::GetFullPath) como a pasta de
        backup: daqui para baixo todo mundo conta com a mesma forma. Quem cria e quem confere é
        Confirm-WinForgeDownloadRoot.
    #>
    param([string]$Root)

    $alvo = if ($Root) { $Root } else { (Join-Path $env:ProgramData 'WinForge\downloads') }
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

        Quem instala é o usuário: o instalador da NVIDIA é interativo (licença, tipo de instalação,
        reinício), e fingir que o WinForge conduz isso seria mentira. O WinForge abre a janela dele.
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
        # existe em instalação limpa. 600 s porque o instalador passa de 700 MB.
        # -MaximumRedirection 0: os links do catálogo da NVIDIA são diretos. Seguir um
        # redirecionamento é aceitar um host que Test-WinForgeNvidiaDownloadUrl nunca viu.
        Invoke-WebRequest -Uri $Url -OutFile $parcial -UseBasicParsing -TimeoutSec 600 -MaximumRedirection 0 -ErrorAction Stop
        Move-Item -LiteralPath $parcial -Destination $destino -Force -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $parcial -Force -ErrorAction SilentlyContinue
        $causa = [string]$_.Exception.Message
        $codigo = $null
        try { $codigo = [int]$_.Exception.Response.StatusCode } catch { $codigo = $null }
        # 'redirec' pega tanto "redirection" quanto "redirecionamento": a mensagem do
        # Invoke-WebRequest vem no idioma do Windows.
        if ($causa -match 'redirec' -or ($codigo -ge 300 -and $codigo -lt 400)) {
            $causa = "o servidor respondeu com um redirecionamento e os endereços da NVIDIA são diretos ($causa)"
        }
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
