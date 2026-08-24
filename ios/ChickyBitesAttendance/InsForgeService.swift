import Foundation
import InsForge
import UIKit

enum BackendError: LocalizedError {
    case noMembership, noBranch, noEmployeeProfile, invalidInput(String)
    var errorDescription: String? {
        switch self {
        case .noMembership: "Your account has not been assigned to the organization yet."
        case .noBranch: "No active branch is assigned to this account."
        case .noEmployeeProfile: "Your login is not linked to an employee profile."
        case .invalidInput(let message): message
        }
    }
}

struct InsForgeService {
    static let baseURL = URL(string: "https://dbve4gzs.us-east.insforge.app")!
    static let anonKey = "anon_b627f9a671a01a40f45aa08054fa511ab312c0b27c61a8e776e0eaef9c1a94c3"
    static let client = InsForgeClient(baseURL: baseURL, anonKey: anonKey)

    func signIn(email: String, password: String) async throws -> AdminUser {
        let response = try await Self.client.auth.signIn(email: email, password: password)
        let user = response.user
        return try await resolveUser(id: user.id, email: user.email, name: user.profile?.name, bootstrapIfNeeded: true)
    }

    private func resolveUser(id: String, email: String, name: String?, bootstrapIfNeeded: Bool) async throws -> AdminUser {
        var memberships: [OrganizationMembership] = try await Self.client.database.from("organization_memberships").select().eq("user_id", value: id).eq("is_active", value: true).execute()
        if memberships.isEmpty && bootstrapIfNeeded {
            struct Claim: Decodable { let organizationId: String; let branchId: String; enum CodingKeys: String, CodingKey { case organizationId="organization_id", branchId="branch_id" } }
            let _: Claim? = try? await Self.client.database.rpc("bootstrap_organization", args: ["org_name":"Chicky Bites","branch_name":"Main Branch","branch_code":"MAIN"]).executeSingle()
            memberships = try await Self.client.database.from("organization_memberships").select().eq("user_id", value: id).eq("is_active", value: true).execute()
        }
        return AdminUser(id: id, fullName: name ?? email, email: email, role: memberships.first?.role ?? "employee")
    }

    func signUp(email: String, password: String, name: String) async throws -> Bool {
        let response = try await Self.client.auth.signUp(email: email, password: password, name: name)
        return response.needsEmailVerification
    }

    func verify(email: String, code: String) async throws -> AdminUser {
        let response = try await Self.client.auth.verifyEmail(email: email, otp: code)
        let user = response.user
        return try await resolveUser(id: user.id, email: user.email, name: user.profile?.name, bootstrapIfNeeded: true)
    }
    func resendVerification(email: String) async throws { try await Self.client.auth.sendEmailVerification(email: email) }
    func sendPasswordReset(email: String) async throws { try await Self.client.auth.sendPasswordReset(email: email) }
    func exchangePasswordReset(email: String, code: String) async throws -> String {
        let response = try await Self.client.auth.exchangeResetPasswordToken(email: email, code: code)
        return response.token
    }
    func resetPassword(token: String, newPassword: String) async throws {
        try await Self.client.auth.resetPassword(otp: token, newPassword: newPassword)
    }
    func signOut() async throws { try await Self.client.auth.signOut() }
    func deactivateMobileDevice(deviceId:String) async throws { let _:Bool=try await Self.client.database.rpc("deactivate_my_mobile_device",args:["p_device_id":deviceId]).executeSingle() }
    func currentUser() async throws -> AdminUser? {
        guard try await Self.client.auth.getSession() != nil else { return nil }
        let user = try await Self.client.auth.getCurrentUser()
        let memberships: [OrganizationMembership] = try await Self.client.database.from("organization_memberships").select().eq("user_id", value: user.id).eq("is_active", value: true).execute()
        guard let membership = memberships.first else { return nil }
        return AdminUser(id:user.id,fullName:user.profile?.name ?? user.email,email:user.email,role:membership.role)
    }

    func branches() async throws -> [Branch] { try await Self.client.database.from("branches").select().eq("is_active",value:true).order("name",ascending:true).execute() }
    func employees(branchId:String,offset:Int=0,limit:Int=100) async throws -> [Employee] {
        try await Self.client.database.rpc("mobile_branch_employees",args:["p_branch_id":branchId,"p_limit":min(max(limit,1),100),"p_offset":max(offset,0)]).execute()
    }
    func attendance(branchId:String,date: String) async throws -> [AttendanceDay] { try await Self.client.database.from("attendance_daily").select().eq("branch_id",value:branchId).eq("work_date",value:date).limit(2000).execute() }
    func leaveTypes() async throws -> [LeaveType] { try await Self.client.database.from("leave_types").select().eq("is_active",value:true).order("name",ascending:true).execute() }
    func leaves(branchId:String,offset:Int=0) async throws -> [LeaveRecord] { try await Self.client.database.from("leave_requests").select().eq("branch_id",value:branchId).order("created_at",ascending:false).range(from:offset,to:offset+49).execute() }
    func payrollRuns(branchId:String,offset:Int=0) async throws -> [PayrollRun] { try await Self.client.database.from("payroll_runs").select().eq("branch_id",value:branchId).order("period_end",ascending:false).range(from:offset,to:offset+24).execute() }
    func payrollItems() async throws -> [PayrollItem] { try await Self.client.database.from("payroll_items").select().order("created_at",ascending:false).limit(500).execute() }
    func salaryPayments() async throws -> [SalaryPayment] { try await Self.client.database.from("salary_payments").select().order("paid_on",ascending:false).limit(500).execute() }
    func compensations() async throws -> [CompensationVersion] { try await Self.client.database.from("compensation_versions").select().order("effective_from",ascending:false).limit(500).execute() }
    func payrollProfiles() async throws -> [EmployeePayrollProfile] { try await Self.client.database.from("employee_payroll_profiles").select().order("effective_from",ascending:false).limit(500).execute() }
    func employeeBranchAssignments(branchId:String,offset:Int=0,limit:Int=100) async throws -> [EmployeeBranchAssignment] {
        try await Self.client.database.rpc("mobile_branch_assignments",args:["p_branch_id":branchId,"p_limit":min(max(limit,1),100),"p_offset":max(offset,0)]).execute()
    }
    func branchIPRules(branchId:String) async throws -> [BranchIPRule] { try await Self.client.database.from("branch_ip_rules").select().eq("branch_id",value:branchId).order("created_at",ascending:false).limit(100).execute() }
    func leaveBalanceEntries() async throws -> [LeaveBalanceEntry] { try await Self.client.database.from("leave_balance_ledger").select().order("entry_date",ascending:false).limit(1000).execute() }
    func salaryComponentDefinitions() async throws -> [SalaryComponentDefinition] { try await Self.client.database.from("salary_component_definitions").select().eq("is_active",value:true).order("name",ascending:true).execute() }
    func employeeSalaryComponents() async throws -> [EmployeeSalaryComponent] { try await Self.client.database.from("employee_salary_components").select().order("effective_from",ascending:false).limit(1000).execute() }
    func payrollAdjustments() async throws -> [PayrollAdjustment] { try await Self.client.database.from("payroll_adjustments").select().order("created_at",ascending:false).limit(1000).execute() }
    func payrollItemComponents() async throws -> [PayrollItemComponent] { try await Self.client.database.from("payroll_item_components").select().order("created_at",ascending:true).limit(2000).execute() }
    func notifications(offset:Int=0) async throws -> [AppNotification] { try await Self.client.database.from("app_notifications").select().order("created_at",ascending:false).range(from:offset,to:offset+49).execute() }
    func auditEvents(branchId:String,offset:Int=0) async throws -> [AuditEvent] { try await Self.client.database.from("audit_events").select("id,action,entity_type,reason,created_at").eq("branch_id",value:branchId).order("created_at",ascending:false).range(from:offset,to:offset+49).execute() }
    func workforceReport(branchId:String,from:String,to:String,kind:String) async throws -> [WorkforceReportRow] {
        try await workforceReportPage(branchId:branchId,filter:WorkforceReportFilter(kind:kind,from:ISODate.date(from:from) ?? .now,to:ISODate.date(from:to) ?? .now),offset:0,limit:500)
    }
    func workforceReportPage(branchId:String,filter:WorkforceReportFilter,offset:Int=0,limit:Int=100) async throws -> [WorkforceReportRow] {
        var args:[String:Any] = [
            "p_branch_id":branchId,"p_from":ISODate.string(from:filter.from),"p_to":ISODate.string(from:filter.to),
            "p_kind":filter.kind,"p_limit":min(max(limit,1),500),"p_offset":max(offset,0)
        ]
        if !filter.employeeId.isEmpty { args["p_employee_id"] = filter.employeeId }
        if filter.status != "all" { args["p_status"] = filter.status }
        if filter.markMethod != "all" { args["p_mark_method"] = filter.markMethod }
        if filter.overrideMode == "yes" { args["p_used_override"] = true }
        if filter.overrideMode == "no" { args["p_used_override"] = false }
        let search=filter.search.trimmingCharacters(in:.whitespacesAndNewlines)
        if !search.isEmpty { args["p_search"] = search }
        return try await Self.client.database.rpc("mobile_workforce_report_v2",args:args).execute()
    }
    func attendanceHistory(employeeId:String?,branchId:String?,filter:AttendanceHistoryFilter,offset:Int=0,limit:Int=50) async throws -> [AttendanceHistoryEntry] {
        try await Self.client.database.rpc("mobile_attendance_history",args:[
            "p_employee_id":employeeId ?? NSNull(),"p_branch_id":branchId ?? NSNull(),
            "p_from":ISODate.string(from:filter.from),"p_to":ISODate.string(from:filter.to),
            "p_limit":min(max(limit,1),100),"p_offset":max(offset,0)
        ]).execute()
    }
    func operationsHealth(branchId:String) async throws -> OperationsHealth {
        try await Self.client.database.rpc("mobile_operations_health",args:["p_branch_id":branchId]).executeSingle()
    }
    func diagnosticFeed(branchId:String,severity:String?,offset:Int=0,limit:Int=50) async throws -> [MobileDiagnosticEvent] {
        try await Self.client.database.rpc("mobile_diagnostic_feed",args:[
            "p_branch_id":branchId,"p_severity":severity ?? NSNull(),
            "p_offset":max(offset,0),"p_limit":min(max(limit,1),100)
        ]).execute()
    }
    func failedPushNotifications(branchId:String,offset:Int=0,limit:Int=50) async throws -> [FailedPushNotification] {
        try await Self.client.database.rpc("mobile_failed_push_notifications",args:[
            "p_branch_id":branchId,"p_offset":max(offset,0),"p_limit":min(max(limit,1),100)
        ]).execute()
    }
    func retryFailedPushNotification(branchId:String,notificationId:String) async throws -> Bool {
        try await Self.client.database.rpc("retry_failed_push_notification",args:[
            "p_branch_id":branchId,"p_notification_id":notificationId
        ]).executeSingle()
    }
    func retryAllFailedPushNotifications(branchId:String) async throws -> Int {
        try await Self.client.database.rpc("retry_all_failed_push_notifications",args:["p_branch_id":branchId]).executeSingle()
    }
    func recordDiagnostic(_ diagnostic:PendingDiagnostic,organizationId:String,branchId:String?) async throws {
        let _:String=try await Self.client.database.rpc("record_mobile_diagnostic",args:[
            "p_organization_id":organizationId,"p_branch_id":branchId ?? NSNull(),"p_device_id":diagnostic.deviceId,
            "p_severity":diagnostic.severity,"p_category":diagnostic.category,"p_screen":diagnostic.screen ?? NSNull(),
            "p_message":diagnostic.message,"p_error_code":diagnostic.errorCode ?? NSNull(),"p_build_version":diagnostic.buildVersion,
            "p_os_version":diagnostic.osVersion,"p_model_identifier":diagnostic.modelIdentifier,
            "p_payload_text":diagnostic.payloadText ?? NSNull(),"p_occurred_at":diagnostic.occurredAt
        ]).executeSingle()
    }

