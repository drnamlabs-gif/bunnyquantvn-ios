// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

struct WatchlistView: View {
    @State private var model = WatchModel()
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var path: [WatchItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    if model.enough {
                        Card {
                            Label("Hôm nay vậy là đủ rồi, mai quay lại nhé.", systemImage: "moon.stars")
                                .font(.subheadline).foregroundStyle(Palette.dim)
                        }
                    }
                    if model.offline {
                        Card { Label("Không có kết nối mạng.", systemImage: "wifi.slash").font(.subheadline).foregroundStyle(Palette.dim) }
                    }
                    if model.loading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ForEach(model.visible) { item in
                            NavigationLink(value: item) { Row(item: item, info: model.rows[item.id], failed: model.failed.contains(item.id)) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { Task { await model.remove(item) } } label: { Label("Bỏ khỏi danh sách", systemImage: "minus.circle") }
                                }
                        }
                    }
                    Text("Giá cổ phiếu tính bằng nghìn đồng (62,30 là 62.300 đồng). Chỉ là phân tích, không phải lời khuyên đầu tư.")
                        .font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center).padding(.top, 8)
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.bg)
            .navigationTitle("BunnyQuantVN")
            .navigationDestination(for: WatchItem.self) { SymbolView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Cài đặt")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm mã")
                }
            }
            .refreshable { await model.refreshRows() }
        }
        .task {
            await model.load()
            #if DEBUG   // chụp màn hình trên simulator: -debugOpen FPT mở thẳng màn hình mã, -debugSheet settings|add mở bảng
            let a = CommandLine.arguments
            if let i = a.firstIndex(of: "-debugOpen"), i + 1 < a.count, let it = model.items.first(where: { $0.symbol == a[i + 1] }) { path = [it] }
            if let i = a.firstIndex(of: "-debugSheet"), i + 1 < a.count { showSettings = a[i + 1] == "settings"; showAdd = a[i + 1] == "add" }
            #endif
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAdd) { AddSymbolView { sym in Task { await model.add(symbol: sym) } } }
    }
}

private struct Row: View {
    let item: WatchItem
    let info: RowInfo?
    let failed: Bool

    var body: some View {
        Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline).foregroundStyle(Palette.text)
                    Text(item.symbol).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                if let info {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(fmtPrice(info.price)).font(.headline.monospacedDigit()).foregroundStyle(Palette.text)
                        HStack(spacing: 6) {
                            if let c = info.change {
                                Text(fmtPct(c)).font(.footnote.monospacedDigit()).foregroundStyle(c >= 0 ? Palette.buy : Palette.sell)
                            }
                            Pill(text: info.stance.word, fg: info.stance.fg, bg: info.stance.bg)
                        }
                    }
                } else if failed {
                    Text("—").foregroundStyle(Palette.muted)
                } else {
                    ProgressView()
                }
            }
        }
    }
}

/// Chọn thêm một mã trong rổ VN30, hoặc gõ mã bất kỳ (ví dụ HPG).
struct AddSymbolView: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var list: [String] = []
    @State private var query = ""
    @State private var loading = false

    private var q: String { query.trimmingCharacters(in: .whitespaces).uppercased() }
    private var filtered: [String] { q.isEmpty ? list : list.filter { $0.contains(q) || Names.of($0).uppercased().contains(q) } }
    /// Mã gõ tay hợp lệ: 3 đến 8 chữ hoặc số, không phải hợp đồng phái sinh.
    private var typedOK: Bool {
        q.range(of: "^[A-Z0-9]{3,8}$", options: .regularExpression) != nil && !q.hasPrefix("VN30F") && !list.contains(q)
    }

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if typedOK {
                    Button { onPick(q); dismiss() } label: {
                        Label("Thêm mã \(q)", systemImage: "plus.circle").foregroundStyle(Palette.tint)
                    }
                }
                Section("Rổ VN30") {
                    ForEach(filtered, id: \.self) { s in
                        Button { onPick(s); dismiss() } label: {
                            VStack(alignment: .leading) {
                                Text(s).font(.headline).foregroundStyle(Palette.text)
                                Text(Names.of(s)).font(.caption).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Tìm hoặc gõ mã")
            .textInputAutocapitalization(.characters)
            .navigationTitle("Thêm mã")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
            .task { await loadList() }
        }
    }

    private func loadList() async {
        loading = true; defer { loading = false }
        guard let data = try? await API.call("/api/danh-muc/VN30") else { return }
        list = (Http.json(data)["danh_sach"] as? [Any])?.compactMap { $0 as? String } ?? []
    }
}
