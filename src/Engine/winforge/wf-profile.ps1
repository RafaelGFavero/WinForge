#region ===== WinForge - perfil do sistema =====
# Retrato do computador (SO, papéis, máquina, CPU, RAM, GPU, disco, rede, energia, estado e drivers).
# Toda folha é valor simples ou array - nada de objeto CIM -, para que o perfil sobreviva a
# ConvertTo-Json e seja consumido pelas regras de recomendação.
# Cada área roda dentro do seu try/catch: uma falha vira campo $null mais uma linha em .Errors,
# nunca uma exceção que escape para quem chamou.

function ConvertTo-WinForgeNvidiaVersion {
    <#
    .SYNOPSIS
        Converte a versão de driver do Windows na versão comercial da NVIDIA (32.0.16.1656 -> 616.56).
    .DESCRIPTION
        A NVIDIA embute a versão comercial nos dois últimos grupos: 16 + 1656 = 161656, cujos
        cinco últimos dígitos (61656) são lidos como 616.56. Devolve $null se o formato não bater.
    #>
    param([string]$DriverVersion)
    if ($DriverVersion -match '^\d+\.\d+\.(\d+)\.(\d+)$') {
        $digits = ($Matches[1] + $Matches[2])
        if ($digits.Length -ge 5) {
            $d = $digits.Substring($digits.Length - 5)
            return ('{0}.{1}' -f $d.Substring(0, 3), $d.Substring(3))
        }
    }
    return $null
}

function Get-WinForgeVendorKey {
    <#
    .SYNOPSIS
        Reduz fabricante + nome do dispositivo a uma chave curta ('nvidia', 'amd', 'intel', ...)
        usada pelas regras e pela consulta de driver.
    #>
    param([string]$Provider, [string]$Device)
    $t = "$Provider $Device"
    switch -Regex ($t) {
        'NVIDIA'            { 'nvidia';   break }
        'AMD|Advanced Micro Devices|Radeon|ATI ' { 'amd'; break }
        'Intel'             { 'intel';    break }
        'Realtek'           { 'realtek';  break }
        'Qualcomm|Atheros'  { 'qualcomm'; break }
        'MediaTek'          { 'mediatek'; break }
        'Broadcom'          { 'broadcom'; break }
        'Logitech'          { 'logitech'; break }
        default             { 'other' }
    }
}

function Get-WinForgeDriverInventory {
    <#
    .SYNOPSIS
        Inventário dos drivers que interessam (vídeo, rede, áudio, armazenamento, chipset, USB,
        Bluetooth), ignorando os que vêm da própria Microsoft.
    .DESCRIPTION
        'Old' marca o driver que vale a pena conferir, e o prazo depende da classe: vídeo, rede,
        áudio e Bluetooth mudam de verdade a cada poucos meses (180 dias), enquanto chipset, USB e
        controladoras de disco saem de fábrica com INF de anos e continuam certos - marcar tudo isso
        transformava a coluna "verificar" em ruído (17 de 20 numa máquina saudável), então para elas
        o prazo é de três anos.
        A ordenação inclui DeviceID: dois adaptadores de rede idênticos são duas linhas, e sem ele
        o -Unique jogaria um fora, fazendo o inventário mentir na contagem.
        'Status', 'Latest' e 'Url' são preenchidos depois pela consulta online
        (Update-WinForgeProfileDriverStatus).
    #>
    $classes = 'DISPLAY', 'NET', 'MEDIA', 'HDC', 'SCSIADAPTER', 'SYSTEM', 'USB', 'BLUETOOTH'
    $watchedClasses = 'DISPLAY', 'NET', 'MEDIA', 'BLUETOOTH'
    $cutoff = (Get-Date).AddDays(-180)
    $cutoffOther = (Get-Date).AddDays(-1095)
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceClass -in $classes -and $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' -and $_.DeviceName } |
        Sort-Object DeviceClass, DeviceName, DeviceID -Unique |
        ForEach-Object {
            [pscustomobject]@{
                Device   = $_.DeviceName
                Class    = $_.DeviceClass
                Version  = $_.DriverVersion
                Date     = $(if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '' })
                Provider = $_.DriverProviderName
                Signed   = [bool]$_.IsSigned
                Signer   = $_.Signer
                Vendor   = (Get-WinForgeVendorKey $_.DriverProviderName $_.DeviceName)
                Old      = $(if ($_.DriverDate) { $_.DriverDate -lt $(if ($_.DeviceClass -in $watchedClasses) { $cutoff } else { $cutoffOther }) } else { $false })
                Status   = 'ok'
                Latest   = $null
                Url      = $null
            }
        }
}

