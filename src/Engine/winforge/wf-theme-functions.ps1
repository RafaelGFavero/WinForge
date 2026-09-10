#region ===== WinForge - sistema visual (contraste) =====
# Contas de contraste do WCAG 2.1 sobre os tokens de tema. Só matemática: nada aqui toca na janela.
# Existe para o -SelfTest poder reprovar um par texto/fundo ilegível ANTES de alguém abrir o
# programa - trocar um hexadecimal do tema é a mudança mais fácil de fazer e a mais difícil de ver.

function Get-WinForgeRelativeLuminance {
    <#
    .SYNOPSIS
        Luminância relativa (0..1) de uma cor #RRGGBB, pela fórmula do WCAG 2.1.
    .DESCRIPTION
        Cada canal vai de 0..255 para 0..1, sai do gama do sRGB e entra na soma ponderada
        0,2126 R + 0,7152 G + 0,0722 B. Aceita #RGB, #RRGGBB e o mesmo sem o '#'.
        Cor inválida ESTOURA em vez de devolver 0: um token com erro de digitação passaria pela
        trava de contraste com nota máxima se a conta devolvesse preto silenciosamente.
    #>
    param([Parameter(Mandatory)][string]$Hex)

    $h = ([string]$Hex).Trim().TrimStart('#')
    if ($h.Length -eq 3) { $h = "$($h[0])$($h[0])$($h[1])$($h[1])$($h[2])$($h[2])" }
    if ($h -notmatch '^[0-9A-Fa-f]{6}$') { throw "cor inválida para contraste: '$Hex'" }

    $canais = @(0, 2, 4) | ForEach-Object {
        $v = [Convert]::ToInt32($h.Substring($_, 2), 16) / 255
        if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow((($v + 0.055) / 1.055), 2.4) }
    }
    return (0.2126 * $canais[0]) + (0.7152 * $canais[1]) + (0.0722 * $canais[2])
}

function Get-WinForgeContrastRatio {
    <#
    .SYNOPSIS
        Razão de contraste entre duas cores, de 1:1 (iguais) a 21:1 (preto e branco).
    .DESCRIPTION
        (L_claro + 0,05) / (L_escuro + 0,05). A ordem dos parâmetros não muda o resultado - quem é
        o texto e quem é o fundo importa para quem lê o relatório, não para a conta.
        O piso do WinForge é 4,5:1 (WCAG AA para texto normal).
    .OUTPUTS
        Double arredondado em duas casas.
    #>
    param(
        [Parameter(Mandatory)][string]$Fg,
        [Parameter(Mandatory)][string]$Bg
    )

    $l1 = Get-WinForgeRelativeLuminance -Hex $Fg
    $l2 = Get-WinForgeRelativeLuminance -Hex $Bg
    if ($l2 -gt $l1) { $troca = $l1; $l1 = $l2; $l2 = $troca }
    return [Math]::Round((($l1 + 0.05) / ($l2 + 0.05)), 2)
}
#endregion
