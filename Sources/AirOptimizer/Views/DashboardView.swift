import SwiftUI

/// Tela principal do app: tabela de processos com busca/ordenação, ações de
/// gerenciamento e o painel de monitoramento do sistema.
struct DashboardView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    /// Injetadas pelo `AirOptimizerApp` — as mesmas instâncias usadas pelo
    /// `MenuBarView`, para que só exista um poller de processos/CPU no app
    /// (duas instâncias independentes chamando `ProcessManager.shared`
    /// corromperiam o baseline de delta de %CPU uma da outra).
    @ObservedObject var processListVM: ProcessListViewModel
    @ObservedObject var monitorVM: SystemMonitorViewModel
    @ObservedObject var performanceModeVM: PerformanceModeViewModel
    @ObservedObject var cleanupScheduler: CleanupScheduler

    @State private var selectedProcessID: Int32?
    @State private var pendingTermination: (process: ProcessInfo, signal: TerminationSignal)?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                monitorSummary
                Divider()

                Picker("", selection: $navigationState.selectedTab) {
                    ForEach(DashboardTab.allCases) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                switch navigationState.selectedTab {
                case .processes:
                    processTable
                case .monitor:
                    ScrollView {
                        ResourceChartView(history: monitorVM.history)
                    }
                case .settings:
                    ScrollView {
                        SettingsPanelView(
                            processListVM: processListVM,
                            monitorVM: monitorVM,
                            performanceModeVM: performanceModeVM,
                            cleanupScheduler: cleanupScheduler
                        )
                    }
                }
            }
        }
        .onAppear {
            monitorVM.start { processListVM.processes.count }
            AppDelegate.processListViewModel = processListVM
            AppDelegate.monitorViewModel = monitorVM
        }
        .onDisappear {
            monitorVM.stop()
        }
        .alert(
            "Encerrar \(pendingTermination?.process.displayName ?? "")?",
            isPresented: Binding(
                get: { pendingTermination != nil },
                set: { if !$0 { pendingTermination = nil } }
            ),
            presenting: pendingTermination
        ) { pending in
            Button("Cancelar", role: .cancel) { pendingTermination = nil }
            Button(LocalizedStringKey(pending.signal.actionLabel), role: .destructive) {
                processListVM.terminate(pending.process, signal: pending.signal)
                pendingTermination = nil
            }
        } message: { pending in
            let path = ProcessManager.shared.path(forPID: pending.process.pid) ?? "caminho desconhecido"
            let signal = "\(pending.signal.rawValue) — \(pending.signal.description)"
            Text("PID \(pending.process.pid) · \(path)\nSinal: \(signal)")
        }
        .alert(
            "Erro",
            isPresented: Binding(
                get: { processListVM.lastError != nil },
                set: { if !$0 { processListVM.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { processListVM.dismissError() }
        } message: {
            Text(processListVM.lastError ?? "")
        }
        .alert(
            "Performance Mode",
            isPresented: Binding(
                get: { performanceModeVM.statusMessage != nil },
                set: { if !$0 { performanceModeVM.acknowledgeStatus() } }
            )
        ) {
            Button("OK", role: .cancel) { performanceModeVM.acknowledgeStatus() }
        } message: {
            Text(performanceModeVM.statusMessage ?? "")
        }
    }

    private var sidebar: some View {
        List {
            Section("Ações rápidas") {
                Button {
                    processListVM.runQuickBoost()
                } label: {
                    Label("Quick Boost", systemImage: "bolt.fill")
                }
                .help("Libera memória inativa do sistema sem encerrar nenhum app")
            }

            Section("Ordenar por") {
                Picker("Ordenar por", selection: $processListVM.sortField) {
                    ForEach(ProcessSortField.allCases) { field in
                        Text(LocalizedStringKey(field.rawValue)).tag(field)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Toggle("Crescente", isOn: $processListVM.sortAscending)
            }

            if !processListVM.zombieProcesses.isEmpty {
                Section("Processos zumbi (\(processListVM.zombieProcesses.count))") {
                    Toggle("Mostrar apenas zumbis", isOn: $processListVM.showOnlyZombies)
                    Text("Um processo zumbi já terminou, mas seu pai ainda não coletou o status de saída.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("AirOptimizer")
        .frame(minWidth: 220)
    }

    private var monitorSummary: some View {
        HStack(spacing: 20) {
            if let stats = monitorVM.current {
                statTile(icon: "cpu", symbolFallback: "cpu", title: "CPU", value: String(format: "%.0f%%", stats.totalCPUUsage))
                statTile(
                    icon: "ram", symbolFallback: "memorychip",
                    title: "Memória",
                    value: String(format: "%.0f%%", stats.memoryUsagePercentage)
                )
                statTile(
                    icon: "thermometer", symbolFallback: "thermometer",
                    title: "Temperatura",
                    value: stats.cpuTemperatureCelsius.map { String(format: "%.0f°", $0) } ?? "--°"
                )
                statTile(icon: nil, symbolFallback: "number", title: "Processos", value: "\(stats.processCount)")
            } else {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .padding()
    }

    /// Ícone customizado (`Resources/Icons/`) à esquerda + rótulo em cima e
    /// valor embaixo à direita — minimalista o bastante para caber 4 tiles
    /// lado a lado na barra de resumo sem virar poluição visual.
    private func statTile(icon: String?, symbolFallback: String, title: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon, let nsImage = BundledIcon.image(named: icon) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.template)
                } else {
                    Image(systemName: symbolFallback)
                        .resizable()
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.title3.monospacedDigit())
            }
        }
    }

    private var processTable: some View {
        Table(processListVM.filteredProcesses, selection: $selectedProcessID) {
            TableColumn("Nome") { process in
                nameCell(for: process)
            }
            TableColumn("PID") { process in
                Text("\(process.pid)").monospacedDigit()
            }
            TableColumn("CPU") { process in
                Text(process.formattedCPU).monospacedDigit()
            }
            TableColumn("Memória") { process in
                Text(process.formattedMemory).monospacedDigit()
            }
            TableColumn("Status") { process in
                Text(process.state.rawValue)
            }
            TableColumn("Ações") { process in
                actionButtons(for: process)
            }
        }
        .searchable(text: $processListVM.searchText, prompt: "Buscar processo")
    }

    /// Mostra o ícone do app (quando disponível) e o nome amigável em
    /// destaque, com o nome técnico do executável como legenda só quando os
    /// dois divergem — evita repetir "Safari / Safari" e ainda deixa o nome
    /// cru acessível para quem precisa dele (ex.: para diferenciar helpers).
    @ViewBuilder
    private func nameCell(for process: ProcessInfo) -> some View {
        HStack(spacing: 8) {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: process.isApplication ? "app" : "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(process.displayName)
                    .foregroundStyle(process.isCritical ? .secondary : .primary)
                if process.displayName != process.name {
                    Text(process.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for process: ProcessInfo) -> some View {
        HStack(spacing: 6) {
            Button {
                pendingTermination = (process, .sigterm)
            } label: {
                Label(LocalizedStringKey(TerminationSignal.sigterm.actionLabel), systemImage: TerminationSignal.sigterm.actionIcon)
            }
            .buttonStyle(.bordered)
            .disabled(process.isCritical)

            Button {
                pendingTermination = (process, .sigkill)
            } label: {
                Label(LocalizedStringKey(TerminationSignal.sigkill.actionLabel), systemImage: TerminationSignal.sigkill.actionIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(process.isCritical)
        }
        .controlSize(.small)
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}
