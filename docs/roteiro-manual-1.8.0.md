# Roteiro manual da 1.8.0

Este roteiro existe porque a 1.8.0 mexe em coisas perigosas — permissões do disco do Windows,
driver de rede e instalação de driver em lote — e **nada disso foi visto rodando numa máquina com o
problema de verdade**. O autoteste do WinForge roda sem administrador e sobre um perfil íntegro:
ele prova a decisão, as recusas e a forma dos comandos, e não prova o efeito no sistema.

O que está aqui é o que falta medir, na ordem em que vale a pena medir, e escrito para alguém
executar na frente da máquina. Cada teste diz o que fazer, o que observar e o que fazer se der
errado.

## Antes de começar

- Use uma máquina que você possa reinstalar. Nenhum destes testes é para rodar na máquina de
  trabalho de alguém.
- Tenha **um cabo de rede à mão** e uma tomada de rede que funcione. Os testes de driver de rede
  podem deixar o computador sem Wi-Fi, e o cabo é o caminho de volta.
- Tenha um **pen drive ou HD externo formatado em NTFS**, para o teste de backup em outro disco.
  exFAT e FAT32 não guardam permissão e são recusados.
- Ligue a Proteção do Sistema no disco do Windows e crie um ponto de restauração à mão antes de
  começar. É a rede de segurança que está fora do WinForge.
- Anote em cada teste: versão do Windows (`winver`), se o WinForge estava elevado, o horário, o
  tempo que cada coisa levou e o caminho do arquivo de saída. Os arquivos ficam em
  `%LocalAppData%\WinForge\logs`.
- **Um teste por vez, e reinicie entre os que alteram permissão.** Programas abertos continuam com
  as permissões antigas em cache, e um resultado lido antes do reinício não vale.

Onde estiver escrito **ELEVAÇÃO**, o WinForge precisa estar aberto como administrador. Onde estiver
escrito **PODE FICAR SEM REDE**, leia o teste inteiro antes de clicar.

---

## 1. Restauração de permissões numa máquina saudável, com perfil grande

**ELEVAÇÃO.** Risco: baixo numa máquina saudável, e é esse o ponto — aqui ela precisa ser rápida e
não estragar nada. Este é o teste que a máquina de desenvolvimento não consegue fazer: é preciso um
**perfil grande**, de uso real, com OneDrive ou outra nuvem ligada, dezenas de milhares de pastas e
`AppData` cheio. Um perfil recém-criado não exercita nada.

**Passos**

1. Antes de abrir o WinForge, anote o espaço livre do disco C: e o tamanho do perfil
   (`C:\Users\<você>`), pelas Propriedades da pasta.
2. Abra o WinForge como administrador, vá em **Configurações** e clique em
   `Permissões do disco C: - Verificar`. Guarde o texto: é o retrato do "antes".
3. Clique em `Permissões do disco C: - Restaurar padrões`, confirme, e **deixe a janela de saída
   aberta**. Cronometre.
4. Enquanto roda, abra o Gerenciador de Tarefas e olhe o disco e a memória do `powershell.exe` do
   WinForge de tempos em tempos.
5. Quando terminar, reinicie o computador. Depois do reinício, clique em **Verificar** de novo.
6. Abra `C:\ProgramData\WinForge\acl-backup` e anote o tamanho da pasta e o do maior arquivo.

**O que observar**

- A fase 2 (backup) tem de terminar em **segundos**, não em minutos. No perfil de referência foram
  338 pastas, 103,4 KB de arquivo e 39 segundos.
- O espaço livre do disco não pode cair de forma perceptível. Se cair em GB, é o defeito da 1.7.0
  de volta — pare tudo e registre.
- A memória do processo tem de ficar na casa das centenas de MB, sem subir sem parar.
- O cabeçalho da janela termina em `Concluído em mm:ss (código 0)`. Se terminar em
  `Concluído com ressalvas`, anote quais pastas ele nomeou: são pastas que ele não conseguiu ler,
  e elas não foram copiadas nem alteradas.
- Depois do reinício: a área de trabalho abre, os programas instalados abrem, o Explorer entra em
  `AppData`, e a nuvem (OneDrive e afins) continua sincronizando.

