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
    Abre dist\WinForge.exe, espera a janela aparecer e fecha o programa no fim. Sem isto, a
    ferramenta usa a janela do WinForge que já estiver aberta.

.PARAMETER OutDir
    Pasta das imagens e do log. Padrão: dist\screenshots (dentro do repositório, fora do git).

.PARAMETER SettleSeconds
    Segundos de espera depois de cada clique, antes da foto. Padrão: 2.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\UI-Walkthrough.ps1 -Launch

.NOTES
    Precisa de administrador (o WinForge se eleva sozinho e a janela elevada não aceita cliques de
    um processo comum). Se não estiver elevado, o script se reabre elevado - uma janela do UAC.
    Recusa rodar com CS2/CS:GO aberto: o jogo captura o mouse e os cliques iriam para ele.
#>
[CmdletBinding()]
param(
    [switch]$Launch,
    [string]$OutDir,
    [int]$SettleSeconds = 2
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'dist\screenshots' }

# ---------------------------------------------------------------- administrador
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Sem privilégio de administrador: reabrindo elevado..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-OutDir', "`"$OutDir`"", '-SettleSeconds', $SettleSeconds)
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

function Get-WinForgeWindow {
    # O título não basta: o console que hospeda o motor também se chama "WinForge", e num terminal
    # com abas é ele que aparece primeiro. A janela certa é a que tem o botão do Diagnóstico
    # dentro. O botão, e não o NavDockPanel: painel não é controle e não entra na árvore que
    # FindFirst percorre.
    $cond = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty), 'WPFTab8BT'
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'WinForge*' } |
            Sort-Object StartTime -Descending)) {
        try {
            $el = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
            if ($el -and $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)) { return $p }
        } catch { continue }
    }
    return $null
}

# ---------------------------------------------------------------- janela
$launched = $null
if ($Launch) {
    $exe = Join-Path $RepoRoot 'dist\WinForge.exe'
    if (-not (Test-Path $exe)) { throw "Não encontrei $exe - rode build.cmd primeiro." }
    Write-Log "Abrindo $exe"
    $launched = Start-Process -FilePath $exe -PassThru
    $deadline = (Get-Date).AddSeconds(120)
    do {
        Start-Sleep -Seconds 2
        $proc = Get-WinForgeWindow
    } while (-not $proc -and (Get-Date) -lt $deadline)
    if (-not $proc) { throw "A janela do WinForge não apareceu em 120 s." }
} else {
    $proc = Get-WinForgeWindow
    if (-not $proc) { throw "Nenhuma janela do WinForge aberta. Use -Launch." }
}
Write-Log "Janela: pid $($proc.Id) '$($proc.MainWindowTitle)'"

$hwnd = $proc.MainWindowHandle
[WfWin]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
[WfWin]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Seconds 2
$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)

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

function Invoke-Scroll([int]$ticks) {
    1..$ticks | ForEach-Object {
        [WfWin]::mouse_event($MOUSE_WHEEL, 0, 0, -120, 0)
        Start-Sleep -Milliseconds 80
    }
}

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

    # Com o cursor parado sobre a tabela de drivers: o DataGrid tem rolagem própria e engole a roda,
    # então a página inteira para de rolar. É o caso que a foto tem de registrar.
    $grid = Find-ById 'WPFDiagDrivers'
    if ($grid) {
        $b = $grid.Current.BoundingRectangle
        Write-Log "  tabela de drivers em $b"
        if ($b.Height -gt 0) {
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int]($b.X + $b.Width / 2)), ([int]($b.Y + [Math]::Min(80, $b.Height / 2)))
            Invoke-Scroll 8
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
    $alvo = Get-WinForgeWindow
    if ($alvo) { $alvo.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 3 }
    foreach ($p in @($launched, $alvo)) {
        if ($p -and -not $p.HasExited) { $p | Stop-Process -Force -ErrorAction SilentlyContinue }
    }
}
Write-Log "Fim: $(@(Get-ChildItem -Path $OutDir -Filter '*.png').Count) imagem(ns) em $OutDir"
