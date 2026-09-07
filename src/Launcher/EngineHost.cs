using System;
using System.Diagnostics;
using System.Globalization;
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
        /// O dono é BUILTIN\Administrators: o dono de um objeto mantém WRITE_DAC implícito e
        /// poderia reescrever a DACL protegida depois da extração.
        /// </summary>
        public static DirectorySecurity BuildDirectorySecurity()
        {
            return BuildDirectorySecurity(true);
        }

        private static DirectorySecurity BuildDirectorySecurity(bool setOwner)
        {
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            if (setOwner) security.SetOwner(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null));
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
            ProtectBaseDirectory(baseDir);

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

        /// <summary>
        /// Cria a pasta base já com a ACL protegida (não existe janela entre criar e proteger) ou,
        /// se ela já existe, reaplica a ACL. Doar a posse ao grupo Administradores exige
        /// SeRestorePrivilege; se o token não tiver, registra e repete sem dono — a DACL
        /// protegida continua obrigatória em qualquer caso.
        /// </summary>
        private static void ProtectBaseDirectory(string baseDir)
        {
            try
            {
                CreateOrProtect(baseDir, BuildDirectorySecurity(true));
            }
            // ERROR_INVALID_OWNER chega com tipos diferentes conforme o caminho: IOException vindo
            // de Directory.CreateDirectory(path, security) e InvalidOperationException vindo de
            // DirectoryInfo.SetAccessControl (UnauthorizedAccessException cobre
            // PrivilegeNotHeldException). Falha de E/S de verdade estoura de novo na 2ª tentativa.
            catch (Exception ex) when (ex is IOException || ex is InvalidOperationException || ex is UnauthorizedAccessException)
            {
                LogOwnerFailure(ex.Message);
                CreateOrProtect(baseDir, BuildDirectorySecurity(false));
            }
        }

        private static void CreateOrProtect(string baseDir, DirectorySecurity security)
        {
            var info = new DirectoryInfo(baseDir);
            if (info.Exists) { info.SetAccessControl(security); return; }
            Directory.CreateDirectory(baseDir, security);
            // Corrida: se outro processo criar a pasta entre o Exists e o CreateDirectory, o CLR
            // trata ERROR_ALREADY_EXISTS como sucesso e ignora a DirectorySecurity — sobraria a
            // pasta alheia, sem proteção. Confere e reaplica.
            info.Refresh();
            if (!info.GetAccessControl().AreAccessRulesProtected) info.SetAccessControl(security);
        }

        private static void LogOwnerFailure(string message)
        {
            try
            {
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WinForge");
                Directory.CreateDirectory(dir);
                // mensagens do Win32 vêm com quebra de linha no fim; uma ocorrência = uma linha
                var flat = message.Replace('\r', ' ').Replace('\n', ' ').Trim();
                File.AppendAllText(Path.Combine(dir, "launcher.log"),
                    DateTime.Now.ToString("s", CultureInfo.InvariantCulture) + " owner not set: " + flat + Environment.NewLine);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
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
