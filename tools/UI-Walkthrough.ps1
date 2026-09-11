<#
.SYNOPSIS
    Passeia pela interface do WinForge e salva um PNG de cada aba.

.DESCRIPTION
    Ferramenta de QA visual: abre (ou encontra) a janela do WinForge, clica nos botões da barra de
    navegação com o mouse de verdade e fotografa a janela em cada aba, na ordem em que elas
    aparecem na tela. No Diagnóstico tira também as fotos rolando a página e uma com o cursor
    parado sobre a tabela de drivers - é ali que a rolagem costuma travar.

    Os cliques são eventos reais de mouse (mouse_event) em cima do ponto que a árvore de
    acessibilidade (UI Automation) informa para cada AutomationId. Nada de Invoke() nem de mandar
    o WPF trocar de aba por dentro: o objetivo é fotografar o que o usuário veria.

.PARAMETER Launch
    Abre o WinForge, espera a janela aparecer e fecha o programa no fim. Sem isto, a ferramenta usa
    a janela do WinForge que já estiver aberta. Em qualquer caso o programa sobe com
    -NoRestorePoint: a caixa "criar ponto de restauração?" é modal e o passeio pararia nela.

.PARAMETER NoElevation
    Não pede elevação e abre o MOTOR direto (dist\engine\WinForge.ps1 -NoElevation -NoRestorePoint)
    em vez de dist\WinForge.exe. É o modo da QA visual: o passeio inteiro roda como usuário comum,
    sem UAC e sem tocar no sistema.

.PARAMETER Theme
    'Escuro' ou 'Claro' trocam o tema pelo menu da barra (botão da paleta) antes das fotos.
    'Manter' (padrão) fotografa o tema que estiver valendo.

.PARAMETER OutDir
    Pasta das imagens e do log. Padrão: dist\screenshots (dentro do repositório, fora do git), ou
    dist\screenshots\dark|light quando -Theme é informado.

.PARAMETER SettleSeconds
    Segundos de espera depois de cada clique, antes da foto. Padrão: 2.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\UI-Walkthrough.ps1 -Launch -NoElevation -Theme Escuro

.NOTES
    Sem -NoElevation precisa de administrador (o WinForge se eleva sozinho e a janela elevada não
    aceita cliques de um processo comum); nesse caso o script se reabre elevado - uma janela do UAC.
    Recusa rodar com CS2/CS:GO aberto: o jogo captura o mouse e os cliques iriam para ele.
#>
[CmdletBinding()]
param(
    [switch]$Launch,
    [switch]$NoElevation,
    [ValidateSet('Manter', 'Escuro', 'Claro')]
    [string]$Theme = 'Manter',
    [string]$OutDir,
    [int]$SettleSeconds = 2
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot 'dist\screenshots'
    if ($Theme -eq 'Escuro') { $OutDir = Join-Path $OutDir 'dark' }
    elseif ($Theme -eq 'Claro') { $OutDir = Join-Path $OutDir 'light' }
}

# ---------------------------------------------------------------- administrador
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $NoElevation -and -not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Sem privilégio de administrador: reabrindo elevado..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-OutDir', "`"$OutDir`"", '-SettleSeconds', $SettleSeconds, '-Theme', $Theme)
    if ($Launch) { $argList += '-Launch' }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    return
}

# ---------------------------------------------------------------- jogo aberto
# CS2/CS:GO prendem o cursor: cada clique deste script iria para o jogo, não para a janela.
$game = @(Get-Process -Name 'cs2', 'csgo' -ErrorAction SilentlyContinue)
if ($game.Count) {
    throw "Feche $(@($game | ForEach-Object { $_.ProcessName }) -join ', ') antes de rodar: o jogo captura o mouse e os cliques não chegariam ao WinForge."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$logPath = Join-Path $OutDir 'UI-Walkthrough.log'
function Write-Log([string]$msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    $line | Add-Content -Path $logPath -Encoding UTF8
    Write-Host $line
}
"" | Set-Content -Path $logPath -Encoding UTF8
Write-Log "Início | saída: $OutDir"

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WfWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, int extra);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@

$MOUSE_LEFTDOWN = 0x0002
$MOUSE_LEFTUP   = 0x0004
$MOUSE_WHEEL    = 0x0800

function Get-WinForgeTopWindows {
    # Janelas de topo do desktop. Serve tanto para achar a janela principal quanto para achar o
    # POPUP do menu de tema, que no WPF é outra janela do processo e não está dentro da principal.
    return @([System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition))
}

