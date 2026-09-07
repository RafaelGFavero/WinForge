using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using WinForge;
using Xunit;

public class EngineHostTests
{
    [Fact]
    public void ComputeSha256_KnownVector()
    {
        var hash = EngineHost.ComputeSha256(Encoding.ASCII.GetBytes("abc"));
        Assert.Equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", hash);
    }

    [Fact]
    public void NeedsExtract_WhenFileMissing_True()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".ps1");
        Assert.True(EngineHost.NeedsExtract(path, "00"));
    }

    [Fact]
    public void NeedsExtract_WhenHashMatches_False()
    {
        var path = Path.GetTempFileName();
        File.WriteAllBytes(path, Encoding.ASCII.GetBytes("abc"));
        Assert.False(EngineHost.NeedsExtract(path, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
        File.Delete(path);
    }

    [Fact]
    public void BuildArguments_QuotesPathAndPassesThrough()
    {
        var args = EngineHost.BuildArguments(@"C:\x y\WinForge.ps1", "WinForge.Ready.42", new[] { "-NoRestorePoint", "-Preset", "Gamer" }, hideWindow: true);
        Assert.Equal("-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\x y\\WinForge.ps1\" -ReadyEvent WinForge.Ready.42 -NoRestorePoint -Preset Gamer", args);
    }

    [Fact]
    public void BuildArguments_ConsoleFlag_NotForwardedAndWindowVisible()
    {
        var args = EngineHost.BuildArguments(@"C:\e.ps1", "ev", new[] { "-Console" }, hideWindow: false);
        Assert.Equal("-STA -NoProfile -ExecutionPolicy Bypass -File \"C:\\e.ps1\" -ReadyEvent ev", args);
    }

    [Fact]
    public void BuildArguments_ForwardsHardwareRender()
    {
        var args = EngineHost.BuildArguments(@"C:\e.ps1", "ev", new[] { "-HardwareRender" }, hideWindow: true);
        Assert.Equal("-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\e.ps1\" -ReadyEvent ev -HardwareRender", args);
    }

    [Fact]
    public void EnginePath_UsesVersionFolder()
    {
        // a raiz passada por EnsureEngine é %ProgramData% (pasta protegida por ACL)
        Assert.Equal(@"C:\ProgramData\WinForge\engine\1.0.0\WinForge.ps1", EngineHost.EnginePath(@"C:\ProgramData", "1.0.0"));
    }

    [Fact]
    public void BuildDirectorySecurity_ProtectedWithThreeWellKnownRules()
    {
        var security = EngineHost.BuildDirectorySecurity();
        Assert.True(security.AreAccessRulesProtected);

        // dono = BUILTIN\Administrators: sem isso o criador da pasta mantém WRITE_DAC e pode
        // reescrever a DACL protegida depois da extração.
        var owner = security.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
        Assert.NotNull(owner);
        Assert.True(owner.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid));

        var rules = security.GetAccessRules(true, false, typeof(SecurityIdentifier))
            .Cast<FileSystemAccessRule>()
            .ToList();
        Assert.Equal(3, rules.Count);

        const InheritanceFlags inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
        Assert.All(rules, r =>
        {
            Assert.Equal(AccessControlType.Allow, r.AccessControlType);
            Assert.Equal(inherit, r.InheritanceFlags);
            Assert.Equal(PropagationFlags.None, r.PropagationFlags);
        });

        Assert.Equal(FileSystemRights.FullControl, RightsFor(rules, WellKnownSidType.BuiltinAdministratorsSid));
        Assert.Equal(FileSystemRights.FullControl, RightsFor(rules, WellKnownSidType.LocalSystemSid));
        // o CLR acrescenta Synchronize a ReadAndExecute; o que importa é ler sim, escrever não
        var userRights = RightsFor(rules, WellKnownSidType.BuiltinUsersSid);
        Assert.Equal(FileSystemRights.ReadAndExecute, userRights & FileSystemRights.ReadAndExecute);
        Assert.Equal((FileSystemRights)0, userRights & FileSystemRights.Write);
        Assert.Equal((FileSystemRights)0, userRights & FileSystemRights.Delete);
    }

    [Fact]
    public void CreateOrProtect_NewDirectory_HasOurDacl()
    {
        var path = ScratchPath();
        try
        {
            // sem dono: o teste não roda elevado, e doar a posse ao grupo Administradores exigiria
            // SeRestorePrivilege. A DACL é a mesma nos dois casos.
            EngineHost.CreateOrProtect(path, EngineHost.BuildDirectorySecurity(false));

            var acl = new DirectoryInfo(path).GetAccessControl();
            Assert.True(acl.AreAccessRulesProtected);
            Assert.Equal(ExpectedSids(), SidsOf(acl));
        }
        finally { Cleanup(path); }
    }

    [Fact]
    public void CreateOrProtect_ExistingHostileProtectedDacl_IsReplaced()
    {
        var path = ScratchPath();
        var me = WindowsIdentity.GetCurrent().User;
        try
        {
            // atacante pré-cria a pasta com DACL protegida dando FullControl só a ele: o
            // CreateDirectory(path, security) devolveria sucesso sem aplicar nada.
            var hostile = new DirectorySecurity();
            hostile.SetAccessRuleProtection(true, false);
            hostile.AddAccessRule(new FileSystemAccessRule(me, FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None, AccessControlType.Allow));
            Directory.CreateDirectory(path, hostile);
            Assert.Contains(me, SidsOf(new DirectoryInfo(path).GetAccessControl()));

            EngineHost.CreateOrProtect(path, EngineHost.BuildDirectorySecurity(false));

            var acl = new DirectoryInfo(path).GetAccessControl();
            Assert.True(acl.AreAccessRulesProtected);
            Assert.DoesNotContain(me, SidsOf(acl));
            Assert.Equal(ExpectedSids(), SidsOf(acl));
        }
        finally { Cleanup(path); }
    }

    [Fact]
    public void CreateOrProtect_ReparsePoint_Throws()
    {
        var target = ScratchPath();
        var link = ScratchPath();
        try
        {
            Directory.CreateDirectory(target);
            Mklink(link, target);
            Assert.True((new DirectoryInfo(link).Attributes & FileAttributes.ReparsePoint) != 0);

            // carimbar a ACL num junction escreveria no alvo escolhido pelo atacante
            Assert.ThrowsAny<IOException>(
                () => EngineHost.CreateOrProtect(link, EngineHost.BuildDirectorySecurity(false)));

            // o alvo continua intocado (nada de DACL protegida vazando para lá)
            Assert.False(new DirectoryInfo(target).GetAccessControl().AreAccessRulesProtected);
        }
        finally
        {
            // Delete não recursivo: remove o junction, não o conteúdo do alvo
            try { if (Directory.Exists(link)) Directory.Delete(link); } catch (Exception) { }
            Cleanup(target);
        }
    }

    [Fact]
    public void EnsureEngineDirectories_ProtectsEveryLevel()
    {
        // proteger só a base não basta: os usuários têm travessia nela e um atacante que pré-crie
        // engine\<versão> continua dono da pasta onde o .ps1 é extraído.
        var chain = EngineHost.ProtectedDirectoryChain(@"C:\ProgramData", "1.0.0");

        Assert.Equal(new[]
        {
            @"C:\ProgramData\WinForge",
            @"C:\ProgramData\WinForge\engine",
            @"C:\ProgramData\WinForge\engine\1.0.0"
        }, chain);

        // o último nível é exatamente a pasta onde EnsureEngine escreve o motor
        Assert.Equal(Path.GetDirectoryName(EngineHost.EnginePath(@"C:\ProgramData", "1.0.0")), chain[chain.Length - 1]);
    }

    [Fact]
    public void ProtectDirectory_ForeignOwnerWithoutOwnerAssignment_Throws()
    {
        // DACL protegida sobre dono alheio não protege nada: o dono mantém WRITE_DAC implícito.
        var acl = EngineHost.BuildDirectorySecurity(false);
        acl.SetOwner(WindowsIdentity.GetCurrent().User);

        var ex = Assert.Throws<UnauthorizedAccessException>(
            () => EngineHost.EnsureAcceptableOwner(acl, @"C:\ProgramData\WinForge"));
        Assert.Contains(@"C:\ProgramData\WinForge", ex.Message);
    }

    [Fact]
    public void ProtectDirectory_WellKnownOwner_DoesNotThrow()
    {
        var admins = EngineHost.BuildDirectorySecurity(false);
        admins.SetOwner(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null));
        EngineHost.EnsureAcceptableOwner(admins, @"C:\ProgramData\WinForge");

        var system = EngineHost.BuildDirectorySecurity(false);
        system.SetOwner(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null));
        EngineHost.EnsureAcceptableOwner(system, @"C:\ProgramData\WinForge");
    }

    [Fact]
    public void BuildFileSecurity_ProtectedWithThreeWellKnownRulesAndNoInheritance()
    {
        var security = EngineHost.BuildFileSecurity();
        Assert.True(security.AreAccessRulesProtected);

        var owner = security.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
        Assert.NotNull(owner);
        Assert.True(owner.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid));

        var rules = security.GetAccessRules(true, false, typeof(SecurityIdentifier))
            .Cast<FileSystemAccessRule>()
            .ToList();
        Assert.Equal(3, rules.Count);
        // arquivo não propaga herança: qualquer flag aqui seria rejeitada pelo Win32
        Assert.All(rules, r =>
        {
            Assert.Equal(AccessControlType.Allow, r.AccessControlType);
            Assert.Equal(InheritanceFlags.None, r.InheritanceFlags);
            Assert.Equal(PropagationFlags.None, r.PropagationFlags);
        });

        Assert.Equal(FileSystemRights.FullControl, RightsFor(rules, WellKnownSidType.BuiltinAdministratorsSid));
        Assert.Equal(FileSystemRights.FullControl, RightsFor(rules, WellKnownSidType.LocalSystemSid));
        var userRights = RightsFor(rules, WellKnownSidType.BuiltinUsersSid);
        Assert.Equal(FileSystemRights.ReadAndExecute, userRights & FileSystemRights.ReadAndExecute);
        Assert.Equal((FileSystemRights)0, userRights & FileSystemRights.Write);
        Assert.Equal((FileSystemRights)0, userRights & FileSystemRights.Delete);
    }

    [Fact]
    public void WriteProtectedFile_NewFile_HasProtectedDacl()
    {
        var path = ScratchPath() + ".ps1";
        try
        {
            // sem dono: o teste não roda elevado. A DACL é a mesma nos dois casos.
            EngineHost.WriteProtectedFile(path, Encoding.ASCII.GetBytes("motor"), EngineHost.BuildFileSecurity(false));

            Assert.Equal(Encoding.ASCII.GetBytes("motor"), File.ReadAllBytes(path));
            var acl = new FileInfo(path).GetAccessControl();
            Assert.True(acl.AreAccessRulesProtected);
            Assert.Equal(ExpectedSids(), SidsOf(acl));
        }
        finally { CleanupFile(path); }
    }

    [Fact]
    public void WriteProtectedFile_ExistingHostileFile_IsReplaced()
    {
        var path = ScratchPath() + ".ps1";
        var me = WindowsIdentity.GetCurrent().User;
        try
        {
            // atacante pré-planta o .ps1 com o conteúdo (e o hash) do motor embutido, mas com DACL
            // protegida própria: o carimbo da pasta não toca em filhos e a conferência de hash passa.
            var hostile = new FileSecurity();
            hostile.SetAccessRuleProtection(true, false);
            hostile.AddAccessRule(new FileSystemAccessRule(me, FileSystemRights.FullControl, AccessControlType.Allow));
            using (var s = new FileStream(path, FileMode.CreateNew, FileSystemRights.Write,
                FileShare.None, 4096, FileOptions.None, hostile))
            {
                var planted = Encoding.ASCII.GetBytes("plantado");
                s.Write(planted, 0, planted.Length);
            }
            Assert.Contains(me, SidsOf(new FileInfo(path).GetAccessControl()));

            EngineHost.WriteProtectedFile(path, Encoding.ASCII.GetBytes("motor"), EngineHost.BuildFileSecurity(false));

            Assert.Equal(Encoding.ASCII.GetBytes("motor"), File.ReadAllBytes(path));
            var acl = new FileInfo(path).GetAccessControl();
            Assert.True(acl.AreAccessRulesProtected);
            Assert.DoesNotContain(me, SidsOf(acl));
            Assert.Equal(ExpectedSids(), SidsOf(acl));
        }
        finally { CleanupFile(path); }
    }

    [Fact]
    public void WriteProtectedFile_DirectoryOrJunctionAtPath_Throws()
    {
        var asDirectory = ScratchPath();
        var target = ScratchPath();
        var junction = ScratchPath();
        try
        {
            // pasta no lugar do arquivo: escrever ali é impossível, mas a recusa tem de ser explícita
            Directory.CreateDirectory(asDirectory);
            Assert.ThrowsAny<IOException>(() => EngineHost.WriteProtectedFile(
                asDirectory, Encoding.ASCII.GetBytes("motor"), EngineHost.BuildFileSecurity(false)));

            // junction no lugar do arquivo: escrever ali iria parar no alvo escolhido pelo atacante
            Directory.CreateDirectory(target);
            Mklink(junction, target);
            Assert.ThrowsAny<IOException>(() => EngineHost.WriteProtectedFile(
                junction, Encoding.ASCII.GetBytes("motor"), EngineHost.BuildFileSecurity(false)));
            Assert.Empty(Directory.GetFileSystemEntries(target));
        }
        finally
        {
            try { if (Directory.Exists(junction)) Directory.Delete(junction); } catch (Exception) { }
            Cleanup(target);
            Cleanup(asDirectory);
        }
    }

    [Fact]
    public void WriteProtectedFile_ExistingFileThatCannotBeDeleted_RefusesInsteadOfOverwriting()
    {
        var path = ScratchPath() + ".ps1";
        try
        {
            // sobrescrever um arquivo alheio manteria a DACL e o dono dele; se não dá para apagar,
            // recusa fechado em vez de executar algo que o atacante ainda controla.
            using (var held = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                held.WriteByte(0x41);
                held.Flush();

                var ex = Assert.ThrowsAny<UnauthorizedAccessException>(() => EngineHost.WriteProtectedFile(
                    path, Encoding.ASCII.GetBytes("motor"), EngineHost.BuildFileSecurity(false)));
                Assert.Contains(path, ex.Message);
            }

            Assert.Equal(new byte[] { 0x41 }, File.ReadAllBytes(path));
        }
        finally { CleanupFile(path); }
    }

    private static void Mklink(string link, string target)
    {
        var psi = new ProcessStartInfo("cmd.exe", "/c mklink /J \"" + link + "\" \"" + target + "\"")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        using (var p = Process.Start(psi))
        {
            var output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
            p.WaitForExit();
            Assert.True(p.ExitCode == 0 && Directory.Exists(link), "mklink /J falhou: " + output);
        }
    }

    private static string ScratchPath()
    {
        return Path.Combine(Path.GetTempPath(), "WinForgeTest_" + Guid.NewGuid().ToString("N"));
    }

    private static List<SecurityIdentifier> ExpectedSids()
    {
        return new List<SecurityIdentifier>
        {
            new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
            new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
            new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null)
        }.OrderBy(s => s.Value).ToList();
    }

    private static List<SecurityIdentifier> SidsOf(FileSystemSecurity acl)
    {
        return acl.GetAccessRules(true, false, typeof(SecurityIdentifier))
            .Cast<FileSystemAccessRule>()
            .Select(r => (SecurityIdentifier)r.IdentityReference)
            .Distinct()
            .OrderBy(s => s.Value)
            .ToList();
    }

    /// <summary>A DACL protegida dá só leitura aos usuários; devolve o controle antes de apagar.</summary>
    private static void Cleanup(string path)
    {
        if (!Directory.Exists(path)) return;
        try
        {
            var info = new DirectoryInfo(path);
            var acl = info.GetAccessControl();
            acl.SetAccessRuleProtection(false, true);
            acl.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User,
                FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None, AccessControlType.Allow));
            info.SetAccessControl(acl);
        }
        catch (Exception) { }
        // limpeza nunca pode mascarar a falha de uma asserção
        try { Directory.Delete(path, true); } catch (Exception) { }
    }

    /// <summary>Mesma ideia para arquivos: o criador é o dono, então sempre pode reabrir a DACL.</summary>
    private static void CleanupFile(string path)
    {
        if (!File.Exists(path)) return;
        try
        {
            var info = new FileInfo(path);
            var acl = info.GetAccessControl();
            acl.SetAccessRuleProtection(false, true);
            acl.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User,
                FileSystemRights.FullControl, AccessControlType.Allow));
            info.SetAccessControl(acl);
        }
        catch (Exception) { }
        try { File.Delete(path); } catch (Exception) { }
    }

    private static FileSystemRights RightsFor(IEnumerable<FileSystemAccessRule> rules, WellKnownSidType sidType)
    {
        var sid = new SecurityIdentifier(sidType, null);
        return rules.Single(r => r.IdentityReference.Equals(sid)).FileSystemRights;
    }
}
