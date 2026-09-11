#region ===== WinForge - configurações do servidor =====

# ---------------------------------------------------------------------------
# Ajustes gerais do Windows Server (mesclados em $sync.configs.tweaks)
#   panel 1 = checkboxes | panel 2 = botões | tab "Servidor" = aba Servidor
#   platform "server" = só aparece no Windows Server (ver Test-WinUtilBoostEntryCompatible)
#   role "iis"/"ad"   = itens por função: só aparecem quando o papel está instalado (categoria IIS
#                       e os botões de Active Directory)
# Nada daqui entra em preset: preset é para máquina de usuário, não para servidor em produção.
# ---------------------------------------------------------------------------
$sync.configs.wfserver = @'
{
  "WPFTweaksWFSrvNoServerManager": {
    "Content": "Não abrir o Gerenciador do Servidor no logon",
    "Description": "Impede que o Gerenciador do Servidor (Server Manager) abra sozinho a cada logon, para a máquina e para o usuário atual. O programa continua instalado e pode ser aberto pelo menu Iniciar. Desfazer volta a abrir no logon.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\ServerManager", "Name": "DoNotOpenServerManagerAtLogon", "Value": "1", "Type": "DWord", "OriginalValue": "0" },
      { "Path": "HKCU:\\Software\\Microsoft\\ServerManager", "Name": "DoNotOpenServerManagerAtLogon", "Value": "1", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWFSrvShutdownTracker": {
    "Content": "Desativar o Rastreador de Eventos de Desligamento",
    "Description": "Desliga a caixa que pede o motivo a cada desligamento ou reinício do servidor (Shutdown Event Tracker). O motivo deixa de ser gravado no log de eventos; se a sua operação exige esse registro por auditoria, não marque. Desfazer remove a política e o rastreador volta.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\Reliability", "Name": "ShutdownReasonOn", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\Reliability", "Name": "ShutdownReasonUI", "Value": "0", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ]
  },
  "WPFTweaksWFSrvIEESC": {
    "Content": "Desativar a Configuração de Segurança Reforçada do IE (administradores)",
    "Description": "Desliga a IE Enhanced Security Configuration para o grupo de administradores. Sem ela, o navegador do servidor deixa de bloquear scripts e downloads de sites não confiáveis. Desfazer religa a proteção.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\Active Setup\\Installed Components\\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}", "Name": "IsInstalled", "Value": "0", "Type": "DWord", "OriginalValue": "1" }
    ]
  },
  "WPFTweaksWFSrvHighPerf": {
    "Content": "Plano de energia Alto desempenho",
    "Description": "Ativa o plano 'Alto desempenho' (o padrão recomendado para servidores: sem redução de clock em ocioso, latência menor). Aumenta o consumo de energia. O plano que estava ativo é gravado em %ProgramData%\\WinForge\\iis-backup antes da troca; 'Desfazer' volta a ele - e não faz nada se o Alto desempenho já era o plano ativo, porque nesse caso não há o que devolver.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "InvokeScript": [
      "Invoke-WinForgeServerSetting -Name HighPerf | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeServerSetting -Name HighPerf -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFSrvRdpNla": {
    "Content": "RDP: exigir Autenticação no Nível da Rede e tempo limite de sessão ociosa (30 min)",
    "Description": "Exige NLA (autenticação antes de abrir a sessão) e camada de segurança TLS no RDP, e derruba sessões ociosas depois de 30 minutos. Clientes antigos sem suporte a NLA (Windows XP, thin clients velhos) deixam de conseguir conectar. Os três valores anteriores são gravados em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' devolve exatamente o que estava lá - inclusive apagando o tempo limite se ele não existia.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "InvokeScript": [
      "Invoke-WinForgeServerSetting -Name RdpNla | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeServerSetting -Name RdpNla -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFSrvSmb1Off": {
    "Content": "Desativar o SMB1 no servidor",
    "Description": "Desliga o protocolo SMB1 no serviço de arquivos (o recurso do Windows continua instalado; o WinForge não desinstala recurso). Dispositivos antigos que só falam SMB1 (scanners e multifuncionais de rede, NAS velhos, Windows XP) param de acessar os compartilhamentos. O cartão de perfil da aba Diagnóstico mostra o estado atual do SMB1. O estado anterior é gravado em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' devolve o que estava lá - e não liga o SMB1 num servidor onde ele já estava desligado.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "InvokeScript": [
      "Invoke-WinForgeServerSetting -Name Smb1Off | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeServerSetting -Name Smb1Off -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFSrvSmbSigning": {
    "Content": "SMB: exigir assinatura",
    "Description": "Passa a exigir assinatura digital em toda sessão SMB do servidor. O estado anterior é gravado em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' devolve o que estava lá - num controlador de domínio, onde a assinatura já é obrigatória por política, aplicar não muda nada e desfazer também não.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "InvokeScript": [
      "Invoke-WinForgeServerSetting -Name SmbSigning | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeServerSetting -Name SmbSigning -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFSrvTcpAutotuning": {
    "Content": "TCP: nível de ajuste automático 'normal'",
    "Description": "Devolve o autotuning da janela de recepção TCP ao valor padrão 'normal'. Serve para desfazer o 'disabled' ou 'restricted' que scripts de otimização antigos deixam para trás e que derruba a taxa de transferência em rede rápida. O nível anterior é gravado em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' devolve exatamente esse nível - use o botão 'Mostrar parâmetros TCP' para conferir antes e depois.",
    "category": "Servidor",
    "panel": "1",
    "tab": "Servidor",
    "platform": "server",
    "InvokeScript": [
      "Invoke-WinForgeServerSetting -Name TcpAutotuning | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeServerSetting -Name TcpAutotuning -Undo | Out-Null"
    ]
  },

  "WPFTweaksWFIisAlwaysRunning": {
    "Content": "Pools: iniciar sempre (AlwaysRunning)",
    "Description": "Põe todos os pools de aplicativos em startMode 'AlwaysRunning' e autoStart 'True': o processo sobe junto com o servidor, em vez de esperar a primeira requisição (fim da lentidão do primeiro acesso). Em troca, os pools ociosos passam a ocupar memória o tempo todo. Os valores anteriores de cada pool são gravados em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' lê esse backup de volta.",
    "category": "IIS",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "iis",
    "InvokeScript": [
      "Invoke-WinForgeIisTweak -Name AlwaysRunning | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeIisTweak -Name AlwaysRunning -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFIisNoIdleTimeout": {
    "Content": "Pools: sem tempo limite de ociosidade",
    "Description": "Zera o processModel.idleTimeout de todos os pools (padrão: 20 minutos), então o pool deixa de ser desligado por ficar sem requisições e o primeiro acesso depois de um período parado não paga a subida do processo. O pool ocioso continua ocupando memória. O idleTimeout anterior de cada pool é gravado em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' devolve pool por pool o tempo que estava lá.",
    "category": "IIS",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "iis",
    "InvokeScript": [
      "Invoke-WinForgeIisTweak -Name NoIdleTimeout | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeIisTweak -Name NoIdleTimeout -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFIisMemoryRecycling": {
    "Content": "Pools: reciclar por memória, não por tempo",
    "Description": "Desliga a reciclagem por tempo (recycling.periodicRestart.time = 00:00:00, que por padrão derruba o pool a cada 29 horas, muitas vezes no meio do expediente) e coloca no lugar um limite de memória privada por pool: 60% da RAM dividido pela quantidade de pools, preso entre 1 GB e 8 GB. O horário de reciclagem e o limite de memória que cada pool tinha são gravados em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' repõe os dois de uma vez.",
    "category": "IIS",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "iis",
    "InvokeScript": [
      "Invoke-WinForgeIisTweak -Name MemoryRecycling | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeIisTweak -Name MemoryRecycling -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFIisPreload": {
    "Content": "Sites: pré-carregar (preloadEnabled)",
    "Description": "Liga applicationDefaults.preloadEnabled em todos os sites: o IIS carrega o aplicativo assim que o pool sobe, sem esperar o primeiro visitante. O que muda é o PADRÃO DO SITE - o aplicativo que já tem preloadEnabled definido explicitamente continua com o valor dele, ligado ou desligado. Depende do recurso 'Inicialização de Aplicativos' (Web-AppInit); se ele não estiver instalado, o item avisa e não altera nada - o WinForge não instala recursos do Windows. O preloadEnabled anterior de cada site é gravado em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' percorre esse arquivo e repõe site por site.",
    "category": "IIS",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "iis",
    "InvokeScript": [
      "Invoke-WinForgeIisTweak -Name Preload | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeIisTweak -Name Preload -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFIisCompression": {
    "Content": "Compressão estática e dinâmica",
    "Description": "Liga doStaticCompression e doDynamicCompression na seção system.webServer/urlCompression do servidor: menos banda por resposta, mais CPU por resposta (a parte dinâmica comprime a cada requisição). A compressão dinâmica depende do recurso Web-Dyn-Compression; sem ele, só a estática é ligada e o item avisa. O estado anterior das duas compressões é gravado em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' religa ou desliga cada uma conforme estava.",
    "category": "IIS",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "iis",
    "InvokeScript": [
      "Invoke-WinForgeIisTweak -Name Compression | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeIisTweak -Name Compression -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFIisOutputCache": {
    "Content": "Cache de saída e cache de kernel",
    "Description": "Liga enabled e enableKernelCache na seção system.webServer/caching: respostas que podem ser reaproveitadas passam a sair do cache, e as elegíveis saem direto do kernel (http.sys), sem entrar no modo usuário. Conteúdo que muda a cada requisição não entra no cache de kernel. O estado anterior do cache e do cache de kernel é gravado em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' devolve os dois valores.",
    "category": "IIS",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "iis",
    "InvokeScript": [
      "Invoke-WinForgeIisTweak -Name OutputCache | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeIisTweak -Name OutputCache -Undo | Out-Null"
    ]
  },
  "WPFTweaksWFIisConcurrency": {
    "Content": "Fila e requisições concorrentes (5000)",
    "Description": "Sobe o queueLength de todos os pools para 5000 (padrão: 1000), então picos de acesso ficam na fila em vez de receber 503, e libera as requisições concorrentes do ASP.NET (MaxConcurrentRequestsPerCPU = 5000) nas duas chaves, a de 64 bits e a de 32 bits (Wow6432Node) - pool em modo 32 bits lê a segunda. Fila maior significa espera maior quando o aplicativo é o gargalo - não substitui mais CPU. Os valores anteriores dos pools são gravados em %ProgramData%\\WinForge\\iis-backup antes da mudança; 'Desfazer' lê esse backup de volta e remove as duas chaves do ASP.NET.",
    "category": "IIS",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "iis",
    "registry": [
      { "Path": "HKLM:\\SOFTWARE\\Microsoft\\ASP.NET\\4.0.30319.0", "Name": "MaxConcurrentRequestsPerCPU", "Value": "5000", "Type": "DWord", "OriginalValue": "<RemoveEntry>" },
      { "Path": "HKLM:\\SOFTWARE\\Wow6432Node\\Microsoft\\ASP.NET\\4.0.30319.0", "Name": "MaxConcurrentRequestsPerCPU", "Value": "5000", "Type": "DWord", "OriginalValue": "<RemoveEntry>" }
    ],
    "InvokeScript": [
      "Invoke-WinForgeIisTweak -Name Concurrency | Out-Null"
    ],
    "UndoScript": [
      "Invoke-WinForgeIisTweak -Name Concurrency -Undo | Out-Null"
    ]
  },

  "WPFWFSrvTimeCheck": {
    "Content": "Verificar fonte de horário (w32tm)",
    "Description": "Roda 'w32tm /query' para mostrar de onde este servidor tira a hora (NTP externo, hierarquia do domínio ou o relógio local), o estado do serviço W32Time e o desvio da última sincronização. Serve para achar a causa de erro de autenticação Kerberos e de certificado, que reclamam quando o relógio foge mais de cinco minutos. Só lê, não altera nada.",
    "category": "Servidor",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "Type": "Button",
    "ButtonWidth": "300"
  },
  "WPFWFSrvDefenderExclusions": {
    "Content": "Listar exclusões do Defender",
    "Description": "Lista as exclusões de caminho, de extensão e de processo configuradas no Microsoft Defender desta máquina. Serve para conferir se as pastas de banco de dados, de log e de aplicação recomendadas pelo fabricante estão mesmo fora da verificação em tempo real - e para descobrir exclusão demais, que é buraco de segurança. Só lê, não altera nada.",
    "category": "Servidor",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "Type": "Button",
    "ButtonWidth": "300"
  },
  "WPFWFSrvTcpShow": {
    "Content": "Mostrar parâmetros TCP",
    "Description": "Mostra os parâmetros TCP do perfil de Internet (Get-NetTCPSetting) e as opções de descarregamento da placa (Get-NetOffloadGlobalSetting): autotuning, algoritmo de congestionamento, ECN, RSS e afins. Só lê, não altera nada.",
    "category": "Servidor",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "Type": "Button",
    "ButtonWidth": "300"
  },
  "WPFWFAdDcdiag": {
    "Content": "Executar dcdiag /q",
    "Description": "Roda o 'dcdiag /q', a bateria de testes de saúde de controlador de domínio, no modo em que só o que falhou é impresso. Saída vazia é boa notícia: quer dizer que replicação, DNS, serviços e confiança passaram em todos os testes. Só lê, não altera nada.",
    "category": "Active Directory",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "ad",
    "Type": "Button",
    "ButtonWidth": "300"
  },
  "WPFWFAdReplSummary": {
    "Content": "Resumo de replicação (repadmin)",
    "Description": "Roda 'repadmin /replsummary' e mostra, por parceiro de replicação, há quanto tempo foi a última troca bem-sucedida e quantas falharam. É o primeiro lugar a olhar quando uma senha trocada num controlador não vale no outro. Só lê, não altera nada.",
    "category": "Active Directory",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "ad",
    "Type": "Button",
    "ButtonWidth": "300"
  },
  "WPFWFAdDnsScavenging": {
    "Content": "Limpeza de registros DNS (scavenging)",
    "Description": "Mostra se a limpeza automática de registros DNS antigos (scavenging) está ligada neste servidor e com que intervalos de atualização e de expiração. Sem ela, a zona vai acumulando registro de máquina que não existe mais e o nome passa a resolver para o IP errado. Só lê, não altera nada.",
    "category": "Active Directory",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "ad",
    "Type": "Button",
    "ButtonWidth": "300"
  },
  "WPFWFAdNtdsLocation": {
    "Content": "Onde estão NTDS e SYSVOL",
    "Description": "Mostra em que disco e pasta estão o banco do AD (ntds.dit), os logs de transação e o SYSVOL, marcando o que está no disco do sistema. Só lê, não altera nada.",
    "category": "Active Directory",
    "panel": "2",
    "tab": "Servidor",
    "platform": "server",
    "role": "ad",
    "Type": "Button",
    "ButtonWidth": "300"
  }
}
'@ | ConvertFrom-Json

#endregion
