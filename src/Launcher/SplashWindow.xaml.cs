using System;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace WinForge
{
    public partial class SplashWindow : Window
    {
        public SplashWindow(string version)
        {
            InitializeComponent();
            VersionText.Text = "versão " + version;
            Logo.Source = LoadLogo();
        }

        public void SetStatus(string text)
        {
            StatusText.Text = text;
        }

        private static ImageSource LoadLogo()
        {
            try
            {
                // o .ico tem vários tamanhos; BitmapFrame.Create devolveria o primeiro quadro (16x16)
                var uri = new Uri("pack://application:,,,/WinForge;component/winforge.ico");
                var decoder = new IconBitmapDecoder(uri, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                return decoder.Frames.OrderByDescending(f => f.PixelWidth).First();
            }
            catch
            {
                try
                {
                    using (var icon = System.Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location))
                    {
                        if (icon == null) return null;
                        return Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                    }
                }
                catch
                {
                    return null;
                }
            }
        }
    }
}
