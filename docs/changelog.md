# Changelog

## 1.6.0 (2026-09-11)

### Aba Diagnóstico

- O checklist de recomendações deixou de ser só leitura: **Aplicar marcados** e **Desfazer
  marcados** ficam ao lado do contador, na mesma faixa de Marcar todos / Desmarcar todos. Eles
  chamam o MESMO caminho dos botões da aba Ajustes (`Invoke-WPFtweaksbutton` e `Invoke-WPFundoall`)
  — marcar a linha no Diagnóstico já marca a caixa de verdade na aba de destino, e é ela que
  alimenta a lista de aplicação. Não existe caminho de aplicação paralelo: a pergunta do ponto de
  restauração, a trava de um trabalho por vez e o runspace continuam sendo os da base.
- Os dois ficam desabilitados enquanto há trabalho em andamento, em vez de aceitar o clique e
  responder com uma caixa de erro depois dele.

### Correções da aba Configurações

- Os cinco botões do grupo **Correções** que demoram — Rede - Redefinir, Servidor NTP - Ativar,
  Verificação de corrupção do sistema, Windows Update - Redefinir e WinGet - Reinstalar — rodavam
  na thread da janela e escreviam num console que o lançador esconde: a aba congelava e nada
  aparecia na tela. Agora rodam num runspace, com a saída ao vivo numa **janela própria** que se
  enche enquanto o comando trabalha (cabeçalho "Em andamento: `<título>` (mm:ss)", que vira
  "Concluído em mm:ss (código N)" no fim), e a janela principal continua respondendo.
- Cada passo fecha com uma linha `== Passo N: <nome> — código X ==`, e o cabeçalho final diz qual
  passo falhou. Antes, um chkdsk + sfc + DISM saía emendado com um único código no fim, e não dava
  para saber qual dos três tinha falhado.
- A **Verificação de corrupção do sistema** passou a rodar `chkdsk /scan /perf` antes do
  `sfc /scannow` e do `DISM /RestoreHealth`. A ordem é dependência: um setor ruim corrompe de novo o
  que o sfc acabou de consertar, e é o DISM que repõe a imagem de onde o sfc copia os arquivos bons.
- Os cinco passaram a pedir confirmação de Sim/Não antes de agir, com o texto da própria descrição
  do botão — que foi reescrita para dizer o que de fato acontece. A do **Windows Update -
  Redefinir** é a que mais mudou: além de mexer no Windows Update, ela apaga a diretiva de grupo
  local inteira, e com ela os ajustes do WinForge que moram em diretiva (Edge, Brave,
  ConsumerFeatures, telemetria), que precisam ser marcados de novo. O histórico de atualizações é
  preservado.
- A frase de fechamento de cada comando ("Configuração de rede redefinida. Reinicie o computador.")
  passou a sair **só com código 0**. Ela é escrita no presente do indicativo e é a última linha que
  a pessoa lê: imprimi-la logo abaixo de um `== Falhou no passo N ==` era dizer que deu certo no
  exato lugar em que a saída diz que não deu. Com erro sai uma frase neutra, que aponta o passo.
- **Fechar a janela principal no meio de um reparo agora pergunta antes**, com "Não" como resposta
  padrão. O fechamento deixou de esperar pelo pool nesta versão (era o que travava o programa no
  meio de um diagnóstico), e o preço disso é que as threads de segundo plano morrem onde estiverem:
  uma restauração de permissões interrompida entre "tomar a posse" e "devolver a posse" deixa a
  pasta do sistema aceitando alteração de qualquer processo elevado. Diagnóstico e busca de driver
  continuam fechando direto, sem pergunta.
- O `Requires` das linhas com fluxo ao vivo passou a ser conferido **antes** de abrir a janela e de
  tomar as travas. Era dado morto: numa edição do Windows sem `w32tm.exe` a falta virava exceção de
  `Start-Process` dentro do runspace, em vez da frase que a máquina de comandos tem para isso.
- Os botões **Aplicar marcados** / **Desfazer marcados** da aba Diagnóstico passaram a ser
  repintados no começo e no fim de cada comando com fluxo ao vivo. Antes só o contador de marcações
  os repintava: eles ficavam habilitados durante o comando (a caixa de recusa vinha depois do
  clique) e, se alguém marcasse uma caixa no meio, ficavam desabilitados até a marca seguinte.
