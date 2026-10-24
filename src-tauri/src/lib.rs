//! HTML -> PDF Demo (Tauri 2)
//! Kien truc:
//! - FE Next.js chay tu BAN COPY cua standalone dong kem (resources/web/standalone)
//!   sang app_local_data_dir/next-runtime/<BUILD_ID>, do chinh bun runtime
//!   (sidecar dong goi san) spawn, nghe tren 127.0.0.1 o mot
//!   (khong chay truc tiep tu thu muc cai dat: Next ghi cache runtime vao
//!   .next/server/route-cache, ghi vao thu muc cai dat se sot lai sau uninstall).
//!   port trong dai dynamic do Rust chon bang bind-test + xac minh health-check.
//! - 2 exe cong cu (invoice-pdf + weasyprint) KHONG dong goi san: lan chay dau
//!   app tai tu GitHub Release cua repo nay, kiem tra SHA-256, luu vao
//!   app_data_dir/bin. FE goi invoice-pdf qua plugin-shell (ten chuong trinh
//!   giai quyet qua PATH ma Rust da chen bin_dir vao, env WEASYPRINT_PATH tro
//!   toi exe weasyprint vua tai).
//! - Bao mat cong local: chi bind 127.0.0.1 + token phien ngau nhien 32 byte
//!   (env APP_SESSION_TOKEN cho server Next; middleware cua FE chi cho phep
//!   header x-app-token / cookie phien / bootstrap ?__app_token= 1 lan).

use std::collections::HashMap;
use std::io::Write;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use rand::Rng;
use serde::Serialize;
use sha2::{Digest, Sha256};
use tauri::{Emitter, Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;
use tokio::io::AsyncWriteExt;

// TODO: doi thanh repo that khi day len GitHub. Cac asset tren Release phai
// dat ten: invoice-pdf-<triple>[.exe], weasyprint-<triple>[.exe] + moi file
// kem mot file <ten>.sha256 (noi dung: "<hex>  <ten file>").
const RELEASE_BASE: &str =
    "https://github.com/TanNhatCMS/html2pdf-tauri-demo/releases/download/tools-v1.0.0";
const PORT_RANGE: std::ops::RangeInclusive<u16> = 49300..=49499; // dai dynamic IANA 49152-65535

struct AppState {
    next_child: Mutex<Option<CommandChild>>,
}

#[derive(Clone, Serialize)]
struct ProgressPayload {
    file: String,
    downloaded: u64,
    total: u64,
}

fn asset_triple() -> &'static str {
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    {
        "x86_64-pc-windows-msvc"
    }
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        "x86_64-unknown-linux-gnu"
    }
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    {
        "aarch64-apple-darwin"
    }
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    {
        "x86_64-apple-darwin"
    }
}

fn exe_name(base: &str) -> String {
    if cfg!(target_os = "windows") {
        format!("{base}.exe")
    } else {
        base.to_string()
    }
}

fn gen_token() -> String {
    let mut buf = [0u8; 32];
    rand::rng().fill_bytes(&mut buf);
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

/// Chon port dang trong that su: bind thu tung port trong dai dynamic
/// (xao tron diem bat dau), khong duoc thi nho OS cap port ephemeral (bind 0).
/// Khong co dai port nao "khong bao gio trung" ve mat toan hoc — co che dam
/// bao la: bind-test o day + health-check sau khi spawn, thua thi thu port
/// khac (xem start_next_server).
fn pick_free_port() -> Option<u16> {
    let mut rng = rand::rng();
    let span = (PORT_RANGE.end() - PORT_RANGE.start() + 1) as u32;
    let offset = (rng.next_u32() % span) as u16;
    for i in 0..span as u16 {
        let p = PORT_RANGE.start() + (offset + i) % span as u16;
        if TcpListener::bind(("127.0.0.1", p)).is_ok() {
            return Some(p);
        }
    }
    TcpListener::bind(("127.0.0.1", 0))
        .ok()
        .map(|l| l.local_addr().unwrap().port())
}

async fn download_verified(
    app: &tauri::AppHandle,
    url: &str,
    dest: &Path,
    label: &str,
) -> Result<(), String> {
    let client = reqwest::Client::new();
    // 1) tai file .sha256 truoc de co muc kiem tra
    let sha_url = format!("{url}.sha256");
    let sha_text = client
        .get(&sha_url)
        .send()
        .await
        .map_err(|e| format!("tai {sha_url}: {e}"))?
        .error_for_status()
        .map_err(|e| format!("tai {sha_url}: {e}"))?
        .text()
        .await
        .map_err(|e| format!("doc {sha_url}: {e}"))?;
    let expected = sha_text
        .split_whitespace()
        .next()
        .ok_or("file .sha256 rong")?
        .to_lowercase();

    // 2) tai file chinh, vua tai vua bam SHA-256, bao tien do ve FE
    let resp = client
        .get(url)
        .send()
        .await
        .map_err(|e| format!("tai {url}: {e}"))?
        .error_for_status()
        .map_err(|e| format!("tai {url}: {e}"))?;
    let total = resp.content_length().unwrap_or(0);
    let tmp = dest.with_extension("part");
    let mut f = tokio::fs::File::create(&tmp)
        .await
        .map_err(|e| format!("tao file tam: {e}"))?;
    let mut hasher = Sha256::new();
    let mut downloaded: u64 = 0;
    use futures_util::StreamExt;
    let mut stream = resp.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| format!("tai {url}: {e}"))?;
        hasher.update(&chunk);
        f.write_all(&chunk)
            .await
            .map_err(|e| format!("ghi file tam: {e}"))?;
        downloaded += chunk.len() as u64;
        let _ = app.emit(
            "tools://progress",
            ProgressPayload {
                file: label.to_string(),
                downloaded,
                total,
            },
        );
    }
    f.flush().await.ok();
    drop(f);
    let got: String = hasher.finalize().iter().map(|b| format!("{b:02x}")).collect();
    if got != expected {
        let _ = tokio::fs::remove_file(&tmp).await;
        return Err(format!(
            "SHA-256 khong khop cho {label}: expected {expected}, got {got}"
        ));
    }
    tokio::fs::rename(&tmp, dest)
        .await
        .map_err(|e| format!("rename file tai: {e}"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(dest, std::fs::Permissions::from_mode(0o755));
    }
    Ok(())
}

