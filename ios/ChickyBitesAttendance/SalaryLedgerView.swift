import SwiftUI

struct SalarySummaryCard: View {
    let summary: SalarySummary
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Label("Salary this month",systemImage:"banknote.fill").font(.headline);Spacer();Text(nextPayText).font(.caption).foregroundStyle(CBTheme.muted) }
            Text(MoneyFormatter.pkr(minor:summary.estimatedNetMinor)).font(.system(.title,design:.rounded,weight:.bold))
            Text("Estimated after pending activity").font(.caption).foregroundStyle(CBTheme.muted)
            Divider()
            HStack {
                salaryValue("Base",summary.baseSalaryMinor,CBTheme.text)
                Spacer();salaryValue("Earnings",summary.approvedEarningsMinor,CBTheme.success)
                Spacer();salaryValue("Deductions",summary.approvedDeductionsMinor,CBTheme.danger)
            }
            if summary.pendingDeductionsMinor>0 { InfoRow(symbol:"clock",title:"Pending deductions",value:MoneyFormatter.pkr(minor:summary.pendingDeductionsMinor),color:CBTheme.warning) }
            HStack { Text("Paid \(MoneyFormatter.pkr(minor:summary.paidMinor))");Spacer();Text("Remaining \(MoneyFormatter.pkr(minor:summary.remainingMinor))") }.font(.caption.weight(.semibold)).foregroundStyle(CBTheme.muted)
        }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
    }
    private func salaryValue(_ title:String,_ amount:Int64,_ color:Color)->some View { VStack(alignment:.leading,spacing:3){Text(L10n.text(title)).font(.caption).foregroundStyle(CBTheme.muted);Text(MoneyFormatter.pkr(minor:amount)).font(.caption.weight(.bold)).foregroundStyle(color)} }
    private var nextPayText:String { guard let date=ISODate.date(from:summary.nextPayDate) else{return summary.nextPayDate};return "\(L10n.text("Next pay")) \(L10n.date(date,dateStyle:.medium))" }
}

