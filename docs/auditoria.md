# Auditoria de risco

> Arquivo gerado por `src/Engine/build.ps1` a partir de `src/Engine/config/wf-audit.ps1`.
> Não editar à mão: qualquer alteração é sobrescrita no próximo build.

Todo tweak e toggle do WinForge tem uma classe de risco. A classe não é só documentação — o motor
a aplica ao carregar as configurações:

- **Seguro** — reversível, sem custo de segurança ou estabilidade; pode aparecer em preset.
- **Cuidado** — tem um custo real; vive só na categoria "Avançado (CUIDADO)", com o custo no início
  da descrição, e nunca entra em preset.
- **Removido** — saldo negativo; a entrada e qualquer referência a ela em preset somem.

Total: **142 Seguro** · **30 Cuidado** · **2 Removido**.

## Seguro (142)

As chaves `WPFTweaksWBGame<Jogo>` (68 entradas, contadas a partir da lista de jogos) são a
prioridade de CPU por jogo (IFEO): uma chave de registro por executável, removida ao desfazer.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFToggleBatteryPercentage` | Porcentagem da bateria na área de notificação | — |
| `WPFToggleBingSearch` | Busca do Bing no menu Iniciar | — |
| `WPFToggleDarkMode` | Tema escuro do Windows | — |
| `WPFToggleDetailedBSoD` | Tela azul detalhada | — |
| `WPFToggleGameMode` | Modo Jogo | — |
| `WPFToggleHiddenFiles` | Arquivos ocultos no Explorador | — |
| `WPFToggleHideSettingsHome` | Página inicial das Configurações | — |
| `WPFToggleLoginBlur` | Desfoque acrílico na tela de logon | — |
| `WPFToggleLongPaths` | Caminhos longos | — |
| `WPFToggleMouseAcceleration` | Aceleração do mouse | — |
| `WPFToggleNewOutlook` | Nova versão do Microsoft Outlook | — |
| `WPFToggleNumLock` | Num Lock ao iniciar | — |
| `WPFToggleScrollbars` | Barras de rolagem sempre visíveis | — |
| `WPFToggleShowExt` | Extensões de arquivo no Explorador | — |
| `WPFToggleStandbyFix` | Rede durante a suspensão S0 | — |
| `WPFToggleStartMenuRecommendations` | Recomendações do menu Iniciar | — |
| `WPFToggleStickyKeys` | Teclas de aderência | — |
| `WPFToggleTaskView` | Ícone de Visão de Tarefas na barra de tarefas | — |
| `WPFToggleTaskbarAlignment` | Ícones centralizados na barra de tarefas | — |
| `WPFToggleTaskbarSearch` | Ícone de pesquisa na barra de tarefas | — |
| `WPFToggleVerboseLogon` | Mensagens detalhadas no logon | — |
| `WPFToggleWBHAGS` | HAGS - Agendamento de GPU acelerado por hardware | — |
| `WPFToggleWBTransparency` | Transparência do Windows (efeitos de vidro) | — |
| `WPFToggleWindowSnapping` | Encaixe de janelas | — |
| `WPFTweaksActivity` | Histórico de atividades - Desativar | — |
| `WPFTweaksBraveDebloat` | Navegador Brave - Remover excessos | — |
| `WPFTweaksConsumerFeatures` | Recursos ao consumidor (ConsumerFeatures) - Desativar | — |
| `WPFTweaksDeleteTempFiles` | Arquivos temporários - Remover | — |
| `WPFTweaksDeliveryOptimization` | Otimização de Entrega - Desativar | — |
| `WPFTweaksDisableExplorerAutoDiscovery` | Descoberta automática do tipo de pasta no Explorador - Desativar | — |
| `WPFTweaksDisableLockscreen` | Tela de bloqueio - Desativar | — |
| `WPFTweaksDiskCleanup` | Limpeza de Disco - Executar | — |
| `WPFTweaksDisplay` | Efeitos visuais - Ajustar para melhor desempenho | — |
| `WPFTweaksEdgeDebloat` | Microsoft Edge - Remover excessos | — |
| `WPFTweaksEndTaskOnTaskbar` | Finalizar tarefa com o botão direito - Ativar | — |
| `WPFTweaksHiber` | Hibernação - Desativar | — |
| `WPFTweaksIPv46` | IPv6 - Preferir IPv4 | — |
| `WPFTweaksLocation` | Rastreamento de localização - Desativar | — |
| `WPFTweaksPreventDeviceMetadataFromNetwork` | Aplicativos complementares de dispositivo - Bloquear | — |
| `WPFTweaksRazerBlock` | Instalação automática do software Razer - Desativar | — |
| `WPFTweaksRemoveHomeAndGallery` | Início e Galeria do Explorador de Arquivos - Desativar | — |
| `WPFTweaksRestorePoint` | Ponto de restauração - Criar | — |
| `WPFTweaksRightClickMenu` | Layout anterior do menu de contexto - Ativar | — |
| `WPFTweaksServices` | Serviços - Definir como Manual | — |
| `WPFTweaksStorage` | Sensor de Armazenamento - Desativar | — |
| `WPFTweaksTelemetry` | Telemetria - Desativar | — |
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
| `WPFTweaksWFIisAlwaysRunning` | Pools: iniciar sempre (AlwaysRunning) | — |
| `WPFTweaksWFIisCompression` | Compressão estática e dinâmica | — |
| `WPFTweaksWFIisConcurrency` | Fila e requisições concorrentes (5000) | — |
| `WPFTweaksWFIisNoIdleTimeout` | Pools: sem tempo limite de ociosidade | — |
| `WPFTweaksWFIisOutputCache` | Cache de saída e cache de kernel | — |
| `WPFTweaksWFIisPreload` | Sites: pré-carregar (preloadEnabled) | — |
| `WPFTweaksWFSrvHighPerf` | Plano de energia Alto desempenho | — |
| `WPFTweaksWFSrvNoServerManager` | Não abrir o Gerenciador do Servidor no logon | — |
| `WPFTweaksWFSrvRdpNla` | RDP: exigir Autenticação no Nível da Rede e tempo limite de sessão ociosa (30 min) | — |
| `WPFTweaksWFSrvShutdownTracker` | Desativar o Rastreador de Eventos de Desligamento | — |
| `WPFTweaksWFSrvSmb1Off` | Desativar o SMB1 no servidor | — |
| `WPFTweaksWFSrvTcpAutotuning` | TCP: nível de ajuste automático 'normal' | — |
| `WPFTweaksWPBT` | Windows Platform Binary Table (WPBT) - Desativar | — |
| `WPFTweaksWidget` | Widgets - Remover | — |

## Cuidado (30)

O motivo abaixo é o mesmo texto que aparece como `CUIDADO: ...` no início da descrição do item
na interface.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFToggleS3Sleep` | Suspensão S3 | força suspensão S3 em vez de Modern Standby; em notebooks modernos pode impedir a suspensão ou o despertar correto |
| `WPFTweaksBlockAdobeNet` | Lista de bloqueio de URLs da Adobe - Ativar | edita o arquivo hosts com uma lista baixada da internet; quebra login, licenciamento e atualização de produtos Adobe |
| `WPFTweaksDisableBGapps` | Aplicativos em segundo plano - Desativar | impede TODOS os apps da Store de rodar em segundo plano: e-mail, calendário e mensagens param de sincronizar/notificar |
| `WPFTweaksDisableBitLocker` | BitLocker - Desativar | descriptografa a unidade do sistema: perde a proteção contra roubo/acesso físico e demora muito em discos grandes |
| `WPFTweaksDisableIPv6` | IPv6 - Desativar | desativa o IPv6 em todos os adaptadores; redes, VPNs e provedores que dependem de IPv6 param de funcionar |
| `WPFTweaksDisableNotifications` | Notificações e calendário da área de notificação - Desativar | desliga TODAS as notificações (toasts) e a Central de Ações, incluindo alertas de antivírus e de bateria |
| `WPFTweaksDisableStoreSearch` | Resultados recomendados da Microsoft Store na busca - Desativar | nega permissão ao banco da Microsoft Store (store.db); pode quebrar a busca e atualizações da Store até desfazer |
| `WPFTweaksDisableWarningForUnsignedRdp` | Avisos de arquivo RDP não assinado - Desativar | remove o aviso de segurança ao abrir arquivos .rdp não assinados |
| `WPFTweaksRemoveEdge` | Microsoft Edge - Remover | remove o navegador Edge; apps que dependem dele (Widgets, alguns instaladores, PDF padrão) deixam de funcionar; o Windows pode reinstalá-lo em atualizações |
| `WPFTweaksRemoveOneDrive` | Microsoft OneDrive - Remover | desinstala o OneDrive e move arquivos para o perfil local; arquivos só na nuvem NÃO são baixados antes |
| `WPFTweaksReservedStorage` | Armazenamento reservado - Desativar | sem o armazenamento reservado, atualizações do Windows podem falhar quando o disco estiver quase cheio |
| `WPFTweaksRevertStartMenu` | Layout anterior do menu Iniciar - Ativar | usa override interno de recurso (FeatureManagement) que a Microsoft pode remover; pode não ter efeito ou reverter sozinho |
| `WPFTweaksTeredo` | Teredo - Desativar | o Teredo é usado pelo Xbox Live (chat de festa, multiplayer de jogos Xbox no PC); desativar pode quebrar esses recursos |
| `WPFTweaksUTC` | Data e hora - Usar UTC no relógio | só faz sentido em dual boot com Linux; em PC só Windows o relógio fica errado até desfazer |
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
| `WPFTweaksWFIisMemoryRecycling` | Pools: reciclar por memória, não por tempo | recicla o pool quando passa do limite de memória privada calculado (60% da RAM dividido pelos pools); pools com muitos dados em memória podem reciclar mais que hoje |
| `WPFTweaksWFSrvIEESC` | Desativar a Configuração de Segurança Reforçada do IE (administradores) | reduz a proteção do navegador para administradores no servidor; use só se administra pelo navegador local |
| `WPFTweaksWFSrvSmbSigning` | SMB: exigir assinatura | assinar cada pacote custa CPU num servidor de arquivos, e o cliente antigo que não sabe assinar para de acessar os compartilhamentos |
| `WPFTweaksWindowsAI` | IA do Windows - Desativar e remover | remove o Copilot/Recall e componentes de IA (pacote CoreAI) do sistema; reinstalar exige atualização do Windows |

## Removido (2)

Estas entradas não existem no programa; ficam aqui para registrar por que saíram.

| Chave | Nome | Motivo |
|---|---|---|
| `WPFTweaksWBServicesAggressive` | Serviços - Desativar (agressivo: impressão, Bluetooth, RDP, Windows Hello, teclado touch) | pacote que desliga impressão, Bluetooth, RDP, Windows Hello e teclado touch de uma vez; substituído por 5 itens separados |
| `WPFTweaksWBSmartScreen` | SmartScreen do Explorer e bloqueio de downloads - Desativar | reduz a segurança sem ganho de desempenho (SmartScreen e marca de origem de downloads) |
