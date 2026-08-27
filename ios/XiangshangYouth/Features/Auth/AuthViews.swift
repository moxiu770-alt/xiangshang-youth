import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var state: AppState
    private var displayDuration: Duration {
        // UI automation needs a deterministic inspection window.  Production
        // stays at the approved two-second poster transition.
        ProcessInfo.processInfo.arguments.contains("-ui-testing-splash-hold") ? .seconds(6) : .seconds(2)
    }

    var body: some View {
        ZStack {
            Color(hex: "7452A5").ignoresSafeArea()
            Image("LaunchPoster")
                .resizable()
                // The approved poster is a portrait composition. Preserve the
                // whole artwork on iPad instead of cropping its headline; the
                // purple canvas provides intentional side letterboxing there.
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityLabel("向上少年启动页")
        }
        .statusBarHidden(true)
        // Keep the launch artwork edge-to-edge for the full splash duration.
        // This hides the transient Home indicator while the native poster is
        // visible; the login/dashboard screens restore the system overlay.
        .persistentSystemOverlays(.hidden)
        .task {
            do {
                try await Task.sleep(for: displayDuration)
                // A stored session refreshes behind the pure poster.  Wait for
                // that result before exposing Login/RoleSelect, matching the
                // Android root behavior and preventing a half-restored screen.
                while state.restoringSession {
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.28)) {
                state.dismissSplash()
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var phone = ""
    @State private var account = ""
    @State private var password = ""
    @State private var verificationCode = ""
    // The reference login screen leads with WeChat authorization; phone and
    // account/password remain one-tap alternatives below it.
    @State private var method: LoginMethod = .wechat
    @State private var agreementAccepted = false
    @State private var codeSent = false
    @State private var codeSending = false
    @State private var codeCountdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var validationMessage: String?
    @State private var registerPresented = false
    @State private var resetPasswordPresented = false
    @State private var legalDocument: LegalDocument?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "E9F4FF"), Color(hex: "F8FBFF")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle().fill(ReferenceColor.blue.opacity(0.08)).frame(width: 360).blur(radius: 4).offset(x: 190, y: -300)

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        VStack(spacing: 14) {
                            Image(systemName: "figure.run.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, ReferenceColor.blue)
                                .font(.system(size: 62, weight: .semibold))
                                .accessibilityHidden(true)
                            VStack(spacing: 6) {
                                Text("登录向上少年")
                                    .font(.system(size: AppTheme.displaySize, weight: .bold))
                                    .foregroundStyle(ReferenceColor.navy)
                                Text("连接学校与家庭，陪伴孩子健康成长")
                                    .font(.system(size: AppTheme.secondarySize, weight: .medium))
                                    .foregroundStyle(AppTheme.muted)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, horizontalSizeClass == .compact ? 34 : 56)

                        loginPanel
                        Spacer(minLength: 24)
                        landscape
                    }
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onDisappear { countdownTask?.cancel() }
        .sheet(isPresented: $registerPresented) { RegisterView() }
        .sheet(isPresented: $resetPasswordPresented) { ResetPasswordView() }
        .sheet(item: $legalDocument) { document in LegalDocumentView(document: document) }
    }

    private var loginPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("账号登录")
                    .font(.system(size: AppTheme.sectionTitleSize, weight: .bold))
                    .foregroundStyle(ReferenceColor.navy)
                Text("公开注册账号仅进入家庭端，教师账号由学校统一开通")
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            loginMethodButton("微信登录", icon: "message.fill", color: ReferenceColor.blue, selected: method == .wechat, showsProgress: state.loading && method == .wechat) {
                if method == .wechat { submitLogin() }
                else { method = .wechat; clearLoginError() }
            }
            HStack(spacing: AppTheme.cardSpacing) {
                loginAlternativeButton("手机号登录", icon: "iphone", selected: method == .phone) {
                    method = .phone; clearLoginError()
                }
                loginAlternativeButton("账号密码登录", icon: "person.crop.circle", selected: method == .account) {
                    method = .account; clearLoginError()
                }
            }
            .disabled(state.loading)

            if method == .phone {
                VStack(spacing: 12) {
                    TextField("手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: phone) { _, _ in invalidateLoginVerification() }
                    HStack(spacing: 10) {
                        TextField("短信验证码", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: verificationCode) { _, _ in clearLoginError() }
                        Button(codeSending ? "发送中…" : codeCountdown > 0 ? "\(codeCountdown)s" : codeSent ? "重新获取" : "获取验证码") {
                            guard phone.filter(\.isNumber).count == 11 else { validationMessage = "请先填写 11 位手机号。"; return }
                            codeSending = true
                            Task { @MainActor in
                                let sent = await state.requestVerificationCode(account: phone, purpose: "login")
                                codeSending = false
                                guard sent else { validationMessage = state.error ?? "验证码发送失败，请稍后重试。"; return }
                                codeSent = true
                                codeCountdown = 60
                                countdownTask?.cancel()
                                countdownTask = Task { @MainActor in
                                    while codeCountdown > 0 {
                                        try? await Task.sleep(for: .seconds(1))
                                        guard !Task.isCancelled else { return }
                                        codeCountdown -= 1
                                    }
                                }
                            }
                        }
                        .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                        .foregroundStyle(ReferenceColor.blue)
                        .frame(minWidth: 82, minHeight: AppTheme.minimumTapSize)
                        .disabled(codeCountdown > 0 || codeSending)
                    }
                }
            } else if method == .account {
                VStack(spacing: 12) {
                    TextField("账号 / 手机号", text: $account)
                        .textContentType(.username)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: account) { _, _ in clearLoginError() }
                    PasswordInput("登录密码（至少 8 位）", text: $password)
                        .onChange(of: password) { _, _ in clearLoginError() }
                }
            }

            if method != .wechat {
                Button(action: submitLogin) {
                    Group {
                        if state.loading { HStack(spacing: 8) { ProgressView().tint(.white); Text("正在登录…") } }
                        else { Text("登录") }
                    }
                    .font(.system(size: AppTheme.buttonSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.controlHeight)
                    .background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                // A stable identifier keeps the real remote-login regression
                // independent from the adjacent "账号密码登录" method picker.
                .accessibilityIdentifier("login-submit-button")
                .disabled(state.loading)
            }

            if let message = validationMessage ?? state.error {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isStaticText)
            }

            HStack {
                Button { registerPresented = true } label: { Text("家长注册").foregroundStyle(ReferenceColor.blue) }
                Spacer()
                Button { resetPasswordPresented = true } label: { Text("忘记密码？").foregroundStyle(AppTheme.muted) }
            }
            .font(.system(size: AppTheme.secondarySize, weight: .semibold))

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Button { agreementAccepted.toggle() } label: {
                    Image(systemName: agreementAccepted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(agreementAccepted ? ReferenceColor.green : AppTheme.muted)
                        .frame(width: AppTheme.minimumTapSize, height: AppTheme.minimumTapSize, alignment: .top)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(agreementAccepted ? "已阅读并同意相关协议" : "请阅读并同意相关协议")
                Text("我已阅读并同意")
                    .font(.system(size: AppTheme.captionSize))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.top, 3)
                Menu {
                    Button("用户协议") { legalDocument = .userAgreement }
                    Button("隐私政策") { legalDocument = .privacy }
                    Button("儿童隐私政策") { legalDocument = .childPrivacy }
                } label: {
                    Text("用户协议与隐私政策")
                        .font(.system(size: AppTheme.captionSize, weight: .semibold))
                        .foregroundStyle(ReferenceColor.blue)
                        .padding(.top, 3)
                }
                .accessibilityLabel("查看用户协议、隐私政策和儿童隐私政策")
                Spacer(minLength: 0)
            }

            Label("儿童信息按监护关系授权使用", systemImage: "lock.shield.fill")
                .font(.system(size: AppTheme.captionSize, weight: .medium))
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(AppTheme.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.85), lineWidth: 1))
        .shadow(color: ReferenceColor.navy.opacity(0.10), radius: 24, y: 12)
    }

    private var landscape: some View {
        Image("CampusFooter")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .padding(.horizontal, 16)
            .clipped()
    }

    private func submitLogin() {
        guard agreementAccepted else { validationMessage = "请先阅读并同意用户协议和儿童隐私政策。"; return }
        if method == .wechat {
            if state.usesRemoteDataSource {
                Task {
                    guard let url = await state.beginWechatAuthorization() else { return }
                    openURL(url)
                }
            } else {
                Task { await state.login(phone: "wechat_authorization", verificationCode: nil, password: nil) }
            }
            return
        }
        if method == .phone {
            guard phone.filter(\.isNumber).count == 11 else { validationMessage = "请输入有效的 11 位手机号。"; return }
            guard codeSent else { validationMessage = "请先获取短信验证码。"; return }
            guard verificationCode.count == 6 else { validationMessage = "请输入 6 位短信验证码。"; return }
        } else {
            guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validationMessage = "请输入账号或手机号。"; return }
            guard password.count >= 8 else { validationMessage = "密码至少需要 8 位。"; return }
        }
        Task { await state.login(phone: method == .phone ? phone : account, verificationCode: method == .phone ? verificationCode : nil, password: method == .account ? password : nil) }
    }

    private func clearLoginError() { validationMessage = nil; state.error = nil }

    /// A verification code belongs to exactly one phone number.  Keeping it
    /// after the number changes made a locally valid code look reusable across
    /// accounts before the real authentication service is connected.
    private func invalidateLoginVerification() {
        clearLoginError()
        guard codeSent || codeCountdown > 0 || !verificationCode.isEmpty else { return }
        codeSent = false
        codeCountdown = 0
        verificationCode = ""
        countdownTask?.cancel()
    }

    private func loginMethodButton(_ title: String, icon: String, color: Color, selected: Bool, showsProgress: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if showsProgress { ProgressView().controlSize(.small).tint(.white) }
                else { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: AppTheme.buttonSize, weight: .semibold))
            .foregroundStyle(selected ? .white : color)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.controlHeight)
            .background(selected ? color : color.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous).stroke(color, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func loginAlternativeButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                .foregroundStyle(selected ? ReferenceColor.blue : AppTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.controlHeight)
                .background(selected ? ReferenceColor.sky : AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous).stroke(selected ? ReferenceColor.blue.opacity(0.35) : AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

}

private struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.content)
                    .font(.body).foregroundStyle(ReferenceColor.navy).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle(document.rawValue)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

}

