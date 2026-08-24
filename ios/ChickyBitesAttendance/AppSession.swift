import Foundation
import Observation
import LocalAuthentication
import Security
import UserNotifications
import InsForge
import UIKit
import Network

@MainActor @Observable
final class AppSession {
    enum Access: Equatable { case signedOut, authenticated(AdminUser), demo(AdminUser) }
    var access: Access = .signedOut
    var currentUser: AdminUser? { if case .authenticated(let u)=access { return u }; if case .demo(let u)=access{return u}; return nil }
    var role: AppRole { currentUser?.appRole ?? .staff }
    var isDemo: Bool { if case .demo=access{return true}; return false }
    var branches:[Branch]=[]
    var selectedBranchId:String? = UserDefaults.standard.string(forKey:"cb.selectedBranch")
    var selectedBranch:Branch? { branches.first{$0.id==selectedBranchId} ?? branches.first }
    var organizationId:String? { selectedBranch?.organizationId }
    var employees:[Employee]=[]
    var attendanceDays:[AttendanceDay]=[]
    var attendance:[AttendanceRow]=[]
    var leaveTypes:[LeaveType]=[]
    var leaves:[LeaveRecord]=[]
    var payrollRuns:[PayrollRun]=[]
    var payrollItems:[PayrollItem]=[]
    var salaryPayments:[SalaryPayment]=[]
    var compensations:[CompensationVersion]=[]
    var payrollProfiles:[EmployeePayrollProfile]=[]
    var employeeBranchAssignments:[EmployeeBranchAssignment]=[]
    var branchIPRules:[BranchIPRule]=[]
    var leaveBalanceEntries:[LeaveBalanceEntry]=[]
    var salaryComponentDefinitions:[SalaryComponentDefinition]=[]
    var employeeSalaryComponents:[EmployeeSalaryComponent]=[]
    var payrollAdjustments:[PayrollAdjustment]=[]
    var payrollItemComponents:[PayrollItemComponent]=[]
    var notifications:[AppNotification]=[]
    var auditEvents:[AuditEvent]=[]
    var shifts:[ShiftRosterEntry]=[]
    var shiftSwaps:[ShiftSwapRequest]=[]
    var correctionRequests:[AttendanceCorrectionRequest]=[]
    var holidays:[PublicHoliday]=[]
    var leaveBlackouts:[LeaveBlackoutPeriod]=[]
    var employeeDocuments:[EmployeeDocument]=[]
    var financialProfiles:[EmployeeFinancialProfile]=[]
    var payrollLoans:[PayrollLoan]=[]
    var reimbursements:[PayrollReimbursement]=[]
    var statutoryRules:[PayrollStatutoryRule]=[]
    var salarySummary:SalarySummary?
    var salaryLedger:[SalaryLedgerTransaction]=[]
    var salaryRules:[SalaryTransactionRule]=[]
    var salaryFoodItems:[SalaryFoodItem]=[]
    var salaryDisputes:[SalaryTransactionDispute]=[]
    var branchSummaries:[MultiBranchSummary]=[]
    var scheduleTemplates:[ScheduleTemplate]=[]
    var kioskDevices:[BranchKioskDevice]=[]
    var payslipDocuments:[PayslipDocument]=[]
    var employeesHaveMore=false
    var shiftsHaveMore=false
    var leavesHaveMore=false
    var payrollRunsHaveMore=false
    var employeeDocumentsHaveMore=false
    var payrollLoansHaveMore=false
    var reimbursementsHaveMore=false
    var payslipDocumentsHaveMore=false
    var olderLeaveIsLoading=false
    var olderPayrollIsLoading=false
    var olderDocumentsIsLoading=false
    var olderLoansIsLoading=false
    var salaryLedgerFilter=SalaryLedgerFilter()
    var salaryLedgerHasMore=false
    var salaryLedgerIsLoading=false
    var lifecycleTasks:[EmployeeLifecycleTask]=[]
    var employeeAssets:[EmployeeAsset]=[]
    var employeeAvailability:[EmployeeAvailability]=[]
    var notificationPreferences:NotificationPreferences?
    var offlineAttendanceCount=0
    var offlineSyncMessage:String?
    var isConnected=true
    var dashboardSummary:MobileDashboardSummary?
    var stats=DashboardStats()
    var metrics=BiometricMetrics()
    var biometricLogs:[BiometricLog]=[]
    var biometricSummaries:[String:BiometricSummary]=[:]
    var selectedDate=Date()
    var isWorking=false
    var attendanceIsLoading=false
    var operationsIsLoading=false
    var dashboardIsLoading=false
    var peopleIsLoading=false
    var leaveIsLoading=false
    var payrollIsLoading=false
    var workforceIsLoading=false
    var branchSettingsIsLoading=false
    var attendanceHistory:[AttendanceHistoryEntry]=[]
    var attendanceHistoryFilter=AttendanceHistoryFilter()
    var attendanceHistoryHasMore=false
    var attendanceHistoryIsLoading=false
    var workforceReportRows:[WorkforceReportRow]=[]
    var workforceReportHasMore=false
    var workforceReportIsLoading=false
    var operationsHealth:OperationsHealth?
    var operationsHealthIsLoading=false
    var diagnosticEvents:[MobileDiagnosticEvent]=[]
    var diagnosticSeverity:String?=nil
    var diagnosticEventsHaveMore=false
    var diagnosticEventsIsLoading=false
    var failedPushNotifications:[FailedPushNotification]=[]
    var failedPushNotificationsHaveMore=false
    var failedPushNotificationsIsLoading=false
    var notificationRetryIsWorking=false
    var isRestoringSession=true
    var isEstablishingSession=false
    var errorMessage:String?
    var noticeMessage:String?
    var successMessage:String?
    var pendingVerificationEmail:String?
    var pendingPasswordResetEmail:String?
    var passwordResetToken:String?
    var generatedInviteCode:String?
    var observedPublicIP:String?
    var hasBiometricLogin:Bool { BiometricLoginStore.hasCredential }
    var biometricName:String { BiometricLoginStore.biometricName }
    private let backend=InsForgeService()
    private var realtimeStarted=false
    private var realtimeChannelName:String?
    private var realtimeListenerId:UUID?
    @ObservationIgnored private let pathMonitor=NWPathMonitor()
    @ObservationIgnored private let pathQueue=DispatchQueue(label:"pk.com.chickybites.employeehub.connectivity")
    @ObservationIgnored private var refreshInProgress=false
    @ObservationIgnored private var attendanceRefreshPending=false
    @ObservationIgnored private var lastSuccessfulFullRefreshAt:Date?
    @ObservationIgnored private var attendanceHistoryGeneration=UUID()
    @ObservationIgnored private var workforceReportGeneration=UUID()
    @ObservationIgnored private var operationsHealthGeneration=UUID()
    @ObservationIgnored private var diagnosticFeedGeneration=UUID()
    @ObservationIgnored private var failedPushGeneration=UUID()
    var lastSuccessfulRefreshAt:Date? { lastSuccessfulFullRefreshAt }

