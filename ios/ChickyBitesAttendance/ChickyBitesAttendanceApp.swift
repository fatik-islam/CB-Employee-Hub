import SwiftUI

@main
struct ChickyBitesAttendanceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession()
    @AppStorage("cb.appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.english.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var language: AppLanguage { AppLanguage(rawValue: storedLanguage) ?? .english }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.layoutDirection)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .tint(CBTheme.orange)
                .onReceive(NotificationCenter.default.publisher(for: .didReceivePushToken)) { notification in
                    guard let token = notification.object as? String else { return }
                    Task { await session.registerPushToken(token) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await session.appDidBecomeActive() } }
                }
        }
    }
}
