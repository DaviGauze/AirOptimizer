import SwiftUI

/// Aba "Configurações" da janela principal — ao contrário de uma janela de
/// preferências separada com `@AppStorage` desconectado, os controles aqui
/// são ligados diretamente às ViewModels em uso, então mudar um valor tem
/// efeito imediato (ex.: arrastar o intervalo de atualização já reinicia o
/// timer de polling).
struct SettingsPanelView: View {
    @ObservedObject var processListVM: ProcessListViewModel
    @ObservedObject var monitorVM: SystemMonitorViewModel
    @ObservedObject var performanceModeVM: PerformanceModeViewModel
    @ObservedObject var cleanupScheduler: CleanupScheduler

    var body: some View {
        Form {
            Section("Monitoramento") {
                Toggle("Auto-refresh", isOn: $processListVM.isAutoRefreshEnabled)
                    .onChange(of: processListVM.isAutoRefreshEnabled) { enabled in
                        enabled ? processListVM.startAutoRefresh() : processListVM.stopAutoRefresh()
                    }

                Slider(value: $processListVM.refreshInterval, in: 1...10, step: 0.5) {
                    Text("Intervalo de atualização")
                } minimumValueLabel: {
                    Text("1s")
                } maximumValueLabel: {
                    Text("10s")
                }
                .disabled(!processListVM.isAutoRefreshEnabled)
                Text("Atual: \(String(format: "%.1f", processListVM.refreshInterval))s")
                    .foregroundStyle(.secondary)

                Slider(value: $monitorVM.memoryWarningThresholdPercent, in: 50...99, step: 1) {
                    Text("Alerta de memória")
                } minimumValueLabel: {
                    Text("50%")
                } maximumValueLabel: {
                    Text("99%")
                }
                Text("Notificar quando memória atingir \(Int(monitorVM.memoryWarningThresholdPercent))%")
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Mostrar CPU/RAM/Temperatura na menu bar", isOn: $monitorVM.isMenuBarStatsEnabled)
                Text("Quando ativado, o ícone da menu bar mostra CPU | RAM | Temperatura lado a lado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Performance Mode") {
                Toggle("Ativar Performance Mode", isOn: Binding(
                    get: { performanceModeVM.isEnabled },
                    set: { enabled in
                        if enabled {
                            performanceModeVM.enable { processListVM.processes }
                        } else {
                            performanceModeVM.disable()
                        }
                    }
                ))
                Text("Prioriza o app em primeiro plano e reduz a prioridade de apps ociosos em background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Limpeza automática") {
                Toggle("Ativar agendador", isOn: $cleanupScheduler.isEnabled)
                Stepper(
                    "A cada \(String(format: "%.1f", cleanupScheduler.intervalHours))h",
                    value: $cleanupScheduler.intervalHours,
                    in: 0.5...12,
                    step: 0.5
                )
                .disabled(!cleanupScheduler.isEnabled)

                if let lastRun = cleanupScheduler.lastRunAt {
                    Text("Última execução: \(lastRun.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sobre") {
                Text("AirOptimizer — gerenciador de processos open source para macOS.")
                    .foregroundStyle(.secondary)
                // TODO: apontar para a URL real do repositório assim que for publicado.
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