    private enum SessionPreference {
        static let remember = "cb.rememberSession"
        static let email = "cb.rememberedEmail"
    }

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                if !wasConnected && self.isConnected && self.currentUser != nil {
                    await self.syncOfflineAttendance()
                    await self.refreshIfStale(minimumInterval:60)
                }
            }
        }
        pathMonitor.start(queue:pathQueue)
        BackgroundRecoveryCoordinator.shared.operation = { [weak self] in
            guard let self else{return false}
            return await self.performBackgroundRecovery()
        }
    }

    func restoreSession() async {
        defer { isRestoringSession=false }
        guard UserDefaults.standard.bool(forKey:SessionPreference.remember) else {
            try? await backend.signOut()
            access = .signedOut
            return
        }
        do {
            guard let user=try await backend.currentUser() else { access = .signedOut; return }
            access = .authenticated(user)
            loadCache(for:user.id)
            try await refresh()
            await prepareTrustedDeviceAndSync()
        } catch {
            AppDiagnostics.shared.capture(error:error,category:"session-restore",screen:"Session Restore")
            access = .signedOut
            errorMessage = UserFacingError.message(for:error)
        }
    }
    func signIn(email:String,password:String,rememberMe:Bool=true,enableBiometric:Bool=false) async {
        isWorking=true;isEstablishingSession=true; errorMessage=nil
        defer{isWorking=false;isEstablishingSession=false}
        do {
            let normalizedEmail=email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            let user=try await backend.signIn(email:normalizedEmail,password:password)
            access = .authenticated(user)
            loadCache(for:user.id)
            try await refresh()
            await prepareTrustedDeviceAndSync()
            AppDiagnostics.shared.captureBreadcrumb("Account signed in",category:"authentication",screen:"Login")
            let shouldRemember = rememberMe || enableBiometric
            UserDefaults.standard.set(shouldRemember,forKey:SessionPreference.remember)
            if shouldRemember { UserDefaults.standard.set(normalizedEmail,forKey:SessionPreference.email) }
            else { UserDefaults.standard.removeObject(forKey:SessionPreference.email) }
            if enableBiometric {
                do {
                    try await BiometricLoginStore.save(email:normalizedEmail,password:password)
                    successMessage="\(biometricName) login is ready."
                } catch {
                    successMessage="Signed in. \(biometricName) login was not enabled."
                }
            }
        } catch {
            AppDiagnostics.shared.capture(error:error,category:"authentication",screen:"Login")
            if case .authenticated = access {
                try? await backend.signOut()
                access = .signedOut
            }
            if AuthFlowClassifier.requiresVerification(error) {
                pendingVerificationEmail=email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                successMessage="Enter your verification code to finish signing in."
            } else {
                errorMessage=UserFacingError.message(for:error)
            }
        }
    }
    func register(name:String,email:String,password:String) async {
        await perform { let needsVerification=try await backend.signUp(email:email,password:password,name:name); pendingVerificationEmail=needsVerification ? email:nil; successMessage=needsVerification ? "Verification code sent.":"Account created. You can sign in." }
    }
    func verify(code:String) async {
        guard let email=pendingVerificationEmail else{return}
        isEstablishingSession=true
        defer { isEstablishingSession=false }
        await perform {
            let user=try await backend.verify(email:email,code:code)
            pendingVerificationEmail=nil
            access = .authenticated(user)
            try await refresh()
            await prepareTrustedDeviceAndSync()
            UserDefaults.standard.set(true,forKey:SessionPreference.remember)
            UserDefaults.standard.set(email,forKey:SessionPreference.email)
            successMessage="Email verified. Welcome to CB Employee Hub."
        }
    }
    func resendVerification() async {
        guard let email=pendingVerificationEmail else{return}
        await perform { try await backend.resendVerification(email:email); successMessage="A new verification code has been sent." }
    }
    func beginPasswordReset(email:String) async -> Bool {
        let normalized=email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { errorMessage="Enter your registered email address first."; return false }
        return await performReturning {
            try await backend.sendPasswordReset(email:normalized)
            pendingPasswordResetEmail=normalized
            passwordResetToken=nil
            successMessage="If this email is registered, a reset code is on its way."
            return true
        } fallback:{false}
    }
    func verifyPasswordReset(code:String) async -> Bool {
        guard let email=pendingPasswordResetEmail else{return false}
        return await performReturning {
            passwordResetToken=try await backend.exchangePasswordReset(email:email,code:code)
            return true
        } fallback:{false}
    }
    func finishPasswordReset(newPassword:String) async -> Bool {
        guard let token=passwordResetToken else{return false}
        return await performReturning {
            try await backend.resetPassword(token:token,newPassword:newPassword)
            pendingPasswordResetEmail=nil; passwordResetToken=nil
            successMessage="Password updated. Sign in with your new password."
            return true
        } fallback:{false}
    }
    func cancelPasswordReset(){ pendingPasswordResetEmail=nil; passwordResetToken=nil }
    func signInWithBiometrics() async {
        isWorking=true;isEstablishingSession=true; errorMessage=nil
        defer{isWorking=false;isEstablishingSession=false}
        do {
            let credential=try await BiometricLoginStore.read()
            let user=try await backend.signIn(email:credential.email,password:credential.password)
            access = .authenticated(user)
            try await refresh()
            await prepareTrustedDeviceAndSync()
            UserDefaults.standard.set(true,forKey:SessionPreference.remember)
            UserDefaults.standard.set(credential.email,forKey:SessionPreference.email)
            successMessage="Signed in with \(biometricName)."
        } catch {
            if case .authenticated = access { try? await backend.signOut();access = .signedOut }
            if !(error is CancellationError) { errorMessage=UserFacingError.message(for:error) }
        }
    }
    func enableBiometricLogin(password:String) async ->Bool {
        guard let email=currentUser?.email else{return false}
        return await performReturning {
            _ = try await backend.signIn(email:email,password:password)
            try await BiometricLoginStore.save(email:email,password:password)
            successMessage="\(biometricName) login is ready."
            return true
        } fallback:{false}
    }
    func disableBiometricLogin(){ BiometricLoginStore.remove(); successMessage="Biometric login removed from this iPhone." }
    func signOut() async {
        AppDiagnostics.shared.captureBreadcrumb("Account signed out",category:"authentication")
        await flushDiagnostics()
        if let channel=realtimeChannelName { InsForgeService.client.realtime.unsubscribe(from:channel) }
        if let listener=realtimeListenerId { InsForgeService.client.realtime.off("data_changed",id:listener) }
        InsForgeService.client.realtime.disconnect()
        realtimeChannelName=nil;realtimeListenerId=nil;realtimeStarted=false
        MobileCache.clear()
        if !isDemo { try? await backend.deactivateMobileDevice(deviceId:DeviceIdentity.value);try? await backend.signOut() }
        UserDefaults.standard.set(false,forKey:SessionPreference.remember)
        access = .signedOut; branches=[]; employees=[]; attendance=[]; attendanceDays=[]; leaves=[]; payrollRuns=[]; payrollItems=[];shifts=[];shiftSwaps=[];correctionRequests=[];employeeDocuments=[];financialProfiles=[];payrollLoans=[];reimbursements=[];salarySummary=nil;salaryLedger=[];salaryRules=[];salaryFoodItems=[];salaryDisputes=[];branchSummaries=[];scheduleTemplates=[];kioskDevices=[];payslipDocuments=[];attendanceHistory=[];workforceReportRows=[];operationsHealth=nil;diagnosticEvents=[];failedPushNotifications=[]
        leavesHaveMore=false;payrollRunsHaveMore=false;employeeDocumentsHaveMore=false;payrollLoansHaveMore=false;reimbursementsHaveMore=false;payslipDocumentsHaveMore=false
    }
    func selectBranch(_ id:String){ selectedBranchId=id; UserDefaults.standard.set(id,forKey:"cb.selectedBranch"); Task{await refreshSafely()} }

    func refresh() async throws {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await refreshOnce()
                lastSuccessfulFullRefreshAt=Date()
                noticeMessage=nil
                return
            } catch {
                lastError=error
                guard UserFacingError.isTransientServiceFailure(error), attempt < 2 else { throw error }
                try await Task.sleep(for:.milliseconds(350 * (attempt + 1)))
            }
        }
        if let lastError { throw lastError }
    }

    private func refreshOnce() async throws {
        branches=try await backend.branches(); if selectedBranchId==nil || !branches.contains(where:{$0.id==selectedBranchId}) { selectedBranchId=branches.first?.id }
        guard let branch=selectedBranch else{return}
        let date=ISODate.string(from:selectedDate)
        async let loadedEmployees=backend.employees(branchId:branch.id)
        async let loadedAttendance=backend.attendance(branchId:branch.id,date:date)
        async let loadedTypes=backend.leaveTypes()
        async let loadedLeaves=backend.leaves(branchId:branch.id)
        async let loadedNotifications=backend.notifications()
        async let loadedSummary=backend.dashboardSummary(branchId:branch.id,date:date)
        employees=try await loadedEmployees; employeesHaveMore=employees.count == 100; attendanceDays=try await loadedAttendance; leaveTypes=try await loadedTypes
        leaves=try await loadedLeaves; leavesHaveMore=leaves.count==50; notifications=(try? await loadedNotifications) ?? []; dashboardSummary=try? await loadedSummary
        branchSummaries=role.isAdministrator ? ((try? await backend.multiBranchSummary(date:date)) ?? []):[]
        if role == .staff { salarySummary=try? await backend.salarySummary(employeeId:ownEmployee?.id) }
        if let user=currentUser { notificationPreferences=try? await backend.notificationPreferences(organizationId:branch.organizationId,userId:user.id) }
        rebuildAttendancePresentation()
        rebuildDashboardStats()
        saveCache()
        if !realtimeStarted { realtimeStarted=true; await startRealtime(organizationId:branch.organizationId) }
    }

    private func rebuildDashboardStats() {
        stats=DashboardStats(today:ISODate.string(from:selectedDate),activeEmployees:dashboardSummary?.activeEmployees ?? employees.filter{$0.employmentStatus=="active"}.count,inactiveEmployees:employees.filter{$0.employmentStatus != "active"}.count,present:dashboardSummary?.present ?? attendanceDays.filter{$0.status=="present"}.count,absent:dashboardSummary?.absent ?? attendanceDays.filter{$0.status=="absent"}.count,leaveCount:dashboardSummary?.onLeave ?? attendanceDays.filter{$0.status=="leave"}.count,pendingLeaves:leaves.filter{$0.status=="pending"}.count)
    }
    func refreshSafely() async {
        guard !refreshInProgress, !attendanceIsLoading, !operationsIsLoading, currentUser != nil, isConnected else { return }
        refreshInProgress=true
        defer { refreshInProgress=false }
        do { try await refresh() }
        catch {
            if UserFacingError.isTransientServiceFailure(error), !branches.isEmpty {
                noticeMessage="Latest information could not be refreshed. Your saved information is still available."
            } else {
                errorMessage=UserFacingError.message(for:error)
            }
        }
    }

    func refreshDashboardFeature() async {
        guard !dashboardIsLoading,!refreshInProgress,isConnected,let branch=selectedBranch else{return}
        dashboardIsLoading=true;defer{dashboardIsLoading=false}
        let branchId=branch.id
        do {
            let date=ISODate.string(from:selectedDate)
            async let loadedEmployees=backend.employees(branchId:branchId)
            async let loadedAttendance=backend.attendance(branchId:branchId,date:date)
            async let loadedLeaves=backend.leaves(branchId:branchId)
            async let loadedSummary=backend.dashboardSummary(branchId:branchId,date:date)
            let nextEmployees=try await loadedEmployees
            let nextAttendance=try await loadedAttendance
            let nextLeaves=try await loadedLeaves
            let nextSummary=try await loadedSummary
            guard branchId==selectedBranch?.id else{return}
            employees=nextEmployees;employeesHaveMore=nextEmployees.count==100
            attendanceDays=nextAttendance;leaves=nextLeaves;leavesHaveMore=nextLeaves.count==50;dashboardSummary=nextSummary
            branchSummaries=role.isAdministrator ? ((try? await backend.multiBranchSummary(date:date)) ?? branchSummaries):[]
            if role == .staff { salarySummary=try? await backend.salarySummary(employeeId:ownEmployee?.id) }
            rebuildAttendancePresentation();rebuildDashboardStats();saveCache()
        } catch { noticeMessage=employees.isEmpty ? UserFacingError.message(for:error):"Overview could not be refreshed. Saved information is still available." }
    }

    func refreshPeopleFeature() async {
        guard !peopleIsLoading,!refreshInProgress,isConnected,let branch=selectedBranch else{return}
        peopleIsLoading=true;defer{peopleIsLoading=false}
        let branchId=branch.id
        do {
            async let loadedEmployees=backend.employees(branchId:branchId)
            async let loadedAssignments=backend.employeeBranchAssignments(branchId:branchId)
            let nextEmployees=try await loadedEmployees
            let nextAssignments=try await loadedAssignments
            guard branchId==selectedBranch?.id else{return}
            employees=nextEmployees;employeesHaveMore=nextEmployees.count==100;employeeBranchAssignments=nextAssignments
        } catch { noticeMessage=employees.isEmpty ? UserFacingError.message(for:error):"Team information could not be refreshed." }
    }

    func refreshLeaveFeature() async {
        guard !leaveIsLoading,!refreshInProgress,isConnected,let branch=selectedBranch else{return}
        leaveIsLoading=true;defer{leaveIsLoading=false}
        let branchId=branch.id
        do {
            async let loadedTypes=backend.leaveTypes()
            async let loadedLeaves=backend.leaves(branchId:branchId)
            async let loadedBalances=backend.leaveBalanceEntries()
            async let loadedHolidays=backend.holidays(branchId:branchId,organizationId:branch.organizationId)
            async let loadedBlackouts=backend.leaveBlackouts(organizationId:branch.organizationId)
            let nextTypes=try await loadedTypes
            let nextLeaves=try await loadedLeaves
            let nextBalances=(try? await loadedBalances) ?? []
            let nextHolidays=(try? await loadedHolidays) ?? []
            let nextBlackouts=(try? await loadedBlackouts) ?? []
            guard branchId==selectedBranch?.id else{return}
            leaveTypes=nextTypes;leaves=nextLeaves;leavesHaveMore=nextLeaves.count==50;leaveBalanceEntries=nextBalances;holidays=nextHolidays;leaveBlackouts=nextBlackouts
            rebuildAttendancePresentation();rebuildDashboardStats()
        } catch { noticeMessage=leaves.isEmpty ? UserFacingError.message(for:error):"Leave information could not be refreshed." }
    }

    func refreshPayrollFeature() async {
        guard !payrollIsLoading,!refreshInProgress,isConnected,let branch=selectedBranch else{return}
        payrollIsLoading=true;defer{payrollIsLoading=false}
        let branchId=branch.id
        do {
            async let loadedRuns=backend.payrollRuns(branchId:branchId)
            async let loadedItems=backend.payrollItems()
            async let loadedPayments=backend.salaryPayments()
            async let loadedComp=backend.compensations()
            async let loadedProfiles=backend.payrollProfiles()
            async let loadedDefinitions=backend.salaryComponentDefinitions()
            async let loadedEmployeeComponents=backend.employeeSalaryComponents()
            async let loadedAdjustments=backend.payrollAdjustments()
            async let loadedItemComponents=backend.payrollItemComponents()
            async let loadedFinancial=backend.financialProfiles()
            async let loadedLoans=backend.payrollLoans()
            async let loadedReimbursements=backend.reimbursements()
            async let loadedStatutory=backend.statutoryRules(organizationId:branch.organizationId)
            let nextRuns=(try? await loadedRuns) ?? []
            let nextItems=try await loadedItems
            guard branchId==selectedBranch?.id else{return}
            payrollRuns=nextRuns;payrollRunsHaveMore=nextRuns.count==25;payrollItems=nextItems;salaryPayments=(try? await loadedPayments) ?? []
            compensations=(try? await loadedComp) ?? [];payrollProfiles=(try? await loadedProfiles) ?? []
            salaryComponentDefinitions=(try? await loadedDefinitions) ?? [];employeeSalaryComponents=(try? await loadedEmployeeComponents) ?? []
            payrollAdjustments=(try? await loadedAdjustments) ?? [];payrollItemComponents=(try? await loadedItemComponents) ?? []
            financialProfiles=(try? await loadedFinancial) ?? [];payrollLoans=(try? await loadedLoans) ?? [];payrollLoansHaveMore=payrollLoans.count==50
            reimbursements=(try? await loadedReimbursements) ?? [];reimbursementsHaveMore=reimbursements.count==50;statutoryRules=(try? await loadedStatutory) ?? []
            payslipDocuments=(try? await backend.payslipDocuments()) ?? [];payslipDocumentsHaveMore=payslipDocuments.count==50
            salarySummary=try? await backend.salarySummary(employeeId:role == .staff ? ownEmployee?.id:nil)
            if role.canManagePayroll || role.canApprovePayroll {
                salaryRules=(try? await backend.salaryRules()) ?? [];salaryFoodItems=(try? await backend.salaryFoodItems()) ?? [];salaryDisputes=(try? await backend.salaryDisputes()) ?? []
            }
        } catch { noticeMessage=payrollItems.isEmpty ? UserFacingError.message(for:error):"Payroll information could not be refreshed." }
    }

    func refreshWorkforceFeature() async {
        guard !workforceIsLoading,!refreshInProgress,isConnected,let branch=selectedBranch else{return}
        workforceIsLoading=true;defer{workforceIsLoading=false}
        let branchId=branch.id
        let start=ISODate.string(from:selectedDate)
        let end=ISODate.string(from:Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate)
        do {
            async let loadedShifts=backend.shifts(branchId:branchId,start:start,end:end)
            async let loadedSwaps=backend.shiftSwaps(branchId:branchId)
            async let loadedCorrections=backend.correctionRequests(branchId:branchId)
            async let loadedDocuments=backend.employeeDocuments()
            async let loadedLifecycle=backend.lifecycleTasks()
            async let loadedAssets=backend.employeeAssets()
            async let loadedAvailability=backend.availability(branchId:branchId)
            let nextShifts=try await loadedShifts
            guard branchId==selectedBranch?.id else{return}
            shifts=nextShifts;shiftsHaveMore=nextShifts.count==100;shiftSwaps=(try? await loadedSwaps) ?? []
            correctionRequests=(try? await loadedCorrections) ?? [];employeeDocuments=(try? await loadedDocuments) ?? [];employeeDocumentsHaveMore=employeeDocuments.count==50
            lifecycleTasks=(try? await loadedLifecycle) ?? [];employeeAssets=(try? await loadedAssets) ?? []
            employeeAvailability=(try? await loadedAvailability) ?? []
            scheduleTemplates=role.canManagePeople ? ((try? await backend.scheduleTemplates(branchId:branchId)) ?? []):[]
            kioskDevices=role.canManagePeople ? ((try? await backend.kioskDevices(branchId:branchId)) ?? []):[]
            if role.canManagePeople { salaryFoodItems=(try? await backend.salaryFoodItems()) ?? salaryFoodItems }
        } catch { noticeMessage=shifts.isEmpty ? UserFacingError.message(for:error):"Workforce information could not be refreshed." }
    }

    func loadOlderLeaves() async {
        guard leavesHaveMore,!olderLeaveIsLoading,isConnected,let branch=selectedBranch else{return}
        olderLeaveIsLoading=true;defer{olderLeaveIsLoading=false}
        do {
            let page=try await backend.leaves(branchId:branch.id,offset:leaves.count)
            leaves += page.filter{item in !leaves.contains(where:{$0.id==item.id})}
            leavesHaveMore=page.count==50
        } catch { noticeMessage="Older leave requests could not be loaded." }
    }

    func loadOlderPayrollRuns() async {
        guard payrollRunsHaveMore,!olderPayrollIsLoading,isConnected,let branch=selectedBranch else{return}
        olderPayrollIsLoading=true;defer{olderPayrollIsLoading=false}
        do {
            let page=try await backend.payrollRuns(branchId:branch.id,offset:payrollRuns.count)
            payrollRuns += page.filter{item in !payrollRuns.contains(where:{$0.id==item.id})}
            payrollRunsHaveMore=page.count==25
        } catch { noticeMessage="Older payroll runs could not be loaded." }
    }

    func loadOlderEmployeeDocuments() async {
        guard employeeDocumentsHaveMore,!olderDocumentsIsLoading,isConnected else{return}
        olderDocumentsIsLoading=true;defer{olderDocumentsIsLoading=false}
        do {
            let page=try await backend.employeeDocuments(offset:employeeDocuments.count)
            employeeDocuments += page.filter{item in !employeeDocuments.contains(where:{$0.id==item.id})}
            employeeDocumentsHaveMore=page.count==50
        } catch { noticeMessage="Older employee documents could not be loaded." }
    }

    func loadOlderPayrollOperations() async {
        guard (payrollLoansHaveMore || reimbursementsHaveMore || payslipDocumentsHaveMore),!olderLoansIsLoading,isConnected else{return}
        olderLoansIsLoading=true;defer{olderLoansIsLoading=false}
        do {
            let nextLoans:[PayrollLoan]=payrollLoansHaveMore ? try await backend.payrollLoans(offset:payrollLoans.count) : []
            let nextReimbursements:[PayrollReimbursement]=reimbursementsHaveMore ? try await backend.reimbursements(offset:reimbursements.count) : []
            let nextDocuments:[PayslipDocument]=payslipDocumentsHaveMore ? try await backend.payslipDocuments(offset:payslipDocuments.count) : []
            payrollLoans += nextLoans.filter{item in !payrollLoans.contains(where:{$0.id==item.id})}
            reimbursements += nextReimbursements.filter{item in !reimbursements.contains(where:{$0.id==item.id})}
            payslipDocuments += nextDocuments.filter{item in !payslipDocuments.contains(where:{$0.id==item.id})}
            if payrollLoansHaveMore { payrollLoansHaveMore=nextLoans.count==50 }
            if reimbursementsHaveMore { reimbursementsHaveMore=nextReimbursements.count==50 }
            if payslipDocumentsHaveMore { payslipDocumentsHaveMore=nextDocuments.count==50 }
        } catch { noticeMessage="Older payroll records could not be loaded." }
    }

    func refreshBranchSettingsFeature() async {
        guard !branchSettingsIsLoading,!refreshInProgress,isConnected,let currentBranch=selectedBranch else{return}
        branchSettingsIsLoading=true;defer{branchSettingsIsLoading=false}
        do {
            let nextBranches=try await backend.branches()
            guard nextBranches.contains(where:{$0.id==currentBranch.id}) else{return}
            branches=nextBranches
            branchIPRules=(try? await backend.branchIPRules(branchId:currentBranch.id)) ?? []
        } catch { noticeMessage="Branch settings could not be refreshed." }
    }

    /// Loads only the information needed by the Attendance tab. This keeps tab
    /// navigation responsive and avoids repeating the much larger app refresh.
    func refreshAttendanceScreen() async {
        guard isConnected, !refreshInProgress, selectedBranch != nil else { return }
        if attendanceIsLoading {
            attendanceRefreshPending=true
            return
        }
        attendanceIsLoading=true
        defer { attendanceIsLoading=false }
        repeat {
            attendanceRefreshPending=false
            guard let branch=selectedBranch else { return }
            let date=ISODate.string(from:selectedDate)
            do {
                // Keep these requests sequential. The shared backend client was
                // previously asked to run this screen refresh at the same time
                // as the app-wide refresh, which caused large request bursts on
                // device and could make iOS terminate the app under pressure.
                let loadedEmployees=try await backend.employees(branchId:branch.id)
                let loadedAttendance=try await backend.attendance(branchId:branch.id,date:date)
                guard branch.id == selectedBranch?.id else {
                    attendanceRefreshPending=true
                    continue
                }
                employees=loadedEmployees
                attendanceDays=loadedAttendance
                rebuildAttendancePresentation()
                // If the date changed while the request was in flight, immediately
                // load the new date instead of leaving mismatched attendance data.
                if date != ISODate.string(from:selectedDate) { attendanceRefreshPending=true }
            } catch {
                if employees.isEmpty && attendanceDays.isEmpty {
                    errorMessage=UserFacingError.message(for:error)
                } else {
                    noticeMessage="Attendance could not be refreshed. The latest saved information is still available."
                }
            }
        } while attendanceRefreshPending && isConnected && !refreshInProgress
    }

    /// Notifications and audit history are independent of the rest of the app.
    /// Loading them here prevents the Reports screen from waiting on payroll,
    /// schedules, documents, and other unrelated modules.
    func refreshOperationsCenter() async {
        guard !operationsIsLoading, !refreshInProgress, isConnected else { return }
        operationsIsLoading=true
        defer { operationsIsLoading=false }
        do {
            // Show notifications as soon as they arrive. Audit history is a
            // secondary owner-only section and must not hold the whole screen in
            // a loading state when its query is slower.
            notifications=try await backend.notifications()
            if role.isAdministrator, let branch=selectedBranch {
                do { auditEvents=try await backend.auditEvents(branchId:branch.id) }
                catch { noticeMessage="Audit history could not be refreshed. Notifications are still available." }
            }
        } catch {
            if notifications.isEmpty {
                errorMessage=UserFacingError.message(for:error)
            } else {
                noticeMessage="Updates could not be refreshed. The latest saved information is still available."
            }
        }
    }

    /// Never use `Dictionary(uniqueKeysWithValues:)` for server responses: one
    /// accidental duplicate otherwise raises a fatal Swift runtime trap. The
    /// most recently returned row wins and the UI remains usable while the data
    /// issue can be corrected separately.
    private func rebuildAttendancePresentation() {
        var employeeMap:[String:Employee]=[:]
        for employee in employees { employeeMap[employee.id]=employee }
        leaves=leaves.map { item in
            var value=item
            value.fullName=employeeMap[item.employeeId]?.fullName ?? "Employee"
            value.employeeCode=employeeMap[item.employeeId]?.employeeCode ?? ""
            return value
        }
        var attendanceMap:[String:AttendanceDay]=[:]
        for day in attendanceDays { attendanceMap[day.employeeId]=day }
        attendance=employees.filter{$0.employmentStatus=="active"}.map { employee in
            let day=attendanceMap[employee.id]
            return AttendanceRow(employeeId:employee.id,employeeCode:employee.employeeCode,fullName:employee.fullName,position:employee.position,employeeStatus:employee.employmentStatus,attendanceId:day?.id,attendanceStatus:day?.status,markSource:nil,notes:nil,checkInAt:day?.firstCheckInAt,checkOutAt:day?.lastCheckOutAt,updatedAt:nil)
        }
    }

    func appDidBecomeActive() async {
        guard currentUser != nil, !isDemo else { return }
        await syncOfflineAttendance()
        await flushDiagnostics()
        // Returning from Face ID, Control Centre, or another system sheet makes
        // the scene active again. A full refresh on every such transition used
        // to overlap tab-specific requests and was the main source of request
        // storms, long spinners, and device-only terminations.
        await refreshIfStale(minimumInterval:300)
    }

    private func refreshIfStale(minimumInterval:TimeInterval) async {
        if let lastSuccessfulFullRefreshAt,
           Date().timeIntervalSince(lastSuccessfulFullRefreshAt) < minimumInterval { return }
        await refreshSafely()
    }

    var ownEmployee:Employee? { guard let uid=currentUser?.id else{return nil}; return employees.first{$0.userId==uid} }

    func loadMoreEmployees() async {
        guard employeesHaveMore,let branch=selectedBranch else{return}
        await perform {
            let next=try await backend.employees(branchId:branch.id,offset:employees.count)
            let known=Set(employees.map(\.id))
            employees.append(contentsOf:next.filter{!known.contains($0.id)})
            employeesHaveMore=next.count == 100
        }
    }

    func loadMoreShifts() async {
        guard shiftsHaveMore,let branch=selectedBranch else{return}
        await perform {
            let end=Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate
            let next=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:end),offset:shifts.count)
            let known=Set(shifts.map(\.id))
            shifts.append(contentsOf:next.filter{!known.contains($0.id)})
            shiftsHaveMore=next.count == 100
        }
    }

    func loadSalaryLedger(employeeId:String?=nil,reset:Bool=true) async {
        if isDemo { return }
        guard !salaryLedgerIsLoading else{return};salaryLedgerIsLoading=true;defer{salaryLedgerIsLoading=false}
        do {
            let before=reset ? nil:salaryLedger.last
            let page=try await backend.salaryLedgerPage(employeeId:employeeId,filter:salaryLedgerFilter,before:before)
            if reset { salaryLedger=page } else { let known=Set(salaryLedger.map(\.id));salaryLedger.append(contentsOf:page.filter{!known.contains($0.id)}) }
            salaryLedgerHasMore=page.first?.hasMore ?? false
            salarySummary=try? await backend.salarySummary(employeeId:employeeId)
        } catch { AppDiagnostics.shared.capture(error:error,category:"salary-ledger",screen:"Salary Details");errorMessage=UserFacingError.message(for:error) }
    }

    func loadAttendanceHistory(employeeId:String?=nil,reset:Bool=true) async {
        if isDemo { attendanceHistory=[];attendanceHistoryHasMore=false;return }
        guard let branch=selectedBranch,isConnected else{return}
        if !reset && attendanceHistoryIsLoading { return }
        if reset { attendanceHistoryGeneration=UUID() }
        let generation=attendanceHistoryGeneration
        attendanceHistoryIsLoading=true
        defer{if generation==attendanceHistoryGeneration{attendanceHistoryIsLoading=false}}
        do {
            let target=employeeId ?? (role == .staff ? ownEmployee?.id:nil)
            let offset=reset ? 0:attendanceHistory.count
            let page=try await backend.attendanceHistory(employeeId:target,branchId:branch.id,filter:attendanceHistoryFilter,offset:offset)
            guard generation==attendanceHistoryGeneration,branch.id==selectedBranch?.id else{return}
            if reset { attendanceHistory=page }
            else { let known=Set(attendanceHistory.map(\.id));attendanceHistory.append(contentsOf:page.filter{!known.contains($0.id)}) }
            attendanceHistoryHasMore=page.first?.hasMore ?? false
        } catch {
            AppDiagnostics.shared.capture(error:error,category:"attendance-history",screen:"Attendance History")
            errorMessage=UserFacingError.message(for:error)
        }
    }

    func loadWorkforceReport(filter:WorkforceReportFilter,reset:Bool=true) async {
        if isDemo { workforceReportRows=[];workforceReportHasMore=false;return }
        guard let branch=selectedBranch,isConnected else{return}
        if !reset && workforceReportIsLoading { return }
        if reset { workforceReportGeneration=UUID() }
        let generation=workforceReportGeneration
        workforceReportIsLoading=true
        defer{if generation==workforceReportGeneration{workforceReportIsLoading=false}}
        do {
            let offset=reset ? 0:workforceReportRows.count
            let page=try await backend.workforceReportPage(branchId:branch.id,filter:filter,offset:offset)
            guard generation==workforceReportGeneration,branch.id==selectedBranch?.id else{return}
            if reset { workforceReportRows=page }
            else { let known=Set(workforceReportRows.map(\.id));workforceReportRows.append(contentsOf:page.filter{!known.contains($0.id)}) }
            workforceReportHasMore=page.first?.hasMore ?? false
        } catch {
            AppDiagnostics.shared.capture(error:error,category:"reports",screen:"Advanced Reports")
            errorMessage=UserFacingError.message(for:error)
        }
    }

    func completeWorkforceReport(filter:WorkforceReportFilter) async -> [WorkforceReportRow] {
        if isDemo { return workforceReportRows }
        guard let branch=selectedBranch,isConnected else{return []}
        var rows:[WorkforceReportRow]=[]
        do {
            while rows.count < 5_000 {
                let page=try await backend.workforceReportPage(branchId:branch.id,filter:filter,offset:rows.count,limit:500)
                let known=Set(rows.map(\.id))
                rows.append(contentsOf:page.filter{!known.contains($0.id)})
                if page.isEmpty || page.first?.hasMore != true { break }
            }
            return rows
        } catch {
            AppDiagnostics.shared.capture(error:error,category:"report-export",screen:"Advanced Reports")
            errorMessage=UserFacingError.message(for:error)
            return []
        }
    }

    func loadOperationsHealth() async {
        if isDemo {
            operationsHealth=OperationsHealth(backendOk:true,generatedAt:ISO8601DateFormatter().string(from:.now),activeEmployees:employees.count,activeIPRules:1,missingFaceEnrollments:0,missingSchedules:0,missingCompensations:0,pendingPushNotifications:0,failedPushNotifications:0,attendanceRejections7d:0,crashes7d:0,errors7d:0,missingBranchLocation:false,lastCrashAt:nil,lastPushSentAt:nil,lastAttendanceAt:nil,topRejectionReasons:[])
            return
        }
        guard role == .owner,let branch=selectedBranch,isConnected else{return}
        operationsHealthGeneration=UUID()
        let generation=operationsHealthGeneration
        operationsHealthIsLoading=true
        defer{if generation==operationsHealthGeneration{operationsHealthIsLoading=false}}
        do {
            let health=try await backend.operationsHealth(branchId:branch.id)
            guard generation==operationsHealthGeneration,branch.id==selectedBranch?.id else{return}
            operationsHealth=health
        }
        catch {
            AppDiagnostics.shared.capture(error:error,category:"operations-health",screen:"Operations Health")
            errorMessage=UserFacingError.message(for:error)
        }
    }

    func loadDiagnosticFeed(reset:Bool=true) async {
        if isDemo { diagnosticEvents=[];diagnosticEventsHaveMore=false;return }
        guard role == .owner,let branch=selectedBranch,isConnected else{return}
        if !reset && diagnosticEventsIsLoading{return}
        if reset{diagnosticFeedGeneration=UUID()}
        let generation=diagnosticFeedGeneration
        diagnosticEventsIsLoading=true
        defer{if generation==diagnosticFeedGeneration{diagnosticEventsIsLoading=false}}
        do {
            let page=try await backend.diagnosticFeed(branchId:branch.id,severity:diagnosticSeverity,offset:reset ? 0:diagnosticEvents.count)
            guard generation==diagnosticFeedGeneration,branch.id==selectedBranch?.id else{return}
            if reset{diagnosticEvents=page}else{let known=Set(diagnosticEvents.map(\.id));diagnosticEvents.append(contentsOf:page.filter{!known.contains($0.id)})}
            diagnosticEventsHaveMore=page.first?.hasMore ?? false
        } catch { AppDiagnostics.shared.capture(error:error,category:"diagnostic-feed",screen:"Diagnostics");errorMessage=UserFacingError.message(for:error) }
    }

    func loadFailedPushNotifications(reset:Bool=true) async {
        if isDemo { failedPushNotifications=[];failedPushNotificationsHaveMore=false;return }
        guard role == .owner,let branch=selectedBranch,isConnected else{return}
        if !reset && failedPushNotificationsIsLoading{return}
        if reset{failedPushGeneration=UUID()}
        let generation=failedPushGeneration
        failedPushNotificationsIsLoading=true
        defer{if generation==failedPushGeneration{failedPushNotificationsIsLoading=false}}
        do {
            let page=try await backend.failedPushNotifications(branchId:branch.id,offset:reset ? 0:failedPushNotifications.count)
            guard generation==failedPushGeneration,branch.id==selectedBranch?.id else{return}
            if reset{failedPushNotifications=page}else{let known=Set(failedPushNotifications.map(\.id));failedPushNotifications.append(contentsOf:page.filter{!known.contains($0.id)})}
            failedPushNotificationsHaveMore=page.first?.hasMore ?? false
        } catch { AppDiagnostics.shared.capture(error:error,category:"push-recovery",screen:"Notification Recovery");errorMessage=UserFacingError.message(for:error) }
    }

    func retryFailedPushNotification(_ notification:FailedPushNotification) async {
        guard role == .owner,let branch=selectedBranch,!notificationRetryIsWorking else{return}
        notificationRetryIsWorking=true;defer{notificationRetryIsWorking=false}
        do {
            guard try await backend.retryFailedPushNotification(branchId:branch.id,notificationId:notification.id) else{throw BackendError.invalidInput("This notification is no longer waiting for delivery.")}
            failedPushNotifications.removeAll{$0.id==notification.id}
            successMessage="Notification queued. Delivery will retry within one minute."
            await loadOperationsHealth()
        } catch { AppDiagnostics.shared.capture(error:error,category:"push-retry",screen:"Notification Recovery");errorMessage=UserFacingError.message(for:error) }
    }

    func retryAllFailedPushNotifications() async {
        guard role == .owner,let branch=selectedBranch,!notificationRetryIsWorking else{return}
        notificationRetryIsWorking=true;defer{notificationRetryIsWorking=false}
        do {
            let count=try await backend.retryAllFailedPushNotifications(branchId:branch.id)
            failedPushNotifications=[];failedPushNotificationsHaveMore=false
            successMessage=count==0 ? "No failed notifications need retrying.":"\(count) notification(s) queued. Delivery will retry within one minute."
            await loadOperationsHealth()
        } catch { AppDiagnostics.shared.capture(error:error,category:"push-retry-all",screen:"Notification Recovery");errorMessage=UserFacingError.message(for:error) }
    }

    func saveEmployee(_ draft:EmployeeDraft) async -> Bool {
        await performReturning {
            guard let org=organizationId,let branch=selectedBranch?.id else{throw BackendError.noBranch}
            let cnicDigits=CNICFormatter.digits(from:draft.cnic)
            if let duplicate=employees.first(where:{$0.id != draft.id && CNICFormatter.digits(from:$0.cnic ?? "")==cnicDigits}) {
                throw BackendError.invalidInput("This CNIC already belongs to \(duplicate.employeeCode) — \(duplicate.fullName). Use the employee's own CNIC or edit the existing record.")
            }
            let employeeCode=draft.employeeCode.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
            if let duplicate=employees.first(where:{$0.id != draft.id && $0.employeeCode.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()==employeeCode}) {
                throw BackendError.invalidInput("Employee code \(employeeCode) already belongs to \(duplicate.fullName). Enter a unique employee code.")
            }
            try await backend.saveEmployee(draft,organizationId:org,branchId:branch); await refreshPeopleFeature(); successMessage=draft.id==nil ? "Employee added.":"Employee updated."; return true
        } fallback:{false}
    }
    func setEmployeeStatus(_ employee:Employee,status:String,reason:String) async -> Bool { await performReturning{try await backend.setEmployeeStatus(id:employee.id,status:status,reason:reason);await refreshPeopleFeature();successMessage="Employee \(status).";return true}fallback:{false} }
    func assignEmployee(_ employee:Employee,to branch:Branch,isPrimary:Bool,startsOn:Date) async -> Bool { await performReturning{try await backend.assignEmployeeBranch(employeeId:employee.id,branchId:branch.id,isPrimary:isPrimary,startsOn:startsOn);await refreshPeopleFeature();successMessage="Branch assignment saved.";return true}fallback:{false} }
    func endAssignment(_ assignment:EmployeeBranchAssignment,reason:String) async { await perform{try await backend.endEmployeeBranchAssignment(id:assignment.id,reason:reason);await refreshPeopleFeature();successMessage="Branch assignment ended."} }
    func submitLeave(_ draft:LeaveDraft) async -> Bool {
        await performReturning {
            guard let org=organizationId,let branch=selectedBranch?.id else{throw BackendError.noBranch}
            let employeeId = role.isAdministrator ? draft.employeeId : (ownEmployee?.id ?? "")
            guard !employeeId.isEmpty else{throw BackendError.noEmployeeProfile}
            try await backend.submitLeave(draft,organizationId:org,branchId:branch,employeeId:employeeId); await refreshLeaveFeature(); successMessage="Leave request submitted."; return true
        } fallback:{false}
    }
    func reviewLeave(_ leave:LeaveRecord,status:String) async { await perform{try await backend.reviewLeave(id:leave.id,status:status,note:nil);await refreshLeaveFeature();successMessage="Leave request \(status)."} }
    func cancelLeave(_ leave:LeaveRecord,reason:String) async { await perform{try await backend.cancelLeave(id:leave.id,reason:reason);await refreshLeaveFeature();successMessage="Leave cancelled."} }
    func updateLeaveType(_ type:LeaveType,isPaid:Bool,annualDays:Double,requiresDocument:Bool,requiresReason:Bool,accrualMethod:String,carryForwardDays:Double,attachmentAfterDays:Double?) async -> Bool { await performReturning{try await backend.updateLeaveType(type,isPaid:isPaid,annualDays:annualDays,requiresDocument:requiresDocument,requiresReason:requiresReason,accrualMethod:accrualMethod,carryForwardDays:carryForwardDays,attachmentAfterDays:attachmentAfterDays);await refreshLeaveFeature();successMessage="\(type.name) policy updated.";return true}fallback:{false} }
    func addHoliday(name:String,date:Date,allBranches:Bool,isPaid:Bool) async ->Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveHoliday(organizationId:org,branchId:allBranches ? nil:selectedBranch?.id,name:name,date:date,isPaid:isPaid);await refreshLeaveFeature();successMessage="Holiday added.";return true}fallback:{false} }
    func addLeaveBlackout(start:Date,end:Date,reason:String,allBranches:Bool) async ->Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveLeaveBlackout(organizationId:org,branchId:allBranches ? nil:selectedBranch?.id,start:start,end:end,reason:reason);await refreshLeaveFeature();successMessage="Leave blackout added.";return true}fallback:{false} }
    func setSalary(employeeId:String,rupees:Double,effectiveFrom:Date) async { await perform{guard let org=organizationId else{throw BackendError.noMembership};try await backend.setCompensation(employeeId:employeeId,organizationId:org,monthlyRupees:rupees,effectiveFrom:effectiveFrom);await refreshPayrollFeature();successMessage="Salary version saved."} }
    func configurePayroll(employee:Employee,rupees:Double,effectiveFrom:Date,payDay:Int,cutoffDay:Int,workWeek:String) async -> Bool { await performReturning{guard let org=organizationId,let branch=selectedBranch?.id else{throw BackendError.noBranch};try await backend.setCompensation(employeeId:employee.id,organizationId:org,monthlyRupees:rupees,effectiveFrom:effectiveFrom);try await backend.setPayrollProfile(employeeId:employee.id,payDay:payDay,cutoffDay:cutoffDay,effectiveFrom:effectiveFrom);try await backend.setWorkWeek(employeeId:employee.id,organizationId:org,branchId:branch,employeeCode:employee.employeeCode,pattern:workWeek,effectiveFrom:effectiveFrom);await refreshPayrollFeature();successMessage="Salary, pay dates and work week saved.";return true}fallback:{false} }
    func createPayroll(title:String,start:Date,end:Date) async { await perform{guard let org=organizationId,let user=currentUser else{throw BackendError.noMembership};let run=try await backend.createPayroll(organizationId:org,branchId:selectedBranch?.id,title:title,start:start,end:end,preparedBy:user.id);_ = try await backend.preparePayroll(id:run.id);_ = try await backend.applyPayrollOperations(id:run.id);_ = try await backend.applyStatutoryRules(id:run.id);_ = try await backend.applySalaryLedger(payrollId:run.id);await refreshPayrollFeature();successMessage="Payroll draft prepared with approved salary transactions."} }
    func transitionPayroll(_ run:PayrollRun,to status:String) async { await perform{try await backend.transitionPayroll(id:run.id,status:status);if status=="locked"{try await backend.generatePayslips(runId:run.id)};await refreshPayrollFeature();successMessage=status=="locked" ? "Payroll locked and secure payslips generated.":"Payroll \(status)."} }
    func downloadPayslip(_ document:PayslipDocument) async ->URL? { await performReturning{try await backend.downloadPayslip(document)}fallback:{nil} }
    func recordPayment(item:PayrollItem,amount:Double,method:String,reference:String,date:Date) async { await perform{try await backend.recordPayment(itemId:item.id,amountRupees:amount,method:method,reference:reference,paidOn:date);await refreshPayrollFeature();successMessage="Salary payment recorded."} }
    func addPayrollAdjustment(employeeId:String,type:String,label:String,amount:Double,reason:String) async -> Bool { await performReturning{guard let org=organizationId,let user=currentUser else{throw BackendError.noMembership};try await backend.createAdjustment(organizationId:org,employeeId:employeeId,type:type,label:label,rupees:amount,reason:reason,userId:user.id);await refreshPayrollFeature();successMessage="Payroll adjustment added.";return true}fallback:{false} }
    func addSalaryComponent(employeeId:String,name:String,type:String,amount:Double,effectiveFrom:Date) async -> Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveSalaryComponent(organizationId:org,employeeId:employeeId,name:name,type:type,rupees:amount,effectiveFrom:effectiveFrom);await refreshPayrollFeature();successMessage="Salary component saved.";return true}fallback:{false} }
    func saveSalaryRule(_ draft:SalaryRuleDraft) async ->Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveSalaryRule(organizationId:org,branchId:draft.scopeType=="branch" ? selectedBranch?.id:nil,draft:draft);salaryRules=try await backend.salaryRules();successMessage="Salary rule saved.";return true}fallback:{false} }
    func saveFoodItem(name:String,unit:String,price:Double,effectiveFrom:Date) async ->Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveSalaryFoodItem(organizationId:org,branchId:selectedBranch?.id,name:name,unit:unit,price:price,effectiveFrom:effectiveFrom);salaryFoodItems=try await backend.salaryFoodItems();successMessage="Food item saved.";return true}fallback:{false} }
    func addSalaryTransaction(employeeId:String,rule:SalaryTransactionRule?,type:String,category:String,label:String,description:String,amount:Double,date:Date) async ->Bool { await performReturning{_ = try await backend.createSalaryTransaction(employeeId:employeeId,branchId:selectedBranch?.id,ruleId:rule?.id,type:type,category:category,label:label,description:description,amount:amount,date:date);await loadSalaryLedger(employeeId:employeeId);successMessage="Salary transaction added.";return true}fallback:{false} }
    func addFoodCharge(employeeId:String,item:SalaryFoodItem,quantity:Double,date:Date,note:String) async ->Bool { await performReturning{_ = try await backend.recordSalaryFoodCharge(employeeId:employeeId,foodItemId:item.id,quantity:quantity,date:date,note:note);await loadSalaryLedger(employeeId:employeeId);successMessage="Food charge added for approval.";return true}fallback:{false} }
    func reviewSalaryTransaction(_ item:SalaryLedgerTransaction,status:String,note:String) async { await perform{_ = try await backend.reviewSalaryTransaction(id:item.id,status:status,note:note);await loadSalaryLedger(employeeId:item.employeeId);salaryDisputes=(try? await backend.salaryDisputes()) ?? [];successMessage="Salary transaction \(status)."} }
    func disputeSalaryTransaction(_ item:SalaryLedgerTransaction,reason:String) async ->Bool { await performReturning{_ = try await backend.disputeSalaryTransaction(id:item.id,reason:reason);await loadSalaryLedger(employeeId:item.employeeId);successMessage="Dispute submitted.";return true}fallback:{false} }
    func resolveSalaryDispute(_ dispute:SalaryTransactionDispute,status:String,note:String) async { await perform{_ = try await backend.resolveSalaryDispute(id:dispute.id,status:status,note:note);salaryDisputes=(try? await backend.salaryDisputes()) ?? [];successMessage="Dispute \(status)."} }
    func reverseSalaryTransaction(_ item:SalaryLedgerTransaction,reason:String) async ->Bool { await performReturning{_ = try await backend.reverseSalaryTransaction(id:item.id,reason:reason);await loadSalaryLedger(employeeId:item.employeeId);successMessage="Reversal recorded.";return true}fallback:{false} }
    func salaryEvents(for item:SalaryLedgerTransaction) async->[SalaryTransactionEvent] { await performReturning{try await backend.salaryEvents(transactionId:item.id)}fallback:{[]} }
    func saveShift(employeeId:String,date:Date,start:Date,end:Date,breakMinutes:Int,notes:String,weeks:Int=1) async -> Bool { await performReturning{guard let org=organizationId,let branch=selectedBranch else{throw BackendError.noBranch};try await backend.saveRecurringShifts(organizationId:org,branchId:branch.id,employeeId:employeeId,date:date,start:start,end:end,breakMinutes:breakMinutes,notes:notes,weeks:weeks);shifts=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:Calendar.current.date(byAdding:.day,value:max(35,weeks*7),to:selectedDate) ?? selectedDate));successMessage=weeks>1 ? "\(weeks) weekly shifts saved.":"Shift saved.";return true}fallback:{false} }
    func updateShift(id:String,employeeId:String,date:Date,start:Date,end:Date,breakMinutes:Int,notes:String) async -> Bool { await performReturning{guard let org=organizationId,let branch=selectedBranch else{throw BackendError.noBranch};try await backend.updateShift(id:id,organizationId:org,branchId:branch.id,employeeId:employeeId,date:date,start:start,end:end,breakMinutes:breakMinutes,notes:notes);shifts=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate));successMessage="Shift updated and returned to draft.";return true}fallback:{false} }
    func cancelShift(_ entry:ShiftRosterEntry) async { await perform{try await backend.cancelShift(id:entry.id);if let branch=selectedBranch{shifts=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate))};successMessage="Shift cancelled."} }
    func saveAvailability(employeeId:String,weekday:Int,isAvailable:Bool,from:Date,until:Date,note:String) async -> Bool { await performReturning{guard let org=organizationId,let branch=selectedBranch else{throw BackendError.noBranch};try await backend.saveAvailability(organizationId:org,branchId:branch.id,employeeId:employeeId,weekday:weekday,isAvailable:isAvailable,from:from,until:until,note:note);employeeAvailability=try await backend.availability(branchId:branch.id);successMessage="Availability saved.";return true}fallback:{false} }
    func copyRoster(sourceStart:Date,targetStart:Date) async -> Bool { await performReturning{guard let branch=selectedBranch else{throw BackendError.noBranch};let count=try await backend.copyRoster(branchId:branch.id,sourceStart:sourceStart,targetStart:targetStart);shifts=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate));successMessage="Copied \(count) shifts.";return true}fallback:{false} }
    func publishRoster(weekStart:Date) async -> Bool { await performReturning{guard let branch=selectedBranch else{throw BackendError.noBranch};let count=try await backend.publishRoster(branchId:branch.id,weekStart:weekStart);shifts=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate));successMessage="Published \(count) shifts.";return true}fallback:{false} }
    func requestShiftSwap(_ entry:ShiftRosterEntry,targetEmployeeId:String?,reason:String) async -> Bool { await performReturning{guard let org=organizationId,let employee=ownEmployee else{throw BackendError.noEmployeeProfile};try await backend.requestShiftSwap(organizationId:org,entry:entry,employeeId:employee.id,targetEmployeeId:targetEmployeeId,reason:reason);shiftSwaps=try await backend.shiftSwaps(branchId:entry.branchId);successMessage="Shift swap requested.";return true}fallback:{false} }
    func reviewShiftSwap(_ request:ShiftSwapRequest,status:String,note:String="") async { await perform{try await backend.reviewShiftSwap(id:request.id,status:status,note:note);guard let branch=selectedBranch else{return};shiftSwaps=try await backend.shiftSwaps(branchId:branch.id);shifts=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate));successMessage="Shift swap \(status)."} }
    func requestAttendanceCorrection(date:Date,checkIn:Date?,checkOut:Date?,reason:String) async -> Bool { await performReturning{guard let org=organizationId,let branch=selectedBranch,let employee=ownEmployee else{throw BackendError.noEmployeeProfile};try await backend.submitAttendanceCorrection(organizationId:org,branchId:branch.id,employeeId:employee.id,date:date,checkIn:checkIn,checkOut:checkOut,reason:reason);correctionRequests=try await backend.correctionRequests(branchId:branch.id);successMessage="Correction request submitted.";return true}fallback:{false} }
    func reviewAttendanceCorrection(_ request:AttendanceCorrectionRequest,status:String,note:String) async { await perform{try await backend.reviewAttendanceCorrection(id:request.id,status:status,note:note);guard let branch=selectedBranch else{return};correctionRequests=try await backend.correctionRequests(branchId:branch.id);attendanceDays=try await backend.attendance(branchId:branch.id,date:ISODate.string(from:selectedDate));successMessage="Correction request \(status)."} }
    func uploadEmployeeDocument(employeeId:String,type:String,title:String,fileURL:URL,expiresOn:Date?) async -> Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.uploadEmployeeDocument(organizationId:org,employeeId:employeeId,type:type,title:title,fileURL:fileURL,expiresOn:expiresOn);employeeDocuments=try await backend.employeeDocuments();employeeDocumentsHaveMore=employeeDocuments.count==50;successMessage="Employee document uploaded securely.";return true}fallback:{false} }
    func downloadEmployeeDocument(_ document:EmployeeDocument) async -> URL? { await performReturning{try await backend.downloadEmployeeDocument(document)}fallback:{nil} }
    func saveFinancialProfile(employeeId:String,bank:String,accountTitle:String,iban:String,taxNumber:String,eobiNumber:String,tax:Double,eobi:Double) async -> Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveFinancialProfile(organizationId:org,employeeId:employeeId,bank:bank,accountTitle:accountTitle,iban:iban,taxNumber:taxNumber,eobiNumber:eobiNumber,tax:tax,eobi:eobi);financialProfiles=try await backend.financialProfiles();successMessage="Bank and statutory payroll details saved.";return true}fallback:{false} }
    func createPayrollLoan(employeeId:String,label:String,principal:Double,installment:Double,start:Date) async -> Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.createPayrollLoan(organizationId:org,employeeId:employeeId,label:label,principal:principal,installment:installment,start:start);payrollLoans=try await backend.payrollLoans();payrollLoansHaveMore=payrollLoans.count==50;successMessage="Salary loan added.";return true}fallback:{false} }
    func addStatutoryRule(code:String,name:String,type:String,value:Double,effectiveFrom:Date) async ->Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveStatutoryRule(organizationId:org,code:code,name:name,type:type,value:value,effectiveFrom:effectiveFrom);statutoryRules=try await backend.statutoryRules(organizationId:org);successMessage="Statutory payroll rule saved.";return true}fallback:{false} }
    func submitReimbursement(label:String,amount:Double,date:Date,reason:String,employeeId:String?=nil) async -> Bool { await performReturning{guard let org=organizationId,let employee=employeeId ?? ownEmployee?.id else{throw BackendError.noEmployeeProfile};try await backend.submitReimbursement(organizationId:org,employeeId:employee,label:label,amount:amount,date:date,reason:reason);reimbursements=try await backend.reimbursements();reimbursementsHaveMore=reimbursements.count==50;successMessage="Reimbursement submitted.";return true}fallback:{false} }
    func reviewReimbursement(_ item:PayrollReimbursement,status:String) async { await perform{try await backend.reviewReimbursement(id:item.id,status:status);reimbursements=try await backend.reimbursements();reimbursementsHaveMore=reimbursements.count==50;successMessage="Reimbursement \(status)."} }
    func saveBranch(_ branch:Branch) async { await perform{try await backend.updateBranch(branch);await refreshBranchSettingsFeature();successMessage="Branch settings saved."} }
    func createBranch(name:String,code:String,address:String) async -> Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.createBranch(organizationId:org,name:name,code:code,address:address);await refreshBranchSettingsFeature();successMessage="Branch created.";return true}fallback:{false} }
    func setBranchActive(_ branch:Branch,isActive:Bool) async { await perform{try await backend.setBranchActive(id:branch.id,isActive:isActive);await refreshBranchSettingsFeature();successMessage=isActive ? "Branch activated.":"Branch deactivated."} }
    func addIPRule(label:String,network:String) async { await perform{guard let branch=selectedBranch,let user=currentUser else{throw BackendError.noBranch};try await backend.addIPRule(branchId:branch.id,label:label,network:network,userId:user.id);await refreshBranchSettingsFeature();successMessage="Approved Wi-Fi IP added."} }
    func setIPRuleActive(_ rule:BranchIPRule,isActive:Bool) async { await perform{try await backend.setIPRuleActive(id:rule.id,isActive:isActive);await refreshBranchSettingsFeature();successMessage="Wi-Fi rule updated."} }
    func diagnoseNetwork() async { await perform{guard let branch=selectedBranch else{throw BackendError.noBranch};let result=try await backend.networkDiagnostic(branchId:branch.id);observedPublicIP=result.observedIp;successMessage=result.observedIp.map{"Public IP: \($0)"} ?? "No public IP detected."} }
    func createInvite(employeeId:String,email:String) async { await perform{generatedInviteCode=try await backend.createEmployeeInvite(employeeId:employeeId,email:email);successMessage="Invite code created."} }
    func claimInvite(code:String) async -> Bool { await performReturning{try await backend.claimEmployeeInvite(code:code);try await refresh();successMessage="Account linked to your employee record.";return true}fallback:{false} }
    func registerCurrentDeviceAsKiosk(name:String) async ->Bool { await performReturning{guard let branch=selectedBranch else{throw BackendError.noBranch};_ = try await backend.registerKiosk(branchId:branch.id,name:name);kioskDevices=try await backend.kioskDevices(branchId:branch.id);successMessage="This iPhone is ready for branch kiosk attendance.";return true}fallback:{false} }
    func deactivateKiosk(_ kiosk:BranchKioskDevice) async { await perform{try await backend.deactivateKiosk(id:kiosk.id);if let branch=selectedBranch{kioskDevices=try await backend.kioskDevices(branchId:branch.id)};successMessage="Kiosk access removed."} }
    func saveScheduleTemplate(_ template:ScheduleTemplate) async ->Bool { await performReturning{try await backend.saveScheduleTemplate(template);if let branch=selectedBranch{scheduleTemplates=try await backend.scheduleTemplates(branchId:branch.id)};successMessage="Schedule template saved.";return true}fallback:{false} }
    func assignSchedule(employeeId:String,templateId:String,effectiveFrom:Date) async ->Bool { await performReturning{try await backend.assignSchedule(employeeId:employeeId,templateId:templateId,effectiveFrom:effectiveFrom);successMessage="Schedule assigned.";return true}fallback:{false} }
    func bulkImportStaff(rows:[[String:String]]) async ->Bool { await performReturning{guard let branch=selectedBranch else{throw BackendError.noBranch};let result=try await backend.bulkImport(branchId:branch.id,rows:rows);await refreshPeopleFeature();successMessage="Import complete: \(result.created) added, \(result.updated) updated, \(result.assigned) assigned.";return true}fallback:{false} }
    func faceStatus(employeeId:String) async -> FaceTemplateStatus? {
        await performReturning { try await backend.faceStatus(employeeId:employeeId) } fallback: { nil }
    }
    func enrollFace(employeeId:String,descriptors:[[Float]],liveness:BiometricLivenessEvidence) async -> Bool {
        await performReturning {
            _ = try await backend.enrollFace(employeeId:employeeId,descriptors:descriptors,liveness:liveness)
            successMessage="Employee face enrolled securely."
            return true
        } fallback:{false}
    }
    func verifyFace(descriptors:[[Float]],challenge:BiometricChallenge,liveness:BiometricLivenessEvidence,kioskEmployeeId:String?=nil) async -> String? {
        await performReturning {
            guard let branch=selectedBranch else{throw BackendError.noBranch}
            let result=try await backend.verifyFace(branchId:branch.id,deviceId:DeviceIdentity.value,descriptors:descriptors,challenge:challenge,liveness:liveness,kioskEmployeeId:kioskEmployeeId)
            guard result.matched,let proof=result.proofId else{throw BackendError.invalidInput(FaceVerificationMessage.forReason(result.reason))}
            return proof
        } fallback:{nil}
    }
    func revokeFace(employeeId:String,reason:String) async -> Bool {
        await performReturning {
            _ = try await backend.revokeFace(employeeId:employeeId,reason:reason)
            successMessage="Employee face enrollment removed."
            return true
        } fallback:{false}
    }
    func markAttendance(eventType:String,location:LocationSnapshot?,biometricProofId:String?=nil,overrideEmployeeId:String?=nil,overrideReason:String?=nil,managerPassword:String?=nil,kioskEmployeeId:String?=nil) async -> Bool {
        await performReturning {
            guard let branch=selectedBranch else{throw BackendError.noBranch}
            let response=try await backend.markAttendance(AttendanceFunctionRequest(requestId:UUID().uuidString,branchId:branch.id,eventType:eventType,deviceId:DeviceIdentity.value,latitude:location?.latitude,longitude:location?.longitude,gpsAccuracyM:location?.accuracy,biometricProofId:biometricProofId,overrideEmployeeId:overrideEmployeeId,overrideReason:overrideReason,managerPassword:managerPassword,kioskEmployeeId:kioskEmployeeId,isSimulated:location?.isSimulated ?? false,isProducedByAccessory:location?.isProducedByAccessory ?? false))
            guard response.accepted else{throw BackendError.invalidInput(AttendanceMessage.forCode(response.rejectionCode))}
            await refreshAttendanceScreen(); successMessage=["check_in":"Checked in successfully.","break_start":"Break started.","break_end":"Break ended.","check_out":"Checked out successfully."][eventType] ?? "Attendance recorded."; return true
        } fallback:{false}
    }
    func queueOfflineAttendance(eventType:String,location:LocationSnapshot,challenge:BiometricChallenge,descriptors:[[Float]]) async -> Bool {
        await performReturning {
            guard let branch=selectedBranch else{throw BackendError.noBranch}
            guard !location.isSimulated && !location.isProducedByAccessory else{throw BackendError.invalidInput("A trusted iPhone location is required.")}
            let summary=FaceEmbeddingMath.robustSummary(descriptors)
            let evidence=try await AttendanceEvidenceVault.shared.prepare(branchId:branch.id,eventType:eventType,deviceId:DeviceIdentity.value,capturedAt:.now,location:location,challengeAction:challenge.action,descriptor:summary.descriptor)
            try await AttendanceEvidenceVault.shared.enqueue(evidence)
            offlineAttendanceCount=await AttendanceEvidenceVault.shared.count()
            successMessage="Attendance saved securely and will sync when internet returns."
            return true
        } fallback:{false}
    }
    func syncOfflineAttendance() async {
        let pending=(try? await AttendanceEvidenceVault.shared.pending()) ?? []
        guard !pending.isEmpty else{offlineAttendanceCount=0;offlineSyncMessage=nil;return}
        guard isConnected else { offlineSyncMessage="Waiting for an internet connection.";return }
        var failed=0
        for evidence in pending {
            do { let response=try await backend.syncOfflineAttendance(evidence);if response.accepted{try await AttendanceEvidenceVault.shared.remove(id:evidence.requestId)} }
            catch { failed += 1 }
        }
        offlineAttendanceCount=await AttendanceEvidenceVault.shared.count()
        if offlineAttendanceCount==0 { offlineSyncMessage=nil;await refreshAttendanceScreen();successMessage="Offline attendance synchronized." }
        else if failed>0 { offlineSyncMessage="\(offlineAttendanceCount) attendance record(s) could not sync yet. They remain encrypted on this iPhone." }
    }
    func markAttendance(row:AttendanceRow,status:String,notes:String) async -> Bool { errorMessage="Use the verified check-in or manager override flow."; return false }
    func removeFaceProfile(employeeId:String) async { _ = await revokeFace(employeeId:employeeId,reason:"Removed by manager from employee profile") }
    func correctAttendance(id:String,checkIn:Date?,checkOut:Date?,status:String,reason:String) async -> Bool { await performReturning{try await backend.correctAttendance(id:id,checkIn:checkIn,checkOut:checkOut,status:status,reason:reason);await refreshAttendanceScreen();successMessage="Attendance corrected.";return true}fallback:{false} }
    func updateAccount(name:String,phone:String) async -> Bool { await performReturning{try await backend.updateProfile(name:name,phone:phone);if let user=currentUser{access = .authenticated(AdminUser(id:user.id,fullName:name,email:user.email,role:user.role))};successMessage="Account updated.";return true}fallback:{false} }
    func markNotificationRead(_ notification:AppNotification) async { await perform{try await backend.markNotificationRead(id:notification.id);if let index=notifications.firstIndex(where:{$0.id==notification.id}){notifications[index].isRead=true}} }
    func markAllNotificationsRead() async { await perform{try await backend.markAllNotificationsRead();for index in notifications.indices{notifications[index].isRead=true}} }
    func loadMoreNotifications() async { let next=(try? await backend.notifications(offset:notifications.count)) ?? [];let known=Set(notifications.map(\.id));notifications.append(contentsOf:next.filter{!known.contains($0.id)}) }
    func loadMoreAuditEvents() async { guard role.isAdministrator,let branch=selectedBranch else{return};let next=(try? await backend.auditEvents(branchId:branch.id,offset:auditEvents.count)) ?? [];let known=Set(auditEvents.map(\.id));auditEvents.append(contentsOf:next.filter{!known.contains($0.id)}) }
    func saveNotificationPreferences(_ preferences:NotificationPreferences) async -> Bool { await performReturning{try await backend.saveNotificationPreferences(preferences);notificationPreferences=preferences;successMessage="Notification preferences saved.";return true}fallback:{false} }
    func reportRows(kind:String,from:Date,to:Date) async ->[WorkforceReportRow] { await performReturning{guard let branch=selectedBranch else{throw BackendError.noBranch};return try await backend.workforceReport(branchId:branch.id,from:ISODate.string(from:from),to:ISODate.string(from:to),kind:kind)}fallback:{[]} }
    func addLifecycleTask(employeeId:String,phase:String,title:String,dueOn:Date?) async ->Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveLifecycleTask(organizationId:org,employeeId:employeeId,phase:phase,title:title,dueOn:dueOn);lifecycleTasks=try await backend.lifecycleTasks();successMessage="Lifecycle task added.";return true}fallback:{false} }
    func completeLifecycleTask(_ task:EmployeeLifecycleTask) async { await perform{try await backend.updateLifecycleTask(id:task.id,status:"completed");lifecycleTasks=try await backend.lifecycleTasks()} }
    func addEmployeeAsset(employeeId:String,type:String,label:String,identifier:String,date:Date) async ->Bool { await performReturning{guard let org=organizationId else{throw BackendError.noMembership};try await backend.saveEmployeeAsset(organizationId:org,employeeId:employeeId,type:type,label:label,identifier:identifier,issuedOn:date);employeeAssets=try await backend.employeeAssets();successMessage="Asset issued.";return true}fallback:{false} }
    func returnEmployeeAsset(_ asset:EmployeeAsset,condition:String) async { await perform{try await backend.returnEmployeeAsset(id:asset.id,condition:condition);employeeAssets=try await backend.employeeAssets()} }
    func enableNotifications() async -> Bool {
        do {
            let granted=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound])
            if granted { await MainActor.run{UIApplication.shared.registerForRemoteNotifications()};successMessage="Notifications enabled." } else { errorMessage="Notifications are disabled in iPhone Settings." }
            return granted
        } catch { errorMessage=UserFacingError.message(for:error);return false }
    }
    func requestAccountDeletion(reason:String) async -> Bool { await performReturning{try await backend.requestAccountDeletion(reason:reason);BiometricLoginStore.remove();MobileCache.clear();UserDefaults.standard.set(false,forKey:"cb.rememberSession");try? await backend.signOut();access = .signedOut;successMessage="Account deletion requested. Access has been disabled.";return true}fallback:{false} }
    func signInKiosk(pin:String) async { errorMessage="The web kiosk was retired. Use an assigned employee account on iOS." }
    func enterDemo(role:String="owner"){
        let title=AppRole.resolved(role).title
        let user=AdminUser(id:"demo",fullName:"Demo \(title)",email:"demo@chickybites.app",role:role)
        let org="00000000-0000-0000-0000-000000000001"
        let branch="00000000-0000-0000-0000-000000000002"
        let employee="00000000-0000-0000-0000-000000000003"
        let now=ISO8601DateFormatter().string(from:.now)
        branches=[Branch(id:branch,organizationId:org,code:"CB-01",name:"Chicky Bites Main",address:"Demo branch",latitude:31.5204,longitude:74.3587,geofenceRadiusM:50,attendanceVerificationMode:"ip_and_gps",requiresBiometric:true,gpsAccuracyLimitM:35,timezone:"Asia/Karachi",isActive:true)]
        selectedBranchId=branch
        employees=[Employee(id:employee,organizationId:org,userId:"demo",employeeCode:"CB-001",fullName:"Demo \(title)",phone:"0312-0000000",position:"Team Member",cnic:"00000-0000000-0",address:"Lahore",joiningDate:"2026-01-01",employmentStatus:"active",appRole:role,terminationDate:nil,createdAt:now,department:"Operations",reportingManagerId:nil,employmentType:"full_time",probationEndDate:nil,emergencyContactName:nil,emergencyContactPhone:nil,dateOfBirth:nil)]
        salarySummary=SalarySummary(employeeId:employee,currency:"PKR",periodStart:ISODate.string(from:Calendar.current.date(from:Calendar.current.dateComponents([.year,.month],from:.now)) ?? .now),periodEnd:ISODate.string(from:.now),nextPayDate:ISODate.string(from:Calendar.current.date(byAdding:.day,value:7,to:.now) ?? .now),baseSalaryMinor:65_000_00,approvedEarningsMinor:4_500_00,approvedDeductionsMinor:1_850_00,pendingDeductionsMinor:650_00,estimatedNetMinor:67_000_00,confirmedNetMinor:67_650_00,paidMinor:0,remainingMinor:67_650_00)
        salaryLedger=[
            SalaryLedgerTransaction(id:"demo-ledger-1",organizationId:org,employeeId:employee,transactionType:"deduction",category:"extra_food",label:"Extra meal",description:"One staff meal recorded after the included allowance",currency:"PKR",status:"pending",occurredAt:now,sourceType:"food",createdAt:now,branchId:branch,ruleId:nil,payrollItemId:nil,reversalOfId:nil,sourceId:nil,calculationText:"1 × PKR 650.00",createdBy:nil,approvedBy:nil,approvedAt:nil,appliedAt:nil,amountMinor:650_00,unitRateMinor:650_00,workDate:ISODate.string(from:.now),quantity:1,calculationMinutes:nil,hasMore:false),
            SalaryLedgerTransaction(id:"demo-ledger-2",organizationId:org,employeeId:employee,transactionType:"deduction",category:"late_checkin",label:"Late check-in",description:"12 chargeable minutes after the grace period",currency:"PKR",status:"approved",occurredAt:ISO8601DateFormatter().string(from:Calendar.current.date(byAdding:.day,value:-2,to:.now) ?? .now),sourceType:"attendance",createdAt:now,branchId:branch,ruleId:nil,payrollItemId:nil,reversalOfId:nil,sourceId:nil,calculationText:"12 minutes × PKR 100.00",createdBy:nil,approvedBy:nil,approvedAt:now,appliedAt:nil,amountMinor:1_200_00,unitRateMinor:100_00,workDate:ISODate.string(from:Calendar.current.date(byAdding:.day,value:-2,to:.now) ?? .now),quantity:nil,calculationMinutes:12,hasMore:false),
            SalaryLedgerTransaction(id:"demo-ledger-3",organizationId:org,employeeId:employee,transactionType:"earning",category:"overtime",label:"Overtime",description:"Three approved overtime hours",currency:"PKR",status:"approved",occurredAt:ISO8601DateFormatter().string(from:Calendar.current.date(byAdding:.day,value:-5,to:.now) ?? .now),sourceType:"attendance",createdAt:now,branchId:branch,ruleId:nil,payrollItemId:nil,reversalOfId:nil,sourceId:nil,calculationText:"3 hours × PKR 1,500.00",createdBy:nil,approvedBy:nil,approvedAt:now,appliedAt:nil,amountMinor:4_500_00,unitRateMinor:1_500_00,workDate:ISODate.string(from:Calendar.current.date(byAdding:.day,value:-5,to:.now) ?? .now),quantity:3,calculationMinutes:180,hasMore:false)
        ]
        stats=DashboardStats(activeEmployees:1,present:1)
        isRestoringSession=false
        access = .demo(user)
    }

    func registerPushToken(_ token:String) async { guard currentUser != nil else{return};do{try await backend.registerPushToken(token,deviceId:DeviceIdentity.value,environment:"production")}catch{errorMessage=UserFacingError.message(for:error)} }
    func biometricChallenge() async -> BiometricChallenge? { guard let branch=selectedBranch else{return nil};return try? await backend.issueBiometricChallenge(branchId:branch.id,deviceId:DeviceIdentity.value) }

    private func prepareTrustedDeviceAndSync() async {
        do { let key=try await AttendanceEvidenceVault.shared.devicePublicKey();try await backend.registerTrustedDevice(deviceId:DeviceIdentity.value,publicKey:key) } catch { }
        offlineAttendanceCount=await AttendanceEvidenceVault.shared.count()
        await syncOfflineAttendance()
        await flushDiagnostics()
        BackgroundRecoveryCoordinator.schedule()
    }

    private func performBackgroundRecovery() async ->Bool {
        guard currentUser != nil,!isDemo,isConnected else{return currentUser == nil || isDemo}
        await syncOfflineAttendance()
        await flushDiagnostics()
        return offlineAttendanceCount == 0
    }

    func flushDiagnostics() async {
        guard currentUser != nil,let organizationId,!isDemo,isConnected else{return}
        let pending=await DiagnosticQueue.shared.pending()
        guard !pending.isEmpty else{return}
        var uploaded=Set<UUID>()
        for diagnostic in pending.prefix(12) {
            do { try await backend.recordDiagnostic(diagnostic,organizationId:organizationId,branchId:selectedBranch?.id);uploaded.insert(diagnostic.id) }
            catch { break }
        }
        if !uploaded.isEmpty { await DiagnosticQueue.shared.remove(ids:uploaded) }
    }

    private func startRealtime(organizationId:String) async {
        let realtime=InsForgeService.client.realtime
        let channel="employee-hub:\(organizationId)"
        do { try await realtime.connect() } catch { realtimeStarted=false;return }
        let result=await realtime.subscribe(channel);guard result.ok else{realtimeStarted=false;return}
        realtimeListenerId=realtime.on("data_changed"){[weak self] message in Task{@MainActor in try? await Task.sleep(for:.milliseconds(250));await self?.applyRealtimeChange(message.payload)} }
        realtimeChannelName=channel
    }
    private func applyRealtimeChange(_ payload:[String:Any]) async {
        guard let branch=selectedBranch else{return}
        let table=payload["table"] as? String
        do {
            switch table {
            case "app_notifications": notifications=try await backend.notifications()
            case "shift_roster_entries": shifts=try await backend.shifts(branchId:branch.id,start:ISODate.string(from:selectedDate),end:ISODate.string(from:Calendar.current.date(byAdding:.day,value:35,to:selectedDate) ?? selectedDate))
            case "attendance_correction_requests": correctionRequests=try await backend.correctionRequests(branchId:branch.id)
            case "leave_requests": leaves=try await backend.leaves(branchId:branch.id);leavesHaveMore=leaves.count==50
            case "payroll_runs": payrollRuns=try await backend.payrollRuns(branchId:branch.id);payrollRunsHaveMore=payrollRuns.count==25
            case "attendance_daily":
                attendanceDays=try await backend.attendance(branchId:branch.id,date:ISODate.string(from:selectedDate))
                rebuildAttendancePresentation()
            case "employee_documents": employeeDocuments=try await backend.employeeDocuments();employeeDocumentsHaveMore=employeeDocuments.count==50
            case "shift_swap_requests": shiftSwaps=try await backend.shiftSwaps(branchId:branch.id)
            case "payroll_items": payrollItems=try await backend.payrollItems()
            default: return
            }
            saveCache()
        } catch { }
    }

    private func loadCache(for userId:String) {
        guard let cache=MobileCache.load(userId:userId) else{return}
        branches=cache.branches;selectedBranchId=cache.selectedBranchId;employees=cache.employees;attendanceDays=cache.attendanceDays;leaves=cache.leaves;shifts=cache.shifts;notifications=cache.notifications
    }
    private func saveCache() {
        guard let userId=currentUser?.id else{return}
        MobileCache.save(MobileCacheSnapshot(userId:userId,selectedBranchId:selectedBranch?.id,branches:branches,employees:employees,attendanceDays:attendanceDays,leaves:leaves,shifts:shifts,notifications:notifications,savedAt:.now))
    }

    private func perform(_ op:() async throws->Void) async { isWorking=true;errorMessage=nil;defer{isWorking=false};do{try await op()}catch{AppDiagnostics.shared.capture(error:error,category:"app-operation");errorMessage=UserFacingError.message(for:error)} }
    private func performReturning<T>(_ op:() async throws->T,fallback:()->T) async -> T { isWorking=true;errorMessage=nil;defer{isWorking=false};do{return try await op()}catch{AppDiagnostics.shared.capture(error:error,category:"app-operation");errorMessage=UserFacingError.message(for:error);return fallback()} }
}

