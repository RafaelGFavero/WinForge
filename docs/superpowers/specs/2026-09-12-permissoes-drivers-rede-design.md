# WinForge 1.8.0 — permissões, drivers e rede

Data: 12/09/2026 · alvo **1.8.0** · base `main` `f68da5e`. Toda medição citada aqui está nos relatórios de
`C:\Users\rafa_\AppData\Local\Temp\winforge-plan9`; esta spec guarda as decisões, não a prova.

## Objetivo

O botão das permissões do disco C: enche o disco e trava a máquina — numa máquina real, **~205 GB em 404 min** ainda
na Fase 2, contra **73 MB** de backup legítimo. É o único item que segue causando dano em produção. Junto vão memória e
Parar (§2), agrupamento dos INFs sem versão do WU (§3), o Chipset INF pela via do WU (§4) e a escada de rede (§5).
**Nada aqui baixa ou executa instalador de terceiro**; a exceção da NVIDIA é a única e não se estende à Intel. D2:
**não há hotfix 1.7.1** — a Fase 5 sai consertada no 1.8.0.

---

## 1. Permissões sem travar a máquina

**Causa.** Os comentários de `wf-repair.ps1:2400-2406` e `:2561` afirmam que `/L` poda a travessia. Não poda. O laço é
`AppData\Local\Dados de Aplicativos` → `AppData\Local`, junção para o próprio pai, alcançável por dois caminhos; quem
para a recursão é o limite de **63 saltos de reparse**, não `MAX_PATH`, e isso dá ~50 GB, **≥ 2.800×** o backup
legítimo. A superfície do icacls é `/T /C /L /Q`, sem `/XJ` e sem teto de profundidade: **`icacls … /T` não é
utilizável sobre pasta de perfil**.

### 1.1 A caminhada nova

A Fase 2 troca `icacls /save /T` por caminhada em pilha que lê `[IO.File]::GetAttributes` antes de empilhar.

- **`ReparsePoint` nunca é empilhado e nunca vira entrada.** As duas coisas: o .NET lê a ACL do alvo e
  `icacls /restore … /L` a devolve ao link — guardar uma e aplicar na outra troca permissão por permissão.
- **`EnumerateFileSystemEntries(..., AllDirectories)` proibido**: medido, segue reparse point e entra em laço.
- **Prefixo `\\?\` em toda chamada .NET**: `LongPathsEnabled = 1` da máquina de investigação **não é o padrão**, e sem
  ele caminho longo dá `PathTooLongException` no PC do usuário.
- **`GetAccessControl($p)` + `GetSecurityDescriptorSddlForm('Access')`**, nunca `AccessControlSections::All`, que
  **lança sem `SeSecurityPrivilege`** (medido). Foi essa combinação que saiu igual ao `icacls /save`.
- **O filtro é `AreAccessRulesProtected`**, não "tem ACE explícita": `/inheritance:e` só altera item com herança
  bloqueada, e o aplicado tem de ser o guardado. Em 39.582 pastas, 381.880 entradas / 174,41 MB hoje contra **338 /
  103,4 KB / 39 s**.
- **Arquivos ficam fora** (`-IncludeFiles` nasce desligado; 84 protegidos em 294.011, cache) e por isso **a Fase 5
  também cobre só pastas**.

```powershell
Get-WinForgeAclContentScope -Path <string> [-IncludeFiles]
    [-MaxItems 20000] [-MaxBytes 4194304] [-MaxDepth 32] [-MaxSeconds 90]
  → @{ Ok; Reason; Entries=@(@{Name;Sddl}); Scanned; Reparse; Denied; DeniedPaths; Deny; Bytes; Seconds }
