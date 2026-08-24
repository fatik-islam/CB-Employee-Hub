import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = UserDefaults.standard.string(forKey: "cb.rememberedEmail") ?? ""
    @State private var password = ""
    @State private var name = ""
    @State private var verificationCode = ""
    @State private var createAccount = false
    @State private var passwordVisible = false
    @State private var enableBiometric = true
    @State private var rememberMe = UserDefaults.standard.object(forKey: "cb.rememberSession") == nil ? true : UserDefaults.standard.bool(forKey: "cb.rememberSession")
    @State private var showingPasswordReset = false

    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool {
        normalizedEmail.contains("@") && (createAccount ? PasswordPolicy.isValid(password) : !password.isEmpty)
            && (!createAccount || name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2)
            && !session.isWorking
    }

    var body: some View {
        BrandedBackground {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 34)
                    BrandLockup(onDarkBackground: true)

                    VStack(spacing: 22) {
                        VStack(spacing: 7) {
                            Text(createAccount ? "Create your account" : "Welcome back")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text(createAccount
                                 ? "Register securely, verify your email, then join your assigned branch."
                                 : "Attendance, leave and salary—clear for every role.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 14) {
                            if createAccount {
                                PremiumTextField(symbol: "person.fill", placeholder: "Full name", text: $name, contentType: .name)
                            }
                            PremiumTextField(symbol: "envelope.fill", placeholder: "Email address", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                            PremiumPasswordField(
                                placeholder: createAccount ? "Create password" : "Password",
                                text: $password,
                                isVisible: $passwordVisible,
                                contentType: createAccount ? .newPassword : .password
                            )

                            if createAccount {
                                PasswordRequirementPanel(password: password)
                            }
                        }

                        if !createAccount && !session.hasBiometricLogin {
                            Toggle(isOn: $enableBiometric) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use \(session.biometricName) next time")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Your login is encrypted in this iPhone’s Keychain.")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                            }
                            .tint(CBTheme.orange)
                            .foregroundStyle(.white)
                        }

                        if !createAccount {
                            Toggle(isOn: $rememberMe) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Remember me")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Keep this account signed in on this iPhone.")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                            }
                            .tint(CBTheme.orange)
                            .foregroundStyle(.white)
                            .onChange(of: enableBiometric) { _, enabled in
                                if enabled { rememberMe = true }
                            }
                            .onChange(of: rememberMe) { _, enabled in
                                if !enabled { enableBiometric = false }
                            }
                        }

                        Button {
                            Task {
                                if createAccount {
                                    await session.register(name: name, email: normalizedEmail, password: password)
                                } else {
                                    await session.signIn(email: normalizedEmail, password: password, rememberMe: rememberMe, enableBiometric: enableBiometric)
                                }
                            }
                        } label: {
                            HStack(spacing: 9) {
                                if session.isWorking { ProgressView().tint(CBTheme.navy950) }
                                Text(createAccount ? "Create Account" : "Sign In")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                        }
                        .cbPrimaryButton()
                        .disabled(!canSubmit)

                        if !createAccount && session.hasBiometricLogin {
                            Button {
                                Task { await session.signInWithBiometrics() }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "faceid")
                                        .font(.system(size: 25, weight: .medium))
                                        .frame(width: 38, height: 38)
                                        .background(CBTheme.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Continue with \(session.biometricName)")
                                            .font(.headline)
                                        Text("Fast, private sign-in on this iPhone")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.66))
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .cbGlass(cornerRadius: 18, tint: CBTheme.orange.opacity(0.08))
                            .foregroundStyle(.white)
                            .disabled(session.isWorking)
                            .accessibilityLabel("Continue with \(session.biometricName)")
                            .accessibilityHint("Authenticates using biometrics saved on this iPhone")
                        }

                        HStack(spacing: 16) {
                            if !createAccount {
                                Button("Forgot password?") { showingPasswordReset = true }
                            }
                            Button(createAccount ? "Sign in instead" : "Create an account") {
                                withAnimation(.smooth) {
                                    createAccount.toggle()
                                    password = ""
                                    passwordVisible = false
                                }
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CBTheme.gold)
                    }
                    .padding(24)
                    .frame(maxWidth: 520)
                    .background(.white.opacity(colorScheme == .dark ? 0.025 : 0.055), in: RoundedRectangle(cornerRadius: 32))
                    .cbGlass(cornerRadius: 32, tint: .white.opacity(0.06))
                    .padding(.horizontal, 18)

                    Label("Protected by InsForge • Asia/Karachi", systemImage: "lock.shield.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.68))
                    Spacer(minLength: 28)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .topTrailing) {
            LanguageToggle(onDarkBackground: true)
                .padding(.top, 10)
                .padding(.trailing, 16)
        }
        .sheet(isPresented: Binding(
            get: { session.pendingVerificationEmail != nil },
            set: { if !$0 { session.pendingVerificationEmail = nil } }
        )) {
            VerificationView(code: $verificationCode)
                .presentationDetents([.height(470)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPasswordReset, onDismiss: { session.cancelPasswordReset() }) {
            PasswordResetView(initialEmail: normalizedEmail)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct PremiumTextField: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(CBTheme.info).frame(width: 20)
            TextField("", text: $text, prompt: Text(L10n.text(placeholder)).foregroundStyle(CBTheme.muted))
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .foregroundStyle(CBTheme.text)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 54)
        .background(CBTheme.surface.opacity(0.93), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CBTheme.divider.opacity(0.55), lineWidth: 0.8) }
    }
}

