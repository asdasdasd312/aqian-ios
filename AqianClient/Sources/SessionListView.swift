import SwiftUI

struct SessionListView: View {
    @State private var rows: [SessionRow] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                ForEach(rows) { row in
                    NavigationLink {
                        ChatView(session: row)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.headline).lineLimit(1)
                            Text(row.last_text).font(.subheadline)
                                .foregroundStyle(.secondary).lineLimit(2)
                            Text(short(row.updated_ms) + "  ·  " + row.proj)
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("会话")
            .refreshable { await load() }
            .task { await load() }
            .overlay {
                if loading && rows.isEmpty { ProgressView() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            rows = try await API.shared.sessions()
            error = nil
        } catch {
            self.error = "连不上网关：" + error.localizedDescription
        }
    }

    private func short(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "MM-dd"
        return f.string(from: d)
    }
}
