#region ===== WinForge - tradução por chave (tweaks, Config e aplicativos) =====

# O texto dos três blocos JSON da base - tweaks (inclui os toggles), feature (aba Configurações) e
# applications (aba Instalar) - não dá para traduzir por substituição literal como o resto do motor
# (config\wf-i18n-strings.ps1): são centenas de frases parecidas, e um par literal errado se
# esconderia num Replace-Once que continua achando âncora em outro lugar. Aqui a tradução é POR
# CHAVE, então cada entrada tem um dono e a cobertura é verificável.
#
# Quem aplica é Initialize-WinUtilBoostConfigs (winforge\wb-functions.ps1), depois das mesclas e
# ANTES de Initialize-WinForgeAudit - a auditoria prefixa "CUIDADO: ..." na descrição dos itens de
# risco e precisa ver o texto já em português.
#
# Regras:
#   - 'Content' mantém a forma "<coisa> - <ação>" da base, em português ("Histórico de atividades -
#     Desativar", "Ponto de restauração - Criar"). Nome próprio fica como está (Copilot, OneDrive,
#     Edge, Hyper-V).
#   - Toggle não é ação, é estado: o Content fica em forma de substantivo ("Tema escuro do Windows",
#     "Modo Jogo", "Aceleração do mouse").
#   - 'Description' é tradução fiel: nada de promessa nova, número novo ou recomendação que o texto
#     original não fazia.
#   - Aplicativo tem só 'Description'. O nome do produto ('content') fica em inglês de propósito -
#     é como o programa se chama na tela de instalação e na busca.
#
# As entradas do próprio WinForge (WPFTweaksWB*, WPFTweaksWF*, WPFToggleWB*, WPFPanelWB*, WPFWFRep*,
# WPFWFSrv*, WPFWFAd*) já nascem em português e NÃO entram aqui; a trava do -SelfTest as dispensa
# por prefixo. Chave que falta e chave a mais são erro de -SelfTest; `tools\List-I18nKeys.ps1`
# imprime o que falta, já no formato de colar.

