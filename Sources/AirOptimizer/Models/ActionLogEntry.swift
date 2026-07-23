import Foundation

/// Tipo de ação registrada no histórico de auditoria do app.
enum ActionType: String, Codable {
    case processKilled
    case killBlocked
    case quickBoost
    case performanceModeToggled
    case memoryWarning
    case zombieDetected
}

/// Entrada imutável de log usada para auditoria de ações destrutivas
/// (ex.: qual processo foi encerrado, quando, e por qual sinal).
///
/// Persistida via `ActionLogger` em `UserDefaults` (ver TODO em ActionLogger
/// para migração futura a Core Data caso o histórico cresça muito).
struct ActionLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: ActionType
    let processName: String
    let processID: Int32
    let detail: String

    init(type: ActionType, processName: String, processID: Int32, detail: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.processName = processName
        self.processID = processID
        self.detail = detail
    }
}
