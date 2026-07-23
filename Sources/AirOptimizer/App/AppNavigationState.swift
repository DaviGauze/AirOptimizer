import Foundation

/// Aba selecionada no painel de detalhe da janela principal.
enum DashboardTab: String, CaseIterable, Identifiable {
    case processes = "Processos"
    case monitor = "Monitoramento"
    case settings = "Configurações"

    var id: String { rawValue }
}

/// Estado de navegação compartilhado entre a janela principal e o menu bar —
/// permite que o botão "Configurações" do menu bar traga a janela para
/// frente já na aba certa, em vez de só ativar o app na aba que estava aberta.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: DashboardTab = .processes
}
