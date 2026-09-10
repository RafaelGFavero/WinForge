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

1. Execute o `WinForge.exe`. Ele pede elevação de administrador (os tweaks não funcionam sem ela).
2. Responda à pergunta de ponto de restauração que aparece ao abrir: crie o ponto se quiser poder
   voltar atrás pelo próprio Windows, ou pule se preferir usar só o Desfazer da ferramenta.
3. Marque o que quer aplicar e clique em aplicar. Cada tweak tem seu Desfazer.

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

## O que tem

- **Install** — instalação de programas em lote via gerenciador de pacotes.
- **Tweaks** — desempenho, privacidade, energia, serviços, anúncios, Cortana, pesquisa, VBS,
  limpeza de disco, backup do registro, cache de RAM e otimização de unidades.
- **Jogos** — prioridade de CPU por jogo (IFEO), GameDVR, MMCSS, HAGS e ajustes de shader cache
  para NVIDIA, AMD e Intel.
- **Config** — recursos do Windows, correções de sistema e atalhos de manutenção.
- **Updates** — política de atualizações do Windows (padrão, adiada ou desligada).
- **Win11 Creator** — criação de mídia de instalação do Windows 11.
- **AppX** — remoção de aplicativos pré-instalados.
- **Servidor** — só no Windows Server: ajustes gerais do servidor, IIS e Active Directory.
- **Diagnóstico** — o que foi detectado na máquina, as recomendações e os drivers instalados.

A janela se adapta ao sistema: no Windows 10, os itens que só existem no Windows 11 não são
exibidos; os tweaks marcados para uma marca de GPU só aparecem se aquela GPU for detectada; e no
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
sozinha: quem marca é você, por um dos botões — **Marcar recomendados**, nas abas Tweaks e Jogos,
marca o que é daquela aba; **Marcar todos os recomendados**, na aba Diagnóstico, marca as duas de
uma vez. Nos três casos dá para desmarcar item por item antes de aplicar. Os toggles ficam de fora:
eles aplicam o tweak no instante em que são ligados, e recomendação não muda o sistema.

A aba **Diagnóstico** (`Alt+D`) reúne isso em nove cartões — Sistema, Máquina, Processador,
Memória, Placa de vídeo, Armazenamento, Rede, Energia, e Segurança e estado —, mais um décimo,
Servidor, no Windows Server, a lista das recomendações com seus motivos e a tabela dos drivers
instalados. Os botões:

| Botão | O que faz |
|---|---|
| Atualizar diagnóstico | Coleta o perfil de novo e reavalia as recomendações. |
| Buscar drivers no Windows Update | Pergunta ao Windows Update quais drivers ele tem para este computador (pode levar até um minuto). |
| Exportar relatório HTML | Gera um relatório HTML com tudo desta aba e abre no navegador. |
| Marcar todos os recomendados | Marca nas abas Tweaks e Jogos os itens recomendados para este PC. |

Para placas NVIDIA, a versão instalada é comparada com a mais recente do catálogo do fabricante
(consulta ao site da NVIDIA, guardada por 24 horas em `%LocalAppData%\WinForge\cache`); para AMD e
Intel, a tabela leva à página de download da marca.

**O WinForge não baixa nem instala driver nenhum.** Tudo o que a aba faz é olhar e comparar: a
lista do Windows Update é informativa, os links abrem no seu navegador, e a decisão de instalar
qualquer coisa continua sendo sua.

O relatório HTML descreve a máquina inteira: nome do computador, fabricante e modelo, modelos dos
discos, servidores DNS e o estado de BitLocker, Secure Boot e TPM. O arquivo fica em
`%LocalAppData%\WinForge\reports` e não sai da máquina sozinho — só vale saber o que vai junto
antes de mandá-lo para outra pessoa.

Cada etapa do diagnóstico vai para o log da sessão, em `%LocalAppData%\WinForge\logs`. Ao abrir, o
WinForge mantém ali as 30 sessões mais recentes e apaga as anteriores.

## Windows Server

Se o Windows for Server, a janela muda de forma sozinha: aparece a aba **Servidor** (`Alt+S`) e
somem as abas que não fazem sentido ali — Jogos, AppX e Win11 Creator. A detecção acontece antes
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
continuam sendo itens da aba **Tweaks** recomendados pelo Diagnóstico, não itens da aba Servidor —
quem trabalhar só nesta aba não os verá.

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

## Estrutura

```
src/Engine/         gerador do motor PowerShell/WPF
  base/             cópia intocada do utilitário de origem
  winforge/         blocos de código do WinForge (funções, assets, launcher)
  config/           tweaks, jogos e presets do WinForge
  xaml/             trechos de interface (abas Jogos, Diagnóstico e Servidor, com sua navegação)
  build.ps1         aplica os blocos sobre a base e escreve dist/engine/WinForge.ps1
src/Launcher/       WinForge.exe (C# net48): splash, elevação e hospedagem do motor
src/Launcher.Tests/ testes do launcher
tests/engine/       verificações do motor gerado (marca, mojibake)
tools/              utilitários de build (geração do ícone)
docs/               changelog e documentação
```

## Roadmap

Concluído: auditoria de risco de todos os tweaks (ver [`docs/auditoria.md`](docs/auditoria.md)), a
detecção de hardware, drivers e papéis de servidor com as recomendações da aba Diagnóstico, e a aba
Servidor com os ajustes de Windows Server, IIS e Active Directory.

- Auditoria de tweaks: relatório do que já está aplicado no sistema antes de mexer em nada.
- Reparo de componentes do Windows (DISM/SFC e correção de repositório).

## Licença

MIT (veja `LICENSE`). O WinForge é derivado do WinUtil, de Chris Titus Tech, e de outros trabalhos
de terceiros — os créditos e as licenças de origem estão em `NOTICE`.
