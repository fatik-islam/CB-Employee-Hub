import SwiftUI

struct DashboardView: View {
    @Environment(AppSession.self) private var session

    private let columns = [
        GridItem(.adaptive(minimum: 145), spacing: 14)
    ]

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing: 22) {
                    hero

                    if session.role.isAdministrator && session.branchSummaries.count>1 { multiBranchCommandCenter }

                    metricGrid

                    if session.role.canManagePeople {
                        biometricHealth
                        recentTeam
                    } else {
                        employeeSnapshot
                        if let summary=session.salarySummary {
                            NavigationLink { SalaryLedgerView() } label: {
                                VStack(alignment:.leading,spacing:10) {
                                    SalarySummaryCard(summary:summary)
                                    Label("View every earning and deduction",systemImage:"chevron.right")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(CBTheme.info).frame(maxWidth:.infinity,alignment:.trailing)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .refreshable { await session.refreshDashboardFeature() }
        }
        .navigationTitle(L10n.text("Overview"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .task(id:"\(session.selectedBranchId ?? "")-\(ISODate.string(from:session.selectedDate))"){await session.refreshDashboardFeature()}
        .overlay {
            if session.isWorking { LoadingOverlay() }
        }
    }

    private var multiBranchCommandCenter:some View {
        VStack(alignment:.leading,spacing:14) {
            SectionTitle(title:"All branches",subtitle:"Live attendance and pending work across your locations.",symbol:"building.2.fill")
            ForEach(session.branchSummaries) { branch in
                Button { session.selectBranch(branch.branchId) } label: {
                    VStack(alignment:.leading,spacing:10) {
                        HStack { Text(branch.branchName).font(.headline).foregroundStyle(CBTheme.text);Spacer();if branch.branchId==session.selectedBranch?.id{Image(systemName:"checkmark.circle.fill").foregroundStyle(CBTheme.success)} }
                        HStack(spacing:14) {
                            Label("\(branch.present) present",systemImage:"checkmark.circle.fill").foregroundStyle(CBTheme.success)
                            Label("\(branch.absent) absent",systemImage:"xmark.circle.fill").foregroundStyle(CBTheme.danger)
                            Spacer();Text("\(branch.pendingLeaves) leave").foregroundStyle(CBTheme.muted)
                        }.font(.caption.weight(.semibold))
                    }.padding(14).background(CBTheme.surface.opacity(0.45),in:RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain)
            }
        }.padding(18).cbGlass(cornerRadius:24,tint:CBTheme.info.opacity(0.05))
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [CBTheme.navy900, CBTheme.navy800],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(formattedToday)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Hello, \(firstName).")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(session.role.canManagePeople ? "Here’s your branch overview." : "Here’s your personal workday overview.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                    Text(session.role.title)
                    if let branch = session.selectedBranch { Text("•"); Text(branch.name) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CBTheme.gold)
            }
            .padding(22)
        }
        .frame(minHeight: 190)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = L10n.currentLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return L10n.latinDigits(formatter.string(from: .now))
    }

    private var firstName: String {
        session.currentUser?.fullName.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var metricGrid: some View {
        GlassGroup(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 14) {
                if session.role.canManagePeople {
                    MetricCard(title: "Active Employees", value: "\(session.stats.activeEmployees)", symbol: "person.2.fill", color: CBTheme.info)
                    MetricCard(title: "Present Today", value: "\(session.stats.present)", symbol: "checkmark.circle.fill", color: CBTheme.success)
                    MetricCard(title: "Absent Today", value: "\(session.stats.absent)", symbol: "xmark.circle.fill", color: CBTheme.danger)
                    MetricCard(title: "Pending Leaves", value: "\(session.stats.pendingLeaves)", symbol: "calendar.badge.clock", color: CBTheme.warning)
                } else {
                    MetricCard(title: "Today’s Status", value: ownAttendanceStatus, symbol: "person.crop.circle.badge.checkmark", color: ownAttendanceStatus == "Present" ? CBTheme.success : CBTheme.info)
                    MetricCard(title: "Pending Leave", value: "\(ownPendingLeaves)", symbol: "calendar.badge.clock", color: CBTheme.warning)
                    MetricCard(title: "Payslips", value: "\(ownPayslips)", symbol: "doc.text.fill", color: CBTheme.info)
                    MetricCard(title: "Branch Radius", value: "\(session.selectedBranch?.geofenceRadiusM ?? 50)m", symbol: "location.circle.fill", color: CBTheme.orange)
                }
            }
        }
    }

    private var ownAttendanceStatus: String {
        guard let id = session.ownEmployee?.id else { return "Not linked" }
        return session.attendanceDays.first { $0.employeeId == id }?.status.sentenceCased ?? "Unmarked"
    }
    private var ownPendingLeaves: Int {
        guard let id = session.ownEmployee?.id else { return 0 }
        return session.leaves.filter { $0.employeeId == id && $0.status == "pending" }.count
    }
    private var ownPayslips: Int {
        guard let id = session.ownEmployee?.id else { return 0 }
        return session.payrollItems.filter { $0.employeeId == id }.count
    }

    private var employeeSnapshot: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Your secure access", subtitle: "Information is filtered for your employee account and assigned branch.", symbol: "lock.shield.fill")
            InfoRow(symbol: "person.text.rectangle.fill", title: "Employee", value: session.ownEmployee.map { "\($0.employeeCode) — \($0.fullName)" } ?? "Invite code required")
            InfoRow(symbol: "building.2.fill", title: "Assigned branch", value: session.selectedBranch?.name ?? "Not assigned", color: CBTheme.orange)
        }
        .padding(18).cbGlass(cornerRadius: 23, tint: CBTheme.surface.opacity(0.08))
    }

    private var biometricHealth: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Biometric health")
                        .font(.headline)
                    Text("\(session.metrics.totalFaceEnrolledEmployees) of \(session.stats.activeEmployees) active employees enrolled")
                        .font(.caption)
                        .foregroundStyle(CBTheme.muted)
                }
                Spacer()
                StatusBadge(status: session.metrics.systemHealth)
            }

            ProgressView(
                value: Double(session.metrics.totalFaceEnrolledEmployees),
                total: Double(max(session.stats.activeEmployees, 1))
            )
            .tint(CBTheme.orange)

            HStack {
                Label(
                    "\(Int(session.metrics.attendanceSuccessRate * 100))% attendance success",
                    systemImage: "waveform.path.ecg"
                )
                Spacer()
                Text("\(Int(session.metrics.failedVerificationRate * 100))% failed")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(CBTheme.muted)
        }
        .padding(18)
        .cbGlass(cornerRadius: 22)
    }

    private var recentTeam: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Recent team", subtitle: "Newest employee records")

            if session.employees.isEmpty {
                EmptyState(
                    symbol: "person.2.slash",
                    title: "No employees yet",
                    message: "Add your first employee from the Team tab."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(session.employees.prefix(5)) { employee in
                        HStack(spacing: 12) {
                            InitialsAvatar(name: employee.fullName)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(employee.fullName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(employee.employeeCode) • \(employee.position ?? "Team member")")
                                    .font(.caption)
                                    .foregroundStyle(CBTheme.muted)
                            }
                            Spacer()
                            StatusBadge(status: employee.status)
                        }
                        .padding(.vertical, 12)

                        if employee.id != session.employees.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .cbGlass(cornerRadius: 22)
            }
        }
    }
}
