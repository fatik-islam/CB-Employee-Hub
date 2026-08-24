import Foundation
import MetricKit
import OSLog
import SwiftUI
import UIKit

struct PendingDiagnostic: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let severity, category, message, buildVersion, osVersion, modelIdentifier, deviceId, occurredAt: String
    let screen, errorCode, payloadText: String?
}

actor DiagnosticQueue {
    static let shared = DiagnosticQueue()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var fileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("diagnostic-queue.json")
    }

    func enqueue(_ diagnostic: PendingDiagnostic) {
        var values = load()
        values.append(diagnostic)
        if values.count > 40 { values.removeFirst(values.count - 40) }
        save(values)
    }

    func pending() -> [PendingDiagnostic] { load() }

    func remove(ids: Set<UUID>) {
        save(load().filter { !ids.contains($0.id) })
    }

    private func load() -> [PendingDiagnostic] {
        guard let fileURL, let data=try? Data(contentsOf:fileURL) else{return []}
        return (try? decoder.decode([PendingDiagnostic].self,from:data)) ?? []
    }

    private func save(_ values:[PendingDiagnostic]) {
        guard let fileURL,let data=try? encoder.encode(values) else{return}
        try? data.write(to:fileURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}

final class AppDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = AppDiagnostics()
    private let logger = Logger(subsystem:"pk.com.chickybites.employeehub",category:"diagnostics")
    private var started=false

    func start() {
        guard !started else{return}
        started=true
        MXMetricManager.shared.add(self)
        captureBreadcrumb("Application launched",category:"lifecycle")
    }

    nonisolated func didReceive(_ payloads:[MXDiagnosticPayload]) {
        // MetricKit invokes subscribers on its own serial queue. This callback
        // must remain nonisolated under Swift 6; otherwise the generated
        // Objective-C witness traps before the method body can run.
        let payloadTexts=payloads.map { String(data:$0.jsonRepresentation(),encoding:.utf8) }
        Task { @MainActor [weak self] in
            guard let self else{return}
            for json in payloadTexts {
                enqueue(severity:"crash",category:"metric-kit",message:"iOS delivered a crash or termination diagnostic from a previous app session.",errorCode:"MXDiagnosticPayload",payloadText:json)
            }
        }
    }

    nonisolated func didReceive(_ payloads:[MXMetricPayload]) {
        guard let payload=payloads.last else{return}
        let payloadText=String(data:payload.jsonRepresentation(),encoding:.utf8)
        Task { @MainActor [weak self] in
            self?.enqueue(severity:"info",category:"metric-kit-performance",message:"iOS delivered an aggregated performance report.",errorCode:"MXMetricPayload",payloadText:payloadText)
        }
    }

    func capture(error:Error,category:String,screen:String?=nil) {
        let nsError=error as NSError
        logger.error("\(category,privacy:.public): \(nsError.domain,privacy:.public) \(nsError.code): \(nsError.localizedDescription,privacy:.private(mask:.hash))")
        enqueue(severity:"error",category:category,message:UserFacingError.message(for:error),errorCode:"\(nsError.domain):\(nsError.code)",screen:screen,payloadText:nil)
    }

    func captureBreadcrumb(_ message:String,category:String,screen:String?=nil) {
        logger.info("\(category,privacy:.public): \(message,privacy:.public)")
        enqueue(severity:"info",category:category,message:message,screen:screen,payloadText:nil)
    }

    private func enqueue(severity:String,category:String,message:String,errorCode:String?=nil,screen:String?=nil,payloadText:String?) {
        let value=PendingDiagnostic(
            id:UUID(),severity:severity,category:category,message:String(message.prefix(1000)),
            buildVersion:Self.buildVersion,osVersion:UIDevice.current.systemVersion,
            modelIdentifier:Self.modelIdentifier,deviceId:DeviceIdentity.value,
            occurredAt:ISO8601DateFormatter().string(from:.now),
            screen:screen ?? UserDefaults.standard.string(forKey:"cb.lastScreen"),errorCode:errorCode,
            payloadText:payloadText.map{String($0.prefix(262_144))}
        )
        Task { await DiagnosticQueue.shared.enqueue(value) }
    }

    private static var buildVersion:String {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown"
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    private static var modelIdentifier:String {
        var systemInfo=utsname();uname(&systemInfo)
        return withUnsafePointer(to:&systemInfo.machine) {
            $0.withMemoryRebound(to:CChar.self,capacity:1) { String(cString:$0) }
        }
    }
}

private struct DiagnosticScreenModifier:ViewModifier {
    let name:String
    func body(content:Content)->some View {
        content
            .onAppear{UserDefaults.standard.set(name,forKey:"cb.lastScreen")}
            .onDisappear{if UserDefaults.standard.string(forKey:"cb.lastScreen")==name{UserDefaults.standard.removeObject(forKey:"cb.lastScreen")}}
    }
}

extension View {
    func diagnosticScreen(_ name:String)->some View { modifier(DiagnosticScreenModifier(name:name)) }
}
