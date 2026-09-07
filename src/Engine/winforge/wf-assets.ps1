#region ===== WinForge - logo =====
function Get-WinForgeLogoPaths {
    <#
    .SYNOPSIS
        Logo do WinForge em um canvas 100x100: bigorna (aço) com um "W" de faíscas (laranja forja).
        Arte original do projeto WinForge.
    #>
    # Traços grossos de propósito: o logo precisa continuar legível em 16 px (ícone da barra de tarefas).
    $anvil = New-Object Windows.Shapes.Path
    $anvil.Data = [Windows.Media.Geometry]::Parse("M 6,56 L 94,56 L 94,70 L 62,70 L 62,80 L 78,92 L 22,92 L 38,80 L 38,70 L 18,70 L 6,61 Z")
    $anvil.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5B6470")

    $horn = New-Object Windows.Shapes.Path
    $horn.Data = [Windows.Media.Geometry]::Parse("M 6,56 L 18,70 L 6,61 Z M 88,56 C 96,53 98,63 94,70 Z")
    $horn.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F4650")

    $w = New-Object Windows.Shapes.Path
    $w.Data = [Windows.Media.Geometry]::Parse("M 14,8 L 28,8 L 35,30 L 41,15 L 51,15 L 57,30 L 64,8 L 78,8 L 62,50 L 51,50 L 46,33 L 41,50 L 30,50 Z")
    $w.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF7A1A")

    $spark = New-Object Windows.Shapes.Path
    $spark.Data = [Windows.Media.Geometry]::Parse("M 88,8 L 91,13 L 96,16 L 91,19 L 88,24 L 85,19 L 80,16 L 85,13 Z")
    $spark.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFB347")

    return @($anvil, $horn, $w, $spark)
}
#endregion
