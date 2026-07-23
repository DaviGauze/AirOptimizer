import Foundation
import Combine

/// Executa o Quick Boost automaticamente em um intervalo configurável,
/// para o usuário que prefere "configurar e esquecer" em vez de acionar a
/// liberação de memória manualmente.
@MainActor
final class CleanupScheduler: ObservableObject {
    @Published var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    /// Intervalo entre execuções automáticas, em horas.
    @Published var intervalHours: Double = 2 {
        didSet {
            guard isEnabled, intervalHours != oldValue else { return }
            start()
        }
    }

    @Published private(set) var lastRunAt: Date?

    private let logger: ActionLogger
    private var timer: DispatchSourceTimer?

    init(logger: ActionLogger = .shared) {
        self.logger = logger
    }

    deinit {
        timer?.cancel()
    }

    private func start() {
        timer?.cancel()
        let interval = max(intervalHours, 1.0 / 60.0) * 3600
        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        newTimer.schedule(deadline: .now() + interval, repeating: interval)
        newTimer.setEventHandler { [weak self] in
            self?.runCleanup()
        }
        newTimer.resume()
        timer = newTimer
    }

    private func stop() {
        timer?.cancel()
        timer = nil
    }

    private func runCleanup() {
        PerformanceOptimizer.runQuickBoost(logger: logger)
        lastRunAt = Date()
    }
}
