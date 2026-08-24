import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct WorkforceOperationsView: View {
    @Environment(AppSession.self) private var session
    @State private var section = 0
    @State private var shiftSheet = false
    @State private var correctionSheet = false
    @State private var documentSheet = false
    @State private var payrollSheet = false
    @State private var sharedDocument:URL?
    @State private var rosterActions=false
    @State private var lifecycleSheet=false
    @State private var assetSheet=false
    @State private var availabilitySheet=false
    @State private var editingShift:ShiftRosterEntry?
    @State private var foodChargeSheet=false

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing:16) {
                    Picker("Workspace",selection:$section) {
                        Text("Shifts").tag(0);Text("Corrections").tag(1);Text("People").tag(2);Text("Payroll").tag(3)
                    }.pickerStyle(.segmented)
                    Group {
                        switch section {
                        case 0: shifts
                        case 1: corrections
                        case 2: peopleOperations
                        default: payrollOperations
                        }
                    }
                }.padding(16).padding(.bottom,24)
            }
        }
        .navigationTitle(L10n.text("Workforce")).navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .sheet(isPresented:$shiftSheet){ShiftEditorSheet()}
        .sheet(item:$editingShift){ShiftEditorSheet(entry:$0)}
        .sheet(isPresented:$correctionSheet){AttendanceCorrectionRequestSheet()}
        .sheet(isPresented:$documentSheet){EmployeeDocumentSheet()}
        .sheet(isPresented:$payrollSheet){PayrollOperationsSheet()}
        .sheet(isPresented:$rosterActions){RosterActionsSheet()}
        .sheet(isPresented:$lifecycleSheet){LifecycleTaskSheet()}
        .sheet(isPresented:$assetSheet){EmployeeAssetSheet()}
        .sheet(isPresented:$availabilitySheet){AvailabilityEditorSheet()}
        .sheet(isPresented:$foodChargeSheet){SalaryFoodChargeSheet()}
        .sheet(isPresented:Binding(get:{sharedDocument != nil},set:{if !$0{sharedDocument=nil}})){if let sharedDocument{DocumentShareSheet(url:sharedDocument)}}
        .refreshable{await session.refreshWorkforceFeature()}
        .task(id:session.selectedBranchId){await session.refreshWorkforceFeature()}
        .overlay{if session.isWorking || (session.workforceIsLoading && session.shifts.isEmpty){LoadingOverlay()}}
    }

    private var shifts: some View {
        VStack(spacing:12) {
            HStack { SectionTitle(title:"Shift roster",subtitle:"Upcoming hours, breaks and approved swaps.",symbol:"calendar.badge.clock");Spacer();if session.role.canManagePeople{Menu{Button("Add Shift",systemImage:"plus"){shiftSheet=true};Button("Availability",systemImage:"clock.badge.checkmark"){availabilitySheet=true};Button("Copy or Publish Week",systemImage:"calendar.badge.checkmark"){rosterActions=true}}label:{Image(systemName:"ellipsis.circle.fill").font(.title2).foregroundStyle(CBTheme.orange)}}else{Button{availabilitySheet=true}label:{Image(systemName:"clock.badge.checkmark").font(.title3).foregroundStyle(CBTheme.orange)}} }
                .padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
            if session.shifts.isEmpty { EmptyState(symbol:"calendar.badge.exclamationmark",title:"No upcoming shifts",message:"Scheduled shifts will appear here.") }
            ForEach(session.shifts){entry in
                VStack(alignment:.leading,spacing:10) {
                    HStack { Text(employeeName(entry.employeeId)).font(.headline);Spacer();if entry.isPublished{Label("Published",systemImage:"checkmark.seal.fill").font(.caption).foregroundStyle(CBTheme.success)};StatusBadge(status:entry.status);if session.role.canManagePeople && entry.status != "cancelled"{Menu{Button("Edit",systemImage:"pencil"){editingShift=entry};Button("Cancel Shift",systemImage:"xmark.circle",role:.destructive){Task{await session.cancelShift(entry)}}}label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("Shift actions")} }
                    InfoRow(symbol:"calendar",title:entry.workDate,value:"\(shortTime(entry.startsAt)) – \(shortTime(entry.endsAt))")
                    InfoRow(symbol:"cup.and.saucer.fill",title:"Break",value:"\(entry.breakMinutes) minutes")
                    if !session.role.isAdministrator,entry.employeeId==session.ownEmployee?.id {
                        NavigationLink { ShiftSwapSheet(entry:entry) } label:{Label("Request Swap",systemImage:"arrow.triangle.swap")} .buttonStyle(.bordered)
                    }
                }.padding(17).cbGlass(cornerRadius:22,tint:CBTheme.surface.opacity(0.07))
            }
            if session.shiftsHaveMore { Button("Load More Shifts",systemImage:"arrow.down.circle"){Task{await session.loadMoreShifts()}}.buttonStyle(.bordered) }
            if session.role.isAdministrator,!session.shiftSwaps.filter({$0.status=="pending"||$0.status=="accepted"}).isEmpty {
                SectionTitle(title:"Pending swaps",symbol:"arrow.triangle.swap")
                ForEach(session.shiftSwaps.filter{$0.status=="pending"||$0.status=="accepted"}){request in
                    VStack(alignment:.leading,spacing:10){Text(request.reason).font(.subheadline);HStack{Button("Reject",role:.destructive){Task{await session.reviewShiftSwap(request,status:"rejected")}}.buttonStyle(.bordered);Spacer();Button("Approve"){Task{await session.reviewShiftSwap(request,status:"approved")}}.cbPrimaryButton()}}
                        .padding(16).cbGlass(cornerRadius:20,tint:CBTheme.warning.opacity(0.04))
                }
            }
        }
    }

    private var peopleOperations:some View {
        VStack(spacing:12) {
            HStack{SectionTitle(title:"Employee lifecycle",subtitle:"Files, onboarding, offboarding and issued assets.",symbol:"person.text.rectangle");Spacer();if session.role.canAdministerEmployees{Menu{Button("Upload File",systemImage:"doc.badge.plus"){documentSheet=true};Button("Add Task",systemImage:"checklist"){lifecycleSheet=true};Button("Issue Asset",systemImage:"shippingbox"){assetSheet=true}}label:{Image(systemName:"plus.circle.fill").font(.title2).foregroundStyle(CBTheme.orange)}}}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
            ForEach(session.lifecycleTasks.filter{$0.status=="pending"}){task in HStack{VStack(alignment:.leading){Text(task.title).font(.headline);Text("\(employeeName(task.employeeId)) • \(task.phase.sentenceCased)").font(.caption).foregroundStyle(CBTheme.muted)};Spacer();Button{Task{await session.completeLifecycleTask(task)}}label:{Image(systemName:"checkmark.circle")}.buttonStyle(.bordered)}.padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))}
            ForEach(session.employeeAssets.filter{$0.returnedOn==nil}){asset in HStack{Image(systemName:"shippingbox.fill").foregroundStyle(CBTheme.info);VStack(alignment:.leading){Text(asset.label).font(.headline);Text("\(employeeName(asset.employeeId)) • \(asset.assetType.sentenceCased)").font(.caption).foregroundStyle(CBTheme.muted)};Spacer();Button("Return"){Task{await session.returnEmployeeAsset(asset,condition:"Returned")}}.buttonStyle(.bordered)}.padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))}
            documents
        }
    }

    private var corrections: some View {
        VStack(spacing:12) {
            HStack { SectionTitle(title:"Attendance corrections",subtitle:"Request or review a missed check-in or check-out.",symbol:"clock.badge.exclamationmark");Spacer();if !session.role.isAdministrator{Button("Request",systemImage:"plus"){correctionSheet=true}.cbPrimaryButton()} }
                .padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
            if session.correctionRequests.isEmpty { EmptyState(symbol:"checkmark.circle",title:"No correction requests",message:"Requests and decisions will appear here.") }
            ForEach(session.correctionRequests){request in
                VStack(alignment:.leading,spacing:10) {
                    HStack{Text(employeeName(request.employeeId)).font(.headline);Spacer();StatusBadge(status:request.status)}
                    InfoRow(symbol:"calendar",title:"Work date",value:request.workDate)
                    if let checkIn=request.requestedCheckInAt{InfoRow(symbol:"arrow.right.circle",title:"Requested check-in",value:displayDateTime(checkIn))}
                    if let checkOut=request.requestedCheckOutAt{InfoRow(symbol:"arrow.left.circle",title:"Requested check-out",value:displayDateTime(checkOut))}
                    Text(request.reason).font(.caption).foregroundStyle(CBTheme.muted)
                    if session.role.isAdministrator,request.status=="pending" { HStack{Button("Reject",role:.destructive){Task{await session.reviewAttendanceCorrection(request,status:"rejected",note:"Reviewed in CB Employee Hub")}}.buttonStyle(.bordered);Spacer();Button("Approve"){Task{await session.reviewAttendanceCorrection(request,status:"approved",note:"Approved correction")}}.cbPrimaryButton()} }
                }.padding(17).cbGlass(cornerRadius:22,tint:CBTheme.surface.opacity(0.07))
            }
        }
    }

    private var documents: some View {
        VStack(spacing:12) {
            HStack { SectionTitle(title:"Employee documents",subtitle:"Contracts, CNIC, bank and employment records.",symbol:"folder.badge.person.crop");Spacer();if session.role.canManagePeople{Button("Upload",systemImage:"square.and.arrow.up"){documentSheet=true}.cbPrimaryButton()} }
                .padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
            if session.employeeDocuments.isEmpty { EmptyState(symbol:"folder",title:"No documents",message:"Private employee files will appear here.") }
            ForEach(session.employeeDocuments){document in
                HStack(spacing:12){Image(systemName:"doc.text.fill").foregroundStyle(CBTheme.info);VStack(alignment:.leading){Text(document.title).font(.subheadline.weight(.semibold));Text("\(employeeName(document.employeeId)) • \(document.documentType.sentenceCased)").font(.caption).foregroundStyle(CBTheme.muted)};Spacer();if let expiry=document.expiresOn{Text(expiry).font(.caption2).foregroundStyle(CBTheme.warning)};Button{Task{sharedDocument=await session.downloadEmployeeDocument(document)}}label:{Image(systemName:"square.and.arrow.up")}.buttonStyle(.bordered)}
                    .padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))
            }
            if session.employeeDocumentsHaveMore {
                Button { Task { await session.loadOlderEmployeeDocuments() } } label:{Label(session.olderDocumentsIsLoading ? "Loading…":"Load Older Documents",systemImage:"clock.arrow.circlepath").frame(maxWidth:.infinity)}
                    .buttonStyle(.bordered).disabled(session.olderDocumentsIsLoading)
            }
        }
    }

    private var payrollOperations: some View {
        VStack(spacing:12) {
            HStack { SectionTitle(title:"Payroll operations",subtitle:"Bank details, tax, food, loans and reimbursements.",symbol:"building.columns.fill");Spacer();Menu{Button("Extra Food",systemImage:"fork.knife"){foodChargeSheet=true};Button("Other Operation",systemImage:"plus"){payrollSheet=true}}label:{Image(systemName:"plus.circle.fill").font(.title2).foregroundStyle(CBTheme.orange)} }
                .padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
            ForEach(session.payrollLoans){loan in
                VStack(alignment:.leading,spacing:8){HStack{Text(loan.label).font(.headline);Spacer();StatusBadge(status:loan.status)};InfoRow(symbol:"banknote",title:employeeName(loan.employeeId),value:MoneyFormatter.pkr(minor:loan.outstandingMinor));InfoRow(symbol:"calendar.badge.minus",title:"Monthly installment",value:MoneyFormatter.pkr(minor:loan.installmentMinor))}.padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))
            }
            ForEach(session.reimbursements){item in
                VStack(alignment:.leading,spacing:8){HStack{Text(item.label).font(.headline);Spacer();StatusBadge(status:item.status)};InfoRow(symbol:"receipt",title:employeeName(item.employeeId),value:MoneyFormatter.pkr(minor:item.amountMinor));if session.role.canManagePayroll && item.status=="pending"{HStack{Button("Reject",role:.destructive){Task{await session.reviewReimbursement(item,status:"rejected")}}.buttonStyle(.bordered);Spacer();Button("Approve"){Task{await session.reviewReimbursement(item,status:"approved")}}.cbPrimaryButton()}}}.padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))
            }
            if session.payrollLoansHaveMore || session.reimbursementsHaveMore || session.payslipDocumentsHaveMore {
                Button { Task { await session.loadOlderPayrollOperations() } } label:{Label(session.olderLoansIsLoading ? "Loading…":"Load Older Payroll Records",systemImage:"clock.arrow.circlepath").frame(maxWidth:.infinity)}
                    .buttonStyle(.bordered).disabled(session.olderLoansIsLoading)
            }
            if session.role.canManagePayroll {
                ForEach(session.statutoryRules.filter(\.isActive)){rule in
                    InfoRow(symbol:"building.columns.circle.fill",title:rule.name,value:statutoryValue(rule),color:CBTheme.info).padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))
                }
            }
        }
    }

    private func employeeName(_ id:String)->String{session.employees.first{$0.id==id}?.fullName ?? "Employee"}
    private func statutoryValue(_ rule:PayrollStatutoryRule)->String {
        if rule.ruleType=="fixed_deduction" { return MoneyFormatter.pkr(minor:rule.configuration.amountMinor ?? 0) }
        return String(format:"%.2f%% of gross",rule.configuration.ratePercent ?? 0)
    }
    private func shortTime(_ value:String)->String{String(value.prefix(5))}
    private func displayDateTime(_ value:String)->String{guard let date=ISO8601DateFormatter().date(from:value) else{return value};return L10n.date(date,dateStyle:.medium,timeStyle:.short)}
}

