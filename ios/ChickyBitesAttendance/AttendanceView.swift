import SwiftUI
import UIKit

struct AttendanceView: View {
    @Environment(AppSession.self) private var session
    @State private var locationService = LocationService()
    @State private var showingOverride = false
    @State private var showingKiosk = false
    @State private var correctionRow: AttendanceRow?

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing: 16) {
                    if let branch = session.selectedBranch { BranchVerificationCard(branch: branch) }
                    if session.attendanceIsLoading && session.attendance.isEmpty && session.attendanceDays.isEmpty {
                        LoadingStateCard(title: "Loading attendance", message: "Getting today’s register…")
                    } else if session.role.isAdministrator {
                        managerContent
                    } else {
                        EmployeeAttendanceCard(locationService: locationService)
                    }
                }
                .padding(16).padding(.bottom, 24)
            }
            .refreshable { await session.refreshAttendanceScreen() }
        }
        .navigationTitle(L10n.text("Attendance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .sheet(isPresented: $showingOverride) { ManagerOverrideSheet() }
        .fullScreenCover(isPresented:$showingKiosk) { BranchKioskModeView() }
        .sheet(item:$correctionRow){AttendanceCorrectionSheet(row:$0)}
        .overlay { if session.isWorking { LoadingOverlay() } }
        .overlay(alignment:.top) {
            if session.attendanceIsLoading && (!session.attendance.isEmpty || !session.attendanceDays.isEmpty) {
                ProgressView()
                    .controlSize(.small)
                    .tint(CBTheme.orange)
                    .padding(10)
                    .cbGlass(cornerRadius:16,tint:CBTheme.surface.opacity(0.12))
                    .padding(.top,8)
                    .accessibilityLabel("Updating attendance")
            }
        }
        .task(id:"\(session.selectedBranchId ?? "")-\(ISODate.string(from:session.selectedDate))") {
            await session.refreshAttendanceScreen()
        }
        .diagnosticScreen("Attendance")
    }

    private var managerContent: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Daily register", subtitle: "Review attendance for the selected branch and date.", symbol: "calendar")
                HStack(spacing: 12) {
                    DatePicker("Attendance date", selection: Binding(
                        get: { session.selectedDate },
                        set: { session.selectedDate = $0 }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    Spacer(minLength: 0)
                    Button("Override", systemImage: "person.badge.key") { showingOverride = true }
                        .cbSecondaryButton()
                    Button("Kiosk",systemImage:"ipad.and.iphone") {
                        Task {
                            if await session.registerCurrentDeviceAsKiosk(name:UIDevice.current.name) { showingKiosk=true }
                        }
                    }
                    .cbSecondaryButton()
                }
                NavigationLink {
                    AttendanceHistoryView()
                } label: {
                    Label(L10n.text("Attendance History"),systemImage:"calendar.badge.clock")
                        .frame(maxWidth:.infinity)
                }
                .cbSecondaryButton()
            }
            .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

            if session.attendance.isEmpty {
                EmptyState(symbol: "person.2.slash", title: "No employees", message: "Active employees assigned to this branch will appear here.")
            } else {
                ForEach(session.attendance) { row in AttendanceEmployeeRow(row: row,onCorrect:row.attendanceId == nil ? nil:{correctionRow=row}) }
            }
        }
    }
}

private struct BranchVerificationCard: View {
    let branch: Branch

    private var verificationTitle: String {
        switch branch.attendanceVerificationMode {
        case "IP_AND_GPS": "Restaurant Wi-Fi and GPS"
        case "IP_ONLY": "Restaurant Wi-Fi"
        case "GPS_ONLY": "GPS location"
        default: "Restaurant Wi-Fi or GPS"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.title2).foregroundStyle(CBTheme.orange)
                    .frame(width: 44, height: 44)
                    .background(CBTheme.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(branch.name).font(.headline).foregroundStyle(CBTheme.text)
                    Text(branch.address ?? "Address not configured")
                        .font(.subheadline).foregroundStyle(CBTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                StatusBadge(status: branch.isActive ? "Active" : "Inactive")
            }
            Divider().overlay(CBTheme.divider)
            InfoRow(symbol: "checkmark.shield.fill", title: "Location verification", value: verificationTitle, color: CBTheme.success)
            InfoRow(symbol: "location.circle.fill", title: "Allowed radius", value: "Within \(branch.geofenceRadiusM) metres of the branch", color: CBTheme.info)
        }
        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.info.opacity(0.045))
    }
}

