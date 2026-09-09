#region ===== WinForge - aba Diagnóstico =====
# Mostra o perfil coletado por Get-WinForgeSystemProfile em cartões, a tabela de drivers, o que as
# regras recomendaram e (sob demanda) os drivers que o Windows Update tem para este computador.
# Nada aqui aplica tweak: o único botão que mexe em seleção é "Marcar todos os recomendados", que
# só marca caixas (Select-WinForgeRecommended).
# O modelo de seções é montado uma vez (Get-WinForgeDiagSections) e serve tanto aos cartões da
# janela quanto ao relatório HTML - sem isso os dois sairiam contando histórias diferentes.

function Format-WinForgeDiagValue {
    <#
    .SYNOPSIS
        Texto de um campo do perfil, com 'n/d' no lugar de vazio/desconhecido e sim/não para booleano.
    .DESCRIPTION
        Campo $null não é erro: Secure Boot, TPM e BitLocker ficam nulos sem elevação, e VBS fica nulo
        onde o Device Guard não responde. 'n/d' diz isso ao usuário sem fingir um valor.
    #>
    param($Value, [string]$Suffix = '')

    if ($null -eq $Value) { return 'n/d' }
    if ($Value -is [bool]) { return $(if ($Value) { 'sim' } else { 'não' }) }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return 'n/d' }
    return "$text$Suffix"
}

function New-WinForgeDiagSection {
    <#
    .SYNOPSIS
        Seção vazia do diagnóstico (título + lista de linhas chave/valor).
    #>
    param([Parameter(Mandatory)][string]$Title)
    return [pscustomobject]@{ Title = $Title; Lines = [System.Collections.Generic.List[object]]::new() }
}

function Add-WinForgeDiagLine {
    <#
    .SYNOPSIS
        Acrescenta uma linha "chave: valor" a uma seção.
    #>
    param([Parameter(Mandatory)]$Section, [Parameter(Mandatory)][string]$Key, $Value)
    $Section.Lines.Add([pscustomobject]@{ Key = $Key; Value = [string]$Value })
}

