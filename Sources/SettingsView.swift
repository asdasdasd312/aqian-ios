import SwiftUI

struct SettingsView: View {
    @Binding var base: String
    @Binding var token: String
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var b: String = ""
    @State private var k: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("房间地址") {
                    TextField("http://192.168.0.233:8099", text: $b, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .lineLimit(1...3)
                }
                Section("口令") {
                    TextField("OA1MJ…", text: $k)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("手机只是那间房的一扇窗：能看她说话、能发话过去。\n工具审批、改设置这些，仍然只能在电脑那边做。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        base = b.trimmingCharacters(in: .whitespacesAndNewlines)
                        token = k.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear { b = base; k = token }
        }
    }
}
