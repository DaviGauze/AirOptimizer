import Foundation

/// Erros possíveis ao acionar o `purge` de memória inativa do macOS.
enum MemoryPurgerError: LocalizedError {
    case authorizationDenied
    case purgeFailed(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Quick Boost precisa de autenticação de administrador para liberar memória inativa."
        case .purgeFailed(let status, let output):
            return "Falha ao liberar memória (status \(status)): \(output)"
        }
    }
}

/// Aciona o utilitário `/usr/sbin/purge` do macOS, que força o kernel a
/// descartar páginas de memória inativas/em cache (o mesmo mecanismo usado
/// por ferramentas de "memory cleaner") sem encerrar nenhum processo.
///
/// `purge` exige privilégios de root, então rodamos via `osascript ... with
/// administrator privileges`, que exibe o diálogo de autenticação nativo do
/// macOS — não fechamos apps para "liberar memória" porque isso quebraria a
/// experiência do usuário; o objetivo do Quick Boost é aliviar pressão de
/// memória mantendo tudo aberto.
enum MemoryPurger {
    static func purge() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "do shell script \"/usr/sbin/purge\" with administrator privileges"
        ]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if output.contains("User canceled") {
                throw MemoryPurgerError.authorizationDenied
            }
            throw MemoryPurgerError.purgeFailed(status: task.terminationStatus, output: output)
        }
    }
}
