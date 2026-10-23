# HTML → PDF Demo — Tauri 2 + Next.js standalone + WeasyPrint sidecar

App demo đúng kiến trúc đã chốt:

- **Backend Tauri (Rust)** khởi động **bun runtime** (sidecar đóng gói sẵn
  `src-tauri/binaries/bun-<triple>`) để chạy **Next.js standalone**
  (`resources/web/standalone`: `server.js` + `.next` + `node_modules` rút gọn).
- **Frontend Next.js** là một server local trên `127.0.0.1`, phục vụ giao diện
  demo: chọn thư mục chứa bộ hoá đơn (invoice.html + js + ảnh), log debug có
  mốc thời gian, đo thời gian xử lý, gọi sidecar qua **plugin-shell**.
- **2 exe công cụ tải online ở lần chạy đầu** (không đóng gói sẵn):
  `invoice-pdf` (tiền xử lý + điều phối, Bun compile) và `weasyprint`
  (engine HTML→PDF). App tải từ GitHub Release của repo này, **kiểm tra
  SHA-256** theo file `.sha256` đi kèm, lưu vào `app_data_dir/bin`, chen thư
  mục đó vào `PATH` và đặt `WEASYPRINT_PATH`. Tiến độ tải phát sự kiện
  `tools://progress` về FE.

## Chọn port "không bao giờ trùng" — cơ chế thật

Không tồn tại dải port nào đảm bảo tuyệt đối không trùng. App dùng tổ hợp:

1. Quét dải dynamic IANA **49300–49499** (điểm bắt đầu xáo trộn), **bind-test
   từng port** — chỉ lấy port bind được thật.
2. Spawn server xong **health-check bằng token** tối đa ~8 giây; tiến trình
   chết sớm hoặc không khoẻ → kill, thử port khác (tối đa 5 lần).
3. Dự phòng cuối: bind port 0 để OS cấp port ephemeral đang trống.

Lưu ý đã kiểm chứng: `server.js` của Next **bỏ qua PORT=0** (coi 0 là falsy,
rơi về 3000) nên không thể "để OS tự chọn rồi đọc lại port" với Next —
bind-test ở tầng Rust là bắt buộc.

## Chỉ Tauri app mới truy cập được server local

- Server chỉ bind `127.0.0.1` (không `0.0.0.0`).
- Mỗi lần chạy, Rust sinh **token phiên 32 byte ngẫu nhiên**, truyền cho Next
  qua env `APP_SESSION_TOKEN`. Middleware của FE (`apps/web/middleware.ts`)
  chỉ cho qua khi có một trong: header `x-app-token` (Rust health-check),
  cookie `app_session` (sau bootstrap), hoặc tham số bootstrap
  `?__app_token=` dùng **một lần** lúc mở cửa sổ để set cookie rồi redirect
  xoá khỏi URL. Mọi truy cập khác — kể cả trình duyệt/app khác trên cùng máy
  gõ đúng `127.0.0.1:<port>` — nhận **401**.
- Luồng chuyển PDF đi qua IPC của plugin-shell (không qua mạng) và bị giới
  hạn bởi capability scope: chỉ `invoice-pdf` (qua PATH) và sidecar `bun`.

## Vì sao weasyprint.exe không build bằng Bun

WeasyPrint là **Python** (Pango/Cairo/fontTools qua cffi) — Bun chỉ compile
được JS/TS. Kết quả "1 file exe chạy như sidecar" đạt bằng **PyInstaller
freeze** (`tools/weasyprint-freeze/`): Windows ra `.exe` thật, Linux/macOS
ra binary tương đương, CLI giữ nguyên của WeasyPrint. Bản Linux đã build và
chạy kiểm chứng tại máy phát triển: `weasyprint --version` → 70.0, chuyển
hoá đơn mẫu ra PDF 1 trang A4 đúng dữ liệu, ~3,5 giây kể cả cold start.
Giới hạn còn lại: bản freeze cần thư viện hệ thống Pango/Cairo ở máy đích
(Linux/macOS thường có sẵn; Windows phải kèm DLL GTK — job CI Windows đã có
bước MSYS2 và để `continue-on-error` kèm ghi chú, cần hoàn thiện khi có máy
Windows thật để đối chứng).

