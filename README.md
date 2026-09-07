<img src="assets/logo.svg" alt="WinForge" width="128" height="128">

# WinForge

![build](https://github.com/rafaelfavero/WinForge/actions/workflows/build.yml/badge.svg)

Utilitário de otimização e reparo para Windows 10, 11 e Server. Reúne em uma única janela os
ajustes de desempenho, privacidade, jogos e manutenção que normalmente exigiriam dezenas de
comandos avulsos — cada um reversível, com Desfazer, e com um ponto de restauração opcional
criado antes de qualquer alteração. O que não se aplica ao seu computador não aparece: recursos
exclusivos do Windows 11 ficam ocultos no Windows 10, e tweaks de GPU só aparecem para a marca
de placa que você tem.

## Download

Baixe na página de [releases](https://github.com/rafaelfavero/WinForge/releases):

- `WinForge.exe` — o programa inteiro em um único arquivo, sem instalação.
- `WinForge-<versão>.zip` — o mesmo executável junto com `README.md`, `LICENSE` e `NOTICE`.

## Como usar

1. Execute o `WinForge.exe`. Ele pede elevação de administrador (os tweaks não funcionam sem ela).
2. Responda à pergunta de ponto de restauração que aparece ao abrir: crie o ponto se quiser poder
   voltar atrás pelo próprio Windows, ou pule se preferir usar só o Desfazer da ferramenta.
3. Marque o que quer aplicar e clique em aplicar. Cada tweak tem seu Desfazer.

Parâmetros de linha de comando:

| Parâmetro | O que faz |
|---|---|
| `-RestorePoint` | Cria o ponto de restauração ao abrir, sem perguntar. |
| `-NoRestorePoint` | Não pergunta nem cria ponto de restauração. |
| `-Console` | Mantém a janela de console visível (útil para ver erros). |
| `-HardwareRender` | Usa renderização WPF por hardware em vez do padrão por software. |
| `-SelfTest` | Valida configurações e XAML, imprime o resultado e sai. Não exige administrador. |

## O que tem

- **Install** — instalação de programas em lote via gerenciador de pacotes.
- **Tweaks** — desempenho, privacidade, energia, serviços, anúncios, Cortana, pesquisa, VBS,
  limpeza de disco, backup do registro, cache de RAM e otimização de unidades.
- **Jogos** — prioridade de CPU por jogo (IFEO), GameDVR, MMCSS, HAGS e ajustes de shader cache
  para NVIDIA, AMD e Intel.
- **Config** — recursos do Windows, correções de sistema e atalhos de manutenção.
- **Updates** — política de atualizações do Windows (padrão, adiada ou desligada).
- **Win11 Creator** — criação de mídia de instalação do Windows 11.
- **AppX** — remoção de aplicativos pré-instalados.

A janela se adapta ao sistema: no Windows 10, os itens que só existem no Windows 11 não são
exibidos; os tweaks marcados para uma marca de GPU só aparecem se aquela GPU for detectada.

## Renderização

A interface usa renderização por software por padrão — é mais compatível com drivers antigos,
sessões remotas e overlays de jogos, que costumam quebrar a aceleração WPF. Se preferir a
aceleração por hardware, rode com `-HardwareRender`.

## Compilar

Requer o .NET SDK 8. Na raiz do repositório:

```
build.cmd
```

O script gera o motor em `dist\engine\WinForge.ps1`, roda o SelfTest, compila o launcher e deixa
o executável final em `dist\WinForge.exe`.

Para rodar só a validação do motor já gerado:

```
powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest
```

O SelfTest lê a versão real do Windows. Para conferir o comportamento em outra versão sem
trocar de máquina, defina `WINFORGE_SIMULATE_BUILD` com o número do build antes de rodar — por
exemplo `WINFORGE_SIMULATE_BUILD=19045` para simular o Windows 10 22H2.

## Estrutura

```
src/Engine/         gerador do motor PowerShell/WPF
  base/             cópia intocada do utilitário de origem
  winforge/         blocos de código do WinForge (funções, assets, launcher)
  config/           tweaks, jogos e presets do WinForge
  xaml/             trechos de interface (aba Jogos e sua navegação)
  build.ps1         aplica os blocos sobre a base e escreve dist/engine/WinForge.ps1
src/Launcher/       WinForge.exe (C# net48): splash, elevação e hospedagem do motor
src/Launcher.Tests/ testes do launcher
tests/engine/       verificações do motor gerado (marca, mojibake)
tools/              utilitários de build (geração do ícone)
docs/               changelog e documentação
```

## Roadmap

- Auditoria de tweaks: relatório do que já está aplicado no sistema antes de mexer em nada.
- Detecção de hardware e drivers com recomendações específicas para a máquina.
- Suporte a Windows Server, IIS e Active Directory.
- Reparo de componentes do Windows (DISM/SFC e correção de repositório).

## Licença

MIT (veja `LICENSE`). O WinForge é derivado do WinUtil, de Chris Titus Tech, e de outros trabalhos
de terceiros — os créditos e as licenças de origem estão em `NOTICE`.
