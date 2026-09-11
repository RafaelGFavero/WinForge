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
- **"Permissões do disco C: - Restaurar padrões"** (`repair`, confirmação com aviso de duração e reinício), em seis fases: (1) `chkdsk C: /scan` (só leitura) — se reportar erro, para e recomenda `chkdsk /f` na reinicialização (botão já existe); (2) **backup** na pasta protegida `%ProgramData%\WinForge\acl-backup` (mesmos helpers de cadeia/DACL dos backups): para cada pasta guardada — a raiz, cada pasta de primeiro nível, as aninhadas da tabela de esperados (`Users\Public`) e o perfil — a DACL **em SDDL** e o dono vão para o **índice** (JSON), e só o perfil ganha ainda um `icacls "<perfil>" /save <arquivo> /T /L /C /Q` para o CONTEÚDO; (3) raiz: `icacls C:\ /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" "*S-1-5-11:(OI)(CI)(IO)M"` e, numa chamada separada, `/grant "*S-1-5-11:(AD)"` (SIDs, não nomes — funciona em qualquer idioma; direito específico entre parênteses, senão o icacls responde 87); (4) as seis pastas do sistema, **uma a uma e só as que a verificação acusou**, com `/setowner` condicional e `/inheritance:r /grant:r` + `/grant` da tabela medida, NA PASTA, sem `/T` e sem `/reset`; acesso negado numa pasta do TrustedInstaller cai no par de socorro (posse para Administradores, segunda tentativa, posse devolvida); (5) perfil atual: `/setowner` e `/remove:d` condicionais, `icacls "<perfil>" /inheritance:r /grant:r "<SID do usuário>:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F"` e, depois disso, `icacls "<perfil>\*" /inheritance:e /T /L /C /Q` no conteúdo; (6) `takeown /F C:\ /A` (sem recursão) só quando a fase 3 falhar com acesso negado na raiz, seguido de uma segunda tentativa. Tudo ao vivo na janela; log; aviso de reinício ao final.
- **"Permissões do disco C: - Desfazer (restaurar backup)"** (`repair`): a lista de cada pasta volta do SDDL do índice (`SetSecurityDescriptorSddlForm` + `DirectoryInfo.SetAccessControl`, seção Access — nunca `Set-Acl`, que reescreve a DACL junto com o dono), com o dono tentado em operação separada; o conteúdo do perfil volta por `icacls <pasta acima> /restore <arquivo> /C /L` (mesma validação de pasta/arquivo dos snapshots).
- Nunca: `/reset /T` na raiz inteira, `takeown /R`, alterar `C:\Windows` por icacls direto, `/T` sem `/L`, `/restore` sem `/L`.

### Desvios medidos em relação ao rascunho acima (11/09/2026)

Três pontos do rascunho não sobreviveram à medição, e a implementação é a que vale:

1. **Sem `secedit`.** No Windows 10 e no 11 o `defltbase.inf` tem `[File Security]` e `[Registry Keys]` **vazias**: `/areas FILESTORE REGKEYS` não repõe DACL nenhuma. A fase 4 faz esse trabalho explicitamente, pasta a pasta, com uma tabela de ACEs medida.
2. **Sem `/reset /T` no perfil.** Ele apagaria as ACEs explícitas que os próprios aplicativos põem dentro do perfil (`AppData\Local\Packages`, OneDrive). `/inheritance:e /T /L` propaga o que a raiz do perfil concede e preserva as explícitas.
3. **O backup da pasta em si é SDDL, não `icacls /save`.** Medido, elevado, numa pasta de `%TEMP%`: `icacls <pasta>\ /save f /C` grava a entrada da própria pasta com o **nome vazio**, e `icacls <pasta>\ /restore f /C /L` **não a aplica** — monta o caminho `<pasta>\<sddl>` e responde "arquivo não encontrado". O `/save` desfaz os filhos; a pasta em si só volta por SDDL. Daí o índice em JSON.

## 5. Descrições

- Reescrever as descrições de **todos** os ajustes, toggles, recursos e apps (dicionário `wf-i18n-configs.ps1` + entradas próprias em `wb-config.ps1`, `wf-server-config.ps1`, `wf-repair-config.ps1`): pesquisa por item (documentação Microsoft/fabricante); formato "O que faz. Efeito prático. Quando usar / custo."; direto, sem frase repetida, sem "Origem:" duplicado (a proveniência "Origem: … Windows Boost - Essential" aparece uma vez, no fim, só nas entradas que vieram de lá); `CUIDADO:` continua sendo prefixado pela auditoria.
- Trava no SelfTest: nenhuma descrição com sentença repetida (dividir em `. `, comparar normalizado), nenhuma com menos de 40 caracteres, nenhuma que repita o título literalmente, nenhuma com dois "Origem:".

## 6. Testes

- SelfTest: botões novos existem e despacham (`-NoUI`); `Show-WinForgeOutputWindow -FollowPath -NoShow` acompanha um arquivo que cresce (timer disparado à mão); `Invoke-WinForgeNativeCommand -StreamTo` grava linhas de um comando inofensivo (`cmd /c echo`); specs dos cinco comandos de correção válidos, `DryRun` sem execução, todos recusados em SelfTest; permissões: `Get-WinForgeAclReport -DryRun`/parser de `icacls` com saída sintética, plano de restauração (`-DryRun`) lista os passos na ordem e nunca executa; travas de descrição.
- Nada do SelfTest altera a máquina.