function Get-WinForgeDiagSections {
    <#
    .SYNOPSIS
        Modelo do diagnóstico: uma seção por área do perfil (Sistema, Máquina, CPU, Memória, GPU,
        Armazenamento, Rede, Energia, Segurança e estado).
    .DESCRIPTION
        Fonte única dos cartões da janela e do relatório HTML. Área que a coleta não trouxe vira
        seção com linhas 'n/d' - o motivo real da falha aparece nas informações (perfil .Errors).
    .PARAMETER Profile
        Perfil devolvido por Get-WinForgeSystemProfile. Sem parâmetro usa $sync.Profile.
    .OUTPUTS
        Array de @{ Title; Lines = @(@{ Key; Value }) }.
    #>
    param($Profile)

    if ($null -eq $Profile) { $Profile = $sync.Profile }
    if ($null -eq $Profile) { return @() }

    $sections = [System.Collections.Generic.List[object]]::new()

    # ---- Sistema
    $os = $Profile.OS
    $sec = New-WinForgeDiagSection "Sistema"
    Add-WinForgeDiagLine $sec "Edição" (Format-WinForgeDiagValue $os.Caption)
    Add-WinForgeDiagLine $sec "Versão" ("{0} (build {1})" -f (Format-WinForgeDiagValue $os.DisplayVersion), (Format-WinForgeDiagValue $os.Build))
    Add-WinForgeDiagLine $sec "Arquitetura" (Format-WinForgeDiagValue $os.Architecture)
    Add-WinForgeDiagLine $sec "Instalado em" (Format-WinForgeDiagValue $os.InstallDate)
    Add-WinForgeDiagLine $sec "Ligado há" (Format-WinForgeDiagValue $os.UptimeHours ' h')
    if ($os.IsServer) {
        $roles = @()
        foreach ($r in @('IIS', 'AD', 'HyperV', 'DNS', 'DHCP', 'FileServer', 'RDS')) {
            if ($Profile.Roles.$r) { $roles += $r }
        }
        Add-WinForgeDiagLine $sec "Windows Server" "sim"
        Add-WinForgeDiagLine $sec "Funções instaladas" $(if ($roles.Count) { $roles -join ', ' } else { 'nenhuma detectada' })
    }
    $sections.Add($sec)

    # ---- Máquina
    $mc = $Profile.Machine
    $sec = New-WinForgeDiagSection "Máquina"
    Add-WinForgeDiagLine $sec "Fabricante" (Format-WinForgeDiagValue $mc.Manufacturer)
    Add-WinForgeDiagLine $sec "Modelo" (Format-WinForgeDiagValue $mc.Model)
    $tipo = if ($mc.IsVirtual) { 'máquina virtual' } elseif ($mc.IsLaptop) { 'notebook' } else { 'desktop' }
    Add-WinForgeDiagLine $sec "Tipo" $tipo
    Add-WinForgeDiagLine $sec "Hipervisor presente" (Format-WinForgeDiagValue $mc.HypervisorPresent)
    Add-WinForgeDiagLine $sec "Secure Boot" (Format-WinForgeDiagValue $mc.SecureBoot)
    Add-WinForgeDiagLine $sec "TPM" (Format-WinForgeDiagValue $mc.TpmVersion)
    Add-WinForgeDiagLine $sec "BitLocker" (Format-WinForgeDiagValue $mc.BitLocker)
    $sections.Add($sec)

    # ---- CPU
    $cpu = $Profile.CPU
    $sec = New-WinForgeDiagSection "Processador"
    Add-WinForgeDiagLine $sec "Modelo" (Format-WinForgeDiagValue $cpu.Name)
    Add-WinForgeDiagLine $sec "Núcleos" ("{0} físicos / {1} lógicos" -f (Format-WinForgeDiagValue $cpu.Cores), (Format-WinForgeDiagValue $cpu.Logical))
    Add-WinForgeDiagLine $sec "Frequência máxima" (Format-WinForgeDiagValue $cpu.MaxMHz ' MHz')
    Add-WinForgeDiagLine $sec "Núcleos híbridos (P/E)" (Format-WinForgeDiagValue $cpu.Hybrid)
    Add-WinForgeDiagLine $sec "Virtualização no firmware" (Format-WinForgeDiagValue $cpu.VirtualizationEnabled)
    $sections.Add($sec)

    # ---- Memória
    $ram = $Profile.RAM
    $sec = New-WinForgeDiagSection "Memória"
    Add-WinForgeDiagLine $sec "Total" (Format-WinForgeDiagValue $ram.TotalGB ' GB')
    Add-WinForgeDiagLine $sec "Livre" (Format-WinForgeDiagValue $ram.FreeGB ' GB')
    Add-WinForgeDiagLine $sec "Módulos" (Format-WinForgeDiagValue $ram.Modules)
    Add-WinForgeDiagLine $sec "Velocidade" (Format-WinForgeDiagValue $ram.SpeedMHz ' MHz')
    Add-WinForgeDiagLine $sec "Arquivo de paginação" (Format-WinForgeDiagValue $ram.PageFileGB ' GB')
    $sections.Add($sec)

    # ---- GPU (uma linha por adaptador, com driver instalado x mais recente)
    $sec = New-WinForgeDiagSection "Placa de vídeo"
    $gpus = @($Profile.GPU)
    if ($gpus.Count -eq 0) {
        Add-WinForgeDiagLine $sec "Adaptadores" "n/d"
    } else {
        foreach ($g in $gpus) {
            $instalado = Format-WinForgeDiagValue $g.DriverVersion
            if ($g.MarketingVersion) { $instalado = "$($g.MarketingVersion) ($($g.DriverVersion))" }
            $detalhe = "driver $instalado de $(Format-WinForgeDiagValue $g.DriverDate)"
            if ($g.VRAMGB) { $detalhe = "$($g.VRAMGB) GB, $detalhe" }
            if ($g.Latest) { $detalhe = "$detalhe | mais recente: $($g.Latest) de $(Format-WinForgeDiagValue $g.LatestDate)" }
            $detalhe = "$detalhe | situação: $(Format-WinForgeDiagValue $g.LatestStatus)"
            Add-WinForgeDiagLine $sec ([string]$g.Name) $detalhe
        }
    }
    $sections.Add($sec)

    # ---- Armazenamento
    $st = $Profile.Storage
    $sec = New-WinForgeDiagSection "Armazenamento"
    Add-WinForgeDiagLine $sec "Disco do sistema" (Format-WinForgeDiagValue $st.SystemDriveMedia)
    foreach ($d in @($st.Disks)) {
        Add-WinForgeDiagLine $sec ([string]$d.Name) ("{0} GB, {1}, barramento {2}, saúde {3}" -f (Format-WinForgeDiagValue $d.SizeGB), (Format-WinForgeDiagValue $d.MediaNormalized), (Format-WinForgeDiagValue $d.Bus), (Format-WinForgeDiagValue $d.Health))
    }
    foreach ($v in @($st.Volumes)) {
        Add-WinForgeDiagLine $sec ("Volume {0}:" -f (Format-WinForgeDiagValue $v.Letter)) ("{0} GB {1}, {2}% livre" -f (Format-WinForgeDiagValue $v.SizeGB), (Format-WinForgeDiagValue $v.FS), (Format-WinForgeDiagValue $v.FreePct))
    }
    $sections.Add($sec)

    # ---- Rede
    $net = $Profile.Network
    $sec = New-WinForgeDiagSection "Rede"
    Add-WinForgeDiagLine $sec "Adaptador" (Format-WinForgeDiagValue $net.Adapter)
    Add-WinForgeDiagLine $sec "Conexão" (Format-WinForgeDiagValue $net.Name)
    Add-WinForgeDiagLine $sec "Velocidade do enlace" (Format-WinForgeDiagValue $net.LinkSpeed)
    Add-WinForgeDiagLine $sec "Sem fio" (Format-WinForgeDiagValue $net.IsWifi)
    Add-WinForgeDiagLine $sec "DNS" $(if (@($net.Dns).Count) { @($net.Dns) -join ', ' } else { 'n/d' })
    Add-WinForgeDiagLine $sec "IPv6 ligado" (Format-WinForgeDiagValue $net.IPv6Enabled)
    $sections.Add($sec)

    # ---- Energia
    $pw = $Profile.Power
    $sec = New-WinForgeDiagSection "Energia"
    Add-WinForgeDiagLine $sec "Plano ativo" (Format-WinForgeDiagValue $pw.ActiveScheme)
    Add-WinForgeDiagLine $sec "GUID do plano" (Format-WinForgeDiagValue $pw.ActiveSchemeGuid)
    Add-WinForgeDiagLine $sec "Na bateria" (Format-WinForgeDiagValue $pw.OnBattery)
    Add-WinForgeDiagLine $sec "Hibernação" (Format-WinForgeDiagValue $pw.HibernationEnabled)
    $sections.Add($sec)

    # ---- Segurança e estado
    $stt = $Profile.State
    $sec = New-WinForgeDiagSection "Segurança e estado"
    Add-WinForgeDiagLine $sec "VBS (segurança por virtualização)" (Format-WinForgeDiagValue $stt.VBS)
    Add-WinForgeDiagLine $sec "HAGS (agendamento pela GPU)" (Format-WinForgeDiagValue $stt.HAGS)
    Add-WinForgeDiagLine $sec "Modo Jogo" (Format-WinForgeDiagValue $stt.GameMode)
    Add-WinForgeDiagLine $sec "SysMain" (Format-WinForgeDiagValue $stt.SysMain)
    Add-WinForgeDiagLine $sec "Windows Search" (Format-WinForgeDiagValue $stt.WSearch)
    Add-WinForgeDiagLine $sec "Inicialização rápida" (Format-WinForgeDiagValue $stt.FastStartup)
    $sections.Add($sec)

    return @($sections)
}

