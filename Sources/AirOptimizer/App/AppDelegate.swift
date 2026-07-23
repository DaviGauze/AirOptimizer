import Cocoa

/// Delegate padrão do `NSApplication`, usado apenas para o ciclo de vida do
/// app. Guarda referências fracas para as ViewModels ativas, atribuídas por
/// `DashboardView.onAppear`, para que os comandos AppleScript
/// (`QuickBoostCommand`, `SystemStatsCommand`) leiam exatamente os mesmos
/// valores exibidos na janela principal em vez de recalcular estatísticas
/// com um baseline de %CPU zerado.
///
/// - Note: o SwiftUI `@NSApplicationDelegateAdaptor` encapsula este delegate
///   em um objeto interno próprio — `NSApp.delegate` não é literalmente esta
///   classe. Por isso os comandos AppleScript são declarados como comandos
///   de suite independentes no `.sdef` (não como propriedades de uma
///   `class-extension extends="application"`, que dependeria de KVC direto
///   sobre `NSApp.delegate` e não funciona com esse encapsulamento).
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var processListViewModel: ProcessListViewModel?
    static weak var monitorViewModel: SystemMonitorViewModel?
}
