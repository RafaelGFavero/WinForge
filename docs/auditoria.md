# Auditoria de risco

> Arquivo gerado por `src/Engine/build.ps1` a partir de `src/Engine/config/wf-audit.ps1`.
> Não editar à mão: qualquer alteração é sobrescrita no próximo build.

Todo tweak e toggle do WinForge tem uma classe de risco. A classe não é só documentação — o motor
a aplica ao carregar as configurações:

- **Seguro** — reversível, sem custo de segurança ou estabilidade; pode aparecer em preset.
- **Cuidado** — tem um custo real; vive só na categoria "Avançado (CUIDADO)", com o custo no início
  da descrição, e nunca entra em preset.
- **Removido** — saldo negativo; a entrada e qualquer referência a ela em preset somem.

Total: **136 Seguro** · **29 Cuidado** · **2 Removido**.

## Seguro (136)

As chaves `WPFTweaksWBGame<Jogo>` (68 entradas, contadas a partir da lista de jogos) são a
prioridade de CPU por jogo (IFEO): uma chave de registro por executável, removida ao desfazer.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFToggleBatteryPercentage` | System Tray Battery Percentage | — |
| `WPFToggleBingSearch` | Start Menu Bing Search | — |
| `WPFToggleDarkMode` | Dark Theme for Windows | — |
| `WPFToggleDetailedBSoD` | BSoD Verbose Mode | — |
| `WPFToggleGameMode` | Game Mode | — |
| `WPFToggleHiddenFiles` | File Explorer Hidden Files | — |
| `WPFToggleHideSettingsHome` | Settings Home Page | — |
| `WPFToggleLoginBlur` | Logon Screen Acrylic Blur | — |
| `WPFToggleLongPaths` | Enable Long Paths | — |
| `WPFToggleMouseAcceleration` | Mouse Acceleration | — |
| `WPFToggleNewOutlook` | Microsoft Outlook New Version | — |
| `WPFToggleNumLock` | Num Lock on Startup | — |
| `WPFToggleScrollbars` | Scrollbars Always Visible | — |
| `WPFToggleShowExt` | File Explorer File Extensions | — |
| `WPFToggleStandbyFix` | S0 Sleep Network Connectivity | — |
| `WPFToggleStartMenuRecommendations` | Start Menu Recommendations | — |
| `WPFToggleStickyKeys` | Sticky Keys | — |
| `WPFToggleTaskView` | Taskbar Task View Icon | — |
| `WPFToggleTaskbarAlignment` | Taskbar Centered Icons | — |
| `WPFToggleTaskbarSearch` | Taskbar Search Icon | — |
| `WPFToggleVerboseLogon` | Logon Verbose Mode | — |
| `WPFToggleWBHAGS` | HAGS - Agendamento de GPU acelerado por hardware | — |
| `WPFToggleWBTransparency` | Transparência do Windows (efeitos de vidro) | — |
| `WPFToggleWindowSnapping` | Window Snapping | — |
| `WPFTweaksActivity` | Activity History - Disable | — |
| `WPFTweaksBraveDebloat` | Brave Browser - Debloat | — |
| `WPFTweaksConsumerFeatures` | ConsumerFeatures - Disable | — |
| `WPFTweaksDeleteTempFiles` | Temporary Files - Remove | — |
| `WPFTweaksDeliveryOptimization` | Delivery Optimization - Disable | — |
| `WPFTweaksDisableExplorerAutoDiscovery` | File Explorer Automatic Folder Discovery - Disable | — |
| `WPFTweaksDisableLockscreen` | Lock Screen - Disable | — |
| `WPFTweaksDiskCleanup` | Disk Cleanup - Run | — |
| `WPFTweaksDisplay` | Visual Effects - Set to Best Performance | — |
| `WPFTweaksEdgeDebloat` | Microsoft Edge - Debloat | — |
| `WPFTweaksEndTaskOnTaskbar` | End Task With Right Click - Enable | — |
| `WPFTweaksHiber` | Hibernation - Disable | — |
| `WPFTweaksIPv46` | IPv6 - Set IPv4 as Preferred | — |
| `WPFTweaksLocation` | Location Tracking - Disable | — |
| `WPFTweaksPreventDeviceMetadataFromNetwork` | Prevent Device Companion Apps | — |
| `WPFTweaksRazerBlock` | Razer Software Auto-Install - Disable | — |
| `WPFTweaksRemoveHomeAndGallery` | File Explorer Home and Gallery - Disable | — |
| `WPFTweaksRestorePoint` | Restore Point - Create | — |
| `WPFTweaksRightClickMenu` | Right-Click Menu Previous Layout - Enable | — |
| `WPFTweaksServices` | Services - Set to Manual | — |
| `WPFTweaksStorage` | Storage Sense - Disable | — |
| `WPFTweaksTelemetry` | Telemetry - Disable | — |
| `WPFTweaksWBAds` | Anúncios e sugestões do Windows - Desativar | — |
| `WPFTweaksWBAmdCrashDefender` | AMD - Desativar serviço Crash Defender | — |
| `WPFTweaksWBAmdShaderCache` | AMD - Forçar Shader Cache sempre ativo | — |
| `WPFTweaksWBAmdTelemetry` | AMD - Desativar conteúdo web e telemetria do Adrenalin | — |
| `WPFTweaksWBCortana` | Cortana - Desativar | — |
| `WPFTweaksWBGameApexLegends` | Apex Legends | — |
| `WPFTweaksWBGameArenaBreakout` | Arena Breakout | — |
| `WPFTweaksWBGameBattlefield2042` | Battlefield 2042 | — |
| `WPFTweaksWBGameBattlefield6` | Battlefield 6 | — |
| `WPFTweaksWBGameBattlefieldOld` | Battlefield 3 / 4 / Hardline / 1 / V | — |
| `WPFTweaksWBGameBloodStrike` | Blood Strike | — |
| `WPFTweaksWBGameCODBlackOps` | Call of Duty: Black Ops (3, 4, Cold War, 6) | — |
| `WPFTweaksWBGameCS2` | Counter-Strike 2 | — |
| `WPFTweaksWBGameChivalry2` | Chivalry 2 | — |
| `WPFTweaksWBGameChooChoo` | Choo-Choo Charles | — |
| `WPFTweaksWBGameCrossfire` | Crossfire | — |
| `WPFTweaksWBGameCultOfTheLamb` | Cult of the Lamb | — |
| `WPFTweaksWBGameCuphead` | Cuphead | — |
| `WPFTweaksWBGameCyberpunk` | Cyberpunk 2077 | — |
| `WPFTweaksWBGameDVR` | Game DVR / captura da Game Bar - Desativar | — |
| `WPFTweaksWBGameDayZ` | DayZ | — |
| `WPFTweaksWBGameDaysGone` | Days Gone | — |
| `WPFTweaksWBGameDeadByDaylight` | Dead by Daylight | — |
| `WPFTweaksWBGameDeadlock` | Deadlock | — |
| `WPFTweaksWBGameDeathStranding` | Death Stranding 1 e 2 | — |
| `WPFTweaksWBGameEAFC26` | EA Sports FC 26 | — |
| `WPFTweaksWBGameETS` | Euro Truck Simulator 1 e 2 | — |
| `WPFTweaksWBGameEscapeFromTarkov` | Escape from Tarkov | — |
| `WPFTweaksWBGameFFXIV` | Final Fantasy XIV | — |
| `WPFTweaksWBGameFS22` | Farming Simulator 22 | — |
| `WPFTweaksWBGameFS25` | Farming Simulator 25 | — |
| `WPFTweaksWBGameFiveM` | FiveM | — |
| `WPFTweaksWBGameFortnite` | Fortnite | — |
| `WPFTweaksWBGameFreeFire` | Free Fire (BlueStacks) | — |
| `WPFTweaksWBGameGTAV` | GTA V (Legacy e Enhanced) | — |
| `WPFTweaksWBGameGenshin` | Genshin Impact | — |
| `WPFTweaksWBGameGhostOfTsushima` | Ghost of Tsushima | — |
| `WPFTweaksWBGameGodOfWar` | God of War (2018) e Ragnarök | — |
| `WPFTweaksWBGameHellLetLoose` | Hell Let Loose | — |
| `WPFTweaksWBGameHollowKnight` | Hollow Knight e Silksong | — |
| `WPFTweaksWBGameLeagueOfLegends` | League of Legends | — |
| `WPFTweaksWBGameLeft4Dead` | Left 4 Dead 1 e 2 | — |
| `WPFTweaksWBGameMTA` | Multi Theft Auto (GTA SA) | — |
| `WPFTweaksWBGameMarvelRivals` | Marvel Rivals | — |
| `WPFTweaksWBGameMecchaChameleon` | Meccha Chameleon | — |
| `WPFTweaksWBGameMinecraft` | Minecraft (Java e Bedrock) - afeta todo app Java | — |
| `WPFTweaksWBGameMySummerCar` | My Summer Car | — |
| `WPFTweaksWBGamePES` | PES 2017-2020 e eFootball | — |
| `WPFTweaksWBGamePUBG` | PUBG: Battlegrounds | — |
| `WPFTweaksWBGamePalworld` | Palworld | — |
| `WPFTweaksWBGamePointBlank` | Point Blank | — |
| `WPFTweaksWBGamePoppyPlaytime` | Poppy Playtime (todos) | — |
| `WPFTweaksWBGameR6Siege` | Rainbow Six Siege | — |
| `WPFTweaksWBGameRDR2` | Red Dead Redemption 2 | — |
| `WPFTweaksWBGameRE2` | Resident Evil 2 Remake | — |
| `WPFTweaksWBGameRE4` | Resident Evil 4 Remake | — |
| `WPFTweaksWBGameRERequiem` | Resident Evil Requiem | — |
| `WPFTweaksWBGameREVillage` | Resident Evil Village | — |
| `WPFTweaksWBGameRematch` | Rematch | — |
| `WPFTweaksWBGameRoblox` | Roblox | — |
| `WPFTweaksWBGameRocketLeague` | Rocket League | — |
| `WPFTweaksWBGameRust` | Rust | — |
| `WPFTweaksWBGameSkyrim` | Skyrim (SE/AE e clássico) | — |
| `WPFTweaksWBGameSnowRunner` | SnowRunner | — |
| `WPFTweaksWBGameStreetFighter6` | Street Fighter 6 | — |
| `WPFTweaksWBGameSubnautica` | Subnautica e Below Zero | — |
| `WPFTweaksWBGameTerraria` | Terraria | — |
| `WPFTweaksWBGameTheIsle` | The Isle | — |
| `WPFTweaksWBGameTheLastOfUs` | The Last of Us Part I e II | — |
| `WPFTweaksWBGameUltrakill` | ULTRAKILL | — |
| `WPFTweaksWBGameValorant` | Valorant | — |
| `WPFTweaksWBGameWarface` | Warface | — |
| `WPFTweaksWBGameWarframe` | Warframe | — |
| `WPFTweaksWBGameWarzone` | Call of Duty: Warzone / MW (cod.exe) | — |
| `WPFTweaksWBMMCSSGames` | Prioridade das tarefas de jogos (MMCSS) - Alta | — |
| `WPFTweaksWBNtfsLastAccess` | NTFS - Não gravar 'último acesso' (abrir pastas/arquivos mais rápido) | — |
| `WPFTweaksWBNvidiaShadowPlay` | NVIDIA - Desativar ShadowPlay (overlay e gravação) | — |
| `WPFTweaksWBNvidiaTelemetry` | NVIDIA - Desativar telemetria | — |
| `WPFTweaksWBPowerSettings` | Energia - Sem suspensão USB, sem throttle e CPU em 100% na tomada | — |
| `WPFTweaksWBSearchSuggestions` | Pesquisa - Sem histórico, sem sugestões da web e sem conteúdo da nuvem | — |
| `WPFTweaksWBServicesSafe` | Serviços dispensáveis - Desativar (seleção segura) | — |
| `WPFTweaksWBWin32PrioritySeparation` | Prioridade do programa em primeiro plano (Win32PrioritySeparation = 0x26) | — |
| `WPFTweaksWFSrvHighPerf` | Plano de energia Alto desempenho | — |
| `WPFTweaksWFSrvNoServerManager` | Não abrir o Gerenciador do Servidor no logon | — |
| `WPFTweaksWFSrvRdpNla` | RDP: exigir Autenticação no Nível da Rede e tempo limite de sessão ociosa (30 min) | — |
| `WPFTweaksWFSrvShutdownTracker` | Desativar o Rastreador de Eventos de Desligamento | — |
| `WPFTweaksWFSrvSmb1Off` | Desativar o SMB1 no servidor | — |
| `WPFTweaksWFSrvTcpAutotuning` | TCP: nível de ajuste automático 'normal' | — |
| `WPFTweaksWPBT` | Windows Platform Binary Table (WPBT) - Disable | — |
| `WPFTweaksWidget` | Widgets - Remove | — |

## Cuidado (29)

O motivo abaixo é o mesmo texto que aparece como `CUIDADO: ...` no início da descrição do item
na interface.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFToggleS3Sleep` | S3 Sleep | força suspensão S3 em vez de Modern Standby; em notebooks modernos pode impedir a suspensão ou o despertar correto |
| `WPFTweaksBlockAdobeNet` | Adobe URL Block List - Enable | edita o arquivo hosts com uma lista baixada da internet; quebra login, licenciamento e atualização de produtos Adobe |
| `WPFTweaksDisableBGapps` | Background Apps - Disable | impede TODOS os apps da Store de rodar em segundo plano: e-mail, calendário e mensagens param de sincronizar/notificar |
| `WPFTweaksDisableBitLocker` | BitLocker - Disable | descriptografa a unidade do sistema: perde a proteção contra roubo/acesso físico e demora muito em discos grandes |
| `WPFTweaksDisableIPv6` | IPv6 - Disable | desativa o IPv6 em todos os adaptadores; redes, VPNs e provedores que dependem de IPv6 param de funcionar |
| `WPFTweaksDisableNotifications` | System Tray Notifications & Calendar - Disable | desliga TODAS as notificações (toasts) e a Central de Ações, incluindo alertas de antivírus e de bateria |
| `WPFTweaksDisableStoreSearch` | Microsoft Store Recommended Search Results - Disable | nega permissão ao banco da Microsoft Store (store.db); pode quebrar a busca e atualizações da Store até desfazer |
| `WPFTweaksDisableWarningForUnsignedRdp` | RDP Unsigned File Warnings - Disable | remove o aviso de segurança ao abrir arquivos .rdp não assinados |
| `WPFTweaksRemoveEdge` | Microsoft Edge - Remove | remove o navegador Edge; apps que dependem dele (Widgets, alguns instaladores, PDF padrão) deixam de funcionar; o Windows pode reinstalá-lo em atualizações |
| `WPFTweaksRemoveOneDrive` | Microsoft OneDrive - Remove | desinstala o OneDrive e move arquivos para o perfil local; arquivos só na nuvem NÃO são baixados antes |
| `WPFTweaksReservedStorage` | Disable Reserved Storage | sem o armazenamento reservado, atualizações do Windows podem falhar quando o disco estiver quase cheio |
| `WPFTweaksRevertStartMenu` | Start Menu Previous Layout - Enable | usa override interno de recurso (FeatureManagement) que a Microsoft pode remover; pode não ter efeito ou reverter sozinho |
| `WPFTweaksTeredo` | Teredo - Disable | o Teredo é usado pelo Xbox Live (chat de festa, multiplayer de jogos Xbox no PC); desativar pode quebrar esses recursos |
| `WPFTweaksUTC` | Date & Time - Set Time to UTC | só faz sentido em dual boot com Linux; em PC só Windows o relógio fica errado até desfazer |
| `WPFTweaksWBAmdULPS` | AMD - Desativar ULPS (stutter e quedas de clock) | altera o driver AMD (ULPS) em todas as instâncias; em notebooks pode aumentar consumo; exige reinício |
| `WPFTweaksWBHypervisorOff` | Hypervisor (Hyper-V) - Desativar no boot | quebra WSL2, Hyper-V, Windows Sandbox, WSA e emuladores baseados em Hyper-V; exige reinício |
| `WPFTweaksWBIndexing` | Indexação (Windows Search) - Desativar serviço | a pesquisa do menu Iniciar, do Explorador e do Outlook fica lenta ou incompleta |
| `WPFTweaksWBPrefetch` | Prefetch / Superfetch - Desativar (apenas para SSD) | em HDD deixa o sistema mais lento; só faz sentido em SSD |
| `WPFTweaksWBSvcBluetooth` | Bluetooth (bthserv) - Desativar | desliga o Bluetooth (bthserv): mouses, teclados e fones Bluetooth param |
| `WPFTweaksWBSvcHello` | Biometria / Windows Hello (WbioSrvc) - Desativar | desliga a biometria (WbioSrvc): Windows Hello por rosto/digital deixa de funcionar |
| `WPFTweaksWBSvcRdp` | Área de Trabalho Remota (TermService) - Desativar | desliga a Área de Trabalho Remota (TermService): ninguém consegue acessar este PC por RDP |
| `WPFTweaksWBSvcSpooler` | Serviço de impressão (Spooler) - Desativar | desliga o Spooler: impressão e impressoras PDF param de funcionar |
| `WPFTweaksWBSvcTouchKeyboard` | Teclado virtual e caneta (TabletInputService) - Desativar | desliga o teclado virtual/caneta (TabletInputService): tablets e 2-em-1 perdem o teclado na tela |
| `WPFTweaksWBTimerBcdedit` | Timer de alta precisão via bcdedit (CUIDADO) | altera timer do kernel via bcdedit; pode causar instabilidade, stutter ou consumo maior; exige reinício |
| `WPFTweaksWBVBS` | VBS / Isolamento de Núcleo (HVCI) - Desativar | reduz a segurança contra malware de kernel (VBS/HVCI); ganho de FPS em alguns jogos; exige reinício |
| `WPFTweaksWBXboxServices` | Serviços Xbox - Desativar | quebra login no app Xbox, Game Pass, Minecraft Bedrock e jogos com conta Xbox |
| `WPFTweaksWFSrvIEESC` | Desativar a Configuração de Segurança Reforçada do IE (administradores) | reduz a proteção do navegador para administradores no servidor; use só se administra pelo navegador local |
| `WPFTweaksWFSrvSmbSigning` | SMB: exigir assinatura | custo de CPU em servidores de arquivos e clientes antigos sem assinatura param de acessar |
| `WPFTweaksWindowsAI` | Windows AI - Disable And Remove | remove o Copilot/Recall e componentes de IA (pacote CoreAI) do sistema; reinstalar exige atualização do Windows |

## Removido (2)

Estas entradas não existem no programa; ficam aqui para registrar por que saíram.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFTweaksWBServicesAggressive` | Serviços - Desativar (agressivo: impressão, Bluetooth, RDP, Windows Hello, teclado touch) | pacote que desliga impressão, Bluetooth, RDP, Windows Hello e teclado touch de uma vez; substituído por 5 itens separados |
| `WPFTweaksWBSmartScreen` | SmartScreen do Explorer e bloqueio de downloads - Desativar | reduz a segurança sem ganho de desempenho (SmartScreen e marca de origem de downloads) |
