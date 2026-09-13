#region ===== WinForge - reparo de componentes =====
# Os botões do grupo "WinForge - Reparo de componentes" da aba Config. Cada botão cai em
# Invoke-WinForgeRepairCommand -Name <nome curto>: o nome curto é a única coisa que a interface
# conhece, o QUE roda mora na tabela de Get-WinForgeRepairCommand e o COMO roda mora na máquina
# genérica de comandos (wf-commands.ps1) - núcleo síncrono Invoke-WinForgeCommandCore, despacho em
# runspace Invoke-WinForgeCommandButton e a janela de saída montada em código.
#
# A diferença para a aba Servidor é o 'Kind' de cada linha:
#   read    - só lê o estado da máquina; pode ser clicado a qualquer hora, inclusive em produção.
#   repair  - mexe no sistema (repositório WMI, registro de aplicativos, agendamento de disco).
#   install - baixa e instala componente (DISM, winget, instalador da Microsoft).
#
# 'read' vai direto para o despacho. 'repair' e 'install' passam antes por uma caixa de Sim/Não que
# repete o título e a descrição do botão (Get-WinForgeRepairConfirmText) e tem o "Não" como padrão:
# um Enter distraído não repara nada. A pergunta acontece na thread da janela e a trava de comando em
# andamento é CONFERIDA antes dela, mas só TOMADA depois - perguntar com a trava na mão deixaria o
# programa sem botões enquanto a caixa espera resposta, e perguntar sem conferir faria o usuário ler
# o aviso inteiro para receber "já existe um comando em andamento" depois do "Sim".
#
# Nenhum comando desta tabela é montado com texto vindo de fora do programa. O que chama executável
# usa Invoke-WinForgeNativeCommand -FilePath/-Arguments, que entrega cada argumento inteiro, sem
# interpretador no meio.
# ---------------------------------------------------------------------------

function Get-WinForgeRepairCommand {
    <#
    .SYNOPSIS
        Tabela do reparo de componentes: título, texto do comando, ferramenta exigida e tipo de ação.
    .DESCRIPTION
        Dado puro, separado da execução: o -SelfTest passa por todas as linhas (título, comando que
        compila, tipo válido) e simula cada uma em qualquer máquina, sem reparar nem instalar nada.

        'Requires' é o nome de um executável ou de um cmdlet resolvido com Get-Command. Ausente, o
        comando não roda: vira uma frase dizendo qual ferramenta falta.

        'Native' é sempre $false aqui: toda linha chama uma função do próprio WinForge, e é ela que
        chama o executável (com -FilePath/-Arguments) quando existe executável. Marcar 'Native' faria
        o núcleo trocar a code page para um pipeline de cmdlet e inventar um "Código de saída: 0".

        'Kind' e 'Confirm' são lidos por Invoke-WinForgeRepairCommand, não pelo núcleo genérico.
        'Confirm' é a RESERVA do texto da caixa: quem manda é a descrição da config (a mesma frase do
        botão na tela), e este campo entra só se a entrada da config sumir. Nenhum dos dois termina
        com a pergunta - "Continuar?" é acrescentado uma única vez por Get-WinForgeRepairConfirmText.

        'ExpectMinutes' é quanto a linha COSTUMA levar, e é o que deixa o cabeçalho da janela ficar
        âmbar a 1,5x e urgente a 3x (Get-WinForgeFollowHeader). Existe porque a queixa que abriu esta
        leva foram 404 minutos olhando um contador subir sem saber se aquilo era normal.

        OS NÚMEROS ABAIXO SÃO ESTIMATIVAS A CALIBRAR. Eles saíram de máquina de desenvolvimento e de
        ordem de grandeza conhecida (um DISM baixa da internet, um agendamento de disco é instantâneo,
        uma restauração de permissões caminha o perfil inteiro), e não de telemetria: disco lento,
        perfil de 300 GB ou link ruim mudam cada um deles. Errar para MAIS é o lado seguro - um âmbar
        cedo demais treina o usuário a ignorar a cor, que é exatamente o que este campo combate.
        Toda linha que altera a máquina declara o campo; as que só leem declaram quando demoram
        (ChkdskScan varre o disco inteiro).
    .OUTPUTS
        Hashtable com Title, Command, Requires, Native, Kind, ExpectMinutes e (fora de 'read') Confirm.
    #>
    param([Parameter(Mandatory)][string]$Name)

    switch ($Name) {
        'SecurityStatus' {
            return @{
                Title    = 'Estado de TPM, Secure Boot e BitLocker'
                Command  = 'Get-WinForgeSecurityStatus'
                Requires = $null
                Native   = $false
                Kind     = 'read'
            }
        }
        'SmartReport' {
            return @{
                Title    = 'Saúde dos discos (SMART)'
                Command  = 'Get-WinForgeSmartReport'
                Requires = 'Get-PhysicalDisk'
                Native   = $false
                Kind     = 'read'
            }
        }
        'DotNetStatus' {
            return @{
                Title    = 'Estado do .NET Framework 3.5 e 4.8'
                Command  = 'Get-WinForgeDotNetStatus'
                Requires = $null
                Native   = $false
                Kind     = 'read'
            }
        }
        'ChkdskScan' {
            # 'chkdsk /scan' é o modo online e somente leitura do chkdsk: varre o volume com o
            # Windows rodando e não repara nada. Demora minutos num disco cheio - por isso roda em
            # runspace, como todo comando desta máquina.
            return @{
                Title         = 'Verificar disco do sistema agora (chkdsk /scan)'
                Command       = 'Invoke-WinForgeChkdskScan'
                Requires      = (Get-WinForgeSystemExe -Name 'chkdsk.exe')
                Native        = $false
                Kind          = 'read'
                ExpectMinutes = 10
            }
        }
        'WmiRepair' {
            return @{
                Title         = 'Repositório WMI: verificar e recuperar'
                Command       = 'Invoke-WinForgeWmiRepair'
                Requires      = (Get-WinForgeSystemExe -Name 'wbem\winmgmt.exe')
                Native        = $false
                Kind          = 'repair'
                ExpectMinutes = 5
                Confirm       = 'Verificar o repositório WMI e, se ele estiver inconsistente, tentar recuperá-lo. Programas que consultam o WMI podem falhar durante a recuperação. Exige o WinForge aberto como administrador: sem elevação a verificação responde "acesso negado" e nada é recuperado.'
            }
        }
        'StoreReregister' {
            return @{
                Title         = 'Microsoft Store e App Installer: registrar de novo'
                Command       = 'Invoke-WinForgeStoreReregister'
                Requires      = 'Get-AppxPackage'
                Native        = $false
                Kind          = 'repair'
                ExpectMinutes = 5
                Confirm       = 'Registrar de novo a Microsoft Store, o App Installer (winget) e o Store Purchase App PARA O USUÁRIO ATUAL, a partir dos arquivos que já estão no disco. Os aplicativos fecham durante o registro. Outros usuários desta máquina não são afetados: cada um precisa rodar isto no próprio logon.'
            }
        }
        'ChkdskSchedule' {
            return @{
                Title         = 'Agendar chkdsk /f na próxima reinicialização'
                Command       = 'Invoke-WinForgeChkdskSchedule'
                Requires      = (Get-WinForgeSystemExe -Name 'fsutil.exe')
                Native        = $false
                Kind          = 'repair'
                # Dois minutos para um 'fsutil dirty set', que responde na hora: o que demora é o
                # chkdsk da PRÓXIMA inicialização, e esse não roda dentro do WinForge.
                ExpectMinutes = 2
                Confirm       = 'Marcar o disco do sistema como "sujo" (fsutil dirty set): na próxima reinicialização o Windows roda o chkdsk com reparo antes de carregar, e isso pode demorar bastante. NÃO TEM DESFAZER: quem limpa a marca é o próprio chkdsk, e só quando concluir que o volume está íntegro - até lá a verificação se repete a cada reinicialização.'
            }
        }
        'MemoryDiag' {
            return @{
                Title         = 'Diagnóstico de memória na próxima reinicialização'
                Command       = 'Invoke-WinForgeMemoryDiagSchedule'
                Requires      = (Get-WinForgeSystemExe -Name 'bcdedit.exe')
                Native        = $false
                Kind          = 'repair'
                ExpectMinutes = 2
                Confirm       = 'Colocar o Diagnóstico de Memória do Windows na sequência de inicialização: a próxima reinicialização vai testar a memória antes de carregar o Windows.'
            }
        }
        'DotNet35Enable' {
            return @{
                Title         = '.NET Framework 3.5: habilitar (DISM)'
                Command       = 'Enable-WinForgeDotNet35'
                Requires      = $null
                Native        = $false
                Kind          = 'install'
                ExpectMinutes = 20
                Confirm       = 'Habilitar o recurso NetFx3 (.NET Framework 3.5) pelo DISM. Os arquivos vêm do Windows Update: precisa de internet e pode demorar.'
            }
        }
        'VcRedist' {
            # Sem 'Requires': quem procura o winget é Get-WinForgeWingetPath, que também olha a pasta
            # do App Installer quando ele não está no PATH (é o caso logo depois de um logon novo).
            # 'Requires = winget.exe' recusaria o botão justamente nessa máquina, que é onde ele mais
            # serve. Winget ausente vira texto na janela, com o que fazer a respeito.
            return @{
                Title         = 'Visual C++ 2005–2022 (x86/x64) via winget'
                Command       = 'Install-WinForgeVcRedist'
                Requires      = $null
                Native        = $false
                Kind          = 'install'
                ExpectMinutes = 20
                Confirm       = 'Instalar (ou atualizar) os pacotes redistribuíveis do Visual C++ de 2005 a 2022, x86 e x64, pelo winget. São vários downloads e pode demorar.'
            }
        }
        'PowerShell7' {
            return @{
                Title         = 'PowerShell 7 via winget'
                Command       = 'Install-WinForgePowerShell7'
                Requires      = $null
                Native        = $false
                Kind          = 'install'
                ExpectMinutes = 10
                Confirm       = 'Instalar o PowerShell 7 (Microsoft.PowerShell) pelo winget. O Windows PowerShell 5.1 continua instalado e é ele que o WinForge usa.'
            }
        }
        # ------------------------------------------------------------------ Correções (vindas da base)
        # Estas cinco linhas não têm 'Command': elas têm 'Steps', e quem as roda é
        # Start-WinForgeStreamedCommand, não Invoke-WinForgeCommandCore. O motivo é o tempo. Um
        # dcdiag responde em segundos e cabe no modelo "roda, devolve texto, abre janela"; um sfc, um
        # DISM ou uma redefinição do Windows Update levam de minutos a mais de uma hora, e uma janela
        # que só aparece no fim é indistinguível de um botão quebrado.
        #
        # Na base, os cinco botões chamavam a função direto da THREAD DA JANELA e escreviam num
        # console que o lançador esconde: a aba inteira congelava e nada aparecia na tela. Aqui eles
        # ganham runspace, janela que acompanha o arquivo ao vivo e a mesma pergunta de Sim/Não das
        # outras ações que alteram o sistema.
        #
        # 'ConfigKey' existe porque a entrada da config destas cinco veio da BASE e não segue o
        # padrão WPFWFRep<Nome>: é dela que sai a descrição da caixa de confirmação, a mesma frase
        # que a dica do botão mostra na aba Config.
        'NetworkReset' {
            return @{
                Title         = 'Rede - Redefinir'
                ConfigKey     = 'WPFFixesNetwork'
                Requires      = (Get-WinForgeSystemExe -Name 'netsh.exe')
                Kind          = 'repair'
                ExpectMinutes = 2
                Stream        = $true
                # 'utf8' no netsh: medido, ele escreve UTF-8 quando a saída é redirecionada (o 'ç'
                # sai como 0xC3 0xA7, dois bytes). É a mesma medição que já estava anotada no
                # levantamento do perfil e na aba Servidor; aqui a dica dizia OEM.
                Steps     = @(
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'netsh.exe'); Arguments = @('winsock', 'reset'); Encoding = 'utf8' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'netsh.exe'); Arguments = @('int', 'ip', 'reset'); Encoding = 'utf8' }
                )
                Final     = 'Configuração de rede redefinida. Reinicie o computador.'
                Confirm   = 'Redefine a pilha de rede com "netsh winsock reset" e "netsh int ip reset": as configurações de TCP/IP e do Winsock voltam ao padrão do Windows. Não reinstala nem troca driver de rede, e não mexe em antivírus, firewall ou VPN. É preciso reiniciar o computador para concluir.'
            }
        }
        'NtpPool' {
            # Quatro passos, e os dois de serviço são função porque Start-Service/Restart-Service são
            # cmdlets: 'net start w32time' faria a mesma coisa chamando um executável a mais e
            # perdendo a mensagem de erro em português do próprio PowerShell.
            return @{
                Title         = 'Servidor NTP - Ativar'
                ConfigKey     = 'WPFFixesNTPPool'
                Requires      = (Get-WinForgeSystemExe -Name 'w32tm.exe')
                Kind          = 'repair'
                ExpectMinutes = 2
                Stream        = $true
                Steps     = @(
                    @{ Function = 'Start-WinForgeTimeService' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'w32tm.exe'); Arguments = @('/config', '/update', '/manualpeerlist:pool.ntp.org,0x8', '/syncfromflags:MANUAL'); Encoding = 'oem' }
                    @{ Function = 'Restart-WinForgeTimeService' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'w32tm.exe'); Arguments = @('/resync'); Encoding = 'oem' }
                )
                Final     = 'Servidor de horário configurado para pool.ntp.org.'
                Confirm   = 'Troca o servidor NTP padrão do Windows (time.windows.com) pelo pool.ntp.org: inicia o serviço de Horário do Windows, grava a nova lista de servidores, reinicia o serviço e força uma sincronização.'
            }
        }
        'SystemRepair' {
            # A ordem é dependência, não gosto: o disco primeiro (um setor ruim corrompe de novo o
            # que o sfc acabou de consertar), o sfc depois e o DISM por último, porque é ele que
            # repõe a imagem de onde o sfc copia os arquivos bons.
            #
            # A dica de 'Encoding' de cada passo é MEDIDA, byte a byte, com o mesmo
            # ProcessStartInfo do fluxo ao vivo (a tabela está em Get-WinForgeOutputEncoding):
            #
            # - chkdsk: 'ansi'. O 'ó' dele sai como 0xF3, que é CP1252; em OEM 850 seria 0xA2.
            #   Lido como OEM, "concluídos" chegava à janela como 'concluÝdos' e "Estágio" como
            #   'EstÃgio' - foi assim que este desvio apareceu, numa execução elevada de verdade.
            # - sfc: 'unicode'. Quando a saída dele é redirecionada, ele passa a escrever UTF-16LE.
            #   Lida como OEM, cada caractere vira uma letra seguida de um byte zero.
            # - DISM: 'oem'. Conferido com 'Dism.exe /Online /Get-Version' redirecionado: o 'õ' de
            #   "Permissões" sai como 0xE4 e o 'ó' de "obrigatórias" como 0xA2, que são os bytes da
            #   code page 850.
            return @{
                Title         = 'Verificação de corrupção do sistema - Executar'
                ConfigKey     = 'WPFPanelDISM'
                Requires      = (Get-WinForgeSystemExe -Name 'sfc.exe')
                Kind          = 'repair'
                # A mais demorada da tabela, e a própria confirmação já dizia isso: "de vários
                # minutos a mais de uma hora". Uma hora é a estimativa; o âmbar só aparece na segunda.
                ExpectMinutes = 60
                Stream        = $true
                Steps     = @(
                    # O volume sai de Get-WinForgeSystemDriveRoot (que nasce de
                    # [Environment]::SystemDirectory), e não de $env:SystemDrive: variável de
                    # ambiente é herdada do processo pai e pode apontar para outro volume. É a mesma
                    # regra que as permissões do disco já seguem.
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'chkdsk.exe'); Arguments = @((Get-WinForgeSystemDriveRoot).TrimEnd('\'), '/scan', '/perf'); Encoding = 'ansi' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'sfc.exe'); Arguments = @('/scannow'); Encoding = 'unicode' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'Dism.exe'); Arguments = @('/Online', '/Cleanup-Image', '/RestoreHealth'); Encoding = 'oem' }
                )
                Final     = 'Verificação de corrupção concluída.'
                Confirm   = 'Roda em sequência o chkdsk (verificação do disco do sistema, só leitura), o sfc /scannow (reparo dos arquivos protegidos do Windows) e o DISM /RestoreHealth (reparo da imagem do Windows, que baixa arquivos pela internet). Pode levar de vários minutos a mais de uma hora.'
            }
        }
        'WindowsUpdateReset' {
            return @{
                Title         = 'Windows Update - Redefinir'
                ConfigKey     = 'WPFFixesUpdate'
                Requires      = $null
                Kind          = 'repair'
                ExpectMinutes = 20
                Stream        = $true
                Steps     = @(
                    @{ Function = 'Invoke-WPFFixesUpdate' }
                )
                Final     = 'Windows Update redefinido. Reinicie o computador.'
                Confirm   = 'Redefine o Windows Update: para os serviços, apaga a fila do BITS e o log, renomeia a pasta de downloads, registra de novo as DLLs, remove as configurações de WSUS, redefine o Winsock e religa os serviços. É preciso reiniciar o computador depois.'
            }
        }
        'WingetReinstall' {
            return @{
                Title         = 'WinGet - Reinstalar'
                ConfigKey     = 'WPFFixesWinget'
                Requires      = $null
                Kind          = 'repair'
                ExpectMinutes = 10
                Stream        = $true
                Steps     = @(
                    @{ Function = 'Invoke-WPFFixesWinget' }
                )
                Final     = 'Reinstalação do WinGet concluída.'
                Confirm   = 'Age só quando o WinGet está ausente ou quebrado: se ele já responde, este botão não faz nada. Caso contrário, instala o provedor NuGet, baixa da Galeria do PowerShell o módulo Microsoft.WinGet.Client e chama o Repair-WinGetPackageManager, que repõe o Gerenciador de Pacotes do Windows para todos os usuários. Precisa de internet. Os programas já instalados por ele continuam onde estão.'
            }
        }
        'DirectX' {
            # O WinForge NÃO baixa executável nenhum. A versão anterior deste botão baixava o
            # dxwebsetup.exe para %TEMP% e o abria com o token de administrador do programa - e
            # %TEMP% é gravável por qualquer processo de integridade média do mesmo usuário: entre a
            # conferência da assinatura e o Start-Process cabia a troca do arquivo, e a pasta podia
            # ser uma junção apontando para outro lugar. Quem baixa e executa agora é o usuário, no
            # navegador, com o token dele: este botão só abre a página oficial da Microsoft.
            #
            # 'read' porque é o que ele é: abrir uma página não altera a máquina, e uma caixa de
            # Sim/Não para abrir um link treinaria o usuário a clicar em "Sim" sem ler - justamente o
            # hábito que a confirmação do 'repair' precisa combater.
            #
            # 'OpensExternal' avisa o -SelfTest: esta é a única linha 'read' cujo comando abre coisa
            # fora do WinForge, e um build que a rodasse de verdade abriria um navegador na máquina
            # de quem compila.
            return @{
                Title         = 'DirectX: abrir a página oficial da Microsoft'
                Command       = "Start-Process 'https://www.microsoft.com/download/details.aspx?id=35'"
                Requires      = $null
                Native        = $false
                Kind          = 'read'
                OpensExternal = $true
            }
        }
        # ------------------------------------------------- Permissões do disco do sistema
        # O caso que deu origem a estes três botões: uma atualização de fabricante derrubou a cadeia
        # de permissões do disco do Windows e o dono da máquina ficou sem acesso às próprias pastas.
        #
        # As duas ações que escrevem são 'Stream' com UM passo de função, e não com a lista de
        # fases em 'Steps'. O motivo é que o plano não é uma fila fixa: ele PARA quando o chkdsk
        # acusa erro no volume (mexer em DACL de um disco com problema é consertar o que vai
        # corromper de novo), e a fase do takeown só existe se a raiz responder "acesso negado".
        # Invoke-WinForgeStreamedSteps roda todos os passos, um atrás do outro, sempre - decisão
        # nenhuma cabe nele. Quem conduz as fases é a função; o fluxo ao vivo continua sendo o
        # mesmo, porque o passo de função manda cada linha para o arquivo assim que ela sai.
        'AclVerify' {
            return @{
                Title    = 'Permissões do disco C: - Verificar'
                Command  = 'Get-WinForgeAclReport'
                Requires = $null
                Native   = $false
                Kind     = 'read'
            }
        }
        'AclRestore' {
            return @{
                Title         = 'Permissões do disco C: - Restaurar padrões'
                Requires      = (Get-WinForgeSystemExe -Name 'icacls.exe')
                Kind          = 'repair'
                # A linha da queixa: 404 minutos numa execução real, contra estes 15 de estimativa.
                # Ela caminha o perfil inteiro, então varia com o tamanho dele - o âmbar a 22:30 e o
                # urgente a 45:00 são justamente o que faltou naquele dia.
                ExpectMinutes = 15
                Stream        = $true
                Steps         = @(@{ Function = 'Invoke-WinForgeAclRestore' })
                Final         = 'Reinicie o computador: serviços e programas já abertos continuam com as permissões antigas em cache até o próximo logon.'
                Confirm       = 'Devolve as permissões do disco do Windows ao padrão de fábrica, em fases: chkdsk de verificação do volume, backup das listas atuais (a lista e o dono de cada pasta em SDDL, mais um arquivo de icacls com o conteúdo da sua pasta de usuário), a raiz do disco, as pastas do sistema uma a uma e a sua pasta de usuário. Leva minutos e pede reinicialização no fim.'
            }
        }
        'AclUndo' {
            return @{
                Title         = 'Permissões do disco C: - Desfazer (restaurar backup)'
                Requires      = (Get-WinForgeSystemExe -Name 'icacls.exe')
                Kind          = 'repair'
                ExpectMinutes = 10
                Stream        = $true
                Steps         = @(@{ Function = 'Invoke-WinForgeAclUndo' })
                Final         = 'Reinicie o computador para que os programas já abertos passem a enxergar as permissões que voltaram.'
                Confirm       = 'Reaplica as listas de permissão guardadas na última restauração de padrões, a partir da pasta protegida do WinForge, e tenta devolver também a posse de cada pasta. Sem backup gravado, não faz nada.'
            }
        }
        # A terceira ação de permissões só APAGA arquivo, e mesmo assim é 'repair' com fluxo ao
        # vivo: a pasta pode ter centenas de GB e a lista do que vai sair precisa aparecer na tela
        # antes do primeiro Remove-Item. Ela fecha o par aberto pela guarda da segunda restauração -
        # numa máquina que rodou a 1.7.0 o índice antigo não tem a marca de consumido, conta como
        # pendente e recusa toda restauração nova; sem este botão não havia saída dessa recusa.
        'AclCleanup' {
            return @{
                Title         = 'Permissões do disco C: - Limpar backups antigos'
                Requires      = $null
                Kind          = 'repair'
                # Apagar centenas de GB de um disco lento não é instantâneo, e a lista do que vai
                # sair aparece antes do primeiro Remove-Item.
                ExpectMinutes = 10
                Stream        = $true
                Steps         = @(@{ Function = 'Invoke-WinForgeAclCleanup' })
                Final         = 'A pasta de backup continua protegida: o que ficou nela é backup que ninguém desfez, e é dele que o botão Desfazer depende.'
                Confirm  = 'Lista os arquivos da pasta protegida de backup de permissões com tamanho e data e apaga apenas os que nenhum backup pendente usa: os avulsos, que índice nenhum referencia, e os conjuntos que o Desfazer já aplicou. Backup que ninguém desfez nunca sai.'
            }
        }
        # ---- Rede. O primeiro degrau da escada é de LEITURA, e é de propósito: "conectado certinho
        # e sem navegar" prova que o rádio associou e autenticou, ou seja, que o driver funciona.
        # Arrancar driver antes de olhar é trocar um problema que se conserta por um que deixa a
        # máquina sem rádio.
        #
        # 'read' com fluxo ao vivo: são doze leituras, e algumas (as sondas, as duas consultas de
        # nome) esperam pela rede. Sem o fluxo, a janela abriria só no fim, que é indistinguível de
        # um botão quebrado - o mesmo motivo que tirou os cinco botões de Correções da thread da
        # janela.
        'NetDiagFull' {
            return @{
                Title    = 'Rede — Diagnóstico completo'
                Requires = $null
                Kind     = 'read'
                Stream   = $true
                Steps    = @(@{ Function = 'Invoke-WinForgeNetworkDiagnostic' })
                Final    = 'Leitura concluída: nada foi alterado nesta máquina.'
            }
        }
        # O segundo degrau, e o primeiro que MEXE. Quatro passos, e a ordem é o conserto: esvaziar o
        # cache de nomes, devolver o endereço, pedir outro e limpar o cache de nomes NetBIOS.
        # Devolver DEPOIS de pedir jogaria fora o endereço que acabou de chegar.
        #
        # 'utf8' nos quatro: o ipconfig e o nbtstat escrevem UTF-8 quando a saída é um cano, medido
        # em wf-commands.ps1 junto com o netsh. Lidos como OEM, os acentos chegam embaralhados à
        # janela que a pessoa está olhando enquanto a rede dela cai.
        #
        # 'NetworkGuard' é o que prende esta linha à asserção que LANÇA: ver o bloco de guarda em
        # Invoke-WinForgeRepairCommand.
        'NetDnsRenew' {
            return @{
                Title         = 'Rede — Limpar cache de DNS e pegar endereço novo'
                Requires      = (Get-WinForgeSystemExe -Name 'ipconfig.exe')
                Kind          = 'repair'
                Stream        = $true
                ExpectMinutes = 2
                NetworkGuard  = 'NetDnsRenew'
                Steps         = @(
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'ipconfig.exe'); Arguments = @('/flushdns'); Encoding = 'utf8' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'ipconfig.exe'); Arguments = @('/release');  Encoding = 'utf8' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'ipconfig.exe'); Arguments = @('/renew');    Encoding = 'utf8' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'nbtstat.exe');  Arguments = @('-R');        Encoding = 'utf8' }
                )
                Final   = 'Cache de nomes esvaziado e endereço pedido de novo ao roteador. Se o endereço continuar em 169.254, o problema está entre este computador e o roteador.'
                Confirm = 'Esvazia o cache de nomes, devolve o endereço atual ao roteador e pede outro no lugar. A rede cai por alguns segundos.'
            }
        }
        # Os dois botões que mexem no driver do rádio, e eles nascem juntos porque o que VOLTA é a
        # condição do que VAI: sem volta, não se oferece a ida.
        'WifiDriverReinstall' {
            return @{
                Title         = 'Rede sem fio — Reinstalar o driver que já está instalado'
                Requires      = (Get-WinForgeSystemExe -Name 'pnputil.exe')
                Kind          = 'repair'
                Stream        = $true
                ExpectMinutes = 5
                NetworkGuard  = 'WifiDriverReinstall'
                Steps         = @(@{ Function = 'Invoke-WinForgeWifiDriverReinstall' })
                Final   = 'Se o rádio não voltar sozinho em um minuto, reinicie o computador antes de tentar qualquer outra coisa.'
                Confirm = 'Guarda uma cópia conferida do driver de rede atual, tira o rádio sem fio da lista de dispositivos e manda o Windows encontrá-lo de novo, o que reinstala o MESMO driver que já estava. Nenhum pacote é apagado. A rede sem fio cai durante a troca e volta em segundos; se o rádio voltar com problema, o driver guardado é devolvido na hora, sem perguntar. Aviso: a detecção de acesso remoto cobre a Área de Trabalho Remota do Windows, e NÃO enxerga AnyDesk, TeamViewer ou RustDesk - se você estiver usando um desses agora, vai perder a conexão.'
            }
        }
        'WifiDriverRestore' {
            return @{
                Title         = 'Rede sem fio — Voltar para o driver que estava antes'
                Requires      = (Get-WinForgeSystemExe -Name 'pnputil.exe')
                Kind          = 'repair'
                Stream        = $true
                ExpectMinutes = 5
                NetworkGuard  = 'WifiDriverRestore'
                Steps         = @(@{ Function = 'Invoke-WinForgeWifiDriverRestore' })
                Final   = 'Confira na lista de redes sem fio se o Wi-Fi voltou. Se não voltou, traga o driver do fabricante por cabo ou pen drive.'
                Confirm = 'Propõe ao Windows o driver de rede guardado na última cópia de segurança. Quem decide qual pacote assume o dispositivo é o próprio Windows, então isto propõe, não impõe. Sem cópia guardada o botão fica desabilitado.'
            }
        }
        'WifiDriverGeneric' {
            return @{
                Title         = 'Rede sem fio — Trocar pelo driver básico do Windows (pode ficar sem Wi-Fi)'
                Requires      = (Get-WinForgeSystemExe -Name 'pnputil.exe')
                Kind          = 'repair'
                Stream        = $true
                ExpectMinutes = 5
                NetworkGuard  = 'WifiDriverGeneric'
                Steps         = @(@{ Function = 'Invoke-WinForgeWifiDriverGeneric' })
                Final   = 'Se o Wi-Fi não voltar, use "Voltar para o driver que estava antes". Se nem assim, traga o driver do fabricante por cabo ou pen drive.'
                Confirm = 'APAGA do computador os pacotes de driver do seu rádio sem fio e deixa o Windows instalar o driver básico dele. Uma cópia conferida é guardada antes, e a volta é automática se o rádio não responder no fim. Se o driver básico não servir para este rádio, a máquina fica sem rede sem fio até você trazer o driver do fabricante de outro computador - tenha um cabo à mão. Aviso: a detecção de acesso remoto cobre a Área de Trabalho Remota do Windows, e NÃO enxerga AnyDesk, TeamViewer ou RustDesk - se você estiver usando um desses agora, vai perder a conexão.'
            }
        }
    }
    throw "Comando de reparo desconhecido: '$Name'."
}

function Test-WinForgeRepairElevated {
    <#
    .SYNOPSIS
        Diz se o processo está elevado.
    .DESCRIPTION
        Existe porque as leituras de segurança se comportam diferente sem elevação: Get-Tpm e
        Get-BitLockerVolume não devolvem "nada", devolvem "Acesso negado" depois de segundos cada um.
        Perguntar antes evita a espera e deixa o texto dizer o motivo real ("sem elevação") em vez de
        despejar a mensagem de erro do cmdlet.
    #>
    try {
        return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-WinForgeSecurityStatus {
    <#
    .SYNOPSIS
        TPM, Secure Boot, BitLocker e segurança baseada em virtualização (VBS), em texto.
    .DESCRIPTION
        As quatro respostas que aparecem juntas em toda conversa sobre "esta máquina roda o Windows
        11 / está criptografada / está com o Core Isolation ligado". Cada uma vem de uma fonte
        diferente e cada uma falha de um jeito diferente - daí um try/catch por item, e nunca uma
        exceção subindo: o botão é de leitura, e "n/d" é uma resposta legítima.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    $elevado = Test-WinForgeRepairElevated
    $linhas = New-Object System.Collections.Generic.List[string]
    $linhas.Add("Computador: $env:COMPUTERNAME")
    $linhas.Add('')

    # ---- TPM
    if ($elevado) {
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            $linhas.Add("TPM presente: $(if ($tpm.TpmPresent) { 'sim' } else { 'não' })")
            $linhas.Add("TPM pronto para uso: $(if ($tpm.TpmReady) { 'sim' } else { 'não' })")
            $linhas.Add("TPM habilitado: $(if ($tpm.TpmEnabled) { 'sim' } else { 'não' }) | ativado: $(if ($tpm.TpmActivated) { 'sim' } else { 'não' })")
            $versao = $null
            try { $versao = ((Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -ErrorAction Stop).SpecVersion -split ',')[0].Trim() } catch { $versao = $null }
            if ($versao) { $linhas.Add("Versão da especificação do TPM: $versao") }
        } catch {
            $linhas.Add("TPM: n/d ($($_.Exception.Message))")
        }
    } else {
        $linhas.Add('TPM: n/d (sem elevação)')
    }

    # ---- Secure Boot: em BIOS legado o cmdlet lança "não há suporte nesta plataforma", e essa é a
    # resposta - não um erro a esconder. Sem elevação ele lança outra coisa ("Não é possível definir
    # privilégios apropriados. Acesso negado."), que não fala do Secure Boot e sim do WinForge: aí a
    # linha diz o motivo real, como as do TPM e do BitLocker.
    if ($elevado) {
        try {
            $sb = Confirm-SecureBootUEFI -ErrorAction Stop
            $linhas.Add("Secure Boot: $(if ($sb) { 'ligado' } else { 'desligado' })")
        } catch {
            $linhas.Add("Secure Boot: n/d ($($_.Exception.Message))")
        }
    } else {
        $linhas.Add('Secure Boot: n/d (sem elevação)')
    }

    # ---- BitLocker
    if ($elevado) {
        try {
            $vols = @(Get-BitLockerVolume -ErrorAction Stop)
            if ($vols.Count -eq 0) {
                $linhas.Add('BitLocker: nenhum volume reportado.')
            } else {
                foreach ($v in $vols) {
                    $linhas.Add("BitLocker $($v.MountPoint): proteção $($v.ProtectionStatus), estado $($v.VolumeStatus), criptografado $($v.EncryptionPercentage)%")
                }
            }
        } catch {
            $linhas.Add("BitLocker: n/d ($($_.Exception.Message))")
        }
    } else {
        $linhas.Add('BitLocker: n/d (sem elevação)')
    }

    # ---- VBS / Credential Guard: os dois números que interessam são o que está CONFIGURADO e o que
    # está RODANDO. Máquina com VBS configurado e não rodando é o caso comum de "liguei e não fez
    # efeito"; por isso os dois aparecem, com o significado do código ao lado.
    try {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
        $estado = switch ([int]$dg.VirtualizationBasedSecurityStatus) {
            0 { 'desligada' }
            1 { 'ligada, mas não rodando' }
            2 { 'ligada e rodando' }
            default { "código $($dg.VirtualizationBasedSecurityStatus)" }
        }
        $linhas.Add("Segurança baseada em virtualização (VBS): $estado")
        # O zero da lista não é um serviço: é como o WMI diz "nenhum". Sem tirá-lo, o relatório de uma
        # máquina com VBS desligada trazia a linha "serviço 0: configurado sim | rodando sim".
        $conf = @(@($dg.SecurityServicesConfigured) | Where-Object { [int]$_ -ne 0 })
        $rod  = @(@($dg.SecurityServicesRunning) | Where-Object { [int]$_ -ne 0 })
        $nomes = @{ 1 = 'Credential Guard'; 2 = 'Integridade de código protegida por hipervisor (HVCI)'; 3 = 'Inicialização segura do System Guard'; 4 = 'Proteção de DMA por SMM' }
        $servicos = @(@($conf + $rod) | Sort-Object -Unique)
        if ($servicos.Count -eq 0) {
            $linhas.Add('  Nenhum serviço de segurança baseado em virtualização configurado.')
        } else {
            foreach ($s in $servicos) {
                $rotulo = if ($nomes.ContainsKey([int]$s)) { $nomes[[int]$s] } else { "serviço $s" }
                $linhas.Add("  $rotulo`: configurado $(if ($s -in $conf) { 'sim' } else { 'não' }) | rodando $(if ($s -in $rod) { 'sim' } else { 'não' })")
            }
        }
    } catch {
        $linhas.Add("Segurança baseada em virtualização (VBS): n/d ($($_.Exception.Message))")
    }

    return ($linhas -join "`r`n")
}

function Get-WinForgeSmartReport {
    <#
    .SYNOPSIS
        Saúde dos discos: modelo, tipo, tamanho, estado e os contadores SMART de cada um.
    .DESCRIPTION
        Get-PhysicalDisk responde em qualquer Windows 8+ e não exige elevação; os contadores de
        confiabilidade (Get-StorageReliabilityCounter), sim - e num disco USB ou num controlador RAID
        eles simplesmente não existem. Cada disco vai no seu try/catch: um disco sem contador não
        pode tirar do relatório os outros que têm.

        Os campos escolhidos são os que respondem "este disco está morrendo?": Wear (desgaste do
        SSD), ReadErrorsUncorrected/WriteErrorsUncorrected (erro que o disco não conseguiu corrigir)
        e PowerOnHours.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    $linhas = New-Object System.Collections.Generic.List[string]
    $discos = @()
    try {
        $discos = @(Get-PhysicalDisk -ErrorAction Stop)
    } catch {
        return "Não foi possível listar os discos: $($_.Exception.Message)"
    }
    if ($discos.Count -eq 0) { return 'Nenhum disco físico reportado por Get-PhysicalDisk.' }

    $linhas.Add(($discos |
        Select-Object DeviceId,
                      FriendlyName,
                      MediaType,
                      BusType,
                      @{ Name = 'TamanhoGB'; Expression = { [math]::Round($_.Size / 1GB, 1) } },
                      HealthStatus,
                      OperationalStatus |
        Format-Table -AutoSize | Out-String -Width 4096).TrimEnd())
    $linhas.Add('')
    $linhas.Add('Contadores SMART por disco')
    $linhas.Add('-' * 78)

    foreach ($d in $discos) {
        $linhas.Add('')
        $linhas.Add("Disco $($d.DeviceId) - $($d.FriendlyName)")
        try {
            $c = $d | Get-StorageReliabilityCounter -ErrorAction Stop
            if ($null -eq $c) {
                $linhas.Add('  Sem contadores de confiabilidade para este disco.')
                continue
            }
            $linhas.Add("  Temperatura: $(if ($null -ne $c.Temperature) { "$($c.Temperature) °C" } else { 'n/d' }) (máxima registrada: $(if ($null -ne $c.TemperatureMax) { "$($c.TemperatureMax) °C" } else { 'n/d' }))")
            $linhas.Add("  Horas ligado: $(if ($null -ne $c.PowerOnHours) { $c.PowerOnHours } else { 'n/d' })")
            $linhas.Add("  Desgaste (Wear): $(if ($null -ne $c.Wear) { $c.Wear } else { 'n/d' })")
            $linhas.Add("  Erros de leitura não corrigidos: $(if ($null -ne $c.ReadErrorsUncorrected) { $c.ReadErrorsUncorrected } else { 'n/d' })")
            $linhas.Add("  Erros de escrita não corrigidos: $(if ($null -ne $c.WriteErrorsUncorrected) { $c.WriteErrorsUncorrected } else { 'n/d' })")
        } catch {
            $linhas.Add("  Contadores indisponíveis: $($_.Exception.Message)")
        }
    }

    $linhas.Add('')
    $linhas.Add('Desgaste alto, erros não corrigidos acima de zero ou estado diferente de "Healthy" pedem backup imediato e troca do disco.')
    return ($linhas -join "`r`n")
}

function Get-WinForgeDotNetStatus {
    <#
    .SYNOPSIS
        Estado do .NET Framework 3.5 (recurso NetFx3) e da linha 4.x instalada.
    .DESCRIPTION
        São duas perguntas diferentes com duas fontes diferentes:

        - O 3.5 é um RECURSO opcional do Windows: quem responde é Get-WindowsOptionalFeature, que
          exige elevação. Sem admin o texto diz "n/d (sem elevação)" em vez de despejar o erro do
          DISM.
        - O 4.x é INSTALADO, não é recurso: quem responde é o valor 'Release' em
          HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full, que é um número crescente por
          versão (528040 = 4.8). Ler o registro não exige elevação.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    $linhas = New-Object System.Collections.Generic.List[string]

    if (Test-WinForgeRepairElevated) {
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
            $linhas.Add(".NET Framework 3.5 (NetFx3): $($f.State)")
            if ([string]$f.State -ne 'Enabled') {
                $linhas.Add('  Use o botão ".NET Framework 3.5: habilitar (DISM)" para instalá-lo (precisa de internet).')
            }
        } catch {
            $linhas.Add(".NET Framework 3.5 (NetFx3): n/d ($($_.Exception.Message))")
        }
    } else {
        $linhas.Add('.NET Framework 3.5 (NetFx3): n/d (sem elevação)')
    }

    # A tabela vai do maior para o menor: o 'Release' é um piso, não um valor exato (uma atualização
    # do 4.8 sobe o número), então a primeira faixa que couber é a versão instalada.
    $faixas = @(
        @{ Release = 533320; Nome = '4.8.1' },
        @{ Release = 528040; Nome = '4.8' },
        @{ Release = 461808; Nome = '4.7.2' },
        @{ Release = 461308; Nome = '4.7.1' },
        @{ Release = 460798; Nome = '4.7' },
        @{ Release = 394802; Nome = '4.6.2' },
        @{ Release = 394254; Nome = '4.6.1' },
        @{ Release = 393295; Nome = '4.6' },
        @{ Release = 379893; Nome = '4.5.2' },
        @{ Release = 378675; Nome = '4.5.1' },
        @{ Release = 378389; Nome = '4.5' }
    )
    $release = $null
    try { $release = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release } catch { $release = $null }
    if ($null -eq $release) {
        $linhas.Add('.NET Framework 4.x: não encontrado (chave NDP\v4\Full ausente).')
    } else {
        $nome = 'anterior a 4.5'
        foreach ($f in $faixas) {
            if ([int]$release -ge $f.Release) { $nome = $f.Nome; break }
        }
        $linhas.Add(".NET Framework 4.x: $nome (Release $release)")
        if ([int]$release -lt 528040) {
            $linhas.Add('  Abaixo de 4.8 (Release 528040): vale atualizar pelo Windows Update.')
        }
    }

    $linhas.Add('')
    $linhas.Add('O 3.5 e o 4.x convivem: programas antigos pedem o 3.5 mesmo com o 4.8 instalado.')
    return ($linhas -join "`r`n")
}

function Invoke-WinForgeChkdskScan {
    <#
    .SYNOPSIS
        Verificação online e somente leitura do disco do sistema (chkdsk /scan).
    .DESCRIPTION
        '/scan' é o modo online do chkdsk: varre o volume com o Windows rodando, não desmonta nada e
        não repara nada - o que ele acha vira relatório, e o reparo fica para o botão de agendamento.
        Por isso este é o único comando do grupo classificado como leitura.
    .OUTPUTS
        Texto com o código de saída na primeira linha.
    #>
    $unidade = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($unidade)) { $unidade = 'C:' }
    $r = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'chkdsk.exe') -Arguments @($unidade, '/scan')
    return "chkdsk $unidade /scan - código de saída: $($r.ExitCode)`r`n`r`n$($r.Text)"
}

function Start-WinForgeTimeService {
    <#
    .SYNOPSIS
        Liga o serviço de Horário do Windows (w32time). Passo do botão "Servidor NTP - Ativar".
    .DESCRIPTION
        O w32tm só configura um serviço que está de pé: numa máquina onde o Horário do Windows está
        parado (o padrão em várias instalações de cliente), o '/config' responde "o serviço não foi
        iniciado" e a troca do servidor não acontece. O passo existe por causa disso.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return 'Start-Service w32time' }
    Assert-WinForgeNotSelfTest -Name 'Start-WinForgeTimeService'
    Start-Service -Name w32time -ErrorAction Stop
    Write-Host "Serviço de Horário do Windows (w32time) iniciado."
}

function Restart-WinForgeTimeService {
    <#
    .SYNOPSIS
        Reinicia o serviço de Horário do Windows. Passo do botão "Servidor NTP - Ativar".
    .DESCRIPTION
        O w32tm grava a nova lista de servidores no registro, mas o serviço só a lê ao subir: sem o
        reinício, o '/resync' do passo seguinte ainda falaria com o time.windows.com.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return 'Restart-Service w32time' }
    Assert-WinForgeNotSelfTest -Name 'Restart-WinForgeTimeService'
    Restart-Service -Name w32time -Force -ErrorAction Stop
    Write-Host "Serviço de Horário do Windows (w32time) reiniciado."
}

function Select-WinForgeNewestPackage {
    <#
    .SYNOPSIS
        O pacote de versão mais alta de uma lista de pacotes Appx.
    .DESCRIPTION
        Existe por um motivo só, e é um que morde calado: a propriedade Version de Get-AppxPackage é
        TEXTO. Ordenar texto põe '1.9.0.0' na frente de '1.25.0.0' - o 9 é maior que o 2 -, e quem
        pega o primeiro acaba com a pasta de instalação de uma versão antiga que pode já ter sido
        removida. Convertendo para [version] antes de ordenar, 1.25.0.0 volta a ser a mais nova.

        Uma versão que não converte (formato inesperado) vira 0.0.0.0 em vez de derrubar a ordenação:
        um pacote esquisito na lista não pode fazer o botão inteiro falhar.

        Função pura, sem tocar na máquina: é assim que o -SelfTest prova a ordem com uma lista
        sintética, sem depender do que está instalado em quem compila.
    .OUTPUTS
        O objeto de maior versão, ou $null quando a lista está vazia.
    #>
    param([object[]]$Package)

    if ($null -eq $Package -or $Package.Count -eq 0) { return $null }
    return ($Package | Sort-Object {
        $v = $null
        if ([version]::TryParse([string]$_.Version, [ref]$v)) { $v } else { [version]'0.0.0.0' }
    } -Descending | Select-Object -First 1)
}

function Test-WinForgeTrustedAppxPackage {
    <#
    .SYNOPSIS
        Diz se um pacote Appx é mesmo o da Microsoft: editor, origem da assinatura e pasta.
    .DESCRIPTION
        A porteira que faltava entre 'Get-AppxPackage -Name Microsoft.DesktopAppInstaller' e rodar o
        winget.exe daquela pasta com o token de administrador do WinForge. '-Name' filtra pela
        identidade declarada no MANIFESTO do pacote, e manifesto é texto que quem instala escolhe: um
        pacote sideloaded (modo desenvolvedor, arquivos soltos no perfil de qualquer usuário da
        máquina) pode se chamar Microsoft.DesktopAppInstaller, dizer que é a versão 99.0.0.0 e ganhar
        a ordenação por versão. A pasta dele é gravável por integridade média - e o WinForge abriria
        o executável de lá elevado.

        Três perguntas, e as três precisam de sim:

        1. PublisherId '8wekyb3d8bbwe'. CUIDADO com o que ele prova: é o hash do NOME do editor
           declarado no manifesto ("CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond,
           S=Washington, C=US"), e não do certificado que assinou o pacote. Quem copia o nome copia o
           hash junto - sozinho, este item não separa nada. Ele fica como primeiro filtro barato, e o
           que de fato tranca a porta é o item 2.
        2. SignatureKind 'Store' ou 'System'. É AQUI que mora a garantia: o valor sai da assinatura
           conferida pelo Windows na instalação, não de texto do manifesto. 'Developer', 'Enterprise'
           e 'None' ficam de fora - são exatamente as origens que um usuário com modo desenvolvedor
           ligado consegue produzir.
        3. InstallLocation dentro de %ProgramFiles%\WindowsApps. É a pasta que só o TrustedInstaller
           escreve; %LOCALAPPDATA%\...\WindowsApps é OUTRA coisa (aliases de execução, graváveis pelo
           usuário). A raiz vem de [Environment]::GetFolderPath(ProgramFiles), e não de
           %ProgramFiles%: variável de ambiente nasce de HKCU\Environment, que um processo de
           integridade MÉDIA da conta escreve - com ela apontando para uma pasta do perfil, o
           "prefixo de WindowsApps" passaria a ser um caminho gravável. A comparação é por prefixo de
           caminho COMPLETO (GetFullPath), sem depender de maiúsculas, e nenhum pedaço do caminho
           pode ser ponto de reanálise - uma junção plantada no meio faria uma pasta gravável
           responder por um caminho que começa em WindowsApps.

        Função pura no que decide: recebe o objeto do pacote, não lista nada. O único toque no disco
        é a leitura de atributo de pasta - e ela agora é FECHADA: pasta que não existe, ou que não
        deixa ler o atributo, vale como reprovada. Antes o Get-Item nulo era simplesmente pulado, o
        que é exatamente a resposta errada para a pergunta "este caminho é o que ele diz ser?". Isso
        muda o que o -SelfTest consegue montar: a pasta dos casos positivos tem de existir de
        verdade, e um caminho inventado dentro de WindowsApps é agora um caso NEGATIVO.
    .OUTPUTS
        $true ou $false. Tudo que não deu para confirmar é $false.
    #>
    param([object]$Package)

    if ($null -eq $Package) { return $false }
    if ([string]$Package.PublisherId -ne '8wekyb3d8bbwe') { return $false }
    if ([string]$Package.SignatureKind -notin @('Store', 'System')) { return $false }

    $local = [string]$Package.InstallLocation
    if ([string]::IsNullOrWhiteSpace($local)) { return $false }

    $raiz = $null
    try { $raiz = [string][Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles) } catch { $raiz = $null }
    if ([string]::IsNullOrWhiteSpace($raiz)) { return $false }

    try {
        $raizCheia = [System.IO.Path]::GetFullPath((Join-Path $raiz 'WindowsApps'))
        $localCheio = [System.IO.Path]::GetFullPath($local)
    } catch {
        return $false
    }
    if (-not $raizCheia.EndsWith('\')) { $raizCheia += '\' }
    if (-not $localCheio.StartsWith($raizCheia, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }

    # Ponto de reanálise em QUALQUER nível, da pasta do pacote até a raiz de WindowsApps: uma junção
    # no meio do caminho manda a leitura para outro lugar sem mudar uma letra do texto do caminho.
    #
    # Get-Item nulo é REPROVA, e não "segue em frente". A varredura existe para responder se o
    # caminho é mesmo o que o texto diz; um nível que não pôde ser lido é justamente o nível sobre o
    # qual nada se sabe, e pular a pergunta é responder "sim". Na prática o nulo aparece quando a
    # pasta não existe - InstallLocation apontando para um caminho que já foi removido, ou inventado
    # - e nesses casos não há winget nenhum para rodar de lá.
    try {
        $atual = $localCheio
        while (-not [string]::IsNullOrWhiteSpace($atual) -and $atual.Length -ge ($raizCheia.Length - 1)) {
            $item = Get-Item -LiteralPath $atual -Force -ErrorAction SilentlyContinue
            if ($null -eq $item) { return $false }
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint) { return $false }
            $pai = Split-Path -Parent $atual
            if ([string]::IsNullOrWhiteSpace($pai) -or $pai -eq $atual) { break }
            $atual = $pai
        }
    } catch {
        return $false
    }

    return $true
}

function Get-WinForgeWingetPath {
    <#
    .SYNOPSIS
        Caminho do winget.exe, ou $null quando ele não existe nesta máquina.
    .DESCRIPTION
        O PATH NÃO é resposta aqui, e essa é a decisão principal desta função. Num processo elevado
        'Get-Command winget.exe' resolve para %LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe - um
        alias de execução numa pasta gravável por qualquer processo de integridade média do mesmo
        usuário. Trocar o alias por um executável qualquer bastaria para o botão do Visual C++ rodar
        esse executável com token de administrador. O mesmo vale para uma pasta plantada no PATH.

        A única origem aceita é o pacote do App Installer instalado pela Store, e ele passa antes por
        Test-WinForgeTrustedAppxPackage: editor 8wekyb3d8bbwe, assinatura de Store ou do sistema e
        pasta dentro de %ProgramFiles%\WindowsApps, sem junção no caminho. Um pacote sideloaded que
        se diga Microsoft.DesktopAppInstaller versão 99.0.0.0 é descartado ANTES da ordenação - senão
        ele venceria justamente por ter a versão mais alta.

        Entre os pacotes que sobram, a escolha passa por Select-WinForgeNewestPackage: Version é
        texto e a ordem de texto elegeria a versão errada.

        -AllUsers exige elevação: sem admin ele lança, e o catch cai na listagem do usuário atual - o
        filtro de confiança é o mesmo nos dois caminhos.
    .OUTPUTS
        Caminho completo do winget.exe, ou $null.
    #>
    $pacotes = @()
    try {
        $pacotes = @(Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction Stop)
    } catch {
        try { $pacotes = @(Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop) } catch { $pacotes = @() }
    }
    $confiaveis = @($pacotes | Where-Object { Test-WinForgeTrustedAppxPackage -Package $_ })
    $pacote = Select-WinForgeNewestPackage -Package $confiaveis
    if ($null -eq $pacote -or [string]::IsNullOrWhiteSpace($pacote.InstallLocation)) { return $null }

    $caminho = Join-Path ([string]$pacote.InstallLocation) 'winget.exe'
    if (Test-Path -LiteralPath $caminho -PathType Leaf) { return $caminho }
    return $null
}

function Assert-WinForgeNotSelfTest {
    <#
    .SYNOPSIS
        Lança quando o WinForge está em modo SelfTest. É a trava que nenhuma função que ESCREVE pula.
    .DESCRIPTION
        Nasceu de um estrago real: durante o desenvolvimento, uma chamada de teste a um ajudante que
        ainda não tinha bloco param() engoliu o -DryRun em $args, e o instalador web do DirectX foi
        baixado e ABERTO na máquina de quem estava compilando; o winget rodou os doze pacotes do
        Visual C++ na mesma rodada. Uma função PowerShell sem param() aceita qualquer switch em
        silêncio - não há erro, não há aviso, e a "simulação" mexe no sistema.

        A resposta tem duas camadas, e esta é a segunda: mesmo que o -DryRun se perca outra vez, toda
        função que altera a máquina pergunta se o programa está em modo SelfTest e RECUSA. O build
        marca $sync.SelfTest = $true na primeira linha do bloco de teste; uma execução normal nunca
        define a chave, e uma chave ausente num hashtable é $null - ou seja, falso.

        A ordem dentro de cada ajudante importa e é sempre a mesma: param() primeiro, o retorno de
        -DryRun em seguida, esta trava DEPOIS. Assim a simulação continua funcionando dentro do
        SelfTest (é ela que exercita as tabelas) e só o caminho que escreve é barrado.
    .PARAMETER Name
        Nome da função que está sendo barrada, para a mensagem dizer QUEM foi recusado. Quando não
        vem, sai da pilha de chamadas.
    #>
    param([string]$Name)

    if (-not $sync.SelfTest) { return }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        try {
            $pilha = @(Get-PSCallStack)
            if ($pilha.Count -gt 1) { $Name = [string]$pilha[1].FunctionName }
        } catch { $Name = '(desconhecida)' }
    }
    throw "Recusado: '$Name' altera o sistema e o WinForge está em modo SelfTest."
}

function Test-WinForgeWingetInstalled {
    <#
    .SYNOPSIS
        Lê a resposta de 'winget list --id <id> -e' e diz se o pacote já está na máquina.
    .DESCRIPTION
        O código de saída sozinho não basta: em algumas versões do winget uma origem que responde
        devagar também sai com 0 e um texto de "nenhum pacote encontrado". Mas procurar o id INTEIRO
        na saída é o erro oposto - a listagem do winget é uma TABELA de largura fixa, e um id longo
        como 'Microsoft.VCRedist.2015+.x64' sai cortado com reticências na coluna Id. O id inteiro
        nunca aparece, o pacote instalado é dado como ausente e o botão manda instalar de novo os doze
        redistribuíveis - minutos de winget para não mudar nada.

        Por isso a busca é pelo PREFIXO do id: até o último ponto ('Microsoft.VCRedist.2015+' para o
        exemplo acima) e, se ainda assim ele passar de 20 caracteres, só os 20 primeiros - a coluna
        corta em largura, não em ponto. O que se perde é o fim do id; o que se ganha é a leitura
        funcionar. Quando o id não tem ponto, vale ele inteiro (limitado do mesmo jeito).

        Perder o fim do id não afrouxa a conferência tanto quanto parece: a pergunta foi feita com
        '--id <id> -e', que é busca EXATA - a saída ou é o pacote pedido, ou é o texto de "nenhum
        pacote encontrado". O prefixo serve para distinguir esses dois casos, não para escolher entre
        pacotes.

        Função pura: recebe o código e o texto, não chama nada.
    .OUTPUTS
        $true ou $false.
    #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [int]$ExitCode,
        [string]$Text
    )

    if ($ExitCode -ne 0) { return $false }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $ponto = $Id.LastIndexOf('.')
    $prefixo = if ($ponto -gt 0) { $Id.Substring(0, $ponto) } else { $Id }
    if ($prefixo.Length -gt 20) { $prefixo = $prefixo.Substring(0, 20) }
    return ([string]$Text -match [regex]::Escape($prefixo))
}

function Invoke-WinForgeWmiRepair {
    <#
    .SYNOPSIS
        Verifica o repositório WMI e só tenta recuperá-lo quando ele está inconsistente.
    .DESCRIPTION
        A ordem importa e é o que separa este botão de um "resetrepository" às cegas:

        1. 'winmgmt /verifyrepository' diz se o repositório está consistente.
        2. Consistente: para aqui. Recuperar um repositório saudável é trabalho inútil com risco de
           perder registros de classes de programas instalados.
        3. Inconsistente: 'winmgmt /salvagerepository', que tenta reconstruir a partir do que dá para
           aproveitar (o /resetrepository, que joga tudo fora, fica de fora de propósito).
        4. Verifica de novo, para o texto terminar dizendo se resolveu.

        Entre o 2 e o 3 mora a elevação, e ela é conferida ANTES do salvage por um motivo concreto:
        sem admin o /verifyrepository não responde "inconsistente", responde "acesso negado" - e o
        código de saída dele não é 0 do mesmo jeito. Um salvage disparado por acesso negado seria uma
        reconstrução do repositório WMI de uma máquina saudável, decidida por uma leitura que nunca
        aconteceu. Por isso, sem elevação, o texto diz que precisa de elevação e para aí.

        A saída de cada passo entra inteira no relatório: é ela que alguém vai colar num chamado.
    .PARAMETER DryRun
        Diz o que faria e não chama o winmgmt. Existe em toda função que escreve, e não só nas que o
        -SelfTest simula: uma função sem param() engole o switch em silêncio e roda de verdade.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return '[simulação] winmgmt /verifyrepository e, se o repositório estiver inconsistente e o WinForge estiver elevado, winmgmt /salvagerepository seguido de nova verificação.' }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $linhas = New-Object System.Collections.Generic.List[string]

    $ver = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'wbem\winmgmt.exe') -Arguments @('/verifyrepository')
    $linhas.Add("winmgmt /verifyrepository - código de saída: $($ver.ExitCode)")
    $linhas.Add([string]$ver.Text)

    # Código 0 é a resposta boa do /verifyrepository; qualquer outro é "inconsistente" (ou o serviço
    # não respondeu). O texto muda com o idioma do Windows, o código não.
    if ($ver.ExitCode -eq 0) {
        $linhas.Add('Repositório consistente: nada a recuperar.')
        return ($linhas -join "`r`n")
    }

    if (-not (Test-WinForgeRepairElevated)) {
        $linhas.Add('')
        $linhas.Add('O repositório não foi dado como consistente, mas este WinForge não está elevado: precisa de elevação para saber se o problema é real.')
        $linhas.Add('Sem admin o próprio /verifyrepository responde "acesso negado", e recuperar o repositório com base nessa resposta reconstruiria o WMI de uma máquina que pode estar saudável.')
        $linhas.Add('Feche o WinForge, abra como administrador e clique de novo.')
        return ($linhas -join "`r`n")
    }

    $linhas.Add('')
    $linhas.Add('Repositório inconsistente: tentando recuperar (winmgmt /salvagerepository).')
    $sal = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'wbem\winmgmt.exe') -Arguments @('/salvagerepository')
    $linhas.Add("winmgmt /salvagerepository - código de saída: $($sal.ExitCode)")
    $linhas.Add([string]$sal.Text)

    $linhas.Add('')
    $ver2 = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'wbem\winmgmt.exe') -Arguments @('/verifyrepository')
    $linhas.Add("winmgmt /verifyrepository (depois) - código de saída: $($ver2.ExitCode)")
    $linhas.Add([string]$ver2.Text)
    if ($ver2.ExitCode -eq 0) {
        $linhas.Add('Repositório consistente depois da recuperação.')
    } else {
        $linhas.Add('O repositório continua inconsistente. O próximo passo costuma ser reinstalar o Windows por cima (upgrade in-place), preservando programas e arquivos.')
    }
    return ($linhas -join "`r`n")
}

function Invoke-WinForgeStoreReregister {
    <#
    .SYNOPSIS
        Registra de novo, PARA O USUÁRIO ATUAL, a Microsoft Store, o App Installer (winget) e o Store
        Purchase App.
    .DESCRIPTION
        É o reparo padrão de "a Store não abre" e de "o winget sumiu": o pacote continua no disco, só
        o registro do usuário se perdeu. Add-AppxPackage -Register aponta para o AppXManifest.xml da
        própria pasta de instalação e refaz esse registro, sem baixar nada.

        O registro vale só para QUEM ESTÁ RODANDO o WinForge, e isso não é uma limitação de elevação
        que dá para contornar: 'Add-AppxPackage -Register' registra no perfil do chamador. Elevar
        muda o chamador, não amplia o alcance - num WinForge aberto como outro administrador o
        registro sairia no perfil DELE, e o usuário que reclamou continuaria sem a Store. Registrar
        para os outros usuários é outro comando (-AllUsers em Add-AppxPackage, que só aceita pacote
        provisionado) e não é o que este botão faz.

        -AllUsers em Get-AppxPackage é outra coisa: é só a LISTAGEM, e serve para achar a pasta de
        instalação de um pacote que sumiu do perfil atual. Ele exige elevação; sem admin, cai para os
        pacotes do usuário atual.

        Quando a listagem traz mais de uma versão do mesmo pacote, o registro usa a mais nova
        (Select-WinForgeNewestPackage): Version é texto, e registrar a mais antiga significa apontar
        para uma pasta que a próxima limpeza do Windows apaga.

        Cada pacote tem seu try/catch: um que não existe nesta edição do Windows não pode derrubar os
        outros dois.
    .PARAMETER DryRun
        Devolve os pacotes que seriam registrados, sem listar nem registrar nada.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return '[simulação] Add-AppxPackage -Register do AppXManifest.xml de Microsoft.WindowsStore, Microsoft.DesktopAppInstaller e Microsoft.StorePurchaseApp, para o usuário atual.' }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $alvos = @('Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.StorePurchaseApp')
    $linhas = New-Object System.Collections.Generic.List[string]

    foreach ($alvo in $alvos) {
        $linhas.Add('')
        $linhas.Add("== $alvo")
        $pacotes = @()
        try {
            $pacotes = @(Get-AppxPackage -AllUsers -Name $alvo -ErrorAction Stop)
        } catch {
            try { $pacotes = @(Get-AppxPackage -Name $alvo -ErrorAction Stop) } catch { $pacotes = @() }
        }
        if ($pacotes.Count -eq 0) {
            $linhas.Add('  Pacote não encontrado nesta máquina.')
            continue
        }
        # O mesmo filtro de confiança do winget, e pelo mesmo motivo: '-Name' filtra pela identidade
        # declarada no manifesto, e é o AppXManifest.xml apontado aqui que o Add-AppxPackage vai
        # registrar no perfil de quem está com o WinForge aberto. Um pacote sideloaded com o nome
        # certo e versão alta venceria a ordenação e seria registrado no lugar do da Store.
        # -DisableDevelopmentMode recusa pacote não assinado, mas não pergunta QUEM assinou.
        $descartados = @($pacotes).Count
        $pacotes = @(@($pacotes) | Where-Object { Test-WinForgeTrustedAppxPackage -Package $_ })
        $descartados = $descartados - $pacotes.Count
        if ($descartados -gt 0) {
            $linhas.Add("  $descartados pacote(s) descartado(s): não são da Microsoft Store em %ProgramFiles%\WindowsApps (editor, assinatura ou pasta fora do esperado).")
        }
        if ($pacotes.Count -eq 0) {
            $linhas.Add('  Nenhum pacote confiável desta identidade nesta máquina.')
            continue
        }
        # Uma arquitetura de cada pacote registra por vez; entre versões duplicadas do mesmo pacote
        # vale a mais nova. Sem isso, registrar 1.9.0.0 por cima de 1.25.0.0 desfaria uma atualização.
        $porNome = $pacotes | Group-Object -Property Name
        foreach ($grupo in $porNome) {
            $p = Select-WinForgeNewestPackage -Package @($grupo.Group)
            if ($null -eq $p) { continue }
            if (@($grupo.Group).Count -gt 1) {
                $linhas.Add("  $($grupo.Name): $(@($grupo.Group).Count) versões instaladas, usando a mais nova ($($p.Version)).")
            }
            if ([string]::IsNullOrWhiteSpace($p.InstallLocation)) {
                $linhas.Add("  $($p.PackageFullName): sem pasta de instalação (pacote provisionado, nada a registrar).")
                continue
            }
            $manifesto = Join-Path $p.InstallLocation 'AppXManifest.xml'
            if (-not (Test-Path -LiteralPath $manifesto)) {
                $linhas.Add("  $($p.PackageFullName): AppXManifest.xml não encontrado em $($p.InstallLocation).")
                continue
            }
            try {
                Add-AppxPackage -DisableDevelopmentMode -Register $manifesto -ErrorAction Stop
                $linhas.Add("  $($p.PackageFullName): registrado para o usuário atual.")
            } catch {
                $linhas.Add("  $($p.PackageFullName): falhou - $($_.Exception.Message)")
            }
        }
    }

    $linhas.Add('')
    $linhas.Add('O registro vale para o usuário que está com o WinForge aberto, e só para ele: cada usuário desta máquina que estiver com a Store quebrada precisa rodar este botão no próprio logon.')
    $linhas.Add('Se a Store continuar sem abrir, reinicie o computador antes de tentar de novo: o registro só vale a partir do próximo logon em alguns casos.')
    return (($linhas -join "`r`n").Trim())
}

function Enable-WinForgeDotNet35 {
    <#
    .SYNOPSIS
        Habilita o recurso NetFx3 (.NET Framework 3.5) pelo DISM, se já não estiver habilitado.
    .DESCRIPTION
        Os arquivos do 3.5 não vêm na imagem instalada: o DISM os busca no Windows Update, então isto
        exige internet e pode demorar minutos. -All traz junto as sub-features (WCF), e -NoRestart
        deixa a decisão de reiniciar com quem clicou.
    .PARAMETER DryRun
        Diz o que faria e não chama o DISM (nem a consulta ao recurso, que já carrega módulo).
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return '[simulação] Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart, quando o recurso não estiver habilitado.' }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $linhas = New-Object System.Collections.Generic.List[string]

    $atual = $null
    try {
        $atual = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
    } catch {
        return "Não foi possível consultar o recurso NetFx3: $($_.Exception.Message)`r`n`r`nGet-WindowsOptionalFeature exige o WinForge aberto como administrador."
    }

    $linhas.Add("Estado atual do NetFx3: $($atual.State)")
    if ([string]$atual.State -eq 'Enabled') {
        $linhas.Add('O .NET Framework 3.5 já está habilitado: nada a fazer.')
        return ($linhas -join "`r`n")
    }

    $linhas.Add('Habilitando pelo DISM (os arquivos vêm do Windows Update; pode demorar).')
    try {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction Stop
        $linhas.Add("Reinicialização necessária: $(if ($r.RestartNeeded) { 'sim' } else { 'não' })")
    } catch {
        $linhas.Add("Falhou: $($_.Exception.Message)")
        $linhas.Add('Erro 0x800F0954 costuma ser uma política de WSUS bloqueando o Windows Update: nesse caso o recurso precisa da mídia de instalação do Windows (-Source).')
        return ($linhas -join "`r`n")
    }

    try {
        $depois = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction Stop
        $linhas.Add("Estado depois: $($depois.State)")
    } catch { }
    return ($linhas -join "`r`n")
}

function Install-WinForgeVcRedist {
    <#
    .SYNOPSIS
        Instala (ou atualiza) os redistribuíveis do Visual C++ de 2005 a 2022, x86 e x64, pelo winget.
    .DESCRIPTION
        Programa que abre com "VCRUNTIME140.dll não encontrada" quer exatamente esta lista. As duas
        arquiteturas entram sempre: num Windows x64 os programas de 32 bits são a maioria dos que
        pedem o pacote.

        O winget é chamado com -FilePath/-Arguments (nunca com texto montado), um id por vez, e o
        código de saída de cada um vira uma linha do relatório - um pacote que falha não interrompe
        os outros. Código 0 é sucesso; -1978335189 é "nenhuma atualização aplicável", que aqui
        significa "já está instalado e atualizado".

        Antes de instalar cada id vem um 'winget list --id <id> -e', que é leitura pura: o que já
        está na máquina é pulado com uma linha dizendo isso. São doze pacotes e a maioria das
        máquinas já tem quase todos - sem essa pergunta, o botão gastaria minutos para o winget
        responder doze vezes que não havia nada a fazer.
    .PARAMETER DryRun
        Devolve a lista de ids e não chama o winget. É o que o -SelfTest usa para conferir a lista
        (os doze pacotes, nas duas arquiteturas, na ordem) sem instalar nada em quem compila.
    .OUTPUTS
        Com -DryRun: os ids, em ordem. Sem -DryRun: texto pronto para a janela de saída.
    #>
    param([switch]$DryRun)

    $ids = @(
        'Microsoft.VCRedist.2005.x86', 'Microsoft.VCRedist.2005.x64',
        'Microsoft.VCRedist.2008.x86', 'Microsoft.VCRedist.2008.x64',
        'Microsoft.VCRedist.2010.x86', 'Microsoft.VCRedist.2010.x64',
        'Microsoft.VCRedist.2012.x86', 'Microsoft.VCRedist.2012.x64',
        'Microsoft.VCRedist.2013.x86', 'Microsoft.VCRedist.2013.x64',
        'Microsoft.VCRedist.2015+.x86', 'Microsoft.VCRedist.2015+.x64'
    )
    if ($DryRun) { return $ids }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $winget = Get-WinForgeWingetPath
    if (-not $winget) {
        return "winget não encontrado: use 'WinGet - Reinstalar' (aba Config) ou o botão 'Microsoft Store e App Installer: registrar de novo' e tente de novo."
    }

    $linhas = New-Object System.Collections.Generic.List[string]
    $linhas.Add("winget: $winget")
    $linhas.Add('')
    $instalados = 0

    foreach ($id in $ids) {
        # 'winget list --id <id> -e' devolve 0 quando achou, e o código sozinho não basta (uma origem
        # lenta também sai com 0 e um texto de "nenhum pacote encontrado"). Quem lê a resposta é
        # Test-WinForgeWingetInstalled: a saída é uma tabela de largura fixa e o id sai CORTADO na
        # coluna, então a busca é pelo prefixo dele até o último ponto.
        $lista = Invoke-WinForgeNativeCommand -FilePath $winget -Encoding 'utf8' -Arguments @('list', '--id', $id, '-e', '--disable-interactivity', '--accept-source-agreements')
        if (Test-WinForgeWingetInstalled -Id $id -ExitCode ([int]$lista.ExitCode) -Text ([string]$lista.Text)) {
            $linhas.Add("$id`: já instalado (nada a fazer)")
            $instalados++
            continue
        }

        $r = Invoke-WinForgeNativeCommand -FilePath $winget -Encoding 'utf8' -Arguments @(
            'install', '--id', $id, '-e', '--silent', '--disable-interactivity',
            '--accept-package-agreements', '--accept-source-agreements'
        )
        $situacao = switch ([int]$r.ExitCode) {
            0 { 'instalado' }
            -1978335189 { 'já instalado e atualizado' }
            -1978335212 { 'pacote não encontrado na origem' }
            default { "código $($r.ExitCode)" }
        }
        $linhas.Add("$id`: $situacao")
    }

    $linhas.Add('')
    $linhas.Add("$instalados de $($ids.Count) pacote(s) já estavam na máquina e foram pulados.")
    $linhas.Add('Reinicie os programas que reclamavam de DLL depois da instalação.')
    return ($linhas -join "`r`n")
}

function Install-WinForgePowerShell7 {
    <#
    .SYNOPSIS
        Instala o PowerShell 7 (Microsoft.PowerShell) pelo winget.
    .DESCRIPTION
        Instalação lado a lado: o Windows PowerShell 5.1 continua onde está, e é ele que roda o
        WinForge. O 7 aparece como "PowerShell 7" no menu Iniciar (pwsh.exe).
    .PARAMETER DryRun
        Devolve o comando que seria dado ao winget, sem chamá-lo.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return '[simulação] winget install --id Microsoft.PowerShell -e --silent --disable-interactivity --accept-package-agreements --accept-source-agreements' }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $winget = Get-WinForgeWingetPath
    if (-not $winget) {
        return "winget não encontrado: use 'WinGet - Reinstalar' (aba Config) ou o botão 'Microsoft Store e App Installer: registrar de novo' e tente de novo."
    }

    $r = Invoke-WinForgeNativeCommand -FilePath $winget -Encoding 'utf8' -Arguments @(
        'install', '--id', 'Microsoft.PowerShell', '-e', '--silent', '--disable-interactivity',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    $cabecalho = "winget: $winget`r`nMicrosoft.PowerShell - código de saída: $($r.ExitCode)"
    if ([int]$r.ExitCode -eq -1978335189) { $cabecalho += ' (já instalado e atualizado)' }
    return "$cabecalho`r`n`r`n$([string]$r.Text)"
}

function Invoke-WinForgeChkdskSchedule {
    <#
    .SYNOPSIS
        Marca o disco do sistema para o chkdsk /f rodar na próxima reinicialização.
    .DESCRIPTION
        'fsutil dirty set' liga o bit de "volume sujo": é exatamente o que o chkdsk /f faz quando não
        consegue bloquear o volume em uso, e é a forma sem interação de agendar a verificação com
        reparo - 'chkdsk /f' direto faria uma pergunta no console, e não há console nenhum na frente
        do usuário aqui.

        É de MÃO ÚNICA: não existe 'fsutil dirty clear'. Quem limpa o bit é o autochk, e só depois de
        rodar e concluir que o volume está íntegro. Enquanto o disco tiver problema que ele não
        conserta, o chkdsk volta a rodar A CADA reinicialização - o botão não tem desfazer, e é isso
        que o texto de confirmação precisa dizer antes do clique.

        Depois de marcar, 'fsutil dirty query' confirma o estado: o relatório termina dizendo o que
        vai acontecer no próximo boot, não o que se pretendia fazer.
    .PARAMETER DryRun
        Diz qual volume seria marcado e não chama o fsutil. A marca é de mão única: não existe
        'fsutil dirty clear', então esta é a função em que um -DryRun engolido custa mais caro.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return "[simulação] fsutil dirty set $(if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { 'C:' } else { $env:SystemDrive }) - marcaria o volume para o chkdsk rodar na próxima reinicialização." }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $unidade = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($unidade)) { $unidade = 'C:' }

    $linhas = New-Object System.Collections.Generic.List[string]
    $set = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'fsutil.exe') -Arguments @('dirty', 'set', $unidade)
    $linhas.Add("fsutil dirty set $unidade - código de saída: $($set.ExitCode)")
    $linhas.Add([string]$set.Text)
    if ($set.ExitCode -ne 0) {
        $linhas.Add('')
        $linhas.Add('Marcar o volume exige o WinForge aberto como administrador.')
        return ($linhas -join "`r`n")
    }

    $linhas.Add('')
    $query = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'fsutil.exe') -Arguments @('dirty', 'query', $unidade)
    $linhas.Add("fsutil dirty query $unidade - código de saída: $($query.ExitCode)")
    $linhas.Add([string]$query.Text)
    $linhas.Add('')
    $linhas.Add("Na próxima reinicialização o Windows roda o chkdsk em $unidade antes de carregar. Num disco grande isso pode demorar bastante - não desligue a máquina no meio.")
    $linhas.Add('')
    $linhas.Add('Não há como desmarcar: quem limpa a marca é o próprio chkdsk, depois de rodar e concluir que o volume está íntegro. Se o disco tiver um problema que ele não consegue reparar, a verificação vai se repetir em toda reinicialização até o problema sair do caminho.')
    return ($linhas -join "`r`n")
}

function Invoke-WinForgeMemoryDiagSchedule {
    <#
    .SYNOPSIS
        Coloca o Diagnóstico de Memória do Windows na sequência da próxima inicialização.
    .DESCRIPTION
        'bcdedit /bootsequence {memdiag}' é uma ordem de UMA vez: a próxima inicialização vai para o
        teste de memória e a seguinte volta ao normal sozinha - diferente de mudar o item padrão do
        gerenciador de inicialização, que ficaria valendo para sempre.

        A confirmação sai de 'bcdedit /enum {bootmgr}': a linha 'bootsequence' só existe quando a
        ordem foi aceita, então o relatório mostra a linha real em vez de repetir a intenção.

        Os RÓTULOS do /enum são traduzidos - num Windows em português a linha é 'sequência de
        inicialização', não 'bootsequence', e a busca não acha nada mesmo com a ordem aceita. Por
        isso o caminho de "não achei" não manda ninguém "conferir o resultado acima": ele imprime o
        /enum inteiro, que é onde a resposta está em qualquer idioma. Quem decide se deu certo é o
        código de saída do /bootsequence, já conferido acima; esta parte é só a leitura de apoio.
    .PARAMETER DryRun
        Diz o que faria e não chama o bcdedit.
    .OUTPUTS
        Texto pronto para a janela de saída.
    #>
    param([switch]$DryRun)

    if ($DryRun) { return '[simulação] bcdedit /bootsequence {memdiag} - colocaria o Diagnóstico de Memória na próxima inicialização, uma vez só.' }
    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $linhas = New-Object System.Collections.Generic.List[string]
    $set = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'bcdedit.exe') -Arguments @('/bootsequence', '{memdiag}')
    $linhas.Add("bcdedit /bootsequence {memdiag} - código de saída: $($set.ExitCode)")
    $linhas.Add([string]$set.Text)
    if ($set.ExitCode -ne 0) {
        $linhas.Add('')
        $linhas.Add('Alterar a sequência de inicialização exige o WinForge aberto como administrador.')
        return ($linhas -join "`r`n")
    }

    $enum = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'bcdedit.exe') -Arguments @('/enum', '{bootmgr}')
    $sequencia = @([string]$enum.Text -split "`r?`n" | Where-Object { $_ -match '(?i)bootsequence' })
    $linhas.Add('')
    if ($sequencia.Count) {
        $linhas.Add('Sequência de inicialização atual:')
        foreach ($l in $sequencia) { $linhas.Add("  $($l.Trim())") }
    } else {
        $linhas.Add('Nenhuma linha "bootsequence" foi encontrada na saída abaixo - o que é esperado num Windows traduzido, onde o rótulo aparece como "sequência de inicialização". A ordem foi aceita (código de saída 0 acima); segue o gerenciador de inicialização inteiro:')
        $linhas.Add("bcdedit /enum {bootmgr} - código de saída: $($enum.ExitCode)")
        $linhas.Add([string]$enum.Text)
    }
    $linhas.Add('')
    $linhas.Add('Reinicie para o teste começar. Ele roda antes do Windows carregar e o resultado aparece no Visualizador de Eventos (origem MemoryDiagnostics-Results) depois do próximo logon.')
    return ($linhas -join "`r`n")
}

function Invoke-WinForgeRepairCommandCore {
    <#
    .SYNOPSIS
        Invólucro do reparo sobre o núcleo genérico: resolve o nome curto na tabela e roda, síncrono.
    .DESCRIPTION
        Existe para o resto do programa (e o -SelfTest) continuar falando por nome curto. Todo o
        comportamento - ferramenta ausente virando texto, arquivo gravado em
        repair-<Nome>-<aaaaMMdd-HHmmss>.txt na pasta de logs - mora em Invoke-WinForgeCommandCore.

        Não olha o 'Kind': quem chama aqui já decidiu rodar. A decisão é de Invoke-WinForgeRepairCommand.
    .OUTPUTS
        Hashtable com Name, Title, Text, Path e ExitCode.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$DryRun
    )

    return Invoke-WinForgeCommandCore -Spec (Get-WinForgeRepairCommand -Name $Name) -Name $Name -Component 'Repair' -Prefix 'repair' -DryRun:$DryRun
}

function Get-WinForgeRepairConfirmText {
    <#
    .SYNOPSIS
        O texto da caixa de confirmação de um botão que altera o sistema.
    .DESCRIPTION
        Três partes, nesta ordem, separadas por linha em branco:

        1. O TÍTULO do botão. Sem ele a caixa seria um "Continuar?" sem dizer continuar o quê - e a
           essa altura o usuário já clicou, já tirou os olhos do botão e está lendo a caixa.
        2. A DESCRIÇÃO da config, que é a MESMA frase mostrada ao lado do botão na aba Config. Repetir
           a descrição, em vez de escrever um segundo texto só para a caixa, é o que garante que o
           que foi prometido e o que vai ser confirmado não divirjam com o tempo: um texto duplicado
           é um texto que envelhece pela metade. O 'Confirm' da tabela é a reserva, para o caso de a
           entrada da config sumir - a pergunta nunca sai em branco.
        3. A PERGUNTA. Uma só, no fim, onde o olho para.
    .OUTPUTS
        Texto de uma caixa de mensagem.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $cmd = Get-WinForgeRepairCommand -Name $Name
    $descricao = $null
    try {
        # 'ConfigKey' é das cinco linhas que vieram da base: a entrada delas na config tem o nome do
        # arquivo original (WPFFixesNetwork), não o padrão WPFWFRep<Nome> das linhas do WinForge.
        $chave = [string]$cmd.ConfigKey
        if ([string]::IsNullOrWhiteSpace($chave)) { $chave = "WPFWFRep$Name" }
        $entrada = $sync.configs.feature.$chave
        if ($entrada) { $descricao = [string]$entrada.Description }
    } catch { $descricao = $null }
    if ([string]::IsNullOrWhiteSpace($descricao)) { $descricao = [string]$cmd.Confirm }
    if ([string]::IsNullOrWhiteSpace($descricao)) { $descricao = 'Esta ação altera o sistema.' }

    return "$($cmd.Title)`r`n`r`n$($descricao.Trim())`r`n`r`nContinuar?"
}

function Get-WinForgeRepairBusyReason {
    <#
    .SYNOPSIS
        A frase de "já tem coisa rodando", ou '' quando não tem. Só LÊ o estado compartilhado: não
        toma trava nenhuma, não abre caixa e não despacha nada.
    .DESCRIPTION
        São duas travas, e elas dizem coisas diferentes:

        - $sync.CommandRunning é a desta máquina de comandos (um chkdsk /scan leva minutos).
        - $sync.ProcessRunning é a do BASE - o botão "sfc + DISM" e os de instalação. Ela só barra o
          que ALTERA o sistema: duas sessões de manutenção ao mesmo tempo fazem a segunda falhar com
          "outra operação em andamento", e ler o estado da máquina enquanto o base trabalha não
          atrapalha nada. Por isso o -Kind.

        A pergunta virou função porque ela passou a ser feita DUAS vezes no mesmo clique, e as duas
        com a mesma frase: uma antes da caixa de confirmação e outra antes da caixa de destino do
        backup de permissões. Duplicar o texto seria duplicar a manutenção dele.
    .PARAMETER Kind
        O tipo da linha da tabela. 'read' não é barrado por $sync.ProcessRunning; o resto é.
    .OUTPUTS
        A frase, ou '' quando não há nada rodando.
    #>
    param([string]$Kind = 'repair')

    if ($sync.CommandRunning) { return 'Já existe um comando em andamento. Espere ele terminar.' }
    if ([string]$Kind -ne 'read' -and $sync.ProcessRunning) { return 'O WinForge já está com uma instalação ou manutenção em andamento. Espere ela terminar antes de reparar ou instalar componente.' }
    return ''
}

function Invoke-WinForgeRepairCommand {
    <#
    .SYNOPSIS
        Ação dos botões de reparo: leitura vai direto, o que altera o sistema pergunta antes.
    .DESCRIPTION
        Nome desconhecido morre AQUI, no clique, e não dentro do runspace: a tabela é deste grupo de
        botões, e uma caixa de mensagem dizendo qual botão está errado vale mais que uma linha de log
        que ninguém vai ler.

        'Kind read' segue direto para Invoke-WinForgeCommandButton, sem pergunta: ler o estado da
        máquina não muda nada, e uma confirmação para cada leitura treinaria o usuário a clicar em
        "Sim" sem ler - que é exatamente o hábito que a confirmação do 'repair' precisa combater.

        'repair' e 'install' passam pela caixa de Sim/Não montada por Get-WinForgeRepairConfirmText,
        com ícone de aviso e SEM botão padrão de "Sim": quem não leu e apertou Enter não repara nada.
        "Não" vira uma linha de log e o botão volta ao lugar; "Sim" cai no mesmo despacho da leitura -
        a trava de um comando por vez, o runspace do pool e a janela de saída são os mesmos.

        A caixa aparece na thread da janela porque este é o handler do botão, que já roda nela. Não
        há Invoke-WPFUIThread aqui de propósito: chamá-lo de dentro da própria thread da interface
        esperaria por um Dispatcher que está parado esperando esta função retornar.

        A decisão fica antes do despacho, e não dentro do runspace, por um motivo: a trava
        $sync.CommandRunning só é tomada por Invoke-WinForgeCommandButton. Perguntar depois de tomar
        a trava deixaria o programa inteiro sem botões enquanto uma caixa espera alguém ler.

        'AclRestore' tem uma segunda pergunta pelo mesmo motivo, e no mesmo lugar: ONDE o backup das
        permissões vai ficar (Show-WinForgeAclBackupDestination). Ela é WPF e precisa da thread da
        janela, e o seletor de pasta do shell precisa do apartamento STA em que este processo nasce -
        a runspace do pool não tem nenhum dos dois. O que atravessa para lá é só o texto do caminho,
        em $sync.WinForgeAclExternalRoot, escrito UMA vez e só depois da caixa: ele é estado
        compartilhado com a restauração que já estiver correndo, e Get-WinForgeRepairBusyReason é
        perguntada outra vez logo antes de abrir a caixa por causa disso.
    .PARAMETER NoUI
        Devolve a decisão em vez de mostrar janela ou caixa de mensagem, e não despacha nada. É o que
        o -SelfTest usa: ele roda sem ninguém na frente, não pode abrir caixa nenhuma (não há quem
        responda, e o build ficaria pendurado até alguém passar pela máquina) e não pode sair
        reparando o sistema de quem compila.
    .OUTPUTS
        Com -NoUI: @{ Dispatched = <bool>; Reason = <string>; Kind = <string> }. Sem -NoUI: nada.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$NoUI
    )

    try {
        $cmd = Get-WinForgeRepairCommand -Name $Name
    } catch {
        Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message $_.Exception.Message
        if ($NoUI) { return @{ Dispatched = $false; Reason = 'desconhecido'; Kind = $null } }
        [System.Windows.MessageBox]::Show($_.Exception.Message, "WinForge", "OK", "Error") | Out-Null
        return
    }

    $kind = [string]$cmd.Kind
    if ([string]::IsNullOrWhiteSpace($kind)) { $kind = 'read' }

    # As duas travas de "já tem coisa rodando" vêm ANTES da caixa de confirmação, e não depois.
    # Perguntar primeiro e recusar depois é o pior dos dois mundos: o usuário lê o aviso inteiro,
    # decide, clica em "Sim" e só então descobre que o clique não valia nada.
    $ocupado = [string](Get-WinForgeRepairBusyReason -Kind $kind)
    if ([string]::IsNullOrWhiteSpace($ocupado)) { $ocupado = $null }
    if ($null -ne $ocupado) {
        Write-WinForgeLog -Component "Repair" -Message "$Name não despachado: $ocupado"
        if ($NoUI) { return @{ Dispatched = $false; Reason = 'ocupado'; Kind = $kind } }
        [System.Windows.MessageBox]::Show($ocupado, "WinForge", "OK", "Warning") | Out-Null
        return
    }

    # O guarda de rede é ESTRUTURAL, e não conselho: linha que declara 'NetworkGuard' não chega ao
    # despacho sem passar por uma asserção que LANÇA. Devolver @{ Ok = $false } e esperar que alguém
    # olhe é o mecanismo que já falhou neste repositório - ver o bloco de ajuda de
    # Assert-WinForgeNotSelfTest, onde um helper sem param() engoliu o -DryRun e instalador rodou de
    # verdade na máquina de um usuário.
    #
    # Ele fica AQUI, no caminho de execução, e não na pintura do botão: dois dos fatos que ele pesa
    # mudam entre pintar a aba e clicar - se o cabo ainda está ligado e se a máquina ainda está na
    # tomada. E vem ANTES da caixa de confirmação pelo mesmo motivo das duas travas acima:
    # perguntar primeiro e recusar depois faz a pessoa ler o aviso inteiro, decidir e só então
    # descobrir que o clique não valia nada.
    #
    # O valor verdadeiro vai no argumento da exportação porque nenhuma linha COM guarda exporta
    # driver; quem exportar passa o que mediu, no próprio passo que exporta, e nunca herda daqui.
    $guardaRede = [string]$cmd.NetworkGuard
    if (-not [string]::IsNullOrWhiteSpace($guardaRede)) {
        try {
            $null = Assert-WinForgeNetworkGuard -Action $guardaRede -ExportOk $true
        } catch {
            $motivoRede = [string]$_.Exception.Message
            Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message "$Name não despachado: $motivoRede"
            if ($NoUI) { return @{ Dispatched = $false; Reason = 'rede'; Kind = $kind } }
            [System.Windows.MessageBox]::Show($motivoRede, "WinForge", "OK", "Warning") | Out-Null
            return
        }
    }

    if ($kind -ne 'read') {
        if ($NoUI) {
            Write-WinForgeLog -Component "Repair" -Message "$Name não despachado: ação do tipo '$kind' precisa de confirmação e não há ninguém para confirmar."
            return @{ Dispatched = $false; Reason = 'confirmação'; Kind = $kind }
        }
        # Segunda camada da trava de SelfTest: com -NoUI o caminho já morreu acima, mas quem chamar
        # sem -NoUI durante um SelfTest não pode abrir caixa nenhuma (não há ninguém para responder e
        # o build ficaria pendurado) nem despachar coisa alguma.
        Assert-WinForgeNotSelfTest -Name "Invoke-WinForgeRepairCommand ($Name)"
        # A caixa nasce DONA da janela do WinForge quando ela existe: sem dono, ela pode aparecer
        # atrás do programa - e uma confirmação escondida é uma confirmação que alguém vai fechar no
        # susto. Sem $sync.Form (SelfTest, ou antes de a janela existir) vai a versão sem dono.
        $resposta = if ($sync.Form) {
            [System.Windows.MessageBox]::Show(
                $sync.Form,
                (Get-WinForgeRepairConfirmText -Name $Name),
                "WinForge",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning,
                [System.Windows.MessageBoxResult]::No
            )
        } else {
            [System.Windows.MessageBox]::Show(
                (Get-WinForgeRepairConfirmText -Name $Name),
                "WinForge",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning,
                [System.Windows.MessageBoxResult]::No
            )
        }
        if ($resposta -ne [System.Windows.MessageBoxResult]::Yes) {
            Write-WinForgeLog -Component "Repair" -Message "$Name cancelado na confirmação. Nada foi alterado."
            return
        }
        Write-WinForgeLog -Component "Repair" -Message "$Name confirmado pelo usuário (ação do tipo '$kind')."
    }

    if ($NoUI) { return @{ Dispatched = $false; Reason = 'NoUI'; Kind = $kind } }

    # O DESTINO do backup de permissões é perguntado AQUI, e não dentro da runspace. Três razões, e
    # nenhuma é estilo: a caixa é WPF e precisa da thread da janela; perguntar depois de
    # Invoke-WinForgeCommandButton seria perguntar com a trava $sync.CommandRunning na mão, deixando
    # o programa sem botões enquanto alguém lê; e o seletor de pasta do shell exige o apartamento STA
    # em que este processo nasce, que a runspace do pool não tem.
    #
    # O que atravessa é só o texto do caminho, em $sync.WinForgeAclExternalRoot. Ele é ESTADO
    # COMPARTILHADO com a restauração que já estiver correndo, e é daí que vêm as duas regras abaixo.
    #
    # 1. PERGUNTAR DE NOVO se há coisa rodando. A trava do começo desta função foi lida antes da
    #    caixa de confirmação, e entre uma coisa e outra o usuário passou um tempo lendo. A trava de
    #    verdade só é TOMADA em Start-WinForgeStreamedCommand, que tem a conferência dela própria -
    #    ou seja, este caminho pode chegar até lá e ser recusado. Com uma restauração de quinze
    #    minutos em curso, um segundo clique recusado lá embaixo já teria zerado o destino da rodada
    #    EM ANDAMENTO, e a fase 2 dela passaria a gravar na pasta protegida sem dizer nada a ninguém:
    #    o usuário escolheu um disco e o arquivo não estaria lá.
    # 2. ESCREVER UMA VEZ SÓ, depois da caixa. Enquanto a pessoa lê e escolhe, o valor de quem está
    #    rodando continua intacto; cancelar não mexe em nada. Não há mais "zerar agora e preencher
    #    depois".
    if ($Name -eq 'AclRestore') {
        $ocupadoDestino = [string](Get-WinForgeRepairBusyReason -Kind $kind)
        if (-not [string]::IsNullOrWhiteSpace($ocupadoDestino)) {
            Write-WinForgeLog -Component "Repair" -Message "$Name não despachado: $ocupadoDestino"
            [System.Windows.MessageBox]::Show($ocupadoDestino, "WinForge", "OK", "Warning") | Out-Null
            return
        }
        $destino = Show-WinForgeAclBackupDestination
        if (-not $destino.Ok) {
            Write-WinForgeLog -Component "Repair" -Message "$Name cancelado na escolha do destino do backup. Nada foi alterado."
            return
        }
        $sync.WinForgeAclExternalRoot = if ($destino.External) { [string]$destino.Path } else { '' }
        if ($destino.External) {
            Write-WinForgeLog -Component "Repair" -Message "${Name}: o backup do conteúdo vai para '$([string]$destino.Path)', fora da pasta protegida."
        } else {
            Write-WinForgeLog -Component "Repair" -Message "${Name}: o backup do conteúdo vai para a pasta protegida do WinForge."
        }
    }

    # Dois despachos, e a diferença é o TEMPO do comando. 'Stream' é das linhas que demoram minutos
    # ou horas (sfc, DISM, Windows Update): a janela abre vazia e se enche enquanto o trabalho
    # acontece. O resto continua no despacho de sempre - roda, devolve o texto, abre a janela pronta.
    if ($cmd.Stream) {
        Start-WinForgeStreamedCommand -Name $Name -Spec $cmd
        return
    }

    Invoke-WinForgeCommandButton -Spec $cmd -Name $Name -Component 'Repair' -Prefix 'repair'
}

# =============================================================== Permissões do disco do sistema
# O caso real: depois de uma atualização de fabricante, o disco do Windows perdeu a cadeia de
# permissões - o dono da máquina sem acesso às próprias pastas, programas que não abrem, "acesso
# negado" em toda parte. São três botões, e a ordem entre eles é a do atendimento:
#
#   Verificar          - só lê (Get-Acl) e diz o que está fora do padrão. Pode ser clicado sempre.
#   Restaurar padrões  - as seis fases abaixo, com backup antes de qualquer alteração.
#   Desfazer           - reaplica o backup mais recente, arquivo por arquivo.
#
# Três regras atravessam tudo o que está aqui embaixo:
#
# 1. SID, nunca nome. 'Administradores' só existe em português; 'Administrators' só em inglês. Uma
#    linha de icacls com nome localizado falha calada num Windows de outro idioma - e a máquina
#    quebrada fica pior do que estava. Todo direito concedido sai como '*S-1-5-32-544:(OI)(CI)F'.
# 2. Nada é montado como TEXTO de comando. Cada chamada é -FilePath + -Arguments, com o vetor de
#    argumentos inteiro, e todo executável vem por caminho completo de Get-WinForgeSystemExe.
# 3. Nas pastas do sistema (Windows, Program Files, Program Files (x86), ProgramData, Users,
#    Users\Public) o icacls só faz duas coisas, e só NA PASTA: '/setowner' quando o dono está
#    fora do padrão e '/inheritance:r /grant:r' com as ACEs medidas. '/reset', '/T' e '/R' não
#    existem ali - os três descem a árvore inteira apagando o que o Windows sabe e o WinForge não.
#
# O secedit com o defltbase.inf foi tirado daqui depois de medido: no Windows 10 e no 11 as seções
# [Registry Keys] e [File Security] desse arquivo vêm VAZIAS, então '/areas FILESTORE REGKEYS' não
# repõe DACL nenhuma. Ele demorava minutos e não consertava nada. No lugar dele entrou a fase 4,
# que aplica, pasta por pasta, a mesma tabela de esperados que a verificação usa - e só nas pastas
# que a verificação acusou.

function Get-WinForgeAclWellKnownSid {
    <#
    .SYNOPSIS
        Os SIDs conhecidos usados pela verificação e pela restauração de permissões.
    .DESCRIPTION
        Uma tabela só, para o texto do SID aparecer UMA vez no programa. O do TrustedInstaller é o
        que mais se escreve errado: ele é um SID de serviço (S-1-5-80 + o hash do nome
        'TrustedInstaller'), igual em toda instalação do Windows, e é ele o dono de C:\Windows e de
        C:\Program Files - não o grupo Administradores.
    .OUTPUTS
        Hashtable de apelido -> SID.
    #>
    return @{
        Sistema           = 'S-1-5-18'
        Administradores   = 'S-1-5-32-544'
        Usuarios          = 'S-1-5-32-545'
        Autenticados      = 'S-1-5-11'
        Todos             = 'S-1-1-0'
        Criador           = 'S-1-3-0'
        Lote              = 'S-1-5-3'
        Interativo        = 'S-1-5-4'
        Servico           = 'S-1-5-6'
        PacotesApp        = 'S-1-15-2-1'
        PacotesAppRestr   = 'S-1-15-2-2'
        TrustedInstaller  = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    }
}

function Get-WinForgeSystemDriveRoot {
    <#
    .SYNOPSIS
        A raiz do volume em que o Windows está instalado ('C:\' na esmagadora maioria das máquinas).
    .DESCRIPTION
        A âncora é [Environment]::SystemDirectory, e não %SystemDrive%, pelo mesmo motivo de
        Get-WinForgeSystemExe: variável de ambiente de processo nasce do bloco do usuário em
        HKCU\Environment, que qualquer processo de integridade média da conta escreve. Com
        'SystemDrive' apontando para outro volume, a restauração reescreveria as permissões do disco
        errado - com elevação e sem perguntar mais nada.
    .OUTPUTS
        A raiz com a barra final ('C:\').
    #>
    $dir = ''
    try { $dir = [string][Environment]::SystemDirectory } catch { $dir = '' }
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = 'C:\Windows\System32' }
    $raiz = ''
    try { $raiz = [string][System.IO.Path]::GetPathRoot($dir) } catch { $raiz = '' }
    if ([string]::IsNullOrWhiteSpace($raiz)) { $raiz = 'C:\' }
    return $raiz
}

function ConvertTo-WinForgeAclMask {
    <#
    .SYNOPSIS
        Traduz os quatro bits GENÉRICOS de uma ACE para os bits de acesso a arquivo correspondentes.
    .DESCRIPTION
        Sem isto a conferência acusa permissão faltando numa pasta impecável, e a raiz do disco é o
        exemplo: a ACE dos Usuários Autenticados lá é '(OI)(CI)(IO)M', herdável e de SOMENTE
        HERANÇA, e uma ACE assim guarda GENERIC_READ/GENERIC_WRITE/GENERIC_EXECUTE (0xE0010000) em
        vez dos bits de arquivo. Comparada direto contra FileSystemRights::Modify (0x301BF) ela não
        casa em nada, e o relatório diria que a máquina está quebrada.

        O mapeamento é o GENERIC_MAPPING do sistema de arquivos do Windows, o mesmo que o próprio
        kernel aplica quando abre o objeto. Os quatro bits genéricos saem da máscara depois de
        traduzidos: eles não significam nada na comparação.
    .OUTPUTS
        A máscara efetiva, como número.
    #>
    param([Parameter(Mandatory)][int]$Rights)

    # O enum é Int32 e os bits genéricos moram na ponta alta, então um valor com GENERIC_READ chega
    # aqui NEGATIVO. Passar por [long] e mascarar em 32 bits devolve o padrão de bits real.
    $bruto = (([long]$Rights) -band 0xFFFFFFFFL)
    $efetivo = $bruto -band 0x0FFFFFFFL
    if ($bruto -band 0x80000000L) { $efetivo = $efetivo -bor 0x00120089L }  # GENERIC_READ
    if ($bruto -band 0x40000000L) { $efetivo = $efetivo -bor 0x00120116L }  # GENERIC_WRITE
    if ($bruto -band 0x20000000L) { $efetivo = $efetivo -bor 0x001200A0L }  # GENERIC_EXECUTE
    if ($bruto -band 0x10000000L) { $efetivo = $efetivo -bor 0x001F01FFL }  # GENERIC_ALL
    return [long]$efetivo
}

function Get-WinForgeAclName {
    <#
    .SYNOPSIS
        O nome legível de um SID, com o próprio SID como resposta quando ele não traduz.
    .DESCRIPTION
        A comparação é toda por SID (é o que funciona em qualquer idioma), mas o relatório é lido por
        gente: 'S-1-5-32-544' não diz nada e 'BUILTIN\Administradores' diz tudo. SID de conta apagada
        e SID de pacote de aplicativo não traduzem - aí o próprio SID é a melhor resposta possível.
    .OUTPUTS
        Texto.
    #>
    param([Parameter(Mandatory)][string]$Sid)

    try {
        $s = New-Object System.Security.Principal.SecurityIdentifier $Sid
        return [string]$s.Translate([System.Security.Principal.NTAccount]).Value
    } catch {
        return $Sid
    }
}

function Get-WinForgeAclExpected {
    <#
    .SYNOPSIS
        O padrão do Windows para as oito pastas que a verificação olha: donos aceitos e ACEs
        obrigatórias, tudo por SID.
    .DESCRIPTION
        Dado puro, separado da leitura: é a tabela que o -SelfTest exercita com listas de permissão
        montadas na memória, sem tocar em pasta nenhuma.

        Duas escolhas explicam o resto:

        - 'Donos' é uma LISTA, e não um valor. O dono de C:\ é o TrustedInstaller em instalações
          recentes e o SYSTEM em outras, e as duas formas são padrão de fábrica. Cobrar um só faria
          o relatório acusar diferença em metade das máquinas saudáveis, que é o jeito mais rápido
          de a verificação deixar de ser lida.
        - As ACEs são um PISO, não um retrato. O que se cobra é "este SID tem ao menos este
          direito"; ACE a mais (pacotes de aplicativo, CREATOR OWNER, Todos em Users\Public) não é
          diferença. Uma pasta do sistema tem ACEs que variam com a edição e com o que já foi
          instalado, e exigir igualdade exata daria diferença em tudo.

        Windows, Program Files e Program Files (x86) pedem dono TrustedInstaller e só 'Modify' para
        SYSTEM e Administradores: é o padrão do Windows moderno, em que nem o administrador tem
        controle total sobre os arquivos do sistema sem antes tomar a posse deles.

        Além do piso de conferência, cada linha carrega o que a RESTAURAÇÃO aplica naquela pasta -
        é a mesma tabela dos dois lados, para não existir um padrão para conferir e outro para
        escrever. São três chaves:

        - 'Dono': o SID que o '/setowner' repõe quando o dono está fora da lista aceita.
        - 'Grant': as ACEs EFETIVAS na própria pasta, do '/inheritance:r /grant:r'.
        - 'GrantExtra': as ACEs herdáveis de SOMENTE HERANÇA, de um '/grant' separado. Elas não
          cabem na mesma chamada: o icacls só guarda a ÚLTIMA entrada de cada SID dentro de um
          '/grant', então '*S-1-5-18:M' e '*S-1-5-18:(OI)(CI)(IO)F' juntos viram uma ACE só.
        - 'Direta': a fase 4 conserta esta pasta. A raiz é da fase 3 e o perfil é da fase 5.

        As ACEs saíram de Get-Acl nas pastas desta máquina (Windows 11 Pro 26200, pt-BR), e não de
        documentação: é o que o Windows realmente tem quando ninguém mexeu.
    .OUTPUTS
        Vetor de hashtables com Path, Nome, Donos, Aces, Dono, Grant, GrantExtra e Direta.
    #>
    $sid = Get-WinForgeAclWellKnownSid
    $raiz = Get-WinForgeSystemDriveRoot
    $perfil = ''
    try { $perfil = [string][Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) } catch { $perfil = '' }
    $meu = ''
    try { $meu = [string][System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $meu = '' }

    $F = [int][System.Security.AccessControl.FileSystemRights]::FullControl
    $M = [int][System.Security.AccessControl.FileSystemRights]::Modify
    $RX = [int][System.Security.AccessControl.FileSystemRights]::ReadAndExecute

    $itens = @()
    $itens += @{
        Path       = $raiz
        Nome       = "Raiz do disco do sistema ($raiz)"
        Donos      = @($sid.Sistema, $sid.Administradores, $sid.TrustedInstaller)
        Dono       = ''
        Direta     = $false
        Grant      = @()
        GrantExtra = @()
        Aces       = @(
            @{ Sid = $sid.Sistema;         Rights = $F;  Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F;  Rotulo = 'Administradores com controle total' }
            @{ Sid = $sid.Usuarios;        Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
            @{ Sid = $sid.Autenticados;    Rights = $M;  Rotulo = 'Usuários Autenticados podendo modificar o que criarem' }
        )
    }
    # Windows, Program Files e Program Files (x86) têm a MESMA lista nesta máquina: cada princípio
    # aparece duas vezes, uma valendo na própria pasta e uma de somente herança para o que nascer
    # abaixo. O TrustedInstaller é o único cuja ACE herdável é só de container ((CI), sem (OI)).
    foreach ($nome in @('Windows', 'Program Files', 'Program Files (x86)')) {
        $itens += @{
            Path       = (Join-Path $raiz $nome)
            Nome       = $nome
            Donos      = @($sid.TrustedInstaller)
            Dono       = $sid.TrustedInstaller
            Direta     = $true
            Grant      = @(
                "*$($sid.Sistema):M"              # SYSTEM, modificar, na pasta
                "*$($sid.Administradores):M"      # Administradores, modificar, na pasta
                "*$($sid.Usuarios):RX"            # Usuários, ler e executar
                "*$($sid.TrustedInstaller):F"     # TrustedInstaller, controle total
                "*$($sid.PacotesApp):RX"          # TODOS OS PACOTES DE APLICATIVOS
                "*$($sid.PacotesAppRestr):RX"     # TODOS OS PACOTES DE APLICATIVOS RESTRITOS
            )
            GrantExtra = @(
                "*$($sid.Criador):(OI)(CI)(IO)F"           # CREATOR OWNER no que for criado abaixo
                "*$($sid.Sistema):(OI)(CI)(IO)F"
                "*$($sid.Administradores):(OI)(CI)(IO)F"
                "*$($sid.Usuarios):(OI)(CI)(IO)RX"
                "*$($sid.TrustedInstaller):(CI)(IO)F"      # só subpastas, como no padrão medido
                "*$($sid.PacotesApp):(OI)(CI)(IO)RX"
                "*$($sid.PacotesAppRestr):(OI)(CI)(IO)RX"
            )
            Aces       = @(
                @{ Sid = $sid.Sistema;          Rights = $M;  Rotulo = 'SYSTEM podendo modificar' }
                @{ Sid = $sid.Administradores;  Rights = $M;  Rotulo = 'Administradores podendo modificar' }
                @{ Sid = $sid.Usuarios;         Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
                @{ Sid = $sid.TrustedInstaller; Rights = $F;  Rotulo = 'TrustedInstaller com controle total' }
            )
        }
    }
    # ProgramData: as ACEs de SYSTEM, Administradores e Usuários valem na pasta E abaixo (sem (IO)).
    # A segunda ACE dos Usuários é o direito de CRIAR sem poder alterar o que já existe, que é o que
    # deixa um programa gravar a própria subpasta de dados sem mexer na dos outros.
    $itens += @{
        Path       = (Join-Path $raiz 'ProgramData')
        Nome       = 'ProgramData'
        Donos      = @($sid.Sistema, $sid.Administradores)
        Dono       = $sid.Sistema
        Direta     = $true
        Grant      = @(
            "*$($sid.Sistema):(OI)(CI)F"
            "*$($sid.Administradores):(OI)(CI)F"
            "*$($sid.Usuarios):(OI)(CI)RX"
        )
        GrantExtra = @(
            "*$($sid.Criador):(OI)(CI)(IO)F"
            "*$($sid.Usuarios):(CI)(WD,AD,WEA,WA)"
        )
        Aces       = @(
            @{ Sid = $sid.Sistema;         Rights = $F;  Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F;  Rotulo = 'Administradores com controle total' }
            @{ Sid = $sid.Usuarios;        Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
        )
    }
    $itens += @{
        Path       = (Join-Path $raiz 'Users')
        Nome       = 'Users'
        Donos      = @($sid.Sistema, $sid.Administradores)
        Dono       = $sid.Sistema
        Direta     = $true
        Grant      = @(
            "*$($sid.Todos):RX"
            "*$($sid.Sistema):(OI)(CI)F"
            "*$($sid.Administradores):(OI)(CI)F"
            "*$($sid.Usuarios):RX"
        )
        GrantExtra = @(
            "*$($sid.Todos):(OI)(CI)(IO)RX"
            "*$($sid.Usuarios):(OI)(CI)(IO)RX"
        )
        Aces       = @(
            @{ Sid = $sid.Sistema;         Rights = $F;  Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F;  Rotulo = 'Administradores com controle total' }
            @{ Sid = $sid.Usuarios;        Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
            @{ Sid = $sid.Todos;           Rights = $RX; Rotulo = 'Todos podendo ler e executar' }
        )
    }
    # Users\Public é a pasta compartilhada: quem entrou na máquina de verdade (INTERATIVO, LOTE,
    # SERVIÇO) pode criar e apagar dentro dela, e é por isso que ela tem ACE para esses três e não
    # para 'Usuários'. '(M,DC)' é modificar mais apagar subpasta; '(RX,WD,AD)' é ler, executar e
    # criar, sem poder alterar o que já está lá.
    $itens += @{
        Path       = (Join-Path $raiz 'Users\Public')
        Nome       = 'Users\Public'
        Donos      = @($sid.Sistema, $sid.Administradores)
        Dono       = $sid.Sistema
        Direta     = $true
        Grant      = @(
            "*$($sid.Lote):(RX,WD,AD)"
            "*$($sid.Interativo):(RX,WD,AD)"
            "*$($sid.Servico):(RX,WD,AD)"
            "*$($sid.Sistema):(OI)(CI)F"
            "*$($sid.Administradores):(OI)(CI)F"
        )
        GrantExtra = @(
            "*$($sid.Criador):(OI)(CI)(IO)F"
            "*$($sid.Lote):(OI)(CI)(IO)(M,DC)"
            "*$($sid.Interativo):(OI)(CI)(IO)(M,DC)"
            "*$($sid.Servico):(OI)(CI)(IO)(M,DC)"
        )
        Aces       = @(
            @{ Sid = $sid.Sistema;         Rights = $F; Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F; Rotulo = 'Administradores com controle total' }
        )
    }
    if (-not [string]::IsNullOrWhiteSpace($perfil)) {
        $aces = @(
            @{ Sid = $sid.Sistema;         Rights = $F; Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F; Rotulo = 'Administradores com controle total' }
        )
        # Sem o SID da identidade atual (conta de serviço, token estranho) a linha do dono da pasta
        # some da conferência em vez de virar uma diferença que ninguém consegue explicar.
        if (-not [string]::IsNullOrWhiteSpace($meu)) {
            $aces += @{ Sid = $meu; Rights = $F; Rotulo = 'o usuário atual com controle total' }
        }
        $itens += @{
            Path       = $perfil
            Nome       = "Pasta do usuário atual ($perfil)"
            Donos      = @($sid.Sistema, $sid.Administradores, $meu)
            Dono       = $meu
            Direta     = $false
            Grant      = @()
            GrantExtra = @()
            Aces       = $aces
        }
    }
    return @($itens)
}

function Compare-WinForgeAclExpected {
    <#
    .SYNOPSIS
        Compara uma lista de permissões contra o padrão esperado e devolve as diferenças, em texto.
    .DESCRIPTION
        Função pura: recebe o objeto de segurança já lido e a linha da tabela, não abre arquivo
        nenhum. É o que permite provar "acusa ACE faltando" e "acusa dono errado" com objetos
        montados na memória, sem estragar as permissões da máquina de quem compila para depois
        consertá-las.

        A comparação é por SID dos dois lados. A identidade de uma ACE chega como NTAccount quando o
        SID traduz e como SecurityIdentifier quando não - por isso a tradução explícita, e por isso
        uma ACE cuja identidade não traduz para SID é PULADA em vez de derrubar a conferência.

        As ACEs de PERMISSÃO de um mesmo SID são somadas antes de comparar. Elas costumam vir em
        pares - uma efetiva na própria pasta e uma herdável de somente herança para o que nascer
        abaixo - e cada uma sozinha é um pedaço do direito.

        ACE de NEGAÇÃO é diferença, qualquer uma. Nenhuma das oito pastas conferidas tem negação no
        padrão de fábrica, e a negação VENCE a permissão: uma linha 'Deny Todos:(OI)(CI)F' plantada
        em C:\Users tranca o disco inteiro sem tirar uma única ACE de permissão da lista. Somar só
        as permissões deixaria essa pasta passar como 'padrão' - que é exatamente o sintoma que
        estes três botões existem para explicar.
    .OUTPUTS
        Vetor de textos, vazio quando está tudo no padrão.
    #>
    param(
        [Parameter(Mandatory)]$Acl,
        [Parameter(Mandatory)][hashtable]$Expected
    )

    $dif = New-Object System.Collections.Generic.List[string]

    $dono = $null
    try { $dono = $Acl.GetOwner([System.Security.Principal.SecurityIdentifier]) } catch { $dono = $null }
    $donos = @($Expected.Donos | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($null -eq $dono) {
        $dif.Add('o dono não pôde ser lido')
    } elseif ($donos.Count -and ($donos -notcontains [string]$dono.Value)) {
        $dif.Add("dono '$(Get-WinForgeAclName -Sid ([string]$dono.Value))' fora do padrão (esperado $((@($donos | ForEach-Object { Get-WinForgeAclName -Sid ([string]$_) })) -join ' ou '))")
    }

    $mascaras = @{}
    foreach ($ace in @($Acl.Access)) {
        $s = $ace.IdentityReference
        try {
            if ($s -isnot [System.Security.Principal.SecurityIdentifier]) { $s = $s.Translate([System.Security.Principal.SecurityIdentifier]) }
        } catch { $s = $null }
        $chave = if ($null -eq $s) { '' } else { [string]$s.Value }
        if ([string]$ace.AccessControlType -ne 'Allow') {
            $quem = if ([string]::IsNullOrWhiteSpace($chave)) { [string]$ace.IdentityReference } else { "$(Get-WinForgeAclName -Sid $chave) [$chave]" }
            $dif.Add("negação de acesso para $quem ($($ace.FileSystemRights)) - não existe no padrão e vence qualquer permissão")
            continue
        }
        if ([string]::IsNullOrWhiteSpace($chave)) { continue }
        $mascaras[$chave] = ([long]$mascaras[$chave]) -bor (ConvertTo-WinForgeAclMask -Rights ([int]$ace.FileSystemRights))
    }

    foreach ($esp in @($Expected.Aces)) {
        $chave = [string]$esp.Sid
        if ([string]::IsNullOrWhiteSpace($chave)) { continue }
        $exigido = ConvertTo-WinForgeAclMask -Rights ([int]$esp.Rights)
        $tem = [long]$mascaras[$chave]
        if (($tem -band $exigido) -ne $exigido) {
            $dif.Add("falta $($esp.Rotulo) [$chave]")
        }
    }
    return @($dif)
}

function Get-WinForgeAclDenySid {
    <#
    .SYNOPSIS
        Quais dos SIDs procurados têm ACE de NEGAÇÃO nesta lista de permissões. Função pura.
    .DESCRIPTION
        A restauração precisa saber disto antes de conceder: '/grant' ADICIONA permissão e não tira
        negação, e a negação vence. Numa pasta com 'Deny Todos:F' a fase de concessão termina com
        código 0, a lista fica com as ACEs certas e o acesso continua negado - o pior resultado
        possível, porque parece que funcionou.

        Só se procura pelos SIDs pedidos, e o '/remove:d' só roda quando algum deles aparece:
        apagar negação que ninguém conferiu é decidir por configuração legítima de outra pessoa.
    .OUTPUTS
        Vetor com os SIDs (texto) que têm negação, na ordem em que foram pedidos. Vazio quando não
        há nenhuma.
    #>
    param(
        [Parameter(Mandatory)]$Acl,
        [Parameter(Mandatory)][string[]]$Sids
    )

    $achados = @{}
    foreach ($ace in @($Acl.Access)) {
        if ([string]$ace.AccessControlType -eq 'Allow') { continue }
        $s = $ace.IdentityReference
        try {
            if ($s -isnot [System.Security.Principal.SecurityIdentifier]) { $s = $s.Translate([System.Security.Principal.SecurityIdentifier]) }
        } catch { continue }
        $achados[[string]$s.Value] = $true
    }
    return @($Sids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and $achados.ContainsKey([string]$_) } | ForEach-Object { [string]$_ })
}

function Get-WinForgeAclReport {
    <#
    .SYNOPSIS
        Dono e lista de permissões das pastas do sistema, com as diferenças em relação ao padrão do
        Windows e um veredito no fim. SÓ LÊ.
    .DESCRIPTION
        O botão que se clica ANTES de qualquer reparo, e o que se clica DEPOIS para conferir. Não
        altera nada: a leitura é Get-Acl, que não pede elevação para as pastas do sistema.

        Pasta que não existe (Program Files (x86) numa instalação de 32 bits, por exemplo) sai como
        'não existe nesta máquina' e NÃO conta como diferença. Pasta que existe e não deixa ler a
        lista conta: a verificação só tem uma defesa, que é olhar, e o que não pôde ser olhado não é
        um "está tudo bem".
    .PARAMETER AsObject
        Devolve @{ Text; Differences; Items } em vez do texto. É o que o -SelfTest usa para cobrar o
        veredito como número; o botão recebe o texto, que é o que a janela de saída mostra.
    .OUTPUTS
        Texto pronto para a janela, ou o hashtable com -AsObject.
    #>
    param([switch]$AsObject)

    $linhas = New-Object System.Collections.Generic.List[string]
    $itens = @()
    $total = 0

    $linhas.Add('Permissões das pastas do sistema, comparadas com o padrão do Windows.')
    $linhas.Add('A comparação é por SID, então ela vale em qualquer idioma do Windows.')

    foreach ($esp in @(Get-WinForgeAclExpected)) {
        $linhas.Add('')
        $linhas.Add("$($esp.Nome)")
        $linhas.Add('-' * 78)
        if (-not (Test-Path -LiteralPath $esp.Path)) {
            $linhas.Add('  Não existe nesta máquina.')
            $itens += @{ Path = $esp.Path; Nome = $esp.Nome; Differences = @(); Missing = $true; OwnerOk = $true }
            continue
        }
        $lista = $null
        try { $lista = Get-Acl -LiteralPath $esp.Path -ErrorAction Stop } catch { $lista = $null }
        if ($null -eq $lista) {
            $linhas.Add('  A lista de permissões não pôde ser lida.')
            $total++
            $itens += @{ Path = $esp.Path; Nome = $esp.Nome; Differences = @('a lista de permissões não pôde ser lida'); Missing = $false; OwnerOk = $true }
            continue
        }

        $dono = $null
        try { $dono = $lista.GetOwner([System.Security.Principal.SecurityIdentifier]) } catch { $dono = $null }
        # O '/setowner' da restauração só roda quando o dono está fora da lista aceita: trocar o
        # dono de uma pasta que já está no padrão é mexer onde não havia problema.
        $donoOk = $false
        if ($dono) {
            $aceitos = @($esp.Donos | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $donoOk = ((-not $aceitos.Count) -or ($aceitos -contains [string]$dono.Value))
        }
        $linhas.Add("  Dono: $(if ($dono) { "$(Get-WinForgeAclName -Sid ([string]$dono.Value)) [$($dono.Value)]" } else { 'não pôde ser lido' })")
        foreach ($ace in @($lista.Access)) {
            $s = $ace.IdentityReference
            try {
                if ($s -isnot [System.Security.Principal.SecurityIdentifier]) { $s = $s.Translate([System.Security.Principal.SecurityIdentifier]) }
            } catch { }
            $linhas.Add("  $($ace.AccessControlType) $(Get-WinForgeAclName -Sid ([string]$s)) : $($ace.FileSystemRights) | herança $($ace.InheritanceFlags)/$($ace.PropagationFlags)")
        }
        $dif = @(Compare-WinForgeAclExpected -Acl $lista -Expected $esp)
        if ($dif.Count -eq 0) {
            $linhas.Add('  -> padrão')
        } else {
            foreach ($d in $dif) { $linhas.Add("  -> DIFERENÇA: $d") }
            $total += $dif.Count
        }
        $itens += @{ Path = $esp.Path; Nome = $esp.Nome; Differences = @($dif); Missing = $false; OwnerOk = $donoOk }
    }

    $linhas.Add('')
    $linhas.Add('=' * 78)
    if ($total -eq 0) {
        $linhas.Add('Veredito: padrão. Nenhuma diferença encontrada nas pastas conferidas.')
    } else {
        $linhas.Add("Veredito: $total diferença(s) em relação ao padrão do Windows.")
        $linhas.Add('O botão "Permissões do disco C: - Restaurar padrões" desfaz esse estrago; ele guarda um backup antes de mexer em qualquer coisa.')
    }
    $texto = ($linhas -join "`r`n")
    if ($AsObject) { return @{ Text = $texto; Differences = [int]$total; Items = @($itens) } }
    return $texto
}

function Get-WinForgeAclBackupRoot {
    <#
    .SYNOPSIS
        Pasta dos backups de permissões (%ProgramData%\WinForge\acl-backup). -Root existe para o
        -SelfTest não escrever em %ProgramData%.
    .DESCRIPTION
        A base é Get-WinForgeMachineDataRoot (API de pastas do Windows), a MESMA da pasta de backup
        de servidor e da de downloads, e nunca a variável de ambiente - ver lá o porquê. O caminho é
        normalizado uma vez ([System.IO.Path]::GetFullPath): daqui para baixo todo mundo conta com a
        mesma forma, e é essa forma que a conferência da cadeia de pastas usa.
    .OUTPUTS
        O caminho normalizado.
    #>
    param([string]$Root)

    $alvo = if ($Root) { $Root } else { (Join-Path (Get-WinForgeMachineDataRoot) 'WinForge\acl-backup') }
    try { return [System.IO.Path]::GetFullPath($alvo) } catch { return $alvo }
}

function Confirm-WinForgeAclBackupRoot {
    <#
    .SYNOPSIS
        Garante que a pasta dos backups de permissões existe e é confiável, ANTES de o primeiro
        backup ser gravado.
    .DESCRIPTION
        Mesmas regras e mesmas funções da pasta de downloads: DACL própria sem herança
        (New-WinForgeSnapshotRoot), nenhum ponto de reanálise na cadeia, dono dentro de
        SYSTEM/Administradores, ninguém de fora deles com escrita (Test-WinForgeSnapshotRootTrusted)
        e a ACE herdável de OWNER RIGHTS (Repair-WinForgeSnapshotRootOwnerRight).

        E, como na pasta de downloads, o afrouxamento que a pasta de teste usa NUNCA é passado, nem
        quando -Root vem preenchido. O que sai desta pasta é aplicado por um icacls /restore elevado
        sobre o disco inteiro: se um processo de integridade média da mesma conta puder escrever
        aqui, ele escolhe as permissões do sistema. É o mesmo furo do instalador trocado, com a
        diferença de que aqui o estrago é a máquina inteira.

        Consequência prática: sem elevação a pasta nasce com a identidade atual como dona e esta
        função RECUSA. O backup não acontece e a restauração inteira para, o que é melhor do que
        alterar o disco guardando o desfazer numa pasta que a própria conta reescreve.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Path = <pasta> }.
    #>
    param([string]$Root)

    $dir = Get-WinForgeAclBackupRoot $Root
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-WinForgeSnapshotRoot -Root $dir | Out-Null }
        catch { return @{ Ok = $false; Reason = "não foi possível criar '$dir': $($_.Exception.Message)"; Path = $dir } }
        if (-not (Test-Path -LiteralPath $dir)) { return @{ Ok = $false; Reason = "a pasta '$dir' não pôde ser criada"; Path = $dir } }
    }
    $t = Test-WinForgeSnapshotRootTrusted -Root $dir
    if (-not $t.Trusted) { return @{ Ok = $false; Reason = $t.Reason; Path = $dir } }
    $dono = Repair-WinForgeSnapshotRootOwnerRight -Root $dir
    if (-not $dono.Ok) { return @{ Ok = $false; Reason = "pasta de backup de permissões sem proteção de dono ('$dir'): $($dono.Reason)"; Path = $dir } }
    return @{ Ok = $true; Reason = ''; Path = $dir }
}

function Test-WinForgeAclBackupFile {
    <#
    .SYNOPSIS
        Diz se um arquivo pode ser usado como backup de permissões: dentro da pasta protegida, direto
        nela, e com dono e DACL de backup.
    .DESCRIPTION
        Três perguntas, nesta ordem, e a primeira é a que o índice do backup torna necessária. O
        índice é um arquivo de texto, e o que ele nomeia vira argumento de um /restore elevado: um
        'sub\..\..\Users\Public\meu.txt' plantado nele apontaria para fora da pasta protegida sem
        nenhum caractere suspeito à vista. Por isso o caminho é normalizado e tem de ficar
        DIRETAMENTE na pasta - subpasta também não, porque a conferência de dono e DACL é feita na
        pasta, e uma subpasta pode ter outra.

        A terceira pergunta é Test-WinForgeSnapshotFileTrusted, sem o afrouxamento da pasta de
        teste: dono fora de SYSTEM/Administradores, ACE de escrita para quem não devia ou ponto de
        reanálise recusam o arquivo.
    .OUTPUTS
        @{ Trusted = <bool>; Reason = <string> }.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $completo = ''
    try { $completo = [System.IO.Path]::GetFullPath($Path) } catch { return @{ Trusted = $false; Reason = "caminho inválido: '$Path'" } }
    $raiz = ''
    try { $raiz = ([System.IO.Path]::GetFullPath($Root)).TrimEnd('\') } catch { return @{ Trusted = $false; Reason = "pasta de backup inválida: '$Root'" } }
    if (-not $completo.StartsWith(($raiz + '\'), [StringComparison]::OrdinalIgnoreCase)) {
        return @{ Trusted = $false; Reason = "'$completo' está fora da pasta de backup '$raiz'" }
    }
    $pai = ''
    try { $pai = ([string][System.IO.Path]::GetDirectoryName($completo)).TrimEnd('\') } catch { $pai = '' }
    if ($pai -ne $raiz) { return @{ Trusted = $false; Reason = "'$completo' não está diretamente na pasta de backup '$raiz'" } }
    if (-not (Test-Path -LiteralPath $completo -PathType Leaf)) { return @{ Trusted = $false; Reason = "'$completo' não existe" } }
    return (Test-WinForgeSnapshotFileTrusted -Path $completo)
}

function Get-WinForgeAclSlug {
    <#
    .SYNOPSIS
        Apelido de arquivo INJETIVO para um texto: dois textos diferentes nunca dão o mesmo apelido.
    .DESCRIPTION
        O apelido anterior trocava todo caractere fora de '[A-Za-z0-9._-]' por '_', e isso não é
        injetivo: 'Program Files' e 'Program_Files' viravam o MESMO nome de arquivo. Qualquer
        Usuário Autenticado cria pasta na raiz do disco - é a ACE '(AD)' que a própria fase 3 repõe
        -, então uma pasta 'C:\Program_Files' plantada por um processo SEM elevação sobrescrevia o
        backup de 'C:\Program Files', e o Desfazer devolvia a lista da pasta do invasor no lugar da
        do Windows, calado.

        A regra aqui é a da porcentagem, byte a byte em UTF-8: o que não for '[A-Za-z0-9]' vira
        '%<hex de dois dígitos>'. O '%' também é codificado ('%25'), senão 'a%20b' e 'a b' voltariam
        a colidir. A função é REVERSÍVEL, e é por ser reversível que ela não colide.
    .OUTPUTS
        O apelido.
    #>
    param([string]$Text)

    if ($null -eq $Text) { $Text = '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in [System.Text.Encoding]::UTF8.GetBytes([string]$Text)) {
        if (($b -ge 0x61 -and $b -le 0x7A) -or ($b -ge 0x41 -and $b -le 0x5A) -or ($b -ge 0x30 -and $b -le 0x39)) { [void]$sb.Append([char]$b) }
        else { [void]$sb.AppendFormat('%{0:X2}', $b) }
    }
    return $sb.ToString()
}

function Get-WinForgeAclFolderSecurity {
    <#
    .SYNOPSIS
        A lista de permissões (SDDL) e o dono de UMA pasta. Só lê.
    .DESCRIPTION
        É o backup da pasta EM SI, e existe porque o 'icacls /save' não serve para isso. Medido, com
        elevação, numa pasta de %TEMP%: 'icacls <pasta>\ /save f /C' grava a entrada da própria
        pasta com o NOME VAZIO, e 'icacls <pasta>\ /restore f /C /L' NÃO aplica essa entrada - ele
        monta o caminho '<pasta>\<sddl>', responde "arquivo não encontrado" e a lista alterada
        continua alterada. O '/save' desfaz os FILHOS; a pasta em si só volta por SDDL.

        A DACL sai com '-eq [AccessControlSections]::Access' de propósito: é a seção que o Desfazer
        reaplica. O dono viaja junto, mas separado, porque repô-lo é outra operação e pode falhar
        sozinha (devolver a posse ao TrustedInstaller exige SeRestorePrivilege).
    .OUTPUTS
        @{ Ok; Sddl; Owner; OwnerSid; Reason }.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $r = @{ Ok = $false; Sddl = ''; Owner = ''; OwnerSid = ''; Reason = '' }
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $r.Sddl = [string]$acl.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
        $r.Owner = [string]$acl.Owner
        try { $r.OwnerSid = [string]$acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value } catch { $r.OwnerSid = '' }
        if ([string]::IsNullOrWhiteSpace($r.Sddl)) {
            $r.Reason = "a lista de '$Path' veio vazia"
            return $r
        }
        $r.Ok = $true
    } catch {
        $r.Reason = $_.Exception.Message
    }
    return $r
}

# Quatro medições decidem o desenho de Get-WinForgeAclContentScope, e estão AQUI, fora do corpo, de
# propósito: o SelfTest lê '(Get-Command …).ScriptBlock' e reprova o fonte que cite a sobrecarga
# recursiva de enumeração ou a seção 'All' - escrever esses nomes dentro da função reprovaria
# justamente a função que os evita.
#   1. 'icacls <perfil> /save /T /L' NÃO poda a travessia. O '/L' fala do ALVO de cada item, não do
#      caminho percorrido: com '/T' o icacls desce na junção do mesmo jeito. Foi esse laço -
#      'AppData\Local\Dados de Aplicativos' é junção para 'AppData\Local', o próprio pai - que
#      gravou ~50 GB e travou a máquina de um usuário real. Quem para a recursão é o limite de 63
#      saltos de reparse, não o MAX_PATH.
#   2. '[IO.Directory]::EnumerateFileSystemEntries(<pasta>, <padrão>, AllDirectories)' é PROIBIDO
#      aqui: medido, ele segue ponto de reanálise e cai no mesmo laço. Por isso a caminhada é uma
#      pilha explícita que pergunta os atributos ANTES de empilhar.
#   3. Prefixo '\\?\' em TODA chamada .NET. 'LongPathsEnabled = 1' não é o padrão do Windows: sem o
#      prefixo, um caminho longo dentro do perfil devolve PathTooLongException no PC do usuário, e
#      aqui isso viraria 'Denied' - ou seja, pasta silenciosamente fora do backup.
#   4. 'GetAccessControl([...AccessControlSections]::Access)' e nunca a seção 'All': medido, 'All'
#      inclui a SACL e LANÇA sem SeSecurityPrivilege. 'Access' é também a única seção que o Desfazer
#      reaplica, então guardar mais do que isso seria guardar o que não volta.
function Get-WinForgeAclContentScope {
    <#
    .SYNOPSIS
        Caminha uma árvore de pastas e devolve só as que têm a herança BLOQUEADA, cada uma com o seu
        SDDL. É a caminhada que substitui o 'icacls <perfil> /save /T'. Só lê.
    .DESCRIPTION
        A travessia é uma PILHA explícita - nem recursão, nem a sobrecarga de enumeração que desce
        sozinha. Ponto de reanálise (junção, link simbólico) não é empilhado E não vira entrada. São
        dois problemas diferentes e por isso as duas coisas: não empilhar é o que evita o laço
        infinito; não indexar é o que evita trocar permissão por permissão, porque o .NET lê a ACL
        do ALVO da junção e o 'icacls /restore ... /L' devolveria essa ACL ao LINK.

        O filtro é AreAccessRulesProtected, não "tem ACE explícita": a restauração liga a herança
        com '/inheritance:e', que só altera item com herança bloqueada. O guardado tem de ser
        exatamente o alterado, senão o Desfazer cobre um conjunto e a restauração mexe em outro.

        'Denied' conta o GetAccessControl, a enumeração dos filhos e o GetAttributes que LANÇA. Em
        pasta apenas negada o GetAttributes não lança (medido), e é por isso que não é ele quem
        detecta negação; mas quando ele lança não se sabe se o item é ponto de reanálise, e seguir
        adiante seria descer justamente no que não se conseguiu identificar - então falha FECHADA.
        Denied > 0 muda o veredito do chamador - essas pastas não foram copiadas, então também não
        podem ser alteradas.

        Estourar qualquer um dos quatro tetos devolve Ok = $false e Entries VAZIO, nunca o coletado
        até ali: meia cópia é um Desfazer que não desfaz.
    .OUTPUTS
        @{ Ok; Reason; Entries = @(@{ Name; Sddl; Deny }); Scanned; Reparse; Denied; DeniedPaths;
        Deny; Bytes; Seconds }. 'Name' é o caminho RELATIVO à pasta acima de -Path, com a folha de
        -Path na frente ('rafa_', 'rafa_\AppData', ...), que é a forma que o 'icacls <pasta acima>
        /restore' espera. O 'Deny' de cada entrada diz se AQUELA pasta tem ACE de negação; o 'Deny'
        de fora conta quantas são.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$IncludeFiles,
        [int]$MaxItems = 20000,
        [int]$MaxBytes = 4194304,
        [int]$MaxDepth = 32,
        [int]$MaxSeconds = 90
    )

    $frase = 'A cópia das permissões não ficou pronta em {0} segundos. Sem ela não haveria como desfazer, então nada foi alterado. Tente de novo com o computador recém-ligado.'
    # O SDDL tem quatro formas de ACE de negação: 'D' (deny), 'OD' (object deny), 'XD' (callback
    # deny) e 'ZD' (object callback deny). '\(D;' sozinho deixava passar as três últimas. O NTFS não
    # produz ACE de objeto, então o SelfTest pesca este literal pelo marcador de fim de linha e o
    # prova em SDDL sintético - o marcador tem de continuar onde está.
    $negacao = '\([OXZ]?D;'   # SDDL-NEGACAO
    $r = @{ Ok = $false; Reason = ''; Entries = @(); Scanned = 0; Reparse = 0; Denied = 0; DeniedPaths = @(); Deny = 0; Bytes = 0; Seconds = 0.0 }
    $base = [string](Split-Path -Parent ([string]$Path))          # a pasta ACIMA: os nomes são relativos a ela
    $longo = { param($p) if ($p -like '\\?\*') { $p } else { '\\?\' + $p } }
    $pilha = New-Object System.Collections.Generic.Stack[object]
    $pilha.Push(@{ Path = [string]$Path; Depth = 0 })
    $relogio = [System.Diagnostics.Stopwatch]::StartNew()
    $itens = New-Object System.Collections.Generic.List[object]
    $bytes = 0
    while ($pilha.Count -gt 0) {
        if ($relogio.Elapsed.TotalSeconds -gt $MaxSeconds) { $r.Reason = ($frase -f $MaxSeconds); break }
        $no = $pilha.Pop()
        # GetAttributes ANTES de empilhar, e sobre o caminho longo: é a única pergunta que separa
        # pasta de ponto de reanálise sem abrir o item. Em pasta apenas NEGADA ele não lança
        # (medido) - não é ele quem detecta negação, é o GetAccessControl abaixo. Mas quando ele
        # LANÇA o item é desconhecido, e seguir adiante seria descer justamente no que não se
        # conseguiu identificar: falha FECHADA, conta em Denied e não desce. Não é hipótese - sem o
        # prefixo '\\?\' uma pasta de nome com espaço no fim cai exatamente aqui.
        $attr = $null
        try { $attr = [IO.File]::GetAttributes((& $longo $no.Path)) } catch { $attr = $null }
        if ($null -eq $attr) {
            $r.Denied++
            if ($r.DeniedPaths.Count -lt 200) { $r.DeniedPaths += [string]$no.Path }
            continue
        }
        # O ponto de reanálise conta em Reparse e NÃO em Scanned: são duas grandezas diferentes.
        # 'Scanned' só sobe para pasta que a caminhada de fato visitou.
        if ($attr -band [IO.FileAttributes]::ReparsePoint) { $r.Reparse++; continue }
        $r.Scanned++
        $seg = $null
        try {
            $seg = (New-Object System.IO.DirectoryInfo ((& $longo $no.Path))).GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        } catch {
            $r.Denied++
            if ($r.DeniedPaths.Count -lt 200) { $r.DeniedPaths += [string]$no.Path }
            continue
        }
        if ($seg.AreAccessRulesProtected) {
            $sddl = [string]$seg.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
            # A negação é detectada UMA vez e viaja com a entrada. O chamador precisa saber QUAIS
            # entradas negam, e não só quantas: é nelas - e só nelas - que a ordem canônica do .NET
            # muda o acesso, e é nelas que o texto tem de sair do próprio icacls. Um segundo
            # detector no chamador seria um segundo padrão para manter em dia com este.
            $negado = [bool]($sddl -match $negacao)
            if ($negado) { $r.Deny++ }
            $nome = [string]$no.Path
            if ($nome.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { $nome = $nome.Substring($base.TrimEnd('\').Length + 1) }
            $itens.Add(@{ Name = $nome; Sddl = $sddl; Deny = $negado })
            $bytes += [System.Text.Encoding]::Unicode.GetByteCount($nome + $sddl) + 8
            if ($itens.Count -gt $MaxItems) { $r.Reason = "A cópia das permissões passou de $MaxItems pastas. Nada foi alterado."; break }
            if ($bytes -gt $MaxBytes) { $r.Reason = "A cópia das permissões passou de $MaxBytes bytes. Nada foi alterado."; break }
        }
        # Duas causas, duas frases. Árvore funda de verdade e laço de atalhos estouram o MESMO teto,
        # e responder a mesma coisa nas duas esconde justamente o defeito que esta função existe
        # para evitar. O sinal do laço é a proporção: atalho de pasta é minoria numa árvore real e
        # vira maioria quando a caminhada está girando.
        if ($no.Depth -ge $MaxDepth) {
            if ($r.Reparse -gt 0 -and ($r.Reparse * 2) -ge $r.Scanned) {
                $r.Reason = "A cópia das permissões passou de $MaxDepth níveis de pasta, e $($r.Reparse) dos $($r.Scanned) itens vistos eram atalhos de pasta - isso é sinal de um laço de atalhos, não de uma árvore funda. Nada foi alterado."
            } else {
                $r.Reason = "A cópia das permissões passou de $MaxDepth níveis de pasta. Nada foi alterado."
            }
            break
        }
        try {
            foreach ($filho in [IO.Directory]::EnumerateDirectories((& $longo $no.Path))) {
                $pilha.Push(@{ Path = ([string]$filho -replace '^\\\\\?\\', ''); Depth = $no.Depth + 1 })
            }
            if ($IncludeFiles) { foreach ($arq in [IO.Directory]::EnumerateFiles((& $longo $no.Path))) { $r.Scanned++ } }
        } catch {
            $r.Denied++
            if ($r.DeniedPaths.Count -lt 200) { $r.DeniedPaths += [string]$no.Path }
        }
    }
    $r.Bytes = $bytes
    $r.Seconds = [math]::Round($relogio.Elapsed.TotalSeconds, 3)
    # A lista só sai inteira. Teto estourado deixa Entries vazio de propósito - §1.6 não tem
    # "continuar mesmo assim", porque meia cópia reintroduz o Desfazer que não desfaz.
    if ([string]::IsNullOrEmpty([string]$r.Reason)) {
        $r.Entries = $itens.ToArray()
        $r.Ok = $true
    }
    return $r
}

function Test-WinForgeAclAbsolutePath {
    <#
    .SYNOPSIS
        Diz se um caminho é ABSOLUTO de verdade - com disco ou servidor na frente. Função pura, só
        texto: não toca no disco e não pergunta se o caminho existe.
    .DESCRIPTION
        Existe porque '[System.IO.Path]::IsPathRooted' responde OUTRA pergunta, e as duas portas que
        tocam o arquivo de backup faziam a pergunta errada com a frase certa. MEDIDO: 'C:acl.txt'
        (relativo ao diretório corrente DAQUELE disco) e '\acl.txt' (relativo ao disco corrente) são
        "rooted", passavam pela porta que diz "precisa ser absoluto", viravam '\\?\C:acl.txt' e
        morriam adiante em "Não foi possível localizar o arquivo". Falha FECHADA - medido, nada é
        gravado nesse caminho -, mas a mensagem culpava o disco por um caminho que o próprio
        programa montou, e é isso que se conserta aqui.

        Quem separa os casos é a RAIZ, e a prova é GetFullPath sobre ela: 'C:\' e '\\servidor\share'
        resolvem para si mesmas, enquanto 'C:', '\' e '' resolvem para onde o PROCESSO está - que é
        exatamente o que "absoluto" exclui.

        A comparação é só sobre a RAIZ, e isso também foi medido: GetFullPath sobre o caminho
        INTEIRO normaliza - come o ponto final de uma pasta chamada 'cache.' e resolve '..'.
        Recusar por isso seria recusar justamente o caminho que o prefixo '\\?\' existe para
        atender, e o backup de permissões vive em caminho longo dentro do perfil.

        Um caminho que JÁ chega com '\\?\' é aceito pela raiz que ele declara: o prefixo é a forma
        de dizer ao Windows "este caminho é literal, não normalize". Quem chama nunca o monta antes
        desta porta - os dois chamadores põem o prefixo DEPOIS dela.
    .OUTPUTS
        $true ou $false. Caminho vazio é $false.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $raiz = ''
    try { $raiz = [string][System.IO.Path]::GetPathRoot([string]$Path) } catch { return $false }
    if ([string]::IsNullOrEmpty($raiz)) { return $false }
    try { return ([string][System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($raiz)) -eq $raiz) } catch { return $false }
}

function Test-WinForgeAclNetworkPath {
    <#
    .SYNOPSIS
        Diz se um caminho é de REDE. Função pura, só texto: não toca no disco, não resolve nome e
        não pergunta nada à rede.
    .DESCRIPTION
        Existe porque Test-WinForgeAclAbsolutePath responde OUTRA pergunta e ACEITA caminho de rede -
        '\\servidor\compartilhada' é absoluto de verdade, e para o que aquela função protege isso
        está certo. Só que o backup de permissões tem uma regra a mais: o que sai desta máquina volta
        por um '/restore' elevado sobre o perfil inteiro, e um compartilhamento pode ser outro entre
        o backup e o Desfazer sem que o caminho mude. A escolha do destino já recusava rede; o
        Desfazer e a limpeza, que recebem o caminho pronto do índice, não - e era a única
        conferência estrutural deles. Achado do revisor da Tarefa 7.

        Por TEXTO, e antes de qualquer pergunta ao disco, porque é isso que funciona com um servidor
        que não existe: DriveInfo sobre '\\servidor\share' lança, e a recusa sairia falando de disco
        em vez de rede. O prefixo '\\?\' é retirado antes da pergunta - ele é só a forma de dizer ao
        Windows "não normalize" -, e a forma de rede dele é '\\?\UNC\<servidor>\<share>'.
    .OUTPUTS
        $true ou $false. Caminho vazio é $false.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $texto = [string]$Path
    if ([string]::IsNullOrWhiteSpace($texto)) { return $false }
    $tinhaPrefixo = $false
    if ($texto.StartsWith('\\?\', [StringComparison]::Ordinal)) { $texto = $texto.Substring(4); $tinhaPrefixo = $true }
    if ($texto.StartsWith('\\', [StringComparison]::Ordinal)) { return $true }
    if ($tinhaPrefixo -and $texto.StartsWith('UNC\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Test-WinForgeAclContentRoot {
    <#
    .SYNOPSIS
        Diz se a pasta escolhida pelo usuário pode receber o arquivo de permissões do CONTEÚDO do
        perfil. Só lê: não cria pasta, não grava nada e não pergunta nada a ninguém.
    .DESCRIPTION
        O backup do conteúdo é OBRIGATÓRIO, e isso é medida, não opinião: filtrado pela caminhada -
        só pasta com a herança bloqueada entra -, ele caiu de 174 MB e 76 segundos para 103,4 KB e
        39 segundos. Não há o que economizar deixando de fazê-lo. O que virou opcional foi o
        DESTINO, e é por isso que esta função existe.

        Dentro de %ProgramData%\WinForge o projeto sabe montar a pasta que o backup precisa - DACL
        própria sem herança, dono Administradores, ninguém de fora de SYSTEM/Administradores com
        escrita (Confirm-WinForgeAclBackupRoot). Fora dela, não sabe: um pen drive não tem lista de
        permissões que o WinForge possa impor. Quem substitui a pasta protegida é o SHA-256 que o
        índice guarda - e o índice continua DENTRO dela. Por isso o que se recusa aqui é só o que
        nem o SHA-256 cobriria.

        São sete perguntas, do mais barato para o mais caro, e nenhuma delas é gosto:

        1. ABSOLUTO e não de REDE. A rede é recusada por TEXTO e primeiro: um '\\servidor\share'
           que não existe não tem unidade a consultar, e a recusa tem de falar de rede e não de
           disco. O absoluto é Test-WinForgeAclAbsolutePath, e não 'IsPathRooted': medido,
           'C:pasta' e '\pasta' são "rooted" e resolvem contra o diretório do PROCESSO.
        2. NÃO ser a raiz de um volume. Qualquer Usuário Autenticado cria e renomeia pasta na raiz
           do disco - é a ACE '(AD)' que a própria fase 3 repõe.
        3. DriveFormat igual a 'NTFS'. exFAT e FAT32 NÃO guardam lista de permissão nenhuma e NÃO
           DÃO ERRO ao tentar: o arquivo sairia mudo e o Desfazer aplicaria lixo, calado. Esta é a
           recusa que mais se parece com implicância e é a que mais faz falta.
        4. DriveType 'Fixed' ou 'Removable'. Unidade de rede cai na recusa 1 por outro caminho; CD
           e disco de memória não sobrevivem à reinicialização que separa a restauração do Desfazer.
        5. Nem DENTRO nem CONTENDO o perfil, as duas pontas. Dentro, a fase 5 liga a herança em
           cima do próprio backup; contendo, o arquivo fica num caminho que o /restore percorre.
        6. Nenhum PONTO DE REANÁLISE na cadeia, da pasta escolhida até a raiz do volume. Com uma
           junção no meio, o caminho conferido e o caminho gravado são dois - e quem planta a junção
           escolhe o segundo.
        7. ESPAÇO LIVRE com folga. Backup pela metade é o botão Desfazer prometendo o que não tem.

        O caminho vem SEMPRE do seletor de pasta do shell (Show-WinForgeAclBackupDestination), e
        nunca de variável de ambiente: a base de confiança deste projeto é
        [Environment]::GetFolderPath, e um destino escolhido à mão não tem base nenhuma - ele tem de
        ser conferido, que é exatamente o que acontece aqui.
    .PARAMETER ProfilePath
        A pasta do usuário. Vem de quem chama e não é adivinhada aqui: no -SelfTest ela é uma pasta
        de %TEMP%, e a função não pode ter opinião sobre qual perfil é o certo.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Path = <caminho normalizado>; Warning = <string> }.
        'Warning' só vem preenchido quando a pasta é ACEITA - é o que o usuário precisa ler antes de
        confirmar, e em cima de uma recusa não teria a quem servir.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ProfilePath
    )

    $r = @{ Ok = $false; Reason = ''; Path = [string]$Path; Warning = '' }
    $bruto = [string]$Path
    if ([string]::IsNullOrWhiteSpace($bruto)) {
        $r.Reason = 'Nenhuma pasta foi escolhida. O destino precisa ser um caminho absoluto, com o disco na frente.'
        return $r
    }
    # ---- 1. Rede, por TEXTO e antes de tudo (Test-WinForgeAclNetworkPath, a mesma porta que o
    # Desfazer e a limpeza usam sobre o caminho já gravado no índice).
    if (Test-WinForgeAclNetworkPath -Path $bruto) {
        $r.Reason = "'$bruto' é uma pasta de rede. O backup das permissões não sai para a rede: o arquivo volta por um /restore elevado sobre o perfil inteiro, e um compartilhamento pode ser outro entre o backup e o Desfazer sem que o caminho mude."
        return $r
    }
    # ---- 1b. Absoluto de verdade.
    if (-not (Test-WinForgeAclAbsolutePath -Path $bruto)) {
        $r.Reason = "'$bruto' não é um caminho absoluto. O destino do backup precisa ser absoluto, com o disco na frente: 'C:pasta' e '\pasta' resolvem contra o diretório do processo e gravariam em outro lugar."
        return $r
    }
    $completo = ''
    try { $completo = [string][System.IO.Path]::GetFullPath($bruto) }
    catch {
        $r.Reason = "'$bruto' não é um caminho válido: $($_.Exception.Message)"
        return $r
    }
    $r.Path = $completo
    $semBarra = $completo.TrimEnd('\')
    $volume = ''
    try { $volume = [string][System.IO.Path]::GetPathRoot($completo) } catch { $volume = '' }
    if ([string]::IsNullOrWhiteSpace($volume)) {
        $r.Reason = "'$completo' não diz em que volume está."
        return $r
    }
    $raizVolume = $volume.TrimEnd('\')
    # ---- 2. A raiz do volume.
    if ($semBarra.Equals($raizVolume, [StringComparison]::OrdinalIgnoreCase)) {
        $r.Reason = "'$completo' é a raiz do disco. O backup não fica na raiz de um volume: qualquer Usuário Autenticado cria e renomeia pasta ali - é a ACE '(AD)' que a própria restauração repõe. Escolha uma subpasta."
        return $r
    }
    # ---- 3 e 4. O sistema de arquivos e o tipo da unidade, na MESMA leitura e os dois dentro do
    # try: '[string]$obj.Propriedade' sobre propriedade que LANÇA devolve '' em silêncio (medido), e
    # '' aqui viraria "não sei" em vez de erro - que é justamente o caso em que a recusa importa.
    $formato = ''
    $tipo = ''
    try {
        $unidade = New-Object System.IO.DriveInfo ($volume)
        if ($unidade.IsReady) {
            $formato = [string]$unidade.DriveFormat
            $tipo = [string]$unidade.DriveType
        }
    } catch {
        $formato = ''
        $tipo = ''
    }
    if ([string]::IsNullOrWhiteSpace($formato) -or [string]::IsNullOrWhiteSpace($tipo)) {
        $r.Reason = "o volume '$volume' não respondeu qual é o sistema de arquivos dele nem que tipo de unidade é. Sem essa resposta não há como garantir que a lista de permissões seria guardada, então a pasta é recusada."
        return $r
    }
    if ($formato -ne 'NTFS') {
        $r.Reason = "o volume '$volume' está formatado em $formato, e não em NTFS. exFAT e FAT32 não guardam lista de permissão nenhuma e NÃO dão erro ao tentar: o arquivo sairia mudo e o Desfazer aplicaria lixo."
        return $r
    }
    if ($tipo -ne 'Fixed' -and $tipo -ne 'Removable') {
        $r.Reason = "o volume '$volume' é do tipo $tipo. O backup só vai para disco interno (Fixed) ou removível (Removable): unidade de rede, CD e disco de memória não sobrevivem à reinicialização que separa a restauração do Desfazer."
        return $r
    }
    # ---- 5. O perfil, nas duas pontas.
    $perfil = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$ProfilePath)) {
        try { $perfil = ([string][System.IO.Path]::GetFullPath([string]$ProfilePath)).TrimEnd('\') } catch { $perfil = '' }
    }
    if (-not [string]::IsNullOrWhiteSpace($perfil)) {
        if ($semBarra.Equals($perfil, [StringComparison]::OrdinalIgnoreCase) -or $semBarra.StartsWith(($perfil + '\'), [StringComparison]::OrdinalIgnoreCase)) {
            $r.Reason = "'$completo' está dentro do perfil '$perfil'. A fase 5 liga a herança em cada pasta de lá dentro: o backup seria alterado pela mesma alteração que ele existe para desfazer."
            return $r
        }
        if ($perfil.StartsWith(($semBarra + '\'), [StringComparison]::OrdinalIgnoreCase)) {
            $r.Reason = "'$completo' contém o perfil '$perfil'. Pelo mesmo motivo da recusa de dentro: o arquivo ficaria num caminho que a restauração percorre."
            return $r
        }
    }
    # ---- 6. A cadeia, da pasta escolhida até a raiz do volume. Prefixo '\\?\' em TODA chamada
    # .NET, a mesma regra da caminhada da fase 2: 'LongPathsEnabled = 1' não é o padrão do Windows.
    $longo = { param($p) if ($p -like '\\?\*') { $p } else { '\\?\' + $p } }
    $atual = $semBarra
    $passos = 0
    while (-not [string]::IsNullOrWhiteSpace($atual) -and $passos -lt 64) {
        $passos++
        if ($atual.Equals($raizVolume, [StringComparison]::OrdinalIgnoreCase)) { break }
        $attr = $null
        try { $attr = [IO.File]::GetAttributes((& $longo $atual)) } catch { $attr = $null }
        if ($null -eq $attr) {
            # Só a pasta ESCOLHIDA precisa existir. Um pai ilegível no meio do caminho não é recusa:
            # o que se persegue aqui é a junção, e junção ilegível não existe - ela é lida pelo
            # atributo, não pelo conteúdo.
            if ($atual.Equals($semBarra, [StringComparison]::OrdinalIgnoreCase)) {
                $r.Reason = "a pasta '$completo' não existe ou não pôde ser lida. Escolha uma pasta que já esteja no disco."
                return $r
            }
        } else {
            if ($atual.Equals($semBarra, [StringComparison]::OrdinalIgnoreCase) -and -not ($attr -band [IO.FileAttributes]::Directory)) {
                $r.Reason = "'$completo' não é uma pasta."
                return $r
            }
            if ($attr -band [IO.FileAttributes]::ReparsePoint) {
                $r.Reason = "'$atual' é um ponto de reanálise (junção ou link) no caminho de '$completo'. O caminho conferido e o caminho gravado seriam dois, e quem planta a junção escolhe o segundo."
                return $r
            }
        }
        $pai = ''
        try { $pai = [string](Split-Path -Parent $atual) } catch { $pai = '' }
        if ([string]::IsNullOrWhiteSpace($pai)) { break }
        $pai = $pai.TrimEnd('\')
        if ($pai.Equals($atual, [StringComparison]::OrdinalIgnoreCase)) { break }
        $atual = $pai
    }
    # ---- 7. O espaço livre, com folga. O arquivo medido tem 103,4 KB; o teto aqui é de 64 MB
    # porque quem escolhe um destino externo o escolhe uma vez e restaura muitas, e um volume sem
    # folga nenhuma é um backup pela metade esperando acontecer.
    $esp = Test-WinForgeAclFreeSpace -Path $completo -Bytes ([long]67108864)
    if (-not $esp.Ok) {
        $r.Reason = [string]$esp.Reason
        return $r
    }

    $r.Ok = $true
    $r.Warning = 'Fora da pasta do WinForge, qualquer conta de administrador — desta máquina ou de outra onde o disco for ligado — pode ler, alterar ou apagar este arquivo. O WinForge percebe a alteração e recusa restaurar, mas não recupera arquivo apagado. Em pen drive ou HD externo: disco desligado na hora de desfazer é a mesma coisa que não ter backup.'
    return $r
}

function Show-WinForgeAclBackupDestination {
    <#
    .SYNOPSIS
        A caixa que pergunta ONDE o backup das permissões vai ficar. Roda na thread da janela, não
        escreve nada em disco e não despacha nada.
    .DESCRIPTION
        A caixa não pergunta SE o backup acontece: ele acontece sempre. Medido, filtrado pela
        caminhada, ele são 103,4 KB e 39 segundos - não há o que economizar deixando de fazê-lo, e
        uma restauração sem Desfazer é o tipo de ajuda que transforma um problema em dois. O que a
        caixa pergunta é ONDE, e a opção de sair da pasta do WinForge nasce DESMARCADA: o lugar
        certo para quase todo mundo é a pasta protegida, e uma caixa pré-marcada treinaria a pessoa
        a confirmar sem ler o aviso que vem junto.

        Ela é chamada do handler do botão, que já roda na thread da janela, e ANTES do
        Invoke-WPFRunspace: perguntar de dentro da runspace exigiria um Dispatcher.Invoke, e o
        resultado da pergunta precisa existir antes de a trava de comando em andamento ser tomada -
        senão o programa inteiro fica sem botões enquanto uma caixa espera alguém ler. O que atravessa
        para a runspace é só o texto do caminho, em $sync.WinForgeAclExternalRoot.

        O seletor é o FolderBrowserDialog do Windows Forms, e não uma caixa de texto: em .NET
        Framework 4.8 o WPF só tem seletor de ARQUIVO, e um caminho digitado à mão seria o mesmo
        que aceitar variável de ambiente - texto de origem desconhecida virando argumento de um
        /restore elevado. O processo nasce STA e o relançamento '-Verb RunAs' preserva isso, que é o
        que o seletor do shell exige.

        A pasta escolhida passa por Test-WinForgeAclContentRoot na hora, com o resultado na tela: o
        usuário descobre que o pen drive é exFAT ali, e não trinta e nove segundos depois.

        A ALTURA acompanha o conteúdo, e a barra de botões fica FORA da rolagem. Medido pelo revisor
        da Tarefa 7 na versão de altura fixa: o conteúdo ocupava 316,7 pixels num cliente de 369,
        sem redimensionar e sem rolar; com a fonte do sistema 50% maior - o tamanho que quem usa
        acessibilidade escolhe - ele ia a 460,2 e a barra com 'Continuar' e 'Cancelar' saía da
        janela, deixando a caixa sem saída. Hoje são três coisas juntas, e nenhuma basta sozinha:
        'SizeToContent = Height' faz a janela crescer com o texto; 'MaxHeight' na área de trabalho
        impede que ela cresça para fora da tela; e a grade de duas linhas deixa o texto rolar sem
        levar os botões junto.
    .PARAMETER NoShow
        Devolve a JANELA sem mostrá-la, em vez da resposta. É o que o -SelfTest usa - mesmo desenho
        de Show-WinForgeOutputWindow e de Show-WinForgeAclCleanupConfirm -, e é assim que a caixa
        desmarcada por padrão, os handlers dela e o lugar da barra são provados sem abrir nada.
    .OUTPUTS
        Com -NoShow, a janela ([System.Windows.Window]). Sem ele,
        @{ Ok = <bool>; External = <bool>; Path = <string>; Warning = <string> }. 'Ok' falso é
        "cancelar": quem chamou não despacha nada. Com 'External' falso o backup vai para a pasta
        protegida de sempre, e 'Path' vem vazio.
    #>
    param([switch]$NoShow)

    # No uso normal o WPF já está carregado desde a montagem da janela principal; o Windows Forms
    # não, e é dele que vem o seletor de pasta do shell.
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')

    $perfil = ''
    try { $perfil = [string][Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) } catch { $perfil = '' }

    # O estado mora numa hashtable porque os handlers abaixo são scriptblocks com closure: fechar
    # sobre uma hashtable deixa eles ESCREVEREM no mesmo objeto; fechar sobre uma variável de valor
    # daria a cada handler uma cópia, e a resposta da caixa voltaria vazia.
    $estado = @{ Ok = $false; External = $false; Path = ''; Warning = '' }

    $fundo = $null
    $frente = $null
    if ($null -ne $sync -and $null -ne $sync.Form) {
        try { $fundo = $sync.Form.Resources['MainBackgroundColor'] } catch { $fundo = $null }
        try { $frente = $sync.Form.Resources['MainForegroundColor'] } catch { $frente = $null }
    }
    if ($null -eq $fundo) { $fundo = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(35, 38, 41)) }
    if ($null -eq $frente) { $frente = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(230, 230, 230)) }

    $janela = New-Object System.Windows.Window
    $janela.Title = 'WinForge - onde guardar o backup das permissões'
    $janela.Width = 640
    # A altura SEGUE o conteúdo, e nunca o contrário: com altura fixa, a fonte grande do sistema
    # empurrava a barra de botões para fora da janela. 'MinHeight' existe só para a caixa não nascer
    # esmagada quando o texto for curto.
    $janela.SizeToContent = [System.Windows.SizeToContent]::Height
    $janela.MinHeight = 260
    # E o teto: sem ele, 'SizeToContent' cresce para fora da tela em fonte muito grande, e aí a barra
    # sai por baixo do mesmo jeito - só que agora sem nem dar para arrastar a janela de volta.
    try { $janela.MaxHeight = [double]([System.Windows.SystemParameters]::WorkArea.Height * 0.9) } catch { $janela.MaxHeight = 900 }
    $janela.Background = $fundo
    # Redimensionável de propósito: em fonte grande o teto acima entra em ação, e quem quiser ver
    # mais texto de uma vez tem de poder esticar.
    $janela.ResizeMode = [System.Windows.ResizeMode]::CanResize
    $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    if ($null -ne $sync -and $null -ne $sync.Form -and $sync.Form.IsVisible) {
        try {
            $janela.Owner = $sync.Form
            $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        } catch { }
    }

    # Duas linhas: o conteúdo rola, a barra não. Numa pilha única, o teto de altura cortaria os
    # botões junto com o texto - e uma caixa modal sem 'Cancelar' visível é uma caixa sem saída.
    $grade = New-Object System.Windows.Controls.Grid
    $grade.Margin = New-Object System.Windows.Thickness 16
    $linhaTexto = New-Object System.Windows.Controls.RowDefinition
    $linhaTexto.Height = New-Object System.Windows.GridLength (1, [System.Windows.GridUnitType]::Star)
    $linhaBarra = New-Object System.Windows.Controls.RowDefinition
    $linhaBarra.Height = [System.Windows.GridLength]::Auto
    $grade.RowDefinitions.Add($linhaTexto)
    $grade.RowDefinitions.Add($linhaBarra)

    $pilha = New-Object System.Windows.Controls.StackPanel

    $novoTexto = {
        param($Conteudo, $Topo)
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = [string]$Conteudo
        $t.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $t.Foreground = $frente
        $t.Margin = New-Object System.Windows.Thickness (0, [int]$Topo, 0, 0)
        return $t
    }.GetNewClosure()

    $pilha.Children.Add((& $novoTexto 'O backup das permissões atuais é sempre feito: sem ele o botão Desfazer não teria o que devolver. Ele ocupa cerca de 100 KB e leva meio minuto.' 0)) | Out-Null
    $pilha.Children.Add((& $novoTexto "Por padrão o arquivo fica na pasta protegida do WinForge, em '$(Get-WinForgeAclBackupRoot)', onde só o SYSTEM e os Administradores escrevem." 10)) | Out-Null

    $caixaExterna = New-Object System.Windows.Controls.CheckBox
    $caixaExterna.Content = 'Guardar o backup das permissões em outro disco'
    $caixaExterna.Foreground = $frente
    $caixaExterna.Margin = New-Object System.Windows.Thickness (0, 16, 0, 0)
    # DESMARCADA. O lugar certo para quase todo mundo é a pasta protegida, e uma caixa que nasce
    # marcada é uma caixa que ninguém lê.
    $caixaExterna.IsChecked = $false
    $pilha.Children.Add($caixaExterna) | Out-Null

    $linhaPasta = New-Object System.Windows.Controls.StackPanel
    $linhaPasta.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $linhaPasta.Margin = New-Object System.Windows.Thickness (0, 10, 0, 0)
    $btnEscolher = New-Object System.Windows.Controls.Button
    $btnEscolher.Content = 'Escolher pasta...'
    $btnEscolher.MinWidth = 130
    $btnEscolher.Padding = New-Object System.Windows.Thickness (10, 4, 10, 4)
    $btnEscolher.IsEnabled = $false
    $linhaPasta.Children.Add($btnEscolher) | Out-Null
    $pilha.Children.Add($linhaPasta) | Out-Null

    $rotuloPasta = & $novoTexto '' 8
    $pilha.Children.Add($rotuloPasta) | Out-Null
    $rotuloAviso = & $novoTexto '' 10
    $pilha.Children.Add($rotuloAviso) | Out-Null

    # A rolagem envolve SÓ o conteúdo, e vai na linha 0.
    $rolagem = New-Object System.Windows.Controls.ScrollViewer
    $rolagem.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $rolagem.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
    $rolagem.Content = $pilha
    [System.Windows.Controls.Grid]::SetRow($rolagem, 0)
    $grade.Children.Add($rolagem) | Out-Null

    $barra = New-Object System.Windows.Controls.StackPanel
    $barra.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $barra.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $barra.Margin = New-Object System.Windows.Thickness (0, 16, 0, 0)
    [System.Windows.Controls.Grid]::SetRow($barra, 1)
    $grade.Children.Add($barra) | Out-Null
    $btnOk = New-Object System.Windows.Controls.Button
    $btnOk.Content = 'Continuar'
    $btnOk.MinWidth = 110
    $btnOk.Padding = New-Object System.Windows.Thickness (10, 4, 10, 4)
    $btnCancelar = New-Object System.Windows.Controls.Button
    $btnCancelar.Content = 'Cancelar'
    $btnCancelar.MinWidth = 110
    $btnCancelar.Margin = New-Object System.Windows.Thickness (8, 0, 0, 0)
    $btnCancelar.Padding = New-Object System.Windows.Thickness (10, 4, 10, 4)
    $barra.Children.Add($btnOk) | Out-Null
    $barra.Children.Add($btnCancelar) | Out-Null

    $caixaExterna.Add_Checked({
        $btnEscolher.IsEnabled = $true
        # Marcar a caixa não escolhe pasta nenhuma: até haver uma pasta CONFERIDA, 'Continuar' fica
        # desligado. Sem isso, marcar e confirmar cairia de volta na pasta protegida em silêncio,
        # que é o oposto do que a pessoa acabou de pedir.
        $btnOk.IsEnabled = [bool]$estado.External
    }.GetNewClosure())
    $caixaExterna.Add_Unchecked({
        $btnEscolher.IsEnabled = $false
        $estado.External = $false
        $estado.Path = ''
        $estado.Warning = ''
        $rotuloPasta.Text = ''
        $rotuloAviso.Text = ''
        $btnOk.IsEnabled = $true
    }.GetNewClosure())

    $btnEscolher.Add_Click({
        try {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Escolha a pasta onde o arquivo de permissões vai ficar'
            $dlg.ShowNewFolderButton = $true
            if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $escolhida = [string]$dlg.SelectedPath
            $julg = Test-WinForgeAclContentRoot -Path $escolhida -ProfilePath $perfil
            if (-not $julg.Ok) {
                $estado.External = $false
                $estado.Path = ''
                $estado.Warning = ''
                $rotuloPasta.Text = "Esta pasta não serve: $($julg.Reason)"
                $rotuloAviso.Text = ''
                $btnOk.IsEnabled = $false
                return
            }
            $estado.External = $true
            $estado.Path = [string]$julg.Path
            $estado.Warning = [string]$julg.Warning
            $rotuloPasta.Text = "O arquivo das permissões vai para: $($julg.Path)"
            $rotuloAviso.Text = [string]$julg.Warning
            $btnOk.IsEnabled = $true
        } catch {
            $estado.External = $false
            $estado.Path = ''
            $estado.Warning = ''
            $rotuloPasta.Text = "A pasta não pôde ser escolhida: $($_.Exception.Message)"
            $rotuloAviso.Text = ''
            $btnOk.IsEnabled = $false
        }
    }.GetNewClosure())

    $btnOk.Add_Click({
        $estado.Ok = $true
        $janela.Close()
    }.GetNewClosure())
    $btnCancelar.Add_Click({
        $estado.Ok = $false
        $janela.Close()
    }.GetNewClosure())

    $janela.Content = $grade
    [System.Windows.NameScope]::SetNameScope($janela, (New-Object System.Windows.NameScope))
    $janela.RegisterName('WFAclDestCaixa', $caixaExterna)
    $janela.RegisterName('WFAclDestEscolher', $btnEscolher)
    $janela.RegisterName('WFAclDestOk', $btnOk)
    $janela.RegisterName('WFAclDestCancelar', $btnCancelar)
    $janela.RegisterName('WFAclDestRolagem', $rolagem)
    $janela.RegisterName('WFAclDestBarra', $barra)

    if ($NoShow) { return $janela }
    # Modal, e aqui isso é o certo: o handler do botão é síncrono e ainda não tomou a trava de
    # comando em andamento, então nada mais do programa está parado esperando esta resposta.
    $janela.ShowDialog() | Out-Null

    return @{ Ok = [bool]$estado.Ok; External = [bool]$estado.External; Path = [string]$estado.Path; Warning = [string]$estado.Warning }
}

function Write-WinForgeAclContentBackup {
    <#
    .SYNOPSIS
        Grava a lista que a caminhada devolveu no formato que o 'icacls /restore' lê. É o ÚNICO
        ponto do programa que escreve o arquivo de conteúdo.
    .DESCRIPTION
        O formato foi MEDIDO no arquivo que o 'icacls /save' escreve, e são dois fatos:

        1. UTF-16LE SEM BOM. Os primeiros bytes do arquivo real são '72 00 61 00' - o "ra" do nome da
           primeira pasta - e não 'FF FE'. Em .NET 4.8 quem produz isso é UnicodeEncoding($false,
           $false): o primeiro $false é "não big-endian", o segundo é "não emita a marca".
           '[System.Text.Encoding]::Unicode' TEM a marca. O que está MEDIDO é o arquivo do icacls
           não ter marca nenhuma - o SelfTest confere isso a cada build, comparando os nossos bytes
           com os de um '/save' da mesma árvore. Que o '/restore' RECUSE um arquivo que comece com
           a marca é pesquisa, não medição: ele habilita SeRestorePrivilege na entrada e por isso
           não roda sem admin, onde o SelfTest vive. A regra prática não muda nos dois casos -
           escrever exatamente o que o icacls escreve.
        2. Par de linhas: '<nome relativo>' CRLF '<SDDL>' CRLF. O nome é relativo à pasta ACIMA do
           perfil, que é a pasta passada ao 'icacls <pasta> /restore'; quem monta esse nome é
           Get-WinForgeAclContentScope.

        O SDDL vem do .NET, e não do icacls. Nas amostras conferidas os dois são -ceq; quando
        diferem, diferem só na ORDEM das ACEs, porque o .NET as entrega em ordem canônica - 34 de 338
        entradas no perfil medido. Numa lista só de permissão a ordem é indiferente. Com ACE de
        NEGAÇÃO não é: negação só vence quando vem antes. Por isso a caminhada devolve 'Deny' e é o
        chamador que desvia essas pastas para um '/save' de verdade; aqui não há como recuperar uma
        ordem que já chegou canônica.

        'Count' sai do ARQUIVO RELIDO, nunca da lista de entrada. Medido: uma entrada cujo '.Sddl'
        estoura na leitura NÃO derruba a gravação - '[string]$e.Sddl' sobre uma propriedade que lança
        devolve '' em silêncio, e o par vira nome + linha em branco. Contando a lista, a função
        respondia Ok = $true e Count = 2 com um descritor só no disco: backup incompleto passando por
        bom, e o Desfazer só descobriria na hora de desfazer. Relido, o arquivo denuncia sozinho.

        A ordem é ORDINAL (§1.3). Não é estética: a fase 5 roda 'icacls <pasta> /inheritance:e' por
        entrada, SEM '/T', e depende do pai chegar antes do filho. Ordinal garante isso porque um
        prefixo sempre ordena antes do que o estende. 'Sort-Object' ordena pela CULTURA, onde 'ab'
        vem antes de 'a-b' e a caixa não separa - e aí a garantia de prefixo some.

        A trava de SelfTest vem antes de qualquer abertura de arquivo: esta função escreve, e o
        SelfTest não altera a máquina.
    .OUTPUTS
        @{ Ok; Reason; Count; Bytes }. 'Count' é quantos descritores o arquivo tem DEPOIS de gravado;
        com Ok = $false não sobra arquivo no disco, e Count e Bytes são 0.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries
    )

    Assert-WinForgeNotSelfTest -Name $MyInvocation.MyCommand.Name

    $r = @{ Ok = $false; Reason = ''; Count = 0; Bytes = 0 }
    $itens = @($Entries)
    # Lista vazia não vira arquivo vazio: um backup sem entrada nenhuma é contado como rede de
    # segurança pelo índice e não segura nada. Quem chama trata isso como "esta pasta fica fora".
    if ($itens.Count -lt 1) {
        $r.Reason = 'A lista de pastas veio vazia; não há permissão nenhuma para guardar.'
        return $r
    }
    # Caminho ABSOLUTO e prefixo '\\?\' em toda chamada .NET, a mesma regra da caminhada.
    # StreamWriter e FileInfo resolvem caminho relativo contra o diretório do PROCESSO, e não contra
    # a localização do PowerShell (Set-Content faria o contrário): um caminho relativo gravaria o
    # backup em outro lugar EM SILÊNCIO, e o Desfazer depois procuraria onde não está.
    # A pergunta é Test-WinForgeAclAbsolutePath e não 'IsPathRooted': a segunda deixava passar
    # 'C:acl.txt' e '\acl.txt', que falhavam adiante com a mensagem errada.
    if (-not (Test-WinForgeAclAbsolutePath -Path ([string]$Path))) {
        $r.Reason = "O caminho do backup precisa ser absoluto; veio '$Path'."
        return $r
    }
    $longo = if ([string]$Path -like '\\?\*') { [string]$Path } else { '\\?\' + [string]$Path }
    # Ordem ordinal (§1.3), por CompareOrdinal e não por Sort-Object: é o código do caractere que
    # entrega prefixo antes do que o estende, e é disso que a fase 5 depende para ligar a herança do
    # pai antes da do filho.
    $ordenados = New-Object System.Collections.Generic.List[object]
    foreach ($e in $itens) { $ordenados.Add($e) }
    $ordenados.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal([string]$a.Name, [string]$b.Name) })

    $abriu = $false
    try {
        # UnicodeEncoding($false, $false): UTF-16LE, sem BOM e sem detecção. É o formato medido no
        # arquivo que o 'icacls /save' escreve.
        $enc = New-Object System.Text.UnicodeEncoding($false, $false)
        $escritor = New-Object System.IO.StreamWriter($longo, $false, $enc)
        $abriu = $true
        try {
            foreach ($e in $ordenados) {
                $escritor.Write([string]$e.Name); $escritor.Write("`r`n")
                $escritor.Write([string]$e.Sddl); $escritor.Write("`r`n")
            }
        } finally { $escritor.Dispose() }
        # A conferência: quantos descritores o ARQUIVO tem. Divergiu do que foi mandado gravar, o
        # backup está incompleto e não sai daqui como bom.
        $r.Count = [int](Measure-WinForgeAclSaveEntry -Path $longo)
        if ($r.Count -ne $ordenados.Count) {
            throw ("O arquivo saiu com {0} descritor(es) para {1} pasta(s); a cópia das permissões está incompleta. Nada foi alterado." -f $r.Count, $ordenados.Count)
        }
        $r.Bytes = [long](New-Object System.IO.FileInfo ($longo)).Length
        $r.Ok = $true
    } catch {
        $r.Reason = $_.Exception.Message
    }
    # §1.6: arquivo pela metade não fica no disco. Só apaga o que ESTA chamada abriu - se a própria
    # abertura falhou, o que estiver lá é de outro, e apagar seria o estrago. (A trava para o
    # processo morrer NO MEIO da gravação é de quem orquestra, não do escritor.)
    if (-not $r.Ok -and $abriu) {
        try { [System.IO.File]::Delete($longo) } catch { }
        $r.Count = 0
        $r.Bytes = 0
    }
    return $r
}

function Get-WinForgeAclContentHash {
    <#
    .SYNOPSIS
        A impressão digital SHA-256 de um arquivo de backup de permissões, em maiúsculas. Só lê.
    .DESCRIPTION
        FileShare.Read, e não FileShare.None: o arquivo de backup é endurecido e conferido por outras
        partes do reparo, que o abrem para ler. Pedir exclusividade faria a impressão digital falhar
        justamente quando alguém está olhando o mesmo arquivo - e um 'não consegui' aqui vira
        "backup sem impressão digital", que é o mesmo que backup sem conferência.

        O hash sai do FLUXO, não dos bytes carregados na memória: ComputeHash(Stream) lê em pedaços,
        e o arquivo pode ter centenas de MB.

        Caminho absoluto e prefixo '\\?\', pelo mesmo motivo de Write-WinForgeAclContentBackup:
        'File::Open' resolve relativo contra o diretório do PROCESSO, e a impressão digital do
        arquivo errado é pior que impressão digital nenhuma.
    .OUTPUTS
        @{ Ok; Reason; Hash }. 'Hash' são 64 caracteres hexadecimais em MAIÚSCULAS, ou '' quando o
        arquivo não pôde ser lido.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $r = @{ Ok = $false; Reason = ''; Hash = '' }
    $sha = $null
    $fluxo = $null
    # Mesma porta da gravação, e pela mesma medição: 'C:acl.txt' e '\acl.txt' são "rooted" e não são
    # absolutos - a impressão digital do arquivo errado é pior que impressão digital nenhuma.
    if (-not (Test-WinForgeAclAbsolutePath -Path ([string]$Path))) {
        $r.Reason = "O caminho do backup precisa ser absoluto; veio '$Path'."
        return $r
    }
    $longo = if ([string]$Path -like '\\?\*') { [string]$Path } else { '\\?\' + [string]$Path }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fluxo = [System.IO.File]::Open($longo, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $r.Hash = [string](([System.BitConverter]::ToString($sha.ComputeHash($fluxo))) -replace '-', '')
        $r.Ok = $true
    } catch {
        $r.Reason = $_.Exception.Message
    } finally {
        if ($null -ne $fluxo) { $fluxo.Dispose() }
        if ($null -ne $sha) { $sha.Dispose() }
    }
    return $r
}

function Test-WinForgeAclFreeSpace {
    <#
    .SYNOPSIS
        Diz se o volume de um caminho ainda tem espaço para gravar N bytes. Só lê.
    .DESCRIPTION
        A pergunta vem ANTES da gravação, e não depois. Um escritor que enche o volume no meio do
        arquivo deixa um backup pela metade, e backup pela metade é o botão Desfazer prometendo o
        que não tem - §1.6. Aqui a recusa acontece com o disco ainda intocado.

        'AvailableFreeSpace', e não 'TotalFreeSpace': o primeiro desconta a cota de disco da
        identidade atual, e é ele que diz o que ESTE processo consegue mesmo gravar.

        Não ler o volume é RECUSA, não permissão: sem saber o espaço, gravar é apostar - a mesma
        regra da caminhada, que trata atributo ilegível como recusa.
    .OUTPUTS
        @{ Ok; Reason; Free }. 'Free' são os bytes livres do volume, ou 0 quando não deu para ler.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$Bytes
    )

    $r = @{ Ok = $false; Reason = ''; Free = [long]0 }
    try {
        $volume = [string][System.IO.Path]::GetPathRoot([string]$Path)
        if ([string]::IsNullOrWhiteSpace($volume)) { throw "'$Path' não diz em que volume está." }
        $r.Free = [long](New-Object System.IO.DriveInfo ($volume)).AvailableFreeSpace
    } catch {
        $r.Reason = "O espaço livre de '$Path' não pôde ser lido ($($_.Exception.Message)). Nada foi gravado."
        $r.Free = [long]0
        return $r
    }
    # O número vai para a tela nas duas pontas: "preciso de X" sem "e há Y" não diz ao usuário
    # quanto ele tem de liberar.
    if ($r.Free -lt $Bytes) {
        $r.Reason = ("O backup das permissões precisa de {0:N0} byte(s) e o volume tem {1:N0} livre(s). Nada foi alterado - libere espaço e tente de novo." -f $Bytes, $r.Free)
        return $r
    }
    $r.Ok = $true
    return $r
}

function Get-WinForgeAclScopeVerdict {
    <#
    .SYNOPSIS
        O cabeçalho e o texto de fim da restauração, a partir do que a caminhada CONSEGUIU ler.
    .DESCRIPTION
        Função pura: recebe a saída de Get-WinForgeAclContentScope e devolve texto. Não lê disco,
        não escreve nada e não depende de estado nenhum.

        Por que o cabeçalho MUDA, em vez de ganhar um aviso no rodapé: até a 1.7.0 a fase 5 descia
        o perfil inteiro com '/T' e alcançava também a pasta que a caminhada não conseguiu abrir.
        Agora ela percorre só a lista guardada, então pasta ilegível fica de fora das DUAS pontas -
        do backup e do conserto. Em máquina já quebrada é justamente ali que dói. Dizer
        'Concluído' e esconder isso no fim de um texto longo seria dizer que consertou o que não
        consertou.

        Vinte caminhos, não a lista inteira: 'DeniedPaths' vem com até 200, e uma parede de texto
        na janela de saída esconde a informação em vez de entregá-la. A contagem completa fica na
        primeira linha - e quando ela for MAIOR que a lista de caminhos, o texto diz isso em vez de
        emendar "as 20 primeiras, de 200" logo abaixo de "500 pasta(s)". Dois tetos diferentes
        (contagem sem teto, caminhos até 200) faziam os números se contradizerem na tela.
    .OUTPUTS
        @{ Header; Text }. Sem pasta negada, 'Header' é 'Concluído' e 'Text' é vazio.
    #>
    param([Parameter(Mandatory)][object]$Scope)

    $r = @{ Header = 'Concluído'; Text = '' }
    $negadas = 0
    try { $negadas = [int]$Scope.Denied } catch { $negadas = 0 }
    if ($negadas -lt 1) { return $r }

    $todas = @(@($Scope.DeniedPaths) | ForEach-Object { [string]$_ })
    $mostrar = @($todas | Select-Object -First 20)
    $linhas = New-Object System.Collections.Generic.List[string]
    $linhas.Add("$negadas pasta(s) não puderam ser lidas e por isso não foram copiadas nem alteradas - ficaram exatamente como estavam.")
    # Três números, e eles têm de fechar. A CONTAGEM não tem teto; a lista de caminhos tem (a
    # caminhada para de anotar em 200). Anunciar "500 pasta(s)" e emendar "as 20 primeiras, de 200"
    # é contar duas histórias na mesma caixa - quem lê conclui que perdeu 480 no caminho. Quando os
    # dois divergem, a linha diz por quê.
    if ($mostrar.Count) {
        if ($negadas -gt $todas.Count) { $linhas.Add("O caminho de $($todas.Count) delas foi anotado - as outras $($negadas - $todas.Count) foram contadas, mas a anotação dos caminhos para em $($todas.Count). Destas, as $($mostrar.Count) primeiras:") }
        elseif ($todas.Count -gt $mostrar.Count) { $linhas.Add("As $($mostrar.Count) primeiras, de $($todas.Count):") }
        else { $linhas.Add('São elas:') }
    }
    foreach ($p in $mostrar) { $linhas.Add("  $p") }
    $r.Header = 'Concluído com ressalvas'
    $r.Text = (@($linhas) -join [Environment]::NewLine)
    return $r
}

function Get-WinForgeAclIcaclsSddl {
    <#
    .SYNOPSIS
        O SDDL de UMA pasta escrito pelo próprio icacls, na ordem em que as ACEs estão no disco.
    .DESCRIPTION
        Existe por causa da ORDEM das ACEs, e só por isso. O SDDL que a caminhada lê vem do .NET,
        que entrega a lista em ordem CANÔNICA - negação antes de permissão. Medido no perfil real:
        34 das 338 pastas diferem do texto do icacls só nessa ordem, e nenhuma delas tem ACE de
        negação. Numa lista só de permissão a ordem é indiferente. Com NEGAÇÃO não é: negação só
        vence quando vem ANTES, e devolver uma ordem canônica a uma pasta que não estava canônica
        muda o acesso sem mudar uma vírgula do texto que o usuário vê. Para essas - e só para
        essas - o texto tem de sair de quem leu o disco sem reordenar.

        'icacls <pasta> /save <arq> /L /Q', SEM '/T': é UMA chamada por pasta, e é justamente o
        '/T' que não pode voltar - ele é o laço que gravou ~50 GB. MEDIDO nesta forma exata, com
        caminho absoluto e SEM barra no fim: o arquivo sai com UM par só, e o nome dele é a FOLHA
        da pasta pedida ('Negada'), não um nome vazio e não os filhos. (O nome vazio é de outra
        forma de chamada - 'icacls <pasta>\ /save', com a barra -, e é justamente a que o
        '/restore' não sabe aplicar.) O par é conferido pelo nome antes de o SDDL ser aceito: se um
        Windows futuro mudar essa escolha, esta função RECUSA em vez de devolver o descritor de
        outra pasta. O nome que vai para o backup continua sendo o relativo que a caminhada montou.

        O '/L' é obrigatório pelo mesmo motivo de sempre: sem ele o icacls leria a ACL do DESTINO
        de um ponto de reanálise. (A caminhada não indexa reparse point, então na prática não chega
        aqui nenhum - mas a trava não custa nada e a ausência dela custaria caro.)

        E o '/C' fica de FORA, ao contrário do resto do reparo. Medido: com '/C' uma pasta que o
        icacls não acha sai com código 0 - '/C' é "continue apesar do erro", e num alvo único não
        há o que continuar; ele só apaga o sinal de falha. Sem '/C' a mesma pasta sai com 2, e é
        esse número que vira a frase do log. O arquivo de saída, aliás, é TRUNCADO antes de o
        icacls falhar, então sobra de chamada anterior não existe - o código é o que diz ao usuário
        o que aconteceu, e é para isso que ele é conferido.

        Primitiva, e por isso SEM a trava de -SelfTest: quem a chama é Invoke-WinForgeAclRestore,
        que tem. É também o que deixa o -SelfTest prová-la numa pasta descartável de %TEMP%, sem
        elevação - 'icacls /save' não precisa dela numa pasta cuja dona é a própria identidade.
    .PARAMETER WorkFile
        O arquivo que o icacls escreve, e que esta função apaga ao sair. Quem chama escolhe o
        lugar, e escolhe a pasta protegida: o texto lido daqui vira o SDDL que o Desfazer reaplica,
        então um arquivo que outro processo possa trocar entre a gravação e a leitura é o ataque,
        não um detalhe.
    .OUTPUTS
        @{ Ok; Reason; Sddl }. Com Ok = $false o 'Sddl' vem vazio, e quem chama falha FECHADO: o
        texto do .NET não serve de substituto justamente aqui, porque é a ordem dele que trancaria
        o usuário na hora de desfazer.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$WorkFile
    )

    $r = @{ Ok = $false; Reason = ''; Sddl = '' }
    $leitor = $null
    try {
        $res = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'icacls.exe') -Arguments @([string]$Path, '/save', [string]$WorkFile, '/L', '/Q') -Encoding 'oem'
        if ([int]$res.ExitCode -ne 0) { throw ("o 'icacls /save' de '{0}' terminou com código {1}." -f $Path, $res.ExitCode) }
        # O mesmo formato de sempre: pares <nome>CRLF<SDDL>CRLF, UTF-16LE sem marca. O $false final
        # desliga a detecção por marca, que este arquivo não tem.
        $leitor = New-Object System.IO.StreamReader([string]$WorkFile, [System.Text.Encoding]::Unicode, $false)
        $nome = [string]$leitor.ReadLine()
        $folha = [string](Split-Path -Leaf ([string]$Path))
        if ($nome -ne $folha) { throw ("o 'icacls /save' de '{0}' trouxe '{1}' onde era esperada a folha '{2}'." -f $Path, $nome, $folha) }
        $r.Sddl = [string]$leitor.ReadLine()
        if ([string]::IsNullOrEmpty([string]$r.Sddl)) { throw ("o 'icacls /save' de '{0}' não trouxe o descritor da pasta." -f $Path) }
        $r.Ok = $true
    } catch {
        $r.Reason = $_.Exception.Message
        $r.Sddl = ''
    } finally {
        if ($null -ne $leitor) { $leitor.Dispose() }
        Remove-Item -LiteralPath $WorkFile -Force -ErrorAction SilentlyContinue
    }
    return $r
}

function Restore-WinForgeAclSddl {
    <#
    .SYNOPSIS
        Devolve a uma pasta a lista de permissões guardada como SDDL e, se der, o dono.
    .DESCRIPTION
        Duas operações SEPARADAS, por ferramentas DIFERENTES, e a separação é o ponto: a DACL volta
        sempre que o chamador tiver WRITE_DAC na pasta; o dono precisa de SeRestorePrivilege.
        Juntá-las faria a falha do dono derrubar a volta da lista, que é a parte que o usuário está
        esperando.

        A LISTA volta por SDDL: o descritor nasce VAZIO, recebe só a seção 'Access' e quem escreve é
        DirectoryInfo.SetAccessControl - NÃO o Set-Acl. A diferença foi medida numa pasta de %TEMP%:
        com 'Set-Acl' um descritor que só teve SetOwner() chamado REESCREVE TAMBÉM A DACL, apagando
        toda ACE explícita e deixando só as herdadas. Numa pasta do sistema restaurada com
        '/inheritance:r' - onde TUDO é explícito - isso apagaria, no passo do dono, exatamente a
        lista que o passo anterior acabou de devolver. O SetAccessControl respeita as seções que o
        objeto marcou como modificadas: dono é dono, lista é lista, e a SACL e o grupo primário
        ficam onde estão.

        O DONO volta por 'icacls <pasta> /setowner *<SID> /L /Q', e não pelo .NET. O
        SetAccessControl NUNCA habilita o SeRestorePrivilege do token: sem ele, atribuir a posse a
        um SID que o chamador não possui - TrustedInstaller nas pastas do sistema, que é o caso que
        importa - responde ERROR_INVALID_OWNER (1307, "o identificador de segurança não pode ser o
        proprietário deste objeto") mesmo com o WinForge elevado, e o Desfazer devolvia a lista e
        deixava a pasta do sistema com os Administradores como donos. O icacls habilita o
        privilégio sozinho; é o que a fase 4 da restauração já faz no 'setowner-devolver', e agora
        as duas pontas usam o mesmo caminho.

        Três travas nesse vetor, e as três importam porque o SID vem do índice, que é um arquivo:
        o executável é o caminho completo do System32 (Get-WinForgeSystemExe), o direito é SÓ POR
        SID (o texto passa por SecurityIdentifier antes de virar argumento, então um
        'Administradores' ou um '/grant:r ...' plantado no índice é recusado AQUI, sem chegar ao
        icacls) e o '/L' é obrigatório: sem ele, uma pasta que já tenha virado ponto de reanálise
        faria o '/setowner' trocar o dono do DESTINO do link em vez do da pasta que o backup
        guardou.

        Esta é uma primitiva, e por isso NÃO tem a trava de -SelfTest: quem a chama é
        Invoke-WinForgeAclUndo, que tem. É também o que permite ao -SelfTest provar a ida e a volta
        numa pasta descartável de %TEMP%, sem elevação (nem a DACL nem a posse de uma pasta cuja
        dona é a própria identidade precisam dela).
    .OUTPUTS
        @{ DaclOk; OwnerTried; OwnerOk; Reason; OwnerReason }.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sddl,
        [string]$OwnerSid
    )

    $r = @{ DaclOk = $false; OwnerTried = $false; OwnerOk = $false; Reason = ''; OwnerReason = '' }
    try {
        $pasta = New-Object System.IO.DirectoryInfo ([string]$Path)
        $sd = New-Object System.Security.AccessControl.DirectorySecurity
        $sd.SetSecurityDescriptorSddlForm([string]$Sddl, [System.Security.AccessControl.AccessControlSections]::Access)
        $pasta.SetAccessControl($sd)
        $r.DaclOk = $true
    } catch {
        $r.Reason = $_.Exception.Message
        return $r
    }
    if ([string]::IsNullOrWhiteSpace($OwnerSid)) { return $r }
    $r.OwnerTried = $true
    $sid = $null
    try { $sid = [string](New-Object System.Security.Principal.SecurityIdentifier ([string]$OwnerSid)).Value } catch { $sid = '' }
    if ([string]::IsNullOrWhiteSpace($sid)) {
        $r.OwnerReason = "'$OwnerSid' não é um SID válido; a posse não foi tocada"
        return $r
    }
    $res = Invoke-WinForgeNativeCommand -FilePath (Get-WinForgeSystemExe -Name 'icacls.exe') -Arguments @([string]$Path, '/setowner', "*$sid", '/L', '/Q')
    if ([int]$res.ExitCode -eq 0) { $r.OwnerOk = $true }
    else { $r.OwnerReason = ("o icacls terminou com código {0}: {1}" -f [int]$res.ExitCode, ([string]$res.Text).Trim()) }
    return $r
}

function Measure-WinForgeAclSaveEntry {
    <#
    .SYNOPSIS
        Quantas entradas um arquivo de 'icacls /save' tem. Só lê.
    .DESCRIPTION
        O arquivo do '/save' é UTF-16LE SEM BOM (medido), e cada entrada ocupa duas linhas úteis: o
        nome relativo e o descritor. Contar as linhas de descritor é contar entradas - e é o que
        separa um backup com conteúdo de um arquivo que o '/save' criou e não conseguiu preencher
        (pasta com DACL só de SYSTEM, 'System Volume Information' e parentes), que era indexado e
        contado como se fosse rede de segurança.

        A leitura é por FLUXO, uma linha de cada vez. Um backup de perfil inteiro guardado pela 1.7.0
        passa dos 100 MB; materializar as linhas num vetor só para olhar as duas primeiras letras de
        cada uma é OutOfMemoryException numa função que não precisa de nenhuma linha depois de
        contá-la.
    .OUTPUTS
        O número de entradas; 0 quando o arquivo não pôde ser lido.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $leitor = $null
    try {
        # O $false final desliga a detecção pela marca: o formato medido não tem marca nenhuma, e
        # assim a decodificação fica presa em UTF-16LE em vez de depender dos primeiros bytes.
        $leitor = New-Object System.IO.StreamReader([string]$Path, [System.Text.Encoding]::Unicode, $false)
        $n = 0
        while ($null -ne ($linha = $leitor.ReadLine())) {
            $t = ([string]$linha).Trim()
            if ($t.StartsWith('D:', [StringComparison]::Ordinal) -or $t.StartsWith('O:', [StringComparison]::Ordinal)) { $n++ }
        }
        return $n
    } catch {
        return 0
    } finally {
        if ($null -ne $leitor) { $leitor.Dispose() }
    }
}

function Get-WinForgeAclInheritSteps {
    <#
    .SYNOPSIS
        As chamadas de icacls da fase 5: UMA por pasta da lista que a fase 2 guardou, e nenhuma com
        '/T'. Função pura - monta caminhos e vetores de argumentos, não roda nada.
    .DESCRIPTION
        É a outra metade do par que tirou o 'icacls /T' do perfil. A fase 2 já guarda só as pastas
        com herança bloqueada (Get-WinForgeAclContentScope); esta função faz a fase 5 percorrer
        EXATAMENTE essa lista. Guardado e alterado passam a ser o mesmo conjunto, que é a condição
        de o botão Desfazer desfazer.

        O que sai daqui é o conserto de um defeito da 1.7.0, e não só um ganho de velocidade:
        'icacls <perfil>\* /inheritance:e /T /L' descia SEGUINDO ponto de reanálise - o '/L' fala do
        ALVO de cada item, não do caminho percorrido - e ligava herança FORA do perfil, no destino
        de cada junção de compatibilidade e no OneDrive redirecionado. Alterava o que o backup não
        cobria, em pasta que o usuário nem sabia estar no caminho.

        A ordem é ORDINAL, por CompareOrdinal, e é a MESMA de Write-WinForgeAclContentBackup: é o
        código do caractere que garante que um prefixo venha antes do que o estende, e todo nome de
        pai é prefixo do nome do filho ('fulano' < 'fulano\AppData' < 'fulano\AppData\Local'). Isso
        importa porque ligar a herança no filho antes do pai não propaga o que o pai ainda não tem.
        'Sort-Object' ordena pela CULTURA, onde 'ab' vem antes de 'a-b' e a garantia de prefixo sai
        de cena; medido nesta máquina, as duas ordenações discordam em nove nomes de teste, e
        '-Culture ([CultureInfo]::InvariantCulture)' não conserta isso - o parâmetro é uma STRING, a
        cultura invariante vira '' e a comparação continua linguística.

        SEM '/C', e isso é o oposto do que a primeira versão desta função fazia. O '/C' é "continue
        apesar do erro", e num alvo ÚNICO não há o que continuar: ele só apaga o sinal. MEDIDO
        nesta forma exata de chamada, sem elevação, em %TEMP%:

            pasta que existe            -> 0 com '/C' e 0 sem
            pasta que não existe        -> 0 com '/C' e 2 sem
            PAI da pasta não existe     -> 3 sem '/C'
            pai inexistente dois níveis -> 3 sem '/C'
            unidade não existe          -> 3 sem '/C'
            curinga sem correspondência -> 0 sem '/C'

        Com '/C' no vetor, o 'if ($r.ExitCode -ne 0)' do chamador era código MORTO: a fase 5 podia
        não ligar herança em pasta nenhuma e o log dizer "Concluído". O que sobra do argumento a
        favor do '/C' - pasta de cache some entre a caminhada da fase 2 e esta fase o tempo todo -
        é resolvido onde deve ser, no CHAMADOR, e pela EXISTÊNCIA da pasta, nunca pelo código de
        saída: ver Get-WinForgeAclInheritOutcome.

        A linha do curinga acima já esteve errada aqui, e a linha errada sustentou uma conclusão
        errada: ela dizia que o curinga sem correspondência sai 3, e daí se concluía que o código 3
        não era produzível nesta forma de chamada, sem '/T' e sem curinga. O curinga sai 0. O 3 é o
        código de caminho inexistente ACIMA do alvo - e pai inexistente é o caso comum desta lista,
        porque a caminhada da fase 2 desce em toda pasta e indexa pai e filho.

        Sem '/L': a caminhada da fase 2 NÃO indexa ponto de reanálise, então nenhuma entrada desta
        lista é junção. O '/L' existe para não seguir o link, e aqui não há link para seguir.
    .PARAMETER Root
        A pasta de onde os nomes da lista são relativos - o 'Target' do passo 'scope' da fase 2, que
        é a pasta ACIMA do perfil. É a mesma pasta que o 'icacls /restore' do Desfazer usa, e é por
        isso que ela não é adivinhada aqui.
    .OUTPUTS
        @(@{ Path; FilePath; Arguments }), na ordem em que têm de rodar.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries
    )

    $icacls = Get-WinForgeSystemExe -Name 'icacls.exe'
    $ordenadas = New-Object System.Collections.Generic.List[object]
    foreach ($e in @($Entries)) { $ordenadas.Add($e) }
    $ordenadas.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal([string]$a.Name, [string]$b.Name) })

    $passos = @()
    foreach ($e in $ordenadas) {
        # Entrada sem nome não vira passo: '[string]$e.Name' sobre uma propriedade que lança devolve
        # '' em silêncio, e 'Join-Path' com '' estouraria no meio da fase. Pular altera MENOS do que
        # o backup cobre, que é o lado seguro da mesma regra.
        $nome = [string]$e.Name
        if ([string]::IsNullOrWhiteSpace($nome)) { continue }
        $pasta = [string](Join-Path ([string]$Root) $nome)
        $passos += @{
            Path      = $pasta
            FilePath  = $icacls
            Arguments = @($pasta, '/inheritance:e', '/Q')
        }
    }
    return @($passos)
}

function Get-WinForgeAclInheritOutcome {
    <#
    .SYNOPSIS
        Classifica o resultado de UMA chamada de icacls da fase 5: deu certo, a pasta sumiu desde o
        backup, ou falhou. Só lê.
    .DESCRIPTION
        A pergunta é pela EXISTÊNCIA da pasta, e não pelo CÓDIGO de saída. A diferença entre as duas
        é um reparo que correu bem terminando numa lista de erros.

        A versão anterior classificava pelo código: 2 era "sumiu" (aviso) e qualquer outro código
        diferente de zero era erro. MEDIDO na forma exata desta chamada
        ('icacls <alvo> /inheritance:e /Q', sem elevação e sem curinga): pasta inexistente com o pai
        no lugar sai 2, mas PAI inexistente sai 3, pai inexistente a dois níveis sai 3 e unidade
        inexistente sai 3.

        E pai e filho estão os DOIS nesta lista, porque a caminhada da fase 2 desce em toda pasta
        com herança bloqueada: 'AppData\Local\Packages\<app>' com '...\<app>\LocalCache' é o arranjo
        normal de aplicativo da Loja. Desinstalado o aplicativo entre a fase 2 e a fase 5, a ordem
        ordinal manda o pai primeiro - o pai sai com 2 e vira aviso, e cada descendente sai com 3 e
        vira erro. Um perfil com algumas dezenas dessas pastas terminaria com dezenas de erros num
        reparo que não errou nada, que é exatamente o que o ramo do aviso existe para evitar.

        Código 0 responde antes de qualquer pergunta ao disco. Ele é a resposta do próprio icacls,
        que acabou de ligar a herança ali: perguntar primeiro custaria um acesso a disco por pasta,
        em centenas delas, e faria uma pasta de cache apagada um instante DEPOIS de uma chamada bem
        sucedida contar como sumida.

        A existência é perguntada pelo CAMINHO LONGO ('\\?\'), como no resto deste arquivo. Sem o
        prefixo, a API normaliza o nome antes de olhar o disco - corta espaço no fim, corta ponto no
        fim - e responde "não existe" para pasta que está lá: a falha de verdade sairia como aviso,
        calada, e é dentro do perfil que nomes assim aparecem.

        Caminho vazio é 'falha', e não 'sumida': não dá para AFIRMAR que sumiu o que não foi
        nomeado, e o lado seguro do erro aqui é o que aparece no log.

        1223 (ERROR_CANCELLED) é 'cancelada', e vem antes de qualquer pergunta ao disco: é o código
        que o fluxo ao vivo devolve para um passo que NÃO chegou a ser iniciado, depois do Parar.
        Sem essa resposta, parar no meio de um perfil com 338 pastas fecharia com "a herança não
        pôde ser ligada em 334 pasta(s)" - o programa culpando o usuário por ter clicado em Parar.
    .OUTPUTS
        'ok', 'cancelada', 'sumida' ou 'falha'.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][int]$ExitCode
    )

    if ($ExitCode -eq 0) { return 'ok' }
    if ($ExitCode -eq 1223) { return 'cancelada' }
    if ([string]::IsNullOrWhiteSpace($Path)) { return 'falha' }
    $longo = if ([string]$Path -like '\\?\*') { [string]$Path } else { '\\?\' + [string]$Path }
    if ([System.IO.Directory]::Exists($longo)) { return 'falha' }
    return 'sumida'
}

function Get-WinForgeAclRestorePlan {
    <#
    .SYNOPSIS
        As seis fases da restauração de permissões, em ordem, como passos de executável.
    .DESCRIPTION
        Dado puro: monta caminhos e vetores de argumentos, não roda nada e não cria pasta nenhuma. É
        assim que o -SelfTest confere a ORDEM das fases, o caminho completo de cada executável e o
        fato de todo direito sair por SID, sem reescrever as permissões do disco de quem compila.

        As fases, e por que nesta ordem:

        1. chkdsk /scan (só leitura). Reescrever a DACL de um volume com erro de sistema de arquivos
           é consertar o que vai corromper de novo. Se ele acusar erro, a restauração PARA aqui.
        2. Backup das listas atuais, uma por pasta: a raiz, cada pasta de primeiro nível, cada
           pasta ANINHADA da tabela de esperados que a fase 4 pode reescrever ('Users\Public') e a
           pasta do usuário. Cada uma vira um passo 'sddl' - a DACL e o dono DELA MESMA, guardados
           no índice -, e o perfil ganha ainda um passo 'scope' para o CONTEÚDO, que o MOTOR
           executa: uma caminhada em pilha que guarda só as pastas com herança bloqueada. É o que
           o botão Desfazer consome.
        3. A raiz. Negações fora ('/remove:d', só se houver), '/inheritance:r' + '/grant:r' com as
           ACEs padrão e um '/grant' separado para a segunda ACE dos Usuários Autenticados.
        4. Pasta por pasta: Windows, Program Files, Program Files (x86), ProgramData, Users e
           Users\Public. Para cada uma, '/setowner' (só se o dono estiver fora do padrão) e
           '/inheritance:r /grant:r' + '/grant' com as ACEs medidas de Get-WinForgeAclExpected -
           NA PASTA, sem '/T', sem '/reset'. E só nas pastas que a verificação acusou: quem decide
           é Invoke-WinForgeAclRestore, com o relatório na mão. Cada pasta traz ainda um par de
           socorro condicional ('setowner-socorro' e 'setowner-devolver'): se a concessão responder
           "acesso negado", a posse vai para os Administradores, a concessão é repetida uma vez e a
           posse VOLTA ao dono padrão.
        5. A pasta do usuário: '/setowner' (condicional), negações fora (condicional), as três ACEs
           padrão na RAIZ do perfil e, depois delas, a herança do CONTEÚDO - um passo 'inherit-list'
           sem executável, que o motor expande em um 'icacls <pasta> /inheritance:e' por pasta da
           lista guardada na fase 2. A ordem é dependência: a herança só propaga o que já está
           concedido na raiz. '/reset /T' não é usado - ele apagaria as ACEs explícitas que os
           próprios aplicativos põem (AppData\Local\Packages, OneDrive), e '/inheritance:e' as
           preserva. '/T' não é usado por nada nesta fase: ele descia pela junção e pelo OneDrive e
           alterava mais do que o backup cobre.
        6. takeown /F <raiz> /A, SEM recursão, e só quando a fase 3 responder "acesso negado". O
           passo vem marcado com 'Conditional' e quem decide rodá-lo é Invoke-WinForgeAclRestore.

        O secedit saiu do plano: no Windows 10 e no 11 o defltbase.inf tem [Registry Keys] e
        [File Security] VAZIAS, então '/areas FILESTORE REGKEYS' não repõe DACL nenhuma. A fase 4
        faz esse trabalho explicitamente, com a tabela medida.

        O passo 'scope' do CONTEÚDO carrega 'Backup' (o arquivo que vai ser gravado) e 'Target' (a
        pasta a partir da qual o /restore tem de rodar). O alvo não é adivinhado depois: o arquivo
        traz NOMES RELATIVOS a essa pasta - é o formato do icacls, e é dele que o Desfazer depende
        -, então ela é anotada aqui, no único lugar em que a regra existe. Os passos 'sddl' e
        'scope' são os dois sem 'FilePath': o primeiro é lido na hora
        (Get-WinForgeAclFolderSecurity) e gravado no índice; o segundo é a caminhada do motor.

        Um '/grant' por SID por chamada: dentro de um mesmo '/grant' o icacls guarda só a ÚLTIMA
        entrada de cada SID, então '*S-1-5-11:(OI)(CI)(IO)M' e '*S-1-5-11:(AD)' na mesma linha viram
        uma ACE só - e o direito de criar arquivo na raiz sumiria sem nenhum erro.

        Direito ESPECÍFICO vai entre parênteses, e isso foi medido: 'icacls <pasta> /grant
        *S-1-5-11:AD' termina com código 87 ("Parâmetro inválido") e não concede nada. Sem
        parênteses o icacls só aceita as letras de direito SIMPLES (F, M, RX, R, W, D). O -SelfTest
        roda cada string de concessão deste plano contra uma pasta em %TEMP% justamente para que um
        erro desses apareça no build, e não na máquina de quem clicou no botão.
    .OUTPUTS
        Vetor de hashtables com Phase, Title, Kind e, conforme o passo, FilePath/Arguments,
        Path/Backup/Target (fase 2), Folder (fases 3 a 5) e Conditional. Três passos não têm
        FilePath, e nenhum dos três chama executável a partir do plano: 'sddl' e 'scope' na fase 2 e
        'inherit-list' na fase 5.
    #>
    param(
        [string]$Profile,
        [string]$UserSid,
        [string]$BackupRoot,
        [string]$Stamp
    )

    $sid = Get-WinForgeAclWellKnownSid
    $raiz = Get-WinForgeSystemDriveRoot
    $unidade = $raiz.TrimEnd('\')
    $icacls = Get-WinForgeSystemExe -Name 'icacls.exe'
    $takeown = Get-WinForgeSystemExe -Name 'takeown.exe'
    $chkdsk = Get-WinForgeSystemExe -Name 'chkdsk.exe'
    if ([string]::IsNullOrWhiteSpace($Stamp)) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $BackupRoot = Get-WinForgeAclBackupRoot }

    $plano = @()
    $plano += @{
        Phase     = 1
        Title     = "Verificação do disco $unidade (chkdsk /scan, só leitura)"
        FilePath  = $chkdsk
        Arguments = @($unidade, '/scan')
        # A dica de decodificação, e ela NÃO é a de todo mundo aqui: o resto do plano é icacls e
        # takeown, que escrevem OEM (o padrão de Get-WinForgeOutputEncoding, e por isso não
        # declarado). O chkdsk escreve ANSI - medido, o 'ó' dele é 0xF3 -, e sem esta chave o
        # 'concluídos' dele chegava embaralhado à janela. Passou a doer quando a fase 1 entrou no
        # fluxo ao vivo: antes o texto ia para a janela pelo mesmo erro, agora vai linha a linha.
        Encoding  = 'ansi'
    }

    # As pastas de primeiro nível saem de uma listagem, e não de uma lista escrita à mão: cada
    # máquina tem as suas. Ponto de reanálise fica de fora - 'C:\Documents and Settings' é uma
    # junção para 'C:\Users', e salvar (ou restaurar) por ela seria mexer no destino por outro nome.
    $primeiroNivel = @()
    try {
        $primeiroNivel = @(Get-ChildItem -LiteralPath $raiz -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) } |
            Sort-Object Name | ForEach-Object { $_.FullName })
    } catch { $primeiroNivel = @() }

    $alvos = @()
    $alvos += @{ Path = $raiz; Recursive = $false }
    foreach ($p in $primeiroNivel) { $alvos += @{ Path = $p; Recursive = $false } }
    # As pastas ANINHADAS da tabela de esperados - hoje só 'Users\Public' - não aparecem na
    # listagem de primeiro nível, e a fase 4 reescreve a DACL delas. Sem esta volta o Desfazer
    # devolveria tudo menos justamente uma pasta que a restauração mexeu. A regra é essa, e não a
    # lista: toda pasta que a fase 4 pode tocar tem de ter backup na fase 2.
    $jaSalvas = @{}
    foreach ($a in $alvos) { $jaSalvas[([string]$a.Path).TrimEnd('\')] = $true }
    foreach ($esp in @(Get-WinForgeAclExpected | Where-Object { $_.Direta })) {
        $p = [string]$esp.Path
        if ($jaSalvas.ContainsKey($p.TrimEnd('\'))) { continue }
        $alvos += @{ Path = $p; Recursive = $false }
        $jaSalvas[$p.TrimEnd('\')] = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $alvos += @{ Path = $Profile; Recursive = $true }
    }

    foreach ($alvo in $alvos) {
        # A lista da PRÓPRIA pasta vai para o ÍNDICE, como SDDL, e não para um arquivo de icacls.
        # Foi medido, elevado, numa pasta de %TEMP%: 'icacls <pasta>\ /save f /C' grava a entrada da
        # própria pasta com o NOME VAZIO, e 'icacls <pasta>\ /restore f /C /L' NÃO a aplica - ele
        # monta o caminho '<pasta>\<sddl>' e responde "arquivo não encontrado", deixando a DACL
        # alterada como estava. O '/save' desfaz os FILHOS de uma pasta; a pasta em si, nunca.
        # Como a fase 3 mexe na raiz e a fase 4 mexe nas seis pastas do sistema NELAS MESMAS (sem
        # '/T'), o backup que o Desfazer precisa é exatamente esse - e ele passa a existir para
        # TODAS as pastas guardadas, com o dono junto.
        $plano += @{
            Phase = 2
            Kind  = 'sddl'
            Title = "Guardar a lista e o dono de '$($alvo.Path)' no índice (SDDL)"
            Path  = [string]$alvo.Path
        }
        if (-not $alvo.Recursive) { continue }
        # Só o perfil ganha arquivo de conteúdo, e por um motivo que a raiz e as pastas do sistema
        # não têm: a fase 5 liga a herança nas pastas de DENTRO dele, então o desfazer precisa da
        # lista de cada uma - o SDDL da pasta em si não alcança isso.
        #
        # Quem escreve esse arquivo é o MOTOR (Get-WinForgeAclContentScope + a gravação), e não o
        # 'icacls /save /T'. O passo não tem executável nem vetor de argumentos.
        #
        # Por que o '/T' saiu, medido e não suposto: ele desce a árvore SEGUINDO ponto de reanálise,
        # e o '/L' NÃO poda a travessia - o '/L' fala do ALVO de cada item, não do caminho
        # percorrido. Num perfil isso é OneDrive, 'Meus Documentos' redirecionado e as junções de
        # compatibilidade ('AppData\Local\Dados de Aplicativos' aponta para 'AppData\Local', o
        # próprio pai). Quem para a recursão não é o MAX_PATH nem o '/L': é o limite de 63 saltos de
        # reparse do Windows. Até chegar lá o icacls já gravou o mesmo ramo dezenas de vezes - foi
        # assim que esse passo escreveu ~50 GB e travou a máquina de um usuário real. Por isso
        # 'icacls <perfil> /T' não é utilizável sobre pasta de perfil, com ou sem '/L'.
        $arquivo = Join-Path $BackupRoot ("acl-{0}-{1}.txt" -f ('perfil-' + (Get-WinForgeAclSlug -Text ([string](Split-Path -Leaf ([string]$alvo.Path))))), $Stamp)
        $plano += @{
            Phase  = 2
            Kind   = 'scope'
            Title  = "Backup das permissões do conteúdo de '$($alvo.Path)'"
            Path   = [string]$alvo.Path
            Backup = $arquivo
            # A pasta de onde o '/restore' roda: o nome de cada entrada é relativo a ela, e é a
            # pasta ACIMA do perfil. Medido: o arquivo começa com a entrada do próprio perfil
            # ('<folha>'), e não com uma entrada de nome vazio - o que decide isso é a BARRA no fim
            # do alvo, e não quem invocou de onde: 'icacls <pasta>\ /save' grava a entrada vazia,
            # 'icacls <pasta> /save' grava o par nomeado pela folha. A raiz cai no primeiro caso
            # porque 'C:\' já termina em barra.
            Target = [string](Split-Path -Parent ([string]$alvo.Path))
        }
    }

    # ---- Fase 3: a raiz. As negações saem antes da concessão porque negação vence permissão.
    $negarRaiz = @($sid.Todos, $sid.Autenticados)
    if (-not [string]::IsNullOrWhiteSpace($UserSid)) { $negarRaiz = @($UserSid) + $negarRaiz }
    $plano += @{
        Phase       = 3
        Kind        = 'remove-deny'
        Folder      = $raiz
        DenySids    = $negarRaiz
        Title       = "Retirar negações de acesso da raiz '$raiz' (só se houver alguma)"
        FilePath    = $icacls
        Arguments   = @($raiz) + @($negarRaiz | ForEach-Object { '/remove:d'; "*$_" })
        Conditional = $true
    }
    $plano += @{
        Phase     = 3
        Kind      = 'grant'
        Folder    = $raiz
        Title     = "Permissões padrão da raiz '$raiz'"
        FilePath  = $icacls
        Arguments = @(
            $raiz, '/inheritance:r', '/grant:r',
            "*$($sid.Administradores):(OI)(CI)F",
            "*$($sid.Sistema):(OI)(CI)F",
            "*$($sid.Usuarios):(OI)(CI)RX",
            "*$($sid.Autenticados):(OI)(CI)(IO)M"
        )
    }
    $plano += @{
        Phase     = 3
        Kind      = 'grant-extra'
        Folder    = $raiz
        Title     = "Direito de criar arquivo na raiz '$raiz' para os Usuários Autenticados"
        FilePath  = $icacls
        Arguments = @($raiz, '/grant', "*$($sid.Autenticados):(AD)")
    }

    # ---- Fase 4: as seis pastas do sistema, uma a uma, com a tabela de esperados.
    foreach ($esp in @(Get-WinForgeAclExpected | Where-Object { $_.Direta })) {
        $pasta = [string]$esp.Path
        if (-not [string]::IsNullOrWhiteSpace([string]$esp.Dono)) {
            $plano += @{
                Phase       = 4
                Kind        = 'setowner'
                Folder      = $pasta
                Title       = "Dono padrão de '$pasta'"
                FilePath    = $icacls
                Arguments   = @($pasta, '/setowner', "*$([string]$esp.Dono)")
                Conditional = $true
            }
        }
        if (@($esp.Grant).Count) {
            $plano += @{
                Phase     = 4
                Kind      = 'grant'
                Folder    = $pasta
                Title     = "Permissões padrão de '$pasta'"
                FilePath  = $icacls
                Arguments = @($pasta, '/inheritance:r', '/grant:r') + @($esp.Grant | ForEach-Object { [string]$_ })
            }
        }
        if (@($esp.GrantExtra).Count) {
            $plano += @{
                Phase     = 4
                Kind      = 'grant-extra'
                Folder    = $pasta
                Title     = "Permissões herdáveis de '$pasta'"
                FilePath  = $icacls
                Arguments = @($pasta, '/grant') + @($esp.GrantExtra | ForEach-Object { [string]$_ })
            }
        }
        # O par de socorro da pasta, que só roda se a concessão responder "acesso negado" (código
        # 5). C:\Windows e C:\Program Files pertencem ao TrustedInstaller, e a ACE padrão dos
        # Administradores ali é 'M' - modificar, não controle total. 'M' não inclui WRITE_DAC:
        # elevado ou não, o administrador NÃO reescreve a DACL dessas pastas enquanto não for o
        # dono. Tomar a posse, repetir a concessão uma vez e DEVOLVER a posse ao dono padrão é o
        # caminho do próprio Windows - e devolver não é opcional, porque uma pasta do sistema que
        # fica com os Administradores como dona passa a aceitar alteração de qualquer processo
        # elevado, que é o oposto do que estes botões existem para restaurar.
        if (-not [string]::IsNullOrWhiteSpace([string]$esp.Dono)) {
            $plano += @{
                Phase       = 4
                Kind        = 'setowner-socorro'
                Folder      = $pasta
                Title       = "Posse de '$pasta' para os Administradores (só se a concessão responder acesso negado)"
                FilePath    = $icacls
                Arguments   = @($pasta, '/setowner', "*$($sid.Administradores)")
                Conditional = $true
            }
            $plano += @{
                Phase       = 4
                Kind        = 'setowner-devolver'
                Folder      = $pasta
                Title       = "Devolver a posse de '$pasta' ao dono padrão depois da segunda tentativa"
                FilePath    = $icacls
                Arguments   = @($pasta, '/setowner', "*$([string]$esp.Dono)")
                Conditional = $true
            }
        }
    }

    # ---- Fase 5: o perfil. Concessão na RAIZ do perfil primeiro, herança do conteúdo DEPOIS.
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        if (-not [string]::IsNullOrWhiteSpace($UserSid)) {
            $plano += @{
                Phase       = 5
                Kind        = 'setowner'
                Folder      = [string]$Profile
                Title       = "Dono da pasta '$Profile'"
                FilePath    = $icacls
                Arguments   = @([string]$Profile, '/setowner', "*$UserSid")
                Conditional = $true
            }
        }
        $negarPerfil = @($sid.Todos, $sid.Autenticados)
        if (-not [string]::IsNullOrWhiteSpace($UserSid)) { $negarPerfil = @($UserSid) + $negarPerfil }
        $plano += @{
            Phase       = 5
            Kind        = 'remove-deny'
            Folder      = [string]$Profile
            DenySids    = $negarPerfil
            Title       = "Retirar negações de acesso de '$Profile' (só se houver alguma)"
            FilePath    = $icacls
            Arguments   = @([string]$Profile) + @($negarPerfil | ForEach-Object { '/remove:d'; "*$_" })
            Conditional = $true
        }
        $grant = @([string]$Profile, '/inheritance:r', '/grant:r')
        if (-not [string]::IsNullOrWhiteSpace($UserSid)) { $grant += "*$($UserSid):(OI)(CI)F" }
        $grant += "*$($sid.Sistema):(OI)(CI)F"
        $grant += "*$($sid.Administradores):(OI)(CI)F"
        $plano += @{ Phase = 5; Kind = 'grant'; Folder = [string]$Profile; Title = "Permissões padrão da pasta '$Profile'"; FilePath = $icacls; Arguments = $grant }
        # '/inheritance:e' LIGA a herança em cada item de dentro, e é o que faz as três ACEs da raiz
        # do perfil descerem. O que os aplicativos puseram à mão continua lá: as ACEs de pacote em
        # AppData\Local\Packages e as do OneDrive são explícitas, e ligar herança não apaga nenhuma.
        #
        # Este passo NÃO tem executável nem vetor de argumentos, e é o terceiro do plano assim (os
        # outros dois são o 'sddl' e o 'scope' da fase 2). As chamadas saem de
        # Get-WinForgeAclInheritSteps, uma por pasta da lista que a fase 2 guardou, e quem as roda é
        # Invoke-WinForgeAclRestore.
        #
        # O '/inheritance:e /T /L' que morava aqui saiu pela mesma medição que tirou o '/T' da fase
        # 2: o '/L' fala do ALVO de cada item, não do caminho percorrido, e por isso NÃO poda a
        # travessia do '/T'. Ele descia pela junção de compatibilidade e pelo OneDrive até o limite
        # de 63 saltos de reparse, ligando herança FORA do perfil - em pasta que o backup não cobria
        # e que o usuário nem sabia estar no caminho. Com a lista, o conjunto alterado é exatamente
        # o conjunto guardado: o OneDrive em Sob Demanda fica fora do backup E fora desta fase, e as
        # pastas que a caminhada não conseguiu ler também - o par é consistente nas duas pontas, e é
        # o veredito de Get-WinForgeAclScopeVerdict que diz isso ao usuário.
        $plano += @{ Phase = 5; Kind = 'inherit-list'; Folder = [string]$Profile; Title = "Herança do conteúdo de '$Profile', pasta por pasta da lista guardada" }
    }
    $plano += @{
        Phase       = 6
        Kind        = 'takeown'
        Folder      = $raiz
        Title       = "Assumir a posse da raiz '$raiz' (só se a fase 3 responder acesso negado)"
        FilePath    = $takeown
        Arguments   = @('/F', $raiz, '/A')
        Conditional = $true
    }
    return @($plano)
}

function Select-WinForgeAclTargetedSteps {
    <#
    .SYNOPSIS
        Quais passos da fase 4 rodam, dado o relatório da verificação. Função pura.
    .DESCRIPTION
        A fase 4 não passa por todas as seis pastas: passa pelas que a verificação ACUSOU. Numa
        máquina em que só o ProgramData ficou torto, reescrever a lista de C:\Windows é criar risco
        onde não havia problema - e é onde mora o estrago irreversível deste botão.

        Duas regras, e é só isto que a função faz:

        - Pasta sem diferença, ou que não existe nesta máquina, não entra.
        - O par de socorro de posse ('setowner-socorro' e 'setowner-devolver') nunca entra: ele
          pertence a Invoke-WinForgeAclOwnerFallback e só roda com a resposta "acesso negado".
        - O '/setowner' só entra quando o relatório disse que o dono está fora do padrão
          ('OwnerOk' falso). Trocar o dono de uma pasta cujo dono já está certo não conserta nada e
          ainda quebra o '/restore' do Desfazer, que devolve DACL e não dono.

        Ser pura é o que permite provar as duas com um relatório montado na memória, sem tocar em
        pasta nenhuma da máquina de quem compila.
    .PARAMETER Plan
        A saída de Get-WinForgeAclRestorePlan.
    .PARAMETER Report
        O objeto de Get-WinForgeAclReport -AsObject (ou um equivalente montado no teste).
    .OUTPUTS
        O subconjunto dos passos da fase 4, na mesma ordem do plano.
    #>
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Report
    )

    $acusadas = @{}
    foreach ($item in @($Report.Items)) {
        if ($item.Missing) { continue }
        if (-not @($item.Differences).Count) { continue }
        $acusadas[([string]$item.Path).TrimEnd('\')] = [bool]$item.OwnerOk
    }
    $saida = @()
    foreach ($passo in @($Plan | Where-Object { [int]$_.Phase -eq 4 })) {
        $chave = ([string]$passo.Folder).TrimEnd('\')
        if (-not $acusadas.ContainsKey($chave)) { continue }
        if (([string]$passo.Kind -eq 'setowner') -and $acusadas[$chave]) { continue }
        # O par de socorro ('setowner-socorro'/'setowner-devolver') nunca entra na fila: ele é
        # procurado por Invoke-WinForgeAclOwnerFallback, e só quando a concessão responder código
        # 5. Trocar o dono de uma pasta do sistema sem essa resposta é criar o estrago à toa.
        if (([string]$passo.Kind) -like 'setowner-*') { continue }
        $saida += $passo
    }
    return @($saida)
}

function Invoke-WinForgeAclStreamStep {
    <#
    .SYNOPSIS
        Roda um passo do plano de permissões com a saída indo AO VIVO para o arquivo da janela.
        Devolve o código de saída.
    .DESCRIPTION
        É o que as fases 3 a 5 usam no lugar do par 'Invoke-WinForgeNativeCommand' + 'Write-Host
        ([string]$r.Text)'. Aquele par levava a saída inteira pela memória DUAS vezes: o
        'Out-String -Width 4096' junta o que o executável escreveu numa string só, e o Write-Host
        seguinte a repassa - uma linha de centenas de MB - pelo pipeline do passo. Medido: 135 MB de
        saída viraram 1.575 MB de pico, 11,7x, e é isso que enchia a memória da máquina no meio de
        uma restauração de permissões.

        Com -StreamTo cada linha vai do processo direto para o arquivo que a janela acompanha, e
        -NoCapture diz que ninguém quer o texto de volta: guardá-lo num StringBuilder seria juntar o
        volume inteiro na memória para descartá-lo no fim.

        O cabeçalho '> <exe> <args>' sai pela MESMA porta que a saída do processo (o escritor
        persistente do arquivo) e não por Write-Host: ele tem de aparecer antes da primeira linha do
        executável, e o Write-Host de um passo de função chega ao arquivo pelo pipeline do passo,
        que é outra fila.

        Sem -Path - isto é, fora de um comando com fluxo ao vivo - o passo volta ao caminho de
        captura e escreve por Write-Host. Não é zelo: '-StreamTo' vazio cai no caminho de captura, e
        '-NoCapture' ali ESTOURA por desenho (a guarda de Invoke-WinForgeNativeCommand recusa
        descartar um texto que não foi para lugar nenhum). Sem este ramo, uma chamada fora do fluxo
        derrubaria a restauração no primeiro passo em vez de rodá-lo; com ele, a saída aparece na
        única porta que sobrou.
    .PARAMETER Path
        O arquivo que a janela de saída está acompanhando ($sync.WinForgeStreamPath). Vazio, o passo
        roda pelo caminho de captura. Não confundir com '$Step.Path', que nos passos da fase 5 é a
        PASTA em que o icacls vai mexer.
    .PARAMETER Step
        Um passo do plano: FilePath, Arguments e, quando houver, Encoding (a dica de decodificação;
        sem ela vale 'oem', que é a do icacls e a do takeown).
    .OUTPUTS
        O código de saída do executável, ou 0 quando ele não devolveu nenhum.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Step,
        [string]$Path = ''
    )

    # Parado: nem o cabeçalho sai. Quem impede o processo de nascer é a conferência de ponto único
    # dentro de Invoke-WinForgeStreamedProcess - esta aqui é sobre o ARQUIVO não mostrar um
    # '> icacls <pasta>' para cada uma das centenas de pastas que nunca chegaram a ser tocadas.
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-WinForgeStreamCancelled -Path $Path)) {
        Write-WinForgeStreamCancelNote -Path $Path
        return 1223
    }
    $cabecalho = ("> {0} {1}" -f [string]$Step.FilePath, (@($Step.Arguments) -join ' ')).TrimEnd()
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host $cabecalho
        $semFluxo = Invoke-WinForgeNativeCommand -FilePath ([string]$Step.FilePath) -Arguments @($Step.Arguments) -Encoding ([string]$Step.Encoding)
        Write-Host ([string]$semFluxo.Text)
        if ($null -eq $semFluxo.ExitCode) { return 0 }
        return [int]$semFluxo.ExitCode
    }
    Write-WinForgeStreamLine -Path $Path -Text $cabecalho
    $comFluxo = Invoke-WinForgeNativeCommand -FilePath ([string]$Step.FilePath) -Arguments @($Step.Arguments) -StreamTo $Path -Encoding ([string]$Step.Encoding) -NoCapture
    if ($null -eq $comFluxo.ExitCode) { return 0 }
    return [int]$comFluxo.ExitCode
}

function Invoke-WinForgeAclRestore {
    <#
    .SYNOPSIS
        Devolve as permissões do disco do sistema ao padrão do Windows, guardando antes as atuais.
    .DESCRIPTION
        Conduz as fases de Get-WinForgeAclRestorePlan com as decisões que uma lista fixa de passos
        não sabe tomar:

        - Antes de tudo, a elevação. Sem ela nada roda: a pasta de backup nasceria com a identidade
          atual como dona e o icacls não escreveria em pasta nenhuma do sistema. A pergunta vem
          antes da primeira pasta ser criada, para a recusa não deixar rastro.
        - Depois da fase 1, o código do chkdsk. Diferente de zero significa erro no volume, e aí a
          função PARA sem alterar permissão nenhuma e manda agendar o chkdsk /f.
        - Nas fases 3 e 5, a existência de ACE de NEGAÇÃO. '/grant' adiciona permissão e não tira
          negação, e negação vence: sem o '/remove:d' antes, a fase termina com código 0, a lista
          fica com as ACEs certas e o acesso continua negado.
        - Na fase 4, o RELATÓRIO. Só as pastas que a verificação acusou são reescritas, e o
          '/setowner' só roda onde o dono está fora do padrão (Select-WinForgeAclTargetedSteps).
          Concessão que responde 5 numa pasta do TrustedInstaller cai em
          Invoke-WinForgeAclOwnerFallback: posse para os Administradores, uma segunda tentativa e a
          posse de volta ao dono padrão.
        - Depois da fase 3, o código do icacls. 5 é "acesso negado": a raiz pertence a alguém que
          nem o administrador alcança, e é o único caso em que o takeown da fase 6 roda - uma vez,
          só na raiz, sem recursão, seguido de UMA segunda tentativa da fase 3.

        - Na fase 5, a LISTA da fase 2. O passo 'inherit-list' não traz comando nenhum: o motor o
          expande em um 'icacls <pasta> /inheritance:e' por entrada de '$sync.WinForgeAclScope',
          na ordem ordinal que entrega pai antes de filho. Sem escopo publicado - isto é, sem
          backup do conteúdo - o conteúdo NÃO é alterado, e a fase diz isso em vez de seguir.
          O que se perde, escrito: arquivo solto dentro do perfil (o backup guarda pasta, não
          arquivo); ACE explícita de aplicativo, que '/inheritance:e' preserva de propósito; o
          OneDrive em Sob Demanda, que fica fora do backup E fora desta fase, então o par é
          consistente; e as pastas que a caminhada não conseguiu ler, que saem no veredito.

        A fase 2 é bloqueante das duas pontas: se a pasta protegida não passar na conferência, nada
        é alterado; se nenhum backup chegar a ser gravado, também não. E o passo do CONTEÚDO tem
        uma terceira porta: teto de caminhada estourado PARA a restauração inteira, porque nesse
        caso a lista sai vazia de propósito e seguir alteraria mais do que o backup cobre.
        Restaurar sem desfazer é o tipo de ajuda que transforma um problema em dois.

        O índice (JSON, na pasta protegida) É o backup: ele guarda, por pasta, a DACL em SDDL e o
        dono. O único arquivo separado do conjunto é o do CONTEÚDO do perfil - escrito pelo MOTOR,
        no formato do icacls -, e para ele o índice anota a pasta de onde o /restore tem de rodar
        (os nomes lá dentro são RELATIVOS a ela; adivinhar isso depois é o jeito de aplicar a DACL
        da pasta errada) e a impressão digital SHA-256, com que o Desfazer descobre que o arquivo
        deixou de ser o que esta fase gravou. Índice e arquivo são endurecidos
        (Protect-WinForgeSnapshotFile: dono Administradores, DACL fechada).

        O backup do conteúdo acontece SEMPRE - filtrado pela caminhada ele são 103,4 KB e 39
        segundos, e não há o que economizar deixando de fazê-lo. O que é opcional é o DESTINO: a
        caixa de Show-WinForgeAclBackupDestination, que roda na thread da janela antes do despacho,
        deixa o usuário mandar o ARQUIVO para outro disco, e o caminho chega aqui em
        $sync.WinForgeAclExternalRoot. O ÍNDICE não sai da pasta protegida em hipótese nenhuma: é
        ele que carrega os SDDL e a impressão digital, e é a impressão digital que substitui, no
        Desfazer, a proteção de pasta que um pen drive não tem. Destino que não passa por
        Test-WinForgeAclContentRoot no momento da gravação não cancela nada - o arquivo volta para a
        pasta protegida, com o motivo na tela.
    .PARAMETER DryRun
        Lista as fases, prefixadas com '[simulação] ' e com os passos condicionais marcados, e para
        por aí: nada roda, nenhuma pasta é criada, nenhum arquivo é gravado.
    .PARAMETER Probe
        Responde só à PRIMEIRA porta - a elevação - e volta, sem tocar em nada e sem passar pela
        trava de SelfTest. Existe para o -SelfTest provar, com a trava LIGADA, que a função consulta
        Test-WinForgeRepairElevated: antes disso o teste desligava $sync.SelfTest e chamava a função
        de verdade, apostando que nenhum efeito colateral tinha sido posto antes da checagem.
    .PARAMETER BackupRoot
        Pasta de backup alternativa. Existe para o teste; a conferência dela é a mesma da pasta
        padrão, sem afrouxamento nenhum.
    .OUTPUTS
        Com -DryRun, as linhas do plano. Com -Probe, @{ Elevated; Reason }. Sem eles, escreve o
        andamento (é um passo de fluxo ao vivo).
    #>
    param(
        [switch]$DryRun,
        [switch]$Probe,
        [string]$BackupRoot
    )

    $perfil = ''
    try { $perfil = [string][Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) } catch { $perfil = '' }
    $meuSid = ''
    try { $meuSid = [string][System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $meuSid = '' }
    $raiz = Get-WinForgeSystemDriveRoot
    $raizBackup = Get-WinForgeAclBackupRoot $BackupRoot
    $plano = @(Get-WinForgeAclRestorePlan -Profile $perfil -UserSid $meuSid -BackupRoot $raizBackup)

    if ($DryRun) {
        # Passo condicional aparece marcado: mais da metade do plano só roda em resposta a alguma
        # coisa (negação encontrada, dono fora do padrão, acesso negado), e uma simulação que
        # lista tudo em pé de igualdade promete estrago que não vai acontecer.
        return @($plano | ForEach-Object {
            $marca = if ($_.Conditional) { ' (condicional)' } else { '' }
            if ([string]$_.Kind -eq 'sddl') {
                ("[simulação] Fase {0}{1}: guardar a lista e o dono de '{2}' no índice (SDDL)" -f $_.Phase, $marca, $_.Path)
            } elseif ([string]$_.Kind -eq 'scope') {
                # Sem FilePath e sem Arguments: quem caminha e quem grava é o motor. A simulação diz
                # o que vai ser feito, e não uma linha de comando que não existe.
                ("[simulação] Fase {0}{1}: caminhar '{2}' e guardar em '{3}' as pastas com herança bloqueada (o /restore roda de '{4}')" -f $_.Phase, $marca, $_.Path, $_.Backup, $_.Target)
            } elseif ([string]$_.Kind -eq 'inherit-list') {
                # Também sem FilePath: quantas chamadas vão sair daqui só se sabe com a lista da
                # fase 2 na mão, e a simulação roda antes dela. Dizer o que vai ser feito é honesto;
                # inventar uma linha de comando com '*' seria desenhar de volta o '/T' que saiu.
                ("[simulação] Fase {0}{1}: ligar a herança em cada pasta de '{2}' que a fase 2 guardou, uma chamada '{3} <pasta> /inheritance:e' por entrada (sem '/T', sem sair do perfil)" -f $_.Phase, $marca, $_.Folder, (Get-WinForgeSystemExe -Name 'icacls.exe'))
            } else {
                ("[simulação] Fase {0}{1}: {2} {3}" -f $_.Phase, $marca, $_.FilePath, (@($_.Arguments) -join ' ')).TrimEnd()
            }
        })
    }
    if ($Probe) {
        # Antes da trava de SelfTest de propósito: -Probe não escreve, não cria pasta e não roda
        # passo nenhum. Ele responde o que a primeira porta responderia, e é só isso.
        $elevado = [bool](Test-WinForgeRepairElevated)
        return @{ Elevated = $elevado; Reason = $(if ($elevado) { '' } else { 'Esta ação precisa do WinForge aberto como administrador. Nada foi alterado e nenhuma pasta foi criada.' }) }
    }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeAclRestore'

    # Para onde as fases 3 a 5 mandam a saída dos executáveis. Esta função roda como um passo do
    # tipo 'Function', que não recebe argumento nenhum: o arquivo que a janela acompanha chega por
    # $sync.WinForgeStreamPath, escrito pelo corpo da runspace. Sem ele (chamada fora de um comando
    # com fluxo ao vivo) os passos voltam ao caminho de captura - ver Invoke-WinForgeAclStreamStep.
    $fluxo = ''
    try { $fluxo = [string]$sync.WinForgeStreamPath } catch { $fluxo = '' }
    # Onde o Parar pegou, e o que já estava pronto quando ele pegou. Os dois são anotados pelos
    # laços, à medida que as coisas acontecem: adivinhar isso no fim daria um relato que descreve o
    # que o programa acha, e não o que ele fez.
    $faseParada = 0
    # DUAS listas, e elas não se misturam: a da fase 4 tem pasta do SISTEMA, a da fase 5 tem pasta
    # de dentro do PERFIL. Com uma só, parar durante a fase 5 fazia o relato dizer "2 pasta(s) de
    # dentro já tinham recebido a herança" citando C:\Windows e C:\Program Files.
    $pastasFeitas = @()
    $pastasFase5 = @()

    # A elevação vem antes de QUALQUER efeito colateral, inclusive o de criar a pasta de backup:
    # sem elevação ela nasceria com a identidade atual como dona e ficaria plantada, fazendo a
    # conferência recusar todas as restaurações seguintes desta máquina.
    if (-not (Test-WinForgeRepairElevated)) {
        Write-Error 'Esta ação precisa do WinForge aberto como administrador. Nada foi alterado e nenhuma pasta foi criada.'
        return
    }
    # A segunda porta, e ela vem antes de criar pasta e antes do chkdsk: um backup pendente significa
    # que o disco já está alterado em relação a ele, e restaurar por cima gravaria o índice do disco
    # ALTERADO. Foi assim que a 1.7.0 destruiu o backup bom - ver Test-WinForgeAclRestoreAllowed.
    # Perguntar depois de qualquer trabalho seria perguntar tarde.
    $permitido = Test-WinForgeAclRestoreAllowed -Root $BackupRoot
    if (-not $permitido.Ok) {
        Write-Error "Nada foi alterado: $($permitido.Reason)"
        return
    }
    if ([string]::IsNullOrWhiteSpace($perfil) -or [string]::IsNullOrWhiteSpace($meuSid)) {
        Write-Error 'Não foi possível descobrir a pasta e o SID do usuário atual. Nada foi alterado.'
        return
    }
    $conf = Confirm-WinForgeAclBackupRoot -Root $BackupRoot
    if (-not $conf.Ok) {
        Write-Error "A pasta de backup de permissões não é confiável ($($conf.Reason)). Nada foi alterado - sem backup não há Desfazer."
        return
    }
    Write-Host "Backup das permissões atuais em: $($conf.Path)"

    # ---- Fase 1: o disco antes das permissões.
    $fase1 = @($plano | Where-Object { [int]$_.Phase -eq 1 })[0]
    Write-Host ''
    Write-Host "Fase 1 de 6 - $($fase1.Title). Num disco grande isso leva minutos."
    # Também pelo fluxo ao vivo, e aqui o motivo não é memória: são os MINUTOS. O chkdsk conta o
    # progresso em estágios, e segurar esse texto até o fim é a janela parada justamente no passo
    # mais longo do botão.
    $codigo1 = [int](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $fase1)
    if ($codigo1 -ne 0) {
        Write-Error "O chkdsk terminou com código $($codigo1): o volume tem erro de sistema de arquivos. PARADO antes de alterar qualquer permissão - use o botão 'Agendar chkdsk /f na próxima reinicialização', reinicie e volte aqui."
        return
    }

    # ---- Fase 2: o desfazer, antes de qualquer alteração.
    # O índice é o backup, e não só o mapa dele: a lista e o dono de cada pasta viajam DENTRO dele,
    # como SDDL. O arquivo de icacls existe para um alvo só, o conteúdo do perfil.
    $indice = New-Object System.Collections.Generic.List[object]
    $gravados = 0
    $fora = @()
    # Zerados a cada rodada. A janela vive numa sessão só: sobra de uma restauração anterior faria
    # a fase 5 alterar o escopo de ANTES e o veredito falar de pastas de outra rodada.
    $sync.WinForgeAclScope = $null
    $sync.WinForgeAclDenied = @{ Count = 0; Paths = @() }
    foreach ($passo in @($plano | Where-Object { [int]$_.Phase -eq 2 })) {
        Write-Host ''
        Write-Host "Fase 2 de 6 - $($passo.Title)"
        if ([string]$passo.Kind -eq 'sddl') {
            $seg = Get-WinForgeAclFolderSecurity -Path ([string]$passo.Path)
            if (-not $seg.Ok) {
                Write-Warning "A lista de '$($passo.Path)' não pôde ser lida ($($seg.Reason)); esta pasta fica de fora do Desfazer."
                $fora += [string]$passo.Path
                continue
            }
            Write-Host "Dono: $($seg.Owner). Lista guardada no índice."
            $indice.Add([pscustomobject]@{
                Path     = [string]$passo.Path
                Sddl     = [string]$seg.Sddl
                Owner    = [string]$seg.Owner
                OwnerSid = [string]$seg.OwnerSid
                File     = ''
                Target   = ''
            })
            $gravados++
            continue
        }
        # ---- O passo 'scope': o CONTEÚDO do perfil, caminhado e gravado pelo MOTOR. O
        # 'icacls /save /T' saiu daqui - a medição que o tirou está em Get-WinForgeAclRestorePlan.
        #
        # '$parcial' só recebe o caminho no instante em que a gravação começa. Antes disso não há
        # arquivo desta chamada no disco, e o 'finally' não tem o que apagar.
        $parcial = ''
        try {
            $escopo = Get-WinForgeAclContentScope -Path ([string]$passo.Path)
            # Teto estourado NÃO tem "continuar mesmo assim". A caminhada devolve a lista vazia de
            # propósito (§1.6), e seguir daqui alteraria o perfil com um backup que cobre menos do
            # que a alteração - o Desfazer que não desfaz, de novo. Para a restauração inteira.
            if (-not $escopo.Ok) {
                Write-Error "A cópia das permissões do conteúdo de '$($passo.Path)' não ficou pronta: $($escopo.Reason) Nada foi alterado."
                return
            }
            # O que a caminhada NÃO conseguiu ler muda o veredito do fim, e fica guardado antes de
            # qualquer gravação: ele vale mesmo que o arquivo não chegue a ser escrito.
            $sync.WinForgeAclDenied = @{ Count = [int]$escopo.Denied; Paths = @($escopo.DeniedPaths) }
            Write-Host ("{0} pasta(s) com herança bloqueada, de {1} visitada(s); {2} atalho(s) de pasta não seguidos e {3} não lida(s), em {4}s." -f @($escopo.Entries).Count, $escopo.Scanned, $escopo.Reparse, $escopo.Denied, $escopo.Seconds)

            # Daqui para baixo é uma corrente: o primeiro elo que falhar escreve '$motivo', e todos
            # os seguintes ficam de fora. Um conteúdo sem backup é um conteúdo que também não vai
            # ser alterado - o escopo só é publicado em '$sync.WinForgeAclScope' no fim, com o
            # arquivo gravado, protegido e conferido.
            $motivo = ''
            if (-not @($escopo.Entries).Count) {
                $motivo = "nenhuma pasta de '$($passo.Path)' está com a herança bloqueada, então não há conteúdo a guardar"
            }
            # Ordem de ACE: o SDDL da caminhada vem do .NET, em ordem CANÔNICA - negação antes de
            # permissão. Numa lista só de permissão isso é indiferente; numa lista com NEGAÇÃO não
            # é, porque devolver a ordem canônica a uma pasta que não estava canônica faz a negação
            # passar a vencer, e o Desfazer TRANCARIA o usuário. Para essas entradas o texto sai do
            # próprio icacls, uma chamada por pasta e sem '/T'. Medido: 0 das 338 do perfil real
            # negam, então normalmente nada disto roda.
            if (-not $motivo -and [int]$escopo.Deny -gt 0) {
                $negadas = @(@($escopo.Entries) | Where-Object { $_.Deny })
                # Uma chamada de processo por pasta: 200 são segundos, e é o mesmo teto que
                # 'DeniedPaths' já usa. Acima disso a fase voltaria a levar minutos, que é
                # exatamente o travamento que este trabalho existe para tirar do caminho.
                if ($negadas.Count -gt 200) {
                    $motivo = "$($negadas.Count) pastas do perfil têm negação de acesso, mais do que as 200 que dá para reler uma a uma sem travar a máquina"
                } else {
                    foreach ($e in $negadas) {
                        $abs = Join-Path ([string]$passo.Target) ([string]$e.Name)
                        $ordem = Get-WinForgeAclIcaclsSddl -Path $abs -WorkFile ([string]$passo.Backup + '.ordem')
                        if (-not $ordem.Ok) {
                            $motivo = "a ordem das permissões de '$abs' não pôde ser lida ($($ordem.Reason))"
                            break
                        }
                        $e.Sddl = [string]$ordem.Sddl
                    }
                }
            }
            # ---- O DESTINO do arquivo. O ÍNDICE fica sempre na pasta protegida; só o arquivo de
            # conteúdo sai, e só se o usuário tiver pedido isso na caixa que rodou na thread da
            # janela. O caminho vem de '$sync.WinForgeAclExternalRoot' e é CONFERIDO DE NOVO aqui:
            # entre a caixa e este ponto passam o chkdsk e a caminhada do perfil, e um pen drive
            # tirado nesse intervalo não pode virar um arquivo gravado em lugar nenhum.
            #
            # Destino recusado agora NÃO cancela o backup: ele volta para a pasta protegida, com o
            # motivo na tela. O backup é obrigatório - é a rede de segurança de tudo o que vem
            # depois -, e trocar "onde" por "se" seria deixar o disco sem Desfazer por causa de uma
            # preferência.
            $destinoArquivo = [string]$passo.Backup
            $externoArquivo = ''
            $externoEscolhido = ''
            try { $externoEscolhido = [string]$sync.WinForgeAclExternalRoot } catch { $externoEscolhido = '' }
            if (-not $motivo -and -not [string]::IsNullOrWhiteSpace($externoEscolhido)) {
                $julgado = Test-WinForgeAclContentRoot -Path $externoEscolhido -ProfilePath $perfil
                if ($julgado.Ok) {
                    # A FOLHA do nome planejado, e nunca um nome montado aqui: é ela que o índice
                    # anota e é por ela que Get-WinForgeAclBackupInventory reconhece o arquivo.
                    $destinoArquivo = [string](Join-Path ([string]$julgado.Path) ([string](Split-Path -Leaf ([string]$passo.Backup))))
                    $externoArquivo = $destinoArquivo
                    Write-Host "O backup do conteúdo vai para '$destinoArquivo', fora da pasta protegida do WinForge."
                    Write-Host ([string]$julgado.Warning)
                } else {
                    Write-Warning "A pasta escolhida para guardar o backup não serve mais ($($julgado.Reason)). O arquivo vai para a pasta protegida do WinForge: o backup acontece de todo jeito."
                }
            }
            # O espaço é conferido ANTES da primeira letra ir para o disco: encher o volume no meio
            # do arquivo deixaria um backup pela metade, e é ele que o Desfazer leria como bom. A
            # pergunta é sobre o volume do DESTINO, que pode não ser o do %ProgramData%.
            if (-not $motivo) {
                $esp = Test-WinForgeAclFreeSpace -Path $destinoArquivo -Bytes ([long]$escopo.Bytes)
                if (-not $esp.Ok) { $motivo = $esp.Reason }
            }
            if (-not $motivo) {
                $parcial = $destinoArquivo
                $grav = Write-WinForgeAclContentBackup -Path $parcial -Entries @($escopo.Entries)
                if (-not $grav.Ok) { $motivo = $grav.Reason }
            }
            # O endurecimento vale para o arquivo esteja ele onde estiver - dono Administradores e
            # DACL fechada são propriedade do ARQUIVO, não da pasta, e num volume NTFS externo eles
            # pegam do mesmo jeito. Não é o mesmo que a pasta protegida (lá a pasta em si também
            # recusa quem não devia), e é por isso que o índice guarda o SHA-256: o que o
            # endurecimento não alcança fora do %ProgramData% a impressão digital denuncia.
            if (-not $motivo) {
                $prot = Protect-WinForgeSnapshotFile -Path $parcial
                if (-not $prot.Hardened) { $motivo = "o backup não pôde ser protegido ($($prot.Reason))" }
            }
            # A impressão digital vai para o índice: é com ela que o Desfazer descobre, antes de
            # aplicar coisa alguma, que o arquivo não é mais o que esta fase gravou.
            $impressao = ''
            if (-not $motivo) {
                $hash = Get-WinForgeAclContentHash -Path $parcial
                if (-not $hash.Ok) { $motivo = "a impressão digital do backup não pôde ser calculada ($($hash.Reason))" }
                else { $impressao = [string]$hash.Hash }
            }
            if ($motivo) {
                Write-Warning "O backup do conteúdo de '$($passo.Path)' não foi gravado ($motivo); o conteúdo desta pasta fica de fora do Desfazer e NÃO será alterado."
                $fora += ("conteúdo de " + [string]$passo.Path)
            } else {
                Write-Host "$($grav.Count) entrada(s) guardadas em $($grav.Bytes) byte(s)."
                $indice.Add([pscustomobject]@{
                    Path         = [string]$passo.Path
                    Sddl         = ''
                    Owner        = ''
                    OwnerSid     = ''
                    File         = [string](Split-Path -Leaf $parcial)
                    Target       = [string]$passo.Target
                    Sha256       = $impressao
                    # Vazio quando o arquivo ficou na pasta protegida. Preenchido, é o caminho
                    # COMPLETO de fora: o Desfazer usa ele, e 'File' continua sendo só a folha,
                    # que é por onde Get-WinForgeAclBackupInventory reconhece o arquivo citado.
                    ExternalPath = [string]$externoArquivo
                })
                # Publicado só agora, e é o contrato com a fase 5: o que está aqui é exatamente o
                # que o arquivo no disco cobre. Sem backup, sem escopo - e sem escopo a fase 5 não
                # toca no conteúdo.
                $sync.WinForgeAclScope = $escopo
                $parcial = ''
                $gravados++
            }
        } finally {
            # O descarte do arquivo parcial mora AQUI, e não no fim de cada ramo: assim ele roda
            # também quando a fase aborta no meio (o 'return' lá de cima passa por este finally) e
            # quando alguma chamada estoura sem aviso. Antes, o descarte ficava dentro do laço e
            # simplesmente não acontecia nesses dois casos.
            if ($parcial -and (Test-Path -LiteralPath $parcial)) { Remove-Item -LiteralPath $parcial -Force -ErrorAction SilentlyContinue }
        }
    }
    if ($gravados -eq 0) {
        Write-Error 'Nenhum backup de permissões pôde ser gravado. Nada foi alterado.'
        return
    }
    # PARAR na fase 2, e esta é a única porta em que ele desfaz alguma coisa: o índice ainda NÃO foi
    # escrito, e escrevê-lo agora criaria um conjunto de Desfazer que aponta para um backup que
    # ninguém vai usar - o disco não foi alterado, e a restauração seguinte seria recusada por
    # "conjunto pendente". Os arquivos de conteúdo já gravados saem junto, pelo mesmo motivo.
    if (Test-WinForgeStreamCancelled -Path $fluxo) {
        foreach ($item in @($indice)) {
            $soltoParcial = [string]$item.ExternalPath
            if ([string]::IsNullOrWhiteSpace($soltoParcial) -and -not [string]::IsNullOrWhiteSpace([string]$item.File)) { $soltoParcial = Join-Path $conf.Path ([string]$item.File) }
            if (-not [string]::IsNullOrWhiteSpace($soltoParcial) -and (Test-Path -LiteralPath $soltoParcial)) { Remove-Item -LiteralPath $soltoParcial -Force -ErrorAction SilentlyContinue }
        }
        Write-Host ''
        Write-Host 'Parado a pedido durante a cópia das permissões. O disco NÃO foi alterado, e o backup parcial foi descartado: não há conjunto novo na fila do Desfazer. Pode rodar a restauração de novo quando quiser.'
        return
    }
    $carimbo = (Get-Date).ToString('yyyyMMdd-HHmmss')
    # JSON, e não mais '<arquivo>|<pasta>': o índice passou a carregar a lista e o dono de cada
    # pasta, e um formato de duas colunas não comporta isso sem inventar separador novo.
    $arquivoIndice = Join-Path $conf.Path ("acl-index-{0}.json" -f $carimbo)
    # 'Consumed' nasce falso e vira verdadeiro num Desfazer sem recusa: é ele que tira o conjunto da
    # fila e deixa a próxima restauração começar. 'Origin' é a máquina e o perfil que gravaram - o
    # Desfazer confere os dois antes de aplicar SDDL nenhum, porque descritor de outra máquina traz
    # SID que não existe aqui e trancaria o perfil.
    Set-Content -LiteralPath $arquivoIndice -Value ([pscustomobject]@{ Stamp = $carimbo; Consumed = $false; Origin = (New-WinForgeAclIndexOrigin); Items = @($indice) } | ConvertTo-Json -Depth 5) -Encoding UTF8 -ErrorAction Stop
    $protIndice = Protect-WinForgeSnapshotFile -Path $arquivoIndice
    if (-not $protIndice.Hardened) {
        Remove-Item -LiteralPath $arquivoIndice -Force -ErrorAction SilentlyContinue
        Write-Error "O índice do backup não pôde ser protegido ($($protIndice.Reason)). Nada foi alterado - sem o índice não há Desfazer."
        return
    }
    Write-Host ''
    Write-Host "$gravados item(ns) guardados no conjunto $carimbo. O botão Desfazer usa exatamente este conjunto."
    if ($fora.Count) { Write-Warning ("Fora do Desfazer: {0}." -f ($fora -join '; ')) }

    # ---- O retrato de antes. É ele que diz QUAIS pastas a fase 4 reescreve, e é o mesmo texto que
    # o botão Verificar mostra - tirado aqui, com o backup já gravado e nada ainda alterado.
    $relatorio = Get-WinForgeAclReport -AsObject
    Write-Host ''
    Write-Host "Verificação antes de alterar: $($relatorio.Differences) diferença(s) em relação ao padrão do Windows."

    # ---- Fase 3 (e, só em acesso negado, a 6 seguida de uma segunda tentativa da 3).
    # AQUI a escrita começa de verdade, e é a única linha que liga esta chave. Ela é o que faz a
    # confirmação do Parar dizer a verdade: até esta linha nada foi alterado e parar é de graça; da
    # próxima em diante o disco muda, e o backup da fase 2 é o que cobre a mudança. Quem apaga é o
    # 'finally' do corpo da runspace, junto com o nome do comando.
    $sync.WinForgeStreamWriting = $true
    $fase3 = @($plano | Where-Object { [int]$_.Phase -eq 3 -and [string]$_.Kind -eq 'grant' })[0]
    Invoke-WinForgeAclDenyRemoval -Plan $plano -Phase 3 -Path $raiz
    Write-Host ''
    Write-Host "Fase 3 de 6 - $($fase3.Title)"
    $codigo3 = [int](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $fase3)
    if ($codigo3 -eq 5) {
        $fase6 = @($plano | Where-Object { [int]$_.Phase -eq 6 })[0]
        Write-Host ''
        Write-Host "Acesso negado na raiz. Fase 6 de 6 - $($fase6.Title)"
        [void](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $fase6)
        Write-Host 'Segunda e última tentativa das permissões da raiz.'
        $codigo3 = [int](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $fase3)
    }
    if ($codigo3 -ne 0) {
        # Segue assim mesmo: as fases 4 e 5 consertam as pastas do sistema e o perfil
        # independentemente da raiz, e parar aqui deixaria a máquina no meio do caminho.
        Write-Error "As permissões da raiz não puderam ser aplicadas (código $codigo3). As fases seguintes continuam."
    } else {
        foreach ($passo in @($plano | Where-Object { [int]$_.Phase -eq 3 -and [string]$_.Kind -eq 'grant-extra' })) {
            Write-Host "Fase 3 de 6 - $($passo.Title)"
            $codigoExtra = [int](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $passo)
            # SAI na primeira recusa, como os outros laços: seguir renderia um 'terminou com código
            # 1223' por passo restante - erro espúrio para quem só clicou em Parar.
            if ($codigoExtra -eq 1223) { if ($faseParada -eq 0) { $faseParada = 3 }; break }
            if ($codigoExtra -ne 0) { Write-Error "Esta etapa terminou com código $codigoExtra." }
        }
    }

    # ---- Fase 4: as pastas do sistema que a verificação acusou, uma a uma. Pasta no padrão não é
    # tocada: reescrever a lista de C:\Windows numa máquina em que ela está certa é criar o
    # problema que este botão existe para resolver.
    $fase4 = @(Select-WinForgeAclTargetedSteps -Plan $plano -Report $relatorio)
    Write-Host ''
    if (-not $fase4.Count) {
        Write-Host 'Fase 4 de 6 - nenhuma pasta do sistema está fora do padrão; nada a reescrever aqui.'
    } else {
        $quantas = @($fase4 | ForEach-Object { [string]$_.Folder } | Sort-Object -Unique).Count
        Write-Host "Fase 4 de 6 - $quantas pasta(s) do sistema fora do padrão."
        foreach ($passo in $fase4) {
            Write-Host ''
            Write-Host "Fase 4 de 6 - $($passo.Title)"
            $codigo4 = [int](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $passo)
            # Parado: o laço SAI. Seguir para o passo seguinte só produziria mais uma recusa e mais
            # um "Esta etapa terminou com código 1223" por pasta restante - uma lista de erros para
            # quem apenas clicou em Parar. A fase é anotada aqui, no laço, e não adivinhada no fim,
            # e a pasta deste passo não entra na lista do que ficou pronto: ele não chegou a rodar.
            if ($codigo4 -eq 1223) { if ($faseParada -eq 0) { $faseParada = 4 }; break }
            if (($codigo4 -eq 5) -and ([string]$passo.Kind -ne 'setowner')) {
                $codigo4 = [int](Invoke-WinForgeAclOwnerFallback -Plan $plano -Step $passo -StreamPath $fluxo)
            }
            if ($codigo4 -ne 0) { Write-Error "Esta etapa terminou com código $codigo4." }
            else { $pastasFeitas += [string]$passo.Folder }
        }
    }

    # ---- Fase 5: a pasta do usuário. A ordem é dependência: dono, negações, concessão na raiz do
    # perfil e SÓ ENTÃO a herança do conteúdo, que é o que faz as três ACEs descerem.
    $perfilOk = $true
    foreach ($item in @($relatorio.Items)) {
        if (([string]$item.Path).TrimEnd('\') -eq ([string]$perfil).TrimEnd('\')) { $perfilOk = [bool]$item.OwnerOk }
    }
    foreach ($passo in @($plano | Where-Object { [int]$_.Phase -eq 5 })) {
        if ([string]$passo.Kind -eq 'setowner') {
            if ($perfilOk) { continue }
            Write-Host ''
            Write-Host "Fase 5 de 6 - $($passo.Title)"
        } elseif ([string]$passo.Kind -eq 'remove-deny') {
            Invoke-WinForgeAclDenyRemoval -Plan $plano -Phase 5 -Path $perfil
            continue
        } elseif ([string]$passo.Kind -eq 'inherit-list') {
            # A herança é ligada pasta por pasta, na lista que a fase 2 guardou - e em nenhuma
            # outra. É aqui que "guardado = alterado" deixa de ser promessa: o escopo em
            # '$sync.WinForgeAclScope' só foi publicado com o arquivo de backup gravado, protegido
            # e conferido, então sem ele não houve Desfazer e o conteúdo não pode ser tocado.
            $escopo5 = $sync.WinForgeAclScope
            $alvo5 = ''
            foreach ($p2 in @($plano | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'scope' })) {
                if (([string]$p2.Path).TrimEnd('\') -eq ([string]$perfil).TrimEnd('\')) { $alvo5 = [string]$p2.Target }
            }
            Write-Host ''
            if ($null -eq $escopo5 -or [string]::IsNullOrWhiteSpace($alvo5)) {
                Write-Warning "O conteúdo de '$perfil' ficou fora do Desfazer, então fica fora daqui também: a herança NÃO foi ligada em pasta nenhuma de dentro. A pasta do perfil em si continua com as permissões que esta fase acabou de aplicar."
                continue
            }
            $passos5 = @(Get-WinForgeAclInheritSteps -Root $alvo5 -Entries @($escopo5.Entries))
            Write-Host "Fase 5 de 6 - $($passo.Title): $($passos5.Count) pasta(s)."
            # Cada chamada vai para o arquivo pelo fluxo ao vivo, com o cabeçalho '> icacls ...'. São
            # centenas de linhas, e elas são o ponto: este laço leva dezenas de segundos, e uma
            # janela parada é indistinguível de uma janela travada - que foi a queixa que trouxe este
            # trabalho. O '/Q' dos argumentos mantém o icacls calado quando dá certo, então o que
            # cresce ali é uma linha por pasta, e não a árvore inteira. O RESUMO continua sendo o que
            # se lê no fim; o que FALHOU sai também aqui, com a pasta e o código.
            #
            # O código de saída só existe porque o '/C' saiu do vetor - com ele, MEDIDO, uma pasta
            # que não existe mais sai com 0 e este laço não teria sinal nenhum. Mas ele NÃO separa
            # "sumiu" de "falhou": pasta inexistente sai 2, pai inexistente sai 3, e a caminhada da
            # fase 2 põe pai e filho os DOIS nesta lista. Quem separa é a EXISTÊNCIA da pasta -
            # Get-WinForgeAclInheritOutcome, com o porquê medido lá.
            $falhas5 = 0
            $sumidas5 = 0
            $canceladas5 = 0
            $vistas5 = 0
            foreach ($p5 in $passos5) {
                $vistas5++
                $codigo5 = [int](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $p5)
                $veredito5 = [string](Get-WinForgeAclInheritOutcome -Path ([string]$p5.Path) -ExitCode $codigo5)
                if ($veredito5 -eq 'ok') { $pastasFase5 += [string]$p5.Path; continue }
                # Pasta que não chegou a ser tocada depois do Parar. O laço SAI na primeira: da
                # primeira recusa em diante todas as outras seriam recusa também, e contá-las uma a
                # uma é trabalho para dizer o que já se sabe. As que sobraram entram no resumo pela
                # subtração, e não entram na conta das falhas - quem pediu para parar não errou nada.
                if ($veredito5 -eq 'cancelada') { $canceladas5 = $passos5.Count - $vistas5 + 1; break }
                if ($veredito5 -eq 'sumida') { $sumidas5++; continue }
                $falhas5++
                # Sem o texto do icacls: ele acabou de sair no arquivo, logo acima desta linha, e
                # repeti-lo aqui seria trazer de volta pela memória o que o fluxo ao vivo tirou dela.
                Write-Host ("  '{0}': código {1}." -f $p5.Path, $codigo5)
            }
            $resumo5 = "Herança ligada em $($passos5.Count - $falhas5 - $sumidas5 - $canceladas5) de $($passos5.Count) pasta(s) que o backup cobre."
            if ($sumidas5) { $resumo5 += " $sumidas5 já não existia(m) desde a cópia das permissões - não havia o que ligar nelas." }
            if ($canceladas5) { $resumo5 += " $canceladas5 não foram tocadas porque você pediu para parar; elas continuam como estavam, e o backup delas segue no conjunto do Desfazer."; if ($faseParada -eq 0) { $faseParada = 5 } }
            Write-Host $resumo5
            if ($falhas5) { Write-Error "A herança não pôde ser ligada em $falhas5 pasta(s) do perfil; elas continuam como estavam, e o backup delas segue no conjunto do Desfazer." }
            continue
        } else {
            Write-Host ''
            Write-Host "Fase 5 de 6 - $($passo.Title)"
        }
        $codigoPasso = [int](Invoke-WinForgeAclStreamStep -Path $fluxo -Step $passo)
        # Mesma regra dos outros laços: na primeira recusa o laço SAI, em vez de acumular um erro
        # espúrio por passo que ninguém tentou.
        if ($codigoPasso -eq 1223) { if ($faseParada -eq 0) { $faseParada = 5 }; break }
        if ($codigoPasso -ne 0) { Write-Error "Esta etapa terminou com código $codigoPasso." }
    }

    # ---- PARADO A PEDIDO: o relato da parada sai NO LUGAR do veredito. 'Concluído' depois de uma
    # interrupção seria o programa dizendo que terminou o que foi interrompido - e o que a pessoa
    # precisa saber é outra coisa: o disco ficou num estado MISTO, e qual.
    if ($faseParada -gt 0 -or (Test-WinForgeStreamCancelled -Path $fluxo)) {
        if ($faseParada -eq 0) { $faseParada = 5 }
        Write-Host ''
        Write-Host (Get-WinForgeAclStopReport -Phase $faseParada -Folders @(@(if ($faseParada -eq 5) { $pastasFase5 } else { $pastasFeitas }) | Sort-Object -Unique) -Profile $perfil)
        return
    }

    # ---- O veredito. O cabeçalho MUDA quando alguma pasta não pôde ser lida: a fase 5 percorre só
    # a lista guardada, então o que ficou de fora do backup ficou também de fora do conserto, e
    # dizer 'Concluído' ali seria dizer que consertou o que não consertou.
    $ressalvas = $sync.WinForgeAclDenied
    $veredito = Get-WinForgeAclScopeVerdict -Scope @{ Denied = [int]$ressalvas.Count; DeniedPaths = @($ressalvas.Paths) }
    Write-Host ''
    Write-Host "$($veredito.Header). Reinicie o computador antes de julgar o resultado: serviços e programas já abertos seguem com as permissões antigas em cache."
    if (-not [string]::IsNullOrEmpty([string]$veredito.Text)) {
        Write-Host ''
        Write-Host ([string]$veredito.Text)
        Write-Host ''
    }
    Write-Host 'Depois de reiniciar, use "Permissões do disco C: - Verificar" para conferir, e "Desfazer (restaurar backup)" se algo tiver ficado pior.'
    Write-Host 'O Desfazer devolve a lista de permissões de cada pasta guardada e TENTA devolver o dono. Devolver a posse ao TrustedInstaller nem sempre é possível, mesmo com o WinForge como administrador: quando falhar, o Desfazer diz em qual pasta.'
}

function Get-WinForgeAclOwnerPendingPath {
    <#
    .SYNOPSIS
        O caminho do marcador de posse pendente. Só calcula.
    .DESCRIPTION
        Mora em '%ProgramData%\WinForge', ao lado da pasta de backup e pelo mesmo motivo: ele fala de
        uma pasta do SISTEMA, e o aviso tem de aparecer para qualquer usuário da máquina, não só
        para quem clicou no botão.

        O '-Root' existe pela mesma razão de Get-WinForgeAclBackupRoot - sem ele o -SelfTest
        escreveria em '%ProgramData%\WinForge' de verdade.
    .OUTPUTS
        O caminho do arquivo.
    #>
    param([string]$Root)

    $alvo = if ($Root) { $Root } else { (Join-Path (Get-WinForgeMachineDataRoot) 'WinForge') }
    try { $alvo = [System.IO.Path]::GetFullPath($alvo) } catch { }
    return (Join-Path $alvo 'acl-posse-pendente.json')
}

function Get-WinForgeAclStopReport {
    <#
    .SYNOPSIS
        O relato que fecha uma restauração de permissões interrompida a pedido. Função pura, só texto.
    .DESCRIPTION
        Parar no meio de um reparo de permissões deixa o disco num estado MISTO, e o que a pessoa
        precisa saber é exatamente qual: o que foi alterado, o que não foi, e que o backup cobre a
        primeira parte. Um "cancelado" seco deixaria alguém sem saber se pode reiniciar a máquina.

        A frase muda com a FASE porque o estado é diferente em cada uma:

        - Fase 4 (pastas do sistema, uma a uma): as pastas que já passaram estão no padrão, as
          demais ficaram como estavam. O backup da Fase 2 é anterior a todas, então o Desfazer volta
          o conjunto inteiro.
        - Fase 5 (o perfil): a raiz do perfil já foi concedida e a herança do conteúdo ficou pela
          metade. Aqui a saída natural é RODAR DE NOVO - a restauração é idempotente, e terminar o
          que faltou é mais simples do que desfazer tudo.

        As pastas citadas são as que ENTRARAM, e não uma lista escrita à mão: relatar pasta que não
        foi tocada é tão ruim quanto omitir a que foi.
    .PARAMETER Phase
        4 ou 5. Qualquer outra fase cai no texto genérico - parar nas fases de leitura não altera
        nada, e o relato diz isso.
    .PARAMETER Folders
        As pastas que a fase chegou a alterar, na ordem em que foram.
    .PARAMETER Profile
        A pasta do usuário, para o texto da Fase 5.
    .OUTPUTS
        O texto do relato.
    #>
    param(
        [Parameter(Mandatory)][int]$Phase,
        [AllowEmptyCollection()][string[]]$Folders = @(),
        [string]$Profile = ''
    )

    $lista = @($Folders | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($Phase -eq 4) {
        $quais = if ($lista.Count) { "Ficaram no padrão do Windows: $($lista -join ', ') - as demais ficaram como estavam." } else { 'Nenhuma pasta do sistema chegou a ser alterada - todas ficaram como estavam.' }
        return "Parado a pedido durante as pastas do sistema. $quais`r`n`r`nO backup da Fase 2 está completo e é anterior a qualquer alteração: use 'Permissões do disco C: - Desfazer (restaurar backup)' para voltar tudo ao que era, ou rode a restauração de novo para terminar o que faltou."
    }
    if ($Phase -eq 5) {
        $perfil = if ([string]::IsNullOrWhiteSpace($Profile)) { 'a sua pasta de usuário' } else { $Profile }
        $quantas = if ($lista.Count) { "$($lista.Count) pasta(s) de dentro já tinham recebido a herança; as demais ficaram como estavam." } else { 'A herança do conteúdo não chegou a ser ligada em pasta nenhuma de dentro.' }
        return "Parado a pedido durante a herança do perfil. As permissões da raiz de '$perfil' já foram aplicadas. $quantas`r`n`r`nRode a restauração de novo para terminar: ela refaz só o que falta, e o backup deste conjunto continua valendo. Se preferir voltar tudo, use 'Permissões do disco C: - Desfazer (restaurar backup)'."
    }
    return "Parado a pedido antes de qualquer alteração: esta fase só lê o disco, e nada foi modificado. Pode rodar a restauração de novo quando quiser."
}

function Get-WinForgeAclStepOwnerSid {
    <#
    .SYNOPSIS
        O SID que um passo '/setowner' do plano entrega à pasta. Função pura.
    .DESCRIPTION
        O passo de devolução de posse carrega o dono padrão como '*<SID>' no vetor de argumentos -
        é o formato que o icacls exige. Quem precisa do SID cru é o marcador de posse pendente: sem
        ele o aviso da abertura diz que algo está errado e não diz para onde a posse tem de voltar,
        que é a única parte acionável.

        Ser pura é o que permite provar a extração contra o plano de verdade, sem trocar a posse de
        pasta nenhuma. Estava embutida em Invoke-WinForgeAclOwnerFallback e por isso não era
        exercitada: um mutante que a apagava SOBREVIVEU, e o marcador teria saído sem dono.

        Passo sem SID devolve texto vazio, e não estoura: quem chama decide o que fazer com isso.
    .OUTPUTS
        O SID, ou '' quando o passo não traz nenhum.
    #>
    param([Parameter(Mandatory)][hashtable]$Step)

    foreach ($arg in @($Step.Arguments)) {
        $texto = [string]$arg
        if ($texto.StartsWith('*S-1-', [StringComparison]::OrdinalIgnoreCase)) { return $texto.Substring(1) }
    }
    return ''
}

function Write-WinForgeAclOwnerPending {
    <#
    .SYNOPSIS
        Grava o marcador de "esta pasta está com a posse trocada agora". Escreve.
    .DESCRIPTION
        A Fase 4 troca a posse de uma pasta do sistema para os Administradores, repete a concessão e
        devolve a posse ao dono padrão. Entre o primeiro e o terceiro movimento existe uma janela em
        que a pasta do Windows pertence aos Administradores - e aceita alteração de qualquer processo
        elevado. A janela protegida impede que o Parar caia ali; este marcador cobre o que nenhuma
        trava de software cobre: queda de energia, tela azul, Gerenciador de Tarefas.

        Ele é gravado ANTES da troca, e não depois. O instante que precisa dele é justamente aquele
        em que o programa pode não chegar à linha seguinte - gravar depois seria gravar para o caso
        que não interessa.

        Um marcador só: a Fase 4 troca a posse de uma pasta por vez, e sobrescrever é o certo -
        chegar à segunda pasta significa que a primeira devolveu a posse.

        NÃO conserta nada, e nada aqui conserta: quem relata é a abertura seguinte, quem resolve é o
        usuário no botão. Um programa que devolve posse de pasta de sistema sozinho, na abertura, sem
        ninguém olhando, é o oposto do que estes botões prometem.
    .PARAMETER Folder
        A pasta cuja posse está trocada agora.
    .PARAMETER OwnerSid
        O SID do dono ORIGINAL - para quem a posse tem de voltar. É o que torna o aviso acionável.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Path = <string> }.
    #>
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$OwnerSid,
        [string]$Root
    )

    Assert-WinForgeNotSelfTest -Name 'Write-WinForgeAclOwnerPending'
    $caminho = Get-WinForgeAclOwnerPendingPath -Root $Root
    try {
        $pasta = Split-Path -Parent $caminho
        if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force -ErrorAction Stop | Out-Null }
        Set-Content -LiteralPath $caminho -Value ([pscustomobject]@{
            Folder   = [string]$Folder
            OwnerSid = [string]$OwnerSid
            Stamp    = (Get-Date).ToString('yyyyMMdd-HHmmss')
        } | ConvertTo-Json -Depth 3) -Encoding UTF8 -ErrorAction Stop
        return @{ Ok = $true; Reason = ''; Path = [string]$caminho }
    } catch {
        # Falhar aqui NÃO derruba a Fase 4: o marcador é uma rede de segurança para o caso raro, e
        # recusar a troca de posse porque o aviso não pôde ser escrito deixaria a pasta do sistema
        # sem o conserto que o usuário pediu. Quem chama registra o motivo e segue.
        return @{ Ok = $false; Reason = [string]$_.Exception.Message; Path = [string]$caminho }
    }
}

function Clear-WinForgeAclOwnerPending {
    <#
    .SYNOPSIS
        Apaga o marcador de posse pendente, depois de a posse ter voltado ao dono padrão. Escreve.
    .DESCRIPTION
        Roda no 'finally' da Fase 4, junto com o fechamento da janela protegida: a essa altura a
        devolução já foi tentada, e o marcador deixa de descrever o disco.

        Marcador ausente é sucesso, e não erro: a Fase 4 pode ter parado antes de gravá-lo.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string> }.
    #>
    param([string]$Root)

    Assert-WinForgeNotSelfTest -Name 'Clear-WinForgeAclOwnerPending'
    $caminho = Get-WinForgeAclOwnerPendingPath -Root $Root
    try {
        if (Test-Path -LiteralPath $caminho) { Remove-Item -LiteralPath $caminho -Force -ErrorAction Stop }
        return @{ Ok = $true; Reason = '' }
    } catch {
        return @{ Ok = $false; Reason = [string]$_.Exception.Message }
    }
}

function Get-WinForgeAclOwnerPending {
    <#
    .SYNOPSIS
        Lê o marcador de posse pendente e monta a frase do relato. SÓ LÊ.
    .DESCRIPTION
        É a função que a abertura consulta. Ela não apaga o marcador, não roda icacls e não devolve
        posse nenhuma: o marcador some quando a Fase 4 termina, ou quando o usuário usa o botão. Um
        relato que "conserta sozinho" mexeria na posse de uma pasta do Windows na abertura do
        programa, sem ninguém olhando - exatamente o estrago que o marcador existe para denunciar.

        A frase traz a PASTA e o DONO ORIGINAL. Sem o segundo, o aviso diz que algo está errado e não
        diz para onde voltar, que é a única parte acionável.

        Arquivo ausente, ilegível ou sem os campos responde 'Present = $false'. Um marcador que não
        pode ser lido não é um alarme: é um arquivo estranho na pasta, e alarmar com base nele seria
        assustar sem ter o que dizer.

        ATENÇÃO, ANTES DE USAR 'OwnerSid' PARA QUALQUER OUTRA COISA. Hoje o conteúdo deste arquivo
        só vira TEXTO - uma linha de log e um rótulo -, e é por isso que ele não passa pelas mesmas
        conferências dos outros arquivos do WinForge. Ele mora em '%ProgramData%\WinForge', pasta
        criada com New-Item -Force simples, que HERDA permissão de escrita de usuário comum, e o
        arquivo NÃO é endurecido (ao contrário do índice de backup, que passa por
        Protect-WinForgeSnapshotFile). Em outras palavras: um processo de integridade média pode
        reescrever o que está aqui dentro.

        Enquanto isso for texto, tudo bem. No instante em que alguém usar 'OwnerSid' (ou 'Folder')
        para montar um comando ELEVADO - um '/setowner', por exemplo -, este arquivo passa a ser
        entrada de comando privilegiado vinda de fonte que um processo comum controla, e as quatro
        condições abaixo passam a ser OBRIGATÓRIAS, nesta ordem:

        1. a pasta tem de ser criada e conferida como raiz confiável (Test-WinForgeSnapshotRootTrusted);
        2. o arquivo tem de ser endurecido (Protect-WinForgeSnapshotFile) e conferido na leitura;
        3. o SID tem de ser revalidado convertendo-o para [System.Security.Principal.SecurityIdentifier];
        4. a pasta citada tem de ser casada contra a lista de pastas do plano, e não aceita como veio.

        Sem as quatro, o caminho é o de escalonamento clássico: conteúdo que um processo comum
        escreve virando argumento de comando com privilégio. A mesma ameaça já está nomeada em
        wf-server.ps1 para os arquivos daquela aba.
    .OUTPUTS
        @{ Present = <bool>; Folder = <string>; OwnerSid = <string>; Stamp = <string>; Text = <string> }.
    #>
    param([string]$Root)

    $vazio = @{ Present = $false; Folder = ''; OwnerSid = ''; Stamp = ''; Text = '' }
    $caminho = Get-WinForgeAclOwnerPendingPath -Root $Root
    if (-not (Test-Path -LiteralPath $caminho -PathType Leaf)) { return $vazio }
    $dados = $null
    try { $dados = Get-Content -LiteralPath $caminho -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { return $vazio }
    if ($null -eq $dados) { return $vazio }
    $pasta = ''
    $dono = ''
    $carimbo = ''
    try { $pasta = ([string]$dados.Folder).Trim() } catch { $pasta = '' }
    try { $dono = ([string]$dados.OwnerSid).Trim() } catch { $dono = '' }
    try { $carimbo = ([string]$dados.Stamp).Trim() } catch { $carimbo = '' }
    if ([string]::IsNullOrWhiteSpace($pasta) -or [string]::IsNullOrWhiteSpace($dono)) { return $vazio }
    return @{
        Present  = $true
        Folder   = $pasta
        OwnerSid = $dono
        Stamp    = $carimbo
        # O botão citado EXISTE. A frase oferecia 'Devolver ao padrão do Windows', que não é botão
        # nenhum desta base - mandar a pessoa procurar o que não está lá é pior do que não oferecer
        # saída. Quem devolve a posse é a própria restauração: ela refaz a fase 4 e o socorro de
        # posse na pasta que ficou torta.
        Text     = "A restauração de permissões de $carimbo parou no meio da troca de posse: '$pasta' pode ter ficado com os Administradores como dona, em vez de '$dono'. Enquanto estiver assim, qualquer processo elevado altera essa pasta. Rode 'Permissões do disco C: - Restaurar padrões' de novo, na aba Config: ela refaz essa pasta e devolve a posse."
    }
}

function Show-WinForgeAclOwnerPending {
    <#
    .SYNOPSIS
        Põe o relato da posse pendente no log e na barra de status, na abertura. Não conserta nada.
    .DESCRIPTION
        Pendurada no mesmo gancho da varredura da pasta de backup, e pelos mesmos motivos: é leitura
        de um arquivo só, não justifica runspace, e não pode segurar a janela antes de ela aparecer.

        Log e barra, e nunca caixa de mensagem - mesma regra da varredura. E nada escapa daqui: o que
        roda no Dispatcher roda na thread da interface, e uma exceção solta derrubaria o programa na
        abertura por causa de um aviso.
    .OUTPUTS
        $true se relatou, $false se não há marcador (ou se ele não pôde ser lido).
    #>
    param([string]$Root)

    try {
        $pendente = Get-WinForgeAclOwnerPending -Root $Root
        if (-not $pendente.Present) { return $false }
        Write-WinForgeLog -Component "Repair" -Level "WARN" -Message ([string]$pendente.Text)
        $null = Set-WinForgeProfileProgress -Label ([string]$pendente.Text) -Percent 100
        return $true
    } catch {
        try { Write-WinForgeLog -Component "Repair" -Level "WARN" -Message "O marcador de posse pendente não pôde ser lido: $($_.Exception.Message)" } catch { }
        return $false
    }
}

function Invoke-WinForgeAclOwnerFallback {
    <#
    .SYNOPSIS
        A saída para "acesso negado" numa pasta do TrustedInstaller: toma a posse, repete a
        concessão uma vez e devolve a posse ao dono padrão.
    .DESCRIPTION
        C:\Windows e C:\Program Files pertencem ao TrustedInstaller, e a ACE padrão dos
        Administradores neles é 'M'. 'M' (Modify) não carrega WRITE_DAC: elevado ou não, o
        administrador não reescreve a DACL dessas pastas enquanto não for o dono - o icacls
        responde 5 e a fase 4 terminaria em erro justamente nas duas pastas que mais importam.

        Três movimentos, nesta ordem, e o terceiro não é opcional: pasta do sistema que fica com os
        Administradores como dona passa a aceitar alteração de qualquer processo elevado, que é o
        oposto do que estes botões restauram. A devolução roda mesmo quando a segunda tentativa
        falha - deixar a posse trocada por causa de um erro é trocar um problema por outro.

        Os dois passos de '/setowner' vêm do PLANO (Kind 'setowner-socorro' e 'setowner-devolver'),
        e não são montados aqui: é o plano que sabe o dono padrão de cada pasta, e é ele que o
        -SelfTest confere.

        As três chamadas passam pelo fluxo ao vivo, como as das fases 3 e 5, e isso vale dizer
        porque é aqui que o cancelamento é PROIBIDO: entre a posse tomada e a posse devolvida a
        pasta do sistema fica aberta a qualquer processo elevado. Transmitir a saída e poder
        interromper são coisas separadas - esta função faz a primeira e continua sem oferecer a
        segunda.
    .PARAMETER Plan
        A saída de Get-WinForgeAclRestorePlan.
    .PARAMETER Step
        O passo da fase 4 que respondeu 5.
    .PARAMETER StreamPath
        O arquivo que a janela de saída está acompanhando. Vazio, as três chamadas voltam ao caminho
        de captura - ver Invoke-WinForgeAclStreamStep.
    .OUTPUTS
        O código da segunda tentativa (ou 5, quando o par de socorro não existe no plano).
    #>
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Step,
        [string]$StreamPath = ''
    )

    $pasta = ([string]$Step.Folder).TrimEnd('\')
    $socorro = @($Plan | Where-Object { [int]$_.Phase -eq 4 -and [string]$_.Kind -eq 'setowner-socorro' -and ([string]$_.Folder).TrimEnd('\') -eq $pasta })
    $devolver = @($Plan | Where-Object { [int]$_.Phase -eq 4 -and [string]$_.Kind -eq 'setowner-devolver' -and ([string]$_.Folder).TrimEnd('\') -eq $pasta })
    if (-not $socorro.Count -or -not $devolver.Count) {
        Write-Warning "Acesso negado em '$pasta' e esta pasta não tem dono padrão no plano: a posse fica como está."
        return 5
    }
    # O dono ORIGINAL sai do passo de devolução do plano, que é quem sabe qual é. É ele que vai para
    # o marcador - sem o SID, o aviso da abertura diz que algo está errado e não diz para onde a
    # posse tem de voltar.
    $donoOriginal = [string](Get-WinForgeAclStepOwnerSid -Step $devolver[0])
    # A CHAVE da janela protegida. Fora de um comando com fluxo ao vivo não há arquivo de saída nem
    # job para proteger, e uma chave fixa mantém a função linear - o dicionário é só nosso, a chave
    # não colide com caminho nenhum e sai no 'finally' como qualquer outra.
    $chaveProtegida = [string]$StreamPath
    if ([string]::IsNullOrWhiteSpace($chaveProtegida)) { $chaveProtegida = '(fase 4 sem fluxo)' }
    # Daqui até o 'finally' o cancelamento NÃO vale, e os processos destes três passos ficam FORA do
    # job: um job com KILL_ON_JOB_CLOSE mata a árvore quando o dono morre, e morrer entre a posse
    # tomada e a posse devolvida é exatamente o estrago que esta janela existe para impedir - uma
    # pasta do Windows com os Administradores como dona aceita alteração de qualquer processo
    # elevado. A janela abre ANTES da primeira troca; se ficasse aberta por causa de uma exceção, o
    # Parar morreria para o resto da sessão, e é por isso que o fechamento é no 'finally'.
    # Os dois estados que o 'finally' consulta. 'Tomada' vira verdadeiro assim que o /setowner dos
    # Administradores responde zero; 'Voltou', só quando a devolução responde zero. Enquanto a
    # primeira for verdadeira e a segunda falsa, a pasta do sistema está com o dono errado AGORA - e
    # é exatamente esse par que decide se o marcador fica no disco.
    $posseTomada = $false
    $posseVoltou = $false
    Enter-WinForgeStreamProtected -Path $chaveProtegida
    try {
        Write-Host ''
        Write-Host "Acesso negado. $($socorro[0].Title)"
        # ANTES da troca, e não depois: o instante que precisa do marcador é justamente aquele em
        # que o programa pode não chegar à linha seguinte (queda de energia, tela azul, Gerenciador
        # de Tarefas). Falhar ao gravá-lo não cancela a Fase 4 - ele é rede de segurança, não porta.
        if ([string]::IsNullOrWhiteSpace($donoOriginal)) {
            # Sem SID não há marcador: '-OwnerSid' é obrigatório e vazio ESTOURARIA aqui dentro,
            # derrubando a troca de posse por causa do aviso que existe para protegê-la.
            Write-Warning "O passo de devolução da posse de '$pasta' não traz o SID do dono padrão: a troca continua, mas uma interrupção aqui não teria para onde apontar."
        } else {
            $marcaPosse = Write-WinForgeAclOwnerPending -Folder $pasta -OwnerSid $donoOriginal
            if (-not $marcaPosse.Ok) { Write-Warning "O marcador de posse pendente de '$pasta' não pôde ser gravado ($($marcaPosse.Reason)); a troca de posse continua, mas uma interrupção aqui não será relatada na próxima abertura." }
        }
        $codigoSocorro = [int](Invoke-WinForgeAclStreamStep -Path $StreamPath -Step $socorro[0])
        if ($codigoSocorro -ne 0) {
            Write-Error "A posse de '$pasta' não pôde ser assumida (código $codigoSocorro); a concessão fica sem a segunda tentativa."
            return $codigoSocorro
        }
        # Daqui em diante a pasta do sistema está com os Administradores como dona.
        $posseTomada = $true
        Write-Host 'Segunda e última tentativa desta etapa.'
        $codigoRetentativa = [int](Invoke-WinForgeAclStreamStep -Path $StreamPath -Step $Step)
        Write-Host $devolver[0].Title
        $codigoDevolver = [int](Invoke-WinForgeAclStreamStep -Path $StreamPath -Step $devolver[0])
        if ($codigoDevolver -ne 0) { Write-Error "A posse de '$pasta' NÃO voltou ao dono padrão (código $codigoDevolver): a pasta ficou com os Administradores como dona." }
        # SÓ com código zero. Devolver a posse ao TrustedInstaller nem sempre é possível, mesmo
        # elevado, e este é o caso em que o marcador MAIS importa: a pasta ficou mesmo com os
        # Administradores como dona. Apagá-lo aqui daria silêncio na abertura seguinte justamente
        # sobre a pasta que ele existe para denunciar.
        $posseVoltou = ($codigoDevolver -eq 0)
        return $codigoRetentativa
    } finally {
        # A saída da janela protegida vem PRIMEIRO: a limpeza do marcador toca no disco e pode
        # estourar, e com ela na frente uma falha ali deixaria o Parar ignorado até o fim do comando
        # inteiro. O que protege o sistema sai antes do que informa sobre ele.
        Exit-WinForgeStreamProtected -Path $chaveProtegida
        # '$posseVoltou' nasce falso e só vira verdadeiro na linha acima: o 'return' do socorro que
        # falhou passa por aqui com ele falso, e ali a posse nunca chegou a ser tomada - é o outro
        # caminho que limpa, e por isso a condição é sobre a posse, não sobre o código de retorno.
        if ($posseVoltou -or -not $posseTomada) { $null = Clear-WinForgeAclOwnerPending }
    }
}

function Invoke-WinForgeAclDenyRemoval {
    <#
    .SYNOPSIS
        Roda o '/remove:d' de uma fase, e só quando a pasta realmente tem ACE de negação.
    .DESCRIPTION
        Lê a lista da pasta (Get-Acl, só leitura), pergunta a Get-WinForgeAclDenySid se algum dos
        SIDs do passo está negado e, só aí, executa. Sem negação nenhuma a função não roda nada e
        diz isso: apagar negação que ninguém conferiu é decidir por configuração legítima de outra
        pessoa, e o Desfazer não traria essa ACE de volta com o dono certo.
    .OUTPUTS
        Nada. Escreve o andamento (é chamada de dentro de um passo de fluxo ao vivo).
    #>
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][int]$Phase,
        [Parameter(Mandatory)][string]$Path
    )

    $passo = @($Plan | Where-Object { [int]$_.Phase -eq $Phase -and [string]$_.Kind -eq 'remove-deny' })
    if (-not $passo.Count) { return }
    $passo = $passo[0]
    $lista = $null
    try { $lista = Get-Acl -LiteralPath $Path -ErrorAction Stop } catch { $lista = $null }
    if ($null -eq $lista) {
        Write-Warning "A lista de '$Path' não pôde ser lida; as negações de acesso ficam como estão."
        return
    }
    $negados = @(Get-WinForgeAclDenySid -Acl $lista -Sids @($passo.DenySids | ForEach-Object { [string]$_ }))
    if (-not $negados.Count) { return }
    Write-Host ''
    Write-Host "$($passo.Title) - $($negados.Count) negação(ões) encontrada(s)."
    $r = Invoke-WinForgeNativeCommand -FilePath ([string]$passo.FilePath) -Arguments @($passo.Arguments)
    Write-Host ([string]$r.Text)
    if ([int]$r.ExitCode -ne 0) { Write-Error "A retirada das negações terminou com código $($r.ExitCode)." }
}

function New-WinForgeAclIndexOrigin {
    <#
    .SYNOPSIS
        A identidade da máquina e do perfil que estão gravando um índice de backup de permissões.
        Só lê.
    .DESCRIPTION
        Duas coisas, e as duas fazem falta. O 'MachineGuid' de
        'HKLM\SOFTWARE\Microsoft\Cryptography' nasce na instalação do Windows e separa esta máquina
        de qualquer outra; o SID do perfil ATUAL separa dois usuários da mesma máquina.

        O SHA-256 do item de conteúdo protege o ARQUIVO contra alteração e não diz nada sobre a
        PROCEDÊNCIA do índice - e é o índice que carrega os SDDL das fases 3 e 4. Um índice de outra
        máquina aplica descritores com SIDs que não existem aqui: eles entram como SID cru, não
        resolvem para conta nenhuma e trancam o perfil. Por isso o par é gravado na fase 2 e
        conferido pelo Desfazer (Test-WinForgeAclIndexOrigin) antes de qualquer SDDL virar argumento.

        Campo que não pôde ser lido volta VAZIO, e nunca inventado: quem confere trata vazio como
        "não dá para afirmar", que é diferente de "confere".
    .OUTPUTS
        @{ MachineGuid = <string>; ProfileSid = <string> }.
    #>
    param()

    $guid = ''
    try { $guid = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid } catch { $guid = '' }
    $sid = ''
    try { $sid = [string]([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value) } catch { $sid = '' }
    return @{ MachineGuid = [string]$guid; ProfileSid = [string]$sid }
}

function Test-WinForgeAclIndexOrigin {
    <#
    .SYNOPSIS
        Diz se um índice de backup foi gravado NESTA máquina, por ESTE perfil. Só lê.
    .DESCRIPTION
        A pergunta vem antes de o primeiro SDDL do índice virar argumento. Divergência RECUSA: um
        descritor gravado em outra máquina traz SIDs que não existem aqui, e o Windows os mantém
        como SID cru - a pasta fica com uma lista que não dá acesso a ninguém desta máquina, que é
        exatamente o sintoma que estes botões existem para curar.

        Índice SEM origem nenhuma - o da 1.7.0, que não gravava o campo - é ACEITO, com o motivo
        preenchido para quem chama avisar. Recusá-lo seria matar o Desfazer justamente do backup que
        a guarda de Test-WinForgeAclRestoreAllowed manda desfazer, e a pasta protegida já garante
        que quem escreveu ali estava elevado nesta máquina (Confirm-WinForgeAclBackupRoot: dono
        dentro de SYSTEM/Administradores, ninguém de fora deles com escrita). O que a origem pega é
        a CÓPIA deliberada de um índice de outra máquina para dentro dessa pasta.

        Campo presente e diferente recusa; campo ausente não afirma nada. E não poder ler a
        identidade DESTA máquina também recusa: sem os dois lados não há comparação, e aqui não
        comparar é aplicar às cegas.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string> }. Com Ok = $true, 'Reason' vazio é "confere" e 'Reason'
        preenchido é "não havia o que comparar" - o aviso que quem chama põe na tela.
    #>
    param([Parameter(Mandatory)]$Index)

    $r = @{ Ok = $false; Reason = '' }
    $atual = New-WinForgeAclIndexOrigin
    $origem = $null
    try { $origem = $Index.Origin } catch { $origem = $null }
    $guid = ''
    $sid = ''
    if ($null -ne $origem) {
        # '[string]$obj.Propriedade' sobre propriedade que lança devolve '' em silêncio (medido), e
        # '' aqui significa "não afirma nada" - que é o tratamento certo, não um atalho.
        try { $guid = ([string]$origem.MachineGuid).Trim() } catch { $guid = '' }
        try { $sid = ([string]$origem.ProfileSid).Trim() } catch { $sid = '' }
    }
    if ([string]::IsNullOrWhiteSpace($guid) -and [string]::IsNullOrWhiteSpace($sid)) {
        $r.Ok = $true
        $r.Reason = 'este índice foi gravado por uma versão do WinForge que não anotava a máquina de origem; não há como conferir se ele é mesmo daqui.'
        return $r
    }
    if (-not [string]::IsNullOrWhiteSpace($guid)) {
        if ([string]::IsNullOrWhiteSpace([string]$atual.MachineGuid)) {
            $r.Reason = "o identificador desta máquina não pôde ser lido, então não dá para confirmar que o índice '$guid' é daqui"
            return $r
        }
        if (-not [string]::Equals($guid, ([string]$atual.MachineGuid).Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            $r.Reason = "o índice foi gravado em OUTRA máquina (identificador '$guid'; esta é '$($atual.MachineGuid)') - as permissões guardadas lá citam contas que não existem aqui"
            return $r
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($sid)) {
        if ([string]::IsNullOrWhiteSpace([string]$atual.ProfileSid)) {
            $r.Reason = "o SID do perfil desta sessão não pôde ser lido, então não dá para confirmar que o índice '$sid' é deste usuário"
            return $r
        }
        if (-not [string]::Equals($sid, ([string]$atual.ProfileSid).Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            $r.Reason = "o índice foi gravado por OUTRO usuário desta máquina (SID '$sid'; o desta sessão é '$($atual.ProfileSid)') - a pasta de usuário guardada lá não é esta"
            return $r
        }
    }
    $r.Ok = $true
    return $r
}

function Get-WinForgeAclIndexList {
    <#
    .SYNOPSIS
        Todos os índices de backup de permissões de uma pasta, do MAIS ANTIGO para o mais novo. Só lê.
    .DESCRIPTION
        O carimbo sai do NOME do arquivo ('acl-index-<aaaaMMdd-HHmmss>.json'), campo de largura fixa,
        e não da data do sistema de arquivos, que uma cópia de pasta reescreve, nem do campo 'Stamp'
        de dentro, que é conteúdo de arquivo como qualquer outro.

        A ordem é ORDINAL, por CompareOrdinal: 'Sort-Object' ordena pela CULTURA, e
        '-Culture ([CultureInfo]::InvariantCulture)' não conserta isso - o parâmetro é uma STRING, a
        cultura invariante vira '' em silêncio e a comparação continua linguística.

        'Consumed' AUSENTE conta como $false, e isso é o certo: um índice da 1.7.0 é mesmo um backup
        que ninguém desfez. Índice que não pôde ser lido também entra como não consumido, com
        'Readable' falso - ele existe, ninguém o desfez, e sumir com ele da fila faria a guarda da
        segunda restauração dizer "pode ir" por cima de um backup que ninguém conferiu.
    .PARAMETER Trusted
        Confere cada índice por Test-WinForgeAclBackupFile ANTES de abri-lo, e marca 'Refused' com o
        motivo quando ele não passa - sem chegar a analisar o JSON. É a promessa de
        Test-WinForgeSnapshotFileTrusted ("antes de ele ser lido"), e é o caminho do Desfazer.
    .OUTPUTS
        @(@{ Path; Stamp; Consumed; Origin; Items; Readable; Refused; Reason }), do mais antigo para
        o mais novo.
    #>
    param([string]$Root, [switch]$Trusted)

    $dir = Get-WinForgeAclBackupRoot $Root
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $arquivos = @(Get-ChildItem -LiteralPath $dir -Filter 'acl-index-*.json' -File -ErrorAction SilentlyContinue)
    if (-not $arquivos.Count) { return @() }
    $saida = New-Object System.Collections.Generic.List[object]
    foreach ($f in $arquivos) {
        $carimbo = [string]([System.IO.Path]::GetFileNameWithoutExtension([string]$f.Name)) -replace '^acl-index-', ''
        $item = @{ Path = [string]$f.FullName; Stamp = $carimbo; Consumed = $false; Origin = $null; Items = @(); Readable = $false; Refused = $false; Reason = '' }
        if ($Trusted) {
            $julg = Test-WinForgeAclBackupFile -Path ([string]$f.FullName) -Root $dir
            if (-not $julg.Trusted) {
                $item.Refused = $true
                $item.Reason = [string]$julg.Reason
                $saida.Add($item)
                continue
            }
        }
        $dados = $null
        try { $dados = Get-Content -LiteralPath ([string]$f.FullName) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { $dados = $null }
        if ($null -eq $dados) {
            $item.Reason = "o índice '$($f.Name)' não pôde ser lido"
            $saida.Add($item)
            continue
        }
        $item.Readable = $true
        $item.Consumed = [bool]$dados.Consumed
        $item.Origin = $dados.Origin
        $item.Items = @($dados.Items)
        $saida.Add($item)
    }
    $arr = $saida.ToArray()
    [array]::Sort($arr, [System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal([string]$a.Stamp, [string]$b.Stamp) })
    return @($arr)
}

function Set-WinForgeAclIndexConsumed {
    <#
    .SYNOPSIS
        Marca um índice de backup como já desfeito, para ele sair da fila do Desfazer.
    .DESCRIPTION
        É a outra metade do conserto do defeito da 1.7.0: sem a marca, o índice recém-desfeito
        continuaria sendo o mais antigo não consumido e o Desfazer seguinte o aplicaria de novo, em
        cima de um disco que já voltou.

        A gravação é por TROCA, e não por reescrita no lugar, e a diferença é o que acontece quando
        a máquina morre no meio. 'Set-Content' TRUNCA o arquivo antes de escrever: interrompido ali
        - queda de energia, disco cheio -, o índice fica pela metade e vira ILEGÍVEL, que é
        exatamente o estado que prende o conjunto na fila e deixa a restauração recusada. O texto
        novo vai para um temporário ao lado e [IO.File]::Replace() troca os dois de uma vez.

        Replace mantém a LISTA do destino - medido, SDDL idêntico antes e depois -, mas NÃO o DONO:
        o arquivo que fica é o temporário renomeado, e arquivo criado por processo elevado nasce
        pertencendo à CONTA, não ao grupo Administradores (ver Protect-WinForgeSnapshotFile). Dono
        guarda WRITE_DAC implícito, e o estrago não é só funcional - índice com dono errado é
        recusado na conferência do Desfazer seguinte: um processo de integridade MÉDIA da mesma
        conta reabriria o índice já consumido e plantaria um 'ExternalPath', que a limpeza elevada
        apagaria. Por isso o TEMPORÁRIO é endurecido ANTES da troca, e não o destino depois dela.

        Endurecimento que falha NÃO cancela a marca, e isso é deliberado: parar aqui deixaria o
        conjunto pendente para sempre, que é o beco sem saída já consertado. O que acontece é que
        'Hardened' volta falso com o motivo, quem chama avisa, e a segunda porta continua de pé - o
        inventário não honra caminho externo vindo de índice que não passa na conferência.

        O temporário nasce na MESMA pasta, por duas razões: Replace exige o mesmo volume, e a pasta
        já é a protegida, então o arquivo intermediário nunca fica exposto.

        Morrer ENTRE o '/restore' e a marca continua aceitável: a operação é idempotente e a
        execução seguinte reaplica o mesmo conjunto. O que não era aceitável é morrer DENTRO da
        marca e perder o índice.

        Quem chama já está elevado; sem elevação a gravação falha e o motivo volta em 'Reason'.

        O NOME é conferido antes da abertura: esta função escreve, e o caminho vem de um arquivo de
        índice. 'acl-index-*.json' é a única forma que ela aceita.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Hardened = <bool> }. 'Ok' é a marca gravada; 'Hardened'
        é o dono e a lista do arquivo trocado, e pode ser falso com 'Ok' verdadeiro.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $r = @{ Ok = $false; Reason = ''; Hardened = $false }
    $nome = ''
    try { $nome = [string](Split-Path -Leaf ([string]$Path)) } catch { $nome = '' }
    if ($nome -notmatch '^acl-index-.+\.json$') {
        $r.Reason = "'$Path' não tem a forma de um índice de backup de permissões"
        return $r
    }
    if (-not (Test-Path -LiteralPath ([string]$Path) -PathType Leaf)) {
        $r.Reason = "o índice '$Path' não existe"
        return $r
    }
    $temporario = ([string]$Path + '.tmp')
    try {
        $dados = Get-Content -LiteralPath ([string]$Path) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $dados) { throw "o índice '$Path' não pôde ser lido" }
        # '-Force' porque o índice da 1.7.0 não TEM o campo: ali a marca é criada, não atualizada.
        $dados | Add-Member -NotePropertyName 'Consumed' -NotePropertyValue $true -Force
        Set-Content -LiteralPath $temporario -Value ($dados | ConvertTo-Json -Depth 5) -Encoding UTF8 -ErrorAction Stop
        # Dono e lista ANTES da troca: é o temporário que vai ficar no lugar do índice, e o Replace
        # não leva o dono do destino junto. Falhar aqui não cancela a marca - ver a descrição.
        $endurecido = Protect-WinForgeSnapshotFile -Path $temporario
        $r.Hardened = [bool]$endurecido.Hardened
        if (-not $r.Hardened) { $r.Reason = "o índice trocado não pôde ser endurecido ($($endurecido.Reason)); o conjunto sai da fila do mesmo jeito, mas o arquivo fica com o dono de quem o gravou" }
        # '[NullString]::Value', e não '$null'. MEDIDO: '$null' num parâmetro [string] de método .NET
        # chega como STRING VAZIA, e '' não é caminho - a chamada morre com "O caminho tem um formato
        # inválido" e a marca nunca é gravada. '[NullString]::Value' existe exatamente para isso, e é
        # o que faz o Replace rodar sem deixar arquivo de reserva para trás.
        [System.IO.File]::Replace($temporario, [string]$Path, [NullString]::Value)
        $r.Ok = $true
    } catch {
        $r.Reason = $_.Exception.Message
        $r.Hardened = $false
    } finally {
        # O temporário só sobrevive a uma troca que não aconteceu. Deixá-lo na pasta daria um órfão
        # para a limpeza apagar e um arquivo a mais na conta do aviso de tamanho.
        if (Test-Path -LiteralPath $temporario) { Remove-Item -LiteralPath $temporario -Force -ErrorAction SilentlyContinue }
    }
    return $r
}

function Test-WinForgeAclRestoreAllowed {
    <#
    .SYNOPSIS
        Diz se uma restauração NOVA pode começar, ou se há backup que ninguém desfez no caminho.
        Só lê.
    .DESCRIPTION
        É a guarda que fecha o defeito da 1.7.0. Lá, a segunda restauração gravava um índice novo
        sobre um disco JÁ alterado: a fase 5 da primeira tinha tirado a proteção de herança, o escopo
        do conteúdo caía para perto de zero e mesmo assim '$gravados' continuava maior que zero,
        porque os itens 'sddl' das fases 3 e 4 entram sempre. Como o Desfazer lia o índice mais novo,
        esse índice quase vazio virava o único alcançável e as 338 pastas originais ficavam
        irrecuperáveis.

        Com a guarda, a segunda restauração nem começa: ou o usuário desfaz o que está pendente, ou
        descarta o backup antigo pelo botão de limpeza. A recusa nomeia os dois caminhos, e diz que
        a limpeza alcança TAMBÉM o pendente - sem essa frase ela mandaria para uma saída que, até o
        conserto do beco sem saída, não existia: a limpeza só apagava órfão e consumido, e respondia
        "nada a apagar" justamente para quem estava preso aqui.

        Índice sem 'Consumed' - o da 1.7.0 - conta como PENDENTE, e é o certo: ele é mesmo um backup
        que ninguém desfez.
    .OUTPUTS
        @{ Ok = <bool>; Reason = <string>; Pending = <int> }.
    #>
    param([string]$Root)

    $r = @{ Ok = $true; Reason = ''; Pending = 0 }
    $pendentes = @(Get-WinForgeAclIndexList -Root $Root | Where-Object { -not $_.Consumed })
    $r.Pending = [int]$pendentes.Count
    if ($r.Pending -lt 1) { return $r }
    $r.Ok = $false
    $carimbos = @($pendentes | ForEach-Object { [string]$_.Stamp }) -join ', '
    $r.Reason = "já existe backup de permissões que ninguém desfez ($($r.Pending) conjunto(s): $carimbos). Restaurar de novo gravaria um backup do disco JÁ alterado, e o backup bom deixaria de ser alcançável - foi assim que a versão anterior destruiu a cópia que interessava. Use 'Permissões do disco C: - Desfazer (restaurar backup)' para voltar ao que estava, ou 'Permissões do disco C: - Limpar backups antigos' para descartar o que não interessa mais - ela alcança inclusive os pendentes como estes, sob confirmação digitada -, e então tente outra vez."
    return $r
}

function Test-WinForgeAclSddlSame {
    <#
    .SYNOPSIS
        Diz se dois descritores descrevem a MESMA lista de permissões. Função pura, só texto.
    .DESCRIPTION
        Duas normalizações, e as duas são medição, não gosto:

        1. As FLAGS de controle da DACL entram só pela proteção de herança ('P'). 'AI' ("herança
           automática já propagada") aparece sozinha na primeira gravação de uma pasta recém-criada,
           sem nenhuma ACE ter mudado - comparar o texto cru acusaria isso como divergência. 'P' fica
           porque é semântica: é ela que diz se a herança está bloqueada, que é justamente a condição
           que o backup guarda.
        2. As ACEs são comparadas como CONJUNTO, e não na ordem. O descritor guardado pode ter vindo
           do próprio icacls (as pastas com negação saem de 'icacls /save', para preservar a ordem no
           disco), enquanto a releitura vem do .NET, que entrega a lista em ordem canônica - negação
           antes de permissão. Cobrar a ordem aqui acusaria divergência em pasta que voltou inteira.

        A comparação existe para a conferência por amostragem do Desfazer, e ali a pergunta é "esta
        pasta recebeu a lista que o backup guardava", não "os dois textos são iguais byte a byte".
    .OUTPUTS
        $true ou $false. Texto sem seção 'D:' é $false nos dois lados - sem DACL não há o que comparar.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$A,
        [Parameter(Mandatory)][AllowEmptyString()][string]$B
    )

    $forma = {
        param($sddl)
        $t = [string]$sddl
        $i = $t.IndexOf('D:', [StringComparison]::Ordinal)
        if ($i -lt 0) { return $null }
        $resto = $t.Substring($i + 2)
        $flags = [string][regex]::Match($resto, '^[A-Za-z_]*').Value
        $aces = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($resto, '\([^()]*\)')) { $aces.Add(([string]$m.Value).ToUpperInvariant()) }
        $arr = $aces.ToArray()
        # Ordinal de novo, pelo mesmo motivo de sempre: ordenação por cultura muda com a máquina.
        [array]::Sort($arr, [System.Comparison[string]] { param($x, $y) [string]::CompareOrdinal($x, $y) })
        return @{ Protected = ($flags.IndexOf('P', [StringComparison]::OrdinalIgnoreCase) -ge 0); Aces = @($arr) }
    }
    $fa = & $forma $A
    $fb = & $forma $B
    if ($null -eq $fa -or $null -eq $fb) { return $false }
    if ([bool]$fa.Protected -ne [bool]$fb.Protected) { return $false }
    if (@($fa.Aces).Count -ne @($fb.Aces).Count) { return $false }
    for ($i = 0; $i -lt @($fa.Aces).Count; $i++) {
        if ([string]@($fa.Aces)[$i] -ne [string]@($fb.Aces)[$i]) { return $false }
    }
    return $true
}

# A regra que decide o desenho de Test-WinForgeAclRestoreSample está AQUI, fora do corpo, pelo mesmo
# motivo de Get-WinForgeAclContentScope: o SelfTest lê '(Get-Command …).ScriptBlock' e reprova o
# fonte que CITE a frase de resumo do icacls ("Processados com sucesso N arquivos", "successfully
# processed"), porque essa frase muda com o idioma do sistema e a integração contínua deste projeto
# roda em inglês - uma asserção presa ao idioma já quebrou aqui antes. Escrever o exemplo dentro da
# função reprovaria justamente a função que não o usa. O sinal daqui é COMPORTAMENTO: relê a ACL e
# compara descritor com descritor.
function Test-WinForgeAclRestoreSample {
    <#
    .SYNOPSIS
        Relê a lista de permissões de uma AMOSTRA das pastas de um arquivo de backup e compara com o
        descritor guardado nele. Só lê.
    .DESCRIPTION
        Existe para pagar a dívida do '/C'. O '/restore' do Desfazer roda COM '/C' de propósito - o
        alvo é um arquivo de centenas de entradas e continuar apesar do erro vale mais do que o
        código de saída -, e o preço é que o código de saída passa a ser 0 quase sempre. Contar uma
        pasta como aplicada por causa dele significa "o icacls rodou", não "as entradas foram
        aplicadas". O sinal volta por comparação de descritores, e nunca por leitura de texto de
        saída - ver o comentário acima desta função.

        A leitura é a MESMA da caminhada da fase 2 - 'DirectoryInfo.GetAccessControl(Access)' sobre
        o caminho com prefixo '\\?\' -, e não Get-Acl: é o mesmo produtor do texto guardado, e o
        prefixo é o que faz caminho longo dentro do perfil responder em vez de virar divergência.

        A amostra é ESPALHADA pelo arquivo, e isso não é detalhe: um '/restore' que morre no meio
        deixa o começo certo e o fim intocado, e é exatamente esse o caso que o '/C' esconde. Uma
        amostra das N primeiras entradas aprovaria esse arquivo. Os índices vão de 0 a Total-1 em
        passo constante, as duas pontas incluídas, e a escolha é determinística: o mesmo arquivo dá
        a mesma amostra, e o resultado é reproduzível.

        Tamanho padrão 20, e o número tem uma razão de cada lado. O custo de conferir é uma leitura
        de ACL por pasta - dezenas de milissegundos no total, contra um '/restore' que leva minutos -,
        então reler pouco não economiza nada que importe; e reler TUDO num perfil de centenas de
        pastas transformaria a conferência em uma segunda caminhada, que é o que a fase 2 acabou de
        gastar 39 segundos fazendo. Vinte pontos espalhados detectam com certeza a falha que
        interessa (o '/restore' que não aplicou nada, ou que parou no meio, atinge blocos inteiros do
        arquivo) e, para uma falha espalhada em 10% das entradas, a chance de passar despercebida é
        (1 - 0,1)^20, cerca de 12%.

        Pasta que não existe mais NÃO é divergência: conta em 'Missing'. Entre o backup e o Desfazer
        passam minutos, e pasta de cache dentro de um perfil some o tempo todo - é o mesmo
        tratamento que a fase 5 dá ao código 2 do icacls. Pasta que existe e não pôde ser LIDA conta
        em 'Differ': não confirmar é diferente de confirmar.
    .PARAMETER Root
        A pasta de onde os nomes do arquivo são relativos - a mesma que o 'icacls /restore' recebeu.
    .PARAMETER Size
        Quantas pastas conferir. Menos que 1 vira 1; mais que o arquivo tem confere o arquivo todo.
    .OUTPUTS
        @{ Ok; Reason; Total; Checked; Match; Differ; Missing; Paths }. 'Paths' traz até 10 das
        divergentes, para o resumo poder nomeá-las.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$File,
        [int]$Size = 20
    )

    $r = @{ Ok = $false; Reason = ''; Total = 0; Checked = 0; Match = 0; Differ = 0; Missing = 0; Paths = @() }
    if ($Size -lt 1) { $Size = 1 }
    # Primeira passada: quantos pares o arquivo tem. Por FLUXO, e duas linhas de cada vez - é o
    # formato do '/save' (nome, descritor) e é o mesmo motivo de Measure-WinForgeAclSaveEntry ler
    # assim: materializar as linhas de um backup grande é OutOfMemoryException numa função que não
    # precisa de nenhuma delas depois de contá-la.
    $leitor = $null
    try {
        $leitor = New-Object System.IO.StreamReader([string]$File, [System.Text.Encoding]::Unicode, $false)
        while ($null -ne ($linha = $leitor.ReadLine())) {
            if ($null -eq $leitor.ReadLine()) { break }
            $r.Total++
        }
    } catch {
        $r.Reason = "o backup '$File' não pôde ser lido para conferência: $($_.Exception.Message)"
        return $r
    } finally {
        if ($null -ne $leitor) { $leitor.Dispose() }
    }
    if ($r.Total -lt 1) {
        $r.Reason = "o backup '$File' não tem entrada nenhuma para conferir"
        return $r
    }
    $quantas = [Math]::Min([int]$Size, [int]$r.Total)
    $alvos = New-Object 'System.Collections.Generic.HashSet[int]'
    if ($quantas -le 1) {
        [void]$alvos.Add(0)
    } else {
        for ($i = 0; $i -lt $quantas; $i++) {
            [void]$alvos.Add([int][Math]::Round(([double]$i * ([double]$r.Total - 1.0)) / ([double]$quantas - 1.0), [MidpointRounding]::AwayFromZero))
        }
    }
    $longo = { param($p) if ($p -like '\\?\*') { $p } else { '\\?\' + $p } }
    $indice = 0
    $leitor = $null
    try {
        $leitor = New-Object System.IO.StreamReader([string]$File, [System.Text.Encoding]::Unicode, $false)
        while ($null -ne ($nome = $leitor.ReadLine())) {
            $sddl = $leitor.ReadLine()
            if ($null -eq $sddl) { break }
            if ($alvos.Contains($indice)) {
                $r.Checked++
                $abs = ''
                try { if (-not [string]::IsNullOrWhiteSpace([string]$nome)) { $abs = [string](Join-Path ([string]$Root) ([string]$nome)) } } catch { $abs = '' }
                if ([string]::IsNullOrWhiteSpace($abs)) {
                    $r.Differ++
                } elseif (-not [System.IO.Directory]::Exists((& $longo $abs))) {
                    $r.Missing++
                } else {
                    $atual = ''
                    try {
                        $atual = [string](New-Object System.IO.DirectoryInfo ((& $longo $abs))).GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access).GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
                    } catch { $atual = '' }
                    if (Test-WinForgeAclSddlSame -A $atual -B ([string]$sddl)) {
                        $r.Match++
                    } else {
                        $r.Differ++
                        if (@($r.Paths).Count -lt 10) { $r.Paths += $abs }
                    }
                }
            }
            $indice++
            if ($r.Checked -ge $alvos.Count) { break }
        }
        $r.Ok = $true
    } catch {
        $r.Reason = "a conferência do backup '$File' parou: $($_.Exception.Message)"
    } finally {
        if ($null -ne $leitor) { $leitor.Dispose() }
    }
    return $r
}

function Get-WinForgeAclBackupSet {
    <#
    .SYNOPSIS
        O conjunto de backup de permissões da vez: o índice, o carimbo de tempo e os arquivos.
    .DESCRIPTION
        Só lê. O escolhido é o MAIS ANTIGO ainda NÃO CONSUMIDO, e não o mais novo - esse "mais novo"
        era o defeito da 1.7.0. Na segunda restauração a fase 5 da primeira já tinha tirado a
        proteção de herança, o escopo do conteúdo caía para perto de zero e mesmo assim o índice novo
        nascia com itens (os 'sddl' das fases 3 e 4 entram sempre): lendo o mais novo, o Desfazer
        aplicava esse índice quase vazio e as 338 pastas originais ficavam irrecuperáveis. Quem tira
        um conjunto da fila é Set-WinForgeAclIndexConsumed, chamada por um Desfazer sem recusa.

        A ordem vem do NOME do arquivo, e não da data do sistema de arquivos, que uma cópia de pasta
        reescreve: o nome carrega '<aaaaMMdd-HHmmss>', campo de largura fixa.

        O índice é um JSON com 'Stamp' e 'Items'. Cada item é uma pasta: 'Path' sempre, e daí ou
        'Sddl'/'Owner'/'OwnerSid' (a lista DELA MESMA, que o Desfazer reaplica direto) ou
        'File'/'Target' (o arquivo de icacls do CONTEÚDO, hoje só o do perfil). Item sem 'Path' é
        ignorado; o nome de arquivo vira caminho dentro da pasta protegida e ainda passa, um a um,
        por Test-WinForgeAclBackupFile antes de virar argumento de coisa alguma.
    .PARAMETER Trusted
        Confere o índice por Test-WinForgeAclBackupFile ANTES de abri-lo, e devolve
        'Refused = $true' com o motivo se ele não passar. É o caminho de verdade do Desfazer: um
        índice recusado não chega a ser lido nem analisado, que é o que a própria descrição de
        Test-WinForgeSnapshotFileTrusted promete ("antes de ele ser lido"). Antes a conferência
        vinha DEPOIS do ConvertFrom-Json, e um arquivo adulterado já tinha passado pelo analisador
        de JSON quando era recusado.

        Sem o switch a leitura é crua: é o que o -DryRun usa (ele só LISTA, não roda nada) e o que
        deixa o -SelfTest montar um conjunto numa pasta de %TEMP%, cujos arquivos pertencem à
        identidade atual e por isso nunca passariam na regra de dono da pasta padrão.
    .OUTPUTS
        @{ Stamp; Index; Items = @(@{ Path; Sddl; Owner; OwnerSid; File; Target; Sha256;
        ExternalPath }); Origin; Consumed; Pending; Reason; Refused }. 'Pending' é quantos índices
        não consumidos existem na pasta, e é o número que a guarda da segunda restauração usa.
    #>
    param([string]$Root, [switch]$Trusted)

    $dir = Get-WinForgeAclBackupRoot $Root
    $vazio = @{ Stamp = ''; Index = ''; Items = @(); Origin = $null; Consumed = $false; Pending = 0; Refused = $false; Reason = '' }
    if (-not (Test-Path -LiteralPath $dir)) {
        $vazio.Reason = "a pasta '$dir' não existe - nenhuma restauração foi feita nesta máquina"
        return $vazio
    }
    $lista = @(Get-WinForgeAclIndexList -Root $dir -Trusted:$Trusted)
    if (-not $lista.Count) {
        $vazio.Reason = "nenhum índice de backup em '$dir'"
        return $vazio
    }
    $pendentes = @($lista | Where-Object { -not $_.Consumed })
    $quantos = [int]$pendentes.Count
    if ($quantos -lt 1) {
        # Tudo já desfeito não é erro nem recusa: é o caso de quem clica no Desfazer duas vezes.
        $ultimo = $lista | Select-Object -Last 1
        return @{ Stamp = [string]$ultimo.Stamp; Index = [string]$ultimo.Path; Items = @(); Origin = $ultimo.Origin; Consumed = $true; Pending = 0; Refused = $false; Reason = "os $($lista.Count) conjunto(s) de backup desta pasta já foram desfeitos" }
    }
    $escolhido = $pendentes | Select-Object -First 1
    if ($escolhido.Refused) {
        return @{ Stamp = [string]$escolhido.Stamp; Index = [string]$escolhido.Path; Items = @(); Origin = $null; Consumed = $false; Pending = $quantos; Refused = $true; Reason = [string]$escolhido.Reason }
    }
    if (-not $escolhido.Readable) {
        return @{ Stamp = [string]$escolhido.Stamp; Index = [string]$escolhido.Path; Items = @(); Origin = $null; Consumed = $false; Pending = $quantos; Refused = $false; Reason = [string]$escolhido.Reason }
    }
    $itens = @()
    foreach ($it in @($escolhido.Items)) {
        $caminho = [string]$it.Path
        if ([string]::IsNullOrWhiteSpace($caminho)) { continue }
        $arquivo = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$it.File)) { $arquivo = Join-Path $dir ([string]$it.File).Trim() }
        # 'ExternalPath' é o caminho COMPLETO de um arquivo de conteúdo que o usuário mandou para
        # outro disco. Ele sai daqui CRU, sem ser reancorado na pasta protegida como 'File': é
        # justamente por estar fora dela que ele existe. Quem o aceita ou recusa é
        # Invoke-WinForgeAclUndo, e o que substitui a pasta protegida é o SHA-256 desta mesma linha.
        # Índice de versão anterior não tem o campo, e '[string]$null' é '' - "não há externo".
        $itens += @{
            Path         = $caminho
            Sddl         = [string]$it.Sddl
            Owner        = [string]$it.Owner
            OwnerSid     = [string]$it.OwnerSid
            File         = $arquivo
            Target       = ([string]$it.Target).Trim()
            Sha256       = ([string]$it.Sha256).Trim()
            ExternalPath = ([string]$it.ExternalPath).Trim()
        }
    }
    return @{ Stamp = [string]$escolhido.Stamp; Index = [string]$escolhido.Path; Items = @($itens); Origin = $escolhido.Origin; Consumed = $false; Pending = $quantos; Refused = $false; Reason = '' }
}

function Invoke-WinForgeAclUndo {
    <#
    .SYNOPSIS
        Reaplica as permissões guardadas pela última restauração de padrões.
    .DESCRIPTION
        Duas formas de voltar, e a diferença é medida, não estilística:

        - A pasta EM SI volta pelo SDDL guardado no índice, aplicado com
          Restore-WinForgeAclSddl (seção Access) e com uma tentativa separada de devolver o dono
          por 'icacls /setowner *<SID> /L /Q' - o .NET não habilita o SeRestorePrivilege e devolver
          a posse ao TrustedInstaller falhava com 1307 mesmo elevado. O 'icacls /save' não serve
          para a lista da pasta em si, e o discriminador é a BARRA no fim do alvo - MEDIDO, e o
          SelfTest confere as duas pontas: 'icacls <pasta>\ /save' (COM a barra) grava a entrada da
          própria pasta com o nome VAZIO, e o '/restore' não a aplica - procura '<pasta>\<sddl>' e
          responde "arquivo não encontrado". Sem a barra o arquivo sai com UM par nomeado pela
          FOLHA, que é outra forma de chamada e a que Get-WinForgeAclIcaclsSddl usa para LER um
          descritor. O que o Desfazer precisa aqui é aplicar, e para isso o SDDL do índice basta.
        - O CONTEÚDO do perfil volta por 'icacls <pasta acima> /restore <arquivo> /C /L', rodado a
          partir da pasta anotada no índice: o icacls grava nomes RELATIVOS à pasta em que foi
          invocado, e restaurar da pasta errada aplicaria a DACL de uma coisa em outra. O '/L' é
          obrigatório e é o par do '/T' do backup: sem ele o '/restore' abre cada item SEGUINDO o
          ponto de reanálise, e a DACL das junções de compatibilidade do perfil ('Dados de
          aplicativos', 'Configurações locais', 'Cookies'), que carregam um Deny de travessia para
          Todos, cairia em AppData\Roaming, AppData\Local e InetCookies - trancando o usuário fora
          do próprio AppData, que é o sintoma que estes botões existem para curar.

        Três conferências antes de qualquer argumento ser montado: a PASTA
        (Confirm-WinForgeAclBackupRoot, regras da pasta padrão), o ÍNDICE - conferido ANTES de ser
        aberto, pelo '-Trusted' de Get-WinForgeAclBackupSet, e não depois do ConvertFrom-Json como
        era - e cada ARQUIVO (Test-WinForgeAclBackupFile: dentro da pasta, direto nela, dono e DACL
        de backup). Índice recusado para tudo; arquivo recusado é pulado com o motivo na tela e não
        derruba os outros, porque um backup adulterado no meio do conjunto não é razão para deixar
        o disco pela metade.

        O arquivo de conteúdo pode ter sido guardado FORA da pasta protegida, num disco que o
        usuário escolheu na restauração: é o campo 'ExternalPath' do item. Ali a conferência de
        pasta não existe - não há como impor DACL a um pen drive -, e quem toma o lugar dela é o
        SHA-256 do ÍNDICE, que continua dentro da pasta protegida. Por isso, para esse arquivo, a
        impressão digital deixa de ser opcional. E quando ele simplesmente não está lá, a mensagem
        diz qual disco ligar antes de dizer qualquer outra coisa: quem clicou neste botão acabou de
        ter as permissões do disco reescritas, e o que ele precisa é da instrução, não do diagnóstico.

        O conjunto é o MAIS ANTIGO ainda não desfeito, e não o mais novo (Get-WinForgeAclBackupSet).
        Antes de o primeiro SDDL virar argumento vêm mais duas portas: a ORIGEM do índice
        (Test-WinForgeAclIndexOrigin - descritor de outra máquina traz SID que não existe aqui) e,
        por item de conteúdo, a IMPRESSÃO DIGITAL que a fase 2 anotou. No fim, um Desfazer sem
        recusa marca o conjunto como consumido (Set-WinForgeAclIndexConsumed), que é o que tira ele
        da fila e libera a próxima restauração.

        O que o resumo afirma também mudou. O '/restore' roda com '/C', e com ele o código de saída
        é 0 quase sempre: contar por ele diria "o icacls rodou", não "as entradas foram aplicadas".
        Depois de cada arquivo, Test-WinForgeAclRestoreSample relê a lista de uma amostra espalhada
        das pastas e compara com o descritor guardado - comportamento, não a frase de resumo do
        icacls, que muda com o idioma. Divergência na amostra deixa o conjunto na fila.

        Sem conjunto nenhum a função apenas DIZ isso. É o caso de quem clica no Desfazer sem nunca
        ter restaurado nada, e ele não é erro.
    .PARAMETER DryRun
        Lista o que seria feito, prefixado com '[simulação] ', sem rodar nada e sem criar a pasta
        de backup.
    .PARAMETER Probe
        Responde só à primeira porta, a elevação, e volta. Ver Invoke-WinForgeAclRestore.
    .PARAMETER BackupRoot
        Pasta de backup alternativa, para o teste. Vale a conferência da pasta padrão.
    .OUTPUTS
        Com -DryRun, as linhas do plano. Com -Probe, @{ Elevated; Reason }. Sem eles, escreve o
        andamento (é um passo de fluxo ao vivo).
    #>
    param(
        [switch]$DryRun,
        [switch]$Probe,
        [string]$BackupRoot
    )

    $icacls = Get-WinForgeSystemExe -Name 'icacls.exe'

    if ($DryRun) {
        $conjunto = Get-WinForgeAclBackupSet -Root $BackupRoot
        if (-not @($conjunto.Items).Count) { return @("[simulação] nada a desfazer: $($conjunto.Reason)") }
        return @($conjunto.Items | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace([string]$_.File)) {
                # A simulação nomeia o arquivo que o '/restore' vai receber de verdade: o de fora,
                # quando o índice traz um 'ExternalPath', e não o nome reancorado na pasta protegida.
                # Mostrar o outro faria a simulação apontar para um arquivo que não existe.
                $arquivoSeco = if (-not [string]::IsNullOrWhiteSpace([string]$_.ExternalPath)) { [string]$_.ExternalPath } else { [string]$_.File }
                "[simulação] $icacls $($_.Target) /restore $arquivoSeco /C /L"
            } elseif ([string]::IsNullOrWhiteSpace([string]$_.OwnerSid)) {
                "[simulação] devolver a lista (SDDL) de '$($_.Path)' (o índice não guardou dono)"
            } else {
                # O dono aparece como o COMANDO que vai rodar, e não como "e o dono": ele volta pelo
                # icacls, que é a única forma de habilitar o SeRestorePrivilege, e quem lê a
                # simulação precisa ver o vetor inteiro - inclusive o '/L'.
                "[simulação] devolver a lista (SDDL) de '$($_.Path)' e o dono com $icacls $($_.Path) /setowner *$($_.OwnerSid) /L /Q"
            }
        })
    }
    if ($Probe) {
        $elevado = [bool](Test-WinForgeRepairElevated)
        return @{ Elevated = $elevado; Reason = $(if ($elevado) { '' } else { 'Esta ação precisa do WinForge aberto como administrador. Nada foi restaurado e nenhuma pasta foi criada.' }) }
    }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeAclUndo'

    # Mesma razão da restauração: a pergunta vem antes de a pasta de backup ser criada ou conferida.
    if (-not (Test-WinForgeRepairElevated)) {
        Write-Error 'Esta ação precisa do WinForge aberto como administrador. Nada foi restaurado e nenhuma pasta foi criada.'
        return
    }
    $conf = Confirm-WinForgeAclBackupRoot -Root $BackupRoot
    if (-not $conf.Ok) {
        Write-Error "A pasta de backup de permissões não é confiável ($($conf.Reason)). Nada foi restaurado."
        return
    }
    # '-Trusted': o índice é conferido ANTES de ser aberto. A ordem é a trava - um arquivo
    # adulterado não passa nem pelo analisador de JSON.
    $conjunto = Get-WinForgeAclBackupSet -Root $BackupRoot -Trusted
    if ($conjunto.Refused) {
        Write-Error "O índice do backup foi recusado ($($conjunto.Reason)). Nada foi restaurado."
        return
    }
    if (-not @($conjunto.Items).Count) {
        Write-Host "Nada a desfazer: $($conjunto.Reason)."
        return
    }
    # A origem, antes de o primeiro SDDL do índice virar argumento: um descritor gravado em outra
    # máquina traz SIDs que não existem aqui, entram como SID cru e trancam o perfil - e o SHA-256
    # do arquivo de conteúdo não diz nada sobre isso, porque quem carrega os SDDL é o ÍNDICE.
    $origem = Test-WinForgeAclIndexOrigin -Index $conjunto
    if (-not $origem.Ok) {
        Write-Error "O índice do backup foi recusado ($($origem.Reason)). Nada foi restaurado."
        return
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$origem.Reason)) { Write-Warning ([string]$origem.Reason) }
    Write-Host "Conjunto de backup $($conjunto.Stamp): $(@($conjunto.Items).Count) item(ns) para restaurar."
    if ([int]$conjunto.Pending -gt 1) { Write-Host "Há $($conjunto.Pending) conjunto(s) por desfazer nesta pasta; este é o mais antigo, e é por ele que se começa." }

    $aplicados = 0
    $recusados = 0
    # Duas contagens, e a diferença entre elas decide se o conjunto sai da fila. RECUSA é problema
    # (backup adulterado, hash que não confere, '/restore' com erro); PULO é a pasta que sumiu desde
    # o backup, que não é problema de ninguém. Enquanto os dois eram a mesma coisa, uma pasta de
    # cache apagada prendia o conjunto para sempre: a restauração seguia recusada, o Desfazer
    # repetia a mesma pasta sumida e a limpeza não alcançava o conjunto.
    $pulados = 0
    $donosFora = @()
    # A conferência por amostragem do conteúdo, somada entre os itens. Ver
    # Test-WinForgeAclRestoreSample: o código de saída do '/restore' com '/C' não serve de sinal.
    $amostraLidas = 0
    $amostraBatem = 0
    $amostraFora = 0
    $amostraSumidas = 0
    $amostraPaths = @()
    foreach ($item in @($conjunto.Items)) {
        # Item sem arquivo é a pasta EM SI, guardada como SDDL no índice.
        if ([string]::IsNullOrWhiteSpace([string]$item.File)) {
            if ([string]::IsNullOrWhiteSpace([string]$item.Sddl)) {
                Write-Error "O índice não traz a lista de '$($item.Path)'; esta pasta fica de fora."
                $recusados++
                continue
            }
            if (-not (Test-Path -LiteralPath ([string]$item.Path) -PathType Container)) {
                # PULO, e não recusa. A pasta sumiu entre o backup e agora: não há o que devolver
                # nela, e o resto do conjunto volta inteiro. Contar isto como recusa prendia o
                # conjunto na fila para sempre - ver a porta da marca de consumido, no fim.
                Write-Warning "A pasta '$($item.Path)' não existe mais; fica de fora."
                $pulados++
                continue
            }
            Write-Host ''
            Write-Host "Devolvendo a lista de permissões de '$($item.Path)'."
            $res = Restore-WinForgeAclSddl -Path ([string]$item.Path) -Sddl ([string]$item.Sddl) -OwnerSid ([string]$item.OwnerSid)
            if (-not $res.DaclOk) {
                Write-Error "A lista de '$($item.Path)' não pôde ser devolvida: $($res.Reason)."
                $recusados++
                continue
            }
            if ($res.OwnerTried -and -not $res.OwnerOk) {
                $donosFora += ("{0} (dono guardado: {1})" -f [string]$item.Path, [string]$item.Owner)
                Write-Warning "A lista voltou, mas o dono de '$($item.Path)' NÃO pôde ser devolvido para '$($item.Owner)': $($res.OwnerReason)"
            }
            $aplicados++
            continue
        }
        # ---- O arquivo do CONTEÚDO, e ele mora num de dois lugares. São dois regimes de confiança
        # diferentes, e por isso duas portas:
        #
        # - Na pasta protegida (o normal), quem responde é Test-WinForgeAclBackupFile: dentro da
        #   pasta, direto nela, dono e DACL de backup.
        # - No disco que o usuário escolheu ('ExternalPath'), não há pasta protegida a conferir - um
        #   pen drive não tem lista de permissões que o WinForge possa impor, e o próprio aviso da
        #   escolha diz isso. O que substitui é o SHA-256 que a fase 2 anotou no ÍNDICE, e o índice
        #   continua dentro da pasta protegida. Consequência direta: aqui a impressão digital deixa
        #   de ser opcional. Sem ela o arquivo externo é RECUSADO, e não apenas avisado.
        $externo = ''
        try { $externo = ([string]$item.ExternalPath).Trim() } catch { $externo = '' }
        $arquivoUsado = [string]$item.File
        if (-not [string]::IsNullOrWhiteSpace($externo)) {
            $arquivoUsado = $externo
            # Rede primeiro, e por texto. A porta do absoluto ACEITA '\\servidor\share' - ele é
            # absoluto de verdade -, e até aqui essa era a única conferência estrutural deste
            # caminho: a escolha do destino recusa rede na primeira regra e o Desfazer não recusava,
            # então um caminho de rede plantado no índice entrava num '/restore' elevado sobre o
            # perfil inteiro. Achado do revisor da Tarefa 7.
            if (Test-WinForgeAclNetworkPath -Path $externo) {
                Write-Error "O índice manda buscar o backup do conteúdo de '$($item.Path)' em '$externo', que é um caminho de rede. O backup das permissões não volta da rede: um compartilhamento pode ser outro entre o backup e agora sem que o caminho mude. Este arquivo fica de fora e nada foi alterado."
                $recusados++
                continue
            }
            # Absoluto de verdade antes de virar argumento: a mesma porta da gravação, e pela mesma
            # medição - 'C:acl.txt' e '\acl.txt' são "rooted" e resolvem contra o diretório do
            # PROCESSO, que aqui é um /restore elevado sobre o perfil inteiro.
            if (-not (Test-WinForgeAclAbsolutePath -Path $externo)) {
                Write-Error "O índice manda buscar o backup do conteúdo de '$($item.Path)' em '$externo', que não é um caminho absoluto. Este arquivo fica de fora e nada foi alterado."
                $recusados++
                continue
            }
            if (-not (Test-Path -LiteralPath $externo -PathType Leaf)) {
                # A pergunta que o usuário tem na cabeça não é "cadê o arquivo", é "qual disco eu
                # tenho de plugar". Quem responde é Get-WinForgeAclDriveHint, a mesma função que a
                # limpeza usa para o mesmo arquivo - a frase tem de ser a mesma nas duas telas, e ela
                # vem INTEIRA de lá porque muda de forma conforme a letra esteja ligada ou não.
                Write-Error "O backup do conteúdo de '$($item.Path)' foi guardado fora da pasta do WinForge, em '$externo', e o arquivo não está lá: $(Get-WinForgeAclDriveHint -Path $externo). Nada foi alterado. Se tiver uma cópia do arquivo original, coloque-a de volta em '$externo' e tente outra vez."
                $recusados++
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$item.Sha256)) {
                Write-Error "O backup do conteúdo de '$($item.Path)' está fora da pasta protegida ('$externo') e o índice não guardou a impressão digital dele. Fora da pasta protegida a impressão digital é a ÚNICA conferência que existe, então este arquivo fica de fora. Nada foi alterado."
                $recusados++
                continue
            }
        } else {
            $julg = Test-WinForgeAclBackupFile -Path ([string]$item.File) -Root ([string]$conf.Path)
            if (-not $julg.Trusted) {
                Write-Error "Backup recusado ('$($item.File)'): $($julg.Reason)."
                $recusados++
                continue
            }
        }
        # A impressão digital que a fase 2 anotou, recalculada agora. É o que descobre, ANTES de o
        # arquivo virar argumento de um '/restore' elevado, que ele deixou de ser o que foi gravado.
        # Índice antigo não traz o campo: aí não há conferência, e isso é dito em vez de fingido.
        # (No arquivo externo isso já foi recusado acima - lá o campo não é opcional.)
        $impressao = [string]$item.Sha256
        if ([string]::IsNullOrWhiteSpace($impressao)) {
            Write-Warning "O backup '$(Split-Path -Leaf $arquivoUsado)' foi gravado por uma versão anterior, sem impressão digital: não há como conferir se ele ainda é o arquivo original."
        } else {
            $conferida = Get-WinForgeAclContentHash -Path $arquivoUsado
            if (-not $conferida.Ok -or ([string]$conferida.Hash -ne $impressao)) {
                $porque = if ($conferida.Ok) { 'a impressão digital SHA-256 não confere com a que a restauração anotou' } else { [string]$conferida.Reason }
                Write-Error "O backup do conteúdo de '$($item.Path)' não é mais o arquivo que a restauração gravou ($porque). Nada foi alterado. Se tiver uma cópia do arquivo original, coloque-a de volta em '$arquivoUsado' e tente outra vez."
                $recusados++
                continue
            }
        }
        if (-not (Test-Path -LiteralPath ([string]$item.Target) -PathType Container)) {
            # Mesmo caso da pasta acima: PULO. O '/restore' precisa da pasta de onde os nomes são
            # relativos, e sem ela não há o que restaurar - o que não é falha de ninguém.
            Write-Warning "A pasta '$($item.Target)' não existe mais; '$(Split-Path -Leaf $arquivoUsado)' fica de fora."
            $pulados++
            continue
        }
        Write-Host ''
        Write-Host "Restaurando o conteúdo de '$($item.Path)' a partir de '$($item.Target)'."
        # '/L' é obrigatório aqui: ver a descrição da função.
        #
        # E o '/C' FICA, ao contrário da fase 5, que roda sem ele. Os dois lados usam o mesmo
        # icacls e recebem tratamento oposto de propósito, porque a pergunta é outra:
        #
        # - Fase 5: alvo ÚNICO, uma pasta por chamada. Não há o que "continuar" dentro de uma
        #   chamada só, então o '/C' apenas apagaria o código de saída - e o código de saída é o
        #   único sinal que aquela fase tem. Lá ele sai, e está MEDIDO (pasta inexistente: 2 sem
        #   '/C', 0 com).
        # - Aqui: uma chamada para um arquivo de CENTENAS de entradas. Continuar apesar do erro é o
        #   comportamento desejado - uma pasta que sumiu desde o backup não pode custar a
        #   restauração das outras 337. Sem '/C' o icacls pode PARAR na primeira entrada morta, e
        #   abortar no meio é pior do que contar errado: quem clica neste botão acabou de ter as
        #   permissões do disco reescritas e ele é o último recurso.
        #
        # O preço do '/C' é que o código de saída vira 0 quase sempre: sozinho, ele diz "o icacls
        # rodou", e não "todas as entradas foram aplicadas". Quem devolve o sinal é a CONFERÊNCIA
        # POR AMOSTRAGEM logo abaixo - reler a lista de algumas das pastas restauradas e comparar
        # com o descritor guardado no arquivo. É comportamento, e por isso não depende do idioma do
        # sistema, que é justamente o que ler a frase de resumo do icacls não garante (a integração
        # contínua deste projeto roda em inglês e já quebrou uma asserção assim).
        $r = Invoke-WinForgeNativeCommand -FilePath $icacls -Arguments @([string]$item.Target, '/restore', $arquivoUsado, '/C', '/L')
        Write-Host ([string]$r.Text)
        if ([int]$r.ExitCode -ne 0) {
            Write-Error "Este arquivo terminou com código $($r.ExitCode)."
            $recusados++
            continue
        }
        $aplicados++
        $amostra = Test-WinForgeAclRestoreSample -Root ([string]$item.Target) -File $arquivoUsado
        if (-not $amostra.Ok) {
            Write-Warning "A conferência por amostragem de '$($item.Path)' não pôde ser feita ($($amostra.Reason)); o resultado deste arquivo fica sem confirmação."
        } else {
            $amostraLidas += [int]$amostra.Checked
            $amostraBatem += [int]$amostra.Match
            $amostraFora += [int]$amostra.Differ
            $amostraSumidas += [int]$amostra.Missing
            foreach ($p in @($amostra.Paths)) { if ($amostraPaths.Count -lt 10) { $amostraPaths += [string]$p } }
            Write-Host ("Conferência por amostragem: {0} de {1} pasta(s) relidas conferem com o backup ({2} de {3} entradas do arquivo)." -f $amostra.Match, $amostra.Checked, $amostra.Checked, $amostra.Total)
        }
    }
    Write-Host ''
    Write-Host "Desfazer concluído: $aplicados item(ns) processados, $recusados recusado(s), $pulados pulada(s) por já não existirem."
    # O resumo diz o que foi CONFERIDO, e não "restaurado": o '/restore' com '/C' não garante que
    # todas as entradas foram aplicadas, e prometer isso seria a mesma mentira que o código de saída
    # conta. A amostra também não promete o arquivo inteiro, e o texto diz isso.
    if ($amostraLidas -gt 0) {
        Write-Host "Conferência por amostragem do conteúdo: de $amostraLidas pasta(s) relidas, $amostraBatem conferem com o backup, $amostraFora não conferem e $amostraSumidas já não existem. A conferência é por amostra - ela não afirma que todas as entradas do arquivo voltaram."
    }
    if ($amostraFora -gt 0) {
        Write-Error ("A lista de $amostraFora pasta(s) da amostra NÃO voltou ao que o backup guardava (por exemplo: {0}). O conjunto $($conjunto.Stamp) continua na fila do Desfazer para você tentar de novo." -f (@($amostraPaths) -join '; '))
    }
    if ($donosFora.Count) {
        Write-Warning ("O dono NÃO voltou em: {0}. Devolver a posse ao TrustedInstaller exige um privilégio que nem todo administrador tem; a lista de permissões dessas pastas voltou do mesmo jeito." -f ($donosFora -join '; '))
    }
    # A marca de consumido é o que tira este conjunto da fila e deixa a próxima restauração começar.
    # Ela só vem quando NÃO houve recusa nem divergência na amostra: marcar um Desfazer que falhou
    # pela metade esconderia o backup que o usuário ainda precisa.
    #
    # PULO não entra nessa conta, e essa é a diferença que faltava. Pasta que sumiu desde o backup é
    # o caso mais comum do mundo dentro de um perfil, e enquanto ela contava como recusa o conjunto
    # ficava pendente para sempre - com a restauração recusada por causa dele e o Desfazer batendo
    # na mesma pasta inexistente a cada tentativa.
    if ($recusados -eq 0 -and $amostraFora -eq 0) {
        $marca = Set-WinForgeAclIndexConsumed -Path ([string]$conjunto.Index)
        if ($marca.Ok) {
            Write-Host "O conjunto $($conjunto.Stamp) sai da fila do Desfazer; a pasta e o arquivo continuam no disco até você usar 'Limpar backups antigos'."
            # 'Ok' e 'Hardened' são duas respostas, e a segunda morria aqui: a marca foi gravada (o
            # conjunto sai da fila) e o índice ficou com o dono de quem o gravou - que é justamente o
            # dono que a conferência do Desfazer SEGUINTE recusa. Sem este aviso, o usuário só
            # descobre no próximo Desfazer, quando o índice é recusado sem explicação nenhuma.
            if (-not $marca.Hardened) { Write-Warning "Conjunto $($conjunto.Stamp): $($marca.Reason). Se um Desfazer futuro recusar este índice por causa do dono, use 'Limpar backups antigos' para tirá-lo do caminho." }
        }
        else { Write-Warning "O conjunto $($conjunto.Stamp) não pôde ser marcado como desfeito ($($marca.Reason)); ele continua aparecendo como pendente." }
    } else {
        Write-Host "O conjunto $($conjunto.Stamp) continua na fila do Desfazer, porque nem tudo voltou."
    }
    Write-Host 'O que volta de cada pasta é a lista DELA MESMA, mais o dono quando dá. O conteúdo de dentro só volta na sua pasta de usuário, que é a única guardada com recursão.'
    Write-Host 'Reinicie o computador para que os programas já abertos passem a enxergar as permissões que voltaram.'
}

function Get-WinForgeAclDriveHint {
    <#
    .SYNOPSIS
        A INSTRUÇÃO de tela para quem procura um backup que foi para outro disco. Só lê.
    .DESCRIPTION
        A pergunta que o usuário tem na cabeça quando o backup foi para outro disco não é "cadê o
        arquivo", é "qual disco eu tenho de plugar". Quem responde é esta função, e ela devolve a
        frase INTEIRA - não um pedaço para quem chama emendar. Os dois chamadores (o Desfazer e a
        limpeza) mostram a mesma coisa, e a frase muda de forma entre os casos: emendá-la fora daqui
        obrigaria os dois a repetir a decisão.

        São três casos, e o terceiro é o que essa frase errava antes. Achado do revisor da Tarefa 7:

        1. Sem raiz no caminho - não há letra a nomear, e a instrução é genérica.
        2. A letra NÃO está ligada. É o caso comum, e a instrução é "ligue o disco <letra>". O
           rótulo não entra: ler '.VolumeLabel' de um volume ausente LANÇA, e
           '[string]$obj.Propriedade' sobre propriedade que lança devolve '' em silêncio - o que
           daria um "( )" sem sentido no meio da frase. O WinForge nunca guardou o rótulo do disco
           no índice, então quando ele some não há de onde tirar o nome.
        3. A letra ESTÁ ligada e o arquivo não está lá. Mandar "ligue o disco E: (Backup)" aqui era
           mandar ligar um disco que já está ligado, com o rótulo de OUTRO volume - o que estiver
           nessa letra agora. As duas explicações possíveis são honestas e cabem na frase: ou a
           letra foi reaproveitada por outro disco, ou o arquivo foi apagado de lá.
    .OUTPUTS
        A frase, começando em minúscula e terminando em "tente de novo", para entrar depois de um
        dois-pontos.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $raiz = ''
    try { $raiz = [string][System.IO.Path]::GetPathRoot([string]$Path) } catch { $raiz = '' }
    $letra = $raiz.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($letra)) { return 'ligue o disco em que o backup foi guardado e tente de novo' }
    $ligada = $false
    $rotulo = ''
    try {
        $unidade = New-Object System.IO.DriveInfo ($raiz)
        if ($unidade.IsReady) {
            $ligada = $true
            $nome = [string]$unidade.VolumeLabel
            $rotulo = if ([string]::IsNullOrWhiteSpace($nome)) { 'sem rótulo' } else { $nome }
        }
    } catch {
        $ligada = $false
        $rotulo = ''
    }
    if (-not $ligada) { return "ligue o disco $letra e tente de novo" }
    return "a letra $letra está ligada agora e tem o rótulo '$rotulo', então ou essa letra é de outro disco, ou o arquivo foi apagado de lá; ligue o disco em que o backup foi guardado e tente de novo"
}

function Get-WinForgeAclBackupInventory {
    <#
    .SYNOPSIS
        O que existe na pasta de backups de permissões: cada arquivo com tamanho, data, tipo, e se
        algum índice ainda precisa dele. Só lê.
    .DESCRIPTION
        É a lista que o botão de limpeza mostra antes de apagar qualquer coisa, e a mesma que a
        varredura de abertura soma para dizer quanto a pasta ocupa.

        Duas classes de arquivo moram ali: o ÍNDICE ('acl-index-<carimbo>.json', que carrega o SDDL
        e o dono de cada pasta) e o CONTEÚDO (o arquivo de 'icacls /save' do perfil). ÓRFÃO é
        arquivo de conteúdo que índice nenhum referencia - nem por 'File' nem por 'ExternalPath'.
        Ele aparece quando uma restauração grava o arquivo do perfil e morre antes de gravar o
        índice: o arquivo fica no disco, do tamanho que for, e não serve para desfazer nada.

        'Consumed' de um arquivo de conteúdo é o E de todos os índices que o citam: um índice
        pendente no meio segura o arquivo inteiro. É essa conta que impede a limpeza de levar o
        arquivo do perfil de um backup que ninguém desfez ainda.

        Índice que NÃO PÔDE SER LIDO cega a pasta, e aqui isso é decisivo: sem saber o que ele
        referenciava, chamar de órfão qualquer arquivo de conteúdo seria apagar justamente o backup
        que ele cobre. Com um ilegível na pasta, NENHUM arquivo de conteúdo é marcado como órfão -
        que é o lado seguro do erro.

        O ÍNDICE ilegível em si, ao contrário, sai marcado com 'Unreadable' e é alvo de limpeza
        sempre. Não é generosidade: o Desfazer não consegue aplicá-lo (Get-WinForgeAclBackupSet
        devolve zero item para um índice que não abre), ele conta como PENDENTE na guarda da segunda
        restauração, e enquanto ele fica na pasta a restauração está recusada e a pasta está cega.
        Era um beco sem saída - a recusa mandava limpar e a limpeza respondia "nada a apagar".
        Reparar que ele é ilegível não depende de interpretar o conteúdo dele, que é justamente o
        que não dá para fazer.

        A ordem é ORDINAL, por CompareOrdinal, como no resto deste arquivo: 'Sort-Object' ordena
        pela CULTURA, e '-Culture' recebe uma STRING - passar um objeto de cultura vira '' em
        silêncio e a comparação continua linguística.
    .PARAMETER Root
        Pasta de backup alternativa, para o teste. A padrão é Get-WinForgeAclBackupRoot.
    .OUTPUTS
        @(@{ Name; Path; Bytes; Date; Kind = 'indice'|'conteudo'; Orphan = <bool>; Consumed = <bool>;
        Unreadable = <bool>; External = <bool>; Missing = <bool>; Trusted = <bool> }), em ordem
        ordinal por nome. Com 'External', 'Path' é o caminho COMPLETO no outro disco e 'Missing' diz
        que ele não está lá agora - disco desligado, que é o caso comum e não um erro. 'Trusted' é
        se o índice que NOMEIA aquele caminho passou em Test-WinForgeAclBackupFile: só caminho
        confiável pode virar argumento de uma remoção elevada.
    #>
    param([string]$Root)

    $dir = Get-WinForgeAclBackupRoot $Root
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $arquivos = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)
    if (-not $arquivos.Count) { return @() }

    $indices = @(Get-WinForgeAclIndexList -Root $dir)
    $cego = [bool]@($indices | Where-Object { -not $_.Readable }).Count
    # SEGUNDA passada, com exigência de CONFIANÇA, e ela existe por segurança e não por arrumação.
    # O caminho de um arquivo DENTRO da pasta sai de Get-ChildItem - conteúdo de arquivo nenhum
    # escolhe esse caminho. Já 'ExternalPath' sai de DENTRO do índice, que é um arquivo de texto, e
    # vira argumento de um Remove-Item ELEVADO: se esse índice puder ser reescrito por um processo
    # de integridade média, quem escolhe o que a limpeza apaga é aquele processo. Test-WinForgeAclBackupFile
    # é quem separa os dois casos, e o '-Trusted' a aplica ANTES de o JSON ser analisado.
    $confiaveis = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($idx in @(Get-WinForgeAclIndexList -Root $dir -Trusted)) {
        if (-not $idx.Refused) { [void]$confiaveis.Add([string]$idx.Path) }
    }
    # Quem é citado por quem. O índice nomeia o arquivo de conteúdo pelo NOME, e é o Desfazer que
    # reancora esse nome dentro da pasta protegida - por isso a chave aqui também é o nome, e a
    # folha é tirada com Split-Path para um 'sub\..\x.txt' plantado no índice não virar chave nova.
    $citados = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($idx in $indices) {
        foreach ($it in @($idx.Items)) {
            # '[string]$obj.Propriedade' sobre propriedade que lança devolve '' em silêncio (medido),
            # e '' aqui é "não cita nada" - que é o tratamento certo, não um atalho.
            $campos = @()
            try { $campos += ([string]$it.File).Trim() } catch { }
            try { $campos += ([string]$it.ExternalPath).Trim() } catch { }
            foreach ($campo in $campos) {
                if ([string]::IsNullOrWhiteSpace($campo)) { continue }
                $folha = ''
                try { $folha = [string](Split-Path -Leaf $campo) } catch { $folha = '' }
                if ([string]::IsNullOrWhiteSpace($folha)) { continue }
                if ($citados.ContainsKey($folha)) { $citados[$folha] = $citados[$folha] -and [bool]$idx.Consumed }
                else { $citados[$folha] = [bool]$idx.Consumed }
            }
        }
    }

    $saida = New-Object System.Collections.Generic.List[object]
    foreach ($f in $arquivos) {
        $nome = [string]$f.Name
        $tipo = if ($nome -match '^acl-index-.+\.json$') { 'indice' } else { 'conteudo' }
        $consumido = $false
        $orfao = $false
        $ilegivel = $false
        if ($tipo -eq 'indice') {
            $meu = @($indices | Where-Object { [string]$_.Path -eq [string]$f.FullName })
            if ($meu.Count) {
                $consumido = [bool]$meu[0].Consumed
                $ilegivel = -not [bool]$meu[0].Readable
            }
        } elseif ($citados.ContainsKey($nome)) {
            $consumido = [bool]$citados[$nome]
        } else {
            $orfao = -not $cego
        }
        $saida.Add(@{
            Name       = $nome
            Path       = [string]$f.FullName
            Bytes      = [long]$f.Length
            Date       = $f.LastWriteTime
            Kind       = $tipo
            Orphan     = $orfao
            Consumed   = $consumido
            Unreadable = $ilegivel
            External   = $false
            Missing    = $false
            # Caminho que saiu de Get-ChildItem sobre a pasta já conferida: conteúdo de arquivo
            # nenhum o escolheu, então não há o que desconfiar dele.
            Trusted    = $true
        })
    }

    # Os arquivos de conteúdo que foram para OUTRO disco ('ExternalPath'). Eles não saem de
    # Get-ChildItem - não estão nesta pasta -, e é justamente por isso que precisam sair daqui: sem
    # eles a limpeza apagava metade do backup e deixava a outra metade num pen drive, sem uma linha
    # dizendo isso. Quem os nomeia é o índice, que continua dentro da pasta protegida.
    #
    # 'Missing' é o disco desligado, que é o caso comum, e não um erro: o item aparece na lista
    # assim mesmo, porque omitir em silêncio é o que se está consertando. 'Orphan' nunca vale aqui -
    # se ele está nesta lista é porque um índice o citou.
    $externos = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::OrdinalIgnoreCase)
    $externosFiaveis = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($idx in $indices) {
        $idxFiavel = $confiaveis.Contains([string]$idx.Path)
        foreach ($it in @($idx.Items)) {
            $ext = ''
            try { $ext = ([string]$it.ExternalPath).Trim() } catch { $ext = '' }
            if ([string]::IsNullOrWhiteSpace($ext)) { continue }
            if ($externos.ContainsKey($ext)) {
                $externos[$ext] = $externos[$ext] -and [bool]$idx.Consumed
                # Um índice não confiável no meio derruba a confiança do caminho inteiro: basta um
                # para que a escolha do caminho tenha passado por mãos erradas.
                $externosFiaveis[$ext] = $externosFiaveis[$ext] -and $idxFiavel
            } else {
                $externos[$ext] = [bool]$idx.Consumed
                $externosFiaveis[$ext] = $idxFiavel
            }
        }
    }
    foreach ($ext in @($externos.Keys)) {
        $info = $null
        try { if (Test-Path -LiteralPath $ext -PathType Leaf) { $info = Get-Item -LiteralPath $ext -ErrorAction Stop } } catch { $info = $null }
        $folhaExt = ''
        try { $folhaExt = [string](Split-Path -Leaf $ext) } catch { $folhaExt = '' }
        if ([string]::IsNullOrWhiteSpace($folhaExt)) { $folhaExt = $ext }
        $saida.Add(@{
            Name       = $folhaExt
            Path       = [string]$ext
            Bytes      = $(if ($null -ne $info) { [long]$info.Length } else { [long]0 })
            Date       = $(if ($null -ne $info) { $info.LastWriteTime } else { $null })
            Kind       = 'conteudo'
            Orphan     = $false
            Consumed   = [bool]$externos[$ext]
            Unreadable = $false
            External   = $true
            Missing    = ($null -eq $info)
            Trusted    = [bool]$externosFiaveis[$ext]
        })
    }
    $arr = $saida.ToArray()
    [array]::Sort($arr, [System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal([string]$a.Name, [string]$b.Name) })
    return @($arr)
}

function Get-WinForgeAclBackupSizeWarning {
    <#
    .SYNOPSIS
        Diz se a pasta de backups de permissões passou do limite de tamanho, e com que frase avisar.
        SÓ RELATA.
    .DESCRIPTION
        A varredura de abertura do WinForge. O caso real é o de quem matou a 1.7.0 no meio da fase 2:
        o 'icacls /save' do perfil inteiro já tinha gravado centenas de GB numa pasta que só o
        SYSTEM e os Administradores apagam, e ninguém contou isso a ele - o disco simplesmente
        encheu.

        Esta função não apaga nada e nunca vai apagar: ela responde, e quem apaga é o botão, depois
        de o usuário ler a lista e confirmar. Um aviso de abertura que apagasse arquivo por conta
        própria levaria junto o backup de quem ainda não desfez.
    .PARAMETER LimitBytes
        O limite. O padrão é 1 GB (1073741824), que é o ponto em que a pasta deixa de ser detalhe.
    .OUTPUTS
        @{ Over = <bool>; Bytes = <long>; Text = <string> }. 'Text' vem vazio quando não passou: não
        há o que dizer a quem tem uma pasta de alguns megabytes.
    #>
    param([string]$Root, [long]$LimitBytes = 1073741824)

    # Só o que está NA PASTA. O arquivo de conteúdo que foi para outro disco também faz parte do
    # backup, mas a frase daqui é sobre o espaço que o WinForge ocupa em %ProgramData% - somar o pen
    # drive do usuário nessa conta seria acusar a pasta por espaço que não é dela.
    $itens = @(Get-WinForgeAclBackupInventory -Root $Root | Where-Object { -not $_.External })
    $total = [long]0
    foreach ($i in $itens) { $total += [long]$i.Bytes }
    $r = @{ Over = $false; Bytes = $total; Text = '' }
    if (-not $itens.Count -or $total -lt $LimitBytes) { return $r }
    $r.Over = $true
    $tamanho = if ($total -ge 1GB) { '{0:N1} GB' -f ($total / 1GB) } else { '{0:N1} MB' -f ($total / 1MB) }
    $orfaos = @($itens | Where-Object { $_.Orphan }).Count
    $r.Text = "Os backups de permissões do WinForge ocupam $tamanho em '$(Get-WinForgeAclBackupRoot $Root)' ($($itens.Count) arquivo(s), $orfaos sem índice que os use). Use o botão 'Permissões do disco C: - Limpar backups antigos', na aba Config, para descartar o que não interessa mais."
    return $r
}

function Show-WinForgeAclBackupSizeWarning {
    <#
    .SYNOPSIS
        Põe o aviso da pasta de backups de permissões no log e na barra de status, na abertura da
        janela. Não apaga nada e não abre caixa de mensagem nenhuma.
    .DESCRIPTION
        Pendurada no mesmo gancho de Start-WinForgeProfileJob, em DispatcherPriority::Background: a
        varredura é leitura de uma pasta só e não justifica um runspace, mas também não pode segurar
        a janela antes de ela aparecer.

        Log e barra, e nunca caixa de mensagem: quem abre o WinForge abriu para fazer outra coisa, e
        uma caixa modal na abertura por causa de espaço em disco é a definição de aviso que se fecha
        no susto. Quem decide o que fazer é o usuário, no botão, com a lista na frente.

        Nada escapa daqui. O que roda no Dispatcher da janela roda na thread da interface: uma
        exceção solta neste bloco derruba o programa na abertura, e derrubar o WinForge por causa de
        um aviso de espaço em disco seria trocar um incômodo por um defeito.
    .OUTPUTS
        $true se avisou, $false se a pasta está dentro do limite ou se a varredura não pôde ser feita.
    #>
    param([string]$Root, [long]$LimitBytes = 1073741824)

    try {
        $aviso = Get-WinForgeAclBackupSizeWarning -Root $Root -LimitBytes $LimitBytes
        if (-not $aviso.Over) { return $false }
        Write-WinForgeLog -Component "Repair" -Level "WARN" -Message ([string]$aviso.Text)
        $null = Set-WinForgeProfileProgress -Label ([string]$aviso.Text) -Percent 100
        return $true
    } catch {
        try { Write-WinForgeLog -Component "Repair" -Level "WARN" -Message "A pasta de backup de permissões não pôde ser medida: $($_.Exception.Message)" } catch { }
        return $false
    }
}

function Test-WinForgeAclCleanupPhrase {
    <#
    .SYNOPSIS
        Diz se o que o usuário digitou vale como confirmação do descarte de backup pendente. Função
        pura, só texto.
    .DESCRIPTION
        Descartar conjunto que ninguém desfez é a única ação destes botões que joga fora um backup
        bom, e por isso ela não se confirma com um clique em "Sim": pede a palavra digitada. A caixa
        de Sim/Não do clique continua existindo e é outra coisa - ela autoriza a limpeza, esta
        autoriza o descarte.

        As folgas são as que um humano comete e que não mudam a intenção: espaço em volta e
        maiúscula/minúscula. O resto não passa - 'APAGA' não é 'APAGAR', e 'APAGAR TUDO' também não:
        quem digitou a mais não digitou a palavra pedida, e aceitar um prefixo ou um superconjunto
        seria transformar a trava em decoração.

        A palavra é ASCII de propósito. Uma palavra acentuada num teclado que o usuário pode não ter
        configurado, ou numa sessão com outra página de código, viraria uma trava impossível de
        passar em vez de uma trava deliberada.
    .PARAMETER Phrase
        A palavra exigida. Existe para o teste; o padrão é a de verdade.
    .OUTPUTS
        $true ou $false.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Typed,
        [string]$Phrase = 'APAGAR'
    )

    if ($null -eq $Typed) { return $false }
    return [string]::Equals(([string]$Typed).Trim(), ([string]$Phrase).Trim(), [StringComparison]::OrdinalIgnoreCase)
}

function Show-WinForgeAclCleanupConfirm {
    <#
    .SYNOPSIS
        A caixa que pede a palavra digitada antes de descartar backup que ninguém desfez.
    .DESCRIPTION
        Montada em código, e não em XAML, pelo mesmo motivo de Show-WinForgeOutputWindow: ela nasce
        de um caminho que o -SelfTest precisa exercitar sem abrir nada na tela, e o '-NoShow'
        devolve a janela pronta para o teste ler os controles por nome.

        O botão de descartar nasce DESABILITADO e só liga quando o que está na caixa passa por
        Test-WinForgeAclCleanupPhrase. É a diferença entre uma trava e um aviso: com o botão sempre
        ligado, a palavra digitada seria enfeite.

        A mensagem nomeia os conjuntos que vão embora, um por linha. Quem chegou aqui tem um backup
        pendente e precisa saber QUAL, porque a resposta certa muitas vezes é fechar esta caixa e
        usar o Desfazer.
    .PARAMETER NoShow
        Devolve a janela sem mostrar. É o que o -SelfTest usa.
    .OUTPUTS
        Com -NoShow, a janela ([System.Windows.Window]). Sem ele, $true se o usuário confirmou.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Stamps,
        [long]$Bytes = 0,
        [switch]$NoShow
    )

    # Em uso normal o WPF já está carregado desde a montagem da janela principal. No -SelfTest não:
    # sem os dois assemblies o primeiro [System.Windows.*] do corpo falharia.
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')

    $janela = New-Object System.Windows.Window
    $janela.Title = 'WinForge - Descartar backup de permissões'
    $janela.Width = 620
    $janela.SizeToContent = [System.Windows.SizeToContent]::Height
    $janela.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    if ($null -ne $sync -and $null -ne $sync.Form -and $sync.Form.IsVisible) {
        try {
            $janela.Owner = $sync.Form
            $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        } catch { }
    }

    $pilha = New-Object System.Windows.Controls.StackPanel
    $pilha.Margin = New-Object System.Windows.Thickness 14

    $tamanho = if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) } else { '{0:N1} MB' -f ($Bytes / 1MB) }
    $aviso = New-Object System.Windows.Controls.TextBlock
    $aviso.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $aviso.Text = "Estes backups de permissões NÃO foram desfeitos, e descartá-los é definitivo: depois disso o botão Desfazer não tem mais o que devolver.`r`n`r`nConjunto(s): $(@($Stamps) -join ', ')`r`nTotal a apagar: $tamanho`r`n`r`nSe você ainda quer as permissões antigas de volta, feche esta caixa e use 'Permissões do disco C: - Desfazer (restaurar backup)' primeiro.`r`n`r`nPara descartar mesmo assim, digite APAGAR abaixo."
    $pilha.Children.Add($aviso) | Out-Null

    $caixa = New-Object System.Windows.Controls.TextBox
    $caixa.Margin = New-Object System.Windows.Thickness (0, 12, 0, 0)
    $caixa.FontSize = 14
    $pilha.Children.Add($caixa) | Out-Null

    $barra = New-Object System.Windows.Controls.StackPanel
    $barra.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $barra.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $barra.Margin = New-Object System.Windows.Thickness (0, 14, 0, 0)
    $pilha.Children.Add($barra) | Out-Null

    $btnDescartar = New-Object System.Windows.Controls.Button
    $btnDescartar.Content = 'Descartar'
    $btnDescartar.MinWidth = 120
    $btnDescartar.Padding = New-Object System.Windows.Thickness (10, 4, 10, 4)
    $btnDescartar.IsEnabled = $false
    $barra.Children.Add($btnDescartar) | Out-Null

    $btnCancelar = New-Object System.Windows.Controls.Button
    $btnCancelar.Content = 'Cancelar'
    $btnCancelar.MinWidth = 120
    $btnCancelar.Margin = New-Object System.Windows.Thickness (8, 0, 0, 0)
    $btnCancelar.Padding = New-Object System.Windows.Thickness (10, 4, 10, 4)
    $btnCancelar.IsCancel = $true
    $barra.Children.Add($btnCancelar) | Out-Null

    $caixa.Add_TextChanged({ $btnDescartar.IsEnabled = [bool](Test-WinForgeAclCleanupPhrase -Typed ([string]$caixa.Text)) }.GetNewClosure())
    $btnDescartar.Add_Click({ $janela.DialogResult = $true }.GetNewClosure())

    $janela.Content = $pilha
    [System.Windows.NameScope]::SetNameScope($janela, (New-Object System.Windows.NameScope))
    $janela.RegisterName('WFAclCleanupText', $aviso)
    $janela.RegisterName('WFAclCleanupPhrase', $caixa)
    $janela.RegisterName('WFAclCleanupOk', $btnDescartar)

    if ($NoShow) { return $janela }
    return [bool]($janela.ShowDialog() -eq $true)
}

# O pedido de descarte esperando a thread da janela: quem escreve é o runspace do fluxo ao vivo,
# quem lê é o callback abaixo. Mesmo desenho de $sync.WinForgeDriverConfirm, e pela mesma razão -
# um scriptblock criado numa runspace do pool e executado pelo Dispatcher trava na primeira
# pipeline, porque a thread da janela pede a runspace de origem, que está parada esperando o
# Dispatcher terminar.
$sync.WinForgeAclCleanupConfirm = $null

$sync.WinForgeAclCleanupConfirmCallback = {
    $pedido = $sync.WinForgeAclCleanupConfirm
    if ($null -eq $pedido) { return }
    try {
        $pedido.Answer = [bool](Show-WinForgeAclCleanupConfirm -Stamps @($pedido.Stamps) -Bytes ([long]$pedido.Bytes))
    } catch {
        $pedido.Answer = $false
        Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message "A confirmação do descarte de backups pendentes falhou: $($_.Exception.Message)"
    }
}

function Request-WinForgeAclCleanupDiscard {
    <#
    .SYNOPSIS
        Leva o pedido de descarte de backup pendente até a thread da janela e volta com a resposta.
    .DESCRIPTION
        A limpeza roda num runspace do pool, e caixa de diálogo é da thread da janela. O salto é o
        mesmo de $sync.WinForgeDriverConfirm: o pedido viaja por um slot de $sync e o callback, que
        nasceu na runspace principal, é chamado por Invoke-WPFUIThread.

        Sem janela (uma sessão sem interface) a resposta é NÃO, e não "sim por omissão": não há quem
        digite a palavra, e descartar backup bom porque ninguém estava lá para recusar é exatamente
        o estrago que a palavra digitada existe para impedir.

        Janela FECHANDO responde NÃO antes de qualquer outra coisa, como no download de driver da aba
        Diagnóstico: Invoke-WPFUIThread é Dispatcher.Invoke SÍNCRONO, e chamá-lo com o Dispatcher
        desligando deixa a thread do pool parada esperando por ele - a limpeza não termina e o
        fechamento não completa.
    .OUTPUTS
        $true só quando alguém digitou a palavra e clicou em Descartar.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Stamps,
        [long]$Bytes = 0
    )

    if ($sync.WinForgeClosing) { return $false }
    if ($null -eq $sync -or $null -eq $sync.Form) { return $false }
    $sync.WinForgeAclCleanupConfirm = @{ Stamps = @($Stamps); Bytes = [long]$Bytes; Answer = $false }
    try {
        Invoke-WPFUIThread $sync.WinForgeAclCleanupConfirmCallback
    } catch {
        Write-WinForgeLog -Component "Repair" -Level "ERROR" -Message "O pedido de descarte não chegou à janela: $($_.Exception.Message)"
        $sync.WinForgeAclCleanupConfirm = $null
        return $false
    }
    $resposta = $false
    try { $resposta = [bool]$sync.WinForgeAclCleanupConfirm.Answer } catch { $resposta = $false }
    $sync.WinForgeAclCleanupConfirm = $null
    return $resposta
}

function Invoke-WinForgeAclCleanup {
    <#
    .SYNOPSIS
        Apaga da pasta protegida os backups de permissões que ninguém mais usa, e só esses.
    .DESCRIPTION
        É a outra metade da guarda da segunda restauração (Test-WinForgeAclRestoreAllowed). Numa
        máquina que rodou a 1.7.0 o índice antigo não tem o campo 'Consumed', conta como PENDENTE e
        recusa toda restauração nova: ou o usuário desfaz aquele backup, ou o descarta aqui. Sem
        este botão a recusa era um beco sem saída, porque a pasta só o SYSTEM e os Administradores
        apagam - o Explorer do próprio dono da máquina responde "acesso negado".

        Sai daqui exatamente o que Get-WinForgeAclBackupInventory marca:

        - ÓRFÃO: arquivo de conteúdo que índice nenhum referencia. Ele é o rastro de uma restauração
          que morreu entre gravar o arquivo do perfil e gravar o índice - o maior arquivo da pasta,
          e o único que não serve para desfazer coisa alguma.
        - CONJUNTO JÁ DESFEITO: o índice marcado como consumido e o arquivo de conteúdo que só ele
          referencia. O Desfazer já aplicou aquilo; guardar de novo não devolve nada.
        - ÍNDICE ILEGÍVEL: o que não abre. O Desfazer não consegue aplicá-lo, ele conta como
          pendente na guarda da segunda restauração e cega o inventário. Enquanto ele fica, a
          restauração está recusada e a pasta não pode ser limpa - era um beco sem saída.

        Backup que ninguém desfez só sai com -DiscardPending, e essa é a saída que faltava. Sem ela,
        um conjunto pendente por qualquer motivo - uma pasta que sumiu desde o backup, um arquivo de
        conteúdo ausente, um hash divergente, um '/restore' com código diferente de zero, uma
        divergência na amostra - prendia a máquina: a restauração recusada, a limpeza sem alvo e o
        Desfazer repetindo a mesma falha. No cenário que originou tudo isto, duas execuções da
        1.7.0, o usuário saía obrigado a aplicar justamente o conjunto ruim para se livrar dele.

        O preço de -DiscardPending é uma confirmação DIGITADA, e não mais um clique em "Sim":
        Request-WinForgeAclCleanupDiscard leva o pedido até a thread da janela e a pessoa tem de
        escrever a palavra. É a única ação destes botões que joga fora backup bom.

        A confirmação do CLIQUE (a caixa Sim/Não com o texto da aba Config) continua valendo para a
        limpeza toda, e a LISTA vai para a tela antes do primeiro arquivo sair: é fluxo ao vivo, e
        quem está olhando vê nome, tamanho e motivo de cada um.
    .PARAMETER DryRun
        Lista o que seria apagado, prefixado com '[simulação] ', sem apagar nada e sem criar a pasta
        de backup.
    .PARAMETER Probe
        Responde só à primeira porta, a elevação, e volta. Ver Invoke-WinForgeAclRestore.
    .PARAMETER DiscardPending
        Inclui os conjuntos que ninguém desfez. No caminho de verdade quem liga isto é a confirmação
        digitada; no -DryRun é o teste, que precisa provar a seleção sem abrir janela nenhuma.
    .PARAMETER BackupRoot
        Pasta de backup alternativa, para o teste. Vale a conferência da pasta padrão.
    .OUTPUTS
        Com -DryRun, as linhas do plano. Com -Probe, @{ Elevated; Reason }. Sem eles, escreve o
        andamento (é um passo de fluxo ao vivo).
    #>
    param(
        [switch]$DryRun,
        [switch]$Probe,
        [switch]$DiscardPending,
        [string]$BackupRoot
    )

    # 'Descartável sem perguntar mais nada': o que não serve para desfazer coisa alguma. O que sobra
    # é backup pendente, e ele só sai pela confirmação digitada.
    $solto = {
        param($item)
        [bool]($item.Orphan -or $item.Consumed -or $item.Unreadable)
    }
    $motivo = {
        param($item)
        if ($item.Unreadable) { return 'índice ilegível - o Desfazer não consegue aplicá-lo' }
        if ($item.Orphan) { return 'nenhum índice o referencia' }
        if ($item.Consumed) { if ([string]$item.Kind -eq 'indice') { return 'conjunto já desfeito' } else { return 'conteúdo de conjunto já desfeito' } }
        return 'DESCARTADO a pedido - ninguém desfez este backup'
    }
    # O que aparece na tela de um item de OUTRO disco é o caminho COMPLETO, e não a folha: 'ligue o
    # disco' só ajuda quem sabe qual. E o item ausente sai com o motivo do disco em vez de sumir da
    # lista - omitir em silêncio era o defeito.
    # O WinForge só entrega a um Remove-Item ELEVADO caminho em que ele confia. Caminho de dentro da
    # pasta vem de Get-ChildItem sobre a pasta já conferida; caminho de FORA vem de dentro de um
    # índice, e só vale se aquele índice passou na conferência de confiança. Sem esta porta, um
    # processo de integridade média que consiga reescrever um índice escolhe o que a limpeza apaga.
    # A pergunta é só 'Trusted', e não 'não é externo OU é confiável': item de dentro da pasta já
    # nasce confiável no inventário, e fazer a conta aqui deixaria o campo sem efeito - um inventário
    # futuro que esquecesse de preenchê-lo passaria batido. Assim, item sem confiança declarada
    # simplesmente não é apagado, que é o lado seguro do esquecimento.
    $apagavel = {
        param($item)
        [bool]$item.Trusted
    }
    $linha = {
        param($item)
        $onde = if ($item.External) { [string]$item.Path } else { [string]$item.Name }
        $quando = if ($null -eq $item.Date) { 'sem data' } else { ([datetime]$item.Date).ToString('dd/MM/yyyy HH:mm') }
        # Os dois motivos se EMPILHAM, não se escolhem: um arquivo pode estar num disco desligado E
        # vir de um índice em que não se confia, e o usuário precisa dos dois fatos para decidir.
        $porque = & $motivo $item
        if ($item.External -and $item.Missing) { $porque = "em outro disco, que não está disponível agora - $porque" }
        if ($item.External -and -not $item.Trusted) { $porque = "o índice que o nomeia não passou na conferência de confiança - $porque" }
        "'$onde' - $($item.Bytes) byte(s), $quando, $porque"
    }

    if ($DryRun) {
        $secos = @(Get-WinForgeAclBackupInventory -Root $BackupRoot | Where-Object { (& $solto $_) -or $DiscardPending })
        if (-not $secos.Count) { return @('[simulação] nada a apagar: todo arquivo desta pasta pertence a um backup que ninguém desfez.') }
        return @($secos | ForEach-Object {
            if (& $apagavel $_) { "[simulação] apagar $(& $linha $_)" }
            else { "[simulação] NÃO será apagado pelo WinForge, apague à mão: $(& $linha $_)" }
        })
    }
    if ($Probe) {
        $elevado = [bool](Test-WinForgeRepairElevated)
        return @{ Elevated = $elevado; Reason = $(if ($elevado) { '' } else { 'Esta ação precisa do WinForge aberto como administrador. Nada foi apagado e nenhuma pasta foi criada.' }) }
    }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeAclCleanup'

    # Mesma ordem das outras duas: a elevação vem antes de a pasta de backup ser criada ou conferida.
    if (-not (Test-WinForgeRepairElevated)) {
        Write-Error 'Esta ação precisa do WinForge aberto como administrador. Nada foi apagado e nenhuma pasta foi criada.'
        return
    }
    $conf = Confirm-WinForgeAclBackupRoot -Root $BackupRoot
    if (-not $conf.Ok) {
        Write-Error "A pasta de backup de permissões não é confiável ($($conf.Reason)). Nada foi apagado."
        return
    }
    $todos = @(Get-WinForgeAclBackupInventory -Root $conf.Path)
    if (-not $todos.Count) {
        Write-Host "Nada a limpar: a pasta '$($conf.Path)' não tem arquivo nenhum."
        return
    }
    $bytesTodos = [long]0
    foreach ($t in $todos) { $bytesTodos += [long]$t.Bytes }
    Write-Host "Pasta de backup de permissões: '$($conf.Path)' - $($todos.Count) arquivo(s), $([math]::Round($bytesTodos / 1MB, 1)) MB."
    Write-Host ''
    foreach ($t in $todos) {
        $estado = if ($t.Unreadable) { 'ILEGÍVEL' } elseif ($t.Orphan) { 'órfão' } elseif ($t.Consumed) { 'já desfeito' } else { 'EM USO (backup pendente)' }
        if ($t.External) { $estado = "$estado, em outro disco$(if ($t.Missing) { ' que NÃO está disponível agora' } else { '' })" }
        Write-Host ("  [{0}] '{1}' - {2} byte(s), {3} - {4}" -f $t.Kind, $(if ($t.External) { $t.Path } else { $t.Name }), $t.Bytes, $(if ($null -eq $t.Date) { 'sem data' } else { ([datetime]$t.Date).ToString('dd/MM/yyyy HH:mm') }), $estado)
    }
    Write-Host ''
    $alvos = @($todos | Where-Object { (& $solto $_) -or $DiscardPending })
    # Os pendentes, e a saída que faltava. Sem esta porta, um conjunto que ficou pendente por um
    # aviso qualquer trancava a máquina: restauração recusada, limpeza sem alvo, Desfazer repetindo.
    $presos = @($todos | Where-Object { -not (& $solto $_) })
    if ($presos.Count -and -not $DiscardPending) {
        $carimbosPresos = @($presos | Where-Object { [string]$_.Kind -eq 'indice' } | ForEach-Object { ([string]$_.Name) -replace '^acl-index-', '' -replace '\.json$', '' })
        if (-not $carimbosPresos.Count) { $carimbosPresos = @($presos | ForEach-Object { [string]$_.Name }) }
        $bytesPresos = [long]0
        foreach ($p in $presos) { $bytesPresos += [long]$p.Bytes }
        Write-Host "$($presos.Count) arquivo(s) pertencem a backup que ninguém desfez ($($carimbosPresos -join ', ')). O caminho normal é usar o Desfazer; descartar sem desfazer é definitivo."
        if (Request-WinForgeAclCleanupDiscard -Stamps @($carimbosPresos) -Bytes $bytesPresos) {
            Write-Host 'Descarte confirmado por escrito: os conjuntos pendentes vão junto.'
            $alvos = @($todos)
        } else {
            Write-Host 'Descarte NÃO confirmado: os conjuntos pendentes ficam onde estão.'
        }
    }
    if (-not $alvos.Count) {
        Write-Host 'Nada a apagar: todo arquivo desta pasta pertence a um backup que ninguém desfez. Use o botão Desfazer antes, ou peça o descarte e confirme por escrito.'
        return
    }
    Write-Host "$($alvos.Count) arquivo(s) para apagar:"
    $apagados = 0
    $liberados = [long]0
    $falhas = @()
    $ausentes = @()
    $aMao = @()
    foreach ($a in $alvos) {
        # Caminho de fora vindo de índice que não passou na conferência: o WinForge não o apaga, e
        # diz isso com o caminho na frente. Apagar "por garantia" aqui é o caminho de escalonamento.
        if (-not (& $apagavel $a)) {
            $aMao += ("'$($a.Path)'")
            Write-Host ("  NÃO será apagado pelo WinForge, apague à mão: $(& $linha $a)")
            continue
        }
        # Disco desligado não é falha, é instrução: o item continua no índice, o arquivo continua no
        # outro disco, e a limpeza seguinte o alcança. Dizer qual disco ligar é o que resolve.
        if ($a.External -and $a.Missing) {
            $ausentes += ("'$($a.Path)' - $(Get-WinForgeAclDriveHint -Path ([string]$a.Path))")
            Write-Host ("  PULADO, disco indisponível: $(& $linha $a)")
            continue
        }
        # O caminho externo vem de um arquivo de texto, e aqui ele vira argumento de um Remove-Item
        # elevado. Mesmas duas portas do Desfazer, e pelo mesmo motivo: rede primeiro (a porta do
        # absoluto ACEITA '\\servidor\share', e apagar na rede é o mesmo risco com outro nome) e
        # depois o absoluto, porque 'C:acl.txt' e '\acl.txt' são "rooted" e resolvem contra o
        # diretório do PROCESSO.
        if ($a.External -and (Test-WinForgeAclNetworkPath -Path ([string]$a.Path))) {
            $falhas += ("'$($a.Path)': o índice guardou um caminho de rede, e a limpeza não apaga na rede")
            continue
        }
        if ($a.External -and -not (Test-WinForgeAclAbsolutePath -Path ([string]$a.Path))) {
            $falhas += ("'$($a.Path)': o índice guardou um caminho que não é absoluto")
            continue
        }
        Write-Host ("  apagando $(& $linha $a)")
        try {
            Remove-Item -LiteralPath ([string]$a.Path) -Force -ErrorAction Stop
            $apagados++
            $liberados += [long]$a.Bytes
        } catch {
            $falhas += ("'$($a.Name)': $($_.Exception.Message)")
        }
    }
    Write-Host ''
    Write-Host "Limpeza concluída: $apagados de $($alvos.Count) arquivo(s) apagados, $([math]::Round($liberados / 1MB, 1)) MB liberados."
    # Sem promessa de segunda passada, e isso é medido no código ao lado, não no otimismo: o ÍNDICE
    # que nomeia o arquivo de outro disco sai NESTA mesma limpeza, no laço acima, e é só através
    # dele que o inventário enxerga aquele caminho. Rodar a limpeza de novo com o disco ligado não
    # acharia mais nada. Guardar o índice para uma segunda passada reabriria o beco sem saída que a
    # rodada anterior fechou, então o que sobra - e o que é honesto - é mandar apagar à mão.
    if ($ausentes.Count) { Write-Warning ("Backup de conteúdo em outro disco, que não estava disponível agora: {0}. Estes arquivos continuam ocupando espaço lá, e o índice que o nomeava saiu junto nesta limpeza - uma segunda passada não vai mais encontrá-los. Apague-os à mão, no disco em que eles foram guardados." -f ($ausentes -join '; ')) }
    if ($aMao.Count) { Write-Warning ("Estes arquivos estão fora da pasta protegida e o índice que os nomeia não passou na conferência de confiança, então o WinForge NÃO os apaga: {0}. Confira o caminho e apague à mão se ele for mesmo seu." -f ($aMao -join '; ')) }
    if ($falhas.Count) { Write-Error ("Não foi possível apagar: {0}." -f ($falhas -join '; ')) }
    $sobrando = @($todos | Where-Object { $_.Path -notin @($alvos | ForEach-Object { [string]$_.Path }) }).Count
    if ($sobrando) { Write-Host "$sobrando arquivo(s) ficaram: eles pertencem a backup que ninguém desfez, e é deles que o botão Desfazer depende. Para descartá-los, rode a limpeza de novo e confirme o descarte por escrito." }
}

#endregion
