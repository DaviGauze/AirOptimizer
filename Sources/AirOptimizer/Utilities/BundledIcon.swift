import AppKit

/// Carrega os ícones customizados (CPU/RAM/temperatura) empacotados em
/// `Resources/Icons/` pelo `Scripts/build_app.sh`.
///
/// Só existem quando o app roda como bundle de verdade — em `swift run`
/// (binário cru, sem `Contents/Resources`) `Bundle.main` não os encontra,
/// então retorna `nil` e quem chama cai para um SF Symbol equivalente em vez
/// de travar (mesmo padrão de degradação usado por `SMCReader`/
/// `NotificationCenterHelper` para recursos que dependem do bundle).
enum BundledIcon {
    static func image(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
