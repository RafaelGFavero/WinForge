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

        /// <summary>
        /// Comparação de hash com o arquivo em disco. ATENÇÃO: não é mais usada por
        /// <see cref="EnsureEngine"/> e não serve como controle de segurança — um usuário comum
        /// pode pré-plantar um WinForge.ps1 com o conteúdo (e portanto o hash) do motor embutido
        /// mas com DACL própria, e depois trocar o conteúdo entre a conferência e a execução.
        /// Continua aqui só como utilitário de diagnóstico.
        /// </summary>
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
        /// ACL dos arquivos do motor, espelhando a da pasta: administradores e SYSTEM com controle
        /// total, usuários só leem e executam, DACL protegida (não herda nada) e dono
        /// BUILTIN\Administrators. Arquivos não propagam herança, então sem flags de herança.
        /// </summary>
        public static FileSecurity BuildFileSecurity()
        {
            return BuildFileSecurity(true);
        }

        internal static FileSecurity BuildFileSecurity(bool setOwner)
        {
            var security = new FileSecurity();
            security.SetAccessRuleProtection(true, false);
            if (setOwner) security.SetOwner(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null));
            security.AddAccessRule(new FileSystemAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                FileSystemRights.FullControl, InheritanceFlags.None, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(
                new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                FileSystemRights.FullControl, InheritanceFlags.None, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null),
                FileSystemRights.ReadAndExecute, InheritanceFlags.None, PropagationFlags.None, AccessControlType.Allow));
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

            // Recria os quatro arquivos em toda execução, sempre com a ACL protegida. O antigo
            // atalho "hash bate, não extrai" era o furo: um usuário comum podia pré-plantar o
            // WinForge.ps1 com exatamente o conteúdo embutido (hash idêntico) e DACL própria; o
            // carimbo da pasta não toca em filhos com DACL protegida, a conferência de hash
            // passava e o launcher executava um arquivo que o atacante ainda controlava. Custo de
            // reescrever tudo: ~830 KB por execução.
            WriteProtectedFile(path, bytes);
            WriteProtectedFile(path + ".sha256", Encoding.UTF8.GetBytes(hash));
            // atribuição MIT sempre ao lado do motor (o diálogo de Créditos abre o NOTICE.txt)
            WriteProtectedFile(Path.Combine(dir, "NOTICE.txt"), ReadEmbeddedResource(NoticeResourceName));
            WriteProtectedFile(Path.Combine(dir, "LICENSE.txt"), ReadEmbeddedResource(LicenseResourceName));
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
            // Recusa de alvo (link/junction, pasta no lugar do arquivo, arquivo que não pôde ser
            // removido) não é problema de dono: estoura direto, sem log enganoso.
            catch (Exception ex) when (!(ex is IUnsafeTargetRefusal)
                && (ex is IOException || ex is InvalidOperationException || ex is UnauthorizedAccessException))
            {
                LogOwnerFailure(ex.Message);
                CreateOrProtect(dir, BuildDirectorySecurity(false));
                EnsureAcceptableOwner(new DirectoryInfo(dir).GetAccessControl(), dir);
            }
        }

        /// <summary>
        /// Escreve o arquivo já com a ACL protegida, com a mesma queda para "sem dono" da
        /// <see cref="ProtectDirectory"/>: doar a posse ao grupo Administradores exige um token
        /// elevado; sem ele, registra, repete sem dono e confere o dono efetivo.
        /// </summary>
        internal static void WriteProtectedFile(string path, byte[] content)
        {
            try
            {
                WriteProtectedFile(path, content, BuildFileSecurity(true));
            }
            catch (Exception ex) when (!(ex is IUnsafeTargetRefusal)
                && (ex is IOException || ex is InvalidOperationException || ex is UnauthorizedAccessException))
            {
                LogOwnerFailure(ex.Message);
                WriteProtectedFile(path, content, BuildFileSecurity(false));
                EnsureAcceptableOwner(new FileInfo(path).GetAccessControl(), path);
            }
        }

        /// <summary>
        /// Apaga o que estiver no caminho e cria o arquivo do zero com a ACL protegida. Recriar em
        /// vez de sobrescrever é o ponto: <c>File.WriteAllBytes</c> num arquivo pré-plantado
        /// mantém a DACL do atacante, e carimbar a ACL por cima de um arquivo alheio ainda deixa
        /// o dono original com WRITE_DAC. Link, pasta no lugar do arquivo ou remoção que falha
        /// são recusados fechado — nunca se escreve num alvo que não é nosso.
        /// </summary>
        internal static void WriteProtectedFile(string path, byte[] content, FileSecurity security)
        {
            var asDirectory = new DirectoryInfo(path);
            if (asDirectory.Exists)
            {
                throw new UnsafeTargetException("Caminho " + path
                    + ((asDirectory.Attributes & FileAttributes.ReparsePoint) != 0
                        ? " é um link/junction; recusando por segurança."
                        : " é uma pasta; recusando por segurança."));
            }

            var info = new FileInfo(path);
            if (info.Exists)
            {
                if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new UnsafeTargetException("Arquivo " + path + " é um link; recusando por segurança.");
                try
                {
                    File.Delete(path);
                }
                catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException)
                {
                    throw new FileReplaceRefusedException("Arquivo " + path
                        + " não pôde ser substituído; recusando por segurança.", ex);
                }
            }

            // CreateNew: se alguém recriar o arquivo entre o Delete e aqui, a criação falha em vez
            // de aceitar o arquivo do atacante. A ACL vai junto na criação, sem janela aberta.
            using (var stream = new FileStream(path, FileMode.CreateNew, FileSystemRights.Write,
                FileShare.None, 4096, FileOptions.None, security))
            {
                stream.Write(content, 0, content.Length);
            }
        }

        /// <summary>
        /// DACL protegida sobre dono alheio não é proteção nenhuma: o dono de um objeto mantém
        /// WRITE_DAC implícito e reescreve a ACL quando quiser. Se a posse não pôde ser assumida e
        /// o dono efetivo não é Administradores nem SYSTEM, recusa fechado em vez de seguir com a
        /// falsa sensação de pasta protegida.
        /// </summary>
        internal static void EnsureAcceptableOwner(FileSystemSecurity acl, string path)
        {
            var owner = acl.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
            if (owner != null && (owner.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid)
                || owner.IsWellKnown(WellKnownSidType.LocalSystemSid))) return;
            throw new UnauthorizedAccessException("Caminho " + path + " pertence a outro usuário ("
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
                throw new UnsafeTargetException("Pasta " + dir + " é um link/junction; recusando por segurança.");
            info.SetAccessControl(security);
        }

        /// <summary>Marca as recusas de alvo: continuam sendo IOException/UnauthorizedAccessException
        /// para quem chama, mas não disparam a segunda tentativa sem dono — o problema não é o dono.</summary>
        private interface IUnsafeTargetRefusal { }

        /// <summary>Alvo inaceitável (link/junction, ou pasta onde deveria haver arquivo).</summary>
        private sealed class UnsafeTargetException : IOException, IUnsafeTargetRefusal
        {
            public UnsafeTargetException(string message) : base(message) { }
        }

        /// <summary>Arquivo pré-existente que não pôde ser removido: sobrescrever manteria a DACL
        /// e o dono do atacante, então recusa fechado.</summary>
        private sealed class FileReplaceRefusedException : UnauthorizedAccessException, IUnsafeTargetRefusal
        {
            public FileReplaceRefusedException(string message, Exception inner) : base(message, inner) { }
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
