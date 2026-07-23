import Foundation
import IOKit

/// Lê a temperatura da CPU via SMC (System Management Controller) do
/// macOS — a mesma técnica usada por apps como iStat Menus, TG Pro ou
/// `osx-cpu-temp`, já que a Apple não expõe temperatura por API pública.
///
/// As chaves de temperatura da SMC não são documentadas e variam por
/// geração de chip. Em Apple Silicon (testado em M1) os núcleos
/// "performance" expõem `Tp1a`…`Tp9a`; em Intel a chave clássica de
/// proximidade da CPU é `TC0P`. Nenhuma combinação é garantida em todo
/// hardware/versão do macOS — por isso a API é opcional e falha em
/// silêncio (retorna `nil`) em vez de travar o app.
final class SMCReader {
    static let shared = SMCReader()

    /// Núcleos "performance" do Apple Silicon — nem todo índice existe em
    /// todo chip (ex.: M1 base não tem `Tp1a`/`Tp6a`), por isso lemos todos
    /// os candidatos e ignoramos os que falham.
    private static let appleSiliconKeys = [
        "Tp1a", "Tp2a", "Tp3a", "Tp4a", "Tp5a", "Tp6a", "Tp7a", "Tp8a", "Tp9a"
    ]

    /// Chave clássica de proximidade da CPU em Macs Intel.
    private static let intelFallbackKeys = ["TC0P", "TC0D", "TC0E", "TC0F"]

    private let connection: io_connect_t?

    private init() {
        var conn: io_connect_t = 0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            connection = nil
            return
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        connection = result == kIOReturnSuccess ? conn : nil
    }

    deinit {
        if let connection {
            IOServiceClose(connection)
        }
    }

    /// Temperatura da CPU em graus Celsius, ou `nil` se a SMC não expôs
    /// nenhuma das chaves conhecidas neste Mac.
    func cpuTemperatureCelsius() -> Double? {
        guard connection != nil else { return nil }

        let performanceReadings = Self.appleSiliconKeys.compactMap { readTemperature(key: $0) }
        if !performanceReadings.isEmpty {
            return performanceReadings.reduce(0, +) / Double(performanceReadings.count)
        }

        for key in Self.intelFallbackKeys {
            if let value = readTemperature(key: key) { return value }
        }

        return nil
    }

    // MARK: - SMC low-level

    private func readTemperature(key: String) -> Double? {
        guard let connection else { return nil }

        var infoInput = SMCParamStruct()
        infoInput.key = Self.fourCharCode(key)
        infoInput.data8 = Selector.getKeyInfo.rawValue
        guard let info = Self.call(connection, infoInput), info.result == 0 else { return nil }

        let dataType = Self.string(fromCode: info.keyInfo.dataType)

        var valueInput = SMCParamStruct()
        valueInput.key = Self.fourCharCode(key)
        valueInput.keyInfo.dataSize = info.keyInfo.dataSize
        valueInput.data8 = Selector.readKey.rawValue
        guard let value = Self.call(connection, valueInput), value.result == 0 else { return nil }

        let bytes = value.bytes
        let temperature: Double?
        switch dataType {
        case "sp78":
            let intValue = (Int(bytes.0) * 256 + Int(bytes.1)) >> 2
            temperature = Double(intValue) / 64.0
        case "flt ":
            let rawBytes: [UInt8] = [bytes.0, bytes.1, bytes.2, bytes.3]
            temperature = Double(rawBytes.withUnsafeBytes { $0.load(as: Float32.self) })
        default:
            temperature = nil
        }

        // Sensores desligados/não calibrados costumam reportar 0 ou valores
        // absurdos; filtra para a faixa plausível de temperatura de CPU.
        guard let temperature, temperature > 0, temperature < 150 else { return nil }
        return temperature
    }

    private enum Selector: UInt8 {
        case readKey = 5
        case getKeyInfo = 9
    }

    /// Layout replicado byte-a-byte da struct `SMCKeyData_t` usada pelo
    /// kernel driver da AppleSMC (mesmo layout usado por SMCKit/osx-cpu-temp).
    /// O campo `padding` existe porque o compilador C insere 2 bytes aqui
    /// para alinhar `data32` em 4 bytes — omiti-lo desalinha todo o resto
    /// da struct e faz toda leitura falhar silenciosamente.
    private struct SMCParamStruct {
        struct Version { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct PLimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
        struct KeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

        var key: UInt32 = 0
        var vers = Version()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    /// Selector `kSMCHandleYPCEvent` do kernel driver — único ponto de
    /// entrada da AppleSMC; a operação real (ler chave, ler info, etc.) é
    /// escolhida pelo campo `data8` dentro da struct, não pelo selector.
    private static func call(_ connection: io_connect_t, _ input: SMCParamStruct) -> SMCParamStruct? {
        var inputStruct = input
        var outputStruct = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = withUnsafeMutablePointer(to: &outputStruct) { outPtr -> kern_return_t in
            withUnsafePointer(to: &inputStruct) { inPtr -> kern_return_t in
                IOConnectCallStructMethod(connection, 2, inPtr, inputSize, outPtr, &outputSize)
            }
        }
        guard result == kIOReturnSuccess else { return nil }
        return outputStruct
    }

    private static func fourCharCode(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }

    private static func string(fromCode code: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff), UInt8(code & 0xff)
        ]
        return String(bytes: chars, encoding: .ascii) ?? ""
    }
}