struct SalaryLedgerView: View {
    @Environment(AppSession.self) private var session
    let employee: Employee?
    @State private var showingFilters=false
    @State private var selected:SalaryLedgerTransaction?
    init(employee:Employee?=nil){self.employee=employee}
    private var target:Employee? { employee ?? session.ownEmployee }
    var body:some View {
        CreamPage {
            ScrollView {
                LazyVStack(spacing:12) {
                    if let summary=session.salarySummary { SalarySummaryCard(summary:summary) }
                    HStack {
                        VStack(alignment:.leading,spacing:3){Text(target.map{L10n.format("%@ salary history",$0.fullName)} ?? L10n.text("Salary history")).font(.headline);Text("Newest transactions first").font(.caption).foregroundStyle(CBTheme.muted)}
                        Spacer();Button("Filter",systemImage:"line.3.horizontal.decrease.circle"){showingFilters=true}.buttonStyle(.bordered)
                    }.padding(16).cbGlass(cornerRadius:20,tint:CBTheme.surface.opacity(0.06))
                    if session.salaryLedger.isEmpty && !session.salaryLedgerIsLoading { EmptyState(symbol:"list.bullet.rectangle",title:"No salary transactions",message:"Transactions matching these filters will appear here.") }
                    ForEach(groupedMonths){group in
                        VStack(alignment:.leading,spacing:10){
                            Text(group.title).font(.headline).foregroundStyle(CBTheme.info)
                            ForEach(group.items){item in Button{selected=item}label:{SalaryTransactionRow(item:item)}.buttonStyle(.plain)}
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    if session.salaryLedgerHasMore { Button("Load Older Transactions",systemImage:"clock.arrow.circlepath"){Task{await session.loadSalaryLedger(employeeId:target?.id,reset:false)}}.buttonStyle(.bordered).disabled(session.salaryLedgerIsLoading) }
                    if session.salaryLedgerIsLoading { ProgressView().padding() }
                }.padding(16).padding(.bottom,24)
            }.refreshable{await session.loadSalaryLedger(employeeId:target?.id)}
        }
        .navigationTitle(L10n.text("Salary Details")).navigationBarTitleDisplayMode(.inline)
        .toolbar{StandardToolbar()}
        .task{applyPreset();await session.loadSalaryLedger(employeeId:target?.id)}
        .sheet(isPresented:$showingFilters){SalaryFilterSheet(employeeId:target?.id)}
        .sheet(item:$selected){SalaryTransactionDetailView(item:$0)}
    }
    private struct MonthGroup:Identifiable { let title:String;let items:[SalaryLedgerTransaction];var id:String{title} }
    private var groupedMonths:[MonthGroup] {
        let groups=Dictionary(grouping:session.salaryLedger){L10n.monthYear(SalaryInstant.date($0.occurredAt) ?? .distantPast)}
        return groups.map{MonthGroup(title:$0.key,items:$0.value)}.sorted{($0.items.first?.occurredAt ?? "") > ($1.items.first?.occurredAt ?? "")}
    }
    private func applyPreset(){ if session.salaryLedgerFilter.preset.isEmpty { session.salaryLedgerFilter.preset="this_month" } }
}

private struct SalaryTransactionRow:View {
    let item:SalaryLedgerTransaction
    private var isNegative:Bool{item.transactionType=="deduction"}
    var body:some View {
        HStack(spacing:12){
            Image(systemName:isNegative ? "minus.circle.fill":"plus.circle.fill").foregroundStyle(isNegative ? CBTheme.danger:CBTheme.success).font(.title3)
            VStack(alignment:.leading,spacing:4){Text(L10n.text(item.label)).font(.subheadline.weight(.semibold)).foregroundStyle(CBTheme.text);Text(L10n.text(item.description)).font(.caption).foregroundStyle(CBTheme.muted).lineLimit(2);Text(displayDate(item.occurredAt)).font(.caption2).foregroundStyle(CBTheme.muted)}
            Spacer(minLength:6)
            VStack(alignment:.trailing,spacing:5){Text("\(isNegative ? "−":"+")\(MoneyFormatter.pkr(minor:item.amountMinor))").font(.subheadline.weight(.bold)).foregroundStyle(isNegative ? CBTheme.danger:CBTheme.success);StatusBadge(status:item.status)}
        }.padding(15).cbGlass(cornerRadius:19,tint:CBTheme.surface.opacity(0.05))
    }
    private func displayDate(_ value:String)->String{guard let date=SalaryInstant.date(value)else{return value};return L10n.date(date,dateStyle:.medium,timeStyle:.short)}
}

private enum SalaryInstant {
    static func date(_ value:String)->Date? {
        let fractional=ISO8601DateFormatter();fractional.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return fractional.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    }
}

private struct SalaryFilterSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let employeeId:String?
    var body:some View { @Bindable var session=session;NavigationStack{Form{
        Section("Date and time"){Picker("Period",selection:$session.salaryLedgerFilter.preset){Text("Today").tag("today");Text("Last 7 days").tag("7_days");Text("This month").tag("this_month");Text("Previous month").tag("previous_month");Text("Last 3 months").tag("3_months");Text("All time").tag("all");Text("Custom").tag("custom")}.onChange(of:session.salaryLedgerFilter.preset){_,_ in updateDates()};if session.salaryLedgerFilter.preset=="custom"{DatePicker("From",selection:Binding(get:{session.salaryLedgerFilter.from ?? .now},set:{session.salaryLedgerFilter.from=$0}),displayedComponents:[.date,.hourAndMinute]);DatePicker("To",selection:Binding(get:{session.salaryLedgerFilter.to ?? .now},set:{session.salaryLedgerFilter.to=$0}),displayedComponents:[.date,.hourAndMinute])}}
        Section("Transaction"){Picker("Type",selection:$session.salaryLedgerFilter.transactionType){Text("All").tag("all");Text("Earnings").tag("earning");Text("Deductions").tag("deduction");Text("Payments").tag("payment")};Picker("Category",selection:$session.salaryLedgerFilter.category){Text("All").tag("all");ForEach(["late_checkin","early_checkout","absence","unpaid_leave","overtime","extra_food","loan","tax","eobi","reimbursement","bonus","penalty","allowance","custom"],id:\.self){Text(L10n.text($0.sentenceCased)).tag($0)}};Picker("Status",selection:$session.salaryLedgerFilter.status){Text("All").tag("all");ForEach(["pending","approved","disputed","applied","paid","reversed","rejected"],id:\.self){Text(L10n.text($0.sentenceCased)).tag($0)}};TextField("Search reason or reference",text:$session.salaryLedgerFilter.search)}
    }.navigationTitle(L10n.text("Salary Filters")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Clear"){session.salaryLedgerFilter=SalaryLedgerFilter();updateDates()}};ToolbarItem(placement:.confirmationAction){Button("Apply"){Task{await session.loadSalaryLedger(employeeId:employeeId);dismiss()}}}}.onAppear{updateDates()}} }
    private func updateDates() {
        let calendar = Calendar.current
        switch session.salaryLedgerFilter.preset {
        case "today":
            session.salaryLedgerFilter.from = calendar.startOfDay(for: .now)
            session.salaryLedgerFilter.to = .now
        case "7_days":
            session.salaryLedgerFilter.from = calendar.date(byAdding: .day, value: -7, to: .now)
            session.salaryLedgerFilter.to = .now
        case "this_month":
            session.salaryLedgerFilter.from = calendar.date(from: calendar.dateComponents([.year, .month], from: .now))
            session.salaryLedgerFilter.to = .now
        case "previous_month":
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now))!
            session.salaryLedgerFilter.from = calendar.date(byAdding: .month, value: -1, to: thisMonth)
            session.salaryLedgerFilter.to = calendar.date(byAdding: .second, value: -1, to: thisMonth)
        case "3_months":
            session.salaryLedgerFilter.from = calendar.date(byAdding: .month, value: -3, to: .now)
            session.salaryLedgerFilter.to = .now
        case "all":
            session.salaryLedgerFilter.from = nil
            session.salaryLedgerFilter.to = nil
        default:
            break
        }
    }
}

private struct SalaryTransactionDetailView:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let item:SalaryLedgerTransaction
    @State private var events:[SalaryTransactionEvent]=[]
    @State private var reason=""
    var body:some View{NavigationStack{Form{
        Section("Transaction"){InfoRow(symbol:"banknote",title:item.label,value:MoneyFormatter.pkr(minor:item.amountMinor),color:item.transactionType=="deduction" ? CBTheme.danger:CBTheme.success);InfoRow(symbol:"calendar",title:"Date",value:item.workDate ?? item.occurredAt);InfoRow(symbol:"tag",title:"Category",value:item.category.sentenceCased);InfoRow(symbol:"checkmark.circle",title:"Status",value:item.status.sentenceCased);Text(item.description);if let calculation=item.calculationText{Text(calculation).font(.caption).foregroundStyle(CBTheme.muted)}}
        if !events.isEmpty{Section("History"){ForEach(events){event in VStack(alignment:.leading){Text(L10n.text(event.eventType.sentenceCased)).font(.subheadline.weight(.semibold));Text(L10n.text(event.note ?? event.createdAt)).font(.caption).foregroundStyle(CBTheme.muted)}}}}
        if session.role == .staff && ["pending","approved","applied"].contains(item.status){Section("Dispute"){TextField("Explain the issue",text:$reason,axis:.vertical);Button("Raise Dispute"){Task{if await session.disputeSalaryTransaction(item,reason:reason){dismiss()}}}.disabled(reason.trimmingCharacters(in:.whitespaces).count<5)}}
        if session.role.canApprovePayroll && ["pending","disputed"].contains(item.status){Section("Review"){TextField("Review note",text:$reason,axis:.vertical);HStack{Button("Reject",role:.destructive){Task{await session.reviewSalaryTransaction(item,status:"rejected",note:reason);dismiss()}};Spacer();Button("Approve"){Task{await session.reviewSalaryTransaction(item,status:"approved",note:reason);dismiss()}}}}}
        if session.role.canApprovePayroll && ["approved","applied","paid"].contains(item.status){Section("Correction"){TextField("Reversal reason",text:$reason,axis:.vertical);Button("Record Reversal",role:.destructive){Task{if await session.reverseSalaryTransaction(item,reason:reason){dismiss()}}}.disabled(reason.trimmingCharacters(in:.whitespaces).count<5)}}
    }.navigationTitle(L10n.text("Transaction Details")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}}}.task{events=await session.salaryEvents(for:item)}}}
}

