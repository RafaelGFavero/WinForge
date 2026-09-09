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
- **Diagnóstico** — o que foi detectado na máquina, as recomendações e os drivers instalados.

A janela se adapta ao sistema: no Windows 10, os itens que só existem no Windows 11 não são
exibidos; os tweaks marcados para uma marca de GPU só aparecem se aquela GPU for detectada.

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
Memória, Placa de vídeo, Armazenamento, Rede, Energia, e Segurança e estado —, a lista das
recomendações com seus motivos e a tabela dos drivers instalados. Os botões:

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

O script gera o motor em `dist\engine\WinForge.ps1`, roda o SelfTest, compila o launcher e deixa
o executável final em `dist\WinForge.exe`.

Para rodar só a validação do motor já gerado:

```
powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest
```

O SelfTest lê a versão real do Windows. Para conferir o comportamento em outra versão sem
trocar de máquina, defina `WINFORGE_SIMULATE_BUILD` com o número do build antes de rodar — por
exemplo `WINFORGE_SIMULATE_BUILD=19045` para simular o Windows 10 22H2.

## Estrutura

```
src/Engine/         gerador do motor PowerShell/WPF
  base/             cópia intocada do utilitário de origem
  winforge/         blocos de código do WinForge (funções, assets, launcher)
  config/           tweaks, jogos e presets do WinForge
  xaml/             trechos de interface (aba Jogos e sua navegação)
  build.ps1         aplica os blocos sobre a base e escreve dist/engine/WinForge.ps1
src/Launcher/       WinForge.exe (C# net48): splash, elevação e hospedagem do motor
src/Launcher.Tests/ testes do launcher
tests/engine/       verificações do motor gerado (marca, mojibake)
tools/              utilitários de build (geração do ícone)
docs/               changelog e documentação
```

## Roadmap

Concluído: auditoria de risco de todos os tweaks (ver [`docs/auditoria.md`](docs/auditoria.md)) e a
detecção de hardware, drivers e papéis de servidor, com as recomendações da aba Diagnóstico.

- Auditoria de tweaks: relatório do que já está aplicado no sistema antes de mexer em nada.
- Tweaks próprios de Windows Server, IIS e Active Directory — hoje os papéis são detectados e
  entram nas recomendações, mas não há ajustes específicos para eles.
- Reparo de componentes do Windows (DISM/SFC e correção de repositório).

## Licença

MIT (veja `LICENSE`). O WinForge é derivado do WinUtil, de Chris Titus Tech, e de outros trabalhos
de terceiros — os créditos e as licenças de origem estão em `NOTICE`.