Write-WinForgeAclContentBackup -Path <string> -Entries <object[]>  # único que grava; lança se $sync.SelfTest
Test-WinForgeAclContentRoot -Path <string> -ProfilePath <string>   → @{ Ok; Reason; Path; Warning }
Get-WinForgeAclContentHash  -Path <string>                         → @{ Ok; Reason; Hash }
Test-WinForgeAclIndexOrigin -Index <object>                        → @{ Ok; Reason }
```

### 1.2 `Denied` — nunca sucesso silencioso

`Denied` conta `GetAccessControl`, `EnumerateFileSystemEntries` **e o `GetAttributes` que lança**. As duas primeiras são
a regra geral. O `GetAttributes` é o caso de borda que a revisão da Tarefa 1 mediu: em pasta negada ele **não lança** —
por isso ele sozinho daria zero justo onde há problema — mas quando lança por outro motivo, tratar a falha como "não é
ponto de reanálise" faz a caminhada DESCER na junção e reabre o laço que esta seção existe para fechar. Falha ao ler o
atributo é recusa, não permissão.

Em máquina já quebrada, `GetAccessControl` falha nas pastas que mais importam; elas ficam fora da lista e, como a Fase
5 agora percorre só a lista, **deixam de ser consertadas** (a 1.7.0 as alcançava pelo `/T`). Então `Denied > 0` muda o
veredito: cabeçalho `Concluído com ressalvas`, a contagem, as 20 primeiras de `DeniedPaths`, e a frase de que essas
pastas **não foram copiadas nem alteradas**. Posse / `SeBackupPrivilege` fica fora desta versão.

### 1.3 O arquivo, escrito pelo motor

Formato medido no arquivo real: pares `<nome relativo>CRLF<SDDL>CRLF`, **UTF-16LE sem BOM**
(`UnicodeEncoding($false,$false)`), nomes relativos à pasta acima do perfil. Desfazer segue
`icacls <Target> /restore <File> /C /L`. **Ordem de ACE:** 34 das 338 diferem só na ordem — irrelevante sem negação, e
**0 das 338 têm negação**; a função devolve `Deny`, e com `Deny > 0` essas entradas passam por `icacls /save` real.

**Fase 5 sem `/T`:** `icacls <pasta> /inheritance:e /C /Q` por entrada da mesma lista; a ordenação ordinal entrega pai
antes de filho. Sem isso, consertar só a Fase 2 **move o travamento para depois da Fase 4**. Conserta de quebra um
defeito da 1.7.0, em que `/T /L` liga herança **fora do perfil**, no destino de cada junção e no OneDrive.

### 1.4 Backup obrigatório, destino escolhível (D1)

Backup de conteúdo **ligado, não opcional** — a 103,4 KB não há o que economizar. **O opcional é o destino**, pela
caixa "Guardar o backup das permissões em outro disco", **desmarcada por padrão**. O índice fica sempre em
`%ProgramData%\WinForge\acl-backup` e é ele que o Desfazer lê; **só o arquivo de conteúdo sai**, com caminho e
**SHA-256** no índice, recalculado no Desfazer com o arquivo aberto em `FileShare.Read`.

Caminho vindo do `FolderBrowserDialog` — viável: o processo nasce **STA** e o relançamento `-Verb RunAs`
(`WinForge.ps1:83/85`) preserva isso —, **nunca de variável de ambiente**. `Test-WinForgeAclContentRoot` **recusa por
padrão**; sete exigências: absoluto e não-UNC; não ser raiz de volume; `DriveFormat -eq 'NTFS'` (exFAT/FAT32 não
guardam DACL e não dão erro); `DriveType` Fixed ou Removable; nem dentro nem contendo o perfil; nenhum reparse point na
cadeia; espaço livre com folga. **O arquivo de conteúdo, dentro ou fora do `%ProgramData%`, passa por
`Protect-WinForgeSnapshotFile` (`wf-server.ps1:889`)** como o índice já passa; falhou, recusa. Aviso literal:

> Fora da pasta do WinForge, qualquer conta de administrador — desta máquina ou de outra onde o disco for ligado — pode
> ler, alterar ou apagar este arquivo. O WinForge percebe a alteração e recusa restaurar, mas não recupera arquivo
> apagado. Em pen drive ou HD externo: disco desligado na hora de desfazer é a mesma coisa que não ter backup.

### 1.5 Um índice por vez, e desta máquina

**Defeito da 1.7.0 que esta versão fecha.** O Desfazer lê `$indices[$indices.Count-1]` (`:3044`), o **mais novo**. Na
2ª execução a Fase 5 da 1ª já removeu a proteção de herança e o escopo cai para perto de zero, mas `$gravados` continua
maior que zero porque os itens `sddl` das fases 3/4 entram sempre (`:2760-2769`): o índice novo vira o único visível e
**as 338 originais viram irrecuperáveis**. Conserto: campo `Consumed`, virado `$true` por um Desfazer bem-sucedido; **o
Desfazer lê o mais antigo não consumido**; **nova restauração é recusada enquanto existir índice não consumido**,
mandando usar Desfazer ou "Limpar backups antigos".

`Test-WinForgeAclIndexOrigin`: o índice guarda `MachineGuid` e **SID do perfil**; divergência recusa. Sem isso, índice
de outra máquina aplica SDDL com SIDs alheios, que entram como SID cru e trancam o perfil — o SHA-256 protege o arquivo
de conteúdo, não a procedência do índice.

### 1.6 Tetos

`MaxItems` 20.000 (medido 338) · `MaxBytes` 4.194.304 (103,4 KB) · `MaxDepth` 32 (24) · `MaxSeconds` 90 (39,2 s).
Estourar devolve `Ok=$false` e `Entries` **vazio**, nunca o coletado até ali. **A restauração para e não há "continuar
mesmo assim"**: um escape reintroduziria o Desfazer que não desfaz, que é o que D1 matou. Uma caixa, um botão:

> A cópia das permissões não ficou pronta em 90 segundos. Sem ela não haveria como desfazer, então nada foi alterado.
> Tente de novo com o computador recém-ligado.

Mais três travas: espaço livre conferido **antes**; **`finally` que apaga o arquivo parcial** (hoje o descarte está
dentro do laço, `:2778/2790/2797`, e não roda se o processo morre); **`Measure-WinForgeAclSaveEntry` (`:2259`) lê por
fluxo** — hoje é `Get-Content` sem `-Raw` materializado em array, `OutOfMemoryException` garantida sobre um backup
antigo grande, que ela continua lendo.

### 1.7 Desfazer, limpeza e textos

Não muda no Desfazer: recusa individual de item sem arquivo (`:3207-3216`), guarda `$gravados -eq 0`, reversibilidade
das fases 3 e 4 pelo SDDL do índice. Muda: conjunto coberto = conjunto alterado (338/338); `Sha256` e `ExternalPath` no
item de conteúdo, com recusa própria e, no caminho ausente, dizendo qual disco ligar; `Consumed` e a origem de §1.5.
Toda recusa termina com *"Nada foi alterado. Se tiver uma cópia do arquivo original, coloque-a de volta em <caminho> e
tente outra vez."* Perde-se, escrito: arquivos dentro do perfil (84 de 294.011, cache); `/inheritance:e` liga herança,
não remove ACE explícita; **OneDrive em Sob Demanda fica fora do backup — e também fora da Fase 5, então o par é
consistente**; e as pastas de `Denied`.

**`Permissões do disco C: — Limpar backups antigos`** (`AclCleanup`): lista `acl-backup` com tamanho e data, marca como
órfão o arquivo que nenhum índice referencia, apaga sob confirmação; na inicialização, varredura que **só relata**
acima de 1 GB. É a saída de quem matou o 1.7.0 na Fase 2 e ficou com centenas de GB numa pasta que só SYSTEM e
Administradores apagam.

Botão principal: **`Permissões do disco C: — Devolver ao padrão do Windows`**. Confirmação:

> Devolve as permissões de arquivos e pastas do disco C: ao padrão do Windows. Leva de 10 a 20 minutos e a janela
> precisa ficar aberta. Antes de mexer, o WinForge guarda uma cópia das permissões atuais para você poder desfazer.
> Programas abertos podem perder acesso a arquivos enquanto isso roda — feche o que der.

---

## 2. Janela de saída, memória e Parar

**Causa.** Não é o `TextBox`. As fases 2 a 5 chamam `Invoke-WinForgeNativeCommand` **sem `-StreamTo`**
(`wf-repair.ps1:2769, 2843, 2881, 2908`), caindo no `Out-String -Width 4096` (`wf-commands.ps1:471-475`); o
`Write-Host` seguinte vira **uma** linha de centenas de MB. Medido: **135 MB → 1.575 MB de pico**, **11,7×**.

**Conserto.** `-StreamTo` nas fases 2 a 5, via `Invoke-WinForgeStreamStep`, mais três sem as quais um gargalo vira
outro: `Write-WinForgeStreamLine` (`:298-300`) abre e fecha o arquivo por linha (99× mais lento que um escritor
persistente); `Invoke-WinForgeStreamedProcess` (`:339,353,367`) acumula num `StringBuilder` que o único chamador
descarta → `-NoCapture`, `Text=''`; `StandardError.ReadToEndAsync()` (`:350,357`) junta o erro sem teto, que aqui **é**
o volume → ler linha a linha numa `Task` que escreve no `StreamWriter`, com trava.

**Tetos.** Anel de **4 MB → 2 MB com histerese**, blocos de 512 KB (medido: pico cai de 971 MB para 274 MB; teto rígido
de 2 MB em blocos de 64 KB foi descartado por levar 393 s). Leitura por tique: cresceu mais de 8 MB → `Length - 1 MB`,
cortando na primeira quebra de linha. Bloco por tique: manter 512 KB (`:867`). Arquivo de saída: **256 MB por
execução**, e ao passar, uma linha dizendo que os detalhes dali em diante foram descartados. Retenção **30 dias / 20
arquivos por prefixo**. `IsUndoEnabled = $false` não muda nada — **não mexer**. `ExpectMinutes` entra na especificação
do comando (`AclRestore` 15, `AclUndo` 10, `sfc` 10, `DISM` 20, WU 20, a calibrar); a 1,5× o cabeçalho fica âmbar com
*"Está demorando mais que o normal (o comum são N minutos). Continua rodando. Não feche esta janela — se precisar
parar, use o botão Parar."*, e a 3× o mesmo com o Parar em destaque.

**Parar, com Job Object.** Não existe cancelamento em `src/Engine/`, e medido: `powershell.exe` morto com
`Stop-Process -Force` **deixa vivo** o filho `UseShellExecute=$false` — fechar o WinForge deixa um `icacls.exe` elevado
reescrevendo ACL de sistema. Entra Job Object, com três ajustes que a medição impôs:

- **`Add-Type` dentro do scriptblock do pool**, guardado por `if (-not ('WfJob' -as [type])) { Add-Type … }`. Medido:
  tipo criado na runspace principal não é visto no pool, e um segundo `Add-Type` do mesmo nome falha.
- **`KILL_ON_JOB_CLOSE` não vale para a Fase 4.** Proibimos cancelar dentro de `Invoke-WinForgeAclOwnerFallback` para
  não morrer entre "posse aos Admins" e "posse de volta" — e um job que mata a árvore quando o processo morre faz
  exatamente isso pelo Gerenciador de Tarefas. **Os processos da Fase 4 não entram no job.** Antes da troca de posse o
  motor escreve `acl-posse-pendente.json` com a pasta e o dono original e apaga depois de devolver; na abertura
  seguinte, marcador presente → **relata** e oferece o botão, nunca conserta sozinho.
- **`-NoElevate` (`WinForge.ps1:21`) não pode prometer Parar**: medido, `OpenProcess` sobre processo elevado, de pai
  não elevado, devolve `handle=0 err=5`.

Encanamento: `$sync.WinForgeStreamCancel` e `$sync.WinForgeStreamJob`, hashtables sincronizadas chaveadas pelo caminho,
iguais a `WinForgeStreamDone/Exit` (`:906-907`); atribuição ao job antes do `Start()`; limpeza no `finally`
(`:362-365`); `Invoke-WinForgeStreamedSteps` (`:1165-1172`) checa a flag antes de cada passo.

**Textos do Parar**, obrigatórios: botão à esquerda do `Fechar`, mesmo `$novoBotao` (`:727`), só com `-FollowPath`,
habilitado enquanto `WinForgeStreamDone[$path]` for falso; confirmação com **Não** como padrão, dizendo "Nada foi
alterado até agora" em fase de leitura e "Algumas pastas já foram alteradas; o Desfazer cobre todas elas" em fase de
escrita; depois do sim, botão `Parando…` desabilitado e cabeçalho `Parando: <título> (mm:ss)`; na janela protegida da
Fase 4, **`Parar (aguarde alguns segundos)`**; parada na Fase 4, `Parado a pedido. As pastas <lista> já foram
reescritas com o padrão do Windows; as demais ficaram como estavam. O backup da Fase 2 está completo — use "Desfazer
(restaurar backup)" para voltar ao estado anterior.`; parada na Fase 5, `Parado a pedido durante a herança do perfil:
ela foi ligada só em parte de <perfil>. Rode a restauração de novo para terminar, ou use "Desfazer" para voltar tudo.`;
no fim, **`Cancelado em mm:ss`**, nunca `Concluído`.

Cancelar na Fase 2 apaga os parciais e **não escreve o índice** (`:2821` é o último passo da fase), então o Desfazer
segue apontando para o conjunto anterior — o correto. O `Add_Closing` passa a cancelar de verdade e esperar.

---

## 3. Drivers do Windows Update agrupados

`Select-WinForgeWindowsUpdateLatest` (`wf-drivers.ps1:388`) está certa e não muda. O agrupamento é segunda camada,
dentro de `Update-WinForgeDiagnosticsWindowsUpdateGrid`; `$sync.DiagWUResults` e `$sync.DiagWUUpdates` seguem inteiros,
porque é escolha de vista. Assinatura:
`Group-WinForgeWindowsUpdateNullDrivers -Rows <Kept> -MinGroup 5 -MaxBytes 262144 → @{ Rows; Groups }`.

### 3.1 Critério — parametrizado (D4)

Quatro condições simultâneas, nenhuma baixa nada: (1) `Version -eq $null`, nenhum número no título; (2) `Class` numa
**lista de permissão fechada**, comparada com `.Trim().ToLowerInvariant()`; (3) `SizeBytes` entre 1 e o corte, sendo
`MaxDownloadSize` e, se vier 0, `MinDownloadSize` — desconhecido nos dois **não agrupa**; (4) grupo com ≥ `MinGroup`
membros.

**Os valores de (2), (3) e (4) são PROVISÓRIOS, em constantes num único lugar**, no topo de `wf-drivers.ps1`:

```powershell
$script:WinForgeNullDriverMaxBytes = 262144   # PROVISÓRIO — 256 KB
$script:WinForgeNullDriverMinGroup = 5        # PROVISÓRIO
$script:WinForgeNullDriverClasses  = @('', 'system', 'other hardware', 'unknown', 'outro hardware')  # PROVISÓRIO
```

Motivo: a busca da WUA nesta máquina devolveu **0 ofertas de driver**, e `DriverClass`, `MaxDownloadSize` e
`Categories` nunca foram vistos numa oferta real de INF sem versão; o corte de 256 KB veio do `DriverStore` local, onde
pacote sem binário tem mediana 7.662 B e com binário 180.064 B. `Coletar-OfertasWU.ps1` já foi entregue para rodar na
X99. **Chegando os dados, muda-se a constante e mais nada** — e por isso **os testes leem a constante, nunca o
literal**.

Propriedades novas em `Search-WinForgeWindowsUpdateDrivers`, no `try/catch` já usado para `$class`:
`MaxDownloadSize`/`MinDownloadSize` → `SizeBytes`; `DriverHardwareID` → `HardwareId`; **`DeviceProblemNumber` →
`ProblemCode`, que NÃO participa do critério** — lido só para o texto de §4. Os relatórios não se contradizem:
`drivers-wu.md:126` o recusa como critério (as linhas a agrupar são justamente as de problema 28) e
`chipset-inf.md:335` o exige para saber se há mesmo dispositivo sem nome. `Categories.Name` segue descartado: vem no
idioma de `UserLocale`. Chave: `($provider + [char]1 + $class + [char]1 + $date).ToLowerInvariant()` — **a data entra**
para amarrar o lote a uma publicação de INF.

### 3.2 Interface

Mesmas seis colunas, **zero mudança no XAML delas**. Atualização: `Intel — 47 itens que só dão nome a componentes da
placa-mãe`; Driver: `47 dispositivos`; Versão: `sem número de versão`; data anterior a 1990: `sem data confiável`;
Instalar: `Instalar todos (47)`. **A palavra "chipset" não entra no rótulo**: ele nasce de `Provider` e classe, mais
frouxos que o filtro de §4, e dizer "chipset" ali afirmaria o que §4 proíbe afirmar. O grupo ocupa a posição da
primeira linha que o originou; as não agrupadas mantêm a ordem. Campos novos: `IsGroup`, `Members` (ids reais, ordem
original), `MemberTitles`, `UpdateId = 'grupo:' + <hash da chave>` — o id sintético faz
`Get-`/`Set-WinForgeWindowsUpdateRowState` funcionarem sem mudança. **Lista expandida na janela de saída existente**,
por um botão "Ver lista" numa coluna "Detalhes"; **nada de `RowDetailsTemplate` nem expander**, porque
`wf-xaml-styles.xml:334-344` registra que gabarito próprio de célula quebra a rolagem da aba.

**Estado do grupo derivado a cada remontagem, nunca armazenado.** Com `N` total, `I` instalados, `F` falhados, `A`
instalando: tudo zero → pendente, habilitado; `A≥1` → `instalando 13 de 47...`, desabilitado; `I=N` → `47 de 47
instalados` (+ ` (reinicie)`), desabilitado; `I+F=N, F≥1` → `45 de 47 instalados, 2 falharam`, habilitado; `I+F<N, A=0`
→ `12 de 47 instalados, 1 falhou, 34 pendentes`, habilitado. **O segundo clique instala só os que não estão
instalados.**

Instalação: **um único `Invoke-WPFRunspace` com `foreach` sobre `$Row.Members`**, em
`Invoke-WinForgeWindowsUpdateGroupAction` — um job por membro disputaria a trava `CommandRunning` consigo mesmo. Um
tique por membro pelo caminho existente (`$sync.LastWUInstallId/Code/Reboot` + `Invoke-WPFUIThread`), com o callback
sendo **scriptblock de escopo de arquivo criado na runspace principal, sem exceção**. Falha não interrompe o laço;
entre membros confere `$sync.WinForgeClosing` e um `$sync.WUGroupCancel` novo; **um único `MessageBox` de reinício no
fim**. Única mudança no `CellTemplate`: `Content="{Binding ActionLabel}"`, padrão que `wf-xaml-diag-tab.xml:68` já usa.

### 3.3 O que nunca agrupar

> Qualquer dúvida, a linha fica sozinha. O erro barato é mostrar uma linha a mais; o erro caro é esconder o driver que
> o usuário veio buscar.

Título com versão. Classe fora da lista — é lista de **permissão**, então classe nova, traduzida ou ausente fica
visível. **`Firmware`, `SoftwareComponent` e `Extension`** ficam escritos à parte, mesmo já caindo pela condição 2.
Tamanho desconhecido, porque falta de dado é motivo para **mostrar**. Tamanho acima do corte. Grupo abaixo de
`MinGroup`. Fornecedor, classe ou data diferentes. `Export-WinForgeDiagnosticsReport` (`wf-diag.ps1:1535`) **continua
cru**; ganha a coluna "Classe" e a nota de quantos itens a aba agrupou.

---

## 4. Chipset INF pela via do Windows Update

**Não é botão novo nem entrada de config.** É o filtro, o ponto de restauração e o texto que cercam o botão `Instalar
todos (N)` da linha de grupo de §3.2 quando o grupo passa no teste de chipset. Instalar de uma vez as N entradas pelo
WU **é** o Chipset INF Utility. Descartados: `SetupChipset.exe` quebraria a perna que sustenta a exceção da NVIDIA
(consulta à API pública ao vivo no clique), e a Intel não tem API equivalente; a página do SKU X99 (81761) marca
**Discontinued**; `winget search chipset` → **0 pacotes**; o Chocolatey baixa de espelho de terceiro.

Filtro, com campos já lidos: `DriverClass -eq 'System'` (obrigatório) **e** `DriverProvider` casando `^intel$` sem
caixa **e**, de reforço, `DriverHardwareID` começando em `PCI\VEN_8086&DEV_`. Classe `System` =
`{4d36e97d-e325-11ce-bfc1-08002be10318}`, invariante de idioma; vídeo é `Display`, rede `Net`, áudio `MEDIA`. **Não
filtrar por "chipset" no título**: `INTEL - System - 10.1.1.44` não contém a palavra e é o pacote do X99. **Classe
vazia cai em não classificado**, jamais em "é chipset".

**Ponto de restauração antes do lote**, porque a Intel documenta (000023446) INF de chipset do WU sobrescrevendo o
driver funcional do SMBus. `New-WinForgeChipsetRestorePoint` roda **uma vez, antes do primeiro membro**, dentro de
`Invoke-WinForgeWindowsUpdateGroupAction`. `Checkpoint-Computer` é **silenciosamente ignorado** com Proteção do Sistema
desligada ou dentro da janela de 24 h, então a função lê `Get-ComputerRestorePoint` antes e depois e confere que
apareceu sequência nova. Não apareceu → **o lote não roda**, dizendo se a Proteção está desligada (e onde ligar) ou se
já houve ponto nas últimas 24 h (e que dá para seguir criando um à mão). **Esta ação não tem Desfazer no WinForge**, e
o aviso aponta "Propriedades → Driver → Reverter Driver" como a única volta.

> **O que muda:** o dispositivo deixa de aparecer como "Dispositivo PCI", "Controlador de barramento SM" ou
> "Dispositivo de sistema base" com ponto de exclamação, e passa a mostrar o nome real no Gerenciador de Dispositivos.
>
> **O que não muda:** desempenho. Estes arquivos só informam ao Windows o nome do componente — não são o driver que faz
> o dispositivo funcionar. A própria Intel diz que, fora de uma instalação do Windows, não é preciso instalar.

Sem nenhum membro com `ProblemCode = 28`: `Nenhum dispositivo deste PC está sem nome. Instalar não traria efeito
visível.` **Palavras proibidas:** "otimiza", "melhora o desempenho", "atualiza o chipset", "driver de chipset". A
confirmação diz o que fica de fora ante o pacote da Intel — cobertura offline, versão de pacote, registro em
"Aplicativos e recursos" — e, em destaque, **que não há como desfazer pelo WinForge**.

---

## 5. Rede sem fio

"Conectado certinho" prova que o rádio associou e autenticou: driver quebrado não associa. O sintoma é DHCP/APIPA, DNS,
rota, proxy ou filtro de software, nessa ordem, e é essa a ordem da escada.

| # | Botão | O que faz |
|---|---|---|
| 1 | `Rede — Diagnóstico completo` (`NetDiagFull`, `read`) | rádio físico, perfil, IP/APIPA, rota, DNS do sistema contra `1.1.1.1`, NCSI, proxy, filtros NDIS, Winsock, MTU, IPv6, problema de dispositivo |
| 2 | `Rede — Redefinir` (existente) | ganha o texto do que **não** faz |
| 3 | `Rede — Limpar cache de DNS e pegar endereço novo` (`NetDnsRenew`) | `flushdns`, `release`, `renew`, `nbtstat -R` |
| 4 | `Rede sem fio — Reinstalar o driver que já está instalado` (`WifiDriverReinstall`) | exporta, `/remove-device`, `/scan-devices` |
| 5 | `Rede sem fio — Trocar pelo driver básico do Windows (pode ficar sem Wi-Fi)` (`WifiDriverGeneric`) | exporta **todos** os OEM, `/delete-driver /uninstall` em todos, reenumera |
| 6 | `Rede sem fio — Voltar para o driver que estava antes` (`WifiDriverRestore`) | `/add-driver … /install`, `/scan-devices` |

O rádio é achado por `Get-NetAdapter -Physical` com `PhysicalMediaType -like '*802.11*'` e `-not Virtual` —
independente de idioma e, medido, separa o rádio Intel dos sete adaptadores virtuais de VPN desta máquina. **Nada de
`Test-NetConnection -Port`** (medido 5.443 ms por chamada): `TcpClient` com `BeginConnect` + `WaitOne(2000)`, ou
`-InformationLevel Quiet`. Base medida em máquina saudável: **28 entradas Winsock**, todas `mswsock.dll` sob
`%SystemRoot%`; outro caminho, ou `Protocol Chain Length > 1`, é LSP de terceiro. **Norton não vira botão:** o
relatório nomeia o produto, escreve o caminho de menu, e diz que **se o antivírus é a causa, remover e reinstalar o
driver de WiFi não conserta nada e ainda arrisca deixar a máquina sem rádio**.

**O veredito de uma frase** do botão 1 é o texto mais lido do recurso, escolhido de lista fechada:

> - `O computador não pegou endereço do roteador (está em 169.254.x.x). Comece por "Limpar cache de DNS e pegar endereço novo".`
> - `O endereço está certo, mas o servidor de nomes configurado não responde e o 1.1.1.1 responde. O problema é o servidor de nomes, não o Wi-Fi.`
> - `Há um filtro do <produto> preso em todos os adaptadores. Desligue-o em <caminho de menu> e teste de novo antes de mexer em driver.`
> - `O roteador entrega endereço e nome, mas nada sai para fora. O problema está no roteador ou no provedor, não neste computador.`
> - `Não encontrei nada errado na rede deste computador.`

**Por que o 5 apaga todos os OEM:** medido, o rádio tem três candidatos e a classificação menor vence, então apagar só
o instalado entregaria um Intel de 2014 e **mentiria sobre o que fez**. Confirmação por digitação
(`VOLTAR AO GENERICO`), com:

> Se o driver básico não funcionar com este Wi-Fi, o computador fica sem rede sem fio até você trazer o driver por cabo
> ou pen drive. Tenha um cabo de rede à mão antes de continuar.

**O botão 6 é a condição para os 4 e 5 existirem.** `/install` **propõe**, não impõe: o texto **não pode afirmar
"driver restaurado"** — confere com `Get-NetAdapter` depois e relata. Se ainda assim não houver rádio, o texto final
manda ligar cabo de rede ou trazer o driver em pen drive de outro computador, **com o nome do adaptador e o fabricante
na tela**. **Verificação depois de 4, 5 e 6**, três desfechos: presente, `Up/Disconnected` **e `DriverProvider =
Microsoft`** → deu certo (sem o fornecedor não se distingue "o básico entrou" de "outro OEM venceu");
`Problem -ne CM_PROB_NONE` → **restaurar imediatamente, sem perguntar**; sumiu da lista → idem. O usuário não tem como
julgar `CM_PROB_FAILED_INSTALL`. O botão 4 tem a mesma restauração automática do 5: em notebook sem Ethernet, mandar
clicar num botão para voltar é mandar clicar sem rede.

### 5.1 Bloqueios

Todos de leitura, na ordem de custo. Disparou: parar, explicar em pt-BR, **não oferecer "continuar mesmo assim"**.

| Bloqueio | Detecção | Aplica-se a |
|---|---|---|
| Sessão remota | `GetSystemMetrics(0x1000)` | 3, 4, 5 |
| Build < 18362 | `[Environment]::OSVersion.Version.Build` | 4 e 5 não aparecem |
| Nenhuma outra via de rede | `Get-NetAdapter -Physical`, `Status -eq 'Up'`, `-not Virtual`, `ifIndex` diferente | absoluto em 5; aviso em 4 |
| Sem driver inbox | análise da saída do `pnputil` | 5 (o botão não aparece) |
| Falha ao exportar | `$LASTEXITCODE -ne 0` **mais** conferência dos arquivos | 4 e 5 |
| Notebook na bateria | `Win32_Battery.BatteryStatus -eq 1` | 4 e 5 |
| Máquina virtual / Windows Server | `Machine.IsVirtual`, `OS.IsServer` | 4, 5 e 6 |
| `CM_PROB_NEED_RESTART` (14) | `Get-PnpDevice` | reiniciar antes |
| Espaço em disco | livre < pacote + margem | 4 e 5, com o número na tela |

O gate de build é obrigatório: `/remove-device` e `/scan-devices` só existem a partir do Windows 10 1903, e o README
declara suporte a Windows 10, o que inclui 1809/LTSC 2019 — barrar só por `IsServer` deixaria dois botões que falham
sem explicação.

**`$env:SESSIONNAME` veio vazia numa sessão de console legítima** (Win11 26200): o teste `-ne 'Console'`, o conselho
mais repetido na internet, **bloquearia o botão para toda gente**. Usar `GetSystemMetrics(SM_REMOTESESSION = 0x1000)`.
Ressalva na confirmação de 4 e 5: **ele não detecta AnyDesk, TeamViewer e afins**, que rodam na sessão de console — se
você está acessando este computador de longe por um programa desses, pare aqui.

### 5.2 Backup do driver e armadilhas do `pnputil`

O export do WiFi Intel desta máquina deu **10 arquivos, 120 MB** (inclui `WiFi.msi` e um `Setup.exe` de 17 MB). Logo:
medir espaço livre antes, mostrar o tamanho, guardar sob `[Environment]::GetFolderPath('CommonApplicationData')`, em
`%ProgramData%\WinForge\driver-backup\<oem##>-<carimbo>`, **nunca `$env:TEMP`**.