**Se der errado**

- Disco enchendo ou fase 2 passando de dois ou três minutos: use o botão **Parar**, espere a etapa
  em curso terminar, e depois **Desfazer (restaurar backup)**. Registre o tamanho de
  `acl-backup` antes de limpar.
- Máquina sem acesso a arquivos depois do reinício: `Desfazer (restaurar backup)` e reiniciar de
  novo. Se o WinForge não abrir mais, use o ponto de restauração do Windows.

---

## 2. A mesma restauração com o backup indo para outro disco

**ELEVAÇÃO.** Risco: baixo. O que está em teste é a caixa de destino e as sete recusas.

**Passos**

1. Antes de marcar a caixa, tente **de propósito** três destinos que têm de ser recusados: uma
   pasta de rede (`\\servidor\pasta`), a raiz de um pen drive em exFAT ou FAT32, e uma pasta dentro
   do seu próprio perfil. Anote a frase de recusa de cada uma.
2. Ligue o pen drive ou HD externo em NTFS, marque **Guardar o backup das permissões em outro
   disco** e escolha uma pasta dentro dele.
3. Rode a restauração e espere terminar.
4. Abra a pasta escolhida e confira que o arquivo de conteúdo está lá. Confira também que o índice
   **continua** em `C:\ProgramData\WinForge\acl-backup`.
5. **Desligue o disco externo** e clique em `Desfazer (restaurar backup)`.
6. Ligue o disco de novo e clique em **Desfazer** outra vez.

**O que observar**

- As três recusas do passo 1 explicam o motivo em português e não deixam continuar.
- Com o disco desligado, o Desfazer **recusa e diz qual disco ligar**, sem alterar nada.
- Com o disco ligado, o Desfazer funciona normalmente.
- Bônus, se você quiser exercitar a proteção: abra o arquivo de conteúdo no Bloco de Notas, altere
  um caractere, salve, e clique em Desfazer. Ele tem de recusar pela conferência do SHA-256. Depois
  desse teste o backup não serve mais — rode a restauração de novo se quiser seguir.

**Se der errado**

- Desfazer que aceita um arquivo alterado, ou que não percebe o disco desligado: registre e **não
  use esse backup**. Rode uma restauração nova, com o destino padrão, para ter um backup bom.

---

## 3. Desfazer, e o backup que não pode ser destruído

**ELEVAÇÃO.** Risco: médio — é o teste que prova que o defeito mais perigoso da 1.7.0 morreu.

**Passos**

1. Com uma restauração já feita (teste 1), clique em `Permissões do disco C: - Restaurar padrões`
   **de novo**, sem desfazer a primeira.
2. Leia a recusa e siga o que ela manda: clique em `Desfazer (restaurar backup)`.
3. Depois que o Desfazer terminar, clique em **Desfazer** mais uma vez.
4. Reinicie e clique em **Verificar**.

**O que observar**

- O passo 1 tem de ser **recusado** enquanto existir backup não usado, oferecendo duas saídas:
  desfazer, ou limpar os backups antigos. Restauração que roda por cima da anterior é o defeito da
  1.7.0.
- O Desfazer do passo 2 lê o conjunto **mais antigo ainda não usado**. Confira no arquivo de saída
  qual carimbo de data ele diz ter usado.
- O passo 3 diz que não há mais backup pendente, e não toca em nada.
- Se alguma pasta não aceitar a volta do dono, o Desfazer diz **qual pasta**. Isso é esperado:
  devolver a posse ao TrustedInstaller exige um privilégio que nem todo administrador tem.

**Se der errado**

- Se a segunda restauração rodar em vez de ser recusada, pare e registre: o backup bom pode ter
  sido substituído. Nesse caso, o caminho de volta é o ponto de restauração do Windows.

---

## 4. Limpar backups antigos, com um conjunto pendente

**ELEVAÇÃO.** Risco: baixo, mas o teste apaga arquivos de propósito.

**Passos**

1. Com um backup pendente (rode uma restauração e **não** desfaça), clique em
   `Permissões do disco C: - Limpar backups antigos`.
