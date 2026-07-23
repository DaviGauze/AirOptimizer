import Foundation

/// Lógica de Quick Boost compartilhada entre a UI (`ProcessListViewModel`),
/// o agendador automático (`CleanupScheduler`) e o comando AppleScript
/// `quick boost` — centralizada aqui para não duplicar em três lugares
/// diferentes.
///
/// Quick Boost libera memória inativa via `MemoryPurger` (equivalente ao
/// utilitário `purge` do macOS). Ele **não encerra apps** — fechar apps do
/// usuário para "otimizar performance" é justamente o que o projeto existe
/// para evitar; o objetivo é aliviar pressão de memória mantendo tudo aberto.
enum PerformanceOptimizer {

    /// Executa o Quick Boost: libera memória inativa do sistema sem
    /// encerrar nenhum processo. Usado tanto pelo clique manual na UI
    /// quanto pelo `CleanupScheduler` e pelo comando AppleScript `quick
    /// boost` — os três compartilham exatamente o mesmo comportamento, já
    /// que não há mais nenhuma lista de apps para o usuário revisar.
    static func runQuickBoost(logger: ActionLogger) {
        do {
            try MemoryPurger.purge()
            logger.log(ActionLogEntry(
                type: .quickBoost,
                processName: "Quick Boost",
                processID: 0,
                detail: "Memória inativa liberada"
            ))
        } catch {
            logger.log(ActionLogEntry(
                type: .quickBoost,
                processName: "Quick Boost",
                processID: 0,
                detail: "Falha ao liberar memória: \(error.localizedDescription)"
            ))
        }
    }
}
