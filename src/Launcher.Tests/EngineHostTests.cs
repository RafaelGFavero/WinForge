using System;
using System.IO;
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
        Assert.Equal(@"C:\LAD\WinForge\engine\1.0.0\WinForge.ps1", EngineHost.EnginePath(@"C:\LAD", "1.0.0"));
    }
}