enum DeviceIdentity { static var value:String { if let id=UserDefaults.standard.string(forKey:"cb.deviceId"){return id};let id=UUID().uuidString;UserDefaults.standard.set(id,forKey:"cb.deviceId");return id } }
enum AttendanceMessage { static func forCode(_ code:String?)->String { switch code { case "biometric_required":"A fresh live face scan is required.";case "ip_not_allowed":"Connect to an approved restaurant Wi-Fi network.";case "outside_geofence":"Move within 50 metres of your branch.";case "location_not_verified":"Connect to restaurant Wi-Fi or move within the branch geofence.";case "both_ip_and_gps_required":"Both restaurant Wi-Fi and GPS verification are required.";default:"Attendance could not be verified." } } }
enum FaceVerificationMessage { static func forReason(_ reason:String?)->String { switch reason { case "face_not_enrolled":"Your manager must enroll your face before you can mark attendance.";case "face_model_changed":"Your face enrollment must be updated by a manager.";case "liveness_required":"Please complete the quick live face check.";case "capture_inconsistent":"Keep one face steady in even light and try again.";case "face_not_matched":"The face does not match the employee logged into this account.";default:"The employee face could not be verified." } } }

enum UserFacingError {
    static func isTransientServiceFailure(_ error: Error) -> Bool {
        let message=error.localizedDescription.lowercased()
        return message.contains("socket hang up")
            || message.contains("econnreset")
            || message.contains("network connection was lost")
            || message.contains("timed out")
            || message.contains("internal_error")
            || message.contains("temporarily unavailable")
            || ["http 500","http 502","http 503","http 504"].contains(where:message.contains)
    }

