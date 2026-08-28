import SwiftUI

struct TeacherClassCircleDashboard: View {
    @EnvironmentObject private var state: AppState
    @State private var composerShown = false
    @State private var selectedNotice: String?
    @State private var editingPost: ClassPostDraft?
    private var currentTeacherName: String { state.activeDisplayName }
    private var primaryClassName: String { state.managedTeacherClasses.first?.name ?? "我的班级" }
    var body: some View { ScrollView { VStack(spacing: 10) {
        ParentPageNavigation(title: "\(primaryClassName) · 班级圈")
        if !state.usesRemoteDataSource { ReferenceCard { VStack(alignment: .leading, spacing: 7) { HStack { Image(systemName: "megaphone.fill").foregroundStyle(ReferenceColor.blue); Text("班级公告").font(.system(size: 15, weight: .bold)); Spacer(); Button("全部公告 ›") { selectedNotice = "全部班级公告\n请家长于 9 月 12 日前完成孩子健康信息确认，并留意测评时间与场地安排。" }.font(.system(size: 16)).foregroundStyle(ReferenceColor.blue).buttonStyle(.plain) }; Button { selectedNotice = "秋季综合测评通知\n请家长于 9 月 12 日前完成孩子健康信息确认。测评当天请为孩子准备舒适运动服和饮水。" } label: { VStack(alignment: .leading, spacing: 4) { Text("秋季综合测评通知").font(.system(size: 16, weight: .bold)); Text("请家长于 9 月 12 日前完成孩子健康信息确认。") .font(.system(size: 16)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) } }.padding(.horizontal, AppTheme.pagePadding) }
        Button { composerShown = true } label: { Label("发布公告或班级动态", systemImage: "square.and.pencil").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white).background(ReferenceColor.blue, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).padding(.horizontal, AppTheme.pagePadding)
        ReferenceSectionTitle(title: "班级动态", trailing: state.classPostsNextCursor == nil ? "本班最新" : "可继续加载").padding(.horizontal, AppTheme.pagePadding)
        if state.usesRemoteDataSource, state.classPostsLoading, state.localFeatures.classPosts.isEmpty {
            LoadingStateView().padding(.vertical, 20)
        } else if state.usesRemoteDataSource, let error = state.classPostsError, state.localFeatures.classPosts.isEmpty {
            ErrorStateView(message: error) { Task { await state.loadClassPosts() } }.padding(.horizontal, AppTheme.pagePadding)
        } else if state.localFeatures.classPosts.isEmpty {
            EmptyStateView(title: "暂无班级动态", detail: "发布班级通知或动态后，会按审核状态显示在这里。").padding(.horizontal, AppTheme.pagePadding)
        } else {
            ForEach(state.localFeatures.classPosts) { post in
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.displayName ?? post.author).font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.blue)
                                Text("\(post.status.taskStatusLabel) · \(post.moderationStatus == "approved" || post.moderationStatus == "published" ? "已审核" : "待审核")")
                                    .font(.system(size: 16)).foregroundStyle(post.status == .failed ? .red : .secondary)
                            }
                            Spacer()
                            Menu {
                                // Ownership is service-provided. A teacher may
                                // moderate/pin class content, but cannot edit
                                // or delete another publisher's post.
                                let canEditOrDelete = post.ownedByCurrentUser || post.postID == nil
                                if canEditOrDelete { Button("编辑") { editingPost = post } }
                                if state.teacherHasCapability("PUBLISH_CLASS_NOTICE"), post.postID != nil {
                                    Button((post.isPinned ?? false) ? "取消置顶" : "置顶") { Task { await state.setClassPostPinnedCommand(post, pinned: !(post.isPinned ?? false)) } }
                                }
                                Button("举报") { Task { await state.reportClassPostCommand(post) } }
                                if canEditOrDelete {
                                    Button("删除", role: .destructive) { Task { await state.deleteClassPostCommand(post) } }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(ReferenceColor.blue)
                            }.accessibilityLabel("管理班级动态")
                        }
                        Text(post.content).font(.system(size: 16)).foregroundStyle(ReferenceColor.navy).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if post.isPinned == true { Label("置顶", systemImage: "pin.fill").foregroundStyle(ReferenceColor.yellow) }
                            if post.reportStatus == "reported" { Label("已举报", systemImage: "exclamationmark.bubble.fill").foregroundStyle(.orange) }
                            Spacer()
                            Text(post.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }.font(.system(size: 16))
                    }
                }.padding(.horizontal, AppTheme.pagePadding)
            }
            if state.usesRemoteDataSource, let cursor = state.classPostsNextCursor {
                Button { Task { await state.loadClassPosts(cursor: cursor) } } label: {
                    Text(state.classPostsLoading ? "加载中…" : "加载更多动态").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                }.buttonStyle(.bordered).disabled(state.classPostsLoading).padding(.horizontal, AppTheme.pagePadding)
            } else if state.usesRemoteDataSource, let error = state.classPostsError {
                ErrorStateView(message: error) { Task { await state.loadClassPosts(cursor: state.classPostsNextCursor) } }.padding(.horizontal, AppTheme.pagePadding)
            }
        }
        if !state.usesRemoteDataSource { ForEach([("今日体能活动", "孩子们完成了侧向滑步与障碍跳练习，表现很棒！"), ("家校共育小贴士", "建议每天安排 20 分钟亲子运动时间。")], id: \.0) { item in Button { selectedNotice = "\(item.0)\n\(item.1)" } label: { ReferenceCard { HStack { VStack(alignment: .leading, spacing: 5) { Text(item.0).font(.system(size: 16, weight: .bold)); Text(item.1).font(.system(size: 16)).foregroundStyle(.secondary); Text("\(currentTeacherName) · 今天").font(.system(size: 16)).foregroundStyle(ReferenceColor.green) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(.secondary) } }.padding(.horizontal, AppTheme.pagePadding) }.buttonStyle(.plain).accessibilityLabel("查看\(item.0)") } }
    }.padding(.bottom, 10) }
        .background(ReferenceColor.canvas)
        .overlay {
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
                ZStack { ReferenceColor.canvas.ignoresSafeArea(); LoadingStateView() }
            } else if state.data?.students.isEmpty == true {
                EmptyStateView(title: "暂无班级动态", detail: "班级名单同步后，公告和家校动态会显示在这里。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            }
        }
        .sheet(isPresented: $composerShown) { PublishClassPostSheet(author: currentTeacherName) }
        .sheet(item: $editingPost) { post in PublishClassPostSheet(author: post.author, editingPost: post) }
        .sheet(item: Binding(get: { selectedNotice.map(TeacherNoticeSheetItem.init) }, set: { selectedNotice = $0?.value })) { item in TeacherNoticeDetailSheet(value: item.value, author: currentTeacherName) }
        .task { if state.usesRemoteDataSource { await state.loadClassPosts() } }
    }
}