/// Dam bao 2 exe cong cu da co trong app_data_dir/bin; thieu thi tai online.
/// Tra ve duong dan thu muc bin.
async fn ensure_tools(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let bin_dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("bin");
    std::fs::create_dir_all(&bin_dir).map_err(|e| e.to_string())?;
    let triple = asset_triple();
    for tool in ["invoice-pdf", "weasyprint"] {
        let asset = format!("{tool}-{triple}");
        let asset = if cfg!(target_os = "windows") {
            format!("{asset}.exe")
        } else {
            asset
        };
        let local = bin_dir.join(exe_name(tool));
        if local.exists() {
            continue;
        }
        let url = format!("{RELEASE_BASE}/{asset}");
        download_verified(app, &url, &local, tool).await?;
    }
    Ok(bin_dir)
}

async fn health_ok(port: u16, token: &str) -> bool {
    let client = reqwest::Client::new();
    client
        .get(format!("http://127.0.0.1:{port}/api/health"))
        .header("x-app-token", token)
        .timeout(Duration::from_millis(800))
        .send()
        .await
        .map(|r| r.status().is_success())
        .unwrap_or(false)
}

/// Copy mot thu muc de quy (file + thu muc con). Symlink duoc copy theo
/// noi dung file dich (fs::copy tu dong follow symlink).
fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if from.is_dir() {
            copy_dir_recursive(&from, &to)?;
        } else {
            std::fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

/// Chuan bi thu muc chay Next standalone.
///
/// LY DO: truoc day app spawn server truc tiep tu resource_dir (nam trong
/// thu muc cai dat, vd AppData\Local\HTML to PDF Demo\web\standalone).
/// Next 16 ghi cache runtime (.next/server/route-cache/APP_PAGE/...,
/// index.segments) ngay trong thu muc do, ma trinh gỡ cai dat NSIS chi xoa
/// file no da cai dat nen cay thu muc cache sot lai sau khi uninstall.
/// Tu ban nay server chay tu ban copy trong app_local_data_dir (thu muc
/// du lieu nguoi dung, noi app duoc phep ghi); thu muc cai dat khong bao
/// gio bi ghi runtime nua nen uninstall se sach. Moi ban build co BUILD_ID
/// rieng (Next sinh moi moi lan build) nen thu muc runtime dat theo
/// BUILD_ID: doi build thi copy ban moi, ban cu khong bi xoa de tranh pha
/// server cua instance dang chay; ban cu chi la app data, xoa tay duoc.
/// Dong thoi xoa best-effort route-cache do ban cu de lai trong thu muc
/// cai dat (neu ghi duoc) de uninstall cua ban nang cap sau nay cung sach.
fn prepare_next_runtime_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let src = app
        .path()
        .resource_dir()
        .map_err(|e| e.to_string())?
        .join("web")
        .join("standalone");
    let server_js = src.join("server.js");
    if !server_js.exists() {
        return Err(format!("khong thay {}", server_js.display()));
    }
    // Don route-cache do ban cu de lai trong thu muc cai dat (best-effort:
    // thu muc cai dat dang read-only, vd cai per-machine, thi bo qua).
    let _ = std::fs::remove_dir_all(src.join(".next").join("server").join("route-cache"));
    let fingerprint = std::fs::read_to_string(src.join(".next").join("BUILD_ID"))
        .map(|v| {
            v.trim()
                .chars()
                .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
                .collect::<String>()
        })
        // Result khong co .filter (chi Option/Iterator co): doi sang Option
        // bang .ok() truoc - doc file loi -> None -> fallback version,
        // chuoi rong sau loc cung -> None -> fallback version.
        // Chu y: Option::unwrap_or_else nhan closure 0 tham so, khac
        // Result::unwrap_or_else nhan 1 tham so (de |_| la do E0593).
        .ok()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| app.package_info().version.to_string());
    let runtime = app
        .path()
        .app_local_data_dir()
        .map_err(|e| e.to_string())?
        .join("next-runtime")
        .join(fingerprint);
    if !runtime.join("server.js").exists() {
        copy_dir_recursive(&src, &runtime).map_err(|e| format!("copy standalone: {e}"))?;
    }
    Ok(runtime)
}

