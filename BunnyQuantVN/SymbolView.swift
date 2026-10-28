// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

struct SymbolView: View {
    let item: WatchItem
    @State private var interval = "1d"
    @State private var analysis: Analysis?
    @State private var loading = true
    @State private var problem: APIError?

    private let frames: [(String, String)] = [("1d", "Ngày"), ("1w", "Tuần")]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                Picker("", selection: $interval) {
                    ForEach(frames, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)

                if let a = analysis {
                    Card { CandleChart(candles: a.candles, levels: chartLevels(a)) }
                    if !chartLevels(a).isEmpty { levelsCard(a) }
                    riskCard(a)
                    readingCard(a)
                } else if loading {
                    ProgressView().padding(.top, 80)
                } else if let p = problem {
                    problemView(p)
                }

                Text("Chỉ là phân tích, không phải lời khuyên đầu tư. Số liệu ước lượng từ dữ liệu lịch sử và có thể sai.")
                    .font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.bg)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: interval) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(analysis.map { fmtPrice($0.price) } ?? "—")
                .font(.system(size: 38, weight: .bold).monospacedDigit()).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                if let c = analysis?.changePct {
                    Text(fmtPct(c)).font(.headline.monospacedDigit()).foregroundStyle(c >= 0 ? Palette.buy : Palette.sell)
                }
                if let a = analysis { Pill(text: a.stance.word, fg: a.stance.fg, bg: a.stance.bg) }
                Spacer()
                Text(item.symbol).font(.footnote).foregroundStyle(Palette.muted)
            }
            if let a = analysis {
                Text(a.isIndex ? "điểm" : "nghìn đồng mỗi cổ phiếu").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartLevels(_ a: Analysis) -> [ChartLevel] {
        var out: [ChartLevel] = []
        if let e = a.entry { out.append(ChartLevel(label: "Vào", price: e, color: Palette.level)) }
        if let s = a.stop { out.append(ChartLevel(label: "SL", price: s, color: Palette.sell)) }
        if let t = a.target1 { out.append(ChartLevel(label: "TP1", price: t, color: Palette.buy)) }
        if let t = a.target2 { out.append(ChartLevel(label: "TP2", price: t, color: Palette.buy.opacity(0.7))) }
        return out
    }

    private func levelsCard(_ a: Analysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Các mức giá cần chú ý").font(.headline).foregroundStyle(Palette.text)
                ForEach(chartLevels(a)) { l in
                    HStack {
                        Circle().fill(l.color).frame(width: 8, height: 8)
                        Text(levelName(l.label)).foregroundStyle(Palette.dim)
                        Spacer()
                        Text(fmtPrice(l.price)).font(.body.monospacedDigit()).foregroundStyle(Palette.text)
                        Text(fmtPct((l.price - a.price) / a.price * 100)).font(.footnote.monospacedDigit())
                            .foregroundStyle(Palette.muted).frame(width: 76, alignment: .trailing)
                    }
                }
                if let rr = a.rr, rr > 0 {
                    Divider()
                    Text("Lợi nhuận so với rủi ro khoảng 1 : " + fmtNum(rr, 1))
                        .font(.footnote).foregroundStyle(Palette.dim)
                }
            }
        }
    }

    private func levelName(_ k: String) -> String {
        switch k {
        case "Vào": return "Vùng vào"
        case "SL": return "Cắt lỗ"
        case "TP1": return "Chốt lời 1"
        default: return "Chốt lời 2"
        }
    }

    /// Ba con số người dùng cần nhất, vẽ thành thanh để so với nhau: giá hay nhúc nhích bao nhiêu, cắt lỗ thì mất bao nhiêu, mục tiêu được bao nhiêu.
    @ViewBuilder private func riskCard(_ a: Analysis) -> some View {
        let rows: [(String, String, Double?, Color)] = [
            ("Biến động thường thấy", "mỗi nến", a.typicalMovePct, Palette.tint),
            ("Rủi ro nếu cắt lỗ", "SL", a.riskPct, Palette.sell),
            ("Mục tiêu 1", "TP", a.rewardPct, Palette.buy),
        ]
        let shown = rows.filter { $0.2 != nil }
        if !shown.isEmpty {
            let top = shown.compactMap { $0.2 }.max() ?? 1
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Biến động và rủi ro").font(.headline).foregroundStyle(Palette.text)
                    ForEach(shown, id: \.0) { r in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(r.0).foregroundStyle(Palette.dim)
                                Text(r.1).font(.caption).foregroundStyle(Palette.muted)
                                Spacer()
                                Text(fmtNum(r.2 ?? 0, 2) + "%").font(.body.monospacedDigit()).foregroundStyle(Palette.text)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.muted.opacity(0.15))
                                    Capsule().fill(r.3).frame(width: max(6, g.size.width * CGFloat((r.2 ?? 0) / top)))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    Text("Ý nghĩa từng số: Cài đặt > Các con số nghĩa là gì.").font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func readingCard(_ a: Analysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Đọc nhanh").font(.headline).foregroundStyle(Palette.text)
                Text(summary(a)).font(.subheadline).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                if let c = a.confidence {
                    Text("Độ tin cậy: " + c.lowercased()).font(.subheadline).foregroundStyle(Palette.dim)
                }
                if a.settlement == "T+2" {
                    Text("Cổ phiếu giao dịch T+2: mua hôm nay thì sớm nhất ngày làm việc thứ ba mới bán được, nên cắt lỗ cần tính trước.")
                        .font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func summary(_ a: Analysis) -> String {
        let frame = (frames.first { $0.0 == interval }?.1 ?? "").lowercased()
        switch a.stance {
        case .up: return "Trên khung \(frame), xu hướng đang nghiêng tăng."
        case .down: return "Trên khung \(frame), xu hướng đang nghiêng giảm."
        case .steady: return "Trên khung \(frame), giá đang đi ngang, chưa có hướng rõ."
        case .wait: return "Trên khung \(frame), tín hiệu chưa đủ rõ. Đợi thêm sẽ an toàn hơn."
        }
    }

    @ViewBuilder private func problemView(_ p: APIError) -> some View {
        Card {
            VStack(spacing: 10) {
                switch p.code {
                case .quota:
                    Label("Hôm nay vậy là đủ rồi, mai quay lại nhé.", systemImage: "moon.stars")
                case .locked, .notFound:
                    Label("Mã này hiện chưa xem được.", systemImage: "lock")
                case .busy:
                    Label("Nguồn dữ liệu giá đang bận, thử lại sau ít phút.", systemImage: "clock")
                case .offline, .timeout:
                    Label("Không có kết nối mạng.", systemImage: "wifi.slash")
                default:
                    Label("Có lỗi, thử lại giúp tôi.", systemImage: "exclamationmark.triangle")
                }
                if p.code != .quota && p.code != .locked && p.code != .notFound {
                    Button("Thử lại") { Task { await load(force: true) } }.buttonStyle(.bordered)
                }
            }
            .font(.subheadline).foregroundStyle(Palette.dim).frame(maxWidth: .infinity)
        }
    }

    private func load(force: Bool = false) async {
        loading = true; problem = nil
        defer { loading = false }
        do {
            analysis = try await Service.analysis(symbol: item.symbol, interval: interval, force: force)
        } catch let e as APIError { analysis = nil; problem = e }
        catch { analysis = nil; problem = APIError(code: .server) }
    }
}
