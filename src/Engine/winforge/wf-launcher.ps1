#region ===== WinForge - integração com o launcher =====
function Send-WinForgeReady {
    <#
    .SYNOPSIS
        Sinaliza ao WinForge.exe que a janela está pronta (fecha o splash). Sem launcher, não faz nada.
    #>
    param([switch]$Failed)
    if ([string]::IsNullOrWhiteSpace($sync.ReadyEventName)) { return }
    try {
        $evt = [System.Threading.EventWaitHandle]::OpenExisting($sync.ReadyEventName)
        $evt.Set() | Out-Null
        $evt.Dispose()
        Write-WinForgeLog -Component "Launcher" -Message ("Evento de prontidão sinalizado ({0})." -f $(if ($Failed) { "falha" } else { "ok" }))
    } catch {
        Write-WinForgeLog -Level "WARN" -Component "Launcher" -Message "Não foi possível sinalizar $($sync.ReadyEventName): $($_.Exception.Message)"
    }
}
#endregion
