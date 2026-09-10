# Tokens do sistema visual do WinForge (Plano 6, seção 7 do design).
#
# O arquivo base guarda tema num bloco JSON ($sync.configs.themes) com três seções - "shared",
# "Light" e "Dark" - e aplica cada linha como um recurso dinâmico da janela em tempo de execução.
# Trocar os VALORES desse bloco troca a cara do programa inteiro sem tocar em nenhum controle:
# é por isso que o visual do WinForge é, em primeiro lugar, esta tabela.
#
# $WinForgeTheme = tokens que JÁ EXISTEM na base e mudam de valor. O build reprova se algum
# sumir (Set-WinForgeThemeToken estoura), que é a proteção contra o arquivo base mudar de nome.
# $WinForgeThemeNovos = tokens que a base NÃO tem e o WinForge acrescenta. O build reprova se
# algum já existir - assim um token novo da base nunca é sobrescrito por engano.
#
# O aplicador de tema da base decide o TIPO pelo nome: nome com "color" vira SolidColorBrush,
# com "Radius" vira CornerRadius, com "Thickness"/"margin" vira Thickness, com "FontFamily" vira
# FontFamily, e o resto vira Double. Token novo tem de respeitar essa convenção de nome.
#
# Contraste: todo par texto/fundo desta tabela é conferido pelo -SelfTest (mínimo 4,5:1, WCAG AA).
# Nenhum valor daqui deve ser alterado sem rodar o SelfTest - ele é a única coisa entre um
# hexadecimal bonito e uma tela ilegível.

$WinForgeTheme = [ordered]@{

    # ---------------------------------------------------------------- comum aos dois temas
    # Tipografia: Segoe UI 13 no corpo (a base usava Arial 12) e Segoe UI Semibold 15 nos títulos
    # de categoria (a base usava Consolas 16, que é fonte de terminal e destoava de todo o resto).
    # Componentes: botão de 32 px com raio 4, aba de 118x32, caixa de seleção de 16 px.
    shared = [ordered]@{
        FontFamily                  = 'Segoe UI'
        FontSize                    = '13'
        HeaderFontFamily            = 'Segoe UI Semibold'
        HeaderFontSize              = '15'
        ButtonFontFamily            = 'Segoe UI'
        ButtonFontSize              = '13'
        ButtonHeight                = '32'
        ButtonCornerRadius          = '4'
        ButtonMargin                = '4'
        TabButtonFontSize           = '13'
        TabButtonWidth              = '118'
        TabButtonHeight             = '32'
        CheckBoxBulletDecoratorSize = '16'
        CheckBoxMargin              = '15,3,0,3'
        ConfigTabButtonFontSize     = '13'
        ConfigUpdateButtonFontSize  = '13'
        SearchBarHeight             = '32'
        SearchBarTextBoxFontSize    = '13'
        AppEntryFontSize            = '13'
        AppEntryMargin              = '4'
        CustomDialogFontSize        = '13'
        CustomDialogFontSizeHeader  = '15'
    }

    # ---------------------------------------------------------------- tema Claro
    # Fundo #F8FAFC, cartão #FFFFFF, texto #0F172A, títulos e selecionado #0369A1.
    Light = [ordered]@{
        MainBackgroundColor           = '#F8FAFC'
        MainForegroundColor           = '#0F172A'
        LabelBackgroundColor          = '#F8FAFC'
        LabelboxForegroundColor       = '#0369A1'
        LinkForegroundColor           = '#0369A1'
        LinkHoverForegroundColor      = '#0F172A'
        BorderColor                   = '#CBD5E1'
        BorderOpacity                 = '0'
        ButtonBackgroundColor         = '#E8ECF1'
        ButtonBackgroundMouseoverColor = '#D7DEE8'
        ButtonBackgroundPressedColor  = '#C3CCD8'
        ButtonBackgroundSelectedColor = '#0369A1'
        ButtonForegroundColor         = '#0F172A'
        ButtonInstallBackgroundColor  = '#FFFFFF'
        ButtonTweaksBackgroundColor   = '#FFFFFF'
        ButtonConfigBackgroundColor   = '#FFFFFF'
        ButtonUpdatesBackgroundColor  = '#FFFFFF'
        ButtonWin11ISOBackgroundColor = '#FFFFFF'
        ButtonAppxBackgroundColor     = '#FFFFFF'
        ButtonInstallForegroundColor  = '#0F172A'
        ButtonTweaksForegroundColor   = '#0F172A'
        ButtonConfigForegroundColor   = '#0F172A'
        ButtonUpdatesForegroundColor  = '#0F172A'
        ButtonWin11ISOForegroundColor = '#0F172A'
        ButtonAppxForegroundColor     = '#0F172A'
        AppInstallUnselectedColor     = '#FFFFFF'
        AppInstallHighlightedColor    = '#E8ECF1'
        AppInstallSelectedColor       = '#D7DEE8'
        ComboBoxBackgroundColor       = '#FFFFFF'
        ComboBoxForegroundColor       = '#0F172A'
        ScrollBarBackgroundColor      = '#CBD5E1'
        ScrollBarHoverColor           = '#94A3B8'
        ScrollBarDraggingColor        = '#0369A1'
        ProgressBarForegroundColor    = '#15803D'
        ToggleButtonOnColor           = '#0369A1'
        ToggleButtonOffColor          = '#475569'
        ToolTipBackgroundColor        = '#FFFFFF'
    }

    # ---------------------------------------------------------------- tema Escuro
    # Fundo #0B1220, cartão #111A2E, botão #1B2A44, texto #E6EDF5, títulos e links #7DD3FC.
    Dark = [ordered]@{
        MainBackgroundColor           = '#0B1220'
        MainForegroundColor           = '#E6EDF5'
        LabelBackgroundColor          = '#0B1220'
        LabelboxForegroundColor       = '#7DD3FC'
        LinkForegroundColor           = '#7DD3FC'
        LinkHoverForegroundColor      = '#E6EDF5'
        BorderColor                   = '#263244'
        BorderOpacity                 = '0'
        ButtonBackgroundColor         = '#1B2A44'
        ButtonBackgroundMouseoverColor = '#25385C'
        ButtonBackgroundPressedColor  = '#152238'
        ButtonBackgroundSelectedColor = '#2563EB'
        ButtonForegroundColor         = '#E6EDF5'
        ButtonInstallBackgroundColor  = '#111A2E'
        ButtonTweaksBackgroundColor   = '#111A2E'
        ButtonConfigBackgroundColor   = '#111A2E'
        ButtonUpdatesBackgroundColor  = '#111A2E'
        ButtonWin11ISOBackgroundColor = '#111A2E'
        ButtonAppxBackgroundColor     = '#111A2E'
        ButtonInstallForegroundColor  = '#E6EDF5'
        ButtonTweaksForegroundColor   = '#E6EDF5'
        ButtonConfigForegroundColor   = '#E6EDF5'
        ButtonUpdatesForegroundColor  = '#E6EDF5'
        ButtonWin11ISOForegroundColor = '#E6EDF5'
        ButtonAppxForegroundColor     = '#E6EDF5'
        AppInstallUnselectedColor     = '#111A2E'
        AppInstallHighlightedColor    = '#1B2A44'
        AppInstallSelectedColor       = '#25385C'
        ComboBoxBackgroundColor       = '#111A2E'
        ComboBoxForegroundColor       = '#E6EDF5'
        ScrollBarBackgroundColor      = '#1B2A44'
        ScrollBarHoverColor           = '#25385C'
        ScrollBarDraggingColor        = '#3B82F6'
        ProgressBarForegroundColor    = '#22C55E'
        ToggleButtonOnColor           = '#3B82F6'
        ToggleButtonOffColor          = '#94A3B8'
        ToolTipBackgroundColor        = '#111A2E'
    }
}

