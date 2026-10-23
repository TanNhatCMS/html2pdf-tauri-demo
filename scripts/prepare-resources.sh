#!/usr/bin/env bash
# Chuan bi tai nguyen cho Tauri bundle:
#  1) build Next standalone (bang bun) + copy .next/static vao dung cho
#  2) copy thu muc standalone -> src-tauri/resources/web/standalone
#  3) copy bun runtime cua may build -> src-tauri/binaries/bun-<triple> (sidecar)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/apps/web"
bun --bun run build
SA=.next/standalone
cp -r .next/static "$SA/.next/static"
[ -d public ] && cp -r public "$SA/public" || true
rm -rf "$ROOT/src-tauri/resources/web/standalone"
mkdir -p "$ROOT/src-tauri/resources/web"
cp -r "$SA" "$ROOT/src-tauri/resources/web/standalone"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  TRIPLE=x86_64-unknown-linux-gnu ;;
  Darwin-arm64)  TRIPLE=aarch64-apple-darwin ;;
  Darwin-x86_64) TRIPLE=x86_64-apple-darwin ;;
  MINGW*-x86_64|MSYS*-x86_64) TRIPLE=x86_64-pc-windows-msvc ;;
  *) echo "khong nhan dien duoc nen tang build" >&2; exit 1 ;;
esac
BUN_BIN="$(command -v bun)"
mkdir -p "$ROOT/src-tauri/binaries"
if [ "$TRIPLE" = "x86_64-pc-windows-msvc" ]; then
  cp "$BUN_BIN" "$ROOT/src-tauri/binaries/bun-$TRIPLE.exe"
else
  cp "$BUN_BIN" "$ROOT/src-tauri/binaries/bun-$TRIPLE"
  chmod +x "$ROOT/src-tauri/binaries/bun-$TRIPLE"
fi
echo "OK: resources/web/standalone + binaries/bun-$TRIPLE"
