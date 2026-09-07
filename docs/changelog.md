# Changelog

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
  serializa instâncias simultâneas; e falhas de propriedade vão para o log de eventos do Windows.

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
- Dois `WinForge.exe` abertos ao mesmo tempo não atrapalham mais um ao outro: a preparação do motor
  é serializada por um mutex de máquina e um arquivo momentaneamente em uso é reesperado em vez de
  abortar a inicialização. Falhas de propriedade na extração passam a ser registradas no log de
  Aplicativo do Windows (origem `WinForge`), não mais em arquivo dentro de `%LocalAppData%`.
- `NOTICE` e `LICENSE` embutidos no executável e extraídos junto do motor; o diálogo de Créditos
  ganhou um link que abre o `NOTICE.txt`.
- Splash: o logo passa a usar o maior quadro do `.ico` em vez do de 16x16.
