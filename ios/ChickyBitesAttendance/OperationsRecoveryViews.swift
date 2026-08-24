import SwiftUI

struct DiagnosticFeedView: View {
    @Environment(AppSession.self) private var session
    @State private var selectedEvent: MobileDiagnosticEvent?

    var body: some View {
        @Bindable var session = session
        CreamPage {
            ScrollView {
                LazyVStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Diagnostics", subtitle: "Open an error to see its screen, build, device, time, and recommended action.", symbol: "stethoscope")
                        Picker(L10n.text("Severity"), selection: $session.diagnosticSeverity) {
                            Text(L10n.text("All")).tag(String?.none)
                            Text(L10n.text("Crashes")).tag(String?.some("crash"))
                            Text(L10n.text("Errors")).tag(String?.some("error"))
                            Text(L10n.text("Warnings")).tag(String?.some("warning"))
                            Text(L10n.text("Information")).tag(String?.some("info"))
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.info.opacity(0.05))

                    if session.diagnosticEventsIsLoading && session.diagnosticEvents.isEmpty {
                        LoadingStateCard(title: "Loading diagnostics", message: "Getting the latest app errors…")
                    } else if session.diagnosticEvents.isEmpty {
                        EmptyState(symbol: "checkmark.shield.fill", title: "No diagnostics found", message: "No matching app errors were recorded for this branch.")
                    } else {
                        ForEach(session.diagnosticEvents) { event in
                            Button { selectedEvent = event } label: { DiagnosticEventRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    }

                    if session.diagnosticEventsHaveMore {
                        Button { Task { await session.loadDiagnosticFeed(reset: false) } } label: {
                            Label(L10n.text("Load Older Diagnostics"), systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.bordered).disabled(session.diagnosticEventsIsLoading)
                    }
                    if session.diagnosticEventsIsLoading && !session.diagnosticEvents.isEmpty { ProgressView().padding() }
                }
                .padding(16).padding(.bottom, 24)
            }
            .refreshable { await session.loadDiagnosticFeed() }
        }
        .navigationTitle(L10n.text("Diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .task(id: "\(session.selectedBranchId ?? "")-\(session.diagnosticSeverity ?? "all")") { await session.loadDiagnosticFeed() }
        .sheet(item: $selectedEvent) { DiagnosticEventDetail(event: $0) }
        .diagnosticScreen("Diagnostics")
    }
}

private struct DiagnosticEventRow: View {
    let event: MobileDiagnosticEvent
    private var color: Color { event.severity == "crash" ? CBTheme.danger : event.severity == "error" ? CBTheme.warning : event.severity == "warning" ? CBTheme.orange : CBTheme.info }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: event.severity == "crash" ? "bolt.trianglebadge.exclamationmark.fill" : "exclamationmark.bubble.fill")
                .foregroundStyle(color).frame(width: 42, height: 42).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(L10n.text(event.screen ?? event.category.sentenceCased)).font(.headline);Spacer();Text(L10n.text(event.severity.sentenceCased)).font(.caption2.weight(.bold)).foregroundStyle(color) }
                Text(event.message).font(.subheadline).foregroundStyle(CBTheme.muted).lineLimit(2)
                Text("\(recoveryDate(event.occurredAt)) • \(L10n.text("Build")) \(event.buildVersion)").font(.caption2).foregroundStyle(CBTheme.muted)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(CBTheme.muted)
        }
        .padding(16).cbGlass(cornerRadius: 21, tint: color.opacity(0.035))
    }
}

private struct DiagnosticEventDetail: View {
    @Environment(\.dismiss) private var dismiss
    let event: MobileDiagnosticEvent

    var body: some View {
        NavigationStack {
            CreamPage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: event.screen ?? event.category.sentenceCased, subtitle: event.message, symbol: "exclamationmark.triangle.fill")
                            if let code=event.errorCode { Text(code).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(CBTheme.danger) }
                        }.padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.danger.opacity(0.05))
                        VStack(spacing: 0) {
                            DiagnosticDetailRow(title: "Severity", value: event.severity.sentenceCased)
                            DiagnosticDetailRow(title: "Affected screen", value: event.screen ?? "Unknown")
                            DiagnosticDetailRow(title: "Build", value: event.buildVersion)
                            DiagnosticDetailRow(title: "Device model", value: event.modelIdentifier)
                            DiagnosticDetailRow(title: "iOS version", value: event.osVersion)
                            DiagnosticDetailRow(title: "Time", value: recoveryDate(event.occurredAt))
                            DiagnosticDetailRow(title: "Device reference", value: event.deviceId)
                        }.padding(.horizontal,18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.07))
                        VStack(alignment:.leading,spacing:10) {
                            SectionTitle(title:"Suggested action",symbol:"lightbulb.fill")
                            Text(L10n.text(event.suggestedAction)).font(.subheadline).foregroundStyle(CBTheme.text).fixedSize(horizontal:false,vertical:true)
                        }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.warning.opacity(0.06))
                    }.padding(16).padding(.bottom,24)
                }
            }
            .navigationTitle(L10n.text("Diagnostic Detail")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction){Button(L10n.text("Done")){dismiss()}} }
        }
    }
}

