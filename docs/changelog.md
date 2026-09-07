# Changelog

## 1.0.0 (2026-09-07)

- Launcher próprio `WinForge.exe` (C# net48): splash, elevação de administrador e hospedagem do
  motor PowerShell/WPF em um único executável.
- Rebranding completo para WinForge: textos, mensagens, links e metadados do motor gerado, com
  teste automático que barra referências de marca de terceiros no arquivo gerado.
- Logo próprio (SVG, PNG e ícone), usado na janela, no splash e no executável.
- Renderização WPF por software como padrão, mais compatível com drivers antigos, sessões remotas
  e overlays; `-HardwareRender` volta para a aceleração por hardware.
- Pergunta de ponto de restauração ao abrir, com `-RestorePoint` e `-NoRestorePoint` para
  responder pela linha de comando.
- Nova aba "Jogos": prioridade de CPU por jogo (IFEO), GameDVR, MMCSS, HAGS e shader cache.
- Filtro de compatibilidade: entradas exclusivas do Windows 11 ficam ocultas no Windows 10 e
  tweaks de GPU só aparecem para a marca de placa detectada.
- `-SelfTest`: valida configurações, XAML, montagem das abas e presets sem exigir administrador.
