import Foundation

enum AppRole: String, Codable, CaseIterable {
    case owner, manager, staff = "employee"

    var canManagePeople: Bool { self != .staff }
    var canAdministerEmployees: Bool { self == .owner }
    var canManagePayroll: Bool { self == .owner }
    var canApprovePayroll: Bool { self == .owner }
    var isAdministrator: Bool { self != .staff }
    var title: String { self == .staff ? L10n.text("Staff") : L10n.text(rawValue.capitalized) }

    static func resolved(_ value: String) -> AppRole {
        switch value {
        case "owner": .owner
        case "manager", "super_admin", "hr_admin", "payroll_admin", "payroll_approver": .manager
        default: .staff
        }
    }
}

struct AdminUser: Codable, Hashable {
    let id: String
    let fullName: String
    let email: String
    let role: String
    var appRole: AppRole { AppRole.resolved(role) }
}

struct OrganizationMembership: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let userId: String
    let role: String
    let isActive: Bool
    enum CodingKeys: String, CodingKey { case id, role; case organizationId = "organization_id"; case userId = "user_id"; case isActive = "is_active" }
}

struct Branch: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    var code: String
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var geofenceRadiusM: Int
    var attendanceVerificationMode: String
    var requiresBiometric: Bool
    var gpsAccuracyLimitM: Int
    var timezone: String
    var isActive: Bool
    enum CodingKeys: String, CodingKey {
        case id, code, name, address, latitude, longitude, timezone
        case organizationId = "organization_id", geofenceRadiusM = "geofence_radius_m"
        case attendanceVerificationMode = "attendance_verification_mode"
        case requiresBiometric = "requires_biometric", gpsAccuracyLimitM = "gps_accuracy_limit_m", isActive = "is_active"
    }
}

struct DashboardStats: Codable, Hashable {
    var today = ISODate.string(from: .now)
    var activeEmployees = 0
    var inactiveEmployees = 0
    var present = 0
    var absent = 0
    var leaveCount = 0
    var pendingLeaves = 0
}

struct BiometricMetrics: Codable, Hashable {
    var totalFaceEnrolledEmployees = 0
    var pendingFaceEnrollment = 0
    var attendanceSuccessRate = 0.0
    var failedVerificationRate = 0.0
    var systemHealth = "Healthy"
}

struct Employee: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String?
    var userId: String?
    var employeeCode: String
    var fullName: String
    var phone: String?
    var position: String?
    var cnic: String?
    var address: String?
    var joiningDate: String?
    var employmentStatus: String
    var appRole: String
    var terminationDate: String?
    var createdAt: String?
    var department: String?
    var reportingManagerId: String?
    var employmentType: String?
    var probationEndDate: String?
    var emergencyContactName: String?
    var emergencyContactPhone: String?
    var dateOfBirth: String?
    var role: String { appRole }
    var status: String { employmentStatus }
    var salaryDate: String? { nil }
    enum CodingKeys: String, CodingKey {
        case id, phone, position, cnic, address
        case organizationId = "organization_id", userId = "user_id", employeeCode = "employee_code"
        case fullName = "full_name", joiningDate = "joining_date", employmentStatus = "employment_status"
        case appRole = "app_role"
        case terminationDate = "termination_date", createdAt = "created_at"
        case department, employmentType = "employment_type"
        case reportingManagerId = "reporting_manager_id", probationEndDate = "probation_end_date"
        case emergencyContactName = "emergency_contact_name", emergencyContactPhone = "emergency_contact_phone"
        case dateOfBirth = "date_of_birth"
    }
}

struct AttendanceDay: Codable, Identifiable, Hashable {
    let id: String
    let branchId: String
    let employeeId: String
    let workDate: String
    let firstCheckInAt: String?
    let lastCheckOutAt: String?
    let workedMinutes: Int
    let breakMinutes: Int
    let activeBreakStartedAt: String?
    let status: String
    enum CodingKeys: String, CodingKey {
        case id, status; case branchId = "branch_id", employeeId = "employee_id", workDate = "work_date"
        case firstCheckInAt = "first_check_in_at", lastCheckOutAt = "last_check_out_at", workedMinutes = "worked_minutes"
        case breakMinutes = "break_minutes", activeBreakStartedAt = "active_break_started_at"
    }
}

struct AttendanceRow: Codable, Identifiable, Hashable {
    var id: String { employeeId }
    let employeeId: String
    let employeeCode: String
    let fullName: String
    let position: String?
    let employeeStatus: String
    let attendanceId: String?
    var attendanceStatus: String?
    var markSource: String?
    var notes: String?
    var checkInAt: String?
    var checkOutAt: String?
    var updatedAt: String?
}

