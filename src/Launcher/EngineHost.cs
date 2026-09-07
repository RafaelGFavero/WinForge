using System;
using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;

namespace WinForge
{
    public static class EngineHost
    {
        public const string ResourceName = "WinForge.Engine";
        public const string NoticeResourceName = "WinForge.NOTICE";
        public const string LicenseResourceName = "WinForge.LICENSE";

        public static string ComputeSha256(byte[] data)
        {
            using (var sha = SHA256.Create())
            {
                var hash = sha.ComputeHash(data);
                var sb = new StringBuilder(hash.Length * 2);
                foreach (var b in hash) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        public static string EnginePath(string localAppData, string version)
        {
            return Path.Combine(localAppData, "WinForge", "engine", version, "WinForge.ps1");
        }

        public static bool NeedsExtract(string targetFile, string expectedHash)
        {
            if (!File.Exists(targetFile)) return true;
            var current = ComputeSha256(File.ReadAllBytes(targetFile));
            return !string.Equals(current, expectedHash, StringComparison.OrdinalIgnoreCase);
        }

        public static byte[] ReadEmbeddedResource(string resourceName)
        {
            using (var s = typeof(EngineHost).Assembly.GetManifestResourceStream(resourceName))
            {
                if (s == null) throw new InvalidOperationException("Recurso '" + resourceName + "' não encontrado no executável.");
                using (var ms = new MemoryStream()) { s.CopyTo(ms); return ms.ToArray(); }
            }
        }

        public static byte[] ReadEmbeddedEngine()
        {
            return ReadEmbeddedResource(ResourceName);
        }

        /// <summary>
        /// ACL da pasta base do motor: só administradores e SYSTEM escrevem; usuários apenas leem
        /// e executam. Impede que um usuário sem privilégio troque o .ps1 entre a extração e a
        /// execução elevada (TOCTOU). SIDs bem conhecidos, para não depender de nomes localizados.
        /// </summary>
        public static DirectorySecurity BuildDirectorySecurity()
        {
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            const InheritanceFlags inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            security.AddAccessRule(new FileSystemAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(
                new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null),
                FileSystemRights.ReadAndExecute, inherit, PropagationFlags.None, AccessControlType.Allow));
            return security;
        }

        public static string EnsureEngine(string version)
        {
            var bytes = ReadEmbeddedEngine();
            var hash = ComputeSha256(bytes);
            // %ProgramData% em vez de %LocalAppData%: pasta protegida por ACL, já que o motor roda elevado.
            var root = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            var baseDir = Path.Combine(root, "WinForge");
            var created = Directory.CreateDirectory(baseDir);
            created.SetAccessControl(BuildDirectorySecurity());

            var path = EnginePath(root, version);
            var dir = Path.GetDirectoryName(path);
            Directory.CreateDirectory(dir);

            var extracted = false;
            if (NeedsExtract(path, hash))
            {
                File.WriteAllBytes(path, bytes);
                File.WriteAllText(path + ".sha256", hash);
                extracted = true;
            }
            // atribuição MIT sempre ao lado do motor (o diálogo de Créditos abre o NOTICE.txt)
            ExtractResource(NoticeResourceName, Path.Combine(dir, "NOTICE.txt"), extracted);
            ExtractResource(LicenseResourceName, Path.Combine(dir, "LICENSE.txt"), extracted);
            return path;
        }

        private static void ExtractResource(string resourceName, string targetFile, bool force)
        {
            if (!force && File.Exists(targetFile)) return;
            File.WriteAllBytes(targetFile, ReadEmbeddedResource(resourceName));
        }

        public static string BuildArguments(string enginePath, string readyEvent, string[] passthrough, bool hideWindow)
        {
            var sb = new StringBuilder("-STA -NoProfile -ExecutionPolicy Bypass");
            if (hideWindow) sb.Append(" -WindowStyle Hidden");
            sb.Append(" -File \"").Append(enginePath).Append("\"");
            sb.Append(" -ReadyEvent ").Append(readyEvent);
            foreach (var a in passthrough)
            {
                if (string.Equals(a, "-Console", StringComparison.OrdinalIgnoreCase)) continue;
                sb.Append(' ').Append(a.IndexOf(' ') >= 0 ? "\"" + a + "\"" : a);
            }
            return sb.ToString();
        }

        public static string FindPowerShell()
        {
            var sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
            var ps = Path.Combine(sys, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(ps)) throw new FileNotFoundException("powershell.exe não encontrado", ps);
            return ps;
        }

        public static Process Start(string enginePath, string readyEvent, string[] passthrough, bool hideWindow)
        {
            var psi = new ProcessStartInfo
            {
                FileName = FindPowerShell(),
                Arguments = BuildArguments(enginePath, readyEvent, passthrough, hideWindow),
                UseShellExecute = false,
                CreateNoWindow = hideWindow,
                WorkingDirectory = Path.GetDirectoryName(enginePath)
            };
            return Process.Start(psi);
        }
    }
}
