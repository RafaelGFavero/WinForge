# WinForge 1.8.0 — Permissões, drivers e rede Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tirar do botão das permissões o laço que enche o disco (~205 GB em 404 min), dar memória, teto e Parar à janela de saída, agrupar os INFs sem versão do Windows Update com o cerco de chipset em volta, e acrescentar a escada de rede sem fio — sem baixar nem executar instalador de terceiro.

**Architecture:** A Fase 2 da restauração de permissões deixa de ser `icacls /save /T` e passa a ser uma caminhada em pilha no .NET que lê `[IO.File]::GetAttributes` antes de empilhar, nunca desce nem indexa ponto de reanálise, prefixa `\\?\` em toda chamada e guarda só pasta com herança bloqueada (`AreAccessRulesProtected`). O que ela guarda é exatamente o que a Fase 5 aplica: `icacls <pasta> /inheritance:e /C /Q` por entrada da mesma lista, sem `/T`. O arquivo de conteúdo continua no formato do `icacls /save` (pares nome/SDDL em UTF-16LE sem BOM), porque o Desfazer segue usando `icacls /restore`; o que muda é quem o escreve e de onde ele sai. O índice ganha `Sha256`, `ExternalPath`, `Consumed` e a origem da máquina (`MachineGuid` + SID do perfil), e o Desfazer passa a ler o mais antigo não consumido em vez do mais novo.

A janela de saída ganha três camadas independentes: fluxo (`-StreamTo` nas fases 3 a 5 - depois da Tarefa 3 a fase 2 não roda processo nenhum -, escritor persistente, sem acúmulo em `StringBuilder`, erro lido linha a linha), teto (anel de 4 MB → 2 MB com histerese na caixa, leitura por tique limitada, arquivo de 256 MB, retenção 30 dias / 20 arquivos por prefixo) e cancelamento (Job Object criado dentro do scriptblock do pool com `Add-Type` guardado, flag por caminho de arquivo, e a Fase 4 deliberadamente FORA do job, com marcador `acl-posse-pendente.json` para o caso de a troca de posse morrer no meio).

Os drivers do Windows Update ganham uma segunda camada de vista dentro de `Update-WinForgeDiagnosticsWindowsUpdateGrid`: `Select-WinForgeWindowsUpdateLatest` não muda, e `Group-WinForgeWindowsUpdateNullDrivers` agrupa por (fornecedor, classe, data) as ofertas sem versão, de classe permitida e de tamanho pequeno. O grupo é uma linha sintética com `UpdateId = 'grupo:<hash>'`, estado derivado a cada remontagem e instalação num único `Invoke-WPFRunspace` com `foreach` sobre os membros. O §4 (chipset INF) não é botão novo: é o filtro, o ponto de restauração e o texto que cercam o `Instalar todos (N)` dessa linha. A rede entra como cinco linhas novas de `Get-WinForgeRepairCommand` mais a de redefinição que já existe, com todos os bloqueios em funções de leitura puras e o `pnputil` tratado pelas três armadilhas medidas (`$LASTEXITCODE -ne 0`, decodificação `ansi`, saída interpretada mesmo com código 0).

**Tech Stack:** Windows PowerShell 5.1, WPF (DataGrid, DispatcherTimer, `System.Windows.Forms.FolderBrowserDialog`), `System.IO`/`System.Security.AccessControl`, P/Invoke via `Add-Type` (Job Object, `GetSystemMetrics`), COM `Microsoft.Update.Session`, `icacls.exe`/`takeown.exe`/`pnputil.exe`/`netsh.exe`/`ipconfig.exe`/`nbtstat.exe` por caminho absoluto do System32, SelfTest do próprio motor como suíte de testes.

**Spec:** C:\Users\rafa_\Projetos\WinForge\docs\superpowers\specs\2026-09-12-permissoes-drivers-rede-design.md

## Global Constraints

- Nunca editar `src/Engine/base/winutil-26.08.19.ps1` nem `dist/`; o motor é gerado por `src/Engine/build.ps1` a partir de `src/Engine/{winforge,config,xaml}`.
- Todo arquivo de fonte do motor é UTF-8 com BOM e CRLF; textos em pt-BR; funções `*-WinForge*`.
- O código de teste vive dentro do here-string de aspas simples do bloco `if ($SelfTest)` de `src/Engine/build.ps1` (começa em `build.ps1:1107`, termina em `build.ps1:5870`): `$` é literal ali, e a sequência `'@` nunca pode aparecer no início de uma linha.
- Toda função nova declara `param()`, mesmo sem parâmetro.
- `$sync.SelfTest = $true` faz todo helper de escrita e todo comando de `Kind` diferente de `read` lançar; toda função nova que escreve chama `Assert-WinForgeNotSelfTest`.
- Scriptblock criado em runspace de pool e invocado por `Dispatcher.Invoke` causa deadlock: callback de interface é scriptblock de escopo de arquivo criado na runspace principal. `Invoke-WPFUIThread` não recebe argumento — o pacote viaja por slot GUID em `$sync`.
- Verificação de **toda** tarefa: `build.cmd` (motor → SelfTest ×2 → `dotnet build` → `dist\WinForge.exe`). `dotnet test src\Launcher.Tests` (22 testes) e `git diff --exit-code -- docs/auditoria.md` rodam na Tarefa 23 e em qualquer tarefa que toque `src/Launcher*` ou `docs/` — nenhuma outra tarefa deste plano toca esses caminhos, e é por isso que só o Step 4 da Tarefa 23 os lista. (Antes esta linha exigia os três em cada tarefa e nenhum Step 4 os cumpria; a exigência é que estava errada, não os Steps.)
- Travas de contagem em `build.ps1:1157`: Tweaks 83, Jogos 84, Servidor 22, Instalar 137 não mudam. Config sobe de 57 para 63 ao longo do plano, uma entrada por vez: **a tarefa que acrescenta entrada de config sobe o número da trava no mesmo commit**, senão o build fica vermelho entre tarefas. Valor final: 63 (Tarefas 6, 15, 16, 18 e 19 — a 18 sobe duas de uma vez porque entrega dois botões inseparáveis).
- Nenhuma tarefa pode deixar o botão das permissões pior do que está hoje. **Dois pares indivisíveis**, e a razão de cada um está escrita na tarefa: **3 + 4** (a Fase 2 guarda o que a Fase 5 aplica) e **5 + 6** (a recusa de restauração da Tarefa 5 manda usar um botão que só nasce na Tarefa 6). Nada de PR, tag ou release entre os membros de um par.
- **Por que as Tarefas 8 e 9 (135 MB → 1.575 MB de pico, spec §2) vêm depois de sete tarefas**, e não é ordem arbitrária: a Tarefa 8 reescreve exatamente as mesmas chamadas das fases 3 a 5 que as Tarefas 3 e 4 mexem em `wf-repair.ps1`. Fazê-la antes garantiria conflito nas duas pontas e obrigaria a reescrever o mesmo trecho duas vezes. O dano que trava a máquina (~205 GB) morre nas Tarefas 1 a 4; o de memória é o segundo pior e sai logo depois do par 5 + 6.
- **Menor corte entregável:** Tarefas 1 a 6 + 23. Para quem está com a máquina travada, isso já devolve o disco e conserta o Desfazer. As Tarefas 8 a 22 são conforto e recursos novos.
- `icacls … /T` sobre pasta de perfil está proibido a partir da Tarefa 3, em qualquer fase.
- Nada neste plano baixa ou executa instalador de terceiro. A exceção da NVIDIA é a única e não se estende à Intel.
- Commits: Conventional Commits com trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Branch `feat/plan9-permissoes`, base `a957723`; encerrar com push + PR, nunca merge local.

---

### Task 1: A caminhada que substitui o `icacls /save /T`

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — nova função `Get-WinForgeAclContentScope`, inserida logo depois de `Get-WinForgeAclFolderSecurity` (`wf-repair.ps1:2133-2188`).
- Test: `src/Engine/build.ps1`, bloco novo dentro do `if ($SelfTest)`, logo antes de `# ---------------------------------------------------------------- Windows Update: uma linha por dispositivo` (`build.ps1:4138`).