struct DocumentShareSheet:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}

private struct ShiftEditorSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session
    let entry:ShiftRosterEntry?
    @State private var employeeId="";@State private var date=Date();@State private var start=Calendar.current.date(bySettingHour:9,minute:0,second:0,of:.now) ?? .now;@State private var end=Calendar.current.date(bySettingHour:18,minute:0,second:0,of:.now) ?? .now;@State private var breakMinutes=60;@State private var notes="";@State private var repeatWeeks=1
    init(entry:ShiftRosterEntry?=nil){self.entry=entry}
    var body:some View{NavigationStack{Form{Section("Shift"){Picker("Employee",selection:$employeeId){Text("Select").tag("");ForEach(session.employees.filter{$0.employmentStatus=="active"}){Text($0.fullName).tag($0.id)}};DatePicker("Date",selection:$date,displayedComponents:.date);DatePicker("Starts",selection:$start,displayedComponents:.hourAndMinute);DatePicker("Ends",selection:$end,displayedComponents:.hourAndMinute);Stepper("Break: \(breakMinutes) minutes",value:$breakMinutes,in:0...180,step:15);if entry==nil{Picker("Repeat",selection:$repeatWeeks){Text("Once").tag(1);ForEach(2...12,id:\.self){Text("Weekly for \($0) weeks").tag($0)}}};TextField("Notes",text:$notes)}}.navigationTitle(L10n.text(entry==nil ? "Schedule Shift":"Edit Shift")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){Task{let ok:Bool;if let entry{ok=await session.updateShift(id:entry.id,employeeId:employeeId,date:date,start:start,end:end,breakMinutes:breakMinutes,notes:notes)}else{ok=await session.saveShift(employeeId:employeeId,date:date,start:start,end:end,breakMinutes:breakMinutes,notes:notes,weeks:repeatWeeks)};if ok{dismiss()}}}.disabled(employeeId.isEmpty)}}.onAppear{loadEntry()}}}
    private func loadEntry(){guard let entry else{return};employeeId=entry.employeeId;date=ISODate.date(from:entry.workDate) ?? .now;let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="HH:mm:ss";start=formatter.date(from:entry.startsAt) ?? start;end=formatter.date(from:entry.endsAt) ?? end;breakMinutes=entry.breakMinutes;notes=entry.notes ?? ""}
}