2. Leia a lista: tamanho, data e a marca de quem está pendente e de quem é órfão.
3. Peça para descartar o conjunto pendente e **digite a palavra** que a confirmação pedir. Digite
   errado de propósito na primeira vez.
4. Confirme de verdade e confira a pasta `C:\ProgramData\WinForge\acl-backup` depois.
5. Repita com um backup que foi para outro disco, com o disco **desligado**.

**O que observar**

- Backup que ainda serve para desfazer **não** é marcado para apagar sozinho — ele só sai sob a
  confirmação digitada.
- A palavra digitada errada não apaga nada.
- Com o disco externo desligado, o botão diz onde o arquivo está e manda apagá-lo à mão, em vez de
  dizer que apagou.
- Ao reabrir o WinForge, se a pasta passar de 1 GB aparece um aviso na abertura. Ele só relata.

**Se der errado**

- Se ele apagar um conjunto pendente sem a confirmação digitada, registre e pare: é o backup do
  usuário que está em jogo.

---

## 5. O botão Parar numa operação longa

**ELEVAÇÃO** para a restauração de permissões; sem elevação para o `chkdsk /scan`. Risco: o teste
existe para provar que parar é seguro.

**Passos**

1. Comece pelo caso barato: `Verificar disco do sistema agora (chkdsk /scan)`. Deixe rodar meio
   minuto e clique em **Parar**. Leia a confirmação antes de aceitar.
2. Agora o caso caro: comece uma restauração de permissões e clique em **Parar** durante a fase 4
   (as pastas do sistema, uma a uma). Leia a confirmação.
3. Aceite, e espere.
4. Depois, clique em `Desfazer (restaurar backup)` e reinicie.
5. Repita o passo 2 parando durante a fase 5 (a herança do perfil).

**O que observar**

- Na fase de leitura, a confirmação diz que **nada foi alterado até agora**. Na fase de escrita,
  diz que algumas pastas já mudaram e que o Desfazer cobre todas elas.
- Depois do sim, o botão vira `Parando…` e o cabeçalho, `Parando: <título>`.
- A etapa em curso termina; as seguintes não começam. O fim do cabeçalho é
  **`Cancelado em mm:ss`**, nunca `Concluído`.
- Na fase 4, o texto final nomeia as pastas que já foram reescritas. Na fase 5, diz que a herança
  foi ligada só em parte do perfil e oferece as duas saídas.
- Numa operação que passe de uma vez e meia o tempo esperado, o cabeçalho muda de cor e avisa. É
  bom conferir isso num `sfc` ou num `DISM`, que demoram de verdade.

**Se der errado**

- Parar que não para, ou que deixa a fase 4 no meio sem avisar: registre o horário e o arquivo de
  saída, e rode o Desfazer.

---

## 6. Fechar a janela com um comando em andamento

**ELEVAÇÃO.** Risco: médio. **Este é o teste sem prova automática nenhuma** — o autoteste consegue
provar que o job encerra os filhos quando o próprio teste manda encerrar, e não consegue provar que
`KILL_ON_JOB_CLOSE` mata a árvore quando o WinForge morre de morte matada.

**Passos**

1. Comece um comando longo (a restauração de permissões, ou o `chkdsk /scan`).
2. Com ele rodando, abra o Gerenciador de Tarefas e anote o PID do `powershell.exe` do WinForge e o
   do processo filho (`icacls.exe`, `chkdsk.exe` — use a visão em árvore, em Detalhes).
3. Clique no X da janela de saída. Leia a pergunta e responda **Não**. O comando tem de continuar.
4. Clique no X de novo e responda **Sim**.
5. Repita do passo 1, mas agora **mate o WinForge pelo Gerenciador de Tarefas** (Finalizar tarefa
   na árvore do processo principal), em vez de fechar pela janela.
6. Depois de cada um, confira no Gerenciador de Tarefas se sobrou algum `icacls.exe` ou
   `chkdsk.exe` vivo.

**O que observar**

