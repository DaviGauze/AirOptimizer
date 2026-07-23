import SwiftUI
import Charts

/// Gráfico de série temporal com CPU e memória do sistema, alimentado pelo
/// histórico já coletado em `SystemMonitorViewModel.history`.
struct ResourceChartView: View {
    let history: [SystemStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uso de recursos ao longo do tempo")
                .font(.headline)

            if history.count < 2 {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Coletando amostras…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                Chart(history) { stat in
                    LineMark(
                        x: .value("Hora", stat.timestamp),
                        y: .value("Uso (%)", stat.totalCPUUsage)
                    )
                    .foregroundStyle(by: .value("Métrica", "CPU"))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Hora", stat.timestamp),
                        y: .value("Uso (%)", stat.memoryUsagePercentage)
                    )
                    .foregroundStyle(by: .value("Métrica", "Memória"))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(minHeight: 240)
            }

            if let last = history.last {
                HStack(spacing: 24) {
                    Label("\(Int(last.totalCPUUsage))% CPU", systemImage: "cpu")
                    Label("\(Int(last.memoryUsagePercentage))% memória", systemImage: "memorychip")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
