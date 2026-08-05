import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var state: AppState
    @State private var breathes = false

    var body: some View {
        ZStack {
            Color(hex: "7452A5").ignoresSafeArea()
            Image("LaunchPoster")
                .resizable()
                .scaledToFill()
                .scaleEffect(breathes ? 1.025 : 1)
                .ignoresSafeArea()
        }
        .statusBarHidden(true)
        .task {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breathes = true
            }
            try? await Task.sleep(for: .seconds(2.0))
            withAnimation(.easeOut(duration: 0.28)) {
                state.dismissSplash()
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @State private var phone = ""
    @State private var account = ""
    @State private var password = ""
    @State private var verificationCode = ""
    // The reference login screen leads with WeChat authorization; phone and
    // account/password remain one-tap alternatives below it.
    @State private var method: LoginMethod = .wechat
    @State private var agreementAccepted = false
    @State private var codeSent = false
    @State private var codeCountdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var validationMessage: String?
    @State private var registerPresented = false
    @State private var landscapeDrifts = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "76B8F7"), Color(hex: "EEF8FF")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle().fill(.white.opacity(0.13)).frame(width: 420).offset(x: 175, y: -290)

            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    Text("向上少年")
                        .font(.system(size: 31, weight: .heavy))
                    Text("身心健康智慧平台")
                        .font(.system(size: 25, weight: .heavy))
                    Text("科学评估 · 精准干预 · 守护3-18岁青少年身心健康")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ReferenceColor.yellow)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.top, 30)
                .padding(.bottom, 12)

                loginPanel
                Spacer(minLength: 12)
                landscape
            }
            .padding(.bottom, 8)
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) { landscapeDrifts = true }
        }
        .onDisappear { countdownTask?.cancel() }
        .sheet(isPresented: $registerPresented) { RegisterView() }
    }

    private var loginPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Spacer()
                Text("登录开启成长之旅").font(.system(size: 14, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                Image(systemName: "sun.max.fill").foregroundStyle(ReferenceColor.yellow)
                Spacer()
            }
            VStack(spacing: 8) {
                loginMethodButton("微信登录", icon: "message.fill", color: ReferenceColor.blue, selected: method == .wechat) { method = .wechat; clearLoginError() }
                loginMethodButton("手机号登录", icon: "iphone", color: ReferenceColor.blue, selected: method == .phone) { method = .phone; clearLoginError() }
                loginMethodButton("账号密码登录", icon: "person.crop.circle", color: ReferenceColor.yellow, selected: method == .account) { method = .account; clearLoginError() }
            }
            .accessibilityElement(children: .contain)
            if method == .phone {
                TextField("手机号", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: phone) { _, _ in clearLoginError() }
                HStack(spacing: 8) {
                    TextField("短信验证码", text: $verificationCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button(codeCountdown > 0 ? "\(codeCountdown)s 后重试" : codeSent ? "重新获取" : "获取验证码") {
                        guard phone.filter(\.isNumber).count == 11 else { validationMessage = "请先填写 11 位手机号。"; return }
                        codeSent = true
                        verificationCode = "1234"
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ReferenceColor.blue)
                    .disabled(codeCountdown > 0)
                }
            } else if method == .account {
                TextField("账号 / 手机号", text: $account)
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: account) { _, _ in clearLoginError() }
                SecureField("登录密码（至少 6 位）", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: password) { _, _ in clearLoginError() }
            }
            Button(action: submitLogin) {
                Group {
                    if state.loading {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text("正在登录…") }
                    } else {
                        Label(method == .wechat ? "微信授权登录" : "登录", systemImage: method == .wechat ? "checkmark.shield.fill" : "arrow.right.circle.fill")
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(ReferenceColor.blue, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(state.loading)
            if let message = validationMessage ?? state.error {
                Text(message).font(.system(size: 10)).foregroundStyle(.red)
            }
            HStack {
                Button { registerPresented = true } label: { Text("注册新账号").foregroundStyle(ReferenceColor.blue) }
                Spacer()
                Button { validationMessage = "请联系学校管理员重置密码，或使用短信验证码登录。" } label: { Text("忘记密码？").foregroundStyle(.secondary) }
            }
            .font(.system(size: 11, weight: .semibold))
            VStack(alignment: .leading, spacing: 9) {
                check("专业身心测评与科学健康干预", "体质评估 · 科学干预")
                check("提供专属解决方案", "成长规划 · 定制方案")
                check("全程跟踪辅导", "专家护航 · 全程陪伴")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            Button {
                agreementAccepted.toggle()
            } label: {
                Label(agreementAccepted ? "已阅读并同意《用户协议》《隐私政策》《儿童隐私政策》" : "请阅读并同意《用户协议》《隐私政策》《儿童隐私政策》", systemImage: agreementAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9)).foregroundStyle(agreementAccepted ? ReferenceColor.green : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 10)
        .shadow(color: ReferenceColor.blue.opacity(0.08), radius: 12, y: 4)
    }

    private var landscape: some View {
        Image("CampusFooter")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .padding(.horizontal, 3)
            .padding(.bottom, 3)
            .scaleEffect(landscapeDrifts ? 1.035 : 1)
            .offset(x: landscapeDrifts ? -4 : 4)
            .clipped()
    }

    private func submitLogin() {
        guard agreementAccepted else { validationMessage = "请先阅读并同意用户协议和儿童隐私政策。"; return }
        if method == .wechat {
            Task { await state.login(phone: "wechat_mock") }
            return
        }
        if method == .phone {
            guard phone.filter(\.isNumber).count == 11 else { validationMessage = "请输入有效的 11 位手机号。"; return }
            guard verificationCode.count >= 4 else { validationMessage = "请输入短信验证码。"; return }
        } else {
            guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validationMessage = "请输入账号或手机号。"; return }
            guard password.count >= 6 else { validationMessage = "密码至少需要 6 位。"; return }
        }
        Task { await state.login(phone: method == .phone ? phone : account) }
    }

    private func clearLoginError() { validationMessage = nil; state.error = nil }

    private func loginMethodButton(_ title: String, icon: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? .white : color)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
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
                Text(subtitle).font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }
}

private enum LoginMethod: String, CaseIterable {
    case wechat, phone, account
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
    @State private var codeCountdown = 0
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if submitted {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(ReferenceColor.green)
                            Text("注册成功").font(.title3.bold())
                            Text("账号已创建，正在进入角色选择。").font(.footnote).foregroundStyle(.secondary)
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
                            Button(codeCountdown > 0 ? "\(codeCountdown)s" : code.isEmpty ? "获取验证码" : "重新获取") {
                                guard phone.filter(\.isNumber).count == 11 else { error = "请先填写 11 位手机号。"; return }
                                code = "1234"
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
                            .font(.caption.weight(.semibold))
                            .disabled(codeCountdown > 0)
                        }
                        SecureField("设置密码（至少 6 位）", text: $password)
                    }
                    Section {
                        Button { confirmed.toggle() } label: {
                            Label("我已阅读并同意用户协议、隐私政策和儿童隐私政策", systemImage: confirmed ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(confirmed ? ReferenceColor.green : ReferenceColor.navy)
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        Button("注册并登录") { register() }
                            .frame(maxWidth: .infinity)
                            .disabled(!confirmed)
                    }
                }
            }
            .navigationTitle("注册账号")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(submitted ? "完成" : "取消") { dismiss() } } }
        }
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
        guard code.count >= 4 else { error = "请输入短信验证码。"; return }
        guard password.count >= 6 else { error = "密码至少需要 6 位。"; return }
        submitted = true
        Task { await state.login(phone: phone) }
    }
}