struct SalaryAdministrationView:View {
    @Environment(AppSession.self) private var session
    @State private var employeeId=""
    @State private var manual=false
    @State private var food=false
    @State private var rule=false
    @State private var ruleToEdit:SalaryTransactionRule?
    @State private var foodItem=false
    var body:some View{CreamPage{ScrollView{VStack(spacing:14){
        VStack(alignment:.leading,spacing:12){SectionTitle(title:"Salary operations",subtitle:"Rules, daily activity, approvals and reversals.",symbol:"list.bullet.rectangle");Picker("Employee",selection:$employeeId){Text("Select employee").tag("");ForEach(session.employees){Text("\($0.employeeCode) — \($0.fullName)").tag($0.id)}};HStack{Button("Transaction",systemImage:"plus"){manual=true}.buttonStyle(.bordered).disabled(employeeId.isEmpty);Button("Food",systemImage:"fork.knife"){food=true}.buttonStyle(.bordered).disabled(employeeId.isEmpty);Button("Rule",systemImage:"slider.horizontal.3"){ruleToEdit=nil;rule=true}.buttonStyle(.bordered);Button("Menu Item",systemImage:"takeoutbag.and.cup.and.straw"){foodItem=true}.buttonStyle(.bordered)}}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.07))
        if let employee=session.employees.first(where:{$0.id==employeeId}){NavigationLink{SalaryLedgerView(employee:employee)}label:{HStack{Label("Open full salary ledger",systemImage:"list.bullet.rectangle");Spacer();Image(systemName:"chevron.right")}}.buttonStyle(.bordered)}
        if session.role.canApprovePayroll { ForEach(session.salaryLedger.filter{["pending","disputed"].contains($0.status)}){item in SalaryTransactionRow(item:item)} }
        VStack(alignment:.leading,spacing:10){SectionTitle(title:"Dynamic rules",symbol:"slider.horizontal.3");ForEach(session.salaryRules){r in Button{ruleToEdit=r;rule=true}label:{HStack{VStack(alignment:.leading){Text(r.name).font(.headline);Text("\(r.category.sentenceCased) • \(r.calculationMethod.sentenceCased)").font(.caption).foregroundStyle(CBTheme.muted)};Spacer();StatusBadge(status:r.isActive ? "active":"inactive");Image(systemName:"chevron.right").foregroundStyle(CBTheme.muted)}}.buttonStyle(.plain)}}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.06))
        if !session.salaryDisputes.isEmpty{VStack(alignment:.leading,spacing:10){SectionTitle(title:"Disputes",symbol:"exclamationmark.bubble");ForEach(session.salaryDisputes.filter{["open","under_review"].contains($0.status)}){d in VStack(alignment:.leading,spacing:8){Text(d.reason);HStack{Button("Reject dispute"){Task{await session.resolveSalaryDispute(d,status:"rejected",note:"Transaction confirmed")}}.buttonStyle(.bordered);Spacer();Button("Accept dispute"){Task{await session.resolveSalaryDispute(d,status:"accepted",note:"Transaction removed from salary")}}.cbPrimaryButton()}}}}.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.06))}
    }.padding(16)}}.navigationTitle(L10n.text("Salary Ledger")).navigationBarTitleDisplayMode(.inline).toolbar{StandardToolbar()}.onChange(of:employeeId){_,value in Task{await session.loadSalaryLedger(employeeId:value)}}.sheet(isPresented:$manual){SalaryManualTransactionSheet(employeeId:employeeId)}.sheet(isPresented:$food){SalaryFoodChargeSheet(employeeId:employeeId)}.sheet(isPresented:$rule){SalaryRuleEditorSheet(rule:ruleToEdit)}.sheet(isPresented:$foodItem){SalaryFoodItemSheet()}}
}

