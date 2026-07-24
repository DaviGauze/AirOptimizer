#!/usr/bin/env swift
// Gera Resources/AppIcon-1024.png: um ícone minimalista para o AirOptimizer —
// fundo flat (squircle, seguindo o grid de ícones da Apple, sem gradiente)
// com um único glifo simples ao centro, no estilo dos ícones utilitários da
// própria Apple (Lembretes, Notas, etc.: uma cor sólida, um símbolo, zero
// enfeite).
//
// A partir desse PNG mestre, `Scripts/build_icns.sh` gera o .iconset e o
// .icns final. Mantido como script separado (em vez de gerar o PNG só uma
// vez manualmente) para o ícone ser reproduzível/versionável via código, não
// um binário opaco sem origem.

import AppKit

let canvasSize: CGFloat = 1024
let rect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Sem contexto de desenho")
}

// Squircle seguindo aproximadamente o grid de ícones da Apple (macOS Big
// Sur+): raio de canto ~22% do lado do canvas.
let cornerRadius = canvasSize * 0.2237
let backgroundPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

ctx.saveGState()
ctx.addPath(backgroundPath)
ctx.clip()

// Cor sólida única, sem gradiente — o que diferencia ícones "Apple-style"
// (Lembretes, Notas, Calculadora) dos ícones com gradiente/sombra/textura
// mais comuns em apps de terceiros.
NSColor(calibratedRed: 0.20, green: 0.09, blue: 0.30, alpha: 1.0).setFill()
ctx.fill(rect)
ctx.restoreGState()

// Símbolo central: um único glifo simples (raio — desempenho/boost), branco
// puro, sem peso extra nem elementos decorativos.
let symbolConfig = NSImage.SymbolConfiguration(pointSize: canvasSize * 0.46, weight: .medium)
guard let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) else {
    fatalError("Símbolo SF Symbols não encontrado")
}

let tintedSymbol = NSImage(size: symbol.size)
tintedSymbol.lockFocus()
NSColor.white.set()
let symbolRect = CGRect(origin: .zero, size: symbol.size)
symbol.draw(in: symbolRect)
symbolRect.fill(using: .sourceAtop)
tintedSymbol.unlockFocus()

let symbolSize = tintedSymbol.size
let symbolOrigin = CGPoint(
    x: (canvasSize - symbolSize.width) / 2,
    y: (canvasSize - symbolSize.height) / 2 - canvasSize * 0.02
)
tintedSymbol.draw(at: symbolOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Falha ao gerar PNG")
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon-1024.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Ícone gerado em \(outputPath)")