function Get-WinForgeWindow {
    # A busca é na árvore de janelas do desktop, e não pelo MainWindowHandle do processo: com o
    # motor aberto direto (powershell.exe dist\engine\WinForge.ps1) o MainWindowHandle do processo
    # é o CONSOLE, não a janela WPF, e o passeio fotografaria o console.
    # O título também não basta - o console se chama "WinForge" igual. A janela certa é a que tem
    # o botão do Diagnóstico dentro. O botão, e não o NavDockPanel: painel não é controle e não
    # entra na árvore que FindFirst percorre.
    $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty), 'WPFTab8BT'
    foreach ($w in (Get-WinForgeTopWindows)) {
        try {
            if ($w.Current.Name -notlike 'WinForge*') { continue }
            if ($w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)) { return $w }
        } catch { continue }
    }
    return $null
}

# ---------------------------------------------------------------- janela
# -NoRestorePoint sempre: a caixa "criar um ponto de restauração?" é modal e o passeio pararia nela
# esperando um clique que ninguém dá.
$launched = $null
if ($Launch) {
    if ($NoElevation) {
        $engine = Join-Path $RepoRoot 'dist\engine\WinForge.ps1'
        if (-not (Test-Path $engine)) { throw "Não encontrei $engine - rode build.cmd primeiro." }
        Write-Log "Abrindo $engine (sem elevação, sem ponto de restauração)"
        $launched = Start-Process -FilePath 'powershell.exe' -PassThru -ArgumentList @(
            '-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$engine`"", '-NoElevation', '-NoRestorePoint')
    } else {
        $exe = Join-Path $RepoRoot 'dist\WinForge.exe'
        if (-not (Test-Path $exe)) { throw "Não encontrei $exe - rode build.cmd primeiro." }
        Write-Log "Abrindo $exe"
        $launched = Start-Process -FilePath $exe -PassThru -ArgumentList '-NoRestorePoint'
    }
    $deadline = (Get-Date).AddSeconds(120)
    do {
        Start-Sleep -Seconds 2
        $root = Get-WinForgeWindow
    } while (-not $root -and (Get-Date) -lt $deadline)
    if (-not $root) { throw "A janela do WinForge não apareceu em 120 s." }
} else {
    $root = Get-WinForgeWindow
    if (-not $root) { throw "Nenhuma janela do WinForge aberta. Use -Launch." }
}
$pidJanela = $root.Current.ProcessId
Write-Log "Janela: pid $pidJanela '$($root.Current.Name)'"

$hwnd = [IntPtr]$root.Current.NativeWindowHandle
[WfWin]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
[WfWin]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Seconds 2

function Save-Shot([string]$name) {
    $r = New-Object WfWin+RECT
    [WfWin]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { Write-Log "  foto $name ignorada: janela sem tamanho"; return }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $g.Dispose()
    $file = Join-Path $OutDir "$name.png"
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Log "  foto $name (${w}x$h) -> $file"
}

function Find-ById([string]$id) {
    $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty), $id
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Invoke-Click([string]$id) {
    $el = Find-ById $id
    if (-not $el) { Write-Log "  '$id' não existe na janela"; return $false }
    if ($el.Current.IsOffscreen) { Write-Log "  '$id' está escondido nesta máquina"; return $false }
    try { $pt = $el.GetClickablePoint() } catch { Write-Log "  '$id' sem ponto clicável: $($_.Exception.Message)"; return $false }
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int]$pt.X), ([int]$pt.Y)
    Start-Sleep -Milliseconds 150
    [WfWin]::mouse_event($MOUSE_LEFTDOWN, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [WfWin]::mouse_event($MOUSE_LEFTUP, 0, 0, 0, 0)
    Write-Log "  clique em '$id'"
    return $true
}

function Invoke-Scroll([int]$ticks, [int]$delta = -120) {
    1..$ticks | ForEach-Object {
        [WfWin]::mouse_event($MOUSE_WHEEL, 0, 0, $delta, 0)
        Start-Sleep -Milliseconds 80
    }
}

