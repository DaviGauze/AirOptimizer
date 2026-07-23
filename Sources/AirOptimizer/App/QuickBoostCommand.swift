import Cocoa

/// Implementa o comando AppleScript `quick boost` declarado em
/// `AirOptimizer.sdef`. Reaproveita `PerformanceOptimizer` — a mesma lógica
/// usada pelo botão "Quick Boost" da UI e pelo `CleanupScheduler` — para não
/// duplicar a liberação de memória em três lugares diferentes.
///
/// Exemplo de uso via `osascript`:
/// ```applescript
/// tell application "AirOptimizer" to quick boost
/// ```
@objc(AirOptimizerQuickBoostCommand)
final class QuickBoostCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            PerformanceOptimizer.runQuickBoost(logger: .shared)
            return nil
        }
    }
}
