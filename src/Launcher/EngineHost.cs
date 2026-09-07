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

        internal static DirectorySecurity BuildDirectorySecurity(bool setOwner)
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

        /// <summary>
        /// Os três níveis que precisam da ACL protegida, do mais externo para o mais interno:
        /// %ProgramData%\WinForge, ...\engine e ...\engine\&lt;versão&gt;. Não basta proteger a base:
        /// como os usuários têm travessia nela, um atacante que pré-crie engine\&lt;versão&gt; com DACL
        /// própria continua dono da pasta onde o .ps1 é extraído.
        /// </summary>
        internal static string[] ProtectedDirectoryChain(string root, string version)
        {
            var baseDir = Path.Combine(root, "WinForge");
            var engineDir = Path.Combine(baseDir, "engine");
            return new[] { baseDir, engineDir, Path.Combine(engineDir, version) };
        }

        public static string EnsureEngine(string version)
        {
            var bytes = ReadEmbeddedEngine();
            var hash = ComputeSha256(bytes);
            // %ProgramData% em vez de %LocalAppData%: pasta protegida por ACL, já que o motor roda elevado.
            var root = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            foreach (var level in ProtectedDirectoryChain(root, version)) ProtectDirectory(level);

            var path = EnginePath(root, version);
            var dir = Path.GetDirectoryName(path);

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
        /// Cria a pasta já com a ACL protegida (não existe janela entre criar e proteger) ou,
        /// se ela já existe, reaplica a ACL. Doar a posse ao grupo Administradores exige
        /// SeRestorePrivilege; se o token não tiver, registra e repete sem dono — a DACL
        /// protegida continua obrigatória em qualquer caso — e depois confere o dono efetivo.
        /// </summary>
        internal static void ProtectDirectory(string dir)
        {
            try
            {
                CreateOrProtect(dir, BuildDirectorySecurity(true));
            }
            // ERROR_INVALID_OWNER chega com tipos diferentes conforme o caminho: IOException vindo
            // de Directory.CreateDirectory(path, security) e InvalidOperationException vindo de
            // DirectoryInfo.SetAccessControl (UnauthorizedAccessException cobre
            // PrivilegeNotHeldException). Falha de E/S de verdade estoura de novo na 2ª tentativa.
            // Recusa de link/junction não é problema de dono: estoura direto, sem log enganoso.
            catch (Exception ex) when (!(ex is ReparsePointRejectedException)
                && (ex is IOException || ex is InvalidOperationException || ex is UnauthorizedAccessException))
            {
                LogOwnerFailure(ex.Message);
                CreateOrProtect(dir, BuildDirectorySecurity(false));
                EnsureAcceptableOwner(new DirectoryInfo(dir).GetAccessControl(), dir);
            }
        }

        /// <summary>
        /// DACL protegida sobre dono alheio não é proteção nenhuma: o dono de um objeto mantém
        /// WRITE_DAC implícito e reescreve a ACL quando quiser. Se a posse não pôde ser assumida e
        /// o dono efetivo não é Administradores nem SYSTEM, recusa fechado em vez de seguir com a
        /// falsa sensação de pasta protegida.
        /// </summary>
        internal static void EnsureAcceptableOwner(DirectorySecurity acl, string dir)
        {
            var owner = acl.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
            if (owner != null && (owner.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid)
                || owner.IsWellKnown(WellKnownSidType.LocalSystemSid))) return;
            throw new UnauthorizedAccessException("Pasta " + dir + " pertence a outro usuário ("
                + owner + ") e o WinForge não conseguiu assumir a propriedade; recusando por segurança.");
        }

        /// <summary>
        /// Cria a pasta com a ACL protegida quando ela não existe e, em qualquer caso, carimba a
        /// ACL por cima. Carimbar sempre é o ponto: se um atacante pré-cria
        /// %ProgramData%\WinForge com DACL protegida dando FullControl a ele mesmo,
        /// Directory.CreateDirectory(path, security) devolve sucesso sem aplicar nada e qualquer
        /// verificação de "já está protegida" passaria batido. Custo: uma escrita de ACL por
        /// execução. Junction/symlink é recusado antes do carimbo — a ACL iria parar no alvo
        /// escolhido pelo atacante.
        /// </summary>
        internal static void CreateOrProtect(string dir, DirectorySecurity security)
        {
            var info = new DirectoryInfo(dir);
            if (!info.Exists) Directory.CreateDirectory(dir, security);
            info.Refresh();
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new ReparsePointRejectedException("Pasta " + dir + " é um link/junction; recusando por segurança.");
            info.SetAccessControl(security);
        }

        /// <summary>Recusa de link/junction: é IOException para quem chama, mas não dispara a
        /// segunda tentativa sem dono — o problema não é o dono.</summary>
        private sealed class ReparsePointRejectedException : IOException
        {
            public ReparsePointRejectedException(string message) : base(message) { }
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
            // log é acessório: nenhuma falha aqui pode impedir a 2ª tentativa sem dono.
            catch (Exception) { }
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