private struct SalaryManualTransactionSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session;let employeeId:String
    @State private var type="deduction";@State private var category="custom";@State private var label="";@State private var amount="";@State private var reason="";@State private var date=Date();@State private var ruleId=""
    var body:some View{NavigationStack{Form{Picker("Saved rule",selection:$ruleId){Text("No rule").tag("");ForEach(session.salaryRules){Text($0.name).tag($0.id)}}.onChange(of:ruleId){_,id in if let r=session.salaryRules.first(where:{$0.id==id}){type=r.transactionType;category=r.category;label=r.name}};Picker("Type",selection:$type){Text("Earning").tag("earning");Text("Deduction").tag("deduction")};Picker("Category",selection:$category){ForEach(["bonus","allowance","penalty","late_checkin","early_checkout","extra_food","custom"],id:\.self){Text($0.sentenceCased).tag($0)}};TextField("Title",text:$label);TextField("Amount PKR",text:$amount).keyboardType(.decimalPad);TextField("Clear reason",text:$reason,axis:.vertical);DatePicker("Date and time",selection:$date)}.navigationTitle(L10n.text("Salary Transaction")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){Task{if await session.addSalaryTransaction(employeeId:employeeId,rule:session.salaryRules.first{$0.id==ruleId},type:type,category:category,label:label,description:reason,amount:Double(amount) ?? 0,date:date){dismiss()}}}.disabled(label.count<2||reason.count<2||Double(amount)==nil)}}}}
}

