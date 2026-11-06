import SwiftUI

/// 0.3 的主界面：打开就是这一轮对话，不再先给一张会话列表。
/// 列表藏在「长按标题」里——找的是一个人，不是去翻通讯录。
struct LampRootView: View {
    @AppStorage("gw_url") private var gwURL = ""
    @AppStorage("gw_key") private var gwKey = ""
    @AppStorage("last_session") private var lastSession = ""

    @State private var sessions: [SessionRow] = []
    @State private var current: SessionRow?
    @State private var showList = false
    @State private var loadError: String?

    var body: some View {
        ZStack {
            LampBackground()
            if let cur = current {
                ChatPane(session: cur,
                         onLongPressTitle: { showList = true },
                         onPick: { picked in
                             current = picked
                             lastSession = picked.id
                         })
                .transition(.opacity)
            } else if let e = loadError {
                VStack(spacing: 14) {
                    Text("连不上").font(.headline)
                    Text(e).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                    Button("再试一次") { Task { await boot() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().tint(.white.opacity(0.6))
            }
        }
        .preferredColorScheme(.dark)
        .task { await boot() }
        .sheet(isPresented: $showList) {
            NavigationStack {
                SessionListView(onPick: { picked in
                    current = picked
                    lastSession = picked.id
                    showList = false
                })
                    .navigationTitle("会话")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关") { showList = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func boot() async {
        loadError = nil
        do {
            let list = try await API.shared.sessions()
            sessions = list
            guard !list.isEmpty else { return }
            if let pick = list.first(where: { $0.id == lastSession }) {
                current = pick
            } else {
                current = list.first
                lastSession = list.first!.id
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// 底色：近黑的屋子，底部一团很淡的暖光。不抢字。
struct LampBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.031, green: 0.039, blue: 0.063)
            RadialGradient(
                colors: [Color(red: 0.19, green: 0.16, blue: 0.13).opacity(0.55), .clear],
                center: UnitPoint(x: 0.5, y: 0.92),
                startRadius: 10,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}
