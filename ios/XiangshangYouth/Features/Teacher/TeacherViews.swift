import SwiftUI
import UniformTypeIdentifiers

struct TeacherHomeView: View {
    @State private var selectedTab = 0
    @State private var isSportsTeacher = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 0: TeacherDashboard(isSportsTeacher: $isSportsTeacher)
                case 1:
                    if isSportsTeacher {
                        SportsUploadDashboard()
                    } else {
                        TeacherClassCircleDashboard()
                    }
                default: AccountDashboard()
                }
            }
            .id("\(selectedTab)-\(isSportsTeacher)")
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            teacherBottomBar
        }
        .background(ReferenceColor.canvas)
        .animation(.easeInOut(duration: 0.22), value: selectedTab)
    }

    private var teacherBottomBar: some View {
        HStack {
            tabButton(index: 0, icon: "house.fill", title: "首页")
            tabButton(index: 1, icon: isSportsTeacher ? "camera.fill" : "rectangle.grid.2x2", title: isSportsTeacher ? "延时上传" : "班级圈")
            tabButton(index: 2, icon: "person", title: "我的")
        }
        .padding(.top, 7)
        .padding(.bottom, 5)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(ReferenceColor.navy.opacity(0.06)).frame(height: 0.5) }
    }

    private func tabButton(index: Int, icon: String, title: String) -> some View {
        Button { withAnimation { selectedTab = index } } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(selectedTab == index ? ReferenceColor.blue : Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct TeacherClassCircleDashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var composerShown = false
    @State private var selectedNotice: String?
    @State private var editingPost: ClassPostDraft?
    var body: some View { ScrollView { VStack(spacing: 10) {
        ParentPageNavigation(title: "三年级2班 · 班级圈")
        ReferenceCard { VStack(alignment: .leading, spacing: 7) { HStack { Image(systemName: "megaphone.fill").foregroundStyle(ReferenceColor.blue); Text("班级公告").font(.system(size: 13, weight: .bold)); Spacer(); Button("全部公告 ›") { selectedNotice = "全部班级公告" }.font(.system(size: 9)).foregroundStyle(ReferenceColor.blue).buttonStyle(.plain) }; Button { selectedNotice = "秋季综合测评通知" } label: { VStack(alignment: .leading, spacing: 4) { Text("秋季综合测评通知").font(.system(size: 12, weight: .bold)); Text("请家长于 9 月 12 日前完成孩子健康信息确认。") .font(.system(size: 9)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) } }.padding(.horizontal, 12)
        Button { composerShown = true } label: { Label("发布公告或班级动态", systemImage: "square.and.pencil").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
        ForEach(state.localFeatures.classPosts) { post in ReferenceCard { VStack(alignment: .leading, spacing: 5) { HStack { Text(post.author).font(.system(size: 10, weight: .bold)).foregroundStyle(ReferenceColor.blue); Spacer(); if post.author == "李老师" { Button("编辑") { editingPost = post }.font(.system(size: 9, weight: .semibold)).foregroundStyle(ReferenceColor.blue) } }; Text(post.content).font(.system(size: 12)); Text("刚刚发布").font(.system(size: 8)).foregroundStyle(.secondary) } }.padding(.horizontal, 12) }
        ReferenceSectionTitle(title: "班级动态", trailing: "本班最新").padding(.horizontal, 12)
        ForEach([("今日体能活动", "孩子们完成了侧向滑步与障碍跳练习，表现很棒！"), ("家校共育小贴士", "建议每天安排 20 分钟亲子运动时间。")], id: \.0) { item in ReferenceCard { VStack(alignment: .leading, spacing: 5) { Text(item.0).font(.system(size: 12, weight: .bold)); Text(item.1).font(.system(size: 9)).foregroundStyle(.secondary); Text("李老师 · 今天").font(.system(size: 8)).foregroundStyle(ReferenceColor.green) } }.padding(.horizontal, 12) }
    }.padding(.bottom, 10) }.background(ReferenceColor.canvas).sheet(isPresented: $composerShown) { PublishClassPostSheet(author: "李老师") }.sheet(item: $editingPost) { post in PublishClassPostSheet(author: post.author, editingPost: post) }.sheet(item: Binding(get: { selectedNotice.map(CourseSheetItem.init) }, set: { selectedNotice = $0?.name })) { item in CourseDetailSheet(title: item.name) } }
}

struct SportsUploadDashboard: View {
    @EnvironmentObject private var state: AppState
    private let taskID = "sports-upload-2026-09-12"
    @State private var isUploadFormShown = false
    var body: some View { ScrollView { VStack(spacing: 10) {
        ParentPageNavigation(title: "延时课程上传")
        ReferenceCard { VStack(alignment: .leading, spacing: 9) { ReferenceSectionTitle(title: "一（6）班体能提升课", trailing: "17:20–18:00"); Label("请上传测评结果记录与课堂照片", systemImage: "camera.badge.ellipsis").font(.system(size: 10)).foregroundStyle(.secondary); HStack { uploadTile("photo.on.rectangle", "课堂照片"); uploadTile("doc.text.fill", "测评记录"); uploadTile("person.3.fill", "出勤名单") } } }.padding(.horizontal, 12)
        ReferenceCard { VStack(alignment: .leading, spacing: 7) { Text("今日待上传课程").font(.system(size: 13, weight: .bold)); uploadTask("16:30 · 一（6）班测评任务", "已完成，待上传"); uploadTask("17:20 · 体能提升班", "课程进行中") } }.padding(.horizontal, 12)
        let submitted = state.localFeatures.uploadedTaskIDs.contains(taskID)
        Button { isUploadFormShown = true } label: { Text(submitted ? "查看已提交课程记录" : "填写并提交课程记录").font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(.white).background(submitted ? ReferenceColor.green : .orange, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12)
        if let record = state.localFeatures.courseUploads.first(where: { $0.taskID == taskID }) { Text(record.status == .submitted ? "已提交：\(record.attachmentName) · 出勤 \(record.attendanceCount) 人" : "已保存草稿：\(record.notes)").font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 14) }
    }.padding(.bottom, 10) }.background(ReferenceColor.canvas).sheet(isPresented: $isUploadFormShown) { CourseUploadSheet(taskID: taskID) } }
    private func uploadTile(_ icon: String, _ title: String) -> some View { Button { isUploadFormShown = true } label: { VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 18)).foregroundStyle(ReferenceColor.blue); Text(title).font(.system(size: 9, weight: .medium)) }.frame(maxWidth: .infinity).padding(.vertical, 8).background(ReferenceColor.sky, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel("上传\(title)") }
    private func uploadTask(_ title: String, _ status: String) -> some View { Button { isUploadFormShown = true } label: { HStack { Image(systemName: "figure.run").foregroundStyle(ReferenceColor.green); VStack(alignment: .leading) { Text(title).font(.system(size: 11, weight: .bold)); Text(status).font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary) }.padding(.vertical, 4) }.buttonStyle(.plain).accessibilityLabel("查看\(title)\(status)") }
}

struct CourseUploadSheet: View {
    let taskID: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var attendance = "26"
    @State private var notes = "完成侧向滑步与障碍跳训练，学生整体表现良好。"
    @State private var attachment = "课堂活动照片.jpg"
    @State private var error: String?
    @State private var isImporterShown = false
    private var draftKey: String { "course-upload-\(taskID)" }
    var body: some View { NavigationStack { Form { Section("课程记录") { TextField("出勤人数", text: $attendance).keyboardType(.numberPad); TextField("课堂记录", text: $notes, axis: .vertical).lineLimit(3...5); LabeledContent("课堂附件", value: attachment); Button("从文件选择照片") { isImporterShown = true } }; Section { Button("保存草稿") { save(submit: false) }; Button("提交审核") { save(submit: true) }.disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }; if let error { Section { Text(error).foregroundStyle(.red) } } }.navigationTitle("延时课程上传").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }.task { if let record = state.localFeatures.courseUploads.first(where: { $0.taskID == taskID }) { attendance = String(record.attendanceCount); notes = record.notes; attachment = record.attachmentName } else if let draft = state.localFeatures.drafts[draftKey]?.split(separator: "|", maxSplits: 2).map(String.init), draft.count == 3 { attendance = draft[0]; notes = draft[1]; attachment = draft[2] } }.onChange(of: attendance) { _, _ in saveDraft() }.onChange(of: notes) { _, _ in saveDraft() }.onChange(of: attachment) { _, _ in saveDraft() }.fileImporter(isPresented: $isImporterShown, allowedContentTypes: [.image]) { result in if case let .success(url) = result { attachment = url.lastPathComponent } } } }
    private func saveDraft() { state.saveDraft("\(attendance)|\(notes)|\(attachment)", key: draftKey) }
    private func save(submit: Bool) { guard let count = Int(attendance), count >= 0 else { error = "请填写有效的出勤人数。"; return }; if submit && (notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { error = "提交前请补齐课堂记录和附件。"; return }; state.saveCourseUpload(taskID: taskID, attendanceCount: count, notes: notes, attachmentName: attachment, submit: submit); if submit { state.clearDraft(draftKey); dismiss() } else { error = "草稿已保存，可稍后继续编辑。" } }
}

struct TeacherMessageDetail: Identifiable { let id = UUID(); let title: String; let detail: String; let time: String }

struct TeacherMessagesView: View {
    @EnvironmentObject private var state: AppState
    private let items = [("m1", "exclamationmark.triangle.fill", "学生预警通知", "王小明体质指标需关注，请及时跟进。", Color.red), ("m2", "building.2.fill", "学校通知", "秋季综合测评工作安排已发布。", ReferenceColor.blue), ("teacher-course", "calendar.badge.clock", "课程通知", "三年级2班延时课程将在明日 16:30 开始。", ReferenceColor.green), ("teacher-system", "gearshape.fill", "系统消息", "测评数据已完成同步。", ReferenceColor.purple)]
    @State private var selectedMessage: TeacherMessageDetail?
    var body: some View { ScrollView { VStack(spacing: 8) { ParentPageNavigation(title: "消息中心", showsBack: true); ForEach(items.indices, id: \.self) { index in let item = items[index]; let unread = ["m1", "m2"].contains(item.0) && !state.localFeatures.readMessageIDs.contains(item.0) && state.data?.messages.first(where: { $0.id == item.0 })?.isRead == false; Button { state.markMessageRead(item.0); selectedMessage = TeacherMessageDetail(title: item.2, detail: item.3, time: index == 0 ? "刚刚" : "今天") } label: { HStack(spacing: 10) { Image(systemName: item.1).foregroundStyle(item.4).frame(width: 36, height: 36).background(item.4.opacity(0.10), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 4) { HStack(spacing: 5) { Text(item.2).font(.system(size: 12, weight: .bold)); if unread { Circle().fill(.red).frame(width: 5, height: 5) } }; Text(item.3).font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer(); Text(index == 0 ? "刚刚" : "今天").font(.system(size: 8)).foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary) }.foregroundStyle(ReferenceColor.navy).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, 12) } }.padding(.bottom, 10) }.background(ReferenceColor.canvas).sheet(item: $selectedMessage) { message in NavigationStack { VStack(alignment: .leading, spacing: 14) { Text(message.title).font(.title3.bold()); Text(message.time).font(.caption).foregroundStyle(.secondary); Divider(); Text(message.detail).font(.body); Spacer() }.padding().navigationTitle("消息详情").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { selectedMessage = nil } } } } } }
}

struct TeacherDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Binding var isSportsTeacher: Bool
    private var classStudents: [Student] { state.data?.students.filter { $0.className == "三年级2班" } ?? [] }
    private var measuredCount: Int { classStudents.filter { state.taskStatus(for: $0) == .completed }.count }
    private var riskCount: Int { classStudents.filter { ($0.totalScore ?? 35) < 25 || state.taskStatus(for: $0) == .review || state.taskStatus(for: $0) == .retest }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                teacherHeader
                teacherSwitch
                if isSportsTeacher {
                    sportsTeacherContent
                } else {
                    classTeacherContent
                }
            }
            .padding(.bottom, 8)
        }
        .background(ReferenceColor.canvas)
        .refreshable { await state.refreshDashboard() }
        .overlay {
            if state.loading || state.data == nil {
                LoadingStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas.opacity(0.96))
            } else if classStudents.isEmpty {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    EmptyStateView(title: "暂无班级数据", detail: "当前账号还没有被分配班级，请联系学校管理员。")
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isSportsTeacher)
    }

    private var teacherHeader: some View {
        HStack(spacing: 9) {
            Image("TeacherAvatar").resizable().scaledToFill()
                .frame(width: 43, height: 43).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("李老师").font(.system(size: 14, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                Text("向上实验小学").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(isSportsTeacher ? "体育老师" : "三年级2班").font(.system(size: 8, weight: .semibold)).foregroundStyle(ReferenceColor.green)
            }
            Spacer()
            Button { withAnimation { isSportsTeacher.toggle() } } label: { Label("切换角色", systemImage: "arrow.left.arrow.right")
                .font(.system(size: 9, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
                .background(.white, in: Capsule()).overlay(Capsule().stroke(ReferenceColor.navy.opacity(0.10), lineWidth: 1)) }.buttonStyle(.plain)
            Button { router.push(.teacherMessages) } label: { Image(systemName: "bell").font(.system(size: 16, weight: .medium)).foregroundStyle(ReferenceColor.navy)
                .overlay(alignment: .topTrailing) { if state.unreadMessageCount > 0 { Circle().fill(.red).frame(width: 5, height: 5).offset(x: 2, y: -2) } }
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(.white)
    }

    private var teacherSwitch: some View {
        HStack(spacing: 8) {
            roleSwitchButton("班主任", "person.3.fill", selected: !isSportsTeacher, color: ReferenceColor.blue) { isSportsTeacher = false }
            roleSwitchButton("体育老师", "figure.run", selected: isSportsTeacher, color: ReferenceColor.green) { isSportsTeacher = true }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    private func roleSwitchButton(_ title: String, _ icon: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { action() }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? .white : color)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(selected ? color : color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(selected ? 0 : 0.14), lineWidth: 1))
        }
    }

    private var classTeacherContent: some View {
        VStack(spacing: 10) {
            Text("🔒 仅查看所有测评数据及授权数据").font(.system(size: 9)).foregroundStyle(.secondary)
            ReferenceCard {
                VStack(spacing: 10) {
                    ReferenceSectionTitle(title: "班级健康概览", trailing: "查看班级看板", action: { router.push(.teacherClassBoard) })
                    HStack {
                        count("班级人数", "\(classStudents.count)", "person.3.fill", ReferenceColor.blue) { router.push(.studentList(nil)) }
                        count("已测评", "\(measuredCount)", "checkmark.circle.fill", ReferenceColor.green) { router.push(.studentList(nil)) }
                        count("测评率", "\(classStudents.isEmpty ? 0 : measuredCount * 100 / classStudents.count)%", "circle", ReferenceColor.green) { router.push(.teacherClassBoard) }
                        count("待处理预警", "\(riskCount)", "exclamationmark.shield.fill", .red) { router.push(.reviewList) }
                    }
                    Divider()
                    HStack {
                        Text("问题分布（人）").font(.system(size: 10, weight: .bold))
                        Spacer()
                        Text("低分 \(classStudents.filter { ($0.totalScore ?? 35) < 25 }.count) · 待复核 \(classStudents.filter { state.taskStatus(for: $0) == .review }.count) · 待补测 \(classStudents.filter { state.taskStatus(for: $0) == .retest }.count)")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 5) {
                action("rectangle.stack.fill", "班级看板", ReferenceColor.blue, .teacherClassBoard)
                action("exclamationmark.triangle.fill", "预警中心", .red, .reviewList)
                action("person.3.fill", "学生列表", ReferenceColor.green, .studentList(nil))
                action("person.2.fill", "待分班学生", .orange, .teacherClasses)
                action("figure.run", "查看延时课", .teal, .teacherTasks)
                action("medal.fill", "优秀学生评选", ReferenceColor.purple, .studentList(nil))
                action("person.badge.plus", "学生名单", .orange, .studentList(nil))
            }
            .padding(.horizontal, 12)
            ReferenceCard {
                VStack(alignment: .leading, spacing: 7) {
                    ReferenceSectionTitle(title: "今日任务", trailing: "查看全部", action: { router.push(.teacherTasks) })
                    teacherTaskRow("16:30–17:10 · 三年级2班综合测评", "进行中", ReferenceColor.green)
                    teacherTaskRow("17:20–18:00 · 体能提升课", "待上传", .orange)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func teacherTaskRow(_ title: String, _ status: String, _ color: Color) -> some View {
        Button { router.push(.teacherTasks) } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(color)
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(ReferenceColor.navy)
                Spacer()
                Text(status).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var sportsTeacherContent: some View {
        VStack(spacing: 10) {
            ReferenceCard {
                VStack(alignment: .leading, spacing: 9) {
                    ReferenceSectionTitle(title: "近日测评提醒", trailing: "查看全部", action: { router.push(.teacherTasks) })
                    HStack {
                        count("待测班级", "\(state.data?.tasks.filter { $0.completedCount < $0.totalCount }.count ?? 0)", "folder.fill", ReferenceColor.blue) { router.push(.teacherTasks) }
                        count("测评学生", "\(state.data?.students.count ?? 0)", "person.fill", ReferenceColor.green) { router.push(.studentList(nil)) }
                        count("今日排班", "\(state.data?.tasks.count ?? 0)", "calendar", .orange) { router.push(.teacherTasks) }
                        count("待上传", "\(state.data?.tasks.filter { $0.completedCount < $0.totalCount }.count ?? 0)", "icloud.and.arrow.up.fill", ReferenceColor.purple) { router.push(.teacherTasks) }
                    }
                    let total = state.data?.tasks.reduce(0) { $0 + $1.totalCount } ?? 0
                    let completed = state.data?.tasks.reduce(0) { $0 + $1.completedCount } ?? 0
                    let progress = total == 0 ? 0 : Double(completed) / Double(total)
                    AnimatedProgressLine(value: progress, colors: [ReferenceColor.green, ReferenceColor.blue])
                    Text("已完成 \(completed) / \(total) 人    \(Int(progress * 100))%").font(.system(size: 9, weight: .bold)).foregroundStyle(ReferenceColor.green)
                }
            }
            .padding(.horizontal, 12)
            HStack(spacing: 8) {
                action("person.3.sequence.fill", "学生管理", ReferenceColor.green, .studentList(nil))
                action("calendar.badge.clock", "班级排课", ReferenceColor.blue, .teacherTasks)
            }
            .padding(.horizontal, 12)
            ReferenceCard {
                VStack(alignment: .leading, spacing: 8) {
                    ReferenceSectionTitle(title: "今日任务", trailing: "查看全部", action: { router.push(.teacherTasks) })
                    taskRow("16:30", "16:30 · 17:10", "一（6）班 测评任务", "待上课", ReferenceColor.green)
                    taskRow("17:20", "17:20 · 18:00", "体能提升班", "待上课", ReferenceColor.blue)
                }
            }
            .padding(.horizontal, 12)
            Button { router.push(.teacherTasks) } label: {
                Label("课后上传测评结果记录与照片", systemImage: "camera.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 9))
            }
            .padding(.horizontal, 12)
        }
    }

    private func taskRow(_ time: String, _ duration: String, _ title: String, _ state: String, _ color: Color) -> some View {
        Button { router.push(.teacherTasks) } label: {
            HStack {
                Text(time).font(.system(size: 12, weight: .bold)).foregroundStyle(color).frame(width: 34)
                VStack(alignment: .leading) {
                    Text(duration).font(.system(size: 8)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 11, weight: .bold))
                }
                Spacer()
                Text(state).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)任务")
    }

    private func count(_ title: String, _ value: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    Text(value).font(.system(size: 19, weight: .bold)).foregroundStyle(color)
                    Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)")
    }

    private func action(_ icon: String, _ title: String, _ color: Color, _ route: AppRoute) -> some View {
        Button { router.push(route) } label: { ReferenceAction(icon: icon, title: title, color: color) }
            .buttonStyle(.plain)
    }
}

struct TeacherClassBoardView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var dashboardAppeared = false
    @State private var actionMessage: String?
    @State private var selectedPeriod = 0
    private var classInfo: ClassInfo? { state.data?.classes.first(where: { $0.name == "三年级2班" }) }
    private var classStudents: [Student] { state.data?.students.filter { $0.className == "三年级2班" } ?? [] }
    private var measuredCount: Int { classStudents.filter { state.taskStatus(for: $0) == .completed }.count }
    private var riskCount: Int { classStudents.filter { ($0.totalScore ?? 35) < 25 || state.taskStatus(for: $0) == .review || state.taskStatus(for: $0) == .retest }.count }
    private var lowScoreCount: Int { classStudents.filter { ($0.totalScore ?? 35) < 25 }.count }
    private var reviewCount: Int { classStudents.filter { state.taskStatus(for: $0) == .review }.count }
    private var retestCount: Int { classStudents.filter { state.taskStatus(for: $0) == .retest }.count }
    private var processingCount: Int { classStudents.filter { [.checkedIn, .waiting, .testing].contains(state.taskStatus(for: $0)) }.count }
    private var completedCount: Int { classStudents.filter { state.taskStatus(for: $0) == .completed }.count }
    private var riskStudents: [Student] { classStudents.filter { (($0.totalScore ?? 35) < 25) || [.review, .retest].contains(state.taskStatus(for: $0)) } }
    private var completion: Double { classStudents.isEmpty ? 0 : Double(measuredCount) / Double(classStudents.count) }

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                HStack {
                    Button { router.pop() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("返回")
                    Spacer()
                    VStack(spacing: 1) {
                        Text("三年级2班 · 班级数据看板").font(.system(size: 14, weight: .bold))
                        Text("向上实验小学 · 三年级2班 · 共\(classStudents.count)人").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { router.push(.teacherMessages) } label: {
                        Image(systemName: "bell").overlay(alignment: .topTrailing) {
                            if state.unreadMessageCount > 0 { Circle().fill(.red).frame(width: 5, height: 5) }
                        }
                    }.buttonStyle(.plain).accessibilityLabel("消息通知")
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 8)

                HStack {
                    chip("本轮综合测评", selected: selectedPeriod == 0) { selectedPeriod = 0 }
                    chip("2026春季", selected: selectedPeriod == 1) { selectedPeriod = 1 }
                    Spacer()
                    Text("更新于 07-26 14:27").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)

                boardCard(title: "班级健康概览", trailing: "查看明细", action: { router.push(.studentList(classInfo)) }) {
                    HStack {
                        boardStat("班级人数", "\(classStudents.count)", "person.3.fill", ReferenceColor.blue) { router.push(.studentList(classInfo)) }
                        boardStat("已测评", "\(measuredCount)", "checkmark.circle.fill", ReferenceColor.green) { router.push(.teacherTasks) }
                        boardStat("测评率", "\(Int(completion * 100))%", "circle", ReferenceColor.green) { router.push(.teacherTasks) }
                        boardStat("待处理预警", "\(riskCount)", "exclamationmark.shield.fill", .red) { router.push(.reviewList) }
                    }
                }

                boardCard(title: "四维测评健康度", trailing: "健康明细", action: { router.push(.reviewList) }) {
                    HStack(spacing: 6) {
                        healthGauge("体质", ReferenceColor.blue, completion: completion) { router.push(.reviewList) }
                        healthGauge("心理", ReferenceColor.pink, completion: completion) { router.push(.reviewList) }
                        healthGauge("视力", ReferenceColor.green, completion: completion) { router.push(.reviewList) }
                        healthGauge("口腔", ReferenceColor.purple, completion: completion) { router.push(.reviewList) }
                    }
                }

                HStack(spacing: 7) {
                    compactBoardCard(title: "问题分布", trailing: "", action: { router.push(.riskStudents) }) {
                        VStack(spacing: 5) {
                            smallBar("低分", min(1, Double(lowScoreCount) / Double(max(1, classStudents.count))), ReferenceColor.blue, "\(lowScoreCount)人")
                            smallBar("待复核", min(1, Double(reviewCount) / Double(max(1, classStudents.count))), .orange, "\(reviewCount)人")
                            smallBar("待补测", min(1, Double(retestCount) / Double(max(1, classStudents.count))), ReferenceColor.purple, "\(retestCount)人")
                        }
                    }
                    compactBoardCard(title: "班级总评", trailing: "", action: { router.push(.reviewList) }) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().trim(from: 0.15, to: 0.92).stroke(AngularGradient(colors: [ReferenceColor.green, ReferenceColor.yellow, .red], center: .center), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                                Text("\(riskCount)").font(.system(size: 17, weight: .bold))
                            }
                            .frame(width: 54, height: 54)
                            VStack(alignment: .leading, spacing: 4) {
                                Label("待处理 \(riskCount)", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                                Label("处理中 \(processingCount)", systemImage: "circle.fill").foregroundStyle(ReferenceColor.yellow)
                                Label("已完成 \(completedCount)", systemImage: "checkmark.circle.fill").foregroundStyle(ReferenceColor.green)
                            }
                            .font(.system(size: 8, weight: .medium))
                        }
                    }
                }
                .padding(.horizontal, 12)

                boardCard(title: "测评平均完成趋势", trailing: "查看详情", action: { router.push(.teacherTasks) }) {
                    CompletionTrendChart()
                }

                boardCard(title: "重点关注学生", trailing: "查看全部", action: { router.push(.reviewList) }) {
                    if riskStudents.isEmpty {
                        Text("当前没有重点风险学生").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(Array(riskStudents.prefix(3))) { student in
                                Button {
                                    router.push(.report(student))
                                } label: {
                                    studentAlert(student.name, riskDetail(for: student), state.taskStatus(for: student).rawValue, riskColor(for: student))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("查看\(student.name)的风险报告")
                            }
                        }
                    }
                }

                HStack(spacing: 7) {
                    actionButton("推送班级通知", "bell.fill", ReferenceColor.blue) { router.push(.teacherMessages) }
                    actionButton("导出班级数据报告", "doc.text.fill", ReferenceColor.purple) { actionMessage = "班级数据报告已生成，可在消息通知中查看。" }
                    actionButton("批量发出预警", "exclamationmark.shield.fill", .red) { actionMessage = "已向待处理学生发送预警通知。" }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 10)
        }
        .background(ReferenceColor.canvas)
        .overlay {
            if state.loading || state.data == nil {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    LoadingStateView()
                }
            } else if classStudents.isEmpty {
                ZStack {
                    ReferenceColor.canvas.ignoresSafeArea()
                    EmptyStateView(title: "暂无班级数据", detail: "学生名单同步后，班级看板会自动更新。")
                }
            }
        }
        .navigationBarBackButtonHidden()
        .task {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.18)) {
                dashboardAppeared = true
            }
        }
        .alert("操作完成", isPresented: Binding(get: { actionMessage != nil }, set: { if !$0 { actionMessage = nil } })) {
            Button("知道了") { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text + "⌄")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(selected ? ReferenceColor.blue : ReferenceColor.navy)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? ReferenceColor.sky : .white, in: Capsule())
                .overlay(Capsule().stroke(ReferenceColor.blue.opacity(selected ? 0.35 : 0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func boardCard<Content: View>(title: String, trailing: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        ReferenceCard {
            VStack(alignment: .leading, spacing: 7) {
                ReferenceSectionTitle(title: title, trailing: trailing, action: action)
                content()
            }
        }
        .padding(.horizontal, 12)
    }

    private func compactBoardCard<Content: View>(title: String, trailing: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            ReferenceCard {
                VStack(alignment: .leading, spacing: 7) {
                    ReferenceSectionTitle(title: title, trailing: trailing)
                    content()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func boardStat(_ title: String, _ value: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(color)
                    Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(title)：\(value)")
    }

    private func healthGauge(_ title: String, _ color: Color, completion: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 9, weight: .bold))
                ZStack {
                    Circle().stroke(color.opacity(0.18), lineWidth: 5)
                    Circle().trim(from: 0, to: dashboardAppeared ? completion : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(completion * 100))%").font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                }
                .frame(width: 40, height: 40)
                Text("\(Int((1 - completion) * 100))%未完成").font(.system(size: 7)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(color.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(title)测评健康度")
    }

    private func smallBar(_ label: String, _ value: Double, _ color: Color, _ count: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 8)).frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: proxy.size.width * value, height: 5)
            }
            .frame(height: 5)
            Text(count).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    private func studentAlert(_ name: String, _ detail: String, _ state: String, _ color: Color) -> some View {
        HStack {
            Circle().fill(color.opacity(0.15)).frame(width: 20, height: 20).overlay(Text(String(name.prefix(1))).font(.system(size: 9, weight: .bold)).foregroundStyle(color))
            Text(name).font(.system(size: 9, weight: .bold)).frame(width: 42, alignment: .leading)
            Text(detail).font(.system(size: 8)).foregroundStyle(.secondary)
            Spacer()
            Text(state).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
        }
    }

    private func riskDetail(for student: Student) -> String {
        switch state.taskStatus(for: student) {
        case .review: return "测评结果待复核"
        case .retest: return "需要安排补测"
        default: return "综合得分偏低"
        }
    }

    private func riskColor(for student: Student) -> Color {
        switch state.taskStatus(for: student) {
        case .retest: return ReferenceColor.purple
        case .review: return .orange
        default: return .red
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 8, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

struct CompletionTrendChart: View {
    private let values: [Double] = [0.70, 0.76, 0.84, 0.90]
    private let labels = ["第1周", "第2周", "第3周", "本周"]
    @State private var draw = false

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                ZStack {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Divider().overlay(ReferenceColor.blue.opacity(0.10))
                            Spacer()
                        }
                    }
                    CompletionLine(values: values)
                        .trim(from: 0, to: draw ? 1 : 0)
                        .stroke(ReferenceColor.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(Array(values.enumerated()), id: \.offset) { item in
                        let x = proxy.size.width * CGFloat(item.offset) / CGFloat(values.count - 1)
                        let y = proxy.size.height * (1 - CGFloat(item.element))
                        Circle().fill(.white).frame(width: 7, height: 7)
                            .overlay(Circle().stroke(ReferenceColor.blue, lineWidth: 2))
                            .position(x: x, y: y)
                            .opacity(draw ? 1 : 0)
                        Text("\(Int(item.element * 100))%").font(.system(size: 7, weight: .bold)).foregroundStyle(ReferenceColor.blue)
                            .position(x: x, y: max(7, y - 10))
                            .opacity(draw ? 1 : 0)
                    }
                }
            }
            .frame(height: 48)
            HStack {
                ForEach(labels, id: \.self) { label in
                    Text(label).font(.system(size: 7)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
        .task { withAnimation(.easeOut(duration: 1.1)) { draw = true } }
    }
}

struct CompletionLine: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = rect.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
            let y = rect.height * (1 - CGFloat(value))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

private extension View {
    func roleChip(isSelected: Bool, selectedColor: Color) -> some View {
        self
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(isSelected ? Color.white : selectedColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? selectedColor : selectedColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
    }
}
struct TeacherClassesView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "我管理的班级", showsBack: true)
                ReferenceHeader(name: "李老师", school: "向上实验小学 · 三年级2班", initial: "李", avatarAsset: "TeacherAvatar")
                ReferenceSectionTitle(title: "我管理的班级", trailing: "负责 2 个班级").padding(.horizontal, 12)
                if state.loading || state.data == nil {
                    LoadingStateView()
                } else if let data = state.data, data.classes.isEmpty {
                    EmptyStateView(title: "暂无管理班级", detail: "学校分班后会自动同步到这里。")
                } else if let data = state.data {
                    ForEach(Array(data.classes.prefix(2))) { item in
                        let classStudents = data.students.filter { $0.className == item.name }
                        let completionRate = classStudents.isEmpty ? item.completionRate : Int((Double(classStudents.filter { state.taskStatus(for: $0) == .completed }.count) / Double(classStudents.count) * 100).rounded())
                        Button { router.push(.studentList(item)) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.system(size: 14, weight: .bold))
                                    Text("\(item.studentCount)人 · \(item.teacherName)").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(completionRate)%").font(.system(size: 17, weight: .bold)).foregroundStyle(ReferenceColor.green)
                                    Text("完成率").font(.system(size: 8)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
        .background(ReferenceColor.canvas)
    }
}

struct StudentListView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    let classInfo: ClassInfo?
    var body: some View {
        AppScaffold(title: classInfo?.name ?? "学生列表") {
            VStack(spacing: 8) {
                if state.loading || state.data == nil {
                    LoadingStateView()
                } else {
                    let students = state.data?.students.filter { classInfo == nil || $0.className == classInfo?.name } ?? []
                    if students.isEmpty {
                        EmptyStateView(title: "暂无学生数据", detail: "当前班级暂未同步学生名单。")
                    } else {
                        ForEach(students) { student in
                            StudentCard(student: student) { router.push(.report(student)) }
                        }
                    }
                }
            }
        }
    }
}

struct TeacherTasksView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "延时课程上传", showsBack: true)
                ReferenceHeader(name: "李老师", school: "向上实验小学 · 体育组", initial: "李", avatarAsset: "TeacherAvatar")
                ReferenceSectionTitle(title: "近日测评任务", trailing: "共 3 项任务").padding(.horizontal, 12)
                if state.loading || state.data == nil {
                    LoadingStateView()
                } else {
                    let tasks = state.data?.tasks ?? []
                    if tasks.isEmpty {
                        EmptyStateView(title: "暂无测评任务", detail: "新的任务发布后会在这里显示。")
                    } else {
                        ForEach(tasks) { task in
                            TestTaskCard(task: task) { router.push(.teacherTaskDetail(task)) }
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
        .background(ReferenceColor.canvas)
    }
}

struct TeacherTaskDetailView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    let task: TestTask
    @State private var selectedStudent: Student?
    var body: some View {
        let currentTask = state.data?.tasks.first(where: { $0.id == task.id }) ?? task
        AppScaffold(title: "任务详情") {
            VStack(spacing: 10) {
                TestTaskCard(task: currentTask, action: nil)
                Text("点击学生更新签到、测试、复核或补测状态；状态将保存在本机，等待场地端同步。")
                    .font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if state.loading || state.data == nil {
                    LoadingStateView()
                } else if let data = state.data, data.students.isEmpty {
                    EmptyStateView(title: "暂无任务学生", detail: "学生名单同步后可更新测评状态。")
                } else if let data = state.data {
                    let classNames = Set(currentTask.className.split(separator: "、").map(String.init))
                    let taskStudents = data.students.filter { $0.grade == currentTask.gradeName && classNames.contains($0.className) }
                    if taskStudents.isEmpty {
                        EmptyStateView(title: "暂无任务学生", detail: "该任务对应的年级或班级名单尚未同步。")
                    }
                    ForEach(taskStudents) { student in
                        TeacherStudentStatusRow(student: student, status: state.taskStatus(for: student)) { selectedStudent = student }
                    }
                }
            }
        }
        .sheet(item: $selectedStudent) { student in TaskStatusSheet(student: student, status: state.taskStatus(for: student)) }
    }
}

struct ReviewListView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var selectedStudent: Student?
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ParentPageNavigation(title: "预警中心", showsBack: true)
                ReferenceHeader(name: "李老师", school: "向上实验小学 · 三年级2班", initial: "李", avatarAsset: "TeacherAvatar")
                ReferenceSectionTitle(title: "预警中心", trailing: "待处理列表").padding(.horizontal, 12)
                if state.loading || state.data == nil {
                    LoadingStateView()
                } else {
                    let students = state.data?.students.filter { [.review, .retest, .absent].contains(state.taskStatus(for: $0)) } ?? []
                    Text("待处理 \(students.count) 人 · 点击可更新处理状态")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                    ForEach(students) { student in
                        TeacherStudentStatusRow(student: student, status: state.taskStatus(for: student)) { selectedStudent = student }
                            .padding(.horizontal, 12)
                        if let note = state.localFeatures.reviewNotes[student.id] {
                            Text("复核意见：\(note)")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
                        }
                    }
                    if students.isEmpty { EmptyStateView(title: "暂无待处理预警", detail: "待复核、待补测和缺席学生将在此显示。") }
                }
            }
        }
        .background(ReferenceColor.canvas)
        .sheet(item: $selectedStudent) { student in TaskStatusSheet(student: student, status: state.taskStatus(for: student), requiresReviewNote: true) }
    }
}

private struct TeacherStudentStatusRow: View {
    let student: Student
    let status: TaskStatus
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(student.name.prefix(1))).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).background(ReferenceColor.blue, in: Circle())
                VStack(alignment: .leading, spacing: 3) { Text(student.name).font(.system(size: 12, weight: .bold)); Text("\(student.grade) · \(student.className)").font(.system(size: 9)).foregroundStyle(.secondary) }
                Spacer()
                Text(status.rawValue).font(.system(size: 10, weight: .bold)).foregroundStyle(status.color).padding(.horizontal, 8).padding(.vertical, 4).background(status.color.opacity(0.12), in: Capsule())
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }.padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

private struct TaskStatusSheet: View {
    let student: Student
    let status: TaskStatus
    var requiresReviewNote = false
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reviewNote = ""
    @State private var validationMessage: String?
    var body: some View {
        NavigationStack {
            List {
                if requiresReviewNote {
                    Section("复核 / 补测处理意见") {
                        TextEditor(text: $reviewNote).frame(minHeight: 92)
                        Text("请说明证据核验结果、是否需要补测及后续处理。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let validationMessage { Text(validationMessage).font(.caption).foregroundStyle(.red) }
                    }
                }
                Section("处理结论") {
                    ForEach(TaskStatus.allCases, id: \.self) { item in
                        Button {
                            if requiresReviewNote && reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                validationMessage = "请先填写复核或补测处理意见。"
                                return
                            }
                            state.updateTaskStatus(for: student, status: item, reviewNote: reviewNote)
                            dismiss()
                        } label: {
                            HStack { Text(item.rawValue); Spacer(); if item == status { Image(systemName: "checkmark").foregroundStyle(ReferenceColor.blue) } }
                        }.foregroundStyle(item == status ? ReferenceColor.blue : ReferenceColor.navy)
                    }
                }
            }
            .navigationTitle("处理\(student.name)预警")
            .task { reviewNote = state.localFeatures.reviewNotes[student.id] ?? "" }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}

private extension TaskStatus {
    var color: Color {
        switch self { case .completed: ReferenceColor.green; case .review, .absent: .red; case .retest: .orange; case .testing: ReferenceColor.blue; default: .secondary }
    }
}
