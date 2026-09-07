# WinForge

Utilitário de otimização e reparo para Windows 10, 11 e Server. Reúne em uma única
janela os ajustes de desempenho, privacidade, jogos e manutenção que normalmente
exigiriam dezenas de comandos avulsos — cada um reversível, com Desfazer, e com um
ponto de restauração opcional criado antes de qualquer alteração.

## Como usar

1. Baixe o `WinForge.exe`.
2. Execute o arquivo (ele pede elevação de administrador).
3. Responda à pergunta de ponto de restauração que aparece ao abrir: crie o ponto
   se quiser poder voltar atrás pelo próprio Windows, ou pule se preferir usar só o
   Desfazer da ferramenta.

## Compilar

Requer o .NET SDK 8. Na raiz do repositório:

```
build.cmd
```

O script gera o motor em `dist\engine\WinForge.ps1`, roda o SelfTest, compila o
launcher e deixa o executável final em `dist\WinForge.exe`.

## Licença

MIT (veja `LICENSE`). O WinForge é derivado do WinUtil e de outros trabalhos de
terceiros — os créditos e as licenças de origem estão em `NOTICE`.
