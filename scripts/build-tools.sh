#!/usr/bin/env bash
# Build 2 exe cong cu cho nen tang hien tai + tao file .sha256 di kem,
# dat vao dist-tools/ de tai len GitHub Release (khop asset_triple trong src-tauri).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist-tools"; mkdir -p "$OUT"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  TRIPLE=x86_64-unknown-linux-gnu; EXT="" ;;
  Darwin-arm64)  TRIPLE=aarch64-apple-darwin; EXT="" ;;
  Darwin-x86_64) TRIPLE=x86_64-apple-darwin; EXT="" ;;
  MINGW*-x86_64|MSYS*-x86_64) TRIPLE=x86_64-pc-windows-msvc; EXT=".exe" ;;
  *) echo "nen tang chua ho tro" >&2; exit 1 ;;
esac

# 1) invoice-pdf bang Bun compile
cd "$ROOT/tools/invoice-pdf"
bun install
case "$TRIPLE" in
  *windows*) bun build src/cli.mjs --compile --target=bun-windows-x64 --outfile "$OUT/invoice-pdf-$TRIPLE.exe" ;;
  *darwin*)  bun build src/cli.mjs --compile --outfile "$OUT/invoice-pdf-$TRIPLE" ;;
  *)         bun build src/cli.mjs --compile --target=bun-linux-x64 --outfile "$OUT/invoice-pdf-$TRIPLE" ;;
esac

# 2) weasyprint freeze bang PyInstaller (khong the bun build vi no la Python)
bash "$ROOT/tools/weasyprint-freeze/build.sh"
cp "$ROOT/tools/weasyprint-freeze/dist/weasyprint$EXT" "$OUT/weasyprint-$TRIPLE$EXT" 2>/dev/null \
  || cp "$ROOT/tools/weasyprint-freeze/dist/weasyprint" "$OUT/weasyprint-$TRIPLE$EXT"

# 3) sha256 kem theo tung file
cd "$OUT"
for f in invoice-pdf-* weasyprint-*; do
  [ -f "$f" ] && [ "${f##*.}" != "sha256" ] && sha256sum "$f" > "$f.sha256"
done
ls -lh "$OUT"