struct PremiumPasswordField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool
    var contentType: UITextContentType = .password

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundStyle(CBTheme.info).frame(width: 20)
            Group {
                if isVisible {
                    TextField("", text: $text, prompt: Text(L10n.text(placeholder)).foregroundStyle(CBTheme.muted))
                } else {
                    SecureField("", text: $text, prompt: Text(L10n.text(placeholder)).foregroundStyle(CBTheme.muted))
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(CBTheme.text)

            Button { isVisible.toggle() } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(CBTheme.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide password" : "Show password")
        }
        .padding(.leading, 15)
        .padding(.trailing, 9)
        .frame(minHeight: 54)
        .background(CBTheme.surface.opacity(0.93), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CBTheme.divider.opacity(0.55), lineWidth: 0.8) }
    }
}

struct PasswordRequirementPanel: View {
    let password: String
    private var isValid: Bool { PasswordPolicy.isValid(password) }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "info.circle.fill")
            Text(isValid ? "Strong password" : "10+ characters with uppercase, lowercase and a number")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isValid ? CBTheme.success : CBTheme.warning)
        .padding(12)
        .background((isValid ? CBTheme.success : CBTheme.warning).opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct VerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Binding var code: String

    var body: some View {
        NavigationStack {
            CreamPage {
                VStack(spacing: 22) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(CBTheme.orange)
                        .frame(width: 76, height: 76)
                        .cbGlass(cornerRadius: 24, tint: CBTheme.orange.opacity(0.12))
                    SectionTitle(
                        title: "Verify your email",
                        subtitle: "Enter the six-digit code sent to \(session.pendingVerificationEmail ?? "your email")."
                    )
                    TextField("000000", text: $code)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding()
                        .background(CBTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                        .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                    Button("Verify and Continue") { Task { await session.verify(code: code) } }
                        .cbPrimaryButton().disabled(code.count != 6 || session.isWorking)
                    Button("Send a new code") { Task { await session.resendVerification() } }
                        .font(.subheadline.weight(.semibold))
                        .disabled(session.isWorking)
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle(L10n.text("Email Verification"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let initialEmail: String
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var passwordVisible = false

    init(initialEmail: String) {
        self.initialEmail = initialEmail
        _email = State(initialValue: initialEmail)
    }

    private var stage: Int {
        if session.passwordResetToken != nil { return 3 }
        if session.pendingPasswordResetEmail != nil { return 2 }
        return 1
    }

    var body: some View {
        NavigationStack {
            CreamPage {
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: stage == 3 ? "key.fill" : "lock.rotation")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(CBTheme.orange)
                            .frame(width: 74, height: 74)
                            .cbGlass(cornerRadius: 23, tint: CBTheme.orange.opacity(0.1))

                        SectionTitle(title: title, subtitle: subtitle)

                        if stage == 1 {
                            PremiumTextField(symbol: "envelope.fill", placeholder: "Registered email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                            Button("Send Reset Code") { Task { _ = await session.beginPasswordReset(email: email) } }
                                .cbPrimaryButton().disabled(!email.contains("@") || session.isWorking)
                        } else if stage == 2 {
                            TextField("000000", text: $code)
                                .font(.system(size: 30, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .padding()
                                .background(CBTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                                .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                            Button("Verify Code") { Task { _ = await session.verifyPasswordReset(code: code) } }
                                .cbPrimaryButton().disabled(code.count != 6 || session.isWorking)
                            Button("Send another code") { Task { _ = await session.beginPasswordReset(email: email) } }
                                .font(.subheadline.weight(.semibold))
                        } else {
                            PremiumPasswordField(placeholder: "New password", text: $password, isVisible: $passwordVisible, contentType: .newPassword)
                            PasswordRequirementPanel(password: password)
                            Button("Update Password") {
                                Task { if await session.finishPasswordReset(newPassword: password) { dismiss() } }
                            }
                            .cbPrimaryButton().disabled(!PasswordPolicy.isValid(password) || session.isWorking)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle(L10n.text("Forgot Password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var title: String {
        switch stage { case 1: "Reset your password"; case 2: "Enter the reset code"; default: "Choose a new password" }
    }
    private var subtitle: String {
        switch stage {
        case 1: "We’ll send a secure six-digit code to your registered email."
        case 2: "Enter the code sent to \(session.pendingPasswordResetEmail ?? email)."
        default: "Use at least six characters. Your previous password will stop working immediately."
        }
    }
}

enum PasswordPolicy {
    static func isValid(_ value:String)->Bool {
        value.count>=10 && value.contains(where:{$0.isUppercase}) && value.contains(where:{$0.isLowercase}) && value.contains(where:{$0.isNumber})
    }
}