struct LeaveType: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let code: String
    let name: String
    let isPaid: Bool
    let defaultAnnualDays: Double
    let requiresDocument: Bool
    let requiresReason: Bool
    let accrualMethod: String
    let carryForwardDays: Double
    let attachmentAfterDays: Double?
    enum CodingKeys: String, CodingKey {
        case id, code, name; case organizationId = "organization_id", isPaid = "is_paid"
        case defaultAnnualDays = "default_annual_days", requiresDocument = "requires_document", requiresReason = "requires_reason"
        case accrualMethod = "accrual_method", carryForwardDays = "carry_forward_days", attachmentAfterDays = "attachment_after_days"
    }
}

struct LeaveRecord: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String?
    let branchId: String?
    let employeeId: String
    let leaveTypeId: String?
    let startDate: String
    let endDate: String
    let requestedDays: Double?
    let durationType: String?
    let requestedMinutes: Int?
    let reason: String?
    var status: String
    let reviewedBy: String?
    let reviewedAt: String?
    let reviewNote: String?
    let createdAt: String?
    var fullName = ""
    var employeeCode = ""
    var requestedByUserId: String { "" }
    var reviewedByUserId: String? { reviewedBy }
    var requestedByName: String? { nil }
    var reviewedByName: String? { nil }
    enum CodingKeys: String, CodingKey {
        case id, reason, status; case organizationId = "organization_id", branchId = "branch_id"
        case employeeId = "employee_id", leaveTypeId = "leave_type_id", startDate = "start_date", endDate = "end_date"
        case requestedDays = "requested_days", durationType = "duration_type", requestedMinutes = "requested_minutes", reviewedBy = "reviewed_by", reviewedAt = "reviewed_at"
        case reviewNote = "review_note", createdAt = "created_at"
    }
}

struct PayrollRun: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let branchId: String?
    let title: String
    let periodStart: String
    let periodEnd: String
    let currency: String
    let status: String
    let preparedBy: String
    let approvedBy: String?
    enum CodingKeys: String, CodingKey {
        case id, title, currency, status; case organizationId = "organization_id", branchId = "branch_id"
        case periodStart = "period_start", periodEnd = "period_end", preparedBy = "prepared_by", approvedBy = "approved_by"
    }
}

struct PayrollItem: Codable, Identifiable, Hashable {
    let id: String
    let payrollRunId: String
    let employeeId: String
    let scheduledDays: Double
    let eligibleDays: Double
    let baseSalaryMinor: Int64
    let proratedBaseMinor: Int64
    let grossMinor: Int64
    let deductionsMinor: Int64
    let netMinor: Int64
    let status: String
    enum CodingKeys: String, CodingKey {
        case id, status; case payrollRunId = "payroll_run_id", employeeId = "employee_id"
        case scheduledDays = "scheduled_days", eligibleDays = "eligible_days", baseSalaryMinor = "base_salary_minor"
        case proratedBaseMinor = "prorated_base_minor", grossMinor = "gross_minor", deductionsMinor = "deductions_minor", netMinor = "net_minor"
    }
    var formattedNet: String { MoneyFormatter.pkr(minor: netMinor) }
}

struct SalaryPayment:Codable,Identifiable,Hashable {
    let id,organizationId,payrollItemId,currency,paymentMethod:String
    let amountMinor:Int64
    let reference:String?
    let paidOn:String
    enum CodingKeys:String,CodingKey{case id,currency,reference;case organizationId="organization_id",payrollItemId="payroll_item_id",amountMinor="amount_minor",paymentMethod="payment_method",paidOn="paid_on"}
}

struct CompensationVersion: Codable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let baseSalaryMinor: Int64
    let currency: String
    let effectiveFrom: String
    enum CodingKeys: String, CodingKey { case id, currency; case employeeId = "employee_id", baseSalaryMinor = "base_salary_minor", effectiveFrom = "effective_from" }
}

struct EmployeePayrollProfile: Codable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let payFrequency: String
    let payDay: Int
    let cutoffDay: Int
    let effectiveFrom: String
    let effectiveTo: String?
    enum CodingKeys: String, CodingKey {
        case id
        case employeeId = "employee_id", payFrequency = "pay_frequency", payDay = "pay_day"
        case cutoffDay = "cutoff_day", effectiveFrom = "effective_from", effectiveTo = "effective_to"
    }
}

struct EmployeeBranchAssignment: Codable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let branchId: String
    var isPrimary: Bool
    let startsOn: String
    var endsOn: String?
    enum CodingKeys: String, CodingKey {
        case id; case employeeId = "employee_id", branchId = "branch_id", isPrimary = "is_primary"
        case startsOn = "starts_on", endsOn = "ends_on"
    }
}

