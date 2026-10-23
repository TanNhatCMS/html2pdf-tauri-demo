import Converter from './converter';
export default function Page() {
  return (
    <main style={{ maxWidth: 860, margin: '0 auto', padding: 24 }}>
      <h1 style={{ fontSize: 22, margin: '0 0 4px' }}>Chuyển HTML → PDF (WeasyPrint sidecar)</h1>
      <p style={{ color: '#555', marginTop: 0 }}>
        Chọn thư mục chứa bộ hoá đơn (invoice.html + js + ảnh) rồi bấm Chuyển PDF.
        Frontend Next.js này đang chạy từ thư mục standalone trên một cổng local do Tauri cấp;
        việc chuyển đổi do sidecar <code>invoice-pdf</code> thực hiện qua plugin-shell.
      </p>
      <Converter />
    </main>
  );
}
