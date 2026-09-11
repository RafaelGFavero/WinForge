#region ===== WinForge - funções adicionais =====
# Todas as funções levam "WinUtilBoost" no nome para serem importadas automaticamente
# nos runspaces (Initialize-WinUtilRunspacePool importa tudo que casa com 'winutil|WPF').

function Get-WinForgeWindowsProductType {
    <#
    .SYNOPSIS
        Diz se este Windows é cliente ou servidor, lendo o registro; o CIM só entra se o registro falhar.
    .DESCRIPTION
        HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions\ProductType responde em 12 ms aqui,
        contra 100-190 ms de um Get-CimInstance Win32_OperatingSystem quente (e muito mais com o
        winmgmt frio). Mais importante: num servidor com o repositório WMI corrompido a chamada CIM
        lança, $sync.IsServer ficava $false e a aba Servidor inteira sumia sem uma palavra.

        'WinNT' = cliente; 'ServerNT' (servidor membro) e 'LanmanNT' (controlador de domínio) =
        servidor. Falhando os dois caminhos, a resposta é 'cliente' com um WARN no log: esconder a
        aba Servidor num servidor é chato, mostrar itens de servidor num cliente é pior.
    .OUTPUTS
        @{ IsServer = <bool>; Source = 'registry'|'cim'|'nenhum'; ProductType = <texto ou $null> }.
    #>
    try {
        $pt = [string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name 'ProductType' -ErrorAction Stop).ProductType
        if (-not [string]::IsNullOrWhiteSpace($pt)) {
            return @{ IsServer = ($pt -ne 'WinNT'); Source = 'registry'; ProductType = $pt }
        }
    } catch { }
    try {
        $osTipo = [int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).ProductType
        return @{ IsServer = ($osTipo -ne 1); Source = 'cim'; ProductType = [string]$osTipo }
    } catch { }
    try { Write-WinForgeLog -Component "Server" -Level "WARN" -Message "Tipo de produto do Windows não pôde ser lido (nem pelo registro nem pelo CIM): assumindo cliente." } catch { }
    return @{ IsServer = $false; Source = 'nenhum'; ProductType = $null }
}

function Test-WinForgeRealServer {
    <#
    .SYNOPSIS
        $true só num Windows Server de verdade - WINFORGE_SIMULATE_SERVER não conta.
    .DESCRIPTION
        A simulação existe para montar a aba e exercitar as regras num cliente. O que ela NÃO pode
        fazer é liberar a escrita em SMB, plano de energia, TCP ou RDP da máquina de quem está
        testando: por isso quem mexe de verdade pergunta aqui, e não a $sync.IsServer.
    #>
    return [bool](Get-WinForgeWindowsProductType).IsServer
}

function Get-WinUtilBoostSystemInfo {
    <#
    .SYNOPSIS
        Detecta a versão do Windows (10/11/Server), os papéis de servidor instalados e os
        fabricantes de GPU presentes. Usado para ocultar recursos que não se aplicam ao
        sistema atual. Roda antes da janela abrir, então tudo aqui tem de ser barato.
    #>
    $build = [System.Environment]::OSVersion.Version.Build
    if ($env:WINFORGE_SIMULATE_BUILD) { $build = [int]$env:WINFORGE_SIMULATE_BUILD }   # só para testes (ex.: 19045 = Windows 10 22H2)
    $sync.OSBuild = $build
    $sync.IsWin11 = ($build -ge 22000)
    $sync.OSName = if ($sync.IsWin11) { "Windows 11" } else { "Windows 10" }
    try {
        $sync.OSDisplayVersion = [string](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).DisplayVersion
    } catch {
        $sync.OSDisplayVersion = ""
    }

    # ---- Servidor e papéis (barato: ProductType + presença de serviços; o perfil completo vem depois)
    $sync.IsServer = $false; $sync.ServerRoles = @(); $sync.IsDC = $false
    if ($null -ne $env:WINFORGE_SIMULATE_SERVER) {
        # só para testes: "iis,ad" simula um servidor com esses papéis; "none" simula servidor sem
        # papel nenhum. String vazia não serve como sentinela: no Windows, $env:X = '' APAGA a
        # variável, então "servidor sem papel" era um estado inalcançável.
        $sync.IsServer = $true
        $sync.ServerRoles = @($env:WINFORGE_SIMULATE_SERVER -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -and $_ -ne 'none' })
        $sync.IsDC = ('ad' -in $sync.ServerRoles)
    } else {
        $sync.IsServer = [bool](Get-WinForgeWindowsProductType).IsServer
        if ($sync.IsServer) {
            $roles = [System.Collections.Generic.List[string]]::new()
            $wfSvc = @{}
            foreach ($s in (Get-Service -ErrorAction SilentlyContinue)) { $wfSvc[$s.Name] = $true }
            if ($wfSvc['W3SVC'])  { $roles.Add('iis') }
            if ($wfSvc['NTDS'])   { $roles.Add('ad') }
            if ($wfSvc['vmms'])   { $roles.Add('hyperv') }
            if ($wfSvc['DNS'])    { $roles.Add('dns') }
            if ($wfSvc['DHCPServer']) { $roles.Add('dhcp') }
            $sync.ServerRoles = @($roles)
            try { $sync.IsDC = ([int](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).DomainRole -ge 4) } catch { }
            if ($sync.IsDC -and 'ad' -notin $sync.ServerRoles) { $sync.ServerRoles += 'ad' }
        }
    }
    if ($sync.IsServer) { $sync.OSName = "Windows Server" }

    $vendors = [System.Collections.Generic.List[string]]::new()
    $names = [System.Collections.Generic.List[string]]::new()
    try {
        Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
            $n = [string]$_.Name
            if ([string]::IsNullOrWhiteSpace($n)) { return }
            $names.Add($n)
            if ($n -match 'NVIDIA|GeForce|Quadro') { if (-not $vendors.Contains('nvidia')) { $vendors.Add('nvidia') } }
            if ($n -match 'AMD|Radeon|ATI ')      { if (-not $vendors.Contains('amd'))    { $vendors.Add('amd') } }
            if ($n -match 'Intel')                { if (-not $vendors.Contains('intel'))  { $vendors.Add('intel') } }
        }
    } catch {
        Write-Warning "Não foi possível detectar a GPU: $($_.Exception.Message)"
    }
    $sync.GPUVendors = $vendors
    $sync.GPUNames = $names
}

