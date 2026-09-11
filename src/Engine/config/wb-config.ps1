#region ===== WinForge - configurações adicionais =====

# Entradas do WinUtil que só fazem sentido no Windows 11 (ficam ocultas no Windows 10)
$sync.WinForgeWin11OnlyTweaks = @(
    "WPFTweaksWidget",                  # Widgets da barra de tarefas
    "WPFTweaksRevertStartMenu",         # Layout antigo do menu Iniciar (25H2)
    "WPFTweaksRightClickMenu",          # Menu de contexto clássico
    "WPFTweaksRemoveHomeAndGallery",    # Início e Galeria do Explorador
    "WPFTweaksEndTaskOnTaskbar",        # "Finalizar tarefa" no clique direito da barra
    "WPFToggleTaskbarAlignment",        # Ícones centralizados
    "WPFToggleStartMenuRecommendations",# Recomendações do menu Iniciar
    "WPFToggleHideSettingsHome"         # Página inicial de Configurações
)
$sync.WinForgeWin11OnlyAppx = @(
    "WPFAppxClipchamp_Clipchamp",
    "WPFAppxMicrosoft_WindowsDevHome",
    "WPFAppxMicrosoft_WindowsCrossDevice",
    "WPFAppxMicrosoft_StartExperiencesApp",
    "WPFAppxMSTeams"
)

