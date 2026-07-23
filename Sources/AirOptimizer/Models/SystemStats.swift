import Foundation

/// Snapshot agregado do estado do sistema em um instante, usado para os
/// gráficos de série temporal e para o resumo mostrado no menu bar.
struct SystemStats: Identifiable {
    let id = UUID()
    let timestamp: Date
    /// Uso total de CPU do sistema em porcentagem (0-100 * número de núcleos, normalizado a 100).
    let totalCPUUsage: Double
    let totalMemoryUsedBytes: UInt64
    let totalMemoryBytes: UInt64
    let processCount: Int
    /// `nil` quando a SMC não expõe nenhuma chave de temperatura conhecida
    /// neste Mac (ver `SMCReader`).
    let cpuTemperatureCelsius: Double?

    var memoryUsagePercentage: Double {
        guard totalMemoryBytes > 0 else { return 0 }
        return (Double(totalMemoryUsedBytes) / Double(totalMemoryBytes)) * 100
    }

    var totalMemoryUsedGB: Double {
        Double(totalMemoryUsedBytes) / 1_073_741_824.0
    }

    var totalMemoryGB: Double {
        Double(totalMemoryBytes) / 1_073_741_824.0
    }
}