struct SalaryFoodChargeSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session;var employeeId:String?=nil
    @State private var selectedEmployee="";@State private var itemId="";@State private var quantity=1.0;@State private var date=Date();@State private var note=""
    var body:some View{NavigationStack{Form{if employeeId==nil{Picker("Employee",selection:$selectedEmployee){Text("Select").tag("");ForEach(session.employees){Text($0.fullName).tag($0.id)}}};Picker("Food item",selection:$itemId){Text("Select").tag("");ForEach(session.salaryFoodItems){Text("\($0.name) • \(MoneyFormatter.pkr(minor:$0.unitPriceMinor))").tag($0.id)}};Stepper("Quantity: \(quantity.formatted())",value:$quantity,in:0.5...20,step:0.5);DatePicker("Date and time",selection:$date);TextField("Note",text:$note,axis:.vertical)}.navigationTitle(L10n.text("Extra Food")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Add"){Task{let target=employeeId ?? selectedEmployee;if let item=session.salaryFoodItems.first(where:{$0.id==itemId}),await session.addFoodCharge(employeeId:target,item:item,quantity:quantity,date:date,note:note){dismiss()}}}.disabled((employeeId ?? selectedEmployee).isEmpty||itemId.isEmpty)}}}}
}

private struct SalaryFoodItemSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session;@State private var name="";@State private var unit="item";@State private var price="";@State private var date=Date()
    var body:some View{NavigationStack{Form{TextField("Food item",text:$name);TextField("Unit",text:$unit);TextField("Price PKR",text:$price).keyboardType(.decimalPad);DatePicker("Effective from",selection:$date,displayedComponents:.date)}.navigationTitle(L10n.text("Food Menu Item")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){Task{if await session.saveFoodItem(name:name,unit:unit,price:Double(price) ?? 0,effectiveFrom:date){dismiss()}}}.disabled(name.count<2||Double(price)==nil)}}}}
}