struct BranchIPRule: Codable, Identifiable, Hashable {
    let id: String
    let branchId: String
    let label: String
    let network: String
    var isActive: Bool
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, label, network; case branchId = "branch_id", isActive = "is_active", createdAt = "created_at"
    }
}

struct LeaveBalanceEntry: Codable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let leaveTypeId: String
    let daysDelta: Double
    let entryType: String
    let entryDate: String
    let note: String?
    enum CodingKeys: String, CodingKey {
        case id, note; case employeeId = "employee_id", leaveTypeId = "leave_type_id"
        case daysDelta = "days_delta", entryType = "entry_type", entryDate = "entry_date"
    }
}

struct SalaryComponentDefinition: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let code: String
    let name: String
    let componentType: String
    let calculationType: String
    let isTaxable: Bool
    let isActive: Bool
    enum CodingKeys: String, CodingKey {
        case id, code, name; case organizationId = "organization_id", componentType = "component_type"
        case calculationType = "calculation_type", isTaxable = "is_taxable", isActive = "is_active"
    }
}

struct EmployeeSalaryComponent: Codable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let componentDefinitionId: String
    let amountMinor: Int64?
    let percentage: Double?
    let effectiveFrom: String
    enum CodingKeys: String, CodingKey {
        case id, percentage; case employeeId = "employee_id", componentDefinitionId = "component_definition_id"
        case amountMinor = "amount_minor", effectiveFrom = "effective_from"
    }
}

struct PayrollAdjustment: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String
    let employeeId: String
    let payrollRunId: String?
    let componentType: String
    let label: String
    let amountMinor: Int64
    let reason: String
    let status: String
    enum CodingKeys: String, CodingKey {
        case id, label, reason, status; case organizationId = "organization_id", employeeId = "employee_id"
        case payrollRunId = "payroll_run_id", componentType = "component_type", amountMinor = "amount_minor"
    }
}

struct PayrollItemComponent: Codable, Identifiable, Hashable {
    let id: String
    let payrollItemId: String
    let label: String
    let componentType: String
    let amountMinor: Int64
    let source: String
    enum CodingKeys: String, CodingKey {
        case id, label, source; case payrollItemId = "payroll_item_id", componentType = "component_type", amountMinor = "amount_minor"
    }
}

struct AppNotification: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
    let category: String
    let entityType: String?
    let entityId: String?
    var isRead: Bool
    let createdAt: String
    enum CodingKeys: String, CodingKey { case id, title, message, category; case entityType = "entity_type", entityId = "entity_id", isRead = "is_read", createdAt = "created_at" }
}

struct AuditEvent: Codable, Identifiable, Hashable {
    let id: String
    let action: String
    let entityType: String
    let reason: String?
    let createdAt: String
    enum CodingKeys: String, CodingKey { case id, action, reason; case entityType = "entity_type", createdAt = "created_at" }
}

struct NetworkDiagnostic: Codable, Hashable {
    let observedIp: String?
    let activeRules: [NetworkRule]
}
struct NetworkRule: Codable, Hashable { let label,network:String;let isActive:Bool;enum CodingKeys:String,CodingKey{case label,network;case isActive="is_active"} }

struct BiometricLog: Codable, Identifiable, Hashable { let id, method: String; let success: Int; let details, createdAt, employeeCode, fullName: String? }
struct BiometricSummary: Codable, Hashable { let employeeId, employeeCode, fullName: String; let position: String?; let hasFaceProfile: Int; let faceUpdatedAt: String? }

struct FaceTemplateStatus: Codable, Hashable {
    let employeeId: String
    let enrolled: Bool
    let enrolledAt: String?
    let modelVersion: String?
}

struct FaceVerificationResult: Codable, Hashable {
    let matched: Bool
    let proofId: String?
    let expiresAt: String?
    let similarity: Double?
    let reason: String?
}

struct BiometricChallenge: Codable, Hashable {
    let challengeId: String
    let action: String
    let expiresAt: String
}

struct BiometricLivenessEvidence: Codable, Hashable, Sendable {
    let captureDurationMs: Int
    let qualifiedFrames: Int
    let naturalMotionScore: Double
    let maxFrameJump: Double
    let blinkAmplitude: Double
    let turnAmplitude: Double
    let challengeOrderPassed: Bool
    let passivePassed: Bool

