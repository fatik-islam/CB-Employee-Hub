import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.isRestoringSession || session.isEstablishingSession {
                SessionLoadingView()
            } else {
                switch session.access {
                case .signedOut: LoginView()
                case .authenticated, .demo: AppShellView()
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: session.access)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-demo") { session.enterDemo(); return }
            if ProcessInfo.processInfo.arguments.contains("--ui-demo-salary") { session.enterDemo(role:"employee"); return }
            if ProcessInfo.processInfo.arguments.contains("--ui-demo-employee") { session.enterDemo(role:"employee"); return }
            #endif
            if case .signedOut = session.access { await session.restoreSession() }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(L10n.text(session.errorMessage ?? ""))
        }
        .overlay(alignment: .top) {
            if let message = session.successMessage ?? session.noticeMessage {
                StatusToast(message: message, isNotice: session.successMessage == nil)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(session.successMessage == nil ? 4.5 : 2.6))
                        withAnimation {
                            session.successMessage = nil
                            session.noticeMessage = nil
                        }
                    }
            }
        }
    }
}

private struct SessionLoadingView: View {
    var body: some View {
        BrandedBackground {
            VStack(spacing: 18) {
                BrandLockup(onDarkBackground: true)
                ProgressView()
                    .controlSize(.large)
                    .tint(CBTheme.orange)
                    .accessibilityLabel("Loading your account")
            }
        }
    }
}

private struct StatusToast: View {
    let message: String
    let isNotice: Bool
    var body: some View {
        Label(L10n.text(message), systemImage: isNotice ? "exclamationmark.arrow.triangle.2.circlepath" : "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isNotice ? CBTheme.warning : CBTheme.success)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .cbGlass(cornerRadius: 18, tint: (isNotice ? CBTheme.warning : CBTheme.success).opacity(0.14))
    }
}

struct AppShellView: View {
    @Environment(AppSession.self) private var session
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.english.rawValue
    @State private var selectedTab = AppTab.overview

    private enum AppTab: Hashable { case overview, attendance, team, leave, salary, more }

