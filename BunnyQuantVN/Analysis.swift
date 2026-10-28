// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import CryptoKit
import Foundation

struct Candle: Identifiable {
    let t: Double, o: Double, h: Double, l: Double, c: Double
    var id: Double { t }
}

/// Kết quả một lần phân tích, đọc phòng thủ từ JSON của máy chủ: khối bị khóa là {"khoa": true, ...}, số có thể null.
/// Thiếu gì thì thẻ đó biến mất; không bao giờ hiện "NaN".
struct Analysis {
    var symbol: String, interval: String
    var stance: Stance
    var confidence: String?
    var price: Double
    var unit: String               // "nghìn đồng" hoặc "điểm"
    var settlement: String?        // "T+2" ...
    var entry: Double?, stop: Double?, target1: Double?, target2: Double?
    var rr: Double?
    var candles: [Candle]

    var isIndex: Bool { unit == "điểm" }

    /// Biên độ trung bình của 14 nến gần nhất, tính theo % giá: "giá thường dao động bao nhiêu mỗi nến".
    var typicalMovePct: Double? {
        let w = candles.suffix(14)
        guard w.count >= 5 else { return nil }
        let m = w.compactMap { $0.c > 0 ? ($0.h - $0.l) / $0.c * 100 : nil }
        return m.isEmpty ? nil : m.reduce(0, +) / Double(m.count)
    }
    private var base: Double { entry ?? price }
    /// Lỗ nếu chạm điểm cắt lỗ, % so với điểm vào.
    var riskPct: Double? { stop.map { abs(base - $0) / base * 100 } }
    /// Lãi nếu chạm chốt lời 1, % so với điểm vào.
    var rewardPct: Double? { target1.map { abs($0 - base) / base * 100 } }

    var changePct: Double? {
        guard candles.count >= 2, let prev = candles.dropLast().last?.c, prev > 0, let last = candles.last?.c else { return nil }
        return (last - prev) / prev * 100
    }

    init?(json: [String: Any]) {
        func num(_ v: Any?) -> Double? {
            let d = (v as? Double) ?? (v as? NSNumber)?.doubleValue ?? Double(v as? String ?? "")
            return d.flatMap { $0.isFinite ? $0 : nil }
        }
        guard let price = num(json["gia_hien_tai"]) else { return nil }
        symbol = ((json["ma_ck"] as? String) ?? "").uppercased()
        interval = json["khung"] as? String ?? ""
        let kl = json["ket_luan"] as? [String: Any] ?? [:]
        stance = Stance(vi: kl["hanh_dong"] as? String ?? "")
        // Nhãn độ tin cậy là chữ ngắn ("Cao", "Trung bình"); câu dài thì bỏ.
        confidence = (kl["do_tin_cay"] as? String).flatMap { $0.count <= 20 ? $0 : nil }
        self.price = price
        unit = (json["don_vi_gia"] as? String) == "điểm" ? "điểm" : "nghìn đồng"
        settlement = json["che_do_thanh_toan"] as? String
        let gm = kl["gia_muc_tieu"] as? [String: Any] ?? [:]
        entry = num((gm["vung_mua"] as? [String: Any])?["ly_tuong"])
        stop = num(gm["cat_lo"])
        target1 = num(gm["chot_loi_1"]); target2 = num(gm["chot_loi_2"])
        rr = num(gm["ty_le_loi_rui_ro"])
        candles = ((json["chuoi_nen"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let t = num(d["t"]), let o = num(d["o"]), let h = num(d["h"]), let l = num(d["l"]), let c = num(d["c"]) else { return nil }
            return Candle(t: t, o: o, h: h, l: l, c: c)
        }
    }
}

/// Kết quả giữ trên máy tới khi nến đang chạy đóng: trong một nến máy chủ trả đúng các số đó và vẫn tính một lượt.
enum ResultCache {
    private struct Entry: Codable { var expiresAt: Double; var body: Data }
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("results", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static let lock = NSLock()

    private static func file(_ key: String) -> URL {
        let h = SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(h + ".json")
    }

    /// Thời điểm nến hiện tại đóng (epoch giây). Lưới theo giờ Việt Nam; tuần neo vào thứ Hai.
    static func barClose(_ interval: String, now: Date = Date()) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let day = cal.startOfDay(for: now)
        switch interval {
        case "1w", "1wk":
            let wd = cal.component(.weekday, from: now)            // 1 = Chủ nhật
            let toMonday = (9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7
            return cal.date(byAdding: .day, value: toMonday, to: day)!.timeIntervalSince1970
        default:
            return cal.date(byAdding: .day, value: 1, to: day)!.timeIntervalSince1970
        }
    }

    static func get(_ key: String) -> (json: [String: Any], expiresAt: Double)? {
        lock.lock(); defer { lock.unlock() }
        guard let raw = try? Data(contentsOf: file(key)), let e = try? JSONDecoder().decode(Entry.self, from: raw) else { return nil }
        if Date().timeIntervalSince1970 >= e.expiresAt { try? FileManager.default.removeItem(at: file(key)); return nil }
        return (Http.json(e.body), e.expiresAt)
    }

    static func put(_ key: String, body: Data, interval: String) {
        lock.lock(); defer { lock.unlock() }
        let e = Entry(expiresAt: barClose(interval), body: body)
        try? JSONEncoder().encode(e).write(to: file(key), options: .atomic)
    }

    static func clear() { try? FileManager.default.removeItem(at: dir); _ = dir }
}

enum Service {
    /// Phân tích nhẹ một mã: chỉ phần kỹ thuật và các mức giá (bỏ báo cáo tài chính, mô phỏng ở mức thấp nhất) để nhanh và đỡ tốn lượt.
    static func analysis(symbol: String, interval: String, force: Bool = false) async throws -> Analysis {
        let key = [symbol.uppercased(), interval].joined(separator: "|")
        if !force, let hit = ResultCache.get(key), let a = Analysis(json: hit.json) { return a }

        let q = "khung=\(interval)&tam_nhin=trung_han&bo_qua_co_ban=true&xac_suat=false&da_khung=false&so_lan_mo_phong=500"
        let sym = symbol.uppercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let body = try await API.call("/api/phan-tich/\(sym)?\(q)")
        guard let a = Analysis(json: Http.json(body)) else { throw APIError(code: .server, message: "unreadable result") }
        ResultCache.put(key, body: body, interval: interval)
        return a
    }
}
