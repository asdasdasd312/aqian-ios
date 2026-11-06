import SwiftUI
import UIKit
import UserNotifications

final class PushBridge: NSObject, ObservableObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var shared = PushBridge()

    override init() {
        super.init()
        PushBridge.shared = self
    }

    @Published var token: String = UserDefaults.standard.string(forKey: "apns_token") ?? ""
    @Published var status: String = "未申请"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func ask() {
        status = "申请中…"
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.status = "被拒：\(err.localizedDescription)"
                    return
                }
                guard ok else {
                    self.status = "你没允许通知"
                    return
                }
                UIApplication.shared.registerForRemoteNotifications()
                self.status = "已申请，等 token…"
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            self.token = hex
            self.status = "拿到 token（\(hex.count / 2) 字节）"
            UserDefaults.standard.set(hex, forKey: "apns_token")
            Task {
                do {
                    try await API.shared.registerPush(hex)
                    await MainActor.run { self.status = "token 已交给我这边" }
                } catch {
                    await MainActor.run { self.status = "token 拿到了，但没传上来" }
                }
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DispatchQueue.main.async {
            self.status = "注册失败：\(error.localizedDescription)"
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
