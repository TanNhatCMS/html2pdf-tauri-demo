import { NextRequest, NextResponse } from 'next/server';

// Token phien do backend Rust sinh moi lan khoi dong app, truyen qua env
// APP_SESSION_TOKEN khi spawn server nay. Khong co token dung -> 401,
// ke ca khi co nguoi/mo app khac trung port tren cung may.
// - Rust health-check: header x-app-token
// - Lan mo cua so dau tien: ?__app_token=... (bootstrap 1 lan) -> set cookie roi redirect xoa param
// - Cac request sau: cookie app_session
export function middleware(req: NextRequest) {
  const token = process.env.APP_SESSION_TOKEN;
  if (!token) return NextResponse.next(); // chay dev ngoai Tauri: khong khoa
  if (req.headers.get('x-app-token') === token) return NextResponse.next();
  if (req.cookies.get('app_session')?.value === token) return NextResponse.next();
  if (req.nextUrl.searchParams.get('__app_token') === token) {
    const url = req.nextUrl.clone();
    url.searchParams.delete('__app_token');
    const res = NextResponse.redirect(url);
    res.cookies.set('app_session', token, { httpOnly: true, sameSite: 'strict', path: '/' });
    return res;
  }
  return new NextResponse('Forbidden: phien Tauri khong hop le', { status: 401 });
}
export const config = { matcher: ['/((?!favicon.ico).*)'] };