private enum LoginMethod: String, CaseIterable {
    case wechat, phone, account
}

/// Keeps password verification usable on a phone: users can reveal the value
/// briefly to correct a typo without sacrificing secure entry by default.
private struct PasswordInput: View {
    let title: String
    @Binding var text: String
    @State private var revealed = false

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if revealed { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }
            .textContentType(.password)
            .textFieldStyle(.roundedBorder)
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? "隐藏密码" : "显示密码")
        }
    }
}

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var name = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmed = false
    @State private var error: String?
    @State private var submitted = false
    @State private var codeSent = false
    @State private var codeSending = false
    @State private var codeCountdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var legalDocument: LegalDocument?
    @State private var accountRole: UserRole = .parent

    var body: some View {
        NavigationStack {
            Form {
                if submitted {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(ReferenceColor.green)
                            Text("注册成功").font(.title3.bold())
                            Text("账号已创建，正在进入\(accountRole.rawValue)工作区。").font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                } else {
                    Section("账号信息") {
                        TextField("姓名", text: $name)
                        TextField("手机号", text: $phone).keyboardType(.phonePad)
                        HStack(spacing: 8) {
                            TextField("短信验证码", text: $code).keyboardType(.numberPad)
                            Button(codeSending ? "发送中…" : codeCountdown > 0 ? "\(codeCountdown)s" : codeSent ? "重新获取" : "获取验证码") {
                                guard phone.filter(\.isNumber).count == 11 else { error = "请先填写 11 位手机号。"; return }
                                codeSending = true
                                Task { @MainActor in
                                    let sent = await state.requestVerificationCode(account: phone, purpose: "register")
                                    codeSending = false
                                    guard sent else { error = state.error ?? "验证码发送失败，请稍后重试。"; return }
                                    codeSent = true
                                    codeCountdown = 60
                                    countdownTask?.cancel()
                                    countdownTask = Task { @MainActor in
                                        while codeCountdown > 0 {
                                            try? await Task.sleep(for: .seconds(1))
                                            guard !Task.isCancelled else { return }
                                            codeCountdown -= 1
                                        }
                                    }
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .disabled(codeCountdown > 0 || codeSending)
                        }
                        PasswordInput("设置密码（至少 8 位）", text: $password)
                    }
                    Section("账户类型") {
                        Label("家庭账户", systemImage: UserRole.parent.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ReferenceColor.navy)
                        Text("用于绑定孩子、查看测评报告与训练计划。教师及学校管理账号由学校管理员创建。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Button { confirmed.toggle() } label: {
                            Label("我已阅读并同意用户协议、隐私政策和儿童隐私政策", systemImage: confirmed ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(confirmed ? ReferenceColor.green : ReferenceColor.navy)
                        Menu {
                            Button("用户协议") { legalDocument = .userAgreement }
                            Button("隐私政策") { legalDocument = .privacy }
                            Button("儿童隐私政策") { legalDocument = .childPrivacy }
                        } label: {
                            Label("分别查看三份协议", systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(ReferenceColor.blue)
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        Button("注册并登录") { register() }
                            .frame(maxWidth: .infinity)
                            .disabled(!confirmed)
                    }
                }
            }
            .navigationTitle("注册账号")
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(submitted ? "完成" : "取消") { dismiss() } } }
            .onChange(of: name) { _, _ in error = nil }
            .onChange(of: phone) { _, _ in invalidateVerification() }
            .onChange(of: code) { _, _ in error = nil }
            .onChange(of: password) { _, _ in error = nil }
            .onChange(of: confirmed) { _, _ in error = nil }
        }
        .sheet(item: $legalDocument) { document in LegalDocumentView(document: document) }
        .onChange(of: state.profile?.id) { _, profileID in
            if submitted, profileID != nil { dismiss() }
        }
        .onDisappear { countdownTask?.cancel() }
        .onChange(of: state.error) { _, message in
            if submitted, let message {
                submitted = false
                error = message
            }
        }
    }

    private func register() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请输入姓名。"; return }
        guard phone.filter(\.isNumber).count == 11 else { error = "请输入有效的 11 位手机号。"; return }
        guard codeSent else { error = "请先获取短信验证码。"; return }
        guard code.count == 6 else { error = "请输入 6 位短信验证码。"; return }
        guard password.count >= 8 else { error = "密码至少需要 8 位。"; return }
        submitted = true
        Task { await state.register(name: name, phone: phone, verificationCode: code, password: password, role: accountRole) }
    }

    private func invalidateVerification() {
        error = nil
        guard codeSent || codeCountdown > 0 || !code.isEmpty else { return }
        codeSent = false
        codeCountdown = 0
        code = ""
        countdownTask?.cancel()
    }
}

struct ResetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var codeSent = false
    @State private var codeSending = false
    @State private var codeCountdown = 0
    @State private var error: String?
    @State private var submitted = false
    @State private var countdownTask: Task<Void, Never>?

    private var verificationHint: String {
        #if DEBUG
        "验证手机号后设置新密码，验证码将通过短信发送。"
        #else
        "验证手机号后设置新密码，验证码将通过短信发送。"
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                if !submitted {
                    Text(verificationHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if submitted {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(ReferenceColor.green)
                            Text("密码已重置").font(.title3.bold())
                            Text("请使用新密码重新登录。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("返回登录") { dismiss() }
                                .buttonStyle(.borderedProminent)
                                .tint(ReferenceColor.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                } else {
                    Section("验证身份") {
                        TextField("手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        HStack(spacing: 8) {
                            TextField("短信验证码", text: $code)
                                .keyboardType(.numberPad)
                            Button(codeSending ? "发送中…" : codeCountdown > 0 ? "\(codeCountdown)s" : codeSent ? "重新获取" : "获取验证码") {
                                sendCode()
                            }
                            .font(.caption.weight(.semibold))
                            .disabled(codeCountdown > 0 || codeSending)
                        }
                    }
                    Section("设置新密码") {
                        PasswordInput("新密码（至少 8 位）", text: $password)
                        PasswordInput("再次输入新密码", text: $confirmation)
                    }
                    if let error {
                        Section { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                    Section {
                        Button("确认重置密码") { reset() }
                            .frame(maxWidth: .infinity)
                            .disabled(phone.filter(\.isNumber).count != 11 || !codeSent || code.count != 6 || password.count < 8 || confirmation.isEmpty)
                    }
                }
            }
            .navigationTitle("忘记密码")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(submitted ? "完成" : "取消") { dismiss() }
                }
            }
            .onChange(of: phone) { _, _ in invalidateVerification() }
            .onChange(of: code) { _, _ in error = nil }
            .onChange(of: password) { _, _ in error = nil }
            .onChange(of: confirmation) { _, _ in error = nil }
        }
        .onDisappear { countdownTask?.cancel() }
    }

    private func sendCode() {
        guard phone.filter(\.isNumber).count == 11 else {
            error = "请输入有效的 11 位手机号。"
            return
        }
        error = nil
        codeSending = true
        Task { @MainActor in
            let sent = await state.requestVerificationCode(account: phone, purpose: "reset-password")
            codeSending = false
            guard sent else { error = state.error ?? "验证码发送失败，请稍后重试。"; return }
            codeSent = true
            codeCountdown = 60
            countdownTask?.cancel()
            countdownTask = Task { @MainActor in
                while codeCountdown > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    codeCountdown -= 1
                }
            }
        }
    }

    private func reset() {
        guard phone.filter(\.isNumber).count == 11 else { error = "请输入有效的 11 位手机号。"; return }
        guard codeSent else { error = "请先获取短信验证码。"; return }
        guard code.count == 6 else { error = "请输入 6 位短信验证码。"; return }
        guard password.count >= 8 else { error = "新密码至少需要 8 位。"; return }
        guard password == confirmation else { error = "两次输入的密码不一致。"; return }
        error = nil
        Task {
            if await state.resetPassword(phone: phone, verificationCode: code, password: password) {
                submitted = true
            } else {
                error = state.error ?? "密码重置失败，请稍后重试。"
            }
        }
    }

    private func invalidateVerification() {
        error = nil
        guard codeSent || codeCountdown > 0 || !code.isEmpty else { return }
        codeSent = false
        codeCountdown = 0
        code = ""
        countdownTask?.cancel()
    }
}

struct RoleSelectView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var visible = false
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "F5FAFF"), .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.sectionSpacing) {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(ReferenceColor.blue)
                            .accessibilityHidden(true)
                        Text("选择工作台")
                            .font(.system(size: AppTheme.pageTitleSize, weight: .bold))
                            .foregroundStyle(ReferenceColor.navy)
                        Text("仅显示当前账号已获得授权的入口")
                            .font(.system(size: AppTheme.secondarySize))
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 52)

                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(ReferenceColor.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.activeDisplayName)
                                .font(.system(size: AppTheme.bodySize, weight: .semibold))
                                .foregroundStyle(ReferenceColor.navy)
                            Text("账号权限已验证")
                                .font(.system(size: AppTheme.captionSize))
                                .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous).stroke(AppTheme.divider, lineWidth: 1))

                    VStack(spacing: AppTheme.cardSpacing) {
                        if isRoleAvailable(.parent) {
                            roleEntry(icon: "house.fill", title: "家庭端", detail: "查看孩子测评、健康档案与训练计划", color: ReferenceColor.blue, role: .parent)
                                .offset(y: visible ? 0 : 14).opacity(visible ? 1 : 0)
                        }
                        if isRoleAvailable(.teacher) {
                            roleEntry(icon: "building.2.fill", title: "学校端", detail: "管理授权班级、任务与学生状态", color: ReferenceColor.blue, role: .teacher)
                                .offset(y: visible ? 0 : 14).opacity(visible ? 1 : 0)
                        }
                        if !isRoleAvailable(.parent) && !isRoleAvailable(.teacher) && isRoleAvailable(.principal) {
                            Button {
                                if state.selectRole(.principal) { router.start(.principal) }
                            } label: {
                                Label("查看学校后台说明", systemImage: "chart.bar.xaxis")
                                    .font(.system(size: AppTheme.buttonSize, weight: .semibold))
                                    .frame(maxWidth: .infinity).frame(height: AppTheme.controlHeight)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ReferenceColor.blue)
                        }
                    }

                    Label("学校管理数据看板通过电脑端后台提供", systemImage: "desktopcomputer")
                        .font(.system(size: AppTheme.captionSize, weight: .medium))
                        .foregroundStyle(AppTheme.muted)

                    Button {
                        state.switchAccount()
                        router.reset()
                    } label: {
                        Text("退出当前账号")
                            .font(.system(size: AppTheme.secondarySize, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                            .frame(minHeight: AppTheme.minimumTapSize)
                    }

                    Spacer(minLength: 24)
                    Image("CampusFooter")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 480)
                        .frame(height: 92)
                        .clipped()
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 16)
            }
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { visible = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { visible = true }
        }
    }

    private func isRoleAvailable(_ role: UserRole) -> Bool {
        state.profile?.availableRoles.contains(role) == true
    }

    private func roleEntry(icon: String, title: String, detail: String, color: Color, role: UserRole) -> some View {
        return Button {
            if state.selectRole(role) { router.start(role) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: AppTheme.sectionTitleSize, weight: .bold))
                        .foregroundStyle(ReferenceColor.navy)
                    Text(detail)
                        .font(.system(size: AppTheme.secondarySize))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            .padding(AppTheme.cardPadding)
            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
            .shadow(color: ReferenceColor.navy.opacity(0.06), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }
}

