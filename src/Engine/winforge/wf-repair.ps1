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
    .OUTPUTS
        Hashtable com Title, Command, Requires, Native, Kind e (fora de 'read') Confirm.
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
                Title    = 'Verificar disco do sistema agora (chkdsk /scan)'
                Command  = 'Invoke-WinForgeChkdskScan'
                Requires = (Get-WinForgeSystemExe -Name 'chkdsk.exe')
                Native   = $false
                Kind     = 'read'
            }
        }
        'WmiRepair' {
            return @{
                Title    = 'Repositório WMI: verificar e recuperar'
                Command  = 'Invoke-WinForgeWmiRepair'
                Requires = (Get-WinForgeSystemExe -Name 'wbem\winmgmt.exe')
                Native   = $false
                Kind     = 'repair'
                Confirm  = 'Verificar o repositório WMI e, se ele estiver inconsistente, tentar recuperá-lo. Programas que consultam o WMI podem falhar durante a recuperação. Exige o WinForge aberto como administrador: sem elevação a verificação responde "acesso negado" e nada é recuperado.'
            }
        }
        'StoreReregister' {
            return @{
                Title    = 'Microsoft Store e App Installer: registrar de novo'
                Command  = 'Invoke-WinForgeStoreReregister'
                Requires = 'Get-AppxPackage'
                Native   = $false
                Kind     = 'repair'
                Confirm  = 'Registrar de novo a Microsoft Store, o App Installer (winget) e o Store Purchase App PARA O USUÁRIO ATUAL, a partir dos arquivos que já estão no disco. Os aplicativos fecham durante o registro. Outros usuários desta máquina não são afetados: cada um precisa rodar isto no próprio logon.'
            }
        }
        'ChkdskSchedule' {
            return @{
                Title    = 'Agendar chkdsk /f na próxima reinicialização'
                Command  = 'Invoke-WinForgeChkdskSchedule'
                Requires = (Get-WinForgeSystemExe -Name 'fsutil.exe')
                Native   = $false
                Kind     = 'repair'
                Confirm  = 'Marcar o disco do sistema como "sujo" (fsutil dirty set): na próxima reinicialização o Windows roda o chkdsk com reparo antes de carregar, e isso pode demorar bastante. NÃO TEM DESFAZER: quem limpa a marca é o próprio chkdsk, e só quando concluir que o volume está íntegro - até lá a verificação se repete a cada reinicialização.'
            }
        }
        'MemoryDiag' {
            return @{
                Title    = 'Diagnóstico de memória na próxima reinicialização'
                Command  = 'Invoke-WinForgeMemoryDiagSchedule'
                Requires = (Get-WinForgeSystemExe -Name 'bcdedit.exe')
                Native   = $false
                Kind     = 'repair'
                Confirm  = 'Colocar o Diagnóstico de Memória do Windows na sequência de inicialização: a próxima reinicialização vai testar a memória antes de carregar o Windows.'
            }
        }
        'DotNet35Enable' {
            return @{
                Title    = '.NET Framework 3.5: habilitar (DISM)'
                Command  = 'Enable-WinForgeDotNet35'
                Requires = $null
                Native   = $false
                Kind     = 'install'
                Confirm  = 'Habilitar o recurso NetFx3 (.NET Framework 3.5) pelo DISM. Os arquivos vêm do Windows Update: precisa de internet e pode demorar.'
            }
        }
        'VcRedist' {
            # Sem 'Requires': quem procura o winget é Get-WinForgeWingetPath, que também olha a pasta
            # do App Installer quando ele não está no PATH (é o caso logo depois de um logon novo).
            # 'Requires = winget.exe' recusaria o botão justamente nessa máquina, que é onde ele mais
            # serve. Winget ausente vira texto na janela, com o que fazer a respeito.
            return @{
                Title    = 'Visual C++ 2005–2022 (x86/x64) via winget'
                Command  = 'Install-WinForgeVcRedist'
                Requires = $null
                Native   = $false
                Kind     = 'install'
                Confirm  = 'Instalar (ou atualizar) os pacotes redistribuíveis do Visual C++ de 2005 a 2022, x86 e x64, pelo winget. São vários downloads e pode demorar.'
            }
        }
        'PowerShell7' {
            return @{
                Title    = 'PowerShell 7 via winget'
                Command  = 'Install-WinForgePowerShell7'
                Requires = $null
                Native   = $false
                Kind     = 'install'
                Confirm  = 'Instalar o PowerShell 7 (Microsoft.PowerShell) pelo winget. O Windows PowerShell 5.1 continua instalado e é ele que o WinForge usa.'
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
                Title     = 'Rede - Redefinir'
                ConfigKey = 'WPFFixesNetwork'
                Requires  = (Get-WinForgeSystemExe -Name 'netsh.exe')
                Kind      = 'repair'
                Stream    = $true
                Steps     = @(
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'netsh.exe'); Arguments = @('winsock', 'reset') }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'netsh.exe'); Arguments = @('int', 'ip', 'reset') }
                )
                Final     = 'Configuração de rede redefinida. Reinicie o computador.'
                Confirm   = 'Redefine a pilha de rede com "netsh winsock reset" e "netsh int ip reset": as configurações de TCP/IP e do Winsock voltam ao padrão do Windows. É preciso reiniciar o computador para concluir.'
            }
        }
        'NtpPool' {
            # Quatro passos, e os dois de serviço são função porque Start-Service/Restart-Service são
            # cmdlets: 'net start w32time' faria a mesma coisa chamando um executável a mais e
            # perdendo a mensagem de erro em português do próprio PowerShell.
            return @{
                Title     = 'Servidor NTP - Ativar'
                ConfigKey = 'WPFFixesNTPPool'
                Requires  = (Get-WinForgeSystemExe -Name 'w32tm.exe')
                Kind      = 'repair'
                Stream    = $true
                Steps     = @(
                    @{ Function = 'Start-WinForgeTimeService' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'w32tm.exe'); Arguments = @('/config', '/update', '/manualpeerlist:pool.ntp.org,0x8', '/syncfromflags:MANUAL') }
                    @{ Function = 'Restart-WinForgeTimeService' }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'w32tm.exe'); Arguments = @('/resync') }
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
            # 'Unicode' no sfc: quando a saída dele é redirecionada, ele passa a escrever UTF-16LE.
            # Lida como OEM, cada caractere vira uma letra seguida de um byte zero.
            return @{
                Title     = 'Verificação de corrupção do sistema - Executar'
                ConfigKey = 'WPFPanelDISM'
                Requires  = (Get-WinForgeSystemExe -Name 'sfc.exe')
                Kind      = 'repair'
                Stream    = $true
                Steps     = @(
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'chkdsk.exe'); Arguments = @($(if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { 'C:' } else { $env:SystemDrive }), '/scan', '/perf') }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'sfc.exe'); Arguments = @('/scannow'); Unicode = $true }
                    @{ FilePath = (Get-WinForgeSystemExe -Name 'Dism.exe'); Arguments = @('/Online', '/Cleanup-Image', '/RestoreHealth') }
                )
                Final     = 'Verificação de corrupção concluída.'
                Confirm   = 'Roda em sequência o chkdsk (verificação do disco do sistema, só leitura), o sfc /scannow (reparo dos arquivos protegidos do Windows) e o DISM /RestoreHealth (reparo da imagem do Windows, que baixa arquivos pela internet). Pode levar de vários minutos a mais de uma hora.'
            }
        }
        'WindowsUpdateReset' {
            return @{
                Title     = 'Windows Update - Redefinir'
                ConfigKey = 'WPFFixesUpdate'
                Requires  = $null
                Kind      = 'repair'
                Stream    = $true
                Steps     = @(
                    @{ Function = 'Invoke-WPFFixesUpdate' }
                )
                Final     = 'Windows Update redefinido. Reinicie o computador.'
                Confirm   = 'Redefine o Windows Update: para os serviços, apaga a fila do BITS e o log, renomeia a pasta de downloads, registra de novo as DLLs, remove as configurações de WSUS, redefine o Winsock e religa os serviços. É preciso reiniciar o computador depois.'
            }
        }
        'WingetReinstall' {
            return @{
                Title     = 'WinGet - Reinstalar'
                ConfigKey = 'WPFFixesWinget'
                Requires  = $null
                Kind      = 'repair'
                Stream    = $true
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
                Title    = 'Permissões do disco C: - Restaurar padrões'
                Requires = (Get-WinForgeSystemExe -Name 'icacls.exe')
                Kind     = 'repair'
                Stream   = $true
                Steps    = @(@{ Function = 'Invoke-WinForgeAclRestore' })
                Final    = 'Reinicie o computador: serviços e programas já abertos continuam com as permissões antigas em cache até o próximo logon.'
                Confirm  = 'Devolve as permissões do disco do Windows ao padrão de fábrica, em fases: verificação do disco, backup das listas atuais, raiz, secedit e pasta de usuário. Leva minutos e pede reinicialização no fim.'
            }
        }
        'AclUndo' {
            return @{
                Title    = 'Permissões do disco C: - Desfazer (restaurar backup)'
                Requires = (Get-WinForgeSystemExe -Name 'icacls.exe')
                Kind     = 'repair'
                Stream   = $true
                Steps    = @(@{ Function = 'Invoke-WinForgeAclUndo' })
                Final    = 'Reinicie o computador para que os programas já abertos passem a enxergar as permissões que voltaram.'
                Confirm  = 'Reaplica as listas de permissão guardadas na última restauração de padrões, arquivo por arquivo, a partir da pasta protegida do WinForge. Sem backup gravado, não faz nada.'
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
        $lista = Invoke-WinForgeNativeCommand -FilePath $winget -Utf8 -Arguments @('list', '--id', $id, '-e', '--disable-interactivity', '--accept-source-agreements')
        if (Test-WinForgeWingetInstalled -Id $id -ExitCode ([int]$lista.ExitCode) -Text ([string]$lista.Text)) {
            $linhas.Add("$id`: já instalado (nada a fazer)")
            $instalados++
            continue
        }

        $r = Invoke-WinForgeNativeCommand -FilePath $winget -Utf8 -Arguments @(
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

    $r = Invoke-WinForgeNativeCommand -FilePath $winget -Utf8 -Arguments @(
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
    #
    # $sync.CommandRunning é a trava desta máquina de comandos (um chkdsk /scan leva minutos).
    # $sync.ProcessRunning é a do BASE - o botão "sfc + DISM" e os de instalação. Ela só barra o que
    # altera o sistema: duas sessões de manutenção ao mesmo tempo fazem a segunda falhar com "outra
    # operação em andamento", e ler o estado da máquina enquanto o base trabalha não atrapalha nada.
    $ocupado = $null
    if ($sync.CommandRunning) {
        $ocupado = 'Já existe um comando em andamento. Espere ele terminar.'
    } elseif ($kind -ne 'read' -and $sync.ProcessRunning) {
        $ocupado = 'O WinForge já está com uma instalação ou manutenção em andamento. Espere ela terminar antes de reparar ou instalar componente.'
    }
    if ($null -ne $ocupado) {
        Write-WinForgeLog -Component "Repair" -Message "$Name não despachado: $ocupado"
        if ($NoUI) { return @{ Dispatched = $false; Reason = 'ocupado'; Kind = $kind } }
        [System.Windows.MessageBox]::Show($ocupado, "WinForge", "OK", "Warning") | Out-Null
        return
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
# 3. O icacls nunca é apontado para dentro de Windows nem de Program Files. Quem repõe as DACLs
#    dessas duas (e as do registro) é o secedit com o defltbase.inf, que é o procedimento
#    documentado pela Microsoft. '/reset /T' na raiz e 'takeown /R' também não existem aqui: os
#    dois descem a árvore inteira apagando o que o Windows sabe e o WinForge não.

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
        Sistema          = 'S-1-5-18'
        Administradores  = 'S-1-5-32-544'
        Usuarios         = 'S-1-5-32-545'
        Autenticados     = 'S-1-5-11'
        Todos            = 'S-1-1-0'
        TrustedInstaller = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
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
    .OUTPUTS
        Vetor de hashtables com Path, Nome, Donos e Aces.
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
        Path  = $raiz
        Nome  = "Raiz do disco do sistema ($raiz)"
        Donos = @($sid.Sistema, $sid.Administradores, $sid.TrustedInstaller)
        Aces  = @(
            @{ Sid = $sid.Sistema;         Rights = $F;  Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F;  Rotulo = 'Administradores com controle total' }
            @{ Sid = $sid.Usuarios;        Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
            @{ Sid = $sid.Autenticados;    Rights = $M;  Rotulo = 'Usuários Autenticados podendo modificar o que criarem' }
        )
    }
    foreach ($nome in @('Windows', 'Program Files', 'Program Files (x86)')) {
        $itens += @{
            Path  = (Join-Path $raiz $nome)
            Nome  = $nome
            Donos = @($sid.TrustedInstaller)
            Aces  = @(
                @{ Sid = $sid.Sistema;          Rights = $M;  Rotulo = 'SYSTEM podendo modificar' }
                @{ Sid = $sid.Administradores;  Rights = $M;  Rotulo = 'Administradores podendo modificar' }
                @{ Sid = $sid.Usuarios;         Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
                @{ Sid = $sid.TrustedInstaller; Rights = $F;  Rotulo = 'TrustedInstaller com controle total' }
            )
        }
    }
    $itens += @{
        Path  = (Join-Path $raiz 'ProgramData')
        Nome  = 'ProgramData'
        Donos = @($sid.Sistema, $sid.Administradores)
        Aces  = @(
            @{ Sid = $sid.Sistema;         Rights = $F;  Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F;  Rotulo = 'Administradores com controle total' }
            @{ Sid = $sid.Usuarios;        Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
        )
    }
    $itens += @{
        Path  = (Join-Path $raiz 'Users')
        Nome  = 'Users'
        Donos = @($sid.Sistema, $sid.Administradores)
        Aces  = @(
            @{ Sid = $sid.Sistema;         Rights = $F;  Rotulo = 'SYSTEM com controle total' }
            @{ Sid = $sid.Administradores; Rights = $F;  Rotulo = 'Administradores com controle total' }
            @{ Sid = $sid.Usuarios;        Rights = $RX; Rotulo = 'Usuários podendo ler e executar' }
            @{ Sid = $sid.Todos;           Rights = $RX; Rotulo = 'Todos podendo ler e executar' }
        )
    }
    $itens += @{
        Path  = (Join-Path $raiz 'Users\Public')
        Nome  = 'Users\Public'
        Donos = @($sid.Sistema, $sid.Administradores)
        Aces  = @(
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
            Path  = $perfil
            Nome  = "Pasta do usuário atual ($perfil)"
            Donos = @($sid.Sistema, $sid.Administradores, $meu)
            Aces  = $aces
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

        As ACEs de um mesmo SID são somadas antes de comparar. Elas costumam vir em pares - uma
        efetiva na própria pasta e uma herdável de somente herança para o que nascer abaixo - e cada
        uma sozinha é um pedaço do direito. Só as de PERMISSÃO entram: uma ACE de negação é assunto
        de quem a criou, e tratá-la aqui faria a verificação opinar sobre configuração legítima.
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
        if ([string]$ace.AccessControlType -ne 'Allow') { continue }
        $s = $ace.IdentityReference
        try {
            if ($s -isnot [System.Security.Principal.SecurityIdentifier]) { $s = $s.Translate([System.Security.Principal.SecurityIdentifier]) }
        } catch { continue }
        $chave = [string]$s.Value
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
            $itens += @{ Path = $esp.Path; Nome = $esp.Nome; Differences = @(); Missing = $true }
            continue
        }
        $lista = $null
        try { $lista = Get-Acl -LiteralPath $esp.Path -ErrorAction Stop } catch { $lista = $null }
        if ($null -eq $lista) {
            $linhas.Add('  A lista de permissões não pôde ser lida.')
            $total++
            $itens += @{ Path = $esp.Path; Nome = $esp.Nome; Differences = @('a lista de permissões não pôde ser lida'); Missing = $false }
            continue
        }

        $dono = $null
        try { $dono = $lista.GetOwner([System.Security.Principal.SecurityIdentifier]) } catch { $dono = $null }
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
        $itens += @{ Path = $esp.Path; Nome = $esp.Nome; Differences = @($dif); Missing = $false }
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
        2. Backup das listas atuais, uma por pasta: a raiz, cada pasta de primeiro nível (sem
           recursão) e a pasta do usuário (com /T). É o que o botão Desfazer consome.
        3. A raiz. '/inheritance:r' + um '/grant:r' com as cinco ACEs padrão, por SID.
        4. secedit com o defltbase.inf. É ELE quem repõe as DACLs de Windows, Program Files,
           ProgramData, Users e do registro - o icacls não é apontado para dentro dessas pastas.
        5. A pasta do usuário: as três ACEs padrão nela e '/reset /T' ABAIXO dela, que devolve a
           herança ao conteúdo. '/reset /T' aqui é seguro porque o alvo é uma pasta de perfil; na
           raiz ele apagaria a DACL de tudo que existe no disco.
        6. takeown /F <raiz> /A, SEM recursão, e só quando a fase 3 responder "acesso negado". O
           passo vem marcado com 'Conditional' e quem decide rodá-lo é Invoke-WinForgeAclRestore.

        Cada passo de backup carrega 'Backup' (o arquivo que vai ser gravado) e 'Target' (a pasta a
        partir da qual o /restore tem de rodar). O alvo não é adivinhado depois: o icacls grava
        NOMES RELATIVOS à pasta em que foi invocado, então o Desfazer precisa da mesma pasta, e ela
        é anotada aqui, no único lugar em que a regra existe.
    .OUTPUTS
        Vetor de hashtables com Phase, Title, FilePath, Arguments e, no backup, Path/Backup/Target.
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
    $secedit = Get-WinForgeSystemExe -Name 'secedit.exe'
    $takeown = Get-WinForgeSystemExe -Name 'takeown.exe'
    $chkdsk = Get-WinForgeSystemExe -Name 'chkdsk.exe'
    $windir = ''
    try { $windir = [string][System.IO.Path]::GetDirectoryName([string][Environment]::SystemDirectory) } catch { $windir = '' }
    if ([string]::IsNullOrWhiteSpace($windir)) { $windir = Join-Path $raiz 'Windows' }
    if ([string]::IsNullOrWhiteSpace($Stamp)) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $BackupRoot = Get-WinForgeAclBackupRoot }

    $plano = @()
    $plano += @{
        Phase     = 1
        Title     = "Verificação do disco $unidade (chkdsk /scan, só leitura)"
        FilePath  = $chkdsk
        Arguments = @($unidade, '/scan')
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
    $alvos += @{ Path = $raiz; Slug = 'raiz'; Recursive = $false }
    foreach ($p in $primeiroNivel) {
        $folha = [string](Split-Path -Leaf $p)
        $alvos += @{ Path = $p; Slug = ([regex]::Replace($folha, '[^A-Za-z0-9._-]', '_')); Recursive = $false }
    }
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $alvos += @{ Path = $Profile; Slug = ('perfil-' + [regex]::Replace([string](Split-Path -Leaf $Profile), '[^A-Za-z0-9._-]', '_')); Recursive = $true }
    }

    foreach ($alvo in $alvos) {
        $arquivo = Join-Path $BackupRoot ("acl-{0}-{1}.txt" -f $alvo.Slug, $Stamp)
        # O destino do /restore: a raiz salva a si mesma (não há pasta acima dela), e todo o resto é
        # restaurado da pasta em que o icacls gravou os nomes relativos, que é a pasta acima.
        $destino = if ([string]$alvo.Path -eq $raiz) { $raiz } else { [string](Split-Path -Parent ([string]$alvo.Path)) }
        $argumentos = @([string]$alvo.Path, '/save', $arquivo, '/C')
        if ($alvo.Recursive) { $argumentos += '/T' }
        $plano += @{
            Phase     = 2
            Title     = "Backup das permissões de '$($alvo.Path)'"
            FilePath  = $icacls
            Arguments = $argumentos
            Path      = [string]$alvo.Path
            Backup    = $arquivo
            Target    = $destino
        }
    }

    $plano += @{
        Phase     = 3
        Title     = "Permissões padrão da raiz '$raiz'"
        FilePath  = $icacls
        Arguments = @(
            $raiz, '/inheritance:r', '/grant:r',
            "*$($sid.Administradores):(OI)(CI)F",
            "*$($sid.Sistema):(OI)(CI)F",
            "*$($sid.Usuarios):(OI)(CI)RX",
            "*$($sid.Autenticados):(OI)(CI)(IO)M",
            "*$($sid.Autenticados):AD"
        )
    }
    $plano += @{
        Phase     = 4
        Title     = 'DACLs padrão do Windows e do registro (secedit com o defltbase.inf)'
        FilePath  = $secedit
        Arguments = @('/configure', '/cfg', (Join-Path $windir 'inf\defltbase.inf'), '/db', (Join-Path $BackupRoot 'defltbase.sdb'), '/areas', 'FILESTORE', 'REGKEYS', '/verbose')
    }
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $grant = @([string]$Profile, '/inheritance:r', '/grant:r')
        if (-not [string]::IsNullOrWhiteSpace($UserSid)) { $grant += "*$($UserSid):(OI)(CI)F" }
        $grant += "*$($sid.Sistema):(OI)(CI)F"
        $grant += "*$($sid.Administradores):(OI)(CI)F"
        $plano += @{ Phase = 5; Title = "Permissões padrão da pasta '$Profile'"; FilePath = $icacls; Arguments = $grant }
        $plano += @{ Phase = 5; Title = "Herança do conteúdo de '$Profile'"; FilePath = $icacls; Arguments = @([string]$Profile, '/reset', '/T', '/C', '/Q') }
    }
    $plano += @{
        Phase       = 6
        Title       = "Assumir a posse da raiz '$raiz' (só se a fase 3 responder acesso negado)"
        FilePath    = $takeown
        Arguments   = @('/F', $raiz, '/A')
        Conditional = $true
    }
    return @($plano)
}

function Invoke-WinForgeAclRestore {
    <#
    .SYNOPSIS
        Devolve as permissões do disco do sistema ao padrão do Windows, guardando antes as atuais.
    .DESCRIPTION
        Conduz as fases de Get-WinForgeAclRestorePlan com as duas decisões que uma lista fixa de
        passos não sabe tomar:

        - Depois da fase 1, o código do chkdsk. Diferente de zero significa erro no volume, e aí a
          função PARA sem alterar permissão nenhuma e manda agendar o chkdsk /f.
        - Depois da fase 3, o código do icacls. 5 é "acesso negado": a raiz pertence a alguém que
          nem o administrador alcança, e é o único caso em que o takeown da fase 6 roda - uma vez,
          só na raiz, sem recursão, seguido de UMA segunda tentativa da fase 3.

        A fase 2 é bloqueante das duas pontas: se a pasta protegida não passar na conferência, nada
        é alterado; se nenhum backup chegar a ser gravado, também não. Restaurar sem desfazer é o
        tipo de ajuda que transforma um problema em dois.

        Cada arquivo gravado é endurecido (Protect-WinForgeSnapshotFile: dono Administradores, DACL
        fechada) e anotado num índice, que é o que o Desfazer lê. O índice guarda a pasta de onde
        cada /restore tem de rodar, porque o icacls grava nomes RELATIVOS à pasta em que foi
        invocado - adivinhar isso depois é o jeito de aplicar a DACL da pasta errada.
    .PARAMETER DryRun
        Lista as fases, prefixadas com '[simulação] ', e para por aí: nada roda, nenhuma pasta é
        criada, nenhum arquivo é gravado.
    .PARAMETER BackupRoot
        Pasta de backup alternativa. Existe para o teste; a conferência dela é a mesma da pasta
        padrão, sem afrouxamento nenhum.
    .OUTPUTS
        Com -DryRun, as linhas do plano. Sem ele, escreve o andamento (é um passo de fluxo ao vivo).
    #>
    param(
        [switch]$DryRun,
        [string]$BackupRoot
    )

    $perfil = ''
    try { $perfil = [string][Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) } catch { $perfil = '' }
    $meuSid = ''
    try { $meuSid = [string][System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $meuSid = '' }
    $raizBackup = Get-WinForgeAclBackupRoot $BackupRoot
    $plano = @(Get-WinForgeAclRestorePlan -Profile $perfil -UserSid $meuSid -BackupRoot $raizBackup)

    if ($DryRun) {
        return @($plano | ForEach-Object {
            ("[simulação] Fase {0}: {1} {2}" -f $_.Phase, $_.FilePath, (@($_.Arguments) -join ' ')).TrimEnd()
        })
    }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeAclRestore'

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
    $r = Invoke-WinForgeNativeCommand -FilePath ([string]$fase1.FilePath) -Arguments @($fase1.Arguments)
    Write-Host ([string]$r.Text)
    if ([int]$r.ExitCode -ne 0) {
        Write-Error "O chkdsk terminou com código $($r.ExitCode): o volume tem erro de sistema de arquivos. PARADO antes de alterar qualquer permissão - use o botão 'Agendar chkdsk /f na próxima reinicialização', reinicie e volte aqui."
        return
    }

    # ---- Fase 2: o desfazer, antes de qualquer alteração.
    $indice = New-Object System.Collections.Generic.List[string]
    $gravados = 0
    foreach ($passo in @($plano | Where-Object { [int]$_.Phase -eq 2 })) {
        Write-Host ''
        Write-Host "Fase 2 de 6 - $($passo.Title)"
        $r = Invoke-WinForgeNativeCommand -FilePath ([string]$passo.FilePath) -Arguments @($passo.Arguments)
        Write-Host ([string]$r.Text)
        if (-not (Test-Path -LiteralPath ([string]$passo.Backup) -PathType Leaf)) {
            Write-Warning "Nada foi gravado em '$($passo.Backup)'; esta pasta fica de fora do Desfazer."
            continue
        }
        $prot = Protect-WinForgeSnapshotFile -Path ([string]$passo.Backup)
        if (-not $prot.Hardened) {
            Remove-Item -LiteralPath ([string]$passo.Backup) -Force -ErrorAction SilentlyContinue
            Write-Warning "O backup de '$($passo.Path)' não pôde ser protegido ($($prot.Reason)) e foi apagado."
            continue
        }
        $indice.Add(("{0}|{1}" -f [string](Split-Path -Leaf ([string]$passo.Backup)), [string]$passo.Target))
        $gravados++
    }
    if ($gravados -eq 0) {
        Write-Error 'Nenhum backup de permissões pôde ser gravado. Nada foi alterado.'
        return
    }
    $carimbo = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $arquivoIndice = Join-Path $conf.Path ("acl-index-{0}.txt" -f $carimbo)
    Set-Content -LiteralPath $arquivoIndice -Value @($indice) -Encoding UTF8 -ErrorAction Stop
    $protIndice = Protect-WinForgeSnapshotFile -Path $arquivoIndice
    if (-not $protIndice.Hardened) {
        Remove-Item -LiteralPath $arquivoIndice -Force -ErrorAction SilentlyContinue
        Write-Error "O índice do backup não pôde ser protegido ($($protIndice.Reason)). Nada foi alterado - sem o índice o Desfazer não sabe de que pasta restaurar cada arquivo."
        return
    }
    Write-Host ''
    Write-Host "$gravados pasta(s) guardadas no conjunto $carimbo. O botão Desfazer usa exatamente este conjunto."

    # ---- Fase 3 (e, só em acesso negado, a 6 seguida de uma segunda tentativa da 3).
    $fase3 = @($plano | Where-Object { [int]$_.Phase -eq 3 })[0]
    Write-Host ''
    Write-Host "Fase 3 de 6 - $($fase3.Title)"
    $r = Invoke-WinForgeNativeCommand -FilePath ([string]$fase3.FilePath) -Arguments @($fase3.Arguments)
    Write-Host ([string]$r.Text)
    if ([int]$r.ExitCode -eq 5) {
        $fase6 = @($plano | Where-Object { [int]$_.Phase -eq 6 })[0]
        Write-Host ''
        Write-Host "Acesso negado na raiz. Fase 6 de 6 - $($fase6.Title)"
        $rt = Invoke-WinForgeNativeCommand -FilePath ([string]$fase6.FilePath) -Arguments @($fase6.Arguments)
        Write-Host ([string]$rt.Text)
        Write-Host 'Segunda e última tentativa das permissões da raiz.'
        $r = Invoke-WinForgeNativeCommand -FilePath ([string]$fase3.FilePath) -Arguments @($fase3.Arguments)
        Write-Host ([string]$r.Text)
    }
    if ([int]$r.ExitCode -ne 0) {
        # Segue assim mesmo: o secedit da fase 4 conserta Windows, Program Files, ProgramData e
        # Users independentemente da raiz, e parar aqui deixaria a máquina no meio do caminho.
        Write-Error "As permissões da raiz não puderam ser aplicadas (código $($r.ExitCode)). As fases seguintes continuam."
    }

    # ---- Fase 4: quem cuida de Windows e Program Files.
    $fase4 = @($plano | Where-Object { [int]$_.Phase -eq 4 })[0]
    Write-Host ''
    Write-Host "Fase 4 de 6 - $($fase4.Title). É a fase mais demorada."
    $r = Invoke-WinForgeNativeCommand -FilePath ([string]$fase4.FilePath) -Arguments @($fase4.Arguments)
    Write-Host ([string]$r.Text)
    if ([int]$r.ExitCode -ne 0) { Write-Error "O secedit terminou com código $($r.ExitCode); veja o %windir%\security\logs\scesrv.log." }

    # ---- Fase 5: a pasta do usuário.
    foreach ($passo in @($plano | Where-Object { [int]$_.Phase -eq 5 })) {
        Write-Host ''
        Write-Host "Fase 5 de 6 - $($passo.Title)"
        $r = Invoke-WinForgeNativeCommand -FilePath ([string]$passo.FilePath) -Arguments @($passo.Arguments)
        Write-Host ([string]$r.Text)
        if ([int]$r.ExitCode -ne 0) { Write-Error "Esta etapa terminou com código $($r.ExitCode)." }
    }

    Write-Host ''
    Write-Host 'Restauração concluída. Reinicie o computador antes de julgar o resultado: serviços e programas já abertos seguem com as permissões antigas em cache.'
    Write-Host 'Depois de reiniciar, use "Permissões do disco C: - Verificar" para conferir, e "Desfazer (restaurar backup)" se algo tiver ficado pior.'
}

function Get-WinForgeAclBackupSet {
    <#
    .SYNOPSIS
        O conjunto de backup de permissões mais recente: o índice, o carimbo de tempo e os arquivos.
    .DESCRIPTION
        Só lê. O mais recente sai da ordenação por NOME, e não pela data do sistema de arquivos, que
        uma cópia de pasta reescreve: o nome carrega '<aaaaMMdd-HHmmss>', campo de largura fixa.

        Cada linha do índice é '<nome do arquivo>|<pasta de onde restaurar>'. Linha em branco,
        comentário e linha sem a barra são ignorados; o que sobra ainda passa, um a um, por
        Test-WinForgeAclBackupFile antes de virar argumento de coisa alguma.
    .OUTPUTS
        @{ Stamp; Index; Items = @(@{ File; Target }); Reason }.
    #>
    param([string]$Root)

    $dir = Get-WinForgeAclBackupRoot $Root
    if (-not (Test-Path -LiteralPath $dir)) {
        return @{ Stamp = ''; Index = ''; Items = @(); Reason = "a pasta '$dir' não existe - nenhuma restauração foi feita nesta máquina" }
    }
    $indices = @(Get-ChildItem -LiteralPath $dir -Filter 'acl-index-*.txt' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if (-not $indices.Count) {
        return @{ Stamp = ''; Index = ''; Items = @(); Reason = "nenhum índice de backup em '$dir'" }
    }
    $novo = $indices[$indices.Count - 1]
    $carimbo = [string]([System.IO.Path]::GetFileNameWithoutExtension($novo.Name)) -replace '^acl-index-', ''
    $itens = @()
    foreach ($linha in @(Get-Content -LiteralPath $novo.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $t = ([string]$linha).Trim()
        if ([string]::IsNullOrWhiteSpace($t) -or $t.StartsWith('#')) { continue }
        $partes = $t -split '\|', 2
        if ($partes.Count -ne 2) { continue }
        $itens += @{ File = (Join-Path $dir ([string]$partes[0]).Trim()); Target = ([string]$partes[1]).Trim() }
    }
    return @{ Stamp = $carimbo; Index = [string]$novo.FullName; Items = @($itens); Reason = '' }
}

function Invoke-WinForgeAclUndo {
    <#
    .SYNOPSIS
        Reaplica as permissões guardadas pela última restauração de padrões.
    .DESCRIPTION
        Um icacls /restore por arquivo do conjunto mais recente, rodado a partir da pasta anotada no
        índice - o icacls grava nomes RELATIVOS à pasta em que foi invocado, e restaurar da pasta
        errada aplicaria a DACL de uma coisa em outra.

        Duas conferências antes de qualquer argumento ser montado: a PASTA
        (Confirm-WinForgeAclBackupRoot, regras da pasta padrão) e cada ARQUIVO
        (Test-WinForgeAclBackupFile: dentro da pasta, direto nela, dono e DACL de backup). Arquivo
        recusado é pulado com o motivo na tela; ele não derruba os outros, porque um backup adulterado
        no meio do conjunto não é razão para deixar o disco pela metade.

        Sem conjunto nenhum a função apenas DIZ isso. É o caso de quem clica no Desfazer sem nunca
        ter restaurado nada, e ele não é erro.
    .PARAMETER DryRun
        Lista os /restore que seriam feitos, prefixados com '[simulação] ', sem rodar nada e sem
        criar a pasta de backup.
    .PARAMETER BackupRoot
        Pasta de backup alternativa, para o teste. Vale a conferência da pasta padrão.
    .OUTPUTS
        Com -DryRun, as linhas do plano. Sem ele, escreve o andamento (é um passo de fluxo ao vivo).
    #>
    param(
        [switch]$DryRun,
        [string]$BackupRoot
    )

    $icacls = Get-WinForgeSystemExe -Name 'icacls.exe'
    $conjunto = Get-WinForgeAclBackupSet -Root $BackupRoot

    if ($DryRun) {
        if (-not @($conjunto.Items).Count) { return @("[simulação] nada a desfazer: $($conjunto.Reason)") }
        return @($conjunto.Items | ForEach-Object {
            "[simulação] $icacls $($_.Target) /restore $($_.File) /C"
        })
    }
    Assert-WinForgeNotSelfTest -Name 'Invoke-WinForgeAclUndo'

    $conf = Confirm-WinForgeAclBackupRoot -Root $BackupRoot
    if (-not $conf.Ok) {
        Write-Error "A pasta de backup de permissões não é confiável ($($conf.Reason)). Nada foi restaurado."
        return
    }
    $conjunto = Get-WinForgeAclBackupSet -Root $BackupRoot
    if (-not @($conjunto.Items).Count) {
        Write-Host "Nada a desfazer: $($conjunto.Reason)."
        return
    }
    $julgIndice = Test-WinForgeAclBackupFile -Path ([string]$conjunto.Index) -Root ([string]$conf.Path)
    if (-not $julgIndice.Trusted) {
        Write-Error "O índice do backup foi recusado ($($julgIndice.Reason)). Nada foi restaurado."
        return
    }
    Write-Host "Conjunto de backup $($conjunto.Stamp): $(@($conjunto.Items).Count) pasta(s) para restaurar."

    $aplicados = 0
    $recusados = 0
    foreach ($item in @($conjunto.Items)) {
        $julg = Test-WinForgeAclBackupFile -Path ([string]$item.File) -Root ([string]$conf.Path)
        if (-not $julg.Trusted) {
            Write-Error "Backup recusado ('$($item.File)'): $($julg.Reason)."
            $recusados++
            continue
        }
        if (-not (Test-Path -LiteralPath ([string]$item.Target) -PathType Container)) {
            Write-Warning "A pasta '$($item.Target)' não existe mais; '$(Split-Path -Leaf ([string]$item.File))' fica de fora."
            $recusados++
            continue
        }
        Write-Host ''
        Write-Host "Restaurando '$(Split-Path -Leaf ([string]$item.File))' a partir de '$($item.Target)'."
        $r = Invoke-WinForgeNativeCommand -FilePath $icacls -Arguments @([string]$item.Target, '/restore', [string]$item.File, '/C')
        Write-Host ([string]$r.Text)
        if ([int]$r.ExitCode -ne 0) { Write-Error "Este arquivo terminou com código $($r.ExitCode)." } else { $aplicados++ }
    }
    Write-Host ''
    Write-Host "Desfazer concluído: $aplicados pasta(s) restauradas, $recusados fora."
    Write-Host 'Reinicie o computador para que os programas já abertos passem a enxergar as permissões que voltaram.'
}

#endregion
