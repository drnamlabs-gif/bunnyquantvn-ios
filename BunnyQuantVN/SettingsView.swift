// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var message: String?

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Chỉ là phân tích, không phải lời khuyên đầu tư. Số liệu được ước lượng từ dữ liệu lịch sử và có thể sai. Quyết định và rủi ro là của bạn.")
                        .font(.footnote).foregroundStyle(Palette.dim)
                } header: { Text("Lưu ý") }

                Section {
                    Explain("Biến động thường thấy",
                            "Giá thường dao động bao nhiêu phần trăm trong một nến (một ngày hay một tuần tùy khung bạn chọn). Số càng lớn, giá càng hay nhảy.")
                    Explain("Vùng vào",
                            "Vùng giá hợp lý để cân nhắc mua, tính từ cách giá đã chạy gần đây.")
                    Explain("Cắt lỗ (SL)",
                            "Mức giá mà nếu chạm tới thì kịch bản đã sai và nên thoát để giữ khoản lỗ trong tầm kiểm soát. Rủi ro là khoảng cách từ điểm vào tới mức này, tính bằng phần trăm.")
                    Explain("Chốt lời (TP)",
                            "Mức giá mục tiêu để cân nhắc chốt lãi. Có hai mục tiêu: chốt lời 1 gần hơn, chốt lời 2 xa hơn.")
                    Explain("Lợi nhuận so với rủi ro",
                            "Nếu số này là 1 : 2 thì lãi ở mục tiêu gấp khoảng hai lần khoản lỗ ở điểm cắt lỗ. Lớn hơn 1 là tốt hơn, nhưng không đảm bảo kết quả.")
                    Explain("Đơn vị giá",
                            "Giá cổ phiếu tính bằng nghìn đồng: 62,30 nghĩa là 62.300 đồng. Chỉ số như VN-Index tính bằng điểm.")
                } header: { Text("Các con số nghĩa là gì") }

                Section("Giới thiệu") {
                    LabeledContent("BunnyQuantVN", value: version)
                    LabeledContent("Tác giả", value: "Dr. Nam H. Le")
                    Link("drnamlabs.com", destination: URL(string: "https://drnamlabs.com")!)
                    Link("bunnyquant.vn", destination: URL(string: "https://bunnyquant.vn")!)
                    Link("Quyền riêng tư", destination: URL(string: "https://bunnyquant.vn/bao-mat")!)
                    Text("© 2026 Dr. Nam H. Le. drnamlabs.com, bunnyquant.com").font(.caption).foregroundStyle(Palette.muted)
                }

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if deleting { ProgressView() } else { Text("Xóa tài khoản và dữ liệu") }
                    }
                    .disabled(deleting)
                } footer: {
                    Text("Xóa danh sách theo dõi và mọi dữ liệu của tài khoản này khỏi máy chủ.")
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
            .confirmationDialog("Xóa tài khoản?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Xóa vĩnh viễn", role: .destructive) { Task { await deleteAccount() } }
                Button("Hủy", role: .cancel) {}
            } message: { Text("Việc này không hoàn tác được.") }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func deleteAccount() async {
        deleting = true; defer { deleting = false }
        do {
            _ = try await API.call("/api/tai-khoan", method: "DELETE")
            await Auth.shared.wipe()
            ResultCache.clear()
            UserDefaults.standard.removeObject(forKey: "bq.seeded")
            NotificationCenter.default.post(name: .accountWiped, object: nil)
            dismiss()
        } catch {
            message = "Chưa xóa được, thử lại giúp tôi."
        }
    }
}

private struct Explain: View {
    let title: String, text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            Text(text).font(.footnote).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
