import CryptoKit
import Foundation
import Security
import UIKit

struct OfflineAttendanceRequest: Codable, Identifiable, Sendable {
    var id: String { requestId }
    let mode: String
    let requestId, branchId, eventType, deviceId, capturedAt, challengeAction: String
    let latitude, longitude, gpsAccuracyM: Double
    let isSimulated, isProducedByAccessory: Bool
    let descriptor: [Float]
    let signedPayload, signature: String
}

struct SignedBiometricAssertion: Codable, Sendable {
    let signedPayload: String
    let signature: String
}

actor AttendanceEvidenceVault {
    static let shared = AttendanceEvidenceVault()
    private let service = "pk.com.chickybites.employeehub.attendance-evidence"
    private let signingAccount = "device-signing-key"
    private let encryptionAccount = "offline-queue-key"

    func devicePublicKey() throws -> String {
        try signingKey().publicKey.rawRepresentation.base64EncodedString()
    }

    func prepare(
        branchId: String,
        eventType: String,
        deviceId: String,
        capturedAt: Date,
        location: LocationSnapshot,
        challengeAction: String,
        descriptor: [Float]
    ) throws -> OfflineAttendanceRequest {
        guard descriptor.count == 512 else { throw BackendError.invalidInput("The face evidence is incomplete.") }
        let requestId = UUID().uuidString
        let timestamp = ISO8601DateFormatter().string(from: capturedAt)
        let digest = SHA256.hash(data: canonicalDescriptor(descriptor).data(using: .utf8)!)
            .map { String(format: "%02x", $0) }.joined()
        let payload = [
            requestId, branchId, eventType, timestamp,
            fixed(location.latitude, digits: 7), fixed(location.longitude, digits: 7),
            fixed(location.accuracy, digits: 1), challengeAction, digest
        ].joined(separator: "|")
        let signature = try signingKey().signature(for: Data(payload.utf8)).derRepresentation.base64EncodedString()
        return OfflineAttendanceRequest(
            mode: "offline_sync", requestId: requestId, branchId: branchId, eventType: eventType,
            deviceId: deviceId, capturedAt: timestamp, challengeAction: challengeAction,
            latitude: location.latitude, longitude: location.longitude, gpsAccuracyM: location.accuracy,
            isSimulated: location.isSimulated, isProducedByAccessory: location.isProducedByAccessory,
            descriptor: descriptor, signedPayload: payload, signature: signature
        )
    }

    func signBiometricChallenge(challengeId:String,branchId:String,deviceId:String,action:String,descriptor:[Float],liveness:BiometricLivenessEvidence) throws -> SignedBiometricAssertion {
        guard descriptor.count==512 else { throw BackendError.invalidInput("The face evidence is incomplete.") }
        let digest=SHA256.hash(data:canonicalDescriptor(descriptor).data(using:.utf8)!).map{String(format:"%02x",$0)}.joined()
        let payload=[challengeId,branchId,deviceId,action,digest,liveness.canonicalString].joined(separator:"|")
        let signature=try signingKey().signature(for:Data(payload.utf8)).derRepresentation.base64EncodedString()
        return SignedBiometricAssertion(signedPayload:payload,signature:signature)
    }

    func enqueue(_ request: OfflineAttendanceRequest) throws {
        var requests = try load()
        requests.removeAll { $0.requestId == request.requestId }
        requests.append(request)
        try save(requests)
    }

    func pending() throws -> [OfflineAttendanceRequest] { try load() }

    func remove(id: String) throws {
        try save(try load().filter { $0.requestId != id })
    }

    func count() -> Int { (try? load().count) ?? 0 }

    private func canonicalDescriptor(_ descriptor: [Float]) -> String {
        descriptor.map { fixed(Double($0), digits: 6) }.joined(separator: ",")
    }

    private func fixed(_ value: Double, digits: Int) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
    }

    private func signingKey() throws -> P256.Signing.PrivateKey {
        if let stored = KeychainBlob.read(service: service, account: signingAccount),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: stored) { return key }
        let key = P256.Signing.PrivateKey()
        try KeychainBlob.write(key.rawRepresentation, service: service, account: signingAccount)
        return key
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let stored = KeychainBlob.read(service: service, account: encryptionAccount), stored.count == 32 {
            return SymmetricKey(data: stored)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try KeychainBlob.write(data, service: service, account: encryptionAccount)
        return key
    }

    private func load() throws -> [OfflineAttendanceRequest] {
        guard let data = try? Data(contentsOf: queueURL), !data.isEmpty else { return [] }
        let box = try AES.GCM.SealedBox(combined: data)
        return try JSONDecoder().decode([OfflineAttendanceRequest].self, from: AES.GCM.open(box, using: encryptionKey()))
    }

    private func save(_ requests: [OfflineAttendanceRequest]) throws {
        if requests.isEmpty { try? FileManager.default.removeItem(at: queueURL); return }
        let encoded = try JSONEncoder().encode(requests)
        guard let combined = try AES.GCM.seal(encoded, using: encryptionKey()).combined else {
            throw BackendError.invalidInput("Offline attendance could not be protected.")
        }
        try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try combined.write(to: queueURL, options: [.atomic, .completeFileProtection])
    }

    private var queueURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CBEmployeeHub", isDirectory: true).appendingPathComponent("offline-attendance.bin")
    }
}

nonisolated private enum KeychainBlob {
    static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw BackendError.invalidInput("This iPhone could not create a protected attendance key.")
        }
    }
}

enum BackgroundFileLoader {
    nonisolated static func data(from url: URL, maximumBytes: Int = 15_000_000) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > maximumBytes { throw BackendError.invalidInput("Choose a file smaller than 15 MB.") }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }.value
    }
}
