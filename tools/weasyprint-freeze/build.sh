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
# Tren Windows ma khong thay MSYS2 mingw64 thi fail ngay tai day, dung de
# freeze ra exe thieu DLL roi moi do o buoc kiem chung PATH sach.
if [ -z "$MSYS_BIN" ] && { [ "${RUNNER_OS:-}" = "Windows" ] || uname -s | grep -qiE 'mingw|msys'; }; then
  echo "LOI: khong tim thay MSYS2 mingw64/bin — khong the dong DLL GTK vao onefile" >&2
  exit 1
fi
if [ -n "$MSYS_BIN" ]; then
  echo "Phat hien MSYS2 mingw64: $MSYS_BIN — dong kem DLL GTK vao onefile"
  # Danh sach co dinh (van giu de phong DLL nap bang dlopen ma ldd khong thay).
  # Bai hoc vong v1.0.2: danh sach cu thieu 3 DLL runtime cua mingw ma MOI DLL
  # mingw deu phu thuoc — libwinpthread-1.dll, libgcc_s_seh-1.dll, libstdc++-6.dll
  # (+ libssp-0.dll neu toolchain co) — nen exe freeze xong van gãy ngay khi chay
  # voi PATH sach (chi System32), du cac DLL pango/cairo da duoc dong kem.
  DLLS="libglib-2.0-0.dll libgobject-2.0-0.dll libgio-2.0-0.dll libgmodule-2.0-0.dll
        libpango-1.0-0.dll libpangocairo-1.0-0.dll libpangoft2-1.0-0.dll libpangowin32-1.0-0.dll
        libcairo-2.dll libcairo-gobject-2.dll libfontconfig-1.dll libfreetype-6.dll
        libharfbuzz-0.dll libffi-8.dll libintl-8.dll libiconv-2.dll zlib1.dll
        libpng16-16.dll libexpat-1.dll libpixman-1-0.dll libfribidi-0.dll
        libthai-0.dll libdatrie-1.dll libgraphite2.dll libbrotlidec.dll
        libbrotlicommon.dll libzstd.dll libbz2-1.dll libpcre2-8-0.dll
        libgdk_pixbuf-2.0-0.dll libjpeg-8.dll libtiff-6.dll libwebp-7.dll liblzma-5.dll
        libwinpthread-1.dll libgcc_s_seh-1.dll libstdc++-6.dll libssp-0.dll"
  declare -A SEEN=()
  for dll in $DLLS; do
    if [ -f "$MSYS_BIN/$dll" ]; then
      EXTRA+=(--add-binary "$MSYS_BIN/$dll;.")
      SEEN["$dll"]=1
    else
      echo "  (bo qua, khong co trong mingw64/bin: $dll)"
    fi
  done
  # Bao dong phu thuoc de quy bang ldd: bat ca DLL doi ten theo version
  # (vd libffi-7/libffi-8, libintl-8/libintl-9) va DLL runtime ma danh sach
  # co dinh co the sot trong tuong lai. Chi lay file nam trong mingw64/bin,
  # bo qua DLL he thong Windows.
  if command -v ldd >/dev/null 2>&1; then
    echo "Tinh bao dong DLL bang ldd tu cac DLL goc..."
    QUEUE="libpango-1.0-0.dll libpangocairo-1.0-0.dll libcairo-2.dll libfontconfig-1.dll libglib-2.0-0.dll libgobject-2.0-0.dll libgio-2.0-0.dll libgdk_pixbuf-2.0-0.dll"
    declare -A VISITED=()
    while [ -n "$QUEUE" ]; do
      cur="${QUEUE%% *}"; QUEUE="${QUEUE#* }"; [ "$cur" = "$QUEUE" ] && QUEUE=""
      [ -n "${VISITED["$cur"]:-}" ] && continue
      VISITED["$cur"]=1
      [ -f "$MSYS_BIN/$cur" ] || continue
      while IFS= read -r line; do
        dep_path="$(printf '%s' "$line" | sed -n 's/.*=> *\([^ ]*\).*/\1/p')"
        case "$dep_path" in
          "$MSYS_BIN"/* | /c/msys64/mingw64/bin/* | /msys64/mingw64/bin/* | /mingw64/bin/*)
            dep_name="$(basename "$dep_path")"
            if [ -z "${SEEN["$dep_name"]:-}" ]; then
              EXTRA+=(--add-binary "$dep_path;.")
              SEEN["$dep_name"]=1
              echo "  + ldd: $dep_name"
            fi
            [ -z "${VISITED["$dep_name"]:-}" ] && QUEUE="$QUEUE $dep_name"
            ;;
        esac
      done < <(ldd "$MSYS_BIN/$cur" 2>/dev/null || true)
    done
  else
    echo "  (khong co ldd — chi dung danh sach co dinh)"
  fi
  echo "Tong cong $((${#EXTRA[@]} / 2)) DLL duoc dong vao onefile"
  if [ "${#EXTRA[@]}" -eq 0 ]; then
    echo "LOI: khong dong duoc DLL nao — dung freeze de tranh exe thieu DLL" >&2
    exit 1
  fi
fi

pyinstaller --noconfirm --onefile --name weasyprint \
  --collect-all weasyprint --collect-all pydyf --collect-all fontTools \
  --collect-all pyphen --collect-all PIL \
  "${EXTRA[@]}" \
  entry.py
echo "OK: dist/weasyprint"
