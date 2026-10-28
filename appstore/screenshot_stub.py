# Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
"""Máy chủ giả CHỈ để chụp ảnh App Store trên simulator (simulator không có App Attest nên không đăng ký được với máy chủ thật).

Nến là GIÁ THẬT lấy từ Yahoo (mã *.VN, đổi sang nghìn đồng); các mức Vào / SL / TP và nhãn hướng là số minh hoạ tính đơn giản
từ nến thật, KHÔNG phải kết quả của máy chủ BunnyQuantVN. Hợp đồng giống backend VN: /api/ios/*, /api/theo-doi, /api/danh-muc/VN30,
/api/phan-tich/{mã}, /api/tai-khoan.

    python3 ios-swift/appstore/screenshot_stub.py        # nghe 127.0.0.1:8099
    xcodebuild ... BQ_API_BASE=http://127.0.0.1:8099 build
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
import yfinance as yf

WATCH = []
VN30 = ["ACB", "BCM", "BID", "BVH", "CTG", "FPT", "GAS", "GVR", "HDB", "HPG", "MBB", "MSN", "MWG", "PLX", "POW", "SAB", "SHB",
        "SSB", "SSI", "STB", "TCB", "TPB", "VCB", "VHM", "VIB", "VIC", "VJC", "VNM", "VPB", "VRE"]
PERIOD = {"1d": ("6mo", "1d"), "1w": ("2y", "1wk")}
CACHE = {}


def candles(sym, khung):
    key = (sym, khung)
    if key not in CACHE:
        per, yi = PERIOD.get(khung, ("6mo", "1d"))
        d = yf.Ticker(sym + ".VN").history(period=per, interval=yi).dropna()
        CACHE[key] = [{"t": int(i.timestamp()), "o": round(float(r.Open) / 1000, 2), "h": round(float(r.High) / 1000, 2),
                       "l": round(float(r.Low) / 1000, 2), "c": round(float(r.Close) / 1000, 2), "v": int(r.Volume)}
                      for i, r in d.iterrows()]
    return CACHE[key]


def decide(cs):
    px = cs[-1]["c"]; sma = sum(c["c"] for c in cs[-20:]) / 20; prev = sum(c["c"] for c in cs[-25:-5]) / 20
    up, down = px > sma and sma > prev, px < sma and sma < prev
    stop = round(min(c["l"] for c in cs[-10:]) * 0.99, 2)
    r = max(px - stop, px * 0.01)
    action = "MUA" if up else "GIẢM TỶ TRỌNG" if down else "GIỮ"
    return px, stop, round(px + 1.5 * r, 2), round(px + 3 * r, 2), action


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)

    def log_message(self, *a): print(self.command, self.path, flush=True)

    def do_GET(self):
        u = urlparse(self.path); p = u.path
        if p == "/api/ios/challenge": return self._send(200, {"challenge": "stub"})
        if p == "/api/theo-doi":
            return self._send(200, {"danh_sach": [{"ma_ck": m, "ghi_chu": None, "created_at": ""} for m in WATCH], "so_ma": len(WATCH), "gioi_han": 30})
        if p == "/api/danh-muc/VN30": return self._send(200, {"ten": "VN30", "so_ma": len(VN30), "danh_sach": VN30})
        if p.startswith("/api/phan-tich/"):
            sym = p.split("/")[-1].upper(); khung = parse_qs(u.query).get("khung", ["1d"])[0]
            try: cs = candles(sym, khung)
            except Exception: return self._send(404, {"detail": f"Không đủ dữ liệu cho {sym}."})
            if len(cs) < 25: return self._send(404, {"detail": f"Không đủ dữ liệu cho {sym}."})
            px, stop, t1, t2, action = decide(cs)
            return self._send(200, {"ma_ck": sym, "khung": khung, "gia_hien_tai": px, "don_vi_gia": "nghìn đồng", "che_do_thanh_toan": "T+2",
                "chuoi_nen": cs[-300:],
                "ket_luan": {"hanh_dong": action, "diem": 6.5, "do_tin_cay": "Trung bình", "tom_tat": "",
                    "gia_muc_tieu": {"vung_mua": {"ly_tuong": px}, "cat_lo": stop, "chot_loi_1": t1, "chot_loi_2": t2,
                                     "ty_le_loi_rui_ro": round((t1 - px) / (px - stop), 1)}}})
        self._send(404, {"detail": "nf"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); b = json.loads(self.rfile.read(n) or b"{}"); p = urlparse(self.path).path
        if p in ("/api/ios/register", "/api/ios/refresh"):
            return self._send(200, {"access_token": "tok", "refresh_token": "ref", "expires_in": 3600, "user_id": "u1"})
        if p == "/api/theo-doi":
            m = b["ma_ck"].upper()
            if m in WATCH: return self._send(409, {"detail": f"{m} đã có trong danh sách theo dõi."})
            WATCH.append(m); return self._send(200, {"da_them": m, "so_ma": len(WATCH), "gioi_han": 30})
        self._send(404, {})

    def do_DELETE(self):
        p = urlparse(self.path).path
        if p.startswith("/api/theo-doi/"):
            m = p.split("/")[-1].upper()
            if m in WATCH: WATCH.remove(m)
        self._send(200, {"da_xoa": True})


HTTPServer(("127.0.0.1", 8099), H).serve_forever()