**As quatro verificações depois do comando são obrigatórias**: `$LASTEXITCODE -eq 0`; `.inf` no destino; `.cat` no
destino; total em bytes coerente. Qualquer uma falhar → **abortar sem tocar em nada**. Três armadilhas medidas: **(a)**
`pnputil` falhando devolve `$LASTEXITCODE = -536870340`, então a verificação **tem de ser `-ne 0`** — com `-gt 0` a
falha viraria sucesso e o código seguiria para o `delete-driver`; **(b)** `pnputil` escreve ANSI/CP1252 quando
redirecionado, então todo passo leva `Encoding = 'ansi'`, **não `oem`**; **(c)** `/enum-devices /class Net /problem`
achou dispositivo em falha e **saiu com código 0**, então é obrigatório interpretar a saída. **Nunca `/force`**, que
apaga o pacote em uso e é a diferença entre "não deu, nada mudou" e "não deu, e agora não há driver". **Nunca
`/reboot`**.

Detecção de inbox independente de idioma (a saída é localizada; os rótulos não servem de âncora, os valores sim):
dentro de cada bloco, o primeiro valor terminado em `.inf` é o nome publicado; casa `^oem\d+\.inf$` → terceiro, não
casa → **inbox**. Medido: o bloco do inbox tem **uma só** linha `.inf`, os OEM têm duas. `Get-WindowsDriver -Online
-All` tem `.Inbox` mas **exige elevação** e por isso não serve ao SelfTest.

