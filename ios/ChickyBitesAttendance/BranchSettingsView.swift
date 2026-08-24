import SwiftUI

struct BranchSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var draft: Branch?
    @State private var ipLabel = "Restaurant Wi-Fi"
    @State private var ipNetwork = ""
    @State private var locationService = LocationService()
    @State private var showingNewBranch = false

    var body: some View {
        CreamPage {
            ScrollView {
                VStack(spacing: 16) {
                    if session.role == .owner {
                        HStack {
                            Picker("Branch", selection: Binding(get:{session.selectedBranchId ?? ""},set:{session.selectBranch($0)})) {
                                ForEach(session.branches) { Text($0.name).tag($0.id) }
                            }
                            Button("Add", systemImage:"plus") { showingNewBranch=true }.cbPrimaryButton()
                        }
                        .padding(16).cbGlass(cornerRadius:22,tint:CBTheme.surface.opacity(0.08))
                    }
                    if var branch = draft ?? session.selectedBranch {
                        VStack(alignment: .leading, spacing: 15) {
                            SectionTitle(title: "Branch identity", subtitle: "These details help employees confirm their assigned workplace.", symbol: "building.2.fill")
                            TextField("Branch name", text: binding(for: branch, get: { $0.name }, set: { $0.name = $1 }))
                                .textFieldStyle(.roundedBorder)
                            TextField("Address", text: binding(for: branch, get: { $0.address ?? "" }, set: { $0.address = $1 }))
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

                        VStack(alignment: .leading, spacing: 15) {
                            SectionTitle(title: "Attendance security", subtitle: "Choose which free location signals employees must pass.", symbol: "checkmark.shield.fill")
                            Picker("Verification", selection: binding(for: branch, get: { $0.attendanceVerificationMode }, set: { $0.attendanceVerificationMode = $1 })) {
                                Text("Wi-Fi or GPS").tag("IP_OR_GPS")
                                Text("Wi-Fi and GPS").tag("IP_AND_GPS")
                                Text("Wi-Fi only").tag("IP_ONLY")
                                Text("GPS only").tag("GPS_ONLY")
                            }
                            Toggle("Require employee face verification", isOn: binding(for: branch, get: { $0.requiresBiometric }, set: { $0.requiresBiometric = $1 }))
                            Stepper("Geofence radius: \(branch.geofenceRadiusM) metres", value: binding(for: branch, get: { $0.geofenceRadiusM }, set: { $0.geofenceRadiusM = $1 }), in: 10...1000, step: 10)
                            Divider().overlay(CBTheme.divider)
                            InfoRow(symbol: "mappin.and.ellipse", title: "Branch coordinates", value: coordinateText(branch))
                            Button("Use Current Location", systemImage: "location.fill") {
                                Task {
                                    if let location = await locationService.current() {
                                        branch.latitude = location.latitude; branch.longitude = location.longitude; draft = branch
                                    } else { session.errorMessage = "Location is unavailable. Check Location Services and try again." }
                                }
                            }.cbSecondaryButton()
                            Button("Save Branch Policy") { Task { await session.saveBranch(branch) } }
                                .cbPrimaryButton().frame(maxWidth: .infinity, alignment: .trailing)
                            if session.branches.count > 1 && session.role == .owner {
                                Button("Deactivate Branch",role:.destructive) { Task { await session.setBranchActive(branch,isActive:false) } }.buttonStyle(.bordered)
                            }
                        }
                        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

                        VStack(alignment: .leading, spacing: 15) {
                            SectionTitle(title: "Approved public IP", subtitle: "Add the restaurant’s public IP as one address or CIDR range. The server checks the connection at no API cost.", symbol: "wifi.router.fill")
                            TextField("Label", text: $ipLabel).textFieldStyle(.roundedBorder)
                            TextField("Example: 203.0.113.10/32", text: $ipNetwork)
                                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                            HStack {
                                Button("Detect This Wi-Fi",systemImage:"dot.radiowaves.left.and.right") { Task{await session.diagnoseNetwork()} }.buttonStyle(.bordered)
                                if let ip=session.observedPublicIP { Text(ip).font(.caption.monospaced()).textSelection(.enabled) }
                            }
                            Button("Add Approved IP") {
                                Task { await session.addIPRule(label: ipLabel, network: ipNetwork); if session.errorMessage == nil { ipNetwork = "" } }
                            }.cbPrimaryButton().disabled(ipNetwork.isEmpty)
                            ForEach(session.branchIPRules.filter{$0.branchId==branch.id}) { rule in
                                HStack {
                                    VStack(alignment:.leading) {
                                        Text(rule.label).font(.subheadline.weight(.semibold))
                                        Text(rule.network).font(.caption.monospaced()).foregroundStyle(CBTheme.muted)
                                    }
                                    Spacer()
                                    Toggle("",isOn:Binding(get:{rule.isActive},set:{value in Task{await session.setIPRuleActive(rule,isActive:value)}})).labelsHidden()
                                }
                            }
                        }
                        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.08))

                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "Safe outage behavior", subtitle: "Employees can fall back from Wi-Fi to GPS when permitted. If verification fails, an authorized manager can record an audited override with a reason and fresh password confirmation.", symbol: "shield.checkered")
                        }
                        .padding(18).cbGlass(cornerRadius: 24, tint: CBTheme.warning.opacity(0.045))
                    } else {
                        EmptyState(symbol: "building.2", title: "No branch assigned", message: "Assign this account to a branch before configuring attendance.")
                    }
                }
                .padding(16).padding(.bottom, 24)
            }
        }
        .navigationTitle(L10n.text("Branch Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .onAppear { draft = session.selectedBranch }
        .onChange(of: session.selectedBranchId) { _, _ in draft = session.selectedBranch }
        .task(id:session.selectedBranchId){await session.refreshBranchSettingsFeature();draft=session.selectedBranch}
        .refreshable{await session.refreshBranchSettingsFeature();draft=session.selectedBranch}
        .sheet(isPresented:$showingNewBranch) { NewBranchSheet() }
        .overlay { if session.isWorking { LoadingOverlay() } }
    }

    private func binding<Value>(for fallback: Branch, get: @escaping (Branch) -> Value, set: @escaping (inout Branch, Value) -> Void) -> Binding<Value> {
        Binding(
            get: { get(draft ?? fallback) },
            set: { value in var updated = draft ?? fallback; set(&updated, value); draft = updated }
        )
    }

    private func coordinateText(_ branch: Branch) -> String {
        guard let lat = branch.latitude, let lon = branch.longitude else { return "Not configured" }
        return String(format: "%.6f, %.6f", lat, lon)
    }
}

private struct NewBranchSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var name=""
    @State private var code=""
    @State private var address=""
    var body:some View {
        NavigationStack {
            Form {
                Section("Branch") {
                    TextField("Name",text:$name)
                    TextField("Code",text:$code).textInputAutocapitalization(.characters)
                    TextField("Address",text:$address,axis:.vertical)
                }
                Section { Button("Create Branch") { Task{if await session.createBranch(name:name,code:code,address:address){dismiss()}} }.disabled(name.count<2 || code.isEmpty || address.isEmpty) }
            }
            .navigationTitle(L10n.text("New Branch")).navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
        }
    }
}
