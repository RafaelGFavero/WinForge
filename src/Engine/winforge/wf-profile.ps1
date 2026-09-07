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
        'Old' marca driver com mais de 180 dias. 'Status', 'Latest' e 'Url' são preenchidos depois
        pela consulta online (Update-WinForgeProfileDriverStatus).
    #>
    $classes = 'DISPLAY', 'NET', 'MEDIA', 'HDC', 'SCSIADAPTER', 'SYSTEM', 'USB', 'BLUETOOTH'
    $cutoff = (Get-Date).AddDays(-180)
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
        Where-Object { $_.DeviceClass -in $classes -and $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' -and $_.DeviceName } |
        Sort-Object DeviceClass, DeviceName -Unique |
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
                Old      = $(if ($_.DriverDate) { $_.DriverDate -lt $cutoff } else { $false })
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

    $p = [ordered]@{ GeneratedAt = (Get-Date).ToString('s'); Errors = @() }

    # ---- SO
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $p.OS = [ordered]@{
            Caption        = $os.Caption
            Build          = [int][Environment]::OSVersion.Version.Build
            DisplayVersion = [string]$cv.DisplayVersion
            IsWin11        = ([Environment]::OSVersion.Version.Build -ge 22000)
            IsServer       = ($os.ProductType -ne 1)
            ProductType    = [int]$os.ProductType
            InstallDate    = $os.InstallDate.ToString('yyyy-MM-dd')
            UptimeHours    = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
            Architecture   = $os.OSArchitecture
        }
    } catch { $p.Errors += "OS: $($_.Exception.Message)" }

    # ---- Papéis (só no Server: Get-WindowsFeature não existe no cliente)
    $p.Roles = [ordered]@{ IIS = $false; AD = $false; HyperV = $false; DNS = $false; DHCP = $false; FileServer = $false; RDS = $false }
    if ($p.OS.IsServer -and (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) {
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
        $cs = Get-CimInstance Win32_ComputerSystem
        $enc = Get-CimInstance Win32_SystemEnclosure
        $chassis = @($enc.ChassisTypes)
        $laptopTypes = 8, 9, 10, 11, 12, 14, 30, 31, 32
        # HypervisorPresent NÃO serve para detectar VM: ele fica ligado em máquina física com
        # Hyper-V, WSL2, Sandbox, Credential Guard ou VBS. A virtualização é decidida pela
        # assinatura do fabricante/modelo; HypervisorPresent vai junto, como campo separado.
        $vmSignature = 'VMware|VirtualBox|innotek|KVM|QEMU|Virtual Machine|Hyper-V|Xen|Parallels|Bochs|BHYVE'
        $p.Machine = [ordered]@{
            Manufacturer      = $cs.Manufacturer
            Model             = $cs.Model
            IsVirtual         = ("$($cs.Manufacturer) $($cs.Model)" -match $vmSignature)
            HypervisorPresent = [bool]$cs.HypervisorPresent
            IsLaptop          = (@($chassis | Where-Object { $_ -in $laptopTypes }).Count -gt 0) -or [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
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
            Hybrid                = ($vendor -eq 'intel' -and $c.Name -match '1[2-9]\d{3}|Core Ultra')
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
        $p.Network = [ordered]@{
            Adapter     = $a.InterfaceDescription
            Name        = $a.Name
            LinkSpeed   = [string]$a.LinkSpeed
            IsWifi      = ($a.MediaType -match '802\.11|Native 802.11|Wireless')
            Dns         = $dns
            IPv6Enabled = [bool](Get-NetAdapterBinding -Name $a.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue).Enabled
        }
    } catch { $p.Errors += "Network: $($_.Exception.Message)" }

    # ---- Energia
    try {
        # powercfg pode devolver linha em branco junto: só a primeira linha com conteúdo interessa.
        # A linha tem a forma "GUID da Configuração de Energia: <guid>  (<nome>)" - o GUID e o nome
        # ficam em campos separados, porque o texto antes deles muda com o idioma do Windows.
        $schemeLine = [string](@(powercfg /getactivescheme) | Where-Object { $_ } | Select-Object -First 1)
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
        do hardware correspondente (notebook, máquina virtual, servidor com IIS, HDD, Windows 10).
    #>
    param([Parameter(Mandatory)][ValidateSet('laptop', 'vm', 'server-iis', 'hdd', 'win10')][string]$Name)
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
            if ($base.Roles) { $base.Roles.IIS = $true }
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
