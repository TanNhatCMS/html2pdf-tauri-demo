#!/usr/bin/env bash
# Build weasyprint 1-file exe (Linux/macOS chay truc tiep; Windows chay tren windows runner -> .exe)
# Yeu cau he thong co libpango/libcairo (Linux/macOS) hoac GTK runtime (Windows) - xem README repo.
set -euo pipefail
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
. .venv/bin/activate
pip install -q --upgrade pip weasyprint pyinstaller
pyinstaller --noconfirm --onefile --name weasyprint \
  --collect-all weasyprint --collect-all pydyf --collect-all fontTools \
  --collect-all pyphen --collect-all PIL \
  entry.py
echo "OK: dist/weasyprint"