function Get-WinForgeDiagRecommendationItems {
    <#
    .SYNOPSIS
        Lista pronta para exibir do que as regras recomendaram e do que desaconselharam.
    .DESCRIPTION
        Só entra chave que existe na configuração de tweaks: uma regra pode citar uma entrada que a
        auditoria removeu, e mostrar o nome cru da chave não ajudaria ninguém. Recomendados primeiro,
        na ordem em que as regras os produziram.
    .OUTPUTS
        Array de @{ Key; Content; Reason; Icon; Hex; Kind }.
    #>
    $items = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $sync) { return @($items) }

    foreach ($group in @(
        @{ Map = $sync.Recommended; Icon = '✔'; Hex = '#2E7D32'; Kind = 'recomendado' },
        @{ Map = $sync.Discouraged; Icon = '⚠'; Hex = '#EF6C00'; Kind = 'evitar' }
    )) {
        if (-not $group.Map) { continue }
        foreach ($key in @($group.Map.Keys)) {
            if (-not $key) { continue }
            $entry = $sync.configs.tweaks.$key
            if ($null -eq $entry) { continue }
            $items.Add([pscustomobject]@{
                Key     = [string]$key
                Content = $(if ($entry.Content) { [string]$entry.Content } else { [string]$key })
                Reason  = [string]$group.Map[$key]
                Icon    = [string]$group.Icon
                Hex     = [string]$group.Hex
                Kind    = [string]$group.Kind
            })
        }
    }
    return @($items)
}

