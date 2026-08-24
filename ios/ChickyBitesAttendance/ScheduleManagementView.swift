import SwiftUI

struct ScheduleManagementView:View {
    @Environment(AppSession.self) private var session
    @State private var editing:ScheduleTemplate?
    @State private var assigning:ScheduleTemplate?

    var body:some View {
        CreamPage {
            ScrollView {
                VStack(spacing:14) {
                    VStack(alignment:.leading,spacing:10) {
                        SectionTitle(title:"Work schedules",subtitle:"Reusable weekly hours, breaks, grace time, overnight shifts, and split shifts.",symbol:"calendar.badge.clock")
                        Button("New Schedule",systemImage:"plus") { editing=newTemplate }.cbPrimaryButton()
                    }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.surface.opacity(0.08))
                    if session.scheduleTemplates.isEmpty {
                        EmptyState(symbol:"calendar.badge.plus",title:"No schedules",message:"Create a schedule and assign it to staff.")
                    } else {
                        ForEach(session.scheduleTemplates) { template in
                            VStack(alignment:.leading,spacing:12) {
                                HStack { Text(template.name).font(.headline);Spacer();StatusBadge(status:template.isActive ? "Active":"Inactive") }
                                Text("\(short(template.checkInTime)) – \(short(template.checkOutTime)) • \(template.breakMinutes) min break • \(template.graceMinutes) min grace")
                                    .font(.subheadline).foregroundStyle(CBTheme.muted)
                                HStack {
                                    Button("Edit",systemImage:"pencil"){editing=template}.buttonStyle(.bordered)
                                    Button("Assign",systemImage:"person.badge.clock"){assigning=template}.buttonStyle(.bordered)
                                }
                            }.padding(18).cbGlass(cornerRadius:22,tint:CBTheme.surface.opacity(0.07))
                        }
                    }
                }.padding(16).padding(.bottom,24)
            }
        }
        .navigationTitle("Schedules").navigationBarTitleDisplayMode(.inline).toolbar{StandardToolbar()}
        .sheet(item:$editing){ScheduleTemplateEditor(template:$0)}
        .sheet(item:$assigning){ScheduleAssignmentSheet(template:$0)}
        .task(id:session.selectedBranchId){await session.refreshWorkforceFeature()}
        .refreshable{await session.refreshWorkforceFeature()}
        .overlay{if session.isWorking{LoadingOverlay()}}
    }

    private var newTemplate:ScheduleTemplate {
        let rules=Dictionary(uniqueKeysWithValues:["monday","tuesday","wednesday","thursday","friday","saturday","sunday"].map{($0,ScheduleDayRule(working:$0 != "sunday"))})
        return ScheduleTemplate(id:"",organizationId:session.organizationId ?? "",branchId:session.selectedBranch?.id,name:"Standard Shift",weeklyRules:rules,graceMinutes:10,expectedMinutesPerDay:480,isActive:true,checkInTime:"09:00:00",checkOutTime:"18:00:00",breakMinutes:60,overtimeAfterMinutes:480,isOvernight:false,isSplitShift:false,notes:nil)
    }
    private func short(_ value:String)->String{String(value.prefix(5))}
}

