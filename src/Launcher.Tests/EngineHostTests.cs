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
            var ex = Assert.ThrowsAny<IOException>(
                () => EngineHost.CreateOrProtect(link, EngineHost.BuildDirectorySecurity(false)));
            Assert.Contains("link/junction", ex.Message);

            // o alvo continua intocado (nada de DACL protegida vazando para lá)
            Assert.False(new DirectoryInfo(target).GetAccessControl().AreAccessRulesProtected);
        }
        finally
        {
            // Delete não recursivo: remove o junction, não o conteúdo do alvo
            if (Directory.Exists(link)) Directory.Delete(link);
            Cleanup(target);
        }
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

    private static List<SecurityIdentifier> SidsOf(DirectorySecurity acl)
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
        Directory.Delete(path, true);
    }

    private static FileSystemRights RightsFor(IEnumerable<FileSystemAccessRule> rules, WellKnownSidType sidType)
    {
        var sid = new SecurityIdentifier(sidType, null);
        return rules.Single(r => r.IdentityReference.Equals(sid)).FileSystemRights;
    }
}