- A janela ao vivo passou a ter **teto por tique** (512 KB): um passo que despeja dezenas de MB de
  uma vez congelava a thread da interface num `AppendText` só. O arquivo continua completo, e é ele
  o resultado; a caixa recebe a última parte, com um aviso.
- A saída fica em `repair-<nome>-<data-hora>.txt`, em `%LocalAppData%\WinForge\logs`, e a janela
  tem **Copiar** e **Abrir arquivo**.

### Permissões do disco C:

Novo grupo de três botões no reparo de componentes, para o caso em que a cadeia de permissões do
disco do Windows cai — depois de uma atualização de fabricante, por exemplo — e o dono da máquina
fica sem acesso às próprias pastas.

- **Verificar** só lê (`Get-Acl`, sem elevação). Confere dono e ACEs da raiz do disco, de Windows,
  Program Files, Program Files (x86), ProgramData, Users, Users\Public e da pasta do usuário atual
  contra o padrão de fábrica, e termina com a contagem das diferenças. O confronto é **por SID**,
  então vale igual num Windows em inglês e num em português; e é um PISO, não um retrato: ACE a mais
  não é diferença, porque uma pasta do sistema tem ACEs que variam com a edição e com o que já foi
  instalado. A exceção é a ACE de NEGAÇÃO: qualquer uma conta, porque nenhuma dessas pastas tem
  negação de fábrica e negar vence permitir — um `Deny Todos:(OI)(CI)F` plantado em `C:\Users`
  tranca o disco sem tirar uma única permissão da lista. Pasta que não existe não conta; pasta que
  existe e não deixa ler a lista, conta.
- **Restaurar padrões** roda seis fases, nesta ordem: `chkdsk /scan` (se acusar erro no volume, para
  aí e nada é alterado); backup das listas atuais em
  `%ProgramData%\WinForge\acl-backup`; a raiz, com as negações fora, `/inheritance:r` e as ACEs
  padrão por SID; as pastas do sistema (Windows, Program Files, Program Files (x86), ProgramData,
  Users e Users\Public) **uma a uma**, com `/setowner` só onde o dono está errado e
  `/inheritance:r /grant:r` na própria pasta, e **só naquelas que a verificação acusou**; a pasta do
  usuário, com a herança do conteúdo religada depois da concessão na raiz dela; e, só quando a raiz
  responde acesso negado, um `takeown` sem recursão seguido de uma segunda tentativa. `/reset`, `/T`
  e `/R` não existem na raiz nem nas pastas do sistema — os três descem a árvore inteira apagando o
  que o Windows sabe e o WinForge não. Leva minutos e pede reinicialização no fim.
- Três detalhes do `icacls` que só aparecem quando se roda o comando de verdade, e que agora o
  build roda: direito **específico** vai entre parênteses (`*S-1-5-11:(AD)`; sem eles o icacls
  responde 87, "Parâmetro inválido", e não concede nada), `/T` anda junto com `/L` para a recursão
  não sair do alvo pelo primeiro OneDrive ou junção de compatibilidade, e `Users\Public` tem backup
  próprio porque a fase por pasta reescreve a lista dela. Nas pastas do TrustedInstaller (`Windows`,
  `Program Files`), onde o administrador só tem `M` e não consegue reescrever a lista, a concessão
  que responde acesso negado toma a posse, tenta de novo uma vez e **devolve** a posse ao dono
  padrão — pasta do sistema que ficasse com os Administradores como dona aceitaria alteração de
  qualquer processo elevado.
- O `secedit` com o `defltbase.inf` **não entrou**: foi medido nesta máquina e, no Windows 10 e no
  11, as seções `[Registry Keys]` e `[File Security]` desse arquivo vêm vazias — `/areas FILESTORE
  REGKEYS` levava minutos e não repunha DACL nenhuma. A fase por pasta faz esse trabalho de forma
  explícita, com a mesma tabela de esperados que a verificação usa.
- As duas ações que escrevem conferem a **elevação antes de criar a pasta de backup**: sem
  administrador a pasta nasceria com a identidade atual como dona e ficaria plantada em
  `%ProgramData%`, fazendo a conferência recusar todas as restaurações seguintes da máquina.
