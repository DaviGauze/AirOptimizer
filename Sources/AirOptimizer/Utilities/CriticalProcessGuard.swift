import Foundation

/// Centraliza as regras de proteção contra encerramento acidental de
/// processos essenciais do macOS.
///
/// Esta é a única fonte de verdade sobre "o que é crítico" — `ProcessManager`
/// consulta este tipo antes de qualquer `kill()`. Manter a lista aqui (em vez
/// de espalhada) facilita auditoria de segurança e futura configuração pelo
/// usuário (ex.: permitir que avançados adicionem exceções).
enum CriticalProcessGuard {

    /// Nomes de processo (case-insensitive, sem extensão) que nunca podem ser
    /// encerrados pelo app, independente do sinal escolhido.
    ///
    /// TODO: permitir extensão desta lista via arquivo de config assinado,
    /// para novos processos de sistema introduzidos em versões futuras do macOS.
    private static let protectedNames: Set<String> = [
        "kernel_task",
        "launchd",
        "windowserver",
        "loginwindow",
        "finder",
        "dock",
        "systemuiserver",
        "coreaudiod",
        "distnoted",
        "cfprefsd",
        "notifyd",
        "opendirectoryd",
        "securityd",
        "syslogd",
        "logd",
        "usereventagent",
        "airoptimizer" // não permite que o app se auto-encerre por engano
    ]

    /// PIDs que nunca devem ser encerrados independentemente do nome.
    /// PID 0 é o kernel scheduler; PID 1 é launchd.
    private static let protectedPIDs: Set<Int32> = [0, 1]

    static func isCritical(pid: Int32, name: String) -> Bool {
        if protectedPIDs.contains(pid) { return true }
        return protectedNames.contains(name.lowercased())
    }

    /// Mensagem amigável explicando por que um processo não pode ser encerrado,
    /// usada nos diálogos de confirmação/erro da UI.
    static func protectionReason(for name: String) -> String {
        "\"\(name)\" é um processo essencial do macOS. Encerrá-lo pode travar " +
        "o sistema ou causar perda de dados, por isso o AirOptimizer bloqueia essa ação."
    }
}
