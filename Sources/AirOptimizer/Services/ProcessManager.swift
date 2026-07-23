import Foundation
import Darwin
import Cocoa

/// Erros que podem ocorrer ao inspecionar ou encerrar processos.
enum ProcessManagerError: LocalizedError {
    case processNotFound(pid: Int32)
    case criticalProcessProtected(name: String)
    case killFailed(pid: Int32, errno: Int32)
    case insufficientPrivileges(pid: Int32)
    case priorityChangeFailed(pid: Int32, errno: Int32)

    var errorDescription: String? {
        switch self {
        case .processNotFound(let pid):
            return "O processo com PID \(pid) não foi encontrado (pode já ter encerrado)."
        case .criticalProcessProtected(let name):
            return CriticalProcessGuard.protectionReason(for: name)
        case .killFailed(let pid, let errno):
            return "Falha ao encerrar o processo \(pid): \(String(cString: strerror(errno)))."
        case .insufficientPrivileges(let pid):
            return "Permissão insuficiente para encerrar o processo \(pid). " +
                   "Esse processo pertence a outro usuário ou ao sistema."
        case .priorityChangeFailed(let pid, let errno):
            if errno == EACCES || errno == EPERM {
                return "Aumentar a prioridade do processo \(pid) requer privilégios de administrador (sudo). " +
                       "Reduzir a prioridade de processos em segundo plano não exige privilégios especiais."
            }
            return "Falha ao ajustar a prioridade do processo \(pid): \(String(cString: strerror(errno)))."
        }
    }
}

/// Serviço de baixo nível que lista e gerencia processos do sistema usando
/// as APIs nativas de `libproc` (disponíveis via `import Darwin`, sem
/// necessidade de bridging header) e `Foundation.Process`/`kill(2)` para
/// encerramento.
///
/// Não requer privilégios elevados: para processos de outros usuários ou do
/// sistema, `proc_pidinfo` retorna dados parciais (ou zero) e `kill()` falha
/// com `EPERM`, o que é tratado e reportado como `.insufficientPrivileges`
/// em vez de travar o app.
final class ProcessManager {

    /// Instância compartilhada usada pelas ViewModels, pelo `AppDelegate`
    /// (comandos AppleScript) e pelo `PerformanceModeViewModel`. Compartilhar
    /// uma única instância evita baselines de %CPU duplicados e mantém o
    /// estado de "níveis de prioridade alterados" consistente em todo o app.
    static let shared = ProcessManager()

    /// Guarda o tempo de CPU acumulado (user+system, em nanossegundos) visto
    /// no poll anterior para cada PID, permitindo calcular %CPU como delta
    /// entre amostras em vez de um valor cumulativo desde o boot do processo.
    private var lastCPUTimeByPID: [Int32: (time: UInt64, timestamp: Date)] = [:]

    /// Número de núcleos lógicos, usado para normalizar %CPU por processo
    /// para a mesma escala 0-100% usada por Activity Monitor (não 0-100*nCores).
    private let coreCount: Int

    init() {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.logicalcpu", &count, &size, nil, 0)
        self.coreCount = max(Int(count), 1)
    }

    // MARK: - Listagem

    /// Retorna todos os processos atualmente visíveis para o usuário atual.
    ///
    /// - Note: chamado periodicamente pelo `ProcessListViewModel` via
    ///   `DispatchSourceTimer`; o custo é O(n) processos e é seguro chamar
    ///   a cada 2-3s mesmo com milhares de processos.
    func listProcesses() -> [ProcessInfo] {
        let pids = runningPIDs()
        let now = Date()

        // Cruza PIDs com apps reais do Dock para obter nome amigável, ícone
        // e se é o app em primeiro plano — é isso que permite mostrar
        // "Safari" com o ícone em vez do nome cru do executável, e é o que
        // o Quick Boost usa para distinguir apps de daemons de sistema.
        let runningApps = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        var result: [ProcessInfo] = []
        result.reserveCapacity(pids.count)

        for pid in pids {
            guard pid > 0, let raw = taskAllInfo(for: pid) else { continue }

            let name = processName(from: raw)
            let cpu = calculateCPUUsage(
                pid: pid,
                totalUserNanos: raw.ptinfo.pti_total_user,
                totalSystemNanos: raw.ptinfo.pti_total_system,
                now: now
            )
            let app = runningApps[pid]

            let info = ProcessInfo(
                pid: pid,
                name: name,
                displayName: app?.localizedName ?? name,
                icon: app?.icon,
                path: processPath(for: pid),
                cpuUsage: cpu,
                memoryBytes: raw.ptinfo.pti_resident_size,
                state: ProcessState.from(bsdStatus: Int32(raw.pbsd.pbi_status)),
                parentPID: Int32(raw.pbsd.pbi_ppid),
                isCritical: CriticalProcessGuard.isCritical(pid: pid, name: name),
                isApplication: app?.activationPolicy == .regular,
                isFrontmost: app?.isActive ?? false
            )
            result.append(info)
        }

        pruneStaleCPUSamples(currentPIDs: Set(pids))
        return result
    }