- **O backup da pasta em si passou a ser SDDL, guardado no índice**, e não mais um arquivo de
  `icacls /save`. Foi medido, com elevação, numa pasta descartável: `icacls <pasta>\ /save f /C`
  grava a entrada da própria pasta com o **nome vazio**, e `icacls <pasta>\ /restore f /C /L`
  **não** a aplica — monta o caminho `<pasta>\<descritor>`, responde "arquivo não encontrado" e a
  lista alterada fica como estava. Ou seja: o `/save` desfaz os filhos de uma pasta, nunca a pasta
  em si — que é exatamente o que as fases 3 e 4 reescrevem. Agora a DACL e o dono de cada pasta
  guardada vão para o índice (JSON, na mesma pasta protegida) e voltam por
  `SetSecurityDescriptorSddlForm` + `DirectoryInfo.SetAccessControl`. O único arquivo de `icacls`
  que sobra é o do **conteúdo** do perfil, salvo com `/T /L /C /Q`.
- Quem escreve o descritor é `DirectoryInfo.SetAccessControl`, e **não** o `Set-Acl`: foi medido
  numa pasta de `%TEMP%` que, com `Set-Acl`, um descritor que só teve `SetOwner()` chamado
  reescreve **também a DACL**, apagando toda ACE explícita e deixando só as herdadas. Numa pasta do
  sistema restaurada com `/inheritance:r`, onde tudo é explícito, o passo do dono apagaria a lista
  que o passo anterior acabou de devolver — e a única pista seria o disco continuar quebrado depois
  do Desfazer. O `-SelfTest` prova as duas seções como independentes.
- **Desfazer** aplica esses dois caminhos: o SDDL na pasta, e `icacls <pasta acima> /restore
  <arquivo> /C /L` no conteúdo do perfil, a partir da pasta anotada no índice (o icacls grava nomes
  relativos à pasta em que foi invocado). Sem backup gravado, ele apenas diz isso.
- **O `/L` do `/restore` faltava, e a falta era grave.** O backup do perfil é gravado com `/T /L`,
  então o arquivo tem uma entrada para cada junção de compatibilidade de dentro dele (`Dados de
  aplicativos`, `Configurações locais`, `Cookies`), com a DACL da própria junção — que carrega uma
  negação de travessia para Todos, que é como o Windows impede que sejam percorridas. Sem `/L` o
  `/restore` abre cada item seguindo o ponto de reanálise e derramaria essa negação em
  `AppData\Roaming`, `AppData\Local` e `InetCookies`, trancando o usuário fora do próprio AppData
  com o botão que existe para destrancá-lo. A trava do build agora cobra `/L` em todo `/restore`,
  como já cobrava em todo `/T`.
- **A posse voltou a ser tentada.** Junto com a lista de cada pasta vai uma tentativa separada de
  devolver o dono guardado. Devolver a posse ao TrustedInstaller exige um privilégio que nem todo
  administrador tem: quando falha, o Desfazer diz em qual pasta, e a lista volta do mesmo jeito.
- O nome dos arquivos de backup passou a ser **injetivo** (codificação por porcentagem, byte a
  byte). O anterior trocava tudo que não fosse `[A-Za-z0-9._-]` por `_`, e `Program Files` e
  `Program_Files` viravam o mesmo nome: como qualquer Usuário Autenticado cria pasta na raiz do
  disco (a ACE `(AD)` que a própria restauração repõe), uma `C:\Program_Files` plantada sem
  elevação sobrescrevia o backup da pasta do Windows, e o Desfazer devolvia a lista do invasor,
  calado.
- O `/save` do perfil ganhou `/Q` e passou a ter o **código de saída conferido**. Sem `/Q` o icacls
  escreve "arquivo processado: `<caminho>`" por arquivo — centenas de milhares de linhas indo para
  a janela num bloco só. E um `/save` que termina em acesso negado ainda deixa um arquivo no disco:
  contá-lo pela simples existência inflava o "N pasta(s) guardadas" com rede de segurança que não
  existia. Agora a fase imprime o número de entradas lido do arquivo.
- Dois limites que a descrição dos botões não esconde: o backup das pastas fora do perfil é **sem
  recursão** (volta a lista da pasta em si, não a do conteúdo); e a restauração não acontece sem
  backup, em nenhuma das duas pontas (pasta de backup que não passa na conferência, ou nenhum
  backup gravado, param tudo antes de a primeira permissão ser alterada).