/// Spawn bun runtime chay Next standalone; thu toi da 5 port khac nhau.
async fn start_next_server(
    app: &tauri::AppHandle,
    token: &str,
) -> Result<(u16, CommandChild), String> {
    let standalone_dir = prepare_next_runtime_dir(app)?;
    let server_js = standalone_dir.join("server.js");
    let mut last_err = String::new();
    for attempt in 0..5 {
        let port = pick_free_port().ok_or("khong chon duoc port trong")?;
        let mut envs: HashMap<String, String> = HashMap::new();
        envs.insert("PORT".into(), port.to_string());
        envs.insert("HOSTNAME".into(), "127.0.0.1".into());
        envs.insert("APP_SESSION_TOKEN".into(), token.to_string());
        let cmd = app
            .shell()
            .sidecar("bun")
            .map_err(|e| e.to_string())?
            .current_dir(&standalone_dir)
            .envs(envs)
            .args([server_js.to_string_lossy().as_ref()]);
        let (mut rx, child) = cmd.spawn().map_err(|e| format!("spawn bun: {e}"))?;
        // Cho health-check toi da ~8s; neu tien trinh chet som thi thu port khac.
        let mut ok = false;
        for _ in 0..40 {
            if health_ok(port, token).await {
                ok = true;
                break;
            }
            match rx.try_recv() {
                Ok(CommandEvent::Terminated(payload)) => {
                    last_err = format!(
                        "bun thoat som (code {:?}) o lan thu {}",
                        payload.code,
                        attempt + 1
                    );
                    break;
                }
                Ok(CommandEvent::Stderr(line)) => {
                    eprint!("[next] {}", String::from_utf8_lossy(&line));
                }
                _ => {}
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        if ok {
            return Ok((port, child));
        }
        let _ = child.kill();
    }
    Err(format!("khong khoi dong duoc Next server: {last_err}"))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState {
            next_child: Mutex::new(None),
        })
        .setup(|app| {
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                // 1) Tai 2 exe cong cu (neu thieu) — FE nhan su kien tools://progress
                match ensure_tools(&handle).await {
                    Ok(bin_dir) => {
                        // Chen bin_dir vao PATH + tro WEASYPRINT_PATH de plugin-shell
                        // tu FE giai quyet duoc 'invoice-pdf' va no tu thay weasyprint.
                        let old = std::env::var("PATH").unwrap_or_default();
                        let sep = if cfg!(windows) { ";" } else { ":" };
                        std::env::set_var("PATH", format!("{}{sep}{old}", bin_dir.display()));
                        std::env::set_var("WEASYPRINT_PATH", bin_dir.join(exe_name("weasyprint")));
                        let _ = handle.emit("tools://ready", bin_dir.to_string_lossy().to_string());
                    }
                    Err(e) => {
                        eprintln!("[tools] {e}");
                        let _ = handle.emit("tools://error", e);
                    }
                }
                // 2) Khoi dong Next standalone tren port trong + token phien moi
                let token = gen_token();
                match start_next_server(&handle, &token).await {
                    Ok((port, child)) => {
                        *handle.state::<AppState>().next_child.lock().unwrap() = Some(child);
                        let url = format!("http://127.0.0.1:{port}/?__app_token={token}");
                        let h2 = handle.clone();
                        // Tao cua so tren main thread (macOS bat buoc)
                        let _ = handle.run_on_main_thread(move || {
                            if let Ok(parsed) = url.parse() {
                                let _ = WebviewWindowBuilder::new(
                                    &h2,
                                    "main",
                                    WebviewUrl::External(parsed),
                                )
                                .title("HTML -> PDF Demo")
                                .inner_size(980.0, 760.0)
                                .build();
                            }
                        });
                    }
                    Err(e) => eprintln!("[next] {e}"),
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                if let Some(child) = window.state::<AppState>().next_child.lock().unwrap().take() {
                    let _ = child.kill();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// Giu std::io::Write duoc dung (flush file part o ban ghi truc tiep neu can)
#[allow(dead_code)]
fn _unused(_: &Path) {
    let _ = std::io::stdout().flush();
}
