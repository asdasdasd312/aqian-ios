import SwiftUI
import UIKit
import UserNotifications

/// 只放状态，给界面看。不做 delegate，避免和 SwiftUI 的 delegate 实例打架。
final class PushState: ObservableObject {
    static let shared = PushState()
    @Published var token: String = UserDefaults.standard.string(forKey: "apns_token") ?? ""
    @Published var status: String = "未申请"
}

/// 真正的 delegate。SwiftUI 用 @UIApplicationDelegateAdaptor 创建它。
final class PushBridge: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if !PushState.shared.token.isEmpty {
            PushState.shared.status = "有旧 token（\(PushState.shared.token.count / 2) 字节）"
        }
        return true
    }

    static func ask() {
        PushState.shared.status = "申请中…"
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, err in
            DispatchQueue.main.async {
                if let err = err {
                    PushState.shared.status = "被拒：\(err.localizedDescription)"
                    return
                }
                guard ok else {
                    PushState.shared.status = "你没允许通知"
                    return
                }
                UIApplication.shared.registerForRemoteNotifications()
                PushState.shared.status = "已申请，等 token…"
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            PushState.shared.token = hex
            PushState.shared.status = "拿到 token（\(hex.count / 2) 字节）"
            UserDefaults.standard.set(hex, forKey: "apns_token")
        }
        Task {
            do {
                try await API.shared.registerPush(hex)
                await MainActor.run { PushState.shared.status = "token 已交给我这边" }
            } catch {
                await MainActor.run { PushState.shared.status = "token 拿到了，但没传上来" }
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DispatchQueue.main.async {
            PushState.shared.status = "注册失败：\(error.localizedDescription)"
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