- A pasta de backup passa pela mesma conferência da pasta de downloads de driver: DACL própria sem
  herança, nenhum ponto de reanálise na cadeia, dono dentro de SYSTEM/Administradores e ninguém de
  fora deles com escrita. Cada arquivo gravado é endurecido, e o Desfazer recusa arquivo que não
  esteja diretamente na pasta ou cujo dono não seja o SYSTEM ou o grupo Administradores. Sem
  elevação a pasta nasce com a identidade atual como dona e a restauração inteira para.

### Descrições

- Toda descrição visível foi revisada para dizer as três coisas que decidem se alguém marca ou não
  marca o item: o mecanismo em palavras simples, o efeito prático e o custo. As que só repetiam o
  título ("IPv6 - Desativar" → "Desativa o IPv6.") ou diziam a mesma frase duas vezes dentro de si
  mesmas foram reescritas, e sete botões de ação que não tinham descrição nenhuma ganharam uma.
- Nova trava no `-SelfTest`, sobre `Description` de tweaks e Config e `description` dos aplicativos,
  já mesclados e traduzidos: nenhuma frase repetida dentro da mesma descrição nem **entre**
  descrições, 40 caracteres no mínimo, nada de ser igual ao título nem começar por ele, no máximo
  uma "Origem:" e nenhum "CUIDADO:" escrito à mão — quem prefixa isso é a auditoria de risco.
  Descrição em branco só passa para 14 botões de painel clássico do Windows, numa lista explícita
  que o próprio teste cobra por tamanho.
- `tools/List-Descriptions.ps1` põe chave, título e descrição lado a lado para a revisão que a
  trava não consegue fazer — se o texto é bom. Tem `-Grupo`, `-MenorQue` e `-Csv`.

## 1.5.0 (2026-09-10)

### Interface em português

- A interface inteira passou para o português: abas, botões, dicas, caixas de diálogo, mensagens do
  console e o texto dos 137 aplicativos, dos 83 ajustes, dos 84 itens de Jogos, dos 22 de Servidor e
  dos 54 de Configurações. O nome dos produtos da aba Instalar continua em inglês de propósito — é
  como eles se chamam na tela de instalação e na busca.
- Duas travas guardam isso. A do `-SelfTest` procura 37 termos em inglês no XAML gerado e no
  Content/Description das configurações, e reprova o build se achar qualquer um; a de cobertura
  exige que toda entrada vinda do arquivo base tenha tradução por chave, e que nenhuma tradução seja
  igual ao texto original (tradução esquecida passava batida antes).
- As abas mudaram de ordem e de nome: **Diagnóstico** (`Alt+D`), **Ajustes** (`Alt+T`), **Jogos**
  (`Alt+J`), **Configurações** (`Alt+C`), **Servidor** (`Alt+S`), **Atualizações** (`Alt+U`),
  **Instalar** (`Alt+I`) e **ISO Win11** (`Alt+W`). A janela abre no Diagnóstico, e não na lista de
  aplicativos: a primeira tela diz o que a máquina é antes de oferecer o que instalar.

### Aba Instalar

- A lista caiu de 232 para **137 aplicativos**: saíram 95 entradas de nicho ou duplicadas. Os grupos
  viraram nove, em português — Comunicação, Desenvolvimento, Documentos, Ferramentas Microsoft,
  Ferramentas profissionais, Jogos, Multimídia, Navegadores e Utilitários — e abrem fechados.
- Os botões da barra lateral voltaram à ordem declarada na configuração (Instalar/atualizar,
  Desinstalar, Atualizar todos). A base ordenava pelo texto, e em português a ação principal caía
  para o fim da lista.

### Aba Diagnóstico

- A lista de recomendações virou um **checklist espelhado**: cada linha tem uma caixa, e ela é a
  mesma marcação da aba de origem (Ajustes, Jogos ou Servidor) nos dois sentidos. Um contador
  mostra `N de M recomendados marcados`, e os botões **Marcar todos** / **Desmarcar todos** agem
  sobre o checklist inteiro.
- A roda do mouse sobre as tabelas de drivers passa a rolar a página. Antes o `DataGrid` engolia o
  evento e a página ficava parada.
- Nova coluna **Ação** na tabela de drivers. Numa placa NVIDIA atrasada, e só quando o link do
  catálogo é de um domínio oficial da NVIDIA, aparece **Baixar `<versão>`**: o arquivo vai para
  `%ProgramData%\WinForge\downloads` (recusado se a cadeia de pastas não for gravável apenas por
  SYSTEM e Administradores), tem a **assinatura digital conferida** contra o nome exato do
  certificado da NVIDIA e só então é aberto — pelo instalador da própria NVIDIA. Nos demais casos
  sobra **Página do fabricante**, que apenas abre um endereço no navegador.