    var body: some View {
        Group {
            if session.branches.isEmpty && !session.isDemo {
                JoinTeamView()
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack { DashboardView() }
                        .tag(AppTab.overview)
                        .tabItem { Label("Overview", systemImage: "square.grid.2x2.fill") }
                    NavigationStack { AttendanceView() }
                        .tag(AppTab.attendance)
                        .tabItem { Label("Attendance", systemImage: "location.circle.fill") }
                    if session.role.canManagePeople {
                        NavigationStack { EmployeesView() }
                            .tag(AppTab.team)
                            .tabItem { Label("Team", systemImage: "person.2.fill") }
                    }
                    NavigationStack { LeavesView() }
                        .tag(AppTab.leave)
                        .tabItem { Label("Leave", systemImage: "calendar.badge.clock") }
                    if !session.role.canManagePeople {
                        NavigationStack { PayrollView() }
                            .tag(AppTab.salary)
                            .tabItem { Label("Salary", systemImage: "banknote.fill") }
                    }
                    NavigationStack { MoreHubView() }
                        .tag(AppTab.more)
                        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                }
                .id(storedLanguage)
                .tint(CBTheme.orange)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-demo-salary") { selectedTab = .salary }
            #endif
            // Sign-in and session restoration already refresh the app. Only
            // recover here when the shell has no cached or freshly loaded data.
            if !session.isDemo && session.branches.isEmpty { await session.refreshSafely() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushRoute)) { notification in
            let category = notification.object as? String ?? ""
            switch category {
            case "attendance": selectedTab = .attendance
            case "leave": selectedTab = .leave
            case "payroll" where !session.role.canManagePeople: selectedTab = .salary
            case "employee" where session.role.canManagePeople: selectedTab = .team
            default: selectedTab = .more
            }
        }
    }
}

private struct MoreHubView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.currentUser?.fullName ?? "Account")
                            .font(.title2.bold())
                        Text("\(session.role.title) • \(session.selectedBranch?.name ?? "CB Employee Hub")")
                            .font(.subheadline)
                            .foregroundStyle(CBTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .cbGlass(cornerRadius: 24, tint: CBTheme.orange.opacity(0.07))

                    VStack(spacing: 0) {
                        MoreLink(title: "Account & Security", symbol: "person.badge.key.fill") { AccountPreferencesView() }
                        MoreLink(title: "Notifications & Reports", symbol: "bell.badge.fill", badge: session.notifications.filter { !$0.isRead }.count) { OperationsCenterView() }
                        MoreLink(title: "Attendance History", symbol: "calendar.badge.clock") { AttendanceHistoryView() }
                        MoreLink(title: "Workforce", symbol: "person.2.badge.gearshape.fill") { WorkforceOperationsView() }
                        if session.role.canManagePeople {
                            MoreLink(title:"Schedules",symbol:"calendar.badge.clock") { ScheduleManagementView() }
                        }
                        if session.role.canManagePeople {
                            MoreLink(title: "Salary & Payroll", symbol: "banknote.fill") { PayrollView() }
                        }
                        if session.role.isAdministrator {
                            MoreLink(title: "Branch Settings", symbol: "building.2.badge.gearshape.fill") { BranchSettingsView() }
                        }
                        if session.role == .owner {
                            MoreLink(title: "Setup Checklist", symbol: "checklist") { OwnerSetupChecklistView() }
                            MoreLink(title: "Operations Health", symbol: "waveform.path.ecg.rectangle") { OperationsHealthView() }
                        }
                        MoreLink(title: "Help & Guides", symbol: "questionmark.circle.fill") { HelpCenterView() }
                    }
                    .cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

                    if !session.isConnected || session.offlineAttendanceCount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Sync status", symbol: session.isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash")
                            Text(session.offlineSyncMessage.map { L10n.text($0) } ?? (session.isConnected ? "\(session.offlineAttendanceCount) \(L10n.text("protected attendance records are waiting to sync."))" : L10n.text("You are offline. Existing information remains available and attendance evidence will be protected on this iPhone.")))
                                .font(.subheadline).foregroundStyle(CBTheme.muted)
                            Button("Try Sync Now", systemImage: "arrow.clockwise") { Task { await session.syncOfflineAttendance() } }
                                .buttonStyle(.bordered).disabled(!session.isConnected)
                        }
                        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.warning.opacity(0.07))
                    }

                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        Task { await session.signOut() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16).padding(.bottom, 24)
            }
        }
        .navigationTitle(L10n.text("More"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
    }
}

private struct MoreLink<Destination: View>: View {
    let title: String
    let symbol: String
    var badge = 0
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 13) {
                Image(systemName: symbol).foregroundStyle(CBTheme.orange).frame(width: 26)
                Text(L10n.text(title)).font(.body.weight(.semibold)).foregroundStyle(CBTheme.text)
                Spacer()
                if badge > 0 { Text("\(badge)").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).background(CBTheme.orange, in: Capsule()) }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(CBTheme.muted)
            }
            .padding(.horizontal, 18).frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(L10n.text(title)), \(badge) \(L10n.text("unread"))" : L10n.text(title))
    }
}

private struct JoinTeamView: View {
    @Environment(AppSession.self) private var session
    @State private var code = ""

    var body: some View {
        BrandedBackground {
            VStack(spacing: 22) {
                BrandLockup(onDarkBackground: true)
                VStack(spacing: 16) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(CBTheme.orange)
                    Text("Join your team").font(.title.bold()).foregroundStyle(.white)
                    Text("Ask your owner or HR manager for the one-time invite code created for your email address.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding().background(CBTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    Button("Link Employee Account") { Task { _ = await session.claimInvite(code: code) } }
                        .cbPrimaryButton().disabled(code.count < 8)
                    Button("Sign Out") { Task { await session.signOut() } }.cbSecondaryButton().foregroundStyle(.white)
                }
                .padding(26).frame(maxWidth: 440)
                .cbGlass(cornerRadius: 30, tint: .white.opacity(0.06))
            }
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            LanguageToggle(onDarkBackground: true)
                .padding(.top, 10)
                .padding(.trailing, 16)
        }
    }
}