private struct TeacherNoticeSheetItem: Identifiable {
    let value: String
    var id: String { value }
}

private struct TeacherNoticeDetailSheet: View {
    let value: String
    let author: String
    @Environment(\.dismiss) private var dismiss
    private var title: String { value.components(separatedBy: "\n").first ?? "班级动态" }
    private var detail: String { value.components(separatedBy: "\n").dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("\(author) · 今天", systemImage: "person.crop.circle.fill")
                        .font(.subheadline).foregroundStyle(ReferenceColor.blue)
                    Text(detail.isEmpty ? "暂无补充说明。" : detail)
                        .font(.body).foregroundStyle(ReferenceColor.navy)
                    Label("本班可见", systemImage: "lock.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

/// Shared visual treatment for the teacher message list and its details.
func messagePresentation(for item: MessageItem) -> (icon: String, color: Color) {
    if item.category == "系统" { return ("gearshape.fill", ReferenceColor.purple) }
    if item.title.contains("体质") { return ("exclamationmark.triangle.fill", .red) }
    if item.title.contains("视力") { return ("eye.fill", ReferenceColor.green) }
    if item.title.contains("口腔") { return ("mouth.fill", ReferenceColor.purple) }
    return ("building.2.fill", ReferenceColor.blue)
}

struct TeacherDashboard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var isSportsTeacher: Bool
    private var canUseSportsWorkbench: Bool { state.teacherHasCapability("UPLOAD_AFTER_SCHOOL_COURSE") }
    private var managedClasses: [ClassInfo] { state.managedTeacherClasses }
    private var classStudents: [Student] {
        let classIDs = Set(managedClasses.map(\.id))
        return state.data?.students.filter { student in
            guard let classID = student.classID else { return false }
            return classIDs.contains(classID)
        } ?? []
    }
    private var measuredCount: Int { classStudents.filter { state.taskStatus(for: $0) == .completed }.count }
    private func officialReport(for student: Student) -> DiagnosisReport? {
        guard state.hasPublishedSchoolReport(for: student) else { return nil }
        return state.visibleReport(for: student)
    }
    private var lowScoreStudentIDs: Set<String> {
        Set(classStudents.compactMap(officialReport(for:)).filter { $0.requiresFollowUp }.map(\.student.id))
    }
    private var highScoreStudentIDs: Set<String> {
        Set(classStudents.compactMap(officialReport(for:)).filter { $0.isComplete && $0.totalScore >= AssessmentScoreRules.highTotalThreshold && !$0.requiresReview }.map(\.student.id))
    }
    private var riskCount: Int { classStudents.filter { lowScoreStudentIDs.contains($0.id) || state.taskStatus(for: $0) == .review || state.taskStatus(for: $0) == .retest }.count }
    private var reduceMotion: Bool { state.localFeatures.settings.reduceMotion || systemReduceMotion }
    private var actionGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppTheme.cardSpacing), count: dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact ? 2 : 4)
    }
    private var metricGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.cardSpacing) {
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
            if let error = state.error, state.data == nil {
                ErrorStateView(message: error) { Task { await state.refreshDashboard() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ReferenceColor.canvas)
            } else if state.loading || state.data == nil {
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
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: isSportsTeacher)
    }

    private var teacherHeader: some View {
        HStack(spacing: 9) {
            Image("TeacherAvatar").resizable().scaledToFill()
                .frame(width: 43, height: 43).background(ReferenceColor.sky, in: Circle()).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(state.activeDisplayName).font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.navy)
                Text(state.profile?.schoolName ?? "学校").font(.system(size: 15)).foregroundStyle(.secondary)
                Text(isSportsTeacher ? "延时课程工作台" : "负责 \(managedClasses.count) 个授权班级")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(ReferenceColor.green)
            }
            Spacer()
            Button { router.push(.teacherMessages) } label: { Image(systemName: "bell").font(.system(size: 16, weight: .medium)).foregroundStyle(ReferenceColor.navy)
                .overlay(alignment: .topTrailing) { if state.unreadMessageCount > 0 { Circle().fill(.red).frame(width: 5, height: 5).offset(x: 2, y: -2) } }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("消息通知").accessibilityHint("打开消息中心")
        }
        .padding(.horizontal, AppTheme.pagePadding).padding(.vertical, 9)
        // Keep the role workbench consistent with the rest of the iOS chrome:
        // this is a root header, not a white content card.  Native material
        // gives it the requested Apple glass treatment while preserving the
        // reference layout over the light dashboard canvas.
        .background { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) { Rectangle().fill(ReferenceColor.navy.opacity(0.08)).frame(height: 0.5) }
    }

    private var teacherSwitch: some View {
        HStack(spacing: 8) {
            roleSwitchButton("班级工作台", "person.3.fill", selected: !isSportsTeacher, color: ReferenceColor.blue) { isSportsTeacher = false }
            // The two choices are account roles, not task-health states. Keep
            // both in the blue identity family used by the reference teacher
            // panel; green remains reserved for completed/healthy data below.
            if canUseSportsWorkbench { roleSwitchButton("延时课程", "figure.run", selected: isSportsTeacher, color: ReferenceColor.blue) { isSportsTeacher = true } }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.pagePadding)
    }

    private func roleSwitchButton(_ title: String, _ icon: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            if reduceMotion { var transaction = Transaction(); transaction.animation = nil; withTransaction(transaction) { action() } }
            else { withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { action() } }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(selected ? .white : color)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.controlHeight)
                .background(selected ? color : color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous).stroke(color.opacity(selected ? 0 : 0.16), lineWidth: 1))
        }
    }

    private var classTeacherContent: some View {
        VStack(spacing: AppTheme.cardSpacing) {
            Label("仅显示当前账号已授权的班级数据", systemImage: "lock.shield.fill")
                .font(.system(size: AppTheme.captionSize, weight: .medium))
                .foregroundStyle(AppTheme.muted)
            ReferenceCard {
                VStack(spacing: 10) {
                    ReferenceSectionTitle(title: "班级健康概览", trailing: "查看班级看板", action: { router.push(.teacherClassBoard) })
                    LazyVGrid(columns: metricGridColumns, spacing: 8) {
                        count("班级人数", "\(classStudents.count)", "person.3.fill", ReferenceColor.blue) { router.push(.studentList(nil)) }
                        count("已测评", "\(measuredCount)", "checkmark.circle.fill", ReferenceColor.green) { router.push(.studentList(nil)) }
                        count("测评率", "\(classStudents.isEmpty ? 0 : measuredCount * 100 / classStudents.count)%", "circle", ReferenceColor.green) { router.push(.teacherClassBoard) }
                        count("待处理预警", "\(riskCount)", "exclamationmark.shield.fill", .red) { router.push(.reviewList) }
                    }
                    Divider()
                    HStack {
                        Text("问题分布（人）").font(.system(size: 16, weight: .bold))
                        Spacer()
                        Text("低分 \(lowScoreStudentIDs.count) · 表现良好 \(highScoreStudentIDs.count) · 待复核 \(classStudents.filter { state.taskStatus(for: $0) == .review }.count) · 待补测 \(classStudents.filter { state.taskStatus(for: $0) == .retest }.count)")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            LazyVGrid(columns: actionGridColumns, spacing: AppTheme.cardSpacing) {
                action("rectangle.stack.fill", "班级看板", ReferenceColor.blue, .teacherClassBoard)
                action("exclamationmark.triangle.fill", "预警中心", .red, .reviewList)
                action("person.3.fill", "学生列表", ReferenceColor.green, .studentList(nil))
                action("person.2.fill", "待分班学生", .orange, .unassignedStudents)
                action("figure.run", "查看延时课", .teal, .teacherTasks)
                action("medal.fill", "优秀学生评选", ReferenceColor.purple, .outstandingStudents)
                // Keep class management reachable from the main teacher
                // workbench, rather than duplicating the student-list shortcut.
                action("person.badge.plus", "班级管理", .orange, .teacherClasses)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            if state.usesRemoteDataSource {
                EmptyStateView(title: "暂无今日任务", detail: "学校排期同步后会显示可处理任务.")
                    .padding(.horizontal, AppTheme.pagePadding)
            } else {
                ReferenceCard {
                    VStack(alignment: .leading, spacing: 7) {
                        ReferenceSectionTitle(title: "今日任务", trailing: "查看全部", action: { router.push(.teacherTasks) })
                        teacherTaskRow("16:30–17:10 · \(managedClasses.first?.name ?? "班级")综合测评", "进行中", ReferenceColor.green)
                        teacherTaskRow("17:20–18:00 · 体能提升课", "待上传", .orange)
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
        }
    }

    private func teacherTaskRow(_ title: String, _ status: String, _ color: Color) -> some View {
        Button { router.push(.teacherTasks) } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(color)
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(ReferenceColor.navy).lineLimit(2)
                Spacer()
                Text(status).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(.secondary)
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
                    Text("已完成 \(completed) / \(total) 人    \(Int(progress * 100))%").font(.system(size: 16, weight: .bold)).foregroundStyle(ReferenceColor.green)
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            HStack(spacing: 8) {
                action("person.3.sequence.fill", "学生管理", ReferenceColor.green, .studentList(nil))
                action("calendar.badge.clock", "班级排课", ReferenceColor.blue, .teacherTasks)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            ReferenceCard {
                VStack(alignment: .leading, spacing: 8) {
                    ReferenceSectionTitle(title: "今日任务", trailing: "查看全部", action: { router.push(.teacherTasks) })
                    let tasks = Array((state.data?.tasks ?? []).prefix(2))
                    if tasks.isEmpty {
                        Text("暂无已排期任务").font(.system(size: 16)).foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            let time = task.date.split(separator: " ").last.map(String.init) ?? "待排期"
                            taskRow(time, task.date, "\(task.className) · \(task.title)", task.completedCount >= task.totalCount ? "已完成" : "待上课", index == 0 ? ReferenceColor.green : ReferenceColor.blue)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            Button { router.push(.teacherTasks) } label: {
                Label("课后上传测评结果记录与照片", systemImage: "camera.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 9))
            }
            .padding(.horizontal, AppTheme.pagePadding)
        }
    }

    private func taskRow(_ time: String, _ duration: String, _ title: String, _ state: String, _ color: Color) -> some View {
        Button { router.push(.teacherTasks) } label: {
            HStack {
                Text(time).font(.system(size: 16, weight: .bold)).foregroundStyle(color).frame(width: 34)
                VStack(alignment: .leading) {
                    Text(duration).font(.system(size: 16)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 16, weight: .bold))
                }
                Spacer()
                Text(state).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)任务")
    }

    private func count(_ title: String, _ value: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)")
    }

    private func action(_ icon: String, _ title: String, _ color: Color, _ route: AppRoute) -> some View {
        Button { router.push(route) } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ReferenceColor.navy)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous).stroke(AppTheme.divider.opacity(0.8), lineWidth: 0.75))
        }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
    }
}
