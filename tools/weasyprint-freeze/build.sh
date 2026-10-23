#!/usr/bin/env bash
# Build weasyprint 1-file exe (Linux/macOS chay truc tiep; Windows chay tren windows runner -> .exe)
# - Linux/macOS: can libpango/libcairo cua he thong luc chay.
# - Windows: can GTK/Pango DLL luc dong goi — script tu tim MSYS2 mingw64 va
#   --add-binary toan bo chuoi DLL (glib/pango/cairo/fontconfig/freetype...)
#   vao onefile de may nguoi dung khong can cai GTK rieng.
set -euo pipefail
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
if [ -f .venv/Scripts/activate ]; then . .venv/Scripts/activate; else . .venv/bin/activate; fi
pip install -q --upgrade pip weasyprint pyinstaller

EXTRA=()
MSYS_BIN=""
for d in /c/msys64/mingw64/bin /msys64/mingw64/bin; do
  [ -d "$d" ] && MSYS_BIN="$d" && break
done
if [ -n "$MSYS_BIN" ]; then
  echo "Phat hien MSYS2 mingw64: $MSYS_BIN — dong kem DLL GTK vao onefile"
  DLLS="libglib-2.0-0.dll libgobject-2.0-0.dll libgio-2.0-0.dll libgmodule-2.0-0.dll
        libpango-1.0-0.dll libpangocairo-1.0-0.dll libpangoft2-1.0-0.dll libpangowin32-1.0-0.dll
        libcairo-2.dll libcairo-gobject-2.dll libfontconfig-1.dll libfreetype-6.dll
        libharfbuzz-0.dll libffi-8.dll libintl-8.dll libiconv-2.dll zlib1.dll
        libpng16-16.dll libexpat-1.dll libpixman-1-0.dll libfribidi-0.dll
        libthai-0.dll libdatrie-1.dll libgraphite2.dll libbrotlidec.dll
        libbrotlicommon.dll libzstd.dll libbz2-1.dll libpcre2-8-0.dll
        libgdk_pixbuf-2.0-0.dll libjpeg-8.dll libtiff-6.dll libwebp-7.dll liblzma-5.dll"
  for dll in $DLLS; do
    [ -f "$MSYS_BIN/$dll" ] && EXTRA+=(--add-binary "$MSYS_BIN/$dll;.")
  done
  echo "Da them ${#EXTRA[@]} tuy chon --add-binary"
fi

pyinstaller --noconfirm --onefile --name weasyprint \
  --collect-all weasyprint --collect-all pydyf --collect-all fontTools \
  --collect-all pyphen --collect-all PIL \
  "${EXTRA[@]}" \
  entry.py
echo "OK: dist/weasyprint"
