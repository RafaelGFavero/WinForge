#region ===== WinForge - auditoria de risco =====

# Classificação de risco de cada tweak/toggle (fonte única; docs/auditoria.md é gerado daqui).
#   Seguro   - reversível, sem custo de segurança ou estabilidade; pode aparecer em preset.
#   Cuidado  - tem um custo real; vive só na categoria CUIDADO, com o custo no início da descrição,
#              e nunca entra em preset.
#   Removido - saldo negativo; a entrada e qualquer referência em preset somem.
# Chaves 'WPFTweaksWBGame*' (prioridade de CPU por jogo, via IFEO, reversível) são Seguro
# automaticamente e não precisam de linha aqui. Entradas de Type Button/Combobox são ações,
# não tweaks, e ficam fora da classificação.
# 'Override' (opcional) sobrescreve propriedades da entrada antes da classificação valer.

$sync.WinForgeCautionCategory = 'zz__Avançado (CUIDADO)'

$sync.WinForgeAudit = @{

    # ---------------------------------------------------------------- base (Essential / Advanced)
    'WPFTweaksActivity'                          = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksHiber'                             = @{ Class = 'Seguro';  Reason = '' }   # regras de hardware tratam notebook no Plano 3
    'WPFTweaksWidget'                            = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksRevertStartMenu'                   = @{ Class = 'Cuidado'; Reason = 'usa override interno de recurso (FeatureManagement) que a Microsoft pode remover; pode não ter efeito ou reverter sozinho' }
    'WPFTweaksDisableStoreSearch'                = @{ Class = 'Cuidado'; Reason = 'nega permissão ao banco da Microsoft Store (store.db); pode quebrar a busca e atualizações da Store até desfazer' }
    'WPFTweaksLocation'                          = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksServices'                          = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksConsumerFeatures'                  = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksTelemetry'                         = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksDeliveryOptimization'              = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksDisableBitLocker'                  = @{ Class = 'Cuidado'; Reason = 'descriptografa a unidade do sistema: perde a proteção contra roubo/acesso físico e demora muito em discos grandes'
                                                      Override = @{ category = 'zz__Avançado (CUIDADO)' } }
    'WPFTweaksRestorePoint'                      = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksEndTaskOnTaskbar'                  = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWPBT'                              = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksPreventDeviceMetadataFromNetwork'  = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksDiskCleanup'                       = @{ Class = 'Seguro';  Reason = ''
                                                      Override = @{
                                                          InvokeScript = @("cleanmgr.exe /d C: /VERYLOWDISK", "Dism.exe /online /Cleanup-Image /StartComponentCleanup")
                                                          Description  = "Executa a Limpeza de Disco e o StartComponentCleanup do DISM (sem /ResetBase, para manter a possibilidade de desinstalar atualizações)."
                                                      } }
    'WPFTweaksDeleteTempFiles'                   = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksDisableExplorerAutoDiscovery'      = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksBraveDebloat'                      = @{ Class = 'Seguro';  Reason = '' }   # só afeta o Brave, por política
    'WPFTweaksDisableWarningForUnsignedRdp'      = @{ Class = 'Cuidado'; Reason = 'remove o aviso de segurança ao abrir arquivos .rdp não assinados' }
    'WPFTweaksEdgeDebloat'                       = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksRemoveEdge'                        = @{ Class = 'Cuidado'; Reason = 'remove o navegador Edge; apps que dependem dele (Widgets, alguns instaladores, PDF padrão) deixam de funcionar; o Windows pode reinstalá-lo em atualizações' }
    'WPFTweaksUTC'                               = @{ Class = 'Cuidado'; Reason = 'só faz sentido em dual boot com Linux; em PC só Windows o relógio fica errado até desfazer' }
    'WPFTweaksRemoveOneDrive'                    = @{ Class = 'Cuidado'; Reason = 'desinstala o OneDrive e move arquivos para o perfil local; arquivos só na nuvem NÃO são baixados antes' }
    'WPFTweaksRemoveHomeAndGallery'              = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksDisplay'                           = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksReservedStorage'                   = @{ Class = 'Cuidado'; Reason = 'sem o armazenamento reservado, atualizações do Windows podem falhar quando o disco estiver quase cheio' }
    'WPFTweaksStorage'                           = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWindowsAI'                         = @{ Class = 'Cuidado'; Reason = 'remove o Copilot/Recall e componentes de IA (pacote CoreAI) do sistema; reinstalar exige atualização do Windows' }
    'WPFTweaksRazerBlock'                        = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksDisableNotifications'              = @{ Class = 'Cuidado'; Reason = 'desliga TODAS as notificações (toasts) e a Central de Ações, incluindo alertas de antivírus e de bateria' }
    'WPFTweaksBlockAdobeNet'                     = @{ Class = 'Cuidado'; Reason = 'edita o arquivo hosts com uma lista baixada da internet; quebra login, licenciamento e atualização de produtos Adobe' }
    'WPFTweaksRightClickMenu'                    = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksIPv46'                             = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksTeredo'                            = @{ Class = 'Cuidado'; Reason = 'o Teredo é usado pelo Xbox Live (chat de festa, multiplayer de jogos Xbox no PC); desativar pode quebrar esses recursos' }
    'WPFTweaksDisableIPv6'                       = @{ Class = 'Cuidado'; Reason = 'desativa o IPv6 em todos os adaptadores; redes, VPNs e provedores que dependem de IPv6 param de funcionar' }
    'WPFTweaksDisableBGapps'                     = @{ Class = 'Cuidado'; Reason = 'impede TODOS os apps da Store de rodar em segundo plano: e-mail, calendário e mensagens param de sincronizar/notificar' }
    'WPFTweaksDisableLockscreen'                 = @{ Class = 'Seguro';  Reason = '' }

    # ---------------------------------------------------------------- toggles da base
    'WPFToggleDetailedBSoD'                      = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleBatteryPercentage'                 = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleDarkMode'                          = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleShowExt'                           = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleHiddenFiles'                       = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleVerboseLogon'                      = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleNewOutlook'                        = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleScrollbars'                        = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleMouseAcceleration'                 = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleNumLock'                           = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleWindowSnapping'                    = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleStandbyFix'                        = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleS3Sleep'                           = @{ Class = 'Cuidado'; Reason = 'força suspensão S3 em vez de Modern Standby; em notebooks modernos pode impedir a suspensão ou o despertar correto' }
    'WPFToggleHideSettingsHome'                  = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleBingSearch'                        = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleLoginBlur'                         = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleStartMenuRecommendations'          = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleStickyKeys'                        = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleTaskbarAlignment'                  = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleTaskbarSearch'                     = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleTaskView'                          = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleGameMode'                          = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleLongPaths'                         = @{ Class = 'Seguro';  Reason = '' }

    # ---------------------------------------------------------------- WinForge (Windows Boost - Essential)
    'WPFTweaksWBPowerSettings'                   = @{ Class = 'Seguro';  Reason = '' }   # regras de notebook no Plano 3
    'WPFTweaksWBNtfsLastAccess'                  = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBServicesSafe'                    = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBAds'                             = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBCortana'                         = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBSearchSuggestions'               = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBPrefetch'                        = @{ Class = 'Cuidado'; Reason = 'em HDD deixa o sistema mais lento; só faz sentido em SSD' }
    'WPFTweaksWBSmartScreen'                     = @{ Class = 'Removido'; Reason = 'reduz a segurança sem ganho de desempenho (SmartScreen e marca de origem de downloads)' }
    'WPFTweaksWBIndexing'                        = @{ Class = 'Cuidado'; Reason = 'a pesquisa do menu Iniciar, do Explorador e do Outlook fica lenta ou incompleta' }
    'WPFTweaksWBServicesAggressive'              = @{ Class = 'Removido'; Reason = 'pacote que desliga impressão, Bluetooth, RDP, Windows Hello e teclado touch de uma vez; substituído por 5 itens separados' }
    'WPFTweaksWBVBS'                             = @{ Class = 'Cuidado'; Reason = 'reduz a segurança contra malware de kernel (VBS/HVCI); ganho de FPS em alguns jogos; exige reinício' }
    'WPFTweaksWBHypervisorOff'                   = @{ Class = 'Cuidado'; Reason = 'quebra WSL2, Hyper-V, Windows Sandbox, WSA e emuladores baseados em Hyper-V; exige reinício' }
    'WPFToggleWBTransparency'                    = @{ Class = 'Seguro';  Reason = '' }
    'WPFToggleWBHAGS'                            = @{ Class = 'Seguro';  Reason = '' }

    # ---------------------------------------------------------------- aba Jogos (não-IFEO)
    'WPFTweaksWBGameDVR'                         = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBMMCSSGames'                      = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBWin32PrioritySeparation'         = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBXboxServices'                    = @{ Class = 'Cuidado'; Reason = 'quebra login no app Xbox, Game Pass, Minecraft Bedrock e jogos com conta Xbox' }
    'WPFTweaksWBTimerBcdedit'                    = @{ Class = 'Cuidado'; Reason = 'altera timer do kernel via bcdedit; pode causar instabilidade, stutter ou consumo maior; exige reinício' }
    'WPFTweaksWBNvidiaTelemetry'                 = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBNvidiaShadowPlay'                = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBAmdTelemetry'                    = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBAmdULPS'                         = @{ Class = 'Cuidado'; Reason = 'altera o driver AMD (ULPS) em todas as instâncias; em notebooks pode aumentar consumo; exige reinício' }
    'WPFTweaksWBAmdShaderCache'                  = @{ Class = 'Seguro';  Reason = '' }
    'WPFTweaksWBAmdCrashDefender'                = @{ Class = 'Seguro';  Reason = '' }

    # ---------------------------------------------------------------- serviços separados (criados em tarefa posterior)
    'WPFTweaksWBSvcSpooler'                      = @{ Class = 'Cuidado'; Reason = 'desliga o Spooler: impressão e impressoras PDF param de funcionar' }
    'WPFTweaksWBSvcBluetooth'                    = @{ Class = 'Cuidado'; Reason = 'desliga o Bluetooth (bthserv): mouses, teclados e fones Bluetooth param' }
    'WPFTweaksWBSvcRdp'                          = @{ Class = 'Cuidado'; Reason = 'desliga a Área de Trabalho Remota (TermService): ninguém consegue acessar este PC por RDP' }
    'WPFTweaksWBSvcHello'                        = @{ Class = 'Cuidado'; Reason = 'desliga a biometria (WbioSrvc): Windows Hello por rosto/digital deixa de funcionar' }
    'WPFTweaksWBSvcTouchKeyboard'                = @{ Class = 'Cuidado'; Reason = 'desliga o teclado virtual/caneta (TabletInputService): tablets e 2-em-1 perdem o teclado na tela' }
}

#endregion
