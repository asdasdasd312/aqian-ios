import SwiftUI
import WebKit
import UIKit

/// 外壳里那台浏览器：加载页面、下拉刷新、加载失败时说清是哪种失败。
struct NearWebView: UIViewRepresentable {
    let url: URL
    @Binding var state: LoadState
    var reloadToken: Int

    enum LoadState: Equatable {
        case idle
        case loading
        case ok
        case failed(code: Int, text: String)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.applicationNameForUserAgent = "AqianNear/1.0"
        // 让页面自己的 localStorage 能长久留下来（钥匙第一次进去后就靠它）
        cfg.websiteDataStore = .default()

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.scrollView.keyboardDismissMode = .interactive
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.020, green: 0.027, blue: 0.039, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.allowsBackForwardNavigationGestures = false

        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(red: 0.85, green: 0.64, blue: 0.36, alpha: 1)
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pulled(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh

        context.coordinator.loadedURL = url
        context.coordinator.web = web
        web.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            web.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
            return
        }
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            web.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: NearWebView
        var lastToken = 0
        var loadedURL: URL?
        weak var web: WKWebView?

        init(_ parent: NearWebView) {
            self.parent = parent
        }

        @objc func pulled(_ sender: UIRefreshControl) {
            guard let host = web else {
                sender.endRefreshing()
                return
            }
            parent.state = .loading
            if host.url == nil {
                host.load(URLRequest(url: parent.url, timeoutInterval: 20))
            } else {
                host.reload()
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.state = .loading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.state = .ok
            webView.scrollView.refreshControl?.endRefreshing()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            webViewRefreshEnd()
            let ns = error as NSError
            // -999 是我自己打断的（比如换地址重载），不算失败
            if ns.code == NSURLErrorCancelled { return }
            parent.state = .failed(code: ns.code, text: NearWebView.describe(ns))
        }

        private func webViewRefreshEnd() {
            web?.scrollView.refreshControl?.endRefreshing()
        }

        // 页面里要开新窗口（target=_blank），就在同一个视图里打开，不要弹空白
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = navigationAction.request.url, navigationAction.targetFrame == nil {
                webView.load(URLRequest(url: u))
            }
            return nil
        }
    }

    /// 把系统那串英文错误码翻成“到底哪一步断了”。
    static func describe(_ e: NSError) -> String {
        switch e.code {
        case NSURLErrorNotConnectedToInternet: return "手机没有网络"
        case NSURLErrorTimedOut: return "等了 20 秒没回话（网络慢，或者服务没开）"
        case NSURLErrorCannotFindHost: return "找不到这个域名（域名解析失败）"
        case NSURLErrorCannotConnectToHost: return "域名解析到了，但端口连不上（隧道可能断了）"
        case NSURLErrorNetworkConnectionLost: return "连着连着断了（多半是隧道掉线）"
        case NSURLErrorSecureConnectionFailed: return "HTTPS 握手失败（证书问题）"
        case NSURLErrorServerCertificateUntrusted: return "证书不被信任"
        case NSURLErrorHTTPTooManyRedirects: return "跳转次数太多（地址被反复重定向）"
        default: return "\(e.localizedDescription)（code \(e.code)）"
        }
    }
}