function Test-WinUtilBoostEntryCompatible {
    <#
    .SYNOPSIS
        Retorna $true se a entrada (tweak/feature/appx) se aplica ao sistema atual.
        Campos opcionais na entrada:
          "os"       : "win11" ou "win10"  -> só aparece nessa versão
          "gpu"      : "nvidia" | "amd" | "intel" (ou lista) -> só aparece se a GPU foi detectada
          "platform" : "server" -> só no Windows Server; "client" -> só no Windows 10/11
          "role"     : "iis" | "ad" | "hyperv" | "dns" | "dhcp" (ou lista) -> só aparece se
                       QUALQUER um dos papéis listados estiver presente no servidor

        ATENÇÃO ao "os": ele é decidido por BUILD (>= 22000 = win11), não por família. O Server
        2022 é build 20348 e conta como "win10"; o Server 2025 é build 26100 e conta como "win11".
        Entrada nova de servidor deve usar "platform"/"role" - "os" ali separa geração de kernel,
        não cliente de servidor.
    #>
    param($Entry)

    if ($null -eq $Entry) { return $true }

    $os = $null
    $gpu = $null
    if ($Entry.PSObject.Properties['os'])  { $os = [string]$Entry.os }
    if ($Entry.PSObject.Properties['gpu']) { $gpu = $Entry.gpu }

    if (-not [string]::IsNullOrWhiteSpace($os)) {
        switch ($os.ToLower()) {
            'win11' { if (-not $sync.IsWin11) { return $false } }
            'win10' { if ($sync.IsWin11) { return $false } }
        }
    }

    $platform = $null; $role = $null
    if ($Entry.PSObject.Properties['platform']) { $platform = ([string]$Entry.platform).ToLower() }
    if ($Entry.PSObject.Properties['role'])     { $role = $Entry.role }
    if ($platform -eq 'server' -and -not $sync.IsServer) { return $false }
    if ($platform -eq 'client' -and $sync.IsServer)      { return $false }
    if ($role) {
        $wanted = @($role | ForEach-Object { ([string]$_).ToLower() })
        $have = @($sync.ServerRoles)
        $ok = $false
        foreach ($w in $wanted) { if ($have -contains $w) { $ok = $true } }
        if (-not $ok) { return $false }
    }

    if ($gpu) {
        $wanted = @($gpu | ForEach-Object { ([string]$_).ToLower() })
        $have = @($sync.GPUVendors)
        if ($have.Count -eq 0) { return $true }   # sem detecção: mostra tudo
        $ok = $false
        foreach ($w in $wanted) { if ($have -contains $w) { $ok = $true } }
        if (-not $ok) { return $false }
    }

    return $true
}