### 5.3 Exceção de interface (D3, registrada)

A regra do projeto é "botão desabilitado, não removido". **Aqui se abre exceção: o botão 5 NÃO APARECE quando a análise
do `pnputil` não achou alternativa não-`oem##.inf`.** Motivo: para MediaTek, Realtek recentes, Intel AX/BE novos e
Qualcomm frequentemente **não há inbox nenhum**, e apagar o pacote deixa a máquina sem rádio. Botão desabilitado
convida a procurar como habilitá-lo, e o que se acha na internet é "use `/force`" — precisamente o caminho para ficar
sem rádio. **A exceção vale só para este botão**, e é esta linha que a registra.

---

## 6. Entradas novas de config

Seis entradas sobem a trava **Config 57 → 63** (`build.ps1:1157`); Tweaks 83, Jogos 84, Servidor 22 e Instalar 137 não
mudam. Cada descrição tem ≥ 40 caracteres, difere do título, nenhuma sentença se repete entre elas, nenhuma traz
"Origem:".

| Id | Título | Descrição |
|---|---|---|
| `AclCleanup` | Permissões do disco C: — Limpar backups antigos | Lista os arquivos de backup de permissões guardados pelo WinForge com tamanho e data, marca os que nenhum índice usa e apaga só os marcados, sob confirmação. |
| `NetDiagFull` | Rede — Diagnóstico completo | Levanta adaptador sem fio, endereço, rota, servidor de nomes, proxy, filtros de antivírus e catálogo Winsock, e termina com uma frase dizendo onde está a falha. |
| `NetDnsRenew` | Rede — Limpar cache de DNS e pegar endereço novo | Esvazia o cache de nomes, devolve o endereço atual ao roteador e pede outro no lugar. Serve para endereço 169.254 preso e site que abre errado. |
| `WifiDriverReinstall` | Rede sem fio — Reinstalar o driver que já está instalado | Guarda uma cópia do pacote atual, remove o dispositivo e manda o Windows procurá-lo de novo, o que traz de volta exatamente o mesmo pacote. |
| `WifiDriverGeneric` | Rede sem fio — Trocar pelo driver básico do Windows (pode ficar sem Wi-Fi) | Apaga os pacotes do fabricante para o Windows passar a usar o driver simples que vem com ele. Exige digitar uma confirmação e ter cabo de rede à mão. |
| `WifiDriverRestore` | Rede sem fio — Voltar para o driver que estava antes | Reaplica o pacote guardado pelas duas ações acima e confere no adaptador o que de fato entrou em uso. Aparece só quando existe cópia conferida em disco. |

