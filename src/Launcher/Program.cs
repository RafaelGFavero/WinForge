using System;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace WinForge
{
    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
            var app = new App();
            app.InitializeComponent();
            var splash = new SplashWindow(version);
            splash.Show();

            bool console = args.Any(a => string.Equals(a, "-Console", StringComparison.OrdinalIgnoreCase));
            bool selfTest = args.Any(a => string.Equals(a, "-SelfTest", StringComparison.OrdinalIgnoreCase));
            string readyName = "WinForge.Ready." + Process.GetCurrentProcess().Id + "." + Guid.NewGuid().ToString("N");
            int exitCode = 1;

            Task.Run(() =>
            {
                Process engine = null;
                try
                {
                    using (var ready = new EventWaitHandle(false, EventResetMode.ManualReset, readyName))
                    {
                        // Extração e partida do motor sob o mesmo mutex: um segundo launcher não pode
                        // apagar e recriar o .ps1 entre a extração e o Process.Start deste. Depois que
                        // o powershell.exe já leu o script, soltar é seguro — ele carrega o arquivo
                        // apontado por -File inteiro na análise inicial e fecha o handle antes de
                        // executar, então a recriação seguinte não afeta quem já está rodando. Os
                        // 500 ms cobrem a janela entre Process.Start retornar (processo criado) e o
                        // powershell efetivamente abrir o arquivo; sem WaitForInputIdle, que só vale
                        // para processos com fila de mensagens.
                        engine = EngineHost.WithEngineLock(() =>
                        {
                            var enginePath = EngineHost.EnsureEngine(version);
                            // atribui já dentro do lock: se algo estourar antes de sair daqui, o
                            // catch de baixo ainda encontra o processo para matar
                            engine = EngineHost.Start(enginePath, readyName, args, hideWindow: !console && !selfTest);
                            // Residual aceito: os 500 ms são heurística, não sincronização - não há
                            // sinal de "o powershell.exe já abriu o script". Se uma máquina muito
                            // lenta estourar esse prazo e um segundo launcher recriar o .ps1 no
                            // intervalo, o pior caso é a PRIMEIRA instância não achar o arquivo e
                            // sair com erro. Não é brecha de segurança: o arquivo recriado tem a
                            // mesma ACL protegida e vem do mesmo executável assinado.
                            Thread.Sleep(500);
                            return engine;
                        });
                        splash.Dispatcher.Invoke(() => splash.SetStatus("Carregando a interface..."));
                        var handles = new WaitHandle[] { ready, new ProcessWaitHandle(engine) };
                        int signaled = WaitHandle.WaitAny(handles, TimeSpan.FromSeconds(90));
                        if (signaled == 1 || signaled == WaitHandle.WaitTimeout)
                        {
                            if (engine.HasExited && engine.ExitCode != 0)
                                splash.Dispatcher.Invoke(() => MessageBox.Show("O motor do WinForge terminou com erro (código " + engine.ExitCode + ").\nLog: %LocalAppData%\\WinForge\\logs", "WinForge", MessageBoxButton.OK, MessageBoxImage.Error));
                            else if (signaled == WaitHandle.WaitTimeout)
                            {
                                splash.Dispatcher.Invoke(() => MessageBox.Show("O motor do WinForge não respondeu em 90 s. Execute WinForge.exe -Console para ver detalhes.", "WinForge", MessageBoxButton.OK, MessageBoxImage.Warning));
                                // sem resposta do motor: encerra o par para não deixar um processo sem janela rodando
                                try { engine.Kill(); } catch { }
                            }
                        }
                    }
                    splash.Dispatcher.Invoke(splash.Close);
                    if (engine != null) { engine.WaitForExit(); exitCode = engine.ExitCode; }
                }
                catch (Exception ex)
                {
                    // não deixa o motor órfão se o launcher falhar depois de iniciá-lo
                    if (engine != null)
                    {
                        try { if (!engine.HasExited) engine.Kill(); } catch { }
                    }
                    splash.Dispatcher.Invoke(() => { MessageBox.Show("Falha ao iniciar o WinForge:\n" + ex.Message, "WinForge", MessageBoxButton.OK, MessageBoxImage.Error); splash.Close(); });
                }
                finally { app.Dispatcher.Invoke(app.Shutdown); }
            });

            app.Run();
            return exitCode;
        }

        private sealed class ProcessWaitHandle : WaitHandle
        {
            public ProcessWaitHandle(Process p) { SafeWaitHandle = new Microsoft.Win32.SafeHandles.SafeWaitHandle(p.Handle, false); }
        }
    }
}
