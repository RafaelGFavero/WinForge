// CreateOrProtect e BuildDirectorySecurity(bool) são internos, mas carregam a regra de segurança
// da pasta base — precisam de teste automatizado.
[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("Launcher.Tests")]
