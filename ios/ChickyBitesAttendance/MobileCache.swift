import Foundation

struct MobileCacheSnapshot: Codable {
    let userId: String
    let selectedBranchId: String?
    let branches: [Branch]
    let employees: [Employee]
    let attendanceDays: [AttendanceDay]
    let leaves: [LeaveRecord]
    let shifts: [ShiftRosterEntry]
    let notifications: [AppNotification]
    let savedAt: Date
}

enum MobileCache {
    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("employee-hub-cache.json")
    }

    static func load(userId: String) -> MobileCacheSnapshot? {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(MobileCacheSnapshot.self, from: data),
              snapshot.userId == userId,
              Date().timeIntervalSince(snapshot.savedAt) < 7 * 24 * 60 * 60 else { return nil }
        return snapshot
    }

    static func save(_ snapshot: MobileCacheSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() {
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