    nonisolated var canonicalString: String {
        let locale=Locale(identifier:"en_US_POSIX")
        func fixed(_ value:Double)->String { String(format:"%.4f",locale:locale,value) }
        return [
            String(captureDurationMs),String(qualifiedFrames),fixed(naturalMotionScore),fixed(maxFrameJump),
            fixed(blinkAmplitude),fixed(turnAmplitude),challengeOrderPassed ? "1":"0",passivePassed ? "1":"0"
        ].joined(separator:",")
    }
}

struct ShiftRosterEntry: Codable, Identifiable, Hashable {
    let id, organizationId, branchId, employeeId, workDate, startsAt, endsAt, status: String
    let breakMinutes: Int
    let notes: String?
    let isPublished: Bool
    let publishedAt: String?
    enum CodingKeys:String,CodingKey { case id,status,notes;case organizationId="organization_id",branchId="branch_id",employeeId="employee_id",workDate="work_date",startsAt="starts_at",endsAt="ends_at",breakMinutes="break_minutes",isPublished="is_published",publishedAt="published_at" }
}

struct ShiftSwapRequest: Codable, Identifiable, Hashable {
    let id, organizationId, branchId, rosterEntryId, requestedByEmployeeId, reason, status: String
    let targetEmployeeId, reviewedBy, reviewedAt, createdAt: String?
    enum CodingKeys:String,CodingKey { case id,reason,status;case organizationId="organization_id",branchId="branch_id",rosterEntryId="roster_entry_id",requestedByEmployeeId="requested_by_employee_id",targetEmployeeId="target_employee_id",reviewedBy="reviewed_by",reviewedAt="reviewed_at",createdAt="created_at" }
}

struct AttendanceCorrectionRequest: Codable, Identifiable, Hashable {
    let id, organizationId, branchId, employeeId, workDate, reason, status: String
    let requestedCheckInAt, requestedCheckOutAt, attachmentPath, reviewNote, reviewedAt, createdAt: String?
    enum CodingKeys:String,CodingKey { case id,reason,status;case organizationId="organization_id",branchId="branch_id",employeeId="employee_id",workDate="work_date",requestedCheckInAt="requested_check_in_at",requestedCheckOutAt="requested_check_out_at",attachmentPath="attachment_path",reviewNote="review_note",reviewedAt="reviewed_at",createdAt="created_at" }
}

struct PublicHoliday: Codable, Identifiable, Hashable {
    let id, organizationId, holidayDate, name: String
    let branchId: String?
    let isPaid: Bool
    enum CodingKeys:String,CodingKey { case id,name;case organizationId="organization_id",branchId="branch_id",holidayDate="holiday_date",isPaid="is_paid" }
}

struct LeaveBlackoutPeriod: Codable, Identifiable, Hashable {
    let id, organizationId, startsOn, endsOn, reason: String
    let branchId: String?
    enum CodingKeys:String,CodingKey { case id,reason;case organizationId="organization_id",branchId="branch_id",startsOn="starts_on",endsOn="ends_on" }
}

struct EmployeeDocument: Codable, Identifiable, Hashable {
    let id, organizationId, employeeId, documentType, title, storageKey, createdAt: String
    let expiresOn: String?
    let isConfidential: Bool
    enum CodingKeys:String,CodingKey { case id,title;case organizationId="organization_id",employeeId="employee_id",documentType="document_type",storageKey="storage_key",expiresOn="expires_on",isConfidential="is_confidential",createdAt="created_at" }
}

struct EmployeeFinancialProfile: Codable, Identifiable, Hashable {
    var id: String { employeeId }
    let employeeId, organizationId: String
    let bankName, accountTitle, iban, taxNumber, eobiNumber: String?
    let taxMonthlyMinor, eobiMonthlyMinor: Int64
    enum CodingKeys:String,CodingKey { case employeeId="employee_id",organizationId="organization_id",bankName="bank_name",accountTitle="account_title",iban,taxNumber="tax_number",eobiNumber="eobi_number",taxMonthlyMinor="tax_monthly_minor",eobiMonthlyMinor="eobi_monthly_minor" }
}

struct PayrollLoan: Codable, Identifiable, Hashable {
    let id, organizationId, employeeId, label, startsOn, status: String
    let principalMinor, installmentMinor, outstandingMinor: Int64
    enum CodingKeys:String,CodingKey { case id,label,status;case organizationId="organization_id",employeeId="employee_id",principalMinor="principal_minor",installmentMinor="installment_minor",outstandingMinor="outstanding_minor",startsOn="starts_on" }
}

struct PayrollReimbursement: Codable, Identifiable, Hashable {
    let id, organizationId, employeeId, label, expenseDate, reason, status: String
    let amountMinor: Int64
    let receiptPath: String?
    enum CodingKeys:String,CodingKey { case id,label,reason,status;case organizationId="organization_id",employeeId="employee_id",amountMinor="amount_minor",expenseDate="expense_date",receiptPath="receipt_path" }
}

