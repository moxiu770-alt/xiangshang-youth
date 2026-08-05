import SwiftUI

/// Assessment flow preserves the production route boundary and keeps unfinished entries
/// recoverable before the external systems are connected.
struct AssessmentFlowView: View {
    let category: AssessmentCategory
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var state: AppState
    @State private var step = 0
    @State private var completed = false
    @State private var answer = ""
    @State private var validationMessage: String?
    private var steps: [String] { switch category { case .fitness: ["基础信息", "遗传身高", "脊柱姿态", "运动表现"]; case .vision: ["基础信息", "用眼习惯", "视力筛查"]; case .oral: ["基础信息", "口腔习惯", "口腔筛查"]; case .mental: ["授权登录", "心理问卷", "结果回传"] } }
    var body: some View { ScrollView { VStack(spacing: 14) {
        ParentPageNavigation(title: "\(category.rawValue)测评", showsBack: true)
        VStack(spacing: 8) { Image(systemName: category.icon).font(.system(size: 42, weight: .semibold)).foregroundStyle(category.color).frame(width: 78, height: 78).background(category.color.opacity(0.12), in: Circle()); Text("\(state.selectedChild?.name ?? "王小明")的\(category.rawValue)测评").font(.system(size: 18, weight: .bold)); Text(category == .fitness ? "完成身高、体态与学校运动表现记录" : "请根据孩子最近情况完成本次测评") .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(.top, 14)
        HStack(spacing: 0) { ForEach(steps.indices, id: \.self) { index in VStack(spacing: 5) { Circle().fill(index <= step ? category.color : Color.gray.opacity(0.2)).frame(width: 24, height: 24).overlay { Text("\(index + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(index <= step ? .white : .secondary) }; Text(steps[index]).font(.system(size: 8)).foregroundStyle(index <= step ? category.color : .secondary).lineLimit(1) }.frame(maxWidth: .infinity); if index < steps.count - 1 { Rectangle().fill(index < step ? category.color : Color.gray.opacity(0.2)).frame(height: 2) } } }.padding(.horizontal, 14)
        ReferenceCard { VStack(alignment: .leading, spacing: 10) { Text(completed ? "测评已保存" : steps[step]).font(.system(size: 15, weight: .bold)); Text(description).font(.system(size: 11)).foregroundStyle(.secondary); if !completed { TextField(inputPlaceholder, text: $answer).textFieldStyle(.roundedBorder).onChange(of: answer) { _, value in state.saveDraft(value, key: draftKey) }; Label("内容会自动保存为草稿，可稍后继续。", systemImage: "internaldrive").font(.system(size: 9)).foregroundStyle(.secondary) }; if let validationMessage { Text(validationMessage).font(.system(size: 10)).foregroundStyle(.red) }; if category == .fitness && step == 3 { Label("运动发展测试由学校场地端完成，结果将自动同步至本页。", systemImage: "building.2.crop.circle").font(.system(size: 10)).foregroundStyle(ReferenceColor.blue).padding(9).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 8)) }; if category == .mental && step == 0 { Label("将跳转至第三方心理系统授权登录。", systemImage: "checkmark.shield.fill").font(.system(size: 10)).foregroundStyle(ReferenceColor.purple).padding(9).background(ReferenceColor.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) } }.padding(12) }.padding(.horizontal, 12)
        Button { submitCurrentStep() } label: { Text(completed ? "查看\(category.rawValue)报告" : step == steps.count - 1 ? "完成并保存" : "保存并下一步").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(category.color, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).padding(.horizontal, 16).onChange(of: completed) { _, done in if done, let child = state.selectedChild { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { router.push(.report(child)) } } }
    }.padding(.bottom, 14) }.background(ReferenceColor.canvas).task { answer = state.localFeatures.drafts[draftKey] ?? "" } .onChange(of: step) { _, _ in answer = state.localFeatures.drafts[draftKey] ?? ""; validationMessage = nil } .overlay {
        if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
        else if state.selectedChild == nil { ParentBindingPrompt() }
    } }
    private var description: String { if completed { return "本次测评结果已经保存，并将刷新健康档案。" }; switch category { case .fitness: return ["确认孩子的出生日期、当前身高和体重。", "填写父母身高，系统会计算遗传身高区间。", "按引导上传或记录站立姿态筛查结果。", "选择学校测试完成情况，或暂时跳过等待场地端回传。"][step]; case .vision: return "填写用眼习惯并进行视力筛查结果确认。"; case .oral: return "填写刷牙习惯并确认近期口腔筛查结果。"; case .mental: return "完成授权后，第三方系统将回传测评报告。" } }
    private var draftKey: String { "assessment-\(state.selectedChild?.id ?? "anonymous")-\(category.rawValue)-\(step)" }
    private var inputPlaceholder: String { switch category { case .fitness: return ["例如：身高132cm，体重30kg", "例如：父亲175cm，母亲162cm", "例如：站姿筛查正常", "例如：学校场地端待回传"][step]; case .vision: return "例如：每日屏幕使用不超过1小时"; case .oral: return "例如：每日早晚刷牙，近期无牙痛"; case .mental: return "例如：已阅读并确认授权说明" } }
    private func submitCurrentStep() { guard completed || !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validationMessage = "请填写本步骤信息后再继续。"; return }; if completed { if let child = state.selectedChild { router.push(.report(child)) }; return }; if step < steps.count - 1 { withAnimation { step += 1 } } else { state.clearDrafts(prefix: "assessment-\(state.selectedChild?.id ?? "anonymous")-\(category.rawValue)-"); completed = true; state.completeAssessment(category) } }
}

struct ParentCourseTeaser: View {
    let image: String; let title: String
    @State private var isShown = false
    @State private var isPresented = false
    var body: some View { Button { isPresented = true } label: { VStack(alignment: .leading, spacing: 4) { Image(image).resizable().scaledToFill().frame(height: 48).frame(maxWidth: .infinity).clipped().scaleEffect(isShown ? 1.06 : 1); Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(ReferenceColor.navy); Text("免费学习 ›").font(.system(size: 8)).foregroundStyle(ReferenceColor.green) }.padding(4).background(.white, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).task { withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { isShown = true } }.sheet(isPresented: $isPresented) { CourseDetailSheet(title: title) } }
}

struct ParentArticleRow: View {
    let title: String; let detail: String
    @State private var isPresented = false
    var body: some View { Button { isPresented = true } label: { HStack { Image(systemName: "book.closed.fill").foregroundStyle(ReferenceColor.green).frame(width: 34, height: 34).background(ReferenceColor.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 11, weight: .bold)); Text(detail).font(.system(size: 8)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).sheet(isPresented: $isPresented) { HealthArticleSheet(title: title) } }
}

/// The two missing parent tabs from the supplied information architecture.
/// All cards are actionable and can switch to the remote source without changing the route contract.
struct ParentCoursesDashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedKind = 0
    @State private var selectedCourse: String?
    @State private var catalogShown = false
    private let categories = [("figure.run", "体质", ReferenceColor.blue), ("eye.fill", "视力", ReferenceColor.green), ("mouth.fill", "口腔", ReferenceColor.purple), ("brain.head.profile", "心理", ReferenceColor.pink)]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我的课程")
                ReferenceHeader(name: state.selectedChild?.name ?? "王小明", school: "\(state.selectedChild?.className ?? "三年级2班") · 成长课程", initial: String((state.selectedChild?.name ?? "王").prefix(1)), avatarAsset: "ChildAvatar")
                Picker("课程类型", selection: $selectedKind) { Text("公益课程").tag(0); Text("学校课程").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal, 12)
                ReferenceSectionTitle(title: selectedKind == 0 ? "公益课堂" : "精选学校课程", trailing: "全部课程", action: { catalogShown = true }).padding(.horizontal, 12)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(categories, id: \.1) { icon, title, color in
                        Button { selectedCourse = "\(title)健康成长课程" } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Image(systemName: icon).font(.system(size: 23, weight: .semibold)).foregroundStyle(color)
                                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                                Text(selectedKind == 0 ? "公益 · 立即学习" : "校内课程 · 查看课程").font(.system(size: 9)).foregroundStyle(color)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12)
                Button { selectedCourse = "客服咨询" } label: {
                    HStack { Image(systemName: "message.fill"); VStack(alignment: .leading) { Text("课程咨询").font(.system(size: 12, weight: .bold)); Text("客服老师会在工作时间内回复您").font(.system(size: 9)) }; Spacer(); Image(systemName: "chevron.right") }
                        .foregroundStyle(ReferenceColor.blue).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).padding(.horizontal, 12)
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .overlay {
            if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
            else if state.selectedChild == nil { ParentBindingPrompt() }
        }
        .sheet(item: Binding(get: { selectedCourse.map(CourseSheetItem.init) }, set: { selectedCourse = $0?.name })) { item in
            CourseDetailSheet(title: item.name)
        }
        .sheet(isPresented: $catalogShown) {
            CourseCatalogSheet(kind: selectedKind == 0 ? "公益课堂" : "精选学校课程")
        }
    }
}

private struct CourseCatalogSheet: View {
    let kind: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCourse: String?
    private let courses = ["体质成长课", "视力守护课", "口腔健康课", "心理舒展课"]

    var body: some View {
        NavigationStack {
            List {
                Section(kind) {
                    ForEach(courses, id: \.self) { course in
                        Button { selectedCourse = course } label: {
                            Label(course, systemImage: "play.circle.fill")
                                .foregroundStyle(ReferenceColor.navy)
                        }
                    }
                }
            }
            .navigationTitle("课程目录")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(item: Binding(get: { selectedCourse.map(CourseSheetItem.init) }, set: { selectedCourse = $0?.name })) { item in
                CourseDetailSheet(title: item.name)
            }
        }
    }
}

struct ParentClassCircleDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var isComposerShown = false
    @State private var selectedMoment: String?
    @State private var editingPost: ClassPostDraft?
    @State private var commentPostID: UUID?
    @State private var commentDraft = ""
    @State private var commentSubmitted = false
    @State private var selectedFilter = "全部"
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "班级圈")
                ReferenceHeader(name: state.selectedChild?.name ?? "王小明", school: "\(state.selectedChild?.className ?? "三年级2班") · 42人", initial: String((state.selectedChild?.name ?? "王").prefix(1)), avatarAsset: "ChildAvatar")
                ReferenceCard {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) { Text("本班家校圈").font(.system(size: 16, weight: .bold)); Text("分享运动成长，和老师保持联系").font(.system(size: 9)).foregroundStyle(.secondary) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) { Text("42").font(.system(size: 20, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text("班级成员").font(.system(size: 8)).foregroundStyle(.secondary) }
                    }
                }.padding(.horizontal, 12)
                HStack(spacing: 8) {
                    ForEach(["全部", "老师动态", "家长分享"], id: \.self) { filter in
                        Button { selectedFilter = filter } label: { Text(filter).font(.system(size: 10, weight: .semibold)).foregroundStyle(selectedFilter == filter ? .white : ReferenceColor.blue).padding(.horizontal, 12).padding(.vertical, 6).background(selectedFilter == filter ? ReferenceColor.blue : ReferenceColor.sky, in: Capsule()) }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(.horizontal, 12)
                Button { isComposerShown = true } label: { Label("发布班级动态", systemImage: "square.and.pencil").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
                let visiblePosts = state.localFeatures.classPosts.filter { post in
                    selectedFilter == "全部" || (selectedFilter == "老师动态" && post.author.contains("老师")) || (selectedFilter == "家长分享" && !post.author.contains("老师"))
                }
                if visiblePosts.isEmpty {
                    circleMockPost(author: "李老师", content: "本周运动打卡已开启，欢迎家长分享孩子的练习瞬间。", isTeacher: true)
                }
                ForEach(visiblePosts) { post in
                    ReferenceCard {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Image(systemName: "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(ReferenceColor.sky); VStack(alignment: .leading, spacing: 1) { Text(post.author).font(.system(size: 11, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text("刚刚发布 · 本班可见").font(.system(size: 8)).foregroundStyle(.secondary) }; Spacer(); if post.author == "王女士" { Button("编辑") { editingPost = post }.font(.system(size: 9, weight: .semibold)).foregroundStyle(ReferenceColor.blue) } }
                            Text(post.content).font(.system(size: 12)).foregroundStyle(ReferenceColor.navy)
                            HStack { Button { state.toggleClassPostLike(post.id) } label: { Label(state.localFeatures.likedClassPostIDs.contains(post.id) ? "已赞" : "点赞", systemImage: state.localFeatures.likedClassPostIDs.contains(post.id) ? "hand.thumbsup.fill" : "hand.thumbsup") }.buttonStyle(.plain); Button { commentSubmitted = false; commentDraft = ""; commentPostID = post.id } label: { Label("评论", systemImage: "bubble.left") }.buttonStyle(.plain); Spacer(); ShareLink(item: post.content) { Label("分享", systemImage: "square.and.arrow.up") } }.font(.system(size: 10, weight: .semibold)).foregroundStyle(state.localFeatures.likedClassPostIDs.contains(post.id) ? ReferenceColor.blue : .secondary)
                        }
                    }.padding(.horizontal, 12)
                }
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ReferenceSectionTitle(title: "班级之星", trailing: "查看全部", action: { selectedMoment = "班级之星榜单" })
                        HStack { star("勤劳之星", "陈乐乐", ReferenceColor.yellow); star("运动之星", state.selectedChild?.name ?? "王小明", ReferenceColor.blue); star("阅读之星", "李安然", ReferenceColor.purple) }
                    }
                }.padding(.horizontal, 12)
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 7) {
                        ReferenceSectionTitle(title: "本月打卡", trailing: "查看记录", action: { selectedMoment = "本月运动打卡记录" })
                        Text("✓  ✓  ✓  ✓  ·  ✓  ✓  ·  ✓  ✓  ✓  ✓  ✓  ·  ✓").font(.system(size: 15)).foregroundStyle(ReferenceColor.green)
                        Text("小明本月完成 15 次运动打卡，继续加油！").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 12)
                ReferenceSectionTitle(title: "延时课堂精彩瞬间", trailing: "查看全部", action: { router.push(.parentCourses) }).padding(.horizontal, 12)
                HStack(spacing: 8) { moment("ActivityFootball", "足球启蒙"); moment("ActivityClassroom", "健康课堂"); moment("ActivityBalance", "亲子平衡") }.padding(.horizontal, 12)
                ReferenceSectionTitle(title: "推荐课程", trailing: "查看详情", action: { router.push(.parentCourses) }).padding(.horizontal, 12)
                CourseSuggestionBanner().padding(.horizontal, 12)
                ReferenceSectionTitle(title: "我的课程", trailing: "全部课程", action: { router.push(.parentCourses) }).padding(.horizontal, 12)
                UpcomingTrainingCard().padding(.horizontal, 12)
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .overlay {
            if state.loading || state.data == nil { ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() } }
            else if state.selectedChild == nil { ParentBindingPrompt() }
        }
        .sheet(isPresented: $isComposerShown) { PublishClassPostSheet(author: "王女士") }
        .sheet(item: $editingPost) { post in PublishClassPostSheet(author: post.author, editingPost: post) }
        .sheet(item: Binding(get: { selectedMoment.map(CourseSheetItem.init) }, set: { selectedMoment = $0?.name })) { item in
            if item.name.contains("榜单") || item.name.contains("打卡记录") {
                CircleInfoSheet(title: item.name)
            } else {
                CourseDetailSheet(title: item.name)
            }
        }
        .sheet(item: Binding(get: { commentPostID.map(CommentSheetItem.init) }, set: { commentPostID = $0?.id })) { item in
            NavigationStack { VStack(spacing: 14) { if commentSubmitted { Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(ReferenceColor.green); Text("评论已发布").font(.headline); Text("班级成员可以看到你的留言。").font(.footnote).foregroundStyle(.secondary); Button("完成") { commentPostID = nil }.buttonStyle(.borderedProminent) } else { Text("给这条动态留言").font(.headline); TextField("说点鼓励的话…", text: $commentDraft, axis: .vertical).textFieldStyle(.roundedBorder); Button("发布评论") { if let postID = commentPostID { state.addClassPostComment(postID: postID, text: commentDraft) }; commentSubmitted = true }.buttonStyle(.borderedProminent).disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }; Spacer() }.padding(20).navigationTitle("评论").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { commentPostID = nil } } } }
        }
    }
    private func circleMockPost(author: String, content: String, isTeacher: Bool) -> some View { ReferenceCard { VStack(alignment: .leading, spacing: 7) { HStack { Image(systemName: isTeacher ? "graduationcap.circle.fill" : "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(ReferenceColor.blue); VStack(alignment: .leading, spacing: 1) { Text(author).font(.system(size: 11, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text("今天 08:30 · 本班可见").font(.system(size: 8)).foregroundStyle(.secondary) }; Spacer(); Text("置顶").font(.system(size: 9, weight: .bold)).foregroundStyle(ReferenceColor.yellow) }; Text(content).font(.system(size: 12)).foregroundStyle(ReferenceColor.navy); HStack { Label("12", systemImage: "hand.thumbsup"); Label("3", systemImage: "bubble.left"); Spacer(); Text("班级通知").foregroundStyle(ReferenceColor.blue) }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) } }.padding(.horizontal, 12) }
    private func star(_ title: String, _ name: String, _ color: Color) -> some View { VStack(spacing: 3) { Image(systemName: "star.fill").foregroundStyle(color).font(.system(size: 21)); Text(title).font(.system(size: 9, weight: .bold)); Text(name).font(.system(size: 8)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
    private func moment(_ image: String, _ title: String) -> some View { Button { selectedMoment = title } label: { VStack(alignment: .leading, spacing: 4) { Image(image).resizable().scaledToFill().frame(height: 48).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 7)); Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(ReferenceColor.navy) }.frame(maxWidth: .infinity) }.buttonStyle(.plain) }
}

private struct CommentSheetItem: Identifiable { let id: UUID }

private struct CircleInfoSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if title.contains("榜单") {
                    Section("本月班级之星") {
                        LabeledContent("勤劳之星", value: "陈乐乐")
                        LabeledContent("运动之星", value: "王小明")
                        LabeledContent("阅读之星", value: "李安然")
                    }
                } else {
                    Section("王小明的运动打卡") {
                        LabeledContent("本月完成", value: "15 次")
                        LabeledContent("连续打卡", value: "5 天")
                        Text("打卡数据会在学校活动和家庭运动记录同步后自动更新。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

struct AccountDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var dialog: String?
    @State private var settingsShown = false
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我的")
                HStack(spacing: 12) {
                    Image(state.selectedRole == .teacher ? "TeacherAvatar" : "ChildAvatar").resizable().scaledToFill().frame(width: 54, height: 54).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) { Text(state.profile?.name ?? "王女士").font(.system(size: 16, weight: .bold)); Text(state.profile?.schoolName ?? "向上实验小学").font(.system(size: 10)).foregroundStyle(.secondary); RoleBadge(role: state.selectedRole ?? .parent) }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 12).contentShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { dialog = "个人资料" }.accessibilityElement(children: .combine).accessibilityLabel("查看个人资料").accessibilityAddTraits(.isButton)
                if state.selectedRole == .parent {
                    HStack(spacing: 8) {
                        accountMetric(title: "已绑定孩子", value: "\(state.boundChildren.count)", action: { router.push(.children) })
                        accountMetric(title: "成长报告", value: state.selectedChild == nil ? "0" : "1", action: { if let child = state.selectedChild { router.push(.report(child)) } })
                        accountMetric(title: "未读消息", value: "\(state.unreadMessageCount)", action: { router.push(.parentMessages) })
                    }.padding(.horizontal, 12)
                    ReferenceSectionTitle(title: "家庭服务", trailing: "孩子管理", action: { router.push(.children) }).padding(.horizontal, 12)
                } else {
                    HStack(spacing: 8) {
                        accountMetric(title: "管理班级", value: "2", action: { router.push(.teacherClasses) })
                        accountMetric(title: "待复核", value: "3", action: { router.push(.reviewList) })
                        accountMetric(title: "未读消息", value: "\(state.unreadMessageCount)", action: { router.push(.teacherMessages) })
                    }.padding(.horizontal, 12)
                    ReferenceSectionTitle(title: "教师工作台", trailing: "查看数据", action: { router.push(.teacherClassBoard) }).padding(.horizontal, 12)
                }
                if state.selectedRole == .teacher {
                    accountRow("个人信息", "person.text.rectangle.fill", ReferenceColor.blue) { dialog = "个人信息" }
                    accountRow("我的权限", "lock.shield.fill", ReferenceColor.green) { dialog = "我的权限" }
                    accountRow("工作数据", "chart.bar.fill", ReferenceColor.purple) { router.push(.teacherClassBoard) }
                    accountRow("设置", "gearshape.fill", .orange) { settingsShown = true }
                    accountRow("消息", "bell.fill", .red) { router.push(.teacherMessages) }
                } else {
                    accountRow("我的健康档案", "heart.text.square.fill", ReferenceColor.green) { router.push(.healthProfile) }
                    accountRow("我的课程", "play.rectangle.fill", ReferenceColor.blue) { dialog = "我的课程" }
                    accountRow("客服咨询", "message.fill", ReferenceColor.purple) { dialog = "客服咨询" }
                    accountRow("消息", "bell.fill", .red) { router.push(.parentMessages) }
                }
                ReferenceSectionTitle(title: "服务与安全", trailing: "隐私安全").padding(.horizontal, 12)
                accountRow("通知与显示设置", "gearshape.fill", .orange) { settingsShown = true }
                accountRow("帮助与反馈", "questionmark.circle.fill", ReferenceColor.blue) { dialog = "帮助与反馈" }
                accountRow("用户协议与隐私政策", "doc.text.fill", .secondary) { dialog = "用户协议与隐私政策" }
                Button { state.chooseAnotherRole(); router.path = NavigationPath() } label: { Label("切换使用角色", systemImage: "arrow.left.arrow.right").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(ReferenceColor.blue).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
                Button { state.switchAccount(); router.path = NavigationPath() } label: { Text("切换账号").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(.red).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
            }.padding(.bottom, 10)
        }.background(ReferenceColor.canvas)
        .sheet(item: Binding(get: { dialog.map(CourseSheetItem.init) }, set: { dialog = $0?.name })) { item in
            if ["个人资料", "个人信息", "我的权限", "帮助与反馈", "用户协议与隐私政策"].contains(item.name) {
                AccountInfoSheet(title: item.name)
            } else {
                CourseDetailSheet(title: item.name)
            }
        }
        .sheet(isPresented: $settingsShown) { AppSettingsSheet() }
    }
    private func accountMetric(title: String, value: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 3) { Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(ReferenceColor.blue); Text(title).font(.system(size: 9)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 10).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) }
    private func accountRow(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View { Button(action: action) { HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12) }
}

struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    var body: some View { NavigationStack { Form { Section("通知与显示") { Toggle("接收测评与班级通知", isOn: Binding(get: { state.localFeatures.settings.notificationsEnabled }, set: { state.updateSettings(notificationsEnabled: $0) })); Toggle("减少动态效果", isOn: Binding(get: { state.localFeatures.settings.reduceMotion }, set: { state.updateSettings(reduceMotion: $0) })); Text("设置已自动保存，并将在下次启动后保留。").font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("设置").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } } } }
}

struct AccountInfoSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var feedback = ""
    @State private var feedbackSubmitted = false
    var body: some View {
        NavigationStack {
            Form {
                if title == "个人资料" || title == "个人信息" {
                    Section("账号信息") {
                        LabeledContent("姓名", value: "王女士")
                        LabeledContent("手机号", value: "138****8000")
                        LabeledContent("所属学校", value: "向上实验小学")
                        Text("账号信息由学校或平台管理员维护。") .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if title == "我的权限" {
                    Section("当前权限") { Label("查看测评、报告和成长建议", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green); Label("管理所负责班级数据", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green); Text("权限以学校后台授权为准。") .font(.footnote).foregroundStyle(.secondary) }
                } else if title == "帮助与反馈" {
                    Section("问题反馈") {
                        if feedbackSubmitted {
                            Label("反馈已提交，客服会在工作时间内回复。", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green)
                        } else {
                            TextEditor(text: $feedback).frame(minHeight: 110)
                            Button("提交反馈") {
                                let message = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !message.isEmpty else { return }
                                state.sendSupportMessage(message)
                                feedbackSubmitted = true
                            }.disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Section("常见问题") { Text("孩子绑定码由学校或班主任提供。\n测评报告生成后会在消息中心通知。\n如遇数据异常，请联系学校管理员。") .font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Section("协议说明") { Text("向上少年仅在获得授权后处理学生健康与运动数据，用于测评、报告和课程建议。儿童账号和家庭绑定数据不会用于商业推广。") .font(.footnote).foregroundStyle(.secondary); Text("协议版本：2026.1") .font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

struct CourseSheetItem: Identifiable { let name: String; var id: String { name } }
struct PublishClassPostSheet: View {
    let author: String
    var editingPost: ClassPostDraft?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var content = ""
    @State private var validationMessage: String?
    @State private var submitted = false
    private var draftKey: String { "class-post-\(editingPost?.id.uuidString ?? author)" }
    var body: some View { NavigationStack { VStack(alignment: .leading, spacing: 14) { if submitted { VStack(spacing: 12) { Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(ReferenceColor.green); Text(editingPost == nil ? "动态已发布" : "修改已保存").font(.title3.bold()); Text("内容已保存到本班家校圈，可在班级圈继续查看。").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center); Spacer(); Button("完成") { dismiss() }.font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 11)) } } else { Text(editingPost == nil ? "发布班级动态" : "编辑班级动态").font(.title3.bold()); Text("内容将同步显示在本班家校圈。请勿发布学生隐私信息。").font(.system(size: 12)).foregroundStyle(.secondary); TextEditor(text: $content).frame(minHeight: 160).padding(8).overlay(RoundedRectangle(cornerRadius: 10).stroke(validationMessage == nil ? ReferenceColor.navy.opacity(0.15) : .red, lineWidth: 1)).onChange(of: content) { _, value in state.saveDraft(value, key: draftKey) }; if let validationMessage { Text(validationMessage).font(.system(size: 10)).foregroundStyle(.red) }; Spacer(); Button { let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { validationMessage = "动态内容不能为空。"; return }; if let editingPost { state.updateClassPost(id: editingPost.id, text: trimmed) } else { state.publishClassPost(trimmed, author: author) }; state.clearDraft(draftKey); submitted = true } label: { Text(editingPost == nil ? "发布动态" : "保存修改").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 11)) }.disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.padding(18).navigationBarTitleDisplayMode(.inline) }.task { content = editingPost?.content ?? state.localFeatures.drafts[draftKey] ?? "" } }
}
struct HealthArticleSheet: View { let title: String; @Environment(\.dismiss) private var dismiss; @Environment(\.openURL) private var openURL; var body: some View { NavigationStack { VStack(spacing: 15) { Image(systemName: "book.closed.fill").font(.system(size: 44)).foregroundStyle(ReferenceColor.green); Text(title).font(.title3.bold()).multilineTextAlignment(.center); Text("完整健康专栏将由“向上少年健康成长”微信公众号提供。") .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28); Button { openURL(URL(string: "weixin://")!) } label: { Label("打开微信公众号", systemImage: "arrow.up.forward.app") }.buttonStyle(.borderedProminent); Text("若未安装微信，可搜索公众号：向上少年健康成长").font(.system(size: 10)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("健康科普").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } } } } }
struct ActivityDetailSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var contactName = "王女士"
    @State private var phone = "13800138000"
    @State private var consented = false
    @State private var validationMessage: String?
    private let activityID = "health-growth-season-2026"
    private var draftKey: String { "activity-registration-\(activityID)" }

    var body: some View {
        let registered = state.localFeatures.registeredActivities.contains(activityID)
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 14) {
            Image("ParentCampaign").resizable().scaledToFill().frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 14))
            Text(title).font(.title3.bold())
            Label("7 月 16 日–8 月 15 日", systemImage: "calendar").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("完成综合健康测评，了解孩子的运动发展与健康成长情况。活动成绩将自动同步到孩子档案。") .font(.system(size: 13)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) { Text("活动说明").font(.system(size: 15, weight: .bold)); Text("• 完成四项健康测评\n• 查看个性化成长报告\n• 可预约学校体测场地") .font(.system(size: 12)).foregroundStyle(ReferenceColor.navy) }.padding(12).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 12))
            if registered {
                Label("已报名，活动开始前将通过消息中心通知您。", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(ReferenceColor.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("报名信息").font(.system(size: 15, weight: .bold))
                    TextField("联系人姓名", text: $contactName).textFieldStyle(.roundedBorder)
                    TextField("手机号", text: $phone).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
                    Toggle("已阅读活动说明并同意接收报名通知", isOn: $consented).font(.system(size: 11))
                }
                .onChange(of: contactName) { _, _ in saveDraft() }
                .onChange(of: phone) { _, _ in saveDraft() }
                if let validationMessage { Text(validationMessage).font(.system(size: 10)).foregroundStyle(.red) }
            }
            Button {
                guard !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validationMessage = "请填写联系人姓名。"; return }
                guard phone.filter(\.isNumber).count == 11 else { validationMessage = "请填写 11 位手机号。"; return }
                guard consented else { validationMessage = "请先确认活动说明和通知授权。"; return }
                state.registerActivity(activityID, contactName: contactName, phone: phone)
                state.clearDraft(draftKey)
                validationMessage = nil
            } label: { Text(registered ? "已报名，等待活动开始" : "确认报名").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(registered ? ReferenceColor.green : ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 12)) }
            .buttonStyle(.plain).disabled(registered)
        }.padding(16) }.navigationTitle("活动详情").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        .task { if let values = state.localFeatures.drafts[draftKey]?.split(separator: "|", maxSplits: 1).map(String.init), values.count == 2 { contactName = values[0]; phone = values[1] } }
        }
    }

    private func saveDraft() { state.saveDraft("\(contactName)|\(phone)", key: draftKey) }
}

struct CourseDetailSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var isPlaying = false
    @State private var progress = 0.15
    @State private var draft = ""
    @State private var replyError: String?
    var body: some View { NavigationStack { VStack(spacing: 14) {
        if title == "客服咨询" {
            Image(systemName: "message.fill").font(.system(size: 42)).foregroundStyle(ReferenceColor.blue)
            Text("课程咨询").font(.title3.bold())
            ScrollView { VStack(alignment: .leading, spacing: 8) { bubble("您好，我是向上少年客服老师，请问想咨询哪一类课程？", mine: false); ForEach(state.localFeatures.supportMessages) { message in bubble(message.text, mine: message.isMine) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 220).padding(.horizontal, 18)
            HStack { TextField("输入咨询内容", text: $draft).textFieldStyle(.roundedBorder).onChange(of: draft) { _, value in state.saveDraft(value, key: supportDraftKey) }; Button("发送") { let text = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { replyError = "请输入咨询内容。"; return }; state.sendSupportMessage(text); state.clearDraft(supportDraftKey); draft = ""; replyError = nil } .buttonStyle(.borderedProminent).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding(.horizontal, 18)
            if let replyError { Text(replyError).font(.system(size: 10)).foregroundStyle(.red) }
        } else {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 48)).foregroundStyle(ReferenceColor.blue); Text(title).font(.title3.bold()); Text("已为您加载课程视频。播放进度会同步到孩子的学习记录。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28); ProgressView(value: progress).tint(ReferenceColor.green).padding(.horizontal, 30); Button { isPlaying.toggle(); if isPlaying { withAnimation(.linear(duration: 2.5)) { progress = 0.8 }; state.updateCourseProgress(title, progress: 0.8) } } label: { Label(isPlaying ? "暂停学习" : "播放课程", systemImage: isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent)
        }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }.task { progress = state.localFeatures.courseProgress[title] ?? progress; draft = state.localFeatures.drafts[supportDraftKey] ?? "" } } }
    private var supportDraftKey: String { "support-\(title)" }
    private func bubble(_ text: String, mine: Bool) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(mine ? .white : ReferenceColor.navy).padding(9).background(mine ? ReferenceColor.blue : ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading) }
}

struct ExpertDetailSheet: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var date = "2026-09-12 上午"
    @State private var note = "想了解孩子的运动发展建议。"
    @State private var submitted = false
    private var draftKey: String { "expert-\(name)" }
    var body: some View { NavigationStack { VStack(spacing: 14) {
        Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 48)).foregroundStyle(ReferenceColor.blue)
        Text("\(name) · 健康成长专家").font(.title3.bold())
        Text("擅长儿童运动发展与健康评估，可为孩子提供体质、运动及成长建议。在线咨询申请提交后将同步至学校服务。")
            .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
        if submitted { Label("预约已提交，专家团队会在 1 个工作日内确认。", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(ReferenceColor.green) } else { VStack(spacing: 8) { TextField("期望咨询时间", text: $date).textFieldStyle(.roundedBorder); TextField("咨询说明", text: $note, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder) }.padding(.horizontal, 20).onChange(of: date) { _, _ in state.saveDraft("\(date)|\(note)", key: draftKey) }.onChange(of: note) { _, _ in state.saveDraft("\(date)|\(note)", key: draftKey) }; Button("提交预约") { state.bookExpert(name: name, preferredDate: date, note: note); state.clearDraft(draftKey); submitted = true }.buttonStyle(.borderedProminent).disabled(date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("专家详情").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }.task { if let saved = state.localFeatures.drafts[draftKey]?.split(separator: "|", maxSplits: 1).map(String.init), saved.count == 2 { date = saved[0]; note = saved[1] }; submitted = state.localFeatures.expertAppointments.contains { $0.expertName == name && $0.status == .submitted } } } }
}

struct ExpertListView: View {
    @State private var selected: String?
    private let experts = [("ExpertProfessor", "张教授", "儿童运动发展"), ("ExpertDoctor", "李医生", "儿童健康评估"), ("ExpertCoach", "王教练", "青少年运动训练"), ("ExpertCounselor", "刘主任", "儿童心理成长")]
    var body: some View { ScrollView { VStack(spacing: 9) { ParentPageNavigation(title: "专家团队", showsBack: true); ForEach(experts, id: \.1) { item in Button { selected = item.1 } label: { HStack(spacing: 12) { Image(item.0).resizable().scaledToFit().frame(width: 56, height: 56).background(ReferenceColor.sky, in: Circle()).clipShape(Circle()); VStack(alignment: .leading, spacing: 5) { Text(item.1).font(.system(size: 14, weight: .bold)); Text(item.2).font(.system(size: 10)).foregroundStyle(ReferenceColor.blue); Text("简介、专业领域与服务内容").font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).padding(.horizontal, 12) } }.padding(.bottom, 10) }.background(ReferenceColor.canvas).sheet(item: Binding(get: { selected.map(CourseSheetItem.init) }, set: { selected = $0?.name })) { item in ExpertDetailSheet(name: item.name) } }
}

struct ParentHealthDimension: View {
    let title: String; let detail: String; let color: Color
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    var body: some View { Button { if let child = state.selectedChild { router.push(.report(child)) } } label: {
        HStack(spacing: 10) { Image(systemName: title == "体质" ? "figure.run" : title == "视力" ? "eye.fill" : title == "口腔" ? "mouth.fill" : "brain.head.profile").font(.system(size: 16, weight: .bold)).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .bold)); Text(detail).font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer(); Text("良好").font(.system(size: 10, weight: .bold)).foregroundStyle(color); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary) }
            .foregroundStyle(ReferenceColor.navy).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain) }
}
