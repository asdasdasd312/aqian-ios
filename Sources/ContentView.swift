import SwiftUI

struct ContentView: View {
    /// 默认地址：我现在那台电脑的临时隧道。换网络/重启隧道后要在这里改，
    /// 或者点右上角的齿轮改成新地址（存进 UserDefaults，下次打开还在）。
    static let defaultURL = "about:blank"

    @AppStorage("bridge_url") private var urlString: String = ContentView.defaultURL
    @State private var showSettings = false
    @State private var isLoading = false
    @State private var failed = false
    @State private var reloadToken = 0

    private var url: URL {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw) ?? URL(string: ContentView.defaultURL)!
        }
        return URL(string: "https://" + raw) ?? URL(string: ContentView.defaultURL)!
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WebView(url: url, isLoading: $isLoading, failed: $failed, reloadToken: reloadToken)
                    .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }

                if failed {
                    VStack(spacing: 14) {
                        Text("连不上")
                            .font(.headline)
                        Text("地址可能换了。点下面的按钮改成新的。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("改地址") { showSettings = true }
                            .buttonStyle(.borderedProminent)
                        Button("再试一次") { reloadToken += 1 }
                            .buttonStyle(.bordered)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.top, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    Button {
                        reloadToken += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(9)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(9)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.top, 6)
                .padding(.trailing, 10)
                .opacity(0.55)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(urlString: $urlString, onSave: {
                    failed = false
                    reloadToken += 1
                })
            }
        }
    }
}
