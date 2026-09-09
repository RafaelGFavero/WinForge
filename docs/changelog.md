# Changelog

## 1.2.0 (2026-09-07)

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
  para o log da sessão em `%LocalAppData%\WinForge\logs`.

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
