import Foundation
import Combine

/// ViewModel responsável pelo histórico de `SystemStats` usado nos gráficos
/// de CPU/memória do Dashboard e pelo resumo exibido no menu bar.
@MainActor
final class SystemMonitorViewModel: ObservableObject {
    @Published private(set) var history: [SystemStats] = []
    @Published private(set) var current: SystemStats?
    @Published var memoryWarningThresholdPercent: Double = 85

    /// Controla se CPU/RAM/temperatura aparecem no ícone da menu bar (ver
    /// `MenuBarIconLabel`). Desligado, o ícone volta a mostrar só o símbolo
    /// do app.
    @Published var isMenuBarStatsEnabled: Bool = true

    /// Quantidade de amostras mantidas em memória para o gráfico. A 2.5s por
    /// amostra, 240 amostras cobrem 10 minutos de histórico — suficiente para
    /// visualizar tendências sem crescer indefinidamente.
    private let maxHistoryCount = 240

    private let systemMonitor: SystemMonitor
    private let logger: ActionLogger
    private var timer: DispatchSourceTimer?
    private var didWarnAboveThreshold = false

    init(systemMonitor: SystemMonitor = .shared, logger: ActionLogger = .shared) {
        self.systemMonitor = systemMonitor
        self.logger = logger
    }

    deinit {
        timer?.cancel()
    }

    func start(interval: TimeInterval = 2.5, processCountProvider: @escaping () -> Int) {
        timer?.cancel()
        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        newTimer.schedule(deadline: .now(), repeating: interval)
        newTimer.setEventHandler { [weak self] in
            self?.sample(processCount: processCountProvider())
        }
        newTimer.resume()
        timer = newTimer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func sample(processCount: Int) {
        let stats = systemMonitor.currentStats(processCount: processCount)
        current = stats
        history.append(stats)
        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }
        checkMemoryThreshold(stats)
    }

    /// Dispara uma entrada de log (e, futuramente, uma notificação nativa)
    /// quando a memória cruza o limite configurado. Usa uma flag de
    /// debounce simples para não gerar uma entrada a cada amostra enquanto
    /// o uso permanece acima do limite.
    private func checkMemoryThreshold(_ stats: SystemStats) {
        let isAboveThreshold = stats.memoryUsagePercentage >= memoryWarningThresholdPercent

        if isAboveThreshold && !didWarnAboveThreshold {
            didWarnAboveThreshold = true
            logger.log(ActionLogEntry(
                type: .memoryWarning,
                processName: "Sistema",
                processID: 0,
                detail: String(format: "Uso de memória atingiu %.1f%%", stats.memoryUsagePercentage)
            ))
            NotificationCenterHelper.postMemoryWarning(percentage: stats.memoryUsagePercentage)
        } else if !isAboveThreshold {
            didWarnAboveThreshold = false
        }
    }
}
