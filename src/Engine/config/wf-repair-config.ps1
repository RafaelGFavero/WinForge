#region ===== WinForge - reparo de componentes (config) =====

# ---------------------------------------------------------------------------
# Botões do grupo "WinForge - Reparo de componentes" (mesclados em $sync.configs.feature)
#   panel 1 = coluna da esquerda da aba Config | Type Button | ButtonWidth 350
#
# Nenhuma entrada declara "function", de propósito: quem despacha estes botões é o switch de
# Invoke-WPFButton, com "Invoke-WinForgeRepairCommand -Name <nome curto>" por caso. O caminho da
# config chamaria a função SEM argumento nenhum, e ela não saberia qual comando rodar - por isso o
# lookup de Invoke-WPFButton também pula as chaves WPFWFRep*.
#
# A descrição de cada botão diz o que ele faz, o que muda na máquina e o que ele exige, e os que
# alteram o sistema avisam isso na primeira linha. Ela tem um segundo leitor além de quem passa o
# olho na aba: Get-WinForgeRepairConfirmText usa ESTE texto na caixa de Sim/Não que aparece antes de
# 'repair' e 'install' rodarem. Por isso ele descreve, mas não pergunta - a pergunta é acrescentada
# uma vez só, na hora de montar a caixa.
# ---------------------------------------------------------------------------
$sync.configs.wfrepair = @'
{
  "WPFWFRepSecurityStatus": {
    "Content": "Estado de TPM, Secure Boot e BitLocker",
    "Description": "Só lê, sem alterar nada. Mostra numa janela se o TPM está presente e pronto, se o Secure Boot está ligado, o estado do BitLocker de cada volume e se a segurança baseada em virtualização (VBS/Credential Guard) está configurada e rodando. TPM e BitLocker só respondem com o WinForge aberto como administrador; sem elevação aparecem como 'n/d'.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepSmartReport": {
    "Content": "Saúde dos discos (SMART)",
    "Description": "Só lê, sem alterar nada. Lista os discos físicos (modelo, tipo, tamanho, estado) e os contadores SMART de cada um: temperatura, horas ligado, desgaste e erros de leitura/escrita não corrigidos. Os contadores dependem do disco e do controlador: em USB e em alguns RAID eles não existem, e aí a linha diz 'indisponíveis'.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepDotNetStatus": {
    "Content": "Estado do .NET Framework 3.5 e 4.8",
    "Description": "Só lê, sem alterar nada. Diz se o recurso NetFx3 (.NET Framework 3.5) está habilitado e qual versão da linha 4.x está instalada, lida do valor Release do registro (528040 ou maior = 4.8). A parte do 3.5 exige o WinForge aberto como administrador; sem elevação aparece como 'n/d'.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepChkdskScan": {
    "Content": "Verificar disco do sistema agora (chkdsk /scan)",
    "Description": "Só lê, sem alterar nada. Roda 'chkdsk /scan' no disco do Windows: é a verificação online, com o sistema em uso, que relata problemas sem reparar nada e sem reiniciar. Pode demorar minutos num disco grande. Para reparar de verdade, use o botão de agendar o chkdsk /f.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepWmiRepair": {
    "Content": "Repositório WMI: verificar e recuperar",
    "Description": "ALTERA O SISTEMA. Roda 'winmgmt /verifyrepository' e, só se o repositório estiver inconsistente, 'winmgmt /salvagerepository' (recupera o que dá para aproveitar; não apaga o repositório). Programas que consultam o WMI podem falhar durante a recuperação. Exige o WinForge aberto como administrador: sem elevação a verificação responde 'acesso negado', e o botão para aí em vez de recuperar o repositório por causa de uma leitura que não aconteceu.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepStoreReregister": {
    "Content": "Microsoft Store e App Installer: registrar de novo",
    "Description": "ALTERA O SISTEMA. Registra de novo, PARA O USUÁRIO ATUAL, a Microsoft Store, o App Installer (winget) e o Store Purchase App a partir do AppXManifest.xml que já está no disco, sem baixar nada. É o reparo de 'a Store não abre' e de 'o winget sumiu'. Os aplicativos fecham durante o registro. Vale só para quem está com o WinForge aberto: outros usuários da máquina precisam rodar o botão no próprio logon. Com o WinForge como administrador a busca alcança os pacotes que sumiram do perfil atual.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepChkdskSchedule": {
    "Content": "Agendar chkdsk /f na próxima reinicialização",
    "Description": "ALTERA O SISTEMA E NÃO TEM DESFAZER. Marca o disco do Windows como 'sujo' (fsutil dirty set): na próxima reinicialização o chkdsk roda com reparo antes de o Windows carregar, e isso pode demorar bastante - a máquina não pode ser desligada no meio. Não existe 'fsutil dirty clear': quem limpa a marca é o próprio chkdsk, e só quando concluir que o volume está íntegro, então num disco com problema a verificação se repete a cada reinicialização. Nada é verificado agora. Exige o WinForge aberto como administrador.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepMemoryDiag": {
    "Content": "Diagnóstico de memória na próxima reinicialização",
    "Description": "ALTERA O SISTEMA. Coloca o Diagnóstico de Memória do Windows na sequência de inicialização (bcdedit /bootsequence {memdiag}): vale para a PRÓXIMA reinicialização e só para ela. O teste roda antes do Windows e o resultado aparece no Visualizador de Eventos. Exige o WinForge aberto como administrador.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepDotNet35Enable": {
    "Content": ".NET Framework 3.5: habilitar (DISM)",
    "Description": "INSTALA COMPONENTE. Habilita o recurso NetFx3 (.NET Framework 3.5, com WCF) pelo DISM, sem reiniciar na hora. Os arquivos não estão na imagem instalada: vêm do Windows Update, então precisa de internet e pode demorar minutos. Em rede com WSUS restritivo o DISM pede a mídia do Windows. Exige o WinForge aberto como administrador.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepVcRedist": {
    "Content": "Visual C++ 2005–2022 (x86/x64) via winget",
    "Description": "INSTALA COMPONENTE. Instala ou atualiza os 12 pacotes redistribuíveis do Visual C++ (2005, 2008, 2010, 2012, 2013 e 2015-2022), nas duas arquiteturas, pelo winget. O que já está instalado é pulado. É o que resolve erro de VCRUNTIME140.dll e MSVCP140.dll. São vários downloads: precisa de internet e demora. Exige o winget instalado (App Installer) e o WinForge aberto como administrador.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepPowerShell7": {
    "Content": "PowerShell 7 via winget",
    "Description": "INSTALA COMPONENTE. Instala o PowerShell 7 (Microsoft.PowerShell) pelo winget, lado a lado: o Windows PowerShell 5.1 continua instalado e é ele que roda o WinForge. Precisa de internet e do winget instalado (App Installer).",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepDirectX": {
    "Content": "DirectX: abrir a página oficial da Microsoft",
    "Description": "Só abre uma página. Abre no navegador a página oficial de download do DirectX End-User Runtime Web Installer, no site da Microsoft. O download e a execução do dxwebsetup.exe são seus, no navegador: o WinForge não baixa nem executa arquivo nenhum da internet. O instalador é interativo e traz as bibliotecas antigas do DirectX (d3dx9, XInput) que jogos mais velhos pedem; o DirectX do sistema continua vindo pelo Windows Update. Precisa de internet.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepAclVerify": {
    "Content": "Permissões do disco C: - Verificar",
    "Description": "Só lê, sem alterar nada. Confere o dono e a lista de permissões da raiz do disco, de Windows, Program Files, Program Files (x86), ProgramData, Users, Users\\Public e da sua pasta de usuário contra o padrão de fábrica. O confronto é feito por SID, então o resultado vale igual num Windows em inglês e num em português. Toda ACE de negação de acesso entra como diferença: nenhuma dessas pastas tem negação de fábrica, e uma negação plantada tranca o acesso sem tirar uma única permissão da lista. Cada pasta sai marcada como 'padrão' ou com o que está faltando nela, e o texto termina com a contagem das diferenças.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepAclRestore": {
    "Content": "Permissões do disco C: - Restaurar padrões",
    "Description": "ALTERA O SISTEMA E PEDE REINICIALIZAÇÃO. É o reparo de 'depois da atualização do fabricante perdi o acesso às minhas pastas', em seis fases: chkdsk /scan para conferir o volume antes de qualquer coisa; backup das listas atuais em %ProgramData%\\WinForge\\acl-backup, guardando a lista e o dono de cada pasta em SDDL dentro do índice e, só para a sua pasta de usuário, um arquivo de icacls com o conteúdo inteiro; a raiz do disco, com as ACEs padrão por SID; as pastas do sistema (Windows, Program Files, Program Files (x86), ProgramData, Users e Users\\Public) uma a uma, com o icacls apontado só para a pasta e apenas naquelas que a verificação acusou; a sua pasta de usuário, religando a herança do conteúdo depois de conceder na raiz dela; e, só quando a raiz responde acesso negado, um takeown sem recursão seguido de nova tentativa. Negações de acesso saem antes das concessões, porque negar vence permitir. Se o chkdsk acusar erro no volume, nada é alterado. O Desfazer devolve a lista de permissões de cada pasta guardada e tenta devolver o dono; devolver a posse ao TrustedInstaller nem sempre é possível, e nesse caso ele diz em qual pasta. Leva vários minutos e é preciso reiniciar o computador no fim. Exige o WinForge aberto como administrador.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepAclUndo": {
    "Content": "Permissões do disco C: - Desfazer (restaurar backup)",
    "Description": "ALTERA O SISTEMA. Reaplica as listas de permissão que o botão de restaurar padrões guardou antes de mexer no disco, a partir do conjunto mais antigo que ainda não foi usado, que é o que preserva o backup bom quando a restauração rodou mais de uma vez. A lista de cada pasta volta pelo SDDL guardado no índice, e junto com ela vai uma tentativa de devolver o dono; o conteúdo da sua pasta de usuário volta por icacls /restore, com /L para o restauro não sair do perfil pelas junções de compatibilidade. Só aceita índice e arquivo que estejam diretamente na pasta protegida %ProgramData%\\WinForge\\acl-backup e cujo dono seja o SYSTEM ou o grupo Administradores; qualquer outro é recusado sem nem ser lido. Dois limites: devolver a posse ao TrustedInstaller exige um privilégio que nem todo administrador tem, e quando falha o botão diz em qual pasta; e fora do seu perfil volta a lista da pasta, não a de cada arquivo dentro dela. Sem nenhum backup gravado o botão apenas diz isso e não toca em nada. Exige o WinForge aberto como administrador.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepAclCleanup": {
    "Content": "Permissões do disco C: - Limpar backups antigos",
    "Description": "Lista os arquivos de backup de permissões guardados pelo WinForge com tamanho e data, marca os que nenhum índice usa e apaga só os marcados, sob confirmação.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepNetDiagFull": {
    "Content": "Rede — Diagnóstico completo",
    "Description": "Só lê, sem alterar nada. Levanta doze pontos da rede deste computador: o rádio sem fio, o perfil da rede ativa, o endereço IP e o 169.254 que aparece quando o roteador não responde, a rota padrão, o servidor de nomes comparado com o 1.1.1.1, três sondas de saída para a internet, o proxy do usuário e o do WinHTTP, os filtros de terceiro presos aos adaptadores, o catálogo de protocolos do Winsock, o tamanho máximo de pacote, o IPv6 e o código de problema do dispositivo. Termina com uma frase de veredito, escolhida de uma lista fechada de cinco, dizendo por onde começar. Quando acha filtro de antivírus, firewall ou VPN ligado em todos os adaptadores físicos, ele nomeia o filtro e escreve o caminho de menu do próprio Windows para você desligá-lo à mão: este programa não desliga, não reconfigura e não desinstala produto de segurança de terceiro. Nenhum driver é tocado aqui.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepNetDnsRenew": {
    "Content": "Rede — Limpar cache de DNS e pegar endereço novo",
    "Description": "ALTERA O SISTEMA. Esvazia o cache de nomes do Windows, devolve ao roteador o endereço que esta máquina está usando, pede outro no lugar e limpa também o cache de nomes NetBIOS, nessa ordem. É o primeiro conserto a tentar quando o diagnóstico aponta endereço 169.254 ou servidor de nomes mudo, e é reversível por natureza: o roteador entrega outro endereço em segundos. A rede cai durante a troca; por isso, se você estiver usando este computador de longe, por Área de Trabalho Remota, o botão recusa no clique e explica: a sua própria conexão cairia junto e não haveria como desfazer de longe. Não toca em driver, em antivírus nem na pilha de rede: para essas coisas há outros botões, e o diagnóstico diz qual.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepWifiDriverReinstall": {
    "Content": "Rede sem fio — Reinstalar o driver que já está instalado",
    "Description": "ALTERA O SISTEMA. É o degrau mais conservador dos que mexem em driver: nenhum pacote é apagado do repositório, então o Windows repõe exatamente o mesmo driver que já estava. Serve para quando o driver é o certo e a instalação dele é que azedou. Antes de qualquer coisa ele guarda uma cópia conferida do driver atual em %ProgramData%\\WinForge\\driver-backup e confere arquivo por arquivo; se a cópia falhar, a ação para ali e nada é alterado, porque sem ela não existe caminho de volta. Depois tira o rádio da lista de dispositivos e manda o Windows procurar de novo. Se o rádio voltar com problema, sumido ou em situação estranha, o driver guardado é devolvido NA HORA, sem perguntar - num notebook sem porta de rede, mandar você clicar noutro botão para voltar seria mandar clicar sem rede. A detecção de acesso remoto cobre a Área de Trabalho Remota do Windows e não enxerga AnyDesk, TeamViewer ou RustDesk.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  },
  "WPFWFRepWifiDriverRestore": {
    "Content": "Rede sem fio — Voltar para o driver que estava antes",
    "Description": "ALTERA O SISTEMA. Pega o pacote de driver guardado na última cópia de segurança e o PROPÕE ao Windows: quem decide qual pacote assume o dispositivo é o mecanismo de classificação do próprio Windows, que pode escolher outro, e por isso o relatório conta o que o adaptador virou em vez de afirmar que a volta aconteceu. É a rede de segurança dos outros dois botões de driver, e existe antes deles de propósito: sem volta, não se oferece a ida. Aparece habilitado depois que 'Reinstalar' ou 'Trocar pelo driver básico' guardarem uma cópia conferida em disco; sem cópia nenhuma ele fica desabilitado e a dica diz isso. Se nem assim o rádio voltar, o texto manda trazer o driver do fabricante por cabo ou pen drive, de outro computador.",
    "category": "WinForge - Reparo de componentes",
    "panel": "1",
    "Type": "Button",
    "ButtonWidth": "350"
  }
}
'@ | ConvertFrom-Json

#endregion