function Get-WinUtilBoostConfigSubset {
    <#
    .SYNOPSIS
        Retorna um PSCustomObject só com as entradas cuja propriedade 'tab' está em -Tab
        (ou fora dela, quando -Exclude). Usado para separar as abas "Jogos" e "Servidor"
        da aba "Tweaks".
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [string[]]$Tab,
        [switch]$Exclude
    )
    $out = [PSCustomObject]@{}
    foreach ($p in $Config.PSObject.Properties) {
        $entryTab = ""
        if ($p.Value -and $p.Value.PSObject.Properties['tab']) { $entryTab = [string]$p.Value.tab }
        $match = ($entryTab -in $Tab)
        if ($Exclude) { $match = -not $match }
        if ($match) { $out | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
    return $out
}

function Initialize-WinUtilBoostConfigs {
    <#
    .SYNOPSIS
        Mescla as configurações do WinForge nas da base:
          - marca entradas do WinUtil que só existem no Windows 11
          - adiciona os tweaks, botões, presets e a lista de jogos (IFEO) do WinForge
    #>

    foreach ($k in $sync.WinForgeWin11OnlyTweaks) {
        if ($sync.configs.tweaks.PSObject.Properties[$k]) {
            $sync.configs.tweaks.$k | Add-Member -NotePropertyName os -NotePropertyValue "win11" -Force
        }
    }
    foreach ($k in $sync.WinForgeWin11OnlyAppx) {
        if ($sync.configs.appx.PSObject.Properties[$k]) {
            $sync.configs.appx.$k | Add-Member -NotePropertyName os -NotePropertyValue "win11" -Force
        }
    }

    foreach ($p in $sync.configs.wbtweaks.PSObject.Properties) {
        $sync.configs.tweaks | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
    }

    # aba Servidor: mesma config de tweaks, separada só pela propriedade 'tab' (e escondida no
    # cliente pelo 'platform'). Entra depois de wbtweaks para que a auditoria veja todas as chaves.
    foreach ($p in $sync.configs.wfserver.PSObject.Properties) {
        $sync.configs.tweaks | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
    }

    foreach ($g in $sync.configs.wbgames) {
        $regs = @()
        foreach ($exe in $g.Exes) {
            $regs += [PSCustomObject]@{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exe\PerfOptions"
                Name          = "CpuPriorityClass"
                Value         = "3"
                Type          = "DWord"
                OriginalValue = "<RemoveEntry>"
            }
        }
        $entry = [PSCustomObject]@{
            Content     = $g.Name
            Description = "Prioridade de CPU ALTA para: $($g.Exes -join ', ') (IFEO\PerfOptions CpuPriorityClass=3). O Windows passa a iniciar o processo com prioridade Alta. Marque + 'Desfazer selecionados' para remover."
            category    = "Prioridade de CPU por jogo (IFEO)"
            panel       = "1"
            tab         = "Jogos"
            registry    = $regs
        }
        $sync.configs.tweaks | Add-Member -NotePropertyName "WPFTweaksWBGame$($g.Key)" -NotePropertyValue $entry -Force
    }

    foreach ($p in $sync.configs.wbfeatures.PSObject.Properties) {
        $sync.configs.feature | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
    }

    # Reparo de componentes: mesma aba Config, grupo próprio. Entra depois de wbfeatures porque é a
    # ordem em que os grupos aparecem na tela.
    foreach ($p in $sync.configs.wfrepair.PSObject.Properties) {
        $sync.configs.feature | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
    }

    foreach ($p in $sync.configs.wbpresets.PSObject.Properties) {
        $sync.configs.preset | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
    }

    # Aba Instalar: tira da lista os aplicativos que não entram no WinForge (wf-apps.ps1) e traduz
    # os títulos dos grupos. Tem de acontecer aqui, antes de o motor derivar applicationsHashtable
    # e montar a aba - depois disso a chave removida já seria um controle na tela.
    $wfRemovidos = 0
    foreach ($k in $sync.WinForgeRemovedApps) {
        if ($sync.configs.applications.PSObject.Properties[$k]) {
            $sync.configs.applications.PSObject.Properties.Remove($k)
            $wfRemovidos++
        }
    }
    foreach ($p in $sync.configs.applications.PSObject.Properties) {
        $cat = [string]$p.Value.Category
        if ($sync.WinForgeAppCategoryMap.ContainsKey($cat)) { $p.Value.Category = $sync.WinForgeAppCategoryMap[$cat] }
    }
    foreach ($o in $sync.WinForgeAppCategoryOverride.GetEnumerator()) {
        $app = $sync.configs.applications.PSObject.Properties[$o.Key]
        if ($app) { $app.Value.Category = $o.Value }
    }
    Write-WinUtilLog -Component "Boost" -Message "Aba Instalar: $wfRemovidos aplicativo(s) removido(s), $(@($sync.configs.applications.PSObject.Properties).Count) na lista."

    # Correções da aba Config: as cinco entradas abaixo vieram da base apontando para funções que
    # rodavam NA THREAD DA JANELA e escreviam num console que o lançador esconde - a aba congelava e
    # nada aparecia. Agora quem as despacha é o switch de Invoke-WPFButton, com o nome curto do
    # comando e a máquina de saída ao vivo. A chave 'function' sai daqui porque ela é o caminho que
    # levava de volta ao comportamento antigo: sem ela, uma guarda de lookup quebrada cai no switch
    # em vez de congelar a janela de novo.
    foreach ($k in @('WPFFixesNetwork', 'WPFFixesNTPPool', 'WPFPanelDISM', 'WPFFixesUpdate', 'WPFFixesWinget')) {
        $entradaCorrecao = $sync.configs.feature.PSObject.Properties[$k]
        if ($entradaCorrecao -and $entradaCorrecao.Value.PSObject.Properties['function']) {
            $entradaCorrecao.Value.PSObject.Properties.Remove('function')
        }
    }

    # Tradução por chave do texto que veio do arquivo base (config\wf-i18n-configs.ps1).
    # Roda DEPOIS das mesclas - assim vê as chaves da base e as do WinForge de uma vez - e ANTES de
    # Initialize-WinForgeAudit, que prefixa "CUIDADO: ..." na descrição dos itens de risco: se a
    # tradução viesse depois, ela sobrescreveria a descrição já prefixada e o aviso sumiria.
    # A busca da propriedade é pelo nome que existe na entrada, não por um nome fixo: o bloco de
    # aplicativos usa 'description' em minúsculo (e o nome do produto em 'content', que não se
    # traduz), enquanto tweaks e recursos usam 'Content'/'Description'.
    $wfTraduzidos = 0
    foreach ($cfg in @($sync.configs.tweaks, $sync.configs.feature, $sync.configs.applications)) {
        foreach ($p in $cfg.PSObject.Properties) {
            $t = $sync.WinForgeI18n[$p.Name]
            if (-not $t) { continue }
            foreach ($campo in @('Content', 'Description')) {
                if (-not $t.ContainsKey($campo)) { continue }
                $prop = $p.Value.PSObject.Properties[$campo]
                if ($prop) {
                    $prop.Value = $t[$campo]
                } else {
                    # Campo que a base não tem. Quatro dos cinco botões de "Correções" chegam SEM
                    # Description nenhuma, e é dela que sai a dica do botão e o texto da caixa de
                    # confirmação: enquanto isto era um 'continue', a descrição escrita no dicionário
                    # era simplesmente ignorada, em silêncio.
                    $p.Value | Add-Member -NotePropertyName $campo -NotePropertyValue $t[$campo] -Force
                }
                $wfTraduzidos++
            }
        }
    }
    Write-WinUtilLog -Component "Boost" -Message "Tradução por chave: $wfTraduzidos texto(s) traduzido(s) em $(@($sync.WinForgeI18n.Keys).Count) entrada(s)."
}

function Set-WinForgeInstallCollapsed {
    <#
    .SYNOPSIS
        Fecha todos os grupos da aba Instalar assim que ela é montada.
    .DESCRIPTION
        Chamada por Initialize-WinUtilTabContent no caso "Install". A base já sabe fechar tudo
        (é o botão "Collapse All Categories"), então aqui só se aciona a mesma função - com
        try/catch porque isto roda dentro da montagem da aba e uma exceção deixaria a aba pela
        metade.

        O filtro de busca vazio (Find-AppsByNameOrDescription) respeita o "+" no título do grupo,
        então trocar de aba e voltar não reabre nada.
    #>
    try {
        Invoke-WPFToggleAllCategories -Action "Collapse"
        Write-WinUtilLog -Component "Boost" -Message "Aba Instalar: grupos fechados na montagem."
    } catch {
        Write-WinUtilLog -Component "Boost" -Message "Aba Instalar: falha ao fechar os grupos: $($_.Exception.Message)"
    }
}

function Get-WinForgeNavOrder {
    <#
    .SYNOPSIS
        Nomes dos botões da barra de navegação, na ordem em que aparecem na tela.
    .PARAMETER Window
        A janela já carregada do XAML.
    .OUTPUTS
        String[] com os nomes (WPFTab8BT, WPFTab2BT, ...). Vazio se o painel não existir.
    #>
    param(
        [Parameter(Mandatory = $true)]$Window
    )
    $panel = $Window.FindName('NavDockPanel')
    if ($null -eq $panel) { return @() }
    return @($panel.Children | Where-Object { $_ -is [System.Windows.Controls.Primitives.ToggleButton] } | ForEach-Object { $_.Name })
}

function Invoke-WinUtilBoostRestorePointPrompt {
    <#
    .SYNOPSIS
        Pergunta (uma vez, ao abrir) se o usuário quer criar um ponto de restauração.
        -RestorePoint   : cria sem perguntar
        -NoRestorePoint : não pergunta nem cria
    #>
    if ($sync.NoRestorePointPrompt) {
        Write-WinUtilLog -Component "Boost" -Message "Pergunta de ponto de restauração ignorada (-NoRestorePoint)."
        return
    }

    $create = $false
    if ($sync.ForceRestorePoint) {
        $create = $true
    } else {
        $msg = "Deseja criar um Ponto de Restauração do Sistema antes de começar?`n`n" +
               "Recomendado: permite voltar o Windows ao estado atual caso alguma otimização cause problema.`n`n" +
               "Sim  = criar agora (leva de 30 segundos a alguns minutos; a janela pode ficar sem resposta nesse tempo)`n" +
               "Não  = continuar sem criar. Você ainda pode criar depois em:`n" +
               "         Configurações > WinForge - Manutenção > 'Ponto de restauração - Criar agora'`n" +
               "         ou marcando '$($sync.configs.tweaks.WPFTweaksRestorePoint.Content)' na aba Ajustes."
        $result = [System.Windows.MessageBox]::Show($sync.Form, $msg, "WinForge - Ponto de Restauração",
            [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        $create = ($result -eq [System.Windows.MessageBoxResult]::Yes)
    }

    if ($create) {
        Invoke-WinUtilBoostCreateRestorePoint
    } else {
        Write-WinUtilLog -Component "Boost" -Message "Usuário optou por não criar ponto de restauração no início."
    }
}

function Invoke-WinUtilBoostCreateRestorePoint {
    <#
    .SYNOPSIS
        Cria um ponto de restauração agora (síncrono, como o WinUtil faz no botão Run Tweaks).
    #>
    if ($sync.ProcessRunning) {
        [System.Windows.MessageBox]::Show("Aguarde o processo atual terminar.", "WinForge", "OK", "Warning") | Out-Null
        return
    }
    $sync.ProcessRunning = $true
    try {
        Set-WinUtilTaskbaritem -state "Indeterminate" -overlay "logo"
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Criando ponto de restauração do sistema... a janela pode ficar sem resposta por até alguns minutos." -Percent 0
        if ($sync.Form -and $sync.Form.Dispatcher) {
            # força a barra de progresso a ser desenhada antes do trabalho síncrono
            $sync.Form.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) | Out-Null
        }
        Write-WinUtilLog -Component "Boost" -Message "Criando ponto de restauração."

        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -Force -ErrorAction Stop
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WinForge $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop

        $sync.RestorePointCreated = $true
        Write-WinUtilLog -Component "Boost" -Message "Ponto de restauração criado com sucesso."
        Write-Host "Ponto de restauração criado com sucesso." -ForegroundColor Green
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Ponto de restauração criado com sucesso." -Percent 100
        Set-WinUtilTaskbaritem -state "None" -overlay "checkmark"
    } catch {
        $err = $_.Exception.Message
        Write-Warning "Falha ao criar ponto de restauração: $err"
        Write-WinUtilLog -Level "ERROR" -Component "Boost" -Message "Falha ao criar ponto de restauração: $err"
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Falha ao criar ponto de restauração: $err" -Percent 100
        Set-WinUtilTaskbaritem -state "Error" -overlay "warning"
        [System.Windows.MessageBox]::Show("Não foi possível criar o ponto de restauração:`n$err`n`nVerifique se a Proteção do Sistema está ativada (Win+R > sysdm.cpl > aba Proteção do Sistema).", "WinForge", "OK", "Warning") | Out-Null
    } finally {
        $sync.ProcessRunning = $false
    }
}

function Start-WinUtilBoostJob {
    <#
    .SYNOPSIS
        Executa um bloco de trabalho em runspace com indicador de progresso e ícone na barra de tarefas.
        O bloco deve retornar uma string de resumo (opcional).
    #>
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Work
    )
    if ($sync.ProcessRunning) {
        [System.Windows.MessageBox]::Show("Aguarde o processo atual terminar.", "WinForge", "OK", "Warning") | Out-Null
        return
    }
    $sync.ProcessRunning = $true
    Set-WinUtilTaskbaritem -state "Indeterminate" -overlay "logo"
    Set-WinUtilTweaksProgressIndicator -Visible $true -Label "$Label..." -Percent 0
    Write-WinUtilLog -Component "Boost" -Message "Iniciando: $Label"

    Invoke-WPFRunspace -ParameterList @(("work", $Work.ToString()), ("label", $Label)) -ScriptBlock {
        param($work, $label)
        try {
            $summary = & ([scriptblock]::Create($work))
            $summaryText = ($summary | Where-Object { $_ -is [string] } | Select-Object -Last 1)
            Write-WinUtilLog -Component "Boost" -Message "Concluído: $label. $summaryText"
            Write-Host "$label - concluído. $summaryText" -ForegroundColor Green
            Set-WinUtilTweaksProgressIndicator -Visible $true -Label "$label - concluído. $summaryText" -Percent 100
            Invoke-WPFUIThread -ScriptBlock { Set-WinUtilTaskbaritem -state "None" -overlay "checkmark" }
        } catch {
            $err = $_.Exception.Message
            Write-Warning "$label falhou: $err"
            Write-WinUtilLog -Level "ERROR" -Component "Boost" -Message "$label falhou: $err"
            Set-WinUtilTweaksProgressIndicator -Visible $true -Label "$label - erro: $err" -Percent 100
            Invoke-WPFUIThread -ScriptBlock { Set-WinUtilTaskbaritem -state "Error" -overlay "warning" }
        } finally {
            $sync.ProcessRunning = $false
        }
    } | Out-Null
}

function Invoke-WinUtilBoostRegistryBackup {
    <#
    .SYNOPSIS
        Exporta as chaves HKLM, HKCU, HKCR, HKU e HKCC para arquivos .reg (igual ao 'Fazer backup do Windows.bat').
    #>
    Start-WinUtilBoostJob -Label "Backup do Registro" -Work {
        $folder = Join-Path $sync.winutildir ("Backup_Regedit\" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $hives = @('HKLM', 'HKCU', 'HKCR', 'HKU', 'HKCC')
        $i = 0
        foreach ($h in $hives) {
            $i++
            Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Backup do Registro: exportando $h ($i de $($hives.Count))... isso pode demorar alguns minutos" -Percent ([int](($i - 1) / $hives.Count * 100))
            $out = Join-Path $folder "$h.reg"
            Write-Host "reg export $h -> $out"
            & reg.exe export $h "$out" /y | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warning "reg export $h retornou código $LASTEXITCODE" }
        }
        $size = (Get-ChildItem -Path $folder -File | Measure-Object -Property Length -Sum).Sum
        Start-Process explorer.exe -ArgumentList "`"$folder`""
        "Salvo em $folder ($([math]::Round($size / 1MB)) MB)."
    }
}

function Invoke-WinUtilBoostClearStandbyList {
    <#
    .SYNOPSIS
        Limpa a Standby List e a Modified List da memória (mesmo efeito do EmptyStandbyList.exe / ISLC),
        sem depender de executável externo. Usa NtSetSystemInformation(SystemMemoryListInformation).
    #>
    $csharp = @"
using System;
using System.Runtime.InteropServices;
public static class WinUtilBoostMemory {
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] public struct TOKEN_PRIVILEGES { public int PrivilegeCount; public LUID Luid; public int Attributes; }
    [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool LookupPrivilegeValue(string system, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES newState, int bufferLength, IntPtr previousState, IntPtr returnLength);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const int SystemMemoryListInformation = 80;
    static void EnablePrivilege(string name) {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0028, out token)) throw new System.ComponentModel.Win32Exception();
        try {
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Attributes = 0x00000002;
            if (!LookupPrivilegeValue(null, name, out tp.Luid)) throw new System.ComponentModel.Win32Exception();
            if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) throw new System.ComponentModel.Win32Exception();
            int err = Marshal.GetLastWin32Error();
            if (err != 0) throw new System.ComponentModel.Win32Exception(err);
        } finally { CloseHandle(token); }
    }
    // 2 = MemoryEmptyWorkingSets, 3 = MemoryFlushModifiedList, 4 = MemoryPurgeStandbyList, 5 = MemoryPurgeLowPriorityStandbyList
    public static int Run(int command) {
        EnablePrivilege("SeProfileSingleProcessPrivilege");
        EnablePrivilege("SeIncreaseQuotaPrivilege");
        int cmd = command;
        return NtSetSystemInformation(SystemMemoryListInformation, ref cmd, 4);
    }
}
"@
    try {
        if (-not ("WinUtilBoostMemory" -as [type])) {
            Add-Type -TypeDefinition $csharp -ErrorAction Stop
        }
        $os = Get-CimInstance Win32_OperatingSystem
        $before = [double]$os.FreePhysicalMemory
        $total = [double]$os.TotalVisibleMemorySize

        $r = [WinUtilBoostMemory]::Run(3)   # Modified List
        if ($r -ne 0) { throw ("NtSetSystemInformation(FlushModifiedList) retornou 0x{0:X8}" -f $r) }
        $r = [WinUtilBoostMemory]::Run(4)   # Standby List
        if ($r -ne 0) { throw ("NtSetSystemInformation(PurgeStandbyList) retornou 0x{0:X8}" -f $r) }

        Start-Sleep -Milliseconds 700
        $after = [double](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
        $freedMB = [math]::Round(($after - $before) / 1024)
        if ($freedMB -lt 0) { $freedMB = 0 }
        $msg = "Standby List e Modified List limpas.`n`nMemória livre antes: $([math]::Round($before/1024)) MB`nMemória livre agora: $([math]::Round($after/1024)) MB (de $([math]::Round($total/1024)) MB)`nLiberado: ~$freedMB MB"
        Write-Host $msg -ForegroundColor Green
        Write-WinUtilLog -Component "Boost" -Message ("Cache de RAM limpo: ~{0} MB liberados." -f $freedMB)
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Cache de RAM limpo: ~$freedMB MB liberados (livre agora: $([math]::Round($after/1024)) MB)." -Percent 100
        [System.Windows.MessageBox]::Show($msg, "WinForge - Limpar cache de RAM", "OK", "Information") | Out-Null
    } catch {
        $err = $_.Exception.Message
        Write-Warning "Falha ao limpar cache de RAM: $err"
        Write-WinUtilLog -Level "ERROR" -Component "Boost" -Message "Falha ao limpar cache de RAM: $err"
        [System.Windows.MessageBox]::Show("Falha ao limpar cache de RAM:`n$err", "WinForge", "OK", "Warning") | Out-Null
    }
}

function Invoke-WinUtilBoostOptimizeVolumes {
    <#
    .SYNOPSIS
        Otimiza todas as unidades fixas: TRIM em SSD, desfragmentação em HDD (Optimize-Volume escolhe pelo tipo de mídia).
        Substitui os atalhos 'HDD.exe' e 'LIMPAR SSD.exe' do repositório original.
    #>
    Start-WinUtilBoostJob -Label "Otimização de unidades" -Work {
        $vols = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -match 'NTFS|ReFS' } | Sort-Object DriveLetter)
        if ($vols.Count -eq 0) { throw "Nenhuma unidade fixa NTFS/ReFS encontrada." }
        $i = 0
        foreach ($v in $vols) {
            $i++
            Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Otimizando unidade $($v.DriveLetter): ($i de $($vols.Count))... (TRIM em SSD / desfragmentação em HDD)" -Percent ([int](($i - 1) / $vols.Count * 100))
            Write-Host "== Optimize-Volume $($v.DriveLetter): =="
            Optimize-Volume -DriveLetter $v.DriveLetter -Verbose -ErrorAction Continue 4>&1 | ForEach-Object { Write-Host "  $_" }
        }
        "$($vols.Count) unidade(s) otimizada(s): $(($vols | ForEach-Object { "$($_.DriveLetter):" }) -join ' ')"
    }
}

