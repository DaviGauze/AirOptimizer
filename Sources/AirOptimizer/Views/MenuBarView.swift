import SwiftUI
import AppKit

/// Conteúdo exibido no menu do ícone da status bar: uso de CPU/memória por
/// processo (top consumidores) e as ações — Quick Boost, Abrir AirOptimizer,
/// Configurações e Sair — para usar sem depender do ícone do Dock, que some
/// quando a janela principal é fechada (ver `AppDelegate`).
struct MenuBarView: View {
    @ObservedObject var monitorVM: SystemMonitorViewModel
    @ObservedObject var processListVM: ProcessListViewModel
    var onOpenWindow: () -> Void
    var onOpenSettings: () -> Void

    /// Quantos processos mostrar no resumo — o suficiente para identificar
    /// o que está pesando no sistema sem precisar abrir a janela principal.
    private let topProcessCount = 6

    private var topProcesses: [ProcessInfo] {
        processListVM.processes
            .sorted { $0.cpuUsage > $1.cpuUsage }
            .prefix(topProcessCount)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stats = monitorVM.current {
                Text("CPU: \(String(format: "%.0f%%", stats.totalCPUUsage)) · Memória: \(String(format: "%.0f%%", stats.memoryUsagePercentage))")
                    .font(.callout.bold())
            } else {
                Text("Coletando estatísticas…")
                    .font(.callout.bold())
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(topProcesses) { process in
                    HStack {
                        Text(process.displayName)
                            .lineLimit(1)
                        Spacer()
                        Text(process.formattedCPU)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(process.formattedMemory)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }

            Divider()

            Button("Quick Boost") {
                processListVM.runQuickBoost()
            }

            Button("Abrir AirOptimizer") {
                onOpenWindow()
            }

            Button("Configurações") {
                onOpenSettings()
            }

            Divider()

            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 280)
    }
}

/// Ícone da status bar com CPU/RAM/temperatura (para `MenuBarExtra`'s
/// `label`). Controlado por `monitorVM.isMenuBarStatsEnabled`.
///
/// - Note: `MenuBarExtra` só renderiza corretamente um label composto por um
///   único `Text`/`Image`/`Label` atômico — um `HStack`/`VStack` com vários
///   `Image(systemName:)` + `Text` filhos é silenciosamente cortado para só o
///   primeiro filho (bug de layout do `MenuBarExtra` nesta versão do macOS,
///   confirmado testando com texto puro sem nenhum símbolo). Por isso os três
///   valores são concatenados em uma única `Text`. Ícones (SF Symbol embutido
///   via `Text(Image(systemName:))`, e até emoji coloridos com seletor de
///   variação `\u{FE0E}` para forçar estilo monocromático) também não
///   renderizam nesse contexto — só texto puro funciona, daí os rótulos
///   "CPU"/"RAM" em vez de um glifo. Pelo mesmo motivo de altura (o item da
///   status bar é travado na altura padrão da menu bar) um layout empilhado
///   verticalmente (rótulo em cima, valor embaixo) também não é viável —
///   testado com `Text + Text` concatenados (que continuam sendo um único
///   `Text`, então não esbarra no bug de filhos múltiplos acima) e fonte de
///   7pt: a segunda linha ainda fica cortada pela metade, porque o
///   `NSStatusItem` trava a altura do container em uma linha, não em duas
///   linhas pequenas — confirmado por captura de tela real. Por isso o
///   layout final é uma linha só, com os valores em negrito.
struct MenuBarIconLabel: View {
    @ObservedObject var monitorVM: SystemMonitorViewModel

    var body: some View {
        if monitorVM.isMenuBarStatsEnabled {
            (Text("CPU ") + Text(cpuText).bold()
                + Text(" · RAM ") + Text(ramText).bold()
                + Text(" · ") + Text(tempText).bold())
                .monospacedDigit()
        } else {
            Image(systemName: "gauge.with.dots.needle.50percent")
        }
    }

    private var cpuText: String {
        guard let stats = monitorVM.current else { return "--%" }
        return String(format: "%.0f%%", stats.totalCPUUsage)
    }

    private var ramText: String {
        guard let stats = monitorVM.current else { return "--%" }
        return String(format: "%.0f%%", stats.memoryUsagePercentage)
    }

    private var tempText: String {
        guard let celsius = monitorVM.current?.cpuTemperatureCelsius else { return "--°" }
        return String(format: "%.0f°", celsius)
    }
}