struct StatutoryRuleConfiguration:Codable,Hashable {
    var amountMinor:Int64?
    var ratePercent:Double?
    enum CodingKeys:String,CodingKey{case amountMinor="amount_minor",ratePercent="rate_percent"}
}

struct PayrollStatutoryRule:Codable,Identifiable,Hashable {
    let id,organizationId,code,name,ruleType,effectiveFrom:String
    let effectiveTo:String?
    let configuration:StatutoryRuleConfiguration
    let isActive:Bool
    enum CodingKeys:String,CodingKey{case id,code,name,configuration;case organizationId="organization_id",ruleType="rule_type",effectiveFrom="effective_from",effectiveTo="effective_to",isActive="is_active"}
}

struct SalarySummary: Codable, Hashable {
    let employeeId, currency, periodStart, periodEnd, nextPayDate: String
    let baseSalaryMinor, approvedEarningsMinor, approvedDeductionsMinor, pendingDeductionsMinor: Int64
    let estimatedNetMinor, confirmedNetMinor, paidMinor, remainingMinor: Int64
}

struct SalaryLedgerTransaction: Codable, Identifiable, Hashable {
    let id, organizationId, employeeId, transactionType, category, label, description, currency, status, occurredAt, sourceType, createdAt: String
    let branchId, ruleId, payrollItemId, reversalOfId, sourceId, calculationText, createdBy, approvedBy, approvedAt, appliedAt: String?
    let amountMinor: Int64
    let unitRateMinor: Int64?
    let workDate: String?
    let quantity: Double?
    let calculationMinutes: Int?
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case id, category, label, description, currency, status, quantity
        case organizationId="organization_id", branchId="branch_id", employeeId="employee_id", ruleId="rule_id"
        case payrollItemId="payroll_item_id", reversalOfId="reversal_of_id", transactionType="transaction_type"
        case amountMinor="amount_minor", occurredAt="occurred_at", workDate="work_date", sourceType="source_type", sourceId="source_id"
        case unitRateMinor="unit_rate_minor", calculationMinutes="calculation_minutes", calculationText="calculation_text"
        case createdBy="created_by", approvedBy="approved_by", approvedAt="approved_at", appliedAt="applied_at", createdAt="created_at", hasMore="has_more"
    }
    var signedAmountMinor: Int64 { transactionType == "deduction" ? -amountMinor : amountMinor }
}

struct SalaryTransactionRule: Codable, Identifiable, Hashable {
    let id, organizationId, code, name, transactionType, category, calculationMethod, scopeType, effectiveFrom: String
    let branchId, description, scopeValue, effectiveTo: String?
    let rateMinor, dailyCapMinor, monthlyCapMinor: Int64?
    let percentage: Double?
    let graceMinutes: Int
    let approvalRequired, allowDispute, autoGenerate, isActive: Bool
    enum CodingKeys:String,CodingKey {
        case id,code,name,description,category,percentage
        case organizationId="organization_id",branchId="branch_id",transactionType="transaction_type",calculationMethod="calculation_method"
        case rateMinor="rate_minor",graceMinutes="grace_minutes",dailyCapMinor="daily_cap_minor",monthlyCapMinor="monthly_cap_minor"
        case scopeType="scope_type",scopeValue="scope_value",approvalRequired="approval_required",allowDispute="allow_dispute"
        case autoGenerate="auto_generate",effectiveFrom="effective_from",effectiveTo="effective_to",isActive="is_active"
    }
}

struct SalaryFoodItem: Codable, Identifiable, Hashable {
    let id, organizationId, name, unitLabel, effectiveFrom: String
    let branchId, effectiveTo: String?
    let unitPriceMinor: Int64
    let isActive: Bool
    enum CodingKeys:String,CodingKey { case id,name;case organizationId="organization_id",branchId="branch_id",unitLabel="unit_label",unitPriceMinor="unit_price_minor",effectiveFrom="effective_from",effectiveTo="effective_to",isActive="is_active" }
}

struct SalaryTransactionDispute: Codable, Identifiable, Hashable {
    let id, organizationId, transactionId, employeeId, reason, status, createdByUserId, createdAt: String
    let resolutionNote, reviewedBy, reviewedAt: String?
    enum CodingKeys:String,CodingKey { case id,reason,status;case organizationId="organization_id",transactionId="transaction_id",employeeId="employee_id",resolutionNote="resolution_note",createdByUserId="created_by_user_id",reviewedBy="reviewed_by",reviewedAt="reviewed_at",createdAt="created_at" }
}

