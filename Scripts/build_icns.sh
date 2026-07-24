#!/bin/bash
# Gera Resources/AppIcon.icns a partir de Resources/AppIcon-1024.png,
# criando todos os tamanhos que o macOS espera num bundle .iconset
# (16pt até 512pt, @1x e @2x) via `sips` e empacotando com `iconutil`.
#
# Rodar de novo sempre que Resources/AppIcon-1024.png mudar (ex.: depois de
# `swift Scripts/generate_icon.swift Resources/AppIcon-1024.png`).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER_PNG="$ROOT_DIR/Resources/AppIcon-1024.png"
ICONSET="$ROOT_DIR/Resources/AppIcon.iconset"
ICNS_OUT="$ROOT_DIR/Resources/AppIcon.icns"

if [ ! -f "$MASTER_PNG" ]; then
    echo "Faltando $MASTER_PNG — rode 'swift Scripts/generate_icon.swift Resources/AppIcon-1024.png' primeiro." >&2
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# tamanho_ponto:nome_arquivo — os pares @1x/@2x que o iconutil exige.
declare -a sizes=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${sizes[@]}"; do
    px="${entry%%:*}"
    name="${entry##*:}"
    sips -z "$px" "$px" "$MASTER_PNG" --out "$ICONSET/$name" >/dev/null
done

rm -f "$ICNS_OUT"
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
rm -rf "$ICONSET"

echo "==> Gerado $ICNS_OUT"