    // MARK: - Encerramento

    /// Tenta encerrar um processo, aplicando as proteções de segurança antes
    /// de qualquer chamada destrutiva.
    ///
    /// A UI é responsável por exibir a confirmação ao usuário *antes* de
    /// chamar este método — este método assume que a confirmação já ocorreu
    /// e apenas garante as invariantes de segurança de mais baixo nível
    /// (processo crítico / privilégios).
    @discardableResult
    func terminate(pid: Int32, name: String, signal: TerminationSignal) throws -> Bool {
        if CriticalProcessGuard.isCritical(pid: pid, name: name) {
            throw ProcessManagerError.criticalProcessProtected(name: name)
        }

        guard processExists(pid: pid) else {
            throw ProcessManagerError.processNotFound(pid: pid)
        }

        let result = kill(pid, signal.signalValue)
        if result != 0 {
            let err = errno
            if err == EPERM {
                throw ProcessManagerError.insufficientPrivileges(pid: pid)
            }
            if err == ESRCH {
                throw ProcessManagerError.processNotFound(pid: pid)
            }
            throw ProcessManagerError.killFailed(pid: pid, errno: err)
        }
        return true
    }

    /// Verifica se um PID ainda corresponde a um processo vivo, sem enviar
    /// sinal algum (`kill(pid, 0)` é a forma padrão de "ping" em POSIX).
    func processExists(pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    // MARK: - Prioridade (Performance Mode)

    /// Lê o valor de "nice" atual do processo (-20 = prioridade máxima,
    /// 19 = prioridade mínima). Retorna `nil` se o processo não existir ou
    /// não puder ser consultado.
    func priority(forPID pid: Int32) -> Int32? {
        errno = 0
        let value = getpriority(PRIO_PROCESS, id_t(pid))
        if value == -1 && errno != 0 { return nil }
        return value
    }

    /// Ajusta a prioridade de escalonamento (nice) de um processo.
    ///
    /// - Note: por regra do POSIX, qualquer processo pode *aumentar* seu
    ///   próprio "nice" (reduzir prioridade) livremente, mas *reduzir* o nice
    ///   (aumentar prioridade) de um processo de outro usuário exige
    ///   privilégios de root — nesse caso o kernel retorna EACCES/EPERM,
    ///   tratado aqui como `.priorityChangeFailed` para a UI explicar ao usuário.
    @discardableResult
    func setPriority(pid: Int32, name: String, value: Int32) throws -> Bool {
        if CriticalProcessGuard.isCritical(pid: pid, name: name) {
            throw ProcessManagerError.criticalProcessProtected(name: name)
        }

        errno = 0
        let result = setpriority(PRIO_PROCESS, id_t(pid), value)
        if result != 0 {
            throw ProcessManagerError.priorityChangeFailed(pid: pid, errno: errno)
        }
        return true
    }

    // MARK: - libproc helpers

    private func runningPIDs() -> [Int32] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let capacity = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: capacity)
        let usedBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard usedBytes > 0 else { return [] }

        let usedCount = Int(usedBytes) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(usedCount)).filter { $0 != 0 }
    }

    private func taskAllInfo(for pid: Int32) -> proc_taskallinfo? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    private func processName(from info: proc_taskallinfo) -> String {
        var mutable = info
        return withUnsafePointer(to: &mutable.pbsd.pbi_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                String(cString: $0)
            }
        }
    }

    private func processPath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Converte tempo de CPU cumulativo (nanossegundos desde o início do
    /// processo) em uma taxa percentual instantânea, comparando com a
    /// amostra anterior. Na primeira observação de um PID não há baseline,
    /// então retorna 0 (evita picos falsos de 100% no primeiro poll).
    private func calculateCPUUsage(
        pid: Int32,
        totalUserNanos: UInt64,
        totalSystemNanos: UInt64,
        now: Date
    ) -> Double {
        let totalNanos = totalUserNanos + totalSystemNanos

        guard let previous = lastCPUTimeByPID[pid] else {
            lastCPUTimeByPID[pid] = (totalNanos, now)
            return 0
        }

        let elapsedSeconds = now.timeIntervalSince(previous.timestamp)
        lastCPUTimeByPID[pid] = (totalNanos, now)

        guard elapsedSeconds > 0, totalNanos >= previous.time else { return 0 }

        let deltaNanos = totalNanos - previous.time
        let deltaSeconds = Double(deltaNanos) / 1_000_000_000.0
        let usage = (deltaSeconds / elapsedSeconds) * 100.0 / Double(coreCount)
        return min(usage, 100.0)
    }

    /// Remove amostras de CPU de PIDs que não existem mais, evitando
    /// crescimento ilimitado do dicionário de baseline ao longo de uma sessão longa.
    private func pruneStaleCPUSamples(currentPIDs: Set<Int32>) {
        lastCPUTimeByPID = lastCPUTimeByPID.filter { currentPIDs.contains($0.key) }
    }
}
