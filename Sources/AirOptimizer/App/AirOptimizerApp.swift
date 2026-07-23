import SwiftUI

@main
struct AirOptimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        WindowGroup("AirOptimizer") {
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
                onOpenSettings: {
                    navigationState.selectedTab = .settings
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
        } label: {
            MenuBarIconLabel(monitorVM: monitorVM)
        }
        .menuBarExtraStyle(.window)
    }
}
