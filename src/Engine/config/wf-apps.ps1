#region ===== WinForge - curadoria da lista de aplicativos =====

# A base traz 232 aplicativos na aba Instalar. Boa parte é alternativa de nicho, ferramenta de
# desenvolvimento ou serviço auto-hospedado que não serve ao público do WinForge - e uma lista
# longa demais atrapalha justamente quem só quer instalar o básico.
#
# Estas três tabelas são consumidas por Initialize-WinUtilBoostConfigs, que roda ANTES de o motor
# derivar $sync.configs.applicationsHashtable e montar a aba: depois disso a chave removida já
# teria virado controle na tela.

# Chaves de $sync.configs.applications que não entram no WinForge.
$sync.WinForgeRemovedApps = @(
    # Navegadores: sobram os de uso corrente; forks e derivados saem.
    'WPFInstallchromium', 'WPFInstallfirefoxesr', 'WPFInstallfloorp', 'WPFInstallhelium', 'WPFInstallmullvadbrowser', 'WPFInstallungoogled', 'WPFInstallwaterfox',
    # Comunicação: clientes alternativos e redes de nicho.
    'WPFInstallbetterbird', 'WPFInstallchatterino', 'WPFInstalldorion', 'WPFInstallmatrix', 'WPFInstallprotonmail', 'WPFInstallqtox', 'WPFInstallteamspeak3', 'WPFInstallvesktop', 'WPFInstallviber',
    # Desenvolvimento: runtimes, gerenciadores de pacote e IDEs que quem programa instala do próprio jeito.
    'WPFInstalljava25', 'WPFInstalljava8', 'WPFInstallbruno', 'WPFInstallclaude-code', 'WPFInstallcmake', 'WPFInstallcodex', 'WPFInstallfnm', 'WPFInstallgitextensions', 'WPFInstallgithubcli', 'WPFInstalllazygit', 'WPFInstallLua', 'WPFInstallneovim', 'WPFInstallnodejs', 'WPFInstallposh', 'WPFInstallpnpm', 'WPFInstallRuby', 'WPFInstallstarship', 'WPFInstallsysteminformer', 'WPFInstallunity', 'WPFInstalluv', 'WPFInstallvagrant', 'WPFInstallvisualstudio2026', 'WPFInstallvscodium', 'WPFInstallyarn', 'WPFInstallZed',
    # Documentos: leitores e blocos de notas alternativos.
    'WPFInstalljoplin', 'WPFInstallokular', 'WPFInstallpdfgear', 'WPFInstallpdfsam', 'WPFInstallpdf-xchange', 'WPFInstallqownnotes', 'WPFInstallsimplenote', 'WPFInstallxournal', 'WPFInstallzotero',
    # Jogos: emuladores e lojas de nicho.
    'WPFInstallcemu', 'WPFInstalles-de', 'WPFInstallheroiclauncher', 'WPFInstallitch', 'WPFInstallmodrinth', 'WPFInstallOverwolf', 'WPFInstallroblox', 'WPFInstallvrdesktopstreamer',
    # Ferramentas Microsoft: SDK e ferramentas de imagem/administração remota.
    'WPFInstalldotnet9', 'WPFInstalldismtools', 'WPFInstallntlite', 'WPFInstallnuget', 'WPFInstallrdcman',
    # Multimídia: players e visualizadores alternativos.
    'WPFInstallfoobar', 'WPFInstallmpc-qt', 'WPFInstallnomacs',
    # Ferramentas profissionais: rede e VPN de uso especializado.
    'WPFInstallangryipscanner', 'WPFInstallgsudo', 'WPFInstallmullvadvpn', 'WPFInstallnmap', 'WPFInstallsimplewall',
    # Auto-hospedados: servidores e clientes de serviço próprio.
    'WPFInstalljellyfinmediaplayer', 'WPFInstalljellyfinserver', 'WPFInstallnetbird', 'WPFInstallnextclouddesktop', 'WPFInstallplex', 'WPFInstallsunshine',
    # Utilitários: automação, shells e acessórios de nicho.
    'WPFInstallblurautoclicker', 'WPFInstalldeskflow', 'WPFInstallenteauth', 'WPFInstallfiles', 'WPFInstallglazewm', 'WPFInstallhugo', 'WPFInstallxeheditor', 'WPFInstalljpegview', 'WPFInstallmsedgeredirect', 'WPFInstallnilesoftShell', 'WPFInstallOFGB', 'WPFInstallOPAutoClicker', 'WPFInstallpolicyplus', 'WPFInstallprotonauth', 'WPFInstallprotondrive', 'WPFInstallprotonpass', 'WPFInstallsignalrgb', 'WPFInstallWiseProgramUninstaller'
)

# Categoria da base (inglês) -> título do grupo na tela (pt-BR). O grupo "Selfhosted Tools" some:
# o pouco que sobra dele é utilitário comum, e um grupo de dois itens só ocupa espaço.
$sync.WinForgeAppCategoryMap = @{
    'Browsers'         = 'Navegadores'
    'Communications'   = 'Comunicação'
    'Development'      = 'Desenvolvimento'
    'Document'         = 'Documentos'
    'Games'            = 'Jogos'
    'Microsoft Tools'  = 'Ferramentas Microsoft'
    'Multimedia Tools' = 'Multimídia'
    'Pro Tools'        = 'Ferramentas profissionais'
    'Utilities'        = 'Utilitários'
    'Selfhosted Tools' = 'Utilitários'
}

# Exceções por aplicativo, aplicadas depois do mapa: são players de mídia que a base catalogou em
# "Selfhosted Tools" e que, sem isto, cairiam em Utilitários junto com o resto do grupo.
$sync.WinForgeAppCategoryOverride = @{
    'WPFInstallplexdesktop' = 'Multimídia'
    'WPFInstallkodi'        = 'Multimídia'
}

#endregion
