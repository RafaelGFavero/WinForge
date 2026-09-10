# Changelog

## 1.3.0 (2026-09-10)

- Nova aba "Servidor" (`Alt+S`), só no Windows Server: ajustes gerais do servidor, IIS e Active
  Directory. No servidor, as abas Jogos, AppX e Win11 Creator saem da navegação; no cliente a aba
  Servidor não existe. A troca acontece antes de a janela ser montada, a partir da edição do Windows
  e dos papéis instalados (IIS, Active Directory e se a máquina é controlador de domínio, Hyper-V,
  DNS, DHCP, servidor de arquivos, RDS).
- Ajustes de servidor: não abrir o Gerenciador do Servidor no logon, desativar o Rastreador de
  Eventos de Desligamento, plano de energia Alto desempenho, RDP com NLA obrigatório e tempo limite
  de sessão ociosa, desativar o SMB1 e devolver o ajuste automático TCP ao padrão 'normal'. Desativar
  a Configuração de Segurança Reforçada do IE e exigir assinatura SMB são `Cuidado`: vão para
  "Avançado (CUIDADO)" e ficam de fora de qualquer marcação automática.
- Ajustes de IIS, aplicados a todos os pools e sites: iniciar sempre (`AlwaysRunning`), sem tempo
  limite de ociosidade, reciclagem por memória no lugar da reciclagem por tempo (`Cuidado`),
  pré-carregar os sites, compressão estática e dinâmica, cache de saída e de kernel, e fila de 5000
  com as requisições concorrentes do ASP.NET liberadas nas chaves de 64 e de 32 bits.
- Antes de qualquer mudança no IIS, os valores anteriores vão para um JSON em
  `%ProgramData%\WinForge\iis-backup`; "Desfazer" junta todos os backups vivos daquele item e devolve
  pool por pool o valor mais antigo — o de antes da primeira aplicação —, depois arquiva os arquivos
  consumidos como `<nome>.restored.json`. Sem essa junção, um pool criado entre duas aplicações
  deixaria os pools antigos mexidos para sempre. Aplicar de novo não faz nada quando o valor já está
  no lugar, e o backup só é gravado quando há algo a mudar. Pré-carregar e a compressão dinâmica
  dependem dos recursos `Web-AppInit` e `Web-Dyn-Compression`: sem eles o item avisa e não altera
  aquela parte — o WinForge não instala recurso do Windows.
- A pasta de backup passou a nascer com permissões próprias — sem herança, só SYSTEM e
  Administradores — e é conferida antes de todo "Desfazer": pasta de outro dono, com escrita para
  quem não é administrador, ou que seja um link, é recusada com a mensagem na tela e nada alterado.
  Do arquivo só volta o que aquele item de fato escreve; qualquer outra chave é ignorada e vai para
  o log. Sem isso, um JSON plantado na pasta viraria escrita arbitrária no `applicationHost.config`
  no primeiro "Desfazer".
- Os ajustes de servidor que não moram no registro — SMB1, assinatura SMB, plano de energia, ajuste
  automático TCP e o item de RDP — passaram a **ler e guardar o estado atual antes de mudar**, no
  mesmo backup. "Desfazer" devolve o que estava lá em vez de escrever um valor fixo: num servidor
  onde o SMB1 já vinha desligado, desfazer não o liga; num controlador de domínio onde a assinatura
  SMB é obrigatória por política, desfazer não a remove; e o plano de energia volta ao que estava
  ativo, não a "Equilibrado". Sem backup, o Desfazer não faz nada.
- O botão de parâmetros TCP e o cartão de diagnóstico deixaram de depender do `netsh`, que escreve
  UTF-8 quando a saída é um cano: o texto chegava embaralhado e o campo "Ajuste automático TCP"
  ficava vazio em toda máquina localizada. Agora são `Get-NetTCPSetting` e
  `Get-NetOffloadGlobalSetting`, que não dependem de idioma.
