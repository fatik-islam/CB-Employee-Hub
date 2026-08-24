import BackgroundTasks
import Foundation

@MainActor
final class BackgroundRecoveryCoordinator {
    static let shared=BackgroundRecoveryCoordinator()
    nonisolated static let taskIdentifier="pk.com.chickybites.employeehub.recovery"
    var operation:(() async -> Bool)?

    func run() async ->Bool { await operation?() ?? true }

    nonisolated static func schedule() {
        let request=BGAppRefreshTaskRequest(identifier:taskIdentifier)
        request.earliestBeginDate=Date(timeIntervalSinceNow:15*60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