function Get-WinForgeDiagDriverRows {
    <#
    .SYNOPSIS
        Linhas da tabela de drivers a partir do inventário do perfil.
    .DESCRIPTION
        'Url' vira $null quando não há página de fabricante conhecida: a coluna de hyperlink liga o
        texto ao endereço, e uma string vazia ali só produziria um link morto.
    .OUTPUTS
        ObservableCollection de PSCustomObject (o DataGrid liga direto nela).
    #>
    param($Profile)

    if ($null -eq $Profile) { $Profile = $sync.Profile }
    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($d in @($Profile.Drivers)) {
        if ($null -eq $d) { continue }
        $status = [string]$d.Status
        if ([string]::IsNullOrWhiteSpace($status)) { $status = 'ok' }
        $icon = switch ($status) { 'atualizar' { '⬆' } 'verificar' { '⚠' } default { '✓' } }
        $url = [string]$d.Url
        if ([string]::IsNullOrWhiteSpace($url)) { $url = $null }
        $rows.Add([pscustomobject]@{
            Device     = [string]$d.Device
            Class      = [string]$d.Class
            Version    = (Format-WinForgeDiagValue $d.Version)
            Date       = (Format-WinForgeDiagValue $d.Date)
            Provider   = [string]$d.Provider
            Status     = $status
            StatusText = "$icon $status"
            Latest     = [string]$d.Latest
            Url        = $url
            UrlLabel   = $(if ($url) { 'página do fabricante' } else { '' })
        })
    }
    return ,$rows
}

function New-WinForgeDiagLineBlock {
    <#
    .SYNOPSIS
        TextBlock de uma linha do cartão: chave em negrito, valor normal.
    #>
    param([string]$Key, [string]$Value)

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'
    $tb.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSize")
    $tb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "MainForegroundColor")

    $keyRun = New-Object System.Windows.Documents.Run("${Key}: ")
    $keyRun.FontWeight = [System.Windows.FontWeights]::Bold
    $tb.Inlines.Add($keyRun)
    $tb.Inlines.Add((New-Object System.Windows.Documents.Run([string]$Value)))
    return $tb
}

function New-WinForgeDiagCard {
    <#
    .SYNOPSIS
        Cartão (Border no estilo da janela) com o título da seção e uma linha por campo.
    #>
    param([Parameter(Mandatory)]$Section)

    $border = New-Object System.Windows.Controls.Border
    $border.SetResourceReference([System.Windows.FrameworkElement]::StyleProperty, "BorderStyle")
    $border.Width = 360
    $border.VerticalAlignment = 'Top'

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Orientation = 'Vertical'

    $header = New-Object System.Windows.Controls.TextBlock
    $header.Text = [string]$Section.Title
    $header.TextWrapping = 'Wrap'
    $header.FontWeight = [System.Windows.FontWeights]::Bold
    $header.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
    $header.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "HeaderFontSize")
    $header.SetResourceReference([System.Windows.Controls.TextBlock]::FontFamilyProperty, "HeaderFontFamily")
    $header.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "LabelboxForegroundColor")
    $stack.Children.Add($header) | Out-Null

    foreach ($line in @($Section.Lines)) {
        $stack.Children.Add((New-WinForgeDiagLineBlock -Key ([string]$line.Key) -Value ([string]$line.Value))) | Out-Null
    }

    $border.Child = $stack
    return $border
}