    static func message(for error: Error) -> String {
        let message=error.localizedDescription
        if message.contains("employees_organization_id_cnic_key") {
            return "This CNIC is already assigned to another employee. Use the employee's own CNIC or edit the existing record."
        }
        if message.contains("employees_organization_id_employee_code_key") {
            return "This employee code is already in use. Enter a unique employee code."
        }
        if message.contains("HTTP 409") || message.localizedCaseInsensitiveContains("duplicate key") {
            return "An employee already uses this information. Check the CNIC and employee code, then try again."
        }
        if message.localizedCaseInsensitiveContains("invalid credentials") || message.contains("HTTP 401") {
            return "The email or password is incorrect. Please check both and try again."
        }
        if message.localizedCaseInsensitiveContains("expired") && message.localizedCaseInsensitiveContains("code") {
            return "This code has expired. Request a new code and try again."
        }
        if isTransientServiceFailure(error) {
            return "The service is temporarily unavailable. Please try again in a moment."
        }
        return message
    }
}

enum AuthFlowClassifier {
    static func requiresVerification(_ error:Error)->Bool {
        let message=error.localizedDescription.lowercased()
        return message.contains("email verification required")
            || message.contains("email not verified")
            || (message.contains("403") && message.contains("verif"))
    }
}

fileprivate struct StoredLoginCredential:Codable { let email:String;let password:String }