struct StandardToolbar: ToolbarContent {
    @Environment(AppSession.self) private var session
    @AppStorage("cb.appearance") private var appearance = AppAppearance.system.rawValue

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { BrandLockup(compact: true) }
        ToolbarItemGroup(placement: .topBarTrailing) {
            LanguageToggle()
            Menu {
                Section {
                    Label(session.currentUser?.fullName ?? "Account", systemImage: "person.crop.circle.fill")
                    Text(session.role.title)
                }
                if session.branches.count > 1 {
                    Section("Branch") {
                        ForEach(session.branches) { branch in
                            Button { session.selectBranch(branch.id) } label: {
                                if branch.id == session.selectedBranch?.id { Label(branch.name, systemImage: "checkmark") }
                                else { Text(branch.name) }
                            }
                        }
                    }
                }
                Menu("Appearance", systemImage: "circle.lefthalf.filled") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option.rawValue)
                        }
                    }
                }
                NavigationLink {
                    AccountPreferencesView()
                } label: {
                    Label("Account", systemImage: "person.badge.key.fill")
                }
                NavigationLink { OperationsCenterView() } label: { Label("Notifications & Reports",systemImage:"bell.badge.fill") }
                NavigationLink { WorkforceOperationsView() } label: {
                    Label("Workforce Operations", systemImage: "person.2.badge.gearshape.fill")
                }
                if session.role.isAdministrator {
                    NavigationLink {
                        BranchSettingsView()
                    } label: {
                        Label("Branch Settings", systemImage: "building.2.badge.gearshape.fill")
                    }
                }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await session.refreshSafely() } }
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await session.signOut() }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .foregroundStyle(CBTheme.info)
            }
            .accessibilityLabel("Account, theme, and branch menu")
        }
    }
}