function Invoke-WinUtilBoostFullCleanup {
    <#
    .SYNOPSIS
        Limpeza completa (versão revisada do 'Limpeza Completa PC.bat'):
        Temp do usuário e do Windows, itens recentes, cache do Windows Update, DNS, WER, cache de shaders DirectX e Lixeira.
    #>
    Start-WinUtilBoostJob -Label "Limpeza completa" -Work {
        $script:freed = [long]0

        function Remove-WinUtilBoostContents([string]$path, [bool]$recurse = $true) {
            if (-not (Test-Path -LiteralPath $path)) { return }
            $items = if ($recurse) { Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue } else { Get-ChildItem -LiteralPath $path -File -Force -ErrorAction SilentlyContinue }
            foreach ($it in $items) {
                $size = 0
                try {
                    if ($it.PSIsContainer) { $size = (Get-ChildItem -LiteralPath $it.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum }
                    else { $size = $it.Length }
                } catch { }
                try {
                    Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
                    $script:freed += [long]$size
                } catch { }   # arquivos em uso são ignorados
            }
        }

        $steps = @(
            @{ Label = "Temp do usuário";            Path = $env:TEMP;                                         Recurse = $true },
            @{ Label = "Temp do Windows";            Path = "$env:windir\Temp";                                Recurse = $true },
            @{ Label = "Itens recentes";             Path = "$env:APPDATA\Microsoft\Windows\Recent";           Recurse = $false },
            @{ Label = "Cache de internet (legado)"; Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache";   Recurse = $true },
            @{ Label = "Cache de shaders DirectX";   Path = "$env:LOCALAPPDATA\D3DSCache";                     Recurse = $true },
            @{ Label = "Despejos de falhas";         Path = "$env:LOCALAPPDATA\CrashDumps";                    Recurse = $true },
            @{ Label = "Relatórios de erro (WER)";   Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue";   Recurse = $true },
            @{ Label = "Relatórios de erro (WER)";   Path = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Recurse = $true }
        )
        $total = $steps.Count + 3
        $i = 0
        foreach ($s in $steps) {
            $i++
            Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Limpeza completa: $($s.Label)..." -Percent ([int]($i / $total * 100))
            Write-Host "Limpando: $($s.Label) ($($s.Path))"
            Remove-WinUtilBoostContents -path $s.Path -recurse $s.Recurse
        }

        $i++
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Limpeza completa: cache do Windows Update (SoftwareDistribution\Download)..." -Percent ([int]($i / $total * 100))
        Write-Host "Limpando: cache do Windows Update"
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
        Remove-WinUtilBoostContents -path "$env:windir\SoftwareDistribution\Download" -recurse $true
        Start-Service -Name bits -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue

        $i++
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Limpeza completa: cache DNS..." -Percent ([int]($i / $total * 100))
        ipconfig /flushdns | Out-Null

        $i++
        Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Limpeza completa: Lixeira..." -Percent ([int]($i / $total * 100))
        try { Clear-RecycleBin -Force -ErrorAction Stop } catch { }

        "Liberados ~$([math]::Round($script:freed / 1MB)) MB (arquivos em uso foram ignorados)."
    }
}

function Invoke-WinUtilBoostClearShaderCache {
    <#
    .SYNOPSIS
        Limpa o cache de shaders (NVIDIA DXCache/GLCache/OptixCache, AMD DxCache/GLCache/VkCache, Intel, DirectX D3DSCache).
        Os jogos recompilam os shaders na próxima execução (pode haver stutter inicial).
    #>
    $dirs = @(
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\NVIDIA\OptixCache",
        "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache",
        "$env:PROGRAMDATA\NVIDIA Corporation\NV_Cache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\AMD\DxcCache",
        "$env:LOCALAPPDATA\AMD\GLCache",
        "$env:LOCALAPPDATA\AMD\VkCache",
        "$env:LOCALAPPDATA\Intel\ShaderCache",
        "$env:LOCALAPPDATA\D3DSCache"
    )
    $freed = [long]0
    $found = 0
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $found++
        Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $size = 0
            try {
                if ($_.PSIsContainer) { $size = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } else { $size = $_.Length }
            } catch { }
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $freed += [long]$size } catch { }
        }
    }
    $msg = "Cache de shaders limpo em $found pasta(s). Liberados ~$([math]::Round($freed / 1MB)) MB.`n`nOs jogos vão recompilar os shaders na próxima execução (pode ter stutter no começo)."
    Write-Host $msg -ForegroundColor Green
    Write-WinUtilLog -Component "Boost" -Message "Shader cache limpo: ~$([math]::Round($freed / 1MB)) MB em $found pasta(s)."
    Set-WinUtilTweaksProgressIndicator -Visible $true -Label "Cache de shaders limpo: ~$([math]::Round($freed / 1MB)) MB liberados." -Percent 100
    [System.Windows.MessageBox]::Show($msg, "WinForge - Shader Cache", "OK", "Information") | Out-Null
}

