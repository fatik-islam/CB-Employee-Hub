import SwiftUI
import UniformTypeIdentifiers

struct LeavesView: View {
    @Environment(AppSession.self) private var session
    @State private var showingNew = false
    @State private var editingType: LeaveType?
    @State private var showingCalendar = false

    private var pendingCount: Int { session.leaves.filter { $0.status == "pending" }.count }

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 15) {
                        SectionTitle(
                            title: session.role.canManagePeople ? "Leave management" : "My leave",
                            subtitle: session.role.canManagePeople
                                ? "Review requests and keep policies understandable for the team."
                                : "Request time off and follow each approval status.",
                            symbol: "calendar.badge.clock"
                        )
                        HStack {
                            Label("\(pendingCount) pending", systemImage: "clock.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(CBTheme.warning)
                            Spacer()
                            Button("New Request", systemImage: "plus") { showingNew = true }.cbPrimaryButton()
                        }
                    }
                    .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

                    if session.role == .owner {
                        Button { showingCalendar=true } label:{
                            HStack { Label("Holiday & blackout calendar",systemImage:"calendar.badge.exclamationmark");Spacer();Image(systemName:"chevron.right") }
                        }.buttonStyle(.bordered)
                        policies
                    }

                    if let employee=session.role.isAdministrator ? nil:session.ownEmployee {
                        VStack(alignment:.leading,spacing:12) {
                            SectionTitle(title:"Leave balance",symbol:"calendar.badge.checkmark")
                            ForEach(session.leaveTypes){type in
                                let used = session.leaveBalanceEntries.filter{$0.employeeId==employee.id && $0.leaveTypeId==type.id}.reduce(0){$0 + $1.daysDelta}
                                InfoRow(symbol:"calendar",title:type.name,value:"\(max(0,type.defaultAnnualDays + used).formatted()) days")
                            }
                        }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
                    }

                    if session.leaveIsLoading && session.leaves.isEmpty {
                        LoadingStateCard(title:"Loading leave",message:"Getting requests, balances, and policies…")
                    } else if session.leaves.isEmpty {
                        EmptyState(symbol: "calendar.badge.clock", title: "No leave requests", message: "New requests and their approval history will appear here.")
                    } else {
                        ForEach(session.leaves) { LeaveCard(leave: $0) }
                        if session.leavesHaveMore {
                            Button { Task { await session.loadOlderLeaves() } } label: {
                                Label(session.olderLeaveIsLoading ? "Loading…" : "Load Older Requests",systemImage:"clock.arrow.circlepath")
                                    .frame(maxWidth:.infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.olderLeaveIsLoading)
                        }
                    }
                }
                .padding(16).padding(.bottom, 24)
            }
        }
        .navigationTitle(L10n.text("Leave"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .sheet(isPresented: $showingNew) { NewLeaveSheet() }
        .sheet(item: $editingType) { LeavePolicySheet(type: $0) }
        .sheet(isPresented:$showingCalendar) { LeaveCalendarSheet() }
        .refreshable { await session.refreshLeaveFeature() }
        .task(id:session.selectedBranchId){await session.refreshLeaveFeature()}
        .overlay { if session.isWorking { LoadingOverlay() } }
    }

    private var policies: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Leave policies", subtitle: "Annual entitlement and evidence rules.", symbol: "slider.horizontal.3")
            ForEach(session.leaveTypes) { type in
                Button { editingType = type } label: {
                    HStack(spacing: 12) {
                        Image(systemName: type.isPaid ? "banknote.fill" : "calendar")
                            .foregroundStyle(type.isPaid ? CBTheme.success : CBTheme.info)
                            .frame(width: 36, height: 36)
                            .background((type.isPaid ? CBTheme.success : CBTheme.info).opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text(type.name)).font(.subheadline.weight(.semibold)).foregroundStyle(CBTheme.text)
                            Text("\(L10n.text(type.isPaid ? "Paid" : "Unpaid")) • \(type.defaultAnnualDays.formatted()) \(L10n.text("days per year"))")
                                .font(.caption).foregroundStyle(CBTheme.muted)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(CBTheme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if type.id != session.leaveTypes.last?.id { Divider().overlay(CBTheme.divider) }
            }
        }
        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))
    }
}