struct SalaryTransactionEvent: Codable, Identifiable, Hashable {
    let id, organizationId, transactionId, eventType, createdAt: String
    let fromStatus, toStatus, note, actorUserId: String?
    enum CodingKeys:String,CodingKey { case id,note;case organizationId="organization_id",transactionId="transaction_id",eventType="event_type",fromStatus="from_status",toStatus="to_status",actorUserId="actor_user_id",createdAt="created_at" }
}

struct SalaryLedgerFilter: Hashable {
    var preset = "this_month"
    var from: Date? = Calendar.current.date(from: Calendar.current.dateComponents([.year,.month], from: .now))
    var to: Date? = .now
    var transactionType = "all"
    var category = "all"
    var status = "all"
    var search = ""
}

struct SalaryRuleDraft: Hashable {
    var id: String?
    var code = ""
    var name = ""
    var description = ""
    var transactionType = "deduction"
    var category = "custom"
    var calculationMethod = "fixed"
    var rate = ""
    var percentage = ""
    var graceMinutes = 0
    var dailyCap = ""
    var monthlyCap = ""
    var scopeType = "all"
    var scopeValue = ""
    var approvalRequired = true
    var allowDispute = true
    var autoGenerate = false
    var effectiveFrom = Date()
    var isActive = true
}

struct MobileDashboardSummary: Codable, Hashable {
    let activeEmployees, present, absent, onLeave, pendingCorrections, scheduledShifts: Int
}

struct MultiBranchSummary: Codable, Identifiable, Hashable {
    var id: String { branchId }
    let branchId, branchCode, branchName: String
    let activeEmployees, present, absent, onLeave, pendingLeaves, pendingCorrections, scheduledShifts: Int
    enum CodingKeys:String,CodingKey {
        case branchId="branch_id",branchCode="branch_code",branchName="branch_name"
        case activeEmployees="active_employees",present,absent,onLeave="on_leave",pendingLeaves="pending_leaves"
        case pendingCorrections="pending_corrections",scheduledShifts="scheduled_shifts"
    }
}

struct ScheduleDayRule: Codable, Hashable {
    var working = true
    var start = "09:00:00"
    var end = "18:00:00"
    var breakMinutes = 60
    var expectedMinutes = 480
    var secondStart: String?
    var secondEnd: String?
    var overnight = false
}

struct ScheduleTemplate: Codable, Identifiable, Hashable {
    let id, organizationId: String
    let branchId: String?
    var name: String
    var weeklyRules: [String:ScheduleDayRule]
    var graceMinutes, expectedMinutesPerDay: Int
    var isActive: Bool
    var checkInTime, checkOutTime: String
    var breakMinutes, overtimeAfterMinutes: Int
    var isOvernight, isSplitShift: Bool
    var notes: String?
    enum CodingKeys:String,CodingKey {
        case id,name,notes
        case organizationId="organization_id",branchId="branch_id",weeklyRules="weekly_rules",graceMinutes="grace_minutes"
        case expectedMinutesPerDay="expected_minutes_per_day",isActive="is_active",checkInTime="check_in_time"
        case checkOutTime="check_out_time",breakMinutes="break_minutes",overtimeAfterMinutes="overtime_after_minutes"
        case isOvernight="is_overnight",isSplitShift="is_split_shift"
    }
}

struct BranchKioskDevice: Codable, Identifiable, Hashable {
    let id, organizationId, branchId, deviceId, deviceName, registeredBy: String
    let isActive: Bool
    let registeredAt, lastUsedAt, revokedAt: String?
    enum CodingKeys:String,CodingKey {
        case id
        case organizationId="organization_id",branchId="branch_id",deviceId="device_id",deviceName="device_name"
        case registeredBy="registered_by",isActive="is_active",registeredAt="registered_at",lastUsedAt="last_used_at",revokedAt="revoked_at"
    }
}

struct PayslipDocument: Codable, Identifiable, Hashable {
    let id, organizationId, payrollItemId, employeeId, storagePath, contentType: String
    let generatedAt: String
    let version: Int
    let fileSizeBytes: Int64?
    enum CodingKeys:String,CodingKey {
        case id,version
        case organizationId="organization_id",payrollItemId="payroll_item_id",employeeId="employee_id",storagePath="storage_path"
        case contentType="content_type",generatedAt="generated_at",fileSizeBytes="file_size_bytes"
    }
}

struct BulkImportResult: Codable, Hashable { let created, updated, assigned: Int }