# Tokens que a base não tem.
#
# ButtonForegroundSelectedColor existe porque a base tem UM único ButtonForegroundColor para
# botão comum e botão selecionado. Com o fundo selecionado virando azul forte, o texto normal
# (#E6EDF5 no Escuro, #0F172A no Claro) cairia para 4,3:1 e 3,0:1 - abaixo do piso de 4,5:1.
#
# TabAccentColor é a faixa de 2 px embaixo da aba selecionada: o azul de seleção sozinho é
# discreto demais quando duas abas ficam lado a lado, e a faixa é o que diz onde você está.
#
# CardBackgroundColor é a superfície dos cartões e painéis (BorderStyle). A base pintava painel
# com a mesma cor do fundo da janela, então o contorno era a única coisa separando um do outro.
#
# RecommendedColor / DiscouragedColor / DangerColor são as cores de situação (recomendado, evitar,
# perigo). Eram três hexadecimais fixos no código - verde #2E7D32 e laranja #EF6C00 -, e cor fixa
# não serve para dois temas: no fundo escuro novo o verde caía para 3,6:1 e a lista de
# recomendações, que é a tela principal do WinForge, ficava mais apagada que o texto ao lado.
$WinForgeThemeNovos = [ordered]@{
    Light = [ordered]@{
        ButtonForegroundSelectedColor = '#FFFFFF'
        TabAccentColor                = '#E0F2FE'
        CardBackgroundColor           = '#FFFFFF'
        RecommendedColor              = '#15803D'
        DiscouragedColor              = '#B45309'
        DangerColor                   = '#B91C1C'
    }
    Dark = [ordered]@{
        ButtonForegroundSelectedColor = '#FFFFFF'
        TabAccentColor                = '#7DD3FC'
        CardBackgroundColor           = '#111A2E'
        RecommendedColor              = '#22C55E'
        DiscouragedColor              = '#F59E0B'
        DangerColor                   = '#EF4444'
    }
}
