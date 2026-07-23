import SwiftUI

/// Painel de detalhes de um processo individual — caminho completo, PID pai,
/// estado e ações de encerramento com o mesmo fluxo de confirmação usado
/// no `DashboardView`.
struct ProcessDetailView: View {
    let process: ProcessInfo
    var onTerminate: (TerminationSignal) -> Void

    @State private var confirmingSignal: TerminationSignal?

    var body: some View {
        Form {
            Section("Identificação") {
                LabeledContent("Nome", value: process.displayName)
                if process.displayName != process.name {
                    LabeledContent("Executável", value: process.name)
                }
                LabeledContent("PID", value: "\(process.pid)")
                LabeledContent("PID pai", value: "\(process.parentPID)")
                LabeledContent("Caminho", value: process.path ?? "Desconhecido")
            }

            Section("Recursos") {
                LabeledContent("CPU", value: process.formattedCPU)
                LabeledContent("Memória", value: process.formattedMemory)
                LabeledContent("Estado", value: process.state.rawValue)
            }

            if process.isCritical {
                Section {
                    Label(CriticalProcessGuard.protectionReason(for: process.name), systemImage: "lock.shield")
                        .foregroundStyle(.orange)
                }
            } else {
                Section("Ações") {
                    ForEach(TerminationSignal.allCases) { signal in
                        Button(role: .destructive) {
                            confirmingSignal = signal
                        } label: {
                            Label("Encerrar com \(signal.rawValue)", systemImage: "xmark.octagon")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(process.displayName)
        .alert(
            "Confirmar encerramento",
            isPresented: Binding(
                get: { confirmingSignal != nil },
                set: { if !$0 { confirmingSignal = nil } }
            )
        ) {
            Button("Cancelar", role: .cancel) { confirmingSignal = nil }
            Button("Encerrar", role: .destructive) {
                if let signal = confirmingSignal {
                    onTerminate(signal)
                }
                confirmingSignal = nil
            }
        } message: {
            Text("Tem certeza que deseja encerrar \"\(process.displayName)\" (PID \(process.pid))?")
        }
    }
}