struct RoleSelectView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var visible = false
    @State private var landscapeDrifts = false

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
                roleEntry(icon: "house.fill", title: "家庭端", detail: "家长查看孩子测评与成长建议", color: ReferenceColor.blue, role: .parent)
                    .offset(x: visible ? 0 : -28).opacity(visible ? 1 : 0)
                roleEntry(icon: "building.2.fill", title: "学校端", detail: "教师与校长管理班级健康数据", color: .white, role: .teacher)
                    .offset(x: visible ? 0 : 28).opacity(visible ? 1 : 0)
                roleEntry(icon: "chart.bar.xaxis", title: "校长端", detail: "查看学校总览、年级对比与风险学生", color: ReferenceColor.navy, role: .principal)
                    .offset(y: visible ? 0 : 20).opacity(visible ? 1 : 0)
                Button {
                    state.switchAccount()
                    router.path = NavigationPath()
                } label: {
                    Text("退出当前账号").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Image("CampusFooter")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 132)
                    .padding(.bottom, 4)
                    .scaleEffect(landscapeDrifts ? 1.035 : 1)
                    .offset(x: landscapeDrifts ? -4 : 4)
                    .clipped()
            }
            .padding(.horizontal, 19)
        }
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { visible = true }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) { landscapeDrifts = true }
        }
    }

    private func roleEntry(icon: String, title: String, detail: String, color: Color, role: UserRole) -> some View {
        let outlined = role == .teacher
        return Button { state.selectRole(role); router.start(role) } label: {
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
                    Text(detail).font(.system(size: 10)).foregroundStyle(outlined ? .secondary : Color.white.opacity(0.85))
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