function Invoke-WinUtilBoostOpenTool {
    <#
    .SYNOPSIS
        Abre um utilitário externo da pasta 'Apps' (ao lado do script). Se não existir, oferece abrir a página oficial.
    #>
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Name
    )
    $appsDir = Join-Path $sync.ScriptRoot 'Apps'
    $exe = $null
    if (Test-Path -LiteralPath $appsDir) {
        $exe = Get-ChildItem -Path $appsDir -Filter $Pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($exe) {
        Write-WinUtilLog -Component "Boost" -Message "Abrindo ferramenta externa: $($exe.FullName)"
        Start-Process -FilePath $exe.FullName -WorkingDirectory $appsDir
    } else {
        $r = [System.Windows.MessageBox]::Show("$Name não foi encontrado na pasta 'Apps' ao lado do WinForge.ps1`n($appsDir)`n`nAbrir a página oficial de download?", "WinForge", "YesNo", "Question")
        if ($r -eq [System.Windows.MessageBoxResult]::Yes) { Start-Process $Url }
    }
}

function Show-WinUtilBoostAbout {
    $gpu = if ($sync.GPUNames -and $sync.GPUNames.Count -gt 0) { $sync.GPUNames -join ', ' } else { 'não detectada' }
    $msg = @"
WinForge $($sync.version)
Ferramenta de otimização para Windows 10 e 11.

Sistema : $($sync.OSName) $($sync.OSDisplayVersion) (build $($sync.OSBuild))
GPU     : $gpu
Logs    : $($sync.logPath)

Base    : projeto original $($sync.baseVersion) (licença MIT) - ver arquivo NOTICE
Extras  : scripts do repositório 'Windows Boost - Essential' reescritos como tweaks reversíveis
          (aba Ajustes, aba Jogos e Configurações > WinForge - Manutenção)
"@
    Show-CustomDialog -Title "Sobre o WinForge" -Message $msg
}

function Show-WinUtilBoostCredits {
    # o launcher extrai o NOTICE.txt ao lado do motor; se o motor rodar solto, só cita o arquivo
    $noticePath = Join-Path $sync.ScriptRoot 'NOTICE.txt'
    if (Test-Path -LiteralPath $noticePath -PathType Leaf) {
        $noticeLine = '<a href="' + ([uri]$noticePath).AbsoluteUri + '">Abrir NOTICE (atribuições e licença MIT)</a>'
    } else {
        $noticeLine = "O arquivo NOTICE.txt acompanha o WinForge.exe / o pacote zip."
    }
    $msg = @"
WinForge é construído sobre um utilitário de código aberto sob licença MIT.
A atribuição completa aos autores originais está no arquivo NOTICE distribuído junto.

$noticeLine

As otimizações de jogos, GPU, serviços, energia e limpeza vêm do repositório
'Windows Boost - Essential' e foram revisadas para terem 'Desfazer' e detecção de estado.
"@
    Show-CustomDialog -Title "Créditos" -Message $msg
}
#endregion
