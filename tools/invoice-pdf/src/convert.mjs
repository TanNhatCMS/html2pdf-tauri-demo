// Ban Node.js cua convert: tien xu ly bang JS thuan + goi WeasyPrint CLI.
// Dung: node convert.mjs <thu-muc-hoa-don> <file-pdf-ra> [duong-dan-weasyprint]
// Trong app Tauri: file nay chay duoc o moi noi co Node (server, Electron main,
// hoac Node sidecar) — frontend webview cua Tauri thi KHONG spawn duoc tien trinh
// neu khong qua plugin shell/backend Rust.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import QRCode from 'qrcode';

const FIT_ONE_PAGE_CSS = `<style>
body { font-size: 10.8pt !important; }
.main-page { padding: 10px 14px 4px !important; line-height: 1.27 !important; }
.heading-content .main-title { font-size: 15.5pt !important; }
.heading-content p, .heading-content .code-ms { font-size: 10.8pt !important; }
.content-info .list-fill-out { margin-top: 2px !important; margin-bottom: 2px !important; }
.content-info .list-fill-out li { font-size: 10.8pt !important; }
.data-item { font-size: 10.8pt !important; margin-bottom: 2px !important; }
.data-item .di-label, .data-item .di-value { min-height: 18px !important; }
.res-tb { margin-top: 5px !important; margin-bottom: 5px !important; }
.res-tb tr td, .res-tb tr th { padding: 2px 4px !important; font-size: 10.3pt !important; }
.sign-box { margin-top: 4px !important; padding: 3px !important; }
.sign-box span { font-size: 10.8pt !important; }
.ft-sign p, .ft-sign h3 { margin: 2px 0 !important; }
.fd-end { padding-top: 2px !important; }
.vip-divide { margin: 2px 0 !important; }
#qrcodeTable svg { width: 80px; height: 80px; }
</style>`;

export async function preprocessInvoiceHtml(html) {
  // 1) QR: details.js lam viec nay trong browser — o day sinh SVG bang package qrcode
  const m = html.match(/id="qrcodeContent"\s+value="([^"]+)"/);
  if (m) {
    const svg = await QRCode.toString(m[1], { type: 'svg', errorCorrectionLevel: 'L', margin: 1 });
    html = html.replace('<div id="qrcodeTable"></div>', `<div id="qrcodeTable">${svg}</div>`);
  }
  // 2) Chu ky: chuoi DN -> chi giu CN
  html = html.replace(/(<span id="cks"[^>]*>)([\s\S]*?)(<\/span>)/, (_, a, dn, b) => {
    const cn = dn.match(/CN=([^,]+)/);
    return a + (cn ? cn[1] : dn) + b;
  });
  // 3) Bo script + the an, chen CSS ep 1 trang
  html = html.replace(/<script[^>]*src="details\.js"[^>]*><\/script>/, '');
  html = html.replace(/<input type="hidden" id="qrcodeContent"[^>]*>/, '');
  return html.replace('</head>', FIT_ONE_PAGE_CSS + '</head>');
}

export async function convertInvoiceToPdf(invoiceDir, outPdf, weasyprint = 'weasyprint') {
  const raw = fs.readFileSync(path.join(invoiceDir, 'invoice.html'), 'utf8');
  const html = await preprocessInvoiceHtml(raw);
  const workDir = path.join(path.dirname(path.resolve(outPdf)), 'work');
  fs.mkdirSync(workDir, { recursive: true });
  const tmpHtml = path.join(workDir, 'invoice-print.html');
  fs.writeFileSync(tmpHtml, html);
  const r = spawnSync(weasyprint,
    ['--base-url', path.resolve(invoiceDir), '--encoding', 'utf-8', tmpHtml, outPdf],
    { encoding: 'utf8' });
  if (r.error) throw new Error(`khong chay duoc weasyprint: ${r.error.message}`);
  if (r.status !== 0) throw new Error(`weasyprint loi: ${r.stderr}`);
  const head = fs.readFileSync(outPdf).subarray(0, 4).toString('latin1');
  if (head !== '%PDF') throw new Error('file ra khong phai PDF');
}

// Tim weasyprint dong goi canh exe nay (khi ca 2 deu la sidecar cua Tauri,
// Tauri dat chung 1 thu muc). Khong co thi tra null -> roi ve PATH.
export function siblingWeasyprint() {
  const dir = path.dirname(process.execPath);
  for (const name of ['weasyprint.exe', 'weasyprint']) {
    const p = path.join(dir, name);
    if (fs.existsSync(p)) return p;
  }
  return null;
}