function Get-WinForgeSystemProfile {
    <#
    .SYNOPSIS
        Monta o perfil completo do sistema.
    .PARAMETER SkipNetwork
        Não consulta a internet para saber se há driver mais novo (usado pelo -SelfTest).
    #>
    param([switch]$SkipNetwork)

    $p = [ordered]@{ GeneratedAt = (Get-Date).ToString('s'); Errors = @(); Simulated = $null }

    # ---- Servidor simulado (WINFORGE_SIMULATE_SERVER): o mesmo override que o banner usa vale aqui.
    # Sem isto a janela dizia "Windows Server" e o perfil devolvia OS.IsServer=$false e Server=$null:
    # todo cartão e toda regra da aba Servidor caía em null exatamente na execução que deveria
    # exercitá-los. Os papéis vêm de $sync (já normalizados por Get-WinUtilBoostSystemInfo); fora da
    # janela - perfil chamado solto -, lê a variável direto, com a mesma normalização.
    # Detecção real fica intacta quando a variável não existe.
    $wfSimServer = ($null -ne $env:WINFORGE_SIMULATE_SERVER)
    $wfSimRoles  = @()
    $wfSimIsDC   = $false
    if ($wfSimServer) {
        $wfSyncRef = $null
        try { $wfSyncRef = Get-Variable -Name sync -ValueOnly -ErrorAction Stop } catch { }
        if ($wfSyncRef -and $wfSyncRef.ServerRoles) {
            $wfSimRoles = @($wfSyncRef.ServerRoles)
            $wfSimIsDC  = [bool]$wfSyncRef.IsDC
        } else {
            $wfSimRoles = @($env:WINFORGE_SIMULATE_SERVER -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -and $_ -ne 'none' })
            $wfSimIsDC  = ('ad' -in $wfSimRoles)
        }
        # O relatório HTML e o cartão Servidor passam a dizer de onde veio esse "servidor": sob
        # simulação o perfil relata ProductType 3 numa máquina que é ProductType 1, e um relatório
        # que afirma isso sem ressalva vira uma informação errada quando alguém o abre depois.
        $p.Simulated = 'env:WINFORGE_SIMULATE_SERVER'
    }

    # ---- SO
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $p.OS = [ordered]@{
            Caption        = $os.Caption
            Build          = [int][Environment]::OSVersion.Version.Build
            DisplayVersion = [string]$cv.DisplayVersion
            IsWin11        = ([Environment]::OSVersion.Version.Build -ge 22000)
            IsServer       = ($wfSimServer -or ($os.ProductType -ne 1))
            # 3 = servidor membro; sob simulação num cliente (ProductType 1) o perfil relata 3 para
            # não ficar com IsServer=$true e ProductType=1, combinação que não existe em máquina real.
            ProductType    = $(if ($wfSimServer -and [int]$os.ProductType -eq 1) { 3 } else { [int]$os.ProductType })
            InstallDate    = $os.InstallDate.ToString('yyyy-MM-dd')
            UptimeHours    = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
            Architecture   = $os.OSArchitecture
        }
    } catch { $p.Errors += "OS: $($_.Exception.Message)" }

    # ---- Papéis (só no Server: Get-WindowsFeature não existe no cliente)
    # IsDC/DomainRole/Domain valem para qualquer SO: um cliente ingressado no domínio também
    # interessa às regras, e DomainRole >= 4 é o que separa controlador de domínio de membro.
    $p.Roles = [ordered]@{ IIS = $false; AD = $false; HyperV = $false; DNS = $false; DHCP = $false; FileServer = $false; RDS = $false
                           IsDC = $false; DomainRole = $null; Domain = $null }
    # $csRole é consultado uma vez só e reaproveitado pela área Máquina mais abaixo - eram duas
    # chamadas à mesma classe, e Win32_ComputerSystem não é barato.
    $csRole = $null
    try {
        $csRole = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $p.Roles.DomainRole = [int]$csRole.DomainRole
        $p.Roles.Domain     = [string]$csRole.Domain
        $p.Roles.IsDC       = ($p.Roles.DomainRole -ge 4)
    } catch { $p.Errors += "DomainRole: $($_.Exception.Message)" }
    if ($wfSimServer) {
        # Simulação: os papéis vêm da lista, e não do Get-WindowsFeature que não existe no cliente.
        # FileServer/RDS não têm sigla na simulação e ficam $false.
        $p.Roles.IIS    = ('iis'    -in $wfSimRoles)
        $p.Roles.AD     = ('ad'     -in $wfSimRoles)
        $p.Roles.HyperV = ('hyperv' -in $wfSimRoles)
        $p.Roles.DNS    = ('dns'    -in $wfSimRoles)
        $p.Roles.DHCP   = ('dhcp'   -in $wfSimRoles)
        $p.Roles.IsDC   = $wfSimIsDC
    } elseif ($p.OS.IsServer -and (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) {
        try {
            $f = Get-WindowsFeature | Where-Object Installed | Select-Object -ExpandProperty Name
            $p.Roles.IIS        = 'Web-Server' -in $f
            $p.Roles.AD         = 'AD-Domain-Services' -in $f
            $p.Roles.HyperV     = 'Hyper-V' -in $f
            $p.Roles.DNS        = 'DNS' -in $f
            $p.Roles.DHCP       = 'DHCP' -in $f
            $p.Roles.FileServer = 'FS-FileServer' -in $f
            $p.Roles.RDS        = 'RDS-RD-Server' -in $f
        } catch { $p.Errors += "Roles: $($_.Exception.Message)" }
    }

    # ---- Máquina
    try {
        # reaproveita a consulta do bloco Papéis; só refaz se aquela tiver falhado
        $cs = $(if ($csRole) { $csRole } else { Get-CimInstance Win32_ComputerSystem })
        $enc = Get-CimInstance Win32_SystemEnclosure
        $chassis = @($enc.ChassisTypes)
        $laptopTypes = 8, 9, 10, 11, 12, 14, 30, 31, 32
        # Gabinete que o fabricante declarou como de mesa (torre, desktop, rack...). A bateria só
        # conta como sinal de notebook fora dessa lista: um no-break USB (APC, CyberPower) aparece
        # como Win32_Battery e transformava qualquer torre em "notebook" - com isso a regra 'laptop'
        # disparava e a 'desktop' nunca disparava numa máquina de mesa.
        $desktopTypes = 3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24
        $chassisIsPortable = (@($chassis | Where-Object { $_ -in $laptopTypes }).Count -gt 0)
        $chassisIsDesktop  = (@($chassis | Where-Object { $_ -in $desktopTypes }).Count -gt 0)
        $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        # HypervisorPresent NÃO serve para detectar VM: ele fica ligado em máquina física com
        # Hyper-V, WSL2, Sandbox, Credential Guard ou VBS. A virtualização é decidida pela
        # assinatura do fabricante/modelo; HypervisorPresent vai junto, como campo separado.
        # A lista inclui os convidados de nuvem mais comuns, que não trazem 'Virtual' no nome.
        $vmSignature = 'VMware|VirtualBox|innotek|KVM|QEMU|Virtual Machine|Hyper-V|Xen|Parallels|Bochs|BHYVE|' +
                       'Amazon EC2|Google Compute Engine|Nutanix|OpenStack|oVirt|Cloud Hosting|Alibaba Cloud'
        $p.Machine = [ordered]@{
            Manufacturer      = $cs.Manufacturer
            Model             = $cs.Model
            IsVirtual         = ("$($cs.Manufacturer) $($cs.Model) $($cs.SystemFamily)" -match $vmSignature)
            HypervisorPresent = [bool]$cs.HypervisorPresent
            IsLaptop          = $chassisIsPortable -or ($hasBattery -and -not $chassisIsDesktop)
            ChassisTypes      = $chassis
            SecureBoot        = $null
            TpmVersion        = $null
            BitLocker         = $null
        }
        # os três abaixo dependem de elevação/firmware: sem admin ficam $null, e isso é esperado
        try { $p.Machine.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $p.Machine.SecureBoot = $null }
        # TPM e BitLocker sem elevação não devolvem "nada": devolvem "Acesso negado" depois de 5s
        # cada um. Como o resultado sem admin é $null de qualquer jeito, nem tenta - o perfil inteiro
        # cai de ~16s para ~6s no -SelfTest, que roda sem elevação.
        $wfElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($wfElevated) {
            try {
                $tpm = Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop
                if ($tpm) { $p.Machine.TpmVersion = ($tpm.SpecVersion -split ',')[0].Trim() }
            } catch { }
            try {
                $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
                $p.Machine.BitLocker = [string]$bl.ProtectionStatus
            } catch { }
        }
    } catch { $p.Errors += "Machine: $($_.Exception.Message)" }

    # ---- CPU
    try {
        $c = Get-CimInstance Win32_Processor | Select-Object -First 1
        $vendor = switch -Regex ($c.Manufacturer) { 'Intel' { 'intel' } 'AMD' { 'amd' } default { 'other' } }
        $p.CPU = [ordered]@{
            Name                  = $c.Name.Trim()
            Vendor                = $vendor
            Cores                 = [int]$c.NumberOfCores
            Logical               = [int]$c.NumberOfLogicalProcessors
            MaxMHz                = [int]$c.MaxClockSpeed
            # 12ª geração em diante: o SKU de mesa tem cinco dígitos (i7-12700K) e o de notebook
            # quatro (i5-1235U), daí o {2,3}. O 'i<n>-' na frente evita casar com Xeon E5-1650 e
            # afins, e o (?!\d) deixa passar o sufixo de letra (K/U/H).
            Hybrid                = ($vendor -eq 'intel' -and $c.Name -match '(?i)i[3579]-1[2-9]\d{2,3}(?!\d)|Core(\(TM\))?\s*Ultra')
            VirtualizationEnabled = [bool]$c.VirtualizationFirmwareEnabled
        }
    } catch { $p.Errors += "CPU: $($_.Exception.Message)" }

    # ---- RAM
    try {
        $m = @(Get-CimInstance Win32_PhysicalMemory)
        $osm = Get-CimInstance Win32_OperatingSystem
        $p.RAM = [ordered]@{
            TotalGB    = [math]::Round(($m | Measure-Object Capacity -Sum).Sum / 1GB, 1)
            Modules    = $m.Count
            SpeedMHz   = [int](($m | Select-Object -First 1).ConfiguredClockSpeed)
            FreeGB     = [math]::Round($osm.FreePhysicalMemory / 1MB, 1)
            PageFileGB = [math]::Round(((Get-CimInstance Win32_PageFileUsage | Measure-Object AllocatedBaseSize -Sum).Sum) / 1KB, 1)
        }
    } catch { $p.Errors += "RAM: $($_.Exception.Message)" }

    # ---- GPU
    try {
        $p.GPU = @(Get-CimInstance Win32_VideoController | Where-Object Name | ForEach-Object {
            $n = $_.Name
            $v = Get-WinForgeVendorKey $_.AdapterCompatibility $n
            [ordered]@{
                Name             = $n
                Vendor           = $v
                VRAMGB           = $(if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1GB, 1) } else { $null })
                DriverVersion    = $_.DriverVersion
                DriverDate       = $(if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '' })
                MarketingVersion = $(if ($v -eq 'nvidia') { ConvertTo-WinForgeNvidiaVersion $_.DriverVersion } else { $null })
                Latest           = $null
                LatestDate       = $null
                LatestStatus     = 'não consultado'
            }
        })
    } catch { $p.Errors += "GPU: $($_.Exception.Message)" }

    # ---- Armazenamento
    try {
        $disks = @(Get-PhysicalDisk)
        # Muito driver NVMe reporta MediaType 'Unspecified'. Tratar NVMe como SSD evita concluir
        # "não é SSD, logo é HDD" numa máquina que só tem NVMe.
        $isSsdDisk = { param($d) ([string]$d.MediaType -eq 'SSD') -or ([string]$d.MediaType -eq 'Unspecified' -and [string]$d.BusType -eq 'NVMe') }
        $p.Storage = [ordered]@{
            Disks = @($disks | ForEach-Object {
                [ordered]@{
                    Name            = $_.FriendlyName
                    Media           = [string]$_.MediaType
                    MediaNormalized = $(if (& $isSsdDisk $_) { 'SSD' } else { [string]$_.MediaType })
                    Bus             = [string]$_.BusType
                    Health          = [string]$_.HealthStatus
                    SizeGB          = [math]::Round($_.Size / 1GB)
                }
            })
            HasHDD           = (@($disks | Where-Object MediaType -eq 'HDD').Count -gt 0)
            HasSSD           = (@($disks | Where-Object { & $isSsdDisk $_ }).Count -gt 0)
            SystemDriveMedia = $null
            Volumes = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
                [ordered]@{
                    Letter  = [string]$_.DriveLetter
                    FS      = $_.FileSystem
                    SizeGB  = [math]::Round($_.Size / 1GB)
                    FreePct = $(if ($_.Size) { [math]::Round($_.SizeRemaining / $_.Size * 100) } else { 0 })
                }
            })
        }
        try {
            $sysDisk = Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') | Get-Disk | Get-PhysicalDisk
            $p.Storage.SystemDriveMedia = $(if (& $isSsdDisk $sysDisk) { 'SSD' } else { [string]$sysDisk.MediaType })
        } catch { }
    } catch { $p.Errors += "Storage: $($_.Exception.Message)" }

    # ---- Rede: adaptador ativo preferindo cabo (802.3) e maior velocidade
    try {
        # LinkSpeed é string ("1 Gbps", "100 Mbps") e ordena errado; ReceiveLinkSpeed é numérico (bps)
        $a = Get-NetAdapter | Where-Object Status -eq 'Up' |
            Sort-Object -Property @{ Expression = { $_.MediaType -eq '802.3' }; Descending = $true },
                                   @{ Expression = { [uint64]$_.ReceiveLinkSpeed }; Descending = $true } |
            Select-Object -First 1
        $dns = @((Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | Select-Object -First 1).ServerAddresses)
        if (-not $a) {
            # Máquina sem nenhum adaptador ativo é um estado normal (cabo fora, Wi-Fi desligado),
            # não uma falha de coleta. Sem esta saída, Get-NetAdapterBinding -Name $null estourava
            # e o perfil registrava "Falha ao coletar" na aba e no relatório.
            $p.Network = [ordered]@{
                Adapter     = $null
                Name        = $null
                LinkSpeed   = 'sem conexão'
                IsWifi      = $false
                Dns         = $dns
                IPv6Enabled = $null
            }
        } else {
            $p.Network = [ordered]@{
                Adapter     = $a.InterfaceDescription
                Name        = $a.Name
                LinkSpeed   = [string]$a.LinkSpeed
                IsWifi      = ($a.MediaType -match '802\.11|Native 802.11|Wireless')
                Dns         = $dns
                IPv6Enabled = [bool](Get-NetAdapterBinding -Name $a.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue).Enabled
            }
        }
    } catch { $p.Errors += "Network: $($_.Exception.Message)" }

    # ---- Energia
    try {
        # powercfg pode devolver linha em branco junto: só a primeira linha com conteúdo interessa.
        # A linha tem a forma "GUID da Configuração de Energia: <guid>  (<nome>)" - o GUID e o nome
        # ficam em campos separados, porque o texto antes deles muda com o idioma do Windows.
        #
        # 'powercfg' pelo nome deixaria a escolha do binário com o PATH, e o WinForge roda elevado:
        # o caminho sai de Get-WinForgeSystemExe e a leitura passa por Invoke-WinForgeNativeCommand,
        # que ainda troca a code page para OEM - sem isso o NOME do plano ("Alto desempenho") chega
        # com acento embaralhado ao relatório. As duas funções vivem em wf-commands.ps1, inserido
        # DEPOIS deste bloco no motor gerado: a ordem de definição não importa, porque tudo já está
        # definido quando o job de perfil roda.
        $pcfg = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'powercfg.exe') -Arguments @('/getactivescheme')
        $schemeLine = [string](@([string]$pcfg.Text -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        $schemeGuid = $null
        $schemeName = $null
        if ($schemeLine -match '([0-9a-f-]{36})\s*\((.+)\)') {
            $schemeGuid = $Matches[1]
            $schemeName = $Matches[2].Trim()
        } else {
            $schemeName = ([string]($schemeLine -replace '.*:\s*', '')).Trim()
        }
        $p.Power = [ordered]@{
            ActiveScheme       = $schemeName
            ActiveSchemeGuid   = $schemeGuid
            OnBattery          = $(try { (Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1).BatteryStatus -eq 1 } catch { $false })
            HibernationEnabled = [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HibernateEnabled
        }
    } catch { $p.Errors += "Power: $($_.Exception.Message)" }

    # ---- Estado (registro/serviços)
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
        $p.State = [ordered]@{
            VBS         = $(if ($dg) { $dg.VirtualizationBasedSecurityStatus -eq 2 } else { $null })
            HAGS        = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue).HwSchMode -eq 2)
            GameMode    = ((Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue).AutoGameModeEnabled -ne 0)
            SysMain     = [string](Get-Service SysMain -ErrorAction SilentlyContinue).StartType
            WSearch     = [string](Get-Service WSearch -ErrorAction SilentlyContinue).StartType
            FastStartup = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled -ne 0)
        }
    } catch { $p.Errors += "State: $($_.Exception.Message)" }

    # ---- Servidor (só no Server; no cliente fica $null e os cartões/regras ignoram)
    $p.Server = $null
    if ($p.OS -and $p.OS.IsServer) {
        $srv = [ordered]@{ Smb1Enabled = $null; SmbSigningRequired = $null; TcpAutotuning = $null; TimeSource = $null
                           Iis = [ordered]@{ Installed = [bool]$p.Roles.IIS; PoolCount = $null; SiteCount = $null; LogDirectory = $null; LogOnOsDrive = $null; AppInitInstalled = $null; DynCompressionInstalled = $null }
                           Ad  = [ordered]@{ NtdsPath = $null; SysvolPath = $null; NtdsOnOsDrive = $null; SysvolOnOsDrive = $null } }
        try { $smb = Get-SmbServerConfiguration -ErrorAction Stop; $srv.Smb1Enabled = [bool]$smb.EnableSMB1Protocol; $srv.SmbSigningRequired = [bool]$smb.RequireSecuritySignature } catch { $p.Errors += "SMB: $($_.Exception.Message)" }
        # Get-NetTCPSetting, e não 'netsh int tcp show global': o netsh escreve UTF-8 quando a saída é
        # um cano (e OEM quando é console), então no processo sem janela que o lançador usa o texto
        # chegava embaralhado e a linha em português nunca casava com a expressão regular - o campo
        # ficava $null em toda máquina localizada, e é justamente o campo que o item
        # WPFTweaksWFSrvTcpAutotuning existe para corrigir. O cmdlet devolve objeto, existe desde o
        # Server 2012 e não depende de idioma; AutoTuningLevelLocal é o que o antigo
        # 'netsh int tcp set global autotuninglevel' escrevia.
        try {
            $nivelTcp = [string](Get-NetTCPSetting -SettingName Internet -ErrorAction Stop).AutoTuningLevelLocal
            if (-not [string]::IsNullOrWhiteSpace($nivelTcp)) { $srv.TcpAutotuning = $nivelTcp.ToLower() }
        } catch { $p.Errors += "TCP: $($_.Exception.Message)" }
        # O w32tm escreve a FALHA no stdout, não no stderr ("Ocorreu o seguinte erro: O serviço não
        # foi iniciado. (0x80070426)"), então filtrar o stderr não adianta e a mensagem de erro virava
        # a fonte de horário do relatório. Só o código de saída separa resposta de erro - e a leitura
        # passa por Invoke-WinForgeNativeCommand para a mensagem em português não chegar embaralhada
        # (ele troca a code page para OEM). O executável vai por CAMINHO COMPLETO, pelo mesmo motivo
        # do powercfg acima: '-Command' compilaria o texto 'w32tm ...' e deixaria a escolha do binário
        # com o PATH.
        try {
            $ts = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'w32tm.exe') -Arguments @('/query', '/source')
            $tsOut = @([string]$ts.Text -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $tsFirst = $(if (@($tsOut).Count) { ([string]@($tsOut)[0]).Trim() } else { '' })
            if ($ts.ExitCode -eq 0 -and $tsFirst) { $srv.TimeSource = $tsFirst }
            elseif ($tsFirst) { $p.Errors += "Horário: $tsFirst" }
            else { $p.Errors += "Horário: w32tm /query /source não respondeu (código $($ts.ExitCode))" }
        } catch { $p.Errors += "Horário: $($_.Exception.Message)" }
        if ($p.Roles.IIS) {
            try {
                Import-Module WebAdministration -ErrorAction Stop
                $srv.Iis.PoolCount = @(Get-ChildItem IIS:\AppPools -ErrorAction Stop).Count
                $sites = @(Get-ChildItem IIS:\Sites -ErrorAction Stop)
                $srv.Iis.SiteCount = $sites.Count
                $dir = [string]($sites | Select-Object -First 1).logFile.directory
                if ($dir) { $dir = [Environment]::ExpandEnvironmentVariables($dir); $srv.Iis.LogDirectory = $dir; $srv.Iis.LogOnOsDrive = ($dir -like "$($env:SystemDrive)*") }
                if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
                    $srv.Iis.AppInitInstalled = [bool](Get-WindowsFeature Web-AppInit -ErrorAction SilentlyContinue).Installed
                    $srv.Iis.DynCompressionInstalled = [bool](Get-WindowsFeature Web-Dyn-Compression -ErrorAction SilentlyContinue).Installed
                }
            } catch { $p.Errors += "IIS: $($_.Exception.Message)" }
        }
        if ($p.Roles.IsDC) {
            try {
                $ntds = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters' -ErrorAction Stop
                $srv.Ad.NtdsPath = [string]$ntds.'DSA Database file'
                $srv.Ad.NtdsOnOsDrive = ($srv.Ad.NtdsPath -like "$($env:SystemDrive)*")
                $sysvol = [string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' -ErrorAction Stop).SysVol
                $srv.Ad.SysvolPath = $sysvol
                $srv.Ad.SysvolOnOsDrive = ($sysvol -like "$($env:SystemDrive)*")
            } catch { $p.Errors += "AD: $($_.Exception.Message)" }
        }
        $p.Server = $srv
    }

    # ---- Drivers (sempre array, mesmo vazio)
    try { $p.Drivers = @(Get-WinForgeDriverInventory) } catch { $p.Errors += "Drivers: $($_.Exception.Message)"; $p.Drivers = @() }

    if (-not $SkipNetwork) {
        try { Update-WinForgeProfileDriverStatus -Profile $p } catch { $p.Errors += "DriverLookup: $($_.Exception.Message)" }
    }

    return $p
}

