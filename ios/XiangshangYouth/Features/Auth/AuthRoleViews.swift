import SwiftUI

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
                        Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 48, weight: .semibold)).foregroundStyle(ReferenceColor.blue).accessibilityHidden(true)
                        Text("选择工作台").font(.system(size: AppTheme.pageTitleSize, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                        Text("仅显示当前账号已获得授权的入口").font(.system(size: AppTheme.secondarySize)).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
                    }.padding(.top, 52)
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(ReferenceColor.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.activeDisplayName).font(.system(size: AppTheme.bodySize, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
                            Text("账号权限已验证").font(.system(size: AppTheme.captionSize)).foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous).stroke(AppTheme.divider, lineWidth: 1))
                    VStack(spacing: AppTheme.cardSpacing) {
                        if isRoleAvailable(.parent) { roleEntry(icon: "house.fill", title: "家庭端", detail: "查看孩子测评、健康档案与训练计划", color: ReferenceColor.blue, role: .parent).offset(y: visible ? 0 : 14).opacity(visible ? 1 : 0) }
                        if isRoleAvailable(.teacher) { roleEntry(icon: "building.2.fill", title: "学校端", detail: "管理授权班级、任务与学生状态", color: ReferenceColor.blue, role: .teacher).offset(y: visible ? 0 : 14).opacity(visible ? 1 : 0) }
                        if !isRoleAvailable(.parent) && !isRoleAvailable(.teacher) && isRoleAvailable(.principal) {
                            Button { if state.selectRole(.principal) { router.start(.principal) } } label: {
                                Label("查看学校后台说明", systemImage: "chart.bar.xaxis").font(.system(size: AppTheme.buttonSize, weight: .semibold)).frame(maxWidth: .infinity).frame(height: AppTheme.controlHeight)
                            }.buttonStyle(.borderedProminent).tint(ReferenceColor.blue)
                        }
                    }
                    Label("学校管理数据看板通过电脑端后台提供", systemImage: "desktopcomputer").font(.system(size: AppTheme.captionSize, weight: .medium)).foregroundStyle(AppTheme.muted)
                    Button { state.switchAccount(); router.reset() } label: {
                        Text("退出当前账号").font(.system(size: AppTheme.secondarySize, weight: .semibold)).foregroundStyle(AppTheme.muted).frame(minHeight: AppTheme.minimumTapSize)
                    }
                    Spacer(minLength: 24)
                    Image("CampusFooter").resizable().scaledToFit().frame(maxWidth: 480).frame(height: 92).clipped()
                }
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.pagePadding).padding(.bottom, 16)
            }
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { visible = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { visible = true }
        }
    }

    private func isRoleAvailable(_ role: UserRole) -> Bool { state.profile?.availableRoles.contains(role) == true }

    private func roleEntry(icon: String, title: String, detail: String, color: Color, role: UserRole) -> some View {
        Button { if state.selectRole(role) { router.start(role) } } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(color).frame(width: 52, height: 52).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: AppTheme.sectionTitleSize, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                    Text(detail).font(.system(size: AppTheme.secondarySize)).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            }
            .padding(AppTheme.cardPadding)
            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
            .shadow(color: ReferenceColor.navy.opacity(0.06), radius: 12, y: 5)
        }.buttonStyle(.plain)
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
                Image(systemName: "chart.bar.xaxis").font(.system(size: 54, weight: .semibold)).foregroundStyle(ReferenceColor.blue)
                Text("学校管理数据看板已迁移至后台系统").font(.title3.bold()).foregroundStyle(ReferenceColor.navy).multilineTextAlignment(.center)
                Text("校长端不再作为移动端工作台提供。学校总览、年级对比、班级完成率和风险学生数据，请在学校后台数据看板中查看。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(adminURL == nil ? "后台地址待配置" : "打开学校管理后台") {
                    guard let adminURL else { openError = "当前版本尚未配置学校后台地址，请联系平台管理员。"; return }
                    openURL(adminURL) { accepted in if !accepted { openError = "无法打开学校后台，请稍后重试。" } }
                }.buttonStyle(.borderedProminent).disabled(adminURL == nil)
                if let openError { Text(openError).font(.subheadline).foregroundStyle(.red).multilineTextAlignment(.center) }
                Button("返回角色选择") { state.chooseAnotherRole(); router.reset() }.buttonStyle(.borderedProminent)
                Button("退出当前账号") { state.switchAccount(); router.reset() }.buttonStyle(.bordered)
            }.frame(maxWidth: 460).frame(maxWidth: .infinity).padding(.vertical, 72)
        }
    }
}