private struct AttendanceEmployeeRow: View {
    let row: AttendanceRow
    let onCorrect:(()->Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                InitialsAvatar(name: row.fullName)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.fullName).font(.headline).foregroundStyle(CBTheme.text)
                    Text([row.employeeCode, row.position].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.subheadline).foregroundStyle(CBTheme.muted)
                }
                Spacer(minLength: 8)
                StatusBadge(status: row.attendanceStatus ?? "Unmarked")
            }
            if row.checkInAt != nil || row.checkOutAt != nil {
                Divider().overlay(CBTheme.divider)
                HStack(spacing: 18) {
                    if let checkIn = row.checkInAt { Label(shortTime(checkIn), systemImage: "arrow.right.circle.fill") }
                    if let checkOut = row.checkOutAt { Label(shortTime(checkOut), systemImage: "arrow.left.circle.fill") }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(CBTheme.muted)
            }
            if let onCorrect { Button("Correct",systemImage:"pencil"){onCorrect()}.buttonStyle(.bordered) }
        }
        .padding(16).cbGlass(cornerRadius: 21, tint: CBTheme.surface.opacity(0.06))
    }

    private func shortTime(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return L10n.date(date, dateStyle: .none, timeStyle: .short)
    }
}

private struct AttendanceCorrectionSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let row:AttendanceRow
    @State private var checkIn=Date()
    @State private var checkOut=Date()
    @State private var hasCheckIn=true
    @State private var hasCheckOut=true
    @State private var status="present"
    @State private var reason=""
    var body:some View {
        NavigationStack {
            Form {
                Section(row.fullName){
                    Picker("Status",selection:$status){Text("Present").tag("present");Text("Absent").tag("absent");Text("Leave").tag("leave");Text("Partial").tag("partial")}
                    Toggle("Has check-in",isOn:$hasCheckIn);if hasCheckIn{DatePicker("Check-in",selection:$checkIn)}
                    Toggle("Has check-out",isOn:$hasCheckOut);if hasCheckOut{DatePicker("Check-out",selection:$checkOut)}
                    TextField("Correction reason",text:$reason,axis:.vertical)
                }
                Section{Button("Save Correction"){Task{if let id=row.attendanceId,await session.correctAttendance(id:id,checkIn:hasCheckIn ? checkIn:nil,checkOut:hasCheckOut ? checkOut:nil,status:status,reason:reason){dismiss()}}}.disabled(reason.trimmingCharacters(in:.whitespaces).count<5)}
            }
            .navigationTitle(L10n.text("Attendance Correction")).navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
            .onAppear{
                let iso=ISO8601DateFormatter();if let value=row.checkInAt,let date=iso.date(from:value){checkIn=date}else{hasCheckIn=false};if let value=row.checkOutAt,let date=iso.date(from:value){checkOut=date}else{hasCheckOut=false};status=row.attendanceStatus ?? "present"
            }
        }
    }
}

private struct EmployeeAttendanceCard: View {
    @Environment(AppSession.self) private var session
    let locationService: LocationService
    @State private var pendingScan: AttendanceFaceScan?