private struct AccountPreferencesView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("cb.appearance") private var appearance = AppAppearance.system.rawValue
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var name = ""
    @State private var phone = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var resetStarted = false
    @State private var resetVerified = false
    @State private var deletionReason = ""
    @State private var confirmingDeletion = false
    @State private var preferences:NotificationPreferences?
    @State private var quietHoursEnabled=false
    @State private var quietStart=Calendar.current.date(bySettingHour:22,minute:0,second:0,of:.now) ?? .now
    @State private var quietEnd=Calendar.current.date(bySettingHour:7,minute:0,second:0,of:.now) ?? .now

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Account", symbol: "person.crop.circle.fill")
                        TextField("Full name",text:$name).textFieldStyle(.roundedBorder)
                        TextField("Phone",text:$phone).textFieldStyle(.roundedBorder).keyboardType(.phonePad)
                        InfoRow(symbol: "envelope.fill", title: "Email", value: session.currentUser?.email ?? "—")
                        InfoRow(symbol: "checkmark.shield.fill", title: "Role", value: session.role.title, color: CBTheme.success)
                        Button("Save Account") { Task{_ = await session.updateAccount(name:name,phone:phone)} }.cbPrimaryButton().disabled(name.count<2)
                    }
                    .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.1))

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Appearance", subtitle: "Use your iPhone setting or select a permanent theme.", symbol: "paintpalette.fill")
                        Picker("Appearance", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { option in Text(option.title).tag(option.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.1))

                    VStack(alignment:.leading,spacing:14) {
                        SectionTitle(title:"Password & notifications",symbol:"lock.shield.fill")
                        if !resetStarted {
                            Button("Change Password") { Task{if await session.beginPasswordReset(email:session.currentUser?.email ?? ""){resetStarted=true}} }.buttonStyle(.bordered)
                        } else if !resetVerified {
                            TextField("Reset code",text:$resetCode).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                            Button("Verify Code") { Task{resetVerified=await session.verifyPasswordReset(code:resetCode)} }.cbPrimaryButton().disabled(resetCode.count<4)
                        } else {
                            SecureField("New password",text:$newPassword).textFieldStyle(.roundedBorder)
                            PasswordRequirementPanel(password:newPassword)
                            Button("Update Password") { Task{if await session.finishPasswordReset(newPassword:newPassword){resetStarted=false;resetVerified=false;newPassword=""}} }.cbPrimaryButton().disabled(!PasswordPolicy.isValid(newPassword))
                        }
                        Button("Enable Notifications",systemImage:"bell.badge.fill") { Task{_ = await session.enableNotifications()} }.buttonStyle(.bordered)
                        if let binding=Binding($preferences) {
                            Toggle("Attendance",isOn:binding.attendanceEnabled)
                            Toggle("Shifts",isOn:binding.shiftsEnabled)
                            Toggle("Leave",isOn:binding.leaveEnabled)
                            Toggle("Salary",isOn:binding.payrollEnabled)
                            Toggle("Document expiry",isOn:binding.documentsEnabled)
                            Toggle("Quiet hours",isOn:$quietHoursEnabled)
                            if quietHoursEnabled {
                                HStack { DatePicker("From",selection:$quietStart,displayedComponents:.hourAndMinute);DatePicker("Until",selection:$quietEnd,displayedComponents:.hourAndMinute) }.font(.caption)
                            }
                            Button("Save Notification Preferences"){Task{var value=binding.wrappedValue;let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="HH:mm:ss";value.quietStart=quietHoursEnabled ? formatter.string(from:quietStart):nil;value.quietEnd=quietHoursEnabled ? formatter.string(from:quietEnd):nil;preferences=value;_ = await session.saveNotificationPreferences(value)}}.buttonStyle(.bordered)
                        }
                    }
                    .padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.1))

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Biometric login", subtitle: "Credentials stay encrypted in this iPhone’s Keychain and are invalidated if biometrics change.", symbol: "faceid")
                        if session.hasBiometricLogin {
                            Label("\(session.biometricName) is enabled", systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(CBTheme.success)
                            Button("Remove \(session.biometricName) Login", role: .destructive) { session.disableBiometricLogin() }
                                .buttonStyle(.bordered)
                        } else {
                            PremiumPasswordField(placeholder: "Confirm account password", text: $password, isVisible: $passwordVisible)
                            Button("Enable \(session.biometricName)") {
                                Task { if await session.enableBiometricLogin(password: password) { password = "" } }
                            }
                            .cbPrimaryButton().disabled(password.isEmpty || session.isWorking)
                        }
                    }
                    .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.1))

                    VStack(alignment:.leading,spacing:14) {
                        SectionTitle(title:"Privacy & account deletion",subtitle:"Review what the app uses or permanently remove your account.",symbol:"hand.raised.fill")
                        NavigationLink { PrivacyInformationView() } label: { Label("Privacy Information",systemImage:"doc.text.magnifyingglass") }.buttonStyle(.bordered)
                        TextField("Reason for deletion",text:$deletionReason,axis:.vertical).textFieldStyle(.roundedBorder)
                        Text("Deletion immediately disables this login, push notifications, trusted devices and face enrollment. The deletion request is processed after a 30-day safety period; payroll and audit records required for legal compliance may be retained.")
                            .font(.caption).foregroundStyle(CBTheme.muted).fixedSize(horizontal:false,vertical:true)
                        Button("Delete My Account",role:.destructive){confirmingDeletion=true}.buttonStyle(.bordered).disabled(deletionReason.trimmingCharacters(in:.whitespaces).count<5)
                    }
                    .padding(18).cbGlass(cornerRadius:24,tint:CBTheme.danger.opacity(0.04))
                }
                .padding(16).padding(.bottom, 24)
            }
        }
        .navigationTitle(L10n.text("Account & Security"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear{name=session.currentUser?.fullName ?? "";phone=session.ownEmployee?.phone ?? "";preferences=session.notificationPreferences;loadQuietHours()}
        .confirmationDialog("Permanently delete this account?",isPresented:$confirmingDeletion,titleVisibility:.visible){
            Button("Request Permanent Deletion",role:.destructive){Task{_ = await session.requestAccountDeletion(reason:deletionReason)}}
            Button("Cancel",role:.cancel){}
        }
        .overlay { if session.isWorking { LoadingOverlay() } }
    }

    private func loadQuietHours(){guard let preferences,let start=preferences.quietStart,let end=preferences.quietEnd else{return};let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="HH:mm:ss";quietHoursEnabled=true;quietStart=formatter.date(from:start) ?? quietStart;quietEnd=formatter.date(from:end) ?? quietEnd}
}

