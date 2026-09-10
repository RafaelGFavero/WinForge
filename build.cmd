@echo off
setlocal
cd /d "%~dp0"
echo [1/5] Engine
powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1 || exit /b 1
echo [2/5] SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest || exit /b 1
rem A aba Servidor so existe quando o Windows e servidor: a segunda rodada simula um com IIS e AD.
rem O 'setlocal' la em cima ja limita a variavel a este script, mas ela e limpa mesmo assim para
rem que os passos seguintes rodem como cliente.
echo [3/5] SelfTest (servidor simulado)
set WINFORGE_SIMULATE_SERVER=iis,ad
powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest || exit /b 1
set "WINFORGE_SIMULATE_SERVER="
echo [4/5] Launcher
dotnet build src\Launcher\WinForge.csproj -c Release -nologo || exit /b 1
echo [5/5] Copiar
copy /y src\Launcher\bin\Release\net48\WinForge.exe dist\WinForge.exe >nul || exit /b 1
echo OK: dist\WinForge.exe