$sync.WinForgeI18n = @{

    # ---------------------------------------------------------------- aba Ajustes: tweaks
    'WPFTweaksActivity' = @{
        Content     = 'Histórico de atividades - Desativar'
        Description = 'Apaga o histórico de documentos recentes, da área de transferência e da caixa Executar.'
    }
    'WPFTweaksHiber' = @{
        Content     = 'Hibernação - Desativar'
        Description = 'A hibernação foi pensada para notebooks: salva o conteúdo da memória antes de desligar o PC. Na prática, quase nunca deveria ser usada.'
    }
    'WPFTweaksWidget' = @{
        Content     = 'Widgets - Remover'
        Description = 'Remove os widgets incômodos do canto inferior esquerdo da barra de tarefas.'
    }
    'WPFTweaksRevertStartMenu' = @{
        Content     = 'Layout anterior do menu Iniciar - Ativar'
        Description = 'Traz de volta o layout antigo do menu Iniciar, anterior à troca gradual feita no 25H2. Em versões mais novas do Windows !!ESTE AJUSTE NÃO FUNCIONA!!'
    }
    'WPFTweaksDisableStoreSearch' = @{
        Content     = 'Resultados recomendados da Microsoft Store na busca - Desativar'
        Description = 'Deixa de mostrar aplicativos recomendados da Microsoft Store ao procurar programas no menu Iniciar.'
    }
    'WPFTweaksLocation' = @{
        Content     = 'Rastreamento de localização - Desativar'
        Description = 'Desativa o rastreamento de localização.'
    }
    'WPFTweaksServices' = @{
        Content     = 'Serviços - Definir como Manual'
        Description = 'Coloca alguns serviços em inicialização Manual e ajusta o valor SvcHostSplitThresholdInKB do registro conforme a memória do sistema, o que pode reduzir bastante o número de processos svchost.exe.'
    }
    'WPFTweaksBraveDebloat' = @{
        Content     = 'Navegador Brave - Remover excessos'
        Description = 'Desativa incômodos como Brave Rewards, Leo AI, Crypto Wallet e VPN.'
    }
    'WPFTweaksDisableWarningForUnsignedRdp' = @{
        Content     = 'Avisos de arquivo RDP não assinado - Desativar'
        Description = 'Desativa os avisos exibidos ao abrir arquivos RDP não assinados, introduzidos nas atualizações mais recentes do Windows 10 e 11.'
    }
    'WPFTweaksEdgeDebloat' = @{
        Content     = 'Microsoft Edge - Remover excessos'
        Description = 'Desativa opções de telemetria, pop-ups e outros incômodos do Edge.'
    }
    'WPFTweaksConsumerFeatures' = @{
        Content     = 'Recursos ao consumidor (ConsumerFeatures) - Desativar'
        Description = 'Impede a instalação de aplicativos promovidos e reduz as sugestões de aplicativos vindas da Microsoft Store.'
    }
    'WPFTweaksTelemetry' = @{
        Content     = 'Telemetria - Desativar'
        Description = 'Desativa a telemetria da Microsoft.'
    }
    'WPFTweaksDeliveryOptimization' = @{
        Content     = 'Otimização de Entrega - Desativar'
        Description = 'Impede que o Windows use a sua banda para enviar atualizações a outros PCs da internet ou da rede local.'
    }
    'WPFTweaksRemoveEdge' = @{
        Content     = 'Microsoft Edge - Remover'
        Description = 'Desinstala o Microsoft Edge criando um arquivo MicrosoftEdge.exe falso na pasta do Edge antigo. Isso engana o Windows, que libera o desinstalador oficial do Edge e permite a remoção no nível do sistema.'
    }
    'WPFTweaksDisableBitLocker' = @{
        Content     = 'BitLocker - Desativar'
        Description = 'Desativa o BitLocker.'
    }
    'WPFTweaksUTC' = @{
        Content     = 'Data e hora - Usar UTC no relógio'
        Description = 'Essencial em computadores com dual boot. Corrige a sincronização de horário com sistemas Linux.'
    }
    'WPFTweaksRemoveOneDrive' = @{
        Content     = 'Microsoft OneDrive - Remover'
        Description = 'Nega a permissão de apagar os arquivos do usuário no OneDrive, usa o desinstalador do próprio programa para removê-lo e devolve a permissão original depois.'
    }
    'WPFTweaksRemoveHomeAndGallery' = @{
        Content     = 'Início e Galeria do Explorador de Arquivos - Desativar'
        Description = 'Remove o Início e a Galeria do Explorador e define Este Computador como pasta padrão.'
    }
    'WPFTweaksDisplay' = @{
        Content     = 'Efeitos visuais - Ajustar para melhor desempenho'
        Description = 'Ajusta as preferências do sistema para desempenho. Dá para fazer o mesmo à mão pelo sysdm.cpl.'
    }
    'WPFTweaksReservedStorage' = @{
        Content     = 'Armazenamento reservado - Desativar'
        Description = 'Desativa o Armazenamento Reservado do Windows (7 a 10 GB guardados para atualizações e arquivos temporários). Recomendado só em discos pequenos. Reative antes das atualizações grandes de recurso do Windows, para não falhar a instalação.'
    }
    'WPFTweaksRestorePoint' = @{
        Content     = 'Ponto de restauração - Criar'
        Description = 'Cria um ponto de restauração na hora, caso seja preciso desfazer as alterações do WinForge.'
    }
    'WPFTweaksEndTaskOnTaskbar' = @{
        Content     = 'Finalizar tarefa com o botão direito - Ativar'
        Description = 'Ativa a opção de finalizar tarefa ao clicar com o botão direito em um programa na barra de tarefas.'
    }
    'WPFTweaksStorage' = @{
        Content     = 'Sensor de Armazenamento - Desativar'
        Description = 'O Sensor de Armazenamento apaga arquivos temporários automaticamente.'
    }
    'WPFTweaksWindowsAI' = @{
        Content     = 'IA do Windows - Desativar e remover'
        Description = 'Remove e desativa todos os recursos e pacotes de IA.'
    }
    'WPFTweaksWPBT' = @{
        Content     = 'Windows Platform Binary Table (WPBT) - Desativar'
        Description = 'Com a WPBT ativa, o fabricante do computador pode executar programas na inicialização: software antifurto, drivers e até instalação forçada de programas sem o consentimento do usuário. É um risco de segurança em potencial.'
    }
    'WPFTweaksPreventDeviceMetadataFromNetwork' = @{
        Content     = 'Aplicativos complementares de dispositivo - Bloquear'
        Description = 'Impede a instalação de programas adicionais ao conectar dispositivos (por exemplo, anúncios ao ligar um monitor). É um risco de segurança em potencial.'
    }
    'WPFTweaksRazerBlock' = @{
        Content     = 'Instalação automática do software Razer - Desativar'
        Description = 'Bloqueia TODAS as instalações de software da Razer. O hardware funciona bem sem programa nenhum.'
    }
    'WPFTweaksDisableNotifications' = @{
        Content     = 'Notificações e calendário da área de notificação - Desativar'
        Description = 'Desativa TODAS as notificações, INCLUSIVE o calendário.'
    }
    'WPFTweaksBlockAdobeNet' = @{
        Content     = 'Lista de bloqueio de URLs da Adobe - Ativar'
        Description = 'Reduz interrupções bloqueando seletivamente as conexões com os servidores de ativação e telemetria da Adobe. Crédito: Ruddernation-Designs'
    }
    'WPFTweaksRightClickMenu' = @{
        Content     = 'Layout anterior do menu de contexto - Ativar'
        Description = 'Restaura o menu de contexto clássico ao clicar com o botão direito no Explorador de Arquivos, no lugar da versão simplificada do Windows 11.'
    }
    'WPFTweaksDiskCleanup' = @{
        Content     = 'Limpeza de Disco - Executar'
        Description = 'Executa a Limpeza de Disco na unidade C: e remove atualizações antigas do Windows.'
    }
    'WPFTweaksDeleteTempFiles' = @{
        Content     = 'Arquivos temporários - Remover'
        Description = 'Apaga as pastas TEMP.'
    }
    'WPFTweaksIPv46' = @{
        Content     = 'IPv6 - Preferir IPv4'
        Description = 'Preferir o IPv4 pode trazer ganho de latência e de segurança em redes privadas onde o IPv6 não está configurado.'
    }
    'WPFTweaksTeredo' = @{
        Content     = 'Teredo - Desativar'
        Description = 'O tunelamento de rede Teredo é um recurso de IPv6 que pode somar latência, mas desativá-lo pode causar problemas em alguns jogos.'
    }
    'WPFTweaksDisableIPv6' = @{
        Content     = 'IPv6 - Desativar'
        Description = 'Desativa o IPv6.'
    }
    'WPFTweaksDisableBGapps' = @{
        Content     = 'Aplicativos em segundo plano - Desativar'
        Description = 'Impede que todos os aplicativos da Microsoft Store rodem em segundo plano - algo que, desde o Windows 11, só dava para fazer um por um.'
    }
    'WPFTweaksDisableExplorerAutoDiscovery' = @{
        Content     = 'Descoberta automática do tipo de pasta no Explorador - Desativar'
        Description = 'O Explorador do Windows tenta adivinhar o tipo da pasta pelo conteúdo, o que deixa a navegação mais lenta. ATENÇÃO! Isto desativa o agrupamento no Explorador de Arquivos.'
    }

    # ---------------------------------------------------------------- aba Ajustes: toggles e listas
    'WPFToggleDetailedBSoD' = @{
        Content     = 'Tela azul detalhada'
        Description = 'Mostra mais informações quando ocorre uma tela azul.'
    }
    'WPFToggleBatteryPercentage' = @{
        Content     = 'Porcentagem da bateria na área de notificação'
        Description = 'Mostra a porcentagem da bateria em números ao lado do ícone de bateria, na área de notificação.'
    }
    'WPFToggleDarkMode' = @{
        Content     = 'Tema escuro do Windows'
        Description = 'Modo escuro para o sistema e para os aplicativos.'
    }
    'WPFToggleShowExt' = @{
        Content     = 'Extensões de arquivo no Explorador'
        Description = 'Mostra as extensões dos arquivos no Explorador (.exe, .png etc.).'
    }
    'WPFToggleHiddenFiles' = @{
        Content     = 'Arquivos ocultos no Explorador'
        Description = 'Exibe os arquivos ocultos no Explorador.'
    }
    'WPFToggleVerboseLogon' = @{
        Content     = 'Mensagens detalhadas no logon'
        Description = 'Mostra mensagens detalhadas durante a inicialização e o desligamento.'
    }
    'WPFToggleNewOutlook' = @{
        Content     = 'Nova versão do Microsoft Outlook'
        Description = 'Garante que o aplicativo clássico do Outlook seja usado.'
    }
    'WPFToggleScrollbars' = @{
        Content     = 'Barras de rolagem sempre visíveis'
        Description = 'Ativado, as barras de rolagem ficam sempre visíveis. Desativado, o Windows as esconde automaticamente enquanto não estão em uso.'
    }
    'WPFMultiplaneOverlay' = @{
        Content     = 'Multiplane Overlay (MPO)'
        Description = 'O Multiplane Overlay compõe várias camadas de imagem, o que às vezes causa problemas com placas de vídeo. A mudança nesta preferência vale imediatamente.'
    }
    'WPFToggleMouseAcceleration' = @{
        Content     = 'Aceleração do mouse'
        Description = 'Faz o movimento do cursor depender da velocidade do movimento físico do mouse.'
    }
    'WPFToggleNumLock' = @{
        Content     = 'Num Lock ao iniciar'
        Description = 'Define o estado da tecla Num Lock quando o computador inicia.'
    }
    'WPFToggleWindowSnapping' = @{
        Content     = 'Encaixe de janelas'
        Description = 'Liga e desliga o encaixe de janelas ao arrastá-las.'
    }
    'WPFToggleStandbyFix' = @{
        Content     = 'Rede durante a suspensão S0'
        Description = 'Liga e desliga a conexão de rede durante a suspensão S0, o modo de baixo consumo dos notebooks modernos.'
    }
    'WPFToggleS3Sleep' = @{
        Content     = 'Suspensão S3'
        Description = 'Alterna entre o Modern Standby e a suspensão S3, que corta a energia da CPU e continua apenas atualizando a memória.'
    }
    'WPFToggleHideSettingsHome' = @{
        Content     = 'Página inicial das Configurações'
        Description = 'Liga e desliga a página inicial do aplicativo Configurações do Windows.'
    }
    'WPFToggleBingSearch' = @{
        Content     = 'Busca do Bing no menu Iniciar'
        Description = 'Liga e desliga os resultados da web do Bing na Pesquisa do Windows.'
    }
    'WPFToggleLoginBlur' = @{
        Content     = 'Desfoque acrílico na tela de logon'
        Description = 'Liga e desliga o efeito de desfoque acrílico no fundo da tela de login.'
    }
    'WPFTweaksDisableLockscreen' = @{
        Content     = 'Tela de bloqueio - Desativar'
        Description = 'Pula a tela de bloqueio e vai direto para a tela de entrada, ao ligar e ao acordar o computador.'
    }
    'WPFToggleStartMenuRecommendations' = @{
        Content     = 'Recomendações do menu Iniciar'
        Description = 'Liga e desliga a seção de recomendações do menu Iniciar. ATENÇÃO: como efeito colateral, isto também desativa o Windows Spotlight na tela de bloqueio.'
    }
    'WPFToggleStickyKeys' = @{
        Content     = 'Teclas de aderência'
        Description = 'Liga e desliga as Teclas de Aderência, que são acionadas ao apertar Shift várias vezes seguidas.'
    }
    'WPFToggleTaskbarAlignment' = @{
        Content     = 'Ícones centralizados na barra de tarefas'
        Description = 'Alterna o alinhamento da barra de tarefas entre a esquerda e o centro.'
    }
    'WPFToggleTaskbarSearch' = @{
        Content     = 'Ícone de pesquisa na barra de tarefas'
        Description = 'Liga e desliga o botão de pesquisa na barra de tarefas.'
    }
    'WPFToggleTaskView' = @{
        Content     = 'Ícone de Visão de Tarefas na barra de tarefas'
        Description = 'Liga e desliga o botão de Visão de Tarefas na barra de tarefas.'
    }
    'WPFToggleGameMode' = @{
        Content     = 'Modo Jogo'
        Description = 'Faz o Windows priorizar o desempenho em jogos, destinando recursos do sistema a eles.'
    }
    'WPFToggleLongPaths' = @{
        Content     = 'Caminhos longos'
        Description = 'Liga e desliga o suporte a caminhos de arquivo com mais de 260 caracteres no Explorador.'
    }
    'WPFOOSUbutton' = @{
        Content = 'O&O ShutUp10++ - Executar'
    }
    'WPFchangedns' = @{
        Content = 'DNS - Definir como:'
    }
    'WPFAddUltPerf' = @{
        Content = 'Plano Desempenho Máximo - Ativar'
    }
    'WPFRemoveUltPerf' = @{
        Content = 'Plano Desempenho Máximo - Desativar'
    }

    # ---------------------------------------------------------------- aba Configurações: recursos
    'WPFFeaturesdotnet' = @{
        Content     = '.NET Framework (versões 2, 3 e 4) - Ativar'
        Description = 'O .NET e o .NET Framework formam uma plataforma de desenvolvimento feita de ferramentas, linguagens de programação e bibliotecas para criar muitos tipos de aplicação.'
    }
    # Os cinco botões do grupo "Correções" rodam fora da thread da janela, com a saída ao vivo numa
    # janela própria, e todos passam por uma caixa de Sim/Não antes de agir. A descrição abaixo é a
    # MESMA frase que a caixa mostra (Get-WinForgeRepairConfirmText a lê daqui), então ela precisa
    # dizer o que vai rodar e, onde for o caso, que é preciso reiniciar - não é só uma dica de botão.
    'WPFFixesNTPPool' = @{
        Content     = 'Servidor NTP - Ativar'
        Description = 'Troca o servidor NTP padrão do Windows (time.windows.com) pelo pool.ntp.org, para uma sincronização de horário mais precisa e confiável. Inicia o serviço de Horário do Windows, grava a nova lista de servidores com o w32tm, reinicia o serviço e força uma sincronização.'
    }
    'WPFFeatureshyperv' = @{
        Content     = 'Hyper-V - Ativar'
        Description = 'O Hyper-V é o produto de virtualização de hardware da Microsoft, que permite criar e gerenciar máquinas virtuais.'
    }
    'WPFFeatureslegacymedia' = @{
        Content     = 'Componentes de mídia antigos (WMP, DirectPlay) - Ativar'
        Description = 'Ativa programas antigos, de versões anteriores do Windows.'
    }
    'WPFFeaturewsl' = @{
        Content     = 'Subsistema do Windows para Linux (WSL) - Ativar'
        Description = 'O Subsistema do Windows para Linux é um recurso opcional do Windows que permite rodar programas Linux nativamente, sem máquina virtual e sem dual boot.'
    }
    'WPFFeaturenfs' = @{
        Content     = 'Sistema de Arquivos de Rede (NFS) - Ativar'
        Description = 'O Network File System (NFS) é um mecanismo para guardar arquivos em rede.'
    }
    'WPFFeatureRegBackup' = @{
        Content     = 'Backup do registro (tarefa diária às 00:30) - Ativar'
        Description = 'Ativa o backup diário do registro, que a Microsoft desativou no Windows 10 1803.'
    }
    'WPFFeatureEnableLegacyRecovery' = @{
        Content     = 'Recuperação antiga pelo F8 - Ativar'
        Description = 'Ativa a tela de Opções Avançadas de Inicialização, que permite iniciar o Windows em modos avançados de solução de problemas.'
    }
    'WPFFeatureDisableLegacyRecovery' = @{
        Content     = 'Recuperação antiga pelo F8 - Desativar'
        Description = 'Desativa a tela de Opções Avançadas de Inicialização, que permite iniciar o Windows em modos avançados de solução de problemas.'
    }
    'WPFFeaturesSandbox' = @{
        Content     = 'Windows Sandbox - Ativar'
        Description = 'O Windows Sandbox é uma máquina virtual leve que oferece uma área de trabalho temporária para rodar aplicativos e programas em isolamento, com segurança.'
    }
    'WPFFeatureInstall' = @{
        Content = 'Instalar recursos'
    }
    'WPFPanelAutologin' = @{
        Content = 'Logon automático - Executar'
    }
    'WPFFixesUpdate' = @{
        Content     = 'Windows Update - Redefinir'
        Description = 'Redefine o Windows Update: para os serviços BITS, wuauserv, appidsvc e cryptsvc, apaga a fila de trabalhos do BITS e o log, renomeia a pasta de downloads, registra de novo as DLLs, remove as configurações de WSUS, redefine o Winsock e religa os serviços. É preciso reiniciar o computador depois.'
    }
    'WPFFixesNetwork' = @{
        Content     = 'Rede - Redefinir'
        Description = 'Redefine a pilha de rede com "netsh winsock reset" e "netsh int ip reset": as configurações de TCP/IP e do Winsock voltam ao padrão do Windows, e conexões de VPN ou proxy podem precisar ser refeitas. É preciso reiniciar o computador para concluir.'
    }
    'WPFPanelDISM' = @{
        Content     = 'Verificação de corrupção do sistema - Executar'
        Description = 'Roda em sequência o chkdsk (verificação do disco do sistema, só leitura), o sfc /scannow (reparo dos arquivos protegidos do Windows) e o DISM /RestoreHealth (reparo da imagem do Windows, que baixa arquivos pela internet). Pode levar de vários minutos a mais de uma hora, e a saída aparece ao vivo numa janela.'
    }
    'WPFFixesWinget' = @{
        Content     = 'WinGet - Reinstalar'
        Description = 'Reinstala o WinGet (Gerenciador de Pacotes do Windows) baixando o App Installer da Microsoft. Precisa de internet e pode demorar. Os programas já instalados por ele continuam onde estão.'
    }
    'WPFWinForgeSSHServer' = @{
        Content = 'Servidor OpenSSH - Ativar'
    }

    # ---------------------------------------------------------------- aba Configurações: painéis clássicos
    'WPFPanelComputer' = @{
        Content = 'Gerenciamento do Computador'
    }
    'WPFPanelControl' = @{
        Content = 'Painel de Controle'
    }
    'WPFPanelMouse' = @{
        Content = 'Propriedades do Mouse'
    }
    'WPFPanelNetwork' = @{
        Content = 'Conexões de Rede'
    }
    'WPFPanelPower' = @{
        Content = 'Opções de Energia'
    }
    'WPFPanelPrinter' = @{
        Content = 'Impressoras'
    }
    'WPFPanelPrograms' = @{
        Content = 'Programas e Recursos'
    }
    'WPFPanelRegion' = @{
        Content = 'Região'
    }
    'WPFPanelSecurity' = @{
        Content = 'Segurança e Manutenção'
    }
    'WPFPanelSound' = @{
        Content = 'Configurações de Som'
    }
    'WPFPanelSystem' = @{
        Content = 'Propriedades do Sistema'
    }
    'WPFPanelTimedate' = @{
        Content = 'Data e Hora'
    }
    'WPFPanelFirewall' = @{
        Content = 'Firewall do Windows Defender'
    }
    'WPFPanelRestore' = @{
        Content = 'Restauração do Sistema'
    }

    # ---------------------------------------------------------------- aba Instalar: descrição dos aplicativos
    # O nome do produto ('content') não é traduzido: é o nome pelo qual o programa é procurado.
    'WPFInstall1password' = @{ Description = 'O 1Password é um gerenciador de senhas que guarda e organiza suas senhas com segurança.' }
    'WPFInstall7zip' = @{ Description = 'O 7-Zip é um compactador de arquivos livre e de código aberto. Suporta vários formatos de compressão e alcança uma taxa de compressão alta, o que o tornou uma escolha popular.' }
    'WPFInstalladobe' = @{ Description = 'O Adobe Acrobat Reader é um leitor de PDF gratuito, com os recursos essenciais para ver, imprimir e anotar documentos PDF.' }
    'WPFInstalladvancedip' = @{ Description = 'O Advanced IP Scanner é um analisador de rede rápido e fácil de usar. Foi feito para examinar redes locais e mostra informações sobre os dispositivos conectados.' }
    'WPFInstallaimp' = @{ Description = 'O AIMP é um reprodutor de música completo, com suporte a vários formatos de áudio, listas de reprodução e interface personalizável.' }
    'WPFInstallanydesk' = @{ Description = 'O AnyDesk é um programa de acesso remoto que permite usar e controlar computadores à distância. É conhecido pela conexão rápida e pela baixa latência.' }
    'WPFInstallaudacity' = @{ Description = 'O Audacity é um editor de áudio livre e de código aberto, conhecido pelos recursos de gravação e edição.' }
    'WPFInstallautoruns' = @{ Description = 'Este utilitário mostra quais programas estão configurados para iniciar junto com o sistema ou com o logon.' }
    'WPFInstallautohotkey' = @{ Description = 'O AutoHotkey é uma linguagem de script para Windows que permite criar automações e macros próprias. É muito usado para automatizar tarefas repetitivas e personalizar atalhos de teclado.' }
    'WPFInstallbattlenet' = @{ Description = 'O Battle.net é o lançador dos jogos criados e desenvolvidos pela Activision Blizzard.' }
    'WPFInstallbitwarden' = @{ Description = 'O Bitwarden é um gerenciador de senhas de código aberto. Guarda e organiza as senhas em um cofre criptografado, acessível de vários dispositivos.' }
    'WPFInstallblender' = @{ Description = 'O Blender é uma suíte de criação 3D de código aberto, com ferramentas de modelagem, escultura, animação e renderização.' }
    'WPFInstallbrave' = @{ Description = 'O Brave é um navegador focado em privacidade, que bloqueia anúncios e rastreadores e deixa a navegação mais rápida e segura.' }
    'WPFInstallbulkcrapuninstaller' = @{ Description = 'O Bulk Crap Uninstaller é um desinstalador livre e de código aberto para Windows. Ajuda a tirar programas indesejados e a limpar o sistema desinstalando vários aplicativos de uma vez.' }
    'WPFInstallcalibre' = @{ Description = 'O Calibre é um gerenciador, leitor e conversor de e-books poderoso e fácil de usar.' }
    'WPFInstallchatgpt' = @{ Description = 'Aplicativo oficial do ChatGPT para Windows, distribuído pela Microsoft Store.' }
    'WPFInstallchrome' = @{ Description = 'O Google Chrome é um navegador muito usado, conhecido pela velocidade, pela simplicidade e pela integração com os serviços do Google.' }
    'WPFInstallcinebenchr23' = @{ Description = 'O Cinebench R23 é uma ferramenta de benchmark para comparar o desempenho de renderização da CPU entre computadores.' }
    'WPFInstallclaude' = @{ Description = 'Aplicativo da Anthropic para conversar com o Claude e trabalhar com apoio de IA sem distração.' }
    'WPFInstallcpuz' = @{ Description = 'O CPU-Z é uma ferramenta de monitoramento e diagnóstico para Windows. Mostra informações detalhadas do hardware do computador, incluindo processador, memória e placa-mãe.' }
    'WPFInstallcrystaldiskinfo' = @{ Description = 'O Crystal Disk Info monitora a saúde dos discos e mostra o estado e o desempenho das unidades. Ajuda a antecipar problemas e a acompanhar o desgaste do disco.' }
    'WPFInstallcrystaldiskmark' = @{ Description = 'O Crystal Disk Mark mede as velocidades de leitura e escrita dos dispositivos de armazenamento. Ajuda a avaliar o desempenho de HDs e SSDs.' }
    'WPFInstallcursor' = @{ Description = 'Editor de código com IA (baseado no VS Code), com recursos de programação agêntica e assistência de IA integrada ao fluxo de desenvolvimento.' }
    'WPFInstallddu' = @{ Description = 'O Display Driver Uninstaller (DDU) desinstala por completo drivers de vídeo NVIDIA, AMD e Intel. É útil para resolver problemas causados por driver de vídeo.' }
    'WPFInstalldiscord' = @{ Description = 'O Discord é uma plataforma de comunicação com voz, vídeo e texto, criada para jogadores e adotada por comunidades de todo tipo.' }
    'WPFInstalldockerdesktop' = @{ Description = 'O Docker Desktop oferece um ambiente local para criar, executar e testar aplicações em contêiner no Windows.' }
    'WPFInstalldotnet6' = @{ Description = 'O .NET Desktop Runtime 6 é o ambiente de execução necessário para rodar aplicativos feitos com o .NET 6.' }
    'WPFInstalldotnet8' = @{ Description = 'O .NET Desktop Runtime 8 é o ambiente de execução necessário para rodar aplicativos feitos com o .NET 8.' }
    'WPFInstalldotnet10' = @{ Description = 'O .NET Desktop Runtime 10 é o ambiente de execução necessário para rodar aplicativos feitos com o .NET 10.' }
    'WPFInstalldropbox' = @{ Description = 'O Dropbox é um cliente de armazenamento em nuvem para sincronizar arquivos, compartilhar conteúdo e manter documentos disponíveis em vários dispositivos.' }
    'WPFInstalleaapp' = @{ Description = 'O EA App é a plataforma para acessar e jogar os jogos da Electronic Arts.' }
    'WPFInstalleartrumpet' = @{ Description = 'O EarTrumpet é um controle de áudio para Windows, com uma interface simples e direta para gerenciar o som.' }
    'WPFInstalledge' = @{ Description = 'O Microsoft Edge é um navegador moderno baseado no Chromium, com desempenho, segurança e integração com os serviços da Microsoft.' }
    'WPFInstallepicgames' = @{ Description = 'O Epic Games Launcher é o cliente para acessar e jogar os jogos da Epic Games Store.' }
    'WPFInstallfirefox' = @{ Description = 'O Mozilla Firefox é um navegador de código aberto conhecido pelas opções de personalização, pelos recursos de privacidade e pelas extensões.' }
    'WPFInstallflux' = @{ Description = 'O f.lux ajusta a temperatura de cor da tela para reduzir o cansaço visual à noite.' }
    'WPFInstallfoxpdfreader' = @{ Description = 'O Foxit PDF Reader é um leitor de PDF gratuito, com a interface em faixa de opções a que todo mundo está acostumado.' }
    'WPFInstallgeforcenow' = @{ Description = 'O GeForce NOW é um serviço de jogos em nuvem que permite jogar títulos pesados de PC no seu dispositivo.' }
    'WPFInstallgimp' = @{ Description = 'O GIMP é um editor de imagens raster de código aberto, versátil, usado para retoque de fotos, edição e composição de imagens.' }
    'WPFInstallgit' = @{ Description = 'O Git é um sistema de controle de versão distribuído, muito usado para acompanhar mudanças no código-fonte durante o desenvolvimento.' }
    'WPFInstallgithubdesktop' = @{ Description = 'O GitHub Desktop é um cliente Git visual que simplifica a colaboração em repositórios do GitHub, com uma interface fácil de usar.' }
    'WPFInstallgog' = @{ Description = 'O GOG Galaxy é um cliente de jogos que oferece títulos sem DRM, conteúdo adicional e mais.' }
    'WPFInstallgolang' = @{ Description = 'Go (ou Golang) é uma linguagem de programação compilada e de tipagem estática, criada com foco em simplicidade, confiabilidade e eficiência.' }
    'WPFInstallgoogledrive' = @{ Description = 'Sincronização de arquivos entre dispositivos, tudo ligado à sua conta Google.' }
    'WPFInstallgpuz' = @{ Description = 'O GPU-Z mostra informações detalhadas sobre a sua placa de vídeo e a GPU.' }
    'WPFInstallhandbrake' = @{ Description = 'O HandBrake é um conversor de vídeo de código aberto, que converte vídeo de quase qualquer formato para uma seleção de codecs bem suportados.' }
    'WPFInstallhwinfo' = @{ Description = 'O HWiNFO mostra informações completas de hardware e diagnósticos no Windows.' }
    'WPFInstallhwmonitor' = @{ Description = 'O HWMonitor é um programa de monitoramento de hardware que lê os principais sensores de saúde do PC.' }
    'WPFInstallimageglass' = @{ Description = 'O ImageGlass é um visualizador de imagens versátil, com suporte a vários formatos e foco em simplicidade e velocidade.' }
    'WPFInstallinternetdownloadmanager' = @{ Description = 'O Internet Download Manager é um gerenciador de downloads para acelerar, retomar e agendar transferências de arquivos.' }
    'WPFInstallirfanview' = @{ Description = 'O IrfanView é um visualizador e editor de imagens leve, rápido e gratuito. Suporta vários formatos, processamento em lote e plugins poderosos.' }
    'WPFInstallitunes' = @{ Description = 'O iTunes é um reprodutor de mídia, biblioteca de mídia e rádio on-line desenvolvido pela Apple.' }
    'WPFInstalljava21' = @{ Description = 'O Amazon Corretto é uma distribuição gratuita, multiplataforma e pronta para produção do OpenJDK.' }
    'WPFInstalljetbrains' = @{ Description = 'O JetBrains Toolbox é uma plataforma para instalar e gerenciar com facilidade as ferramentas de desenvolvimento da JetBrains.' }
    'WPFInstallkeepassxc' = @{ Description = 'O KeePassXC é um gerenciador de senhas moderno, seguro e de código aberto, que guarda e organiza suas informações mais sensíveis. Roda no Windows, no macOS e no Linux. Foi feito para quem tem exigências altas de segurança: guarda usuários, senhas, endereços, anexos e anotações em um arquivo criptografado, off-line, que pode ficar em qualquer lugar, inclusive em nuvens públicas ou privadas. As entradas recebem títulos e ícones próprios e são organizadas em grupos personalizáveis. A busca integrada aceita padrões avançados para achar qualquer entrada do banco. O gerador de senhas, rápido e fácil de usar, cria senhas com qualquer combinação de caracteres ou frases-senha fáceis de lembrar.' }
    'WPFInstallklite' = @{ Description = 'O K-Lite Codec Pack Standard é um conjunto de codecs de áudio e vídeo e ferramentas relacionadas, com os componentes essenciais para reproduzir mídia.' }
    'WPFInstallkodi' = @{ Description = 'O Kodi é uma central de mídia de código aberto que reproduz e exibe a maior parte dos vídeos, músicas, podcasts e outros arquivos de mídia digital.' }
    'WPFInstalllibreoffice' = @{ Description = 'O LibreOffice é uma suíte de escritório gratuita e completa, compatível com as outras grandes suítes de escritório.' }
    'WPFInstalllibrewolf' = @{ Description = 'O LibreWolf é um navegador focado em privacidade, baseado no Firefox, com reforços extras de privacidade e segurança.' }
    'WPFInstalllocalsend' = @{ Description = 'Alternativa ao AirDrop, de código aberto e multiplataforma.' }
    'WPFInstallmpv' = @{ Description = 'O mpv é um reprodutor de mídia gratuito, de código aberto e multiplataforma, com suporte a uma grande variedade de formatos, codecs e tipos de legenda.' }
    'WPFInstallminitoolpartitionwizard' = @{ Description = 'Gerenciador de partições gratuito e completo, que faz operações avançadas que o Windows não faz sozinho, como unir partições, converter sistemas de arquivos e reorganizar o espaço em disco.' }
    'WPFInstallmoonlight' = @{ Description = 'O Moonlight/GameStream Client transmite jogos de PC para outros dispositivos da sua rede local.' }
    'WPFInstallmpchc' = @{ Description = 'O Media Player Classic - Home Cinema (MPC-HC) é um reprodutor de vídeo e áudio livre e de código aberto para Windows. É baseado no projeto original Guliverkli e traz muitos recursos adicionais e correções.' }
    'WPFInstallmsiafterburner' = @{ Description = 'O MSI Afterburner é um utilitário de overclock de placa de vídeo com recursos avançados.' }
    'WPFInstallnanazip' = @{ Description = 'O NanaZip é uma ferramenta de compressão e descompressão de arquivos rápida e eficiente.' }
    'WPFInstalltailscale' = @{ Description = 'O cliente Tailscale conecta todos os seus dispositivos usando WireGuard®, sem complicação. É tão simples quanto instalar o aplicativo e entrar na conta.' }
    'WPFInstallnaps2' = @{ Description = 'O NAPS2 é um aplicativo de digitalização que simplifica a criação de documentos eletrônicos.' }
    'WPFInstallnodejslts' = @{ Description = 'O NodeJS LTS traz as versões com suporte de longo prazo, para um desenvolvimento JavaScript no servidor estável e confiável.' }
    'WPFInstallnotepadplus' = @{ Description = 'O Notepad++ é um editor de código gratuito e de código aberto, substituto do Bloco de Notas, com suporte a várias linguagens.' }
    'WPFInstallnvclean' = @{ Description = 'O NVCleanstall permite personalizar a instalação dos drivers NVIDIA, dando ao usuário avançado controle sobre mais partes do processo.' }
    'WPFInstallobs' = @{ Description = 'O OBS Studio é um programa livre e de código aberto para gravar vídeo e transmitir ao vivo. Captura e mistura vídeo e áudio em tempo real, o que o tornou popular entre criadores de conteúdo.' }
    'WPFInstallobsidian' = @{ Description = 'O Obsidian é um aplicativo de anotações e de gestão de conhecimento.' }
    'WPFInstallonedrive' = @{ Description = 'O OneDrive é o serviço de armazenamento em nuvem da Microsoft, para guardar e compartilhar arquivos com segurança entre dispositivos.' }
    'WPFInstallonlyoffice' = @{ Description = 'O ONLYOFFICE Desktop é uma suíte de escritório completa para editar documentos e colaborar.' }
    'WPFInstallopenrgb' = @{ Description = 'O OpenRGB é um software de código aberto para controlar a iluminação RGB de vários componentes e periféricos.' }
    'WPFInstallOpenVPN' = @{ Description = 'O OpenVPN Connect é um cliente de VPN para se conectar com segurança a um servidor VPN. Oferece uma conexão segura e criptografada para proteger sua privacidade on-line.' }
    'WPFInstallOVirtualBox' = @{ Description = 'O Oracle VirtualBox é uma ferramenta de virtualização gratuita e de código aberto para arquiteturas x86 e AMD64/Intel64.' }
    'WPFInstallprocessexplorer' = @{ Description = 'O Process Explorer é um gerenciador de tarefas e monitor de sistema.' }
    'WPFInstallPaintdotnet' = @{ Description = 'O Paint.NET é um editor de imagens e fotos gratuito para Windows. Tem uma interface intuitiva e uma boa variedade de ferramentas de edição.' }
    'WPFInstallparsec' = @{ Description = 'O Parsec é um aplicativo de área de trabalho remota de baixa latência e alta qualidade, para colaborar e jogar entre dispositivos.' }
    'WPFInstallpeazip' = @{ Description = 'O PeaZip é um compactador de arquivos gratuito e de código aberto, com suporte a vários formatos e recursos de criptografia.' }
    'WPFInstallpdf24creator' = @{ Description = 'Ferramentas de PDF gratuitas e fáceis de usar, on-line e no computador, que fazem você produzir mais.' }
    'WPFInstallplaynite' = @{ Description = 'O Playnite é um gerenciador de biblioteca de jogos de código aberto com um objetivo simples: reunir todos os seus jogos em uma interface única.' }
    'WPFInstallplexdesktop' = @{ Description = 'O Plex Desktop para Windows é a interface do Plex Media Server.' }
    'WPFInstallpostman' = @{ Description = 'O Postman é uma plataforma de APIs e um cliente de desktop para projetar, testar, documentar e colaborar em APIs.' }
    'WPFInstallpowershell' = @{ Description = 'O PowerShell é uma plataforma de automação e uma linguagem de script feita para administradores de sistema, com recursos poderosos de linha de comando.' }
    'WPFInstallpowertoys' = @{ Description = 'O PowerToys é um conjunto de utilitários para usuários avançados ganharem produtividade, com ferramentas como FancyZones e PowerRename.' }
    'WPFInstallprismlauncher' = @{ Description = 'O Prism Launcher é um lançador de Minecraft de código aberto, capaz de gerenciar várias instâncias, contas e mods.' }
    'WPFInstallprocesslasso' = @{ Description = 'O Process Lasso é uma ferramenta de otimização e automação que melhora a resposta e a estabilidade do sistema ajustando prioridades de processo e afinidade de CPU.' }
    'WPFInstallprotonvpn' = @{ Description = 'O Proton VPN é um serviço de VPN sem registro de atividade, que protege sua privacidade on-line com recursos como Secure Core e Tor sobre VPN.' }
    'WPFInstallprocessmonitor' = @{ Description = 'O Process Monitor, da SysInternals, é uma ferramenta avançada que mostra em tempo real a atividade do sistema de arquivos, do registro e dos processos e threads.' }
    'WPFInstallputty' = @{ Description = 'O PuTTY é um emulador de terminal, console serial e programa de transferência de arquivos livre e de código aberto. Suporta protocolos de rede como SSH, Telnet e SCP.' }
    'WPFInstallpython3' = @{ Description = 'Python é uma linguagem de programação versátil, usada em desenvolvimento web, análise de dados, inteligência artificial e muito mais.' }
    'WPFInstallqbittorrent' = @{ Description = 'O qBittorrent é um cliente BitTorrent livre e de código aberto, que quer ser uma alternativa completa e leve aos outros clientes de torrent.' }
    'WPFInstallrevo' = @{ Description = 'O Revo Uninstaller é um desinstalador avançado que ajuda a tirar programas indesejados e a limpar o sistema.' }
    'WPFInstallrufus' = @{ Description = 'O Rufus é um utilitário que formata e cria pen drives inicializáveis.' }
    'WPFInstallrustlang' = @{ Description = 'Rust é uma linguagem de programação criada com foco em segurança e desempenho, voltada principalmente à programação de sistemas.' }
    'WPFInstallsdio' = @{ Description = 'O Snappy Driver Installer Origin é um atualizador de drivers livre e de código aberto, com um banco de drivers enorme para Windows.' }
    'WPFInstallsharex' = @{ Description = 'O ShareX é uma ferramenta livre e de código aberto para capturar a tela e compartilhar arquivos. Tem vários modos de captura e recursos avançados para editar e compartilhar as imagens.' }
    'WPFInstallsignal' = @{ Description = 'O Signal é um mensageiro focado em privacidade, com criptografia de ponta a ponta para uma comunicação segura e privada.' }
    'WPFInstallslack' = @{ Description = 'O Slack é uma central de colaboração que conecta equipes por canais, mensagens e compartilhamento de arquivos.' }
    'WPFInstallstartallback' = @{ Description = 'O StartAllBack restaura e melhora a barra de tarefas, o menu Iniciar, o Explorador de Arquivos e o comportamento da interface do Windows.' }
    'WPFInstallsteam' = @{ Description = 'A Steam é uma plataforma de distribuição digital para comprar e jogar jogos, com multijogador, transmissão de vídeo e mais.' }
    'WPFInstallsublimetext' = @{ Description = 'O Sublime Text é um editor de texto sofisticado para código, marcação e prosa.' }
    'WPFInstallsumatra' = @{ Description = 'O Sumatra PDF é um leitor de PDF leve e rápido, de visual minimalista.' }
    'WPFInstalltcpview' = @{ Description = 'O TCPView, da SysInternals, é uma ferramenta de monitoramento de rede que mostra em detalhe todos os pontos de conexão TCP e UDP do sistema.' }
    'WPFInstallteams' = @{ Description = 'O Microsoft Teams é uma plataforma de colaboração integrada ao Office 365, com bate-papo, videoconferência, compartilhamento de arquivos e mais.' }
    'WPFInstallteamviewer' = @{ Description = 'O TeamViewer é um programa popular de acesso remoto e suporte, que permite conectar e controlar dispositivos à distância.' }
    'WPFInstallteamspeak6' = @{ Description = 'TEAMSPEAK. SEU TIME. SUAS REGRAS. Som cristalino para falar com o time em qualquer plataforma, com segurança de nível militar, desempenho sem travada e confiabilidade e disponibilidade sem igual.' }
    'WPFInstalltelegram' = @{ Description = 'O Telegram é um mensageiro instantâneo baseado em nuvem, conhecido pelos recursos de segurança, pela velocidade e pela simplicidade.' }
    'WPFInstallterminal' = @{ Description = 'O Windows Terminal é um aplicativo de terminal moderno, rápido e eficiente para quem usa linha de comando, com várias abas, painéis e mais.' }
    'WPFInstallthunderbird' = @{ Description = 'O Mozilla Thunderbird é um cliente de e-mail, de notícias e de bate-papo livre e de código aberto, com recursos avançados.' }
    'WPFInstalltor' = @{ Description = 'O Tor Browser foi feito para navegação anônima: usa a rede Tor para proteger a privacidade e a segurança de quem navega.' }
    'WPFInstalltotalcommander' = @{ Description = 'O Total Commander é um gerenciador de arquivos para Windows, com uma interface poderosa e direta.' }
    'WPFInstalltreesize' = @{ Description = 'O TreeSize Free é um gerenciador de espaço em disco que ajuda a analisar e visualizar o uso do espaço nas unidades.' }
    'WPFInstallttaskbar' = @{ Description = 'O TranslucentTB permite personalizar a transparência da barra de tarefas do Windows.' }
    'WPFInstallubisoft' = @{ Description = 'O Ubisoft Connect é o serviço de distribuição digital e de jogos on-line da Ubisoft, com acesso aos jogos e serviços da empresa.' }
    'WPFInstalleverything' = @{ Description = 'O Everything é um buscador que encontra arquivos e pastas pelo nome, instantaneamente, no Windows. Diferente da pesquisa do Windows, ele começa mostrando todos os arquivos e pastas do computador (daí o nome) e você digita um filtro para limitar o que aparece.' }
    'WPFInstallvc2015_32' = @{ Description = 'O pacote redistribuível do Visual C++ 2015-2022 de 32 bits instala os componentes de execução das bibliotecas do Visual C++ necessários para rodar aplicativos de 32 bits.' }
    'WPFInstallvc2015_64' = @{ Description = 'O pacote redistribuível do Visual C++ 2015-2022 de 64 bits instala os componentes de execução das bibliotecas do Visual C++ necessários para rodar aplicativos de 64 bits.' }
    'WPFInstallventoy' = @{ Description = 'O Ventoy é uma ferramenta de código aberto para criar pen drives inicializáveis. Aceita vários arquivos ISO em um único pen drive, o que o torna uma solução versátil para instalar sistemas operacionais.' }
    'WPFInstallvisualstudio2022' = @{ Description = 'O Visual Studio 2022 é um ambiente de desenvolvimento integrado (IDE) para criar, depurar e publicar aplicações.' }
    'WPFInstallvivaldi' = @{ Description = 'O Vivaldi é um navegador altamente configurável, com foco em personalização e produtividade.' }
    'WPFInstallvlc' = @{ Description = 'O VLC Media Player é um reprodutor multimídia livre e de código aberto, com suporte a uma grande variedade de formatos de áudio e vídeo. É conhecido pela versatilidade e por rodar em várias plataformas.' }
    'WPFInstallvscode' = @{ Description = 'O Visual Studio Code é um editor de código gratuito e de código aberto, com suporte a várias linguagens de programação.' }
    'WPFInstallwhatsapp' = @{ Description = 'O WhatsApp Desktop é o aplicativo oficial de mensagens da Meta para Windows, distribuído pela Microsoft Store.' }
    'WPFInstallwingetui' = @{ Description = 'O UniGetUI é uma interface gráfica para o WinGet, o Chocolatey e outros gerenciadores de pacotes de linha de comando do Windows.' }
    'WPFInstallwinrar' = @{ Description = 'O WinRAR é um gerenciador de arquivos compactados que permite criar, organizar e extrair arquivos.' }
    'WPFInstallwinscp' = @{ Description = 'O WinSCP é um cliente SFTP, FTP e SCP de código aberto muito usado no Windows. Permite transferir arquivos com segurança entre o computador local e um remoto.' }
    'WPFInstallwireguard' = @{ Description = 'O WireGuard é um protocolo de VPN rápido e moderno. Quer ser mais simples e mais eficiente que os outros protocolos de VPN, com conexões seguras e confiáveis.' }
    'WPFInstallwireshark' = @{ Description = 'O Wireshark é um analisador de protocolos de rede de código aberto, muito usado. Permite capturar e analisar o tráfego de rede em tempo real, com uma visão detalhada do que acontece na rede.' }
    'WPFInstallwiztree' = @{ Description = 'O WizTree é um analisador de espaço em disco rápido, que ajuda a encontrar depressa os arquivos e pastas que mais ocupam espaço.' }
    'WPFInstallzoom' = @{ Description = 'O Zoom é um serviço popular de videoconferência para reuniões on-line, webinars e trabalho em equipe.' }
    'WPFInstalltightvnc' = @{ Description = 'O TightVNC é um programa de acesso remoto livre e de código aberto que permite usar e controlar um computador pela rede. Pela interface, você interage com a tela remota como se estivesse na frente dela: abre arquivos, inicia programas e faz o que precisa, quase como se estivesse ali.' }
    'WPFInstallZenBrowser' = @{ Description = 'Navegador moderno, focado em privacidade e desempenho, construído sobre o Firefox.' }
    'WPFInstallCloudflareWARP' = @{ Description = 'O WARP é um serviço de VPN freemium da Cloudflare. Inclui o uso do DNS da Cloudflare.' }
}
#endregion
