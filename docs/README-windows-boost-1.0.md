# Windows Boost 1.0.0

Ferramenta de otimização para **Windows 10 e 11**, construída sobre o
[WinUtil](https://github.com/ChrisTitusTech/winutil) 26.08.19 de Chris Titus Tech (licença MIT)
e com as otimizações do repositório *Windows Boost - Essential* reescritas como tweaks
reversíveis (cada item tem "Desfazer" e detecção de "já aplicado").

## Como usar

1. Dê dois cliques em `Windows Boost.bat` (ou rode `WindowsBoost.ps1`). A ferramenta pede
   elevação de administrador sozinha.
2. Ao abrir, ela pergunta se você quer **criar um Ponto de Restauração**. Responda Sim ou Não.
   - `Windows Boost.bat -RestorePoint` cria sem perguntar.
   - `Windows Boost.bat -NoRestorePoint` não pergunta nem cria.
3. Marque o que quiser e clique em **Run Tweaks** (aba Tweaks) ou **Aplicar selecionados** (aba Jogos).
   Para reverter, marque os itens e use **Undo Selected Tweaks** / **Desfazer selecionados**.

Passe o mouse sobre qualquer item para ver a descrição, o que ele altera e de qual script do
Windows Boost - Essential ele veio.

## O que tem em cada aba

| Aba | Conteúdo |
|-----|----------|
| Install | Instalação de programas via winget/choco (WinUtil). |
| Tweaks | Tweaks do WinUtil + categorias **Windows Boost - Desempenho**, **Privacidade e Interface**, **Avançado (CUIDADO)** e toggles **Windows Boost - Preferências** (transparência, HAGS). Botão de preset **Windows Boost**. |
| Jogos | Esquerda: **prioridade de CPU por jogo** (67 jogos, IFEO). Direita: **Otimizações para jogos** (Game DVR, MMCSS, prioridade de primeiro plano, serviços Xbox, timer bcdedit) e **GPU NVIDIA / AMD / Intel** (só aparece a GPU detectada). Botão de preset **Gamer**. Atalho Alt+J. |
| Config | Recursos e correções do WinUtil + **Windows Boost - Manutenção** (ponto de restauração, backup do registro, limpar cache de RAM, limpeza completa, otimizar unidades, shader cache) e **Ferramentas externas** (ISLC, MSI Utility, DNS Jumper, Firemin). |
| Updates | Perfis de Windows Update (WinUtil). |
| Win11 Creator | Cria ISO/USB do Windows 11 sem exigência de TPM (WinUtil). |
| AppX | Remoção de apps da Microsoft. Botão **Windows Boost** = seleção equivalente ao "REMOVA TUDO DE UMA VEZ SÓ" (sem a Microsoft Store). |

## Windows 10 x Windows 11

A ferramenta detecta a versão e **oculta** o que não se aplica:

- No Windows 10 somem: Widgets, layout antigo do menu Iniciar, menu de contexto clássico,
  Início/Galeria do Explorador, "Finalizar tarefa" na barra, ícones centralizados,
  recomendações do menu Iniciar, página inicial de Configurações e os AppX Clipchamp,
  Dev Home, Mobile Devices, Start Experiences e Teams.
- Sem GPU AMD somem os itens AMD; sem NVIDIA somem os itens NVIDIA; idem Intel.
- Presets e arquivos importados também respeitam o filtro (um preset com item só do Windows 11
  não o aplica no Windows 10).

## Ferramentas externas

Coloque os executáveis na pasta `Apps\` ao lado do `WindowsBoost.ps1`
(`ISLC*.exe`, `MSI_util*.exe`, `DnsJumper*.exe`, `Firemin*.exe`). Os botões em
Config > Ferramentas externas abrem o programa; se ele não estiver na pasta, abrem a página oficial.
O `EmptyStandbyList.exe` não é mais necessário: "Limpar cache de RAM" faz a mesma coisa nativamente.

## Logs e backups

- Logs: `%LocalAppData%\WindowsBoost\logs\`
- Backups do registro: `%LocalAppData%\WindowsBoost\Backup_Regedit\<data>\`

## Itens do repositório original que NÃO foram incluídos (de propósito)

- *Desativar Serviço de Relógio do Windows* e desativar `wuauserv`/`W32Time` no script de serviços:
  quebram sincronização de hora, TLS e Windows Update. Use a aba **Updates** para controlar atualizações.
- *Habilitar a otimização do sistema de arquivos.reg* (`EnableOplocks=1`): já é o padrão do Windows.
- *Desativar efeitos visuais / animações*: já coberto por "Visual Effects - Set to Best Performance".
- *Desativar telemetria, hibernação, histórico de atividade, Bing Search*: já existem no WinUtil.
- Limiares de ocioso da CPU do *Ajustes de energia.reg*: com valor 100 eles pioram a latência;
  ficou só a parte útil (USB, throttle, estado mínimo do processador).
- Remover a **Microsoft Store** na seleção de AppX.

## Para alterar a ferramenta

A pasta `src\` tem as peças e o script de build:

- `winutil-26.08.19.ps1` - WinUtil original, sem alterações
- `wb-functions.ps1` - funções novas (detecção de sistema, ponto de restauração, manutenção, etc.)
- `wb-config.ps1` - tweaks, botões, presets e lista de jogos do Windows Boost (JSON)
- `wb-xaml-nav.xml` / `wb-xaml-tab.xml` - botão de navegação e aba Jogos
- `build.ps1` - injeta tudo no WinUtil e gera `WindowsBoost.ps1` (falha se alguma âncora sumir)

Depois de editar, rode `powershell -ExecutionPolicy Bypass -File src\build.ps1` e depois
`WindowsBoost.ps1 -SelfTest` para validar configurações, XAML e montagem das abas sem abrir a janela.
Para simular Windows 10 no SelfTest: `set WINBOOST_SIMULATE_BUILD=19045` antes de rodar.
