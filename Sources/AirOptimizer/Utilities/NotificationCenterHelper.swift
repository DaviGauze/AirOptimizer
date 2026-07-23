import Foundation
import UserNotifications

/// Encapsula o envio de notificações locais (banner do macOS), isolando o
/// resto do app da API `UserNotifications` e de sua permissão assíncrona.
enum NotificationCenterHelper {

    /// Deve ser chamado uma vez na inicialização do app (ver `AirOptimizerApp`).
    ///
    /// `UNUserNotificationCenter` exige um bundle `.app` válido (com
    /// `Info.plist` e bundle identifier); ao rodar via `swift run`/`swift build`
    /// sem empacotamento, `bundleIdentifier` é `nil` e a API lança uma
    /// exceção Objective-C fatal. Este guard evita o crash em desenvolvimento;
    /// em um `.app` produzido pelo Xcode o bundle identifier está sempre presente.
    static func requestAuthorizationIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil else {
            print("AirOptimizer: notificações desabilitadas (executando fora de um bundle .app).")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                print("AirOptimizer: falha ao solicitar autorização de notificações — \(error.localizedDescription)")
            }
        }
    }

    static func postMemoryWarning(percentage: Double) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "Memória alta"
        content.body = String(format: "O uso de memória do sistema atingiu %.0f%%. Considere usar o Quick Boost.", percentage)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.airoptimizer.memoryWarning.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