**Interfaces:**
- Consumes: nada de tarefas anteriores.
- Produces:
  ```powershell
  Get-WinForgeAclContentScope -Path <string> [-IncludeFiles]
      [-MaxItems 20000] [-MaxBytes 4194304] [-MaxDepth 32] [-MaxSeconds 90]
    → @{ Ok = <bool>; Reason = <string>; Entries = @(@{ Name = <string>; Sddl = <string> });
         Scanned = <int>; Reparse = <int>; Denied = <int>; DeniedPaths = @(<string>);
         Deny = <int>; Bytes = <int>; Seconds = <double> }
  ```
  `Name` é o caminho RELATIVO à pasta acima de `-Path` (`Split-Path -Parent`), com a própria pasta entrando como a folha (`rafa_`, `rafa_\AppData`, …). `Deny` conta quantas entradas têm ACE de negação no SDDL. Estourar qualquer teto devolve `Ok = $false`, `Reason` com a frase do §1.6 e `Entries` **vazio** — nunca o coletado até ali.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Permissões: a caminhada
    # O laço que encheu o disco em produção: 'AppData\Local\Dados de Aplicativos' é uma junção para
    # 'AppData\Local', alcançável por dois caminhos, e quem para a recursão é o limite de 63 saltos
    # de reparse - não o MAX_PATH. A caminhada nova não desce em ponto de reanálise E não o indexa:
    # o .NET lê a ACL do ALVO e o '/restore /L' a devolveria ao LINK, trocando permissão por
    # permissão. As duas coisas, e é isto que o teste cobra.
    $wfCamRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-caminhada'
    try {
        if (Test-Path -LiteralPath $wfCamRaiz) { Remove-Item -LiteralPath $wfCamRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        $wfCamPerfil = Join-Path $wfCamRaiz 'perfil'
        $wfCamLocal = Join-Path $wfCamPerfil 'AppData\Local'
        New-Item -ItemType Directory -Path $wfCamLocal -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $wfCamPerfil 'Documentos') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $wfCamPerfil 'nota.txt') -Value 'x' -Encoding UTF8
        # A junção auto-referente: 'Dados de Aplicativos' -> o próprio pai. É o laço exato da máquina real.
        $wfCamJuncao = Join-Path $wfCamLocal 'Dados de Aplicativos'
        cmd.exe /c mklink /J "$wfCamJuncao" "$wfCamLocal" | Out-Null
        if (-not (Test-Path -LiteralPath $wfCamJuncao)) { throw "a junção de teste não pôde ser criada em '$wfCamJuncao'" }
        # Herança bloqueada em UMA pasta: é ela, e só ela, que o filtro tem de guardar.
        $wfCamProt = New-Object System.IO.DirectoryInfo (Join-Path $wfCamPerfil 'Documentos')
        $wfCamSd = $wfCamProt.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $wfCamSd.SetAccessRuleProtection($true, $true)
        $wfCamProt.SetAccessControl($wfCamSd)

        $wfCamR = Get-WinForgeAclContentScope -Path $wfCamPerfil
        if (-not $wfCamR.Ok) { Write-Host "  [ERRO] Permissões (caminhada): devolveu Ok=`$false ('$($wfCamR.Reason)') numa pasta de teste íntegra" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamR.Reparse -lt 1) { Write-Host "  [ERRO] Permissões (caminhada): a junção não foi contada em Reparse (veio $($wfCamR.Reparse))" -ForegroundColor Red; $wbErrors++ }
        $wfCamNomes = @($wfCamR.Entries | ForEach-Object { [string]$_.Name })
        if (@($wfCamNomes | Where-Object { $_ -like '*Dados de Aplicativos*' }).Count) { Write-Host "  [ERRO] Permissões (caminhada): o ponto de reanálise virou ENTRADA ('$($wfCamNomes -join ' | ')') - o /restore /L aplicaria no link a ACL do destino" -ForegroundColor Red; $wbErrors++ }
        if (@($wfCamNomes | Sort-Object -Unique).Count -ne $wfCamNomes.Count) { Write-Host "  [ERRO] Permissões (caminhada): item visitado duas vezes ('$($wfCamNomes -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        # CONTAGEM EXATA, e não 'pelo menos': com uma entrada só, "sem duplicata" é vácuo, e contar o
        # reparse E empilhá-lo passaria verde com o laço inteiro vivo e invisível. São quatro pastas -
        # perfil, AppData, Local, Documentos - e nenhuma quinta: 'Scanned' conta pasta ENUMERADA, o
        # ponto de reanálise conta só em 'Reparse'. Descer na junção traria Local e Documentos de novo
        # e isto viraria 6.
        if ([int]$wfCamR.Scanned -ne 4) { Write-Host "  [ERRO] Permissões (caminhada): Scanned=$($wfCamR.Scanned), esperado exatamente 4 (perfil, AppData, Local, Documentos) - mais que isso é a junção sendo descida" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamR.Reparse -ne 1) { Write-Host "  [ERRO] Permissões (caminhada): Reparse=$($wfCamR.Reparse), esperado exatamente 1" -ForegroundColor Red; $wbErrors++ }
        if (@($wfCamR.Entries).Count -ne 1) { Write-Host "  [ERRO] Permissões (caminhada): o filtro é AreAccessRulesProtected - esperava 1 entrada, veio $(@($wfCamR.Entries).Count)" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfCamR.Entries[0].Name -notlike '*Documentos') { Write-Host "  [ERRO] Permissões (caminhada): a entrada guardada é '$($wfCamR.Entries[0].Name)', esperada a pasta com herança bloqueada" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]::IsNullOrWhiteSpace([string]$wfCamR.Entries[0].Sddl)) { Write-Host "  [ERRO] Permissões (caminhada): a entrada veio sem SDDL" -ForegroundColor Red; $wbErrors++ }
        # Nome RELATIVO à pasta ACIMA do perfil, com a folha do perfil na frente: é o que o
        # 'icacls <pasta acima> /restore' espera, e é o que o Desfazer vai consumir.
        if ([string]$wfCamR.Entries[0].Name -ne 'perfil\Documentos') { Write-Host "  [ERRO] Permissões (caminhada): o nome relativo veio '$($wfCamR.Entries[0].Name)', esperado 'perfil\Documentos'" -ForegroundColor Red; $wbErrors++ }
        # Arquivo fica FORA por padrão (84 protegidos em 294.011 na máquina medida, todos cache).
        # Contagem EXATA outra vez: há um único arquivo na árvore ('nota.txt'), então -IncludeFiles
        # soma exatamente 1. "Aumentou" passaria verde com a árvore inteira sendo varrida duas vezes.
        $wfCamArq = Get-WinForgeAclContentScope -Path $wfCamPerfil -IncludeFiles
        if ([int]$wfCamArq.Scanned -ne ([int]$wfCamR.Scanned + 1)) { Write-Host "  [ERRO] Permissões (caminhada): -IncludeFiles deu Scanned=$($wfCamArq.Scanned), esperado $([int]$wfCamR.Scanned + 1) (só 'nota.txt' entra)" -ForegroundColor Red; $wbErrors++ }

        # Os quatro tetos: Entries VAZIO, nunca o coletado até ali, e a frase de §1.6.
        # '@($h)[0]' NÃO é splat - é argumento posicional, e os quatro tetos rodariam com o padrão,
        # sem estourar nunca. Splat é '@nome', sobre uma VARIÁVEL.
        foreach ($wfCamTeto in @(
            @{ Nome = 'MaxItems';   Args = @{ MaxItems = 0 } },
            @{ Nome = 'MaxBytes';   Args = @{ MaxBytes = 1 } },
            @{ Nome = 'MaxDepth';   Args = @{ MaxDepth = 0 } },
            @{ Nome = 'MaxSeconds'; Args = @{ MaxSeconds = 0 } })) {
            $wfCamArgs = $wfCamTeto.Args
            $wfCamEstouro = Get-WinForgeAclContentScope -Path $wfCamPerfil @wfCamArgs
            if ($wfCamEstouro.Ok) { Write-Host "  [ERRO] Permissões (tetos): $($wfCamTeto.Nome) estourado devolveu Ok=`$true" -ForegroundColor Red; $wbErrors++ }
            if (@($wfCamEstouro.Entries).Count -ne 0) { Write-Host "  [ERRO] Permissões (tetos): $($wfCamTeto.Nome) devolveu $(@($wfCamEstouro.Entries).Count) entrada(s) - o parcial não pode sair" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfCamEstouro.Reason -notmatch 'nada foi alterado') { Write-Host "  [ERRO] Permissões (tetos): $($wfCamTeto.Nome) sem a frase de §1.6 ('$($wfCamEstouro.Reason)')" -ForegroundColor Red; $wbErrors++ }
        }
        # Caminho longo: sem o prefixo '\\?\' isto estoura PathTooLongException no PC do usuário,
        # porque LongPathsEnabled=1 não é o padrão.
        $wfCamLongo = $wfCamPerfil
        while ($wfCamLongo.Length -lt 294) { $wfCamLongo = Join-Path $wfCamLongo ('n' * 30) }
        [System.IO.Directory]::CreateDirectory('\\?\' + $wfCamLongo) | Out-Null
        $wfCamRLongo = Get-WinForgeAclContentScope -Path $wfCamPerfil
        if (-not $wfCamRLongo.Ok) { Write-Host "  [ERRO] Permissões (caminho longo): a caminhada falhou ('$($wfCamRLongo.Reason)') - falta o prefixo \\?\" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfCamRLongo.Denied -ne 0) { Write-Host "  [ERRO] Permissões (caminho longo): $($wfCamRLongo.Denied) negada(s) num caminho de $($wfCamLongo.Length) caracteres - o prefixo \\?\ não está em toda chamada" -ForegroundColor Red; $wbErrors++ }
        # 'Denied' conta GetAccessControl e EnumerateFileSystemEntries, e NÃO GetAttributes: medido,
        # em pasta negada o GetAttributes não lança, e contá-lo daria zero justo onde há problema.
        $wfCamFonte = [string](Get-Command Get-WinForgeAclContentScope).ScriptBlock
        if ($wfCamFonte -match 'AllDirectories') { Write-Host "  [ERRO] Permissões (caminhada): EnumerateFileSystemEntries com AllDirectories é proibido - ele segue reparse point" -ForegroundColor Red; $wbErrors++ }
        if ($wfCamFonte -match 'AccessControlSections\]::All') { Write-Host "  [ERRO] Permissões (caminhada): AccessControlSections::All lança sem SeSecurityPrivilege" -ForegroundColor Red; $wbErrors++ }
        if ($wfCamFonte -notmatch 'GetSecurityDescriptorSddlForm') { Write-Host "  [ERRO] Permissões (caminhada): o SDDL tem de sair de GetSecurityDescriptorSddlForm('Access')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (caminhada): junção auto-referente não é descida nem indexada, 1 entrada protegida, tetos devolvem lista vazia, caminho de $($wfCamLongo.Length) caracteres lido"
    } catch {
        Write-Host "  [ERRO] Permissões (caminhada): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        try { cmd.exe /c rmdir "$wfCamRaiz\perfil\AppData\Local\Dados de Aplicativos" 2>$null | Out-Null } catch { }
        Remove-Item -LiteralPath $wfCamRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Permissões (caminhada): O termo 'Get-WinForgeAclContentScope' não é reconhecido como nome de cmdlet…` e `== SelfTest concluído: 1 erro(s) ==`.

- [ ] **Step 3: Implementar** — `Get-WinForgeAclContentScope` em `wf-repair.ps1`, com a pilha explícita (nada de recursão e nada de `AllDirectories`). O trecho que decide o desenho:

  ```powershell
  param(
      [Parameter(Mandatory)][string]$Path,
      [switch]$IncludeFiles,
      [int]$MaxItems = 20000,
      [int]$MaxBytes = 4194304,
      [int]$MaxDepth = 32,
      [int]$MaxSeconds = 90
  )

  $frase = 'A cópia das permissões não ficou pronta em {0} segundos. Sem ela não haveria como desfazer, então nada foi alterado. Tente de novo com o computador recém-ligado.'
  $r = @{ Ok = $false; Reason = ''; Entries = @(); Scanned = 0; Reparse = 0; Denied = 0; DeniedPaths = @(); Deny = 0; Bytes = 0; Seconds = 0.0 }
  $base = [string](Split-Path -Parent ([string]$Path))          # a pasta ACIMA: os nomes são relativos a ela
  $longo = { param($p) if ($p -like '\\?\*') { $p } else { '\\?\' + $p } }
  $pilha = New-Object System.Collections.Generic.Stack[object]
  $pilha.Push(@{ Path = [string]$Path; Depth = 0 })
  $relogio = [System.Diagnostics.Stopwatch]::StartNew()
  $itens = New-Object System.Collections.Generic.List[object]
  $bytes = 0
  while ($pilha.Count -gt 0) {
      if ($relogio.Elapsed.TotalSeconds -gt $MaxSeconds) { $r.Reason = ($frase -f $MaxSeconds); return $r }
      $no = $pilha.Pop()
      # GetAttributes ANTES de empilhar, e sobre o caminho longo: é a única pergunta que separa
      # pasta de ponto de reanálise sem abrir o item. Ele NÃO entra em Denied: medido, em pasta
      # negada ele não lança, e contá-lo daria zero justo onde há problema.
      $attr = $null
      try { $attr = [IO.File]::GetAttributes((& $longo $no.Path)) } catch { $attr = $null }
      # O ponto de reanálise conta em Reparse e NÃO em Scanned: são duas grandezas diferentes, e o
      # teste cobra as duas por número exato. 'Scanned' só sobe para pasta que a caminhada de fato
      # visitou.
      if ($null -ne $attr -and ($attr -band [IO.FileAttributes]::ReparsePoint)) { $r.Reparse++; continue }
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
          if ($sddl -match '\(D;') { $r.Deny++ }
          $nome = [string]$no.Path
          if ($nome.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { $nome = $nome.Substring($base.TrimEnd('\').Length + 1) }
          $itens.Add(@{ Name = $nome; Sddl = $sddl })
          $bytes += [System.Text.Encoding]::Unicode.GetByteCount($nome + $sddl) + 8
          if ($itens.Count -gt $MaxItems) { $r.Reason = "A cópia das permissões passou de $MaxItems pastas. Nada foi alterado."; return $r }
          if ($bytes -gt $MaxBytes) { $r.Reason = "A cópia das permissões passou de $MaxBytes bytes. Nada foi alterado."; return $r }
      }
      if ($no.Depth -ge $MaxDepth) { $r.Reason = "A cópia das permissões passou de $MaxDepth níveis de pasta. Nada foi alterado."; return $r }
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
  ```
  Comentário obrigatório na função, com as quatro medições: `/L` não poda travessia; `AllDirectories` proibido; `\\?\` porque `LongPathsEnabled` não é padrão; `AccessControlSections::All` lança sem `SeSecurityPrivilege`.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Permissões (caminhada): junção auto-referente não é descida nem indexada, 1 entrada protegida, tetos devolvem lista vazia, caminho de 294 caracteres lido` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: trocar `continue` do ramo `ReparsePoint` por `$pilha.Push(@{ Path = $no.Path; Depth = $no.Depth + 1 })` e ver `Scanned=$($wfCamR.Scanned), esperado exatamente 4` ficar vermelho (a caminhada volta a descer na junção); desfazer e confirmar o verde. Esta é a mutação que a versão anterior do teste deixava passar: com `-lt 3` e `-ge 1`, contar o reparse **e** empilhá-lo ficava verde.

- [ ] **Step 5: Commit**
  `fix(repair): caminhada em pilha para o escopo das permissões, sem seguir ponto de reanálise`

---

### Task 2: O arquivo de conteúdo, a impressão digital e a contagem por fluxo

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — `Write-WinForgeAclContentBackup` e `Get-WinForgeAclContentHash` novas, logo depois de `Get-WinForgeAclContentScope`; `Measure-WinForgeAclSaveEntry` (`wf-repair.ps1:2242-2265`) reescrita para ler por fluxo.
- Test: `src/Engine/build.ps1`, no mesmo bloco da Tarefa 1, logo abaixo dele.

**Interfaces:**
- Consumes: `Get-WinForgeAclContentScope … → @{ Ok; Entries = @(@{ Name; Sddl }); … }` (Tarefa 1).
- Produces:
  ```powershell
  Write-WinForgeAclContentBackup -Path <string> -Entries <object[]>
    → @{ Ok = <bool>; Reason = <string>; Count = <int>; Bytes = <long> }
  Get-WinForgeAclContentHash -Path <string> → @{ Ok = <bool>; Reason = <string>; Hash = <string> }
  Measure-WinForgeAclSaveEntry -Path <string> → <int>
  ```
  `Write-WinForgeAclContentBackup` é o **único** ponto que grava o arquivo de conteúdo e chama `Assert-WinForgeNotSelfTest`. Formato medido no arquivo real do `icacls /save`: pares `<nome relativo>CRLF<SDDL>CRLF`, **UTF-16LE sem BOM** (`New-Object System.Text.UnicodeEncoding($false, $false)`). `Get-WinForgeAclContentHash` abre com `FileShare.Read` e devolve SHA-256 em maiúsculas.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Permissões: o arquivo e a ida e volta
    # É o único ponto do desenho sem prova: gravar, restaurar pelo icacls, reler e comparar.
    # Roda em %TEMP%, sem elevação: nem a DACL nem a posse de uma pasta cuja dona é a própria
    # identidade precisam dela.
    $wfArqRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-arquivo'
    try {
        if (Test-Path -LiteralPath $wfArqRaiz) { Remove-Item -LiteralPath $wfArqRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        $wfArqPerfil = Join-Path $wfArqRaiz 'perfil'
        $wfArqAlvo = Join-Path $wfArqPerfil 'Protegida'
        New-Item -ItemType Directory -Path $wfArqAlvo -Force | Out-Null
        $wfArqDir = New-Object System.IO.DirectoryInfo $wfArqAlvo
        $wfArqSd = $wfArqDir.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $wfArqSd.SetAccessRuleProtection($true, $true)
        $wfArqDir.SetAccessControl($wfArqSd)
        $wfArqEscopo = Get-WinForgeAclContentScope -Path $wfArqPerfil
        if (-not $wfArqEscopo.Ok -or @($wfArqEscopo.Entries).Count -lt 1) { throw "o escopo de teste saiu vazio ($($wfArqEscopo.Reason))" }
        $wfArqSddlAntes = [string]@($wfArqEscopo.Entries)[0].Sddl

        $wfArqArquivo = Join-Path $wfArqRaiz 'conteudo.txt'
        $wfArqGrav = Write-WinForgeAclContentBackup -Path $wfArqArquivo -Entries @($wfArqEscopo.Entries)
        if (-not $wfArqGrav.Ok) { throw "a gravação falhou: $($wfArqGrav.Reason)" }
        # UTF-16LE SEM BOM, pares de linhas. Com BOM, o icacls /restore recusa o arquivo. Cobrar só a
        # AUSÊNCIA de 'FF FE' deixaria passar UTF-8, ASCII e arquivo vazio - por isso o teste afirma
        # o encoding: o primeiro nome é 'perfil\Protegida', então os dois primeiros bytes têm de ser
        # 0x70 ('p') e 0x00 (o byte alto do UTF-16LE).
        $wfArqBytes = [System.IO.File]::ReadAllBytes($wfArqArquivo)
        if ($wfArqBytes.Length -lt 4) { Write-Host "  [ERRO] Permissões (arquivo): o arquivo saiu com $($wfArqBytes.Length) byte(s)" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfArqBytes[0] -eq 0xFF -and $wfArqBytes[1] -eq 0xFE) { Write-Host "  [ERRO] Permissões (arquivo): o arquivo saiu COM BOM - o formato medido é UTF-16LE sem BOM" -ForegroundColor Red; $wbErrors++ }
        elseif ($wfArqBytes[0] -ne 0x70 -or $wfArqBytes[1] -ne 0x00) { Write-Host "  [ERRO] Permissões (arquivo): os dois primeiros bytes são $('0x{0:X2} 0x{1:X2}' -f $wfArqBytes[0], $wfArqBytes[1]), esperado 0x70 0x00 - isto não é UTF-16LE" -ForegroundColor Red; $wbErrors++ }
        $wfArqLinhas = @([System.IO.File]::ReadAllText($wfArqArquivo, [System.Text.Encoding]::Unicode) -split "`r`n" | Where-Object { $_ -ne '' })
        if ($wfArqLinhas.Count -ne (2 * @($wfArqEscopo.Entries).Count)) { Write-Host "  [ERRO] Permissões (arquivo): $($wfArqLinhas.Count) linha(s) úteis para $(@($wfArqEscopo.Entries).Count) entrada(s) - o formato é um par por entrada" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfArqLinhas[0] -ne 'perfil\Protegida') { Write-Host "  [ERRO] Permissões (arquivo): a primeira linha é '$($wfArqLinhas[0])', esperado o nome relativo 'perfil\Protegida'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfArqLinhas[1] -ne $wfArqSddlAntes) { Write-Host "  [ERRO] Permissões (arquivo): o SDDL gravado difere do lido" -ForegroundColor Red; $wbErrors++ }
        if ((Measure-WinForgeAclSaveEntry -Path $wfArqArquivo) -ne @($wfArqEscopo.Entries).Count) { Write-Host "  [ERRO] Permissões (arquivo): a contagem de entradas não bate" -ForegroundColor Red; $wbErrors++ }

        # IDA E VOLTA: altera a DACL, restaura pelo icacls e compara o SDDL com o de antes.
        $wfArqSd2 = $wfArqDir.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $wfArqSd2.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule ([System.Security.Principal.WindowsIdentity]::GetCurrent().User), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        $wfArqSd2.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-545'), 'Read', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        $wfArqDir.SetAccessControl($wfArqSd2)
        $wfArqIcacls = Get-WinForgeSystemExe -Name 'icacls.exe'
        $wfArqRes = Invoke-WinForgeNativeCommand -FilePath $wfArqIcacls -Arguments @($wfArqRaiz, '/restore', $wfArqArquivo, '/C', '/L') -Encoding 'oem'
        if ([int]$wfArqRes.ExitCode -ne 0) { Write-Host "  [ERRO] Permissões (ida e volta): o /restore terminou com código $($wfArqRes.ExitCode): $(([string]$wfArqRes.Text).Trim())" -ForegroundColor Red; $wbErrors++ }
        $wfArqDepois = Get-WinForgeAclContentScope -Path $wfArqPerfil
        $wfArqSddlDepois = [string]@($wfArqDepois.Entries)[0].Sddl
        if ($wfArqSddlDepois -ne $wfArqSddlAntes) { Write-Host "  [ERRO] Permissões (ida e volta): o SDDL não voltou ao original`n    antes : $wfArqSddlAntes`n    depois: $wfArqSddlDepois" -ForegroundColor Red; $wbErrors++ }

        # SHA-256: um byte muda e a impressão digital muda.
        $wfArqH1 = Get-WinForgeAclContentHash -Path $wfArqArquivo
        if (-not $wfArqH1.Ok -or [string]$wfArqH1.Hash.Length -ne 64) { Write-Host "  [ERRO] Permissões (SHA-256): '$($wfArqH1.Hash)' ($($wfArqH1.Reason))" -ForegroundColor Red; $wbErrors++ }
        Add-Content -LiteralPath $wfArqArquivo -Value ' ' -Encoding Unicode
        $wfArqH2 = Get-WinForgeAclContentHash -Path $wfArqArquivo
        if ([string]$wfArqH2.Hash -eq [string]$wfArqH1.Hash) { Write-Host "  [ERRO] Permissões (SHA-256): a impressão digital não mudou com o arquivo alterado" -ForegroundColor Red; $wbErrors++ }
        # E a gravação recusa em modo SelfTest - é o único ponto que escreve.
        $wfArqFonteW = [string](Get-Command Write-WinForgeAclContentBackup).ScriptBlock
        if ($wfArqFonteW -notmatch 'Assert-WinForgeNotSelfTest') { Write-Host "  [ERRO] Permissões (arquivo): Write-WinForgeAclContentBackup sem a trava de SelfTest" -ForegroundColor Red; $wbErrors++ }
        # Measure-WinForgeAclSaveEntry lê por FLUXO: 'Get-Content' sem -Raw materializa um array e um
        # backup antigo grande vira OutOfMemoryException numa função que só conta linhas.
        $wfArqFonteM = [string](Get-Command Measure-WinForgeAclSaveEntry).ScriptBlock
        if ($wfArqFonteM -match 'Get-Content') { Write-Host "  [ERRO] Permissões (contagem): Measure-WinForgeAclSaveEntry ainda usa Get-Content - tem de ler por StreamReader" -ForegroundColor Red; $wbErrors++ }
        if ($wfArqFonteM -notmatch 'StreamReader') { Write-Host "  [ERRO] Permissões (contagem): Measure-WinForgeAclSaveEntry não usa StreamReader" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (arquivo): UTF-16LE sem BOM, $(@($wfArqEscopo.Entries).Count) par(es), ida e volta pelo icacls devolveu o SDDL original, SHA-256 sensível a um byte"
    } catch {
        Write-Host "  [ERRO] Permissões (arquivo): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfArqRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```
  Observação para quem implementa: a trava de SelfTest dentro de `Write-WinForgeAclContentBackup` faria este teste estourar. A gravação do teste roda por `Write-WinForgeAclContentBackup` **com `$sync.SelfTest` momentaneamente desligado** — as três linhas `$wfArqSelfAntes = $sync.SelfTest; $sync.SelfTest = $false; … ; $sync.SelfTest = $wfArqSelfAntes` envolvem só a chamada de gravação, dentro do `try`, e o `finally` as devolve. É o mesmo recurso já usado em `build.ps1:3237-3242`.

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Permissões (arquivo): O termo 'Write-WinForgeAclContentBackup' não é reconhecido…`.

- [ ] **Step 3: Implementar** — as duas funções novas e a reescrita da contagem. O trecho que decide o desenho:

  ```powershell
  # UnicodeEncoding($false, $false): UTF-16LE, sem BOM e sem detecção. É o formato medido no
  # arquivo que o 'icacls /save' escreve, e é o que o '/restore' aceita - com BOM ele recusa.
  $enc = New-Object System.Text.UnicodeEncoding($false, $false)
  $escritor = New-Object System.IO.StreamWriter($Path, $false, $enc)
  try {
      foreach ($e in @($Entries)) {
          $escritor.Write([string]$e.Name); $escritor.Write("`r`n")
          $escritor.Write([string]$e.Sddl); $escritor.Write("`r`n")
      }
  } finally { $escritor.Dispose() }
  ```
  ```powershell
  # Por FLUXO: o arquivo pode ter centenas de MB (um backup antigo da 1.7.0), e materializar as
  # linhas num array para contar duas letras é OutOfMemoryException garantida.
  $leitor = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::Unicode, $false)
  try {
      $n = 0
      while ($null -ne ($linha = $leitor.ReadLine())) {
          $t = ([string]$linha).Trim()
          if ($t.StartsWith('D:', [StringComparison]::Ordinal) -or $t.StartsWith('O:', [StringComparison]::Ordinal)) { $n++ }
      }
      return $n
  } finally { $leitor.Dispose() }
  ```

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Permissões (arquivo): UTF-16LE sem BOM, 1 par(es), ida e volta pelo icacls devolveu o SDDL original, SHA-256 sensível a um byte` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: trocar `UnicodeEncoding($false, $false)` por `([System.Text.Encoding]::Unicode)` (que tem BOM) e ver "o arquivo saiu COM BOM" ficar vermelho; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `feat(repair): arquivo de backup de permissões escrito pelo motor, com SHA-256 e contagem por fluxo`

---

### Task 3: Fase 2 — o backup passa a ser a caminhada (par com a Tarefa 4)

> **Não se solta esta tarefa sem a Tarefa 4.** A Fase 2 e a Fase 5 são inseparáveis quanto a ESCOPO: o que é guardado tem de ser o que é aplicado. Com a Tarefa 3 sozinha no repositório, a Fase 5 ainda roda `/inheritance:e /T` sobre o perfil inteiro e o Desfazer cobriria só as 338 pastas protegidas — pior do que hoje. Nada de PR, tag ou release entre as duas; a Tarefa 4 vem no commit seguinte.

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — `Get-WinForgeAclRestorePlan` (passo `Kind = 'save'` da fase 2, `wf-repair.ps1:2404-2432`) e `Invoke-WinForgeAclRestore` (laço da fase 2, `wf-repair.ps1:2748-2820`).
- Test: `src/Engine/build.ps1`, no bloco de permissões, abaixo do da Tarefa 2.

**Interfaces:**
- Consumes: `Get-WinForgeAclContentScope -Path <string> → @{ Ok; Reason; Entries; Denied; DeniedPaths; Deny; … }` (Tarefa 1); `Write-WinForgeAclContentBackup -Path <string> -Entries <object[]> → @{ Ok; Reason; Count; Bytes }` e `Get-WinForgeAclContentHash -Path <string> → @{ Ok; Reason; Hash }` (Tarefa 2).
- Produces:
  - Passo de plano `@{ Phase = 2; Kind = 'scope'; Title; Path; Backup; Target }` — **sem `FilePath` e sem `Arguments`**: quem executa é o motor, não o `icacls`. O passo `Kind = 'save'` some do plano.
  - `Test-WinForgeAclFreeSpace -Path <string> -Bytes <long> → @{ Ok = <bool>; Reason = <string>; Free = <long> }` — espaço conferido ANTES de gravar.
  - `Get-WinForgeAclScopeVerdict -Scope <object> → @{ Header = <string>; Text = <string> }` — função pura; `Denied > 0` devolve `Concluído com ressalvas`, a contagem e as **20 primeiras** de `DeniedPaths`.
  - Item de índice de conteúdo, consumido pela Tarefa 4 e pelo Desfazer: `@{ Path; Sddl = ''; Owner = ''; OwnerSid = ''; File = <nome do arquivo>; Target = <pasta acima do perfil>; Sha256 = <string>; ExternalPath = '' }`.
  - `$sync.WinForgeAclDenied = @{ Count = <int>; Paths = @(<string>) }` — lido pelo cabeçalho de veredito.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Permissões: a fase 2 no plano
    try {
        $wfF2Plano = @(Get-WinForgeAclRestorePlan -Profile 'C:\Users\fulano' -UserSid 'S-1-5-21-1-2-3-1001' -BackupRoot (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-plano') -Stamp '20260912-101010')
        $wfF2Save = @($wfF2Plano | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'save' })
        if ($wfF2Save.Count) { Write-Host "  [ERRO] Permissões (fase 2): o passo 'save' com 'icacls /T' continua no plano - ele é o laço que encheu o disco" -ForegroundColor Red; $wbErrors++ }
        $wfF2Escopo = @($wfF2Plano | Where-Object { [int]$_.Phase -eq 2 -and [string]$_.Kind -eq 'scope' })
        if ($wfF2Escopo.Count -ne 1) { Write-Host "  [ERRO] Permissões (fase 2): esperava 1 passo 'scope', veio $($wfF2Escopo.Count)" -ForegroundColor Red; $wbErrors++ }
        else {
            if ($wfF2Escopo[0].FilePath) { Write-Host "  [ERRO] Permissões (fase 2): o passo 'scope' não pode ter executável - quem caminha é o motor" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfF2Escopo[0].Target -ne 'C:\Users') { Write-Host "  [ERRO] Permissões (fase 2): Target='$($wfF2Escopo[0].Target)', esperado 'C:\Users' (a pasta de onde o /restore roda)" -ForegroundColor Red; $wbErrors++ }
        }
        # Nenhum passo do plano inteiro pode carregar '/T' sobre o perfil.
        foreach ($wfF2P in $wfF2Plano) {
            $wfF2Args = @($wfF2P.Arguments | ForEach-Object { [string]$_ })
            if (($wfF2Args -contains '/T') -and ((@($wfF2Args) -join ' ') -like '*C:\Users\fulano*')) { Write-Host "  [ERRO] Permissões (plano): passo da fase $($wfF2P.Phase) ainda usa '/T' sobre a pasta de perfil ('$($wfF2Args -join ' ')')" -ForegroundColor Red; $wbErrors++ }
        }
        # Espaço livre conferido ANTES: pedir mais do que o disco tem recusa, e diz quanto há.
        $wfF2Esp = Test-WinForgeAclFreeSpace -Path $wbSelfTestTemp -Bytes ([long]1PB)
        if ($wfF2Esp.Ok) { Write-Host "  [ERRO] Permissões (espaço): 1 PB deveria ser recusado" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Esp.Reason -notmatch '\d') { Write-Host "  [ERRO] Permissões (espaço): a recusa não traz o número na tela ('$($wfF2Esp.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeAclFreeSpace -Path $wbSelfTestTemp -Bytes 103400).Ok) { Write-Host "  [ERRO] Permissões (espaço): 103,4 KB foram recusados" -ForegroundColor Red; $wbErrors++ }
        # 'Denied > 0' muda o VEREDITO: cabeçalho, contagem e as 20 primeiras pastas.
        $wfF2Ver = Get-WinForgeAclScopeVerdict -Scope @{ Ok = $true; Denied = 3; DeniedPaths = @('C:\Users\fulano\A', 'C:\Users\fulano\B', 'C:\Users\fulano\C'); Entries = @(1, 2) }
        if ([string]$wfF2Ver.Header -ne 'Concluído com ressalvas') { Write-Host "  [ERRO] Permissões (ressalvas): cabeçalho '$($wfF2Ver.Header)', esperado 'Concluído com ressalvas'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Ver.Text -notmatch 'não foram copiadas nem alteradas') { Write-Host "  [ERRO] Permissões (ressalvas): falta a frase de que essas pastas não foram copiadas nem alteradas" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF2Ver.Text -notmatch 'C:\\Users\\fulano\\A') { Write-Host "  [ERRO] Permissões (ressalvas): a lista de DeniedPaths não aparece no texto" -ForegroundColor Red; $wbErrors++ }
        $wfF2Muitas = Get-WinForgeAclScopeVerdict -Scope @{ Ok = $true; Denied = 50; DeniedPaths = @(1..50 | ForEach-Object { "C:\p$_" }); Entries = @(1) }
        if (@([regex]::Matches([string]$wfF2Muitas.Text, 'C:\\p\d+')).Count -ne 20) { Write-Host "  [ERRO] Permissões (ressalvas): o texto tem de listar as 20 PRIMEIRAS, veio $(@([regex]::Matches([string]$wfF2Muitas.Text, 'C:\\p\d+')).Count)" -ForegroundColor Red; $wbErrors++ }
        $wfF2Limpo = Get-WinForgeAclScopeVerdict -Scope @{ Ok = $true; Denied = 0; DeniedPaths = @(); Entries = @(1) }
        if ([string]$wfF2Limpo.Header -ne 'Concluído') { Write-Host "  [ERRO] Permissões (ressalvas): sem Denied o cabeçalho é 'Concluído', veio '$($wfF2Limpo.Header)'" -ForegroundColor Red; $wbErrors++ }
        # O arquivo parcial some no 'finally', e não dentro do laço: hoje o descarte não roda se o
        # processo morre no meio.
        $wfF2Fonte = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if ($wfF2Fonte -notmatch '(?s)finally\s*\{[^}]*Remove-Item[^}]*parcial') { Write-Host "  [ERRO] Permissões (parcial): falta o 'finally' que apaga o arquivo de conteúdo pela metade" -ForegroundColor Red; $wbErrors++ }
        if ($wfF2Fonte -notmatch 'Get-WinForgeAclContentScope') { Write-Host "  [ERRO] Permissões (fase 2): Invoke-WinForgeAclRestore não usa a caminhada" -ForegroundColor Red; $wbErrors++ }
        if ($wfF2Fonte -notmatch 'Get-WinForgeAclContentHash') { Write-Host "  [ERRO] Permissões (fase 2): o índice não recebe o SHA-256 do arquivo de conteúdo" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (fase 2): passo 'scope' sem icacls, nenhum '/T' sobre o perfil, espaço conferido antes, veredito com ressalvas e finally do parcial"
    } catch {
        Write-Host "  [ERRO] Permissões (fase 2): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Permissões (fase 2): o passo 'save' com 'icacls /T' continua no plano - ele é o laço que encheu o disco` e `[ERRO] Permissões (fase 2): O termo 'Test-WinForgeAclFreeSpace' não é reconhecido…`.

- [ ] **Step 3: Implementar**
  - No plano, o passo do perfil vira:
    ```powershell
    $plano += @{
        Phase  = 2
        Kind   = 'scope'
        Title  = "Backup das permissões do conteúdo de '$($alvo.Path)'"
        Path   = [string]$alvo.Path
        Backup = $arquivo
        # A pasta de onde o '/restore' roda: o nome de cada entrada é relativo a ela.
        Target = [string](Split-Path -Parent ([string]$alvo.Path))
    }
    ```
    O passo `Kind = 'save'` (com `'/save', $arquivo, '/T', '/L', '/C', '/Q'`) é removido, e o comentário de `wf-repair.ps1:2400-2406` e `:2561` — que afirmava que `/L` poda a travessia — é substituído pelo que foi medido: quem para a recursão é o limite de 63 saltos de reparse, e por isso `icacls … /T` não é utilizável sobre pasta de perfil.
  - Em `Invoke-WinForgeAclRestore`, o ramo `'scope'` da fase 2, na ordem: `Get-WinForgeAclContentScope` → teto estourado imprime `Reason` e **aborta a restauração inteira** (`Write-Error` + `return`, sem "continuar mesmo assim") → `Test-WinForgeAclFreeSpace` → `Write-WinForgeAclContentBackup` → `Protect-WinForgeSnapshotFile` → `Get-WinForgeAclContentHash` → item de índice com `Sha256`. O `$escopo` fica guardado em `$sync.WinForgeAclScope` para a Fase 5 da Tarefa 4 consumir, e `$sync.WinForgeAclDenied` guarda `Denied`/`DeniedPaths`.
  - `Get-WinForgeAclScopeVerdict -Scope <object> → @{ Header; Text }` nova, pura, no mesmo arquivo.
  - O `try` da fase 2 ganha `finally { if ($parcial -and (Test-Path -LiteralPath $parcial)) { Remove-Item -LiteralPath $parcial -Force -ErrorAction SilentlyContinue } }`.
  - Com `Deny > 0` na caminhada, essas entradas passam por `icacls /save` real (chamada por entrada, sem `/T`): ordem de ACE importa quando há negação. Com `Deny = 0` — o caso medido, 0 das 338 — nada disso roda.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Permissões (fase 2): passo 'scope' sem icacls, nenhum '/T' sobre o perfil, espaço conferido antes, veredito com ressalvas e finally do parcial` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `fix(repair): fase 2 guarda só pasta com herança bloqueada, sem icacls /T no perfil`

---

### Task 4: Fase 5 sem `/T` — uma chamada por entrada da mesma lista

> Fecha o par aberto na Tarefa 3. Sem ela o travamento só muda de lugar: sai da Fase 2 e vai para depois da Fase 4.

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — passo `Kind = 'inherit'` da fase 5 (`wf-repair.ps1:2563`) e o laço da fase 5 em `Invoke-WinForgeAclRestore` (`wf-repair.ps1:2925-2945`).
- Test: `src/Engine/build.ps1`, logo abaixo do bloco da Tarefa 3.

**Interfaces:**
- Consumes: `$sync.WinForgeAclScope` = saída de `Get-WinForgeAclContentScope` (Tarefa 3); passo de plano `@{ Phase = 5; Kind = 'inherit-list'; Folder }`.
- Produces:
  ```powershell
  Get-WinForgeAclInheritSteps -Root <string> -Entries <object[]>
    → @(@{ Path = <string>; FilePath = <caminho do icacls>; Arguments = @(<pasta>, '/inheritance:e', '/C', '/Q') })
  ```
  Função pura. A ordenação é **ordinal por `Name`**, que entrega pai antes de filho. `Root` é o `Target` do passo de escopo (a pasta acima do perfil); o caminho absoluto de cada passo é `Join-Path $Root $entrada.Name`.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Permissões: a fase 5 sem /T
    # Conserta de quebra um defeito da 1.7.0: '/inheritance:e /T /L' liga herança FORA do perfil,
    # no destino de cada junção e no OneDrive. Uma chamada por entrada da lista da fase 2 não sai
    # do conjunto que o backup cobre - e é isso que mantém "guardado = alterado".
    try {
        $wfF5Entradas = @(
            @{ Name = 'fulano\AppData\Local\Pacotes'; Sddl = 'D:P(A;;FA;;;SY)' },
            @{ Name = 'fulano'; Sddl = 'D:P(A;;FA;;;SY)' },
            @{ Name = 'fulano\AppData'; Sddl = 'D:P(A;;FA;;;SY)' }
        )
        $wfF5Passos = @(Get-WinForgeAclInheritSteps -Root 'C:\Users' -Entries $wfF5Entradas)
        if ($wfF5Passos.Count -ne 3) { Write-Host "  [ERRO] Permissões (fase 5): $($wfF5Passos.Count) passo(s) para 3 entradas" -ForegroundColor Red; $wbErrors++ }
        $wfF5Ordem = @($wfF5Passos | ForEach-Object { [string]$_.Path })
        if ([string]$wfF5Ordem[0] -ne 'C:\Users\fulano') { Write-Host "  [ERRO] Permissões (fase 5): a ordem ordinal tem de entregar o pai primeiro, veio '$($wfF5Ordem -join ' | ')'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF5Ordem[2] -ne 'C:\Users\fulano\AppData\Local\Pacotes') { Write-Host "  [ERRO] Permissões (fase 5): o filho mais fundo tem de vir por último, veio '$($wfF5Ordem -join ' | ')'" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfF5P in $wfF5Passos) {
            $wfF5A = @($wfF5P.Arguments | ForEach-Object { [string]$_ })
            if ($wfF5A -contains '/T') { Write-Host "  [ERRO] Permissões (fase 5): '/T' voltou ao vetor ('$($wfF5A -join ' ')')" -ForegroundColor Red; $wbErrors++ }
            if ($wfF5A -notcontains '/inheritance:e') { Write-Host "  [ERRO] Permissões (fase 5): falta '/inheritance:e' ('$($wfF5A -join ' ')')" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfF5P.FilePath -ne (Get-WinForgeSystemExe -Name 'icacls.exe')) { Write-Host "  [ERRO] Permissões (fase 5): o executável não é o icacls do System32 ('$($wfF5P.FilePath)')" -ForegroundColor Red; $wbErrors++ }
        }
        # O conjunto coberto é o conjunto alterado: mesma lista, mesma contagem.
        $wfF5Plano = @(Get-WinForgeAclRestorePlan -Profile 'C:\Users\fulano' -UserSid 'S-1-5-21-1-2-3-1001' -BackupRoot (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-plano') -Stamp '20260912-101010')
        $wfF5Velho = @($wfF5Plano | Where-Object { [int]$_.Phase -eq 5 -and [string]$_.Kind -eq 'inherit' })
        if ($wfF5Velho.Count) { Write-Host "  [ERRO] Permissões (fase 5): o passo 'inherit' com '/T' continua no plano" -ForegroundColor Red; $wbErrors++ }
        $wfF5Lista = @($wfF5Plano | Where-Object { [int]$_.Phase -eq 5 -and [string]$_.Kind -eq 'inherit-list' })
        if ($wfF5Lista.Count -ne 1) { Write-Host "  [ERRO] Permissões (fase 5): esperava 1 passo 'inherit-list', veio $($wfF5Lista.Count)" -ForegroundColor Red; $wbErrors++ }
        $wfF5Fonte = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if ($wfF5Fonte -notmatch 'Get-WinForgeAclInheritSteps') { Write-Host "  [ERRO] Permissões (fase 5): a fase 5 não monta os passos a partir da lista da fase 2" -ForegroundColor Red; $wbErrors++ }
        if ($wfF5Fonte -notmatch 'WinForgeAclScope') { Write-Host "  [ERRO] Permissões (fase 5): a fase 5 não lê o escopo guardado pela fase 2 - guardado e alterado divergiriam" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (fase 5): $($wfF5Passos.Count) chamada(s) '/inheritance:e' por entrada, pai antes de filho, nenhum '/T'"
    } catch {
        Write-Host "  [ERRO] Permissões (fase 5): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Permissões (fase 5): O termo 'Get-WinForgeAclInheritSteps' não é reconhecido…` e `[ERRO] Permissões (fase 5): o passo 'inherit' com '/T' continua no plano`.

- [ ] **Step 3: Implementar** — `Get-WinForgeAclInheritSteps` nova; no plano, `Kind = 'inherit'` vira `Kind = 'inherit-list'` sem `FilePath`/`Arguments`; na condução, o ramo `'inherit-list'` monta os passos com o escopo da fase 2 e os roda em sequência. O trecho que decide o desenho:

  ```powershell
  # Ordinal, e não cultural: 'AppData' < 'AppData\Local' byte a byte, e é isso que entrega pai
  # antes de filho sem contar separadores. Ligar a herança no filho antes do pai não propaga o que
  # o pai ainda não tem.
  $ordenadas = @($Entries | Sort-Object -Property @{ Expression = { [string]$_.Name } } -Culture ([System.Globalization.CultureInfo]::InvariantCulture))
  ```
  Os textos de §1.7 entram junto: o "Perde-se, escrito" ganha a linha do OneDrive em Sob Demanda ficar fora do backup **e** fora da Fase 5 ("o par é consistente") e as pastas de `Denied`.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Permissões (fase 5): 3 chamada(s) '/inheritance:e' por entrada, pai antes de filho, nenhum '/T'` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: acrescentar `'/T'` ao vetor de `Get-WinForgeAclInheritSteps` e ver "'/T' voltou ao vetor" ficar vermelho; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `fix(repair): fase 5 liga herança por entrada da lista guardada, sem /T e sem sair do perfil`

---

### Task 5: Um índice por vez, e desta máquina (par com a Tarefa 6)

> **Não se solta esta tarefa sem a Tarefa 6.** A recusa que esta tarefa cria manda o usuário "usar Desfazer ou Limpar backups antigos", e o botão `Limpar backups antigos` só nasce na Tarefa 6. Pior: o índice de uma 1.7.0 instalada não tem o campo `Consumed`, entra como **pendente** e faz recusar toda restauração nova. Com a Tarefa 5 sozinha no repositório, o botão das permissões fica pior do que está hoje — o que a constraint global proíbe. A Tarefa 6 vem no commit seguinte; nada de PR, tag ou release entre as duas.

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — `Get-WinForgeAclBackupSet` (`wf-repair.ps1:3021-3078`), `Invoke-WinForgeAclUndo` (`wf-repair.ps1:3079-3232`), `Invoke-WinForgeAclRestore` (recusa antes de tudo) e **cinco** funções novas.
- Test: `src/Engine/build.ps1`, bloco de permissões, abaixo do da Tarefa 4.

**Interfaces:**
- Consumes: item de índice de conteúdo com `Sha256` (Tarefa 3).
- Produces:
  ```powershell
  New-WinForgeAclIndexOrigin → @{ MachineGuid = <string>; ProfileSid = <string> }
  Test-WinForgeAclIndexOrigin -Index <object> → @{ Ok = <bool>; Reason = <string> }
  Get-WinForgeAclIndexList -Root <string>
    → @(@{ Path; Stamp; Consumed = <bool>; Origin; Items = @(<object>) })   # ordenado por Stamp crescente
  Set-WinForgeAclIndexConsumed -Path <string> → @{ Ok = <bool>; Reason = <string> }
  Test-WinForgeAclRestoreAllowed -Root <string> → @{ Ok = <bool>; Reason = <string>; Pending = <int> }
  ```
  `Get-WinForgeAclBackupSet [-Root <string>] [-Trusted]` passa a devolver o **mais antigo não consumido** e ganha dois campos: `Pending = <int>` (quantos índices não consumidos existem) e `Consumed = <bool>`. O índice gravado na fase 2 passa a carregar `Consumed = $false` e `Origin = <saída de New-WinForgeAclIndexOrigin>`.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Permissões: um índice por vez
    # Defeito da 1.7.0, confirmado no código (:3044 e :2760-2769): o Desfazer lia o índice MAIS NOVO.
    # Na 2ª execução a fase 5 da 1ª já tinha removido a proteção de herança, o escopo caía para perto
    # de zero e o índice novo - que continua com os itens 'sddl' das fases 3 e 4 - virava o único
    # visível. As 338 originais ficavam irrecuperáveis.
    $wfIdxRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-indices'
    try {
        if (Test-Path -LiteralPath $wfIdxRaiz) { Remove-Item -LiteralPath $wfIdxRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfIdxRaiz -Force | Out-Null
        $wfIdxOrigem = New-WinForgeAclIndexOrigin
        if ([string]::IsNullOrWhiteSpace([string]$wfIdxOrigem.MachineGuid) -or [string]::IsNullOrWhiteSpace([string]$wfIdxOrigem.ProfileSid)) { Write-Host "  [ERRO] Permissões (origem): New-WinForgeAclIndexOrigin veio incompleta ('$($wfIdxOrigem.MachineGuid)' / '$($wfIdxOrigem.ProfileSid)')" -ForegroundColor Red; $wbErrors++ }
        $wfIdxGrava = {
            param($Nome, $Consumido, $Origem)
            $conteudo = [pscustomobject]@{
                Stamp = $Nome; Consumed = $Consumido; Origin = $Origem
                Items = @([pscustomobject]@{ Path = 'C:\Users\fulano'; Sddl = 'D:P(A;;FA;;;SY)'; Owner = 'SYSTEM'; OwnerSid = 'S-1-5-18'; File = ''; Target = ''; Sha256 = ''; ExternalPath = '' })
            }
            Set-Content -LiteralPath (Join-Path $wfIdxRaiz "acl-index-$Nome.json") -Value ($conteudo | ConvertTo-Json -Depth 5) -Encoding UTF8
        }
        & $wfIdxGrava '20260101-000000' $false $wfIdxOrigem
        & $wfIdxGrava '20260202-000000' $false $wfIdxOrigem
        $wfIdxLista = @(Get-WinForgeAclIndexList -Root $wfIdxRaiz)
        if ($wfIdxLista.Count -ne 2) { Write-Host "  [ERRO] Permissões (índices): a lista trouxe $($wfIdxLista.Count), esperado 2" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfIdxLista[0].Stamp -ne '20260101-000000') { Write-Host "  [ERRO] Permissões (índices): a lista não vem do mais antigo para o mais novo ('$($wfIdxLista[0].Stamp)')" -ForegroundColor Red; $wbErrors++ }
        $wfIdxConj = Get-WinForgeAclBackupSet -Root $wfIdxRaiz
        if ([string]$wfIdxConj.Stamp -ne '20260101-000000') { Write-Host "  [ERRO] Permissões (Desfazer): o conjunto escolhido é '$($wfIdxConj.Stamp)', esperado o MAIS ANTIGO não consumido '20260101-000000'" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfIdxConj.Pending -ne 2) { Write-Host "  [ERRO] Permissões (Desfazer): Pending=$($wfIdxConj.Pending), esperado 2" -ForegroundColor Red; $wbErrors++ }
        # Consumido some da fila; o seguinte assume.
        if (-not (Set-WinForgeAclIndexConsumed -Path (Join-Path $wfIdxRaiz 'acl-index-20260101-000000.json')).Ok) { Write-Host "  [ERRO] Permissões (Consumed): a marcação falhou" -ForegroundColor Red; $wbErrors++ }
        $wfIdxConj2 = Get-WinForgeAclBackupSet -Root $wfIdxRaiz
        if ([string]$wfIdxConj2.Stamp -ne '20260202-000000') { Write-Host "  [ERRO] Permissões (Consumed): depois de consumido o primeiro, o conjunto é '$($wfIdxConj2.Stamp)', esperado '20260202-000000'" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfIdxConj2.Pending -ne 1) { Write-Host "  [ERRO] Permissões (Consumed): Pending=$($wfIdxConj2.Pending), esperado 1" -ForegroundColor Red; $wbErrors++ }
        # Índice de OUTRA máquina é recusado: SDDL com SIDs alheios entra como SID cru e tranca o perfil.
        $wfIdxOutra = Test-WinForgeAclIndexOrigin -Index ([pscustomobject]@{ Origin = [pscustomobject]@{ MachineGuid = '00000000-0000-0000-0000-000000000000'; ProfileSid = [string]$wfIdxOrigem.ProfileSid } })
        if ($wfIdxOutra.Ok) { Write-Host "  [ERRO] Permissões (origem): MachineGuid trocado foi aceito" -ForegroundColor Red; $wbErrors++ }
        $wfIdxOutroSid = Test-WinForgeAclIndexOrigin -Index ([pscustomobject]@{ Origin = [pscustomobject]@{ MachineGuid = [string]$wfIdxOrigem.MachineGuid; ProfileSid = 'S-1-5-21-9-9-9-1001' } })
        if ($wfIdxOutroSid.Ok) { Write-Host "  [ERRO] Permissões (origem): SID de perfil trocado foi aceito" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeAclIndexOrigin -Index ([pscustomobject]@{ Origin = $wfIdxOrigem })).Ok) { Write-Host "  [ERRO] Permissões (origem): o índice desta máquina foi recusado" -ForegroundColor Red; $wbErrors++ }
        # Restauração NOVA é recusada enquanto houver índice não consumido, e diz o que fazer.
        $wfIdxProva = Test-WinForgeAclRestoreAllowed -Root $wfIdxRaiz
        if ($wfIdxProva.Ok) { Write-Host "  [ERRO] Permissões (segunda execução): com 1 índice não consumido a restauração foi permitida - é o defeito que destrói o backup bom" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfIdxProva.Reason -notmatch 'Limpar backups antigos') { Write-Host "  [ERRO] Permissões (segunda execução): a recusa não manda usar Desfazer ou 'Limpar backups antigos' ('$($wfIdxProva.Reason)')" -ForegroundColor Red; $wbErrors++ }
        $null = Set-WinForgeAclIndexConsumed -Path (Join-Path $wfIdxRaiz 'acl-index-20260202-000000.json')
        if (-not (Test-WinForgeAclRestoreAllowed -Root $wfIdxRaiz).Ok) { Write-Host "  [ERRO] Permissões (segunda execução): com todos consumidos a restauração continua recusada" -ForegroundColor Red; $wbErrors++ }
        # E a restauração CHAMA a guarda: exercer Test-WinForgeAclRestoreAllowed solto prova que ela
        # sabe responder, não que alguém pergunta. Implementá-la e nunca invocá-la deixaria o defeito
        # que destrói o backup bom inteiro, com o teste verde.
        $wfIdxFonteR = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if ($wfIdxFonteR -notmatch 'Test-WinForgeAclRestoreAllowed') { Write-Host "  [ERRO] Permissões (segunda execução): Invoke-WinForgeAclRestore não chama Test-WinForgeAclRestoreAllowed - a guarda existe e ninguém pergunta a ela" -ForegroundColor Red; $wbErrors++ }
        $wfIdxPosGuarda = $wfIdxFonteR.IndexOf('Test-WinForgeAclRestoreAllowed', [StringComparison]::Ordinal)
        $wfIdxPosEscopo = $wfIdxFonteR.IndexOf('Get-WinForgeAclContentScope', [StringComparison]::Ordinal)
        if ($wfIdxPosGuarda -lt 0 -or $wfIdxPosEscopo -lt 0 -or $wfIdxPosGuarda -gt $wfIdxPosEscopo) { Write-Host "  [ERRO] Permissões (segunda execução): a guarda é conferida DEPOIS da caminhada - a recusa tem de vir antes de qualquer trabalho" -ForegroundColor Red; $wbErrors++ }
        # Toda recusa do Desfazer termina com a frase de §1.7.
        $wfIdxFonteU = [string](Get-Command Invoke-WinForgeAclUndo).ScriptBlock
        if ($wfIdxFonteU -notmatch 'coloque-a de volta em') { Write-Host "  [ERRO] Permissões (Desfazer): falta a frase 'Nada foi alterado. Se tiver uma cópia do arquivo original…'" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -notmatch 'Set-WinForgeAclIndexConsumed') { Write-Host "  [ERRO] Permissões (Desfazer): um Desfazer bem-sucedido não marca o índice como consumido" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -notmatch 'Test-WinForgeAclIndexOrigin') { Write-Host "  [ERRO] Permissões (Desfazer): a origem do índice não é conferida" -ForegroundColor Red; $wbErrors++ }
        if ($wfIdxFonteU -notmatch 'Get-WinForgeAclContentHash') { Write-Host "  [ERRO] Permissões (Desfazer): o SHA-256 do arquivo de conteúdo não é recalculado" -ForegroundColor Red; $wbErrors++ }
        # Ancorado no INDEXADOR, e não em 'Count - 1': essa string casa com qualquer comentário que
        # explique o defeito antigo, e o teste ficaria vermelho justamente na implementação correta.
        if ($wfIdxFonteU -match '\$indices\[\s*\$indices\.Count\s*-\s*1\s*\]') { Write-Host "  [ERRO] Permissões (Desfazer): ainda existe a escolha pelo índice mais novo (`$indices[`$indices.Count-1])" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (índices): Desfazer no mais antigo não consumido, Consumed avança a fila, origem por MachineGuid+SID, restauração recusada com pendente"
    } catch {
        Write-Host "  [ERRO] Permissões (índices): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfIdxRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Permissões (índices): O termo 'New-WinForgeAclIndexOrigin' não é reconhecido…`.

- [ ] **Step 3: Implementar** — as cinco funções novas: `New-WinForgeAclIndexOrigin`, `Test-WinForgeAclIndexOrigin`, `Get-WinForgeAclIndexList`, `Set-WinForgeAclIndexConsumed` e `Test-WinForgeAclRestoreAllowed`. Um índice da 1.7.0 **não tem** o campo `Consumed`: ausente conta como `$false`, isto é, **pendente**, e é o certo — ele é mesmo um backup que ninguém desfez. A consequência é que, entre esta tarefa e a 6, a restauração fica recusada numa máquina que tenha rodado a 1.7.0, e é por isso que as duas andam juntas. O trecho que decide o desenho:

  ```powershell
  # MachineGuid do registro (HKLM\SOFTWARE\Microsoft\Cryptography) e o SID do perfil ATUAL. O
  # SHA-256 protege o arquivo de CONTEÚDO contra alteração; ele não diz nada sobre a procedência do
  # ÍNDICE, e é o índice que carrega os SDDL das fases 3 e 4. Um índice de outra máquina aplica
  # SDDL com SIDs que não existem aqui: eles entram como SID cru e trancam o perfil.
  $guid = ''
  try { $guid = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid } catch { $guid = '' }
  $sid = [string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
  ```
  ```powershell
  # O MAIS ANTIGO não consumido, e não o mais novo. Na 2ª execução o índice novo tem escopo perto de
  # zero (a fase 5 da 1ª já tirou a proteção de herança) e '$gravados' continua > 0 porque os itens
  # 'sddl' das fases 3 e 4 entram sempre: ler o mais novo apaga o backup que interessa.
  $pendentes = @(Get-WinForgeAclIndexList -Root $dir | Where-Object { -not $_.Consumed })
  ```
  `Invoke-WinForgeAclRestore` chama `Test-WinForgeAclRestoreAllowed` logo depois da conferência de elevação, antes de criar pasta ou rodar o chkdsk. `Invoke-WinForgeAclUndo` confere `Test-WinForgeAclIndexOrigin` antes de qualquer SDDL virar argumento, confere `Sha256` de cada item de conteúdo (recusa própria; com o arquivo ausente em `ExternalPath`, diz qual disco ligar) e chama `Set-WinForgeAclIndexConsumed` **só** quando não houve recusa. Continuam como estão: recusa individual de item sem arquivo (`:3207-3216`) e a guarda de `$gravados -eq 0`.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Permissões (índices): Desfazer no mais antigo não consumido, Consumed avança a fila, origem por MachineGuid+SID, restauração recusada com pendente` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: trocar `Where-Object { -not $_.Consumed } | Select-Object -First 1` por `Select-Object -Last 1` e ver "o conjunto escolhido é '20260202-000000'" ficar vermelho; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `fix(repair): Desfazer lê o índice mais antigo não consumido e recusa índice de outra máquina`

---

### Task 6: `Permissões do disco C: — Limpar backups antigos` (Config 57 → 58)

> Fecha o par aberto na Tarefa 5: é este botão que a recusa de lá manda usar, e é a saída de quem matou a 1.7.0 na Fase 2 e ficou com centenas de GB numa pasta que só SYSTEM e Administradores apagam (spec §1.7). Ela consome `Get-WinForgeAclIndexList` e `New-WinForgeAclIndexOrigin` da Tarefa 5 — não dá para trocar a ordem das duas, só para não soltá-las separadas.

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — funções novas e linha `'AclCleanup'` em `Get-WinForgeRepairCommand` (junto de `'AclUndo'`, `wf-repair.ps1:334-343`).
- Modify: `src/Engine/config/wf-repair-config.ps1` — entrada `WPFWFRepAclCleanup`.
- Modify: `src/Engine/build.ps1` — caso `"WPFWFRepAclCleanup" {Invoke-WinForgeRepairCommand -Name AclCleanup}` no switch de `Invoke-WPFButton` (`build.ps1:812-826`); trava de Config `57` → `58` (`build.ps1:1157`); varredura de abertura junto do gancho de `Start-WinForgeProfileJob`.
- Test: `src/Engine/build.ps1`, bloco de permissões.

**Interfaces:**
- Consumes: `Get-WinForgeAclIndexList -Root <string> → @(@{ Path; Stamp; Consumed; Origin; Items })` (Tarefa 5).
- Produces:
  ```powershell
  Get-WinForgeAclBackupInventory -Root <string>
    → @(@{ Name; Path; Bytes; Date; Kind = 'indice'|'conteudo'; Orphan = <bool>; Consumed = <bool> })
  Get-WinForgeAclBackupSizeWarning -Root <string> -LimitBytes 1073741824 → @{ Over = <bool>; Bytes = <long>; Text = <string> }
  Invoke-WinForgeAclCleanup [-DryRun] [-Probe] [-BackupRoot <string>]
  ```
  `Invoke-WinForgeAclCleanup` é o passo único (`Steps = @(@{ Function = 'Invoke-WinForgeAclCleanup' })`) da linha `AclCleanup`, `Kind = 'repair'`, `Stream = $true`, com `Assert-WinForgeNotSelfTest`. Órfão = arquivo de conteúdo que nenhum índice referencia (nem por `File` nem por `ExternalPath`).

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Permissões: limpar backups antigos
    # A saída de quem matou a 1.7.0 na fase 2 e ficou com centenas de GB numa pasta que só SYSTEM e
    # Administradores apagam.
    $wfLimpRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-limpeza'
    try {
        if (Test-Path -LiteralPath $wfLimpRaiz) { Remove-Item -LiteralPath $wfLimpRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfLimpRaiz -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-perfil-fulano-20260101-000000.txt') -Value 'usado' -Encoding Unicode
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-perfil-fulano-19990101-000000.txt') -Value 'orfao' -Encoding Unicode
        Set-Content -LiteralPath (Join-Path $wfLimpRaiz 'acl-index-20260101-000000.json') -Value (([pscustomobject]@{
            Stamp = '20260101-000000'; Consumed = $false; Origin = (New-WinForgeAclIndexOrigin)
            Items = @([pscustomobject]@{ Path = 'C:\Users\fulano'; Sddl = ''; Owner = ''; OwnerSid = ''; File = 'acl-perfil-fulano-20260101-000000.txt'; Target = 'C:\Users'; Sha256 = ''; ExternalPath = '' })
        } | ConvertTo-Json -Depth 5)) -Encoding UTF8
        $wfLimpInv = @(Get-WinForgeAclBackupInventory -Root $wfLimpRaiz)
        if ($wfLimpInv.Count -ne 3) { Write-Host "  [ERRO] Permissões (limpeza): o inventário trouxe $($wfLimpInv.Count) item(ns), esperado 3" -ForegroundColor Red; $wbErrors++ }
        $wfLimpOrf = @($wfLimpInv | Where-Object { $_.Orphan })
        if ($wfLimpOrf.Count -ne 1) { Write-Host "  [ERRO] Permissões (limpeza): $($wfLimpOrf.Count) órfão(s), esperado 1" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfLimpOrf[0].Name -ne 'acl-perfil-fulano-19990101-000000.txt') { Write-Host "  [ERRO] Permissões (limpeza): o órfão apontado é '$($wfLimpOrf[0].Name)'" -ForegroundColor Red; $wbErrors++ }
        if (@($wfLimpInv | Where-Object { [string]$_.Name -eq 'acl-perfil-fulano-20260101-000000.txt' -and $_.Orphan }).Count) { Write-Host "  [ERRO] Permissões (limpeza): arquivo referenciado por índice foi marcado como órfão" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLimpI in $wfLimpInv) {
            if ([long]$wfLimpI.Bytes -le 0) { Write-Host "  [ERRO] Permissões (limpeza): '$($wfLimpI.Name)' sem tamanho" -ForegroundColor Red; $wbErrors++ }
            if ($null -eq $wfLimpI.Date) { Write-Host "  [ERRO] Permissões (limpeza): '$($wfLimpI.Name)' sem data" -ForegroundColor Red; $wbErrors++ }
        }
        $wfLimpSeco = @(Invoke-WinForgeAclCleanup -DryRun -BackupRoot $wfLimpRaiz)
        if (-not @($wfLimpSeco | Where-Object { [string]$_ -like '*[simulação]*' }).Count) { Write-Host "  [ERRO] Permissões (limpeza): -DryRun não devolveu linhas prefixadas com '[simulação] '" -ForegroundColor Red; $wbErrors++ }
        if (@($wfLimpSeco | Where-Object { [string]$_ -like '*20260101*' }).Count) { Write-Host "  [ERRO] Permissões (limpeza): a simulação apagaria um arquivo em uso" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-Path -LiteralPath (Join-Path $wfLimpRaiz 'acl-perfil-fulano-19990101-000000.txt'))) { Write-Host "  [ERRO] Permissões (limpeza): o -DryRun APAGOU arquivo" -ForegroundColor Red; $wbErrors++ }
        # Varredura de abertura: acima de 1 GB ela RELATA, e não apaga nada.
        $wfLimpAviso = Get-WinForgeAclBackupSizeWarning -Root $wfLimpRaiz -LimitBytes 1
        if (-not $wfLimpAviso.Over) { Write-Host "  [ERRO] Permissões (varredura): 1 byte de limite deveria disparar o aviso" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfLimpAviso.Text -notmatch 'Limpar backups antigos') { Write-Host "  [ERRO] Permissões (varredura): o aviso não aponta o botão ('$($wfLimpAviso.Text)')" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeAclBackupSizeWarning -Root $wfLimpRaiz -LimitBytes 1073741824).Over) { Write-Host "  [ERRO] Permissões (varredura): três arquivos minúsculos dispararam o aviso de 1 GB" -ForegroundColor Red; $wbErrors++ }
        $wfLimpFonteV = [string](Get-Command Get-WinForgeAclBackupSizeWarning).ScriptBlock
        if ($wfLimpFonteV -match 'Remove-Item') { Write-Host "  [ERRO] Permissões (varredura): a varredura de abertura SÓ RELATA - não pode apagar nada" -ForegroundColor Red; $wbErrors++ }
        # A linha nova existe, é 'repair' e recusa despacho sem ninguém para confirmar.
        $wfLimpCmd = Get-WinForgeRepairCommand -Name 'AclCleanup'
        if ([string]$wfLimpCmd.Kind -ne 'repair') { Write-Host "  [ERRO] Permissões (limpeza): a linha AclCleanup é '$($wfLimpCmd.Kind)', esperado 'repair'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfLimpCmd.Title -ne 'Permissões do disco C: — Limpar backups antigos') { Write-Host "  [ERRO] Permissões (limpeza): título '$($wfLimpCmd.Title)'" -ForegroundColor Red; $wbErrors++ }
        $wfLimpDesp = Invoke-WinForgeRepairCommand -Name 'AclCleanup' -NoUI
        if ($wfLimpDesp.Dispatched) { Write-Host "  [ERRO] Permissões (limpeza): a linha foi despachada no SelfTest" -ForegroundColor Red; $wbErrors++ }
        if ([string]::IsNullOrWhiteSpace([string]$sync.configs.feature.WPFWFRepAclCleanup.Description)) { Write-Host "  [ERRO] Permissões (limpeza): WPFWFRepAclCleanup sem Description na config" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (limpeza): inventário com tamanho e data, 1 órfão marcado, simulação não apaga, varredura de 1 GB só relata"
    } catch {
        Write-Host "  [ERRO] Permissões (limpeza): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfLimpRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1`
  - Esperado, já no build: `[ERRO] Config: esperado 58 entradas` não aparece ainda; o SelfTest acusa `[ERRO] Permissões (limpeza): O termo 'Get-WinForgeAclBackupInventory' não é reconhecido…` e `Comando de reparo desconhecido: 'AclCleanup'`.

- [ ] **Step 3: Implementar**
  - Entrada de config, texto literal do §6 (descrição com ≥ 40 caracteres, diferente do título, sem "Origem:"):
    ```json
    "WPFWFRepAclCleanup": {
      "Content": "Permissões do disco C: — Limpar backups antigos",
      "Description": "Lista os arquivos de backup de permissões guardados pelo WinForge com tamanho e data, marca os que nenhum índice usa e apaga só os marcados, sob confirmação.",
      "category": "WinForge - Reparo de componentes", "panel": "1", "Type": "Button", "ButtonWidth": "350"
    }
    ```
  - Trava de Config em `build.ps1:1157`: `-ne 57` → `-ne 58`, e a mensagem `esperado 57 entradas` → `esperado 58 entradas`.
  - A varredura de abertura entra no mesmo gancho de `Start-WinForgeProfileJob` (`build.ps1`, "restore prompt hook"), em `DispatcherPriority::Background`, e escreve no log e na barra de status — nunca em caixa de mensagem.
  - `Invoke-WinForgeAclCleanup` lista, pede confirmação com a lista na tela e apaga **só os marcados como órfãos**; índice consumido é oferecido para apagar junto do arquivo que ele referencia.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Entradas -> … | Config: 58 | …`, `Permissões (limpeza): inventário com tamanho e data, 1 órfão marcado, simulação não apaga, varredura de 1 GB só relata` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(repair): botão para limpar backups antigos de permissões e aviso de pasta acima de 1 GB`

---

### Task 7: Backup obrigatório, destino escolhível (D1)

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — `Test-WinForgeAclContentRoot` e `Show-WinForgeAclBackupDestination` novas; `Invoke-WinForgeAclRestore` (ramo `'scope'`) e `Invoke-WinForgeAclUndo` (item de conteúdo).
- Modify: `src/Engine/build.ps1` — o diálogo abre na thread da janela dentro de `Invoke-WinForgeRepairCommand` (`wf-repair.ps1:1370+`), antes do despacho; SelfTest.
- Test: `src/Engine/build.ps1`, bloco de permissões.

**Interfaces:**
- Consumes: item de índice com `File`, `Target`, `Sha256`, `ExternalPath` (Tarefa 3); `Get-WinForgeAclContentHash -Path <string> → @{ Ok; Reason; Hash }` (Tarefa 2).
- Produces:
  ```powershell
  Test-WinForgeAclContentRoot -Path <string> -ProfilePath <string> → @{ Ok = <bool>; Reason = <string>; Path = <string>; Warning = <string> }
  Show-WinForgeAclBackupDestination → @{ Ok = <bool>; External = <bool>; Path = <string>; Warning = <string> }
  ```
  `Show-WinForgeAclBackupDestination` roda **na thread da janela** (é chamada do handler do botão, antes do `Invoke-WPFRunspace`), com a caixa "Guardar o backup das permissões em outro disco" **desmarcada por padrão**; o caminho vem do `FolderBrowserDialog` (o processo nasce STA e o relançamento `-Verb RunAs` de `WinForge.ps1:83/85` preserva isso) e **nunca** de variável de ambiente. O resultado viaja para a runspace em `$sync.WinForgeAclExternalRoot`. O índice continua sempre em `%ProgramData%\WinForge\acl-backup`; **só o arquivo de conteúdo sai**.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Permissões: destino do conteúdo
    # O backup de conteúdo é OBRIGATÓRIO (103,4 KB: não há o que economizar). O que é opcional é o
    # DESTINO. As sete recusas abaixo existem porque o que sai desta pasta volta por um /restore
    # elevado sobre o perfil inteiro.
    $wfDestRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\acl-destino'
    try {
        if (Test-Path -LiteralPath $wfDestRaiz) { Remove-Item -LiteralPath $wfDestRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        $wfDestPerfil = Join-Path $wfDestRaiz 'perfil'
        $wfDestBom = Join-Path $wfDestRaiz 'destino'
        New-Item -ItemType Directory -Path $wfDestPerfil -Force | Out-Null
        New-Item -ItemType Directory -Path $wfDestBom -Force | Out-Null
        foreach ($wfDestCaso in @(
            @{ Nome = 'relativo';    Path = 'pasta\destino';                        Match = 'absoluto' },
            @{ Nome = 'UNC';         Path = '\\servidor\compartilhada\acl';         Match = 'rede' },
            @{ Nome = 'raiz';        Path = ([System.IO.Path]::GetPathRoot($wfDestRaiz)); Match = 'raiz' },
            @{ Nome = 'no perfil';   Path = (Join-Path $wfDestPerfil 'dentro');     Match = 'perfil' },
            @{ Nome = 'sobre o perfil'; Path = $wfDestRaiz;                          Match = 'perfil' })) {
            $wfDestR = Test-WinForgeAclContentRoot -Path ([string]$wfDestCaso.Path) -ProfilePath $wfDestPerfil
            if ($wfDestR.Ok) { Write-Host "  [ERRO] Permissões (destino): '$($wfDestCaso.Nome)' foi aceito ('$($wfDestCaso.Path)')" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfDestR.Reason -notmatch [string]$wfDestCaso.Match) { Write-Host "  [ERRO] Permissões (destino): a recusa de '$($wfDestCaso.Nome)' não diz o motivo ('$($wfDestR.Reason)')" -ForegroundColor Red; $wbErrors++ }
        }
        # Ponto de reanálise na cadeia: o caminho aponta para outro lugar sem parecer que aponta.
        $wfDestLink = Join-Path $wfDestRaiz 'atalho'
        cmd.exe /c mklink /J "$wfDestLink" "$wfDestBom" | Out-Null
        if (Test-Path -LiteralPath $wfDestLink) {
            $wfDestRL = Test-WinForgeAclContentRoot -Path $wfDestLink -ProfilePath $wfDestPerfil
            if ($wfDestRL.Ok) { Write-Host "  [ERRO] Permissões (destino): pasta com ponto de reanálise na cadeia foi aceita" -ForegroundColor Red; $wbErrors++ }
        }
        # Sistema de arquivos e tipo de unidade são conferidos: exFAT/FAT32 não guardam DACL e não
        # dão erro - o arquivo sairia mudo e o Desfazer aplicaria lixo.
        $wfDestFonte = [string](Get-Command Test-WinForgeAclContentRoot).ScriptBlock
        foreach ($wfDestExig in @('DriveFormat', 'NTFS', 'DriveType', 'Fixed', 'Removable')) {
            if ($wfDestFonte -notmatch [regex]::Escape($wfDestExig)) { Write-Host "  [ERRO] Permissões (destino): a conferência não olha '$wfDestExig'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfDestFonte -match '\$env:') { Write-Host "  [ERRO] Permissões (destino): o caminho não pode vir de variável de ambiente" -ForegroundColor Red; $wbErrors++ }
        # Pasta boa passa e traz o aviso literal de §1.4.
        $wfDestOk = Test-WinForgeAclContentRoot -Path $wfDestBom -ProfilePath $wfDestPerfil
        if (-not $wfDestOk.Ok) { Write-Host "  [ERRO] Permissões (destino): a pasta de teste foi recusada ('$($wfDestOk.Reason)')" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfDestFrase in @('qualquer conta de administrador', 'recusa restaurar, mas não recupera arquivo apagado', 'disco desligado na hora de desfazer')) {
            if ([string]$wfDestOk.Warning -notmatch [regex]::Escape($wfDestFrase)) { Write-Host "  [ERRO] Permissões (destino): o aviso não traz '$wfDestFrase'" -ForegroundColor Red; $wbErrors++ }
        }
        # O arquivo de conteúdo, dentro ou fora do %ProgramData%, passa por Protect-WinForgeSnapshotFile.
        $wfDestFonteR = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if (@([regex]::Matches($wfDestFonteR, 'Protect-WinForgeSnapshotFile')).Count -lt 2) { Write-Host "  [ERRO] Permissões (destino): o arquivo de conteúdo externo não passa por Protect-WinForgeSnapshotFile" -ForegroundColor Red; $wbErrors++ }
        if ($wfDestFonteR -notmatch 'WinForgeAclExternalRoot') { Write-Host "  [ERRO] Permissões (destino): a runspace não lê o destino escolhido na thread da janela" -ForegroundColor Red; $wbErrors++ }
        # A caixa nasce DESMARCADA e o diálogo é criado na thread da janela.
        $wfDestFonteD = [string](Get-Command Show-WinForgeAclBackupDestination).ScriptBlock
        if ($wfDestFonteD -notmatch 'IsChecked\s*=\s*\$false') { Write-Host "  [ERRO] Permissões (destino): a caixa 'em outro disco' não nasce desmarcada" -ForegroundColor Red; $wbErrors++ }
        if ($wfDestFonteD -notmatch 'FolderBrowserDialog') { Write-Host "  [ERRO] Permissões (destino): o caminho não vem do seletor de pasta" -ForegroundColor Red; $wbErrors++ }
        # Desfazer: caminho externo ausente diz QUAL disco ligar, e a recusa termina com a frase de §1.7.
        $wfDestFonteU = [string](Get-Command Invoke-WinForgeAclUndo).ScriptBlock
        if ($wfDestFonteU -notmatch 'ExternalPath') { Write-Host "  [ERRO] Permissões (Desfazer): o item de conteúdo não considera ExternalPath" -ForegroundColor Red; $wbErrors++ }
        if ($wfDestFonteU -notmatch 'ligue o disco') { Write-Host "  [ERRO] Permissões (Desfazer): com o arquivo externo ausente, o texto não diz qual disco ligar" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Permissões (destino): sete recusas de Test-WinForgeAclContentRoot, aviso literal, caixa desmarcada por padrão e proteção do arquivo externo"
    } catch {
        Write-Host "  [ERRO] Permissões (destino): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        try { cmd.exe /c rmdir "$wfDestRaiz\atalho" 2>$null | Out-Null } catch { }
        Remove-Item -LiteralPath $wfDestRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Permissões (destino): O termo 'Test-WinForgeAclContentRoot' não é reconhecido…`.

- [ ] **Step 3: Implementar** — as sete exigências, na ordem barata → cara, e o aviso literal:

  ```powershell
  # Sete perguntas, e nenhuma delas é gosto:
  # 1. absoluto e não-UNC     2. não ser raiz de volume     3. DriveFormat -eq 'NTFS' (exFAT/FAT32
  # não guardam DACL e NÃO DÃO ERRO)  4. DriveType Fixed ou Removable  5. nem dentro nem contendo o
  # perfil  6. nenhum ponto de reanálise na cadeia  7. espaço livre com folga.
  $aviso = @'
  Fora da pasta do WinForge, qualquer conta de administrador — desta máquina ou de outra onde o disco for ligado — pode ler, alterar ou apagar este arquivo. O WinForge percebe a alteração e recusa restaurar, mas não recupera arquivo apagado. Em pen drive ou HD externo: disco desligado na hora de desfazer é a mesma coisa que não ter backup.
  '@
  ```
  No Desfazer, com `ExternalPath` preenchido: se o arquivo não estiver lá, a mensagem nomeia o caminho e a unidade (`ligue o disco <letra> (<rótulo>) e tente de novo`) e termina com *"Nada foi alterado. Se tiver uma cópia do arquivo original, coloque-a de volta em &lt;caminho&gt; e tente outra vez."*

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Permissões (destino): sete recusas de Test-WinForgeAclContentRoot, aviso literal, caixa desmarcada por padrão e proteção do arquivo externo` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(repair): backup de permissões obrigatório com destino escolhível e proteção do arquivo externo`

---

### Task 8: Memória — `-StreamTo` nas fases 3 a 5 e os três gargalos atrás dele

**Files:**
- Modify: `src/Engine/winforge/wf-commands.ps1` — `Write-WinForgeStreamLine` (`:280-301`), `Invoke-WinForgeStreamedProcess` (`:303-367`).
- Modify: `src/Engine/winforge/wf-repair.ps1` — as chamadas sem `-StreamTo` **como elas ficam depois das Tarefas 3 e 4**: `:2769` não existe mais (era o `icacls /save /T` que a Tarefa 3 apagou; a Fase 2 agora é caminhada do motor e não roda processo nenhum), então a lista é a da **fase 3** (`:2843`, `:2881`, `:2908`), a da **fase 4** dentro de `Invoke-WinForgeAclOwnerFallback` (`:2959`, `:2966`, `:2969` — as três trocas de posse, que a spec §2 também manda pôr no fluxo e que nenhuma outra tarefa tocava) e o laço **por entrada** da fase 5 que a Tarefa 4 criou.
- Test: `src/Engine/build.ps1`, bloco novo antes de `# ---------------------------------------------------------------- Permissões do disco do sistema` (`build.ps1:3316`).

**Interfaces:**
- Consumes: o laço das fases 3 a 5 de `Invoke-WinForgeAclRestore` (Tarefas 3 e 4).
- Produces:
  ```powershell
  Open-WinForgeStreamWriter  -Path <string> → [System.IO.StreamWriter]   # do cache $sync.WinForgeStreamWriters
  Close-WinForgeStreamWriter -Path <string>
  Write-WinForgeStreamLine   -Path <string> [-Text <string>]             # usa o escritor persistente
  Invoke-WinForgeStreamedProcess -FilePath <string> [-Arguments <string[]>] -StreamTo <string> -Encoding <Encoding> [-NoCapture]
    → @{ Text = <string>; ExitCode = <int> }                             # com -NoCapture, Text = ''
  Invoke-WinForgeAclStreamStep -Path <string> -Step <hashtable> → <int>  # usado pelas fases 3 a 5
  ```
  `$sync.WinForgeStreamWriters` é `[System.Collections.Hashtable]::Synchronized(@{})` chaveada pelo caminho, igual a `WinForgeStreamDone`/`Exit` (`wf-commands.ps1:906-907`); o `finally` do corpo da runspace (`$sync.WinForgeStreamBody`) fecha o escritor.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Janela de saída: memória
    # Não é o TextBox. As fases 2 a 5 chamavam Invoke-WinForgeNativeCommand SEM -StreamTo, caíam no
    # 'Out-String -Width 4096' e o Write-Host seguinte virava UMA linha de centenas de MB: medido,
    # 135 MB de saída viraram 1.575 MB de pico (11,7x).
    $wfMemRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\stream'
    try {
        if (Test-Path -LiteralPath $wfMemRaiz) { Remove-Item -LiteralPath $wfMemRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfMemRaiz -Force | Out-Null
        $wfMemArq = Join-Path $wfMemRaiz 'saida.txt'
        Set-Content -LiteralPath $wfMemArq -Value 'cabecalho' -Encoding UTF8
        # O escritor é PERSISTENTE: abrir e fechar o arquivo por linha é 99x mais lento.
        $wfMemE1 = Open-WinForgeStreamWriter -Path $wfMemArq
        $wfMemE2 = Open-WinForgeStreamWriter -Path $wfMemArq
        if (-not [object]::ReferenceEquals($wfMemE1, $wfMemE2)) { Write-Host "  [ERRO] Fluxo (escritor): duas aberturas do mesmo arquivo devolveram escritores diferentes" -ForegroundColor Red; $wbErrors++ }
        $wfMemRelogio = [System.Diagnostics.Stopwatch]::StartNew()
        1..2000 | ForEach-Object { Write-WinForgeStreamLine -Path $wfMemArq -Text "linha $_" }
        $wfMemRelogio.Stop()
        Close-WinForgeStreamWriter -Path $wfMemArq
        if ((Measure-Object -InputObject (Get-Content -LiteralPath $wfMemArq -Raw) -Character).Characters -lt 2000) { Write-Host "  [ERRO] Fluxo (escritor): as linhas não chegaram ao arquivo" -ForegroundColor Red; $wbErrors++ }
        if (@(Get-Content -LiteralPath $wfMemArq).Count -ne 2001) { Write-Host "  [ERRO] Fluxo (escritor): $(@(Get-Content -LiteralPath $wfMemArq).Count) linha(s), esperado 2001" -ForegroundColor Red; $wbErrors++ }
        if ($wfMemRelogio.Elapsed.TotalSeconds -gt 5) { Write-Host "  [ERRO] Fluxo (escritor): 2000 linhas levaram $([int]$wfMemRelogio.Elapsed.TotalSeconds)s - o arquivo continua sendo aberto por linha" -ForegroundColor Red; $wbErrors++ }
        if ($sync.WinForgeStreamWriters.ContainsKey($wfMemArq)) { Write-Host "  [ERRO] Fluxo (escritor): o escritor não saiu do cache no Close" -ForegroundColor Red; $wbErrors++ }
        # -NoCapture: o único chamador descarta o texto, e acumulá-lo num StringBuilder é guardar o
        # volume inteiro na memória para jogar fora.
        $wfMemSaida = Join-Path $wfMemRaiz 'cmd.txt'
        Set-Content -LiteralPath $wfMemSaida -Value '' -Encoding UTF8
        $wfMemRes = Invoke-WinForgeStreamedProcess -FilePath (Get-WinForgeSystemExe -Name 'cmd.exe') -Arguments @('/c', 'echo alfa& echo beta 1>&2') -StreamTo $wfMemSaida -Encoding (Get-WinForgeOutputEncoding -Name 'oem') -NoCapture
        if ([string]$wfMemRes.Text -ne '') { Write-Host "  [ERRO] Fluxo (-NoCapture): Text veio com $(([string]$wfMemRes.Text).Length) caractere(s), esperado vazio" -ForegroundColor Red; $wbErrors++ }
        $wfMemTexto = [string](Get-Content -LiteralPath $wfMemSaida -Raw)
        if ($wfMemTexto -notmatch 'alfa') { Write-Host "  [ERRO] Fluxo (-NoCapture): a saída padrão não chegou ao arquivo" -ForegroundColor Red; $wbErrors++ }
        if ($wfMemTexto -notmatch '\[erro\] beta') { Write-Host "  [ERRO] Fluxo (-NoCapture): o fluxo de erro não chegou ao arquivo" -ForegroundColor Red; $wbErrors++ }
        # StandardError lido LINHA A LINHA numa Task, com trava: o ReadToEndAsync junta o erro sem
        # teto, e aqui o erro É o volume.
        $wfMemFonteP = [string](Get-Command Invoke-WinForgeStreamedProcess).ScriptBlock
        if ($wfMemFonteP -match 'ReadToEndAsync') { Write-Host "  [ERRO] Fluxo (erro): StandardError.ReadToEndAsync() continua lá - ele junta o erro inteiro na memória" -ForegroundColor Red; $wbErrors++ }
        if ($wfMemFonteP -notmatch 'ReadLine') { Write-Host "  [ERRO] Fluxo (erro): o fluxo de erro não é lido linha a linha" -ForegroundColor Red; $wbErrors++ }
        if ($wfMemFonteP -notmatch '\[System\.Threading\.Monitor\]|lock|Mutex|SyncRoot') { Write-Host "  [ERRO] Fluxo (erro): duas threads escrevem no mesmo StreamWriter sem trava" -ForegroundColor Red; $wbErrors++ }
        # As fases 3 a 5 passaram a usar o fluxo (a fase 2 não roda mais processo nenhum: depois da
        # Tarefa 3 ela é caminhada do motor). São as três chamadas da fase 3, o laço por entrada da
        # fase 5 e - a que faltava - a fase 4, dentro de Invoke-WinForgeAclOwnerFallback.
        $wfMemFonteR = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        if (@([regex]::Matches($wfMemFonteR, 'Invoke-WinForgeAclStreamStep')).Count -lt 4) { Write-Host "  [ERRO] Fluxo (fases): menos de 4 passos das fases 3 a 5 usam o fluxo ao vivo" -ForegroundColor Red; $wbErrors++ }
        $wfMemFonteF4 = [string](Get-Command Invoke-WinForgeAclOwnerFallback).ScriptBlock
        if ($wfMemFonteF4 -notmatch 'Invoke-WinForgeAclStreamStep') { Write-Host "  [ERRO] Fluxo (fase 4): Invoke-WinForgeAclOwnerFallback continua em Invoke-WinForgeNativeCommand, fora do fluxo" -ForegroundColor Red; $wbErrors++ }
        if ($wfMemFonteF4 -match 'Invoke-WinForgeNativeCommand') { Write-Host "  [ERRO] Fluxo (fase 4): sobrou chamada direta a Invoke-WinForgeNativeCommand na troca de posse" -ForegroundColor Red; $wbErrors++ }
        if ($wfMemFonteR -match 'Write-Host \(\[string\]\$r\.Text\)') { Write-Host "  [ERRO] Fluxo (fases): ainda existe 'Write-Host ([string]`$r.Text)' - é a linha de centenas de MB" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Fluxo (memória): escritor persistente (2000 linhas em $([int]$wfMemRelogio.Elapsed.TotalMilliseconds)ms), -NoCapture sem texto, erro linha a linha, fases 3 a 5 no fluxo"
    } catch {
        Write-Host "  [ERRO] Fluxo (memória): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfMemRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Fluxo (memória): O termo 'Open-WinForgeStreamWriter' não é reconhecido…` e `[ERRO] Fluxo (erro): StandardError.ReadToEndAsync() continua lá…`.

- [ ] **Step 3: Implementar** — o trecho que decide o desenho, dentro de `Invoke-WinForgeStreamedProcess`:

  ```powershell
  # Duas threads escrevem no MESMO StreamWriter (a saída padrão aqui, o erro na Task), e
  # StreamWriter não é seguro para isso: sem a trava, duas linhas se intercalam no meio de um
  # caractere. E o erro é lido LINHA A LINHA: com ReadToEndAsync o fluxo de erro - que num icacls
  # de perfil É o volume - fica inteiro na memória até o processo terminar.
  $trava = New-Object object
  $tarefaErro = [System.Threading.Tasks.Task]::Run([Action]{
      while ($null -ne ($le = $processo.StandardError.ReadLine())) {
          [System.Threading.Monitor]::Enter($trava)
          try { $escritor.WriteLine("[erro] $le") } finally { [System.Threading.Monitor]::Exit($trava) }
      }
  })
  ```
  `-NoCapture` some com o `StringBuilder`: nada de `AppendLine`, e o retorno é `@{ Text = ''; ExitCode = $codigo }`. `Invoke-WinForgeAclStreamStep -Path -Step` é o invólucro que as fases 3 a 5 usam: escreve a linha `> <exe> <args>`, chama `Invoke-WinForgeNativeCommand … -StreamTo $Path -NoCapture` e devolve o código.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Fluxo (memória): escritor persistente (2000 linhas em NNms), -NoCapture sem texto, erro linha a linha, fases 3 a 5 no fluxo` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: devolver o `AppendLine` ao `-NoCapture` e ver "Text veio com N caractere(s)" ficar vermelho; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `perf(commands): fluxo ao vivo nas fases 3 a 5, escritor persistente e erro lido linha a linha`

---

### Task 9: Tetos — anel na caixa, leitura por tique, arquivo de 256 MB e retenção

**Files:**
- Modify: `src/Engine/winforge/wf-commands.ps1` — `Invoke-WinForgeFollowTick` (`:828-900`), `Get-WinForgeCommandOutputPath` (`:145-186`) e funções novas.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 8.

**Interfaces:**
- Consumes: `Open-WinForgeStreamWriter -Path <string>` / `Write-WinForgeStreamLine -Path <string> [-Text <string>]` (Tarefa 8).
- Produces:
  ```powershell
  Limit-WinForgeStreamText -Text <string> [-MaxChars 4194304] [-KeepChars 2097152] → <string>
  Get-WinForgeFollowReadWindow -Offset <long> -Length <long> [-MaxGrowth 8388608] [-TailBytes 1048576]
    → @{ Start = <long>; Count = <int>; Skipped = <long> }
  Test-WinForgeStreamFileCap -Path <string> [-MaxBytes 268435456] → @{ Over = <bool>; Bytes = <long>; Text = <string> }
  Remove-WinForgeOldCommandOutput -Prefix <string> [-MaxAgeDays 30] [-MaxFiles 20] → @{ Removed = @(<string>) }
  ```
  Histerese: a caixa só é cortada quando passa de `MaxChars` (4 MB) e volta para `KeepChars` (2 MB) — cortar a cada tique é o que fazia o pico de 971 MB. O bloco por tique continua 512 KB (`wf-commands.ps1:867`): o teto rígido de 2 MB em blocos de 64 KB foi medido e descartado por levar 393 s.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Janela de saída: tetos
    try {
        # Anel com histerese: abaixo do teto não mexe; acima, volta para 2 MB cortando na primeira
        # quebra de linha, com a marca.
        $wfTetoCurto = ('linha' + "`r`n") * 100
        if ((Limit-WinForgeStreamText -Text $wfTetoCurto) -ne $wfTetoCurto) { Write-Host "  [ERRO] Tetos (anel): texto abaixo do teto foi alterado" -ForegroundColor Red; $wbErrors++ }
        $wfTetoGrande = ('x' * 99 + "`r`n") * 50000     # ~5 MB
        $wfTetoCortado = Limit-WinForgeStreamText -Text $wfTetoGrande
        if ($wfTetoCortado.Length -gt 4194304) { Write-Host "  [ERRO] Tetos (anel): o corte deixou $($wfTetoCortado.Length) caractere(s), acima do teto de 4 MB" -ForegroundColor Red; $wbErrors++ }
        if ($wfTetoCortado.Length -lt 1000000) { Write-Host "  [ERRO] Tetos (anel): o corte deixou só $($wfTetoCortado.Length) caractere(s) - a histerese devolve ~2 MB" -ForegroundColor Red; $wbErrors++ }
        if ($wfTetoCortado -notlike '*(o começo desta parte ficou só no arquivo)*') { Write-Host "  [ERRO] Tetos (anel): o texto cortado saiu sem a marca" -ForegroundColor Red; $wbErrors++ }
        $wfTetoResto = $wfTetoCortado.Substring($wfTetoCortado.IndexOf("`n") + 1)
        if ($wfTetoResto -notmatch '^x{99}') { Write-Host "  [ERRO] Tetos (anel): o corte não caiu numa quebra de linha" -ForegroundColor Red; $wbErrors++ }
        # E a histerese de verdade: cortar o já cortado não corta de novo.
        if ((Limit-WinForgeStreamText -Text $wfTetoCortado).Length -ne $wfTetoCortado.Length) { Write-Host "  [ERRO] Tetos (anel): o texto já dentro do teto foi cortado outra vez" -ForegroundColor Red; $wbErrors++ }
        # Leitura por tique: cresceu mais de 8 MB, lê só o último 1 MB e diz quanto pulou.
        $wfTetoJan = Get-WinForgeFollowReadWindow -Offset 0 -Length 20971520
        if ([long]$wfTetoJan.Start -ne (20971520 - 1048576)) { Write-Host "  [ERRO] Tetos (tique): crescimento de 20 MB deveria começar em Length-1MB, veio $($wfTetoJan.Start)" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfTetoJan.Count -gt 1048576) { Write-Host "  [ERRO] Tetos (tique): o tique leria $($wfTetoJan.Count) bytes" -ForegroundColor Red; $wbErrors++ }
        if ([long]$wfTetoJan.Skipped -le 0) { Write-Host "  [ERRO] Tetos (tique): o que foi pulado não é relatado" -ForegroundColor Red; $wbErrors++ }
        $wfTetoPouco = Get-WinForgeFollowReadWindow -Offset 100 -Length 200000
        if ([long]$wfTetoPouco.Start -ne 100 -or [int]$wfTetoPouco.Count -ne 199900) { Write-Host "  [ERRO] Tetos (tique): crescimento pequeno foi recortado ($($wfTetoPouco.Start)/$($wfTetoPouco.Count))" -ForegroundColor Red; $wbErrors++ }
        if ([long]$wfTetoPouco.Skipped -ne 0) { Write-Host "  [ERRO] Tetos (tique): crescimento pequeno relatou salto" -ForegroundColor Red; $wbErrors++ }
        # Teto do ARQUIVO: 256 MB por execução, com a linha dizendo que os detalhes foram descartados.
        $wfTetoDir = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\tetos'
        if (Test-Path -LiteralPath $wfTetoDir) { Remove-Item -LiteralPath $wfTetoDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfTetoDir -Force | Out-Null
        $wfTetoArq = Join-Path $wfTetoDir 'repair-Teste-20260912-101010.txt'
        Set-Content -LiteralPath $wfTetoArq -Value ('y' * 4096) -Encoding UTF8
        $wfTetoCap = Test-WinForgeStreamFileCap -Path $wfTetoArq -MaxBytes 1024
        if (-not $wfTetoCap.Over) { Write-Host "  [ERRO] Tetos (arquivo): 4 KB contra um teto de 1 KB não disparou" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfTetoCap.Text -notmatch 'descartados') { Write-Host "  [ERRO] Tetos (arquivo): a linha não diz que os detalhes dali em diante foram descartados ('$($wfTetoCap.Text)')" -ForegroundColor Red; $wbErrors++ }
        if ((Test-WinForgeStreamFileCap -Path $wfTetoArq).Over) { Write-Host "  [ERRO] Tetos (arquivo): 4 KB dispararam o teto padrão de 256 MB" -ForegroundColor Red; $wbErrors++ }
        # Retenção: 30 dias / 20 arquivos POR PREFIXO - 'server' não conta no corte de 'repair'.
        foreach ($wfTetoN in 1..25) { Set-Content -LiteralPath (Join-Path $wfTetoDir ("repair-X-202609{0:00}-101010.txt" -f $wfTetoN)) -Value 'z' -Encoding UTF8 }
        foreach ($wfTetoN in 1..3) { Set-Content -LiteralPath (Join-Path $wfTetoDir ("server-X-202609{0:00}-101010.txt" -f $wfTetoN)) -Value 'z' -Encoding UTF8 }
        $wfTetoVelho = Join-Path $wfTetoDir 'repair-Antigo-20250101-101010.txt'
        Set-Content -LiteralPath $wfTetoVelho -Value 'z' -Encoding UTF8
        (Get-Item -LiteralPath $wfTetoVelho).LastWriteTime = (Get-Date).AddDays(-45)
        $wfTetoRet = Remove-WinForgeOldCommandOutput -Prefix 'repair' -Root $wfTetoDir
        if (@(Get-ChildItem -LiteralPath $wfTetoDir -Filter 'repair-*.txt').Count -gt 20) { Write-Host "  [ERRO] Tetos (retenção): sobraram $(@(Get-ChildItem -LiteralPath $wfTetoDir -Filter 'repair-*.txt').Count) arquivos 'repair', o teto é 20" -ForegroundColor Red; $wbErrors++ }
        if (Test-Path -LiteralPath $wfTetoVelho) { Write-Host "  [ERRO] Tetos (retenção): o arquivo de 45 dias não foi apagado" -ForegroundColor Red; $wbErrors++ }
        if (@(Get-ChildItem -LiteralPath $wfTetoDir -Filter 'server-*.txt').Count -ne 3) { Write-Host "  [ERRO] Tetos (retenção): a limpeza de 'repair' mexeu nos arquivos de 'server'" -ForegroundColor Red; $wbErrors++ }
        # 'IsUndoEnabled = $false' NÃO MUDA NADA (medido) e não pode aparecer.
        $wfTetoFonteT = [string](Get-Command Invoke-WinForgeFollowTick).ScriptBlock
        if ($wfTetoFonteT -match 'IsUndoEnabled') { Write-Host "  [ERRO] Tetos (caixa): 'IsUndoEnabled' voltou ao tique - medido, não muda nada" -ForegroundColor Red; $wbErrors++ }
        if ($wfTetoFonteT -notmatch '524288') { Write-Host "  [ERRO] Tetos (caixa): o bloco por tique deixou de ser 512 KB" -ForegroundColor Red; $wbErrors++ }
        if ($wfTetoFonteT -notmatch 'Limit-WinForgeStreamText') { Write-Host "  [ERRO] Tetos (caixa): o tique não aplica o anel" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Tetos: anel 4 MB -> 2 MB com histerese, tique lê no máximo 1 MB após 8 MB de crescimento, arquivo de 256 MB, retenção 30/20 por prefixo"
    } catch {
        Write-Host "  [ERRO] Tetos: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\tetos') -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Tetos: O termo 'Limit-WinForgeStreamText' não é reconhecido…`.

- [ ] **Step 3: Implementar** — `Remove-WinForgeOldCommandOutput` ganha `-Root <string>` (padrão: a pasta de `Get-WinForgeCommandOutputPath`) e é chamada uma vez por execução, em `Start-WinForgeStreamedCommand`, logo depois de criar o arquivo. O trecho que decide o desenho:

  ```powershell
  # HISTERESE, e não corte por tique: cortar sempre que passa de 2 MB faz a caixa copiar 2 MB a
  # cada 512 KB que chegam - foi assim que o pico bateu 971 MB. Cortando só acima de 4 MB e
  # voltando para 2 MB, a cópia acontece uma vez a cada 2 MB de saída: 274 MB de pico, medido.
  if ($Text.Length -le $MaxChars) { return $Text }
  $corte = $Text.IndexOf("`n", $Text.Length - $KeepChars)
  $inicio = if ($corte -lt 0) { $Text.Length - $KeepChars } else { $corte + 1 }
  return "… (o começo desta parte ficou só no arquivo)`r`n" + $Text.Substring($inicio)
  ```

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Tetos: anel 4 MB -> 2 MB com histerese, tique lê no máximo 1 MB após 8 MB de crescimento, arquivo de 256 MB, retenção 30/20 por prefixo` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `perf(commands): anel com histerese na janela de saída, teto do arquivo e retenção 30/20`

---

### Task 10: `ExpectMinutes` e o cabeçalho âmbar a 1,5× e 3×

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — `ExpectMinutes` em cada linha `repair` de `Get-WinForgeRepairCommand`.
- Modify: `src/Engine/winforge/wf-commands.ps1` — `Get-WinForgeFollowHeader` nova; `Invoke-WinForgeFollowTick` passa a usá-la; `Show-WinForgeOutputWindow` guarda `ExpectMinutes` na `Tag`.
- Modify: `src/Engine/config/wf-theme.ps1` — tokens `HeaderWarningColor` e `HeaderUrgentColor` (Claro e Escuro).
- Modify: `src/Engine/build.ps1` — pares de contraste novos na conferência de tema; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 9.

**Interfaces:**
- Consumes: `$sync.WinForgeStreamDone`/`$sync.WinForgeStreamExit` (já existentes, `wf-commands.ps1:906-907`).
- Produces:
  ```powershell
  Get-WinForgeFollowHeader -Title <string> -Elapsed <timespan> [-ExpectMinutes <int>] [-Done] [-ExitCode <object>] [-Cancelled]
    → @{ Text = <string>; Level = 'normal'|'ambar'|'urgente' }
  ```
  `ExpectMinutes` por linha: `AclRestore` 15, `AclUndo` 10, `ChkdskScan` 10, `DotNet35Enable` 20, `FixesUpdate` 20 (a calibrar, e o comentário diz isso). `Tag.ExpectMinutes` é lido pelo tique.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Janela de saída: cabeçalho
    try {
        $wfCabN = Get-WinForgeFollowHeader -Title 'Restaurar padrões' -Elapsed ([timespan]::FromMinutes(5)) -ExpectMinutes 15
        if ([string]$wfCabN.Level -ne 'normal') { Write-Host "  [ERRO] Cabeçalho: 5 de 15 minutos deu '$($wfCabN.Level)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfCabN.Text -notmatch '^Em andamento: Restaurar padrões \(05:00\)$') { Write-Host "  [ERRO] Cabeçalho: '$($wfCabN.Text)'" -ForegroundColor Red; $wbErrors++ }
        $wfCabA = Get-WinForgeFollowHeader -Title 'Restaurar padrões' -Elapsed ([timespan]::FromMinutes(23)) -ExpectMinutes 15
        if ([string]$wfCabA.Level -ne 'ambar') { Write-Host "  [ERRO] Cabeçalho: 23 de 15 minutos (1,53x) deu '$($wfCabA.Level)', esperado 'ambar'" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfCabF in @('Está demorando mais que o normal (o comum são 15 minutos)', 'Continua rodando', 'Não feche esta janela', 'use o botão Parar')) {
            if ([string]$wfCabA.Text -notmatch [regex]::Escape($wfCabF)) { Write-Host "  [ERRO] Cabeçalho (âmbar): falta '$wfCabF'" -ForegroundColor Red; $wbErrors++ }
        }
        $wfCabU = Get-WinForgeFollowHeader -Title 'Restaurar padrões' -Elapsed ([timespan]::FromMinutes(46)) -ExpectMinutes 15
        if ([string]$wfCabU.Level -ne 'urgente') { Write-Host "  [ERRO] Cabeçalho: 46 de 15 minutos (3,06x) deu '$($wfCabU.Level)', esperado 'urgente'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfCabU.Text -notmatch 'Parar') { Write-Host "  [ERRO] Cabeçalho (urgente): o Parar não está em destaque" -ForegroundColor Red; $wbErrors++ }
        $wfCabD = Get-WinForgeFollowHeader -Title 'Restaurar padrões' -Elapsed ([timespan]::FromMinutes(7)) -Done -ExitCode 0
        if ([string]$wfCabD.Text -ne 'Concluído em 07:00 (código 0)') { Write-Host "  [ERRO] Cabeçalho (fim): '$($wfCabD.Text)'" -ForegroundColor Red; $wbErrors++ }
        $wfCabC = Get-WinForgeFollowHeader -Title 'Restaurar padrões' -Elapsed ([timespan]::FromMinutes(3)) -Done -ExitCode 0 -Cancelled
        if ([string]$wfCabC.Text -ne 'Cancelado em 03:00') { Write-Host "  [ERRO] Cabeçalho (cancelado): '$($wfCabC.Text)', esperado 'Cancelado em 03:00' - nunca 'Concluído'" -ForegroundColor Red; $wbErrors++ }
        # Sem ExpectMinutes não há âmbar: um comando sem estimativa não pode inventar atraso.
        if ([string](Get-WinForgeFollowHeader -Title 'X' -Elapsed ([timespan]::FromHours(3))).Level -ne 'normal') { Write-Host "  [ERRO] Cabeçalho: sem ExpectMinutes o nível mudou" -ForegroundColor Red; $wbErrors++ }
        # Toda linha 'repair' declara ExpectMinutes.
        foreach ($wfCabNome in @('WmiRepair', 'StoreReregister', 'ChkdskSchedule', 'MemoryDiag', 'DotNet35Enable', 'VcRedist', 'PowerShell7', 'AclRestore', 'AclUndo', 'AclCleanup')) {
            $wfCabCmd = Get-WinForgeRepairCommand -Name $wfCabNome
            if ([string]$wfCabCmd.Kind -eq 'read') { continue }
            if (-not ([int]$wfCabCmd.ExpectMinutes -gt 0)) { Write-Host "  [ERRO] Cabeçalho: a linha '$wfCabNome' não declara ExpectMinutes" -ForegroundColor Red; $wbErrors++ }
        }
        if ([int](Get-WinForgeRepairCommand -Name 'AclRestore').ExpectMinutes -ne 15) { Write-Host "  [ERRO] Cabeçalho: AclRestore deveria estimar 15 minutos" -ForegroundColor Red; $wbErrors++ }
        if ([int](Get-WinForgeRepairCommand -Name 'AclUndo').ExpectMinutes -ne 10) { Write-Host "  [ERRO] Cabeçalho: AclUndo deveria estimar 10 minutos" -ForegroundColor Red; $wbErrors++ }
        # Os dois tokens novos existem nos dois temas (o contraste é cobrado pela conferência de tema).
        foreach ($wfCabTema in @('Light', 'Dark')) {
            foreach ($wfCabTok in @('HeaderWarningColor', 'HeaderUrgentColor')) {
                if ([string]::IsNullOrWhiteSpace([string]$sync.configs.themes.$wfCabTema.$wfCabTok)) { Write-Host "  [ERRO] Cabeçalho: token '$wfCabTok' ausente no tema $wfCabTema" -ForegroundColor Red; $wbErrors++ }
            }
        }
        Write-Host "  Cabeçalho: normal/âmbar (1,5x)/urgente (3x), 'Cancelado em mm:ss' nunca vira 'Concluído', ExpectMinutes em toda linha repair"
    } catch {
        Write-Host "  [ERRO] Cabeçalho: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Cabeçalho: O termo 'Get-WinForgeFollowHeader' não é reconhecido…`.

- [ ] **Step 3: Implementar** — `Get-WinForgeFollowHeader` pura; o tique só pinta:

  ```powershell
  # 1,5x e 3x do ESPERADO, e não um número fixo de minutos: um DISM de vinte minutos e um Desfazer
  # de dez não têm o mesmo "está demorando". Sem ExpectMinutes o nível é sempre 'normal' - comando
  # sem estimativa não pode acusar atraso que ninguém sabe medir.
  $mmss = '{0:00}:{1:00}' -f [int][math]::Floor($Elapsed.TotalMinutes), $Elapsed.Seconds
  if ($Cancelled) { return @{ Text = "Cancelado em $mmss"; Level = 'normal' } }
  ```
  Tokens: `HeaderWarningColor` = `#B45309` (Claro) / `#F59E0B` (Escuro); `HeaderUrgentColor` = `#B91C1C` (Claro) / `#EF4444` (Escuro) — os mesmos valores já conferidos de `DiscouragedColor`/`DangerColor` (`wf-theme.ps1:166-177`), com os pares novos entrando na conferência de ≥ 4,5:1 contra `MainBackgroundColor` nos dois temas.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Cabeçalho: normal/âmbar (1,5x)/urgente (3x), 'Cancelado em mm:ss' nunca vira 'Concluído', ExpectMinutes em toda linha repair`, a linha de contraste do tema sem `[ERRO]`, e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(commands): cabeçalho da janela avisa quando passa de 1,5x e 3x do tempo esperado`

---

### Task 11: Parar — o encanamento do cancelamento e um Job Object que mata a árvore

**Files:**
- Modify: `src/Engine/winforge/wf-commands.ps1` — `$sync.WinForgeStreamCancel`/`$sync.WinForgeStreamJob`/`$sync.WinForgeStreamProtected` (junto de `:906-907`), `Invoke-WinForgeStreamedProcess` (criação do job, atribuição e limpeza no `finally`, `:362-365`), `Invoke-WinForgeStreamedSteps` (`:1165-1172`), `$sync.WinForgeStreamBody` (o `Add-Type` guardado).
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 10.

**Interfaces:**
- Consumes: `Invoke-WinForgeStreamedProcess … -NoCapture` (Tarefa 8).
- Produces:
  ```powershell
  Request-WinForgeStreamCancel -Path <string> → @{ Ok = <bool>; Reason = <string> }
  Test-WinForgeStreamCancelled -Path <string> → <bool>          # $false enquanto $sync.WinForgeStreamProtected[$Path]
  Enter-WinForgeStreamProtected -Path <string> / Exit-WinForgeStreamProtected -Path <string>
  ```
  `$sync.WinForgeStreamCancel`, `$sync.WinForgeStreamJob` e `$sync.WinForgeStreamProtected` são hashtables sincronizadas chaveadas pelo caminho do arquivo de saída, iguais a `WinForgeStreamDone`/`Exit`. Quem usa a janela protegida é a Tarefa 12; aqui ela nasce e é exercida.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Parar: encanamento e Job Object
    # Medido: 'powershell.exe' morto com Stop-Process -Force DEIXA VIVO o filho iniciado com
    # UseShellExecute=$false - fechar o WinForge deixava um icacls.exe elevado reescrevendo ACL de
    # sistema. Daí o Job Object. E medido também: tipo criado por Add-Type na runspace PRINCIPAL não
    # é visto no pool, e um segundo Add-Type do mesmo nome falha - daí a guarda.
    $wfParRaiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\parar'
    try {
        if (Test-Path -LiteralPath $wfParRaiz) { Remove-Item -LiteralPath $wfParRaiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfParRaiz -Force | Out-Null
        $wfParArq = Join-Path $wfParRaiz 'saida.txt'
        Set-Content -LiteralPath $wfParArq -Value 'cab' -Encoding UTF8
        foreach ($wfParChave in @('WinForgeStreamCancel', 'WinForgeStreamJob', 'WinForgeStreamProtected')) {
            if ($null -eq $sync.$wfParChave) { Write-Host "  [ERRO] Parar: `$sync.$wfParChave não existe" -ForegroundColor Red; $wbErrors++ }
            elseif (-not $sync.$wfParChave.IsSynchronized) { Write-Host "  [ERRO] Parar: `$sync.$wfParChave não é sincronizada - ela atravessa duas threads" -ForegroundColor Red; $wbErrors++ }
        }
        if (Test-WinForgeStreamCancelled -Path $wfParArq) { Write-Host "  [ERRO] Parar: arquivo novo já nasce cancelado" -ForegroundColor Red; $wbErrors++ }
        $null = Request-WinForgeStreamCancel -Path $wfParArq
        if (-not (Test-WinForgeStreamCancelled -Path $wfParArq)) { Write-Host "  [ERRO] Parar: o pedido de cancelamento não levantou a flag" -ForegroundColor Red; $wbErrors++ }
        # A flag é IGNORADA dentro da janela protegida: cancelar entre 'posse aos Admins' e 'posse de
        # volta' (Fase 4, Tarefa 12) deixa a pasta do sistema aberta a qualquer processo elevado.
        Enter-WinForgeStreamProtected -Path $wfParArq
        if (Test-WinForgeStreamCancelled -Path $wfParArq) { Write-Host "  [ERRO] Parar: a flag venceu dentro da janela protegida" -ForegroundColor Red; $wbErrors++ }
        Exit-WinForgeStreamProtected -Path $wfParArq
        if (-not (Test-WinForgeStreamCancelled -Path $wfParArq)) { Write-Host "  [ERRO] Parar: a flag sumiu ao sair da janela protegida" -ForegroundColor Red; $wbErrors++ }
        [void]$sync.WinForgeStreamCancel.Remove($wfParArq)
        # A checagem acontece ENTRE passos.
        $wfParFonteS = [string](Get-Command Invoke-WinForgeStreamedSteps).ScriptBlock
        if ($wfParFonteS -notmatch 'Test-WinForgeStreamCancelled') { Write-Host "  [ERRO] Parar: Invoke-WinForgeStreamedSteps não confere a flag antes de cada passo" -ForegroundColor Red; $wbErrors++ }
        # Add-Type GUARDADO, dentro do scriptblock do POOL.
        $wfParCorpo = [string]$sync.WinForgeStreamBody
        if ($wfParCorpo -notmatch "'WfJob'\s*-as\s*\[type\]") { Write-Host "  [ERRO] Parar: o Add-Type do job não está guardado por ('WfJob' -as [type])" -ForegroundColor Red; $wbErrors++ }
        if ($wfParCorpo -notmatch 'Add-Type') { Write-Host "  [ERRO] Parar: o Add-Type do job não está dentro do corpo da runspace" -ForegroundColor Red; $wbErrors++ }
        # A guarda roda DUAS VEZES seguidas sem estourar - e com o MESMO nome nas duas pontas: com
        # '-Namespace WinForgeProva' o tipo nasceria 'WinForgeProva.WfJobProva', a guarda
        # ('WfJobProva' -as [type]) daria $null para sempre e o segundo Add-Type é que estouraria.
        $wfParDef = '[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr a, string lpName);' +
                    '[DllImport("kernel32.dll")] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);' +
                    '[DllImport("kernel32.dll")] public static extern bool TerminateJobObject(IntPtr job, uint exitCode);' +
                    '[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);'
        $wfParGuarda = { if (-not ('WfJobProva' -as [type])) { Add-Type -Namespace '' -Name 'WfJobProva' -MemberDefinition $wfParDef } }
        & $wfParGuarda; & $wfParGuarda
        if (-not ('WfJobProva' -as [type])) { Write-Host "  [ERRO] Parar: a guarda não criou o tipo" -ForegroundColor Red; $wbErrors++ }
        else {
            # O JOB DE VERDADE, matando o PRÓPRIO filho: um grep de fonte não prova que um handle
            # mata uma árvore, e é essa a única coisa que o Parar promete.
            $wfParJob = [WfJobProva]::CreateJobObject([IntPtr]::Zero, $null)
            if ($wfParJob -eq [IntPtr]::Zero) { Write-Host "  [ERRO] Parar (job): CreateJobObject devolveu handle nulo" -ForegroundColor Red; $wbErrors++ }
            else {
                $wfParFilho = Start-Process -FilePath (Get-WinForgeSystemExe -Name 'cmd.exe') -ArgumentList '/c', 'ping -n 30 127.0.0.1' -PassThru -WindowStyle Hidden
                try {
                    if (-not [WfJobProva]::AssignProcessToJobObject($wfParJob, $wfParFilho.Handle)) { Write-Host "  [ERRO] Parar (job): AssignProcessToJobObject falhou (erro $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))" -ForegroundColor Red; $wbErrors++ }
                    $null = [WfJobProva]::TerminateJobObject($wfParJob, 1)
                    if (-not $wfParFilho.WaitForExit(5000)) { Write-Host "  [ERRO] Parar (job): o job NÃO matou a árvore - o filho continuou vivo depois do TerminateJobObject" -ForegroundColor Red; $wbErrors++ }
                } finally {
                    if (-not $wfParFilho.HasExited) { Stop-Process -Id $wfParFilho.Id -Force -ErrorAction SilentlyContinue }
                    $null = [WfJobProva]::CloseHandle($wfParJob)
                }
            }
        }
        # O job é criado e guardado ANTES do Start(), a Fase 4 fica de fora e a limpeza é no finally.
        $wfParFonteP = [string](Get-Command Invoke-WinForgeStreamedProcess).ScriptBlock
        if ($wfParFonteP -notmatch 'AssignProcessToJobObject') { Write-Host "  [ERRO] Parar: o processo não é atribuído a nenhum job" -ForegroundColor Red; $wbErrors++ }
        if ($wfParFonteP -notmatch 'WinForgeStreamProtected') { Write-Host "  [ERRO] Parar: a atribuição ao job não pula os processos da janela protegida" -ForegroundColor Red; $wbErrors++ }
        if ($wfParFonteP -notmatch '(?s)finally\s*\{[^}]*WinForgeStreamJob') { Write-Host "  [ERRO] Parar: o job não é limpo no 'finally'" -ForegroundColor Red; $wbErrors++ }
        $wfParPosJob = $wfParFonteP.IndexOf('CreateJobObject', [StringComparison]::Ordinal)
        $wfParPosStart = $wfParFonteP.IndexOf('.Start()', [StringComparison]::Ordinal)
        if ($wfParPosJob -lt 0 -or $wfParPosStart -lt 0 -or $wfParPosJob -gt $wfParPosStart) { Write-Host "  [ERRO] Parar: o job é criado DEPOIS do Start() - há uma janela em que o filho não pertence a job nenhum" -ForegroundColor Red; $wbErrors++ }
        # '-NoElevate' não promete Parar: medido, OpenProcess sobre processo elevado, de pai não
        # elevado, devolve handle=0 err=5.
        $wfParFonteR = [string](Get-Command Request-WinForgeStreamCancel).ScriptBlock
        if ($wfParFonteR -notmatch 'NoElevate|não elevado') { Write-Host "  [ERRO] Parar: falta a ressalva de '-NoElevate' em Request-WinForgeStreamCancel" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Parar: três hashtables sincronizadas, flag ignorada na janela protegida, guarda do Add-Type roda duas vezes e o job matou a árvore do filho"
    } catch {
        Write-Host "  [ERRO] Parar: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfParRaiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Parar: $sync.WinForgeStreamCancel não existe` e `[ERRO] Parar: O termo 'Request-WinForgeStreamCancel' não é reconhecido…`.

- [ ] **Step 3: Implementar** — o `Add-Type` mora **dentro** de `$sync.WinForgeStreamBody`, que é o scriptblock que vai para o pool:

  ```powershell
  # Medido: um tipo criado por Add-Type na runspace principal NÃO é visto nas runspaces do pool, e
  # um segundo Add-Type do mesmo nome falha com "o tipo já existe". A guarda resolve as duas pontas.
  # O NOME da guarda e o NOME do tipo têm de ser o mesmo: com -Namespace preenchido o tipo nasce
  # 'Espaco.WfJob', a guarda nunca o encontra e o segundo Add-Type estoura.
  if (-not ('WfJob' -as [type])) {
      Add-Type -Namespace '' -Name 'WfJob' -MemberDefinition @'
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr a, string lpName);
  [DllImport("kernel32.dll")] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll")] public static extern bool TerminateJobObject(IntPtr job, uint exitCode);
  [DllImport("kernel32.dll")] public static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint len);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  '@
  }
  ```
  (Esse here-string vive em `wf-commands.ps1`, onde é um here-string normal. Ele **não** pode ser copiado para dentro do here-string do SelfTest em `build.ps1`: `'@` no começo da linha fecharia o de fora. É por isso que o teste acima monta a definição por concatenação de strings de uma linha.)

  O job é criado e guardado em `$sync.WinForgeStreamJob[$caminho]` **antes** do `Start()`; `AssignProcessToJobObject` roda na linha seguinte ao `Start()`, antes da primeira leitura — não há como atribuir um processo que ainda não existe, e este é o instante mais cedo possível. `KILL_ON_JOB_CLOSE` é ligado por `SetInformationJobObject`. `Invoke-WinForgeStreamedProcess` **pula a atribuição** quando `$sync.WinForgeStreamProtected[$StreamTo]` está ligado — quem liga essa chave é a Tarefa 12. `Invoke-WinForgeStreamedSteps` confere `Test-WinForgeStreamCancelled` antes de cada passo.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Parar: três hashtables sincronizadas, flag ignorada na janela protegida, guarda do Add-Type roda duas vezes e o job matou a árvore do filho` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: trocar `TerminateJobObject` por `$null` (não matar) e ver "o job NÃO matou a árvore" ficar vermelho; desfazer e confirmar o verde.
  - `KILL_ON_JOB_CLOSE` matando a árvore quando o WinForge é encerrado pelo Gerenciador de Tarefas é **teste manual**, e entra no roteiro da Tarefa 23.

- [ ] **Step 5: Commit**
  `feat(commands): cancelamento por Job Object, com a guarda do Add-Type dentro da runspace do pool`

---

### Task 12: A Fase 4 fora do job e o marcador de posse pendente

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — `Invoke-WinForgeAclOwnerFallback` (`:2919-2974`) e as três funções do marcador.
- Modify: `src/Engine/build.ps1` — a leitura do marcador entra no mesmo gancho de abertura da varredura da Tarefa 6; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 11.

**Interfaces:**
- Consumes: `Enter-WinForgeStreamProtected -Path <string>` / `Exit-WinForgeStreamProtected -Path <string>` e `Test-WinForgeStreamCancelled -Path <string> → <bool>` (Tarefa 11); `Invoke-WinForgeAclStreamStep -Path <string> -Step <hashtable> → <int>` (Tarefa 8).
- Produces:
  ```powershell
  Write-WinForgeAclOwnerPending -Folder <string> -OwnerSid <string> [-Root <string>] → @{ Ok; Reason; Path }
  Clear-WinForgeAclOwnerPending [-Root <string>] → @{ Ok; Reason }
  Get-WinForgeAclOwnerPending   [-Root <string>] → @{ Present = <bool>; Folder = <string>; OwnerSid = <string>; Stamp = <string>; Text = <string> }
  ```
  `-Root` existe pelo mesmo motivo de `Get-WinForgeAclBackupRoot`: sem ele o SelfTest escreveria em `%ProgramData%\WinForge`. O padrão é `%ProgramData%\WinForge`, e o arquivo é `acl-posse-pendente.json`. `Write-WinForgeAclOwnerPending` chama `Assert-WinForgeNotSelfTest`; `Get-WinForgeAclOwnerPending` **não escreve nada**.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Parar: a Fase 4 fora do job
    # KILL_ON_JOB_CLOSE mata a árvore quando o processo dono morre - que é exatamente o que a
    # proibição de cancelar na Fase 4 existe para impedir: morrer entre 'posse aos Admins' e 'posse
    # de volta' deixa uma pasta de sistema aberta a qualquer processo elevado.
    $wfF4Raiz = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\posse'
    try {
        if (Test-Path -LiteralPath $wfF4Raiz) { Remove-Item -LiteralPath $wfF4Raiz -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $wfF4Raiz -Force | Out-Null
        $wfF4Fonte = [string](Get-Command Invoke-WinForgeAclOwnerFallback).ScriptBlock
        if ($wfF4Fonte -notmatch 'Enter-WinForgeStreamProtected') { Write-Host "  [ERRO] Posse: Invoke-WinForgeAclOwnerFallback não abre a janela protegida" -ForegroundColor Red; $wbErrors++ }
        if ($wfF4Fonte -notmatch '(?s)finally\s*\{[^}]*Exit-WinForgeStreamProtected') { Write-Host "  [ERRO] Posse: a janela protegida não fecha no 'finally' - uma exceção deixaria o cancelamento morto para sempre" -ForegroundColor Red; $wbErrors++ }
        if ($wfF4Fonte -notmatch 'Write-WinForgeAclOwnerPending') { Write-Host "  [ERRO] Posse: o marcador não é escrito antes da troca de posse" -ForegroundColor Red; $wbErrors++ }
        if ($wfF4Fonte -notmatch 'Clear-WinForgeAclOwnerPending') { Write-Host "  [ERRO] Posse: o marcador não é apagado depois de devolver a posse" -ForegroundColor Red; $wbErrors++ }
        $wfF4PosMarca = $wfF4Fonte.IndexOf('Write-WinForgeAclOwnerPending', [StringComparison]::Ordinal)
        $wfF4PosTroca = $wfF4Fonte.IndexOf('setowner', [StringComparison]::Ordinal)
        if ($wfF4PosMarca -lt 0 -or $wfF4PosTroca -lt 0 -or $wfF4PosMarca -gt $wfF4PosTroca) { Write-Host "  [ERRO] Posse: o marcador é escrito DEPOIS da troca de posse - a janela sem marcador é justamente a que precisa dele" -ForegroundColor Red; $wbErrors++ }
        if ($wfF4Fonte -notmatch 'Invoke-WinForgeAclStreamStep') { Write-Host "  [ERRO] Posse: a Fase 4 ficou fora do fluxo ao vivo - ela é a fase que mais escreve" -ForegroundColor Red; $wbErrors++ }
        # Marcador: escrito ANTES da troca, apagado depois de devolver, e na abertura seguinte ele
        # RELATA - nunca conserta sozinho.
        $wfF4SelfAntes = $sync.SelfTest
        try {
            $sync.SelfTest = $false
            $wfF4Marca = Write-WinForgeAclOwnerPending -Folder 'C:\Windows' -OwnerSid 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' -Root $wfF4Raiz
        } finally { $sync.SelfTest = $wfF4SelfAntes }
        if (-not $wfF4Marca.Ok) { Write-Host "  [ERRO] Posse (marcador): a gravação falhou ('$($wfF4Marca.Reason)')" -ForegroundColor Red; $wbErrors++ }
        $wfF4Lido = Get-WinForgeAclOwnerPending -Root $wfF4Raiz
        if (-not $wfF4Lido.Present) { Write-Host "  [ERRO] Posse (marcador): o marcador plantado não foi lido" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF4Lido.Folder -ne 'C:\Windows') { Write-Host "  [ERRO] Posse (marcador): a pasta lida é '$($wfF4Lido.Folder)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfF4Lido.Text -notmatch 'Devolver ao padrão do Windows') { Write-Host "  [ERRO] Posse (marcador): o relato não oferece o botão ('$($wfF4Lido.Text)')" -ForegroundColor Red; $wbErrors++ }
        # E a gravação é o único ponto que escreve: com SelfTest ligado ela LANÇA.
        $wfF4Lancou = $false
        try { $null = Write-WinForgeAclOwnerPending -Folder 'C:\Windows' -OwnerSid 'S-1-5-18' -Root $wfF4Raiz } catch { $wfF4Lancou = $true }
        if (-not $wfF4Lancou) { Write-Host "  [ERRO] Posse (marcador): a gravação passou com `$sync.SelfTest ligado - falta Assert-WinForgeNotSelfTest" -ForegroundColor Red; $wbErrors++ }
        $wfF4FonteM = [string](Get-Command Get-WinForgeAclOwnerPending).ScriptBlock
        foreach ($wfF4Proibido in @('icacls', 'setowner', 'Remove-Item', 'Set-Content')) {
            if ($wfF4FonteM -match [regex]::Escape($wfF4Proibido)) { Write-Host "  [ERRO] Posse (marcador): a leitura da abertura ESCREVE ('$wfF4Proibido') - ela só relata" -ForegroundColor Red; $wbErrors++ }
        }
        $wfF4SelfAntes2 = $sync.SelfTest
        try { $sync.SelfTest = $false; $null = Clear-WinForgeAclOwnerPending -Root $wfF4Raiz } finally { $sync.SelfTest = $wfF4SelfAntes2 }
        if ((Get-WinForgeAclOwnerPending -Root $wfF4Raiz).Present) { Write-Host "  [ERRO] Posse (marcador): o marcador não foi apagado" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Posse: janela protegida aberta e fechada no finally, marcador escrito antes da troca, leitura da abertura só relata"
    } catch {
        Write-Host "  [ERRO] Posse: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath $wfF4Raiz -Recurse -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Posse: Invoke-WinForgeAclOwnerFallback não abre a janela protegida` e `[ERRO] Posse: O termo 'Write-WinForgeAclOwnerPending' não é reconhecido…`.

- [ ] **Step 3: Implementar**

  ```powershell
  # Os processos da Fase 4 NÃO entram no job: um job com KILL_ON_JOB_CLOSE mata a árvore quando o
  # dono morre, e é exatamente isso que a proibição de cancelar aqui existe para impedir. A janela
  # protegida abre ANTES da primeira troca de posse e fecha no finally - se ela ficasse aberta por
  # uma exceção, o Parar morreria para o resto da sessão.
  Enter-WinForgeStreamProtected -Path $arquivoSaida
  try {
      $null = Write-WinForgeAclOwnerPending -Folder $passo.Path -OwnerSid $donoOriginal
      # posse aos Administradores -> segunda tentativa -> posse de volta, tudo por
      # Invoke-WinForgeAclStreamStep (fluxo ao vivo, sem -StreamTo esta fase voltaria a materializar
      # a saída inteira numa linha só)
  } finally {
      $null = Clear-WinForgeAclOwnerPending
      Exit-WinForgeStreamProtected -Path $arquivoSaida
  }
  ```
  A leitura da abertura entra no mesmo gancho da varredura da Tarefa 6, em `DispatcherPriority::Background`: marcador presente → **relata** a pasta e o dono original e oferece o botão `Permissões do disco C: — Devolver ao padrão do Windows`, e **nunca conserta sozinho**.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Posse: janela protegida aberta e fechada no finally, marcador escrito antes da troca, leitura da abertura só relata` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: trocar o `Enter-WinForgeStreamProtected` de lugar para depois do `setowner` e ver "o marcador é escrito DEPOIS da troca de posse" ficar vermelho; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `fix(repair): fase 4 fora do job de cancelamento, com marcador de posse pendente relatado na abertura`

---

### Task 13: O botão Parar, os textos e o fechamento que cancela de verdade

**Files:**
- Modify: `src/Engine/winforge/wf-commands.ps1` — `Show-WinForgeOutputWindow` (barra de botões, `:727-770`), `Invoke-WinForgeFollowTick` (cabeçalho `Parando:`).
- Modify: `src/Engine/winforge/wf-repair.ps1` — textos de parada das fases 4 e 5.
- Modify: `src/Engine/build.ps1` — `Add_Closing` ("closing hook", `build.ps1:5923-5958`) passa a cancelar e esperar; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 12.

**Interfaces:**
- Consumes: `Request-WinForgeStreamCancel -Path <string> → @{ Ok; Reason }`, `Test-WinForgeStreamCancelled -Path <string> → <bool>` (Tarefa 11); `Get-WinForgeFollowHeader …` (Tarefa 10).
- Produces:
  ```powershell
  Get-WinForgeStreamStopText -Phase <'leitura'|'escrita'> → <string>              # texto da confirmação
  Get-WinForgeAclStopReport -Phase <int> -Folders <string[]> -Profile <string> → <string>
  ```
  O botão nasce em `Show-WinForgeOutputWindow` **só com `-FollowPath`**, pelo mesmo `$novoBotao` (`wf-commands.ps1:727`), **à esquerda do `Fechar`**, habilitado enquanto `$sync.WinForgeStreamDone[$path]` for falso. O nome registrado é `WFOutputStop`, para o SelfTest achá-lo por `FindName`.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Parar: botão e textos
    try {
        $wfBtnArq = Join-Path $wbSelfTestTemp 'WinForge-SelfTest\parar-botao.txt'
        Set-Content -LiteralPath $wfBtnArq -Value 'cab' -Encoding UTF8
        $sync.WinForgeStreamDone[$wfBtnArq] = $false
        $wfBtnJan = Show-WinForgeOutputWindow -Title 'Restaurar padrões' -FollowPath $wfBtnArq -Component 'Repair' -NoShow
        $wfBtnParar = $wfBtnJan.FindName('WFOutputStop')
        if ($null -eq $wfBtnParar) { Write-Host "  [ERRO] Parar (botão): a janela com -FollowPath não tem o botão Parar" -ForegroundColor Red; $wbErrors++ }
        else {
            if (-not $wfBtnParar.IsEnabled) { Write-Host "  [ERRO] Parar (botão): nasce desabilitado com o comando em andamento" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfBtnParar.Content -ne 'Parar') { Write-Host "  [ERRO] Parar (botão): o rótulo é '$($wfBtnParar.Content)'" -ForegroundColor Red; $wbErrors++ }
            $wfBtnBarra = $wfBtnParar.Parent
            $wfBtnIdx = $wfBtnBarra.Children.IndexOf($wfBtnParar)
            $wfBtnFechar = @($wfBtnBarra.Children | Where-Object { [string]$_.Content -eq 'Fechar' })[0]
            if ($wfBtnIdx -ge $wfBtnBarra.Children.IndexOf($wfBtnFechar)) { Write-Host "  [ERRO] Parar (botão): ele tem de ficar à ESQUERDA do Fechar" -ForegroundColor Red; $wbErrors++ }
        }
        # Sem -FollowPath não existe botão Parar: não há o que parar numa saída pronta.
        $wfBtnJan2 = Show-WinForgeOutputWindow -Title 'Saída pronta' -Text 'ok' -Component 'Repair' -NoShow
        if ($null -ne $wfBtnJan2.FindName('WFOutputStop')) { Write-Host "  [ERRO] Parar (botão): janela sem -FollowPath ganhou o botão" -ForegroundColor Red; $wbErrors++ }
        # Concluído desabilita o botão no tique seguinte.
        $sync.WinForgeStreamDone[$wfBtnArq] = $true
        $sync.WinForgeStreamExit[$wfBtnArq] = 0
        Invoke-WinForgeFollowTick -Window $wfBtnJan
        if ($null -ne $wfBtnParar -and $wfBtnParar.IsEnabled) { Write-Host "  [ERRO] Parar (botão): continua habilitado depois de concluído" -ForegroundColor Red; $wbErrors++ }
        # Os seis textos obrigatórios de §2, literais.
        $wfBtnLeitura = Get-WinForgeStreamStopText -Phase 'leitura'
        if ($wfBtnLeitura -notmatch 'Nada foi alterado até agora') { Write-Host "  [ERRO] Parar (texto): fase de leitura sem 'Nada foi alterado até agora'" -ForegroundColor Red; $wbErrors++ }
        $wfBtnEscrita = Get-WinForgeStreamStopText -Phase 'escrita'
        if ($wfBtnEscrita -notmatch 'Algumas pastas já foram alteradas; o Desfazer cobre todas elas') { Write-Host "  [ERRO] Parar (texto): fase de escrita sem a frase do Desfazer" -ForegroundColor Red; $wbErrors++ }
        $wfBtnF4 = Get-WinForgeAclStopReport -Phase 4 -Folders @('C:\Windows', 'C:\ProgramData') -Profile 'C:\Users\fulano'
        foreach ($wfBtnF in @('Parado a pedido', 'C:\Windows', 'as demais ficaram como estavam', 'O backup da Fase 2 está completo', 'Desfazer (restaurar backup)')) {
            if ($wfBtnF4 -notmatch [regex]::Escape($wfBtnF)) { Write-Host "  [ERRO] Parar (texto fase 4): falta '$wfBtnF'" -ForegroundColor Red; $wbErrors++ }
        }
        $wfBtnF5 = Get-WinForgeAclStopReport -Phase 5 -Folders @() -Profile 'C:\Users\fulano'
        foreach ($wfBtnF in @('Parado a pedido durante a herança do perfil', 'C:\Users\fulano', 'Rode a restauração de novo para terminar')) {
            if ($wfBtnF5 -notmatch [regex]::Escape($wfBtnF)) { Write-Host "  [ERRO] Parar (texto fase 5): falta '$wfBtnF'" -ForegroundColor Red; $wbErrors++ }
        }
        # Na janela protegida da Fase 4 o rótulo muda; a confirmação tem 'Não' como padrão.
        $wfBtnFonteJ = [string](Get-Command Show-WinForgeOutputWindow).ScriptBlock
        if ($wfBtnFonteJ -notmatch 'Parar \(aguarde alguns segundos\)') { Write-Host "  [ERRO] Parar (botão): falta o rótulo da janela protegida da Fase 4" -ForegroundColor Red; $wbErrors++ }
        if ($wfBtnFonteJ -notmatch 'Parando…') { Write-Host "  [ERRO] Parar (botão): falta o estado 'Parando…' desabilitado" -ForegroundColor Red; $wbErrors++ }
        if ($wfBtnFonteJ -notmatch 'MessageBoxResult\]::No') { Write-Host "  [ERRO] Parar (confirmação): 'Não' não é o padrão" -ForegroundColor Red; $wbErrors++ }
        $wfBtnFonteT = [string](Get-Command Invoke-WinForgeFollowTick).ScriptBlock
        if ($wfBtnFonteT -notmatch 'Parando: ') { Write-Host "  [ERRO] Parar (cabeçalho): falta 'Parando: <título> (mm:ss)'" -ForegroundColor Red; $wbErrors++ }
        # Cancelar na Fase 2 apaga os parciais e NÃO escreve o índice.
        $wfBtnFonteR = [string](Get-Command Invoke-WinForgeAclRestore).ScriptBlock
        $wfBtnPosCancel = $wfBtnFonteR.IndexOf('Test-WinForgeStreamCancelled', [StringComparison]::Ordinal)
        $wfBtnPosIndice = $wfBtnFonteR.IndexOf('acl-index-', [StringComparison]::Ordinal)
        if ($wfBtnPosCancel -lt 0 -or $wfBtnPosIndice -lt 0 -or $wfBtnPosCancel -gt $wfBtnPosIndice) { Write-Host "  [ERRO] Parar (fase 2): o cancelamento é conferido DEPOIS de o índice ser escrito - o Desfazer passaria a apontar para um conjunto pela metade" -ForegroundColor Red; $wbErrors++ }
        # O Add_Closing passa a CANCELAR e ESPERAR, e não só a perguntar.
        $wfBtnFonteF = [string](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'WinForge.ps1') -Raw -ErrorAction SilentlyContinue)
        if ([string]::IsNullOrWhiteSpace($wfBtnFonteF)) { $wfBtnFonteF = [string](Get-Content -LiteralPath $PSCommandPath -Raw -ErrorAction SilentlyContinue) }
        if ($wfBtnFonteF -notmatch 'Request-WinForgeStreamCancel') { Write-Host "  [ERRO] Parar (fechamento): o Add_Closing não cancela de verdade" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Parar (botão): à esquerda do Fechar, só com -FollowPath, desabilita no fim, seis textos literais e fechamento que cancela"
    } catch {
        Write-Host "  [ERRO] Parar (botão): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    } finally {
        Remove-Item -LiteralPath (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\parar-botao.txt') -Force -ErrorAction SilentlyContinue
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Parar (botão): a janela com -FollowPath não tem o botão Parar` e `[ERRO] Parar (botão): O termo 'Get-WinForgeStreamStopText' não é reconhecido…`.

- [ ] **Step 3: Implementar** — o botão, o clique e o fechamento. O trecho que decide o desenho:

  ```powershell
  # O clique é um scriptblock de ESCOPO DE ARQUIVO fechado sobre o caminho (.GetNewClosure()), como
  # os outros três botões desta janela: ele roda na thread da interface e nunca nasce dentro de uma
  # runspace do pool. Quem cancela é Request-WinForgeStreamCancel; quem obedece é o laço de passos.
  $btnParar.Add_Click({
      $fase = if ($sync.WinForgeStreamKind -eq 'repair' -and $sync.WinForgeStreamWriting) { 'escrita' } else { 'leitura' }
      $resp = [System.Windows.MessageBox]::Show($janela, (Get-WinForgeStreamStopText -Phase $fase), 'WinForge',
          [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
      if ($resp -ne [System.Windows.MessageBoxResult]::Yes) { return }
      $btnParar.Content = 'Parando…'
      $btnParar.IsEnabled = $false
      $null = Request-WinForgeStreamCancel -Path $caminhoSeguido
  }.GetNewClosure())
  ```
  Na janela protegida da Fase 4 o rótulo vira `Parar (aguarde alguns segundos)` (o tique troca o `Content` enquanto `$sync.WinForgeStreamProtected[$path]` estiver ligado). O `Add_Closing` (`build.ps1`, "closing hook") ganha, depois do "Sim": `Request-WinForgeStreamCancel` no caminho em andamento e uma espera curta (`while (-not $sync.WinForgeStreamDone[$p] -and $relogio.Elapsed.TotalSeconds -lt 10) { Start-Sleep -Milliseconds 200 }`) antes do `BeginClose`. A pergunta continua **antes** de `$sync.WinForgeClosing = $true` — a ordem que `build.ps1:3219-3223` já cobra.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Parar (botão): à esquerda do Fechar, só com -FollowPath, desabilita no fim, seis textos literais e fechamento que cancela` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(commands): botão Parar na janela de saída, com textos por fase e fechamento que cancela`

---

### Task 14: Rede — o rádio, as sondas e os nove bloqueios

**Files:**
- Create: `src/Engine/winforge/wf-net.ps1` — arquivo novo do motor (mesmo padrão de `wf-drivers.ps1`).
- Modify: `src/Engine/build.ps1` — leitura do arquivo novo junto dos outros de `winforge\` (mesmo ponto em que `wf-drivers.ps1` é lido); SelfTest.
- Test: `src/Engine/build.ps1`, bloco novo antes de `# ---------------------------------------------------------------- o cache do catálogo é de TELA` (`build.ps1:4457`).

**Interfaces:**
- Consumes: `Get-WinForgeSystemExe -Name <string> → <caminho>` (existente, `wf-commands.ps1:88`).
- Produces:
  ```powershell
  Test-WinForgeRemoteSession → <bool>                         # GetSystemMetrics(SM_REMOTESESSION = 0x1000)
  Get-WinForgeWifiAdapter [-Adapters <object[]>]
    → @{ Ok = <bool>; Reason = <string>; Name; ifIndex = <int>; Status; Problem; DriverProvider; PhysicalMediaType }
  Test-WinForgeTcpProbe -TargetHost <string> -Port <int> [-TimeoutMs 2000] → @{ Ok = <bool>; Ms = <int> }
  Test-WinForgeNetworkGuard -Action <'NetDnsRenew'|'WifiDriverReinstall'|'WifiDriverGeneric'|'WifiDriverRestore'> [-Facts <hashtable>]
    → @{ Ok = <bool>; Hidden = <bool>; Reason = <string>; Blocks = @(<string>) }
  ```
  `-Facts` é a porta do SelfTest: uma hashtable com `Remote`, `Build`, `OtherAdapter`, `Inbox`, `ExportOk`, `OnBattery`, `Virtual`, `Server`, `NeedRestart`, `FreeBytes`, `NeedBytes`. Sem ela, a função levanta os mesmos dados da máquina. `Hidden = $true` só acontece para `WifiDriverGeneric` sem driver inbox (a exceção D3 de §5.3).

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Rede: rádio, sondas e bloqueios
    # "Conectado certinho" prova que o rádio associou e autenticou: driver quebrado não associa. O
    # sintoma é DHCP/APIPA, DNS, rota, proxy ou filtro de software, nessa ordem.
    try {
        # O rádio é achado por mídia física, e não por nome: separa o rádio Intel dos sete
        # adaptadores virtuais de VPN desta máquina, e vale igual num Windows em inglês.
        $wfNetLista = @(
            [pscustomobject]@{ Name = 'VPN da empresa'; ifIndex = 3;  Status = 'Up';           Virtual = $true;  PhysicalMediaType = 'Unspecified'; DriverProvider = 'Terceiro' },
            [pscustomobject]@{ Name = 'Wi-Fi';          ifIndex = 12; Status = 'Up';           Virtual = $false; PhysicalMediaType = 'Native 802.11'; DriverProvider = 'Intel' },
            [pscustomobject]@{ Name = 'Ethernet';       ifIndex = 7;  Status = 'Disconnected'; Virtual = $false; PhysicalMediaType = '802.3';        DriverProvider = 'Realtek' }
        )
        $wfNetRadio = Get-WinForgeWifiAdapter -Adapters $wfNetLista
        if (-not $wfNetRadio.Ok) { Write-Host "  [ERRO] Rede (rádio): não achou o adaptador sem fio ('$($wfNetRadio.Reason)')" -ForegroundColor Red; $wbErrors++ }
        elseif ([int]$wfNetRadio.ifIndex -ne 12) { Write-Host "  [ERRO] Rede (rádio): escolheu ifIndex $($wfNetRadio.ifIndex), esperado 12" -ForegroundColor Red; $wbErrors++ }
        $wfNetSemRadio = Get-WinForgeWifiAdapter -Adapters @($wfNetLista[0], $wfNetLista[2])
        if ($wfNetSemRadio.Ok) { Write-Host "  [ERRO] Rede (rádio): achou rádio numa lista sem nenhum" -ForegroundColor Red; $wbErrors++ }
        $wfNetFonteA = [string](Get-Command Get-WinForgeWifiAdapter).ScriptBlock
        if ($wfNetFonteA -notmatch '802\.11') { Write-Host "  [ERRO] Rede (rádio): o filtro não é PhysicalMediaType '*802.11*'" -ForegroundColor Red; $wbErrors++ }
        if ($wfNetFonteA -match "Name\s*-like\s*'\*Wi-Fi\*'") { Write-Host "  [ERRO] Rede (rádio): filtro por NOME é dependente de idioma" -ForegroundColor Red; $wbErrors++ }
        # Sonda de TCP: nada de Test-NetConnection -Port (medido: 5.443 ms por chamada).
        $wfNetFonteS = [string](Get-Command Test-WinForgeTcpProbe).ScriptBlock
        if ($wfNetFonteS -match 'Test-NetConnection\s+[^|]*-Port') { Write-Host "  [ERRO] Rede (sonda): Test-NetConnection -Port leva 5,4 s por chamada" -ForegroundColor Red; $wbErrors++ }
        if ($wfNetFonteS -notmatch 'BeginConnect|InformationLevel') { Write-Host "  [ERRO] Rede (sonda): a sonda não usa TcpClient/BeginConnect nem -InformationLevel Quiet" -ForegroundColor Red; $wbErrors++ }
        $wfNetSonda = Test-WinForgeTcpProbe -TargetHost '127.0.0.1' -Port 9 -TimeoutMs 500
        if ([int]$wfNetSonda.Ms -gt 3000) { Write-Host "  [ERRO] Rede (sonda): $($wfNetSonda.Ms)ms com tempo limite de 500ms" -ForegroundColor Red; $wbErrors++ }
        # $env:SESSIONNAME veio VAZIA numa sessão de console legítima (Win11 26200): o teste
        # '-ne Console', conselho mais repetido da internet, bloquearia o botão para toda gente.
        $wfNetFonteRem = [string](Get-Command Test-WinForgeRemoteSession).ScriptBlock
        if ($wfNetFonteRem -match 'SESSIONNAME') { Write-Host "  [ERRO] Rede (sessão): o código usa `$env:SESSIONNAME - ele vem vazio em console legítimo" -ForegroundColor Red; $wbErrors++ }
        if ($wfNetFonteRem -notmatch 'GetSystemMetrics') { Write-Host "  [ERRO] Rede (sessão): falta GetSystemMetrics(0x1000)" -ForegroundColor Red; $wbErrors++ }
        # Os nove bloqueios, um a um, com fatos simulados.
        $wfNetBase = @{ Remote = $false; Build = 26200; OtherAdapter = $true; Inbox = $true; ExportOk = $true; OnBattery = $false; Virtual = $false; Server = $false; NeedRestart = $false; FreeBytes = 50GB; NeedBytes = 200MB }
        foreach ($wfNetCaso in @(
            @{ Nome = 'sessão remota';        Acao = 'WifiDriverReinstall'; Fato = @{ Remote = $true };        Match = 'de longe|remot' },
            @{ Nome = 'build 17763';          Acao = 'WifiDriverReinstall'; Fato = @{ Build = 17763 };         Match = '1903|17763|versão do Windows' },
            @{ Nome = 'sem outra via';        Acao = 'WifiDriverGeneric';   Fato = @{ OtherAdapter = $false }; Match = 'cabo' },
            @{ Nome = 'sem inbox';            Acao = 'WifiDriverGeneric';   Fato = @{ Inbox = $false };        Match = 'básico' },
            @{ Nome = 'falha ao exportar';    Acao = 'WifiDriverReinstall'; Fato = @{ ExportOk = $false };     Match = 'cópia' },
            @{ Nome = 'na bateria';           Acao = 'WifiDriverReinstall'; Fato = @{ OnBattery = $true };     Match = 'bateria' },
            @{ Nome = 'máquina virtual';      Acao = 'WifiDriverRestore';   Fato = @{ Virtual = $true };       Match = 'virtual' },
            @{ Nome = 'Windows Server';       Acao = 'WifiDriverRestore';   Fato = @{ Server = $true };        Match = 'Server' },
            @{ Nome = 'reiniciar antes';      Acao = 'WifiDriverReinstall'; Fato = @{ NeedRestart = $true };   Match = 'Reinicie' },
            @{ Nome = 'espaço em disco';      Acao = 'WifiDriverReinstall'; Fato = @{ FreeBytes = 10MB };      Match = '\d' })) {
            $wfNetFatos = @{} + $wfNetBase
            foreach ($wfNetK in $wfNetCaso.Fato.Keys) { $wfNetFatos[$wfNetK] = $wfNetCaso.Fato[$wfNetK] }
            $wfNetG = Test-WinForgeNetworkGuard -Action ([string]$wfNetCaso.Acao) -Facts $wfNetFatos
            if ($wfNetG.Ok) { Write-Host "  [ERRO] Rede (bloqueio): '$($wfNetCaso.Nome)' não bloqueou '$($wfNetCaso.Acao)'" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfNetG.Reason -notmatch [string]$wfNetCaso.Match) { Write-Host "  [ERRO] Rede (bloqueio): '$($wfNetCaso.Nome)' explicou com '$($wfNetG.Reason)'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfNetG.Reason -match 'continuar mesmo assim') { Write-Host "  [ERRO] Rede (bloqueio): '$($wfNetCaso.Nome)' oferece 'continuar mesmo assim'" -ForegroundColor Red; $wbErrors++ }
        }
        # Sem inbox, o botão 5 SOME (exceção D3); o 4 só avisa quando não há outra via.
        if (-not (Test-WinForgeNetworkGuard -Action 'WifiDriverGeneric' -Facts (@{} + $wfNetBase + @{ Inbox = $false })).Hidden) { Write-Host "  [ERRO] Rede (D3): sem driver inbox o botão 5 tem de SUMIR, não ficar desabilitado" -ForegroundColor Red; $wbErrors++ }
        $wfNetAviso = Test-WinForgeNetworkGuard -Action 'WifiDriverReinstall' -Facts (@{} + $wfNetBase + @{ OtherAdapter = $false })
        if (-not $wfNetAviso.Ok) { Write-Host "  [ERRO] Rede (bloqueio): 'nenhuma outra via' é ABSOLUTO no 5 e só AVISO no 4" -ForegroundColor Red; $wbErrors++ }
        if (-not @($wfNetAviso.Blocks).Count) { Write-Host "  [ERRO] Rede (bloqueio): o aviso do botão 4 não foi registrado em Blocks" -ForegroundColor Red; $wbErrors++ }
        # Build baixo tira os botões 4 e 5 da tela: '/remove-device' e '/scan-devices' só existem a
        # partir do 1903, e o README declara suporte a Windows 10 (inclui 1809/LTSC 2019).
        foreach ($wfNetBtn in @('WifiDriverReinstall', 'WifiDriverGeneric')) {
            if (-not (Test-WinForgeNetworkGuard -Action $wfNetBtn -Facts (@{} + $wfNetBase + @{ Build = 17763 })).Hidden) { Write-Host "  [ERRO] Rede (build): '$wfNetBtn' tem de sumir no build 17763" -ForegroundColor Red; $wbErrors++ }
        }
        if ((Test-WinForgeNetworkGuard -Action 'NetDnsRenew' -Facts (@{} + $wfNetBase + @{ Build = 17763 })).Hidden) { Write-Host "  [ERRO] Rede (build): o botão 3 não depende do 1903" -ForegroundColor Red; $wbErrors++ }
        if ((Test-WinForgeNetworkGuard -Action 'NetDnsRenew' -Facts $wfNetBase).Ok -ne $true) { Write-Host "  [ERRO] Rede (bloqueio): máquina saudável bloqueou o botão 3" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Rede (bloqueios): rádio por mídia física, sonda sem Test-NetConnection -Port, sessão remota por GetSystemMetrics, dez recusas sem 'continuar mesmo assim'"
    } catch {
        Write-Host "  [ERRO] Rede (bloqueios): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Rede (bloqueios): O termo 'Get-WinForgeWifiAdapter' não é reconhecido…`.

- [ ] **Step 3: Implementar** — `wf-net.ps1` novo. O trecho que decide o desenho:

  ```powershell
  # SM_REMOTESESSION = 0x1000. '$env:SESSIONNAME -ne "Console"' é o conselho mais repetido da
  # internet e está errado: medido no Win11 26200, a variável veio VAZIA numa sessão de console
  # legítima, e o teste bloquearia o botão para toda gente. A ressalva vai no texto: isto NÃO
  # detecta AnyDesk, TeamViewer e afins, que rodam na sessão de console.
  if (-not ('WfSysMetrics' -as [type])) {
      Add-Type -Namespace '' -Name 'WfSysMetrics' -MemberDefinition '[DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);'
  }
  return ([WfSysMetrics]::GetSystemMetrics(0x1000) -ne 0)
  ```
  Ordem dos bloqueios: do mais barato ao mais caro (sessão remota → build → VM/Server → reinício pendente → outra via de rede → bateria → espaço → inbox → exportação). Disparou: para, explica em pt-BR e **não oferece "continuar mesmo assim"**.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Rede (bloqueios): rádio por mídia física, sonda sem Test-NetConnection -Port, sessão remota por GetSystemMetrics, dez recusas sem 'continuar mesmo assim'` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(net): descoberta do rádio sem fio, sondas rápidas e os bloqueios de leitura`

---

### Task 15: `Rede — Diagnóstico completo` e o veredito de uma frase (Config 58 → 59)

**Files:**
- Modify: `src/Engine/winforge/wf-net.ps1` — `Get-WinForgeNetworkVerdict`, `Test-WinForgeWinsockCatalog`, `Invoke-WinForgeNetworkDiagnostic`.
- Modify: `src/Engine/winforge/wf-repair.ps1` — linha `'NetDiagFull'` em `Get-WinForgeRepairCommand`.
- Modify: `src/Engine/config/wf-repair-config.ps1` — `WPFWFRepNetDiagFull`.
- Modify: `src/Engine/build.ps1` — caso no switch; trava de Config `58` → `59`; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 14.

**Interfaces:**
- Consumes: `Get-WinForgeWifiAdapter`, `Test-WinForgeTcpProbe`, `Test-WinForgeRemoteSession` (Tarefa 14).
- Produces:
  ```powershell
  Test-WinForgeWinsockCatalog -Entries <object[]> → @{ Ok = <bool>; Third = @(@{ Name; Path; ChainLength }); Count = <int> }
  Get-WinForgeNetworkVerdict -Facts <hashtable> → <string>     # uma das cinco frases fechadas
  Invoke-WinForgeNetworkDiagnostic [-Facts <hashtable>] → <string>
  ```
  `Get-WinForgeRepairCommand -Name 'NetDiagFull'` devolve `Kind = 'read'`, `Stream = $true`, `Steps = @(@{ Function = 'Invoke-WinForgeNetworkDiagnostic' })`, `Title = 'Rede — Diagnóstico completo'`.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Rede: diagnóstico e veredito
    # O veredito é o texto mais lido do recurso, e sai de LISTA FECHADA: cinco frases, nenhuma
    # inventada na hora.
    try {
        $wfVerFrases = @{
            APIPA  = 'O computador não pegou endereço do roteador (está em 169.254.x.x). Comece por "Limpar cache de DNS e pegar endereço novo".'
            DNS    = 'O endereço está certo, mas o servidor de nomes configurado não responde e o 1.1.1.1 responde. O problema é o servidor de nomes, não o Wi-Fi.'
            Limpo  = 'Não encontrei nada errado na rede deste computador.'
            Fora   = 'O roteador entrega endereço e nome, mas nada sai para fora. O problema está no roteador ou no provedor, não neste computador.'
        }
        $wfVerBase = @{ Apipa = $false; DnsOk = $true; DnsPublicoOk = $true; SaidaOk = $true; Lsp = @() }
        if ((Get-WinForgeNetworkVerdict -Facts $wfVerBase) -ne $wfVerFrases.Limpo) { Write-Host "  [ERRO] Rede (veredito): máquina saudável deu '$(Get-WinForgeNetworkVerdict -Facts $wfVerBase)'" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeNetworkVerdict -Facts (@{} + $wfVerBase + @{ Apipa = $true })) -ne $wfVerFrases.APIPA) { Write-Host "  [ERRO] Rede (veredito): 169.254 não deu a frase do APIPA" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeNetworkVerdict -Facts (@{} + $wfVerBase + @{ DnsOk = $false })) -ne $wfVerFrases.DNS) { Write-Host "  [ERRO] Rede (veredito): DNS do sistema mudo com o 1.1.1.1 respondendo não deu a frase do servidor de nomes" -ForegroundColor Red; $wbErrors++ }
        if ((Get-WinForgeNetworkVerdict -Facts (@{} + $wfVerBase + @{ SaidaOk = $false })) -ne $wfVerFrases.Fora) { Write-Host "  [ERRO] Rede (veredito): sem saída não deu a frase do roteador/provedor" -ForegroundColor Red; $wbErrors++ }
        $wfVerLsp = Get-WinForgeNetworkVerdict -Facts (@{} + $wfVerBase + @{ Lsp = @(@{ Name = 'Norton Security'; Path = 'C:\Program Files\Norton\nlsp.dll'; Menu = 'Configurações → Firewall → Proteção da Rede' }) })
        if ($wfVerLsp -notmatch 'Há um filtro do Norton Security preso em todos os adaptadores') { Write-Host "  [ERRO] Rede (veredito): o filtro de terceiro não é nomeado ('$wfVerLsp')" -ForegroundColor Red; $wbErrors++ }
        if ($wfVerLsp -notmatch 'Configurações → Firewall → Proteção da Rede') { Write-Host "  [ERRO] Rede (veredito): o caminho de menu não aparece" -ForegroundColor Red; $wbErrors++ }
        if ($wfVerLsp -notmatch 'antes de mexer em driver') { Write-Host "  [ERRO] Rede (veredito): falta a ordem de testar antes de mexer em driver" -ForegroundColor Red; $wbErrors++ }
        # A ordem da escada: APIPA antes de DNS, DNS antes de saída, filtro antes de tudo que mexe
        # em driver. E o filtro NUNCA vira botão.
        $wfVerFonteD = [string](Get-Command Invoke-WinForgeNetworkDiagnostic).ScriptBlock
        if ($wfVerFonteD -match 'pnputil') { Write-Host "  [ERRO] Rede (diagnóstico): o botão 1 é de LEITURA e não chama o pnputil" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfVerProibido in @('Remove-Item', 'netsh winsock reset', 'delete-driver', 'remove-device')) {
            if ($wfVerFonteD -match [regex]::Escape($wfVerProibido)) { Write-Host "  [ERRO] Rede (diagnóstico): o botão 1 escreve ('$wfVerProibido')" -ForegroundColor Red; $wbErrors++ }
        }
        # Catálogo Winsock: a base medida é 28 entradas, todas mswsock.dll sob %SystemRoot%. Outro
        # caminho, ou Protocol Chain Length > 1, é LSP de terceiro.
        $wfVerCat = Test-WinForgeWinsockCatalog -Entries @(
            @{ Name = 'MSAFD Tcpip [TCP/IP]'; Path = (Join-Path $env:SystemRoot 'system32\mswsock.dll'); ChainLength = 1 },
            @{ Name = 'Norton LSP';           Path = 'C:\Program Files\Norton\nlsp.dll';                 ChainLength = 3 }
        )
        if ($wfVerCat.Ok) { Write-Host "  [ERRO] Rede (Winsock): um LSP de terceiro passou como catálogo limpo" -ForegroundColor Red; $wbErrors++ }
        if (@($wfVerCat.Third).Count -ne 1) { Write-Host "  [ERRO] Rede (Winsock): $(@($wfVerCat.Third).Count) filtro(s) de terceiro, esperado 1" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeWinsockCatalog -Entries @(@{ Name = 'MSAFD'; Path = (Join-Path $env:SystemRoot 'system32\mswsock.dll'); ChainLength = 1 })).Ok) { Write-Host "  [ERRO] Rede (Winsock): catálogo limpo foi acusado" -ForegroundColor Red; $wbErrors++ }
        # O botão roda INTEIRO nesta máquina e devolve uma das cinco frases.
        $wfVerSaida = [string](Invoke-WinForgeNetworkDiagnostic)
        if ([string]::IsNullOrWhiteSpace($wfVerSaida)) { Write-Host "  [ERRO] Rede (diagnóstico): a saída veio vazia" -ForegroundColor Red; $wbErrors++ }
        if (-not @($wfVerFrases.Values + 'Há um filtro do' | Where-Object { $wfVerSaida -match [regex]::Escape([string]$_) }).Count) { Write-Host "  [ERRO] Rede (diagnóstico): a saída não termina com uma das cinco frases" -ForegroundColor Red; $wbErrors++ }
        $wfVerCmd = Get-WinForgeRepairCommand -Name 'NetDiagFull'
        if ([string]$wfVerCmd.Kind -ne 'read') { Write-Host "  [ERRO] Rede (diagnóstico): a linha é '$($wfVerCmd.Kind)', esperado 'read'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfVerCmd.Title -ne 'Rede — Diagnóstico completo') { Write-Host "  [ERRO] Rede (diagnóstico): título '$($wfVerCmd.Title)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]::IsNullOrWhiteSpace([string]$sync.configs.feature.WPFWFRepNetDiagFull.Description)) { Write-Host "  [ERRO] Rede (diagnóstico): WPFWFRepNetDiagFull sem Description" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Rede (diagnóstico): cinco frases fechadas, filtro de terceiro nomeado com caminho de menu, catálogo Winsock conferido, botão roda inteiro"
    } catch {
        Write-Host "  [ERRO] Rede (diagnóstico): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Rede (diagnóstico): O termo 'Get-WinForgeNetworkVerdict' não é reconhecido…` e `Comando de reparo desconhecido: 'NetDiagFull'`.

- [ ] **Step 3: Implementar** — o relatório levanta, nesta ordem: rádio físico, perfil, IP/APIPA, rota, DNS do sistema contra `1.1.1.1`, NCSI, proxy, filtros NDIS, Winsock, MTU, IPv6 e problema de dispositivo. O trecho que decide o desenho:

  ```powershell
  # Lista FECHADA, e a ordem é a da escada: endereço antes de nome, nome antes de saída. O filtro
  # de antivírus vem na frente de tudo que mexe em driver, porque se ele é a causa, remover e
  # reinstalar o driver de WiFi NÃO conserta nada e ainda arrisca deixar a máquina sem rádio.
  if (@($Facts.Lsp).Count) { return ("Há um filtro do {0} preso em todos os adaptadores. Desligue-o em {1} e teste de novo antes de mexer em driver." -f @($Facts.Lsp)[0].Name, @($Facts.Lsp)[0].Menu) }
  if ($Facts.Apipa) { return 'O computador não pegou endereço do roteador (está em 169.254.x.x). Comece por "Limpar cache de DNS e pegar endereço novo".' }
  ```
  Entrada de config, texto literal do §6, e trava de Config `58` → `59`.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Entradas -> … | Config: 59 | …`, `Rede (diagnóstico): cinco frases fechadas, filtro de terceiro nomeado com caminho de menu, catálogo Winsock conferido, botão roda inteiro` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(net): diagnóstico completo de rede com veredito de uma frase`

---

### Task 16: `Rede — Limpar cache de DNS e pegar endereço novo` e o que o Redefinir não faz (Config 59 → 60)

**Files:**
- Modify: `src/Engine/winforge/wf-repair.ps1` — linha `'NetDnsRenew'` em `Get-WinForgeRepairCommand`; texto da linha de redefinição de rede que já existe (`ConfigKey = 'WPFFixesNetwork'`).
- Modify: `src/Engine/config/wf-repair-config.ps1` — `WPFWFRepNetDnsRenew`.
- Modify: `src/Engine/build.ps1` — caso no switch; trava de Config `59` → `60`; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 15.

**Interfaces:**
- Consumes: `Test-WinForgeNetworkGuard -Action 'NetDnsRenew' [-Facts <hashtable>] → @{ Ok; Hidden; Reason; Blocks }` (Tarefa 14); `Invoke-WinForgeStreamedSteps` (existente).
- Produces: linha `'NetDnsRenew'` com `Kind = 'repair'`, `Stream = $true`, `ExpectMinutes = 2` e quatro passos de executável, todos com `Encoding = 'utf8'` (netsh/ipconfig medidos em UTF-8, `wf-commands.ps1:201-240`).

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Rede: DNS e endereço novo
    try {
        $wfDnsCmd = Get-WinForgeRepairCommand -Name 'NetDnsRenew'
        if ([string]$wfDnsCmd.Title -ne 'Rede — Limpar cache de DNS e pegar endereço novo') { Write-Host "  [ERRO] Rede (DNS): título '$($wfDnsCmd.Title)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfDnsCmd.Kind -ne 'repair') { Write-Host "  [ERRO] Rede (DNS): a linha é '$($wfDnsCmd.Kind)', esperado 'repair'" -ForegroundColor Red; $wbErrors++ }
        $wfDnsPassos = @($wfDnsCmd.Steps)
        if ($wfDnsPassos.Count -ne 4) { Write-Host "  [ERRO] Rede (DNS): $($wfDnsPassos.Count) passo(s), esperado 4 (flushdns, release, renew, nbtstat -R)" -ForegroundColor Red; $wbErrors++ }
        $wfDnsLinha = @($wfDnsPassos | ForEach-Object { "$($_.FilePath) $(@($_.Arguments) -join ' ')" }) -join ' | '
        foreach ($wfDnsExig in @('/flushdns', '/release', '/renew', '-R')) {
            if ($wfDnsLinha -notmatch [regex]::Escape($wfDnsExig)) { Write-Host "  [ERRO] Rede (DNS): falta '$wfDnsExig' nos passos ('$wfDnsLinha')" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($wfDnsP in $wfDnsPassos) {
            if (-not ([System.IO.Path]::IsPathRooted([string]$wfDnsP.FilePath))) { Write-Host "  [ERRO] Rede (DNS): '$($wfDnsP.FilePath)' não é caminho absoluto do System32" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfDnsP.FilePath -notlike ([string][Environment]::SystemDirectory + '*')) { Write-Host "  [ERRO] Rede (DNS): '$($wfDnsP.FilePath)' está fora de [Environment]::SystemDirectory" -ForegroundColor Red; $wbErrors++ }
            foreach ($wfDnsA in @($wfDnsP.Arguments)) {
                if ([string]$wfDnsA -match '\$|\+') { Write-Host "  [ERRO] Rede (DNS): argumento montado por concatenação ('$wfDnsA')" -ForegroundColor Red; $wbErrors++ }
            }
        }
        # A simulação passa por ele sem redefinir a rede de quem compila, e o despacho recusa no SelfTest.
        $wfDnsSeco = @(Start-WinForgeStreamedCommand -Name 'NetDnsRenew' -Spec $wfDnsCmd -DryRun)
        if ($wfDnsSeco.Count -ne 4) { Write-Host "  [ERRO] Rede (DNS): a simulação devolveu $($wfDnsSeco.Count) linha(s)" -ForegroundColor Red; $wbErrors++ }
        if (-not @($wfDnsSeco | Where-Object { [string]$_ -like '[simulação]*' }).Count) { Write-Host "  [ERRO] Rede (DNS): a simulação não é prefixada" -ForegroundColor Red; $wbErrors++ }
        if ((Invoke-WinForgeRepairCommand -Name 'NetDnsRenew' -NoUI).Dispatched) { Write-Host "  [ERRO] Rede (DNS): a linha foi despachada no SelfTest" -ForegroundColor Red; $wbErrors++ }
        # O botão 2 (Redefinir, que já existe) ganha o texto do que NÃO faz.
        $wfDnsRedef = [string]$sync.configs.feature.WPFFixesNetwork.Description
        foreach ($wfDnsF in @('não reinstala driver', 'não troca o driver')) {
            if ($wfDnsRedef -match [regex]::Escape($wfDnsF)) { $wfDnsAchou = $true }
        }
        if (-not $wfDnsAchou) { Write-Host "  [ERRO] Rede (Redefinir): a descrição não diz o que ele NÃO faz ('$wfDnsRedef')" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Rede (DNS): quatro passos por caminho absoluto, nenhum argumento concatenado, simulação sem efeito e o Redefinir dizendo o que não faz"
    } catch {
        Write-Host "  [ERRO] Rede (DNS): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Rede (DNS): Comando de reparo desconhecido: 'NetDnsRenew'`.

- [ ] **Step 3: Implementar**

  ```powershell
  'NetDnsRenew' {
      return @{
          Title         = 'Rede — Limpar cache de DNS e pegar endereço novo'
          Requires      = (Get-WinForgeSystemExe -Name 'ipconfig.exe')
          Kind          = 'repair'
          Stream        = $true
          ExpectMinutes = 2
          Steps         = @(
              @{ FilePath = (Get-WinForgeSystemExe -Name 'ipconfig.exe'); Arguments = @('/flushdns'); Encoding = 'utf8' },
              @{ FilePath = (Get-WinForgeSystemExe -Name 'ipconfig.exe'); Arguments = @('/release');  Encoding = 'utf8' },
              @{ FilePath = (Get-WinForgeSystemExe -Name 'ipconfig.exe'); Arguments = @('/renew');    Encoding = 'utf8' },
              @{ FilePath = (Get-WinForgeSystemExe -Name 'nbtstat.exe');  Arguments = @('-R');        Encoding = 'utf8' }
          )
          Final   = 'Cache de nomes esvaziado e endereço pedido de novo ao roteador. Se o endereço continuar em 169.254, o problema está entre este computador e o roteador.'
          Confirm = 'Esvazia o cache de nomes, devolve o endereço atual ao roteador e pede outro no lugar. A rede cai por alguns segundos.'
      }
  }
  ```
  Entrada de config com o texto literal do §6; trava de Config `59` → `60`; a descrição do botão 2 ganha, no fim, a frase do que ele **não** faz (não reinstala driver, não troca driver, não mexe em antivírus).

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Entradas -> … | Config: 60 | …`, `Rede (DNS): quatro passos por caminho absoluto, nenhum argumento concatenado, simulação sem efeito e o Redefinir dizendo o que não faz` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(net): botão para limpar cache de DNS e pedir endereço novo`

---

### Task 17: `pnputil` — leitura do repositório, inbox, exportação e as três armadilhas medidas

**Files:**
- Create: `tests/samples/pnputil-enum-drivers-ptbr.txt` e `tests/samples/pnputil-enum-devices-net-problem-ptbr.txt` — capturas reais em pt-BR, copiadas do relatório de medição citado pela spec.
- Modify: `src/Engine/winforge/wf-net.ps1` — funções de leitura e exportação.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 16.

**Interfaces:**
- Consumes: `Get-WinForgeWifiAdapter …` (Tarefa 14).
- Produces:
  ```powershell
  Get-WinForgeDriverStoreEntry -Text <string>
    → @(@{ Published; Original; Provider; Class; Date; Version; IsOem = <bool> })
  Select-WinForgeWifiInboxDriver -Entries <object[]> → @{ Found = <bool>; Published = <string>; Oem = @(<string>) }
  Test-WinForgePnputilExit -ExitCode <int> → <bool>
  Test-WinForgePnputilProblem -Text <string> → @{ Any = <bool>; Devices = @(@{ Name; Problem }) }
  Export-WinForgeWifiDriverBackup -Published <string[]> -Root <string> [-DryRun]
    → @{ Ok = <bool>; Reason = <string>; Path = <string>; Files = <int>; Bytes = <long> }
  Get-WinForgeWifiDriverBackupSet [-Root <string>] → @{ Found = <bool>; Path = <string>; Stamp = <string>; Files = <int>; Bytes = <long> }
  ```
  A raiz é `[Environment]::GetFolderPath('CommonApplicationData')` + `WinForge\driver-backup\<oem##>-<carimbo>`, **nunca `$env:TEMP`**. Todo passo de `pnputil` leva `Encoding = 'ansi'`.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Rede: pnputil
    # A saída do pnputil é LOCALIZADA: os rótulos não servem de âncora, os valores sim. Dentro de
    # cada bloco, o primeiro valor terminado em '.inf' é o nome PUBLICADO; casa '^oem\d+\.inf$' ->
    # é de terceiro, não casa -> é inbox. Medido: o bloco do inbox tem UMA só linha '.inf', os OEM
    # têm duas ("Nome Original:" é a segunda, e confundi-la com um inbox some com o botão 5).
    try {
        $wfPnpAmostra = Join-Path (Get-Location) 'tests\samples\pnputil-enum-drivers-ptbr.txt'
        if (-not (Test-Path -LiteralPath $wfPnpAmostra)) { Write-Host "  [ERRO] Rede (pnputil): falta a amostra real em '$wfPnpAmostra'" -ForegroundColor Red; $wbErrors++ }
        else {
            $wfPnpTexto = [string](Get-Content -LiteralPath $wfPnpAmostra -Raw -Encoding UTF8)
            $wfPnpEnt = @(Get-WinForgeDriverStoreEntry -Text $wfPnpTexto)
            if ($wfPnpEnt.Count -lt 2) { Write-Host "  [ERRO] Rede (pnputil): a amostra rendeu $($wfPnpEnt.Count) entrada(s)" -ForegroundColor Red; $wbErrors++ }
            if (-not @($wfPnpEnt | Where-Object { [string]$_.Published -eq 'oem22.inf' }).Count) { Write-Host "  [ERRO] Rede (pnputil): 'oem22.inf' não foi encontrado na amostra" -ForegroundColor Red; $wbErrors++ }
            foreach ($wfPnpE in $wfPnpEnt) {
                if ([string]$wfPnpE.Published -notmatch '\.inf$') { Write-Host "  [ERRO] Rede (pnputil): entrada sem nome publicado ('$($wfPnpE.Published)')" -ForegroundColor Red; $wbErrors++ }
                if (([string]$wfPnpE.Published -match '^oem\d+\.inf$') -ne [bool]$wfPnpE.IsOem) { Write-Host "  [ERRO] Rede (pnputil): IsOem errado para '$($wfPnpE.Published)'" -ForegroundColor Red; $wbErrors++ }
            }
            $wfPnpInbox = Select-WinForgeWifiInboxDriver -Entries $wfPnpEnt
            if (-not $wfPnpInbox.Found) { Write-Host "  [ERRO] Rede (pnputil): a amostra tem um inbox e ele não foi achado" -ForegroundColor Red; $wbErrors++ }
            elseif ([string]$wfPnpInbox.Published -match '^oem\d+\.inf$') { Write-Host "  [ERRO] Rede (pnputil): o 'inbox' achado é um oem ('$($wfPnpInbox.Published)') - a linha 'Nome Original:' do bloco OEM foi confundida com um inbox" -ForegroundColor Red; $wbErrors++ }
            if (@($wfPnpEnt | Where-Object { -not $_.IsOem }).Count -ne 1) { Write-Host "  [ERRO] Rede (pnputil): $(@($wfPnpEnt | Where-Object { -not $_.IsOem }).Count) inbox na amostra, esperado exatamente 1" -ForegroundColor Red; $wbErrors++ }
            # Sem inbox, o botão 5 some (a decisão é de Test-WinForgeNetworkGuard, a informação é daqui).
            $wfPnpSoOem = Select-WinForgeWifiInboxDriver -Entries @($wfPnpEnt | Where-Object { $_.IsOem })
            if ($wfPnpSoOem.Found) { Write-Host "  [ERRO] Rede (pnputil): achou inbox numa lista só de oem" -ForegroundColor Red; $wbErrors++ }
        }
        # (a) '$LASTEXITCODE -gt 0' transformaria -536870340 em SUCESSO, e o código seguiria para o
        # delete-driver. Só 0 é sucesso.
        foreach ($wfPnpCod in @(0, 1, -536870340, 3010)) {
            $wfPnpOk = Test-WinForgePnputilExit -ExitCode $wfPnpCod
            if ($wfPnpCod -eq 0 -and -not $wfPnpOk) { Write-Host "  [ERRO] Rede (pnputil): código 0 recusado" -ForegroundColor Red; $wbErrors++ }
            if ($wfPnpCod -ne 0 -and $wfPnpOk) { Write-Host "  [ERRO] Rede (pnputil): código $wfPnpCod aceito como sucesso" -ForegroundColor Red; $wbErrors++ }
        }
        # (c) '/enum-devices /class Net /problem' achou dispositivo em falha e SAIU COM CÓDIGO 0:
        # é obrigatório interpretar a saída.
        $wfPnpProbArq = Join-Path (Get-Location) 'tests\samples\pnputil-enum-devices-net-problem-ptbr.txt'
        if (-not (Test-Path -LiteralPath $wfPnpProbArq)) { Write-Host "  [ERRO] Rede (pnputil): falta a amostra real em '$wfPnpProbArq'" -ForegroundColor Red; $wbErrors++ }
        else {
            $wfPnpProb = Test-WinForgePnputilProblem -Text ([string](Get-Content -LiteralPath $wfPnpProbArq -Raw -Encoding UTF8))
            if (-not $wfPnpProb.Any) { Write-Host "  [ERRO] Rede (pnputil): a amostra tem dispositivo em falha e a leitura disse que não" -ForegroundColor Red; $wbErrors++ }
            if (-not @($wfPnpProb.Devices).Count) { Write-Host "  [ERRO] Rede (pnputil): nenhum dispositivo nomeado no relato de falha" -ForegroundColor Red; $wbErrors++ }
        }
        if ((Test-WinForgePnputilProblem -Text '').Any) { Write-Host "  [ERRO] Rede (pnputil): saída vazia virou dispositivo em falha" -ForegroundColor Red; $wbErrors++ }
        # (b) decodificação ANSI, não OEM: o pnputil escreve CP1252 quando redirecionado.
        $wfPnpFonteE = [string](Get-Command Export-WinForgeWifiDriverBackup).ScriptBlock
        if ($wfPnpFonteE -notmatch "Encoding\s*=\s*'ansi'") { Write-Host "  [ERRO] Rede (pnputil): o passo não leva Encoding = 'ansi'" -ForegroundColor Red; $wbErrors++ }
        if ($wfPnpFonteE -match "Encoding\s*=\s*'oem'") { Write-Host "  [ERRO] Rede (pnputil): 'oem' embaralha o acento da saída do pnputil" -ForegroundColor Red; $wbErrors++ }
        # '/force' nunca; '/reboot' nunca.
        foreach ($wfPnpFn in @('Export-WinForgeWifiDriverBackup', 'Get-WinForgeWifiDriverBackupSet')) {
            $wfPnpF = [string](Get-Command $wfPnpFn).ScriptBlock
            foreach ($wfPnpProibido in @('/force', '/reboot')) {
                if ($wfPnpF -match [regex]::Escape($wfPnpProibido)) { Write-Host "  [ERRO] Rede (pnputil): '$wfPnpProibido' aparece em $wfPnpFn - é a diferença entre 'não deu, nada mudou' e 'não deu, e agora não há driver'" -ForegroundColor Red; $wbErrors++ }
            }
        }
        # As QUATRO conferências depois do comando, e o destino nunca é o %TEMP%.
        foreach ($wfPnpConf in @('LASTEXITCODE|ExitCode', '\.inf', '\.cat', 'Bytes')) {
            if ($wfPnpFonteE -notmatch $wfPnpConf) { Write-Host "  [ERRO] Rede (exportação): falta a conferência '$wfPnpConf'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfPnpFonteE -match '\$env:TEMP') { Write-Host "  [ERRO] Rede (exportação): o backup de 120 MB não pode ir para o %TEMP%" -ForegroundColor Red; $wbErrors++ }
        if ($wfPnpFonteE -notmatch 'CommonApplicationData') { Write-Host "  [ERRO] Rede (exportação): a raiz não é GetFolderPath('CommonApplicationData')" -ForegroundColor Red; $wbErrors++ }
        # Exportação com destino inexistente aborta SEM TOCAR EM NADA.
        $wfPnpSeco = Export-WinForgeWifiDriverBackup -Published @('oem22.inf') -Root (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\driver-backup') -DryRun
        if ($wfPnpSeco.Ok -and $wfPnpSeco.Files -gt 0) { Write-Host "  [ERRO] Rede (exportação): o -DryRun exportou arquivo" -ForegroundColor Red; $wbErrors++ }
        # Sem pasta de backup, o botão 6 não tem o que restaurar.
        if ((Get-WinForgeWifiDriverBackupSet -Root (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\driver-backup-vazio')).Found) { Write-Host "  [ERRO] Rede (backup): achou cópia numa pasta que não existe" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Rede (pnputil): amostra pt-BR com oem22.inf e exatamente 1 inbox, só código 0 é sucesso, saída interpretada, decodificação ansi, sem /force e sem /reboot"
    } catch {
        Write-Host "  [ERRO] Rede (pnputil): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Rede (pnputil): falta a amostra real em '…\tests\samples\pnputil-enum-drivers-ptbr.txt'` e `[ERRO] Rede (pnputil): O termo 'Get-WinForgeDriverStoreEntry' não é reconhecido…`.

- [ ] **Step 3: Implementar**
  - As duas amostras vêm das capturas de `pnputil /enum-drivers` e `pnputil /enum-devices /class Net /problem` guardadas no relatório de medição da spec; são gravadas em UTF-8 com BOM e commitadas. Elas precisam conter, no mínimo: um bloco OEM com `Nome Publicado: oem22.inf` **e** `Nome Original: netwtw10.inf` (duas linhas `.inf`), um segundo bloco OEM, e um bloco de inbox com **uma só** linha `.inf`.
  - O trecho que decide o desenho:
    ```powershell
    # Blocos separados por linha em branco; dentro de cada um, o PRIMEIRO valor terminado em '.inf'
    # é o nome publicado. Os RÓTULOS não servem de âncora ("Published Name" / "Nome Publicado" /
    # "Nome do arquivo INF publicado" conforme a versão e o idioma); os VALORES servem.
    foreach ($bloco in ($Text -split "(\r?\n){2,}")) {
        $infs = @([regex]::Matches($bloco, '(?m)^\s*[^:\r\n]+:\s*(\S+\.inf)\s*$') | ForEach-Object { $_.Groups[1].Value })
        if (-not $infs.Count) { continue }
        $publicado = [string]$infs[0]
        $entradas += @{ Published = $publicado; Original = $(if ($infs.Count -gt 1) { [string]$infs[1] } else { '' }); IsOem = [bool]($publicado -match '^oem\d+\.inf$'); … }
    }
    ```
  - `Get-WindowsDriver -Online -All` tem `.Inbox`, mas **exige elevação** e por isso não serve ao SelfTest — o comentário registra isso.
  - `Export-WinForgeWifiDriverBackup` roda `pnputil /export-driver <oem##.inf> <destino>` e, depois, as quatro conferências: `Test-WinForgePnputilExit`, `.inf` no destino, `.cat` no destino, total em bytes coerente. Qualquer uma falhar → **abortar sem tocar em nada**, com o tamanho medido na tela (o export medido deu 10 arquivos e 120 MB, com `WiFi.msi` e um `Setup.exe` de 17 MB).

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Rede (pnputil): amostra pt-BR com oem22.inf e exatamente 1 inbox, só código 0 é sucesso, saída interpretada, decodificação ansi, sem /force e sem /reboot` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: trocar `Test-WinForgePnputilExit` por `$code -gt 0` e ver "código -536870340 aceito como sucesso" ficar vermelho; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `feat(net): leitura do repositório de drivers e exportação conferida, com as armadilhas do pnputil`

---

### Task 18: Botões 4 e 6 — reinstalar o driver que já está e voltar para o que estava antes (Config 60 → 62)

> O botão 6 é a condição para os 4 e 5 existirem: sem volta, não se oferece a ida. Por isso os dois nascem juntos.

**Files:**
- Modify: `src/Engine/winforge/wf-net.ps1` — `Invoke-WinForgeWifiDriverReinstall`, `Invoke-WinForgeWifiDriverRestore`, `Test-WinForgeWifiOutcome`.
- Modify: `src/Engine/winforge/wf-repair.ps1` — linhas `'WifiDriverReinstall'` e `'WifiDriverRestore'`.
- Modify: `src/Engine/config/wf-repair-config.ps1` — `WPFWFRepWifiDriverReinstall` e `WPFWFRepWifiDriverRestore`.
- Modify: `src/Engine/build.ps1` — dois casos no switch; trava de Config `60` → `62`; habilitação do botão 6 no gancho de abertura; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 17.

**Interfaces:**
- Consumes: `Get-WinForgeWifiAdapter …`, `Test-WinForgeNetworkGuard -Action <string> [-Facts <hashtable>]` (Tarefa 14); `Export-WinForgeWifiDriverBackup -Published <string[]> -Root <string> [-DryRun]`, `Get-WinForgeWifiDriverBackupSet [-Root <string>]`, `Test-WinForgePnputilExit -ExitCode <int>` (Tarefa 17).
- Produces:
  ```powershell
  Test-WinForgeWifiOutcome -Adapter <object> [-Generic] → @{ Outcome = 'ok'|'restaurar'|'sumiu'; Text = <string> }
  Invoke-WinForgeWifiDriverReinstall [-DryRun] [-Facts <hashtable>] → @(<string>)
  Invoke-WinForgeWifiDriverRestore   [-DryRun] [-Facts <hashtable>] → @(<string>)
  ```
  `-Generic` é o que separa os dois usos da mesma verificação: sem ele (botões 4 e 6) o desfecho bom é presente + `Status` em `Up`/`Disconnected` + `Problem = CM_PROB_NONE`; **com** ele (botão 5, Tarefa 19) exige também `DriverProvider = 'Microsoft'`, porque sem o fornecedor não se distingue "o básico entrou" de "outro OEM venceu". O parâmetro nasce aqui, cobrado por comportamento, e a Tarefa 19 só o usa.
  `Outcome = 'ok'` exige presente **e** `Status` em `Up`/`Disconnected`; `'restaurar'` (problema diferente de `CM_PROB_NONE`) e `'sumiu'` disparam **restauração imediata, sem perguntar** — inclusive no botão 4, porque em notebook sem Ethernet mandar clicar num botão para voltar é mandar clicar sem rede.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Rede: botões 4 e 6
    try {
        foreach ($wfW46 in @(
            @{ Nome = 'WifiDriverReinstall'; Titulo = 'Rede sem fio — Reinstalar o driver que já está instalado' },
            @{ Nome = 'WifiDriverRestore';   Titulo = 'Rede sem fio — Voltar para o driver que estava antes' })) {
            $wfW46Cmd = Get-WinForgeRepairCommand -Name ([string]$wfW46.Nome)
            if ([string]$wfW46Cmd.Title -ne [string]$wfW46.Titulo) { Write-Host "  [ERRO] Rede (botões 4/6): título de '$($wfW46.Nome)' é '$($wfW46Cmd.Title)'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfW46Cmd.Kind -ne 'repair') { Write-Host "  [ERRO] Rede (botões 4/6): '$($wfW46.Nome)' é '$($wfW46Cmd.Kind)'" -ForegroundColor Red; $wbErrors++ }
            if ([string]$wfW46Cmd.Requires -ne (Get-WinForgeSystemExe -Name 'pnputil.exe')) { Write-Host "  [ERRO] Rede (botões 4/6): '$($wfW46.Nome)' não exige o pnputil do System32" -ForegroundColor Red; $wbErrors++ }
            if ((Invoke-WinForgeRepairCommand -Name ([string]$wfW46.Nome) -NoUI).Dispatched) { Write-Host "  [ERRO] Rede (botões 4/6): '$($wfW46.Nome)' foi despachado no SelfTest" -ForegroundColor Red; $wbErrors++ }
            if ([string]::IsNullOrWhiteSpace([string]$sync.configs.feature."WPFWFRep$($wfW46.Nome)".Description)) { Write-Host "  [ERRO] Rede (botões 4/6): WPFWFRep$($wfW46.Nome) sem Description" -ForegroundColor Red; $wbErrors++ }
        }
        # Os três desfechos da verificação. Sem o fornecedor não se distingue "o básico entrou" de
        # "outro OEM venceu".
        $wfW46Ok = Test-WinForgeWifiOutcome -Adapter ([pscustomobject]@{ Ok = $true; Status = 'Disconnected'; Problem = 'CM_PROB_NONE'; DriverProvider = 'Microsoft'; Name = 'Wi-Fi' })
        if ([string]$wfW46Ok.Outcome -ne 'ok') { Write-Host "  [ERRO] Rede (desfecho): adaptador são deu '$($wfW46Ok.Outcome)'" -ForegroundColor Red; $wbErrors++ }
        $wfW46Prob = Test-WinForgeWifiOutcome -Adapter ([pscustomobject]@{ Ok = $true; Status = 'Disconnected'; Problem = 'CM_PROB_FAILED_INSTALL'; DriverProvider = 'Microsoft'; Name = 'Wi-Fi' })
        if ([string]$wfW46Prob.Outcome -ne 'restaurar') { Write-Host "  [ERRO] Rede (desfecho): CM_PROB_FAILED_INSTALL deu '$($wfW46Prob.Outcome)' - o usuário não tem como julgar esse código" -ForegroundColor Red; $wbErrors++ }
        $wfW46Sumiu = Test-WinForgeWifiOutcome -Adapter ([pscustomobject]@{ Ok = $false; Reason = 'nenhum adaptador sem fio' })
        if ([string]$wfW46Sumiu.Outcome -ne 'sumiu') { Write-Host "  [ERRO] Rede (desfecho): adaptador ausente deu '$($wfW46Sumiu.Outcome)'" -ForegroundColor Red; $wbErrors++ }
        # A exigência de 'DriverProvider = Microsoft' é cobrada POR COMPORTAMENTO, e não por um
        # '-match "Microsoft"' na fonte - que casaria com o próprio comentário que a explica. Mesmo
        # adaptador, duas respostas, e o que muda é só o fornecedor.
        $wfW46Intel = [pscustomobject]@{ Ok = $true; Status = 'Up'; Problem = 'CM_PROB_NONE'; DriverProvider = 'Intel'; Name = 'Wi-Fi' }
        if ([string](Test-WinForgeWifiOutcome -Adapter $wfW46Intel).Outcome -ne 'ok') { Write-Host "  [ERRO] Rede (desfecho): sem -Generic, um rádio são com driver Intel tem de dar 'ok' (é o caso do botão 4)" -ForegroundColor Red; $wbErrors++ }
        if ([string](Test-WinForgeWifiOutcome -Adapter $wfW46Intel -Generic).Outcome -eq 'ok') { Write-Host "  [ERRO] Rede (desfecho): com -Generic, driver 'Intel' foi aceito como sucesso - não se distingue 'o básico entrou' de 'outro OEM venceu'" -ForegroundColor Red; $wbErrors++ }
        if ([string](Test-WinForgeWifiOutcome -Adapter ([pscustomobject]@{ Ok = $true; Status = 'Up'; Problem = 'CM_PROB_NONE'; DriverProvider = 'Microsoft'; Name = 'Wi-Fi' }) -Generic).Outcome -ne 'ok') { Write-Host "  [ERRO] Rede (desfecho): com -Generic, o driver da Microsoft foi recusado" -ForegroundColor Red; $wbErrors++ }
        # E as duas funções são CHAMADAS, não só lidas: em simulação, com fatos que bloqueiam,
        # elas têm de recusar e dizer por quê.
        $wfW46Seco4 = @(Invoke-WinForgeWifiDriverReinstall -DryRun -Facts @{ Remote = $false; Build = 26200; OtherAdapter = $true; Inbox = $true; ExportOk = $true; OnBattery = $true; Virtual = $false; Server = $false; NeedRestart = $false; FreeBytes = 50GB; NeedBytes = 200MB })
        if (-not @($wfW46Seco4 | Where-Object { [string]$_ -match 'bateria' }).Count) { Write-Host "  [ERRO] Rede (botão 4): a simulação na bateria não recusou dizendo por quê ('$($wfW46Seco4 -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        if (@($wfW46Seco4 | Where-Object { [string]$_ -match 'remove-device' }).Count) { Write-Host "  [ERRO] Rede (botão 4): a simulação bloqueada ainda listou o '/remove-device'" -ForegroundColor Red; $wbErrors++ }
        # O botão 4 tem a MESMA restauração automática do 5.
        $wfW46Fonte4 = [string](Get-Command Invoke-WinForgeWifiDriverReinstall).ScriptBlock
        if ($wfW46Fonte4 -notmatch 'Invoke-WinForgeWifiDriverRestore') { Write-Host "  [ERRO] Rede (botão 4): sem restauração automática no desfecho ruim" -ForegroundColor Red; $wbErrors++ }
        if ($wfW46Fonte4 -notmatch 'Export-WinForgeWifiDriverBackup') { Write-Host "  [ERRO] Rede (botão 4): não exporta antes de remover" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfW46Passo in @('/remove-device', '/scan-devices')) {
            if ($wfW46Fonte4 -notmatch [regex]::Escape($wfW46Passo)) { Write-Host "  [ERRO] Rede (botão 4): falta '$wfW46Passo'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfW46Fonte4 -match 'delete-driver') { Write-Host "  [ERRO] Rede (botão 4): ele NÃO apaga pacote - isso é o botão 5" -ForegroundColor Red; $wbErrors++ }
        # '/install' PROPÕE, não impõe: o texto do 6 não pode afirmar 'driver restaurado'.
        $wfW46Fonte6 = [string](Get-Command Invoke-WinForgeWifiDriverRestore).ScriptBlock
        if ($wfW46Fonte6 -match '[Dd]river restaurado') { Write-Host "  [ERRO] Rede (botão 6): o texto afirma 'driver restaurado' - o '/install' apenas propõe" -ForegroundColor Red; $wbErrors++ }
        if ($wfW46Fonte6 -notmatch 'Get-WinForgeWifiAdapter') { Write-Host "  [ERRO] Rede (botão 6): não confere o adaptador depois" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfW46F in @('cabo de rede', 'pen drive')) {
            if ($wfW46Fonte6 -notmatch [regex]::Escape($wfW46F)) { Write-Host "  [ERRO] Rede (botão 6): sem rádio no fim, o texto não manda '$wfW46F'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfW46Fonte6 -notmatch 'add-driver') { Write-Host "  [ERRO] Rede (botão 6): falta o '/add-driver … /install'" -ForegroundColor Red; $wbErrors++ }
        # Sem cópia conferida em disco, o botão 6 fica DESABILITADO (não some: a exceção D3 vale só
        # para o botão 5) e a dica diz por quê.
        $wfW46Seco = @(Invoke-WinForgeWifiDriverRestore -DryRun -Facts @{ BackupRoot = (Join-Path $wbSelfTestTemp 'WinForge-SelfTest\driver-backup-vazio') })
        if (-not @($wfW46Seco | Where-Object { [string]$_ -match 'nenhuma cópia' }).Count) { Write-Host "  [ERRO] Rede (botão 6): sem cópia em disco ele não diz isso ('$($wfW46Seco -join ' | ')')" -ForegroundColor Red; $wbErrors++ }
        $wfW46Guarda = Test-WinForgeNetworkGuard -Action 'WifiDriverRestore' -Facts @{ Remote = $false; Build = 26200; OtherAdapter = $true; Inbox = $true; ExportOk = $true; OnBattery = $false; Virtual = $false; Server = $false; NeedRestart = $false; FreeBytes = 50GB; NeedBytes = 200MB; BackupFound = $false }
        if ($wfW46Guarda.Hidden) { Write-Host "  [ERRO] Rede (botão 6): ele SOME sem cópia - a exceção de interface vale só para o botão 5" -ForegroundColor Red; $wbErrors++ }
        if ($wfW46Guarda.Ok) { Write-Host "  [ERRO] Rede (botão 6): sem cópia conferida ele continua habilitado" -ForegroundColor Red; $wbErrors++ }
        # A ressalva de AnyDesk/TeamViewer entra na confirmação do botão 4 (a do 5 é cobrada pelo
        # teste da Tarefa 19, junto da linha que a cria).
        $wfW46C = [string](Get-WinForgeRepairCommand -Name 'WifiDriverReinstall').Confirm
        if ($wfW46C -notmatch 'AnyDesk') { Write-Host "  [ERRO] Rede (botão 4): a confirmação não avisa que AnyDesk e TeamViewer não são detectados" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Rede (botões 4 e 6): exportar antes de remover, três desfechos, restauração automática também no 4, '/install' que propõe e botão 6 desabilitado sem cópia"
    } catch {
        Write-Host "  [ERRO] Rede (botões 4/6): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```
  Este bloco **não** cita `WifiDriverGeneric` em lugar nenhum: tudo que dependia dele foi para o teste da Tarefa 19, que é quem cria a linha. Assim a Tarefa 18 fecha verde sozinha — e por isso ela **não** é um par indivisível como a 3 + 4: entregar os botões 4 e 6 sem o 5 deixa o produto incompleto, não pior. O que a spec §5 exige é o contrário (o 6 é a condição para o 4 e o 5), e é justamente o 6 que sai aqui, junto do 4.

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Rede (botões 4/6): Comando de reparo desconhecido: 'WifiDriverReinstall'`.

- [ ] **Step 3: Implementar** — as duas linhas, as duas entradas de config com os textos literais do §6, os dois casos no switch e a trava de Config `60` → `62`. O trecho que decide o desenho:

  ```powershell
  # Os três desfechos, e por que o ruim NÃO pergunta: 'CM_PROB_FAILED_INSTALL' não é uma decisão
  # que o dono da máquina tenha como tomar, e a máquina em que ele apareceria é justamente a que
  # está sem rede para pesquisar o que ele significa.
  switch ($true) {
      (-not $Adapter.Ok)                              { return @{ Outcome = 'sumiu';     Text = 'O adaptador sem fio sumiu da lista. Devolvendo o driver anterior agora, sem perguntar.' } }
      ([string]$Adapter.Problem -ne 'CM_PROB_NONE')   { return @{ Outcome = 'restaurar'; Text = "O adaptador voltou com problema ($($Adapter.Problem)). Devolvendo o driver anterior agora, sem perguntar." } }
      ([string]$Adapter.Status -notin @('Up', 'Disconnected')) { return @{ Outcome = 'restaurar'; Text = "O adaptador voltou em '$($Adapter.Status)'. Devolvendo o driver anterior agora, sem perguntar." } }
      # -Generic: só aqui o fornecedor entra. No botão 4 o driver que volta é o MESMO de antes
      # (Intel, Realtek, o que for) e exigir 'Microsoft' reprovaria todo sucesso legítimo.
      ($Generic -and [string]$Adapter.DriverProvider -ne 'Microsoft') { return @{ Outcome = 'restaurar'; Text = "Quem assumiu o adaptador foi '$($Adapter.DriverProvider)', e não o driver básico do Windows. Devolvendo o driver anterior agora, sem perguntar." } }
      default                                          { return @{ Outcome = 'ok';        Text = "O adaptador '$($Adapter.Name)' está presente e responde (fornecedor do driver: $($Adapter.DriverProvider))." } }
  }
  ```
  O botão 6 é **desabilitado**, e não escondido, quando `Get-WinForgeWifiDriverBackupSet` não acha cópia conferida: a regra do projeto é "botão desabilitado, não removido", e a exceção registrada em §5.3 vale **só para o botão 5**. A dica diz: *"Aparece habilitado depois que 'Reinstalar' ou 'Trocar pelo driver básico' guardarem uma cópia conferida em disco."*

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Entradas -> … | Config: 62 | …`, `Rede (botões 4 e 6): exportar antes de remover, três desfechos, restauração automática também no 4, '/install' que propõe e botão 6 desabilitado sem cópia` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(net): reinstalar o driver de WiFi instalado e voltar para o driver anterior`

---

### Task 19: Botão 5 — trocar pelo driver básico do Windows, com a exceção D3 (Config 62 → 63)

**Files:**
- Modify: `src/Engine/winforge/wf-net.ps1` — `Invoke-WinForgeWifiDriverGeneric`.
- Modify: `src/Engine/winforge/wf-repair.ps1` — linha `'WifiDriverGeneric'`.
- Modify: `src/Engine/config/wf-repair-config.ps1` — `WPFWFRepWifiDriverGeneric`.
- Modify: `src/Engine/build.ps1` — caso no switch; trava de Config `62` → `63`; o gancho de abertura que **esconde** o botão; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 18 — inclusive a confirmação com a ressalva de AnyDesk e a verificação por `-Generic`, que saíram do teste da Tarefa 18 para cá, junto da linha que as torna possíveis.

**Interfaces:**
- Consumes: `Select-WinForgeWifiInboxDriver -Entries <object[]> → @{ Found; Published; Oem }` e `Export-WinForgeWifiDriverBackup …` (Tarefa 17); `Test-WinForgeNetworkGuard -Action 'WifiDriverGeneric' …` com `Hidden` (Tarefa 14); `Test-WinForgeWifiOutcome -Adapter <object> [-Generic]` e `Invoke-WinForgeWifiDriverRestore` (Tarefa 18).
- Produces:
  ```powershell
  Invoke-WinForgeWifiDriverGeneric [-DryRun] [-Facts <hashtable>]
  Get-WinForgeWifiGenericConfirmText → @{ Text = <string>; Typed = 'VOLTAR AO GENERICO' }
  ```

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- Rede: botão 5
    # Medido: o rádio tem TRÊS candidatos no repositório e a classificação menor vence. Apagar só o
    # instalado entregaria um Intel de 2014 e MENTIRIA sobre o que fez - por isso apaga todos os OEM.
    try {
        $wfW5Cmd = Get-WinForgeRepairCommand -Name 'WifiDriverGeneric'
        if ([string]$wfW5Cmd.Title -ne 'Rede sem fio — Trocar pelo driver básico do Windows (pode ficar sem Wi-Fi)') { Write-Host "  [ERRO] Rede (botão 5): título '$($wfW5Cmd.Title)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfW5Cmd.Kind -ne 'repair') { Write-Host "  [ERRO] Rede (botão 5): a linha é '$($wfW5Cmd.Kind)'" -ForegroundColor Red; $wbErrors++ }
        if ((Invoke-WinForgeRepairCommand -Name 'WifiDriverGeneric' -NoUI).Dispatched) { Write-Host "  [ERRO] Rede (botão 5): foi despachado no SelfTest" -ForegroundColor Red; $wbErrors++ }
        $wfW5Conf = Get-WinForgeWifiGenericConfirmText
        if ([string]$wfW5Conf.Typed -ne 'VOLTAR AO GENERICO') { Write-Host "  [ERRO] Rede (botão 5): a confirmação por digitação é '$($wfW5Conf.Typed)'" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfW5F in @('Se o driver básico não funcionar com este Wi-Fi, o computador fica sem rede sem fio até você trazer o driver por cabo ou pen drive', 'Tenha um cabo de rede à mão antes de continuar')) {
            if ([string]$wfW5Conf.Text -notmatch [regex]::Escape($wfW5F)) { Write-Host "  [ERRO] Rede (botão 5): falta '$wfW5F' na confirmação" -ForegroundColor Red; $wbErrors++ }
        }
        $wfW5Fonte = [string](Get-Command Invoke-WinForgeWifiDriverGeneric).ScriptBlock
        if ($wfW5Fonte -notmatch 'delete-driver') { Write-Host "  [ERRO] Rede (botão 5): falta o '/delete-driver /uninstall'" -ForegroundColor Red; $wbErrors++ }
        if ($wfW5Fonte -match '/force') { Write-Host "  [ERRO] Rede (botão 5): '/force' apaga o pacote em uso e é o caminho para ficar sem rádio" -ForegroundColor Red; $wbErrors++ }
        if ($wfW5Fonte -notmatch 'Invoke-WinForgeWifiDriverRestore') { Write-Host "  [ERRO] Rede (botão 5): sem restauração automática no desfecho ruim" -ForegroundColor Red; $wbErrors++ }
        # Exporta TODOS os OEM antes de apagar qualquer um.
        $wfW5PosExport = $wfW5Fonte.IndexOf('Export-WinForgeWifiDriverBackup', [StringComparison]::Ordinal)
        $wfW5PosDelete = $wfW5Fonte.IndexOf('delete-driver', [StringComparison]::Ordinal)
        if ($wfW5PosExport -lt 0 -or $wfW5PosDelete -lt 0 -or $wfW5PosExport -gt $wfW5PosDelete) { Write-Host "  [ERRO] Rede (botão 5): o apagamento vem antes da exportação" -ForegroundColor Red; $wbErrors++ }
        if ($wfW5Fonte -notmatch 'Oem') { Write-Host "  [ERRO] Rede (botão 5): ele não apaga TODOS os pacotes OEM do rádio" -ForegroundColor Red; $wbErrors++ }
        # A verificação de sucesso exige DriverProvider = Microsoft - cobrada POR COMPORTAMENTO, e
        # não por '-match "Microsoft"' na fonte, que casaria com o comentário que explica a regra.
        if ($wfW5Fonte -notmatch 'Test-WinForgeWifiOutcome[^\r\n]*-Generic') { Write-Host "  [ERRO] Rede (botão 5): a verificação não passa '-Generic' - sem ele não se distingue 'o básico entrou' de 'outro OEM venceu'" -ForegroundColor Red; $wbErrors++ }
        if ([string](Test-WinForgeWifiOutcome -Adapter ([pscustomobject]@{ Ok = $true; Status = 'Up'; Problem = 'CM_PROB_NONE'; DriverProvider = 'Intel'; Name = 'Wi-Fi' }) -Generic).Outcome -eq 'ok') { Write-Host "  [ERRO] Rede (botão 5): um driver Intel passou como 'o básico entrou'" -ForegroundColor Red; $wbErrors++ }
        # E a ressalva de AnyDesk/TeamViewer, que a Tarefa 18 deixou para cá junto com esta linha.
        if ([string]$wfW5Cmd.Confirm -notmatch 'AnyDesk') { Write-Host "  [ERRO] Rede (botão 5): a confirmação não avisa que AnyDesk e TeamViewer não são detectados" -ForegroundColor Red; $wbErrors++ }
        # Exceção D3: SEM inbox o botão SOME. Botão desabilitado convida a procurar como habilitá-lo,
        # e o que se acha na internet é "use /force".
        $wfW5FonteUI = [string](Get-Command Update-WinForgeNetworkButtons).ScriptBlock
        if ($wfW5FonteUI -notmatch 'WPFWFRepWifiDriverGeneric') { Write-Host "  [ERRO] Rede (D3): nada esconde o botão 5" -ForegroundColor Red; $wbErrors++ }
        if ($wfW5FonteUI -notmatch 'Collapsed') { Write-Host "  [ERRO] Rede (D3): o botão 5 é desabilitado em vez de escondido" -ForegroundColor Red; $wbErrors++ }
        # A entrada de config CONTINUA existindo (a trava é 63): quem some é o controle na tela.
        if ([string]::IsNullOrWhiteSpace([string]$sync.configs.feature.WPFWFRepWifiDriverGeneric.Description)) { Write-Host "  [ERRO] Rede (botão 5): WPFWFRepWifiDriverGeneric sem Description" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Rede (botão 5): confirmação por digitação, exporta todos os OEM antes de apagar, sem /force, sucesso só com DriverProvider Microsoft e o botão some sem inbox"
    } catch {
        Write-Host "  [ERRO] Rede (botão 5): $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Rede (botão 5): Comando de reparo desconhecido: 'WifiDriverGeneric'`.

- [ ] **Step 3: Implementar** — a linha, a entrada de config (texto literal do §6), o caso no switch, a trava `62` → `63` e `Update-WinForgeNetworkButtons` nova em `wf-net.ps1`, chamada do mesmo gancho de abertura das Tarefas 6 e 11. O trecho que decide o desenho:

  ```powershell
  # EXCEÇÃO à regra "botão desabilitado, não removido", e ela vale SÓ para este botão. Para MediaTek,
  # Realtek recentes, Intel AX/BE novos e Qualcomm frequentemente NÃO HÁ inbox nenhum, e apagar o
  # pacote deixa a máquina sem rádio. Botão desabilitado convida a procurar como habilitá-lo, e o
  # que se acha na internet é "use /force" - precisamente o caminho para ficar sem rádio.
  $guarda = Test-WinForgeNetworkGuard -Action 'WifiDriverGeneric'
  if ($guarda.Hidden) { $sync.WPFWFRepWifiDriverGeneric.Visibility = 'Collapsed' }
  ```
  A confirmação por digitação (`VOLTAR AO GENERICO`) é uma janela própria, criada na thread da janela, no mesmo estilo de `Show-WinForgeAclBackupDestination` (Tarefa 7).

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Entradas -> … | Config: 63 | …`, `Rede (botão 5): confirmação por digitação, exporta todos os OEM antes de apagar, sem /force, sucesso só com DriverProvider Microsoft e o botão some sem inbox` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(net): trocar o driver de WiFi pelo básico do Windows, com o botão escondido sem driver inbox`

---

### Task 20: Agrupar os INFs sem versão do Windows Update — critério em constantes provisórias

> **O corte de tamanho, a lista de classe e o tamanho mínimo do grupo são três constantes nomeadas, num único lugar** (o topo de `src/Engine/winforge/wf-drivers.ps1`), **marcadas como PROVISÓRIAS até os dados da máquina X99 chegarem**. A busca da WUA nesta máquina devolveu **0 ofertas de driver**, e `DriverClass`, `MaxDownloadSize` e `Categories` nunca foram vistos numa oferta real de INF sem versão; o corte de 256 KB veio do `DriverStore` local (pacote sem binário tem mediana 7.662 B, com binário 180.064 B). Chegando os dados de `Coletar-OfertasWU.ps1`, **muda-se a constante e mais nada** — e por isso **os testes leem as constantes, nunca o literal**: nenhum caso deste bloco escreve `262144`, `5` ou o nome de uma classe à mão.

**Files:**
- Modify: `src/Engine/winforge/wf-drivers.ps1` — as três constantes no topo do arquivo; `Search-WinForgeWindowsUpdateDrivers` (`:474-523`) ganha três propriedades; `Group-WinForgeWindowsUpdateNullDrivers` nova, depois de `Select-WinForgeWindowsUpdateLatest` (`:388-453`).
- Modify: `src/Engine/winforge/wf-diag.ps1` — `Export-WinForgeDiagnosticsReport` (`:1535`): coluna "Classe" e a nota de quantos itens a aba agrupou.
- Test: `src/Engine/build.ps1`, dentro do bloco `# ------- Windows Update: uma linha por dispositivo` (`build.ps1:4138-4221`), logo depois dos casos que já existem.

**Interfaces:**
- Consumes: `Select-WinForgeWindowsUpdateLatest -Rows <object[]> → @{ Kept; Superseded }` (existente, **não muda**).
- Produces:
  ```powershell
  $script:WinForgeNullDriverMaxBytes = 262144   # PROVISÓRIO — 256 KB
  $script:WinForgeNullDriverMinGroup = 5        # PROVISÓRIO
  $script:WinForgeNullDriverClasses  = @('', 'system', 'other hardware', 'unknown', 'outro hardware')  # PROVISÓRIO

  Group-WinForgeWindowsUpdateNullDrivers -Rows <object[]>
      [-MinGroup $script:WinForgeNullDriverMinGroup] [-MaxBytes $script:WinForgeNullDriverMaxBytes]
      [-Classes $script:WinForgeNullDriverClasses]
    → @{ Rows = @(<object>); Groups = @(@{ Key; Provider; Class; Date; Members = @(<UpdateId>);
         MemberTitles = @(<string>); HardwareIds = @(<string>); ProblemCodes = @(<int>) }) }
  ```
  **`HardwareIds` é obrigatório no grupo** e vem de `HardwareId` de cada membro, na ordem original: é o reforço `PCI\VEN_8086&DEV_` do filtro de §4, e é a Tarefa 22 que o consome. Sem ele o filtro de chipset leria vazio em produção e recusaria todo grupo real — ou, pior, viraria cheque morto, com o teste da Tarefa 22 injetando o campo à mão e passando verde.
  Propriedades novas em cada linha de `Search-WinForgeWindowsUpdateDrivers`, no mesmo `try/catch` já usado para `$class`: `SizeBytes` (de `MaxDownloadSize` e, se vier 0, `MinDownloadSize`), `HardwareId` (de `DriverHardwareID`) e `ProblemCode` (de `DeviceProblemNumber`). **`ProblemCode` NÃO participa do critério** — é lido só para o texto do §4.

- [ ] **Step 1: Teste que falha**

  ```powershell
        # ---- agrupamento dos INFs sem versão. As três constantes são PROVISÓRIAS: os casos abaixo
        # leem $script:WinForgeNullDriver*, e nenhum deles escreve 256 KB, 5 ou nome de classe à mão.
        $wfGrpMax = [int]$script:WinForgeNullDriverMaxBytes
        $wfGrpMin = [int]$script:WinForgeNullDriverMinGroup
        $wfGrpClasses = @($script:WinForgeNullDriverClasses)
        if ($wfGrpMax -le 0 -or $wfGrpMin -le 1 -or -not $wfGrpClasses.Count) { Write-Host "  [ERRO] Agrupamento: as constantes não existem ou estão vazias ($wfGrpMax / $wfGrpMin / $($wfGrpClasses.Count))" -ForegroundColor Red; $wbErrors++ }
        $wfGrpFonteC = [string](Get-Content -LiteralPath $PSCommandPath -Raw -ErrorAction SilentlyContinue)
        # A marca é cobrada NA LINHA DA CONSTANTE. Procurar 'PROVISÓRIO' no arquivo inteiro é
        # autoaprovação: a palavra está neste próprio comentário de teste, e o motor gerado junta
        # teste e função no mesmo arquivo.
        foreach ($wfGrpConst in @('WinForgeNullDriverMaxBytes', 'WinForgeNullDriverMinGroup', 'WinForgeNullDriverClasses')) {
            if ($wfGrpFonteC -notmatch ('\$script:' + $wfGrpConst + '[^\r\n]*#[^\r\n]*PROVISÓRIO')) { Write-Host "  [ERRO] Agrupamento: a constante '$wfGrpConst' não está marcada como PROVISÓRIA na própria linha" -ForegroundColor Red; $wbErrors++ }
        }
        $wfGrpClasseBoa = [string]@($wfGrpClasses | Where-Object { $_ -ne '' })[0]
        $wfGrpLinha = {
            param($Id, $Classe, $Tamanho, $Titulo, $Data, $Fornecedor, $Versao)
            [pscustomobject]@{ Title = $Titulo; Driver = ''; Provider = $Fornecedor; Class = $Classe; Version = $Versao; Date = $Data; UpdateId = $Id; SizeBytes = $Tamanho; HardwareId = 'PCI\VEN_8086&DEV_8D44'; ProblemCode = 28 }
        }
        # 47 ofertas iguais em fornecedor, classe e data: vira UM grupo.
        $wfGrp47 = @(1..47 | ForEach-Object { & $wfGrpLinha "n-$_" $wfGrpClasseBoa ([int]($wfGrpMax / 8)) "INTEL - System - $_" '2026-03-01' 'INTEL' $null })
        $wfGrpR = Group-WinForgeWindowsUpdateNullDrivers -Rows $wfGrp47
        if (@($wfGrpR.Groups).Count -ne 1) { Write-Host "  [ERRO] Agrupamento: 47 ofertas deram $(@($wfGrpR.Groups).Count) grupo(s)" -ForegroundColor Red; $wbErrors++ }
        if (@($wfGrpR.Rows).Count -ne 1) { Write-Host "  [ERRO] Agrupamento: sobraram $(@($wfGrpR.Rows).Count) linha(s), esperado 1" -ForegroundColor Red; $wbErrors++ }
        elseif (@(@($wfGrpR.Groups)[0].Members).Count -ne 47) { Write-Host "  [ERRO] Agrupamento: o grupo tem $(@(@($wfGrpR.Groups)[0].Members).Count) membro(s)" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]@($wfGrpR.Rows)[0].UpdateId -notlike 'grupo:*') { Write-Host "  [ERRO] Agrupamento: o id sintético é '$(@($wfGrpR.Rows)[0].UpdateId)', esperado 'grupo:<hash>'" -ForegroundColor Red; $wbErrors++ }
        if (@(@($wfGrpR.Groups)[0].Members) -join ',' -ne (@($wfGrp47 | ForEach-Object { $_.UpdateId }) -join ',')) { Write-Host "  [ERRO] Agrupamento: os membros não estão na ordem original" -ForegroundColor Red; $wbErrors++ }
        # Abaixo de MinGroup, ninguém agrupa: a linha fica sozinha.
        $wfGrpPoucos = Group-WinForgeWindowsUpdateNullDrivers -Rows @($wfGrp47 | Select-Object -First ($wfGrpMin - 1))
        if (@($wfGrpPoucos.Groups).Count -ne 0) { Write-Host "  [ERRO] Agrupamento: $($wfGrpMin - 1) ofertas formaram grupo" -ForegroundColor Red; $wbErrors++ }
        if (@($wfGrpPoucos.Rows).Count -ne ($wfGrpMin - 1)) { Write-Host "  [ERRO] Agrupamento: as linhas soltas sumiram" -ForegroundColor Red; $wbErrors++ }
        # Qualquer dúvida, a linha fica sozinha: título com versão, classe fora da lista de permissão,
        # tamanho desconhecido, tamanho acima do corte.
        foreach ($wfGrpNao in @(
            @{ Nome = 'título com versão';   Muda = { param($l) $l.Title = 'INTEL - System - 10.1.1.44'; $l } },
            @{ Nome = 'versão preenchida';   Muda = { param($l) $l.Version = '10.1.1.44'; $l } },
            @{ Nome = 'classe Display';      Muda = { param($l) $l.Class = 'Display'; $l } },
            @{ Nome = 'classe Firmware';     Muda = { param($l) $l.Class = 'Firmware'; $l } },
            @{ Nome = 'classe Extension';    Muda = { param($l) $l.Class = 'Extension'; $l } },
            @{ Nome = 'classe SoftwareComponent'; Muda = { param($l) $l.Class = 'SoftwareComponent'; $l } },
            @{ Nome = 'tamanho desconhecido'; Muda = { param($l) $l.SizeBytes = 0; $l } },
            @{ Nome = 'acima do corte';      Muda = { param($l) $l.SizeBytes = $wfGrpMax + 1; $l } })) {
            $wfGrpCaso = @(1..47 | ForEach-Object { & $wfGrpNao.Muda (& $wfGrpLinha "x-$_" $wfGrpClasseBoa ([int]($wfGrpMax / 8)) "INTEL - System - $_" '2026-03-01' 'INTEL' $null) })
            $wfGrpRes = Group-WinForgeWindowsUpdateNullDrivers -Rows $wfGrpCaso
            if (@($wfGrpRes.Groups).Count -ne 0) { Write-Host "  [ERRO] Agrupamento: '$($wfGrpNao.Nome)' foi agrupado - o erro caro é esconder o driver que o usuário veio buscar" -ForegroundColor Red; $wbErrors++ }
            if (@($wfGrpRes.Rows).Count -ne 47) { Write-Host "  [ERRO] Agrupamento: '$($wfGrpNao.Nome)' perdeu linha ($(@($wfGrpRes.Rows).Count) de 47)" -ForegroundColor Red; $wbErrors++ }
        }
        # Fornecedor, classe ou data diferentes dão grupos diferentes - a DATA entra na chave para
        # amarrar o lote a uma publicação de INF.
        $wfGrpDatas = @(1..47 | ForEach-Object { & $wfGrpLinha "d1-$_" $wfGrpClasseBoa ([int]($wfGrpMax / 8)) "INTEL - System - $_" '2026-03-01' 'INTEL' $null }) +
                      @(1..47 | ForEach-Object { & $wfGrpLinha "d2-$_" $wfGrpClasseBoa ([int]($wfGrpMax / 8)) "INTEL - System - $_" '2026-07-15' 'INTEL' $null })
        if (@((Group-WinForgeWindowsUpdateNullDrivers -Rows $wfGrpDatas).Groups).Count -ne 2) { Write-Host "  [ERRO] Agrupamento: datas diferentes não deram dois grupos" -ForegroundColor Red; $wbErrors++ }
        $wfGrpForn = @(1..47 | ForEach-Object { & $wfGrpLinha "f1-$_" $wfGrpClasseBoa ([int]($wfGrpMax / 8)) "INTEL - System - $_" '2026-03-01' 'INTEL' $null }) +
                     @(1..47 | ForEach-Object { & $wfGrpLinha "f2-$_" $wfGrpClasseBoa ([int]($wfGrpMax / 8)) "AMD - System - $_" '2026-03-01' 'AMD' $null })
        if (@((Group-WinForgeWindowsUpdateNullDrivers -Rows $wfGrpForn).Groups).Count -ne 2) { Write-Host "  [ERRO] Agrupamento: fornecedores diferentes não deram dois grupos" -ForegroundColor Red; $wbErrors++ }
        # A linha agrupada ocupa a posição da PRIMEIRA que a originou; as não agrupadas mantêm a ordem.
        $wfGrpMistura = @((& $wfGrpLinha 'solta-a' 'Display' 5000 'Realtek - Display - 1.2.3' '2026-03-01' 'Realtek' '1.2.3')) +
                        @(1..47 | ForEach-Object { & $wfGrpLinha "m-$_" $wfGrpClasseBoa ([int]($wfGrpMax / 8)) "INTEL - System - $_" '2026-03-01' 'INTEL' $null }) +
                        @((& $wfGrpLinha 'solta-b' 'Net' 5000 'Intel - Net - 22.1' '2026-03-01' 'Intel' '22.1'))
        $wfGrpOrd = @((Group-WinForgeWindowsUpdateNullDrivers -Rows $wfGrpMistura).Rows)
        if ($wfGrpOrd.Count -ne 3) { Write-Host "  [ERRO] Agrupamento: a mistura virou $($wfGrpOrd.Count) linha(s), esperado 3" -ForegroundColor Red; $wbErrors++ }
        elseif ([string]$wfGrpOrd[0].UpdateId -ne 'solta-a' -or [string]$wfGrpOrd[1].UpdateId -notlike 'grupo:*' -or [string]$wfGrpOrd[2].UpdateId -ne 'solta-b') { Write-Host "  [ERRO] Agrupamento: a ordem saiu '$(@($wfGrpOrd | ForEach-Object { $_.UpdateId }) -join ', ')'" -ForegroundColor Red; $wbErrors++ }
        # A busca real traz os três campos novos, e 'Categories.Name' continua descartado (vem no
        # idioma de UserLocale).
        $wfGrpFonteB = [string]${function:Search-WinForgeWindowsUpdateDrivers}
        foreach ($wfGrpCampo in @('MaxDownloadSize', 'MinDownloadSize', 'DriverHardwareID', 'DeviceProblemNumber')) {
            if ($wfGrpFonteB -notmatch [regex]::Escape($wfGrpCampo)) { Write-Host "  [ERRO] Agrupamento: a busca não lê '$wfGrpCampo'" -ForegroundColor Red; $wbErrors++ }
        }
        if ($wfGrpFonteB -match 'Categories') { Write-Host "  [ERRO] Agrupamento: 'Categories' voltou à busca - ele vem no idioma de UserLocale" -ForegroundColor Red; $wbErrors++ }
        $wfGrpFonteG = [string]${function:Group-WinForgeWindowsUpdateNullDrivers}
        # 'ProblemCode' no singular é o CRITÉRIO e está proibido; 'ProblemCodes' no plural é o campo
        # que o grupo TEM de emitir para a Tarefa 22. Proibir a substring reprovaria a implementação
        # correta - daí o \b(?!s).
        if ($wfGrpFonteG -match 'ProblemCode\b(?!s)') { Write-Host "  [ERRO] Agrupamento: ProblemCode NÃO participa do critério - as linhas a agrupar são justamente as de problema 28" -ForegroundColor Red; $wbErrors++ }
        # O grupo emite HardwareIds e ProblemCodes, na ordem original: são o que a Tarefa 22 lê.
        $wfGrpG0 = @($wfGrpR.Groups)[0]
        foreach ($wfGrpCampoG in @('HardwareIds', 'ProblemCodes', 'MemberTitles')) {
            if (@($wfGrpG0.$wfGrpCampoG).Count -ne 47) { Write-Host "  [ERRO] Agrupamento: o grupo emitiu $(@($wfGrpG0.$wfGrpCampoG).Count) item(ns) em '$wfGrpCampoG', esperado 47" -ForegroundColor Red; $wbErrors++ }
        }
        if (@($wfGrpG0.HardwareIds)[0] -ne 'PCI\VEN_8086&DEV_8D44') { Write-Host "  [ERRO] Agrupamento: HardwareIds veio '$(@($wfGrpG0.HardwareIds)[0])' - sem ele o reforço PCI\VEN_8086 da §4 lê vazio em produção" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfGrpLit in @('262144', "'system'", "'other hardware'")) {
            if ($wfGrpFonteC -match ([regex]::Escape($wfGrpLit) + '[\s\S]{0,200}\[ERRO\] Agrupamento')) { Write-Host "  [ERRO] Agrupamento: o teste escreve o literal '$wfGrpLit' em vez de ler a constante" -ForegroundColor Red; $wbErrors++ }
        }
        # O relatório HTML continua CRU: ganha a coluna "Classe" e a nota do que a aba agrupou.
        $wfGrpFonteRel = [string](Get-Command Export-WinForgeDiagnosticsReport).ScriptBlock
        if ($wfGrpFonteRel -match 'Group-WinForgeWindowsUpdateNullDrivers') { Write-Host "  [ERRO] Agrupamento: o relatório passou a agrupar - ele continua cru" -ForegroundColor Red; $wbErrors++ }
        if ($wfGrpFonteRel -notmatch '<th>Classe</th>[\s\S]{0,400}Windows Update|Windows Update[\s\S]{0,400}<th>Classe</th>') { Write-Host "  [ERRO] Agrupamento: a tabela do Windows Update no relatório não tem a coluna 'Classe'" -ForegroundColor Red; $wbErrors++ }
        Write-Host "  Agrupamento: 47 -> 1 grupo lendo as constantes provisórias ($wfGrpMax B / $wfGrpMin / $($wfGrpClasses.Count) classes), oito recusas, ordem preservada, relatório cru"
  ```
- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Agrupamento: as constantes não existem ou estão vazias (0 / 0 / 0)` e `[ERRO] Windows Update (uma linha por dispositivo): O termo 'Group-WinForgeWindowsUpdateNullDrivers' não é reconhecido…`.

- [ ] **Step 3: Implementar** — as três constantes no topo de `wf-drivers.ps1`, com o comentário que diz por que são provisórias e que **muda-se a constante e mais nada**. O trecho que decide o desenho:

  ```powershell
  # Quatro condições SIMULTÂNEAS, e nenhuma delas baixa coisa alguma:
  # (1) Version nulo E nenhum número no título;
  # (2) Class numa LISTA DE PERMISSÃO fechada, comparada com .Trim().ToLowerInvariant() - classe
  #     nova, traduzida ou ausente fica VISÍVEL, porque é lista de permissão e não de proibição;
  # (3) SizeBytes entre 1 e o corte (desconhecido NÃO agrupa: falta de dado é motivo para MOSTRAR);
  # (4) grupo com pelo menos MinGroup membros.
  # A chave leva a DATA para amarrar o lote a uma publicação de INF.
  $chave = ($provider + [char]1 + $class + [char]1 + $date).ToLowerInvariant()
  ```
  `UpdateId = 'grupo:' + <hash da chave>` faz `Get-`/`Set-WinForgeWindowsUpdateRowState` (`wf-diag.ps1:871-918`) funcionarem sem mudança nenhuma.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Agrupamento: 47 -> 1 grupo lendo as constantes provisórias (262144 B / 5 / 5 classes), oito recusas, ordem preservada, relatório cru` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: trocar `$script:WinForgeNullDriverMinGroup` para `50` e ver "47 ofertas deram 0 grupo(s)" ficar vermelho **sem que nenhum literal do teste precise mudar**; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `feat(drivers): agrupar os INFs sem versão do Windows Update por fornecedor, classe e data`

---

### Task 21: A linha de grupo na tabela e a instalação em lote

**Files:**
- Modify: `src/Engine/winforge/wf-diag.ps1` — `Update-WinForgeDiagnosticsWindowsUpdateGrid` (`:1194-1258`) e `Invoke-WinForgeWindowsUpdateGroupAction` nova.
- Modify: `src/Engine/xaml/wf-xaml-diag-tab.xml` — coluna "Detalhes" com um botão "Ver lista"; o botão da coluna "Instalar" passa a `Content="{Binding ActionLabel}"`.
- Modify: `src/Engine/config/wf-theme.ps1` — token `RowGroupBackgroundColor` (Claro e Escuro).
- Modify: `src/Engine/build.ps1` — pares de contraste novos; SelfTest.
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 20.

**Interfaces:**
- Consumes: `Group-WinForgeWindowsUpdateNullDrivers -Rows <object[]> … → @{ Rows; Groups }` (Tarefa 20); `Get-WinForgeWindowsUpdateRowState -UpdateId <string> → @{ State; Text }` e `Set-WinForgeWindowsUpdateRowState -UpdateId <string> -State <string> [-Text <string>]` (existentes).
- Produces:
  ```powershell
  Get-WinForgeWindowsUpdateGroupState -Members <string[]>
    → @{ State; StatusText; ActionLabel; ActionEnabled }
  Format-WinForgeWindowsUpdateGroupRow -Group <object> → <pscustomobject>
    # Title; Driver; Provider; Version; Date; UpdateId; IsGroup; Members; MemberTitles;
    # State; StatusText; ActionLabel; ActionEnabled; ActionTip; DetailsVisible;
    # Group = <o grupo original, inteiro>
  Invoke-WinForgeWindowsUpdateGroupAction -Row <object> [-NoUI] → <string>
  ```
  **`Group` viaja inteiro dentro da linha.** As colunas mostram texto já formatado (`Date` vira `sem data confiável`, `Version` vira `sem número de versão`), e o filtro de chipset da Tarefa 22 precisa dos valores crus — `Class`, `Provider`, `HardwareIds`, `ProblemCodes`. Sem este campo, `Invoke-WinForgeWindowsUpdateGroupAction` receberia a linha e não teria como perguntar nada ao grupo.
  `$sync.WUGroupCancel` (bool) é lido entre membros, junto de `$sync.WinForgeClosing`.

- [ ] **Step 1: Teste que falha**

  ```powershell
        # ---- a linha de grupo. O estado é DERIVADO a cada remontagem, nunca armazenado.
        $wfLgMembros = @(1..47 | ForEach-Object { "g-$_" })
        $sync.DiagWUState = @{}
        $wfLgPend = Get-WinForgeWindowsUpdateGroupState -Members $wfLgMembros
        if ([string]$wfLgPend.ActionLabel -ne 'Instalar todos (47)') { Write-Host "  [ERRO] Grupo (estado): pendente deu '$($wfLgPend.ActionLabel)'" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfLgPend.ActionEnabled) { Write-Host "  [ERRO] Grupo (estado): pendente nasceu desabilitado" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLgId in @($wfLgMembros | Select-Object -First 13)) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId $wfLgId -State 'instalando' -Text 'instalando...' }
        $wfLgAnd = Get-WinForgeWindowsUpdateGroupState -Members $wfLgMembros
        if ([string]$wfLgAnd.StatusText -ne 'instalando 13 de 47...') { Write-Host "  [ERRO] Grupo (estado): em andamento deu '$($wfLgAnd.StatusText)'" -ForegroundColor Red; $wbErrors++ }
        if ($wfLgAnd.ActionEnabled) { Write-Host "  [ERRO] Grupo (estado): em andamento continua habilitado" -ForegroundColor Red; $wbErrors++ }
        $sync.DiagWUState = @{}
        foreach ($wfLgId in $wfLgMembros) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId $wfLgId -State 'instalado' -Text 'instalado' }
        $wfLgTudo = Get-WinForgeWindowsUpdateGroupState -Members $wfLgMembros
        if ([string]$wfLgTudo.StatusText -ne '47 de 47 instalados') { Write-Host "  [ERRO] Grupo (estado): tudo instalado deu '$($wfLgTudo.StatusText)'" -ForegroundColor Red; $wbErrors++ }
        if ($wfLgTudo.ActionEnabled) { Write-Host "  [ERRO] Grupo (estado): tudo instalado continua habilitado" -ForegroundColor Red; $wbErrors++ }
        $null = Set-WinForgeWindowsUpdateRowState -UpdateId 'g-1' -State 'instalado' -Text 'instalado (reinicie)'
        if ([string](Get-WinForgeWindowsUpdateGroupState -Members $wfLgMembros).StatusText -ne '47 de 47 instalados (reinicie)') { Write-Host "  [ERRO] Grupo (estado): o '(reinicie)' não aparece no grupo" -ForegroundColor Red; $wbErrors++ }
        $sync.DiagWUState = @{}
        foreach ($wfLgId in @($wfLgMembros | Select-Object -First 45)) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId $wfLgId -State 'instalado' -Text 'instalado' }
        foreach ($wfLgId in @($wfLgMembros | Select-Object -Last 2)) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId $wfLgId -State 'falhou' -Text 'falhou (código 5)' }
        $wfLgFalha = Get-WinForgeWindowsUpdateGroupState -Members $wfLgMembros
        if ([string]$wfLgFalha.StatusText -ne '45 de 47 instalados, 2 falharam') { Write-Host "  [ERRO] Grupo (estado): falha deu '$($wfLgFalha.StatusText)'" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfLgFalha.ActionEnabled) { Write-Host "  [ERRO] Grupo (estado): com falha o botão tem de continuar clicável" -ForegroundColor Red; $wbErrors++ }
        $sync.DiagWUState = @{}
        foreach ($wfLgId in @($wfLgMembros | Select-Object -First 12)) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId $wfLgId -State 'instalado' -Text 'instalado' }
        $null = Set-WinForgeWindowsUpdateRowState -UpdateId 'g-13' -State 'falhou' -Text 'falhou'
        if ([string](Get-WinForgeWindowsUpdateGroupState -Members $wfLgMembros).StatusText -ne '12 de 47 instalados, 1 falhou, 34 pendentes') { Write-Host "  [ERRO] Grupo (estado): parcial deu '$((Get-WinForgeWindowsUpdateGroupState -Members $wfLgMembros).StatusText)'" -ForegroundColor Red; $wbErrors++ }
        $sync.DiagWUState = @{}
        # Rótulos da linha. A palavra "chipset" NÃO entra: o rótulo nasce de Provider e classe, mais
        # frouxos que o filtro de §4, e dizer "chipset" ali afirmaria o que §4 proíbe afirmar.
        # HardwareIds de propósito FORA do 'PCI\VEN_8086&DEV_': este grupo não passa no filtro de
        # chipset da Tarefa 22, e é assim que o lote deste teste continua rodando sem ponto de
        # restauração depois que aquela tarefa entrar. O rótulo da linha não depende daquele filtro -
        # ele nasce de Provider e classe, que são mais frouxos de propósito (§3.2).
        $wfLgGrupo = @{ Key = 'intel|system|2026-03-01'; Provider = 'Intel'; Class = 'System'; Date = '2026-03-01'; Members = $wfLgMembros; MemberTitles = @($wfLgMembros | ForEach-Object { "INTEL - System - $_" }); HardwareIds = @(1..47 | ForEach-Object { 'PCI\VEN_1022&DEV_1450' }); ProblemCodes = @(1..47 | ForEach-Object { 28 }) }
        $wfLgLinha = Format-WinForgeWindowsUpdateGroupRow -Group $wfLgGrupo
        if ([string]$wfLgLinha.Title -ne 'Intel — 47 itens que só dão nome a componentes da placa-mãe') { Write-Host "  [ERRO] Grupo (rótulo): Atualização = '$($wfLgLinha.Title)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfLgLinha.Driver -ne '47 dispositivos') { Write-Host "  [ERRO] Grupo (rótulo): Driver = '$($wfLgLinha.Driver)'" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfLgLinha.Version -ne 'sem número de versão') { Write-Host "  [ERRO] Grupo (rótulo): Versão = '$($wfLgLinha.Version)'" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLgProp in @('Title', 'Driver', 'Provider', 'Version', 'Date', 'ActionLabel', 'StatusText')) {
            if ([string]$wfLgLinha.$wfLgProp -match '(?i)chipset') { Write-Host "  [ERRO] Grupo (rótulo): a palavra 'chipset' apareceu em '$wfLgProp'" -ForegroundColor Red; $wbErrors++ }
        }
        if ([string](Format-WinForgeWindowsUpdateGroupRow -Group (@{} + $wfLgGrupo + @{ Date = '1980-01-01' })).Date -ne 'sem data confiável') { Write-Host "  [ERRO] Grupo (rótulo): data anterior a 1990 não virou 'sem data confiável'" -ForegroundColor Red; $wbErrors++ }
        if (-not $wfLgLinha.IsGroup) { Write-Host "  [ERRO] Grupo (linha): IsGroup não está marcado" -ForegroundColor Red; $wbErrors++ }
        if (@($wfLgLinha.MemberTitles).Count -ne 47) { Write-Host "  [ERRO] Grupo (linha): MemberTitles tem $(@($wfLgLinha.MemberTitles).Count) item(ns)" -ForegroundColor Red; $wbErrors++ }
        # O grupo cru viaja na linha: 'Date' já virou texto de tela, e a Tarefa 22 precisa de Class,
        # Provider, HardwareIds e ProblemCodes como vieram.
        foreach ($wfLgCru in @('Class', 'Provider', 'HardwareIds', 'ProblemCodes')) {
            if ($null -eq $wfLgLinha.Group.$wfLgCru) { Write-Host "  [ERRO] Grupo (linha): a linha não carrega '$wfLgCru' do grupo cru - o filtro de chipset ficaria sem o que ler" -ForegroundColor Red; $wbErrors++ }
        }
        # Instalação: UM runspace com foreach, e não um job por membro (dois jobs disputariam a trava
        # CommandRunning consigo mesmos). O segundo clique instala só os que faltam.
        $wfLgFonteI = [string](Get-Command Invoke-WinForgeWindowsUpdateGroupAction).ScriptBlock
        if (@([regex]::Matches($wfLgFonteI, 'Invoke-WPFRunspace')).Count -ne 1) { Write-Host "  [ERRO] Grupo (instalação): $(@([regex]::Matches($wfLgFonteI, 'Invoke-WPFRunspace')).Count) despachos, esperado 1" -ForegroundColor Red; $wbErrors++ }
        if ($wfLgFonteI -notmatch 'foreach') { Write-Host "  [ERRO] Grupo (instalação): falta o foreach sobre os membros" -ForegroundColor Red; $wbErrors++ }
        if ($wfLgFonteI -notmatch 'WUGroupCancel') { Write-Host "  [ERRO] Grupo (instalação): não confere `$sync.WUGroupCancel entre membros" -ForegroundColor Red; $wbErrors++ }
        if ($wfLgFonteI -notmatch 'WinForgeClosing') { Write-Host "  [ERRO] Grupo (instalação): não confere `$sync.WinForgeClosing entre membros" -ForegroundColor Red; $wbErrors++ }
        # UMA caixa de REINÍCIO, e ela vem depois do laço. O teste conta a caixa de reinício
        # (MessageBoxImage::Information), e não 'MessageBox' cru: a Tarefa 22 acrescenta a
        # confirmação do chipset (MessageBoxImage::Warning) a esta mesma função, e contar todas
        # deixaria este teste vermelho no dia em que aquela tarefa entrasse.
        if (@([regex]::Matches($wfLgFonteI, 'MessageBoxImage\]::Information')).Count -ne 1) { Write-Host "  [ERRO] Grupo (instalação): $(@([regex]::Matches($wfLgFonteI, 'MessageBoxImage\]::Information')).Count) caixas de reinício, esperado UMA no fim" -ForegroundColor Red; $wbErrors++ }
        $wfLgPosLaco = $wfLgFonteI.IndexOf('foreach', [StringComparison]::Ordinal)
        $wfLgPosCaixa = $wfLgFonteI.IndexOf('MessageBoxImage]::Information', [StringComparison]::Ordinal)
        if ($wfLgPosCaixa -lt 0 -or $wfLgPosLaco -lt 0 -or $wfLgPosCaixa -lt $wfLgPosLaco) { Write-Host "  [ERRO] Grupo (instalação): a caixa de reinício aparece antes do laço - uma por membro é justamente o que ela existe para evitar" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLgId in @($wfLgMembros | Select-Object -First 40)) { $null = Set-WinForgeWindowsUpdateRowState -UpdateId $wfLgId -State 'instalado' -Text 'instalado' }
        $wfLgSeco = Invoke-WinForgeWindowsUpdateGroupAction -Row $wfLgLinha -NoUI
        if ($wfLgSeco -notmatch '7') { Write-Host "  [ERRO] Grupo (instalação): o segundo clique diria '$wfLgSeco', esperado só os 7 que faltam" -ForegroundColor Red; $wbErrors++ }
        $sync.DiagWUState = @{}
        # A lista expandida sai na JANELA DE SAÍDA por um botão "Ver lista": gabarito próprio de
        # célula (RowDetailsTemplate, expander) quebra a rolagem da aba - wf-xaml-styles.xml:334-344.
        $wfLgXaml = [string](Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\Engine\xaml\wf-xaml-diag-tab.xml') -Raw -ErrorAction SilentlyContinue)
        if ([string]::IsNullOrWhiteSpace($wfLgXaml)) { $wfLgXaml = [string]$inputXML }
        if ($wfLgXaml -match 'RowDetailsTemplate|<Expander') { Write-Host "  [ERRO] Grupo (XAML): RowDetailsTemplate/Expander quebram a rolagem da aba" -ForegroundColor Red; $wbErrors++ }
        if ($wfLgXaml -notmatch 'Ver lista') { Write-Host "  [ERRO] Grupo (XAML): falta a coluna 'Detalhes' com o botão 'Ver lista'" -ForegroundColor Red; $wbErrors++ }
        if ($wfLgXaml -notmatch 'Content="\{Binding ActionLabel\}"[\s\S]{0,600}Instalar') { Write-Host "  [ERRO] Grupo (XAML): o botão da coluna Instalar não liga o Content a ActionLabel" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfLgTema in @('Light', 'Dark')) {
            if ([string]::IsNullOrWhiteSpace([string]$sync.configs.themes.$wfLgTema.RowGroupBackgroundColor)) { Write-Host "  [ERRO] Grupo (tema): RowGroupBackgroundColor ausente em $wfLgTema" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Grupo: cinco estados derivados, rótulos sem a palavra 'chipset', um runspace com foreach, uma caixa de reinício e lista na janela de saída"
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Windows Update (uma linha por dispositivo): O termo 'Get-WinForgeWindowsUpdateGroupState' não é reconhecido…`.

- [ ] **Step 3: Implementar** — o estado é **derivado a cada remontagem, nunca armazenado**, e a instalação é um único `Invoke-WPFRunspace`:

  ```powershell
  # UM despacho, com foreach dentro. Um job por membro disputaria $sync.CommandRunning consigo
  # mesmo: o segundo veria a trava do primeiro e recusaria. Cada membro dá um tique pelo caminho
  # que já existe ($sync.LastWUInstallId/Code/Reboot + Invoke-WPFUIThread), e o callback é um
  # scriptblock de ESCOPO DE ARQUIVO criado na runspace principal, sem exceção. Falha não
  # interrompe o laço; entre membros, $sync.WinForgeClosing e $sync.WUGroupCancel.
  ```
  A única mudança no `CellTemplate` da coluna "Instalar" é `Content="{Binding ActionLabel}"` — padrão que `wf-xaml-diag-tab.xml:68` já usa na tabela de drivers instalados. As seis colunas existentes **não mudam**; entra uma sétima, "Detalhes", com o botão "Ver lista" visível só quando `DetailsVisible` (isto é, na linha de grupo), que abre `Show-WinForgeOutputWindow -Title '<rótulo do grupo>' -Text (MemberTitles -join "`r`n")`.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Grupo: cinco estados derivados, rótulos sem a palavra 'chipset', um runspace com foreach, uma caixa de reinício e lista na janela de saída` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.

- [ ] **Step 5: Commit**
  `feat(diag): linha de grupo na tabela do Windows Update, com instalação em lote num runspace só`

---

### Task 22: Chipset INF pela via do Windows Update — filtro, ponto de restauração e texto

> Não é botão novo nem entrada de config: é o que cerca o `Instalar todos (N)` da linha de grupo quando ela passa no teste de chipset. Instalar de uma vez as N entradas pelo WU **é** o Chipset INF Utility. Descartados e registrados: `SetupChipset.exe` quebraria a perna que sustenta a exceção da NVIDIA (consulta à API pública ao vivo no clique) e a Intel não tem API equivalente; a página do SKU X99 (81761) marca **Discontinued**; `winget search chipset` devolveu **0 pacotes**; o Chocolatey baixa de espelho de terceiro.

**Files:**
- Modify: `src/Engine/winforge/wf-drivers.ps1` — `Test-WinForgeChipsetGroup` e `New-WinForgeChipsetRestorePoint`.
- Modify: `src/Engine/winforge/wf-diag.ps1` — `Invoke-WinForgeWindowsUpdateGroupAction` (confirmação, ponto de restauração antes do primeiro membro).
- Test: `src/Engine/build.ps1`, abaixo do bloco da Tarefa 21.

**Interfaces:**
- Consumes: `Format-WinForgeWindowsUpdateGroupRow -Group <object> → <pscustomobject>` com o campo `Group` (o grupo cru) e `Invoke-WinForgeWindowsUpdateGroupAction -Row <object> [-NoUI] → <string>` (Tarefa 21); `Group-WinForgeWindowsUpdateNullDrivers … → @{ Rows; Groups }` com `HardwareIds` **e** `ProblemCodes` (Tarefa 20). Os dois campos vêm da Tarefa 20 preenchidos a partir dos membros reais — este teste não os injeta à mão, e o filtro do `PCI\VEN_8086&DEV_` é cheque que a produção cobre.
- Produces:
  ```powershell
  Test-WinForgeChipsetGroup -Group <object> → @{ Ok = <bool>; Reason = <string>; ProblemCount = <int> }
  New-WinForgeChipsetRestorePoint [-Before <object[]>] [-After <object[]>]
    → @{ Ok = <bool>; Reason = <string>; SequenceNumber = <int> }
  Get-WinForgeChipsetConfirmText -Group <object> → <string>
  ```

- [ ] **Step 1: Teste que falha**

  ```powershell
        # ---- §4: chipset INF pela via do Windows Update
        # Classe 'System' = {4d36e97d-e325-11ce-bfc1-08002be10318}, invariante de idioma. Vídeo é
        # 'Display', rede 'Net', áudio 'MEDIA'. E NÃO se filtra por "chipset" no título:
        # 'INTEL - System - 10.1.1.44' não contém a palavra e é o pacote do X99.
        # O grupo vem de Group-WinForgeWindowsUpdateNullDrivers, e não escrito à mão: é a única forma
        # de o reforço 'PCI\VEN_8086&DEV_' ser cheque coberto. Se a Tarefa 20 parar de emitir
        # HardwareIds, é aqui que fica vermelho, e não em produção.
        $wfChLinhas = @(1..47 | ForEach-Object {
            [pscustomobject]@{ Title = "INTEL - System - $_"; Driver = ''; Provider = 'INTEL'; Class = [string]@($script:WinForgeNullDriverClasses | Where-Object { $_ -ne '' })[0]; Version = $null; Date = '2026-03-01'; UpdateId = "c-$_"; SizeBytes = [int]($script:WinForgeNullDriverMaxBytes / 8); HardwareId = 'PCI\VEN_8086&DEV_8D44'; ProblemCode = 28 }
        })
        $wfChGrupo = @(@(Group-WinForgeWindowsUpdateNullDrivers -Rows $wfChLinhas).Groups)[0]
        if ($null -eq $wfChGrupo) { Write-Host "  [ERRO] Chipset: o agrupamento da Tarefa 20 não devolveu grupo para o caso do X99" -ForegroundColor Red; $wbErrors++ }
        if (@($wfChGrupo.HardwareIds).Count -ne 47) { Write-Host "  [ERRO] Chipset: o grupo veio com $(@($wfChGrupo.HardwareIds).Count) HardwareIds - o reforço PCI\VEN_8086 leria vazio em produção" -ForegroundColor Red; $wbErrors++ }
        # A classe do grupo sai da lista de permissão, que é PROVISÓRIA e pode mudar com os dados da
        # X99; o filtro de §4 exige 'System' e é outro teste, mais apertado. Fixar a classe aqui
        # mantém este bloco medindo o FILTRO, e não a constante.
        $wfChGrupo = @{} + $wfChGrupo + @{ Class = 'System'; Provider = 'INTEL' }
        if (-not (Test-WinForgeChipsetGroup -Group $wfChGrupo).Ok) { Write-Host "  [ERRO] Chipset: o grupo Intel/System/PCI\VEN_8086 foi recusado ('$((Test-WinForgeChipsetGroup -Group $wfChGrupo).Reason)')" -ForegroundColor Red; $wbErrors++ }
        if (-not (Test-WinForgeChipsetGroup -Group (@{} + $wfChGrupo + @{ Provider = 'Intel' })).Ok) { Write-Host "  [ERRO] Chipset: '^intel$' tem de casar sem ligar para a caixa" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfChNao in @(
            @{ Nome = 'classe vazia';        Muda = @{ Class = '' } },
            @{ Nome = 'classe Net';          Muda = @{ Class = 'Net' } },
            @{ Nome = 'fornecedor AMD';      Muda = @{ Provider = 'AMD' } },
            @{ Nome = 'fornecedor parecido'; Muda = @{ Provider = 'Intel Corporation' } },
            @{ Nome = 'outro VEN';           Muda = @{ HardwareIds = @('PCI\VEN_1022&DEV_1450') } })) {
            if ((Test-WinForgeChipsetGroup -Group (@{} + $wfChGrupo + $wfChNao.Muda)).Ok) { Write-Host "  [ERRO] Chipset: '$($wfChNao.Nome)' passou no filtro - classe vazia cai em NÃO CLASSIFICADO, jamais em 'é chipset'" -ForegroundColor Red; $wbErrors++ }
        }
        # Sem nenhum membro com problema 28, o texto muda (e o ProblemCode continua fora do critério).
        $wfChSemProb = Test-WinForgeChipsetGroup -Group (@{} + $wfChGrupo + @{ ProblemCodes = @(1..47 | ForEach-Object { 0 }) })
        if (-not $wfChSemProb.Ok) { Write-Host "  [ERRO] Chipset: ProblemCode virou critério - ele é lido só para o texto" -ForegroundColor Red; $wbErrors++ }
        if ([int]$wfChSemProb.ProblemCount -ne 0) { Write-Host "  [ERRO] Chipset: ProblemCount=$($wfChSemProb.ProblemCount), esperado 0" -ForegroundColor Red; $wbErrors++ }
        $wfChTexto0 = Get-WinForgeChipsetConfirmText -Group (@{} + $wfChGrupo + @{ ProblemCodes = @(1..47 | ForEach-Object { 0 }) })
        if ($wfChTexto0 -notmatch 'Nenhum dispositivo deste PC está sem nome\. Instalar não traria efeito visível\.') { Write-Host "  [ERRO] Chipset (texto): falta a frase de 'nenhum dispositivo sem nome'" -ForegroundColor Red; $wbErrors++ }
        $wfChTexto = Get-WinForgeChipsetConfirmText -Group $wfChGrupo
        foreach ($wfChF in @('passa a mostrar o nome real no Gerenciador de Dispositivos', 'O que não muda: desempenho', 'só informam ao Windows o nome do componente', 'não há como desfazer', 'Reverter Driver')) {
            if ($wfChTexto -notmatch [regex]::Escape($wfChF)) { Write-Host "  [ERRO] Chipset (texto): falta '$wfChF'" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($wfChProibida in @('otimiza', 'melhora o desempenho', 'atualiza o chipset', 'driver de chipset')) {
            if ($wfChTexto -match [regex]::Escape($wfChProibida)) { Write-Host "  [ERRO] Chipset (texto): palavra proibida '$wfChProibida'" -ForegroundColor Red; $wbErrors++ }
        }
        foreach ($wfChFalta in @('cobertura offline', 'versão de pacote', 'Aplicativos e recursos')) {
            if ($wfChTexto -notmatch [regex]::Escape($wfChFalta)) { Write-Host "  [ERRO] Chipset (texto): a confirmação não diz o que fica de fora ante o pacote da Intel ('$wfChFalta')" -ForegroundColor Red; $wbErrors++ }
        }
        # Checkpoint-Computer é SILENCIOSAMENTE IGNORADO com a Proteção do Sistema desligada ou
        # dentro da janela de 24 h: a função confere a SEQUÊNCIA antes e depois.
        $wfChPonto = New-WinForgeChipsetRestorePoint -Before @(@{ SequenceNumber = 10 }) -After @(@{ SequenceNumber = 10 })
        if ($wfChPonto.Ok) { Write-Host "  [ERRO] Chipset (ponto): sem sequência nova ele respondeu Ok" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfChPonto.Reason -notmatch 'Proteção do Sistema') { Write-Host "  [ERRO] Chipset (ponto): a recusa não diz se a Proteção está desligada e onde ligar ('$($wfChPonto.Reason)')" -ForegroundColor Red; $wbErrors++ }
        if ([string]$wfChPonto.Reason -notmatch '24 h|24 horas') { Write-Host "  [ERRO] Chipset (ponto): a recusa não menciona a janela de 24 h" -ForegroundColor Red; $wbErrors++ }
        $wfChPontoOk = New-WinForgeChipsetRestorePoint -Before @(@{ SequenceNumber = 10 }) -After @(@{ SequenceNumber = 10 }, @{ SequenceNumber = 11 })
        if (-not $wfChPontoOk.Ok -or [int]$wfChPontoOk.SequenceNumber -ne 11) { Write-Host "  [ERRO] Chipset (ponto): sequência nova não foi reconhecida ($($wfChPontoOk.SequenceNumber))" -ForegroundColor Red; $wbErrors++ }
        # O ponto roda UMA VEZ, antes do primeiro membro, e sem ele o LOTE NÃO RODA.
        $wfChFonteA = [string](Get-Command Invoke-WinForgeWindowsUpdateGroupAction).ScriptBlock
        if (@([regex]::Matches($wfChFonteA, 'New-WinForgeChipsetRestorePoint')).Count -ne 1) { Write-Host "  [ERRO] Chipset: o ponto de restauração não roda exatamente uma vez" -ForegroundColor Red; $wbErrors++ }
        $wfChPosPonto = $wfChFonteA.IndexOf('New-WinForgeChipsetRestorePoint', [StringComparison]::Ordinal)
        $wfChPosLaco = $wfChFonteA.IndexOf('foreach', [StringComparison]::Ordinal)
        if ($wfChPosPonto -lt 0 -or $wfChPosLaco -lt 0 -or $wfChPosPonto -gt $wfChPosLaco) { Write-Host "  [ERRO] Chipset: o ponto de restauração roda DEPOIS do primeiro membro" -ForegroundColor Red; $wbErrors++ }
        if ($wfChFonteA -notmatch 'Install-WinForgeWindowsUpdateDriver') { Write-Host "  [ERRO] Chipset: o lote não instala pelo caminho existente" -ForegroundColor Red; $wbErrors++ }
        # O PORTÃO, por comportamento, nas duas pontas - e sem tocar em Checkpoint-Computer, que é
        # escrita: com -NoUI a função RELATA o que faria. Grupo que passa no filtro anuncia o ponto
        # de restauração; grupo que não passa (é a linha do teste da Tarefa 21) segue sem ele, senão
        # todo lote do Windows Update passaria a depender da Proteção do Sistema.
        $wfChLinha = Format-WinForgeWindowsUpdateGroupRow -Group $wfChGrupo
        $wfChRelato = [string](Invoke-WinForgeWindowsUpdateGroupAction -Row $wfChLinha -NoUI)
        if ($wfChRelato -notmatch 'ponto de restauração') { Write-Host "  [ERRO] Chipset: o lote de um grupo de chipset não anuncia o ponto de restauração ('$wfChRelato')" -ForegroundColor Red; $wbErrors++ }
        $wfChNaoCh = Format-WinForgeWindowsUpdateGroupRow -Group (@{} + $wfChGrupo + @{ HardwareIds = @(1..47 | ForEach-Object { 'PCI\VEN_1022&DEV_1450' }) })
        if ([string](Invoke-WinForgeWindowsUpdateGroupAction -Row $wfChNaoCh -NoUI) -match 'ponto de restauração') { Write-Host "  [ERRO] Chipset: um grupo que NÃO é chipset ficou preso ao ponto de restauração" -ForegroundColor Red; $wbErrors++ }
        if ($wfChFonteA -notmatch 'Test-WinForgeChipsetGroup') { Write-Host "  [ERRO] Chipset: o lote não pergunta ao filtro - o ponto de restauração viraria obrigatório para todo grupo" -ForegroundColor Red; $wbErrors++ }
        if ($wfChFonteA -notmatch '\$Row\.Group') { Write-Host "  [ERRO] Chipset: o filtro é consultado com a LINHA, e não com o grupo cru que ela carrega - Class e HardwareIds não sobrevivem à formatação" -ForegroundColor Red; $wbErrors++ }
        if ($wfChFonteA -match 'Checkpoint-Computer') { Write-Host "  [ERRO] Chipset: Checkpoint-Computer é chamado direto aqui - ele mora em New-WinForgeChipsetRestorePoint, que é quem confere a sequência" -ForegroundColor Red; $wbErrors++ }
        # Nada deste caminho baixa ou executa instalador de terceiro.
        foreach ($wfChProibido in @('SetupChipset', 'chocolatey', 'choco ', 'Invoke-WebRequest', 'Start-BitsTransfer')) {
            if ($wfChFonteA -match [regex]::Escape($wfChProibido)) { Write-Host "  [ERRO] Chipset: '$wfChProibido' aparece no caminho do lote" -ForegroundColor Red; $wbErrors++ }
        }
        Write-Host "  Chipset: filtro por classe System + Intel + PCI\VEN_8086, cinco recusas, ponto de restauração conferido pela sequência e texto sem palavra proibida"
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Windows Update (uma linha por dispositivo): O termo 'Test-WinForgeChipsetGroup' não é reconhecido…`.

- [ ] **Step 3: Implementar** — o filtro usa campos que a Tarefa 20 já lê:

  ```powershell
  # Classe 'System' é OBRIGATÓRIA; fornecedor casando '^intel$' sem caixa; e, de REFORÇO, o
  # DriverHardwareID começando em 'PCI\VEN_8086&DEV_'. Classe vazia cai em não classificado, jamais
  # em "é chipset": o rótulo do grupo (§3.2) é mais frouxo que este filtro de propósito, e é por
  # isso que a palavra "chipset" não aparece lá.
  if ([string]$Group.Class -ne 'System') { return @{ Ok = $false; Reason = "classe '$($Group.Class)' não é System"; ProblemCount = 0 } }
  if ([string]$Group.Provider -notmatch '^(?i)intel$') { return @{ Ok = $false; Reason = "fornecedor '$($Group.Provider)' não é Intel"; ProblemCount = 0 } }
  ```
  ```powershell
  # A Intel documenta (000023446) INF de chipset do WU sobrescrevendo o driver funcional do SMBus:
  # daí o ponto de restauração. E Checkpoint-Computer é SILENCIOSAMENTE IGNORADO com a Proteção do
  # Sistema desligada ou dentro da janela de 24 h - ele não devolve erro. A única prova é a
  # SEQUÊNCIA: lê Get-ComputerRestorePoint antes e depois e confere que apareceu número novo.
  $novos = @($After | Where-Object { [int]$_.SequenceNumber -notin @($Before | ForEach-Object { [int]$_.SequenceNumber }) })
  if (-not $novos.Count) { return @{ Ok = $false; Reason = 'Não foi criado ponto de restauração…'; SequenceNumber = 0 } }
  ```
  **Esta ação não tem Desfazer no WinForge**, e o aviso aponta "Propriedades → Driver → Reverter Driver" como a única volta, em destaque na confirmação.

  O portão em `Invoke-WinForgeWindowsUpdateGroupAction`, na ordem exata:
  ```powershell
  # O ponto de restauração é do CHIPSET, e não de todo lote: um grupo que não passa em
  # Test-WinForgeChipsetGroup instala como instalava. O filtro pergunta ao GRUPO CRU que a linha
  # carrega ($Row.Group) - 'Date' e 'Version' da linha já são texto de tela.
  $chipset = Test-WinForgeChipsetGroup -Group $Row.Group
  if ($chipset.Ok) {
      if ($NoUI) { $saida += 'Antes do primeiro item o WinForge criaria um ponto de restauração.' }
      else {
          # confirmação (MessageBoxImage::Warning) com Get-WinForgeChipsetConfirmText, e só depois:
          $ponto = New-WinForgeChipsetRestorePoint
          if (-not $ponto.Ok) { return $ponto.Reason }   # o LOTE NÃO RODA, e nenhum membro é tocado
      }
  }
  foreach ($id in @($Row.Members)) { … }
  # a UMA caixa de reinício (MessageBoxImage::Information) fica depois do laço
  ```

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - Esperado: `Chipset: filtro por classe System + Intel + PCI\VEN_8086, cinco recusas, ponto de restauração conferido pela sequência e texto sem palavra proibida` e `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas.
  - Prova por mutação: fazer `New-WinForgeChipsetRestorePoint` devolver sempre `Ok = $true` e ver "sem sequência nova ele respondeu Ok" ficar vermelho; desfazer e confirmar o verde.

- [ ] **Step 5: Commit**
  `feat(drivers): ponto de restauração e texto do chipset INF antes do lote do Windows Update`

---

### Task 23: Documentação, changelog, roteiro manual e 1.8.0

**Files:**
- Modify: `README.md` — permissões (o que muda no botão, o backup obrigatório, o destino opcional, Limpar backups antigos, o Parar), drivers (linha de grupo e o que ela é), rede (a escada de seis botões e o que cada um não faz).
- Modify: `docs/changelog.md` — seção `## 1.8.0 (2026-09-12)` no topo.
- Modify: `version.props` — `<Version>1.8.0</Version>`.
- Create: `docs/roteiro-manual-1.8.0.md` — o roteiro do §8, escrito **antes** do PR.
- Test: `build.cmd`, `dotnet test src\Launcher.Tests`, `git diff --exit-code -- docs/auditoria.md`.

**Interfaces:**
- Consumes: tudo que as Tarefas 1 a 22 produziram. Nada novo é definido aqui.
- Produces: nenhuma função; o roteiro manual é a saída desta tarefa.

- [ ] **Step 1: Teste que falha**

  ```powershell
    # ---------------------------------------------------------------- 1.8.0: versão e documentação
    try {
        if ([string]$sync.version -ne '1.8.0') { Write-Host "  [ERRO] Versão: `$sync.version = '$($sync.version)', esperado '1.8.0'" -ForegroundColor Red; $wbErrors++ }
        $wfDocChange = [string](Get-Content -LiteralPath (Join-Path (Get-Location) 'docs\changelog.md') -Raw -ErrorAction SilentlyContinue)
        if ($wfDocChange -notmatch '(?m)^## 1\.8\.0 \(2026-09-12\)') { Write-Host "  [ERRO] Changelog: falta a seção '## 1.8.0 (2026-09-12)'" -ForegroundColor Red; $wbErrors++ }
        foreach ($wfDocTema in @('Permissões', 'Parar', 'Windows Update', 'Rede sem fio')) {
            if ($wfDocChange -notmatch [regex]::Escape($wfDocTema)) { Write-Host "  [ERRO] Changelog: a seção 1.8.0 não fala de '$wfDocTema'" -ForegroundColor Red; $wbErrors++ }
        }
        $wfDocReadme = [string](Get-Content -LiteralPath (Join-Path (Get-Location) 'README.md') -Raw -ErrorAction SilentlyContinue)
        foreach ($wfDocBotao in @('Devolver ao padrão do Windows', 'Limpar backups antigos', 'Diagnóstico completo', 'Trocar pelo driver básico do Windows', 'Voltar para o driver que estava antes')) {
            if ($wfDocReadme -notmatch [regex]::Escape($wfDocBotao)) { Write-Host "  [ERRO] README: o botão '$wfDocBotao' não está documentado" -ForegroundColor Red; $wbErrors++ }
        }
        $wfDocRot = [string](Get-Content -LiteralPath (Join-Path (Get-Location) 'docs\roteiro-manual-1.8.0.md') -Raw -ErrorAction SilentlyContinue)
        if ([string]::IsNullOrWhiteSpace($wfDocRot)) { Write-Host "  [ERRO] Roteiro: 'docs\roteiro-manual-1.8.0.md' não existe - nada desta versão foi visto rodando numa máquina quebrada de verdade" -ForegroundColor Red; $wbErrors++ }
        else {
            foreach ($wfDocItem in @('remove-device', 'add-driver', 'inbox', 'KILL_ON_JOB_CLOSE', 'perfil grande')) {
                if ($wfDocRot -notmatch [regex]::Escape($wfDocItem)) { Write-Host "  [ERRO] Roteiro: falta o item '$wfDocItem'" -ForegroundColor Red; $wbErrors++ }
            }
        }
        Write-Host "  1.8.0: versão, changelog, README e roteiro manual no lugar"
    } catch {
        Write-Host "  [ERRO] 1.8.0: $($_.Exception.Message)" -ForegroundColor Red; $wbErrors++
    }
  ```

- [ ] **Step 2: Rodar e ver falhar**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest`
  - Esperado: `[ERRO] Versão: $sync.version = '1.7.0', esperado '1.8.0'` e `[ERRO] Roteiro: 'docs\roteiro-manual-1.8.0.md' não existe…`.

- [ ] **Step 3: Implementar** — `version.props` para `1.8.0`; a seção nova do changelog; o README; e o roteiro manual com os cinco itens do §8 que **nada nesta versão mediu**: que `remove-device` + `scan-devices` traz o adaptador de volta; que `add-driver /install` reamarra o driver ao dispositivo; que o driver inbox **funciona** com aquele rádio (o `Setup.exe` de 17 MB dentro do pacote Intel sugere que o fabricante espera um instalador, não só um INF); que a restauração de ACL termina em tempo aceitável num perfil grande e elevado; e que `KILL_ON_JOB_CLOSE` mata a árvore quando o WinForge é encerrado pelo Gerenciador de Tarefas. Os três limites de comportamento que o usuário lê entram no README: o Chipset INF pelo WU não tem Desfazer; ele não instala SMBus funcional, Intel ME/HECI, Serial IO, DPTF nem Rapid Storage (depois do lote, um "Dispositivo PCI" que precisava de driver de verdade continua sem ele e muda só o nome); e a recuperação do §5 depende de o backup de 120 MB caber no disco.

- [ ] **Step 4: Rodar e ver passar**
  - `build.cmd`
  - `dotnet test src\Launcher.Tests`
  - `git diff --exit-code -- docs/auditoria.md`
  - Esperado: `1.8.0: versão, changelog, README e roteiro manual no lugar`, `== SelfTest concluído: 0 erro(s) ==` nas duas rodadas, `OK: dist\WinForge.exe`, `Aprovado!  - Com falha:     0, Aprovado:    22`, e o `git diff` sem saída.

- [ ] **Step 5: Commit**
  `docs: permissões sem travar, escada de rede e drivers agrupados; release 1.8.0`

---

## Autorrevisão

**Cada seção da spec e a tarefa que a implementa**

| Spec | Tarefa |
|---|---|
| §1.1 caminhada, reparse, `\\?\`, `AreAccessRulesProtected`, arquivos fora | 1 |
| §1.2 `Denied` contando só `GetAccessControl`/`EnumerateFileSystemEntries`; veredito "Concluído com ressalvas" | 1 (contagem) e 3 (veredito) |
| §1.3 formato UTF-16LE sem BOM, nomes relativos, `Deny`; Fase 5 sem `/T` | 2 (arquivo) e 4 (Fase 5) |
| §1.4 backup obrigatório, destino escolhível, sete recusas, `Protect-WinForgeSnapshotFile`, aviso literal | 7 |
| §1.5 `Consumed`, mais antigo não consumido, recusa com pendente, `Test-WinForgeAclIndexOrigin` | 5 |
| §1.6 quatro tetos, espaço antes, `finally` do parcial, `Measure-WinForgeAclSaveEntry` por fluxo | 1 (tetos), 2 (contagem), 3 (espaço e `finally`) |
| §1.7 Desfazer, `AclCleanup`, textos, rótulo "Devolver ao padrão do Windows" | 5 (Desfazer), 6 (limpeza), 23 (textos no README) |
| §2 `-StreamTo`, escritor, `-NoCapture`, erro linha a linha | 8 |
| §2 anel, leitura por tique, 256 MB, retenção | 9 |
| §2 `ExpectMinutes`, âmbar 1,5× e 3× | 10 |
| §2 Job Object, `-NoElevate`, guarda do `Add-Type` | 11 |
| §2 Fase 4 fora do job e marcador de posse pendente | 12 |
| §2 textos do Parar, `Cancelado em mm:ss`, `Add_Closing` | 13 |
| §3.1 critério e as três constantes provisórias; campos novos da busca | 20 |
| §3.2 rótulos, cinco estados, instalação em lote, "Ver lista", `ActionLabel` | 21 |
| §3.3 o que nunca agrupar; relatório cru com coluna "Classe" | 20 |
| §4 filtro, ponto de restauração, textos e palavras proibidas | 22 |
| §5 tabela de seis botões | 14 (base), 15 (botão 1), 16 (botões 2 e 3), 18 (botões 4 e 6), 19 (botão 5) |
| §5.1 nove bloqueios, gate de build, `SM_REMOTESESSION`, ressalva de AnyDesk | 14 (bloqueios), 18 (ressalva do botão 4) e 19 (ressalva do botão 5) |
| §5.2 backup do driver, quatro conferências, três armadilhas, inbox independente de idioma | 17 |
| §5.3 exceção D3 | 19 |
| §6 seis entradas, Config 57 → 63, contraste ≥ 4,5:1 | 6, 15, 16, 18, 19 (entradas) · 10 e 21 (contraste) |
| §7 testes | os Steps 1 e 4 de cada tarefa |
| §8 limites conhecidos e roteiro manual | 23 |

**Varredura dos padrões proibidos** — sem "TBD", sem "implementar depois", sem "tratar os casos de borda", sem "escrever testes para o acima" e sem "parecido com a Tarefa N": cada tarefa repete o código de teste de que precisa. As referências cruzadas que existem são declarações de dependência com assinatura completa (Tarefa 4 → Tarefa 3; Tarefa 6 → Tarefa 5; Tarefa 12 → Tarefa 11; Tarefa 22 → Tarefas 20 e 21), não remissões a código não escrito.

**Esforço por tarefa** — julgamento alto (Fable 5 / Opus máximo): 1, o par 3 + 4, 5, 11, 12, 13 e 21. Mecânico, com o código já escrito aqui (Opus 5, esforço alto): 2, 6, 15, 16, 18, 19, 20, 22 e 23. As demais ficam no padrão do dia a dia.

---

## Julgamento das revisões

**Conflitos entre tarefas**

1. `HardwareIds` ausente no grupo da Tarefa 20 e exigido pelo filtro da 22 — **acatado**: o campo entra na interface do grupo, vem dos membros reais, e o teste da 22 passou a montar o grupo pelo agrupamento em vez de injetá-lo à mão.
2. A Tarefa 22 quebraria as duas travas do teste da 21 (`MessageBox` = 1 e o `-NoUI` esperando "7") — **acatado**: a 21 passou a contar a caixa de **reinício** (`MessageBoxImage::Information`) e seu grupo de teste ganhou `HardwareIds` fora do `VEN_8086`, de modo que não é chipset e o lote roda sem portão.
3. `Format-WinForgeWindowsUpdateGroupRow` não entregava `Class`/`HardwareIds` para a Tarefa 22 ler — **acatado por conta própria**, achado ao conferir o par: a linha passou a carregar `Group`, o grupo cru inteiro.
4. Tarefa 5 sozinha deixa o botão pior que hoje (índice da 1.7.0 vira pendente e recusa tudo, apontando um botão da 6) — **acatado**: 5 + 6 vira par indivisível declarado, com o motivo escrito nas duas tarefas.
5. A Tarefa 8 citava `:2769`, que a Tarefa 3 apaga — **acatado**: a lista de chamadas foi reescrita para o estado pós-3/4 (fase 3, fase 4 e o laço da fase 5).
6. `Invoke-WinForgeAclOwnerFallback` ficava fora do fluxo — **acatado**: as três trocas de posse entram na Tarefa 8, com teste próprio.
7. Tarefa 5 com 4 funções no Produces, "três" no Files e 5 no Step 3 — **acatado**: `Test-WinForgeAclRestoreAllowed` entra na interface e a contagem virou cinco.
8. `Get-WinForgeAclScopeVerdict` usada no teste da 3 e ausente do Produces — **acatado**: declarada com assinatura.
9. Tarefa 11 com prosa falando de `-Root` e SelfTest desligado que o código do teste não fazia — **acatado**: `-Root` entra nas três assinaturas do marcador e o teste (agora Tarefa 12) liga e desliga `$sync.SelfTest` explicitamente.
10. Deriva de ~10 linhas nas referências de `wf-repair.ps1` — **acatado onde foi conferido** (`Invoke-WinForgeAclOwnerFallback` em `:2919`, o `$indices[$indices.Count - 1]` em `:3048`); as demais seguem como estavam, são âncoras de leitura e não de edição cega.

**Qualidade dos testes**

11. `@($h)[0]` não é splat: os quatro tetos da Tarefa 1 rodavam com o padrão — **acatado**, virou `$wfCamArgs = …; @wfCamArgs`.
12. `Reparse ≥ 1` + "sem duplicata" + "1 entrada" deixam passar contar **e** empilhar a junção — **acatado**: contagem exata `Scanned -eq 4` e `Reparse -eq 1`, com `Scanned` deixando de contar ponto de reanálise na implementação para os dois números fecharem.
13. `-IncludeFiles` cobrado só por "aumentou" — **acatado**: exatamente `Scanned + 1`.
14. Ausência de BOM não prova UTF-16LE — **acatado**: os dois primeiros bytes têm de ser `0x70 0x00`.
15. Nada provava que a restauração chama `Test-WinForgeAclRestoreAllowed` — **acatado**: o teste cobra a chamada **e** que ela venha antes da caminhada.
16. `-notmatch 'Count - 1'` casa comentário — **acatado**: ancorado em `\$indices\[…\]`, e a condição invertida do original foi endireitada.
17. Job Object provado só por grep — **acatado**: o teste cria o job, prende um `cmd /c ping` próprio, chama `TerminateJobObject` e cobra que o filho morreu em 5 s.
18. `$wfParGuarda` quebrado (`-Namespace WinForgeProva` × guarda `'WfJobProva'`) — **acatado**: mesmo nome nas duas pontas, e a explicação do porquê ficou no comentário.
19. `-match 'ProblemCode'` reprovaria a implementação correta — **acatado**: `ProblemCode\b(?!s)`.
20. `PROVISÓRIO` procurado no arquivo inteiro se autoaprova — **acatado** (achado da mesma família): a marca passou a ser cobrada na linha de cada constante.
21. `DriverProvider = Microsoft` cobrado por `-match "Microsoft"` na fonte — **acatado**: `Test-WinForgeWifiOutcome` ganha `-Generic` e o teste mede comportamento, mesmo adaptador com dois fornecedores.
22. `Invoke-WinForgeWifiDriverReinstall` nunca chamada — **acatado**: entra `-DryRun -Facts`, com recusa na bateria e sem listar `/remove-device`.

**Ordem e risco**

23. Mover a Tarefa 6 para o início — **recusado**: ela consome `Get-WinForgeAclIndexList` e `New-WinForgeAclIndexOrigin` da Tarefa 5, e o teste dela grava um índice com `New-WinForgeAclIndexOrigin`; "não consome nada de 1 a 5" não é verdade. O risco real que o revisor viu é o do item 4, e o par indivisível o fecha.
24. Escrever por que a Tarefa 8 vem depois de sete tarefas — **acatado**: a razão (ela reescreve as mesmas chamadas que a 3 e a 4 mexem) está nas constraints globais.
25. Marcar 18 + 19 como par indivisível igual a 3 + 4 — **recusado**: com as duas linhas de `WifiDriverGeneric` movidas para a Tarefa 19, a 18 fecha verde sozinha, e 4 + 6 sem o 5 é produto incompleto, não pior. A spec §5 exige o 6 como condição do 4 e do 5, e é o 6 que sai junto do 4.
26. Dividir a Tarefa 11 em duas — **acatado**: 11 fica com o encanamento do cancelamento e o Job Object; 12, com a Fase 4 fora do job e o marcador de posse. São duas decisões independentes e dois arquivos.
27. Dividir a Tarefa 21 (antiga 20) — **recusado**: os cinco estados, a linha e a instalação em lote são um objeto só; separá-los cria uma tarefa cujo único consumidor é a seguinte. O risco de deadlock mora no callback, que pertence à instalação. A tarefa segue marcada como de julgamento alto e é a mais perigosa do plano.
28. Fundir a Tarefa 16 na 15 — **recusado**: a constraint global manda uma entrada de config por tarefa, com a trava subindo no mesmo commit. Fundir põe duas entradas e duas travas num commit só.
29. Fundir a Tarefa 10 na 13 — **recusado**: a 13 já é a segunda maior do plano, e `Get-WinForgeFollowHeader` é consumida pelo tique da 9 antes de o botão Parar existir.
30. Constraint exigindo `dotnet test` e `git diff` em cada tarefa sem nenhum Step 4 cumprindo — **acatado**: a exigência é que estava errada; agora `build.cmd` vale para toda tarefa, e os outros dois para a Tarefa 23 e para quem tocar `src/Launcher*` ou `docs/`.
31. Textos de recusa do Desfazer sem dono — **recusado**: o teste da Tarefa 5 já cobra a frase literal (`coloque-a de volta em`) dentro de `Invoke-WinForgeAclUndo`, e a Tarefa 7 cobra a variante do disco externo.
32. Menor corte entregável (1 a 6 + 23) e esforço por tarefa — **acatados**: os dois viraram linha escrita, um nas constraints, outro no fim da autorrevisão.
