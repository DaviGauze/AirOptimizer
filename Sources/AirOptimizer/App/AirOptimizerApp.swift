import SwiftUI

@main
struct AirOptimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    /// Instância única de cada ViewModel, compartilhada entre a janela
    /// principal e o menu bar — evita dois pollers independentes chamando
    /// `ProcessManager.shared` e corrompendo o baseline de %CPU um do outro.
    @StateObject private var navigationState = AppNavigationState()
    @StateObject private var processListVM = ProcessListViewModel()
    @StateObject private var monitorVM = SystemMonitorViewModel()
    @StateObject private var performanceModeVM = PerformanceModeViewModel()
    @StateObject private var cleanupScheduler = CleanupScheduler()

    init() {
        NotificationCenterHelper.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup("AirOptimizer", id: "main") {
            DashboardView(
                processListVM: processListVM,
                monitorVM: monitorVM,
                performanceModeVM: performanceModeVM,
                cleanupScheduler: cleanupScheduler
            )
            .environmentObject(navigationState)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarView(
                monitorVM: monitorVM,
                processListVM: processListVM,
                onOpenWindow: { showMainWindow() },
                onOpenSettings: {
                    navigationState.selectedTab = .settings
                    showMainWindow()
                }
            )
        } label: {
            MenuBarIconLabel(monitorVM: monitorVM)
        }
        .menuBarExtraStyle(.window)
    }

    /// A janela some do Dock quando fechada (ver `AppDelegate`), então
    /// reabri-la exige voltar a política de ativação para `.regular` antes —
    /// sem isso o app fica preso como acessório e nunca ganha foco de verdade.
    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
