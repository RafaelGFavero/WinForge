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
# ---------------------------------------------------------------------------

function Test-WinForgeIisAvailable {
    <#
    .SYNOPSIS
        Diz se dá para falar com o IIS nesta máquina (módulo WebAdministration + provedor IIS:\).
    #>
    try {
        Import-Module WebAdministration -ErrorAction Stop
        return [bool](Test-Path 'IIS:\')
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
    .OUTPUTS
        Caminho do arquivo gravado.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Values,
        [string]$Root
    )

    $dir = Get-WinForgeIisSnapshotRoot $Root
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir ("{0}-{1}.json" -f $Name, (Get-Date).ToString('yyyyMMdd-HHmmss'))
    @{ Name = $Name; Date = (Get-Date).ToString('s'); Values = $Values } | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
    Write-WinForgeLog -Component "IIS" -Message "Valores anteriores de $Name guardados em $path ($($Values.Count) item(ns))."
    return $path
}

function Get-WinForgeIisSnapshot {
    <#
    .SYNOPSIS
        Devolve o backup mais recente de um item de IIS, ou $null se não houver nenhum.
    .DESCRIPTION
        O nome do arquivo é '<Item>-<yyyyMMdd-HHmmss>.json': ordenar por nome em ordem decrescente
        coloca o mais novo primeiro sem depender da data do sistema de arquivos (que uma cópia de
        pasta reescreve). Os valores voltam como hashtable, e não como o PSCustomObject do
        ConvertFrom-Json, porque quem restaura precisa iterar chave a chave.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Root
    )

    $dir = Get-WinForgeIisSnapshotRoot $Root
    if (-not (Test-Path $dir)) { return $null }
    $file = Get-ChildItem -Path $dir -Filter "$Name-*.json" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
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
        Algumas propriedades voltam cruas (bool, int), outras dentro de um objeto de configuração
        com .Value. TimeSpan é formatado à mão porque o ToString() padrão vira '1.00:00:00' quando
        passa de um dia, formato que o IIS não aceita de volta.
    #>
    param($Value)

    if ($null -eq $Value) { return '' }
    if ($Value -isnot [string] -and $Value -isnot [bool] -and $Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [System.TimeSpan]) {
        $inner = $Value.PSObject.Properties['Value']
        if ($inner) { $Value = $inner.Value }
    }
    if ($null -eq $Value) { return '' }
    if ($Value -is [System.TimeSpan]) { return ('{0:00}:{1:00}:{2:00}' -f [int][math]::Floor($Value.TotalHours), $Value.Minutes, $Value.Seconds) }
    if ($Value -is [bool]) { if ($Value) { return 'True' } else { return 'False' } }
    return [string]$Value
}

function Get-WinForgeIisValue {
    <#
    .SYNOPSIS
        Lê o valor atual de uma chave de IIS, como texto.
    #>
    param([Parameter(Mandatory)][string]$Key)

    $k = Split-WinForgeIisKey -Key $Key
    switch ($k.Kind) {
        'pool'   { return (ConvertTo-WinForgeIisString (Get-ItemProperty -Path ("IIS:\AppPools\" + $k.Target) -Name $k.Property -ErrorAction Stop)) }
        'site'   { return (ConvertTo-WinForgeIisString (Get-ItemProperty -Path ("IIS:\Sites\" + $k.Target) -Name $k.Property -ErrorAction Stop)) }
        'server' { return (ConvertTo-WinForgeIisString (Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter (Get-WinForgeIisFilter $k.Target) -Name $k.Property -ErrorAction Stop)) }
    }
    throw "Chave de IIS inválida: '$Key' (tipo '$($k.Kind)' desconhecido)."
}

function Set-WinForgeIisValue {
    <#
    .SYNOPSIS
        Escreve um valor numa chave de IIS. O valor vai como texto - é assim que ele sai do backup.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)]$Value
    )

    $k = Split-WinForgeIisKey -Key $Key
    switch ($k.Kind) {
        'pool'   { Set-ItemProperty -Path ("IIS:\AppPools\" + $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
        'site'   { Set-ItemProperty -Path ("IIS:\Sites\" + $k.Target) -Name $k.Property -Value $Value -ErrorAction Stop; return }
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
    #>
    param([int]$PoolCount = 1)

    $totalKb = 0
    try { $totalKb = [int64](((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory) / 1024) } catch { $totalKb = 0 }
    if ($PoolCount -lt 1) { $PoolCount = 1 }
    $limitKb = 1048576
    if ($totalKb -gt 0) { $limitKb = [int64][math]::Floor($totalKb * 0.6 / $PoolCount) }
    if ($limitKb -lt 1048576) { $limitKb = 1048576 }
    if ($limitKb -gt 8388608) { $limitKb = 8388608 }
    return [int64]$limitKb
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
        $pools = @(Get-ChildItem -Path 'IIS:\AppPools' -ErrorAction Stop | ForEach-Object { $_.Name })
        if (-not $pools.Count) { $skipped += "IIS: nenhum pool de aplicativos encontrado." }
    }
    if ($Name -eq 'Preload') {
        $sites = @(Get-ChildItem -Path 'IIS:\Sites' -ErrorAction Stop | ForEach-Object { $_.Name })
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

        # Ler ANTES de escrever qualquer coisa: uma chave que nem existe (propriedade removida numa
        # versão futura do IIS) fica de fora do backup e da escrita, em vez de virar um Desfazer
        # que restaura vazio.
        $previous = @{}
        $unreadable = @()
        foreach ($key in $keys) {
            try { $previous[$key] = Get-WinForgeIisValue -Key $key }
            catch {
                $unreadable += $key
                Write-WinForgeLog -Component "IIS" -Level "WARN" -Message "Não foi possível ler '$key': $($_.Exception.Message)"
            }
        }
        if ($previous.Count -eq 0) {
            $result.Skipped = ("IIS: nenhum valor de '$Name' pôde ser lido; nada foi alterado. " + $result.Skipped).Trim()
            Write-Host $result.Skipped -ForegroundColor Yellow
            return $result
        }
        $result.Snapshot = New-WinForgeIisSnapshot -Name $Name -Values $previous -Root $Root

        foreach ($key in $keys) {
            if (-not $previous.ContainsKey($key)) { continue }
            try {
                Set-WinForgeIisValue -Key $key -Value $plan.Targets[$key]
                $result.Changed++
            } catch {
                Write-WinForgeLog -Component "IIS" -Level "ERROR" -Message "Falha ao ajustar '$key': $($_.Exception.Message)"
                Write-Host "IIS: falha ao ajustar '$key' -> $($_.Exception.Message)" -ForegroundColor Red
            }
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