# ---------------------------------------------------------------------------
# Tweaks do WinForge (mesclados em $sync.configs.tweaks)
#   panel 1 = checkboxes | panel 2 = toggles/botões | tab "Jogos" = aba Jogos
#   os/gpu  = filtro de compatibilidade (ver Test-WinUtilBoostEntryCompatible)
# ---------------------------------------------------------------------------
$sync.configs.wbtweaks = @'
{
  "WPFTweaksWBPowerSettings": {
    "Content": "Energia - Sem suspensão USB, sem throttle e CPU em 100% na tomada",
    "Description": "No plano de energia ATUAL: desativa 'Suspensão seletiva de USB' (tomada e bateria) e 'USB 3 Link Power Management', desativa 'Estados de throttle do processador' e define 'Estado mínimo do processador' = 100% quando na tomada. Reduz latência e micro-travamentos; aumenta consumo e temperatura em ocioso. Desfazer restaura os padrões do plano Equilibrado. Origem: 'Ajustes de energia.reg' (revisado; os limiares de ocioso do .reg original foram descartados por reduzirem desempenho).",
    "category": "WinForge - Desempenho",
    "panel": "1",
    "InvokeScript": [
      "powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e1e2 0; powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e1e2 0; powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 0; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb 0; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100; powercfg /setactive SCHEME_CURRENT"
    ],
    "UndoScript": [
      "powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e1e2 1; powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb50f7e1e2 1; powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 2; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb 2; powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5; powercfg /setactive SCHEME_CURRENT"
    ]
  },
  "WPFTweaksWBNtfsLastAccess": {
    "Content": "NTFS - Não gravar 'último acesso' (abrir pastas/arquivos mais rápido)",
    "Description": "Impede o NTFS de gravar a data de último acesso a cada leitura de arquivo, reduzindo escritas em disco (fsutil behavior set disablelastaccess 1). Desfazer volta ao padrão gerenciado pelo sistema. Origem: 'Aumentar velocidade ao abrir pastas e arquivos.reg' e 'Aumentar Prioridade da GPU.reg' (os dois faziam exatamente isto).",
    "category": "WinForge - Desempenho",
    "panel": "1",
    "registry": [
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem", "Name": "NtfsDisableLastAccessUpdate", "Value": "1", "Type": "DWord", "OriginalValue": "2147483650" }
    ],
    "InvokeScript": [ "fsutil behavior set disablelastaccess 1 | Out-Null" ],
    "UndoScript":   [ "fsutil behavior set disablelastaccess 2 | Out-Null" ]
  },
  "WPFTweaksWBServicesSafe": {
    "Content": "Serviços dispensáveis - Desativar (seleção segura)",
    "Description": "Desativa: Windows Insider (wisvc), Política de Diagnóstico (DPS), Demonstração de Loja (RetailDemo), Fax, Assistente de Compatibilidade (PcaSvc), Configuração de Área de Trabalho Remota (SessionEnv) e Registro Remoto. Nada que afete impressão, Bluetooth, Windows Hello, teclado touch ou Windows Update. Serviços já alterados manualmente são mantidos. Origem: 'Desativar seviços.bat' (só a parte segura; o resto está em 'Avançado').",
    "category": "WinForge - Desempenho",
    "panel": "1",
    "service": [
      { "Name": "wisvc",          "StartupType": "Disabled", "OriginalType": "Manual" },
      { "Name": "DPS",            "StartupType": "Disabled", "OriginalType": "Automatic" },
      { "Name": "RetailDemo",     "StartupType": "Disabled", "OriginalType": "Manual" },
      { "Name": "Fax",            "StartupType": "Disabled", "OriginalType": "Manual" },
      { "Name": "PcaSvc",         "StartupType": "Disabled", "OriginalType": "Automatic" },
      { "Name": "SessionEnv",     "StartupType": "Disabled", "OriginalType": "Manual" },
      { "Name": "RemoteRegistry", "StartupType": "Disabled", "OriginalType": "Disabled" }
    ]
  },
  "WPFTweaksWBAds": {
    "Content": "Anúncios e sugestões do Windows - Desativar",
    "Description": "Zera as doze chaves do ContentDeliveryManager que alimentam as sugestões de aplicativo no menu Iniciar, as dicas do Windows, a instalação silenciosa de programas patrocinados e o conteúdo promocional na tela de bloqueio e nas Configurações. O menu Iniciar passa a mostrar só o que você instalou, e nenhum aplicativo novo aparece sozinho. Vale para o usuário atual; o Windows Spotlight da tela de bloqueio para junto. Origem: 'Desativar Anúncios e sugestões.bat' + opção 22 do iGust Debloater.",
    "category": "WinForge - Privacidade e Interface",
    "panel": "1",
    "registry": [
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SystemPaneSuggestionsEnabled",    "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SoftLandingEnabled",              "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SilentInstalledAppsEnabled",      "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "PreInstalledAppsEnabled",         "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "OemPreInstalledAppsEnabled",      "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SubscribedContent-310093Enabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SubscribedContent-338388Enabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SubscribedContent-338389Enabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SubscribedContent-338393Enabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SubscribedContent-353694Enabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SubscribedContent-353696Enabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager", "Name": "SubscribedContent-353698Enabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" }
    ]
  },
  "WPFTweaksWBCortana": {
    "Content": "Cortana - Desativar",
    "Description": "Bloqueia a Cortana por política (AllowCortana=0) e tira o consentimento e a integração dela na caixa de pesquisa. A assistente deixa de responder e de aparecer no menu Iniciar, e a pesquisa volta a ser só local. O aplicativo continua instalado: para removê-lo de vez, use a aba AppX. Origem: 'Desativar Cortana.bat' + 'Desativar Bing Search.bat'.",
    "category": "WinForge - Privacidade e Interface",
    "panel": "1",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Search",        "Name": "AllowCortana",   "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",           "Name": "CortanaEnabled", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",           "Name": "CortanaConsent", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBSearchSuggestions": {
    "Content": "Pesquisa - Sem histórico, sem sugestões da web e sem conteúdo da nuvem",
    "Description": "Desliga o histórico de pesquisa do dispositivo, as sugestões e resultados da web na caixa de pesquisa (DisableSearchBoxSuggestions) e a busca de conteúdo na nuvem da conta Microsoft ou corporativa. O menu Iniciar passa a procurar só em arquivos, aplicativos e configurações locais, e responde sem esperar a internet. Arquivo no OneDrive e no SharePoint deixa de aparecer nos resultados. Origem: 'Desativar Sugestões de Pesquisa.bat' (revisado: a chave original era inócua).",
    "category": "WinForge - Privacidade e Interface",
    "panel": "1",
    "registry": [
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\SearchSettings", "Name": "IsDeviceSearchHistoryEnabled", "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\SearchSettings", "Name": "IsMSACloudSearchEnabled",      "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\SearchSettings", "Name": "IsAADCloudSearchEnabled",      "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer",              "Name": "DisableSearchBoxSuggestions",  "Value": "1", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBPrefetch": {
    "Content": "Prefetch / Superfetch - Desativar (apenas para SSD)",
    "Description": "Desliga o Prefetcher e o Superfetch/SysMain no registro. Só faz sentido em SSD; em HDD deixa o sistema mais lento. Desfazer restaura o padrão (3). Origem: 'Desabilitar Prefetch e Superfetch.reg' (o arquivo original estava em formato inválido e não funcionava).",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "registry": [
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management\\PrefetchParameters", "Name": "EnablePrefetcher", "Value": "0", "Type": "DWord", "OriginalValue": "3" },
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management\\PrefetchParameters", "Name": "EnableSuperfetch", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBIndexing": {
    "Content": "Indexação (Windows Search) - Desativar serviço",
    "Description": "Desliga o serviço WSearch. Libera disco/CPU em segundo plano, mas a pesquisa do menu Iniciar/Explorador e do Outlook fica bem mais lenta. Origem: 'Desativar indexação.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "WSearch", "StartupType": "Disabled", "OriginalType": "Automatic" }
    ]
  },
  "WPFTweaksWBSvcSpooler": {
    "Content": "Serviço de impressão (Spooler) - Desativar",
    "Description": "Põe o serviço Spooler em Desabilitado. Some um processo que fica sempre carregado e que é alvo frequente de falha de segurança (a família PrintNightmare). Em máquina que imprime, nada mais funciona: nem impressora física, nem 'Imprimir em PDF', nem fila de impressão. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "Spooler", "StartupType": "Disabled", "OriginalType": "Automatic" }
    ]
  },
  "WPFTweaksWBSvcBluetooth": {
    "Content": "Bluetooth (bthserv) - Desativar",
    "Description": "Põe o serviço bthserv em Desabilitado, que é o que mantém o rádio Bluetooth descoberto e os dispositivos pareados. Faz sentido em desktop ligado por cabo, onde o rádio fica ligado sem nunca ser usado. Fone, mouse, teclado e transferência por Bluetooth param de funcionar até reativar. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "bthserv", "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBSvcRdp": {
    "Content": "Área de Trabalho Remota (TermService) - Desativar",
    "Description": "Põe o serviço TermService em Desabilitado, fechando a porta 3389 e a escuta de sessão remota. É uma superfície de ataque a menos numa máquina doméstica, que quase nunca recebe conexão por RDP. Ninguém mais acessa este computador por Área de Trabalho Remota, inclusive você de fora. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "TermService", "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBSvcHello": {
    "Content": "Biometria / Windows Hello (WbioSrvc) - Desativar",
    "Description": "Põe o serviço WbioSrvc em Desabilitado, que é quem fala com o leitor de digital e com a câmera infravermelha. Útil em desktop sem nenhum sensor biométrico, onde o serviço sobe à toa. A entrada por rosto e por digital do Windows Hello para de funcionar; sobram PIN e senha. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "WbioSrvc", "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBSvcTouchKeyboard": {
    "Content": "Teclado virtual e caneta (TabletInputService) - Desativar",
    "Description": "Põe o serviço TabletInputService em Desabilitado, que é quem desenha o teclado na tela e o painel de escrita à caneta. Em desktop com teclado físico ele nunca é chamado e some da memória. Em tablet e 2-em-1, o teclado virtual deixa de aparecer e a máquina fica sem como digitar no modo tablet. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "TabletInputService", "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBVBS": {
    "Content": "VBS / Isolamento de Núcleo (HVCI) - Desativar",
    "Description": "Desliga a Segurança Baseada em Virtualização e a Integridade de Memória. Ganho de 5-15% de FPS em alguns jogos, mas REDUZ A SEGURANÇA contra malware de kernel. Exige reinício. Desfazer reativa. Origem: 'Desativar VBS (Isolamento de núcleo).bat' (a parte do hypervisor está em item separado).",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "registry": [
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\DeviceGuard\\Scenarios\\HypervisorEnforcedCodeIntegrity", "Name": "Enabled",                           "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\DeviceGuard",                                              "Name": "EnableVirtualizationBasedSecurity", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBHypervisorOff": {
    "Content": "Hypervisor (Hyper-V) - Desativar no boot",
    "Description": "bcdedit /set hypervisorlaunchtype off. QUEBRA WSL2, Hyper-V, Windows Sandbox, WSA e emuladores que usam Hyper-V (BlueStacks em modo Hyper-V). Exige reinício. Desfazer volta para 'auto'. Origem: 'Desativar o Hyper-V.bat' e 'Desativar VBS.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "InvokeScript": [ "bcdedit /set hypervisorlaunchtype off" ],
    "UndoScript":   [ "bcdedit /set hypervisorlaunchtype auto" ]
  },
  "WPFToggleWBTransparency": {
    "Content": "Transparência do Windows (efeitos de vidro)",
    "Description": "Liga/desliga os efeitos de transparência da barra de tarefas, menu Iniciar e Configurações. Desligar economiza GPU em máquinas fracas. Origem: 'Desativar Transparência do Windows.bat'.",
    "category": "WinForge - Preferências",
    "panel": "2",
    "Type": "Toggle",
    "registry": [
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", "Name": "EnableTransparency", "Value": "1", "Type": "DWord", "OriginalValue": "0", "DefaultState": "true" }
    ]
  },
  "WPFToggleWBHAGS": {
    "Content": "HAGS - Agendamento de GPU acelerado por hardware",
    "Description": "Liga/desliga o Hardware-Accelerated GPU Scheduling (HwSchMode 2/1). Exige reinício. Em alguns jogos/drivers desligar reduz stutter; em outros ligar melhora latência - teste. Origem: 'Desativar HGS.reg' / 'Desativar Hardware Accelerated GPU Scheduling.reg'.",
    "category": "WinForge - Preferências",
    "panel": "2",
    "Type": "Toggle",
    "registry": [
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers", "Name": "HwSchMode", "Value": "2", "Type": "DWord", "OriginalValue": "1", "DefaultState": "false" }
    ]
  },

  "WPFTweaksWBGameDVR": {
    "Content": "Game DVR / captura da Game Bar - Desativar",
    "Description": "Desliga a gravação em segundo plano e a captura da Xbox Game Bar (GameDVR) e ajusta o comportamento de tela cheia (FSE). Reduz uso de GPU/CPU em jogos. A Game Bar continua abrindo com Win+G. Origem: 'Desativar Game DVR.reg' + scripts por jogo.",
    "category": "Otimizações para jogos",
    "panel": "2",
    "tab": "Jogos",
    "registry": [
      { "Path": "HKCU:\\System\\GameConfigStore",                                  "Name": "GameDVR_Enabled",                        "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\System\\GameConfigStore",                                  "Name": "GameDVR_FSEBehaviorMode",                "Value": "2", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKCU:\\System\\GameConfigStore",                                  "Name": "GameDVR_HonorUserFSEBehaviorMode",       "Value": "1", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKCU:\\System\\GameConfigStore",                                  "Name": "GameDVR_DXGIHonorFSEWindowsCompatible",  "Value": "1", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKCU:\\System\\GameConfigStore",                                  "Name": "GameDVR_EFSEFeatureFlags",               "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\GameDVR",   "Name": "AppCaptureEnabled",                      "Value": "0", "Type": "DWord", "OriginalValue": "1" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\GameDVR",   "Name": "AudioCaptureEnabled",                    "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\GameDVR",   "Name": "HistoricalCaptureEnabled",               "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\GameDVR",         "Name": "AllowGameDVR",                           "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBMMCSSGames": {
    "Content": "Prioridade das tarefas de jogos (MMCSS) - Alta",
    "Description": "Sobe o perfil 'Games' do MMCSS (Priority 6, Scheduling Category High, SFIO High, GPU Priority 8), zera o SystemResponsiveness - que por padrão reserva 20% da CPU para as tarefas comuns de segundo plano e deixa os outros 80% para a multimídia, e em 0 acaba com essa reserva - e tira o limite de pacotes por milissegundo do NetworkThrottlingIndex. O jogo passa a ganhar a disputa por CPU, disco e rede contra o que roda atrás dele, o que se nota mais em queda de quadros esporádica do que na média. Só vale para quem declara a tarefa 'Games' ao MMCSS, ou seja, a maioria dos jogos, mas não todos. Origem: 'Forçar o windows a priorizar tarefas de jogos.reg', 'Otimizar Foreground.reg' e scripts por jogo.",
    "category": "Otimizações para jogos",
    "panel": "2",
    "tab": "Jogos",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games", "Name": "GPU Priority",           "Value": "8",          "Type": "DWord",  "OriginalValue": "8" },
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games", "Name": "Priority",               "Value": "6",          "Type": "DWord",  "OriginalValue": "2" },
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games", "Name": "Scheduling Category",    "Value": "High",       "Type": "String", "OriginalValue": "Medium" },
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games", "Name": "SFIO Priority",          "Value": "High",       "Type": "String", "OriginalValue": "Normal" },
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",               "Name": "SystemResponsiveness",   "Value": "0",          "Type": "DWord",  "OriginalValue": "20" },
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",               "Name": "NetworkThrottlingIndex", "Value": "4294967295", "Type": "DWord",  "OriginalValue": "10" }
    ]
  },
  "WPFTweaksWBWin32PrioritySeparation": {
    "Content": "Prioridade do programa em primeiro plano (Win32PrioritySeparation = 0x26)",
    "Description": "Grava Win32PrioritySeparation = 0x26 no lugar do padrão 2: fatia de tempo curta, de duração variável, e o triplo de fatias para a janela que está em primeiro plano. Num Windows de mesa a diferença é pequena, porque o padrão 2 manda o sistema escolher e ele já escolhe exatamente isto - curta, variável e 3:1; o que o 0x26 faz é deixar a escolha escrita, o que só muda algo em máquina configurada como servidor ou onde outro utilitário já mexeu neste valor. Vale para qualquer processador, não só Intel, apesar do nome do script de origem. Origem: 'Intel Priority Optimization.bat'.",
    "category": "Otimizações para jogos",
    "panel": "2",
    "tab": "Jogos",
    "registry": [
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\PriorityControl", "Name": "Win32PrioritySeparation", "Value": "38", "Type": "DWord", "OriginalValue": "2" }
    ]
  },
  "WPFTweaksWBXboxServices": {
    "Content": "Serviços Xbox - Desativar",
    "Description": "Desativa XblAuthManager, XblGameSave, XboxNetApiSvc e XboxGipSvc. ATENÇÃO: quebra login no app Xbox, Game Pass, Minecraft (Bedrock) e jogos que usam conta Xbox. Origem: 'Desativar Serviços Xbox.reg'.",
    "category": "Otimizações para jogos",
    "panel": "2",
    "tab": "Jogos",
    "service": [
      { "Name": "XblAuthManager", "StartupType": "Disabled", "OriginalType": "Manual" },
      { "Name": "XblGameSave",    "StartupType": "Disabled", "OriginalType": "Manual" },
      { "Name": "XboxNetApiSvc",  "StartupType": "Disabled", "OriginalType": "Manual" },
      { "Name": "XboxGipSvc",     "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBTimerBcdedit": {
    "Content": "Timer de alta precisão via bcdedit (CUIDADO)",
    "Description": "bcdedit: useplatformtick yes, disabledynamictick yes, tscsyncpolicy Enhanced. Pode reduzir stutter em alguns sistemas e causar instabilidade/consumo maior em outros - teste e desfaça se piorar. Exige reinício. Origem: 'Intel Timer Optimization (bcedit).bat'.",
    "category": "Otimizações para jogos",
    "panel": "2",
    "tab": "Jogos",
    "InvokeScript": [ "bcdedit /set useplatformtick yes; bcdedit /set disabledynamictick yes; bcdedit /set tscsyncpolicy Enhanced" ],
    "UndoScript":   [ "bcdedit /deletevalue useplatformtick; bcdedit /deletevalue disabledynamictick; bcdedit /deletevalue tscsyncpolicy" ]
  },

  "WPFTweaksWBNvidiaTelemetry": {
    "Content": "NVIDIA - Desativar telemetria",
    "Description": "Desativa o serviço NvTelemetryContainer, as tarefas agendadas NvTm*/NvProfile*/NvDriverUpdate* e o opt-in de telemetria do painel. Não afeta o driver nem o NVIDIA App. Origem: 'Desativar Telemetria NVIDIA.bat'.",
    "category": "GPU NVIDIA",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "nvidia",
    "service": [
      { "Name": "NvTelemetryContainer", "StartupType": "Disabled", "OriginalType": "Automatic" }
    ],
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\NVIDIA Corporation\\NvControlPanel2\\Client", "Name": "OptInOrOutPreference", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ],
    "InvokeScript": [ "Get-ScheduledTask -TaskName 'NvTm*','NvProfile*','NvDriverUpdate*','NvNode*' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null" ],
    "UndoScript":   [ "Get-ScheduledTask -TaskName 'NvTm*','NvProfile*','NvDriverUpdate*','NvNode*' -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null" ]
  },
  "WPFTweaksWBNvidiaShadowPlay": {
    "Content": "NVIDIA - Desativar ShadowPlay (overlay e gravação)",
    "Description": "Desliga o ShadowPlay/overlay in-game por registro. Libera recursos se você não grava/transmite. Se o NVIDIA App reativar, desligue também o overlay dentro dele. Origem: 'Desativar NVIDIA ShadowPlay.reg'.",
    "category": "GPU NVIDIA",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "nvidia",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\NVIDIA Corporation\\Global\\ShadowPlay", "Name": "Allow", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBNvidiaShaderCache": {
    "Content": "Limpar Shader Cache (NVIDIA / DirectX)",
    "Description": "Apaga DXCache, GLCache, OptixCache, NV_Cache e D3DSCache. Resolve stutter/artefatos após troca de driver. Os jogos recompilam os shaders na próxima execução.",
    "category": "GPU NVIDIA",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "nvidia",
    "Type": "Button",
    "ButtonWidth": "300",
    "function": "Invoke-WinUtilBoostClearShaderCache"
  },
  "WPFTweaksWBNvidiaDriver": {
    "Content": "Baixar driver NVIDIA (site oficial)",
    "Description": "Abre a página oficial de drivers da NVIDIA no seu navegador, onde se escolhe a série da placa e se baixa o pacote Game Ready ou Studio. Quem baixa e executa o instalador é você, no navegador: este botão só abre o endereço. Use quando a aba Diagnóstico apontar driver de vídeo antigo e você quiser o Game Ready recém-lançado para um jogo, que o Windows Update demora semanas a entregar.",
    "category": "GPU NVIDIA",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "nvidia",
    "Type": "Button",
    "ButtonWidth": "300",
    "InvokeScript": [ "Start-Process 'https://www.nvidia.com/pt-br/drivers/'" ]
  },

  "WPFTweaksWBAmdTelemetry": {
    "Content": "AMD - Desativar conteúdo web e telemetria do Adrenalin",
    "Description": "Zera AllowWebContent e AutoUpdate em HKLM\\SOFTWARE\\AMD\\CN, as duas chaves que o AMD Software Adrenalin consulta para buscar conteúdo na internet e avisar de driver novo. O painel abre sem a aba de notícias e sem a checagem de atualização, e para de conversar com os servidores da AMD em segundo plano. Você passa a saber de driver novo só pela página oficial. Origem: 'Desativar AMD Overlay e Telemetria.reg'.",
    "category": "GPU AMD",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "amd",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\AMD\\CN", "Name": "AllowWebContent", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKLM:\\SOFTWARE\\AMD\\CN", "Name": "AutoUpdate",      "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBAmdULPS": {
    "Content": "AMD - Desativar ULPS (stutter e quedas de clock)",
    "Description": "Desliga o Ultra Low Power State em todas as instâncias do driver AMD (classe de vídeo) e no serviço amdkmdag. Útil em CrossFire e notebooks com quedas de clock. Exige reinício. Origem: 'Desativar ULPS (Stutter e quedas de clock).reg'.",
    "category": "GPU AMD",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "amd",
    "registry": [
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\amdkmdag", "Name": "EnableUlps",    "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\amdkmdag", "Name": "EnableUlps_NA", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ],
    "InvokeScript": [ "Get-ChildItem 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object { if ($null -ne (Get-ItemProperty -Path $_.PSPath -Name EnableUlps -ErrorAction SilentlyContinue)) { Set-ItemProperty -Path $_.PSPath -Name EnableUlps -Value 0 -Type DWord } }" ],
    "UndoScript":   [ "Get-ChildItem 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Class\\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue | ForEach-Object { if ($null -ne (Get-ItemProperty -Path $_.PSPath -Name EnableUlps -ErrorAction SilentlyContinue)) { Set-ItemProperty -Path $_.PSPath -Name EnableUlps -Value 1 -Type DWord } }" ]
  },
  "WPFTweaksWBAmdShaderCache": {
    "Content": "AMD - Forçar Shader Cache sempre ativo",
    "Description": "Grava ShaderCache = 2 no driver amdkmdag, que é o valor 'sempre ligado' - no padrão do Adrenalin quem decide guardar shader compilado é o perfil de cada jogo. Com o cache garantido, o engasgo da primeira passagem por uma área nova acontece uma vez só, e não toda vez que o jogo abre. Em troca, a pasta de cache cresce em disco. Origem: 'Forçar Shader Cache sempre ativo (AMD).reg'.",
    "category": "GPU AMD",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "amd",
    "registry": [
      { "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\amdkmdag", "Name": "ShaderCache", "Value": "2", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWBAmdCrashDefender": {
    "Content": "AMD - Desativar serviço Crash Defender",
    "Description": "Põe o 'AMD Crash Defender Service' em Desabilitado. Ele fica residente vigiando o driver de vídeo para tentar recuperá-lo quando trava, e o custo disso é um processo sempre carregado. Sem ele, uma falha do driver vira tela preta ou reinício em vez de recuperação silenciosa - se a sua placa trava com frequência, deixe ligado. Origem: 'Desativar AMD Crash Defender (serviços.bat'.",
    "category": "GPU AMD",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "amd",
    "service": [
      { "Name": "AMD Crash Defender Service", "StartupType": "Disabled", "OriginalType": "Automatic" }
    ]
  },
  "WPFTweaksWBAmdShaderCacheClear": {
    "Content": "Limpar Shader Cache (AMD / DirectX)",
    "Description": "Apaga DxCache, GLCache, VkCache e D3DSCache. Os jogos recompilam os shaders na próxima execução.",
    "category": "GPU AMD",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "amd",
    "Type": "Button",
    "ButtonWidth": "300",
    "function": "Invoke-WinUtilBoostClearShaderCache"
  },
  "WPFTweaksWBAmdDriver": {
    "Content": "Baixar driver AMD (site oficial)",
    "Description": "Abre a página oficial de suporte e drivers da AMD no seu navegador, onde se informa o modelo da placa e se baixa o pacote Adrenalin. O download e a execução do instalador ficam por sua conta - nenhum arquivo chega à máquina por este botão. Use quando a aba Diagnóstico apontar driver de vídeo antigo: o Adrenalin completo traz o painel de controle da AMD, que a versão vinda do Windows Update não instala.",
    "category": "GPU AMD",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "amd",
    "Type": "Button",
    "ButtonWidth": "300",
    "InvokeScript": [ "Start-Process 'https://www.amd.com/pt/support/download/drivers.html'" ]
  },

  "WPFTweaksWBIntelDriver": {
    "Content": "Baixar driver Intel (site oficial)",
    "Description": "Abre a central de downloads da Intel no seu navegador, onde ficam os drivers de vídeo integrado, de rede e de chipset. O WinForge não baixa nem instala nada: o download e a execução do instalador são seus. As otimizações 'Intel' do repositório de origem (prioridade e timer) não estão aqui, e sim em 'Otimizações para jogos', porque valem para qualquer processador.",
    "category": "GPU Intel",
    "panel": "2",
    "tab": "Jogos",
    "gpu": "intel",
    "Type": "Button",
    "ButtonWidth": "300",
    "InvokeScript": [ "Start-Process 'https://www.intel.com.br/content/www/br/pt/download-center/home.html'" ]
  }
}
'@ | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Botões da aba Config (mesclados em $sync.configs.feature)
# ---------------------------------------------------------------------------
$sync.configs.wbfeatures = @'
{
  "WPFPanelWBRestorePoint": {
    "Content": "Ponto de restauração - Criar agora",
    "Description": "Liga a Proteção do Sistema no disco do Windows se preciso e grava um ponto de restauração agora - é o mesmo ponto que o WinForge oferece na pergunta ao abrir, disponível a qualquer momento. Serve para marcar um estado bom antes de aplicar uma leva de ajustes, ou logo depois de uma leva que deu certo. A gravação leva de segundos a alguns minutos e consome parte da cota de disco reservada à Proteção do Sistema.",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostCreateRestorePoint"
  },
  "WPFPanelWBRegistryBackup": {
    "Content": "Backup do Registro - Exportar chaves raiz",
    "Description": "Exporta as 5 chaves raiz (HKLM, HKCU, HKCR, HKU e HKCC) para arquivos .reg em %LocalAppData%\\WinForge\\Backup_Regedit\\<data>. Demora alguns minutos e ocupa centenas de MB. Origem: 'Fazer backup do Windows.bat'.",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostRegistryBackup"
  },
  "WPFPanelWBClearRam": {
    "Content": "Limpar cache de RAM (Standby List)",
    "Description": "Esvazia a Standby List e a Modified List, igual ao EmptyStandbyList.exe/ISLC, sem executável externo. Útil quando jogos ficam com stutter por RAM 'em cache'. Origem: 'Limpar CACHE Memória RAM.bat'.",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostClearStandbyList"
  },
  "WPFPanelWBFullCleanup": {
    "Content": "Limpeza completa (Temp, Recentes, Windows Update, DNS, Lixeira)",
    "Description": "Apaga temporários do usuário e do Windows, itens recentes, cache do Windows Update, cache de internet legado, cache de shaders do DirectX e relatórios de erro, limpa o resolvedor de DNS e esvazia a Lixeira. Costuma liberar de centenas de MB a vários GB numa máquina que nunca foi limpa. Repare na Lixeira: o que estava lá dentro não volta, e os jogos vão recompilar os shaders na próxima abertura. Origem: 'Limpeza Completa PC.bat' (revisado).",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostFullCleanup"
  },
  "WPFPanelWBOptimizeVolumes": {
    "Content": "Otimizar unidades (TRIM em SSD / desfragmentar HDD)",
    "Description": "Roda Optimize-Volume em todas as unidades fixas; o Windows escolhe TRIM para SSD e desfragmentação para HDD. Substitui os atalhos 'HDD.exe' e 'LIMPAR SSD.exe'.",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostOptimizeVolumes"
  },
  "WPFPanelWBShaderCache": {
    "Content": "Limpar Shader Cache (NVIDIA / AMD / Intel / DirectX)",
    "Description": "Apaga as pastas de shader compilado dos três fabricantes (NVIDIA, AMD e Intel) e do DirectX de uma vez. É o conserto de engasgo, artefato na tela e travamento que aparecem logo depois de trocar ou atualizar o driver de vídeo, quando sobra cache do driver antigo. Os jogos recompilam os shaders na próxima execução, então a primeira partida depois disto engasga um pouco. Origem: 'Limpar Shader Cache NVIDIA.bat' (estendido).",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostClearShaderCache"
  },
  "WPFPanelWBToolISLC": {
    "Content": "ISLC - Intelligent Standby List Cleaner",
    "Description": "Abre o ISLC da pasta 'Apps' (ao lado do script) ou, se ele não estiver ali, a página oficial da Wagnardsoft. O programa vigia a Standby List e a esvazia sozinho quando ela passa de um limite, o que evita o engasgo periódico em jogo de mundo aberto em máquina com pouca RAM. É um utilitário de terceiro: o WinForge só abre, não instala nem configura.",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "Invoke-WinUtilBoostOpenTool -Pattern 'ISLC*.exe' -Url 'https://www.wagnardsoft.com/ISLC' -Name 'ISLC'" ]
  },
  "WPFPanelWBToolMSI": {
    "Content": "MSI Utility v3 (modo MSI para GPU/placas)",
    "Description": "Abre o MSI_util da pasta 'Apps' ou, se ele não estiver ali, o tópico oficial no fórum Guru3D. O programa troca a interrupção de um dispositivo PCI do modo por linha para o modo MSI, o que costuma resolver estalo no áudio e microtravamento causados por placa de vídeo ou controladora USB. É um utilitário de terceiro que mexe direto no registro de drivers: use com um ponto de restauração pronto.",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "Invoke-WinUtilBoostOpenTool -Pattern 'MSI_util*.exe' -Url 'https://forums.guru3d.com/threads/windows-line-based-vs-message-signaled-based-interrupts-msi-tool.378044/' -Name 'MSI Utility'" ]
  },
  "WPFPanelWBToolDnsJumper": {
    "Content": "DNS Jumper (teste e troca de DNS)",
    "Description": "Abre o DnsJumper da pasta 'Apps' ou, se ele não estiver ali, a página oficial da Sordum. O programa mede o tempo de resposta de dezenas de servidores DNS públicos a partir da sua conexão e aplica o mais rápido com um clique. Para só trocar por um servidor conhecido, a aba Ajustes já tem um seletor com Cloudflare, Google e outros.",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "Invoke-WinUtilBoostOpenTool -Pattern 'DnsJumper*.exe' -Url 'https://www.sordum.org/7952/dns-jumper-v2-3/' -Name 'DNS Jumper'" ]
  },
  "WPFPanelWBToolFiremin": {
    "Content": "Firemin (reduz RAM do Firefox)",
    "Description": "Abre o instalador do Firemin da pasta 'Apps' ou, se ele não estiver ali, a página oficial da Rizonesoft. O programa devolve ao sistema, de tempos em tempos, a memória que o Firefox reservou e não está usando, o que ajuda em máquina com 4 ou 8 GB e muitas abas abertas. O Firemin é programa de terceiro: este botão apenas o abre, sem instalar nada e sem ajustar por você o intervalo de limpeza.",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "Invoke-WinUtilBoostOpenTool -Pattern 'Firemin*.exe' -Url 'https://www.rizonesoft.com/downloads/firemin/' -Name 'Firemin'" ]
  },
  "WPFPanelWBToolAppsFolder": {
    "Content": "Abrir pasta 'Apps' (utilitários externos)",
    "Description": "Cria (se preciso) e abre a pasta Apps ao lado do WinForge.ps1. Coloque ali os executáveis (ISLC, MSI_util, DnsJumper, Firemin) para os botões acima abrirem direto.",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "$d = Join-Path $sync.ScriptRoot 'Apps'; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }; Start-Process explorer.exe -ArgumentList \"`\"$d`\"\"" ]
  }
}
'@ | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Presets (mesclados em $sync.configs.preset)
# ---------------------------------------------------------------------------
$sync.configs.wbpresets = @'
{
  "WinForge": [
    "WPFTweaksRestorePoint",
    "WPFTweaksActivity",
    "WPFTweaksConsumerFeatures",
    "WPFTweaksDisableExplorerAutoDiscovery",
    "WPFTweaksWPBT",
    "WPFTweaksLocation",
    "WPFTweaksServices",
    "WPFTweaksTelemetry",
    "WPFTweaksDeliveryOptimization",
    "WPFTweaksDiskCleanup",
    "WPFTweaksDeleteTempFiles",
    "WPFTweaksEndTaskOnTaskbar",
    "WPFTweaksHiber",
    "WPFTweaksWBServicesSafe",
    "WPFTweaksWBAds",
    "WPFTweaksWBCortana",
    "WPFTweaksWBSearchSuggestions",
    "WPFTweaksWBNtfsLastAccess",
    "WPFTweaksWBPowerSettings"
  ],
  "Gamer": [
    "WPFTweaksRestorePoint",
    "WPFTweaksActivity",
    "WPFTweaksConsumerFeatures",
    "WPFTweaksDisableExplorerAutoDiscovery",
    "WPFTweaksWPBT",
    "WPFTweaksLocation",
    "WPFTweaksServices",
    "WPFTweaksTelemetry",
    "WPFTweaksDeliveryOptimization",
    "WPFTweaksDiskCleanup",
    "WPFTweaksDeleteTempFiles",
    "WPFTweaksEndTaskOnTaskbar",
    "WPFTweaksHiber",
    "WPFTweaksDisplay",
    "WPFTweaksWBServicesSafe",
    "WPFTweaksWBAds",
    "WPFTweaksWBCortana",
    "WPFTweaksWBSearchSuggestions",
    "WPFTweaksWBNtfsLastAccess",
    "WPFTweaksWBPowerSettings",
    "WPFTweaksWBGameDVR",
    "WPFTweaksWBMMCSSGames",
    "WPFTweaksWBWin32PrioritySeparation",
    "WPFTweaksWBNvidiaTelemetry",
    "WPFTweaksWBAmdTelemetry"
  ],
  "AppxWinForge": [
    "WPFAppxMicrosoft_WindowsFeedbackHub",
    "WPFAppxMicrosoft_GetHelp",
    "WPFAppxMicrosoft_MicrosoftOfficeHub",
    "WPFAppxMicrosoft_ZuneMusic",
    "WPFAppxMicrosoft_BingSearch",
    "WPFAppxMicrosoftCorporationII_QuickAssist",
    "WPFAppxMicrosoft_Todos",
    "WPFAppxMicrosoft_YourPhone",
    "WPFAppxMicrosoft_WindowsAlarms",
    "WPFAppxMicrosoft_Copilot",
    "WPFAppxMicrosoft_WindowsCamera",
    "WPFAppxMicrosoft_WindowsPhotos",
    "WPFAppxMicrosoft_WindowsCalculator",
    "WPFAppxMicrosoft_BingNews",
    "WPFAppxMicrosoft_BingWeather",
    "WPFAppxMicrosoft_GamingApp",
    "WPFAppxMicrosoft_XboxGamingOverlay",
    "WPFAppxMicrosoft_Xbox_TCUI",
    "WPFAppxMicrosoft_MicrosoftSolitaireCollection",
    "WPFAppxMicrosoft_OutlookForWindows"
  ]
}
'@ | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Jogos para prioridade de CPU via IFEO (origem: 'Aumentar Prioridade de jogos no Sistema.bat'
# e scripts 'Otimizar <jogo>.bat'). Executáveis revisados; entradas duplicadas/erradas do original corrigidas.
# ---------------------------------------------------------------------------
$sync.configs.wbgames = @(
    @{ Key = "ApexLegends";     Name = "Apex Legends";                          Exes = @("r5apex.exe", "r5apex_dx12.exe") },
    @{ Key = "ArenaBreakout";   Name = "Arena Breakout";                        Exes = @("ArenaBreakout.exe") },
    @{ Key = "BattlefieldOld";  Name = "Battlefield 3 / 4 / Hardline / 1 / V";  Exes = @("bf3.exe", "bf4.exe", "bfh.exe", "bf1.exe", "bfv.exe") },
    @{ Key = "Battlefield2042"; Name = "Battlefield 2042";                      Exes = @("BF2042.exe") },
    @{ Key = "Battlefield6";    Name = "Battlefield 6";                         Exes = @("BF6.exe") },
    @{ Key = "BloodStrike";     Name = "Blood Strike";                          Exes = @("BloodStrike.exe") },
    @{ Key = "CODBlackOps";     Name = "Call of Duty: Black Ops (3, 4, Cold War, 6)"; Exes = @("BlackOps3.exe", "BlackOps4.exe", "BlackOpsColdWar.exe", "cod.exe") },
    @{ Key = "Warzone";         Name = "Call of Duty: Warzone / MW (cod.exe)";  Exes = @("cod.exe") },
    @{ Key = "Chivalry2";       Name = "Chivalry 2";                            Exes = @("Chivalry2-Win64-Shipping.exe") },
    @{ Key = "ChooChoo";        Name = "Choo-Choo Charles";                     Exes = @("Charles.exe") },
    @{ Key = "CS2";             Name = "Counter-Strike 2";                      Exes = @("cs2.exe") },
    @{ Key = "Crossfire";       Name = "Crossfire";                             Exes = @("crossfire.exe") },
    @{ Key = "CultOfTheLamb";   Name = "Cult of the Lamb";                      Exes = @("CultOfTheLamb.exe") },
    @{ Key = "Cuphead";         Name = "Cuphead";                               Exes = @("Cuphead.exe") },
    @{ Key = "Cyberpunk";       Name = "Cyberpunk 2077";                        Exes = @("Cyberpunk2077.exe") },
    @{ Key = "DaysGone";        Name = "Days Gone";                             Exes = @("DaysGone.exe") },
    @{ Key = "DayZ";            Name = "DayZ";                                  Exes = @("DayZ_x64.exe", "DayZ.exe") },
    @{ Key = "DeadByDaylight";  Name = "Dead by Daylight";                      Exes = @("DeadByDaylight-Win64-Shipping.exe") },
    @{ Key = "Deadlock";        Name = "Deadlock";                              Exes = @("project8.exe", "Deadlock.exe") },
    @{ Key = "DeathStranding";  Name = "Death Stranding 1 e 2";                 Exes = @("ds.exe", "DeathStranding2.exe") },
    @{ Key = "EAFC26";          Name = "EA Sports FC 26";                       Exes = @("FC26.exe") },
    @{ Key = "EscapeFromTarkov";Name = "Escape from Tarkov";                    Exes = @("EscapeFromTarkov.exe") },
    @{ Key = "ETS";             Name = "Euro Truck Simulator 1 e 2";            Exes = @("eurotrucks.exe", "eurotrucks2.exe", "ets2.exe") },
    @{ Key = "FS22";            Name = "Farming Simulator 22";                  Exes = @("FarmingSimulator2022.exe") },
    @{ Key = "FS25";            Name = "Farming Simulator 25";                  Exes = @("FarmingSimulator2025.exe") },
    @{ Key = "FFXIV";           Name = "Final Fantasy XIV";                     Exes = @("ffxiv_dx11.exe") },
    @{ Key = "FiveM";           Name = "FiveM";                                 Exes = @("FiveM.exe", "FiveM_GTAProcess.exe", "FiveM_b2372_GTAProcess.exe") },
    @{ Key = "Fortnite";        Name = "Fortnite";                              Exes = @("FortniteClient-Win64-Shipping.exe") },
    @{ Key = "FreeFire";        Name = "Free Fire (BlueStacks)";                Exes = @("HD-Player.exe") },
    @{ Key = "Genshin";         Name = "Genshin Impact";                        Exes = @("GenshinImpact.exe") },
    @{ Key = "GhostOfTsushima"; Name = "Ghost of Tsushima";                     Exes = @("GhostOfTsushima.exe") },
    @{ Key = "GodOfWar";        Name = "God of War (2018) e Ragnarök";          Exes = @("GoW.exe", "GoWRagnarok.exe") },
    @{ Key = "GTAV";            Name = "GTA V (Legacy e Enhanced)";             Exes = @("GTA5.exe", "GTA5_Enhanced.exe") },
    @{ Key = "HellLetLoose";    Name = "Hell Let Loose";                        Exes = @("HLL.exe", "HLL-Win64-Shipping.exe") },
    @{ Key = "HollowKnight";    Name = "Hollow Knight e Silksong";              Exes = @("hollow_knight.exe", "Hollow Knight Silksong.exe") },
    @{ Key = "Left4Dead";       Name = "Left 4 Dead 1 e 2";                     Exes = @("left4dead.exe", "left4dead2.exe") },
    @{ Key = "LeagueOfLegends"; Name = "League of Legends";                     Exes = @("League of Legends.exe", "LeagueClient.exe") },
    @{ Key = "MarvelRivals";    Name = "Marvel Rivals";                         Exes = @("MarvelRivals.exe", "Marvel-Win64-Shipping.exe") },
    @{ Key = "MecchaChameleon"; Name = "Meccha Chameleon";                      Exes = @("MecchaChameleon.exe") },
    @{ Key = "Minecraft";       Name = "Minecraft (Java e Bedrock) - afeta todo app Java"; Exes = @("javaw.exe", "java.exe", "Minecraft.Windows.exe") },
    @{ Key = "MTA";             Name = "Multi Theft Auto (GTA SA)";             Exes = @("Multi Theft Auto.exe", "gta_sa.exe") },
    @{ Key = "MySummerCar";     Name = "My Summer Car";                         Exes = @("mysummercar.exe") },
    @{ Key = "Palworld";        Name = "Palworld";                              Exes = @("Palworld-Win64-Shipping.exe") },
    @{ Key = "PES";             Name = "PES 2017-2020 e eFootball";             Exes = @("PES2017.exe", "PES2018.exe", "PES2019.exe", "PES2020.exe", "eFootball.exe") },
    @{ Key = "PointBlank";      Name = "Point Blank";                           Exes = @("PointBlank.exe") },
    @{ Key = "PoppyPlaytime";   Name = "Poppy Playtime (todos)";                Exes = @("Poppy_Playtime.exe", "Playtime_Multiplayer.exe", "PoppyPlaytimeChapter4.exe", "PoppyPlaytimeChapter5.exe", "ProjectPlaytime.exe") },
    @{ Key = "PUBG";            Name = "PUBG: Battlegrounds";                   Exes = @("TslGame.exe") },
    @{ Key = "R6Siege";         Name = "Rainbow Six Siege";                     Exes = @("RainbowSix.exe", "RainbowSix_Vulkan.exe") },
    @{ Key = "RDR2";            Name = "Red Dead Redemption 2";                 Exes = @("RDR2.exe") },
    @{ Key = "Rematch";         Name = "Rematch";                               Exes = @("REMATCH.exe") },
    @{ Key = "RE2";             Name = "Resident Evil 2 Remake";                Exes = @("re2.exe") },
    @{ Key = "RE4";             Name = "Resident Evil 4 Remake";                Exes = @("re4.exe") },
    @{ Key = "REVillage";       Name = "Resident Evil Village";                 Exes = @("re8.exe") },
    @{ Key = "RERequiem";       Name = "Resident Evil Requiem";                 Exes = @("re9.exe") },
    @{ Key = "Roblox";          Name = "Roblox";                                Exes = @("RobloxPlayerBeta.exe") },
    @{ Key = "RocketLeague";    Name = "Rocket League";                         Exes = @("RocketLeague.exe") },
    @{ Key = "Rust";            Name = "Rust";                                  Exes = @("RustClient.exe") },
    @{ Key = "Skyrim";          Name = "Skyrim (SE/AE e clássico)";             Exes = @("SkyrimSE.exe", "TESV.exe") },
    @{ Key = "SnowRunner";      Name = "SnowRunner";                            Exes = @("SnowRunner.exe") },
    @{ Key = "StreetFighter6";  Name = "Street Fighter 6";                      Exes = @("StreetFighter6.exe") },
    @{ Key = "Subnautica";      Name = "Subnautica e Below Zero";               Exes = @("Subnautica.exe", "SubnauticaZero.exe") },
    @{ Key = "Terraria";        Name = "Terraria";                              Exes = @("Terraria.exe") },
    @{ Key = "TheIsle";         Name = "The Isle";                              Exes = @("TheIsleClient-Win64-Shipping.exe") },
    @{ Key = "TheLastOfUs";     Name = "The Last of Us Part I e II";            Exes = @("tlou-i.exe", "tlou-ii.exe") },
    @{ Key = "Ultrakill";       Name = "ULTRAKILL";                             Exes = @("ULTRAKILL.exe") },
    @{ Key = "Valorant";        Name = "Valorant";                              Exes = @("VALORANT-Win64-Shipping.exe", "RiotClientServices.exe") },
    @{ Key = "Warface";         Name = "Warface";                               Exes = @("Warface.exe") },
    @{ Key = "Warframe";        Name = "Warframe";                              Exes = @("Warframe.x64.exe") }
)
#endregion