## Cấu trúc

```
apps/web/                 Next.js (output: 'standalone'), middleware token gate
src-tauri/                Tauri 2: lib.rs (port/token/tải tool/spawn), capabilities
tools/invoice-pdf/        Sidecar Bun: src/cli.mjs + src/convert.mjs
tools/weasyprint-freeze/  PyInstaller: entry.py + build.sh
scripts/                  prepare-resources.sh, build-tools.sh
.github/workflows/        release.yml — chạy khi push tag v*
samples/hoadon/           Bộ hoá đơn mẫu để thử (không commit nội dung)
```

## Chạy thử từng phần (không cần build Tauri)

```bash
# FE standalone + token gate
cd apps/web && bun install && bun --bun run build
cp -r .next/static .next/standalone/.next/static
cd .next/standalone
PORT=49300 HOSTNAME=127.0.0.1 APP_SESSION_TOKEN=test123 bun server.js
#  http://127.0.0.1:49300/                    -> 401
#  http://127.0.0.1:49300/?__app_token=test123 -> vào được (set cookie)

# Chuỗi 2 exe (đặt cạnh nhau như thư mục bin sau khi app tải về)
tools/invoice-pdf/binaries/invoice-pdf-* samples/hoadon /tmp/out.pdf \
  --weasyprint tools/weasyprint-freeze/dist/weasyprint
```

## Phát hành

1. `RELEASE_BASE` trong `src-tauri/src/lib.rs` đã trỏ sẵn tới release
   `tools-v1.0.0` của repo này. Không cần tạo tag công cụ thủ công: khi push
   tag bản app (vd `v1.0.1`), job `publish-tools` của CI tự tạo release
   công khai `tools-v1.0.0` và gắn `invoice-pdf-<triple>[.exe]`,
   `weasyprint-<triple>[.exe]` + `.sha256` của cả 3 hệ vào đó.
2. Push tag bản app: workflow Release build Tauri cho Windows (user chốt 2026-10-24 chỉ build Windows; muốn mở lại Linux/macOS thì thêm entry vào matrix của job `tools`/`app` trong release.yml)
   và tạo Release **draft** (kèm bộ cài) để duyệt trước khi công khai.
   Release công cụ ở bước 1 là public ngay vì app cần tải ẩn danh.

Lưu ý icon: Tauri bắt buộc icon nguồn phải là **RGBA** — bản v1.0.0 fail cả
3 hệ ở `generate_context!` chỉ vì icon.png ban đầu là RGB. Bộ icon chuẩn
(32/128/256 + .icns + .ico) đã sinh bằng `tauri icon` từ icon.png RGBA
1024×1024 và commit sẵn trong `src-tauri/icons/`.

## Trạng thái kiểm chứng (2026-10-23, máy phát triển Linux)

| Phần | Trạng thái |
|---|---|
| Next standalone build + chạy bằng bun runtime | ✅ chạy thật, trang 200 |
| Token gate (401 / header / bootstrap cookie) | ✅ test bằng curl đủ 5 ca |
| Chọn port bind-test trong dải dynamic | ✅ mô phỏng đúng thuật toán của lib.rs |
| invoice-pdf exe (Bun compile) `--ping` + chuyển PDF | ✅ |
| weasyprint freeze (PyInstaller, Linux) + chuỗi 2 exe | ✅ PDF 1 trang A4, đúng tổng tiền |
| `scripts/prepare-resources.sh` | ✅ chạy thật trên máy này |
| src-tauri (`cargo build`) | ✅ đã cài webkit2gtk-4.1-dev lên VM (đường .deb) và build thật: `cargo check` sạch + `cargo build` link thành công ra binary |
| GitHub Actions workflow | ⚠️ Đã chạy với tag v1.0.0: 3 job tools ✅; 3 job app fail vì icon RGB (đã sửa — chờ tag mới chạy lại) |
| Freeze weasyprint cho Windows | ⚠️ scaffold trong CI, chưa đối chứng máy Windows |