private struct LeavePolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let type: LeaveType
    @State private var paid: Bool
    @State private var days: String
    @State private var document: Bool
    @State private var reason: Bool
    @State private var accrual: String
    @State private var carryForward: String
    @State private var attachmentAfter: String

    init(type: LeaveType) {
        self.type = type
        _paid = State(initialValue: type.isPaid)
        _days = State(initialValue: type.defaultAnnualDays.formatted())
        _document = State(initialValue: type.requiresDocument)
        _reason = State(initialValue: type.requiresReason)
        _accrual = State(initialValue:type.accrualMethod)
        _carryForward = State(initialValue:type.carryForwardDays.formatted())
        _attachmentAfter = State(initialValue:type.attachmentAfterDays?.formatted() ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(type.name) {
                    Toggle("Paid leave", isOn: $paid)
                    TextField("Annual entitlement (days)", text: $days).keyboardType(.decimalPad)
                    Toggle("Require supporting document", isOn: $document)
                    Toggle("Require reason", isOn: $reason)
                    Picker("Accrual",selection:$accrual) {
                        Text("Annual").tag("annual");Text("Monthly").tag("monthly");Text("Joining anniversary").tag("joining_anniversary")
                    }
                    TextField("Carry forward days",text:$carryForward).keyboardType(.decimalPad)
                    TextField("Require attachment after days (optional)",text:$attachmentAfter).keyboardType(.decimalPad)
                }
                Section { Button("Save Policy") { Task { if let value = Double(days),let carry=Double(carryForward), await session.updateLeaveType(type, isPaid: paid, annualDays: value, requiresDocument: document, requiresReason: reason,accrualMethod:accrual,carryForwardDays:carry,attachmentAfterDays:Double(attachmentAfter)) { dismiss() } } }.disabled(Double(days) == nil || Double(carryForward)==nil) }
            }
            .navigationTitle(L10n.text("Leave Policy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct LeaveCard: View {
    @Environment(AppSession.self) private var session
    let leave: LeaveRecord
    private var typeName: String { session.leaveTypes.first { $0.id == leave.leaveTypeId }?.name ?? "Leave" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                InitialsAvatar(name: leave.fullName.isEmpty ? "My Request" : leave.fullName)
                VStack(alignment: .leading, spacing: 4) {
                    Text(leave.fullName.isEmpty ? L10n.text("My request") : leave.fullName).font(.headline).foregroundStyle(CBTheme.text)
                    Text(L10n.text(typeName)).font(.subheadline.weight(.medium)).foregroundStyle(CBTheme.info)
                }
                Spacer(minLength: 8); StatusBadge(status: leave.status)
            }
            Divider().overlay(CBTheme.divider)
            InfoRow(symbol: "calendar", title: "Dates", value: "\(leave.startDate) to \(leave.endDate)")
            if let duration=leave.durationType { InfoRow(symbol:"clock",title:"Duration",value:L10n.text(duration.replacingOccurrences(of:"_",with:" ").capitalized) + (leave.requestedMinutes.map{" • \($0) \(L10n.text("minutes"))"} ?? "")) }
            if let reason = leave.reason, !reason.isEmpty { InfoRow(symbol: "text.quote", title: "Reason", value: reason, color: CBTheme.warning) }
            if session.role.canManagePeople && leave.status == "pending" {
                HStack {
                    Button("Reject", role: .destructive) { Task { await session.reviewLeave(leave, status: "rejected") } }.buttonStyle(.bordered)
                    Spacer()
                    Button("Approve") { Task { await session.reviewLeave(leave, status: "approved") } }.cbPrimaryButton()
                }
            }
            if leave.status == "pending" || (leave.status == "approved" && session.role.canManagePeople) {
                Button("Cancel Request",role:.destructive){Task{await session.cancelLeave(leave,reason:"Cancelled in CB Employee Hub")}}.buttonStyle(.bordered)
            }
        }
        .padding(17).cbGlass(cornerRadius: 22, tint: CBTheme.surface.opacity(0.07))
    }
}

