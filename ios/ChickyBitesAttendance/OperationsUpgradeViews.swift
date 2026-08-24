import SwiftUI
import UIKit

struct AttendanceHistoryView:View {
    @Environment(AppSession.self) private var session
    let employee:Employee?
    @State private var filters=false
    @State private var correction:AttendanceHistoryEntry?

    init(employee:Employee?=nil){self.employee=employee}

    var body:some View {
        CreamPage {
            ScrollView {
                LazyVStack(spacing:14) {
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            SectionTitle(title:employee.map{"\($0.fullName) Attendance"} ?? (session.role == .staff ? "My Attendance History":"Attendance History"),symbol:"calendar.badge.clock")
                            Spacer()
                            Button{filters=true} label:{Label(L10n.text("Filters"),systemImage:"line.3.horizontal.decrease.circle")}.buttonStyle(.bordered)
                        }
                        HStack(spacing:10) {
                            HistoryMetric(title:"Days",value:"\(session.attendanceHistory.count)",color:CBTheme.info)
                            HistoryMetric(title:"Late",value:"\(session.attendanceHistory.reduce(0){$0+$1.lateMinutes}) min",color:CBTheme.warning)
                            HistoryMetric(title:"Overtime",value:"\(session.attendanceHistory.reduce(0){$0+$1.overtimeMinutes}) min",color:CBTheme.success)
                        }
                    }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))

                    if session.attendanceHistoryIsLoading && session.attendanceHistory.isEmpty {
                        LoadingStateCard(title:"Loading history",message:"Getting your attendance records…")
                    } else if session.attendanceHistory.isEmpty {
                        EmptyState(symbol:"calendar.badge.exclamationmark",title:"No attendance records",message:"Records in the selected period will appear here.")
                    } else {
                        ForEach(session.attendanceHistory){entry in AttendanceHistoryRow(entry:entry,onCorrection:session.role == .staff ? {correction=entry}:nil)}
                    }
                    if session.attendanceHistoryHasMore {
                        Button{Task{await session.loadAttendanceHistory(employeeId:employee?.id,reset:false)}} label:{Label(L10n.text("Load Older Attendance"),systemImage:"clock.arrow.circlepath")}
                            .buttonStyle(.bordered).disabled(session.attendanceHistoryIsLoading)
                    }
                    if session.attendanceHistoryIsLoading && !session.attendanceHistory.isEmpty { ProgressView().padding() }
                }.padding(16).padding(.bottom,24)
            }.refreshable{await session.loadAttendanceHistory(employeeId:employee?.id)}
        }
        .navigationTitle(L10n.text("Attendance History")).navigationBarTitleDisplayMode(.inline)
        .toolbar{StandardToolbar()}
        .task(id:"\(session.selectedBranchId ?? "")-\(employee?.id ?? session.ownEmployee?.id ?? "all")"){await session.loadAttendanceHistory(employeeId:employee?.id)}
        .sheet(isPresented:$filters){AttendanceHistoryFilterSheet(employeeId:employee?.id)}
        .sheet(item:$correction){AttendanceHistoryCorrectionSheet(entry:$0)}
        .diagnosticScreen("Attendance History")
    }
}

private struct HistoryMetric:View {
    let title,value:String;let color:Color
    var body:some View { VStack(alignment:.leading,spacing:4){Text(L10n.text(title)).font(.caption).foregroundStyle(CBTheme.muted);Text(L10n.text(value)).font(.subheadline.weight(.bold)).foregroundStyle(color)}.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(color.opacity(0.08),in:RoundedRectangle(cornerRadius:15)) }
}