Os dois estados novos de cabeçalho (âmbar a 1,5× e 3×) e a pintura da linha de grupo passam pela conferência de
**≥ 4,5:1 em tema claro e escuro**.

---

## 7. Testes

`dist\engine\WinForge.ps1 -SelfTest` roda **sem admin**, `$sync.SelfTest = $true` fazendo todo helper de escrita e toda
linha `Kind -ne 'read'` lançarem. **Toda função nova declara `param()`.** Meta: **0 erros em dois modos**.

- **Permissões.** Ida e volta do arquivo em `%TEMP%` (gravar → `/restore` → reler → comparar), **o único ponto do
  desenho ainda sem prova**. Os quatro tetos devolvem `Ok=$false` com `Entries` vazio e o texto de §1.6. A caminhada
  não desce numa junção auto-referente plantada em `%TEMP%`, visita cada item uma vez e **não inclui o reparse point
  como entrada** — teria pegado o defeito de hoje. Formato UTF-16LE sem BOM, pares de linhas, nomes relativos. As sete
  recusas de `Test-WinForgeAclContentRoot`. SHA-256 muda com um byte e a recusa acontece.
  `Test-WinForgeAclIndexOrigin` recusa `MachineGuid` e SID trocados. Índice `Consumed = $false` plantado → restauração
  recusada e Desfazer no **mais antigo** não consumido. `Denied > 0` sintético → `Concluído com ressalvas` e a lista.
  `Measure-WinForgeAclSaveEntry` conta arquivo grande sem materializar array. Caminho de 294 caracteres com `\\?\` é
  lido; sem o prefixo, cai em `Denied`.
- **Memória e cancelamento.** O anel corta e o resultado começa numa quebra de linha, com a marca. Crescimento de 20 MB
  devolve no máximo ~1 MB. Teto de 256 MB e retenção 30/20. `ExpectMinutes` existe em cada comando `repair` e o
  cabeçalho muda a 1,5× e 3×. A flag é checada entre passos e **ignorada dentro de
  `Invoke-WinForgeAclOwnerFallback`**; os processos da Fase 4 **não** aparecem na atribuição ao job. `Add-Type`
  guardado por `'WfJob' -as [type]` roda **duas vezes seguidas** num scriptblock de pool. Marcador
  `acl-posse-pendente.json` plantado produz o relato na abertura e **nenhuma escrita**. `KILL_ON_JOB_CLOSE` é teste
  manual.
- **Drivers.** `Group-WinForgeWindowsUpdateNullDrivers` é pura e roda sem COM (molde de `build.ps1:4169-4221`): 47
  agrupa; 4 não; título com versão nunca; `Display`, `Firmware`, `Extension`, `SoftwareComponent` nunca;
  `SizeBytes = 0` nunca; acima do corte nunca; datas e fornecedores diferentes dão dois grupos. **Os casos leem as três
  constantes; nenhum literal de tamanho, contagem ou classe no teste.** Os cinco estados de §3.2. **O rótulo nunca
  contém "chipset"**, nem para Intel. Data anterior a 1990 vira `sem data confiável`. O filtro de §4 aceita `INTEL` e
  `Intel`, recusa classe vazia e `Provider` não-Intel. `New-WinForgeChipsetRestorePoint` sem sequência nova **recusa o
  lote** e não chama membro nenhum.
- **Rede.** As cinco linhas novas compilam em `Get-WinForgeRepairCommand` com `Title`, `Kind`, `Confirm`, `Steps`.
  `Get-WinForgeSystemExe -Name 'pnputil.exe'` devolve caminho sob `[Environment]::SystemDirectory`. Teste estático de
  que nenhum argumento é montado por concatenação. A trava de SelfTest dispara nas linhas novas. Contra as amostras
  reais em pt-BR de `tests/`: acha `oem22.inf` instalado, acha **exatamente um** inbox, **não** confunde a linha "Nome
  Original:" do bloco OEM com um inbox, e sem inbox o botão 5 some. `$LASTEXITCODE` com `0`, `1`, **`-536870340`**,
  `3010`, só `0` sucesso — impede o bug `-gt 0`. Decodificação `ansi` × `oem`. Teste negativo: o código **não** usa
  `$env:SESSIONNAME -ne 'Console'`. Build 17763 simulado → botões 4 e 5 somem. Sem `driver-backup`, botão 6 `$false`. A
  verificação de sucesso exige `DriverProvider = Microsoft`. O botão 1 roda inteiro e devolve uma das cinco frases.

---

## 8. Limites conhecidos

**Nada desta versão foi visto rodando numa máquina quebrada de verdade.** O SelfTest roda sem admin e em perfil
íntegro; as condições que disparam o laço original (elevação com `SeBackupPrivilege`, ou perfil com as ACEs de negação
das junções já quebradas) estão fora do alcance dele. Precisa de roteiro manual escrito **antes** do PR, porque nada
disso foi medido: que `remove-device` + `scan-devices` traz o adaptador de volta; que `add-driver /install` reamarra o
driver ao dispositivo; que o driver inbox **funciona** com aquele rádio (o `Setup.exe` de 17 MB dentro do pacote Intel
sugere que o fabricante espera um instalador, não só um INF); que a restauração de ACL termina em tempo aceitável num
perfil grande, elevado; e que `KILL_ON_JOB_CLOSE` mata a árvore quando o WinForge é encerrado pelo Gerenciador de
Tarefas. Também não foi medido, e por isso fica parametrizado (§3.1): `DriverClass`, `MaxDownloadSize` e `Categories`
de uma oferta real de INF sem versão.

Três limites de comportamento aparecem no texto que o usuário lê: o Chipset INF pelo WU **não tem Desfazer**; ele não
instala SMBus funcional, Intel ME/HECI, Serial IO, DPTF nem Rapid Storage, de modo que depois do lote um "Dispositivo
PCI" que precisava de driver de verdade continua sem ele e muda só o nome; e a recuperação do §5 depende de o backup de
120 MB caber no disco, conferido antes mas nunca exercitado num disco quase cheio.

---

## Julgamento das críticas

**Cobertura do pedido**

1. "(chipset)" no rótulo contradiz o filtro de §4 — **acatado**: a palavra sai do rótulo, e "AMD" cai junto, sem
   respaldo em relatório nenhum.
2. §4 não tem onde morar — **acatado**: passa a ser explicitamente o botão `Instalar todos (N)`, com
   `New-WinForgeChipsetRestorePoint` uma vez antes do primeiro membro e recusa do lote se a sequência não subir.
3. `DeviceProblemNumber` descartado mas necessário ao texto — **acatado**: lido como `ProblemCode`, com "não participa
   do critério" escrito em §3.1.
4. Escapatória do teto com frase literal e padrão cancelar — **recusado**: D1 é posterior ao relatório e tornou o
   backup obrigatório; um escape devolve o Desfazer que não desfaz. A contradição da spec antiga morre pelo outro lado
   — uma caixa, um botão, nada é alterado.
5. Faltavam os textos de cancelamento de `memoria-ui.md` — **acatado**: as seis frases entram literais em §2.
6. Botão 6 sem desfecho ruim e sem `DriverProvider = Microsoft` — **acatado**: os dois entram em §5.
7. `Protect-WinForgeSnapshotFile` ignorado — **acatado em outra forma**: ele grava dono e DACL, não materializa
   conteúdo, então não é caminho de `OutOfMemoryException`; o buraco real é o arquivo de conteúdo externo nunca ter
   proteção escrita, e é isso que §1.4 passa a exigir.

**Segurança**

1. Segunda execução destrói o backup bom — **acatado**, confirmado no código (`:3044`, `:2760-2769`): `Consumed`,
   Desfazer no mais antigo não consumido, restauração recusada enquanto houver pendente.
2. Job Object anula a proibição de cancelar na Fase 4 — **acatado**: Fase 4 fora do job, marcador de posse pendente,
   relatado na abertura seguinte e nunca consertado sozinho.
3. `Denied` sem política — **acatado no veredito, recusado no mecanismo**: `Denied > 0` vira "Concluído com ressalvas"
   com a lista; posse / `SeBackupPrivilege` fica fora, é operação de outro tamanho e não foi pedida.
4. Assimetria de `/L` com reparse point — **acatado**: reparse point nunca é entrada, não só nunca empilhado.
5. Ponto de restauração pode não existir — **acatado**: conferência da sequência e recusa do lote.
6. Índice de outra máquina — **acatado reduzido**: `MachineGuid` + SID do perfil; serial de volume dispensado por não
   pegar nada que esses dois já não peguem.
7. OneDrive Sob Demanda, botão 4 sem auto-restauração, `SM_REMOTESESSION` cego para AnyDesk — **acatados os três**, os
   dois de texto por texto e o do botão 4 também por código.

**Viabilidade no PowerShell 5.1** (comando rodado vence texto de spec)

1. `Add-Type` do job invisível no pool — **acatado**: guarda `'WfJob' -as [type]` dentro do scriptblock do pool.
2. Assign falha de pai não elevado — **acatado**: ressalva escrita para `-NoElevate`.
3. `AccessControlSections::All` lança sem `SeSecurityPrivilege` — **acatado**: `GetAccessControl($p)` +
   `GetSecurityDescriptorSddlForm('Access')`.
4. `LongPathsEnabled` não é padrão, e `Denied` contava a chamada errada — **acatado**: prefixo `\\?\`, e `Denied`
   envolvendo `GetAccessControl` e `EnumerateFileSystemEntries`. Corrigido na execucao (12/09): o `GetAttributes` que
   lanca tambem entra, porque trata-lo como "nao e ponto de reanalise" fazia a caminhada descer na juncao.
5. Falta gate de build para 1903 — **acatado**: linha nova na tabela de bloqueios.

**Clareza do texto**

1. Seis descrições de Config e veredito de uma frase inexistentes — **acatado**: §6 e §5, escritos.
2. Jargão (`n/d`, "identificações de dispositivo", "INF de nomeação", "driver genérico", "teto de 90 s", "no passo N")
   — **acatado**, substituído em todos os pontos.
3. Nomes de botão que não dizem o efeito — **acatado**: "Devolver ao padrão do Windows" e "Trocar pelo driver básico do
   Windows (pode ficar sem Wi-Fi)".
4. Confirmação sem o custo real — **acatado**: §1.7 traz o tempo, §4 traz "não há como desfazer" em destaque.
5. Reescritas propostas (teto, outro disco, recusa do Desfazer, cabeçalho âmbar, botão travado, rótulo do grupo, botão
   5) — **acatadas literalmente**, menos a do teto, que entra sem a segunda via por causa de D1.
