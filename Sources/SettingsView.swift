import SwiftUI

struct SettingsView: View {
    @Binding var urlString: String
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("地址") {
                    TextField("https://…/?k=口令", text: $draft, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .lineLimit(2...4)
                }
                Section {
                    Text("整条地址里带 `?k=` 后面的口令，别只发域名——没有口令会被挡回来。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("恢复默认") {
                        draft = ContentView.defaultURL
                    }
                }
            }
            .navigationTitle("连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        urlString = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear { draft = urlString }
        }
    }
}