private struct DiagnosticDetailRow: View {
    let title,value:String
    var body:some View { HStack(alignment:.top){Text(L10n.text(title)).foregroundStyle(CBTheme.muted);Spacer(minLength:20);Text(L10n.text(value)).multilineTextAlignment(.trailing).textSelection(.enabled)}.font(.subheadline).padding(.vertical,13).overlay(alignment:.bottom){Divider().overlay(CBTheme.divider)} }
}

struct NotificationRecoveryView: View {
    @Environment(AppSession.self) private var session
    @State private var confirmingRetryAll=false

    var body: some View {
        CreamPage {
            ScrollView {
                LazyVStack(spacing:14) {
                    VStack(alignment:.leading,spacing:12) {
                        HStack(alignment:.top) {
                            SectionTitle(title:"Notification Recovery",subtitle:"Failed alerts for the organization. Retried alerts are sent by the secure delivery service within one minute.",symbol:"bell.badge.waveform.fill")
                            Spacer()
                            if session.failedPushNotificationsIsLoading || session.notificationRetryIsWorking { ProgressView().tint(CBTheme.orange) }
                        }
                        if !session.failedPushNotifications.isEmpty {
                            Button { confirmingRetryAll=true } label: { Label(L10n.text("Retry All"),systemImage:"arrow.clockwise.circle.fill") }
                                .cbPrimaryButton().disabled(session.notificationRetryIsWorking)
                        }
                    }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.warning.opacity(0.05))

                    if session.failedPushNotificationsIsLoading && session.failedPushNotifications.isEmpty {
                        LoadingStateCard(title:"Loading failed notifications",message:"Checking delivery attempts…")
                    } else if session.failedPushNotifications.isEmpty {
                        EmptyState(symbol:"bell.and.waves.left.and.right.fill",title:"No failed notifications",message:"All recorded push deliveries are healthy or already queued.")
                    } else {
                        ForEach(session.failedPushNotifications) { notification in
                            FailedNotificationCard(notification:notification)
                        }
                    }
                    if session.failedPushNotificationsHaveMore {
                        Button { Task { await session.loadFailedPushNotifications(reset:false) } } label: { Label(L10n.text("Load Older Failures"),systemImage:"clock.arrow.circlepath") }
                            .buttonStyle(.bordered).disabled(session.failedPushNotificationsIsLoading)
                    }
                }.padding(16).padding(.bottom,24)
            }.refreshable{await session.loadFailedPushNotifications()}
        }
        .navigationTitle(L10n.text("Notification Recovery")).navigationBarTitleDisplayMode(.inline)
        .toolbar{StandardToolbar()}
        .task(id:session.selectedBranchId){await session.loadFailedPushNotifications()}
        .confirmationDialog(L10n.text("Retry every failed notification?"),isPresented:$confirmingRetryAll,titleVisibility:.visible) {
            Button(L10n.text("Retry All")){Task{await session.retryAllFailedPushNotifications()}}
            Button(L10n.text("Cancel"),role:.cancel){}
        } message:{Text(L10n.text("They will be queued for the next secure delivery cycle."))}
        .diagnosticScreen("Notification Recovery")
    }
}

private struct FailedNotificationCard: View {
    @Environment(AppSession.self) private var session
    let notification:FailedPushNotification

    var body:some View {
        VStack(alignment:.leading,spacing:11) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text(notification.title).font(.headline)
                    Text(notification.recipientCode.map{"\($0) • \(notification.recipientName)"} ?? notification.recipientName).font(.caption).foregroundStyle(CBTheme.muted)
                }
                Spacer();Text(L10n.format("%lld attempts",Int64(notification.pushAttempts))).font(.caption2.weight(.bold)).foregroundStyle(CBTheme.danger)
            }
            Text(notification.message).font(.subheadline).foregroundStyle(CBTheme.text)
            Text(notification.pushLastError).font(.caption.monospaced()).foregroundStyle(CBTheme.danger).textSelection(.enabled)
            HStack {
                Text(recoveryDate(notification.createdAt)).font(.caption).foregroundStyle(CBTheme.muted)
                Spacer()
                Button { Task { await session.retryFailedPushNotification(notification) } } label: { Label(L10n.text("Retry"),systemImage:"arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(CBTheme.orange).disabled(session.notificationRetryIsWorking)
            }
        }.padding(16).cbGlass(cornerRadius:21,tint:CBTheme.danger.opacity(0.035))
    }
}

private func recoveryDate(_ value:String)->String {
    let fractional=ISO8601DateFormatter();fractional.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    guard let date=fractional.date(from:value) ?? ISO8601DateFormatter().date(from:value) else{return value}
    return L10n.date(date,dateStyle:.medium,timeStyle:.short)
}
