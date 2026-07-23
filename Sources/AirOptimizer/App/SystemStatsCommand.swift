import Cocoa

/// Implementa o comando AppleScript `system stats` declarado em
/// `AirOptimizer.sdef`, lendo os mesmos valores exibidos no Dashboard.
///
/// Exemplo de uso via `osascript`:
/// ```applescript
/// tell application "AirOptimizer" to system stats
/// ```
@objc(AirOptimizerSystemStatsCommand)
final class SystemStatsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            if let stats = AppDelegate.monitorViewModel?.current {
                return String(
                    format: "CPU: %.0f%% | Memória: %.0f%% | Processos: %d",
                    stats.totalCPUUsage,
                    stats.memoryUsagePercentage,
                    stats.processCount
                )
            }
            let stats = SystemMonitor.shared.currentStats(
                processCount: AppDelegate.processListViewModel?.processes.count ?? ProcessManager.shared.listProcesses().count
            )
            return String(
                format: "CPU: %.0f%% | Memória: %.0f%% | Processos: %d",
                stats.totalCPUUsage,
                stats.memoryUsagePercentage,
                stats.processCount
            )
        }
    }
}
