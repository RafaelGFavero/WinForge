# WinForge — Interface em pt-BR, reordenação, Diagnóstico e visual (Plano 6)

Data: 2026-09-10. Complementa `2026-09-07-winforge-design.md`. Versão alvo: 1.5.0.

## 1. Objetivo

Deixar o WinForge inteiro em português do Brasil, abrir no Diagnóstico com as abas na ordem de uso, corrigir os defeitos vistos na aba Diagnóstico (rolagem sobre a tabela de drivers, ausência de botão para atualizar driver, "Marcar recomendados" sem efeito visível), enxugar a aba Install e aplicar um visual único e consistente (tokens de tema, tipografia, espaçamento) em todas as abas.

## 2. Fora de escopo

- Traduzir nomes de aplicativos, de jogos, de chaves de registro, GUIDs e nomes de serviços.
- Mudar o comportamento de qualquer tweak.
- Tema claro novo além dos tokens equivalentes (o base já alterna Claro/Escuro/Auto).

## 3. Tradução (pt-BR completo)

Mecanismo híbrido, no build (`src/Engine/build.ps1`), base intocada:

- **Por chave (JSON)**: `src/Engine/config/wf-i18n-configs.ps1` guarda `$sync.WinForgeI18n = @{ '<chave>' = @{ Content = '...'; Description = '...' } }` para todos os tweaks, toggles, features (aba Config), perfis de Updates e apps da base que sobrevivem ao corte (§5). `Initialize-WinForgeBoostConfigs` aplica o dicionário depois de mesclar as configs. Chave sem tradução no dicionário = erro de SelfTest (trava de cobertura: toda entrada visível da base tem linha, exceto nomes de app, que ficam).
- **Por texto (XAML, funções, mensagens)**: `src/Engine/config/wf-i18n-strings.ps1` guarda pares `@('texto original', 'tradução')` aplicados com `Replace-Once` (falha no build se o original sumir ou duplicar). Cobre rótulos do XAML (`Content=`, `Text=`, `Header=`, `ToolTip=`), `MessageBox`, `Write-Host` visíveis, textos das abas Updates e Win11 Creator, painéis legados, nomes de categorias (`Essential Tweaks` → `Ajustes essenciais`, `Customize Preferences` → `Preferências`, `Legacy Windows Panels` → `Painéis clássicos do Windows`, `Fixes` → `Correções`, `Features` → `Recursos do Windows`, `z__Advanced Tweaks - CAUTION` → `zz__Avançado (CUIDADO)`, `Performance Plans - NOT FOR LAPTOPS` → `Planos de energia (não para notebooks)`, `Powershell Profile Powershell 7+ Only` removido junto com os botões CTT).
- **Categorias de apps**: Browsers → Navegadores; Communications → Comunicação; Development → Desenvolvimento; Document → Documentos; Games → Jogos; Microsoft Tools → Ferramentas Microsoft; Multimedia Tools → Multimídia; Pro Tools → Ferramentas profissionais; Utilities → Utilitários; Selfhosted Tools some (itens mantidos migram, §5).
- **Trava de idioma no SelfTest**: lista fechada de ~60 termos ingleses (`Recommended Selections`, `Run Tweaks`, `Undo Selected`, `Install/Upgrade`, `Clear Selection`, `Collapse All`, `- Disable`, `- Enable`, `- Remove`, `Restore Defaults`, `Apply Recommended`, `Status Log`, `Browse`, `Legacy`, `Features`, `Fixes`, ...) que não podem aparecer no XAML nem em `Content/Description` do motor gerado. Termos que são nomes próprios (`Game Mode` vira `Modo Jogo`; `Windows Update` fica) estão fora da lista.
- Título da janela: `WinForge <versão> - <SO> <edição>` (já em pt-BR). Menus: Sobre, Créditos, Documentação (já).

## 4. Abas e abertura

- Ordem da barra: **Diagnóstico, Tweaks, Jogos, Config, Updates, Install, Win11 Creator**; em servidor, **Servidor** entra depois de Config e Jogos/Install/Win11 somem (regra atual). Só a ordem dos `ToggleButton` muda (bloco de navegação substituído no build); `TabItem`, nomes `WPFTab<n>` e atalhos Alt continuam.
- Rótulos: Diagnóstico, Ajustes (Tweaks), Jogos, Config → **Configurações**, Updates → **Atualizações**, Install → **Instalar**, Win11 Creator → **ISO Win11**, Servidor. Sublinhado do atalho na letra correspondente (I, T, C, U, W, J, D, S — mantidos).
- Abertura: `$sync.currentTab = "Diagnostico"` e `Invoke-WPFTab "WPFTab8BT"` na inicialização; a barra de busca fica oculta no Diagnóstico como hoje.