struct BackendDashboardNoticeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.openURL) private var openURL
    @State private var openError: String?

    private var adminURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String else { return nil }
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard base.hasPrefix("https://"), base.lowercased() != "https://api.example.com" else { return nil }
        return URL(string: "\(base)/admin")
    }

    var body: some View {
        AppScaffold(title: "学校管理看板") {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(ReferenceColor.blue)
                Text("学校管理数据看板已迁移至后台系统")
                    .font(.title3.bold())
                    .foregroundStyle(ReferenceColor.navy)
                    .multilineTextAlignment(.center)
                Text("校长端不再作为移动端工作台提供。学校总览、年级对比、班级完成率和风险学生数据，请在学校后台数据看板中查看。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(adminURL == nil ? "后台地址待配置" : "打开学校管理后台") {
                    guard let adminURL else {
                        openError = "当前版本尚未配置学校后台地址，请联系平台管理员。"
                        return
                    }
                    openURL(adminURL) { accepted in
                        if !accepted { openError = "无法打开学校后台，请稍后重试。" }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(adminURL == nil)
                if let openError {
                    Text(openError).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button("返回角色选择") {
                    // A principal account must never be silently converted to
                    // a teacher session just because the mobile dashboard is
                    // unavailable.  Returning to role selection preserves
                    // backend authority and lets an eligible account choose a
                    // permitted mobile workbench explicitly.
                    state.chooseAnotherRole()
                    router.reset()
                }
                .buttonStyle(.borderedProminent)
                Button("退出当前账号") {
                    state.switchAccount()
                    router.reset()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 72)
        }
    }
}