private struct AttendanceHistoryRow:View {
    let entry:AttendanceHistoryEntry
    let onCorrection:(()->Void)?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4){Text(historyDate(entry.workDate)).font(.headline);if entry.employeeName.isEmpty==false{Text("\(entry.employeeCode) • \(entry.employeeName)").font(.caption).foregroundStyle(CBTheme.muted)}}
                Spacer();StatusBadge(status:entry.status)
            }
            Divider().overlay(CBTheme.divider)
            HStack(spacing:18) {
                if let value=entry.firstCheckInAt { HistoryTime(symbol:"arrow.right.circle.fill",title:"In",value:historyTime(value),color:CBTheme.success) }
                if let value=entry.lastCheckOutAt { HistoryTime(symbol:"arrow.left.circle.fill",title:"Out",value:historyTime(value),color:CBTheme.info) }
                HistoryTime(symbol:"cup.and.saucer.fill",title:"Break",value:"\(entry.breakMinutes) min",color:CBTheme.warning)
            }
            HStack(spacing:8) {
                if entry.lateMinutes>0 { StatusPill(text:"Late \(entry.lateMinutes) min",color:CBTheme.warning) }
                if entry.overtimeMinutes>0 { StatusPill(text:"Overtime \(entry.overtimeMinutes) min",color:CBTheme.success) }
                if let method=entry.markMethod { StatusPill(text:method.sentenceCased,color:entry.usedOverride ? CBTheme.warning:CBTheme.info) }
                if let status=entry.correctionStatus { StatusPill(text:"Correction \(status.sentenceCased)",color:CBTheme.info) }
            }
            if let onCorrection { Button{onCorrection()} label:{Label(L10n.text("Request Correction"),systemImage:"pencil.and.list.clipboard")}.buttonStyle(.bordered) }
        }.padding(16).cbGlass(cornerRadius:21,tint:CBTheme.surface.opacity(0.06))
    }
}

private struct HistoryTime:View {
    let symbol,title,value:String;let color:Color
    var body:some View { VStack(alignment:.leading,spacing:3){Label(L10n.text(title),systemImage:symbol).font(.caption).foregroundStyle(color);Text(value).font(.caption.weight(.semibold))} }
}

private struct StatusPill:View {
    let text:String;let color:Color
    var body:some View { Text(L10n.text(text)).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal,8).padding(.vertical,5).background(color.opacity(0.1),in:Capsule()) }
}

private struct AttendanceHistoryFilterSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let employeeId:String?
    var body:some View { @Bindable var session=session;NavigationStack{Form{DatePicker("From",selection:$session.attendanceHistoryFilter.from,displayedComponents:.date);DatePicker("To",selection:$session.attendanceHistoryFilter.to,in:session.attendanceHistoryFilter.from...,displayedComponents:.date)}.navigationTitle(L10n.text("Attendance Filters")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Apply"){Task{await session.loadAttendanceHistory(employeeId:employeeId);dismiss()}}}}} }
}

private struct AttendanceHistoryCorrectionSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let entry:AttendanceHistoryEntry
    @State private var checkIn=Date()
    @State private var checkOut=Date()
    @State private var reason=""
    @State private var hasCheckIn=true
    @State private var hasCheckOut=true
    var body:some View {NavigationStack{Form{Section(entry.workDate){Toggle(isOn:$hasCheckIn){Text(L10n.text("Correct check-in"))};if hasCheckIn{DatePicker("Check-in",selection:$checkIn)};Toggle(isOn:$hasCheckOut){Text(L10n.text("Correct check-out"))};if hasCheckOut{DatePicker("Check-out",selection:$checkOut)};TextField(L10n.text("Explain what should be corrected"),text:$reason,axis:.vertical)};Section{Button{Task{guard let date=ISODate.date(from:entry.workDate)else{return};if await session.requestAttendanceCorrection(date:date,checkIn:hasCheckIn ? combined(day:date,time:checkIn):nil,checkOut:hasCheckOut ? combined(day:date,time:checkOut):nil,reason:reason){dismiss()}}} label:{Text(L10n.text("Submit Correction Request"))}.disabled(reason.trimmingCharacters(in:.whitespacesAndNewlines).count<5)}}.navigationTitle(L10n.text("Attendance Correction")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}.onAppear{checkIn=historyDateTime(entry.firstCheckInAt) ?? checkIn;checkOut=historyDateTime(entry.lastCheckOutAt) ?? checkOut;hasCheckIn=entry.firstCheckInAt != nil;hasCheckOut=entry.lastCheckOutAt != nil}}}
}

struct AdvancedReportsView:View {
    @Environment(AppSession.self) private var session
    @State private var filter=WorkforceReportFilter()
    @State private var showingFilters=false
    @State private var shareURL:URL?
    var body:some View {
        CreamPage { ScrollView { LazyVStack(spacing:14) {
            VStack(alignment:.leading,spacing:12) {
                HStack{SectionTitle(title:"Advanced Reports",symbol:"doc.text.magnifyingglass");Spacer();Button{showingFilters=true} label:{Label(L10n.text("Filters"),systemImage:"line.3.horizontal.decrease.circle")}.buttonStyle(.bordered)}
                HStack{Text("\(session.workforceReportRows.count) \(L10n.text("records"))").font(.subheadline.weight(.semibold));Spacer();Button("PDF",systemImage:"doc.richtext"){export(pdf:true)}.buttonStyle(.bordered).disabled(session.workforceReportRows.isEmpty);Button("CSV",systemImage:"tablecells"){export(pdf:false)}.buttonStyle(.bordered).disabled(session.workforceReportRows.isEmpty)}
            }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
            if session.workforceReportIsLoading && session.workforceReportRows.isEmpty { LoadingStateCard(title:"Loading report",message:"Applying your filters…") }
            else if session.workforceReportRows.isEmpty { EmptyState(symbol:"doc.text",title:"No report records",message:"Change the filters or date range and try again.") }
            else { ForEach(session.workforceReportRows){ReportResultRow(row:$0)} }
            if session.workforceReportHasMore { Button{Task{await session.loadWorkforceReport(filter:filter,reset:false)}} label:{Label(L10n.text("Load Older Records"),systemImage:"clock.arrow.circlepath")}.buttonStyle(.bordered).disabled(session.workforceReportIsLoading) }
            if session.workforceReportIsLoading && !session.workforceReportRows.isEmpty { ProgressView().padding() }
        }.padding(16).padding(.bottom,24) }.refreshable{await session.loadWorkforceReport(filter:filter)} }
        .navigationTitle(L10n.text("Reports")).navigationBarTitleDisplayMode(.inline).toolbar{StandardToolbar()}
        .task(id:session.selectedBranchId){await session.loadWorkforceReport(filter:filter)}
        .sheet(isPresented:$showingFilters){AdvancedReportFilterSheet(filter:$filter)}
        .sheet(isPresented:Binding(get:{shareURL != nil},set:{if !$0{shareURL=nil}})){if let shareURL{DocumentShareSheet(url:shareURL)}}
        .diagnosticScreen("Advanced Reports")
    }
    private func export(pdf:Bool){Task{let rows=await session.completeWorkforceReport(filter:filter);guard !rows.isEmpty else{return};shareURL=await AdvancedReportExport.make(rows:rows,kind:filter.kind,pdf:pdf)}}
}

private struct ReportResultRow:View {
    let row:WorkforceReportRow
    var body:some View {VStack(alignment:.leading,spacing:10){HStack{VStack(alignment:.leading,spacing:3){Text(row.employeeName).font(.headline);Text("\(row.employeeCode) • \(historyDate(row.recordDate))").font(.caption).foregroundStyle(CBTheme.muted)};Spacer();StatusBadge(status:row.status)};if let details=row.details{Text(L10n.text(details)).font(.subheadline).foregroundStyle(CBTheme.muted)};HStack(spacing:8){StatusPill(text:row.reportType.sentenceCased,color:CBTheme.info);if let method=row.markMethod{StatusPill(text:method.sentenceCased,color:row.usedOverride==true ? CBTheme.warning:CBTheme.info)};if let rejection=row.rejectionCode{StatusPill(text:rejection.sentenceCased,color:CBTheme.danger)};if let amount=row.amountMinor{Spacer();Text(MoneyFormatter.pkr(minor:amount)).font(.subheadline.weight(.bold))}}}.padding(16).cbGlass(cornerRadius:21,tint:CBTheme.surface.opacity(0.06)) }
}

private struct AdvancedReportFilterSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Binding var filter:WorkforceReportFilter
    var body:some View {NavigationStack{Form{Section(L10n.text("Date")){DatePicker("From",selection:$filter.from,displayedComponents:.date);DatePicker("To",selection:$filter.to,in:filter.from...,displayedComponents:.date)};Section(L10n.text("Report")){Picker(L10n.text("Type"),selection:$filter.kind){Text(L10n.text("All")).tag("all");Text(L10n.text("Attendance")).tag("attendance");Text(L10n.text("Leave")).tag("leave");Text(L10n.text("Payroll")).tag("payroll")};if session.role.canManagePeople{Picker(L10n.text("Employee"),selection:$filter.employeeId){Text(L10n.text("All employees")).tag("");ForEach(session.employees){Text("\($0.employeeCode) — \($0.fullName)").tag($0.id)}}};Picker(L10n.text("Status"),selection:$filter.status){Text(L10n.text("All")).tag("all");ForEach(["present","absent","leave","partial","rejected","pending","approved","paid"],id:\.self){Text(L10n.text($0.sentenceCased)).tag($0)}};Picker(L10n.text("Marking method"),selection:$filter.markMethod){Text(L10n.text("All")).tag("all");Text(L10n.text("Restaurant IP")).tag("ip");Text(L10n.text("GPS")).tag("gps");Text(L10n.text("Manager override")).tag("override");Text(L10n.text("Offline verified")).tag("offline")};Picker(L10n.text("Override"),selection:$filter.overrideMode){Text(L10n.text("All")).tag("all");Text(L10n.text("Used")).tag("yes");Text(L10n.text("Not used")).tag("no")};TextField(L10n.text("Search employee, code, or reason"),text:$filter.search)}}.navigationTitle(L10n.text("Report Filters")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Apply"){Task{await session.loadWorkforceReport(filter:filter);dismiss()}}}}}}
}

struct OperationsHealthView:View {
    @Environment(AppSession.self) private var session
    var body:some View {CreamPage{ScrollView{VStack(spacing:14){
        VStack(alignment:.leading,spacing:12){HStack{SectionTitle(title:"Operations Health",symbol:"waveform.path.ecg.rectangle");Spacer();if session.operationsHealthIsLoading{ProgressView()}};Text(session.operationsHealth?.backendOk==true ? L10n.text("All core services are responding."):L10n.text("Health information is unavailable.")).font(.subheadline).foregroundStyle(session.operationsHealth?.backendOk==true ? CBTheme.success:CBTheme.warning)}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
        if let health=session.operationsHealth {
            VStack(spacing:10) {
                NavigationLink { DiagnosticFeedView() } label: { Label(L10n.text("View Diagnostics"),systemImage:"stethoscope").frame(maxWidth:.infinity) }.cbSecondaryButton()
                NavigationLink { NotificationRecoveryView() } label: { Label(L10n.text("Notification Recovery"),systemImage:"bell.badge.waveform.fill").frame(maxWidth:.infinity) }.cbSecondaryButton()
            }
            HealthRow(symbol:"network",title:"Backend connection",value:health.backendOk ? "Connected":"Unavailable",healthy:health.backendOk)
            HealthRow(symbol:"location.fill",title:"Branch location",value:health.missingBranchLocation ? "Needs configuration":"Ready",healthy:!health.missingBranchLocation)
            HealthRow(symbol:"wifi",title:"Approved restaurant IPs",value:"\(health.activeIPRules) active",healthy:health.activeIPRules>0)
            HealthRow(symbol:"person.crop.circle.badge.checkmark",title:"Face enrollment",value:"\(health.missingFaceEnrollments) missing",healthy:health.missingFaceEnrollments==0)
            HealthRow(symbol:"calendar.badge.clock",title:"Schedules",value:"\(health.missingSchedules) missing",healthy:health.missingSchedules==0)
            HealthRow(symbol:"banknote.fill",title:"Salary configuration",value:"\(health.missingCompensations) missing",healthy:health.missingCompensations==0)
            HealthRow(symbol:"bell.badge.fill",title:"Push delivery",value:"\(health.failedPushNotifications) failed • \(health.pendingPushNotifications) pending",healthy:health.failedPushNotifications==0)
            HealthRow(symbol:"location.slash.fill",title:"Rejected attendance (7 days)",value:"\(health.attendanceRejections7d)",healthy:health.attendanceRejections7d==0)
            HealthRow(symbol:"iphone.gen3",title:"iOS diagnostics (7 days)",value:"\(health.crashes7d) crashes • \(health.errors7d) errors",healthy:health.crashes7d==0)
            HealthRow(symbol:"arrow.triangle.2.circlepath",title:"Pending offline attendance",value:"\(session.offlineAttendanceCount)",healthy:session.offlineAttendanceCount==0)
            if !health.topRejectionReasons.isEmpty {VStack(alignment:.leading,spacing:10){SectionTitle(title:"Common rejection reasons",symbol:"exclamationmark.triangle.fill");ForEach(health.topRejectionReasons){reason in InfoRow(symbol:"xmark.circle",title:reason.code.sentenceCased,value:"\(reason.count)",color:CBTheme.warning)}}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.warning.opacity(0.05))}
        } else if !session.operationsHealthIsLoading {EmptyState(symbol:"waveform.path.ecg",title:"Health information unavailable",message:"Pull to refresh when the internet connection is available.")}
    }.padding(16).padding(.bottom,24)}}.navigationTitle(L10n.text("Operations Health")).navigationBarTitleDisplayMode(.inline).toolbar{StandardToolbar()}.task(id:session.selectedBranchId){await session.loadOperationsHealth()}.refreshable{await session.loadOperationsHealth()}.diagnosticScreen("Operations Health")}
}

private struct HealthRow:View {let symbol,title,value:String;let healthy:Bool;var body:some View{HStack(spacing:13){Image(systemName:symbol).foregroundStyle(healthy ? CBTheme.success:CBTheme.warning).frame(width:38,height:38).background((healthy ? CBTheme.success:CBTheme.warning).opacity(0.1),in:RoundedRectangle(cornerRadius:12));VStack(alignment:.leading,spacing:3){Text(L10n.text(title)).font(.headline);Text(L10n.text(value)).font(.caption).foregroundStyle(CBTheme.muted)};Spacer();Image(systemName:healthy ? "checkmark.circle.fill":"exclamationmark.triangle.fill").foregroundStyle(healthy ? CBTheme.success:CBTheme.warning)}.padding(16).cbGlass(cornerRadius:21,tint:CBTheme.surface.opacity(0.06))}}

struct OwnerSetupChecklistView:View {
    @Environment(AppSession.self) private var session
    var body:some View {CreamPage{ScrollView{VStack(spacing:14){
        VStack(alignment:.leading,spacing:8){SectionTitle(title:"Restaurant Setup",symbol:"checklist");Text(L10n.text("Complete these items before using attendance and payroll with real employees.")).font(.subheadline).foregroundStyle(CBTheme.muted)}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
        SetupLink(title:"Branch location and IP",detail:"Coordinates, 50-metre radius, and restaurant Wi-Fi",complete:session.operationsHealth.map{!$0.missingBranchLocation && $0.activeIPRules>0} ?? false){BranchSettingsView()}
        SetupLink(title:"Employees and branch assignments",detail:"Identity, contact details, role, and joining date",complete:(session.operationsHealth?.activeEmployees ?? 0)>0){EmployeesView()}
        SetupLink(title:"Attendance face enrollment",detail:"Enroll every employee who will mark attendance",complete:(session.operationsHealth?.missingFaceEnrollments ?? 1)==0){EmployeesView()}
        SetupLink(title:"Schedules",detail:"Working days, check-in, checkout, breaks, and grace time",complete:(session.operationsHealth?.missingSchedules ?? 1)==0){ScheduleManagementView()}
        SetupLink(title:"Leave policies",detail:"Sick, urgent, and normal leave entitlements",complete:!session.leaveTypes.isEmpty){LeavesView()}
        SetupLink(title:"Salary and payroll",detail:"Base salary, deductions, pay dates, and rules",complete:(session.operationsHealth?.missingCompensations ?? 1)==0){PayrollView()}
        SetupLink(title:"Notifications",detail:"Enable alerts and confirm delivery health",complete:(session.operationsHealth?.failedPushNotifications ?? 1)==0){OperationsCenterView()}
    }.padding(16).padding(.bottom,24)}}.navigationTitle(L10n.text("Setup Checklist")).navigationBarTitleDisplayMode(.inline).toolbar{StandardToolbar()}.task(id:session.selectedBranchId){await session.loadOperationsHealth()}.diagnosticScreen("Setup Checklist")}
}

private struct SetupLink<Destination:View>:View {let title,detail:String;let complete:Bool;@ViewBuilder let destination:()->Destination;var body:some View{NavigationLink(destination:destination()){HStack(spacing:13){Image(systemName:complete ? "checkmark.circle.fill":"circle.dashed").font(.title3).foregroundStyle(complete ? CBTheme.success:CBTheme.warning);VStack(alignment:.leading,spacing:4){Text(L10n.text(title)).font(.headline);Text(L10n.text(detail)).font(.caption).foregroundStyle(CBTheme.muted)};Spacer();Image(systemName:"chevron.right").foregroundStyle(CBTheme.muted)}}.buttonStyle(.plain).padding(16).cbGlass(cornerRadius:21,tint:CBTheme.surface.opacity(0.06))}}

struct HelpCenterView:View {
    @Environment(AppSession.self) private var session
    var body:some View {CreamPage{ScrollView{VStack(spacing:14){
        HelpCard(title:"Marking attendance",symbol:"location.circle.fill",steps:["Open Attendance and tap Check In.","Keep one face inside the oval in even light.","Use restaurant Wi-Fi or allow precise GPS.","Tap Check Out before leaving."])
        HelpCard(title:"If Wi-Fi or GPS fails",symbol:"wifi.exclamationmark",steps:["Keep location permission enabled.","Try near an entrance or window for a clearer GPS reading.","Attendance can be protected offline when valid GPS and face evidence are available.","Ask a manager to use an audited override only when both methods fail."])
        HelpCard(title:"Leave and corrections",symbol:"calendar.badge.clock",steps:["Submit leave with the correct dates and reason.","Follow its status in the Leave tab.","Open Attendance History to request a correction for an older day."])
        HelpCard(title:"Salary details",symbol:"banknote.fill",steps:["Open Salary to see your current summary.","Every earning and deduction shows its date, reason, and calculation.","Use Raise Dispute when a transaction looks incorrect."])
        if session.role.canManagePeople {HelpCard(title:"Manager essentials",symbol:"person.badge.shield.checkmark",steps:["Review pending leave and correction requests.","Use the daily register to correct records with a clear reason.","Maintain schedules and branch assignments before publishing shifts.","Never share your password when confirming an override."])}
        if session.role == .owner {HelpCard(title:"Owner essentials",symbol:"building.2.fill",steps:["Complete the Restaurant Setup checklist for every branch.","Review Operations Health regularly.","Resolve missing salary, schedule, IP, and face configuration before payroll.","Use Advanced Reports for filtered operational exports."])}
    }.padding(16).padding(.bottom,24)}}.navigationTitle(L10n.text("Help & Guides")).navigationBarTitleDisplayMode(.inline).toolbar{StandardToolbar()}.diagnosticScreen("Help & Guides")}
}

private struct HelpCard:View {let title,symbol:String;let steps:[String];var body:some View{VStack(alignment:.leading,spacing:12){SectionTitle(title:title,symbol:symbol);ForEach(Array(steps.enumerated()),id:\.offset){index,step in HStack(alignment:.top,spacing:10){Text("\(index+1)").font(.caption.weight(.bold)).foregroundStyle(CBTheme.navy950).frame(width:24,height:24).background(CBTheme.orange,in:Circle());Text(L10n.text(step)).font(.subheadline).foregroundStyle(CBTheme.text).fixedSize(horizontal:false,vertical:true)}}}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.07))}}

