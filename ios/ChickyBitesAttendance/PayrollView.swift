import SwiftUI
import UIKit

struct PayrollView: View {
    @Environment(AppSession.self) private var session
    @State private var showingRun = false
    @State private var salaryEmployee: Employee?
    @State private var paymentItem: PayrollItem?

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing: 16) {
                    if session.role.canManagePayroll || session.role.canApprovePayroll { adminContent }
                    else { employeeContent }
                }
                .padding(16).padding(.bottom, 24)
            }
        }
        .navigationTitle(L10n.text("Salary"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .sheet(isPresented: $showingRun) { NewPayrollSheet() }
        .sheet(item: $salaryEmployee) { SalarySheet(employee: $0) }
        .sheet(item: $paymentItem) { PaymentSheet(item: $0) }
        .refreshable { await session.refreshPayrollFeature() }
        .task(id:session.selectedBranchId){await session.refreshPayrollFeature()}
        .overlay { if session.isWorking || (session.payrollIsLoading && session.payrollItems.isEmpty) { LoadingOverlay() } }
    }

    @ViewBuilder private var adminContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: "Payroll workspace", subtitle: "PKR salary calculations based on each employee’s joining date and work schedule.", symbol: "banknote.fill")
            HStack {
                Label("\(session.payrollRuns.count) payroll runs", systemImage: "doc.text.fill").font(.subheadline.weight(.semibold)).foregroundStyle(CBTheme.muted)
                Spacer()
                if !session.payrollRuns.isEmpty {
                    ShareLink(item:BankBatchExport.make(session:session)) { Image(systemName:"building.columns") }.buttonStyle(.bordered).accessibilityLabel("Export bank payment file")
                }
                if session.role.canManagePayroll { Button("New Run", systemImage: "plus") { showingRun = true }.cbPrimaryButton() }
            }
        }
        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

        if session.role.canManagePayroll { compensationDirectory }

        NavigationLink { SalaryAdministrationView() } label: {
            HStack { Label("Dynamic Salary Ledger",systemImage:"list.bullet.rectangle.fill");Spacer();Image(systemName:"chevron.right") }
                .padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))
        }.buttonStyle(.plain)

        if session.payrollRuns.isEmpty {
            EmptyState(symbol: "doc.text", title: "No payroll runs", message: "Create a payroll run when employee compensation is configured.")
        } else {
            ForEach(session.payrollRuns) { PayrollRunCard(run: $0, paymentItem: $paymentItem) }
            if session.payrollRunsHaveMore {
                Button { Task { await session.loadOlderPayrollRuns() } } label: {
                    Label(session.olderPayrollIsLoading ? "Loading…" : "Load Older Payroll",systemImage:"clock.arrow.circlepath")
                        .frame(maxWidth:.infinity)
                }
                .buttonStyle(.bordered)
                .disabled(session.olderPayrollIsLoading)
            }
        }
    }

    private var compensationDirectory: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Employee compensation", subtitle: "Open an employee to configure salary, pay dates, and work week.", symbol: "person.text.rectangle.fill")
            ForEach(session.employees.filter { $0.employmentStatus == "active" }) { employee in
                Button { salaryEmployee = employee } label: {
                    HStack(spacing: 12) {
                        InitialsAvatar(name: employee.fullName)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(employee.fullName).font(.subheadline.weight(.semibold)).foregroundStyle(CBTheme.text)
                            Text("\(employee.employeeCode) • \(employee.position ?? "Team member")").font(.caption).foregroundStyle(CBTheme.muted)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(currentSalary(employee.id)).font(.subheadline.weight(.bold)).foregroundStyle(CBTheme.text)
                            Text("Monthly").font(.caption2).foregroundStyle(CBTheme.muted)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(CBTheme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if employee.id != session.employees.filter({ $0.employmentStatus == "active" }).last?.id { Divider().overlay(CBTheme.divider) }
            }
        }
        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))
    }

    @ViewBuilder private var employeeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "My payslips", subtitle: "Approved and paid salary records visible only to you.", symbol: "doc.text.fill")
            Label("All amounts are shown in PKR", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(CBTheme.muted)
        }
        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

        let own = session.ownEmployee
        let items = session.payrollItems.filter { $0.employeeId == own?.id }
        if let summary=session.salarySummary {
            NavigationLink { SalaryLedgerView() } label: { SalarySummaryCard(summary:summary) }.buttonStyle(.plain)
        }
        if items.isEmpty {
            EmptyState(symbol: "doc.text", title: "No payslips yet", message: "Approved payroll records will appear here.")
        } else {
            ForEach(items) { item in PayslipCard(item: item) }
        }
    }

    private func currentSalary(_ employeeId: String) -> String {
        guard let value = session.compensations.first(where: { $0.employeeId == employeeId }) else { return "Configure" }
        return MoneyFormatter.pkr(minor: value.baseSalaryMinor)
    }
}