## 5. Aba Instalar

- Categorias **fechadas** ao abrir (chama a mesma função do botão "Recolher todas" após montar a aba; o botão continua).
- Remoção de 96 apps de nicho/duplicados, lista em `src/Engine/config/wf-apps.ps1` (`$sync.WinForgeRemovedApps`), aplicada em `Initialize-WinForgeBoostConfigs` antes de montar a UI; trava de contagem no SelfTest (139 apps). Lista:
  - Navegadores (7): Chromium, Firefox ESR, Floorp, Helium, Mullvad Browser, Ungoogled Chromium, Waterfox.
  - Comunicação (9): Betterbird, Chatterino, Dorion, Element, Proton Mail, QTox, TeamSpeak 3, Vesktop, Viber.
  - Desenvolvimento (25): Amazon Corretto 25, Amazon Corretto 8, Bruno, Claude Code, CMake, Codex, Fast Node Manager, Git Extensions, GitHub CLI, Lazygit, Lua, Neovim, NodeJS (não-LTS), Oh My Posh, pnpm, Ruby, Starship, System Informer, Unity, uv, Vagrant, Visual Studio 2026, VS Codium, Yarn, Zed.
  - Documentos (9): Joplin, Okular, PDFgear, PDFsam Basic, PDF-XChange Editor, QOwnNotes, Simplenote, Xournal++, Zotero.
  - Jogos (8): Cemu, EmulationStation DE, Heroic, Itch.io, Modrinth, Overwolf, Roblox, Virtual Desktop Streamer.
  - Ferramentas Microsoft (5): .NET Desktop Runtime 9, DISMTools, NTLite, NuGet, RDCMan.
  - Multimídia (3): foobar2000, mpc-qt, nomacs.
  - Ferramentas profissionais (5): Angry IP Scanner, gsudo, Mullvad VPN, Nmap, Simplewall.
  - Selfhosted (6): Jellyfin Media Player, Jellyfin Server, NetBird, Nextcloud Desktop, Plex Media Server, Sunshine. Mantidos e migrados: LocalSend e Moonlight → Utilitários; Plex Desktop e Kodi → Multimídia.
  - Utilitários (18): BlurAutoClicker, Deskflow, Ente Auth, Files, GlazeWM, Hugo, HxD, JPEG View, MSEdgeRedirect, Nilesoft Shell, OFGB, OPAutoClicker, Policy Plus, Proton Authenticator, Proton Drive, Proton Pass, SignalRGB, Wise Program Uninstaller.
- Descrições dos 139 apps mantidos traduzidas (dicionário por chave, §3).

## 6. Aba Diagnóstico

- **Rolagem**: `PreviewMouseWheel` nas duas `DataGrid` (drivers e Windows Update) marca o evento como tratado e repassa um `MouseWheelEventArgs` ao `ScrollViewer` da aba; a página rola com o cursor sobre a tabela.
- **Recomendações com caixas**: a lista "Recomendações para este computador" vira `ItemsControl` de linhas `CheckBox` (chave, título traduzido, motivo em cinza). Marcar/desmarcar uma linha monta a aba de destino se preciso e marca/desmarca o controle real (`$sync[<chave>].IsChecked`); o `Checked/Unchecked` do controle real atualiza a linha (espelho, sem laço: guarda `$sync.WinForgeMirrorBusy`). Botões "Marcar todos" e "Desmarcar todos"; contador na própria aba ("16 de 16 recomendados marcados"). Sem `MessageBox`. Os botões "Marcar recomendados" das abas Ajustes/Jogos/Servidor continuam.
- **Ação por driver**: coluna "Ação" na tabela de drivers com um botão por linha:
  - NVIDIA com situação `atualizar`: **"Baixar <versão>"** — baixa o instalador oficial (URL `DownloadURL` da resposta da API já consultada) para `%ProgramData%\WinForge\downloads` (pasta criada e verificada com os mesmos helpers de DACL/dono/junção dos backups), confere assinatura Authenticode válida com `O=NVIDIA Corporation` (RDN exato), e só então abre o instalador para o usuário conduzir; falha de assinatura apaga o arquivo. Progresso na barra de status; confirmação antes de baixar (tamanho estimado).
  - Demais fornecedores: **"Página do fabricante"** (o link atual vira botão).
  - Windows Update (segunda tabela): coluna **"Instalar"** por linha — confirmação, depois `IUpdateDownloader` + `IUpdateInstaller` (COM) no runspace, progresso na barra, resultado (código, reinício necessário) na barra e no log. Um por vez (`$sync.CommandRunning`).
