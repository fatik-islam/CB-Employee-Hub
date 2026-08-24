import SwiftUI
import UniformTypeIdentifiers

private struct EmployeeEditorDestination: Identifiable {
    let id = UUID()
    let draft: EmployeeDraft
}

struct EmployeesView: View {
    @Environment(AppSession.self) private var session
    @State private var searchText = ""
    @State private var editor: EmployeeEditorDestination?
    @State private var employeeToManage: Employee?
    @State private var employeeToInvite: Employee?
    @State private var faceEmployee: Employee?
    @State private var importingStaff=false

    private var filteredEmployees: [Employee] {
        guard !searchText.isEmpty else { return session.employees }
        return session.employees.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
                || $0.employeeCode.localizedCaseInsensitiveContains(searchText)
                || ($0.position?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        CreamPage {
            ScrollView {
                LazyVStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Team directory", subtitle: "Employee identity, access role, attendance face, and employment status.", symbol: "person.2.fill")
                        Text("\(session.employees.filter { $0.employmentStatus == "active" }.count) active employees")
                            .font(.caption.weight(.semibold)).foregroundStyle(CBTheme.muted)
                    }
                    .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

                    if session.peopleIsLoading && filteredEmployees.isEmpty {
                        LoadingStateCard(title:"Loading team",message:"Getting employee and branch information…")
                    } else if filteredEmployees.isEmpty {
                        EmptyState(
                            symbol: searchText.isEmpty ? "person.badge.plus" : "magnifyingglass",
                            title: searchText.isEmpty ? "No employees yet" : "No matching employees",
                            message: searchText.isEmpty
                                ? "Tap Add to create the first team record."
                                : "Try a different name, code, or position."
                        )
                    } else {
                        ForEach(filteredEmployees) { employee in
                            employeeCard(employee)
                        }
                        if searchText.isEmpty && session.employeesHaveMore {
                            Button("Load More Staff",systemImage:"arrow.down.circle") { Task{await session.loadMoreEmployees()} }.buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .refreshable { await session.refreshPeopleFeature() }
        }
        .navigationTitle(L10n.text("Team"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Name, code, or position")
        .task(id:session.selectedBranchId){await session.refreshPeopleFeature()}
        .toolbar {
            StandardToolbar()
            ToolbarItem(placement: .primaryAction) {
                if session.role.canAdministerEmployees {
                    Menu {
                        Button("Add Staff",systemImage:"person.badge.plus"){editor=EmployeeEditorDestination(draft:EmployeeDraft())}
                        Button("Import CSV",systemImage:"tablecells"){importingStaff=true}
                        ShareLink(item:staffImportTemplate){Label("Download CSV Template",systemImage:"arrow.down.doc")}
                    } label: {
                        Label("Add",systemImage:"person.badge.plus")
                    }
                    .accessibilityIdentifier("addEmployeeButton")
                }
            }
        }
        .sheet(item: $editor) { destination in
            EmployeeEditorView(draft: destination.draft)
        }
        .sheet(item:$employeeToInvite){employee in EmployeeInviteSheet(employee:employee)}
        .sheet(item:$faceEmployee){employee in FaceScanView(mode:.enrollment(employee))}
        .sheet(item:$employeeToManage){employee in EmployeeManagementSheet(employee:employee)}
        .fileImporter(isPresented:$importingStaff,allowedContentTypes:[.commaSeparatedText,.plainText],allowsMultipleSelection:false){result in
            Task {
                do {
                    guard let url=try result.get().first else{return}
                    let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                    let text=try String(contentsOf:url,encoding:.utf8)
                    let rows=try StaffCSVParser.parse(text)
                    _=await session.bulkImportStaff(rows:rows)
                } catch { session.errorMessage=UserFacingError.message(for:error) }
            }
        }
        .overlay {
            if session.isWorking { LoadingOverlay() }
        }
    }

    private var staffImportTemplate:URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("CB-Staff-Import-Template.csv")
        let text="employeeCode,fullName,phone,position,cnic,address,joiningDate,department,employmentType,role\nCB-002,Example Staff,03120000000,Cashier,45102-0000000-0,Lahore,2026-08-14,Operations,full_time,staff\n"
        try? text.write(to:url,atomically:true,encoding:.utf8);return url
    }

    private func employeeCard(_ employee: Employee) -> some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: employee.fullName)
            VStack(alignment: .leading, spacing: 6) {
                Text(employee.fullName)
                    .font(.headline)
                    .foregroundStyle(CBTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(employee.employeeCode) • \(employee.position ?? "Team member")")
                    .font(.subheadline)
                    .foregroundStyle(CBTheme.muted)
                Label(employee.role.sentenceCased, systemImage: "person.text.rectangle")
                    .font(.caption)
                    .foregroundStyle(CBTheme.info)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 12) {
                StatusBadge(status: employee.status)
            Menu {
                if session.role.canAdministerEmployees {
                    Button("Edit", systemImage: "pencil") {
                        editor = EmployeeEditorDestination(draft: EmployeeDraft(employee: employee))
                    }
                    if employee.userId == nil { Button("Create App Invite",systemImage:"envelope.badge"){employeeToInvite=employee} }
                }
                Button("Enroll / Replace Face",systemImage:"person.crop.circle.badge.plus") { faceEmployee=employee }
                if session.role.canAdministerEmployees {
                    Button("Employment & Branches", systemImage: "building.2.crop.circle") { employeeToManage = employee }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(CBTheme.info)
            }
            .accessibilityLabel("Actions for \(employee.fullName)")
            }
        }
        .padding(16)
        .cbGlass(cornerRadius: 21, tint: CBTheme.surface.opacity(0.07))
    }
}

private enum StaffCSVParser {
    static func parse(_ text:String)throws->[[String:String]] {
        let lines=text.components(separatedBy:.newlines).filter{!$0.trimmingCharacters(in:.whitespaces).isEmpty}
        guard let first=lines.first else{throw BackendError.invalidInput("The CSV file is empty.")}
        let headers=fields(first).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
        guard headers.contains("employeeCode"),headers.contains("fullName") else{throw BackendError.invalidInput("Use the CB template with employeeCode and fullName columns.")}
        let rows=lines.dropFirst().map{line->[String:String] in
            let values=fields(line)
            var row:[String:String]=[:]
            for (offset,header) in headers.enumerated() {
                row[header]=offset<values.count ? values[offset].trimmingCharacters(in:.whitespacesAndNewlines):""
            }
            return row
        }
        guard !rows.isEmpty,rows.count<=500 else{throw BackendError.invalidInput("Import 1 to 500 staff rows at a time.")};return rows
    }
    private static func fields(_ line:String)->[String] {
        var result=[String](),value="",quoted=false;var index=line.startIndex
        while index<line.endIndex { let character=line[index];if character=="\"" { let next=line.index(after:index);if quoted,next<line.endIndex,line[next]=="\""{value.append("\"");index=next}else{quoted.toggle()}}else if character==",",!quoted{result.append(value);value=""}else{value.append(character)};index=line.index(after:index)}
        result.append(value);return result
    }
}

private struct EmployeeManagementSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let employee:Employee
    @State private var status="active"
    @State private var reason=""
    @State private var branchId=""
    @State private var primary=true
    @State private var startsOn=Date()
    private var assignments:[EmployeeBranchAssignment]{session.employeeBranchAssignments.filter{$0.employeeId==employee.id && $0.endsOn==nil}}
    var body:some View {
        NavigationStack {
            Form {
                Section("Employment") {
                    Picker("Status",selection:$status){Text("Active").tag("active");Text("Inactive").tag("inactive");Text("Terminated").tag("terminated")}
                    TextField("Reason",text:$reason,axis:.vertical)
                    Button("Update Status") { Task{if await session.setEmployeeStatus(employee,status:status,reason:reason){dismiss()}} }
                        .disabled(status==employee.employmentStatus || (status != "active" && reason.trimmingCharacters(in:.whitespaces).count<5))
                }
                Section("Active branches") {
                    ForEach(assignments){assignment in
                        HStack {
                            Text(session.branches.first{$0.id==assignment.branchId}?.name ?? "Branch")
                            Spacer()
                            if assignment.isPrimary { Text("Primary").font(.caption).foregroundStyle(CBTheme.orange) }
                            Button("End",role:.destructive){Task{await session.endAssignment(assignment,reason:"Assignment ended by administrator")}}
                        }
                    }
                    Picker("Branch",selection:$branchId){Text("Select").tag("");ForEach(session.branches){Text($0.name).tag($0.id)}}
                    Toggle("Primary branch",isOn:$primary)
                    DatePicker("Starts",selection:$startsOn,displayedComponents:.date)
                    Button("Assign Branch") { Task{if let branch=session.branches.first(where:{$0.id==branchId}){_ = await session.assignEmployee(employee,to:branch,isPrimary:primary,startsOn:startsOn)}} }.disabled(branchId.isEmpty)
                }
            }
            .navigationTitle(employee.fullName).navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}}}
            .onAppear{status=employee.employmentStatus;branchId=session.selectedBranch?.id ?? ""}
        }
    }
}

