#region ===== WinForge - regras de recomendação =====

# Regras que traduzem o perfil do sistema (Get-WinForgeSystemProfile) em sugestões de tweaks.
# Cada regra é uma tabela com:
#   Id        - identificador curto, único, usado no log e no Diagnóstico.
#   When      - EXPRESSÃO PowerShell em texto, avaliada com $p = perfil. Verdadeiro dispara a regra.
#   Recommend - chaves de tweak a sugerir. Só pode conter itens Seguro (o -SelfTest reprova o resto).
#   Avoid     - chaves a desaconselhar. 'Avoid' vence 'Recommend' de qualquer outra regra.
#   Reason    - texto em pt-BR mostrado ao usuário. A primeira regra que cita uma chave dá o motivo.
#   Info      - opcional; também é EXPRESSÃO em texto avaliada com $p, mas devolve a FRASE a exibir
#               (por isso o texto fixo aparece entre aspas dentro da expressão). Vai para
#               $sync.RuleInfos e é só informativo: não marca nem desmarca nada.
# Nada aqui altera o sistema: as regras só sugerem. Quem aplica é o usuário, pelos botões de sempre.

$sync.WinForgeRules = @(

    @{  Id        = 'base-privacy'
        When      = '$true'
        Recommend = @('WPFTweaksActivity', 'WPFTweaksConsumerFeatures', 'WPFTweaksTelemetry', 'WPFTweaksDeliveryOptimization',
                      'WPFTweaksWBAds', 'WPFTweaksWBSearchSuggestions', 'WPFTweaksWBServicesSafe', 'WPFTweaksRestorePoint')
        Avoid     = @()
        Reason    = 'Base segura para qualquer PC: privacidade, sem anúncios, serviços dispensáveis e ponto de restauração.'
    }

    @{  Id        = 'ssd-only'
        When      = '$p.Storage.HasSSD -and -not $p.Storage.HasHDD'
        Recommend = @('WPFTweaksWBNtfsLastAccess')
        Avoid     = @()
        Reason    = 'Só SSD: menos escrita de metadados.'
    }

    @{  Id        = 'hdd-present'
        When      = '$p.Storage.HasHDD'
        Recommend = @()
        Avoid     = @('WPFTweaksWBPrefetch', 'WPFTweaksWBIndexing')
        Reason    = 'Há HDD: Prefetch/Superfetch e indexação ajudam discos mecânicos.'
    }

    @{  Id        = 'laptop'
        When      = '$p.Machine.IsLaptop'
        Recommend = @()
        Avoid     = @('WPFTweaksWBPowerSettings', 'WPFTweaksHiber', 'WPFTweaksWBTimerBcdedit')
        Reason    = 'Notebook: CPU a 100% e sem hibernação gastam bateria e esquentam.'
    }

    @{  Id        = 'desktop'
        When      = '-not $p.Machine.IsLaptop -and -not $p.Machine.IsVirtual'
        Recommend = @('WPFTweaksHiber', 'WPFTweaksWBPowerSettings')
        Avoid     = @()
        Reason    = 'Desktop na tomada: hibernação inútil; energia sem suspensão USB/throttle reduz latência.'
    }

    @{  Id        = 'low-ram'
        When      = '$p.RAM.TotalGB -le 8'
        Recommend = @('WPFTweaksWBServicesSafe', 'WPFTweaksWBAds', 'WPFTweaksDisplay')
        Avoid     = @('WPFTweaksWBPrefetch')
        Reason    = '8 GB ou menos: cada serviço conta; Superfetch ajuda.'
    }

    @{  Id        = 'vm'
        When      = '$p.Machine.IsVirtual'
        Recommend = @()
        Avoid     = @('WPFTweaksWBTimerBcdedit', 'WPFToggleWBHAGS', 'WPFTweaksWBVBS', 'WPFTweaksWBHypervisorOff', 'WPFTweaksWBPowerSettings')
        Reason    = 'Máquina virtual: timer, HAGS, VBS e energia são controlados pelo host.'
    }

    @{  Id        = 'nvidia'
        When      = '@($p.GPU | Where-Object { $_.Vendor -eq "nvidia" }).Count -gt 0'
        Recommend = @('WPFTweaksWBNvidiaTelemetry', 'WPFTweaksWBGameDVR')
        Avoid     = @()
        Reason    = 'GPU NVIDIA: telemetria da NVIDIA e Game DVR gastam recursos.'
    }

    @{  Id        = 'amd'
        When      = '@($p.GPU | Where-Object { $_.Vendor -eq "amd" }).Count -gt 0'
        Recommend = @('WPFTweaksWBAmdTelemetry', 'WPFTweaksWBGameDVR')
        Avoid     = @()
        Reason    = 'GPU AMD: telemetria da AMD e Game DVR gastam recursos.'
    }

    @{  Id        = 'dedicated-gpu-desktop'
        When      = '(@($p.GPU | Where-Object { $_.Vendor -in "nvidia", "amd" }).Count -gt 0) -and -not $p.Machine.IsLaptop'
        Recommend = @('WPFTweaksWBMMCSSGames', 'WPFTweaksWBWin32PrioritySeparation')
        Avoid     = @()
        Reason    = 'PC de jogo: prioridade de mídia/primeiro plano.'
    }

    @{  Id        = 'win11'
        When      = '$p.OS.IsWin11'
        Recommend = @('WPFTweaksEndTaskOnTaskbar')
        Avoid     = @()
        Reason    = 'Windows 11: finalizar tarefa pela barra.'
    }

    @{  Id        = 'server'
        When      = '$p.OS.IsServer'
        Recommend = @()
        Avoid     = @('WPFTweaksWBGameDVR', 'WPFTweaksWBXboxServices', 'WPFTweaksWBMMCSSGames',
                      'WPFTweaksWBWin32PrioritySeparation', 'WPFTweaksWidget', 'WPFTweaksWBAds')
        Reason    = 'Servidor: itens de consumidor/jogos não se aplicam.'
    }

    # ------------------------------------------------------------------ só informação (não marcam nada)

    @{  Id        = 'vbs-on-gaming'
        When      = '$p.State.VBS -eq $true -and (@($p.GPU | Where-Object { $_.Vendor -in "nvidia", "amd" }).Count -gt 0) -and -not $p.Machine.IsVirtual'
        Recommend = @()
        Avoid     = @()
        Reason    = 'VBS ativo em PC com GPU dedicada.'
        Info      = '"VBS/Isolamento de Núcleo ativo: custa 5-15% de FPS em alguns jogos; desligar reduz a segurança (item em Avançado (CUIDADO))."'
    }

    @{  Id        = 'nvidia-driver-behind'
        When      = '@($p.GPU | Where-Object { $_.Vendor -eq "nvidia" -and $_.LatestStatus -eq "atualizar" }).Count -gt 0'
        Recommend = @()
        Avoid     = @()
        Reason    = 'Driver NVIDIA atrás do catálogo do fabricante.'
        Info      = '$g = @($p.GPU | Where-Object { $_.Vendor -eq "nvidia" -and $_.LatestStatus -eq "atualizar" })[0]; "Driver NVIDIA desatualizado: instalado $($g.MarketingVersion), disponível $($g.Latest)."'
    }

    # Só vídeo, rede, áudio e Bluetooth: chipset, USB e controladora de disco vêm com INF de anos
    # de fábrica e continuam corretos - contá-los aqui enchia a aba de aviso sem informação.
    @{  Id        = 'old-drivers'
        When      = '@($p.Drivers | Where-Object { $_.Old -and $_.Class -in "DISPLAY", "NET", "MEDIA", "BLUETOOTH" }).Count -gt 0'
        Recommend = @()
        Avoid     = @()
        Reason    = 'Drivers antigos no inventário.'
        Info      = '"{0} driver(es) de vídeo, rede, áudio ou Bluetooth com mais de 180 dias - veja a tabela." -f @($p.Drivers | Where-Object { $_.Old -and $_.Class -in "DISPLAY", "NET", "MEDIA", "BLUETOOTH" }).Count'
    }
)

#endregion
