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
#   - 'Description' NÃO é tradução do texto original. O texto da base é um slogan curto ("Disables
#     Microsoft Telemetry") que não ajuda ninguém a decidir. Aqui a descrição é escrita a partir do
#     que a entrada REALMENTE faz - os campos registry, service, feature, InvokeScript e UndoScript
#     do bloco JSON da base dizem isso com precisão - em 1 a 3 frases, nesta ordem: (1) o que faz,
#     nomeando o mecanismo em palavras simples; (2) que efeito prático isso tem; (3) quando usar, o
#     que custa ou o que deixa de funcionar. Sem promessa vaga ("melhora o desempenho" sem dizer
#     como), sem repetir o título e sem repetir a mesma frase duas vezes dentro da mesma descrição.
#   - Item de risco NÃO escreve "CUIDADO:" aqui: quem prefixa o motivo é Initialize-WinForgeAudit,
#     a partir do Reason de config\wf-audit.ps1. Escrever à mão daria o aviso em dobro.
#   - Aplicativo tem só 'Description': uma frase dizendo o que o programa é, outra dizendo por que
#     alguém o instalaria. O nome do produto ('content') fica em inglês de propósito - é como o
#     programa se chama na tela de instalação e na busca.
#
# As cinco regras acima têm trava no -SelfTest do motor (frase repetida, tamanho mínimo, descrição
# que só repete o Content, 'Origem:' em dobro e 'CUIDADO:' escrito à mão). O que a trava não julga
# é se o texto é bom: para revisar isso, `tools\List-Descriptions.ps1` põe chave, título e descrição
# lado a lado.
#
# As entradas do próprio WinForge (WPFTweaksWB*, WPFTweaksWF*, WPFToggleWB*, WPFPanelWB*, WPFWFRep*,
# WPFWFSrv*, WPFWFAd*) já nascem em português e NÃO entram aqui; a trava do -SelfTest as dispensa
# por prefixo. Chave que falta e chave a mais são erro de -SelfTest; `tools\List-I18nKeys.ps1`
# imprime o que falta, já no formato de colar.