private struct EmployeeInviteSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session;let employee:Employee;@State private var email=""
    var body:some View{NavigationStack{Form{Section(employee.fullName){TextField("Employee email",text:$email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)};if let code=session.generatedInviteCode{Section("One-time invite code"){Text(code).font(.title.monospaced().bold()).textSelection(.enabled);ShareLink(item:code,subject:Text("CB Employee Hub invite"),message:Text("Install CB Employee Hub, register with \(email), then enter this code. It expires in 72 hours.")){Label("Share Invite",systemImage:"square.and.arrow.up")}}}else{Section{Button("Generate Invite"){Task{await session.createInvite(employeeId:employee.id,email:email)}}.disabled(!email.contains("@"))}}}.navigationTitle(L10n.text("App Invite")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){session.generatedInviteCode=nil;dismiss()}}}}}
}

private struct EmployeeEditorView: View {
    private enum Field: Hashable { case employeeCode, fullName, cnic, phone, position, address }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var draft: EmployeeDraft
    @FocusState private var focusedField: Field?

    init(draft: EmployeeDraft) {
        _draft = State(initialValue: draft)
    }

    private var missingRequirements: [String] {
        var missing: [String] = []
        if draft.employeeCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { missing.append("employee code") }
        if draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { missing.append("full legal name") }
        if !CNICFormatter.isComplete(draft.cnic) { missing.append("13-digit CNIC") }
        if draft.position.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { missing.append("position") }
        if draft.address.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 { missing.append("address") }
        return missing
    }