private struct NewLeaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var draft = LeaveDraft()
    @State private var importingDocument=false

    var body: some View {
        NavigationStack {
            Form {
                if session.role.isAdministrator {
                    Section("Employee") {
                        Picker("Employee", selection: $draft.employeeId) {
                            Text("Select employee").tag("")
                            ForEach(session.employees.filter { $0.employmentStatus == "active" }) { Text("\($0.employeeCode) — \($0.fullName)").tag($0.id) }
                        }
                    }
                }
                Section("Leave details") {
                    Picker("Type", selection: $draft.leaveTypeId) {
                        Text("Select type").tag("")
                        ForEach(session.leaveTypes) { Text(L10n.text($0.name) + ($0.isPaid ? " (\(L10n.text("Paid")))" : " (\(L10n.text("Unpaid")))")).tag($0.id) }
                    }
                    Picker("Duration",selection:$draft.durationType){Text("Full day").tag("full_day");Text("First half").tag("first_half");Text("Second half").tag("second_half");Text("Hourly").tag("hourly")}
                    DatePicker("Start", selection: $draft.startDate, displayedComponents: .date)
                    if draft.durationType=="full_day" { DatePicker("End", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date) }
                    if draft.durationType=="hourly" {
                        Stepper("Duration: \(draft.requestedMinutes ?? 60) minutes",value:Binding(get:{draft.requestedMinutes ?? 60},set:{draft.requestedMinutes=$0}),in:30...480,step:30)
                    }
                    TextField("Reason", text: $draft.reason, axis: .vertical).lineLimit(3...6)
                    Button(draft.documentURL?.lastPathComponent ?? "Add Supporting Document",systemImage:"paperclip") { importingDocument=true }
                }
                Section { Button("Submit Request") { Task { if await session.submitLeave(draft) { dismiss() } } }.disabled(draft.leaveTypeId.isEmpty || draft.reason.trimmingCharacters(in: .whitespaces).isEmpty || (session.role.isAdministrator && draft.employeeId.isEmpty)) }
            }
            .navigationTitle(L10n.text("Request Leave")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fileImporter(isPresented:$importingDocument,allowedContentTypes:[.pdf,.image]){result in if case .success(let url)=result{draft.documentURL=url} }
        }
    }
}

private struct LeaveCalendarSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var mode=0
    @State private var name=""
    @State private var start=Date()
    @State private var end=Date()
    @State private var allBranches=false
    @State private var paid=true
    var body:some View {
        NavigationStack {
            Form {
                Picker("Entry",selection:$mode){Text("Holiday").tag(0);Text("Leave blackout").tag(1)}.pickerStyle(.segmented)
                if mode==0 { TextField("Holiday name",text:$name);DatePicker("Date",selection:$start,displayedComponents:.date);Toggle("Paid holiday",isOn:$paid) }
                else { TextField("Reason",text:$name);DatePicker("Starts",selection:$start,displayedComponents:.date);DatePicker("Ends",selection:$end,in:start...,displayedComponents:.date) }
                Toggle("All branches",isOn:$allBranches)
                Section("Upcoming") {
                    ForEach(session.holidays){Text("\($0.holidayDate) • \($0.name)")}
                    ForEach(session.leaveBlackouts){Text("\($0.startsOn)–\($0.endsOn) • \($0.reason)")}
                }
            }
            .navigationTitle(L10n.text("Leave Calendar"))
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Close"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Add"){Task{let ok = mode==0 ? await session.addHoliday(name:name,date:start,allBranches:allBranches,isPaid:paid) : await session.addLeaveBlackout(start:start,end:end,reason:name,allBranches:allBranches);if ok{name=""}}}.disabled(name.trimmingCharacters(in:.whitespaces).count<3)}
            }
        }
    }
}
