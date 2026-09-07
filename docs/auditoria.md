# Auditoria de risco

> Arquivo gerado por `src/Engine/build.ps1` a partir de `src/Engine/config/wf-audit.ps1`.
> Não editar à mão: qualquer alteração é sobrescrita no próximo build.

Todo tweak e toggle do WinForge tem uma classe de risco. A classe não é só documentação — o motor
a aplica ao carregar as configurações:

- **Seguro** — reversível, sem custo de segurança ou estabilidade; pode aparecer em preset.
- **Cuidado** — tem um custo real; vive só na categoria "Avançado (CUIDADO)", com o custo no início
  da descrição, e nunca entra em preset.
- **Removido** — saldo negativo; a entrada e qualquer referência a ela em preset somem.

Total: **130 Seguro** · **27 Cuidado** · **2 Removido**.

## Seguro (130)

As 68 chaves `WPFTweaksWBGame*` são a prioridade de CPU por jogo (IFEO): uma chave de
registro por executável, removida ao desfazer.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFTweaksWidget` | Widgets - Remove | — |
| `WPFToggleDarkMode` | Dark Theme for Windows | — |
| `WPFTweaksRightClickMenu` | Right-Click Menu Previous Layout - Enable | — |
| `WPFTweaksServices` | Services - Set to Manual | — |
| `WPFToggleWBTransparency` | Transparência do Windows (efeitos de vidro) | — |
| `WPFTweaksHiber` | Hibernation - Disable | — |
| `WPFTweaksPreventDeviceMetadataFromNetwork` | Prevent Device Companion Apps | — |
| `WPFTweaksRazerBlock` | Razer Software Auto-Install - Disable | — |
| `WPFTweaksDiskCleanup` | Disk Cleanup - Run | — |
| `WPFTweaksActivity` | Activity History - Disable | — |
| `WPFTweaksDeliveryOptimization` | Delivery Optimization - Disable | — |
| `WPFToggleStickyKeys` | Sticky Keys | — |
| `WPFTweaksWBNvidiaTelemetry` | NVIDIA - Desativar telemetria | — |
| `WPFTweaksWBNtfsLastAccess` | NTFS - Não gravar 'último acesso' (abrir pastas/arquivos mais rápido) | — |
| `WPFTweaksWBWin32PrioritySeparation` | Prioridade do programa em primeiro plano (Win32PrioritySeparation = 0x26) | — |
| `WPFToggleTaskbarSearch` | Taskbar Search Icon | — |
| `WPFToggleTaskbarAlignment` | Taskbar Centered Icons | — |
| `WPFTweaksWBPowerSettings` | Energia - Sem suspensão USB, sem throttle e CPU em 100% na tomada | — |
| `WPFTweaksLocation` | Location Tracking - Disable | — |
| `WPFTweaksDisplay` | Visual Effects - Set to Best Performance | — |
| `WPFToggleGameMode` | Game Mode | — |
| `WPFTweaksWBAmdCrashDefender` | AMD - Desativar serviço Crash Defender | — |
| `WPFTweaksStorage` | Storage Sense - Disable | — |
| `WPFTweaksWBServicesSafe` | Serviços dispensáveis - Desativar (seleção segura) | — |
| `WPFTweaksWBSearchSuggestions` | Pesquisa - Sem histórico, sem sugestões da web e sem conteúdo da nuvem | — |
| `WPFToggleMouseAcceleration` | Mouse Acceleration | — |
| `WPFTweaksDisableExplorerAutoDiscovery` | File Explorer Automatic Folder Discovery - Disable | — |
| `WPFToggleLongPaths` | Enable Long Paths | — |
| `WPFToggleWindowSnapping` | Window Snapping | — |
| `WPFToggleTaskView` | Taskbar Task View Icon | — |
| `WPFTweaksBraveDebloat` | Brave Browser - Debloat | — |
| `WPFTweaksWBMMCSSGames` | Prioridade das tarefas de jogos (MMCSS) - Alta | — |
| `WPFToggleDetailedBSoD` | BSoD Verbose Mode | — |
| `WPFTweaksDeleteTempFiles` | Temporary Files - Remove | — |
| `WPFTweaksWBAmdShaderCache` | AMD - Forçar Shader Cache sempre ativo | — |
| `WPFToggleBingSearch` | Start Menu Bing Search | — |
| `WPFTweaksTelemetry` | Telemetry - Disable | — |
| `WPFTweaksWBNvidiaShadowPlay` | NVIDIA - Desativar ShadowPlay (overlay e gravação) | — |
| `WPFToggleVerboseLogon` | Logon Verbose Mode | — |
| `WPFToggleNumLock` | Num Lock on Startup | — |
| `WPFToggleStandbyFix` | S0 Sleep Network Connectivity | — |
| `WPFTweaksWBCortana` | Cortana - Desativar | — |
| `WPFToggleWBHAGS` | HAGS - Agendamento de GPU acelerado por hardware | — |
| `WPFToggleLoginBlur` | Logon Screen Acrylic Blur | — |
| `WPFToggleScrollbars` | Scrollbars Always Visible | — |
| `WPFTweaksRemoveHomeAndGallery` | File Explorer Home and Gallery - Disable | — |
| `WPFTweaksConsumerFeatures` | ConsumerFeatures - Disable | — |
| `WPFTweaksWBAds` | Anúncios e sugestões do Windows - Desativar | — |
| `WPFToggleBatteryPercentage` | System Tray Battery Percentage | — |
| `WPFTweaksWPBT` | Windows Platform Binary Table (WPBT) - Disable | — |
| `WPFTweaksWBAmdTelemetry` | AMD - Desativar conteúdo web e telemetria do Adrenalin | — |
| `WPFToggleStartMenuRecommendations` | Start Menu Recommendations | — |
| `WPFTweaksDisableLockscreen` | Lock Screen - Disable | — |
| `WPFTweaksEndTaskOnTaskbar` | End Task With Right Click - Enable | — |
| `WPFTweaksWBGameDVR` | Game DVR / captura da Game Bar - Desativar | — |
| `WPFTweaksRestorePoint` | Restore Point - Create | — |
| `WPFToggleShowExt` | File Explorer File Extensions | — |
| `WPFToggleHiddenFiles` | File Explorer Hidden Files | — |
| `WPFTweaksEdgeDebloat` | Microsoft Edge - Debloat | — |
| `WPFToggleHideSettingsHome` | Settings Home Page | — |
| `WPFTweaksIPv46` | IPv6 - Set IPv4 as Preferred | — |
| `WPFToggleNewOutlook` | Microsoft Outlook New Version | — |
| `WPFTweaksWBGameApexLegends` | Apex Legends | — |
| `WPFTweaksWBGameArenaBreakout` | Arena Breakout | — |
| `WPFTweaksWBGameBattlefieldOld` | Battlefield 3 / 4 / Hardline / 1 / V | — |
| `WPFTweaksWBGameBattlefield2042` | Battlefield 2042 | — |
| `WPFTweaksWBGameBattlefield6` | Battlefield 6 | — |
| `WPFTweaksWBGameBloodStrike` | Blood Strike | — |
| `WPFTweaksWBGameCODBlackOps` | Call of Duty: Black Ops (3, 4, Cold War, 6) | — |
| `WPFTweaksWBGameWarzone` | Call of Duty: Warzone / MW (cod.exe) | — |
| `WPFTweaksWBGameChivalry2` | Chivalry 2 | — |
| `WPFTweaksWBGameChooChoo` | Choo-Choo Charles | — |
| `WPFTweaksWBGameCS2` | Counter-Strike 2 | — |
| `WPFTweaksWBGameCrossfire` | Crossfire | — |
| `WPFTweaksWBGameCultOfTheLamb` | Cult of the Lamb | — |
| `WPFTweaksWBGameCuphead` | Cuphead | — |
| `WPFTweaksWBGameCyberpunk` | Cyberpunk 2077 | — |
| `WPFTweaksWBGameDaysGone` | Days Gone | — |
| `WPFTweaksWBGameDayZ` | DayZ | — |
| `WPFTweaksWBGameDeadByDaylight` | Dead by Daylight | — |
| `WPFTweaksWBGameDeadlock` | Deadlock | — |
| `WPFTweaksWBGameDeathStranding` | Death Stranding 1 e 2 | — |
| `WPFTweaksWBGameEAFC26` | EA Sports FC 26 | — |
| `WPFTweaksWBGameEscapeFromTarkov` | Escape from Tarkov | — |
| `WPFTweaksWBGameETS` | Euro Truck Simulator 1 e 2 | — |
| `WPFTweaksWBGameFS22` | Farming Simulator 22 | — |
| `WPFTweaksWBGameFS25` | Farming Simulator 25 | — |
| `WPFTweaksWBGameFFXIV` | Final Fantasy XIV | — |
| `WPFTweaksWBGameFiveM` | FiveM | — |
| `WPFTweaksWBGameFortnite` | Fortnite | — |
| `WPFTweaksWBGameFreeFire` | Free Fire (BlueStacks) | — |
| `WPFTweaksWBGameGenshin` | Genshin Impact | — |
| `WPFTweaksWBGameGhostOfTsushima` | Ghost of Tsushima | — |
| `WPFTweaksWBGameGodOfWar` | God of War (2018) e Ragnarök | — |
| `WPFTweaksWBGameGTAV` | GTA V (Legacy e Enhanced) | — |
| `WPFTweaksWBGameHellLetLoose` | Hell Let Loose | — |
| `WPFTweaksWBGameHollowKnight` | Hollow Knight e Silksong | — |
| `WPFTweaksWBGameLeft4Dead` | Left 4 Dead 1 e 2 | — |
| `WPFTweaksWBGameLeagueOfLegends` | League of Legends | — |
| `WPFTweaksWBGameMarvelRivals` | Marvel Rivals | — |
| `WPFTweaksWBGameMecchaChameleon` | Meccha Chameleon | — |
| `WPFTweaksWBGameMinecraft` | Minecraft (Java e Bedrock) - afeta todo app Java | — |
| `WPFTweaksWBGameMTA` | Multi Theft Auto (GTA SA) | — |
| `WPFTweaksWBGameMySummerCar` | My Summer Car | — |
| `WPFTweaksWBGamePalworld` | Palworld | — |
| `WPFTweaksWBGamePES` | PES 2017-2020 e eFootball | — |
| `WPFTweaksWBGamePointBlank` | Point Blank | — |
| `WPFTweaksWBGamePoppyPlaytime` | Poppy Playtime (todos) | — |
| `WPFTweaksWBGamePUBG` | PUBG: Battlegrounds | — |
| `WPFTweaksWBGameR6Siege` | Rainbow Six Siege | — |
| `WPFTweaksWBGameRDR2` | Red Dead Redemption 2 | — |
| `WPFTweaksWBGameRematch` | Rematch | — |
| `WPFTweaksWBGameRE2` | Resident Evil 2 Remake | — |
| `WPFTweaksWBGameRE4` | Resident Evil 4 Remake | — |
| `WPFTweaksWBGameREVillage` | Resident Evil Village | — |
| `WPFTweaksWBGameRERequiem` | Resident Evil Requiem | — |
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

## Cuidado (27)

O motivo abaixo é o mesmo texto que aparece como `CUIDADO: ...` no início da descrição do item
na interface.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFTweaksDisableBitLocker` | BitLocker - Disable | descriptografa a unidade do sistema: perde a proteção contra roubo/acesso físico e demora muito em discos grandes |
| `WPFTweaksWBAmdULPS` | AMD - Desativar ULPS (stutter e quedas de clock) | altera o driver AMD (ULPS) em todas as instâncias; em notebooks pode aumentar consumo; exige reinício |
| `WPFTweaksWBSvcRdp` | Área de Trabalho Remota (TermService) - Desativar | desliga a Área de Trabalho Remota (TermService): ninguém consegue acessar este PC por RDP |
| `WPFTweaksWBSvcSpooler` | Serviço de impressão (Spooler) - Desativar | desliga o Spooler: impressão e impressoras PDF param de funcionar |
| `WPFTweaksWBXboxServices` | Serviços Xbox - Desativar | quebra login no app Xbox, Game Pass, Minecraft Bedrock e jogos com conta Xbox |
| `WPFTweaksWBSvcTouchKeyboard` | Teclado virtual e caneta (TabletInputService) - Desativar | desliga o teclado virtual/caneta (TabletInputService): tablets e 2-em-1 perdem o teclado na tela |
| `WPFTweaksWBIndexing` | Indexação (Windows Search) - Desativar serviço | a pesquisa do menu Iniciar, do Explorador e do Outlook fica lenta ou incompleta |
| `WPFTweaksDisableWarningForUnsignedRdp` | RDP Unsigned File Warnings - Disable | remove o aviso de segurança ao abrir arquivos .rdp não assinados |
| `WPFTweaksDisableStoreSearch` | Microsoft Store Recommended Search Results - Disable | nega permissão ao banco da Microsoft Store (store.db); pode quebrar a busca e atualizações da Store até desfazer |
| `WPFTweaksReservedStorage` | Disable Reserved Storage | sem o armazenamento reservado, atualizações do Windows podem falhar quando o disco estiver quase cheio |
| `WPFTweaksWindowsAI` | Windows AI - Disable And Remove | remove o Copilot/Recall e componentes de IA (pacote CoreAI) do sistema; reinstalar exige atualização do Windows |
| `WPFTweaksUTC` | Date & Time - Set Time to UTC | só faz sentido em dual boot com Linux; em PC só Windows o relógio fica errado até desfazer |
| `WPFTweaksWBSvcHello` | Biometria / Windows Hello (WbioSrvc) - Desativar | desliga a biometria (WbioSrvc): Windows Hello por rosto/digital deixa de funcionar |
| `WPFToggleS3Sleep` | S3 Sleep | força suspensão S3 em vez de Modern Standby; em notebooks modernos pode impedir a suspensão ou o despertar correto |
| `WPFTweaksDisableNotifications` | System Tray Notifications & Calendar - Disable | desliga TODAS as notificações (toasts) e a Central de Ações, incluindo alertas de antivírus e de bateria |
| `WPFTweaksRemoveEdge` | Microsoft Edge - Remove | remove o navegador Edge; apps que dependem dele (Widgets, alguns instaladores, PDF padrão) deixam de funcionar; o Windows pode reinstalá-lo em atualizações |
| `WPFTweaksDisableIPv6` | IPv6 - Disable | desativa o IPv6 em todos os adaptadores; redes, VPNs e provedores que dependem de IPv6 param de funcionar |
| `WPFTweaksBlockAdobeNet` | Adobe URL Block List - Enable | edita o arquivo hosts com uma lista baixada da internet; quebra login, licenciamento e atualização de produtos Adobe |
| `WPFTweaksWBVBS` | VBS / Isolamento de Núcleo (HVCI) - Desativar | reduz a segurança contra malware de kernel (VBS/HVCI); ganho de FPS em alguns jogos; exige reinício |
| `WPFTweaksRevertStartMenu` | Start Menu Previous Layout - Enable | usa override interno de recurso (FeatureManagement) que a Microsoft pode remover; pode não ter efeito ou reverter sozinho |
| `WPFTweaksRemoveOneDrive` | Microsoft OneDrive - Remove | desinstala o OneDrive e move arquivos para o perfil local; arquivos só na nuvem NÃO são baixados antes |
| `WPFTweaksTeredo` | Teredo - Disable | o Teredo é usado pelo Xbox Live (chat de festa, multiplayer de jogos Xbox no PC); desativar pode quebrar esses recursos |
| `WPFTweaksWBPrefetch` | Prefetch / Superfetch - Desativar (apenas para SSD) | em HDD deixa o sistema mais lento; só faz sentido em SSD |
| `WPFTweaksWBHypervisorOff` | Hypervisor (Hyper-V) - Desativar no boot | quebra WSL2, Hyper-V, Windows Sandbox, WSA e emuladores baseados em Hyper-V; exige reinício |
| `WPFTweaksDisableBGapps` | Background Apps - Disable | impede TODOS os apps da Store de rodar em segundo plano: e-mail, calendário e mensagens param de sincronizar/notificar |
| `WPFTweaksWBSvcBluetooth` | Bluetooth (bthserv) - Desativar | desliga o Bluetooth (bthserv): mouses, teclados e fones Bluetooth param |
| `WPFTweaksWBTimerBcdedit` | Timer de alta precisão via bcdedit (CUIDADO) | altera timer do kernel via bcdedit; pode causar instabilidade, stutter ou consumo maior; exige reinício |

## Removido (2)

Estas entradas não existem no programa; ficam aqui para registrar por que saíram.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFTweaksWBServicesAggressive` | Serviços - Desativar (agressivo: impressão, Bluetooth, RDP, Windows Hello, teclado touch) | pacote que desliga impressão, Bluetooth, RDP, Windows Hello e teclado touch de uma vez; substituído por 5 itens separados |
| `WPFTweaksWBSmartScreen` | SmartScreen do Explorer e bloqueio de downloads - Desativar | reduz a segurança sem ganho de desempenho (SmartScreen e marca de origem de downloads) |
