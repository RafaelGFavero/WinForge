# WinForge — Aplicar no Diagnóstico, correções visíveis, permissões do disco C: e descrições (Plano 7)

Data: 2026-09-11. Complementa `2026-09-10-interface-ptbr-design.md`. Versão alvo: 1.6.0.

## 1. Objetivo

Feedback do teste da 1.5.0: (a) o checklist do Diagnóstico marca itens mas não há como aplicá-los ali; (b) na aba Configurações os botões de "Correções" (Rede - Redefinir, Servidor NTP, Windows Update - Redefinir, WinGet - Reinstalar) não mostram nada e "Verificação de corrupção do sistema" trava a janela; (c) falta uma correção para o caso "atualização de fabricante (Samsung) derrubou as permissões do disco C:"; (d) descrições de ajustes/recursos/apps são genéricas, repetem frases e não dizem o efeito real.

## 2. Diagnóstico: aplicar e desfazer

- Barra de botões ganha **"Aplicar marcados"** e **"Desfazer marcados"** ao lado do contador. Chamam exatamente o que a aba Ajustes chama (`Invoke-WPFtweaksbutton` / `Invoke-WPFundoall`), que leem `$sync.selectedTweaks` — já alimentado pelo espelho (a linha marca o controle real, cujo evento `Checked` registra a seleção). Confirmação e ponto de restauração seguem a regra da aba Ajustes (nada novo).
- Desabilitados enquanto `$sync.ProcessRunning`; contador continua.

## 3. Correções com saída visível (aba Configurações)

Causa: `Invoke-WPFButton` chama a função da base na **thread da janela** (`& $buttonConfig.function`), e a função escreve com `Write-Host`/`Start-Process -NoNewWindow` num console que o lançador esconde. Resultado: janela congelada e nenhum retorno.

- Os botões da base `WPFFixesNetwork`, `WPFFixesNTPPool`, `WPFPanelDISM`, `WPFFixesUpdate`, `WPFFixesWinget` passam a ser despachados pelo mecanismo de comandos do WinForge (`Invoke-WinForgeRepairCommand`, `Kind repair`, confirmação com a descrição): corpo num runspace, um por vez, barra de status "Em andamento: <título> (mm:ss)", e **janela de saída ao vivo**.
- Janela ao vivo: `Show-WinForgeOutputWindow -FollowPath <arquivo>` abre já no início e acompanha o arquivo (DispatcherTimer 500 ms, anexa só o que chegou); ao terminar, cabeçalho "Concluído em mm:ss, código N" e botão Fechar. `Invoke-WinForgeNativeCommand -StreamTo <arquivo>` roda o executável com stdout/stderr redirecionados (decodificação OEM, como hoje) gravando linha a linha.
- Comandos: `NetworkReset` (`netsh winsock reset`, `netsh int ip reset`; aviso de reinício), `NtpPool` (o que a base faz: `w32time` + `w32tm /config … pool.ntp.org` + `/resync`), `SystemRepair` (`chkdsk C: /scan /perf`, `sfc /scannow`, `DISM /Online /Cleanup-Image /RestoreHealth`, em sequência, cada um transmitido ao vivo; resumo no fim), `WindowsUpdateReset` (função da base executada dentro do runspace com `*>&1` para o arquivo), `WingetReinstall` (idem). `WPFPanelAutologin` fica como está (abre o Autologon da Sysinternals).
- `Invoke-WPFButton` deixa de chamar `function` para essas chaves (mesma guarda de `WPFWFRep*`).

## 4. Permissões do disco C: (novo grupo em "WinForge - Reparo de componentes")

Caso real: após uma atualização do fabricante, o disco C: perdeu a cadeia de permissões (usuário sem acesso a pastas, programas que não abrem, erros de acesso negado).

- **"Permissões do disco C: - Verificar"** (`read`): mostra dono e DACL de `C:\`, `C:\Windows`, `C:\Program Files`, `C:\Program Files (x86)`, `C:\ProgramData`, `C:\Users`, `C:\Users\Public` e do perfil atual, marca o que difere do padrão do Windows (dono, ACEs obrigatórias de SYSTEM/Administradores/Usuários) e termina com um veredito ("padrão", "N diferenças").
- **"Permissões do disco C: - Restaurar padrões"** (`repair`, confirmação com aviso de duração e reinício): (1) `chkdsk C: /scan` (só leitura) — se reportar erro, para e recomenda `chkdsk /f` na reinicialização (botão já existe); (2) **backup** das DACLs atuais com `icacls <pasta> /save <arquivo> /C` (raiz e pastas de primeiro nível sem recursão; perfil atual com `/T`) na pasta protegida `%ProgramData%\WinForge\acl-backup` (mesmos helpers de cadeia/DACL dos backups); (3) raiz: `icacls C:\ /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" "*S-1-5-11:(OI)(CI)(IO)M" "*S-1-5-11:AD"` (SIDs, não nomes — funciona em qualquer idioma); (4) `secedit /configure /cfg %windir%\inf\defltbase.inf /db <pasta protegida>\defltbase.sdb /areas FILESTORE REGKEYS /verbose` — reaplica as DACLs padrão do Windows em `Windows`, `Program Files`, `ProgramData`, `Users` e no registro (é o procedimento documentado pela Microsoft); (5) perfil atual: `icacls "<perfil>" /inheritance:r /grant:r "<SID do usuário>:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F"` seguido de `icacls "<perfil>" /reset /T /C /Q` (restaura herança abaixo); (6) `takeown` só quando o passo anterior falhar com acesso negado na raiz (`takeown /F C:\ /A`, sem recursão). Tudo ao vivo na janela; log; aviso de reinício ao final.
- **"Permissões do disco C: - Desfazer (restaurar backup)"** (`repair`): `icacls <pasta> /restore <arquivo>` para cada arquivo do backup mais recente (mesma validação de pasta/arquivo dos snapshots).
- Nunca: `/reset /T` na raiz inteira, `takeown /R`, alterar `C:\Windows` por icacls direto.

## 5. Descrições

- Reescrever as descrições de **todos** os ajustes, toggles, recursos e apps (dicionário `wf-i18n-configs.ps1` + entradas próprias em `wb-config.ps1`, `wf-server-config.ps1`, `wf-repair-config.ps1`): pesquisa por item (documentação Microsoft/fabricante); formato "O que faz. Efeito prático. Quando usar / custo."; direto, sem frase repetida, sem "Origem:" duplicado (a proveniência "Origem: … Windows Boost - Essential" aparece uma vez, no fim, só nas entradas que vieram de lá); `CUIDADO:` continua sendo prefixado pela auditoria.
- Trava no SelfTest: nenhuma descrição com sentença repetida (dividir em `. `, comparar normalizado), nenhuma com menos de 40 caracteres, nenhuma que repita o título literalmente, nenhuma com dois "Origem:".

## 6. Testes

- SelfTest: botões novos existem e despacham (`-NoUI`); `Show-WinForgeOutputWindow -FollowPath -NoShow` acompanha um arquivo que cresce (timer disparado à mão); `Invoke-WinForgeNativeCommand -StreamTo` grava linhas de um comando inofensivo (`cmd /c echo`); specs dos cinco comandos de correção válidos, `DryRun` sem execução, todos recusados em SelfTest; permissões: `Get-WinForgeAclReport -DryRun`/parser de `icacls` com saída sintética, plano de restauração (`-DryRun`) lista os passos na ordem e nunca executa; travas de descrição.
- Nada do SelfTest altera a máquina.
