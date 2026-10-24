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
MSYS_SRC="khong tim thay"
# setup-msys2 KHONG cai mac dinh vao C:\msys64: neu khong truyen location,
# action cai vao thu muc tam cua runner (vd D:\a\_temp\msys64) va tra ve qua
# output msys2-location. Workflow phai truyen output do qua env MSYS2_LOCATION
# (xem .github/workflows/release.yml). Vong v1.0.3 fail nhanh o buoc freeze
# chinh vi ban cu chi thu /c/msys64 va /msys64, khong thay thi fail-loud.
if [ -n "${MSYS2_LOCATION:-}" ]; then
  loc="${MSYS2_LOCATION}"
  if command -v cygpath >/dev/null 2>&1; then
    loc="$(cygpath -u "$loc")"
  else
    case "$loc" in
      [A-Za-z]:[\\/]*)
        drive="$(printf '%s' "$loc" | cut -c1 | tr 'A-Z' 'a-z')"
        rest="$(printf '%s' "$loc" | cut -c3- | tr '\\' '/')"
        loc="/$drive$rest"
        ;;
    esac
  fi
  if [ -d "$loc/mingw64/bin" ]; then
    MSYS_BIN="$loc/mingw64/bin"
    MSYS_SRC="MSYS2_LOCATION=$MSYS2_LOCATION"
  fi
fi
if [ -z "$MSYS_BIN" ]; then
  for d in /c/msys64/mingw64/bin /msys64/mingw64/bin; do
    [ -d "$d" ] && MSYS_BIN="$d" && MSYS_SRC="duong dan mac dinh $d" && break
  done
fi
echo "MSYS2 mingw64/bin: ${MSYS_BIN:-<khong thay>} (nguon: $MSYS_SRC)"
# Tren Windows ma khong thay MSYS2 mingw64 thi fail ngay tai day, dung de
# freeze ra exe thieu DLL roi moi do o buoc kiem chung PATH sach.
if [ -z "$MSYS_BIN" ] && { [ "${RUNNER_OS:-}" = "Windows" ] || uname -s | grep -qiE 'mingw|msys'; }; then
  echo "LOI: khong tim thay MSYS2 mingw64/bin (da thu MSYS2_LOCATION, /c/msys64, /msys64) — khong the dong DLL GTK vao onefile" >&2
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
  # co dinh co the sot trong tuong lai. Giai quyet theo basename trong
  # mingw64/bin (xem ghi chu trong vong lap duoi).
  # Dung ldd cua chinh MSYS2 (<msys>/usr/bin/ldd) thay vi ldd cua Git Bash:
  # hai bo MSYS2 nay co cay /mingw64 khac nhau, duong dan ldd in ra cua
  # ben nay khong khop ben kia. Khong co thi dung ldd tren PATH.
  LDD_BIN=""
  # mingw64/bin/../../usr/bin/ldd = <msys>/usr/bin/ldd
  [ -x "$MSYS_BIN/../../usr/bin/ldd" ] && LDD_BIN="$MSYS_BIN/../../usr/bin/ldd"
  if [ -z "$LDD_BIN" ] && command -v ldd >/dev/null 2>&1; then LDD_BIN="ldd"; fi
  echo "ldd: ${LDD_BIN:-<khong co>}"
  if [ -n "$LDD_BIN" ]; then
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
        # Giai quyet theo BASENAME trong mingw64/bin, khong tin duong dan
        # ldd in ra: ldd cua MSYS2 in /mingw64/bin/... (goc cua no), ldd cua
        # Git Bash in duong dan cua Git — ca hai deu co the khac duong dan
        # that cua MSYS_BIN. Chi can file cung ten co trong mingw64/bin thi
        # lay ban cua MSYS_BIN; DLL he thong (KERNEL32...) khong co trong
        # mingw64/bin nen tu bi loai.
        dep_name="$(basename "$dep_path")"
        if [ -n "$dep_name" ] && [ -f "$MSYS_BIN/$dep_name" ]; then
          if [ -z "${SEEN["$dep_name"]:-}" ]; then
            EXTRA+=(--add-binary "$MSYS_BIN/$dep_name;.")
            SEEN["$dep_name"]=1
            echo "  + ldd: $dep_name"
          fi
          if [ -z "${VISITED["$dep_name"]:-}" ]; then
            QUEUE="$QUEUE $dep_name"
          fi
        fi
      done < <("$LDD_BIN" "$MSYS_BIN/$cur" 2>/dev/null || true)
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
