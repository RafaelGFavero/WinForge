<img src="assets/logo.svg" alt="WinForge" width="128" height="128">

# WinForge

![build](https://github.com/RafaelGFavero/WinForge/actions/workflows/build.yml/badge.svg)

Utilitário de otimização e reparo para Windows 10, 11 e Server. Reúne em uma única janela os
ajustes de desempenho, privacidade, jogos e manutenção que normalmente exigiriam dezenas de
comandos avulsos — cada um reversível, com Desfazer, e com um ponto de restauração opcional
criado antes de qualquer alteração. O que não se aplica ao seu computador não aparece: recursos
exclusivos do Windows 11 ficam ocultos no Windows 10, e tweaks de GPU só aparecem para a marca
de placa que você tem.

## Download

Baixe na página de [releases](https://github.com/RafaelGFavero/WinForge/releases):

- `WinForge.exe` — o programa inteiro em um único arquivo, sem instalação.
- `WinForge-<versão>.zip` — o mesmo executável junto com `README.md`, `LICENSE` e `NOTICE`.

## Como usar

1. Execute o `WinForge.exe`. Ele pede elevação de administrador (os ajustes não funcionam sem ela).
2. Responda à pergunta de ponto de restauração que aparece ao abrir: crie o ponto se quiser poder
   voltar atrás pelo próprio Windows, ou pule se preferir usar só o Desfazer da ferramenta.
3. A janela abre no **Diagnóstico**, que levanta o perfil da máquina e lista o que é recomendado
   para ela. Marque na própria lista o que quiser aplicar — cada item marcado ali fica marcado
   também na aba de origem (Ajustes, Jogos ou Servidor).
4. Vá à aba correspondente e clique em aplicar. Cada ajuste tem o seu Desfazer.

Na primeira execução o `WinForge.exe` extrai o motor em `%ProgramData%\WinForge\engine\<versão>\`,
junto com o `NOTICE.txt` e o `LICENSE.txt`. Essa pasta é gravável só por administradores e pelo
SYSTEM — o motor roda elevado e não pode ficar em um diretório que qualquer usuário altere. Os
logs e os backups de registro continuam em `%LocalAppData%\WinForge`.

Parâmetros de linha de comando:

| Parâmetro | O que faz |
|---|---|
| `-RestorePoint` | Cria o ponto de restauração ao abrir, sem perguntar. |
| `-NoRestorePoint` | Não pergunta nem cria ponto de restauração. |
| `-Console` | Mantém a janela de console visível (útil para ver erros). |
| `-HardwareRender` | Usa renderização WPF por hardware em vez do padrão por software. |
| `-SelfTest` | Valida configurações, XAML e montagem das abas sem abrir a janela (rodando o `dist\engine\WinForge.ps1` diretamente não exige administrador; pelo `.exe` pede elevação). |

## Interface

A interface é toda em português. As abas ficam na barra de cima, na ordem em que costumam ser
usadas — primeiro diagnosticar, depois ajustar, instalar por último:

| # | Aba | Atalho | O que tem |
|---|---|---|---|
| 1 | Diagnóstico | `Alt+D` | O que foi detectado na máquina, a lista de recomendações e a tabela de drivers. É a aba que abre. |
| 2 | Ajustes | `Alt+T` | Desempenho, privacidade, energia, serviços, anúncios, Cortana, pesquisa, VBS, limpeza de disco, backup do registro, cache de RAM, otimização de unidades e a remoção de aplicativos pré-instalados (AppX). |
| 3 | Jogos | `Alt+J` | Prioridade de CPU por jogo (IFEO), GameDVR, MMCSS, HAGS e shader cache para NVIDIA, AMD e Intel. |
| 4 | Configurações | `Alt+C` | Recursos do Windows, correções de sistema, reparo de componentes, painéis clássicos e atalhos de manutenção. |
| 5 | Servidor | `Alt+S` | Só no Windows Server: ajustes gerais do servidor, IIS e Active Directory. Em máquina cliente o botão nem aparece. |
| 6 | Atualizações | `Alt+U` | Política do Windows Update em três perfis: Recomendado, Padrão do Windows e Desativar atualizações. |
| 7 | Instalar | `Alt+I` | Instalação de programas em lote pelo WinGet ou pelo Chocolatey. |
| 8 | ISO Win11 | `Alt+W` | Criação de mídia de instalação do Windows 11. |

Na barra de cima, à direita, ficam ainda a busca (`Ctrl+F`, nas abas que têm lista), o **tema**
(Automático, que segue o Windows, Escuro ou Claro), o **tamanho da fonte** e o menu de
importar/exportar configuração.

A aba **Instalar** traz 137 programas divididos em 9 grupos — Comunicação, Desenvolvimento,
Documentos, Ferramentas Microsoft, Ferramentas profissionais, Jogos, Multimídia, Navegadores e
Utilitários. Os grupos abrem fechados; as fichas de filtro logo abaixo da busca mostram um grupo
de cada vez (`Ctrl+clique` para escolher mais de um).

A janela se adapta ao sistema: no Windows 10, os itens que só existem no Windows 11 não são
exibidos; os ajustes marcados para uma marca de GPU só aparecem se aquela GPU for detectada; e no
Windows Server as abas de consumidor dão lugar à aba Servidor.

## Diagnóstico e recomendações

Ao abrir a janela, o WinForge levanta o perfil da máquina em segundo plano (uma barra de progresso
mostra o andamento): versão e edição do Windows, papéis de servidor como IIS e Active Directory,
se é notebook, desktop ou máquina virtual, processador, memória, placas de vídeo, tipo de disco
(SSD ou HDD), rede, plano de energia e o inventário de drivers com versão e data.

Com esse perfil, um conjunto de regras avalia cada item e desenha um contorno na linha:

- **Verde**, `✔ Recomendado: <motivo>` — faz sentido nesta máquina. Exemplo: em desktop na tomada,
  desligar a hibernação e o plano de energia sem suspensão de USB ficam verdes.
- **Laranja**, `⚠ Não recomendado neste sistema: <motivo>` — não faz. Esses mesmos dois itens ficam
  laranja em notebook, onde gastam bateria; desativar o Prefetch/Superfetch fica laranja quando há
  HDD na máquina; e em máquina virtual timer, HAGS, VBS e energia ficam laranja porque quem decide
  é o host.

O motivo completo aparece na dica ao passar o mouse sobre a linha. Nenhuma recomendação marca nada
sozinha: quem marca é você.

A aba **Diagnóstico** (`Alt+D`) reúne isso em nove cartões — Sistema, Máquina, Processador,
Memória, Placa de vídeo, Armazenamento, Rede, Energia, e Segurança e estado —, mais um décimo,
Servidor, no Windows Server, a lista das recomendações com seus motivos e a tabela dos drivers
instalados.

**A lista de recomendações é um checklist espelhado.** Cada linha tem uma caixa de seleção, e ela
é a MESMA marcação da aba de origem: marcar a linha aqui marca o item na aba Ajustes, Jogos ou
Servidor, e marcar lá marca a linha aqui. O contador ao lado dos botões (`N de M recomendados
marcados · A já aplicados`) acompanha os dois sentidos. Os toggles ficam de fora do checklist:
eles aplicam o ajuste no instante em que são ligados, e recomendação não muda o sistema.

**E dá para aplicar sem sair daqui.** Ao lado do contador ficam **Aplicar marcados** e **Desfazer
marcados**: eles chamam o mesmo caminho dos botões da aba Ajustes, sobre os mesmos itens marcados —
inclusive o ponto de restauração, que é criado primeiro quando "Ponto de restauração - Criar"
estiver entre eles. Não há um segundo caminho de aplicação: marcar a linha aqui marca a caixa de
verdade na aba de destino, e é ela que é aplicada. Os dois ficam desabilitados enquanto já há
trabalho em andamento.

| Botão | O que faz |
|---|---|
| Atualizar diagnóstico | Coleta o perfil de novo e reavalia as recomendações. |
| Buscar drivers no Windows Update | Pergunta ao Windows Update quais drivers ele tem para este computador (pode levar até um minuto). |
| Exportar relatório HTML | Gera um relatório HTML com tudo desta aba e abre no navegador. |
| Marcar todos | Marca todas as linhas do checklist — e, com elas, os itens correspondentes nas abas Ajustes, Jogos e Servidor. |
| Desmarcar todos | O contrário. |
| Aplicar marcados | Aplica os itens marcados, igual ao botão da aba Ajustes. |
| Desfazer marcados | Desfaz os itens marcados, igual ao botão Desfazer da aba Ajustes. |

### O que já está aplicado

Junto com o perfil, o diagnóstico de abertura confere quais ajustes **já estão em vigor** nesta
máquina. O que estiver aplicado aparece assim:

- Nas abas Ajustes, Jogos e Servidor, a linha ganha um `· aplicado` ao lado da caixa, e a dica
  começa com "✔ Já aplicado neste sistema.".
- No checklist do Diagnóstico, o contador soma a conta: `N de M recomendados marcados · A já
  aplicados`. **Marcar todos** deixa essas linhas de fora. Você pode marcá-las na mão, mas isso
  não força nada: **Aplicar** pula o que está aplicado, com ou sem a caixa marcada. Para aplicar
  de novo, **Desfazer** primeiro e **Aplicar** em seguida — é o único caminho.
- **Aplicar** refaz a detecção no momento do clique, porque você pode ter desfeito algo desde que
  a janela abriu, e pula o que já está em vigor. No fim, a barra diz "Aplicados: A · já estavam
  aplicados: S", e as linhas que acabaram de ser aplicadas já aparecem marcadas — a detecção é
  refeita ao terminar, sem esperar o próximo diagnóstico.

Nunca são pulados: o ponto de restauração, os toggles, botões e listas — que agem no instante do
clique e não têm estado a detectar — e todo ajuste que, além de mexer no registro ou num serviço,
roda um script. A detecção enxerga registro e serviço; a hibernação, por exemplo, grava duas
chaves e ainda chama `powercfg /hibernate off`, e pular com as chaves já gravadas deixaria a
hibernação ligada.

### Drivers: a coluna Ação

Para placas NVIDIA, a versão instalada é comparada com a mais recente do catálogo do fabricante
(consulta ao site da NVIDIA, guardada por 24 horas em `%LocalAppData%\WinForge\cache`). A última
coluna da tabela oferece, por linha, uma destas ações — e nenhuma delas acontece sozinha:

- **Baixar `<versão>`** — só aparece numa placa NVIDIA que esteja atrás e cujo link do catálogo
  seja de um domínio oficial da NVIDIA. O arquivo é gravado em
  `%ProgramData%\WinForge\downloads`, uma pasta cuja cadeia inteira tem de ser gravável apenas por
  SYSTEM e Administradores (se não for, o download é recusado antes de começar). Depois de baixar,
  o WinForge **confere a assinatura digital** do instalador e exige o nome exato do certificado da
  NVIDIA; assinatura inválida ou de outra empresa apaga o arquivo. Só então o instalador é aberto
  — pelo instalador da própria NVIDIA, com a interface dele, e a instalação é você quem conduz.
- **Página do fabricante** — abre o endereço de download da marca no seu navegador. Sem download e
  sem execução. É o que sobra para AMD, Intel e para qualquer linha em que a regra acima não valha.
- Linha sem nenhuma das duas fica sem botão.

A tabela de baixo, **Drivers oferecidos pelo Windows Update**, aparece depois de "Buscar drivers no
Windows Update" e traz o botão **Instalar**. Ele **sempre pede confirmação** numa caixa que nomeia
a atualização antes de baixar e instalar qualquer coisa — e o botão fica desabilitado quando o
WinForge não está elevado, porque instalar driver exige administrador.

É **uma linha por dispositivo**. O serviço costuma oferecer mais de uma revisão do mesmo driver, e
mostrar as duas é convidar a instalar a antiga: a tabela mantém só a mais nova, avisa no título
quantas escondeu (`· M versão(ões) mais antiga(s) oculta(s)`) e lista os títulos na dica. O que
conta como "mesmo driver" é modelo, fornecedor **e** classe juntos: o driver base e o INF de
extensão de uma mesma placa chegam com modelo e fornecedor iguais, são pacotes que se completam e
por isso ficam os dois. A coluna **Versão** sai do próprio título da atualização.

**Dezenas de arquivos de informação viram uma linha só.** Em placa-mãe cheia de componentes — um
desktop com chipset X99, por exemplo — o Windows Update oferece dezenas de entradas que não trazem
driver nenhum: são arquivos que apenas dão nome ao componente no Gerenciador de Dispositivos. Elas
passam a ocupar uma **linha de grupo**, com o fornecedor e a contagem no título (`Intel — 47 itens
que só dão nome a componentes da placa-mãe`), a coluna Versão dizendo "sem número de versão", um
botão **Ver lista** que abre os títulos de todos os membros e um **Instalar todos (47)** que roda o
lote inteiro de uma vez. O estado é recontado a cada remontagem da tabela ("12 de 47 instalados, 1
falhou, 34 pendentes"), e o segundo clique instala só o que faltou.

Para virar grupo são quatro condições ao mesmo tempo: título sem número de versão, classe dentro de
uma lista de permissão fechada, tamanho conhecido e abaixo do corte, e pelo menos cinco membros com
o mesmo fornecedor, a mesma classe e a mesma data. Qualquer dúvida deixa a linha sozinha — mostrar
uma linha a mais é barato, esconder o driver que você veio buscar é caro. Firmware, componente de
software e INF de extensão nunca são agrupados. O relatório HTML continua cru, uma linha por
atualização, com a coluna **Classe** e a nota de quantos itens a aba agrupou.

**Quando o grupo é de chipset Intel, o WinForge cria um ponto de restauração antes do lote**, e não
instala nada se não conseguir criá-lo. O Windows ignora esse pedido em silêncio com a Proteção
do Sistema desligada, e também quando já existe um ponto das últimas 24 horas; o WinForge confere
que apareceu um ponto novo e diz qual dos dois casos impediu. Três limites, escritos na
confirmação:

- **Não há como desfazer isso pelo WinForge.** A única volta é o Gerenciador de Dispositivos, em
  Propriedades → Driver → Reverter Driver, dispositivo por dispositivo.
- Esses arquivos **não são o driver que faz o dispositivo funcionar**. Eles não instalam SMBus
  funcional, Intel ME/HECI, Serial IO, DPTF nem Rapid Storage: depois do lote, um "Dispositivo PCI"
  que precisava de driver de verdade continua sem ele e muda só de nome.
- Desempenho não muda. A própria Intel diz que, fora de uma instalação do Windows, não é preciso
  instalar esses arquivos. Se nenhum dispositivo da máquina estiver sem nome, o texto avisa que
  instalar não traria efeito visível.

O WinForge não baixa nem executa instalador de fabricante para isso. O lote vai pela via do Windows
Update, com as mesmas entradas que a tabela mostra.

Depois do clique em Instalar, a linha conta o que aconteceu: "instalando…", depois "instalado" (ou
"instalado (reinicie)") em verde, ou "falhou (código N)" em vermelho. A coluna **Situação** repete
em palavras o que a cor diz. O botão continua na linha, desabilitado enquanto ela estiver
"instalando…" ou "instalado", e clicável de novo na que falhou. Esse estado
vale só enquanto a janela estiver aberta: quem sabe o que está instalado é o Windows Update, e na
próxima abertura é ele que responde.

O relatório HTML descreve a máquina inteira: nome do computador, fabricante e modelo, modelos dos
discos, servidores DNS e o estado de BitLocker, Secure Boot e TPM. O arquivo fica em
`%LocalAppData%\WinForge\reports` e não sai da máquina sozinho — só vale saber o que vai junto
antes de mandá-lo para outra pessoa.

Cada etapa do diagnóstico vai para o log da sessão, em `%LocalAppData%\WinForge\logs`. Ao abrir, o
WinForge mantém ali as 30 sessões mais recentes e apaga as anteriores.

## Windows Server

Se o Windows for Server, a janela muda de forma sozinha: aparece a aba **Servidor** (`Alt+S`) e
somem as abas que não fazem sentido ali — Jogos e ISO Win11. A detecção acontece antes
de a janela ser montada e lê a edição do Windows e os papéis instalados; hoje o WinForge reconhece
IIS, Active Directory (inclusive se a máquina é controlador de domínio), Hyper-V, DNS, DHCP,
servidor de arquivos e RDS.

A aba reúne os ajustes por assunto. Os itens de servidor valem para qualquer Server; os de IIS e de
Active Directory só aparecem quando o papel está instalado.

**Servidor** — ajustes gerais, cada um com seu Desfazer:

| Item | O que faz |
|---|---|
| Não abrir o Gerenciador do Servidor no logon | Tira o Server Manager da abertura automática, para a máquina e para o usuário atual. |
| Desativar o Rastreador de Eventos de Desligamento | Desliga a caixa que pede o motivo a cada desligamento. O motivo deixa de ir para o log de eventos. |
| Plano de energia Alto desempenho | Ativa o plano recomendado para servidor, sem redução de clock em ocioso. |
| RDP: exigir NLA e tempo limite de sessão ociosa (30 min) | Exige autenticação antes de abrir a sessão e derruba sessões paradas. Clientes antigos sem NLA param de conectar. |
| Desativar o SMB1 no servidor | Desliga o protocolo obsoleto. Dispositivos que só falam SMB1 (multifuncionais, NAS velhos) perdem o acesso. |
| TCP: nível de ajuste automático 'normal' | Devolve o autotuning da janela TCP ao padrão do Windows, desfazendo o `disabled` que scripts antigos deixam para trás. |

Esses quatro — mais a exigência de assinatura SMB, em "Avançado (CUIDADO)" — não moram no registro, então o
WinForge **lê o estado atual antes de mexer** e grava em `%ProgramData%\WinForge\iis-backup`, como já fazia
com o IIS. O **Desfazer** devolve exatamente o que estava lá: num servidor onde o SMB1 já vinha desligado,
desfazer não o liga; num controlador de domínio onde a assinatura já é obrigatória por política, desfazer
não a remove. Sem backup (item nunca aplicado), o Desfazer não faz nada.

**IIS** — todos os pools e sites de uma vez: iniciar sempre (`AlwaysRunning`), sem tempo limite de
ociosidade, reciclar por memória em vez de por tempo, pré-carregar os sites (`preloadEnabled`),
compressão estática e dinâmica, cache de saída e de kernel, e fila de 5000 com as requisições
concorrentes do ASP.NET liberadas.

**Avançado (CUIDADO)** — os três itens que cobram um preço ficam aqui, como no resto do programa, e
não entram em nada automaticamente: desativar a Configuração de Segurança Reforçada do IE, exigir
assinatura SMB e a reciclagem de pool por memória (que na tela aparece só nessa categoria, e não
junto dos outros itens de IIS).

Antes de mexer em qualquer configuração do IIS, o WinForge grava os valores anteriores em
`%ProgramData%\WinForge\iis-backup\<item>-<data-hora>.json`. O **Desfazer** junta todos os backups
vivos daquele item e devolve, propriedade por propriedade, o valor **mais antigo** — o de antes da
primeira aplicação, e não o da última. É isso que mantém a promessa depois de um pool novo: aplicar
de novo grava um backup só com o que mudou, e sem essa junção o Desfazer deixaria os pools antigos
mexidos para sempre. Os arquivos consumidos viram `<nome>.restored.json` e saem da conta, para que
uma aplicação seguinte comece de um backup limpo. Aplicar duas vezes não muda nada na segunda: o
que já está no valor desejado é pulado, e o backup só é gravado quando há mesmo algo a mudar.

A pasta de backup é criada pelo próprio WinForge com permissões próprias — sem herança, só SYSTEM e
Administradores — e é conferida antes de todo Desfazer: pasta que pertence a outra pessoa, que dê
escrita a quem não é administrador ou que seja um link é recusada, com a mensagem na tela e nada
alterado. Do arquivo, só volta o que aquele item de fato escreve; qualquer outra chave é ignorada e
registrada no log. Sem isso, um JSON plantado na pasta viraria escrita arbitrária no
`applicationHost.config` na primeira vez que alguém clicasse em Desfazer.

Os dois itens que dependem de recurso do Windows — pré-carregar (Inicialização de
Aplicativos, `Web-AppInit`) e a parte dinâmica da compressão (`Web-Dyn-Compression`) — avisam e
seguem sem alterar aquilo quando o recurso não está instalado. **O WinForge não instala recurso
nenhum do Windows.**

Os botões só leem, nunca alteram. Os três primeiros ficam no grupo **Servidor**; os quatro últimos,
no grupo **Active Directory**, que só aparece quando o papel de AD está instalado:

| Botão | O que mostra |
|---|---|
| Verificar fonte de horário (w32tm) | A fonte de horário configurada e o estado do serviço W32Time. |
| Listar exclusões do Defender | As exclusões de caminho, extensão e processo do Microsoft Defender. |
| Mostrar parâmetros TCP | `Get-NetTCPSetting` e `Get-NetOffloadGlobalSetting`: autotuning, congestionamento, ECN, RSS. |
| Executar dcdiag /q | Só o que está errado no controlador de domínio. Sem saída significa sem erro. |
| Resumo de replicação (repadmin) | Atrasos e falhas de replicação por parceiro (`repadmin /replsummary`). |
| Limpeza de registros DNS (scavenging) | A configuração de limpeza automática de registros DNS antigos. |
| Onde estão NTDS e SYSVOL | Em que disco e pasta estão o banco do AD, os logs de transação e o SYSVOL, marcando o que está no disco do sistema. |

A saída abre em uma janela à parte, que não trava a principal, com **Copiar** e **Abrir arquivo**;
o mesmo texto fica salvo em `%LocalAppData%\WinForge\logs\server-<nome>-<data-hora>.txt`. Quando a
ferramenta não existe na máquina (dcdiag e repadmin só vêm com as ferramentas de AD), a janela diz
isso em vez de falhar.

O que foi detectado no servidor aparece no cartão **Servidor** da aba Diagnóstico e no relatório
HTML — papéis, estado do SMB1, assinatura SMB, ajuste automático TCP, fonte de horário, quantidade
de pools e sites do IIS com a pasta de logs, e os caminhos de NTDS e SYSVOL num controlador de
domínio. As recomendações também levam o servidor em conta: itens de jogos e de consumidor ficam
laranja, o SMB1 ligado é apontado, e logs do IIS ou banco do AD no disco do sistema viram aviso.

**Nada da aba Servidor entra em preset.** Preset é para máquina de usuário; em servidor de produção
cada item se marca à mão, e o botão "Marcar recomendados" da aba deixa tudo visível antes de você
aplicar.

Vale registrar onde a aba se afasta de propósito do que foi desenhado no começo, para ninguém
procurar o que não existe: o SMB1 é **desativado**, não desinstalado (o recurso do Windows continua
lá — o WinForge não remove recurso); o perfil de atualização "só de segurança" do Windows Update é
**texto de orientação** no rodapé da aba, e não um item que se aplica; a verificação de horário
(`w32tm`) fica no grupo **Servidor**, e não no grupo **Active Directory**, porque ela interessa
igualmente a um servidor membro; e telemetria no mínimo, Delivery Optimization e hibernação
continuam sendo itens da aba **Ajustes** recomendados pelo Diagnóstico, não itens da aba Servidor —
quem trabalhar só nesta aba não os verá.

## Reparo de componentes

Na aba **Configurações**, o grupo **WinForge - Reparo de componentes** reúne vinte e um botões para
os problemas que não se resolvem com tweak: componente que sumiu, repositório corrompido, disco com
suspeita de defeito, permissão de pasta perdida, rede que conecta e não navega. Na mesma coluna
fica o grupo **Correções**, que veio do utilitário de origem e usa a mesma janela de saída ao vivo
(ver [Correções](#correções-os-cinco-botões-que-demoram) mais abaixo).

**Só leem, não mudam nada (e o do DirectX só abre uma página):**

| Botão | O que faz |
|---|---|
| Estado de TPM, Secure Boot e BitLocker | TPM presente e pronto, Secure Boot ligado, BitLocker de cada volume e a segurança baseada em virtualização (VBS/Credential Guard). |
| Saúde dos discos (SMART) | Discos físicos e os contadores SMART de cada um: temperatura, horas ligado, desgaste e erros não corrigidos. Em USB e em alguns RAID os contadores não existem. |
| Estado do .NET Framework 3.5 e 4.8 | Se o recurso NetFx3 está habilitado e qual versão da linha 4.x está instalada, lida do valor Release do registro. |
| Verificar disco do sistema agora (chkdsk /scan) | Verificação online, com o sistema em uso: relata problemas, não repara nada e não reinicia. Pode demorar minutos num disco grande. |
| DirectX: abrir a página oficial da Microsoft | Abre no navegador a página oficial de download do DirectX End-User Runtime Web Installer. Quem baixa e roda o `dxwebsetup.exe` é você, no navegador: o WinForge não baixa nem executa arquivo da internet. O instalador é interativo e traz as bibliotecas antigas (d3dx9, XInput) que jogos mais velhos pedem. |
| Rede — Diagnóstico completo | Doze pontos da rede deste computador, do rádio sem fio ao catálogo Winsock, com uma frase de veredito no fim dizendo por onde começar. Nenhum driver é tocado. Ver [Rede](#rede-a-escada-de-seis-degraus) mais abaixo. |

**Alteram o sistema:**

| Botão | O que faz |
|---|---|
| Repositório WMI: verificar e recuperar | `winmgmt /verifyrepository` e, só se o repositório estiver inconsistente, `winmgmt /salvagerepository`. Programas que consultam o WMI podem falhar durante a recuperação. |
| Microsoft Store e App Installer: registrar de novo | Registra de novo, para o usuário atual, a Store, o App Installer (winget) e o Store Purchase App a partir do manifesto que já está no disco, sem baixar nada. É o reparo de "a Store não abre" e de "o winget sumiu". |
| Agendar chkdsk /f na próxima reinicialização | Marca o disco do Windows como sujo (`fsutil dirty set`): o chkdsk roda com reparo antes de o Windows carregar. **Não tem desfazer** — quem limpa a marca é o próprio chkdsk, e só quando o volume estiver íntegro, então num disco com problema a verificação se repete a cada reinicialização. |
| Diagnóstico de memória na próxima reinicialização | Coloca o Diagnóstico de Memória na sequência de inicialização (`bcdedit /bootsequence {memdiag}`), válido só para a próxima. O resultado aparece no Visualizador de Eventos. |

**Instalam componente:**

| Botão | O que faz |
|---|---|
| .NET Framework 3.5: habilitar (DISM) | Habilita o recurso NetFx3 pelo DISM. Os arquivos não estão na imagem instalada: vêm do Windows Update, então precisa de internet. Em rede com WSUS restritivo o DISM pede a mídia do Windows. |
| Visual C++ 2005–2022 (x86/x64) via winget | Os 12 redistribuíveis (2005, 2008, 2010, 2012, 2013 e 2015-2022), nas duas arquiteturas. O que já está instalado é pulado. É o que resolve erro de VCRUNTIME140.dll e MSVCP140.dll. |
| PowerShell 7 via winget | Instala o `Microsoft.PowerShell` lado a lado: o Windows PowerShell 5.1 continua instalado e é ele que roda o WinForge. |

**Permissões do disco C: (quatro botões):** a seção
[Permissões do disco C:](#permissões-do-disco-c) explica os quatro em detalhe, porque o que eles
mexem não cabe numa linha de tabela.

**Rede (cinco botões, mais um que já existia):** a seção
[Rede: a escada de seis degraus](#rede-a-escada-de-seis-degraus) explica a ordem em que eles são
para ser usados e o que cada um não faz. Os três que mexem em driver ficam no fim da escada, e é lá
que estão os bloqueios que podem impedir o clique.

**Nada roda sem clique e confirmação.** Os botões que só leem rodam direto. Os que alteram o
sistema ou instalam componente abrem antes uma caixa de Sim/Não com a descrição inteira do botão —
o mesmo texto que está na aba, com o aviso na primeira linha. Responder "Não" não deixa rastro.

Tudo roda fora da thread da interface: a janela continua respondendo enquanto o comando trabalha. A
saída aparece numa janela própria, que não bloqueia o resto do programa, com **Copiar** e **Abrir
arquivo**. O arquivo é `repair-<nome>-<data-hora>.txt`, na mesma pasta de logs do WinForge
(`%LocalAppData%\WinForge\logs`). Nos comandos longos a janela mostra a saída **ao vivo**, linha a
linha, e o cabeçalho conta o tempo: "Em andamento: `<título>` (mm:ss)" vira "Concluído em mm:ss
(código N)" quando o trabalho termina.

A saída é transmitida linha a linha, e não guardada até o fim: o que a janela mostra tem teto de
2 MB, e o arquivo, 256 MB por execução — passando disso, uma linha avisa que os detalhes dali em
diante foram descartados. O WinForge guarda 30 dias ou 20 arquivos de cada tipo de comando, o que
vier primeiro. Quando a operação passa de uma vez e meia o tempo que ela costuma levar, o cabeçalho
muda de cor e diz quanto é o comum; ao passar do triplo, repete o aviso com mais destaque. Nos dois
casos ele diz a mesma coisa: continua rodando, isso não é travamento.

**Parar.** Os comandos com saída ao vivo têm um botão **Parar** à esquerda do Fechar. Ele não mata
a etapa que está rodando; essa termina. O que ele impede é a seguinte de começar. A confirmação diz
o que você perde: numa fase de leitura, nada foi alterado até ali; numa de escrita, o que já mudou
é coberto pelo Desfazer, porque o backup é anterior à primeira alteração. Depois do sim o botão
vira "Parando…" e, no fim, o cabeçalho diz **Cancelado em mm:ss**, e não "Concluído". Fechar a
janela no meio de um comando que altera o sistema faz a mesma pergunta.

Fechar o WinForge no meio de um comando encerra também os programas que ele lançou. Até a versão
anterior, matar o WinForge pelo Gerenciador de Tarefas deixava um `icacls` elevado rodando sozinho.
A exceção é a troca de posse da fase 4 das permissões, que fica fora dessa amarração de propósito:
morrer entre tomar a posse e devolvê-la deixa uma pasta do sistema aberta a qualquer processo
elevado. Se o WinForge for encerrado justo ali, a abertura seguinte **relata** a pasta e o dono
original e aponta o botão que resolve; ele nunca conserta isso sozinho.

O que cada botão exige está escrito na descrição dele. Em resumo: WMI, chkdsk agendado, diagnóstico
de memória, .NET 3.5 e Visual C++ precisam do WinForge aberto como administrador; sem elevação, as
leituras de TPM, Secure Boot, BitLocker e NetFx3 respondem `n/d`. Os dois botões de winget precisam
do App Installer instalado e de internet. O .NET 3.5 também precisa de internet.

**O WinForge não baixa nem executa arquivo da internet.** O `winget.exe` que os botões de instalação
usam sai só do pacote do App Installer instalado pela Microsoft Store: editor `8wekyb3d8bbwe`,
assinatura de Store ou do sistema e pasta dentro de `%ProgramFiles%\WindowsApps`, sem link no
caminho. O `PATH` fica de fora de propósito — num processo elevado ele resolve para o atalho em
`%LOCALAPPDATA%\Microsoft\WindowsApps`, uma pasta que qualquer programa do usuário pode reescrever.
O registro de novo da Store e do App Installer aplica o mesmo crivo antes de escolher o manifesto.
Pelo mesmo motivo, todo executável do Windows que o WinForge chama (`chkdsk`, `winmgmt`, `fsutil`,
`bcdedit`, `powercfg`, `w32tm`, `dcdiag`, `repadmin`) é chamado pelo caminho completo em
`%SystemRoot%\System32`, e não pelo nome.

### Correções: os cinco botões que demoram

O grupo **Correções** da aba Configurações tem cinco botões que não respondem em segundos: **Rede -
Redefinir**, **Servidor NTP - Ativar**, **Verificação de corrupção do sistema - Executar**,
**Windows Update - Redefinir** e **WinGet - Reinstalar**. Eles rodavam na thread da janela e
escreviam num console que o lançador esconde — a aba congelava e nada aparecia na tela. Agora:

- Rodam num runspace, com a **janela de saída ao vivo** descrita acima. A janela abre na hora, com o
  cabeçalho, e se enche enquanto o comando trabalha.
- Passam pela mesma caixa de Sim/Não das ações que alteram o sistema, com a descrição do botão
  inteira — que foi reescrita para descrever o que de fato acontece.
- Cada passo fecha com uma linha `== Passo N: <nome> — código X ==`, e no fim o cabeçalho diz qual
  passo falhou. Num `chkdsk` + `sfc` + `DISM`, o código de um não apaga o erro do outro.
- A frase de fechamento ("Configuração de rede redefinida. Reinicie o computador.") só aparece
  quando **tudo** deu certo. Com erro, a última linha aponta o passo que falhou em vez de dizer que
  deu certo logo abaixo da linha que diz que não deu.
- **Fechar a janela no meio de um desses botões pergunta antes**, com "Não" como resposta padrão.
  Fechar interrompe o trabalho onde ele estiver: uma restauração de permissões parada entre "tomar
  a posse" e "devolver a posse" deixa a pasta do sistema aberta a qualquer processo elevado. Para
  leitura e diagnóstico o fechamento continua imediato, sem pergunta.

| Botão | O que roda |
|---|---|
| Rede - Redefinir | `netsh winsock reset` e `netsh int ip reset`. Conexões de VPN e proxy podem precisar ser refeitas; é preciso reiniciar para concluir. |
| Servidor NTP - Ativar | Inicia o serviço de Horário do Windows, troca `time.windows.com` por `pool.ntp.org` (`w32tm /config`), reinicia o serviço e força um `/resync`. Em máquina de domínio não use: ali quem dita o horário é o controlador de domínio. |
| Verificação de corrupção do sistema - Executar | `chkdsk /scan /perf`, depois `sfc /scannow`, depois `DISM /Online /Cleanup-Image /RestoreHealth`. A ordem é dependência: um setor ruim corrompe de novo o que o sfc consertou, e é o DISM que repõe a imagem de onde o sfc copia os arquivos bons. Pode levar mais de uma hora. |
| Windows Update - Redefinir | Para os serviços, limpa a fila do BITS, renomeia a pasta de downloads, registra as DLLs de novo e remove as configurações de WSUS. **Vai além do Windows Update:** apaga a diretiva de grupo local inteira, e com ela os ajustes do WinForge que moram em diretiva (enxugamento do Edge e do Brave, bloqueio de ConsumerFeatures, políticas de telemetria), que precisam ser marcados de novo. O histórico de atualizações é preservado. Reinicie no fim. |
| WinGet - Reinstalar | Se o winget já responde, não faz nada. Se não, instala o provedor NuGet, baixa da Galeria do PowerShell o módulo `Microsoft.WinGet.Client` e chama o `Repair-WinGetPackageManager`. Precisa de internet e confia na Galeria do PowerShell como fonte do módulo. |

Uma ressalva sobre os dois últimos: o corpo deles vem do utilitário de origem e não foi reescrito.
O WinForge resolve todo executável do sistema pelo **caminho completo** em `System32`, mas essas
duas funções da base ainda chamam `netsh`, `secedit`, `regsvr32`, `gpupdate` e `cmd` pelo `PATH`.
Numa máquina com o `PATH` adulterado é possível que um executável de mesmo nome seja encontrado
antes do do Windows. O comportamento é o mesmo de antes desta versão; o que mudou foi a descrição,
que agora diz tudo que essas funções fazem.

### Permissões do disco C:

O caso real: depois de uma atualização de fabricante, o disco do Windows perde a cadeia de
permissões — o dono da máquina fica sem acesso às próprias pastas, programas não abrem, "acesso
negado" em toda parte. São quatro botões, e a ordem entre eles é a do atendimento.

Se você rodou a restauração na versão 1.7.0 e a máquina travou com o disco enchendo, é o defeito
que a 1.8.0 conserta — a explicação está na fase 2, logo abaixo. A pasta de backup pode ter ficado
com dezenas ou centenas de GB de arquivo pela metade: o botão **Limpar backups antigos** é a saída,
e ele não apaga o backup que o Desfazer usa.

Três regras atravessam os que mexem em permissão: todo direito é concedido **por SID**, nunca por
nome (uma linha de `icacls` com `Administradores` falha calada num Windows em inglês, e a máquina
quebrada fica pior); nenhum comando é montado como texto, e todo executável vem pelo caminho
completo em System32; e nas pastas do sistema o `icacls` só faz duas coisas, **na própria pasta**:
`/setowner` quando o dono está fora do padrão e `/inheritance:r /grant:r` com as ACEs medidas.
`/reset`, `/T` e `/R` não existem ali, porque os três descem a árvore inteira apagando o que o
Windows sabe e o WinForge não.

**Verificar** — só lê, e pode ser clicado sempre (a leitura não pede elevação). Confere dono e
permissões da raiz do disco, de `Windows`, `Program Files`, `Program Files (x86)`, `ProgramData`,
`Users`, `Users\Public` e da sua pasta de usuário contra o padrão de fábrica, e termina com a
contagem das diferenças. Dois detalhes que explicam o resultado: a comparação é **por SID**, então
vale igual em qualquer idioma do Windows; e o que se cobra é um **piso** ("este SID tem ao menos
este direito"), não igualdade exata — ACE a mais não é diferença, porque uma pasta do sistema tem
ACEs que variam com a edição e com o que já foi instalado. A exceção é a ACE de **negação**:
qualquer uma conta, porque nenhuma dessas pastas tem negação de fábrica e a negação vence a
permissão — uma linha `Deny Todos:(OI)(CI)F` plantada em `C:\Users` tranca o disco sem tirar uma
única permissão da lista. Pasta que não existe nesta máquina não conta como diferença; pasta que
existe e não deixa ler a lista, conta.

**Restaurar padrões** — altera o sistema e pede reinicialização. Exige o WinForge aberto como
administrador, e a pergunta pela elevação vem antes de a pasta de backup ser criada. Seis fases,
nesta ordem:

1. `chkdsk /scan` no disco do sistema. Se ele acusar erro no volume, a restauração **para aqui** e
   nenhuma permissão é alterada: reescrever a DACL de um disco com problema é consertar o que vai
   corromper de novo.
2. **Backup** das listas atuais em `%ProgramData%\WinForge\acl-backup`, uma por pasta: a raiz, cada
   pasta de primeiro nível, cada pasta aninhada que a fase 4 pode reescrever (`Users\Public`) e a
   sua pasta de usuário. A regra é essa, e não uma lista: pasta que a restauração toca tem backup.
   De cada uma vão para o **índice** (um JSON na mesma pasta protegida) a lista de permissões em
   **SDDL** e o dono. Só a sua pasta de usuário ganha, além disso, um arquivo com o **conteúdo**
   dela — é a única pasta em que a restauração desce a árvore. É o que o botão Desfazer consome.

   Esse arquivo passou a ser escrito pelo próprio WinForge, e não mais por `icacls /save /T`. Sobre
   uma pasta de perfil o `/T` não é utilizável: o `/L` fala do link, não da caminhada, e as junções
   de compatibilidade do perfil apontam para o próprio pai (`AppData\Local\Dados de aplicativos`
   leva de volta a `AppData\Local`). O `icacls` entrava em laço e só parava no limite de 63 saltos
   de reparse do Windows — numa máquina real, cerca de 205 GB gravados e o computador travado
   depois de 404 minutos, ainda nesta fase. A caminhada de hoje lê o atributo de cada item antes de
   entrar nele, nunca entra em ponto de reanálise e guarda só as pastas com **herança bloqueada**,
   que são exatamente aquelas em que a fase 5 mexe. O mesmo perfil que gerava os 205 GB dá 338
   pastas, 103,4 KB e 39 segundos.

   A fase para sozinha em quatro tetos — 20.000 itens, 4 MB, 32 níveis de profundidade, 90
   segundos — e, quando para, **nada é alterado**. Não há "continuar mesmo assim": continuar sem
   backup é ficar sem Desfazer. Pasta cuja lista de permissões não pode ser lida é contada e
   nomeada no relatório, e o cabeçalho termina em "Concluído com ressalvas" — essas pastas não
   foram copiadas e também não foram alteradas.

   O SDDL não é preciosismo: foi medido, com elevação, numa pasta descartável. O
   `icacls <pasta>\ /save` grava a entrada da própria pasta com o **nome vazio**, e o
   `icacls <pasta>\ /restore` **não aplica** essa entrada — ele monta o caminho `<pasta>\<descritor>`
   e responde "arquivo não encontrado", deixando a lista alterada como estava. O `/save` desfaz os
   filhos de uma pasta; a pasta em si, nunca. E as fases 3 e 4 mexem exatamente nas pastas em si.
3. A **raiz**: negações fora (`/remove:d`, só se houver alguma), `/inheritance:r` e as ACEs padrão
   por SID. O direito de criar arquivo dos Usuários Autenticados sai numa chamada separada — dentro
   de um mesmo `/grant` o `icacls` guarda só a última entrada de cada SID.
4. As **pastas do sistema**, uma a uma: `Windows`, `Program Files`, `Program Files (x86)`,
   `ProgramData`, `Users` e `Users\Public`. Para cada uma, `/setowner` (só se o dono estiver fora do
   padrão) e `/inheritance:r /grant:r` com as ACEs medidas — na pasta, sem `/T` e sem `/reset`. E só
   nas pastas que a **verificação acusou**: pasta no padrão não é tocada. `Windows` e
   `Program Files` pertencem ao TrustedInstaller e dão só `M` ao administrador, que não inclui o
   direito de reescrever a lista: quando a concessão responde "acesso negado", a posse vai para os
   Administradores, a concessão é repetida uma vez e a posse **volta** ao dono padrão.
5. A **sua pasta de usuário**: dono, negações, as três ACEs padrão na raiz do perfil e, depois
   delas, a herança religada **pasta a pasta** — um `icacls <pasta> /inheritance:e` por entrada da
   lista que a fase 2 guardou, em ordem que entrega pai antes de filho. A ordem é dependência: a
   herança só propaga o que já está concedido na raiz. O `/T` saiu daqui pelo mesmo motivo que saiu
   da fase 2, e com ele saiu um defeito da 1.7.0 — descendo a árvore, o `icacls` ligava a herança
   **fora** do perfil, no destino de cada junção de compatibilidade e no armazenamento em nuvem
   redirecionado. `/reset /T` continua de fora: ele apagaria as ACEs explícitas que os próprios
   aplicativos põem dentro do perfil (`AppData\Local\Packages`, OneDrive), e `/inheritance:e` as
   preserva.
6. `takeown` na raiz, **sem recursão**, e só quando a fase 3 responder "acesso negado", seguido de
   uma segunda e última tentativa da fase 3.

O `secedit` com o `defltbase.inf` **saiu** desta lista. No Windows 10 e no 11 as seções
`[Registry Keys]` e `[File Security]` desse arquivo vêm vazias, então `/areas FILESTORE REGKEYS` não
repõe DACL nenhuma: ele levava minutos e não consertava nada. Quem faz esse trabalho é a fase 4,
pasta por pasta, com a mesma tabela que a verificação usa.

**O backup é obrigatório; o destino é que é opcional.** A 103,4 KB não há o que economizar, então
não existe caixa para desligá-lo. Existe uma para mandá-lo a outro lugar — **Guardar o backup das
permissões em outro disco**, desmarcada por padrão. Marcada, só o arquivo de conteúdo sai: o índice
fica sempre em `%ProgramData%\WinForge\acl-backup`, porque é ele que o Desfazer lê. O destino é
recusado por padrão e só passa cumprindo sete exigências — caminho absoluto e local (nada de
rede), fora da raiz do volume, NTFS (exFAT e FAT32 não guardam permissão e não reclamam disso),
disco fixo ou removível, nem dentro nem contendo o seu perfil, sem ponto de reanálise no caminho, e
espaço livre com folga. O arquivo é endurecido lá como já era aqui, e o índice guarda o SHA-256
dele, recalculado na hora de desfazer.

O aviso ao lado da caixa diz o que muda ao sair da pasta do WinForge: ali, qualquer conta de
administrador — desta máquina ou de outra onde o disco for ligado — pode ler, alterar ou apagar o
arquivo. O WinForge percebe a alteração e recusa restaurar, mas não recupera arquivo apagado. Em
pen drive ou HD externo, disco desligado na hora de desfazer é o mesmo que não ter backup, e a
recusa diz qual disco ligar.

**Uma restauração de cada vez.** Enquanto existir backup que o Desfazer ainda não usou, uma
restauração nova é recusada, e a recusa manda escolher: desfazer o que está pendente ou apagá-lo
pelo botão de limpar. Na 1.7.0 não era assim, e rodar a restauração duas vezes destruía o backup
bom — o Desfazer lia o conjunto mais novo, que na segunda rodada já era um retrato do disco depois
da primeira. O índice também guarda de qual máquina e de qual perfil ele é, e índice de outra
máquina é recusado: aplicar permissões com SIDs alheios tranca o perfil em vez de destrancá-lo.

**Desfazer (restaurar backup)** — reaplica o conjunto de backup **mais antigo que ainda não foi
usado**, de duas formas conforme o item. A lista de cada **pasta** volta do SDDL guardado no
índice, e logo depois dela vem uma tentativa **separada** de devolver o dono. O **conteúdo** da sua
pasta de usuário volta por `icacls <pasta acima> /restore <arquivo> /C /L`, rodado a partir da
pasta anotada no índice (o `icacls` grava nomes relativos à pasta em que foi invocado, e restaurar
da pasta errada aplicaria a DACL de uma coisa em outra). Sem backup gravado, ele apenas diz isso e
não toca em nada. Também exige elevação, conferida antes de qualquer pasta ser criada.

O `/L` do `/restore` é obrigatório, e pelo mesmo motivo que tirou o `/T` do backup. Sem ele o
`icacls` abre cada item **seguindo** o ponto de reanálise, e o perfil está cheio deles: as junções
de compatibilidade (`Dados de aplicativos`, `Configurações locais`, `Cookies`) carregam uma negação
de travessia para Todos, que é como o Windows impede que sejam percorridas. Restaurar sem `/L`
derramaria essa negação em `AppData\Roaming`, `AppData\Local` e `InetCookies` —
trancando você fora do próprio AppData com o botão que existe para destrancá-lo.

Os limites do desfazer, que estão escritos na descrição dos botões:

- **A posse volta quando dá.** Devolver a posse ao TrustedInstaller exige um privilégio que nem
  todo administrador tem. Quando a lista volta e o dono não, o Desfazer diz em qual pasta — em vez
  de ficar calado ou de deixar a lista de fora por causa disso.
- O backup das pastas **fora do seu perfil** é sem recursão: volta a lista da pasta em si, não a de
  tudo que está dentro dela. Só a pasta de usuário é salva com o conteúdo.
- Dentro do perfil, o que volta são as pastas que tinham a herança bloqueada. Arquivo solto fica de
  fora, e ligar a herança de volta não apaga ACE que um aplicativo tenha posto ali. Pasta de nuvem
  sob demanda fica fora do backup e também fora da fase 5 — as duas pontas combinam.
- Um Desfazer bem-sucedido **marca o conjunto como usado**. Ele continua no disco, e continua
  aparecendo na lista do botão de limpar, mas deixa de ser o que o próximo Desfazer vai ler.

**Limpar backups antigos** — só lê até você confirmar. Lista o que está guardado em
`%ProgramData%\WinForge\acl-backup` com tamanho e data, marca o arquivo que nenhum índice
referencia e apaga apenas os marcados, sob confirmação. Backup que ainda serve para desfazer não é
marcado. Backup que foi para outro disco também entra na lista; se esse disco não estiver ligado na
hora, o botão diz onde o arquivo está e manda apagá-lo à mão, em vez de dizer que apagou. Ao abrir
o WinForge, uma varredura em segundo plano avisa se essa pasta passou de 1 GB — ela só relata, e
não apaga nada.

A pasta de backup passa pela mesma conferência da pasta de downloads de driver — DACL própria sem
herança, nenhum ponto de reanálise na cadeia, dono dentro de SYSTEM/Administradores e ninguém de
fora deles com escrita —, e cada arquivo gravado é endurecido. O Desfazer recusa, sem nem ler,
arquivo que não esteja diretamente nessa pasta ou cujo dono não seja o SYSTEM ou o grupo
Administradores. Sem elevação a pasta nasce com a sua identidade como dona e a restauração inteira
para: sem backup confiável não há desfazer, e restaurar sem desfazer transforma um problema em dois.

Reinicie o computador depois da restauração e depois do Desfazer: serviços e programas já abertos
continuam com as permissões antigas em cache.

### Rede: a escada de seis degraus

O caso real: "mesmo conectado certinho, a rede e a navegação na internet não funcionam". Estar
conectado prova que o rádio associou e autenticou, e driver quebrado não chega até aí. O que sobra,
na ordem em que costuma ser a causa, é endereço, servidor de nomes, rota, proxy ou um filtro de
software preso na pilha de rede. É essa a ordem dos botões, e por isso os que mexem em driver ficam
no fim.

| # | Botão | O que faz |
|---|---|---|
| 1 | Rede — Diagnóstico completo | Só lê, e é por onde se começa. Levanta doze pontos e fecha com uma frase dizendo por onde seguir. |
| 2 | Rede - Redefinir | Devolve a pilha TCP/IP e o Winsock ao padrão (`netsh winsock reset`, `netsh int ip reset`). Fica no grupo **Correções**, ao lado. Reinicie no fim. |
| 3 | Rede — Limpar cache de DNS e pegar endereço novo | Esvazia o cache de nomes, devolve o endereço atual ao roteador, pede outro e limpa o cache NetBIOS. É reversível por natureza: o roteador entrega outro endereço em segundos. |
| 4 | Rede sem fio — Reinstalar o driver que já está instalado | Guarda uma cópia conferida do driver atual, tira o rádio da lista de dispositivos e manda o Windows procurar de novo. Nenhum pacote é apagado, então volta exatamente o mesmo driver. |
| 5 | Rede sem fio — Voltar para o driver que estava antes | Propõe ao Windows o pacote guardado na última cópia de segurança. É a rede de segurança dos outros dois, e foi construído antes deles: sem volta, não se oferece a ida. Fica habilitado só quando existe cópia conferida em disco. |
| 6 | Rede sem fio — Trocar pelo driver básico do Windows | O único que **apaga** pacote de driver. Último recurso, e pode deixar o computador sem Wi-Fi. |

O diagnóstico do botão 1 termina em poucos segundos e não altera nada: rádio sem fio, perfil da
rede ativa, endereço IP (inclusive o `169.254.x.x` que aparece quando o roteador não responde),
rota padrão, servidor de nomes comparado com o `1.1.1.1`, três sondas de saída para a internet,
proxy do usuário e do WinHTTP, filtros de terceiros presos aos adaptadores, catálogo de protocolos
do Winsock, tamanho máximo de pacote, IPv6 e o código de problema do dispositivo. A frase final sai
de uma lista fechada de cinco e diz por onde começar — endereço, servidor de nomes, filtro,
roteador, ou "não encontrei nada errado na rede deste computador".

**Filtro de antivírus, de firewall ou de rede privada é o primeiro suspeito**, não o driver. Quando
o diagnóstico acha um preso a todos os adaptadores físicos, ele nomeia o produto e escreve o
caminho de menu do próprio Windows para você desligá-lo à mão. O WinForge não desliga, não
reconfigura e não desinstala produto de segurança de terceiro. E o texto avisa que, se o filtro é a
causa, trocar o driver do Wi-Fi não conserta nada e ainda arrisca deixar a máquina sem rádio.

Os botões 4, 5 e 6 são cercados. Antes de qualquer remoção, o pacote em uso é exportado para
`%ProgramData%\WinForge\driver-backup` e conferido arquivo por arquivo — código de saída, o `.inf`,
o `.cat` e o total em bytes. Falhou a conferência, a ação para ali e nada é alterado, porque sem
cópia não há caminho de volta. Depois da troca o adaptador é conferido, e desfecho ruim (sumiu da
lista, voltou com código de problema, ou quem assumiu não foi quem devia) devolve o driver guardado
**na hora, sem perguntar**: num notebook sem porta de rede, mandar você clicar noutro botão para
voltar seria mandar clicar sem rede.

O botão 5 **propõe** o pacote guardado, não o impõe: quem decide qual driver assume o dispositivo é
o mecanismo de classificação do Windows, e ele pode escolher outro. Por isso o relatório conta o
que o adaptador virou, em vez de afirmar que a volta aconteceu. Se nem assim o rádio voltar, o
texto final põe na tela o nome do adaptador e o fabricante e manda trazer o driver por cabo ou pen
drive, de outro computador.

Nove bloqueios podem impedir o clique, todos de leitura e todos explicados em português na tela:
sessão remota (o botão derrubaria a sua própria conexão), Windows anterior ao 10 versão 1903 (os
comandos não existem lá), nenhuma outra via de rede na máquina, ausência de driver básico, falha ao
exportar o pacote, notebook na bateria, máquina virtual ou Windows Server, reinício pendente e
espaço em disco. Disparado um bloqueio, não existe "continuar mesmo assim".

Três ressalvas sobre o botão 6:

- Ele **pede uma palavra digitada**, e não um Sim — Sim se clica por reflexo. A confirmação avisa
  para ter um cabo de rede à mão.
- Ele **não aparece** quando o Windows não tem driver básico para aquele rádio, que é o caso comum
  em MediaTek, Realtek recentes e Intel novos. Botão desabilitado convidaria a procurar como
  habilitá-lo, e o que se acha na internet é a opção que força a remoção do pacote em uso —
  justamente o caminho para ficar sem rádio.
- A detecção de acesso remoto enxerga a Área de Trabalho Remota do Windows, e **não** enxerga
  AnyDesk, TeamViewer ou RustDesk, que rodam na sessão de console. Se você está acessando o
  computador de longe por um desses, pare antes dos botões de driver.

## Classificação de risco

Todo tweak e toggle passou por uma auditoria e carrega uma de três classes:

- **Seguro** — reversível, sem custo de segurança ou estabilidade. É o que os presets marcam.
- **Cuidado** — funciona, mas cobra um preço (segurança, compatibilidade ou um recurso que deixa
  de existir). Fica só na categoria **Avançado (CUIDADO)**, com o custo escrito no começo da
  descrição, e **nunca entra em preset**: para aplicar um desses, você precisa marcá-lo à mão.
- **Removido** — o saldo era negativo. A entrada simplesmente não existe no programa.

A tabela completa, com o motivo de cada item de risco, está em
[`docs/auditoria.md`](docs/auditoria.md) — gerada pelo build a partir da mesma fonte que o
programa usa, então documentação e comportamento não têm como divergir.

## Renderização

A interface usa renderização por software por padrão — é mais compatível com drivers antigos,
sessões remotas e overlays de jogos, que costumam quebrar a aceleração WPF. Se preferir a
aceleração por hardware, rode com `-HardwareRender`.

## Compilar

Requer o .NET SDK 8. Na raiz do repositório:

```
build.cmd
```

O script gera o motor em `dist\engine\WinForge.ps1`, roda o SelfTest duas vezes — a segunda com um
servidor simulado, porque a aba Servidor não existe na máquina de quem compila —, compila o
launcher e deixa o executável final em `dist\WinForge.exe`.

Para rodar só a validação do motor já gerado:

```
powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest
```

O SelfTest lê a versão real do Windows. Para conferir o comportamento em outro sistema sem trocar
de máquina, defina antes de rodar:

- `WINFORGE_SIMULATE_BUILD` com o número do build — por exemplo `19045` para o Windows 10 22H2.
- `WINFORGE_SIMULATE_SERVER` com os papéis desejados — por exemplo `iis,ad` para um Windows Server
  com IIS e Active Directory. É o que a segunda rodada do `build.cmd` usa.

### Ferramentas de QA

Para conferir a interface de verdade, o passeio de QA abre o programa, clica em cada aba com o
mouse e salva um PNG de cada tela em `dist\screenshots` (fora do git). Uma rodada por tema:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\UI-Walkthrough.ps1 -Launch -NoElevation -Theme Escuro
powershell -NoProfile -ExecutionPolicy Bypass -File tools\UI-Walkthrough.ps1 -Launch -NoElevation -Theme Claro
```

Com `-NoElevation` o passeio abre o motor direto, como usuário comum, e as imagens vão para
`dist\screenshots\dark` e `dist\screenshots\light`. Sem ele o script se reabre elevado sozinho e
usa o `dist\WinForge.exe`. Em qualquer caso o programa sobe com `-NoRestorePoint` (a caixa do ponto
de restauração é modal e travaria o passeio), e o script se recusa a rodar com CS2 ou CS:GO aberto,
porque o jogo captura o mouse.

Os inventários de texto servem para achar o que traduzir — quem prova que acabou são as travas do
`-SelfTest`:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\List-EnglishStrings.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\List-I18nKeys.ps1 -Orphans
```

`List-EnglishStrings.ps1` varre o motor gerado (`dist\engine\WinForge.ps1`) atrás de texto em
inglês nos atributos do XAML, no miolo dos blocos de texto e nas caixas de diálogo — inclusive nas
chamadas de `MessageBox::Show` que quebram em várias linhas. `List-I18nKeys.ps1` compara os blocos
JSON do arquivo base com o dicionário por chave (`src\Engine\config\wf-i18n-configs.ps1`) e imprime
as entradas que faltam já no formato de colar; com `-Orphans` lista também as chaves do dicionário
que não existem mais na base.

O terceiro é para revisar a descrição dos itens — o texto que decide se alguém marca ou não marca:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\List-Descriptions.ps1
```

`List-Descriptions.ps1` põe chave, título e descrição lado a lado, já com a tradução aplicada e
somando as entradas do próprio WinForge. `-Grupo tweaks|config|apps` corta por origem, `-MenorQue N`
mostra só as mais curtas e `-Csv` sai com tabulação, para colar em planilha. O `-SelfTest` reprova
as formas conhecidas de descrição vazia (frase repetida dentro da mesma descrição ou entre duas,
menos de 40 caracteres, texto que repete o título, duas "Origem:", "CUIDADO:" escrito à mão); o que
ele não consegue julgar é se o texto é bom, e é para isso que serve a lista.

## Estrutura

```
src/Engine/         gerador do motor PowerShell/WPF
  base/             cópia intocada do utilitário de origem
  winforge/         blocos de código do WinForge (funções, assets, launcher)
  config/           tweaks, jogos, presets, curadoria da lista de aplicativos, tema e tradução
  xaml/             trechos de interface (estilos, barra de navegação e abas Jogos, Diagnóstico e Servidor)
  build.ps1         aplica os blocos sobre a base e escreve dist/engine/WinForge.ps1
src/Launcher/       WinForge.exe (C# net48): splash, elevação e hospedagem do motor
src/Launcher.Tests/ testes do launcher
tests/engine/       verificações do motor gerado (marca, mojibake)
tools/              ícone, passeio de QA pela interface e os inventários de texto visível
docs/               changelog e documentação
```

## Roadmap

Concluído: auditoria de risco de todos os tweaks (ver [`docs/auditoria.md`](docs/auditoria.md)), a
detecção de hardware, drivers e papéis de servidor com as recomendações da aba Diagnóstico, a aba
Servidor com os ajustes de Windows Server, IIS e Active Directory, o reparo de componentes do
Windows na aba Configurações, a restauração das permissões padrão do disco do sistema, a detecção
do que já está aplicado na máquina antes de aplicar qualquer coisa, a escada de rede sem fio
(diagnóstico, DNS e a troca de driver), o agrupamento dos arquivos de informação oferecidos pelo
Windows Update e o botão Parar nos comandos que demoram.

## Licença

MIT (veja `LICENSE`). O WinForge é derivado do WinUtil, de Chris Titus Tech, e de outros trabalhos
de terceiros — os créditos e as licenças de origem estão em `NOTICE`.