- No passo 3, "Não" é a resposta padrão e o comando continua.
- Nos passos 4 e 5, o processo filho tem de **sumir junto**. Um `icacls.exe` elevado sobrevivente
  reescrevendo permissão de pasta do sistema é exatamente o que esta versão existe para impedir.
- Se o WinForge for morto durante a **troca de posse da fase 4**, a próxima abertura tem de
  **relatar** a pasta e o dono original, apontando o botão que resolve. Ele nunca conserta sozinho.
  Esse caso é difícil de acertar no tempo: tente, e se não conseguir, registre que não conseguiu.

**Se der errado**

- Filho vivo depois de matar o WinForge: mate-o à mão pelo Gerenciador de Tarefas, reinicie a
  máquina e registre. Depois do reinício, rode `Permissões do disco C: - Verificar` para saber em
  que estado as pastas ficaram.

---

## 7. A escada de rede, do diagnóstico à troca de driver

**PODE FICAR SEM REDE.** **ELEVAÇÃO** dos degraus 3 em diante. Faça este teste **com o cabo de rede
ligado** e funcionando, e confira antes que você consegue navegar pelo cabo com o Wi-Fi desligado.
Esse é o caminho de volta.

**Passos**

1. `Rede — Diagnóstico completo`. Leia o relatório inteiro e a frase final. Cronometre.
2. Se a máquina tiver antivírus de terceiro, confira que ele aparece nomeado, com o caminho de menu
   para desligá-lo.
3. `Rede — Limpar cache de DNS e pegar endereço novo`. Confira antes e depois com `ipconfig /all`.
4. `Rede sem fio — Reinstalar o driver que já está instalado`. É aqui que o WinForge usa
   `remove-device` e manda o Windows procurar de novo. Cronometre e fique olhando a bandeja.
5. Confira em `C:\ProgramData\WinForge\driver-backup` que a cópia do driver existe e tem o `.inf` e
   o `.cat`. Anote o tamanho (no rádio Intel de referência foram 10 arquivos e 120 MB).
6. `Rede sem fio — Voltar para o driver que estava antes`. É aqui que o WinForge usa `add-driver`
   com instalação. Leia o que o relatório diz que o adaptador virou.
7. Só então, e só se o botão aparecer: `Rede sem fio — Trocar pelo driver básico do Windows`.
   Digite a palavra que ele pedir. Este é o degrau que apaga pacote de driver.
8. Com o driver básico no lugar, teste a rede sem fio de verdade: desligue o cabo, conecte no
   Wi-Fi, abra um site, rode uma transferência grande.
9. Volte com `Rede sem fio — Voltar para o driver que estava antes` e reinicie.

**O que observar**

- O diagnóstico não altera nada e termina em segundos. A frase final é uma das cinco e diz por onde
  começar.
- O passo 4 devolve o **mesmo** driver: fornecedor e versão iguais aos de antes, no Gerenciador de
  Dispositivos.
- Nos passos 4, 6 e 7, desfecho ruim (adaptador sumido, código de problema, ou outro driver
  assumindo) tem de devolver o driver guardado **na hora, sem perguntar**.
- No passo 7, o botão só aparece quando existe driver **inbox** para aquele rádio. Em MediaTek,
  Realtek recentes e Intel novos ele costuma não aparecer, e isso **é** o comportamento certo —
  registre qual rádio a máquina tem e se o botão apareceu ou não.
- O passo 8 é o teste que ninguém fez ainda: **ninguém sabe se o driver básico do Windows funciona
  com esse rádio**. O pacote da Intel traz um `Setup.exe` de 17 MB, o que sugere que o fabricante
  espera um instalador, e não só um arquivo `.inf`. Se o Wi-Fi não funcionar com o básico, é uma
  descoberta, não um defeito do teste — registre e volte pelo passo 9.
- Confira os nove bloqueios pelo menos por amostragem: tente o passo 4 por Área de Trabalho Remota
  (tem de recusar), e com o notebook na bateria (tem de recusar).

**Se der errado**

- Sem Wi-Fi depois de qualquer passo: ligue o cabo e use `Rede sem fio — Voltar para o driver que
  estava antes`.