$sync.WinForgeI18n = @{

    # ---------------------------------------------------------------- aba Ajustes: tweaks
    'WPFTweaksActivity' = @{
        Content     = 'Histórico de atividades - Desativar'
        Description = 'Zera as três políticas da Linha do Tempo (EnableActivityFeed, PublishUserActivities e UploadUserActivities), então o Windows para de registrar o que você abriu e de enviar esse histórico para a conta Microsoft. Some o "retomar de onde parei" entre dispositivos e a lista de atividades antigas na Visão de Tarefas. Reversível pelo Desfazer.'
    }
    'WPFTweaksHiber' = @{
        Content     = 'Hibernação - Desativar'
        Description = 'Roda "powercfg /hibernate off" e tira a opção Hibernar do menu de energia. Some o hiberfil.sys, que ocupa no disco do sistema uma fatia do tamanho da memória instalada - em geral vários GB. Junto vai a Inicialização Rápida, que depende desse arquivo; em notebook, pense duas vezes antes de abrir mão de salvar a sessão quando a bateria acaba.'
    }
    'WPFTweaksWidget' = @{
        Content     = 'Widgets - Remover'
        Description = 'Encerra o processo dos Widgets e desinstala para todos os usuários os pacotes Microsoft.WidgetsPlatformRuntime e MicrosoftWindows.Client.WebExperience, reiniciando o Explorador em seguida. O painel de clima e notícias some do canto da barra de tarefas e para de consumir memória em segundo plano. Para ter de volta é preciso reinstalar os pacotes pela Microsoft Store.'
    }
    'WPFTweaksRevertStartMenu' = @{
        Content     = 'Layout anterior do menu Iniciar - Ativar'
        Description = 'Grava um override interno de recurso (FeatureManagement\Overrides) para desligar o menu Iniciar novo que a Microsoft passou a distribuir gradualmente no 25H2. Quando pega, o menu volta ao layout anterior depois de reiniciar o Explorador. É um identificador interno da Microsoft: em versões mais novas do Windows !!ESTE AJUSTE NÃO FUNCIONA!! e simplesmente não faz efeito.'
    }
    'WPFTweaksDisableStoreSearch' = @{
        Content     = 'Resultados recomendados da Microsoft Store na busca - Desativar'
        Description = 'Nega a permissão de todo mundo (icacls /deny) sobre o arquivo store.db da Microsoft Store, que é de onde a Pesquisa do Windows tira os aplicativos sugeridos. Digitar um nome no menu Iniciar deixa de trazer a faixa de programas para comprar. Como o banco fica inacessível, a busca dentro da própria Store pode parar junto.'
    }
    'WPFTweaksLocation' = @{
        Content     = 'Rastreamento de localização - Desativar'
        Description = 'Marca a localização como negada no ConsentStore do sistema, zera a permissão do sensor, desliga o serviço lfsvc (Localização Geográfica) e para a atualização automática dos mapas offline. Clima, "Encontrar meu dispositivo" e qualquer programa que peça sua posição passam a receber recusa. Nenhum hardware é desabilitado, só o acesso a ele; reversível pelo Desfazer.'
    }
    'WPFTweaksServices' = @{
        Content     = 'Serviços - Definir como Manual'
        Description = 'Desativa Arquivos Offline (CscService), telemetria (DiagTrack) e Compartilhamento de Conexão (SharedAccess), põe Mapas (MapsBroker) e Armazenamento (StorSvc) em Manual e grava SvcHostSplitThresholdInKB com o total de memória da máquina. Esse último valor faz o Windows voltar a agrupar serviços em poucos processos svchost.exe em vez de um por serviço, encurtando muito a lista do Gerenciador de Tarefas. O agrupamento tem um custo: um serviço que trave pode derrubar os vizinhos do mesmo processo.'
    }
    'WPFTweaksBraveDebloat' = @{
        Content     = 'Navegador Brave - Remover excessos'
        Description = 'Grava doze políticas em HKLM\SOFTWARE\Policies\BraveSoftware\Brave que desligam Rewards, Wallet, VPN, Leo AI, Brave News, Brave Talk, a janela Tor e os quatro canais de métricas (P3A, ping de estatísticas, dados por URL e navegação segura estendida). O navegador abre sem esses painéis e sem enviar telemetria. Só mexe no Brave, e só funciona na instalação que respeita política corporativa.'
    }
    'WPFTweaksDisableWarningForUnsignedRdp' = @{
        Content     = 'Avisos de arquivo RDP não assinado - Desativar'
        Description = 'Grava RedirectionWarningDialogVersion e RdpLaunchConsentAccepted para o Windows parar de pedir confirmação ao abrir um arquivo .rdp sem assinatura digital. Serve a quem conecta no mesmo servidor várias vezes por dia por um atalho próprio. O Desfazer remove as duas chaves e a caixa volta.'
    }
    'WPFTweaksEdgeDebloat' = @{
        Content     = 'Microsoft Edge - Remover excessos'
        Description = 'Grava políticas em HKLM\SOFTWARE\Policies\Microsoft\Edge que desligam a tela de primeira execução, os dados de diagnóstico, o relatório de personalização, as recomendações, o painel lateral (WebWidget), as Coleções, o assistente de compras, o Rewards, as páginas de erro alternativas e a campanha de "torne o Edge o padrão". O navegador abre limpo e para de sugerir e de medir. O Edge continua instalado e funcionando; desfazer remove as chaves de política.'
    }
    'WPFTweaksConsumerFeatures' = @{
        Content     = 'Recursos ao consumidor (ConsumerFeatures) - Desativar'
        Description = 'Liga a política DisableWindowsConsumerFeatures, que é a chave consultada antes de o Windows instalar sozinho os aplicativos promovidos (Candy Crush, TikTok, Spotify e afins) numa conta nova. Nada é removido: o que para é a instalação silenciosa de novos e a sugestão deles no menu Iniciar. Reversível pelo Desfazer.'
    }
    'WPFTweaksTelemetry' = @{
        Content     = 'Telemetria - Desativar'
        Description = 'Zera AllowTelemetry, o ID de publicidade, o reconhecimento de fala on-line, a personalização de digitação e escrita à tinta, o Feedback do Windows e a lista de programas mais usados; desliga os serviços DiagTrack e wermgr, põe o Defender para não enviar amostras automaticamente e marca a recusa de telemetria do PowerShell 7. Menos dados saem da máquina e duas tarefas somem do segundo plano. O Windows continua recebendo atualizações, mas relatórios de erro deixam de ser enviados e alguns diagnósticos da Microsoft param de funcionar.'
    }
    'WPFTweaksDeliveryOptimization' = @{
        Content     = 'Otimização de Entrega - Desativar'
        Description = 'Põe DODownloadMode em 0, o modo em que o Windows só aceita atualização vinda dos servidores da Microsoft. Este PC para de baixar pedaços de outros computadores e, principalmente, de gastar a sua banda de upload enviando para eles. Em rede com muitas máquinas as atualizações podem ficar mais lentas, porque cada uma passa a baixar tudo por conta própria.'
    }
    'WPFTweaksRemoveEdge' = @{
        Content     = 'Microsoft Edge - Remover'
        Description = 'Cria um MicrosoftEdge.exe falso na pasta do Edge antigo para destravar o desinstalador oficial e roda esse desinstalador com remoção no nível do sistema e apagamento do perfil. O navegador some da máquina, e com ele o motor que os Widgets e alguns visualizadores de PDF usam por baixo. O Desfazer reinstala o Edge pelo winget.'
    }
    'WPFTweaksDisableBitLocker' = @{
        Content     = 'BitLocker - Desativar'
        Description = 'Roda Disable-BitLocker no volume do Windows, o que dispara a descriptografia em segundo plano. Dá para usar o PC enquanto isso, mas o disco fica mais lento até terminar. Ao fim, a unidade passa a abrir em qualquer computador sem senha nem chave de recuperação.'
    }
    'WPFTweaksUTC' = @{
        Content     = 'Data e hora - Usar UTC no relógio'
        Description = 'Grava RealTimeIsUniversal e faz o Windows ler o relógio da placa-mãe como UTC, e não como hora local. É a convenção que o Linux usa por padrão, então num dual boot os dois sistemas param de adiantar e atrasar o relógio um do outro a cada troca. A hora que aparece na tela continua a do seu fuso, convertida pelo sistema.'
    }
    'WPFTweaksRemoveOneDrive' = @{
        Content     = 'Microsoft OneDrive - Remover'
        Description = 'Nega temporariamente a permissão de apagar a pasta do OneDrive, chama o desinstalador do próprio programa (OneDriveSetup /uninstall), limpa os restos em %LocalAppData% e %ProgramData%, devolve a permissão original e desativa o serviço OneSyncSvc. O ícone da nuvem some do Explorador e a sincronização para. O Desfazer reinstala o OneDrive pelo winget e religa o serviço.'
    }
    'WPFTweaksRemoveHomeAndGallery' = @{
        Content     = 'Início e Galeria do Explorador de Arquivos - Desativar'
        Description = 'Desafixa da árvore do Explorador os nós Início e Galeria, cada um pelo seu CLSID, e muda LaunchTo para a janela abrir em "Este Computador". Some a página de arquivos recentes e recomendados e a linha do tempo de fotos, e o Explorador passa a abrir direto nas unidades. Nenhum arquivo é tocado; reversível pelo Desfazer.'
    }
    'WPFTweaksDisplay' = @{
        Content     = 'Efeitos visuais - Ajustar para melhor desempenho'
        Description = 'Aplica por registro o mesmo conjunto do "ajustar para melhor desempenho" do sysdm.cpl: sem animação de janela e de barra de tarefas, sem sombra e sem transparência na seleção, sem Aero Peek, menu abrindo em 200 ms em vez de 400 e conteúdo não redesenhado durante o arrasto. A interface fica seca e responde antes, o que se nota em máquina fraca e em área de trabalho remota. Também esconde os botões de Visão de Tarefas e de pesquisa da barra; é tudo preferência visual, nada de sistema.'
    }
    'WPFTweaksReservedStorage' = @{
        Content     = 'Armazenamento reservado - Desativar'
        Description = 'Roda "DISM /Set-ReservedStorageState /State:Disabled" e devolve ao uso comum os 7 a 10 GB que o Windows separa para instalar atualizações e guardar arquivos temporários. Faz diferença real em disco de 128 GB, onde esse espaço é o que separa caber de não caber. Reative antes de uma atualização grande de versão do Windows, senão a instalação pode não achar espaço.'
    }
    'WPFTweaksRestorePoint' = @{
        Content     = 'Ponto de restauração - Criar'
        Description = 'Liga a Proteção do Sistema no disco do Windows se ela estiver desligada, zera o intervalo mínimo entre pontos (SystemRestorePointCreationFrequency) e cria um ponto na hora. É o seguro para voltar atrás caso algum ajuste desta lista não caia bem na sua máquina. Leva de segundos a alguns minutos e ocupa espaço dentro da cota da Proteção do Sistema.'
    }
    'WPFTweaksEndTaskOnTaskbar' = @{
        Content     = 'Finalizar tarefa com o botão direito - Ativar'
        Description = 'Liga TaskbarEndTask, a opção de desenvolvedor que acrescenta "Finalizar tarefa" ao menu do botão direito de qualquer programa na barra de tarefas. Mata o processo travado sem precisar abrir o Gerenciador de Tarefas. O encerramento é forçado: o programa morre sem salvar nada.'
    }
    'WPFTweaksStorage' = @{
        Content     = 'Sensor de Armazenamento - Desativar'
        Description = 'Zera a política 01 do Sensor de Armazenamento, a rotina que apaga sozinha arquivos temporários e itens antigos da Lixeira quando o disco enche. Nada mais some sem você mandar. Em disco pequeno, conte com limpar à mão de vez em quando.'
    }
    'WPFTweaksWindowsAI' = @{
        Content     = 'IA do Windows - Desativar e remover'
        Description = 'Remove os pacotes do Copilot e o MicrosoftWindows.Client.CoreAI, desliga o recurso opcional Recall e o serviço WSAIFabricSvc, tira os recursos de IA do Bloco de Notas e esconde a página de componentes de IA nas Configurações. Somem o botão do Copilot, o histórico do Recall e a reescrita por IA. É praticamente só de ida: trazer esses componentes de volta depende de uma atualização do Windows reinstalá-los.'
    }
    'WPFTweaksWPBT' = @{
        Content     = 'Windows Platform Binary Table (WPBT) - Desativar'
        Description = 'Grava DisableWpbtExecution, que impede o Windows de executar na inicialização o programa que a UEFI da placa-mãe injeta pela tabela WPBT. É por esse caminho que alguns fabricantes reinstalam software de fábrica mesmo depois de uma formatação limpa, sem pedir nada a ninguém. Se você depende de um agente antifurto embutido na BIOS, ele deixa de se reinstalar sozinho.'
    }
    'WPFTweaksPreventDeviceMetadataFromNetwork' = @{
        Content     = 'Aplicativos complementares de dispositivo - Bloquear'
        Description = 'Liga a política PreventDeviceMetadataFromNetwork, que corta a busca de metadados na internet quando você conecta um periférico novo. É esse download que às vezes traz junto o aplicativo do fabricante e um anúncio ao ligar um monitor ou uma impressora. O driver continua vindo normalmente pelo Windows Update; o que some é o pacote extra e o ícone bonito do dispositivo.'
    }
    'WPFTweaksRazerBlock' = @{
        Content     = 'Instalação automática do software Razer - Desativar'
        Description = 'Zera SearchOrderConfig, liga DisableCoInstallers e nega escrita na pasta %SystemRoot%\Installer\Razer, que é por onde o Synapse se reinstala sozinho quando o periférico é plugado. Mouse e teclado Razer continuam funcionando como dispositivo comum, sem macro e sem perfil na nuvem. Repare no alcance: a primeira chave vale para TODOS os fabricantes, então drivers opcionais deixam de chegar pelo Windows Update.'
    }
    'WPFTweaksDisableNotifications' = @{
        Content     = 'Notificações e calendário da área de notificação - Desativar'
        Description = 'Liga DisableNotificationCenter e zera ToastEnabled: somem os balões do canto da tela e o painel lateral com o calendário junto. Nada mais interrompe uma apresentação ou uma gravação de tela. É um corte geral, sem exceção por aplicativo.'
    }
    'WPFTweaksBlockAdobeNet' = @{
        Content     = 'Lista de bloqueio de URLs da Adobe - Ativar'
        Description = 'Baixa a lista da Ruddernation-Designs e acrescenta as linhas ao arquivo hosts do Windows, apontando para lugar nenhum os domínios de ativação e telemetria da Adobe. As checagens e os avisos que interrompem o trabalho param de aparecer. O Desfazer corta de volta o trecho acrescentado e limpa o cache de DNS.'
    }
    'WPFTweaksRightClickMenu' = @{
        Content     = 'Layout anterior do menu de contexto - Ativar'
        Description = 'Cria vazia a chave InprocServer32 sob o CLSID {86ca1aa0-34aa-4e8b-a509-50c905bae2a2} e reinicia o Explorador, que é a forma conhecida de o Windows 11 desistir do menu de contexto reduzido. Volta o menu completo do Windows 10 no clique direito, sem o passo "Mostrar mais opções". O Desfazer apaga a chave e o menu novo retorna.'
    }
    'WPFTweaksDiskCleanup' = @{
        Content     = 'Limpeza de Disco - Executar'
        Description = 'Roda o cleanmgr em /VERYLOWDISK na unidade C:, que limpa todas as categorias sem abrir caixa de diálogo, e em seguida o StartComponentCleanup do DISM, que compacta os componentes antigos do WinSxS. Libera de poucos GB a algumas dezenas numa instalação antiga. Pode demorar vários minutos e a Lixeira é esvaziada no caminho.'
    }
    'WPFTweaksDeleteTempFiles' = @{
        Content     = 'Arquivos temporários - Remover'
        Description = 'Apaga o conteúdo de %TEMP% (do seu usuário) e de C:\Windows\Temp, as duas pastas onde instaladores e programas deixam lixo para trás. Libera de alguns MB a vários GB, conforme o tempo desde a última limpeza. Arquivo em uso é pulado e nada fora dessas duas pastas é tocado.'
    }
    'WPFTweaksIPv46' = @{
        Content     = 'IPv6 - Preferir IPv4'
        Description = 'Grava DisabledComponents = 0x20 em Tcpip6, que é a forma recomendada pela Microsoft de dar preferência ao IPv4 na tabela de políticas de prefixo. O IPv6 continua ligado, mas só é usado quando não há caminho por IPv4 - o que corta a espera de um IPv6 mal configurado na rede local. É a mais branda das três opções de IPv6 desta lista: nada é desligado, só reordenado. O valor é lido quando a pilha TCP/IP sobe, então reinicie o computador depois de marcar.'
    }
    'WPFTweaksTeredo' = @{
        Content     = 'Teredo - Desativar'
        Description = 'Grava DisabledComponents = 0x01 e roda "netsh interface teredo set state disabled", desligando os túneis de IPv6 sobre IPv4 (Teredo, 6to4 e ISATAP). Some uma camada de encapsulamento que em algumas redes só acrescenta latência. O comando netsh vale na hora e derruba os túneis já levantados; a chave de registro só passa a valer no próximo início do Windows.'
    }
    'WPFTweaksDisableIPv6' = @{
        Content     = 'IPv6 - Desativar'
        Description = 'Grava DisabledComponents = 0xFF e desmarca o Protocolo IP Versão 6 em todas as placas de rede. A máquina passa a falar só IPv4, o que às vezes resolve DNS lento e site que demora a abrir numa rede onde o IPv6 é anunciado mas não funciona. É a mais drástica das três opções de IPv6 desta lista: DirectAccess e qualquer serviço que só escute em IPv6 param de funcionar, e a Microsoft não recomenda desligar o protocolo inteiro. Só passa a valer depois de reiniciar.'
    }
    'WPFTweaksDisableBGapps' = @{
        Content     = 'Aplicativos em segundo plano - Desativar'
        Description = 'Grava GlobalUserDisabled, o interruptor único que impede TODOS os aplicativos da Microsoft Store de rodar em segundo plano - desde o Windows 11 as Configurações só permitem isso um por um. Menos processos acordando sozinhos, menos CPU e bateria gastas com o computador parado. Programas comuns de área de trabalho não são afetados.'
    }
    'WPFTweaksDisableExplorerAutoDiscovery' = @{
        Content     = 'Descoberta automática do tipo de pasta no Explorador - Desativar'
        Description = 'Apaga os bancos Bags e BagMRU, onde o Explorador guarda o tipo que ele adivinhou para cada pasta, e fixa FolderType = NotSpecified para todas. Pastas grandes abrem na hora, sem a espera de montar colunas de música ou miniaturas de foto que você não pediu. ATENÇÃO! Isto desativa o agrupamento no Explorador de Arquivos, e é preciso sair e entrar da conta para valer.'
    }

    # ---------------------------------------------------------------- aba Ajustes: toggles e listas
    'WPFToggleDetailedBSoD' = @{
        Content     = 'Tela azul detalhada'
        Description = 'Liga DisplayParameters e tira o rosto triste da tela azul (DisableEmoticon). No lugar da carinha e do QR code aparecem o código de parada, os parâmetros e o driver envolvido - a informação que serve para pesquisar a causa. Só muda o que é exibido: não evita nem provoca travamento.'
    }
    'WPFToggleBatteryPercentage' = @{
        Content     = 'Porcentagem da bateria na área de notificação'
        Description = 'Liga IsBatteryPercentageEnabled e põe o número ao lado do ícone de bateria, na área de notificação. Você lê 37% em vez de adivinhar pelo desenho quanto ainda resta. Só faz diferença em máquina com bateria.'
    }
    'WPFToggleDarkMode' = @{
        Content     = 'Tema escuro do Windows'
        Description = 'Zera AppsUseLightTheme e SystemUsesLightTheme, os dois valores que o Windows lê para pintar a interface, e reinicia o Explorador para valer na hora. Menu Iniciar, Configurações, Explorador e os aplicativos que seguem o tema do sistema ficam escuros. Programa antigo com cor própria continua claro.'
    }
    'WPFToggleShowExt' = @{
        Content     = 'Extensões de arquivo no Explorador'
        Description = 'Zera HideFileExt e reinicia o Explorador, fazendo aparecer .exe, .png, .pdf no fim do nome de cada arquivo. Além de saber o que se está abrindo, é a defesa mais simples contra o velho truque do "foto.jpg.exe".'
    }
    'WPFToggleHiddenFiles' = @{
        Content     = 'Arquivos ocultos no Explorador'
        Description = 'Liga o valor Hidden do Explorador e reinicia a janela. Pastas como AppData e ProgramData e arquivos de configuração que começam com ponto passam a aparecer na listagem. Arquivos protegidos do sistema continuam escondidos: isso é outra opção, separada.'
    }
    'WPFToggleVerboseLogon' = @{
        Content     = 'Mensagens detalhadas no logon'
        Description = 'Liga VerboseStatus e troca o genérico "Bem-vindo" pelo passo exato em que o Windows está: qual política, qual perfil, qual serviço. Serve para descobrir onde um logon lento perde tempo. Não acelera nada por si só.'
    }
    'WPFToggleNewOutlook' = @{
        Content     = 'Nova versão do Microsoft Outlook'
        Description = 'Mexe nas preferências do Outlook 16.0 (UseNewOutlook e a migração automática) para escolher entre o cliente clássico de área de trabalho e o Outlook novo, que é o aplicativo web empacotado. Desligado, o clássico continua sendo aberto e a Microsoft não migra a conta sozinha. Só vale onde o Office está instalado.'
    }
    'WPFToggleScrollbars' = @{
        Content     = 'Barras de rolagem sempre visíveis'
        Description = 'Escreve DynamicScrollbars em Painel de Controle\Acessibilidade. Ligado, a barra fica sempre na largura cheia; desligado, ela encolhe para um traço fino quando o mouse sai de cima. Barra sempre visível é mais fácil de acertar e não faz o conteúdo pular quando aparece.'
    }
    'WPFMultiplaneOverlay' = @{
        Content     = 'Multiplane Overlay (MPO)'
        Description = 'Escreve OverlayTestMode (DWM) e DisableOverlays (GraphicsDrivers), os dois valores que ligam e desligam a composição por camadas que a placa de vídeo faz junto com o Windows. Desligar o MPO é o primeiro teste quando a tela pisca, fica preta por um instante ou mostra faixas em vídeo e em janela acelerada. A escolha vale imediatamente, sem reiniciar.'
    }
    'WPFToggleMouseAcceleration' = @{
        Content     = 'Aceleração do mouse'
        Description = 'Escreve MouseSpeed, MouseThreshold1 e MouseThreshold2 - é o que a caixa "Aprimorar a precisão do ponteiro" grava. Ligada, mover o mouse depressa leva o cursor mais longe do que mover devagar a mesma distância física. Desligada, a relação fica fixa, que é o que se quer para mira em jogo e para memória muscular.'
    }
    'WPFToggleNumLock' = @{
        Content     = 'Num Lock ao iniciar'
        Description = 'Grava InitialKeyboardIndicators no seu perfil e no perfil padrão (HKU\.Default), que é o que vale na tela de entrada. O teclado numérico já começa ligado, sem apertar Num Lock toda vez para digitar a senha. Em notebook sem bloco numérico separado, ligar pode transformar parte das letras em números.'
    }
    'WPFToggleWindowSnapping' = @{
        Content     = 'Encaixe de janelas'
        Description = 'Escreve WindowArrangementActive, o valor por trás do "Ajustar janelas" das Configurações. Ligado, arrastar uma janela até a borda a encaixa em meia tela e oferece as outras para preencher o resto. Desligado, a janela fica exatamente onde você soltou.'
    }
    'WPFToggleStandbyFix' = @{
        Content     = 'Rede durante a suspensão S0'
        Description = 'Escreve a política de energia "Conectividade de rede em espera" para o perfil na tomada. Ligada, o notebook continua na rede durante a suspensão moderna e recebe e-mail e mensagem dormindo; desligada, ele desconecta e gasta bem menos bateria. Só tem efeito em máquina com Modern Standby.'
    }
    'WPFToggleS3Sleep' = @{
        Content     = 'Suspensão S3'
        Description = 'Escreve PlatformAoAcOverride, que manda o Windows ignorar o Modern Standby anunciado pelo firmware e usar a suspensão S3 clássica. Em S3 a CPU é desligada de verdade e só a memória continua alimentada, o que resolve notebook que esquenta e descarrega dentro da mochila. Exige reiniciar e depende de o firmware aceitar.'
    }
    'WPFToggleHideSettingsHome' = @{
        Content     = 'Página inicial das Configurações'
        Description = 'Escreve SettingsPageVisibility com "show:home" ou "hide:home", a política que decide se o aplicativo Configurações tem página inicial. Escondida, ele abre direto na lista de categorias, sem os cartões de recomendação, de conta e de armazenamento. Só muda a navegação; nenhuma opção deixa de existir.'
    }
    'WPFToggleBingSearch' = @{
        Content     = 'Busca do Bing no menu Iniciar'
        Description = 'Escreve BingSearchEnabled, o valor que decide se a caixa do menu Iniciar consulta a web. Desligado, o menu procura só em arquivos, aplicativos e configurações locais, e responde antes por não esperar a internet. Ligado, voltam os resultados do Bing e o resumo por IA.'
    }
    'WPFToggleLoginBlur' = @{
        Content     = 'Desfoque acrílico na tela de logon'
        Description = 'Escreve DisableAcrylicBackgroundOnLogon, a política do efeito acrílico que borra o papel de parede atrás da caixa de senha. Sem o desfoque, o fundo aparece nítido e a tela desenha um pouco mais rápido em máquina sem placa dedicada. É só estético.'
    }
    'WPFTweaksDisableLockscreen' = @{
        Content     = 'Tela de bloqueio - Desativar'
        Description = 'Liga a política NoLockScreen: ao ligar o PC ou acordá-lo, o Windows vai direto para a caixa de senha, sem a imagem que pede um clique ou um Enter antes. É um passo a menos em toda entrada. Somem junto o Windows Spotlight e o que aparecia naquela tela.'
    }
    'WPFToggleStartMenuRecommendations' = @{
        Content     = 'Recomendações do menu Iniciar'
        Description = 'Escreve HideRecommendedSection nas três chaves de política que o Windows 11 consulta (PolicyManager, Explorer e a de ambiente educacional) e reinicia o Explorador. Escondida, a metade de baixo do menu Iniciar deixa de listar arquivos recentes e aplicativos sugeridos. ATENÇÃO: como efeito colateral, isto também desativa o Windows Spotlight na tela de bloqueio.'
    }
    'WPFToggleStickyKeys' = @{
        Content     = 'Teclas de aderência'
        Description = 'Escreve os sinalizadores de Teclas de Aderência em Painel de Controle\Acessibilidade. Com elas ativas, Ctrl, Alt e Shift ficam presos depois de um toque, o que permite fazer Ctrl+Alt+Del com um dedo só. É também o recurso por trás da caixa que aparece do nada quando se aperta Shift cinco vezes seguidas.'
    }
    'WPFToggleTaskbarAlignment' = @{
        Content     = 'Ícones centralizados na barra de tarefas'
        Description = 'Escreve TaskbarAl e reinicia o Explorador: centralizado é o padrão do Windows 11, à esquerda é o arranjo do Windows 10. Encostado na esquerda, o botão Iniciar fica sempre no mesmo canto e não se desloca quando você abre mais um programa.'
    }
    'WPFToggleTaskbarSearch' = @{
        Content     = 'Ícone de pesquisa na barra de tarefas'
        Description = 'Escreve SearchboxTaskbarMode, que decide se a barra de tarefas mostra a caixa de pesquisa inteira, só a lupa ou nada. Esconder libera bastante espaço para ícones de programa. A pesquisa continua a um toque na tecla Windows.'
    }
    'WPFToggleTaskView' = @{
        Content     = 'Ícone de Visão de Tarefas na barra de tarefas'
        Description = 'Escreve ShowTaskViewButton, o botão que abre as áreas de trabalho virtuais e as janelas em miniatura. Escondê-lo não desliga as áreas de trabalho virtuais: elas continuam acessíveis por Win+Tab. É espaço a mais na barra para quem usa o atalho.'
    }
    'WPFToggleGameMode' = @{
        Content     = 'Modo Jogo'
        Description = 'Escreve AllowAutoGameMode e AutoGameModeEnabled em HKCU\Software\Microsoft\GameBar. Com o Modo Jogo ligado, o Windows reconhece o jogo em primeiro plano, segura atualização e reinicialização enquanto ele roda e evita que tarefas de fundo disputem a CPU. O ganho de quadros é pequeno e depende do título; o benefício maior é não ser interrompido no meio de uma partida.'
    }
    'WPFToggleLongPaths' = @{
        Content     = 'Caminhos longos'
        Description = 'Liga LongPathsEnabled, que tira o limite histórico de 260 caracteres no caminho de arquivo para os programas preparados para isso. Resolve o erro de "caminho muito longo" em pastas profundas como node_modules e em projetos com nomes grandes. Programa antigo que não declara suporte continua preso ao limite antigo.'
    }
    'WPFOOSUbutton' = @{
        Content     = 'O&O ShutUp10++ - Executar'
        Description = 'Baixa o O&O ShutUp10++ do site do fabricante e o abre. É um programa de terceiro, com dezenas de opções de privacidade próprias, que não passa pela classificação de risco do WinForge nem entra no Desfazer dele. Precisa de internet, e o que for mudado ali se desfaz dentro do próprio programa.'
    }
    'WPFchangedns' = @{
        Content     = 'DNS - Definir como:'
        Description = 'Escolhe o servidor de nomes que será gravado em todas as placas de rede ativas quando você clicar em aplicar os ajustes - com DNS sobre HTTPS onde o Windows aceita. Trocar por Cloudflare ou Google costuma resolver página que demora a abrir porque o resolvedor do provedor está lento. A opção DHCP devolve o servidor que o roteador informa.'
    }
    'WPFAddUltPerf' = @{
        Content     = 'Plano Desempenho Máximo - Ativar'
        Description = 'Duplica e ativa o plano de energia Desempenho Máximo, que o Windows traz escondido (powercfg /duplicatescheme). Ele corta as micropausas de gerenciamento de energia: o processador não desce de frequência em ocioso e o disco não é desligado, o que ajuda em áudio profissional e em servidor caseiro. Em notebook, a bateria dura bem menos e a máquina esquenta mais.'
    }
    'WPFRemoveUltPerf' = @{
        Content     = 'Plano Desempenho Máximo - Desativar'
        Description = 'Roda "powercfg /restoredefaultschemes" e devolve os planos de energia de fábrica. Serve para voltar atrás depois de ativar o Desempenho Máximo. Repare no alcance do comando: qualquer plano personalizado que você tenha criado some junto.'
    }

    # ---------------------------------------------------------------- aba Configurações: recursos
    'WPFFeaturesdotnet' = @{
        Content     = '.NET Framework (versões 2, 3 e 4) - Ativar'
        Description = 'Habilita pelo DISM os recursos NetFx3, que cobre o .NET 2.0 e 3.5, e NetFx4-AdvSrvs, que traz WCF e ASP.NET do .NET 4. É o que falta quando um programa mais antigo abre pedindo o .NET Framework 3.5. Os arquivos do 3.5 não estão na imagem instalada e vêm do Windows Update, então precisa de internet.'
    }
    # Os cinco botões do grupo "Correções" rodam fora da thread da janela, com a saída ao vivo numa
    # janela própria, e todos passam por uma caixa de Sim/Não antes de agir. A descrição abaixo é a
    # MESMA frase que a caixa mostra (Get-WinForgeRepairConfirmText a lê daqui), então ela precisa
    # dizer o que vai rodar e, onde for o caso, que é preciso reiniciar - não é só uma dica de botão.
    'WPFFixesNTPPool' = @{
        Content     = 'Servidor NTP - Ativar'
        Description = 'Inicia o serviço de Horário do Windows, grava a lista de servidores com o w32tm trocando o time.windows.com padrão pelo pool.ntp.org, reinicia o serviço e força uma sincronização. Resolve relógio que atrasa sozinho e diferença de horário que atrapalha login e validação de certificado. Em máquina de domínio não use este botão: ali quem deve ditar o horário é o controlador de domínio.'
    }
    'WPFFeatureshyperv' = @{
        Content     = 'Hyper-V - Ativar'
        Description = 'Habilita o recurso Microsoft-Hyper-V-All, que traz o hipervisor, o Gerenciador do Hyper-V e o comutador virtual. Com ele dá para criar e rodar máquinas virtuais Windows e Linux direto no sistema. Exige edição Pro ou superior e virtualização ligada na BIOS, pede reinício e passa a conviver mal com VirtualBox e emuladores que querem o hardware de virtualização só para si.'
    }
    'WPFFeatureslegacymedia' = @{
        Content     = 'Componentes de mídia antigos (WMP, DirectPlay) - Ativar'
        Description = 'Habilita os recursos WindowsMediaPlayer, MediaPlayback, DirectPlay e LegacyComponents, que não vêm marcados numa instalação nova. São eles que jogos dos anos 2000 e programas de mídia antigos procuram e não acham. Pede reinício e não altera nada do que já funciona.'
    }
    'WPFFeaturewsl' = @{
        Content     = 'Subsistema do Windows para Linux (WSL) - Ativar'
        Description = 'Habilita VirtualMachinePlatform e Microsoft-Windows-Subsystem-Linux, a base do WSL. Depois de reiniciar, "wsl --install" baixa uma distribuição Linux que roda lado a lado com o Windows, com acesso aos mesmos arquivos e sem dual boot. Como usa o hipervisor, convive mal com VirtualBox e com emuladores Android que pedem virtualização exclusiva.'
    }
    'WPFFeaturenfs' = @{
        Content     = 'Sistema de Arquivos de Rede (NFS) - Ativar'
        Description = 'Habilita o Cliente para NFS e configura o acesso anônimo com UID e GID 0, permissão 755 e autenticação AUTH_SYS. Com isso o Windows monta compartilhamentos NFS de servidores Linux, NAS e ESXi como unidade de rede. Repare no modelo de segurança: AUTH_SYS acredita no que o cliente diz ser, então use só em rede controlada.'
    }
    'WPFFeatureRegBackup' = @{
        Content     = 'Backup do registro (tarefa diária às 00:30) - Ativar'
        Description = 'Liga EnablePeriodicBackup, guarda duas gerações e registra a tarefa AutoRegBackup, que às 00:30 dispara o RegIdleBackup do próprio Windows. Os hives vão para C:\Windows\System32\config\RegBack, de onde dá para recuperar um registro corrompido pelo ambiente de recuperação. A Microsoft desligou esse backup no Windows 10 1803 para economizar disco - cada geração custa algumas centenas de MB.'
    }
    'WPFFeatureEnableLegacyRecovery' = @{
        Content     = 'Recuperação antiga pelo F8 - Ativar'
        Description = 'Roda "bcdedit /set bootmenupolicy legacy" e devolve o menu de inicialização em texto que responde ao F8. Dá para entrar em Modo de Segurança apertando F8 ao ligar, sem depender de o Windows chegar até a recuperação gráfica. Em troca, a inicialização passa a ter uma pequena pausa esperando a tecla.'
    }
    'WPFFeatureDisableLegacyRecovery' = @{
        Content     = 'Recuperação antiga pelo F8 - Desativar'
        Description = 'Roda "bcdedit /set bootmenupolicy standard" e volta ao comportamento padrão do Windows 8 em diante, sem a pausa esperando o F8. A inicialização fica o mais rápida possível. A recuperação continua acessível pelas Configurações ou por três desligamentos forçados seguidos.'
    }
    'WPFFeaturesSandbox' = @{
        Content     = 'Windows Sandbox - Ativar'
        Description = 'Habilita o recurso Containers-DisposableClientVM, uma máquina virtual leve com área de trabalho descartável. Serve para abrir um instalador ou um anexo suspeito isolado do sistema: ao fechar a janela, tudo que aconteceu lá dentro some. Exige edição Pro ou superior, virtualização na BIOS e reinício.'
    }
    'WPFFeatureInstall' = @{
        Content     = 'Instalar recursos'
        Description = 'Habilita pelo DISM os recursos do Windows marcados acima, um a um, com o progresso na barra da janela e no ícone da barra de tarefas. O que já estava ligado é pulado. Vários desses recursos só passam a valer depois de reiniciar o computador.'
    }
    'WPFPanelAutologin' = @{
        Content     = 'Logon automático - Executar'
        Description = 'Baixa o Autologon da Sysinternals e o abre para você preencher usuário, domínio e senha. A partir daí o Windows entra na área de trabalho sozinho ao ligar, o que faz sentido em quiosque, painel de parede e servidor de mídia. A senha fica guardada no registro da máquina: quem tiver acesso físico entra na sua conta.'
    }
    'WPFFixesUpdate' = @{
        Content     = 'Windows Update - Redefinir'
        Description = 'Para os serviços BITS, wuauserv, appidsvc e cryptsvc, apaga a fila de trabalhos do BITS e o log antigo, renomeia a pasta de downloads, registra de novo as DLLs e remove as configurações de WSUS. Vai bem além do Windows Update: apaga a diretiva de grupo local inteira - HKLM\Software\Policies, HKCU\Software\Policies e as chaves CurrentVersion\Policies das duas raízes -, exclui as pastas GroupPolicy e GroupPolicyUsers do System32, roda "secedit /configure /cfg defltbase.inf" seguido de "gpupdate /force" e usa o netsh para redefinir o Winsock, a pilha IP e o proxy do winhttp. Isso apaga também os ajustes do próprio WinForge que moram em diretiva: o enxugamento do Edge e do Brave, o bloqueio de ConsumerFeatures e as políticas de telemetria voltam ao padrão do Windows e precisam ser marcados de novo. O histórico de atualizações é preservado - a renomeação da pasta DataStore, que é o que o apagaria, só acontece no modo agressivo, que este botão não usa. É o que se tenta quando a busca por atualizações trava ou volta sempre com o mesmo código de erro; reinicie o computador no fim.'
    }
    'WPFFixesNetwork' = @{
        Content     = 'Rede - Redefinir'
        Description = 'Redefine a pilha de rede com "netsh winsock reset" e "netsh int ip reset": as configurações de TCP/IP e do Winsock voltam ao padrão do Windows. É o caminho para "conectado, sem internet" e para DNS que parou de resolver depois de um antivírus ou VPN mal desinstalado. O que ele NÃO faz, porque é a confusão mais comum: não reinstala driver, não troca o driver da placa de rede e não mexe em antivírus, firewall nem VPN que ainda estejam instalados. Conexões de VPN ou proxy podem precisar ser refeitas, e é preciso reiniciar o computador para concluir.'
    }
    'WPFPanelDISM' = @{
        Content     = 'Verificação de corrupção do sistema - Executar'
        Description = 'Roda em sequência o chkdsk (verificação do disco do sistema, só leitura), o sfc /scannow (reparo dos arquivos protegidos do Windows) e o DISM /RestoreHealth (reparo da imagem do Windows, que baixa arquivos pela internet). É a trinca padrão para travamento sem causa, erro de DLL e atualização que não instala. Pode levar de vários minutos a mais de uma hora, e a saída aparece ao vivo numa janela.'
    }
    'WPFFixesWinget' = @{
        Content     = 'WinGet - Reinstalar'
        Description = 'Se o winget já responder, não faz nada. Se não responder, instala o provedor NuGet, baixa da Galeria do PowerShell o módulo Microsoft.WinGet.Client e chama o Repair-WinGetPackageManager, que repõe o Gerenciador de Pacotes do Windows para todos os usuários. É o conserto de "winget não é reconhecido" e de erro de fonte de pacotes depois de uma atualização do Windows. Precisa de internet, pode demorar e confia na Galeria do PowerShell como fonte do módulo; os programas já instalados por ele continuam onde estão.'
    }
    'WPFWinForgeSSHServer' = @{
        Content     = 'Servidor OpenSSH - Ativar'
        Description = 'Instala o recurso OpenSSH.Server, põe os serviços sshd e ssh-agent em automático, abre a porta 22 no firewall e prepara o arquivo de chaves autorizadas do administrador. Depois disso dá para entrar nesta máquina por SSH e usar scp de qualquer computador da rede. É um serviço de entrada exposto: ligue só em rede que você controla, e prefira chave a senha.'
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
    # Duas frases por entrada: o que o programa é e por que alguém o instalaria.
    'WPFInstall1password' = @{ Description = 'Gerenciador de senhas comercial, com cofre criptografado sincronizado entre computador, celular e navegador. Instale se você já assina o serviço e quer o aplicativo nativo em vez da extensão sozinha.' }
    'WPFInstall7zip' = @{ Description = 'Compactador livre que abre praticamente todo formato de arquivo (zip, rar, 7z, iso, tar) e comprime melhor que o Explorador. É o primeiro programa que se instala numa máquina nova quando o assunto é abrir arquivo baixado.' }
    'WPFInstalladobe' = @{ Description = 'Leitor de PDF gratuito da Adobe, com assinatura digital, preenchimento de formulário e anotação. Instale quando o PDF precisa se comportar exatamente como o autor previu - formulário corporativo e documento assinado, por exemplo.' }
    'WPFInstalladvancedip' = @{ Description = 'Varredor de rede local que lista em segundos todos os dispositivos ligados, com IP, nome, fabricante e portas abertas. Serve para achar a impressora, a câmera ou o aparelho que ninguém sabe onde está.' }
    'WPFInstallaimp' = @{ Description = 'Reprodutor de música leve, com equalizador, suporte a lista de reprodução e a formatos sem perda como FLAC e APE. Boa escolha para quem tem biblioteca em arquivo e não quer serviço por assinatura.' }
    'WPFInstallanydesk' = @{ Description = 'Acesso remoto com conexão rápida e imagem fluida, feito para dar suporte em máquina de outra pessoa. Instale nas duas pontas quando precisar resolver o problema de alguém sem ir até lá.' }
    'WPFInstallautoruns' = @{ Description = 'Utilitário da Sysinternals que lista TUDO que inicia junto com o Windows: programas, serviços, tarefas agendadas, extensões de shell e drivers. É a ferramenta certa para caçar o que deixa o boot lento ou o que volta sozinho depois de removido.' }
    'WPFInstallaudacity' = @{ Description = 'Editor de áudio livre para gravar, cortar, normalizar e remover ruído de faixas. Instale para limpar uma gravação de reunião, de podcast ou de narração sem pagar por suíte profissional.' }
    'WPFInstallautohotkey' = @{ Description = 'Linguagem de script que transforma qualquer combinação de teclas em uma ação: abrir programa, digitar texto pronto, remapear tecla, automatizar janela. Vale o aprendizado para quem repete a mesma sequência de cliques dezenas de vezes por dia.' }
    'WPFInstallbattlenet' = @{ Description = 'Loja e lançador da Blizzard e da Activision, por onde passam World of Warcraft, Diablo, Overwatch e Call of Duty. Instale se você joga algum desses títulos: não há outro caminho para baixá-los.' }
    'WPFInstallbitwarden' = @{ Description = 'Gerenciador de senhas de código aberto, com cofre criptografado na nuvem e plano gratuito sem limite de senhas. Boa porta de entrada para quem ainda repete a mesma senha em vários sites.' }
    'WPFInstallblender' = @{ Description = 'Suíte 3D completa e gratuita: modelagem, escultura, animação, simulação, renderização e edição de vídeo num programa só. Instale para trabalhar com 3D sem licença cara, do brinquedo ao trabalho profissional.' }
    'WPFInstallbrave' = @{ Description = 'Navegador baseado no Chromium que bloqueia anúncio e rastreador por padrão, sem precisar de extensão. Instale para páginas que carregam mais rápido e para não ser seguido de site em site.' }
    'WPFInstallbulkcrapuninstaller' = @{ Description = 'Desinstalador em lote que remove vários programas de uma vez e ainda varre pastas e chaves de registro deixadas para trás. É o que se usa depois de limpar uma máquina cheia de software de fábrica.' }
    'WPFInstallcalibre' = @{ Description = 'Biblioteca de e-books que organiza a coleção, converte entre EPUB, MOBI e PDF e envia direto para o leitor digital. Instale para deixar de depender da loja de cada fabricante.' }
    'WPFInstallchatgpt' = @{ Description = 'Aplicativo oficial do ChatGPT para Windows, distribuído pela Microsoft Store. Instale para ter a conversa numa janela própria, com atalho de teclado, em vez de mais uma aba do navegador.' }
    'WPFInstallchrome' = @{ Description = 'Navegador do Google, o mais usado do mundo e o alvo de compatibilidade de praticamente todo site. Instale como segundo navegador para o sistema interno que só funciona nele.' }
    'WPFInstallcinebenchr23' = @{ Description = 'Teste de desempenho que mede a CPU renderizando uma cena 3D real e devolve uma pontuação comparável com a de outras máquinas. Serve para conferir se o processador entrega o esperado depois de um overclock ou de trocar a pasta térmica.' }
    'WPFInstallclaude' = @{ Description = 'Aplicativo da Anthropic para conversar com o Claude numa janela dedicada, com histórico e anexos. Instale para trabalhar com apoio de IA sem a distração do navegador aberto.' }
    'WPFInstallcpuz' = @{ Description = 'Identificador de hardware que mostra modelo exato de processador, placa-mãe, chipset e cada pente de memória, com clock e tensão em tempo real. É a forma mais rápida de saber o que há dentro da máquina antes de comprar peça.' }
    'WPFInstallcrystaldiskinfo' = @{ Description = 'Lê os contadores SMART dos discos e traduz em um estado simples: bom, atenção ou ruim, com temperatura, horas ligado e setores realocados. Instale para ser avisado do HD ou SSD que está morrendo antes de perder os arquivos.' }
    'WPFInstallcrystaldiskmark' = @{ Description = 'Mede a velocidade de leitura e escrita do disco em blocos grandes e pequenos, sequencial e aleatório. Serve para conferir se o SSD novo entrega o que a caixa prometeu ou se o pen drive é falsificado.' }
    'WPFInstallcursor' = @{ Description = 'Editor de código baseado no VS Code com IA integrada ao fluxo: completar, explicar e reescrever trechos dentro do próprio arquivo. Instale se você programa e quer o assistente dentro do editor, não numa aba ao lado.' }
    'WPFInstallddu' = @{ Description = 'Remove por completo driver de vídeo NVIDIA, AMD e Intel, inclusive as sobras que o desinstalador oficial deixa no registro e nas pastas. É o passo obrigatório antes de trocar de marca de placa ou de resolver tela preta causada por driver.' }
    'WPFInstalldiscord' = @{ Description = 'Plataforma de voz, vídeo e texto organizada em servidores e canais, nascida entre jogadores e hoje usada por comunidades de todo tipo. Instale para o aplicativo nativo, que tem sobreposição em jogo e push-to-talk que a versão web não tem.' }
    'WPFInstalldockerdesktop' = @{ Description = 'Roda contêineres Linux no Windows sobre o WSL 2, com interface para imagens, volumes e redes. Instale para desenvolver com o mesmo ambiente que vai para o servidor, sem instalar banco e serviço direto na máquina.' }
    'WPFInstalldotnet6' = @{ Description = 'Ambiente de execução do .NET 6 para aplicativos de área de trabalho (Windows Forms e WPF). Instale quando um programa se recusa a abrir pedindo o .NET Desktop Runtime 6.' }
    'WPFInstalldotnet8' = @{ Description = 'Ambiente de execução do .NET 8 para aplicativos de área de trabalho (Windows Forms e WPF). Instale quando um programa se recusa a abrir pedindo o .NET Desktop Runtime 8.' }
    'WPFInstalldotnet10' = @{ Description = 'Ambiente de execução do .NET 10 para aplicativos de área de trabalho (Windows Forms e WPF). Instale quando um programa se recusa a abrir pedindo o .NET Desktop Runtime 10.' }
    'WPFInstalldropbox' = @{ Description = 'Cliente de armazenamento em nuvem que sincroniza uma pasta do computador com o servidor e com os outros dispositivos. Instale se a sua equipe ou o seu backup já vivem no Dropbox.' }
    'WPFInstalleaapp' = @{ Description = 'Loja e lançador da Electronic Arts, por onde passam FIFA, Battlefield, The Sims e Apex Legends. Instale se você joga algum título da EA: é por ele que o jogo baixa e atualiza.' }
    'WPFInstalleartrumpet' = @{ Description = 'Controle de volume por aplicativo na área de notificação, com troca rápida de dispositivo de saída e de entrada. Resolve a vida de quem alterna entre fone e caixa de som ou quer abaixar só o navegador.' }
    'WPFInstalledge' = @{ Description = 'Navegador da Microsoft baseado no Chromium, integrado à conta corporativa e ao Windows Hello. Instale para reinstalar o Edge depois de removê-lo, ou se você precisa dele para um site interno.' }
    'WPFInstallepicgames' = @{ Description = 'Loja e lançador da Epic, com Fortnite e um jogo gratuito por semana. Instale para resgatar esses gratuitos e para os títulos que saem só nessa loja.' }
    'WPFInstallfirefox' = @{ Description = 'Navegador da Mozilla, o único grande que não usa o motor do Chromium, com isolamento de cookies por site e perfis separados. Instale para não ficar dependente de um motor só e para usar extensões que o Chrome não permite mais.' }
    'WPFInstallflux' = @{ Description = 'Reduz o azul da tela conforme o horário, deixando a imagem mais quente à noite. Ajuda quem trabalha até tarde e sente os olhos cansados ou demora a pegar no sono.' }
    'WPFInstallfoxpdfreader' = @{ Description = 'Leitor de PDF leve, com interface em faixa de opções parecida com a do Office, anotação e preenchimento de formulário. Alternativa ao Acrobat para quem acha o da Adobe pesado demais.' }
    'WPFInstallgeforcenow' = @{ Description = 'Cliente de jogo em nuvem da NVIDIA: o jogo roda no servidor dela e chega aqui como vídeo. Instale para jogar título pesado em máquina fraca, desde que a internet seja estável.' }
    'WPFInstallgimp' = @{ Description = 'Editor de imagem em bitmap, livre e completo: camadas, máscaras, seleção por cor, retoque e filtros. Instale para o que o Paint não faz quando não se quer pagar Photoshop.' }
    'WPFInstallgit' = @{ Description = 'Sistema de controle de versão distribuído, base do GitHub e de quase todo projeto de software. Instale para clonar repositório, acompanhar histórico e poder voltar atrás em qualquer arquivo de texto.' }
    'WPFInstallgithubdesktop' = @{ Description = 'Interface gráfica para Git focada em GitHub: clonar, criar ramo, ver diferença e enviar alteração sem linha de comando. Instale se você trabalha com repositório mas não quer decorar comandos.' }
    'WPFInstallgog' = @{ Description = 'Loja e lançador da GOG, especializada em jogos sem DRM e em clássicos ajustados para rodar em Windows moderno. Instale para ter os jogos como arquivo que continua funcionando mesmo sem a loja.' }
    'WPFInstallgolang' = @{ Description = 'A linguagem Go, compilada e de tipagem estática, feita para gerar um executável único e rodar bem em servidor. Instale para compilar projeto em Go ou usar ferramentas distribuídas nessa forma.' }
    'WPFInstallgoogledrive' = @{ Description = 'Cliente do Google Drive que monta a nuvem como unidade no Explorador, baixando o arquivo só quando ele é aberto. Instale para chegar aos documentos da conta Google sem ocupar disco.' }
    'WPFInstallgpuz' = @{ Description = 'Mostra tudo sobre a placa de vídeo: modelo exato do chip, memória, BIOS, clock, temperatura e uso em tempo real. Serve para conferir se a placa usada que você comprou é mesmo o que o anúncio dizia.' }
    'WPFInstallhandbrake' = @{ Description = 'Conversor de vídeo livre que reempacota quase qualquer arquivo em H.264, H.265 ou AV1, com perfis prontos por dispositivo. Instale para reduzir o tamanho de um acervo de vídeo ou fazer um arquivo tocar na TV.' }
    'WPFInstallhwinfo' = @{ Description = 'Monitor de hardware que lê todos os sensores da máquina: temperatura por núcleo, tensão, rotação de ventoinha, consumo e frequência. É a ferramenta de referência para diagnosticar superaquecimento e queda de clock.' }
    'WPFInstallhwmonitor' = @{ Description = 'Leitor de sensores enxuto, com temperatura, tensão e ventoinha numa árvore simples, sem configuração. Instale quando quiser só olhar a temperatura rápido, sem a complexidade do HWiNFO.' }
    'WPFInstallimageglass' = @{ Description = 'Visualizador de imagem leve e de código aberto, com suporte a WEBP, HEIC, SVG e RAW que o visualizador do Windows não abre. Instale para trocar o visualizador padrão por algo que abre na hora.' }
    'WPFInstallinternetdownloadmanager' = @{ Description = 'Gerenciador de downloads comercial que divide o arquivo em partes paralelas, retoma transferência interrompida e captura links do navegador. Instale em conexão instável ou para baixar arquivo grande sem começar do zero a cada queda.' }
    'WPFInstallirfanview' = @{ Description = 'Visualizador de imagem minúsculo e instantâneo, com conversão e renomeação em lote e edição básica. Instale para abrir mil fotos de uma pasta sem esperar e para converter tudo de uma vez.' }
    'WPFInstallitunes' = @{ Description = 'Reprodutor e biblioteca de mídia da Apple, também usado para sincronizar, atualizar e fazer backup de iPhone e iPad no Windows. Instale se você tem aparelho da Apple e usa PC.' }
    'WPFInstalljava21' = @{ Description = 'Distribuição gratuita do OpenJDK 21 mantida pela Amazon, com suporte de longo prazo e sem a licença comercial da Oracle. Instale para rodar ou compilar programa Java sem se preocupar com licenciamento.' }
    'WPFInstalljetbrains' = @{ Description = 'Instalador e atualizador das IDEs da JetBrains (IntelliJ, PyCharm, Rider, WebStorm), com controle de versão e de licença num lugar só. Instale se você usa mais de uma dessas ferramentas.' }
    'WPFInstallkeepassxc' = @{ Description = 'Gerenciador de senhas de código aberto que guarda tudo num arquivo criptografado no seu disco, sem servidor nem assinatura - você decide se e onde sincroniza. Instale quando o cofre não pode depender da nuvem de terceiro.' }
    'WPFInstallklite' = @{ Description = 'Conjunto de codecs de áudio e vídeo com reprodutor incluído, que faz o Windows abrir formato que ele não conhece de fábrica. Instale quando um vídeo abre sem imagem ou sem som no reprodutor padrão.' }
    'WPFInstallkodi' = @{ Description = 'Central de mídia que transforma o computador numa interface de TV para filmes, séries e música guardados em disco ou na rede, com capa e sinopse baixadas automaticamente. Instale no PC ligado à televisão.' }
    'WPFInstalllibreoffice' = @{ Description = 'Suíte de escritório gratuita com editor de texto, planilha e apresentação, que lê e grava os formatos do Microsoft Office. Instale onde não há licença do Office e ainda é preciso trocar documento com quem tem.' }
    'WPFInstalllibrewolf' = @{ Description = 'Firefox recompilado com a telemetria removida e as proteções contra rastreamento no máximo desde a instalação. Instale para ter a privacidade ajustada de fábrica, sem mexer em dezenas de opções.' }
    'WPFInstalllocalsend' = @{ Description = 'Envia arquivo entre computador, celular e tablet pela rede local, sem nuvem, sem conta e sem cabo - funciona entre Windows, Android, iOS, macOS e Linux. É a alternativa aberta ao AirDrop para quem mistura plataformas.' }
    'WPFInstallmpv' = @{ Description = 'Reprodutor de vídeo minimalista e muito rápido, que abre praticamente tudo sem codec extra e é controlado por teclado. Instale para assistir sem interface no caminho e para arquivo que trava em outros reprodutores.' }
    'WPFInstallminitoolpartitionwizard' = @{ Description = 'Gerenciador de partições que redimensiona, move, une e converte volume sem apagar dados, incluindo MBR para GPT. Instale para reorganizar o disco quando o Gerenciamento de Disco do Windows recusa a operação.' }
    'WPFInstallmoonlight' = @{ Description = 'Cliente livre que transmite o jogo rodando no seu PC para outro aparelho da rede, com baixa latência. Instale para jogar na TV ou no notebook fraco usando a placa de vídeo da máquina principal.' }
    'WPFInstallmpchc' = @{ Description = 'Reprodutor de vídeo clássico, leve, com interface simples e filtros próprios para quase todo formato. Instale em máquina antiga, onde reprodutor moderno pesa demais.' }
    'WPFInstallmsiafterburner' = @{ Description = 'Ajusta clock, tensão, limite de energia e curva de ventoinha da placa de vídeo, de qualquer marca, e traz o RivaTuner para mostrar quadros por segundo na tela. Instale para fazer undervolt, baixar a temperatura ou medir desempenho em jogo.' }
    'WPFInstallnanazip' = @{ Description = 'Compactador derivado do 7-Zip, empacotado como aplicativo moderno e integrado ao menu de contexto do Windows 11. Instale para ter a compressão do 7-Zip sem o menu antigo escondido em "Mostrar mais opções".' }
    'WPFInstalltailscale' = @{ Description = 'Rede privada baseada em WireGuard que liga os seus dispositivos entre si como se estivessem na mesma rede local, atravessando roteador e provedor sem abrir porta. Instale para chegar ao computador de casa de qualquer lugar sem montar VPN à mão.' }
    'WPFInstallnaps2' = @{ Description = 'Digitalizador simples que fala com scanner WIA e TWAIN, junta várias páginas num PDF e reconhece texto por OCR. Instale para não depender do programa pesado que vem com a multifuncional.' }
    'WPFInstallnodejslts' = @{ Description = 'Ambiente de execução JavaScript fora do navegador, na versão com suporte de longo prazo, com o gerenciador de pacotes npm junto. Instale para rodar ferramenta de desenvolvimento web ou servidor escrito em JavaScript.' }
    'WPFInstallnotepadplus' = @{ Description = 'Editor de texto e código leve, com abas, realce de sintaxe, busca e substituição em pasta inteira e recuperação do que não foi salvo. É o substituto natural do Bloco de Notas.' }
    'WPFInstallnvclean' = @{ Description = 'Instala o driver NVIDIA escolhendo o que entra: só o driver de vídeo, sem GeForce Experience, sem telemetria e sem componente que você não usa. Instale para uma instalação enxuta ou para escapar de serviço de fundo da NVIDIA.' }
    'WPFInstallobs' = @{ Description = 'Grava a tela e transmite ao vivo montando cenas com várias fontes: jogo, câmera, imagem e áudio separados. É o padrão de fato para quem faz vídeo, aula ou transmissão a partir do PC.' }
    'WPFInstallobsidian' = @{ Description = 'Bloco de anotações em arquivos Markdown guardados no seu disco, com links entre notas e visão de grafo. Instale para construir uma base de conhecimento que continua legível mesmo sem o programa.' }
    'WPFInstallonedrive' = @{ Description = 'Cliente de nuvem da Microsoft, integrado ao Windows e ao Office, com arquivos sob demanda e histórico de versão. Instale para reinstalá-lo depois de removido ou para usar a cota que vem com a assinatura do Microsoft 365.' }
    'WPFInstallonlyoffice' = @{ Description = 'Suíte de escritório gratuita com a melhor fidelidade aos formatos DOCX, XLSX e PPTX entre as alternativas livres. Instale quando o documento precisa voltar para alguém que usa Microsoft Office sem a formatação quebrar.' }
    'WPFInstallopenrgb' = @{ Description = 'Controla a iluminação RGB de placa-mãe, memória, ventoinha, teclado e mouse de marcas diferentes num programa só, sem serviço de fundo de cada fabricante. Instale para tirar da máquina três ou quatro utilitários proprietários.' }
    'WPFInstallOpenVPN' = @{ Description = 'Cliente do protocolo OpenVPN, que importa o arquivo .ovpn do servidor e abre o túnel criptografado. Instale para conectar à VPN da empresa ou a um servidor próprio.' }
    'WPFInstallOVirtualBox' = @{ Description = 'Virtualizador gratuito da Oracle para rodar outro sistema operacional numa janela, com pasta compartilhada e instantâneo de estado. Instale para testar Linux ou outra versão do Windows sem mexer na instalação real.' }
    'WPFInstallprocessexplorer' = @{ Description = 'Gerenciador de tarefas da Sysinternals que mostra a árvore de processos, qual arquivo ou DLL cada um segurou e a assinatura digital de cada executável. É o que se usa para descobrir quem está travando um arquivo ou consumindo a CPU.' }
    'WPFInstallPaintdotnet' = @{ Description = 'Editor de imagem no meio do caminho entre o Paint e o Photoshop: camadas, seleção, efeitos e plugins, com interface fácil. Instale para edição do dia a dia sem a curva de aprendizado do GIMP.' }
    'WPFInstallparsec' = @{ Description = 'Área de trabalho remota com vídeo comprimido por hardware e latência baixa o bastante para jogar e editar vídeo à distância. Instale para usar a máquina potente de casa a partir de um notebook qualquer.' }
    'WPFInstallpeazip' = @{ Description = 'Compactador livre com interface de dois painéis, suporte a mais de 200 formatos e criptografia forte com arquivo de chave. Instale quando o 7-Zip não abre o formato ou quando você quer proteger o pacote com senha.' }
    'WPFInstallpdf24creator' = @{ Description = 'Conjunto de ferramentas de PDF com impressora virtual: juntar, dividir, girar, comprimir, converter e assinar, tudo no computador. Instale para resolver PDF sem enviar documento para site de terceiro.' }
    'WPFInstallplaynite' = @{ Description = 'Reúne numa biblioteca só os jogos de Steam, Epic, GOG, Xbox, Battle.net e emuladores, com capa e tempo jogado. Instale quando você não lembra mais em qual loja comprou cada jogo.' }
    'WPFInstallplexdesktop' = @{ Description = 'Cliente do Plex para assistir ao acervo do seu servidor de mídia com interface de TV, legenda e retomada de onde parou. Instale no PC que consome o Plex Media Server da casa.' }
    'WPFInstallpostman' = @{ Description = 'Cliente de API para montar requisição HTTP, guardar coleções, variáveis de ambiente e testes automáticos. Instale para experimentar e documentar API sem escrever código descartável.' }
    'WPFInstallpowershell' = @{ Description = 'A versão 7 do PowerShell, multiplataforma e de código aberto, instalada lado a lado com o Windows PowerShell 5.1 que já vem no sistema. Instale para ter sintaxe e cmdlets novos sem perder o que já funciona no 5.1.' }
    'WPFInstallpowertoys' = @{ Description = 'Coleção oficial de utilitários da Microsoft: FancyZones para dividir a tela, PowerRename para renomear em lote, seletor de cor, extrator de texto de imagem e busca rápida. Instale para ganhar uma dúzia de recursos que o Windows deveria ter.' }
    'WPFInstallprismlauncher' = @{ Description = 'Lançador de Minecraft de código aberto que separa instâncias, cada uma com sua versão, seus mods e seu modpack. Instale para manter vários mundos modificados sem um quebrar o outro.' }
    'WPFInstallprocesslasso' = @{ Description = 'Ajusta automaticamente prioridade e afinidade de CPU dos processos, segurando o programa que tenta monopolizar o processador. Ajuda a manter o sistema respondendo enquanto compila, renderiza ou compacta algo pesado.' }
    'WPFInstallprotonvpn' = @{ Description = 'Serviço de VPN suíço sem registro de atividade, com plano gratuito e recursos como Secure Core e saída pela rede Tor. Instale para navegar em rede pública sem expor o tráfego.' }
    'WPFInstallprocessmonitor' = @{ Description = 'Ferramenta da Sysinternals que registra em tempo real cada acesso a arquivo, a registro, a rede e a processo, com filtro por programa. É o último recurso quando um software falha e ninguém sabe o que ele foi procurar.' }
    'WPFInstallputty' = @{ Description = 'Cliente SSH, Telnet e console serial minúsculo, que não precisa de instalação e guarda sessões salvas. Instale para acessar servidor, roteador ou switch pela porta serial ou pela rede.' }
    'WPFInstallpython3' = @{ Description = 'Interpretador Python 3 com o gerenciador de pacotes pip, base de ferramentas de automação, análise de dados e aprendizado de máquina. Instale para rodar script em Python ou começar a programar.' }
    'WPFInstallqbittorrent' = @{ Description = 'Cliente BitTorrent livre, sem anúncio e sem software embutido, com busca integrada e interface web opcional. Instale como substituto direto dos clientes que passaram a vir com propaganda.' }
    'WPFInstallrevo' = @{ Description = 'Desinstalador que roda o removedor oficial e depois varre disco e registro atrás do que ficou, com modo de monitorar a instalação para desfazê-la por completo. Instale para tirar programa teimoso que volta ou deixa rastro.' }
    'WPFInstallrufus' = @{ Description = 'Grava ISO em pen drive inicializável, com opções para contornar as exigências de TPM e conta Microsoft na instalação do Windows 11. É a ferramenta padrão para preparar mídia de instalação.' }
    'WPFInstallrustlang' = @{ Description = 'Cadeia de compilação da linguagem Rust (compilador e gerenciador cargo), com a compilação para Windows que usa as bibliotecas da Microsoft. Instale para compilar projeto em Rust ou ferramentas distribuídas em código-fonte.' }
    'WPFInstallsdio' = @{ Description = 'Atualizador de driver livre, com um acervo enorme que pode ser baixado inteiro e usado sem internet. Instale para achar driver de máquina antiga ou para preparar um pen drive de manutenção.' }
    'WPFInstallsharex' = @{ Description = 'Captura de tela e gravação livre, com rolagem de página, anotação, OCR e envio automático para onde você escolher. Instale para substituir a Ferramenta de Captura e o print seguido de colar no Paint.' }
    'WPFInstallsignal' = @{ Description = 'Mensageiro com criptografia de ponta a ponta por padrão, sem coleta de metadados e mantido por uma fundação sem fins lucrativos. Instale para conversa que precisa ficar entre as duas partes.' }
    'WPFInstallslack' = @{ Description = 'Ferramenta de comunicação de equipe organizada em canais, com histórico pesquisável e integração com outros serviços. Instale se a sua empresa já usa: o aplicativo tem notificação e chamada que a versão web não entrega igual.' }
    'WPFInstallstartallback' = @{ Description = 'Devolve ao Windows 11 o menu Iniciar, a barra de tarefas e o Explorador no formato do Windows 10 ou 7, incluindo barra em outra borda da tela. Programa pago, com período de teste; instale se a interface nova atrapalha o seu jeito de trabalhar.' }
    'WPFInstallsteam' = @{ Description = 'A maior loja de jogos para PC, com biblioteca na nuvem, conquistas, oficina de mods e jogo remoto entre dispositivos. Instale se você tem qualquer jogo comprado ali.' }
    'WPFInstallsublimetext' = @{ Description = 'Editor de texto comercial conhecido por abrir arquivo gigante instantaneamente e por edição em múltiplos cursores. Instale para mexer em log de centenas de MB que trava outros editores.' }
    'WPFInstallsumatra' = @{ Description = 'Leitor de PDF, EPUB, MOBI, CBZ e DjVu que abre praticamente no instante do clique e ocupa poucos MB. Instale em máquina fraca ou quando você só quer ler o documento, sem editar nada.' }
    'WPFInstalltcpview' = @{ Description = 'Ferramenta da Sysinternals que lista cada conexão TCP e UDP aberta, com o processo dono, o endereço remoto e o tráfego de cada uma. Serve para descobrir qual programa está falando com a internet sem avisar.' }
    'WPFInstallteams' = @{ Description = 'Plataforma de reunião, chamada e bate-papo da Microsoft, integrada ao Microsoft 365 e ao calendário do Outlook. Instale se a sua empresa marca reunião por ele.' }
    'WPFInstallteamviewer' = @{ Description = 'Acesso remoto amplamente usado em suporte, que atravessa roteador sem configuração e tem versão portátil para o lado atendido. Instale quando precisar acessar uma máquina que não é sua, com a pessoa presente.' }
    'WPFInstallteamspeak6' = @{ Description = 'Cliente de voz para grupo, com servidor próprio, baixa latência e consumo de banda pequeno, na versão 6. Instale se o seu grupo mantém um servidor TeamSpeak em vez de usar Discord.' }
    'WPFInstalltelegram' = @{ Description = 'Mensageiro em nuvem com histórico sincronizado entre dispositivos, envio de arquivo grande e canais públicos. Instale para o aplicativo nativo, mais rápido que a versão web e com notificação confiável.' }
    'WPFInstallterminal' = @{ Description = 'Terminal moderno da Microsoft com abas, painéis divididos, perfis por shell (PowerShell, cmd, WSL) e aceleração por GPU. Instale para parar de abrir três janelas de console diferentes.' }
    'WPFInstallthunderbird' = @{ Description = 'Cliente de e-mail livre da Mozilla, com várias contas IMAP e POP, calendário, agenda e filtros locais. Instale para ler e guardar o e-mail no seu computador em vez de depender do webmail.' }
    'WPFInstalltor' = @{ Description = 'Navegador que encaminha todo o tráfego pela rede Tor, em três saltos, para esconder de onde a conexão parte. Instale quando o anonimato importa mais que a velocidade.' }
    'WPFInstalltotalcommander' = @{ Description = 'Gerenciador de arquivos de dois painéis, com comparação de pastas, renomeação em lote, cliente FTP e tudo operável pelo teclado. Programa pago, com teste sem prazo; instale para mover arquivo em volume sem tirar a mão do teclado.' }
    'WPFInstalltreesize' = @{ Description = 'Mostra o tamanho de cada pasta em árvore ordenada, do maior para o menor, para achar quem comeu o disco. Instale quando o C: enche e ninguém sabe por quê.' }
    'WPFInstallttaskbar' = @{ Description = 'Deixa a barra de tarefas transparente ou opaca conforme a situação: janela maximizada, menu Iniciar aberto, área de trabalho à mostra. É personalização visual, com consumo próximo de zero.' }
    'WPFInstallubisoft' = @{ Description = 'Loja e lançador da Ubisoft, por onde passam Assassin''s Creed, Far Cry e Rainbow Six. Instale se joga algum título da casa: mesmo comprado em outra loja, ele costuma exigir este cliente.' }
    'WPFInstalleverything' = @{ Description = 'Busca arquivo por nome instantaneamente lendo o índice do próprio NTFS, em vez do índice do Windows - digitar e achar é a mesma coisa. Instale para nunca mais esperar a pesquisa do Explorador.' }
    'WPFInstallvc2015_32' = @{ Description = 'Bibliotecas de execução do Visual C++ 2015 a 2022 na versão de 32 bits. Instale quando um programa reclama de VCRUNTIME140.dll ou MSVCP140.dll ausente - vários jogos e utilitários dependem delas.' }
    'WPFInstallvc2015_64' = @{ Description = 'Bibliotecas de execução do Visual C++ 2015 a 2022 na versão de 64 bits. Instale junto com a de 32 bits: a maioria das máquinas precisa das duas, porque programa antigo continua sendo de 32 bits.' }
    'WPFInstallventoy' = @{ Description = 'Prepara o pen drive uma vez e depois basta copiar arquivos ISO para dentro dele - no boot aparece um menu para escolher qual iniciar. Instale para carregar Windows, Linux e ferramentas de resgate num pen drive só.' }
    'WPFInstallvisualstudio2022' = @{ Description = 'IDE completa da Microsoft para C#, C++, .NET e desenvolvimento web, com depurador, perfilador e designer visual. Instale para trabalhar com projeto .NET de verdade; ocupa vários GB conforme as cargas escolhidas.' }
    'WPFInstallvivaldi' = @{ Description = 'Navegador baseado no Chromium com abas empilhadas, painel lateral, anotações e atalhos de mouse - quase tudo é configurável. Instale se você mantém dezenas de abas abertas e quer organizá-las.' }
    'WPFInstallvlc' = @{ Description = 'Reprodutor que abre praticamente qualquer arquivo de áudio e vídeo sem codec extra, inclusive DVD, transmissão de rede e arquivo corrompido pela metade. É o primeiro reprodutor a instalar numa máquina nova.' }
    'WPFInstallvscode' = @{ Description = 'Editor de código gratuito da Microsoft, com depurador, integração com Git e um catálogo enorme de extensões para qualquer linguagem. É o editor mais usado hoje e serve tanto para script solto quanto para projeto grande.' }
    'WPFInstallwhatsapp' = @{ Description = 'Aplicativo oficial do WhatsApp para Windows, distribuído pela Microsoft Store, com conversa e chamada no computador. Instale para digitar no teclado de verdade em vez de no celular.' }
    'WPFInstallwingetui' = @{ Description = 'Interface gráfica para winget, Chocolatey, Scoop e npm: procurar, instalar, atualizar tudo de uma vez e ver o que tem versão nova. Instale para manter os programas atualizados sem abrir o terminal.' }
    'WPFInstallwinrar' = @{ Description = 'Compactador comercial dono do formato RAR, com recuperação de arquivo danificado e divisão em volumes. Instale se você recebe .rar com frequência e quer também criá-los.' }
    'WPFInstallwinscp' = @{ Description = 'Cliente gráfico de SFTP, FTP e SCP com dois painéis, sincronização de pastas e editor embutido. Instale para enviar arquivo a servidor Linux arrastando, em vez de decorar comandos.' }
    'WPFInstallwireguard' = @{ Description = 'Cliente do protocolo WireGuard, bem mais simples e rápido que OpenVPN e IPsec, com túnel que sobe em instantes. Instale para conectar a uma VPN própria ou ao seu roteador de casa.' }
    'WPFInstallwireshark' = @{ Description = 'Analisador de protocolos que captura os pacotes da rede e os decodifica camada por camada, com filtro por endereço, porta ou conteúdo. Instale para investigar conexão que falha e ver exatamente o que a máquina mandou.' }
    'WPFInstallwiztree' = @{ Description = 'Analisador de espaço em disco que lê a tabela do NTFS direto e varre um SSD inteiro em segundos, muito antes de qualquer concorrente. Instale quando o disco encheu e você quer a resposta agora.' }
    'WPFInstallzoom' = @{ Description = 'Plataforma de videoconferência com sala, gravação e divisão em grupos, que funciona bem em conexão ruim. Instale se as reuniões de que você participa acontecem nela.' }
    'WPFInstalltightvnc' = @{ Description = 'Servidor e cliente VNC livres para controlar outro computador pela rede local, leve e sem serviço na nuvem. Instale para acessar uma máquina da sua própria rede sem depender de servidor de terceiro.' }
    'WPFInstallZenBrowser' = @{ Description = 'Navegador construído sobre o Firefox, com abas na lateral, espaços separados por contexto e visual enxuto. Instale para o motor da Mozilla numa interface pensada para quem trabalha com muitas abas.' }
    'WPFInstallCloudflareWARP' = @{ Description = 'Encaminha o tráfego pela rede da Cloudflare e usa o DNS 1.1.1.1, com plano gratuito ilimitado. Instale para proteger a navegação em rede pública e, às vezes, melhorar a rota até serviços que passam pela Cloudflare.' }
}
#endregion