function Update-WinForgeDiagnosticsTab {
    <#
    .SYNOPSIS
        Redesenha a aba Diagnóstico a partir de $sync.Profile, $sync.Recommended, $sync.Discouraged
        e $sync.RuleInfos.
    .DESCRIPTION
        Tem de rodar na thread da interface (quem chama de dentro do job usa Invoke-WPFUIThread) e,
        por causa dos pipelines daqui, num scriptblock da runspace principal - veja o comentário em
        Start-WinForgeProfileJob.
        Rodar com a aba fechada é normal e seguro: os controles nascem com o XAML, não com a montagem
        da aba, e o diagnóstico costuma terminar com a janela ainda na aba Instalar. Quem abre a aba
        depois cai em Initialize-WinForgeDiagnosticsTab, que liga os hyperlinks e redesenha.
    #>
    # Todos os controles da aba nascem com o XAML, muito antes de a aba ser aberta: a guarda pega a
    # janela que ainda não carregou (e o -SelfTest antes de $sync.Form existir), não a aba fechada.
    if ($null -eq $sync) { return }
    foreach ($wfCtl in @('WPFDiagCards', 'WPFDiagRecs', 'WPFDiagInfos', 'WPFDiagDrivers', 'WPFDiagStatus')) {
        if ($null -eq $sync[$wfCtl]) { return }
    }

    $p = $sync.Profile
    if ($null -eq $p) {
        $sync.WPFDiagStatus.Text = "Coletando informações do sistema..."
        return
    }

    # ---- cartões
    $sync.WPFDiagCards.Children.Clear()
    foreach ($section in (Get-WinForgeDiagSections -Profile $p)) {
        $sync.WPFDiagCards.Children.Add((New-WinForgeDiagCard -Section $section)) | Out-Null
    }

    # ---- recomendações
    $sync.WPFDiagRecs.Items.Clear()
    $recItems = @(Get-WinForgeDiagRecommendationItems)
    foreach ($item in $recItems) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "$($item.Icon) $($item.Content) — $($item.Reason)"
        $tb.TextWrapping = 'Wrap'
        $tb.Margin = New-Object System.Windows.Thickness(0, 2, 0, 2)
        $tb.Foreground = New-WinForgeRecoBrush -Hex $item.Hex
        $tb.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSize")
        $sync.WPFDiagRecs.Items.Add($tb) | Out-Null
    }

    # ---- informações das regras + falhas de coleta
    $infos = [System.Collections.Generic.List[string]]::new()
    foreach ($i in @($sync.RuleInfos)) { if ($i) { $infos.Add("• $i") } }
    foreach ($e in @($p.Errors)) { if ($e) { $infos.Add("• Falha ao coletar -> $e") } }
    if ($infos.Count -gt 0) {
        $sync.WPFDiagInfos.Text = ($infos -join [Environment]::NewLine)
        $sync.WPFDiagInfos.Visibility = 'Visible'
    } else {
        $sync.WPFDiagInfos.Text = ''
        $sync.WPFDiagInfos.Visibility = 'Collapsed'
    }

    # ---- drivers
    $sync.WPFDiagDrivers.ItemsSource = (Get-WinForgeDiagDriverRows -Profile $p)

    # $sync.Recommended pode ser $null (nenhum diagnóstico rodou ainda): @($null.Keys) tem um item,
    # não zero - daí as guardas, senão a linha de resumo mentiria "1 recomendação".
    $nRec = $(if ($sync.Recommended) { @($sync.Recommended.Keys).Count } else { 0 })
    $nEvi = $(if ($sync.Discouraged) { @($sync.Discouraged.Keys).Count } else { 0 })
    $pendentes = @(@($p.Drivers) | Where-Object { $_ -and $_.Status -ne 'ok' }).Count
    $sync.WPFDiagStatus.Text = "Diagnóstico de {0} | {1} recomendação(ões), {2} a evitar | {3} driver(s), {4} para conferir | {5} falha(s) de coleta" -f `
        (Format-WinForgeDiagValue $p.GeneratedAt), $nRec, $nEvi, @($p.Drivers).Count, $pendentes, @($p.Errors).Count

    Write-WinForgeLog -Component "Diag" -Message "Aba Diagnóstico atualizada: $($sync.WPFDiagCards.Children.Count) cartões, $(@($p.Drivers).Count) drivers, $($recItems.Count) recomendações."
}

function Update-WinForgeDiagnosticsWindowsUpdateGrid {
    <#
    .SYNOPSIS
        Preenche a tabela dos drivers oferecidos pelo Windows Update ($sync.DiagWUResults).
    .DESCRIPTION
        Roda na thread da interface. A tabela e o título só aparecem depois da primeira busca - antes
        disso não há nada a dizer, e uma tabela vazia parada na aba sugeriria que a busca já rodou.
    #>
    if ($null -eq $sync -or $null -eq $sync.WPFDiagWU) { return }

    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($u in @($sync.DiagWUResults)) {
        if ($null -eq $u) { continue }
        $rows.Add([pscustomobject]@{
            Title    = [string]$u.Title
            Driver   = (Format-WinForgeDiagValue $u.Driver)
            Provider = (Format-WinForgeDiagValue $u.Provider)
            Version  = (Format-WinForgeDiagValue $u.Version)
            Date     = (Format-WinForgeDiagValue $u.Date)
        })
    }

    $sync.WPFDiagWU.ItemsSource = $rows
    $sync.WPFDiagWU.Visibility = 'Visible'
    $sync.WPFDiagWULabel.Visibility = 'Visible'
    $sync.WPFDiagWULabel.Text = if ($rows.Count -gt 0) {
        "Drivers oferecidos pelo Windows Update ($($rows.Count))"
    } elseif ($sync.LastWUError) {
        "Windows Update: a consulta falhou -> $($sync.LastWUError)"
    } else {
        "Windows Update: nenhum driver pendente para este computador"
    }
}

function Invoke-WinForgeDriverUpdateSearch {
    <#
    .SYNOPSIS
        Pergunta ao Windows Update quais drivers ele tem para este computador, fora da thread da
        interface.
    .DESCRIPTION
        A consulta COM fala com os servidores da Microsoft e pode levar de 10 a 60 segundos: na thread
        da janela ela congelaria tudo. Uma busca por vez; a barra de progresso só é usada quando nenhum
        outro trabalho está nela (o texto do que o usuário mandou fazer vale mais que o desta consulta).
    #>
    if ($sync.DiagWUSearchRunning) {
        Write-WinForgeLog -Component "Diag" -Message "Busca de drivers no Windows Update já em andamento; pedido ignorado."
        return
    }
    $sync.DiagWUSearchRunning = $true
    $sync.LastWUError = $null
    if (-not $sync.ProcessRunning) {
        Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Consultando o Windows Update (pode levar até um minuto)..." -Percent 0
    }
    Write-WinForgeLog -Component "Diag" -Message "Busca de drivers no Windows Update iniciada."

    # Criado aqui, na runspace principal (esta função roda no clique do botão): um scriptblock feito
    # dentro do corpo do job pertenceria à runspace do pool e travaria no primeiro pipeline quando o
    # Dispatcher o executasse - o mesmo laço descrito em Start-WinForgeProfileJob.
    $sync.WinForgeWUUiRefresh = {
        try {
            Update-WinForgeDiagnosticsWindowsUpdateGrid
        } catch {
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Windows Update: falha ao atualizar a tabela -> $($_.Exception.Message)"
        }
    }

    # A consulta COM não é interrompível: quando a janela fecha no meio dela, o processo já está
    # indo embora e nada mais aqui pode tocar a interface - escrever na barra ou pedir o Dispatcher
    # seria esperar por uma thread que está desligando.
    $wfBody = {
        try {
            $sync.DiagWUResults = @(Search-WinForgeWindowsUpdateDrivers)
            if (-not $sync.WinForgeClosing) { Invoke-WPFUIThread $sync.WinForgeWUUiRefresh }
            $wfMsg = if ($sync.LastWUError) {
                "Windows Update: a consulta falhou -> $($sync.LastWUError)"
            } else {
                "Windows Update: $(@($sync.DiagWUResults).Count) driver(s) disponível(is) para este computador."
            }
            if (-not $sync.ProcessRunning -and -not $sync.WinForgeClosing) {
                Set-WinForgeTweaksProgressIndicator -Visible $true -Label $wfMsg -Percent 100
            }
            Write-WinForgeLog -Component "Diag" -Message $wfMsg
        } catch {
            Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Busca no Windows Update falhou: $($_.Exception.Message)"
            if (-not $sync.ProcessRunning -and -not $sync.WinForgeClosing) {
                Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Busca no Windows Update falhou: $($_.Exception.Message)" -Percent 0
            }
        } finally {
            $sync.DiagWUSearchRunning = $false
        }
    }

    # Se o despacho falhar (pool fechado, sem thread livre), quem zera a trava é este catch: sem ele
    # $sync.DiagWUSearchRunning ficaria ligado para sempre e o botão nunca mais responderia.
    try {
        Invoke-WPFRunspace -ScriptBlock $wfBody | Out-Null
    } catch {
        $sync.DiagWUSearchRunning = $false
        Write-WinForgeLog -Component "Diag" -Level "ERROR" -Message "Busca no Windows Update não pôde começar: $($_.Exception.Message)"
        if (-not $sync.ProcessRunning) {
            Set-WinForgeTweaksProgressIndicator -Visible $true -Label "Busca no Windows Update não pôde começar: $($_.Exception.Message)" -Percent 0
        }
    }
}

function Initialize-WinForgeDiagnosticsTab {
    <#
    .SYNOPSIS
        Monta a aba Diagnóstico (chamada por Initialize-WinForgeTabContent na primeira vez que a aba
        é aberta).
    .DESCRIPTION
        Os botões já são ligados a Invoke-WPFButton pelo laço geral da janela; o que falta aqui é o
        clique nos links da coluna "Fabricante", que é evento roteado de Hyperlink e não de Button.
        O handler é registrado uma única vez - a aba pode ser redesenhada muitas vezes, e um handler
        por redesenho abriria o navegador várias vezes no mesmo clique.
    #>
    if ($null -eq $sync -or $null -eq $sync.WPFDiagDrivers) { return }

    if (-not $sync.DiagNavigateHandlerWired) {
        $handler = [System.Windows.Navigation.RequestNavigateEventHandler] {
            param($eventSender, $eventArgs)
            try { Start-Process $eventArgs.Uri.AbsoluteUri } catch {
                Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Não foi possível abrir o link: $($_.Exception.Message)"
            }
            $eventArgs.Handled = $true
        }
        $sync.WPFDiagDrivers.AddHandler([System.Windows.Documents.Hyperlink]::RequestNavigateEvent, $handler)
        $sync.DiagNavigateHandlerWired = $true
    }

    Update-WinForgeDiagnosticsTab
}

function ConvertTo-WinForgeDiagHtml {
    <#
    .SYNOPSIS
        Texto seguro para o relatório (escapa &, <, > e aspas).
    #>
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Export-WinForgeDiagnosticsReport {
    <#
    .SYNOPSIS
        Gera o relatório HTML do diagnóstico e o abre no navegador.
    .DESCRIPTION
        Arquivo único, sem nada externo (CSS embutido, tema escuro): pode ser enviado por e-mail ou
        aberto em outra máquina. Gravado em UTF-8 com BOM para que navegador e Bloco de Notas leiam
        os acentos sem depender da code page do sistema.
    .PARAMETER Path
        Caminho do arquivo. Sem parâmetro:
        %LocalAppData%\WinForge\reports\diagnostico-<aaaaMMdd-HHmmss>.html
        Com os segundos no nome, dois relatórios seguidos não se sobrescrevem.
    .PARAMETER NoOpen
        Não abre o arquivo depois de gravar (usado pelo -SelfTest).
    .OUTPUTS
        Caminho do arquivo gerado, ou $null se o diagnóstico ainda não terminou.
    #>
    param([string]$Path, [switch]$NoOpen)

    $p = $sync.Profile
    if ($null -eq $p) {
        Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Relatório não gerado: o diagnóstico ainda não terminou."
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $env:LocalAppData ("WinForge\reports\diagnostico-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $html = New-Object System.Text.StringBuilder
    [void]$html.AppendLine('<!DOCTYPE html>')
    [void]$html.AppendLine('<html lang="pt-br"><head><meta charset="utf-8">')
    [void]$html.AppendLine("<title>WinForge - diagnóstico de $(ConvertTo-WinForgeDiagHtml $env:COMPUTERNAME)</title>")
    [void]$html.AppendLine('<style>')
    [void]$html.AppendLine(@'
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; padding: 24px; background: #1b1e21; color: #e6e6e6;
       font-family: "Segoe UI", Tahoma, Arial, sans-serif; font-size: 14px; line-height: 1.5; }
h1 { font-size: 24px; margin: 0 0 4px 0; color: #ffffff; }
h2 { font-size: 18px; margin: 32px 0 12px 0; color: #ffffff;
     border-bottom: 1px solid #3a3f44; padding-bottom: 6px; }
.sub { color: #9aa0a6; margin: 0 0 8px 0; }
.cards { display: flex; flex-wrap: wrap; gap: 16px; }
.card { background: #232629; border: 1px solid #3a3f44; border-radius: 6px;
        padding: 14px 16px; min-width: 320px; flex: 1 1 320px; }
.card h3 { font-size: 15px; margin: 0 0 8px 0; color: #7ec8ff; }
.card div { margin: 2px 0; word-break: break-word; }
.card b { color: #cfd3d7; }
table { border-collapse: collapse; width: 100%; margin-top: 8px; }
th, td { border-bottom: 1px solid #3a3f44; padding: 6px 8px; text-align: left; vertical-align: top; }
th { color: #cfd3d7; background: #232629; font-weight: 600; }
tr:hover td { background: #232629; }
a { color: #7ec8ff; }
ul { margin: 8px 0; padding-left: 20px; }
li { margin: 3px 0; }
.ok { color: #7dc97d; }
.warn { color: #f9a825; }
.upd { color: #ef6c00; }
.rec { color: #7dc97d; }
.avoid { color: #ef8a3c; }
footer { margin-top: 40px; color: #7d8288; font-size: 12px;
         border-top: 1px solid #3a3f44; padding-top: 10px; }
'@)
    [void]$html.AppendLine('</style></head><body>')

    [void]$html.AppendLine("<h1>WinForge - relatório de diagnóstico</h1>")
    [void]$html.AppendLine("<p class=""sub"">Computador: $(ConvertTo-WinForgeDiagHtml $env:COMPUTERNAME) &middot; Coletado em: $(ConvertTo-WinForgeDiagHtml $p.GeneratedAt) &middot; WinForge $(ConvertTo-WinForgeDiagHtml $sync.version)</p>")

    # ---- cartões
    [void]$html.AppendLine('<h2>Sistema</h2>')
    [void]$html.AppendLine('<div class="cards">')
    foreach ($section in (Get-WinForgeDiagSections -Profile $p)) {
        [void]$html.AppendLine('<div class="card">')
        [void]$html.AppendLine("<h3>$(ConvertTo-WinForgeDiagHtml $section.Title)</h3>")
        foreach ($line in @($section.Lines)) {
            [void]$html.AppendLine("<div><b>$(ConvertTo-WinForgeDiagHtml $line.Key):</b> $(ConvertTo-WinForgeDiagHtml $line.Value)</div>")
        }
        [void]$html.AppendLine('</div>')
    }
    [void]$html.AppendLine('</div>')

    # ---- recomendações
    [void]$html.AppendLine('<h2>Recomendações para este computador</h2>')
    $recItems = @(Get-WinForgeDiagRecommendationItems)
    if ($recItems.Count -eq 0) {
        [void]$html.AppendLine('<p>Nenhuma recomendação específica para este sistema.</p>')
    } else {
        [void]$html.AppendLine('<ul>')
        foreach ($item in $recItems) {
            $cls = if ($item.Kind -eq 'recomendado') { 'rec' } else { 'avoid' }
            [void]$html.AppendLine("<li class=""$cls"">$(ConvertTo-WinForgeDiagHtml $item.Icon) <b>$(ConvertTo-WinForgeDiagHtml $item.Content)</b> &mdash; $(ConvertTo-WinForgeDiagHtml $item.Reason)</li>")
        }
        [void]$html.AppendLine('</ul>')
    }

    # ---- informações e falhas de coleta
    $infos = [System.Collections.Generic.List[string]]::new()
    foreach ($i in @($sync.RuleInfos)) { if ($i) { $infos.Add([string]$i) } }
    foreach ($e in @($p.Errors)) { if ($e) { $infos.Add("Falha ao coletar -> $e") } }
    if ($infos.Count -gt 0) {
        [void]$html.AppendLine('<h2>Observações</h2><ul>')
        foreach ($i in $infos) { [void]$html.AppendLine("<li>$(ConvertTo-WinForgeDiagHtml $i)</li>") }
        [void]$html.AppendLine('</ul>')
    }

    # ---- drivers
    [void]$html.AppendLine('<h2>Drivers instalados</h2>')
    [void]$html.AppendLine('<table><tr><th>Dispositivo</th><th>Classe</th><th>Versão</th><th>Data</th><th>Fornecedor</th><th>Status</th><th>Fabricante</th></tr>')
    foreach ($row in (Get-WinForgeDiagDriverRows -Profile $p)) {
        $cls = switch ($row.Status) { 'atualizar' { 'upd' } 'verificar' { 'warn' } default { 'ok' } }
        $link = if ($row.Url) { "<a href=""$(ConvertTo-WinForgeDiagHtml $row.Url)"">$(ConvertTo-WinForgeDiagHtml $row.UrlLabel)</a>" } else { '' }
        [void]$html.AppendLine("<tr><td>$(ConvertTo-WinForgeDiagHtml $row.Device)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Class)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Version)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Date)</td><td>$(ConvertTo-WinForgeDiagHtml $row.Provider)</td><td class=""$cls"">$(ConvertTo-WinForgeDiagHtml $row.StatusText)</td><td>$link</td></tr>")
    }
    [void]$html.AppendLine('</table>')

    # ---- Windows Update (só se a busca já rodou nesta sessão)
    $wu = @($sync.DiagWUResults)
    if ($wu.Count -gt 0) {
        [void]$html.AppendLine('<h2>Drivers oferecidos pelo Windows Update</h2>')
        [void]$html.AppendLine('<table><tr><th>Atualização</th><th>Driver</th><th>Fornecedor</th><th>Versão</th><th>Data</th></tr>')
        foreach ($u in $wu) {
            if ($null -eq $u) { continue }
            [void]$html.AppendLine("<tr><td>$(ConvertTo-WinForgeDiagHtml $u.Title)</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Driver))</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Provider))</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Version))</td><td>$(ConvertTo-WinForgeDiagHtml (Format-WinForgeDiagValue $u.Date))</td></tr>")
        }
        [void]$html.AppendLine('</table>')
    }

    [void]$html.AppendLine("<footer>Gerado pelo WinForge $(ConvertTo-WinForgeDiagHtml $sync.version) em $(ConvertTo-WinForgeDiagHtml (Get-Date).ToString('dd/MM/yyyy HH:mm')). Este relatório descreve o estado do computador; nenhuma alteração foi aplicada ao gerá-lo.</footer>")
    [void]$html.AppendLine('</body></html>')

    # BOM: sem ele o navegador pode adivinhar a code page do sistema e comer os acentos
    [System.IO.File]::WriteAllText($Path, $html.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    Write-WinForgeLog -Component "Diag" -Message "Relatório de diagnóstico gerado: $Path"

    if (-not $NoOpen) {
        try { Start-Process $Path } catch {
            Write-WinForgeLog -Component "Diag" -Level "WARN" -Message "Relatório gerado, mas não foi possível abri-lo: $($_.Exception.Message)"
        }
    }
    return $Path
}
#endregion