function Get-WinForgeSimulatedProfile {
    <#
    .SYNOPSIS
        Perfil desta máquina com uma característica forçada, para exercitar as regras sem precisar
        do hardware correspondente (notebook, máquina virtual, servidor com IIS, controlador de
        domínio, HDD, Windows 10).
    #>
    param([Parameter(Mandatory)][ValidateSet('laptop', 'vm', 'server-iis', 'server-ad', 'hdd', 'win10')][string]$Name)
    $base = Get-WinForgeSystemProfile -SkipNetwork
    # Cada área pode ter vindo $null (coleta falhou). A simulação não pode explodir por causa disso:
    # sobrescreve o que existe e ignora o resto - o SelfTest já acusa a área faltando em separado.
    switch ($Name) {
        'laptop' {
            if ($base.Machine) { $base.Machine.IsLaptop = $true }
            if ($base.Power)   { $base.Power.OnBattery = $true }
        }
        'vm' {
            if ($base.Machine) { $base.Machine.IsVirtual = $true }
            $base.GPU = @([ordered]@{ Name = 'Microsoft Basic Display'; Vendor = 'other'; VRAMGB = $null; DriverVersion = '10.0'; DriverDate = ''; MarketingVersion = $null; Latest = $null; LatestDate = $null; LatestStatus = 'n/a' })
        }
        'server-iis' {
            if ($base.OS) {
                $base.OS.IsServer = $true
                $base.OS.ProductType = 3
            }
            if ($base.Roles) { $base.Roles.IIS = $true; $base.Roles.IsDC = $false }
            $base.Server = [ordered]@{ Smb1Enabled = $true; SmbSigningRequired = $false; TcpAutotuning = 'disabled'; TimeSource = 'Local CMOS Clock'
                                       Iis = [ordered]@{ Installed = $true; PoolCount = 3; SiteCount = 2; LogDirectory = 'C:\inetpub\logs\LogFiles'; LogOnOsDrive = $true; AppInitInstalled = $false; DynCompressionInstalled = $true }
                                       Ad  = [ordered]@{ NtdsPath = $null; SysvolPath = $null; NtdsOnOsDrive = $null; SysvolOnOsDrive = $null } }
        }
        'server-ad' {
            if ($base.OS) {
                $base.OS.IsServer = $true
                $base.OS.ProductType = 2
            }
            # IIS = $false explícito: sob WINFORGE_SIMULATE_SERVER=iis,ad o perfil base já vem com o
            # papel IIS, e um "DC com IIS" não exercitaria o que esta simulação existe para provar -
            # que as recomendações de IIS não vazam para um controlador de domínio sem IIS.
            if ($base.Roles) { $base.Roles.AD = $true; $base.Roles.IsDC = $true; $base.Roles.DNS = $true; $base.Roles.IIS = $false }
            $base.Server = [ordered]@{ Smb1Enabled = $false; SmbSigningRequired = $true; TcpAutotuning = 'normal'; TimeSource = 'time.windows.com,0x9'
                                       Iis = [ordered]@{ Installed = $false; PoolCount = $null; SiteCount = $null; LogDirectory = $null; LogOnOsDrive = $null; AppInitInstalled = $null; DynCompressionInstalled = $null }
                                       Ad  = [ordered]@{ NtdsPath = 'C:\Windows\NTDS\ntds.dit'; SysvolPath = 'C:\Windows\SYSVOL\sysvol'; NtdsOnOsDrive = $true; SysvolOnOsDrive = $true } }
        }
        'hdd' {
            if ($base.Storage) {
                $base.Storage.HasHDD = $true
                $base.Storage.HasSSD = $false
                $base.Storage.SystemDriveMedia = 'HDD'
            }
        }
        'win10' {
            if ($base.OS) {
                $base.OS.IsWin11 = $false
                $base.OS.Build = 19045
            }
        }
    }
    $base.Simulated = $Name
    return $base
}

#endregion