- Botões de leitura na aba, nenhum deles altera nada: fonte de horário (`w32tm`), exclusões do
  Microsoft Defender, parâmetros TCP (`Get-NetTCPSetting`) e, num controlador de domínio,
  `dcdiag /q`, `repadmin /replsummary`, limpeza de registros DNS (scavenging) e a localização de
  NTDS e SYSVOL. A saída abre em uma janela à parte, que não trava a principal, com "Copiar" e
  "Abrir arquivo", e fica salva em `%LocalAppData%\WinForge\logs\server-<nome>-<data-hora>.txt`.
  Ferramenta ausente vira mensagem na janela, não erro; o código de saída vai no topo do texto dos
  comandos que são executáveis (`w32tm`, `dcdiag`, `repadmin`), para "falhou" e "não achou nada" não
  se parecerem.
- Diagnóstico: cartão "Servidor" com papéis detectados, estado do SMB1, assinatura SMB, ajuste
  automático TCP, fonte de horário, pools/sites e pasta de logs do IIS, e os caminhos de NTDS e
  SYSVOL num controlador de domínio. O cartão também entra no relatório HTML.
- Cinco regras novas de recomendação, e a regra de servidor passou a sugerir os ajustes da aba: o
  SMB1 ligado é apontado, o IIS instalado sugere o conjunto de pools e cache, e logs do IIS ou banco
  do AD no disco do sistema viram aviso informativo, junto de um lembrete de `dcdiag`/`repadmin` no
  controlador de domínio.
- Nada da aba Servidor entra em preset: preset é para máquina de usuário, e em servidor de produção
  cada item se marca à mão. A aba tem seu próprio "Marcar recomendados", que mostra a seleção antes
  de você aplicar.
- A detecção de "isto é um servidor?" passou a ler o registro primeiro e a usar o WMI só como
  reserva: num servidor com o repositório WMI corrompido a aba Servidor sumia sem uma palavra. E o
  relatório de um perfil montado com `WINFORGE_SIMULATE_SERVER` passa a dizer isso no cartão
  Servidor, em vez de afirmar um tipo de produto que não é o da máquina.
- Build: o SelfTest roda duas vezes, a segunda com `WINFORGE_SIMULATE_SERVER=iis,ad`, porque a aba
  Servidor não existe na máquina de quem compila. A variável aceita os papéis a simular e vale
  também para rodar o motor gerado à mão.

## 1.2.0 (2026-09-09)

- Nova aba "Diagnóstico" (`Alt+D`): nove cartões com o que foi detectado — Sistema, Máquina,
  Processador, Memória, Placa de vídeo, Armazenamento, Rede, Energia, e Segurança e estado —,
  a lista das recomendações com o motivo de cada uma e a tabela dos drivers instalados.
- Detecção do computador: versão e edição do Windows, papéis de servidor (IIS, Active Directory),
  notebook, desktop ou máquina virtual, processador, memória, placas de vídeo, tipo de disco (SSD
  ou HDD), rede, plano de energia e o inventário de drivers com versão e data.
- Recomendações em cada linha de tweak e de recurso, por 15 regras aplicadas ao que foi detectado:
  contorno verde `✔ Recomendado: <motivo>` no que faz sentido para a máquina, laranja
  `⚠ Não recomendado neste sistema: <motivo>` no que não faz. O motivo fica na dica da linha.
  Nada é marcado sozinho — quem marca é o botão "Marcar todos os recomendados", quando você clica.
- Drivers: a versão instalada da NVIDIA é comparada com a mais recente do catálogo do fabricante
  (consulta ao site da NVIDIA, com cache de 24 horas em `%LocalAppData%\WinForge\cache`); para AMD
  e Intel a tabela leva à página de download da marca. O botão "Buscar drivers no Windows Update"
  pergunta ao Windows Update o que existe para este computador. Nada é baixado nem instalado
  automaticamente: a lista é informativa e a instalação continua sendo sua.
- "Exportar relatório HTML" grava um arquivo com tudo o que a aba mostra — perfil, recomendações e
  drivers — e o abre no navegador.
- O perfil é coletado em segundo plano ao abrir a janela, com barra de progresso, e cada etapa vai
  para o log da sessão em `%LocalAppData%\WinForge\logs` — onde agora ficam guardadas as 30 sessões
  mais recentes, com as anteriores apagadas ao abrir.
- A coluna "verificar" da tabela de drivers só marca o que costuma mesmo envelhecer: vídeo, rede,
  áudio e Bluetooth com mais de 180 dias. Chipset, USB e controladoras de disco saem de fábrica com
  driver de anos e continuam certos — marcá-los enchia a aba de aviso sem informação (eram 17 de 20
  numa máquina saudável).