    func shifts(branchId:String,start:String,end:String,offset:Int=0,limit:Int=100) async throws -> [ShiftRosterEntry] {
        try await Self.client.database.from("shift_roster_entries").select().eq("branch_id",value:branchId).gte("work_date",value:start).lte("work_date",value:end).order("work_date",ascending:true).range(from:offset,to:offset+min(max(limit,1),100)-1).execute()
    }
    func shiftSwaps(branchId:String,offset:Int=0) async throws -> [ShiftSwapRequest] { try await Self.client.database.from("shift_swap_requests").select().eq("branch_id",value:branchId).order("created_at",ascending:false).range(from:offset,to:offset+49).execute() }
    func correctionRequests(branchId:String,offset:Int=0) async throws -> [AttendanceCorrectionRequest] { try await Self.client.database.from("attendance_correction_requests").select().eq("branch_id",value:branchId).order("created_at",ascending:false).range(from:offset,to:offset+49).execute() }
    func holidays(branchId:String,organizationId:String) async throws -> [PublicHoliday] { try await Self.client.database.from("public_holidays").select().eq("organization_id",value:organizationId).order("holiday_date",ascending:true).limit(100).execute() }
    func leaveBlackouts(organizationId:String) async throws -> [LeaveBlackoutPeriod] { try await Self.client.database.from("leave_blackout_periods").select().eq("organization_id",value:organizationId).order("starts_on",ascending:true).limit(100).execute() }
    func saveHoliday(organizationId:String,branchId:String?,name:String,date:Date,isPaid:Bool) async throws {
        struct Payload:Codable { let organization_id:String;let branch_id:String?;let name,holiday_date:String;let is_paid:Bool }
        let _:Payload=try await Self.client.database.from("public_holidays").insert(Payload(organization_id:organizationId,branch_id:branchId,name:name,holiday_date:ISODate.string(from:date),is_paid:isPaid))
    }
    func saveLeaveBlackout(organizationId:String,branchId:String?,start:Date,end:Date,reason:String) async throws {
        struct Payload:Codable { let organization_id:String;let branch_id:String?;let starts_on,ends_on,reason:String }
        let _:Payload=try await Self.client.database.from("leave_blackout_periods").insert(Payload(organization_id:organizationId,branch_id:branchId,starts_on:ISODate.string(from:start),ends_on:ISODate.string(from:end),reason:reason))
    }
    func employeeDocuments(offset:Int=0) async throws -> [EmployeeDocument] { try await Self.client.database.from("employee_documents").select().order("created_at",ascending:false).range(from:offset,to:offset+49).execute() }
    func financialProfiles() async throws -> [EmployeeFinancialProfile] { try await Self.client.database.from("employee_financial_profiles").select().limit(100).execute() }
    func payrollLoans(offset:Int=0) async throws -> [PayrollLoan] { try await Self.client.database.from("payroll_loans").select().order("created_at",ascending:false).range(from:offset,to:offset+49).execute() }
    func reimbursements(offset:Int=0) async throws -> [PayrollReimbursement] { try await Self.client.database.from("payroll_reimbursements").select().order("expense_date",ascending:false).range(from:offset,to:offset+49).execute() }
    func statutoryRules(organizationId:String) async throws ->[PayrollStatutoryRule]{try await Self.client.database.from("payroll_statutory_rules").select().eq("organization_id",value:organizationId).order("effective_from",ascending:false).execute()}
    func saveStatutoryRule(organizationId:String,code:String,name:String,type:String,value:Double,effectiveFrom:Date) async throws {
        struct Payload:Codable{let organization_id,code,name,rule_type,effective_from:String;let configuration:StatutoryRuleConfiguration;let is_active:Bool}
        let configuration=type=="fixed_deduction" ? StatutoryRuleConfiguration(amountMinor:Int64((value*100).rounded()),ratePercent:nil):StatutoryRuleConfiguration(amountMinor:nil,ratePercent:value)
        let _:Payload=try await Self.client.database.from("payroll_statutory_rules").insert(Payload(organization_id:organizationId,code:code.trimmingCharacters(in:.whitespacesAndNewlines).uppercased(),name:name.trimmingCharacters(in:.whitespacesAndNewlines),rule_type:type,effective_from:ISODate.string(from:effectiveFrom),configuration:configuration,is_active:true))
    }
    func dashboardSummary(branchId:String,date:String) async throws -> MobileDashboardSummary {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await Self.client.database.rpc("mobile_dashboard_summary",args:["p_branch_id":branchId,"p_date":date]).executeSingle()
            } catch {
                lastError=error
                guard UserFacingError.isTransientServiceFailure(error), attempt < 2 else { throw error }
                try await Task.sleep(for:.milliseconds(250 * (attempt + 1)))
            }
        }
        throw lastError ?? BackendError.invalidInput("Dashboard information is temporarily unavailable.")
    }
    func multiBranchSummary(date:String) async throws -> [MultiBranchSummary] {
        try await Self.client.database.rpc("mobile_multi_branch_summary",args:["p_date":date]).execute()
    }
    func scheduleTemplates(branchId:String) async throws -> [ScheduleTemplate] {
        try await Self.client.database.from("schedule_templates").select().eq("branch_id",value:branchId).order("name",ascending:true).limit(100).execute()
    }
    func kioskDevices(branchId:String) async throws -> [BranchKioskDevice] {
        try await Self.client.database.from("branch_kiosk_devices").select().eq("branch_id",value:branchId).order("registered_at",ascending:false).limit(50).execute()
    }
    func payslipDocuments(offset:Int=0) async throws -> [PayslipDocument] {
        try await Self.client.database.from("payslip_documents").select("id,organization_id,payroll_item_id,employee_id,storage_path,content_type,generated_at,version,file_size_bytes").order("generated_at",ascending:false).range(from:offset,to:offset+49).execute()
    }
    func lifecycleTasks() async throws -> [EmployeeLifecycleTask] { try await Self.client.database.from("employee_lifecycle_tasks").select().order("due_on",ascending:true).limit(500).execute() }
    func employeeAssets() async throws -> [EmployeeAsset] { try await Self.client.database.from("employee_assets").select().order("issued_on",ascending:false).limit(500).execute() }
    func availability(branchId:String) async throws -> [EmployeeAvailability] { try await Self.client.database.from("employee_availability").select().eq("branch_id",value:branchId).order("weekday",ascending:true).limit(700).execute() }
    func notificationPreferences(organizationId:String,userId:String) async throws -> NotificationPreferences {
        let rows:[NotificationPreferences]=try await Self.client.database.from("notification_preferences").select().eq("user_id",value:userId).limit(1).execute()
        return rows.first ?? NotificationPreferences(userId:userId,organizationId:organizationId)
    }

    func salarySummary(employeeId:String?=nil,asOf:Date=Date()) async throws -> SalarySummary {
        var args:[String:Any] = ["p_as_of":ISODate.string(from:asOf)]
        if let employeeId { args["p_employee_id"] = employeeId }
        return try await Self.client.database.rpc("employee_salary_summary",args:args).executeSingle()
    }

    func salaryLedgerPage(employeeId:String?=nil,filter:SalaryLedgerFilter,before:SalaryLedgerTransaction?=nil,limit:Int=20) async throws -> [SalaryLedgerTransaction] {
        var args:[String:Any] = ["p_limit":limit]
        if let employeeId { args["p_employee_id"] = employeeId }
        let iso=ISO8601DateFormatter()
        if let from=filter.from { args["p_from"] = iso.string(from:filter.preset=="custom" ? from:Calendar.current.startOfDay(for:from)) }
        if let to=filter.to {
            if filter.preset=="custom" { args["p_to"] = iso.string(from:to) }
            else if let inclusive=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:to)) { args["p_to"] = iso.string(from:inclusive.addingTimeInterval(-0.001)) }
        }
        if filter.transactionType != "all" { args["p_transaction_type"] = filter.transactionType }
        if filter.category != "all" { args["p_category"] = filter.category }
        if filter.status != "all" { args["p_status"] = filter.status }
        if !filter.search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { args["p_search"] = filter.search.trimmingCharacters(in:.whitespacesAndNewlines) }
        if let before { args["p_before_at"] = before.occurredAt; args["p_before_id"] = before.id }
        return try await Self.client.database.rpc("salary_ledger_page",args:args).execute()
    }

    func salaryRules() async throws -> [SalaryTransactionRule] { try await Self.client.database.from("salary_transaction_rules").select().order("effective_from",ascending:false).limit(500).execute() }
    func salaryFoodItems() async throws -> [SalaryFoodItem] { try await Self.client.database.from("salary_food_items").select().eq("is_active",value:true).order("name",ascending:true).limit(500).execute() }
    func salaryDisputes() async throws -> [SalaryTransactionDispute] { try await Self.client.database.from("salary_transaction_disputes").select().order("created_at",ascending:false).limit(500).execute() }
    func salaryEvents(transactionId:String) async throws -> [SalaryTransactionEvent] { try await Self.client.database.from("salary_transaction_events").select().eq("transaction_id",value:transactionId).order("created_at",ascending:true).limit(100).execute() }

    func saveSalaryRule(organizationId:String,branchId:String?,draft:SalaryRuleDraft) async throws {
        struct Payload:Codable {
            let id,organization_id,code,name,transaction_type,category,calculation_method,scope_type,effective_from:String
            let branch_id,description,scope_value:String?
            let rate_minor,daily_cap_minor,monthly_cap_minor:Int64?
            let percentage:Double?
            let grace_minutes:Int
            let approval_required,allow_dispute,auto_generate,is_active:Bool
        }
        func minor(_ text:String)->Int64? { guard let value=Double(text),value>=0 else{return nil};return Int64((value*100).rounded()) }
        let needsPercentage=draft.calculationMethod=="percentage_base"
        let scopeValue:String? = draft.scopeType=="all" ? nil:(draft.scopeType=="branch" ? branchId:draft.scopeValue.trimmingCharacters(in:.whitespacesAndNewlines))
        let payload=Payload(id:draft.id ?? UUID().uuidString,organization_id:organizationId,code:draft.code.trimmingCharacters(in:.whitespacesAndNewlines).uppercased(),name:draft.name.trimmingCharacters(in:.whitespacesAndNewlines),transaction_type:draft.transactionType,category:draft.category,calculation_method:draft.calculationMethod,scope_type:draft.scopeType,effective_from:ISODate.string(from:draft.effectiveFrom),branch_id:branchId,description:draft.description.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil:draft.description.trimmingCharacters(in:.whitespacesAndNewlines),scope_value:scopeValue,rate_minor:needsPercentage ? nil:minor(draft.rate),daily_cap_minor:minor(draft.dailyCap),monthly_cap_minor:minor(draft.monthlyCap),percentage:needsPercentage ? Double(draft.percentage):nil,grace_minutes:draft.graceMinutes,approval_required:draft.approvalRequired,allow_dispute:draft.allowDispute,auto_generate:draft.autoGenerate,is_active:draft.isActive)
        if let id=draft.id { let _:[Payload]=try await Self.client.database.from("salary_transaction_rules").eq("id",value:id).update(payload) }
        else { let _:Payload=try await Self.client.database.from("salary_transaction_rules").insert(payload) }
    }

    func saveSalaryFoodItem(organizationId:String,branchId:String?,name:String,unit:String,price:Double,effectiveFrom:Date) async throws {
        struct Payload:Codable { let id,organization_id,name,unit_label,effective_from:String;let branch_id:String?;let unit_price_minor:Int64;let is_active:Bool }
        let _:Payload=try await Self.client.database.from("salary_food_items").insert(Payload(id:UUID().uuidString,organization_id:organizationId,name:name.trimmingCharacters(in:.whitespacesAndNewlines),unit_label:unit.trimmingCharacters(in:.whitespacesAndNewlines),effective_from:ISODate.string(from:effectiveFrom),branch_id:branchId,unit_price_minor:Int64((price*100).rounded()),is_active:true))
    }

    func createSalaryTransaction(employeeId:String,branchId:String?,ruleId:String?,type:String,category:String,label:String,description:String,amount:Double,date:Date) async throws -> SalaryLedgerTransaction {
        var args:[String:Any] = ["p_employee_id":employeeId,"p_transaction_type":type,"p_category":category,"p_label":label,"p_description":description,"p_amount_minor":Int64((amount*100).rounded()),"p_occurred_at":ISO8601DateFormatter().string(from:date),"p_work_date":ISODate.string(from:date),"p_source_type":"manual","p_calculation_text":description]
        if let branchId { args["p_branch_id"] = branchId }
        if let ruleId { args["p_rule_id"] = ruleId }
        return try await Self.client.database.rpc("create_salary_transaction",args:args).executeSingle()
    }

    func recordSalaryFoodCharge(employeeId:String,foodItemId:String,quantity:Double,date:Date,note:String) async throws -> SalaryLedgerTransaction { try await Self.client.database.rpc("record_salary_food_charge",args:["p_employee_id":employeeId,"p_food_item_id":foodItemId,"p_quantity":quantity,"p_occurred_at":ISO8601DateFormatter().string(from:date),"p_note":note]).executeSingle() }
    func reviewSalaryTransaction(id:String,status:String,note:String) async throws -> SalaryLedgerTransaction { try await Self.client.database.rpc("review_salary_transaction",args:["p_transaction_id":id,"p_status":status,"p_note":note]).executeSingle() }
    func disputeSalaryTransaction(id:String,reason:String) async throws -> SalaryTransactionDispute { try await Self.client.database.rpc("dispute_salary_transaction",args:["p_transaction_id":id,"p_reason":reason]).executeSingle() }
    func resolveSalaryDispute(id:String,status:String,note:String) async throws -> SalaryTransactionDispute { try await Self.client.database.rpc("resolve_salary_dispute",args:["p_dispute_id":id,"p_status":status,"p_note":note]).executeSingle() }
    func reverseSalaryTransaction(id:String,reason:String) async throws -> SalaryLedgerTransaction { try await Self.client.database.rpc("reverse_salary_transaction",args:["p_transaction_id":id,"p_reason":reason]).executeSingle() }
    func applySalaryLedger(payrollId:String) async throws ->Int { try await Self.client.database.rpc("apply_salary_ledger",args:["p_run_id":payrollId]).executeSingle() }

    func saveEmployee(_ draft: EmployeeDraft, organizationId: String, branchId: String) async throws {
        struct Payload: Codable {
            let id, organization_id, employee_code, full_name, phone, position, cnic, address, joining_date, employment_status, app_role: String
            let department,reporting_manager_id,employment_type,probation_end_date,emergency_contact_name,emergency_contact_phone:String?
        }
        func optional(_ value:String)->String?{let clean=value.trimmingCharacters(in:.whitespacesAndNewlines);return clean.isEmpty ? nil:clean}
        let body=Payload(id:draft.id ?? UUID().uuidString,organization_id:organizationId,employee_code:draft.employeeCode.trimmingCharacters(in:.whitespacesAndNewlines).uppercased(),full_name:draft.fullName.trimmingCharacters(in:.whitespacesAndNewlines),phone:draft.phone.trimmingCharacters(in:.whitespacesAndNewlines),position:draft.position.trimmingCharacters(in:.whitespacesAndNewlines),cnic:CNICFormatter.format(draft.cnic),address:draft.address.trimmingCharacters(in:.whitespacesAndNewlines),joining_date:ISODate.string(from:draft.joiningDate),employment_status:draft.status,app_role:draft.role,department:optional(draft.department),reporting_manager_id:optional(draft.reportingManagerId),employment_type:draft.employmentType,probation_end_date:draft.hasProbationEnd ? ISODate.string(from:draft.probationEndDate):nil,emergency_contact_name:optional(draft.emergencyContactName),emergency_contact_phone:optional(draft.emergencyContactPhone))
        if let id=draft.id {
            let _: [Payload] = try await Self.client.database.from("employees").eq("id",value:id).update(body)
        } else {
            let _: Payload = try await Self.client.database.from("employees").insert(body)
            struct Assignment: Codable { let employee_id,branch_id,starts_on:String; let is_primary:Bool }
            let _: Assignment = try await Self.client.database.from("employee_branch_assignments").insert(Assignment(employee_id:body.id,branch_id:branchId,starts_on:ISODate.string(from:draft.joiningDate),is_primary:true))
        }
    }

    func submitLeave(_ draft: LeaveDraft, organizationId: String, branchId: String, employeeId: String) async throws {
        let calendar=Calendar(identifier:.gregorian); let days=(calendar.dateComponents([.day],from:calendar.startOfDay(for:draft.startDate),to:calendar.startOfDay(for:draft.endDate)).day ?? 0)+1
        guard days>0 else { throw BackendError.invalidInput("End date must be on or after the start date.") }
        var documentPath:String?
        if let fileURL=draft.documentURL {
            let accessed=fileURL.startAccessingSecurityScopedResource();defer{if accessed{fileURL.stopAccessingSecurityScopedResource()}}
            let safeName=fileURL.lastPathComponent.replacingOccurrences(of:"/",with:"-")
            let path="\(organizationId)/\(employeeId)/\(UUID().uuidString)-\(safeName)"
            let data=try await BackgroundFileLoader.data(from:fileURL)
            _ = try await Self.client.storage.from("leave-documents").upload(path:path,data:data)
            documentPath=path
        }
        let requestedDays = draft.durationType == "full_day" ? Double(days) : (draft.durationType == "hourly" ? Double(draft.requestedMinutes ?? 60)/480.0 : 0.5)
        struct Payload: Codable { let organization_id,branch_id,employee_id,leave_type_id,start_date,end_date,reason,status,duration_type:String; let requested_days:Double;let requested_minutes:Int?;let document_path:String? }
        let payload=Payload(organization_id:organizationId,branch_id:branchId,employee_id:employeeId,leave_type_id:draft.leaveTypeId,start_date:ISODate.string(from:draft.startDate),end_date:ISODate.string(from:draft.endDate),reason:draft.reason,status:"pending",duration_type:draft.durationType,requested_days:requestedDays,requested_minutes:draft.requestedMinutes,document_path:documentPath)
        let _: Payload = try await Self.client.database.from("leave_requests").insert(payload)
    }

    func saveShift(organizationId:String,branchId:String,employeeId:String,date:Date,start:Date,end:Date,breakMinutes:Int,notes:String) async throws {
        struct Payload:Codable { let organization_id,branch_id,employee_id,work_date,starts_at,ends_at,status:String;let break_minutes:Int;let notes:String? }
        let time=DateFormatter();time.locale=Locale(identifier:"en_US_POSIX");time.dateFormat="HH:mm:ss"
        let payload=Payload(organization_id:organizationId,branch_id:branchId,employee_id:employeeId,work_date:ISODate.string(from:date),starts_at:time.string(from:start),ends_at:time.string(from:end),status:"scheduled",break_minutes:breakMinutes,notes:notes.isEmpty ? nil:notes)
        let _:Payload=try await Self.client.database.from("shift_roster_entries").insert(payload)
    }
    func updateShift(id:String,organizationId:String,branchId:String,employeeId:String,date:Date,start:Date,end:Date,breakMinutes:Int,notes:String) async throws {
        struct Payload:Codable { let organization_id,branch_id,employee_id,work_date,starts_at,ends_at:String;let break_minutes:Int;let notes:String? }
        let time=DateFormatter();time.locale=Locale(identifier:"en_US_POSIX");time.dateFormat="HH:mm:ss"
        let payload=Payload(organization_id:organizationId,branch_id:branchId,employee_id:employeeId,work_date:ISODate.string(from:date),starts_at:time.string(from:start),ends_at:time.string(from:end),break_minutes:breakMinutes,notes:notes.isEmpty ? nil:notes)
        let _:[Payload]=try await Self.client.database.from("shift_roster_entries").eq("id",value:id).update(payload)
    }
    func cancelShift(id:String) async throws {
        struct Payload:Codable { let status:String }
        let _:[Payload]=try await Self.client.database.from("shift_roster_entries").eq("id",value:id).update(Payload(status:"cancelled"))
    }
    func saveRecurringShifts(organizationId:String,branchId:String,employeeId:String,date:Date,start:Date,end:Date,breakMinutes:Int,notes:String,weeks:Int) async throws {
        for week in 0..<max(1,weeks) {
            guard let target=Calendar.current.date(byAdding:.day,value:week*7,to:date) else{continue}
            try await saveShift(organizationId:organizationId,branchId:branchId,employeeId:employeeId,date:target,start:start,end:end,breakMinutes:breakMinutes,notes:notes)
        }
    }
    func saveAvailability(organizationId:String,branchId:String,employeeId:String,weekday:Int,isAvailable:Bool,from:Date,until:Date,note:String) async throws {
        struct Payload:Codable { let organization_id,branch_id,employee_id:String;let weekday:Int;let available_from,available_until,note:String?;let is_available:Bool }
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="HH:mm:ss"
        let payload=Payload(organization_id:organizationId,branch_id:branchId,employee_id:employeeId,weekday:weekday,available_from:isAvailable ? formatter.string(from:from):nil,available_until:isAvailable ? formatter.string(from:until):nil,note:note.isEmpty ? nil:note,is_available:isAvailable)
        let existing:[EmployeeAvailability]=try await Self.client.database.from("employee_availability").select().eq("employee_id",value:employeeId).eq("branch_id",value:branchId).eq("weekday",value:weekday).limit(1).execute()
        if let row=existing.first { let _:[Payload]=try await Self.client.database.from("employee_availability").eq("id",value:row.id).update(payload) }
        else { let _:Payload=try await Self.client.database.from("employee_availability").insert(payload) }
    }
    func copyRoster(branchId:String,sourceStart:Date,targetStart:Date) async throws -> Int { try await Self.client.database.rpc("bulk_copy_roster",args:["p_branch_id":branchId,"p_source_start":ISODate.string(from:sourceStart),"p_target_start":ISODate.string(from:targetStart)]).executeSingle() }
    func publishRoster(branchId:String,weekStart:Date) async throws -> Int { try await Self.client.database.rpc("publish_roster",args:["p_branch_id":branchId,"p_week_start":ISODate.string(from:weekStart)]).executeSingle() }

    func requestShiftSwap(organizationId:String,entry:ShiftRosterEntry,employeeId:String,targetEmployeeId:String?,reason:String) async throws {
        struct Payload:Codable { let organization_id,branch_id,roster_entry_id,requested_by_employee_id,reason,status:String;let target_employee_id:String? }
        let _:Payload=try await Self.client.database.from("shift_swap_requests").insert(Payload(organization_id:organizationId,branch_id:entry.branchId,roster_entry_id:entry.id,requested_by_employee_id:employeeId,reason:reason,status:"pending",target_employee_id:targetEmployeeId))
    }
    func reviewShiftSwap(id:String,status:String,note:String) async throws { let _:ShiftSwapRequest=try await Self.client.database.rpc("review_shift_swap",args:["p_request_id":id,"p_status":status,"p_note":note]).executeSingle() }

    func submitAttendanceCorrection(organizationId:String,branchId:String,employeeId:String,date:Date,checkIn:Date?,checkOut:Date?,reason:String) async throws {
        struct Payload:Codable { let organization_id,branch_id,employee_id,work_date,reason,status:String;let requested_check_in_at,requested_check_out_at:String? }
        let iso=ISO8601DateFormatter()
        let _:Payload=try await Self.client.database.from("attendance_correction_requests").insert(Payload(organization_id:organizationId,branch_id:branchId,employee_id:employeeId,work_date:ISODate.string(from:date),reason:reason,status:"pending",requested_check_in_at:checkIn.map { iso.string(from: $0) },requested_check_out_at:checkOut.map { iso.string(from: $0) }))
    }
    func reviewAttendanceCorrection(id:String,status:String,note:String) async throws { let _:AttendanceCorrectionRequest=try await Self.client.database.rpc("review_attendance_correction",args:["p_request_id":id,"p_status":status,"p_note":note]).executeSingle() }

    func uploadEmployeeDocument(organizationId:String,employeeId:String,type:String,title:String,fileURL:URL,expiresOn:Date?) async throws {
        let accessed=fileURL.startAccessingSecurityScopedResource();defer{if accessed{fileURL.stopAccessingSecurityScopedResource()}}
        let path="\(organizationId)/\(employeeId)/\(UUID().uuidString)-\(fileURL.lastPathComponent.replacingOccurrences(of:"/",with:"-"))"
        let data=try await BackgroundFileLoader.data(from:fileURL)
        _=try await Self.client.storage.from("employee-documents").upload(path:path,data:data)
        struct Payload:Codable { let organization_id,employee_id,document_type,title,storage_key:String;let expires_on:String?;let is_confidential:Bool }
        let _:Payload=try await Self.client.database.from("employee_documents").insert(Payload(organization_id:organizationId,employee_id:employeeId,document_type:type,title:title,storage_key:path,expires_on:expiresOn.map { ISODate.string(from: $0) },is_confidential:true))
    }

    func downloadEmployeeDocument(_ document:EmployeeDocument) async throws ->URL {
        let data=try await Self.client.storage.from("employee-documents").download(path:document.storageKey)
        let suffix=URL(fileURLWithPath:document.storageKey).pathExtension
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(document.title.replacingOccurrences(of:"/",with:"-")).appendingPathExtension(suffix.isEmpty ? "pdf":suffix)
        try data.write(to:file,options:[.atomic,.completeFileProtection])
        return file
    }

    func saveFinancialProfile(organizationId:String,employeeId:String,bank:String,accountTitle:String,iban:String,taxNumber:String,eobiNumber:String,tax:Double,eobi:Double) async throws {
        struct Payload:Codable { let employee_id,organization_id,bank_name,account_title,iban,tax_number,eobi_number:String;let tax_monthly_minor,eobi_monthly_minor:Int64 }
        let payload=Payload(employee_id:employeeId,organization_id:organizationId,bank_name:bank,account_title:accountTitle,iban:iban,tax_number:taxNumber,eobi_number:eobiNumber,tax_monthly_minor:Int64((tax*100).rounded()),eobi_monthly_minor:Int64((eobi*100).rounded()))
        let existing:[EmployeeFinancialProfile]=try await Self.client.database.from("employee_financial_profiles").select().eq("employee_id",value:employeeId).limit(1).execute()
        if existing.isEmpty { let _:Payload=try await Self.client.database.from("employee_financial_profiles").insert(payload) }
        else { let _:[Payload]=try await Self.client.database.from("employee_financial_profiles").eq("employee_id",value:employeeId).update(payload) }
    }

    func createPayrollLoan(organizationId:String,employeeId:String,label:String,principal:Double,installment:Double,start:Date) async throws {
        struct Payload:Codable { let organization_id,employee_id,label,starts_on,status:String;let principal_minor,installment_minor,outstanding_minor:Int64 }
        let principalMinor=Int64((principal*100).rounded());guard principalMinor>0,installment>0 else{throw BackendError.invalidInput("Enter valid loan and installment amounts.")}
        let _:Payload=try await Self.client.database.from("payroll_loans").insert(Payload(organization_id:organizationId,employee_id:employeeId,label:label,starts_on:ISODate.string(from:start),status:"active",principal_minor:principalMinor,installment_minor:Int64((installment*100).rounded()),outstanding_minor:principalMinor))
    }

    func submitReimbursement(organizationId:String,employeeId:String,label:String,amount:Double,date:Date,reason:String) async throws {
        struct Payload:Codable { let organization_id,employee_id,label,expense_date,reason,status:String;let amount_minor:Int64 }
        let _:Payload=try await Self.client.database.from("payroll_reimbursements").insert(Payload(organization_id:organizationId,employee_id:employeeId,label:label,expense_date:ISODate.string(from:date),reason:reason,status:"pending",amount_minor:Int64((amount*100).rounded())))
    }
    func reviewReimbursement(id:String,status:String) async throws { struct Payload:Codable{let status:String};let _:[Payload]=try await Self.client.database.from("payroll_reimbursements").eq("id",value:id).update(Payload(status:status)) }

    func registerPushToken(_ token:String,deviceId:String,environment:String) async throws { let _:Bool=try await Self.client.database.rpc("register_mobile_push_token",args:["p_device_id":deviceId,"p_token":token,"p_environment":environment]).executeSingle() }
    func issueBiometricChallenge(branchId:String,deviceId:String) async throws -> BiometricChallenge { try await Self.client.database.rpc("issue_biometric_challenge",args:["p_branch_id":branchId,"p_device_id":deviceId]).executeSingle() }

    func reviewLeave(id:String,status:String,note:String?) async throws {
        let _: LeaveRecord = try await Self.client.database.rpc("review_leave_request",args:["p_request_id":id,"p_status":status,"p_note":note ?? ""]).executeSingle()
    }

    func updateLeaveType(_ type:LeaveType,isPaid:Bool,annualDays:Double,requiresDocument:Bool,requiresReason:Bool,accrualMethod:String,carryForwardDays:Double,attachmentAfterDays:Double?) async throws {
        guard annualDays >= 0 else { throw BackendError.invalidInput("Annual leave days cannot be negative.") }
        struct Payload:Codable { let is_paid:Bool; let default_annual_days:Double; let requires_document,requires_reason:Bool;let accrual_method:String;let carry_forward_days:Double;let attachment_after_days:Double? }
        let _: [Payload] = try await Self.client.database.from("leave_types").eq("id",value:type.id).update(Payload(is_paid:isPaid,default_annual_days:annualDays,requires_document:requiresDocument,requires_reason:requiresReason,accrual_method:accrualMethod,carry_forward_days:carryForwardDays,attachment_after_days:attachmentAfterDays))
    }

    func markAttendance(_ request: AttendanceFunctionRequest) async throws -> AttendanceFunctionResponse {
        try await Self.client.functions.invoke("attendance-action",body:request)
    }
    func syncOfflineAttendance(_ request:OfflineAttendanceRequest) async throws -> AttendanceFunctionResponse { try await Self.client.functions.invoke("attendance-action",body:request) }
    func networkDiagnostic(branchId:String) async throws -> NetworkDiagnostic {
        struct Request:Codable { let mode,branchId:String }
        return try await Self.client.functions.invoke("attendance-action",body:Request(mode:"diagnose",branchId:branchId))
    }

    func faceStatus(employeeId:String) async throws -> FaceTemplateStatus {
        struct Request:Codable { let mode,employeeId:String }
        return try await Self.client.functions.invoke("biometric-action",body:Request(mode:"status",employeeId:employeeId))
    }

    func enrollFace(employeeId:String,descriptors:[[Float]],liveness:BiometricLivenessEvidence) async throws -> FaceTemplateStatus {
        struct Request:Codable { let mode,employeeId,modelVersion:String; let descriptor:[Float]; let descriptors:[[Float]]; let sampleCount:Int; let captureVersion:String;let livenessEvidence:BiometricLivenessEvidence }
        let summary=FaceEmbeddingMath.robustSummary(descriptors)
        return try await Self.client.functions.invoke("biometric-action",body:Request(mode:"enroll",employeeId:employeeId,modelVersion:"adaface_ir18_v1",descriptor:summary.descriptor,descriptors:summary.samples,sampleCount:summary.samples.count,captureVersion:"challenge_temporal_v5",livenessEvidence:liveness))
    }

    func verifyFace(branchId:String,deviceId:String,descriptors:[[Float]],challenge:BiometricChallenge,liveness:BiometricLivenessEvidence,kioskEmployeeId:String?=nil) async throws -> FaceVerificationResult {
        struct Request:Codable { let mode,branchId,deviceId,modelVersion,challengeId,challengeAction:String; let employeeId:String?;let descriptor:[Float]; let descriptors:[[Float]]; let livenessPassed:Bool; let livenessEvidence:BiometricLivenessEvidence;let captureVersion,signedPayload,signature:String }
        let summary=FaceEmbeddingMath.robustSummary(descriptors)
        let assertion=try await AttendanceEvidenceVault.shared.signBiometricChallenge(challengeId:challenge.challengeId,branchId:branchId,deviceId:deviceId,action:challenge.action,descriptor:summary.descriptor,liveness:liveness)
        return try await Self.client.functions.invoke("biometric-action",body:Request(mode:kioskEmployeeId == nil ? "verify":"verify_kiosk",branchId:branchId,deviceId:deviceId,modelVersion:"adaface_ir18_v1",challengeId:challenge.challengeId,challengeAction:challenge.action,employeeId:kioskEmployeeId,descriptor:summary.descriptor,descriptors:summary.samples,livenessPassed:true,livenessEvidence:liveness,captureVersion:"challenge_temporal_v5",signedPayload:assertion.signedPayload,signature:assertion.signature))
    }

    func revokeFace(employeeId:String,reason:String) async throws -> FaceTemplateStatus {
        struct Request:Codable { let mode,employeeId,reason:String }
        return try await Self.client.functions.invoke("biometric-action",body:Request(mode:"revoke",employeeId:employeeId,reason:reason))
    }

    func setCompensation(employeeId:String,organizationId:String,monthlyRupees:Double,effectiveFrom:Date) async throws {
        guard monthlyRupees>=0 else { throw BackendError.invalidInput("Salary cannot be negative.") }
        struct Payload:Codable { let organization_id,employee_id:String; let base_salary_minor:Int64; let currency,effective_from:String }
        let _: Payload = try await Self.client.database.from("compensation_versions").insert(Payload(organization_id:organizationId,employee_id:employeeId,base_salary_minor:Int64((monthlyRupees*100).rounded()),currency:"PKR",effective_from:ISODate.string(from:effectiveFrom)))
    }


    func setPayrollProfile(employeeId:String,payDay:Int,cutoffDay:Int,effectiveFrom:Date) async throws {
        guard (1...31).contains(payDay),(1...31).contains(cutoffDay) else { throw BackendError.invalidInput("Pay day and cutoff day must be between 1 and 31.") }
        let date=ISODate.string(from:effectiveFrom)
        let existing:[EmployeePayrollProfile] = try await Self.client.database.from("employee_payroll_profiles").select().eq("employee_id",value:employeeId).eq("effective_from",value:date).limit(1).execute()
        struct Payload:Codable { let employee_id,pay_frequency:String; let pay_day,cutoff_day:Int; let effective_from:String }
        let payload=Payload(employee_id:employeeId,pay_frequency:"monthly",pay_day:payDay,cutoff_day:cutoffDay,effective_from:date)
        if let row=existing.first {
            let _: [Payload] = try await Self.client.database.from("employee_payroll_profiles").eq("id",value:row.id).update(payload)
        } else {
            let _: Payload = try await Self.client.database.from("employee_payroll_profiles").insert(payload)
        }
    }

    func setWorkWeek(employeeId:String,organizationId:String,branchId:String,employeeCode:String,pattern:String,effectiveFrom:Date) async throws {
        let workingDays:Set<Int>
        switch pattern { case "mon_fri": workingDays=[1,2,3,4,5]; case "every_day": workingDays=[1,2,3,4,5,6,7]; default: workingDays=[1,2,3,4,5,6] }
        struct DayRule:Codable { let working:Bool }
        struct TemplatePayload:Codable { let id,organization_id,branch_id,name:String; let weekly_rules:[String:DayRule]; let grace_minutes,expected_minutes_per_day:Int; let is_active:Bool }
        let templateId=UUID().uuidString
        let rules=Dictionary(uniqueKeysWithValues:(1...7).map{(String($0),DayRule(working:workingDays.contains($0)))})
        let template=TemplatePayload(id:templateId,organization_id:organizationId,branch_id:branchId,name:"\(employeeCode) work week from \(ISODate.string(from:effectiveFrom))",weekly_rules:rules,grace_minutes:10,expected_minutes_per_day:480,is_active:true)
        let _:TemplatePayload = try await Self.client.database.from("schedule_templates").insert(template)
        struct Assignment:Codable { let id,employee_id,schedule_template_id,effective_from:String }
        let date=ISODate.string(from:effectiveFrom)
        let existing:[Assignment] = try await Self.client.database.from("employee_schedule_assignments").select().eq("employee_id",value:employeeId).eq("effective_from",value:date).limit(1).execute()
        if let row=existing.first {
            struct Update:Codable { let schedule_template_id:String }
            let _: [Update] = try await Self.client.database.from("employee_schedule_assignments").eq("id",value:row.id).update(Update(schedule_template_id:templateId))
        } else {
            let _:Assignment = try await Self.client.database.from("employee_schedule_assignments").insert(Assignment(id:UUID().uuidString,employee_id:employeeId,schedule_template_id:templateId,effective_from:date))
        }
    }

    func createPayroll(organizationId:String,branchId:String?,title:String,start:Date,end:Date,preparedBy:String) async throws -> PayrollRun {
        struct Payload:Codable { let id,organization_id:String; let branch_id:String?; let title,period_start,period_end,currency,status,prepared_by:String }
        let id=UUID().uuidString
        let _:Payload = try await Self.client.database.from("payroll_runs").insert(Payload(id:id,organization_id:organizationId,branch_id:branchId,title:title,period_start:ISODate.string(from:start),period_end:ISODate.string(from:end),currency:"PKR",status:"draft",prepared_by:preparedBy))
        let rows:[PayrollRun] = try await Self.client.database.from("payroll_runs").select().eq("id",value:id).execute()
        guard let run=rows.first else { throw BackendError.invalidInput("Payroll run was not created.") }; return run
    }
    func preparePayroll(id:String) async throws -> Int { try await Self.client.database.rpc("prepare_payroll_run",args:["p_run_id":id]).executeSingle() }
    func applyPayrollOperations(id:String) async throws -> Int { try await Self.client.database.rpc("apply_payroll_operations",args:["p_run_id":id]).executeSingle() }
    func applyStatutoryRules(id:String) async throws -> Int { try await Self.client.database.rpc("apply_statutory_rules",args:["p_run_id":id]).executeSingle() }
    func transitionPayroll(id:String,status:String) async throws { let _:PayrollRun = try await Self.client.database.rpc("transition_payroll_run",args:["p_run_id":id,"p_status":status]).executeSingle() }
    func recordPayment(itemId:String,amountRupees:Double,method:String,reference:String,paidOn:Date) async throws {
        let _:SalaryPayment = try await Self.client.database.rpc("record_salary_payment",args:["p_payroll_item_id":itemId,"p_amount_minor":Int64((amountRupees*100).rounded()),"p_method":method,"p_reference":reference,"p_paid_on":ISODate.string(from:paidOn)]).executeSingle()
    }

    func updateBranch(_ branch:Branch) async throws {
        struct Payload:Codable { let name,code:String; let address:String?; let latitude,longitude:Double?; let geofence_radius_m:Int; let attendance_verification_mode:String; let requires_biometric:Bool; let gps_accuracy_limit_m:Int }
        let _: [Payload] = try await Self.client.database.from("branches").eq("id",value:branch.id).update(Payload(name:branch.name,code:branch.code,address:branch.address,latitude:branch.latitude,longitude:branch.longitude,geofence_radius_m:branch.geofenceRadiusM,attendance_verification_mode:branch.attendanceVerificationMode,requires_biometric:branch.requiresBiometric,gps_accuracy_limit_m:branch.gpsAccuracyLimitM))
    }
    func createBranch(organizationId:String,name:String,code:String,address:String) async throws {
        struct Payload:Codable {
            let id,organization_id,code,name,address,attendance_verification_mode,timezone:String
            let geofence_radius_m,gps_accuracy_limit_m:Int
            let requires_biometric,is_active:Bool
        }
        let payload=Payload(id:UUID().uuidString,organization_id:organizationId,code:code.trimmingCharacters(in:.whitespacesAndNewlines).uppercased(),name:name.trimmingCharacters(in:.whitespacesAndNewlines),address:address.trimmingCharacters(in:.whitespacesAndNewlines),attendance_verification_mode:"IP_OR_GPS",timezone:"Asia/Karachi",geofence_radius_m:50,gps_accuracy_limit_m:50,requires_biometric:true,is_active:true)
        let _:Payload = try await Self.client.database.from("branches").insert(payload)
    }
    func setBranchActive(id:String,isActive:Bool) async throws {
        struct Payload:Codable { let is_active:Bool }
        let _:[Payload] = try await Self.client.database.from("branches").eq("id",value:id).update(Payload(is_active:isActive))
    }
    func addIPRule(branchId:String,label:String,network:String,userId:String) async throws {
        struct Payload:Codable { let branch_id,label,network,created_by:String; let is_active:Bool }
        let _: Payload = try await Self.client.database.from("branch_ip_rules").insert(Payload(branch_id:branchId,label:label,network:network,created_by:userId,is_active:true))
    }
    func setIPRuleActive(id:String,isActive:Bool) async throws {
        struct Payload:Codable { let is_active:Bool }
        let _:[Payload] = try await Self.client.database.from("branch_ip_rules").eq("id",value:id).update(Payload(is_active:isActive))
    }
    func setEmployeeStatus(id:String,status:String,reason:String) async throws {
        let _:Employee = try await Self.client.database.rpc("set_employee_status",args:["p_employee_id":id,"p_status":status,"p_reason":reason]).executeSingle()
    }
    func assignEmployeeBranch(employeeId:String,branchId:String,isPrimary:Bool,startsOn:Date) async throws {
        let _:EmployeeBranchAssignment = try await Self.client.database.rpc("assign_employee_branch",args:["p_employee_id":employeeId,"p_branch_id":branchId,"p_is_primary":isPrimary,"p_starts_on":ISODate.string(from:startsOn)]).executeSingle()
    }
    func endEmployeeBranchAssignment(id:String,reason:String) async throws {
        let _:EmployeeBranchAssignment = try await Self.client.database.rpc("end_employee_branch_assignment",args:["p_assignment_id":id,"p_reason":reason]).executeSingle()
    }
    func cancelLeave(id:String,reason:String) async throws {
        let _:LeaveRecord = try await Self.client.database.rpc("cancel_leave_request",args:["p_request_id":id,"p_reason":reason]).executeSingle()
    }
    func correctAttendance(id:String,checkIn:Date?,checkOut:Date?,status:String,reason:String) async throws {
        let formatter=ISO8601DateFormatter()
        let _:AttendanceDay = try await Self.client.database.rpc("correct_attendance_day",args:[
            "p_attendance_id":id,"p_first_check_in_at":checkIn.map(formatter.string(from:)) as Any,
            "p_last_check_out_at":checkOut.map(formatter.string(from:)) as Any,"p_status":status,"p_reason":reason
        ]).executeSingle()
    }
    func createAdjustment(organizationId:String,employeeId:String,type:String,label:String,rupees:Double,reason:String,userId:String) async throws {
        struct Payload:Codable { let id,organization_id,employee_id,component_type,label,reason,status,created_by:String; let amount_minor:Int64 }
        let payload=Payload(id:UUID().uuidString,organization_id:organizationId,employee_id:employeeId,component_type:type,label:label,reason:reason,status:"pending",created_by:userId,amount_minor:Int64((rupees*100).rounded()))
        let _:Payload = try await Self.client.database.from("payroll_adjustments").insert(payload)
    }
    func saveSalaryComponent(organizationId:String,employeeId:String,name:String,type:String,rupees:Double,effectiveFrom:Date) async throws {
        let code="CUSTOM_"+name.uppercased().filter{$0.isLetter || $0.isNumber}.prefix(24)
        struct DefinitionPayload:Codable { let id,organization_id,code,name,component_type,calculation_type:String; let is_taxable,is_active:Bool }
        var definitions:[SalaryComponentDefinition] = try await Self.client.database.from("salary_component_definitions").select().eq("organization_id",value:organizationId).eq("code",value:String(code)).limit(1).execute()
        let definitionId:String
        if let existing=definitions.first { definitionId=existing.id }
        else {
            definitionId=UUID().uuidString
            let payload=DefinitionPayload(id:definitionId,organization_id:organizationId,code:String(code),name:name,component_type:type,calculation_type:"fixed",is_taxable:false,is_active:true)
            let _:DefinitionPayload = try await Self.client.database.from("salary_component_definitions").insert(payload)
            definitions=[]
        }
        struct ComponentPayload:Codable { let id,employee_id,component_definition_id:String; let amount_minor:Int64; let effective_from:String }
        let component=ComponentPayload(id:UUID().uuidString,employee_id:employeeId,component_definition_id:definitionId,amount_minor:Int64((rupees*100).rounded()),effective_from:ISODate.string(from:effectiveFrom))
        let _:ComponentPayload = try await Self.client.database.from("employee_salary_components").insert(component)
    }
    func updateProfile(name:String,phone:String) async throws {
        guard let user=try await Self.client.auth.getSession()?.user else { throw BackendError.noMembership }
        struct Payload:Codable { let full_name,phone:String }
        let _:[Payload] = try await Self.client.database.from("profiles").eq("user_id",value:user.id).update(Payload(full_name:name.trimmingCharacters(in:.whitespacesAndNewlines),phone:phone.trimmingCharacters(in:.whitespacesAndNewlines)))
    }
    func markNotificationRead(id:String) async throws {
        struct Payload:Codable { let is_read:Bool }
        let _:[Payload] = try await Self.client.database.from("app_notifications").eq("id",value:id).update(Payload(is_read:true))
    }
    func markAllNotificationsRead() async throws { let _:Int=try await Self.client.database.rpc("mark_all_notifications_read").executeSingle() }
    func saveNotificationPreferences(_ preferences:NotificationPreferences) async throws {
        let existing:[NotificationPreferences]=try await Self.client.database.from("notification_preferences").select().eq("user_id",value:preferences.userId).limit(1).execute()
        if existing.isEmpty { let _:NotificationPreferences=try await Self.client.database.from("notification_preferences").insert(preferences) }
        else { let _:[NotificationPreferences]=try await Self.client.database.from("notification_preferences").eq("user_id",value:preferences.userId).update(preferences) }
    }
    func registerTrustedDevice(deviceId:String,publicKey:String) async throws { let _:Bool=try await Self.client.database.rpc("register_trusted_device",args:["p_device_id":deviceId,"p_public_key":publicKey,"p_device_name":UIDevice.current.name]).executeSingle() }
    func saveLifecycleTask(organizationId:String,employeeId:String,phase:String,title:String,dueOn:Date?) async throws {
        struct Payload:Codable { let organization_id,employee_id,phase,title,status:String;let due_on:String? }
        let _:Payload=try await Self.client.database.from("employee_lifecycle_tasks").insert(Payload(organization_id:organizationId,employee_id:employeeId,phase:phase,title:title,status:"pending",due_on:dueOn.map(ISODate.string(from:))))
    }
    func updateLifecycleTask(id:String,status:String) async throws {
        struct Payload:Codable { let status:String;let completed_at:String? }
        let _:[Payload]=try await Self.client.database.from("employee_lifecycle_tasks").eq("id",value:id).update(Payload(status:status,completed_at:status=="completed" ? ISO8601DateFormatter().string(from:.now):nil))
    }
    func saveEmployeeAsset(organizationId:String,employeeId:String,type:String,label:String,identifier:String,issuedOn:Date) async throws {
        struct Payload:Codable { let organization_id,employee_id,asset_type,label,identifier,issued_on:String }
        let _:Payload=try await Self.client.database.from("employee_assets").insert(Payload(organization_id:organizationId,employee_id:employeeId,asset_type:type,label:label,identifier:identifier,issued_on:ISODate.string(from:issuedOn)))
    }
    func returnEmployeeAsset(id:String,condition:String) async throws {
        struct Payload:Codable { let returned_on,condition_note:String }
        let _:[Payload]=try await Self.client.database.from("employee_assets").eq("id",value:id).update(Payload(returned_on:ISODate.string(from:.now),condition_note:condition))
    }
    func requestAccountDeletion(reason:String) async throws {
        let _:String = try await Self.client.database.rpc("request_account_deletion",args:["p_reason":reason]).executeSingle()
    }
    func createEmployeeInvite(employeeId:String,email:String) async throws -> String {
        try await Self.client.database.rpc("create_employee_invite",args:["p_employee_id":employeeId,"p_email":email,"p_valid_hours":72]).executeSingle()
    }
    func claimEmployeeInvite(code:String) async throws {
        struct Result:Decodable { let organizationId,employeeId:String; enum CodingKeys:String,CodingKey{case organizationId="organization_id",employeeId="employee_id"} }
        let _:Result = try await Self.client.database.rpc("claim_employee_invite",args:["p_code":code]).executeSingle()
    }
    func registerKiosk(branchId:String,name:String) async throws -> BranchKioskDevice {
        try await Self.client.database.rpc("register_branch_kiosk",args:["p_branch_id":branchId,"p_device_id":DeviceIdentity.value,"p_device_name":name]).executeSingle()
    }
    func deactivateKiosk(id:String) async throws {
        let _:Bool=try await Self.client.database.rpc("deactivate_branch_kiosk",args:["p_kiosk_id":id]).executeSingle()
    }
    func saveScheduleTemplate(_ template:ScheduleTemplate) async throws {
        struct Payload:Codable {
            let organization_id:String;let branch_id:String?;let name:String;let weekly_rules:[String:ScheduleDayRule]
            let grace_minutes,expected_minutes_per_day:Int;let is_active:Bool;let check_in_time,check_out_time:String
            let break_minutes,overtime_after_minutes:Int;let is_overnight,is_split_shift:Bool;let notes:String?
        }
        let payload=Payload(organization_id:template.organizationId,branch_id:template.branchId,name:template.name,weekly_rules:template.weeklyRules,
                            grace_minutes:template.graceMinutes,expected_minutes_per_day:template.expectedMinutesPerDay,is_active:template.isActive,
                            check_in_time:template.checkInTime,check_out_time:template.checkOutTime,break_minutes:template.breakMinutes,
                            overtime_after_minutes:template.overtimeAfterMinutes,is_overnight:template.isOvernight,is_split_shift:template.isSplitShift,notes:template.notes)
        if template.id.isEmpty { let _:Payload=try await Self.client.database.from("schedule_templates").insert(payload) }
        else { let _:[Payload]=try await Self.client.database.from("schedule_templates").eq("id",value:template.id).update(payload) }
    }
    func assignSchedule(employeeId:String,templateId:String,effectiveFrom:Date) async throws {
        struct Payload:Codable { let employee_id,schedule_template_id,effective_from:String }
        let _:Payload=try await Self.client.database.from("employee_schedule_assignments").insert(Payload(employee_id:employeeId,schedule_template_id:templateId,effective_from:ISODate.string(from:effectiveFrom)))
    }
    func bulkImport(branchId:String,rows:[[String:String]]) async throws -> BulkImportResult {
        try await Self.client.database.rpc("bulk_upsert_staff",args:["p_branch_id":branchId,"p_rows":rows]).executeSingle()
    }
    func generatePayslips(runId:String) async throws {
        struct Request:Codable { let runId:String }
        struct Result:Decodable { let generated,skipped,runs:Int }
        let _:Result=try await Self.client.functions.invoke("payslip-action",body:Request(runId:runId))
    }
    func downloadPayslip(_ document:PayslipDocument,action:String="share") async throws ->URL {
        let data=try await Self.client.storage.from("payslips").download(path:document.storagePath)
        let file=FileManager.default.temporaryDirectory.appendingPathComponent("CB-Payslip-v\(document.version)-\(document.payrollItemId).pdf")
        try data.write(to:file,options:[.atomic,.completeFileProtection])
        let _:Bool=try await Self.client.database.rpc("record_payslip_access",args:["p_document_id":document.id,"p_action":action,"p_device_id":DeviceIdentity.value]).executeSingle()
        return file
    }
}

struct AttendanceFunctionRequest: Codable {
    let requestId, branchId, eventType, deviceId: String
    let latitude, longitude, gpsAccuracyM: Double?
    let biometricProofId: String?
    let overrideEmployeeId, overrideReason, managerPassword: String?
    let kioskEmployeeId: String?
    let isSimulated, isProducedByAccessory: Bool
}
struct AttendanceFunctionResponse: Codable {
    let accepted: Bool
    let attemptId, eventId, rejectionCode: String?
    let distanceM: Double?
    let ipPassed, gpsPassed: Bool?
    let syncedOffline: Bool?
}
