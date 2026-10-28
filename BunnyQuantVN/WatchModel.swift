// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import Foundation
import Observation

extension Notification.Name {
    static let accountWiped = Notification.Name("bq.accountWiped")       // đã xóa tài khoản: đăng ký lại từ đầu
}

struct WatchItem: Identifiable, Hashable {
    var symbol: String
    var name: String
    var id: String { symbol }
}

struct RowInfo { var price: Double; var isIndex: Bool; var change: Double?; var stance: Stance }

/// Tên gọi quen thuộc của các mã hay xem; mã khác hiện đúng mã.
enum Names {
    static let table: [String: String] = [
        "VNINDEX": "VN-Index", "VN30": "VN30", "VCB": "Vietcombank", "FPT": "FPT", "HPG": "Hòa Phát", "VNM": "Vinamilk",
        "MWG": "Thế Giới Di Động", "ACB": "ACB", "VIC": "Vingroup", "SSI": "Chứng khoán SSI", "TCB": "Techcombank",
        "VPB": "VPBank", "MBB": "MB Bank", "BID": "BIDV", "CTG": "VietinBank", "GAS": "PV GAS", "MSN": "Masan",
        "VHM": "Vinhomes", "STB": "Sacombank", "SAB": "Sabeco", "PLX": "Petrolimex", "POW": "PV Power", "TPB": "TPBank",
        "VIB": "VIB", "SHB": "SHB", "SSB": "SeABank", "VRE": "Vincom Retail", "BCM": "Becamex", "HDB": "HDBank",
        "GVR": "Cao su Việt Nam", "BVH": "Bảo Việt", "VJC": "Vietjet", "KDH": "Khang Điền", "NVL": "Novaland",
    ]
    static func of(_ symbol: String) -> String { table[symbol] ?? symbol }
}

/// Danh sách mã ngắn gọn: lấy từ danh sách theo dõi trên máy chủ (đã có sẵn), mỗi hàng một lượt phân tích khung ngày,
/// giữ trên máy tới khi nến ngày đóng nên mở lại app không tốn thêm lượt.
@Observable @MainActor
final class WatchModel {
    static let defaults: [WatchItem] = ["VCB", "FPT", "HPG", "VNM", "MWG", "ACB", "VIC", "SSI"].map { WatchItem(symbol: $0, name: Names.of($0)) }

    var items: [WatchItem] = []
    var rows: [String: RowInfo] = [:]
    var hidden: Set<String> = []          // máy chủ không mở mã này cho tài khoản, hoặc không có dữ liệu: ẩn lặng lẽ
    var failed: Set<String> = []
    var enough = false                    // hết lượt hôm nay
    var loading = true
    var offline = false

    var visible: [WatchItem] { items.filter { !hidden.contains($0.id) } }

    func load() async {
        loading = items.isEmpty
        offline = false
        do {
            var list = try await fetchList()
            if list.isEmpty, !UserDefaults.standard.bool(forKey: "bq.seeded") {
                for d in Self.defaults { _ = try? await API.call("/api/theo-doi", method: "POST", body: ["ma_ck": d.symbol]) }
                UserDefaults.standard.set(true, forKey: "bq.seeded")
                list = try await fetchList()
            }
            items = list.isEmpty ? Self.defaults : list
        } catch let e as APIError {
            offline = (e.code == .offline || e.code == .timeout)
            if items.isEmpty { items = Self.defaults }   // vẫn dùng được khi danh sách trên máy chủ lỗi
        } catch {}
        loading = false
        await refreshRows()
    }

    private func fetchList() async throws -> [WatchItem] {
        let json = Http.json(try await API.call("/api/theo-doi"))
        return ((json["danh_sach"] as? [[String: Any]]) ?? []).compactMap { w in
            guard let sym = (w["ma_ck"] as? String)?.uppercased(), !sym.isEmpty else { return nil }
            return WatchItem(symbol: sym, name: Names.of(sym))
        }
    }

    private func info(_ a: Analysis) -> RowInfo { RowInfo(price: a.price, isIndex: a.isIndex, change: a.changePct, stance: a.stance) }

    /// Nối tiếp từng mã (máy chủ phân tích mất vài giây mỗi mã), mã nào có sẵn trong bộ nhớ đệm thì hiện ngay.
    func refreshRows() async {
        enough = false
        for item in visible where rows[item.id] == nil || failed.contains(item.id) {
            if let hit = ResultCache.get(item.symbol + "|1d"), let a = Analysis(json: hit.json) { rows[item.id] = info(a) }
        }
        for item in visible where rows[item.id] == nil {
            do {
                rows[item.id] = info(try await Service.analysis(symbol: item.symbol, interval: "1d"))
                failed.remove(item.id)
            } catch let e as APIError {
                switch e.code {
                case .quota: enough = true; return
                case .locked, .notFound: hidden.insert(item.id)
                default: failed.insert(item.id)
                }
            } catch { failed.insert(item.id) }
        }
    }

    func add(symbol: String) async {
        let item = WatchItem(symbol: symbol, name: Names.of(symbol))
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        _ = try? await API.call("/api/theo-doi", method: "POST", body: ["ma_ck": symbol])
        await refreshRows()
    }

    func remove(_ item: WatchItem) async {
        items.removeAll { $0.id == item.id }
        _ = try? await API.call("/api/theo-doi/\(item.symbol)", method: "DELETE")
    }

    func reset() { items = []; rows = [:]; hidden = []; failed = []; enough = false; loading = true }
}