private struct SalaryRuleEditorSheet:View {
    @Environment(\.dismiss) private var dismiss;@Environment(AppSession.self) private var session;@State private var draft:SalaryRuleDraft
    init(rule:SalaryTransactionRule?=nil){_draft=State(initialValue:SalaryRuleDraft(rule:rule))}
    var body:some View{NavigationStack{Form{Section("Rule"){TextField("Code",text:$draft.code);TextField("Name",text:$draft.name);TextField("Description",text:$draft.description,axis:.vertical);Picker("Type",selection:$draft.transactionType){Text("Earning").tag("earning");Text("Deduction").tag("deduction")};Picker("Category",selection:$draft.category){ForEach(["late_checkin","early_checkout","absence","unpaid_leave","overtime","extra_food","bonus","penalty","allowance","custom"],id:\.self){Text($0.sentenceCased).tag($0)}};Toggle("Rule enabled",isOn:$draft.isActive)};Section("Calculation"){Picker("Method",selection:$draft.calculationMethod){Text("Fixed").tag("fixed");Text("Per minute").tag("per_minute");Text("Per hour").tag("per_hour");Text("Per occurrence").tag("per_occurrence");Text("Percentage of base").tag("percentage_base");Text("Quantity × rate").tag("quantity_rate")};if draft.calculationMethod=="percentage_base"{TextField("Percentage",text:$draft.percentage).keyboardType(.decimalPad)}else{TextField("Rate PKR",text:$draft.rate).keyboardType(.decimalPad)};Stepper("Grace: \(draft.graceMinutes) minutes",value:$draft.graceMinutes,in:0...1440);TextField("Daily cap PKR (optional)",text:$draft.dailyCap).keyboardType(.decimalPad);TextField("Monthly cap PKR (optional)",text:$draft.monthlyCap).keyboardType(.decimalPad)};Section("Application"){Picker("Applies to",selection:$draft.scopeType){Text("Everyone").tag("all");Text("Current branch").tag("branch");Text("Employee ID").tag("employee");Text("Department").tag("department");Text("Position").tag("position")};if !["all","branch"].contains(draft.scopeType){TextField("Scope value",text:$draft.scopeValue)};Toggle("Approval required",isOn:$draft.approvalRequired);Toggle("Employee can dispute",isOn:$draft.allowDispute);if ["late_checkin","early_checkout","absence","overtime"].contains(draft.category){Toggle("Generate from attendance",isOn:$draft.autoGenerate)};DatePicker("Effective from",selection:$draft.effectiveFrom,displayedComponents:.date)}}.navigationTitle(L10n.text(draft.id==nil ? "New Salary Rule":"Edit Salary Rule")).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Save"){Task{if await session.saveSalaryRule(draft){dismiss()}}}.disabled(draft.code.count<2||draft.name.count<2||(draft.calculationMethod=="percentage_base" ? Double(draft.percentage)==nil:Double(draft.rate)==nil))}}}}
}

private extension SalaryRuleDraft {
    init(rule:SalaryTransactionRule?){
        self.init();guard let rule else{return}
        id=rule.id;code=rule.code;name=rule.name;description=rule.description ?? "";transactionType=rule.transactionType;category=rule.category;calculationMethod=rule.calculationMethod
        rate=rule.rateMinor.map{String(format:"%.2f",Double($0)/100)} ?? "";percentage=rule.percentage.map{String($0)} ?? "";graceMinutes=rule.graceMinutes
        dailyCap=rule.dailyCapMinor.map{String(format:"%.2f",Double($0)/100)} ?? "";monthlyCap=rule.monthlyCapMinor.map{String(format:"%.2f",Double($0)/100)} ?? ""
        scopeType=rule.scopeType;scopeValue=rule.scopeValue ?? "";approvalRequired=rule.approvalRequired;allowDispute=rule.allowDispute;autoGenerate=rule.autoGenerate;effectiveFrom=ISODate.date(from:rule.effectiveFrom) ?? .now;isActive=rule.isActive
    }
}