private enum BankBatchExport {
    @MainActor static func make(session:AppSession)->URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("CB-Payroll-Bank-Batch.csv")
        guard let run=session.payrollRuns.first else { try? "Employee Code,Employee,Bank,Account Title,IBAN,Amount PKR\n".write(to:url,atomically:true,encoding:.utf8);return url }
        func csv(_ value:String)->String { "\"\(value.replacingOccurrences(of:"\"",with:"\"\""))\"" }
        var rows=["Employee Code,Employee,Bank,Account Title,IBAN,Amount PKR"]
        for item in session.payrollItems.filter({$0.payrollRunId==run.id}) {
            let employee=session.employees.first{$0.id==item.employeeId}
            let profile=session.financialProfiles.first{$0.employeeId==item.employeeId}
            rows.append([employee?.employeeCode ?? "",employee?.fullName ?? "",profile?.bankName ?? "",profile?.accountTitle ?? "",profile?.iban ?? "",String(format:"%.2f",Double(item.netMinor)/100)].map(csv).joined(separator:","))
        }
        try? rows.joined(separator:"\n").write(to:url,atomically:true,encoding:.utf8)
        return url
    }
}

private struct PayrollRunCard: View {
    @Environment(AppSession.self) private var session
    let run: PayrollRun
    @Binding var paymentItem: PayrollItem?
    private var items: [PayrollItem] { session.payrollItems.filter { $0.payrollRunId == run.id } }
    private var total: Int64 { items.reduce(0) { $0 + $1.netMinor } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.title).font(.headline).foregroundStyle(CBTheme.text)
                    Text("\(run.periodStart) – \(run.periodEnd)").font(.caption).foregroundStyle(CBTheme.muted)
                }
                Spacer(minLength: 8); StatusBadge(status: run.status)
            }
            Divider().overlay(CBTheme.divider)
            HStack {
                InfoRow(symbol: "person.2.fill", title: "Employees", value: "\(items.count)")
                InfoRow(symbol: "banknote.fill", title: "Net payroll", value: MoneyFormatter.pkr(minor: total), color: CBTheme.success)
            }
            if run.status == "approved" || run.status == "locked" {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        HStack {
                            Text(session.employees.first { $0.id == item.employeeId }?.fullName ?? "Employee")
                                .font(.subheadline).foregroundStyle(CBTheme.text)
                            Spacer(); Text(item.formattedNet).font(.subheadline.weight(.bold))
                            if item.status != "paid" && session.role.canManagePayroll {
                                Button("Pay") { paymentItem = item }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            HStack {
                if session.role.canManagePayroll && run.status == "draft" { Button("Submit for Approval") { Task { await session.transitionPayroll(run, to: "submitted") } }.cbPrimaryButton() }
                if session.role.canApprovePayroll && run.status == "submitted" { Button("Approve Payroll") { Task { await session.transitionPayroll(run, to: "approved") } }.cbPrimaryButton() }
                if session.role.canApprovePayroll && run.status == "approved" { Button("Lock Run") { Task { await session.transitionPayroll(run, to: "locked") } }.buttonStyle(.bordered) }
            }
        }
        .padding(18).cbGlass(cornerRadius: 23, tint: CBTheme.surface.opacity(0.07))
    }
}

