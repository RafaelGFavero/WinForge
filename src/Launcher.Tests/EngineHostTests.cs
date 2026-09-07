using System;
using System.Collections.Generic;
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

    private static FileSystemRights RightsFor(IEnumerable<FileSystemAccessRule> rules, WellKnownSidType sidType)
    {
        var sid = new SecurityIdentifier(sidType, null);
        return rules.Single(r => r.IdentityReference.Equals(sid)).FileSystemRights;
    }
}
