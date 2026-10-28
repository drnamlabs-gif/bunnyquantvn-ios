// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

/// Bảng màu của BunnyQuantVN: đỏ -> vàng ấm là gradient thương hiệu (cờ đỏ, sao vàng). Chỉ có giao diện sáng.
/// Xanh lá = tăng, đỏ = giảm theo thói quen của người chơi chứng khoán Việt Nam.
enum Palette {
    static let bg = Color(hex: 0xFAF7F2)
    static let card = Color.white
    static let fill = Color(hex: 0xF1EBE1)
    static let line = Color(hex: 0xE6DDCF)
    static let text = Color(hex: 0x24180F)
    static let dim = Color(hex: 0x5B4B3C)
    static let muted = Color(hex: 0x76685A)
    static let brandA = Color(hex: 0xC8102E)
    static let brandB = Color(hex: 0xF5A300)
    static let tint = Color(hex: 0x9A3412)
    static let level = Color(hex: 0x1E3A8A)
    static let buy = Color(hex: 0x15803D), buySoft = Color(hex: 0xDCFCE7)
    static let sell = Color(hex: 0xB91C1C), sellSoft = Color(hex: 0xFEE2E2)
    static let hold = Color(hex: 0xB45309), holdSoft = Color(hex: 0xFEF3C7)
    static let wait = Color(hex: 0x2563EB), waitSoft = Color(hex: 0xDBEAFE)
    static let gradient = LinearGradient(colors: [brandA, brandB], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

/// Hướng nhận định của máy chủ, nói bằng một từ dễ hiểu (không phải lệnh mua bán).
enum Stance {
    case up, down, steady, wait

    /// Hành động tiếng Việt của máy chủ -> hướng. Thứ tự có chủ đích: "GIỮ NGẮN" là chờ, "GIẢM TỶ TRỌNG" là giảm.
    init(vi raw: String) {
        let s = raw.uppercased()
        if s.contains("CHỜ") || s.contains("LƯỚT") || s.contains("NGẮN") { self = .wait }
        else if s.contains("GIẢM") || s.contains("TRÁNH") || s.contains("THOÁT") || s.contains("BÁN") { self = .down }
        else if s.contains("MUA") { self = .up }
        else if s.contains("GIỮ") || s.contains("QUAN SÁT") || s.contains("NẮM") { self = .steady }
        else { self = .wait }
    }

    var word: String {
        switch self {
        case .up: return "Nghiêng tăng"
        case .down: return "Nghiêng giảm"
        case .steady: return "Đứng yên"
        case .wait: return "Đang chờ"
        }
    }
    var fg: Color { self == .up ? Palette.buy : self == .down ? Palette.sell : self == .steady ? Palette.hold : Palette.wait }
    var bg: Color { self == .up ? Palette.buySoft : self == .down ? Palette.sellSoft : self == .steady ? Palette.holdSoft : Palette.waitSoft }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line.opacity(0.8), lineWidth: 0.5))
    }
}

struct Pill: View {
    let text: String
    let fg: Color, bg: Color
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: Capsule())
    }
}

/// Số theo kiểu Việt Nam: dấu phẩy thập phân, dấu chấm hàng nghìn (giống trang web).
private let viFormatters: [Int: NumberFormatter] = Dictionary(uniqueKeysWithValues: (0...3).map { d in
    let f = NumberFormatter()
    f.locale = Locale(identifier: "vi_VN")
    f.numberStyle = .decimal
    f.minimumFractionDigits = d; f.maximumFractionDigits = d
    f.usesGroupingSeparator = true
    return (d, f)
})

func fmtNum(_ v: Double, _ digits: Int = 2) -> String { viFormatters[digits]?.string(from: NSNumber(value: v)) ?? "\(v)" }

/// Giá cổ phiếu tính bằng nghìn đồng (62,30 = 62.300 đồng); chỉ số tính bằng điểm. Cả hai hai chữ số lẻ như trên web.
func fmtPrice(_ v: Double) -> String { fmtNum(v, 2) }

func fmtPct(_ v: Double) -> String { (v > 0 ? "+" : "") + fmtNum(v, 2) + "%" }
