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
            string readyName = "WinForge.Ready." + Process.GetCurrentProcess().Id;
            int exitCode = 1;

            Task.Run(() =>
            {
                Process engine = null;
                try
                {
                    var enginePath = EngineHost.EnsureEngine(version);
                    using (var ready = new EventWaitHandle(false, EventResetMode.ManualReset, readyName))
                    {
                        engine = EngineHost.Start(enginePath, readyName, args, hideWindow: !console && !selfTest);
                        splash.Dispatcher.Invoke(() => splash.SetStatus("Carregando a interface..."));
                        var handles = new WaitHandle[] { ready, new ProcessWaitHandle(engine) };
                        int signaled = WaitHandle.WaitAny(handles, TimeSpan.FromSeconds(90));
                        if (signaled == 1 || signaled == WaitHandle.WaitTimeout)
                        {
                            if (engine.HasExited && engine.ExitCode != 0)
                                splash.Dispatcher.Invoke(() => MessageBox.Show("O motor do WinForge terminou com erro (código " + engine.ExitCode + ").\nLog: %LocalAppData%\\WinForge\\logs", "WinForge", MessageBoxButton.OK, MessageBoxImage.Error));
                            else if (signaled == WaitHandle.WaitTimeout)
                                splash.Dispatcher.Invoke(() => MessageBox.Show("O motor do WinForge não respondeu em 90 s. Execute WinForge.exe -Console para ver detalhes.", "WinForge", MessageBoxButton.OK, MessageBoxImage.Warning));
                        }
                    }
                    splash.Dispatcher.Invoke(splash.Close);
                    if (engine != null) { engine.WaitForExit(); exitCode = engine.ExitCode; }
                }
                catch (Exception ex)
                {
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
