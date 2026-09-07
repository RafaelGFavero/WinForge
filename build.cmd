@echo off
setlocal
cd /d "%~dp0"
echo [1/4] Engine
powershell -NoProfile -ExecutionPolicy Bypass -File src\Engine\build.ps1 || exit /b 1
echo [2/4] SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File dist\engine\WinForge.ps1 -SelfTest || exit /b 1
echo [3/4] Launcher
dotnet build src\Launcher\WinForge.csproj -c Release -nologo || exit /b 1
echo [4/4] Copiar
copy /y src\Launcher\bin\Release\net48\WinForge.exe dist\WinForge.exe >nul || exit /b 1
echo OK: dist\WinForge.exe