private struct AvailabilityEditorSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var employeeId=""
    @State private var weekday=1
    @State private var isAvailable=true
    @State private var availableFrom=Calendar.current.date(bySettingHour:9,minute:0,second:0,of:.now) ?? .now
    @State private var availableUntil=Calendar.current.date(bySettingHour:18,minute:0,second:0,of:.now) ?? .now
    @State private var note=""
    private let weekdays=["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

    var body:some View {
        NavigationStack {
            Form {
                if session.role.canManagePeople {
                    Picker("Employee",selection:$employeeId){Text("Select").tag("");ForEach(session.employees.filter{$0.employmentStatus=="active"}){Text($0.fullName).tag($0.id)}}
                } else if let employee=session.ownEmployee {
                    LabeledContent("Employee",value:employee.fullName)
                }
                Picker("Weekday",selection:$weekday){ForEach(1...7,id:\.self){Text(weekdays[$0-1]).tag($0)}}
                Toggle("Available",isOn:$isAvailable)
                if isAvailable {
                    DatePicker("From",selection:$availableFrom,displayedComponents:.hourAndMinute)
                    DatePicker("Until",selection:$availableUntil,displayedComponents:.hourAndMinute)
                }
                TextField("Note",text:$note)
            }
            .navigationTitle(L10n.text("Availability"))
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Save"){Task{if await session.saveAvailability(employeeId:employeeId,weekday:weekday,isAvailable:isAvailable,from:availableFrom,until:availableUntil,note:note){dismiss()}}}.disabled(employeeId.isEmpty)}
            }
            .onAppear { employeeId=session.role.canManagePeople ? "":(session.ownEmployee?.id ?? "");loadExisting() }
            .onChange(of:employeeId){_,_ in loadExisting()}
            .onChange(of:weekday){_,_ in loadExisting()}
        }
    }

    private func loadExisting(){
        guard let row=session.employeeAvailability.first(where:{$0.employeeId==employeeId && $0.weekday==weekday}) else{return}
        isAvailable=row.isAvailable;note=row.note ?? ""
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="HH:mm:ss"
        if let value=row.availableFrom,let parsed=formatter.date(from:value){availableFrom=parsed}
        if let value=row.availableUntil,let parsed=formatter.date(from:value){availableUntil=parsed}
    }
}