private struct PayslipCard: View {
    @Environment(AppSession.self) private var session
    let item: PayrollItem
    @State private var sharedDocument:URL?
    private var secureDocument:PayslipDocument?{session.payslipDocuments.first{$0.payrollItemId==item.id}}
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("Payslip", systemImage: "doc.text.fill").font(.headline); Spacer(); StatusBadge(status: item.status) }
            Text(item.formattedNet).font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(CBTheme.text)
            Divider().overlay(CBTheme.divider)
            HStack {
                InfoRow(symbol: "plus.circle.fill", title: "Gross", value: MoneyFormatter.pkr(minor: item.grossMinor), color: CBTheme.success)
                InfoRow(symbol: "minus.circle.fill", title: "Deductions", value: MoneyFormatter.pkr(minor: item.deductionsMinor), color: CBTheme.danger)
            }
            ForEach(session.payrollItemComponents.filter{$0.payrollItemId==item.id}) { component in
                InfoRow(symbol:component.componentType=="earning" ? "plus":"minus",title:component.label,value:MoneyFormatter.pkr(minor:component.amountMinor),color:component.componentType=="earning" ? CBTheme.success:CBTheme.danger)
            }
            Button(secureDocument == nil ? "Share Preview":"Download Secure Payslip",systemImage:"square.and.arrow.up") {
                Task {
                    if let document=secureDocument { sharedDocument=await session.downloadPayslip(document) }
                    else { sharedDocument=PayslipPDF.make(item:item,employee:session.employees.first{$0.id==item.employeeId},components:session.payrollItemComponents.filter{$0.payrollItemId==item.id}) }
                }
            }.buttonStyle(.bordered)
            if secureDocument != nil { Label("Immutable payroll copy • access recorded",systemImage:"lock.shield.fill").font(.caption).foregroundStyle(CBTheme.success) }
        }
        .padding(18).cbGlass(cornerRadius: 23, tint: CBTheme.surface.opacity(0.07))
        .sheet(isPresented:Binding(get:{sharedDocument != nil},set:{if !$0{sharedDocument=nil}})){if let sharedDocument{DocumentShareSheet(url:sharedDocument)}}
    }
}

private struct SalarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let employee: Employee
    @State private var salary = ""
    @State private var effectiveFrom = Date()
    @State private var payDay = 1
    @State private var cutoffDay = 25
    @State private var workWeek = "mon_sat"
    @State private var loaded = false
    @State private var componentName = ""
    @State private var componentType = "earning"
    @State private var componentAmount = ""
    @State private var adjustmentLabel = ""
    @State private var adjustmentType = "earning"
    @State private var adjustmentAmount = ""
    @State private var adjustmentReason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(employee.fullName) {
                    TextField("Monthly salary (PKR)", text: $salary).keyboardType(.decimalPad)
                    DatePicker("Effective from", selection: $effectiveFrom, displayedComponents: .date)
                }
                Section("Employee-specific payroll dates") {
                    Stepper("Pay day: \(payDay)", value: $payDay, in: 1...31)
                    Stepper("Cutoff day: \(cutoffDay)", value: $cutoffDay, in: 1...31)
                    Text("For shorter months, payroll uses the final available day.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Scheduled work week") {
                    Picker("Working days", selection: $workWeek) {
                        Text("Monday–Friday").tag("mon_fri"); Text("Monday–Saturday").tag("mon_sat"); Text("Every day").tag("every_day")
                    }
                }
                Section("Recurring component") {
                    TextField("Name",text:$componentName)
                    Picker("Type",selection:$componentType){Text("Earning").tag("earning");Text("Deduction").tag("deduction")}.pickerStyle(.segmented)
                    TextField("Amount (PKR)",text:$componentAmount).keyboardType(.decimalPad)
                    Button("Add Component"){Task{if let value=Double(componentAmount),await session.addSalaryComponent(employeeId:employee.id,name:componentName,type:componentType,amount:value,effectiveFrom:effectiveFrom){componentName="";componentAmount=""}}}.disabled(componentName.isEmpty || Double(componentAmount)==nil)
                }
                Section("One-time adjustment") {
                    TextField("Label",text:$adjustmentLabel)
                    Picker("Type",selection:$adjustmentType){Text("Earning").tag("earning");Text("Deduction").tag("deduction")}.pickerStyle(.segmented)
                    TextField("Amount (PKR)",text:$adjustmentAmount).keyboardType(.decimalPad)
                    TextField("Reason",text:$adjustmentReason)
                    Button("Add Adjustment"){Task{if let value=Double(adjustmentAmount),await session.addSalaryTransaction(employeeId:employee.id,rule:nil,type:adjustmentType,category:"custom",label:adjustmentLabel,description:adjustmentReason,amount:value,date:.now){adjustmentLabel="";adjustmentAmount="";adjustmentReason=""}}}.disabled(adjustmentLabel.isEmpty || adjustmentReason.count<5 || Double(adjustmentAmount)==nil)
                }
                Section {
                    Button("Save Payroll Setup") {
                        Task { if let amount = Double(salary), await session.configurePayroll(employee: employee, rupees: amount, effectiveFrom: effectiveFrom, payDay: payDay, cutoffDay: cutoffDay, workWeek: workWeek) { dismiss() } }
                    }.disabled(Double(salary) == nil)
                }
            }
            .navigationTitle(L10n.text("Compensation")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                guard !loaded else { return }; loaded = true
                if let current = session.compensations.first(where: { $0.employeeId == employee.id }) { salary = String(format: "%.2f", Double(current.baseSalaryMinor) / 100); effectiveFrom = ISODate.date(from: current.effectiveFrom) ?? .now }
                if let profile = session.payrollProfiles.first(where: { $0.employeeId == employee.id }) { payDay = profile.payDay; cutoffDay = profile.cutoffDay }
            }
        }
    }
}