- O botão **Baixar** consulta o catálogo da NVIDIA na hora: o cache só alimenta a tela, e a versão,
  o endereço e o tamanho que aparecem na confirmação — e o que é baixado — vêm dessa consulta ao
  vivo, que recusa endereço fora do domínio oficial e versão que não seja mais nova que a instalada.
- A tabela do Windows Update ganhou o botão **Instalar**, que **sempre pede confirmação** nomeando a
  atualização, e que fica desabilitado quando o WinForge não está elevado.

### Visual

- Sistema visual próprio nos dois temas: paleta com contraste mínimo de 4,5:1 em todos os pares de
  texto e fundo (conferido no `-SelfTest` pelo cálculo do WCAG 2.1), Segoe UI no lugar de
  Consolas/Arial, botões de 32 px com largura pelo conteúdo, abas de largura igual, caixas de
  seleção de 16 px, cartões com raio 6 e barra de status com fundo de cartão.
- Nenhuma cor escrita à mão no XAML: as quatro do cartão "Desativar atualizações" e as cinco da aba
  ISO Win11 viraram token de tema (`DangerColor`, `DiscouragedColor`), e um teste de build reprova
  qualquer cor fixa nova fora de uma lista curta de exceções conhecidas.
- Botão desabilitado deixou de nascer com a cor de SELEÇÃO (azul) nos gabaritos herdados da base -
  agora é o fundo normal a 50 % de opacidade, igual ao resto.
- No tema Claro os botões ganharam contorno de 1 px: `#E8ECF1` sobre `#F8FAFC` não se distinguia do
  fundo e eles não pareciam controles.
- Os botões da aba Configurações esticam na coluna em vez de flutuar com 350 px de largura fixa, e
  as linhas da tabela de drivers passaram a 30 px para os botões da coluna Ação não se encostarem.

### Segurança

- A máscara de "ACE perigosa" da pasta de backup deixou de somar `FullControl` e `Modify`: os dois
  carregam os bits de LEITURA, e qualquer ACE de "Ler e executar" era acusada como permissão de
  escrita. A máscara agora lista direito a direito o que é escrita de fato (gravar, acrescentar,
  excluir, trocar DACL, tomar posse e os bits genéricos GW/GA); `FullControl` e `Modify` continuam
  sendo pegos pelos bits de escrita que carregam.
- Consequência da cadeia de pastas fail-closed que entrou nesta versão: numa máquina em que
  `%ProgramData%\WinForge` já exista com a ACL **herdada** — criada, por exemplo, por uma execução
  anterior sem o launcher —, além do download de driver, o **backup do IIS e dos ajustes de
  Servidor** também passa a recusar, nomeando a pasta. É o comportamento certo (a pasta de fato não
  é confiável), mas é uma mudança de comportamento em campo: na instalação normal o launcher cria a
  pasta já protegida e nada disso aparece.

### Ferramentas

- `tools/UI-Walkthrough.ps1` ganhou `-NoElevation` (abre o motor direto, como usuário comum) e
  `-Theme Escuro|Claro`, e sobe o programa sempre com `-NoRestorePoint` — a caixa do ponto de
  restauração é modal e travava o passeio.
- `tools/List-EnglishStrings.ps1` passou a ler a chamada de `MessageBox::Show` inteira, e não linha
  a linha: era por isso que cinco caixas em inglês não apareciam no inventário.

## 1.4.0 (2026-09-10)

- Novo grupo "WinForge - Reparo de componentes" na aba Config, com doze botões. Cinco só leem:
  estado de TPM, Secure Boot, BitLocker e VBS; saúde dos discos pelos contadores SMART; estado do
  .NET Framework 3.5 e 4.8; `chkdsk /scan` no disco do Windows, que relata sem reparar; e o do
  DirectX, que abre a página oficial da Microsoft no navegador. Os botões de leitura rodam direto.
- Quatro alteram o sistema: verificação do repositório WMI, com `salvagerepository` só quando a
  verificação acusa inconsistência; registro de novo da Microsoft Store, do App Installer (winget) e
  do Store Purchase App para o usuário atual, a partir do manifesto que já está no disco;
  agendamento do `chkdsk /f` para a próxima reinicialização via `fsutil dirty set`; e o Diagnóstico
  de Memória na sequência de inicialização (`bcdedit /bootsequence {memdiag}`), válido só para a
  próxima. O chkdsk agendado não tem desfazer: não existe `fsutil dirty clear`, quem limpa a marca é
  o próprio chkdsk e só quando concluir que o volume está íntegro.
