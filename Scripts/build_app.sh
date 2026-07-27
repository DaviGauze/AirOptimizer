#!/bin/bash
# Empacota o executável do AirOptimizer em um bundle .app de verdade.
#
# `swift build` sozinho produz um binário "cru" sem Info.plist — suficiente
# para desenvolvimento rápido, mas insuficiente para recursos que dependem de
# um bundle registrado no macOS (notificações, e principalmente automação via
# AppleScript, que precisa do Info.plist apontar para o AirOptimizer.sdef).
#
# Uso:
#   ./Scripts/build_app.sh          # build debug (padrão)
#   ./Scripts/build_app.sh release  # build release
set -euo pipefail

CONFIG="${1:-debug}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AirOptimizer"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"

echo "==> Compilando ($CONFIG)…"
if [ "$CONFIG" = "release" ]; then
    swift build -c release --package-path "$ROOT_DIR"
    BINARY_PATH="$ROOT_DIR/.build/release/$APP_NAME"
else
    swift build --package-path "$ROOT_DIR"
    BINARY_PATH="$ROOT_DIR/.build/debug/$APP_NAME"
fi

echo "==> Montando $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AirOptimizer.sdef" "$APP_BUNDLE/Contents/Resources/AirOptimizer.sdef"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Ícones customizados (CPU/RAM/temperatura) usados na barra de resumo do
# Dashboard — ver Utilities/BundledIcon.swift.
mkdir -p "$APP_BUNDLE/Contents/Resources/Icons"
cp "$ROOT_DIR/Resources/Icons"/*.png "$APP_BUNDLE/Contents/Resources/Icons/"

# Copia toda pasta de localização (*.lproj) encontrada em Resources/ — assim,
# adicionar um novo idioma (ex.: en.lproj) não exige mexer neste script.
for lproj in "$ROOT_DIR"/Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    name="$(basename "$lproj")"
    mkdir -p "$APP_BUNDLE/Contents/Resources/$name"
    cp "$lproj"/*.strings "$APP_BUNDLE/Contents/Resources/$name/" 2>/dev/null || true
done

echo "==> Assinando ad-hoc (necessário para o Gatekeeper/Launch Services aceitar o bundle)"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Registrando no Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE"

# O cache de ícones do macOS (iconservicesd) é notoriamente teimoso: sem
# "tocar" o bundle e reiniciar o Dock, o ícone genérico antigo às vezes
# persiste mesmo depois de registrar de novo no Launch Services.
touch "$APP_BUNDLE"
killall Dock >/dev/null 2>&1 || true

echo "==> Pronto: $APP_BUNDLE"
echo "    Abrir:        open '$APP_BUNDLE'"
echo "    Testar AppleScript: osascript -e 'tell application \"$APP_NAME\" to quick boost'"