private struct PrivacyInformationView: View {
    var body: some View {
        CreamPage {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    SectionTitle(title:"Your privacy",subtitle:"CB Employee Hub does not use your information for advertising or cross-app tracking.",symbol:"hand.raised.fill")
                    PrivacyRow(symbol:"location.fill",title:"Location",text:"Precise location and restaurant network checks are used only when attendance is marked. Failed and successful attempts may be audited for workplace security.")
                    PrivacyRow(symbol:"face.smiling",title:"Face attendance",text:"An on-device face model creates a mathematical template for attendance matching. Face ID used for login is handled separately by iOS and the app never receives your Face ID image.")
                    PrivacyRow(symbol:"person.text.rectangle",title:"Employment records",text:"Your identity, contact, attendance, leave, salary, document and branch records are stored in the organization’s InsForge backend and shown only according to your role.")
                    PrivacyRow(symbol:"bell.fill",title:"Notifications",text:"A device token is stored to deliver relevant attendance, leave, shift, document and salary updates. Signing out disables this iPhone’s token.")
                    PrivacyRow(symbol:"trash.fill",title:"Deletion",text:"You can request permanent account deletion from Account & Security. Access and biometric credentials are revoked immediately. Records that must remain for payroll, fraud prevention, audit or legal obligations are retained only as required.")
                }
                .padding(18).padding(.bottom,24)
            }
        }
        .navigationTitle(L10n.text("Privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyRow: View {
    let symbol,title,text:String
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Label { Text(L10n.text(title)) } icon: { Image(systemName:symbol) }.font(.headline).foregroundStyle(CBTheme.info)
            Text(L10n.text(text)).font(.subheadline).foregroundStyle(CBTheme.muted).fixedSize(horizontal:false,vertical:true)
        }
        .padding(16).frame(maxWidth:.infinity,alignment:.leading).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.08))
    }
}

