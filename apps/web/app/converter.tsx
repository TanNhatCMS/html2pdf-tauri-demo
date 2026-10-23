'use client';
import { useRef, useState } from 'react';

type LogLine = { ts: string; msg: string };
const now = () => new Date().toLocaleTimeString('vi-VN', { hour12: false }) + '.' + String(Date.now() % 1000).padStart(3, '0');
const inTauri = () => typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export default function Converter() {
  const [dir, setDir] = useState('');
  const [htmlFiles, setHtmlFiles] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [logs, setLogs] = useState<LogLine[]>([]);
  const [lastMs, setLastMs] = useState<number | null>(null);
  const [origin, setOrigin] = useState('');
  const logRef = useRef<HTMLDivElement>(null);

  const log = (msg: string) => setLogs((p) => [...p, { ts: now(), msg }]);

  async function pickDir() {
    if (!inTauri()) { log('Đang mở ngoài Tauri (trình duyệt thường): hộp chọn thư mục chỉ hoạt động trong app.'); return; }
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const { readDir } = await import('@tauri-apps/plugin-fs');
      const picked = await open({ directory: true, multiple: false, title: 'Chọn thư mục chứa hoá đơn (invoice.html)' });
      if (!picked || typeof picked !== 'string') { log('Đã huỷ chọn thư mục.'); return; }
      setOrigin(window.location.origin);
      setDir(picked); log(`Đã chọn thư mục: ${picked}`);
      const entries = await readDir(picked);
      const htmls = entries.filter((e) => e.isFile && e.name?.toLowerCase().endsWith('.html')).map((e) => e.name as string);
      setHtmlFiles(htmls);
      log(`Quét thấy ${entries.length} mục, trong đó ${htmls.length} file .html: ${htmls.join(', ') || '(không có)'}`);
      if (!htmls.includes('invoice.html')) log('LƯU Ý: sidecar hiện chuyển file invoice.html trong thư mục — chưa thấy file này.');
    } catch (e) { log('Lỗi chọn thư mục: ' + String(e)); }
  }

  async function convert() {
    if (!dir) { log('Chưa chọn thư mục.'); return; }
    if (!inTauri()) { log('Ngoài Tauri không gọi được sidecar. Hãy chạy trong app Tauri.'); return; }
    const sep = dir.includes('\\') ? '\\' : '/';
    const outPdf = dir.replace(/[\\/]$/, '') + sep + 'invoice-1page.pdf';
    setBusy(true); setLastMs(null);
    const t0 = performance.now();
    log(`Bắt đầu chuyển: ${dir}${sep}invoice.html -> ${outPdf}`);
    try {
      const { Command } = await import('@tauri-apps/plugin-shell');
      // 'invoice-pdf' la exe tai online luc chay lan dau, Rust da dua thu muc bin vao PATH
      // va dat env WEASYPRINT_PATH tro toi exe weasyprint da tai. Scope trong capabilities.
      const cmd = Command.create('invoice-pdf', [dir, outPdf]);
      cmd.stdout.on('data', (line) => log('[sidecar stdout] ' + line));
      cmd.stderr.on('data', (line) => log('[sidecar stderr] ' + line));
      cmd.on('error', (err) => log('[sidecar error] ' + String(err)));
      cmd.on('close', (data) => {
        const ms = Math.round(performance.now() - t0);
        setLastMs(ms); setBusy(false);
        log(`Sidecar kết thúc: code=${data.code}, signal=${data.signal ?? '-'}, tổng thời gian ${ms} ms`);
        if (data.code === 0) log(`XONG. File PDF: ${outPdf}`);
      });
      const child = await cmd.spawn();
      log(`Đã spawn sidecar invoice-pdf, pid=${child.pid}`);
    } catch (e) {
      setBusy(false); setLastMs(Math.round(performance.now() - t0));
      log('Lỗi spawn sidecar: ' + String(e) + ' — kiểm tra app đã tải đủ 2 exe ở lần chạy đầu chưa (xem log backend).');
    }
  }

  return (
    <section>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
        <button onClick={pickDir} disabled={busy} style={{ padding: '8px 14px' }}>📁 Chọn thư mục hoá đơn…</button>
        <button onClick={convert} disabled={busy || !dir} style={{ padding: '8px 14px' }}>{busy ? 'Đang chuyển…' : '⚡ Chuyển PDF'}</button>
        {lastMs !== null && <span>Thời gian xử lý gần nhất: <b>{lastMs} ms</b></span>}
      </div>
      <p style={{ color: '#555' }}>
        Thư mục: <code>{dir || '(chưa chọn)'}</code><br />
        File HTML: <code>{htmlFiles.join(', ') || '-'}</code><br />
        Origin đang chạy: <code>{origin || (typeof window !== 'undefined' ? window.location.origin : '')}</code>
      </p>
      <div ref={logRef} style={{ background: '#0b1020', color: '#c9f7c9', padding: 12, borderRadius: 8, height: 300, overflow: 'auto', fontFamily: 'ui-monospace, monospace', fontSize: 12.5, whiteSpace: 'pre-wrap' }}>
        {logs.length === 0 ? 'Log debug sẽ hiện ở đây…' : logs.map((l, i) => <div key={i}>[{l.ts}] {l.msg}</div>)}
      </div>
    </section>
  );
}