private struct ScheduleTemplateEditor:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var template:ScheduleTemplate
    private let days:[(String,String)]=[("monday","Monday"),("tuesday","Tuesday"),("wednesday","Wednesday"),("thursday","Thursday"),("friday","Friday"),("saturday","Saturday"),("sunday","Sunday")]

    init(template:ScheduleTemplate){_template=State(initialValue:template)}
    var body:some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    TextField("Name",text:$template.name)
                    Stepper("Grace: \(template.graceMinutes) minutes",value:$template.graceMinutes,in:0...120,step:5)
                    Stepper("Standard break: \(template.breakMinutes) minutes",value:$template.breakMinutes,in:0...180,step:5)
                    Stepper("Overtime after: \(template.overtimeAfterMinutes) minutes",value:$template.overtimeAfterMinutes,in:60...960,step:15)
                    Toggle("Overnight schedule",isOn:$template.isOvernight)
                    Toggle("Split shift",isOn:$template.isSplitShift)
                    Toggle("Active",isOn:$template.isActive)
                    TextField("Notes",text:Binding(get:{template.notes ?? ""},set:{template.notes=$0}),axis:.vertical)
                }
                ForEach(days,id:\.0){key,title in
                    Section(title) {
                        Toggle("Working day",isOn:ruleBinding(key,\.working))
                        if template.weeklyRules[key]?.working == true {
                            TextField("Start (HH:mm)",text:timeBinding(key,\.start))
                            TextField("End (HH:mm)",text:timeBinding(key,\.end))
                            Stepper("Break: \(template.weeklyRules[key]?.breakMinutes ?? 0) minutes",value:ruleBinding(key,\.breakMinutes),in:0...180,step:5)
                            Toggle("Ends next day",isOn:ruleBinding(key,\.overnight))
                            if template.isSplitShift {
                                TextField("Second start (HH:mm)",text:optionalTimeBinding(key,\.secondStart))
                                TextField("Second end (HH:mm)",text:optionalTimeBinding(key,\.secondEnd))
                            }
                        }
                    }
                }
            }
            .navigationTitle(template.id.isEmpty ? "New Schedule":"Edit Schedule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Save"){Task{normalize();if await session.saveScheduleTemplate(template){dismiss()}}}.disabled(template.name.trimmingCharacters(in:.whitespaces).count<2)}
            }
        }
    }

    private func ruleBinding<T>(_ key:String,_ path:WritableKeyPath<ScheduleDayRule,T>)->Binding<T>{
        Binding(get:{template.weeklyRules[key]![keyPath:path]},set:{value in var rule=template.weeklyRules[key]!;rule[keyPath:path]=value;template.weeklyRules[key]=rule})
    }
    private func timeBinding(_ key:String,_ path:WritableKeyPath<ScheduleDayRule,String>)->Binding<String>{
        Binding(get:{String(template.weeklyRules[key]![keyPath:path].prefix(5))},set:{value in var rule=template.weeklyRules[key]!;rule[keyPath:path]=value;template.weeklyRules[key]=rule})
    }
    private func optionalTimeBinding(_ key:String,_ path:WritableKeyPath<ScheduleDayRule,String?>)->Binding<String>{
        Binding(get:{String((template.weeklyRules[key]![keyPath:path] ?? "").prefix(5))},set:{value in var rule=template.weeklyRules[key]!;rule[keyPath:path]=value.isEmpty ? nil:value;template.weeklyRules[key]=rule})
    }
    private func normalize(){for key in days.map(\.0){guard var rule=template.weeklyRules[key] else{continue};if rule.start.count==5{rule.start += ":00"};if rule.end.count==5{rule.end += ":00"};if let second=rule.secondStart,second.count==5{rule.secondStart=second+":00"};if let second=rule.secondEnd,second.count==5{rule.secondEnd=second+":00"};template.weeklyRules[key]=rule};template.checkInTime=template.weeklyRules["monday"]?.start ?? template.checkInTime;template.checkOutTime=template.weeklyRules["monday"]?.end ?? template.checkOutTime}
}

private struct ScheduleAssignmentSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let template:ScheduleTemplate
    @State private var employeeId=""
    @State private var effectiveFrom=Date()
    var body:some View {NavigationStack{Form{Section(template.name){Picker("Staff member",selection:$employeeId){Text("Select staff").tag("");ForEach(session.employees.filter{$0.employmentStatus=="active"}){Text("\($0.employeeCode) — \($0.fullName)").tag($0.id)}};DatePicker("Effective from",selection:$effectiveFrom,displayedComponents:.date)};Section{Button("Assign Schedule"){Task{if await session.assignSchedule(employeeId:employeeId,templateId:template.id,effectiveFrom:effectiveFrom){dismiss()}}}.disabled(employeeId.isEmpty)}}.navigationTitle("Assign Schedule").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}}}
}