    private var duplicateCNICEmployee: Employee? {
        guard CNICFormatter.isComplete(draft.cnic) else { return nil }
        let digits = CNICFormatter.digits(from: draft.cnic)
        return session.employees.first {
            $0.id != draft.id && CNICFormatter.digits(from: $0.cnic ?? "") == digits
        }
    }

    private var duplicateCodeEmployee: Employee? {
        let code = draft.employeeCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 2 else { return nil }
        return session.employees.first {
            $0.id != draft.id
                && $0.employeeCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == code
        }
    }

    private var conflictMessages: [String] {
        var conflicts: [String] = []
        if let employee = duplicateCNICEmployee {
            conflicts.append("This CNIC already belongs to \(employee.employeeCode) — \(employee.fullName).")
        }
        if let employee = duplicateCodeEmployee {
            conflicts.append("This employee code already belongs to \(employee.fullName).")
        }
        return conflicts
    }

    private var isValid: Bool { missingRequirements.isEmpty && conflictMessages.isEmpty }

    private var cnic: Binding<String> {
        Binding(get: { draft.cnic }, set: { draft.cnic = CNICFormatter.format($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                if !missingRequirements.isEmpty {
                    Section {
                        Label("Complete the required information to enable Save.", systemImage: "info.circle.fill")
                            .foregroundStyle(CBTheme.info)
                        Text(missingRequirements.map { "• \(L10n.text($0.sentenceCased))" }.joined(separator: "\n"))
                            .font(.subheadline)
                            .foregroundStyle(CBTheme.muted)
                    }
                }

                if !conflictMessages.isEmpty {
                    Section {
                        Label("Employee already exists", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(conflictMessages.map { L10n.text($0) }.joined(separator: "\n"))
                            .font(.subheadline)
                        Text("Use this employee's own CNIC and a unique code, or cancel and edit the existing employee record.")
                            .font(.footnote)
                            .foregroundStyle(CBTheme.muted)
                    }
                }

                Section {
                    TextField("Employee code *", text: $draft.employeeCode)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .employeeCode)
                    TextField("Full legal name *", text: $draft.fullName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .fullName)
                    TextField("CNIC — enter 13 digits *", text: cnic)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .cnic)
                    TextField("Mobile number (optional)", text: $draft.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Type 4510283917427; the app will display 45102-8391742-7 automatically. A CNIC can only belong to one employee.")
                }

                Section {
                    TextField("Position *", text: $draft.position)
                        .focused($focusedField, equals: .position)
                    TextField("Department",text:$draft.department)
                    Picker("Employment type",selection:$draft.employmentType){Text("Full-time").tag("full_time");Text("Part-time").tag("part_time");Text("Contract").tag("contract");Text("Temporary").tag("temporary");Text("Intern").tag("intern")}
                    Picker("Reports to",selection:$draft.reportingManagerId){Text("Not assigned").tag("");ForEach(session.employees.filter{$0.id != draft.id}){Text($0.fullName).tag($0.id)}}
                    Picker("App role", selection: $draft.role) {
                        Text("Staff").tag("employee")
                        Text("Manager").tag("manager")
                    }
                    if draft.id != nil {
                        Picker("Status", selection: $draft.status) {
                            Text("Active").tag("active")
                            Text("Inactive").tag("inactive")
                        }
                    }
                    DatePicker("Joining date", selection: $draft.joiningDate, displayedComponents: .date)
                    Toggle("Probation end date",isOn:$draft.hasProbationEnd)
                    if draft.hasProbationEnd{DatePicker("Probation ends",selection:$draft.probationEndDate,displayedComponents:.date)}
                } header: {
                    Text("Employment")
                } footer: {
                    Text("The app role takes effect when the employee claims their app invite. Salary and pay day are configured separately in Payroll after saving.")
                }

                Section {
                    TextField("Current address *", text: $draft.address, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .address)
                    TextField("Emergency contact name",text:$draft.emergencyContactName)
                    TextField("Emergency contact phone",text:$draft.emergencyContactPhone).keyboardType(.phonePad)
                } header: {
                    Text("Contact")
                } footer: {
                    Text("* Required")
                }
            }
            .navigationTitle(L10n.text(draft.id == nil ? "Add Employee" : "Edit Employee"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await session.saveEmployee(draft) {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || session.isWorking)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .interactiveDismissDisabled(session.isWorking)
    }
}