struct NotificationPreferences: Codable, Hashable {
    let userId: String
    let organizationId: String
    var pushEnabled = true
    var attendanceEnabled = true
    var shiftsEnabled = true
    var leaveEnabled = true
    var payrollEnabled = true
    var documentsEnabled = true
    var quietStart: String?
    var quietEnd: String?
    enum CodingKeys:String,CodingKey {
        case userId="user_id",organizationId="organization_id",pushEnabled="push_enabled"
        case attendanceEnabled="attendance_enabled",shiftsEnabled="shifts_enabled",leaveEnabled="leave_enabled"
        case payrollEnabled="payroll_enabled",documentsEnabled="documents_enabled",quietStart="quiet_start",quietEnd="quiet_end"
    }
}

struct WorkforceReportRow: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(reportType)-\(recordId)" }
    let reportType, recordId, employeeId, employeeName, employeeCode, recordDate, status: String
    let amountMinor: Int64?
    let details: String?
    let branchName, markMethod, rejectionCode: String?
    let usedOverride, hasMore: Bool?
    let lateMinutes, overtimeMinutes: Int?
    enum CodingKeys:String,CodingKey {
        case reportType="report_type",recordId="record_id",employeeId="employee_id",employeeName="employee_name"
        case employeeCode="employee_code",recordDate="record_date",status,amountMinor="amount_minor",details
        case branchName="branch_name",markMethod="mark_method",usedOverride="used_override"
        case lateMinutes="late_minutes",overtimeMinutes="overtime_minutes",rejectionCode="rejection_code",hasMore="has_more"
    }
}

struct AttendanceHistoryEntry: Codable, Identifiable, Hashable {
    var id: String { recordId }
    let recordId, employeeId, employeeName, employeeCode, branchId, branchName, workDate, status: String
    let firstCheckInAt, lastCheckOutAt, markMethod, correctionStatus: String?
    let workedMinutes, scheduledMinutes, breakMinutes, lateMinutes, overtimeMinutes, shortfallMinutes: Int
    let usedOverride, hasMore: Bool
    enum CodingKeys:String,CodingKey {
        case recordId="record_id",employeeId="employee_id",employeeName="employee_name",employeeCode="employee_code"
        case branchId="branch_id",branchName="branch_name",workDate="work_date",status
        case firstCheckInAt="first_check_in_at",lastCheckOutAt="last_check_out_at",workedMinutes="worked_minutes"
        case scheduledMinutes="scheduled_minutes",breakMinutes="break_minutes",lateMinutes="late_minutes"
        case overtimeMinutes="overtime_minutes",shortfallMinutes="shortfall_minutes",markMethod="mark_method"
        case usedOverride="used_override",correctionStatus="correction_status",hasMore="has_more"
    }
}

struct AttendanceHistoryFilter: Hashable {
    var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var to = Date()
}

struct WorkforceReportFilter: Hashable {
    var kind = "all"
    var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var to = Date()
    var employeeId = ""
    var status = "all"
    var markMethod = "all"
    var overrideMode = "all"
    var search = ""
}

struct OperationsHealth: Codable, Hashable {
    let backendOk: Bool
    let generatedAt: String
    let activeEmployees, activeIPRules, missingFaceEnrollments, missingSchedules, missingCompensations: Int
    let pendingPushNotifications, failedPushNotifications, attendanceRejections7d, crashes7d, errors7d: Int
    let missingBranchLocation: Bool
    let lastCrashAt, lastPushSentAt, lastAttendanceAt: String?
    let topRejectionReasons: [OperationsHealthReason]
}

struct OperationsHealthReason: Codable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let count: Int
}

struct MobileDiagnosticEvent: Codable, Identifiable, Hashable {
    let diagnosticId: String
    let severity: String
    let category: String
    let screen: String?
    let message: String
    let errorCode: String?
    let buildVersion: String
    let osVersion: String
    let modelIdentifier: String
    let deviceId: String
    let occurredAt: String
    let suggestedAction: String
    let hasMore: Bool

    var id: String { diagnosticId }
    enum CodingKeys: String, CodingKey {
        case severity, category, screen, message
        case diagnosticId = "diagnostic_id", errorCode = "error_code"
        case buildVersion = "build_version", osVersion = "os_version"
        case modelIdentifier = "model_identifier", deviceId = "device_id"
        case occurredAt = "occurred_at", suggestedAction = "suggested_action", hasMore = "has_more"
    }
}

struct FailedPushNotification: Codable, Identifiable, Hashable {
    let notificationId: String
    let title: String
    let message: String
    let category: String
    let recipientName: String
    let recipientCode: String?
    let createdAt: String
    let pushAttempts: Int
    let pushLastError: String
    let retryRequestedAt: String?
    let hasMore: Bool

