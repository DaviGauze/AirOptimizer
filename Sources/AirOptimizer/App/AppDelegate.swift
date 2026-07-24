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

    /// Nunca encerrar ao fechar a última janela — o app é feito para
    /// continuar rodando só na menu bar (`MenuBarExtra`) depois disso.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Título da `WindowGroup` principal (ver `AirOptimizerApp`) — usado para
    /// distinguir a janela de conteúdo de verdade das janelas internas do
    /// AppKit (o `MenuBarExtra` mantém sua própria `NSStatusBarWindow`
    /// sempre "visível" para o hit-test do ícone, mesmo com o popover
    /// fechado; checar por `!($0 is NSPanel)` não basta porque essa classe
    /// não é uma `NSPanel`).
    private static let mainWindowTitle = "AirOptimizer"

    /// Observa o fechamento de janelas para tirar o ícone do Dock assim que
    /// não sobrar nenhuma janela de conteúdo visível — só a menu bar continua
    /// visível, como um utilitário "acessório" (estilo iStat Menus/Bartender).
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let hasVisibleContentWindow = NSApp.windows.contains {
                $0.isVisible && $0.title == Self.mainWindowTitle
            }
            if !hasVisibleContentWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