- Três instalam componente: .NET Framework 3.5 pelo DISM (os arquivos vêm do Windows Update, então
  precisa de internet), os 12 redistribuíveis do Visual C++ 2005–2022 x86/x64 pelo winget e o
  PowerShell 7 pelo winget. O que já está instalado é pulado.
- O WinForge não baixa nem executa arquivo da internet. O botão do DirectX abre a página oficial de
  download da Microsoft no navegador; o `dxwebsetup.exe` é baixado e executado por você, a partir
  dessa página, com o seu próprio usuário. O WinForge roda sempre elevado, e `%TEMP%` é gravável por
  qualquer programa do usuário: baixar para lá e abrir de lá dava a um programa comum a chance de
  trocar o arquivo entre a conferência da assinatura e a execução.
- Nada roda sem clique e confirmação: antes de qualquer botão que altera ou instala, aparece uma
  caixa de Sim/Não com a descrição inteira do botão, o mesmo texto que está na aba. As funções que
  escrevem também recusam rodar em modo SelfTest, então o build nunca mexe na máquina de quem
  compila.
- Todo comando roda fora da thread da interface, e a saída vai para uma janela própria — que não
  bloqueia o resto do programa — com Copiar e Abrir arquivo. Cada execução grava
  `repair-<nome>-<data-hora>.txt` em `%LocalAppData%\WinForge\logs`.
- O `winget.exe` sai só do pacote do App Installer instalado pela Microsoft Store — editor
  `8wekyb3d8bbwe`, assinatura de Store ou do sistema e pasta dentro de `%ProgramFiles%\WindowsApps`,
  sem link de reanálise no caminho. O `PATH` não é mais consultado: num processo elevado ele resolve
  para o atalho em `%LOCALAPPDATA%\Microsoft\WindowsApps`, que qualquer programa do usuário pode
  reescrever. O registro de novo da Store e do App Installer aplica o mesmo crivo antes de escolher
  o manifesto, e descarta com uma linha no relatório o que não passar.
- Todo executável do Windows que o WinForge chama (`chkdsk`, `winmgmt`, `fsutil`, `bcdedit`,
  `powercfg`, `w32tm`, `dcdiag`, `repadmin`) passou a ser chamado pelo caminho completo em
  `%SystemRoot%\System32` em vez de pelo nome: num processo elevado, um `PATH` de sistema com uma
  pasta na frente do System32 escolheria o binário. O `winmgmt` mora em `System32\wbem`, que nem
  sempre está no `PATH`.
- Botão de reparo confere "já existe comando em andamento" (e a instalação do próprio WinForge)
  ANTES de mostrar a caixa de confirmação, e não depois do "Sim". A saída de cada comando chega à
  janela num pacote próprio, e não mais por um espaço global: dois comandos seguidos não trocam mais
  de texto na janela.
- O winget é chamado com `--disable-interactivity` e a saída dele é lida como UTF-8, que é o que ele
  escreve — os acentos do relatório e dos nomes de pacote deixaram de vir embaralhados.
- `Secure Boot` sem elevação responde `n/d (sem elevação)`, como TPM e BitLocker, em vez de repetir
  a mensagem de acesso negado do cmdlet.

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
- A checagem da pasta de backup ficou mais dura, e agora vale também na hora de **aplicar**: a pasta
  padrão (`%ProgramData%\WinForge\iis-backup`) só é aceita se pertencer ao SYSTEM ou ao grupo
  Administradores — antes a conta atual também servia, e um programa comum da mesma conta podia criar
  a pasta antes da primeira execução e escolher o que o "Desfazer" aplicaria depois como
  administrador. Pasta que não passa faz a aplicação ser recusada inteira, sem alterar nada no
  servidor. Cada arquivo é conferido antes de ser lido, e todo valor que vem do backup tem de ter a
  forma da propriedade dele (GUID, `True`/`False`, número, `hh:mm:ss`): nenhum valor de arquivo vira
  texto de comando — o `powercfg` recebe o plano de energia como argumento. Um "Desfazer" em que
  alguma chave falhou mantém os arquivos de backup para nova tentativa, em vez de arquivá-los.
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