- Botão "Buscar drivers no Windows Update" sem corte (largura automática).

## 7. Visual (ui-ux-pro-max: Minimalism & Swiss, densidade 7, movimento 2)

- **Tokens (tema Escuro)**: fundo `#0B1220`, cartão/painel `#111A2E`, botão `#1B2A44`, botão hover `#25385C`, botão selecionado `#3B82F6` (texto `#FFFFFF`), borda `#263244`, texto `#E6EDF5`, texto secundário `#94A3B8`, títulos/links `#7DD3FC`, progresso `#22C55E`, recomendado `#22C55E`, evitar `#F59E0B`, perigo `#EF4444`. **Tema Claro**: fundo `#F8FAFC`, cartão `#FFFFFF`, botão `#E8ECF1`, hover `#D7DEE8`, selecionado `#0369A1`, borda `#CBD5E1`, texto `#0F172A`, secundário `#475569`, títulos `#0369A1`. Todos os pares texto/fundo ≥ 4,5:1.
- **Tipografia**: `Segoe UI` 13 px corpo; títulos de categoria `Segoe UI Semibold` 15 px (sai `Consolas`); cabeçalhos de cartão 14 px semibold.
- **Componentes**: botões 32 px de altura, raio 4, largura automática com padding 14 px (mínimo 120); abas com largura igual (118 px), raio 4, selecionada com fundo `#3B82F6`; caixas de seleção 16 px com 6 px entre linhas; cartões do Diagnóstico com padding 12, raio 6, borda 1 px; tabela com linhas de 26 px e cabeçalho semibold; barra de status com fundo do cartão.
- **Estados**: hover 200 ms (transição de fundo), foco visível (borda `#7DD3FC` 1 px), botão desabilitado 50 % de opacidade.
- Aplicado por troca dos valores do bloco de temas (`$sync.configs.themes`, `Replace-Once` por token) e por estilos no XAML (`Style` dos `Button`/`ToggleButton`/`CheckBox`) via `Replace-Between` no `Window.Resources`.

## 8. Varredura e QA visual

- `tools/UI-Walkthrough.ps1`: sobe o programa (ou usa o aberto), percorre cada aba com clique real de mouse, rola o Diagnóstico e salva capturas em `dist/screenshots/`. Roda elevado; não faz parte do CI.
- Cada tarefa do plano termina com capturas das abas que tocou; a última tarefa faz a varredura completa e corrige o que sobrar (texto em inglês, corte, alinhamento, botão sem largura, fonte fora do padrão).

## 9. Testes

- SelfTest: trava de idioma (§3), cobertura do dicionário (toda chave visível tem tradução), contagem de apps 139 e ausência dos 96 removidos, ordem da barra de abas (`WPFTabNav`/nomes dos botões na ordem esperada), `currentTab` inicial Diagnostico, categorias do Install recolhidas após montar, lista de recomendações com N caixas = N recomendados e espelho funcionando (marcar a caixa marca o controle e vice-versa, sem laço), coluna Ação presente com o botão certo por fornecedor, `Install-WinForgeNvidiaDriver -DryRun` (URL + destino, sem download), `Install-WinForgeWindowsUpdateDriver -DryRun`, tokens dos dois temas com contraste ≥ 4,5:1 (cálculo no SelfTest), nenhum `Consolas` no XAML gerado.
- Nada do SelfTest baixa, instala ou muda a máquina (`$sync.SelfTest` + `-DryRun`).

## 10. Riscos

- Volume do dicionário (≈ 400 entradas): tarefa própria, gerado com apoio de script que lista as chaves e falha de build para chave sem tradução.
- Texto traduzido mais longo que o inglês: larguras automáticas e `TextWrapping` nas descrições; a varredura final pega cortes.
- Download da NVIDIA: mesmo padrão de segurança dos backups (pasta protegida, assinatura RDN exata, nada silencioso).