@MainActor
enum BiometricLoginStore {
    private static let service="pk.com.chickybites.employeehub.biometric-login"
    private static let account="primary"
    private static let enabledKey="cb.biometricLogin.enabled"

    static var hasCredential:Bool { UserDefaults.standard.bool(forKey:enabledKey) }

    static var biometricName:String {
        let context=LAContext(); var error:NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&error) else{return "Face ID"}
        switch context.biometryType { case .touchID:return "Touch ID";case .opticID:return "Optic ID";default:return "Face ID" }
    }

    static func save(email:String,password:String) async throws {
        let context=LAContext()
        context.localizedCancelTitle="Not Now"
        let allowed=try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,localizedReason:"Enable secure biometric login for CB Employee Hub")
        guard allowed else{throw CancellationError()}
        remove()
        guard let data=try? JSONEncoder().encode(StoredLoginCredential(email:email,password:password)) else{throw BackendError.invalidInput("Biometric login could not be prepared.")}
        var accessError:Unmanaged<CFError>?
        guard let access=SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,.biometryCurrentSet,&accessError) else{throw accessError!.takeRetainedValue()}
        let query:[String:Any]=[
            kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service,
            kSecAttrAccount as String:account,
            kSecAttrAccessControl as String:access,
            kSecValueData as String:data
        ]
        let status=SecItemAdd(query as CFDictionary,nil)
        guard status==errSecSuccess else{throw BackendError.invalidInput("Biometric login could not be saved on this iPhone.")}
        UserDefaults.standard.set(true,forKey:enabledKey)
    }

    fileprivate static func read() async throws ->StoredLoginCredential {
        guard hasCredential else{throw BackendError.invalidInput("Sign in with your password once and enable Face ID for future logins.")}
        let context=LAContext();context.localizedCancelTitle="Use Password";context.localizedReason="Sign in to CB Employee Hub"
        let query:[String:Any]=[
            kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service,
            kSecAttrAccount as String:account,
            kSecReturnData as String:true,
            kSecMatchLimit as String:kSecMatchLimitOne,
            kSecUseAuthenticationContext as String:context
        ]
        var result:CFTypeRef?
        let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status==errSecUserCanceled || status==errSecAuthFailed {throw CancellationError()}
        guard status==errSecSuccess,let data=result as? Data,let credential=try? JSONDecoder().decode(StoredLoginCredential.self,from:data) else {
            UserDefaults.standard.set(false,forKey:enabledKey)
            throw BackendError.invalidInput("Face ID login needs to be enabled again using your password.")
        }
        return credential
    }

    static func remove(){
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.set(false,forKey:enabledKey)
    }
}
