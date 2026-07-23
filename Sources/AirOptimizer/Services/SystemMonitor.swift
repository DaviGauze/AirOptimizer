import Foundation
import Darwin

/// Serviço que coleta estatísticas agregadas do sistema (CPU total, memória
/// total/usada) usando as APIs Mach `host_statistics64` / `host_info`.
///
/// Diferente do `ProcessManager` (que foca em processos individuais), este
/// serviço responde por tudo que aparece no menu bar e nos gráficos gerais
/// do Dashboard.
final class SystemMonitor {

    /// Instância compartilhada, usada pelas ViewModels e por comandos
    /// AppleScript que precisam ler os mesmos valores exibidos na UI.
    static let shared = SystemMonitor()

    /// Guarda os "ticks" de CPU do host (user/system/idle/nice) do poll
    /// anterior para calcular %CPU do sistema como delta, da mesma forma
    /// que o Activity Monitor faz — os contadores do kernel são cumulativos
    /// desde o boot, não instantâneos.
    private var lastCPUTicks: host_cpu_load_info_data_t?

    private let pageSize: UInt64

    init() {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        self.pageSize = UInt64(size)
    }

    /// Memória física total instalada, em bytes.
    func totalPhysicalMemory() -> UInt64 {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return size
    }

    /// Memória atualmente em uso (ativa + wired + parte da comprimida),
    /// aproximando a métrica "Memory Used" do Activity Monitor.
    func usedMemoryBytes() -> UInt64 {
        guard let stats = vmStatistics() else { return 0 }
        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return usedPages * pageSize
    }

    /// Uso de CPU total do sistema em porcentagem (0-100), normalizado por
    /// número de núcleos.
    func totalCPUUsage() -> Double {
        guard let ticks = cpuLoadInfo() else { return 0 }
        defer { lastCPUTicks = ticks }

        guard let previous = lastCPUTicks else { return 0 }

        let userDelta = delta(ticks.cpu_ticks.0, previous.cpu_ticks.0)
        let systemDelta = delta(ticks.cpu_ticks.1, previous.cpu_ticks.1)
        let idleDelta = delta(ticks.cpu_ticks.2, previous.cpu_ticks.2)
        let niceDelta = delta(ticks.cpu_ticks.3, previous.cpu_ticks.3)

        let totalTicks = userDelta + systemDelta + idleDelta + niceDelta
        guard totalTicks > 0 else { return 0 }

        let busyTicks = userDelta + systemDelta + niceDelta
        return (Double(busyTicks) / Double(totalTicks)) * 100.0
    }

    /// Monta um snapshot completo para ser plotado nos gráficos do Dashboard.
    func currentStats(processCount: Int) -> SystemStats {
        SystemStats(
            timestamp: Date(),
            totalCPUUsage: totalCPUUsage(),
            totalMemoryUsedBytes: usedMemoryBytes(),
            totalMemoryBytes: totalPhysicalMemory(),
            processCount: processCount,
            cpuTemperatureCelsius: SMCReader.shared.cpuTemperatureCelsius()
        )
    }

    // MARK: - Mach helpers

    private func delta(_ current: UInt32, _ previous: UInt32) -> UInt32 {
        current >= previous ? current - previous : 0
    }

    private func vmStatistics() -> vm_statistics64_data_t? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return stats
    }

    private func cpuLoadInfo() -> host_cpu_load_info_data_t? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }
}
