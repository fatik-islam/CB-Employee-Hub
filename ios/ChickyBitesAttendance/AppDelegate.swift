import UIKit
import UserNotifications
import BackgroundTasks

extension Notification.Name {
    static let didReceivePushToken = Notification.Name("cb.didReceivePushToken")
    static let didReceivePushRoute = Notification.Name("cb.didReceivePushRoute")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppDiagnostics.shared.start()
        BGTaskScheduler.shared.register(forTaskWithIdentifier:BackgroundRecoveryCoordinator.taskIdentifier,using:nil){ task in
            guard let refreshTask=task as? BGAppRefreshTask else{task.setTaskCompleted(success:false);return}
            BackgroundRecoveryCoordinator.schedule()
            let work=Task { @MainActor in
                let succeeded=await BackgroundRecoveryCoordinator.shared.run()
                refreshTask.setTaskCompleted(success:succeeded)
            }
            refreshTask.expirationHandler={work.cancel()}
        }
        return true
    }

    func applicationDidEnterBackground(_ application:UIApplication) {
        BackgroundRecoveryCoordinator.schedule()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .didReceivePushToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("Push registration unavailable: \(error.localizedDescription)")
        #endif
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let category = (info["category"] as? String) ?? (info["type"] as? String) ?? "updates"
        await MainActor.run {
            NotificationCenter.default.post(name: .didReceivePushRoute, object: category)
        }
    }
}
