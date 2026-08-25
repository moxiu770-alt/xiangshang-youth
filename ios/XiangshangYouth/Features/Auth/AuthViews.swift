import SwiftUI
import UIKit

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
        .onAppear {
            // The storyboard owns the first frame, while SwiftUI owns the
            // timed poster. Keep both frames free of time/signal overlays.
            UIApplication.shared.setStatusBarHidden(true, with: .none)
        }
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
            UIApplication.shared.setStatusBarHidden(false, with: .fade)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            LinearGradient(colors: [Color(hex: "76B8F7"), Color(hex: "EEF8FF")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle().fill(.white.opacity(0.13)).frame(width: 420).offset(x: 175, y: -290)

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    // A phone reference layout should not stretch into a desktop-width
                    // form on iPad. Keep the readable mobile composition centered;
                    // the additional minimum height is iPad-only so the supplied phone
                    // layout and its top rhythm remain unchanged.
                    VStack(spacing: 0) {
                        VStack(spacing: 7) {
                            Text("向上少年")
                                .font(.system(size: 31, weight: .heavy))
                            Text("身心健康智慧平台")
                                .font(.system(size: 25, weight: .heavy))
                            Text("学校体测 · 家庭健康记录 · 成长训练")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ReferenceColor.yellow)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(.white.opacity(0.18), in: Capsule())
                        }
                        .foregroundStyle(.white)
                        .padding(.top, 30)
                        .padding(.bottom, 12)

                        // The reference login composition uses the white account
                        // panel as the main visual block.  On modern tall phones a
                        // content-sized card left a large dead gap before the
                        // campus artwork, so reserve proportional panel height and
                        // let its agreement row settle near the lower edge.
                        // Keep the agreement visible without turning tall-phone
                        // login cards into a large empty white panel.
                        // Keep the card tall enough for all login methods, but
                        // avoid a dead band before the campus illustration on
                        // modern 6.3-inch/tall iPhones.
                        loginPanel(minHeight: horizontalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize ? proxy.size.height * 0.46 : 0)
                        Spacer(minLength: 4)
                        landscape
                    }
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: horizontalSizeClass == .regular ? proxy.size.height : nil, alignment: .center)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onDisappear { countdownTask?.cancel() }
        .sheet(isPresented: $registerPresented) { RegisterView() }
        .sheet(isPresented: $resetPasswordPresented) { ResetPasswordView() }
        .sheet(item: $legalDocument) { document in LegalDocumentView(document: document) }
    }

    private func loginPanel(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Spacer()
                Text("欢迎登录").font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                Spacer()
            }
            VStack(spacing: 8) {
                loginMethodButton(state.loading && method == .wechat ? "正在授权…" : "微信登录", icon: "message.fill", color: ReferenceColor.blue, selected: method == .wechat, showsProgress: state.loading && method == .wechat) {
                    if method == .wechat { submitLogin() }
                    else { method = .wechat; clearLoginError() }
                }
                loginMethodButton("手机号登录", icon: "iphone", color: ReferenceColor.blue, selected: method == .phone) { method = .phone; clearLoginError() }
                loginMethodButton("账号密码登录", icon: "person.crop.circle", color: ReferenceColor.yellow, selected: method == .account) { method = .account; clearLoginError() }
            }
            .disabled(state.loading)
            if method == .phone {
                TextField("手机号", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: phone) { _, _ in invalidateLoginVerification() }
                HStack(spacing: 8) {
                    TextField("短信验证码", text: $verificationCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: verificationCode) { _, _ in clearLoginError() }
                    Button(codeSending ? "发送中…" : codeCountdown > 0 ? "\(codeCountdown)s 后重试" : codeSent ? "重新获取" : "获取验证码") {
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ReferenceColor.blue)
                    .disabled(codeCountdown > 0 || codeSending)
                }
            } else if method == .account {
                TextField("账号 / 手机号", text: $account)
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: account) { _, _ in clearLoginError() }
                PasswordInput("登录密码（至少 8 位）", text: $password)
                    .onChange(of: password) { _, _ in clearLoginError() }
            }
            if method != .wechat {
                Button(action: submitLogin) {
                    Group {
                        if state.loading { HStack(spacing: 8) { ProgressView().tint(.white); Text("正在登录…") } }
                        else { Label("登录", systemImage: "arrow.right.circle.fill") }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(ReferenceColor.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(state.loading)
            }
            if let message = validationMessage ?? state.error {
                Text(message).font(.system(size: 12)).foregroundStyle(.red)
            }
            HStack {
                Button { registerPresented = true } label: { Text("家长注册").foregroundStyle(ReferenceColor.blue) }
                Spacer()
                Button { resetPasswordPresented = true } label: { Text("忘记密码？").foregroundStyle(.secondary) }
            }
            .font(.system(size: 11, weight: .semibold))
            VStack(alignment: .leading, spacing: 9) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text("登录后可查看孩子的测评、健康记录和训练建议。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    check("学校体测结果", "查看测评任务与报告")
                    check("家庭健康记录", "完成居家观察与身体测评")
                    check("成长训练建议", "按孩子报告安排每日训练")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                Button { agreementAccepted.toggle() } label: {
                    Label(agreementAccepted ? "已阅读并同意相关协议" : "请阅读并同意相关协议", systemImage: agreementAccepted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12)).foregroundStyle(agreementAccepted ? ReferenceColor.green : .secondary)
                }.buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("用户协议") { legalDocument = .userAgreement }
                    Button("隐私政策") { legalDocument = .privacy }
                    Button("儿童隐私政策") { legalDocument = .childPrivacy }
                } label: {
                    Text("查看协议")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReferenceColor.blue)
                }
                .accessibilityLabel("查看用户协议、隐私政策和儿童隐私政策")
            }
        }
        .padding(20)
        .frame(minHeight: minHeight, alignment: .top)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 10)
        .shadow(color: ReferenceColor.blue.opacity(0.08), radius: 12, y: 4)
    }

    private var landscape: some View {
        Image("CampusFooter")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .padding(.horizontal, 3)
            .padding(.bottom, 3)
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
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(selected ? .white : color)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(selected ? color : color.opacity(0.07), in: Capsule())
            .overlay(Capsule().stroke(color, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func check(_ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(ReferenceColor.green, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

private enum LegalDocument: String, Identifiable {
    case userAgreement = "用户协议"
    case privacy = "隐私政策"
    case childPrivacy = "儿童隐私政策"
    var id: String { rawValue }
}

private struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.body).foregroundStyle(ReferenceColor.navy).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle(document.rawValue)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private var content: String {
        switch document {
        case .userAgreement:
            return "《用户协议》\n\n一、服务范围\n向上少年为学校、教师、家长提供学生运动能力记录、测评报告、训练建议和通知服务。账号仅限本人使用，不得转让、出租或用于批量抓取数据。\n\n二、账号与安全\n请使用真实、可验证的手机号或学校提供的账号。你应妥善保管验证码、密码和设备，发现异常登录应立即联系学校管理员。\n\n三、学校数据\n学校体测成绩、报告及任务状态由学校授权人员和合规体测场地端录入。家长可以查看已绑定孩子的数据，不得访问其他学生信息。\n\n四、服务边界\n平台提供运动能力筛查和训练建议，不构成医疗诊断、治疗或急救意见。出现身体不适时应停止训练并咨询专业人员。\n\n五、联系我们\n账号、数据或未成年人权益问题，请联系所属学校管理员或平台客服。"
        case .privacy:
            return "《隐私政策》\n\n我们仅在提供学校运动管理、测评报告、训练反馈和消息通知所必需的范围内处理账号、学校关系、设备日志及健康测评数据。\n\n健康数据包括身高、体重、BMI、姿态指标、运动成绩和报告。处理前会展示用途并记录家长同意；数据按学校授权范围访问，传输使用加密连接，敏感凭证保存在系统安全存储中。\n\n我们不会出售儿童数据。服务商仅在完成存储、消息或运维任务所需范围内处理数据，并受合同和访问审计约束。\n\n家长可查看、导出、更正或申请删除已绑定孩子的数据。删除申请会先完成身份与学校关系核验，完成后健康记录、成绩和绑定关系会被清理或匿名化。"
        case .childPrivacy:
            return "《儿童隐私政策》\n\n本平台面向未成年人提供服务。儿童账号和健康测评由家长、学校或依法授权的工作人员管理，儿童本人不需要独立提供可识别信息。\n\n我们只收集完成运动测评、报告和训练所需的最少信息，不使用儿童数据进行个性化广告或与服务无关的画像。姿态采集用于生成测评指标，原始影像按学校配置的保存期限处理，并设置访问审计。\n\n家长可以随时撤回同意、查询处理记录、申请导出或删除。若撤回同意，相关测评和训练功能可能无法继续，但不会影响已完成服务之外的其他权益。\n\n如发现儿童信息被误用，请联系学校管理员或平台客服，我们会优先处理。"
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
            LinearGradient(colors: [.white, ReferenceColor.sky], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Text("请选择进入方式").font(.system(size: 18, weight: .bold)).foregroundStyle(ReferenceColor.blue)
                    Image(systemName: "sun.max.fill").foregroundStyle(ReferenceColor.yellow)
                    Spacer()
                }
                .padding(.top, 45)
                if isRoleAvailable(.parent) {
                    roleEntry(icon: "house.fill", title: "家庭端", detail: "家长查看孩子测评与成长建议", color: ReferenceColor.blue, role: .parent)
                        .offset(x: visible ? 0 : -28).opacity(visible ? 1 : 0)
                }
                if isRoleAvailable(.teacher) {
                    roleEntry(icon: "building.2.fill", title: "学校端", detail: "教师管理班级测评与学生状态", color: .white, role: .teacher)
                        .offset(x: visible ? 0 : 28).opacity(visible ? 1 : 0)
                }
                if !isRoleAvailable(.parent) && !isRoleAvailable(.teacher) && isRoleAvailable(.principal) {
                    Button {
                        if state.selectRole(.principal) { router.start(.principal) }
                    } label: {
                        Label("进入学校后台管理看板", systemImage: "chart.bar.xaxis")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReferenceColor.blue)
                    .offset(y: visible ? 0 : 12).opacity(visible ? 1 : 0)
                }
                Text("学校管理数据看板由后台系统提供")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Button {
                    state.switchAccount()
                    router.reset()
                } label: {
                    Text("退出当前账号").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Image("CampusFooter")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .padding(.bottom, 4)
                    .clipped()
            }
            .padding(.horizontal, 19)
            // Keep role cards at the same readable portrait width as LoginView
            // when the app is presented on iPad.
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
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
        let outlined = role == .teacher
        return Button {
            if state.selectRole(role) { router.start(role) }
        } label: {
            HStack(spacing: 18) {
                Group {
                    if role == .parent {
                        Image("FamilyEntrance").resizable().scaledToFit().padding(4)
                    } else {
                        Image("SchoolEntrance").resizable().scaledToFit().padding(4)
                    }
                }
                .frame(width: 64, height: 64)
                .background(outlined ? ReferenceColor.sky : Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .scaleEffect(visible ? 1 : 0.72)
                .rotationEffect(.degrees(visible ? 0 : (role == .parent ? -7 : 7)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(outlined ? ReferenceColor.blue : Color.white)
                    Text(detail).font(.system(size: 12)).foregroundStyle(outlined ? .secondary : Color.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .bold)).foregroundStyle(outlined ? ReferenceColor.yellow : Color.white)
            }
            .padding(17)
            .background(color, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ReferenceColor.yellow.opacity(outlined ? 1 : 0), lineWidth: 1))
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
