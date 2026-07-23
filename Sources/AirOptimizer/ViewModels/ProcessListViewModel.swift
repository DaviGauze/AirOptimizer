import Foundation
import Combine

/// Critério de ordenação da tabela de processos.
enum ProcessSortField: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memória"
    case name = "Nome"

    var id: String { rawValue }
}

/// ViewModel que conecta `ProcessManager` à `DashboardView`.
///
/// Mantém o polling em um `DispatchSourceTimer` (em vez de `Timer` comum)
/// porque ele roda de forma confiável em background sem depender do
/// RunLoop estar em `.default` mode — importante já que a janela principal
/// pode estar com um menu ou sheet aberto durante o refresh.
@MainActor
final class ProcessListViewModel: ObservableObject {
    @Published private(set) var processes: [ProcessInfo] = []
    @Published var searchText: String = ""
    @Published var sortField: ProcessSortField = .cpu
    @Published var sortAscending: Bool = false
    @Published private(set) var lastError: String?
    @Published var isAutoRefreshEnabled: Bool = true
    @Published var showOnlyZombies: Bool = false

    /// PIDs de processos zumbi já notificados nesta sessão, para não gerar
    /// uma entrada de log a cada ciclo de refresh enquanto o zumbi persistir
    /// (o pai precisa fazer `wait()` para ele desaparecer; até lá, o mesmo
    /// zumbi aparece em todo poll).
    private var notifiedZombiePIDs: Set<Int32> = []

    /// Intervalo de auto-refresh, configurável nas Preferências (2-3s por padrão).
    @Published var refreshInterval: TimeInterval = 2.5 {
        didSet { restartTimerIfNeeded() }
    }

    private let processManager: ProcessManager
    private let logger: ActionLogger
    private var timer: DispatchSourceTimer?

    /// Processos em estado zumbi (terminaram, mas o pai ainda não fez
    /// `wait()` para coletar o status de saída). Não podem ser "mortos" —
    /// já estão mortos — mas indicam um pai que pode estar com bug.
    var zombieProcesses: [ProcessInfo] {
        processes.filter { $0.state == .zombie }
    }

    var filteredProcesses: [ProcessInfo] {
        let scoped = showOnlyZombies ? zombieProcesses : processes
        let base = searchText.isEmpty
            ? scoped
            : scoped.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }

        return base.sorted { lhs, rhs in
            let result: Bool
            switch sortField {
            case .cpu: result = lhs.cpuUsage < rhs.cpuUsage
            case .memory: result = lhs.memoryBytes < rhs.memoryBytes
            case .name: result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    init(processManager: ProcessManager = .shared, logger: ActionLogger = .shared) {
        self.processManager = processManager
        self.logger = logger
        refresh()
        startAutoRefresh()
    }

    deinit {
        timer?.cancel()
    }

    func refresh() {
        processes = processManager.listProcesses()
        detectNewZombies()
    }

    /// Compara os zumbis vistos agora com os já notificados e registra uma
    /// entrada de log só para os que apareceram desde o último check —
    /// evita floodar o histórico com o mesmo zumbi a cada 2.5s.
    private func detectNewZombies() {
        let currentZombiePIDs = Set(zombieProcesses.map(\.pid))
        let newZombies = zombieProcesses.filter { !notifiedZombiePIDs.contains($0.pid) }

        for zombie in newZombies {
            logger.log(ActionLogEntry(
                type: .zombieDetected,
                processName: zombie.name,
                processID: zombie.pid,
                detail: "Processo zumbi detectado (PID pai: \(zombie.parentPID))"
            ))
        }

        notifiedZombiePIDs = currentZombiePIDs
    }

    func startAutoRefresh() {
        timer?.cancel()
        guard isAutoRefreshEnabled else { return }

        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        newTimer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        newTimer.setEventHandler { [weak self] in
            self?.refresh()
        }
        newTimer.resume()
        timer = newTimer
    }

    func stopAutoRefresh() {
        timer?.cancel()
        timer = nil
    }

    private func restartTimerIfNeeded() {
        guard timer != nil else { return }
        startAutoRefresh()
    }

    /// Encerra um processo específico após confirmação já ter ocorrido na UI.
    /// Atualiza a lista imediatamente para dar feedback rápido ao usuário,
    /// sem esperar o próximo ciclo de auto-refresh.
    func terminate(_ process: ProcessInfo, signal: TerminationSignal) {
        do {
            try processManager.terminate(pid: process.pid, name: process.name, signal: signal)
            logger.log(ActionLogEntry(
                type: .processKilled,
                processName: process.name,
                processID: process.pid,
                detail: "Encerrado com \(signal.rawValue)"
            ))
            lastError = nil
            refresh()
        } catch {
            if case ProcessManagerError.criticalProcessProtected = error {
                logger.log(ActionLogEntry(
                    type: .killBlocked,
                    processName: process.name,
                    processID: process.pid,
                    detail: "Tentativa bloqueada: processo crítico"
                ))
            }
            lastError = error.localizedDescription
        }
    }

    /// Libera memória inativa do sistema (ver `PerformanceOptimizer`). Não
    /// encerra nenhum app — por isso não há mais folha de confirmação nem
    /// lista de candidatos: não há nada para o usuário revisar antes de agir.
    func runQuickBoost() {
        PerformanceOptimizer.runQuickBoost(logger: logger)
        refresh()
    }

    func dismissError() {
        lastError = nil
    }
}
