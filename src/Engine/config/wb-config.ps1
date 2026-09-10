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
    "Description": "Desliga sugestões de apps no menu Iniciar, dicas, apps instalados silenciosamente, conteúdo promocional na tela de bloqueio/Configurações (ContentDeliveryManager). Origem: 'Desativar Anúncios e sugestões.bat' + opção 22 do iGust Debloater.",
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
    "Description": "Bloqueia a Cortana por política (AllowCortana=0) e desliga a integração dela na pesquisa. Para remover o app, use a aba AppX. Origem: 'Desativar Cortana.bat' + 'Desativar Bing Search.bat'.",
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
    "Description": "Desliga o histórico de pesquisa do dispositivo, as sugestões/resultados da web na caixa de pesquisa (DisableSearchBoxSuggestions) e a pesquisa de conteúdo na nuvem (conta Microsoft/corporativa). Origem: 'Desativar Sugestões de Pesquisa.bat' (revisado: a chave original era inócua).",
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
    "Description": "Desativa o Spooler de Impressão. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "Spooler", "StartupType": "Disabled", "OriginalType": "Automatic" }
    ]
  },
  "WPFTweaksWBSvcBluetooth": {
    "Content": "Bluetooth (bthserv) - Desativar",
    "Description": "Desativa o serviço de suporte a Bluetooth. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "bthserv", "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBSvcRdp": {
    "Content": "Área de Trabalho Remota (TermService) - Desativar",
    "Description": "Desativa o serviço de Área de Trabalho Remota. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "TermService", "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBSvcHello": {
    "Content": "Biometria / Windows Hello (WbioSrvc) - Desativar",
    "Description": "Desativa o serviço de biometria. Origem: 'Desativar seviços.bat'.",
    "category": "zz__Avançado (CUIDADO)",
    "panel": "1",
    "service": [
      { "Name": "WbioSrvc", "StartupType": "Disabled", "OriginalType": "Manual" }
    ]
  },
  "WPFTweaksWBSvcTouchKeyboard": {
    "Content": "Teclado virtual e caneta (TabletInputService) - Desativar",
    "Description": "Desativa o teclado na tela e o painel de caneta. Origem: 'Desativar seviços.bat'.",
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
    "Description": "Perfil 'Games' do MMCSS: Priority 6, Scheduling Category High, SFIO High, GPU Priority 8; SystemResponsiveness 0 e NetworkThrottlingIndex desligado (sem limite de pacotes por ms). Origem: 'Forçar o windows a priorizar tarefas de jogos.reg', 'Otimizar Foreground.reg' e scripts por jogo.",
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
    "Description": "Quantum curto, fixo, com forte prioridade para o app em primeiro plano (o jogo). Padrão do Windows é 2. Vale para qualquer CPU, não só Intel. Origem: 'Intel Priority Optimization.bat'.",
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
    "Description": "Abre nvidia.com/drivers no navegador.",
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
    "Description": "HKLM\\SOFTWARE\\AMD\\CN: AllowWebContent=0 e AutoUpdate=0. Origem: 'Desativar AMD Overlay e Telemetria.reg'.",
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
    "Description": "amdkmdag\\ShaderCache=2 (sempre ligado). Origem: 'Forçar Shader Cache sempre ativo (AMD).reg'.",
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
    "Description": "Desativa o 'AMD Crash Defender Service' (proteção contra travamentos do driver que consome recursos em segundo plano). Origem: 'Desativar AMD Crash Defender (serviços.bat'.",
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
    "Description": "Abre amd.com/support no navegador.",
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
    "Description": "Abre o Intel Download Center no navegador. As otimizações 'Intel' do repositório (prioridade e timer) estão em 'Otimizações para jogos' porque valem para qualquer CPU.",
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
    "Description": "Cria um ponto de restauração do sistema (o mesmo que a pergunta feita ao abrir a ferramenta).",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostCreateRestorePoint"
  },
  "WPFPanelWBRegistryBackup": {
    "Content": "Backup do Registro - Exportar HKLM/HKCU/HKCR/HKU/HKCC",
    "Description": "Exporta as 5 chaves raiz para arquivos .reg em %LocalAppData%\\WinForge\\Backup_Regedit\\<data>. Demora alguns minutos e ocupa centenas de MB. Origem: 'Fazer backup do Windows.bat'.",
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
    "Description": "Apaga temporários do usuário e do Windows, itens recentes, cache do Windows Update, cache de internet legado, cache de shaders DirectX, relatórios de erro, limpa o DNS e esvazia a Lixeira. Origem: 'Limpeza Completa PC.bat' (revisado).",
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
    "Description": "Apaga os caches de shaders de todos os fabricantes e do DirectX. Origem: 'Limpar Shader Cache NVIDIA.bat' (estendido).",
    "category": "WinForge - Manutenção",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "function": "Invoke-WinUtilBoostClearShaderCache"
  },
  "WPFPanelWBToolISLC": {
    "Content": "ISLC - Intelligent Standby List Cleaner",
    "Description": "Abre o ISLC da pasta 'Apps' (ao lado do script) ou a página oficial da Wagnardsoft.",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "Invoke-WinUtilBoostOpenTool -Pattern 'ISLC*.exe' -Url 'https://www.wagnardsoft.com/ISLC' -Name 'ISLC'" ]
  },
  "WPFPanelWBToolMSI": {
    "Content": "MSI Utility v3 (modo MSI para GPU/placas)",
    "Description": "Abre o MSI_util da pasta 'Apps' ou o tópico oficial no fórum Guru3D.",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "Invoke-WinUtilBoostOpenTool -Pattern 'MSI_util*.exe' -Url 'https://forums.guru3d.com/threads/windows-line-based-vs-message-signaled-based-interrupts-msi-tool.378044/' -Name 'MSI Utility'" ]
  },
  "WPFPanelWBToolDnsJumper": {
    "Content": "DNS Jumper (teste e troca de DNS)",
    "Description": "Abre o DnsJumper da pasta 'Apps' ou a página oficial da Sordum. A aba Ajustes também tem um seletor de DNS (Cloudflare, Google, etc.).",
    "category": "WinForge - Ferramentas externas",
    "panel": "2",
    "Type": "Button",
    "ButtonWidth": "350",
    "InvokeScript": [ "Invoke-WinUtilBoostOpenTool -Pattern 'DnsJumper*.exe' -Url 'https://www.sordum.org/7952/dns-jumper-v2-3/' -Name 'DNS Jumper'" ]
  },
  "WPFPanelWBToolFiremin": {
    "Content": "Firemin (reduz RAM do Firefox)",
    "Description": "Abre o instalador do Firemin da pasta 'Apps' ou a página oficial da Rizonesoft.",
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