private struct RosterActionsSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session
    @State private var mode=0;@State private var source=Date();@State private var target=Calendar.current.date(byAdding:.day,value:7,to:.now) ?? .now
    private func weekStart(_ date:Date)->Date{let calendar=Calendar(identifier:.gregorian);let weekday=calendar.component(.weekday,from:date);return calendar.date(byAdding:.day,value:weekday==1 ? -6:2-weekday,to:calendar.startOfDay(for:date)) ?? date}
    var body:some View{NavigationStack{Form{Picker("Action",selection:$mode){Text("Copy Week").tag(0);Text("Publish Week").tag(1)}.pickerStyle(.segmented);DatePicker(mode==0 ? "Source week":"Week",selection:$source,displayedComponents:.date);if mode==0{DatePicker("Target week",selection:$target,displayedComponents:.date)};Section{Button(mode==0 ? "Copy Roster":"Publish Roster"){Task{let ok=mode==0 ? await session.copyRoster(sourceStart:weekStart(source),targetStart:weekStart(target)):await session.publishRoster(weekStart:weekStart(source));if ok{dismiss()}}}.cbPrimaryButton()}}.navigationTitle(L10n.text("Roster Actions")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}}
}

private struct LifecycleTaskSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session
    @State private var employee="";@State private var phase="onboarding";@State private var title="";@State private var hasDue=true;@State private var due=Date()
    var body:some View{NavigationStack{Form{Picker("Employee",selection:$employee){Text("Select").tag("");ForEach(session.employees){Text($0.fullName).tag($0.id)}};Picker("Phase",selection:$phase){Text("Onboarding").tag("onboarding");Text("Probation").tag("probation");Text("Offboarding").tag("offboarding")};TextField("Task",text:$title);Toggle("Due date",isOn:$hasDue);if hasDue{DatePicker("Due",selection:$due,displayedComponents:.date)}}.navigationTitle(L10n.text("Lifecycle Task")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){Task{if await session.addLifecycleTask(employeeId:employee,phase:phase,title:title,dueOn:hasDue ? due:nil){dismiss()}}}.disabled(employee.isEmpty||title.count<2)}}}}
}

