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
    foreach ($gpu in @($Profile.GPU)) {
        if (-not $gpu -or $gpu.Vendor -ne 'nvidia') { continue }
        $latest = Get-WinForgeNvidiaLatestDriver -GpuName ([string]$gpu.Name) -IsWin11 $isWin11 -IsLaptop $isLaptop
        if ($latest.Status -ne 'ok') {
            $gpu.LatestStatus = $latest.Status
            continue
        }
        $gpu.Latest     = $latest.Version
        $gpu.LatestDate = $latest.ReleaseDate
        $gpu.LatestStatus = 'ok'
        # MarketingVersion é a versão comercial derivada do driver instalado (616.56); comparar como
        # texto diria que '616.8' é maior que '616.64', então a comparação é numérica.
        try {
            if ($gpu.MarketingVersion -and ([version]$gpu.MarketingVersion -lt [version]$latest.Version)) {
                $gpu.LatestStatus = 'atualizar'
                $nvidiaBehind = $true
                $nvidiaLatest = $latest.Version
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
    #>
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found    = $searcher.Search("IsInstalled=0 and Type='Driver'")
        return @(foreach ($u in $found.Updates) {
            $date = ''
            try { if ($u.DriverVerDate) { $date = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch { }
            # A API do Windows Update não expõe a versão do driver em campo próprio (DriverVerDate é
            # data, não versão): o número só existe no fim do título ("... - 32.0.15.6636").
            # Sem esse número no título, Version fica $null - melhor vazio do que uma data disfarçada.
            $version = $null
            if ([string]$u.Title -match '(\d+(?:\.\d+){2,3})\s*$') { $version = $Matches[1] }
            [pscustomobject]@{
                Title    = [string]$u.Title
                Driver   = [string]$u.DriverModel
                Provider = [string]$u.DriverProvider
                Version  = $version
                Date     = $date
                KB       = (@($u.KBArticleIDs) -join ',')
            }
        })
    } catch {
        try { if ($sync) { $sync.LastWUError = $_.Exception.Message } } catch { }
        return @()
    }
}
#endregion