- Detecção mais precisa: um no-break USB não faz mais o desktop ser tratado como notebook,
  convidados de nuvem (EC2, Compute Engine, Nutanix, OpenStack) são reconhecidos como máquina
  virtual, máquina sem rede ativa mostra "sem conexão" em vez de falha de coleta, dois dispositivos
  idênticos aparecem como duas linhas na tabela de drivers, e o nome do relatório exportado leva os
  segundos, para dois relatórios seguidos não se sobrescreverem.

## 1.1.0 (2026-09-07)

- Auditoria de risco de todos os tweaks e toggles, com três classes (Seguro, Cuidado, Removido)
  aplicadas pelo motor ao carregar as configurações: itens `Cuidado` vão para a categoria
  "Avançado (CUIDADO)", ganham o custo no início da descrição e saem de todos os presets. A tabela
  completa é gerada pelo build em `docs/auditoria.md`, a partir da mesma fonte que o programa lê.
- Removidos por saldo negativo: o desligamento do SmartScreen (e da marca de origem de downloads)
  e o pacote agressivo de serviços, que desligava impressão, Bluetooth, RDP, Windows Hello e
  teclado touch de uma vez só.
- O pacote agressivo virou cinco itens de serviço separados (Spooler, Bluetooth, Área de Trabalho
  Remota, biometria/Windows Hello e teclado virtual), cada um classificado como `Cuidado` e
  aplicável isoladamente.
- Limpeza de Disco: o `StartComponentCleanup` do DISM roda sem `/ResetBase`, preservando a
  possibilidade de desinstalar atualizações do Windows.
- Desativar o BitLocker passou a ser `Cuidado`, na categoria "Avançado (CUIDADO)": descriptografar
  a unidade do sistema custa a proteção contra acesso físico e demora muito em discos grandes.
- Launcher: a pasta em `%ProgramData%\WinForge` é criada com dono Administrators e ACL aplicada em
  todos os níveis; os arquivos do motor são recriados protegidos a cada execução; um mutex global
  serializa instâncias simultâneas, com novas tentativas quando o arquivo está momentaneamente em
  uso (violação de compartilhamento); e falhas de propriedade vão para o log de eventos do Windows
  (origem `WinForge`), não mais para um arquivo dentro de `%LocalAppData%`.

## 1.0.0 (2026-09-07)

- Launcher próprio `WinForge.exe` (C# net48): splash, elevação de administrador e hospedagem do
  motor PowerShell/WPF em um único executável.
- Rebranding completo para WinForge: textos, mensagens, links e metadados do motor gerado, com
  teste automático que barra referências de marca de terceiros no arquivo gerado.
- Logo próprio (SVG, PNG e ícone), usado na janela, no splash e no executável.
- Renderização WPF por software como padrão, mais compatível com drivers antigos, sessões remotas
  e overlays; `-HardwareRender` volta para a aceleração por hardware.
- Pergunta de ponto de restauração ao abrir, com `-RestorePoint` e `-NoRestorePoint` para
  responder pela linha de comando.
- Nova aba "Jogos": prioridade de CPU por jogo (IFEO), GameDVR, MMCSS, HAGS e shader cache.
- Filtro de compatibilidade: entradas exclusivas do Windows 11 ficam ocultas no Windows 10 e
  tweaks de GPU só aparecem para a marca de placa detectada.
- `-SelfTest` no motor: valida configurações, XAML, montagem das abas e presets sem abrir a janela.
  Rodando `dist\engine\WinForge.ps1` diretamente não exige administrador; pelo `WinForge.exe` a
  elevação continua sendo pedida.
- O motor é extraído em `%ProgramData%\WinForge\engine\<versão>\`, com a herança de permissões
  desligada: só administradores e SYSTEM escrevem, usuários apenas leem. Antes a extração ia para
  `%LocalAppData%`, gravável pelo usuário — um processo sem privilégio podia trocar o `.ps1` entre
  a extração e a execução elevada. Os logs e backups do motor continuam em `%LocalAppData%\WinForge`.
- `NOTICE` e `LICENSE` embutidos no executável e extraídos junto do motor; o diálogo de Créditos
  ganhou um link que abre o `NOTICE.txt`.
- Splash: o logo passa a usar o maior quadro do `.ico` em vez do de 16x16.