private enum PayslipPDF {
    static func make(item:PayrollItem,employee:Employee?,components:[PayrollItemComponent])->URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("Payslip-\(employee?.employeeCode ?? item.id).pdf")
        let renderer=UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792))
        let data=renderer.pdfData{context in
            context.beginPage()
            let title:[NSAttributedString.Key:Any]=[.font:UIFont.boldSystemFont(ofSize:24),.foregroundColor:UIColor(red:0.03,green:0.12,blue:0.35,alpha:1)]
            let body:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:13),.foregroundColor:UIColor.darkGray]
            NSString(string:"CB Employee Hub — Payslip").draw(at:CGPoint(x:48,y:48),withAttributes:title)
            var lines=["Employee: \(employee?.fullName ?? "Employee")","Employee code: \(employee?.employeeCode ?? "—")","Gross: \(MoneyFormatter.pkr(minor:item.grossMinor))","Deductions: \(MoneyFormatter.pkr(minor:item.deductionsMinor))","Net salary: \(item.formattedNet)",""]
            lines += components.map{"\($0.label): \($0.componentType.capitalized) \(MoneyFormatter.pkr(minor:$0.amountMinor))"}
            NSString(string:lines.joined(separator:"\n")).draw(in:CGRect(x:48,y:100,width:516,height:600),withAttributes:body)
        }
        try? data.write(to:url,options:.atomic)
        return url
    }
}

private struct NewPayrollSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var title = "Monthly Payroll"
    @State private var start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var end = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section("Pay period") { TextField("Run title", text: $title); DatePicker("Start", selection: $start, displayedComponents: .date); DatePicker("End", selection: $end, in: start..., displayedComponents: .date) }
                Section { Button("Create and Calculate") { Task { await session.createPayroll(title: title, start: start, end: end); if session.errorMessage == nil { dismiss() } } }.disabled(title.isEmpty) }
            }
            .navigationTitle(L10n.text("New Payroll")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct PaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let item: PayrollItem
    @State private var amount = ""
    @State private var method = "bank_transfer"
    @State private var reference = ""
    @State private var paidOn = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    Text("Net salary: \(item.formattedNet)").fontWeight(.semibold)
                    TextField("Amount in PKR", text: $amount).keyboardType(.decimalPad)
                    Picker("Method", selection: $method) { Text("Bank transfer").tag("bank_transfer"); Text("Cash").tag("cash"); Text("Cheque").tag("cheque"); Text("Other").tag("other") }
                    TextField("Reference", text: $reference)
                    DatePicker("Paid on", selection: $paidOn, displayedComponents: .date)
                }
                Section { Button("Record Payment") { Task { if let value = Double(amount) { await session.recordPayment(item: item, amount: value, method: method, reference: reference, date: paidOn); if session.errorMessage == nil { dismiss() } } } }.disabled(Double(amount) == nil) }
            }
            .navigationTitle(L10n.text("Mark Salary Paid")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