private enum AdvancedReportExport {
    nonisolated static func csvRows(_ rows:[WorkforceReportRow])->[String] {func csv(_ value:String)->String{"\"\(value.replacingOccurrences(of:"\"",with:"\"\""))\""};return ["Report,Branch,Employee,Code,Date,Status,Method,Override,Late Minutes,Overtime Minutes,Rejection,Amount PKR,Details"]+rows.map{[$0.reportType.sentenceCased,$0.branchName ?? "",$0.employeeName,$0.employeeCode,$0.recordDate,$0.status,$0.markMethod ?? "",$0.usedOverride==true ? "Yes":"No",String($0.lateMinutes ?? 0),String($0.overtimeMinutes ?? 0),$0.rejectionCode ?? "",$0.amountMinor.map{String(format:"%.2f",Double($0)/100)} ?? "",$0.details ?? ""].map(csv).joined(separator:",")}}
    static func make(rows:[WorkforceReportRow],kind:String,pdf:Bool) async->URL {await Task.detached(priority:.userInitiated){let csv=csvRows(rows);let url=FileManager.default.temporaryDirectory.appendingPathComponent("CB-Employee-Hub-\(kind)-Advanced-Report").appendingPathExtension(pdf ? "pdf":"csv");if !pdf{try? csv.joined(separator:"\n").data(using:.utf8)?.write(to:url,options:.atomic);return url};let renderer=UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:792,height:612));try? renderer.writePDF(to:url){context in var y:CGFloat=36;func page(){context.beginPage();y=36;("CB Employee Hub — \(kind.capitalized) Report" as NSString).draw(at:CGPoint(x:30,y:y),withAttributes:[.font:UIFont.boldSystemFont(ofSize:18)]);y+=32};page();for line in csv.dropFirst(){if y>570{page()};(line.replacingOccurrences(of:"\"",with:"").replacingOccurrences(of:",",with:" • ") as NSString).draw(in:CGRect(x:30,y:y,width:732,height:30),withAttributes:[.font:UIFont.systemFont(ofSize:8)]);y+=24}};return url}.value}
}

private func historyDate(_ value:String)->String {guard let date=ISODate.date(from:value)else{return value};return L10n.date(date,dateStyle:.medium)}
private func historyDateTime(_ value:String?)->Date? {guard let value else{return nil};let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.date(from:value) ?? ISO8601DateFormatter().date(from:value)}
private func historyTime(_ value:String)->String {guard let date=historyDateTime(value)else{return value};return L10n.date(date,dateStyle:.none,timeStyle:.short)}
private func combined(day:Date,time:Date)->Date {let calendar=Calendar(identifier:.gregorian);let values=calendar.dateComponents([.hour,.minute,.second],from:time);return calendar.date(bySettingHour:values.hour ?? 0,minute:values.minute ?? 0,second:values.second ?? 0,of:day) ?? day}