    private var day: AttendanceDay? {
        guard let id = session.ownEmployee?.id else { return nil }
        return session.attendanceDays.first { $0.employeeId == id }
    }
    private var isCheckedIn: Bool { day?.firstCheckInAt != nil }
    private var isComplete: Bool { day?.lastCheckOutAt != nil }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isComplete ? "checkmark.seal.fill" : (isCheckedIn ? "clock.badge.checkmark.fill" : "person.crop.circle.badge.checkmark"))
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(isComplete ? CBTheme.success : CBTheme.orange)
                .frame(width: 82, height: 82)
                .background((isComplete ? CBTheme.success : CBTheme.orange).opacity(0.11), in: RoundedRectangle(cornerRadius: 25))

            VStack(spacing: 7) {
                Text(isComplete ? "Attendance complete" : (isCheckedIn ? "You’re checked in" : "Ready to check in"))
                    .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(CBTheme.text)
                Text("A live face match confirms your identity. Restaurant Wi-Fi or GPS confirms that you are at your assigned branch.")
                    .font(.subheadline).foregroundStyle(CBTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }

            if session.offlineAttendanceCount>0 {
                Button("Sync \(session.offlineAttendanceCount) Saved Attendance",systemImage:"arrow.triangle.2.circlepath"){Task{await session.syncOfflineAttendance()}}.buttonStyle(.bordered)
            }

            NavigationLink {
                AttendanceHistoryView(employee:session.ownEmployee)
            } label: {
                Label(L10n.text("View Attendance History"),systemImage:"calendar.badge.clock")
                    .frame(maxWidth:.infinity)
            }
            .buttonStyle(.bordered)

            if let checkIn = day?.firstCheckInAt {
                InfoRow(symbol: "arrow.right.circle.fill", title: "Checked in", value: checkIn, color: CBTheme.success)
            }
            if let checkOut = day?.lastCheckOutAt {
                InfoRow(symbol: "arrow.left.circle.fill", title: "Checked out", value: checkOut, color: CBTheme.info)
            }
            if (day?.breakMinutes ?? 0)>0 {
                InfoRow(symbol:"cup.and.saucer.fill",title:"Break time",value:"\(day?.breakMinutes ?? 0) minutes",color:CBTheme.warning)
            }

            if !isCheckedIn {
                attendanceButton("Check In",symbol:"arrow.right.circle.fill",event:"check_in",primary:true)
            } else if !isComplete {
                if day?.activeBreakStartedAt != nil {
                    attendanceButton("End Break",symbol:"play.circle.fill",event:"break_end",primary:true)
                } else {
                    HStack(spacing:10) {
                        attendanceButton("Start Break",symbol:"cup.and.saucer.fill",event:"break_start",primary:false)
                        attendanceButton("Check Out",symbol:"arrow.left.circle.fill",event:"check_out",primary:true)
                    }
                }
            }

            if session.ownEmployee == nil {
                Label("Your account must be linked to an employee record first.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(CBTheme.warning)
            }
        }
        .padding(24).cbGlass(cornerRadius: 28, tint: CBTheme.surface.opacity(0.08))
        .sheet(item: $pendingScan) { scan in
            FaceScanView(mode: .verification) { proofId in
                pendingScan = nil
                Task {
                    let location = await locationService.current()
                    _ = await session.markAttendance(eventType: scan.eventType, location: location, biometricProofId: proofId)
                }
            } onCaptured: { descriptors, challenge in
                pendingScan=nil
                Task {
                    guard let location=await locationService.current() else{session.errorMessage="GPS is required to save attendance offline.";return}
                    _=await session.queueOfflineAttendance(eventType:scan.eventType,location:location,challenge:challenge,descriptors:descriptors)
                }
            }
        }
    }

    @ViewBuilder private func attendanceButton(_ title:String,symbol:String,event:String,primary:Bool)->some View {
        Button { pendingScan=AttendanceFaceScan(eventType:event) } label: {
            Label(title,systemImage:symbol).fontWeight(.bold).frame(maxWidth:.infinity).padding(.vertical,8)
        }
        .modifier(AttendanceButtonStyle(primary:primary))
        .disabled(session.isWorking || isComplete || session.ownEmployee == nil)
    }
}

struct AttendanceButtonStyle:ViewModifier {
    let primary:Bool
    func body(content:Content)->some View { if primary { content.cbPrimaryButton() } else { content.cbSecondaryButton() } }
}

private struct AttendanceFaceScan: Identifiable { let id = UUID(); let eventType: String }

private struct ManagerOverrideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var employeeId = ""
    @State private var eventType = "check_in"
    @State private var reason = ""
    @State private var password = ""
    @State private var passwordVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee and action") {
                    Picker("Employee", selection: $employeeId) {
                        Text("Select employee").tag("")
                        ForEach(session.employees.filter { $0.employmentStatus == "active" }) {
                            Text("\($0.employeeCode) — \($0.fullName)").tag($0.id)
                        }
                    }
                    Picker("Action", selection: $eventType) {
                        Text("Check In").tag("check_in"); Text("Check Out").tag("check_out")
                    }.pickerStyle(.segmented)
                }
                Section("Required reason") {
                    TextField("Explain the Wi-Fi, GPS, or device issue", text: $reason, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    PremiumPasswordField(placeholder: "Your account password", text: $password, isVisible: $passwordVisible)
                } header: { Text("Confirm your identity") }
                  footer: { Text("Overrides are audited with your account, time, employee, and reason.") }
                Section {
                    Button("Record Manager Override") {
                        Task {
                            if await session.markAttendance(eventType: eventType, location: nil, overrideEmployeeId: employeeId, overrideReason: reason, managerPassword: password) { dismiss() }
                        }
                    }
                    .disabled(employeeId.isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 || password.isEmpty)
                }
            }
            .navigationTitle(L10n.text("Attendance Override"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
