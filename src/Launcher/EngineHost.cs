using System;
using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;

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

        /// <summary>Mutex de máquina que serializa a extração do motor entre launchers.</summary>
        internal const string EngineLockName = @"Global\WinForge.EngineExtract";
        private static readonly TimeSpan EngineLockTimeout = TimeSpan.FromSeconds(60);

        /// <summary>
        /// DACL do mutex: só Administradores e SYSTEM. O launcher sempre roda elevado
        /// (requireAdministrator no manifesto), então ninguém legítimo fica de fora — e um usuário
        /// comum não consegue criar/segurar o mutex antes para travar a extração (DoS) nem abandoná-lo
        /// de propósito. Sem regra para Everyone: o nome é previsível e o objeto vive no namespace
        /// global.
        /// </summary>
        internal static MutexSecurity BuildEngineLockSecurity()
        {
            var security = new MutexSecurity();
            security.AddAccessRule(new MutexAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                MutexRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new MutexAccessRule(
                new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                MutexRights.FullControl, AccessControlType.Allow));
            return security;
        }

        /// <summary>
        /// Executa <paramref name="body"/> com o mutex de extração na mão. Dois launchers abertos ao
        /// mesmo tempo, sem isto, apagam e recriam os mesmos arquivos: um aborta o outro com
        /// violação de compartilhamento, ou pior, um deles dispara o powershell sobre um .ps1 que o
        /// segundo acabou de apagar.
        /// </summary>
        internal static T WithEngineLock<T>(Func<T> body)
        {
            return WithEngineLock(EngineLockName, BuildEngineLockSecurity(), body);
        }

        internal static T WithEngineLock<T>(string name, MutexSecurity security, Func<T> body)
        {
            bool createdNew;
            using (var mutex = new Mutex(false, name, out createdNew, security))
            {
                bool held = false;
                try
                {
                    try
                    {
                        held = mutex.WaitOne(EngineLockTimeout, false);
                    }
                    // dono anterior morreu sem soltar: o mutex é nosso, e como cada arquivo é
                    // reescrito do zero em toda execução não há estado meio-gravado a recuperar.
                    catch (AbandonedMutexException)
                    {
                        held = true;
                    }
                    if (!held)
                    {
                        throw new TimeoutException("Outra instância do WinForge está preparando o motor "
                            + "há mais de " + (int)EngineLockTimeout.TotalSeconds + " s; recusando por segurança.");
                    }
                    return body();
                }
                finally
                {
                    if (held) mutex.ReleaseMutex();
                }
            }
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
                LogOwnerFailure(dir, ex.Message);
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
                LogOwnerFailure(path, ex.Message);
                WriteProtectedFile(path, content, BuildFileSecurity(false));
                EnsureAcceptableOwner(new FileInfo(path).GetAccessControl(), path);
            }
        }

        /// <summary>
        /// <see cref="WriteProtectedFileOnce"/> com repetição limitada para violação de
        /// compartilhamento: recusar de primeira transformaria uma disputa passageira entre dois
        /// launchers numa falha de inicialização.
        /// </summary>
        internal static void WriteProtectedFile(string path, byte[] content, FileSecurity security)
        {
            for (int attempt = 1; ; attempt++)
            {
                try
                {
                    WriteProtectedFileOnce(path, content, security);
                    return;
                }
                // Arquivo momentaneamente em uso (outro launcher lendo/gravando, antivírus, o próprio
                // powershell carregando o script) não é ataque: espera e tenta de novo. Só depois de
                // esgotadas as tentativas a recusa vale. Qualquer outro erro estoura na hora.
                catch (Exception ex) when (attempt < SharingRetries && IsSharingViolation(ex))
                {
                    Thread.Sleep(SharingRetryDelayMs);
                }
            }
        }

        private const int SharingRetries = 5;
        private const int SharingRetryDelayMs = 200;
        // HRESULT_FROM_WIN32(ERROR_SHARING_VIOLATION / ERROR_LOCK_VIOLATION)
        private const int SharingViolationHResult = unchecked((int)0x80070020);
        private const int LockViolationHResult = unchecked((int)0x80070021);

        /// <summary>
        /// Violação de compartilhamento/bloqueio, tanto vinda direto do <c>CreateNew</c> quanto
        /// embrulhada pela recusa do <c>File.Delete</c>. Ler o HRESULT em vez da mensagem: a
        /// mensagem do Win32 é localizada.
        /// </summary>
        private static bool IsSharingViolation(Exception ex)
        {
            var io = ex as IOException ?? ex.InnerException as IOException;
            return io != null && (io.HResult == SharingViolationHResult || io.HResult == LockViolationHResult);
        }

        /// <summary>
        /// Apaga o que estiver no caminho e cria o arquivo do zero com a ACL protegida. Recriar em
        /// vez de sobrescrever é o ponto: <c>File.WriteAllBytes</c> num arquivo pré-plantado
        /// mantém a DACL do atacante, e carimbar a ACL por cima de um arquivo alheio ainda deixa
        /// o dono original com WRITE_DAC. Link, pasta no lugar do arquivo ou remoção que falha
        /// são recusados fechado — nunca se escreve num alvo que não é nosso.
        /// </summary>
        private static void WriteProtectedFileOnce(string path, byte[] content, FileSecurity security)
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
            // Residual aceito: entre a checagem de reparse point acima e o SetAccessControl abaixo há
            // uma janela em que a pasta poderia virar junction (TOCTOU por caminho). Ela só existe
            // antes do primeiro carimbo bem-sucedido: depois disso os pais negam Delete a Users, e
            // sem apagar a pasta não dá para pôr um link no lugar dela. Fechar de vez exigiria abrir
            // um handle com FILE_FLAG_OPEN_REPARSE_POINT e aplicar a ACL por SetSecurityInfo(handle),
            // fora do que System.Security.AccessControl expõe (P/Invoke).
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

        internal const string EventLogSource = "WinForge";
        internal const int OwnerFailureEventId = 1001;

        /// <summary>
        /// Registro no log de Aplicativo do Windows, não em arquivo. O log em arquivo anterior ficava
        /// sob %LocalAppData%\WinForge e era escrito pelo processo elevado dentro de uma pasta que o
        /// usuário comum controla: bastava plantar ali um hardlink/junction apontando para um arquivo
        /// de sistema para o launcher acrescentar texto onde não devia. O log de eventos não tem esse
        /// problema — o caminho é do sistema e o serviço faz a escrita.
        /// </summary>
        private static void LogOwnerFailure(string dir, string message)
        {
            try
            {
                // mensagens do Win32 vêm com quebra de linha no fim; uma ocorrência = uma linha
                var flat = message.Replace('\r', ' ').Replace('\n', ' ').Trim();
                // criar a origem exige elevação — que o launcher tem (requireAdministrator)
                if (!EventLog.SourceExists(EventLogSource)) EventLog.CreateEventSource(EventLogSource, "Application");
                // O texto não afirma "falta de privilégio": o catch que chama aqui aceita qualquer
                // IOException/InvalidOperationException, e disco cheio ou erro de E/S cairia no
                // mesmo lugar. Diz o que se sabe - a 1ª tentativa falhou e vai haver uma 2ª.
                EventLog.WriteEntry(EventLogSource,
                    "Não foi possível definir o dono/ACL em " + dir + " na primeira tentativa (" + flat + "); tentando sem definir o dono.",
                    EventLogEntryType.Warning, OwnerFailureEventId);
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
