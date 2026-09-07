# Renderiza o logo WinForge (mesmo path do engine) em PNGs e empacota assets\winforge.ico
# Precisa rodar em STA: powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\Make-Icon.ps1
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
. (Join-Path $RepoRoot "src\Engine\winforge\wf-assets.ps1")

function Render-Png([int]$size) {
    $canvas = New-Object Windows.Controls.Canvas
    $canvas.Width = 100
    $canvas.Height = 100
    $canvas.Background = $null
    foreach ($p in (Get-WinForgeLogoPaths)) { $canvas.Children.Add($p) | Out-Null }
    $canvas.LayoutTransform = New-Object Windows.Media.ScaleTransform(($size / 100), ($size / 100))
    $canvas.Measure([Windows.Size]::new($size, $size))
    $canvas.Arrange([Windows.Rect]::new(0, 0, $size, $size))
    $canvas.UpdateLayout()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($size, $size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($canvas)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $ms = New-Object System.IO.MemoryStream
    $enc.Save($ms)
    return $ms.ToArray()
}

$sizes = 16, 32, 48, 256
$pngs = @{}
foreach ($s in $sizes) { $pngs[$s] = Render-Png $s }
New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot "assets") | Out-Null
[IO.File]::WriteAllBytes((Join-Path $RepoRoot "assets\logo-256.png"), $pngs[256])

# ICO: header(6) + entradas do diretório(16 cada) + payloads PNG
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
foreach ($s in $sizes) {
    $b = $pngs[$s]
    $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s }))); $bw.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$b.Length); $bw.Write([uint32]$offset)
    $offset += $b.Length
}
# NOTA: $bw.Write($bytes) resolve para a sobrecarga errada no PowerShell (grava 1 byte).
# Usar a sobrecarga de 3 argumentos, que aceita byte[] sem ambiguidade.
foreach ($s in $sizes) { $b = [byte[]]$pngs[$s]; $bw.Write($b, 0, $b.Length) }
$bw.Flush()
[IO.File]::WriteAllBytes((Join-Path $RepoRoot "assets\winforge.ico"), $ms.ToArray())
Write-Host "assets\winforge.ico gerado ($($ms.Length) bytes) + assets\logo-256.png"