function Set-WinForgeTheme([string]$Nome) {
    if ($Nome -eq 'Manter') { return }
    $item = if ($Nome -eq 'Escuro') { 'DarkThemeMenuItem' } else { 'LightThemeMenuItem' }
    Write-Log "Tema: $Nome"
    if (-not (Invoke-Click 'ThemeButton')) { Write-Log "  botão de tema não encontrado"; return }
    Start-Sleep -Milliseconds 700
    # O popup do menu é OUTRA janela do processo: procurar dentro da janela principal não acha.
    $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty), $item
    $alvo = $null
    foreach ($w in (Get-WinForgeTopWindows)) {
        try {
            if ($w.Current.ProcessId -ne $pidJanela) { continue }
            $achado = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($achado) { $alvo = $achado; break }
        } catch { continue }
    }
    if (-not $alvo) { Write-Log "  '$item' não apareceu no menu"; [System.Windows.Forms.SendKeys]::SendWait('{ESC}'); return }
    try { $pt = $alvo.GetClickablePoint() } catch { Write-Log "  '$item' sem ponto clicável"; [System.Windows.Forms.SendKeys]::SendWait('{ESC}'); return }
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int]$pt.X), ([int]$pt.Y)
    Start-Sleep -Milliseconds 150
    [WfWin]::mouse_event($MOUSE_LEFTDOWN, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [WfWin]::mouse_event($MOUSE_LEFTUP, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 600
    # ESC fecha o que tiver sobrado do menu: sem isto ele fica aberto por cima da barra e aparece
    # em TODAS as fotos seguintes (aconteceu na primeira leva da Tarefa 6).
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
    Start-Sleep -Milliseconds 400
    [WfWin]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
}

Set-WinForgeTheme $Theme

# ---------------------------------------------------------------- passeio
# Mesma ordem da barra de navegação (wf-xaml-nav.xml).
$tabs = @(
    @{ Id = 'WPFTab8BT'; Shot = '01-diagnostico' }
    @{ Id = 'WPFTab2BT'; Shot = '02-ajustes' }
    @{ Id = 'WPFTab7BT'; Shot = '03-jogos' }
    @{ Id = 'WPFTab3BT'; Shot = '04-configuracoes' }
    @{ Id = 'WPFTab9BT'; Shot = '05-servidor' }
    @{ Id = 'WPFTab4BT'; Shot = '06-atualizacoes' }
    @{ Id = 'WPFTab1BT'; Shot = '07-instalar' }
    @{ Id = 'WPFTab5BT'; Shot = '08-iso-win11' }
)

# O diagnóstico de abertura roda em segundo plano e leva alguns segundos; sem esta espera a foto
# de abertura sai com "Coletando informações do sistema..." e nenhum cartão.
Start-Sleep -Seconds ($SettleSeconds * 2)
Save-Shot '00-abertura'
foreach ($tab in $tabs) {
    Write-Log "Aba $($tab.Shot)"
    if (Invoke-Click $tab.Id) {
        Start-Sleep -Seconds $SettleSeconds
        Save-Shot $tab.Shot
    }
}

# Diagnóstico rolado: a tabela de drivers fica bem abaixo dos cartões.
Write-Log "Diagnóstico rolado"
if (Invoke-Click 'WPFTab8BT') {
    Start-Sleep -Seconds $SettleSeconds
    $r = New-Object WfWin+RECT
    [WfWin]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int](($r.L + $r.R) / 2)), ([int](($r.T + $r.B) / 2))
    Invoke-Scroll 12
    Start-Sleep -Seconds 1
    Save-Shot '09-diagnostico-rolado'
    Invoke-Scroll 12
    Start-Sleep -Seconds 1
    Save-Shot '10-diagnostico-rolado-2'

    # Com o cursor parado sobre a tabela de drivers. O DataGrid tem rolagem própria e engolia a roda,
    # deixando a página inteira parada; hoje o evento é repassado ao ScrollViewer da aba. A foto rola
    # PARA CIMA de propósito: na foto anterior a página já está no fim, e mais rolagem para baixo não
    # mudaria nada nem com o repasse funcionando. Subindo, a diferença entre a foto 10 e a 11 é a
    # prova de que a roda sobre a tabela move a página.
    $grid = Find-ById 'WPFDiagDrivers'
    if ($grid) {
        $b = $grid.Current.BoundingRectangle
        Write-Log "  tabela de drivers em $b"
        if ($b.Height -gt 0) {
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int]($b.X + $b.Width / 2)), ([int]($b.Y + [Math]::Min(80, $b.Height / 2)))
            Invoke-Scroll 8 120
            Start-Sleep -Seconds 1
            Save-Shot '11-diagnostico-roda-sobre-a-tabela'
        }
    } else {
        Write-Log "  tabela de drivers não encontrada"
    }
}

# ---------------------------------------------------------------- fim
if ($launched) {
    Write-Log "Fechando o WinForge"
    $alvo = Get-Process -Id $pidJanela -ErrorAction SilentlyContinue
    if ($alvo) { $alvo.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 3 }
    foreach ($p in @($launched, $alvo)) {
        if ($p -and -not $p.HasExited) { $p | Stop-Process -Force -ErrorAction SilentlyContinue }
    }
}
Write-Log "Fim: $(@(Get-ChildItem -Path $OutDir -Filter '*.png').Count) imagem(ns) em $OutDir"
