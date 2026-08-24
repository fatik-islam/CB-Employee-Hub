import SwiftUI
import LocalAuthentication

struct BranchKioskModeView:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var search=""
    @State private var selectedEmployee:Employee?
    @State private var pendingAction:KioskAttendanceAction?
    @State private var locationService=LocationService()

    private var filtered:[Employee] {
        let active=session.employees.filter{$0.employmentStatus=="active"}
        guard !search.isEmpty else{return active}
        return active.filter{$0.fullName.localizedCaseInsensitiveContains(search) || $0.employeeCode.localizedCaseInsensitiveContains(search)}
    }

    var body:some View {
        NavigationStack {
            CreamPage {
                VStack(spacing:16) {
                    VStack(spacing:5) {
                        BrandLockup(compact:true)
                        Text(session.selectedBranch?.name ?? "Branch Kiosk").font(.title2.bold())
                        Text("Select your name, then complete the quick live face check.").font(.subheadline).foregroundStyle(CBTheme.muted).multilineTextAlignment(.center)
                    }
                    .padding(.top,8)

                    TextField("Search name or employee code",text:$search)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .padding(14).background(CBTheme.surface.opacity(0.9),in:RoundedRectangle(cornerRadius:18))

                    ScrollView {
                        LazyVStack(spacing:10) {
                            ForEach(filtered) { employee in
                                Button { selectedEmployee=employee } label: {
                                    HStack(spacing:12) {
                                        InitialsAvatar(name:employee.fullName)
                                        VStack(alignment:.leading,spacing:3) {
                                            Text(employee.fullName).font(.headline).foregroundStyle(CBTheme.text)
                                            Text("\(employee.employeeCode) • \(employee.position ?? "Staff")").font(.caption).foregroundStyle(CBTheme.muted)
                                        }
                                        Spacer();Image(systemName:"chevron.right").foregroundStyle(CBTheme.orange)
                                    }
                                    .padding(14).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.08))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Attendance Kiosk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Exit",systemImage:"lock.fill") { authenticateAndExit() }
                }
            }
            .sheet(item:$selectedEmployee) { employee in KioskActionSheet(employee:employee){event in
                selectedEmployee=nil
                pendingAction=KioskAttendanceAction(employee:employee,eventType:event)
            }}
            .sheet(item:$pendingAction) { action in
                FaceScanView(mode:.kiosk(action.employee)) { proof in
                    pendingAction=nil
                    Task {
                        let location=await locationService.current()
                        _=await session.markAttendance(eventType:action.eventType,location:location,biometricProofId:proof,kioskEmployeeId:action.employee.id)
                        search=""
                    }
                }
            }
            .overlay{if session.isWorking{LoadingOverlay()}}
        }
    }

    private func authenticateAndExit() {
        let context=LAContext()
        var error:NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error:&error) else { dismiss();return }
        context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"Exit branch attendance kiosk") { success,_ in
            if success { Task{@MainActor in dismiss()} }
        }
    }
}

private struct KioskAttendanceAction:Identifiable {
    let id=UUID();let employee:Employee;let eventType:String
}

private struct KioskActionSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let employee:Employee
    let onSelect:(String)->Void

    private var day:AttendanceDay? { session.attendanceDays.first{$0.employeeId==employee.id} }
    private var checkedIn:Bool { day?.firstCheckInAt != nil }
    private var checkedOut:Bool { day?.lastCheckOutAt != nil }

    var body:some View {
        NavigationStack {
            VStack(spacing:18) {
                InitialsAvatar(name:employee.fullName)
                Text(employee.fullName).font(.title2.bold())
                Text(employee.employeeCode).foregroundStyle(CBTheme.muted)
                if checkedOut {
                    Label("Attendance completed for today",systemImage:"checkmark.seal.fill").foregroundStyle(CBTheme.success)
                } else if !checkedIn {
                    actionButton("Check In",symbol:"arrow.right.circle.fill",event:"check_in",primary:true)
                } else if day?.activeBreakStartedAt != nil {
                    actionButton("End Break",symbol:"play.circle.fill",event:"break_end",primary:true)
                } else {
                    actionButton("Start Break",symbol:"cup.and.saucer.fill",event:"break_start",primary:false)
                    actionButton("Check Out",symbol:"arrow.left.circle.fill",event:"check_out",primary:true)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Choose Action").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
        }
    }

    @ViewBuilder private func actionButton(_ title:String,symbol:String,event:String,primary:Bool)->some View {
        Button { onSelect(event) } label:{Label(title,systemImage:symbol).font(.headline).frame(maxWidth:.infinity).padding(.vertical,10)}
            .modifier(AttendanceButtonStyle(primary:primary))
    }
}
