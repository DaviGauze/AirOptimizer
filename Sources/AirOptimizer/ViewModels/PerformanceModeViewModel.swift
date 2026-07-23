import Foundation
import AppKit
import Combine

/// Gerencia o "Performance Mode": tenta priorizar o app em primeiro plano e
/// reduz a prioridade de escalonamento de processos em background ociosos,
/// usando `setpriority(2)` via `ProcessManager`.
///
/// - Important: reduzir a prioridade (aumentar o "nice") de processos que o
///   próprio usuário possui não requer privilégios especiais. Já *aumentar*
///   a prioridade do app em primeiro plano (reduzir o "nice") normalmente
///   exige privilégios de root — quando isso falha, o modo continua
///   funcionando (a parte de "acalmar" o background já ajuda a percepção de
///   performance), mas o usuário é avisado via `statusMessage`.
@MainActor
final class PerformanceModeViewModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    /// Quantos pontos de "nice" somar a processos de background candidatos.
    /// Valores positivos = prioridade mais baixa (POSIX: -20 a 19).
    private let backgroundNiceDelta: Int32 = 8
    /// Valor de "nice" desejado para o app em primeiro plano. Negativo =
    /// prioridade mais alta; normalmente requer root (ver aviso acima).
    private let foregroundNiceTarget: Int32 = -5

    /// Reaplicação periódica porque o app em primeiro plano muda com o uso
    /// do usuário — sem isso, o boost ficaria "grudado" no app que estava
    /// ativo no momento em que o modo foi ligado.
    private let reapplyInterval: TimeInterval = 10

    private let processManager: ProcessManager
    private let logger: ActionLogger
    private var timer: DispatchSourceTimer?

    /// Valor de "nice" original de cada PID que este serviço alterou, para
    /// poder restaurar ao desligar o modo em vez de deixar processos com
    /// prioridade permanentemente reduzida.
    private var originalPriorities: [Int32: Int32] = [:]

    init(processManager: ProcessManager = .shared, logger: ActionLogger = .shared) {
        self.processManager = processManager
        self.logger = logger
    }

    deinit {
        timer?.cancel()
    }

    func enable(processesProvider: @escaping () -> [ProcessInfo]) {
        guard !isEnabled else { return }
        isEnabled = true
        applyOnce(processes: processesProvider())

        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        newTimer.schedule(deadline: .now() + reapplyInterval, repeating: reapplyInterval)
        newTimer.setEventHandler { [weak self] in
            self?.applyOnce(processes: processesProvider())
        }
        newTimer.resume()
        timer = newTimer

        logger.log(ActionLogEntry(
            type: .performanceModeToggled,
            processName: "Performance Mode",
            processID: 0,
            detail: "Ativado"
        ))
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        timer?.cancel()
        timer = nil
        restoreOriginalPriorities()

        logger.log(ActionLogEntry(
            type: .performanceModeToggled,
            processName: "Performance Mode",
            processID: 0,
            detail: "Desativado — prioridades originais restauradas"
        ))
    }

    private func applyOnce(processes: [ProcessInfo]) {
        let frontmostPID: Int32? = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var warning: String?

        if let frontmostPID, let frontProcess = processes.first(where: { $0.pid == frontmostPID }), !frontProcess.isCritical {
            rememberOriginalPriority(for: frontProcess.pid)
            do {
                try processManager.setPriority(pid: frontProcess.pid, name: frontProcess.name, value: foregroundNiceTarget)
            } catch {
                warning = error.localizedDescription
            }
        }

        let backgroundCandidates = processes.filter {
            !$0.isCritical &&
            $0.state == .sleeping &&
            $0.cpuUsage < 1.0 &&
            $0.pid != frontmostPID
        }

        for process in backgroundCandidates {
            rememberOriginalPriority(for: process.pid)
            _ = try? processManager.setPriority(pid: process.pid, name: process.name, value: backgroundNiceDelta)
        }

        statusMessage = warning
    }

    func acknowledgeStatus() {
        statusMessage = nil
    }

    private func rememberOriginalPriority(for pid: Int32) {
        guard originalPriorities[pid] == nil else { return }
        originalPriorities[pid] = processManager.priority(forPID: pid) ?? 0
    }

    private func restoreOriginalPriorities() {
        for (pid, original) in originalPriorities {
            _ = try? processManager.setPriority(pid: pid, name: "", value: original)
        }
        originalPriorities.removeAll()
    }
}