private struct EmployeeAssetSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session
    @State private var employee="";@State private var type="uniform";@State private var label="";@State private var identifier="";@State private var date=Date()
    var body:some View{NavigationStack{Form{Picker("Employee",selection:$employee){Text("Select").tag("");ForEach(session.employees){Text($0.fullName).tag($0.id)}};TextField("Asset type",text:$type);TextField("Description",text:$label);TextField("Identifier",text:$identifier);DatePicker("Issued",selection:$date,displayedComponents:.date)}.navigationTitle(L10n.text("Issue Asset")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Issue"){Task{if await session.addEmployeeAsset(employeeId:employee,type:type,label:label,identifier:identifier,date:date){dismiss()}}}.disabled(employee.isEmpty||label.count<2)}}}}
}

private struct ShiftSwapSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session;let entry:ShiftRosterEntry;@State private var target="";@State private var reason=""
    var body:some View {
        Form {
            Picker("Swap with",selection:$target) {
                Text("Open request").tag("")
                ForEach(session.employees.filter{$0.id != entry.employeeId && $0.employmentStatus=="active"}) {
                    Text($0.fullName).tag($0.id)
                }
            }
            TextField("Reason",text:$reason,axis:.vertical)
            Button("Submit Swap Request") {
                Task {
                    if await session.requestShiftSwap(entry,targetEmployeeId:target.isEmpty ? nil:target,reason:reason) { dismiss() }
                }
            }
            .disabled(reason.trimmingCharacters(in:.whitespaces).count<5)
        }
        .navigationTitle(L10n.text("Shift Swap"))
    }
}

private struct AttendanceCorrectionRequestSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session
    @State private var date=Date();@State private var checkIn=Date();@State private var checkOut=Date();@State private var hasIn=true;@State private var hasOut=false;@State private var reason=""
    var body:some View{NavigationStack{Form{Section("Requested record"){DatePicker("Work date",selection:$date,displayedComponents:.date);Toggle("Add check-in",isOn:$hasIn);if hasIn{DatePicker("Check-in",selection:$checkIn)};Toggle("Add check-out",isOn:$hasOut);if hasOut{DatePicker("Check-out",selection:$checkOut)};TextField("What happened?",text:$reason,axis:.vertical)}}.navigationTitle(L10n.text("Correction Request")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Submit"){Task{if await session.requestAttendanceCorrection(date:date,checkIn:hasIn ? checkIn:nil,checkOut:hasOut ? checkOut:nil,reason:reason){dismiss()}}}.disabled((!hasIn && !hasOut)||reason.trimmingCharacters(in:.whitespaces).count<5)}}}}
}

private struct EmployeeDocumentSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session
    @State private var employeeId="";@State private var type="contract";@State private var title="";@State private var file:URL?;@State private var importer=false;@State private var hasExpiry=false;@State private var expiry=Date()
    var body:some View{NavigationStack{Form{Picker("Employee",selection:$employeeId){Text("Select").tag("");ForEach(session.employees){Text($0.fullName).tag($0.id)}};Picker("Document type",selection:$type){ForEach(["cnic","contract","bank","certificate","warning","medical","termination","other"],id:\.self){Text($0.sentenceCased).tag($0)}};TextField("Title",text:$title);Toggle("Has expiry",isOn:$hasExpiry);if hasExpiry{DatePicker("Expires",selection:$expiry,displayedComponents:.date)};Button(file?.lastPathComponent ?? "Choose File",systemImage:"paperclip"){importer=true}}.navigationTitle(L10n.text("Employee Document")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Upload"){Task{if let file,await session.uploadEmployeeDocument(employeeId:employeeId,type:type,title:title,fileURL:file,expiresOn:hasExpiry ? expiry:nil){dismiss()}}}.disabled(employeeId.isEmpty||title.count<2||file==nil)}}.fileImporter(isPresented:$importer,allowedContentTypes:[.pdf,.image,.plainText]){if case .success(let url)=$0{file=url}}}}
}

private struct PayrollOperationsSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session
    @State private var mode=0;@State private var employeeId="";@State private var label="";@State private var amount="";@State private var installment="";@State private var reason="";@State private var date=Date();@State private var bank="";@State private var account="";@State private var iban="";@State private var taxNumber="";@State private var eobiNumber="";@State private var tax="0";@State private var eobi="0";@State private var ruleCode="";@State private var ruleType="fixed_deduction"
    var body:some View{NavigationStack{Form{Picker("Operation",selection:$mode){Text("Expense").tag(0);if session.role.canManagePayroll{Text("Loan").tag(1);Text("Profile").tag(2);Text("Rule").tag(3)}}.pickerStyle(.segmented);if session.role.canManagePayroll && mode != 3{Picker("Employee",selection:$employeeId){Text("Select").tag("");ForEach(session.employees){Text($0.fullName).tag($0.id)}}};if mode==2{TextField("Bank",text:$bank);TextField("Account title",text:$account);TextField("IBAN",text:$iban).textInputAutocapitalization(.characters);TextField("NTN / tax number",text:$taxNumber);TextField("EOBI number",text:$eobiNumber);TextField("Monthly tax (PKR)",text:$tax).keyboardType(.decimalPad);TextField("Monthly EOBI (PKR)",text:$eobi).keyboardType(.decimalPad)}else if mode==3{TextField("Rule code (for example EOBI)",text:$ruleCode).textInputAutocapitalization(.characters);TextField("Rule name",text:$label);Picker("Calculation",selection:$ruleType){Text("Fixed PKR").tag("fixed_deduction");Text("Percent of gross").tag("percentage_deduction")};TextField(ruleType=="fixed_deduction" ? "Amount (PKR)":"Percentage",text:$amount).keyboardType(.decimalPad);DatePicker("Effective from",selection:$date,displayedComponents:.date)}else{TextField(mode==0 ? "Expense label":"Loan label",text:$label);TextField(mode==0 ? "Amount (PKR)":"Principal (PKR)",text:$amount).keyboardType(.decimalPad);if mode==1{TextField("Monthly installment (PKR)",text:$installment).keyboardType(.decimalPad)};DatePicker(mode==0 ? "Expense date":"Starts",selection:$date,displayedComponents:.date);if mode==0{TextField("Reason",text:$reason,axis:.vertical)}}}.navigationTitle(L10n.text("Payroll Operation")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){Task{let target=employeeId.isEmpty ? session.ownEmployee?.id ?? "":employeeId;let ok:Bool;if mode==0{ok=await session.submitReimbursement(label:label,amount:Double(amount) ?? 0,date:date,reason:reason,employeeId:target)}else if mode==1{ok=await session.createPayrollLoan(employeeId:target,label:label,principal:Double(amount) ?? 0,installment:Double(installment) ?? 0,start:date)}else if mode==2{ok=await session.saveFinancialProfile(employeeId:target,bank:bank,accountTitle:account,iban:iban,taxNumber:taxNumber,eobiNumber:eobiNumber,tax:Double(tax) ?? 0,eobi:Double(eobi) ?? 0)}else{ok=await session.addStatutoryRule(code:ruleCode,name:label,type:ruleType,value:Double(amount) ?? 0,effectiveFrom:date)};if ok{dismiss()}}}.disabled((mode != 2 && (label.isEmpty || Double(amount)==nil)) || (mode==3 && ruleCode.isEmpty))}}}}
}