- Se nem isso trouxer o rádio de volta: baixe o driver do fabricante **em outro computador**, traga
  por pen drive e instale à mão. O nome do adaptador e o fabricante estão no relatório do passo 1.
- Se a máquina ficar sem rede nenhuma, o ponto de restauração do Windows é a última saída.

---

## 8. A tabela de drivers e o lote de chipset

**ELEVAÇÃO.** Risco: alto na parte do lote — **esta ação não tem Desfazer pelo WinForge**.

Este teste **só pode ser feito numa máquina que receba a oferta**: uma placa-mãe com muitos
componentes, tipicamente um desktop Intel mais velho (o caso de origem é um X99), com o Windows
Update oferecendo dezenas de arquivos de informação de chipset. Numa máquina que não recebe a
oferta, o máximo que dá para conferir é que a tabela continua mostrando uma linha por dispositivo.

**Passos**

1. Na aba **Diagnóstico**, clique em "Buscar drivers no Windows Update" e espere a tabela.
2. Fotografe a tabela. Anote quantas linhas vieram e se apareceu uma **linha de grupo**.
3. Se apareceu: clique em **Ver lista** e confira que os títulos são mesmo os arquivos de
   informação, e não um driver de verdade escondido no meio.
4. Antes de instalar, abra o Gerenciador de Dispositivos e fotografe os itens com ponto de
   exclamação ("Dispositivo PCI", "Controlador de barramento SM", "Dispositivo de sistema base").
5. Clique em **Instalar todos (N)** e leia a confirmação inteira antes de aceitar.
6. Espere o lote terminar. Reinicie se ele pedir.
7. Fotografe o Gerenciador de Dispositivos de novo e compare com o passo 4.
8. Confira em Painel de Controle > Sistema > Proteção do Sistema que **apareceu um ponto de
   restauração novo**, criado antes do lote.

**O que observar**

- A linha de grupo traz o fornecedor e a contagem, "sem número de versão" na coluna de versão, e o
  botão **Instalar todos (N)**.
- O contador anda para a frente durante o lote e a linha termina contando quantos instalaram e
  quantos falharam. Clicar de novo instala **só** o que faltou.
- Sem ponto de restauração novo, **o lote não pode rodar** — e o texto tem de dizer se é porque a
  Proteção do Sistema está desligada ou porque já houve um ponto nas últimas 24 horas. Vale testar
  os dois casos de propósito.
- Depois do lote, os dispositivos passam a mostrar o nome real. Um "Dispositivo PCI" que precisava
  de driver **de verdade** continua sem ele e muda só o nome — isso é esperado, e é o limite
  escrito na confirmação.
- Aproveite para anotar, dessa máquina, o que o WinForge ainda não viu numa oferta real: a classe
  de driver, o tamanho de cada item e a categoria. Esses três valores estão marcados como
  provisórios no código e é essa medição que os fecha.

**Se der errado**

- Máquina instável depois do lote: use o ponto de restauração criado no passo 8.
- Um dispositivo que funcionava parar de funcionar: Gerenciador de Dispositivos, Propriedades >
  Driver > **Reverter Driver** nesse dispositivo. É a única volta, e é por isso que o ponto de
  restauração é obrigatório.

---

## O que este roteiro não cobre

- **A máquina quebrada de verdade.** Todos os testes de permissão acima são numa máquina saudável.
  O caso que originou o recurso — disco sem a cadeia de permissões depois de uma atualização de
  fabricante — não tem como ser reproduzido aqui sem quebrar uma máquina de propósito. Se aparecer
  uma máquina assim, ela vale mais que este roteiro inteiro.
- **Disco quase cheio.** A conferência de espaço antes do backup de driver (120 MB) existe, mas
  nunca foi exercitada com o disco no limite.
- **Rádios que não sejam o Intel de referência.** O comportamento do driver básico muda por
  fabricante, e o teste 7 mede um rádio de cada vez.
- **Ofertas de driver do Windows Update fora da máquina do caso.** Sem a oferta, o critério de
  agrupamento não é exercitado com dado real.

Quando um destes testes for executado, registre o resultado junto do número do teste, a máquina e a
data. Teste que ninguém rodou vale como teste que falhou.
