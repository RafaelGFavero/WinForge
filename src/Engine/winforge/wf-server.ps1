#region ===== WinForge - servidor (IIS/AD) =====
# Ações dos botões da aba Servidor, a visibilidade das abas que dependem do tipo de Windows e o
# ajuste do IIS (pools, sites e configuração do servidor) com backup dos valores anteriores.
# Os comandos de leitura dos botões (w32tm, Defender, netsh) chegam na tarefa 4; até lá o botão
# avisa que ainda não existe, em vez de falhar calado.

function Invoke-WinForgeServerCommand {
    <#
    .SYNOPSIS
        Executa um comando de leitura da aba Servidor pelo nome curto (placeholder da tarefa 2).
    #>
    param([string]$Name)

    [System.Windows.MessageBox]::Show("Comando '$Name' ainda não implementado.", "WinForge", "OK", "Information") | Out-Null
}

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
