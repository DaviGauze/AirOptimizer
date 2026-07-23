import Foundation
import Combine

/// Serviço responsável por registrar e persistir o histórico de ações
/// destrutivas/relevantes realizadas pelo usuário (kills, boosts, avisos).
///
/// Persistência via `UserDefaults` + `Codable`. É intencionalmente simples:
/// o volume esperado de entradas é baixo (ações manuais do usuário), então
/// Core Data seria over-engineering por ora.
///
/// TODO: migrar para Core Data ou SQLite se o histórico crescer além de
/// alguns milhares de entradas, ou se for necessário fazer buscas complexas.
final class ActionLogger: ObservableObject {
    static let shared = ActionLogger()

    @Published private(set) var entries: [ActionLogEntry] = []

    private let storageKey = "com.airoptimizer.actionLog"
    private let maxEntries = 2000
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func log(_ entry: ActionLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    /// Exporta o log completo como texto legível para o usuário salvar em disco.
    func exportAsText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] \(entry.type.rawValue) — " +
            "\(entry.processName) (PID \(entry.processID)): \(entry.detail)"
        }.joined(separator: "\n")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ActionLogEntry].self, from: data) else {
            return
        }
        entries = decoded
    }
}