struct OperationsCenterView:View {
    @Environment(AppSession.self) private var session
    @State private var reportKind="all"
    @State private var from=Calendar.current.date(byAdding:.month,value:-1,to:.now) ?? .now
    @State private var to=Date()
    @State private var reportURL:URL?
    @State private var reportRows:[WorkforceReportRow]=[]
    @State private var selectedNotification:AppNotification?
    @State private var reportIsLoading=false
    private var unread:Int{session.notifications.filter{!$0.isRead}.count}
    var body:some View {
        CreamPage {
            ScrollView {
                VStack(spacing:16) {
                    if session.operationsIsLoading && session.notifications.isEmpty {
                        LoadingStateCard(title:"Loading updates",message:"Getting notifications and reports…")
                    }
                    VStack(alignment:.leading,spacing:12) {
                        HStack{SectionTitle(title:"Notifications",symbol:"bell.badge.fill");Spacer();if session.operationsIsLoading{ProgressView().tint(CBTheme.orange)}else if unread>0{Button("Read All"){Task{await session.markAllNotificationsRead()}}.buttonStyle(.bordered)}}
                        if session.notifications.isEmpty && !session.operationsIsLoading { Text("No notifications").foregroundStyle(CBTheme.muted) }
                        ForEach(session.notifications.prefix(30)){notification in
                            Button{selectedNotification=notification;Task{await session.markNotificationRead(notification)}} label:{
                                HStack(alignment:.top){
                                    Circle().fill(notification.isRead ? CBTheme.divider:CBTheme.orange).frame(width:8,height:8).padding(.top,6)
                                    VStack(alignment:.leading,spacing:3){Text(notification.title).font(.subheadline.weight(.semibold));Text(notification.message).font(.caption).foregroundStyle(CBTheme.muted)}
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if session.notifications.count>=30{Button("Load More"){Task{await session.loadMoreNotifications()}}.buttonStyle(.bordered)}
                    }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))

                    VStack(alignment:.leading,spacing:12) {
                            NavigationLink {
                                AdvancedReportsView()
                            } label: {
                                HStack(spacing:12) {
                                    Image(systemName:"doc.text.magnifyingglass").font(.title3).foregroundStyle(CBTheme.orange)
                                    VStack(alignment:.leading,spacing:3) {
                                        Text(L10n.text("Advanced Reports")).font(.headline)
                                        Text(L10n.text("Filter attendance, leave, payroll, marking method, overrides, and dates.")).font(.caption).foregroundStyle(CBTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName:"chevron.right").foregroundStyle(CBTheme.muted)
                                }
                            }.buttonStyle(.plain)
                            if session.role.isAdministrator {
                            SectionTitle(title:"Audit trail",symbol:"checkmark.shield")
                            ForEach(session.auditEvents.prefix(50)){event in
                                HStack { Image(systemName:"checkmark.shield").foregroundStyle(CBTheme.info);VStack(alignment:.leading){Text(L10n.text(event.action.replacingOccurrences(of:"_",with:" ").replacingOccurrences(of:".",with:" ").capitalized)).font(.subheadline.weight(.semibold));Text(event.createdAt).font(.caption).foregroundStyle(CBTheme.muted)};Spacer() }
                            }
                            if session.auditEvents.count>=50{Button("Load More Audit Events"){Task{await session.loadMoreAuditEvents()}}.buttonStyle(.bordered)}
                            }
                        }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
                }.padding(16).padding(.bottom,24)
            }
        }
        .navigationTitle(unread>0 ? L10n.format("Updates (%lld)", Int64(unread)):L10n.text("Updates")).navigationBarTitleDisplayMode(.inline)
        .refreshable{await session.refreshOperationsCenter()}
        .task(id:session.selectedBranchId){await session.refreshOperationsCenter()}
        .onChange(of:from){_,newValue in if to<newValue{to=newValue}}
        .sheet(isPresented:Binding(get:{reportURL != nil},set:{if !$0{reportURL=nil}})){if let reportURL{DocumentShareSheet(url:reportURL)}}
        .sheet(item:$selectedNotification){notification in NavigationStack{notificationDestination(notification)}}
        .diagnosticScreen("Notifications & Reports")
    }

    private func generateReport(pdf:Bool){Task{reportIsLoading=true;defer{reportIsLoading=false};let rows=await session.reportRows(kind:reportKind,from:from,to:to);reportRows=rows;guard !rows.isEmpty else{return};reportURL=await ReportExport.make(rows:rows,kind:reportKind,pdf:pdf)}}

    @ViewBuilder private func notificationDestination(_ notification:AppNotification)->some View {
        switch notification.category {
        case "attendance": AttendanceView()
        case "leave": LeavesView()
        case "payroll": PayrollView()
        case "shift","documents": WorkforceOperationsView()
        case "employee" where session.role.canManagePeople: EmployeesView()
        default: DashboardView()
        }
    }
}

private enum ReportExport {
    nonisolated static func csvRows(_ rows:[WorkforceReportRow])->[String] {
        func csv(_ value:String)->String{"\"\(value.replacingOccurrences(of:"\"",with:"\"\""))\""}
        return ["Report,Employee,Code,Date,Status,Amount PKR,Details"]+rows.map{[$0.reportType.sentenceCased,$0.employeeName,$0.employeeCode,$0.recordDate,$0.status,$0.amountMinor.map{String(format:"%.2f",Double($0)/100)} ?? "",$0.details ?? ""].map(csv).joined(separator:",")}
    }
    static func make(rows:[WorkforceReportRow],kind:String,pdf:Bool) async->URL { await Task.detached(priority:.userInitiated){
        let csv=csvRows(rows)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("CB-Employee-Hub-\(kind)-Report").appendingPathExtension(pdf ? "pdf":"csv")
        if !pdf { try? csv.joined(separator:"\n").data(using:.utf8)?.write(to:url,options:.atomic);return url }
        let renderer=UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792));try? renderer.writePDF(to:url){context in var y:CGFloat=42;func page(){context.beginPage();y=42;("CB Employee Hub — \(kind.capitalized) Report" as NSString).draw(at:CGPoint(x:36,y:y),withAttributes:[.font:UIFont.boldSystemFont(ofSize:20)]);y+=36};page();for line in csv.dropFirst(){if y>744{page()};(line.replacingOccurrences(of:"\"",with:"").replacingOccurrences(of:",",with:" • ") as NSString).draw(in:CGRect(x:36,y:y,width:540,height:34),withAttributes:[.font:UIFont.systemFont(ofSize:9)]);y+=28}};return url
    }.value
    }
}
