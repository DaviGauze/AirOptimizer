import Cocoa

/// Estado de execução reportado pelo kernel para um processo.
enum ProcessState: String, CaseIterable {
    case running = "Running"
    case sleeping = "Sleeping"
    case stopped = "Stopped"
    case zombie = "Zombie"
    case idle = "Idle"
    case unknown = "Unknown"

    /// Mapeia o campo `p_stat` retornado por `proc_pidinfo` (kinfo_proc/PROC_PIDTBSDINFO).
    static func from(bsdStatus: Int32) -> ProcessState {
        switch bsdStatus {
        case SIDL: return .idle
        case SRUN: return .running
        case SSLEEP: return .sleeping
        case SSTOP: return .stopped
        case SZOMB: return .zombie
        default: return .unknown
        }
    }
}

/// Representa um único sinal que pode ser enviado a um processo ao encerrá-lo.
enum TerminationSignal: String, CaseIterable, Identifiable {
    case sigterm = "SIGTERM"
    case sigkill = "SIGKILL"

    var id: String { rawValue }

    var signalValue: Int32 {
        switch self {
        case .sigterm: return SIGTERM
        case .sigkill: return SIGKILL
        }
    }

    /// Rótulo amigável exibido nos botões da UI — o nome técnico do sinal
    /// POSIX (visível em `rawValue`) só aparece no diálogo de confirmação,
    /// não no botão em si.
    var actionLabel: String {
        switch self {
        case .sigterm: return "Fechar"
        case .sigkill: return "Forçar Parada"
        }
    }

    var actionIcon: String {
        switch self {
        case .sigterm: return "xmark.circle"
        case .sigkill: return "bolt.slash.fill"
        }
    }

    var description: String {
        switch self {
        case .sigterm: return "Encerramento educado (permite que o app salve estado)"
        case .sigkill: return "Encerramento forçado (imediato, sem aviso ao app)"
        }
    }
}

/// Modelo de domínio que descreve um processo em execução no sistema.
///
/// Instâncias são recalculadas a cada ciclo de polling do `ProcessManager`;
/// não representam um snapshot persistente.
struct ProcessInfo: Identifiable, Hashable {
    let pid: Int32
    /// Nome cru do executável, como reportado pelo kernel (`pbi_name` via
    /// libproc) — para daemons/processos de sistema costuma já ser o nome
    /// técnico correto (ex.: "coreaudiod"), mas para apps costuma divergir
    /// do nome exibido no Dock/Finder (ex.: "Google Chrome Helper (Renderer)").
    let name: String
    /// Nome amigável para exibição: vem de `NSRunningApplication.localizedName`
    /// quando o processo corresponde a um app com interface (ex.: "Safari"),
    /// caindo para `name` quando é um processo de sistema sem app associado.
    let displayName: String
    /// Ícone do app no Dock, quando o processo corresponde a um app com
    /// interface. `nil` para processos de sistema.
    let icon: NSImage?
    /// Caminho completo do executável, quando disponível (pode falhar por permissões/sandbox).
    let path: String?
    /// Uso de CPU em porcentagem, calculado como delta de tempo de CPU entre dois polls.
    var cpuUsage: Double
    /// Memória residente (RSS) em bytes.
    var memoryBytes: UInt64
    var state: ProcessState
    /// PID do processo pai, usado para detectar órfãos/zumbis e para futura visão em árvore.
    let parentPID: Int32
    let isCritical: Bool
    /// `true` quando o processo corresponde a um app "normal" do Dock
    /// (`NSRunningApplication.activationPolicy == .regular`), em vez de um
    /// daemon/processo auxiliar do sistema. Usado para decidir o que o
    /// Quick Boost pode encerrar com segurança.
    let isApplication: Bool
    /// `true` quando este é o app atualmente em primeiro plano — nunca é
    /// alvo do Quick Boost.
    let isFrontmost: Bool

    var id: Int32 { pid }

    var memoryMegabytes: Double {
        Double(memoryBytes) / 1_048_576.0
    }

    var formattedMemory: String {
        let mb = memoryMegabytes
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage)
    }

    static func == (lhs: ProcessInfo, rhs: ProcessInfo) -> Bool {
        lhs.pid == rhs.pid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}