    var id: String { notificationId }
    enum CodingKeys: String, CodingKey {
        case title, message, category
        case notificationId = "notification_id", recipientName = "recipient_name"
        case recipientCode = "recipient_code", createdAt = "created_at"
        case pushAttempts = "push_attempts", pushLastError = "push_last_error"
        case retryRequestedAt = "retry_requested_at", hasMore = "has_more"
    }
}

struct EmployeeLifecycleTask: Codable, Identifiable, Hashable {
    let id, organizationId, employeeId, phase, title, status: String
    let dueOn, completedAt: String?
    enum CodingKeys:String,CodingKey { case id,phase,title,status;case organizationId="organization_id",employeeId="employee_id",dueOn="due_on",completedAt="completed_at" }
}

struct EmployeeAsset: Codable, Identifiable, Hashable {
    let id, organizationId, employeeId, assetType, label, issuedOn: String
    let identifier, returnedOn, conditionNote: String?
    enum CodingKeys:String,CodingKey { case id,label,identifier;case organizationId="organization_id",employeeId="employee_id",assetType="asset_type",issuedOn="issued_on",returnedOn="returned_on",conditionNote="condition_note" }
}

struct EmployeeAvailability: Codable, Identifiable, Hashable {
    let id, organizationId, branchId, employeeId: String
    let weekday: Int
    let availableFrom, availableUntil, note: String?
    let isAvailable: Bool
    enum CodingKeys:String,CodingKey { case id,weekday,note;case organizationId="organization_id",branchId="branch_id",employeeId="employee_id",availableFrom="available_from",availableUntil="available_until",isAvailable="is_available" }
}

struct EmployeeDraft: Hashable {
    var id: String?, employeeCode = "", fullName = "", phone = "", position = "", cnic = "", address = ""
    var joiningDate = Date(), role = "employee", status = "active"
    var department = "", reportingManagerId = "", employmentType = "full_time"
    var hasProbationEnd = false, probationEndDate = Date()
    var emergencyContactName = "", emergencyContactPhone = ""
    init() {}
    init(employee: Employee) {
        id = employee.id; employeeCode = employee.employeeCode; fullName = employee.fullName
        phone = employee.phone ?? ""; position = employee.position ?? ""; cnic = employee.cnic ?? ""; address = employee.address ?? ""
        joiningDate = ISODate.date(from: employee.joiningDate) ?? .now; role = employee.appRole; status = employee.employmentStatus
        department = employee.department ?? ""; reportingManagerId = employee.reportingManagerId ?? ""; employmentType = employee.employmentType ?? "full_time"
        if let date = ISODate.date(from: employee.probationEndDate) { hasProbationEnd = true; probationEndDate = date }
        emergencyContactName = employee.emergencyContactName ?? ""; emergencyContactPhone = employee.emergencyContactPhone ?? ""
    }
}

enum CNICFormatter {
    static func digits(from value: String) -> String {
        String(value.filter(\.isNumber).prefix(13))
    }

    static func format(_ value: String) -> String {
        let digits = digits(from: value)
        guard digits.count > 5 else { return digits }

        let areaEnd = digits.index(digits.startIndex, offsetBy: 5)
        let area = digits[..<areaEnd]
        let remainder = digits[areaEnd...]
        guard remainder.count > 7 else { return "\(area)-\(remainder)" }

        let serialEnd = remainder.index(remainder.startIndex, offsetBy: 7)
        return "\(area)-\(remainder[..<serialEnd])-\(remainder[serialEnd...])"
    }

    static func isComplete(_ value: String) -> Bool {
        digits(from: value).count == 13
    }
}

struct LeaveDraft: Hashable { var employeeId = ""; var leaveTypeId = ""; var startDate = Date(); var endDate = Date(); var reason = ""; var documentURL: URL?; var durationType = "full_day"; var requestedMinutes:Int? }

enum ISODate {
    static let formatter: DateFormatter = { let f=DateFormatter(); f.calendar=Calendar(identifier:.gregorian); f.locale=Locale(identifier:"en_US_POSIX"); f.timeZone=TimeZone(identifier:"Asia/Karachi"); f.dateFormat="yyyy-MM-dd"; return f }()
    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from value: String?) -> Date? { value.flatMap(formatter.date) }
}

enum MoneyFormatter {
    static func pkr(minor: Int64) -> String {
        let f=NumberFormatter(); f.numberStyle = .currency; f.currencyCode="PKR"; f.locale=Locale(identifier:"en_PK")
        return f.string(from:NSDecimalNumber(value:Double(minor)/100)) ?? "PKR \(Double(minor)/100)"
    }
}

extension String { nonisolated var sentenceCased: String { prefix(1).uppercased()+dropFirst().lowercased() } }
